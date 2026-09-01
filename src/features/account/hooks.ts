import { useMutation, useQueryClient } from "@tanstack/react-query";

import { forgetMe, leaveTheCommunity } from "./api";

/**
 * Both of these end the session, so neither refreshes anything — there is
 * nothing left to refresh. The cache is cleared instead, because what is in it
 * belongs to a devotee who has just asked the app to stop knowing them, and
 * leaving it in memory for the next sign-in would be the one place their name
 * survived.
 */

export function useLeaveTheCommunity() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: leaveTheCommunity,
    onSuccess: () => queryClient.clear(),
  });
}

export function useForgetMe() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (photoUrl: string | null | undefined) => forgetMe(photoUrl),
    onSuccess: () => queryClient.clear(),
  });
}
