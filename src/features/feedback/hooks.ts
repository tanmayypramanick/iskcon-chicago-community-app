import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import {
  deleteFeedback,
  fetchAllFeedback,
  fetchMyFeedback,
  reviewFeedback,
  submitFeedback,
} from "./api";
import type { FeedbackCategory } from "./types";

export const feedbackKeys = {
  all: ["feedback"] as const,
  mine: (userId: string | null) => ["feedback", "mine", userId] as const,
  everyone: () => ["feedback", "all"] as const,
};

export function useMyFeedback(userId: string | null) {
  return useQuery({
    queryKey: feedbackKeys.mine(userId),
    queryFn: fetchMyFeedback,
    enabled: Boolean(userId),
  });
}

/**
 * The President's and Tech Admin's queue. `enabled` mirrors the client-side
 * permission check so an ordinary devotee's phone does not ask a question it
 * already knows the answer to; the function would return nothing anyway.
 */
export function useAllFeedback(enabled: boolean) {
  return useQuery({
    queryKey: feedbackKeys.everyone(),
    queryFn: fetchAllFeedback,
    enabled,
    // A queue two people share; the other one may have worked through it.
    refetchInterval: 60_000,
  });
}

export function useSubmitFeedback(userId: string | null) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({
      category,
      body,
    }: {
      category: FeedbackCategory;
      body: string;
    }) => submitFeedback(category, body),
    onSuccess: async () => {
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: feedbackKeys.mine(userId) }),
        queryClient.invalidateQueries({ queryKey: feedbackKeys.everyone() }),
      ]);
    },
  });
}

/**
 * Taking a note back off the list. Both faces of the screen are refreshed: the
 * devotee who wrote it and the reviewer reading it are looking at the same row
 * through two different functions.
 */
export function useDeleteFeedback(userId: string | null) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (feedbackId: string) => deleteFeedback(feedbackId),
    onSuccess: async () => {
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: feedbackKeys.mine(userId) }),
        queryClient.invalidateQueries({ queryKey: feedbackKeys.everyone() }),
      ]);
    },
  });
}

/**
 * Reviewing also refreshes the devotee's own list: a reviewer looking at their
 * own feedback in the other tab must not be left reading a stale "waiting".
 */
export function useReviewFeedback(userId: string | null) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({
      feedbackId,
      reply,
    }: {
      feedbackId: string;
      reply?: string | null;
    }) => reviewFeedback(feedbackId, reply),
    onSuccess: async () => {
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: feedbackKeys.everyone() }),
        queryClient.invalidateQueries({ queryKey: feedbackKeys.mine(userId) }),
      ]);
    },
  });
}
