/// <reference types="jest" />

import { fireEvent, render } from "@testing-library/react-native";

import { usePrototypeSession } from "../../store/usePrototypeSession";
import { ProfileScreen } from "../ProfileScreen";

describe("ProfileScreen", () => {
  beforeEach(() => {
    usePrototypeSession.setState({
      isAuthenticated: true,
      role: "devotee",
    });
  });

  it("previews a different access-level profile", async () => {
    const { getByRole, getAllByText, getByText } = await render(
      <ProfileScreen onSignOut={jest.fn()} />,
    );

    expect(getAllByText("Devotee access")).toHaveLength(2);

    await fireEvent.press(
      getByRole("button", { name: "Preview President access" }),
    );

    expect(usePrototypeSession.getState().role).toBe("president");
    expect(getAllByText("President access")).toHaveLength(2);
    expect(
      getByText("A clear leadership view for temple-wide service, communication, and oversight."),
    ).toBeTruthy();
  });

  it("returns to sign in from the profile", async () => {
    const onSignOut = jest.fn();
    const { getByRole } = await render(
      <ProfileScreen onSignOut={onSignOut} />,
    );

    await fireEvent.press(getByRole("button", { name: "Sign out" }));

    expect(onSignOut).toHaveBeenCalledTimes(1);
  });
});
