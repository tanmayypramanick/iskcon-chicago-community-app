import { reportReachability } from "../../lib/connectivity";
import {
  compressImage,
  MESSAGE_IMAGE_LIMITS,
} from "../../lib/compressImage";
import { readLocalFileBytes } from "../../lib/readLocalFile";
import { getSupabaseClient } from "../../lib/supabase";
import { isConnectionProblem } from "../services/format";
import type {
  ConversationSummary,
  MessageRow,
  PickedMessageImage,
  SendMessageInput,
} from "./types";

/**
 * How much of a thread is loaded at once. A conversation between two devotees
 * who serve together every week grows without limit, and rendering years of it
 * to show the last exchange is work nobody asked for.
 */
export const MESSAGE_PAGE_SIZE = 200;

const MESSAGE_IMAGE_BUCKET = "message-images";

async function runRpc(
  name: string,
  params: Record<string, unknown>,
): Promise<unknown> {
  const { data, error } = await getSupabaseClient().rpc(name, params);
  // A transport failure means the server is unreachable; a Postgres error
  // means it answered, so the connection is fine.
  reportReachability(!error || !isConnectionProblem(error));
  if (error) throw error;
  return data;
}

export async function fetchConversations(): Promise<ConversationSummary[]> {
  const { data, error } = await getSupabaseClient().rpc(
    "list_my_conversations",
  );
  reportReachability(!error || !isConnectionProblem(error));
  if (error) throw error;
  return (data ?? []) as unknown as ConversationSummary[];
}

/**
 * Newest first, which is the order an inverted list wants and also the order
 * that makes a `limit` mean "the most recent" rather than "the oldest".
 */
export async function fetchMessages(
  conversationId: string,
): Promise<MessageRow[]> {
  const { data, error } = await getSupabaseClient()
    .from("messages")
    .select(
      "id,conversation_id,sender_id,body,image_url,created_at,read_at,deleted_at,delivered_at",
    )
    .eq("conversation_id", conversationId)
    .order("created_at", { ascending: false })
    .limit(MESSAGE_PAGE_SIZE)
    .returns<MessageRow[]>();

  reportReachability(!error || !isConnectionProblem(error));
  if (error) throw error;
  return data ?? [];
}

/**
 * A row of `list_conversation_messages`. `body` / `image_url` are null once
 * `deleted_at` is set; `original_body` / `original_image_url` keep what the row
 * held before that.
 */
export type ConversationMessageRow = {
  id: string;
  sender_id: string;
  sender_name: string | null;
  body: string | null;
  image_url: string | null;
  created_at: string;
  deleted_at: string | null;
  original_body: string | null;
  original_image_url: string | null;
};

/**
 * Oldest first, the whole thread in one call.
 *
 * Returns null — not an error — when the function is not deployed yet
 * (PGRST202 / 42883), so a caller can fall back instead of showing a failure
 * against a database that has not had the migration applied.
 */
export async function listConversationMessages(
  conversationId: string,
): Promise<ConversationMessageRow[] | null> {
  const { data, error } = await getSupabaseClient().rpc(
    "list_conversation_messages",
    { p_conversation_id: conversationId },
  );
  reportReachability(!error || !isConnectionProblem(error));
  if (error) {
    if (["PGRST202", "42883"].includes(error.code ?? "")) return null;
    throw error;
  }
  return (data ?? []) as unknown as ConversationMessageRow[];
}

/** Returns the existing thread with this devotee, or opens one. */
export async function openConversation(devoteeId: string): Promise<string> {
  const data = await runRpc("open_conversation", { p_devotee_id: devoteeId });
  return data as string;
}

export async function sendMessage(
  input: SendMessageInput,
): Promise<MessageRow> {
  const data = await runRpc("send_message", {
    p_conversation_id: input.conversationId,
    p_body: input.body ?? null,
    p_image_url: input.imageUrl ?? null,
  });
  return data as MessageRow;
}

/** Number of the other devotee's messages this call marked read. */
export async function markConversationDelivered(conversationId: string) {
  return runRpc("mark_conversation_delivered", {
    p_conversation_id: conversationId,
  });
}

export async function hideMessageForMe(messageId: string) {
  return runRpc("hide_message_for_me", { p_message_id: messageId });
}

/**
 * Clears the existing thread from this devotee's inbox without deleting the
 * retained conversation. A later message makes it appear again.
 */
export async function removeConversationForMe(conversationId: string) {
  return runRpc("remove_conversation_for_me", {
    p_conversation_id: conversationId,
  });
}

export async function markConversationRead(
  conversationId: string,
): Promise<number> {
  const data = await runRpc("mark_conversation_read", {
    p_conversation_id: conversationId,
  });
  return typeof data === "number" ? data : 0;
}

export async function deleteMessage(messageId: string): Promise<MessageRow> {
  const data = await runRpc("delete_message", { p_message_id: messageId });
  return data as MessageRow;
}

/**
 * expo-image-picker is a native module, loaded late so a binary built before
 * the dependency existed still starts.
 *
 * `await import()` is not enough: Metro compiles it to a synchronous require
 * and the missing-native-module error is raised while the module body
 * evaluates, escaping the promise and reaching the devotee as a red screen. A
 * plain require inside try/catch does catch it.
 */
const REBUILD_MESSAGE =
  "This copy of the app was built before pictures were added. Rebuild it (npm run ios / npm run android) and try again.";

type ImagePickerModule = typeof import("expo-image-picker");

function loadImagePicker(): ImagePickerModule {
  let candidate: unknown;
  try {
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    candidate = require("expo-image-picker");
  } catch {
    throw new Error(REBUILD_MESSAGE);
  }

  // Metro's interop sometimes nests the real module under `default`.
  const picker = (candidate as { default?: unknown })?.default ?? candidate;
  const api = picker as Partial<ImagePickerModule> | undefined;
  if (
    !api ||
    typeof api.launchImageLibraryAsync !== "function" ||
    typeof api.launchCameraAsync !== "function" ||
    typeof api.requestCameraPermissionsAsync !== "function" ||
    typeof api.requestMediaLibraryPermissionsAsync !== "function"
  ) {
    throw new Error(REBUILD_MESSAGE);
  }
  return api as ImagePickerModule;
}

function extensionFor(mimeType: string) {
  if (mimeType.includes("png")) return "png";
  if (mimeType.includes("webp")) return "webp";
  return "jpg";
}

/**
 * No crop step here, unlike a profile photo: a picture sent in a conversation
 * is whatever the devotee is pointing at, and forcing it square would cut the
 * subject out of it. Returns null when they cancel.
 */
export async function pickMessageImage(
  source: "library" | "camera",
): Promise<PickedMessageImage | null> {
  const ImagePicker = loadImagePicker();
  const permission =
    source === "camera"
      ? await ImagePicker.requestCameraPermissionsAsync()
      : await ImagePicker.requestMediaLibraryPermissionsAsync();
  if (!permission.granted) {
    throw new Error(
      source === "camera"
        ? "Allow camera access to send a photo."
        : "Allow photo access to send a picture.",
    );
  }

  const options: import("expo-image-picker").ImagePickerOptions = {
    mediaTypes: ["images"],
    quality: 0.7,
  };
  const result =
    source === "camera"
      ? await ImagePicker.launchCameraAsync(options)
      : await ImagePicker.launchImageLibraryAsync(options);

  const asset = result.canceled ? null : result.assets[0];
  if (!asset) return null;

  const shrunk = await compressImage(
    asset.uri,
    asset.mimeType ?? "image/jpeg",
    MESSAGE_IMAGE_LIMITS,
  );
  return {
    uri: shrunk.uri,
    mimeType: shrunk.mimeType,
    fileName: asset.fileName ?? `picture.${extensionFor(shrunk.mimeType)}`,
  };
}

/**
 * Uploads to `message-images/<auth uid>/…` — the storage policy checks that
 * first path segment, so the sender's own id is the only folder that will be
 * accepted. Returns the public URL to hand to send_message.
 */
export async function uploadMessageImage(
  userId: string,
  image: PickedMessageImage,
): Promise<string> {
  const supabase = getSupabaseClient();
  const path = `${userId}/${Date.now()}.${extensionFor(image.mimeType)}`;

  const body = await readLocalFileBytes(image.uri);
  // Matches the bucket's own 8 MB limit, so an oversized picture fails here
  // with something readable instead of as a storage error.
  if (body.byteLength > 8 * 1024 * 1024) {
    throw new Error("Please choose a picture smaller than 8 MB.");
  }

  const { error } = await supabase.storage
    .from(MESSAGE_IMAGE_BUCKET)
    .upload(path, body, { contentType: image.mimeType, upsert: false });
  if (error) throw error;

  const {
    data: { publicUrl },
  } = supabase.storage.from(MESSAGE_IMAGE_BUCKET).getPublicUrl(path);
  return publicUrl;
}
