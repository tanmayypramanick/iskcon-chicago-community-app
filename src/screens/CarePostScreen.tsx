import { Ionicons } from "@expo/vector-icons";
import { useEffect, useState } from "react";
import {
  Alert,
  Image,
  KeyboardAvoidingView,
  Platform,
  Pressable,
  Text,
  TextInput,
  View,
} from "react-native";

import tokens from "../../design-tokens.json";
import { ModalScreen } from "../components/ModalScreen";
import {
  Avatar,
  Button,
  EmptyOrOffline,
  ListScreen,
  LoadFailure,
} from "../components/ui";
import {
  useCareReplies,
  useDeleteCareReply,
  useReplyToCarePost,
} from "../features/care/hooks";
import type { CarePost, CareReply } from "../features/care/types";
import { FormError } from "../features/services/components";
import { errorMessage } from "../features/services/format";
import { formatChicagoShortDate } from "../lib/chicagoDate";
import { useServerReachable } from "../lib/connectivity";

const MINUTE = 60_000;
const HOUR = 60 * MINUTE;
const DAY = 24 * HOUR;

/**
 * Short and glanceable, then an actual date once "14d" stops meaning anything.
 * A board is scanned before it is read.
 */
export function formatCareTime(value: string) {
  const at = new Date(value);
  if (Number.isNaN(at.getTime())) return "";
  const elapsed = Date.now() - at.getTime();
  if (elapsed < MINUTE) return "Just now";
  if (elapsed < HOUR) return `${Math.floor(elapsed / MINUTE)}m ago`;
  if (elapsed < DAY) return `${Math.floor(elapsed / HOUR)}h ago`;
  if (elapsed < 7 * DAY) return `${Math.floor(elapsed / DAY)}d ago`;
  return formatChicagoShortDate(at);
}

/**
 * One reply. A removed one keeps its place and loses its words: the replies
 * under it were written as answers to what came before, and closing the gap
 * would leave them answering something nobody can see.
 */
function ReplyRow({
  reply,
  onOpenDevotee,
  onRemove,
}: {
  reply: CareReply;
  onOpenDevotee: (devoteeId: string) => void;
  onRemove: (reply: CareReply) => void;
}) {
  if (reply.deleted_at) {
    return (
      <View className="mt-2 rounded-card border border-border bg-sandalwood/40 px-card py-3">
        <Text className="font-sans text-sm italic text-stoneMuted">
          This reply was removed
        </Text>
      </View>
    );
  }

  return (
    <View className="mt-2 rounded-card border border-border bg-white p-card">
      <View className="flex-row items-center">
        <Pressable
          className="min-w-0 flex-1 flex-row items-center"
          accessibilityRole="button"
          accessibilityLabel={`Open ${reply.author_name}'s profile`}
          onPress={() => onOpenDevotee(reply.author_id)}
        >
          <Avatar
            name={reply.author_name}
            photoUrl={reply.author_photo_url}
            size="tiny"
            tone="peacock"
          />
          <View className="ml-3 min-w-0 flex-1">
            <Text
              className="font-sans-bold text-sm text-stone"
              numberOfLines={1}
            >
              {reply.author_name}
            </Text>
            <Text className="font-sans text-xs text-stoneMuted">
              {formatCareTime(reply.created_at)}
            </Text>
          </View>
        </Pressable>

        {reply.can_remove ? (
          <Pressable
            className="ml-2 h-10 w-10 items-center justify-center rounded-pill"
            accessibilityRole="button"
            accessibilityLabel={`Remove ${reply.author_name}'s reply`}
            onPress={() => onRemove(reply)}
          >
            <Ionicons
              name="trash-outline"
              size={18}
              color={tokens.colors.vermilion}
            />
          </Pressable>
        ) : null}
      </View>

      <Text className="mt-2.5 font-sans text-base leading-6 text-stone">
        {reply.body}
      </Text>
    </View>
  );
}

/**
 * One care post and its thread, presented as a full-screen modal from the
 * board rather than as a route — the board owns which post is open, and this
 * feature has no route of its own to be deep-linked to.
 */
export function CarePostScreen({
  post,
  onClose,
  onOpenDevotee,
}: {
  /** The open post, or null when the modal is closed. */
  post: CarePost | null;
  onClose: () => void;
  /** Closes the thread and opens that devotee's profile on the Devotees tab. */
  onOpenDevotee: (devoteeId: string) => void;
}) {
  const reachable = useServerReachable();
  const postId = post?.id ?? null;
  const replies = useCareReplies(postId);
  const sendReply = useReplyToCarePost();
  const removeReply = useDeleteCareReply();

  const [draft, setDraft] = useState("");
  const [threadError, setThreadError] = useState<string | null>(null);

  // A draft belongs to the post it was written under, not to the modal.
  useEffect(() => {
    setDraft("");
    setThreadError(null);
  }, [postId]);

  const rows = replies.data ?? [];
  const failed = replies.isError && replies.data === undefined;
  const trimmed = draft.trim();

  const submit = () => {
    if (!postId || !trimmed) return;
    setThreadError(null);
    sendReply.mutate(
      { postId, body: trimmed },
      {
        // The words are handed back rather than lost, so a failed reply costs
        // a second tap and not what the devotee wrote.
        onSuccess: () => setDraft(""),
        onError: (caught) =>
          setThreadError(
            errorMessage(caught, "That reply could not be sent.") ?? null,
          ),
      },
    );
  };

  const confirmRemoveReply = (reply: CareReply) => {
    if (!postId) return;
    Alert.alert(
      "Remove this reply?",
      "It will keep its place in the thread, marked as removed.",
      [
        { text: "Keep", style: "cancel" },
        {
          text: "Remove",
          style: "destructive",
          onPress: () =>
            removeReply.mutate(
              { replyId: reply.id, postId },
              {
                onError: (caught) =>
                  setThreadError(
                    errorMessage(caught, "That reply could not be removed.") ??
                      null,
                  ),
              },
            ),
        },
      ],
    );
  };

  return (
    <ModalScreen
      visible={Boolean(post)}
      onClose={onClose}
      eyebrow="Devotee care"
      title="Request"
      backLabel="Close this request"
      scroll={false}
    >
      <KeyboardAvoidingView
        className="flex-1"
        behavior={Platform.OS === "ios" ? "padding" : undefined}
      >
        <ListScreen
          topInset={false}
          bottomInset={false}
          data={rows}
          keyExtractor={(reply) => reply.id}
          header={
            <>
              {post ? (
                <View className="rounded-card border border-border bg-white p-card">
                  <Text className="font-display text-2xl leading-8 text-stone">
                    {post.title}
                  </Text>

                  <Pressable
                    className="mt-3 flex-row items-center"
                    accessibilityRole="button"
                    accessibilityLabel={`Open ${post.author_name}'s profile`}
                    onPress={() => onOpenDevotee(post.author_id)}
                  >
                    <Avatar
                      name={post.author_name}
                      photoUrl={post.author_photo_url}
                      size="small"
                      tone="marigold"
                    />
                    <View className="ml-3 min-w-0 flex-1">
                      <Text
                        className="font-sans-bold text-base text-stone"
                        numberOfLines={1}
                      >
                        {post.author_name}
                      </Text>
                      <Text className="font-sans text-xs text-stoneMuted">
                        {formatCareTime(post.created_at)}
                      </Text>
                    </View>
                    <Ionicons
                      name="chevron-forward"
                      size={18}
                      color={tokens.colors.stoneMuted}
                    />
                  </Pressable>

                  <Text className="mt-3 font-sans text-base leading-6 text-stone">
                    {post.body}
                  </Text>

                  {post.image_url ? (
                    <Image
                      source={{ uri: post.image_url }}
                      className="mt-3 w-full rounded-button"
                      style={{ aspectRatio: 4 / 3 }}
                      resizeMode="cover"
                      accessibilityIgnoresInvertColors
                      accessibilityLabel={`Photo added to ${post.title}`}
                    />
                  ) : null}

                  <Text className="mt-3 font-sans text-sm text-stoneMuted">
                    Tap a devotee to open their profile — you can message them
                    privately from there.
                  </Text>
                </View>
              ) : null}

              <Text className="mb-1 mt-section font-sans-bold text-lg text-stone">
                {rows.length
                  ? `${rows.length} repl${rows.length === 1 ? "y" : "ies"}`
                  : "Replies"}
              </Text>

              {threadError ? <FormError message={threadError} /> : null}
            </>
          }
          renderItem={(reply) => (
            <ReplyRow
              reply={reply}
              onOpenDevotee={onOpenDevotee}
              onRemove={confirmRemoveReply}
            />
          )}
          empty={
            failed ? (
              <LoadFailure
                reachable={reachable}
                message={errorMessage(
                  replies.error,
                  "This thread could not be loaded.",
                )}
                onRetry={() => void replies.refetch()}
              />
            ) : (
              <EmptyOrOffline
                reachable={reachable}
                loading={replies.isLoading}
                loadingLabel="Loading this thread…"
                empty={
                  <View className="items-center rounded-card border border-border bg-white px-card py-8">
                    <Ionicons
                      name="heart-outline"
                      size={28}
                      color={tokens.colors.peacock}
                    />
                    <Text className="mt-3 text-center font-sans-bold text-base text-stone">
                      Nobody has answered yet
                    </Text>
                    <Text className="mt-1 max-w-72 text-center font-sans text-sm leading-5 text-stoneMuted">
                      Be the first. Even “I am praying for you” is an answer.
                    </Text>
                  </View>
                }
              />
            )
          }
          footer={
            <View className="mb-4 mt-section rounded-card border border-border bg-white p-card">
              <TextInput
                className="min-h-[88px] rounded-button border border-border bg-white px-4 py-3 font-sans text-base text-stone"
                value={draft}
                onChangeText={setDraft}
                placeholder="Write a reply"
                placeholderTextColor={tokens.colors.stoneMuted}
                multiline
                textAlignVertical="top"
                accessibilityLabel="Your reply"
              />
              <View className="mt-3">
                <Button
                  icon="send-outline"
                  disabled={sendReply.isPending || !trimmed}
                  onPress={submit}
                >
                  {sendReply.isPending ? "Sending…" : "Send reply"}
                </Button>
              </View>
              <Text className="mt-2 font-sans text-xs leading-5 text-stoneMuted">
                Only the devotee who asked is told about your reply.
              </Text>
            </View>
          }
        />
      </KeyboardAvoidingView>
    </ModalScreen>
  );
}
