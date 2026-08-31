/// <reference types="jest" />

import * as QueryParams from "expo-auth-session/build/QueryParams";

import { getSupabaseClient } from "../../lib/supabase";
import {
  AUTH_CALLBACK_URI,
  AUTH_RECOVERY_URI,
  createSessionFromAuthUrl,
  getAuthEmailRedirectUri,
  getCurrentAuthEmail,
  requestPasswordReset,
  signUpWithEmail,
} from "../auth";

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
const mockGetQueryParams = jest.mocked(QueryParams.getQueryParams);

describe("authentication email flows", () => {
  const signUp = jest.fn();
  const resetPasswordForEmail = jest.fn();
  const setSession = jest.fn();
  const getUser = jest.fn();

  beforeEach(() => {
    jest.clearAllMocks();
    // The page the emails point at is on GitHub Pages, not on the Supabase
    // project, so the project URL no longer has anything to do with it. Set
    // anyway, so the assertions below fail loudly if it ever creeps back in.
    process.env.EXPO_PUBLIC_SUPABASE_URL = "https://project.supabase.co";
    mockGetSupabaseClient.mockReturnValue({
      auth: { signUp, resetPasswordForEmail, setSession, getUser },
    } as never);
    signUp.mockResolvedValue({ data: { session: null }, error: null });
    resetPasswordForEmail.mockResolvedValue({ error: null });
    setSession.mockResolvedValue({
      data: { session: { user: {} } },
      error: null,
    });
    getUser.mockResolvedValue({
      data: { user: { email: "devotee@example.com" } },
      error: null,
    });
  });

  it("returns signup verification to the web page, not the app's scheme", async () => {
    await signUpWithEmail({
      name: "  Gauranga Sharma  ",
      email: "  devotee@example.com  ",
      password: "haribol8",
    });

    // The deep link still exists — the web page hands off to it — but it is no
    // longer what the email points at, because Gmail's embedded browser will
    // not open a custom scheme.
    expect(AUTH_CALLBACK_URI).toBe("iskconchicago://auth/callback");
    expect(signUp).toHaveBeenCalledWith({
      email: "devotee@example.com",
      password: "haribol8",
      options: {
        emailRedirectTo: "https://tanmayypramanick.github.io/iskcon-chicago-community-app/",
        data: { full_name: "Gauranga Sharma" },
      },
    });
  });

  it("returns password recovery to the web page, not the app's scheme", async () => {
    await requestPasswordReset("  devotee@example.com  ");

    expect(AUTH_RECOVERY_URI).toBe("iskconchicago://auth/recover");
    expect(resetPasswordForEmail).toHaveBeenCalledWith("devotee@example.com", {
      redirectTo: "https://tanmayypramanick.github.io/iskcon-chicago-community-app/",
    });
  });

  it("sends the same page whether or not a project URL is configured", async () => {
    // The page is hosted on GitHub Pages and is the same for every environment,
    // so a checkout without .env.local still sends a link that opens. It used to
    // be built from the project URL, back when it was a Supabase edge function.
    delete process.env.EXPO_PUBLIC_SUPABASE_URL;
    expect(getAuthEmailRedirectUri()).toBe(
      "https://tanmayypramanick.github.io/iskcon-chicago-community-app/",
    );
  });

  it("creates a session from an email callback", async () => {
    mockGetQueryParams.mockReturnValue({
      params: { access_token: "access", refresh_token: "refresh" },
      errorCode: null,
    } as never);

    await expect(
      createSessionFromAuthUrl("iskconchicago://auth/callback#tokens"),
    ).resolves.toEqual({ user: {} });
    expect(setSession).toHaveBeenCalledWith({
      access_token: "access",
      refresh_token: "refresh",
    });
  });

  it("reads the signed-in email without accepting user input", async () => {
    await expect(getCurrentAuthEmail()).resolves.toBe("devotee@example.com");
  });
});
