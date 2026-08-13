import { getChicagoDateKey } from "../lib/chicagoDate";
import {
  type AppNotification,
  usePrototypeSession,
} from "../store/usePrototypeSession";

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
    title: "Are you at the temple?",
    body: "Open the app and check in when you arrive at ISKCON Chicago.",
    createdAt: now.toISOString(),
    isRead: false,
    kind: "temple-reminder",
    data: {},
  };

  state.addNotification(userId, notification);
  return notification;
}
