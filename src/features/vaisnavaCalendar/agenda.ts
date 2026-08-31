import { monthName, shortMonthName, shortWeekdayName } from "./calendarDates";
import { paranaWindow, type ParanaWindow } from "./parana";
import type { VaisnavaCalendarEvent, VaisnavaEventKind } from "./types";

/**
 * The calendar as an agenda rather than a grid.
 *
 * Roughly two thirds of the year has nothing on it, and the days that do have
 * something usually have several — the 2026 file has days carrying six. A
 * month grid can hold neither fact: an empty cell and a cell with six
 * observances differ only by a row of dots, and no cell is wide enough for
 * "Srila Bhaktisiddhanta Sarasvati Thakura -- Disappearance". Grouping to days
 * that actually have events lets the screen print what each day *is*.
 */

export type VaisnavaDay = {
  /** "2026-01-23" */
  date: string;
  day: number;
  /** 0-11, so a day knows the month rail entry it belongs to. */
  month: number;
  /** "Fri" */
  weekday: string;
  /** Most consequential first — see `KIND_WEIGHT`. */
  events: VaisnavaCalendarEvent[];
  /** The break-fast window falling on this day, when it is readable. */
  parana: ParanaWindow | null;
  /**
   * Which event `parana` came from, so the screen can lift it out of the list
   * of titles. Null when a pāraṇa row could not be read — that row then stays
   * among the titles and is shown as the temple published it.
   */
  paranaEventId: string | null;
  /** True when this day asks the devotee to fast. */
  fasting: boolean;
};

export type VaisnavaMonth = {
  month: number;
  /** "January 2026" */
  label: string;
  /** "Jan" */
  shortLabel: string;
  days: VaisnavaDay[];
  eventCount: number;
};

/**
 * What a devotee has to act on, before what they only have to know. A pāraṇa
 * has a deadline; an Ekādaśī asks them to fast; a festival asks them to come;
 * a named holy day asks them to observe; an appearance or disappearance asks
 * them to remember. Sorting on the file's own `sort_order` instead put "Ganga
 * Sagara Mela" above "Fasting for Sat-tila Ekadasi" on 14 January, which is
 * the wrong way round for a devotee glancing at the day.
 */
const KIND_WEIGHT: Record<VaisnavaEventKind, number> = {
  parana: 0,
  ekadasi: 1,
  fasting: 2,
  festival: 3,
  observance: 4,
  appearance: 5,
  disappearance: 6,
  other: 7,
};

/**
 * "(Fast till noon)", "(Fasting is done yesterday, today is feast)".
 *
 * The file writes these as ordinary entries, but they are notes qualifying the
 * day rather than observances of their own — 25 January carries Sri Advaita
 * Acarya's appearance and "(Fast till noon)", and by kind alone the bracket
 * would headline the day. Anything parenthesised sinks below everything real.
 *
 * Exported because the screen sets a note quieter than the observance it
 * qualifies, and that decision must be made on the same fact the ordering was.
 */
export function isDayNote(title: string) {
  return title.trimStart().startsWith("(");
}

/** Dates are plain keys, never Date objects, so no device zone can shift them. */
function utcFor(date: string) {
  const [year, month, day] = date.split("-").map(Number);
  return Date.UTC(year, month - 1, day);
}

export function shiftDateKey(date: string, days: number) {
  return new Date(utcFor(date) + days * 86_400_000).toISOString().slice(0, 10);
}

export function daysBetween(from: string, to: string) {
  return Math.round((utcFor(to) - utcFor(from)) / 86_400_000);
}

export function isFastingKind(kind: VaisnavaEventKind) {
  return kind === "ekadasi" || kind === "fasting";
}

/**
 * The source hangs bracketed notes on some titles -- "[PURNIMA SYSTEM]" says
 * which reckoning a Caturmasya month follows. That is addressed to whoever
 * maintains the calendar, not to a devotee reading what today is, and shouting
 * it in capitals on the day's headline is the opposite of what it deserves.
 * Migration 202608260076 drops it from the notification wording for the same
 * reason; this keeps the screen saying what the notice says.
 */
function editorialNotesRemoved(title: string) {
  return title.replace(/\s*\[[^\]]*\]\s*/g, " ").trim();
}

/**
 * The brackets a note is written inside are the file's punctuation, not the
 * temple's instruction. "(Fast till noon)" is read aloud as a bracket by a
 * screen reader and set as one on the page, when the sentence inside it is the
 * whole of what it says; the note is already marked as a note by where it sits
 * and how it is set. Only a title wrapped whole, and holding no brackets of its
 * own, is unwrapped.
 */
function unwrapped(title: string) {
  const match = /^\(([^()]+)\)$/.exec(title.trim());
  return match ? match[1].trim() : title;
}

/**
 * "Srila Gopala Bhatta Gosvami -- Appearance" as its two halves. The file's
 * double hyphen is not something to show a devotee, and the name and the
 * occasion want different weight — but the name must never be truncated to
 * make room, so the screen sets them as one wrapping paragraph.
 */
export function splitEventTitle(title: string) {
  const cleaned = unwrapped(editorialNotesRemoved(title));
  const parts = cleaned.split(/\s+--\s+/);
  if (parts.length !== 2 || !parts[0].trim() || !parts[1].trim()) {
    return { name: cleaned, qualifier: null as string | null };
  }
  return { name: parts[0].trim(), qualifier: parts[1].trim() };
}

/** Every day carrying at least one event, in date order. */
export function groupCalendarDays(
  events: readonly VaisnavaCalendarEvent[],
): VaisnavaDay[] {
  const byDate = new Map<string, VaisnavaCalendarEvent[]>();
  for (const event of events) {
    const existing = byDate.get(event.event_date);
    if (existing) existing.push(event);
    else byDate.set(event.event_date, [event]);
  }

  return [...byDate.entries()]
    .sort(([left], [right]) => left.localeCompare(right))
    .map(([date, dayEvents]) => {
      const ordered = [...dayEvents].sort(
        (left, right) =>
          Number(isDayNote(left.title)) - Number(isDayNote(right.title)) ||
          KIND_WEIGHT[left.event_kind] - KIND_WEIGHT[right.event_kind] ||
          left.sort_order - right.sort_order ||
          left.title.localeCompare(right.title),
      );
      const readable = ordered
        .map((event) => ({ event, window: paranaWindow(event) }))
        .find((candidate) => candidate.window);
      return {
        date,
        day: Number(date.slice(8, 10)),
        month: Number(date.slice(5, 7)) - 1,
        weekday: shortWeekdayName(date),
        events: ordered,
        parana: readable?.window ?? null,
        paranaEventId: readable?.event.id ?? null,
        fasting: ordered.some((event) => isFastingKind(event.event_kind)),
      };
    });
}

/** Only the months that have something in them, so the rail cannot lie. */
export function groupCalendarMonths(
  days: readonly VaisnavaDay[],
  year: number,
): VaisnavaMonth[] {
  const byMonth = new Map<number, VaisnavaDay[]>();
  for (const day of days) {
    const existing = byMonth.get(day.month);
    if (existing) existing.push(day);
    else byMonth.set(day.month, [day]);
  }

  return [...byMonth.entries()]
    .sort(([left], [right]) => left - right)
    .map(([month, monthDays]) => ({
      month,
      label: monthName(year, month),
      shortLabel: shortMonthName(year, month),
      days: monthDays,
      eventCount: monthDays.reduce((total, day) => total + day.events.length, 0),
    }));
}

export function findDay(days: readonly VaisnavaDay[], date: string) {
  return days.find((day) => day.date === date) ?? null;
}

/** The soonest day strictly after `date`, for "what is coming". */
export function findNextDay(days: readonly VaisnavaDay[], date: string) {
  return days.find((day) => day.date > date) ?? null;
}

/**
 * The window for breaking a fast begun today, which falls on tomorrow's row.
 *
 * This is the pairing the old screen lost: the fast is published on one date
 * and its pāraṇa on the next, as two unrelated entries. A devotee fasting
 * today needs tomorrow's times today, not tomorrow.
 */
export function nextDayParana(days: readonly VaisnavaDay[], date: string) {
  const tomorrow = findDay(days, shiftDateKey(date, 1));
  return tomorrow?.parana ? { date: tomorrow.date, window: tomorrow.parana } : null;
}

/** "today", "tomorrow", "in 4 days" — how far off something is. */
export function relativeDayLabel(from: string, to: string) {
  const distance = daysBetween(from, to);
  if (distance === 0) return "today";
  if (distance === 1) return "tomorrow";
  if (distance === -1) return "yesterday";
  if (distance > 1) return `in ${distance} days`;
  return `${Math.abs(distance)} days ago`;
}

export function observanceCountLabel(count: number) {
  if (!count) return "Nothing observed";
  return `${count} ${count === 1 ? "observance" : "observances"}`;
}

/**
 * Everything on the day except the pāraṇa the screen sets as a time. An
 * unreadable pāraṇa has no `paranaEventId` and so stays here, where its title
 * is shown exactly as the temple published it.
 */
export function titledEvents(day: VaisnavaDay) {
  return day.events.filter((event) => event.id !== day.paranaEventId);
}

/** The day's observances as one sentence, so a screen reader gets them all. */
export function describeDayTitles(day: VaisnavaDay) {
  return titledEvents(day)
    .map((event) => {
      const { name, qualifier } = splitEventTitle(event.title);
      return qualifier ? `${name}, ${qualifier.toLowerCase()}` : name;
    })
    .join(". ");
}
