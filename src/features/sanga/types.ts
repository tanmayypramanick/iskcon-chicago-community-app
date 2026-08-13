/**
 * Shapes returned by the sanga migration (202608040039_sangas.sql).
 *
 * A sanga is proposed by any devotee, approved by the President, and then run
 * by the devotee who proposed it. Everyone inside it talks in one thread. The
 * four tables and the ten write functions all speak in the shapes below.
 */

/**
 * A picture on its way into a sanga thread. Sangas share the message-images
 * bucket with direct messages, so they share its picked-image shape too.
 */
export type { PickedMessageImage } from "../messaging/types";

/** A sanga waits for the President, then is either running or turned down. */
export type SangaStatus = "pending" | "approved" | "declined";

/** The only two answers `review_sanga` and `review_sanga_join_request` take. */
export type SangaDecision = "approved" | "declined";

export type SangaJoinRequestStatus = "pending" | "approved" | "declined";

export type SangaMemberRole = "admin" | "member";

/**
 * A whole `sangas` row, as returned by `create_sanga`, `review_sanga` and
 * `transfer_sanga_admin`.
 *
 * `admin_id`, `created_by` and `reviewed_by` are nullable because a devotee's
 * account can be deleted after the fact; the circle outlives the attribution.
 */
export type SangaRow = {
  id: string;
  name: string;
  description: string | null;
  created_by: string | null;
  admin_id: string | null;
  status: SangaStatus;
  reviewed_by: string | null;
  reviewed_at: string | null;
  review_note: string | null;
  /** False once the sanga has been retired. Retired, never deleted. */
  active: boolean;
  created_at: string;
  updated_at: string;
};

/** A whole `sanga_members` row, as returned by `add_sanga_member`. */
export type SangaMemberRow = {
  sanga_id: string;
  devotee_id: string;
  role: SangaMemberRole;
  joined_at: string;
  /** Null when the devotee asked to join; set when an admin put them there. */
  added_by: string | null;
};

/**
 * A whole `sanga_join_requests` row, as returned by `request_to_join_sanga`
 * and `review_sanga_join_request`.
 */
export type SangaJoinRequestRow = {
  id: string;
  sanga_id: string;
  devotee_id: string;
  status: SangaJoinRequestStatus;
  message: string | null;
  decided_by: string | null;
  decided_at: string | null;
  created_at: string;
};

/** A row of `list_sangas()` — every approved, running sanga. */
export type SangaSummary = {
  id: string;
  name: string;
  description: string | null;
  member_count: number;
  /** Whether the signed-in devotee is in this sanga. */
  is_member: boolean;
  /** Whether the signed-in devotee runs it. */
  is_admin: boolean;
  /** The viewer's most recent ask, or null if they have never asked. */
  request_status: SangaJoinRequestStatus | null;
  admin_id: string | null;
  admin_name: string | null;
  created_by: string | null;
  created_by_name: string | null;
  created_at: string;
  /**
   * Messages said in this sanga since the viewer last opened it, not counting
   * their own or deleted ones (202608040056_sanga_unread.sql).
   *
   * Zero for anybody who is not in the circle, including a President browsing
   * it through app.view_all: reading over the top of a group is not being in
   * it, and a badge would be telling them to catch up on somebody else's
   * conversation. A devotee who joins an existing sanga starts at zero — the
   * whole thread is theirs to scroll, but none of it is a debt.
   */
  unread_count: number;
};

/**
 * A row of `list_my_sangas()` — everything the viewer is in or proposed,
 * whatever state it is in, so a sanga awaiting the President does not vanish
 * from the eyes of the devotee who started it.
 */
export type MySangaSummary = {
  id: string;
  name: string;
  description: string | null;
  status: SangaStatus;
  active: boolean;
  /** The President's reason, on a declined sanga. */
  review_note: string | null;
  member_count: number;
  is_member: boolean;
  is_admin: boolean;
  admin_id: string | null;
  admin_name: string | null;
  created_at: string;
  reviewed_at: string | null;
  /** As on `SangaSummary`. Zero on a sanga still waiting for the President,
   * which has no thread to be behind on. */
  unread_count: number;
};

/** A row of `list_pending_sangas()` — the President's approval queue. */
export type PendingSanga = {
  id: string;
  name: string;
  description: string | null;
  created_by: string | null;
  created_by_name: string | null;
  created_by_photo_url: string | null;
  created_at: string;
};

/**
 * A row of `list_sanga_members()`. `id` is the devotee's id, not a membership
 * id — the membership has no id of its own.
 */
export type SangaMember = {
  id: string;
  name: string;
  photo_url: string | null;
  role: SangaMemberRole;
  joined_at: string;
  added_by: string | null;
  added_by_name: string | null;
};

/** A row of `list_sanga_join_requests()` — the admin's inbox for one sanga. */
export type SangaJoinRequest = {
  id: string;
  sanga_id: string;
  devotee_id: string;
  devotee_name: string;
  devotee_photo_url: string | null;
  status: SangaJoinRequestStatus;
  message: string | null;
  created_at: string;
  decided_at: string | null;
  decided_by: string | null;
  decided_by_name: string | null;
};

/**
 * A row of `list_sanga_messages()`, and the shape the cached thread holds.
 *
 * `body` and `image_url` are both null once `deleted_at` is set — what was
 * said moves into columns the client is never granted, so a deleted message
 * arrives as a tombstone with a time on it and nothing else.
 */
export type SangaMessage = {
  id: string;
  sanga_id: string;
  sender_id: string;
  /** Null only if the sender's account has since been deleted. */
  sender_name: string | null;
  sender_photo_url: string | null;
  body: string | null;
  image_url: string | null;
  created_at: string;
  deleted_at: string | null;
  /**
   * Only on a message that has not reached the server yet. It marks the
   * placeholder so the real row can replace it rather than sit beside it.
   */
  pending?: boolean;
};

/**
 * The bare `sanga_messages` row that `send_sanga_message` and
 * `delete_sanga_message` return. It carries no sender name, which is why the
 * hooks that call them are given one to paint with.
 *
 * The retained `original_body` / `original_image_url` columns are deliberately
 * not typed here: they are the temple's record of a deleted message, not
 * something any screen should be able to reach for.
 */
export type SangaMessageRow = {
  id: string;
  sanga_id: string;
  sender_id: string;
  body: string | null;
  image_url: string | null;
  created_at: string;
  deleted_at: string | null;
};

export type SendSangaMessageInput = {
  sangaId: string;
  body?: string | null;
  imageUrl?: string | null;
};

/**
 * Broadcast over the per-sanga realtime channel; never stored.
 *
 * The name travels with the signal because a group can have several people
 * typing at once and the roll may not be loaded yet — "someone is typing" a
 * second before the names arrive is worse than no indicator at all.
 */
export type SangaTypingSignal = {
  typing: boolean;
  from: string;
  name: string | null;
};

/** One devotee currently typing in a sanga. */
export type SangaTypist = {
  id: string;
  name: string | null;
};

/**
 * What the viewer may do in one sanga.
 *
 * A holder of app.view_all — the President or a Tech Admin — may act on any
 * sanga without joining it (202608040043_sanga_powers.sql). So none of the
 * powers below is derived from membership: `isMember` and `isAdmin` stay false
 * for them, because acting on a circle is not being in it and the member count
 * must not move because the office used a button.
 */
export type SangaViewerCapabilities = {
  isMember: boolean;
  isAdmin: boolean;
  /** They hold app.view_all. Only ever used to say why they may act. */
  overseesApp: boolean;
  canPost: boolean;
  canManageMembers: boolean;
  /** Taking down somebody else's message. */
  canDeleteAnyMessage: boolean;
  /** Closing the sanga for good. */
  canDeleteSanga: boolean;
  /** Choosing a successor stays the sanga admin's own judgement. */
  canTransferAdmin: boolean;
  /** Only somebody actually in it has anything to leave. */
  canLeave: boolean;
};
