/**
 * Every date on this calendar is a plain "2026-01-23" key with no time and no
 * zone. Formatting one through `new Date("2026-01-23")` parses it as midnight
 * UTC and then prints it in the device's zone, which shows a Chicago devotee
 * west of Greenwich the day before. Everything here formats at UTC noon so the
 * printed day is always the day that was stored.
 */

function noonUtc(date: string) {
  return new Date(`${date}T12:00:00.000Z`);
}

function firstOfMonth(year: number, month: number) {
  return new Date(Date.UTC(year, month, 1));
}

/** "January 2026" */
export function monthName(year: number, month: number) {
  return new Intl.DateTimeFormat("en-US", {
    month: "long",
    year: "numeric",
    timeZone: "UTC",
  }).format(firstOfMonth(year, month));
}

/** "Jan" — the month rail, where twelve labels share one row. */
export function shortMonthName(year: number, month: number) {
  return new Intl.DateTimeFormat("en-US", {
    month: "short",
    timeZone: "UTC",
  }).format(firstOfMonth(year, month));
}

/** "Friday, January 23" */
export function longCalendarDate(date: string) {
  return new Intl.DateTimeFormat("en-US", {
    weekday: "long",
    month: "long",
    day: "numeric",
    timeZone: "UTC",
  }).format(noonUtc(date));
}

/** "Fri" — the date gutter beside each day of the agenda. */
export function shortWeekdayName(date: string) {
  return new Intl.DateTimeFormat("en-US", {
    weekday: "short",
    timeZone: "UTC",
  }).format(noonUtc(date));
}
