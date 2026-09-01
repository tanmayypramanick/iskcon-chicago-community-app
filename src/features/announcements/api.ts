import { reportReachability } from "../../lib/connectivity";
import { getSupabaseClient } from "../../lib/supabase";
// An announcement photo lives in the same message-images bucket as a chat
// picture, and the migration only accepts a URL from it, so the picker and the
// uploader are the messaging ones rather than a second pair to keep in step.
import { pickMessageImage, uploadMessageImage } from "../messaging/api";
import { isConnectionProblem } from "../services/format";
import type {
  AddAnnouncementCommentInput,
  Announcement,
  AnnouncementComment,
  AnnouncementCommentRow,
  AnnouncementLike,
  AnnouncementRow,
  CreateAnnouncementInput,
} from "./types";

export { pickMessageImage, uploadMessageImage };

/**
 * Announcements arrive with their own migration, which a temple's database may
 * not have had applied yet.
 *   PGRST202 / 42883 — that function does not exist
 *   42P01 / PGRST205 — that relation does not exist
 * The read treats that as an empty noticeboard rather than as a failure: a red
 * error where a quiet empty state belongs reads as the app being broken.
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
 * Newest first, and already free of anything that has run out — the function
 * decides liveness on Chicago's clock, which is the one thing a client must
 * not try to answer for itself.
 */
export function fetchAnnouncements(): Promise<Announcement[]> {
  return listRpc<Announcement>("list_announcements");
}

/** Everyone who liked one notice, newest first, by name and face. */
export function fetchAnnouncementLikes(
  announcementId: string,
): Promise<AnnouncementLike[]> {
  return listRpc<AnnouncementLike>("list_announcement_likes", {
    p_announcement_id: announcementId,
  });
}

/** One thread in render order, tombstones included. */
export function fetchAnnouncementComments(
  announcementId: string,
): Promise<AnnouncementComment[]> {
  return listRpc<AnnouncementComment>("list_announcement_comments", {
    p_announcement_id: announcementId,
  });
}

/**
 * The writes deliberately do not tolerate a missing migration. There is
 * nothing to post or take down until it has run, so an error here is a real
 * one and whoever tapped should be told rather than watching nothing happen.
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

export async function createAnnouncement(
  input: CreateAnnouncementInput,
): Promise<AnnouncementRow> {
  const data = await runRpc("create_announcement", {
    p_title: input.title,
    p_body: input.body,
    p_image_url: input.imageUrl ?? null,
    p_starts_on: input.startsOn ?? null,
    p_ends_on: input.endsOn ?? null,
    p_starts_at: input.startsAt ?? null,
    p_ends_at: input.endsAt ?? null,
    p_kind: input.kind ?? "general",
  });
  return data as AnnouncementRow;
}

/** Likes, or unlikes. True when the devotee now likes it; pressing twice is
 * an unlike, so the answer is the state and not the tap. */
export async function toggleAnnouncementLike(
  announcementId: string,
): Promise<boolean> {
  const data = await runRpc("toggle_announcement_like", {
    p_announcement_id: announcementId,
  });
  return data === true;
}

export async function addAnnouncementComment(
  input: AddAnnouncementCommentInput,
): Promise<AnnouncementCommentRow> {
  const data = await runRpc("add_announcement_comment", {
    p_announcement_id: input.announcementId,
    p_body: input.body,
    p_parent_comment_id: input.parentCommentId ?? null,
  });
  return data as AnnouncementCommentRow;
}

/** Soft: the row keeps its place so the replies under it keep their sense. */
export async function deleteAnnouncementComment(
  commentId: string,
): Promise<AnnouncementCommentRow> {
  const data = await runRpc("delete_announcement_comment", {
    p_comment_id: commentId,
  });
  return data as AnnouncementCommentRow;
}

/** The row goes for good. The server decides who may; `can_delete` says so. */
export async function deleteAnnouncement(
  announcementId: string,
): Promise<AnnouncementRow> {
  const data = await runRpc("delete_announcement", {
    p_announcement_id: announcementId,
  });
  return data as AnnouncementRow;
}
