/// <reference types="jest" />

import { fireEvent, render, waitFor } from "@testing-library/react-native";

import { requestReplacementLink } from "../../services/auth";
import { AuthLinkProblemScreen } from "../AuthLinkProblemScreen";

jest.mock("../../services/auth", () => ({
  requestReplacementLink: jest.fn(),
}));

const mockRequestReplacementLink = jest.mocked(requestReplacementLink);

const EXPIRED = {
  title: "That link has expired",
  body: "For your protection a reset link opens only for a short while. Ask for a fresh one below and it will reach you in a moment.",
  canResend: true,
};

const OFFLINE = {
  title: "The temple could not be reached",
  body: "Your reset link is still good — nothing has been used up. Reconnect and open it again from your email.",
  canResend: false,
};

describe("when an email link does not open", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockRequestReplacementLink.mockResolvedValue(undefined);
  });

  it("says what happened and puts a new link one tap away", async () => {
    const screen = await render(
      <AuthLinkProblemScreen
        problem={EXPIRED}
        linkKind="recovery"
        onDismiss={jest.fn()}
      />,
    );

    expect(
      screen.getByRole("header", { name: "That link has expired" }),
    ).toBeTruthy();
    // No raw Supabase wording reaches the devotee.
    expect(screen.queryByText(/JWT|otp_expired/)).toBeNull();

    await fireEvent.changeText(
      screen.getByLabelText("Email address for a new link"),
      "devotee@example.com",
    );
    await fireEvent.press(
      screen.getByRole("button", { name: "Send me a new link" }),
    );

    await waitFor(() =>
      expect(mockRequestReplacementLink).toHaveBeenCalledWith(
        "devotee@example.com",
        "recovery",
      ),
    );
  });

  it("does not reveal whether the address has an account", async () => {
    const screen = await render(
      <AuthLinkProblemScreen
        problem={EXPIRED}
        linkKind="signup"
        onDismiss={jest.fn()}
      />,
    );

    await fireEvent.changeText(
      screen.getByLabelText("Email address for a new link"),
      "stranger@example.com",
    );
    await fireEvent.press(
      screen.getByRole("button", { name: "Send me a new link" }),
    );

    await waitFor(() =>
      expect(screen.getByText(/If that address is with us/)).toBeTruthy(),
    );
    expect(
      screen.queryByText(/no account|not registered|we found/i),
    ).toBeNull();
  });

  it("does not offer a fresh link when the connection was the fault", async () => {
    const screen = await render(
      <AuthLinkProblemScreen
        problem={OFFLINE}
        linkKind="recovery"
        onDismiss={jest.fn()}
      />,
    );

    expect(screen.getByText(/still good/i)).toBeTruthy();
    expect(screen.queryByLabelText("Email address for a new link")).toBeNull();
  });

  it("names the Gmail hand-off as the likely cause, not a broken app", async () => {
    const screen = await render(
      <AuthLinkProblemScreen
        problem={EXPIRED}
        linkKind="signup"
        onDismiss={jest.fn()}
      />,
    );

    expect(
      screen.getByText(/opened a browser instead of the app/i),
    ).toBeTruthy();
  });

  it("lets a devotee leave without sending anything", async () => {
    const onDismiss = jest.fn();
    const screen = await render(
      <AuthLinkProblemScreen
        problem={EXPIRED}
        linkKind="recovery"
        onDismiss={onDismiss}
      />,
    );

    await fireEvent.press(
      screen.getByRole("button", { name: "Back to sign in" }),
    );
    expect(onDismiss).toHaveBeenCalledTimes(1);
  });
});
