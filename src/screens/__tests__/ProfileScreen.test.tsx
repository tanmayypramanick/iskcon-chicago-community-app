/// <reference types="jest" />

import { fireEvent, render } from "@testing-library/react-native";

import { usePrototypeSession } from "../../store/usePrototypeSession";
import { ProfileScreen } from "../ProfileScreen";

jest.mock("@react-navigation/native", () => ({
  useIsFocused: () => false,
  useNavigation: () => ({ navigate: jest.fn() }),
}));

jest.mock("../../features/access/hooks", () => ({
  useCurrentAccessProfile: () => ({
    data: {
      id: "profile-test-user",
      name: "Gauranga Sharma",
      email: "devotee@example.com",
      role: "devotee",
    },
    error: null,
    refetch: jest.fn(),
  }),
  usePendingAccessRequests: () => ({
    data: [],
    error: null,
    isLoading: false,
    refetch: jest.fn(),
  }),
  useCreateAccessRequest: () => ({
    mutate: jest.fn(),
    error: null,
    refetch: jest.fn(),
  }),
  useReviewAccessRequest: () => ({
    mutate: jest.fn(),
    error: null,
  }),
}));

jest.mock("../../features/profile/hooks", () => ({
  useUpdateDevoteePhoto: () => ({ mutate: jest.fn(), isPending: false }),
  useRemoveDevoteePhoto: () => ({ mutate: jest.fn(), isPending: false }),
}));

jest.mock("../../features/presence/hooks", () => ({
  useTemplePresence: () => ({
    data: { current: null, people: [] },
    error: null,
  }),
  useTemplePresenceRealtime: jest.fn(),
}));

jest.mock("../../features/services/hooks", () => ({
  useServiceDashboard: () => ({
    data: { services: [], recurringInterests: [] },
    error: null,
    isLoading: false,
    refetch: jest.fn(),
  }),
}));

describe("ProfileScreen", () => {
  beforeEach(() => {
    usePrototypeSession.setState({
      isAuthenticated: true,
      previewRole: "devotee",
      accessRequests: [],
    });
  });

  it("previews a different access-level profile", async () => {
    const { getByRole, getAllByText, getByText } = await render(
      <ProfileScreen onSignOut={jest.fn()} />,
    );

    expect(getAllByText("Devotee")).toHaveLength(3);

    await fireEvent.press(
      getByRole("button", { name: "Preview President access" }),
    );

    expect(usePrototypeSession.getState().previewRole).toBe("president");
    expect(getAllByText("President")).toHaveLength(3);
    expect(
      getByText(
        "A clear leadership view for temple-wide service, communication, and oversight.",
      ),
    ).toBeTruthy();
  });

  /**
   * The temple moved the seva summary to "My seva and history", which this
   * page links to. Its hooks are no longer mocked here at all — the card is
   * gone from this screen, so nothing on it can read a devotee's hours.
   */
  it("no longer shows the seva summary, which moved to My seva and history", async () => {
    const { getByText, queryByText } = await render(
      <ProfileScreen onSignOut={jest.fn()} />,
    );

    expect(queryByText("Your seva")).toBeNull();
    expect(
      queryByText("Hours you have offered, and what you offered them to."),
    ).toBeNull();
    expect(getByText("My seva and history")).toBeTruthy();
  });

  it("returns to sign in from the profile", async () => {
    const onSignOut = jest.fn();
    const { getByRole } = await render(<ProfileScreen onSignOut={onSignOut} />);

    await fireEvent.press(getByRole("button", { name: "Sign out" }));

    expect(onSignOut).toHaveBeenCalledTimes(1);
  });

  it("previews an access request and President approval", async () => {
    const { getByRole, getByText, queryByText } = await render(
      <ProfileScreen onSignOut={jest.fn()} />,
    );

    await fireEvent.press(
      getByRole("button", { name: "Request Volunteer access" }),
    );
    expect(getByText("Volunteer request pending")).toBeTruthy();

    await fireEvent.press(
      getByRole("button", { name: "Preview President access" }),
    );
    await fireEvent.press(
      getByRole("button", {
        name: "Approve Gauranga Sharma's access request",
      }),
    );

    expect(usePrototypeSession.getState().accessRequests[0]).toMatchObject({
      requestedRole: "volunteer",
      status: "approved",
      reviewedByRole: "president",
    });
    expect(queryByText("Volunteer request pending")).toBeNull();
  });
});
