import { Ionicons } from "@expo/vector-icons";
import { useNavigation, type NavigationProp } from "@react-navigation/native";
import { Alert, Pressable, Text, View } from "react-native";
import { Swipeable } from "react-native-gesture-handler";

import tokens from "../../design-tokens.json";
import {
  Avatar,
  ListScreen,
  ScreenTitle,
  UnreadBadge,
  unreadLabel,
} from "../components/ui";
import {
  useConversations,
  useRemoveConversationForMe,
} from "../features/messaging/hooks";
import type { ConversationSummary } from "../features/messaging/types";
import { AtTempleBadge } from "../features/presence/components";
import { FormError } from "../features/services/components";
import { formatChicagoShortDate } from "../lib/chicagoDate";
import type { DevoteesStackParamList } from "../navigation/types";
import { usePrototypeSession } from "../store/usePrototypeSession";

const MINUTE = 60_000;
const HOUR = 60 * MINUTE;
const DAY = 24 * HOUR;

/** Short and glanceable: a conversation list is scanned, not read. */
export function formatConversationTime(value: string) {
  const at = new Date(value);
  if (Number.isNaN(at.getTime())) return "";
  const elapsed = Date.now() - at.getTime();
  if (elapsed < MINUTE) return "Now";
  if (elapsed < HOUR) return `${Math.floor(elapsed / MINUTE)}m`;
  if (elapsed < DAY) return `${Math.floor(elapsed / HOUR)}h`;
  if (elapsed < 7 * DAY) return `${Math.floor(elapsed / DAY)}d`;
  return formatChicagoShortDate(at);
}

export function conversationPreview(
  row: ConversationSummary,
  viewerId: string | null,
) {
  if (row.last_deleted) return "Message deleted";
  const mine = Boolean(viewerId) && row.last_sender_id === viewerId;
  if (row.last_body) return mine ? `You: ${row.last_body}` : row.last_body;
  if (row.last_has_image) return mine ? "You: Photo" : "Photo";
  return "Say Hare Kṛṣṇa";
}

/**
 * A conversation in the list. Rows are stacked into one card, so the borders
 * are drawn per row and only the ends are rounded.
 */
export function ConversationRow({
  row,
  viewerId,
  isFirst,
  isLast,
  atTemple = false,
  onPress,
  onRemove,
}: {
  row: ConversationSummary;
  viewerId: string | null;
  isFirst: boolean;
  isLast: boolean;
  /** Whether the other devotee is on today's temple presence list. */
  atTemple?: boolean;
  onPress: () => void;
  /** Removes this thread from the current devotee's inbox, not the record. */
  onRemove?: () => void;
}) {
  const unread = row.unread_count > 0;
  const preview = conversationPreview(row, viewerId);
  const label = `Open the conversation with ${row.other_name}${unreadLabel(
    row.unread_count,
  )}${atTemple ? ", at the temple today" : ""}`;

  const content = (
    <Pressable
      className="min-h-[76px] flex-row items-center bg-white px-card py-3"
      accessibilityRole="button"
      accessibilityLabel={label}
      accessibilityHint={
        onRemove ? "Swipe left to remove this conversation" : undefined
      }
      onPress={onPress}
    >
      <Avatar
        name={row.other_name}
        photoUrl={row.other_photo_url}
        tone={unread ? "peacock" : "indigo"}
      />
      <View className="ml-4 min-w-0 flex-1">
        <Text className="font-sans-bold text-lg text-stone" numberOfLines={1}>
          {row.other_name}
        </Text>
        <Text
          className={`mt-0.5 font-sans text-sm ${
            unread ? "text-stone" : "text-stoneMuted"
          } ${row.last_deleted ? "italic" : ""}`}
          numberOfLines={1}
        >
          {preview}
        </Text>
      </View>
      {atTemple ? <AtTempleBadge /> : null}
      <View className="ml-3 shrink-0 items-end">
        <Text className="font-sans text-xs text-stoneMuted">
          {formatConversationTime(row.last_message_at)}
        </Text>
        {unread ? (
          <View className="mt-1.5">
            <UnreadBadge count={row.unread_count} />
          </View>
        ) : null}
      </View>
    </Pressable>
  );

  return (
    <View
      className={`overflow-hidden border-x border-border bg-white ${
        isFirst ? "rounded-t-card border-t" : ""
      } ${isLast ? "rounded-b-card border-b" : "border-b"}`}
    >
      {onRemove ? (
        <Swipeable
          overshootRight={false}
          renderRightActions={() => (
            <Pressable
              className="w-24 items-center justify-center bg-vermilion"
              accessibilityRole="button"
              accessibilityLabel={`Remove conversation with ${row.other_name}`}
              onPress={onRemove}
            >
              <Ionicons
                name="trash-outline"
                size={21}
                color={tokens.colors.white}
              />
              <Text className="mt-1 font-sans-bold text-xs text-white">
                Remove
              </Text>
            </Pressable>
          )}
        >
          {content}
        </Swipeable>
      ) : (
        content
      )}
    </View>
  );
}

export function ConversationsEmpty() {
  return (
    <View className="items-center rounded-card border border-border bg-white px-card py-8">
      <Ionicons
        name="chatbubbles-outline"
        size={30}
        color={tokens.colors.peacock}
      />
      <Text className="mt-3 text-center font-sans-bold text-base text-stone">
        No messages yet
      </Text>
      <Text className="mt-1 text-center font-sans text-sm text-stoneMuted">
        Open a devotee from the Directory and write the first line.
      </Text>
    </View>
  );
}

/** The conversation list on its own, newest activity first. */
export function ConversationsScreen() {
  const navigation = useNavigation<NavigationProp<DevoteesStackParamList>>();
  const activeUserId = usePrototypeSession((state) => state.activeUserId);
  const conversations = useConversations();
  const removeConversation = useRemoveConversationForMe();
  // The RPC already orders by last_message_at, newest first.
  const rows: ConversationSummary[] = conversations.data ?? [];

  return (
    <ListScreen
      data={rows}
      keyExtractor={(row) => row.id}
      header={<ScreenTitle eyebrow="Your conversations">Messages</ScreenTitle>}
      renderItem={(row, index) => (
        <ConversationRow
          row={row}
          viewerId={activeUserId}
          isFirst={index === 0}
          isLast={index === rows.length - 1}
          onPress={() =>
            navigation.navigate("Chat", {
              conversationId: row.id,
              devoteeId: row.other_devotee_id,
              name: row.other_name,
            })
          }
          onRemove={() =>
            Alert.alert(
              `Remove conversation with ${row.other_name}?`,
              "It will disappear from your Messages. The temple’s retained record is not erased, and a new message will bring the conversation back.",
              [
                { text: "Cancel", style: "cancel" },
                {
                  text: "Remove",
                  style: "destructive",
                  onPress: () =>
                    removeConversation.mutate(row.id, {
                      onError: () =>
                        Alert.alert(
                          "Conversation not removed",
                          "Please check your connection and try again.",
                        ),
                    }),
                },
              ],
            )
          }
        />
      )}
      empty={conversations.isLoading ? null : <ConversationsEmpty />}
      footer={
        conversations.error ? (
          <FormError message="Your conversations could not be loaded." />
        ) : null
      }
    />
  );
}
