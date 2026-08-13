/// <reference types="jest" />

/**
 * The timetable's arithmetic.
 *
 * A block in the wrong place is the one failure nothing else catches: it looks
 * like a timetable either way, and the temple would only find out when somebody
 * turned up an hour late. So every number the grid draws with is asserted here
 * rather than inferred from a render.
 */

import {
  MAX_WINDOW_DAYS,
  addDaysKey,
  blockGeometry,
  daysBetween,
  formatClock,
  gridBounds,
  gridHeight,
  hourLines,
  layOutDay,
  minutesFromTime,
  monthBounds,
  monthGridCells,
  shiftMonth,
  slotMinutesFromOffset,
  slotSegments,
  timeFromMinutes,
  weekDayKeys,
  weekStartKey,
  weekdayOfKey,
} from "../layout";

/** The temple's own dials, seeded by migration 0069. */
const TEMPLE_HOURS = { day_starts_at: "03:30:00", day_ends_at: "21:00:00" };

describe("clock values", () => {
  it("reads a time column and writes one back", () => {
    expect(minutesFromTime("04:15:00")).toBe(255);
    expect(minutesFromTime("03:30")).toBe(210);
    expect(minutesFromTime("00:00:00")).toBe(0);
    expect(timeFromMinutes(255)).toBe("04:15:00");
    expect(timeFromMinutes(1260)).toBe("21:00:00");
  });

  it("says the hour the way the temple would", () => {
    expect(formatClock(270)).toBe("4:30 AM");
    expect(formatClock(750)).toBe("12:30 PM");
    expect(formatClock(0)).toBe("12:00 AM");
    expect(formatClock(1080)).toBe("6:00 PM");
  });
});

describe("the grid's own hours", () => {
  it("draws 3:30 to 9:00 when nothing falls outside them", () => {
    const bounds = gridBounds(TEMPLE_HOURS, [
      { starts_at_local: "04:30:00", duration_minutes: 60 },
      { starts_at_local: "18:00:00", duration_minutes: 90 },
    ]);
    expect(bounds).toEqual({ startMinutes: 210, endMinutes: 1260 });
  });

  it("grows to hold a 2am seva rather than hiding it", () => {
    // The migration is explicit that the dials are advisory and that
    // list_seva_schedule still returns a seva outside them. A grid that clipped
    // it would be the app deciding the temple's data is wrong.
    const bounds = gridBounds(TEMPLE_HOURS, [
      { starts_at_local: "02:10:00", duration_minutes: 60 },
    ]);
    expect(bounds.startMinutes).toBe(120);
    expect(bounds.endMinutes).toBe(1260);
  });

  it("grows at the foot for a late seva, to the whole hour", () => {
    const bounds = gridBounds(TEMPLE_HOURS, [
      { starts_at_local: "21:30:00", duration_minutes: 45 },
    ]);
    expect(bounds.endMinutes).toBe(1380);
  });

  it("never runs past midnight, however long the seva", () => {
    const bounds = gridBounds(TEMPLE_HOURS, [
      { starts_at_local: "23:00:00", duration_minutes: 240, ends_next_day: true },
    ]);
    expect(bounds.endMinutes).toBe(1440);
  });

  it("rules one line an hour, inclusive of both ends", () => {
    const lines = hourLines({ startMinutes: 210, endMinutes: 1260 });
    expect(lines[0]).toBe(240);
    expect(lines.at(-1)).toBe(1260);
    expect(lines).toHaveLength(18);
  });

  it("is as tall as the hours it covers", () => {
    expect(gridHeight({ startMinutes: 210, endMinutes: 1260 }, 60)).toBe(1050);
  });
});

describe("where a block lands", () => {
  const bounds = { startMinutes: 210, endMinutes: 1260 };

  it("puts a 90-minute seva at 4:15 in the right place", () => {
    // 45 minutes past the 3:30 top of the grid, and an hour and a half long.
    const geometry = blockGeometry(
      { starts_at_local: "04:15:00", duration_minutes: 90 },
      bounds,
      56,
    );
    expect(geometry.top).toBe(42);
    expect(geometry.height).toBe(84);
    expect(geometry.continuesPastMidnight).toBe(false);
  });

  it("starts Mangala Arati exactly on the 4:30 line", () => {
    const geometry = blockGeometry(
      { starts_at_local: "04:30:00", duration_minutes: 60 },
      bounds,
      52,
    );
    expect(geometry.top).toBe(52);
  });

  it("grows a short seva to a height that can be hit, without moving its start", () => {
    const geometry = blockGeometry(
      { starts_at_local: "06:00:00", duration_minutes: 15 },
      bounds,
      52,
      34,
    );
    expect(geometry.top).toBe(offsetOf("06:00:00", bounds, 52));
    expect(geometry.height).toBe(34);
  });

  it("stops a seva that runs past midnight at the foot of its own day", () => {
    const geometry = blockGeometry(
      { starts_at_local: "23:00:00", duration_minutes: 180, ends_next_day: true },
      { startMinutes: 210, endMinutes: 1440 },
      60,
    );
    expect(geometry.height).toBe(60);
    expect(geometry.continuesPastMidnight).toBe(true);
  });

  function offsetOf(
    time: string,
    within: { startMinutes: number },
    pixelsPerHour: number,
  ) {
    return ((minutesFromTime(time) - within.startMinutes) / 60) * pixelsPerHour;
  }
});

describe("seva at the same hour", () => {
  it("gives two overlapping seva a lane each so both are visible", () => {
    const laid = layOutDay([
      { starts_at_local: "17:00:00", duration_minutes: 60, id: "a" },
      { starts_at_local: "17:30:00", duration_minutes: 60, id: "b" },
    ]);
    expect(laid.map((entry) => entry.item.id)).toEqual(["a", "b"]);
    expect(laid.map((entry) => entry.lane)).toEqual([0, 1]);
    expect(laid.every((entry) => entry.lanes === 2)).toBe(true);
  });

  it("leaves a seva that overlaps nothing at full width", () => {
    const laid = layOutDay([
      { starts_at_local: "05:00:00", duration_minutes: 60, id: "a" },
      { starts_at_local: "11:00:00", duration_minutes: 60, id: "b" },
    ]);
    expect(laid.every((entry) => entry.lanes === 1)).toBe(true);
  });

  it("reuses a lane once the seva in it has finished", () => {
    // a runs 5-7, b runs 5-6, c runs 6-7. All three are one cluster, but c can
    // sit under b rather than demanding a third of the column.
    const laid = layOutDay([
      { starts_at_local: "05:00:00", duration_minutes: 120, id: "a" },
      { starts_at_local: "05:00:00", duration_minutes: 60, id: "b" },
      { starts_at_local: "06:00:00", duration_minutes: 60, id: "c" },
    ]);
    const byId = new Map(laid.map((entry) => [entry.item.id, entry]));
    expect(byId.get("a")!.lanes).toBe(2);
    expect(byId.get("c")!.lane).toBe(byId.get("b")!.lane);
  });

  it("does not join two clusters that merely touch", () => {
    const laid = layOutDay([
      { starts_at_local: "05:00:00", duration_minutes: 60, id: "a" },
      { starts_at_local: "06:00:00", duration_minutes: 60, id: "b" },
    ]);
    expect(laid.every((entry) => entry.lanes === 1)).toBe(true);
  });
});

describe("tapping empty grid", () => {
  const bounds = { startMinutes: 210, endMinutes: 1260 };

  it("reads a tap as the half hour it landed in, rounding down", () => {
    // 52 points an hour: 200 points below 3:30 is a little past 7:19.
    expect(slotMinutesFromOffset(200, bounds, 52)).toBe(420);
    expect(formatClock(slotMinutesFromOffset(200, bounds, 52))).toBe("7:00 AM");
    expect(slotMinutesFromOffset(0, bounds, 52)).toBe(210);
  });

  it("never offers a slot the grid does not draw", () => {
    expect(slotMinutesFromOffset(-40, bounds, 52)).toBe(210);
    expect(slotMinutesFromOffset(99_999, bounds, 52)).toBe(1230);
  });

  it("cuts the day into one press target per hour, ragged ends included", () => {
    const segments = slotSegments(bounds);
    expect(segments[0]).toEqual({ fromMinutes: 210, toMinutes: 240 });
    expect(segments.at(-1)).toEqual({ fromMinutes: 1200, toMinutes: 1260 });
    expect(segments).toHaveLength(18);
  });
});

describe("paging through weeks and months", () => {
  it("starts a week on Monday, as seva_mala_week_start does", () => {
    // 2026-08-12 is a Wednesday; 2026-08-16 the Sunday that closes its week.
    expect(weekStartKey("2026-08-12")).toBe("2026-08-10");
    expect(weekStartKey("2026-08-16")).toBe("2026-08-10");
    expect(weekStartKey("2026-08-10")).toBe("2026-08-10");
  });

  it("lays a week out Monday to Sunday", () => {
    const days = weekDayKeys("2026-08-10");
    expect(days).toHaveLength(7);
    expect(days[0]).toBe("2026-08-10");
    expect(days[6]).toBe("2026-08-16");
    expect(weekdayOfKey(days[0])).toBe(1);
    expect(weekdayOfKey(days[6])).toBe(0);
  });

  it("pages forward and back over a month boundary", () => {
    expect(addDaysKey("2026-08-31", 7)).toBe("2026-09-07");
    expect(addDaysKey("2026-09-07", -7)).toBe("2026-08-31");
    expect(addDaysKey("2026-12-28", 7)).toBe("2027-01-04");
  });

  it("pages a week without the device's zone moving the day", () => {
    // Every step is a whole week, so the Monday of week n + 1 is the Monday of
    // week n plus seven — this is the assertion that a DST change would break
    // if any of it were done on local Dates.
    let key = weekStartKey("2026-02-25");
    for (let step = 0; step < 12; step += 1) {
      const next = addDaysKey(key, 7);
      expect(weekStartKey(next)).toBe(next);
      expect(weekdayOfKey(next)).toBe(1);
      key = next;
    }
  });

  it("asks a month for its own days and nothing more", () => {
    expect(monthBounds("2026-08-12")).toEqual({
      from: "2026-08-01",
      to: "2026-08-31",
    });
    expect(monthBounds("2026-02-05").to).toBe("2026-02-28");
    expect(monthBounds("2028-02-05").to).toBe("2028-02-29");
  });

  it("keeps every window it asks for inside the server's limit", () => {
    // 35 days. A six-row month grid is 42 cells, which is why the month view
    // fetches the month rather than the grid.
    for (const month of ["2026-01-15", "2026-02-15", "2026-08-15"]) {
      const { from, to } = monthBounds(month);
      expect(daysBetween(from, to)).toBeLessThanOrEqual(MAX_WINDOW_DAYS);
    }
    expect(daysBetween("2026-08-10", "2026-08-16")).toBe(7);
  });

  it("steps a month at a time", () => {
    expect(shiftMonth("2026-08-12", 1)).toBe("2026-09-01");
    expect(shiftMonth("2026-01-31", -1)).toBe("2025-12-01");
  });

  it("draws a month grid Monday first with other months left blank", () => {
    // 2026-08-01 is a Saturday, so August opens five cells into its first row.
    const cells = monthGridCells("2026-08-12");
    expect(cells).toHaveLength(42);
    expect(cells.slice(0, 5).every((cell) => cell === null)).toBe(true);
    expect(cells[5]).toBe("2026-08-01");
    expect(cells[6]).toBe("2026-08-02");
    expect(cells.filter(Boolean)).toHaveLength(31);
  });
});
