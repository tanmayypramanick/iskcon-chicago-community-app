/// <reference types="jest" />

/**
 * The public board, as the deployed database actually answers it.
 *
 * Everything asserted here was checked against a replica of the temple's own
 * data before it was written down:
 *
 *   list_seva_garland(p_period_kind, p_limit, p_rank_by default 'combined')
 *       -> (standing, devotee_id, devotee_name, devotee_photo_url,
 *           points, tier, is_you, gathering)
 *   list_seva_supporters(p_period_kind) -> (devotee_id, devotee_name, photo)
 *
 * Both answer every signed-in devotee. `list_all_seva_scores` — which the app
 * used to build two of the three modes out of — answers nobody without
 * app.view_all, and returned zero rows to an ordinary devotee on that replica.
 */

const mockRpc = jest.fn();

jest.mock("../../../lib/supabase", () => ({
  getSupabaseClient: () => ({ rpc: mockRpc }),
}));

import { fetchSevaGarland, fetchSevaSupporters } from "../api";
import {
  garlandRankForMode,
  sevaBoardModes,
  type SevaBoardMode,
} from "../types";

beforeEach(() => {
  mockRpc.mockReset();
  mockRpc.mockResolvedValue({ data: [], error: null });
});

describe("which read backs each board mode", () => {
  it("offers the temple's three modes", () => {
    expect(sevaBoardModes.map((mode) => mode.key)).toEqual([
      "combined",
      "seva",
      "supporters",
    ]);
  });

  /**
   * The server raises on any `p_rank_by` that is neither 'combined' nor 'seva'
   * — deliberately, so that an unimplemented mode cannot fall through to the
   * combined board — so "supporters" must never reach it. It is a separate
   * function, and mapping it to null is what keeps it out of the argument.
   */
  it("never sends supporters as a ranking", () => {
    expect(garlandRankForMode("combined")).toBe("combined");
    expect(garlandRankForMode("seva")).toBe("seva");
    expect(garlandRankForMode("supporters")).toBeNull();

    for (const mode of sevaBoardModes) {
      const rank = garlandRankForMode(mode.key);
      expect(rank === null || rank === "combined" || rank === "seva").toBe(true);
    }
  });
});

describe("asking the server for a board", () => {
  it("ranks the seva board by seva, rather than re-sorting the combined one", async () => {
    await fetchSevaGarland("week", "seva");

    expect(mockRpc).toHaveBeenCalledWith("list_seva_garland", {
      p_period_kind: "week",
      p_limit: 20,
      p_rank_by: "seva",
    });
  });

  /**
   * The combined board keeps the exact two-argument call it has always made.
   * `p_rank_by` arrived in a later migration and its default is 'combined', so
   * sending it would 404 the one board a devotee reads every day on a temple
   * that has not run that migration — while omitting it changes nothing on one
   * that has.
   */
  it("leaves the third argument off the combined board", async () => {
    await fetchSevaGarland("month");

    expect(mockRpc).toHaveBeenCalledWith("list_seva_garland", {
      p_period_kind: "month",
      p_limit: 20,
    });
    expect(mockRpc.mock.calls[0][1]).not.toHaveProperty("p_rank_by");
  });

  it("reads supporters from their own public function", async () => {
    await fetchSevaSupporters("lifetime");

    expect(mockRpc).toHaveBeenCalledWith("list_seva_supporters", {
      p_period_kind: "lifetime",
    });
  });

  /**
   * Neither board may be built out of `list_all_seva_scores`. That function is
   * app.view_all's; on the temple's own data it answered an ordinary devotee
   * with nothing, which is how the congregation came to see a leaderboard with
   * no numbers on it and two modes that claimed to be unbuilt.
   */
  it("asks no President-only function for any of the three modes", async () => {
    for (const mode of sevaBoardModes) {
      const rank = garlandRankForMode(mode.key satisfies SevaBoardMode);
      if (rank) await fetchSevaGarland("week", rank);
      else await fetchSevaSupporters("week");
    }

    const asked = mockRpc.mock.calls.map((call) => call[0]);
    expect(asked).toEqual([
      "list_seva_garland",
      "list_seva_garland",
      "list_seva_supporters",
    ]);
    expect(asked).not.toContain("list_all_seva_scores");
  });
});

describe("the garland row the server sends", () => {
  /**
   * `points` is `seva_mala_points()` of whichever basis the mode ranked by, and
   * it is published to every signed-in devotee. It is carried through as sent:
   * rounding a rounded figure again is how a board and the hero above it come
   * to disagree by ten.
   */
  it("carries the published points through untouched", async () => {
    mockRpc.mockResolvedValue({
      data: [
        {
          standing: 1,
          devotee_id: "devotee-ramesh",
          devotee_name: "Bhakta Ramesh Patel",
          devotee_photo_url: null,
          points: 750,
          tier: "recognition",
          is_you: false,
          gathering: false,
        },
      ],
      error: null,
    });

    const [row] = await fetchSevaGarland("week");

    expect(row.points).toBe(750);
    expect(row.standing).toBe(1);
  });

  /** A missing migration is a quiet empty board, never a red failure. */
  it("answers with nothing where the function is not deployed", async () => {
    mockRpc.mockResolvedValue({ data: null, error: { code: "PGRST202" } });

    await expect(fetchSevaGarland("week", "seva")).resolves.toEqual([]);
    await expect(fetchSevaSupporters("week")).resolves.toEqual([]);
  });
});
