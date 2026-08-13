/// <reference types="jest" />

// hooks.ts reaches the Supabase client for its realtime channel and its RPCs.
// Nothing here calls either; the patches under test are pure.
jest.mock("../../../lib/supabase", () => ({
  getSupabaseClient: jest.fn(),
}));

import {
  markServedInDashboard,
  setAttendanceInDashboard,
} from "../hooks";
import { isSevaConfirmedServed, unconfirmedAssignmentIds } from "../selectors";
import type {
  SevaAttendance,
  ServiceDashboard,
  ServiceDevotee,
  ServiceListItem,
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

function place(
  devotee: ServiceDevotee,
  id: string,
  overrides: Record<string, unknown> = {},
) {
  return {
    assignment: {
      id,
      service_instance_id: "svc-kitchen",
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
    devotee,
  };
}

function service(overrides: Record<string, unknown> = {}): ServiceListItem {
  return {
    id: "svc-kitchen",
    template_id: null,
    service_type_id: null,
    custom_name: "Kitchen Preparation",
    name: "Kitchen Preparation",
    serviceType: null,
    date: "2026-08-06",
    start_time: "11:00:00",
    duration_minutes: 60,
    slots_needed: 2,
    participation_mode: "open",
    posted_by: "tanmay",
    status: "open",
    created_at: "2026-08-01T00:00:00.000Z",
    filledSlots: 2,
    participants: [place(ARPITA, "asg-arpita"), place(RADHA, "asg-radha")],
    currentUserAssignment: null,
    currentUserOffer: null,
    pendingInvitees: [],
    postedByName: "Tanmay Pramanick",
    ...overrides,
  } as unknown as ServiceListItem;
}

function dashboardOf(...services: ServiceListItem[]): ServiceDashboard {
  return { services } as unknown as ServiceDashboard;
}

function attendanceIn(
  dashboard: ServiceDashboard,
  assignmentId: string,
): SevaAttendance | null | undefined {
  return dashboard.services
    .flatMap((row) => row.participants)
    .find((participant) => participant.assignment.id === assignmentId)
    ?.assignment.attendance;
}

/**
 * Attendance is shown before the server has agreed to it, so the patch has to
 * be exactly what `record_seva_attendance` would have written. Anything wider
 * leaves the coordinator reading an answer nobody gave.
 */
describe("the attendance a tap shows before the server answers", () => {
  it("answers for one place and leaves every other place alone", () => {
    const patched = setAttendanceInDashboard(dashboardOf(service()), {
      assignmentId: "asg-arpita",
      attendance: "absent",
    });

    expect(attendanceIn(patched, "asg-arpita")).toBe("absent");
    expect(attendanceIn(patched, "asg-radha")).toBeNull();
  });

  it("clears an answer when it is taken back", () => {
    const marked = setAttendanceInDashboard(dashboardOf(service()), {
      assignmentId: "asg-arpita",
      attendance: "served",
    });
    const cleared = setAttendanceInDashboard(marked, {
      assignmentId: "asg-arpita",
      attendance: null,
    });

    expect(attendanceIn(cleared, "asg-arpita")).toBeNull();
  });

  it("does not touch a seva the place does not belong to", () => {
    const other = service({
      id: "svc-flowers",
      participants: [place(ARPITA, "asg-elsewhere")],
    });
    const before = dashboardOf(service(), other);
    const patched = setAttendanceInDashboard(before, {
      assignmentId: "asg-arpita",
      attendance: "served",
    });

    expect(patched.services[1]).toBe(before.services[1]);
  });

  it("moves the devotee's own place with it", () => {
    const mine = service({
      currentUserAssignment: place(ARPITA, "asg-arpita").assignment,
    });
    const patched = setAttendanceInDashboard(dashboardOf(mine), {
      assignmentId: "asg-arpita",
      attendance: "excused",
    });

    expect(patched.services[0].currentUserAssignment?.attendance).toBe(
      "excused",
    );
  });
});

/**
 * "Mark served" sends `unconfirmedAssignmentIds` to the server and patches the
 * dashboard separately. The two have to agree exactly, or the card clears while
 * a place the RPC was never told about stays unanswered.
 */
describe("marking a whole seva served", () => {
  it("patches precisely the places it will send", () => {
    const partly = service({
      participants: [
        place(ARPITA, "asg-arpita", { attendance: "excused" }),
        place(RADHA, "asg-radha"),
      ],
    });
    const sent = unconfirmedAssignmentIds(partly);
    const patched = markServedInDashboard(dashboardOf(partly), partly.id);

    expect(sent).toEqual(["asg-radha"]);
    expect(attendanceIn(patched, "asg-radha")).toBe("served");
    // The excused place was never sent, so it must not be repainted either.
    expect(attendanceIn(patched, "asg-arpita")).toBe("excused");
  });

  it("leaves a place that was withdrawn out of both", () => {
    const swapped = service({
      participants: [
        place(ARPITA, "asg-gone", { status: "withdrawn" }),
        place(RADHA, "asg-radha"),
      ],
    });

    expect(unconfirmedAssignmentIds(swapped)).toEqual(["asg-radha"]);
    const patched = markServedInDashboard(dashboardOf(swapped), swapped.id);
    expect(attendanceIn(patched, "asg-gone")).toBeNull();
  });

  it("clears the seva off the waiting list in one tap", () => {
    const finished = service();
    const patched = markServedInDashboard(dashboardOf(finished), finished.id);

    // The card is meant to disappear on the tap, which is exactly what
    // isSevaConfirmedServed decides.
    expect(isSevaConfirmedServed(finished)).toBe(false);
    expect(isSevaConfirmedServed(patched.services[0])).toBe(true);
  });

  it("does not close a different seva along with it", () => {
    const other = service({ id: "svc-flowers" });
    const patched = markServedInDashboard(
      dashboardOf(service(), other),
      "svc-kitchen",
    );

    expect(patched.services[1].status).toBe("open");
    expect(attendanceIn(patched, "asg-arpita")).toBe("served");
  });
});
