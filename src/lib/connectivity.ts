import { useEffect, useState } from "react";
import { AppState } from "react-native";

/**
 * Whether the temple server is reachable.
 *
 * The app talks to one server, so "are we online" is really "can we reach
 * Supabase". A device can be on wi-fi with no route out, which is exactly what
 * the simulator does, so this checks the thing that matters rather than the
 * radio. It only ever downgrades the UI to a quiet banner — nothing blocks.
 */
let listeners = new Set<(reachable: boolean) => void>();
let reachable = true;
let checking = false;

/** How long the probe waits before calling the server unreachable. */
const PROBE_TIMEOUT_MS = 5_000;

function announce(next: boolean) {
  if (next === reachable) return;
  reachable = next;
  for (const listener of listeners) listener(next);
}

/** Called by the data layer whenever a request succeeds or fails. */
export function reportReachability(next: boolean) {
  announce(next);
}

async function probe() {
  if (checking) return;
  checking = true;
  try {
    // Imported here rather than at module scope: this file is pulled in by
    // screens under test, and creating the Supabase client touches native
    // storage that a test environment does not have.
    const { getSupabaseClient } = await import("./supabase");
    const { isConnectionProblem } = await import("../features/services/format");
    // The lightest authenticated read there is; RLS keeps it to one row.
    //
    // A Postgres error means the server ANSWERED, so the connection is fine —
    // the same distinction every api.ts module draws. Without it an expired or
    // revoked refresh token returns a JWT error, the probe calls that "offline",
    // and the 15-second retry below re-confirms it forever: a permanent false
    // offline banner on a device with a perfect connection.
    const query = getSupabaseClient().from("roles").select("id").limit(1);
    // A captive portal accepts the socket and never replies. Without a bound
    // `checking` stays true for the OS timeout and every later probe returns
    // early, so the banner can never clear itself.
    const timeout = new Promise<"timeout">((resolve) =>
      setTimeout(() => resolve("timeout"), PROBE_TIMEOUT_MS),
    );
    const outcome = await Promise.race([query, timeout]);
    if (outcome === "timeout") announce(false);
    else {
      const { error } = outcome;
      announce(!error || !isConnectionProblem(error));
    }
  } catch {
    // Reaching here means the request could not be made at all — the client
    // failed to construct, or the fetch itself threw. Both are genuine
    // unreachability, unlike a Postgres error handled above.
    announce(false);
  } finally {
    checking = false;
  }
}

export function useServerReachable() {
  const [value, setValue] = useState(reachable);

  useEffect(() => {
    const listener = (next: boolean) => setValue(next);
    listeners.add(listener);

    // Coming back to the app is the moment a devotee most needs to know
    // whether what they are looking at is current.
    const subscription = AppState.addEventListener("change", (state) => {
      if (state === "active") void probe();
    });

    // While offline, keep trying quietly so the banner clears itself.
    const timer = setInterval(() => {
      if (!reachable) void probe();
    }, 15_000);

    return () => {
      listeners.delete(listener);
      subscription.remove();
      clearInterval(timer);
    };
  }, []);

  return value;
}
