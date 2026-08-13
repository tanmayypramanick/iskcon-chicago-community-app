/// <reference types="jest" />

import { fireEvent, render } from "@testing-library/react-native";

import type { AccessRole } from "../../features/access/model";
import { usePrototypeSession } from "../../store/usePrototypeSession";
import { EditServiceRequestScreen } from "../EditServiceRequestScreen";

const ACTIVE_USER = "seva-edit-test-user";

let mockRole: AccessRole = "president";

jest.mock("../../features/access/hooks", () => ({
  useCurrentAccessProfile: () => ({
    data: { role: mockRole },
    error: null,
    isLoading: false,
    refetch: jest.fn(),
  }),
}));

const mockUpdate = jest.fn();
const mockRemove = jest.fn();

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
  useUpdateServiceRequirement: () => ({
    mutate: mockUpdate,
    error: null,
    isPending: false,
    isSuccess: false,
  }),
  useDeleteServiceRequirement: () => ({
    mutate: mockRemove,
    error: null,
    isPending: false,
    isSuccess: false,
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
const RADHA = {
  id: "radha",
  name: "Radha Devi",
  photo_url: null,
  role_name: "devotee",
};

function service(overrides: Record<string, unknown> = {}) {
  return {
    id: "svc-kitchen",
    template_id: null,
    name: "Kitchen Preparation",
    date: "2099-08-06",
    start_time: "11:00:00",
    duration_minutes: 60,
    slots_needed: 3,
    filledSlots: 0,
    status: "open",
    participation_mode: "invite_only",
    posted_by: ACTIVE_USER,
    participants: [],
    pendingInvitees: [],
    currentUserAssignment: null,
    currentUserOffer: null,
    ...overrides,
  };
}

async function renderEdit(overrides: Record<string, unknown> = {}) {
  mockDashboard.services = [service(overrides)];
  return render(
    <EditServiceRequestScreen
      navigation={navigation as never}
      route={
        {
          key: "edit-seva",
          name: "EditServiceRequest",
          params: { serviceId: "svc-kitchen" },
        } as never
      }
    />,
  );
}

beforeEach(() => {
  jest.clearAllMocks();
  mockRole = "president";
  usePrototypeSession.setState({
    activeUserId: ACTIVE_USER,
    previewRole: null,
  });
  mockDashboard.devotees = [ARPITA, RADHA];
});

describe("changing a seva request", () => {
  it("opens on the audience and places the request already has", async () => {
    const screen = await renderEdit({
      participation_mode: "invite_only",
      slots_needed: 3,
    });

    await fireEvent.press(screen.getByText("Save changes"));

    expect(mockUpdate.mock.calls[0][0]).toEqual({
      instanceId: "svc-kitchen",
      participationMode: "invite_only",
      slotsNeeded: 3,
      inviteeIds: [],
    });

    screen.unmount();
  });

  it("sends no invitations at all once it is opened to everyone", async () => {
    const screen = await renderEdit({ participation_mode: "invite_only" });

    await fireEvent.press(screen.getByText("Ask specific devotees"));
    await fireEvent.press(screen.getByLabelText("Select Radha Devi"));
    await fireEvent.press(screen.getByText("Open to everyone"));
    await fireEvent.press(screen.getByText("Save changes"));

    expect(mockUpdate.mock.calls[0][0]).toMatchObject({
      participationMode: "open",
      inviteeIds: [],
    });

    screen.unmount();
  });

  it("carries the places the coordinator dialled to", async () => {
    const screen = await renderEdit({ slots_needed: 2 });

    await fireEvent.press(screen.getByLabelText("One more place"));
    await fireEvent.press(screen.getByLabelText("One more place"));
    await fireEvent.press(screen.getByLabelText("One fewer place"));
    await fireEvent.press(screen.getByText("Save changes"));

    expect(mockUpdate.mock.calls[0][0].slotsNeeded).toBe(3);

    screen.unmount();
  });

  it("will not ask more devotees than the places it was just cut down to", async () => {
    // Turning the places down does not untick anybody, so this is the one way
    // the two can disagree — and `update_service_requirement` refuses the same
    // sum, counting invitations against places still going rather than places
    // asked for.
    const screen = await renderEdit({ slots_needed: 3, filledSlots: 1 });

    await fireEvent.press(screen.getByText("Ask specific devotees"));
    await fireEvent.press(screen.getByLabelText("Select Arpita Jadhav"));
    await fireEvent.press(screen.getByLabelText("Select Radha Devi"));
    await fireEvent.press(screen.getByLabelText("One fewer place"));
    await fireEvent.press(screen.getByText("Save changes"));

    expect(screen.getByText(/only 1 place left to fill/)).toBeTruthy();
    expect(mockUpdate).not.toHaveBeenCalled();

    screen.unmount();
  });

  it("blocks nobody from being chosen once every place is spoken for", async () => {
    const screen = await renderEdit({ slots_needed: 1, filledSlots: 1 });

    await fireEvent.press(screen.getByText("Ask specific devotees"));

    expect(
      screen.getByLabelText("Select Radha Devi").props.accessibilityState,
    ).toMatchObject({ checked: false, disabled: true });

    screen.unmount();
  });
});

describe("devotees already asked", () => {
  it("shows them as asked rather than as an empty box", async () => {
    const screen = await renderEdit({
      participation_mode: "invite_only",
      pendingInvitees: [ARPITA],
    });

    await fireEvent.press(screen.getByText("Ask specific devotees"));

    expect(
      screen.getByText("Already asked, waiting to hear back"),
    ).toBeTruthy();
    expect(
      screen.getByLabelText("Select Arpita Jadhav").props.accessibilityState,
    ).toMatchObject({ checked: true, disabled: true });

    screen.unmount();
  });

  it("does not resend their invitation when the request is saved", async () => {
    const screen = await renderEdit({
      participation_mode: "invite_only",
      pendingInvitees: [ARPITA],
    });

    await fireEvent.press(screen.getByLabelText("Select Arpita Jadhav"));
    await fireEvent.press(screen.getByLabelText("Select Radha Devi"));
    await fireEvent.press(screen.getByText("Save changes"));

    expect(mockUpdate.mock.calls[0][0].inviteeIds).toEqual(["radha"]);

    screen.unmount();
  });

  it("leaves a devotee already serving off the list entirely", async () => {
    const screen = await renderEdit({
      participation_mode: "invite_only",
      filledSlots: 1,
      participants: [
        {
          assignment: { id: "asg-1", status: "confirmed", attendance: null },
          devotee: ARPITA,
        },
      ],
    });

    expect(screen.queryByLabelText("Select Arpita Jadhav")).toBeNull();
    expect(screen.getByLabelText("Select Radha Devi")).toBeTruthy();

    screen.unmount();
  });
});

describe("who may change a seva request", () => {
  it.each([
    ["president", "somebody-else", true],
    ["tech", "somebody-else", true],
    // update_service_requirement refuses a Community Head on somebody else's
    // request, so the form must not be offered to them either.
    ["core", "somebody-else", false],
    ["volunteer", "somebody-else", false],
    ["devotee", "somebody-else", false],
    ["volunteer", ACTIVE_USER, true],
    ["devotee", ACTIVE_USER, true],
  ] as const)(
    "%s on a request posted by %s can change it: %s",
    async (role, postedBy, allowed) => {
      mockRole = role;
      const screen = await renderEdit({ posted_by: postedBy });

      expect(Boolean(screen.queryByText("Save changes"))).toBe(allowed);
      expect(
        Boolean(
          screen.queryByText("Only the devotee who posted this can change it"),
        ),
      ).toBe(!allowed);

      screen.unmount();
    },
  );

  it("says the request is gone rather than blaming the reader", async () => {
    mockDashboard.services = [];
    const screen = await render(
      <EditServiceRequestScreen
        navigation={navigation as never}
        route={
          {
            key: "edit-seva",
            name: "EditServiceRequest",
            params: { serviceId: "svc-kitchen" },
          } as never
        }
      />,
    );

    expect(
      screen.getByText("This seva request is no longer listed"),
    ).toBeTruthy();

    screen.unmount();
  });
});
