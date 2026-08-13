import * as Notifications from "expo-notifications";
import Constants from "expo-constants";
import { Platform } from "react-native";

import { getSupabaseClient } from "../lib/supabase";
import {
  type AppNotification,
  type AppNotificationKind,
  usePrototypeSession,
} from "../store/usePrototypeSession";
import { recordTempleArrivalReminder } from "./notificationInbox";

const TEMPLE_REMINDERS_CHANNEL = "temple-reminders";
const COMMUNITY_UPDATES_CHANNEL = "community-updates";

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

export async function sendTempleArrivalReminder(userId: string) {
  const notification = recordTempleArrivalReminder(userId);
  if (!notification) return false;

  const permission = await Notifications.getPermissionsAsync();
  if (!notificationsAreAllowed(permission)) return true;

  await Notifications.scheduleNotificationAsync({
    identifier: notification.id,
    content: {
      title: notification.title,
      body: notification.body,
      data: {
        appNotificationId: notification.id,
        kind: "temple-reminder",
      },
      sound: "default",
    },
    trigger:
      Platform.OS === "android"
        ? {
            type: Notifications.SchedulableTriggerInputTypes.TIME_INTERVAL,
            seconds: 1,
            channelId: TEMPLE_REMINDERS_CHANNEL,
          }
        : null,
  });

  return true;
}
