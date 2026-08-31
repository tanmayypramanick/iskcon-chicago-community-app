import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect } from "react";

import { useChannelSuffix } from "../../lib/channelSuffix";
import { getSupabaseClient } from "../../lib/supabase";
import {
  fetchVaisnavaCalendarEvents,
  fetchVaisnavaCalendarPublications,
  publishVaisnavaCalendar,
} from "./api";

export const vaisnavaCalendarKeys = {
  all: ["vaisnava-calendar"] as const,
  publications: ["vaisnava-calendar", "publications"] as const,
  year: (year: number) => ["vaisnava-calendar", "year", year] as const,
};

export function useVaisnavaCalendarPublications() {
  return useQuery({
    queryKey: vaisnavaCalendarKeys.publications,
    queryFn: fetchVaisnavaCalendarPublications,
  });
}

export function useVaisnavaCalendarEvents(year: number, enabled = true) {
  return useQuery({
    queryKey: vaisnavaCalendarKeys.year(year),
    queryFn: () => fetchVaisnavaCalendarEvents(year),
    enabled: enabled && year > 0,
  });
}

/** Open calendars update immediately after a leader publishes a new file. */
export function useVaisnavaCalendarRealtime(enabled = true) {
  const queryClient = useQueryClient();
  const suffix = useChannelSuffix();

  useEffect(() => {
    if (!enabled) return;
    const channel = getSupabaseClient()
      .channel(`vaisnava-calendar-${suffix}`)
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "vaisnava_calendar_publications" },
        () => void queryClient.invalidateQueries({ queryKey: vaisnavaCalendarKeys.all }),
      )
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "vaisnava_calendar_events" },
        () => void queryClient.invalidateQueries({ queryKey: vaisnavaCalendarKeys.all }),
      )
      .subscribe();
    return () => {
      void getSupabaseClient().removeChannel(channel);
    };
  }, [enabled, queryClient, suffix]);
}

export function usePublishVaisnavaCalendar() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: publishVaisnavaCalendar,
    onSuccess: () =>
      queryClient.invalidateQueries({ queryKey: vaisnavaCalendarKeys.all }),
  });
}
