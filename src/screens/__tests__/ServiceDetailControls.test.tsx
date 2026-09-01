/// <reference types="jest" />

import { act, fireEvent, render } from "@testing-library/react-native";

import type { AccessRole } from "../../features/access/model";
import { dateToKey } from "../../features/services/format";
import { usePrototypeSession } from "../../store/usePrototypeSession";
import { ServiceDetailScreen } from "../ServiceDetailScreen";

const ACTIVE_USER = "service-detail-test-user";

let mockRole: AccessRole = "devotee";

jest.mock("../../features/access/hooks", () => ({
  useCurrentAccessProfile: () => ({
    data: { role: mockRole },
    error: null,
    isLoading: false,
    refetch: jest.fn(),
  }),
}));

const mockJoin = jest.fn();
const mockLeave = jest.fn();
const mockStepBack = jest.fn();
const mockOffer = jest.fn();
const mockRespond = jest.fn();
const mockComplete = jest.fn();
const mockCompleteMine = jest.fn();
const mockAttendance = jest.fn();
const mockDelete = jest.fn();

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

const idle = (mutate: jest.Mock) => () => ({
  mutate,
  error: null,
  isPending: false,
  isSuccess: false,
});

jest.mock("../../features/services/hooks", () => ({
  useStepBackFromSeva: () => ({
    mutate: mockStepBack,
    isPending: false,
    error: null,
  }),
  useServiceDashboard: () => ({
    data: mockDashboard,
    error: null,
    isLoading: false,
  }),
  useJoinService: () => ({ mutate: mockJoin, error: null, isPending: false }),
  useLeaveService: () => ({ mutate: mockLeave, error: null, isPending: false }),
  useOfferService: () => ({ mutate: mockOffer, error: null, isPending: false }),
  useRespondToServiceOffer: () => ({
    mutate: mockRespond,
    error: null,
    isPending: false,
  }),
  useCompleteService: () => ({
    mutate: mockComplete,
    error: null,
    isPending: false,
  }),
  useCompleteMyServiceAssignment: () => ({
    mutate: mockCompleteMine,
    error: null,
    isPending: false,
  }),
  useRecordSevaAttendance: () => ({
    mutate: mockAttendance,
    error: null,
    isPending: false,
  }),
  useDeleteServiceRequirement: () => ({
    mutate: mockDelete,
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

const ARPITA = {
  id: "arpita",
  name: "Arpita Jadhav",
  photo_url: null,
  role_name: "devotee",
};

function shiftDays(days: number) {
  const date = new Date();
  date.setHours(12, 0, 0, 0);
  date.setDate(date.getDate() + days);
  return dateToKey(date);
}

function service(overrides: Record<string, unknown> = {}) {
  return {
    id: "svc-kitchen",
    template_id: null,
    name: "Kitchen Preparation",
    date: shiftDays(7),
    start_time: "11:00:00",
    duration_minutes: 60,
    slots_needed: 3,
    filledSlots: 0,
    status: "open",
    participation_mode: "open",
    posted_by: "somebody-else",
    participants: [],
    pendingInvitees: [],
    currentUserAssignment: null,
    currentUserOffer: null,
    ...overrides,
  };
}

async function renderDetail(
  role: AccessRole,
  overrides: Record<string, unknown> = {},
) {
  mockRole = role;
  mockDashboard.services = [service(overrides)];
  return render(
    <ServiceDetailScreen
      navigation={navigation as never}
      route={
        {
          key: "service-detail",
          name: "ServiceDetail",
          params: { serviceId: "svc-kitchen" },
        } as never
      }
    />,
  );
}

beforeEach(() => {
  jest.clearAllMocks();
  usePrototypeSession.setState({
    activeUserId: ACTIVE_USER,
  });
  mockDashboard.devotees = [ARPITA];
});

/**
 * Every control on this screen maps to an RPC with its own rule, and offering
 * one the server will refuse is worse than not offering it — the devotee taps,
 * waits, and is told no.
 */
describe("only the controls the RPC would accept", () => {
  it.each(["devotee", "volunteer", "core", "tech", "president"] as const)(
    "lets %s join a seva that is open to everyone",
    async (role) => {
      const screen = await renderDetail(role);

      expect(screen.getByText("Join this service")).toBeTruthy();

      screen.unmount();
    },
  );

  it.each([
    // join_service_instance lets a devotee take an invite-only place only if
    // they posted it or hold services.offer_assignment.
    ["devotee", false],
    ["volunteer", true],
    ["core", true],
    ["tech", true],
    ["president", true],
  ] as const)(
    "offers %s the join button on an invite-only seva: %s",
    async (role, allowed) => {
      const screen = await renderDetail(role, {
        participation_mode: "invite_only",
      });

      expect(Boolean(screen.queryByText("Join this service"))).toBe(allowed);

      screen.unmount();
    },
  );

  it("lets the devotee who posted an invite-only seva take it themselves", async () => {
    const screen = await renderDetail("devotee", {
      participation_mode: "invite_only",
      posted_by: ACTIVE_USER,
    });

    expect(screen.getByText("Join this service")).toBeTruthy();

    screen.unmount();
  });

  it.each([
    ["devotee", false],
    ["volunteer", true],
    ["core", true],
    ["tech", true],
    ["president", true],
  ] as const)("shows %s the ask-a-devotee list: %s", async (role, allowed) => {
    const screen = await renderDetail(role);

    expect(Boolean(screen.queryByText("Ask a devotee"))).toBe(allowed);

    screen.unmount();
  });

  it.each([
    // complete_service_instance takes the poster or app.view_all, and nothing
    // else — a Community Head is refused on somebody else's seva.
    ["devotee", false],
    ["volunteer", false],
    ["core", false],
    ["tech", true],
    ["president", true],
  ] as const)(
    "shows %s Complete entire service on another devotee's seva: %s",
    async (role, allowed) => {
      // Dated in the past, because who may close a seva and when it may be
      // closed are two separate rules and this one is about who.
      const screen = await renderDetail(role, { date: shiftDays(-1) });

      expect(Boolean(screen.queryByText("Complete entire service"))).toBe(
        allowed,
      );

      screen.unmount();
    },
  );

  it("shows the poster Complete entire service on their own seva", async () => {
    const screen = await renderDetail("volunteer", {
      posted_by: ACTIVE_USER,
      date: shiftDays(-1),
    });

    expect(screen.getByText("Complete entire service")).toBeTruthy();

    screen.unmount();
  });

  it.each([
    ["devotee", false],
    ["volunteer", false],
    ["core", false],
    ["tech", true],
    ["president", true],
  ] as const)(
    "shows %s Remove seva request on another devotee's seva: %s",
    async (role, allowed) => {
      const screen = await renderDetail(role);

      expect(Boolean(screen.queryByText("Remove seva request"))).toBe(allowed);

      screen.unmount();
    },
  );
});

/**
 * "After the seva has been done and the time has passed, only then can anyone
 * mark this seva completed."
 *
 * The END instant decides, not the start. A 9:00–10:00 seva could be marked
 * completed at 9:01, with the whole hour still ahead of it. The server is being
 * held to the same line, so a control offered any earlier is a button the RPC
 * refuses — the devotee taps, waits, and is told no.
 */
describe("nothing is completed before it has happened", () => {
  const mine = {
    filledSlots: 1,
    currentUserAssignment: {
      id: "asg-mine",
      devotee_id: ACTIVE_USER,
      status: "confirmed",
      attendance: null,
    },
    participants: [
      {
        assignment: {
          id: "asg-mine",
          devotee_id: ACTIVE_USER,
          status: "confirmed",
          attendance: null,
        },
        devotee: { ...ARPITA, id: ACTIVE_USER, name: "Current Devotee" },
      },
    ],
  };

  it("hides Mark my seva completed while the seva is still to come", async () => {
    const screen = await renderDetail("devotee", {
      ...mine,
      date: shiftDays(7),
    });

    expect(screen.queryByText("Mark my seva completed")).toBeNull();
    // and says why, so the missing button reads as "not yet" rather than as a
    // feature that failed to load — naming the hour it is over, which is the
    // hour the control actually arrives.
    expect(
      screen.getByText(/You can mark this seva completed once it is over/),
    ).toBeTruthy();
    expect(screen.getByText(/12:00 PM/)).toBeTruthy();

    screen.unmount();
  });

  it("still refuses while the seva is being served", async () => {
    // 11:00 for an hour, asked at 11:30. It has begun, and nothing about it has
    // been done — this is the case the start-instant gate got wrong.
    jest.useFakeTimers();
    try {
      jest.setSystemTime(new Date("2026-08-12T16:30:00Z"));
      const screen = await renderDetail("devotee", {
        ...mine,
        date: "2026-08-12",
        start_time: "11:00:00",
        duration_minutes: 60,
      });

      expect(screen.queryByText("Mark my seva completed")).toBeNull();
      expect(
        screen.getByText(/You can mark this seva completed once it is over/),
      ).toBeTruthy();

      screen.unmount();
    } finally {
      jest.useRealTimers();
    }
  });

  it("offers it once the seva has finished", async () => {
    const screen = await renderDetail("devotee", {
      ...mine,
      date: shiftDays(-1),
    });

    expect(screen.getByText("Mark my seva completed")).toBeTruthy();

    screen.unmount();
  });

  it("holds Complete entire service back until the seva is over", async () => {
    const screen = await renderDetail("president", {
      ...mine,
      date: shiftDays(7),
    });

    expect(screen.queryByText("Complete entire service")).toBeNull();

    screen.unmount();
  });

  it("holds Complete entire service back mid-seva too", async () => {
    jest.useFakeTimers();
    try {
      jest.setSystemTime(new Date("2026-08-12T16:30:00Z"));
      const screen = await renderDetail("president", {
        ...mine,
        date: "2026-08-12",
        start_time: "11:00:00",
        duration_minutes: 60,
      });

      expect(screen.queryByText("Complete entire service")).toBeNull();

      screen.unmount();
    } finally {
      jest.useRealTimers();
    }
  });

  /**
   * The boundary arrives on its own. No data changes when a seva starts, and
   * React Query hands back the same rows on refetch, so a `now` captured at
   * render would leave a devotee standing in the temple looking at a screen
   * that never grows the button.
   */
  it("gains the control as the clock crosses the end time, with no refresh", async () => {
    jest.useFakeTimers();
    try {
      // 11:00 to 12:00 on an August date, which Chicago keeps as CDT (UTC-5).
      // Asked at 11:59.
      jest.setSystemTime(new Date("2026-08-12T16:59:00Z"));

      const screen = await renderDetail("devotee", {
        ...mine,
        date: "2026-08-12",
        start_time: "11:00:00",
        duration_minutes: 60,
      });

      expect(screen.queryByText("Mark my seva completed")).toBeNull();

      // Two minutes of temple time, nothing else touched.
      await act(async () => {
        jest.advanceTimersByTime(120_000);
      });

      expect(screen.getByText("Mark my seva completed")).toBeTruthy();

      screen.unmount();
    } finally {
      jest.useRealTimers();
    }
  });
});

describe("recording who actually served", () => {
  const serving = {
    filledSlots: 1,
    participants: [
      {
        assignment: {
          id: "asg-arpita",
          devotee_id: "arpita",
          status: "confirmed",
          attendance: null,
        },
        devotee: ARPITA,
      },
    ],
  };

  it("offers no attendance buttons before the seva has begun", async () => {
    // record_seva_attendance refuses anything before the start instant.
    const screen = await renderDetail("president", {
      ...serving,
      date: shiftDays(7),
    });

    expect(screen.getByText("Arpita Jadhav")).toBeTruthy();
    expect(screen.queryByLabelText("Mark Arpita Jadhav served")).toBeNull();

    screen.unmount();
  });

  it("offers them once it has started", async () => {
    const screen = await renderDetail("president", {
      ...serving,
      date: shiftDays(-1),
    });

    expect(screen.getByLabelText("Mark Arpita Jadhav served")).toBeTruthy();

    screen.unmount();
  });

  it("keeps them from a Community Head on a seva they did not post", async () => {
    const screen = await renderDetail("core", {
      ...serving,
      date: shiftDays(-1),
    });

    expect(screen.queryByLabelText("Mark Arpita Jadhav served")).toBeNull();

    screen.unmount();
  });

  it("records one devotee's answer without naming anybody else", async () => {
    const screen = await renderDetail("president", {
      ...serving,
      date: shiftDays(-1),
    });

    await fireEvent.press(screen.getByLabelText("Mark Arpita Jadhav absent"));

    expect(mockAttendance).toHaveBeenCalledWith({
      assignmentId: "asg-arpita",
      attendance: "absent",
    });

    screen.unmount();
  });

  it("clears an answer when the same button is tapped again", async () => {
    const screen = await renderDetail("president", {
      date: shiftDays(-1),
      filledSlots: 1,
      participants: [
        {
          assignment: {
            id: "asg-arpita",
            devotee_id: "arpita",
            status: "confirmed",
            attendance: "served",
          },
          devotee: ARPITA,
        },
      ],
    });

    await fireEvent.press(screen.getByLabelText("Mark Arpita Jadhav served"));

    expect(mockAttendance).toHaveBeenCalledWith({
      assignmentId: "asg-arpita",
      attendance: null,
    });

    screen.unmount();
  });
});

describe("leaving a seva", () => {
  const mine = {
    filledSlots: 1,
    currentUserAssignment: {
      id: "asg-mine",
      devotee_id: ACTIVE_USER,
      status: "confirmed",
      attendance: null,
    },
    participants: [
      {
        assignment: {
          id: "asg-mine",
          devotee_id: ACTIVE_USER,
          status: "confirmed",
          attendance: null,
        },
        devotee: { ...ARPITA, id: ACTIVE_USER, name: "Current Devotee" },
      },
    ],
  };

  it("steps a devotee back from a posted seva rather than leaving quietly", async () => {
    // 202608310100: giving up a place on a posted seva that has not started
    // tells whoever posted it, and on an invite-only seva opens a coverage
    // request. A bare leave did neither, so the seva went short with nobody
    // told.
    const screen = await renderDetail("devotee", mine);

    await fireEvent.press(screen.getByText("I can’t make this seva"));

    expect(mockStepBack).toHaveBeenCalledWith({ instanceId: "svc-kitchen" });
    expect(mockLeave).not.toHaveBeenCalled();

    screen.unmount();
  });

  it("says the place simply reopens when anyone may take it", async () => {
    const screen = await renderDetail("devotee", mine);

    expect(
      screen.getByText(
        "The place opens for anyone again, and whoever posted this is told.",
      ),
    ).toBeTruthy();

    screen.unmount();
  });

  it("says somebody will be asked when the seva was invite-only", async () => {
    // Nobody else can simply take an invited place, so stepping back has to
    // raise a coverage request rather than leave a silent gap.
    const screen = await renderDetail("devotee", {
      ...mine,
      participation_mode: "invite_only",
    });

    expect(
      screen.getByText(
        "Whoever posted this is told, and can open it to everyone or ask somebody else.",
      ),
    ).toBeTruthy();

    screen.unmount();
  });

  it("sends a weekly occurrence to the coverage form instead of a bare leave", async () => {
    // Standing down from a weekly date has to raise a coverage request, or the
    // seva quietly loses its devotee with nobody told.
    const screen = await renderDetail("devotee", {
      ...mine,
      template_id: "weekly-garlands",
    });

    expect(screen.queryByText("Leave this service")).toBeNull();
    await fireEvent.press(screen.getByText("I can’t make this occurrence"));

    expect(navigation.navigate).toHaveBeenCalledWith("ReportUnavailable", {
      serviceId: "svc-kitchen",
    });

    screen.unmount();
  });

  it("offers nothing to leave once the seva is closed off", async () => {
    const screen = await renderDetail("devotee", {
      ...mine,
      status: "completed",
    });

    expect(screen.queryByText("Leave this service")).toBeNull();
    expect(screen.queryByText("Mark my seva completed")).toBeNull();

    screen.unmount();
  });
});

describe("answering an invitation from the seva itself", () => {
  it("accepts and declines through the offer, not the seva", async () => {
    const screen = await renderDetail("devotee", {
      participation_mode: "invite_only",
      currentUserOffer: { id: "offer-1", status: "pending" },
    });

    await fireEvent.press(screen.getByText("Accept seva"));
    expect(mockRespond).toHaveBeenCalledWith({
      offerId: "offer-1",
      accept: true,
    });

    await fireEvent.press(screen.getByText("Not available"));
    expect(mockRespond).toHaveBeenCalledWith({
      offerId: "offer-1",
      accept: false,
    });

    screen.unmount();
  });
});
