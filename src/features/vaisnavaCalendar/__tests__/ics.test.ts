import { classifyVaisnavaEvent, parseVaisnavaIcs } from "../ics";

function calendar(events: Array<{ date: string; title: string; uid?: string }>) {
  return [
    "BEGIN:VCALENDAR",
    ...events.flatMap((event, index) => [
      "BEGIN:VEVENT",
      `UID:${event.uid ?? `event-${index}`}`,
      `DTSTART;VALUE=DATE:${event.date}`,
      `SUMMARY:${event.title}`,
      "DESCRIPTION:",
      "END:VEVENT",
    ]),
    "END:VCALENDAR",
  ].join("\r\n");
}

describe("Vaisnava ICS parsing", () => {
  it.each([
    ["Fasting for Sat-tila Ekadasi", "fasting"],
    ["Vyanjuli Mahadvadasi", "ekadasi"],
    ["Break fast 07:15 - 08:48 LT", "parana"],
    ["Srila Prabhupada -- Appearance", "appearance"],
    ["Sri Jayadeva Gosvami -- Disappearance", "disappearance"],
    ["Sri Krsna Janmastami", "festival"],
    ["Ganga Sagara Mela", "observance"],
  ] as const)("classifies %s", (title, kind) => {
    expect(classifyVaisnavaEvent(title)).toBe(kind);
  });

  it("parses, unfolds, sorts, and deduplicates one complete year", () => {
    const entries = Array.from({ length: 10 }, (_, index) => ({
      date: `2026${String(index + 1).padStart(2, "0")}01`,
      title: index === 0 ? "Fasting for\r\n Sat-tila Ekadasi" : `Event ${index}`,
      uid: index === 9 ? "event-8" : undefined,
    }));
    // The last event shares a UID but not a date, so it remains a distinct
    // occurrence; exact date + UID duplicates do not.
    entries.push({ date: "20260101", title: "Duplicate", uid: "event-0" });

    const parsed = parseVaisnavaIcs(calendar(entries));
    expect(parsed.year).toBe(2026);
    expect(parsed.events).toHaveLength(10);
    expect(parsed.events[0]).toMatchObject({
      date: "2026-01-01",
      title: "Fasting forSat-tila Ekadasi",
      kind: "fasting",
    });
  });

  it("rejects a partial file and a file spanning multiple years", () => {
    expect(() =>
      parseVaisnavaIcs(calendar([{ date: "20260101", title: "One" }])),
    ).toThrow("complete yearly calendar");

    const events = Array.from({ length: 10 }, (_, index) => ({
      date: index === 9 ? "20270101" : `20260${index + 1}01`,
      title: `Event ${index}`,
    }));
    expect(() => parseVaisnavaIcs(calendar(events))).toThrow(
      "one calendar year at a time",
    );
  });
});
