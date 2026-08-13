/// <reference types="jest" />

import {
  clashSubject,
  clashWarningMessage,
  clashWarningTitle,
  coordinatorClashSummary,
  groupClosedUnserved,
  nextDateOnWeekday,
  unservedPlaceReason,
  weekdayNameForDate,
  windowEnd,
  windowText,
} from "../clashes";
import type { ClosedUnservedRow, SevaClash } from "../types";

function clash(overrides: Partial<SevaClash> = {}): SevaClash {
  return {
    service_instance_id: "clashing-seva",
    template_id: null,
    from_weekly_template: false,
    seva_name: "Kitchen Preparation",
    name_visible: true,
    occurs_on: "2026-08-20",
    starts_at_local: "12:00:00",
    ends_at_local: "13:30:00",
    ends_next_day: false,
    starts_at: "2026-08-20T17:00:00Z",
    ends_at: "2026-08-20T18:30:00Z",
    status: "open",
    assignment_status: "confirmed",
    is_substitute: false,
    overlap_minutes: 15,
    overlap_starts_at: "2026-08-20T18:15:00Z",
    overlap_ends_at: "2026-08-20T18:30:00Z",
    covers_whole_request: false,
    ...overrides,
  };
}

describe("the window a clash is measured against", () => {
  it("ends where the seva ends", () => {
    expect(windowEnd("13:15:00", 75)).toEqual({
      time: "14:30:00",
      nextDay: false,
    });
    expect(windowText("13:15:00", 75)).toBe("1:15 PM to 2:30 PM");
  });

  it("says so when a seva runs past midnight", () => {
    expect(windowEnd("23:00:00", 120)).toEqual({
      time: "01:00:00",
      nextDay: true,
    });
    expect(windowText("23:00:00", 120)).toContain("the next day");
  });
});

describe("what a devotee is told", () => {
  const wording = {
    audience: "self" as const,
    startTime: "13:15:00",
    durationMinutes: 75,
  };

  it("says both windows and the size of the brush between them", () => {
    const message = clashWarningMessage(wording, [clash()]);

    expect(message).toBe(
      "You are serving Kitchen Preparation from 12:00 PM to 1:30 PM, " +
        "but this seva is from 1:15 PM to 2:30 PM. " +
        "The two overlap by 15 min. " +
        "Only accept if you can manage to serve both.",
    );
  });

  it("leaves the choice with the devotee rather than making it", () => {
    expect(clashWarningTitle(wording)).toBe("You are already serving then");
    expect(clashWarningMessage(wording, [clash()])).toContain(
      "Only accept if you can manage to serve both",
    );
  });

  it("words a total collision differently from a fifteen-minute one", () => {
    const whole = clashWarningMessage(wording, [
      clash({ overlap_minutes: 75, covers_whole_request: true }),
    ]);

    expect(whole).toContain("That covers the whole of it.");
    expect(whole).not.toContain("overlap by");
  });

  it("never invents a name the server withheld", () => {
    const hidden = clash({ seva_name: null, name_visible: false });

    expect(clashSubject(hidden)).toBe("another seva");
    const message = clashWarningMessage(wording, [hidden]);
    expect(message).toContain("You are serving another seva from 12:00 PM");
    expect(message).not.toMatch(/null|undefined|Kitchen/);
  });

  it("counts the rest rather than listing them", () => {
    expect(clashWarningMessage(wording, [clash(), clash(), clash()])).toContain(
      "2 other seva overlap this time too.",
    );
  });

  it("says nothing at all when nothing clashes", () => {
    expect(clashWarningMessage(wording, [])).toBe("");
  });
});

describe("what a coordinator is told before inviting somebody", () => {
  const wording = { startTime: "13:15:00", durationMinutes: 75 };

  it("names the devotee and still lets the invitation go", () => {
    const message = coordinatorClashSummary(
      [{ name: "Ravi Das", clashes: [clash()] }],
      wording,
    );

    expect(message).toContain("Ravi Das is serving Kitchen Preparation");
    expect(message).toContain("but this seva is from 1:15 PM to 2:30 PM");
    expect(message).toContain(
      "You can still ask — whether they can manage both is theirs to judge.",
    );
  });

  it("withholds a name it was not given, for somebody else too", () => {
    const message = coordinatorClashSummary(
      [
        {
          name: "Ravi Das",
          clashes: [clash({ seva_name: null, name_visible: false })],
        },
      ],
      wording,
    );

    expect(message).toContain("Ravi Das is serving another seva");
    expect(message).not.toMatch(/null|undefined/);
  });

  it("lists several devotees by name", () => {
    const message = coordinatorClashSummary(
      [
        { name: "Ravi Das", clashes: [clash()] },
        { name: "Gita Devi", clashes: [clash()] },
        { name: "Free Devotee", clashes: [] },
      ],
      wording,
    );

    expect(message).toContain("Ravi Das and Gita Devi are already serving");
    expect(message).not.toContain("Free Devotee");
  });
});

describe("what a clash means on a weekly rota", () => {
  const wording = {
    audience: "other" as const,
    devoteeName: "Ravi Das",
    startTime: "13:15:00",
    durationMinutes: 75,
    weekday: "Thursday",
  };

  it("reports a standing commitment as repeating", () => {
    const message = clashWarningMessage(wording, [
      clash({ from_weekly_template: true }),
    ]);

    expect(message).toContain("serving Kitchen Preparation every Thursday");
    expect(message).toContain("this weekly seva is from 1:15 PM to 2:30 PM");
    expect(message).toContain("The two overlap by 15 min, every Thursday.");
  });

  it("reports a dated seva caught under a rota as the one date it is", () => {
    const message = clashWarningMessage(wording, [
      clash({ from_weekly_template: false, occurs_on: "2026-08-20" }),
    ]);

    expect(message).toContain("on Thu, Aug 20 from 12:00 PM to 1:30 PM");
    expect(message).toContain("only.");
    expect(message).not.toContain("every Thursday");
  });

  it("asks about the next occurrence of each weekday it is given", () => {
    // 2026-08-17 is a Monday.
    expect(nextDateOnWeekday("2026-08-17", 4)).toBe("2026-08-20");
    expect(nextDateOnWeekday("2026-08-17", 1)).toBe("2026-08-17");
    expect(nextDateOnWeekday("2026-08-17", 0)).toBe("2026-08-23");
    expect(weekdayNameForDate("2026-08-20")).toBe("Thursday");
  });
});

describe("seva nobody served", () => {
  function row(overrides: Partial<ClosedUnservedRow> = {}): ClosedUnservedRow {
    return {
      service_instance_id: "seva-1",
      seva_name: "Temple Room Cleaning",
      occurred_on: "2026-08-11",
      weekday: "Tuesday",
      started_at_local: "09:00:00",
      planned_minutes: 60,
      is_recurring: false,
      posted_by: "poster",
      closed_at: "2026-08-11T16:00:00Z",
      devotee_id: "devotee-1",
      devotee_name: "Ravi Das",
      assignment_status: "completed",
      attendance: "absent",
      points_status: "not_served",
      ...overrides,
    };
  }

  it("folds one row per place back into one seva", () => {
    const grouped = groupClosedUnserved([
      row(),
      row({ devotee_id: "devotee-2", devotee_name: "Gita Devi", attendance: "excused" }),
      row({ service_instance_id: "seva-2", seva_name: "Garland Making" }),
    ]);

    expect(grouped).toHaveLength(2);
    expect(grouped[0].name).toBe("Temple Room Cleaning");
    expect(grouped[0].places.map((place) => place.name)).toEqual([
      "Ravi Das",
      "Gita Devi",
    ]);
    expect(grouped[1].name).toBe("Garland Making");
  });

  it("says why each place did not count, in the words somebody recorded", () => {
    const [seva] = groupClosedUnserved([
      row(),
      row({ devotee_id: "d2", devotee_name: "Gita", attendance: "excused" }),
      row({
        devotee_id: "d3",
        devotee_name: "Shyam",
        attendance: null,
        assignment_status: "withdrawn",
      }),
    ]);

    expect(seva.places.map(unservedPlaceReason)).toEqual([
      "marked absent",
      "excused",
      "stood down",
    ]);
  });
});
