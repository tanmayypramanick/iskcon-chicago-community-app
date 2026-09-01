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
    usePrototypeSession.setState({ isAuthenticated: true });
  });

  /**
   * The role-preview control and the card that described the level are gone.
   * The badge beside the devotee's name is all that is left of them, and it
   * says what the server says rather than what a developer picked.
   */
  it("shows the real access level and offers no way to preview another", async () => {
    const { getAllByText, queryByRole, queryByText } = await render(
      <ProfileScreen onSignOut={jest.fn()} />,
    );

    expect(getAllByText("Devotee")).toHaveLength(1);
    expect(
      queryByRole("button", { name: "Preview President access" }),
    ).toBeNull();
    expect(queryByText("Test access levels")).toBeNull();
    expect(queryByText("Verified Supabase access")).toBeNull();
  });

  /**
   * The page ends at Weekly seva. Two things stay below it, and both are
   * things a devotee must always be able to reach: signing out, and ending
   * the account — the second because Apple requires an app that can create an
   * account to let you end it from inside the app (5.1.1(v)), so hiding it
   * behind a support address would be a deliberate failure.
   */
  it("ends at Weekly seva, with sign out and leaving still below it", async () => {
    const { getByRole, getByText } = await render(
      <ProfileScreen onSignOut={jest.fn()} />,
    );

    expect(getByText("Weekly seva")).toBeTruthy();
    expect(getByText("Want to offer weekly seva?")).toBeTruthy();
    expect(getByRole("button", { name: "Sign out" })).toBeTruthy();
    expect(
      getByRole("button", { name: "Leaving, or deleting your account" }),
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
    expect(getByText("Change password")).toBeTruthy();
    // The row carries no subtitle: the label already says what it does, and
    // describing the mechanism there was noise on a page of plain settings rows.
    expect(queryByText("Set a new one here, without email")).toBeNull();
  });

  it("returns to sign in from the profile", async () => {
    const onSignOut = jest.fn();
    const { getByRole } = await render(<ProfileScreen onSignOut={onSignOut} />);

    await fireEvent.press(getByRole("button", { name: "Sign out" }));

    expect(onSignOut).toHaveBeenCalledTimes(1);
  });
});
