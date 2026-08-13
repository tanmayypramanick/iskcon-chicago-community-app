import { File } from "expo-file-system";

import { reportReachability } from "../../lib/connectivity";
import { readLocalFileBytes } from "../../lib/readLocalFile";
import { getSupabaseClient } from "../../lib/supabase";
// A story photo and a newsletter cover both live in the message-images bucket,
// and the migration only accepts a URL from it, so the picker and the uploader
// are the messaging ones rather than a second pair to keep in step.
import { pickMessageImage, uploadMessageImage } from "../messaging/api";
import { isConnectionProblem } from "../services/format";
import type {
  AllNewsletterSubmission,
  MyNewsletterSubmission,
  Newsletter,
  NewsletterEditor,
  NewsletterRow,
  NewsletterSubmissionRow,
  PickedNewsletterFile,
  PostNewsletterInput,
} from "./types";

export { pickMessageImage, uploadMessageImage };

const NEWSLETTER_FILE_BUCKET = "newsletter-files";

/** The bucket's own ceiling, so an oversized PDF fails here with something
 * readable instead of as a storage error. */
const MAX_FILE_BYTES = 25 * 1024 * 1024;

/** What the bucket will accept. Anything else is refused by Storage itself. */
export const NEWSLETTER_FILE_MIME_TYPES = [
  "application/pdf",
  "application/msword",
  "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
];

/**
 * The newsletter arrives with its own migration, which a temple's database may
 * not have had applied yet.
 *   PGRST202 / 42883 — that function does not exist
 *   42P01 / PGRST205 — that relation does not exist
 * Reads treat that as "there are no issues yet" rather than as a failure: a
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
 * nothing to post, appoint or review until it has run, so an error here is a
 * real one and whoever tapped should be told rather than watching nothing
 * happen.
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

/** Every issue, newest month first. Open to every devotee. */
export function fetchNewsletters(): Promise<Newsletter[]> {
  return listRpc<Newsletter>("list_newsletters");
}

/**
 * The server's own answer to "may this devotee work on the newsletter".
 *
 * The permission also travels as `can_manage` on every list row, but a temple
 * that has not put out its first issue and has no stories waiting has no rows
 * to carry it — and that is exactly the moment an editor needs the posting
 * button. Asked directly, the answer exists before the data does.
 */
export async function fetchMayManageNewsletter(): Promise<boolean> {
  const { data, error } = await getSupabaseClient().rpc(
    "may_manage_newsletter",
  );
  reportReachability(!error || !isConnectionProblem(error));
  if (error) {
    if (isMigrationPending(error)) return false;
    throw error;
  }
  return data === true;
}

export async function postNewsletter(
  input: PostNewsletterInput,
): Promise<NewsletterRow> {
  const data = await runRpc("post_newsletter", {
    p_title: input.title,
    p_month: input.month,
    p_file_url: input.fileUrl,
    p_cover_image_url: input.coverImageUrl ?? null,
    p_notes: input.notes ?? null,
  });
  return data as NewsletterRow;
}

/** The row goes for good. The server decides who may; `can_delete` says so. */
export async function deleteNewsletter(
  newsletterId: string,
): Promise<NewsletterRow> {
  const data = await runRpc("delete_newsletter", {
    p_newsletter_id: newsletterId,
  });
  return data as NewsletterRow;
}

/**
 * The editors, newest appointment first. The function returns an empty set to
 * anyone who may not manage the newsletter, so calling it is safe whatever the
 * viewer holds.
 */
export function fetchNewsletterEditors(): Promise<NewsletterEditor[]> {
  return listRpc<NewsletterEditor>("list_newsletter_editors");
}

/** Idempotent: re-appointing returns the existing grant with its original date. */
export async function appointNewsletterEditor(devoteeId: string) {
  return runRpc("appoint_newsletter_editor", { p_devotee_id: devoteeId });
}

export async function revokeNewsletterEditor(devoteeId: string) {
  return runRpc("revoke_newsletter_editor", { p_devotee_id: devoteeId });
}

export async function submitNewsletterStory(input: {
  body: string;
  imageUrls: string[];
  fileUrl?: string | null;
}): Promise<NewsletterSubmissionRow> {
  const data = await runRpc("submit_newsletter_story", {
    p_body: input.body,
    p_image_urls: input.imageUrls,
    p_file_url: input.fileUrl ?? null,
  });
  return data as NewsletterSubmissionRow;
}

/**
 * `can_delete` arrives with the removal migration, so until that has run the
 * column is simply absent from the row. Absent is read as "no": offering a
 * Remove the server would refuse is worse than not offering it at all.
 */
function withCanDelete<Row extends { can_delete?: boolean }>(rows: Row[]) {
  return rows.map((row) => ({ ...row, can_delete: row.can_delete === true }));
}

export async function fetchMyNewsletterSubmissions(): Promise<
  MyNewsletterSubmission[]
> {
  return withCanDelete(
    await listRpc<MyNewsletterSubmission>("list_my_newsletter_submissions"),
  );
}

/** Everything, newest first. Empty for anyone who may not manage. */
export async function fetchAllNewsletterSubmissions(): Promise<
  AllNewsletterSubmission[]
> {
  return withCanDelete(
    await listRpc<AllNewsletterSubmission>("list_all_newsletter_submissions"),
  );
}

/** The story goes for good. The server decides who may; `can_delete` says so. */
export function deleteNewsletterSubmission(submissionId: string) {
  return runRpc("delete_newsletter_submission", {
    p_submission_id: submissionId,
  });
}

/** Marks it read. The reply is optional, and blank leaves any existing one. */
export async function reviewNewsletterSubmission(
  submissionId: string,
  reply?: string | null,
): Promise<NewsletterSubmissionRow> {
  const data = await runRpc("review_newsletter_submission", {
    p_submission_id: submissionId,
    p_reply: reply?.trim() ? reply.trim() : null,
  });
  return data as NewsletterSubmissionRow;
}

/**
 * The system file picker, limited to the document types the bucket accepts.
 *
 * `File.pickFileAsync` arrived with a recent expo-file-system, so a binary
 * built before it exists carries a `File` without the method. Checking for it
 * turns that into a sentence an editor can act on rather than
 * "File.pickFileAsync is not a function". Returns null when they cancel.
 */
export async function pickNewsletterFile(
  mimeTypes: string[] = NEWSLETTER_FILE_MIME_TYPES,
): Promise<PickedNewsletterFile | null> {
  if (typeof File.pickFileAsync !== "function") {
    throw new Error(
      "This copy of the app was built before files could be attached. Rebuild it (npm run ios / npm run android) and try again.",
    );
  }

  const result = await File.pickFileAsync({ mimeTypes });
  if (result.canceled || !result.result) return null;

  const picked = result.result;
  // On Android a SAF pick reports no mime type often enough that trusting it
  // would upload a PDF as octet-stream, which the bucket refuses.
  const mimeType = picked.type?.trim() || mimeTypeFromName(picked.name);
  return { uri: picked.uri, name: picked.name, mimeType };
}

function mimeTypeFromName(name: string) {
  const lower = name.toLowerCase();
  if (lower.endsWith(".doc")) return "application/msword";
  if (lower.endsWith(".docx")) {
    return "application/vnd.openxmlformats-officedocument.wordprocessingml.document";
  }
  return "application/pdf";
}

function extensionFor(file: PickedNewsletterFile) {
  const dot = file.name.lastIndexOf(".");
  const found = dot === -1 ? "" : file.name.slice(dot + 1).toLowerCase();
  if (/^[a-z0-9]{2,5}$/.test(found)) return found;
  return file.mimeType.includes("word") ? "docx" : "pdf";
}

/**
 * Uploads to `newsletter-files/<auth uid>/…` — the storage policy checks that
 * first path segment, so the uploader's own id is the only folder that will be
 * accepted. Returns the public URL to hand to post_newsletter.
 */
export async function uploadNewsletterFile(
  userId: string,
  file: PickedNewsletterFile,
): Promise<string> {
  const supabase = getSupabaseClient();
  const path = `${userId}/${Date.now()}.${extensionFor(file)}`;

  const body = await readLocalFileBytes(file.uri);
  if (body.byteLength > MAX_FILE_BYTES) {
    throw new Error("Please choose a file smaller than 25 MB.");
  }

  const { error } = await supabase.storage
    .from(NEWSLETTER_FILE_BUCKET)
    .upload(path, body, { contentType: file.mimeType, upsert: false });
  if (error) throw error;

  const {
    data: { publicUrl },
  } = supabase.storage.from(NEWSLETTER_FILE_BUCKET).getPublicUrl(path);
  return publicUrl;
}
