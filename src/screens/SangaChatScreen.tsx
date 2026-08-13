import { Ionicons } from "@expo/vector-icons";
import { useIsFocused } from "@react-navigation/native";
import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import {
  memo,
  useCallback,
  useEffect,
  useLayoutEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import {
  ActivityIndicator,
  Alert,
  Animated,
  Dimensions,
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
import { Avatar, LoadFailure, Skeleton } from "../components/ui";
import { memberCountLabel } from "../features/sanga/components";
import {
  pickMessageImage,
  sangaTypingLabel,
  useDeleteSangaMessage,
  useMarkSangaRead,
  useSangaMessages,
  useSangaMessagesRealtime,
  useSangaRealtime,
  useSangaTypingIndicator,
  useSangaViewer,
  useSendSangaMessage,
  useSendSangaMessageImage,
} from "../features/sanga/hooks";
import type {
  PickedMessageImage,
  SangaMessage,
  SangaViewerCapabilities,
} from "../features/sanga/types";
import { errorMessage } from "../features/services/format";
import {
  formatChicagoShortDate,
  formatChicagoTime,
  getChicagoDateKey,
} from "../lib/chicagoDate";
import { useServerReachable } from "../lib/connectivity";
import { copyText } from "../lib/copyText";
import { sharePicture } from "../lib/sharePicture";
import type { DevoteesStackParamList } from "../navigation/types";

type Props = NativeStackScreenProps<DevoteesStackParamList, "SangaChat">;

/**
 * A picture never grows past this, however large the original is. Tied to the
 * screen rather than fixed: a group bubble also gives up a column to the
 * sender's face, so a flat 220 overflows the bubble on the narrowest phones.
 */
const IMAGE_WIDTH = Math.min(
  220,
  Math.round(Dimensions.get("window").width * 0.6),
);
const IMAGE_RADIUS = 16;

/** The gutter a group's avatar sits in, held open under the bubbles below it. */
const AVATAR_GUTTER = 40;

/** How close to the foot of the thread still counts as "reading the latest". */
const STICK_TO_BOTTOM_SLACK = 120;

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
 * Three dots lifting in turn, as in the one-to-one thread. Only opacity and
 * translateY move, so the whole loop is handed to the native driver and keeps
 * running while the JS thread is busy rendering arriving messages.
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
 * Two states, not the four a direct message carries: a sanga message is
 * addressed to a circle, and there is no one devotee whose reading of it would
 * make "read" mean anything. So the tick says only that it left the phone.
 */
function SentTick({ message }: { message: SangaMessage }) {
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
  return (
    <Ionicons
      name="checkmark"
      size={14}
      color={tokens.colors.stoneMuted}
      accessibilityLabel="Sent"
    />
  );
}

const URL_SPLIT = /(https?:\/\/[^\s]+)/g;
// Deliberately not the /g one: a global regex keeps lastIndex between calls,
// so testing each part with it would match every other link.
const IS_URL = /^https?:\/\/[^\s]+$/;

function MessageText({
  body,
  mine,
  padding,
}: {
  body: string;
  mine: boolean;
  padding: string;
}) {
  return (
    <Text
      className={`font-sans text-base leading-6 ${padding} ${mine ? "text-white" : "text-stone"}`}
    >
      {body.split(URL_SPLIT).map((part, index) =>
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
            {part}
          </Text>
        ) : (
          part
        ),
      )}
    </Text>
  );
}

type RowProps = {
  message: SangaMessage;
  isMine: boolean;
  /** The message drawn above this one, or undefined at the top of the thread. */
  previous: SangaMessage | undefined;
  /** Takes the message rather than closing over it, so a row's handlers stay
   * identical between renders and React.memo can do its job. */
  onLongPress: (message: SangaMessage) => void;
  onOpenImage: (url: string) => void;
  onOpenSender: (senderId: string) => void;
};

const SangaRow = memo(function SangaRow({
  message,
  isMine,
  previous,
  onLongPress,
  onOpenImage,
  onOpenSender,
}: RowProps) {
  const at = new Date(message.created_at);
  // The separator belongs to the first message of each day.
  const startsDay =
    !previous ||
    getChicagoDateKey(new Date(previous.created_at)) !== getChicagoDateKey(at);
  /**
   * A run of messages from one devotee is drawn as one block: the face and the
   * name once at its head, and nothing repeated under it. Your own messages
   * never carry either — the side they sit on already says who wrote them.
   */
  const startsGroup =
    !isMine &&
    (startsDay || !previous || previous.sender_id !== message.sender_id);
  const sender = message.sender_name?.trim() || "A devotee";

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
  const handleOpenSender = useCallback(
    () => onOpenSender(message.sender_id),
    [message.sender_id, onOpenSender],
  );

  return (
    <View className="px-screen">
      {startsDay ? <DaySeparator at={at} /> : null}
      <View
        className={`flex-row items-start ${startsGroup || startsDay ? "mt-2.5" : "mt-0.5"} ${
          isMine ? "justify-end" : ""
        }`}
      >
        {isMine ? null : (
          // Held open under the rest of the group too, so a run of messages
          // stays in one column instead of stepping left at the second bubble.
          <View style={{ width: AVATAR_GUTTER }}>
            {startsGroup ? (
              <Avatar
                name={sender}
                photoUrl={message.sender_photo_url}
                size="tiny"
                onPress={handleOpenSender}
              />
            ) : null}
          </View>
        )}
        {/* The width cap lives here rather than on the bubble: a percentage
            against a content-sized parent resolves to nothing, and this View is
            a row child with the screen's width behind it. */}
        <View
          className={`min-w-0 max-w-[78%] shrink ${isMine ? "items-end" : "items-start"}`}
        >
          <Pressable
            className={`${hasImage && !isDeleted ? "p-1" : "px-4 py-2.5"} ${
              isMine
                ? "rounded-card rounded-br-md bg-indigo"
                : "rounded-card rounded-bl-md border border-border bg-white"
            }`}
            accessibilityRole="text"
            accessibilityLabel={
              isDeleted
                ? `${isMine ? "You" : sender} deleted a message`
                : `${isMine ? "You" : sender} said ${message.body ?? "a picture"}`
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
              hasImage && !isDeleted && !isUploading
                ? handleOpenImage
                : undefined
            }
            onLongPress={handleLongPress}
            delayLongPress={350}
          >
            {startsGroup ? (
              <Text
                className={`font-sans-bold text-xs text-peacock ${hasImage ? "px-2 pb-1 pt-1" : "pb-0.5"}`}
                numberOfLines={1}
                accessibilityRole="button"
                accessibilityLabel={`Open ${sender}'s profile`}
                onPress={handleOpenSender}
              >
                {sender}
              </Text>
            ) : null}

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
                    <Image
                      source={{ uri: message.image_url }}
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
                <SentTick message={message} />
              </View>
            ) : null}
          </View>
        </View>
      </View>
    </View>
  );
});

const keyExtractor = (message: SangaMessage) => message.id;

/** Bubbles in the shape of the real ones, so a loading thread is not an empty
 * one. */
function ThreadSkeleton() {
  return (
    <View className="px-screen pt-2">
      {[
        { mine: false, width: "62%" },
        { mine: true, width: "48%" },
        { mine: false, width: "72%" },
        { mine: false, width: "40%" },
      ].map((row, index) => (
        <View
          key={index}
          className={`mt-3 ${row.mine ? "items-end" : "items-start"}`}
        >
          <Skeleton height={46} width={row.width} />
        </View>
      ))}
    </View>
  );
}

export function SangaChatScreen({ navigation, route }: Props) {
  const { sangaId, name } = route.params;
  const isFocused = useIsFocused();
  const reachable = useServerReachable();
  const viewer = useSangaViewer(sangaId);
  const capabilities: SangaViewerCapabilities = viewer.capabilities;
  const { activeUserId, selfName, selfPhotoUrl } = viewer;

  const sangaName = viewer.summary?.name ?? name;
  const [draft, setDraft] = useState("");
  const [viewingImage, setViewingImage] = useState<string | null>(null);

  const messages = useSangaMessages(sangaId);
  useSangaMessagesRealtime(sangaId);
  // The roll behind the header count and behind every sender's name, kept
  // live: somebody added while the thread is open should be named in it
  // straight away rather than after a trip out of the screen and back.
  useSangaRealtime(sangaId);
  const { typists, notifyTyping, notifyStoppedTyping } =
    useSangaTypingIndicator(sangaId, activeUserId, selfName);
  const send = useSendSangaMessage();
  const sendImage = useSendSangaMessageImage(activeUserId);
  const removeMessage = useDeleteSangaMessage();
  const markRead = useMarkSangaRead();

  // list_sanga_messages already answers oldest first, and the cache keeps it
  // that way through every optimistic write, so there is nothing to re-sort.
  const rows = messages.data ?? [];
  const threadFailed = messages.isError && messages.data === undefined;
  const typingLabel = sangaTypingLabel(typists);

  /**
   * Covers both halves of the requirement, as ChatScreen does for a one-to-one
   * thread: opening the sanga with something unread, and a message arriving
   * while it is on screen.
   *
   * The newest message's id is the trigger, because a sanga carries no
   * per-viewer read state on the messages themselves — the watermark is the
   * whole record, so there is nothing on a row to say whether it has been seen.
   * The RPC answers 0 when there was nothing to clear, and the hook leaves the
   * lists alone in that case, so this settles after one call per message.
   *
   * Members only. A President reading over the top through app.view_all has no
   * watermark in a circle they are not in, and the server refuses them.
   */
  const newestMessageId = rows.at(-1)?.id ?? null;
  useEffect(() => {
    if (!isFocused || !capabilities.isMember || !newestMessageId) return;
    markRead.mutate(sangaId);
    // Only the sanga, its newest message and focus should retrigger this — not
    // the mutation object, which is new on every render.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [capabilities.isMember, isFocused, newestMessageId, sangaId]);

  /**
   * KeyboardAvoidingView measures its own frame relative to its parent, so on
   * a screen sitting below a navigation header it lifts the composer by the
   * header's height too little and the keyboard covers it. The gap above the
   * screen is measured instead.
   */
  const rootRef = useRef<View>(null);
  const listRef = useRef<FlatList<SangaMessage>>(null);
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
  const onScroll = useCallback(
    (event: NativeSyntheticEvent<NativeScrollEvent>) => {
      const { contentOffset, contentSize, layoutMeasurement } =
        event.nativeEvent;
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

  const openSender = useCallback(
    (devoteeId: string) => navigation.navigate("DevoteeProfile", { devoteeId }),
    [navigation],
  );

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
        sangaId,
        body,
        senderId: activeUserId ?? undefined,
        senderName: selfName,
        senderPhotoUrl: selfPhotoUrl,
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
        sangaId,
        image,
        senderId: activeUserId ?? undefined,
        senderName: selfName,
        senderPhotoUrl: selfPhotoUrl,
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

  const savePicture = useCallback((url: string) => {
    void sharePicture(url).catch((error: unknown) => {
      Alert.alert(
        "Picture not saved",
        errorMessage(error, "That picture could not be saved.") ?? "",
      );
    });
  }, []);

  /**
   * The long-press menu. Open-ness is held apart from the message so the sheet
   * still has something to draw while it slides away.
   */
  const [menuMessage, setMenuMessage] = useState<SangaMessage | null>(null);
  const [menuOpen, setMenuOpen] = useState(false);
  const openMessageMenu = useCallback((message: SangaMessage) => {
    setMenuMessage(message);
    setMenuOpen(true);
  }, []);
  const closeMessageMenu = useCallback(() => setMenuOpen(false), []);

  const menuActions = useMemo<ActionSheetAction[]>(() => {
    const message = menuMessage;
    if (!message) return [];
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

    if (message.image_url && !message.deleted_at) {
      actions.push({
        label: "Save picture",
        icon: "download-outline",
        onPress: () => savePicture(message.image_url ?? ""),
      });
    }

    // Everything below names a row the server has; a message still on its way
    // out has no id to send and would fail on every one of them.
    if (message.pending) return actions;

    actions.push({
      label: "Info",
      icon: "information-circle-outline",
      onPress: () =>
        Alert.alert(
          "Message info",
          [
            `From ${message.sender_name?.trim() || "a devotee"}`,
            `Sent ${formatChicagoShortDate(new Date(message.created_at))} at ${formatChicagoTime(new Date(message.created_at))}`,
            message.deleted_at
              ? `Deleted ${formatChicagoTime(new Date(message.deleted_at))}`
              : null,
          ]
            .filter(Boolean)
            .join("\n"),
        ),
    });

    // Anybody may take down their own; the sanga's admin and the President may
    // take down anyone's.
    const mine = message.sender_id === activeUserId;
    const mayDelete =
      !message.deleted_at && (mine || capabilities.canDeleteAnyMessage);
    if (mayDelete) {
      actions.push({
        label: mine ? "Delete for everyone" : "Delete this message",
        icon: "trash-outline",
        destructive: true,
        // A row in a list is far easier to hit than a native alert button, and
        // this one cannot be taken back, so it asks first.
        confirm: {
          title: "Delete for everyone?",
          message:
            "This message will be replaced with “This message was deleted” for everyone in the sanga. It cannot be undone.",
          confirmLabel: "Delete for everyone",
        },
        onPress: () =>
          removeMessage.mutate(
            { messageId: message.id },
            {
              onError: (error) =>
                Alert.alert(
                  "Not deleted",
                  errorMessage(error, "That message could not be deleted.") ??
                    "",
                ),
            },
          ),
      });
    }

    return actions;
  }, [
    activeUserId,
    capabilities.canDeleteAnyMessage,
    menuMessage,
    removeMessage.mutate,
    savePicture,
  ]);

  /**
   * The sanga's name over its size, and tapping it opens what the sanga is:
   * its description, who is in it, and everything that can be done about it.
   * That is the one place those live now, which is why the header title is a
   * button and there is no second control beside it.
   */
  useLayoutEffect(() => {
    const openInfo = () =>
      navigation.navigate("SangaInfo", { sangaId, name: sangaName });

    navigation.setOptions({
      headerTitle: () => (
        <Pressable
          className="max-w-[220px] items-center"
          accessibilityRole="button"
          accessibilityLabel={`About ${sangaName}, and who is in it`}
          onPress={openInfo}
        >
          <Text className="font-display text-lg text-stone" numberOfLines={1}>
            {sangaName}
          </Text>
          {viewer.memberCount === null ? null : (
            <Text className="font-sans text-xs text-stoneMuted">
              {memberCountLabel(viewer.memberCount)}
            </Text>
          )}
        </Pressable>
      ),
      headerRight: () => (
        <Pressable
          className="h-11 w-11 items-center justify-center"
          accessibilityRole="button"
          accessibilityLabel={`About ${sangaName}`}
          hitSlop={6}
          onPress={openInfo}
        >
          <Ionicons
            name="information-circle-outline"
            size={22}
            color={tokens.colors.indigo}
          />
        </Pressable>
      ),
    });
  }, [navigation, sangaId, sangaName, viewer.memberCount]);

  const renderItem = useCallback(
    ({ item, index }: ListRenderItemInfo<SangaMessage>) => (
      <SangaRow
        message={item}
        previous={rows[index - 1]}
        isMine={item.sender_id === activeUserId}
        onLongPress={openMessageMenu}
        onOpenImage={setViewingImage}
        onOpenSender={openSender}
      />
    ),
    [activeUserId, openMessageMenu, openSender, rows],
  );

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
        <FlatList
          ref={listRef}
          className="flex-1"
          data={rows}
          onContentSizeChange={onContentSizeChange}
          onScroll={onScroll}
          onScrollBeginDrag={onScrollBeginDrag}
          scrollEventThrottle={16}
          keyExtractor={keyExtractor}
          renderItem={renderItem}
          contentContainerClassName="pb-1 pt-1"
          showsVerticalScrollIndicator={false}
          keyboardShouldPersistTaps="handled"
          keyboardDismissMode="interactive"
          initialNumToRender={14}
          maxToRenderPerBatch={10}
          updateCellsBatchingPeriod={40}
          windowSize={9}
          ListEmptyComponent={
            messages.isLoading ? (
              <ThreadSkeleton />
            ) : threadFailed ? (
              <View className="px-screen pt-4">
                <LoadFailure
                  reachable={reachable}
                  message={errorMessage(
                    messages.error,
                    "This thread could not be loaded.",
                  )}
                  onRetry={() => void messages.refetch()}
                />
              </View>
            ) : (
              <View className="items-center px-screen py-10">
                <Ionicons
                  name="chatbubbles-outline"
                  size={30}
                  color={tokens.colors.peacock}
                />
                <Text className="mt-3 text-center font-sans-bold text-base text-stone">
                  No messages yet
                </Text>
                <Text className="mt-1 text-center font-sans text-sm text-stoneMuted">
                  {capabilities.canPost
                    ? `Say Hare Krsna to ${sangaName}.`
                    : `Nothing has been said in ${sangaName}.`}
                </Text>
              </View>
            )
          }
        />

        {capabilities.canPost ? (
          <>
            {/* Sits on the composer's shoulder, and holds its height whether or
            not anyone is typing so the thread never jumps under the reader. */}
            <View
              className="h-7 flex-row items-center px-screen pb-1"
              pointerEvents="none"
              accessibilityLiveRegion="polite"
            >
              {typingLabel ? (
                <>
                  <TypingDots label={typingLabel} />
                  <Text
                    className="ml-2 min-w-0 flex-1 font-sans text-xs text-stoneMuted"
                    numberOfLines={1}
                  >
                    {typingLabel}
                  </Text>
                </>
              ) : null}
            </View>

            <View className="flex-row items-end border-t border-border bg-white px-2 pb-2 pt-1.5">
              <Pressable
                className="h-11 w-11 items-center justify-center rounded-pill"
                accessibilityRole="button"
                accessibilityLabel={`Send a picture to ${sangaName}`}
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
                placeholder={`Message ${sangaName}`}
                placeholderTextColor={tokens.colors.stoneMuted}
                // Grows to about four lines and then scrolls, so a long message
                // never pushes the thread off a short screen.
                multiline
                accessibilityLabel={`Message ${sangaName}`}
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
        ) : null}
      </KeyboardAvoidingView>

      <Modal
        visible={viewingImage !== null}
        transparent
        animationType="fade"
        onRequestClose={() => setViewingImage(null)}
      >
        <View className="flex-1 bg-black/95">
          <Pressable
            className="flex-1 items-center justify-center"
            accessibilityRole="button"
            accessibilityLabel="Close the picture"
            onPress={() => setViewingImage(null)}
          >
            {viewingImage ? (
              <Image
                source={{ uri: viewingImage }}
                style={{ width: "100%", height: "80%" }}
                resizeMode="contain"
                accessibilityIgnoresInvertColors
              />
            ) : null}
          </Pressable>
          {/* box-none, so only the button itself takes a touch and the rest of
              this band still closes the picture. */}
          <View
            className="absolute inset-x-0 bottom-0 flex-row justify-center pb-10"
            pointerEvents="box-none"
          >
            <Pressable
              className="min-h-touch flex-row items-center rounded-pill bg-white/15 px-5"
              accessibilityRole="button"
              accessibilityLabel="Save this picture"
              onPress={() => {
                if (viewingImage) savePicture(viewingImage);
              }}
            >
              <Ionicons
                name="download-outline"
                size={20}
                color={tokens.colors.white}
              />
              <Text className="ml-2 font-sans-bold text-base text-white">
                Save
              </Text>
            </Pressable>
          </View>
        </View>
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
