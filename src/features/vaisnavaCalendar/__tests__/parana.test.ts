/// <reference types="jest" />

import {
  describeParana,
  formatClockTime,
  formatParanaRange,
  formatParanaReason,
  paranaWindow,
  parseParanaTitle,
} from "../parana";
import type { VaisnavaCalendarEvent } from "../types";

function paranaEvent(
  title: string,
  extra: Partial<VaisnavaCalendarEvent> = {},
): VaisnavaCalendarEvent {
  return {
    id: "parana-1",
    calendar_year: 2026,
    event_date: "2026-01-15",
    title,
    description: null,
    event_kind: "parana",
    source_uid: "uid-1",
    sort_order: 9,
    created_at: "2026-01-01T00:00:00.000Z",
    ...extra,
  };
}

describe("reading a parana window out of a title", () => {
  it("reads a bounded window with a reason on each side", () => {
    expect(
      parseParanaTitle("Break fast 07:15 (sunrise) - 08:48 (end of tithi) LT"),
    ).toStrictEqual({
      start: { time: "07:15", reason: "sunrise" },
      end: { time: "08:48", reason: "end of tithi" },
      zone: "CST",
    });
  });

  it("reads reasons that contain slashes and digits", () => {
    expect(
      parseParanaTitle(
        "Break fast 07:45 (1/4 of tithi) - 10:24 (1/3 of daylight) DST",
      ),
    ).toStrictEqual({
      start: { time: "07:45", reason: "1/4 of tithi" },
      end: { time: "10:24", reason: "1/3 of daylight" },
      zone: "CDT",
    });
  });

  it("reads a window the calendar leaves open-ended", () => {
    expect(
      parseParanaTitle("Break fast after 11:12 (end of tithi) DST"),
    ).toStrictEqual({
      start: { time: "11:12", reason: "end of tithi" },
      end: null,
      zone: "CDT",
    });
  });

  it("reads a bare window with no reasons and no zone marker", () => {
    expect(parseParanaTitle("Break fast 07:15 - 08:48")).toStrictEqual({
      start: { time: "07:15", reason: null },
      end: { time: "08:48", reason: null },
      zone: null,
    });
  });

  it("refuses anything not shaped like a window", () => {
    expect(parseParanaTitle("Fasting for Sat-tila Ekadasi")).toBeNull();
    expect(parseParanaTitle("Break fast sometime this morning")).toBeNull();
    expect(parseParanaTitle("Break fast 07:15 - 08:48 - 09:00")).toBeNull();
    expect(parseParanaTitle("Break fast 29:99 (sunrise)")).toBeNull();
  });
});

describe("paranaWindow across the migration boundary", () => {
  it("prefers migration 0076's columns when the database has them", () => {
    const window = paranaWindow(
      paranaEvent("Break fast 07:15 (sunrise) - 08:48 (end of tithi) LT", {
        parana_start_time: "07:20:00",
        parana_end_time: "08:50:00",
        parana_start_reason: "sunrise",
        parana_end_reason: "end of tithi",
      }),
    );
    expect(window).toStrictEqual({
      start: { time: "07:20", reason: "sunrise" },
      end: { time: "08:50", reason: "end of tithi" },
      zone: "CST",
    });
  });

  it("keeps an open-ended window open when the end column is null", () => {
    const window = paranaWindow(
      paranaEvent("Break fast after 11:12 (end of tithi) DST", {
        parana_start_time: "11:12:00",
        parana_end_time: null,
        parana_start_reason: "end of tithi",
        parana_end_reason: null,
      }),
    );
    expect(window?.end).toBeNull();
    expect(formatParanaRange(window!)).toBe("After 11:12 AM");
  });

  it("falls back to the title before the migration is deployed", () => {
    const window = paranaWindow(
      paranaEvent("Break fast 06:26 (sunrise) - 09:15 (end of tithi) LT"),
    );
    expect(window?.start.time).toBe("06:26");
    expect(window?.end?.time).toBe("09:15");
  });

  it("gives up on an unreadable parana so the title can be shown instead", () => {
    expect(paranaWindow(paranaEvent("Break fast at the temple"))).toBeNull();
  });

  it("reads the 2027 file's open-ended entry as published", () => {
    const window = paranaWindow(
      paranaEvent("Break fast after 11:12 (1/4 of tithi) LT", {
        event_date: "2027-01-03",
        calendar_year: 2027,
      }),
    );
    expect(window).toStrictEqual({
      start: { time: "11:12", reason: "1/4 of tithi" },
      end: null,
      zone: "CST",
    });
  });

  it("keeps a window open when the flag says so, whatever else is set", () => {
    const window = paranaWindow(
      paranaEvent("Break fast after 11:12 (1/4 of tithi) LT", {
        parana_start_time: "11:12:00",
        parana_end_time: "13:00:00",
        parana_is_open_ended: true,
      }),
    );
    expect(window?.end).toBeNull();
  });

  it("labels the window with the zone the date is actually in", () => {
    // The source's marker is provenance, not arithmetic: the printed time is
    // already Chicago wall clock, so the label has to follow the date. Adding
    // an hour to the summer rows would hand the congregation a broken fast.
    const summer = paranaWindow(
      paranaEvent("Break fast 05:15 (sunrise) - 09:08 (end of tithi) DST", {
        event_date: "2026-06-12",
      }),
    );
    expect(summer?.zone).toBe("CDT");
    expect(summer?.start.time).toBe("05:15");

    const winter = paranaWindow(
      paranaEvent("Break fast 07:15 (sunrise) - 08:48 (end of tithi) LT", {
        event_date: "2026-01-15",
      }),
    );
    expect(winter?.zone).toBe("CST");
  });

  it("trusts the date over a marker that contradicts it", () => {
    const window = paranaWindow(
      paranaEvent("Break fast 05:15 (sunrise) - 09:08 (end of tithi) LT", {
        event_date: "2026-06-12",
        parana_start_time: "05:15:00",
        parana_end_time: "09:08:00",
        parana_clock_marker: "LT",
      }),
    );
    expect(window?.zone).toBe("CDT");
  });

  it("never reads a window off an event that is not a parana", () => {
    expect(
      paranaWindow(
        paranaEvent("Break fast 07:15 - 08:48 LT", { event_kind: "observance" }),
      ),
    ).toBeNull();
  });
});

describe("presenting a parana window", () => {
  it("says the meridiem once when the window does not cross noon", () => {
    const window = parseParanaTitle(
      "Break fast 07:15 (sunrise) - 08:48 (end of tithi) LT",
    )!;
    expect(formatParanaRange(window)).toBe("7:15 – 8:48 AM");
    expect(formatParanaReason(window)).toBe("from sunrise until end of tithi");
  });

  it("says it twice when the window does cross noon", () => {
    const window = parseParanaTitle("Break fast 11:45 - 12:10 DST")!;
    expect(formatParanaRange(window)).toBe("11:45 AM – 12:10 PM");
  });

  it("formats midnight and noon as a devotee reads them on a clock", () => {
    expect(formatClockTime("00:05")).toBe("12:05 AM");
    expect(formatClockTime("12:00")).toBe("12:00 PM");
  });

  it("keeps only the half of the reason the file gave", () => {
    const window = parseParanaTitle("Break fast 07:15 (sunrise) - 08:48")!;
    expect(formatParanaReason(window)).toBe("from sunrise");
  });

  it("says the whole window as a sentence for a screen reader", () => {
    expect(
      describeParana(
        parseParanaTitle(
          "Break fast 07:15 (sunrise) - 08:48 (end of tithi) LT",
        )!,
      ),
    ).toBe(
      "Break fast between 7:15 AM and 8:48 AM CST, from sunrise until end of tithi.",
    );
    expect(
      describeParana(parseParanaTitle("Break fast after 11:12 DST")!),
    ).toBe("Break fast after 11:12 AM CDT.");
  });
});
