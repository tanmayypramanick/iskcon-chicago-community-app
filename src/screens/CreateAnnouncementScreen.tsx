import { Ionicons } from "@expo/vector-icons";
import { useEffect, useRef, useState } from "react";
import { Alert, Image, Pressable, Text, TextInput, View } from "react-native";

import tokens from "../../design-tokens.json";
import { ModalScreen } from "../components/ModalScreen";
import { Button, SectionHeader } from "../components/ui";
import {
  pickMessageImage,
  useCreateAnnouncement,
} from "../features/announcements/hooks";
import type { PickedMessageImage } from "../features/announcements/types";
import {
  DateField,
  FormError,
  TimeField,
} from "../features/services/components";
import {
  dateToKey,
  errorMessage,
  getDefaultServiceTime,
  timeToDatabaseValue,
} from "../features/services/format";
import { usePrototypeSession } from "../store/usePrototypeSession";

/**
 * A schedule field that is off until it is asked for.
 *
 * Null is "the notice does not have one", which is the common case: most
 * notices are a sentence and nothing else, and a form that opens with four
 * pickers already filled in makes a devotee posting "Ekadashi tomorrow" argue
 * their way back out of a calendar.
 */
function OptionalToggle({
  label,
  on,
  onPress,
}: {
  label: string;
  on: boolean;
  onPress: () => void;
}) {
  return (
    <Pressable
      className={`min-h-11 flex-row items-center rounded-pill border px-3.5 ${
        on ? "border-indigo bg-indigo" : "border-border bg-white"
      }`}
      accessibilityRole="switch"
      accessibilityState={{ checked: on }}
      accessibilityLabel={
        on ? `Remove ${label.toLowerCase()}` : `Add ${label.toLowerCase()}`
      }
      onPress={onPress}
    >
      <Ionicons
        name={on ? "checkmark" : "add"}
        size={16}
        color={on ? tokens.colors.white : tokens.colors.indigo}
      />
      <Text
        className={`ml-1.5 font-sans-bold text-sm ${on ? "text-white" : "text-stone"}`}
      >
        {label}
      </Text>
    </Pressable>
  );
}

/**
 * Words the composer opens with, from wherever the devotee came in. Only ever
 * a starting point: both fields are ordinary editable text once it is open,
 * and nothing is posted until somebody presses Post.
 */
export type AnnouncementPrefill = {
  title: string;
  body: string;
};

/**
 * Posting a notice. A modal over the noticeboard rather than a route of its
 * own: it is one short form, and a devotee who opens it by mistake should be
 * one dismissal away from the list they were reading.
 */
export function CreateAnnouncementModal({
  visible,
  onClose,
  prefill = null,
}: {
  visible: boolean;
  onClose: () => void;
  prefill?: AnnouncementPrefill | null;
}) {
  const activeUserId = usePrototypeSession((state) => state.activeUserId);
  const create = useCreateAnnouncement(activeUserId);

  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");
  const [image, setImage] = useState<PickedMessageImage | null>(null);
  const [startDate, setStartDate] = useState<Date | null>(null);
  const [endDate, setEndDate] = useState<Date | null>(null);
  const [startTime, setStartTime] = useState<Date | null>(null);
  const [endTime, setEndTime] = useState<Date | null>(null);
  const [formError, setFormError] = useState<string | null>(null);

  /**
   * The prefill is applied on the edge where the modal opens, not while it is
   * open: this component stays mounted across openings, so state cannot simply
   * be initialised from the prop, and re-applying on every render would undo
   * whatever the devotee had just typed over it.
   */
  const wasVisible = useRef(false);
  useEffect(() => {
    const opening = visible && !wasVisible.current;
    wasVisible.current = visible;
    if (!opening || !prefill) return;
    setTitle(prefill.title);
    setBody(prefill.body);
  }, [prefill, visible]);

  const dismiss = () => {
    setTitle("");
    setBody("");
    setImage(null);
    setStartDate(null);
    setEndDate(null);
    setStartTime(null);
    setEndTime(null);
    setFormError(null);
    create.reset();
    onClose();
  };

  const choosePhoto = (source: "library" | "camera") => {
    void (async () => {
      try {
        const picked = await pickMessageImage(source);
        if (picked) setImage(picked);
      } catch (caught) {
        Alert.alert(
          "No photo added",
          errorMessage(caught, "That photo could not be used.") ?? "",
        );
      }
    })();
  };

  const attachPhoto = () => {
    Alert.alert("Add a photo", undefined, [
      { text: "Take a photo", onPress: () => choosePhoto("camera") },
      { text: "Choose from library", onPress: () => choosePhoto("library") },
      { text: "Cancel", style: "cancel" },
    ]);
  };

  const submit = () => {
    setFormError(null);
    const cleanTitle = title.trim();
    const cleanBody = body.trim();
    if (!cleanTitle) {
      setFormError("Please give the announcement a title.");
      return;
    }
    if (!cleanBody) {
      setFormError("Please write the announcement.");
      return;
    }

    const startsOn = startDate ? dateToKey(startDate) : null;
    const endsOn = endDate ? dateToKey(endDate) : null;
    const startsAt = startTime ? timeToDatabaseValue(startTime) : null;
    const endsAt = endTime ? timeToDatabaseValue(endTime) : null;

    if (startsOn && endsOn && endsOn < startsOn) {
      setFormError("The announcement ends before it starts. Check the dates.");
      return;
    }
    // Two times only mean "before" and "after" when they fall on the same day,
    // which is either one named date or no dates at all. The server draws the
    // line in exactly this place.
    if (startsAt && endsAt && startsOn === endsOn && endsAt < startsAt) {
      setFormError("The announcement ends before it starts. Check the times.");
      return;
    }

    create.mutate(
      {
        title: cleanTitle,
        body: cleanBody,
        image,
        startsOn,
        endsOn,
        startsAt,
        endsAt,
      },
      { onSuccess: dismiss },
    );
  };

  const error =
    formError ??
    errorMessage(create.error, "The announcement could not be posted.");

  return (
    <ModalScreen
      visible={visible}
      onClose={dismiss}
      eyebrow="Noticeboard"
      title="Post an announcement"
      backLabel="Close without posting"
    >
      <SectionHeader title="Title" />
      <TextInput
        className="min-h-touch rounded-button border border-border bg-white px-4 font-sans text-base text-stone"
        placeholder="Ekadashi tomorrow"
        placeholderTextColor={tokens.colors.stoneMuted}
        value={title}
        onChangeText={setTitle}
        maxLength={120}
        autoCapitalize="sentences"
      />

      <View className="mt-section">
        <SectionHeader title="Announcement" />
        <TextInput
          className="min-h-[120px] rounded-button border border-border bg-white px-4 py-3 font-sans text-base leading-6 text-stone"
          placeholder="What do devotees need to know?"
          placeholderTextColor={tokens.colors.stoneMuted}
          value={body}
          onChangeText={setBody}
          multiline
          textAlignVertical="top"
          maxLength={2000}
          autoCapitalize="sentences"
        />
      </View>

      <View className="mt-section">
        <SectionHeader title="Photo" subtitle="Optional" />
        {image ? (
          <View>
            <Image
              source={{ uri: image.uri }}
              style={{ width: "100%", aspectRatio: 4 / 3, borderRadius: 16 }}
              resizeMode="cover"
              accessibilityIgnoresInvertColors
            />
            <View className="mt-3 flex-row gap-3">
              <View className="flex-1">
                <Button
                  variant="secondary"
                  icon="swap-horizontal-outline"
                  onPress={attachPhoto}
                >
                  Replace
                </Button>
              </View>
              <View className="flex-1">
                <Button
                  variant="secondary"
                  icon="trash-outline"
                  onPress={() => setImage(null)}
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
            onPress={attachPhoto}
          >
            Add a photo
          </Button>
        )}
      </View>

      <View className="mt-section">
        <SectionHeader
          title="Dates and times"
          subtitle="All optional. Add only what the notice needs — with an end date it takes itself down once that has passed."
        />
        <View className="flex-row flex-wrap gap-2">
          <OptionalToggle
            label="Start date"
            on={startDate !== null}
            onPress={() =>
              setStartDate((current) => (current ? null : new Date()))
            }
          />
          <OptionalToggle
            label="End date"
            on={endDate !== null}
            onPress={() =>
              setEndDate((current) =>
                current ? null : (startDate ?? new Date()),
              )
            }
          />
          <OptionalToggle
            label="Start time"
            on={startTime !== null}
            onPress={() =>
              setStartTime((current) =>
                current ? null : getDefaultServiceTime(),
              )
            }
          />
          <OptionalToggle
            label="End time"
            on={endTime !== null}
            onPress={() =>
              setEndTime((current) =>
                current ? null : (startTime ?? getDefaultServiceTime()),
              )
            }
          />
        </View>

        {startDate ? (
          <View className="mt-3">
            <DateField
              label="Start date"
              value={startDate}
              onChange={setStartDate}
            />
          </View>
        ) : null}
        {endDate ? (
          <View className="mt-3">
            <DateField
              label="End date"
              value={endDate}
              onChange={setEndDate}
              minimumDate={startDate ?? undefined}
            />
          </View>
        ) : null}
        {startTime || endTime ? (
          <View className="mt-3 flex-row gap-3">
            {startTime ? (
              <TimeField
                label="Start time"
                value={startTime}
                onChange={setStartTime}
              />
            ) : null}
            {endTime ? (
              <TimeField
                label="End time"
                value={endTime}
                onChange={setEndTime}
              />
            ) : null}
          </View>
        ) : null}
      </View>

      {error ? <FormError message={error} /> : null}

      <View className="mt-section">
        <Button
          icon="megaphone-outline"
          disabled={create.isPending}
          onPress={submit}
        >
          {create.isPending ? "Posting…" : "Post announcement"}
        </Button>
      </View>
    </ModalScreen>
  );
}
