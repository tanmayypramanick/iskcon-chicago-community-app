import { validateSevaEntryWindow } from "../sevaEntry";

describe("seva entry windows", () => {
  const now = new Date("2026-08-26T18:00:00.000Z");

  it("accepts seva beginning now or in the future for Find a way to help", () => {
    expect(
      validateSevaEntryWindow(
        "plan",
        new Date("2026-08-26T18:00:00.000Z"),
        new Date("2026-08-26T19:00:00.000Z"),
        now,
      ),
    ).toBeNull();
    expect(
      validateSevaEntryWindow(
        "plan",
        new Date("2026-08-27T18:00:00.000Z"),
        new Date("2026-08-27T19:00:00.000Z"),
        now,
      ),
    ).toBeNull();
  });

  it("directs finished seva to Log your seva", () => {
    expect(
      validateSevaEntryWindow(
        "plan",
        new Date("2026-08-26T16:00:00.000Z"),
        new Date("2026-08-26T17:00:00.000Z"),
        now,
      ),
    ).toBe("That seva has already finished. Use Log your seva instead.");
  });

  it("accepts only already-completed seva in the log flow", () => {
    expect(
      validateSevaEntryWindow(
        "completed",
        new Date("2026-08-26T16:00:00.000Z"),
        new Date("2026-08-26T17:00:00.000Z"),
        now,
      ),
    ).toBeNull();
    expect(
      validateSevaEntryWindow(
        "completed",
        new Date("2026-08-26T18:00:00.000Z"),
        new Date("2026-08-26T19:00:00.000Z"),
        now,
      ),
    ).toBe("Completed seva must end before the current time.");
  });

  it("rejects implausible durations and logs older than the dashboard window", () => {
    expect(
      validateSevaEntryWindow(
        "completed",
        new Date("2026-08-25T00:00:00.000Z"),
        new Date("2026-08-25T13:00:01.000Z"),
        now,
      ),
    ).toBe("Choose an end time within 12 hours of the start.");
    expect(
      validateSevaEntryWindow(
        "completed",
        new Date("2026-02-20T16:00:00.000Z"),
        new Date("2026-02-20T17:00:00.000Z"),
        now,
      ),
    ).toBe("Completed seva can be logged for up to 180 days.");
  });
});
