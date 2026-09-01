/**
 * Shapes returned by the birthday prompt migration
 * (202608040053_birthday_prompts.sql).
 *
 * A birthday is a private nudge to the President and the Tech Admin, not a
 * broadcast: the server tells only them whose birthday it is, and offers them
 * wording to edit. Nothing here posts anything.
 */

/**
 * One row of `todays_birthdays()`.
 *
 * An empty list does not mean the temple has no birthdays today — the function
 * returns an empty set, not an error, to anybody without `app.view_all`, so it
 * can also mean the reader is not allowed to know.
 */
/**
 * One row of `upcoming_birthdays(days)` — the same fact as TodaysBirthday over
 * a window, so a screen can show the week rather than only this morning.
 */
export type UpcomingBirthday = {
  devotee_id: string;
  name: string | null;
  photo_url: string | null;
  /** "YYYY-MM-DD". */
  date_of_birth: string;
  /** Null where the recorded year of birth would make the number nonsense. */
  turning_age: number | null;
  /** The day it is greeted on, which is not the birthday in a leap year. */
  celebrated_on: string;
  /** 0 for today. The server decides this, so it cannot disagree with today. */
  days_away: number;
};

export type TodaysBirthday = {
  devotee_id: string;
  name: string | null;
  photo_url: string | null;
  /** "YYYY-MM-DD". */
  date_of_birth: string;
  /** Null where the recorded year of birth would make the number nonsense. */
  turning_age: number | null;
};

/**
 * What `suggested_birthday_announcement()` hands back. The temple's voice
 * lives in the database so that changing it is a migration rather than an app
 * release; this is only ever a starting point for a person to edit.
 */
export type SuggestedAnnouncement = {
  title: string;
  body: string;
  /**
   * The birthday devotee's own photograph, as users.photo_url holds it — a
   * reference into a private bucket rather than a fetchable URL, signed by the
   * app before it renders. Null where they have not added one.
   */
  image_url: string | null;
};

/**
 * The suggestion, in the shape the announcement composer opens with.
 *
 * Exists because the two are nearly the same object and differ in exactly one
 * place: the server says `image_url` and the composer wants `imageUrl`. Both
 * call sites used to hand the suggestion straight over, which TypeScript
 * accepts — the extra property is allowed and `imageUrl` is optional — and the
 * devotee's photograph was silently dropped from their own birthday notice.
 * One function, so there is one place for that to be right.
 */
export function birthdayAnnouncementPrefill(suggestion: SuggestedAnnouncement): {
  title: string;
  body: string;
  imageUrl: string | null;
  kind: "birthday";
} {
  return {
    title: suggestion.title,
    body: suggestion.body,
    imageUrl: suggestion.image_url,
    // Carried so the card can draw the frame. Not inferred from the title
    // later, because the President is invited to rewrite that.
    kind: "birthday",
  };
}
