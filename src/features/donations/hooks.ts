import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import {
  attachDonationToBooking,
  fetchAllDonations,
  fetchAllSponsorships,
  fetchDonationTotals,
  fetchMyDonations,
  fetchMySponsorships,
  fetchSponsorshipAvailability,
  fetchSponsorshipTypes,
  fetchUnmatchedDonations,
  holdSponsorship,
  releaseSponsorshipHold,
} from "./api";

/**
 * Nothing here sets `staleTime` or `refetchOnWindowFocus`, and that is the
 * point. The payment finishes in another app: the devotee leaves for Zeffy, a
 * webhook confirms the booking server-side, and the first this app hears of it
 * is the devotee coming back. App.tsx drives React Query's `focusManager` from
 * AppState, and the client's defaults (3s stale, refetch on focus) turn that
 * return into a refetch — so these queries only have to stay on the defaults to
 * be right when the devotee looks at them again.
 */

export const donationKeys = {
  all: ["donations"] as const,
  types: () => ["donations", "types"] as const,
  availability: (from: string, to: string) =>
    ["donations", "availability", from, to] as const,
  /** Every window, for the invalidation after a hold is taken or given back. */
  availabilityAll: () => ["donations", "availability"] as const,
  myDonations: (userId: string | null) =>
    ["donations", "mine", userId] as const,
  mySponsorships: (userId: string | null) =>
    ["donations", "sponsorships", "mine", userId] as const,
  allDonations: (
    from: string | null,
    to: string | null,
    donorId: string | null = null,
  ) => ["donations", "all", from, to, donorId] as const,
  allDonationsAll: () => ["donations", "all"] as const,
  /**
   * Under the same "all" prefix as the lists, so settling a payment by hand
   * drops the totals with the rows they were computed from.
   */
  donationTotals: (
    from: string | null,
    to: string | null,
    donorId: string | null = null,
  ) => ["donations", "all", "totals", from, to, donorId] as const,
  allSponsorships: () => ["donations", "sponsorships", "all"] as const,
  unmatched: () => ["donations", "unmatched"] as const,
};

export function useSponsorshipTypes() {
  return useQuery({
    queryKey: donationKeys.types(),
    queryFn: fetchSponsorshipTypes,
  });
}

/**
 * One month of calendar at a time. `enabled` is off while no sponsorship has
 * been chosen, and for a sponsorship that has no date at all.
 */
export function useSponsorshipAvailability(
  from: string,
  to: string,
  enabled = true,
) {
  return useQuery({
    queryKey: donationKeys.availability(from, to),
    queryFn: () => fetchSponsorshipAvailability(from, to),
    enabled,
  });
}

export function useMyDonations(userId: string | null) {
  return useQuery({
    queryKey: donationKeys.myDonations(userId),
    queryFn: fetchMyDonations,
    enabled: Boolean(userId),
  });
}

export function useMySponsorships(userId: string | null) {
  return useQuery({
    queryKey: donationKeys.mySponsorships(userId),
    queryFn: fetchMySponsorships,
    enabled: Boolean(userId),
  });
}

/**
 * The temple-wide reads. The server answers with an empty set to anybody
 * without `app.view_all`, so `enabled` only spares an ordinary devotee's phone
 * a question whose answer is already known.
 */
export function useAllDonations(
  from: string | null,
  to: string | null,
  enabled = true,
  /** One devotee's giving, rather than the whole ledger read and then filtered. */
  donorId: string | null = null,
) {
  return useQuery({
    queryKey: donationKeys.allDonations(from, to, donorId),
    queryFn: () => fetchAllDonations(from, to, donorId),
    enabled,
  });
}

/**
 * The total behind a list, computed in the database. Kept separate from the
 * list because a page of rows and the figure over them are different questions
 * — summing the rows on the phone is the right answer only until the day a
 * page is truncated, and then it is quietly the wrong one.
 */
export function useDonationTotals(
  from: string | null,
  to: string | null,
  donorId: string | null = null,
  enabled = true,
) {
  return useQuery({
    queryKey: donationKeys.donationTotals(from, to, donorId),
    queryFn: () => fetchDonationTotals(from, to, donorId),
    enabled,
  });
}

export function useAllSponsorships(enabled = true) {
  return useQuery({
    queryKey: donationKeys.allSponsorships(),
    queryFn: fetchAllSponsorships,
    enabled,
  });
}

export function useUnmatchedDonations(enabled = true) {
  return useQuery({
    queryKey: donationKeys.unmatched(),
    queryFn: fetchUnmatchedDonations,
    enabled,
  });
}

/**
 * Taking a date and giving it back both change what every other devotee's
 * calendar should show, so every window of availability is dropped rather than
 * only the month in view — a hold taken on the last day of August is visible
 * from September's grid too.
 */
function useRefreshCalendar(userId: string | null) {
  const queryClient = useQueryClient();
  return () =>
    Promise.all([
      queryClient.invalidateQueries({
        queryKey: donationKeys.availabilityAll(),
      }),
      queryClient.invalidateQueries({
        queryKey: donationKeys.mySponsorships(userId),
      }),
      queryClient.invalidateQueries({
        queryKey: donationKeys.allSponsorships(),
      }),
    ]);
}

export function useHoldSponsorship(userId: string | null) {
  const refreshCalendar = useRefreshCalendar(userId);
  return useMutation({
    mutationFn: ({
      typeId,
      onDate,
    }: {
      typeId: string;
      /** Null only for a sponsorship booked without a day. */
      onDate: string | null;
    }) => holdSponsorship(typeId, onDate),
    onSuccess: () => refreshCalendar(),
  });
}

export function useReleaseSponsorshipHold(userId: string | null) {
  const refreshCalendar = useRefreshCalendar(userId);
  return useMutation({
    mutationFn: (bookingId: string) => releaseSponsorshipHold(bookingId),
    onSuccess: () => refreshCalendar(),
  });
}

/**
 * Settling a payment by hand confirms a booking, so it moves the calendar as
 * well as the queue and the ledger.
 */
export function useAttachDonationToBooking(userId: string | null) {
  const queryClient = useQueryClient();
  const refreshCalendar = useRefreshCalendar(userId);

  return useMutation({
    mutationFn: ({
      donationId,
      bookingId,
    }: {
      donationId: string;
      bookingId: string;
    }) => attachDonationToBooking(donationId, bookingId),
    onSuccess: async () => {
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: donationKeys.unmatched() }),
        queryClient.invalidateQueries({
          queryKey: donationKeys.allDonationsAll(),
        }),
        refreshCalendar(),
      ]);
    },
  });
}
