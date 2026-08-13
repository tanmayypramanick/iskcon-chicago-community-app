import {
  formatDuration,
  formatServiceDate,
  formatServiceTime,
  formatWeekday,
} from "./format";
import type {
  ClosedUnservedRow,
  ClosedUnservedSeva,
  SevaClash,
} from "./types";

/**
 * The words a clash is said in, and nothing that decides anything.
 *
 * The temple was explicit that a clash never blocks: "he is serving 12:00 to
 * 1:30 somewhere but the next seva is from 1:15 which someone asked him — he
 * can finish his first seva quick and then do this seva. If it disables him to
 * assign himself for a 1:15 seva which he can do with just 15 mins collision,
 * then he can't." So every sentence below ends in the devotee's hands, and
 * nothing here returns a boolean anybody could gate a button on.
 */

function pad(value: number) {
  return String(value).padStart(2, "0");
}

/**
 * The end of a proposed window on the temple's wall clock. Kept in wall-clock
 * arithmetic rather than in Date, because the window is a Chicago time the
 * server was asked about and converting it through the device's zone would
 * shift it for anybody outside Chicago.
 */
export function windowEnd(startTime: string, durationMinutes: number) {
  const [hour, minute] = startTime.split(":").map(Number);
  const total = hour * 60 + minute + durationMinutes;
  const withinDay = ((total % 1440) + 1440) % 1440;
  return {
    time: `${pad(Math.floor(withinDay / 60))}:${pad(withinDay % 60)}:00`,
    nextDay: total >= 1440,
  };
}

/**
 * The first date on or after `fromKey` that falls on `weekday`.
 *
 * WHAT A CLASH MEANS FOR A WEEKLY ROTA. A rota repeats without end, so there is
 * no one date to ask about and asking about every date it will ever produce is
 * not a question a form can put. The decision: check the *next* occurrence of
 * each weekday the rota is being given, because the thing a coordinator is
 * actually deciding is whether this devotee's standing commitment collides with
 * another standing commitment — and that is answered on any one occurrence.
 * Whether the answer repeats is then read off the clash itself:
 * `from_weekly_template` means every week, and a dated seva caught this way is
 * reported as the single date it really is.
 */
export function nextDateOnWeekday(fromKey: string, weekday: number) {
  const [year, month, day] = fromKey.split("-").map(Number);
  const date = new Date(year, month - 1, day, 12);
  date.setDate(date.getDate() + ((weekday - date.getDay() + 7) % 7));
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

/** "Thursday", for a date the server answered with. */
export function weekdayNameForDate(dateKey: string) {
  const [year, month, day] = dateKey.split("-").map(Number);
  return formatWeekday(new Date(year, month - 1, day, 12).getDay());
}

/** "1:15 PM to 2:30 PM", or "… to 12:30 AM the next day". */
export function windowText(startTime: string, durationMinutes: number) {
  const end = windowEnd(startTime, durationMinutes);
  const text = `${formatServiceTime(startTime)} to ${formatServiceTime(end.time)}`;
  return end.nextDay ? `${text} the next day` : text;
}

/** When the clashing seva runs, on the temple's clock. */
export function clashWindowText(clash: SevaClash) {
  const text = `${formatServiceTime(clash.starts_at_local)} to ${formatServiceTime(
    clash.ends_at_local,
  )}`;
  return clash.ends_next_day ? `${text} the next day` : text;
}

/**
 * What to call the seva a devotee is already on.
 *
 * `name_visible` false is the server saying this caller may know the devotee is
 * busy and not what with. "another seva" is the whole of what may be said —
 * there is no fallback that could be mistaken for a name.
 */
export function clashSubject(clash: SevaClash) {
  return clash.name_visible && clash.seva_name ? clash.seva_name : "another seva";
}

export type ClashWording = {
  /** Whether the reader is the devotee who would serve, or asking someone else. */
  audience: "self" | "other";
  /** The devotee being asked about. Ignored for "self". */
  devoteeName?: string | null;
  startTime: string;
  durationMinutes: number;
  /**
   * Set when the window is one occurrence of a weekly rota, e.g. "Thursday".
   * A rota repeats, so a clash on it is worded as a standing collision rather
   * than as one date.
   */
  weekday?: string | null;
};

export function clashWarningTitle({ audience, devoteeName }: ClashWording) {
  if (audience === "self") return "You are already serving then";
  return `${devoteeName?.trim() || "That devotee"} is already serving then`;
}

/** "The two overlap by 15 min", or that it swallows the request whole. */
function overlapSentence(clash: SevaClash) {
  if (clash.covers_whole_request) return "That covers the whole of it";
  return `The two overlap by ${formatDuration(clash.overlap_minutes)}`;
}

/**
 * When the clash bites, once a weekly rota is in the question.
 *
 * A rota's real question is whether a standing commitment collides with another
 * standing commitment, and that is answered on any one occurrence. So a weekly
 * clash is reported as repeating, and a dated seva caught under a rota is
 * reported as the single date it actually is.
 */
function clashCadence(clash: SevaClash, weekday: string | null | undefined) {
  if (!weekday) return "";
  if (clash.from_weekly_template) return `, every ${weekday}`;
  return `, on ${formatServiceDate(clash.occurs_on)} only`;
}

/** How the clashing seva's own hours are introduced. */
function servingClause(clash: SevaClash, weekday: string | null | undefined) {
  const subject = clashSubject(clash);
  if (clash.from_weekly_template && weekday) {
    return `${subject} every ${weekday} from ${clashWindowText(clash)}`;
  }
  if (!weekday) return `${subject} from ${clashWindowText(clash)}`;
  return `${subject} on ${formatServiceDate(clash.occurs_on)} from ${clashWindowText(clash)}`;
}

function othersSentence(count: number) {
  if (count < 1) return "";
  return count === 1
    ? " One other seva overlaps this time too."
    : ` ${count} other seva overlap this time too.`;
}

/**
 * The warning itself, in the temple's own shape: "you are serving from xyz to
 * xyz, but this seva is from xyz to xyz — only accept if you manage to serve."
 *
 * Worded from the worst clash, which is the first row `list_seva_clashes`
 * returns; anything else is counted rather than listed, so a devotee reads one
 * sentence and not a table.
 */
export function clashWarningMessage(
  wording: ClashWording,
  clashes: readonly SevaClash[],
) {
  const worst = clashes[0];
  if (!worst) return "";
  const { audience, devoteeName, startTime, durationMinutes, weekday } = wording;
  const who = audience === "self" ? "You are" : `${devoteeName?.trim() || "They"} is`;
  const thisSeva = weekday ? "this weekly seva" : "this seva";
  const closing =
    audience === "self"
      ? "Only accept if you can manage to serve both."
      : "You can still ask — whether they can manage both is theirs to judge.";

  return (
    `${who} serving ${servingClause(worst, weekday)}, ` +
    `but ${thisSeva} is from ${windowText(startTime, durationMinutes)}. ` +
    `${overlapSentence(worst)}${clashCadence(worst, weekday)}. ` +
    `${closing}${othersSentence(clashes.length - 1)}`
  );
}

/**
 * Several devotees at once, for a form that invites more than one. Named rather
 * than described, because the coordinator is about to send each of them an
 * invitation and needs to know which one to think again about.
 */
export function coordinatorClashSummary(
  clashing: ReadonlyArray<{ name: string; clashes: readonly SevaClash[] }>,
  wording: Omit<ClashWording, "audience" | "devoteeName">,
) {
  const withClashes = clashing.filter((entry) => entry.clashes.length > 0);
  if (!withClashes.length) return "";
  if (withClashes.length === 1) {
    return clashWarningMessage(
      { ...wording, audience: "other", devoteeName: withClashes[0].name },
      withClashes[0].clashes,
    );
  }
  const names = withClashes.map((entry) => entry.name);
  const list = `${names.slice(0, -1).join(", ")} and ${names.at(-1)}`;
  return (
    `${list} are already serving something that overlaps ` +
    `${windowText(wording.startTime, wording.durationMinutes)}. ` +
    "You can still ask — whether they can manage both is theirs to judge."
  );
}

export function coordinatorClashTitle(
  clashing: ReadonlyArray<{ name: string; clashes: readonly SevaClash[] }>,
) {
  const withClashes = clashing.filter((entry) => entry.clashes.length > 0);
  if (withClashes.length === 1) {
    return clashWarningTitle({
      audience: "other",
      devoteeName: withClashes[0].name,
      startTime: "00:00:00",
      durationMinutes: 0,
    });
  }
  return `${withClashes.length} devotees are already serving then`;
}

// --- Seva nobody served ---------------------------------------------------

/**
 * `list_seva_closed_unserved` answers one row per place, because what was said
 * about each place is the point. This folds them back into the seva they belong
 * to, in the order the server sent them — newest first.
 */
export function groupClosedUnserved(
  rows: readonly ClosedUnservedRow[],
): ClosedUnservedSeva[] {
  const byInstance = new Map<string, ClosedUnservedSeva>();
  for (const row of rows) {
    const existing = byInstance.get(row.service_instance_id);
    const place = {
      devoteeId: row.devotee_id,
      name: row.devotee_name,
      attendance: row.attendance,
      assignmentStatus: row.assignment_status,
    };
    if (existing) {
      existing.places.push(place);
      continue;
    }
    byInstance.set(row.service_instance_id, {
      serviceInstanceId: row.service_instance_id,
      name: row.seva_name,
      occurredOn: row.occurred_on,
      weekday: row.weekday,
      startedAt: row.started_at_local,
      plannedMinutes: row.planned_minutes,
      isRecurring: row.is_recurring,
      closedAt: row.closed_at,
      places: [place],
    });
  }
  return [...byInstance.values()];
}

/** Why one place did not count, in the words a coordinator recorded. */
export function unservedPlaceReason(place: ClosedUnservedSeva["places"][number]) {
  if (place.attendance === "absent") return "marked absent";
  if (place.attendance === "excused") return "excused";
  if (place.assignmentStatus === "withdrawn") return "stood down";
  if (place.assignmentStatus === "no_show") return "did not arrive";
  return "not recorded as serving";
}
