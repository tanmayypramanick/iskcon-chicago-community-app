import { useIsFocused } from "@react-navigation/native";
import { useEffect, useRef } from "react";
import { InteractionManager } from "react-native";

type RefreshableQuery = {
  dataUpdatedAt: number;
  isFetching: boolean;
  refetch: () => unknown;
};

/**
 * Refresh an already-mounted screen without making the tab press pay for it.
 * Realtime handles normal live changes and app focus refreshes stale queries;
 * this is the safety net for a tab that has been sitting off-screen.
 */
export function useRefreshOnFocus(
  queries: readonly RefreshableQuery[],
  maxAgeMs = 30_000,
) {
  const isFocused = useIsFocused();
  const queriesRef = useRef(queries);
  queriesRef.current = queries;

  useEffect(() => {
    if (!isFocused) return;

    const task = InteractionManager.runAfterInteractions(() => {
      const oldestAllowed = Date.now() - maxAgeMs;
      for (const query of queriesRef.current) {
        if (query.isFetching || query.dataUpdatedAt > oldestAllowed) continue;
        void query.refetch();
      }
    });

    return () => task.cancel();
  }, [isFocused, maxAgeMs]);
}
