/// <reference types="jest" />

import { fireEvent, render } from "@testing-library/react-native";

import { dateToKey } from "../../features/services/format";
import { usePrototypeSession } from "../../store/usePrototypeSession";
import { ReportUnavailableScreen } from "../ReportUnavailableScreen";

const ACTIVE_USER = "report-unavailable-test-user";

const mockReport = jest.fn();

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
  useReportWeeklyServiceUnavailable: () => ({
    mutate: mockReport,
    error: null,
    isPending: false,
  }),
}));

const navigation = { navigate: jest.fn(), goBack: jest.fn(), popToTop: jest.fn() };

/**
 * The next Monday from today, so the occurrence the screen prefills from is
 * always still ahead — `report_weekly_service_unavailable` refuses a date that
 * has already passed, and a fixture pinned to a calendar date would start
 * failing for that reason rather than for the reason it was written.
 */
function nextMonday() {
  const date = new Date();
  date.setHours(12, 0, 0, 0);
  date.setDate(date.getDate() + ((8 - date.getDay()) % 7 || 7));
  return date;
}

const MONDAY = nextMonday();
const MONDAY_KEY = dateToKey(MONDAY);

const TEMPLATE = {
  id: "weekly-garlands",
  name: "Flower Garlands",
  days_of_week: [1, 4, 6],
  start_time: "05:00:00",
  duration_minutes: 90,
  slots_needed: 1,
  participation_mode: "invite_only",
  active: true,
  assignees: [],
};

const OCCURRENCE = {
  id: "occ-monday",
  template_id: "weekly-garlands",
  name: "Flower Garlands",
  date: MONDAY_KEY,
  start_time: "05:00:00",
  duration_minutes: 90,
  slots_needed: 1,
  filledSlots: 1,
  status: "open",
  participation_mode: "invite_only",
  participants: [],
  pendingInvitees: [],
  currentUserAssignment: null,
};

async function renderReport() {
  mockDashboard.recurringTemplates = [TEMPLATE];
  mockDashboard.services = [OCCURRENCE];
  return render(
    <ReportUnavailableScreen
      navigation={navigation as never}
      route={
        {
          key: "report-unavailable",
          name: "ReportUnavailable",
          params: { serviceId: "occ-monday" },
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
});

describe("reporting unavailability on a weekly seva", () => {
  it("sends one occurrence as that single date", async () => {
    const screen = await renderReport();

    await fireEvent.press(screen.getByText("Request weekly-seva coverage"));

    expect(mockReport).toHaveBeenCalledTimes(1);
    expect(mockReport.mock.calls[0][0]).toEqual({
      templateId: "weekly-garlands",
      scope: "occurrence",
      dateFrom: MONDAY_KEY,
      // The RPC clamps this itself, but sending the same day keeps the request
      // the coordinator reads identical to the one the devotee sent.
      dateTo: MONDAY_KEY,
      daysOfWeek: [1],
      reason: "",
    });

    screen.unmount();
  });

  it("sends the chosen weekdays and both ends for a date range", async () => {
    const screen = await renderReport();

    await fireEvent.press(screen.getByText("A date range"));
    // Thursday off; Monday and Saturday remain.
    await fireEvent.press(screen.getByText("Thursday"));
    await fireEvent.press(screen.getByText("Request weekly-seva coverage"));

    const sent = mockReport.mock.calls[0][0];
    expect(sent.scope).toBe("date_range");
    expect(sent.daysOfWeek).toEqual([1, 6]);
    expect(sent.dateFrom).toBe(MONDAY_KEY);
    expect(sent.dateTo).not.toBeNull();
    expect(sent.dateTo > sent.dateFrom).toBe(true);

    screen.unmount();
  });

  it("sends no end date at all when the release is from a date onward", async () => {
    const screen = await renderReport();

    await fireEvent.press(screen.getByText("From a date onward"));
    await fireEvent.press(screen.getByText("Saturday"));
    await fireEvent.press(screen.getByText("Request weekly-seva coverage"));

    expect(mockReport.mock.calls[0][0]).toMatchObject({
      scope: "forever",
      dateTo: null,
      daysOfWeek: [1, 4],
    });

    screen.unmount();
  });

  it("keeps the reason the devotee typed", async () => {
    const screen = await renderReport();

    await fireEvent.changeText(
      screen.getByLabelText("Optional reason for being unavailable"),
      "  Travelling to Mayapur  ",
    );
    await fireEvent.press(screen.getByText("Request weekly-seva coverage"));

    expect(mockReport.mock.calls[0][0].reason).toBe("Travelling to Mayapur");

    screen.unmount();
  });

  it("does not silently retick every day when the last one is cleared", async () => {
    // The prefill used to be keyed off "no days chosen yet", so clearing the
    // last weekday read as "not filled in" and put all three back — along with
    // the dates the devotee had already chosen.
    const screen = await renderReport();

    await fireEvent.press(screen.getByText("A date range"));
    await fireEvent.press(screen.getByText("Monday"));
    await fireEvent.press(screen.getByText("Thursday"));
    await fireEvent.press(screen.getByText("Saturday"));
    await fireEvent.press(screen.getByText("Request weekly-seva coverage"));

    expect(mockReport).not.toHaveBeenCalled();
    expect(screen.getByText("Choose at least one weekly-seva day.")).toBeTruthy();

    screen.unmount();
  });

  it("lets the devotee reselect after clearing every day", async () => {
    const screen = await renderReport();

    await fireEvent.press(screen.getByText("A date range"));
    await fireEvent.press(screen.getByText("Monday"));
    await fireEvent.press(screen.getByText("Thursday"));
    await fireEvent.press(screen.getByText("Saturday"));
    await fireEvent.press(screen.getByText("Thursday"));
    await fireEvent.press(screen.getByText("Request weekly-seva coverage"));

    expect(mockReport.mock.calls[0][0].daysOfWeek).toEqual([4]);

    screen.unmount();
  });

  it("says so rather than crashing when the weekly seva has gone", async () => {
    mockDashboard.recurringTemplates = [];
    mockDashboard.services = [];
    const screen = await render(
      <ReportUnavailableScreen
        navigation={navigation as never}
        route={
          {
            key: "report-unavailable",
            name: "ReportUnavailable",
            params: { serviceId: "occ-monday" },
          } as never
        }
      />,
    );

    expect(
      screen.getByText("This weekly seva is no longer available."),
    ).toBeTruthy();

    screen.unmount();
  });
});
