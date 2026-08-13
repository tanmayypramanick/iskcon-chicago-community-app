import { create } from "zustand";
import {
  createJSONStorage,
  persist,
  type StateStorage,
} from "zustand/middleware";

import {
  canRequestAccessRole,
  type AccessRole,
} from "../features/access/model";
import type { AppNotificationRow } from "../features/notifications/types";

export type { AccessRole } from "../features/access/model";

export type AccessRequestStatus = "pending" | "approved" | "denied";

export type PrototypeAccessRequest = {
  id: string;
  requesterName: string;
  currentRole: AccessRole;
  requestedRole: AccessRole;
  status: AccessRequestStatus;
  createdAt: string;
  reviewedAt: string | null;
  reviewedByRole: "president" | "tech" | null;
};

type PrototypeSession = {
  isAuthenticated: boolean;
  previewRole: AccessRole | null;
  activeUserId: string | null;
  accessRequests: PrototypeAccessRequest[];
  notificationsByUser: Record<string, AppNotification[]>;
  authenticate: () => void;
  signOut: () => void;
  setPreviewRole: (role: AccessRole | null) => void;
  setActiveUserId: (userId: string | null) => void;
  requestAccess: (
    requesterName: string,
    currentRole: AccessRole,
    requestedRole: AccessRole,
  ) => void;
  reviewAccessRequest: (
    requestId: string,
    decision: Exclude<AccessRequestStatus, "pending">,
    reviewerRole: "president" | "tech",
  ) => void;
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
      previewRole: null,
      activeUserId: null,
      accessRequests: [],
      notificationsByUser: {},
      authenticate: () => set({ isAuthenticated: true }),
      signOut: () =>
        set({
          isAuthenticated: false,
          previewRole: null,
          activeUserId: null,
          accessRequests: [],
        }),
      setPreviewRole: (previewRole) => set({ previewRole }),
      setActiveUserId: (activeUserId) => set({ activeUserId }),
      requestAccess: (requesterName, currentRole, requestedRole) =>
        set((state) => {
          if (!canRequestAccessRole(currentRole, requestedRole)) return state;
          if (
            state.accessRequests.some(
              (request) =>
                request.requesterName === requesterName &&
                request.status === "pending",
            )
          ) {
            return state;
          }

          return {
            accessRequests: [
              {
                id: `access-${Date.now()}-${requestedRole}`,
                requesterName,
                currentRole,
                requestedRole,
                status: "pending",
                createdAt: new Date().toISOString(),
                reviewedAt: null,
                reviewedByRole: null,
              },
              ...state.accessRequests,
            ],
          };
        }),
      reviewAccessRequest: (requestId, decision, reviewerRole) =>
        set((state) => ({
          accessRequests: state.accessRequests.map((request) =>
            request.id === requestId && request.status === "pending"
              ? {
                  ...request,
                  status: decision,
                  reviewedAt: new Date().toISOString(),
                  reviewedByRole: reviewerRole,
                }
              : request,
          ),
        })),
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
