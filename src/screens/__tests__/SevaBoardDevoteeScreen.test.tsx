/// <reference types="jest" />

/**
 * The drill-down behind a name on the board — what a President reads off it and
 * what an ordinary devotee reads off the same row.
 *
 * The two fixtures are `seva_yatra_devotee_summary('<Krsna Kirtan Das>', 'week')`
 * as a replica of the temple's own database answered it for each of them. The
 * only differences are the four columns the server withholds: `score`,
 * `giving_cents`, `gifts`, and the `giving_withheld` flag that says so.
 */

import { act, cleanup, fireEvent, render } from "@testing-library/react-native";

import type { SevaYatraDevoteeSummary } from "../../features/sevayatra/types";

jest.mock("../../lib/supabase", () => ({
  getSupabaseClient: () => ({
    rpc: jest.fn().mockResolvedValue({ data: [], error: null }),
  }),
}));

jest.mock("../../lib/connectivity", () => ({
  useServerReachable: () => true,
  reportReachability: jest.fn(),
}));

jest.mock("@tanstack/react-query", () => ({
  useQuery: () => ({
    data: null,
    isLoading: false,
    isError: false,
    error: null,
    refetch: jest.fn(),
  }),
}));

jest.mock("../../features/access/hooks", () => ({
  useCurrentAccessProfile: () => ({ data: { role: mockView.role } }),
}));

jest.mock("../../features/sevayatra/hooks", () => ({
  useSevaYatraDevoteeSummary: (...args: unknown[]) => mockSummary(...args),
}));

import { SevaBoardDevoteeScreen } from "../SevaBoardDevoteeScreen";

/** The row as the server sent it to the President. */
const forPresident: SevaYatraDevoteeSummary = {
  devotee_id: "d-kirtan",
  devotee_name: "Krsna Kirtan Das",
  devotee_photo_url: null,
  period_kind: "week",
  period_start: "2026-08-10",
  period_end: "2026-08-16",
  standing: 3,
  points: 500,
  seva_points: 390,
  score: 0.503045,
  served_minutes: 120,
  seva_minutes: 120,
  seva_acts: 1,
  top_seva_name: "Vegetable Cutting",
  top_seva_service_type_id: "type-veg",
  top_seva_hours: 2,
  top_seva_share: 1,
  supported: true,
  giving_cents: 15100,
  gifts: 1,
  giving_withheld: false,
  is_you: false,
};

/** The same row as the server sent it to an ordinary devotee. */
const forDevotee: SevaYatraDevoteeSummary = {
  ...forPresident,
  score: null,
  giving_cents: null,
  gifts: null,
  giving_withheld: true,
};

const mockSummary = jest.fn();
let mockView: { role: string };

function answered(data: SevaYatraDevoteeSummary | null) {
  return { data, isLoading: false, isError: false, error: null, refetch: jest.fn() };
}

beforeEach(() => {
  mockView = { role: "devotee" };
  mockSummary.mockReset();
  mockSummary.mockImplementation(() => answered(forDevotee));
});

afterEach(cleanup);

const route = {
  params: {
    devoteeId: "d-kirtan",
    name: "Krsna Kirtan Das",
    photoUrl: null,
    range: "week" as const,
  },
};

async function open() {
  return render(
    <SevaBoardDevoteeScreen
      navigation={{ navigate: jest.fn() } as never}
      route={route as never}
    />,
  );
}

async function press(
  screen: { getByLabelText: (label: string) => unknown },
  label: string,
) {
  await act(async () => {
    fireEvent.press(screen.getByLabelText(label) as never);
  });
}

describe("what the congregation may read about a devotee", () => {
  it("publishes the points and the place, which the board already shows", async () => {
    const { getByText } = await open();

    expect(getByText("500")).toBeTruthy();
    expect(getByText("Rank 3 · Seva & Giving")).toBeTruthy();
    expect(getByText("2 hours")).toBeTruthy();
  });

  /**
   * The one thing that must never happen. `giving_cents` is null for every
   * caller the server withheld it from, and `formatCents(null ?? 0)` would put
   * "$0.00" against a devotee's name — the congregation reading that they gave
   * nothing, which is precisely what the server's null was preventing.
   */
  it("never renders a withheld figure as nought", async () => {
    const { getByText, queryByText } = await open();

    expect(queryByText("$0.00")).toBeNull();
    expect(queryByText("$151.00")).toBeNull();
    // What 0060 already publishes: that they gave, by name, with no amount.
    expect(getByText("Gave")).toBeTruthy();
    expect(getByText("Yes")).toBeTruthy();
  });

  it("says nothing at all about a devotee who did not give", async () => {
    mockSummary.mockImplementation(() =>
      answered({ ...forDevotee, supported: false }),
    );
    const { getByText, queryByText } = await open();

    expect(getByText("Gave")).toBeTruthy();
    expect(getByText("—")).toBeTruthy();
    expect(queryByText("$0.00")).toBeNull();
  });

  /** Gift counts are withheld with the cash, and a null is not "no gifts". */
  it("says nothing about gifts it was not told", async () => {
    const { queryByText } = await open();

    expect(queryByText(/gift.* counted towards this period/)).toBeNull();
  });

  it("offers no way into the President's reading of them", async () => {
    const { queryByLabelText } = await open();

    expect(queryByLabelText(/See all of .*'s seva/)).toBeNull();
  });
});

describe("what a President reads off the same row", () => {
  beforeEach(() => {
    mockView.role = "president";
    mockSummary.mockImplementation(() => answered(forPresident));
  });

  it("shows the amount, because the server sent one", async () => {
    const { getByText, queryByText } = await open();

    expect(getByText("Given")).toBeTruthy();
    expect(getByText("$151.00")).toBeTruthy();
    expect(queryByText("Yes")).toBeNull();
  });

  it("counts the gifts", async () => {
    const { getByText } = await open();

    expect(getByText("1 gift counted towards this period.")).toBeTruthy();
  });

  /** One destination, one name for it, wherever it is reached from. */
  it("offers their seva history by the name the temple gave it", async () => {
    const { getByLabelText, getByText } = await open();

    expect(
      getByLabelText("See Krsna Kirtan Das's seva history"),
    ).toBeTruthy();
    expect(getByText("Their seva history")).toBeTruthy();
  });

  /**
   * The points and the place are the same two integers either way. Whether a
   * devotee holds app.view_all changes what the server sends about giving and
   * nothing about where somebody stands.
   */
  it("reads the same place and the same points as everybody else", async () => {
    const { getByText } = await open();

    expect(getByText("500")).toBeTruthy();
    expect(getByText("Rank 3 · Seva & Giving")).toBeTruthy();
  });
});

/**
 * The board a place belongs to. `seva_yatra_devotee_summary` dense-ranks by the
 * combined score and by nothing else, so `standing` is a place on one board
 * however the reader arrived — and a devotee who tapped second place on "Seva
 * only" was shown a bare "Rank 3" and read it as their place there.
 */
describe("which board the drill-down is talking about", () => {
  it("names the board the rank is a place on", async () => {
    const { getByText, queryByText } = await open();

    expect(getByText("Rank 3 · Seva & Giving")).toBeTruthy();
    // Never the bare integer, which is the reading that was wrong.
    expect(queryByText("Rank 3")).toBeNull();
  });

  /** The figure the "Seva only" board showed against this same name. */
  it("publishes the seva half beside the combined figure", async () => {
    const { getByText } = await open();

    expect(getByText("500")).toBeTruthy();
    expect(getByText("Seva only · 390 points")).toBeTruthy();
  });

  // Most devotees give nothing in a period, and then the two boards agree.
  // Saying the same figure twice is the busyness the temple keeps asking about.
  it("says nothing about a second board where both agree", async () => {
    mockSummary.mockImplementation(() =>
      answered({ ...forDevotee, seva_points: 500 }),
    );
    const { queryByText } = await open();

    expect(queryByText(/Seva only/)).toBeNull();
  });

  it("says nothing about a second board it was told nothing about", async () => {
    mockSummary.mockImplementation(() =>
      answered({ ...forDevotee, seva_points: 0 }),
    );
    const { queryByText } = await open();

    expect(queryByText(/Seva only/)).toBeNull();
  });
});

describe("the ranges on the drill-down", () => {
  /** A year has no period row, so there is nothing to ask and no place to show. */
  it("asks the server nothing for the calendar year", async () => {
    const screen = await open();
    await press(screen, "Year");

    expect(
      screen.getByText(/A year is a read rather than a race/),
    ).toBeTruthy();
    expect(screen.queryByText(/^Rank 3/)).toBeNull();
    const calls = mockSummary.mock.calls;
    expect(calls[calls.length - 1][2]).toBe(false);
  });

  it.each(["Week", "Month", "All time"])(
    "asks about the %s period it is showing",
    async (label) => {
      const screen = await open();
      await press(screen, label);

      const calls = mockSummary.mock.calls;
      expect(calls[calls.length - 1][2]).toBe(true);
      expect(calls[calls.length - 1][1]).toBe(
        { Week: "week", Month: "month", "All time": "lifetime" }[label],
      );
    },
  );

  /**
   * The server answers with no row about a devotee who is not on this period's
   * board, and makes "opted out" and "served nothing" look the same on purpose.
   * One sentence has to be true of both, and it must not be an empty screen.
   */
  it("says nothing is published rather than drawing a blank", async () => {
    mockSummary.mockImplementation(() => answered(null));
    const { getByText, queryByText } = await open();

    expect(getByText("There is nothing published for this period.")).toBeTruthy();
    expect(queryByText("$0.00")).toBeNull();
    expect(queryByText(/^Rank 3/)).toBeNull();
  });
});
