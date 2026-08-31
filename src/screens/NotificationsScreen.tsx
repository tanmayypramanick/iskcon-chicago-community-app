import { Ionicons } from "@expo/vector-icons";
import { useIsFocused, type NavigationProp } from "@react-navigation/native";
import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import { useEffect, useMemo, useState } from "react";
import { Pressable, Text, View } from "react-native";
import { Swipeable } from "react-native-gesture-handler";

import tokens from "../../design-tokens.json";
import { ListScreen } from "../components/ui";
import { BirthdayPrompt } from "../features/birthdays/components";
import {
  useAppNotifications,
  useClearAppNotifications,
  useDeleteAppNotification,
  useMarkAppNotificationsRead,
} from "../features/notifications/hooks";
import {
  getNotificationTarget,
  withNotificationBackHistory,
} from "../features/notifications/navigation";
import type { AppNotificationRow } from "../features/notifications/types";
import type { HomeStackParamList, MainTabParamList } from "../navigation/types";
import {
  type AppNotification,
  usePrototypeSession,
} from "../store/usePrototypeSession";
import {
  CreateAnnouncementModal,
  type AnnouncementPrefill,
} from "./CreateAnnouncementScreen";

type Props = NativeStackScreenProps<HomeStackParamList, "Notifications">;

type NotificationItem = {
  id: string;
  title: string;
  body: string;
  createdAt: string;
  isRead: boolean;
  kind: string;
  data: Record<string, unknown>;
  source: "remote" | "local";
  sourceId: string;
};

function formatNotificationTime(value: string) {
  return new Intl.DateTimeFormat("en-US", {
    timeZone: "America/Chicago",
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
  }).format(new Date(value));
}

function fromRemote(notification: AppNotificationRow): NotificationItem {
  return {
    id: `remote-${notification.id}`,
    title: notification.title,
    body: notification.body,
    createdAt: notification.created_at,
    isRead: Boolean(notification.read_at),
    kind: notification.kind,
    data: notification.data,
    source: "remote",
    sourceId: notification.id,
  };
}

function fromLocal(notification: AppNotification): NotificationItem {
  return {
    id: `local-${notification.id}`,
    title: notification.title,
    body: notification.body,
    createdAt: notification.createdAt,
    isRead: notification.isRead,
    kind: notification.kind,
    data: notification.data ?? {},
    source: "local",
    sourceId: notification.id,
  };
}

export function NotificationsScreen({ navigation }: Props) {
  const isFocused = useIsFocused();
  const activeUserId = usePrototypeSession((state) => state.activeUserId);
  const localNotifications = usePrototypeSession((state) =>
    activeUserId ? (state.notificationsByUser[activeUserId] ?? []) : [],
  );
  const markLocalRead = usePrototypeSession(
    (state) => state.markAllNotificationsRead,
  );
  const remote = useAppNotifications(activeUserId);
  const markRemoteRead = useMarkAppNotificationsRead(activeUserId);
  const deleteRemote = useDeleteAppNotification();
  const clearRemote = useClearAppNotifications(activeUserId);
  const removeLocal = usePrototypeSession((state) => state.removeNotification);
  const clearLocal = usePrototypeSession((state) => state.clearNotifications);
  const [birthdayWish, setBirthdayWish] = useState<AnnouncementPrefill | null>(
    null,
  );

  useEffect(() => {
    if (!isFocused || !activeUserId) return;
    void remote.refetch();
  }, [activeUserId, isFocused, remote.refetch]);

  const notifications = useMemo(
    () =>
      [
        ...(remote.data ?? []).map(fromRemote),
        ...localNotifications.map(fromLocal),
      ].sort((a, b) => b.createdAt.localeCompare(a.createdAt)),
    [localNotifications, remote.data],
  );

  useEffect(() => {
    if (!activeUserId) return;
    markLocalRead(activeUserId);
    if ((remote.data ?? []).some((notification) => !notification.read_at)) {
      markRemoteRead.mutate();
    }
    // Only run when the loaded inbox changes, not when the mutation object does.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeUserId, remote.data]);

  const openNotification = (notification: NotificationItem) => {
    const rawTarget = getNotificationTarget(notification);
    if (!rawTarget) return;
    const target = withNotificationBackHistory(rawTarget);
    const tabs = navigation.getParent<NavigationProp<MainTabParamList>>();
    tabs?.navigate(target.tab, target.params as never);
  };

  const clearOne = (notification: NotificationItem) => {
    if (!activeUserId) return;
    if (notification.source === "remote") {
      deleteRemote.mutate(notification.sourceId);
    } else {
      removeLocal(activeUserId, notification.sourceId);
    }
  };

  const clearAll = () => {
    if (!activeUserId) return;
    clearLocal(activeUserId);
    if (remote.data?.length) clearRemote.mutate();
  };

  return (
    <>
      <ListScreen
        bottomInset={false}
        topInset={false}
        data={notifications}
        keyExtractor={(notification) => notification.id}
        header={
          <>
            {/* Above the inbox rather than in it: the prompt is a thing to do
                today, and a birthday that has already been read still wants
                doing until somebody posts. It draws nothing for a devotee. */}
            <BirthdayPrompt onWish={setBirthdayWish} />
            {notifications.length ? (
              <View className="mb-3 flex-row items-center justify-between">
                <Text className="font-sans text-sm text-stoneMuted">
                  Swipe left to clear one
                </Text>
                <Pressable
                  className="min-h-10 items-center justify-center rounded-pill bg-indigoSoft px-4"
                  accessibilityRole="button"
                  accessibilityLabel="Clear all notifications"
                  disabled={clearRemote.isPending}
                  onPress={clearAll}
                >
                  <Text className="font-sans-bold text-sm text-indigo">
                    Clear all
                  </Text>
                </Pressable>
              </View>
            ) : null}
          </>
        }
        renderItem={(notification, index) => {
          const isTempleReminder = notification.kind === "temple-reminder";
          const canOpen = getNotificationTarget(notification) !== null;
          const isFirst = index === 0;
          const isLast = index === notifications.length - 1;

          return (
            <View
              className={`overflow-hidden border-x border-border bg-white ${
                isFirst ? "rounded-t-card border-t" : ""
              } ${isLast ? "rounded-b-card border-b" : ""}`}
            >
              <Swipeable
                overshootRight={false}
                renderRightActions={() => (
                  <Pressable
                    className="w-24 items-center justify-center bg-vermilion"
                    accessibilityRole="button"
                    accessibilityLabel={`Clear ${notification.title}`}
                    onPress={() => clearOne(notification)}
                  >
                    <Ionicons
                      name="trash-outline"
                      size={21}
                      color={tokens.colors.white}
                    />
                    <Text className="mt-1 font-sans-bold text-xs text-white">
                      Clear
                    </Text>
                  </Pressable>
                )}
              >
                <Pressable
                  className={`flex-row bg-white px-card py-4 ${
                    isLast ? "" : "border-b border-border"
                  }`}
                  accessibilityRole={canOpen ? "button" : undefined}
                  disabled={!canOpen}
                  onPress={() => openNotification(notification)}
                >
                  <View
                    className={`h-11 w-11 flex-shrink-0 items-center justify-center rounded-pill ${
                      isTempleReminder ? "bg-marigoldSoft" : "bg-indigoSoft"
                    }`}
                  >
                    <Ionicons
                      name={isTempleReminder ? "location" : "notifications"}
                      size={21}
                      color={tokens.colors.indigo}
                    />
                  </View>
                  <View className="ml-4 min-w-0 flex-1">
                    <View className="flex-row items-start">
                      <Text className="min-w-0 flex-1 font-sans-bold text-base text-stone">
                        {notification.title}
                      </Text>
                      {!notification.isRead ? (
                        <View className="ml-2 mt-1.5 h-2 w-2 rounded-pill bg-marigold" />
                      ) : null}
                    </View>
                    <Text className="mt-1 font-sans text-sm leading-5 text-stoneMuted">
                      {notification.body}
                    </Text>
                    <View className="mt-2 flex-row items-center">
                      <Text className="font-sans-bold text-xs text-peacock">
                        {formatNotificationTime(notification.createdAt)}
                      </Text>
                      {canOpen ? (
                        <Text className="ml-2 font-sans-bold text-xs text-indigo">
                          View details →
                        </Text>
                      ) : null}
                    </View>
                  </View>
                </Pressable>
              </Swipeable>
            </View>
          );
        }}
        empty={
          <View className="items-center rounded-card border border-border bg-white px-card py-10">
            <View className="h-14 w-14 items-center justify-center rounded-pill bg-indigoSoft">
              <Ionicons
                name="notifications-outline"
                size={26}
                color={tokens.colors.indigo}
              />
            </View>
            <Text className="mt-4 font-display text-xl text-stone">
              You’re all caught up
            </Text>
            <Text className="mt-2 max-w-72 text-center font-sans text-sm leading-5 text-stoneMuted">
              Temple reminders and live service updates will appear here.
            </Text>
          </View>
        }
      />

      {/* Rendered here rather than pushed as a route: the composer is the same
          modal the noticeboard opens, and coming back from it should be the
          inbox that was being read. */}
      <CreateAnnouncementModal
        visible={birthdayWish !== null}
        prefill={birthdayWish}
        onClose={() => setBirthdayWish(null)}
      />
    </>
  );
}
