/// <reference types="jest" />

import { fireEvent, render } from "@testing-library/react-native";
import { SafeAreaProvider } from "react-native-safe-area-context";

import type { AccessRole } from "../../features/access/model";
import type { ClosedUnservedSeva } from "../../features/services/types";
import { usePrototypeSession } from "../../store/usePrototypeSession";
import { ServicesScreen } from "../ServicesScreen";

let mockRole: AccessRole = "devotee";
/** What `list_seva_closed_unserved` answered this account. */
let mockClosedUnserved: ClosedUnservedSeva[] = [];
/** Whether the RPC was asked at all. */
const mockClosedUnservedEnabled = jest.fn();

jest.mock("@react-navigation/native", () => ({
  useIsFocused: () => false,
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
};

jest.mock("../../features/services/hooks", () => ({
  useMyWeeklySevaToAnswer: () => ({ data: [], isLoading: false, error: null }),
  useDismissMyWeeklySevaAnswer: () => ({
    mutate: jest.fn(),
    isPending: false,
    error: null,
    variables: undefined,
  }),
  useWeeklySevaAnswers: () => ({ data: [], isLoading: false, error: null }),
  useAnswerMyWeeklySeva: () => ({
    mutate: jest.fn(),
    isPending: false,
    error: null,
    variables: undefined,
  }),
  useServiceDashboard: () => ({
    data: mockDashboard,
    error: null,
    isLoading: false,
  }),
  useRespondToServiceOffer: () => ({
    mutate: jest.fn(),
    error: null,
    isPending: false,
  }),
  useRespondToCoverageRangeOffer: () => ({
    mutate: jest.fn(),
    error: null,
    isPending: false,
  }),
  useDeleteServiceActivity: () => ({
    mutate: jest.fn(),
    error: null,
    isPending: false,
  }),
  useMarkSevaServed: () => ({ mutate: jest.fn(), error: null, isPending: false }),
  useSevaClashLookup: () => new Map(),
  useClosedUnservedSeva: (enabled: boolean) => {
    mockClosedUnservedEnabled(enabled);
    // The RPC answers nobody but the poster, the Tech Admin and the President,
    // so a devotee reading this hook gets exactly what they would really get.
    return {
      data: enabled ? mockClosedUnserved : [],
      isLoading: false,
      error: null,
    };
  },
}));

const navigation = { navigate: jest.fn() };

const AREA = {
  frame: { x: 0, y: 0, width: 390, height: 844 },
  insets: { top: 0, left: 0, right: 0, bottom: 0 },
};

const CLOSED: ClosedUnservedSeva = {
  serviceInstanceId: "seva-cleaning",
  name: "Temple Room Cleaning",
  occurredOn: "2026-08-11",
  weekday: "Tuesday",
  startedAt: "09:00:00",
  plannedMinutes: 60,
  isRecurring: false,
  closedAt: "2026-08-11T16:00:00Z",
  places: [
    {
      devoteeId: "ravi",
      name: "Ravi Das",
      attendance: "absent",
      assignmentStatus: "completed",
    },
  ],
};

async function renderSevaTab(role: AccessRole) {
  mockRole = role;
  usePrototypeSession.setState({
    activeUserId: "closed-unserved-test-user",
  });
  return render(
    <SafeAreaProvider initialMetrics={AREA}>
      <ServicesScreen navigation={navigation as never} route={{} as never} />
    </SafeAreaProvider>,
  );
}

beforeEach(() => {
  jest.clearAllMocks();
  mockClosedUnserved = [CLOSED];
  mockDashboard.services = [];
  mockDashboard.devotees = [];
  mockDashboard.recurringTemplates = [];
});

describe("a seva nobody served does not simply vanish", () => {
  it("is there for whoever posted it, quietly", async () => {
    // A Volunteer posts seva, so the notice is not a coordinator-only thing.
    const screen = await renderSevaTab("volunteer");

    expect(
      screen.getByText("1 seva closed because nobody served it"),
    ).toBeTruthy();
  });

  it("says which seva it was and what was said about each place", async () => {
    const screen = await renderSevaTab("president");

    await fireEvent.press(
      screen.getByLabelText(
        "See the 1 seva closed because nobody served it",
      ),
    );

    expect(screen.getByText("Closed because nobody served")).toBeTruthy();
    expect(screen.getByText("Temple Room Cleaning")).toBeTruthy();
    expect(screen.getByText("Ravi Das — marked absent")).toBeTruthy();
  });

  it("is not shown to an ordinary devotee at all", async () => {
    const screen = await renderSevaTab("devotee");

    // The question is never even put, and there is nothing on their tab.
    expect(mockClosedUnservedEnabled).toHaveBeenCalledWith(false);
    expect(screen.queryByText(/closed because nobody served/)).toBeNull();
  });

  it("draws nothing when there is nothing to say", async () => {
    mockClosedUnserved = [];
    const screen = await renderSevaTab("president");

    expect(screen.queryByText(/closed because nobody served/)).toBeNull();
  });

  it("counts more than one properly", async () => {
    mockClosedUnserved = [
      CLOSED,
      { ...CLOSED, serviceInstanceId: "seva-garlands", name: "Garland Making" },
    ];
    const screen = await renderSevaTab("president");

    expect(
      screen.getByText("2 seva closed because nobody served them"),
    ).toBeTruthy();
  });
});
