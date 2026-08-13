import { useMutation, useQueryClient } from "@tanstack/react-query";

import {
  pickDevoteePhoto,
  removeDevoteePhoto,
  uploadDevoteePhoto,
  type PickedPhoto,
} from "./photo";

/**
 * Every surface that renders a face reads from either the access profile or
 * the service dashboard, so both are refreshed after a photo changes.
 */
function useRefreshFaces() {
  const queryClient = useQueryClient();
  return () =>
    Promise.all([
      queryClient.invalidateQueries({ queryKey: ["access"] }),
      queryClient.invalidateQueries({ queryKey: ["services"] }),
      queryClient.invalidateQueries({ queryKey: ["presence"] }),
    ]);
}

export function useUpdateDevoteePhoto(userId: string | null) {
  const refreshFaces = useRefreshFaces();

  return useMutation({
    mutationFn: async (source: "library" | "camera") => {
      if (!userId) throw new Error("Sign in to add a profile photo.");
      const picked: PickedPhoto | null = await pickDevoteePhoto(source);
      if (!picked) return null;
      return uploadDevoteePhoto(userId, picked);
    },
    onSuccess: (result) => {
      if (result !== null) void refreshFaces();
    },
  });
}

export function useRemoveDevoteePhoto(userId: string | null) {
  const refreshFaces = useRefreshFaces();

  return useMutation({
    mutationFn: async () => {
      if (!userId) throw new Error("Sign in to change your profile photo.");
      return removeDevoteePhoto(userId);
    },
    onSuccess: () => void refreshFaces(),
  });
}
