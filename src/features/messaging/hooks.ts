import type { RealtimeChannel } from "@supabase/supabase-js";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import type { QueryClient } from "@tanstack/react-query";
import { useCallback, useEffect, useRef, useState } from "react";

import { getSupabaseClient } from "../../lib/supabase";
import {
  deleteMessage,
  fetchConversations,
  fetchMessages,
  hideMessageForMe,
  markConversationDelivered,
  markConversationRead,
  openConversation,
  pickMessageImage,
  sendMessage,
  uploadMessageImage,
} from "./api";
import type {
  MessageRow,
  PickedMessageImage,
  SendMessageInput,
  TypingSignal,
} from "./types";

export const messagingKeys = {
  all: ["messaging"] as const,
  conversations: () => ["messaging", "conversations"] as const,
  messages: (conversationId: string | null) =>
    ["messaging", "messages", conversationId] as const,
};

export function useConversations(enabled = true) {
  return useQuery({
    queryKey: messagingKeys.conversations(),
    queryFn: fetchConversations,
    enabled,
    // Realtime keeps an open thread current; this only covers a device that
    // briefly lost its socket while the list was on screen.
    refetchInterval: 60_000,
  });
}

export function useMessages(conversationId: string | null) {
  return useQuery({
    queryKey: messagingKeys.messages(conversationId),
    queryFn: () => fetchMessages(conversationId!),
    enabled: Boolean(conversationId),
  });
}

/**
 * Writes one message into the cached thread without a refetch, so a sent or
 * received message lands the instant it exists. Left alone when the thread has
 * not been loaded yet — seeding it with a single row would look like a
 * conversation of one and be treated as fresh.
 */
function upsertCachedMessage(
  queryClient: QueryClient,
  conversationId: string,
  row: MessageRow,
) {
  queryClient.setQueryData<MessageRow[]>(
    messagingKeys.messages(conversationId),
    (existing) => {
      if (!existing) return existing;
      const others = existing.filter((message) => message.id !== row.id);
      return [row, ...others].sort((left, right) =>
        right.created_at.localeCompare(left.created_at),
      );
    },
  );
}

/** The placeholder a message wears between the tap and the server's reply. */
function insertOptimisticMessage(
  queryClient: QueryClient,
  conversationId: string,
  fields: {
    localId: string;
    senderId: string;
    body?: string | null;
    imageUrl?: string | null;
  },
) {
  const optimistic: MessageRow = {
    id: fields.localId,
    conversation_id: conversationId,
    sender_id: fields.senderId,
    body: fields.body ?? null,
    image_url: fields.imageUrl ?? null,
    created_at: new Date().toISOString(),
    read_at: null,
    delivered_at: null,
    deleted_at: null,
    pending: true,
  };
  queryClient.setQueryData<MessageRow[]>(
    messagingKeys.messages(conversationId),
    (existing) => (existing ? [optimistic, ...existing] : [optimistic]),
  );
}

/** Drops the placeholder in the same write that adds the real row, so the two
 * are never on screen together. */
function replaceOptimisticMessage(
  queryClient: QueryClient,
  row: MessageRow,
  localId: string | undefined,
) {
  queryClient.setQueryData<MessageRow[]>(
    messagingKeys.messages(row.conversation_id),
    (existing) => {
      const without = (existing ?? []).filter(
        (message) => message.id !== localId && message.id !== row.id,
      );
      return [row, ...without].sort((left, right) =>
        right.created_at.localeCompare(left.created_at),
      );
    },
  );
}

/** A message that never left must not linger looking sent. */
function dropOptimisticMessage(
  queryClient: QueryClient,
  conversationId: string,
  localId: string | undefined,
) {
  if (!localId) return;
  queryClient.setQueryData<MessageRow[]>(
    messagingKeys.messages(conversationId),
    (existing) => (existing ?? []).filter((message) => message.id !== localId),
  );
}

export function useOpenConversation() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (devoteeId: string) => openConversation(devoteeId),
    onSuccess: () =>
      queryClient.invalidateQueries({
        queryKey: messagingKeys.conversations(),
      }),
  });
}

/**
 * Sends optimistically: the bubble appears the instant Send is tapped, marked
 * pending, and is replaced by the server's row when it lands.
 *
 * Waiting for the round trip was the whole reason the chat felt slow — the
 * network was never the problem, the blank pause was.
 */
export function useSendMessage() {
  const queryClient = useQueryClient();
  return useMutation({
    // localId and senderId exist only to paint the optimistic bubble; the RPC
    // takes neither.
    mutationFn: ({
      localId: _localId,
      senderId: _senderId,
      ...input
    }: SendMessageInput & { localId?: string; senderId?: string }) =>
      sendMessage(input),

    onMutate: async (input) => {
      const key = messagingKeys.messages(input.conversationId);
      await queryClient.cancelQueries({ queryKey: key });

      const localId = input.localId;
      if (!localId || !input.senderId) return { localId: undefined };

      insertOptimisticMessage(queryClient, input.conversationId, {
        localId,
        senderId: input.senderId,
        body: input.body,
        imageUrl: input.imageUrl,
      });
      return { localId };
    },

    onSuccess: (row, _input, context) => {
      replaceOptimisticMessage(queryClient, row, context?.localId);
      void queryClient.invalidateQueries({
        queryKey: messagingKeys.conversations(),
      });
    },

    onError: (_error, input, context) => {
      dropOptimisticMessage(queryClient, input.conversationId, context?.localId);
    },
  });
}

export function useMarkDelivered() {
  return useMutation({
    mutationFn: (conversationId: string) =>
      markConversationDelivered(conversationId),
  });
}

export function useHideMessageForMe() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ messageId }: { messageId: string; conversationId: string }) =>
      hideMessageForMe(messageId),
    onSuccess: (_result, { messageId, conversationId }) => {
      queryClient.setQueryData<MessageRow[]>(
        messagingKeys.messages(conversationId),
        (existing) =>
          (existing ?? []).filter((message) => message.id !== messageId),
      );
    },
  });
}

export type SendMessageImageInput = {
  conversationId: string;
  image: PickedMessageImage;
  body?: string | null;
  /** Both are needed to paint the pending bubble; neither reaches the server. */
  localId?: string;
  senderId?: string;
};

/**
 * The picture goes to storage first: send_message only records a URL, so a
 * failed upload must never become a message pointing at nothing.
 *
 * The wait is the whole upload, not a single round trip, so the optimistic
 * bubble matters more here than it does for text — it is the only thing that
 * says the picture is on its way.
 */
export function useSendMessageImage(userId: string | null) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async ({ conversationId, image, body }: SendMessageImageInput) => {
      if (!userId) throw new Error("Sign in to send a picture.");
      const imageUrl = await uploadMessageImage(userId, image);
      return sendMessage({ conversationId, body: body ?? null, imageUrl });
    },

    onMutate: async (input) => {
      const key = messagingKeys.messages(input.conversationId);
      await queryClient.cancelQueries({ queryKey: key });

      const localId = input.localId;
      if (!localId || !input.senderId) return { localId: undefined };

      insertOptimisticMessage(queryClient, input.conversationId, {
        localId,
        senderId: input.senderId,
        body: input.body,
        // The file still on the phone stands in until the uploaded copy has a
        // URL, so the picture is on screen before it has left the device.
        imageUrl: input.image.uri,
      });
      return { localId };
    },

    onSuccess: (row, _input, context) => {
      replaceOptimisticMessage(queryClient, row, context?.localId);
      void queryClient.invalidateQueries({
        queryKey: messagingKeys.conversations(),
      });
    },

    onError: (_error, input, context) => {
      dropOptimisticMessage(queryClient, input.conversationId, context?.localId);
    },
  });
}

export { pickMessageImage };

export function useMarkRead() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (conversationId: string) =>
      markConversationRead(conversationId),
    // Only refresh when something actually changed: the screen calls this on
    // every arriving message, and an unconditional invalidate would refetch
    // the conversation list on each one.
    onSuccess: (marked, conversationId) => {
      if (!marked) return;
      void queryClient.invalidateQueries({
        queryKey: messagingKeys.conversations(),
      });
      void queryClient.invalidateQueries({
        queryKey: messagingKeys.messages(conversationId),
      });
    },
  });
}

export function useDeleteMessage() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (messageId: string) => deleteMessage(messageId),
    onSuccess: (row) => {
      upsertCachedMessage(queryClient, row.conversation_id, row);
      void queryClient.invalidateQueries({
        queryKey: messagingKeys.conversations(),
      });
    },
  });
}

/**
 * Live updates for one open thread. Inserts append; updates cover the two
 * things that change after the fact — a read receipt and a deletion.
 */
export function useMessagesRealtime(conversationId: string | null) {
  const queryClient = useQueryClient();

  useEffect(() => {
    if (!conversationId) return;
    const filter = `conversation_id=eq.${conversationId}`;
    const apply = (row: MessageRow) => {
      upsertCachedMessage(queryClient, conversationId, row);
      void queryClient.invalidateQueries({
        queryKey: messagingKeys.conversations(),
      });
    };

    const channel = getSupabaseClient()
      .channel(`messages-live-${conversationId}`)
      .on<MessageRow>(
        "postgres_changes",
        { event: "INSERT", schema: "public", table: "messages", filter },
        (payload) => apply(payload.new),
      )
      .on<MessageRow>(
        "postgres_changes",
        { event: "UPDATE", schema: "public", table: "messages", filter },
        (payload) => apply(payload.new),
      )
      .subscribe();

    return () => {
      void getSupabaseClient().removeChannel(channel);
    };
  }, [conversationId, queryClient]);
}

/** At most one broadcast this often while a devotee keeps typing. */
const TYPING_BROADCAST_INTERVAL = 2_000;
/** How long "typing…" survives without a further signal. */
const TYPING_EXPIRY = 4_000;

/**
 * "typing…" over a broadcast channel rather than a table: it is true for a
 * couple of seconds and worth nothing afterwards, so writing it to Postgres
 * would mean a row per keystroke and a permanent record of hesitation.
 *
 * Nothing reliably announces that typing stopped — a devotee can lock the
 * phone mid-sentence — so the indicator expires on its own.
 */
export function useTypingIndicator(
  conversationId: string | null,
  selfId: string | null,
  peerId: string | null,
) {
  const [isPeerTyping, setIsPeerTyping] = useState(false);
  const channelRef = useRef<RealtimeChannel | null>(null);
  const expiryTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const lastBroadcastAt = useRef(0);

  useEffect(() => {
    if (!conversationId || !selfId) return;

    const channel = getSupabaseClient()
      .channel(`typing-${conversationId}`, {
        config: { broadcast: { self: false } },
      })
      .on<TypingSignal>(
        "broadcast",
        { event: "typing" },
        ({ payload }) => {
          // Only the devotee on the other side of this thread may move the
          // indicator: `self: false` is not honoured before the socket has
          // joined, and a channel name is not a permission.
          if (!payload || payload.from !== peerId) return;
          if (expiryTimer.current) clearTimeout(expiryTimer.current);
          setIsPeerTyping(payload.typing);
          if (payload.typing) {
            expiryTimer.current = setTimeout(
              () => setIsPeerTyping(false),
              TYPING_EXPIRY,
            );
          }
        },
      )
      .subscribe();
    channelRef.current = channel;

    return () => {
      if (expiryTimer.current) clearTimeout(expiryTimer.current);
      // Leaving mid-sentence should not leave "typing…" sitting on the other
      // devotee's screen until it expires. Best effort — the socket may
      // already be gone — which is why the expiry exists at all.
      void channel.send({
        type: "broadcast",
        event: "typing",
        payload: { typing: false, from: selfId } satisfies TypingSignal,
      });
      channelRef.current = null;
      setIsPeerTyping(false);
      void getSupabaseClient().removeChannel(channel);
    };
  }, [conversationId, peerId, selfId]);

  const broadcast = useCallback(
    (typing: boolean) => {
      const channel = channelRef.current;
      if (!channel || !selfId) return;
      void channel.send({
        type: "broadcast",
        event: "typing",
        payload: { typing, from: selfId } satisfies TypingSignal,
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

  return { isPeerTyping, notifyTyping, notifyStoppedTyping };
}
