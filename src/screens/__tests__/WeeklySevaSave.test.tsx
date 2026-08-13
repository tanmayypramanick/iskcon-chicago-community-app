/// <reference types="jest" />

import { fireEvent, render } from "@testing-library/react-native";

import { usePrototypeSession } from "../../store/usePrototypeSession";
import { CreateRecurringServiceScreen } from "../CreateRecurringServiceScreen";

const ACTIVE_USER = "weekly-save-test-user";

jest.mock("../../features/access/hooks", () => ({
  useCurrentAccessProfile: () => ({
    data: { role: "president" },
    error: null,
    isLoading: false,
    refetch: jest.fn(),
  }),
}));

const mockCreate = jest.fn();
const mockUpdate = jest.fn();
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

jest.mock("../../features/services/hooks", () => ({
  useServiceDashboard: () => ({
    data: mockDashboard,
    error: null,
    isLoading: false,
  }),
  useCreateRecurringService: () => ({
    mutate: mockCreate,
    error: null,
    isPending: false,
  }),
  useUpdateRecurringService: () => ({
    mutate: mockUpdate,
    error: null,
    isPending: false,
  }),
  useDeleteRecurringService: () => ({
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

const navigation = { navigate: jest.fn(), goBack: jest.fn(), popTo: jest.fn() };

const ARPITA = {
  id: "devotee-arpita",
  name: "Arpita Jadhav",
  photo_url: null,
  role_name: "devotee",
};
const RADHA = {
  id: "devotee-radha",
  name: "Radha Devi",
  photo_url: null,
  role_name: "devotee",
};

const GARLANDS = {
  id: "type-garlands",
  name: "Flower Garlands",
  category: "deity-worship",
  is_active: true,
};

/**
 * A weekly seva shaped exactly as the temple's own rows are: a catalog seva,
 * several days, a half-hour-grid start, an open-ended run.
 */
function template(overrides: Record<string, unknown> = {}) {
  return {
    id: "weekly-garlands",
    service_type_id: GARLANDS.id,
    custom_name: null,
    serviceType: GARLANDS,
    name: "Flower Garlands",
    day_of_week: 1,
    days_of_week: [1, 4, 6],
    start_time: "05:00:00",
    duration_minutes: 90,
    slots_needed: 2,
    participation_mode: "invite_only",
    start_date: "2026-01-05",
    end_date: null,
    created_by: ACTIVE_USER,
    active: true,
    created_at: "2026-01-01T00:00:00.000Z",
    updated_at: "2026-01-01T00:00:00.000Z",
    assignees: [],
    ...overrides,
  };
}

async function renderEdit(templateRow: Record<string, unknown>) {
  mockDashboard.recurringTemplates = [templateRow];
  return render(
    <CreateRecurringServiceScreen
      navigation={navigation as never}
      route={
        {
          key: "edit-weekly",
          name: "CreateRecurringService",
          params: { templateId: templateRow.id },
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
  mockDashboard.devotees = [ARPITA, RADHA];
  mockDashboard.serviceTypes = [GARLANDS];
  mockDashboard.recurringTemplates = [];
});

describe("editing a weekly seva keeps every field it was created with", () => {
  it("sends back exactly what the template holds when nothing is touched", async () => {
    const screen = await renderEdit(template({ assignees: [{ ...ARPITA, assignedDays: [1, 4, 6] }] }));

    await fireEvent.press(screen.getByText("Save weekly seva"));

    expect(mockUpdate).toHaveBeenCalledTimes(1);
    // Every field the create form sends has to survive a save that changed
    // nothing. A dropped weekday silently cancels occurrences; a dropped end
    // date turns a term-limited seva into a permanent one.
    expect(mockUpdate.mock.calls[0][0]).toEqual({
      templateId: "weekly-garlands",
      serviceTypeId: "type-garlands",
      customName: null,
      daysOfWeek: [1, 4, 6],
      startTime: "05:00:00",
      durationMinutes: 90,
      slotsNeeded: 2,
      participationMode: "invite_only",
      startDate: "2026-01-05",
      endDate: null,
      inviteeIds: [],
    });

    screen.unmount();
  });

  it("keeps a custom name and a fixed end date through the round trip", async () => {
    const screen = await renderEdit(
      template({
        service_type_id: null,
        serviceType: null,
        custom_name: "Gaura Purnima kitchen",
        name: "Gaura Purnima kitchen",
        days_of_week: [0],
        start_time: "17:30:00",
        duration_minutes: 150,
        slots_needed: 4,
        participation_mode: "open",
        start_date: "2026-02-01",
        end_date: "2026-05-31",
      }),
    );

    await fireEvent.press(screen.getByText("Save weekly seva"));

    expect(mockUpdate.mock.calls[0][0]).toEqual({
      templateId: "weekly-garlands",
      serviceTypeId: null,
      customName: "Gaura Purnima kitchen",
      daysOfWeek: [0],
      startTime: "17:30:00",
      durationMinutes: 150,
      slotsNeeded: 4,
      participationMode: "open",
      startDate: "2026-02-01",
      endDate: "2026-05-31",
      inviteeIds: [],
    });

    screen.unmount();
  });

  it("carries a duration that runs past midnight rather than turning it negative", async () => {
    const screen = await renderEdit(
      template({ start_time: "22:00:00", duration_minutes: 360 }),
    );

    await fireEvent.press(screen.getByText("Save weekly seva"));

    expect(mockUpdate.mock.calls[0][0]).toMatchObject({
      startTime: "22:00:00",
      durationMinutes: 360,
    });

    screen.unmount();
  });

  it("saves an invite-only weekly seva nobody has accepted yet", async () => {
    // Most of the temple's real weekly seva are in exactly this state: invite
    // only, with every invitation still unanswered and so no active assignee.
    // Requiring a name before saving made them impossible to reschedule.
    const screen = await renderEdit(template({ assignees: [] }));

    await fireEvent.press(screen.getByText("Save weekly seva"));

    expect(
      screen.queryByText("Choose at least one devotee to invite."),
    ).toBeNull();
    expect(mockUpdate).toHaveBeenCalledTimes(1);

    screen.unmount();
  });

  it("still insists on a devotee when the weekly seva is first created", async () => {
    mockDashboard.recurringTemplates = [];
    const screen = await render(
      <CreateRecurringServiceScreen
        navigation={navigation as never}
        route={
          {
            key: "new-weekly",
            name: "CreateRecurringService",
            params: undefined,
          } as never
        }
      />,
    );

    await fireEvent.press(screen.getByLabelText("Flower Garlands"));
    await fireEvent.press(screen.getByText("Ask specific devotees"));
    await fireEvent.press(screen.getByText("Create weekly seva"));

    expect(
      screen.getByText("Choose at least one devotee to invite."),
    ).toBeTruthy();
    expect(mockCreate).not.toHaveBeenCalled();

    screen.unmount();
  });
});

describe("the weekly-seva invitation list never promises a removal", () => {
  it("shows a standing assignee as locked, not as a box that can be unticked", async () => {
    const screen = await renderEdit(
      template({ assignees: [{ ...ARPITA, assignedDays: [1, 4, 6] }] }),
    );

    // update_service_template_v2 skips anyone already active, so a tick box
    // beside Arpita would be a control with no effect in either direction.
    expect(
      screen.getByText("Already serving this weekly seva"),
    ).toBeTruthy();
    const row = screen.getByLabelText("Select Arpita Jadhav");
    expect(row.props.accessibilityState).toMatchObject({
      checked: true,
      disabled: true,
    });

    screen.unmount();
  });

  it("cannot be made to drop a standing assignee by tapping their row", async () => {
    const screen = await renderEdit(
      template({ assignees: [{ ...ARPITA, assignedDays: [1, 4, 6] }] }),
    );

    await fireEvent.press(screen.getByLabelText("Select Arpita Jadhav"));

    // The tap must leave her exactly as she was. Letting it untick her showed
    // the coordinator a removal the RPC never performs.
    expect(
      screen.getByLabelText("Select Arpita Jadhav").props.accessibilityState,
    ).toMatchObject({ checked: true, disabled: true });

    await fireEvent.press(screen.getByText("Save weekly seva"));
    expect(mockUpdate.mock.calls[0][0].inviteeIds).toEqual([]);

    screen.unmount();
  });

  it("still lets a coordinator invite somebody new alongside them", async () => {
    const screen = await renderEdit(
      template({ assignees: [{ ...ARPITA, assignedDays: [1, 4, 6] }] }),
    );

    await fireEvent.press(screen.getByLabelText("Select Radha Devi"));
    await fireEvent.press(screen.getByText("Save weekly seva"));

    expect(mockUpdate.mock.calls[0][0].inviteeIds).toEqual(["devotee-radha"]);

    screen.unmount();
  });
});

describe("weekly-seva days", () => {
  it("sends the days that are ticked, not the ones it opened with", async () => {
    const screen = await renderEdit(template({ days_of_week: [1, 4, 6] }));

    // Thursday off, Tuesday on.
    await fireEvent.press(screen.getByText("Thu"));
    await fireEvent.press(screen.getByText("Tue"));
    await fireEvent.press(screen.getByText("Save weekly seva"));

    expect(mockUpdate.mock.calls[0][0].daysOfWeek).toEqual([1, 2, 6]);

    screen.unmount();
  });

  it("refuses to save a weekly seva with no day at all", async () => {
    const screen = await renderEdit(template({ days_of_week: [1] }));

    await fireEvent.press(screen.getByText("Mon"));
    await fireEvent.press(screen.getByText("Save weekly seva"));

    expect(screen.getByText("Choose at least one day each week.")).toBeTruthy();
    expect(mockUpdate).not.toHaveBeenCalled();

    screen.unmount();
  });
});
