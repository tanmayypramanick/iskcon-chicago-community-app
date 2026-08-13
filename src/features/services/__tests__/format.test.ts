/// <reference types="jest" />

import {
  dateToKey,
  errorMessage,
  formatDuration,
  formatServiceTime,
  hasServiceStarted,
  serviceDateTimeValue,
  storedSuggestionDuration,
  timeToDatabaseValue,
} from "../format";

describe("service formatting", () => {
  it("formats 30-minute service durations clearly", () => {
    expect(formatDuration(30)).toBe("30 min");
    expect(formatDuration(60)).toBe("1 hr");
    expect(formatDuration(90)).toBe("1 hr 30 min");
  });

  it("converts native date and time values for Supabase", () => {
    const value = new Date(2026, 7, 6, 17, 30);

    expect(dateToKey(value)).toBe("2026-08-06");
    expect(timeToDatabaseValue(value)).toBe("17:30:00");
    expect(serviceDateTimeValue("2026-08-06", "17:30:00")).toBe(
      "2026-08-06T17:30:00",
    );
  });

  it("presents database times in a human-readable form", () => {
    expect(formatServiceTime("17:30:00")).toMatch(/5:30\sPM/i);
  });
});

/**
 * Whether a seva has begun decides whether anyone is offered a way to complete
 * it, so it is answered on the temple's clock and never the device's — a phone
 * in Mumbai must reach the same verdict as one in the temple car park.
 */
describe("whether a seva has started", () => {
  const morning = { date: "2026-08-12", start_time: "11:00:00" };

  it("is false a minute before, true a minute after", () => {
    // August, so Chicago is on CDT (UTC-5): 11:00 local is 16:00Z.
    expect(hasServiceStarted(morning, new Date("2026-08-12T15:59:00Z"))).toBe(
      false,
    );
    expect(hasServiceStarted(morning, new Date("2026-08-12T16:01:00Z"))).toBe(
      true,
    );
  });

  it("counts the start instant itself as started", () => {
    expect(hasServiceStarted(morning, new Date("2026-08-12T16:00:00Z"))).toBe(
      true,
    );
  });

  it("reads a winter seva on CST rather than a fixed offset", () => {
    // January is CST (UTC-6), so the same wall clock is an hour later in UTC.
    const winter = { date: "2026-01-14", start_time: "11:00:00" };

    expect(hasServiceStarted(winter, new Date("2026-01-14T16:30:00Z"))).toBe(
      false,
    );
    expect(hasServiceStarted(winter, new Date("2026-01-14T17:30:00Z"))).toBe(
      true,
    );
  });
});

/**
 * The temple keeps seva in half hours. `propose_service_offer_alternative`
 * rounds every suggestion onto that grid, so anything the screen sends has to
 * be rounded the same way before it is shown — a devotee who offered 45 minutes
 * was being committed to an hour with nothing on screen saying so.
 */
describe("the length a suggested time is actually stored as", () => {
  it("rounds up onto the half hour", () => {
    expect(storedSuggestionDuration(45)).toBe(60);
    expect(storedSuggestionDuration(31)).toBe(60);
    expect(storedSuggestionDuration(100)).toBe(120);
  });

  it("leaves a length already on the half hour exactly where it is", () => {
    expect(storedSuggestionDuration(30)).toBe(30);
    expect(storedSuggestionDuration(60)).toBe(60);
    expect(storedSuggestionDuration(720)).toBe(720);
  });

  it("never stores less than the half hour the RPC floors at", () => {
    expect(storedSuggestionDuration(15)).toBe(30);
    expect(storedSuggestionDuration(1)).toBe(30);
    expect(storedSuggestionDuration(0)).toBe(30);
  });
});

describe("errorMessage", () => {
  it("reads the message from a Supabase PostgrestError, which is not an Error", () => {
    // supabase-js returns a plain object. An `instanceof Error` guard silently
    // swallowed every server message, which hid a real missing-function error.
    const postgrestError = {
      code: "PGRST202",
      message: "Could not find the function public.request_seva_verification",
      details: null,
      hint: null,
    };
    expect(errorMessage(postgrestError, "fallback")).toBe(
      "Could not find the function public.request_seva_verification",
    );
  });

  it("handles real Errors, strings, empty values and unknown shapes", () => {
    expect(errorMessage(new Error("boom"), "fallback")).toBe("boom");
    expect(errorMessage("plain text", "fallback")).toBe("plain text");
    expect(errorMessage(null, "fallback")).toBeNull();
    expect(errorMessage(undefined, "fallback")).toBeNull();
    expect(errorMessage({ code: "X" }, "fallback")).toBe("fallback");
    expect(errorMessage({ details: "only details" }, "fallback")).toBe(
      "only details",
    );
  });
});
