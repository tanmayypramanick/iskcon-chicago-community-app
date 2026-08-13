import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect } from "react";

import { getSupabaseClient } from "../../lib/supabase";
import {
  clearAppNotifications,
  deleteAppNotification,
  fetchAppNotifications,
  markAppNotificationsRead,
} from "./api";

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
    refetchInterval: 20_000,
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
        () => {
          void queryClient.invalidateQueries({
            queryKey: appNotificationKeys.all,
          });
        },
      )
      .subscribe();

    return () => {
      void getSupabaseClient().removeChannel(channel);
    };
  }, [queryClient]);
}
