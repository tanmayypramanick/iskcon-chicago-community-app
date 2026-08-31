/// <reference types="jest" />

import * as QueryParams from "expo-auth-session/build/QueryParams";

import { getSupabaseClient } from "../../lib/supabase";
import {
  consumeAuthLink,
  describeAuthLinkProblem,
  getAuthLinkKind,
  requestReplacementLink,
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

/** Stands in for what Supabase puts in the fragment of a tapped email link. */
function linkParams(params: Record<string, string>) {
  mockGetQueryParams.mockReturnValue({ params, errorCode: null } as never);
}

const CALLBACK = "iskconchicago://auth/callback#fragment";
const RECOVER = "iskconchicago://auth/recover#fragment";
const TOKENS = { access_token: "access", refresh_token: "refresh" };

describe("opening an email link", () => {
  const setSession = jest.fn();
  const resetPasswordForEmail = jest.fn();
  const resend = jest.fn();

  beforeEach(() => {
    jest.clearAllMocks();
    mockGetSupabaseClient.mockReturnValue({
      auth: { setSession, resetPasswordForEmail, resend },
    } as never);
    setSession.mockResolvedValue({
      data: { session: { user: {} } },
      error: null,
    });
    resetPasswordForEmail.mockResolvedValue({ error: null });
    resend.mockResolvedValue({ error: null });
  });

  it("reads which email a link came from", () => {
    linkParams({ type: "signup" });
    expect(getAuthLinkKind(CALLBACK)).toBe("signup");
    linkParams({ type: "recovery" });
    expect(getAuthLinkKind(RECOVER)).toBe("recovery");
    linkParams({ type: "email_change" });
    expect(getAuthLinkKind(CALLBACK)).toBe("emailChange");
    linkParams({});
    expect(getAuthLinkKind(CALLBACK)).toBe("unknown");
  });

  it("confirms a consumed verification link", async () => {
    linkParams({ ...TOKENS, type: "signup" });

    await expect(
      consumeAuthLink(CALLBACK, { hadSession: false }),
    ).resolves.toEqual({ kind: "verified", hadSession: false });
  });

  it("keeps a devotee who was already inside the app in place", async () => {
    linkParams({ ...TOKENS, type: "email_change" });

    await expect(
      consumeAuthLink(CALLBACK, { hadSession: true }),
    ).resolves.toEqual({ kind: "verified", hadSession: true });
  });

  it("does not congratulate an ordinary sign-in", async () => {
    // A magic link and a Google callback both land here with a valid session.
    // Neither proved anything about the address, so neither may claim to.
    linkParams({ ...TOKENS, type: "magiclink" });
    await expect(
      consumeAuthLink(CALLBACK, { hadSession: false }),
    ).resolves.toBeNull();

    linkParams({ ...TOKENS });
    await expect(
      consumeAuthLink(CALLBACK, { hadSession: false }),
    ).resolves.toBeNull();
  });

  it("ignores deep links that are not ours", async () => {
    await expect(
      consumeAuthLink("iskconchicago://seva/123", { hadSession: false }),
    ).resolves.toBeNull();
    await expect(
      consumeAuthLink(null, { hadSession: false }),
    ).resolves.toBeNull();
    expect(setSession).not.toHaveBeenCalled();
  });

  it("sends a recovery link to the password screen", async () => {
    linkParams({ ...TOKENS, type: "recovery" });

    await expect(
      consumeAuthLink(RECOVER, { hadSession: false }),
    ).resolves.toEqual({ kind: "recovery" });
  });

  it("turns an expired link into something a devotee can act on", async () => {
    linkParams({
      type: "recovery",
      error_description: "Email+link+is+invalid+or+has+expired",
    });

    const outcome = await consumeAuthLink(RECOVER, { hadSession: false });

    expect(outcome).toMatchObject({
      kind: "problem",
      linkKind: "recovery",
      problem: { canResend: true },
    });
    if (outcome?.kind !== "problem") throw new Error("expected a problem");
    expect(outcome.problem.title).toBe("That link has expired");
    expect(outcome.problem.body).toMatch(/ask for a fresh one/i);
    // Whatever else it says, it must not hand the raw string to a devotee.
    expect(outcome.problem.body).not.toMatch(/JWT|otp_expired|invalid/i);
  });
});

describe("explaining why a link did not open", () => {
  it("does not offer a new link when the connection is the fault", () => {
    // The link in their inbox is still good; sending another would teach them
    // to distrust one that was never spent.
    const problem = describeAuthLinkProblem(
      new Error("Network request failed"),
      "signup",
    );

    expect(problem.canResend).toBe(false);
    expect(problem.body).toMatch(/still good/i);
  });

  it("explains a spent link without claiming it is tied to one device", () => {
    const problem = describeAuthLinkProblem(
      new Error("Invalid JWT structure"),
      "signup",
    );

    expect(problem.title).toBe("That link could not be opened");
    expect(problem.body).toMatch(/opens once/i);
    expect(problem.canResend).toBe(true);
  });

  it("never tells a devotee a link only works on one device", () => {
    // The app asks Supabase for implicit links, which carry the session in the
    // URL itself -- so a link opens wherever the devotee reads their mail. It
    // was PKCE that bound a link to the phone that requested it, and saying so
    // now would send somebody back to a phone they do not need.
    const claims = /another device|same (phone|device)|on the (phone|device) it was asked/i;
    for (const kind of ["signup", "recovery", "magicLink", "emailChange"] as const) {
      for (const error of [
        new Error("Invalid JWT structure"),
        new Error("Email link is invalid or has expired"),
        new Error("Network request failed"),
      ]) {
        expect(describeAuthLinkProblem(error, kind).body).not.toMatch(claims);
      }
    }
  });
});

describe("asking for a replacement link", () => {
  const resetPasswordForEmail = jest.fn();
  const resend = jest.fn();

  beforeEach(() => {
    jest.clearAllMocks();
    process.env.EXPO_PUBLIC_SUPABASE_URL = "https://project.supabase.co";
    mockGetSupabaseClient.mockReturnValue({
      auth: { resetPasswordForEmail, resend },
    } as never);
    resetPasswordForEmail.mockResolvedValue({ error: null });
    resend.mockResolvedValue({ error: null });
  });

  it("sends whichever link the devotee was trying to open", async () => {
    await requestReplacementLink("  devotee@example.com  ", "recovery");
    expect(resetPasswordForEmail).toHaveBeenCalledWith("devotee@example.com", {
      redirectTo: "https://tanmayypramanick.github.io/iskcon-chicago-community-app/",
    });

    await requestReplacementLink("devotee@example.com", "signup");
    expect(resend).toHaveBeenCalledWith({
      type: "signup",
      email: "devotee@example.com",
      options: {
        emailRedirectTo: "https://tanmayypramanick.github.io/iskcon-chicago-community-app/",
      },
    });
  });

  it("treats an already-confirmed address as nothing to report", async () => {
    // Saying "that address is already confirmed" would answer, for anyone who
    // asked, whether a given devotee has an account here.
    resend.mockResolvedValue({ error: new Error("Email already confirmed") });

    await expect(
      requestReplacementLink("devotee@example.com", "signup"),
    ).resolves.toBeUndefined();
  });
});
