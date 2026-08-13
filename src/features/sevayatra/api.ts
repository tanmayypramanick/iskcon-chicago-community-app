import { reportReachability } from "../../lib/connectivity";
import { getSupabaseClient } from "../../lib/supabase";
import { isConnectionProblem } from "../services/format";
import type {
  AllSevaHours,
  AllSevaScore,
  DevoteeBadge,
  DevoteeShelfAward,
  MySevaAct,
  MySevaBalanceRow,
  MySevaBreakdownRow,
  MySevaMala,
  MySevaProfileWindow,
  SevaBalanceThresholds,
  SevaActPointsRow,
  SevaBadgeLegendEntry,
  SevaBoardRank,
  SevaConcentrationRow,
  SevaGarlandRow,
  SevaGiftPointsRow,
  SevaNarrownessRow,
  SevaPeriodKind,
  SevaSupporter,
  SevaYatraDevoteeSummary,
} from "./types";

/**
 * Seva Yatra arrives across four migrations, and a temple's database may be
 * behind on any of them.
 *   PGRST202 / 42883 — that function does not exist
 *   42P01 / PGRST205 — that relation does not exist
 * Reads answer with nothing rather than with a failure: a devotee cannot act on
 * a migration that has not been run, and a red error where a quiet empty state
 * belongs reads as the app being broken.
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

/** A set-returning function that answers with at most one row. */
async function oneRpc<Row>(
  name: string,
  params: Record<string, unknown> = {},
): Promise<Row | null> {
  const rows = await listRpc<Row>(name, params);
  return rows[0] ?? null;
}

/**
 * The one write deliberately does not tolerate a missing migration. A toggle
 * that silently does nothing is worse than a toggle that says it could not
 * save, because the devotee's whole question is whether they are on the board.
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

/** Your own standing, hours, giving and pending seva for one period. */
export function fetchMySevaMala(
  periodKind: SevaPeriodKind,
): Promise<MySevaMala | null> {
  return oneRpc<MySevaMala>("my_seva_mala", { p_period_kind: periodKind });
}

/** This week, this month, this calendar year, in one call. */
export function fetchMySevaProfile(): Promise<MySevaProfileWindow[]> {
  return listRpc<MySevaProfileWindow>("my_seva_profile");
}

/** The same three windows, per kind of seva. */
export function fetchMySevaBreakdown(): Promise<MySevaBreakdownRow[]> {
  return listRpc<MySevaBreakdownRow>("my_seva_breakdown");
}

/**
 * Act by act. Both bounds are optional; the server's own default is the
 * trailing ninety days, which is the stretch the scoring measures over.
 */
export function fetchMySevaActs(
  from: string | null = null,
  to: string | null = null,
): Promise<MySevaAct[]> {
  return listRpc<MySevaAct>("my_seva_acts", { p_from: from, p_to: to });
}

/** Your own hours, kind by kind, all the way back. */
export function fetchMySevaBalance(): Promise<MySevaBalanceRow[]> {
  return listRpc<MySevaBalanceRow>("my_seva_balance");
}

/**
 * The public garland, ranked by the whole score or by the seva half of it.
 * Comes back as a single `gathering` row while the congregation is under the
 * minimum cohort, which the caller reads as a flag rather than as emptiness.
 *
 * `p_rank_by` is only sent for the seva board. It is the server's third
 * argument and its default is 'combined', so leaving it off keeps the combined
 * board on the exact two-argument call a temple behind on that migration still
 * answers — where sending it would 404 the board a devotee reads every day.
 * The seva board degrades to empty on such a temple, which is honest: there it
 * genuinely does not exist.
 */
export function fetchSevaGarland(
  periodKind: SevaPeriodKind,
  rankBy: SevaBoardRank = "combined",
  limit = 20,
): Promise<SevaGarlandRow[]> {
  return listRpc<SevaGarlandRow>("list_seva_garland", {
    p_period_kind: periodKind,
    p_limit: limit,
    ...(rankBy === "combined" ? {} : { p_rank_by: rankBy }),
  });
}

/**
 * Everybody who gave in a period, by name and in no order but the alphabet.
 * Public to every signed-in devotee, unlike `list_all_seva_scores`.
 */
export function fetchSevaSupporters(
  periodKind: SevaPeriodKind,
): Promise<SevaSupporter[]> {
  return listRpc<SevaSupporter>("list_seva_supporters", {
    p_period_kind: periodKind,
  });
}

/** Everybody, opted-out devotees included and flagged. app.view_all only. */
export function fetchAllSevaScores(
  periodKind: SevaPeriodKind,
): Promise<AllSevaScore[]> {
  return listRpc<AllSevaScore>("list_all_seva_scores", {
    p_period_kind: periodKind,
  });
}

/**
 * Hours served by everybody in a period (0066). `may_view_whole_seva_board()`
 * only, and unlike the board it names the devotees whose every act is still
 * awaiting somebody.
 *
 * Null — not an empty list — when the database has not had 0066, because the
 * caller has to tell "this temple's function is missing, read the old one"
 * apart from "nobody served this week", and an empty array says the second.
 */
export async function fetchAllSevaHours(
  periodKind: SevaPeriodKind,
): Promise<AllSevaHours[] | null> {
  const { data, error } = await getSupabaseClient().rpc("list_all_seva_hours", {
    p_period_kind: periodKind,
  });
  reportReachability(!error || !isConnectionProblem(error));
  if (error) {
    if (isMigrationPending(error)) return null;
    throw error;
  }
  return (data ?? []) as unknown as AllSevaHours[];
}

/** Returns the flag the server settled on, not the one that was asked for. */
export async function setMyLeaderboardVisibility(
  visible: boolean,
): Promise<boolean> {
  const data = await runRpc("set_my_leaderboard_visibility", {
    p_visible: visible,
  });
  return data === true;
}

/** Devotees carrying a great deal of one seva. app.view_all only. */
export function fetchSevaConcentration(): Promise<SevaConcentrationRow[]> {
  return listRpc<SevaConcentrationRow>("list_seva_concentration");
}

/** Devotees whose seva sits in one category. app.view_all only. */
export function fetchSevaNarrowness(): Promise<SevaNarrownessRow[]> {
  return listRpc<SevaNarrownessRow>("list_seva_narrowness");
}

/** What the two care lists are measured against. app.view_all only. */
export function fetchSevaBalanceThresholds(): Promise<SevaBalanceThresholds | null> {
  return oneRpc<SevaBalanceThresholds>("seva_balance_thresholds");
}

/**
 * Where a window's points came from, act by act and gift by gift (0062).
 *
 * Both bounds are optional and the server's own default is the trailing ninety
 * days, but callers pass a period's own bounds where they have them: only a
 * window that is the whole of the period it is priced against sums to the
 * points beside the devotee's name, and the rows say which case they are in.
 */
export function fetchMySevaActPoints(
  from: string | null = null,
  to: string | null = null,
): Promise<SevaActPointsRow[]> {
  return listRpc<SevaActPointsRow>("my_seva_act_points", {
    p_from: from,
    p_to: to,
  });
}

export function fetchMyGivingPoints(
  from: string | null = null,
  to: string | null = null,
): Promise<SevaGiftPointsRow[]> {
  return listRpc<SevaGiftPointsRow>("my_giving_points", {
    p_from: from,
    p_to: to,
  });
}

/** The same two, about one devotee. app.view_all only; empty for anybody else. */
export function fetchDevoteeSevaActPoints(
  devoteeId: string,
  from: string | null = null,
  to: string | null = null,
): Promise<SevaActPointsRow[]> {
  return listRpc<SevaActPointsRow>("list_devotee_seva_act_points", {
    p_devotee_id: devoteeId,
    p_from: from,
    p_to: to,
  });
}

export function fetchDevoteeGivingPoints(
  devoteeId: string,
  from: string | null = null,
  to: string | null = null,
): Promise<SevaGiftPointsRow[]> {
  return listRpc<SevaGiftPointsRow>("list_devotee_giving_points", {
    p_devotee_id: devoteeId,
    p_from: from,
    p_to: to,
  });
}

/**
 * The badges on a devotee's profile right now (0063). Readable by any signed-in
 * devotee, which is why it carries no numbers at all.
 */
export function fetchDevoteeBadges(devoteeId: string): Promise<DevoteeBadge[]> {
  return listRpc<DevoteeBadge>("list_devotee_badges", {
    p_devotee_id: devoteeId,
  });
}

/**
 * Everything they ever earned, current or long since off the profile. Their own
 * or, with app.view_all, anybody's. Read through the function rather than off
 * `devotee_awards` so that `is_current` is the server's own predicate — the app
 * must never work out for itself which badges are still public.
 */
export function fetchDevoteeAwardShelf(
  devoteeId: string,
): Promise<DevoteeShelfAward[]> {
  return listRpc<DevoteeShelfAward>("list_devotee_award_shelf", {
    p_devotee_id: devoteeId,
  });
}

/**
 * What there is to earn and what earns it (0066), so the President can reword
 * a badge without an app release. Every active definition, gifts included, so
 * the caller has to tell the two apart before drawing anything.
 */
export function fetchSevaBadgeLegend(): Promise<SevaBadgeLegendEntry[]> {
  return listRpc<SevaBadgeLegendEntry>("list_seva_badge_legend");
}

/**
 * Why one name is where it is on the board, for one period (0066). Readable
 * about anybody the board already names; the server withholds what this caller
 * may not know rather than the app deciding.
 */
export function fetchSevaYatraDevoteeSummary(
  devoteeId: string,
  periodKind: SevaPeriodKind,
): Promise<SevaYatraDevoteeSummary | null> {
  return oneRpc<SevaYatraDevoteeSummary>("seva_yatra_devotee_summary", {
    p_devotee_id: devoteeId,
    p_period_kind: periodKind,
  });
}

/**
 * Clear a Seva Care row once it has been handled (0066).
 *
 * Unlike the visibility toggle this tolerates a missing migration and reports
 * it, because the caller hides the row locally either way: a President who has
 * just had the conversation should not be shown the row again this sitting,
 * and `false` only means it will be back tomorrow.
 */
export async function dismissSevaCareRow(
  devoteeId: string,
  serviceTypeId: string | null,
): Promise<boolean> {
  const { error } = await getSupabaseClient().rpc("dismiss_seva_care_row", {
    p_devotee_id: devoteeId,
    p_service_type_id: serviceTypeId,
  });
  reportReachability(!error || !isConnectionProblem(error));
  if (error) {
    if (isMigrationPending(error)) return false;
    throw error;
  }
  return true;
}
