/// <reference types="jest" />

import {
  canRemoveRegistration,
  completedRegistrations,
  myUnverifiedRegistrations,
  registrationInstanceIds,
  registrationsHappeningNow,
  sevaTiming,
  upcomingRegistrations,
  visibleRegistrations,
} from "../registrations";
import type { ServiceDashboard, ServiceVerification } from "../types";

const ARPITA = { id: "arpita", name: "Arpita Jadhav", photo_url: null, role_name: "devotee" };
const RAVI = { id: "ravi", name: "Ravi Das", photo_url: null, role_name: "devotee" };
const TANMAY = { id: "tanmay", name: "Tanmay Pramanick", photo_url: null, role_name: "president" };

/** 2026-08-04 18:30 CDT. */
const NOW = new Date("2026-08-04T23:30:00.000Z");

function reg(overrides: Partial<ServiceVerification> = {}): ServiceVerification {
  return {
    id: "reg-1",
    devotee_id: ARPITA.id,
    service_type_id: null,
    custom_name: "Pot Washing",
    // 18:00 - 19:00 CDT, so NOW sits inside it.
    start_at: "2026-08-04T23:00:00.000Z",
    end_at: "2026-08-05T00:00:00.000Z",
    location_text: "ISKCON Chicago Temple",
    verifier_id: TANMAY.id,
    status: "pending",
    review_note: null,
    service_instance_id: null,
    verified_by: null,
    created_at: "2026-08-04T22:00:00.000Z",
    responded_at: null,
    name: "Pot Washing",
    devotee: ARPITA,
    verifier: TANMAY,
    verifiedBy: null,
    ...overrides,
  } as ServiceVerification;
}

function dash(rows: ServiceVerification[], mine = ARPITA.id): ServiceDashboard {
  return {
    verifications: rows,
    myVerifications: rows.filter((r) => r.devotee_id === mine),
    verificationInbox: [],
  } as unknown as ServiceDashboard;
}

const OWNER = { userId: ARPITA.id, seesEveryone: false };
const COORDINATOR = { userId: TANMAY.id, seesEveryone: true };
const OTHER_DEVOTEE = { userId: "someone", seesEveryone: false };

describe("registered seva timing", () => {
  it("places a seva by the clock, not by its status", () => {
    expect(sevaTiming(reg(), NOW)).toBe("now");
    expect(
      sevaTiming(
        reg({ start_at: "2026-08-05T02:00:00.000Z", end_at: "2026-08-05T03:00:00.000Z" }),
        NOW,
      ),
    ).toBe("upcoming");
    expect(
      sevaTiming(
        reg({ start_at: "2026-08-04T20:00:00.000Z", end_at: "2026-08-04T21:00:00.000Z" }),
        NOW,
      ),
    ).toBe("finished");
  });

  it("treats the exact boundaries correctly", () => {
    const exactStart = reg({ start_at: NOW.toISOString() });
    expect(sevaTiming(exactStart, NOW)).toBe("now");
    const exactEnd = reg({
      start_at: "2026-08-04T22:30:00.000Z",
      end_at: NOW.toISOString(),
    });
    // The end instant is no longer "now" — it has finished.
    expect(sevaTiming(exactEnd, NOW)).toBe("finished");
  });

  it("is unaffected by verification status", () => {
    for (const status of ["pending", "verified", "declined"] as const) {
      expect(sevaTiming(reg({ status }), NOW)).toBe("now");
    }
  });
});

describe("who may see a registration", () => {
  it("keeps an unverified registration to the devotee who registered it", () => {
    const rows = [reg({ status: "pending" })];
    expect(visibleRegistrations(dash(rows), OWNER)).toHaveLength(1);
    expect(visibleRegistrations(dash(rows), COORDINATOR)).toHaveLength(0);
    expect(visibleRegistrations(dash(rows), OTHER_DEVOTEE)).toHaveLength(0);
  });

  it("keeps a declined registration private too", () => {
    const rows = [reg({ status: "declined", responded_at: NOW.toISOString() })];
    expect(visibleRegistrations(dash(rows), OWNER)).toHaveLength(1);
    expect(visibleRegistrations(dash(rows), COORDINATOR)).toHaveLength(0);
  });

  it("shares a verified registration with everyone who may see seva", () => {
    const rows = [
      reg({ status: "verified", verified_by: TANMAY.id, verifiedBy: TANMAY }),
    ];
    expect(visibleRegistrations(dash(rows), OWNER)).toHaveLength(1);
    expect(visibleRegistrations(dash(rows), COORDINATOR)).toHaveLength(1);
    // A different devotee still has no business seeing it.
    expect(visibleRegistrations(dash(rows), OTHER_DEVOTEE)).toHaveLength(0);
  });
});

describe("seva lists", () => {
  it("shows an unverified in-progress seva to its own devotee only", () => {
    const rows = [reg({ status: "pending" })];
    expect(registrationsHappeningNow(dash(rows), OWNER, NOW)).toHaveLength(1);
    expect(registrationsHappeningNow(dash(rows), COORDINATOR, NOW)).toHaveLength(0);
  });

  it("shows a verified in-progress seva to coordinators as well", () => {
    const rows = [
      reg({ status: "verified", verified_by: TANMAY.id, verifiedBy: TANMAY }),
    ];
    expect(registrationsHappeningNow(dash(rows), OWNER, NOW)).toHaveLength(1);
    expect(registrationsHappeningNow(dash(rows), COORDINATOR, NOW)).toHaveLength(1);
  });

  it("puts a future registration in upcoming, never in happening now", () => {
    const rows = [
      reg({
        start_at: "2026-08-06T23:00:00.000Z",
        end_at: "2026-08-07T00:00:00.000Z",
        status: "verified",
        verified_by: TANMAY.id,
        verifiedBy: TANMAY,
      }),
    ];
    expect(registrationsHappeningNow(dash(rows), COORDINATOR, NOW)).toHaveLength(0);
    expect(upcomingRegistrations(dash(rows), COORDINATOR, NOW)).toHaveLength(1);
  });

  it("never lists a finished but unverified seva as completed", () => {
    const finishedPending = reg({
      start_at: "2026-08-04T20:00:00.000Z",
      end_at: "2026-08-04T21:00:00.000Z",
      status: "pending",
    });
    expect(completedRegistrations(dash([finishedPending]), OWNER, NOW)).toHaveLength(0);
    // It stays in the devotee's waiting list instead.
    expect(myUnverifiedRegistrations(dash([finishedPending]), ARPITA.id)).toHaveLength(1);
  });

  it("lists a finished and verified seva as completed for both sides", () => {
    const rows = [
      reg({
        start_at: "2026-08-04T20:00:00.000Z",
        end_at: "2026-08-04T21:00:00.000Z",
        status: "verified",
        verified_by: TANMAY.id,
        verifiedBy: TANMAY,
      }),
    ];
    expect(completedRegistrations(dash(rows), OWNER, NOW)).toHaveLength(1);
    expect(completedRegistrations(dash(rows), COORDINATOR, NOW)).toHaveLength(1);
  });

  it("orders upcoming soonest first and completed most recent first", () => {
    const rows = [
      reg({ id: "a", start_at: "2026-08-07T23:00:00.000Z", end_at: "2026-08-08T00:00:00.000Z" }),
      reg({ id: "b", start_at: "2026-08-05T23:00:00.000Z", end_at: "2026-08-06T00:00:00.000Z" }),
    ];
    expect(upcomingRegistrations(dash(rows), OWNER, NOW).map((r) => r.id)).toEqual(["b", "a"]);

    const done = [
      reg({ id: "old", start_at: "2026-08-01T20:00:00.000Z", end_at: "2026-08-01T21:00:00.000Z", status: "verified" }),
      reg({ id: "recent", start_at: "2026-08-04T20:00:00.000Z", end_at: "2026-08-04T21:00:00.000Z", status: "verified" }),
    ];
    expect(completedRegistrations(dash(done), OWNER, NOW).map((r) => r.id)).toEqual([
      "recent",
      "old",
    ]);
  });

  it("keeps a devotee's waiting list free of other devotees' registrations", () => {
    const rows = [reg(), reg({ id: "other", devotee_id: RAVI.id, devotee: RAVI })];
    const mine = myUnverifiedRegistrations(dash(rows), ARPITA.id);
    expect(mine).toHaveLength(1);
    expect(mine[0].devotee_id).toBe(ARPITA.id);
  });
});

describe("removing a registration", () => {
  it("allows the devotee who registered it", () => {
    expect(canRemoveRegistration(reg(), ARPITA.id, false)).toBe(true);
  });

  it("allows a Community Head, Tech Admin or President", () => {
    expect(canRemoveRegistration(reg(), TANMAY.id, true)).toBe(true);
  });

  it("refuses an unrelated devotee", () => {
    expect(canRemoveRegistration(reg(), RAVI.id, false)).toBe(false);
  });
});

describe("no double display", () => {
  it("collects the instance ids that belong to registrations", () => {
    const rows = [
      reg({ id: "a", status: "verified", service_instance_id: "inst-1" }),
      reg({ id: "b", status: "pending", service_instance_id: null }),
      reg({ id: "c", status: "verified", service_instance_id: "inst-2" }),
    ];
    const ids = registrationInstanceIds(dash(rows));
    expect([...ids].sort()).toEqual(["inst-1", "inst-2"]);
  });

  it("is empty when nothing has been verified yet", () => {
    expect(registrationInstanceIds(dash([reg()])).size).toBe(0);
  });
});

describe("the clock moving a seva between sections", () => {
  // A verified seva running 18:00-19:00 CDT on 4 August.
  const verified = reg({
    status: "verified",
    verified_by: TANMAY.id,
    verifiedBy: TANMAY,
    start_at: "2026-08-04T23:00:00.000Z",
    end_at: "2026-08-05T00:00:00.000Z",
  });
  const board = dash([verified]);

  it("moves from upcoming, to happening now, to completed as time passes", () => {
    const before = new Date("2026-08-04T22:00:00.000Z"); // an hour early
    const during = new Date("2026-08-04T23:30:00.000Z"); // halfway through
    const after = new Date("2026-08-05T09:00:00.000Z"); // the next morning

    expect(upcomingRegistrations(board, OWNER, before)).toHaveLength(1);
    expect(registrationsHappeningNow(board, OWNER, before)).toHaveLength(0);
    expect(completedRegistrations(board, OWNER, before)).toHaveLength(0);

    expect(upcomingRegistrations(board, OWNER, during)).toHaveLength(0);
    expect(registrationsHappeningNow(board, OWNER, during)).toHaveLength(1);
    expect(completedRegistrations(board, OWNER, during)).toHaveLength(0);

    // This is the case that was showing wrongly on the phone: hours after the
    // seva ended it must read as completed, not as happening now.
    expect(upcomingRegistrations(board, OWNER, after)).toHaveLength(0);
    expect(registrationsHappeningNow(board, OWNER, after)).toHaveLength(0);
    expect(completedRegistrations(board, OWNER, after)).toHaveLength(1);
  });

  it("never places one seva in two sections at the same instant", () => {
    for (const at of [
      "2026-08-04T22:00:00.000Z",
      "2026-08-04T23:00:00.000Z",
      "2026-08-04T23:59:59.000Z",
      "2026-08-05T00:00:00.000Z",
      "2026-08-05T09:00:00.000Z",
    ]) {
      const now = new Date(at);
      const total =
        upcomingRegistrations(board, OWNER, now).length +
        registrationsHappeningNow(board, OWNER, now).length +
        completedRegistrations(board, OWNER, now).length;
      expect(total).toBe(1);
    }
  });
});
