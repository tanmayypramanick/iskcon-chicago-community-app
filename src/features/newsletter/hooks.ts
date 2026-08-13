import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import {
  appointNewsletterEditor,
  deleteNewsletter,
  deleteNewsletterSubmission,
  fetchAllNewsletterSubmissions,
  fetchMayManageNewsletter,
  fetchMyNewsletterSubmissions,
  fetchNewsletterEditors,
  fetchNewsletters,
  pickMessageImage,
  pickNewsletterFile,
  postNewsletter,
  reviewNewsletterSubmission,
  revokeNewsletterEditor,
  submitNewsletterStory,
  uploadMessageImage,
  uploadNewsletterFile,
} from "./api";
import type {
  Newsletter,
  PickedMessageImage,
  PickedNewsletterFile,
  PostNewsletterInput,
} from "./types";

export { pickMessageImage, pickNewsletterFile };

export const newsletterKeys = {
  all: ["newsletter"] as const,
  issues: () => ["newsletter", "issues"] as const,
  editors: () => ["newsletter", "editors"] as const,
  /** Every viewer's answer, for the invalidation after an appointment. */
  mayManageAll: () => ["newsletter", "may-manage"] as const,
  mayManage: (userId: string | null) =>
    ["newsletter", "may-manage", userId] as const,
  mySubmissions: (userId: string | null) =>
    ["newsletter", "submissions", "mine", userId] as const,
  allSubmissions: () => ["newsletter", "submissions", "all"] as const,
};

export function useNewsletters() {
  return useQuery({
    queryKey: newsletterKeys.issues(),
    queryFn: fetchNewsletters,
  });
}

/**
 * Whether to offer the posting controls at all. Asked of the server rather
 * than worked out from the viewer's role: an appointed editor may hold no rank
 * whatsoever, and no client-side ladder knows about the appointment.
 */
export function useMayManageNewsletter(userId: string | null) {
  return useQuery({
    queryKey: newsletterKeys.mayManage(userId),
    queryFn: fetchMayManageNewsletter,
    enabled: Boolean(userId),
  });
}

/**
 * Who is on the newsletter team. The server answers with an empty set to
 * anybody who may not manage the newsletter, so `enabled` only spares an
 * ordinary devotee's phone a question it already knows the answer to.
 */
export function useNewsletterEditors(enabled = true) {
  return useQuery({
    queryKey: newsletterKeys.editors(),
    queryFn: fetchNewsletterEditors,
    enabled,
  });
}

export function useMyNewsletterSubmissions(userId: string | null) {
  return useQuery({
    queryKey: newsletterKeys.mySubmissions(userId),
    queryFn: fetchMyNewsletterSubmissions,
    enabled: Boolean(userId),
  });
}

export function useAllNewsletterSubmissions(enabled: boolean) {
  return useQuery({
    queryKey: newsletterKeys.allSubmissions(),
    queryFn: fetchAllNewsletterSubmissions,
    enabled,
    // A queue the whole newsletter team shares; somebody else may have worked
    // through part of it.
    refetchInterval: 60_000,
  });
}

export type PostNewsletterVariables = Omit<
  PostNewsletterInput,
  "fileUrl" | "coverImageUrl"
> & {
  /** Both still on the phone; uploaded by the mutation, not by the caller. */
  file: PickedNewsletterFile;
  cover?: PickedMessageImage | null;
};

/**
 * The file goes to storage first: post_newsletter only records a URL, so a
 * failed upload must never become an issue pointing at nothing.
 */
export function usePostNewsletter(userId: string | null) {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async ({ file, cover, ...input }: PostNewsletterVariables) => {
      if (!userId) throw new Error("Sign in to post the newsletter.");
      const fileUrl = await uploadNewsletterFile(userId, file);
      const coverImageUrl = cover
        ? await uploadMessageImage(userId, cover)
        : null;
      return postNewsletter({ ...input, fileUrl, coverImageUrl });
    },
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: newsletterKeys.issues() });
    },
  });
}

/**
 * Taking an issue down. The card goes before the request does — it is already
 * gone as far as the temple is concerned, and a row that sits there through a
 * round trip reads as a tap that missed. A refusal puts it back.
 */
export function useDeleteNewsletter() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (newsletterId: string) => deleteNewsletter(newsletterId),

    onMutate: (newsletterId) => {
      const previous = queryClient.getQueryData<Newsletter[]>(
        newsletterKeys.issues(),
      );

      // Written synchronously, before cancelQueries: awaiting cancelQueries
      // would queue this write behind whatever is already on the wire, which
      // is the exact delay the optimistic update exists to remove.
      queryClient.setQueryData<Newsletter[]>(
        newsletterKeys.issues(),
        (existing) => existing?.filter((issue) => issue.id !== newsletterId),
      );
      void queryClient.cancelQueries({ queryKey: newsletterKeys.issues() });

      return previous;
    },

    onError: (_error, _newsletterId, previous) => {
      if (previous) {
        queryClient.setQueryData(newsletterKeys.issues(), previous);
      }
    },

    onSettled: () => {
      void queryClient.invalidateQueries({ queryKey: newsletterKeys.issues() });
    },
  });
}

export type SubmitStoryVariables = {
  body: string;
  images: PickedMessageImage[];
  file?: PickedNewsletterFile | null;
};

/**
 * Photos and the document are uploaded in order, before the row is written,
 * for the same reason: the server stores URLs and validates their origin, so
 * anything that fails to upload must stop the submission rather than land in
 * an editor's queue as a broken link.
 */
export function useSubmitNewsletterStory(userId: string | null) {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async ({ body, images, file }: SubmitStoryVariables) => {
      if (!userId) throw new Error("Sign in to send a story request.");
      const imageUrls: string[] = [];
      for (const image of images) {
        imageUrls.push(await uploadMessageImage(userId, image));
      }
      const fileUrl = file ? await uploadNewsletterFile(userId, file) : null;
      return submitNewsletterStory({ body, imageUrls, fileUrl });
    },
    onSuccess: async () => {
      await Promise.all([
        queryClient.invalidateQueries({
          queryKey: newsletterKeys.mySubmissions(userId),
        }),
        queryClient.invalidateQueries({
          queryKey: newsletterKeys.allSubmissions(),
        }),
      ]);
    },
  });
}

/**
 * Reviewing also refreshes the devotee's own list: an editor who has sent in a
 * story of their own must not be left reading a stale "waiting".
 */
export function useReviewNewsletterSubmission(userId: string | null) {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({
      submissionId,
      reply,
    }: {
      submissionId: string;
      reply?: string | null;
    }) => reviewNewsletterSubmission(submissionId, reply),
    onSuccess: async () => {
      await Promise.all([
        queryClient.invalidateQueries({
          queryKey: newsletterKeys.allSubmissions(),
        }),
        queryClient.invalidateQueries({
          queryKey: newsletterKeys.mySubmissions(userId),
        }),
      ]);
    },
  });
}

/**
 * Taking a story back off the list. Both lists are refreshed: the devotee who
 * sent it and the team reading it are looking at the same row through two
 * different functions.
 */
export function useDeleteNewsletterSubmission(userId: string | null) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (submissionId: string) =>
      deleteNewsletterSubmission(submissionId),
    onSuccess: async () => {
      await Promise.all([
        queryClient.invalidateQueries({
          queryKey: newsletterKeys.mySubmissions(userId),
        }),
        queryClient.invalidateQueries({
          queryKey: newsletterKeys.allSubmissions(),
        }),
      ]);
    },
  });
}

export function useAppointNewsletterEditor() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (devoteeId: string) => appointNewsletterEditor(devoteeId),
    onSuccess: async () => {
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: newsletterKeys.editors() }),
        queryClient.invalidateQueries({
          queryKey: newsletterKeys.mayManageAll(),
        }),
      ]);
    },
  });
}

/**
 * Revoking also refreshes the issues and the permission itself: `can_manage`
 * and `can_delete` travel on those rows, and an office holder who has just
 * removed somebody — or themselves — must stop being shown controls the server
 * would now refuse.
 */
export function useRevokeNewsletterEditor() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (devoteeId: string) => revokeNewsletterEditor(devoteeId),
    onSuccess: async () => {
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: newsletterKeys.editors() }),
        queryClient.invalidateQueries({ queryKey: newsletterKeys.issues() }),
        queryClient.invalidateQueries({
          queryKey: newsletterKeys.mayManageAll(),
        }),
      ]);
    },
  });
}
