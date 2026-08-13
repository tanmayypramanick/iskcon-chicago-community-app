import { Ionicons } from "@expo/vector-icons";
import { useMemo, useState } from "react";
import {
  Alert,
  Image,
  Pressable,
  RefreshControl,
  Text,
  TextInput,
  View,
} from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";

import tokens from "../../design-tokens.json";
import { ModalScreen } from "../components/ModalScreen";
import {
  Avatar,
  Button,
  EmptyOrOffline,
  ListScreen,
  LoadFailure,
  ScreenTitle,
} from "../components/ui";
import {
  useAllNewsletterSubmissions,
  useDeleteNewsletterSubmission,
  useMayManageNewsletter,
  useReviewNewsletterSubmission,
} from "../features/newsletter/hooks";
import {
  cannedStoryReplies,
  type AllNewsletterSubmission,
} from "../features/newsletter/types";
import { FormError } from "../features/services/components";
import { errorMessage } from "../features/services/format";
import { formatChicagoShortDate } from "../lib/chicagoDate";
import { useServerReachable } from "../lib/connectivity";
import { copyText } from "../lib/copyText";
import { shareDocument } from "../lib/shareDocument";
import { sharePicture } from "../lib/sharePicture";
import { usePrototypeSession } from "../store/usePrototypeSession";

type StatusFilter = "all" | "new" | "reviewed";

const statusFilters: Array<{ key: StatusFilter; label: string }> = [
  { key: "all", label: "All" },
  { key: "new", label: "Waiting" },
  { key: "reviewed", label: "Read" },
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
  onPress,
}: {
  label: string;
  selected: boolean;
  onPress: () => void;
}) {
  return (
    <Pressable
      className={`min-h-10 items-center justify-center rounded-pill border px-3 ${
        selected ? "border-indigo bg-indigo" : "border-border bg-white"
      }`}
      accessibilityRole="button"
      accessibilityState={{ selected }}
      accessibilityLabel={label}
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
        {reviewed ? "Read" : "Waiting"}
      </Text>
    </View>
  );
}

/**
 * The editor's queue: every story devotees have asked to have in the
 * newsletter, with everything needed to actually use one — the words to copy
 * into the layout, the photographs at full size, the document, and a line back
 * to the devotee.
 *
 * Nothing here is gated on the viewer's role. The server returns an empty set
 * to anybody who may not manage the newsletter and puts `can_delete` on each
 * row, so an appointed editor holding no rank reaches this screen and its
 * Remove exactly as the President does.
 */
export function NewsletterSubmissionsScreen() {
  const activeUserId = usePrototypeSession((state) => state.activeUserId);
  const reachable = useServerReachable();
  const mayManage = useMayManageNewsletter(activeUserId);
  const submissions = useAllNewsletterSubmissions(mayManage.data !== false);
  const review = useReviewNewsletterSubmission(activeUserId);
  const remove = useDeleteNewsletterSubmission(activeUserId);

  const [search, setSearch] = useState("");
  const [statusFilter, setStatusFilter] = useState<StatusFilter>("all");
  const [expandedId, setExpandedId] = useState<string | null>(null);
  const [replyDraft, setReplyDraft] = useState("");
  const [actionError, setActionError] = useState<string | null>(null);
  const [viewingImage, setViewingImage] = useState<string | null>(null);
  const [busyFile, setBusyFile] = useState<string | null>(null);

  const all = submissions.data ?? [];
  const failed = submissions.isError && submissions.data === undefined;
  const waitingCount = all.filter((row) => row.status === "new").length;

  const rows = useMemo(() => {
    const term = search.trim().toLowerCase();
    return all.filter((row) => {
      if (statusFilter !== "all" && row.status !== statusFilter) return false;
      if (!term) return true;
      return (
        row.body.toLowerCase().includes(term) ||
        row.devotee_name.toLowerCase().includes(term) ||
        (row.reply ?? "").toLowerCase().includes(term)
      );
    });
  }, [all, search, statusFilter]);

  const openReviewFor = (row: AllNewsletterSubmission) => {
    const opening = expandedId !== row.id;
    setActionError(null);
    setExpandedId(opening ? row.id : null);
    setReplyDraft(opening ? (row.reply ?? "") : "");
  };

  const markReviewed = (row: AllNewsletterSubmission, reply: string | null) => {
    setActionError(null);
    review.mutate(
      { submissionId: row.id, reply },
      {
        onSuccess: () => {
          setExpandedId(null);
          setReplyDraft("");
        },
        onError: (caught) =>
          setActionError(errorMessage(caught, "That could not be saved.")),
      },
    );
  };

  const confirmRemove = (row: AllNewsletterSubmission) => {
    setActionError(null);
    Alert.alert(
      "Remove this request?",
      `${row.devotee_name}'s request disappears for them as well. This cannot be undone.`,
      [
        { text: "Keep", style: "cancel" },
        {
          text: "Remove",
          style: "destructive",
          onPress: () =>
            remove.mutate(row.id, {
              onError: (caught) =>
                setActionError(
                  errorMessage(caught, "That request could not be removed."),
                ),
            }),
        },
      ],
    );
  };

  const copyBody = (row: AllNewsletterSubmission) => {
    void copyText(row.body).then((copied) => {
      if (!copied) Alert.alert("This build cannot copy text.");
    });
  };

  const savePicture = (url: string) => {
    setBusyFile(url);
    void sharePicture(url, "story-photo")
      .catch((caught: unknown) =>
        Alert.alert(
          "Not saved",
          errorMessage(caught, "That picture could not be saved.") ?? "",
        ),
      )
      .finally(() => setBusyFile(null));
  };

  const saveDocument = (row: AllNewsletterSubmission) => {
    const url = row.file_url;
    if (!url) return;
    setBusyFile(url);
    void shareDocument(url, `story-${row.devotee_name.split(/\s+/)[0]}`)
      .catch((caught: unknown) =>
        Alert.alert(
          "Not downloaded",
          errorMessage(caught, "That file could not be downloaded.") ?? "",
        ),
      )
      .finally(() => setBusyFile(null));
  };

  const renderRow = (row: AllNewsletterSubmission) => {
    const expanded = expandedId === row.id;

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
          <StatusBadge status={row.status} />
        </View>

        <Text className="mt-3 font-sans text-base leading-6 text-stone">
          {row.body}
        </Text>

        <Pressable
          className="mt-2 min-h-10 flex-row items-center self-start rounded-pill bg-indigoSoft px-3"
          accessibilityRole="button"
          accessibilityLabel={`Copy ${row.devotee_name}'s words`}
          onPress={() => copyBody(row)}
        >
          <Ionicons
            name="copy-outline"
            size={16}
            color={tokens.colors.indigo}
          />
          <Text className="ml-1.5 font-sans-bold text-sm text-indigo">
            Copy the text
          </Text>
        </Pressable>

        {row.image_urls.length ? (
          <View className="mt-3 flex-row flex-wrap gap-2">
            {row.image_urls.map((url, index) => (
              <Pressable
                key={url}
                accessibilityRole="imagebutton"
                accessibilityLabel={`Open photo ${index + 1} of ${row.image_urls.length}`}
                accessibilityHint="Opens it full size, where it can be saved"
                onPress={() => setViewingImage(url)}
              >
                <Image
                  source={{ uri: url }}
                  style={{ width: 88, height: 88, borderRadius: 12 }}
                  resizeMode="cover"
                  accessibilityIgnoresInvertColors
                />
              </Pressable>
            ))}
          </View>
        ) : null}

        {row.file_url ? (
          <View
            className={`mt-3 ${busyFile === row.file_url ? "opacity-60" : ""}`}
          >
            <Button
              variant="secondary"
              icon="download-outline"
              disabled={busyFile === row.file_url}
              onPress={() => saveDocument(row)}
            >
              {busyFile === row.file_url
                ? "Preparing…"
                : "Download the document"}
            </Button>
          </View>
        ) : null}

        {row.reply ? (
          <View className="mt-3 rounded-button border border-peacock/20 bg-peacockSoft px-4 py-3">
            <Text className="font-sans-bold text-xs uppercase tracking-wider text-peacock">
              Replied
            </Text>
            <Text className="mt-1.5 font-sans text-sm leading-6 text-stone">
              {row.reply}
            </Text>
            {row.replied_by_name || row.replied_at ? (
              <Text className="mt-2 font-sans text-xs text-stoneMuted">
                {[row.replied_by_name, dayLabel(row.replied_at)]
                  .filter(Boolean)
                  .join(" · ")}
              </Text>
            ) : null}
          </View>
        ) : null}

        <Pressable
          className="mt-3 min-h-touch flex-row items-center justify-center rounded-button border border-border bg-white px-4"
          accessibilityRole="button"
          accessibilityState={{ expanded }}
          accessibilityLabel={
            row.status === "reviewed"
              ? `Change the reply to ${row.devotee_name}`
              : `Mark ${row.devotee_name}'s request read`
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
                : "Mark read"}
          </Text>
        </Pressable>

        {expanded ? (
          <View className="mt-3 rounded-button border border-border bg-ivory p-3">
            <Text className="font-sans-bold text-xs uppercase tracking-wider text-stoneMuted">
              Quick replies
            </Text>
            <View className="mt-2 gap-2">
              {cannedStoryReplies.map((canned) => (
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

            <View
              className={`mt-3 gap-2 ${review.isPending ? "opacity-60" : ""}`}
            >
              <Button
                icon="checkmark-done-outline"
                disabled={review.isPending}
                onPress={() => markReviewed(row, replyDraft)}
              >
                {review.isPending
                  ? "Saving…"
                  : replyDraft.trim()
                    ? "Send reply"
                    : "Mark read"}
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
                  Mark read without a reply
                </Button>
              ) : null}
            </View>

            <Text className="mt-2 font-sans text-xs leading-5 text-stoneMuted">
              Either way the devotee is told their request was read.
            </Text>
          </View>
        ) : null}

        {/* Author, the two office holders, or an appointed editor — the server
            has already worked out which, so this asks it rather than the role. */}
        {row.can_delete ? (
          <Pressable
            className="mt-3 min-h-touch flex-row items-center justify-center rounded-button border border-border bg-white px-4"
            accessibilityRole="button"
            accessibilityLabel={`Remove ${row.devotee_name}'s request`}
            onPress={() => confirmRemove(row)}
          >
            <Ionicons
              name="trash-outline"
              size={17}
              color={tokens.colors.vermilion}
            />
            <Text className="ml-2 font-sans-bold text-sm text-vermilion">
              Remove
            </Text>
          </Pressable>
        ) : null}
      </View>
    );
  };

  return (
    <>
      <ListScreen
        topInset={false}
        data={rows}
        keyExtractor={(row) => row.id}
        refreshControl={
          <RefreshControl
            refreshing={submissions.isRefetching}
            onRefresh={() => void submissions.refetch()}
            tintColor={tokens.colors.indigo}
            colors={[tokens.colors.indigo]}
          />
        }
        header={
          <>
            <ScreenTitle eyebrow="Newsletter">Story requests</ScreenTitle>

            <View className="min-h-touch flex-row items-center rounded-button border border-border bg-white px-4">
              <Ionicons name="search" size={19} color={tokens.colors.indigo} />
              <TextInput
                className="min-w-0 flex-1 px-3 py-3 font-sans text-base text-stone"
                accessibilityLabel="Search requests by devotee or words"
                autoCapitalize="none"
                autoCorrect={false}
                value={search}
                onChangeText={setSearch}
                placeholder="Search a devotee or a word"
                placeholderTextColor={tokens.colors.stoneMuted}
              />
            </View>

            <View className="mt-3 flex-row flex-wrap gap-2">
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
              {rows.length} {rows.length === 1 ? "request" : "requests"}
              {rows.length === all.length ? "" : ` of ${all.length}`}
              {waitingCount ? ` · ${waitingCount} waiting` : ""}
            </Text>

            {actionError ? <FormError message={actionError} /> : null}
          </>
        }
        renderItem={renderRow}
        empty={
          failed ? (
            <LoadFailure
              reachable={reachable}
              message={errorMessage(
                submissions.error,
                "The requests could not be loaded.",
              )}
              onRetry={() => void submissions.refetch()}
            />
          ) : (
            <EmptyOrOffline
              reachable={reachable}
              loading={submissions.isLoading}
              loadingLabel="Loading requests…"
              empty={
                <View className="items-center rounded-card border border-border bg-white px-card py-9">
                  <View className="h-14 w-14 items-center justify-center rounded-pill bg-indigoSoft">
                    <Ionicons
                      name="file-tray-outline"
                      size={26}
                      color={tokens.colors.indigo}
                    />
                  </View>
                  <Text className="mt-4 text-center font-display text-xl text-stone">
                    {all.length ? "Nothing to show" : "Nothing waiting"}
                  </Text>
                  <Text className="mt-2 max-w-80 text-center font-sans text-sm leading-6 text-stoneMuted">
                    {all.length
                      ? "No request matches these filters."
                      : "Requests devotees send in for the newsletter will arrive here."}
                  </Text>
                </View>
              }
            />
          )
        }
      />

      <ModalScreen
        visible={viewingImage !== null}
        onClose={() => setViewingImage(null)}
        title="Story photo"
        backLabel="Close the picture"
        tone="dark"
        scroll={false}
      >
        <Pressable
          className="flex-1 items-center justify-center"
          accessibilityRole="button"
          accessibilityLabel="Close the picture"
          onPress={() => setViewingImage(null)}
        >
          {viewingImage ? (
            <Image
              source={{ uri: viewingImage }}
              style={{ width: "100%", height: "78%" }}
              resizeMode="contain"
              accessibilityIgnoresInvertColors
            />
          ) : null}
        </Pressable>
        <SafeAreaView edges={["bottom"]}>
          <View className="flex-row justify-center px-screen pb-4">
            <Pressable
              className={`min-h-touch flex-row items-center justify-center rounded-pill bg-white/15 px-6 ${
                busyFile === viewingImage ? "opacity-60" : ""
              }`}
              accessibilityRole="button"
              accessibilityLabel="Save this picture"
              accessibilityState={{ disabled: busyFile === viewingImage }}
              disabled={busyFile === viewingImage}
              onPress={() => viewingImage && savePicture(viewingImage)}
            >
              <Ionicons
                name="download-outline"
                size={18}
                color={tokens.colors.ivory}
              />
              <Text className="ml-2 font-sans-bold text-sm text-ivory">
                {busyFile === viewingImage ? "Preparing…" : "Save"}
              </Text>
            </Pressable>
          </View>
        </SafeAreaView>
      </ModalScreen>
    </>
  );
}
