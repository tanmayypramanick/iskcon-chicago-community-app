/// <reference types="jest" />

import { birthdayRowWhen, birthdaySummary } from "../summary";
import type { UpcomingBirthday } from "../types";

function birthday(
  overrides: Partial<UpcomingBirthday> & { days_away: number },
): UpcomingBirthday {
  return {
    devotee_id: `d-${overrides.days_away}-${overrides.name ?? ""}`,
    name: "Arpita Jadhav",
    photo_url: null,
    date_of_birth: "1996-08-31",
    turning_age: 30,
    celebrated_on: "2026-08-31",
    ...overrides,
  };
}

describe("birthdaySummary", () => {
  it("draws nothing when there is nothing to say", () => {
    expect(birthdaySummary([])).toBeNull();
  });

  it("names the one devotee celebrating today", () => {
    const summary = birthdaySummary([birthday({ days_away: 0 })]);
    expect(summary).toMatchObject({
      title: "Arpita Jadhav’s birthday is today",
      detail: "Post an announcement?",
      today: true,
      todayCount: 1,
    });
  });

  it("counts them when more than one falls on the same day", () => {
    const summary = birthdaySummary([
      birthday({ days_away: 0, name: "Arpita Jadhav" }),
      birthday({ days_away: 0, name: "Ravi Das" }),
      birthday({ days_away: 4, name: "Later Das" }),
    ]);
    expect(summary).toMatchObject({
      title: "2 birthdays today",
      detail: "Post an announcement?",
      today: true,
      todayCount: 2,
    });
  });

  it("falls back to the next one when nobody is celebrating today", () => {
    const summary = birthdaySummary([
      birthday({ days_away: 5, name: "Ravi Das" }),
      birthday({ days_away: 12, name: "Later Das" }),
    ]);
    expect(summary).toMatchObject({
      title: "Upcoming birthdays",
      detail: "Ravi Das in 5 days",
      today: false,
      todayCount: 0,
    });
  });

  it("says tomorrow rather than in 1 days", () => {
    expect(birthdaySummary([birthday({ days_away: 1 })])?.detail).toBe(
      "Arpita Jadhav tomorrow",
    );
  });

  it("survives a devotee with no usable name", () => {
    expect(birthdaySummary([birthday({ days_away: 0, name: null })])).toMatchObject(
      { title: "A devotee’s birthday is today" },
    );
    expect(birthdaySummary([birthday({ days_away: 3, name: "   " })])?.detail).toBe(
      "A devotee in 3 days",
    );
  });

  it("treats today as today even if the list is not sorted first", () => {
    const summary = birthdaySummary([
      birthday({ days_away: 9, name: "Later Das" }),
      birthday({ days_away: 0, name: "Arpita Jadhav" }),
    ]);
    expect(summary?.today).toBe(true);
    expect(summary?.title).toBe("Arpita Jadhav’s birthday is today");
  });
});

describe("birthdayRowWhen", () => {
  it("says Today rather than a date", () => {
    expect(birthdayRowWhen(birthday({ days_away: 0 }))).toBe("Today · Turning 30");
  });

  it("says Tomorrow", () => {
    expect(birthdayRowWhen(birthday({ days_away: 1 }))).toBe(
      "Tomorrow · Turning 30",
    );
  });

  it("counts days out", () => {
    expect(birthdayRowWhen(birthday({ days_away: 12 }))).toBe(
      "In 12 days · Turning 30",
    );
  });

  it("leaves the age out when the recorded year makes it nonsense", () => {
    expect(birthdayRowWhen(birthday({ days_away: 0, turning_age: null }))).toBe(
      "Today",
    );
  });
});
