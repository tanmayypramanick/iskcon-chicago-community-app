import {
  chicagoWallClockToInstant,
  getChicagoZoneAbbreviation,
} from "../../lib/chicagoDate";
import type { VaisnavaCalendarEvent } from "./types";

/**
 * Pāraṇa — the window in which a devotee who fasted yesterday must break the
 * fast. It is the only entry on this calendar that is an instruction with a
 * deadline, so it is the one entry that must never be left as a sentence for
 * someone to read times out of.
 *
 * The calendar file writes it as a title:
 *
 *   Break fast 07:15 (sunrise) - 08:48 (end of tithi) LT
 *   Break fast after 11:12 (end of tithi) DST
 *
 * Migration 0076 lifts those numbers into real columns. Until it is deployed —
 * and for any older row it does not backfill — the title is the only source,
 * so both paths produce the same shape and the screen cannot tell which one
 * answered.
 */

export type ParanaBound = {
  /** 24-hour "HH:MM" on the temple's clock. */
  time: string;
  /** Why the window opens or closes there, e.g. "sunrise", "end of tithi". */
  reason: string | null;
};

export type ParanaWindow = {
  start: ParanaBound;
  /** Absent when the calendar gives an opening time and no closing one. */
  end: ParanaBound | null;
  /** "CST" or "CDT". Null when the file did not say. */
  zone: string | null;
};

const TITLE = /^\s*break\s+fast\s+(.+?)\s*$/i;
const BOUND = /^(?:after\s+|from\s+)?(\d{1,2}:\d{2})(?:\s*\(([^)]*)\))?$/i;

/**
 * The file marks each window "LT" or "DST" — its own words for standard and
 * daylight time. Every publication is pinned to America/Chicago by the
 * migration and by the import RPC, so those two markers can be named as the
 * abbreviations a Chicago devotee actually reads on a clock.
 */
const ZONE = /\s+(LT|DST|CST|CDT)\s*$/i;

function namedZone(marker: string | undefined): string | null {
  if (!marker) return null;
  const value = marker.toUpperCase();
  if (value === "LT") return "CST";
  if (value === "DST") return "CDT";
  return value;
}

function normaliseTime(value: string | null | undefined): string | null {
  if (!value) return null;
  const match = /^(\d{1,2}):(\d{2})/.exec(value.trim());
  if (!match) return null;
  const hour = Number(match[1]);
  const minute = Number(match[2]);
  if (hour > 23 || minute > 59) return null;
  return `${String(hour).padStart(2, "0")}:${match[2]}`;
}

function cleanReason(value: string | null | undefined): string | null {
  const trimmed = value?.trim();
  return trimmed ? trimmed : null;
}

function readBound(raw: string): ParanaBound | null {
  const match = BOUND.exec(raw.trim());
  if (!match) return null;
  const time = normaliseTime(match[1]);
  if (!time) return null;
  return { time, reason: cleanReason(match[2]) };
}

/** The window a pāraṇa title describes, or null when it is not shaped like one. */
export function parseParanaTitle(title: string): ParanaWindow | null {
  const heading = TITLE.exec(title);
  if (!heading) return null;

  let body = heading[1];
  const zone = namedZone(ZONE.exec(body)?.[1]);
  body = body.replace(ZONE, "").trim();

  // Times are "HH:MM", so a spaced hyphen can only be the range separator; the
  // reasons themselves ("1/3 of daylight") never contain one.
  const parts = body.split(/\s+[-–—]\s+/);
  if (parts.length > 2) return null;

  const start = readBound(parts[0] ?? "");
  if (!start) return null;
  if (parts.length === 1) return { start, end: null, zone };

  const end = readBound(parts[1]);
  if (!end) return null;
  return { start, end, zone };
}

/** Migration 0076's columns, absent on every database that has not run it. */
function parseParanaColumns(event: VaisnavaCalendarEvent): ParanaWindow | null {
  const start = normaliseTime(event.parana_start_time);
  if (!start) return null;
  // 0076 constrains the two to agree, but the flag is the one that says what
  // the source meant, so an open-ended window stays open whatever else is set.
  const end = event.parana_is_open_ended
    ? null
    : normaliseTime(event.parana_end_time);
  return {
    start: { time: start, reason: cleanReason(event.parana_start_reason) },
    end: end
      ? { time: end, reason: cleanReason(event.parana_end_reason) }
      : null,
    zone: namedZone(
      event.parana_clock_marker ?? ZONE.exec(event.title)?.[1] ?? undefined,
    ),
  };
}

/**
 * The break-fast window for an event, from the columns when they exist and
 * from the title otherwise. Null for anything that is not a readable pāraṇa —
 * the caller then shows the title exactly as the temple published it.
 *
 * The published times are already Chicago wall clock, so the "LT" / "DST"
 * marker beside them is never arithmetic — adding an hour to the summer rows
 * would hand the congregation a broken fast. It is only a label, and the
 * truthful label is the abbreviation actually in force on that date, which the
 * date itself answers without trusting the marker at all.
 */
export function paranaWindow(
  event: VaisnavaCalendarEvent,
): ParanaWindow | null {
  if (event.event_kind !== "parana") return null;
  const window = parseParanaColumns(event) ?? parseParanaTitle(event.title);
  if (!window) return null;
  return { ...window, zone: chicagoZoneOn(event.event_date, window) };
}

function chicagoZoneOn(date: string, window: ParanaWindow) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) return window.zone;
  return getChicagoZoneAbbreviation(
    chicagoWallClockToInstant(date, window.start.time),
  );
}

function clockParts(time: string) {
  const [hour, minute] = time.split(":").map(Number);
  const meridiem = hour < 12 ? "AM" : "PM";
  const display = hour % 12 === 0 ? 12 : hour % 12;
  return { text: `${display}:${String(minute).padStart(2, "0")}`, meridiem };
}

/** "7:15 AM" */
export function formatClockTime(time: string) {
  const { text, meridiem } = clockParts(time);
  return `${text} ${meridiem}`;
}

/**
 * "7:15 – 8:48 AM", "7:45 AM – 12:10 PM", or "After 11:12 AM".
 *
 * A window that opens and closes before noon says AM once. Repeating it is
 * noise on the one line of this screen that has to be read at a glance.
 */
export function formatParanaRange(window: ParanaWindow) {
  const start = clockParts(window.start.time);
  if (!window.end) return `After ${start.text} ${start.meridiem}`;
  const end = clockParts(window.end.time);
  if (start.meridiem === end.meridiem) {
    return `${start.text} – ${end.text} ${end.meridiem}`;
  }
  return `${start.text} ${start.meridiem} – ${end.text} ${end.meridiem}`;
}

/** "from sunrise until end of tithi" — null when the file gave no reasons. */
export function formatParanaReason(window: ParanaWindow) {
  const from = window.start.reason ? `from ${window.start.reason}` : null;
  const until = window.end?.reason ? `until ${window.end.reason}` : null;
  if (from && until) return `${from} ${until}`;
  return from ?? until;
}

/** The whole window as a sentence, for a screen reader. */
export function describeParana(window: ParanaWindow) {
  const zone = window.zone ? ` ${window.zone}` : "";
  const when = window.end
    ? `Break fast between ${formatClockTime(window.start.time)} and ${formatClockTime(window.end.time)}${zone}`
    : `Break fast after ${formatClockTime(window.start.time)}${zone}`;
  const reason = formatParanaReason(window);
  return reason ? `${when}, ${reason}.` : `${when}.`;
}
