/// <reference types="jest" />

import {
  clearSignedUrlCache,
  getSignedUrl,
  parseStorageRef,
} from "../storageUrl";

const mockCreateSignedUrls = jest.fn();
const mockFrom = jest.fn(() => ({ createSignedUrls: mockCreateSignedUrls }));

jest.mock("../supabase", () => ({
  getSupabaseClient: () => ({ storage: { from: mockFrom } }),
}));

beforeEach(() => {
  clearSignedUrlCache();
  mockCreateSignedUrls.mockReset();
  mockFrom.mockClear();
});

describe("parseStorageRef", () => {
  it("reads the bucket and path out of a stored public URL", () => {
    expect(
      parseStorageRef(
        "https://abc.supabase.co/storage/v1/object/public/message-images/user-1/1234.jpg",
      ),
    ).toEqual({ bucket: "message-images", path: "user-1/1234.jpg" });
  });

  it("reads a devotee photo the same way", () => {
    expect(
      parseStorageRef(
        "https://abc.supabase.co/storage/v1/object/public/devotee-photos/uid-9/face.png",
      ),
    ).toEqual({ bucket: "devotee-photos", path: "uid-9/face.png" });
  });

  it("drops a query string, which the object path never has", () => {
    expect(
      parseStorageRef(
        "https://abc.supabase.co/storage/v1/object/public/devotee-photos/uid/face.png?t=1",
      ),
    ).toEqual({ bucket: "devotee-photos", path: "uid/face.png" });
  });

  it("accepts a bare bucket/path, so what gets stored may change later", () => {
    expect(parseStorageRef("newsletter-files/uid/aug.pdf")).toEqual({
      bucket: "newsletter-files",
      path: "uid/aug.pdf",
    });
  });

  it("leaves things that are not Storage references alone", () => {
    // A picked local file, an absolute URL elsewhere, and nothing at all —
    // each must render as-is rather than be mangled into a bucket.
    expect(parseStorageRef("file:///var/tmp/picked.jpg")).toBeNull();
    expect(parseStorageRef("https://iskconchicago.com/logo.png")).toBeNull();
    expect(parseStorageRef("data:image/png;base64,AAA")).toBeNull();
    expect(parseStorageRef(null)).toBeNull();
    expect(parseStorageRef("")).toBeNull();
    expect(parseStorageRef("   ")).toBeNull();
  });
});

describe("getSignedUrl", () => {
  const photo = (n: number) =>
    `https://abc.supabase.co/storage/v1/object/public/devotee-photos/uid-${n}/face.png`;

  it("mints a signed URL for a stored reference", async () => {
    mockCreateSignedUrls.mockResolvedValue({
      data: [{ path: "uid-1/face.png", signedUrl: "https://signed/1" }],
      error: null,
    });
    await expect(getSignedUrl(photo(1))).resolves.toBe("https://signed/1");
    expect(mockFrom).toHaveBeenCalledWith("devotee-photos");
  });

  it("asks once for one object however many callers want it", async () => {
    mockCreateSignedUrls.mockResolvedValue({
      data: [{ path: "uid-1/face.png", signedUrl: "https://signed/1" }],
      error: null,
    });

    const [a, b, c] = await Promise.all([
      getSignedUrl(photo(1)),
      getSignedUrl(photo(1)),
      getSignedUrl(photo(1)),
    ]);

    expect([a, b, c]).toEqual([
      "https://signed/1",
      "https://signed/1",
      "https://signed/1",
    ]);
    expect(mockCreateSignedUrls).toHaveBeenCalledTimes(1);
  });

  it("batches a screenful of different faces into one round trip", async () => {
    mockCreateSignedUrls.mockResolvedValue({
      data: [
        { path: "uid-1/face.png", signedUrl: "https://signed/1" },
        { path: "uid-2/face.png", signedUrl: "https://signed/2" },
        { path: "uid-3/face.png", signedUrl: "https://signed/3" },
      ],
      error: null,
    });

    const urls = await Promise.all([
      getSignedUrl(photo(1)),
      getSignedUrl(photo(2)),
      getSignedUrl(photo(3)),
    ]);

    expect(urls).toEqual([
      "https://signed/1",
      "https://signed/2",
      "https://signed/3",
    ]);
    // The whole point: one request for the list, not one per face.
    expect(mockCreateSignedUrls).toHaveBeenCalledTimes(1);
    expect(mockCreateSignedUrls).toHaveBeenCalledWith(
      ["uid-1/face.png", "uid-2/face.png", "uid-3/face.png"],
      expect.any(Number),
    );
  });

  it("serves the second ask from cache without a second round trip", async () => {
    mockCreateSignedUrls.mockResolvedValue({
      data: [{ path: "uid-1/face.png", signedUrl: "https://signed/1" }],
      error: null,
    });

    await getSignedUrl(photo(1));
    await getSignedUrl(photo(1));

    expect(mockCreateSignedUrls).toHaveBeenCalledTimes(1);
  });

  it("gives back null rather than a broken URL when signing fails", async () => {
    mockCreateSignedUrls.mockResolvedValue({ data: null, error: new Error("nope") });
    await expect(getSignedUrl(photo(7))).resolves.toBeNull();
  });

  it("gives back null when the request throws outright", async () => {
    mockCreateSignedUrls.mockRejectedValue(new Error("offline"));
    await expect(getSignedUrl(photo(8))).resolves.toBeNull();
  });

  it("does not cache a failure, so the next mount tries again", async () => {
    mockCreateSignedUrls.mockResolvedValueOnce({ data: null, error: new Error("x") });
    await expect(getSignedUrl(photo(9))).resolves.toBeNull();

    mockCreateSignedUrls.mockResolvedValueOnce({
      data: [{ path: "uid-9/face.png", signedUrl: "https://signed/9" }],
      error: null,
    });
    await expect(getSignedUrl(photo(9))).resolves.toBe("https://signed/9");
  });

  it("passes a non-Storage value straight through untouched", async () => {
    await expect(getSignedUrl("file:///tmp/local.jpg")).resolves.toBe(
      "file:///tmp/local.jpg",
    );
    expect(mockCreateSignedUrls).not.toHaveBeenCalled();
  });

  it("keeps two buckets apart", async () => {
    mockCreateSignedUrls.mockImplementation((paths: string[]) => ({
      data: paths.map((path) => ({ path, signedUrl: `https://signed/${path}` })),
      error: null,
    }));

    await Promise.all([
      getSignedUrl(photo(1)),
      getSignedUrl(
        "https://abc.supabase.co/storage/v1/object/public/message-images/uid-1/a.jpg",
      ),
    ]);

    expect(mockFrom).toHaveBeenCalledWith("devotee-photos");
    expect(mockFrom).toHaveBeenCalledWith("message-images");
    expect(mockCreateSignedUrls).toHaveBeenCalledTimes(2);
  });
});
