/// <reference types="jest" />

import { getSupabaseClient } from "../../../lib/supabase";
import {
  fetchDailyDarshan,
  fetchDarshanDeities,
  fetchLatestDailyDarshan,
  publishDailyDarshan,
} from "../api";
import { MAX_DARSHAN_IMAGES } from "../types";

jest.mock("../../../lib/supabase", () => ({
  getSupabaseClient: jest.fn(),
}));

const mockGetSupabaseClient = jest.mocked(getSupabaseClient);

function withRpc(result: { data?: unknown; error?: unknown }) {
  const rpc = jest
    .fn()
    .mockResolvedValue({ data: result.data ?? null, error: result.error ?? null });
  mockGetSupabaseClient.mockReturnValue({ rpc } as never);
  return rpc;
}

function image(deity: string, dressedBy: string | null, position: number) {
  return {
    imageUrl: `https://temple.example/${position}.jpg`,
    deity,
    dressedBy,
    position,
  };
}

describe("publishing a day of darshan", () => {
  beforeEach(() => jest.clearAllMocks());

  it("sends each picture with the deity and the devotee who dressed Them", async () => {
    const rpc = withRpc({ data: "darshan-1" });

    await publishDailyDarshan({
      darshanOn: "2026-08-26",
      note: "Jhulan Yatra",
      images: [
        image("Sri Sri Radha Govinda", "Rukmini devi dasi", 0),
        image("Sri Sri Gaura Nitai", "Bhakta Arjun", 1),
      ],
    });

    // The pairing is what the temple asked for: each picture carries its own
    // Deities and its own dresser, and the two never come apart.
    expect(rpc).toHaveBeenCalledWith("publish_daily_darshan", {
      p_darshan_on: "2026-08-26",
      p_note: "Jhulan Yatra",
      p_images: [
        {
          imageUrl: "https://temple.example/0.jpg",
          deity: "Sri Sri Radha Govinda",
          dressedBy: "Rukmini devi dasi",
          position: 0,
        },
        {
          imageUrl: "https://temple.example/1.jpg",
          deity: "Sri Sri Gaura Nitai",
          dressedBy: "Bhakta Arjun",
          position: 1,
        },
      ],
    });
  });

  it("renumbers positions from the order it was given", async () => {
    const rpc = withRpc({ data: "darshan-2" });

    await publishDailyDarshan({
      darshanOn: "2026-08-26",
      note: null,
      images: [
        image("Radha Govinda", null, 7),
        image("Gaura Nitai", null, 2),
      ],
    });

    const sent = rpc.mock.calls[0][1].p_images as { position: number }[];
    expect(sent.map((row) => row.position)).toEqual([0, 1]);
  });

  it("refuses a sixth picture without spending the request", async () => {
    const rpc = withRpc({ data: "darshan-3" });
    const tooMany = Array.from({ length: MAX_DARSHAN_IMAGES + 1 }, (_, index) =>
      image(`Deity ${index}`, null, index),
    );

    await expect(
      publishDailyDarshan({
        darshanOn: "2026-08-26",
        note: null,
        images: tooMany,
      }),
    ).rejects.toThrow(/Up to 5 photographs/);
    expect(rpc).not.toHaveBeenCalled();
  });

  it("refuses a day with no pictures at all", async () => {
    const rpc = withRpc({ data: null });

    await expect(
      publishDailyDarshan({ darshanOn: "2026-08-26", note: null, images: [] }),
    ).rejects.toThrow(/at least one/i);
    expect(rpc).not.toHaveBeenCalled();
  });

  it("surfaces a refusal from the server", async () => {
    withRpc({
      error: { message: "Only a Community Head may post darshan.", code: "P0001" },
    });

    await expect(
      publishDailyDarshan({
        darshanOn: "2026-08-26",
        note: null,
        images: [image("Radha Govinda", null, 0)],
      }),
    ).rejects.toEqual(
      expect.objectContaining({
        message: "Only a Community Head may post darshan.",
      }),
    );
  });
});

describe("reading the gallery", () => {
  beforeEach(() => jest.clearAllMocks());

  it("returns a day's pictures in position order, whatever order they arrive", async () => {
    withRpc({
      data: [
        {
          id: "darshan-1",
          darshan_on: "2026-08-26",
          note: null,
          images: [
            { imageUrl: "b.jpg", deity: "Gaura Nitai", dressedBy: null, position: 1 },
            { imageUrl: "a.jpg", deity: "Radha Govinda", dressedBy: "Mira", position: 0 },
          ],
          can_delete: false,
        },
      ],
    });

    const [day] = await fetchDailyDarshan();
    expect(day.images.map((row) => row.imageUrl)).toEqual(["a.jpg", "b.jpg"]);
    expect(day.images[0]).toMatchObject({
      deity: "Radha Govinda",
      dressedBy: "Mira",
    });
  });

  it("never hands a screen a picture with no URL to draw", async () => {
    withRpc({
      data: [
        {
          id: "darshan-1",
          darshan_on: "2026-08-26",
          images: [
            { imageUrl: "  ", deity: "Radha Govinda", position: 0 },
            { imageUrl: "real.jpg", deity: "Gaura Nitai", position: 1 },
          ],
        },
        // A day whose images column came back null rather than an empty array.
        { id: "darshan-2", darshan_on: "2026-08-25", images: null },
      ],
    });

    const days = await fetchDailyDarshan();
    expect(days[0].images).toHaveLength(1);
    expect(days[1].images).toEqual([]);
  });

  it("reads a day quietly when the migration has not been applied yet", async () => {
    // A red error where a quiet empty gallery belongs reads as a broken app.
    withRpc({ error: { code: "PGRST202", message: "function does not exist" } });
    await expect(fetchDailyDarshan()).resolves.toEqual([]);

    withRpc({ error: { code: "PGRST202", message: "function does not exist" } });
    await expect(fetchLatestDailyDarshan()).resolves.toBeNull();
  });

  it("still raises a real failure rather than pretending the temple is empty", async () => {
    withRpc({ error: { code: "P0001", message: "Sign in to see darshan." } });
    await expect(fetchDailyDarshan()).rejects.toEqual(
      expect.objectContaining({ message: "Sign in to see darshan." }),
    );
  });

  it("takes the Home card's day from either shape the function can return", async () => {
    // latest_daily_darshan returns a table, so PostgREST hands back an array of
    // one; a scalar-shaped answer must not leave the card blank either.
    withRpc({
      data: [{ id: "darshan-1", darshan_on: "2026-08-26", images: [] }],
    });
    await expect(fetchLatestDailyDarshan()).resolves.toMatchObject({
      id: "darshan-1",
    });

    withRpc({ data: { id: "darshan-2", darshan_on: "2026-08-25", images: [] } });
    await expect(fetchLatestDailyDarshan()).resolves.toMatchObject({
      id: "darshan-2",
    });

    withRpc({ data: [] });
    await expect(fetchLatestDailyDarshan()).resolves.toBeNull();
  });
});

describe("the Deities to choose between", () => {
  beforeEach(() => jest.clearAllMocks());

  it("offers the temple's catalogue in the order the server gave it", async () => {
    const rpc = withRpc({
      data: [
        { id: "deity-1", name: "Kisora Kisori", display_order: 10 },
        { id: "deity-2", name: "Gaura Nitai", display_order: 20 },
        // The same Deity twice would draw the same chip twice.
        { id: "deity-3", name: "Gaura Nitai", display_order: 30 },
      ],
    });

    await expect(fetchDarshanDeities()).resolves.toEqual([
      { id: "deity-1", name: "Kisora Kisori" },
      { id: "deity-2", name: "Gaura Nitai" },
    ]);
    // display_order is the altar order; re-sorting here would throw it away.
    expect(rpc).toHaveBeenCalledWith("list_temple_deities", {});
  });

  it("falls back to the three the temple named when 0080 has not been applied", async () => {
    // A picker with nothing in it stops a day being posted at all, and a red
    // error where a list belongs reads as a broken app.
    for (const code of ["PGRST202", "42883", "PGRST205"]) {
      withRpc({ error: { code, message: "function does not exist" } });
      await expect(fetchDarshanDeities()).resolves.toEqual([
        { id: null, name: "Kisora Kisori" },
        { id: null, name: "Gaura Nitai" },
        { id: null, name: "Jagannath Baldev Subhadra" },
      ]);
    }
  });

  it("falls back the same way for a catalogue that exists but is empty", async () => {
    withRpc({ data: [] });
    await expect(fetchDarshanDeities()).resolves.toEqual([
      { id: null, name: "Kisora Kisori" },
      { id: null, name: "Gaura Nitai" },
      { id: null, name: "Jagannath Baldev Subhadra" },
    ]);
  });

  it("still raises a real refusal rather than quietly showing the fallback", async () => {
    withRpc({ error: { code: "P0001", message: "Sign in to see the Deities." } });
    await expect(fetchDarshanDeities()).rejects.toEqual(
      expect.objectContaining({ message: "Sign in to see the Deities." }),
    );
  });
});
