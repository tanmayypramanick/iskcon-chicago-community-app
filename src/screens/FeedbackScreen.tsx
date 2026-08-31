import { Ionicons } from "@expo/vector-icons";
import { useNavigation, type NavigationProp } from "@react-navigation/native";
import { useMemo, useState } from "react";
import { Alert, Pressable, Text, TextInput, View } from "react-native";

import tokens from "../../design-tokens.json";
import { CommunityEmailLink } from "../components/CommunityEmailLink";
import {
  Avatar,
  Button,
  EmptyOrOffline,
  ListScreen,
  LoadFailure,
  ScreenTitle,
  SectionHeader,
} from "../components/ui";
import { useCurrentAccessProfile } from "../features/access/hooks";
import { hasAccessPermission } from "../features/access/model";
import {
  useAllFeedback,
  useDeleteFeedback,
  useMyFeedback,
  useReviewFeedback,
  useSubmitFeedback,
} from "../features/feedback/hooks";
import {
  cannedFeedbackReplies,
  feedbackCategories,
  feedbackCategoryHints,
  feedbackCategoryLabels,
  type AllFeedback,
  type FeedbackCategory,
  type MyFeedback,
} from "../features/feedback/types";
import { openConversation } from "../features/messaging/api";
import { FormError } from "../features/services/components";
import { errorMessage } from "../features/services/format";
import { formatChicagoShortDate } from "../lib/chicagoDate";
import { useServerReachable } from "../lib/connectivity";
import type { MainTabParamList } from "../navigation/types";
import { usePrototypeSession } from "../store/usePrototypeSession";

/**
 * The two faces of this screen. Every devotee has "mine" — the form and their
 * own notes. Only the President and the Tech Admin are offered "all", and for
 * them it is a second face of the same screen rather than a second screen,
 * because a reviewer is also a devotee with feedback of their own.
 */
type Face = "mine" | "all";

type StatusFilter = "all" | "new" | "reviewed";
type CategoryFilter = "all" | FeedbackCategory;

/**
 * One list backs both faces. A tagged row keeps the two shapes apart without
 * a second FlatList, a second set of empty states and a second scroll
 * position to lose.
 */
type FeedbackListItem =
  | { key: string; kind: "mine"; row: MyFeedback }
  | { key: string; kind: "all"; row: AllFeedback };

const statusFilters: Array<{ key: StatusFilter; label: string }> = [
  { key: "all", label: "All" },
  { key: "new", label: "Waiting" },
  { key: "reviewed", label: "Reviewed" },
];

function dayLabel(value: string | null) {
  if (!value) return null;
  const at = new Date(value);
  if (Number.isNaN(at.getTime())) return null;
  return formatChicagoShortDate(at);
}

/** The app's pill: an option that is either chosen or not. */
function Pill({
  label,
  selected,
  accessibilityLabel,
  onPress,
}: {
  label: string;
  selected: boolean;
  accessibilityLabel?: string;
  onPress: () => void;
}) {
  return (
    <Pressable
      className={`min-h-10 items-center justify-center rounded-pill border px-3 ${
        selected ? "border-indigo bg-indigo" : "border-border bg-white"
      }`}
      accessibilityRole="button"
      accessibilityState={{ selected }}
      accessibilityLabel={accessibilityLabel ?? label}
      onPress={onPress}
    >
      <Text
        className={`font-sans-bold text-xs ${selected ? "text-white" : "text-stone"}`}
      >
        {label}
      </Text>
    </Pressable>
  );
}

function StatusBadge({ status }: { status: "new" | "reviewed" }) {
  const reviewed = status === "reviewed";
  return (
    <View
      className={`flex-row items-center rounded-pill px-2.5 py-1 ${
        reviewed ? "bg-peacockSoft" : "bg-marigoldSoft"
      }`}
    >
      <Ionicons
        name={reviewed ? "checkmark-circle" : "hourglass-outline"}
        size={13}
        color={reviewed ? tokens.colors.peacock : tokens.colors.stone}
      />
      <Text
        className={`ml-1 font-sans-bold text-xs ${
          reviewed ? "text-peacock" : "text-stone"
        }`}
      >
        {reviewed ? "Reviewed" : "Waiting"}
      </Text>
    </View>
  );
}

function CategoryBadge({ category }: { category: FeedbackCategory }) {
  return (
    <View className="rounded-pill bg-indigoSoft px-2.5 py-1">
      <Text className="font-sans-bold text-xs text-indigo">
        {feedbackCategoryLabels[category]}
      </Text>
    </View>
  );
}

/** The temple's answer, shown to the devotee who wrote the note. */
function ReplyBlock({
  reply,
  who,
  at,
}: {
  reply: string | null;
  who: string | null;
  at: string | null;
}) {
  if (!reply) return null;
  const when = dayLabel(at);
  return (
    <View className="mt-3 rounded-button border border-peacock/20 bg-peacockSoft px-4 py-3">
      <Text className="font-sans-bold text-xs uppercase tracking-wider text-peacock">
        The temple replied
      </Text>
      <Text className="mt-1.5 font-sans text-sm leading-6 text-stone">
        {reply}
      </Text>
      {who || when ? (
        <Text className="mt-2 font-sans text-xs text-stoneMuted">
          {[who, when].filter(Boolean).join(" · ")}
        </Text>
      ) : null}
    </View>
  );
}

/**
 * A Remove, offered only where the server says this viewer may. Written the
 * same way in both faces of the screen, so a note and a queue row lose their
 * words the same way.
 */
function RemoveRow({
  accessibilityLabel,
  onPress,
}: {
  accessibilityLabel: string;
  onPress: () => void;
}) {
  return (
    <Pressable
      className="min-h-touch flex-row items-center justify-center rounded-button border border-border bg-white px-4"
      accessibilityRole="button"
      accessibilityLabel={accessibilityLabel}
      onPress={onPress}
    >
      <Ionicons
        name="trash-outline"
        size={17}
        color={tokens.colors.vermilion}
      />
      <Text className="ml-2 font-sans-bold text-sm text-vermilion">Remove</Text>
    </Pressable>
  );
}

/** A note the devotee sent, and whatever came back. */
function MyFeedbackCard({
  row,
  onRemove,
}: {
  row: MyFeedback;
  onRemove: () => void;
}) {
  const acknowledged = row.status === "reviewed" && !row.reply;

  return (
    <View className="mt-3 rounded-card border border-border bg-white p-card">
      <View className="flex-row flex-wrap items-center gap-2">
        <CategoryBadge category={row.category} />
        <StatusBadge status={row.status} />
        <Text className="font-sans text-xs text-stoneMuted">
          {dayLabel(row.created_at)}
        </Text>
      </View>
      <Text className="mt-3 font-sans text-base leading-6 text-stone">
        {row.body}
      </Text>
      <ReplyBlock
        reply={row.reply}
        who={row.replied_by_name}
        at={row.replied_at}
      />
      {acknowledged ? (
        <Text className="mt-3 font-sans text-sm leading-5 text-stoneMuted">
          {row.replied_by_name
            ? `${row.replied_by_name} read this. Thank you.`
            : "This was read. Thank you."}
        </Text>
      ) : null}
      {row.status === "new" ? (
        <Text className="mt-3 font-sans text-sm leading-5 text-stoneMuted">
          Waiting to be read. You will be told when it has been.
        </Text>
      ) : null}
      {row.can_delete ? (
        <View className="mt-3">
          <RemoveRow
            accessibilityLabel="Remove the feedback you sent"
            onPress={onRemove}
          />
        </View>
      ) : null}
    </View>
  );
}

export function FeedbackScreen() {
  const navigation = useNavigation();
  const tabs = navigation.getParent<NavigationProp<MainTabParamList>>();
  const activeUserId = usePrototypeSession((state) => state.activeUserId);
  const previewRole = usePrototypeSession((state) => state.previewRole);
  const profile = useCurrentAccessProfile(activeUserId);
  const role =
    __DEV__ && previewRole ? previewRole : (profile.data?.role ?? "devotee");
  // list_all_feedback answers with an empty set to anyone else anyway; this is
  // the client saying the same thing so the section never even flickers.
  const canReviewAll = hasAccessPermission(role, "app.view_all");
  const reachable = useServerReachable();

  const mine = useMyFeedback(activeUserId);
  const everyone = useAllFeedback(canReviewAll);
  const submit = useSubmitFeedback(activeUserId);
  const review = useReviewFeedback(activeUserId);
  const remove = useDeleteFeedback(activeUserId);

  const [face, setFace] = useState<Face>("mine");
  const activeFace: Face = canReviewAll ? face : "mine";

  const [category, setCategory] = useState<FeedbackCategory>("temple");
  const [body, setBody] = useState("");
  const [formError, setFormError] = useState<string | null>(null);
  const [sent, setSent] = useState(false);

  const [search, setSearch] = useState("");
  const [categoryFilter, setCategoryFilter] = useState<CategoryFilter>("all");
  const [statusFilter, setStatusFilter] = useState<StatusFilter>("all");

  const [expandedId, setExpandedId] = useState<string | null>(null);
  const [replyDraft, setReplyDraft] = useState("");
  const [reviewError, setReviewError] = useState<string | null>(null);
  const [openingChatFor, setOpeningChatFor] = useState<string | null>(null);

  const allRows = useMemo(() => {
    const term = search.trim().toLowerCase();
    return (everyone.data ?? []).filter((row) => {
      if (categoryFilter !== "all" && row.category !== categoryFilter) {
        return false;
      }
      if (statusFilter !== "all" && row.status !== statusFilter) return false;
      if (!term) return true;
      return (
        row.body.toLowerCase().includes(term) ||
        row.devotee_name.toLowerCase().includes(term) ||
        (row.reply ?? "").toLowerCase().includes(term)
      );
    });
  }, [categoryFilter, everyone.data, search, statusFilter]);

  const items: FeedbackListItem[] =
    activeFace === "mine"
      ? (mine.data ?? []).map((row) => ({
          key: `mine-${row.id}`,
          kind: "mine" as const,
          row,
        }))
      : allRows.map((row) => ({
          key: `all-${row.id}`,
          kind: "all" as const,
          row,
        }));

  const query = activeFace === "mine" ? mine : everyone;
  const failed = query.isError && query.data === undefined;
  const waitingCount = (everyone.data ?? []).filter(
    (row) => row.status === "new",
  ).length;

  const trimmedBody = body.trim();

  const send = () => {
    setFormError(null);
    setSent(false);
    if (!trimmedBody) {
      setFormError("Please write your feedback before sending it.");
      return;
    }
    submit.mutate(
      { category, body: trimmedBody },
      {
        onSuccess: () => {
          setBody("");
          setSent(true);
        },
        onError: (caught) =>
          setFormError(
            errorMessage(caught, "That feedback could not be sent.") ?? null,
          ),
      },
    );
  };

  const openReviewFor = (row: AllFeedback) => {
    const opening = expandedId !== row.id;
    setReviewError(null);
    setExpandedId(opening ? row.id : null);
    setReplyDraft(opening ? (row.reply ?? "") : "");
  };

  const markReviewed = (row: AllFeedback, reply: string | null) => {
    setReviewError(null);
    review.mutate(
      { feedbackId: row.id, reply },
      {
        onSuccess: () => {
          setExpandedId(null);
          setReplyDraft("");
        },
        onError: (caught) =>
          setReviewError(
            errorMessage(caught, "That could not be saved.") ?? null,
          ),
      },
    );
  };

  const confirmRemove = (row: MyFeedback | AllFeedback) => {
    Alert.alert(
      "Remove this feedback?",
      "It disappears for the temple as well. This cannot be undone.",
      [
        { text: "Keep", style: "cancel" },
        {
          text: "Remove",
          style: "destructive",
          onPress: () =>
            remove.mutate(row.id, {
              onError: (caught) =>
                Alert.alert(
                  "Not removed",
                  errorMessage(caught, "That could not be removed.") ?? "",
                ),
            }),
        },
      ],
    );
  };

  /**
   * The same path DevoteeProfileScreen uses: open_conversation, then the Chat
   * screen on the Devotees tab. A reply here is one line on one row and cannot
   * grow into a thread, so anything that needs a back-and-forth belongs in the
   * conversation the devotee already has.
   */
  const messageDevotee = (row: AllFeedback) => {
    setReviewError(null);
    setOpeningChatFor(row.id);
    void openConversation(row.devotee_id)
      .then((conversationId) => {
        tabs?.navigate("Devotees", {
          screen: "Chat",
          params: {
            conversationId,
            devoteeId: row.devotee_id,
            name: row.devotee_name,
          },
        });
      })
      .catch((caught: unknown) =>
        setReviewError(
          errorMessage(caught, "That conversation could not be opened.") ??
            null,
        ),
      )
      .finally(() => setOpeningChatFor(null));
  };

  const composer = (
    <View className="rounded-card border border-border bg-white p-card">
      <Text className="font-sans-bold text-lg text-stone">
        Say something to the temple
      </Text>
      <Text className="mt-1 font-sans text-sm leading-5 text-stoneMuted">
        Only the President and the Tech Admin read this. You will be told when
        it has been read.
      </Text>
      <Text className="mt-2 font-sans text-xs leading-5 text-stoneMuted">
        Prefer email? Write to{" "}
        <CommunityEmailLink
          subject="Feedback for ISKCON Chicago"
          className="font-sans text-xs text-indigo underline"
        />
        .
      </Text>

      <View className="mt-4 flex-row flex-wrap gap-2">
        {feedbackCategories.map((option) => (
          <Pill
            key={option}
            label={feedbackCategoryLabels[option]}
            selected={category === option}
            accessibilityLabel={`Feedback about the ${feedbackCategoryLabels[option].toLowerCase()}`}
            onPress={() => setCategory(option)}
          />
        ))}
      </View>
      <Text className="mt-2 font-sans text-xs leading-5 text-stoneMuted">
        {feedbackCategoryHints[category]}
      </Text>

      <TextInput
        className="mt-3 min-h-[112px] rounded-button border border-border bg-white px-4 py-3 font-sans text-base text-stone"
        value={body}
        onChangeText={(value) => {
          setBody(value);
          if (formError) setFormError(null);
          if (sent) setSent(false);
        }}
        placeholder="What would you like the temple to know?"
        placeholderTextColor={tokens.colors.stoneMuted}
        multiline
        textAlignVertical="top"
        accessibilityLabel="Your feedback"
      />

      <View className="mt-3">
        <Button
          icon="send-outline"
          disabled={submit.isPending || !trimmedBody}
          onPress={send}
        >
          {submit.isPending ? "Sending…" : "Send feedback"}
        </Button>
      </View>

      {sent ? (
        <View className="mt-3 flex-row items-center rounded-button bg-peacockSoft px-4 py-3">
          <Ionicons
            name="checkmark-circle"
            size={18}
            color={tokens.colors.peacock}
          />
          <Text className="ml-2 min-w-0 flex-1 font-sans text-sm leading-5 text-peacock">
            Sent. It is below, and you will be told when it has been read.
          </Text>
        </View>
      ) : null}

      {formError ? <FormError message={formError} /> : null}
    </View>
  );

  const faceSwitch = canReviewAll ? (
    <View className="mb-section flex-row flex-wrap gap-2">
      <Pill
        label="Your feedback"
        selected={activeFace === "mine"}
        onPress={() => setFace("mine")}
      />
      <Pill
        label={
          waitingCount
            ? `All feedback · ${waitingCount} waiting`
            : "All feedback"
        }
        selected={activeFace === "all"}
        accessibilityLabel="See all feedback"
        onPress={() => setFace("all")}
      />
    </View>
  ) : null;

  const reviewFilters = (
    <View>
      <View className="min-h-touch flex-row items-center rounded-button border border-border bg-white px-4">
        <Ionicons name="search" size={19} color={tokens.colors.indigo} />
        <TextInput
          className="min-w-0 flex-1 px-3 py-3 font-sans text-base text-stone"
          accessibilityLabel="Search feedback by devotee or words"
          autoCapitalize="none"
          autoCorrect={false}
          value={search}
          onChangeText={setSearch}
          placeholder="Search a devotee or a word"
          placeholderTextColor={tokens.colors.stoneMuted}
        />
      </View>

      <View className="mt-3 flex-row flex-wrap gap-2">
        <Pill
          label="All topics"
          selected={categoryFilter === "all"}
          onPress={() => setCategoryFilter("all")}
        />
        {feedbackCategories.map((option) => (
          <Pill
            key={option}
            label={feedbackCategoryLabels[option]}
            selected={categoryFilter === option}
            onPress={() => setCategoryFilter(option)}
          />
        ))}
      </View>

      <View className="mt-2 flex-row flex-wrap gap-2">
        {statusFilters.map((option) => (
          <Pill
            key={option.key}
            label={option.label}
            selected={statusFilter === option.key}
            onPress={() => setStatusFilter(option.key)}
          />
        ))}
      </View>

      <Text className="my-3 font-sans-bold text-sm text-peacock">
        {allRows.length} note{allRows.length === 1 ? "" : "s"}
        {allRows.length === (everyone.data ?? []).length
          ? ""
          : ` of ${(everyone.data ?? []).length}`}
        {waitingCount ? ` · ${waitingCount} waiting` : ""}
      </Text>

      {reviewError ? <FormError message={reviewError} /> : null}
    </View>
  );

  const renderMine = (row: MyFeedback) => (
    <MyFeedbackCard row={row} onRemove={() => confirmRemove(row)} />
  );

  const renderForReview = (row: AllFeedback) => {
    const expanded = expandedId === row.id;
    const isSelf = row.devotee_id === activeUserId;

    return (
      <View className="mt-3 rounded-card border border-border bg-white p-card">
        <View className="flex-row items-center">
          <Avatar
            name={row.devotee_name}
            photoUrl={row.devotee_photo_url}
            size="small"
            tone={row.status === "new" ? "marigold" : "indigo"}
          />
          <View className="ml-3 min-w-0 flex-1">
            <Text
              className="font-sans-bold text-base text-stone"
              numberOfLines={1}
            >
              {row.devotee_name}
            </Text>
            <Text className="font-sans text-xs text-stoneMuted">
              {dayLabel(row.created_at)}
            </Text>
          </View>
        </View>

        <View className="mt-3 flex-row flex-wrap items-center gap-2">
          <CategoryBadge category={row.category} />
          <StatusBadge status={row.status} />
        </View>

        <Text className="mt-3 font-sans text-base leading-6 text-stone">
          {row.body}
        </Text>

        <ReplyBlock
          reply={row.reply}
          who={row.replied_by_name}
          at={row.replied_at}
        />

        {/* Stacked rather than side by side: "Mark reviewed" and "Message"
            do not both fit on a small Android phone at a readable size. */}
        <View className="mt-3 gap-2">
          <Pressable
            className="min-h-touch flex-row items-center justify-center rounded-button border border-border bg-white px-4"
            accessibilityRole="button"
            accessibilityState={{ expanded }}
            accessibilityLabel={
              row.status === "reviewed"
                ? `Change the reply to ${row.devotee_name}`
                : `Mark ${row.devotee_name}'s feedback reviewed`
            }
            onPress={() => openReviewFor(row)}
          >
            <Ionicons
              name={expanded ? "chevron-up" : "checkmark-done-outline"}
              size={19}
              color={tokens.colors.indigo}
            />
            <Text className="ml-2 font-sans-bold text-sm text-indigo">
              {expanded
                ? "Close"
                : row.status === "reviewed"
                  ? "Edit reply"
                  : "Mark reviewed"}
            </Text>
          </Pressable>

          {isSelf ? null : (
            <Pressable
              className="min-h-touch flex-row items-center justify-center rounded-button border border-border bg-white px-4"
              accessibilityRole="button"
              accessibilityLabel={`Message ${row.devotee_name}`}
              disabled={openingChatFor === row.id}
              onPress={() => messageDevotee(row)}
            >
              <Ionicons
                name="chatbubble-ellipses-outline"
                size={19}
                color={tokens.colors.peacock}
              />
              <Text className="ml-2 font-sans-bold text-sm text-peacock">
                {openingChatFor === row.id ? "Opening…" : "Message"}
              </Text>
            </Pressable>
          )}

          {row.can_delete ? (
            <RemoveRow
              accessibilityLabel={`Remove ${row.devotee_name}'s feedback`}
              onPress={() => confirmRemove(row)}
            />
          ) : null}
        </View>

        {expanded ? (
          <View className="mt-3 rounded-button border border-border bg-ivory p-3">
            <Text className="font-sans-bold text-xs uppercase tracking-wider text-stoneMuted">
              Quick replies
            </Text>
            <View className="mt-2 gap-2">
              {cannedFeedbackReplies.map((canned) => (
                <Pressable
                  key={canned}
                  className="min-h-touch justify-center rounded-button border border-border bg-white px-4 py-2.5"
                  accessibilityRole="button"
                  accessibilityLabel={`Reply: ${canned}`}
                  onPress={() => setReplyDraft(canned)}
                >
                  <Text className="font-sans text-sm leading-5 text-stone">
                    {canned}
                  </Text>
                </Pressable>
              ))}
            </View>

            <TextInput
              className="mt-3 min-h-[88px] rounded-button border border-border bg-white px-4 py-3 font-sans text-base text-stone"
              value={replyDraft}
              onChangeText={setReplyDraft}
              placeholder="Or write your own — optional"
              placeholderTextColor={tokens.colors.stoneMuted}
              multiline
              textAlignVertical="top"
              accessibilityLabel={`Your reply to ${row.devotee_name}`}
            />

            <View className="mt-3 gap-2">
              <Button
                icon="checkmark-done-outline"
                disabled={review.isPending}
                onPress={() => markReviewed(row, replyDraft)}
              >
                {review.isPending
                  ? "Saving…"
                  : replyDraft.trim()
                    ? "Send reply"
                    : "Mark reviewed"}
              </Button>
              {replyDraft.trim() && !row.reply ? (
                // Offered only while there is nothing to preserve: sending no
                // reply against a row that already has one leaves the old one
                // standing, so the button would not do what it says.
                <Button
                  variant="secondary"
                  disabled={review.isPending}
                  onPress={() => markReviewed(row, null)}
                >
                  Mark reviewed without a reply
                </Button>
              ) : null}
            </View>

            <Text className="mt-2 font-sans text-xs leading-5 text-stoneMuted">
              Either way the devotee is told it was read. A reply cannot be
              answered — use Message for a conversation.
            </Text>
          </View>
        ) : null}
      </View>
    );
  };

  return (
    <ListScreen
      topInset={false}
      data={items}
      keyExtractor={(item) => item.key}
      header={
        <>
          <ScreenTitle>Tell the temple</ScreenTitle>
          {faceSwitch}
          {activeFace === "mine" ? (
            <>
              {composer}
              <SectionHeader
                title="What you have sent"
                subtitle={
                  (mine.data ?? []).length
                    ? undefined
                    : "Nothing yet — the form above is the way in."
                }
              />
            </>
          ) : (
            reviewFilters
          )}
        </>
      }
      renderItem={(item) =>
        item.kind === "mine" ? renderMine(item.row) : renderForReview(item.row)
      }
      empty={
        failed ? (
          <LoadFailure
            reachable={reachable}
            message={errorMessage(query.error, "Feedback could not be loaded.")}
            onRetry={() => void query.refetch()}
          />
        ) : (
          <EmptyOrOffline
            reachable={reachable}
            loading={query.isLoading}
            loadingLabel="Loading feedback…"
            empty={
              <View className="items-center rounded-card border border-border bg-white px-card py-9">
                <View className="h-14 w-14 items-center justify-center rounded-pill bg-indigoSoft">
                  <Ionicons
                    name={
                      activeFace === "mine"
                        ? "chatbox-ellipses-outline"
                        : "file-tray-outline"
                    }
                    size={26}
                    color={tokens.colors.indigo}
                  />
                </View>
                <Text className="mt-4 text-center font-display text-xl text-stone">
                  {activeFace === "mine"
                    ? "Nothing sent yet"
                    : "Nothing to read"}
                </Text>
                <Text className="mt-2 max-w-72 text-center font-sans text-sm leading-5 text-stoneMuted">
                  {activeFace === "mine"
                    ? "Anything at all — the parking, a prasadam suggestion, something confusing in this app."
                    : (everyone.data ?? []).length
                      ? "No feedback matches these filters."
                      : "No devotee has written in yet."}
                </Text>
              </View>
            }
          />
        )
      }
    />
  );
}
