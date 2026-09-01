import { Ionicons } from "@expo/vector-icons";
import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import { useMemo, useState } from "react";
import {
  Alert,
  Image,
  Pressable,
  ScrollView,
  Text,
  TextInput,
  View,
} from "react-native";

import tokens from "../../design-tokens.json";
import { Button, Screen } from "../components/ui";
import { useCurrentAccessProfile } from "../features/access/hooks";
import { DeityPicker } from "../features/dailyDarshan/components";
import {
  canPostDailyDarshan,
  pickDarshanImages,
  useDailyDarshan,
  useDarshanDeities,
  usePublishDailyDarshan,
} from "../features/dailyDarshan/hooks";
import {
  MAX_DARSHAN_IMAGES,
  type DarshanDraftImage,
} from "../features/dailyDarshan/types";
import { DateField, FormError } from "../features/services/components";
import { dateToKey, errorMessage } from "../features/services/format";
import { formatChicagoDate, getChicagoDateKey } from "../lib/chicagoDate";
import type { HomeStackParamList } from "../navigation/types";
import { usePrototypeSession } from "../store/usePrototypeSession";

type Props = NativeStackScreenProps<HomeStackParamList, "PostDarshan">;

let draftCounter = 0;
function nextDraftId() {
  draftCounter += 1;
  return `draft-${Date.now()}-${draftCounter}`;
}

/**
 * One photograph in the strip along the top.
 *
 * The strip is what makes five pictures stop being five copies of a form: it is
 * the only place all five are visible at once, so it carries the whole state of
 * the post — which one is being captioned, which still need a name, and which
 * one failed to send.
 */
function StripThumb({
  draft,
  selected,
  captioned,
  onPress,
}: {
  draft: DarshanDraftImage;
  selected: boolean;
  captioned: boolean;
  onPress: () => void;
}) {
  const state =
    draft.status === "failed"
      ? { icon: "alert-circle" as const, color: tokens.colors.vermilion }
      : draft.status === "uploading"
        ? { icon: "arrow-up-circle" as const, color: tokens.colors.indigo }
        : draft.status === "uploaded"
          ? { icon: "checkmark-circle" as const, color: tokens.colors.peacock }
          : captioned
            ? null
            : { icon: "ellipse-outline" as const, color: tokens.colors.marigold };

  return (
    <Pressable
      className="mr-2"
      accessibilityRole="button"
      accessibilityState={{ selected }}
      accessibilityLabel={
        draft.status === "failed"
          ? `${draft.deity || "This picture"} — could not be sent. Open it`
          : captioned
            ? `Open ${draft.deity}`
            : "Open a picture that still needs a name"
      }
      onPress={onPress}
    >
      <View
        className={`overflow-hidden rounded-button border-2 ${
          selected ? "border-indigo" : "border-transparent"
        }`}
      >
        <Image
          source={{ uri: draft.uri }}
          style={{ width: 62, height: 78 }}
          resizeMode="cover"
          accessibilityIgnoresInvertColors
        />
      </View>
      {state ? (
        <View className="absolute bottom-1 right-1 rounded-pill bg-white">
          <Ionicons name={state.icon} size={15} color={state.color} />
        </View>
      ) : null}
    </Pressable>
  );
}

/**
 * Posting a day of darshan.
 *
 * A screen rather than a modal: it holds up to five photographs, each with two
 * captions and its own upload, and a devotee who leaves the app halfway through
 * should come back to it standing where they left it.
 *
 * The captions are deliberately not a list of five field pairs. One photograph
 * is shown large at a time and named underneath the way a caption is written
 * under a picture, with the strip above saying where you are in the five. The
 * temple's words were "who dressed which deity", so the pairing lives with the
 * picture it belongs to and never gets separated from it.
 */
export function PostDarshanScreen({ navigation }: Props) {
  const activeUserId = usePrototypeSession((state) => state.activeUserId);
  const previewRole = usePrototypeSession((state) => state.previewRole);
  const profile = useCurrentAccessProfile(activeUserId);
  const role =
    __DEV__ && previewRole ? previewRole : (profile.data?.role ?? "devotee");
  const canPost = canPostDailyDarshan(role);

  const publish = usePublishDailyDarshan(activeUserId);
  const recent = useDailyDarshan(canPost);
  const deities = useDarshanDeities(canPost);

  const [drafts, setDrafts] = useState<DarshanDraftImage[]>([]);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  /** The one picture, if any, whose Deities are being typed rather than chosen. */
  const [typingDeityFor, setTypingDeityFor] = useState<string | null>(null);
  const [note, setNote] = useState("");
  const [day, setDay] = useState<Date | null>(null);
  const [formError, setFormError] = useState<string | null>(null);

  const selected =
    drafts.find((draft) => draft.id === selectedId) ?? drafts[0] ?? null;
  const remaining = MAX_DARSHAN_IMAGES - drafts.length;
  const dayKey = day ? dateToKey(day) : getChicagoDateKey();

  /**
   * The server keeps one darshan per day and replaces the pictures of a day
   * posted twice. That is the right behaviour — a Head correcting a name should
   * not create a second Tuesday — but it has to be said out loud, or the second
   * post silently removes the first one's pictures.
   */
  const replacing = (recent.data ?? []).some(
    (darshan) => darshan.darshan_on === dayKey,
  );

  /**
   * What the picker offers.
   *
   * The temple's catalogue first, in the altar order the server gave it, then
   * any Deity this week's darshan named that the catalogue has not heard of —
   * a visiting or festival Deity someone typed yesterday should be a tap today
   * rather than being typed again. Both are names, because that is what a
   * picture stores; the catalogue is a list to choose from, not a foreign key.
   */
  const deityOptions = useMemo(() => {
    const catalogue = (deities.data ?? []).map((deity) => deity.name);
    const recentlyNamed = (recent.data ?? [])
      .flatMap((darshan) => darshan.images.map((image) => image.deity))
      .filter((name): name is string => Boolean(name));
    return [...new Set([...catalogue, ...recentlyNamed])].slice(0, 8);
  }, [deities.data, recent.data]);

  /**
   * Whether this picture's Deities are being typed rather than chosen. Either
   * the devotee asked for "Another", or the name already on it is not one the
   * picker offers — a day being corrected after the catalogue changed must show
   * the name it actually carries, not silently drop it.
   */
  const typingDeity =
    selected !== null &&
    (typingDeityFor === selected.id ||
      (Boolean(selected.deity) && !deityOptions.includes(selected.deity)));

  const patch = (id: string, change: Partial<DarshanDraftImage>) =>
    setDrafts((existing) =>
      existing.map((draft) =>
        draft.id === id ? { ...draft, ...change } : draft,
      ),
    );

  const addPictures = (source: "library" | "camera") => {
    void (async () => {
      try {
        const picked = await pickDarshanImages(source, remaining);
        if (!picked.length) return;
        const added = picked.map((image) => ({
          id: nextDraftId(),
          uri: image.uri,
          mimeType: image.mimeType,
          fileName: image.fileName,
          deity: "",
          dressedBy: "",
          uploadedUrl: null,
          status: "waiting" as const,
          error: null,
        }));
        setDrafts((existing) => [...existing, ...added]);
        // The newest picture becomes the one being captioned, because that is
        // what the devotee just chose and is still looking at.
        setSelectedId(added[0].id);
        setFormError(null);
      } catch (caught) {
        Alert.alert(
          "No pictures added",
          errorMessage(caught, "Those pictures could not be used.") ?? "",
        );
      }
    })();
  };

  const choosePictures = () => {
    if (remaining < 1) {
      setFormError(
        `Up to ${MAX_DARSHAN_IMAGES} pictures can go in one day's darshan.`,
      );
      return;
    }
    Alert.alert("Add pictures", undefined, [
      { text: "Take a photo", onPress: () => addPictures("camera") },
      { text: "Choose from library", onPress: () => addPictures("library") },
      { text: "Cancel", style: "cancel" },
    ]);
  };

  const removeSelected = () => {
    if (!selected) return;
    setDrafts((existing) => existing.filter((d) => d.id !== selected.id));
    setSelectedId(null);
    setFormError(null);
  };

  const submit = () => {
    setFormError(null);
    if (!drafts.length) {
      setFormError("Add at least one picture of the Deities.");
      return;
    }
    // The temple asked for "who dressed which deity", so a picture with nobody
    // named is a picture nobody can read. The dresser may genuinely be unknown;
    // the Deities never are.
    const unnamed = drafts.find((draft) => !draft.deity.trim());
    if (unnamed) {
      setSelectedId(unnamed.id);
      setFormError("Name the Deities in each picture before posting.");
      return;
    }

    publish.mutate(
      {
        darshanOn: dayKey,
        note: note.trim() || null,
        images: drafts,
        onImageState: patch,
      },
      { onSuccess: () => navigation.goBack() },
    );
  };

  if (!canPost) {
    return (
      <Screen>
        <View className="mt-section items-center rounded-card border border-border bg-white px-card py-9">
          <View className="h-14 w-14 items-center justify-center rounded-pill bg-sandalwood">
            <Ionicons
              name="lock-closed-outline"
              size={26}
              color={tokens.colors.stoneMuted}
            />
          </View>
          <Text className="mt-4 text-center font-display text-xl text-stone">
            Posting darshan is for temple leaders
          </Text>
          <Text className="mt-2 max-w-80 text-center font-sans text-sm leading-6 text-stoneMuted">
            The President, Tech Admin and Community Heads post the day's
            pictures. You can see every one of them in Daily Darshan.
          </Text>
        </View>
      </Screen>
    );
  }

  const sent = drafts.filter((draft) => draft.uploadedUrl).length;
  const error =
    formError ?? errorMessage(publish.error, "The darshan could not be posted.");

  return (
    <Screen>
      <Text className="mt-1 font-sans text-base leading-6 text-stoneMuted">
        Up to {MAX_DARSHAN_IMAGES} pictures of the Deities, each named with who
        dressed Them.
      </Text>

      {/* The strip: every picture at once, and the state of every upload. */}
      <View className="mt-section flex-row items-center">
        <ScrollView
          horizontal
          showsHorizontalScrollIndicator={false}
          className="flex-1"
        >
          {drafts.map((draft) => (
            <StripThumb
              key={draft.id}
              draft={draft}
              selected={draft.id === selected?.id}
              captioned={Boolean(draft.deity.trim())}
              onPress={() => setSelectedId(draft.id)}
            />
          ))}
        </ScrollView>
        {remaining > 0 ? (
          <Pressable
            className="ml-1 h-[78px] w-[62px] items-center justify-center rounded-button border border-dashed border-border bg-white"
            accessibilityRole="button"
            accessibilityLabel={`Add pictures, ${remaining} of ${MAX_DARSHAN_IMAGES} still free`}
            onPress={choosePictures}
          >
            <Ionicons name="add" size={22} color={tokens.colors.indigo} />
            <Text className="mt-0.5 font-sans text-[11px] text-stoneMuted">
              {drafts.length}/{MAX_DARSHAN_IMAGES}
            </Text>
          </Pressable>
        ) : null}
      </View>

      {selected ? (
        <View className="mt-4">
          <Image
            source={{ uri: selected.uri }}
            style={{ width: "100%", aspectRatio: 4 / 5, borderRadius: 20 }}
            resizeMode="cover"
            accessibilityIgnoresInvertColors
            accessibilityLabel="The picture being named"
          />

          {selected.status === "failed" && selected.error ? (
            <View className="mt-3 flex-row items-center rounded-button border border-vermilion bg-white px-3 py-2.5">
              <Ionicons
                name="alert-circle-outline"
                size={18}
                color={tokens.colors.vermilion}
              />
              <Text className="ml-2 min-w-0 flex-1 font-sans text-sm leading-5 text-vermilion">
                {selected.error}
              </Text>
            </View>
          ) : null}

          {/* Whom, then by whose hands: the two are meant to be read as one
              sentence about this photograph, so they sit together under it and
              never get separated from the picture they belong to. */}
          <DeityPicker
            options={deityOptions}
            value={selected.deity}
            onChange={(name) => patch(selected.id, { deity: name })}
            custom={typingDeity}
            onCustom={(open) =>
              setTypingDeityFor(open ? selected.id : null)
            }
          />

          <View className="mt-3 flex-row items-center border-b border-border pb-1">
            <Text className="font-sans text-base text-stoneMuted">
              Dressed by
            </Text>
            <TextInput
              className="ml-2 min-h-11 flex-1 font-sans-bold text-base text-stone"
              placeholder="a devotee’s name"
              placeholderTextColor={tokens.colors.stoneMuted}
              value={selected.dressedBy}
              onChangeText={(text) => patch(selected.id, { dressedBy: text })}
              maxLength={120}
              autoCapitalize="words"
              accessibilityLabel="Who dressed the Deities in this picture"
            />
          </View>

          <Pressable
            className="mt-3 min-h-11 flex-row items-center"
            accessibilityRole="button"
            accessibilityLabel="Remove this picture from the darshan"
            onPress={removeSelected}
          >
            <Ionicons
              name="close-circle-outline"
              size={17}
              color={tokens.colors.stoneMuted}
            />
            <Text className="ml-1.5 font-sans text-sm text-stoneMuted">
              Remove this picture
            </Text>
          </Pressable>
        </View>
      ) : (
        <Pressable
          className="mt-4 items-center rounded-card border border-dashed border-border bg-white px-card py-12"
          accessibilityRole="button"
          accessibilityLabel="Choose the day’s pictures"
          onPress={choosePictures}
        >
          <View className="h-14 w-14 items-center justify-center rounded-pill bg-marigoldSoft">
            <Ionicons
              name="images-outline"
              size={26}
              color={tokens.colors.stone}
            />
          </View>
          <Text className="mt-4 text-center font-display text-xl text-stone">
            Choose the day's pictures
          </Text>
          <Text className="mt-2 max-w-80 text-center font-sans text-sm leading-6 text-stoneMuted">
            Pick up to {MAX_DARSHAN_IMAGES} at once, then name the Deities in
            each one.
          </Text>
        </Pressable>
      )}

      <View className="mt-section">
        <TextInput
          className="min-h-11 rounded-button border border-border bg-white px-4 py-3 font-sans text-base leading-6 text-stone"
          placeholder="A word about today’s darshan (optional)"
          placeholderTextColor={tokens.colors.stoneMuted}
          value={note}
          onChangeText={setNote}
          multiline
          textAlignVertical="top"
          maxLength={600}
          autoCapitalize="sentences"
          accessibilityLabel="A word about today’s darshan, optional"
        />
      </View>

      {/* Almost every darshan is posted the day it was taken, so the day is a
          line of text until somebody actually needs to change it. */}
      <View className="mt-4">
        {day ? (
          <DateField
            label="Darshan day"
            value={day}
            onChange={setDay}
            maximumDate={new Date()}
          />
        ) : (
          <Pressable
            className="min-h-11 flex-row items-center"
            accessibilityRole="button"
            accessibilityLabel={`Posting for today, ${formatChicagoDate()}. Change the day`}
            onPress={() => setDay(new Date())}
          >
            <Ionicons
              name="calendar-outline"
              size={16}
              color={tokens.colors.stoneMuted}
            />
            <Text className="ml-2 font-sans text-sm text-stoneMuted">
              For today, {formatChicagoDate()} ·{" "}
              <Text className="font-sans-bold text-indigo">Change</Text>
            </Text>
          </Pressable>
        )}
      </View>

      {replacing ? (
        <View className="mt-3 flex-row rounded-button border border-border bg-white px-3 py-2.5">
          <Ionicons
            name="information-circle-outline"
            size={18}
            color={tokens.colors.peacock}
          />
          <Text className="ml-2 min-w-0 flex-1 font-sans text-sm leading-5 text-stoneMuted">
            A darshan is already posted for this day. Posting replaces its
            pictures.
          </Text>
        </View>
      ) : null}

      {error ? <FormError message={error} /> : null}

      <View className="mt-section">
        <Button
          icon="flower-outline"
          disabled={publish.isPending}
          onPress={submit}
        >
          {publish.isPending
            ? `Sending ${Math.min(sent + 1, drafts.length)} of ${drafts.length}…`
            : replacing
              ? "Replace this day’s darshan"
              : "Post darshan"}
        </Button>
        {publish.isPending ? (
          <Text
            className="mt-2 text-center font-sans text-xs text-stoneMuted"
            accessibilityLiveRegion="polite"
          >
            Pictures are sent one at a time, so a slow connection only has to
            carry one of them at once.
          </Text>
        ) : null}
      </View>
    </Screen>
  );
}
