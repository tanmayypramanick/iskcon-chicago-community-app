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
};
