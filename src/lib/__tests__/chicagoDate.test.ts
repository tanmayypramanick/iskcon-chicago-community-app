/// <reference types="jest" />

import {
  addChicagoDays,
  chicagoWallClockToInstant,
  formatChicagoDate,
  formatChicagoShortDate,
  formatChicagoTime,
  getChicagoDateKey,
  getChicagoMinutesOfDay,
  getChicagoOffsetMinutes,
  getChicagoWallClock,
  getChicagoWeekday,
  getChicagoZoneAbbreviation,
} from "../chicagoDate";

describe("Chicago date helpers", () => {
  it("uses the temple's Chicago calendar day", () => {
    const justBeforeChicagoMidnight = new Date("2026-08-03T04:59:00.000Z");
    const justAfterChicagoMidnight = new Date("2026-08-03T05:01:00.000Z");

    expect(getChicagoDateKey(justBeforeChicagoMidnight)).toBe("2026-08-02");
    expect(getChicagoDateKey(justAfterChicagoMidnight)).toBe("2026-08-03");
    expect(formatChicagoDate(justBeforeChicagoMidnight)).toBe(
      "Sunday, August 2",
    );
  });

  it("knows CST and CDT, including the exact changeover instants", () => {
    // 2026: DST starts Sunday March 8, ends Sunday November 1.
    const deepWinter = new Date("2026-01-15T12:00:00.000Z");
    const deepSummer = new Date("2026-07-15T12:00:00.000Z");

    expect(getChicagoOffsetMinutes(deepWinter)).toBe(-360);
    expect(getChicagoZoneAbbreviation(deepWinter)).toBe("CST");
    expect(getChicagoOffsetMinutes(deepSummer)).toBe(-300);
    expect(getChicagoZoneAbbreviation(deepSummer)).toBe("CDT");

    // 08:00Z on the spring-forward morning is 02:00 CST -> clocks jump to 03:00.
    expect(getChicagoOffsetMinutes(new Date("2026-03-08T07:59:00.000Z"))).toBe(
      -360,
    );
    expect(getChicagoOffsetMinutes(new Date("2026-03-08T08:00:00.000Z"))).toBe(
      -300,
    );
    // Clocks fall back at 02:00 CDT, which is 07:00Z: 01:00 repeats as CST.
    expect(getChicagoOffsetMinutes(new Date("2026-11-01T06:59:00.000Z"))).toBe(
      -300,
    );
    expect(getChicagoOffsetMinutes(new Date("2026-11-01T07:00:00.000Z"))).toBe(
      -360,
    );
  });

  it("returns a whole-minute offset even when the instant has milliseconds", () => {
    // Date.UTC() carries no milliseconds, so an unrounded difference against a
    // real clock reading lands on a fraction and breaks the zone comparison.
    const withMillis = new Date("2026-08-03T23:58:10.315Z");
    expect(getChicagoOffsetMinutes(withMillis)).toBe(-300);
    expect(getChicagoZoneAbbreviation(withMillis)).toBe("CDT");

    const winterMillis = new Date("2026-01-15T18:22:41.907Z");
    expect(getChicagoOffsetMinutes(winterMillis)).toBe(-360);
    expect(getChicagoZoneAbbreviation(winterMillis)).toBe("CST");
  });

  it("converts a Chicago wall clock to the right instant in both zones", () => {
    // 18:30 CDT on 3 August is 23:30 UTC.
    expect(
      chicagoWallClockToInstant("2026-08-03", "18:30").toISOString(),
    ).toBe("2026-08-03T23:30:00.000Z");
    // 18:30 CST on 15 January is 00:30 UTC the next day.
    expect(
      chicagoWallClockToInstant("2026-01-15", "18:30").toISOString(),
    ).toBe("2026-01-16T00:30:00.000Z");
  });

  it("resolves wall-clock times either side of a DST change", () => {
    // 01:30 on spring-forward day still exists, in CST.
    expect(
      chicagoWallClockToInstant("2026-03-08", "01:30").toISOString(),
    ).toBe("2026-03-08T07:30:00.000Z");
    // 03:30 is after the jump, in CDT.
    expect(
      chicagoWallClockToInstant("2026-03-08", "03:30").toISOString(),
    ).toBe("2026-03-08T08:30:00.000Z");
    // A seva scheduled for 09:00 lands correctly on both sides of the change.
    expect(
      chicagoWallClockToInstant("2026-03-07", "09:00").toISOString(),
    ).toBe("2026-03-07T15:00:00.000Z");
    expect(
      chicagoWallClockToInstant("2026-03-09", "09:00").toISOString(),
    ).toBe("2026-03-09T14:00:00.000Z");
  });

  it("round-trips a wall clock back to the same wall clock", () => {
    for (const dateKey of ["2026-01-15", "2026-03-08", "2026-07-04", "2026-11-01"]) {
      const instant = chicagoWallClockToInstant(dateKey, "14:45");
      const clock = getChicagoWallClock(instant);
      expect(clock.dateKey).toBe(dateKey);
      expect(clock.hour).toBe(14);
      expect(clock.minute).toBe(45);
    }
  });

  it("reports the weekday and minutes of day at the temple, not on the device", () => {
    // 02:30 UTC on 4 August is still 21:30 on Monday 3 August in Chicago.
    const lateMonday = new Date("2026-08-04T02:30:00.000Z");
    expect(getChicagoWeekday(lateMonday)).toBe(1);
    expect(getChicagoMinutesOfDay(lateMonday)).toBe(21 * 60 + 30);
    expect(getChicagoDateKey(lateMonday)).toBe("2026-08-03");
  });

  it("formats times and dates at the temple regardless of device zone", () => {
    const instant = new Date("2026-08-03T23:30:00.000Z");
    expect(formatChicagoTime(instant)).toBe("6:30 PM");
    expect(formatChicagoShortDate(instant)).toBe("Mon, Aug 3");
  });

  it("adds days on the Chicago calendar, across a DST change", () => {
    expect(addChicagoDays(1, new Date("2026-08-03T23:30:00.000Z"))).toBe(
      "2026-08-04",
    );
    // 05:30Z on 2 November is 23:30 on 1 November in Chicago (CST by then).
    expect(addChicagoDays(1, new Date("2026-11-02T05:30:00.000Z"))).toBe(
      "2026-11-02",
    );
    expect(addChicagoDays(-1, new Date("2026-03-08T08:30:00.000Z"))).toBe(
      "2026-03-07",
    );
  });
});
