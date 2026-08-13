import { compressImage } from "../compressImage";

const LIMITS = { maxWidth: 1000, quality: 0.7 };

function mockManipulator(saveAsync: () => Promise<unknown>) {
  jest.doMock("expo-image-manipulator", () => ({
    SaveFormat: { JPEG: "jpeg" },
    ImageManipulator: {
      manipulate: () => ({
        resize: () => ({ renderAsync: async () => ({ saveAsync }) }),
      }),
    },
  }));
}

describe("compressImage", () => {
  beforeEach(() => {
    jest.resetModules();
  });

  it("returns the re-encoded JPEG when the native module is present", async () => {
    mockManipulator(async () => ({
      uri: "file:///small.jpg",
      width: 1000,
      height: 750,
    }));
    const { compressImage: compress } = require("../compressImage");

    await expect(
      compress("file:///huge.png", "image/png", LIMITS),
    ).resolves.toEqual({ uri: "file:///small.jpg", mimeType: "image/jpeg" });
  });

  // The devotee's picture matters more than the storage saving, so every
  // failure path below has to keep the original rather than lose the upload.
  it("keeps the original when the native module is missing", async () => {
    jest.doMock("expo-image-manipulator", () => {
      throw new Error("Cannot find native module 'ExpoImageManipulator'");
    });
    const { compressImage: compress } = require("../compressImage");

    await expect(
      compress("file:///huge.png", "image/png", LIMITS),
    ).resolves.toEqual({ uri: "file:///huge.png", mimeType: "image/png" });
  });

  it("keeps the original when compressing throws", async () => {
    mockManipulator(async () => {
      throw new Error("out of memory");
    });
    const { compressImage: compress } = require("../compressImage");

    await expect(
      compress("file:///huge.jpg", "image/jpeg", LIMITS),
    ).resolves.toEqual({ uri: "file:///huge.jpg", mimeType: "image/jpeg" });
  });

  it("keeps the original when the result has no file behind it", async () => {
    mockManipulator(async () => ({ width: 10, height: 10 }));
    const { compressImage: compress } = require("../compressImage");

    await expect(
      compress("file:///huge.jpg", "image/jpeg", LIMITS),
    ).resolves.toEqual({ uri: "file:///huge.jpg", mimeType: "image/jpeg" });
  });

  it("is exported and callable without a manipulator mock in place", () => {
    expect(typeof compressImage).toBe("function");
  });
});
