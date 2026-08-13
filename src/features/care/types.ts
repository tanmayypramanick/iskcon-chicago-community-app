/**
 * Shapes returned by the devotee care migration (202608040042_devotee_care.sql).
 *
 * A board, not a chat: any devotee posts a request for help, any devotee
 * replies, everybody reads everything. The only notification in the whole
 * feature goes to the post's author when somebody answers them.
 */

/**
 * A picture on its way onto the board. Care posts share the message-images
 * bucket with direct messages, so they share its picked-image shape too.
 */
export type { PickedMessageImage } from "../messaging/types";

/** A whole `care_posts` row, as returned by the write functions. */
export type CarePostRow = {
  id: string;
  author_id: string;
  title: string;
  body: string;
  image_url: string | null;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
  deleted_by: string | null;
};

/** A whole `care_replies` row, as returned by `reply_to_care_post`. */
export type CareReplyRow = {
  id: string;
  post_id: string;
  author_id: string;
  body: string;
  created_at: string;
  deleted_at: string | null;
  deleted_by: string | null;
};

/**
 * A row of `list_care_posts`. `can_remove` travels with the post because every
 * card needs it to decide whether to draw the button.
 */
export type CarePost = {
  id: string;
  author_id: string;
  author_name: string;
  author_photo_url: string | null;
  title: string;
  body: string;
  image_url: string | null;
  created_at: string;
  updated_at: string;
  reply_count: number;
  can_remove: boolean;
};

/**
 * A row of `list_care_replies`, oldest first. A removed reply keeps its place
 * in the thread and comes back with `body` null and `deleted_at` set — the
 * shape of the conversation survives, the words do not.
 */
export type CareReply = {
  id: string;
  post_id: string;
  author_id: string;
  author_name: string;
  author_photo_url: string | null;
  body: string | null;
  created_at: string;
  deleted_at: string | null;
  can_remove: boolean;
};
