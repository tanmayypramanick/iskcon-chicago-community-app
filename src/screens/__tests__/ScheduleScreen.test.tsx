/// <reference types="jest" />

/**
 * The timetable as a coordinator and a devotee actually meet it.
 *
 * The fixtures are `list_seva_schedule` rows for the week of Monday 10 August
 * 2026, including the Thursday the temple keeps asking about — the one that was
 * handed over to a substitute.
 */

import { act, fireEvent, render } from "@testing-library/react-native";
import {
  SafeAreaProvider,
  type Metrics,
} from "react-native-safe-area-context";

import type { AccessRole } from "../../features/access/model";
import type { SevaScheduleOccurrence } from "../../features/schedule/types";
import { usePrototypeSession } from "../../store/usePrototypeSession";

let mockRole: AccessRole = "president";
let mockRows: SevaScheduleOccurrence[] = [];
let mockError: unknown = null;
let lastWindow: {
  from: string;
  to: string;
  devoteeId: string | null;
  enabled: boolean;
} | null = null;

jest.mock("../../lib/supabase", () => ({
  getSupabaseClient: () => ({
    channel: () => ({ on: jest.fn().mockReturnThis(), subscribe: jest.fn() }),
    removeChannel: jest.fn(),
  }),
}));

jest.mock("../../lib/connectivity", () => ({
  useServerReachable: () => true,
  reportReachability: jest.fn(),
}));

jest.mock("../../features/access/hooks", () => ({
  useCurrentAccessProfile: () => ({ data: { role: mockRole } }),
}));

jest.mock("../../features/schedule/hooks", () => ({
  useSevaSchedule: (
    from: string,
    to: string,
    devoteeId: string | null,
    enabled: boolean,
  ) => {
    lastWindow = { from, to, devoteeId, enabled };
    return {
      data: mockError ? undefined : mockRows,
      error: mockError,
      isLoading: false,
      refetch: jest.fn(),
    };
  },
  useTempleProgramme: () => ({
    data: [
      {
        programme_id: "prog-mangala",
        kind: "temple_programme",
        name: "Mangala Arati",
        occurs_on: "2026-08-13",
        day_of_week: 4,
        starts_at_local: "04:30:00",
        ends_at_local: null,
        duration_minutes: null,
        starts_at: "2026-08-13T09:30:00.000Z",
        ends_at: null,
        sort_order: 10,
      },
    ],
    error: null,
    isLoading: false,
  }),
  useTimetableHours: () => ({
    data: { day_starts_at: "03:30:00", day_ends_at: "21:00:00" },
  }),
  useScheduleRealtime: jest.fn(),
}));

import { ScheduleScreen } from "../ScheduleScreen";

const ME = "d-arpita";

function occurrence(
  overrides: Partial<SevaScheduleOccurrence> = {},
): SevaScheduleOccurrence {
  return {
    service_instance_id: "inst-veg",
    template_id: "tpl-veg",
    from_weekly_template: true,
    seva_name: "Vegetable Cutting",
    service_type_id: "type-veg",
    service_category: "kitchen",
    occurs_on: "2026-08-13",
    day_of_week: 4,
    starts_at_local: "16:15:00",
    ends_at_local: "17:45:00",
    ends_next_day: false,
    duration_minutes: 90,
    starts_at: "2026-08-13T21:15:00.000Z",
    ends_at: "2026-08-13T22:45:00.000Z",
    status: "full",
    nobody_served: false,
    participation_mode: "invite_only",
    posted_by: "d-tanmay",
    slots_needed: 1,
    filled_slots: 1,
    open_slots: 0,
    roster_visible: true,
    servers: [
      {
        devoteeId: ME,
        name: "Arpita Jadhav",
        assignmentId: "asg-1",
        assignmentStatus: "confirmed",
        attendance: null,
        pointsStatus: "pending",
        isSubstitute: false,
        coveringForDevoteeId: null,
        coveringForName: null,
      },
    ],
    ...overrides,
  };
}

const navigation = { navigate: jest.fn(), setOptions: jest.fn() };

const METRICS: Metrics = {
  frame: { x: 0, y: 0, width: 390, height: 844 },
  insets: { top: 47, left: 0, right: 0, bottom: 34 },
};

/** Wednesday 12 August 2026, 10:00 Chicago — mid-week, so paging has both sides. */
const NOW = new Date("2026-08-12T15:00:00.000Z");

async function renderSchedule(params?: {
  devoteeId?: string;
  name?: string;
}) {
  usePrototypeSession.setState({ activeUserId: ME });
  return render(
    // The bottom sheet measures the home indicator before it slides, so the
    // screen needs the same provider the app gives it.
    <SafeAreaProvider initialMetrics={METRICS}>
      <ScheduleScreen
        navigation={navigation as never}
        route={{ key: "schedule", name: "Schedule", params } as never}
      />
    </SafeAreaProvider>,
  );
}

describe("the community timetable", () => {
  beforeAll(() => {
    jest.useFakeTimers().setSystemTime(NOW);
  });
  afterAll(() => {
    jest.useRealTimers();
  });
  beforeEach(() => {
    jest.clearAllMocks();
    mockRole = "president";
    mockRows = [occurrence()];
    mockError = null;
    lastWindow = null;
  });

  it("asks for the whole temple's week, Monday to Sunday", async () => {
    await renderSchedule();
    expect(lastWindow).toEqual({
      from: "2026-08-10",
      to: "2026-08-16",
      // Null is the whole temple; the server gates it on the board permission.
      devoteeId: null,
      enabled: true,
    });
  });

  it("draws a block that says the seva and carries the rest in its label", async () => {
    const screen = await renderSchedule();
    expect(screen.getAllByText("Vegetable Cutting").length).toBeGreaterThan(0);
    expect(
      screen.getByLabelText(/Vegetable Cutting.*4:15 PM to 5:45 PM/),
    ).toBeTruthy();
  });

  it("opens the seva's own detail screen when a block is tapped", async () => {
    const screen = await renderSchedule();
    await fireEvent.press(
      screen.getByLabelText(/Vegetable Cutting.*4:15 PM to 5:45 PM/),
    );
    expect(navigation.navigate).toHaveBeenCalledWith("ServiceDetail", {
      serviceId: "inst-veg",
    });
  });

  it("names the substitute when a seva has been handed over", async () => {
    mockRows = [
      occurrence({
        servers: [
          {
            devoteeId: "d-krsna",
            name: "Krsna Kirtan Das",
            assignmentId: null,
            assignmentStatus: null,
            attendance: null,
            pointsStatus: "pending",
            isSubstitute: true,
            coveringForDevoteeId: ME,
            coveringForName: "Arpita Jadhav",
          },
        ],
      }),
    ];
    const screen = await renderSchedule();
    expect(
      screen.getByLabelText(/Krsna Kirtan Das \(covering for Arpita Jadhav\)/),
    ).toBeTruthy();
  });

  it("does not name co-servers on a seva whose roster is withheld", async () => {
    mockRows = [
      occurrence({
        roster_visible: false,
        slots_needed: 4,
        filled_slots: 4,
        servers: [],
      }),
    ];
    const screen = await renderSchedule();
    expect(screen.queryByLabelText(/Arpita Jadhav/)).toBeNull();
    expect(
      screen.getByLabelText(/the roster is not shown to you/),
    ).toBeTruthy();
  });

  it("pages a week at a time, forwards and back", async () => {
    const screen = await renderSchedule();
    expect(screen.getByText("Aug 10 – Aug 16")).toBeTruthy();

    await fireEvent.press(screen.getByLabelText("Next"));
    expect(screen.getByText("Aug 17 – Aug 23")).toBeTruthy();
    expect(lastWindow).toEqual({
      from: "2026-08-17",
      to: "2026-08-23",
      devoteeId: null,
      enabled: true,
    });

    await fireEvent.press(screen.getByLabelText("Previous"));
    await fireEvent.press(screen.getByLabelText("Previous"));
    expect(screen.getByText("Aug 3 – Aug 9")).toBeTruthy();
    expect(lastWindow?.from).toBe("2026-08-03");
  });

  it("comes back to this week from wherever it has been paged to", async () => {
    const screen = await renderSchedule();
    await fireEvent.press(screen.getByLabelText("Next"));
    await fireEvent.press(screen.getByLabelText("Back to this week"));
    expect(screen.getByText("Aug 10 – Aug 16")).toBeTruthy();
  });

  it("asks a month for its own days only, never the ragged grid", async () => {
    const screen = await renderSchedule();
    await fireEvent.press(screen.getByLabelText("Month view"));
    // 42 cells would be over the server's 35-day limit; 31 is not.
    expect(lastWindow).toEqual({
      from: "2026-08-01",
      to: "2026-08-31",
      devoteeId: null,
      enabled: true,
    });
  });
});

describe("posting a seva from an empty square", () => {
  beforeAll(() => {
    jest.useFakeTimers().setSystemTime(NOW);
  });
  afterAll(() => {
    jest.useRealTimers();
  });
  beforeEach(() => {
    jest.clearAllMocks();
    mockRole = "president";
    mockRows = [];
    mockError = null;
  });

  it("carries the day and the time of the square that was tapped", async () => {
    const screen = await renderSchedule();
    // The day view is where an empty square is a labelled, reachable button.
    await fireEvent.press(screen.getByLabelText(/^Thu, Aug 13/));

    await fireEvent.press(
      screen.getByLabelText("Post a seva on Thu, Aug 13 at 5:00 PM"),
      { nativeEvent: { locationY: 0 } },
    );
    expect(screen.getByText("Thu, Aug 13 at 5:00 PM")).toBeTruthy();

    // The sheet runs the action only once it has finished sliding away, so
    // that an Alert is never raised against a modal still on screen.
    await fireEvent.press(screen.getByText("Post a one-off seva"));
    await act(async () => {
      jest.advanceTimersByTime(400);
    });
    expect(navigation.navigate).toHaveBeenCalledWith("CreateService", {
      date: "2026-08-13",
      startTime: "17:00:00",
    });
  });

  it("offers the same square as a weekly seva, on that weekday", async () => {
    const screen = await renderSchedule();
    await fireEvent.press(screen.getByLabelText(/^Thu, Aug 13/));
    await fireEvent.press(
      screen.getByLabelText("Post a seva on Thu, Aug 13 at 5:00 PM"),
      { nativeEvent: { locationY: 0 } },
    );

    await fireEvent.press(screen.getByText("Create a weekly seva at this time"));
    await act(async () => {
      jest.advanceTimersByTime(400);
    });
    expect(navigation.navigate).toHaveBeenCalledWith("CreateRecurringService", {
      startDate: "2026-08-13",
      startTime: "17:00:00",
      // 4 is Thursday, Postgres dow.
      dayOfWeek: 4,
    });
  });

  it("offers nothing to a devotee who may not post", async () => {
    mockRole = "devotee";
    const screen = await renderSchedule({ devoteeId: ME });
    await fireEvent.press(screen.getByLabelText(/^Thu, Aug 13/));
    expect(
      screen.queryByLabelText("Post a seva on Thu, Aug 13 at 5:00 PM"),
    ).toBeNull();
  });
});

describe("a timetable that is not yours to read", () => {
  beforeAll(() => {
    jest.useFakeTimers().setSystemTime(NOW);
  });
  afterAll(() => {
    jest.useRealTimers();
  });
  beforeEach(() => {
    jest.clearAllMocks();
    mockRows = [];
    mockError = null;
    lastWindow = null;
  });

  it("never asks for the whole temple on behalf of a devotee", async () => {
    mockRole = "devotee";
    const screen = await renderSchedule();
    // Not a request that fails — a request that is never made, because the
    // answer is already known and the server would only raise.
    expect(lastWindow?.enabled).toBe(false);
    expect(screen.getByText("This timetable is not yours to read")).toBeTruthy();
  });

  it("shows a devotee their own week without asking anybody", async () => {
    mockRole = "devotee";
    mockRows = [occurrence()];
    const screen = await renderSchedule({ devoteeId: ME });
    expect(lastWindow?.devoteeId).toBe(ME);
    expect(screen.getAllByText("Vegetable Cutting").length).toBeGreaterThan(0);
  });

  it("says a refusal is a refusal and not an empty week", async () => {
    mockRole = "president";
    mockError = {
      code: "P0001",
      message: "You may only read your own seva timetable.",
    };
    const screen = await renderSchedule({ devoteeId: "d-somebody", name: "Gopi" });
    expect(
      screen.getByText("The temple did not open this timetable to you"),
    ).toBeTruthy();
    expect(screen.queryByText(/No seva is on the board/)).toBeNull();
  });

  it("says an empty week is empty", async () => {
    mockRole = "president";
    mockRows = [];
    const screen = await renderSchedule();
    expect(screen.getByText("No seva is on the board for this week.")).toBeTruthy();
  });

  it("lets a coordinator read one devotee's week to see when they are free", async () => {
    mockRole = "core";
    mockRows = [occurrence()];
    const screen = await renderSchedule({ devoteeId: "d-gopi", name: "Gopi Dasi" });
    expect(lastWindow?.devoteeId).toBe("d-gopi");
    expect(navigation.setOptions).toHaveBeenCalledWith({
      title: "Gopi Dasi’s timetable",
    });
    expect(screen.getAllByText("Vegetable Cutting").length).toBeGreaterThan(0);
  });
});
