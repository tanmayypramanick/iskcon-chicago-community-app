import { useEffect, useState } from "react";
import { AppState } from "react-native";

/**
 * A clock that re-renders the screen as time passes.
 *
 * Seva moves between "upcoming", "happening now" and "completed" purely
 * because the clock advances — no data changes at that moment. React Query's
 * structural sharing hands back the same object when a refetch returns
 * identical rows, so nothing re-renders and a finished seva can sit under
 * "happening now" indefinitely. This hook is what makes the boundary actually
 * arrive.
 *
 * It also resyncs when the app returns to the foreground, since timers do not
 * fire reliably while backgrounded.
 */
export function useNow(intervalMs = 30_000) {
  const [now, setNow] = useState(() => new Date());

  useEffect(() => {
    const tick = () => setNow(new Date());
    const timer = setInterval(tick, intervalMs);
    const subscription = AppState.addEventListener("change", (state) => {
      if (state === "active") tick();
    });

    return () => {
      clearInterval(timer);
      subscription.remove();
    };
  }, [intervalMs]);

  return now;
}
