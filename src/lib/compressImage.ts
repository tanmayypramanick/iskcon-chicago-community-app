/**
 * Shrinking a picked photo before it is uploaded.
 *
 * A modern phone camera produces a 3–8 MB image several thousand pixels wide.
 * Nothing in this app ever displays one larger than a phone screen, so the
 * extra pixels are paid for twice — once in the temple's storage quota, and
 * again in every devotee's mobile data each time the picture is opened.
 * Re-encoding at display size typically removes 80–90% of the bytes with no
 * difference anyone can see on a phone.
 */

type Manipulated = { uri: string; width: number; height: number };

type ManipulatorModule = {
  ImageManipulator: {
    manipulate: (uri: string) => {
      resize: (size: { width?: number | null; height?: number | null }) => {
        renderAsync: () => Promise<{
          saveAsync: (options: {
            compress?: number;
            format?: string;
          }) => Promise<Manipulated>;
        }>;
      };
    };
  };
  SaveFormat: { JPEG: string };
};

/**
 * Metro turns a dynamic import into a synchronous require, so a module that
 * throws while evaluating escapes a try/catch around `await import`. Requiring
 * it directly is the only form that can actually be caught — which matters
 * here, because a missing native module must degrade to "upload the original"
 * rather than lose the devotee's picture.
 */
function loadManipulator(): ManipulatorModule | null {
  try {
    const candidate = require("expo-image-manipulator") as unknown;
    const api = ((candidate as { default?: unknown })?.default ??
      candidate) as Partial<ManipulatorModule> | undefined;
    if (typeof api?.ImageManipulator?.manipulate !== "function") return null;
    if (typeof api?.SaveFormat?.JPEG !== "string") return null;
    return api as ManipulatorModule;
  } catch {
    return null;
  }
}

export type CompressedImage = {
  uri: string;
  mimeType: string;
};

/**
 * Returns the picture re-encoded as a JPEG no wider than `maxWidth`, or the
 * original untouched if it is already small enough or the native module is
 * unavailable. Never throws: a picture that will not compress is still worth
 * uploading at full size.
 *
 * The result is always a JPEG, so callers must use the returned `mimeType`
 * rather than the one the picker reported — a PNG saved under a `.png` name
 * with JPEG bytes inside would fail to render for everyone.
 */
export async function compressImage(
  uri: string,
  mimeType: string,
  { maxWidth, quality }: { maxWidth: number; quality: number },
): Promise<CompressedImage> {
  const original = { uri, mimeType };
  const manipulator = loadManipulator();
  if (!manipulator) return original;

  try {
    const rendered = await manipulator.ImageManipulator.manipulate(uri)
      // Only a width is given so the height follows the original ratio. The
      // native resize never scales up, so a picture already narrower than
      // this is left at its own size.
      .resize({ width: maxWidth })
      .renderAsync();
    const saved = await rendered.saveAsync({
      compress: quality,
      format: manipulator.SaveFormat.JPEG,
    });
    if (!saved?.uri) return original;
    return { uri: saved.uri, mimeType: "image/jpeg" };
  } catch {
    return original;
  }
}

/**
 * An avatar is never drawn larger than 112pt, so even a retina screen needs
 * nothing beyond a few hundred pixels.
 */
export const PROFILE_PHOTO_LIMITS = { maxWidth: 720, quality: 0.7 } as const;

/**
 * A chat picture is drawn at 220pt in the thread and full-screen when tapped,
 * so it is kept larger than an avatar but still far below camera resolution.
 */
export const MESSAGE_IMAGE_LIMITS = { maxWidth: 1400, quality: 0.7 } as const;
