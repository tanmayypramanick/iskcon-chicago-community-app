/**
 * Every number the timetable draws with.
 *
 * Kept apart from the components on purpose: a block landing in the wrong place
 * is the one failure a screenshot cannot be trusted to catch, and this is the
 * only part of the grid that can be asserted directly.
 *
 * Dates are handled as plain "YYYY-MM-DD" keys throughout. The server already
 * answered in Chicago dates, so re-reading them as instants would only give the
 * device's zone a chance to move a day; the arithmetic below is done in UTC,
 * which for a bare date key is pure string maths with a leap-year table.
 */

/** `list_seva_schedule` and `list_temple_programme` both refuse anything longer. */
export const MAX_WINDOW_DAYS = 35;

/** The dials' own seed, drawn until `temple_timetable_hours()` answers. */
export const DEFAULT_DAY_STARTS_AT = "03:30:00";
export const DEFAULT_DAY_ENDS_AT = "21:00:00";

export const MINUTES_PER_DAY = 1440;

/** How finely an empty-slot tap is read. The temple posts on the half hour. */
export const SLOT_SNAP_MINUTES = 30;

export type GridBounds = {
  /** Minutes after Chicago midnight where the grid's first hour line sits. */
  startMinutes: number;
  endMinutes: number;
};

/** "04:15" or "04:15:00" -> 255. */
export function minutesFromTime(value: string): number {
  const [hour = 0, minute = 0] = value.split(":").map(Number);
  return hour * 60 + minute;
}

/** 255 -> "04:15:00", the shape a `time` column and every RPC expects. */
export function timeFromMinutes(minutes: number): string {
  const wrapped = ((minutes % MINUTES_PER_DAY) + MINUTES_PER_DAY) % MINUTES_PER_DAY;
  const hour = String(Math.floor(wrapped / 60)).padStart(2, "0");
  const minute = String(wrapped % 60).padStart(2, "0");
  return `${hour}:${minute}:00`;
}

/** "4:15 PM". Chicago wall clock already, so no zone conversion is wanted. */
export function formatClock(minutes: number): string {
  const wrapped = ((minutes % MINUTES_PER_DAY) + MINUTES_PER_DAY) % MINUTES_PER_DAY;
  const hour24 = Math.floor(wrapped / 60);
  const minute = wrapped % 60;
  const suffix = hour24 < 12 ? "AM" : "PM";
  const hour12 = hour24 % 12 === 0 ? 12 : hour24 % 12;
  return `${hour12}:${String(minute).padStart(2, "0")} ${suffix}`;
}

function keyToUtc(dateKey: string): number {
  const [year, month, day] = dateKey.split("-").map(Number);
  return Date.UTC(year, (month ?? 1) - 1, day ?? 1);
}

function utcToKey(value: number): string {
  return new Date(value).toISOString().slice(0, 10);
}

export function addDaysKey(dateKey: string, days: number): string {
  return utcToKey(keyToUtc(dateKey) + days * 86_400_000);
}

/** 0 = Sunday, matching Postgres `extract(dow ...)` and the RPC's day_of_week. */
export function weekdayOfKey(dateKey: string): number {
  return new Date(keyToUtc(dateKey)).getUTCDay();
}

/**
 * The Monday of a date's week, which is what `seva_mala_week_start` means by a
 * week everywhere else in this app. Sunday belongs to the week that began six
 * days earlier, so the timetable's last column is Sunday.
 */
export function weekStartKey(dateKey: string): string {
  const isoOffset = (weekdayOfKey(dateKey) + 6) % 7;
  return addDaysKey(dateKey, -isoOffset);
}

export function weekDayKeys(weekStart: string): string[] {
  return Array.from({ length: 7 }, (_, index) => addDaysKey(weekStart, index));
}

export function daysBetween(from: string, to: string): number {
  return Math.round((keyToUtc(to) - keyToUtc(from)) / 86_400_000) + 1;
}

/**
 * A month asks for its own days and nothing else.
 *
 * A Monday-first month grid is up to six rows — 42 cells — and the server
 * refuses any window over 35 days. Rather than paging a month in two calls, the
 * grid asks for the month itself (28 to 31 days, always inside the limit) and
 * draws the ragged leading and trailing cells as belonging to another month,
 * which is what they are.
 */
export function monthBounds(dateKey: string): { from: string; to: string } {
  const [year, month] = dateKey.split("-").map(Number);
  const from = `${String(year).padStart(4, "0")}-${String(month).padStart(2, "0")}-01`;
  const to = utcToKey(Date.UTC(year, month, 0));
  return { from, to };
}

export function shiftMonth(dateKey: string, delta: number): string {
  const [year, month] = dateKey.split("-").map(Number);
  return utcToKey(Date.UTC(year, month - 1 + delta, 1));
}

/**
 * Six rows of seven, Monday first. Cells outside the month are null: the grid
 * has no data for them, and drawing a number there would claim otherwise.
 */
export function monthGridCells(dateKey: string): Array<string | null> {
  const { from, to } = monthBounds(dateKey);
  const lead = (weekdayOfKey(from) + 6) % 7;
  const days = daysBetween(from, to);
  return Array.from({ length: 42 }, (_, index) => {
    const dayNumber = index - lead;
    return dayNumber >= 0 && dayNumber < days ? addDaysKey(from, dayNumber) : null;
  });
}

type BoundedOccurrence = {
  starts_at_local: string;
  duration_minutes: number;
  ends_next_day?: boolean;
};

/**
 * Anything with a place on the grid, seva or temple programme. A null duration
 * is the temple naming a start and no end; it occupies its own minute and
 * nothing after it.
 */
type PlacedOnGrid = {
  starts_at_local: string;
  duration_minutes: number | null;
  ends_next_day?: boolean;
};

/**
 * The hours the grid actually draws.
 *
 * `temple_timetable_hours()` is advisory and the migration says so: a 2am seva
 * is still returned, and a grid that started at 3:30 would silently drop it.
 * So the dials are a floor, widened outwards to the whole hour by anything the
 * window really contains. Nothing is ever hidden for being outside temple
 * hours; the day just gets taller.
 *
 * The temple's own programme counts as "anything". `temple_programme.day_starts_at`
 * is a setting the President can move, and it does not move Mangala Arati with
 * it — the dials set to 6am would otherwise draw the 4:30 arati at a negative
 * offset, above the grid and over the dates.
 */
export function gridBounds(
  hours: { day_starts_at: string; day_ends_at: string },
  occurrences: readonly PlacedOnGrid[] = [],
): GridBounds {
  let start = minutesFromTime(hours.day_starts_at);
  let end = minutesFromTime(hours.day_ends_at);

  for (const occurrence of occurrences) {
    const from = minutesFromTime(occurrence.starts_at_local);
    // Anything running past midnight is drawn to the foot of its own day and
    // said so in words; a block cannot be in two columns at once.
    const to = Math.min(
      from + (occurrence.duration_minutes ?? 0),
      MINUTES_PER_DAY,
    );
    if (from < start) start = Math.floor(from / 60) * 60;
    if (to > end) end = Math.min(MINUTES_PER_DAY, Math.ceil(to / 60) * 60);
  }

  return { startMinutes: start, endMinutes: end };
}

export function gridHeight(bounds: GridBounds, pixelsPerHour: number): number {
  return ((bounds.endMinutes - bounds.startMinutes) / 60) * pixelsPerHour;
}

/** Every whole hour line the grid rules, first and last included. */
export function hourLines(bounds: GridBounds): number[] {
  const first = Math.ceil(bounds.startMinutes / 60) * 60;
  const lines: number[] = [];
  for (let minute = first; minute <= bounds.endMinutes; minute += 60) {
    lines.push(minute);
  }
  return lines;
}

/**
 * The empty grid, cut into one press target per hour.
 *
 * One pressable per column would be simpler to draw, but it is a single
 * unlabelled button covering a whole day as far as a screen reader is
 * concerned. An hour at a time can be named — "post a seva on Tuesday at 5 PM"
 * — and the tap's own offset still decides the half hour inside it.
 */
export function slotSegments(
  bounds: GridBounds,
): Array<{ fromMinutes: number; toMinutes: number }> {
  const segments: Array<{ fromMinutes: number; toMinutes: number }> = [];
  let from = bounds.startMinutes;
  while (from < bounds.endMinutes) {
    const nextHour = (Math.floor(from / 60) + 1) * 60;
    const to = Math.min(nextHour, bounds.endMinutes);
    segments.push({ fromMinutes: from, toMinutes: to });
    from = to;
  }
  return segments;
}

export function offsetForMinutes(
  minutes: number,
  bounds: GridBounds,
  pixelsPerHour: number,
): number {
  return ((minutes - bounds.startMinutes) / 60) * pixelsPerHour;
}

export type BlockGeometry = {
  top: number;
  height: number;
  /** The seva runs past midnight and is drawn only as far as this day goes. */
  continuesPastMidnight: boolean;
};

/**
 * Where one seva sits in its column.
 *
 * `minHeight` exists because a fifteen-minute seva is four pixels tall at a
 * readable hour height, and a block nobody can hit is a block nobody can open.
 * It only ever grows a block downwards, so the start — the thing a timetable is
 * read for — stays exactly where the clock says it is.
 */
export function blockGeometry(
  occurrence: BoundedOccurrence,
  bounds: GridBounds,
  pixelsPerHour: number,
  minHeight = 0,
): BlockGeometry {
  const from = minutesFromTime(occurrence.starts_at_local);
  const rawEnd = from + occurrence.duration_minutes;
  const to = Math.min(rawEnd, MINUTES_PER_DAY);
  const top = offsetForMinutes(from, bounds, pixelsPerHour);
  const height = ((to - from) / 60) * pixelsPerHour;
  return {
    top,
    height: Math.max(height, minHeight),
    continuesPastMidnight: rawEnd > MINUTES_PER_DAY,
  };
}

export type LaidOut<Item> = {
  item: Item;
  /** Which side-by-side column this block takes, 0-based. */
  lane: number;
  /** How many the cluster it overlaps needs, so every block in it aligns. */
  lanes: number;
};

/**
 * Overlapping seva at the same hour must both be visible — the temple's words.
 *
 * Blocks that overlap are packed into side-by-side lanes and every block in one
 * run of overlaps is given the same lane count, so two seva at 5pm are two half
 * width blocks rather than one hiding the other. Ordered by start then by name,
 * so the same week always draws the same way.
 */
export function layOutDay<Item extends BoundedOccurrence>(
  occurrences: readonly Item[],
): Array<LaidOut<Item>> {
  const sorted = [...occurrences].sort((left, right) => {
    const byStart =
      minutesFromTime(left.starts_at_local) - minutesFromTime(right.starts_at_local);
    if (byStart !== 0) return byStart;
    return right.duration_minutes - left.duration_minutes;
  });

  const placed: Array<{ item: Item; lane: number; end: number }> = [];
  const results: Array<LaidOut<Item>> = [];
  // A cluster is a run of blocks joined by overlap; it ends the moment one
  // starts after everything before it has finished.
  let clusterStart = 0;
  let clusterEnd = -1;
  let laneEnds: number[] = [];

  const closeCluster = () => {
    const lanes = Math.max(laneEnds.length, 1);
    for (let index = clusterStart; index < placed.length; index += 1) {
      results.push({ item: placed[index].item, lane: placed[index].lane, lanes });
    }
    clusterStart = placed.length;
    laneEnds = [];
    clusterEnd = -1;
  };

  for (const occurrence of sorted) {
    const from = minutesFromTime(occurrence.starts_at_local);
    const to = Math.min(
      from + occurrence.duration_minutes,
      MINUTES_PER_DAY,
    );
    if (laneEnds.length && from >= clusterEnd) closeCluster();

    let lane = laneEnds.findIndex((laneEnd) => laneEnd <= from);
    if (lane === -1) {
      lane = laneEnds.length;
      laneEnds.push(to);
    } else {
      laneEnds[lane] = to;
    }
    placed.push({ item: occurrence, lane, end: to });
    clusterEnd = Math.max(clusterEnd, to);
  }
  if (placed.length > clusterStart) closeCluster();

  return results;
}

/**
 * The half hour a tap on empty grid landed in.
 *
 * Snapped down, never up: tapping just below the 5 o'clock line means five
 * o'clock, and rounding to the nearest would post at 4:30 for a tap the devotee
 * aimed at 5.
 */
export function slotMinutesFromOffset(
  offsetY: number,
  bounds: GridBounds,
  pixelsPerHour: number,
  snapMinutes = SLOT_SNAP_MINUTES,
): number {
  const raw = bounds.startMinutes + (offsetY / pixelsPerHour) * 60;
  const clamped = Math.min(Math.max(raw, bounds.startMinutes), bounds.endMinutes - snapMinutes);
  return Math.floor(clamped / snapMinutes) * snapMinutes;
}

/**
 * A date key as a device-local Date, for handing to a picker.
 *
 * Noon, so that no device's zone can round the day backwards, and the calendar
 * fields — which is all a picker reads — are the temple's date.
 */
export function dateFromKey(dateKey: string): Date {
  const [year, month, day] = dateKey.split("-").map(Number);
  return new Date(year, (month ?? 1) - 1, day ?? 1, 12);
}

/** "16:30:00" as a device-local Date, for the same reason. */
export function timeFromValue(value: string): Date {
  const [hour = 0, minute = 0] = value.split(":").map(Number);
  const date = new Date();
  date.setHours(hour, minute, 0, 0);
  return date;
}
