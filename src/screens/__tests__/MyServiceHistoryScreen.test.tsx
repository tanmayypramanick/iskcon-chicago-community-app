/// <reference types="jest" />

/**
 * "My seva and history": where the temple moved the seva summary to, and where
 * a devotee's weekly and one-off commitments now read as one section.
 */

import { render } from "@testing-library/react-native";

jest.mock("../../features/services/hooks", () => ({
  useServiceDashboard: () => ({
    data: mockDashboard,
    error: null,
    isLoading: false,
  }),
}));

// The devotee's own hours. Two rows so the card renders its real shape rather
// than the never-served state, which is a different branch.
jest.mock("../../features/sevayatra/hooks", () => ({
  useMySevaBreakdown: () => ({
    data: [
      {
        window_kind: "month",
        service_type_id: "type-kitchen",
        seva_name: "Cow Care",
        acts: 3,
        hours: 6,
        not_served_acts: 1,
        not_served_hours: 2,
      },
    ],
    isError: false,
    isLoading: false,
  }),
  useMySevaBalance: () => ({
    data: [
      {
        service_type_id: "type-kitchen",
        seva_name: "Cow Care",
        hours_all_time: 40,
        acts_all_time: 18,
      },
    ],
    isError: false,
    isLoading: false,
  }),
}));

import { usePrototypeSession } from "../../store/usePrototypeSession";
import { MyServiceHistoryScreen } from "../MyServiceHistoryScreen";

const ME = {
  id: "history-test-user",
  name: "Arpita Jadhav",
  photo_url: null,
  role_name: "devotee",
};

const mockDashboard: any = {
  serviceTypes: [],
  devotees: [ME],
  services: [],
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
  sevaNeedingAnswer: [],
};

async function open() {
  usePrototypeSession.setState({ activeUserId: ME.id });
  return render(
    <MyServiceHistoryScreen
      navigation={{ navigate: jest.fn() } as never}
      route={{ key: "my-seva", name: "MyServiceHistory" } as never}
    />,
  );
}

beforeEach(() => {
  mockDashboard.services = [];
  mockDashboard.recurringTemplates = [];
});

describe("the seva summary the temple moved here", () => {
  it("shows it at the top of the page, above the seva itself", async () => {
    const { getByText } = await open();

    expect(getByText("Your seva")).toBeTruthy();
    expect(
      getByText("Hours you have offered, and what you offered them to."),
    ).toBeTruthy();
  });
});

describe("one section for what a devotee is down for", () => {
  it("names the two kinds as groups under one heading", async () => {
    mockDashboard.recurringTemplates = [
      {
        id: "weekly-garlands",
        name: "Flower Garlands",
        active: true,
        participation_mode: "invite_only",
        days_of_week: [4],
        start_time: "05:00:00",
        duration_minutes: 90,
        slots_needed: 1,
        start_date: "2026-01-01",
        end_date: null,
        assignees: [{ ...ME, assignedDays: [4] }],
      },
    ];
    mockDashboard.services = [
      {
        id: "one-off",
        template_id: null,
        name: "Kitchen Preparation",
        date: "2099-09-01",
        start_time: "11:00:00",
        duration_minutes: 60,
        slots_needed: 1,
        filledSlots: 1,
        status: "full",
        participation_mode: "invite_only",
        participants: [
          {
            assignment: { id: "asg-1", status: "confirmed", attendance: null },
            devotee: ME,
          },
        ],
        currentUserAssignment: null,
      },
    ];

    const { getByText, queryByText } = await open();

    expect(getByText("My upcoming seva")).toBeTruthy();
    expect(getByText("Weekly seva")).toBeTruthy();
    expect(getByText("One-off seva")).toBeTruthy();
    // The two headings this section replaced.
    expect(queryByText("My weekly seva")).toBeNull();
    expect(queryByText("Upcoming seva")).toBeNull();
    expect(getByText("Flower Garlands")).toBeTruthy();
    expect(getByText("Kitchen Preparation")).toBeTruthy();
  });

  it("says so plainly when there is nothing at all", async () => {
    const { getByText, queryByText } = await open();

    expect(getByText("No seva is assigned to you.")).toBeTruthy();
    expect(queryByText("Weekly seva")).toBeNull();
    expect(queryByText("One-off seva")).toBeNull();
  });
});
