import { useMutation, useQuery } from "@tanstack/react-query";

import { hasAccessPermission, type AccessRole } from "../access/model";
import {
  fetchSuggestedBirthdayAnnouncement,
  fetchTodaysBirthdays,
  fetchUpcomingBirthdays,
} from "./api";

export const birthdayKeys = {
  all: ["birthdays"] as const,
  today: () => ["birthdays", "today"] as const,
  upcoming: (days: number) => ["birthdays", "upcoming", days] as const,
};

/**
 * Whether to draw the prompt at all.
 *
 * Not the gate — `todays_birthdays()` already returns nothing to anybody else,
 * and it is the server that decides. This is so the card never flashes into
 * view while that request is in flight, the way every other privileged view in
 * the app is gated. `app.view_all` is the key the migration itself checks, so
 * the two answers cannot drift apart.
 */
export function canSeeBirthdays(role: AccessRole) {
  return hasAccessPermission(role, "app.view_all");
}

export function useTodaysBirthdays(enabled = true) {
  return useQuery({
    queryKey: birthdayKeys.today(),
    queryFn: fetchTodaysBirthdays,
    enabled,
    // The answer changes once a day, at midnight in Chicago. Re-asking on
    // every screen focus buys nothing.
    staleTime: 5 * 60_000,
  });
}

/**
 * The suggested wording, read on a tap rather than on render.
 *
 * A mutation for a read, because it is a read that belongs to a button: nobody
 * needs the words until they decide to write, there is one call per devotee
 * being wished, and the server raises for a caller who may not have them — a
 * failure that has to appear under the button that was pressed rather than as
 * a broken screen.
 */
export function useBirthdayAnnouncementDraft() {
  return useMutation({
    mutationFn: (devoteeId: string) =>
      fetchSuggestedBirthdayAnnouncement(devoteeId),
  });
}

/**
 * The birthdays coming up, for the summary on the noticeboard and the list
 * behind it.
 *
 * A birthday cannot change while the app is open, so this is deliberately
 * unhurried: it is refetched when a screen mounts and otherwise left alone.
 * The one thing that must be current is the crossing of midnight, which a
 * mount after midnight already covers.
 */
export function useUpcomingBirthdays(days = 60, enabled = true) {
  return useQuery({
    queryKey: birthdayKeys.upcoming(days),
    queryFn: () => fetchUpcomingBirthdays(days),
    enabled,
    staleTime: 5 * 60_000,
  });
}
