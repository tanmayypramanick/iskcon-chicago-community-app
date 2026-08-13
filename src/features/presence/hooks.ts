import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect } from "react";

import { getChicagoDateKey } from "../../lib/chicagoDate";
import { getSupabaseClient } from "../../lib/supabase";
import { fetchTemplePresence, setMyTemplePresence } from "./api";
import type { TemplePresenceDashboard, TemplePresenceSource } from "./types";

export const templePresenceKeys = {
  all: ["temple-presence"] as const,
  dashboard: (userId: string | null) =>
    ["temple-presence", "dashboard", userId] as const,
};

export function useTemplePresence(userId: string | null) {
  return useQuery({
    queryKey: templePresenceKeys.dashboard(userId),
    queryFn: () => fetchTemplePresence(userId!),
    enabled: Boolean(userId),
    // Presence changes arrive over realtime; this is only a reconnect safety
    // net, so it does not need to run every 20 seconds.
    refetchInterval: 2 * 60_000,
  });
}

export function useSetTemplePresence(userId: string | null) {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({
      isAtTemple,
      source = "manual",
    }: {
      isAtTemple: boolean;
      source?: TemplePresenceSource;
      /** Used to place the devotee in the shared list before the server replies. */
      selfName?: string;
      selfPhotoUrl?: string | null;
    }) => setMyTemplePresence(isAtTemple, source),
    // The switch must move the instant it is touched. The optimistic value
    // below is what the Home screen renders; the server reply and the realtime
    // event only ever confirm it.
    onMutate: ({ isAtTemple, source = "manual", selfName, selfPhotoUrl }) => {
      if (!userId) return undefined;
      const key = templePresenceKeys.dashboard(userId);

      // Deliberately synchronous, and deliberately before cancelQueries.
      // `await cancelQueries()` waits on any in-flight fetch for this key, and
      // Supabase requests are not abortable here, so awaiting it queued the
      // optimistic write behind whatever was already on the wire — the switch
      // appeared frozen for as long as that request took.
      const previous = queryClient.getQueryData<TemplePresenceDashboard>(key);
      if (!previous) {
        void queryClient.cancelQueries({ queryKey: key });
        return { previous };
      }

      const now = new Date().toISOString();
      const withoutSelf = previous.people.filter(
        (person) => person.user_id !== userId,
      );
      const existingSelf = previous.people.find(
        (person) => person.user_id === userId,
      );

      queryClient.setQueryData<TemplePresenceDashboard>(key, {
        current: {
          user_id: userId,
          is_at_temple: isAtTemple,
          presence_date: getChicagoDateKey(),
          source,
          checked_in_at: isAtTemple
            ? (previous.current?.checked_in_at ?? now)
            : (previous.current?.checked_in_at ?? null),
          checked_out_at: isAtTemple ? null : now,
          updated_at: now,
        },
        // Checking in adds the devotee to "At the temple today" immediately,
        // rather than waiting for the next fetch to reveal them.
        people: isAtTemple
          ? [
              ...withoutSelf,
              {
                user_id: userId,
                name: existingSelf?.name ?? selfName ?? "You",
                photo_url: existingSelf?.photo_url ?? selfPhotoUrl ?? null,
                checked_in_at: now,
                updated_at: now,
              },
            ]
          : withoutSelf,
      });

      // Now that the UI is already correct, stop any in-flight fetch from
      // landing on top of the optimistic value. Not awaited.
      void queryClient.cancelQueries({ queryKey: key });

      return { previous };
    },
    // An in-flight fetch started before the tap can still resolve afterwards
    // and overwrite the optimistic row with pre-tap state. cancelQueries is
    // async and cannot be relied on for that, so the server's own returned row
    // is written back here as the authoritative value.
    onSuccess: (row, { selfName, selfPhotoUrl }) => {
      if (!userId || !row) return;
      const key = templePresenceKeys.dashboard(userId);
      queryClient.setQueryData<TemplePresenceDashboard>(key, (existing) => {
        const people = existing?.people ?? [];
        const withoutSelf = people.filter((person) => person.user_id !== userId);
        const existingSelf = people.find((person) => person.user_id === userId);
        return {
          current: row,
          people: row.is_at_temple
            ? [
                ...withoutSelf,
                {
                  user_id: userId,
                  name: existingSelf?.name ?? selfName ?? "You",
                  photo_url: existingSelf?.photo_url ?? selfPhotoUrl ?? null,
                  checked_in_at: row.checked_in_at ?? row.updated_at,
                  updated_at: row.updated_at,
                },
              ]
            : withoutSelf,
        };
      });
    },
    onError: (_error, _variables, context) => {
      if (userId && context?.previous) {
        queryClient.setQueryData(
          templePresenceKeys.dashboard(userId),
          context.previous,
        );
      }
      void queryClient.invalidateQueries({ queryKey: templePresenceKeys.all });
    },
    // No refetch on success: the optimistic row already matches what the server
    // wrote, and the realtime subscription reconciles every device anyway.
    // Refetching here is what made the switch feel like it lagged.
  });
}

export function useTemplePresenceRealtime() {
  const queryClient = useQueryClient();

  useEffect(() => {
    const channel = getSupabaseClient()
      .channel("temple-presence-live")
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "temple_presence" },
        () => {
          void queryClient.invalidateQueries({
            queryKey: templePresenceKeys.all,
          });
        },
      )
      .subscribe();

    return () => {
      void getSupabaseClient().removeChannel(channel);
    };
  }, [queryClient]);
}
