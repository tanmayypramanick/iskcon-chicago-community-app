import { uploadMessageImage } from "../messaging/api";
import { errorMessage } from "../services/format";
import type { DarshanDraftImage, PublishDarshanImage } from "./types";

export type DarshanUploadResult = {
  /** Draft id → the URL that picture now has in storage. */
  urls: Map<string, string>;
  /** How many pictures did not make it. */
  failures: number;
};

/**
 * Five photographs, sent one at a time.
 *
 * They go up in a queue on purpose. Temple wifi carrying five full-size
 * pictures at once finishes all of them slowly and says nothing along the way;
 * in a queue, each one either lands or does not, and the strip above the
 * composer can show which. `onImageState` is how it finds out.
 *
 * A picture that has already landed is skipped, and its URL is written back on
 * to the draft — so a devotee whose fourth picture failed taps Post again and
 * re-sends the fourth, not all five.
 *
 * Kept apart from React Query deliberately: this is the part with the
 * interesting behaviour, and it is worth being able to test it without a query
 * client, a component tree or a clock.
 */
export async function uploadDarshanDrafts(
  userId: string,
  images: readonly DarshanDraftImage[],
  onImageState: (id: string, patch: Partial<DarshanDraftImage>) => void,
): Promise<DarshanUploadResult> {
  const urls = new Map<string, string>();
  let failures = 0;

  for (const image of images) {
    if (image.uploadedUrl) {
      urls.set(image.id, image.uploadedUrl);
      continue;
    }
    onImageState(image.id, { status: "uploading", error: null });
    try {
      const url = await uploadMessageImage(userId, image);
      urls.set(image.id, url);
      onImageState(image.id, {
        status: "uploaded",
        uploadedUrl: url,
        error: null,
      });
    } catch (caught) {
      failures += 1;
      onImageState(image.id, {
        status: "failed",
        error: errorMessage(caught, "This picture could not be sent."),
      });
    }
  }

  return { urls, failures };
}

/** What to tell a devotee who has four of five pictures in storage. */
export function uploadFailureMessage(failures: number) {
  return failures === 1
    ? "One picture could not be sent. Tap Post again to try that one — the others are already saved."
    : `${failures} pictures could not be sent. Tap Post again to try them — the rest are already saved.`;
}

/**
 * The captions, paired with the URLs their pictures ended up at.
 *
 * Position is the order the temple arranged, renumbered from zero, so the
 * gallery reads the pictures in the order they were chosen. An empty caption
 * becomes null rather than "": a name nobody wrote is absent, and the gallery
 * draws an absent caption differently from a blank one.
 */
export function toPublishImages(
  images: readonly DarshanDraftImage[],
  urls: ReadonlyMap<string, string>,
): PublishDarshanImage[] {
  return images.map((image, index) => ({
    imageUrl: urls.get(image.id) as string,
    deity: image.deity.trim() || null,
    dressedBy: image.dressedBy.trim() || null,
    position: index,
  }));
}
