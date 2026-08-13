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
    // The lightest authenticated read there is; RLS keeps it to one row.
    const { error } = await getSupabaseClient()
      .from("roles")
      .select("id")
      .limit(1);
    announce(!error);
  } catch {
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
