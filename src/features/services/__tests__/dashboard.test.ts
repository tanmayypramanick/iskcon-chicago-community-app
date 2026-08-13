/// <reference types="jest" />

// assembleDashboard is pure, but its module reaches the Supabase client for the
// fetching half. Stubbing that keeps this a test of the assembly rule.
jest.mock("../../../lib/supabase", () => ({
  getSupabaseClient: jest.fn(),
}));

import { assembleDashboard } from "../api";
import type {
  ServiceAssignmentRow,
  ServiceDevotee,
  ServiceInstanceRow,
  ServiceOfferRow,
} from "../types";

const ARPITA: ServiceDevotee = {
  id: "arpita",
  name: "Arpita Jadhav",
  photo_url: null,
  role_name: "devotee",
};
const RADHA: ServiceDevotee = {
  id: "radha",
  name: "Radha Devi",
  photo_url: null,
  role_name: "devotee",
};
const TANMAY: ServiceDevotee = {
  id: "tanmay",
  name: "Tanmay Pramanick",
  photo_url: null,
  role_name: "president",
};

const KITCHEN: ServiceInstanceRow = {
  id: "svc-kitchen",
  template_id: null,
  service_type_id: null,
  custom_name: "Kitchen Preparation",
  date: "2099-08-06",
  start_time: "11:00:00",
  duration_minutes: 60,
  slots_needed: 3,
  participation_mode: "invite_only",
  posted_by: "tanmay",
  status: "open",
  created_at: "2099-08-01T00:00:00.000Z",
};

function offer(overrides: Partial<ServiceOfferRow>): ServiceOfferRow {
  return {
    id: "offer-1",
    service_instance_id: "svc-kitchen",
    service_template_id: null,
    service_exception_id: null,
    service_coverage_plan_id: null,
    offered_to: "arpita",
    offered_by: "tanmay",
    offer_kind: "one_time",
    status: "pending",
    created_at: "2099-08-01T00:00:00.000Z",
    responded_at: null,
    ...overrides,
  };
}

function assignment(
  overrides: Partial<ServiceAssignmentRow>,
): ServiceAssignmentRow {
  return {
    id: "asg-1",
    service_instance_id: "svc-kitchen",
    devotee_id: "radha",
    assignment_method: "accepted_offer",
    assigned_by: "tanmay",
    status: "confirmed",
    attendance: null,
    verification: "self_report",
    qr_scanned_at: null,
    created_at: "2099-08-01T00:00:00.000Z",
    completed_at: null,
    ...overrides,
  };
}

function build(
  rows: Partial<Parameters<typeof assembleDashboard>[1]> = {},
  userId = "tanmay",
) {
  return assembleDashboard(userId, {
    serviceTypes: [],
    instanceRows: [KITCHEN],
    assignments: [],
    offers: [],
    templates: [],
    templateAssignees: [],
    exceptions: [],
    coveragePlans: [],
    interests: [],
    verifications: [],
    counters: [],
    devotees: [ARPITA, RADHA, TANMAY],
    ...rows,
  });
}

/**
 * `update_service_requirement` only ever adds invitations — it never withdraws
 * one — so the screen that changes a seva request has to be able to name who is
 * already waiting on it, whoever is reading the dashboard.
 */
describe("a seva request carries who has already been asked", () => {
  it("names every devotee with an outstanding invitation", () => {
    const dashboard = build({
      offers: [
        offer({ id: "offer-arpita", offered_to: "arpita" }),
        offer({ id: "offer-radha", offered_to: "radha" }),
      ],
    });

    expect(
      dashboard.services[0].pendingInvitees.map((devotee) => devotee.id).sort(),
    ).toEqual(["arpita", "radha"]);
  });

  it("does so for a coordinator reading somebody else's invitations", () => {
    // The list is not the signed-in devotee's own offers. Scoping it to them
    // left the coordinator changing the request with an empty box beside a
    // devotee they had asked yesterday.
    const dashboard = build(
      { offers: [offer({ offered_to: "arpita" })] },
      "tanmay",
    );

    expect(dashboard.services[0].pendingInvitees).toHaveLength(1);
    expect(dashboard.services[0].pendingInvitees[0].name).toBe("Arpita Jadhav");
  });

  it("drops an invitation once it has been answered", () => {
    const dashboard = build({
      offers: [
        offer({ id: "offer-a", offered_to: "arpita", status: "accepted" }),
        offer({ id: "offer-r", offered_to: "radha", status: "declined" }),
      ],
    });

    expect(dashboard.services[0].pendingInvitees).toEqual([]);
  });

  it("ignores weekly and coverage invitations, which are not places on this seva", () => {
    const dashboard = build({
      offers: [
        offer({ id: "offer-weekly", offer_kind: "recurring", offered_to: "arpita" }),
        offer({
          id: "offer-cover",
          offer_kind: "coverage_range",
          offered_to: "radha",
        }),
      ],
    });

    expect(dashboard.services[0].pendingInvitees).toEqual([]);
  });

  it("leaves out a devotee the directory no longer carries", () => {
    const dashboard = build({
      offers: [offer({ offered_to: "devotee-who-left" })],
    });

    expect(dashboard.services[0].pendingInvitees).toEqual([]);
  });
});

describe("who is counted as serving a seva", () => {
  it("counts live places and not the one a devotee handed over", () => {
    const dashboard = build({
      assignments: [
        assignment({ id: "asg-gone", devotee_id: "arpita", status: "withdrawn" }),
        assignment({ id: "asg-live", devotee_id: "radha", status: "confirmed" }),
      ],
    });

    expect(dashboard.services[0].filledSlots).toBe(1);
    expect(dashboard.services[0].participants.map((p) => p.devotee.id)).toEqual([
      "radha",
    ]);
  });

  it("gives the signed-in devotee their own live place and nobody else's", () => {
    const dashboard = build(
      {
        assignments: [
          assignment({ id: "asg-live", devotee_id: "radha", status: "confirmed" }),
        ],
      },
      "radha",
    );

    expect(dashboard.services[0].currentUserAssignment?.id).toBe("asg-live");
  });

  it("does not hand back a place that was withdrawn as if it were current", () => {
    const dashboard = build(
      {
        assignments: [
          assignment({ id: "asg-gone", devotee_id: "radha", status: "withdrawn" }),
        ],
      },
      "radha",
    );

    expect(dashboard.services[0].currentUserAssignment).toBeNull();
  });
});
