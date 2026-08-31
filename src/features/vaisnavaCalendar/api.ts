import { reportReachability } from "../../lib/connectivity";
import { getSupabaseClient } from "../../lib/supabase";
import { isConnectionProblem } from "../services/format";
import type {
  PublishVaisnavaCalendarInput,
  VaisnavaCalendarEvent,
  VaisnavaCalendarPublication,
} from "./types";

function migrationPending(error: { code?: string } | null) {
  return ["42P01", "PGRST205", "PGRST202", "42883"].includes(error?.code ?? "");
}

export async function fetchVaisnavaCalendarPublications() {
  const { data, error } = await getSupabaseClient()
    .from("vaisnava_calendar_publications")
    .select(
      "calendar_year,city,time_zone,source_name,source_url,file_name,event_count,published_at,published_by",
    )
    .order("calendar_year", { ascending: false });
  reportReachability(!error || !isConnectionProblem(error));
  if (error) {
    if (migrationPending(error)) return [];
    throw error;
  }
  return (data ?? []) as unknown as VaisnavaCalendarPublication[];
}

const EVENT_COLUMNS =
  "id,calendar_year,event_date,title,description,event_kind,source_uid,sort_order,created_at";

/**
 * Migration 0076 gives pāraṇa its own time columns. Asking for a column the
 * database does not have fails the whole select, so the richer shape is tried
 * first and the original one answers when those columns are missing — the
 * screen then reads the window out of the title instead, and a devotee sees no
 * difference.
 */
const EVENT_COLUMNS_WITH_PARANA = `${EVENT_COLUMNS},parana_start_time,parana_end_time,parana_start_reason,parana_end_reason,parana_is_open_ended,parana_clock_marker`;

export async function fetchVaisnavaCalendarEvents(year: number) {
  const supabase = getSupabaseClient();
  const readYear = (columns: string) =>
    supabase
      .from("vaisnava_calendar_events")
      .select(columns)
      .eq("calendar_year", year)
      .order("event_date")
      .order("sort_order");

  let attempt = await readYear(EVENT_COLUMNS_WITH_PARANA);
  // Only a database that has not run 0076 gets a second request. Retrying a
  // timeout or a dropped connection would just spend it twice.
  if (["42703", "PGRST204"].includes(attempt.error?.code ?? "")) {
    attempt = await readYear(EVENT_COLUMNS);
  }

  const { data, error } = attempt;
  reportReachability(!error || !isConnectionProblem(error));
  if (error) {
    if (migrationPending(error)) return [];
    throw error;
  }
  return (data ?? []) as unknown as VaisnavaCalendarEvent[];
}

export async function publishVaisnavaCalendar(
  input: PublishVaisnavaCalendarInput,
) {
  const { data, error } = await getSupabaseClient().rpc(
    "replace_vaisnava_calendar_year",
    {
      p_year: input.year,
      p_source_name: input.sourceName,
      p_source_url: input.sourceUrl,
      p_file_name: input.fileName,
      p_source_file_text: input.sourceFileText,
      p_events: input.events,
    },
  );
  reportReachability(!error || !isConnectionProblem(error));
  if (error) throw error;
  return data as unknown as VaisnavaCalendarPublication;
}
