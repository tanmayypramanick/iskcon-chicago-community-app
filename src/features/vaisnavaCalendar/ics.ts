import type {
  ParsedVaisnavaCalendar,
  ParsedVaisnavaEvent,
  VaisnavaEventKind,
} from "./types";

const MAX_FILE_BYTES = 2 * 1024 * 1024;

function unescapeIcsText(value: string) {
  return value
    .replace(/\\n/gi, "\n")
    .replace(/\\,/g, ",")
    .replace(/\\;/g, ";")
    .replace(/\\'/g, "'")
    .replace(/\\\\/g, "\\")
    .trim();
}

function property(lines: string[], name: string) {
  const line = lines.find(
    (candidate) => candidate.slice(0, candidate.indexOf(":")).split(";")[0] === name,
  );
  if (!line) return "";
  return unescapeIcsText(line.slice(line.indexOf(":") + 1));
}

export function classifyVaisnavaEvent(title: string): VaisnavaEventKind {
  const value = title.toLocaleLowerCase();
  if (value.startsWith("break fast")) return "parana";
  if (value.startsWith("fasting") || value.includes(" fast till")) return "fasting";
  if (value.includes("ekadasi") || value.includes("ekadashi") || value.includes("mahadvadasi")) {
    return "ekadasi";
  }
  if (value.includes("-- appearance") || value.endsWith(" appearance")) {
    return "appearance";
  }
  if (value.includes("-- disappearance") || value.endsWith(" disappearance")) {
    return "disappearance";
  }
  if (
    value.includes("festival") ||
    value.includes("janmastami") ||
    value.includes("gaura purnima") ||
    value.includes("rama-navami") ||
    value.includes("ratha yatra") ||
    value.includes("govardhana puja") ||
    value.includes("dipavali") ||
    value.includes("diwali")
  ) {
    return "festival";
  }
  return "observance";
}

function dateKey(raw: string) {
  const compact = raw.slice(0, 8);
  if (!/^[0-9]{8}$/.test(compact)) return null;
  const year = Number(compact.slice(0, 4));
  const month = Number(compact.slice(4, 6));
  const day = Number(compact.slice(6, 8));
  const date = new Date(Date.UTC(year, month - 1, day));
  if (
    date.getUTCFullYear() !== year ||
    date.getUTCMonth() !== month - 1 ||
    date.getUTCDate() !== day
  ) {
    return null;
  }
  return `${compact.slice(0, 4)}-${compact.slice(4, 6)}-${compact.slice(6, 8)}`;
}

/** Parse the all-day VEVENT records produced by GCal/Vaiṣṇava ICS exports. */
export function parseVaisnavaIcs(text: string): ParsedVaisnavaCalendar {
  if (!text.includes("BEGIN:VCALENDAR")) {
    throw new Error("Choose a valid Vaiṣṇava Calendar ICS file.");
  }
  if (new TextEncoder().encode(text).length > MAX_FILE_BYTES) {
    throw new Error("The calendar file must be smaller than 2 MB.");
  }

  // RFC 5545 folds long properties onto a following line beginning with one
  // space or tab. Unfold before finding VEVENT boundaries.
  const unfolded = text.replace(/\r?\n[ \t]/g, "");
  const blocks = unfolded.match(/BEGIN:VEVENT[\s\S]*?END:VEVENT/g) ?? [];
  const events: ParsedVaisnavaEvent[] = [];
  const seen = new Set<string>();

  for (const block of blocks) {
    const lines = block.split(/\r?\n/);
    const date = dateKey(property(lines, "DTSTART"));
    const title = property(lines, "SUMMARY");
    if (!date || !title) continue;
    const sourceUid = property(lines, "UID") || `${date}-${title}`;
    const dedupeKey = `${date}|${sourceUid}`;
    if (seen.has(dedupeKey)) continue;
    seen.add(dedupeKey);
    events.push({
      sourceUid,
      date,
      title,
      description: property(lines, "DESCRIPTION"),
      kind: classifyVaisnavaEvent(title),
    });
  }

  if (events.length < 10) {
    throw new Error("This file does not contain a complete yearly calendar.");
  }
  if (events.length > 1000) {
    throw new Error("This calendar contains too many events.");
  }

  const years = [...new Set(events.map((event) => Number(event.date.slice(0, 4))))];
  if (years.length !== 1) {
    throw new Error("Upload one calendar year at a time.");
  }

  events.sort(
    (left, right) =>
      left.date.localeCompare(right.date) || left.title.localeCompare(right.title),
  );
  return { year: years[0], events };
}
