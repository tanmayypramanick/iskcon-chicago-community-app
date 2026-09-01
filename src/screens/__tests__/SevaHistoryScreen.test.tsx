/// <reference types="jest" />

/**
 * My seva history, on Arpita's real week.
 *
 * `my_seva_acts('2026-08-10','2026-08-16')` answered with three acts on the
 * replica of the temple's own data, and the two that are waiting are waiting on
 * different people: Kirtana Support has not been marked done, which is hers to
 * do, and Kitchen Preparation is waiting to be verified, which is not. The old
 * wording called both of them "waiting to be confirmed" — the complaint this
 * screen was reopened for.
 */

import { act, cleanup, fireEvent, render } from "@testing-library/react-native";

import type {
  MySevaAct,
  MySevaBalanceRow,
  MySevaBreakdownRow,
  MySevaProfileWindow,
} from "../../features/sevayatra/types";

jest.mock("../../lib/supabase", () => ({
  getSupabaseClient: () => ({ rpc: jest.fn() }),
}));

jest.mock("../../lib/connectivity", () => ({
  useServerReachable: () => true,
  reportReachability: jest.fn(),
}));

jest.mock("../../features/sevayatra/hooks", () => ({
  useMySevaProfile: () => mockHistory.profile,
  useMySevaBreakdown: () => mockHistory.breakdown,
  useMySevaBalance: () => mockHistory.balance,
  useMySevaActs: () => mockHistory.acts,
}));

import { usePrototypeSession } from "../../store/usePrototypeSession";
import { SevaHistoryScreen } from "../SevaHistoryScreen";

function answered<Row>(data: Row) {
  return { data, isLoading: false, isError: false, error: null, refetch: jest.fn() };
}

const KIRTANA = "type-kirtana";
const KITCHEN = "type-kitchen";
const CLEANING = "type-cleaning";

const week: MySevaProfileWindow = {
  window_kind: "week",
  window_start: "2026-08-10",
  window_end: "2026-08-16",
  acts: 3,
  hours: 6,
  counted_acts: 0,
  counted_hours: 0,
  pending_acts: 2,
  pending_hours: 4,
  not_served_acts: 1,
  not_served_hours: 2,
  recurring_acts: 0,
  recurring_hours: 0,
  giving_cents: 0,
  gifts: 0,
};

const year: MySevaProfileWindow = {
  ...week,
  window_kind: "year",
  window_start: "2026-01-01",
  window_end: "2026-12-31",
  acts: 12,
  hours: 23.5,
  counted_hours: 17.5,
};

function breakdown(
  seva: string,
  serviceTypeId: string,
  pending: number,
): MySevaBreakdownRow {
  return {
    window_kind: "week",
    window_start: "2026-08-10",
    window_end: "2026-08-16",
    service_type_id: serviceTypeId,
    seva_name: seva,
    acts: 1,
    hours: 2,
    counted_acts: 0,
    counted_hours: 0,
    pending_acts: pending,
    pending_hours: pending * 2,
    not_served_acts: pending ? 0 : 1,
    not_served_hours: pending ? 0 : 2,
    recurring_acts: 0,
    recurring_hours: 0,
  };
}

function sevaAct(
  seva: string,
  serviceTypeId: string,
  status: MySevaAct["points_status"],
): MySevaAct {
  return {
    assignment_id: `assignment-${serviceTypeId}`,
    service_instance_id: null,
    service_type_id: serviceTypeId,
    seva_name: seva,
    occurred_on: "2026-08-10",
    weekday: "Mon",
    started_at_local: null,
    minutes: 120,
    hours: 2,
    is_recurring: false,
    assignment_status: "assigned",
    verification: "none",
    attendance: "unknown",
    points_status: status,
    points_note: null,
  };
}

const balanceRow: MySevaBalanceRow = {
  service_type_id: KIRTANA,
  seva_name: "Kirtana Support",
  category: "Kirtan",
  hours_this_month: 4,
  hours_this_quarter: 12,
  hours_all_time: 40,
  acts_all_time: 20,
  first_served_on: "2025-04-06",
  last_served_on: "2026-08-10",
};

let mockHistory: {
  profile: ReturnType<typeof answered<MySevaProfileWindow[]>>;
  breakdown: ReturnType<typeof answered<MySevaBreakdownRow[]>>;
  balance: ReturnType<typeof answered<MySevaBalanceRow[]>>;
  acts: ReturnType<typeof answered<MySevaAct[]>>;
};

beforeEach(() => {
  mockHistory = {
    profile: answered([week, year]),
    breakdown: answered([
      breakdown("Kirtana Support", KIRTANA, 1),
      breakdown("Kitchen Preparation", KITCHEN, 1),
      breakdown("Temple Room Cleaning", CLEANING, 0),
    ]),
    balance: answered([balanceRow]),
    acts: answered([
      sevaAct("Temple Room Cleaning", CLEANING, "not_served"),
      sevaAct("Kirtana Support", KIRTANA, "awaiting_completion"),
      sevaAct("Kitchen Preparation", KITCHEN, "awaiting_verification"),
    ]),
  };
  usePrototypeSession.setState({ activeUserId: "arpita" });
});

afterEach(cleanup);

async function open(range?: string) {
  const screen = await render(<SevaHistoryScreen />);
  if (range) {
    await act(async () => {
      fireEvent.press(screen.getByLabelText(range));
    });
  }
  return screen;
}

describe("what a waiting act is waiting on", () => {
  /**
   * Two sevas, one waiting act each, and the two are not waiting on the same
   * person. Saying "confirmed" over both sends a devotee to the office about an
   * act she could finish herself.
   */
  it("says it seva by seva, rather than confirming everything", async () => {
    const { getByText, queryByText } = await open();

    expect(getByText("1 act · 1 still to be marked done")).toBeTruthy();
    expect(getByText("1 act · 1 still to be verified")).toBeTruthy();
    expect(queryByText(/waiting to be confirmed/)).toBeNull();
  });

  /** The window's own total names every state present in it, and only those. */
  it("names every state the window holds, in the summary", async () => {
    const { getByText } = await open();

    expect(
      getByText("3 acts of seva · 2 still to be marked done and verified"),
    ).toBeTruthy();
  });

  it("says all three where all three are waiting", async () => {
    mockHistory.acts = answered([
      sevaAct("Kirtana Support", KIRTANA, "awaiting_completion"),
      sevaAct("Kitchen Preparation", KITCHEN, "awaiting_verification"),
      sevaAct("Temple Room Cleaning", CLEANING, "awaiting_confirmation"),
    ]);
    const { getByText } = await open();

    expect(
      getByText(
        "3 acts of seva · 2 still to be marked done, verified and confirmed",
      ),
    ).toBeTruthy();
  });

  /** A seva with nothing waiting says nothing about waiting. */
  it("leaves a settled seva alone", async () => {
    const { getByText } = await open();

    expect(getByText("1 act")).toBeTruthy();
  });

  /**
   * A row's phrase is its own. The seva waiting on verification must not
   * borrow the sentence from the one waiting to be marked done.
   */
  it("does not spread one seva's reason across the others", async () => {
    mockHistory.breakdown = answered([
      breakdown("Kirtana Support", KIRTANA, 1),
      breakdown("Kitchen Preparation", KITCHEN, 1),
    ]);
    mockHistory.acts = answered([
      sevaAct("Kirtana Support", KIRTANA, "awaiting_completion"),
      sevaAct("Kitchen Preparation", KITCHEN, "awaiting_confirmation"),
    ]);
    const { getByText, queryByText } = await open();

    expect(getByText("1 act · 1 still to be marked done")).toBeTruthy();
    expect(getByText("1 act · 1 still to be confirmed")).toBeTruthy();
    expect(queryByText("1 act · 1 still to be verified")).toBeNull();
  });
});

describe("the ranges", () => {
  it("reads the week it is showing", async () => {
    const { getByText } = await open();

    expect(getByText("6 hours")).toBeTruthy();
    expect(getByText("Mon, Aug 10 – Sun, Aug 16")).toBeTruthy();
  });

  it("reads the calendar year, which has its own window", async () => {
    const { getByText } = await open("Year");

    expect(getByText("23.5 hours")).toBeTruthy();
  });

  /**
   * All time has no window row of its own, so its total is the per-seva
   * balances added up and its start is the devotee's first ever seva — real
   * dates from the server, rather than a ninety-day default quietly labelled
   * "all time".
   */
  it("adds the balances up for all time, and dates it honestly", async () => {
    const { getAllByText } = await open("All time");

    // The hero total, and the one balance row it was added up from — both the
    // real figure and the real date, never a ninety-day default called "all
    // time".
    expect(getAllByText("40 hours")).toHaveLength(2);
    expect(getAllByText("Since April 6, 2025")).toHaveLength(2);
  });

  /**
   * All time's breakdown IS the balance, so the standing "everything you have
   * offered" section stands down for it — two lists of the same rows on one
   * screen read as a mistake.
   */
  it("lists the balance once for all time, not as two sections", async () => {
    const { getByText, queryByText } = await open("All time");

    expect(getByText("Seva by kind")).toBeTruthy();
    expect(queryByText("All the seva you have offered")).toBeNull();
  });

  /**
   * The window had one too. "Seva by kind" gave Kirtana Support its two hours
   * this week and "All the seva you have offered" gave the same name forty
   * hours three inches below, with nothing on either row saying which range it
   * belonged to. All time is a chip away, and it draws the second list there.
   */
  it("names a seva under one list, with one total", async () => {
    const { getAllByText, getByText, queryByText } = await open();

    expect(getByText("Seva by kind")).toBeTruthy();
    expect(queryByText("All the seva you have offered")).toBeNull();
    // The week's breakdown row and the act itself. Never a third naming with
    // an all-time figure beside it.
    expect(getAllByText("Kirtana Support")).toHaveLength(2);
    expect(queryByText("40 hours")).toBeNull();
  });
});

describe("an empty window", () => {
  it("says nothing was recorded rather than drawing a blank", async () => {
    mockHistory.acts = answered<MySevaAct[]>([]);
    mockHistory.breakdown = answered<MySevaBreakdownRow[]>([]);
    const { getByText } = await open();

    expect(getByText("Nothing recorded in this window.")).toBeTruthy();
  });
});
