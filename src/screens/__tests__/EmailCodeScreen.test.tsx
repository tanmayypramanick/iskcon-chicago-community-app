/// <reference types="jest" />

import { fireEvent, render, waitFor } from "@testing-library/react-native";

import { requestReplacementLink, verifyEmailCode } from "../../services/auth";
import { EmailCodeScreen } from "../EmailCodeScreen";

jest.mock("../../services/auth", () => ({
  EMAIL_CODE_LENGTH: 6,
  // Stated in the screen's own copy, so a mock without it would print
  // "undefined characters" at a devotee.
  PASSWORD_MIN_LENGTH: 6,
  requestReplacementLink: jest.fn(),
  verifyEmailCode: jest.fn(),
}));

const mockVerifyEmailCode = jest.mocked(verifyEmailCode);
const mockRequestReplacementLink = jest.mocked(requestReplacementLink);

const CODE_FIELD = "6-digit code from your email";
const SESSION = { user: { id: "devotee-1" } };

const show = (
  overrides: Partial<React.ComponentProps<typeof EmailCodeScreen>> = {},
) =>
  render(
    <EmailCodeScreen
      purpose={overrides.purpose ?? "recovery"}
      email={"email" in overrides ? overrides.email : "devotee@example.com"}
      requestedAt={
        "requestedAt" in overrides ? overrides.requestedAt : Date.now()
      }
      onVerified={overrides.onVerified ?? jest.fn()}
      onCancel={overrides.onCancel ?? jest.fn()}
    />,
  );

describe("entering the code from an auth email", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockVerifyEmailCode.mockResolvedValue({
      ok: true,
      session: SESSION as never,
    });
    mockRequestReplacementLink.mockResolvedValue(undefined);
  });

  describe("where the address comes from", () => {
    it("carries the address across rather than asking a second time", async () => {
      const screen = await show({ email: "devotee@example.com" });

      expect(screen.getByText(/devotee@example\.com/)).toBeTruthy();
      expect(
        screen.queryByLabelText("Email address the code was sent to"),
      ).toBeNull();

      await fireEvent.changeText(screen.getByLabelText(CODE_FIELD), "123456");

      await waitFor(() =>
        expect(mockVerifyEmailCode).toHaveBeenCalledWith(
          expect.objectContaining({ email: "devotee@example.com" }),
        ),
      );
    });

    it("asks for it, and says why, when the screen is reached cold", async () => {
      const screen = await show({ email: null, requestedAt: null });

      expect(screen.getByText(/Tell us which address/)).toBeTruthy();
      const field = screen.getByLabelText("Email address the code was sent to");

      // Nothing may be sent while there is no address to send it against, so a
      // completed code must not auto-submit into a certain failure.
      await fireEvent.changeText(screen.getByLabelText(CODE_FIELD), "123456");
      expect(mockVerifyEmailCode).not.toHaveBeenCalled();

      await fireEvent.changeText(field, "devotee@example.com");
      await fireEvent.press(
        screen.getByRole("button", { name: "Continue to a new password" }),
      );

      await waitFor(() =>
        expect(mockVerifyEmailCode).toHaveBeenCalledWith(
          expect.objectContaining({
            email: "devotee@example.com",
            code: "123456",
          }),
        ),
      );
    });

    it("lets a devotee correct an address that was carried in wrong", async () => {
      const screen = await show({ email: "typo@example.com" });

      await fireEvent.press(
        screen.getByRole("button", { name: "Use a different email address" }),
      );

      expect(
        screen.getByLabelText("Email address the code was sent to"),
      ).toBeTruthy();
    });
  });

  describe("what a refused code says", () => {
    const refuse = async (reason: string) => {
      mockVerifyEmailCode.mockResolvedValue({
        ok: false,
        reason: reason as never,
      });
      const onVerified = jest.fn();
      const screen = await show({ onVerified });
      await fireEvent.changeText(screen.getByLabelText(CODE_FIELD), "123456");
      await waitFor(() => expect(mockVerifyEmailCode).toHaveBeenCalled());
      return { screen, onVerified };
    };

    it("never lets a wrong code through to the password screen", async () => {
      const { screen, onVerified } = await refuse("wrongCode");

      expect(onVerified).not.toHaveBeenCalled();
      expect(screen.getByText(/were not right/)).toBeTruthy();
      // Nothing Supabase wrote reaches the devotee.
      expect(screen.queryByText(/otp_expired|Token has expired/)).toBeNull();
    });

    it("reads expired, wrong and rate-limited as three different things", async () => {
      const wrong = await refuse("wrongCode");
      const expired = await refuse("expiredCode");
      const limited = await refuse("tooManyAttempts");

      const wrongText = wrong.screen.getByText(/were not right/).props.children;
      const expiredText = expired.screen.getByText(/more than an hour ago/)
        .props.children;
      const limitedText =
        limited.screen.getByText(/Too many tries/).props.children;

      expect(expiredText).not.toEqual(wrongText);
      expect(limitedText).not.toEqual(wrongText);
      expect(limitedText).not.toEqual(expiredText);
      // A rate limit is not the devotee's account being wrong, and must not
      // read as one.
      expect(
        limited.screen.getByText(/nothing wrong with your account/),
      ).toBeTruthy();
    });

    it("says the code is still good when it was the connection that failed", async () => {
      const { screen } = await refuse("network");

      expect(screen.getByText(/Your code is still good/)).toBeTruthy();
    });

    it("announces the refusal rather than only drawing it", async () => {
      const { screen } = await refuse("wrongCode");

      const alert = screen.getByRole("alert");
      expect(alert.props.accessibilityLiveRegion).toBe("assertive");
    });
  });

  describe("where a good code lands", () => {
    it("sends a recovery to the password screen, not into the app", async () => {
      const onVerified = jest.fn();
      const screen = await show({ purpose: "recovery", onVerified });

      await fireEvent.changeText(screen.getByLabelText(CODE_FIELD), "123456");

      await waitFor(() => expect(onVerified).toHaveBeenCalledWith("recovery"));
    });

    it("signs a confirmed signup straight in", async () => {
      const onVerified = jest.fn();
      const screen = await show({ purpose: "signup", onVerified });

      await fireEvent.changeText(screen.getByLabelText(CODE_FIELD), "123456");

      await waitFor(() => expect(onVerified).toHaveBeenCalledWith("signedIn"));
    });
  });

  describe("the input itself", () => {
    it("offers a numeric keypad and takes exactly six digits", async () => {
      const screen = await show();
      const field = screen.getByLabelText(CODE_FIELD);

      expect(field.props.keyboardType).toBe("number-pad");
      expect(field.props.maxLength).toBe(6);
      // Lets the phone offer the code straight from the notification.
      expect(field.props.textContentType).toBe("oneTimeCode");
    });

    it("submits itself the moment the sixth digit lands", async () => {
      const screen = await show();

      await fireEvent.changeText(screen.getByLabelText(CODE_FIELD), "12345");
      expect(mockVerifyEmailCode).not.toHaveBeenCalled();

      await fireEvent.changeText(screen.getByLabelText(CODE_FIELD), "123456");
      await waitFor(() => expect(mockVerifyEmailCode).toHaveBeenCalledTimes(1));
    });

    it("does not fight a devotee correcting a code it already refused", async () => {
      mockVerifyEmailCode.mockResolvedValue({
        ok: false,
        reason: "wrongCode" as never,
      });
      const screen = await show();
      const field = screen.getByLabelText(CODE_FIELD);

      await fireEvent.changeText(field, "123456");
      await waitFor(() => expect(mockVerifyEmailCode).toHaveBeenCalledTimes(1));

      // Backspace and retype the same digit: the same refused code must not
      // fire a second request behind their back.
      await fireEvent.changeText(field, "12345");
      await fireEvent.changeText(field, "123456");
      expect(mockVerifyEmailCode).toHaveBeenCalledTimes(1);

      // A genuinely different code is a new attempt and may go.
      await fireEvent.changeText(field, "12345");
      await fireEvent.changeText(field, "123457");
      await waitFor(() => expect(mockVerifyEmailCode).toHaveBeenCalledTimes(2));
    });

    it("does not send the same code twice on a double tap", async () => {
      mockVerifyEmailCode.mockReturnValue(new Promise(() => {}) as never);
      const screen = await show();

      await fireEvent.changeText(screen.getByLabelText(CODE_FIELD), "12345");
      const button = screen.getByRole("button", {
        name: "Continue to a new password",
      });
      await fireEvent.press(button);
      await fireEvent.press(button);

      expect(mockVerifyEmailCode).toHaveBeenCalledTimes(1);
    });
  });

  describe("asking for another", () => {
    it("sends a fresh code and says so without naming the account", async () => {
      const screen = await show();

      await fireEvent.press(
        screen.getByRole("button", { name: "Send me a new code" }),
      );

      await waitFor(() =>
        expect(mockRequestReplacementLink).toHaveBeenCalledWith(
          "devotee@example.com",
          "recovery",
        ),
      );
      expect(screen.getByText(/If that address is with us/)).toBeTruthy();
      expect(screen.queryByText(/no account|not registered/i)).toBeNull();
    });

    it("leaves without verifying anything when the devotee backs out", async () => {
      const onCancel = jest.fn();
      const screen = await show({ onCancel });

      await fireEvent.press(
        screen.getByRole("button", { name: "Back to sign in" }),
      );

      expect(onCancel).toHaveBeenCalledTimes(1);
      expect(mockVerifyEmailCode).not.toHaveBeenCalled();
    });
  });
});
