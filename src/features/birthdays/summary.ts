import type { UpcomingBirthday } from "./types";

/**
 * What the birthday button on the noticeboard says.
 *
 * Pure, and separate from the component, because the wording is the part with
 * rules in it: singular against plural, today against later, and the case
 * where there is nothing to say at all and the button should not be drawn.
 * A component cannot be asked those questions in a test without a renderer.
 */
export type BirthdaySummary = {
  /** The line in display type. */
  title: string;
  /** The quieter line under it. */
  detail: string;
  /** Whether anybody is celebrating today, which is what makes it marigold. */
  today: boolean;
  /** How many are celebrating today. */
  todayCount: number;
};

const nameOf = (birthday: UpcomingBirthday) =>
  birthday.name?.trim() || "A devotee";

/** "in 1 day" / "in 5 days" / "tomorrow". */
function whenPhrase(days: number) {
  if (days <= 0) return "today";
  if (days === 1) return "tomorrow";
  return `in ${days} days`;
}

/**
 * Null when there is nothing worth a button: no birthday today and none
 * coming up inside the window the caller asked for. Drawing an empty card on
 * the noticeboard every day of the year is worse than drawing nothing.
 */
export function birthdaySummary(
  rows: readonly UpcomingBirthday[],
): BirthdaySummary | null {
  if (!rows.length) return null;

  const today = rows.filter((row) => row.days_away === 0);

  if (today.length) {
    return {
      title:
        today.length === 1
          ? `${nameOf(today[0])}’s birthday is today`
          : `${today.length} birthdays today`,
      // The question is the point of the card: the temple decides, the app
      // does not post anything on its own.
      detail: "Post an announcement?",
      today: true,
      todayCount: today.length,
    };
  }

  // Nobody today. The next one is still worth knowing about, quietly.
  const next = rows[0];
  return {
    title: "Upcoming birthdays",
    detail: `${nameOf(next)} ${whenPhrase(next.days_away)}`,
    today: false,
    todayCount: 0,
  };
}

/**
 * The heading for one devotee's row in the full list.
 *
 * "Today" rather than a date when it is today, because a date a devotee has to
 * compare against their own sense of the day is a small tax on every reading.
 */
export function birthdayRowWhen(birthday: UpcomingBirthday): string {
  const age =
    birthday.turning_age !== null ? `Turning ${birthday.turning_age}` : null;
  const when =
    birthday.days_away === 0
      ? "Today"
      : birthday.days_away === 1
        ? "Tomorrow"
        : `In ${birthday.days_away} days`;
  return age ? `${when} · ${age}` : when;
}
