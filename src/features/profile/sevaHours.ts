/**
 * Hours of seva, read over a range a devotee would name: this week, this month,
 * this year, all time.
 *
 * The four ranges are not four equally-supported reads. `seva_balance_for_devotee`
 * answers week, month, trailing quarter and all time; `seva_mala_periods.period_kind`
 * is constrained to week/month/lifetime, so nothing on the server keeps a
 * calendar year. The year here is derived on the client from the act list over a
 * 1 January → today window, filtered by the same rule the balance function uses,
 * so the two agree rather than merely look similar. The trailing quarter stays a
 * trailing quarter everywhere it appears and is never called a year.
 *
 * Every figure is hours SERVED, not hours credited. An act still waiting on
 * somebody to verify it earned no points and was still served, and the devotee
 * who served it is exactly as tired either way.
 */

import { addChicagoDays, getChicagoDateKey } from "../../lib/chicagoDate";
import type {
  AllSevaHours,
  AllSevaScore,
  MySevaAct,
  MySevaBalanceRow,
  MySevaBreakdownRow,
  SevaPeriodKind,
  SevaRangeKind,
} from "../sevayatra/types";

/**
 * The chooser's four. Seva Yatra names the same set, and the name is shared
 * rather than reinvented so a range can never mean one thing on a profile and
 * another on the board.
 */
export type SevaRange = SevaRangeKind;

/** Short enough to sit four-across inside a switch on a narrow phone. */
export const sevaRangeLabels: Record<SevaRange, string> = {
  week: "Week",
  month: "Month",
  year: "Year",
  lifetime: "All time",
};

/** What each range actually covers, said plainly under the figure. */
export const sevaRangeCaptions: Record<SevaRange, string> = {
  week: "This week, from Monday",
  month: "This calendar month",
  year: "This calendar year, from January 1",
  lifetime: "Every seva on record",
};

export const sevaRanges: SevaRange[] = ["week", "month", "year", "lifetime"];

/** Said of a devotee who served nothing in the range. Never of a failed read. */
export const sevaRangeEmpty: Record<SevaRange, string> = {
  week: "No seva recorded this week.",
  month: "No seva recorded this month.",
  year: "No seva recorded this year.",
  lifetime: "No seva on record.",
};

/**
 * A row of `seva_balance_for_devotee(p_devotee_id)` — one kind of seva, hours
 * windowed three ways plus all time. The server answers with nothing at all to
 * a caller without `app.view_all`, so no screen can assemble a picture it is
 * not entitled to.
 *
 * `share_of_their_seva` is a fraction of the trailing quarter and comes back
 * null when the devotee served nothing in that window — the quarter's total is
 * the divisor.
 */
export type DevoteeSevaBalanceRow = {
  service_type_id: string | null;
  seva_name: string;
  category: string | null;
  hours_this_week: number;
  hours_this_month: number;
  hours_trailing_quarter: number;
  hours_all_time: number;
  share_of_their_seva: number | null;
  consecutive_weeks: number;
  acts_trailing_quarter: number;
  first_served_on: string;
  last_served_on: string;
};

/** One kind of seva, by the name the temple gives it, within one range. */
export type SevaNameHours = {
  key: string;
  name: string;
  hours: number;
  /** Zero where the source publishes hours but no act count for the range. */
  acts: number;
};

export type SevaRangeTotals = {
  hours: number;
  acts: number;
  sevas: SevaNameHours[];
};

export type SevaRangeSummary = Record<SevaRange, SevaRangeTotals>;

/** Postgres `numeric` reaches us as a number, but a null must not become NaN. */
export function num(value: number | null | undefined) {
  const parsed = Number(value ?? 0);
  return Number.isFinite(parsed) ? parsed : 0;
}

/**
 * The key `seva_balance_acts` groups on, restated so a client-side grouping
 * lands on the same buckets. Custom-named seva carries no service type, and
 * folding every custom seva into one null bucket would merge "Janmastami
 * rangoli" with "gate duty".
 */
function sevaKey(serviceTypeId: string | null | undefined, name: string) {
  return serviceTypeId ?? `custom:${name.trim().toLowerCase()}`;
}

function emptyTotals(): SevaRangeTotals {
  return { hours: 0, acts: 0, sevas: [] };
}

/** Biggest first, and a seva with no hours in the range is not in the range. */
function settle(sevas: Map<string, SevaNameHours>): SevaRangeTotals {
  const kept = [...sevas.values()]
    .filter((seva) => seva.hours > 0)
    .sort(
      (left, right) =>
        right.hours - left.hours || left.name.localeCompare(right.name),
    );
  return {
    hours: kept.reduce((total, seva) => total + seva.hours, 0),
    acts: kept.reduce((total, seva) => total + seva.acts, 0),
    sevas: kept,
  };
}

/**
 * The window the act list is asked for: wide enough to hold both the calendar
 * year the year range is derived from and the trailing ninety days the
 * act-by-act history reads over, so one request serves both and the two cannot
 * come to disagree.
 */
export function sevaActsWindow(now = new Date()) {
  const today = getChicagoDateKey(now);
  const yearStart = `${today.slice(0, 4)}-01-01`;
  const trailing = addChicagoDays(-89, now);
  return {
    yearStart,
    from: yearStart < trailing ? yearStart : trailing,
    to: today,
  };
}

/**
 * `seva_balance_acts` keeps everything except "they were not there". Applied
 * here so the derived year counts the same acts the server's own windows do.
 */
function isServed(act: Pick<MySevaAct, "points_status" | "minutes">) {
  return act.points_status !== "not_served" && num(act.minutes) > 0;
}

/**
 * One devotee's four ranges, for a President or Tech Admin.
 *
 * Week, month and all time come from the server. The year is grouped here from
 * the acts falling on or after 1 January, because there is no calendar-year
 * period to ask for.
 */
export function devoteeSevaRanges(
  balance: readonly DevoteeSevaBalanceRow[],
  acts: readonly MySevaAct[],
  yearStart = sevaActsWindow().yearStart,
): SevaRangeSummary {
  const week = new Map<string, SevaNameHours>();
  const month = new Map<string, SevaNameHours>();
  const lifetime = new Map<string, SevaNameHours>();

  for (const row of balance) {
    const key = sevaKey(row.service_type_id, row.seva_name);
    // Acts are published for the trailing quarter only, so a per-range act
    // count is not ours to state here and stays zero for the caller to omit.
    const base = { key, name: row.seva_name, acts: 0 };
    week.set(key, { ...base, hours: num(row.hours_this_week) });
    month.set(key, { ...base, hours: num(row.hours_this_month) });
    lifetime.set(key, { ...base, hours: num(row.hours_all_time) });
  }

  const year = new Map<string, SevaNameHours>();
  for (const act of acts) {
    if (act.occurred_on < yearStart || !isServed(act)) continue;
    const key = sevaKey(act.service_type_id, act.seva_name);
    const running = year.get(key) ?? {
      key,
      name: act.seva_name,
      hours: 0,
      acts: 0,
    };
    running.hours += num(act.minutes) / 60;
    running.acts += 1;
    year.set(key, running);
  }

  return {
    week: settle(week),
    month: settle(month),
    year: settle(year),
    lifetime: settle(lifetime),
  };
}

/**
 * A devotee's own four ranges. `my_seva_breakdown` already keeps a calendar
 * year, so nothing is derived here — their own profile is the one place with no
 * gap to work around.
 *
 * Its `hours` column counts every act including the ones marked not-served, so
 * the not-served share is taken back off to leave hours actually served, which
 * is what `seva_balance_for_devotee` means by the same word.
 */
export function mySevaRanges(
  breakdown: readonly MySevaBreakdownRow[],
  balance: readonly MySevaBalanceRow[],
): SevaRangeSummary {
  const windows: Record<
    "week" | "month" | "year",
    Map<string, SevaNameHours>
  > = { week: new Map(), month: new Map(), year: new Map() };

  for (const row of breakdown) {
    const bucket = windows[row.window_kind];
    if (!bucket) continue;
    const key = sevaKey(row.service_type_id, row.seva_name);
    const running = bucket.get(key) ?? {
      key,
      name: row.seva_name,
      hours: 0,
      acts: 0,
    };
    running.hours += num(row.hours) - num(row.not_served_hours);
    running.acts += num(row.acts) - num(row.not_served_acts);
    bucket.set(key, running);
  }

  const lifetime = new Map<string, SevaNameHours>();
  for (const row of balance) {
    const key = sevaKey(row.service_type_id, row.seva_name);
    lifetime.set(key, {
      key,
      name: row.seva_name,
      hours: num(row.hours_all_time),
      acts: num(row.acts_all_time),
    });
  }

  return {
    week: settle(windows.week),
    month: settle(windows.month),
    year: settle(windows.year),
    lifetime: settle(lifetime),
  };
}

export const emptySevaRangeSummary: SevaRangeSummary = {
  week: emptyTotals(),
  month: emptyTotals(),
  year: emptyTotals(),
  lifetime: emptyTotals(),
};

/**
 * The ranges the temple-wide read can answer. There is no calendar-year period
 * across the congregation, and deriving one would be one act-list request per
 * devotee — a roster of two hundred cannot afford that. The year is offered on
 * a devotee's own record instead, and the congregation says so rather than
 * quietly relabelling the quarter.
 */
export const congregationSevaRanges: SevaPeriodKind[] = [
  "week",
  "month",
  "lifetime",
];

/**
 * `list_all_seva_scores` publishes `seva_minutes` as CREDITED minutes — raw
 * minutes after the day and week caps the scoring applies for fairness. It will
 * never publish anything else: 0064's verification pins that function's OUT
 * columns character for character, so the `served_minutes` this type tolerates
 * is only ever a temple that has widened the function by hand.
 *
 * Which is why hours served come from `list_all_seva_hours` instead, and this
 * read is the last resort for a database without 0066.
 */
export type SevaScoreRow = AllSevaScore & { served_minutes?: number | null };

export function servedHoursOf(score: SevaScoreRow | null | undefined) {
  if (!score) return 0;
  return num(score.served_minutes ?? score.seva_minutes) / 60;
}

/**
 * One devotee's hours and acts for one range, from whichever temple-wide read
 * answered. Hours, never a score — the congregation record does not rank.
 */
export type CongregationSevaRow = {
  devotee_id: string;
  hours: number;
  acts: number;
};

/**
 * The congregation's hours for one range, preferring 0066's read.
 *
 * The two sources do not say the same thing, and the difference is the bug the
 * temple reported. `list_all_seva_scores` is driven by `period_scores`, which
 * the nightly scoring writes only for credited work — so a devotee whose every
 * act is still awaiting a verifier has no row, is absent from the list, and
 * reads as nought hours despite having served all of them. `list_all_seva_hours`
 * full outer joins and carries uncapped served minutes, so those devotees are
 * on it with their real hours, flagged `awaiting_only`.
 *
 * A null `hours` is the server saying it has no such function yet; undefined is
 * a read still in flight. Both fall through to the scores, which is what the
 * congregation showed before 0066 and what it must keep showing until then.
 */
export function congregationSevaRows(
  hours: readonly AllSevaHours[] | null | undefined,
  scores: readonly SevaScoreRow[] | null | undefined,
): CongregationSevaRow[] {
  if (hours) {
    return hours.map((row) => ({
      devotee_id: row.devotee_id,
      hours: num(row.served_minutes) / 60,
      acts: Math.round(num(row.served_acts)),
    }));
  }
  return (scores ?? []).map((score) => ({
    devotee_id: score.devotee_id,
    hours: servedHoursOf(score),
    acts: Math.round(num(score.seva_acts)),
  }));
}
