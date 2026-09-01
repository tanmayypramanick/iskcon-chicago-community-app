/**
 * Shapes returned by the announcements migration
 * (202608040040_announcements.sql). Kept in step with `list_announcements()`
 * and the `announcements` table.
 */

/** An announcement photo goes to the message-images bucket, so it is picked
 * and uploaded by the messaging code and carries its shape. */
export type { PickedMessageImage } from "../messaging/types";

/**
 * One row of `list_announcements()`.
 *
 * All four schedule fields are independent and any of them may be null: a
 * notice can have an end and no beginning, a day and no clock, or neither. The
 * dates are Chicago calendar days ("2026-08-15") and the times are Chicago
 * wall-clock ("18:30:00"); neither is an instant.
 */
export type Announcement = {
  id: string;
  title: string;
  body: string;
  image_url: string | null;
  /** Null once the devotee who posted it has left the congregation. */
  posted_by: string | null;
  posted_by_name: string | null;
  posted_by_photo_url: string | null;
  starts_on: string | null;
  ends_on: string | null;
  starts_at: string | null;
  ends_at: string | null;
  created_at: string;
  /** The server's answer, never re-derived here. */
  can_delete: boolean;
  like_count: number;
  /** Removed comments are not counted, so a card never promises more than the
   * thread shows. */
  comment_count: number;
  liked_by_me: boolean;
  /**
   * What sort of notice this is, so the card can dress it. "birthday" draws
   * the greeting frame. Decided when it is posted and never inferred from the
   * wording, which whoever posts it is free to rewrite.
   */
  kind: "general" | "birthday";
};

/** One row of `list_announcement_likes()`, newest first. */
export type AnnouncementLike = {
  devotee_id: string;
  name: string;
  photo_url: string | null;
  created_at: string;
};

/**
 * One row of `list_announcement_comments()`. The rows arrive in render order —
 * top-level comments oldest first, each immediately followed by its own replies
 * — so the thread is grouped, never re-sorted, on the phone.
 */
export type AnnouncementComment = {
  id: string;
  /** Null for a top-level comment. The thread is exactly one level deep. */
  parent_comment_id: string | null;
  author_id: string;
  author_name: string;
  author_photo_url: string | null;
  /** Null once removed: the words are not returned to anybody. */
  body: string | null;
  created_at: string;
  deleted_at: string | null;
  /** Live replies only. */
  reply_count: number;
  /** The server's answer, never re-derived here. False once removed. */
  can_remove: boolean;
  /** Client-only: written into the thread before the server has answered. */
  pending?: boolean;
};

/** What `add_announcement_comment` and `delete_announcement_comment` hand
 * back: the bare table row, without the author's name or `can_remove`. */
export type AnnouncementCommentRow = {
  id: string;
  announcement_id: string;
  parent_comment_id: string | null;
  author_id: string;
  body: string;
  created_at: string;
  deleted_at: string | null;
  deleted_by: string | null;
};

export type AddAnnouncementCommentInput = {
  announcementId: string;
  body: string;
  /** The top-level comment being answered, or null for a new comment. */
  parentCommentId?: string | null;
};

/** What `create_announcement` and `delete_announcement` hand back: the bare
 * table row, without the poster's name or `can_delete`. */
export type AnnouncementRow = {
  id: string;
  title: string;
  body: string;
  image_url: string | null;
  posted_by: string | null;
  starts_on: string | null;
  ends_on: string | null;
  starts_at: string | null;
  ends_at: string | null;
  created_at: string;
  updated_at: string;
};

export type CreateAnnouncementInput = {
  title: string;
  body: string;
  /**
   * Must already be in one of the app's own buckets — message-images for a
   * photo picked in the composer, devotee-photos for a birthday greeting's
   * picture. The server checks, and refuses anything else so that this column
   * cannot become a tracking pixel.
   */
  imageUrl?: string | null;
  /** "YYYY-MM-DD" */
  startsOn?: string | null;
  endsOn?: string | null;
  /** "HH:MM:SS" */
  startsAt?: string | null;
  endsAt?: string | null;
  /** "birthday" makes the card draw the greeting frame. */
  kind?: "general" | "birthday";
};
