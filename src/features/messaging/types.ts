/**
 * Shapes returned by the messaging migration (202608040032_messaging.sql).
 * Kept in step with `list_my_conversations()` and the `messages` table.
 */

export type ConversationSummary = {
  id: string;
  other_devotee_id: string;
  other_name: string;
  other_photo_url: string | null;
  other_role: string;
  last_message_at: string;
  /** Null when the thread is empty, when the last message was deleted, or when it was a picture. */
  last_body: string | null;
  last_sender_id: string | null;
  last_deleted: boolean | null;
  last_has_image: boolean | null;
  unread_count: number;
};

export type MessageRow = {
  id: string;
  conversation_id: string;
  sender_id: string;
  body: string | null;
  image_url: string | null;
  created_at: string;
  /** Stamped by mark_conversation_read on the recipient's side only. */
  read_at: string | null;
  /** Soft delete: the row survives, body and image_url are nulled. */
  deleted_at: string | null;
  /** Set once the recipient's device has it. Read is a later, separate thing. */
  delivered_at?: string | null;
  /**
   * Only on a message that has not reached the server yet. It carries the
   * optimistic row's identity so the real row can replace it rather than
   * appearing beside it.
   */
  pending?: boolean;
};

export type SendMessageInput = {
  conversationId: string;
  body?: string | null;
  imageUrl?: string | null;
};

export type PickedMessageImage = {
  uri: string;
  mimeType: string;
  fileName: string;
};

/** Broadcast over the per-conversation realtime channel; never stored. */
export type TypingSignal = {
  typing: boolean;
  from: string;
};
