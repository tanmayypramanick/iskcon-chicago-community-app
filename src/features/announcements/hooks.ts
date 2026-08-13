import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import { hasAccessPermission, type AccessRole } from "../access/model";
import {
  addAnnouncementComment,
  createAnnouncement,
  deleteAnnouncement,
  deleteAnnouncementComment,
  fetchAnnouncementComments,
  fetchAnnouncementLikes,
  fetchAnnouncements,
  pickMessageImage,
  toggleAnnouncementLike,
  uploadMessageImage,
} from "./api";
import type {
  AddAnnouncementCommentInput,
  Announcement,
  AnnouncementComment,
  CreateAnnouncementInput,
  PickedMessageImage,
} from "./types";

/** Same picker as a chat picture: same bucket, same limits, same rebuild
 * warning on a binary built before the dependency existed. */
export { pickMessageImage };

export const announcementKeys = {
  all: ["announcements"] as const,
  list: () => ["announcements", "list"] as const,
  likes: (announcementId: string) =>
    ["announcements", "likes", announcementId] as const,
  comments: (announcementId: string) =>
    ["announcements", "comments", announcementId] as const,
};

/**
 * Whether to offer the "Post an announcement" button.
 *
 * The migration gates posting on `may_post_announcements()`, which is
 * `has_permission('services.manage_recurring')` and nothing else — the same
 * three roles the app already recognises here. Registering a separate
 * client-side key would let the two answers drift apart.
 */
export function canPostAnnouncements(role: AccessRole) {
  return hasAccessPermission(role, "services.manage_recurring");
}

export function useAnnouncements(enabled = true) {
  return useQuery({
    queryKey: announcementKeys.list(),
    queryFn: fetchAnnouncements,
    enabled,
  });
}

export type CreateAnnouncementVariables = Omit<
  CreateAnnouncementInput,
  "imageUrl"
> & {
  /** Still on the phone; uploaded by the mutation, not by the caller. */
  image?: PickedMessageImage | null;
};

/**
 * The photo goes to storage first: create_announcement only records a URL, so
 * a failed upload must never become a notice pointing at nothing.
 */
export function useCreateAnnouncement(userId: string | null) {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async ({ image, ...input }: CreateAnnouncementVariables) => {
      let imageUrl: string | null = null;
      if (image) {
        if (!userId) throw new Error("Sign in to add a photo.");
        imageUrl = await uploadMessageImage(userId, image);
      }
      return createAnnouncement({ ...input, imageUrl });
    },
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: announcementKeys.list() });
    },
  });
}

/**
 * Taking one down. The card goes before the request does — the row is already
 * gone as far as the temple is concerned, and a notice that sits there through
 * a round trip reads as a tap that missed. A refusal puts it back.
 */
export function useDeleteAnnouncement() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (announcementId: string) => deleteAnnouncement(announcementId),

    onMutate: (announcementId) => {
      const previous = queryClient.getQueryData<Announcement[]>(
        announcementKeys.list(),
      );

      // Written synchronously, before cancelQueries: awaiting cancelQueries
      // would queue this write behind whatever is already on the wire, which
      // is the exact delay the optimistic update exists to remove.
      queryClient.setQueryData<Announcement[]>(
        announcementKeys.list(),
        (existing) =>
          existing?.filter(
            (announcement) => announcement.id !== announcementId,
          ),
      );
      void queryClient.cancelQueries({ queryKey: announcementKeys.list() });

      return previous;
    },

    onError: (_error, _announcementId, previous) => {
      if (previous) {
        queryClient.setQueryData(announcementKeys.list(), previous);
      }
    },

    onSettled: () => {
      void queryClient.invalidateQueries({ queryKey: announcementKeys.list() });
    },
  });
}

export function useAnnouncementLikes(announcementId: string) {
  return useQuery({
    queryKey: announcementKeys.likes(announcementId),
    queryFn: () => fetchAnnouncementLikes(announcementId),
  });
}

export function useAnnouncementComments(announcementId: string) {
  return useQuery({
    queryKey: announcementKeys.comments(announcementId),
    queryFn: () => fetchAnnouncementComments(announcementId),
    // A thread is read while other devotees are writing on it, but it is not a
    // chat; often enough to feel alive, rarely enough not to be one.
    refetchInterval: 45_000,
  });
}

/**
 * One card, moved one step. Never called with the state it already holds, so
 * the count only ever moves once per tap, and it will not go below zero — a
 * card loaded before somebody else unliked must not render "-1".
 */
function withLike(announcement: Announcement, liked: boolean): Announcement {
  if (announcement.liked_by_me === liked) return announcement;
  return {
    ...announcement,
    liked_by_me: liked,
    like_count: Math.max(0, announcement.like_count + (liked ? 1 : -1)),
  };
}

function mapAnnouncement(
  queryClient: ReturnType<typeof useQueryClient>,
  announcementId: string,
  change: (announcement: Announcement) => Announcement,
) {
  queryClient.setQueryData<Announcement[]>(announcementKeys.list(), (existing) =>
    existing?.map((announcement) =>
      announcement.id === announcementId ? change(announcement) : announcement,
    ),
  );
}

/**
 * The heart fills under the thumb, or it is not worth having.
 *
 * Nothing is invalidated on success: refetching the whole board on every tap is
 * what would make the heart lag, and the server's own answer is written back
 * here instead.
 */
export function useToggleAnnouncementLike() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (announcementId: string) =>
      toggleAnnouncementLike(announcementId),

    onMutate: (announcementId) => {
      const before = queryClient
        .getQueryData<Announcement[]>(announcementKeys.list())
        ?.find((announcement) => announcement.id === announcementId);

      // Written synchronously, before cancelQueries: awaiting cancelQueries
      // would queue this write behind whatever is already on the wire, which is
      // the exact delay the optimistic update exists to remove.
      mapAnnouncement(queryClient, announcementId, (announcement) =>
        withLike(announcement, !announcement.liked_by_me),
      );
      void queryClient.cancelQueries({ queryKey: announcementKeys.list() });

      return before?.liked_by_me;
    },

    // A fetch that started before the tap can still land after it, carrying
    // pre-tap counts. cancelQueries is async and cannot be relied on for that,
    // so the server's own answer is written back as the authoritative one.
    onSuccess: (nowLiked, announcementId) => {
      mapAnnouncement(queryClient, announcementId, (announcement) =>
        withLike(announcement, nowLiked),
      );
      void queryClient.invalidateQueries({
        queryKey: announcementKeys.likes(announcementId),
      });
    },

    // Only this card is put back, not the whole board: a snapshot of the list
    // would also undo a like on another card that is still in flight.
    onError: (_error, announcementId, wasLiked) => {
      if (wasLiked === undefined) return;
      mapAnnouncement(queryClient, announcementId, (announcement) =>
        withLike(announcement, wasLiked),
      );
    },
  });
}

/**
 * Where a new row belongs in a thread the server ordered.
 *
 * A comment goes at the foot of the list; a reply goes at the foot of its own
 * parent's replies, not the list's, or it would appear under somebody else's
 * comment until the refetch moved it under the reader's eyes.
 */
function insertInThread(
  rows: AnnouncementComment[],
  row: AnnouncementComment,
): AnnouncementComment[] {
  if (!row.parent_comment_id) return [...rows, row];

  const parentAt = rows.findIndex(
    (existing) => existing.id === row.parent_comment_id,
  );
  if (parentAt < 0) return [...rows, row];

  let after = parentAt + 1;
  while (
    after < rows.length &&
    rows[after].parent_comment_id === row.parent_comment_id
  ) {
    after += 1;
  }
  return [...rows.slice(0, after), row, ...rows.slice(after)];
}

/**
 * The words appear on the thread as they are sent, under the devotee's own name
 * and face, and are taken back off it if the server refuses.
 *
 * `self` is what the optimistic row is signed with; the refetch replaces it
 * with the server's own copy either way.
 */
export function useAddAnnouncementComment(
  userId: string | null,
  self: { name: string; photoUrl: string | null },
) {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (input: AddAnnouncementCommentInput) =>
      addAnnouncementComment(input),

    onMutate: ({ announcementId, body, parentCommentId }) => {
      const key = announcementKeys.comments(announcementId);
      const previousThread = queryClient.getQueryData<AnnouncementComment[]>(key);

      // Synchronous and ahead of cancelQueries, for the reason given on the
      // like above.
      if (userId) {
        const optimistic: AnnouncementComment = {
          id: `pending-${Date.now()}`,
          parent_comment_id: parentCommentId ?? null,
          author_id: userId,
          author_name: self.name,
          author_photo_url: self.photoUrl,
          body,
          created_at: new Date().toISOString(),
          deleted_at: null,
          reply_count: 0,
          // Nothing may be done to a row the server has not acknowledged: its
          // id is ours, not the database's, and no call would find it.
          can_remove: false,
          pending: true,
        };

        queryClient.setQueryData<AnnouncementComment[]>(key, (existing) =>
          insertInThread(
            (existing ?? []).map((row) =>
              row.id === parentCommentId
                ? { ...row, reply_count: row.reply_count + 1 }
                : row,
            ),
            optimistic,
          ),
        );
        mapAnnouncement(queryClient, announcementId, (announcement) => ({
          ...announcement,
          comment_count: announcement.comment_count + 1,
        }));
      }

      void queryClient.cancelQueries({ queryKey: key });

      return { previousThread, counted: Boolean(userId) };
    },

    // The card's count is stepped back rather than restored from a snapshot of
    // the board, which would also undo a like still in flight on another card.
    onError: (_error, { announcementId }, context) => {
      if (context?.previousThread) {
        queryClient.setQueryData(
          announcementKeys.comments(announcementId),
          context.previousThread,
        );
      }
      if (context?.counted) {
        mapAnnouncement(queryClient, announcementId, (announcement) => ({
          ...announcement,
          comment_count: Math.max(0, announcement.comment_count - 1),
        }));
      }
    },

    onSettled: (_row, _error, { announcementId }) => {
      void queryClient.invalidateQueries({
        queryKey: announcementKeys.comments(announcementId),
      });
      void queryClient.invalidateQueries({ queryKey: announcementKeys.list() });
    },
  });
}

/**
 * Taking words down. The row keeps its place and loses its words immediately,
 * because that is what the server is about to do too — removing it from the
 * list instead would orphan the replies underneath for one round trip.
 */
export function useDeleteAnnouncementComment() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({ commentId }: { commentId: string; announcementId: string }) =>
      deleteAnnouncementComment(commentId),

    onMutate: ({ commentId, announcementId }) => {
      const key = announcementKeys.comments(announcementId);
      const previousThread = queryClient.getQueryData<AnnouncementComment[]>(key);
      const removed = previousThread?.find((row) => row.id === commentId);

      queryClient.setQueryData<AnnouncementComment[]>(key, (existing) =>
        existing?.map((row) => {
          if (row.id === commentId) {
            return {
              ...row,
              body: null,
              deleted_at: new Date().toISOString(),
              can_remove: false,
            };
          }
          // A removed reply stops counting towards its parent's "N more
          // replies", which counts live ones only.
          if (removed?.parent_comment_id && row.id === removed.parent_comment_id) {
            return { ...row, reply_count: Math.max(0, row.reply_count - 1) };
          }
          return row;
        }),
      );
      mapAnnouncement(queryClient, announcementId, (announcement) => ({
        ...announcement,
        comment_count: Math.max(0, announcement.comment_count - 1),
      }));
      void queryClient.cancelQueries({ queryKey: key });

      return { previousThread };
    },

    // Stepped back rather than restored from a snapshot of the board, for the
    // reason given on the comment above.
    onError: (_error, { announcementId }, context) => {
      if (context?.previousThread) {
        queryClient.setQueryData(
          announcementKeys.comments(announcementId),
          context.previousThread,
        );
      }
      mapAnnouncement(queryClient, announcementId, (announcement) => ({
        ...announcement,
        comment_count: announcement.comment_count + 1,
      }));
    },

    onSettled: (_row, _error, { announcementId }) => {
      void queryClient.invalidateQueries({
        queryKey: announcementKeys.comments(announcementId),
      });
      void queryClient.invalidateQueries({ queryKey: announcementKeys.list() });
    },
  });
}
