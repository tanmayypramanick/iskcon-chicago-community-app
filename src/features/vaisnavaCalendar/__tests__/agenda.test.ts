/// <reference types="jest" />

import {
  daysBetween,
  describeDayTitles,
  findDay,
  findNextDay,
  groupCalendarDays,
  groupCalendarMonths,
  nextDayParana,
  observanceCountLabel,
  relativeDayLabel,
  shiftDateKey,
  splitEventTitle,
} from "../agenda";
import type { VaisnavaCalendarEvent, VaisnavaEventKind } from "../types";

let nextId = 0;

function event(
  event_date: string,
  title: string,
  event_kind: VaisnavaEventKind,
  sort_order = ++nextId,
): VaisnavaCalendarEvent {
  return {
    id: `event-${(nextId += 1)}`,
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

/** The real 14–15 January 2026 shape: a fast, then its window the next day. */
const ekadasiWeek = [
  event("2026-01-14", "Ganga Sagara Mela", "observance", 8),
  event("2026-01-14", "Vyanjuli Mahadvadasi", "ekadasi", 6),
  event("2026-01-14", "Fasting for Sat-tila Ekadasi", "fasting", 7),
  event(
    "2026-01-15",
    "Break fast 07:15 (sunrise) - 08:48 (end of tithi) LT",
    "parana",
    9,
  ),
];

describe("grouping the calendar into days", () => {
  it("gathers a multi-event day into one entry", () => {
    // 23 January 2026 really does carry six observances.
    const days = groupCalendarDays([
      event("2026-01-23", "Vasanta Pancami", "observance", 10),
      event("2026-01-23", "Srimati Visnupriya Devi -- Appearance", "appearance", 11),
      event(
        "2026-01-23",
        "Srila Visvanatha Cakravarti Thakura -- Disappearance",
        "disappearance",
        12,
      ),
      event("2026-01-23", "Sri Pundarika Vidyanidhi -- Appearance", "appearance", 13),
      event("2026-01-23", "Sarasvati Puja", "observance", 16),
      event("2026-01-25", "Sri Advaita Acarya -- Appearance", "appearance", 17),
    ]);

    expect(days).toHaveLength(2);
    expect(days[0].date).toBe("2026-01-23");
    expect(days[0].events).toHaveLength(5);
    expect(days[0].day).toBe(23);
    expect(days[0].month).toBe(0);
    expect(days[0].weekday).toBe("Fri");
    expect(days[0].fasting).toBe(false);
    expect(days[1].date).toBe("2026-01-25");
  });

  it("puts what a devotee must act on above what they must only know", () => {
    const [fastDay, paranaDay] = groupCalendarDays(ekadasiWeek);

    expect(fastDay.events.map((item) => item.event_kind)).toStrictEqual([
      "ekadasi",
      "fasting",
      "observance",
    ]);
    expect(fastDay.fasting).toBe(true);
    expect(paranaDay.fasting).toBe(false);
  });

  it("sinks a parenthesised note below the observance it qualifies", () => {
    // 25 January 2026: by kind alone the bracket outranks the appearance and
    // would headline the day, which is the wrong way round.
    const [day] = groupCalendarDays([
      event("2026-01-25", "(Fast till noon)", "observance", 18),
      event("2026-01-25", "Sri Advaita Acarya -- Appearance", "appearance", 17),
    ]);
    expect(day.events.map((item) => item.title)).toStrictEqual([
      "Sri Advaita Acarya -- Appearance",
      "(Fast till noon)",
    ]);
  });

  it("keeps the file's own order between events of the same kind", () => {
    const [day] = groupCalendarDays([
      event("2026-01-23", "Second appearance", "appearance", 30),
      event("2026-01-23", "First appearance", "appearance", 20),
    ]);
    expect(day.events.map((item) => item.title)).toStrictEqual([
      "First appearance",
      "Second appearance",
    ]);
  });

  it("lifts a readable parana out of the day so it can be set as a time", () => {
    const [, paranaDay] = groupCalendarDays(ekadasiWeek);
    expect(paranaDay.parana?.start.time).toBe("07:15");
    expect(paranaDay.parana?.end?.time).toBe("08:48");
    expect(paranaDay.paranaEventId).toBe(paranaDay.events[0].id);
  });

  it("leaves an unreadable parana among the titles so nothing is lost", () => {
    const [day] = groupCalendarDays([
      event("2026-01-15", "Break fast after morning arati", "parana", 9),
    ]);
    expect(day.parana).toBeNull();
    expect(day.paranaEventId).toBeNull();
    expect(day.events).toHaveLength(1);
  });
});

describe("finding today and what is next", () => {
  const days = groupCalendarDays(ekadasiWeek);

  it("finds the day a devotee is standing in", () => {
    expect(findDay(days, "2026-01-14")?.date).toBe("2026-01-14");
  });

  it("returns nothing for a day the calendar does not list", () => {
    expect(findDay(days, "2026-01-16")).toBeNull();
  });

  it("finds the next observance from a day with nothing on it", () => {
    expect(findNextDay(days, "2026-01-10")?.date).toBe("2026-01-14");
  });

  it("never offers today itself as what is next", () => {
    expect(findNextDay(days, "2026-01-14")?.date).toBe("2026-01-15");
    expect(findNextDay(days, "2026-01-15")).toBeNull();
  });

  it("pairs a fast with the window that ends it the following day", () => {
    const paired = nextDayParana(days, "2026-01-14");
    expect(paired?.date).toBe("2026-01-15");
    expect(paired?.window.start.time).toBe("07:15");
    expect(nextDayParana(days, "2026-01-15")).toBeNull();
  });
});

describe("month grouping for the rail", () => {
  it("offers only months that have something in them", () => {
    const months = groupCalendarMonths(
      groupCalendarDays([
        ...ekadasiWeek,
        event("2026-03-03", "Gaura Purnima", "festival", 40),
      ]),
      2026,
    );

    expect(months.map((month) => month.shortLabel)).toStrictEqual([
      "Jan",
      "Mar",
    ]);
    expect(months[0].label).toBe("January 2026");
    expect(months[0].eventCount).toBe(4);
    expect(months[0].days).toHaveLength(2);
    expect(months[1].month).toBe(2);
  });
});

describe("wording", () => {
  it("splits the file's double hyphen into a name and an occasion", () => {
    expect(splitEventTitle("Srila Gopala Bhatta Gosvami -- Appearance")).toStrictEqual(
      { name: "Srila Gopala Bhatta Gosvami", qualifier: "Appearance" },
    );
  });

  it("leaves a title alone when there is nothing to split", () => {
    expect(splitEventTitle("Fasting for Sat-tila Ekadasi")).toStrictEqual({
      name: "Fasting for Sat-tila Ekadasi",
      qualifier: null,
    });
  });

  it("takes the brackets off a note the file wrapped whole", () => {
    // The brackets are the file's punctuation, not the temple's instruction:
    // the sentence inside them is the whole of what the note says, and it is
    // already marked as a note by where it sits and how it is set.
    expect(splitEventTitle("(Fast till noon)")).toStrictEqual({
      name: "Fast till noon",
      qualifier: null,
    });
    // But only a title wrapped whole, and holding no brackets of its own.
    expect(
      splitEventTitle("Sri Krsna Pusya Abhiseka (Radha Ramana)"),
    ).toStrictEqual({
      name: "Sri Krsna Pusya Abhiseka (Radha Ramana)",
      qualifier: null,
    });
  });

  it("counts observances in words", () => {
    expect(observanceCountLabel(0)).toBe("Nothing observed");
    expect(observanceCountLabel(1)).toBe("1 observance");
    expect(observanceCountLabel(6)).toBe("6 observances");
  });

  it("says how far off a day is", () => {
    expect(relativeDayLabel("2026-01-14", "2026-01-14")).toBe("today");
    expect(relativeDayLabel("2026-01-14", "2026-01-15")).toBe("tomorrow");
    expect(relativeDayLabel("2026-01-14", "2026-01-18")).toBe("in 4 days");
    expect(relativeDayLabel("2026-01-14", "2026-01-13")).toBe("yesterday");
  });

  it("gives a screen reader every title on the day", () => {
    const [day] = groupCalendarDays([
      event("2026-01-23", "Vasanta Pancami", "observance", 10),
      event("2026-01-23", "Srimati Visnupriya Devi -- Appearance", "appearance", 11),
    ]);
    expect(describeDayTitles(day)).toBe(
      "Vasanta Pancami. Srimati Visnupriya Devi, appearance",
    );
  });
});

describe("date arithmetic stays on plain keys", () => {
  it("crosses a month and a year boundary without a timezone", () => {
    expect(shiftDateKey("2026-01-31", 1)).toBe("2026-02-01");
    expect(shiftDateKey("2026-12-31", 1)).toBe("2027-01-01");
    expect(shiftDateKey("2026-03-01", -1)).toBe("2026-02-28");
  });

  it("counts days across a daylight-saving change", () => {
    // Chicago springs forward on 8 March 2026; a 23-hour day must still count
    // as one day, which it does only because nothing here uses a local clock.
    expect(daysBetween("2026-03-07", "2026-03-09")).toBe(2);
  });
});

describe("editorial notes are not shown to devotees", () => {
  it("drops the source's bracketed reckoning note", () => {
    expect(
      splitEventTitle("Last day of the first Caturmasya month [PURNIMA SYSTEM]"),
    ).toStrictEqual({
      name: "Last day of the first Caturmasya month",
      qualifier: null,
    });
  });

  it("still splits a name from its occasion once the note is gone", () => {
    expect(
      splitEventTitle("Srila Gopala Bhatta Gosvami -- Appearance [PURNIMA SYSTEM]"),
    ).toStrictEqual({
      name: "Srila Gopala Bhatta Gosvami",
      qualifier: "Appearance",
    });
  });

  it("leaves an ordinary title alone", () => {
    expect(splitEventTitle("Vasanta Pancami")).toStrictEqual({
      name: "Vasanta Pancami",
      qualifier: null,
    });
  });
});
