/**
 * Shapes returned by the daily darshan migration (…0078_daily_darshan.sql).
 * Kept in step with `list_daily_darshan()`, `latest_daily_darshan()` and
 * `publish_daily_darshan()`.
 */

/** A darshan photograph goes to the message-images bucket, so it is picked and
 * uploaded by the messaging code and carries its shape. */
export type { PickedMessageImage } from "../messaging/types";

/**
 * The temple asked for "up to 5 pictures". The server enforces the same bound,
 * so the composer refusing a sixth is a courtesy rather than the only guard.
 */
export const MAX_DARSHAN_IMAGES = 5;

/**
 * One photograph within a day's darshan, as the server returns it inside the
 * day's `images` array — already ordered by `position`.
 *
 * Both captions are nullable because the row is a photograph first: a picture
 * whose dresser nobody wrote down is still darshan, and hiding it would be
 * worse than showing it unattributed.
 */
export type DarshanImage = {
  imageUrl: string;
  deity: string | null;
  dressedBy: string | null;
  position: number;
};

/** One row of `list_daily_darshan()` / `latest_daily_darshan()`. */
export type DailyDarshan = {
  id: string;
  /** A Chicago calendar day ("2026-08-26"), not an instant. */
  darshan_on: string;
  note: string | null;
  /** Always an array — `[]` rather than null when a day has no pictures. */
  images: DarshanImage[];
  /** Null once the devotee who posted it has left the congregation. */
  posted_by: string | null;
  posted_by_name: string | null;
  posted_by_photo_url: string | null;
  created_at: string;
  /** The server's answer, never re-derived here. */
  can_delete: boolean;
};

/**
 * A photograph being composed. It keeps its own upload outcome so a publish
 * that failed on picture four does not make the temple choose the other four
 * again — `uploadedUrl` survives the failure and the retry skips it.
 */
export type DarshanDraftImage = {
  /** Client-only, stable across re-picks so React and the strip agree. */
  id: string;
  uri: string;
  mimeType: string;
  fileName: string;
  deity: string;
  dressedBy: string;
  /** Set once this one photograph has reached storage. */
  uploadedUrl: string | null;
  status: DarshanUploadStatus;
  /** Why this one failed, in words the devotee can act on. */
  error: string | null;
};

export type DarshanUploadStatus =
  | "waiting"
  | "uploading"
  | "uploaded"
  | "failed";

/** What `publish_daily_darshan` is given: the pairing, once every URL exists. */
export type PublishDarshanImage = {
  imageUrl: string;
  deity: string | null;
  dressedBy: string | null;
  position: number;
};

export type PublishDailyDarshanInput = {
  /** "YYYY-MM-DD", Chicago's calendar day. */
  darshanOn: string;
  note: string | null;
  images: PublishDarshanImage[];
};

/**
 * A Deity the temple can be showing, as migration 0080's catalogue returns it.
 *
 * The name is the whole of it as far as this app is concerned: `publish_daily_darshan`
 * records the Deities as text on the picture, so the catalogue is a list to
 * choose from rather than a foreign key. That is deliberate — a temple that
 * dresses someone not yet in the catalogue must still be able to post the day.
 */
export type DarshanDeity = {
  /** The catalogue row, where there is one. Absent for a built-in fallback. */
  id: string | null;
  name: string;
};

/**
 * What the picker offers before 0080 has been applied — the three the temple
 * named, in the order they named them. A picker with nothing in it is worse
 * than no picker, and an error where a list belongs reads as a broken app.
 */
export const FALLBACK_DARSHAN_DEITIES: readonly string[] = [
  "Kisora Kisori",
  "Gaura Nitai",
  "Jagannath Baldev Subhadra",
];
