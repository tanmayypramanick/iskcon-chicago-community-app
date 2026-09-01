/// <reference types="jest" />

/**
 * Seva Yatra, across the permutations the temple asked to be walked through:
 * every range, every board mode, both kinds of viewer, and the data states the
 * replica of their own database actually holds.
 *
 * The fixtures are not invented. `tanmayWeek` and `arpitaWeek` are
 * `my_seva_mala('week')` as the replica answered it for the two devotees, and
 * `garlandWeek` is the head of `list_seva_garland('week', 20, 'combined')` as
 * it answered an ordinary devotee — points and all.
 */

import {
  act,
  cleanup,
  fireEvent,
  render,
} from "@testing-library/react-native";

import type {
  MySevaMala,
  SevaGarlandRow,
  SevaPointsStatus,
} from "../../features/sevayatra/types";

const mockNavigate = jest.fn();

jest.mock("@react-navigation/native", () => ({
  useNavigation: () => ({
    navigate: mockNavigate,
    getParent: () => ({ navigate: jest.fn() }),
  }),
}));

jest.mock("../../lib/supabase", () => ({
  getSupabaseClient: () => ({ rpc: jest.fn() }),
}));

jest.mock("../../lib/connectivity", () => ({
  useServerReachable: () => mockScene.reachable,
  reportReachability: jest.fn(),
}));

jest.mock("../../features/access/hooks", () => ({
  useCurrentAccessProfile: () => ({ data: { role: mockScene.role } }),
}));

// Seva Care is its own screen with its own tests; rendering it here would drag
// in messaging and the query client for a section this file never opens.
jest.mock("../SevaCareScreen", () => ({
  SevaCarePanel: () => null,
}));

jest.mock("../../features/sevayatra/hooks", () => ({
  useMySevaMala: () => mockScene.mala,
  useMySevaProfile: () => mockScene.windows,
  useSevaGarland: (...args: unknown[]) => mockGarland(...args),
  useSevaSupporters: (...args: unknown[]) => mockSupporters(...args),
  useSevaActPoints: () => mockScene.actPoints,
  useSevaGivingPoints: () => mockScene.givingPoints,
  useDevoteeBadges: () => mockScene.badges,
  useDevoteeAwardShelf: () => mockScene.shelf,
  useSevaBadgeLegend: () => ({ data: [] }),
  useSetLeaderboardVisibility: () => ({
    mutate: jest.fn(),
    isPending: false,
    variables: undefined,
  }),
}));

import { usePrototypeSession } from "../../store/usePrototypeSession";
import { SevaYatraScreen } from "../SevaYatraScreen";

const ARPITA = "22222222-2222-2222-2222-222222222222";

type Query<Row> = {
  data: Row | undefined;
  isLoading: boolean;
  isError: boolean;
  error: unknown;
  refetch: () => void;
};

function answered<Row>(data: Row): Query<Row> {
  return { data, isLoading: false, isError: false, error: null, refetch: jest.fn() };
}

function loading<Row>(): Query<Row> {
  return {
    data: undefined,
    isLoading: true,
    isError: false,
    error: null,
    refetch: jest.fn(),
  };
}

function failed<Row>(message: string): Query<Row> {
  return {
    data: undefined,
    isLoading: false,
    isError: true,
    error: new Error(message),
    refetch: jest.fn(),
  };
}

/**
 * `my_seva_mala('week')` for Tanmay: first among the devotees he may see plus
 * himself, off the board, in a period 18 devotees served. The three are kept
 * apart here because 0067 made `standing` and `cohort_size` answer about
 * different populations.
 */
const tanmayWeek: MySevaMala = {
  period_id: "period-week",
  period_kind: "week",
  period_start: "2026-08-10",
  period_end: "2026-08-16",
  score: 0.789166,
  seva_minutes: 390,
  served_minutes: 480,
  served_acts: 4,
  seva_acts: 3,
  pending_acts: 1,
  pending_minutes: 90,
  giving_cents: 5100,
  gifts: 1,
  standing: 1,
  board_standing: null,
  cohort_size: 18,
  gathering: false,
  leaderboard_visible: false,
  awards_earned: 4,
};

/** Arpita: nothing credited, four hours actually served, two acts waiting. */
const arpitaWeek: MySevaMala = {
  ...tanmayWeek,
  score: 0,
  seva_minutes: 0,
  served_minutes: 240,
  served_acts: 2,
  seva_acts: 0,
  pending_acts: 2,
  pending_minutes: 240,
  giving_cents: 0,
  gifts: 0,
  standing: null,
  awards_earned: 1,
};

function garlandRow(over: Partial<SevaGarlandRow>): SevaGarlandRow {
  return {
    standing: 1,
    devotee_id: "devotee-1",
    devotee_name: "A devotee",
    devotee_photo_url: null,
    points: 100,
    tier: null,
    is_you: false,
    gathering: false,
    ...over,
  };
}

/** The head of the real week's board, ties and all. */
const garlandWeek: SevaGarlandRow[] = [
  garlandRow({ standing: 1, devotee_id: "d-ramesh", devotee_name: "Bhakta Ramesh Patel", points: 750, tier: "recognition" }),
  garlandRow({ standing: 2, devotee_id: "d-narottama", devotee_name: "Narottama Das", points: 570, tier: "recognition" }),
  garlandRow({ standing: 3, devotee_id: "d-kirtan", devotee_name: "Krsna Kirtan Das", points: 500, tier: "recognition" }),
  garlandRow({ standing: 4, devotee_id: "d-syama", devotee_name: "Syamasundara Das", points: 370 }),
  garlandRow({ standing: 7, devotee_id: "d-gopala", devotee_name: "Gopala Krishna Das", points: 340 }),
  garlandRow({ standing: 7, devotee_id: "d-gauranga", devotee_name: "Gauranga Das", points: 340 }),
];

/** The single flag row the server sends while the congregation is gathering. */
const gatheringRow = garlandRow({
  standing: null,
  devotee_id: null,
  devotee_name: null,
  points: null,
  gathering: true,
});

const supportersWeek = [
  { devotee_id: "d-kirtan", devotee_name: "Krsna Kirtan Das", devotee_photo_url: null },
  { devotee_id: "d-lalita", devotee_name: "Lalita Sakhi Devi Dasi", devotee_photo_url: null },
  { devotee_id: "d-narottama", devotee_name: "Narottama Das", devotee_photo_url: null },
];

function actPointRow(status: SevaPointsStatus, index = 0) {
  return {
    assignment_id: `act-${status}-${index}`,
    seva_name: "Kitchen Preparation",
    occurred_on: "2026-08-10",
    minutes: 120,
    points: 0,
    points_status: status,
    points_note: null,
    seva_points: 0,
    giving_points: 0,
    total_points: 0,
    attribution: "Shares of a window, not addends.",
  };
}

type Scene = {
  role: string;
  reachable: boolean;
  mala: Query<MySevaMala | null>;
  windows: Query<unknown[]>;
  garland: Query<SevaGarlandRow[]>;
  supporters: Query<typeof supportersWeek>;
  actPoints: Query<unknown[]>;
  givingPoints: Query<unknown[]>;
  badges: Query<unknown[]>;
  shelf: Query<unknown[]>;
};

let mockScene: Scene;
const mockGarland = jest.fn();
const mockSupporters = jest.fn();

beforeEach(() => {
  mockNavigate.mockReset();
  mockScene = {
    role: "devotee",
    reachable: true,
    mala: answered<MySevaMala | null>(tanmayWeek),
    windows: answered<unknown[]>([]),
    garland: answered(garlandWeek),
    supporters: answered(supportersWeek),
    actPoints: answered<unknown[]>([]),
    givingPoints: answered<unknown[]>([]),
    badges: answered<unknown[]>([]),
    shelf: answered<unknown[]>([]),
  };
  mockGarland.mockReset();
  mockSupporters.mockReset();
  mockGarland.mockImplementation(() => mockScene.garland);
  mockSupporters.mockImplementation(() => mockScene.supporters);
  usePrototypeSession.setState({ activeUserId: ARPITA });
});

// Explicit rather than left to the auto-cleanup: a screen left mounted goes on
// answering queries meant for the next one, and the permutation runs below
// open a great many of them.
afterEach(cleanup);

/**
 * Tap something and let the screen settle. React renders these concurrently,
 * so a press that is not awaited is a press the assertion runs in front of.
 */
async function press(screen: { getByLabelText: (label: string) => unknown }, label: string) {
  await act(async () => {
    fireEvent.press(screen.getByLabelText(label) as never);
  });
}

/** Open the screen, and optionally walk to a tab, a board mode and a range. */
async function open(options: { tab?: string; mode?: string; range?: string } = {}) {
  const screen = await render(<SevaYatraScreen />);
  if (options.range) await press(screen, options.range);
  if (options.tab) await press(screen, options.tab);
  if (options.mode) await press(screen, options.mode);
  return screen;
}

describe("the leaderboard an ordinary devotee sees", () => {
  /**
   * The board's points are `list_seva_garland`'s own published column. They
   * used to be read off `list_all_seva_scores`, which answers nobody without
   * app.view_all — so every devotee in the congregation was shown a ranked list
   * of names with no number anywhere on it.
   */
  it("shows the published points beside every name", async () => {
    const { getByText } = await open({ tab: "Leaderboard" });

    expect(getByText("Bhakta Ramesh Patel")).toBeTruthy();
    expect(getByText("750")).toBeTruthy();
    expect(getByText("570")).toBeTruthy();
    expect(getByText("370")).toBeTruthy();
  });

  it("keeps the server's dense ranking, ties included", async () => {
    const { getAllByLabelText } = await open({ tab: "Leaderboard" });

    // Two devotees share seventh, and neither is renumbered to eighth.
    expect(getAllByLabelText("Gopala Krishna Das, rank 7")).toHaveLength(1);
    expect(getAllByLabelText("Gauranga Das, rank 7")).toHaveLength(1);
  });

  /**
   * "Seva only" and "Supporters" both told a devotee they were still being
   * built. Both have been deployed since 0060 and both answer the whole
   * congregation; only the President was ever shown them.
   */
  it("draws the seva board rather than calling it unbuilt", async () => {
    const { queryByText, getByText } = await open({
      tab: "Leaderboard",
      mode: "Seva only",
    });

    expect(queryByText("Opening soon")).toBeNull();
    expect(getByText("Bhakta Ramesh Patel")).toBeTruthy();
    expect(mockGarland).toHaveBeenCalledWith("week", "seva", true);
  });

  it("draws the wall of thanks rather than calling it unbuilt", async () => {
    const { queryByText, getByText } = await open({
      tab: "Leaderboard",
      mode: "Supporters",
    });

    expect(queryByText("Opening soon")).toBeNull();
    expect(getByText("With thanks")).toBeTruthy();
    expect(getByText("Lalita Sakhi Devi Dasi")).toBeTruthy();
  });

  /**
   * `list_seva_garland` raises rather than falling through when it is handed a
   * rank it does not know, so the supporters mode must ask it for nothing at
   * all — and the two boards must not answer for one another in the cache.
   */
  it("never asks the garland to rank the supporters", async () => {
    await open({ tab: "Leaderboard", mode: "Supporters" });

    for (const call of mockGarland.mock.calls) {
      expect(call[1]).not.toBe("supporters");
    }
    // Once the mode is showing, the garland is not the read behind it.
    expect(mockGarland.mock.calls[mockGarland.mock.calls.length - 1][2]).toBe(
      false,
    );
    expect(mockSupporters).toHaveBeenCalledWith("week", true);
  });
});

describe("a devotee who is not on the board", () => {
  /**
   * `my_seva_mala` sends `standing` and `board_standing` apart on purpose: the
   * first is where they actually are and only they can read it, the second is
   * where the congregation sees them. The screen used to show only the second,
   * so a devotee at the top of the temple was shown no rank at all — while the
   * switch beside it promised that opting out "only decides whether other
   * devotees see your name".
   */
  it("still tells them their own place, and says only they can see it", async () => {
    const { getByText } = await open();

    expect(getByText("Rank 1, seen only by you")).toBeTruthy();
  });

  /**
   * 0067 section 5 narrowed `standing` to the devotees the caller may see plus
   * themselves, and left `cohort_size` as the period's whole participant count.
   * The screen used to print them together as "Rank 1 of 18" — a rank taken
   * over one population, "of" the size of another, and on this row the 18
   * includes the very devotees the new population excludes.
   */
  it("does not count the rank against a population it was not taken over", async () => {
    const { queryByText } = await open();

    expect(queryByText(/of 18/)).toBeNull();
  });

  it("says why the board has no row for them", async () => {
    const { getByText } = await open({ tab: "Leaderboard" });

    expect(getByText(/You asked to be left off/)).toBeTruthy();
  });

  /** An empty board is exactly where "where am I?" is loudest. */
  it("says it under an empty board too", async () => {
    mockScene.garland = answered<SevaGarlandRow[]>([]);
    const { getByText } = await open({ tab: "Leaderboard" });

    expect(getByText(/Nobody has appeared on the board/)).toBeTruthy();
    expect(getByText(/You asked to be left off/)).toBeTruthy();
  });

  /** The wall of thanks is not a board and does not rank anybody. */
  it("does not claim they were left off a ranking they are looking away from", async () => {
    const { queryByText } = await open({ tab: "Leaderboard", mode: "Supporters" });

    expect(queryByText(/You asked to be left off/)).toBeNull();
  });

  it("shows the medal instead once they are on the board", async () => {
    mockScene.mala = answered<MySevaMala | null>({
      ...tanmayWeek,
      board_standing: 1,
      leaderboard_visible: true,
    });
    const { getByText, getByLabelText, queryByText } = await open();

    expect(getByText("Rank 1")).toBeTruthy();
    expect(queryByText(/seen only by you/)).toBeNull();

    await press({ getByLabelText }, "Leaderboard");
    expect(queryByText(/You asked to be left off/)).toBeNull();
  });
});

describe("a week with hours served and nothing credited", () => {
  beforeEach(() => {
    mockScene.mala = answered<MySevaMala | null>(arpitaWeek);
  });

  /**
   * Four hours actually stood there, nought points, and the temple's complaint
   * was a bare 0. The hours are the ones she served, and the reason for the
   * nought is above the number rather than left to be guessed at.
   */
  it("shows the hours she served, not the hours the scoring paid for", async () => {
    const { getByText } = await open();

    expect(getByText("4 hours")).toBeTruthy();
    expect(getByText("0 hours counted so far")).toBeTruthy();
  });

  /**
   * The server distinguishes three waiting states and only one of them is
   * somebody else's to do. Telling her all three are "to be confirmed" sends
   * her to the office about an act she could finish herself.
   */
  it("names what each waiting act is actually waiting on", async () => {
    mockScene.actPoints = answered<unknown[]>([
      actPointRow("not_served"),
      actPointRow("awaiting_completion"),
      actPointRow("awaiting_verification"),
    ]);
    const { getByText } = await open();

    expect(getByText("2 acts still to be marked done and verified")).toBeTruthy();
  });

  it("says so for a week waiting on confirmation alone", async () => {
    mockScene.actPoints = answered<unknown[]>([
      actPointRow("awaiting_confirmation", 1),
      actPointRow("awaiting_confirmation", 2),
    ]);
    const { getByText } = await open();

    expect(getByText("2 acts still to be confirmed")).toBeTruthy();
  });

  it("says so for a week waiting on all three", async () => {
    mockScene.actPoints = answered<unknown[]>([
      actPointRow("awaiting_completion"),
      actPointRow("awaiting_verification"),
      actPointRow("awaiting_confirmation"),
    ]);
    const { getByText } = await open();

    expect(
      getByText("2 acts still to be marked done, verified and confirmed"),
    ).toBeTruthy();
  });

  it("never leaves the nought standing on its own", async () => {
    const { getByText } = await open();

    expect(getByText(/Your points arrive as each act is/)).toBeTruthy();
  });
});

/**
 * A ranked range leads with points, so the hours are said once — in the card,
 * under a label — and the counted figure sits beneath them rather than beside
 * them as a second cell of its own.
 */
describe("a ranked week", () => {
  it("prints the hours served exactly once", async () => {
    const { getAllByText, getByText } = await open();

    // 480 served minutes, 390 of them credited.
    expect(getAllByText("8 hours")).toHaveLength(1);
    expect(getByText("Hours served")).toBeTruthy();
    expect(getByText("6.5 hours counted so far")).toBeTruthy();
  });
});

describe("the calendar year", () => {
  beforeEach(() => {
    mockScene.windows = answered<unknown[]>([
      {
        window_kind: "year",
        window_start: "2026-01-01",
        window_end: "2026-12-31",
        acts: 12,
        hours: 23.5,
        counted_hours: 17.5,
        pending_acts: 2,
        giving_cents: 4200,
      },
    ]);
  });

  /** A year has no period row, so there is nothing to rank and no points. */
  it("shows hours rather than points", async () => {
    const { getAllByText, getByText, queryByText } = await open({
      range: "Year",
    });

    expect(getAllByText("23.5 hours").length).toBeGreaterThan(0);
    expect(getByText(/of seva/)).toBeTruthy();
    expect(queryByText("seva points")).toBeNull();
  });

  /**
   * The hero on an unranked range IS the hours served, and the card one element
   * beneath it printed the same figure again under a label of its own — the
   * temple's "things appear twice" in its plainest form. The hero's own line
   * now carries the only thing the big figure does not say, which is how much
   * of it has been counted, and the card below is down to what was given.
   */
  it("prints the year's hours once, on the screen and in the card", async () => {
    const { getAllByText, getByText, queryByText } = await open({
      range: "Year",
    });

    expect(getAllByText("23.5 hours")).toHaveLength(1);
    expect(queryByText("Hours served")).toBeNull();
    expect(queryByText("Hours counted")).toBeNull();
    expect(getByText("of seva · 17.5 hours counted so far")).toBeTruthy();
    expect(getByText("Given")).toBeTruthy();
  });

  /** And where every hour has been signed off, the counted figure is not a
   * second printing of the same number either. */
  it("says all of it counted rather than saying the figure again", async () => {
    mockScene.windows = answered<unknown[]>([
      {
        window_kind: "year",
        window_start: "2026-01-01",
        window_end: "2026-12-31",
        acts: 12,
        hours: 23.5,
        counted_hours: 23.5,
        pending_acts: 0,
        giving_cents: 4200,
      },
    ]);
    const { getAllByText, getByText } = await open({ range: "Year" });

    expect(getAllByText("23.5 hours")).toHaveLength(1);
    expect(getByText("of seva · all of it counted")).toBeTruthy();
  });

  it("says a year is a read rather than a race", async () => {
    const { getByText } = await open({ range: "Year" });

    expect(getByText(/A year is a read rather than a race/)).toBeTruthy();
  });

  it("draws no board for it, and asks the server for none", async () => {
    const { getByText } = await open({ range: "Year", tab: "Leaderboard" });

    expect(getByText("Not a ranked period")).toBeTruthy();
    // `seva_mala_periods` holds no row of kind 'year', so both functions would
    // answer with nothing. The round trip is spared and, more to the point, an
    // empty answer is not the sentence this screen needs to say.
    const last = <T,>(calls: T[]) => calls[calls.length - 1];
    // (period, rank, enabled) and (period, enabled).
    expect(last(mockGarland.mock.calls)[2]).toBe(false);
    expect(last(mockSupporters.mock.calls)[1]).toBe(false);
  });

  /** Including from the supporters mode, which has no year either. */
  it("says the same from every board mode", async () => {
    const { getByText } = await open({
      range: "Year",
      tab: "Leaderboard",
      mode: "Supporters",
    });

    expect(getByText("Not a ranked period")).toBeTruthy();
  });
});

describe("a congregation still gathering", () => {
  beforeEach(() => {
    // Under the minimum cohort the server withholds both standings — the
    // public one and the devotee's own — while still counting their hours.
    mockScene.mala = answered<MySevaMala | null>({
      ...tanmayWeek,
      standing: null,
      board_standing: null,
      gathering: true,
    });
    mockScene.garland = answered([gatheringRow]);
  });

  /** The server's flag row is a state of its own, never an empty board. */
  it("says the board is not drawn yet rather than showing nothing", async () => {
    const { getByText, queryByText } = await open({ tab: "Leaderboard" });

    expect(getByText("Still gathering")).toBeTruthy();
    expect(queryByText(/Nobody has appeared on the board/)).toBeNull();
  });

  it("does not blame the devotee for the absence of a rank", async () => {
    const { queryByText } = await open({ tab: "Leaderboard" });

    expect(queryByText(/You asked to be left off/)).toBeNull();
  });

  it("tells them on their own profile that their seva still counts", async () => {
    const { getByText } = await open();

    expect(getByText(/Your seva is counted all the same/)).toBeTruthy();
  });
});

describe("when the server cannot be read", () => {
  it("offers a retry rather than an empty board", async () => {
    mockScene.garland = failed<SevaGarlandRow[]>("boom");
    const { getByText } = await open({ tab: "Leaderboard" });

    expect(getByText("Retry")).toBeTruthy();
  });

  it("reports the supporters read failing, not the board's", async () => {
    mockScene.supporters = failed<typeof supportersWeek>("boom");
    const { getByText } = await open({ tab: "Leaderboard", mode: "Supporters" });

    expect(getByText("Retry")).toBeTruthy();
  });

  it("waits rather than claiming an empty board while it loads", async () => {
    mockScene.garland = loading<SevaGarlandRow[]>();
    const { queryByText } = await open({ tab: "Leaderboard" });

    expect(queryByText(/Nobody has appeared on the board/)).toBeNull();
  });

  it("shows the offline card rather than an empty one", async () => {
    mockScene.reachable = false;
    mockScene.garland = answered<SevaGarlandRow[]>([]);
    const { getByText } = await open({ tab: "Leaderboard" });

    expect(getByText(/offline|connection/i)).toBeTruthy();
  });
});

describe("what each role is offered", () => {
  it.each(["devotee", "volunteer", "core"])(
    "keeps Seva Care away from a %s",
    async (role) => {
      mockScene.role = role;
      const { queryByText } = await open();

      expect(queryByText("Seva Care")).toBeNull();
    },
  );

  it.each(["president", "tech"])("offers Seva Care to a %s", async (role) => {
    mockScene.role = role;
    const { queryByText } = await open();

    expect(queryByText("Seva Care")).toBeTruthy();
  });

  /**
   * The three modes are the same three for everybody now. A Community Head
   * holds no app.view_all, and used to be told two of them were unbuilt — as
   * did every ordinary devotee in the congregation.
   */
  it.each(
    ["devotee", "volunteer", "core", "president", "tech"].flatMap((role) =>
      ["Seva & Giving", "Seva only", "Supporters"].map(
        (mode) => [role, mode] as const,
      ),
    ),
  )("draws the %s board for a %s", async (role, mode) => {
    mockScene.role = role;
    const { queryByText } = await open({ tab: "Leaderboard", mode });

    expect(queryByText("Opening soon")).toBeNull();
  });
});

/**
 * The grid the temple asked to be walked: every range against every board mode.
 * Nothing may render as a blank screen, nothing may claim to be unbuilt, and
 * nothing that is not a year may be labelled one.
 */
const grid = ["Week", "Month", "Year", "All time"].flatMap((range) =>
  ["Seva & Giving", "Seva only", "Supporters"].map(
    (mode) => [range, mode] as const,
  ),
);

describe("every range against every board mode", () => {
  it.each(grid)("draws something honest for %s / %s", async (range, mode) => {
    const screen = await open({ range, tab: "Leaderboard", mode });

    // A year is the one range with no board behind it, and it must say so
    // rather than showing an empty one — in every mode, including supporters.
    expect(Boolean(screen.queryByText("Not a ranked period"))).toBe(
      range === "Year",
    );
    expect(screen.queryByText("Opening soon")).toBeNull();
  });
});

describe("what the board notice does not do", () => {
  /** A failure is a failure. Explaining an absence nobody can see is noise. */
  it("stays quiet under a board that could not be read", async () => {
    mockScene.garland = failed<SevaGarlandRow[]>("boom");
    const { queryByText } = await open({ tab: "Leaderboard" });

    expect(queryByText(/You asked to be left off/)).toBeNull();
  });

  /**
   * Until `my_seva_mala` has answered, the flag is unknown — and telling a
   * devotee they opted out when they did not is worse than saying nothing.
   */
  it("stays quiet until the flag has arrived", async () => {
    mockScene.mala = loading<MySevaMala | null>();
    const { queryByText } = await open({ tab: "Leaderboard" });

    expect(queryByText(/You asked to be left off/)).toBeNull();
  });
});

/**
 * A board where two devotees show the same number.
 *
 * 0067 section 4 moved the ranking onto the published points, so the board now
 * dense-ranks on the integer it prints and two equal integers share a place.
 * `garlandSevaWeek` is the head of the real `list_seva_garland('week', 20,
 * 'seva')` off the replica: 1, 2, 3, 3, 4, 4.
 */
const garlandSevaWeek: SevaGarlandRow[] = [
  garlandRow({ standing: 1, devotee_id: "d-ramesh", devotee_name: "Bhakta Ramesh Patel", points: 980, tier: "recognition" }),
  garlandRow({ standing: 2, devotee_id: "d-syama", devotee_name: "Syamasundara Das", points: 480, tier: "recognition" }),
  garlandRow({ standing: 3, devotee_id: "d-acyuta", devotee_name: "Acyuta Gopal Das", points: 450, tier: "recognition" }),
  garlandRow({ standing: 3, devotee_id: "d-jahnava", devotee_name: "Jahnava Devi Dasi", points: 450, tier: "recognition" }),
  garlandRow({ standing: 4, devotee_id: "d-gauranga", devotee_name: "Gauranga Das", points: 440 }),
  garlandRow({ standing: 4, devotee_id: "d-gopala", devotee_name: "Gopala Krishna Das", points: 440 }),
];

/**
 * A podium column and a list row are both Pressables carrying the devotee's
 * name and place, and the thing that tells them apart is that a row is laid out
 * across and a column is not. Read off the element rather than asserted as a
 * string, so the check is "these two are drawn the same way" rather than a copy
 * of either one's classes.
 */
function laidOutAcross(element: { props: { className?: string } }) {
  return Boolean(element.props.className?.includes("flex-row"));
}

describe("a place two devotees share", () => {
  beforeEach(() => {
    mockScene.garland = answered(garlandSevaWeek);
  });

  /**
   * The regression this exists for. The podium was `board.slice(0, 3)` — the
   * first three ROWS — so of the two devotees tied for third, whichever the
   * server's name ordering happened to put first stood on the podium and the
   * other became the first row of the list underneath. Both were labelled
   * "rank 3", and nothing a devotee could see decided which got which.
   */
  it("draws both devotees who share third place the same way", async () => {
    const { getByLabelText } = await open({
      tab: "Leaderboard",
      mode: "Seva only",
    });

    const acyuta = getByLabelText("Acyuta Gopal Das, rank 3");
    const jahnava = getByLabelText("Jahnava Devi Dasi, rank 3");

    expect(laidOutAcross(jahnava)).toBe(laidOutAcross(acyuta));
    // And on the podium rather than in the list: a shared third place is still
    // third place, and demoting one of the two is what the slice used to do.
    expect(laidOutAcross(acyuta)).toBe(false);
  });

  /** Nobody counted twice, and nobody quietly lost between the two lists. */
  it("puts every devotee on the board exactly once", async () => {
    const { getAllByLabelText } = await open({
      tab: "Leaderboard",
      mode: "Seva only",
    });

    for (const label of [
      "Bhakta Ramesh Patel, rank 1",
      "Syamasundara Das, rank 2",
      "Acyuta Gopal Das, rank 3",
      "Jahnava Devi Dasi, rank 3",
      "Gauranga Das, rank 4",
      "Gopala Krishna Das, rank 4",
    ]) {
      expect(getAllByLabelText(label)).toHaveLength(1);
    }
  });

  /** The board says 1, 2, 3, 3, 4, 4 — never renumbered to 1, 2, 3, 4, 5, 6. */
  it("keeps the server's own numbering across the podium", async () => {
    const { getAllByText } = await open({
      tab: "Leaderboard",
      mode: "Seva only",
    });

    expect(getAllByText("450")).toHaveLength(2);
    expect(getAllByText("440")).toHaveLength(2);
  });

  /**
   * Three golds and two silvers is five columns on a 320dp phone, which is a
   * row of slivers. The board falls back to a plain ranked list, which still
   * carries every place exactly as the server dense-ranked it.
   */
  it("falls back to a list when the top three places are too crowded", async () => {
    mockScene.garland = answered([
      garlandRow({ standing: 1, devotee_id: "d-a", devotee_name: "Devotee A", points: 500 }),
      garlandRow({ standing: 1, devotee_id: "d-b", devotee_name: "Devotee B", points: 500 }),
      garlandRow({ standing: 1, devotee_id: "d-c", devotee_name: "Devotee C", points: 500 }),
      garlandRow({ standing: 2, devotee_id: "d-d", devotee_name: "Devotee D", points: 490 }),
      garlandRow({ standing: 2, devotee_id: "d-e", devotee_name: "Devotee E", points: 490 }),
    ]);
    const { getByLabelText } = await open({ tab: "Leaderboard" });

    expect(laidOutAcross(getByLabelText("Devotee A, rank 1"))).toBe(true);
    expect(laidOutAcross(getByLabelText("Devotee E, rank 2"))).toBe(true);
  });
});

/**
 * A badge that stops qualifying between two reads.
 *
 * 0067 section 1 re-asks a `derived_threshold` or `personal` rule at read time
 * while its period is still open, so a badge earned on Tuesday against a bar
 * the congregation has since walked past is no longer displayed. Nothing is
 * revoked — `devotee_awards` is append-only — so the shelf still holds it and
 * `is_current` is the only thing that moved. On the replica this is exactly
 * Madhava Priya Das's Dhairya and his weekly Recognition, both on the open week.
 */
function shelfRow(over: Record<string, unknown>) {
  return {
    award_id: "award-1",
    award_code: "weekly_recognition",
    title: "Recognition",
    description: "A week's steady seva.",
    tier: "recognition",
    garland_kind: null,
    rule_kind: "derived_threshold",
    period_kind: "week",
    period_start: "2026-08-03",
    period_end: "2026-08-09",
    awarded_on: "2026-08-12",
    awarded_by: null,
    citation: null,
    fulfilled_on: null,
    fulfilment_note: null,
    is_current: true,
    ...over,
  };
}

describe("a badge that stops qualifying", () => {
  it("says nothing is on show without saying anything was taken back", async () => {
    // The read after the bar moved: the public list is empty, the shelf is not.
    mockScene.badges = answered<unknown[]>([]);
    mockScene.shelf = answered<unknown[]>([
      shelfRow({ award_id: "a-dhairya", award_code: "weekly_dhairya", title: "Dhairya", period_start: "2026-08-10", period_end: "2026-08-16", is_current: false }),
    ]);
    const { getByText, queryByText } = await open();

    expect(
      getByText(/Nothing of yours is on show for this period/),
    ).toBeTruthy();
    // Said once, over the shelf, rather than on every row of it.
    expect(
      getByText("Not on show right now, and yours for good."),
    ).toBeTruthy();
    // Never the language of a badge being lost.
    expect(queryByText(/revoked|taken away|expired|lost/i)).toBeNull();
  });

  /**
   * The shelf is the one place both states are on screen at once, and the
   * temple's own seed gives a good quarter five rows titled "Recognition" —
   * weekly and monthly, several periods each. They are all awarded the same day,
   * so "Recognition · Recognition · earned Aug 12" was printed five times over
   * and the row that was still on show could not be told from the four that
   * were not.
   */
  it("says which week or month each award on the shelf was for", async () => {
    mockScene.badges = answered<unknown[]>([]);
    mockScene.shelf = answered<unknown[]>([
      shelfRow({ award_id: "a-open", period_start: "2026-08-10", period_end: "2026-08-16", is_current: false }),
      shelfRow({ award_id: "a-closed", is_current: true }),
    ]);
    const { getAllByText, getByText } = await open();

    expect(getAllByText("Recognition")).toHaveLength(2);
    expect(getByText(/Mon, Aug 10 – Sun, Aug 16/)).toBeTruthy();
    expect(getByText(/Mon, Aug 3 – Sun, Aug 9/)).toBeTruthy();
  });

  /**
   * An award with no scored period behind it — "Your First Seva" is anchored to
   * a lifetime period starting in 1970 — must not have that drawn as a range.
   */
  it("does not date an award that belongs to no week or month", async () => {
    mockScene.badges = answered<unknown[]>([]);
    mockScene.shelf = answered<unknown[]>([
      shelfRow({
        award_id: "a-first",
        award_code: "first_seva",
        title: "Your First Seva",
        rule_kind: "personal",
        period_kind: "lifetime",
        period_start: "1970-01-01",
        period_end: "2026-08-12",
        is_current: false,
      }),
    ]);
    const { getByText, queryByText } = await open();

    expect(queryByText(/1970/)).toBeNull();
    expect(getByText(/earned Wed, Aug 12/)).toBeTruthy();
  });
});

/**
 * The two badge presentations, which used to be one presentation drawn twice:
 * the strip of medallions and the shelf beneath it both listed every current
 * badge, so three badges arrived as six cards on one screen.
 */
describe("badges and the shelf", () => {
  const badge = (over: Record<string, unknown>) => ({
    award_id: "a-dhairya",
    award_code: "weekly_dhairya",
    title: "Dhairya",
    description: "Perseverance.",
    tier: "recognition",
    garland_kind: null,
    period_kind: "week",
    period_start: "2026-08-10",
    period_end: "2026-08-16",
    awarded_on: "2026-08-12",
    ...over,
  });

  beforeEach(() => {
    mockScene.badges = answered<unknown[]>([badge({})]);
    mockScene.shelf = answered<unknown[]>([
      // The same award, as the shelf carries it — it never leaves.
      shelfRow({ award_id: "a-dhairya", title: "Dhairya", is_current: true }),
      shelfRow({ award_id: "a-earlier", title: "Ruci", is_current: false }),
    ]);
  });

  it("draws a badge that is on show once, as a medallion", async () => {
    const { getAllByText } = await open();

    expect(getAllByText("Dhairya")).toHaveLength(1);
  });

  /** The shelf answers the other question: what else have I been given. */
  it("keeps the shelf for what the profile is not showing", async () => {
    const { getByText } = await open();

    expect(getByText("Kept on your shelf")).toBeTruthy();
    expect(getByText("Ruci")).toBeTruthy();
  });

  /** Nothing on it is ever described as lost, taken back or expired. */
  it("says a kept award is still theirs", async () => {
    const { getByText, queryByText } = await open();

    expect(getByText("Not on show right now, and yours for good.")).toBeTruthy();
    expect(queryByText(/revoked|taken away|expired|lost/i)).toBeNull();
  });
});
