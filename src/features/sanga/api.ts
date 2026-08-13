import { reportReachability } from "../../lib/connectivity";
import { getSupabaseClient } from "../../lib/supabase";
// Sangas post pictures into the same message-images bucket as direct
// messages, so they use the same picker and the same uploader. A second
// uploader would be a second place to get the path prefix wrong, and the
// storage policy only accepts one.
import { pickMessageImage, uploadMessageImage } from "../messaging/api";
import { isConnectionProblem } from "../services/format";
import type {
  MySangaSummary,
  PendingSanga,
  SangaDecision,
  SangaJoinRequest,
  SangaJoinRequestRow,
  SangaMember,
  SangaMemberRow,
  SangaMessage,
  SangaMessageRow,
  SangaRow,
  SangaSummary,
  SendSangaMessageInput,
} from "./types";

export { pickMessageImage, uploadMessageImage };

/**
 * Sangas arrive with their own migration, which a temple's database may not
 * have had applied yet.
 *   PGRST202 / 42883 — that function does not exist
 *   42P01 / PGRST205 — that relation does not exist
 * Reads treat that as "there are no sangas yet" rather than as a failure: a
 * devotee cannot act on a migration that has not been run, and a red error
 * where a quiet empty state belongs reads as the app being broken.
 */
function isMigrationPending(error: { code?: string } | null) {
  return ["PGRST202", "42883", "42P01", "PGRST205"].includes(error?.code ?? "");
}

/**
 * The reads all have the same shape: a list, or an empty one while the
 * migration is outstanding.
 */
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
 * nothing to create, join or approve until it has run, so an error here is a
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

/** Every approved, running sanga, each marked with where the viewer stands. */
export function fetchSangas(): Promise<SangaSummary[]> {
  return listRpc<SangaSummary>("list_sangas");
}

/** Everything the viewer is in or proposed, including what is still waiting. */
export function fetchMySangas(): Promise<MySangaSummary[]> {
  return listRpc<MySangaSummary>("list_my_sangas");
}

/** The President's queue. Empty for everyone else, by the function's own rule. */
export function fetchPendingSangas(): Promise<PendingSanga[]> {
  return listRpc<PendingSanga>("list_pending_sangas");
}

export function fetchSangaMembers(sangaId: string): Promise<SangaMember[]> {
  return listRpc<SangaMember>("list_sanga_members", { p_sanga_id: sangaId });
}

/** The admin's inbox for one sanga. Empty for its ordinary members. */
export function fetchSangaJoinRequests(
  sangaId: string,
): Promise<SangaJoinRequest[]> {
  return listRpc<SangaJoinRequest>("list_sanga_join_requests", {
    p_sanga_id: sangaId,
  });
}

/** Creates it pending, with the caller as its admin, and tells the President. */
export async function createSanga(
  name: string,
  description?: string | null,
): Promise<SangaRow> {
  const data = await runRpc("create_sanga", {
    p_name: name,
    p_description: description ?? null,
  });
  return data as SangaRow;
}

export async function reviewSanga(
  sangaId: string,
  decision: SangaDecision,
  note?: string | null,
): Promise<SangaRow> {
  const data = await runRpc("review_sanga", {
    p_sanga_id: sangaId,
    p_decision: decision,
    p_note: note ?? null,
  });
  return data as SangaRow;
}

/** A second ask returns the request already waiting rather than making two. */
export async function requestToJoinSanga(
  sangaId: string,
  message?: string | null,
): Promise<SangaJoinRequestRow> {
  const data = await runRpc("request_to_join_sanga", {
    p_sanga_id: sangaId,
    p_message: message ?? null,
  });
  return data as SangaJoinRequestRow;
}

export async function reviewSangaJoinRequest(
  requestId: string,
  decision: SangaDecision,
): Promise<SangaJoinRequestRow> {
  const data = await runRpc("review_sanga_join_request", {
    p_request_id: requestId,
    p_decision: decision,
  });
  return data as SangaJoinRequestRow;
}

export async function addSangaMember(
  sangaId: string,
  devoteeId: string,
): Promise<SangaMemberRow> {
  const data = await runRpc("add_sanga_member", {
    p_sanga_id: sangaId,
    p_devotee_id: devoteeId,
  });
  return data as SangaMemberRow;
}

/** False when there was nobody to remove — a second tap, not a failure. */
export async function removeSangaMember(
  sangaId: string,
  devoteeId: string,
): Promise<boolean> {
  const data = await runRpc("remove_sanga_member", {
    p_sanga_id: sangaId,
    p_devotee_id: devoteeId,
  });
  return data === true;
}

/** The successor must already be a member; the server refuses otherwise. */
export async function transferSangaAdmin(
  sangaId: string,
  devoteeId: string,
): Promise<SangaRow> {
  const data = await runRpc("transfer_sanga_admin", {
    p_sanga_id: sangaId,
    p_devotee_id: devoteeId,
  });
  return data as SangaRow;
}

/**
 * Closes a sanga for good: its admin, or a holder of app.view_all. The row
 * survives with `deleted_at` stamped — nothing is erased, but the circle stops
 * appearing anywhere and cannot be brought back.
 */
export async function deleteSanga(sangaId: string): Promise<SangaRow> {
  const data = await runRpc("delete_sanga", { p_sanga_id: sangaId });
  return data as SangaRow;
}

/** False when the viewer was not in it. The last admin is refused outright. */
export async function leaveSanga(sangaId: string): Promise<boolean> {
  const data = await runRpc("leave_sanga", { p_sanga_id: sangaId });
  return data === true;
}

/**
 * The whole thread, oldest first — the order it was said in, and the order the
 * cache keeps it in so no screen has to re-sort it.
 *
 * Members see it because they are in the sanga; the President and Tech Admin
 * see it because they hold app.view_all. Everyone else gets nothing back, not
 * an error, which is the same answer an unapplied migration gives.
 */
export function fetchSangaMessages(sangaId: string): Promise<SangaMessage[]> {
  return listRpc<SangaMessage>("list_sanga_messages", { p_sanga_id: sangaId });
}

export async function sendSangaMessage(
  input: SendSangaMessageInput,
): Promise<SangaMessageRow> {
  const data = await runRpc("send_sanga_message", {
    p_sanga_id: input.sangaId,
    p_body: input.body ?? null,
    p_image_url: input.imageUrl ?? null,
  });
  return data as SangaMessageRow;
}

/**
 * Moves the viewer's watermark to now and answers how many messages that
 * cleared. Zero means there was nothing behind it, which is the caller's cue to
 * leave its caches alone.
 *
 * Tolerant of a missing migration, unlike the other writes here. This is not a
 * devotee asking for something — it is housekeeping the chat screen does on
 * every focus and every arriving message, and on a temple whose database has
 * not caught up it would put a red error over a thread that is working.
 */
export async function markSangaRead(sangaId: string): Promise<number> {
  const { data, error } = await getSupabaseClient().rpc("mark_sanga_read", {
    p_sanga_id: sangaId,
  });
  reportReachability(!error || !isConnectionProblem(error));
  if (error) {
    if (isMigrationPending(error)) return 0;
    throw error;
  }
  return typeof data === "number" ? data : 0;
}

/** The sender may take down their own; the admin may take down any of them. */
export async function deleteSangaMessage(
  messageId: string,
): Promise<SangaMessageRow> {
  const data = await runRpc("delete_sanga_message", {
    p_message_id: messageId,
  });
  return data as SangaMessageRow;
}
