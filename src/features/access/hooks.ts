import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import {
  appointAccess,
  createAccessRequest,
  fetchAccessAppointments,
  fetchCurrentAccessProfile,
  fetchAccessApprovers,
  fetchDevoteeAccessGrants,
  fetchDevoteeProfiles,
  fetchMayAppointAccess,
  fetchMyAccessRequests,
  fetchPendingAccessRequests,
  missingRequiredProfileFields,
  requestEmailChange,
  revokeAccess,
  reviewAccessRequest,
  updateMyProfile,
  updateMyProfileCommunity,
  updateMyProfileExtras,
  type ProfileCommunityInput,
  type ProfileDetailsInput,
  type ProfileExtrasInput,
  type RequiredProfileField,
} from "./api";
import type { AccessRole } from "./model";

const accessKeys = {
  profile: (userId: string | null) => ["access", "profile", userId] as const,
  requests: (userId: string | null) => ["access", "requests", userId] as const,
  mayAppoint: (userId: string | null) =>
    ["access", "may-appoint", userId] as const,
  appointments: (devoteeId: string | null) =>
    ["access", "appointments", devoteeId] as const,
  grants: (devoteeId: string | null) =>
    ["access", "grants", devoteeId] as const,
};

export function useCurrentAccessProfile(userId: string | null) {
  return useQuery({
    queryKey: accessKeys.profile(userId),
    queryFn: fetchCurrentAccessProfile,
    enabled: Boolean(userId),
    // Access notifications invalidate this immediately. Polling is only a
    // recovery path for a temporarily disconnected realtime socket.
    refetchInterval: 5 * 60_000,
  });
}

export type RequiredProfileState =
  | { status: "checking" }
  | { status: "clear" }
  | { status: "blocked"; missing: RequiredProfileField[] };

/**
 * Whether the six answers the temple asks for are on the devotee's profile.
 *
 * It shares a query key with every other reader of the profile, so standing in
 * front of the app costs no extra request, and a saved answer reaches the gate
 * the moment the profile is invalidated.
 *
 * It fails open twice over. A profile that could not be read is not evidence of
 * a profile that was never filled in — the devotee is offline, or the server is
 * down — and a form that cannot save is a locked door rather than a welcome. So
 * an error, like a database behind on migrations, lets them through.
 */
export function useRequiredProfile(userId: string | null): RequiredProfileState {
  const profileQuery = useCurrentAccessProfile(userId);

  if (!userId) return { status: "clear" };

  const profile = profileQuery.data;
  if (!profile) {
    return profileQuery.isError ? { status: "clear" } : { status: "checking" };
  }

  const missing = missingRequiredProfileFields(profile);
  return missing.length ? { status: "blocked", missing } : { status: "clear" };
}

export function usePendingAccessRequests(userId: string | null) {
  return useQuery({
    queryKey: accessKeys.requests(userId),
    queryFn: fetchPendingAccessRequests,
    enabled: Boolean(userId),
    refetchInterval: 5 * 60_000,
  });
}

export function useCreateAccessRequest(userId: string | null) {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({
      requestedRole,
      message,
      approverId,
    }: {
      requestedRole: AccessRole;
      message: string;
      approverId: string;
    }) => createAccessRequest(requestedRole, message, approverId),
    onSuccess: () =>
      queryClient.invalidateQueries({
        queryKey: accessKeys.requests(userId),
      }),
  });
}

export function useReviewAccessRequest(userId: string | null) {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({
      requestId,
      decision,
      note,
    }: {
      requestId: string;
      decision: "approved" | "denied";
      note?: string | null;
    }) => reviewAccessRequest(requestId, decision, note),
    onSuccess: async () => {
      await Promise.all([
        queryClient.invalidateQueries({
          queryKey: accessKeys.requests(userId),
        }),
        queryClient.invalidateQueries({ queryKey: ["access", "profile"] }),
      ]);
    },
  });
}

/**
 * One save writes to three functions, and the same person is read back by the
 * devotee list and by whoever is looking at their profile, so all of them are
 * refreshed together rather than leaving one screen showing yesterday's answer.
 */
function useRefreshProfile(userId: string | null) {
  const queryClient = useQueryClient();
  return () =>
    Promise.all([
      queryClient.invalidateQueries({ queryKey: accessKeys.profile(userId) }),
      queryClient.invalidateQueries({
        queryKey: ["access", "devotee-profiles"],
      }),
      queryClient.invalidateQueries({ queryKey: ["devotee-public-profile"] }),
    ]);
}

export function useUpdateMyProfile(userId: string | null) {
  const refreshProfile = useRefreshProfile(userId);
  return useMutation({
    mutationFn: (input: ProfileDetailsInput) => updateMyProfile(input),
    onSuccess: () => refreshProfile(),
  });
}

export function useRequestEmailChange() {
  return useMutation({
    mutationFn: (newEmail: string) => requestEmailChange(newEmail),
  });
}

/** The congregation, for the President and Tech Admin. Empty for everyone else. */
export function useDevoteeProfiles(enabled: boolean) {
  return useQuery({
    queryKey: ["access", "devotee-profiles"],
    queryFn: fetchDevoteeProfiles,
    enabled,
  });
}

export function useMyAccessRequests(userId: string | null) {
  return useQuery({
    queryKey: ["access", "my-requests", userId],
    queryFn: fetchMyAccessRequests,
    enabled: Boolean(userId),
  });
}

export function useAccessApprovers() {
  return useQuery({
    queryKey: ["access", "approvers"],
    queryFn: fetchAccessApprovers,
  });
}

export function useMayAppointAccess(userId: string | null) {
  return useQuery({
    queryKey: accessKeys.mayAppoint(userId),
    queryFn: fetchMayAppointAccess,
    enabled: Boolean(userId),
  });
}

/** Every grant the temple has made, or one devotee's when an id is given. */
export function useAccessAppointments(
  enabled: boolean,
  devoteeId: string | null = null,
) {
  return useQuery({
    queryKey: accessKeys.appointments(devoteeId),
    queryFn: () => fetchAccessAppointments(devoteeId),
    enabled,
  });
}

/** Who granted a devotee the access they hold today. Empty to everyone else. */
export function useDevoteeAccessGrants(
  devoteeId: string | null,
  enabled: boolean,
) {
  return useQuery({
    queryKey: accessKeys.grants(devoteeId),
    queryFn: () => fetchDevoteeAccessGrants(devoteeId),
    enabled: enabled && Boolean(devoteeId),
  });
}

/**
 * An access change moves the devotee's role, so it is not only the record that
 * goes stale: their profile, the congregation list and whichever profile screen
 * is open all show the old level until they are refetched together.
 */
function useRefreshAccessRecord() {
  const queryClient = useQueryClient();
  return () =>
    Promise.all(
      [
        ["access", "appointments"],
        ["access", "grants"],
        ["access", "profile"],
        ["access", "devotee-profiles"],
        ["devotee-public-profile"],
      ].map((queryKey) => queryClient.invalidateQueries({ queryKey })),
    );
}

export function useAppointAccess() {
  const refresh = useRefreshAccessRecord();
  return useMutation({
    mutationFn: ({
      devoteeId,
      roleName,
      note,
    }: {
      devoteeId: string;
      roleName: "volunteer" | "core";
      note: string | null;
    }) => appointAccess(devoteeId, roleName, note),
    onSuccess: () => refresh(),
  });
}

export function useRevokeAccess() {
  const refresh = useRefreshAccessRecord();
  return useMutation({
    mutationFn: ({
      devoteeId,
      note,
    }: {
      devoteeId: string;
      note: string | null;
    }) => revokeAccess(devoteeId, note),
    onSuccess: () => refresh(),
  });
}

export function useUpdateMyProfileExtras(userId: string | null) {
  const refreshProfile = useRefreshProfile(userId);
  return useMutation({
    mutationFn: (input: ProfileExtrasInput) => updateMyProfileExtras(input),
    onSuccess: () => refreshProfile(),
  });
}

export function useUpdateMyProfileCommunity(userId: string | null) {
  const refreshProfile = useRefreshProfile(userId);
  return useMutation({
    mutationFn: (input: ProfileCommunityInput) =>
      updateMyProfileCommunity(input),
    onSuccess: () => refreshProfile(),
  });
}
