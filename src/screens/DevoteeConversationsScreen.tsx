import { Ionicons } from "@expo/vector-icons";
import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { File, Paths } from "expo-file-system";
import * as Sharing from "expo-sharing";
import { useCallback, useMemo, useState } from "react";
import {
  FlatList,
  Image,
  Pressable,
  Text,
  TextInput,
  useWindowDimensions,
  View,
} from "react-native";

import tokens from "../../design-tokens.json";
import {
  BotanicalBackdrop,
  ListScreen,
  LoadFailure,
  Screen,
  Skeleton,
  SkeletonCard,
} from "../components/ui";
import { useCurrentAccessProfile } from "../features/access/hooks";
import { hasAccessPermission } from "../features/access/model";
import { listConversationMessages } from "../features/messaging/api";
import type { ConversationMessageRow } from "../features/messaging/api";
import { FormError } from "../features/services/components";
import { errorMessage } from "../features/services/format";
import {
  formatChicagoShortDate,
  formatChicagoTime,
  getChicagoDateKey,
} from "../lib/chicagoDate";
import { useServerReachable } from "../lib/connectivity";
import { getSupabaseClient } from "../lib/supabase";
import type { ProfileStackParamList } from "../navigation/types";
import { usePrototypeSession } from "../store/usePrototypeSession";

type ListProps = NativeStackScreenProps<
  ProfileStackParamList,
  "DevoteeConversations"
>;
type ThreadProps = NativeStackScreenProps<
  ProfileStackParamList,
  "DevoteeConversation"
>;

type ConversationRow = {
  id: string;
  first_devotee_id: string;
  first_name: string;
  second_devotee_id: string;
  second_name: string;
  message_count: number;
  last_message_at: string;
};

/** One message, already resolved to the content the bubble should draw. */
type ThreadMessage = {
  id: string;
  senderId: string;
  senderName: string | null;
  body: string | null;
  imageUrl: string | null;
  createdAt: string;
  removed: boolean;
};

type FallbackMessageRow = {
  id: string;
  sender_id: string;
  body: string | null;
  image_url: string | null;
  created_at: string;
  deleted_at: string | null;
};

/** How many rows the list shows before "See all" is offered. */
const PREVIEW_COUNT = 6;

/** A stable empty array, so memos downstream of an unloaded query settle. */
const NO_MESSAGES: readonly ThreadMessage[] = [];

const conversationsKey = ["all-conversations"] as const;
const threadKey = (conversationId: string) =>
  ["conversation-thread", conversationId] as const;

async function fetchAllConversations(): Promise<ConversationRow[]> {
  const { data, error } = await getSupabaseClient().rpc("list_all_conversations");
  if (error) throw error;
  return (data ?? []) as ConversationRow[];
}

function toThreadMessage(row: ConversationMessageRow): ThreadMessage {
  return {
    id: row.id,
    senderId: row.sender_id,
    senderName: row.sender_name?.trim() || null,
    body: row.body ?? row.original_body,
    imageUrl: row.image_url ?? row.original_image_url,
    createdAt: row.created_at,
    removed: Boolean(row.deleted_at),
  };
}

/**
 * `list_conversation_messages` arrives with a migration a temple's database may
 * not have had applied yet; the wrapper returns null in that case and the
 * thread falls back to reading the table directly rather than failing.
 */
async function fetchThread(conversationId: string): Promise<ThreadMessage[]> {
  const rows = await listConversationMessages(conversationId);
  if (rows) {
    return rows
      .map(toThreadMessage)
      .sort((left, right) => left.createdAt.localeCompare(right.createdAt));
  }

  const { data, error } = await getSupabaseClient()
    .from("messages")
    .select("id,sender_id,body,image_url,created_at,deleted_at")
    .eq("conversation_id", conversationId)
    .order("created_at", { ascending: true })
    .returns<FallbackMessageRow[]>();
  if (error) throw error;
  return (data ?? []).map((row) => ({
    id: row.id,
    senderId: row.sender_id,
    senderName: null,
    body: row.body,
    imageUrl: row.image_url,
    createdAt: row.created_at,
    removed: Boolean(row.deleted_at),
  }));
}

function useAllConversations(enabled: boolean) {
  return useQuery({
    queryKey: conversationsKey,
    queryFn: fetchAllConversations,
    enabled,
  });
}

function escapeHtml(value: unknown) {
  return String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

async function shareWorkbook({
  fileName,
  title,
  summary,
  headings,
  rows,
  dialogTitle,
}: {
  fileName: string;
  title: string;
  summary: string;
  headings: readonly string[];
  rows: readonly (readonly string[])[];
  dialogTitle: string;
}) {
  const body = rows
    .map(
      (row) =>
        `<tr>${row.map((value) => `<td>${escapeHtml(value)}</td>`).join("")}</tr>`,
    )
    .join("");
  const workbook = `<!doctype html>
<html><head><meta charset="utf-8"><style>
body{font-family:Arial,sans-serif;color:#3A342B}h1{color:#2B3A67;margin-bottom:4px}
.summary{margin:0 0 18px;color:#6B6355}table{border-collapse:collapse;width:100%}
th{background:#2B3A67;color:#fff;font-weight:700;padding:9px;border:1px solid #D8C9AF}
td{padding:8px;border:1px solid #D8C9AF;vertical-align:top}tr:nth-child(even){background:#FBF7EF}
</style></head><body>
<h1>${escapeHtml(title)}</h1>
<p class="summary">${escapeHtml(summary)}</p>
<table><thead><tr>${headings.map((heading) => `<th>${escapeHtml(heading)}</th>`).join("")}</tr></thead><tbody>${body}</tbody></table>
</body></html>`;

  const file = new File(Paths.cache, fileName);
  file.create({ overwrite: true });
  file.write(workbook);
  if (!(await Sharing.isAvailableAsync())) {
    throw new Error("Sharing is not available on this device.");
  }
  await Sharing.shareAsync(file.uri, {
    mimeType: "application/vnd.ms-excel",
    dialogTitle,
    UTI: "com.microsoft.excel.xls",
  });
}

function generatedStamp() {
  return new Intl.DateTimeFormat("en-US", {
    dateStyle: "long",
    timeStyle: "short",
    timeZone: "America/Chicago",
  }).format(new Date());
}

type Participants = {
  firstDevoteeId: string;
  firstName: string;
  secondDevoteeId: string;
  secondName: string;
};

function senderLabel(participants: Participants, message: ThreadMessage) {
  if (message.senderName) return message.senderName;
  if (message.senderId === participants.secondDevoteeId) {
    return participants.secondName;
  }
  if (message.senderId === participants.firstDevoteeId) {
    return participants.firstName;
  }
  return "Devotee";
}

async function shareConversationReport(
  participants: Participants,
  messages: readonly ThreadMessage[],
) {
  const rows = messages.map((message) => {
    const created = new Date(message.createdAt);
    return [
      getChicagoDateKey(created),
      formatChicagoTime(created),
      senderLabel(participants, message),
      message.body ?? "",
      message.imageUrl ? "Yes" : "No",
      message.removed ? "Yes" : "No",
    ];
  });

  await shareWorkbook({
    fileName: `iskcon-chicago-conversation-${getChicagoDateKey()}.xls`,
    title: "ISKCON Chicago — Conversation Report",
    summary: `${participants.firstName} and ${participants.secondName} · Generated ${generatedStamp()} · ${rows.length} message${rows.length === 1 ? "" : "s"}`,
    headings: ["Date", "Time", "From", "Message", "Has image", "Removed by sender"],
    rows,
    dialogTitle: "Share conversation report",
  });
}

async function shareConversationListReport(
  conversations: readonly ConversationRow[],
) {
  const rows = conversations.map((conversation) => {
    const last = new Date(conversation.last_message_at);
    return [
      conversation.first_name,
      conversation.second_name,
      String(conversation.message_count),
      getChicagoDateKey(last),
      formatChicagoTime(last),
    ];
  });

  await shareWorkbook({
    fileName: `iskcon-chicago-conversations-${getChicagoDateKey()}.xls`,
    title: "ISKCON Chicago — Conversations Report",
    summary: `Generated ${generatedStamp()} · ${rows.length} conversation${rows.length === 1 ? "" : "s"}`,
    headings: [
      "Devotee",
      "With",
      "Messages",
      "Last activity date",
      "Last activity time",
    ],
    rows,
    dialogTitle: "Share conversations report",
  });
}

/** The one export control, so both places produce the same spreadsheet. */
function ExportButton({
  label,
  busy,
  disabled,
  accessibilityLabel,
  onPress,
}: {
  label: string;
  busy: boolean;
  disabled: boolean;
  accessibilityLabel: string;
  onPress: () => void;
}) {
  const live = !disabled;
  return (
    <Pressable
      className={`ml-3 min-h-10 shrink-0 flex-row items-center rounded-pill px-3 ${
        live ? "bg-indigo" : "bg-sandalwood"
      }`}
      accessibilityRole="button"
      accessibilityLabel={accessibilityLabel}
      accessibilityState={{ disabled, busy }}
      disabled={disabled}
      onPress={onPress}
    >
      <Ionicons
        name={busy ? "hourglass-outline" : "download-outline"}
        size={16}
        color={live ? tokens.colors.white : tokens.colors.stoneMuted}
      />
      <Text
        className={`ml-1.5 font-sans-bold text-sm ${
          live ? "text-white" : "text-stoneMuted"
        }`}
      >
        {busy ? "Preparing…" : label}
      </Text>
    </Pressable>
  );
}

type Segment = { value: string; match: boolean };

function splitOnTerm(text: string, term: string): Segment[] {
  if (!term) return [{ value: text, match: false }];
  const haystack = text.toLocaleLowerCase();
  const needle = term.toLocaleLowerCase();
  const segments: Segment[] = [];
  let from = 0;
  for (
    let at = haystack.indexOf(needle);
    at !== -1;
    at = haystack.indexOf(needle, from)
  ) {
    if (at > from) segments.push({ value: text.slice(from, at), match: false });
    segments.push({ value: text.slice(at, at + needle.length), match: true });
    from = at + needle.length;
  }
  if (from < text.length) {
    segments.push({ value: text.slice(from), match: false });
  }
  return segments;
}

/** The searched word tinted where it sits, so a hit is found without hunting. */
function HighlightedBody({
  text,
  term,
  className,
}: {
  text: string;
  term: string;
  className: string;
}) {
  const segments = useMemo(() => splitOnTerm(text, term), [text, term]);

  return (
    <Text className={className}>
      {segments.map((segment, index) =>
        segment.match ? (
          <Text key={index} className="bg-marigoldSoft text-stone">
            {segment.value}
          </Text>
        ) : (
          segment.value
        ),
      )}
    </Text>
  );
}

type ThreadItem =
  | { kind: "day"; key: string; label: string }
  | {
      kind: "message";
      key: string;
      message: ThreadMessage;
      senderName: string;
      alignEnd: boolean;
    };

function buildThread(
  participants: Participants,
  messages: readonly ThreadMessage[],
): ThreadItem[] {
  const items: ThreadItem[] = [];
  let lastDayKey = "";
  for (const message of messages) {
    const created = new Date(message.createdAt);
    const dayKey = getChicagoDateKey(created);
    if (dayKey !== lastDayKey) {
      lastDayKey = dayKey;
      items.push({
        kind: "day",
        key: `day-${dayKey}`,
        label: formatChicagoShortDate(created),
      });
    }
    items.push({
      kind: "message",
      key: message.id,
      message,
      senderName: senderLabel(participants, message),
      // One participant per side, so a long thread stays readable. Anyone who
      // is neither participant keeps the left side rather than being folded
      // into the wrong one.
      alignEnd: message.senderId === participants.secondDevoteeId,
    });
  }
  return items;
}

function DaySeparator({ label }: { label: string }) {
  return (
    <View className="my-3 flex-row items-center justify-center">
      <View className="rounded-pill bg-sandalwood px-3 py-1">
        <Text className="font-sans-bold text-xs text-stoneMuted">{label}</Text>
      </View>
    </View>
  );
}

function ThreadSkeleton() {
  return (
    <View className="px-screen pt-4">
      {[0, 1, 2, 3].map((index) => (
        <View
          key={index}
          className={`mb-4 w-[72%] ${index % 2 ? "self-end items-end" : "self-start items-start"}`}
        >
          <Skeleton height={11} width="38%" />
          <View className="mt-1.5 w-full">
            <Skeleton height={index % 3 === 0 ? 62 : 44} />
          </View>
        </View>
      ))}
    </View>
  );
}

function MessageBubble({
  item,
  maxWidth,
  imageWidth,
  term,
}: {
  item: Extract<ThreadItem, { kind: "message" }>;
  maxWidth: number;
  imageWidth: number;
  term: string;
}) {
  const { message, alignEnd } = item;
  const created = new Date(message.createdAt);
  const hasImage = Boolean(message.imageUrl);
  const hasContent = hasImage || Boolean(message.body);
  const textOnly = !hasImage;

  return (
    <View
      style={{ maxWidth }}
      className={`mb-2.5 ${alignEnd ? "items-end self-end" : "items-start self-start"}`}
    >
      <Text
        className={`mb-1 px-1 font-sans-bold text-xs ${alignEnd ? "text-peacock" : "text-indigo"}`}
        numberOfLines={1}
      >
        {item.senderName}
      </Text>
      <View
        className={`overflow-hidden rounded-card ${textOnly ? "px-card py-2.5" : "p-1"} ${
          alignEnd
            ? "rounded-br-md border border-peacock/20 bg-peacockSoft"
            : "rounded-bl-md border border-border bg-white"
        }`}
      >
        {hasImage && message.imageUrl ? (
          <Image
            source={{ uri: message.imageUrl }}
            style={{ width: imageWidth, height: imageWidth, borderRadius: 16 }}
            resizeMode="cover"
            accessibilityIgnoresInvertColors
            accessibilityLabel={`Picture from ${item.senderName}`}
          />
        ) : null}
        {message.body ? (
          <HighlightedBody
            text={message.body}
            term={term}
            className={`font-sans text-base leading-6 text-stone ${hasImage ? "px-3 pb-1 pt-2" : ""}`}
          />
        ) : null}
        {!hasContent && !message.removed ? (
          <Text className="font-sans text-sm italic leading-5 text-stoneMuted">
            No content
          </Text>
        ) : null}
        {message.removed ? (
          <View
            className={`flex-row items-center ${
              hasContent ? "mt-2 border-t border-border/70 pt-1.5" : ""
            } ${hasImage ? "mx-3 mb-1" : ""}`}
          >
            <Ionicons
              name="remove-circle-outline"
              size={12}
              color={tokens.colors.stoneMuted}
            />
            <Text className="ml-1 font-sans text-[11px] text-stoneMuted">
              Removed by sender
            </Text>
          </View>
        ) : null}
      </View>
      <Text className="mt-1 px-1 font-sans text-[11px] text-stoneMuted">
        {formatChicagoTime(created)}
      </Text>
    </View>
  );
}

export function DevoteeConversationScreen({ route }: ThreadProps) {
  const participants: Participants = route.params;
  const { conversationId } = route.params;
  const reachable = useServerReachable();
  const { width } = useWindowDimensions();
  const queryClient = useQueryClient();

  const [search, setSearch] = useState("");
  const [matchesOnly, setMatchesOnly] = useState(true);
  const [exporting, setExporting] = useState(false);
  const [exportError, setExportError] = useState<string | null>(null);

  const messages = useQuery({
    queryKey: threadKey(conversationId),
    queryFn: () => fetchThread(conversationId),
  });

  const all = messages.data ?? NO_MESSAGES;
  const term = search.trim().toLocaleLowerCase();

  const matching = useMemo(
    () =>
      term
        ? all.filter((message) =>
            (message.body ?? "").toLocaleLowerCase().includes(term),
          )
        : all,
    [all, term],
  );

  const thread = useMemo(
    () => buildThread(participants, term && matchesOnly ? matching : all),
    [participants, all, matching, term, matchesOnly],
  );

  // A bubble is capped in both units: a share of the screen so it never fills
  // it edge to edge, and an absolute width so a tablet-sized phone does not
  // stretch a one-line message across the whole row. 32 is the two px-screen
  // gutters the list already spends.
  const contentWidth = Math.max(width - 32, 240);
  const bubbleMaxWidth = Math.min(contentWidth * 0.82, 460);
  // Inside the bubble's 4px padding and 1px border on each side, so a picture
  // never bleeds past the rounded corner that is meant to clip it.
  const imageWidth = Math.min(bubbleMaxWidth - 10, 260);

  const onExport = useCallback(async () => {
    setExportError(null);
    setExporting(true);
    try {
      // Always the whole thread: a search narrows what is on screen, not what
      // the spreadsheet is for.
      const rows = await queryClient.fetchQuery({
        queryKey: threadKey(conversationId),
        queryFn: () => fetchThread(conversationId),
      });
      await shareConversationReport(participants, rows);
    } catch (caught) {
      setExportError(
        errorMessage(caught, "The report could not be shared.") ??
          "The report could not be shared.",
      );
    } finally {
      setExporting(false);
    }
  }, [conversationId, participants, queryClient]);

  const count = all.length;
  const last = count ? new Date(all[count - 1].createdAt) : null;
  const loadFailed = Boolean(messages.error);

  const meta = messages.isLoading
    ? "Loading…"
    : term
      ? `${matching.length} of ${count} message${count === 1 ? "" : "s"} contain that word`
      : `${count} message${count === 1 ? "" : "s"}${
          last ? ` · last ${formatChicagoShortDate(last)}` : ""
        }`;

  return (
    // The stack header owns the title and the way back; the tab bar owns the
    // foot of the screen. Nothing here may add chrome to either edge.
    <View className="flex-1 bg-ivory">
      <BotanicalBackdrop />
      <View className="border-b border-border px-screen pb-2 pt-2">
        <View className="flex-row items-center">
          <View className="min-w-0 flex-1 flex-row items-center rounded-button border border-border bg-white px-3">
            <Ionicons
              name="search-outline"
              size={16}
              color={tokens.colors.stoneMuted}
            />
            <TextInput
              className="ml-2 min-h-11 min-w-0 flex-1 font-sans text-base text-stone"
              accessibilityLabel="Search the messages shown here for a word"
              value={search}
              onChangeText={setSearch}
              placeholder="Search this conversation"
              placeholderTextColor={tokens.colors.stoneMuted}
              autoCapitalize="none"
              autoCorrect={false}
              returnKeyType="search"
              clearButtonMode="while-editing"
            />
          </View>
          <ExportButton
            label="Export"
            busy={exporting}
            disabled={exporting || !count}
            accessibilityLabel="Export this conversation to Excel"
            onPress={() => {
              void onExport();
            }}
          />
        </View>
        <View className="mt-1.5 flex-row items-center justify-between">
          <Text
            className="min-w-0 flex-1 font-sans text-xs text-stoneMuted"
            numberOfLines={1}
          >
            {meta}
          </Text>
          {term ? (
            <Pressable
              className="ml-3 min-h-9 shrink-0 items-center justify-center rounded-pill bg-indigoSoft px-3"
              accessibilityRole="button"
              accessibilityLabel={
                matchesOnly
                  ? "Show every message, not only the ones that contain that word"
                  : "Show only the messages that contain that word"
              }
              hitSlop={6}
              onPress={() => setMatchesOnly((value) => !value)}
            >
              <Text className="font-sans-bold text-xs text-indigo">
                {matchesOnly ? "Show all" : "Matches only"}
              </Text>
            </Pressable>
          ) : null}
        </View>
      </View>

      {messages.isLoading ? (
        <ThreadSkeleton />
      ) : loadFailed ? (
        <View className="px-screen pt-4">
          <LoadFailure
            reachable={reachable}
            message={errorMessage(
              messages.error,
              "This conversation could not be loaded.",
            )}
            onRetry={() => void messages.refetch()}
          />
        </View>
      ) : (
        <FlatList
          className="flex-1"
          data={thread}
          keyExtractor={(item) => item.key}
          contentContainerClassName="grow px-screen pb-8 pt-2"
          showsVerticalScrollIndicator={false}
          keyboardShouldPersistTaps="handled"
          keyboardDismissMode="on-drag"
          initialNumToRender={16}
          maxToRenderPerBatch={16}
          windowSize={11}
          renderItem={({ item }) =>
            item.kind === "day" ? (
              <DaySeparator label={item.label} />
            ) : (
              <MessageBubble
                item={item}
                maxWidth={bubbleMaxWidth}
                imageWidth={imageWidth}
                term={term}
              />
            )
          }
          ListEmptyComponent={
            <View className="flex-1 items-center justify-center px-4 py-12">
              <Ionicons
                name={term ? "search-outline" : "chatbubble-ellipses-outline"}
                size={30}
                color={tokens.colors.peacock}
              />
              <Text className="mt-3 text-center font-sans-bold text-base text-stone">
                {term ? "No message contains that word" : "No messages yet"}
              </Text>
              <Text className="mt-1 text-center font-sans text-sm text-stoneMuted">
                {term
                  ? "Try a shorter word, or clear the search."
                  : "Nothing has been sent in this conversation."}
              </Text>
            </View>
          }
          ListFooterComponent={
            exportError ? <FormError message={exportError} /> : null
          }
        />
      )}
    </View>
  );
}

export function DevoteeConversationsScreen({ navigation }: ListProps) {
  const activeUserId = usePrototypeSession((state) => state.activeUserId);
  const previewRole = usePrototypeSession((state) => state.previewRole);
  const profile = useCurrentAccessProfile(activeUserId);
  const role = __DEV__ && previewRole ? previewRole : (profile.data?.role ?? "devotee");
  const canOpen = hasAccessPermission(role, "app.view_all");

  const reachable = useServerReachable();
  const queryClient = useQueryClient();
  const conversations = useAllConversations(canOpen);
  const [search, setSearch] = useState("");
  const [showAll, setShowAll] = useState(false);
  const [exportingId, setExportingId] = useState<string | null>(null);
  const [exportError, setExportError] = useState<string | null>(null);

  const term = search.trim();

  const rows = useMemo(() => {
    const needle = term.toLocaleLowerCase();
    return (conversations.data ?? [])
      .filter(
        (row) =>
          !needle ||
          `${row.first_name} ${row.second_name}`
            .toLocaleLowerCase()
            .includes(needle),
      )
      .sort(
        (left, right) =>
          new Date(right.last_message_at).getTime() -
          new Date(left.last_message_at).getTime(),
      );
  }, [conversations.data, term]);

  // A name already narrows the list, so the preview only applies to the
  // unfiltered one.
  const previewing = !term && !showAll && rows.length > PREVIEW_COUNT;
  const visible = previewing ? rows.slice(0, PREVIEW_COUNT) : rows;

  const exportConversation = async (conversation: ConversationRow) => {
    setExportError(null);
    setExportingId(conversation.id);
    try {
      // fetchQuery so a thread already read is not fetched twice, and so a row
      // exported from the list warms the thread opened next.
      const messages = await queryClient.fetchQuery({
        queryKey: threadKey(conversation.id),
        queryFn: () => fetchThread(conversation.id),
      });
      await shareConversationReport(
        {
          firstDevoteeId: conversation.first_devotee_id,
          firstName: conversation.first_name,
          secondDevoteeId: conversation.second_devotee_id,
          secondName: conversation.second_name,
        },
        messages,
      );
    } catch (caught) {
      setExportError(
        errorMessage(caught, "The report could not be shared.") ??
          "The report could not be shared.",
      );
    } finally {
      setExportingId(null);
    }
  };

  const exportList = async () => {
    setExportError(null);
    setExportingId("all");
    try {
      await shareConversationListReport(rows);
    } catch (caught) {
      setExportError(
        errorMessage(caught, "The report could not be shared.") ??
          "The report could not be shared.",
      );
    } finally {
      setExportingId(null);
    }
  };

  if (!canOpen) {
    return (
      <Screen topInset={false}>
        <View className="items-center rounded-card border border-border bg-white px-card py-9">
          <Ionicons name="lock-closed-outline" size={30} color={tokens.colors.indigo} />
          <Text className="mt-3 text-center font-sans-bold text-base text-stone">
            This page is not available
          </Text>
          <Text className="mt-1 text-center font-sans text-sm text-stoneMuted">
            Your account does not have access to it.
          </Text>
        </View>
      </Screen>
    );
  }

  const loadFailed = Boolean(conversations.error);

  return (
    <ListScreen
      topInset={false}
      data={loadFailed ? [] : visible}
      keyExtractor={(item) => item.id}
      header={
        // No screen title: the stack header above already carries these words,
        // and repeating them costs a small phone a whole row.
        <>
          <TextInput
            className="min-h-touch rounded-button border border-border bg-white px-4 font-sans text-base text-stone"
            accessibilityLabel="Search conversations by devotee name"
            value={search}
            onChangeText={setSearch}
            placeholder="Search by either devotee's name"
            placeholderTextColor={tokens.colors.stoneMuted}
            autoCapitalize="words"
            autoCorrect={false}
            returnKeyType="search"
            clearButtonMode="while-editing"
          />
          <View className="mb-3 mt-3 flex-row items-center justify-between">
            <Text className="min-w-0 flex-1 font-sans-bold text-sm text-peacock">
              {conversations.isLoading
                ? "Loading…"
                : previewing
                  ? `${visible.length} of ${rows.length} conversations`
                  : `${rows.length} conversation${rows.length === 1 ? "" : "s"}`}
            </Text>
            <ExportButton
              label="Export all"
              busy={exportingId === "all"}
              disabled={!rows.length || exportingId !== null}
              accessibilityLabel="Export the conversations listed here to Excel"
              onPress={() => {
                void exportList();
              }}
            />
          </View>
        </>
      }
      renderItem={(item) => {
        const last = new Date(item.last_message_at);
        return (
          <View className="mb-3 flex-row items-center rounded-card border border-border bg-white p-card">
            <Pressable
              className="min-w-0 flex-1 flex-row items-center"
              accessibilityRole="button"
              accessibilityLabel={`Open the conversation between ${item.first_name} and ${item.second_name}, ${item.message_count} message${item.message_count === 1 ? "" : "s"}, last active ${formatChicagoShortDate(last)}`}
              onPress={() =>
                navigation.navigate("DevoteeConversation", {
                  conversationId: item.id,
                  firstDevoteeId: item.first_devotee_id,
                  firstName: item.first_name,
                  secondDevoteeId: item.second_devotee_id,
                  secondName: item.second_name,
                })
              }
            >
              <View className="h-10 w-10 items-center justify-center rounded-pill bg-indigoSoft">
                <Ionicons
                  name="chatbubbles-outline"
                  size={19}
                  color={tokens.colors.indigo}
                />
              </View>
              <View className="ml-3 min-w-0 flex-1">
                <Text className="font-display text-lg text-stone" numberOfLines={2}>
                  {item.first_name} & {item.second_name}
                </Text>
                <Text className="mt-1 font-sans text-sm leading-5 text-stoneMuted">
                  {item.message_count} message
                  {item.message_count === 1 ? "" : "s"} ·{" "}
                  {formatChicagoShortDate(last)} at {formatChicagoTime(last)}
                </Text>
              </View>
            </Pressable>
            <Pressable
              className="ml-2 h-10 w-10 items-center justify-center rounded-pill bg-sandalwood"
              accessibilityRole="button"
              accessibilityLabel={`Export the conversation between ${item.first_name} and ${item.second_name} to Excel`}
              accessibilityState={{ disabled: exportingId !== null }}
              disabled={exportingId !== null}
              onPress={() => {
                void exportConversation(item);
              }}
            >
              <Ionicons
                name={
                  exportingId === item.id
                    ? "hourglass-outline"
                    : "download-outline"
                }
                size={18}
                color={tokens.colors.indigo}
              />
            </Pressable>
          </View>
        );
      }}
      empty={
        conversations.isLoading ? (
          <View className="gap-3">
            <SkeletonCard />
            <SkeletonCard />
            <SkeletonCard />
          </View>
        ) : loadFailed ? (
          <LoadFailure
            reachable={reachable}
            message={errorMessage(
              conversations.error,
              "Conversations could not be loaded.",
            )}
            onRetry={() => void conversations.refetch()}
          />
        ) : (
          <View className="items-center rounded-card border border-border bg-white px-card py-8">
            <Ionicons
              name="chatbubbles-outline"
              size={30}
              color={tokens.colors.peacock}
            />
            <Text className="mt-3 text-center font-sans-bold text-base text-stone">
              {term ? "No matching conversation" : "No conversations yet"}
            </Text>
            <Text className="mt-1 text-center font-sans text-sm text-stoneMuted">
              {term
                ? "No conversation matches that name."
                : "No devotee has started a conversation yet."}
            </Text>
          </View>
        )
      }
      footer={
        <>
          {!term && !loadFailed && rows.length > PREVIEW_COUNT ? (
            <Pressable
              className="mt-2 min-h-touch items-center justify-center rounded-button bg-indigoSoft"
              accessibilityRole="button"
              onPress={() => setShowAll((value) => !value)}
            >
              <Text className="font-sans-bold text-sm text-indigo">
                {showAll
                  ? "Show fewer"
                  : `See all ${rows.length} conversations`}
              </Text>
            </Pressable>
          ) : null}
          {exportError ? <FormError message={exportError} /> : null}
        </>
      }
    />
  );
}
