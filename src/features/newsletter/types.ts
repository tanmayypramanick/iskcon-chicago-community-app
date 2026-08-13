/**
 * Shapes returned by the newsletter migration (202608040045_newsletter.sql).
 *
 * Two halves. Reading an issue is open to every devotee; posting one belongs to
 * the President, the Tech Admin, and anyone they have appointed an editor. That
 * appointment is a grant rather than a role, so an editor may be an ordinary
 * devotee — which is why every permission here travels on the row as
 * `can_manage` / `can_delete` / `can_revoke` and is never re-derived from the
 * viewer's role.
 */

/** A story photo goes to the message-images bucket, so it is picked and
 * uploaded by the messaging code and carries its shape. */
export type { PickedMessageImage } from "../messaging/types";

/** The table's own ceiling, enforced again in the UI so a devotee is stopped
 * while choosing rather than after sending. */
export const MAX_STORY_PHOTOS = 5;

/** One row of `list_newsletters()`, newest month first. */
export type Newsletter = {
  id: string;
  title: string;
  /** A Chicago calendar date pinned to the first of the month, "2026-08-01". */
  month: string;
  file_url: string;
  cover_image_url: string | null;
  notes: string | null;
  /** Null once the devotee who posted it has left the congregation. */
  posted_by: string | null;
  posted_by_name: string | null;
  posted_by_photo_url: string | null;
  created_at: string;
  /** The server's answer, never re-derived here. */
  can_delete: boolean;
  can_manage: boolean;
};

/** What `post_newsletter` and `delete_newsletter` hand back: the bare table
 * row, without the poster's name or the permission columns. */
export type NewsletterRow = {
  id: string;
  title: string;
  month: string;
  file_url: string;
  cover_image_url: string | null;
  notes: string | null;
  posted_by: string | null;
  created_at: string;
};

/** One row of `list_newsletter_editors()`. Empty for anyone who may not
 * manage the newsletter. */
export type NewsletterEditor = {
  devotee_id: string;
  devotee_name: string;
  devotee_photo_url: string | null;
  appointed_by: string | null;
  appointed_by_name: string | null;
  appointed_at: string;
  /** True only for the two office holders; an editor sees the team but no way
   * to change it. */
  can_revoke: boolean;
};

export type NewsletterSubmissionStatus = "new" | "reviewed";

/** A whole `newsletter_submissions` row, as returned by the two writes. */
export type NewsletterSubmissionRow = {
  id: string;
  devotee_id: string;
  body: string;
  image_urls: string[];
  file_url: string | null;
  status: NewsletterSubmissionStatus;
  reply: string | null;
  replied_by: string | null;
  replied_at: string | null;
  created_at: string;
};

/**
 * A row of `list_my_newsletter_submissions()`. The editor travels as a name
 * and nothing else: the devotee is being told the temple read it, not handed a
 * contact card.
 */
export type MyNewsletterSubmission = {
  id: string;
  body: string;
  image_urls: string[];
  file_url: string | null;
  status: NewsletterSubmissionStatus;
  reply: string | null;
  replied_by_name: string | null;
  replied_at: string | null;
  created_at: string;
  can_manage: boolean;
  /** False wherever the removal migration has not run; see the api. */
  can_delete: boolean;
};

/** A row of `list_all_newsletter_submissions()`. Empty for anyone who may not
 * manage the newsletter. */
export type AllNewsletterSubmission = {
  id: string;
  devotee_id: string;
  devotee_name: string;
  devotee_photo_url: string | null;
  body: string;
  image_urls: string[];
  file_url: string | null;
  status: NewsletterSubmissionStatus;
  reply: string | null;
  replied_by: string | null;
  replied_by_name: string | null;
  replied_at: string | null;
  created_at: string;
  can_manage: boolean;
  /** False wherever the removal migration has not run; see the api. */
  can_delete: boolean;
};

/** A document chosen off the phone, before it has been uploaded. */
export type PickedNewsletterFile = {
  uri: string;
  name: string;
  mimeType: string;
};

export type PostNewsletterInput = {
  title: string;
  /** "YYYY-MM-DD"; the server normalises it to the first of that month. */
  month: string;
  /** Must already be in the newsletter-files bucket; the server checks. */
  fileUrl: string;
  coverImageUrl?: string | null;
  notes?: string | null;
};

/**
 * One tap instead of a sentence. An editor who has to compose a paragraph per
 * row is an editor with a queue they never work through, and these four cover
 * almost every story that arrives.
 */
export const cannedStoryReplies = [
  "Thank you — we have read this and are keeping it for a coming issue.",
  "Beautiful, thank you. This will go in the next newsletter.",
  "Thank you for sending this in. We may come back to you about it.",
  "Hare Krsna, thank you for taking the time to write this.",
] as const;
