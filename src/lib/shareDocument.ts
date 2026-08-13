import { File, Paths } from "expo-file-system";
import * as Sharing from "expo-sharing";

/**
 * Hands a document — a newsletter PDF, a story attachment — to the phone's
 * share sheet, from which a devotee can open it in a reader, save it to Files,
 * or send it on.
 *
 * The sibling of sharePicture, and separate from it on purpose: that one
 * defaults every unknown extension to JPEG and declares `public.image`, which
 * on iOS offers a PDF to the photo library and to nothing that could read it.
 * The two differ only in those defaults, but those defaults are the whole job.
 */
function extensionFor(url: string) {
  const clean = url.split("?")[0];
  const dot = clean.lastIndexOf(".");
  const found = dot === -1 ? "" : clean.slice(dot + 1).toLowerCase();
  return /^[a-z0-9]{2,5}$/.test(found) ? found : "";
}

const MIME_BY_EXTENSION: Record<string, string> = {
  pdf: "application/pdf",
  doc: "application/msword",
  docx: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
};

const UTI_BY_EXTENSION: Record<string, string> = {
  pdf: "com.adobe.pdf",
  doc: "com.microsoft.word.doc",
  docx: "org.openxmlformats.wordprocessingml.document",
};

export async function shareDocument(
  url: string,
  fileStem = "document",
  dialogTitle = "Save this file",
) {
  if (!(await Sharing.isAvailableAsync())) {
    throw new Error("This device cannot open or save files.");
  }

  const extension = extensionFor(url);
  const mimeType = MIME_BY_EXTENSION[extension] ?? "application/octet-stream";
  // `public.data` is the root of every file type on iOS, so an unrecognised
  // extension still reaches Files rather than nothing at all.
  const uti = UTI_BY_EXTENSION[extension] ?? "public.data";

  if (url.startsWith("file:")) {
    await Sharing.shareAsync(url, { mimeType, dialogTitle, UTI: uti });
    return;
  }

  // A name the devotee will recognise in whatever they open it with: the share
  // sheet carries the cache file's own name through to the destination.
  const target = new File(
    Paths.cache,
    extension ? `${fileStem}.${extension}` : fileStem,
  );
  const saved = await File.downloadFileAsync(url, target, { idempotent: true });
  await Sharing.shareAsync(saved.uri, { mimeType, dialogTitle, UTI: uti });
}
