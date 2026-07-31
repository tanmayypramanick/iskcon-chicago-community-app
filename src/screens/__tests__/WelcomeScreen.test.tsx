/// <reference types="jest" />

import { fireEvent, render } from "@testing-library/react-native";

import { WelcomeScreen } from "../WelcomeScreen";

describe("WelcomeScreen", () => {
  it("shows the ISKCON Chicago spiritual welcome and auth choices", async () => {
    const { getByText, queryByText } = await render(
      <WelcomeScreen onAuthenticated={jest.fn()} />,
    );

    expect(getByText("Home of Śrī Śrī Kiśora-Kiśorī")).toBeTruthy();
    expect(
      getByText("Come as you are. Grow closer to Kṛṣṇa, together."),
    ).toBeTruthy();
    expect(
      getByText(
        "A loving community connected through seva, sādhana, and kīrtana.",
      ),
    ).toBeTruthy();
    expect(getByText("Create account")).toBeTruthy();
    expect(getByText("Continue with Google")).toBeTruthy();
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
      getByPlaceholderText("you@example.com"),
      "devotee@example.com",
    );
    await fireEvent.changeText(
      getByPlaceholderText("At least 6 characters"),
      "haribol",
    );
    await fireEvent.press(getByRole("button", { name: "Sign in" }));

    expect(onAuthenticated).toHaveBeenCalledTimes(1);
  });

  it("switches to account creation and password reset", async () => {
    const { getByRole, getByText, queryByText } = await render(
      <WelcomeScreen onAuthenticated={jest.fn()} />,
    );

    await fireEvent.press(
      getByRole("button", { name: "Show Create account" }),
    );
    expect(getByText("Join the community")).toBeTruthy();
    expect(getByText("Full name")).toBeTruthy();
    expect(getByText("Create your account with email")).toBeTruthy();
    expect(queryByText("Phone OTP")).toBeNull();

    await fireEvent.press(getByRole("button", { name: "Show Sign in" }));
    await fireEvent.press(getByRole("button", { name: "Forgot password?" }));
    expect(getByText("Reset your password")).toBeTruthy();
    expect(getByText("Send reset link")).toBeTruthy();
  });

  it("uses a phone number only for OTP sign-in", async () => {
    const { getByPlaceholderText, getByRole, getByText, queryByPlaceholderText } =
      await render(<WelcomeScreen onAuthenticated={jest.fn()} />);

    await fireEvent.press(
      getByRole("button", { name: "Use Phone OTP" }),
    );

    expect(getByPlaceholderText("(312) 555-0123")).toBeTruthy();
    expect(queryByPlaceholderText("At least 6 characters")).toBeNull();

    await fireEvent.changeText(
      getByPlaceholderText("(312) 555-0123"),
      "3125550123",
    );
    await fireEvent.press(
      getByRole("button", { name: "Send verification code" }),
    );

    expect(getByText("Verification code")).toBeTruthy();
    expect(getByPlaceholderText("6-digit code")).toBeTruthy();
  });
});
