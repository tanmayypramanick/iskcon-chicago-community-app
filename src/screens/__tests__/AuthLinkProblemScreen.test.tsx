/// <reference types="jest" />

import { fireEvent, render, waitFor } from "@testing-library/react-native";

import { requestReplacementLink, verifyEmailCode } from "../../services/auth";
import { AuthLinkProblemScreen } from "../AuthLinkProblemScreen";

jest.mock("../../services/auth", () => ({
  EMAIL_CODE_LENGTH: 6,
  PASSWORD_MIN_LENGTH: 6,
  requestReplacementLink: jest.fn(),
  verifyEmailCode: jest.fn(),
}));

const mockRequestReplacementLink = jest.mocked(requestReplacementLink);
const mockVerifyEmailCode = jest.mocked(verifyEmailCode);

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
    mockVerifyEmailCode.mockResolvedValue({
      ok: true,
      session: { user: { id: "devotee-1" } } as never,
    });
  });

  it("says what happened and puts a new link one tap away", async () => {
    const screen = await render(
      <AuthLinkProblemScreen
        problem={EXPIRED}
        linkKind="recovery"
        onDismiss={jest.fn()}
        onVerified={jest.fn()}
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
        onVerified={jest.fn()}
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
        onVerified={jest.fn()}
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
        onVerified={jest.fn()}
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
        onVerified={jest.fn()}
      />,
    );

    await fireEvent.press(
      screen.getByRole("button", { name: "Back to sign in" }),
    );
    expect(onDismiss).toHaveBeenCalledTimes(1);
  });
  describe("the code, for a link that will not open at all", () => {
    const CODE_FIELD = "6-digit code from your email";

    it("offers the code and hands a verified reset back as a recovery", async () => {
      const onVerified = jest.fn();
      const screen = await render(
        <AuthLinkProblemScreen
          problem={EXPIRED}
          linkKind="recovery"
          onDismiss={jest.fn()}
          onVerified={onVerified}
        />,
      );

      // The address typed for a replacement link is carried across, so the
      // screen a devotee reached because something failed does not ask twice.
      await fireEvent.changeText(
        screen.getByLabelText("Email address for a new link"),
        "devotee@example.com",
      );
      await fireEvent.press(
        screen.getByRole("button", { name: "Enter a code instead" }),
      );
      expect(
        screen.queryByLabelText("Email address the code was sent to"),
      ).toBeNull();

      await fireEvent.changeText(screen.getByLabelText(CODE_FIELD), "123456");

      await waitFor(() =>
        expect(mockVerifyEmailCode).toHaveBeenCalledWith(
          expect.objectContaining({
            email: "devotee@example.com",
            purpose: "recovery",
          }),
        ),
      );
      await waitFor(() => expect(onVerified).toHaveBeenCalledWith("recovery"));
    });

    it("asks for the address when the devotee arrived without typing one", async () => {
      const screen = await render(
        <AuthLinkProblemScreen
          problem={EXPIRED}
          linkKind="signup"
          onDismiss={jest.fn()}
          onVerified={jest.fn()}
        />,
      );

      await fireEvent.press(
        screen.getByRole("button", { name: "Enter a code instead" }),
      );

      expect(screen.getByText(/Tell us which address/)).toBeTruthy();
    });

    it("does not offer a code for a link that never said what it was", async () => {
      // Guessing the OTP type would report a perfectly good code as wrong.
      const screen = await render(
        <AuthLinkProblemScreen
          problem={EXPIRED}
          linkKind="unknown"
          onDismiss={jest.fn()}
          onVerified={jest.fn()}
        />,
      );

      expect(
        screen.queryByRole("button", { name: "Enter a code instead" }),
      ).toBeNull();
    });
  });
});
