import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect } from "react";

import { useChannelSuffix } from "../../lib/channelSuffix";
import { getSupabaseClient } from "../../lib/supabase";
import {
  fetchSevaSchedule,
  fetchTempleProgramme,
  fetchTimetableHours,
} from "./api";

export const scheduleKeys = {
  all: ["seva-schedule"] as const,
  /**
   * Keyed on who is being read about as well as the window: the temple's week
   * and one devotee's week are different answers to different questions, and
   * one must never be served from the cache for the other.
   */
  window: (from: string, to: string, devoteeId: string | null) =>
    ["seva-schedule", "window", from, to, devoteeId] as const,
  programme: (from: string, to: string) =>
    ["seva-schedule", "programme", from, to] as const,
  hours: () => ["seva-schedule", "hours"] as const,
};

export function useSevaSchedule(
  from: string,
  to: string,
  devoteeId: string | null,
  enabled = true,
) {
  return useQuery({
    queryKey: scheduleKeys.window(from, to, devoteeId),
    queryFn: () => fetchSevaSchedule(from, to, devoteeId),
    enabled,
    // A permission raise is not a transient failure. Retrying it three times
    // only delays the honest answer by a second and a half.
    retry: false,
  });
}

export function useTempleProgramme(from: string, to: string, enabled = true) {
  return useQuery({
    queryKey: scheduleKeys.programme(from, to),
    queryFn: () => fetchTempleProgramme(from, to),
    enabled,
    // The temple's daily rhythm changes about once a year.
    staleTime: 60 * 60_000,
    retry: false,
  });
}

export function useTimetableHours() {
  return useQuery({
    queryKey: scheduleKeys.hours(),
    queryFn: fetchTimetableHours,
    staleTime: 60 * 60_000,
  });
}

/**
 * The timetable, live.
 *
 * The temple's requirement is plain: "if someone swapped, their name will be
 * there; if the service is removed, it gets removed." Every table below can do
 * one of those to a block on screen — an instance appearing or being cancelled,
 * an assignment taken or withdrawn, a coverage plan accepted (which is the swap
 * itself, applied server-side), a weekly template changed, an exception opened.
 *
 * Invalidation rather than patching, because what arrives is a raw table row
 * with no name, no roster and no answer to "does this fall in the week on
 * screen" — `list_seva_schedule` has to be asked again, and it is one call for
 * the whole grid.
 *
 * The channel name carries a suffix. `useServiceRealtime` holds a fixed name,
 * so if this reused it the two would collide the moment the timetable opened
 * over the Seva tab — the exact bug that has bitten this app before.
 */
export function useScheduleRealtime(enabled = true) {
  const queryClient = useQueryClient();
  const suffix = useChannelSuffix();

  useEffect(() => {
    if (!enabled) return;
    // One coordinator action fans out across several tables at once. A short
    // window collapses the burst into a single refetch of the window on screen.
    let pending: ReturnType<typeof setTimeout> | null = null;
    const refresh = () => {
      if (pending) return;
      pending = setTimeout(() => {
        pending = null;
        void queryClient.invalidateQueries({ queryKey: scheduleKeys.all });
      }, 220);
    };

    const tables = [
      "service_instances",
      "service_assignments",
      "service_coverage_plans",
      "service_templates",
      "service_template_assignees",
      "service_exceptions",
      "service_offers",
    ];

    let channel = getSupabaseClient().channel(`seva-timetable-live-${suffix}`);
    for (const table of tables) {
      channel = channel.on(
        "postgres_changes",
        { event: "*", schema: "public", table },
        refresh,
      );
    }
    const subscribed = channel.subscribe();

    return () => {
      if (pending) clearTimeout(pending);
      void getSupabaseClient().removeChannel(subscribed);
    };
  }, [enabled, queryClient, suffix]);
}
