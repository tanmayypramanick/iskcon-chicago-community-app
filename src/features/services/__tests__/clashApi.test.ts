/// <reference types="jest" />

import { getSupabaseClient } from "../../../lib/supabase";
import { fetchClosedUnservedSeva, fetchSevaClashes } from "../api";

jest.mock("../../../lib/supabase", () => ({
  getSupabaseClient: jest.fn(),
}));

const mockGetSupabaseClient = jest.mocked(getSupabaseClient);

describe("asking the server about a clash", () => {
  const rpc = jest.fn().mockResolvedValue({ data: [], error: null });

  beforeEach(() => {
    jest.clearAllMocks();
    rpc.mockResolvedValue({ data: [], error: null });
    mockGetSupabaseClient.mockReturnValue({ rpc } as never);
  });

  it("asks list_seva_clashes about one devotee and one window", async () => {
    await fetchSevaClashes({
      devoteeId: "ravi",
      date: "2026-08-20",
      startTime: "13:15:00",
      durationMinutes: 75,
      excludeInstanceId: "this-seva",
    });

    expect(rpc).toHaveBeenCalledWith("list_seva_clashes", {
      p_devotee_id: "ravi",
      p_date: "2026-08-20",
      p_start_time: "13:15:00",
      p_duration_minutes: 75,
      p_exclude_instance_id: "this-seva",
    });
  });

  it("passes no exclusion when there is no seva to exclude", async () => {
    await fetchSevaClashes({
      devoteeId: "ravi",
      date: "2026-08-20",
      startTime: "13:15:00",
      durationMinutes: 75,
    });

    expect(rpc).toHaveBeenCalledWith(
      "list_seva_clashes",
      expect.objectContaining({ p_exclude_instance_id: null }),
    );
  });

  it("reads back-to-back seva as no clash at all", async () => {
    // 12:00–13:30 then 13:30–14:30: the ranges are half-open, so the server
    // answers nothing and the app has nothing to warn about.
    rpc.mockResolvedValue({ data: [], error: null });

    await expect(
      fetchSevaClashes({
        devoteeId: "ravi",
        date: "2026-08-20",
        startTime: "13:30:00",
        durationMinutes: 60,
      }),
    ).resolves.toEqual([]);
  });

  it("answers nothing known against a database without 0069 yet", async () => {
    rpc.mockResolvedValue({ data: null, error: { code: "PGRST202" } });

    await expect(
      fetchSevaClashes({
        devoteeId: "ravi",
        date: "2026-08-20",
        startTime: "13:15:00",
        durationMinutes: 75,
      }),
    ).resolves.toEqual([]);
  });

  it("lets a real failure through rather than pretending nobody is busy", async () => {
    rpc.mockResolvedValue({ data: null, error: { code: "42501", message: "no" } });

    await expect(
      fetchSevaClashes({
        devoteeId: "ravi",
        date: "2026-08-20",
        startTime: "13:15:00",
        durationMinutes: 75,
      }),
    ).rejects.toEqual({ code: "42501", message: "no" });
  });
});

describe("asking the server what closed unserved", () => {
  const rpc = jest.fn().mockResolvedValue({ data: [], error: null });

  beforeEach(() => {
    jest.clearAllMocks();
    rpc.mockResolvedValue({ data: [], error: null });
    mockGetSupabaseClient.mockReturnValue({ rpc } as never);
  });

  it("goes through the RPC and never near service_instances_unserved", async () => {
    await fetchClosedUnservedSeva();

    expect(rpc).toHaveBeenCalledTimes(1);
    const [name, params] = rpc.mock.calls[0];
    expect(name).toBe("list_seva_closed_unserved");
    expect(params).toEqual({ p_from: expect.any(String), p_to: null });
  });

  it("stays quiet on a database without 0068 yet", async () => {
    rpc.mockResolvedValue({ data: null, error: { code: "PGRST202" } });

    await expect(fetchClosedUnservedSeva()).resolves.toEqual([]);
  });
});
