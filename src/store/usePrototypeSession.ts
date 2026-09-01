import { create } from "zustand";
import {
  createJSONStorage,
  persist,
  type StateStorage,
} from "zustand/middleware";

import type { AppNotificationRow } from "../features/notifications/types";

export type { AccessRole } from "../features/access/model";

type PrototypeSession = {
  isAuthenticated: boolean;
  activeUserId: string | null;
  notificationsByUser: Record<string, AppNotification[]>;
  authenticate: () => void;
  signOut: () => void;
  setActiveUserId: (userId: string | null) => void;
  addNotification: (userId: string, notification: AppNotification) => void;
  markAllNotificationsRead: (userId: string) => void;
  removeNotification: (userId: string, notificationId: string) => void;
  clearNotifications: (userId: string) => void;
};

export type AppNotificationKind =
  "temple-reminder" | "remote" | AppNotificationRow["kind"];

export type AppNotification = {
  id: string;
  title: string;
  body: string;
  createdAt: string;
  isRead: boolean;
  kind: AppNotificationKind;
  data?: Record<string, unknown>;
};

const memoryValues = new Map<string, string>();
const memoryStorage: StateStorage = {
  getItem: (name) => memoryValues.get(name) ?? null,
  setItem: (name, value) => {
    memoryValues.set(name, value);
  },
  removeItem: (name) => {
    memoryValues.delete(name);
  },
};

export const usePrototypeSession = create<PrototypeSession>()(
  persist(
    (set) => ({
      isAuthenticated: false,
      activeUserId: null,
      notificationsByUser: {},
      authenticate: () => set({ isAuthenticated: true }),
      signOut: () =>
        set({
          isAuthenticated: false,
          activeUserId: null,
        }),
      setActiveUserId: (activeUserId) => set({ activeUserId }),
      addNotification: (userId, notification) =>
        set((state) => {
          const existing = state.notificationsByUser[userId] ?? [];
          if (existing.some((item) => item.id === notification.id)) {
            return state;
          }

          return {
            notificationsByUser: {
              ...state.notificationsByUser,
              [userId]: [notification, ...existing].slice(0, 100),
            },
          };
        }),
      markAllNotificationsRead: (userId) =>
        set((state) => ({
          notificationsByUser: {
            ...state.notificationsByUser,
            [userId]: (state.notificationsByUser[userId] ?? []).map((item) =>
              item.isRead ? item : { ...item, isRead: true },
            ),
          },
        })),
      removeNotification: (userId, notificationId) =>
        set((state) => ({
          notificationsByUser: {
            ...state.notificationsByUser,
            [userId]: (state.notificationsByUser[userId] ?? []).filter(
              (notification) => notification.id !== notificationId,
            ),
          },
        })),
      clearNotifications: (userId) =>
        set((state) => ({
          notificationsByUser: {
            ...state.notificationsByUser,
            [userId]: [],
          },
        })),
    }),
    {
      name: "iskcon-chicago-presence",
      storage: createJSONStorage(() =>
        typeof localStorage === "undefined" ? memoryStorage : localStorage,
      ),
      partialize: (state) => ({
        activeUserId: state.activeUserId,
        notificationsByUser: state.notificationsByUser,
      }),
    },
  ),
);
