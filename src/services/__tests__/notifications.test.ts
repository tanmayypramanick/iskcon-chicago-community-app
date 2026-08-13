/// <reference types="jest" />

import { readFileSync } from "fs";
import { join } from "path";

import { usePrototypeSession } from "../../store/usePrototypeSession";
import { recordTempleArrivalReminder } from "../notificationInbox";

describe("temple arrival notifications", () => {
  beforeEach(() => {
    usePrototypeSession.setState({ notificationsByUser: {} });
  });

  it("records only one reminder per devotee per Chicago day", () => {
    const first = recordTempleArrivalReminder(
      "devotee-1",
      new Date("2026-08-02T16:00:00Z"),
    );
    const duplicate = recordTempleArrivalReminder(
      "devotee-1",
      new Date("2026-08-02T20:00:00Z"),
    );

    const notifications =
      usePrototypeSession.getState().notificationsByUser["devotee-1"];

    expect(notifications).toHaveLength(1);
    expect(notifications[0]).toMatchObject({
      title: "Are you at the temple?",
      kind: "temple-reminder",
      isRead: false,
    });
    expect(first).not.toBeNull();
    expect(duplicate).toBeNull();
  });

  it("marks bell inbox notifications as read", () => {
    recordTempleArrivalReminder("devotee-2");
    usePrototypeSession.getState().markAllNotificationsRead("devotee-2");

    expect(
      usePrototypeSession.getState().notificationsByUser["devotee-2"][0].isRead,
    ).toBe(true);
  });

  it("clears one notification or the complete local inbox", () => {
    const state = usePrototypeSession.getState();
    state.addNotification("devotee-3", {
      id: "first",
      title: "First",
      body: "First notification",
      createdAt: "2026-08-03T12:00:00.000Z",
      isRead: false,
      kind: "remote",
    });
    state.addNotification("devotee-3", {
      id: "second",
      title: "Second",
      body: "Second notification",
      createdAt: "2026-08-03T13:00:00.000Z",
      isRead: false,
      kind: "service_offer",
    });

    usePrototypeSession.getState().removeNotification("devotee-3", "first");
    expect(
      usePrototypeSession.getState().notificationsByUser["devotee-3"],
    ).toHaveLength(1);
    expect(
      usePrototypeSession.getState().notificationsByUser["devotee-3"][0].id,
    ).toBe("second");

    usePrototypeSession.getState().clearNotifications("devotee-3");
    expect(
      usePrototypeSession.getState().notificationsByUser["devotee-3"],
    ).toEqual([]);
  });
});

describe("push notifications are not double-recorded", () => {
  it("ignores a push that already has an app_notifications row", () => {
    // The inbox reads app_notifications directly. Filing a local copy as well
    // showed the notification twice and double-counted the bell badge.
    const source = readFileSync(
      join(__dirname, "../notifications.ts"),
      "utf8",
    );
    expect(source).toContain(
      'if (typeof content.data?.appNotificationId === "string") return;',
    );
  });

  it("keeps recording local-only pushes, which have no row behind them", () => {
    const source = readFileSync(
      join(__dirname, "../notifications.ts"),
      "utf8",
    );
    // The temple-arrival reminder is scheduled locally and must still appear.
    expect(source).toContain("recordTempleArrivalReminder");
    expect(source).toContain("state.addNotification(");
  });
});
