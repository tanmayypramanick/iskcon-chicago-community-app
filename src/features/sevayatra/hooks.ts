import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import {
  dismissSevaCareRow,
  fetchAllSevaHours,
  fetchAllSevaScores,
  fetchDevoteeAwardShelf,
  fetchDevoteeBadges,
  fetchDevoteeGivingPoints,
  fetchDevoteeSevaActPoints,
  fetchMyGivingPoints,
  fetchMySevaActPoints,
  fetchMySevaActs,
  fetchMySevaBalance,
  fetchMySevaBreakdown,
  fetchMySevaMala,
  fetchMySevaProfile,
  fetchSevaBadgeLegend,
  fetchSevaBalanceThresholds,
  fetchSevaConcentration,
  fetchSevaGarland,
  fetchSevaNarrowness,
  fetchSevaSupporters,
  fetchSevaYatraDevoteeSummary,
  setMyLeaderboardVisibility,
} from "./api";
import {
  sevaBadgeLegend,
  type SevaBoardRank,
  type SevaPeriodKind,
} from "./types";

export const sevaYatraKeys = {
  all: ["seva-yatra"] as const,
  mine: (userId: string | null, periodKind: SevaPeriodKind | null) =>
    ["seva-yatra", "mine", userId, periodKind] as const,
  profile: (userId: string | null) =>
    ["seva-yatra", "profile", userId] as const,
  breakdown: (userId: string | null) =>
    ["seva-yatra", "breakdown", userId] as const,
  acts: (userId: string | null, from: string | null, to: string | null) =>
    ["seva-yatra", "acts", userId, from, to] as const,
  balance: (userId: string | null) =>
    ["seva-yatra", "balance", userId] as const,
  actPoints: (
    devoteeId: string | null,
    from: string | null,
    to: string | null,
  ) => ["seva-yatra", "act-points", devoteeId, from, to] as const,
  givingPoints: (
    devoteeId: string | null,
    from: string | null,
    to: string | null,
  ) => ["seva-yatra", "giving-points", devoteeId, from, to] as const,
  badges: (devoteeId: string | null) =>
    ["seva-yatra", "badges", devoteeId] as const,
  shelf: (devoteeId: string | null) =>
    ["seva-yatra", "shelf", devoteeId] as const,
  // Keyed on the rank as well as the period: the same period ranked two ways is
  // two different boards, and one must never answer for the other in the cache.
  garland: (periodKind: SevaPeriodKind, rankBy: SevaBoardRank) =>
    ["seva-yatra", "garland", periodKind, rankBy] as const,
  supporters: (periodKind: SevaPeriodKind) =>
    ["seva-yatra", "supporters", periodKind] as const,
  everyone: (periodKind: SevaPeriodKind) =>
    ["seva-yatra", "everyone", periodKind] as const,
  everyoneHours: (periodKind: SevaPeriodKind) =>
    ["seva-yatra", "everyone-hours", periodKind] as const,
  legend: () => ["seva-yatra", "badge-legend"] as const,
  devoteeSummary: (devoteeId: string | null, periodKind: SevaPeriodKind) =>
    ["seva-yatra", "devotee-summary", devoteeId, periodKind] as const,
  concentration: () => ["seva-yatra", "concentration"] as const,
  narrowness: () => ["seva-yatra", "narrowness"] as const,
  thresholds: () => ["seva-yatra", "thresholds"] as const,
};

/**
 * Nothing here polls. A score is recomputed nightly and an award is given when
 * a period closes, so a refetch on the way back into the app — which the
 * client's defaults already do — is as fresh as the data can be.
 */

/** Null `periodKind` is the calendar year, which the scoring never ranks. */
export function useMySevaMala(
  userId: string | null,
  periodKind: SevaPeriodKind | null,
) {
  return useQuery({
    queryKey: sevaYatraKeys.mine(userId, periodKind),
    queryFn: () => fetchMySevaMala(periodKind!),
    enabled: Boolean(userId) && Boolean(periodKind),
  });
}

export function useMySevaProfile(userId: string | null, enabled = true) {
  return useQuery({
    queryKey: sevaYatraKeys.profile(userId),
    queryFn: fetchMySevaProfile,
    enabled: enabled && Boolean(userId),
  });
}

export function useMySevaBreakdown(userId: string | null) {
  return useQuery({
    queryKey: sevaYatraKeys.breakdown(userId),
    queryFn: fetchMySevaBreakdown,
    enabled: Boolean(userId),
  });
}

export function useMySevaActs(
  userId: string | null,
  from: string | null,
  to: string | null,
) {
  return useQuery({
    queryKey: sevaYatraKeys.acts(userId, from, to),
    queryFn: () => fetchMySevaActs(from, to),
    enabled: Boolean(userId),
  });
}

export function useMySevaBalance(userId: string | null) {
  return useQuery({
    queryKey: sevaYatraKeys.balance(userId),
    queryFn: fetchMySevaBalance,
    enabled: Boolean(userId),
  });
}

/**
 * Where a window's points came from. Keyed on the window as well as the
 * devotee, because the same act is worth a different share of a week than of a
 * lifetime and the two answers must not overwrite one another in the cache.
 *
 * `viewerId` is who is asking, not who is being asked about: it is a self-read
 * when the two match and the app.view_all read otherwise, and the server
 * refuses the second to anybody who may not make it.
 */
export function useSevaActPoints(
  devoteeId: string | null,
  viewerId: string | null,
  from: string | null,
  to: string | null,
  enabled = true,
) {
  const mine = Boolean(devoteeId) && devoteeId === viewerId;
  return useQuery({
    queryKey: sevaYatraKeys.actPoints(devoteeId, from, to),
    queryFn: () =>
      mine
        ? fetchMySevaActPoints(from, to)
        : fetchDevoteeSevaActPoints(devoteeId!, from, to),
    enabled: enabled && Boolean(devoteeId),
  });
}

export function useSevaGivingPoints(
  devoteeId: string | null,
  viewerId: string | null,
  from: string | null,
  to: string | null,
  enabled = true,
) {
  const mine = Boolean(devoteeId) && devoteeId === viewerId;
  return useQuery({
    queryKey: sevaYatraKeys.givingPoints(devoteeId, from, to),
    queryFn: () =>
      mine
        ? fetchMyGivingPoints(from, to)
        : fetchDevoteeGivingPoints(devoteeId!, from, to),
    enabled: enabled && Boolean(devoteeId),
  });
}

/** The badges on a devotee's profile right now. */
export function useDevoteeBadges(devoteeId: string | null, enabled = true) {
  return useQuery({
    queryKey: sevaYatraKeys.badges(devoteeId),
    queryFn: () => fetchDevoteeBadges(devoteeId!),
    enabled: enabled && Boolean(devoteeId),
  });
}

/** Their whole shelf. Their own, or anybody's with app.view_all. */
export function useDevoteeAwardShelf(devoteeId: string | null, enabled = true) {
  return useQuery({
    queryKey: sevaYatraKeys.shelf(devoteeId),
    queryFn: () => fetchDevoteeAwardShelf(devoteeId!),
    enabled: enabled && Boolean(devoteeId),
  });
}

/**
 * The legend, server-first. The badges themselves do not change from one hour
 * to the next, so this is read once and kept; the app's own copy of the ten is
 * the first paint, and it is asserted against 0066's seed word for word so the
 * server answering widens the list rather than rewriting it.
 *
 * What comes back carries the gifts as well as the badges — one function
 * answers for both — and `SevaAwardLegend` is where the two are told apart.
 */
export function useSevaBadgeLegend(enabled = true) {
  return useQuery({
    queryKey: sevaYatraKeys.legend(),
    queryFn: async () => {
      const published = await fetchSevaBadgeLegend();
      return published.length ? published : sevaBadgeLegend;
    },
    enabled,
    initialData: sevaBadgeLegend,
    // Stale from the first render on purpose: the fallback draws immediately so
    // the legend is never blank, and the server's own wording still replaces it
    // as soon as it answers.
    initialDataUpdatedAt: 0,
    staleTime: 60 * 60 * 1000,
  });
}

/** Why one devotee is where they are on the board, for one period. */
export function useSevaYatraDevoteeSummary(
  devoteeId: string | null,
  periodKind: SevaPeriodKind,
  enabled = true,
) {
  return useQuery({
    queryKey: sevaYatraKeys.devoteeSummary(devoteeId, periodKind),
    queryFn: () => fetchSevaYatraDevoteeSummary(devoteeId!, periodKind),
    enabled: enabled && Boolean(devoteeId),
  });
}

/**
 * Clear a Seva Care row.
 *
 * Only the concentration list is invalidated, because only it reads
 * `seva_care_dismissals` — `list_seva_narrowness` consults them nowhere, so a
 * dismissal cannot move a narrowness row and refetching that list said
 * otherwise. Which is the whole of the confusion this call used to sit on: a
 * dismissal is a note against the burnout reading, not against the devotee.
 */
export function useDismissSevaCare() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (row: { devoteeId: string; serviceTypeId: string | null }) =>
      dismissSevaCareRow(row.devoteeId, row.serviceTypeId),
    onSuccess: async (persisted) => {
      if (!persisted) return;
      await queryClient.invalidateQueries({
        queryKey: sevaYatraKeys.concentration(),
      });
    },
  });
}

/**
 * The public board. Both rankings come from here rather than from the
 * app.view_all reads below, because both are published to the whole
 * congregation — a devotee who cannot see `list_all_seva_scores` can see this.
 */
export function useSevaGarland(
  periodKind: SevaPeriodKind,
  rankBy: SevaBoardRank = "combined",
  enabled = true,
) {
  return useQuery({
    queryKey: sevaYatraKeys.garland(periodKind, rankBy),
    queryFn: () => fetchSevaGarland(periodKind, rankBy),
    enabled,
  });
}

/** Everybody who gave in a period, by name. Public, and never a ranking. */
export function useSevaSupporters(periodKind: SevaPeriodKind, enabled = true) {
  return useQuery({
    queryKey: sevaYatraKeys.supporters(periodKind),
    queryFn: () => fetchSevaSupporters(periodKind),
    enabled,
  });
}

/**
 * The temple-wide reads. Each answers with an empty set to anybody without
 * `app.view_all`, so `enabled` only spares an ordinary devotee's phone a
 * question whose answer is already known.
 */
export function useAllSevaScores(periodKind: SevaPeriodKind, enabled = true) {
  return useQuery({
    queryKey: sevaYatraKeys.everyone(periodKind),
    queryFn: () => fetchAllSevaScores(periodKind),
    enabled,
  });
}

/**
 * Hours served by everybody, one period at a time. `data` is null where the
 * database has not had 0066 — the caller falls back to `useAllSevaScores`
 * rather than showing a congregation that served nothing.
 */
export function useAllSevaHours(periodKind: SevaPeriodKind, enabled = true) {
  return useQuery({
    queryKey: sevaYatraKeys.everyoneHours(periodKind),
    queryFn: () => fetchAllSevaHours(periodKind),
    enabled,
  });
}

export function useSevaConcentration(enabled = true) {
  return useQuery({
    queryKey: sevaYatraKeys.concentration(),
    queryFn: fetchSevaConcentration,
    enabled,
  });
}

export function useSevaNarrowness(enabled = true) {
  return useQuery({
    queryKey: sevaYatraKeys.narrowness(),
    queryFn: fetchSevaNarrowness,
    enabled,
  });
}

export function useSevaBalanceThresholds(enabled = true) {
  return useQuery({
    queryKey: sevaYatraKeys.thresholds(),
    queryFn: fetchSevaBalanceThresholds,
    enabled,
  });
}

/**
 * Nothing a devotee has earned moves when this flips — but who can see it does,
 * so the shelf goes with the board. 0063 reads the same flag to decide whether
 * a badge is published, and `is_current` would otherwise still claim a badge is
 * on a profile that has just been taken off the board.
 */
export function useSetLeaderboardVisibility(userId: string | null) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (visible: boolean) => setMyLeaderboardVisibility(visible),
    onSuccess: async () => {
      await Promise.all([
        queryClient.invalidateQueries({
          queryKey: ["seva-yatra", "mine", userId],
        }),
        queryClient.invalidateQueries({ queryKey: ["seva-yatra", "garland"] }),
        // `list_seva_supporters` reads the same flag, so opting out takes a
        // devotee's name off the wall of thanks as well as off the board.
        queryClient.invalidateQueries({
          queryKey: ["seva-yatra", "supporters"],
        }),
        queryClient.invalidateQueries({ queryKey: ["seva-yatra", "everyone"] }),
        queryClient.invalidateQueries({
          queryKey: ["seva-yatra", "shelf", userId],
        }),
      ]);
    },
  });
}
