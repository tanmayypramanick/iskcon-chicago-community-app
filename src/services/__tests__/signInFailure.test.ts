/// <reference types="jest" />

jest.mock("expo-auth-session", () => ({
  makeRedirectUri: ({ path }: { path: string }) => `iskconchicago://${path}`,
}));

// A real parser rather than jest.fn(): getAuthLinkKind reads `type` out of
// this, so a mock returning undefined would test nothing about the link.
jest.mock("expo-auth-session/build/QueryParams", () => ({
  getQueryParams: (url: string) => {
    const query = url.split(/[#?]/).slice(1).join("&");
    const params: Record<string, string> = {};
    for (const pair of query.split("&")) {
      if (!pair) continue;
      const [key, value = ""] = pair.split("=");
      params[decodeURIComponent(key)] = decodeURIComponent(value);
    }
    return { params, errorCode: params.error_code ?? null };
  },
}));

jest.mock("expo-web-browser", () => ({
  maybeCompleteAuthSession: jest.fn(),
  openAuthSessionAsync: jest.fn(),
}));

jest.mock("../../lib/supabase", () => ({
  getSupabaseClient: jest.fn(),
  getSupabaseConfiguration: jest.fn(),
}));

import { describeSignInFailure, getAuthLinkKind } from "../auth";

/**
 * The sign-in form was the last screen still rendering error.message straight
 * from GoTrue. These are the actual strings it returns, so the test is that a
 * devotee never sees one of them.
 */
const gotrueStrings = [
  "Invalid login credentials",
  "Email not confirmed",
  "User already registered",
  "For security purposes, you can only request this after 21 seconds",
  "Email rate limit exceeded",
  "over_request_rate_limit",
  "Password should be at least 6 characters",
  "Network request failed",
];

describe("describeSignInFailure", () => {
  it("never hands back the developer string it was given", () => {
    for (const raw of gotrueStrings) {
      const shown = describeSignInFailure(new Error(raw));
      expect(shown).not.toContain(raw);
      // Nor any of the tell-tale fragments, in any casing.
      expect(shown.toLowerCase()).not.toContain("invalid login credentials");
      expect(shown.toLowerCase()).not.toContain("rate limit");
      expect(shown.toLowerCase()).not.toContain("_");
    }
  });

  it("says something a devotee can act on for a wrong password", () => {
    const shown = describeSignInFailure(new Error("Invalid login credentials"));
    expect(shown).toContain("do not match");
    expect(shown).toContain("Forgot password");
  });

  it("distinguishes an unconfirmed address from a wrong password", () => {
    expect(describeSignInFailure(new Error("Email not confirmed"))).toContain(
      "not been confirmed",
    );
  });

  it("names the connection when the server could not be reached", () => {
    expect(describeSignInFailure(new Error("Network request failed"))).toContain(
      "Check your connection",
    );
  });

  it("falls back to something safe for anything unrecognised", () => {
    for (const odd of [null, undefined, 42, {}, new Error(""), ""]) {
      const shown = describeSignInFailure(odd);
      expect(shown.length).toBeGreaterThan(0);
      expect(shown).toBe("Something went wrong. Please try again.");
    }
  });

  it("does not leak an unexpected server string verbatim", () => {
    const leaky = "PGRST301: JWSError JWSInvalidSignature";
    expect(describeSignInFailure(new Error(leaky))).not.toContain("PGRST");
  });
});

/**
 * The expired-reset case, which is the one a devotee actually hits.
 *
 * Supabase drops `type` from the redirect when a link has expired or been
 * spent, so the kind has to come from the path or the screen withholds the
 * six-digit fallback at the exact moment it is needed.
 */
describe("getAuthLinkKind on a link that carries no type", () => {
  it("still recognises an expired recovery link by its path", () => {
    const expired =
      "iskconchicago://auth/recover#error=access_denied" +
      "&error_code=otp_expired" +
      "&error_description=Email+link+is+invalid+or+has+expired";
    expect(getAuthLinkKind(expired)).toBe("recovery");
  });

  it("still reads an explicit type when there is one", () => {
    expect(getAuthLinkKind("iskconchicago://auth/recover#type=recovery")).toBe(
      "recovery",
    );
    expect(
      getAuthLinkKind("iskconchicago://auth/callback#type=signup"),
    ).toBe("signup");
  });

  it("leaves auth/callback unknown, because that path proves nothing", () => {
    // signup, magic link, email change and Google sign-in all land here, so
    // guessing would check a good code as the wrong type.
    expect(getAuthLinkKind("iskconchicago://auth/callback#error=x")).toBe(
      "unknown",
    );
  });
});
