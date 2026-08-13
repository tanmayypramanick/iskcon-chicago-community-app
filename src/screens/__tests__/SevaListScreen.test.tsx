/// <reference types="jest" />

/**
 * The See-all behind each section of the Seva tab, and whether it says the same
 * thing the section did.
 *
 * "Weekly seva only one card and not multiple cards" has to hold on both sides
 * of the button, or the temple taps See all and is shown a different answer to
 * the question they just read.
 *
 * Wednesday 12 August 2026, 10:00 Chicago.
 */

import { render } from "@testing-library/react-native";

import type { AccessRole } from "../../features/access/model";
import { usePrototypeSession } from "../../store/usePrototypeSession";
import { SevaListScreen } from "../SevaListScreen";

const ACTIVE_USER = "seva-list-test-user";
let mockRole: AccessRole = "president";

jest.mock("../../features/access/hooks", () => ({
  useCurrentAccessProfile: () => ({
    data: { role: mockRole },
    error: null,
    isLoading: false,
    refetch: jest.fn(),
  }),
}));

jest.mock("../../features/schedule/hooks", () => ({
  useTempleProgramme: () => ({ data: [], isLoading: false, error: null }),
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
}));

const navigation = { navigate: jest.fn(), goBack: jest.fn() };

const ME = {
  id: ACTIVE_USER,
  name: "Current Devotee",
  photo_url: null,
  role_name: "devotee",
};
const RADHA = {
  id: "radha",
  name: "Radha Devi",
  photo_url: null,
  role_name: "devotee",
};

async function renderList(kind: string, role: AccessRole = "president") {
  mockRole = role;
  usePrototypeSession.setState({ activeUserId: ACTIVE_USER, previewRole: null });
  return render(
    <SevaListScreen
      navigation={navigation as never}
      route={{ key: "seva-list", name: "SevaList", params: { kind } } as never}
    />,
  );
}

const NOW = new Date("2026-08-12T15:00:00.000Z");

beforeAll(() => {
  jest.useFakeTimers().setSystemTime(NOW);
});
afterAll(() => {
  jest.useRealTimers();
});

beforeEach(() => {
  jest.clearAllMocks();
  mockDashboard.services = [];
  mockDashboard.recurringTemplates = [];
  mockDashboard.devotees = [ME, RADHA];
  mockDashboard.coveragePlans = [];
  mockDashboard.coverageRequests = [];
  mockDashboard.verifications = [];
  mockDashboard.myVerifications = [];
});

/**
 * A weekly seva Radha served twice last week, and which the reader is down for
 * next Monday. The reader has never served it.
 */
function servedTwiceLastWeek() {
  mockDashboard.recurringTemplates = [
    {
      id: "weekly-garlands",
      name: "Flower Garlands",
      active: true,
      participation_mode: "invite_only",
      days_of_week: [1, 4],
      start_time: "05:00:00",
      duration_minutes: 90,
      slots_needed: 1,
      start_date: "2020-01-01",
      end_date: null,
      created_by: "someone-else",
      assignees: [{ ...ME, assignedDays: [1] }],
    },
  ];
  const occurrence = (
    date: string,
    status: string,
    devotee: typeof ME,
    attendance: string | null,
  ) => ({
    id: `occ-${date}`,
    template_id: "weekly-garlands",
    name: "Flower Garlands",
    date,
    start_time: "05:00:00",
    duration_minutes: 90,
    slots_needed: 1,
    filledSlots: 1,
    status,
    participation_mode: "invite_only",
    participants: [
      {
        assignment: {
          id: `asg-${date}`,
          devotee_id: devotee.id,
          status: status === "completed" ? "completed" : "confirmed",
          attendance,
        },
        devotee,
      },
    ],
    currentUserAssignment: null,
  });
  mockDashboard.services = [
    occurrence("2026-08-03", "completed", RADHA, "served"),
    occurrence("2026-08-06", "completed", RADHA, "served"),
    // Still to come, and it is the reader's.
    occurrence("2026-08-17", "open", ME, null),
  ];
}

describe("the completed See-all answers what the tab answered", () => {
  it("collapses a weekly seva's finished dates into one card", async () => {
    servedTwiceLastWeek();
    const screen = await renderList("completed");

    expect(screen.getAllByText("Flower Garlands")).toHaveLength(1);
    screen.unmount();
  });

  it("dates that card by an occurrence that happened, not the next one", async () => {
    // It used to read `myNextWeeklyOccurrence` — a date in the future printed
    // on a card in a history list.
    servedTwiceLastWeek();
    const screen = await renderList("completed");

    expect(screen.getByText(/Thu, Aug 6/)).toBeTruthy();
    expect(screen.queryByText(/Aug 17/)).toBeNull();
    screen.unmount();
  });

  it("does not call it My seva on the strength of a future date", async () => {
    // "My seva" was decided by the same future occurrence, so a devotee who
    // never served a single one of these mornings was credited with them.
    servedTwiceLastWeek();
    const screen = await renderList("completed");

    expect(screen.queryByText("My seva")).toBeNull();
    screen.unmount();
  });
});

describe("registered seva is excluded wherever services are listed", () => {
  /** A verified registration, and the service_instances row verifying wrote. */
  function verifiedRegistration() {
    mockDashboard.verifications = [
      {
        id: "reg-1",
        devotee_id: ME.id,
        name: "Book Distribution",
        status: "verified",
        start_at: "2026-08-05T15:00:00.000Z",
        end_at: "2026-08-05T17:00:00.000Z",
        location_text: "ISKCON Chicago Temple",
        service_instance_id: "inst-1",
        devotee: ME,
        verifier: null,
        verifiedBy: RADHA,
        created_at: "2026-08-01T00:00:00.000Z",
      },
    ];
    mockDashboard.services = [
      {
        id: "inst-1",
        template_id: null,
        name: "Book Distribution",
        date: "2026-08-05",
        start_time: "10:00:00",
        duration_minutes: 120,
        slots_needed: 1,
        filledSlots: 1,
        // Verified while it was still running, so the row it created is
        // `closed` — which is exactly what "Waiting to be verified" collects.
        status: "closed",
        participation_mode: "invite_only",
        posted_by: ACTIVE_USER,
        participants: [
          {
            assignment: {
              id: "asg-1",
              devotee_id: ME.id,
              status: "confirmed",
              attendance: null,
            },
            devotee: ME,
          },
        ],
        currentUserAssignment: null,
      },
    ];
  }

  it("does not show a verified registration as an unconfirmed service", async () => {
    // Four See-all modes never asked, so the tab called this a finished
    // registration while its own See all called it a seva nobody had confirmed.
    verifiedRegistration();
    const screen = await renderList("awaiting_close");

    expect(screen.queryByText("Book Distribution")).toBeNull();
    screen.unmount();
  });
});

describe("My upcoming seva, on both sides of See all", () => {
  it("carries the devotee's registered seva, which used to answer with none", async () => {
    mockDashboard.verifications = [
      {
        id: "reg-2",
        devotee_id: ME.id,
        name: "Book Distribution",
        status: "verified",
        start_at: "2026-08-14T15:00:00.000Z",
        end_at: "2026-08-14T17:00:00.000Z",
        location_text: "ISKCON Chicago Temple",
        service_instance_id: null,
        devotee: ME,
        verifier: null,
        verifiedBy: RADHA,
        created_at: "2026-08-01T00:00:00.000Z",
      },
    ];
    const screen = await renderList("my_upcoming", "devotee");

    expect(screen.getAllByText("Book Distribution")).toHaveLength(1);
    // Under the same group name the tab uses, not a heading of its own.
    expect(screen.getByText("One-off seva")).toBeTruthy();
    expect(screen.queryByText("Registered seva")).toBeNull();
    screen.unmount();
  });
});
