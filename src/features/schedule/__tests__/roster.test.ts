/// <reference types="jest" />

/**
 * What a block is allowed to say about who is serving, and how the screen tells
 * an empty week from a week it may not read.
 *
 * The fixtures are `list_seva_schedule` rows in the shape migration 0069
 * returns them, including the two the temple cared about most: a Thursday that
 * has been handed over, and a seva whose roster this reader may not see.
 */

jest.mock("../../../lib/supabase", () => ({
  getSupabaseClient: jest.fn(),
}));

import { classifyScheduleError } from "../api";
import {
  densityByDay,
  occurrenceAccessibilityLabel,
  placesLabel,
  rosterSummary,
  serverLabel,
  timeRangeLabel,
} from "../selectors";
import type { SevaScheduleOccurrence, SevaScheduleServer } from "../types";

function server(overrides: Partial<SevaScheduleServer> = {}): SevaScheduleServer {
  return {
    devoteeId: "d-arpita",
    name: "Arpita Jadhav",
    assignmentId: "asg-1",
    assignmentStatus: "confirmed",
    attendance: null,
    pointsStatus: "pending",
    isSubstitute: false,
    coveringForDevoteeId: null,
    coveringForName: null,
    ...overrides,
  };
}

function occurrence(
  overrides: Partial<SevaScheduleOccurrence> = {},
): SevaScheduleOccurrence {
  return {
    service_instance_id: "inst-1",
    template_id: "tpl-1",
    from_weekly_template: true,
    seva_name: "Vegetable Cutting",
    service_type_id: "type-veg",
    service_category: "kitchen",
    occurs_on: "2026-08-13",
    day_of_week: 4,
    starts_at_local: "16:15:00",
    ends_at_local: "17:45:00",
    ends_next_day: false,
    duration_minutes: 90,
    starts_at: "2026-08-13T21:15:00.000Z",
    ends_at: "2026-08-13T22:45:00.000Z",
    status: "full",
    nobody_served: false,
    participation_mode: "invite_only",
    posted_by: "d-tanmay",
    slots_needed: 2,
    filled_slots: 2,
    open_slots: 0,
    roster_visible: true,
    servers: [server()],
    ...overrides,
  };
}

describe("who a block says is serving", () => {
  it("names the substitute on a Thursday that was handed over", () => {
    // The temple's own requirement: "if someone swapped, their name will be
    // there". The server has already applied the coverage plan, so the client's
    // whole job is to not lose the substitute on the way to the screen.
    const swapped = occurrence({
      servers: [
        server({
          devoteeId: "d-krsna",
          name: "Krsna Kirtan Das",
          assignmentId: null,
          isSubstitute: true,
          coveringForDevoteeId: "d-arpita",
          coveringForName: "Arpita Jadhav",
        }),
      ],
    });

    expect(serverLabel(swapped.servers[0])).toBe(
      "Krsna Kirtan Das (covering for Arpita Jadhav)",
    );
    expect(rosterSummary(swapped).named).toEqual([
      "Krsna Kirtan Das (covering for Arpita Jadhav)",
    ]);
    expect(occurrenceAccessibilityLabel(swapped)).toContain(
      "served by Krsna Kirtan Das (covering for Arpita Jadhav)",
    );
    // The devotee whose seva it was is no longer on it, which is the other half
    // of the same requirement.
    expect(occurrenceAccessibilityLabel(swapped)).not.toContain(
      "served by Arpita Jadhav",
    );
  });

  it("says a substitute is covering even when it may not say for whom", () => {
    // The server nulls coveringForName for a reader who is neither party.
    const partial = server({
      name: "Krsna Kirtan Das",
      isSubstitute: true,
      coveringForDevoteeId: null,
      coveringForName: null,
    });
    expect(serverLabel(partial)).toBe("Krsna Kirtan Das (covering)");
  });

  it("hides co-servers when the roster is withheld, without claiming the seva is empty", () => {
    // roster_visible false: the server has filtered `servers` down to this
    // reader's own place while filled_slots still counts everybody. Saying
    // "1 devotee serving" here would be a lie about a seva four people are on.
    const withheld = occurrence({
      roster_visible: false,
      slots_needed: 4,
      filled_slots: 4,
      open_slots: 0,
      servers: [server()],
    });

    const summary = rosterSummary(withheld);
    expect(summary.withheld).toBe(true);
    expect(summary.named).toEqual(["Arpita Jadhav"]);
    expect(summary.unnamed).toBe(3);

    const label = occurrenceAccessibilityLabel(withheld);
    expect(label).toContain("Arpita Jadhav");
    expect(label).toContain("3 other devotees are not named here");
  });

  it("names nobody at all on a withheld roster the reader is not on", () => {
    const stranger = occurrence({
      roster_visible: false,
      slots_needed: 2,
      filled_slots: 2,
      servers: [],
    });
    expect(occurrenceAccessibilityLabel(stranger)).toContain(
      "the roster is not shown to you",
    );
  });

  it("counts places the way a coordinator scans for them", () => {
    expect(placesLabel(occurrence({ filled_slots: 0, open_slots: 2 }))).toBe(
      "no one of 2 places taken",
    );
    expect(
      placesLabel(
        occurrence({ slots_needed: 1, filled_slots: 0, open_slots: 1 }),
      ),
    ).toBe("no one has taken this yet");
    expect(
      placesLabel(
        occurrence({ slots_needed: 3, filled_slots: 2, open_slots: 1 }),
      ),
    ).toBe("2 of 3 places filled");
    expect(placesLabel(occurrence())).toBe("2 devotees serving");
  });
});

describe("what a screen reader is told", () => {
  it("carries everything the block itself has no room for", () => {
    const label = occurrenceAccessibilityLabel(occurrence());
    expect(label).toContain("Vegetable Cutting");
    expect(label).toContain("weekly seva");
    expect(label).toContain("Thursday 2026-08-13");
    expect(label).toContain("4:15 PM to 5:45 PM");
    expect(label).toContain("2 devotees serving");
  });

  it("says when a seva runs into the next day", () => {
    expect(
      timeRangeLabel({
        starts_at_local: "23:00:00",
        duration_minutes: 180,
        ends_next_day: true,
      }),
    ).toBe("11:00 PM to 2:00 AM the next day");
  });

  it("says a cancelled seva is cancelled", () => {
    expect(
      occurrenceAccessibilityLabel(occurrence({ status: "cancelled" })),
    ).toContain("cancelled");
  });
});

describe("a month, reduced to what a cell can show", () => {
  it("counts the seva and the places still open on each day", () => {
    const density = densityByDay([
      occurrence({ service_instance_id: "a", occurs_on: "2026-08-13" }),
      occurrence({
        service_instance_id: "b",
        occurs_on: "2026-08-13",
        open_slots: 2,
        nobody_served: true,
      }),
      occurrence({ service_instance_id: "c", occurs_on: "2026-08-14" }),
    ]);

    expect(density.get("2026-08-13")).toEqual({
      dateKey: "2026-08-13",
      seva: 2,
      openSlots: 2,
      unserved: 1,
    });
    expect(density.get("2026-08-14")?.seva).toBe(1);
    expect(density.has("2026-08-15")).toBe(false);
  });
});

describe("why the timetable has nothing to draw", () => {
  /**
   * The messages are quoted from migration 0069. They all arrive as P0001, so
   * the code cannot separate them — if the temple rewords one of these, this is
   * the test that says the screen will start calling a refusal an outage.
   */
  it("tells a refusal apart from an empty week", () => {
    expect(
      classifyScheduleError({
        code: "P0001",
        message:
          "Only the President, the Tech Admin and the Community Head may read the whole temple's timetable. Ask for your own by naming yourself.",
      }),
    ).toBe("denied");
    expect(
      classifyScheduleError({
        code: "P0001",
        message: "You may only read your own seva timetable.",
      }),
    ).toBe("denied");
    expect(
      classifyScheduleError({
        code: "P0001",
        message: "Sign in to read the seva timetable.",
      }),
    ).toBe("denied");
  });

  it("tells a window that is too long apart from a refusal", () => {
    expect(
      classifyScheduleError({
        code: "P0001",
        message:
          "A timetable window may cover at most 35 days; 2026-08-01 to 2026-09-30 is 61.",
      }),
    ).toBe("window");
  });

  it("tells a database without the migration apart from both", () => {
    expect(
      classifyScheduleError({
        code: "PGRST202",
        message: "Could not find the function public.list_seva_schedule",
      }),
    ).toBe("unavailable");
    expect(classifyScheduleError({ code: "42883", message: "no function" })).toBe(
      "unavailable",
    );
  });

  it("tells a dropped connection apart from all of them", () => {
    expect(
      classifyScheduleError(new TypeError("Network request failed")),
    ).toBe("offline");
  });

  it("does not guess at anything else", () => {
    expect(
      classifyScheduleError({ code: "P0001", message: "something else broke" }),
    ).toBe("unknown");
    expect(classifyScheduleError(null)).toBe("unknown");
  });
});
