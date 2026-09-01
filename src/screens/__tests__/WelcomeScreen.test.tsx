/// <reference types="jest" />

import { fireEvent, render, waitFor } from "@testing-library/react-native";
import * as WebBrowser from "expo-web-browser";

import {
  PRIVACY_POLICY_URL,
  TERMS_OF_SERVICE_URL,
} from "../../config/contact";
import {
  getAuthProviderAvailability,
  requestPasswordReset,
  requestReplacementLink,
  signInWithEmail,
  signInWithGoogle,
  signUpWithEmail,
  verifyEmailCode,
} from "../../services/auth";
import { WelcomeScreen } from "../WelcomeScreen";

jest.mock("expo-web-browser", () => ({
  maybeCompleteAuthSession: jest.fn(),
  openBrowserAsync: jest.fn(async () => ({ type: "opened" })),
  openAuthSessionAsync: jest.fn(),
}));

jest.mock("../../services/auth", () => ({
  // Mirrors the project's password_min_length; the screen states this number
  // in its own copy, so a mock that omitted it would print "undefined".
  PASSWORD_MIN_LENGTH: 6,
  EMAIL_CODE_LENGTH: 6,
  getAuthProviderAvailability: jest.fn(),
  verifyEmailCode: jest.fn(),
  requestPasswordReset: jest.fn(),
  requestReplacementLink: jest.fn(),
  signInWithEmail: jest.fn(),
  signInWithGoogle: jest.fn(),
  signUpWithEmail: jest.fn(),
}));

const mockGetAuthProviderAvailability = jest.mocked(
  getAuthProviderAvailability,
);
const mockSignInWithEmail = jest.mocked(signInWithEmail);
const mockSignInWithGoogle = jest.mocked(signInWithGoogle);
const mockSignUpWithEmail = jest.mocked(signUpWithEmail);
const mockRequestPasswordReset = jest.mocked(requestPasswordReset);
const mockRequestReplacementLink = jest.mocked(requestReplacementLink);
const mockVerifyEmailCode = jest.mocked(verifyEmailCode);

describe("WelcomeScreen", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockGetAuthProviderAvailability.mockResolvedValue({
      email: true,
      google: false,
      emailConfirmationRequired: true,
    });
    mockSignInWithEmail.mockResolvedValue({} as never);
    mockSignInWithGoogle.mockResolvedValue({} as never);
    mockSignUpWithEmail.mockResolvedValue({} as never);
    mockRequestPasswordReset.mockResolvedValue(undefined);
    mockRequestReplacementLink.mockResolvedValue(undefined);
    mockVerifyEmailCode.mockResolvedValue({
      ok: true,
      session: { user: { id: "devotee-1" } } as never,
    });
  });

  /** Fills the reset form and returns the one line the screen answers with. */
  const requestResetFor = async (address: string) => {
    const screen = await render(
      <WelcomeScreen
        onAuthenticated={jest.fn()}
        onRecoveryVerified={jest.fn()}
      />,
    );
    await fireEvent.press(
      screen.getByRole("button", { name: "Forgot password?" }),
    );
    await fireEvent.changeText(
      screen.getByPlaceholderText("Email address"),
      address,
    );
    await fireEvent.press(
      screen.getByRole("button", { name: "Send reset link" }),
    );
    await waitFor(() =>
      expect(screen.getByText(/If an account uses this email/)).toBeTruthy(),
    );
    return screen.getByText(/If an account uses this email/).props.children;
  };

  it("shows the ISKCON Chicago spiritual welcome and auth choices", async () => {
    const { getByRole, getByText, queryByText } = await render(
      <WelcomeScreen
        onAuthenticated={jest.fn()}
        onRecoveryVerified={jest.fn()}
      />,
    );

    expect(getByText("Home of Śrī Śrī Kiśora-Kiśorī")).toBeTruthy();
    expect(getByText("Come as you are")).toBeTruthy();
    expect(getByText("Grow closer to Kṛṣṇa together")).toBeTruthy();
    expect(
      getByText(
        "A loving community connected through seva, sādhana, and kīrtana.",
      ),
    ).toBeTruthy();
    expect(getByRole("button", { name: "Create an account" })).toBeTruthy();
    expect(getByText("Continue with Google")).toBeTruthy();
    expect(
      getByText(
        "By continuing, you agree to our Terms of Service & Privacy Policy.",
      ),
    ).toBeTruthy();
    expect(queryByText("Preview the app")).toBeNull();
    expect(queryByText(/visual prototype/i)).toBeNull();
  });

  it("opens the published Terms and Privacy Policy from the fine print", async () => {
    const openBrowserAsync = jest.mocked(WebBrowser.openBrowserAsync);
    const screen = await render(
      <WelcomeScreen
        onAuthenticated={jest.fn()}
        onRecoveryVerified={jest.fn()}
      />,
    );

    const terms = screen.getAllByRole("link", { name: "Terms of Service" })[0];
    const privacy = screen.getAllByRole("link", { name: "Privacy Policy" })[0];
    expect(terms).toBeTruthy();
    expect(privacy).toBeTruthy();

    await fireEvent.press(terms);
    expect(openBrowserAsync).toHaveBeenLastCalledWith(
      "https://tanmayypramanick.github.io/iskcon-chicago-community-app/terms-of-service.html",
    );

    await fireEvent.press(privacy);
    expect(openBrowserAsync).toHaveBeenLastCalledWith(
      "https://tanmayypramanick.github.io/iskcon-chicago-community-app/privacy-policy.html",
    );

    // The sentence must open the same URLs the rest of the app links to, so a
    // renamed document cannot leave it pointing at a 404.
    expect(openBrowserAsync).toHaveBeenNthCalledWith(1, TERMS_OF_SERVICE_URL);
    expect(openBrowserAsync).toHaveBeenNthCalledWith(2, PRIVACY_POLICY_URL);
  });

  it("validates an email sign-in before opening the app", async () => {
    const onAuthenticated = jest.fn();
    const { getByPlaceholderText, getByRole, getByText } = await render(
      <WelcomeScreen
        onAuthenticated={onAuthenticated}
        onRecoveryVerified={jest.fn()}
      />,
    );

    await fireEvent.press(getByRole("button", { name: "Sign in" }));
    expect(getByText("Enter a valid email address.")).toBeTruthy();

    await fireEvent.changeText(
      getByPlaceholderText("Email address"),
      "devotee@example.com",
    );
    await fireEvent.changeText(getByPlaceholderText("Password"), "haribol");
    await fireEvent.press(getByRole("button", { name: "Sign in" }));

    await waitFor(() => {
      expect(mockSignInWithEmail).toHaveBeenCalledWith(
        "devotee@example.com",
        "haribol",
      );
      expect(onAuthenticated).toHaveBeenCalledTimes(1);
    });
  });

  it("opens a Supabase session through Google", async () => {
    const onAuthenticated = jest.fn();
    mockGetAuthProviderAvailability.mockResolvedValueOnce({
      email: true,
      google: true,
      emailConfirmationRequired: true,
    });
    const { getByRole } = await render(
      <WelcomeScreen
        onAuthenticated={onAuthenticated}
        onRecoveryVerified={jest.fn()}
      />,
    );

    await waitFor(() =>
      expect(mockGetAuthProviderAvailability).toHaveBeenCalled(),
    );
    await fireEvent.press(
      getByRole("button", { name: "Continue with Google" }),
    );

    await waitFor(() => {
      expect(mockSignInWithGoogle).toHaveBeenCalledTimes(1);
      expect(onAuthenticated).toHaveBeenCalledTimes(1);
    });
  });

  it("switches to account creation and password reset", async () => {
    const { getByPlaceholderText, getByRole, getByText, queryByText } =
      await render(
        <WelcomeScreen
          onAuthenticated={jest.fn()}
          onRecoveryVerified={jest.fn()}
        />,
      );

    await fireEvent.press(getByRole("button", { name: "Create an account" }));
    await waitFor(() =>
      expect(mockGetAuthProviderAvailability).toHaveBeenCalled(),
    );
    expect(getByText("Create your account")).toBeTruthy();
    expect(getByPlaceholderText("Full name")).toBeTruthy();
    expect(getByPlaceholderText("Email address")).toBeTruthy();
    expect(getByPlaceholderText("Create password")).toBeTruthy();
    expect(queryByText(/phone/i)).toBeNull();
    expect(queryByText("Continue with Google")).toBeNull();

    await fireEvent.press(getByRole("button", { name: "Return to sign in" }));
    await fireEvent.press(getByRole("button", { name: "Forgot password?" }));
    expect(getByText("Reset your password")).toBeTruthy();
    expect(getByText("Send reset link")).toBeTruthy();
  });

  it("creates an account with name, email, and password only", async () => {
    const onAuthenticated = jest.fn();
    const { getByPlaceholderText, getByRole } = await render(
      <WelcomeScreen
        onAuthenticated={onAuthenticated}
        onRecoveryVerified={jest.fn()}
      />,
    );

    await fireEvent.press(getByRole("button", { name: "Create an account" }));

    await fireEvent.changeText(
      getByPlaceholderText("Full name"),
      "Gauranga Sharma",
    );
    await fireEvent.changeText(
      getByPlaceholderText("Email address"),
      "devotee@example.com",
    );
    await fireEvent.changeText(
      getByPlaceholderText("Create password"),
      "haribol8",
    );
    await fireEvent.press(getByRole("button", { name: "Create account" }));

    await waitFor(() => {
      expect(mockSignUpWithEmail).toHaveBeenCalledWith({
        name: "Gauranga Sharma",
        email: "devotee@example.com",
        password: "haribol8",
      });
      expect(onAuthenticated).toHaveBeenCalledTimes(1);
    });
  });

  it("asks an email-confirmation signup to confirm before signing in", async () => {
    mockSignUpWithEmail.mockResolvedValueOnce(null);
    const { getByPlaceholderText, getByRole, getByText } = await render(
      <WelcomeScreen
        onAuthenticated={jest.fn()}
        onRecoveryVerified={jest.fn()}
      />,
    );

    await fireEvent.press(getByRole("button", { name: "Create an account" }));
    await fireEvent.changeText(
      getByPlaceholderText("Full name"),
      "Gauranga Sharma",
    );
    await fireEvent.changeText(
      getByPlaceholderText("Email address"),
      "devotee@example.com",
    );
    await fireEvent.changeText(
      getByPlaceholderText("Create password"),
      "haribol8",
    );
    await fireEvent.press(getByRole("button", { name: "Create account" }));

    await waitFor(() => {
      expect(
        getByText(
          "Welcome. Open the private verification link sent from tech@iskconchicago.com on this phone, then return here to sign in.",
        ),
      ).toBeTruthy();
    });
  });

  it("answers a reset request the same way for any address", async () => {
    // Supabase deliberately returns success whether or not the address has an
    // account. If the copy varied, the form would become a way of finding out
    // which devotees are members.
    const known = await requestResetFor("devotee@example.com");
    const stranger = await requestResetFor("nobody@example.com");

    expect(known).toEqual(stranger);
    expect(String(known)).not.toMatch(
      /no account|not found|already registered|we could not find|does not exist/i,
    );
  });

  it("offers another confirmation link to a devotee whose link never opened", async () => {
    // Gmail's in-app browser often refuses to hand a custom scheme to the app,
    // so the sign-in they were sent back to would fail with no way forward.
    mockSignUpWithEmail.mockResolvedValueOnce(null);
    const screen = await render(
      <WelcomeScreen
        onAuthenticated={jest.fn()}
        onRecoveryVerified={jest.fn()}
      />,
    );

    await fireEvent.press(
      screen.getByRole("button", { name: "Create an account" }),
    );
    await fireEvent.changeText(
      screen.getByPlaceholderText("Full name"),
      "Gauranga Sharma",
    );
    await fireEvent.changeText(
      screen.getByPlaceholderText("Email address"),
      "devotee@example.com",
    );
    await fireEvent.changeText(
      screen.getByPlaceholderText("Create password"),
      "haribol8",
    );
    await fireEvent.press(
      screen.getByRole("button", { name: "Create account" }),
    );

    const resend = await waitFor(() =>
      screen.getByRole("button", { name: "Send the confirmation link again" }),
    );
    expect(
      screen.getByText(/opened a browser rather than the app/i),
    ).toBeTruthy();

    await fireEvent.press(resend);
    await waitFor(() =>
      expect(mockRequestReplacementLink).toHaveBeenCalledWith(
        "devotee@example.com",
        "signup",
      ),
    );
    expect(screen.getByText(/If that address is with us/)).toBeTruthy();
  });

  it("claims nothing was verified on an ordinary sign-in", async () => {
    // The verified confirmation belongs only to a consumed email link. Sign-in
    // must never borrow it.
    const screen = await render(
      <WelcomeScreen
        onAuthenticated={jest.fn()}
        onRecoveryVerified={jest.fn()}
      />,
    );

    await fireEvent.changeText(
      screen.getByPlaceholderText("Email address"),
      "devotee@example.com",
    );
    await fireEvent.changeText(
      screen.getByPlaceholderText("Password"),
      "haribol",
    );
    await fireEvent.press(screen.getByRole("button", { name: "Sign in" }));

    await waitFor(() => expect(mockSignInWithEmail).toHaveBeenCalled());
    expect(screen.queryByText("Your email is verified")).toBeNull();
    expect(screen.queryByText(/verified/i)).toBeNull();
  });
  describe("the six-digit code, for the devotees the button cannot reach", () => {
    const CODE_FIELD = "6-digit code from your email";

    const askForAReset = async (onRecoveryVerified = jest.fn()) => {
      const screen = await render(
        <WelcomeScreen
          onAuthenticated={jest.fn()}
          onRecoveryVerified={onRecoveryVerified}
        />,
      );
      await fireEvent.press(
        screen.getByRole("button", { name: "Forgot password?" }),
      );
      await fireEvent.changeText(
        screen.getByPlaceholderText("Email address"),
        "devotee@example.com",
      );
      await fireEvent.press(
        screen.getByRole("button", { name: "Send reset link" }),
      );
      await waitFor(() => expect(mockRequestPasswordReset).toHaveBeenCalled());
      return screen;
    };

    it("is not offered until an email with a code in it has been sent", async () => {
      const screen = await render(
        <WelcomeScreen
          onAuthenticated={jest.fn()}
          onRecoveryVerified={jest.fn()}
        />,
      );

      await fireEvent.press(
        screen.getByRole("button", { name: "Forgot password?" }),
      );
      expect(
        screen.queryByRole("button", { name: "Enter a code instead" }),
      ).toBeNull();
    });

    it("carries the address the devotee just typed, rather than asking twice", async () => {
      const screen = await askForAReset();

      await fireEvent.press(
        screen.getByRole("button", { name: "Enter a code instead" }),
      );

      expect(screen.getByText(/devotee@example\.com/)).toBeTruthy();
      expect(
        screen.queryByLabelText("Email address the code was sent to"),
      ).toBeNull();
    });

    it("ends a reset code on Choose a new password, exactly where the link ends", async () => {
      const onRecoveryVerified = jest.fn();
      const screen = await askForAReset(onRecoveryVerified);

      await fireEvent.press(
        screen.getByRole("button", { name: "Enter a code instead" }),
      );
      await fireEvent.changeText(screen.getByLabelText(CODE_FIELD), "123456");

      await waitFor(() =>
        expect(mockVerifyEmailCode).toHaveBeenCalledWith(
          expect.objectContaining({
            email: "devotee@example.com",
            code: "123456",
            purpose: "recovery",
          }),
        ),
      );
      // Not into the app: they are signed in but still do not know their
      // password, which is the whole reason the link raises the same gate.
      await waitFor(() => expect(onRecoveryVerified).toHaveBeenCalledTimes(1));
    });

    it("never reaches the password screen on a code the server refused", async () => {
      mockVerifyEmailCode.mockResolvedValue({
        ok: false,
        reason: "wrongCode" as never,
      });
      const onRecoveryVerified = jest.fn();
      const screen = await askForAReset(onRecoveryVerified);

      await fireEvent.press(
        screen.getByRole("button", { name: "Enter a code instead" }),
      );
      await fireEvent.changeText(screen.getByLabelText(CODE_FIELD), "123456");

      await waitFor(() => expect(mockVerifyEmailCode).toHaveBeenCalled());
      expect(onRecoveryVerified).not.toHaveBeenCalled();
      expect(screen.getByText(/were not right/)).toBeTruthy();
    });

    it("signs a devotee in on a confirmation code from the sign-up they just made", async () => {
      mockSignUpWithEmail.mockResolvedValueOnce(null);
      const onAuthenticated = jest.fn();
      const screen = await render(
        <WelcomeScreen
          onAuthenticated={onAuthenticated}
          onRecoveryVerified={jest.fn()}
        />,
      );

      await fireEvent.press(
        screen.getByRole("button", { name: "Create an account" }),
      );
      await fireEvent.changeText(
        screen.getByPlaceholderText("Full name"),
        "Gauranga Sharma",
      );
      await fireEvent.changeText(
        screen.getByPlaceholderText("Email address"),
        "devotee@example.com",
      );
      await fireEvent.changeText(
        screen.getByPlaceholderText("Create password"),
        "haribol8",
      );
      await fireEvent.press(
        screen.getByRole("button", { name: "Create account" }),
      );

      const enterCode = await waitFor(() =>
        screen.getByRole("button", { name: "Enter a code instead" }),
      );
      await fireEvent.press(enterCode);
      await fireEvent.changeText(screen.getByLabelText(CODE_FIELD), "123456");

      await waitFor(() =>
        expect(mockVerifyEmailCode).toHaveBeenCalledWith(
          expect.objectContaining({ purpose: "signup" }),
        ),
      );
      await waitFor(() => expect(onAuthenticated).toHaveBeenCalledTimes(1));
    });
  });
});
