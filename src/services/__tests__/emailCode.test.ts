/// <reference types="jest" />

import { getSupabaseClient } from "../../lib/supabase";
import { EMAIL_CODE_TTL_MS, verifyEmailCode } from "../auth";

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

/**
 * The one string GoTrue answers with whether the code was mistyped, already
 * spent, or hours old. Every distinction the app draws has to be drawn without
 * its help, which is why this is written out here rather than paraphrased.
 */
const AMBIGUOUS_REFUSAL = {
  code: "otp_expired",
  message: "Token has expired or is invalid",
  status: 403,
};

const SESSION = { user: { id: "devotee-1" } };

describe("verifying a code from an auth email", () => {
  const verifyOtp = jest.fn();

  beforeEach(() => {
    jest.clearAllMocks();
    mockGetSupabaseClient.mockReturnValue({ auth: { verifyOtp } } as never);
    verifyOtp.mockResolvedValue({ data: { session: SESSION }, error: null });
  });

  it("spends a recovery code on the recovery OTP and returns the session", async () => {
    const result = await verifyEmailCode({
      email: " Devotee@Example.com ",
      code: "123456",
      purpose: "recovery",
      requestedAt: Date.now(),
    });

    expect(verifyOtp).toHaveBeenCalledWith({
      email: "Devotee@Example.com",
      token: "123456",
      type: "recovery",
    });
    expect(result).toEqual({ ok: true, session: SESSION });
  });

  it("checks a signup code against the signup OTP, not the recovery one", async () => {
    await verifyEmailCode({
      email: "devotee@example.com",
      code: "123456",
      purpose: "signup",
    });

    expect(verifyOtp).toHaveBeenCalledWith(
      expect.objectContaining({ type: "signup" }),
    );
  });

  it("forgives a code copied with spaces around it", async () => {
    await verifyEmailCode({
      email: "devotee@example.com",
      code: " 123 456 ",
      purpose: "recovery",
    });

    expect(verifyOtp).toHaveBeenCalledWith(
      expect.objectContaining({ token: "123456" }),
    );
  });

  it("never sends a half-typed code or a missing address", async () => {
    await expect(
      verifyEmailCode({
        email: "devotee@example.com",
        code: "1234",
        purpose: "recovery",
      }),
    ).resolves.toEqual({ ok: false, reason: "malformed" });

    await expect(
      verifyEmailCode({ email: "  ", code: "123456", purpose: "recovery" }),
    ).resolves.toEqual({ ok: false, reason: "noAddress" });

    expect(verifyOtp).not.toHaveBeenCalled();
  });

  describe("telling the three refusals apart", () => {
    it("calls a code past its hour expired, without spending an attempt", async () => {
      const result = await verifyEmailCode({
        email: "devotee@example.com",
        code: "123456",
        purpose: "recovery",
        requestedAt: Date.now() - EMAIL_CODE_TTL_MS - 1000,
      });

      expect(result).toEqual({ ok: false, reason: "expiredCode" });
      // The server would have answered "expired or invalid", and the devotee
      // would have been told to check their typing.
      expect(verifyOtp).not.toHaveBeenCalled();
    });

    it("calls a refusal inside the hour a wrong code, not an expired one", async () => {
      verifyOtp.mockResolvedValue({ data: {}, error: AMBIGUOUS_REFUSAL });

      const result = await verifyEmailCode({
        email: "devotee@example.com",
        code: "123456",
        purpose: "recovery",
        requestedAt: Date.now() - 60_000,
      });

      expect(result).toEqual({ ok: false, reason: "wrongCode" });
    });

    it("owns the ambiguity when it does not know when the email was sent", async () => {
      verifyOtp.mockResolvedValue({ data: {}, error: AMBIGUOUS_REFUSAL });

      const result = await verifyEmailCode({
        email: "devotee@example.com",
        code: "123456",
        purpose: "recovery",
      });

      expect(result).toEqual({ ok: false, reason: "codeNotAccepted" });
    });

    it("reads a rate limit as its own thing, not as a wrong code", async () => {
      verifyOtp.mockResolvedValue({
        data: {},
        error: {
          code: "over_request_rate_limit",
          message: "Request rate limit reached",
          status: 429,
        },
      });

      const result = await verifyEmailCode({
        email: "devotee@example.com",
        code: "123456",
        purpose: "recovery",
        requestedAt: Date.now(),
      });

      expect(result).toEqual({ ok: false, reason: "tooManyAttempts" });
    });
  });

  it("blames the connection rather than the code when the phone never got there", async () => {
    verifyOtp.mockRejectedValue(new TypeError("Network request failed"));

    const result = await verifyEmailCode({
      email: "devotee@example.com",
      code: "123456",
      purpose: "recovery",
      requestedAt: Date.now(),
    });

    expect(result).toEqual({ ok: false, reason: "network" });
  });

  it("refuses an accepted code that produced no session", async () => {
    // A recovery with no session cannot set a password, so treating this as a
    // success would drop the devotee somewhere that could not work.
    verifyOtp.mockResolvedValue({ data: { session: null }, error: null });

    const result = await verifyEmailCode({
      email: "devotee@example.com",
      code: "123456",
      purpose: "recovery",
    });

    expect(result).toEqual({ ok: false, reason: "noSession" });
  });
});
