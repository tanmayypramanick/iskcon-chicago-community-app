import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import {
  createCarePost,
  deleteCarePost,
  deleteCareReply,
  fetchCarePosts,
  fetchCareReplies,
  pickMessageImage,
  replyToCarePost,
  uploadMessageImage,
} from "./api";
import type { PickedMessageImage } from "./types";

export { pickMessageImage };

export const careKeys = {
  all: ["care"] as const,
  posts: () => ["care", "posts"] as const,
  replies: (postId: string | null) => ["care", "replies", postId] as const,
};

export function useCarePosts(enabled = true) {
  return useQuery({
    queryKey: careKeys.posts(),
    queryFn: fetchCarePosts,
    enabled,
    // The board is deliberately unnotified, so a devotee only learns that
    // somebody else asked for help by looking. Keep what they are looking at
    // reasonably current without turning it into a chat.
    refetchInterval: 60_000,
  });
}

export function useCareReplies(postId: string | null) {
  return useQuery({
    queryKey: careKeys.replies(postId),
    queryFn: () => fetchCareReplies(postId!),
    enabled: Boolean(postId),
    refetchInterval: postId ? 30_000 : false,
  });
}

/**
 * The picture goes to storage first: create_care_post only records a URL, and
 * it rejects any URL that did not come out of the app's own bucket, so a
 * failed upload must never become a post pointing at nothing.
 */
export function useCreateCarePost(userId: string | null) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async ({
      title,
      body,
      image,
    }: {
      title: string;
      body: string;
      image?: PickedMessageImage | null;
    }) => {
      let imageUrl: string | null = null;
      if (image) {
        if (!userId) throw new Error("Sign in to add a photo.");
        imageUrl = await uploadMessageImage(userId, image);
      }
      return createCarePost({ title, body, imageUrl });
    },
    onSuccess: () =>
      queryClient.invalidateQueries({ queryKey: careKeys.posts() }),
  });
}

/** The board's reply count lives on the post row, so both lists refresh. */
export function useReplyToCarePost() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ postId, body }: { postId: string; body: string }) =>
      replyToCarePost(postId, body),
    onSuccess: async (_row, { postId }) => {
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: careKeys.replies(postId) }),
        queryClient.invalidateQueries({ queryKey: careKeys.posts() }),
      ]);
    },
  });
}

export function useDeleteCarePost() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (postId: string) => deleteCarePost(postId),
    onSuccess: (_row, postId) => {
      queryClient.removeQueries({ queryKey: careKeys.replies(postId) });
      void queryClient.invalidateQueries({ queryKey: careKeys.posts() });
    },
  });
}

export function useDeleteCareReply() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ replyId }: { replyId: string; postId: string }) =>
      deleteCareReply(replyId),
    onSuccess: async (_row, { postId }) => {
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: careKeys.replies(postId) }),
        queryClient.invalidateQueries({ queryKey: careKeys.posts() }),
      ]);
    },
  });
}
