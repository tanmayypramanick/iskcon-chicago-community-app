import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import { hasAccessPermission, type AccessRole } from "../access/model";
import {
  deleteDailyDarshan,
  fetchDailyDarshan,
  fetchDarshanDeities,
  fetchLatestDailyDarshan,
  pickDarshanImages,
  publishDailyDarshan,
} from "./api";
import {
  toPublishImages,
  uploadDarshanDrafts,
  uploadFailureMessage,
} from "./upload";
import type {
  DailyDarshan,
  DarshanDraftImage,
  PublishDailyDarshanInput,
} from "./types";

/** Same picker as a chat picture: same bucket, same limits, same rebuild
 * warning on a binary built before the dependency existed. */
export { pickDarshanImages };

export const dailyDarshanKeys = {
  all: ["daily-darshan"] as const,
  list: () => ["daily-darshan", "list"] as const,
  latest: () => ["daily-darshan", "latest"] as const,
  deities: () => ["daily-darshan", "deities"] as const,
};

/**
 * Whether to offer the composer at all.
 *
 * The temple named three roles — Community Heads, Tech Admin, President — and
 * `services.manage_recurring` is already exactly those three. Registering a
 * separate client-side key would let the app's answer and the server's drift
 * apart, which is how a devotee ends up looking at a button that refuses them.
 */
export function canPostDailyDarshan(role: AccessRole) {
  return hasAccessPermission(role, "services.manage_recurring");
}

export function useDailyDarshan(enabled = true) {
  return useQuery({
    queryKey: dailyDarshanKeys.list(),
    queryFn: () => fetchDailyDarshan(),
    enabled,
  });
}

/**
 * The Deities to choose between. Held long, because a catalogue changes when
 * the temple installs a Deity and not otherwise, and a picker that refetches on
 * every composer open makes the chips arrive after the photograph.
 */
export function useDarshanDeities(enabled = true) {
  return useQuery({
    queryKey: dailyDarshanKeys.deities(),
    queryFn: fetchDarshanDeities,
    enabled,
    staleTime: 30 * 60_000,
  });
}

/** The single day behind the Home hero. Cheaper than the whole gallery. */
export function useLatestDailyDarshan(enabled = true) {
  return useQuery({
    queryKey: dailyDarshanKeys.latest(),
    queryFn: fetchLatestDailyDarshan,
    enabled,
  });
}

export type PublishDailyDarshanVariables = Omit<
  PublishDailyDarshanInput,
  "images"
> & {
  /** Still on the phone; uploaded by the mutation, not by the caller. */
  images: DarshanDraftImage[];
  /** Called as each photograph's own upload begins, finishes or fails, so the
   * composer can show which of the five is moving. */
  onImageState: (id: string, patch: Partial<DarshanDraftImage>) => void;
};

/**
 * Five photographs, then one row.
 *
 * The queue itself lives in ./upload — this is only the part that has to be a
 * mutation. Nothing is published while any photograph is still missing: the row
 * records URLs, and a darshan pointing at a picture that never arrived is worse
 * than no darshan at all.
 */
export function usePublishDailyDarshan(userId: string | null) {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async ({
      images,
      onImageState,
      ...input
    }: PublishDailyDarshanVariables) => {
      if (!userId) throw new Error("Sign in to post darshan.");

      const { urls, failures } = await uploadDarshanDrafts(
        userId,
        images,
        onImageState,
      );
      if (failures > 0) throw new Error(uploadFailureMessage(failures));

      return publishDailyDarshan({
        ...input,
        images: toPublishImages(images, urls),
      });
    },

    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: dailyDarshanKeys.all });
    },
  });
}

/**
 * Taking a day down. The day goes before the request does — it is already gone
 * as far as the temple is concerned, and a card that sits there through a round
 * trip reads as a tap that missed. A refusal puts it back.
 */
export function useDeleteDailyDarshan() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (id: string) => deleteDailyDarshan(id),

    onMutate: (id) => {
      const previous = queryClient.getQueryData<DailyDarshan[]>(
        dailyDarshanKeys.list(),
      );

      // Written synchronously, before cancelQueries: awaiting cancelQueries
      // would queue this write behind whatever is already on the wire, which is
      // the exact delay the optimistic update exists to remove.
      queryClient.setQueryData<DailyDarshan[]>(
        dailyDarshanKeys.list(),
        (existing) => existing?.filter((darshan) => darshan.id !== id),
      );
      void queryClient.cancelQueries({ queryKey: dailyDarshanKeys.list() });

      return previous;
    },

    onError: (_error, _id, previous) => {
      if (previous) {
        queryClient.setQueryData(dailyDarshanKeys.list(), previous);
      }
    },

    onSettled: () => {
      void queryClient.invalidateQueries({ queryKey: dailyDarshanKeys.all });
    },
  });
}
