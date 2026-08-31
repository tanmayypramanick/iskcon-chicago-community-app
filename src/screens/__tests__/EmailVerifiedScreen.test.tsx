/// <reference types="jest" />

import { fireEvent, render, waitFor } from "@testing-library/react-native";
import { AccessibilityInfo } from "react-native";

import {
  EmailVerifiedModal,
  EmailVerifiedScreen,
} from "../EmailVerifiedScreen";

describe("the verified confirmation", () => {
  beforeEach(() => jest.restoreAllMocks());

  it("tells a devotee arriving from their inbox that it worked", async () => {
    const onContinue = jest.fn();
    const screen = await render(
      <EmailVerifiedScreen onContinue={onContinue} />,
    );

    expect(
      screen.getByRole("header", { name: "Your email is verified" }),
    ).toBeTruthy();
    expect(screen.getByText("Hare Kṛṣṇa")).toBeTruthy();
    expect(screen.getByText("Your servant, ISKCON Chicago")).toBeTruthy();

    await fireEvent.press(
      screen.getByRole("button", { name: "Enter the temple app" }),
    );
    expect(onContinue).toHaveBeenCalledTimes(1);
  });

  it("is spoken, not only drawn", async () => {
    const announce = jest
      .spyOn(AccessibilityInfo, "announceForAccessibility")
      .mockImplementation(() => undefined);

    await render(<EmailVerifiedScreen onContinue={jest.fn()} />);

    await waitFor(() =>
      expect(announce).toHaveBeenCalledWith(expect.stringMatching(/verified/i)),
    );
  });

  it("does not take the app away from someone already signed in", async () => {
    const onDismiss = jest.fn();
    const screen = await render(
      <EmailVerifiedModal visible onDismiss={onDismiss} />,
    );

    expect(
      screen.getByRole("header", { name: "Your email is verified" }),
    ).toBeTruthy();
    expect(screen.getByText(/carry on exactly where you were/i)).toBeTruthy();

    await fireEvent.press(screen.getByRole("button", { name: "Continue" }));
    expect(onDismiss).toHaveBeenCalledTimes(1);
  });

  it("shows nothing at all until a link has actually been consumed", async () => {
    const screen = await render(
      <EmailVerifiedModal visible={false} onDismiss={jest.fn()} />,
    );

    expect(screen.queryByText("Your email is verified")).toBeNull();
  });
});
