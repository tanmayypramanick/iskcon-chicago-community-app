import { getSupabaseClient } from "../../lib/supabase";
import type { AppNotificationRow } from "./types";

export async function fetchAppNotifications() {
  const { data, error } = await getSupabaseClient()
    .from("app_notifications")
    .select("id,user_id,kind,title,body,data,created_at,read_at")
    .order("created_at", { ascending: false })
    .limit(100)
    .returns<AppNotificationRow[]>();

  if (error) throw error;
  return data ?? [];
}

export async function markAppNotificationsRead(userId: string) {
  const { error } = await getSupabaseClient()
    .from("app_notifications")
    .update({ read_at: new Date().toISOString() })
    .eq("user_id", userId)
    .is("read_at", null);

  if (error) throw error;
}

export async function deleteAppNotification(notificationId: string) {
  const { error } = await getSupabaseClient()
    .from("app_notifications")
    .delete()
    .eq("id", notificationId);

  if (error) throw error;
}

export async function clearAppNotifications(userId: string) {
  const { error } = await getSupabaseClient()
    .from("app_notifications")
    .delete()
    .eq("user_id", userId);

  if (error) throw error;
}
