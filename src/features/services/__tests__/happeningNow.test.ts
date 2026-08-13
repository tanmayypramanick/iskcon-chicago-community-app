/// <reference types="jest" />

import { sevaHappeningNow } from "../selectors";
import type { ServiceDashboard } from "../types";

const ARPITA = { id: "arpita", name: "Arpita Jadhav", photo_url: null, role_name: "devotee" };
const TANMAY = { id: "tanmay", name: "Tanmay Pramanick", photo_url: null, role_name: "president" };
const RAVI = { id: "ravi", name: "Ravi Das", photo_url: null, role_name: "volunteer" };

/** 2026-08-03 18:30 CDT — a Monday evening at the temple. */
const NOW = new Date("2026-08-03T23:30:00.000Z");

function service(overrides: Record<string, unknown> = {}) {
  return {
    id: "svc-1",
    template_id: null,
    service_type_id: null,
    custom_name: "Pot Washing",
    date: "2026-08-03",
    start_time: "18:00:00",
    duration_minutes: 60,
    slots_needed: 2,
    participation_mode: "open",
    posted_by: RAVI.id,
    status: "open",
    created_at: NOW.toISOString(),
    name: "Pot Washing",
    serviceType: null,
    filledSlots: 1,
    participants: [
      { assignment: { id: "asg-arpita", status: "confirmed" }, devotee: ARPITA },
    ],
    currentUserAssignment: null,
    currentUserOffer: null,
    postedByName: RAVI.name,
    ...overrides,
  };
}

function dashboard(overrides: Partial<ServiceDashboard> = {}) {
  return {
    serviceTypes: [],
    devotees: [ARPITA, TANMAY, RAVI],
    services: [service()],
    pendingOffers: [],
    recurringTemplates: [],
    pendingRecurringOffers: [],
    coverageRequests: [],
    coveragePlans: [],
    activeSessions: [],
    activitySessions: [],
    recurringInterests: [],
    myVerifications: [],
    verificationInbox: [],
    offerCounters: [],
    ...overrides,
  } as unknown as ServiceDashboard;
}

const COORDINATOR = { seesEveryone: true, seesOwnPosts: true };
const VOLUNTEER = { seesEveryone: false, seesOwnPosts: true };
const DEVOTEE = { seesEveryone: false, seesOwnPosts: false };

describe("seva happening now", () => {
  it("includes a dated seva whose Chicago window contains this moment", () => {
    const entries = sevaHappeningNow(
      dashboard(),
      { userId: TANMAY.id, ...COORDINATOR },
      NOW,
    );
    expect(entries).toHaveLength(1);
    expect(entries[0]).toMatchObject({ kind: "one_time", name: "Pot Washing" });
  });

  it("excludes a seva that has not started or has already ended", () => {
    const notYet = dashboard({
      services: [service({ start_time: "20:00:00" })] as never,
    });
    const over = dashboard({
      services: [service({ start_time: "09:00:00" })] as never,
    });
    const scope = { userId: TANMAY.id, ...COORDINATOR };
    expect(sevaHappeningNow(notYet, scope, NOW)).toHaveLength(0);
    expect(sevaHappeningNow(over, scope, NOW)).toHaveLength(0);
  });

  it("uses Chicago's clock, not the device's", () => {
    // 23:30 UTC is 18:30 in Chicago but already the next day in London/Kolkata.
    // The seva is dated 2026-08-03 Chicago and must still be found.
    const entries = sevaHappeningNow(
      dashboard(),
      { userId: TANMAY.id, ...COORDINATOR },
      NOW,
    );
    expect(entries).toHaveLength(1);
  });

  it("excludes a seva nobody is serving", () => {
    const empty = dashboard({
      services: [service({ participants: [], filledSlots: 0 })] as never,
    });
    expect(
      sevaHappeningNow(empty, { userId: TANMAY.id, ...COORDINATOR }, NOW),
    ).toHaveLength(0);

    // A seva whose only devotee handed it over is nobody's seva either, so it
    // must not be listed at the temple under their name.
    const handedOver = dashboard({
      services: [
        service({
          participants: [
            { assignment: { id: "asg-arpita", status: "withdrawn" }, devotee: ARPITA },
          ],
        }),
      ] as never,
    });
    expect(
      sevaHappeningNow(handedOver, { userId: TANMAY.id, ...COORDINATOR }, NOW),
    ).toHaveLength(0);
  });

  describe("scope by access level", () => {
    it("shows a Community Head, Tech Admin or President the whole temple", () => {
      expect(
        sevaHappeningNow(dashboard(), { userId: TANMAY.id, ...COORDINATOR }, NOW),
      ).toHaveLength(1);
    });

    it("shows a Devotee only the seva they are serving", () => {
      expect(
        sevaHappeningNow(dashboard(), { userId: ARPITA.id, ...DEVOTEE }, NOW),
      ).toHaveLength(1);
      expect(
        sevaHappeningNow(dashboard(), { userId: "someone-else", ...DEVOTEE }, NOW),
      ).toHaveLength(0);
    });

    it("shows a Volunteer their own seva and the seva they posted", () => {
      // Ravi posted it but is not serving it.
      expect(
        sevaHappeningNow(dashboard(), { userId: RAVI.id, ...VOLUNTEER }, NOW),
      ).toHaveLength(1);
      // Another volunteer neither serves nor posted it.
      expect(
        sevaHappeningNow(dashboard(), { userId: "other-vol", ...VOLUNTEER }, NOW),
      ).toHaveLength(0);
    });
  });

});

describe("a weekly seva under coverage names the substitute", () => {
  /** Monday, in the middle of the month Tanmay is covering for Arpita. */
  const template = {
    id: "weekly-deity-flowers",
    name: "Deity Flowers",
    active: true,
    participation_mode: "open",
    days_of_week: [1],
    start_time: "18:00:00",
    duration_minutes: 60,
    slots_needed: 1,
    created_by: TANMAY.id,
    assignees: [{ ...ARPITA, assignedDays: [1] }],
  };
  const plan = {
    id: "plan-1",
    service_template_id: template.id,
    status: "accepted",
    days_of_week: [1],
    date_from: "2026-08-01",
    date_to: "2026-08-31",
    original_devotee_id: ARPITA.id,
    substitute_devotee_id: TANMAY.id,
  };
  const scope = { userId: TANMAY.id, ...COORDINATOR };

  function weekly(coveragePlans: unknown[]) {
    return sevaHappeningNow(
      dashboard({
        services: [],
        recurringTemplates: [template] as never,
        coveragePlans: coveragePlans as never,
      }),
      scope,
      NOW,
    );
  }

  it("shows the standing devotee when nobody is covering", () => {
    expect(weekly([])[0]?.people.map((person) => person.name)).toEqual([
      ARPITA.name,
    ]);
  });

  it("shows the substitute for every date the swap covers", () => {
    // The temple's words: swapped for a month, so the swapped devotee's name
    // belongs on that seva — not the one who used to serve it.
    expect(weekly([plan])[0]?.people.map((person) => person.name)).toEqual([
      TANMAY.name,
    ]);
  });

  it("hands the seva back once the swap has run out", () => {
    const past = { ...plan, date_from: "2026-07-01", date_to: "2026-07-31" };
    expect(weekly([past])[0]?.people.map((person) => person.name)).toEqual([
      ARPITA.name,
    ]);
  });

  it("ignores a swap nobody has accepted yet", () => {
    const pending = { ...plan, status: "pending" };
    expect(weekly([pending])[0]?.people.map((person) => person.name)).toEqual([
      ARPITA.name,
    ]);
  });
});

describe("no double display", () => {
  it("omits an instance that is already shown as a registration card", () => {
    const scope = { userId: TANMAY.id, ...COORDINATOR };
    expect(sevaHappeningNow(dashboard(), scope, NOW)).toHaveLength(1);
    expect(
      sevaHappeningNow(
        dashboard(),
        { ...scope, excludeInstanceIds: new Set(["svc-1"]) },
        NOW,
      ),
    ).toHaveLength(0);
  });
});
