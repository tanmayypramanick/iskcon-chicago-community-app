import { describeDayTitles, type VaisnavaDay } from "./agenda";
import { longCalendarDate } from "./calendarDates";
import { describeParana } from "./parana";

/**
 * The shape of a month, as a grid.
 *
 * All of it is arithmetic on plain "2026-01-23" keys at UTC, never on a local
 * Date — the same reason calendarDates.ts formats at UTC noon. A grid built
 * from device-local dates puts a Chicago devotee's first of the month in the
 * wrong column whenever the phone is east of Greenwich.
 *
 * It lives apart from the screen so the two facts that make a grid feel solid
 * — always six rows, and every cell knowing which month it truly belongs to —
 * can be proved without rendering anything.
 */

const DAY_MS = 86_400_000;

/**
 * Sunday.
 *
 * Chosen here rather than read from the device, because the device's locale is
 * not the temple's week. A phone set to en-GB or hi-IN starts the week on
 * Monday, and the same Ekādaśī would then sit in a different column for two
 * devotees standing beside each other in the same room. Chicago reads its
 * calendars Sunday-first, so the temple's calendar is Sunday-first everywhere.
 */
export const WEEK_START = 0;

/**
 * Six, always — even for a February that fits in four.
 *
 * A grid that grows and shrinks as you page makes everything below it jump,
 * and the jump is what makes a homemade calendar feel homemade. The cost is a
 * row or two of the neighbouring month, which is information rather than
 * padding.
 */
export const GRID_WEEKS = 6;

export const DAYS_IN_WEEK = 7;

/** Three marks, then nothing. A fourth dot is a count nobody reads. */
export const MAX_DAY_DOTS = 3;

export type MonthGridDay = {
  /** "2026-01-23" */
  date: string;
  day: number;
  /** 0-11 — the month this date really belongs to, not the month on screen. */
  month: number;
  year: number;
  /** False for the neighbouring month's days that keep the grid rectangular. */
  inMonth: boolean;
};

function keyOf(utcMs: number) {
  return new Date(utcMs).toISOString().slice(0, 10);
}

/** "2026-02-01" — where a month opens when nothing better is known. */
export function monthStartKey(year: number, month: number) {
  return keyOf(Date.UTC(year, month, 1));
}

/** The month `delta` months from this one, carrying the year with it. */
export function addMonths(year: number, month: number, delta: number) {
  const moved = new Date(Date.UTC(year, month + delta, 1));
  return { year: moved.getUTCFullYear(), month: moved.getUTCMonth() };
}

/** The forty-two days a month is drawn from, in order. */
export function buildMonthGrid(year: number, month: number): MonthGridDay[] {
  const first = Date.UTC(year, month, 1);
  const lead = (new Date(first).getUTCDay() - WEEK_START + DAYS_IN_WEEK) % DAYS_IN_WEEK;
  const start = first - lead * DAY_MS;

  return Array.from({ length: GRID_WEEKS * DAYS_IN_WEEK }, (_, index) => {
    const at = new Date(start + index * DAY_MS);
    return {
      date: keyOf(at.getTime()),
      day: at.getUTCDate(),
      month: at.getUTCMonth(),
      year: at.getUTCFullYear(),
      inMonth: at.getUTCMonth() === month && at.getUTCFullYear() === year,
    };
  });
}

/** The same forty-two days as six rows of seven. */
export function monthGridWeeks(year: number, month: number): MonthGridDay[][] {
  const cells = buildMonthGrid(year, month);
  return Array.from({ length: GRID_WEEKS }, (_, week) =>
    cells.slice(week * DAYS_IN_WEEK, week * DAYS_IN_WEEK + DAYS_IN_WEEK),
  );
}

/** A Sunday, so the header row can be named without a locale deciding it. */
const REFERENCE_SUNDAY = Date.UTC(2026, 0, 4);

const NARROW_WEEKDAY = new Intl.DateTimeFormat("en-US", {
  weekday: "narrow",
  timeZone: "UTC",
});
const LONG_WEEKDAY = new Intl.DateTimeFormat("en-US", {
  weekday: "long",
  timeZone: "UTC",
});

/** The seven column headings: "S", "M", … and the names behind them. */
export function weekdayColumns() {
  return Array.from({ length: DAYS_IN_WEEK }, (_, column) => {
    const at = new Date(
      REFERENCE_SUNDAY + ((column + WEEK_START) % DAYS_IN_WEEK) * DAY_MS,
    );
    return { initial: NARROW_WEEKDAY.format(at), name: LONG_WEEKDAY.format(at) };
  });
}

/** How many dots a day earns. Six observances and three look the same, by design. */
export function dayDotCount(eventCount: number) {
  if (eventCount <= 0) return 0;
  return Math.min(eventCount, MAX_DAY_DOTS);
}

const SWIPE_DISTANCE = 48;
/** A drag has to be half again as horizontal as it is vertical to count. */
const HORIZONTAL_BIAS = 1.5;

/**
 * Which way a drag across the grid means to page: 1 forward, -1 back, 0 not a
 * page at all. The grid sits inside the screen's vertical ScrollView, so a
 * gesture that is merely drifting sideways while scrolling must read as 0 or
 * the month changes under a devotee who was only scrolling down.
 */
export function readSwipe(dx: number, dy: number): -1 | 0 | 1 {
  if (Math.abs(dx) < SWIPE_DISTANCE) return 0;
  if (Math.abs(dx) < Math.abs(dy) * HORIZONTAL_BIAS) return 0;
  // Dragging leftwards pulls the next month in from the right.
  return dx < 0 ? 1 : -1;
}

/**
 * What a day cell says when it is spoken rather than looked at.
 *
 * A grid is hostile to a screen reader — a bare "14" in a table of numbers is
 * nothing — so every cell names its own date in full and then says what is on
 * it, which is the whole reason a sighted devotee looks at the dots.
 */
export function describeGridDay(
  cell: MonthGridDay,
  day: VaisnavaDay | null,
  options: { isToday: boolean },
) {
  const titles = day ? describeDayTitles(day) : "";
  return [
    `${longCalendarDate(cell.date)}.`,
    options.isToday ? "Today." : null,
    day?.fasting ? "Fasting day." : null,
    day?.parana ? describeParana(day.parana) : null,
    titles ? `${titles}.` : null,
    day ? null : "Nothing observed.",
  ]
    .filter(Boolean)
    .join(" ");
}
