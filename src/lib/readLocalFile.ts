import { File } from "expo-file-system";

/**
 * Reads a picked file off the device as raw bytes.
 *
 * `fetch(uri).arrayBuffer()` looks like the obvious way to do this, but in
 * React Native `fetch` is a polyfill and its `arrayBuffer()` goes through a
 * Blob and a FileReader. For a `file://` URI that path is unreliable — it
 * yields an empty buffer or throws outright depending on the platform, which
 * is what made picture uploads fail with nothing useful to show the devotee.
 * `expo-file-system` reads the file natively instead.
 */
export async function readLocalFileBytes(uri: string): Promise<Uint8Array> {
  const file = new File(uri);
  if (!file.exists) {
    throw new Error("That file is no longer on this device.");
  }
  const bytes = await file.bytes();
  if (bytes.byteLength === 0) {
    throw new Error("That file came back empty.");
  }
  return bytes;
}
