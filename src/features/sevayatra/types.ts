/**
 * Shapes returned by the Seva Yatra migrations (202608040055, 0057, 0058, and
 * 0059's rescoring).
 *
 * The feature is called Seva Yatra in the app; the SQL is still named
 * `seva_mala` and stays that way, because those functions are deployed. Type
 * names here mirror the RPC they decode so the two can be matched by eye.
 *
 * The server decides what a devotee may know about anybody else: the public
 * board returns a position and an award tier and nothing else, and every number
 * a devotee can see about themselves comes from a function that only ever
 * answers about the caller. Nothing in this file reconstructs what was withheld.
 */

import {
  dateKeyToInstant,
  donationKindLabel,
  formatCents,
  type DonationKind,
  type DonationRecurrence,
} from "../donations/types";

export { donationKindLabel, formatCents };

/** What the scoring ranks over. `year` is a reading window and is never ranked. */
export type SevaPeriodKind = "week" | "month" | "lifetime";
export type SevaWindowKind = "week" | "month" | "year";

/**
 * What a devotee may choose to read over, which is a longer list than what the
 * scoring ranks over. The temple asked for the same four everywhere a period is
 * picked; the year has no score behind it and says so rather than being left
 * out of the chooser, because a missing choice reads as an oversight.
 */
export type SevaRangeKind = SevaPeriodKind | "year";

/**
 * 0057 widened `my_seva_mala` with the two pending columns; a temple still on
 * 0055 answers without them, so they are optional rather than assumed.
 */
export type MySevaMala = {
  period_id: string;
  period_kind: SevaPeriodKind;
  period_start: string;
  period_end: string;
  score: number;
  seva_minutes: number;
  /**
   * 0066, deployed. Minutes a devotee actually stood there and acts they stood
   * there for, credited or not — a different question from `seva_minutes`, the
   * minutes the scoring paid for. Hours are read from these and points from the
   * credited figure, which is the whole of why 0066 added them: a devotee whose
   * six evenings are all waiting on somebody else's confirmation was being told
   * they had served nothing.
   *
   * Not optional. The server coalesces both to zero and always sends them, and
   * a screen that fell back to the credited figure would be reintroducing the
   * conflation by another route.
   */
  served_minutes: number;
  served_acts: number;
  seva_acts: number;
  pending_acts?: number | null;
  pending_minutes?: number | null;
  giving_cents: number;
  gifts: number;
  /** Null while the congregation is still gathering. */
  standing: number | null;
  board_standing: number | null;
  cohort_size: number;
  gathering: boolean;
  leaderboard_visible: boolean;
  awards_earned: number;
};

/** One row of `my_seva_profile` — this week, this month, this calendar year. */
export type MySevaProfileWindow = {
  window_kind: SevaWindowKind;
  window_start: string;
  window_end: string;
  acts: number;
  hours: number;
  counted_acts: number;
  counted_hours: number;
  pending_acts: number;
  pending_hours: number;
  not_served_acts: number;
  not_served_hours: number;
  recurring_acts: number;
  recurring_hours: number;
  giving_cents: number;
  gifts: number;
};

export type MySevaBreakdownRow = {
  window_kind: SevaWindowKind;
  window_start: string;
  window_end: string;
  service_type_id: string | null;
  seva_name: string;
  acts: number;
  hours: number;
  counted_acts: number;
  counted_hours: number;
  pending_acts: number;
  pending_hours: number;
  not_served_acts: number;
  not_served_hours: number;
  recurring_acts: number;
  recurring_hours: number;
};

export type SevaPointsStatus =
  | "counted"
  | "awaiting_completion"
  | "awaiting_verification"
  | "awaiting_confirmation"
  | "not_served";

/**
 * One act of seva. `points_note` is written by the server for exactly this
 * screen — it names who has to do what next — so it is rendered as it arrives
 * rather than being restated in wording of our own.
 */
export type MySevaAct = {
  assignment_id: string;
  service_instance_id: string | null;
  service_type_id: string | null;
  seva_name: string;
  occurred_on: string;
  weekday: string;
  started_at_local: string | null;
  minutes: number;
  hours: number;
  is_recurring: boolean;
  assignment_status: string;
  verification: string;
  attendance: string;
  points_status: SevaPointsStatus;
  points_note: string | null;
};

/**
 * How the public garland may be ordered. `list_seva_garland` raises on anything
 * that is neither — it refuses to fall through to the combined board — so this
 * union is the server's own `p_rank_by` and not a superset of it.
 */
export type SevaBoardRank = "combined" | "seva";

/**
 * What a devotee may choose to look at on the Leaderboard. Two of the three are
 * the garland ranked two ways; the third is not a ranking at all and comes from
 * its own function, which is why "supporters" must never be sent as a rank.
 */
export type SevaBoardMode = SevaBoardRank | "supporters";

export const sevaBoardModes: { key: SevaBoardMode; label: string }[] = [
  { key: "combined", label: "Seva & Giving" },
  { key: "seva", label: "Seva only" },
  { key: "supporters", label: "Supporters" },
];

/** The rank to ask the garland for, or null where the mode is not a garland. */
export function garlandRankForMode(mode: SevaBoardMode): SevaBoardRank | null {
  return mode === "supporters" ? null : mode;
}

/**
 * What the Leaderboard's own chooser calls a board. Read rather than restated
 * wherever a screen has to name which board a figure belongs to, so the two
 * cannot come to call the same board different things.
 */
export function sevaBoardModeLabel(mode: SevaBoardMode) {
  return sevaBoardModes.find((entry) => entry.key === mode)?.label ?? "";
}

/**
 * A row of `list_seva_garland`. Position, published points and tier: the score
 * behind them is withheld, because a raw score inverts to who gives.
 *
 * `points` is `seva_mala_points()` of whichever basis the mode ranked by, and
 * the server publishes it to every signed-in devotee — the same integer the
 * drill-down publishes. Nothing here reconstructs it from a score, and no
 * caller may substitute a figure of its own: an app.view_all read standing in
 * for this one is how a board comes to show numbers to the temple's officers
 * and blanks to everybody else.
 *
 * A single row with `gathering` true and everything else null is the server
 * saying the period has too few devotees to publish. That is a different thing
 * from an empty board and must not look the same.
 */
export type SevaGarlandRow = {
  standing: number | null;
  devotee_id: string | null;
  devotee_name: string | null;
  devotee_photo_url: string | null;
  points: number | null;
  tier: SevaAwardTier | null;
  is_you: boolean;
  gathering: boolean;
};

/**
 * A row of `list_seva_supporters` — everybody who gave in the period, by name,
 * and deliberately nothing else. No amount, no count, no order but the
 * alphabet: the server sorts by name precisely so that a supporters list cannot
 * be read as a ranking with the figures taken off.
 *
 * Readable by every signed-in devotee, which is the whole point of it: 0060
 * already publishes who gave, and reading it through `list_all_seva_scores`
 * would have made a public list of thanks visible only to the two officers.
 */
export type SevaSupporter = {
  devotee_id: string;
  devotee_name: string;
  devotee_photo_url: string | null;
};

/**
 * `list_all_seva_scores` — the whole board, for whoever `may_view_whole_seva_board()`
 * lets in. Opted-out devotees are flagged rather than dropped.
 *
 * Two callers, not one. That predicate is `app.view_all` OR
 * `services.manage_recurring`, so a Community Head reads this function too —
 * and every cash-shaped column is gated on the narrower `may_view_all_giving()`
 * and arrives NULL for them. `score` is one of those columns: it is the raw norm
 * the giving half can be inverted out of.
 *
 * So nothing may work points out from `score`. 0067 publishes `points` for
 * exactly this reason — the same integer the garland prints, ungated — and a
 * screen that ran `sevaPoints(score)` instead would show the President a board
 * and a Community Head a column of noughts.
 */
export type AllSevaScore = {
  standing: number;
  devotee_id: string;
  devotee_name: string;
  /** Published to every caller of this function. The figure to show. */
  points: number;
  /** `may_view_all_giving()`'s, and null to everybody else. Never a zero. */
  score: number | null;
  seva_minutes: number;
  seva_acts: number;
  giving_cents: number | null;
  gifts: number | null;
  seva_norm: number | null;
  giving_norm: number | null;
  is_hidden: boolean;
  /** True where the five figures above came back withheld rather than nought. */
  giving_withheld: boolean;
};

/**
 * `list_all_seva_hours(p_period_kind)` (0066) — hours SERVED for every devotee
 * in the current period, for the three people who may read the whole board.
 *
 * A companion to `list_all_seva_scores` rather than a widening of it, because
 * 0064 pins that function's columns and it can never gain a served figure. Two
 * differences matter here: `served_minutes` is uncapped, and the function full
 * outer joins, so a devotee `period_scores` has no row for at all is still on
 * the list — flagged `awaiting_only`, with the hours nobody has confirmed yet.
 * No score and no norm: this read carries hours and nothing to rank them by.
 */
export type AllSevaHours = {
  devotee_id: string;
  devotee_name: string;
  period_id: string;
  period_start: string;
  period_end: string;
  served_minutes: number;
  served_acts: number;
  credited_minutes: number;
  credited_acts: number;
  awaiting_minutes: number;
  awaiting_acts: number;
  points: number;
  /** True where the scoring has written them no row at all — every act pending. */
  awaiting_only: boolean;
  is_hidden: boolean;
};

/** `my_seva_balance` — the devotee's own hours per kind of seva. A thank-you. */
export type MySevaBalanceRow = {
  service_type_id: string | null;
  seva_name: string;
  category: string | null;
  hours_this_month: number;
  hours_this_quarter: number;
  hours_all_time: number;
  acts_all_time: number;
  first_served_on: string;
  last_served_on: string;
};

export type SevaConcentrationRow = {
  devotee_id: string;
  devotee_name: string;
  service_type_id: string | null;
  seva_name: string;
  category: string | null;
  hours_per_week: number;
  hours_trailing_quarter: number;
  /**
   * 0066. Chicago's own calendar week and month. Both optional: a temple behind
   * on 0066 sends neither, and a row without them prints the quarter alone
   * rather than dividing one out of it.
   */
  hours_this_week?: number | null;
  hours_this_month?: number | null;
  consecutive_weeks: number;
  share_of_their_seva: number;
  weekly_hours_vs_median: number;
  share_vs_congregation: number;
  pronouncedness: number;
  first_served_on: string;
  last_served_on: string;
  min_hours_used: number;
  min_weeks_used: number;
  note: string;
};

export type SevaNarrownessRow = {
  devotee_id: string;
  devotee_name: string;
  category: string;
  hours_trailing_quarter: number;
  hours_this_week?: number | null;
  hours_this_month?: number | null;
  category_share: number;
  untouched_categories: string[] | null;
  untouched_share_of_congregation: number;
  min_hours_used: number;
  min_share_used: number;
  note: string;
};

export type SevaBalanceThresholds = {
  window_starts_on: string;
  window_ends_on: string;
  devotees_considered: number;
  gathering: boolean;
  median_weekly_hours: number | null;
  median_total_hours: number | null;
  median_top_share: number | null;
  weekly_hours_threshold: number | null;
  consecutive_weeks_threshold: number | null;
  top_category_share_threshold: number | null;
  congregation_categories: string[] | null;
};

export type SevaAwardTier =
  "recognition" | "token_of_appreciation" | "maha_prasad" | "garland";

/**
 * `list_devotee_badges` — the badges a devotee's profile shows right now, which
 * any signed-in devotee may read. Deliberately carries no score, no place, no
 * hour and no cent: a badge is a public thing, and the numbers behind it are
 * not.
 *
 * A badge leaves this list when the next period's awards are given. 0063 works
 * that out from the periods rather than storing an expiry, so nothing here is
 * ever "revoked" — it simply stops being the current one.
 */
export type DevoteeBadge = {
  award_id: string;
  award_code: string;
  title: string;
  description: string;
  tier: SevaAwardTier;
  garland_kind: string | null;
  period_kind: string;
  period_start: string;
  period_end: string;
  awarded_on: string;
};

/**
 * `list_devotee_award_shelf` — everything a devotee ever earned, for themselves
 * and for `app.view_all`. Nothing is ever removed from it.
 *
 * `is_current` is the same predicate the public list applies. False means only
 * that other devotees no longer see it on the profile; it never means the award
 * was lost, and nothing rendering this may say otherwise.
 */
export type DevoteeShelfAward = {
  award_id: string;
  award_code: string;
  title: string;
  description: string;
  tier: SevaAwardTier;
  garland_kind: string | null;
  rule_kind: string | null;
  /** Null for an award given outside any scored period. */
  period_kind: string | null;
  period_start: string | null;
  period_end: string | null;
  awarded_on: string;
  awarded_by: string | null;
  citation: string | null;
  fulfilled_on: string | null;
  fulfilment_note: string | null;
  is_current: boolean;
};

/**
 * The columns 0062 hangs on every attribution row: which window was priced,
 * what it was priced against, how the window's points split, and the sentence
 * saying the per-row figures are shares of a non-linear total rather than
 * addends.
 *
 * One server function writes `attribution` for both lists so the two can never
 * come to say different things, which is also why it is typed once here and why
 * no screen restates it in wording of its own.
 */
export type SevaPointsWindow = {
  seva_points: number;
  giving_points: number;
  total_points: number;
  window_from: string;
  window_to: string;
  scaled_against: string;
  /**
   * True when the window is the whole of the period it was scaled against —
   * the only case in which the rows sum to the points beside the devotee's name.
   */
  is_whole_period: boolean;
  attribution: string;
};

/** One act, with the share of the window's seva points it accounts for. */
export type SevaActPointsRow = SevaPointsWindow & {
  assignment_id: string;
  service_instance_id: string | null;
  seva_name: string;
  occurred_on: string;
  weekday: string;
  started_at_local: string | null;
  minutes: number;
  credited_minutes: number;
  counted_minutes: number;
  points_status: SevaPointsStatus;
  points_note: string | null;
  share: number;
  points: number;
};

/** One gift, likewise. Acts that earned nothing are listed at zero, with why. */
export type SevaGiftPointsRow = SevaPointsWindow & {
  donation_id: string;
  received_on: string;
  weekday: string;
  amount_cents: number;
  currency: string;
  kind: DonationKind;
  recurrence: DonationRecurrence | null;
  sponsorship_type_name: string | null;
  share: number;
  points: number;
};

const tierLabels: Record<SevaAwardTier, string> = {
  recognition: "Recognition",
  token_of_appreciation: "Token of appreciation",
  maha_prasad: "Maha prasad",
  garland: "Garland",
};

export function sevaTierLabel(tier: SevaAwardTier | null | undefined) {
  return tier ? tierLabels[tier] : null;
}

/**
 * The four tiers, drawn as flowers on a garland rather than as places. The
 * order here is the order the temple gives them in, not a ranking of devotees.
 */
export const sevaTierIcons: Record<
  SevaAwardTier,
  "trophy" | "gift" | "ribbon" | "leaf"
> = {
  garland: "trophy",
  maha_prasad: "gift",
  token_of_appreciation: "ribbon",
  recognition: "leaf",
};

export function isPendingSeva(status: SevaPointsStatus) {
  return (
    status === "awaiting_completion" ||
    status === "awaiting_verification" ||
    status === "awaiting_confirmation"
  );
}

/**
 * Hours, as a devotee would say them. Never "1.00 hours", never "0 hours" for
 * forty minutes of seva that they actually did.
 */
export function formatHours(hours: number | null | undefined) {
  const value = Number(hours ?? 0);
  if (!Number.isFinite(value) || value <= 0) return "0 hours";
  if (value < 1) {
    const minutes = Math.round(value * 60);
    return `${minutes} min`;
  }
  const rounded = Math.round(value * 10) / 10;
  return `${Number.isInteger(rounded) ? rounded : rounded.toFixed(1)} hour${
    rounded === 1 ? "" : "s"
  }`;
}

export function sevaCountLabel(
  count: number,
  singular: string,
  plural = `${singular}s`,
) {
  return `${count} ${count === 1 ? singular : plural}`;
}

/** "Mon, Aug 3" from a bare `date` column, read as UTC so no day slides. */
export function formatSevaDate(dateKey: string) {
  return new Intl.DateTimeFormat("en-US", {
    timeZone: "UTC",
    weekday: "short",
    month: "short",
    day: "numeric",
  }).format(dateKeyToInstant(dateKey));
}

/** "August 3, 2026" — used where the year matters, like a first-ever seva. */
export function formatSevaLongDate(dateKey: string) {
  return new Intl.DateTimeFormat("en-US", {
    timeZone: "UTC",
    month: "long",
    day: "numeric",
    year: "numeric",
  }).format(dateKeyToInstant(dateKey));
}

export function formatSevaRange(from: string, to: string) {
  return `${formatSevaDate(from)} – ${formatSevaDate(to)}`;
}

export const sevaWindowLabels: Record<SevaWindowKind, string> = {
  week: "This week",
  month: "This month",
  year: "This year",
};

/**
 * The top of the scale, in points. 0055 clamped every score at 1.0, so a
 * thousand was both the unit and the ceiling and the two were easy to confuse.
 * 0062 replaced the clamp with a soft cap at `1 + seva_mala.balance_beta`, and
 * a live period's score may now pass 1.0, so anything drawing a scale must draw
 * it against this rather than against the unit.
 *
 * 0064 moved `balance_beta` to 0.3, which is where `seva_mala_norm_ceiling()`
 * reads it from — so the server's ceiling is 1300 and has been since. The 1500
 * this used to hold was 0062's beta of 0.5, two hundred points above anything
 * the server will ever publish.
 */
export const SEVA_POINTS_CEILING = 1300;

/** The interval the server publishes points in, and rounds them to. */
const SEVA_POINTS_STEP = 10;

/** A norm of 1.0 is a thousand points. The server's unit, not a scale factor. */
const SEVA_POINTS_UNIT = 1000;

/**
 * `round(value × 10^places)`, half away from zero, done on the number's own
 * decimal digits rather than on the double behind them.
 *
 * `Math.round(value * 100)` is off by a whole step wherever the decimal is not
 * a binary fraction: a score of 1.005 is held as 1.00499…, so it rounds down to
 * 1000 points where the server — which prices points in `numeric`, and rounds
 * away from zero — publishes 1010 for the same devotee. Both figures now sit on
 * one screen, so they have to agree exactly rather than usually.
 */
function roundScaled(value: number, places: number) {
  const [mantissa, exponent = "0"] = Math.abs(value).toString().split("e");
  const [whole, fraction = ""] = mantissa.split(".");
  const digits = whole + fraction;
  // Where the decimal point falls in `digits` once the scaling is applied.
  const point = digits.length + Number(exponent) - fraction.length + places;
  if (point >= digits.length) return Number(digits.padEnd(point, "0"));
  if (point < 0) return 0;
  return (
    Number(digits.slice(0, point) || "0") +
    ((digits[point] ?? "0") >= "5" ? 1 : 0)
  );
}

/**
 * The server's score is a ratio against what this congregation itself did.
 * "0.42" is a statistic; the temple asked for a game profile, and a game shows
 * points. Multiplying by a thousand changes nothing about the ordering or the
 * fairness — it is a unit.
 *
 * This is `seva_mala_points` restated, step for step, because a screen that
 * cannot read a published integer has to arrive at the same one the server
 * would have published. Prefer the server's own figure wherever there is one:
 * the board, the drill-down and 0062's attribution rows all carry it, and this
 * is only for the reads that carry a score and nothing else.
 */
export function sevaPoints(score: number | null | undefined) {
  const value = Number(score ?? 0);
  if (!Number.isFinite(value) || value <= 0) return 0;
  // `least(ceiling, norm)` first, exactly as the server orders it.
  const capped = Math.min(value, SEVA_POINTS_CEILING / SEVA_POINTS_UNIT);
  return Math.max(
    SEVA_POINTS_STEP,
    // norm × 1000 ÷ 10, rounded, × 10 — which is two decimal places.
    roundScaled(capped, 2) * SEVA_POINTS_STEP,
  );
}

/** Points with a thousands separator, which they reach in the lifetime board. */
export function formatSevaPoints(score: number | null | undefined) {
  return sevaPoints(score).toLocaleString("en-US");
}

/** The four, in the order the temple says them. */
export const sevaRanges: SevaRangeKind[] = [
  "week",
  "month",
  "year",
  "lifetime",
];

export const sevaRangeLabels: Record<SevaRangeKind, string> = {
  week: "This week",
  month: "This month",
  year: "This year",
  lifetime: "All time",
};

/** Short enough that all four sit on one line of a 320dp phone. */
export const sevaRangeChips: Record<SevaRangeKind, string> = {
  week: "Week",
  month: "Month",
  year: "Year",
  lifetime: "All time",
};

/**
 * The range a devotee is reading and the period the scoring ranks over are not
 * the same thing: the calendar year is a reading window with no score behind
 * it, so it maps to nothing rather than to `lifetime`.
 *
 * Kept now that 0066 is deployed, though it is no longer load-bearing against
 * the server: `seva_mala_periods.period_kind` only ever holds week, month or
 * lifetime, so 'year' matches nothing and both `my_seva_mala` and
 * `seva_yatra_devotee_summary` answer with zero rows rather than raising. It
 * stays because an empty answer is not the same sentence as "a year is a read
 * rather than a race" — an unasked question lets the screen say the second,
 * where a null row would be indistinguishable from a devotee who did nothing —
 * and because a call whose answer is known to be empty is a round trip on a
 * phone for nothing.
 */
export function scoredPeriodForRange(
  range: SevaRangeKind,
): SevaPeriodKind | null {
  return range === "year" ? null : range;
}

/** Null for all time, which `my_seva_profile` has no window for. */
export function profileWindowForRange(
  range: SevaRangeKind,
): SevaWindowKind | null {
  return range === "lifetime" ? null : range;
}

/**
 * The figures a Seva Care row may honestly print.
 *
 * The trailing quarter is the window both lists are actually measured over, and
 * it is the one figure on the row that cannot mislead: a devotee is named here
 * because of a quarter, so it is never nought — where a real week very often is,
 * and a headline nought on a burnout row reads as a fault of the devotee's.
 *
 * The calendar week and month arrive with 0066 and only on the concentration
 * list; `list_seva_narrowness` is 0058's function and still carries the quarter
 * alone. Those rows used to have a week and a month divided out of the quarter
 * and printed under "A week" and "A month" — figures the server never sent,
 * that nothing else on the screen could be reconciled against. A row that has
 * the two says them; a row that does not now says nothing.
 */
export function careRowHours(row: {
  hours_this_week?: number | null;
  hours_this_month?: number | null;
  hours_trailing_quarter: number;
}): { quarter: number; week: number | null; month: number | null } {
  const week = row.hours_this_week;
  const month = row.hours_this_month;
  const exact = week != null && month != null;
  return {
    quarter: Number(row.hours_trailing_quarter ?? 0),
    week: exact ? Number(week) : null,
    month: exact ? Number(month) : null,
  };
}

/**
 * One entry of the badge legend: what a badge is, and what earns it. 0066
 * publishes this so the temple can reword a badge without an app release.
 */
export type SevaBadgeLegendEntry = {
  code: string;
  title: string;
  /** What the badge means. */
  description: string;
  /** What earns it, in the temple's own words. */
  earned_by: string;
  tier: SevaAwardTier;
  /** Which period it is judged over. `lifetime` for the two personal ones. */
  period_kind: SevaPeriodKind;
};

/**
 * The ten badges the temple approved, transcribed from the `award_definitions`
 * seed in 202608040066 — five for a week, five for a month, ten different
 * reasons.
 *
 * Carried in the app as well as read from the server because the legend has to
 * be on the screen the instant it is opened, and a legend that appears only
 * once you have a badge is not a legend. 0066 is deployed, so this is now the
 * first paint rather than the whole of what a devotee sees: the wording is the
 * server's word for word — asserted against the migration itself in
 * `__tests__/legend.test.tsx` — so nothing visibly rewrites itself a beat after
 * opening, and the President's own wording still wins the moment it answers.
 */
export const sevaBadgeLegend: SevaBadgeLegendEntry[] = [
  {
    code: "weekly_shrama_dana",
    title: "Śrama-dāna",
    description:
      "The gift of labour. For the devotee who gave the temple the most of their hours this week.",
    earned_by:
      "Serving more hours than anybody else in the week. Hours count from the moment you serve them, whether or not the confirmation has caught up.",
    tier: "token_of_appreciation",
    period_kind: "week",
  },
  {
    code: "weekly_nitya_seva",
    title: "Nitya-sevā",
    description:
      "Unceasing service. Not the most hours — the most days. The temple was not empty of you.",
    earned_by:
      "Turning up on at least three different days in one week, and on as many days as the most regular part of the congregation.",
    tier: "recognition",
    period_kind: "week",
  },
  {
    code: "weekly_arunodaya",
    title: "Aruṇodaya",
    description:
      "Daybreak. The first light on a seva that was still waiting for somebody.",
    earned_by:
      "Being the first devotee in the week to take up one of the seva the temple finds hardest to fill.",
    tier: "token_of_appreciation",
    period_kind: "week",
  },
  {
    code: "weekly_dhairya",
    title: "Dhairya",
    description:
      "Perseverance. The same seva, week after week, with nobody watching.",
    earned_by:
      "Holding one seva for at least four unbroken weeks, and for as long a run as the steadiest part of the congregation.",
    tier: "recognition",
    period_kind: "week",
  },
  {
    code: "weekly_ruci",
    title: "Ruci",
    description:
      "A new taste. The stage where devotion stops being duty and starts being appetite.",
    earned_by: "Serving a kind of seva you had never served before.",
    tier: "recognition",
    period_kind: "week",
  },
  {
    code: "monthly_navadha",
    title: "Navadhā",
    description:
      "The ninefold. Devotion has many limbs, and this devotee has used more than one of them.",
    earned_by:
      "Serving in at least three different categories of the temple's work in one month.",
    tier: "recognition",
    period_kind: "month",
  },
  {
    code: "monthly_dhruva_dana",
    title: "Dhruva-dāna",
    description:
      "The unwavering gift. Dhruva did not move, and neither does this.",
    earned_by:
      "Giving in at least three separate weeks of the month. How much never enters it.",
    tier: "recognition",
    period_kind: "month",
  },
  {
    code: "monthly_tan_mana_dhana",
    title: "Tan-mana-dhana",
    description:
      "Body, mind and wealth — Narottama's three, offered together rather than one instead of another.",
    earned_by:
      "Reaching the congregation's middle devotee in both hours served and giving, in the same month.",
    tier: "token_of_appreciation",
    period_kind: "month",
  },
  {
    code: "monthly_brahma_muhurta",
    title: "Brāhma-muhūrta",
    description:
      "The hour before dawn. The temple is loveliest and emptiest then, and somebody is always there.",
    earned_by:
      "Serving more of the month's minutes before seven in the morning than anybody else.",
    tier: "token_of_appreciation",
    period_kind: "month",
  },
  {
    code: "monthly_bhakti_lata",
    title: "Bhakti-latā",
    description:
      "The creeper of devotion, which grows. Measured against nobody but your own past.",
    earned_by:
      "Serving more hours this month than in any month you have served before.",
    tier: "recognition",
    period_kind: "month",
  },
];

/** Where the seed order of the ten is remembered, for `sevaLegendBadges`. */
const badgeSeedOrder = new Map(
  sevaBadgeLegend.map((badge, index) => [badge.code, index]),
);

/**
 * The gifts the temple seeded into a badge tier.
 *
 * The tier is the line everywhere else, and it is the server's own line — but
 * 0063 gave the Mystery Gift `token_of_appreciation`, so it arrived in the
 * badges half and a devotee read "Mystery Gift" under a heading promising to
 * say what earns it. A gift is a thing somebody has to make and hand over,
 * whatever tier it was filed under, so these two codes cross to the gifts.
 */
const giftCodes = new Set(["mystery_gift", "weekly_mystery_gift"]);

/**
 * The badges out of a legend that carries badges and gifts in one list.
 *
 * `list_seva_badge_legend()` answers with every active definition — the ten,
 * and every gift the temple has offered since 0055. Those gift rows say in as
 * many words who receives one and when ("for the three devotees who carried
 * this week", "for the devotee at the top of the month"), which is exactly what
 * the temple asked the app never to print beside a gift. So the tier is the
 * line, and it is the migration's own line: 'garland' and 'maha_prasad' are the
 * two tiers 0066 refused to reuse for a badge because they mean "a physical
 * object from the altar that somebody has to make and hand over". Those go to
 * the gift half below, which says what they are and nothing else; the fourteen
 * Deity garland rows leave with them, so the seven stay one lateral entry
 * instead of becoming a column of fourteen.
 *
 * The tier is not quite the whole line: see `giftCodes` for the gift the temple
 * filed under a badge tier, which crosses back to the gift half.
 *
 * The remaining badges are ordered with the ten first, in the order the phone
 * already drew them from `sevaBadgeLegend`, so the server answering widens the
 * list downwards rather than reshuffling what a devotee is reading.
 *
 * One badge to a title. The temple seeds several of these once for the week and
 * again for the month — Recognition and Token of Appreciation are each two
 * definitions on the deployed database — and a legend answering
 * "what is there" with the same name twice reads as a fault in the app rather
 * than as a badge that can be earned in two periods. The period is deliberately
 * not on a legend entry, so the two rows differ in nothing a devotee can see.
 * Seed order decides which survives, so the ten the temple approved always win
 * a collision and the wording never depends on the order rows arrived in.
 */
export function sevaLegendBadges(
  entries: readonly SevaBadgeLegendEntry[],
): SevaBadgeLegendEntry[] {
  const ordered = entries
    .filter(
      (entry) =>
        entry.tier !== "garland" &&
        entry.tier !== "maha_prasad" &&
        !giftCodes.has(entry.code),
    )
    .map((entry, index) => ({
      entry,
      rank: badgeSeedOrder.get(entry.code) ?? badgeSeedOrder.size + index,
    }))
    .sort((a, b) => a.rank - b.rank)
    .map((ranked) => ranked.entry);

  const seen = new Set<string>();
  return ordered.filter((entry) => {
    if (seen.has(entry.title)) return false;
    seen.add(entry.title);
    return true;
  });
}

/**
 * What gifts exist. Deliberately not who receives one, and deliberately not
 * when — the temple was explicit, and a legend that says "for the top three"
 * turns a gift into a prize and the board into the reason for serving.
 *
 * Written here rather than read from `list_seva_badge_legend()` on purpose,
 * and it is the one place this feature does not take the server's wording:
 * every gift row the server sends carries its rule in both its description and
 * its `earned_by`, so the only part of it that could be shown is the title, and
 * a column of bare titles says less than these sentences do. What the server
 * decides is which rows are gifts at all — `sevaLegendBadges` keeps them out of
 * the badges — and this list answers "what is there", covering every gift-tier
 * definition 0055 and 0063 seeded.
 *
 * The garlands are one entry each rather than three and seven rows because they
 * are lateral: listing them in a column is a ranking whatever the wording says.
 *
 * "Maha Burfi" was advertised here and is in `award_definitions` nowhere — the
 * maha_prasad tier holds Maha Prasad and the President's Gift and nothing else,
 * on a replica of the temple's own database. An app promising a sweet the
 * temple has no definition for is a devotee asking the kitchen for it, so it is
 * off this list until the temple seeds it. If they do hand one out, the fix is a
 * row in `award_definitions`, not a line here.
 */
export const sevaGiftLegend: {
  title: string;
  description: string;
  items?: string[];
}[] = [
  {
    title: "Maha Prasad",
    description: "A plate from the altar.",
  },
  {
    title: "Mystery Gift",
    description: "Something from the temple, not said in advance.",
  },
  {
    title: "The temple's garlands",
    description:
      "A garland from the altar: one for hands, one for generosity, one for both together.",
    items: ["Sevā", "Dāna", "Samatva"],
  },
  {
    title: "The Deity garlands",
    description:
      "A garland worn by the Deities, offered onward. Not one of the seven stands above another.",
    items: [
      "Kisora",
      "Kisori",
      "Jagannath",
      "Baldev",
      "Subhadra",
      "Gaura",
      "Nitai",
    ],
  },
  {
    title: "The President's Gift",
    description:
      "Chosen by the President, for something no arithmetic would have noticed.",
  },
];

/**
 * `seva_yatra_devotee_summary(p_devotee_id, p_period_kind)` — why a name is
 * where it is on the board, for one period. The server decides what this
 * caller may know; nothing here reconstructs a figure it withheld.
 *
 * `points` and `seva_points` are published to every signed-in devotee, because
 * 0060's board already publishes both integers for everybody on it. `score` is
 * the raw norm behind them and, with the cash figures, belongs to
 * `may_view_all_giving` — the President and the Tech Admin. `giving_withheld`
 * says which caller you are, so a null can never be read as a zero. There is no
 * `seva_norm` and no `giving_norm` in the shape at all: the server does not
 * declare them, because either one inverts to a devotee's giving to the dollar.
 */
export type SevaYatraDevoteeSummary = {
  devotee_id: string;
  devotee_name: string;
  devotee_photo_url: string | null;
  period_kind: string;
  period_start: string;
  period_end: string;
  standing: number | null;
  /** Already public. What the board shows beside their name. */
  points: number;
  /** The seva half of it, likewise public — 0060's 'seva' board. */
  seva_points: number;
  /** app.view_all's. Null for everybody else, and never rendered as zero. */
  score: number | null;
  served_minutes: number;
  seva_minutes: number;
  seva_acts: number;
  top_seva_name: string | null;
  top_seva_service_type_id: string | null;
  top_seva_hours: number | null;
  /** A fraction of THEIR seva, not of the temple's. */
  top_seva_share: number | null;
  /** "They gave in this period", with no amount. Already public by name. */
  supported: boolean;
  giving_cents: number | null;
  gifts: number | null;
  giving_withheld: boolean;
  is_you: boolean;
};

/**
 * The giving figure on the drill-down, and the word above it.
 *
 * `giving_cents` is null for every caller without `may_view_all_giving`, and
 * `formatCents(null ?? 0)` would put "$0.00" against a devotee's name — the
 * congregation reading that a devotee gave nothing, which is the one thing the
 * server's null was careful to prevent. `supported` is the fact that is already
 * public: 0060 publishes who gave in a period, by name, with no amount.
 */
export function sevaGivingFigure(row: {
  giving_withheld?: boolean | null;
  giving_cents?: number | null;
  supported?: boolean | null;
}): { label: string; value: string } {
  // A row from a caller the server withheld from, and — belt and braces — any
  // row that arrived with no cents figure at all.
  if (row.giving_withheld ?? row.giving_cents == null) {
    return { label: "Gave", value: row.supported ? "Yes" : "—" };
  }
  return { label: "Given", value: formatCents(row.giving_cents ?? 0) };
}

/**
 * What the waiting acts are actually waiting for.
 *
 * The server distinguishes three states and "still to be confirmed" is only the
 * last of them. An act nobody has marked done is waiting on the devotee reading
 * the screen; an act awaiting verification is waiting on whoever runs that
 * seva. Telling a devotee somebody else has to confirm all three sends them to
 * the office to ask about something they could finish themselves. Only the
 * states actually present are named, so the sentence is never a list of steps
 * that do not apply.
 */
const pendingSevaSteps: { status: SevaPointsStatus; step: string }[] = [
  { status: "awaiting_completion", step: "marked done" },
  { status: "awaiting_verification", step: "verified" },
  { status: "awaiting_confirmation", step: "confirmed" },
];

export function pendingSevaPhrase(statuses: readonly SevaPointsStatus[]) {
  const steps = pendingSevaSteps
    .filter((entry) => statuses.includes(entry.status))
    .map((entry) => entry.step);
  // The windows the period scoring cannot itemise — the calendar year — know
  // how many acts are waiting but not on what, and this is honest for all three.
  if (!steps.length) return "signed off";
  if (steps.length === 1) return steps[0];
  return `${steps.slice(0, -1).join(", ")} and ${steps[steps.length - 1]}`;
}
