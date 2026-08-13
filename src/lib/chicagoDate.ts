const CHICAGO_TIME_ZONE = "America/Chicago";

/**
 * Everything the temple schedules happens on Chicago's clock, which is CST
 * (UTC-6) in winter and CDT (UTC-5) in summer. The device may be in any zone,
 * so nothing here reads the device calendar — every value is derived from the
 * instant plus the America/Chicago zone, and DST is handled by Intl rather
 * than by any fixed offset of our own.
 */

const partsFormatter = new Intl.DateTimeFormat("en-US", {
  timeZone: CHICAGO_TIME_ZONE,
  hour12: false,
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
  hour: "2-digit",
  minute: "2-digit",
  second: "2-digit",
  weekday: "short",
});

const WEEKDAY_INDEX = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

export type ChicagoWallClock = {
  /** "2026-08-03" */
  dateKey: string;
  year: number;
  month: number;
  day: number;
  hour: number;
  minute: number;
  second: number;
  /** 0 = Sunday, matching Postgres `extract(dow ...)`. */
  weekday: number;
  /** Minutes since Chicago midnight, for comparing against a `time` column. */
  minutesOfDay: number;
};

function readParts(date: Date) {
  return Object.fromEntries(
    partsFormatter.formatToParts(date).map((part) => [part.type, part.value]),
  ) as Record<string, string>;
}

/** The temple's wall clock at a given instant. */
export function getChicagoWallClock(date = new Date()): ChicagoWallClock {
  const values = readParts(date);
  // Intl renders midnight as hour 24 in some engines; normalise it.
  const hour = Number(values.hour) % 24;
  const minute = Number(values.minute);
  return {
    dateKey: `${values.year}-${values.month}-${values.day}`,
    year: Number(values.year),
    month: Number(values.month),
    day: Number(values.day),
    hour,
    minute,
    second: Number(values.second),
    weekday: WEEKDAY_INDEX.indexOf(values.weekday),
    minutesOfDay: hour * 60 + minute,
  };
}

export function getChicagoDateKey(date = new Date()) {
  return getChicagoWallClock(date).dateKey;
}

export function getChicagoWeekday(date = new Date()) {
  return getChicagoWallClock(date).weekday;
}

export function getChicagoMinutesOfDay(date = new Date()) {
  return getChicagoWallClock(date).minutesOfDay;
}

/** Chicago's UTC offset in minutes at a given instant: -360 CST, -300 CDT. */
export function getChicagoOffsetMinutes(date = new Date()) {
  const values = readParts(date);
  const asIfUtc = Date.UTC(
    Number(values.year),
    Number(values.month) - 1,
    Number(values.day),
    Number(values.hour) % 24,
    Number(values.minute),
    Number(values.second),
  );
  // Rounded to whole minutes: Date.UTC has no milliseconds while getTime()
  // does, so the raw difference is a fraction like -300.005 and would fail an
  // exact comparison against a zone offset.
  return Math.round((asIfUtc - date.getTime()) / 60_000);
}

/**
 * Turns a Chicago wall-clock date and time into the actual instant it refers
 * to. Two passes, because the offset used to make the first guess may itself
 * be the wrong side of a DST change.
 *
 * Spring forward (2:00-3:00 does not exist) resolves to the instant the clock
 * reaches; autumn's repeated hour resolves to the first (daylight) pass.
 */
export function chicagoWallClockToInstant(
  dateKey: string,
  time: string,
): Date {
  const [year, month, day] = dateKey.split("-").map(Number);
  const [hour = 0, minute = 0, second = 0] = time.split(":").map(Number);
  const asIfUtc = Date.UTC(year, month - 1, day, hour, minute, second);

  const firstOffset = getChicagoOffsetMinutes(new Date(asIfUtc));
  const firstGuess = asIfUtc - firstOffset * 60_000;
  const secondOffset = getChicagoOffsetMinutes(new Date(firstGuess));
  if (secondOffset === firstOffset) return new Date(firstGuess);
  return new Date(asIfUtc - secondOffset * 60_000);
}

/** "18:30" or "18:30:00" for a `time` column, from a picker's Date. */
export function toDatabaseTime(date: Date) {
  const hour = String(date.getHours()).padStart(2, "0");
  const minute = String(date.getMinutes()).padStart(2, "0");
  return `${hour}:${minute}:00`;
}

/**
 * The instant for "today in Chicago, at the wall-clock time the devotee
 * picked". The picker returns a device-local Date; only its hour and minute
 * are meaningful, and they are read as Chicago time.
 */
export function chicagoInstantFromPickedTime(
  picked: Date,
  dateKey = getChicagoDateKey(),
) {
  return chicagoWallClockToInstant(dateKey, toDatabaseTime(picked));
}

/** Chicago date key `days` days from the given instant. */
export function addChicagoDays(days: number, date = new Date()) {
  const { year, month, day } = getChicagoWallClock(date);
  const shifted = new Date(Date.UTC(year, month - 1, day + days));
  const iso = shifted.toISOString();
  return iso.slice(0, 10);
}

export function formatChicagoDate(date = new Date()) {
  return new Intl.DateTimeFormat("en-US", {
    timeZone: CHICAGO_TIME_ZONE,
    weekday: "long",
    month: "long",
    day: "numeric",
  }).format(date);
}

/** Clock time at the temple, e.g. "6:30 PM", regardless of device zone. */
export function formatChicagoTime(date: Date) {
  return new Intl.DateTimeFormat("en-US", {
    timeZone: CHICAGO_TIME_ZONE,
    hour: "numeric",
    minute: "2-digit",
  }).format(date);
}

/** "Mon, Aug 3" at the temple, regardless of device zone. */
export function formatChicagoShortDate(date: Date) {
  return new Intl.DateTimeFormat("en-US", {
    timeZone: CHICAGO_TIME_ZONE,
    weekday: "short",
    month: "short",
    day: "numeric",
  }).format(date);
}

/**
 * "Tuesday, August 4, 2026 at 6:30 PM" at the temple. Used wherever a devotee
 * needs the whole answer in one line and cannot infer the year or the hour.
 */
export function formatChicagoLongDateTime(date: Date) {
  return new Intl.DateTimeFormat("en-US", {
    timeZone: CHICAGO_TIME_ZONE,
    weekday: "long",
    month: "long",
    day: "numeric",
    year: "numeric",
    hour: "numeric",
    minute: "2-digit",
  }).format(date);
}

/** Which US Central abbreviation is in force, for labelling times. */
export function getChicagoZoneAbbreviation(date = new Date()) {
  return getChicagoOffsetMinutes(date) === -300 ? "CDT" : "CST";
}
