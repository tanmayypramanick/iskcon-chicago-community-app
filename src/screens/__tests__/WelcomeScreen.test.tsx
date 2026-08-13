/// <reference types="jest" />

import { fireEvent, render, waitFor } from "@testing-library/react-native";

import {
  getAuthProviderAvailability,
  signInWithEmail,
  signInWithGoogle,
  signUpWithEmail,
} from "../../services/auth";
import { WelcomeScreen } from "../WelcomeScreen";

jest.mock("../../services/auth", () => ({
  getAuthProviderAvailability: jest.fn(),
  requestPasswordReset: jest.fn(),
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
  });

  it("shows the ISKCON Chicago spiritual welcome and auth choices", async () => {
    const { getByRole, getByText, queryByText } = await render(
      <WelcomeScreen onAuthenticated={jest.fn()} />,
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

  it("validates an email sign-in before opening the app", async () => {
    const onAuthenticated = jest.fn();
    const { getByPlaceholderText, getByRole, getByText } = await render(
      <WelcomeScreen onAuthenticated={onAuthenticated} />,
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
      <WelcomeScreen onAuthenticated={onAuthenticated} />,
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
      await render(<WelcomeScreen onAuthenticated={jest.fn()} />);

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
      <WelcomeScreen onAuthenticated={onAuthenticated} />,
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
      "haribol",
    );
    await fireEvent.press(getByRole("button", { name: "Create account" }));

    await waitFor(() => {
      expect(mockSignUpWithEmail).toHaveBeenCalledWith({
        name: "Gauranga Sharma",
        email: "devotee@example.com",
        password: "haribol",
      });
      expect(onAuthenticated).toHaveBeenCalledTimes(1);
    });
  });

  it("asks an email-confirmation signup to confirm before signing in", async () => {
    mockSignUpWithEmail.mockResolvedValueOnce(null);
    const { getByPlaceholderText, getByRole, getByText } = await render(
      <WelcomeScreen onAuthenticated={jest.fn()} />,
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
      "haribol",
    );
    await fireEvent.press(getByRole("button", { name: "Create account" }));

    await waitFor(() => {
      expect(
        getByText(
          "Account created. Check your email to confirm it, then sign in.",
        ),
      ).toBeTruthy();
    });
  });
});
