/// <reference types="jest" />

import {
  hasWeeklyOpening,
  isServingOn,
  myCompletedServices,
  myNextWeeklyOccurrence,
  myOtherUpcomingSeva,
  myUpcomingOneTime,
  myUpcomingSeva,
  myWeeklySeva,
  openWeeklySeva,
  recentlyCompletedServices,
  weeklyRoster,
  weeklySearchText,
  weeklyServingOn,
  type WeeklySeva,
} from "../selectors";
import type {
  ServiceCoveragePlanRow,
  ServiceDashboard,
  ServiceListItem,
} from "../types";

const ARPITA = {
  id: "arpita",
  name: "Arpita Jadhav",
  photo_url: null,
  role_name: "devotee",
};
const TANMAY = {
  id: "tanmay",
  name: "Tanmay Pramanick",
  photo_url: null,
  role_name: "president",
};

/** 2026-08-04 14:11 CDT. */
const NOW = new Date("2026-08-04T19:11:00.000Z");

const TUESDAY = 2;
const THURSDAY = 4;

function template(overrides: Record<string, unknown> = {}): WeeklySeva {
  return {
    id: "weekly-kitchen",
    service_type_id: null,
    custom_name: "Kitchen Seva",
    day_of_week: TUESDAY,
    days_of_week: [TUESDAY, THURSDAY],
    start_time: "05:00:00",
    duration_minutes: 90,
    slots_needed: 1,
    participation_mode: "open",
    start_date: "2026-01-01",
    end_date: null,
    created_by: TANMAY.id,
    active: true,
    created_at: "2026-01-01T00:00:00.000Z",
    updated_at: "2026-01-01T00:00:00.000Z",
    serviceType: null,
    name: "Kitchen Seva",
    assignees: [{ ...ARPITA, assignedDays: [TUESDAY, THURSDAY] }],
    ...overrides,
  } as unknown as WeeklySeva;
}

/**
 * A coverage plan as 0009 records one. `scope` is what the coordinator chose;
 * the dates and days are what the app must actually honour, which is why every
 * scope below is expressed through them rather than through the label.
 */
function plan(overrides: Partial<ServiceCoveragePlanRow> = {}) {
  return {
    id: "plan-1",
    service_exception_id: "exc-1",
    request_group_id: "grp-1",
    service_template_id: "weekly-kitchen",
    original_devotee_id: ARPITA.id,
    substitute_devotee_id: TANMAY.id,
    scope: "date_range",
    date_from: "2026-08-01",
    date_to: "2026-08-31",
    days_of_week: [TUESDAY, THURSDAY],
    status: "accepted",
    created_by: TANMAY.id,
    created_at: "2026-07-30T00:00:00.000Z",
    responded_at: "2026-07-30T00:00:00.000Z",
    ...overrides,
  } as ServiceCoveragePlanRow;
}

function service(overrides: Record<string, unknown> = {}) {
  return {
    id: "svc-1",
    template_id: null,
    service_type_id: null,
    custom_name: "Kitchen Preparation",
    date: "2026-08-06",
    start_time: "11:00:00",
    duration_minutes: 60,
    slots_needed: 1,
    participation_mode: "invite_only",
    posted_by: TANMAY.id,
    status: "full",
    created_at: NOW.toISOString(),
    name: "Kitchen Preparation",
    serviceType: null,
    filledSlots: 1,
    participants: [
      {
        assignment: { id: "asg-1", status: "confirmed", attendance: null },
        devotee: ARPITA,
      },
    ],
    currentUserAssignment: { devotee_id: ARPITA.id, status: "confirmed" },
    currentUserOffer: null,
    postedByName: TANMAY.name,
    ...overrides,
  } as unknown as ServiceListItem;
}

/** The occurrence after a swap: 0009 retires the original's place, adds one. */
function swappedOccurrence(overrides: Record<string, unknown> = {}) {
  return service({
    id: "occ-thu",
    template_id: "weekly-kitchen",
    date: "2026-08-06",
    start_time: "05:00:00",
    duration_minutes: 90,
    name: "Kitchen Seva",
    custom_name: "Kitchen Seva",
    status: "open",
    participation_mode: "open",
    participants: [
      {
        assignment: { id: "asg-arpita", status: "withdrawn", attendance: null },
        devotee: ARPITA,
      },
      {
        assignment: {
          id: "asg-tanmay",
          status: "confirmed",
          attendance: null,
          assignment_method: "accepted_coverage_offer",
        },
        devotee: TANMAY,
      },
    ],
    // api.ts only ever sets this from a live row, so after the swap the
    // original's is null and the substitute's is their own.
    currentUserAssignment: null,
    ...overrides,
  });
}

function dashboard(
  services: ServiceListItem[] = [],
  templates: WeeklySeva[] = [],
  coveragePlans: ServiceCoveragePlanRow[] = [],
) {
  return {
    serviceTypes: [],
    devotees: [ARPITA, TANMAY],
    services,
    pendingOffers: [],
    recurringTemplates: templates,
    pendingRecurringOffers: [],
    coverageRequests: [],
    coveragePlans,
    activeSessions: [],
    activitySessions: [],
    recurringInterests: [],
    verifications: [],
    myVerifications: [],
    verificationInbox: [],
    offerCounters: [],
    sevaNeedingAnswer: [],
  } as unknown as ServiceDashboard;
}

const names = (roster: Array<{ name: string }>) => roster.map((row) => row.name);
const ids = (rows: Array<{ id: string }>) => rows.map((row) => row.id);

describe("weeklyRoster answers who is on a weekly seva today", () => {
  it("returns the standing roster when nothing is covered", () => {
    const weekly = template();
    expect(
      names(weeklyRoster(dashboard([], [weekly]), weekly, NOW)),
    ).toEqual([ARPITA.name]);
  });

  it("hands over only the covered day for a one-occurrence swap", () => {
    // 0009 records a single occurrence as a one-day range, so the app must read
    // the dates rather than trust the label.
    const weekly = template();
    const data = dashboard(
      [],
      [weekly],
      [
        plan({
          scope: "occurrence",
          date_from: "2026-08-04",
          date_to: "2026-08-04",
          days_of_week: [TUESDAY],
        }),
      ],
    );
    const roster = weeklyRoster(data, weekly, NOW);

    expect(names(roster)).toEqual([ARPITA.name, TANMAY.name]);
    expect(roster.find((row) => row.id === ARPITA.id)?.assignedDays).toEqual([
      THURSDAY,
    ]);
    expect(roster.find((row) => row.id === TANMAY.id)?.assignedDays).toEqual([
      TUESDAY,
    ]);
  });

  it("hands over every covered day for a date range", () => {
    const weekly = template();
    const data = dashboard([], [weekly], [plan()]);
    const roster = weeklyRoster(data, weekly, NOW);

    // Arpita holds nothing this month, so she is not on the seva at all.
    expect(names(roster)).toEqual([TANMAY.name]);
    expect(roster[0].assignedDays).toEqual([TUESDAY, THURSDAY]);
  });

  it("hands over every covered day forever", () => {
    const weekly = template();
    const data = dashboard(
      [],
      [weekly],
      [plan({ scope: "forever", date_to: null })],
    );
    expect(names(weeklyRoster(data, weekly, NOW))).toEqual([TANMAY.name]);
  });

  it("leaves the roster alone for a swap that has not started", () => {
    const weekly = template();
    const data = dashboard(
      [],
      [weekly],
      [plan({ date_from: "2026-09-01", date_to: "2026-09-30" })],
    );
    // Naming the substitute a month early is the same mistake pointing the
    // other way.
    expect(names(weeklyRoster(data, weekly, NOW))).toEqual([ARPITA.name]);
  });

  it("gives the seva back when the range runs out", () => {
    const weekly = template();
    const data = dashboard(
      [],
      [weekly],
      [plan({ date_from: "2026-07-01", date_to: "2026-07-31" })],
    );
    expect(names(weeklyRoster(data, weekly, NOW))).toEqual([ARPITA.name]);
  });

  it("ignores a plan nobody has accepted", () => {
    const weekly = template();
    for (const status of ["pending", "declined", "cancelled"] as const) {
      const data = dashboard([], [weekly], [plan({ status })]);
      expect(names(weeklyRoster(data, weekly, NOW))).toEqual([ARPITA.name]);
    }
  });

  it("merges days when the substitute is already on the roster", () => {
    const weekly = template({
      assignees: [
        { ...ARPITA, assignedDays: [TUESDAY] },
        { ...TANMAY, assignedDays: [THURSDAY] },
      ],
    });
    const data = dashboard(
      [],
      [weekly],
      [plan({ days_of_week: [TUESDAY], scope: "forever", date_to: null })],
    );
    const roster = weeklyRoster(data, weekly, NOW);

    expect(names(roster)).toEqual([TANMAY.name]);
    expect(roster[0].assignedDays).toEqual([TUESDAY, THURSDAY]);
  });

  it("leaves the day uncovered when the substitute is not in the directory", () => {
    // Better an opening the temple can fill than a name that is not serving.
    const weekly = template();
    const data = dashboard(
      [],
      [weekly],
      [plan({ substitute_devotee_id: "someone-rls-hides" })],
    );
    expect(weeklyRoster(data, weekly, NOW)).toEqual([]);
    expect(
      hasWeeklyOpening(weekly, weeklyRoster(data, weekly, NOW)),
    ).toBe(true);
    expect(ids(openWeeklySeva(data, NOW))).toEqual(["weekly-kitchen"]);
  });

  it("does not report an opening on a day a substitute has taken", () => {
    const weekly = template();
    const data = dashboard([], [weekly], [plan()]);

    expect(hasWeeklyOpening(weekly, weeklyRoster(data, weekly, NOW))).toBe(
      false,
    );
    expect(openWeeklySeva(data, NOW)).toEqual([]);
  });
});

describe("a covered weekly seva reaches the devotee actually serving it", () => {
  it("puts the substitute's own weekly seva in front of them", () => {
    // The substitute is not on the roster — 0009 leaves it alone unless the
    // swap is forever — so before this they had nowhere to see it.
    const weekly = template();
    const data = dashboard([], [weekly], [plan()]);
    expect(ids(myWeeklySeva(data, TANMAY.id, NOW))).toEqual(["weekly-kitchen"]);
  });

  it("keeps it in front of the devotee it comes back to", () => {
    const weekly = template();
    const data = dashboard([], [weekly], [plan()]);
    expect(ids(myWeeklySeva(data, ARPITA.id, NOW))).toEqual(["weekly-kitchen"]);
  });

  it("finds the seva by either devotee's name", () => {
    const weekly = template();
    const data = dashboard([], [weekly], [plan()]);
    const text = weeklySearchText(weekly, weeklyRoster(data, weekly, NOW));

    expect(text).toContain("tanmay");
    expect(text).toContain("arpita");
  });
});

describe("a swapped occurrence credits the substitute", () => {
  it("says the substitute is serving and the original is not", () => {
    const occurrence = swappedOccurrence();
    expect(isServingOn(occurrence, TANMAY.id)).toBe(true);
    expect(isServingOn(occurrence, ARPITA.id)).toBe(false);
  });

  it("lists the covered date as the substitute's upcoming seva only", () => {
    const data = dashboard([swappedOccurrence()], [template()], [plan()]);

    expect(ids(myUpcomingSeva(data, TANMAY.id, NOW))).toEqual(["occ-thu"]);
    expect(myUpcomingSeva(data, ARPITA.id, NOW)).toEqual([]);
  });

  it("credits the finished occurrence to the substitute only", () => {
    const finished = swappedOccurrence({
      date: "2026-08-04",
      status: "completed",
      participants: [
        {
          assignment: { id: "asg-arpita", status: "withdrawn", attendance: null },
          devotee: ARPITA,
        },
        {
          assignment: {
            id: "asg-tanmay",
            status: "completed",
            attendance: "served",
          },
          devotee: TANMAY,
        },
      ],
    });
    const data = dashboard([finished], [template()], [plan()]);

    // 0059 settles a weekly occurrence on completion, so it is history at once.
    expect(ids(recentlyCompletedServices(data, NOW))).toEqual(["occ-thu"]);
    expect(ids(myCompletedServices(data, TANMAY.id, NOW))).toEqual(["occ-thu"]);
    expect(myCompletedServices(data, ARPITA.id, NOW)).toEqual([]);
  });

  it("credits a swapped one-off seva to whoever took it over", () => {
    // A one-off swap is a leave and a join, not a coverage plan, but it retires
    // the place the same way and must read the same way.
    const handedOver = service({
      status: "completed",
      participants: [
        {
          assignment: { id: "asg-1", status: "withdrawn", attendance: null },
          devotee: ARPITA,
        },
        {
          assignment: { id: "asg-2", status: "completed", attendance: "served" },
          devotee: TANMAY,
        },
      ],
      currentUserAssignment: null,
      date: "2026-08-03",
    });
    const data = dashboard([handedOver]);

    expect(ids(myCompletedServices(data, TANMAY.id, NOW))).toEqual(["svc-1"]);
    expect(myCompletedServices(data, ARPITA.id, NOW)).toEqual([]);
  });
});

describe("my upcoming seva is everything ahead of now", () => {
  it("carries weekly occurrences as well as dated requests, soonest first", () => {
    const data = dashboard(
      [
        service({ id: "later", date: "2026-08-09" }),
        swappedOccurrence({
          id: "weekly-soon",
          date: "2026-08-06",
          participants: [
            {
              assignment: { id: "asg-a", status: "confirmed", attendance: null },
              devotee: ARPITA,
            },
          ],
        }),
        service({ id: "sooner", date: "2026-08-05" }),
      ],
      [template()],
    );

    expect(ids(myUpcomingSeva(data, ARPITA.id, NOW))).toEqual([
      "sooner",
      "weekly-soon",
      "later",
    ]);
    // The one-off view is a filter over the same list, so the two can never
    // disagree about what "upcoming" means.
    expect(ids(myUpcomingOneTime(data, ARPITA.id, NOW))).toEqual([
      "sooner",
      "later",
    ]);
  });

  it("leaves out seva that is over, completed or cancelled", () => {
    const data = dashboard([
      service({ id: "over", date: "2026-08-04", start_time: "09:00:00" }),
      service({ id: "done", date: "2026-08-09", status: "completed" }),
      service({ id: "off", date: "2026-08-09", status: "cancelled" }),
      service({ id: "still-on", date: "2026-08-09" }),
    ]);
    expect(ids(myUpcomingSeva(data, ARPITA.id, NOW))).toEqual(["still-on"]);
  });

  /**
   * The Seva tab names a weekly seva once — on its roster card, which carries
   * the next date it falls on. Listing it again as a dated card put the same
   * name twice on one screen, and showing only its next date made three
   * mornings a week look like one commitment. Every date is behind "See all".
   */
  describe("one weekly seva, one card", () => {
    const occurrences = ["2026-08-06", "2026-08-11", "2026-08-13"].map((date) =>
      swappedOccurrence({
        id: `occ-${date}`,
        date,
        participants: [
          {
            assignment: { id: `asg-${date}`, status: "confirmed", attendance: null },
            devotee: TANMAY,
          },
        ],
      }),
    );
    const oneOff = service({
      id: "one-off",
      date: "2026-08-20",
      participants: [
        {
          assignment: { id: "asg-one-off", status: "confirmed", attendance: null },
          devotee: TANMAY,
        },
      ],
    });
    const data = dashboard(
      [...occurrences, oneOff],
      [template()],
      [plan()],
    );

    const shown = (dash: ServiceDashboard, userId: string) =>
      myOtherUpcomingSeva(
        dash,
        userId,
        new Set(myWeeklySeva(dash, userId, NOW).map((row) => row.id)),
        NOW,
      );

    it("drops the dated copy of a weekly seva that has a card of its own", () => {
      expect(ids(shown(data, TANMAY.id))).toEqual(["one-off"]);
    });

    it("keeps a covered occurrence whose template the devotee cannot read", () => {
      // `can_view_service_template` does not grant a substitute the template
      // row — accepting coverage does not make them a roster assignee — so
      // there is no card above and these dates are all they have.
      const templateHidden = dashboard([...occurrences, oneOff], [], [plan()]);

      expect(myWeeklySeva(templateHidden, TANMAY.id, NOW)).toEqual([]);
      expect(ids(shown(templateHidden, TANMAY.id))).toEqual([
        "occ-2026-08-06",
        "one-off",
      ]);
    });

    it("caps a card-less weekly seva to its next date all the same", () => {
      const templateHidden = dashboard([...occurrences, oneOff], [], [plan()]);
      const weeklyRows = shown(templateHidden, TANMAY.id).filter(
        (row) => row.template_id !== null,
      );

      expect(weeklyRows).toHaveLength(1);
    });

    it("gives the roster card the next date the devotee is down to serve", () => {
      expect(
        myNextWeeklyOccurrence(data, TANMAY.id, "weekly-kitchen", NOW)?.date,
      ).toBe("2026-08-06");
    });

    it("names the weekly seva exactly once between the two sections", () => {
      const weekly = myWeeklySeva(data, TANMAY.id, NOW);

      expect(weekly).toHaveLength(1);
      expect(shown(data, TANMAY.id).some((row) => row.template_id !== null))
        .toBe(false);
    });

    it("still lists every date behind See all", () => {
      expect(myUpcomingSeva(data, TANMAY.id, NOW)).toHaveLength(4);
    });

    it("offers no next date to a devotee who is not on the seva", () => {
      // Arpita's Tuesdays and Thursdays are covered all month, so she has no
      // date to turn up for even though the seva is still hers.
      expect(
        myNextWeeklyOccurrence(data, ARPITA.id, "weekly-kitchen", NOW),
      ).toBeNull();
      expect(ids(myWeeklySeva(data, ARPITA.id, NOW))).toEqual(["weekly-kitchen"]);
    });

    it("gives the next date back once the swap runs out", () => {
      const afterHandback = dashboard(
        [
          swappedOccurrence({
            id: "occ-sept",
            date: "2026-09-01",
            participants: [
              {
                assignment: { id: "asg-sept", status: "confirmed", attendance: null },
                devotee: ARPITA,
              },
            ],
          }),
        ],
        [template()],
        [plan()],
      );

      expect(
        myNextWeeklyOccurrence(afterHandback, ARPITA.id, "weekly-kitchen", NOW)?.id,
      ).toBe("occ-sept");
    });
  });
});

/**
 * The same scope matrix again, asked of one particular date rather than of
 * today. This is the answer the community schedule and "happening now" use for
 * days whose occurrence row has not been generated yet, and it has to agree
 * with `weeklyRoster` on every scope or the two halves of the tab disagree.
 */
describe("weeklyServingOn answers who is on one date", () => {
  const weekly = template();
  const on = (plans: ServiceCoveragePlanRow[], dateKey: string, day: number) =>
    weeklyServingOn(dashboard([], [weekly], plans), weekly, dateKey, day)
      .map((person) => person.name);

  it("names the standing devotee when nothing is covered", () => {
    expect(on([], "2026-08-04", TUESDAY)).toEqual([ARPITA.name]);
  });

  it("hands over the single date of a one-occurrence swap and no other", () => {
    const single = [
      plan({
        scope: "occurrence",
        date_from: "2026-08-04",
        date_to: "2026-08-04",
        days_of_week: [TUESDAY],
      }),
    ];

    expect(on(single, "2026-08-04", TUESDAY)).toEqual([TANMAY.name]);
    expect(on(single, "2026-08-11", TUESDAY)).toEqual([ARPITA.name]);
    expect(on(single, "2026-08-06", THURSDAY)).toEqual([ARPITA.name]);
  });

  it("hands over every date inside a range and none outside it", () => {
    expect(on([plan()], "2026-08-01", THURSDAY)).toEqual([TANMAY.name]);
    expect(on([plan()], "2026-08-31", TUESDAY)).toEqual([TANMAY.name]);
    expect(on([plan()], "2026-07-31", THURSDAY)).toEqual([ARPITA.name]);
    expect(on([plan()], "2026-09-01", TUESDAY)).toEqual([ARPITA.name]);
  });

  it("hands over every date from here on for a forever swap", () => {
    const forever = [plan({ scope: "forever", date_to: null })];

    expect(on(forever, "2026-08-04", TUESDAY)).toEqual([TANMAY.name]);
    expect(on(forever, "2027-03-02", TUESDAY)).toEqual([TANMAY.name]);
    expect(on(forever, "2026-07-28", TUESDAY)).toEqual([ARPITA.name]);
  });

  it("leaves the original in place for a swap that has not started", () => {
    const next = [plan({ date_from: "2026-09-01", date_to: "2026-09-30" })];

    expect(on(next, "2026-08-04", TUESDAY)).toEqual([ARPITA.name]);
    expect(on(next, "2026-09-01", TUESDAY)).toEqual([TANMAY.name]);
  });

  it("ignores a plan nobody has accepted, on any date", () => {
    for (const status of ["pending", "declined", "cancelled"] as const) {
      expect(on([plan({ status })], "2026-08-04", TUESDAY)).toEqual([ARPITA.name]);
    }
  });

  it("covers only the days the plan names", () => {
    const thursdaysOnly = [plan({ days_of_week: [THURSDAY] })];

    expect(on(thursdaysOnly, "2026-08-06", THURSDAY)).toEqual([TANMAY.name]);
    expect(on(thursdaysOnly, "2026-08-04", TUESDAY)).toEqual([ARPITA.name]);
  });

  it("agrees with weeklyRoster about today", () => {
    // Two functions, one question. They are read side by side on the tab — the
    // roster card and the schedule row — and disagreeing is the visible bug.
    for (const scope of [
      plan({ scope: "occurrence", date_from: "2026-08-04", date_to: "2026-08-04", days_of_week: [TUESDAY] }),
      plan(),
      plan({ scope: "forever", date_to: null }),
      plan({ date_from: "2026-09-01", date_to: "2026-09-30" }),
      plan({ status: "pending" }),
    ]) {
      const data = dashboard([], [weekly], [scope]);
      const rosteredToday = weeklyRoster(data, weekly, NOW)
        .filter((assignee) => assignee.assignedDays.includes(TUESDAY))
        .map((person) => person.name);

      expect(weeklyServingOn(data, weekly, "2026-08-04", TUESDAY).map((p) => p.name))
        .toEqual(rosteredToday);
    }
  });
});

describe("an accepted alternative time lands in my upcoming seva", () => {
  it("shows the seva at the proposed time, on the devotee who proposed it", () => {
    // The state migration 0024's respond_to_service_offer_counter leaves
    // behind: the instance moved to the proposed date and length, and a
    // confirmed accepted_offer assignment for the devotee who suggested it.
    const moved = service({
      id: "moved",
      date: "2026-08-08",
      start_time: "16:00:00",
      duration_minutes: 120,
      status: "full",
      participants: [
        {
          assignment: {
            id: "asg-counter",
            status: "confirmed",
            attendance: null,
            assignment_method: "accepted_offer",
          },
          devotee: TANMAY,
        },
      ],
      currentUserAssignment: null,
    });
    const data = dashboard([moved]);
    const mine = myUpcomingSeva(data, TANMAY.id, NOW);

    expect(ids(mine)).toEqual(["moved"]);
    expect(mine[0].date).toBe("2026-08-08");
    expect(mine[0].start_time).toBe("16:00:00");
    expect(mine[0].duration_minutes).toBe(120);
    // The devotee who was originally asked is not quietly left on it.
    expect(myUpcomingSeva(data, ARPITA.id, NOW)).toEqual([]);
  });
});

describe("a weekly occurrence counts once its hour has passed", () => {
  /** What 0065's hourly sweep leaves behind: closed, marked, nobody owed. */
  const autoCompleted = () =>
    swappedOccurrence({
      id: "occ-past",
      date: "2026-08-04",
      start_time: "05:00:00",
      status: "completed",
      participants: [
        {
          assignment: {
            id: "asg-auto",
            status: "completed",
            attendance: null,
            completed_at: "2026-08-04T11:30:00.000Z",
          },
          devotee: ARPITA,
        },
      ],
    });

  it("reads as history rather than as something still waiting", () => {
    const data = dashboard([autoCompleted()], [template()]);

    expect(ids(recentlyCompletedServices(data, NOW))).toEqual(["occ-past"]);
    expect(ids(myCompletedServices(data, ARPITA.id, NOW))).toEqual(["occ-past"]);
  });

  it("has left my upcoming seva", () => {
    const data = dashboard([autoCompleted()], [template()]);
    expect(myUpcomingSeva(data, ARPITA.id, NOW)).toEqual([]);
  });

  it("still counts while the sweep has not run yet", () => {
    // The hour has gone but the row is untouched. It must not read as upcoming
    // — a devotee has nowhere to be — and it is the weekly path, so nobody is
    // owed a confirmation either.
    const notSweptYet = autoCompleted();
    const pending = { ...notSweptYet, status: "open" } as ServiceListItem;
    const data = dashboard([pending], [template()]);

    expect(myUpcomingSeva(data, ARPITA.id, NOW)).toEqual([]);
    expect(recentlyCompletedServices(data, NOW)).toEqual([]);
  });
});
