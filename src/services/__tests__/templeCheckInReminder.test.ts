/// <reference types="jest" />

import { readdirSync, readFileSync, existsSync } from "fs";
import { join } from "path";

/**
 * A stand-in for the operating system's own schedule. It lives inside the mock
 * factory because jest hoists that above everything else in the file, and it
 * records a second schedule under a live identifier as a second entry — the
 * real API replaces silently, which would hide the very piling-up this file is
 * here to catch.
 */
jest.mock("expo-notifications", () => {
  const scheduled = new Map<string, unknown>();

  return {
    __scheduled: scheduled,
    setNotificationHandler: jest.fn(),
    getPermissionsAsync: jest.fn(),
    scheduleNotificationAsync: jest.fn(
      async (request: { identifier: string }) => {
        scheduled.set(
          scheduled.has(request.identifier)
            ? `${request.identifier}#${scheduled.size}`
            : request.identifier,
          request,
        );
        return request.identifier;
      },
    ),
    cancelScheduledNotificationAsync: jest.fn(async (identifier: string) => {
      scheduled.delete(identifier);
    }),
    setNotificationChannelAsync: jest.fn(),
    addNotificationReceivedListener: jest.fn(),
    addNotificationResponseReceivedListener: jest.fn(),
    getLastNotificationResponse: jest.fn(),
    IosAuthorizationStatus: { PROVISIONAL: 3, AUTHORIZED: 2 },
    AndroidImportance: { HIGH: 4 },
    SchedulableTriggerInputTypes: {
      DAILY: "daily",
      TIME_INTERVAL: "timeInterval",
    },
  };
});

jest.mock("expo-constants", () => ({
  __esModule: true,
  default: { easConfig: null, expoConfig: null, deviceName: null },
}));

jest.mock("../../lib/supabase", () => ({
  getSupabaseClient: jest.fn(),
}));

import * as Notifications from "expo-notifications";

import { templeCheckInReminderCopy } from "../notificationInbox";
import {
  DAILY_TEMPLE_CHECK_IN_REMINDER_HOUR,
  DAILY_TEMPLE_CHECK_IN_REMINDER_ID,
  DAILY_TEMPLE_CHECK_IN_REMINDER_MINUTE,
  scheduleDailyTempleCheckInReminder,
} from "../notifications";

const mockGetPermissions = jest.mocked(Notifications.getPermissionsAsync);
const scheduled = (Notifications as unknown as { __scheduled: Map<string, unknown> })
  .__scheduled;

const allowed = { granted: true, ios: {} } as never;
const refused = { granted: false, ios: {} } as never;

describe("the daily temple check-in reminder", () => {
  beforeEach(() => {
    scheduled.clear();
    jest.clearAllMocks();
    mockGetPermissions.mockResolvedValue(allowed);
  });

  it("asks for four in the afternoon, every day, on the temple channel", async () => {
    await expect(scheduleDailyTempleCheckInReminder()).resolves.toBe(true);

    expect(Notifications.scheduleNotificationAsync).toHaveBeenCalledWith(
      expect.objectContaining({
        identifier: DAILY_TEMPLE_CHECK_IN_REMINDER_ID,
        trigger: {
          type: "daily",
          hour: 16,
          minute: 0,
          channelId: "temple-reminders",
        },
      }),
    );
    expect(DAILY_TEMPLE_CHECK_IN_REMINDER_HOUR).toBe(16);
    expect(DAILY_TEMPLE_CHECK_IN_REMINDER_MINUTE).toBe(0);
  });

  it("carries the same wording as the entry waiting in the bell", async () => {
    await scheduleDailyTempleCheckInReminder();

    expect(Notifications.scheduleNotificationAsync).toHaveBeenCalledWith(
      expect.objectContaining({
        content: expect.objectContaining({
          title: templeCheckInReminderCopy.title,
          body: templeCheckInReminderCopy.body,
        }),
      }),
    );
  });

  it("replaces itself on every launch rather than piling up", async () => {
    await scheduleDailyTempleCheckInReminder();
    await scheduleDailyTempleCheckInReminder();
    await scheduleDailyTempleCheckInReminder();

    expect(Notifications.cancelScheduledNotificationAsync).toHaveBeenCalledWith(
      DAILY_TEMPLE_CHECK_IN_REMINDER_ID,
    );
    expect([...scheduled.keys()]).toEqual([DAILY_TEMPLE_CHECK_IN_REMINDER_ID]);
  });

  it("schedules nothing for a devotee who refused notifications", async () => {
    mockGetPermissions.mockResolvedValue(refused);

    await expect(scheduleDailyTempleCheckInReminder()).resolves.toBe(false);
    expect(Notifications.scheduleNotificationAsync).not.toHaveBeenCalled();
  });
});

/**
 * The temple dropped background geofencing rather than carry it through an app
 * review. These read the tree rather than the module graph on purpose: a stray
 * import or a permission left in the config would not fail any other test, and
 * that is precisely how half-removed things survive.
 */
describe("nothing is left of the location feature", () => {
  const root = join(__dirname, "../../..");
  const banned =
    /expo-location|expo-task-manager|TaskManager|[Gg]eofenc|locationWhenInUse|startTempleGeofencing/;

  function sourceFiles(directory: string): string[] {
    return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
      const full = join(directory, entry.name);
      if (entry.isDirectory()) return sourceFiles(full);
      return /\.tsx?$/.test(entry.name) ? [full] : [];
    });
  }

  it("has no location service left to import", () => {
    expect(existsSync(join(root, "src/services/templeLocation.ts"))).toBe(
      false,
    );
  });

  it("mentions location nowhere in src, this file aside", () => {
    const offenders = sourceFiles(join(root, "src"))
      .filter((file) => file !== __filename)
      .filter((file) => banned.test(readFileSync(file, "utf8")));

    expect(offenders).toEqual([]);
  });

  it("no longer declares the location plugin or its dependencies", () => {
    expect(readFileSync(join(root, "app.config.js"), "utf8")).not.toMatch(
      banned,
    );

    const dependencies = JSON.parse(
      readFileSync(join(root, "package.json"), "utf8"),
    ).dependencies as Record<string, string>;
    expect(dependencies["expo-location"]).toBeUndefined();
    expect(dependencies["expo-task-manager"]).toBeUndefined();
  });
});
