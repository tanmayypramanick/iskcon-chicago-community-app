import { getChicagoDateKey } from "../lib/chicagoDate";
import {
  type AppNotification,
  usePrototypeSession,
} from "../store/usePrototypeSession";

/**
 * The wording of the daily check-in nudge, kept here so the banner the phone
 * shows and the entry waiting in the bell say the same thing. It offers rather
 * than chases: a devotee who is not at the temple today has done nothing
 * wrong, and the app should not sound as though they have.
 */
export const templeCheckInReminderCopy = {
  title: "If you are at the temple",
  body: "Just a reminder to check in, so the devotees here today know you have come.",
} as const;

/**
 * Files the nudge in the local bell under the Chicago day it arrived on, and
 * only once per day. The scheduled banner repeats under a single identifier,
 * so a bell entry keyed to that identifier would have shown one stale copy
 * forever; the date key is what keeps each day's reminder distinct.
 */
export function recordTempleArrivalReminder(
  userId: string,
  now = new Date(),
): AppNotification | null {
  const dateKey = getChicagoDateKey(now);
  const appNotificationId = `temple-arrival-${userId}-${dateKey}`;
  const state = usePrototypeSession.getState();
  const alreadySent = (state.notificationsByUser[userId] ?? []).some(
    (notification) => notification.id === appNotificationId,
  );

  if (alreadySent) return null;

  const notification: AppNotification = {
    id: appNotificationId,
    title: templeCheckInReminderCopy.title,
    body: templeCheckInReminderCopy.body,
    createdAt: now.toISOString(),
    isRead: false,
    kind: "temple-reminder",
    data: {},
  };

  state.addNotification(userId, notification);
  return notification;
}
