export type SevaEntryMode = "plan" | "completed";

const HOUR_MS = 60 * 60 * 1000;
const DAY_MS = 24 * HOUR_MS;

/**
 * The client gives immediate, specific guidance; the database repeats these
 * boundaries because device clocks and clients are never trusted for access
 * or data integrity.
 */
export function validateSevaEntryWindow(
  mode: SevaEntryMode,
  startAt: Date,
  endAt: Date,
  now = new Date(),
) {
  const duration = endAt.getTime() - startAt.getTime();
  if (duration <= 0 || duration > 12 * HOUR_MS) {
    return "Choose an end time within 12 hours of the start.";
  }

  if (mode === "completed") {
    if (endAt.getTime() > now.getTime()) {
      return "Completed seva must end before the current time.";
    }
    if (startAt.getTime() < now.getTime() - 180 * DAY_MS) {
      return "Completed seva can be logged for up to 180 days.";
    }
    return null;
  }

  if (endAt.getTime() <= now.getTime()) {
    return "That seva has already finished. Use Log your seva instead.";
  }
  if (startAt.getTime() > now.getTime() + 180 * DAY_MS) {
    return "Plan seva within the next six months.";
  }
  return null;
}
