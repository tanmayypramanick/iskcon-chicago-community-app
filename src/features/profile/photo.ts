import {
  compressImage,
  PROFILE_PHOTO_LIMITS,
} from "../../lib/compressImage";
import { readLocalFileBytes } from "../../lib/readLocalFile";
import { getSupabaseClient } from "../../lib/supabase";

/**
 * expo-image-picker is a native module. Two things have to be true for it to
 * work: the JavaScript has to be loaded late (importing at the top level
 * crashes the whole bundle on a binary built before the dependency existed),
 * and the native side has to actually be in that binary.
 *
 * `await import()` is not enough on its own. Metro compiles it to a
 * synchronous require, and the missing-native-module error is raised while the
 * module body evaluates — which escaped the promise and reached the devotee as
 * a red screen instead of a message they could act on. A plain require inside
 * try/catch does catch it.
 */
const REBUILD_MESSAGE =
  "This copy of the app was built before photos were added. Rebuild it (npm run ios / npm run android) and try again.";

type ImagePickerModule = typeof import("expo-image-picker");

function loadImagePicker(): ImagePickerModule {
  let candidate: unknown;
  try {
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    candidate = require("expo-image-picker");
  } catch {
    throw new Error(REBUILD_MESSAGE);
  }

  // Metro's interop sometimes nests the real module under `default`.
  const picker = (candidate as { default?: unknown })?.default ?? candidate;
  const api = picker as Partial<ImagePickerModule> | undefined;
  if (
    !api ||
    typeof api.launchImageLibraryAsync !== "function" ||
    typeof api.launchCameraAsync !== "function" ||
    typeof api.requestCameraPermissionsAsync !== "function" ||
    typeof api.requestMediaLibraryPermissionsAsync !== "function"
  ) {
    throw new Error(REBUILD_MESSAGE);
  }
  return api as ImagePickerModule;
}

const BUCKET = "devotee-photos";

export { photoGuidelines } from "./guidelines";

export type PickedPhoto = {
  uri: string;
  mimeType: string;
  fileName: string;
};

function extensionFor(mimeType: string) {
  if (mimeType.includes("png")) return "png";
  if (mimeType.includes("webp")) return "webp";
  return "jpg";
}

/**
 * Square crop keeps every avatar circle consistent and keeps the upload small.
 * Returns null when the devotee cancels or declines the permission.
 */
export async function pickDevoteePhoto(
  source: "library" | "camera",
): Promise<PickedPhoto | null> {
  const ImagePicker = loadImagePicker();
  const permission =
    source === "camera"
      ? await ImagePicker.requestCameraPermissionsAsync()
      : await ImagePicker.requestMediaLibraryPermissionsAsync();
  if (!permission.granted) {
    throw new Error(
      source === "camera"
        ? "Allow camera access to take your profile photo."
        : "Allow photo access to choose your profile photo.",
    );
  }

  const options: import("expo-image-picker").ImagePickerOptions = {
    mediaTypes: ["images"],
    allowsEditing: true,
    aspect: [1, 1],
    quality: 0.8,
  };
  const result =
    source === "camera"
      ? await ImagePicker.launchCameraAsync(options)
      : await ImagePicker.launchImageLibraryAsync(options);

  const asset = result.canceled ? null : result.assets[0];
  if (!asset) return null;

  // Compressed at the point of picking rather than at upload, so the size the
  // devotee is committing to is the size that actually leaves the phone.
  const shrunk = await compressImage(
    asset.uri,
    asset.mimeType ?? "image/jpeg",
    PROFILE_PHOTO_LIMITS,
  );
  return {
    uri: shrunk.uri,
    mimeType: shrunk.mimeType,
    fileName: asset.fileName ?? `photo.${extensionFor(shrunk.mimeType)}`,
  };
}

/**
 * Uploads to `devotee-photos/<user id>/…` and stores the public URL on the
 * profile. The path is timestamped so a replacement never serves a stale
 * cached image, and the previous file is removed afterwards.
 */
export async function uploadDevoteePhoto(userId: string, photo: PickedPhoto) {
  const supabase = getSupabaseClient();
  const extension = extensionFor(photo.mimeType);
  const path = `${userId}/${Date.now()}.${extension}`;

  const body = await readLocalFileBytes(photo.uri);
  if (body.byteLength > 5 * 1024 * 1024) {
    throw new Error("Please choose a photo smaller than 5 MB.");
  }

  const { error: uploadError } = await supabase.storage
    .from(BUCKET)
    .upload(path, body, { contentType: photo.mimeType, upsert: true });
  if (uploadError) throw uploadError;

  const {
    data: { publicUrl },
  } = supabase.storage.from(BUCKET).getPublicUrl(path);

  const { error: profileError } = await supabase
    .from("users")
    .update({ photo_url: publicUrl })
    .eq("id", userId);
  if (profileError) throw profileError;

  await removeOtherPhotos(userId, path);
  return publicUrl;
}

async function removeOtherPhotos(userId: string, keepPath: string) {
  const supabase = getSupabaseClient();
  const { data } = await supabase.storage.from(BUCKET).list(userId);
  const stale = (data ?? [])
    .map((file) => `${userId}/${file.name}`)
    .filter((path) => path !== keepPath);
  if (stale.length) await supabase.storage.from(BUCKET).remove(stale);
}

export async function removeDevoteePhoto(userId: string) {
  const supabase = getSupabaseClient();
  const { error } = await supabase
    .from("users")
    .update({ photo_url: null })
    .eq("id", userId);
  if (error) throw error;

  const { data } = await supabase.storage.from(BUCKET).list(userId);
  const paths = (data ?? []).map((file) => `${userId}/${file.name}`);
  if (paths.length) await supabase.storage.from(BUCKET).remove(paths);
}
