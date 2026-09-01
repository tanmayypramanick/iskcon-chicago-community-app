import { Ionicons } from "@expo/vector-icons";
import { Image, Pressable, Text, View } from "react-native";

import tokens from "../../../design-tokens.json";
import {
  Avatar,
  RemoteImage,
} from "../../components/ui";
import {
  addChicagoDays,
  chicagoWallClockToInstant,
  formatChicagoShortDate,
  formatChicagoTime,
  getChicagoDateKey,
  getChicagoZoneAbbreviation,
} from "../../lib/chicagoDate";
import { useNow } from "../../lib/useNow";
import type { Announcement } from "./types";

/**
 * The schedule fields are Chicago wall-clock values, not instants, so every
 * one of them is turned into the instant it names at the temple before it is
 * formatted. Reading them on the device's calendar would move a notice by a
 * day for a devotee travelling.
 *
 * Midday, because only the date is shown and no DST change has ever happened
 * at noon.
 */
function chicagoDateLabel(dateKey: string) {
  return formatChicagoShortDate(chicagoWallClockToInstant(dateKey, "12:00"));
}

function chicagoTimeLabel(time: string, dateKey: string | null) {
  return formatChicagoTime(
    chicagoWallClockToInstant(dateKey ?? getChicagoDateKey(), time),
  );
}

/** "Sat, Aug 15, 6:30 PM" — as much of one end as the notice actually gave. */
function boundLabel(dateKey: string | null, time: string | null) {
  const pieces: string[] = [];
  if (dateKey) pieces.push(chicagoDateLabel(dateKey));
  if (time) pieces.push(chicagoTimeLabel(time, dateKey));
  return pieces.length ? pieces.join(", ") : null;
}

/**
 * When the notice applies, in the fewest words that stay unambiguous. Null
 * when it has no schedule at all, which is most of them.
 */
export function formatAnnouncementWindow(
  announcement: Announcement,
): string | null {
  const { starts_on, ends_on, starts_at, ends_at } = announcement;
  const oneDay = starts_on !== null && starts_on === ends_on;

  const start = boundLabel(starts_on, starts_at);
  // A notice that begins and ends on the same day names that day once.
  const end = boundLabel(oneDay ? null : ends_on, ends_at);

  const zone =
    starts_at || ends_at
      ? ` ${getChicagoZoneAbbreviation(
          chicagoWallClockToInstant(
            starts_on ?? ends_on ?? getChicagoDateKey(),
            "12:00",
          ),
        )}`
      : "";

  if (start && end) return `${start} – ${end}${zone}`;
  if (start) return oneDay ? `${start}${zone}` : `From ${start}${zone}`;
  if (end) return `Until ${end}${zone}`;
  return null;
}

/**
 * The two calendar days "Today" and "Yesterday" mean right now at the temple.
 *
 * Held once per screen rather than once per card: a board of twenty notices
 * would otherwise carry twenty clocks. They have to stop being true on their
 * own, because nothing in the data changes at midnight.
 */
export function useAnnouncementDayKeys() {
  const now = useNow(60_000);

  return {
    todayKey: getChicagoDateKey(now),
    // Not "24 hours ago": a DST day is 23 or 25 hours long, and subtracting a
    // fixed span lands on the wrong calendar day twice a year.
    yesterdayKey: addChicagoDays(-1, now),
  };
}

function postedLabel(
  createdAt: string,
  todayKey: string,
  yesterdayKey: string,
) {
  const posted = new Date(createdAt);
  const key = getChicagoDateKey(posted);
  if (key === todayKey) return `Today at ${formatChicagoTime(posted)}`;
  if (key === yesterdayKey) return `Yesterday at ${formatChicagoTime(posted)}`;
  return formatChicagoShortDate(posted);
}

/**
 * The heart and the thread, under every notice.
 *
 * The heart is the toggle and the count beside it is the door to the names:
 * two targets that read as one control, which is the arrangement every thumb in
 * the congregation already knows. Nothing is shown for likes nobody has left —
 * there is no list to open.
 */
export function ReactionBar({
  announcement,
  onToggleLike,
  onOpenLikes,
  onOpenComments,
}: {
  announcement: Announcement;
  onToggleLike: () => void;
  onOpenLikes: () => void;
  /** Absent on the thread itself, where there is nowhere left to go. */
  onOpenComments?: () => void;
}) {
  const { like_count: likes, comment_count: comments } = announcement;
  const liked = announcement.liked_by_me;
  const commentLabel =
    comments === 0
      ? "Comment"
      : `${comments} ${comments === 1 ? "comment" : "comments"}`;
  const likeText = `${likes} ${likes === 1 ? "like" : "likes"}`;

  return (
    <View className="mt-2 flex-row items-center border-t border-border pt-1">
      <Pressable
        className="-ml-1 h-11 flex-row items-center rounded-pill px-2"
        accessibilityRole="button"
        accessibilityState={{ selected: liked }}
        accessibilityLabel={
          liked ? `Unlike ${announcement.title}` : `Like ${announcement.title}`
        }
        hitSlop={4}
        onPress={onToggleLike}
      >
        <Ionicons
          name={liked ? "heart" : "heart-outline"}
          size={22}
          color={liked ? tokens.colors.vermilion : tokens.colors.stoneMuted}
        />
        {likes === 0 ? (
          <Text className="ml-1.5 font-sans-bold text-sm text-stoneMuted">
            Like
          </Text>
        ) : null}
      </Pressable>

      {likes > 0 ? (
        <Pressable
          className="h-11 justify-center rounded-pill px-1"
          accessibilityRole="button"
          accessibilityLabel={`See the ${likes} ${
            likes === 1 ? "devotee who liked" : "devotees who liked"
          } ${announcement.title}`}
          hitSlop={4}
          onPress={onOpenLikes}
        >
          <Text
            className={`font-sans-bold text-sm ${
              liked ? "text-vermilion" : "text-stoneMuted"
            }`}
            numberOfLines={1}
          >
            {likeText}
          </Text>
        </Pressable>
      ) : null}

      <View className="flex-1" />

      {onOpenComments ? (
        <Pressable
          className="-mr-1 h-11 flex-row items-center rounded-pill px-2"
          accessibilityRole="button"
          accessibilityLabel={
            comments === 0
              ? `Comment on ${announcement.title}`
              : `Read the ${comments} ${
                  comments === 1 ? "comment" : "comments"
                } on ${announcement.title}`
          }
          hitSlop={4}
          onPress={onOpenComments}
        >
          <Ionicons
            name="chatbubble-outline"
            size={19}
            color={tokens.colors.indigo}
          />
          <Text
            className="ml-1.5 font-sans-bold text-sm text-indigo"
            numberOfLines={1}
          >
            {commentLabel}
          </Text>
        </Pressable>
      ) : (
        <View className="-mr-1 h-11 flex-row items-center px-2">
          <Ionicons
            name="chatbubble-outline"
            size={19}
            color={tokens.colors.stoneMuted}
          />
          <Text
            className="ml-1.5 font-sans-bold text-sm text-stoneMuted"
            numberOfLines={1}
          >
            {commentLabel}
          </Text>
        </View>
      )}
    </View>
  );
}

/**
 * One notice, as it appears wherever a devotee reads it: on the board, and
 * again at the head of its own comment thread so the words being answered stay
 * in front of the reader.
 *
 * Taking it down and opening its photo full size belong to the board, which
 * owns the confirmation and the picture viewer; where those are not passed the
 * card simply does not offer them, rather than offering a button that leads
 * nowhere.
 */
export function AnnouncementCard({
  announcement,
  todayKey,
  yesterdayKey,
  onDelete,
  onOpenImage,
  onToggleLike,
  onOpenLikes,
  onOpenComments,
}: {
  announcement: Announcement;
  todayKey: string;
  yesterdayKey: string;
  onDelete?: () => void;
  onOpenImage?: (url: string) => void;
  onToggleLike: () => void;
  onOpenLikes: () => void;
  onOpenComments?: () => void;
}) {
  const schedule = formatAnnouncementWindow(announcement);
  const poster = announcement.posted_by_name?.trim() || "The temple";
  const image = announcement.image_url;
  const isBirthday = announcement.kind === "birthday";

  return (
    <View className="mb-3 rounded-card border border-border bg-white p-card">
      <View className="flex-row items-start">
        <Text className="min-w-0 flex-1 font-display text-xl leading-7 text-stone">
          {announcement.title}
        </Text>
        {onDelete && announcement.can_delete ? (
          <Pressable
            className="-mr-1 ml-2 h-11 w-11 items-center justify-center rounded-pill"
            accessibilityRole="button"
            accessibilityLabel={`Take down ${announcement.title}`}
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

      {/* Full width rather than hugging its text: a long window wraps on a
          small phone instead of running off the card. */}
      {schedule ? (
        <View className="mt-2 flex-row items-center rounded-button bg-peacockSoft px-3 py-2">
          <Ionicons
            name="calendar-outline"
            size={15}
            color={tokens.colors.peacock}
          />
          <Text className="ml-1.5 min-w-0 flex-1 font-sans-bold text-sm leading-5 text-peacock">
            {schedule}
          </Text>
        </View>
      ) : null}

      <Text className="mt-3 font-sans text-base leading-6 text-stone">
        {announcement.body}
      </Text>

      {image ? (
        onOpenImage ? (
          <Pressable
            accessibilityRole="button"
            accessibilityLabel="Open this picture"
            accessibilityHint="Opens it full size, where it can be saved"
            onPress={() => onOpenImage(image)}
          >
            {isBirthday ? (
              <BirthdayFrame url={image} />
            ) : (
              <AnnouncementImage url={image} />
            )}
          </Pressable>
        ) : isBirthday ? (
          <BirthdayFrame url={image} />
        ) : (
          <AnnouncementImage url={image} />
        )
      ) : null}

      <View className="mt-3 flex-row items-center">
        <Avatar
          name={poster}
          photoUrl={announcement.posted_by_photo_url}
          size="tiny"
          tone="peacock"
        />
        <Text className="ml-2 min-w-0 flex-1 font-sans text-sm text-stoneMuted">
          {poster} ·{" "}
          {postedLabel(announcement.created_at, todayKey, yesterdayKey)}
        </Text>
      </View>

      <ReactionBar
        announcement={announcement}
        onToggleLike={onToggleLike}
        onOpenLikes={onOpenLikes}
        onOpenComments={onOpenComments}
      />
    </View>
  );
}

/** Sized by ratio, not by pixels, so it fits a small Android phone and a large
 * iPhone alike. */
function AnnouncementImage({ url }: { url: string }) {
  return (
    <RemoteImage
      uri={url}
      style={{
        width: "100%",
        aspectRatio: 4 / 3,
        borderRadius: 16,
        marginTop: 12,
      }}
      resizeMode="cover"
      accessibilityIgnoresInvertColors
    />
  );
}

/**
 * The birthday frame.
 *
 * A greeting to the whole congregation should not look like a notice about the
 * boiler, and the devotee it is about should be able to see at a glance that
 * the temple made something for them.
 *
 * Drawn rather than baked into the file, deliberately. The picture is the
 * devotee's own profile photograph, shared with every other place it appears;
 * compositing a frame into the bytes would mean a second copy in storage for
 * every birthday, and a frame the temple could never restyle without
 * reprocessing every image it had ever made.
 *
 * The garland band sits over the foot of the picture rather than beside it, so
 * the frame reads as one object at any width.
 */
function BirthdayFrame({ url }: { url: string }) {
  return (
    <View
      className="mt-3 rounded-card border-2 border-marigold bg-marigoldSoft p-1.5"
      accessible
      accessibilityRole="image"
      accessibilityLabel="A birthday greeting from the temple"
    >
      <View className="overflow-hidden rounded-[14px]">
        <RemoteImage
          uri={url}
          style={{ width: "100%", aspectRatio: 4 / 3 }}
          resizeMode="cover"
          accessibilityIgnoresInvertColors
        />

        <View className="absolute inset-x-0 bottom-0 flex-row items-center justify-center bg-marigold/95 px-3 py-2">
          <Ionicons name="flower" size={16} color={tokens.colors.stone} />
          <Text className="mx-2 font-display text-lg leading-6 text-stone">
            Happy Birthday
          </Text>
          <Ionicons name="flower" size={16} color={tokens.colors.stone} />
        </View>
      </View>
    </View>
  );
}
