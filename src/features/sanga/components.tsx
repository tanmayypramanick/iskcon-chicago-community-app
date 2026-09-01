import { Ionicons } from "@expo/vector-icons";
import { memo, useCallback } from "react";
import { Pressable, Text, View } from "react-native";

import tokens from "../../../design-tokens.json";
import { Skeleton, UnreadBadge, unreadLabel } from "../../components/ui";
import type { MySangaSummary, SangaSummary, SangaStatus } from "./types";

export function memberCountLabel(count: number) {
  return `${count} ${count === 1 ? "member" : "members"}`;
}

/**
 * What a devotee may do about a sanga they are looking at. Joining is a
 * request the sanga's admin answers, so there are three states and not two:
 * you are in it, you have asked, or you may ask.
 *
 * `mayEnterWithoutJoining` is the President or a Tech Admin: they open the
 * thread without being in the circle, so they are offered the door rather than
 * a request to knock at it.
 */
export type SangaAffordance = "open" | "requested" | "ask";

export function sangaAffordance(
  sanga: {
    is_member: boolean;
    request_status: SangaSummary["request_status"];
  },
  mayEnterWithoutJoining = false,
): SangaAffordance {
  if (sanga.is_member || mayEnterWithoutJoining) return "open";
  return sanga.request_status === "pending" ? "requested" : "ask";
}

const affordanceLabels: Record<SangaAffordance, string> = {
  open: "Open",
  requested: "Requested",
  ask: "Ask to join",
};

/**
 * The one control for all three states. "Requested" is drawn as a disabled
 * control rather than hidden: a devotee who has asked needs to see that the
 * ask landed, and needs to not be able to ask twice.
 */
export function SangaActionButton({
  name,
  affordance,
  busy,
  onPress,
}: {
  name: string;
  affordance: SangaAffordance;
  busy?: boolean;
  onPress: () => void;
}) {
  const disabled = affordance === "requested" || Boolean(busy);
  const tone =
    affordance === "ask"
      ? "bg-marigold"
      : affordance === "open"
        ? "border border-border bg-white"
        : "border border-border bg-sandalwood";

  return (
    <Pressable
      className={`min-h-10 shrink-0 flex-row items-center justify-center rounded-pill px-3.5 ${tone} ${
        busy ? "opacity-60" : ""
      }`}
      accessibilityRole="button"
      accessibilityState={{ disabled }}
      accessibilityLabel={
        affordance === "open"
          ? `Open ${name}`
          : affordance === "requested"
            ? `You have asked to join ${name}`
            : `Ask to join ${name}`
      }
      accessibilityHint={
        affordance === "requested"
          ? "The sanga’s admin has not answered yet."
          : undefined
      }
      disabled={disabled}
      onPress={onPress}
    >
      {affordance === "requested" ? (
        <Ionicons
          name="time-outline"
          size={15}
          color={tokens.colors.stoneMuted}
          style={{ marginRight: 4 }}
        />
      ) : null}
      <Text
        className={`font-sans-bold text-sm ${
          affordance === "requested"
            ? "text-stoneMuted"
            : affordance === "open"
              ? "text-indigo"
              : "text-stone"
        }`}
      >
        {affordanceLabels[affordance]}
      </Text>
    </Pressable>
  );
}

/**
 * One sanga in a stacked list, borrowing the devotee row's card grouping so a
 * run of them reads as a single card.
 *
 * The control sits on its own line under the description rather than beside
 * the name: "Ask to join" is a wide word beside a wide word, and on a 320dp
 * phone one of the two has to lose. The name is the one a devotee is reading.
 *
 * Memoised, and its two handlers take the sanga rather than closing over it,
 * so typing in the search box above redraws the rows that changed and not the
 * twenty that did not.
 */
export const SangaRow = memo(function SangaRow({
  sanga,
  isFirst,
  isLast,
  busy,
  mayEnterWithoutJoining,
  onPress,
  onAsk,
  onLongPress,
}: {
  sanga: SangaSummary;
  isFirst: boolean;
  isLast: boolean;
  busy?: boolean;
  mayEnterWithoutJoining?: boolean;
  onPress: (sanga: SangaSummary) => void;
  onAsk: (sanga: SangaSummary) => void;
  /**
   * A menu for a sanga the viewer is already in. Held rather than shown: what
   * is on it is destructive, and this is a list to browse.
   */
  onLongPress?: (sanga: SangaSummary) => void;
}) {
  const affordance = sangaAffordance(sanga, mayEnterWithoutJoining);
  const open = useCallback(() => onPress(sanga), [onPress, sanga]);
  const ask = useCallback(() => onAsk(sanga), [onAsk, sanga]);
  const hold = useCallback(() => onLongPress?.(sanga), [onLongPress, sanga]);
  const meta = [
    memberCountLabel(sanga.member_count),
    sanga.admin_name ? `run by ${sanga.admin_name}` : null,
  ]
    .filter(Boolean)
    .join(" · ");

  return (
    <Pressable
      className={`min-h-[76px] flex-row items-start border-x border-border bg-white px-card py-3.5 ${
        isFirst ? "rounded-t-card border-t" : ""
      } ${isLast ? "rounded-b-card border-b" : "border-b"}`}
      accessibilityRole="button"
      accessibilityLabel={`Open ${sanga.name}, ${memberCountLabel(
        sanga.member_count,
      )}${unreadLabel(sanga.unread_count)}`}
      accessibilityHint={onLongPress ? "Hold for more" : undefined}
      onPress={open}
      onLongPress={onLongPress ? hold : undefined}
      delayLongPress={350}
    >
      <View className="h-10 w-10 items-center justify-center rounded-pill border border-peacock/10 bg-peacockSoft">
        <Ionicons
          name="people-outline"
          size={20}
          color={tokens.colors.peacock}
        />
      </View>
      <View className="ml-3 min-w-0 flex-1">
        {/* The badge sits on the name's line rather than beside the control
            below it: it is about the sanga, not about what you may do with it,
            and a devotee scanning the list reads down the names. */}
        <View className="flex-row items-start">
          <Text
            className="min-w-0 flex-1 font-sans-bold text-lg text-stone"
            numberOfLines={2}
          >
            {sanga.name}
          </Text>
          {sanga.unread_count ? (
            <View className="ml-2 mt-1">
              <UnreadBadge count={sanga.unread_count} />
            </View>
          ) : null}
        </View>
        {sanga.description?.trim() ? (
          <Text
            className="mt-1 font-sans text-sm leading-5 text-stoneMuted"
            numberOfLines={2}
          >
            {sanga.description.trim()}
          </Text>
        ) : null}
        <View className="mt-2 flex-row items-center justify-between">
          <Text
            className="min-w-0 flex-1 pr-3 font-sans text-xs text-stoneMuted"
            numberOfLines={1}
          >
            {meta}
          </Text>
          <SangaActionButton
            name={sanga.name}
            affordance={affordance}
            busy={busy}
            onPress={affordance === "open" ? open : ask}
          />
        </View>
      </View>
    </Pressable>
  );
});

/** A retired sanga is approved and closed, which is neither of the other two. */
export type SangaDisplayStatus = SangaStatus | "retired";

export function sangaDisplayStatus(sanga: MySangaSummary): SangaDisplayStatus {
  return sanga.status === "approved" && !sanga.active
    ? "retired"
    : sanga.status;
}

const statusTone: Record<SangaDisplayStatus, { chip: string; text: string }> = {
  pending: { chip: "bg-marigoldSoft", text: "text-stone" },
  approved: { chip: "bg-peacockSoft", text: "text-peacock" },
  declined: { chip: "bg-vermilionSoft", text: "text-vermilion" },
  retired: { chip: "bg-sandalwood", text: "text-stoneMuted" },
};

const statusLabels: Record<SangaDisplayStatus, string> = {
  pending: "Waiting for approval",
  approved: "Running",
  declined: "Not approved",
  retired: "Closed",
};

export function SangaStatusPill({ status }: { status: SangaDisplayStatus }) {
  const tone = statusTone[status];
  return (
    <View className={`shrink-0 rounded-pill px-2.5 py-1 ${tone.chip}`}>
      <Text className={`font-sans-bold text-xs ${tone.text}`}>
        {statusLabels[status]}
      </Text>
    </View>
  );
}

/**
 * A row of the devotee's own sangas. Unlike the browse list this one carries
 * sangas that are not running yet, so the status is on the row: a sanga the
 * devotee proposed must not look identical to one they are already inside.
 */
export function MySangaRow({
  sanga,
  isFirst,
  isLast,
  onPress,
}: {
  sanga: MySangaSummary;
  isFirst: boolean;
  isLast: boolean;
  onPress: () => void;
}) {
  const status = sangaDisplayStatus(sanga);
  const meta = [
    status === "approved" ? memberCountLabel(sanga.member_count) : null,
    sanga.is_admin
      ? "you run it"
      : sanga.admin_name
        ? `run by ${sanga.admin_name}`
        : null,
  ]
    .filter(Boolean)
    .join(" · ");

  return (
    <Pressable
      className={`min-h-[76px] flex-row items-start border-x border-border bg-white px-card py-3.5 ${
        isFirst ? "rounded-t-card border-t" : ""
      } ${isLast ? "rounded-b-card border-b" : "border-b"}`}
      accessibilityRole="button"
      accessibilityLabel={`Open ${sanga.name}, ${
        statusLabels[status]
      }${unreadLabel(sanga.unread_count)}`}
      // A sanga still waiting on the President, or one already closed, has no
      // page to open.
      disabled={status !== "approved"}
      onPress={onPress}
    >
      <View className="h-10 w-10 items-center justify-center rounded-pill border border-peacock/10 bg-peacockSoft">
        <Ionicons
          name="people-outline"
          size={20}
          color={tokens.colors.peacock}
        />
      </View>
      <View className="ml-3 min-w-0 flex-1">
        <View className="flex-row items-start">
          <Text
            className="min-w-0 flex-1 font-sans-bold text-lg text-stone"
            numberOfLines={2}
          >
            {sanga.name}
          </Text>
          {sanga.unread_count ? (
            <View className="ml-2 mt-1">
              <UnreadBadge count={sanga.unread_count} />
            </View>
          ) : null}
        </View>
        {sanga.description?.trim() ? (
          <Text
            className="mt-1 font-sans text-sm leading-5 text-stoneMuted"
            numberOfLines={2}
          >
            {sanga.description.trim()}
          </Text>
        ) : null}
        {meta ? (
          <Text className="mt-1 font-sans text-xs text-stoneMuted">{meta}</Text>
        ) : null}
        {status !== "approved" ? (
          <View className="mt-2 flex-row">
            <SangaStatusPill status={status} />
          </View>
        ) : null}
        {status === "declined" && sanga.review_note?.trim() ? (
          <Text className="mt-1.5 font-sans text-xs leading-4 text-stoneMuted">
            {sanga.review_note.trim()}
          </Text>
        ) : null}
      </View>
    </Pressable>
  );
}

/** A quiet line under a group heading that has nothing beneath it yet. */
export function SangaNote({ text }: { text: string }) {
  return (
    <View className="rounded-card border border-border bg-white px-card py-5">
      <Text className="text-center font-sans text-sm leading-5 text-stoneMuted">
        {text}
      </Text>
    </View>
  );
}

export function SangaEmpty({ searching }: { searching: boolean }) {
  return (
    <View className="items-center rounded-card border border-border bg-white px-card py-8">
      <Ionicons
        name="people-circle-outline"
        size={30}
        color={tokens.colors.peacock}
      />
      <Text className="mt-3 text-center font-sans-bold text-base text-stone">
        {searching ? "No matching sanga" : "No sangas yet"}
      </Text>
      <Text className="mt-1 text-center font-sans text-sm leading-5 text-stoneMuted">
        {searching
          ? "Try a shorter word or a different spelling."
          : "Anyone can start one. Yours appears here once the temple has approved it."}
      </Text>
    </View>
  );
}

/** Rows in the shape of the real ones, so an unloaded list never reads as an
 * empty one. */
export function SangaRowsSkeleton() {
  return (
    <View className="overflow-hidden rounded-card border border-border bg-white">
      {[0, 1, 2, 3].map((slot) => (
        <View
          key={slot}
          className={`flex-row items-start px-card py-3.5 ${
            slot ? "border-t border-border" : ""
          }`}
        >
          <View className="h-10 w-10 overflow-hidden rounded-pill">
            <Skeleton height={40} width={40} />
          </View>
          <View className="ml-3 flex-1">
            <Skeleton height={18} width="52%" />
            <View className="mt-2">
              <Skeleton height={12} width="86%" />
            </View>
            <View className="mt-2">
              <Skeleton height={10} width="38%" />
            </View>
          </View>
        </View>
      ))}
    </View>
  );
}
