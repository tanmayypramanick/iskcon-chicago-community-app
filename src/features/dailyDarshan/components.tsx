import { Ionicons } from "@expo/vector-icons";
import { useState } from "react";
import { Image, Pressable, Text, TextInput, View } from "react-native";

import tokens from "../../../design-tokens.json";
import {
  addChicagoDays,
  chicagoWallClockToInstant,
  formatChicagoShortDate,
  getChicagoDateKey,
} from "../../lib/chicagoDate";
import { useNow } from "../../lib/useNow";
import type { DailyDarshan, DarshanImage } from "./types";

/**
 * What a screen reader is told about a photograph.
 *
 * A darshan picture with no label is simply invisible to a devotee using
 * VoiceOver, and "image" tells them nothing. The caption the temple wrote is
 * the label — the Deities' name and who dressed Them is exactly what a sighted
 * devotee gets from looking.
 */
export function darshanImageLabel(image: DarshanImage, dayLabel?: string) {
  const parts: string[] = [];
  if (image.deity) parts.push(image.deity);
  if (image.dressedBy) parts.push(`dressed by ${image.dressedBy}`);
  if (!parts.length) parts.push("Darshan photograph");
  if (dayLabel) parts.push(dayLabel);
  return parts.join(", ");
}

/**
 * The two calendar days "Today" and "Yesterday" mean right now at the temple.
 *
 * Held once per screen rather than once per day-card: a gallery of thirty days
 * would otherwise carry thirty clocks. They have to stop being true on their
 * own, because nothing in the data changes at midnight.
 */
export function useDarshanDayKeys() {
  const now = useNow(60_000);
  return {
    todayKey: getChicagoDateKey(now),
    // Not "24 hours ago": a DST day is 23 or 25 hours long, and subtracting a
    // fixed span lands on the wrong calendar day twice a year.
    yesterdayKey: addChicagoDays(-1, now),
  };
}

/**
 * `darshan_on` is a Chicago calendar day, not an instant, so it is read back at
 * midday Chicago time. Reading "2026-08-26" as a Date would make it UTC
 * midnight, which is the evening of the 25th at the temple — the darshan would
 * be labelled with the wrong day.
 */
export function formatDarshanDay(
  dateKey: string,
  todayKey: string,
  yesterdayKey: string,
) {
  if (dateKey === todayKey) return "Today";
  if (dateKey === yesterdayKey) return "Yesterday";
  const label = formatChicagoShortDate(
    chicagoWallClockToInstant(dateKey, "12:00"),
  );
  const year = dateKey.slice(0, 4);
  // A day from an earlier year needs its year, or "Sat, Jan 4" is a guess.
  return year === todayKey.slice(0, 4) ? label : `${label}, ${year}`;
}

/** The first line of a day, said in one phrase, for the Home card and for a
 * day's accessibility summary. */
export function darshanDeityLine(darshan: DailyDarshan) {
  const named = darshan.images
    .map((image) => image.deity)
    .filter((deity): deity is string => Boolean(deity));
  const unique = [...new Set(named)];
  if (!unique.length) return null;
  if (unique.length <= 2) return unique.join(" and ");
  return `${unique.slice(0, 2).join(", ")} and ${unique.length - 2} more`;
}

/**
 * One photograph, at the size the Deities deserve, with its caption beneath.
 *
 * A picture that will not load keeps its caption: the words are the part a
 * devotee can still read, and an empty grey frame with nothing under it says
 * only that the app is broken.
 */
export function DarshanPhoto({
  image,
  dayLabel,
  onOpen,
}: {
  image: DarshanImage;
  dayLabel?: string;
  onOpen?: (url: string) => void;
}) {
  const [failed, setFailed] = useState(false);
  const label = darshanImageLabel(image, dayLabel);

  const frame = failed ? (
    <View
      className="w-full items-center justify-center rounded-card border border-border bg-sandalwood"
      style={{ aspectRatio: 4 / 5 }}
    >
      <Ionicons
        name="image-outline"
        size={26}
        color={tokens.colors.stoneMuted}
      />
      <Text className="mt-2 px-6 text-center font-sans text-sm text-stoneMuted">
        This picture could not be loaded
      </Text>
    </View>
  ) : (
    <Image
      source={{ uri: image.imageUrl }}
      style={{ width: "100%", aspectRatio: 4 / 5, borderRadius: 20 }}
      resizeMode="cover"
      onError={() => setFailed(true)}
      accessibilityIgnoresInvertColors
    />
  );

  return (
    <View className="mt-3">
      {onOpen && !failed ? (
        <Pressable
          accessibilityRole="imagebutton"
          accessibilityLabel={label}
          accessibilityHint="Opens it full size, where it can be saved"
          onPress={() => onOpen(image.imageUrl)}
        >
          {frame}
        </Pressable>
      ) : (
        <View accessible accessibilityLabel={label}>
          {frame}
        </View>
      )}

      {image.deity || image.dressedBy ? (
        <View
          className="mt-2.5 px-0.5"
          accessibilityElementsHidden
          importantForAccessibility="no-hide-descendants"
        >
          {image.deity ? (
            <Text className="font-display text-lg leading-6 text-stone">
              {image.deity}
            </Text>
          ) : null}
          {image.dressedBy ? (
            <Text className="mt-0.5 font-sans text-sm leading-5 text-stoneMuted">
              Dressed by{" "}
              <Text className="font-sans-bold text-stone">
                {image.dressedBy}
              </Text>
            </Text>
          ) : null}
        </View>
      ) : null}
    </View>
  );
}

/**
 * How many pictures a day holds, said the way a person would.
 *
 * The count is the one thing a week tile can say that its cover photograph
 * cannot: the cover shows what the day looks like, the count says how much
 * more of it there is behind the tap.
 */
export function darshanPictureCount(darshan: DailyDarshan) {
  const count = darshan.images.length;
  return count === 1 ? "1 picture" : `${count} pictures`;
}

/**
 * What a screen reader is told about a whole day.
 *
 * The temple asked that a day be one entry rather than a run of pictures, and
 * this is that entry said out loud: which day, how much is in it, and Whom.
 */
export function darshanDayLabel(
  darshan: DailyDarshan,
  todayKey: string,
  yesterdayKey: string,
) {
  const dayLabel = formatDarshanDay(darshan.darshan_on, todayKey, yesterdayKey);
  const deities = darshanDeityLine(darshan);
  const parts = [dayLabel, darshanPictureCount(darshan)];
  if (deities) parts.push(deities);
  return parts.join(", ");
}

/**
 * The cover of a day: its first photograph.
 *
 * The first one is not an arbitrary choice — `position` is the order the temple
 * arranged when it posted, so picture one is the one they put first. A tile
 * that showed all five would be the very stack of pictures the week view exists
 * to replace.
 */
function DarshanCover({
  darshan,
  radius,
  aspectRatio,
}: {
  darshan: DailyDarshan;
  radius: number;
  aspectRatio: number;
}) {
  const [failed, setFailed] = useState(false);
  const cover = darshan.images[0];

  if (!cover || failed) {
    return (
      <View
        className="w-full items-center justify-center bg-sandalwood"
        style={{ aspectRatio, borderRadius: radius }}
      >
        <Ionicons
          name="flower-outline"
          size={22}
          color={tokens.colors.stoneMuted}
        />
      </View>
    );
  }

  return (
    <Image
      source={{ uri: cover.imageUrl }}
      style={{ width: "100%", aspectRatio, borderRadius: radius }}
      resizeMode="cover"
      onError={() => setFailed(true)}
      accessibilityIgnoresInvertColors
    />
  );
}

/**
 * The newest day, at the top of the week.
 *
 * It is drawn large because it is almost always today's darshan and is what
 * the devotee opened the screen for; the rest of the week is a list beneath it.
 * One tap target for the whole day — the temple's "for one day only one thing
 * inside, and they can check everything on that day".
 */
export function DarshanWeekLead({
  darshan,
  todayKey,
  yesterdayKey,
  onPress,
}: {
  darshan: DailyDarshan;
  todayKey: string;
  yesterdayKey: string;
  onPress: () => void;
}) {
  const dayLabel = formatDarshanDay(darshan.darshan_on, todayKey, yesterdayKey);
  const deities = darshanDeityLine(darshan);

  return (
    <Pressable
      className="mb-3 overflow-hidden rounded-card border border-border bg-stone"
      accessibilityRole="button"
      accessibilityLabel={darshanDayLabel(darshan, todayKey, yesterdayKey)}
      accessibilityHint="Opens everything posted on that day"
      onPress={onPress}
    >
      <DarshanCover darshan={darshan} radius={0} aspectRatio={4 / 3} />
      {/* A scrim behind the words only, so the photograph stays the
          photograph and the text stays readable over whatever is beneath. */}
      <View
        className="absolute bottom-0 left-0 right-0 bg-stone/65 px-card py-3"
        accessibilityElementsHidden
        importantForAccessibility="no-hide-descendants"
      >
        <Text className="font-sans-bold text-[11px] uppercase tracking-widest text-marigoldSoft">
          {dayLabel} · {darshanPictureCount(darshan)}
        </Text>
        <Text
          className="mt-0.5 font-display text-xl leading-7 text-white"
          numberOfLines={1}
        >
          {deities ?? "Darshan of the Deities"}
        </Text>
      </View>
    </Pressable>
  );
}

/**
 * One earlier day of the week, as a row.
 *
 * Rows rather than a second grid of photographs: six of them fit on one screen,
 * every one is the same height, and the week reads as a week. The thumbnail
 * says what the day looked like; the words say how much is inside it.
 */
export function DarshanWeekRow({
  darshan,
  todayKey,
  yesterdayKey,
  onPress,
}: {
  darshan: DailyDarshan;
  todayKey: string;
  yesterdayKey: string;
  onPress: () => void;
}) {
  const dayLabel = formatDarshanDay(darshan.darshan_on, todayKey, yesterdayKey);
  const deities = darshanDeityLine(darshan);

  return (
    <Pressable
      className="mb-3 flex-row items-center rounded-card border border-border bg-white p-2.5"
      accessibilityRole="button"
      accessibilityLabel={darshanDayLabel(darshan, todayKey, yesterdayKey)}
      accessibilityHint="Opens everything posted on that day"
      onPress={onPress}
    >
      <View className="h-[74px] w-[74px] overflow-hidden rounded-button">
        <DarshanCover darshan={darshan} radius={16} aspectRatio={1} />
      </View>
      <View
        className="ml-3 min-w-0 flex-1"
        accessibilityElementsHidden
        importantForAccessibility="no-hide-descendants"
      >
        <Text className="font-sans-bold text-base text-stone" numberOfLines={1}>
          {dayLabel}
        </Text>
        <Text
          className="mt-0.5 font-sans text-sm leading-5 text-stoneMuted"
          numberOfLines={1}
        >
          {deities ?? "Darshan of the Deities"}
        </Text>
        <Text className="mt-0.5 font-sans text-xs text-peacock">
          {darshanPictureCount(darshan)}
        </Text>
      </View>
      <Ionicons
        name="chevron-forward"
        size={18}
        color={tokens.colors.stoneMuted}
      />
    </Pressable>
  );
}

/**
 * The photograph above "Explore the community" on Home.
 *
 * The temple asked for the picture and the card to be two things: this is the
 * picture. It shows the current day's darshan and nothing else — no icon, no
 * tile, no borrowed grid geometry — and it draws nothing at all when there is
 * no photograph to show, because an empty frame on Home says only that
 * something is broken.
 */
export function DarshanHomeHero({
  darshan,
  todayKey,
  yesterdayKey,
  onPress,
}: {
  darshan: DailyDarshan | null | undefined;
  todayKey: string;
  yesterdayKey: string;
  onPress: () => void;
}) {
  const [failed, setFailed] = useState(false);
  const cover = darshan?.images[0];
  if (!darshan || !cover || failed) return null;

  const dayLabel = formatDarshanDay(darshan.darshan_on, todayKey, yesterdayKey);
  const deities = darshanDeityLine(darshan);
  const headline = deities ?? "Darshan of the Deities";

  return (
    <Pressable
      className="overflow-hidden rounded-card border border-border bg-stone"
      accessibilityRole="button"
      accessibilityLabel={`Daily Darshan, ${dayLabel}. ${headline}`}
      accessibilityHint="Opens the day's pictures"
      onPress={onPress}
    >
      <Image
        source={{ uri: cover.imageUrl }}
        style={{ width: "100%", aspectRatio: 16 / 10 }}
        resizeMode="cover"
        onError={() => setFailed(true)}
        accessibilityIgnoresInvertColors
      />
      <View
        className="absolute bottom-0 left-0 right-0 bg-stone/65 px-card py-3"
        accessibilityElementsHidden
        importantForAccessibility="no-hide-descendants"
      >
        <Text className="font-sans-bold text-[11px] uppercase tracking-widest text-marigoldSoft">
          Daily Darshan · {dayLabel}
        </Text>
        <Text
          className="mt-0.5 font-display text-lg leading-6 text-white"
          numberOfLines={1}
        >
          {headline}
        </Text>
      </View>
    </Pressable>
  );
}

/**
 * Choosing Whom a picture shows.
 *
 * The temple asked to choose from a list rather than type, so the list is the
 * control and typing is the exception behind it — a Deity the catalogue has not
 * heard of must never stop a day being posted. The chosen name and the dresser
 * beneath it are meant to be read as one sentence: Whom, then by whose hands.
 */
export function DeityPicker({
  options,
  value,
  onChange,
  custom,
  onCustom,
}: {
  options: readonly string[];
  value: string;
  onChange: (name: string) => void;
  /** Whether the "another Deity" field is open. */
  custom: boolean;
  onCustom: (open: boolean) => void;
}) {
  return (
    <View className="mt-4">
      <Text
        className="font-sans-bold text-xs uppercase tracking-wider text-stoneMuted"
        accessibilityRole="header"
      >
        Which Deities?
      </Text>

      <View className="mt-2.5 flex-row flex-wrap gap-2">
        {options.map((name) => {
          const selected = !custom && value === name;
          return (
            <Pressable
              key={name}
              className={`min-h-11 flex-row items-center justify-center rounded-pill border px-3.5 ${
                selected
                  ? "border-marigold bg-marigoldSoft"
                  : "border-border bg-white"
              }`}
              accessibilityRole="button"
              accessibilityState={{ selected }}
              accessibilityLabel={name}
              onPress={() => {
                onCustom(false);
                onChange(name);
              }}
            >
              {selected ? (
                <Ionicons
                  name="checkmark"
                  size={15}
                  color={tokens.colors.stone}
                />
              ) : null}
              <Text
                className={`${selected ? "ml-1 font-sans-bold text-stone" : "font-sans text-indigo"} text-sm`}
              >
                {name}
              </Text>
            </Pressable>
          );
        })}

        <Pressable
          className={`min-h-11 flex-row items-center justify-center rounded-pill border px-3.5 ${
            custom ? "border-marigold bg-marigoldSoft" : "border-border bg-white"
          }`}
          accessibilityRole="button"
          accessibilityState={{ selected: custom }}
          accessibilityLabel="Another Deity"
          onPress={() => {
            onCustom(true);
            // The typed name starts empty rather than carrying over the chip
            // that was selected: "Another" means another.
            if (!custom) onChange("");
          }}
        >
          <Ionicons name="add" size={15} color={tokens.colors.indigo} />
          <Text className="ml-1 font-sans text-sm text-indigo">Another</Text>
        </Pressable>
      </View>

      {custom ? (
        <View className="mt-3 border-b border-border pb-1">
          <TextInput
            className="min-h-11 font-display text-xl leading-7 text-stone"
            placeholder="Their name"
            placeholderTextColor={tokens.colors.stoneMuted}
            value={value}
            onChangeText={onChange}
            maxLength={120}
            autoCapitalize="words"
            accessibilityLabel="Which Deities are in this picture"
          />
        </View>
      ) : null}
    </View>
  );
}
