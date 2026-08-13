/**
 * The pieces of furniture that put hours of seva on a screen: the range switch,
 * the figure it drives, the list of sevas by name underneath it — and the whole
 * "Your seva" card a devotee reads about themselves.
 *
 * Several screens show these — a devotee's seva and history, a devotee's
 * profile as a coordinator sees it, their full seva record, and the
 * congregation. They share these parts so "12 hours this month" cannot come to
 * mean several slightly different things depending on where it is read.
 */

import { Ionicons } from "@expo/vector-icons";
import { useState } from "react";
import { Pressable, Text, View } from "react-native";

import tokens from "../../../design-tokens.json";
import { SectionHeader, Skeleton } from "../../components/ui";
import { useMySevaBalance, useMySevaBreakdown } from "../sevayatra/hooks";
import { formatHours, sevaCountLabel } from "../sevayatra/types";
import {
  mySevaRanges,
  sevaRangeCaptions,
  sevaRangeLabels,
  sevaRanges,
  type SevaRange,
  type SevaRangeTotals,
} from "./sevaHours";

/**
 * Four ranges as one switch rather than four stacked blocks. A coordinator is
 * reading a devotee in seconds and asking one question at a time; four figures
 * side by side make them find the one they meant before they can read it.
 */
export function SevaRangeSwitch({
  value,
  onChange,
  options = sevaRanges,
  subject,
}: {
  value: SevaRange;
  onChange: (range: SevaRange) => void;
  options?: readonly SevaRange[];
  /** Whose hours, for the screen reader: "their seva", "your seva". */
  subject: string;
}) {
  return (
    <View className="flex-row rounded-pill border border-border bg-ivory p-1">
      {options.map((option) => {
        const selected = option === value;
        return (
          <Pressable
            key={option}
            className={`min-h-10 flex-1 items-center justify-center rounded-pill ${
              selected ? "bg-indigo" : ""
            }`}
            accessibilityRole="button"
            accessibilityState={{ selected }}
            accessibilityLabel={`${sevaRangeLabels[option]} of ${subject}`}
            onPress={() => onChange(option)}
          >
            <Text
              className={`font-sans-bold text-xs ${
                selected ? "text-white" : "text-stone"
              }`}
              numberOfLines={1}
            >
              {sevaRangeLabels[option]}
            </Text>
          </Pressable>
        );
      })}
    </View>
  );
}

/** The hours themselves, with the window they cover said underneath. */
export function SevaHoursFigure({
  hours,
  caption,
}: {
  hours: number;
  caption: string;
}) {
  return (
    <View>
      <Text className="font-display text-4xl leading-[46px] text-stone">
        {formatHours(hours)}
      </Text>
      <Text className="mt-0.5 font-sans text-sm leading-5 text-stoneMuted">
        {caption}
      </Text>
    </View>
  );
}

/**
 * Which sevas, by name, with the hours each. The temple asked for the names —
 * "eight hours" is a figure and "eight hours of pot washing" is a conversation.
 */
export function SevaNameHoursList({
  totals,
  limit,
  empty,
  withBars = false,
}: {
  totals: SevaRangeTotals;
  /** Beyond this, the rest are counted rather than listed. */
  limit?: number;
  empty: string;
  /** How much of the range each seva is, as a shape rather than a percentage. */
  withBars?: boolean;
}) {
  const shown = limit ? totals.sevas.slice(0, limit) : totals.sevas;
  const hidden = totals.sevas.length - shown.length;

  if (!shown.length) {
    return (
      <Text className="font-sans text-sm leading-5 text-stoneMuted">
        {empty}
      </Text>
    );
  }

  return (
    <View>
      {shown.map((seva, index) => (
        <View
          key={seva.key}
          className={index ? "mt-2.5" : ""}
          accessible
          accessibilityLabel={`${seva.name}, ${formatHours(seva.hours)}`}
        >
          <View className="flex-row items-baseline">
            <Text
              className="min-w-0 flex-1 pr-3 font-sans text-sm text-stone"
              numberOfLines={1}
            >
              {seva.name}
            </Text>
            <Text className="flex-shrink-0 font-sans-bold text-sm text-stone">
              {formatHours(seva.hours)}
            </Text>
          </View>
          {withBars && totals.hours > 0 ? (
            <View className="mt-1.5 h-1.5 overflow-hidden rounded-pill bg-sandalwood">
              <View
                className="h-full rounded-pill bg-peacock"
                style={{
                  // Below a couple of percent a truthful bar is invisible,
                  // which reads as "none" rather than "a little".
                  width: `${Math.max(
                    2,
                    Math.min(
                      100,
                      Math.round((seva.hours / totals.hours) * 100),
                    ),
                  )}%`,
                }}
              />
            </View>
          ) : null}
        </View>
      ))}
      {hidden > 0 ? (
        <Text className="mt-2.5 font-sans text-xs text-stoneMuted">
          and {hidden} more kind{hidden === 1 ? "" : "s"} of seva
        </Text>
      ) : null}
    </View>
  );
}

/**
 * Said to a devotee about their own seva, so it is never a shortfall. The
 * coordinator's wording — "no seva recorded" — is a finding about somebody
 * else; this is somebody reading their own page.
 */
const ownRangeEmpty: Record<SevaRange, string> = {
  week: "Nothing this week yet. There is always next week.",
  month: "Nothing yet this month.",
  year: "Nothing yet this year.",
  lifetime: "Your first seva will appear here.",
};

/**
 * "Your seva": one devotee's own hours, and what they offered them to.
 *
 * It lives here rather than inside a screen because the temple moved it — off
 * the Profile tab and onto "My seva and history", where a devotee goes to read
 * what they have served. One component so that wherever it is placed, it is the
 * same card saying the same figure; two copies would drift the moment one of
 * them gained a range or lost a caption.
 *
 * Read from the two functions that only ever answer about the caller, so this
 * card can be put on any screen and still show nobody else's anything.
 */
export function MySevaSummary({ userId }: { userId: string | null }) {
  const [range, setRange] = useState<SevaRange>("month");
  const breakdown = useMySevaBreakdown(userId);
  const balance = useMySevaBalance(userId);
  const ranges = mySevaRanges(breakdown.data ?? [], balance.data ?? []);
  const selected = ranges[range];
  const loading = breakdown.isLoading || balance.isLoading;
  const unread =
    (breakdown.isError && breakdown.data === undefined) ||
    (balance.isError && balance.data === undefined);
  /** Never served at all, which is a different thing from a quiet week. */
  const neverServed = !loading && !unread && ranges.lifetime.hours <= 0;

  return (
    <>
      {/* Their own hours, on their own page. No standing, no points, no
          comparison with anybody — the temple asked for the encouraging
          version here, and the coordinator's version lives elsewhere. */}
      <SectionHeader
        title="Your seva"
        subtitle="Hours you have offered, and what you offered them to."
      />
      <View className="mb-section rounded-card border border-border bg-white px-card py-4">
        {loading ? (
          <View className="gap-2">
            <Skeleton height={36} width="55%" />
            <Skeleton height={14} width="40%" />
          </View>
        ) : unread ? (
          // A read that failed is not a devotee who has served nothing.
          <Text className="font-sans text-sm leading-6 text-stoneMuted">
            Your hours could not be read just now. They are safe — try again in
            a moment.
          </Text>
        ) : neverServed ? (
          <View className="flex-row items-start">
            <View className="h-11 w-11 items-center justify-center rounded-pill bg-peacockSoft">
              <Ionicons
                name="leaf-outline"
                size={22}
                color={tokens.colors.peacock}
              />
            </View>
            <Text className="ml-4 min-w-0 flex-1 font-sans text-sm leading-6 text-stoneMuted">
              {ownRangeEmpty.lifetime} Every hour you offer is counted here,
              whatever it is and however small it feels.
            </Text>
          </View>
        ) : (
          <>
            <SevaRangeSwitch
              value={range}
              onChange={setRange}
              subject="your seva"
            />

            <View className="mt-4">
              <SevaHoursFigure
                hours={selected.hours}
                caption={
                  selected.acts > 0
                    ? `${sevaRangeCaptions[range]} · ${sevaCountLabel(selected.acts, "seva")}`
                    : sevaRangeCaptions[range]
                }
              />
            </View>

            <View className="mt-4 border-t border-border pt-3.5">
              <SevaNameHoursList
                totals={selected}
                limit={4}
                empty={ownRangeEmpty[range]}
                withBars
              />
            </View>

            <Text className="mt-3.5 border-t border-border pt-3 font-sans text-xs leading-4 text-stoneMuted">
              Your own hours, kept for you. Nothing here is measured against
              anybody else.
            </Text>
          </>
        )}
      </View>
    </>
  );
}
