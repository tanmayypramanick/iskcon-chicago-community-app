/// <reference types="jest" />

import {
  longCalendarDate,
  monthName,
  shortMonthName,
  shortWeekdayName,
} from "../calendarDates";

describe("Vaisnava calendar date labels", () => {
  it("formats dates without shifting them through the device timezone", () => {
    expect(monthName(2026, 7)).toBe("August 2026");
    expect(longCalendarDate("2026-08-27")).toBe("Thursday, August 27");
  });

  it("names the short labels the month rail and date gutter use", () => {
    expect(shortMonthName(2026, 0)).toBe("Jan");
    expect(shortMonthName(2026, 8)).toBe("Sep");
    expect(shortWeekdayName("2026-01-23")).toBe("Fri");
  });

  it("keeps a first-of-month date on its own month", () => {
    // A "2026-03-01" parsed as UTC midnight and printed west of Greenwich
    // reads as 28 February; noon leaves no room for the shift.
    expect(longCalendarDate("2026-03-01")).toBe("Sunday, March 1");
    expect(shortWeekdayName("2026-03-01")).toBe("Sun");
  });
});
