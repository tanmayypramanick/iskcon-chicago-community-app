/// <reference types="jest" />

import { fireEvent, render, waitFor } from "@testing-library/react-native";

import { setNewPassword } from "../../services/auth";
import { SetNewPasswordScreen } from "../SetNewPasswordScreen";

jest.mock("../../services/auth", () => ({
  // The screen states this number in its own copy, so the mock has to carry
  // the same value the server enforces.
  PASSWORD_MIN_LENGTH: 6,
  setNewPassword: jest.fn(),
}));

const mockSetNewPassword = jest.mocked(setNewPassword);

const show = (
  overrides: {
    onDone?: () => void;
    onCancel?: () => void | Promise<void>;
  } = {},
) =>
  render(
    <SetNewPasswordScreen
      onDone={overrides.onDone ?? jest.fn()}
      onCancel={overrides.onCancel ?? jest.fn()}
    />,
  );

type Rendered = Awaited<ReturnType<typeof render>>;

const fill = async (
  screen: Rendered,
  password: string,
  confirmation = password,
) => {
  await fireEvent.changeText(screen.getByLabelText("New password"), password);
  await fireEvent.changeText(
    screen.getByLabelText("Confirm new password"),
    confirmation,
  );
  await fireEvent.press(
    screen.getByRole("button", { name: "Save new password" }),
  );
};

describe("choosing a new password from a reset link", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockSetNewPassword.mockResolvedValue(undefined);
  });

  it("states the rule the server actually enforces", async () => {
    const screen = await show();

    expect(screen.getByText(/at least 6 characters/)).toBeTruthy();
    expect(screen.queryByText(/at least 8 characters/)).toBeNull();
  });

  it("accepts the shortest password the server will take", async () => {
    const screen = await show();

    await fill(screen, "haribo");

    await waitFor(() =>
      expect(mockSetNewPassword).toHaveBeenCalledWith("haribo"),
    );
  });

  it("refuses a password shorter than the server would", async () => {
    const screen = await show();

    await fill(screen, "hari");

    expect(screen.getByText("Use at least 6 characters.")).toBeTruthy();
    expect(mockSetNewPassword).not.toHaveBeenCalled();
  });

  it("says plainly that the password was saved before returning", async () => {
    const onDone = jest.fn();
    const screen = await show({ onDone });

    await fill(screen, "haribol8");

    await waitFor(() =>
      expect(
        screen.getByRole("header", { name: "Your new password is saved" }),
      ).toBeTruthy(),
    );
    // The devotee, not a timer, decides when the acknowledgement is done.
    expect(onDone).not.toHaveBeenCalled();

    await fireEvent.press(
      screen.getByRole("button", { name: "Continue to the app" }),
    );
    expect(onDone).toHaveBeenCalledTimes(1);
  });

  it("explains a lapsed recovery session instead of quoting Supabase", async () => {
    mockSetNewPassword.mockRejectedValueOnce(
      new Error("Auth session missing!"),
    );
    const screen = await show();

    await fill(screen, "haribol8");

    await waitFor(() =>
      expect(screen.getByText(/Ask for a new link/)).toBeTruthy(),
    );
    expect(screen.queryByText(/Auth session missing/)).toBeNull();
  });

  it("does not save two passwords that differ", async () => {
    const screen = await show();

    await fill(screen, "haribol8", "haribol9");

    expect(screen.getByText("Both passwords must match.")).toBeTruthy();
    expect(mockSetNewPassword).not.toHaveBeenCalled();
  });

  describe("the way out", () => {
    it("offers an exit that names what it will do", async () => {
      const screen = await show();

      expect(
        screen.getByRole("button", { name: "Cancel and sign out" }),
      ).toBeTruthy();
      expect(screen.getByText(/return to the sign-in screen/)).toBeTruthy();
    });

    it("signs out rather than saving anything when it is taken", async () => {
      const onCancel = jest.fn().mockResolvedValue(undefined);
      const onDone = jest.fn();
      const screen = await show({ onCancel, onDone });

      await fireEvent.press(
        screen.getByRole("button", { name: "Cancel and sign out" }),
      );

      await waitFor(() => expect(onCancel).toHaveBeenCalledTimes(1));
      // The label promises the password is left alone, so nothing may be sent.
      expect(mockSetNewPassword).not.toHaveBeenCalled();
      expect(onDone).not.toHaveBeenCalled();
    });

    it("says so when signing out could not be completed", async () => {
      const onCancel = jest.fn().mockRejectedValue(new Error("network down"));
      const screen = await show({ onCancel });

      await fireEvent.press(
        screen.getByRole("button", { name: "Cancel and sign out" }),
      );

      await waitFor(() =>
        expect(
          screen.getByText(/could not be signed out just now/),
        ).toBeTruthy(),
      );
      expect(screen.queryByText(/network down/)).toBeNull();
    });
  });
});
