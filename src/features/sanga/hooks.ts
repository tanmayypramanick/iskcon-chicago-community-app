import type { RealtimeChannel } from "@supabase/supabase-js";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import type { QueryClient } from "@tanstack/react-query";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";

import { useChannelSuffix } from "../../lib/channelSuffix";
import { getSupabaseClient } from "../../lib/supabase";
import { usePrototypeSession } from "../../store/usePrototypeSession";
import { useCurrentAccessProfile } from "../access/hooks";
import { hasAccessPermission, type AccessRole } from "../access/model";
import {
  addSangaMember,
  createSanga,
  deleteSanga,
  deleteSangaMessage,
  fetchMySangas,
  fetchPendingSangas,
  fetchSangaJoinRequests,
  fetchSangaMembers,
  fetchSangaMessages,
  fetchSangas,
  leaveSanga,
  markSangaRead,
  pickMessageImage,
  removeSangaMember,
  requestToJoinSanga,
  reviewSanga,
  reviewSangaJoinRequest,
  sendSangaMessage,
  transferSangaAdmin,
  uploadMessageImage,
} from "./api";
import type {
  MySangaSummary,
  PickedMessageImage,
  SangaDecision,
  SangaMember,
  SangaMessage,
  SangaMessageRow,
  SangaSummary,
  SangaTypingSignal,
  SangaTypist,
  SangaViewerCapabilities,
  SendSangaMessageInput,
} from "./types";

/** A sanga picture goes through the direct-message picker; same bucket, same
 * limits, same rebuild warning on an old binary. */
export { pickMessageImage };

export const sangaKeys = {
  all: ["sanga"] as const,
  list: () => ["sanga", "list"] as const,
  mine: () => ["sanga", "mine"] as const,
  pending: () => ["sanga", "pending"] as const,
  members: (sangaId: string | null) => ["sanga", "members", sangaId] as const,
  joinRequests: (sangaId: string | null) =>
    ["sanga", "join-requests", sangaId] as const,
  messages: (sangaId: string | null) => ["sanga", "messages", sangaId] as const,
};

/**
 * The four sanga tables are on Realtime as of 202608040043_sanga_powers.sql,
 * and every mutation below invalidates what it touched, so these lists are
 * pushed to rather than polled.
 *
 * That is what buys the staleness window. The app's default is
 * `refetchOnMount: "always"`, which is right for a screen whose data only ever
 * arrives when it is asked for: it means every hop between the browse list, a
 * thread and its roll fires a fresh round of RPCs against data that is already
 * correct, and the screen sits under them. Here the window is opened and mount
 * refetches only what has actually gone stale.
 *
 * The floor under all of it is app focus: `refetchOnWindowFocus` is inherited
 * and App.tsx drives it from AppState, so a phone that was asleep — or a
 * temple whose database has not had the migration applied and therefore has no
 * realtime at all — still comes back to fresh lists.
 */
const LIVE_LIST = { staleTime: 30_000, refetchOnMount: true } as const;

export function useSangas(enabled = true) {
  return useQuery({
    queryKey: sangaKeys.list(),
    queryFn: fetchSangas,
    enabled,
    ...LIVE_LIST,
  });
}

export function useMySangas(enabled = true) {
  return useQuery({
    queryKey: sangaKeys.mine(),
    queryFn: fetchMySangas,
    enabled,
    ...LIVE_LIST,
  });
}

/**
 * The President's approval queue. Pass `enabled` false for everyone else
 * rather than relying on the empty result — a call that can only return
 * nothing is a call not worth making.
 */
export function usePendingSangas(enabled = true) {
  return useQuery({
    queryKey: sangaKeys.pending(),
    queryFn: fetchPendingSangas,
    enabled,
    ...LIVE_LIST,
  });
}

export function useSangaMembers(sangaId: string | null) {
  return useQuery({
    queryKey: sangaKeys.members(sangaId),
    queryFn: () => fetchSangaMembers(sangaId!),
    enabled: Boolean(sangaId),
    ...LIVE_LIST,
  });
}

export function useSangaJoinRequests(sangaId: string | null, enabled = true) {
  return useQuery({
    queryKey: sangaKeys.joinRequests(sangaId),
    queryFn: () => fetchSangaJoinRequests(sangaId!),
    enabled: Boolean(sangaId) && enabled,
    ...LIVE_LIST,
  });
}

/** The thread, oldest first. Realtime keeps it current once it is open. */
export function useSangaMessages(sangaId: string | null) {
  return useQuery({
    queryKey: sangaKeys.messages(sangaId),
    queryFn: () => fetchSangaMessages(sangaId!),
    enabled: Boolean(sangaId),
    ...LIVE_LIST,
  });
}

/**
 * The cached browse list, "my sangas" list and one sanga's roll, kept so a
 * failed mutation can put all three back exactly as they were.
 */
type CachedSanga = {
  list: SangaSummary[] | undefined;
  mine: MySangaSummary[] | undefined;
  members: SangaMember[] | undefined;
};

function snapshotSanga(
  queryClient: QueryClient,
  sangaId: string | null,
): CachedSanga {
  return {
    list: queryClient.getQueryData<SangaSummary[]>(sangaKeys.list()),
    mine: queryClient.getQueryData<MySangaSummary[]>(sangaKeys.mine()),
    members: sangaId
      ? queryClient.getQueryData<SangaMember[]>(sangaKeys.members(sangaId))
      : undefined,
  };
}

function restoreSanga(
  queryClient: QueryClient,
  sangaId: string | null,
  previous: CachedSanga,
) {
  if (previous.list) {
    queryClient.setQueryData(sangaKeys.list(), previous.list);
  }
  if (previous.mine) {
    queryClient.setQueryData(sangaKeys.mine(), previous.mine);
  }
  if (sangaId && previous.members) {
    queryClient.setQueryData(sangaKeys.members(sangaId), previous.members);
  }
}

/**
 * Patches one sanga in both lists in place.
 *
 * An updater returning undefined is a no-op, so a list that has never been
 * loaded stays unloaded rather than being seeded with an empty array that
 * would read as "no sangas".
 */
function patchSanga(
  queryClient: QueryClient,
  sangaId: string,
  patch: {
    list?: (row: SangaSummary) => SangaSummary;
    mine?: (row: MySangaSummary) => MySangaSummary;
  },
) {
  if (patch.list) {
    const apply = patch.list;
    queryClient.setQueryData<SangaSummary[]>(sangaKeys.list(), (existing) =>
      existing?.map((row) => (row.id === sangaId ? apply(row) : row)),
    );
  }
  if (patch.mine) {
    const apply = patch.mine;
    queryClient.setQueryData<MySangaSummary[]>(sangaKeys.mine(), (existing) =>
      existing?.map((row) => (row.id === sangaId ? apply(row) : row)),
    );
  }
}

/** The order list_sanga_members returns: whoever runs it, then by name. */
function sortRoll(rows: SangaMember[]): SangaMember[] {
  return [...rows].sort((left, right) => {
    if (left.role !== right.role) return left.role === "admin" ? -1 : 1;
    return left.name.localeCompare(right.name);
  });
}

function patchRoll(
  queryClient: QueryClient,
  sangaId: string,
  apply: (rows: SangaMember[]) => SangaMember[],
) {
  queryClient.setQueryData<SangaMember[]>(
    sangaKeys.members(sangaId),
    (existing) => (existing ? sortRoll(apply(existing)) : existing),
  );
}

/** Moves the member count on every list showing this sanga. */
function shiftMemberCount(
  queryClient: QueryClient,
  sangaId: string,
  delta: number,
) {
  patchSanga(queryClient, sangaId, {
    list: (row) => ({
      ...row,
      member_count: Math.max(0, row.member_count + delta),
    }),
    mine: (row) => ({
      ...row,
      member_count: Math.max(0, row.member_count + delta),
    }),
  });
}

function invalidateLists(queryClient: QueryClient) {
  void queryClient.invalidateQueries({ queryKey: sangaKeys.list() });
  void queryClient.invalidateQueries({ queryKey: sangaKeys.mine() });
}

/** Proposing one. It is pending until the President looks at it, so only the
 * viewer's own list and the approval queue change. */
export function useCreateSanga() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({
      name,
      description,
    }: {
      name: string;
      description?: string | null;
    }) => createSanga(name, description),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: sangaKeys.mine() });
      void queryClient.invalidateQueries({ queryKey: sangaKeys.pending() });
    },
  });
}

/** The President's decision. An approval puts the sanga into the browse list. */
export function useReviewSanga() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({
      sangaId,
      decision,
      note,
    }: {
      sangaId: string;
      decision: SangaDecision;
      note?: string | null;
    }) => reviewSanga(sangaId, decision, note),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: sangaKeys.pending() });
      invalidateLists(queryClient);
    },
  });
}

/**
 * Asking to join. The row flips to "Requested" before the request goes out:
 * the round trip is the only slow part of asking, and a button that sits inert
 * until it returns is what makes an app feel heavy. A failure puts the list
 * back exactly as it was.
 *
 * Private: every screen goes through useAskToJoinSanga, which is the same ask
 * with the second tap taken out of it.
 */
function useRequestToJoinSanga() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({
      sangaId,
      message,
    }: {
      sangaId: string;
      message?: string | null;
    }) => requestToJoinSanga(sangaId, message),

    onMutate: ({ sangaId }) => {
      const previous = snapshotSanga(queryClient, null);

      // Written synchronously, before cancelQueries. `await cancelQueries()`
      // waits on any in-flight fetch for the key, and Supabase requests are not
      // abortable here, so awaiting it would queue this write behind whatever
      // is already on the wire — the exact delay the optimistic update exists
      // to remove.
      patchSanga(queryClient, sangaId, {
        list: (row) => ({ ...row, request_status: "pending" }),
      });

      // Now that the UI is already correct, stop an in-flight fetch from
      // landing on top of it. Not awaited.
      void queryClient.cancelQueries({ queryKey: sangaKeys.list() });

      return previous;
    },

    onError: (_error, _variables, context) => {
      if (context) restoreSanga(queryClient, null, context);
    },

    // The admin's inbox has a new row in it, and the browse list's
    // request_status now has a server-side answer.
    onSettled: (_data, _error, { sangaId }) => {
      void queryClient.invalidateQueries({ queryKey: sangaKeys.list() });
      void queryClient.invalidateQueries({
        queryKey: sangaKeys.joinRequests(sangaId),
      });
    },
  });
}

/**
 * Asking to join, once.
 *
 * The optimistic patch above already redraws the control as "Requested" and
 * disables it, but that redraw is a render away and two taps can land inside
 * one. The set of asks in flight closes that window in the same tick as the
 * first tap, so a double tap cannot produce a second request. The server
 * dedupes as well — request_to_join_sanga returns the row it already made —
 * but it dedupes after notifying the admin, which is one notification too
 * many.
 *
 * mutateAsync rather than mutate's per-call callbacks: a second ask, for a
 * different sanga, swaps the shared observer and drops the first call's
 * callbacks with it, which would strand that sanga's id in the set forever.
 */
export function useAskToJoinSanga() {
  const { mutateAsync, isPending, variables } = useRequestToJoinSanga();
  const inFlight = useRef(new Set<string>());

  const ask = useCallback(
    (sangaId: string, onError?: (error: unknown) => void) => {
      if (inFlight.current.has(sangaId)) return;
      inFlight.current.add(sangaId);
      void mutateAsync({ sangaId })
        .catch((error: unknown) => onError?.(error))
        .finally(() => inFlight.current.delete(sangaId));
    },
    [mutateAsync],
  );

  return {
    ask,
    /** The sanga whose ask is on the wire, for the control that sent it. */
    askingSangaId: isPending ? (variables?.sangaId ?? null) : null,
  };
}

/** The admin answering. Approving adds the devotee, so the roll changes too. */
export function useReviewSangaJoinRequest() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({
      requestId,
      decision,
    }: {
      requestId: string;
      decision: SangaDecision;
    }) => reviewSangaJoinRequest(requestId, decision),
    // The row carries its sanga, so the caller does not have to pass it.
    onSuccess: (row) => {
      void queryClient.invalidateQueries({
        queryKey: sangaKeys.joinRequests(row.sanga_id),
      });
      void queryClient.invalidateQueries({
        queryKey: sangaKeys.members(row.sanga_id),
      });
      invalidateLists(queryClient);
    },
  });
}

export type AddSangaMemberInput = {
  sangaId: string;
  devoteeId: string;
  /**
   * Enough to draw the devotee on the roll before the server answers. Neither
   * reaches the server, and without a name the optimistic row is skipped
   * rather than guessed at.
   */
  devoteeName?: string;
  devoteePhotoUrl?: string | null;
};

/**
 * The admin adding somebody straight in. Also answers any request that devotee
 * had waiting, which is why the inbox is refreshed alongside the roll.
 */
export function useAddSangaMember() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({ sangaId, devoteeId }: AddSangaMemberInput) =>
      addSangaMember(sangaId, devoteeId),

    onMutate: ({ sangaId, devoteeId, devoteeName, devoteePhotoUrl }) => {
      const previous = snapshotSanga(queryClient, sangaId);
      if (!devoteeName) return previous;

      const alreadyOnRoll = (previous.members ?? []).some(
        (member) => member.id === devoteeId,
      );

      // Synchronous, and before cancelQueries — see useRequestToJoinSanga.
      patchRoll(queryClient, sangaId, (rows) =>
        alreadyOnRoll
          ? rows
          : [
              ...rows,
              {
                id: devoteeId,
                name: devoteeName,
                photo_url: devoteePhotoUrl ?? null,
                role: "member",
                joined_at: new Date().toISOString(),
                // The real attribution arrives with the refetch below. Nobody
                // is shown as having been added by nobody for longer than that.
                added_by: null,
                added_by_name: null,
              },
            ],
      );
      // Adding somebody already in the sanga is a no-op on the server, so the
      // count must not move for it either.
      if (!alreadyOnRoll) shiftMemberCount(queryClient, sangaId, 1);

      void queryClient.cancelQueries({ queryKey: sangaKeys.members(sangaId) });
      void queryClient.cancelQueries({ queryKey: sangaKeys.list() });
      void queryClient.cancelQueries({ queryKey: sangaKeys.mine() });

      return previous;
    },

    onError: (_error, { sangaId }, context) => {
      if (context) restoreSanga(queryClient, sangaId, context);
    },

    onSettled: (_row, _error, { sangaId }) => {
      void queryClient.invalidateQueries({
        queryKey: sangaKeys.members(sangaId),
      });
      void queryClient.invalidateQueries({
        queryKey: sangaKeys.joinRequests(sangaId),
      });
      // The member count on every list showing this sanga has moved.
      invalidateLists(queryClient);
    },
  });
}

/**
 * The admin removing somebody. The server refuses the last admin, and the
 * rollback is what puts them back on the roll when it does.
 */
export function useRemoveSangaMember() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({
      sangaId,
      devoteeId,
    }: {
      sangaId: string;
      devoteeId: string;
    }) => removeSangaMember(sangaId, devoteeId),

    onMutate: ({ sangaId, devoteeId }) => {
      const previous = snapshotSanga(queryClient, sangaId);
      const wasOnRoll = (previous.members ?? []).some(
        (member) => member.id === devoteeId,
      );

      // Synchronous, and before cancelQueries — see useRequestToJoinSanga.
      patchRoll(queryClient, sangaId, (rows) =>
        rows.filter((member) => member.id !== devoteeId),
      );
      if (wasOnRoll) shiftMemberCount(queryClient, sangaId, -1);

      void queryClient.cancelQueries({ queryKey: sangaKeys.members(sangaId) });
      void queryClient.cancelQueries({ queryKey: sangaKeys.list() });
      void queryClient.cancelQueries({ queryKey: sangaKeys.mine() });

      return previous;
    },

    onError: (_error, { sangaId }, context) => {
      if (context) restoreSanga(queryClient, sangaId, context);
    },

    onSettled: (_removed, _error, { sangaId }) => {
      void queryClient.invalidateQueries({
        queryKey: sangaKeys.members(sangaId),
      });
      // Removal deletes their request history for this sanga as well.
      void queryClient.invalidateQueries({
        queryKey: sangaKeys.joinRequests(sangaId),
      });
      invalidateLists(queryClient);
    },
  });
}

/** Handing it over. Both devotees' roles move, so the roll is refetched. */
export function useTransferSangaAdmin() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({
      sangaId,
      devoteeId,
    }: {
      sangaId: string;
      devoteeId: string;
    }) => transferSangaAdmin(sangaId, devoteeId),
    onSuccess: (_row, { sangaId }) => {
      void queryClient.invalidateQueries({
        queryKey: sangaKeys.members(sangaId),
      });
      invalidateLists(queryClient);
    },
  });
}

/**
 * Leaving. The pill and the member count move before the request goes out, for
 * the same reason asking to join does. The last admin is refused by the server
 * — they have to hand the sanga on first — and the rollback is what puts the
 * row back when that happens.
 */
export function useLeaveSanga() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({ sangaId }: { sangaId: string; selfId?: string }) =>
      leaveSanga(sangaId),

    onMutate: ({ sangaId, selfId }) => {
      const previous = snapshotSanga(queryClient, sangaId);

      // Synchronous, and before cancelQueries — see useRequestToJoinSanga.
      patchSanga(queryClient, sangaId, {
        list: (row) => ({
          ...row,
          is_member: false,
          is_admin: false,
          request_status: null,
          member_count: Math.max(0, row.member_count - 1),
        }),
        mine: (row) => ({
          ...row,
          is_member: false,
          is_admin: false,
          member_count: Math.max(0, row.member_count - 1),
        }),
      });
      // Only when the caller says who they are: taking a guess at which row on
      // the roll is "me" would take somebody else off it.
      if (selfId) {
        patchRoll(queryClient, sangaId, (rows) =>
          rows.filter((member) => member.id !== selfId),
        );
      }

      void queryClient.cancelQueries({ queryKey: sangaKeys.list() });
      void queryClient.cancelQueries({ queryKey: sangaKeys.mine() });
      void queryClient.cancelQueries({ queryKey: sangaKeys.members(sangaId) });

      return previous;
    },

    onError: (_error, { sangaId }, context) => {
      if (context) restoreSanga(queryClient, sangaId, context);
    },

    // Only the server knows the real count once other devotees are moving in
    // and out at the same time.
    onSettled: (_data, _error, { sangaId }) => {
      invalidateLists(queryClient);
      void queryClient.invalidateQueries({
        queryKey: sangaKeys.members(sangaId),
      });
      // A devotee who has left may ask again, so the browse row's
      // request_status is no longer whatever it was.
      void queryClient.invalidateQueries({
        queryKey: sangaKeys.joinRequests(sangaId),
      });
    },
  });
}

/**
 * Closing one for good — its admin, or a holder of app.view_all.
 *
 * Not optimistic. Everything else here can be put back by a failed mutation's
 * rollback; a circle vanishing from the screen before the server has agreed
 * that it is gone is the one thing that must not be guessed at.
 */
export function useDeleteSanga() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({ sangaId }: { sangaId: string; name?: string }) =>
      deleteSanga(sangaId),

    onSuccess: (_row, { sangaId }) => {
      // Nothing under a deleted sanga can be read any more — the roll, the
      // inbox and the thread all answer empty now — so they are dropped rather
      // than left in the cache to be refetched into nothing.
      queryClient.removeQueries({ queryKey: sangaKeys.members(sangaId) });
      queryClient.removeQueries({ queryKey: sangaKeys.joinRequests(sangaId) });
      queryClient.removeQueries({ queryKey: sangaKeys.messages(sangaId) });
      invalidateLists(queryClient);
      // A sanga can be deleted before the President has answered it.
      void queryClient.invalidateQueries({ queryKey: sangaKeys.pending() });
    },
  });
}

// ---------------------------------------------------------------------------
// The thread.
// ---------------------------------------------------------------------------

/** Oldest first, matching list_sanga_messages, so no screen has to re-sort. */
function sortThread(rows: SangaMessage[]): SangaMessage[] {
  return [...rows].sort((left, right) =>
    left.created_at.localeCompare(right.created_at),
  );
}

/**
 * Neither the send RPC nor a realtime row carries a sender's name, so it is
 * recovered from what is already on screen: an earlier message from the same
 * devotee, or the roll. Null when neither knows them, which the realtime hook
 * answers with a refetch.
 */
function resolveSender(
  queryClient: QueryClient,
  sangaId: string,
  senderId: string,
  thread: SangaMessage[] | undefined,
): { name: string | null; photoUrl: string | null } {
  const spoken = thread?.find(
    (message) => message.sender_id === senderId && message.sender_name !== null,
  );
  if (spoken) {
    return { name: spoken.sender_name, photoUrl: spoken.sender_photo_url };
  }
  const roll = queryClient.getQueryData<SangaMember[]>(
    sangaKeys.members(sangaId),
  );
  const member = roll?.find((candidate) => candidate.id === senderId);
  return { name: member?.name ?? null, photoUrl: member?.photo_url ?? null };
}

function toSangaMessage(
  row: SangaMessageRow,
  sender: { name: string | null; photoUrl: string | null },
): SangaMessage {
  return {
    id: row.id,
    sanga_id: row.sanga_id,
    sender_id: row.sender_id,
    sender_name: sender.name,
    sender_photo_url: sender.photoUrl,
    body: row.body,
    image_url: row.image_url,
    created_at: row.created_at,
    deleted_at: row.deleted_at,
  };
}

/**
 * Writes one message into the cached thread without a refetch, so a posted or
 * arriving message lands the instant it exists. Left alone when the thread has
 * not been loaded yet — seeding it with a single row would look like a
 * conversation of one and be treated as fresh.
 *
 * Returns false when the sender could not be named, which is the caller's cue
 * to refetch rather than draw an anonymous bubble.
 */
function upsertCachedSangaMessage(
  queryClient: QueryClient,
  sangaId: string,
  row: SangaMessageRow,
): boolean {
  let named = true;
  queryClient.setQueryData<SangaMessage[]>(
    sangaKeys.messages(sangaId),
    (existing) => {
      if (!existing) return existing;
      const previous = existing.find((message) => message.id === row.id);
      // A message that is already on screen keeps the name it was drawn with:
      // a deletion returns the same row with its content stripped, and looking
      // the sender up again would be work for an answer we already have.
      const sender = previous
        ? { name: previous.sender_name, photoUrl: previous.sender_photo_url }
        : resolveSender(queryClient, sangaId, row.sender_id, existing);
      named = sender.name !== null;
      return sortThread([
        ...existing.filter((message) => message.id !== row.id),
        toSangaMessage(row, sender),
      ]);
    },
  );
  return named;
}

/** The placeholder a message wears between the tap and the server's reply. */
function insertOptimisticSangaMessage(
  queryClient: QueryClient,
  sangaId: string,
  fields: {
    localId: string;
    senderId: string;
    senderName?: string | null;
    senderPhotoUrl?: string | null;
    body?: string | null;
    imageUrl?: string | null;
  },
) {
  const optimistic: SangaMessage = {
    id: fields.localId,
    sanga_id: sangaId,
    sender_id: fields.senderId,
    sender_name: fields.senderName ?? null,
    sender_photo_url: fields.senderPhotoUrl ?? null,
    body: fields.body ?? null,
    image_url: fields.imageUrl ?? null,
    created_at: new Date().toISOString(),
    deleted_at: null,
    pending: true,
  };
  queryClient.setQueryData<SangaMessage[]>(
    sangaKeys.messages(sangaId),
    (existing) => (existing ? [...existing, optimistic] : [optimistic]),
  );
}

/** Drops the placeholder in the same write that adds the real row, so the two
 * are never on screen together. */
function replaceOptimisticSangaMessage(
  queryClient: QueryClient,
  row: SangaMessageRow,
  sender: { name?: string | null; photoUrl?: string | null },
  localId: string | undefined,
) {
  queryClient.setQueryData<SangaMessage[]>(
    sangaKeys.messages(row.sanga_id),
    (existing) => {
      const resolved = resolveSender(
        queryClient,
        row.sanga_id,
        row.sender_id,
        existing,
      );
      const without = (existing ?? []).filter(
        (message) => message.id !== localId && message.id !== row.id,
      );
      return sortThread([
        ...without,
        toSangaMessage(row, {
          name: sender.name ?? resolved.name,
          photoUrl: sender.photoUrl ?? resolved.photoUrl,
        }),
      ]);
    },
  );
}

/** A message that never left must not linger looking sent. */
function dropOptimisticSangaMessage(
  queryClient: QueryClient,
  sangaId: string,
  localId: string | undefined,
) {
  if (!localId) return;
  queryClient.setQueryData<SangaMessage[]>(
    sangaKeys.messages(sangaId),
    (existing) => (existing ?? []).filter((message) => message.id !== localId),
  );
}

export type SendSangaMessageVariables = SendSangaMessageInput & {
  /** These four paint the pending bubble; none of them reaches the server. */
  localId?: string;
  senderId?: string;
  senderName?: string | null;
  senderPhotoUrl?: string | null;
};

/**
 * Posts optimistically: the bubble appears the instant Send is tapped, marked
 * pending, and is replaced by the server's row when it lands.
 *
 * The name has to come from the caller because send_sanga_message returns the
 * bare row — in a group the bubble is nobody's until it is somebody's.
 */
export function useSendSangaMessage() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({
      localId: _localId,
      senderId: _senderId,
      senderName: _senderName,
      senderPhotoUrl: _senderPhotoUrl,
      ...input
    }: SendSangaMessageVariables) => sendSangaMessage(input),

    onMutate: (input) => {
      const localId = input.localId;
      if (!localId || !input.senderId) return { localId: undefined };

      // Synchronous, and before cancelQueries — see useRequestToJoinSanga.
      insertOptimisticSangaMessage(queryClient, input.sangaId, {
        localId,
        senderId: input.senderId,
        senderName: input.senderName,
        senderPhotoUrl: input.senderPhotoUrl,
        body: input.body,
        imageUrl: input.imageUrl,
      });
      void queryClient.cancelQueries({
        queryKey: sangaKeys.messages(input.sangaId),
      });

      return { localId };
    },

    onSuccess: (row, input, context) => {
      replaceOptimisticSangaMessage(
        queryClient,
        row,
        { name: input.senderName, photoUrl: input.senderPhotoUrl },
        context?.localId,
      );
    },

    onError: (_error, input, context) => {
      dropOptimisticSangaMessage(queryClient, input.sangaId, context?.localId);
    },
  });
}

export type SendSangaMessageImageInput = {
  sangaId: string;
  image: PickedMessageImage;
  body?: string | null;
  /** As above: only for the pending bubble. */
  localId?: string;
  senderId?: string;
  senderName?: string | null;
  senderPhotoUrl?: string | null;
};

/**
 * The picture goes to storage first: send_sanga_message only records a URL, so
 * a failed upload must never become a message pointing at nothing.
 *
 * The wait is the whole upload, not a single round trip, so the optimistic
 * bubble matters more here than it does for text — it is the only thing that
 * says the picture is on its way.
 */
export function useSendSangaMessageImage(userId: string | null) {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async ({
      sangaId,
      image,
      body,
    }: SendSangaMessageImageInput) => {
      if (!userId) throw new Error("Sign in to send a picture.");
      const imageUrl = await uploadMessageImage(userId, image);
      return sendSangaMessage({ sangaId, body: body ?? null, imageUrl });
    },

    onMutate: (input) => {
      const localId = input.localId;
      if (!localId || !input.senderId) return { localId: undefined };

      // Synchronous, and before cancelQueries — see useRequestToJoinSanga.
      insertOptimisticSangaMessage(queryClient, input.sangaId, {
        localId,
        senderId: input.senderId,
        senderName: input.senderName,
        senderPhotoUrl: input.senderPhotoUrl,
        body: input.body,
        // The file still on the phone stands in until the uploaded copy has a
        // URL, so the picture is on screen before it has left the device.
        imageUrl: input.image.uri,
      });
      void queryClient.cancelQueries({
        queryKey: sangaKeys.messages(input.sangaId),
      });

      return { localId };
    },

    onSuccess: (row, input, context) => {
      replaceOptimisticSangaMessage(
        queryClient,
        row,
        { name: input.senderName, photoUrl: input.senderPhotoUrl },
        context?.localId,
      );
    },

    onError: (_error, input, context) => {
      dropOptimisticSangaMessage(queryClient, input.sangaId, context?.localId);
    },
  });
}

/**
 * Taking a message down. The row survives with `deleted_at` set and nothing in
 * it, which is what keeps everyone's thread the same shape.
 */
export function useDeleteSangaMessage() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({ messageId }: { messageId: string }) =>
      deleteSangaMessage(messageId),
    // The row carries its sanga, so the caller does not have to pass it.
    onSuccess: (row) => {
      upsertCachedSangaMessage(queryClient, row.sanga_id, row);
    },
  });
}

/**
 * Moves the viewer's watermark to now, and takes the badge off the sanga's row
 * in the same tick.
 *
 * Only a member may mark a sanga read, so callers gate this on membership: an
 * observer opening a thread through app.view_all has no watermark to move and
 * the server refuses them.
 */
export function useMarkSangaRead() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (sangaId: string) => markSangaRead(sangaId),

    // Optimistic and not rolled back on failure. A badge that reappeared a
    // second after the devotee opened the sanga would read as a message that
    // arrived while they were looking at it; the next list refetch carries the
    // server's answer either way.
    onMutate: (sangaId) => {
      patchSanga(queryClient, sangaId, {
        list: (row) => ({ ...row, unread_count: 0 }),
        mine: (row) => ({ ...row, unread_count: 0 }),
      });
    },

    // Only refresh when the mark actually cleared something. The chat screen
    // calls this on focus and on every arriving message, and an unconditional
    // invalidate would be two list RPCs per message received.
    onSuccess: (cleared) => {
      if (cleared > 0) invalidateLists(queryClient);
    },
  });
}

/**
 * Live updates for one open thread. Inserts append; updates cover the one
 * thing that changes after the fact, a deletion.
 *
 * Members receive these because they are in the sanga, and a President reading
 * over the top receives them through app.view_all — the same rule the select
 * policy applies, so no extra case is needed here.
 */
export function useSangaMessagesRealtime(sangaId: string | null) {
  const queryClient = useQueryClient();
  const suffix = useChannelSuffix();

  useEffect(() => {
    if (!sangaId) return;
    const filter = `sanga_id=eq.${sangaId}`;
    const apply = (row: SangaMessageRow) => {
      // A devotee who has not spoken in this thread and is not on the cached
      // roll cannot be named from here — someone added a minute ago, most
      // often. One refetch settles it rather than leaving a nameless bubble.
      if (!upsertCachedSangaMessage(queryClient, sangaId, row)) {
        void queryClient.invalidateQueries({
          queryKey: sangaKeys.messages(sangaId),
        });
      }
    };

    const channel = getSupabaseClient()
      .channel(`sanga-messages-live-${sangaId}-${suffix}`)
      .on<SangaMessageRow>(
        "postgres_changes",
        { event: "INSERT", schema: "public", table: "sanga_messages", filter },
        (payload) => apply(payload.new),
      )
      .on<SangaMessageRow>(
        "postgres_changes",
        { event: "UPDATE", schema: "public", table: "sanga_messages", filter },
        (payload) => apply(payload.new),
      )
      .subscribe();

    return () => {
      void getSupabaseClient().removeChannel(channel);
    };
  }, [queryClient, sangaId]);
}

/**
 * Live updates for the sanga lists.
 *
 * Four tables move a browse row. Three went onto the publication with replica
 * identity full in 202608040043_sanga_powers.sql: `sangas` (one approved,
 * renamed, retired or deleted), `sanga_members` (the count, and whether the
 * viewer is inside) and `sanga_join_requests` (whether the viewer has an ask
 * outstanding). Before this they only changed when the devotee left the screen
 * and came back.
 *
 * `sanga_messages` is the fourth, and it is here for the unread badge: a count
 * that only moved on the next visit to the tab would be a count nobody trusts.
 * Unfiltered, because the badge that matters is on the sanga the devotee is
 * NOT looking at — row level security already limits this to circles they are
 * in, which is exactly the set that can carry a badge for them.
 *
 * Invalidation rather than patching, deliberately. What arrives here is a raw
 * table row: no member count, no admin's name, no answer to "is that one
 * mine". The honest response is to ask the list function again — it is one
 * RPC over a short list. Patching is worth doing in the mutations above, where
 * the client already knows what it just did.
 */
export function useSangaListRealtime(enabled = true) {
  const queryClient = useQueryClient();
  const suffix = useChannelSuffix();

  useEffect(() => {
    if (!enabled) return;
    const refreshLists = () => invalidateLists(queryClient);
    const refreshSangas = () => {
      refreshLists();
      // A sangas row changing is the one thing that can empty or fill the
      // President's queue.
      void queryClient.invalidateQueries({ queryKey: sangaKeys.pending() });
    };

    const channel = getSupabaseClient()
      .channel(`sanga-lists-live-${suffix}`)
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "sangas" },
        refreshSangas,
      )
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "sanga_members" },
        refreshLists,
      )
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "sanga_join_requests" },
        refreshLists,
      )
      // Updates as well as inserts: the only thing that ever updates a message
      // is it being taken down, and a message taken down stops counting.
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "sanga_messages" },
        refreshLists,
      )
      .subscribe();

    return () => {
      void getSupabaseClient().removeChannel(channel);
    };
  }, [enabled, queryClient]);
}

/**
 * Live updates for one sanga's roll and its inbox, so the info page and the
 * chat header move while they are open: somebody approved on another phone
 * appears on the roll, and an ask answered from the roll leaves the inbox.
 *
 * The filters are what make this cheap — one sanga's rows and nobody else's —
 * and they are also why the migration insists on replica identity full: a
 * filtered subscription on a table with row level security cannot evaluate its
 * filter from a primary key alone.
 */
export function useSangaRealtime(sangaId: string | null) {
  const queryClient = useQueryClient();
  const suffix = useChannelSuffix();

  useEffect(() => {
    if (!sangaId) return;
    const filter = `sanga_id=eq.${sangaId}`;

    const channel = getSupabaseClient()
      .channel(`sanga-live-${sangaId}-${suffix}`)
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "sanga_members", filter },
        () => {
          void queryClient.invalidateQueries({
            queryKey: sangaKeys.members(sangaId),
          });
          // Somebody joining or leaving moves the count on every list.
          invalidateLists(queryClient);
        },
      )
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "sanga_join_requests", filter },
        () => {
          void queryClient.invalidateQueries({
            queryKey: sangaKeys.joinRequests(sangaId),
          });
          // An answered ask is the viewer's own request_status, if it was
          // theirs.
          invalidateLists(queryClient);
        },
      )
      .on(
        "postgres_changes",
        {
          event: "*",
          schema: "public",
          table: "sangas",
          filter: `id=eq.${sangaId}`,
        },
        () => invalidateLists(queryClient),
      )
      .subscribe();

    return () => {
      void getSupabaseClient().removeChannel(channel);
    };
  }, [queryClient, sangaId]);
}

/** At most one broadcast this often while a devotee keeps typing. */
const TYPING_BROADCAST_INTERVAL = 2_000;
/** How long "typing…" survives without a further signal. */
const TYPING_EXPIRY = 4_000;

/**
 * Who is typing in this sanga, by name rather than as a yes or no: several
 * devotees can be mid-sentence at once, and "someone is typing" in a circle of
 * twenty says nothing worth saying.
 *
 * Broadcast rather than a table, like the one-to-one indicator: it is true for
 * a couple of seconds and worth nothing afterwards, so writing it to Postgres
 * would mean a row per keystroke and a permanent record of hesitation. Nothing
 * reliably announces that typing stopped — a devotee can lock the phone
 * mid-sentence — so each name expires on its own.
 */
export function useSangaTypingIndicator(
  sangaId: string | null,
  selfId: string | null,
  selfName: string | null,
) {
  const [typists, setTypists] = useState<SangaTypist[]>([]);
  const channelRef = useRef<RealtimeChannel | null>(null);
  const expiryTimers = useRef(new Map<string, ReturnType<typeof setTimeout>>());
  const lastBroadcastAt = useRef(0);

  // Held in a ref so renaming the viewer does not tear down the subscription,
  // and so the goodbye broadcast in the cleanup sends the current name.
  const selfNameRef = useRef(selfName);
  useEffect(() => {
    selfNameRef.current = selfName;
  }, [selfName]);

  useEffect(() => {
    if (!sangaId || !selfId) return;
    const timers = expiryTimers.current;

    const forget = (devoteeId: string) => {
      const timer = timers.get(devoteeId);
      if (timer) clearTimeout(timer);
      timers.delete(devoteeId);
      setTypists((current) =>
        current.filter((typist) => typist.id !== devoteeId),
      );
    };

    const channel = getSupabaseClient()
      .channel(`sanga-typing-${sangaId}`, {
        config: { broadcast: { self: false } },
      })
      .on<SangaTypingSignal>(
        "broadcast",
        { event: "typing" },
        ({ payload }) => {
          // `self: false` is not honoured before the socket has joined, so the
          // viewer's own signal has to be dropped here too.
          if (!payload?.from || payload.from === selfId) return;
          if (!payload.typing) {
            forget(payload.from);
            return;
          }

          const running = timers.get(payload.from);
          if (running) clearTimeout(running);
          timers.set(
            payload.from,
            setTimeout(() => forget(payload.from), TYPING_EXPIRY),
          );

          setTypists((current) => {
            const known = current.find((typist) => typist.id === payload.from);
            // Same devotee, same name: return the array untouched so a signal
            // every two seconds does not rerender the thread.
            if (known && known.name === payload.name) return current;
            if (known) {
              return current.map((typist) =>
                typist.id === payload.from
                  ? { ...typist, name: payload.name }
                  : typist,
              );
            }
            return [...current, { id: payload.from, name: payload.name }];
          });
        },
      )
      .subscribe();
    channelRef.current = channel;

    return () => {
      for (const timer of timers.values()) clearTimeout(timer);
      timers.clear();
      // Leaving mid-sentence should not leave a name sitting on everybody
      // else's screen until it expires. Best effort — the socket may already
      // be gone — which is why the expiry exists at all.
      void channel.send({
        type: "broadcast",
        event: "typing",
        payload: {
          typing: false,
          from: selfId,
          name: selfNameRef.current,
        } satisfies SangaTypingSignal,
      });
      channelRef.current = null;
      setTypists([]);
      void getSupabaseClient().removeChannel(channel);
    };
  }, [sangaId, selfId]);

  const broadcast = useCallback(
    (typing: boolean) => {
      const channel = channelRef.current;
      if (!channel || !selfId) return;
      void channel.send({
        type: "broadcast",
        event: "typing",
        payload: {
          typing,
          from: selfId,
          name: selfNameRef.current,
        } satisfies SangaTypingSignal,
      });
    },
    [selfId],
  );

  /** Called on every keystroke; throttled so it is not one send per character. */
  const notifyTyping = useCallback(() => {
    const now = Date.now();
    if (now - lastBroadcastAt.current < TYPING_BROADCAST_INTERVAL) return;
    lastBroadcastAt.current = now;
    broadcast(true);
  }, [broadcast]);

  /** Sending or clearing the composer ends it immediately rather than waiting. */
  const notifyStoppedTyping = useCallback(() => {
    lastBroadcastAt.current = 0;
    broadcast(false);
  }, [broadcast]);

  return { typists, notifyTyping, notifyStoppedTyping };
}

/**
 * "Gopal is typing…", then two names, then a count. Past two the names stop
 * being information and start being a wall of text over the composer.
 */
export function sangaTypingLabel(typists: SangaTypist[]): string | null {
  const names = typists.map((typist) => typist.name?.trim() || "Someone");
  if (names.length === 0) return null;
  if (names.length === 1) return `${names[0]} is typing…`;
  if (names.length === 2) return `${names[0]} and ${names[1]} are typing…`;
  return `${names.length} devotees are typing…`;
}

/**
 * What the viewer may do in one sanga.
 *
 * 202608040043_sanga_powers.sql admitted a second caller to five of the write
 * RPCs: a holder of app.view_all, the President or a Tech Admin. They may post,
 * take any message down, add and remove members, answer requests to join, and
 * delete the sanga — in a circle they have not joined and are not enrolled in
 * by doing any of it. So the powers below are read off the permission as
 * readily as off membership, and `isMember` / `isAdmin` stay false for them.
 *
 * Two things are not theirs. Handing the sanga to a successor is a judgement
 * about the people in the circle and stays with the devotee running it; and
 * there is nothing for them to leave.
 */
export function sangaViewerCapabilities(input: {
  role: AccessRole;
  isMember: boolean;
  isAdmin: boolean;
}): SangaViewerCapabilities {
  const overseesApp = hasAccessPermission(input.role, "app.view_all");
  const mayAct = input.isAdmin || overseesApp;
  return {
    isMember: input.isMember,
    isAdmin: input.isAdmin,
    overseesApp,
    canPost: input.isMember || overseesApp,
    canManageMembers: mayAct,
    canDeleteAnyMessage: mayAct,
    canDeleteSanga: mayAct,
    canTransferAdmin: input.isAdmin,
    canLeave: input.isMember,
  };
}

/**
 * Where the viewer stands in one sanga, and what that lets them do.
 *
 * Shared by the join page, the thread and the info page so that a header, a
 * composer and a roll can never disagree about whether somebody is inside.
 */
export function useSangaViewer(
  sangaId: string,
  /**
   * The join page turns the roll off. list_sanga_members answers anybody for
   * an approved sanga, so fetching it there would be a round trip spent on
   * names that page is not allowed to draw.
   */
  options: { withRoll?: boolean } = {},
) {
  const withRoll = options.withRoll ?? true;
  const activeUserId = usePrototypeSession((state) => state.activeUserId);
  const previewRole = usePrototypeSession((state) => state.previewRole);
  const profile = useCurrentAccessProfile(activeUserId);
  // The same key the browse list uses, so arriving from it costs nothing.
  const sangas = useSangas();
  const members = useSangaMembers(withRoll ? sangaId : null);

  const actualRole = profile.data?.role ?? "devotee";
  const role = __DEV__ && previewRole ? previewRole : actualRole;

  const roll = members.data;
  const self = roll?.find((member) => member.id === activeUserId) ?? null;
  const summary = sangas.data?.find((row) => row.id === sangaId) ?? null;
  // The roll is the authority once it has arrived. Until then the summary the
  // list screen already cached carries the screen, so a member does not watch
  // the composer appear a beat late.
  const isMember = roll ? Boolean(self) : Boolean(summary?.is_member);
  const isAdmin = roll ? self?.role === "admin" : Boolean(summary?.is_admin);

  const capabilities = useMemo(
    () => sangaViewerCapabilities({ role, isMember, isAdmin }),
    [isAdmin, isMember, role],
  );

  return {
    activeUserId,
    capabilities,
    members,
    sangas,
    summary,
    selfName: profile.data?.name ?? null,
    selfPhotoUrl: profile.data?.photo_url ?? null,
    /** Null while nothing yet knows it, so no screen prints "0 members". */
    memberCount: summary?.member_count ?? roll?.length ?? null,
  };
}

/**
 * The refusal the roll can see coming: a sanga must always have somebody
 * responsible for it, so remove_sanga_member turns down its sole admin — for
 * the President as readily as for the admin themselves.
 *
 * Answered here rather than left to the server so the devotee is told before
 * they tap and told what to do instead, which is what the RPC's own message
 * says: hand the sanga on, or delete it.
 */
export function soleAdminOf(
  roll: readonly SangaMember[],
  member: SangaMember,
): boolean {
  if (member.role !== "admin") return false;
  return roll.filter((row) => row.role === "admin").length <= 1;
}

/** Case-insensitive, trimmed, matches anywhere in the name. */
export function matchesSangaSearch(sanga: { name: string }, search: string) {
  const query = search.trim().toLocaleLowerCase();
  if (!query) return true;
  return sanga.name.toLocaleLowerCase().includes(query);
}
