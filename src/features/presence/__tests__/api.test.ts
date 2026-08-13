/// <reference types="jest" />

import { getSupabaseClient } from "../../../lib/supabase";
import { getChicagoDateKey } from "../../../lib/chicagoDate";
import { fetchTemplePresence, setMyTemplePresence } from "../api";

jest.mock("../../../lib/supabase", () => ({
  getSupabaseClient: jest.fn(),
}));

const mockGetSupabaseClient = jest.mocked(getSupabaseClient);

describe("temple presence API", () => {
  it("loads the current account and everyone checked in today", async () => {
    const currentBuilder = {
      select: jest.fn(),
      eq: jest.fn(),
      maybeSingle: jest.fn().mockResolvedValue({
        data: {
          user_id: "user-1",
          is_at_temple: true,
          presence_date: getChicagoDateKey(),
          source: "manual",
          checked_in_at: "2026-08-02T15:00:00.000Z",
          checked_out_at: null,
          updated_at: "2026-08-02T15:00:00.000Z",
        },
        error: null,
      }),
    };
    currentBuilder.select.mockReturnValue(currentBuilder);
    currentBuilder.eq.mockReturnValue(currentBuilder);
    const rpc = jest.fn().mockResolvedValue({
      data: [
        {
          user_id: "user-1",
          name: "Test Devotee",
          photo_url: null,
          checked_in_at: "2026-08-02T15:00:00.000Z",
          updated_at: "2026-08-02T15:00:00.000Z",
        },
      ],
      error: null,
    });
    mockGetSupabaseClient.mockReturnValue({
      from: jest.fn(() => currentBuilder),
      rpc,
    } as never);

    const result = await fetchTemplePresence("user-1");

    expect(result.people).toHaveLength(1);
    expect(result.people[0].name).toBe("Test Devotee");
    expect(result.current?.is_at_temple).toBe(true);
  });

  it("uses the protected RPC for manual check-in", async () => {
    const rpc = jest.fn().mockResolvedValue({ data: {}, error: null });
    mockGetSupabaseClient.mockReturnValue({ rpc } as never);

    await setMyTemplePresence(true, "manual");

    expect(rpc).toHaveBeenCalledWith("set_my_temple_presence", {
      p_is_at_temple: true,
      p_source: "manual",
    });
  });
});
