/// <reference types="jest" />

import { fireEvent, render } from "@testing-library/react-native";

import { WelcomeScreen } from "../WelcomeScreen";

describe("WelcomeScreen", () => {
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
      getByText("By continuing, you agree to our Terms & Privacy Policy."),
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

    expect(onAuthenticated).toHaveBeenCalledTimes(1);
  });

  it("switches to account creation and password reset", async () => {
    const { getByPlaceholderText, getByRole, getByText, queryByText } =
      await render(<WelcomeScreen onAuthenticated={jest.fn()} />);

    await fireEvent.press(getByRole("button", { name: "Create an account" }));
    expect(getByText("Create your account")).toBeTruthy();
    expect(getByPlaceholderText("Full name")).toBeTruthy();
    expect(getByPlaceholderText("Email address")).toBeTruthy();
    expect(getByPlaceholderText("Create password")).toBeTruthy();
    expect(getByPlaceholderText("Phone number")).toBeTruthy();
    expect(queryByText("Continue with Google")).toBeNull();

    await fireEvent.press(getByRole("button", { name: "Return to sign in" }));
    await fireEvent.press(getByRole("button", { name: "Forgot password?" }));
    expect(getByText("Reset your password")).toBeTruthy();
    expect(getByText("Send reset link")).toBeTruthy();
  });

  it("uses the phone number to verify a new account by OTP", async () => {
    const { getByPlaceholderText, getByRole, getByText, queryByText } =
      await render(<WelcomeScreen onAuthenticated={jest.fn()} />);

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
    await fireEvent.changeText(
      getByPlaceholderText("Phone number"),
      "3125550123",
    );
    await fireEvent.press(
      getByRole("button", { name: "Send phone verification" }),
    );

    expect(getByPlaceholderText("6-digit verification code")).toBeTruthy();
    expect(getByRole("button", { name: "Change phone number" })).toBeTruthy();
    expect(queryByText("Continue with Google")).toBeNull();
  });
});
