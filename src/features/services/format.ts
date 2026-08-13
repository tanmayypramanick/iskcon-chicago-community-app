import {
  chicagoWallClockToInstant,
  getChicagoDateKey,
} from "../../lib/chicagoDate";

export const weekdayNames = [
  "Sunday",
  "Monday",
  "Tuesday",
  "Wednesday",
  "Thursday",
  "Friday",
  "Saturday",
] as const;

export function formatWeekday(dayOfWeek: number) {
  return weekdayNames[dayOfWeek] ?? "Weekly";
}

export function formatWeekdayList(daysOfWeek: number[]) {
  const names = [...new Set(daysOfWeek)].sort().map(formatWeekday);
  if (names.length <= 1) return names[0] ?? "selected days";
  if (names.length === 2) return `${names[0]} and ${names[1]}`;
  return `${names.slice(0, -1).join(", ")} and ${names.at(-1)}`;
}

export function formatServiceDate(dateKey: string) {
  const [year, month, day] = dateKey.split("-").map(Number);
  const date = new Date(year, month - 1, day, 12);
  return new Intl.DateTimeFormat("en-US", {
    weekday: "short",
    month: "short",
    day: "numeric",
  }).format(date);
}

export function formatServiceTime(time: string) {
  const [hour, minute] = time.split(":").map(Number);
  const date = new Date(2000, 0, 1, hour, minute);
  return new Intl.DateTimeFormat("en-US", {
    hour: "numeric",
    minute: "2-digit",
  }).format(date);
}

export function formatDuration(minutes: number) {
  if (minutes < 60) return `${minutes} min`;
  const hours = Math.floor(minutes / 60);
  const remaining = minutes % 60;
  return remaining ? `${hours} hr ${remaining} min` : `${hours} hr`;
}

/**
 * A date picker hands back a device-local Date whose calendar fields are what
 * the devotee actually tapped. Those fields are the date they mean at the
 * temple, so they are used directly rather than converted — converting would
 * shift the day for anyone whose phone is not on Chicago time.
 */
export function dateToKey(date: Date) {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

export function timeToDatabaseValue(date: Date) {
  const hour = String(date.getHours()).padStart(2, "0");
  const minute = String(date.getMinutes()).padStart(2, "0");
  return `${hour}:${minute}:00`;
}

export function serviceDateTimeValue(dateKey: string, time: string) {
  return `${dateKey}T${time.slice(0, 8)}`;
}

/**
 * Compared against the temple's calendar day, never the device's. `now` is
 * accepted so every caller judges "upcoming" against one clock — mixing an
 * injected clock for the end time with the real one for the date made the
 * answer depend on when you asked.
 */
export function isUpcomingService(dateKey: string, now = new Date()) {
  return dateKey >= getChicagoDateKey(now);
}

/** The instant a dated seva begins, on the temple's clock. */
export function serviceStartInstant(service: {
  date: string;
  start_time: string;
}) {
  return chicagoWallClockToInstant(service.date, service.start_time);
}

/** The instant a dated seva finishes, on the temple's clock. */
export function serviceEndInstant(service: {
  date: string;
  start_time: string;
  duration_minutes: number;
}) {
  const start = serviceStartInstant(service);
  return new Date(start.getTime() + service.duration_minutes * 60_000);
}

/**
 * Whether a seva has begun.
 *
 * This is the gate for *attendance*, and only that: whoever is running a seva
 * marks devotees in as they arrive, and "happening now" reads those marks to
 * say who is really there. It is deliberately not the gate for completion —
 * the temple was explicit that a seva may only be marked completed once it is
 * over, so `hasServiceFinished` decides that.
 *
 * Callers must pass the ticking `now` from `useNow`, not `new Date()` captured
 * at render: a seva that starts in five minutes has to gain its control on its
 * own, and React Query hands back the same rows on refetch so nothing else
 * would re-render at that moment.
 */
export function hasServiceStarted(
  service: { date: string; start_time: string },
  now = new Date(),
) {
  return serviceStartInstant(service).getTime() <= now.getTime();
}

/**
 * Whether a seva is over. The date alone is not enough: an 11:00 AM seva that
 * runs an hour is finished by lunchtime, and listing it as upcoming for the
 * rest of the day tells a devotee they still have somewhere to be.
 *
 * This is also the completion gate, in the temple's own words: "after the seva
 * has been done and the time has passed, only then can anyone mark this seva
 * completed." Gating on the start instead let a 9:00–10:00 seva be marked
 * completed at 9:01, by which point nothing had been done.
 */
export function hasServiceFinished(
  service: { date: string; start_time: string; duration_minutes: number },
  now = new Date(),
) {
  return serviceEndInstant(service).getTime() <= now.getTime();
}

/**
 * The length `propose_service_offer_alternative` actually stores. The RPC
 * rounds every suggestion up onto the temple's 30-minute grid
 * (`greatest(30, ceil(minutes / 30) * 30)`), so a screen that offers
 * five-minute precision was quietly committing a devotee who said
 * "9:00 to 9:45" to an hour. The rule is repeated here so the time the screen
 * shows and the time the database keeps are the same time.
 */
export function storedSuggestionDuration(minutes: number) {
  return Math.max(30, Math.ceil(minutes / 30) * 30);
}

export function getDefaultServiceTime() {
  const date = new Date();
  const minutes = date.getMinutes();
  date.setMinutes(minutes < 30 ? 30 : 60, 0, 0);
  return date;
}

/**
 * Supabase returns PostgrestError as a plain object, not an Error instance, so
 * an `instanceof Error` guard silently swallows every server message. This
 * accepts anything with a readable message and only falls back when there is
 * genuinely nothing to show.
 */
export function errorMessage(error: unknown, fallback: string) {
  if (!error) return null;

  const readable = readErrorText(error);
  if (!readable) return fallback;
  // A dropped connection is not a seva problem, and the platform wording for
  // it ("Network request failed", "The Internet connection appears to be
  // offline") tells a devotee nothing they can act on.
  if (isConnectionProblem(readable)) {
    return "Could not reach the temple server. Check your connection and try again.";
  }
  return readable;
}

function readErrorText(error: unknown): string | null {
  if (error instanceof Error) return error.message.trim() || null;
  if (typeof error === "string") return error.trim() || null;
  if (typeof error === "object") {
    const candidate = error as { message?: unknown; details?: unknown };
    if (typeof candidate.message === "string" && candidate.message.trim()) {
      return candidate.message.trim();
    }
    if (typeof candidate.details === "string" && candidate.details.trim()) {
      return candidate.details.trim();
    }
  }
  return null;
}

/** True for the transport failures that say nothing about the request. */
export function isConnectionProblem(error: unknown) {
  const text = (
    typeof error === "string" ? error : (readErrorText(error) ?? "")
  ).toLowerCase();
  if (!text) return false;
  return (
    text.includes("network request failed") ||
    text.includes("connection appears to be offline") ||
    text.includes("network connection was lost") ||
    text.includes("failed to fetch") ||
    text.includes("load failed") ||
    text.includes("timeout") ||
    text.includes("aborted")
  );
}
