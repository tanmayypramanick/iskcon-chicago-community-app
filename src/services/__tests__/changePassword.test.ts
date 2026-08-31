/// <reference types="jest" />

import { getSupabaseClient } from "../../lib/supabase";
import { changePassword, getAuthAccount } from "../auth";

jest.mock("expo-auth-session", () => ({
  makeRedirectUri: ({ path }: { path: string }) => `iskconchicago://${path}`,
}));

jest.mock("expo-auth-session/build/QueryParams", () => ({
  getQueryParams: jest.fn(),
}));

jest.mock("expo-web-browser", () => ({
  maybeCompleteAuthSession: jest.fn(),
  openAuthSessionAsync: jest.fn(),
}));

jest.mock("../../lib/supabase", () => ({
  getSupabaseClient: jest.fn(),
  getSupabaseConfiguration: jest.fn(),
}));

const mockGetSupabaseClient = jest.mocked(getSupabaseClient);

const getUser = jest.fn();
const signInWithPassword = jest.fn();
const updateUser = jest.fn();

const emailUser = {
  id: "devotee-1",
  email: "devotee@example.com",
  app_metadata: { provider: "email", providers: ["email"] },
  identities: [{ provider: "email" }],
};

describe("changing a password without leaving the app", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockGetSupabaseClient.mockReturnValue({
      auth: { getUser, signInWithPassword, updateUser },
    } as never);
    getUser.mockResolvedValue({ data: { user: emailUser }, error: null });
    signInWithPassword.mockResolvedValue({
      data: { session: { user: { id: "devotee-1" } } },
      error: null,
    });
    updateUser.mockResolvedValue({ data: { user: emailUser }, error: null });
  });

  it("re-authenticates against the session's own email, not one that was typed", async () => {
    const result = await changePassword({
      currentPassword: "oldpass1",
      newPassword: "newpass1",
    });

    expect(signInWithPassword).toHaveBeenCalledWith({
      email: "devotee@example.com",
      password: "oldpass1",
    });
    expect(updateUser).toHaveBeenCalledWith({ password: "newpass1" });
    expect(result).toEqual({ ok: true });
  });

  it("never reaches updateUser when the current password is refused", async () => {
    signInWithPassword.mockResolvedValue({
      data: { session: null, user: null },
      error: {
        code: "invalid_credentials",
        message: "Invalid login credentials",
      },
    });

    const result = await changePassword({
      currentPassword: "wrong",
      newPassword: "newpass1",
    });

    expect(result).toEqual({ ok: false, reason: "wrongCurrentPassword" });
    expect(updateUser).not.toHaveBeenCalled();
  });

  // The dangerous shape: no error, but nothing that proves anything either.
  it("never reaches updateUser when re-authentication returns no session", async () => {
    signInWithPassword.mockResolvedValue({
      data: { session: null },
      error: null,
    });

    const result = await changePassword({
      currentPassword: "wrong",
      newPassword: "newpass1",
    });

    expect(result).toEqual({ ok: false, reason: "wrongCurrentPassword" });
    expect(updateUser).not.toHaveBeenCalled();
  });

  it("never reaches updateUser when the re-authentication is for another account", async () => {
    signInWithPassword.mockResolvedValue({
      data: { session: { user: { id: "somebody-else" } } },
      error: null,
    });

    const result = await changePassword({
      currentPassword: "another devotee's password",
      newPassword: "newpass1",
    });

    expect(result).toEqual({ ok: false, reason: "wrongCurrentPassword" });
    expect(updateUser).not.toHaveBeenCalled();
  });

  it("treats an unrecognised re-authentication failure as a refusal", async () => {
    signInWithPassword.mockResolvedValue({
      data: { session: null },
      error: { message: "something nobody has seen before" },
    });

    const result = await changePassword({
      currentPassword: "oldpass1",
      newPassword: "newpass1",
    });

    expect(result).toEqual({ ok: false, reason: "wrongCurrentPassword" });
    expect(updateUser).not.toHaveBeenCalled();
  });

  it("keeps a dropped connection apart from a wrong password", async () => {
    signInWithPassword.mockResolvedValue({
      data: { session: null },
      error: { message: "Network request failed" },
    });

    const result = await changePassword({
      currentPassword: "oldpass1",
      newPassword: "newpass1",
    });

    expect(result).toEqual({ ok: false, reason: "network" });
    expect(updateUser).not.toHaveBeenCalled();
  });

  it("refuses a Google-only account before asking for a password it does not have", async () => {
    getUser.mockResolvedValue({
      data: {
        user: {
          id: "devotee-2",
          email: "devotee@gmail.com",
          app_metadata: { provider: "google", providers: ["google"] },
          identities: [{ provider: "google" }],
        },
      },
      error: null,
    });

    const result = await changePassword({
      currentPassword: "anything",
      newPassword: "newpass1",
    });

    expect(result).toEqual({ ok: false, reason: "noPasswordIdentity" });
    expect(signInWithPassword).not.toHaveBeenCalled();
    expect(updateUser).not.toHaveBeenCalled();
  });

  it("names why the update itself was refused", async () => {
    updateUser.mockResolvedValue({
      data: { user: null },
      error: {
        code: "same_password",
        message: "New password should be different from the old password.",
      },
    });

    await expect(
      changePassword({ currentPassword: "oldpass1", newPassword: "oldpass1" }),
    ).resolves.toEqual({ ok: false, reason: "sameAsCurrent" });

    updateUser.mockResolvedValue({
      data: { user: null },
      error: { code: "weak_password", message: "Password is too weak" },
    });

    await expect(
      changePassword({ currentPassword: "oldpass1", newPassword: "password" }),
    ).resolves.toEqual({ ok: false, reason: "weakPassword" });
  });

  it("reports a lapsed session rather than attempting anything", async () => {
    getUser.mockResolvedValue({
      data: { user: null },
      error: { message: "Auth session missing!" },
    });

    const result = await changePassword({
      currentPassword: "oldpass1",
      newPassword: "newpass1",
    });

    expect(result).toEqual({ ok: false, reason: "sessionExpired" });
    expect(signInWithPassword).not.toHaveBeenCalled();
  });
});

describe("reading how an account signs in", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockGetSupabaseClient.mockReturnValue({
      auth: { getUser, signInWithPassword, updateUser },
    } as never);
  });

  it("finds the password identity from the identities list", async () => {
    getUser.mockResolvedValue({ data: { user: emailUser }, error: null });

    await expect(getAuthAccount()).resolves.toEqual({
      email: "devotee@example.com",
      providers: ["email"],
      hasPassword: true,
    });
  });

  it("falls back to app_metadata when identities are absent", async () => {
    getUser.mockResolvedValue({
      data: {
        user: {
          id: "devotee-2",
          email: "devotee@gmail.com",
          app_metadata: { provider: "google", providers: ["google"] },
        },
      },
      error: null,
    });

    await expect(getAuthAccount()).resolves.toEqual({
      email: "devotee@gmail.com",
      providers: ["google"],
      hasPassword: false,
    });
  });

  it("counts an account linked to both as having a password", async () => {
    getUser.mockResolvedValue({
      data: {
        user: {
          id: "devotee-3",
          email: "devotee@gmail.com",
          app_metadata: { provider: "google", providers: ["google", "email"] },
          identities: [{ provider: "google" }, { provider: "email" }],
        },
      },
      error: null,
    });

    const account = await getAuthAccount();
    expect(account.hasPassword).toBe(true);
    expect(account.providers).toEqual(["google", "email"]);
  });
});
