/// <reference types="jest" />

import { groupCalendarDays } from "../agenda";
import {
  addMonths,
  buildMonthGrid,
  dayDotCount,
  describeGridDay,
  monthGridWeeks,
  monthStartKey,
  readSwipe,
  weekdayColumns,
  WEEK_START,
} from "../monthGrid";
import type { VaisnavaCalendarEvent, VaisnavaEventKind } from "../types";

let nextId = 0;

function event(
  event_date: string,
  title: string,
  event_kind: VaisnavaEventKind,
  sort_order = 1,
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
  };
}

describe("the shape of a month", () => {
  // Every weekday a month can begin on is represented in 2026: Thursday
  // (January), Sunday (February), Wednesday (April), Friday (May), Monday
  // (June), Saturday (August), Tuesday (September).
  it.each([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11])(
    "is six rows of seven in month %i, whatever weekday it opens on",
    (month) => {
      const weeks = monthGridWeeks(2026, month);
      expect(weeks).toHaveLength(6);
      for (const week of weeks) expect(week).toHaveLength(7);
    },
  );

  it("stays six rows for a February that would fit in four", () => {
    // 1 February 2026 is itself a Sunday and the month has 28 days, so the
    // month proper is exactly four rows. Two rows of March follow rather than
    // the grid — and everything under it — jumping when you page here.
    const weeks = monthGridWeeks(2026, 1);
    expect(weeks).toHaveLength(6);
    expect(weeks[0][0].date).toBe("2026-02-01");
    expect(weeks[3][6].date).toBe("2026-02-28");
    expect(weeks[4][0]).toMatchObject({ date: "2026-03-01", inMonth: false });
    expect(weeks[5][6]).toMatchObject({ date: "2026-03-14", inMonth: false });
  });

  it("stays six rows for the longest month that needs them all", () => {
    // 1 August 2026 is a Saturday and August has 31 days: six leading cells
    // plus 31 is 37, the most a month can ever ask for.
    const weeks = monthGridWeeks(2026, 7);
    expect(weeks).toHaveLength(6);
    expect(weeks[0][6]).toMatchObject({ date: "2026-08-01", inMonth: true });
    expect(weeks[5][1]).toMatchObject({ date: "2026-08-31", inMonth: true });
    expect(weeks[5][6]).toMatchObject({ date: "2026-09-05", inMonth: false });
  });

  it("starts every row on the chosen week start rather than the device's", () => {
    expect(WEEK_START).toBe(0);
    for (const week of monthGridWeeks(2026, 4)) {
      expect(new Date(`${week[0].date}T12:00:00.000Z`).getUTCDay()).toBe(0);
    }
  });

  it("gives the leading and trailing days the month they really belong to", () => {
    // January 2026 opens on a Thursday, so the grid leads with the last four
    // days of December 2025 and trails into the first week of February.
    const cells = buildMonthGrid(2026, 0);
    expect(cells[0]).toStrictEqual({
      date: "2025-12-28",
      day: 28,
      month: 11,
      year: 2025,
      inMonth: false,
    });
    expect(cells[3]).toMatchObject({ date: "2025-12-31", inMonth: false });
    expect(cells[4]).toMatchObject({ date: "2026-01-01", month: 0, inMonth: true });
    expect(cells[34]).toMatchObject({ date: "2026-01-31", inMonth: true });
    expect(cells[35]).toMatchObject({
      date: "2026-02-01",
      month: 1,
      year: 2026,
      inMonth: false,
    });
  });

  it("holds every day of the month exactly once", () => {
    const inMonth = buildMonthGrid(2026, 0).filter((cell) => cell.inMonth);
    expect(inMonth).toHaveLength(31);
    expect(new Set(inMonth.map((cell) => cell.date)).size).toBe(31);
    expect(inMonth[0].date).toBe("2026-01-01");
    expect(inMonth[30].date).toBe("2026-01-31");
  });

  it("crosses a year boundary in both directions", () => {
    expect(buildMonthGrid(2026, 11).at(-1)?.date).toBe("2027-01-09");
    expect(addMonths(2026, 11, 1)).toStrictEqual({ year: 2027, month: 0 });
    expect(addMonths(2026, 0, -1)).toStrictEqual({ year: 2025, month: 11 });
    expect(addMonths(2026, 0, 1)).toStrictEqual({ year: 2026, month: 1 });
  });

  it("names the first of a month without a timezone shifting it", () => {
    expect(monthStartKey(2026, 2)).toBe("2026-03-01");
    expect(monthStartKey(2027, 0)).toBe("2027-01-01");
  });
});

describe("the column headings", () => {
  it("reads Sunday first, from a fixed locale rather than the device's", () => {
    expect(weekdayColumns().map((column) => column.initial)).toStrictEqual([
      "S",
      "M",
      "T",
      "W",
      "T",
      "F",
      "S",
    ]);
  });

  it("keeps the full weekday behind each initial", () => {
    const columns = weekdayColumns();
    expect(columns[0].name).toBe("Sunday");
    expect(columns[6].name).toBe("Saturday");
  });
});

describe("dots under the number", () => {
  it("shows nothing for an empty day", () => {
    expect(dayDotCount(0)).toBe(0);
  });

  it("counts a day exactly while it is still countable", () => {
    expect(dayDotCount(1)).toBe(1);
    expect(dayDotCount(2)).toBe(2);
    expect(dayDotCount(3)).toBe(3);
  });

  it("caps rather than crowding the cell", () => {
    // 23 January 2026 really carries six; a sixth dot says nothing a third
    // does not, and would not fit beside a 36-point circle either way.
    expect(dayDotCount(6)).toBe(3);
    expect(dayDotCount(60)).toBe(3);
  });
});

describe("reading a swipe across the grid", () => {
  it("pages forward when the month is dragged leftwards", () => {
    expect(readSwipe(-120, 4)).toBe(1);
    expect(readSwipe(120, -4)).toBe(-1);
  });

  it("ignores a drag too short to be meant", () => {
    expect(readSwipe(-30, 0)).toBe(0);
    expect(readSwipe(0, 0)).toBe(0);
  });

  it("ignores a scroll that happens to drift sideways", () => {
    // The grid sits inside the screen's vertical ScrollView; a mostly-vertical
    // gesture must not change the month under a devotee who was scrolling.
    expect(readSwipe(-60, 200)).toBe(0);
    expect(readSwipe(-60, 30)).toBe(1);
  });
});

describe("what a day cell says out loud", () => {
  const [fastDay] = groupCalendarDays([
    event("2026-01-14", "Vyanjuli Mahadvadasi", "ekadasi", 6),
    event("2026-01-14", "Fasting for Sat-tila Ekadasi", "fasting", 7),
  ]);
  const [paranaDay] = groupCalendarDays([
    event(
      "2026-01-15",
      "Break fast 07:15 (sunrise) - 08:48 (end of tithi) LT",
      "parana",
      9,
    ),
  ]);
  const cell = (date: string) =>
    buildMonthGrid(2026, 0).find((entry) => entry.date === date)!;

  it("names the date in full, because a bare number is nothing to a reader", () => {
    expect(describeGridDay(cell("2026-01-14"), fastDay, { isToday: true })).toBe(
      "Wednesday, January 14. Today. Fasting day. " +
        "Vyanjuli Mahadvadasi. Fasting for Sat-tila Ekadasi.",
    );
  });

  it("says nothing about today when it is not today", () => {
    const spoken = describeGridDay(cell("2026-01-14"), fastDay, {
      isToday: false,
    });
    expect(spoken).not.toContain("Today");
    expect(spoken).toContain("Fasting day.");
  });

  it("speaks the break-fast window rather than the dots that stand for it", () => {
    expect(describeGridDay(cell("2026-01-15"), paranaDay, { isToday: false })).toBe(
      "Thursday, January 15. Break fast between 7:15 AM and 8:48 AM CST, " +
        "from sunrise until end of tithi.",
    );
  });

  it("says an empty day is empty rather than leaving silence", () => {
    expect(describeGridDay(cell("2026-01-20"), null, { isToday: false })).toBe(
      "Tuesday, January 20. Nothing observed.",
    );
  });

  it("still names a day belonging to the neighbouring month", () => {
    expect(describeGridDay(cell("2026-02-01"), null, { isToday: false })).toBe(
      "Sunday, February 1. Nothing observed.",
    );
  });
});
