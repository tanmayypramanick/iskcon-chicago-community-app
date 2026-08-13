/**
 * The two per-devotee seva reads behind the hours a coordinator sees.
 *
 * Kept apart from the components they feed because this module reaches the
 * Supabase client at import time, and a devotee's own Profile needs the
 * furniture without needing the reads — it asks the two functions that only
 * ever answer about the caller instead.
 */

import { useQuery } from "@tanstack/react-query";

import { reportReachability } from "../../lib/connectivity";
import { getSupabaseClient } from "../../lib/supabase";
import { isConnectionProblem } from "../services/format";
import type { MySevaAct } from "../sevayatra/types";
import { sevaActsWindow, type DevoteeSevaBalanceRow } from "./sevaHours";

/**
 * The seva balance work arrives in migration 0058 and the per-devotee act list
 * in 0061, and a temple's database may not have had either applied. A missing
 * function is "there is nothing to show" rather than a failure, exactly as the
 * seva and giving features already treat it — a red error where a quiet empty
 * state belongs reads as a broken app.
 */
const MIGRATION_PENDING = ["PGRST202", "42883", "42P01", "PGRST205"];

async function listRpc<Row>(
  name: string,
  params: Record<string, unknown>,
): Promise<Row[]> {
  const { data, error } = await getSupabaseClient().rpc(name, params);
  // A transport failure means the server is unreachable; a Postgres error means
  // it answered, so the connection is fine.
  reportReachability(!error || !isConnectionProblem(error));
  if (error) {
    if (MIGRATION_PENDING.includes(error.code ?? "")) return [];
    throw error;
  }
  return (data ?? []) as Row[];
}

/** One devotee's hours per kind of seva. `app.view_all` only, server-side. */
export function useDevoteeSevaBalance(devoteeId: string, enabled: boolean) {
  return useQuery({
    queryKey: ["seva-yatra", "balance-for-devotee", devoteeId],
    queryFn: () =>
      listRpc<DevoteeSevaBalanceRow>("seva_balance_for_devotee", {
        p_devotee_id: devoteeId,
      }),
    enabled,
  });
}

/**
 * One devotee's seva act by act, which 0061 opened to `app.view_all` — until
 * then a President could see the per-seva totals and not the Tuesdays they were
 * made of, so "that one didn't count and I don't know why" could be asked by a
 * devotee and answered by nobody.
 *
 * The bounds are given rather than left to the server's trailing ninety days,
 * because this list is also what the calendar year is derived from. They are
 * computed from Chicago's today and are therefore stable within a day, so two
 * screens asking about the same devotee share one cached answer.
 */
export function useDevoteeSevaActs(devoteeId: string, enabled: boolean) {
  const bounds = sevaActsWindow();
  return useQuery({
    queryKey: [
      "seva-yatra",
      "acts-for-devotee",
      devoteeId,
      bounds.from,
      bounds.to,
    ],
    queryFn: () =>
      listRpc<MySevaAct>("list_devotee_seva_acts", {
        p_devotee_id: devoteeId,
        p_from: bounds.from,
        p_to: bounds.to,
      }),
    enabled,
  });
}
