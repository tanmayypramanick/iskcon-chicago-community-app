/// <reference types="jest" />

import { fireEvent, render } from "@testing-library/react-native";

import { usePrototypeSession } from "../../store/usePrototypeSession";
import { CoverageDetailScreen } from "../CoverageDetailScreen";
import { EditServiceRequestScreen } from "../EditServiceRequestScreen";

const ACTIVE_USER = "who-can-join-test-user";
const DEVOTEE_SEARCH = "Search devotee by name";

jest.mock("../../features/access/hooks", () => ({
  useCurrentAccessProfile: () => ({
    data: { role: "president" },
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
};

const idleMutation = () => ({
  mutate: jest.fn(),
  error: null,
  isPending: false,
  isSuccess: false,
});

jest.mock("../../features/services/hooks", () => ({
  useServiceDashboard: () => ({
    data: mockDashboard,
    error: null,
    isLoading: false,
  }),
  useUpdateServiceRequirement: () => idleMutation(),
  useDeleteServiceRequirement: () => idleMutation(),
  useReopenServiceException: () => idleMutation(),
  useOfferServiceCoverageRange: () => idleMutation(),
  // Clash checks warn and never block, so the default double is "nothing
  // clashes" and every existing expectation stands unchanged.
  useSevaClashLookup: () => new Map(),
  useSevaClashes: () => [],
  useClashGate: (proceed: (target: unknown) => void) => ({
    checking: false,
    warning: null,
    ask: proceed,
    accept: jest.fn(),
    dismiss: jest.fn(),
  }),
  useClosedUnservedSeva: () => ({ data: [], isLoading: false, error: null }),
}));

const navigation = { navigate: jest.fn(), goBack: jest.fn() };

const devotee = {
  id: "devotee-tanmay",
  name: "Tanmay Pramanick",
  photo_url: null,
  role_name: "devotee",
};

beforeEach(() => {
  jest.clearAllMocks();
  usePrototypeSession.setState({
    activeUserId: ACTIVE_USER,
    previewRole: null,
  });
  mockDashboard.devotees = [devotee];
  mockDashboard.services = [];
  mockDashboard.coverageRequests = [];
});

describe("Who can join, on a seva request", () => {
  function renderEdit() {
    mockDashboard.services = [
      {
        id: "seva-kitchen",
        template_id: null,
        name: "Kitchen Preparation",
        date: "2099-08-06",
        start_time: "11:00:00",
        duration_minutes: 60,
        slots_needed: 2,
        filledSlots: 0,
        status: "open",
        // The screen opens on whatever the request already is.
        participation_mode: "open",
        posted_by: ACTIVE_USER,
        participants: [],
        currentUserAssignment: null,
      },
    ];
    return render(
      <EditServiceRequestScreen
        navigation={navigation as never}
        route={
          {
            key: "edit-seva",
            name: "EditServiceRequest",
            params: { serviceId: "seva-kitchen" },
          } as never
        }
      />,
    );
  }

  it("offers both choices as separate buttons", async () => {
    const screen = await renderEdit();

    expect(screen.getByText("Who can join")).toBeTruthy();
    expect(screen.getByText("Open to everyone")).toBeTruthy();
    expect(screen.getByText("Ask specific devotees")).toBeTruthy();

    screen.unmount();
  });

  it("reveals the devotee picker only once specific devotees are asked", async () => {
    const screen = await renderEdit();

    expect(screen.queryByPlaceholderText(DEVOTEE_SEARCH)).toBeNull();

    await fireEvent.press(screen.getByText("Ask specific devotees"));
    expect(screen.getByPlaceholderText(DEVOTEE_SEARCH)).toBeTruthy();
    expect(screen.getByText("Tanmay Pramanick")).toBeTruthy();

    await fireEvent.press(screen.getByText("Open to everyone"));
    expect(screen.queryByPlaceholderText(DEVOTEE_SEARCH)).toBeNull();

    screen.unmount();
  });
});

describe("Who can join, on weekly-seva coverage", () => {
  function renderCoverage() {
    const exception = {
      id: "exception-thursday",
      request_group_id: "group-1",
      service_instance_id: "weekly-thursday",
      devotee_id: "devotee-radha",
      status: "pending",
      unavailable_scope: "occurrence",
      unavailable_from: "2099-08-06",
      unavailable_to: null,
      unavailable_days: [4],
      reason: null,
      substitute_devotee_id: null,
    };
    const service = {
      id: "weekly-thursday",
      template_id: "weekly-garlands",
      name: "Flower Garlands",
      date: "2099-08-06",
      start_time: "05:00:00",
      duration_minutes: 60,
      slots_needed: 1,
      filledSlots: 0,
      status: "open",
      participation_mode: "open",
      participants: [],
      currentUserAssignment: null,
    };
    mockDashboard.services = [service];
    mockDashboard.coverageRequests = [
      {
        exception,
        exceptions: [exception],
        service,
        unavailableDevotee: {
          id: "devotee-radha",
          name: "Radha Devi",
          photo_url: null,
          role_name: "devotee",
        },
        substituteDevotee: null,
      },
    ];
    return render(
      <CoverageDetailScreen
        navigation={navigation as never}
        route={
          {
            key: "coverage-detail",
            name: "CoverageDetail",
            params: { exceptionId: "exception-thursday" },
          } as never
        }
      />,
    );
  }

  it("asks the same question with the same two buttons", async () => {
    const screen = await renderCoverage();

    expect(screen.getByText("Who can join")).toBeTruthy();
    expect(screen.getByText("Open to everyone")).toBeTruthy();
    expect(screen.getByText("Ask specific devotees")).toBeTruthy();

    screen.unmount();
  });

  it("shows the devotee list only after specific devotees are asked", async () => {
    const screen = await renderCoverage();

    expect(screen.queryByPlaceholderText(DEVOTEE_SEARCH)).toBeNull();
    expect(screen.getByText("Open uncovered dates to everyone")).toBeTruthy();

    await fireEvent.press(screen.getByText("Ask specific devotees"));
    expect(screen.getByPlaceholderText(DEVOTEE_SEARCH)).toBeTruthy();
    expect(screen.getByText("Tanmay Pramanick")).toBeTruthy();
    // The broadcast is a different, final action; it must not sit under the
    // choice that is no longer selected.
    expect(screen.queryByText("Open uncovered dates to everyone")).toBeNull();

    await fireEvent.press(screen.getByText("Open to everyone"));
    expect(screen.queryByPlaceholderText(DEVOTEE_SEARCH)).toBeNull();

    screen.unmount();
  });
});
