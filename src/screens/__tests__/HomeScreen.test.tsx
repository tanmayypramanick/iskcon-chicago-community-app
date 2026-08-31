/// <reference types="jest" />

import { act, fireEvent, render } from "@testing-library/react-native";

const mockNavigate = jest.fn();
const mockTabNavigate = jest.fn();

jest.mock("@react-navigation/native", () => ({
  useIsFocused: () => false,
  useNavigation: () => ({
    navigate: mockNavigate,
    getParent: () => ({ navigate: mockTabNavigate }),
  }),
}));

jest.mock("../../features/access/hooks", () => ({
  useCurrentAccessProfile: () => ({
    data: { name: "Test Devotee" },
    error: null,
    refetch: jest.fn(),
  }),
}));

jest.mock("expo-location", () => ({
  getForegroundPermissionsAsync: jest.fn().mockResolvedValue({
    granted: false,
    canAskAgain: false,
  }),
}));

jest.mock("../../lib/supabase", () => ({
  getSupabaseClient: () => ({
    auth: {
      getUser: jest.fn().mockResolvedValue({
        data: {
          user: {
            id: "home-test-user",
            email: "devotee@example.com",
            user_metadata: { full_name: "Test Devotee" },
          },
        },
      }),
    },
  }),
}));

jest.mock("../../features/announcements/hooks", () => ({
  useAnnouncements: () => ({
    data: [],
    error: null,
    isLoading: false,
    isError: false,
    refetch: jest.fn(),
  }),
  // Home's snippets carry their own heart, so the screen calls the like
  // mutation too. Mocked here only because this file replaces the whole
  // module; the real one is optimistic and needs no query client.
  useToggleAnnouncementLike: () => ({ mutate: jest.fn() }),
}));

/**
 * Home shows the newest day of darshan as a photograph above the Explore
 * grid. Mocked here for the same reason the announcements module is: this file
 * replaces whole modules, and the real hook wants a query client the screen
 * under test does not carry.
 */
let mockLatestDarshan: unknown = null;

jest.mock("../../features/dailyDarshan/hooks", () => ({
  useLatestDailyDarshan: () => ({
    data: mockLatestDarshan,
    error: null,
    isLoading: false,
    isFetching: false,
    dataUpdatedAt: Date.now(),
    refetch: jest.fn(),
  }),
}));

const mockSangasRefetch = jest.fn();

jest.mock("../../features/sanga/hooks", () => ({
  useMySangas: () => ({
    data: [
      {
        id: "sanga-1",
        name: "Kirtan Sanga",
        description: null,
        status: "approved",
        active: true,
        review_note: null,
        member_count: 12,
        is_member: true,
        is_admin: false,
        admin_id: null,
        admin_name: null,
        created_at: "2026-08-01T00:00:00.000Z",
        reviewed_at: null,
      },
      // Still with the President, so it has no thread to open and Home must
      // leave it out.
      {
        id: "sanga-2",
        name: "Waiting Sanga",
        description: null,
        status: "pending",
        active: true,
        review_note: null,
        member_count: 1,
        is_member: true,
        is_admin: true,
        admin_id: "home-test-user",
        admin_name: "Test Devotee",
        created_at: "2026-08-02T00:00:00.000Z",
        reviewed_at: null,
      },
      // Quiet, and third in the server's order: with Home showing two, it is
      // the one that has to go.
      {
        id: "sanga-3",
        name: "Bhakti Vriksha",
        description: null,
        status: "approved",
        active: true,
        review_note: null,
        member_count: 8,
        is_member: true,
        is_admin: false,
        admin_id: null,
        admin_name: null,
        created_at: "2026-08-03T00:00:00.000Z",
        reviewed_at: null,
      },
      // Last in the server's order but the only one with anything unread, so
      // Home lifts it to the top. unread_count is the field the sanga list is
      // expected to carry; Home reads it defensively and this row is what the
      // two sides agree on.
      {
        id: "sanga-4",
        name: "Prasadam Seva",
        description: null,
        status: "approved",
        active: true,
        review_note: null,
        member_count: 5,
        is_member: true,
        is_admin: false,
        admin_id: null,
        admin_name: null,
        created_at: "2026-08-04T00:00:00.000Z",
        reviewed_at: null,
        unread_count: 3,
      },
    ],
    error: null,
    isLoading: false,
    isError: false,
    refetch: mockSangasRefetch,
  }),
}));

const mockPresenceMutate = jest.fn(
  (_variables: unknown, options?: { onSuccess?: () => void }) =>
    options?.onSuccess?.(),
);

jest.mock("../../features/presence/hooks", () => ({
  useTemplePresence: () => ({
    data: { current: null, people: [] },
    error: null,
    isLoading: false,
    refetch: jest.fn(),
  }),
  useSetTemplePresence: () => ({
    mutate: mockPresenceMutate,
    error: null,
    isPending: false,
  }),
  useTemplePresenceRealtime: jest.fn(),
}));

jest.mock("../../features/services/hooks", () => ({
  useServiceDashboard: () => ({
    data: { services: [] },
    error: null,
    isLoading: false,
    refetch: jest.fn(),
  }),
  useServiceRealtime: jest.fn(),
}));

jest.mock("../../features/notifications/hooks", () => ({
  useAppNotifications: () => ({
    data: [],
    error: null,
    isLoading: false,
    refetch: jest.fn(),
  }),
  useAppNotificationsRealtime: jest.fn(),
}));

jest.mock("../../services/notifications", () => ({
  initializeNotifications: jest.fn().mockResolvedValue(true),
  registerPushToken: jest.fn().mockResolvedValue({ ok: true }),
  sendTempleArrivalReminder: jest.fn().mockResolvedValue(true),
}));

jest.mock("../../services/templeLocation", () => ({
  getCurrentTempleProximity: jest.fn(),
  startTempleGeofencingIfAllowed: jest.fn(),
}));

import { getChicagoDateKey } from "../../lib/chicagoDate";
import { usePrototypeSession } from "../../store/usePrototypeSession";
import { HomeScreen } from "../HomeScreen";

const renderHome = () => render(<HomeScreen />);

describe("HomeScreen temple presence", () => {
  beforeEach(() => {
    jest.useFakeTimers();
    jest.clearAllMocks();
    usePrototypeSession.setState({
      activeUserId: "home-test-user",
      notificationsByUser: {},
    });
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  it("changes presence only after a manual switch press and hides its toast after one second", async () => {
    const { getByRole, getByText, queryByText } = await renderHome();

    await fireEvent.press(getByRole("switch", { name: "At the temple" }));

    // The toast and the switch move with the tap, not with the server reply,
    // so the mutation is fired without an onSuccess toast callback. The
    // devotee's name travels with it so the shared "At the temple today" list
    // can show them immediately.
    expect(mockPresenceMutate).toHaveBeenCalledWith(
      expect.objectContaining({ isAtTemple: true, source: "manual" }),
    );
    expect(getByText("Checked in at the temple")).toBeTruthy();

    await act(async () => {
      jest.advanceTimersByTime(1_001);
      await Promise.resolve();
    });

    expect(queryByText("Checked in at the temple")).toBeNull();
  });

  it("opens the notification inbox from the bell", async () => {
    const { getByLabelText } = await renderHome();

    await fireEvent.press(getByLabelText("Notifications"));
    expect(mockNavigate).toHaveBeenCalledWith("Notifications");
  });
});

describe("HomeScreen sangas", () => {
  beforeEach(() => {
    jest.useFakeTimers();
    jest.clearAllMocks();
    usePrototypeSession.setState({
      activeUserId: "home-test-user",
      notificationsByUser: {},
    });
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  it("lists only approved sangas the devotee is in", async () => {
    const { getByText, queryByText } = await renderHome();

    expect(getByText("Kirtan Sanga")).toBeTruthy();
    expect(queryByText("Waiting Sanga")).toBeNull();
  });

  it("shows two sangas, the unread one first and the quiet extra dropped", async () => {
    const { getAllByRole, queryByText } = await renderHome();

    const rows = getAllByRole("button", { name: /^Open .+ chat,/ });
    expect(
      rows.map((row) => row.props.accessibilityLabel as string),
    ).toStrictEqual([
      "Open Prasadam Seva chat, 5 members",
      "Open Kirtan Sanga chat, 12 members",
    ]);
    expect(queryByText("Bhakti Vriksha")).toBeNull();
  });

  it("opens a sanga thread in the Devotees tab", async () => {
    const { getByLabelText } = await renderHome();

    await fireEvent.press(
      getByLabelText("Open Kirtan Sanga chat, 12 members"),
    );

    // `initial: false` is what keeps DevoteesHome under the sanga. Without it
    // React Navigation makes the chat that stack's initial route and the
    // header comes up with no back button.
    expect(mockTabNavigate).toHaveBeenCalledWith("Devotees", {
      screen: "SangaChat",
      params: { sangaId: "sanga-1", name: "Kirtan Sanga" },
      initial: false,
    });
  });
});

describe("HomeScreen daily darshan", () => {
  beforeEach(() => {
    jest.useFakeTimers();
    jest.clearAllMocks();
    mockLatestDarshan = null;
    usePrototypeSession.setState({
      activeUserId: "home-test-user",
      notificationsByUser: {},
    });
  });

  afterEach(() => {
    jest.useRealTimers();
    mockLatestDarshan = null;
  });

  it("shows the current day's photograph above Explore, and the card inside it", async () => {
    // The temple asked for these to be two things: a picture above the section
    // and an ordinary card within it.
    mockLatestDarshan = {
      id: "darshan-today",
      darshan_on: getChicagoDateKey(),
      note: null,
      images: [
        {
          imageUrl: "https://temple.example/a.jpg",
          deity: "Kisora Kisori",
          dressedBy: "Rukmini devi dasi",
          position: 0,
        },
        {
          imageUrl: "https://temple.example/b.jpg",
          deity: "Gaura Nitai",
          dressedBy: null,
          position: 1,
        },
      ],
      posted_by: "head-1",
      posted_by_name: "Gopal das",
      posted_by_photo_url: null,
      created_at: "2026-08-26T12:00:00.000Z",
      can_delete: false,
    };

    const { getByLabelText } = await renderHome();

    const hero = getByLabelText(
      "Daily Darshan, Today. Kisora Kisori and Gaura Nitai",
    );
    await fireEvent.press(hero);
    expect(mockNavigate).toHaveBeenCalledWith("DailyDarshan");

    // And the card is still its own thing in the grid, beside the calendar.
    await fireEvent.press(getByLabelText("Daily Darshan"));
    expect(mockNavigate).toHaveBeenCalledWith("DailyDarshan");
    expect(getByLabelText("Vaiṣṇava Calendar")).toBeTruthy();
  });

  it("draws no photograph at all on a day nothing has been posted", async () => {
    // An empty frame on Home says only that something is broken.
    const { queryByLabelText, getByLabelText } = await renderHome();

    expect(queryByLabelText(/^Daily Darshan, /)).toBeNull();
    expect(getByLabelText("Daily Darshan")).toBeTruthy();
  });
});

describe("HomeScreen community calendar", () => {
  beforeEach(() => {
    jest.useFakeTimers();
    jest.clearAllMocks();
    usePrototypeSession.setState({
      activeUserId: "home-test-user",
      notificationsByUser: {},
    });
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  it("opens the Vaisnava Calendar from Explore the community", async () => {
    const { getByLabelText } = await renderHome();

    await fireEvent.press(getByLabelText("Vaiṣṇava Calendar"));

    expect(mockNavigate).toHaveBeenCalledWith("VaisnavaCalendar");
  });
});

describe("HomeScreen cross-tab history", () => {
  beforeEach(() => {
    jest.useFakeTimers();
    jest.clearAllMocks();
    usePrototypeSession.setState({
      activeUserId: "home-test-user",
      notificationsByUser: {},
    });
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  it("does not ask for history beneath the Devotees tab's own root", async () => {
    const { getAllByLabelText } = await renderHome();

    // Press every "See all" rather than guess which one is the sangas', so the
    // invariant is asserted over whatever this screen navigates to.
    for (const control of getAllByLabelText("See all")) {
      await fireEvent.press(control);
    }

    const toDevoteesHome = mockTabNavigate.mock.calls.filter(
      ([tab, params]) =>
        tab === "Devotees" &&
        (params as { screen?: string } | undefined)?.screen === "DevoteesHome",
    );
    expect(toDevoteesHome.length).toBeGreaterThan(0);
    for (const [, params] of toDevoteesHome) {
      // DevoteesHome IS the stack's root; asking for it beneath itself would
      // stack it twice.
      expect(params).not.toHaveProperty("initial");
    }
  });
});
