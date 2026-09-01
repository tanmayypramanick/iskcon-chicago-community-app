import { reportReachability } from "../../lib/connectivity";
import { getSupabaseClient } from "../../lib/supabase";
import { isConnectionProblem } from "../services/format";
import type {
  SuggestedAnnouncement,
  TodaysBirthday,
  UpcomingBirthday,
} from "./types";

/**
 * Birthday prompts arrive with their own migration, which a temple's database
 * may not have had applied yet.
 *   PGRST202 / 42883 — that function does not exist
 *   42P01 / PGRST205 — that relation does not exist
 * The read treats that as "nobody is celebrating today" rather than as a
 * failure: the card simply does not draw, which is what it does on most days
 * anyway, and a red error where nothing belongs reads as the app being broken.
 */
function isMigrationPending(error: { code?: string } | null) {
  return ["PGRST202", "42883", "42P01", "PGRST205"].includes(error?.code ?? "");
}

/**
 * Whoever is celebrating today in Chicago, by name. The function decides both
 * "today" and "who may know" for itself — it returns an empty set to everybody
 * without `app.view_all` — so there is nothing for a client to work out here.
 */
export async function fetchTodaysBirthdays(): Promise<TodaysBirthday[]> {
  const { data, error } = await getSupabaseClient().rpc("todays_birthdays");
  // A transport failure means the server is unreachable; a Postgres error
  // means it answered, so the connection is fine.
  reportReachability(!error || !isConnectionProblem(error));
  if (error) {
    if (isMigrationPending(error)) return [];
    throw error;
  }
  return (data ?? []) as unknown as TodaysBirthday[];
}

/**
 * The birthdays coming up, nearest first. Same audience and same silence as
 * the list above: the server returns an empty set rather than an error to
 * anybody without `app.view_all`, so there is nothing to decide here.
 */
export async function fetchUpcomingBirthdays(
  days = 60,
): Promise<UpcomingBirthday[]> {
  const { data, error } = await getSupabaseClient().rpc("upcoming_birthdays", {
    p_days: days,
  });
  reportReachability(!error || !isConnectionProblem(error));
  if (error) {
    if (isMigrationPending(error)) return [];
    throw error;
  }
  return (data ?? []) as unknown as UpcomingBirthday[];
}

/**
 * The wording the temple would use, for a person to edit before posting.
 *
 * Deliberately tolerates nothing, including a missing migration: unlike the
 * list above this is nobody's idle read, the server raises for a caller who
 * may not have it, and whoever just tapped "wish them" has to be told why no
 * composer opened rather than watching the tap do nothing.
 */
export async function fetchSuggestedBirthdayAnnouncement(
  devoteeId: string,
): Promise<SuggestedAnnouncement> {
  const { data, error } = await getSupabaseClient().rpc(
    "suggested_birthday_announcement",
    { p_devotee_id: devoteeId },
  );
  reportReachability(!error || !isConnectionProblem(error));
  if (error) throw error;

  // A `returns table` function answers with rows; this one always returns
  // exactly one, so no row at all means something is wrong with the deployment
  // rather than with the devotee that was asked about.
  const suggestion = (data as SuggestedAnnouncement[] | null)?.[0];
  if (!suggestion) {
    throw new Error("The temple’s birthday wording could not be read.");
  }
  return suggestion;
}
