/// <reference types="jest" />

import { fireEvent, render, waitFor } from "@testing-library/react-native";
import type { ComponentProps } from "react";

import { changePassword, getAuthAccount } from "../../services/auth";
import { ChangePasswordScreen } from "../ChangePasswordScreen";

jest.mock("../../services/auth", () => ({
  // Mirrors the server's password_min_length; the screen must state this
  // number rather than one of its own.
  PASSWORD_MIN_LENGTH: 6,
  changePassword: jest.fn(),
  getAuthAccount: jest.fn(),
}));

const mockGetAuthAccount = jest.mocked(getAuthAccount);
const mockChangePassword = jest.mocked(changePassword);
const screenProps = {} as ComponentProps<typeof ChangePasswordScreen>;

type Rendered = Awaited<ReturnType<typeof render>>;

const show = () => render(<ChangePasswordScreen {...screenProps} />);

const fill = async (
  screen: Rendered,
  current: string,
  next: string,
  confirmation = next,
) => {
  await fireEvent.changeText(
    screen.getByLabelText("Current password"),
    current,
  );
  await fireEvent.changeText(screen.getByLabelText("New password"), next);
  await fireEvent.changeText(
    screen.getByLabelText("Confirm new password"),
    confirmation,
  );
  await fireEvent.press(
    screen.getByRole("button", { name: "Change my password" }),
  );
};

describe("changing a password from inside the app", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockGetAuthAccount.mockResolvedValue({
      email: "devotee@example.com",
      providers: ["email"],
      hasPassword: true,
    });
    mockChangePassword.mockResolvedValue({ ok: true });
  });

  const waitForForm = async (screen: Rendered) =>
    waitFor(() =>
      expect(screen.getByLabelText("Current password")).toBeTruthy(),
    );

  it("changes the password in place, with no email involved", async () => {
    const screen = await show();
    await waitForForm(screen);

    await fill(screen, "oldpass1", "newpass1");

    await waitFor(() => {
      expect(mockChangePassword).toHaveBeenCalledWith({
        currentPassword: "oldpass1",
        newPassword: "newpass1",
      });
      expect(screen.getByText(/Your password is changed/)).toBeTruthy();
    });
    expect(screen.queryByText(/link/i)).toBeNull();
  });

  it("never reaches the update when the current password is wrong", async () => {
    mockChangePassword.mockResolvedValue({
      ok: false,
      reason: "wrongCurrentPassword",
    });
    const screen = await show();
    await waitForForm(screen);

    await fill(screen, "guessing", "newpass1");

    await waitFor(() =>
      expect(
        screen.getByText(/That is not your current password/),
      ).toBeTruthy(),
    );
    expect(screen.queryByText(/Your password is changed/)).toBeNull();
  });

  it("tells a wrong current password apart from a dropped connection", async () => {
    mockChangePassword.mockResolvedValue({ ok: false, reason: "network" });
    const screen = await show();
    await waitForForm(screen);

    await fill(screen, "oldpass1", "newpass1");

    await waitFor(() =>
      expect(screen.getByText(/The temple could not be reached/)).toBeTruthy(),
    );
    expect(screen.queryByText(/not your current password/)).toBeNull();
  });

  it("explains a rejected new password in its own terms", async () => {
    mockChangePassword.mockResolvedValue({ ok: false, reason: "weakPassword" });
    const screen = await show();
    await waitForForm(screen);

    await fill(screen, "oldpass1", "password");

    await waitFor(() =>
      expect(screen.getByText(/too easy to guess/)).toBeTruthy(),
    );
  });

  it("states the minimum length the shared constant carries", async () => {
    const screen = await show();
    await waitForForm(screen);

    expect(screen.getByText(/at least 6 characters/)).toBeTruthy();

    await fill(screen, "oldpass1", "hari", "hari");

    expect(
      screen.getByText("Your new password needs at least 6 characters."),
    ).toBeTruthy();
    expect(mockChangePassword).not.toHaveBeenCalled();
  });

  it("does not submit two new passwords that differ", async () => {
    const screen = await show();
    await waitForForm(screen);

    await fill(screen, "oldpass1", "newpass1", "newpass2");

    expect(
      screen.getByText("The two new passwords do not match."),
    ).toBeTruthy();
    expect(mockChangePassword).not.toHaveBeenCalled();
  });

  it("cannot be submitted twice while the first change is in flight", async () => {
    let release: (value: { ok: true }) => void = () => undefined;
    mockChangePassword.mockReturnValue(
      new Promise((resolve) => {
        release = resolve;
      }),
    );
    const screen = await show();
    await waitForForm(screen);

    await fill(screen, "oldpass1", "newpass1");
    await waitFor(() =>
      expect(
        screen.getByLabelText("Change my password").props.accessibilityState
          .disabled,
      ).toBe(true),
    );
    await fireEvent.press(screen.getByLabelText("Change my password"));

    expect(mockChangePassword).toHaveBeenCalledTimes(1);

    release({ ok: true });
    await waitFor(() =>
      expect(screen.getByText(/Your password is changed/)).toBeTruthy(),
    );
    expect(mockChangePassword).toHaveBeenCalledTimes(1);
  });

  it("tells a Google-only devotee the truth instead of showing a dead field", async () => {
    mockGetAuthAccount.mockResolvedValue({
      email: "devotee@gmail.com",
      providers: ["google"],
      hasPassword: false,
    });
    const screen = await show();

    await waitFor(() =>
      expect(screen.getByText("You sign in with Google")).toBeTruthy(),
    );
    expect(screen.getByText(/no password of its own/)).toBeTruthy();
    expect(screen.queryByLabelText("Current password")).toBeNull();
    expect(screen.queryByLabelText("New password")).toBeNull();
    expect(
      screen.queryByRole("button", { name: "Change my password" }),
    ).toBeNull();
  });

  it("says the account could not be read rather than offering a form", async () => {
    mockGetAuthAccount.mockRejectedValueOnce(new Error("AuthApiError: 401"));
    const screen = await show();

    await waitFor(() =>
      expect(
        screen.getByText(/account details could not be loaded/),
      ).toBeTruthy(),
    );
    expect(screen.queryByLabelText("Current password")).toBeNull();
    expect(screen.queryByText(/AuthApiError/)).toBeNull();
  });
});
