import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect } from "react";

import { getSupabaseClient } from "../../lib/supabase";
import {
  clearAppNotifications,
  deleteAppNotification,
  fetchAppNotifications,
  markAppNotificationsRead,
} from "./api";
import type { AppNotificationRow } from "./types";

export const appNotificationKeys = {
  all: ["app-notifications"] as const,
  list: (userId: string | null) =>
    ["app-notifications", "list", userId] as const,
};

export function useAppNotifications(userId: string | null) {
  return useQuery({
    queryKey: appNotificationKeys.list(userId),
    queryFn: fetchAppNotifications,
    enabled: Boolean(userId),
    // Realtime is immediate; polling only repairs a socket interruption.
    refetchInterval: 5 * 60_000,
  });
}

export function useMarkAppNotificationsRead(userId: string | null) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: () => markAppNotificationsRead(userId!),
    onSuccess: () =>
      queryClient.invalidateQueries({ queryKey: appNotificationKeys.all }),
  });
}

export function useDeleteAppNotification() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: deleteAppNotification,
    onSuccess: () =>
      queryClient.invalidateQueries({ queryKey: appNotificationKeys.all }),
  });
}

export function useClearAppNotifications(userId: string | null) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: () => clearAppNotifications(userId!),
    onSuccess: () =>
      queryClient.invalidateQueries({ queryKey: appNotificationKeys.all }),
  });
}

export function useAppNotificationsRealtime() {
  const queryClient = useQueryClient();

  useEffect(() => {
    const channel = getSupabaseClient()
      .channel("app-notifications-live")
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "app_notifications" },
        (payload) => {
          void queryClient.invalidateQueries({
            queryKey: appNotificationKeys.all,
          });

          if (payload.eventType !== "INSERT") return;
          const row = payload.new as Partial<AppNotificationRow>;
          const kind = row.kind;
          if (!kind) return;

          // The notification is also a precise, user-scoped signal that a
          // feature changed. Refresh that cache instead of polling every
          // dashboard whenever a tab receives focus.
          if (kind === "message_received") {
            void queryClient.invalidateQueries({
              queryKey: ["messaging", "conversations"],
            });
          } else if (
            kind === "sanga_message_received" ||
            kind.startsWith("sanga_")
          ) {
            void queryClient.invalidateQueries({ queryKey: ["sanga"] });
          } else if (kind.startsWith("announcement_")) {
            void queryClient.invalidateQueries({
              queryKey: ["announcements"],
            });
          } else if (kind.startsWith("access_")) {
            void queryClient.invalidateQueries({ queryKey: ["access"] });
          }
        },
      )
      .subscribe();

    return () => {
      void getSupabaseClient().removeChannel(channel);
    };
  }, [queryClient]);
}
