import { Ionicons } from "@expo/vector-icons";
import { useNavigation, type NavigationProp } from "@react-navigation/native";
import { useState } from "react";
import {
  Alert,
  Image,
  Pressable,
  RefreshControl,
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
  ScreenTitle,
  SectionHeader,
  SkeletonCard,
} from "../components/ui";
import {
  pickMessageImage,
  pickNewsletterFile,
  useAllNewsletterSubmissions,
  useDeleteNewsletter,
  useDeleteNewsletterSubmission,
  useMayManageNewsletter,
  useMyNewsletterSubmissions,
  useNewsletters,
  usePostNewsletter,
  useSubmitNewsletterStory,
} from "../features/newsletter/hooks";
import {
  MAX_STORY_PHOTOS,
  type MyNewsletterSubmission,
  type Newsletter,
  type PickedMessageImage,
  type PickedNewsletterFile,
} from "../features/newsletter/types";
import { FormError } from "../features/services/components";
import { errorMessage } from "../features/services/format";
import { formatChicagoShortDate } from "../lib/chicagoDate";
import { useServerReachable } from "../lib/connectivity";
import { shareDocument } from "../lib/shareDocument";
import type { HomeStackParamList } from "../navigation/types";
import { usePrototypeSession } from "../store/usePrototypeSession";

const MONTH_NAMES = [
  "January",
  "February",
  "March",
  "April",
  "May",
  "June",
  "July",
  "August",
  "September",
  "October",
  "November",
  "December",
];

/**
 * "August 2026" out of "2026-08-01", read straight off the string.
 *
 * Deliberately not `new Date(month)`: a bare date string is parsed as UTC
 * midnight, which is the previous month for anybody west of Greenwich — and
 * every devotee reading this is.
 */
function monthLabel(month: string) {
  const [year, index] = month.split("-");
  const name = MONTH_NAMES[Number(index) - 1];
  return name ? `${name} ${year}` : month;
}

function monthKey(year: number, monthIndex: number) {
  return `${year}-${String(monthIndex + 1).padStart(2, "0")}-01`;
}

/** A name the devotee will recognise once the file is on their phone. */
function fileStem(title: string) {
  const cleaned = title
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
  return cleaned || "newsletter";
}

function dayLabel(value: string | null) {
  if (!value) return null;
  const at = new Date(value);
  if (Number.isNaN(at.getTime())) return null;
  return formatChicagoShortDate(at);
}

function StoryStatusBadge({ status }: { status: "new" | "reviewed" }) {
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

/** One issue: the cover, what is in it, and a way to get the file. */
function IssueCard({
  issue,
  downloading,
  onDownload,
  onDelete,
}: {
  issue: Newsletter;
  downloading: boolean;
  onDownload: () => void;
  onDelete: () => void;
}) {
  const poster = issue.posted_by_name?.trim() || "The temple";

  return (
    <View className="mb-3 overflow-hidden rounded-card border border-border bg-white">
      {issue.cover_image_url ? (
        // Contained rather than cropped: a newsletter cover is usually a tall
        // page and a centre crop cuts the masthead off the top of it.
        <View className="bg-sandalwood">
          <Image
            source={{ uri: issue.cover_image_url }}
            style={{ width: "100%", aspectRatio: 4 / 3 }}
            resizeMode="contain"
            accessibilityIgnoresInvertColors
          />
        </View>
      ) : null}

      <View className="p-card">
        <View className="flex-row items-start">
          <View className="min-w-0 flex-1">
            <Text className="font-sans-bold text-xs uppercase tracking-widest text-peacock">
              {monthLabel(issue.month)}
            </Text>
            <Text className="mt-1 font-display text-xl leading-7 text-stone">
              {issue.title}
            </Text>
          </View>
          {issue.can_delete ? (
            <Pressable
              className="-mr-1 ml-2 h-11 w-11 items-center justify-center rounded-pill"
              accessibilityRole="button"
              accessibilityLabel={`Take down ${issue.title}`}
              onPress={onDelete}
            >
              <Ionicons
                name="trash-outline"
                size={20}
                color={tokens.colors.vermilion}
              />
            </Pressable>
          ) : null}
        </View>

        {issue.notes ? (
          <Text className="mt-3 font-sans text-base leading-6 text-stone">
            {issue.notes}
          </Text>
        ) : null}

        <View className={`mt-4 ${downloading ? "opacity-60" : ""}`}>
          <Button
            icon="download-outline"
            disabled={downloading}
            onPress={onDownload}
          >
            {downloading ? "Preparing…" : "Download"}
          </Button>
        </View>

        <View className="mt-3 flex-row items-center">
          <Avatar
            name={poster}
            photoUrl={issue.posted_by_photo_url}
            size="tiny"
            tone="peacock"
          />
          <Text className="ml-2 min-w-0 flex-1 font-sans text-sm text-stoneMuted">
            {poster}
            {dayLabel(issue.created_at)
              ? ` · ${dayLabel(issue.created_at)}`
              : ""}
          </Text>
        </View>
      </View>
    </View>
  );
}

/** The month the issue is filed under, stepped rather than picked out of a
 * calendar: only the month matters and a day picker invites a wrong one. */
function MonthStepper({
  year,
  monthIndex,
  onChange,
}: {
  year: number;
  monthIndex: number;
  onChange: (year: number, monthIndex: number) => void;
}) {
  const step = (delta: number) => {
    const total = year * 12 + monthIndex + delta;
    onChange(Math.floor(total / 12), ((total % 12) + 12) % 12);
  };

  return (
    <View className="min-h-touch flex-row items-center justify-between rounded-button border border-border bg-white px-2">
      <Pressable
        className="h-11 w-11 items-center justify-center rounded-pill"
        accessibilityRole="button"
        accessibilityLabel="The month before"
        onPress={() => step(-1)}
      >
        <Ionicons name="chevron-back" size={20} color={tokens.colors.indigo} />
      </Pressable>
      <Text
        className="min-w-0 flex-1 text-center font-sans-bold text-base text-stone"
        numberOfLines={1}
      >
        {MONTH_NAMES[monthIndex]} {year}
      </Text>
      <Pressable
        className="h-11 w-11 items-center justify-center rounded-pill"
        accessibilityRole="button"
        accessibilityLabel="The month after"
        onPress={() => step(1)}
      >
        <Ionicons
          name="chevron-forward"
          size={20}
          color={tokens.colors.indigo}
        />
      </Pressable>
    </View>
  );
}

/**
 * Putting out an issue. A modal over the list rather than a route of its own:
 * it is one short form, and an editor who opens it by mistake should be one
 * dismissal away from the issues they were reading.
 */
function PostNewsletterModal({
  visible,
  onClose,
}: {
  visible: boolean;
  onClose: () => void;
}) {
  const activeUserId = usePrototypeSession((state) => state.activeUserId);
  const post = usePostNewsletter(activeUserId);
  const today = new Date();

  const [title, setTitle] = useState("");
  const [year, setYear] = useState(today.getFullYear());
  const [monthIndex, setMonthIndex] = useState(today.getMonth());
  const [file, setFile] = useState<PickedNewsletterFile | null>(null);
  const [cover, setCover] = useState<PickedMessageImage | null>(null);
  const [notes, setNotes] = useState("");
  const [formError, setFormError] = useState<string | null>(null);

  const dismiss = () => {
    setTitle("");
    setYear(today.getFullYear());
    setMonthIndex(today.getMonth());
    setFile(null);
    setCover(null);
    setNotes("");
    setFormError(null);
    post.reset();
    onClose();
  };

  const chooseFile = () => {
    setFormError(null);
    void (async () => {
      try {
        const picked = await pickNewsletterFile();
        if (picked) setFile(picked);
      } catch (caught) {
        setFormError(
          errorMessage(caught, "That file could not be used.") ?? null,
        );
      }
    })();
  };

  const chooseCover = (source: "library" | "camera") => {
    void (async () => {
      try {
        const picked = await pickMessageImage(source);
        if (picked) setCover(picked);
      } catch (caught) {
        Alert.alert(
          "No cover added",
          errorMessage(caught, "That photo could not be used.") ?? "",
        );
      }
    })();
  };

  const attachCover = () => {
    Alert.alert("Add a cover", undefined, [
      { text: "Take a photo", onPress: () => chooseCover("camera") },
      { text: "Choose from library", onPress: () => chooseCover("library") },
      { text: "Cancel", style: "cancel" },
    ]);
  };

  const submit = () => {
    setFormError(null);
    const cleanTitle = title.trim();
    if (!cleanTitle) {
      setFormError("Please give the newsletter a title.");
      return;
    }
    if (!file) {
      setFormError("Please attach the newsletter file.");
      return;
    }
    post.mutate(
      {
        title: cleanTitle,
        month: monthKey(year, monthIndex),
        file,
        cover,
        notes: notes.trim() || null,
      },
      { onSuccess: dismiss },
    );
  };

  const error =
    formError ??
    errorMessage(post.error, "The newsletter could not be posted.");

  return (
    <ModalScreen
      visible={visible}
      onClose={dismiss}
      eyebrow="Newsletter"
      title="Post an issue"
      backLabel="Close without posting"
    >
      <SectionHeader title="Title" />
      <TextInput
        className="min-h-touch rounded-button border border-border bg-white px-4 font-sans text-base text-stone"
        placeholder="Sri Sri Kishore Kishori Gazette"
        placeholderTextColor={tokens.colors.stoneMuted}
        value={title}
        onChangeText={setTitle}
        maxLength={120}
        autoCapitalize="sentences"
      />

      <View className="mt-section">
        <SectionHeader
          title="Month"
          subtitle="Which month this issue is for."
        />
        <MonthStepper
          year={year}
          monthIndex={monthIndex}
          onChange={(nextYear, nextMonth) => {
            setYear(nextYear);
            setMonthIndex(nextMonth);
          }}
        />
      </View>

      <View className="mt-section">
        <SectionHeader title="The file" subtitle="A PDF, up to 25 MB." />
        {file ? (
          <View className="rounded-card border border-border bg-white p-card">
            <View className="flex-row items-center">
              <View className="h-10 w-10 items-center justify-center rounded-pill bg-vermilionSoft">
                <Ionicons
                  name="document-text-outline"
                  size={20}
                  color={tokens.colors.vermilion}
                />
              </View>
              <Text
                className="ml-3 min-w-0 flex-1 font-sans-bold text-sm text-stone"
                numberOfLines={2}
              >
                {file.name}
              </Text>
            </View>
            <View className="mt-3 gap-2">
              <Button
                variant="secondary"
                icon="swap-horizontal-outline"
                onPress={chooseFile}
              >
                Choose another
              </Button>
              <Button
                variant="secondary"
                icon="trash-outline"
                onPress={() => setFile(null)}
              >
                Remove
              </Button>
            </View>
          </View>
        ) : (
          <Button
            variant="secondary"
            icon="document-attach-outline"
            onPress={chooseFile}
          >
            Choose a PDF
          </Button>
        )}
      </View>

      <View className="mt-section">
        <SectionHeader title="Cover" subtitle="Optional" />
        {cover ? (
          <View>
            <Image
              source={{ uri: cover.uri }}
              style={{ width: "100%", aspectRatio: 4 / 3, borderRadius: 16 }}
              resizeMode="cover"
              accessibilityIgnoresInvertColors
            />
            <View className="mt-3 flex-row gap-3">
              <View className="flex-1">
                <Button
                  variant="secondary"
                  icon="swap-horizontal-outline"
                  onPress={attachCover}
                >
                  Replace
                </Button>
              </View>
              <View className="flex-1">
                <Button
                  variant="secondary"
                  icon="trash-outline"
                  onPress={() => setCover(null)}
                >
                  Remove
                </Button>
              </View>
            </View>
          </View>
        ) : (
          <Button
            variant="secondary"
            icon="image-outline"
            onPress={attachCover}
          >
            Add a cover
          </Button>
        )}
      </View>

      <View className="mt-section">
        <SectionHeader title="Notes" subtitle="Optional — what is inside." />
        <TextInput
          className="min-h-[96px] rounded-button border border-border bg-white px-4 py-3 font-sans text-base leading-6 text-stone"
          placeholder="Janmashtami photographs, the new Bhakti Sastri class, and a word from the President."
          placeholderTextColor={tokens.colors.stoneMuted}
          value={notes}
          onChangeText={setNotes}
          multiline
          textAlignVertical="top"
          maxLength={2000}
          autoCapitalize="sentences"
        />
      </View>

      {error ? <FormError message={error} /> : null}

      <View className={`mt-section ${post.isPending ? "opacity-60" : ""}`}>
        <Button
          icon="newspaper-outline"
          disabled={post.isPending}
          onPress={submit}
        >
          {post.isPending ? "Posting…" : "Post the issue"}
        </Button>
        <Text className="mt-2 font-sans text-xs leading-5 text-stoneMuted">
          Every devotee is told when an issue goes out.
        </Text>
      </View>
    </ModalScreen>
  );
}

/** A request the devotee sent, and whatever came back. */
function MySubmissionCard({
  row,
  onRemove,
}: {
  row: MyNewsletterSubmission;
  onRemove: () => void;
}) {
  const acknowledged = row.status === "reviewed" && !row.reply;

  return (
    <View className="mt-3 rounded-card border border-border bg-white p-card">
      <View className="flex-row flex-wrap items-center gap-2">
        <StoryStatusBadge status={row.status} />
        <Text className="font-sans text-xs text-stoneMuted">
          {dayLabel(row.created_at)}
        </Text>
      </View>

      <Text className="mt-3 font-sans text-base leading-6 text-stone">
        {row.body}
      </Text>

      {row.image_urls.length ? (
        <View className="mt-3 flex-row flex-wrap gap-2">
          {row.image_urls.map((url) => (
            <Image
              key={url}
              source={{ uri: url }}
              style={{ width: 72, height: 72, borderRadius: 12 }}
              resizeMode="cover"
              accessibilityIgnoresInvertColors
            />
          ))}
        </View>
      ) : null}

      {row.file_url ? (
        <View className="mt-3 flex-row items-center">
          <Ionicons
            name="document-text-outline"
            size={16}
            color={tokens.colors.stoneMuted}
          />
          <Text className="ml-1.5 font-sans text-xs text-stoneMuted">
            A document was attached
          </Text>
        </View>
      ) : null}

      {row.reply ? (
        <View className="mt-3 rounded-button border border-peacock/20 bg-peacockSoft px-4 py-3">
          <Text className="font-sans-bold text-xs uppercase tracking-wider text-peacock">
            The newsletter team replied
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

      {/* The server's answer, not the viewer's role: an author may remove
          their own, and so may the newsletter team. */}
      {row.can_delete ? (
        <Pressable
          className="mt-3 min-h-touch flex-row items-center justify-center rounded-button border border-border bg-white px-4"
          accessibilityRole="button"
          accessibilityLabel="Remove the request you sent"
          onPress={onRemove}
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
}

/**
 * Asking for a story to go in. The form, and underneath it every request this
 * devotee has already sent — one that vanishes on send reads as one nobody
 * received.
 *
 * Deliberately worded as a request throughout: the editors write the issue
 * from what arrives here, so nothing a devotee sends is published as it stands.
 */
function StoryRequestModal({
  visible,
  onClose,
}: {
  visible: boolean;
  onClose: () => void;
}) {
  const activeUserId = usePrototypeSession((state) => state.activeUserId);
  const reachable = useServerReachable();
  // This component stays mounted behind the list so the sheet can animate in,
  // so the fetch waits for the sheet rather than firing on every visit to the
  // newsletter.
  const mine = useMyNewsletterSubmissions(visible ? activeUserId : null);
  const submit = useSubmitNewsletterStory(activeUserId);
  const removeStory = useDeleteNewsletterSubmission(activeUserId);

  const [body, setBody] = useState("");
  const [images, setImages] = useState<PickedMessageImage[]>([]);
  const [file, setFile] = useState<PickedNewsletterFile | null>(null);
  const [formError, setFormError] = useState<string | null>(null);
  const [sent, setSent] = useState(false);

  const full = images.length >= MAX_STORY_PHOTOS;

  const dismiss = () => {
    setBody("");
    setImages([]);
    setFile(null);
    setFormError(null);
    setSent(false);
    submit.reset();
    onClose();
  };

  const addPhoto = (source: "library" | "camera") => {
    void (async () => {
      try {
        const picked = await pickMessageImage(source);
        // The ceiling is checked again here, not only on the button: the
        // picker takes a moment and nothing stops a second tap during it.
        if (picked) {
          setImages((current) =>
            current.length >= MAX_STORY_PHOTOS ? current : [...current, picked],
          );
        }
      } catch (caught) {
        Alert.alert(
          "No photo added",
          errorMessage(caught, "That photo could not be used.") ?? "",
        );
      }
    })();
  };

  const attachPhoto = () => {
    if (full) return;
    Alert.alert("Add a photo", undefined, [
      { text: "Take a photo", onPress: () => addPhoto("camera") },
      { text: "Choose from library", onPress: () => addPhoto("library") },
      { text: "Cancel", style: "cancel" },
    ]);
  };

  const chooseFile = () => {
    setFormError(null);
    void (async () => {
      try {
        const picked = await pickNewsletterFile();
        if (picked) setFile(picked);
      } catch (caught) {
        setFormError(
          errorMessage(caught, "That file could not be used.") ?? null,
        );
      }
    })();
  };

  const send = () => {
    setFormError(null);
    setSent(false);
    const cleanBody = body.trim();
    if (!cleanBody) {
      setFormError("Please write your story before sending the request.");
      return;
    }
    submit.mutate(
      { body: cleanBody, images, file },
      {
        onSuccess: () => {
          setBody("");
          setImages([]);
          setFile(null);
          setSent(true);
        },
        onError: (caught) =>
          setFormError(
            errorMessage(caught, "That request could not be sent.") ?? null,
          ),
      },
    );
  };

  const confirmRemoveStory = (row: MyNewsletterSubmission) => {
    Alert.alert(
      "Remove this request?",
      "It comes back off the newsletter team's list. This cannot be undone.",
      [
        { text: "Keep", style: "cancel" },
        {
          text: "Remove",
          style: "destructive",
          onPress: () =>
            removeStory.mutate(row.id, {
              onError: (caught) =>
                Alert.alert(
                  "Not removed",
                  errorMessage(caught, "That request could not be removed.") ??
                    "",
                ),
            }),
        },
      ],
    );
  };

  const rows = mine.data ?? [];
  const failed = mine.isError && mine.data === undefined;

  return (
    <ModalScreen
      visible={visible}
      onClose={dismiss}
      eyebrow="Newsletter"
      title="Story request"
      backLabel="Close without sending"
    >
      <View className="rounded-card border border-border bg-white p-card">
        <Text className="font-sans text-sm leading-6 text-stoneMuted">
          Tell the editors what you would like the newsletter to carry — a
          festival you helped with, a realisation, a photograph of the Deities.
          They write each issue from the requests that come in, so send the
          material rather than the finished piece.
        </Text>

        <TextInput
          className="mt-4 min-h-[128px] rounded-button border border-border bg-white px-4 py-3 font-sans text-base leading-6 text-stone"
          value={body}
          onChangeText={(value) => {
            setBody(value);
            if (formError) setFormError(null);
            if (sent) setSent(false);
          }}
          placeholder="What would you like the newsletter to carry?"
          placeholderTextColor={tokens.colors.stoneMuted}
          multiline
          textAlignVertical="top"
          maxLength={4000}
          autoCapitalize="sentences"
          accessibilityLabel="What you would like the newsletter to carry"
        />

        <Text className="mt-4 font-sans-bold text-xs uppercase tracking-wider text-stoneMuted">
          Photos · {images.length} of {MAX_STORY_PHOTOS}
        </Text>
        {images.length ? (
          <View className="mt-2 flex-row flex-wrap gap-2">
            {images.map((image, index) => (
              <View key={`${image.uri}-${index}`}>
                <Image
                  source={{ uri: image.uri }}
                  style={{ width: 84, height: 84, borderRadius: 12 }}
                  resizeMode="cover"
                  accessibilityIgnoresInvertColors
                />
                <Pressable
                  className="absolute -right-2 -top-2 h-8 w-8 items-center justify-center rounded-pill border border-border bg-white"
                  // The badge cannot grow without covering the photo it sits
                  // on, so the target grows instead.
                  hitSlop={10}
                  accessibilityRole="button"
                  accessibilityLabel={`Remove photo ${index + 1}`}
                  onPress={() =>
                    setImages((current) =>
                      current.filter((_, slot) => slot !== index),
                    )
                  }
                >
                  <Ionicons
                    name="close"
                    size={16}
                    color={tokens.colors.vermilion}
                  />
                </Pressable>
              </View>
            ))}
          </View>
        ) : null}
        <View className="mt-2">
          <Button
            variant="secondary"
            icon="image-outline"
            disabled={full}
            onPress={attachPhoto}
          >
            {full ? `That is all ${MAX_STORY_PHOTOS}` : "Add a photo"}
          </Button>
        </View>

        <Text className="mt-4 font-sans-bold text-xs uppercase tracking-wider text-stoneMuted">
          Document · optional
        </Text>
        {file ? (
          <View className="mt-2 flex-row items-center rounded-button border border-border bg-ivory px-4 py-3">
            <Ionicons
              name="document-text-outline"
              size={18}
              color={tokens.colors.indigo}
            />
            <Text
              className="ml-2 min-w-0 flex-1 font-sans text-sm text-stone"
              numberOfLines={2}
            >
              {file.name}
            </Text>
            <Pressable
              className="ml-2 h-10 w-10 items-center justify-center rounded-pill"
              hitSlop={8}
              accessibilityRole="button"
              accessibilityLabel="Remove the document"
              onPress={() => setFile(null)}
            >
              <Ionicons
                name="close"
                size={18}
                color={tokens.colors.vermilion}
              />
            </Pressable>
          </View>
        ) : (
          <View className="mt-2">
            <Button
              variant="secondary"
              icon="document-attach-outline"
              onPress={chooseFile}
            >
              Attach a document
            </Button>
          </View>
        )}

        <View className={`mt-4 ${submit.isPending ? "opacity-60" : ""}`}>
          <Button
            icon="send-outline"
            disabled={submit.isPending || !body.trim()}
            onPress={send}
          >
            {submit.isPending ? "Sending…" : "Send the request"}
          </Button>
          <Text className="mt-2 font-sans text-xs leading-5 text-stoneMuted">
            The newsletter team reads every request and decides which issue it
            belongs in.
          </Text>
        </View>

        {sent ? (
          <View className="mt-3 flex-row items-center rounded-button bg-peacockSoft px-4 py-3">
            <Ionicons
              name="checkmark-circle"
              size={18}
              color={tokens.colors.peacock}
            />
            <Text className="ml-2 min-w-0 flex-1 font-sans text-sm leading-5 text-peacock">
              Sent. Your request is below, and you will be told when it has been
              read.
            </Text>
          </View>
        ) : null}

        {formError ? <FormError message={formError} /> : null}
      </View>

      <View className="mt-section">
        <SectionHeader
          title="Your requests"
          subtitle={rows.length ? undefined : "Nothing sent yet."}
        />
        {failed ? (
          <LoadFailure
            reachable={reachable}
            message={errorMessage(
              mine.error,
              "Your requests could not be loaded.",
            )}
            onRetry={() => void mine.refetch()}
          />
        ) : rows.length ? (
          rows.map((row) => (
            <MySubmissionCard
              key={row.id}
              row={row}
              onRemove={() => confirmRemoveStory(row)}
            />
          ))
        ) : (
          <EmptyOrOffline
            reachable={reachable}
            loading={mine.isLoading}
            loadingLabel="Loading your requests…"
            empty={
              <View className="rounded-card border border-border bg-white px-card py-6">
                <Text className="text-center font-sans text-sm leading-6 text-stoneMuted">
                  Every request you send appears here with the team's reply.
                </Text>
              </View>
            }
          />
        )}
      </View>
    </ModalScreen>
  );
}

/**
 * The temple's newsletter: every back issue, newest month first, open to every
 * devotee.
 *
 * Posting, the request queue and the editor list are offered on the server's
 * own `may_manage_newsletter()` and the `can_manage` it puts on each row, never
 * on the client's role ladder — an editor is a grant rather than a rank, so a
 * devotee holding no rank at all may hold all three of those doors.
 */
export function NewsletterScreen() {
  const navigation = useNavigation<NavigationProp<HomeStackParamList>>();
  const activeUserId = usePrototypeSession((state) => state.activeUserId);
  const reachable = useServerReachable();
  const issues = useNewsletters();
  const mayManage = useMayManageNewsletter(activeUserId);
  const remove = useDeleteNewsletter();

  const [composerOpen, setComposerOpen] = useState(false);
  const [requestOpen, setRequestOpen] = useState(false);
  const [downloadingId, setDownloadingId] = useState<string | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);

  const rows = issues.data ?? [];
  const failed = issues.isError && issues.data === undefined;
  // The rows carry the same answer, but a temple with no issues yet has no
  // rows — and that is precisely when the first one has to be posted.
  const canManage =
    mayManage.data === true || rows.some((issue) => issue.can_manage);

  // Nothing notifies an editor that a request has arrived — the migration
  // deliberately does not — so the only way the queue gets worked through is
  // if the door to it says how much is behind it.
  const queue = useAllNewsletterSubmissions(canManage);
  const waitingCount = (queue.data ?? []).filter(
    (row) => row.status === "new",
  ).length;

  const download = (issue: Newsletter) => {
    setActionError(null);
    setDownloadingId(issue.id);
    void shareDocument(
      issue.file_url,
      fileStem(issue.title),
      "Save the newsletter",
    )
      .catch((caught: unknown) =>
        Alert.alert(
          "Not downloaded",
          errorMessage(caught, "That file could not be downloaded.") ?? "",
        ),
      )
      .finally(() => setDownloadingId(null));
  };

  const confirmDelete = (issue: Newsletter) => {
    setActionError(null);
    Alert.alert(
      "Take this issue down?",
      `“${issue.title}” will disappear for everyone. This cannot be undone.`,
      [
        { text: "Keep", style: "cancel" },
        {
          text: "Take down",
          style: "destructive",
          onPress: () =>
            remove.mutate(issue.id, {
              onError: (caught) =>
                setActionError(
                  errorMessage(caught, "That issue could not be taken down."),
                ),
            }),
        },
      ],
    );
  };

  return (
    <>
      <ListScreen
        topInset={false}
        data={rows}
        keyExtractor={(issue) => issue.id}
        refreshControl={
          <RefreshControl
            refreshing={issues.isRefetching}
            onRefresh={() => void issues.refetch()}
            tintColor={tokens.colors.indigo}
            colors={[tokens.colors.indigo]}
          />
        }
        header={
          <>
            <ScreenTitle eyebrow="From the temple">Newsletter</ScreenTitle>

            {/* Stacked rather than side by side: four labels this long do not
                fit across a small Android phone. Whichever action belongs to
                the viewer leads and is the only filled one. */}
            <View className="mb-section gap-2">
              {canManage ? (
                <>
                  <Button
                    icon="newspaper-outline"
                    onPress={() => setComposerOpen(true)}
                  >
                    Post an issue
                  </Button>
                  <Button
                    icon="file-tray-full-outline"
                    variant="secondary"
                    onPress={() => navigation.navigate("NewsletterSubmissions")}
                  >
                    {waitingCount
                      ? `Story requests · ${waitingCount} waiting`
                      : "Story requests"}
                  </Button>
                  <Button
                    icon="people-outline"
                    variant="secondary"
                    onPress={() => navigation.navigate("NewsletterEditors")}
                  >
                    Newsletter editors
                  </Button>
                </>
              ) : null}

              <Button
                icon="create-outline"
                variant={canManage ? "secondary" : "primary"}
                onPress={() => setRequestOpen(true)}
              >
                Submit a story request
              </Button>
            </View>

            {actionError ? <FormError message={actionError} /> : null}
          </>
        }
        renderItem={(issue) => (
          <IssueCard
            issue={issue}
            downloading={downloadingId === issue.id}
            onDownload={() => download(issue)}
            onDelete={() => confirmDelete(issue)}
          />
        )}
        empty={
          issues.isLoading ? (
            <View className="gap-3">
              <SkeletonCard />
              <SkeletonCard />
            </View>
          ) : failed ? (
            <LoadFailure
              reachable={reachable}
              message={errorMessage(
                issues.error,
                "The newsletter could not be loaded.",
              )}
              onRetry={() => void issues.refetch()}
            />
          ) : (
            <EmptyOrOffline
              reachable={reachable}
              loading={false}
              empty={
                <View className="items-center rounded-card border border-border bg-white px-card py-9">
                  <View className="h-14 w-14 items-center justify-center rounded-pill bg-marigoldSoft">
                    <Ionicons
                      name="newspaper-outline"
                      size={26}
                      color={tokens.colors.marigold}
                    />
                  </View>
                  <Text className="mt-4 text-center font-display text-xl text-stone">
                    No issues yet
                  </Text>
                  <Text className="mt-2 max-w-80 text-center font-sans text-sm leading-6 text-stoneMuted">
                    Each month's newsletter will appear here to read and keep.
                    Anything you would like in it can be requested above.
                  </Text>
                </View>
              }
            />
          )
        }
      />

      <StoryRequestModal
        visible={requestOpen}
        onClose={() => setRequestOpen(false)}
      />
      {canManage ? (
        <PostNewsletterModal
          visible={composerOpen}
          onClose={() => setComposerOpen(false)}
        />
      ) : null}
    </>
  );
}
