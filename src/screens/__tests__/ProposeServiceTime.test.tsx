/// <reference types="jest" />

import { fireEvent, render } from "@testing-library/react-native";

import { usePrototypeSession } from "../../store/usePrototypeSession";
import { ProposeServiceTimeScreen } from "../ProposeServiceTimeScreen";

const ACTIVE_USER = "propose-time-test-user";

const mockPropose = jest.fn();

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
  useProposeServiceOfferAlternative: () => ({
    mutate: mockPropose,
    error: null,
    isPending: false,
    isSuccess: false,
  }),
}));

const navigation = { navigate: jest.fn(), goBack: jest.fn() };

const SERVICE = {
  id: "seva-kitchen",
  template_id: null,
  name: "Kitchen Preparation",
  date: "2099-08-06",
  start_time: "09:00:00",
  duration_minutes: 60,
  slots_needed: 1,
  filledSlots: 0,
  status: "open",
  participation_mode: "invite_only",
  posted_by: "coordinator",
  participants: [],
  pendingInvitees: [],
  currentUserAssignment: null,
  currentUserOffer: null,
};

async function renderPropose() {
  mockDashboard.services = [SERVICE];
  mockDashboard.pendingOffers = [
    {
      offer: { id: "offer-1", offered_to: ACTIVE_USER, status: "pending" },
      service: SERVICE,
      offeredByName: "Tanmay Pramanick",
    },
  ];
  return render(
    <ProposeServiceTimeScreen
      navigation={navigation as never}
      route={
        {
          key: "propose-time",
          name: "ProposeServiceTime",
          params: { offerId: "offer-1" },
        } as never
      }
    />,
  );
}

/**
 * Move the End spinner to 09:00 + `minutes`, as a devotee would. The temple's
 * time fields step in five minutes, which is exactly why the length reaching
 * the RPC has to be checked rather than assumed.
 */
type Screen = Awaited<ReturnType<typeof render>>;

async function setEnd(screen: Screen, minutes: number) {
  const end = new Date(2099, 7, 6, 9, 0);
  end.setMinutes(end.getMinutes() + minutes);
  await fireEvent.press(screen.getByLabelText("Choose end"));
  await fireEvent(screen.getByTestId("time-picker-end"), "change", {
    nativeEvent: { timestamp: end.getTime(), utcOffset: 0 },
  });
}

beforeEach(() => {
  jest.clearAllMocks();
  usePrototypeSession.setState({
    activeUserId: ACTIVE_USER,
    previewRole: null,
  });
});

describe("suggesting another time for a dated seva", () => {
  it("opens on the seva exactly as it was asked for", async () => {
    const screen = await renderPropose();

    await fireEvent.press(screen.getByText("Send this time"));

    expect(mockPropose.mock.calls[0][0]).toEqual({
      offerId: "offer-1",
      date: "2099-08-06",
      startTime: "09:00:00",
      durationMinutes: 60,
      note: null,
    });

    screen.unmount();
  });

  it("sends the length the temple will actually keep, not the raw span", async () => {
    // propose_service_offer_alternative rounds every suggestion up onto the
    // half-hour grid. A devotee who offered 45 minutes was being committed to
    // an hour without the screen ever saying so.
    const screen = await renderPropose();

    await setEnd(screen, 45);
    await fireEvent.press(screen.getByText("Send this time"));

    expect(mockPropose.mock.calls[0][0].durationMinutes).toBe(60);

    screen.unmount();
  });

  it("says on screen when the offer is being rounded up", async () => {
    const screen = await renderPropose();

    await setEnd(screen, 45);

    expect(screen.getByText(/recorded in half hours/)).toBeTruthy();
    expect(screen.getByText(/9:00 AM to 10:00 AM \(1 hr\)/)).toBeTruthy();

    screen.unmount();
  });

  it("says nothing extra when the offer already sits on the half hour", async () => {
    const screen = await renderPropose();

    await setEnd(screen, 90);

    expect(screen.queryByText(/recorded in half hours/)).toBeNull();
    await fireEvent.press(screen.getByText("Send this time"));
    expect(mockPropose.mock.calls[0][0].durationMinutes).toBe(90);

    screen.unmount();
  });

  it("raises a 20-minute offer to the half hour the database stores", async () => {
    const screen = await renderPropose();

    await setEnd(screen, 20);
    await fireEvent.press(screen.getByText("Send this time"));

    expect(mockPropose.mock.calls[0][0].durationMinutes).toBe(30);

    screen.unmount();
  });

  it("refuses an end time that is not really after the start", async () => {
    const screen = await renderPropose();

    await setEnd(screen, 10);
    await fireEvent.press(screen.getByText("Send this time"));

    expect(mockPropose).not.toHaveBeenCalled();
    expect(
      screen.getByText("The end time must be at least 15 minutes after the start."),
    ).toBeTruthy();

    screen.unmount();
  });

  it("still allows a span the rounding lands exactly on twelve hours", async () => {
    const screen = await renderPropose();

    await setEnd(screen, 715);
    await fireEvent.press(screen.getByText("Send this time"));

    expect(mockPropose.mock.calls[0][0].durationMinutes).toBe(720);

    screen.unmount();
  });

  it("refuses a suggestion the rounding would push past twelve hours", async () => {
    // The RPC's ceiling is checked against the value it stores, so 12h05m
    // becomes 12h30m and is refused here rather than by a raw server error.
    const screen = await renderPropose();

    await setEnd(screen, 725);
    await fireEvent.press(screen.getByText("Send this time"));

    expect(mockPropose).not.toHaveBeenCalled();
    expect(screen.getByText("A seva may be up to 12 hours long.")).toBeTruthy();

    screen.unmount();
  });

  it("keeps the devotee's note, and sends nothing when it is blank", async () => {
    const screen = await renderPropose();

    await fireEvent.changeText(
      screen.getByPlaceholderText("Optional — why this time suits you better"),
      "   ",
    );
    await fireEvent.press(screen.getByText("Send this time"));
    expect(mockPropose.mock.calls[0][0].note).toBeNull();

    await fireEvent.changeText(
      screen.getByPlaceholderText("Optional — why this time suits you better"),
      " I finish work at nine ",
    );
    await fireEvent.press(screen.getByText("Send this time"));
    expect(mockPropose.mock.calls[1][0].note).toBe("I finish work at nine");

    screen.unmount();
  });

  it("says so when the invitation has already been answered elsewhere", async () => {
    mockDashboard.pendingOffers = [];
    const screen = await render(
      <ProposeServiceTimeScreen
        navigation={navigation as never}
        route={
          {
            key: "propose-time",
            name: "ProposeServiceTime",
            params: { offerId: "offer-1" },
          } as never
        }
      />,
    );

    expect(
      screen.getByText("This invitation is no longer waiting for you"),
    ).toBeTruthy();

    screen.unmount();
  });
});
