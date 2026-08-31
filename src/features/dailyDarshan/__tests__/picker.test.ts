/// <reference types="jest" />

import * as ImagePicker from "expo-image-picker";

import { pickDarshanImages } from "../api";
import { MAX_DARSHAN_IMAGES } from "../types";

jest.mock("../../../lib/supabase", () => ({ getSupabaseClient: jest.fn() }));

// The compressor reaches expo-image-manipulator, which has no native side in a
// test runner. It degrades to "upload the original" for real; pinning it here
// keeps this test about the cap and not about the encoder.
jest.mock("../../../lib/compressImage", () => ({
  compressImage: jest.fn(async (uri: string, mimeType: string) => ({
    uri,
    mimeType,
  })),
  MESSAGE_IMAGE_LIMITS: { maxWidth: 1400, quality: 0.7 },
}));

jest.mock("expo-image-picker", () => ({
  requestMediaLibraryPermissionsAsync: jest.fn(),
  requestCameraPermissionsAsync: jest.fn(),
  launchImageLibraryAsync: jest.fn(),
  launchCameraAsync: jest.fn(),
}));

const picker = jest.mocked(ImagePicker);

function asset(name: string) {
  return { uri: `file:///${name}`, mimeType: "image/jpeg", fileName: name };
}

beforeEach(() => {
  jest.clearAllMocks();
  picker.requestMediaLibraryPermissionsAsync.mockResolvedValue({
    granted: true,
  } as never);
  picker.requestCameraPermissionsAsync.mockResolvedValue({
    granted: true,
  } as never);
});

describe("choosing the day's pictures", () => {
  it("asks the library for no more than the day has room for", async () => {
    picker.launchImageLibraryAsync.mockResolvedValue({
      canceled: false,
      assets: [asset("a.jpg"), asset("b.jpg")],
    } as never);

    await pickDarshanImages("library", 3);

    expect(picker.launchImageLibraryAsync).toHaveBeenCalledWith(
      expect.objectContaining({
        allowsMultipleSelection: true,
        selectionLimit: 3,
      }),
    );
  });

  it("holds the cap even when the gallery hands back more than it was asked for", async () => {
    // Some Android gallery apps ignore selectionLimit outright, and a sixth
    // picture would be refused by the server after five uploads had been paid
    // for on temple wifi.
    picker.launchImageLibraryAsync.mockResolvedValue({
      canceled: false,
      assets: Array.from({ length: 9 }, (_, index) => asset(`${index}.jpg`)),
    } as never);

    const picked = await pickDarshanImages("library", MAX_DARSHAN_IMAGES);

    expect(picked).toHaveLength(MAX_DARSHAN_IMAGES);
    expect(picked.map((image) => image.fileName)).toEqual([
      "0.jpg",
      "1.jpg",
      "2.jpg",
      "3.jpg",
      "4.jpg",
    ]);
  });

  it("does not open the picker at all once five are chosen", async () => {
    expect(await pickDarshanImages("library", 0)).toEqual([]);
    expect(picker.launchImageLibraryAsync).not.toHaveBeenCalled();
    expect(picker.requestMediaLibraryPermissionsAsync).not.toHaveBeenCalled();
  });

  it("takes one photograph at a time from the camera", async () => {
    picker.launchCameraAsync.mockResolvedValue({
      canceled: false,
      assets: [asset("shot.jpg")],
    } as never);

    await pickDarshanImages("camera", 4);

    expect(picker.launchCameraAsync).toHaveBeenCalledWith(
      expect.objectContaining({ allowsMultipleSelection: false, selectionLimit: 1 }),
    );
  });

  it("returns nothing when the devotee backs out", async () => {
    picker.launchImageLibraryAsync.mockResolvedValue({
      canceled: true,
      assets: null,
    } as never);

    expect(await pickDarshanImages("library", 5)).toEqual([]);
  });

  it("says what to do when photo access was refused", async () => {
    picker.requestMediaLibraryPermissionsAsync.mockResolvedValue({
      granted: false,
    } as never);

    await expect(pickDarshanImages("library", 5)).rejects.toThrow(
      /Allow photo access/,
    );
  });
});
