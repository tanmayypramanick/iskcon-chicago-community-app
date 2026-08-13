import { useMutation, useQuery } from "@tanstack/react-query";

import { hasAccessPermission, type AccessRole } from "../access/model";
import {
  fetchSuggestedBirthdayAnnouncement,
  fetchTodaysBirthdays,
} from "./api";

export const birthdayKeys = {
  all: ["birthdays"] as const,
  today: () => ["birthdays", "today"] as const,
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
