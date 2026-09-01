/// <reference types="jest" />

import { act, fireEvent, render } from "@testing-library/react-native";
import { SafeAreaProvider } from "react-native-safe-area-context";

import type { AccessRole } from "../../features/access/model";
import type { SevaClash } from "../../features/services/types";
import { usePrototypeSession } from "../../store/usePrototypeSession";
import { CoverageInboxScreen } from "../CoverageInboxScreen";
import { CreateServiceScreen } from "../CreateServiceScreen";
import { ServicesScreen } from "../ServicesScreen";
import { WeeklySevaDetailScreen } from "../WeeklySevaDetailScreen";

const ACTIVE_USER = "clash-test-devotee";
let mockRole: AccessRole = "devotee";

const mockRespond = jest.fn();
const mockRespondCoverage = jest.fn();
const mockCreateRequirement = jest.fn();
const mockJoinWeekly = jest.fn();
const mockRespondCounter = jest.fn();
/** Whatever the server is pretending to say this test. */
let mockClashes = new Map<string, SevaClash[]>();

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
  serviceTypes: [
    {
      id: "type-kitchen",
      name: "Kitchen Preparation",
      category: "kitchen",
      is_active: true,
    },
  ],
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
    mutate: mockRespond,
    error: null,
    isPending: false,
  }),
  useRespondToCoverageRangeOffer: () => ({
    mutate: mockRespondCoverage,
    error: null,
    isPending: false,
  }),
  useJoinWeeklyService: () => ({
    mutate: mockJoinWeekly,
    error: null,
    isPending: false,
  }),
  useDeleteRecurringService: () => ({
    mutate: jest.fn(),
    error: null,
    isPending: false,
  }),
  useRespondToServiceOfferCounter: () => ({
    mutate: mockRespondCounter,
    error: null,
    isPending: false,
  }),
  // One window, looked up under the same key the real hook uses.
  useSevaClashes: () => mockClashes.get("only") ?? [],
  useDeleteServiceActivity: () => ({
    mutate: jest.fn(),
    error: null,
    isPending: false,
  }),
  useMarkSevaServed: () => ({ mutate: jest.fn(), error: null, isPending: false }),
  useCreateServiceRequirement: () => ({
    mutate: mockCreateRequirement,
    error: null,
    isPending: false,
  }),
  useSevaClashLookup: () => mockClashes,
  useClosedUnservedSeva: () => ({ data: [], isLoading: false, error: null }),
}));

const navigation = { navigate: jest.fn(), goBack: jest.fn() };

function clash(overrides: Partial<SevaClash> = {}): SevaClash {
  return {
    service_instance_id: "other-seva",
    template_id: null,
    from_weekly_template: false,
    seva_name: "Kitchen Preparation",
    name_visible: true,
    occurs_on: "2099-08-06",
    starts_at_local: "12:00:00",
    ends_at_local: "13:30:00",
    ends_next_day: false,
    starts_at: "2099-08-06T17:00:00Z",
    ends_at: "2099-08-06T18:30:00Z",
    status: "open",
    assignment_status: "confirmed",
    is_substitute: false,
    overlap_minutes: 15,
    overlap_starts_at: "2099-08-06T18:15:00Z",
    overlap_ends_at: "2099-08-06T18:30:00Z",
    covers_whole_request: false,
    ...overrides,
  };
}

const INVITED_SEVA = {
  id: "seva-garlands",
  template_id: null,
  service_type_id: null,
  custom_name: "Garland Making",
  name: "Garland Making",
  serviceType: null,
  date: "2099-08-06",
  start_time: "13:15:00",
  duration_minutes: 75,
  slots_needed: 1,
  filledSlots: 0,
  participation_mode: "invite_only",
  posted_by: "coordinator",
  status: "open",
  created_at: "2099-08-01T00:00:00Z",
  participants: [],
  pendingInvitees: [],
  currentUserAssignment: null,
  currentUserOffer: null,
  postedByName: "Radha Devi",
};

const OFFER = {
  offer: {
    id: "offer-1",
    service_instance_id: "seva-garlands",
    status: "pending",
  },
  service: INVITED_SEVA,
  offeredByName: "Radha Devi",
};

const AREA = {
  frame: { x: 0, y: 0, width: 390, height: 844 },
  insets: { top: 0, left: 0, right: 0, bottom: 0 },
};

/** The sheet slides in and out; its actions only run once it has gone. */
async function settleSheet() {
  await act(async () => {
    jest.advanceTimersByTime(600);
  });
}

function sevaTab() {
  return (
    <SafeAreaProvider initialMetrics={AREA}>
      <ServicesScreen navigation={navigation as never} route={{} as never} />
    </SafeAreaProvider>
  );
}

beforeEach(() => {
  jest.clearAllMocks();
  jest.useFakeTimers();
  mockRole = "devotee";
  mockClashes = new Map();
  mockDashboard.pendingOffers = [];
  mockDashboard.pendingRecurringOffers = [];
  mockDashboard.recurringTemplates = [];
  mockDashboard.coverageRequests = [];
  mockDashboard.sevaNeedingAnswer = [];
  mockDashboard.services = [];
  mockDashboard.devotees = [];
  usePrototypeSession.setState({ activeUserId: ACTIVE_USER });
});

afterEach(() => {
  jest.useRealTimers();
});

describe("a devotee answering an invitation that overlaps their day", () => {
  it("warns about a partial overlap and still lets them accept", async () => {
    mockDashboard.pendingOffers = [OFFER];
    mockClashes = new Map([["offer-1", [clash()]]]);
    const screen = await render(sevaTab());

    await fireEvent.press(screen.getByLabelText("Accept Garland Making"));
    await settleSheet();

    // Nothing has been sent: the devotee is being told, not overruled.
    expect(mockRespond).not.toHaveBeenCalled();
    expect(screen.getByText("You are already serving then")).toBeTruthy();
    expect(
      screen.getByText(
        "You are serving Kitchen Preparation from 12:00 PM to 1:30 PM, " +
          "but this seva is from 1:15 PM to 2:30 PM. " +
          "The two overlap by 15 min. " +
          "Only accept if you can manage to serve both.",
      ),
    ).toBeTruthy();

    await fireEvent.press(screen.getByLabelText("Accept anyway"));
    await settleSheet();

    expect(mockRespond).toHaveBeenCalledWith({
      offerId: "offer-1",
      accept: true,
    });
  });

  it("says nothing at all when the seva only butts up against theirs", async () => {
    // 12:00–13:30 then 13:30–14:30. The ranges are half-open, so the server
    // answers no clash and this is an ordinary accept with nothing in the way.
    mockDashboard.pendingOffers = [OFFER];
    mockClashes = new Map([["offer-1", []]]);
    const screen = await render(sevaTab());

    await fireEvent.press(screen.getByLabelText("Accept Garland Making"));
    await settleSheet();

    expect(mockRespond).toHaveBeenCalledWith({
      offerId: "offer-1",
      accept: true,
    });
    expect(screen.queryByText("You are already serving then")).toBeNull();
  });

  it("words a withheld name without inventing one", async () => {
    mockDashboard.pendingOffers = [OFFER];
    mockClashes = new Map([
      ["offer-1", [clash({ seva_name: null, name_visible: false })]],
    ]);
    const screen = await render(sevaTab());

    await fireEvent.press(screen.getByLabelText("Accept Garland Making"));
    await settleSheet();

    expect(
      screen.getByText(/You are serving another seva from 12:00 PM/),
    ).toBeTruthy();
    expect(screen.queryByText(/Kitchen Preparation/)).toBeNull();
    expect(screen.queryByText(/null|undefined/)).toBeNull();
  });

  it("offers the other answer the temple asked for", async () => {
    mockDashboard.pendingOffers = [OFFER];
    mockClashes = new Map([["offer-1", [clash()]]]);
    const screen = await render(sevaTab());

    await fireEvent.press(screen.getByLabelText("Accept Garland Making"));
    await settleSheet();
    await fireEvent.press(screen.getByLabelText("I am available another time"));
    await settleSheet();

    expect(navigation.navigate).toHaveBeenCalledWith("ProposeServiceTime", {
      offerId: "offer-1",
    });
    expect(mockRespond).not.toHaveBeenCalled();
  });

  it("clears the warning when the clashing seva goes away underneath it", async () => {
    mockDashboard.pendingOffers = [OFFER];
    mockClashes = new Map([["offer-1", [clash()]]]);
    const screen = await render(sevaTab());

    await fireEvent.press(screen.getByLabelText("Accept Garland Making"));
    await settleSheet();
    expect(screen.getByText("You are already serving then")).toBeTruthy();

    // Somebody else has taken that seva over, and realtime says so.
    mockClashes = new Map([["offer-1", []]]);
    await screen.rerender(sevaTab());
    await settleSheet();

    expect(screen.queryByText("You are already serving then")).toBeNull();
    // Clearing a warning is not the same as answering it.
    expect(mockRespond).not.toHaveBeenCalled();
  });
});

describe("a coordinator inviting somebody who is already serving", () => {
  const RAVI = {
    id: "ravi",
    name: "Ravi Das",
    photo_url: null,
    role_name: "devotee",
  };

  function createForm() {
    return (
      <SafeAreaProvider initialMetrics={AREA}>
        <CreateServiceScreen
          navigation={navigation as never}
          route={{ params: undefined } as never}
        />
      </SafeAreaProvider>
    );
  }

  it("warns before the invitation is sent, and sends it if told to", async () => {
    mockRole = "president";
    mockDashboard.devotees = [RAVI];
    mockClashes = new Map([["ravi", [clash()]]]);
    const screen = await render(createForm());

    await fireEvent.press(screen.getByText("Kitchen Preparation"));
    await fireEvent.press(screen.getByText("Ask specific devotees"));
    await fireEvent.press(screen.getByLabelText("Select Ravi Das"));
    await fireEvent.press(screen.getByText("Post seva request"));
    await settleSheet();

    // The seva has not been posted and Ravi has not been asked.
    expect(mockCreateRequirement).not.toHaveBeenCalled();
    expect(screen.getByText("Ravi Das is already serving then")).toBeTruthy();
    expect(screen.getByText(/You can still ask/)).toBeTruthy();

    await fireEvent.press(screen.getByLabelText("Post and ask anyway"));
    await settleSheet();

    expect(mockCreateRequirement).toHaveBeenCalledTimes(1);
    expect(mockCreateRequirement.mock.calls[0][0]).toMatchObject({
      inviteeIds: ["ravi"],
      participationMode: "invite_only",
    });
  });

  it("posts straight away when nobody invited is busy", async () => {
    mockRole = "president";
    mockDashboard.devotees = [RAVI];
    mockClashes = new Map([["ravi", []]]);
    const screen = await render(createForm());

    await fireEvent.press(screen.getByText("Kitchen Preparation"));
    await fireEvent.press(screen.getByText("Ask specific devotees"));
    await fireEvent.press(screen.getByLabelText("Select Ravi Das"));
    await fireEvent.press(screen.getByText("Post seva request"));
    await settleSheet();

    expect(mockCreateRequirement).toHaveBeenCalledTimes(1);
    expect(screen.queryByText(/is already serving then/)).toBeNull();
  });
});

/**
 * The three accepts that had no warning at all.
 *
 * A standing weekly commitment is the one most worth warning about — saying yes
 * commits every week, not one morning — and it was the one with nothing to say.
 */
describe("a devotee accepting a weekly seva invitation", () => {
  const WEEKLY_OFFER = {
    offer: { id: "offer-weekly", offer_kind: "recurring", status: "pending" },
    template: {
      id: "weekly-garlands",
      name: "Garland Making",
      days_of_week: [4],
      start_time: "13:15:00",
      duration_minutes: 75,
      active: true,
      participation_mode: "open",
      slots_needed: 1,
    },
    offeredByName: "Radha Devi",
    coveragePlan: null,
  };

  it("warns about the standing clash and still lets them accept", async () => {
    mockDashboard.pendingRecurringOffers = [WEEKLY_OFFER];
    mockClashes = new Map([["offer-weekly", [clash()]]]);
    const screen = await render(sevaTab());

    await fireEvent.press(
      screen.getByLabelText("Accept weekly seva Garland Making"),
    );
    await settleSheet();

    expect(mockRespond).not.toHaveBeenCalled();
    expect(screen.getByText("You are already serving then")).toBeTruthy();

    await fireEvent.press(screen.getByLabelText("Accept anyway"));
    await settleSheet();

    expect(mockRespond).toHaveBeenCalledWith({
      offerId: "offer-weekly",
      accept: true,
    });
  });

  it("answers a coverage range through its own mutation", async () => {
    mockDashboard.pendingRecurringOffers = [
      {
        ...WEEKLY_OFFER,
        offer: {
          id: "offer-weekly",
          offer_kind: "coverage_range",
          status: "pending",
        },
        coveragePlan: {
          scope: "date_range",
          date_from: "2099-08-06",
          date_to: "2099-09-06",
          days_of_week: [4],
        },
      },
    ];
    mockClashes = new Map([["offer-weekly", [clash()]]]);
    const screen = await render(sevaTab());

    await fireEvent.press(
      screen.getByLabelText("Accept coverage for Garland Making"),
    );
    await settleSheet();
    await fireEvent.press(screen.getByLabelText("Accept anyway"));
    await settleSheet();

    expect(mockRespondCoverage).toHaveBeenCalledWith({
      offerId: "offer-weekly",
      accept: true,
    });
    expect(mockRespond).not.toHaveBeenCalled();
  });

  it("accepts straight away when nothing overlaps", async () => {
    mockDashboard.pendingRecurringOffers = [WEEKLY_OFFER];
    mockClashes = new Map([["offer-weekly", []]]);
    const screen = await render(sevaTab());

    await fireEvent.press(
      screen.getByLabelText("Accept weekly seva Garland Making"),
    );
    await settleSheet();

    expect(mockRespond).toHaveBeenCalledWith({
      offerId: "offer-weekly",
      accept: true,
    });
    expect(screen.queryByText("You are already serving then")).toBeNull();
  });

  it("says the same thing about the other time, in the same words", async () => {
    // The tab used to offer "I am available another time" on a dated
    // invitation and "I am free at another time" on a weekly one.
    mockDashboard.pendingRecurringOffers = [WEEKLY_OFFER];
    const screen = await render(sevaTab());

    expect(screen.queryByText("I am free at another time")).toBeNull();
    expect(screen.getByText("I am available another time")).toBeTruthy();
  });
});

describe("a devotee joining a weekly seva from its own screen", () => {
  function weeklyScreen() {
    return (
      <SafeAreaProvider initialMetrics={AREA}>
        <WeeklySevaDetailScreen
          navigation={navigation as never}
          route={
            {
              key: "weekly",
              name: "WeeklySevaDetail",
              params: { templateId: "weekly-garlands" },
            } as never
          }
        />
      </SafeAreaProvider>
    );
  }

  beforeEach(() => {
    mockDashboard.recurringTemplates = [
      {
        id: "weekly-garlands",
        name: "Garland Making",
        active: true,
        participation_mode: "open",
        days_of_week: [4],
        start_time: "13:15:00",
        duration_minutes: 75,
        slots_needed: 1,
        start_date: "2020-01-01",
        end_date: null,
        created_by: "coordinator",
        assignees: [],
      },
    ];
  });

  it("warns before a standing commitment is taken on, and joins anyway", async () => {
    mockClashes = new Map([["only", [clash()]]]);
    const screen = await render(weeklyScreen());

    await fireEvent.press(screen.getByText("Join this weekly seva"));
    await settleSheet();

    expect(mockJoinWeekly).not.toHaveBeenCalled();
    expect(screen.getByText("You are already serving then")).toBeTruthy();

    await fireEvent.press(screen.getByLabelText("Join anyway"));
    await settleSheet();

    expect(mockJoinWeekly).toHaveBeenCalledWith("weekly-garlands");
  });

  it("joins without a word when nothing overlaps", async () => {
    mockClashes = new Map();
    const screen = await render(weeklyScreen());

    await fireEvent.press(screen.getByText("Join this weekly seva"));
    await settleSheet();

    expect(mockJoinWeekly).toHaveBeenCalledWith("weekly-garlands");
    expect(screen.queryByText("You are already serving then")).toBeNull();
  });
});

describe("a coordinator moving a seva to the time a devotee suggested", () => {
  const COUNTERED = {
    kind: "countered",
    offer: { id: "offer-1", offered_to: "ravi" },
    counter: {
      id: "counter-1",
      status: "pending",
      proposed_date: "2099-08-06",
      proposed_start_time: "13:15:00",
      proposed_duration_minutes: 75,
      note: null,
    },
    service: {
      id: "svc-1",
      name: "Kitchen Preparation",
      posted_by: ACTIVE_USER,
      status: "open",
      slots_needed: 2,
      filledSlots: 0,
      date: "2099-08-08",
      start_time: "11:00:00",
      duration_minutes: 60,
    },
    devoteeName: "Ravi Das",
  };

  function inbox() {
    return (
      <SafeAreaProvider initialMetrics={AREA}>
        <CoverageInboxScreen navigation={navigation as never} route={{} as never} />
      </SafeAreaProvider>
    );
  }

  it("warns that they are already serving then, and moves it anyway", async () => {
    // "Move it" writes the time onto the seva and puts that devotee on it. A
    // suggestion made a fortnight ago is exactly the one they may since have
    // committed over, and this accept had no warning at all.
    mockRole = "president";
    mockDashboard.sevaNeedingAnswer = [COUNTERED];
    mockClashes = new Map([["counter-1", [clash()]]]);
    const screen = await render(inbox());

    await fireEvent.press(
      screen.getByLabelText("Move Kitchen Preparation to the suggested time"),
    );
    await settleSheet();

    expect(mockRespondCounter).not.toHaveBeenCalled();
    expect(screen.getByText("Ravi Das is already serving then")).toBeTruthy();

    await fireEvent.press(screen.getByLabelText("Move it anyway"));
    await settleSheet();

    expect(mockRespondCounter).toHaveBeenCalledWith({
      counterId: "counter-1",
      accept: true,
      note: null,
    });
  });

  it("moves it straight away when they are free", async () => {
    mockRole = "president";
    mockDashboard.sevaNeedingAnswer = [COUNTERED];
    mockClashes = new Map([["counter-1", []]]);
    const screen = await render(inbox());

    await fireEvent.press(
      screen.getByLabelText("Move Kitchen Preparation to the suggested time"),
    );
    await settleSheet();

    expect(mockRespondCounter).toHaveBeenCalledWith({
      counterId: "counter-1",
      accept: true,
      note: null,
    });
  });
});
