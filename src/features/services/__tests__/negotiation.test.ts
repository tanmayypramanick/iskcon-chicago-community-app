/// <reference types="jest" />

// api.ts reaches for a Supabase client at import time; nothing here calls the
// network, so the module is stubbed rather than the whole client being faked.
jest.mock("../../../lib/supabase", () => ({ getSupabaseClient: jest.fn() }));

import { assembleDashboard } from "../api";
import { errorMessage } from "../format";
import {
  isServingOn,
  myUpcomingSeva,
  sevaNeedingMyAnswer,
} from "../selectors";
import type {
  ServiceAssignmentRow,
  ServiceDevotee,
  ServiceInstanceRow,
  ServiceOfferCounterRow,
  ServiceOfferRow,
} from "../types";

/**
 * The three devotees a negotiation needs: whoever posted the seva, whoever was
 * asked, and somebody with no part in it whose view must stay empty.
 */
const TANMAY: ServiceDevotee = {
  id: "tanmay",
  name: "Tanmay Pramanick",
  photo_url: null,
  role_name: "volunteer",
};
const ARPITA: ServiceDevotee = {
  id: "arpita",
  name: "Arpita Jadhav",
  photo_url: null,
  role_name: "devotee",
};
const PRESIDENT: ServiceDevotee = {
  id: "president",
  name: "Temple President",
  photo_url: null,
  role_name: "president",
};

/** 2026-08-04 14:11 CDT. */
const NOW = new Date("2026-08-04T19:11:00.000Z");

function instance(
  overrides: Partial<ServiceInstanceRow> = {},
): ServiceInstanceRow {
  return {
    id: "svc-1",
    template_id: null,
    service_type_id: null,
    custom_name: "Kitchen Preparation",
    date: "2026-08-08",
    start_time: "11:00:00",
    duration_minutes: 60,
    slots_needed: 2,
    participation_mode: "invite_only",
    posted_by: TANMAY.id,
    status: "open",
    created_at: "2026-08-01T00:00:00.000Z",
    ...overrides,
  };
}

function offer(overrides: Partial<ServiceOfferRow> = {}): ServiceOfferRow {
  return {
    id: "offer-1",
    service_instance_id: "svc-1",
    service_template_id: null,
    service_exception_id: null,
    service_coverage_plan_id: null,
    offered_to: ARPITA.id,
    offered_by: TANMAY.id,
    offer_kind: "one_time",
    status: "pending",
    created_at: "2026-08-01T00:00:00.000Z",
    responded_at: null,
    ...overrides,
  };
}

function counter(
  overrides: Partial<ServiceOfferCounterRow> = {},
): ServiceOfferCounterRow {
  return {
    id: "counter-1",
    service_offer_id: "offer-1",
    devotee_id: ARPITA.id,
    proposed_days: [],
    proposed_date: "2026-08-09",
    proposed_start_time: "16:00:00",
    proposed_duration_minutes: 120,
    note: "I finish work at three.",
    status: "pending",
    review_note: null,
    created_at: "2026-08-02T00:00:00.000Z",
    responded_at: null,
    responded_by: null,
    ...overrides,
  };
}

function assignment(
  overrides: Partial<ServiceAssignmentRow> = {},
): ServiceAssignmentRow {
  return {
    id: "asg-1",
    service_instance_id: "svc-1",
    devotee_id: ARPITA.id,
    assignment_method: "accepted_offer",
    assigned_by: TANMAY.id,
    status: "confirmed",
    attendance: null,
    verification: "self_report",
    qr_scanned_at: null,
    created_at: "2026-08-02T00:00:00.000Z",
    completed_at: null,
    ...overrides,
  };
}

/** The dashboard as one signed-in account receives it, from real row-sets. */
function build(
  userId: string,
  rows: {
    instances?: ServiceInstanceRow[];
    offers?: ServiceOfferRow[];
    counters?: ServiceOfferCounterRow[];
    assignments?: ServiceAssignmentRow[];
  } = {},
) {
  return assembleDashboard(userId, {
    serviceTypes: [],
    instanceRows: rows.instances ?? [instance()],
    assignments: rows.assignments ?? [],
    offers: rows.offers ?? [],
    templates: [],
    templateAssignees: [],
    exceptions: [],
    coveragePlans: [],
    interests: [],
    verifications: [],
    counters: rows.counters ?? [],
    devotees: [TANMAY, ARPITA, PRESIDENT],
  });
}

const ids = (rows: Array<{ id: string }>) => rows.map((row) => row.id);

describe("being asked to take a seva", () => {
  it("puts a pending invitation in front of the devotee asked, and nobody else", () => {
    const asked = build(ARPITA.id, { offers: [offer()] });
    expect(ids(asked.pendingOffers.map((row) => row.offer))).toEqual(["offer-1"]);
    expect(build(TANMAY.id, { offers: [offer()] }).pendingOffers).toEqual([]);
  });

  it("names who is asking, so the devotee knows whose request it is", () => {
    const [pending] = build(ARPITA.id, { offers: [offer()] }).pendingOffers;
    expect(pending.offeredByName).toBe(TANMAY.name);
    expect(pending.service.date).toBe("2026-08-08");
    expect(pending.service.start_time).toBe("11:00:00");
  });

  it("stops offering an invitation once it has been answered", () => {
    for (const status of ["accepted", "declined", "expired", "countered"] as const) {
      expect(build(ARPITA.id, { offers: [offer({ status })] }).pendingOffers)
        .toEqual([]);
    }
  });
});

describe("a decline leaves the poster something to do", () => {
  it("tells the poster the place still needs filling", () => {
    const data = build(TANMAY.id, {
      offers: [offer({ status: "declined", responded_at: "2026-08-02T00:00:00.000Z" })],
    });
    const mine = sevaNeedingMyAnswer(data, TANMAY.id, false);

    expect(mine).toHaveLength(1);
    expect(mine[0].kind).toBe("declined");
    expect(mine[0].devoteeName).toBe(ARPITA.name);
  });

  it("says nothing once the places are filled anyway", () => {
    // Somebody else stepped in. The decline is no longer a hole to fill, and
    // a card asking the poster to act on it would be asking for nothing.
    const data = build(TANMAY.id, {
      offers: [offer({ status: "declined" })],
      instances: [instance({ slots_needed: 1 })],
      assignments: [assignment({ devotee_id: PRESIDENT.id })],
    });
    expect(sevaNeedingMyAnswer(data, TANMAY.id, false)).toEqual([]);
  });

  it("says nothing about a seva that is over or called off", () => {
    for (const status of ["completed", "cancelled"] as const) {
      const data = build(TANMAY.id, {
        offers: [offer({ status: "declined" })],
        instances: [instance({ status })],
      });
      expect(sevaNeedingMyAnswer(data, TANMAY.id, false)).toEqual([]);
    }
  });

  it("does not show the devotee their own decline as work to do", () => {
    // RLS hands Arpita the offer she answered. It is not hers to act on.
    const data = build(ARPITA.id, { offers: [offer({ status: "declined" })] });
    expect(sevaNeedingMyAnswer(data, ARPITA.id, false)).toEqual([]);
  });
});

describe("a suggested time waits on the poster", () => {
  const countered = {
    offers: [offer({ status: "countered" })],
    counters: [counter()],
  };

  it("carries the suggestion itself, not merely that there is one", () => {
    const [item] = sevaNeedingMyAnswer(build(TANMAY.id, countered), TANMAY.id, false);

    expect(item.kind).toBe("countered");
    expect(item.counter?.proposed_date).toBe("2026-08-09");
    expect(item.counter?.proposed_start_time).toBe("16:00:00");
    expect(item.counter?.note).toBe("I finish work at three.");
  });

  it("stops asking once the suggestion has been answered", () => {
    for (const status of ["approved", "declined"] as const) {
      const data = build(TANMAY.id, {
        offers: [offer({ status: "countered" })],
        counters: [counter({ status })],
      });
      expect(sevaNeedingMyAnswer(data, TANMAY.id, false)).toEqual([]);
    }
  });

  it("does not raise a counter whose offer was never marked countered", () => {
    const data = build(TANMAY.id, {
      offers: [offer({ status: "pending" })],
      counters: [counter()],
    });
    expect(sevaNeedingMyAnswer(data, TANMAY.id, false)).toEqual([]);
  });
});

/**
 * The gap this file was written for. `respond_to_service_offer_counter` accepts
 * the poster *or* `app.view_all`, so a Tech Admin and the President can answer
 * a counter on somebody else's seva — and were being shown nothing to answer.
 */
describe("who is shown an answer they are permitted to give", () => {
  const countered = {
    offers: [offer({ status: "countered" })],
    counters: [counter()],
  };

  it("shows the poster their own seva", () => {
    const data = build(TANMAY.id, countered);
    expect(sevaNeedingMyAnswer(data, TANMAY.id, false)).toHaveLength(1);
  });

  it("shows a Tech Admin or the President a counter on a seva they did not post", () => {
    const data = build(PRESIDENT.id, countered);
    expect(sevaNeedingMyAnswer(data, PRESIDENT.id, true)).toHaveLength(1);
  });

  it("shows a Community Head nothing — the RPC would refuse them", () => {
    // `services.resolve_coverage` is not `app.view_all`. Offering the button
    // would produce a refusal the coordinator could do nothing about.
    const data = build("core-devotee", countered);
    expect(sevaNeedingMyAnswer(data, "core-devotee", false)).toEqual([]);
  });

  it("shows a devotee with no part in it nothing", () => {
    const data = build(ARPITA.id, countered);
    expect(sevaNeedingMyAnswer(data, ARPITA.id, false)).toEqual([]);
  });

  it("shows nothing to a signed-out account rather than everything", () => {
    expect(sevaNeedingMyAnswer(build(TANMAY.id, countered), null, false)).toEqual(
      [],
    );
  });
});

describe("the poster accepts the suggested time", () => {
  /**
   * The state 0024 leaves behind: the instance moved to the proposed date,
   * time and length, a confirmed `accepted_offer` place for the devotee who
   * suggested it, the offer accepted and the counter approved.
   */
  const afterAccepting = () =>
    build(ARPITA.id, {
      instances: [
        instance({
          date: "2026-08-09",
          start_time: "16:00:00",
          duration_minutes: 120,
          status: "open",
        }),
      ],
      offers: [offer({ status: "accepted", responded_at: NOW.toISOString() })],
      counters: [counter({ status: "approved", responded_by: TANMAY.id })],
      assignments: [assignment()],
    });

  it("moves the seva to the time that was proposed", () => {
    const [moved] = myUpcomingSeva(afterAccepting(), ARPITA.id, NOW);

    expect(moved.date).toBe("2026-08-09");
    expect(moved.start_time).toBe("16:00:00");
    expect(moved.duration_minutes).toBe(120);
  });

  it("lands it in the proposer's own upcoming seva", () => {
    const data = afterAccepting();

    expect(ids(myUpcomingSeva(data, ARPITA.id, NOW))).toEqual(["svc-1"]);
    expect(isServingOn(data.services[0], ARPITA.id)).toBe(true);
  });

  it("leaves the poster nothing further to answer", () => {
    const data = build(TANMAY.id, {
      instances: [instance({ date: "2026-08-09", start_time: "16:00:00" })],
      offers: [offer({ status: "accepted" })],
      counters: [counter({ status: "approved" })],
      assignments: [assignment()],
    });
    expect(sevaNeedingMyAnswer(data, TANMAY.id, false)).toEqual([]);
  });
});

describe("the poster declines the suggested time", () => {
  /** 0024 declines the offer and the counter; the instance is untouched. */
  const afterDeclining = (userId: string) =>
    build(userId, {
      offers: [offer({ status: "declined", responded_at: NOW.toISOString() })],
      counters: [counter({ status: "declined", responded_by: TANMAY.id })],
    });

  it("leaves the seva at its original time", () => {
    const [seva] = afterDeclining(TANMAY.id).services;

    expect(seva.date).toBe("2026-08-08");
    expect(seva.start_time).toBe("11:00:00");
    expect(seva.duration_minutes).toBe(60);
  });

  it("puts nobody on it", () => {
    const data = afterDeclining(ARPITA.id);

    expect(myUpcomingSeva(data, ARPITA.id, NOW)).toEqual([]);
    expect(data.services[0].filledSlots).toBe(0);
  });

  it("reopens it as a place the poster still has to fill", () => {
    // The counter is answered, but the underlying "no" is not — the seva is
    // still short. Losing this is how a request quietly went unfilled.
    const mine = sevaNeedingMyAnswer(afterDeclining(TANMAY.id), TANMAY.id, false);

    expect(mine).toHaveLength(1);
    expect(mine[0].kind).toBe("declined");
  });
});

describe("somebody else joins before the suggestion is answered", () => {
  it("still shows the poster the suggestion, because it is still pending", () => {
    const data = build(TANMAY.id, {
      offers: [offer({ status: "countered" })],
      counters: [counter()],
      assignments: [assignment({ id: "asg-other", devotee_id: PRESIDENT.id })],
    });
    expect(sevaNeedingMyAnswer(data, TANMAY.id, false)).toHaveLength(1);
  });

  it("passes the server's refusal through to the devotee word for word", () => {
    // 0024 refuses to move a seva other devotees have joined. The screen shows
    // whatever comes back, so the refusal has to survive `errorMessage` intact
    // rather than being flattened into "that could not be answered".
    const refusal = {
      code: "P0001",
      message:
        "Other devotees have already joined this seva, so it cannot be moved. Post a separate seva request for the new time.",
    };

    expect(errorMessage(refusal, "That could not be answered.")).toBe(
      refusal.message,
    );
  });

  it("passes the already-answered refusal through too", () => {
    const refusal = { message: "This suggestion has already been answered." };
    expect(errorMessage(refusal, "That could not be answered.")).toBe(
      refusal.message,
    );
  });

  it("does not blame the devotee for a dropped connection", () => {
    expect(
      errorMessage({ message: "Network request failed" }, "That could not be answered."),
    ).toBe(
      "Could not reach the temple server. Check your connection and try again.",
    );
  });
});

describe("a weekly invitation is a different negotiation", () => {
  it("never lands a weekly or coverage offer in the dated-seva inbox", () => {
    // Weekly suggestions are answered by `respond_to_weekly_offer_counter` on
    // the approvals screen. Mixing them in offered the wrong button.
    for (const offer_kind of ["recurring", "coverage_range"] as const) {
      const data = build(TANMAY.id, {
        offers: [offer({ offer_kind, status: "countered" })],
        counters: [counter({ proposed_date: null, proposed_days: [4] })],
      });

      expect(sevaNeedingMyAnswer(data, TANMAY.id, true)).toEqual([]);
      expect(data.pendingOffers).toEqual([]);
    }
  });

  it("keeps every counter on the dashboard for the approvals badge to count", () => {
    const data = build(TANMAY.id, {
      offers: [offer({ offer_kind: "recurring", status: "countered" })],
      counters: [counter({ proposed_date: null, proposed_days: [4] })],
    });
    expect(
      data.offerCounters.filter((row) => row.status === "pending"),
    ).toHaveLength(1);
  });
});
