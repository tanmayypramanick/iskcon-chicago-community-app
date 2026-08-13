import { Ionicons } from "@expo/vector-icons";
import { type NavigationProp } from "@react-navigation/native";
import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import { useQueryClient } from "@tanstack/react-query";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  Alert,
  KeyboardAvoidingView,
  Platform,
  Pressable,
  Text,
  TextInput,
  View,
} from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";

import tokens from "../../design-tokens.json";
import {
  Avatar,
  EmptyOrOffline,
  ListScreen,
  LoadFailure,
  Skeleton,
} from "../components/ui";
import { useCurrentAccessProfile } from "../features/access/hooks";
import {
  AnnouncementCard,
  useAnnouncementDayKeys,
} from "../features/announcements/components";
import {
  announcementKeys,
  useAddAnnouncementComment,
  useAnnouncementComments,
  useAnnouncements,
  useDeleteAnnouncementComment,
  useToggleAnnouncementLike,
} from "../features/announcements/hooks";
import type {
  Announcement,
  AnnouncementComment,
} from "../features/announcements/types";
import { FormError } from "../features/services/components";
import { errorMessage } from "../features/services/format";
import { useServerReachable } from "../lib/connectivity";
import type { HomeStackParamList, MainTabParamList } from "../navigation/types";
import { usePrototypeSession } from "../store/usePrototypeSession";
import { formatCareTime } from "./CarePostScreen";

type Props = NativeStackScreenProps<HomeStackParamList, "AnnouncementComments">;

/** Longer than this and a comment is folded until somebody asks for it. */
const SEE_MORE_CHARS = 180;
/** How much of a busy thread stands open before "View N more replies". */
const REPLIES_SHOWN = 2;

/** A top-level comment and the replies the server hung under it. */
type Thread = { comment: AnnouncementComment; replies: AnnouncementComment[] };

/**
 * The flat rows come back in render order — each top-level comment immediately
 * followed by its own replies — so this only has to group them, never sort
 * them.
 *
 * A reply whose parent is missing is kept as a thread of its own rather than
 * dropped: words a devotee wrote must not vanish because of a shape the client
 * did not expect.
 */
function buildThreads(rows: AnnouncementComment[]): Thread[] {
  const threads: Thread[] = [];
  const byId = new Map<string, Thread>();

  for (const row of rows) {
    if (!row.parent_comment_id) {
      const thread: Thread = { comment: row, replies: [] };
      byId.set(row.id, thread);
      threads.push(thread);
      continue;
    }
    const parent = byId.get(row.parent_comment_id);
    if (parent) parent.replies.push(row);
    else threads.push({ comment: row, replies: [] });
  }

  return threads;
}

/** Folds a long comment rather than making the thread unscrollable. */
function CommentBody({ body }: { body: string }) {
  const [expanded, setExpanded] = useState(false);
  const long = body.length > SEE_MORE_CHARS;

  return (
    <>
      <Text
        className="mt-1.5 font-sans text-base leading-6 text-stone"
        numberOfLines={long && !expanded ? 4 : undefined}
      >
        {body}
      </Text>
      {long ? (
        <Pressable
          className="mt-1 self-start py-1"
          accessibilityRole="button"
          accessibilityLabel={
            expanded ? "Show less of this comment" : "Show this whole comment"
          }
          hitSlop={6}
          onPress={() => setExpanded((open) => !open)}
        >
          <Text className="font-sans-bold text-sm text-indigo">
            {expanded ? "See less" : "See more"}
          </Text>
        </Pressable>
      ) : null}
    </>
  );
}

/**
 * One comment or one reply.
 *
 * A removed one keeps its place and loses its words: the replies under it were
 * written as answers to what came before, and closing the gap would leave them
 * answering something nobody can see.
 */
function CommentRow({
  comment,
  isReply,
  canReply,
  onReply,
  onRemove,
  onOpenDevotee,
}: {
  comment: AnnouncementComment;
  isReply: boolean;
  /** False under a removed comment: the server refuses a reply there. */
  canReply: boolean;
  onReply: () => void;
  onRemove: () => void;
  onOpenDevotee: (devoteeId: string) => void;
}) {
  if (comment.deleted_at) {
    return (
      <View
        className={`mt-2 rounded-card border border-border bg-sandalwood/40 px-card py-3 ${
          isReply ? "ml-8" : ""
        }`}
      >
        <Text className="font-sans text-sm italic text-stoneMuted">
          This comment was removed
        </Text>
      </View>
    );
  }

  return (
    <View
      className={`mt-2 rounded-card border border-border bg-white p-card ${
        isReply ? "ml-8" : ""
      } ${comment.pending ? "opacity-60" : ""}`}
    >
      <View className="flex-row items-center">
        <Pressable
          className="min-w-0 flex-1 flex-row items-center"
          accessibilityRole="button"
          accessibilityLabel={`Open ${comment.author_name}'s profile`}
          disabled={comment.pending}
          onPress={() => onOpenDevotee(comment.author_id)}
        >
          <Avatar
            name={comment.author_name}
            photoUrl={comment.author_photo_url}
            size="tiny"
            tone="peacock"
          />
          <View className="ml-3 min-w-0 flex-1">
            <Text
              className="font-sans-bold text-sm text-stone"
              numberOfLines={1}
            >
              {comment.author_name}
            </Text>
            <Text className="font-sans text-xs text-stoneMuted">
              {comment.pending
                ? "Sending…"
                : formatCareTime(comment.created_at)}
            </Text>
          </View>
        </Pressable>

        {/* Only where the server said so. Permission is never re-derived here. */}
        {comment.can_remove ? (
          <Pressable
            className="ml-2 h-10 w-10 items-center justify-center rounded-pill"
            accessibilityRole="button"
            accessibilityLabel={`Remove ${comment.author_name}'s comment`}
            onPress={onRemove}
          >
            <Ionicons
              name="trash-outline"
              size={18}
              color={tokens.colors.vermilion}
            />
          </Pressable>
        ) : null}
      </View>

      <CommentBody body={comment.body ?? ""} />

      {canReply && !comment.pending ? (
        <Pressable
          className="mt-1.5 self-start py-1"
          accessibilityRole="button"
          accessibilityLabel={`Reply to ${comment.author_name}`}
          hitSlop={6}
          onPress={onReply}
        >
          <Text className="font-sans-bold text-sm text-indigo">Reply</Text>
        </Pressable>
      ) : null}
    </View>
  );
}

/**
 * The notice being commented on, read out of the board already in the cache
 * rather than fetched again — this screen is only ever reached from the board.
 *
 * The query is subscribed to rather than read once, so a like left here moves
 * the heart on the card straight away, and it is allowed to run only when the
 * cache is empty, which is the case a deep link would arrive in.
 */
function useAnnouncement(announcementId: string): Announcement | null {
  const queryClient = useQueryClient();
  const cached = queryClient.getQueryData<Announcement[]>(
    announcementKeys.list(),
  );
  const board = useAnnouncements(cached === undefined);

  return board.data?.find((row) => row.id === announcementId) ?? null;
}

/**
 * One announcement's thread: the notice itself, every comment, every reply, and
 * the box to add your own. Any devotee may say something here — being heard on
 * the noticeboard is not a privilege the temple hands out — and the server
 * decides whose words may be taken down.
 */
export function AnnouncementCommentsScreen({ navigation, route }: Props) {
  const { announcementId, title } = route.params;
  const activeUserId = usePrototypeSession((state) => state.activeUserId);
  const profile = useCurrentAccessProfile(activeUserId);
  const reachable = useServerReachable();

  const announcement = useAnnouncement(announcementId);
  const { todayKey, yesterdayKey } = useAnnouncementDayKeys();
  const toggleLike = useToggleAnnouncementLike();
  const comments = useAnnouncementComments(announcementId);
  const add = useAddAnnouncementComment(activeUserId, {
    name: profile.data?.name?.trim() || "You",
    photoUrl: profile.data?.photo_url ?? null,
  });
  const remove = useDeleteAnnouncementComment();

  const [draft, setDraft] = useState("");
  const [replyTo, setReplyTo] = useState<{ id: string; name: string } | null>(
    null,
  );
  const [threadError, setThreadError] = useState<string | null>(null);
  const [openThreads, setOpenThreads] = useState<Record<string, boolean>>({});

  const rows = useMemo(() => comments.data ?? [], [comments.data]);
  const threads = useMemo(() => buildThreads(rows), [rows]);
  const failed = comments.isError && comments.data === undefined;
  const trimmed = draft.trim();

  /**
   * KeyboardAvoidingView measures its own frame relative to its parent, so on a
   * screen below a navigation header it lifts the composer by the header's
   * height too little and the keyboard covers it. As on ChatScreen, the gap
   * above the screen is measured rather than adding a dependency for it.
   */
  const rootRef = useRef<View>(null);
  const [headerOffset, setHeaderOffset] = useState(0);
  const measureHeader = useCallback(() => {
    rootRef.current?.measureInWindow((_x, y) => setHeaderOffset(y));
  }, []);

  // Somebody else may take down the comment being answered while the reply is
  // still being typed. The server refuses a reply to a removed comment, so the
  // draft is turned back into a plain comment here rather than sent into a
  // refusal — the words survive either way.
  useEffect(() => {
    if (!replyTo || !rows.length) return;
    const parent = rows.find((row) => row.id === replyTo.id);
    if (parent && !parent.deleted_at) return;
    setReplyTo(null);
    setThreadError(
      "That comment was removed. What you have written will post as a new comment.",
    );
  }, [replyTo, rows]);

  // A devotee's profile lives on the Devotees tab, so opening one is a hop
  // between stacks rather than a push onto this one.
  const openDevotee = (devoteeId: string) => {
    navigation
      .getParent<NavigationProp<MainTabParamList>>()
      ?.navigate("Devotees", {
        screen: "DevoteeProfile",
        params: { devoteeId },
      });
  };

  const submit = () => {
    if (!trimmed || add.isPending) return;
    setThreadError(null);
    // The box empties as the words appear on the thread; a refusal hands them
    // back rather than losing them.
    setDraft("");
    setReplyTo(null);
    add.mutate(
      {
        announcementId,
        body: trimmed,
        parentCommentId: replyTo?.id ?? null,
      },
      {
        onError: (caught) => {
          setDraft(trimmed);
          setThreadError(
            errorMessage(caught, "That comment could not be posted."),
          );
        },
      },
    );
  };

  const confirmRemove = (comment: AnnouncementComment) => {
    Alert.alert(
      "Remove this comment?",
      "It keeps its place in the thread, marked as removed, so the replies under it still make sense.",
      [
        { text: "Keep", style: "cancel" },
        {
          text: "Remove",
          style: "destructive",
          onPress: () => {
            setThreadError(null);
            remove.mutate(
              { commentId: comment.id, announcementId },
              {
                onError: (caught) =>
                  setThreadError(
                    errorMessage(caught, "That comment could not be removed."),
                  ),
              },
            );
          },
        },
      ],
    );
  };

  const liveCount = rows.filter((row) => !row.deleted_at).length;

  return (
    <SafeAreaView
      ref={rootRef}
      onLayout={measureHeader}
      className="flex-1 bg-ivory"
      edges={["bottom"]}
    >
      <KeyboardAvoidingView
        className="flex-1"
        behavior={Platform.OS === "ios" ? "padding" : "height"}
        keyboardVerticalOffset={Platform.OS === "ios" ? headerOffset : 0}
      >
        <ListScreen
          topInset={false}
          bottomInset={false}
          data={threads}
          keyExtractor={(thread) => thread.comment.id}
          header={
            <>
              {/* Scrolls away with the thread rather than staying pinned: a
                  long notice above a long thread would leave a small phone no
                  room to read either. */}
              {announcement ? (
                <AnnouncementCard
                  announcement={announcement}
                  todayKey={todayKey}
                  yesterdayKey={yesterdayKey}
                  onToggleLike={() => {
                    setThreadError(null);
                    toggleLike.mutate(announcement.id);
                  }}
                  onOpenLikes={() =>
                    navigation.navigate("AnnouncementLikes", {
                      announcementId: announcement.id,
                      title: announcement.title,
                    })
                  }
                />
              ) : (
                // The title travelled with the route, so the thread still names
                // its notice while a cold cache fills.
                <Text
                  className="font-display text-xl leading-7 text-stone"
                  numberOfLines={3}
                >
                  {title}
                </Text>
              )}
              <Text className="mt-1 font-sans text-sm text-stoneMuted">
                {liveCount
                  ? `${liveCount} ${liveCount === 1 ? "comment" : "comments"} · anyone can reply`
                  : "Anyone can comment, and anyone can reply."}
              </Text>
              {threadError ? (
                <View className="mt-3">
                  <FormError message={threadError} />
                </View>
              ) : null}
            </>
          }
          renderItem={(thread) => {
            const expanded = openThreads[thread.comment.id] ?? false;
            const shown = expanded
              ? thread.replies
              : thread.replies.slice(0, REPLIES_SHOWN);
            const hidden = thread.replies.length - shown.length;
            // Under a removed comment there is nothing to answer: the server
            // refuses a reply to one, so the action is not offered.
            const canReply = !thread.comment.deleted_at;

            return (
              <View className="mb-1">
                <CommentRow
                  comment={thread.comment}
                  isReply={false}
                  canReply={canReply}
                  onReply={() =>
                    setReplyTo({
                      id: thread.comment.id,
                      name: thread.comment.author_name,
                    })
                  }
                  onRemove={() => confirmRemove(thread.comment)}
                  onOpenDevotee={openDevotee}
                />

                {shown.map((reply) => (
                  <CommentRow
                    key={reply.id}
                    comment={reply}
                    isReply
                    // A reply answers the comment above it, so replying to one
                    // joins that same thread rather than starting a second
                    // level the server will not accept.
                    canReply={canReply}
                    onReply={() =>
                      setReplyTo({
                        id: thread.comment.id,
                        name: reply.author_name,
                      })
                    }
                    onRemove={() => confirmRemove(reply)}
                    onOpenDevotee={openDevotee}
                  />
                ))}

                {hidden > 0 ? (
                  <Pressable
                    className="ml-8 mt-2 self-start py-1"
                    accessibilityRole="button"
                    accessibilityLabel={`View ${hidden} more ${hidden === 1 ? "reply" : "replies"}`}
                    hitSlop={6}
                    onPress={() =>
                      setOpenThreads((open) => ({
                        ...open,
                        [thread.comment.id]: true,
                      }))
                    }
                  >
                    <Text className="font-sans-bold text-sm text-indigo">
                      View {hidden} more {hidden === 1 ? "reply" : "replies"}
                    </Text>
                  </Pressable>
                ) : null}

                {expanded && thread.replies.length > REPLIES_SHOWN ? (
                  <Pressable
                    className="ml-8 mt-2 self-start py-1"
                    accessibilityRole="button"
                    accessibilityLabel="Hide these replies"
                    hitSlop={6}
                    onPress={() =>
                      setOpenThreads((open) => ({
                        ...open,
                        [thread.comment.id]: false,
                      }))
                    }
                  >
                    <Text className="font-sans-bold text-sm text-indigo">
                      Hide replies
                    </Text>
                  </Pressable>
                ) : null}
              </View>
            );
          }}
          empty={
            comments.isLoading ? (
              <View className="mt-2 gap-2 rounded-card border border-border bg-white p-card">
                <Skeleton height={36} />
                <Skeleton height={36} />
                <Skeleton height={36} />
              </View>
            ) : failed ? (
              <View className="mt-2">
                <LoadFailure
                  reachable={reachable}
                  message={errorMessage(
                    comments.error,
                    "This thread could not be loaded.",
                  )}
                  onRetry={() => void comments.refetch()}
                />
              </View>
            ) : (
              <View className="mt-2">
                <EmptyOrOffline
                  reachable={reachable}
                  loading={false}
                  empty={
                    <View className="items-center rounded-card border border-border bg-white px-card py-8">
                      <Ionicons
                        name="chatbubble-outline"
                        size={28}
                        color={tokens.colors.peacock}
                      />
                      <Text className="mt-3 text-center font-sans-bold text-base text-stone">
                        Nobody has said anything yet
                      </Text>
                      <Text className="mt-1 max-w-72 text-center font-sans text-sm leading-5 text-stoneMuted">
                        Ask a question about this notice, or be the first to say
                        thank you.
                      </Text>
                    </View>
                  }
                />
              </View>
            )
          }
        />

        <View className="border-t border-border bg-white">
          {replyTo ? (
            <View className="flex-row items-center px-screen pt-2">
              <Ionicons
                name="return-down-forward-outline"
                size={16}
                color={tokens.colors.peacock}
              />
              <Text
                className="ml-1.5 min-w-0 flex-1 font-sans text-xs text-stoneMuted"
                numberOfLines={1}
              >
                Replying to {replyTo.name}
              </Text>
              <Pressable
                className="h-9 w-9 items-center justify-center rounded-pill"
                accessibilityRole="button"
                accessibilityLabel="Cancel this reply and write a comment instead"
                hitSlop={6}
                onPress={() => setReplyTo(null)}
              >
                <Ionicons
                  name="close"
                  size={18}
                  color={tokens.colors.stoneMuted}
                />
              </Pressable>
            </View>
          ) : null}

          <View className="flex-row items-end px-2 pb-2 pt-1.5">
            <TextInput
              className="mx-1 max-h-28 min-h-11 flex-1 rounded-card border border-border bg-ivory px-4 py-2.5 font-sans text-base text-stone"
              value={draft}
              onChangeText={setDraft}
              placeholder={
                replyTo ? `Reply to ${replyTo.name}` : "Write a comment"
              }
              placeholderTextColor={tokens.colors.stoneMuted}
              multiline
              accessibilityLabel={
                replyTo ? `Your reply to ${replyTo.name}` : "Your comment"
              }
            />
            <Pressable
              className={`h-11 w-11 items-center justify-center rounded-pill ${
                trimmed ? "bg-indigo" : "bg-indigoSoft"
              }`}
              accessibilityRole="button"
              accessibilityLabel={replyTo ? "Post reply" : "Post comment"}
              accessibilityState={{ disabled: !trimmed }}
              hitSlop={6}
              disabled={!trimmed}
              onPress={submit}
            >
              <Ionicons
                name="send"
                size={18}
                color={trimmed ? tokens.colors.white : tokens.colors.indigo}
              />
            </Pressable>
          </View>
        </View>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}
