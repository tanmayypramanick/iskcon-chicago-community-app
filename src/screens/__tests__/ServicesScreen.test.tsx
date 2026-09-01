/// <reference types="jest" />

import { render } from "@testing-library/react-native";

import type { AccessRole } from "../../features/access/model";
import { usePrototypeSession } from "../../store/usePrototypeSession";
import { ServicesScreen } from "../ServicesScreen";

let mockActualRole: AccessRole = "devotee";

jest.mock("@react-navigation/native", () => ({
  useIsFocused: () => false,
}));

jest.mock("../../features/access/hooks", () => ({
  useCurrentAccessProfile: () => ({
    data: { role: mockActualRole },
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
  useDeleteSevaRegistration: () => ({
    mutate: jest.fn(),
    error: null,
    isPending: false,
  }),
  useDeleteServiceActivity: () => ({
    mutate: jest.fn(),
    error: null,
    isPending: false,
  }),
  useMarkSevaServed: () => ({
    mutate: jest.fn(),
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

const navigation = {
  navigate: jest.fn(),
};

async function renderServices(role: AccessRole) {
  mockActualRole = role;
  usePrototypeSession.setState({
    activeUserId: "service-role-test-user",
    previewRole: null,
  });

  return render(
    <ServicesScreen
      navigation={navigation as never}
      route={{ key: "services-home", name: "ServicesHome" } as never}
    />,
  );
}

describe("ServicesScreen access-level presentation", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockDashboard.services = [];
    mockDashboard.recurringTemplates = [];
    mockDashboard.devotees = [];
    mockDashboard.sevaNeedingAnswer = [];
    mockDashboard.coverageRequests = [];
  });

  it.each([
    ["president", true, true, true],
    ["tech", true, true, true],
    ["core", true, true, true],
    ["volunteer", true, false, false],
    ["devotee", false, false, false],
  ] as const)(
    "shows the correct coordinator actions for %s",
    async (role, canPost, canManageRecurring, canResolveCoverage) => {
      const screen = await renderServices(role);

      expect(screen.getByText("Find a way to help")).toBeTruthy();
      expect(screen.getByText("Log your seva")).toBeTruthy();
      expect(screen.queryByText("Scan temple QR")).toBeNull();
      expect(screen.getByText("My seva and history")).toBeTruthy();
      expect(Boolean(screen.queryByText("Post a seva request"))).toBe(canPost);
      expect(Boolean(screen.queryByText("Weekly seva"))).toBe(
        canManageRecurring,
      );
      expect(Boolean(screen.queryByText("Coverage inbox"))).toBe(
        canResolveCoverage,
      );
      expect(Boolean(screen.queryByText("Completed seva report"))).toBe(
        role === "president" || role === "tech" || role === "core",
      );

      screen.unmount();
    },
  );

  it("shows one card when the same weekly seva is mine and also needs help", async () => {
    mockActualRole = "devotee";
    mockDashboard.recurringTemplates = [
      {
        id: "weekly-flower-garlands",
        name: "Flower Garlands",
        active: true,
        participation_mode: "open",
        days_of_week: [1, 4, 6],
        start_time: "05:00:00",
        duration_minutes: 60,
        slots_needed: 2,
        assignees: [
          {
            id: "service-role-test-user",
            name: "Current Devotee",
            assignedDays: [1, 4, 6],
          },
        ],
      },
    ];
    mockDashboard.services = [
      {
        id: "weekly-occurrence",
        template_id: "weekly-flower-garlands",
        date: "2099-08-06",
        start_time: "05:00:00",
        duration_minutes: 60,
        slots_needed: 2,
        status: "open",
        participation_mode: "open",
        currentUserAssignment: {
          devotee_id: "service-role-test-user",
        },
      },
    ];

    const screen = await renderServices("devotee");

    expect(screen.getAllByText("Flower Garlands")).toHaveLength(1);
    screen.unmount();
  });

  it("restores My upcoming seva, weekly occurrences included", async () => {
    // The temple's most-missed section. A devotee covering somebody else's
    // Thursday holds nothing but an occurrence, so a list of one-off requests
    // never mentioned the seva they were actually turning up for.
    mockActualRole = "devotee";
    mockDashboard.devotees = [
      { id: "service-role-test-user", name: "Current Devotee", photo_url: null, role_name: "devotee" },
    ];
    mockDashboard.services = [
      {
        id: "covered-thursday",
        template_id: "weekly-flower-garlands",
        name: "Flower Garlands",
        date: "2099-08-06",
        start_time: "05:00:00",
        duration_minutes: 90,
        slots_needed: 2,
        filledSlots: 1,
        status: "open",
        participation_mode: "open",
        participants: [
          {
            assignment: {
              id: "asg-cover",
              status: "confirmed",
              attendance: null,
              assignment_method: "accepted_coverage_offer",
            },
            devotee: mockDashboard.devotees[0],
          },
        ],
        currentUserAssignment: null,
      },
    ];

    const screen = await renderServices("devotee");

    expect(screen.getByText("My upcoming seva")).toBeTruthy();
    expect(screen.getAllByText("Flower Garlands").length).toBeGreaterThan(0);
    // Item 2: every seva card says how long it is.
    expect(screen.getAllByText("1 hr 30 min").length).toBeGreaterThan(0);
    screen.unmount();
  });

  it("keeps a devotee off a seva they handed over", async () => {
    mockActualRole = "devotee";
    const substitute = { id: "other-devotee", name: "Tanmay Pramanick", photo_url: null, role_name: "devotee" };
    mockDashboard.devotees = [substitute];
    mockDashboard.services = [
      {
        id: "swapped",
        template_id: null,
        name: "Kitchen Preparation",
        date: "2099-08-06",
        start_time: "11:00:00",
        duration_minutes: 60,
        slots_needed: 1,
        filledSlots: 1,
        status: "full",
        participation_mode: "invite_only",
        participants: [
          {
            assignment: { id: "asg-gone", status: "withdrawn", attendance: null },
            devotee: { id: "service-role-test-user", name: "Current Devotee", photo_url: null, role_name: "devotee" },
          },
          {
            assignment: { id: "asg-sub", status: "confirmed", attendance: null },
            devotee: substitute,
          },
        ],
        currentUserAssignment: null,
      },
    ];

    const screen = await renderServices("devotee");

    expect(screen.queryByText("My upcoming seva")).toBeNull();
    expect(screen.queryByText("Kitchen Preparation")).toBeNull();
    screen.unmount();
  });
});

const ME = {
  id: "service-role-test-user",
  name: "Current Devotee",
  photo_url: null,
  role_name: "devotee",
};

/** A weekly seva this devotee is rostered on, with a date generated for it. */
function rosteredWeekly() {
  mockDashboard.devotees = [ME];
  mockDashboard.recurringTemplates = [
    {
      id: "weekly-flower-garlands",
      name: "Flower Garlands",
      active: true,
      participation_mode: "invite_only",
      days_of_week: [1, 4, 6],
      start_time: "05:00:00",
      duration_minutes: 90,
      slots_needed: 1,
      start_date: "2026-01-01",
      end_date: null,
      created_by: "someone-else",
      assignees: [{ ...ME, assignedDays: [1, 4, 6] }],
    },
  ];
  mockDashboard.services = ["2099-08-06", "2099-08-08", "2099-08-10"].map(
    (date) => ({
      id: `occ-${date}`,
      template_id: "weekly-flower-garlands",
      name: "Flower Garlands",
      date,
      start_time: "05:00:00",
      duration_minutes: 90,
      slots_needed: 1,
      filledSlots: 1,
      status: "open",
      participation_mode: "invite_only",
      participants: [
        {
          assignment: { id: `asg-${date}`, status: "confirmed", attendance: null },
          devotee: ME,
        },
      ],
      currentUserAssignment: null,
    }),
  );
}

describe("the Seva tab names one seva once", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockDashboard.services = [];
    mockDashboard.recurringTemplates = [];
    mockDashboard.devotees = [];
    mockDashboard.sevaNeedingAnswer = [];
    mockDashboard.coverageRequests = [];
  });

  it("shows a rostered weekly seva as one card carrying its next date", async () => {
    // It used to appear twice: as "Every Monday, Thursday and Saturday" and
    // again as its next dated card a screen-inch below. The temple keeps
    // asking for less, so the roster card gained the date instead.
    rosteredWeekly();
    const screen = await renderServices("devotee");

    expect(screen.getAllByText("Flower Garlands")).toHaveLength(1);
    // There is one section now — "My weekly seva" was one of the two headings
    // the temple asked us to merge — and the kind is named inside it.
    expect(screen.getByText("My upcoming seva")).toBeTruthy();
    expect(screen.getByText("Weekly seva")).toBeTruthy();
    expect(screen.queryByText("My weekly seva")).toBeNull();
    screen.unmount();
  });

  it("says on that one card which date the devotee is next down for", async () => {
    rosteredWeekly();
    const screen = await renderServices("devotee");

    expect(screen.getByText(/Aug 6/)).toBeTruthy();
    // The days it falls on used to be printed here too. One card now carries
    // only the marker saying it is weekly; "Every Monday, Thursday and
    // Saturday" is on the weekly seva's own screen with every other date.
    expect(screen.getByText("Weekly")).toBeTruthy();
    screen.unmount();
  });

  it("still says how long every card's seva runs", async () => {
    rosteredWeekly();
    const screen = await renderServices("devotee");

    expect(screen.getAllByText(/1 hr 30 min/).length).toBeGreaterThan(0);
    screen.unmount();
  });

  it("keeps a one-off request in its own group alongside", async () => {
    rosteredWeekly();
    mockDashboard.services = [
      ...mockDashboard.services,
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
            assignment: { id: "asg-one-off", status: "confirmed", attendance: null },
            devotee: ME,
          },
        ],
        currentUserAssignment: null,
      },
    ];
    const screen = await renderServices("devotee");

    // One heading, two groups under it, weekly first — the structure the
    // temple asked for in place of two separate sections.
    expect(screen.getAllByText("My upcoming seva")).toHaveLength(1);
    expect(screen.getByText("Weekly seva")).toBeTruthy();
    expect(screen.getByText("One-off seva")).toBeTruthy();
    expect(screen.getAllByText("Kitchen Preparation")).toHaveLength(1);
    expect(screen.getAllByText("Flower Garlands")).toHaveLength(1);
    screen.unmount();
  });
});

/**
 * The counter badge. `respond_to_service_offer_counter` accepts the poster or
 * `app.view_all`, so a Tech Admin and the President can answer a suggestion on
 * a seva somebody else posted — and the tab was showing them nothing to answer.
 */
describe("the coverage inbox badge counts what this account may answer", () => {
  const counteredSeva = {
    kind: "countered",
    offer: { id: "offer-1", offered_to: "arpita" },
    counter: { id: "counter-1", status: "pending", proposed_date: "2099-08-09" },
    service: {
      id: "svc-1",
      name: "Kitchen Preparation",
      posted_by: "somebody-else",
      status: "open",
      slots_needed: 2,
      filledSlots: 0,
      date: "2099-08-08",
      start_time: "11:00:00",
    },
    devoteeName: "Arpita Jadhav",
  };

  beforeEach(() => {
    jest.clearAllMocks();
    mockDashboard.services = [];
    mockDashboard.recurringTemplates = [];
    mockDashboard.devotees = [];
    mockDashboard.coverageRequests = [];
    mockDashboard.sevaNeedingAnswer = [counteredSeva];
  });

  it.each(["tech", "president"] as const)(
    "counts it for a %s, who is permitted to answer it",
    async (role) => {
      const screen = await renderServices(role);

      expect(screen.getByText("Coverage inbox")).toBeTruthy();
      expect(screen.getByText("1")).toBeTruthy();
      screen.unmount();
    },
  );

  it("counts nothing for a Community Head, whom the RPC would refuse", async () => {
    const screen = await renderServices("core");

    expect(screen.getByText("Coverage inbox")).toBeTruthy();
    expect(screen.queryByText("1")).toBeNull();
    screen.unmount();
  });

  it("counts it for the devotee who posted the seva", async () => {
    mockDashboard.sevaNeedingAnswer = [
      {
        ...counteredSeva,
        service: { ...counteredSeva.service, posted_by: "service-role-test-user" },
      },
    ];
    const screen = await renderServices("volunteer");

    // A Volunteer posts seva too, so the inbox opens for them on this alone.
    expect(screen.getByText("Coverage inbox")).toBeTruthy();
    expect(screen.getByText("1")).toBeTruthy();
    screen.unmount();
  });

  it("shows a plain devotee no inbox at all", async () => {
    const screen = await renderServices("devotee");

    expect(screen.queryByText("Coverage inbox")).toBeNull();
    screen.unmount();
  });
});

/**
 * "Things appear twice."
 *
 * The temple's most-repeated complaint, and the one the three consolidations
 * each half-solved: every section de-duplicated inside itself, and nothing
 * de-duplicated across sections — while `communitySchedule` was widened to
 * carry weekly occurrences as well as dated requests, which made it a superset
 * of almost everything above it. Every list here draws the identical
 * `SevaCard`, so an overlap is literally the same card twice.
 *
 * Wednesday 12 August 2026, 10:00 Chicago.
 */
describe("no seva is named twice on the Seva tab", () => {
  const NOW = new Date("2026-08-12T15:00:00.000Z");
  const TODAY = "2026-08-12";
  /** Postgres dow for that Wednesday. */
  const WEDNESDAY = 3;

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
    mockDashboard.devotees = [ME];
    mockDashboard.coveragePlans = [];
    mockDashboard.coverageRequests = [];
    mockDashboard.sevaNeedingAnswer = [];
  });

  const ME = {
    id: "service-role-test-user",
    name: "Current Devotee",
    photo_url: null,
  };

  function myPlace() {
    return [
      {
        assignment: {
          id: "asg-1",
          devotee_id: ME.id,
          status: "confirmed",
          attendance: null,
        },
        devotee: ME,
      },
    ];
  }

  function weeklyTemplate() {
    return {
      id: "weekly-garlands",
      name: "Flower Garlands",
      active: true,
      // invite_only, so the rota has no opening and cannot also surface under
      // "Open weekly seva" — this test is about the other pairs.
      participation_mode: "invite_only",
      days_of_week: [WEDNESDAY],
      start_time: "16:15:00",
      duration_minutes: 90,
      slots_needed: 1,
      start_date: "2020-01-01",
      end_date: null,
      created_by: "someone-else",
      assignees: [{ ...ME, assignedDays: [WEDNESDAY] }],
    };
  }

  it("names a coordinator's own weekly seva once, not as a card and a dated row", async () => {
    // My upcoming seva -> weekly roster card (its next date is today), and
    // Community schedule -> today's generated occurrence. Same name, same
    // hour, same avatars, one section apart.
    mockDashboard.recurringTemplates = [weeklyTemplate()];
    mockDashboard.services = [
      {
        id: "occ-today",
        template_id: "weekly-garlands",
        name: "Flower Garlands",
        date: TODAY,
        start_time: "16:15:00",
        duration_minutes: 90,
        slots_needed: 1,
        filledSlots: 1,
        status: "full",
        participation_mode: "invite_only",
        participants: myPlace(),
        currentUserAssignment: null,
      },
    ];

    const screen = await renderServices("president");
    expect(screen.getAllByText("Flower Garlands")).toHaveLength(1);
    screen.unmount();
  });

  it("names it once when no row has been generated for today either", async () => {
    // The other branch of the same pair: My upcoming seva -> roster card, and
    // Community schedule -> roster card, because `communityWeeklySeva` does
    // not know who is reading it.
    mockDashboard.recurringTemplates = [weeklyTemplate()];

    const screen = await renderServices("president");
    expect(screen.getAllByText("Flower Garlands")).toHaveLength(1);
    screen.unmount();
  });

  it("does not list a seva being served right now as upcoming as well", async () => {
    // 9:30 for two hours contains 10:00. It is in "Seva happening now" and was
    // also still "upcoming", because upcoming only ends at the finish instant.
    mockDashboard.services = [
      {
        id: "occ-running",
        template_id: null,
        name: "Vegetable Cutting",
        date: TODAY,
        start_time: "09:30:00",
        duration_minutes: 120,
        slots_needed: 1,
        filledSlots: 1,
        status: "full",
        participation_mode: "invite_only",
        participants: myPlace(),
        currentUserAssignment: null,
      },
    ];

    const screen = await renderServices("president");
    expect(screen.getAllByText("Vegetable Cutting")).toHaveLength(1);
    screen.unmount();
  });

  /**
   * The whole complaint in one devotee.
   *
   * Wednesday morning: they are rostered on a weekly seva, they are in the
   * kitchen serving something right now, and they have joined an open request
   * that still needs another pair of hands. Before the rule ran one way only,
   * every one of those was named in two or three sections, all drawing the
   * identical card.
   */
  it.each(["devotee", "president"] as const)(
    "names nothing twice for a %s on an open request, serving now, with a rota",
    async (role) => {
    mockDashboard.recurringTemplates = [weeklyTemplate()];
    mockDashboard.services = [
      // Their rota's occurrence today, at 4:15 PM — still to come.
      {
        id: "occ-today",
        template_id: "weekly-garlands",
        name: "Flower Garlands",
        date: TODAY,
        start_time: "16:15:00",
        duration_minutes: 90,
        slots_needed: 1,
        filledSlots: 1,
        status: "full",
        participation_mode: "invite_only",
        participants: myPlace(),
        currentUserAssignment: null,
      },
      // Being served at this minute: 9:30 for two hours contains 10:00.
      {
        id: "occ-running",
        template_id: null,
        name: "Vegetable Cutting",
        date: TODAY,
        start_time: "09:30:00",
        duration_minutes: 120,
        slots_needed: 1,
        filledSlots: 1,
        status: "full",
        participation_mode: "invite_only",
        participants: myPlace(),
        currentUserAssignment: null,
      },
      // An open request they have joined that still needs somebody: their own
      // upcoming seva AND a place where help is needed, both true at once.
      {
        id: "occ-open",
        template_id: null,
        name: "Deity Dressing",
        date: TODAY,
        start_time: "18:00:00",
        duration_minutes: 60,
        slots_needed: 3,
        filledSlots: 1,
        status: "open",
        participation_mode: "open",
        participants: myPlace(),
        currentUserAssignment: null,
      },
    ];

      const screen = await renderServices(role);

      expect(screen.getAllByText("Flower Garlands")).toHaveLength(1);
      expect(screen.getAllByText("Vegetable Cutting")).toHaveLength(1);
      expect(screen.getAllByText("Deity Dressing")).toHaveLength(1);

      screen.unmount();
    },
  );

  it("does not promise every need is covered while it is hiding one", async () => {
    // The empty state had to be reworded before the section above could be
    // thinned: a section that promises may not drop a card.
    mockDashboard.services = [
      {
        id: "occ-open",
        template_id: null,
        name: "Deity Dressing",
        date: TODAY,
        start_time: "18:00:00",
        duration_minutes: 60,
        slots_needed: 3,
        filledSlots: 1,
        status: "open",
        participation_mode: "open",
        participants: myPlace(),
        currentUserAssignment: null,
      },
    ];

    const screen = await renderServices("devotee");

    expect(screen.queryByText("All current needs are covered")).toBeNull();
    expect(screen.getByText("Nothing else needs help right now")).toBeTruthy();
    screen.unmount();
  });

  it("keeps a fourth weekly seva on the tab rather than losing it", async () => {
    // The dated rows of every weekly seva are suppressed, so capping the cards
    // at three took the fourth off the screen altogether — a disappearance, not
    // a duplicate.
    mockDashboard.recurringTemplates = ["a", "b", "c", "d"].map((suffix) => ({
      ...weeklyTemplate(),
      id: `weekly-${suffix}`,
      name: `Weekly Seva ${suffix.toUpperCase()}`,
    }));

    const screen = await renderServices("devotee");

    for (const suffix of ["A", "B", "C", "D"]) {
      expect(screen.getAllByText(`Weekly Seva ${suffix}`)).toHaveLength(1);
    }
    screen.unmount();
  });

  it("still shows the temple's day where nothing above has already named it", async () => {
    // The exclusions must not empty the community schedule of seva that is
    // genuinely only there — somebody else's invite-only seva this afternoon.
    mockDashboard.devotees = [ME, { id: "d-other", name: "Other Devotee", photo_url: null }];
    mockDashboard.services = [
      {
        id: "occ-theirs",
        template_id: null,
        name: "Deity Dressing",
        date: TODAY,
        start_time: "17:00:00",
        duration_minutes: 60,
        slots_needed: 1,
        filledSlots: 1,
        status: "full",
        participation_mode: "invite_only",
        participants: [
          {
            assignment: {
              id: "asg-other",
              devotee_id: "d-other",
              status: "confirmed",
              attendance: null,
            },
            devotee: { id: "d-other", name: "Other Devotee", photo_url: null },
          },
        ],
        currentUserAssignment: null,
      },
    ];

    const screen = await renderServices("president");
    expect(screen.getAllByText("Deity Dressing")).toHaveLength(1);
    expect(screen.queryByText("Nothing else is scheduled today.")).toBeNull();
    screen.unmount();
  });
});

/**
 * Registered seva, and finished seva, as the temple asked for them.
 *
 * "No repetitive schedules, no different weekly seva list — it's inside My
 * upcoming seva, and weekly seva only one card and not multiple cards."
 *
 * Wednesday 12 August 2026, 10:00 Chicago.
 */
describe("one section per idea, one card per seva", () => {
  const NOW = new Date("2026-08-12T15:00:00.000Z");
  const ME = {
    id: "service-role-test-user",
    name: "Current Devotee",
    photo_url: null,
    role_name: "devotee",
  };

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
    mockDashboard.devotees = [ME];
    mockDashboard.coveragePlans = [];
    mockDashboard.coverageRequests = [];
    mockDashboard.sevaNeedingAnswer = [];
    mockDashboard.verifications = [];
    mockDashboard.myVerifications = [];
  });

  it("folds a devotee's registered seva into their one-off group", async () => {
    // It had a heading of its own, four sections above "My upcoming seva" —
    // for a plain devotee, their own upcoming seva announced twice under two
    // names, with a See all that answered with no registrations at all.
    mockDashboard.verifications = [
      {
        id: "reg-1",
        devotee_id: ME.id,
        name: "Book Distribution",
        status: "verified",
        start_at: "2026-08-14T15:00:00.000Z",
        end_at: "2026-08-14T17:00:00.000Z",
        location_text: "ISKCON Chicago Temple",
        service_instance_id: null,
        devotee: ME,
        verifier: null,
        verifiedBy: null,
        created_at: "2026-08-01T00:00:00.000Z",
      },
    ];

    const screen = await renderServices("devotee");

    expect(screen.queryByText("Upcoming seva")).toBeNull();
    expect(screen.getByText("My upcoming seva")).toBeTruthy();
    expect(screen.getByText("One-off seva")).toBeTruthy();
    expect(screen.getAllByText("Book Distribution")).toHaveLength(1);
    screen.unmount();
  });

  /** Three finished dates of one weekly seva, newest last Saturday. */
  function finishedWeekly() {
    mockDashboard.recurringTemplates = [
      {
        id: "weekly-garlands",
        name: "Flower Garlands",
        active: true,
        participation_mode: "invite_only",
        days_of_week: [1, 4, 6],
        start_time: "05:00:00",
        duration_minutes: 90,
        slots_needed: 1,
        start_date: "2020-01-01",
        end_date: null,
        created_by: "someone-else",
        // Deliberately not a standing assignee: this fixture is about the
        // history card alone, and a roster card for the same seva under "My
        // upcoming seva" is a different fact about a different week.
        assignees: [],
      },
    ];
    mockDashboard.services = ["2026-08-03", "2026-08-06", "2026-08-08"].map(
      (date) => ({
        id: `occ-${date}`,
        template_id: "weekly-garlands",
        name: "Flower Garlands",
        date,
        start_time: "05:00:00",
        duration_minutes: 90,
        slots_needed: 1,
        filledSlots: 1,
        status: "completed",
        participation_mode: "invite_only",
        participants: [
          {
            assignment: {
              id: `asg-${date}`,
              devotee_id: ME.id,
              status: "completed",
              attendance: "served",
            },
            devotee: ME,
          },
        ],
        currentUserAssignment: null,
      }),
    );
  }

  it("gives a finished weekly seva one card, not one per date", async () => {
    finishedWeekly();
    const screen = await renderServices("president");

    expect(screen.getByText("Recently completed")).toBeTruthy();
    expect(screen.getAllByText("Flower Garlands")).toHaveLength(1);
    screen.unmount();
  });

  it("dates that card by the last time it happened, never a future date", async () => {
    finishedWeekly();
    const screen = await renderServices("president");

    // Sat 8 August is the newest of the three. The next occurrence — which is
    // what the See-all card used to print — is still ahead of today.
    expect(screen.getByText(/Sat, Aug 8/)).toBeTruthy();
    expect(screen.queryByText(/Aug 1[0-9]/)).toBeNull();
    screen.unmount();
  });

  it("gives a plain devotee the same one card in their own history", async () => {
    finishedWeekly();
    const screen = await renderServices("devotee");

    expect(screen.getByText("Your completed seva")).toBeTruthy();
    expect(screen.getAllByText("Flower Garlands")).toHaveLength(1);
    screen.unmount();
  });
});
