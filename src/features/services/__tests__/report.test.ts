/// <reference types="jest" />

import { buildCompletedSevaRows } from "../report";
import type { ServiceDashboard, ServiceVerification } from "../types";

const ARPITA = { id: "arpita", name: "Arpita Jadhav", photo_url: null, role_name: "devotee" };
const TANMAY = { id: "tanmay", name: "Tanmay Pramanick", photo_url: null, role_name: "president" };

const NOW = new Date("2026-08-04T14:00:00.000Z"); // 09:00 CDT

function registration(overrides: Partial<ServiceVerification> = {}): ServiceVerification {
  return {
    id: "reg-1",
    devotee_id: ARPITA.id,
    service_type_id: null,
    custom_name: "Flower Garlands",
    start_at: "2026-08-04T07:12:00.000Z", // 02:12 CDT
    end_at: "2026-08-04T08:12:00.000Z", // 03:12 CDT
    location_text: "ISKCON Chicago Temple",
    verifier_id: TANMAY.id,
    status: "verified",
    review_note: null,
    // Verified while still running, so the instance it created stayed `closed`.
    service_instance_id: "inst-1",
    verified_by: TANMAY.id,
    created_at: "2026-08-04T07:00:00.000Z",
    responded_at: "2026-08-04T07:30:00.000Z",
    name: "Flower Garlands",
    devotee: ARPITA,
    verifier: TANMAY,
    verifiedBy: TANMAY,
    ...overrides,
  } as ServiceVerification;
}

function dashboard(rows: ServiceVerification[], services: unknown[] = []) {
  return { verifications: rows, services } as unknown as ServiceDashboard;
}

describe("completed seva report", () => {
  it("includes a seva verified while it was still running", () => {
    // This is the case that silently vanished: the service_instances row is
    // `closed`, not `completed`, so a status-only filter dropped it.
    const rows = buildCompletedSevaRows(dashboard([registration()]), NOW);
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({
      devotee: "Arpita Jadhav",
      seva: "Flower Garlands",
      kind: "Registered seva",
      verification: "Verified by Tanmay Pramanick",
      minutes: "60",
    });
  });

  it("reports the temple's clock, not the device's", () => {
    const rows = buildCompletedSevaRows(dashboard([registration()]), NOW);
    expect(rows[0].date).toBe("2026-08-04");
    expect(rows[0].start).toBe("2:12 AM");
    expect(rows[0].end).toBe("3:12 AM");
  });

  it("leaves out seva that is unverified or has not finished", () => {
    expect(
      buildCompletedSevaRows(dashboard([registration({ status: "pending" })]), NOW),
    ).toHaveLength(0);
    expect(
      buildCompletedSevaRows(dashboard([registration({ status: "declined" })]), NOW),
    ).toHaveLength(0);
    const stillRunning = registration({
      start_at: "2026-08-04T13:30:00.000Z",
      end_at: "2026-08-04T15:00:00.000Z",
    });
    expect(buildCompletedSevaRows(dashboard([stillRunning]), NOW)).toHaveLength(0);
  });

  it("does not report the same seva twice via its service instance", () => {
    const instanceRow = {
      id: "inst-1",
      name: "Flower Garlands",
      template_id: null,
      status: "completed",
      date: "2026-08-04",
      start_time: "02:12:00",
      duration_minutes: 60,
      participants: [
        {
          devotee: ARPITA,
          assignment: {
            status: "completed",
            completed_at: "2026-08-04T08:12:00.000Z",
            verification: "member_verified",
          },
        },
      ],
    };
    const rows = buildCompletedSevaRows(
      dashboard([registration()], [instanceRow]),
      NOW,
    );
    expect(rows).toHaveLength(1);
  });
});
