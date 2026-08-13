import { File, Paths } from "expo-file-system";
import * as Sharing from "expo-sharing";

/**
 * Hands a picture to the phone's share sheet, from which a devotee can save it
 * to their gallery, send it on, or file it anywhere else.
 *
 * Deliberately the share sheet rather than expo-media-library: writing straight
 * to the gallery needs a native module this binary does not carry, so it would
 * mean a rebuild before anybody could use it.
 */
function extensionFor(url: string) {
  const clean = url.split("?")[0];
  const dot = clean.lastIndexOf(".");
  const found = dot === -1 ? "" : clean.slice(dot + 1).toLowerCase();
  return /^[a-z0-9]{2,5}$/.test(found) ? found : "jpg";
}

const MIME_BY_EXTENSION: Record<string, string> = {
  jpg: "image/jpeg",
  jpeg: "image/jpeg",
  png: "image/png",
  gif: "image/gif",
  webp: "image/webp",
  heic: "image/heic",
};

export async function sharePicture(url: string, fileStem = "picture") {
  if (!(await Sharing.isAvailableAsync())) {
    throw new Error("This device cannot share pictures.");
  }

  // A picture still uploading is already a local file; only a remote one has
  // to be pulled down before the share sheet can reach it.
  if (url.startsWith("file:")) {
    await Sharing.shareAsync(url, { dialogTitle: "Save this picture" });
    return;
  }

  const extension = extensionFor(url);
  const target = new File(Paths.cache, `${fileStem}.${extension}`);
  const saved = await File.downloadFileAsync(url, target, { idempotent: true });
  await Sharing.shareAsync(saved.uri, {
    mimeType: MIME_BY_EXTENSION[extension] ?? "image/jpeg",
    dialogTitle: "Save this picture",
    UTI: "public.image",
  });
}
