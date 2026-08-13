/// <reference types="jest" />

import {
  congregationSevaRows,
  devoteeSevaRanges,
  mySevaRanges,
  sevaActsWindow,
  servedHoursOf,
} from "../sevaHours";
import type {
  AllSevaHours,
  AllSevaScore,
  MySevaAct,
  MySevaBalanceRow,
  MySevaBreakdownRow,
} from "../../sevayatra/types";

const act = (over: Partial<MySevaAct>): MySevaAct =>
  ({
    assignment_id: "a",
    service_instance_id: null,
    service_type_id: "type-kitchen",
    seva_name: "Kitchen",
    occurred_on: "2026-03-02",
    weekday: "Monday",
    started_at_local: null,
    minutes: 60,
    hours: 1,
    is_recurring: false,
    assignment_status: "completed",
    verification: "verified",
    attendance: "attended",
    points_status: "counted",
    points_note: null,
    ...over,
  }) as MySevaAct;

const balanceRow = (over: Record<string, unknown> = {}) => ({
  service_type_id: "type-kitchen",
  seva_name: "Kitchen",
  category: "kitchen",
  hours_this_week: 2,
  hours_this_month: 8,
  hours_trailing_quarter: 20,
  hours_all_time: 100,
  share_of_their_seva: 0.5,
  consecutive_weeks: 3,
  acts_trailing_quarter: 10,
  first_served_on: "2019-01-05",
  last_served_on: "2026-03-02",
  ...over,
});

describe("sevaActsWindow", () => {
  it("reaches back to 1 January once the year is older than the quarter", () => {
    const window = sevaActsWindow(new Date("2026-08-11T12:00:00Z"));
    expect(window.yearStart).toBe("2026-01-01");
    // Mid-August, the trailing 90 days start later than January, so the wider
    // of the two — the year — is what the one request has to cover.
    expect(window.from).toBe("2026-01-01");
    expect(window.to).toBe("2026-08-11");
  });

  it("reaches back past 1 January in January, when the quarter is wider", () => {
    const window = sevaActsWindow(new Date("2026-01-20T12:00:00Z"));
    expect(window.yearStart).toBe("2026-01-01");
    expect(window.from < "2026-01-01").toBe(true);
  });
});

describe("devoteeSevaRanges", () => {
  const balance = [
    balanceRow(),
    balanceRow({
      service_type_id: null,
      seva_name: "Janmastami rangoli",
      hours_this_week: 0,
      hours_this_month: 3,
      hours_all_time: 3,
    }),
  ];

  const acts = [
    act({ assignment_id: "1", occurred_on: "2026-02-10", minutes: 90 }),
    act({ assignment_id: "2", occurred_on: "2026-03-02", minutes: 30 }),
    // Last year: outside the calendar year, inside the request's window.
    act({ assignment_id: "3", occurred_on: "2025-12-30", minutes: 600 }),
    // Served but still waiting on somebody — hours all the same.
    act({
      assignment_id: "4",
      occurred_on: "2026-03-03",
      minutes: 60,
      points_status: "awaiting_verification",
    }),
    // They were not there, so it is not an hour of seva.
    act({
      assignment_id: "5",
      occurred_on: "2026-03-04",
      minutes: 120,
      points_status: "not_served",
    }),
  ];

  it("takes week, month and all time from the server's own windows", () => {
    const ranges = devoteeSevaRanges(balance, [], "2026-01-01");
    expect(ranges.week.hours).toBe(2);
    expect(ranges.month.hours).toBe(11);
    expect(ranges.lifetime.hours).toBe(103);
  });

  it("derives the calendar year from the acts, counting pending and not last year's", () => {
    const ranges = devoteeSevaRanges(balance, acts, "2026-01-01");
    // 90 + 30 + 60 minutes. December's ten hours and the not-served two are out.
    expect(ranges.year.hours).toBeCloseTo(3);
    expect(ranges.year.acts).toBe(3);
  });

  it("keeps custom-named seva apart instead of folding it into one null bucket", () => {
    const ranges = devoteeSevaRanges(balance, [], "2026-01-01");
    expect(ranges.month.sevas.map((seva) => seva.name)).toEqual([
      "Kitchen",
      "Janmastami rangoli",
    ]);
  });

  it("drops a seva with no hours in the range rather than listing a zero", () => {
    const ranges = devoteeSevaRanges(balance, [], "2026-01-01");
    expect(ranges.week.sevas).toHaveLength(1);
    expect(ranges.week.sevas[0].name).toBe("Kitchen");
  });

  /**
   * `seva_mala_periods.period_kind` is week, month or lifetime and nothing
   * else, so there is no calendar year to ask the server for. The nearest
   * figure to hand is `hours_trailing_quarter`, which is the one thing the year
   * must never quietly become — a devotee who served nothing since January and
   * twenty hours before it has served nothing this year.
   */
  it("never stands the trailing quarter in for the year", () => {
    const ranges = devoteeSevaRanges(
      [balanceRow({ hours_trailing_quarter: 20 })],
      [],
      "2026-01-01",
    );
    expect(ranges.year.hours).toBe(0);
    expect(ranges.year.sevas).toEqual([]);
  });
});

describe("mySevaRanges", () => {
  const breakdown = [
    {
      window_kind: "year",
      service_type_id: "type-kitchen",
      seva_name: "Kitchen",
      acts: 10,
      hours: 20,
      not_served_acts: 2,
      not_served_hours: 4,
    },
    {
      window_kind: "week",
      service_type_id: "type-kitchen",
      seva_name: "Kitchen",
      acts: 1,
      hours: 2,
      not_served_acts: 0,
      not_served_hours: 0,
    },
  ] as unknown as MySevaBreakdownRow[];

  const balance = [
    {
      service_type_id: "type-kitchen",
      seva_name: "Kitchen",
      hours_all_time: 60,
      acts_all_time: 30,
    },
  ] as unknown as MySevaBalanceRow[];

  it("reports hours served, taking the not-served share back off", () => {
    const ranges = mySevaRanges(breakdown, balance);
    expect(ranges.year.hours).toBe(16);
    expect(ranges.year.acts).toBe(8);
    expect(ranges.week.hours).toBe(2);
  });

  it("takes all time from the balance, which the breakdown does not carry", () => {
    const ranges = mySevaRanges(breakdown, balance);
    expect(ranges.lifetime.hours).toBe(60);
    expect(ranges.lifetime.acts).toBe(30);
  });

  it("is empty rather than undefined when nothing has been served", () => {
    const ranges = mySevaRanges([], []);
    expect(ranges.month).toEqual({ hours: 0, acts: 0, sevas: [] });
  });
});

/**
 * The devotee `list_all_seva_hours` exists for.
 *
 * Every one of her acts is still waiting on a verifier, so the scoring has
 * written her no `period_scores` row — she is not zero on the old read, she is
 * absent from it. The new read full outer joins and carries her served minutes,
 * flagged `awaiting_only`, and the congregation record has to show those hours
 * rather than the nought her credited figure would give.
 */
describe("congregationSevaRows", () => {
  const radha = {
    devotee_id: "devotee-radha",
    devotee_name: "Radha Devi",
    served_minutes: 720,
    served_acts: 4,
    credited_minutes: 0,
    credited_acts: 0,
    awaiting_minutes: 720,
    awaiting_acts: 4,
    points: 0,
    awaiting_only: true,
    is_hidden: false,
  } as unknown as AllSevaHours;

  it("lists the awaiting-only devotee with the hours she actually served", () => {
    const [row] = congregationSevaRows([radha], []);
    expect(row.devotee_id).toBe("devotee-radha");
    expect(row.hours).toBe(12);
    expect(row.acts).toBe(4);
  });

  it("has no row for her at all where only the credited read answers", () => {
    expect(congregationSevaRows(null, [])).toEqual([]);
  });
});

/**
 * `list_all_seva_scores` as a Community Head reads it.
 *
 * `may_view_whole_seva_board()` is `app.view_all` OR `services.manage_recurring`,
 * so a Community Head is a caller of that function — and every cash-shaped
 * column on it, `score` included, is gated on the narrower `may_view_all_giving()`
 * and comes back null to them. The type used to declare `score` as a plain
 * number and carry no `points` at all, so anything working points out from the
 * score would have shown them a board of noughts. 0067 publishes `points`
 * ungated, and it is the figure to read.
 */
describe("a row of list_all_seva_scores", () => {
  const asCommunityHead: AllSevaScore = {
    standing: 4,
    devotee_id: "devotee-gopal",
    devotee_name: "Gopal Das",
    points: 370,
    score: null,
    seva_minutes: 180,
    seva_acts: 2,
    giving_cents: null,
    gifts: null,
    seva_norm: null,
    giving_norm: null,
    is_hidden: false,
    giving_withheld: true,
  };

  it("carries the published points beside a withheld score", () => {
    expect(asCommunityHead.points).toBe(370);
    expect(asCommunityHead.score).toBeNull();
  });

  it("still reads their hours, which are not gated on giving", () => {
    expect(servedHoursOf(asCommunityHead)).toBe(3);
    expect(congregationSevaRows(null, [asCommunityHead])).toEqual([
      { devotee_id: "devotee-gopal", hours: 3, acts: 2 },
    ]);
  });
});

describe("servedHoursOf", () => {
  const score = { seva_minutes: 120, seva_acts: 4 } as AllSevaScore;

  it("falls back to credited minutes where 0066 has not been applied", () => {
    expect(servedHoursOf(score)).toBe(2);
  });

  it("prefers hours served over the capped credited figure", () => {
    expect(servedHoursOf({ ...score, served_minutes: 240 })).toBe(4);
  });
});
