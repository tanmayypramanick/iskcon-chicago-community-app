/// <reference types="jest" />

import { getSupabaseClient } from "../../../lib/supabase";
import {
  requestSevaVerification,
  completeMyServiceAssignment,
  createServiceRequirement,
  createRecurringService,
  joinService,
  offerService,
  offerServiceCoverage,
  reviewRecurringServiceInterest,
  respondToServiceOffer,
  submitRecurringServiceInterest,
} from "../api";

jest.mock("../../../lib/supabase", () => ({
  getSupabaseClient: jest.fn(),
}));

const mockGetSupabaseClient = jest.mocked(getSupabaseClient);

describe("services API", () => {
  const rpc = jest.fn().mockResolvedValue({ data: "created-id", error: null });

  beforeEach(() => {
    jest.clearAllMocks();
    mockGetSupabaseClient.mockReturnValue({ rpc } as never);
  });

  it("posts an open requirement through the protected RPC", async () => {
    await createServiceRequirement({
      serviceTypeId: "type-1",
      customName: null,
      date: "2026-08-06",
      startTime: "17:30:00",
      durationMinutes: 90,
      slotsNeeded: 2,
      participationMode: "open",
      inviteeIds: [],
    });

    expect(rpc).toHaveBeenCalledWith("create_service_requirement", {
      p_service_type_id: "type-1",
      p_custom_name: null,
      p_date: "2026-08-06",
      p_start_time: "17:30:00",
      p_duration_minutes: 90,
      p_slots_needed: 2,
      p_participation_mode: "open",
      p_invitee_ids: [],
    });
  });

  it("sends a seva for a chosen member to verify, by QR or from the catalog", async () => {
    await requestSevaVerification({
      serviceTypeId: null,
      customName: null,
      qrToken: "temple-qr-token",
      startAt: "2026-08-03T23:00:00.000Z",
      endAt: "2026-08-04T00:00:00.000Z",
      locationText: "ISKCON Chicago Temple",
      verifierId: "tanmay",
    });
    await requestSevaVerification({
      serviceTypeId: "type-1",
      customName: null,
      qrToken: null,
      startAt: "2026-08-03T23:00:00.000Z",
      endAt: "2026-08-04T00:00:00.000Z",
      locationText: "ISKCON Chicago Temple",
      verifierId: "tanmay",
    });

    expect(rpc).toHaveBeenNthCalledWith(1, "request_seva_verification", {
      p_service_type_id: null,
      p_custom_name: null,
      p_start_at: "2026-08-03T23:00:00.000Z",
      p_end_at: "2026-08-04T00:00:00.000Z",
      p_location_text: "ISKCON Chicago Temple",
      p_verifier_id: "tanmay",
      p_qr_token: "temple-qr-token",
    });
    expect(rpc).toHaveBeenNthCalledWith(2, "request_seva_verification", {
      p_service_type_id: "type-1",
      p_custom_name: null,
      p_start_at: "2026-08-03T23:00:00.000Z",
      p_end_at: "2026-08-04T00:00:00.000Z",
      p_location_text: "ISKCON Chicago Temple",
      p_verifier_id: "tanmay",
      p_qr_token: null,
    });
    await completeMyServiceAssignment("instance-1");
    expect(rpc).toHaveBeenNthCalledWith(3, "complete_my_service_assignment", {
      p_instance_id: "instance-1",
    });
  });

  it("uses atomic RPCs for joining and service invitations", async () => {
    await joinService("instance-1");
    await offerService("instance-1", "devotee-2");
    await respondToServiceOffer("offer-1", true);

    expect(rpc).toHaveBeenNthCalledWith(1, "join_service_instance", {
      p_instance_id: "instance-1",
    });
    expect(rpc).toHaveBeenNthCalledWith(2, "offer_service_instance", {
      p_instance_id: "instance-1",
      p_devotee_id: "devotee-2",
    });
    expect(rpc).toHaveBeenNthCalledWith(3, "respond_to_service_offer", {
      p_offer_id: "offer-1",
      p_accept: true,
    });
  });

  it("maps recurring, unavailable, and substitute coverage operations", async () => {
    await createRecurringService({
      serviceTypeId: "type-1",
      customName: null,
      daysOfWeek: [4, 6],
      startTime: "17:00:00",
      durationMinutes: 120,
      slotsNeeded: 2,
      participationMode: "invite_only",
      startDate: "2026-08-06",
      endDate: null,
      inviteeIds: ["devotee-2"],
    });
    await offerServiceCoverage("exception-1", "devotee-3");

    expect(rpc).toHaveBeenNthCalledWith(1, "create_service_template_v2", {
      p_service_type_id: "type-1",
      p_custom_name: null,
      p_days_of_week: [4, 6],
      p_start_time: "17:00:00",
      p_duration_minutes: 120,
      p_slots_needed: 2,
      p_participation_mode: "invite_only",
      p_start_date: "2026-08-06",
      p_end_date: null,
      p_invitee_ids: ["devotee-2"],
    });
    expect(rpc).toHaveBeenNthCalledWith(2, "offer_service_coverage", {
      p_exception_id: "exception-1",
      p_devotee_id: "devotee-3",
    });
  });

  it("submits and reviews recurring seva interests without assigning a service", async () => {
    await submitRecurringServiceInterest({
      skills: "Cooking and welcoming guests",
      desiredServiceTypeIds: ["type-1", "type-2"],
      otherService: null,
      availability: "Thursday evenings",
      currentlyServing: true,
      currentServiceDetails: "Sunday flower seva at 8 AM",
    });
    await reviewRecurringServiceInterest(
      "interest-1",
      true,
      "Details verified",
    );

    expect(rpc).toHaveBeenNthCalledWith(
      1,
      "submit_recurring_service_interest",
      {
        p_skills: "Cooking and welcoming guests",
        p_desired_service_type_ids: ["type-1", "type-2"],
        p_other_service: null,
        p_availability: "Thursday evenings",
        p_currently_serving: true,
        p_current_service_details: "Sunday flower seva at 8 AM",
      },
    );
    expect(rpc).toHaveBeenNthCalledWith(
      2,
      "review_recurring_service_interest",
      {
        p_interest_id: "interest-1",
        p_approve: true,
        p_review_note: "Details verified",
      },
    );
  });
});
