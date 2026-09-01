import { isConnectionProblem } from "../services/format";
import { reportReachability } from "../../lib/connectivity";
import { getSupabaseClient } from "../../lib/supabase";
import { photoPathIn } from "./photoPath";

/**
 * Leaving, and being forgotten.
 *
 * Two different requests, and the difference matters enough to keep them in
 * separate functions rather than behind one flag: one is a pause and the other
 * cannot be undone. See 202609010105_leaving_and_being_forgotten.sql.
 */

async function runRpc(name: string, params: Record<string, unknown> = {}) {
  const { data, error } = await getSupabaseClient().rpc(name, params);
  reportReachability(!error || !isConnectionProblem(error));
  if (error) throw error;
  return data;
}

/** Steps away from the app. Erases nothing; signing in again undoes it. */
export function leaveTheCommunity() {
  return runRpc("leave_the_community");
}

/**
 * Erases every personal detail the temple holds, for good.
 *
 * The photograph goes first and separately, because it is a file in Storage
 * and the database cannot reach it — Storage refuses SQL deletion outright, by
 * design, so a row deleted that way would leave the picture itself sitting in
 * the bucket. It is removed here, while the devotee still holds the session
 * that owns it. A failure to delete it does not stop the erasure: better to
 * lose the photograph from the app and report the orphan than to refuse
 * somebody their deletion because one file would not go.
 */
export async function forgetMe(photoUrl: string | null | undefined) {
  const orphanedPhoto = photoUrl ? await deletePhoto(photoUrl) : false;
  await runRpc("forget_me");
  return { orphanedPhoto };
}

/** Returns true when the file could not be removed and is now an orphan. */
async function deletePhoto(photoUrl: string): Promise<boolean> {
  const path = photoPathIn(photoUrl);
  if (!path) return true;
  try {
    const { error } = await getSupabaseClient()
      .storage.from("devotee-photos")
      .remove([path]);
    return Boolean(error);
  } catch {
    return true;
  }
}

