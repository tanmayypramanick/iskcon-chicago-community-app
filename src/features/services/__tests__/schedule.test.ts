/// <reference types="jest" />

import {
  awaitingCompletionServices,
  communitySchedule,
  isSevaConfirmedServed,
  lapsedOpenRequests,
  myCompletedServices,
  myUpcomingOneTime,
  openOneTimeRequirements,
  recentlyCompletedServices,
  serviceSearchText,
  servingParticipants,
  unconfirmedAssignmentIds,
} from "../selectors";
import type { ServiceDashboard, ServiceListItem } from "../types";

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

/** 2026-08-04 14:11 CDT — the afternoon of an 11:00 AM seva. */
const NOW = new Date("2026-08-04T19:11:00.000Z");

function service(overrides: Record<string, unknown> = {}) {
  return {
    id: "svc-1",
    template_id: null,
    service_type_id: null,
    custom_name: "Kitchen Preparation",
    date: "2026-08-04",
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
    // Attendance answered by default: an unanswered place is the exception the
    // waiting list exists for, so the tests that mean it say so.
    participants: [
      {
        assignment: { id: "asg-1", status: "completed", attendance: "served" },
        devotee: ARPITA,
      },
    ],
    currentUserAssignment: { devotee_id: ARPITA.id, status: "completed" },
    currentUserOffer: null,
    postedByName: TANMAY.name,
    ...overrides,
  };
}

function dashboard(services: Array<ReturnType<typeof service>>) {
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
  } as unknown as ServiceDashboard;
}

/**
 * A month-long swap, as 0009 records it: Arpita's place is retired rather than
 * edited, and Tanmay gets a place of his own.
 */
const STOOD_DOWN = {
  assignment: { id: "asg-arpita", status: "withdrawn", attendance: null },
  devotee: ARPITA,
};
const SUBSTITUTE = {
  assignment: {
    id: "asg-tanmay",
    status: "confirmed",
    attendance: null,
    assignment_method: "accepted_coverage_offer",
  },
  devotee: TANMAY,
};

describe("a swapped seva names whoever is serving it now", () => {
  it("drops the devotee who stood down and keeps the substitute", () => {
    // The reported bug: covering Arpita's weekly seva for a month still showed
    // Arpita on the occurrence Tanmay was actually serving.
    const swapped = service({
      participants: [STOOD_DOWN, SUBSTITUTE],
    }) as unknown as ServiceListItem;

    expect(
      servingParticipants(swapped).map((row) => row.devotee.name),
    ).toEqual([TANMAY.name]);
    expect(serviceSearchText(swapped)).toContain("tanmay");
    expect(serviceSearchText(swapped)).not.toContain("arpita");
  });

  it("credits the completed seva to the substitute, not the original", () => {
    const data = dashboard([
      service({
        status: "completed",
        participants: [
          STOOD_DOWN,
          { ...SUBSTITUTE, assignment: { ...SUBSTITUTE.assignment, attendance: "served" } },
        ],
      }),
    ]);
    expect(myCompletedServices(data, TANMAY.id, NOW).map((row) => row.id)).toEqual([
      "svc-1",
    ]);
    expect(myCompletedServices(data, ARPITA.id, NOW)).toEqual([]);
  });

  it("never waits on a place that was handed over", () => {
    const swapped = service({
      status: "completed",
      participants: [STOOD_DOWN, SUBSTITUTE],
    }) as unknown as ServiceListItem;

    // Only Tanmay's place is owed an answer; Arpita's is not held open.
    expect(unconfirmedAssignmentIds(swapped)).toEqual(["asg-tanmay"]);
  });
});

describe("attendance is answered one devotee at a time", () => {
  const RAVI = { id: "ravi", name: "Ravi Das", photo_url: null, role_name: "volunteer" };
  const place = (id: string, devotee: typeof ARPITA, attendance: string | null) => ({
    assignment: { id, status: "completed", attendance },
    devotee,
  });

  it("still waits while any one devotee is unmarked", () => {
    const partly = service({
      status: "completed",
      slots_needed: 3,
      filledSlots: 3,
      participants: [
        place("asg-1", ARPITA, "served"),
        place("asg-2", TANMAY, null),
        place("asg-3", RAVI, "absent"),
      ],
    }) as unknown as ServiceListItem;

    expect(unconfirmedAssignmentIds(partly)).toEqual(["asg-2"]);
    expect(isSevaConfirmedServed(partly)).toBe(false);
    expect(
      awaitingCompletionServices(dashboard([partly as never]), NOW).map((row) => row.id),
    ).toEqual(["svc-1"]);
  });

  it("moves the seva into history the moment the last place is answered", () => {
    // One devotee served and another did not is still a complete answer — the
    // list is waiting on a mark, not on a particular mark.
    const answered = service({
      status: "completed",
      slots_needed: 3,
      filledSlots: 3,
      participants: [
        place("asg-1", ARPITA, "served"),
        place("asg-2", TANMAY, "excused"),
        place("asg-3", RAVI, "absent"),
      ],
    }) as unknown as ServiceListItem;
    const data = dashboard([answered as never]);

    expect(unconfirmedAssignmentIds(answered)).toEqual([]);
    expect(isSevaConfirmedServed(answered)).toBe(true);
    expect(awaitingCompletionServices(data, NOW)).toEqual([]);
    expect(recentlyCompletedServices(data, NOW).map((row) => row.id)).toEqual([
      "svc-1",
    ]);
  });
});

describe("a seva stops being upcoming when it ends, not when the day ends", () => {
  it("drops an 11 AM seva out of upcoming by the afternoon", () => {
    // The reported bug: Kitchen Preparation ran 11:00–12:00 and was still
    // listed as upcoming at 2:11 PM, because only the date was compared.
    const data = dashboard([service()]);
    expect(myUpcomingOneTime(data, ARPITA.id, NOW)).toEqual([]);
  });

  it("keeps a seva later the same day in upcoming", () => {
    const data = dashboard([service({ start_time: "18:00:00" })]);
    expect(myUpcomingOneTime(data, ARPITA.id, NOW)).toHaveLength(1);
  });

  it("keeps a seva that is running right now in upcoming", () => {
    // 14:00–15:00 contains 14:11, so it has not finished.
    const data = dashboard([service({ start_time: "14:00:00" })]);
    expect(myUpcomingOneTime(data, ARPITA.id, NOW)).toHaveLength(1);
  });

  it("stops offering an open request whose time has passed", () => {
    const data = dashboard([
      service({ participation_mode: "open", status: "open", participants: [] }),
    ]);
    expect(openOneTimeRequirements(data, NOW)).toEqual([]);
  });
});

describe("where a finished seva goes next", () => {
  it("lapses an open request into completed, served or not", () => {
    const lapsed = service({
      participation_mode: "open",
      status: "open",
      participants: [],
      filledSlots: 0,
    });
    const data = dashboard([lapsed]);

    expect(lapsedOpenRequests(data, NOW).map((row) => row.id)).toEqual(["svc-1"]);
    expect(recentlyCompletedServices(data, NOW).map((row) => row.id)).toEqual([
      "svc-1",
    ]);
    // Nobody owns an open request, so it is not waiting on anyone.
    expect(awaitingCompletionServices(data, NOW)).toEqual([]);
  });

  it("holds an assigned seva until whoever posted it closes it off", () => {
    const data = dashboard([service()]);

    expect(awaitingCompletionServices(data, NOW).map((row) => row.id)).toEqual([
      "svc-1",
    ]);
    // Not completed yet, so it must not appear as history.
    expect(recentlyCompletedServices(data, NOW)).toEqual([]);
    // The community schedule is what is still to come, so a finished seva has
    // left it — it is listed under "Waiting to be verified" instead.
    expect(communitySchedule(data, NOW)).toEqual([]);

    // Closed off, but nobody has said who served: still not history. This is
    // what the temple asked for — unconfirmed seva waits to be verified.
    const unconfirmed = dashboard([
      service({
        status: "completed",
        participants: [
          { assignment: { id: "asg-1", status: "completed" }, devotee: ARPITA },
        ],
      }),
    ]);
    expect(
      awaitingCompletionServices(unconfirmed, NOW).map((row) => row.id),
    ).toEqual(["svc-1"]);
    expect(recentlyCompletedServices(unconfirmed, NOW)).toEqual([]);
  });

  it("moves it to completed once who served is marked", () => {
    const data = dashboard([service({ status: "completed" })]);

    expect(recentlyCompletedServices(data, NOW).map((row) => row.id)).toEqual([
      "svc-1",
    ]);
    expect(awaitingCompletionServices(data, NOW)).toEqual([]);
    expect(communitySchedule(data, NOW)).toEqual([]);

    // 202608040059: a weekly occurrence earns its place on completion with no
    // confirmation owed, so it is history at once and never waits on anyone.
    const weekly = dashboard([
      service({
        status: "completed",
        template_id: "weekly-kitchen",
        participants: [
          { assignment: { id: "asg-1", status: "completed" }, devotee: ARPITA },
        ],
      }),
    ]);
    expect(recentlyCompletedServices(weekly, NOW).map((row) => row.id)).toEqual([
      "svc-1",
    ]);
    expect(awaitingCompletionServices(weekly, NOW)).toEqual([]);
  });

  it("never counts a cancelled seva as finished history", () => {
    const data = dashboard([service({ status: "cancelled" })]);
    expect(recentlyCompletedServices(data, NOW)).toEqual([]);
    expect(awaitingCompletionServices(data, NOW)).toEqual([]);
  });
});

describe("recently completed reads newest first", () => {
  it("puts the most recent seva on top", () => {
    const data = dashboard([
      service({ id: "morning", status: "completed", start_time: "06:00:00" }),
      service({ id: "evening", status: "completed", start_time: "18:00:00", date: "2026-08-03" }),
      service({ id: "midday", status: "completed", start_time: "11:00:00" }),
    ]);
    expect(recentlyCompletedServices(data, NOW).map((row) => row.id)).toEqual([
      "midday",
      "morning",
      "evening",
    ]);
  });
});

/**
 * The temple's complaint: "community schedule should have both weekly and
 * normal seva in there, not just weekly seva". The dated list carried only
 * one-off requests, so a coordinator reading Thursday could not see the weekly
 * seva that falls on it.
 */
describe("the community schedule carries both kinds", () => {
  const upcoming = { date: "2026-08-06", participants: [], filledSlots: 0 };

  it("puts weekly occurrences and one-off seva in one chronological list", () => {
    const data = dashboard([
      service({
        ...upcoming,
        id: "one-off-noon",
        start_time: "12:00:00",
        participation_mode: "invite_only",
      }),
      service({
        ...upcoming,
        id: "weekly-dawn",
        template_id: "weekly-garlands",
        start_time: "05:00:00",
      }),
      service({
        ...upcoming,
        id: "weekly-evening",
        template_id: "weekly-arati",
        start_time: "18:30:00",
      }),
    ]);

    expect(communitySchedule(data, NOW).map((row) => row.id)).toEqual([
      "weekly-dawn",
      "one-off-noon",
      "weekly-evening",
    ]);
  });

  it("keeps a weekly occurrence nobody has joined yet, unlike an open request", () => {
    // A weekly seva is the temple's own standing arrangement: it is planned
    // whoever ends up on it. An open one-off with nobody on it is still only a
    // request, and stays where requests are read.
    const data = dashboard([
      service({
        ...upcoming,
        id: "weekly-open",
        template_id: "weekly-garlands",
        participation_mode: "open",
        status: "open",
      }),
      service({
        ...upcoming,
        id: "request-open",
        participation_mode: "open",
        status: "open",
      }),
    ]);

    expect(communitySchedule(data, NOW).map((row) => row.id)).toEqual([
      "weekly-open",
    ]);
  });

  it("still shows only what is still to come", () => {
    // 11:00 AM, an hour long, read at 2:11 PM the same day.
    const data = dashboard([
      service({ id: "finished-weekly", template_id: "weekly-garlands" }),
    ]);

    expect(communitySchedule(data, NOW)).toEqual([]);
  });
});

describe("an open request that is partly filled is in both lists", () => {
  const upcoming = { date: "2026-08-06", start_time: "09:00:00" };

  it("is only a request while nobody has joined", () => {
    const data = dashboard([
      service({
        ...upcoming,
        participation_mode: "open",
        status: "open",
        slots_needed: 3,
        filledSlots: 0,
        participants: [],
      }),
    ]);
    expect(openOneTimeRequirements(data, NOW).map((row) => row.id)).toEqual([
      "svc-1",
    ]);
    expect(communitySchedule(data, NOW)).toEqual([]);
  });

  it("is in both once someone joins and places remain", () => {
    // One devotee joining a seva that needs three does not mean the other two
    // places have been found.
    const data = dashboard([
      service({
        ...upcoming,
        participation_mode: "open",
        status: "open",
        slots_needed: 3,
        filledSlots: 1,
      }),
    ]);
    expect(openOneTimeRequirements(data, NOW).map((row) => row.id)).toEqual([
      "svc-1",
    ]);
    expect(communitySchedule(data, NOW).map((row) => row.id)).toEqual([
      "svc-1",
    ]);
  });

  it("leaves the request list once every place is filled", () => {
    const data = dashboard([
      service({
        ...upcoming,
        participation_mode: "open",
        status: "full",
        slots_needed: 1,
        filledSlots: 1,
      }),
    ]);
    expect(openOneTimeRequirements(data, NOW)).toEqual([]);
    expect(communitySchedule(data, NOW).map((row) => row.id)).toEqual([
      "svc-1",
    ]);
  });
});
