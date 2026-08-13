import { reportReachability } from "../../lib/connectivity";
import { getSupabaseClient } from "../../lib/supabase";
// The board puts pictures into the same message-images bucket as direct
// messages, so it uses the same picker and the same uploader. A second
// uploader would be a second place to get the path prefix wrong, and both the
// storage policy and create_care_post's URL check only accept one.
import { pickMessageImage, uploadMessageImage } from "../messaging/api";
import { isConnectionProblem } from "../services/format";
import type { CarePost, CarePostRow, CareReply, CareReplyRow } from "./types";

export { pickMessageImage, uploadMessageImage };

/**
 * Devotee Care arrives with its own migration, which a temple's database may
 * not have had applied yet.
 *   PGRST202 / 42883 — that function does not exist
 *   42P01 / PGRST205 — that relation does not exist
 * Reads treat that as "the board is empty" rather than as a failure: a devotee
 * cannot act on a migration that has not been run, and a red error where a
 * quiet empty state belongs reads as the app being broken.
 */
function isMigrationPending(error: { code?: string } | null) {
  return ["PGRST202", "42883", "42P01", "PGRST205"].includes(error?.code ?? "");
}

async function listRpc<Row>(
  name: string,
  params: Record<string, unknown> = {},
): Promise<Row[]> {
  const { data, error } = await getSupabaseClient().rpc(name, params);
  // A transport failure means the server is unreachable; a Postgres error
  // means it answered, so the connection is fine.
  reportReachability(!error || !isConnectionProblem(error));
  if (error) {
    if (isMigrationPending(error)) return [];
    throw error;
  }
  return (data ?? []) as unknown as Row[];
}

/**
 * The writes deliberately do not tolerate a missing migration. There is
 * nothing to post, answer or take down until it has run, so an error here is a
 * real one and the devotee should be told rather than watching a tap do
 * nothing.
 */
async function runRpc(
  name: string,
  params: Record<string, unknown> = {},
): Promise<unknown> {
  const { data, error } = await getSupabaseClient().rpc(name, params);
  reportReachability(!error || !isConnectionProblem(error));
  if (error) throw error;
  return data;
}

/** Every live request, newest first. */
export function fetchCarePosts(): Promise<CarePost[]> {
  return listRpc<CarePost>("list_care_posts");
}

/** One thread, oldest first, tombstones included. */
export function fetchCareReplies(postId: string): Promise<CareReply[]> {
  return listRpc<CareReply>("list_care_replies", { p_post_id: postId });
}

export async function createCarePost(input: {
  title: string;
  body: string;
  imageUrl?: string | null;
}): Promise<CarePostRow> {
  const data = await runRpc("create_care_post", {
    p_title: input.title,
    p_body: input.body,
    p_image_url: input.imageUrl ?? null,
  });
  return data as CarePostRow;
}

export async function replyToCarePost(
  postId: string,
  body: string,
): Promise<CareReplyRow> {
  const data = await runRpc("reply_to_care_post", {
    p_post_id: postId,
    p_body: body,
  });
  return data as CareReplyRow;
}

export async function deleteCarePost(postId: string): Promise<CarePostRow> {
  const data = await runRpc("delete_care_post", { p_post_id: postId });
  return data as CarePostRow;
}

export async function deleteCareReply(replyId: string): Promise<CareReplyRow> {
  const data = await runRpc("delete_care_reply", { p_reply_id: replyId });
  return data as CareReplyRow;
}
