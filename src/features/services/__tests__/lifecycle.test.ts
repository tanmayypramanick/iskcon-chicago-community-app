/// <reference types="jest" />

import { buildCompletedSevaRows } from "../report";
import {
  awaitingCompletionServices,
  communitySchedule,
  didServe,
  didServeAny,
  foldCompletedSeva,
  isSevaConfirmedServed,
  isServingOn,
  lapsedOpenRequests,
  myCompletedServices,
  myUpcomingSeva,
  nobodyServed,
  openOneTimeRequirements,
  recentlyCompletedServices,
  servedDevotees,
  servedParticipants,
  servingDevotees,
  unconfirmedAssignmentIds,
  upcomingServices,
} from "../selectors";
import type {
  ServiceAssignmentRow,
  ServiceDashboard,
  ServiceDevotee,
  ServiceListItem,
  ServiceParticipant,
} from "../types";

const ARPITA: ServiceDevotee = {
  id: "arpita",
  name: "Arpita Jadhav",
  photo_url: null,
  role_name: "devotee",
};
const TANMAY: ServiceDevotee = {
  id: "tanmay",
  name: "Tanmay Pramanick",
  photo_url: null,
  role_name: "president",
};

/** 2026-08-04 14:11 CDT. Morning seva is over; evening seva is not. */
const NOW = new Date("2026-08-04T19:11:00.000Z");
const TODAY = "2026-08-04";
const TOMORROW = "2026-08-05";

function place(
  devotee: ServiceDevotee,
  overrides: Partial<ServiceAssignmentRow> = {},
): ServiceParticipant {
  return {
    devotee,
    assignment: {
      id: `asg-${devotee.id}`,
      service_instance_id: "svc-1",
      devotee_id: devotee.id,
      assignment_method: "self_joined",
      assigned_by: null,
      status: "confirmed",
      attendance: null,
      verification: "self_report",
      qr_scanned_at: null,
      created_at: "2026-08-01T00:00:00.000Z",
      completed_at: null,
      ...overrides,
    },
  };
}

function service(overrides: Record<string, unknown> = {}): ServiceListItem {
  const participants = (overrides.participants as ServiceParticipant[]) ?? [];
  return {
    id: "svc-1",
    template_id: null,
    service_type_id: null,
    custom_name: "Kitchen Preparation",
    date: TOMORROW,
    start_time: "11:00:00",
    duration_minutes: 60,
    slots_needed: 2,
    participation_mode: "open",
    posted_by: TANMAY.id,
    status: "open",
    created_at: "2026-08-01T00:00:00.000Z",
    name: "Kitchen Preparation",
    serviceType: null,
    filledSlots: participants.length,
    participants,
    currentUserAssignment: null,
    currentUserOffer: null,
    postedByName: TANMAY.name,
    ...overrides,
  } as unknown as ServiceListItem;
}

function dashboard(services: ServiceListItem[]): ServiceDashboard {
  return {
    serviceTypes: [],
    devotees: [ARPITA, TANMAY],
    services,
    pendingOffers: [],
    recurringTemplates: [],
    pendingRecurringOffers: [],
    coverageRequests: [],
    coveragePlans: [],
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

const ids = (rows: Array<{ id: string }>) => rows.map((row) => row.id);

/**
 * One seva walked through every state it can reach, asserting where it appears
 * at each. The sections are what the temple reads the tab as, so a state that
 * lands in the wrong one — or in two at once — is the failure that matters.
 */
describe("a one-off seva through its whole life", () => {
  it("open: offered to everyone and on nobody's list", () => {
    const data = dashboard([service()]);

    expect(ids(openOneTimeRequirements(data, NOW))).toEqual(["svc-1"]);
    // Nobody has joined, so it is a request and not yet something planned.
    expect(communitySchedule(data, NOW)).toEqual([]);
    expect(myUpcomingSeva(data, ARPITA.id, NOW)).toEqual([]);
  });

  it("self-joined: still open for the second place, and now mine", () => {
    const data = dashboard([service({ participants: [place(ARPITA)] })]);

    expect(ids(openOneTimeRequirements(data, NOW))).toEqual(["svc-1"]);
    expect(ids(communitySchedule(data, NOW))).toEqual(["svc-1"]);
    expect(ids(myUpcomingSeva(data, ARPITA.id, NOW))).toEqual(["svc-1"]);
    expect(myUpcomingSeva(data, TANMAY.id, NOW)).toEqual([]);
  });

  it("full: off the request list, still on the schedule", () => {
    const data = dashboard([
      service({
        status: "full",
        participants: [place(ARPITA), place(TANMAY)],
      }),
    ]);

    expect(openOneTimeRequirements(data, NOW)).toEqual([]);
    expect(ids(communitySchedule(data, NOW))).toEqual(["svc-1"]);
  });

  it("invite-only: never offered as an open request", () => {
    const data = dashboard([
      service({ participation_mode: "invite_only", participants: [] }),
    ]);

    expect(openOneTimeRequirements(data, NOW)).toEqual([]);
    // An invitation is still something the temple has planned, even empty.
    expect(ids(communitySchedule(data, NOW))).toEqual(["svc-1"]);
  });

  it("assigned but not yet confirmed: the devotee is on it", () => {
    const data = dashboard([
      service({ participants: [place(ARPITA, { status: "assigned" })] }),
    ]);

    expect(isServingOn(data.services[0], ARPITA.id)).toBe(true);
    expect(ids(myUpcomingSeva(data, ARPITA.id, NOW))).toEqual(["svc-1"]);
  });

  it("in progress: upcoming until the last minute has run, then not", () => {
    const running = dashboard([
      service({ date: TODAY, start_time: "14:00:00", duration_minutes: 60, participants: [place(ARPITA)] }),
    ]);
    const finished = dashboard([
      service({ date: TODAY, start_time: "11:00:00", duration_minutes: 60, participants: [place(ARPITA)] }),
    ]);

    expect(ids(upcomingServices(running, NOW))).toEqual(["svc-1"]);
    expect(upcomingServices(finished, NOW)).toEqual([]);
  });

  it("over but not closed off: waiting on whoever posted it, not history", () => {
    const data = dashboard([
      service({
        date: TODAY,
        start_time: "11:00:00",
        participation_mode: "invite_only",
        participants: [place(ARPITA)],
      }),
    ]);

    expect(ids(awaitingCompletionServices(data, NOW))).toEqual(["svc-1"]);
    expect(recentlyCompletedServices(data, NOW)).toEqual([]);
    expect(myUpcomingSeva(data, ARPITA.id, NOW)).toEqual([]);
  });

  it("completed but unmarked: still waiting, and it says how many", () => {
    const data = dashboard([
      service({
        date: TODAY,
        start_time: "11:00:00",
        status: "completed",
        participation_mode: "invite_only",
        participants: [
          place(ARPITA, { status: "completed" }),
          place(TANMAY, { status: "completed" }),
        ],
      }),
    ]);

    expect(isSevaConfirmedServed(data.services[0])).toBe(false);
    expect(unconfirmedAssignmentIds(data.services[0])).toHaveLength(2);
    expect(ids(awaitingCompletionServices(data, NOW))).toEqual(["svc-1"]);
    expect(recentlyCompletedServices(data, NOW)).toEqual([]);
  });

  it("attendance recorded: it becomes history on the last answer", () => {
    const data = dashboard([
      service({
        date: TODAY,
        start_time: "11:00:00",
        status: "completed",
        participation_mode: "invite_only",
        participants: [
          place(ARPITA, { status: "completed", attendance: "served" }),
          place(TANMAY, { status: "completed", attendance: "served" }),
        ],
      }),
    ]);

    expect(isSevaConfirmedServed(data.services[0])).toBe(true);
    expect(awaitingCompletionServices(data, NOW)).toEqual([]);
    expect(ids(recentlyCompletedServices(data, NOW))).toEqual(["svc-1"]);
    expect(ids(myCompletedServices(data, ARPITA.id, NOW))).toEqual(["svc-1"]);
  });

  it("cancelled: it is not upcoming, not waiting and not history", () => {
    const data = dashboard([
      service({ date: TODAY, start_time: "11:00:00", status: "cancelled", participants: [place(ARPITA)] }),
    ]);

    expect(upcomingServices(data, NOW)).toEqual([]);
    expect(awaitingCompletionServices(data, NOW)).toEqual([]);
    expect(recentlyCompletedServices(data, NOW)).toEqual([]);
  });

  it("cancelled before it happens: gone from the devotee's list at once", () => {
    const data = dashboard([
      service({ status: "cancelled", participants: [place(ARPITA)] }),
    ]);
    expect(myUpcomingSeva(data, ARPITA.id, NOW)).toEqual([]);
  });
});

/**
 * The temple's wording: "a passed request appears in recently completed whether
 * or not anyone served it". Nobody owns an open request, so there is nobody to
 * ask — it lapses rather than queuing for an answer that is never coming.
 */
describe("an open request whose time simply ran out", () => {
  const lapsed = (participants: ServiceParticipant[]) =>
    dashboard([
      service({ date: TODAY, start_time: "11:00:00", participants }),
    ]);

  it("lapses into history with nobody on it", () => {
    const data = lapsed([]);

    expect(ids(lapsedOpenRequests(data, NOW))).toEqual(["svc-1"]);
    expect(ids(recentlyCompletedServices(data, NOW))).toEqual(["svc-1"]);
    expect(awaitingCompletionServices(data, NOW)).toEqual([]);
  });

  it("lapses into history with somebody on it too", () => {
    const data = lapsed([place(ARPITA)]);

    expect(ids(recentlyCompletedServices(data, NOW))).toEqual(["svc-1"]);
    expect(awaitingCompletionServices(data, NOW)).toEqual([]);
  });

  it("never leaves an invite-only request to lapse unanswered", () => {
    // Somebody was asked by name, so somebody owes an answer.
    const data = dashboard([
      service({
        date: TODAY,
        start_time: "11:00:00",
        participation_mode: "invite_only",
        participants: [place(ARPITA)],
      }),
    ]);

    expect(lapsedOpenRequests(data, NOW)).toEqual([]);
    expect(ids(awaitingCompletionServices(data, NOW))).toEqual(["svc-1"]);
  });
});

/**
 * A coordinator saying somebody did not turn up. The temple's own rule —
 * `seva_points_status` — calls absent and excused `not_served`, and the app has
 * to agree with it in both places a devotee reads their seva back.
 */
describe("a devotee marked not served", () => {
  const marked = (attendance: "absent" | "excused") =>
    dashboard([
      service({
        date: TODAY,
        start_time: "11:00:00",
        status: "completed",
        slots_needed: 2,
        participation_mode: "invite_only",
        participants: [
          place(ARPITA, { status: "completed", attendance }),
          place(TANMAY, { status: "completed", attendance: "served" }),
        ],
      }),
    ]);

  it.each(["absent", "excused"] as const)(
    "keeps a %s devotee out of their own completed seva",
    (attendance) => {
      const data = marked(attendance);

      expect(didServe(data.services[0], ARPITA.id)).toBe(false);
      expect(myCompletedServices(data, ARPITA.id, NOW)).toEqual([]);
      // The seva itself still happened, and whoever did turn up still has it.
      expect(ids(recentlyCompletedServices(data, NOW))).toEqual(["svc-1"]);
      expect(ids(myCompletedServices(data, TANMAY.id, NOW))).toEqual(["svc-1"]);
    },
  );

  it.each(["absent", "excused"] as const)(
    "keeps a %s devotee's hours out of the temple's report",
    (attendance) => {
      const rows = buildCompletedSevaRows(marked(attendance), NOW);

      expect(rows.map((row) => row.devotee)).toEqual([TANMAY.name]);
    },
  );

  it("settles the seva rather than leaving it waiting forever", () => {
    // "Absent" is an answer. Holding the card open for it would leave a queue
    // nobody can clear.
    const data = marked("absent");

    expect(isSevaConfirmedServed(data.services[0])).toBe(true);
    expect(awaitingCompletionServices(data, NOW)).toEqual([]);
  });

  it("still counts a place nobody has answered for either way", () => {
    // Unmarked is not the same as absent. The hourly sweep closes weekly seva
    // without marking anyone, and those devotees did serve.
    const data = dashboard([
      service({
        date: TODAY,
        start_time: "11:00:00",
        status: "completed",
        template_id: "weekly-kitchen",
        participants: [place(ARPITA, { status: "completed", attendance: null })],
      }),
    ]);

    expect(didServe(data.services[0], ARPITA.id)).toBe(true);
    expect(ids(myCompletedServices(data, ARPITA.id, NOW))).toEqual(["svc-1"]);
    expect(buildCompletedSevaRows(data, NOW).map((row) => row.devotee)).toEqual([
      ARPITA.name,
    ]);
  });
});

/**
 * "If one person did the seva, it will still go to the completed list as one
 * person served, and only that person will get seva in their list."
 *
 * Rule 4: an absence takes the devotee out, never the seva.
 */
describe("a seva one of whose devotees was absent", () => {
  const partly = dashboard([
    service({
      date: TODAY,
      start_time: "11:00:00",
      status: "completed",
      slots_needed: 2,
      participants: [
        place(ARPITA, { status: "completed", attendance: "absent" }),
        place(TANMAY, { status: "completed", attendance: "served" }),
      ],
    }),
  ]);

  it("still completes, because somebody served it", () => {
    expect(nobodyServed(partly.services[0])).toBe(false);
    expect(ids(recentlyCompletedServices(partly, NOW))).toEqual(["svc-1"]);
  });

  it("names only the devotee who served it", () => {
    // This is what a card's avatar row, its "+N" and its names line all draw
    // from — the roster is still whole, but nothing may say Arpita served.
    expect(servedDevotees(partly.services[0])).toEqual([TANMAY]);
    expect(servedParticipants(partly.services[0])).toHaveLength(1);
    // The roster itself is untouched: a coordinator has to be able to see an
    // absent devotee in order to change their mind about them.
    expect(servingDevotees(partly.services[0])).toEqual([ARPITA, TANMAY]);
  });

  it("credits only that devotee", () => {
    expect(ids(myCompletedServices(partly, TANMAY.id, NOW))).toEqual(["svc-1"]);
    expect(myCompletedServices(partly, ARPITA.id, NOW)).toEqual([]);
  });
});

/**
 * "If there is only one person doing seva, if marked absent or excused, it will
 * get removed from the list and not go in the completed list — as if no one
 * served this, how is this seva completed."
 *
 * Rule 3. The status on the row is still the server's to set; what the client
 * refuses to do is present a row nobody served as service that happened.
 */
describe("a seva nobody served", () => {
  const noneServed = (attendance: "absent" | "excused") =>
    dashboard([
      service({
        date: TODAY,
        start_time: "11:00:00",
        status: "completed",
        slots_needed: 1,
        participation_mode: "invite_only",
        participants: [place(ARPITA, { status: "completed", attendance })],
      }),
    ]);

  it.each(["absent", "excused"] as const)(
    "keeps a seva whose only devotee was %s out of the completed list",
    (attendance) => {
      const data = noneServed(attendance);

      expect(nobodyServed(data.services[0])).toBe(true);
      expect(recentlyCompletedServices(data, NOW)).toEqual([]);
      expect(myCompletedServices(data, ARPITA.id, NOW)).toEqual([]);
      expect(buildCompletedSevaRows(data, NOW)).toEqual([]);
    },
  );

  it("drops one whose devotees were every one of them absent", () => {
    // Two devotees, both absent, is the same question as one — nobody served.
    const data = dashboard([
      service({
        date: TODAY,
        start_time: "11:00:00",
        status: "completed",
        slots_needed: 2,
        participants: [
          place(ARPITA, { status: "completed", attendance: "absent" }),
          place(TANMAY, { status: "completed", attendance: "excused" }),
        ],
      }),
    ]);

    expect(nobodyServed(data.services[0])).toBe(true);
    expect(recentlyCompletedServices(data, NOW)).toEqual([]);
  });

  it("is not the same as a seva nobody was ever assigned to", () => {
    // An empty roster has no absent devotee to disqualify it, and open
    // requests whose hour ran out reach history on their own.
    const data = dashboard([
      service({
        date: TODAY,
        start_time: "11:00:00",
        status: "completed",
        participants: [],
      }),
    ]);

    expect(nobodyServed(data.services[0])).toBe(false);
    expect(ids(recentlyCompletedServices(data, NOW))).toEqual(["svc-1"]);
  });
});

/**
 * The client's `nobodyServed` is belt-and-braces for the stale-cache and
 * optimistic-patch windows, and it only earns its keep while it says the same
 * thing as the server. 0068's `service_instance_has_server` is that server
 * rule: a seva has a server unless *every* assignment's `seva_points_status` is
 * `not_served`, and absent, excused, no_show and withdrawn are all not_served.
 * These pin the client to it.
 */
describe("nobodyServed still says what 0068 says", () => {
  const closed = (participants: ServiceParticipant[]) =>
    service({
      date: TODAY,
      start_time: "11:00:00",
      status: "completed",
      participants,
    });

  it("treats a place nobody answered for as service, exactly as the server does", () => {
    // seva_points_status(completed, null, self_report) is not 'not_served', so
    // an unmarked weekly occurrence the hourly sweep closed still counts.
    expect(
      nobodyServed(closed([place(ARPITA, { status: "completed", attendance: null })])),
    ).toBe(false);
  });

  it("discounts a no-show and a stood-down place, exactly as the server does", () => {
    // Both are 'not_served' on the server and both are outside the client's
    // live set, so a seva carrying one of each plus one absent devotee has
    // nobody on it either way.
    expect(
      nobodyServed(
        closed([
          place(ARPITA, { status: "no_show" }),
          place(TANMAY, { status: "completed", attendance: "absent" }),
        ]),
      ),
    ).toBe(true);
  });

  it("differs from the server on one case only, and harmlessly", () => {
    // Every place withdrawn: the server closes it, because an assignment row
    // exists and none of them served. The client says "not this case" because
    // its live roster is empty. It cannot matter — a seva the server closed is
    // `cancelled`, so it never reaches `completedServices` for this filter to
    // be asked about in the first place.
    const withdrawnOnly = closed([place(ARPITA, { status: "withdrawn" })]);

    expect(nobodyServed(withdrawnOnly)).toBe(false);
    expect(servedParticipants(withdrawnOnly)).toEqual([]);
  });
});

describe("a place that was given up is nobody's seva", () => {
  const handedOver = dashboard([
    service({
      date: TODAY,
      start_time: "11:00:00",
      status: "completed",
      participation_mode: "invite_only",
      participants: [
        place(ARPITA, { status: "withdrawn" }),
        place(TANMAY, { status: "completed", attendance: "served" }),
      ],
    }),
  ]);

  it("credits only the devotee who served it", () => {
    expect(myCompletedServices(handedOver, ARPITA.id, NOW)).toEqual([]);
    expect(ids(myCompletedServices(handedOver, TANMAY.id, NOW))).toEqual(["svc-1"]);
  });

  it("never waits on the answer for a place that was given up", () => {
    expect(unconfirmedAssignmentIds(handedOver.services[0])).toEqual([]);
    expect(isSevaConfirmedServed(handedOver.services[0])).toBe(true);
  });

  it("keeps a no-show out of the report", () => {
    const noShow = dashboard([
      service({
        date: TODAY,
        start_time: "11:00:00",
        status: "completed",
        participants: [place(ARPITA, { status: "no_show" })],
      }),
    ]);
    expect(buildCompletedSevaRows(noShow, NOW)).toEqual([]);
  });
});

/**
 * 0059: a weekly occurrence earns its place on completion with nothing further
 * owed, so the hourly sweep of 0065 finishes the job in one step.
 */
/**
 * The Seva tab shows a slice of each list and puts the rest behind "See all".
 * A "See all" that opens a different set than the section it was tapped from is
 * how the temple lost sight of covered dates, so the two are asserted together.
 */
describe("what the tab shows and what See all opens", () => {
  const mine = [
    service({ id: "svc-1", date: TOMORROW, participants: [place(ARPITA)] }),
    service({ id: "svc-2", date: "2026-08-06", participants: [place(ARPITA)] }),
    service({ id: "svc-3", date: "2026-08-07", participants: [place(ARPITA)] }),
    service({ id: "svc-4", date: "2026-08-08", participants: [place(ARPITA)] }),
  ];

  it("opens the same list the section was showing the top of", () => {
    const data = dashboard(mine);
    const section = myUpcomingSeva(data, ARPITA.id, NOW).slice(0, 3);

    expect(ids(section)).toEqual(["svc-1", "svc-2", "svc-3"]);
    expect(ids(myUpcomingSeva(data, ARPITA.id, NOW))).toEqual([
      "svc-1",
      "svc-2",
      "svc-3",
      "svc-4",
    ]);
  });

  it("orders my upcoming seva soonest first, so the top three are the next three", () => {
    const shuffled = dashboard([mine[2], mine[0], mine[3], mine[1]]);
    expect(ids(myUpcomingSeva(shuffled, ARPITA.id, NOW))).toEqual([
      "svc-1",
      "svc-2",
      "svc-3",
      "svc-4",
    ]);
  });

  it("keeps the community schedule to seva still to come", () => {
    // Anything finished has either lapsed into history or is waiting to be
    // closed off, and both are listed elsewhere on the same screen.
    const data = dashboard([
      service({ id: "past", date: TODAY, start_time: "09:00:00", participants: [place(ARPITA)] }),
      service({ id: "ahead", date: TOMORROW, participants: [place(ARPITA)] }),
    ]);

    expect(ids(communitySchedule(data, NOW))).toEqual(["ahead"]);
  });

  it("orders the community schedule soonest first", () => {
    const data = dashboard([
      service({ id: "later", date: "2026-08-09", participants: [place(ARPITA)] }),
      service({ id: "sooner", date: TOMORROW, participants: [place(ARPITA)] }),
    ]);

    expect(ids(communitySchedule(data, NOW))).toEqual(["sooner", "later"]);
  });

  it("orders recently completed newest first, so the top three are the latest", () => {
    const finished = (id: string, date: string) =>
      service({ id, date, start_time: "09:00:00", participants: [place(ARPITA)] });
    const data = dashboard([
      finished("older", "2026-08-01"),
      finished("newest", TODAY),
      finished("middle", "2026-08-02"),
    ]);

    expect(ids(recentlyCompletedServices(data, NOW))).toEqual([
      "newest",
      "middle",
      "older",
    ]);
  });

  it("never places one seva in two of the tab's sections at once", () => {
    // Each seva belongs to exactly one of upcoming, waiting and history. The
    // request lists overlap the schedule on purpose and are excluded here.
    const states = [
      service({ id: "ahead", date: TOMORROW, participants: [place(ARPITA)] }),
      service({ id: "waiting", date: TODAY, start_time: "09:00:00", participation_mode: "invite_only", participants: [place(ARPITA)] }),
      service({ id: "history", date: TODAY, start_time: "09:00:00", participants: [place(ARPITA)] }),
    ];
    const data = dashboard(states);
    const sections = [
      ids(upcomingServices(data, NOW)),
      ids(awaitingCompletionServices(data, NOW)),
      ids(recentlyCompletedServices(data, NOW)),
    ];

    expect(sections).toEqual([["ahead"], ["waiting"], ["history"]]);
    expect(new Set(sections.flat()).size).toBe(3);
  });
});

describe("a weekly occurrence the hourly sweep closed", () => {
  const swept = dashboard([
    service({
      id: "occ-1",
      template_id: "weekly-kitchen",
      date: TODAY,
      start_time: "05:00:00",
      duration_minutes: 90,
      status: "completed",
      participants: [
        place(ARPITA, {
          status: "completed",
          completed_at: "2026-08-04T11:30:00.000Z",
        }),
      ],
    }),
  ]);

  it("is history the moment it is closed, with nobody owed an answer", () => {
    expect(isSevaConfirmedServed(swept.services[0])).toBe(true);
    expect(ids(recentlyCompletedServices(swept, NOW))).toEqual(["occ-1"]);
    expect(awaitingCompletionServices(swept, NOW)).toEqual([]);
  });

  it("is never parked in a queue a roster slot has no poster to clear", () => {
    const notSweptYet = dashboard([
      service({
        id: "occ-1",
        template_id: "weekly-kitchen",
        date: TODAY,
        start_time: "05:00:00",
        duration_minutes: 90,
        status: "open",
        participants: [place(ARPITA)],
      }),
    ]);

    expect(awaitingCompletionServices(notSweptYet, NOW)).toEqual([]);
    expect(myUpcomingSeva(notSweptYet, ARPITA.id, NOW)).toEqual([]);
    // Not closed off, so not history either — it is simply over.
    expect(recentlyCompletedServices(notSweptYet, NOW)).toEqual([]);
  });
});

/**
 * "Weekly seva only one card and not multiple cards", said as a selector.
 *
 * A Monday/Thursday rota finishes twice a week. Every list that draws finished
 * seva goes through this fold, so neither the tab nor the See-all behind it can
 * decide to list the dates separately again.
 */
describe("finished weekly seva folds into one entry", () => {
  function occurrence(date: string): ServiceListItem {
    return service({
      id: `occ-${date}`,
      template_id: "weekly-garlands",
      custom_name: "Flower Garlands",
      name: "Flower Garlands",
      date,
      start_time: "05:00:00",
      status: "completed",
      participants: [
        place(ARPITA, { status: "completed", attendance: "served" }),
      ],
    });
  }

  const finished = [
    occurrence("2026-07-27"),
    occurrence("2026-07-30"),
    occurrence("2026-08-03"),
  ];

  it("gives one entry per weekly seva, however many dates it ran", () => {
    const folded = foldCompletedSeva(finished);

    expect(folded).toHaveLength(1);
    expect(folded[0].kind).toBe("weekly");
    expect(folded[0].name).toBe("Flower Garlands");
  });

  it("dates it by the most recent one that happened", () => {
    const [entry] = foldCompletedSeva(finished);

    expect(entry.kind === "weekly" && entry.latest.date).toBe("2026-08-03");
    expect(entry.kind === "weekly" && entry.occurrences).toHaveLength(3);
  });

  it("leaves one-off seva as its own entry", () => {
    const folded = foldCompletedSeva([
      ...finished,
      service({ id: "one-off", status: "completed", date: "2026-08-01" }),
    ]);

    expect(folded).toHaveLength(2);
    expect(folded.filter((entry) => entry.kind === "one_time")).toHaveLength(1);
  });

  it("orders the whole history by when each seva last happened", () => {
    const folded = foldCompletedSeva([
      ...finished,
      service({ id: "one-off", status: "completed", date: "2026-08-05" }),
    ]);

    expect(folded[0].kind).toBe("one_time");
  });

  it("credits the reader only where they actually served one of them", () => {
    expect(didServeAny(finished, ARPITA.id)).toBe(true);
    expect(didServeAny(finished, TANMAY.id)).toBe(false);
    expect(didServeAny(finished, null)).toBe(false);
  });
});

/**
 * The hours record and the absent devotee.
 *
 * Verifying a registration writes a place of its own, and a coordinator can
 * mark that place absent afterwards. Every list built from services already
 * asked; the registration branch of the report never did, so the spreadsheet —
 * the copy that leaves the building — credited a morning nobody served.
 */
describe("a registration whose place was marked absent", () => {
  const registration = {
    id: "reg-1",
    devotee_id: ARPITA.id,
    name: "Book Distribution",
    status: "verified",
    start_at: "2026-08-04T13:00:00.000Z",
    end_at: "2026-08-04T15:00:00.000Z",
    location_text: "ISKCON Chicago Temple",
    service_instance_id: "inst-1",
    devotee: ARPITA,
    verifier: TANMAY,
    verifiedBy: TANMAY,
    created_at: "2026-08-01T00:00:00.000Z",
  };

  function withInstance(attendance: string | null) {
    const data = dashboard([
      service({
        id: "inst-1",
        status: "closed",
        date: TODAY,
        participants: [place(ARPITA, { attendance: attendance as never })],
      }),
    ]);
    return { ...data, verifications: [registration] } as ServiceDashboard;
  }

  it("is left out of the report entirely", () => {
    expect(buildCompletedSevaRows(withInstance("absent"), NOW)).toHaveLength(0);
    expect(buildCompletedSevaRows(withInstance("excused"), NOW)).toHaveLength(0);
  });

  it("still counts where nobody said otherwise", () => {
    expect(buildCompletedSevaRows(withInstance(null), NOW)).toHaveLength(1);
    expect(buildCompletedSevaRows(withInstance("served"), NOW)).toHaveLength(1);
  });

  it("counts when the instance is out of reach, because silence is not absence", () => {
    const data = {
      ...dashboard([]),
      verifications: [registration],
    } as ServiceDashboard;

    expect(buildCompletedSevaRows(data, NOW)).toHaveLength(1);
  });
});
