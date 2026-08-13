import { formatClock, minutesFromTime } from "./layout";
import type {
  SevaScheduleOccurrence,
  SevaScheduleServer,
  TempleProgrammeOccurrence,
} from "./types";

/**
 * What a block is allowed to say, and what a screen reader is told instead.
 *
 * The temple's rule for the grid is "on the block just what type of service,
 * service name; if clicked, complete details" — so everything below that reads
 * a roster exists for the accessibility label and the day view, never for the
 * block face.
 */

export function groupByDay<Row extends { occurs_on: string }>(
  rows: readonly Row[],
): Map<string, Row[]> {
  const byDay = new Map<string, Row[]>();
  for (const row of rows) {
    const day = byDay.get(row.occurs_on);
    if (day) day.push(row);
    else byDay.set(row.occurs_on, [row]);
  }
  return byDay;
}

export function occurrencesOn(
  rows: readonly SevaScheduleOccurrence[],
  dateKey: string,
) {
  return rows.filter((row) => row.occurs_on === dateKey);
}

export function programmeOn(
  rows: readonly TempleProgrammeOccurrence[],
  dateKey: string,
) {
  return rows.filter((row) => row.occurs_on === dateKey);
}

/**
 * The temple's programme keyed by weekday.
 *
 * `temple_programme` is a weekly recurrence — a name, a start, and the days it
 * falls on, with no date of its own — and `list_temple_programme` does nothing
 * but expand it across a range. So any seven-day window holds every weekday
 * exactly once and is a complete description of the programme.
 *
 * That is what lets a list spanning a year draw the temple's day on every one
 * of its dates: the server refuses a window over 35 days, and asking for a
 * year in eleven calls to describe ten unchanging rows would be absurd. Sunday
 * is a different day from a weekday here — Gaura Arati moves to 5pm and the
 * lecture, prasadam and kirtan only exist then — and the weekday is exactly
 * what tells those apart.
 */
export function programmeByWeekday(
  rows: readonly TempleProgrammeOccurrence[],
): Map<number, TempleProgrammeOccurrence[]> {
  const byWeekday = new Map<number, TempleProgrammeOccurrence[]>();
  for (const row of rows) {
    const day = byWeekday.get(row.day_of_week);
    if (day) {
      // One window can only hold one instance of each weekday, but a caller
      // asking for a fortnight would otherwise get every entry twice.
      if (!day.some((seen) => seen.programme_id === row.programme_id)) {
        day.push(row);
      }
    } else {
      byWeekday.set(row.day_of_week, [row]);
    }
  }
  for (const day of byWeekday.values()) {
    day.sort(
      (left, right) =>
        minutesFromTime(left.starts_at_local) -
          minutesFromTime(right.starts_at_local) ||
        left.sort_order - right.sort_order,
    );
  }
  return byWeekday;
}

/**
 * "4:30 AM", or "5:15 AM to 7:00 AM". A start with no end is a moment and is
 * said as one — inventing "to 4:30 AM" would claim an end the temple withheld.
 */
export function programmeTimeLabel(entry: TempleProgrammeOccurrence): string {
  const from = minutesFromTime(entry.starts_at_local);
  if (entry.duration_minutes === null) return formatClock(from);
  return `${formatClock(from)} to ${formatClock(from + entry.duration_minutes)}`;
}

/**
 * How one name reads on a roster.
 *
 * A substitute is named as themselves, because the temple's requirement is that
 * "if someone swapped, their name will be there" — whose seva it was is the
 * footnote, and it is only present at all when the server decided this reader
 * may know it.
 */
export function serverLabel(server: SevaScheduleServer): string {
  if (server.isSubstitute && server.coveringForName) {
    return `${server.name} (covering for ${server.coveringForName})`;
  }
  if (server.isSubstitute) return `${server.name} (covering)`;
  return server.name;
}

export type RosterSummary = {
  /** Names this reader may be shown, in the server's order. */
  named: string[];
  /** Places filled that this reader is not allowed a name for. */
  unnamed: number;
  /** The server withheld the roster; only the reader's own place is here. */
  withheld: boolean;
};

/**
 * Who is serving, said honestly.
 *
 * `roster_visible` false is not "nobody is serving": the server has already
 * filtered `servers` down to the reader's own place, while `filled_slots` still
 * counts everybody. Reporting the difference is the only way a devotee is not
 * told a seva is empty when four people are on it.
 */
export function rosterSummary(
  occurrence: SevaScheduleOccurrence,
): RosterSummary {
  const named = occurrence.servers.map(serverLabel);
  return {
    named,
    unnamed: Math.max(occurrence.filled_slots - occurrence.servers.length, 0),
    withheld: !occurrence.roster_visible,
  };
}

/** "2 of 3 places filled", "fully served", "nobody yet". */
export function placesLabel(occurrence: SevaScheduleOccurrence): string {
  if (occurrence.filled_slots === 0) {
    return occurrence.slots_needed === 1
      ? "no one has taken this yet"
      : `no one of ${occurrence.slots_needed} places taken`;
  }
  if (occurrence.open_slots === 0) {
    return occurrence.filled_slots === 1
      ? "1 devotee serving"
      : `${occurrence.filled_slots} devotees serving`;
  }
  return `${occurrence.filled_slots} of ${occurrence.slots_needed} places filled`;
}

export function timeRangeLabel(occurrence: {
  starts_at_local: string;
  duration_minutes: number;
  ends_next_day?: boolean;
}): string {
  const from = minutesFromTime(occurrence.starts_at_local);
  const to = from + occurrence.duration_minutes;
  const suffix = occurrence.ends_next_day ? " the next day" : "";
  return `${formatClock(from)} to ${formatClock(to)}${suffix}`;
}

const weekdayNames = [
  "Sunday",
  "Monday",
  "Tuesday",
  "Wednesday",
  "Thursday",
  "Friday",
  "Saturday",
];

/**
 * Everything the block shows, plus everything it cannot fit.
 *
 * A block is a button four characters wide; a screen reader user has to be able
 * to get the same facts a sighted coordinator gets by looking at the grid and
 * then tapping. So the label carries the day, the clock, how full it is and who
 * is on it — including the fact that names are being withheld, which is a fact
 * about the seva and not an absence of one.
 */
export function occurrenceAccessibilityLabel(
  occurrence: SevaScheduleOccurrence,
): string {
  const roster = rosterSummary(occurrence);
  const parts: string[] = [
    occurrence.seva_name,
    occurrence.from_weekly_template ? "weekly seva" : "one-off seva",
    `${weekdayNames[occurrence.day_of_week] ?? ""} ${occurrence.occurs_on}`.trim(),
    timeRangeLabel(occurrence),
    placesLabel(occurrence),
  ];

  if (roster.named.length) parts.push(`served by ${roster.named.join(", ")}`);
  if (roster.withheld) {
    // Withheld and nobody named at all is a different sentence from withheld
    // with the reader's own place on it: the first has to say why the seva
    // looks empty, or it reads as a seva nobody has taken.
    if (roster.named.length === 0) {
      parts.push("the roster is not shown to you");
    } else if (roster.unnamed > 0) {
      parts.push(
        `${roster.unnamed} other ${roster.unnamed === 1 ? "devotee is" : "devotees are"} not named here`,
      );
    }
  } else if (roster.unnamed > 0) {
    parts.push(`${roster.unnamed} more not named`);
  }
  if (occurrence.status === "cancelled") parts.push("cancelled");

  return parts.filter(Boolean).join(", ");
}

export function programmeAccessibilityLabel(
  entry: TempleProgrammeOccurrence,
): string {
  const from = minutesFromTime(entry.starts_at_local);
  // A null duration is the temple naming a start and no end. It is a moment,
  // and saying "for 0 minutes" would be inventing the end they withheld.
  if (entry.duration_minutes === null) {
    return `${entry.name}, temple programme, ${formatClock(from)}`;
  }
  return `${entry.name}, temple programme, ${formatClock(from)} to ${formatClock(
    from + entry.duration_minutes,
  )}`;
}

export type DayDensity = {
  dateKey: string;
  seva: number;
  /** Occurrences still short of devotees — what a month view is scanned for. */
  openSlots: number;
  unserved: number;
};

/**
 * A month's worth of days reduced to what a 48-point cell can honestly show.
 *
 * Deliberately not a miniature timetable: at this size a block is two pixels
 * tall and says nothing. What survives the shrink is how busy a day is and
 * whether anything on it still needs devotees, which is what a coordinator
 * opens a month for.
 */
export function densityByDay(
  rows: readonly SevaScheduleOccurrence[],
): Map<string, DayDensity> {
  const density = new Map<string, DayDensity>();
  for (const row of rows) {
    const current = density.get(row.occurs_on) ?? {
      dateKey: row.occurs_on,
      seva: 0,
      openSlots: 0,
      unserved: 0,
    };
    current.seva += 1;
    current.openSlots += row.open_slots;
    if (row.nobody_served) current.unserved += 1;
    density.set(row.occurs_on, current);
  }
  return density;
}
