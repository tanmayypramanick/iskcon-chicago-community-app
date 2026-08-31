export type VaisnavaEventKind =
  | "ekadasi"
  | "parana"
  | "fasting"
  | "festival"
  | "appearance"
  | "disappearance"
  | "observance"
  | "other";

export type VaisnavaCalendarEvent = {
  id: string;
  calendar_year: number;
  event_date: string;
  title: string;
  description: string | null;
  event_kind: VaisnavaEventKind;
  source_uid: string;
  sort_order: number;
  created_at: string;
  /**
   * The pāraṇa window as data rather than as a sentence, added by migration
   * 0076. Optional because a database that has not run it returns rows without
   * these columns, and because they are null on every event that is not a
   * pāraṇa. src/features/vaisnavaCalendar/parana.ts falls back to the title.
   */
  parana_start_time?: string | null;
  parana_end_time?: string | null;
  parana_start_reason?: string | null;
  parana_end_reason?: string | null;
  parana_is_open_ended?: boolean | null;
  /** The source's own "LT" / "DST" marker, kept for provenance. */
  parana_clock_marker?: string | null;
};

export type VaisnavaCalendarPublication = {
  calendar_year: number;
  city: string;
  time_zone: string;
  source_name: string;
  source_url: string | null;
  file_name: string;
  event_count: number;
  published_at: string;
  published_by: string | null;
};

/** The small, validated shape sent to the atomic yearly-import RPC. */
export type ParsedVaisnavaEvent = {
  sourceUid: string;
  date: string;
  title: string;
  description: string;
  kind: VaisnavaEventKind;
};

export type ParsedVaisnavaCalendar = {
  year: number;
  events: ParsedVaisnavaEvent[];
};

export type PublishVaisnavaCalendarInput = ParsedVaisnavaCalendar & {
  sourceName: string;
  sourceUrl: string | null;
  fileName: string;
  sourceFileText: string;
};
