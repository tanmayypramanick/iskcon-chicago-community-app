/// <reference types="jest" />

/**
 * The completed seva report — the screen and the spreadsheet, which are now one
 * set of rows.
 *
 * They used to be two builders of the same idea and had already drifted: the
 * export required `status === "completed"` and the screen did not, so a
 * coordinator read one list on screen and sent a different one out as a file.
 *
 * Tuesday 4 August 2026, 14:11 Chicago.
 */

import { render } from "@testing-library/react-native";

import type { AccessRole } from "../../features/access/model";
import { buildCompletedSevaRows } from "../../features/services/report";
import { usePrototypeSession } from "../../store/usePrototypeSession";
import { ServiceActivityScreen } from "../ServiceActivityScreen";

const ACTIVE_USER = "activity-test-user";
let mockRole: AccessRole = "president";

jest.mock("../../lib/supabase", () => ({
  getSupabaseClient: () => ({ rpc: jest.fn(), from: jest.fn() }),
}));

jest.mock("../../features/access/hooks", () => ({
  useCurrentAccessProfile: () => ({
    data: { role: mockRole },
    error: null,
    isLoading: false,
    refetch: jest.fn(),
  }),
}));

const mockDashboard: any = {
  serviceTypes: [],
  devotees: [],
  services: [],
  pendingOffers: [],
  recurringTemplates: [],
  pendingRecurringOffers: [],
  coverageRequests: [],
  coveragePlans: [],
  activeSessions: [],
  activitySessions: [],
  recurringInterests: [],
  sevaNeedingAnswer: [],
  verifications: [],
  myVerifications: [],
};

jest.mock("../../features/services/hooks", () => ({
  useServiceDashboard: () => ({
    data: mockDashboard,
    error: null,
    isLoading: false,
  }),
  useDeleteServiceActivity: () => ({
    mutate: jest.fn(),
    error: null,
    isPending: false,
  }),
  useDeleteServiceAssignmentActivity: () => ({
    mutate: jest.fn(),
    error: null,
    isPending: false,
  }),
  useDeleteSevaRegistration: () => ({
    mutate: jest.fn(),
    error: null,
    isPending: false,
  }),
}));

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

const NOW = new Date("2026-08-04T19:11:00.000Z");

function completedSeva() {
  return {
    id: "svc-1",
    template_id: null,
    name: "Kitchen Preparation",
    date: "2026-08-04",
    start_time: "11:00:00",
    duration_minutes: 60,
    slots_needed: 2,
    filledSlots: 2,
    status: "completed",
    participation_mode: "open",
    posted_by: TANMAY.id,
    participants: [ARPITA, TANMAY].map((devotee) => ({
      devotee,
      assignment: {
        id: `asg-${devotee.id}`,
        devotee_id: devotee.id,
        status: "completed",
        attendance: "served",
        verification: "member_verified",
        completed_at: "2026-08-04T17:00:00.000Z",
      },
    })),
    currentUserAssignment: null,
  };
}

async function renderActivity(role: AccessRole = "president") {
  mockRole = role;
  usePrototypeSession.setState({ activeUserId: ACTIVE_USER });
  return render(
    <ServiceActivityScreen
      navigation={{ navigate: jest.fn() } as never}
      route={{ key: "activity", name: "ServiceActivity" } as never}
    />,
  );
}

beforeAll(() => {
  jest.useFakeTimers().setSystemTime(NOW);
});
afterAll(() => {
  jest.useRealTimers();
});

beforeEach(() => {
  jest.clearAllMocks();
  mockDashboard.services = [];
  mockDashboard.verifications = [];
  mockDashboard.devotees = [ARPITA, TANMAY];
});

describe("the completed seva report", () => {
  it("shows exactly the rows the export writes", async () => {
    mockDashboard.services = [completedSeva()];
    const screen = await renderActivity();

    const rows = buildCompletedSevaRows(mockDashboard, NOW);
    expect(rows).toHaveLength(2);
    expect(screen.getByText("2 completed offerings")).toBeTruthy();
    // One row per devotee per seva — which is what an hours report is, and why
    // this is not a third list of completed seva.
    expect(screen.getAllByText("Kitchen Preparation")).toHaveLength(2);
    expect(screen.getByText("Arpita Jadhav")).toBeTruthy();
    screen.unmount();
  });

  it("says the hours on the same card every other list uses", async () => {
    mockDashboard.services = [completedSeva()];
    const screen = await renderActivity();

    expect(screen.getAllByText("1 hr")).toHaveLength(2);
    expect(screen.getAllByText(/Tue, Aug 4 · 11:00 AM/)).toHaveLength(2);
    screen.unmount();
  });

  it("leaves out a devotee somebody marked absent", async () => {
    const service = completedSeva();
    service.participants[0].assignment.attendance = "absent";
    mockDashboard.services = [service];
    const screen = await renderActivity();

    expect(screen.getByText("1 completed offering")).toBeTruthy();
    expect(screen.queryByText("Arpita Jadhav")).toBeNull();
    screen.unmount();
  });

  it("is closed to anyone without oversight", async () => {
    mockDashboard.services = [completedSeva()];
    const screen = await renderActivity("devotee");

    expect(screen.getByText("Seva oversight access required")).toBeTruthy();
    screen.unmount();
  });
});
