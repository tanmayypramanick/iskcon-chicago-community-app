import * as Notifications from "expo-notifications";
import Constants from "expo-constants";
import { Platform } from "react-native";

import { getSupabaseClient } from "../lib/supabase";
import {
  type AppNotification,
  type AppNotificationKind,
  usePrototypeSession,
} from "../store/usePrototypeSession";
import {
  recordTempleArrivalReminder,
  templeCheckInReminderCopy,
} from "./notificationInbox";

const TEMPLE_REMINDERS_CHANNEL = "temple-reminders";
const COMMUNITY_UPDATES_CHANNEL = "community-updates";

/**
 * One identifier, reused for the life of the app, so the daily nudge below can
 * be replaced rather than piled up: scheduling runs on every launch, and
 * without a fixed identifier a devotee who opened the app ten times would be
 * reminded ten times at four o'clock.
 */
export const DAILY_TEMPLE_CHECK_IN_REMINDER_ID = "temple-check-in-daily";

/** Four in the afternoon, local time — late enough to have arrived. */
export const DAILY_TEMPLE_CHECK_IN_REMINDER_HOUR = 16;
export const DAILY_TEMPLE_CHECK_IN_REMINDER_MINUTE = 0;

Notifications.setNotificationHandler({
  handleNotification: async () => ({
    shouldPlaySound: true,
    shouldSetBadge: false,
    shouldShowBanner: true,
    shouldShowList: true,
  }),
});

function notificationsAreAllowed(
  permission: Notifications.NotificationPermissionsStatus,
) {
  return (
    permission.granted ||
    permission.ios?.status ===
      Notifications.IosAuthorizationStatus.PROVISIONAL ||
    permission.ios?.status === Notifications.IosAuthorizationStatus.AUTHORIZED
  );
}

export type PushRegistration = { ok: true } | { ok: false; reason: string };

/**
 * The last token this app run successfully stored, so an unchanged token is
 * not written again on every retry.
 */
let registeredToken: string | null = null;

/**
 * Records this device against the signed-in devotee so the server can push to
 * it. Every failure is described rather than swallowed: a device that silently
 * never registers looks exactly like a temple with nothing to announce, and
 * that is the hardest kind of bug to notice.
 */
export async function registerPushToken(): Promise<PushRegistration> {
  if (Platform.OS === "web") {
    return { ok: false, reason: "Push notifications do not exist on web." };
  }

  // Metro substitutes EXPO_PUBLIC_* into the bundle at build time, so this is
  // the one source that does not depend on how the manifest reached the app.
  // A dev client reads an embedded manifest rather than the dev server's, which
  // is why the config-based lookups alone came back empty.
  const projectId =
    process.env.EXPO_PUBLIC_EAS_PROJECT_ID ??
    Constants.easConfig?.projectId ??
    (Constants.expoConfig?.extra?.eas?.projectId as string | undefined);
  if (!projectId) {
    return {
      ok: false,
      reason:
        "This build has no EAS project id, so Expo cannot issue a push token. Set EXPO_PUBLIC_EAS_PROJECT_ID and rebuild.",
    };
  }

  const permission = await Notifications.getPermissionsAsync();
  if (!notificationsAreAllowed(permission)) {
    return { ok: false, reason: "This devotee has not allowed notifications." };
  }

  let token: string;
  try {
    token = (await Notifications.getExpoPushTokenAsync({ projectId })).data;
  } catch (error) {
    // The usual cause is a simulator, which Apple and Google never issue push
    // tokens to. A physical device retries on the next open.
    return {
      ok: false,
      reason: `Expo would not issue a push token: ${
        error instanceof Error ? error.message : String(error)
      }`,
    };
  }

  if (token === registeredToken) return { ok: true };

  const { error } = await getSupabaseClient().rpc("register_device_push_token", {
    p_expo_push_token: token,
    p_platform: Platform.OS,
    p_device_name: Constants.deviceName ?? null,
  });
  if (error) {
    return { ok: false, reason: `The temple server refused it: ${error.message}` };
  }

  registeredToken = token;
  return { ok: true };
}

async function registerAndReport(): Promise<boolean> {
  const result = await registerPushToken();
  if (!result.ok && __DEV__) {
    console.warn(`[push] this device will not receive push: ${result.reason}`);
  }
  return result.ok;
}

/** Forgets the stored token so a different devotee re-registers this device. */
export function forgetPushRegistration() {
  registeredToken = null;
}

export async function initializeNotifications(userId?: string) {
  if (Platform.OS === "android") {
    await Notifications.setNotificationChannelAsync(TEMPLE_REMINDERS_CHANNEL, {
      name: "Temple reminders",
      description: "Reminders to confirm when you are at ISKCON Chicago",
      importance: Notifications.AndroidImportance.HIGH,
      vibrationPattern: [0, 200, 120, 200],
    });
    await Notifications.setNotificationChannelAsync(COMMUNITY_UPDATES_CHANNEL, {
      name: "Community and seva updates",
      description: "Assignments, coverage requests, and temple community updates",
      importance: Notifications.AndroidImportance.HIGH,
      vibrationPattern: [0, 180, 100, 180],
    });
  }

  let permission = await Notifications.getPermissionsAsync();
  if (!notificationsAreAllowed(permission) && permission.canAskAgain) {
    permission = await Notifications.requestPermissionsAsync({
      ios: {
        allowAlert: true,
        allowBadge: true,
        allowSound: true,
      },
    });
  }

  const allowed = notificationsAreAllowed(permission);
  if (allowed && userId) await registerAndReport();
  return allowed;
}

function notificationKind(value: unknown): AppNotificationKind {
  return typeof value === "string" ? (value as AppNotificationKind) : "remote";
}

/**
 * A push that came from an app_notifications row is already in the inbox — the
 * inbox reads that table directly. Recording it locally as well showed every
 * such notification twice and double-counted the bell badge. Only pushes with
 * no database row behind them (a local temple-arrival reminder, say) are kept
 * here.
 *
 * The local copy is also filed under whoever is signed in right now, which is
 * wrong if the push was aimed at a different account, so a push whose target
 * cannot be confirmed is dropped rather than misfiled.
 */
function recordExpoNotification(notification: Notifications.Notification) {
  const state = usePrototypeSession.getState();
  if (!state.activeUserId) return;

  const content = notification.request.content;
  if (typeof content.data?.appNotificationId === "string") return;

  // The daily check-in nudge repeats under one identifier. Filing it by that
  // identifier would put a single copy in the bell and then dedupe every day
  // after, so it is filed under the Chicago day it actually arrived on.
  if (notification.request.identifier === DAILY_TEMPLE_CHECK_IN_REMINDER_ID) {
    recordTempleArrivalReminder(
      state.activeUserId,
      new Date(notification.date),
    );
    return;
  }

  const appNotification: AppNotification = {
    id:
      typeof content.data?.appNotificationId === "string"
        ? content.data.appNotificationId
        : notification.request.identifier,
    title: content.title ?? "ISKCON Chicago",
    body: content.body ?? "You have a new notification.",
    createdAt: new Date(notification.date).toISOString(),
    isRead: false,
    kind: notificationKind(content.data?.kind),
    data:
      content.data && typeof content.data === "object"
        ? { ...content.data }
        : {},
  };

  state.addNotification(state.activeUserId, appNotification);
}

let lastHandledResponseId: string | null = null;

export function subscribeToNotifications(
  onResponse?: (data: Record<string, unknown>) => void,
) {
  const receivedSubscription = Notifications.addNotificationReceivedListener(
    recordExpoNotification,
  );
  const handleResponse = (response: Notifications.NotificationResponse) => {
    const responseId = response.notification.request.identifier;
    if (lastHandledResponseId === responseId) return;
    lastHandledResponseId = responseId;
    recordExpoNotification(response.notification);
    const data = response.notification.request.content.data;
    onResponse?.(data && typeof data === "object" ? { ...data } : {});
  };
  const responseSubscription =
    Notifications.addNotificationResponseReceivedListener(handleResponse);
  const initialResponse = Notifications.getLastNotificationResponse();
  if (initialResponse?.notification) handleResponse(initialResponse);

  return () => {
    receivedSubscription.remove();
    responseSubscription.remove();
  };
}

/**
 * Schedules the one daily nudge to check in at the temple, replacing whatever
 * was scheduled before it. This runs on every launch, so the cancel is what
 * keeps a devotee from collecting a reminder per launch; the fixed identifier
 * is what makes the cancel possible.
 *
 * The operating system delivers this with the app closed, which is the whole
 * point of it, and also why it cannot know whether the devotee has already
 * checked in today. It is worded as an offer rather than a chase for exactly
 * that reason.
 */
export async function scheduleDailyTempleCheckInReminder() {
  if (Platform.OS === "web") return false;

  // A devotee who has not allowed notifications is not asked again by the back
  // door; the next launch after they allow them will schedule it.
  const permission = await Notifications.getPermissionsAsync();
  if (!notificationsAreAllowed(permission)) return false;

  await Notifications.cancelScheduledNotificationAsync(
    DAILY_TEMPLE_CHECK_IN_REMINDER_ID,
  );
  await Notifications.scheduleNotificationAsync({
    identifier: DAILY_TEMPLE_CHECK_IN_REMINDER_ID,
    content: {
      title: templeCheckInReminderCopy.title,
      body: templeCheckInReminderCopy.body,
      data: { kind: "temple-reminder" },
      sound: "default",
    },
    trigger: {
      type: Notifications.SchedulableTriggerInputTypes.DAILY,
      hour: DAILY_TEMPLE_CHECK_IN_REMINDER_HOUR,
      minute: DAILY_TEMPLE_CHECK_IN_REMINDER_MINUTE,
      channelId: TEMPLE_REMINDERS_CHANNEL,
    },
  });

  return true;
}
