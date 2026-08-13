/// <reference types="jest" />

import { fireEvent, render } from "@testing-library/react-native";

import { dateToKey, formatServiceDate } from "../../features/services/format";
import { usePrototypeSession } from "../../store/usePrototypeSession";
import { CoverageDetailScreen } from "../CoverageDetailScreen";

const ACTIVE_USER = "coverage-arrange-test-user";

jest.mock("../../features/access/hooks", () => ({
  useCurrentAccessProfile: () => ({
    data: { role: "core" },
    error: null,
    isLoading: false,
    refetch: jest.fn(),
  }),
}));

const mockReopen = jest.fn();
const mockOfferRange = jest.fn();

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
  useServiceDashboard: () => ({
    data: mockDashboard,
    error: null,
    isLoading: false,
  }),
  useReopenServiceException: () => ({
    mutate: mockReopen,
    error: null,
    isPending: false,
  }),
  useOfferServiceCoverageRange: () => ({
    mutate: mockOfferRange,
    error: null,
    isPending: false,
  }),
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

const RADHA = {
  id: "radha",
  name: "Radha Devi",
  photo_url: null,
  role_name: "devotee",
};
const TANMAY = {
  id: "tanmay",
  name: "Tanmay Pramanick",
  photo_url: null,
  role_name: "president",
};

function shiftDays(days: number) {
  const date = new Date();
  date.setHours(12, 0, 0, 0);
  date.setDate(date.getDate() + days);
  return dateToKey(date);
}

const FIRST = shiftDays(3);
const SECOND = shiftDays(10);

/** Two still-uncovered dates in one unavailability report, as the RPC groups them. */
function coverageRequest(overrides: Record<string, unknown> = {}) {
  const base = {
    request_group_id: "group-1",
    devotee_id: "radha",
    status: "pending",
    resolution_kind: null,
    substitute_devotee_id: null,
    reason: "Travelling",
    unavailable_scope: "date_range",
    unavailable_from: FIRST,
    unavailable_to: SECOND,
    unavailable_days: [1, 4],
    ...overrides,
  };
  const exceptions = [
    { ...base, id: "exception-first", service_instance_id: "occ-first" },
    { ...base, id: "exception-second", service_instance_id: "occ-second" },
  ];
  const services = [
    {
      id: "occ-first",
      template_id: "weekly-garlands",
      name: "Flower Garlands",
      date: FIRST,
      start_time: "05:00:00",
      duration_minutes: 90,
      slots_needed: 1,
      filledSlots: 0,
      status: "open",
      participation_mode: "invite_only",
      participants: [],
      pendingInvitees: [],
      currentUserAssignment: null,
    },
    {
      id: "occ-second",
      template_id: "weekly-garlands",
      name: "Flower Garlands",
      date: SECOND,
      start_time: "05:00:00",
      duration_minutes: 90,
      slots_needed: 1,
      filledSlots: 0,
      status: "open",
      participation_mode: "invite_only",
      participants: [],
      pendingInvitees: [],
      currentUserAssignment: null,
    },
  ];
  mockDashboard.services = services;
  mockDashboard.coverageRequests = [
    {
      exception: exceptions[0],
      exceptions,
      service: services[0],
      unavailableDevotee: RADHA,
      substituteDevotee: null,
    },
  ];
}

async function renderCoverage() {
  return render(
    <CoverageDetailScreen
      navigation={navigation as never}
      route={
        {
          key: "coverage-detail",
          name: "CoverageDetail",
          params: { exceptionId: "exception-first" },
        } as never
      }
    />,
  );
}

beforeEach(() => {
  jest.clearAllMocks();
  usePrototypeSession.setState({
    activeUserId: ACTIVE_USER,
    previewRole: null,
  });
  mockDashboard.devotees = [RADHA, TANMAY];
  coverageRequest();
});

describe("arranging weekly-seva coverage", () => {
  it("broadcasts the whole group by its exception, not one date", async () => {
    const screen = await renderCoverage();

    await fireEvent.press(screen.getByText("Open uncovered dates to everyone"));

    expect(mockReopen.mock.calls[0][0]).toBe("exception-first");

    screen.unmount();
  });

  it("asks one devotee for one occurrence with that occurrence's own exception", async () => {
    const screen = await renderCoverage();

    await fireEvent.press(screen.getByText("Ask specific devotees"));
    await fireEvent.press(screen.getByText(formatServiceDate(SECOND)));
    await fireEvent.press(
      screen.getByLabelText("Ask Tanmay Pramanick to cover this weekly seva"),
    );

    expect(mockOfferRange.mock.calls[0][0]).toEqual({
      exceptionId: "exception-second",
      devoteeId: "tanmay",
      scope: "occurrence",
      dateFrom: SECOND,
      dateTo: SECOND,
    });

    screen.unmount();
  });

  it("sends both ends for a date range", async () => {
    const screen = await renderCoverage();

    await fireEvent.press(screen.getByText("Ask specific devotees"));
    await fireEvent.press(screen.getByText("All unavailable days"));
    await fireEvent.press(
      screen.getByLabelText("Ask Tanmay Pramanick to cover this weekly seva"),
    );

    expect(mockOfferRange.mock.calls[0][0]).toMatchObject({
      scope: "date_range",
      dateFrom: FIRST,
      dateTo: SECOND,
    });

    screen.unmount();
  });

  it("keeps the range whole after an occurrence chip has been tapped", async () => {
    // One `fromDate` used to serve both the chips and the range start, so
    // choosing a date and then changing your mind about the scope silently
    // truncated a fortnight of cover to its last few days — with nothing on
    // screen to say the start had moved.
    const screen = await renderCoverage();

    await fireEvent.press(screen.getByText("Ask specific devotees"));
    await fireEvent.press(screen.getByText(formatServiceDate(SECOND)));
    await fireEvent.press(screen.getByText("All unavailable days"));
    await fireEvent.press(
      screen.getByLabelText("Ask Tanmay Pramanick to cover this weekly seva"),
    );

    expect(mockOfferRange.mock.calls[0][0]).toMatchObject({
      scope: "date_range",
      dateFrom: FIRST,
      dateTo: SECOND,
    });

    screen.unmount();
  });

  it("sends no end date when the swap is from now onward", async () => {
    const screen = await renderCoverage();

    await fireEvent.press(screen.getByText("Ask specific devotees"));
    await fireEvent.press(screen.getByText("From now onward"));
    await fireEvent.press(
      screen.getByLabelText("Ask Tanmay Pramanick to cover this weekly seva"),
    );

    expect(mockOfferRange.mock.calls[0][0]).toMatchObject({
      scope: "forever",
      dateFrom: FIRST,
      dateTo: null,
    });

    screen.unmount();
  });

  it("never offers the seva back to the devotee who stood down", async () => {
    const screen = await renderCoverage();

    await fireEvent.press(screen.getByText("Ask specific devotees"));

    expect(
      screen.queryByLabelText("Ask Radha Devi to cover this weekly seva"),
    ).toBeNull();

    screen.unmount();
  });

  it("starts the ask today when the report itself began in the past", async () => {
    // offer_service_coverage_range refuses a start date that has passed, so
    // opening on the original from-date handed the coordinator a form whose
    // only possible outcome was a server error.
    coverageRequest({ unavailable_from: shiftDays(-14) });
    const screen = await renderCoverage();

    await fireEvent.press(screen.getByText("Ask specific devotees"));
    await fireEvent.press(screen.getByText("All unavailable days"));
    await fireEvent.press(
      screen.getByLabelText("Ask Tanmay Pramanick to cover this weekly seva"),
    );

    const sent = mockOfferRange.mock.calls[0][0];
    expect(sent.dateFrom >= dateToKey(new Date())).toBe(true);
    expect(sent.dateTo >= sent.dateFrom).toBe(true);

    screen.unmount();
  });

  it("says the request is settled once no uncovered date is left", async () => {
    const settled = {
      id: "exception-first",
      request_group_id: "group-1",
      service_instance_id: "occ-first",
      devotee_id: "radha",
      status: "resolved",
      resolution_kind: "substitute",
      substitute_devotee_id: "tanmay",
      reason: null,
      unavailable_scope: "occurrence",
      unavailable_from: FIRST,
      unavailable_to: FIRST,
      unavailable_days: [1],
    };
    mockDashboard.coverageRequests = [
      {
        exception: settled,
        exceptions: [settled],
        service: mockDashboard.services[0],
        unavailableDevotee: RADHA,
        substituteDevotee: TANMAY,
      },
    ];
    const screen = await renderCoverage();

    expect(screen.getByText("This coverage request is resolved")).toBeTruthy();

    screen.unmount();
  });
});
