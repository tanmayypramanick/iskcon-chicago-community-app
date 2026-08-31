/// <reference types="jest" />

import { accessRoles } from "../../access/model";
import { uploadMessageImage } from "../../messaging/api";
import {
  toPublishImages,
  uploadDarshanDrafts,
  uploadFailureMessage,
} from "../upload";
import type { DarshanDraftImage } from "../types";

jest.mock("../../messaging/api", () => ({
  uploadMessageImage: jest.fn(),
}));

// canPostDailyDarshan lives beside the query hooks, and importing them reaches
// the Supabase module. Nothing here builds a client.
jest.mock("../../../lib/supabase", () => ({ getSupabaseClient: jest.fn() }));

// eslint-disable-next-line @typescript-eslint/no-require-imports
const { canPostDailyDarshan } = require("../hooks") as typeof import("../hooks");

const mockUpload = jest.mocked(uploadMessageImage);

function draft(
  id: string,
  deity: string,
  dressedBy = "",
): DarshanDraftImage {
  return {
    id,
    uri: `file:///${id}.jpg`,
    mimeType: "image/jpeg",
    fileName: `${id}.jpg`,
    deity,
    dressedBy,
    uploadedUrl: null,
    status: "waiting",
    error: null,
  };
}

/** The composer's own state, held the way the screen holds it, so a retry in
 * this test sees exactly what a devotee's second tap would see. */
function composer(initial: DarshanDraftImage[]) {
  let drafts = initial;
  return {
    get drafts() {
      return drafts;
    },
    onImageState(id: string, patch: Partial<DarshanDraftImage>) {
      drafts = drafts.map((row) => (row.id === id ? { ...row, ...patch } : row));
    },
  };
}

beforeEach(() => jest.clearAllMocks());

describe("who may post the day's darshan", () => {
  it("offers the composer to exactly the three roles the temple named", () => {
    expect(accessRoles.filter(canPostDailyDarshan)).toEqual([
      "president",
      "tech",
      "core",
    ]);
  });

  it("offers it to no ordinary devotee", () => {
    expect(canPostDailyDarshan("devotee")).toBe(false);
    expect(canPostDailyDarshan("volunteer")).toBe(false);
  });
});

describe("sending the day's photographs", () => {
  it("sends them one at a time and reports each one as it moves", async () => {
    mockUpload.mockImplementation(
      async (_userId, image) => `https://temple.example/${image.fileName}`,
    );
    const seen: string[] = [];
    const state = composer([draft("one", "Radha Govinda"), draft("two", "Gaura Nitai")]);

    const result = await uploadDarshanDrafts("head-1", state.drafts, (id, patch) => {
      if (patch.status) seen.push(`${id}:${patch.status}`);
      state.onImageState(id, patch);
    });

    expect(seen).toEqual([
      "one:uploading",
      "one:uploaded",
      "two:uploading",
      "two:uploaded",
    ]);
    expect(result.failures).toBe(0);
    expect(result.urls.get("two")).toBe("https://temple.example/two.jpg");
  });

  it("keeps the pictures that landed when one fails, and re-sends only that one", async () => {
    const state = composer([
      draft("one", "Sri Sri Radha Govinda", "Rukmini devi dasi"),
      draft("two", "Sri Sri Gaura Nitai", "Bhakta Arjun"),
      draft("three", "Srila Prabhupada"),
    ]);
    mockUpload.mockImplementation(async (_userId, image) => {
      if (image.fileName === "two.jpg") throw new Error("Network request failed");
      return `https://temple.example/${image.fileName}`;
    });

    const first = await uploadDarshanDrafts(
      "head-1",
      state.drafts,
      state.onImageState,
    );

    expect(first.failures).toBe(1);
    expect(state.drafts.map((row) => row.status)).toEqual([
      "uploaded",
      "failed",
      "uploaded",
    ]);
    // The wording a dropped connection deserves, not "Network request failed".
    expect(state.drafts[1].error).toMatch(/connection/i);
    expect(state.drafts[0].uploadedUrl).toBe("https://temple.example/one.jpg");
    expect(uploadFailureMessage(first.failures)).toMatch(
      /One picture could not be sent/,
    );

    mockUpload.mockClear();
    mockUpload.mockResolvedValue("https://temple.example/two.jpg");

    const second = await uploadDarshanDrafts(
      "head-1",
      state.drafts,
      state.onImageState,
    );

    // Four photographs the temple already paid for are not paid for twice.
    expect(mockUpload).toHaveBeenCalledTimes(1);
    expect(mockUpload.mock.calls[0][1].fileName).toBe("two.jpg");
    expect(second.failures).toBe(0);

    // And the captions still belong to the pictures they were written under.
    expect(toPublishImages(state.drafts, second.urls)).toEqual([
      {
        imageUrl: "https://temple.example/one.jpg",
        deity: "Sri Sri Radha Govinda",
        dressedBy: "Rukmini devi dasi",
        position: 0,
      },
      {
        imageUrl: "https://temple.example/two.jpg",
        deity: "Sri Sri Gaura Nitai",
        dressedBy: "Bhakta Arjun",
        position: 1,
      },
      {
        // Nobody wrote down who dressed Them, so nobody is claimed to have.
        imageUrl: "https://temple.example/three.jpg",
        deity: "Srila Prabhupada",
        dressedBy: null,
        position: 2,
      },
    ]);
  });

  it("counts every picture that did not make it", async () => {
    mockUpload.mockRejectedValue(new Error("Network request failed"));
    const state = composer([draft("one", "A"), draft("two", "B")]);

    const result = await uploadDarshanDrafts(
      "head-1",
      state.drafts,
      state.onImageState,
    );

    expect(result.failures).toBe(2);
    expect(uploadFailureMessage(2)).toMatch(/2 pictures could not be sent/);
  });
});
