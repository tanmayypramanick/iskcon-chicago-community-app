/// <reference types="jest" />

// Nothing here reaches the network — the record's two builders are pure — but
// importing the screen reaches the client, which opens a database on load.
jest.mock("../../lib/supabase", () => ({
  getSupabaseClient: () => ({ rpc: jest.fn() }),
}));

import type { DevoteeProfileRow } from "../../features/access/api";
import { congregationSevaRows } from "../../features/profile/sevaHours";
import type {
  AllSevaHours,
  AllSevaScore,
} from "../../features/sevayatra/types";
import {
  buildDevoteeSummaries,
  buildDevoteeWorkbook,
  devoteeGiftsLine,
  devoteeSummaryLine,
  type DevoteeSummary,
} from "../DevoteeDirectoryScreen";

/**
 * Radha served twelve hours this week and nobody has confirmed one of them, so
 * the nightly scoring has written her no `period_scores` row at all. She is the
 * devotee the temple complained about: the old `list_all_seva_scores` read has
 * no row for her, and the record showed her as having served nothing.
 */
const radha = "devotee-radha";
const gopal = "devotee-gopal";
const nobody = "devotee-nobody";

const hoursRows = [
  {
    devotee_id: radha,
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
  },
  {
    devotee_id: gopal,
    devotee_name: "Gopal Das",
    served_minutes: 240,
    served_acts: 2,
    credited_minutes: 180,
    credited_acts: 2,
    awaiting_minutes: 0,
    awaiting_acts: 0,
    points: 30,
    awaiting_only: false,
    is_hidden: false,
  },
] as unknown as AllSevaHours[];

// The same week as 0064 answers it: Radha is simply absent, and Gopal's minutes
// are what the fairness caps left rather than what he served.
const scoreRows = [
  {
    devotee_id: gopal,
    devotee_name: "Gopal Das",
    seva_minutes: 180,
    seva_acts: 2,
  },
] as unknown as AllSevaScore[];

function ranges(hours: AllSevaHours[] | null, scores: AllSevaScore[]) {
  const rows = congregationSevaRows(hours, scores);
  return { week: rows, month: rows, lifetime: rows };
}

function devotee(id: string, name: string): DevoteeProfileRow {
  return {
    id,
    name,
    email: `${id}@example.com`,
    phone: null,
    photo_url: null,
    role_name: "devotee",
    joined_at: "2026-01-05T12:00:00.000Z",
    date_of_birth: null,
    birth_place: null,
    address: null,
    spiritual_mentor: null,
    is_initiated: false,
    initiation_date: null,
    diksha_guru: null,
    has_first_initiation: false,
    first_initiation_date: null,
    first_diksha_guru: null,
    has_second_initiation: false,
    second_initiation_date: null,
    second_diksha_guru: null,
    profile_updated_at: null,
    completion: 80,
  };
}

describe("the congregation's hours", () => {
  it("lists a devotee whose every act is pending, with the hours she served", () => {
    const summaries = buildDevoteeSummaries(ranges(hoursRows, []), []);
    const hers = summaries.get(radha);

    expect(hers).toBeDefined();
    expect(hers?.hours.week).toBe(12);
    expect(hers?.acts.week).toBe(4);
  });

  it("shows hours served rather than the credited figure", () => {
    const summaries = buildDevoteeSummaries(ranges(hoursRows, []), []);
    // Four hours served, three of them credited after the fairness caps.
    expect(summaries.get(gopal)?.hours.week).toBe(4);
  });

  // Until 0066 deploys the old read is all there is, and it must keep working
  // exactly as it did rather than emptying the record.
  it("falls back to the credited read where the function is missing", () => {
    const summaries = buildDevoteeSummaries(ranges(null, scoreRows), []);

    expect(summaries.get(gopal)?.hours.week).toBe(3);
    expect(summaries.get(radha)).toBeUndefined();
  });

  it("has nothing at all for a devotee neither read names", () => {
    const summaries = buildDevoteeSummaries(ranges(hoursRows, []), []);
    expect(summaries.get(nobody)).toBeUndefined();
  });
});

/**
 * The congregation row stated its two facts on the line under the name, and
 * then stated both of them again as labelled rows the moment it was opened —
 * "12 hours month" over "Seva this month · 12 hours", "$551.00" over "Given ·
 * $551.00 · 2 gifts". Opening a row now adds to what it says rather than
 * repeating it.
 */
describe("what a congregation row says once", () => {
  const summary: DevoteeSummary = {
    hours: { week: 3, month: 12, lifetime: 40 },
    acts: { week: 1, month: 5, lifetime: 20 },
    given: [{ currency: "USD", cents: 55100, gifts: 2 }],
    gifts: 2,
    lastGiftAt: "2026-07-04T12:00:00.000Z",
  };

  it("carries the hours and the amount on one line", () => {
    expect(devoteeSummaryLine(summary, "month")).toBe(
      "12 hours month · $551.00",
    );
  });

  it("adds the count and the date on opening, and neither figure again", () => {
    const line = devoteeGiftsLine(summary, "Jul 4, 2026");

    expect(line).toBe("2 gifts, last Jul 4, 2026");
    expect(line).not.toContain("$551.00");
    expect(line).not.toContain("12 hours");
  });

  it("says nothing at all about gifts where there are none", () => {
    expect(devoteeGiftsLine({ ...summary, gifts: 0 }, null)).toBeNull();
  });
});

describe("the exported congregation sheet", () => {
  const rows = [devotee(radha, "Radha Devi"), devotee(nobody, "Nobody Yet")];

  it("carries the pending devotee's hours, and a blank where there is no record", () => {
    const summaries = buildDevoteeSummaries(ranges(hoursRows, []), []);
    const workbook = buildDevoteeWorkbook(rows, summaries);

    const cells = workbook
      .split("<tr>")
      .map((row) => row.split("</td>").map((cell) => cell.split(">").pop()));
    const hers = cells.find((row) => row.includes("Radha Devi"));
    const theirs = cells.find((row) => row.includes("Nobody Yet"));

    expect(hers).toContain("12");
    // A zero would average into whatever the office does with the column; a
    // devotee with no record has not served nought hours.
    expect(theirs).not.toContain("0");
    expect(theirs).not.toContain("12");
  });
});
