/// <reference types="jest" />

import { cleanup, render } from "@testing-library/react-native";

// The helpers under test are pure, but importing the screen reaches the
// Supabase client, which opens a database on load.
jest.mock("../../lib/supabase", () => ({
  getSupabaseClient: () => ({ rpc: jest.fn() }),
}));

jest.mock("../../lib/connectivity", () => ({
  useServerReachable: () => true,
  reportReachability: jest.fn(),
}));

jest.mock("@react-navigation/native", () => ({
  useNavigation: () => ({ navigate: jest.fn(), getParent: () => null }),
}));

jest.mock("@tanstack/react-query", () => ({
  useQuery: () => ({ data: [], isLoading: false, isError: false, error: null }),
  useQueryClient: () => ({ invalidateQueries: jest.fn() }),
}));

jest.mock("../../features/access/hooks", () => ({
  useCurrentAccessProfile: () => ({ data: { role: "president" } }),
}));

jest.mock("../../features/messaging/api", () => ({
  openConversation: jest.fn(),
}));

jest.mock("../../features/sevayatra/hooks", () => ({
  sevaYatraKeys: {
    concentration: () => ["seva-yatra", "concentration"],
    narrowness: () => ["seva-yatra", "narrowness"],
  },
  useDismissSevaCare: () => ({ mutate: mockDismiss }),
  useSevaBalanceThresholds: () => ({ data: null }),
  useSevaConcentration: () => mockList(mockCarried),
  useSevaNarrowness: () => mockList(mockNarrow),
}));

import type {
  SevaConcentrationRow,
  SevaNarrownessRow,
} from "../../features/sevayatra/types";
import {
  careEmptyState,
  clearOutcome,
  concentrationEntries,
  narrownessEntries,
  SevaCarePanel,
  withoutRepeats,
} from "../SevaCareScreen";

/**
 * A row as 202608040066 answers it: `hours_this_week` and `hours_this_month`
 * are Chicago's own calendar week and month, and `hours_per_week` is still the
 * rate over the trailing quarter beside them. Sixteen hours in a week is not
 * 8.4 hours a week, and the screen must not say the second when it has the
 * first.
 */
function concentration(
  over: Partial<SevaConcentrationRow> = {},
): SevaConcentrationRow {
  return {
    devotee_id: "devotee-radha",
    devotee_name: "Radha Devi",
    service_type_id: "type-pots",
    seva_name: "Pot washing",
    category: "Kitchen",
    hours_per_week: 8.4,
    hours_this_week: 16,
    hours_this_month: 41.5,
    hours_trailing_quarter: 109.2,
    consecutive_weeks: 11,
    share_of_their_seva: 0.82,
    weekly_hours_vs_median: 4.2,
    share_vs_congregation: 1.9,
    pronouncedness: 2.4,
    first_served_on: "2026-03-02",
    last_served_on: "2026-08-10",
    min_hours_used: 4,
    min_weeks_used: 4,
    note: "…",
    ...over,
  } as SevaConcentrationRow;
}

/**
 * `list_seva_narrowness` is 202608040058's function and 0066 did not touch it,
 * so it still carries only the trailing quarter — its two figures are averages
 * over ninety days however new the database is.
 */
function narrowness(over: Partial<SevaNarrownessRow> = {}): SevaNarrownessRow {
  return {
    devotee_id: "devotee-gopal",
    devotee_name: "Gopal Das",
    category: "Kitchen",
    hours_trailing_quarter: 39,
    category_share: 0.95,
    untouched_categories: ["Deity worship"],
    untouched_share_of_congregation: 0.4,
    min_hours_used: 4,
    min_share_used: 0.8,
    note: "…",
    ...over,
  } as SevaNarrownessRow;
}

/** What the two list hooks answer with in the render tests below. */
const mockDismiss = jest.fn();
let mockCarried: SevaConcentrationRow[] = [];
let mockNarrow: SevaNarrownessRow[] = [];

function mockList<Row>(rows: readonly Row[]) {
  return {
    data: rows,
    isLoading: false,
    isError: false,
    error: null,
    refetch: jest.fn(),
  };
}

beforeEach(() => {
  mockDismiss.mockReset();
  mockCarried = [];
  mockNarrow = [];
});

afterEach(cleanup);

describe("the figures on a Seva Care row", () => {
  it("leads with the quarter, and keeps the real week and month beside it", () => {
    const [entry] = concentrationEntries([concentration()]);

    expect(entry.quarter).toBe(109.2);
    expect(entry.week).toBe(16);
    expect(entry.month).toBe(41.5);
  });

  // A database that has not had 0066 applied sends neither column. The row is
  // still perfectly drawable from the quarter, which is what it is measured on.
  it("says nothing about a week a pre-0066 server did not send", () => {
    const [entry] = concentrationEntries([
      concentration({ hours_this_week: null, hours_this_month: null }),
    ]);

    expect(entry.quarter).toBe(109.2);
    expect(entry.week).toBeNull();
    expect(entry.month).toBeNull();
  });

  /**
   * `list_seva_narrowness` is 0058's function and 0066 did not touch it, so its
   * rows carry a quarter alone. They used to have a week and a month divided
   * out of that quarter and printed under "A week" and "A month" — figures the
   * server never sent, beside a concentration row whose week was real.
   */
  it("divides no week out of the narrowness list's quarter", () => {
    const [narrow] = narrownessEntries([narrowness()]);

    expect(narrow.quarter).toBe(39);
    expect(narrow.week).toBeNull();
    expect(narrow.month).toBeNull();
  });

  /**
   * A concentration row clears the one seva it names, and nothing wider.
   * `dismiss_seva_care_row` with no service type is the server's own wording
   * for the whole devotee, and `list_seva_concentration` drops every row for a
   * devotee carrying one of those.
   */
  it("scopes a cleared concentration row to the seva it named", () => {
    const [entry] = concentrationEntries([concentration()]);

    expect(entry.serviceTypeId).toBe("type-pots");
    expect(entry.dismissible).toBe(true);
  });

  /**
   * The dismissal a narrowness row used to send. It is about a whole category,
   * so it has no service type to scope to — the only write available to it was
   * the whole-devotee one, which took the devotee off the burnout list for
   * ninety days while leaving the narrowness row exactly where it was, because
   * `list_seva_narrowness` reads no dismissal at all.
   */
  it("offers no dismissal at all from a narrowness row", () => {
    const [entry] = narrownessEntries([narrowness()]);

    expect(entry.dismissible).toBe(false);
    expect(entry.serviceTypeId).toBeNull();
  });
});

describe("clearing a row", () => {
  it("takes the row away only once the server has written it", () => {
    expect(clearOutcome("Radha Devi", { kind: "saved" })).toEqual({
      stays: true,
      message: null,
    });
  });

  /**
   * The failure the old screen swallowed. The row was hidden whatever happened,
   * so a President was left believing a conversation had been recorded and
   * found the devotee listed again with nothing to explain it.
   */
  it("puts the row back and names the devotee when the write fails", () => {
    const outcome = clearOutcome("Radha Devi", {
      kind: "failed",
      error: new Error("permission denied for function dismiss_seva_care"),
    });

    expect(outcome.stays).toBe(false);
    expect(outcome.message).toContain("permission denied");
  });

  it("falls back to wording that names the devotee when the error says nothing", () => {
    const outcome = clearOutcome("Radha Devi", { kind: "failed", error: {} });

    expect(outcome.stays).toBe(false);
    expect(outcome.message).toContain("Radha Devi");
    expect(outcome.message).toContain("still on the list");
  });

  // A database behind on 0066 has no function to call. Nothing was recorded,
  // so nothing may be claimed.
  it("keeps the row where the function is not there to call", () => {
    const outcome = clearOutcome("Radha Devi", { kind: "unsupported" });

    expect(outcome.stays).toBe(false);
    expect(outcome.message).toContain("Radha Devi");
  });
});

describe("the empty list", () => {
  /**
   * 0066's third gate makes this the ordinary state, so it has to read as a
   * finished thing rather than as a screen that failed to load.
   */
  it("says why an empty list is the temple in good order", () => {
    const empty = careEmptyState({ gathering: false, handled: 0 });

    expect(empty.title).toBe("Nobody stands out");
    expect(empty.body).toContain("empty most weeks");
    expect(empty.hint).toContain("week after week");
  });

  it("does not congratulate anybody when there was too little to measure", () => {
    const empty = careEmptyState({ gathering: true, handled: 0 });

    expect(empty.title).not.toBe("Nobody stands out");
    expect(empty.body).toContain("not drawn");
  });

  it("counts what was cleared, and says how long it holds", () => {
    const empty = careEmptyState({ gathering: false, handled: 2 });

    expect(empty.title).toBe("All handled");
    expect(empty.body).toContain("2 devotees cleared");
    expect(empty.body).toContain("left the quarter");
  });
});

/**
 * The panel itself, because the whole of this fix is which rows carry a control
 * and what the screen says about it. A coordinator must not be able to take a
 * devotee off the burnout list by acting on a row whose own copy says "Not a
 * problem in itself".
 */
describe("the cross on a Seva Care row", () => {
  it("is offered on a concentration row, which the server can honour", async () => {
    mockCarried = [concentration()];
    mockNarrow = [];
    const { getByLabelText } = await render(<SevaCarePanel />);

    expect(getByLabelText("Clear Radha Devi from Seva Care")).toBeTruthy();
  });

  it("is not offered on a narrowness row", async () => {
    mockCarried = [];
    mockNarrow = [narrowness()];
    const { getByText, queryByLabelText } = await render(<SevaCarePanel />);

    expect(getByText("Gopal Das")).toBeTruthy();
    expect(queryByLabelText("Clear Gopal Das from Seva Care")).toBeNull();
    expect(queryByLabelText(/Clear .* from Seva Care/)).toBeNull();
  });

  /** The absent control is explained where the section is introduced. */
  it("says there is nothing to clear on the narrowness section", async () => {
    mockCarried = [];
    mockNarrow = [narrowness()];
    const { getByText } = await render(<SevaCarePanel />);

    expect(
      getByText(
        "A question about the rota, not about the devotee. There is nothing here to clear.",
      ),
    ).toBeTruthy();
  });

  /**
   * The devotee who was actually lost to this. Dismissing his narrowness row
   * sent `dismiss_seva_care_row(devotee, null)` — the whole devotee — and took
   * the temple's most over-concentrated server off Seva Care for ninety days.
   */
  it("writes no dismissal when a devotee is on both lists", async () => {
    mockCarried = [
      concentration({
        devotee_id: "d-ramesh",
        devotee_name: "Bhakta Ramesh Patel",
      }),
    ];
    mockNarrow = [
      narrowness({
        devotee_id: "d-ramesh",
        devotee_name: "Bhakta Ramesh Patel",
      }),
    ];
    const { getAllByLabelText } = await render(<SevaCarePanel />);

    // One cross across both lists: the concentration row's, and only that.
    expect(getAllByLabelText(/Clear .* from Seva Care/)).toHaveLength(1);
    expect(mockDismiss).not.toHaveBeenCalled();
  });
});

/**
 * The temple's oldest complaint about this screen, in its plainest form: Bhakta
 * Ramesh Patel and Madhava Priya Das were each drawn twice, once under the
 * burnout reading and once under the rota one, and the second row read as a
 * second devotee to go and see.
 */
describe("a devotee both readings have something to say about", () => {
  it("names them once, under the question that has an action on it", async () => {
    mockCarried = [
      concentration({
        devotee_id: "d-ramesh",
        devotee_name: "Bhakta Ramesh Patel",
      }),
    ];
    mockNarrow = [
      narrowness({
        devotee_id: "d-ramesh",
        devotee_name: "Bhakta Ramesh Patel",
      }),
      narrowness({ devotee_id: "d-gopal", devotee_name: "Gopal Das" }),
    ];
    const { getAllByText, queryByText } = await render(<SevaCarePanel />);

    expect(getAllByText("Bhakta Ramesh Patel")).toHaveLength(1);
    // The seva he is carrying, which is the row that can be cleared — not the
    // category the rota reading names him for.
    expect(queryByText("Pot washing")).toBeTruthy();
    // Everybody the burnout list did not name is still on the rota list.
    expect(queryByText("Gopal Das")).toBeTruthy();
  });

  it("keeps every other devotee on the second list", () => {
    const carried = concentrationEntries([
      concentration({ devotee_id: "d-ramesh" }),
    ]);
    const narrow = narrownessEntries([
      narrowness({ devotee_id: "d-ramesh" }),
      narrowness({ devotee_id: "d-gopal" }),
    ]);

    expect(withoutRepeats(narrow, carried).map((row) => row.devoteeId)).toEqual(
      ["d-gopal"],
    );
  });
});

/**
 * Syamasundara Das served six hours this month and none this week, and the row
 * led with "0 hours" — honest, and read by every President who saw it as a
 * verdict on him rather than as a quiet week.
 */
describe("the figure a row leads with", () => {
  beforeEach(() => {
    mockCarried = [
      concentration({
        devotee_id: "d-syama",
        devotee_name: "Syamasundara Das",
        hours_this_week: 0,
        hours_this_month: 6,
        hours_trailing_quarter: 21,
      }),
    ];
  });

  it("is the quarter, which is never nought for a devotee on the list", async () => {
    const { getByText, queryByText } = await render(<SevaCarePanel />);

    expect(getByText("21 hours")).toBeTruthy();
    // Never on its own, as the figure the row is read off.
    expect(queryByText("0 hours")).toBeNull();
  });

  it("still says what the week and the month actually were", async () => {
    const { getByText } = await render(<SevaCarePanel />);

    expect(
      getByText("Over the last 13 weeks · 0 hours this week · 6 hours this month"),
    ).toBeTruthy();
  });

  /** The temple named this button. */
  it("offers their seva history by that name", async () => {
    const { getByText, getByLabelText } = await render(<SevaCarePanel />);

    expect(getByText("Their seva history")).toBeTruthy();
    expect(
      getByLabelText("See Syamasundara Das's seva history"),
    ).toBeTruthy();
  });
});
