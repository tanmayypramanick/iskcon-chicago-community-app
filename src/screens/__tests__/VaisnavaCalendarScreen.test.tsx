/// <reference types="jest" />

import { render, fireEvent } from "@testing-library/react-native";

import type {
  VaisnavaCalendarEvent,
  VaisnavaCalendarPublication,
  VaisnavaEventKind,
} from "../../features/vaisnavaCalendar/types";
import { usePrototypeSession } from "../../store/usePrototypeSession";
import { VaisnavaCalendarScreen } from "../VaisnavaCalendarScreen";

/**
 * Every date on this screen is Chicago's, so the tests pin Chicago's today
 * rather than the machine's. 14 January 2026 is an Ekadasi with a fast, and
 * its parana falls on the 15th — the pairing the screen exists to show.
 */
const TODAY = "2026-01-14";

/** Most tests stand on TODAY; a few move the clock to reach a real case. */
let mockToday = TODAY;

jest.mock("@react-navigation/native", () => ({
  useIsFocused: () => false,
}));

jest.mock("../../lib/chicagoDate", () => ({
  ...jest.requireActual("../../lib/chicagoDate"),
  getChicagoDateKey: () => mockToday,
}));

let mockRole = "devotee";

jest.mock("../../features/access/hooks", () => ({
  useCurrentAccessProfile: () => ({
    data: { role: mockRole },
    error: null,
    isLoading: false,
    isFetching: false,
    dataUpdatedAt: Date.now(),
    refetch: jest.fn(),
  }),
}));

let mockPublications: VaisnavaCalendarPublication[] = [];
let mockEventsByYear: Record<number, VaisnavaCalendarEvent[]> = {};
let mockRequestedYears: number[] = [];

jest.mock("../../features/vaisnavaCalendar/hooks", () => ({
  useVaisnavaCalendarPublications: () => ({
    data: mockPublications,
    error: null,
    isLoading: false,
    isFetching: false,
    dataUpdatedAt: Date.now(),
    refetch: jest.fn(),
  }),
  useVaisnavaCalendarEvents: (year: number) => {
    mockRequestedYears.push(year);
    return {
      data: mockEventsByYear[year] ?? [],
      error: null,
      isLoading: false,
      isFetching: false,
      dataUpdatedAt: Date.now(),
      refetch: jest.fn(),
    };
  },
  useVaisnavaCalendarRealtime: () => undefined,
  usePublishVaisnavaCalendar: () => ({
    mutate: jest.fn(),
    error: null,
    isPending: false,
  }),
}));

let nextId = 0;

function event(
  event_date: string,
  title: string,
  event_kind: VaisnavaEventKind,
  sort_order: number,
  extra: Partial<VaisnavaCalendarEvent> = {},
): VaisnavaCalendarEvent {
  nextId += 1;
  return {
    id: `event-${nextId}`,
    calendar_year: Number(event_date.slice(0, 4)),
    event_date,
    title,
    description: null,
    event_kind,
    source_uid: `uid-${nextId}`,
    sort_order,
    created_at: "2026-01-01T00:00:00.000Z",
    ...extra,
  };
}

function publication(calendar_year: number): VaisnavaCalendarPublication {
  return {
    calendar_year,
    city: "Chicago, Illinois",
    time_zone: "America/Chicago",
    source_name: "VaisnavaCalendar.Info — GCal 11",
    source_url: null,
    file_name: `chicago-${calendar_year}.ics`,
    event_count: 231,
    published_at: "2026-08-26T00:00:00.000Z",
    published_by: null,
  };
}

/** The real January 2026 entries around the Sat-tila Ekadasi. */
const january2026 = [
  event("2026-01-14", "Ganga Sagara Mela", "observance", 8),
  event("2026-01-14", "Vyanjuli Mahadvadasi", "ekadasi", 6),
  event("2026-01-14", "Fasting for Sat-tila Ekadasi", "fasting", 7),
  event(
    "2026-01-15",
    "Break fast 07:15 (sunrise) - 08:48 (end of tithi) LT",
    "parana",
    9,
  ),
  event("2026-01-23", "Vasanta Pancami", "observance", 10),
  event("2026-01-23", "Srimati Visnupriya Devi -- Appearance", "appearance", 11),
  event(
    "2026-01-23",
    "Srila Visvanatha Cakravarti Thakura -- Disappearance",
    "disappearance",
    12,
  ),
  event("2026-01-23", "Sarasvati Puja", "observance", 16),
];

const march2026 = [event("2026-03-03", "Gaura Purnima", "festival", 40)];

async function renderCalendar() {
  usePrototypeSession.setState({ activeUserId: "calendar-test-user" });
  return render(<VaisnavaCalendarScreen />);
}

/** The grid cell and the day panel say the same thing; the grid comes first. */
type Rendered = Awaited<ReturnType<typeof render>>;

function cell(screen: Rendered, label: RegExp) {
  return screen.getAllByLabelText(label)[0];
}

beforeEach(() => {
  mockToday = TODAY;
  mockRole = "devotee";
  mockRequestedYears = [];
  mockPublications = [publication(2026)];
  mockEventsByYear = { 2026: [...january2026, ...march2026] };
});

describe("the month grid", () => {
  it("opens on the month holding today, with today under the selection", async () => {
    const screen = await renderCalendar();

    expect(screen.getByText("January 2026")).toBeTruthy();
    expect(screen.getByText("8 observances")).toBeTruthy();
    // The day panel below the grid opens on today without anything scrolled.
    // The date is the panel's heading and "Today" the eyebrow marking it.
    expect(screen.getByText("Today")).toBeTruthy();
    expect(screen.getByText("Wednesday, January 14")).toBeTruthy();
  });

  it("shows the neighbouring month's days, marked as not this month", async () => {
    const screen = await renderCalendar();

    // January 2026 opens on a Thursday, so the first week of February trails
    // it and stays reachable — the grid never reflows to hide it.
    const february = cell(screen, /^Sunday, February 1\./);
    expect(february.props.accessibilityState).toMatchObject({ selected: false });

    await fireEvent.press(february);
    expect(screen.getByText("February 2026")).toBeTruthy();
    expect(screen.getByText("Sunday, February 1")).toBeTruthy();
  });

  it("does not offer a day belonging to a year that was never published", async () => {
    const screen = await renderCalendar();

    // The grid leads with 28–31 December 2025 to stay rectangular, but no
    // calendar exists for them, so they are not days a devotee can open.
    expect(screen.queryByLabelText(/^Sunday, December 28\./)).toBeNull();
    // Drawn, so the grid stays rectangular; hidden from the reader and from
    // touch, because 2025 was never published. 28 December and 28 January.
    expect(
      screen.getAllByText("28", { includeHiddenElements: true }),
    ).toHaveLength(2);
  });

  it("marks today and the selection independently", async () => {
    const screen = await renderCalendar();

    const today = cell(screen, /^Wednesday, January 14\./);
    expect(today.props.accessibilityLabel).toContain("Today.");
    expect(today.props.accessibilityState).toMatchObject({ selected: true });

    await fireEvent.press(cell(screen, /^Friday, January 23\./));

    // The selection has moved; today has not, and both are still on the grid.
    const movedToday = cell(screen, /^Wednesday, January 14\./);
    expect(movedToday.props.accessibilityLabel).toContain("Today.");
    expect(movedToday.props.accessibilityState).toMatchObject({
      selected: false,
    });
    expect(
      cell(screen, /^Friday, January 23\./).props.accessibilityState,
    ).toMatchObject({ selected: true });
  });

  it("moves the day below the grid when a day is tapped", async () => {
    const screen = await renderCalendar();

    expect(screen.queryByText("Vasanta Pancami")).toBeNull();

    await fireEvent.press(cell(screen, /^Friday, January 23\./));

    // All four titles of a crowded day, in full, none of them in a cell.
    expect(screen.getByText("Friday, January 23")).toBeTruthy();
    expect(screen.getByText("Vasanta Pancami")).toBeTruthy();
    expect(screen.getByText("Sarasvati Puja")).toBeTruthy();
    expect(screen.getByText(/^Srimati Visnupriya Devi/)).toBeTruthy();
    expect(screen.getByText(/^Srila Visvanatha Cakravarti Thakura/)).toBeTruthy();
    expect(screen.queryByText("Fasting for Sat-tila Ekadasi")).toBeNull();
  });

  it("names a day and everything on it on the cell itself", async () => {
    const screen = await renderCalendar();

    // A grid is silence to a screen reader unless each cell says its own date
    // and what is on it; "23" on its own is nothing.
    expect(
      cell(screen, /^Friday, January 23\./).props.accessibilityLabel,
    ).toBe(
      "Friday, January 23. Vasanta Pancami. Sarasvati Puja. " +
        "Srimati Visnupriya Devi, appearance. " +
        "Srila Visvanatha Cakravarti Thakura, disappearance.",
    );
    expect(
      cell(screen, /^Wednesday, January 14\./).props.accessibilityLabel,
    ).toBe(
      "Wednesday, January 14. Today. Fasting day. Vyanjuli Mahadvadasi. " +
        "Fasting for Sat-tila Ekadasi. Ganga Sagara Mela.",
    );
  });

  it("keeps a long title whole rather than truncating it", async () => {
    const screen = await renderCalendar();
    await fireEvent.press(cell(screen, /^Friday, January 23\./));

    const title = screen.getByText(/^Srila Visvanatha Cakravarti Thakura/);
    expect(title.props.numberOfLines).toBeUndefined();
  });
});

describe("paging between months", () => {
  it("pages with the arrows without asking for the year again", async () => {
    const screen = await renderCalendar();
    expect(new Set(mockRequestedYears)).toStrictEqual(new Set([2026]));

    await fireEvent.press(screen.getByLabelText("Next month"));
    expect(screen.getByText("February 2026")).toBeTruthy();

    await fireEvent.press(screen.getByLabelText("Next month"));
    expect(screen.getByText("March 2026")).toBeTruthy();

    await fireEvent.press(screen.getByLabelText("Previous month"));
    expect(screen.getByText("February 2026")).toBeTruthy();

    // The whole year is already in hand, so paging is a state change and
    // nothing else — no month ever waits on the network to be drawn.
    expect(new Set(mockRequestedYears)).toStrictEqual(new Set([2026]));
  });

  it("gives the grid a horizontal drag of its own", async () => {
    const screen = await renderCalendar();

    // The gesture itself is decided by readSwipe, which has its own tests; a
    // PanResponder's gestureState cannot be faked without a real touch
    // history, so what is checked here is that the grid is wired to it at all.
    const grid = screen.getByLabelText("January 2026, by week");
    expect(typeof grid.props.onMoveShouldSetResponder).toBe("function");
    expect(typeof grid.props.onResponderRelease).toBe("function");
    // And never on start, or a tap would never reach the day underneath.
    expect(grid.props.onStartShouldSetResponder?.()).toBeFalsy();
  });

  it("opens a month on the first day that has something in it", async () => {
    const screen = await renderCalendar();

    await fireEvent.press(screen.getByLabelText("Next month"));
    await fireEvent.press(screen.getByLabelText("Next month"));

    // Most of this calendar is empty; landing on the 1st would show "nothing"
    // for a month that in fact holds Gaura Purnima.
    expect(screen.getByText("Tuesday, March 3")).toBeTruthy();
    expect(screen.getByText("Gaura Purnima")).toBeTruthy();
  });

  it("says so rather than lying when a month really is empty", async () => {
    const screen = await renderCalendar();

    await fireEvent.press(screen.getByLabelText("Next month"));

    expect(screen.getByText("Nothing observed")).toBeTruthy();
    expect(screen.getByText("Nothing is observed on this day.")).toBeTruthy();
    // And the useful answer on an empty day is the next day that is not.
    expect(screen.getByText(/^Next · Tuesday, March 3 · in 30 days$/)).toBeTruthy();

    await fireEvent.press(screen.getByLabelText(/^Next, Tuesday, March 3, in 30 days\./));
    expect(screen.getByText("March 2026")).toBeTruthy();
    expect(screen.getByText("Tuesday, March 3")).toBeTruthy();
  });

  it("will not page out of the published year", async () => {
    const screen = await renderCalendar();

    expect(
      screen.getByLabelText("Previous month").props.accessibilityState,
    ).toMatchObject({ disabled: true });
    expect(
      screen.getByLabelText("Next month").props.accessibilityState,
    ).toMatchObject({ disabled: false });
  });
});

describe("finding the way back to today", () => {
  it("offers no Today button while today is already the day on show", async () => {
    const screen = await renderCalendar();
    expect(screen.queryByLabelText("Go to today")).toBeNull();
  });

  it("offers it once you are somewhere else, and returns", async () => {
    const screen = await renderCalendar();

    await fireEvent.press(screen.getByLabelText("Next month"));
    expect(screen.getByText("February 2026")).toBeTruthy();

    await fireEvent.press(screen.getByLabelText("Go to today"));

    expect(screen.getByText("January 2026")).toBeTruthy();
    expect(screen.getByText("Wednesday, January 14")).toBeTruthy();
    expect(screen.queryByLabelText("Go to today")).toBeNull();
    // The button is gone, so the only "Today" left is the day panel's eyebrow.
    expect(screen.getByText("Today")).toBeTruthy();
  });
});

describe("the day below the grid", () => {
  it("answers today, its fast, and when the fast ends, before anything is scrolled", async () => {
    const screen = await renderCalendar();

    const spoken = screen.getByLabelText(/^Today, Wednesday, January 14\./);
    expect(spoken.props.accessibilityLabel).toBe(
      "Today, Wednesday, January 14. A fasting day. Vyanjuli Mahadvadasi. " +
        "Fasting for Sat-tila Ekadasi. Ganga Sagara Mela. " +
        "Break fast tomorrow, 7:15 – 8:48 AM CST.",
    );
    // A screen reader is told when the day changes under it.
    expect(spoken.props.accessibilityLiveRegion).toBe("polite");
  });

  it("shows a fasting devotee tomorrow's window today", async () => {
    const screen = await renderCalendar();

    // The file publishes the fast and its window a day apart as two unrelated
    // rows; a devotee deciding when to eat needs them on the same day.
    expect(screen.getByText("Break fast tomorrow")).toBeTruthy();
    expect(screen.getByText("7:15 – 8:48 AM CST")).toBeTruthy();
    expect(screen.getByText("Fasting")).toBeTruthy();
  });

  it("sets a bounded parana window as a time, not as a sentence", async () => {
    const screen = await renderCalendar();
    await fireEvent.press(cell(screen, /^Thursday, January 15\./));

    expect(screen.getByText("Break fast")).toBeTruthy();
    expect(screen.getByText("7:15 – 8:48 AM CST")).toBeTruthy();
    expect(screen.getByText("from sunrise until end of tithi")).toBeTruthy();
    // The raw title is never shown once it has been read.
    expect(
      screen.queryByText("Break fast 07:15 (sunrise) - 08:48 (end of tithi) LT"),
    ).toBeNull();
  });

  it("renders an open-ended parana without inventing an end", async () => {
    mockEventsByYear = {
      2026: [
        event("2026-01-14", "Fasting for Sat-tila Ekadasi", "fasting", 7),
        event("2026-01-15", "Break fast after 11:12 (end of tithi) LT", "parana", 9),
      ],
    };
    const screen = await renderCalendar();

    expect(screen.getByText("After 11:12 AM CST")).toBeTruthy();
    expect(screen.getByText("from end of tithi")).toBeTruthy();
  });

  it("names the zone in force on the date rather than the file's marker", async () => {
    // The source writes "LT" on this June row; June in Chicago is CDT, and the
    // date is the only thing that actually knows which.
    mockEventsByYear = {
      2026: [event("2026-06-02", "Break fast 05:52 - 10:34 LT", "parana", 9)],
    };
    const screen = await renderCalendar();

    await fireEvent.press(screen.getByLabelText("Next month"));
    await fireEvent.press(screen.getByLabelText("Next month"));
    await fireEvent.press(screen.getByLabelText("Next month"));
    await fireEvent.press(screen.getByLabelText("Next month"));
    await fireEvent.press(screen.getByLabelText("Next month"));

    expect(screen.getByText("5:52 – 10:34 AM CDT")).toBeTruthy();
  });

  it("prefers migration 0076's columns over the title when they arrive", async () => {
    mockEventsByYear = {
      2026: [
        event(
          "2026-01-15",
          "Break fast 07:15 (sunrise) - 08:48 (end of tithi) LT",
          "parana",
          9,
          {
            parana_start_time: "07:20:00",
            parana_end_time: "08:50:00",
            parana_start_reason: "sunrise",
            parana_end_reason: "end of tithi",
          },
        ),
      ],
    };
    const screen = await renderCalendar();
    await fireEvent.press(cell(screen, /^Thursday, January 15\./));

    expect(screen.getByText("7:20 – 8:50 AM CST")).toBeTruthy();
  });

  it("falls back to the published title when a parana cannot be read", async () => {
    mockEventsByYear = {
      2026: [event("2026-01-15", "Break fast after morning arati", "parana", 9)],
    };
    const screen = await renderCalendar();
    await fireEvent.press(cell(screen, /^Thursday, January 15\./));

    expect(screen.getByText("Break fast after morning arati")).toBeTruthy();
    // And never dressed up as a window it could not be read into.
    expect(screen.queryByText("Break fast")).toBeNull();
  });

  it("puts what a devotee must act on above what they must only know", async () => {
    const screen = await renderCalendar();

    const spoken = screen.getByLabelText(/^Today, Wednesday, January 14\./)
      .props.accessibilityLabel as string;
    expect(spoken.indexOf("Vyanjuli Mahadvadasi")).toBeLessThan(
      spoken.indexOf("Ganga Sagara Mela"),
    );
  });

  it("sinks a parenthesised note below the observance it qualifies", async () => {
    mockEventsByYear = {
      2026: [
        event("2026-01-25", "(Fast till noon)", "observance", 18),
        event("2026-01-25", "Sri Advaita Acarya -- Appearance", "appearance", 17),
      ],
    };
    const screen = await renderCalendar();

    const spoken = cell(screen, /^Sunday, January 25\./).props
      .accessibilityLabel as string;
    // Spoken without its brackets — they are the file's punctuation, and a
    // screen reader announcing them adds nothing the sentence does not say.
    expect(spoken).toBe(
      "Sunday, January 25. Sri Advaita Acarya, appearance. Fast till noon.",
    );
  });

  it("drops the source's bracketed editorial note", async () => {
    mockEventsByYear = {
      2026: [
        event(
          "2026-01-20",
          "Last day of the first Caturmasya month [PURNIMA SYSTEM]",
          "observance",
          3,
        ),
      ],
    };
    const screen = await renderCalendar();
    await fireEvent.press(cell(screen, /^Tuesday, January 20\./));

    expect(
      screen.getByText("Last day of the first Caturmasya month"),
    ).toBeTruthy();
  });
});

describe("more than one published year", () => {
  it("shows no year switcher when only one year is published", async () => {
    const screen = await renderCalendar();

    expect(screen.queryByLabelText("Show the 2026 calendar")).toBeNull();
    expect(screen.queryByLabelText("Show the 2027 calendar")).toBeNull();
    // The year is still named, by the month heading.
    expect(screen.getByText("January 2026")).toBeTruthy();
  });

  it("switches between two published years", async () => {
    mockPublications = [publication(2027), publication(2026)];
    mockEventsByYear = {
      2026: [...january2026, ...march2026],
      2027: [event("2027-02-08", "Sri Nityananda Trayodasi", "festival", 1)],
    };
    const screen = await renderCalendar();

    expect(screen.getByText("January 2026")).toBeTruthy();
    expect(screen.getByLabelText("Show the 2026 calendar")).toBeTruthy();

    await fireEvent.press(screen.getByLabelText("Show the 2027 calendar"));

    expect(mockRequestedYears).toContain(2027);
    expect(screen.getByText("February 2027")).toBeTruthy();
    expect(screen.getByText("Sri Nityananda Trayodasi")).toBeTruthy();
  });

  it("opens on the current year even when a later year is published first", async () => {
    // The device hit this: publications come back newest-first, so a screen
    // that trusted their order landed a devotee on next January.
    mockToday = "2026-08-27";
    mockPublications = [publication(2027), publication(2026)];
    mockEventsByYear = {
      2026: [event("2026-08-23", "Radha Govinda Jhulana Yatra begins", "observance", 1)],
      2027: [event("2027-01-02", "Fasting for Saphala Ekadasi", "fasting", 1)],
    };
    const screen = await renderCalendar();

    expect(screen.getByText("August 2026")).toBeTruthy();
    expect(screen.queryByText("January 2027")).toBeNull();
  });

  it("claims no today on a year that does not hold one", async () => {
    mockPublications = [publication(2027)];
    mockEventsByYear = {
      2027: [event("2027-02-08", "Sri Nityananda Trayodasi", "festival", 1)],
    };
    const screen = await renderCalendar();

    expect(screen.getByText("February 2027")).toBeTruthy();
    // No eyebrow on the day panel, and no button offering a way back to one.
    expect(screen.queryByText("Today")).toBeNull();
    expect(screen.queryByLabelText(/ Today\. /)).toBeNull();
    // Nor a way back to a today that is not in the published calendar.
    expect(screen.queryByLabelText("Go to today")).toBeNull();
  });
});

describe("before a calendar exists", () => {
  it("explains the emptiness rather than showing a blank grid", async () => {
    mockPublications = [];
    mockEventsByYear = {};
    const screen = await renderCalendar();

    expect(screen.getByText("No calendar has been published yet")).toBeTruthy();
    expect(screen.queryByLabelText(/^Wednesday, January 14\./)).toBeNull();
  });

  it("says so on the day when a published year turns out to hold nothing", async () => {
    mockEventsByYear = { 2026: [] };
    const screen = await renderCalendar();

    expect(screen.getByText("Nothing is listed for 2026 yet.")).toBeTruthy();
  });

  it("keeps the upload path off a devotee's screen entirely", async () => {
    const screen = await renderCalendar();
    expect(
      screen.queryByLabelText("Publish or replace a calendar year"),
    ).toBeNull();
  });

  it("offers a leader the upload, collapsed until it is asked for", async () => {
    mockRole = "president";
    const screen = await renderCalendar();

    const disclosure = screen.getByLabelText(
      "Publish or replace a calendar year",
    );
    expect(disclosure.props.accessibilityState).toMatchObject({
      expanded: false,
    });
    expect(screen.queryByText("Choose yearly ICS file")).toBeNull();

    await fireEvent.press(disclosure);

    // The picker only; the source fields belong to a file already chosen.
    expect(screen.getByText("Choose yearly ICS file")).toBeTruthy();
    expect(screen.queryByLabelText("Calendar source name")).toBeNull();
  });
});
