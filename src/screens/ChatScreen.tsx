import { Ionicons } from "@expo/vector-icons";
import { useIsFocused } from "@react-navigation/native";
import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import { useQuery } from "@tanstack/react-query";
import {
  memo,
  useCallback,
  useEffect,
  useLayoutEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from "react";
import {
  ActivityIndicator,
  Alert,
  Animated,
  BackHandler,
  FlatList,
  Image,
  KeyboardAvoidingView,
  Linking,
  Modal,
  Platform,
  Pressable,
  Text,
  TextInput,
  View,
  type ListRenderItemInfo,
  type NativeScrollEvent,
  type NativeSyntheticEvent,
} from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";

import tokens from "../../design-tokens.json";
import { ActionSheet, type ActionSheetAction } from "../components/ActionSheet";
import {
  Avatar,
  RemoteImage,
} from "../components/ui";
import { getSupabaseClient } from "../lib/supabase";
import {
  pickMessageImage,
  useDeleteMessage,
  useMarkRead,
  useMessages,
  useMessagesRealtime,
  useHideMessageForMe,
  useMarkDelivered,
  useSendMessage,
  useSendMessageImage,
  useTypingIndicator,
} from "../features/messaging/hooks";
import type {
  MessageRow,
  PickedMessageImage,
} from "../features/messaging/types";
import { errorMessage } from "../features/services/format";
import { copyText } from "../lib/copyText";
import {
  formatChicagoShortDate,
  formatChicagoTime,
  getChicagoDateKey,
} from "../lib/chicagoDate";
import type { DevoteesStackParamList } from "../navigation/types";
import { usePrototypeSession } from "../store/usePrototypeSession";

type Props = NativeStackScreenProps<DevoteesStackParamList, "Chat">;

/** A picture never grows past this, however large the original is. */
const IMAGE_WIDTH = 220;
const IMAGE_RADIUS = 16;

/** How close to the foot of the thread still counts as "reading the latest". */
const STICK_TO_BOTTOM_SLACK = 120;

/** Long enough for the list to lay out one more window before a jump retries. */
const SCROLL_RETRY_MS = 120;
/** A jump that has not landed by now never will; better still than looping. */
const SCROLL_MAX_ATTEMPTS = 3;

/** Stable identity, so an empty search does not churn the match memos. */
const NO_MATCHES: number[] = [];

function localMessageId() {
  return `pending-${Date.now()}-${Math.random().toString(36).slice(2)}`;
}

function DaySeparator({ at }: { at: Date }) {
  return (
    <View className="my-3 flex-row items-center justify-center">
      <View className="rounded-pill bg-sandalwood px-3 py-1">
        <Text className="font-sans-bold text-xs text-stoneMuted">
          {formatChicagoShortDate(at)}
        </Text>
      </View>
    </View>
  );
}

const TYPING_DOT_STAGGER = 130;
const TYPING_DOT_DURATION = 260;
const TYPING_DOT_COUNT = 3;

/**
 * Three dots lifting in turn. Only opacity and translateY move, so the whole
 * loop is handed to the native driver and keeps running while the JS thread is
 * busy rendering arriving messages.
 */
const TypingDots = memo(function TypingDots({ label }: { label: string }) {
  const dots = useRef(
    Array.from({ length: TYPING_DOT_COUNT }, () => new Animated.Value(0)),
  ).current;
  const entrance = useRef(new Animated.Value(0)).current;

  useEffect(() => {
    const animations = [
      Animated.timing(entrance, {
        toValue: 1,
        duration: 140,
        useNativeDriver: true,
      }),
      ...dots.map((dot, index) =>
        Animated.loop(
          Animated.sequence([
            Animated.delay(index * TYPING_DOT_STAGGER),
            Animated.timing(dot, {
              toValue: 1,
              duration: TYPING_DOT_DURATION,
              useNativeDriver: true,
            }),
            Animated.timing(dot, {
              toValue: 0,
              duration: TYPING_DOT_DURATION,
              useNativeDriver: true,
            }),
            // Keeps every dot's cycle the same length, so the three stay in
            // step instead of drifting apart over a long sentence.
            Animated.delay((TYPING_DOT_COUNT - 1 - index) * TYPING_DOT_STAGGER),
          ]),
        ),
      ),
    ];
    animations.forEach((animation) => animation.start());
    return () => animations.forEach((animation) => animation.stop());
  }, [dots, entrance]);

  return (
    <Animated.View
      style={{
        opacity: entrance,
        transform: [
          {
            scale: entrance.interpolate({
              inputRange: [0, 1],
              outputRange: [0.85, 1],
            }),
          },
        ],
      }}
    >
      <View
        className="flex-row items-center rounded-pill bg-peacockSoft px-2.5 py-1.5"
        accessible
        accessibilityLabel={label}
      >
        {dots.map((dot, index) => (
          <Animated.View
            key={index}
            style={{
              width: 6,
              height: 6,
              borderRadius: 3,
              marginLeft: index === 0 ? 0 : 4,
              backgroundColor: tokens.colors.peacock,
              opacity: dot.interpolate({
                inputRange: [0, 1],
                outputRange: [0.35, 1],
              }),
              transform: [
                {
                  translateY: dot.interpolate({
                    inputRange: [0, 1],
                    outputRange: [0, -3],
                  }),
                },
              ],
            }}
          />
        ))}
      </View>
    </Animated.View>
  );
});

/**
 * Four states, on your own messages only: still leaving the device, with the
 * temple, on their phone, and opened. Their own side never carries ticks —
 * mark_conversation_read only ever stamps the other devotee's rows.
 */
function ReadTicks({ message }: { message: MessageRow }) {
  if (message.pending) {
    return (
      <Ionicons
        name="time-outline"
        size={14}
        color={tokens.colors.stoneMuted}
        accessibilityLabel="Sending"
      />
    );
  }
  const read = Boolean(message.read_at);
  const delivered = read || Boolean(message.delivered_at);
  return (
    <Ionicons
      name={delivered ? "checkmark-done" : "checkmark"}
      size={14}
      color={read ? tokens.colors.peacock : tokens.colors.stoneMuted}
      accessibilityLabel={read ? "Read" : delivered ? "Delivered" : "Sent"}
    />
  );
}

const URL_SPLIT = /(https?:\/\/[^\s]+)/g;
// Deliberately not the /g one: a global regex keeps lastIndex between calls,
// so testing each part with it would match every other link.
const IS_URL = /^https?:\/\/[^\s]+$/;

/** The hit you are standing on, and the rest of them. */
const HIGHLIGHT_CURRENT = "bg-marigold text-stone";
const HIGHLIGHT_OTHER = "bg-marigoldSoft text-stone";

/**
 * Shades every occurrence of `term` inside one run of text, returning the run
 * untouched when there is none — so an unmatched run costs one indexOf and no
 * extra Text nodes.
 *
 * indexOf rather than a built regex: a devotee searching for "Gita?" or "$20"
 * would otherwise be handing us a pattern instead of a word.
 */
function highlightRuns(
  text: string,
  term: string,
  keyPrefix: string,
  current: boolean,
): ReactNode {
  const haystack = text.toLowerCase();
  // A few scripts lengthen when lowercased, which would slide every slice
  // below out of step with the original. Not worth shading over garbling.
  if (haystack.length !== text.length) return text;

  let at = haystack.indexOf(term);
  if (at === -1) return text;

  const nodes: ReactNode[] = [];
  let from = 0;
  while (at !== -1) {
    if (at > from) nodes.push(text.slice(from, at));
    nodes.push(
      <Text
        key={`${keyPrefix}-${at}`}
        className={current ? HIGHLIGHT_CURRENT : HIGHLIGHT_OTHER}
      >
        {text.slice(at, at + term.length)}
      </Text>,
    );
    from = at + term.length;
    at = haystack.indexOf(term, from);
  }
  if (from < text.length) nodes.push(text.slice(from));
  return nodes;
}

/**
 * Renders a body with any web addresses in it tappable, and any run matching
 * the open search shaded.
 *
 * Links are split off first and the shading is applied inside each run, never
 * around it. A shaded span carries no onPress of its own, so a match that
 * falls inside a URL hands the touch up to the link Text wrapping it and the
 * address still opens.
 */
function MessageText({
  body,
  mine,
  padding,
  highlight,
  isCurrentMatch,
}: {
  body: string;
  mine: boolean;
  padding: string;
  /** Already trimmed and lowercased; only set on a message that contains it. */
  highlight?: string;
  isCurrentMatch?: boolean;
}) {
  const parts = body.split(URL_SPLIT);
  const shade = (part: string, keyPrefix: string) =>
    highlight
      ? highlightRuns(part, highlight, keyPrefix, Boolean(isCurrentMatch))
      : part;
  return (
    <Text
      className={`font-sans text-base leading-6 ${padding} ${mine ? "text-white" : "text-stone"}`}
    >
      {parts.map((part, index) =>
        IS_URL.test(part) ? (
          <Text
            key={`${part}-${index}`}
            className={`underline ${mine ? "text-white" : "text-indigo"}`}
            accessibilityRole="link"
            onPress={() => {
              void Linking.openURL(part).catch(() => {
                Alert.alert("That link could not be opened.");
              });
            }}
          >
            {shade(part, `url-${index}`)}
          </Text>
        ) : (
          shade(part, `text-${index}`)
        ),
      )}
    </Text>
  );
}

type BubbleProps = {
  message: MessageRow;
  isMine: boolean;
  /** Takes the message rather than closing over it, so a row's handlers stay
   * identical between renders and React.memo can do its job. */
  onLongPress: (message: MessageRow) => void;
  onOpenImage: (url: string) => void;
  /**
   * Left undefined on every message that does not contain the search term, so
   * the rows nobody is looking for keep identical props and memo skips them.
   */
  highlight?: string;
  isCurrentMatch?: boolean;
};

const MessageBubble = memo(function MessageBubble({
  message,
  isMine,
  onLongPress,
  onOpenImage,
  highlight,
  isCurrentMatch,
}: BubbleProps) {
  const at = new Date(message.created_at);
  const isDeleted = Boolean(message.deleted_at);
  const hasImage = Boolean(message.image_url);
  const isUploading = Boolean(message.pending && message.image_url);

  const handleLongPress = useCallback(
    () => onLongPress(message),
    [message, onLongPress],
  );
  const handleOpenImage = useCallback(() => {
    if (message.image_url) onOpenImage(message.image_url);
  }, [message.image_url, onOpenImage]);

  return (
    <View className={isMine ? "items-end" : "items-start"}>
      <Pressable
        className={`max-w-[80%] ${hasImage && !isDeleted ? "p-1" : "px-4 py-2.5"} ${
          isMine
            ? "rounded-card rounded-br-md bg-indigo"
            : "rounded-card rounded-bl-md border border-border bg-white"
        }`}
        accessibilityRole="text"
        accessibilityLabel={
          isDeleted
            ? `${isMine ? "You" : "They"} deleted a message`
            : `${isMine ? "You" : "They"} said ${message.body ?? "a picture"}`
        }
        accessibilityHint={
          isDeleted
            ? undefined
            : hasImage
              ? "Tap to see it full size, hold for more"
              : "Hold for more"
        }
        // A picture still uploading has no full-size copy to open yet.
        onPress={
          hasImage && !isDeleted && !isUploading ? handleOpenImage : undefined
        }
        onLongPress={handleLongPress}
        delayLongPress={350}
      >
        {isDeleted ? (
          <Text
            className={`font-sans text-sm italic ${
              isMine ? "text-white/70" : "text-stoneMuted"
            }`}
          >
            This message was deleted
          </Text>
        ) : (
          <>
            {message.image_url ? (
              <View
                style={{
                  width: IMAGE_WIDTH,
                  height: IMAGE_WIDTH,
                  borderRadius: IMAGE_RADIUS,
                  overflow: "hidden",
                }}
              >
                <RemoteImage
                  uri={message.image_url}
                  style={{ width: "100%", height: "100%" }}
                  resizeMode="cover"
                  accessibilityIgnoresInvertColors
                />
                {isUploading ? (
                  <View
                    className="absolute inset-0 items-center justify-center bg-black/35"
                    accessible
                    accessibilityLabel="Sending this picture"
                  >
                    <ActivityIndicator
                      size="small"
                      color={tokens.colors.white}
                    />
                    <Text className="mt-1.5 font-sans text-xs text-white">
                      Sending…
                    </Text>
                  </View>
                ) : null}
              </View>
            ) : null}
            {message.body ? (
              <MessageText
                body={message.body}
                mine={isMine}
                padding={hasImage ? "px-3 pb-1 pt-2" : ""}
                highlight={highlight}
                isCurrentMatch={isCurrentMatch}
              />
            ) : null}
          </>
        )}
      </Pressable>
      <View className="mt-1 flex-row items-center px-1">
        <Text className="font-sans text-[11px] text-stoneMuted">
          {formatChicagoTime(at)}
        </Text>
        {isMine && !isDeleted ? (
          <View className="ml-1">
            <ReadTicks message={message} />
          </View>
        ) : null}
      </View>
    </View>
  );
});

type ChatRowProps = BubbleProps & {
  /** The message drawn above this one, or undefined at the top of the thread. */
  previousCreatedAt: string | undefined;
};

const ChatRow = memo(function ChatRow({
  message,
  previousCreatedAt,
  isMine,
  onLongPress,
  onOpenImage,
  highlight,
  isCurrentMatch,
}: ChatRowProps) {
  const at = new Date(message.created_at);
  // The separator belongs to the first message of each day.
  const startsDay =
    !previousCreatedAt ||
    getChicagoDateKey(new Date(previousCreatedAt)) !== getChicagoDateKey(at);

  return (
    <View className="px-screen">
      {startsDay ? <DaySeparator at={at} /> : null}
      <MessageBubble
        message={message}
        isMine={isMine}
        onLongPress={onLongPress}
        onOpenImage={onOpenImage}
        highlight={highlight}
        isCurrentMatch={isCurrentMatch}
      />
    </View>
  );
});

const keyExtractor = (message: MessageRow) => message.id;

/**
 * Only the face and the name — the full profile screen already owns the rest.
 * Shares a cache key with DevoteeProfileScreen, so tapping through is instant.
 */
function useChatPeer(devoteeId: string) {
  return useQuery({
    queryKey: ["devotee-public-profile", devoteeId],
    queryFn: async () => {
      const { data, error } = await getSupabaseClient().rpc(
        "devotee_public_profile",
        { p_devotee_id: devoteeId },
      );
      if (error) throw error;
      const rows = (data ?? []) as Array<{
        name: string;
        photo_url: string | null;
      }>;
      return rows[0] ?? null;
    },
    staleTime: 5 * 60 * 1000,
  });
}

export function ChatScreen({ route, navigation }: Props) {
  const { conversationId, devoteeId, name } = route.params;
  const isFocused = useIsFocused();
  const peer = useChatPeer(devoteeId);
  const [viewingImage, setViewingImage] = useState<string | null>(null);

  const activeUserId = usePrototypeSession((state) => state.activeUserId);
  const [draft, setDraft] = useState("");

  const messages = useMessages(conversationId);
  useMessagesRealtime(conversationId);
  const { isPeerTyping, notifyTyping, notifyStoppedTyping } =
    useTypingIndicator(conversationId, activeUserId, devoteeId);
  const markRead = useMarkRead();
  const send = useSendMessage();
  const sendImage = useSendMessageImage(activeUserId);
  const removeMessage = useDeleteMessage();
  const hideForMe = useHideMessageForMe();
  const markDelivered = useMarkDelivered();

  /**
   * Oldest first, drawn top to bottom like any other list.
   *
   * This used to be an inverted list, which flips its children on the vertical
   * axis — every bubble rendered mirrored, and the empty state needed a
   * counter-transform to look right. Reading order plus scroll-to-end is the
   * same result without the flip.
   */
  const rows = useMemo(
    () =>
      [...(messages.data ?? [])].sort((left, right) =>
        left.created_at.localeCompare(right.created_at),
      ),
    [messages.data],
  );

  const hasUnreadFromThem = rows.some(
    (message) => message.sender_id !== activeUserId && !message.read_at,
  );

  /**
   * Covers both halves of the requirement: opening the thread with anything
   * unread, and a message arriving while it is on screen. The flag goes false
   * again as soon as the RPC's effect reaches the cache, so this settles.
   */
  useEffect(() => {
    if (!isFocused || !hasUnreadFromThem) return;
    // Delivered and read are stamped together here because the thread being
    // open is proof of both. A separate delivery signal would need a push
    // receipt, which is a bigger change than the tick is worth.
    markDelivered.mutate(conversationId);
    markRead.mutate(conversationId);
    // Only the thread and its unread state should retrigger this, not the
    // mutation object, which is new on every render.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [conversationId, hasUnreadFromThem, isFocused]);

  /**
   * KeyboardAvoidingView measures its own frame relative to its parent, so on
   * a screen sitting below a navigation header it lifts the composer by the
   * header's height too little and the keyboard covers it. The usual fix is
   * @react-navigation/elements' useHeaderHeight, which this app does not
   * depend on, so the gap above the screen is measured instead.
   */
  const rootRef = useRef<View>(null);
  const listRef = useRef<FlatList<MessageRow>>(null);
  const [headerOffset, setHeaderOffset] = useState(0);
  const measureHeader = useCallback(() => {
    rootRef.current?.measureInWindow((_x, y) => setHeaderOffset(y));
  }, []);

  /**
   * Following the newest message must not mean yanking someone out of the
   * history they scrolled up to read — a growing thread only pulls the view
   * down while the foot of it is already in sight.
   */
  const stickToBottom = useRef(true);
  const hasDragged = useRef(false);
  const onScrollBeginDrag = useCallback(() => {
    hasDragged.current = true;
  }, []);
  /** Where the thread was left, so closing search can put it back. */
  const lastOffset = useRef(0);
  const onScroll = useCallback(
    (event: NativeSyntheticEvent<NativeScrollEvent>) => {
      const { contentOffset, contentSize, layoutMeasurement } =
        event.nativeEvent;
      lastOffset.current = contentOffset.y;
      // Only a finger may break the follow. Opening a thread fires scroll
      // events against a content size that is still filling in, and reading
      // those as "scrolled away" would strand the devotee at the top.
      if (!hasDragged.current) return;
      stickToBottom.current =
        contentSize.height - contentOffset.y - layoutMeasurement.height <
        STICK_TO_BOTTOM_SLACK;
    },
    [],
  );
  const onContentSizeChange = useCallback(() => {
    if (stickToBottom.current) {
      listRef.current?.scrollToEnd({ animated: false });
    }
  }, []);

  const [searchOpen, setSearchOpen] = useState(false);
  const [query, setQuery] = useState("");
  const [matchCursor, setMatchCursor] = useState(0);
  const term = query.trim().toLowerCase();

  const matches = useMemo(() => {
    if (!term) return NO_MATCHES;
    const found: number[] = [];
    for (let index = 0; index < rows.length; index += 1) {
      const body = rows[index].body;
      if (rows[index].deleted_at || !body) continue;
      if (body.toLowerCase().includes(term)) found.push(index);
    }
    return found;
  }, [rows, term]);

  /** Ids rather than positions, so a bubble can ask "am I a hit?" in O(1). */
  const matchIds = useMemo(
    () => new Set(matches.map((index) => rows[index].id)),
    [matches, rows],
  );

  // Derived rather than stored: a message deleted out from under the cursor
  // must not leave it pointing past the end of the list.
  const matchIndex = matches.length
    ? Math.min(matchCursor, matches.length - 1)
    : -1;
  const currentMatchId =
    matchIndex >= 0 ? rows[matches[matchIndex]]?.id : undefined;

  /**
   * There is deliberately no getItemLayout — bubbles are whatever height their
   * words need — so the list can only scroll straight to a row it has already
   * measured. Everything past that raises onScrollToIndexFailed instead.
   */
  const jumpAttempt = useRef<{
    index: number;
    attempts: number;
    timer: ReturnType<typeof setTimeout> | null;
  }>({ index: -1, attempts: 0, timer: null });

  const clearJumpTimer = useCallback(() => {
    if (jumpAttempt.current.timer) clearTimeout(jumpAttempt.current.timer);
    jumpAttempt.current.timer = null;
  }, []);

  useEffect(() => clearJumpTimer, [clearJumpTimer]);

  const jumpToRow = useCallback(
    (index: number) => {
      // A hit deep in the history must not be dragged back to the foot of the
      // thread the next time a message lands.
      stickToBottom.current = false;
      clearJumpTimer();
      jumpAttempt.current.index = index;
      jumpAttempt.current.attempts = 0;
      listRef.current?.scrollToIndex({
        index,
        animated: true,
        viewPosition: 0.5,
      });
    },
    [clearJumpTimer],
  );

  /**
   * Walks towards the row using the list's own average height, which lets it
   * measure the frames in between, then finishes the jump. Bounded, because
   * an estimate that keeps undershooting would otherwise ping-pong forever.
   */
  const onScrollToIndexFailed = useCallback(
    (info: { index: number; averageItemLength: number }) => {
      const attempt = jumpAttempt.current;
      if (attempt.index !== info.index) {
        attempt.index = info.index;
        attempt.attempts = 0;
      }
      if (attempt.attempts >= SCROLL_MAX_ATTEMPTS) return;
      attempt.attempts += 1;

      listRef.current?.scrollToOffset({
        offset: Math.max(0, info.averageItemLength * info.index),
        animated: false,
      });
      clearJumpTimer();
      attempt.timer = setTimeout(() => {
        attempt.timer = null;
        listRef.current?.scrollToIndex({
          index: info.index,
          animated: false,
          viewPosition: 0.5,
        });
      }, SCROLL_RETRY_MS);
    },
    [clearJumpTimer],
  );

  /**
   * A fresh term lands on the newest hit, the way every phone's chat app does
   * it, and up walks back through the history from there. Read through a ref
   * so an arriving message cannot re-trigger the jump.
   */
  const matchesRef = useRef(matches);
  matchesRef.current = matches;
  useEffect(() => {
    const found = matchesRef.current;
    setMatchCursor(Math.max(0, found.length - 1));
    if (found.length) jumpToRow(found[found.length - 1]);
  }, [jumpToRow, term]);

  const goToMatch = useCallback(
    (next: number) => {
      setMatchCursor(next);
      jumpToRow(matchesRef.current[next]);
    },
    [jumpToRow],
  );
  const goOlder = useCallback(() => {
    if (matchIndex > 0) goToMatch(matchIndex - 1);
  }, [goToMatch, matchIndex]);
  const goNewer = useCallback(() => {
    if (matchIndex >= 0 && matchIndex < matches.length - 1) {
      goToMatch(matchIndex + 1);
    }
  }, [goToMatch, matchIndex, matches.length]);

  /** Where the thread stood before searching, restored when search closes. */
  const beforeSearch = useRef<{ offset: number; stick: boolean } | null>(null);

  const openSearch = useCallback(() => {
    beforeSearch.current = {
      offset: lastOffset.current,
      stick: stickToBottom.current,
    };
    setSearchOpen(true);
  }, []);

  const closeSearch = useCallback(() => {
    const saved = beforeSearch.current;
    beforeSearch.current = null;
    clearJumpTimer();
    setSearchOpen(false);
    setQuery("");
    setMatchCursor(0);
    if (!saved) return;
    stickToBottom.current = saved.stick;
    // After the header and composer are back, or the offset is measured
    // against a list that is about to change height.
    requestAnimationFrame(() => {
      if (saved.stick) listRef.current?.scrollToEnd({ animated: false });
      else
        listRef.current?.scrollToOffset({
          offset: saved.offset,
          animated: false,
        });
    });
  }, [clearJumpTimer]);

  // Android's back gesture leaves the search, not the conversation — the
  // header that would normally carry that choice is hidden while searching.
  useEffect(() => {
    if (!searchOpen) return;
    const subscription = BackHandler.addEventListener(
      "hardwareBackPress",
      () => {
        closeSearch();
        return true;
      },
    );
    return () => subscription.remove();
  }, [closeSearch, searchOpen]);

  const onChangeDraft = useCallback(
    (value: string) => {
      setDraft(value);
      if (value.trim()) notifyTyping();
      else notifyStoppedTyping();
    },
    [notifyStoppedTyping, notifyTyping],
  );

  const canSend = draft.trim().length > 0;

  /**
   * mutateAsync rather than mutate's onError: a second send swaps the shared
   * mutation observer, and the first call's per-call callbacks are dropped
   * with it. The promise belongs to this send alone, so writing two messages
   * in quick succession still reports failures for both.
   */
  const onSend = () => {
    const body = draft.trim();
    if (!body) return;
    setDraft("");
    notifyStoppedTyping();
    stickToBottom.current = true;
    void send
      .mutateAsync({
        conversationId,
        body,
        senderId: activeUserId ?? undefined,
        localId: localMessageId(),
      })
      // The words are handed back rather than lost, so a failed send costs
      // the devotee a second tap and not the message they wrote.
      .catch((error: unknown) => {
        setDraft((current) => (current ? current : body));
        Alert.alert(
          "Message not sent",
          errorMessage(error, "That message could not be sent.") ?? "",
        );
      });
  };

  // Declared, not a useCallback, so the retry action can call it by name.
  function sendPicture(image: PickedMessageImage) {
    stickToBottom.current = true;
    void sendImage
      .mutateAsync({
        conversationId,
        image,
        senderId: activeUserId ?? undefined,
        localId: localMessageId(),
      })
      .catch((error: unknown) => {
        Alert.alert(
          "Picture not sent",
          errorMessage(error, "That picture could not be sent.") ?? "",
          [
            { text: "Cancel", style: "cancel" },
            // The picked file is still on the phone and already shrunk, so a
            // retry costs the upload and nothing else.
            { text: "Try again", onPress: () => sendPicture(image) },
          ],
        );
      });
  }

  const attachPicture = (source: "library" | "camera") => {
    void (async () => {
      try {
        const image = await pickMessageImage(source);
        if (!image) return;
        sendPicture(image);
      } catch (error) {
        Alert.alert(
          "Picture not sent",
          errorMessage(error, "That picture could not be sent.") ?? "",
        );
      }
    })();
  };

  const onAttach = () => {
    Alert.alert("Send a picture", undefined, [
      { text: "Take a photo", onPress: () => attachPicture("camera") },
      { text: "Choose from library", onPress: () => attachPicture("library") },
      { text: "Cancel", style: "cancel" },
    ]);
  };

  /**
   * The long-press menu. Open-ness is held apart from the message so the sheet
   * still has something to draw while it slides away.
   */
  const [menuMessage, setMenuMessage] = useState<MessageRow | null>(null);
  const [menuOpen, setMenuOpen] = useState(false);
  const openMessageMenu = useCallback((message: MessageRow) => {
    setMenuMessage(message);
    setMenuOpen(true);
  }, []);
  const closeMessageMenu = useCallback(() => setMenuOpen(false), []);

  const menuActions = useMemo<ActionSheetAction[]>(() => {
    const message = menuMessage;
    if (!message) return [];
    const mine = message.sender_id === activeUserId && !message.deleted_at;
    const actions: ActionSheetAction[] = [];

    if (message.body) {
      actions.push({
        label: "Copy",
        icon: "copy-outline",
        onPress: () => {
          void copyText(message.body ?? "").then((copied) => {
            if (!copied) Alert.alert("This build cannot copy text.");
          });
        },
      });
    }

    // Everything below names a row the server has; a message still on its
    // way out has no id to send and would fail on every one of them.
    if (message.pending) return actions;

    actions.push({
      label: "Info",
      icon: "information-circle-outline",
      onPress: () =>
        Alert.alert(
          "Message info",
          [
            `Sent ${formatChicagoShortDate(new Date(message.created_at))} at ${formatChicagoTime(new Date(message.created_at))}`,
            message.delivered_at
              ? `Delivered ${formatChicagoTime(new Date(message.delivered_at))}`
              : "Not delivered yet",
            message.read_at
              ? `Read ${formatChicagoTime(new Date(message.read_at))}`
              : "Not read yet",
          ].join("\n"),
        ),
    });

    // Available on any message: hiding your own view of something is not the
    // same as retracting it, and only the second needs to be your message.
    actions.push({
      label: "Delete for me",
      icon: "eye-off-outline",
      destructive: true,
      onPress: () =>
        hideForMe.mutate(
          { messageId: message.id, conversationId },
          {
            onError: (error) =>
              Alert.alert(
                "Not removed",
                errorMessage(error, "That message could not be removed.") ?? "",
              ),
          },
        ),
    });

    if (mine) {
      actions.push({
        label: "Delete for everyone",
        icon: "trash-outline",
        destructive: true,
        // A row in a list is far easier to hit than a native alert button, and
        // this one cannot be taken back, so it asks first.
        confirm: {
          title: "Delete for everyone?",
          message:
            "This message will be replaced with “This message was deleted” for both of you. It cannot be undone.",
          confirmLabel: "Delete for everyone",
        },
        onPress: () =>
          removeMessage.mutate(message.id, {
            onError: (error) =>
              Alert.alert(
                "Not deleted",
                errorMessage(error, "That message could not be deleted.") ?? "",
              ),
          }),
      });
    }

    return actions;
  }, [
    activeUserId,
    conversationId,
    hideForMe.mutate,
    menuMessage,
    removeMessage.mutate,
  ]);

  /**
   * The search bar takes the whole width of the header row, so the native one
   * steps aside rather than trying to fit a field between a back button and a
   * pair of arrows. Closing puts the avatar and name back untouched.
   */
  useLayoutEffect(() => {
    if (searchOpen) {
      navigation.setOptions({ headerShown: false });
      return;
    }
    navigation.setOptions({
      headerShown: true,
      headerTitle: () => (
        <Pressable
          className="flex-row items-center"
          accessibilityRole="button"
          accessibilityLabel={`Open ${peer.data?.name ?? name}'s profile`}
          onPress={() => navigation.navigate("DevoteeProfile", { devoteeId })}
        >
          <Avatar
            name={peer.data?.name ?? name}
            photoUrl={peer.data?.photo_url}
            size="tiny"
          />
          <Text
            className="ml-2 max-w-[190px] font-serif text-lg text-stone"
            numberOfLines={1}
          >
            {peer.data?.name ?? name}
          </Text>
        </Pressable>
      ),
      headerRight: () => (
        <Pressable
          className="h-11 w-11 items-center justify-center"
          accessibilityRole="button"
          accessibilityLabel="Search this conversation"
          hitSlop={6}
          onPress={openSearch}
        >
          <Ionicons name="search" size={20} color={tokens.colors.indigo} />
        </Pressable>
      ),
    });
  }, [devoteeId, name, navigation, openSearch, peer.data, searchOpen]);

  const renderItem = useCallback(
    ({ item, index }: ListRenderItemInfo<MessageRow>) => {
      const matched = matchIds.has(item.id);
      return (
        <ChatRow
          message={item}
          previousCreatedAt={rows[index - 1]?.created_at}
          isMine={item.sender_id === activeUserId}
          onLongPress={openMessageMenu}
          onOpenImage={setViewingImage}
          // Undefined on a row with no hit in it, so its props are unchanged
          // from the last keystroke and ChatRow's memo returns immediately.
          highlight={matched ? term : undefined}
          isCurrentMatch={matched && item.id === currentMatchId}
        />
      );
    },
    [activeUserId, currentMatchId, matchIds, openMessageMenu, rows, term],
  );

  const peerName = peer.data?.name ?? name;

  return (
    <SafeAreaView
      ref={rootRef}
      onLayout={measureHeader}
      className="flex-1 bg-ivory"
      // With the header stepped aside for the search bar, the top inset is
      // this screen's to hold.
      edges={searchOpen ? ["top", "bottom"] : ["bottom"]}
    >
      <KeyboardAvoidingView
        className="flex-1"
        behavior={Platform.OS === "ios" ? "padding" : "height"}
        keyboardVerticalOffset={Platform.OS === "ios" ? headerOffset : 0}
      >
        {searchOpen ? (
          <View className="flex-row items-center border-b border-border bg-white px-1 py-1.5">
            <Pressable
              className="h-11 w-11 items-center justify-center rounded-pill"
              accessibilityRole="button"
              accessibilityLabel="Close search"
              hitSlop={6}
              onPress={closeSearch}
            >
              <Ionicons
                name="arrow-back"
                size={22}
                color={tokens.colors.indigo}
              />
            </Pressable>
            <TextInput
              className="mx-1 h-11 flex-1 rounded-card border border-border bg-ivory px-4 font-sans text-base text-stone"
              value={query}
              onChangeText={setQuery}
              placeholder="Search this conversation"
              placeholderTextColor={tokens.colors.stoneMuted}
              autoFocus
              autoCorrect={false}
              returnKeyType="search"
              onSubmitEditing={goOlder}
              accessibilityLabel="Search this conversation"
            />
            {term ? (
              <Text
                className="w-12 text-center font-sans text-xs text-stoneMuted"
                accessibilityLiveRegion="polite"
                accessibilityLabel={
                  matches.length
                    ? `Match ${matchIndex + 1} of ${matches.length}`
                    : "No matches"
                }
              >
                {matches.length ? `${matchIndex + 1}/${matches.length}` : "0/0"}
              </Text>
            ) : null}
            <Pressable
              className="h-11 w-9 items-center justify-center"
              accessibilityRole="button"
              accessibilityLabel="Earlier match"
              accessibilityState={{ disabled: matchIndex <= 0 }}
              hitSlop={6}
              disabled={matchIndex <= 0}
              onPress={goOlder}
            >
              <Ionicons
                name="chevron-up"
                size={22}
                color={
                  matchIndex > 0 ? tokens.colors.indigo : tokens.colors.border
                }
              />
            </Pressable>
            <Pressable
              className="h-11 w-9 items-center justify-center"
              accessibilityRole="button"
              accessibilityLabel="Later match"
              accessibilityState={{
                disabled: matchIndex < 0 || matchIndex >= matches.length - 1,
              }}
              hitSlop={6}
              disabled={matchIndex < 0 || matchIndex >= matches.length - 1}
              onPress={goNewer}
            >
              <Ionicons
                name="chevron-down"
                size={22}
                color={
                  matchIndex >= 0 && matchIndex < matches.length - 1
                    ? tokens.colors.indigo
                    : tokens.colors.border
                }
              />
            </Pressable>
          </View>
        ) : null}

        <FlatList
          ref={listRef}
          className="flex-1"
          data={rows}
          onContentSizeChange={onContentSizeChange}
          onScroll={onScroll}
          onScrollBeginDrag={onScrollBeginDrag}
          onScrollToIndexFailed={onScrollToIndexFailed}
          scrollEventThrottle={16}
          keyExtractor={keyExtractor}
          renderItem={renderItem}
          contentContainerClassName="pb-1 pt-3"
          showsVerticalScrollIndicator={false}
          keyboardShouldPersistTaps="handled"
          keyboardDismissMode="interactive"
          initialNumToRender={14}
          maxToRenderPerBatch={10}
          updateCellsBatchingPeriod={40}
          windowSize={9}
          ListEmptyComponent={
            messages.isLoading ? null : (
              <View className="items-center px-screen py-10">
                <Ionicons
                  name="chatbubble-ellipses-outline"
                  size={30}
                  color={tokens.colors.peacock}
                />
                <Text className="mt-3 text-center font-sans-bold text-base text-stone">
                  No messages yet
                </Text>
                <Text className="mt-1 text-center font-sans text-sm text-stoneMuted">
                  Say Hare Kṛṣṇa to {name}.
                </Text>
              </View>
            )
          }
        />

        {messages.error ? (
          <View className="flex-row items-center border-t border-border bg-white px-screen py-2">
            <Ionicons
              name="alert-circle-outline"
              size={16}
              color={tokens.colors.vermilion}
            />
            <Text className="ml-2 font-sans text-xs text-vermilion">
              This conversation could not be loaded.
            </Text>
          </View>
        ) : null}

        {/* The composer stands down while search is open: two fields on one
            screen, both wanting the keyboard, is a fight nobody wins. The
            draft is held in state and comes back with it. */}
        {searchOpen ? null : (
          <>
            {/* Sits on the composer's shoulder, and holds its height whether or
            not anyone is typing so the thread never jumps under the reader. */}
            <View
              className="h-7 items-start justify-end px-screen pb-1"
              pointerEvents="none"
              accessibilityLiveRegion="polite"
            >
              {isPeerTyping ? (
                <TypingDots label={`${peerName} is typing`} />
              ) : null}
            </View>

            <View className="flex-row items-end border-t border-border bg-white px-2 pb-2 pt-1.5">
              <Pressable
                className="h-11 w-11 items-center justify-center rounded-pill"
                accessibilityRole="button"
                accessibilityLabel={`Send a picture to ${peerName}`}
                hitSlop={6}
                onPress={onAttach}
              >
                <Ionicons
                  name="image-outline"
                  size={22}
                  color={tokens.colors.indigo}
                />
              </Pressable>
              <TextInput
                className="mx-1 max-h-28 min-h-11 flex-1 rounded-card border border-border bg-ivory px-4 py-2.5 font-sans text-base text-stone"
                value={draft}
                onChangeText={onChangeDraft}
                placeholder={`Message ${peerName}`}
                placeholderTextColor={tokens.colors.stoneMuted}
                // Grows to about four lines and then scrolls, so a long message
                // never pushes the thread off a short screen.
                multiline
                accessibilityLabel={`Message ${peerName}`}
              />
              <Pressable
                className={`h-11 w-11 items-center justify-center rounded-pill ${
                  canSend ? "bg-indigo" : "bg-indigoSoft"
                }`}
                accessibilityRole="button"
                accessibilityLabel="Send message"
                accessibilityState={{ disabled: !canSend }}
                hitSlop={6}
                disabled={!canSend}
                onPress={onSend}
              >
                <Ionicons
                  name="send"
                  size={18}
                  color={canSend ? tokens.colors.white : tokens.colors.indigo}
                />
              </Pressable>
            </View>
          </>
        )}
      </KeyboardAvoidingView>
      <Modal
        visible={viewingImage !== null}
        transparent
        animationType="fade"
        onRequestClose={() => setViewingImage(null)}
      >
        <Pressable
          className="flex-1 items-center justify-center bg-black/95"
          accessibilityRole="button"
          accessibilityLabel="Close the picture"
          onPress={() => setViewingImage(null)}
        >
          {viewingImage ? (
            <RemoteImage
              uri={viewingImage}
              style={{ width: "100%", height: "80%" }}
              resizeMode="contain"
              accessibilityIgnoresInvertColors
            />
          ) : null}
        </Pressable>
      </Modal>
      <ActionSheet
        visible={menuOpen}
        title="Message"
        message={
          menuMessage?.pending ? "This message is still being sent." : undefined
        }
        actions={menuActions}
        onClose={closeMessageMenu}
      />
    </SafeAreaView>
  );
}
