import { reportReachability } from "../../lib/connectivity";
import { getSupabaseClient } from "../../lib/supabase";
import { isConnectionProblem } from "../services/format";
import { DEFAULT_DAY_ENDS_AT, DEFAULT_DAY_STARTS_AT } from "./layout";
import type {
  ScheduleFailure,
  SevaScheduleOccurrence,
  TempleProgrammeOccurrence,
  TimetableHours,
} from "./types";

/**
 * The timetable's three reads.
 *
 * Nothing here swallows an error into an empty list, which is the opposite of
 * what the other feature APIs in this app do — and it is deliberate. Migration
 * 0069 raises rather than returning zero rows precisely so that a grid can tell
 * "nobody serves this week" from "you may not see this", and an API that turned
 * the raise back into `[]` would throw that distinction away at the last step.
 * The classification below is the client half of that contract.
 */

/**
 * The permission raises, matched on their wording.
 *
 * `raise exception` is PostgREST code P0001 for every one of them — the window
 * complaints included — so the code alone cannot separate "not for you" from
 * "you asked for two months". The messages are quoted from the migration and
 * asserted against it in the tests, which is what keeps this honest if the
 * temple ever rewords them.
 */
const DENIED_PHRASES = [
  "may read the whole temple",
  "may only read your own seva timetable",
  "Sign in to read",
];

const WINDOW_PHRASES = [
  "timetable window may cover at most",
  "timetable window ends before it begins",
];

/** A migration the temple has not run yet is not a permission problem. */
const MIGRATION_PENDING = ["PGRST202", "42883", "42P01", "PGRST205"];

function errorText(error: unknown): string {
  if (!error) return "";
  if (error instanceof Error) return error.message;
  if (typeof error === "string") return error;
  if (typeof error === "object") {
    const candidate = error as { message?: unknown; details?: unknown };
    if (typeof candidate.message === "string") return candidate.message;
    if (typeof candidate.details === "string") return candidate.details;
  }
  return "";
}

export function classifyScheduleError(error: unknown): ScheduleFailure {
  if (!error) return "unknown";
  const code = (error as { code?: string })?.code ?? "";
  if (MIGRATION_PENDING.includes(code)) return "unavailable";
  if (isConnectionProblem(error)) return "offline";

  const text = errorText(error);
  if (DENIED_PHRASES.some((phrase) => text.includes(phrase))) return "denied";
  if (WINDOW_PHRASES.some((phrase) => text.includes(phrase))) return "window";
  return "unknown";
}

async function callRpc<Row>(
  name: string,
  params: Record<string, unknown>,
): Promise<Row[]> {
  const { data, error } = await getSupabaseClient().rpc(name, params);
  // A Postgres error means the server answered, so the connection is fine; only
  // a transport failure says otherwise.
  reportReachability(!error || !isConnectionProblem(error));
  if (error) throw error;
  return (data ?? []) as unknown as Row[];
}

/**
 * Every seva in a Chicago date window, as dated occurrences.
 *
 * `devoteeId` null is the whole temple and needs the board permission;
 * `auth.uid()` is a devotee's own and is open to everybody; anyone else is the
 * "is she free on Thursday" read and needs the board permission again. The
 * server decides all three — this only passes the argument through.
 */
export function fetchSevaSchedule(
  from: string,
  to: string,
  devoteeId: string | null,
): Promise<SevaScheduleOccurrence[]> {
  return callRpc<SevaScheduleOccurrence>("list_seva_schedule", {
    p_from: from,
    p_to: to,
    p_devotee_id: devoteeId,
  });
}

export function fetchTempleProgramme(
  from: string,
  to: string,
): Promise<TempleProgrammeOccurrence[]> {
  return callRpc<TempleProgrammeOccurrence>("list_temple_programme", {
    p_from: from,
    p_to: to,
  });
}

/**
 * The grid's first and last hour. Falls back to the dials' seeded values rather
 * than failing: these are display only, and a timetable that refuses to draw
 * because one advisory setting could not be read would be a worse answer than
 * one drawn 3:30 to 9:00.
 */
export async function fetchTimetableHours(): Promise<TimetableHours> {
  const fallback = {
    day_starts_at: DEFAULT_DAY_STARTS_AT,
    day_ends_at: DEFAULT_DAY_ENDS_AT,
  };
  try {
    const rows = await callRpc<TimetableHours>("temple_timetable_hours", {});
    const hours = rows[0];
    if (!hours?.day_starts_at || !hours?.day_ends_at) return fallback;
    return hours;
  } catch {
    return fallback;
  }
}
