import { reportReachability } from "../../lib/connectivity";
import { getSupabaseClient } from "../../lib/supabase";
import { isConnectionProblem } from "../services/format";
import type {
  AllFeedback,
  FeedbackCategory,
  FeedbackRow,
  MyFeedback,
} from "./types";

/**
 * Feedback arrives with its own migration, which a temple's database may not
 * have had applied yet.
 *   PGRST202 / 42883 — that function does not exist
 *   42P01 / PGRST205 — that relation does not exist
 * Reads treat that as "there is no feedback yet" rather than as a failure: a
 * devotee cannot act on a migration that has not been run, and a red error
 * where a quiet empty state belongs reads as the app being broken.
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
 * nothing to send or review until it has run, so an error here is a real one
 * and the devotee should be told rather than watching a tap do nothing.
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

export async function submitFeedback(
  category: FeedbackCategory,
  body: string,
): Promise<FeedbackRow> {
  const data = await runRpc("submit_feedback", {
    p_category: category,
    p_body: body,
  });
  return data as FeedbackRow;
}

/**
 * `can_delete` arrives with the removal migration, so until that has run the
 * column is simply absent from the row. Absent is read as "no": offering a
 * Remove the server would refuse is worse than not offering it at all.
 */
function withCanDelete<Row extends { can_delete?: boolean }>(rows: Row[]) {
  return rows.map((row) => ({ ...row, can_delete: row.can_delete === true }));
}

/** The devotee's own notes, newest first, each with any reply. */
export async function fetchMyFeedback(): Promise<MyFeedback[]> {
  return withCanDelete(await listRpc<MyFeedback>("list_my_feedback"));
}

/**
 * Everything, newest first. The function itself returns an empty set to anyone
 * without `app.view_all`, so calling it is safe whatever the viewer's role.
 */
export async function fetchAllFeedback(): Promise<AllFeedback[]> {
  return withCanDelete(await listRpc<AllFeedback>("list_all_feedback"));
}

/** Marks it read. The reply is optional, and blank leaves any existing one. */
export async function reviewFeedback(
  feedbackId: string,
  reply?: string | null,
): Promise<FeedbackRow> {
  const data = await runRpc("review_feedback", {
    p_feedback_id: feedbackId,
    p_reply: reply?.trim() ? reply.trim() : null,
  });
  return data as FeedbackRow;
}

/** The note goes for good. The server decides who may; `can_delete` says so. */
export function deleteFeedback(feedbackId: string) {
  return runRpc("delete_feedback", { p_feedback_id: feedbackId });
}
