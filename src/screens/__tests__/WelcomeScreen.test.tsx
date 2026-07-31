/// <reference types="jest" />

import { fireEvent, render } from "@testing-library/react-native";

import { WelcomeScreen } from "../WelcomeScreen";

describe("WelcomeScreen", () => {
  it("shows the ISKCON Chicago spiritual welcome and auth choices", async () => {
    const { getByText, queryByText } = await render(
      <WelcomeScreen onAuthenticated={jest.fn()} />,
    );

    expect(getByText("Home of Sri Sri Kisora-Kisori")).toBeTruthy();
    expect(
      getByText("One community. Many ways to serve Krishna."),
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
    const { getByRole, getByText } = await render(
      <WelcomeScreen onAuthenticated={jest.fn()} />,
    );

    await fireEvent.press(
      getByRole("button", { name: "Show Create account" }),
    );
    expect(getByText("Join the community")).toBeTruthy();
    expect(getByText("Full name")).toBeTruthy();

    await fireEvent.press(getByRole("button", { name: "Show Sign in" }));
    await fireEvent.press(getByRole("button", { name: "Forgot password?" }));
    expect(getByText("Reset your password")).toBeTruthy();
    expect(getByText("Send reset link")).toBeTruthy();
  });
});
