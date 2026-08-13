import { Ionicons } from "@expo/vector-icons";
import { useState, type ReactNode } from "react";
import { Pressable, Text, View } from "react-native";

import tokens from "../../../design-tokens.json";
import {
  sevaGiftLegend,
  sevaLegendBadges,
  sevaTierIcons,
  type SevaAwardTier,
  type SevaBadgeLegendEntry,
} from "./types";

/**
 * The small controls and the two legends the Seva Yatra screens share.
 *
 * They live here rather than in each screen because the temple has said three
 * times that Seva Yatra is too busy, and the only way to add to it without
 * adding weight is for every screen to reach for the same four shapes: a
 * segmented bar, a quiet pill, a disclosure, and a "See all".
 */

/**
 * A row of equal cells, one of which is on.
 *
 * Equal cells rather than pills that size to their labels, because that is the
 * Android bug this replaced: three pills of natural width overflow a 320dp
 * screen, and "Seva only" lost its second word off the right edge. Here every
 * cell is a third of whatever there is, the label never wraps, and it shrinks
 * to fit rather than being cut — so the narrowest phone the temple owns shows
 * all three labels whole.
 */
export function SevaSegmented<Key extends string>({
  value,
  options,
  onChange,
  accessibilityRole = "tab",
}: {
  value: Key;
  options: readonly { key: Key; label: string }[];
  onChange: (key: Key) => void;
  accessibilityRole?: "tab" | "radio";
}) {
  return (
    <View className="flex-row rounded-pill border border-border bg-sandalwood p-1">
      {options.map((option) => {
        const selected = value === option.key;
        return (
          <Pressable
            key={option.key}
            className={`min-h-10 min-w-0 flex-1 items-center justify-center rounded-pill px-1 ${
              selected ? "bg-white" : ""
            }`}
            accessibilityRole={accessibilityRole}
            accessibilityState={{ selected }}
            accessibilityLabel={option.label}
            onPress={() => onChange(option.key)}
          >
            <Text
              className={`font-sans-bold text-sm ${
                selected ? "text-stone" : "text-stoneMuted"
              }`}
              numberOfLines={1}
              adjustsFontSizeToFit
              minimumFontScale={0.75}
            >
              {option.label}
            </Text>
          </Pressable>
        );
      })}
    </View>
  );
}

/** One quiet pill. Never shrinks, never wraps its label, so nothing is cut. */
export function SevaChip({
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
      className={`min-h-9 flex-shrink-0 items-center justify-center rounded-pill border px-3 ${
        selected ? "border-indigo bg-indigo" : "border-border bg-white"
      }`}
      accessibilityRole="button"
      accessibilityState={{ selected }}
      accessibilityLabel={label}
      onPress={onPress}
    >
      <Text
        className={`font-sans-bold text-xs ${
          selected ? "text-white" : "text-stone"
        }`}
        numberOfLines={1}
      >
        {label}
      </Text>
    </Pressable>
  );
}

export function SevaChipRow<Key extends string>({
  value,
  options,
  onChange,
}: {
  value: Key;
  options: readonly { key: Key; label: string }[];
  onChange: (key: Key) => void;
}) {
  return (
    <View className="flex-row flex-wrap gap-2">
      {options.map((option) => (
        <SevaChip
          key={option.key}
          label={option.label}
          selected={value === option.key}
          onPress={() => onChange(option.key)}
        />
      ))}
    </View>
  );
}

/**
 * A section that is one line until it is asked for.
 *
 * Everything the temple added to this screen arrived through one of these. A
 * closed disclosure costs a single row of text, which is how a legend of ten
 * badges and a legend of nine gifts can both be on a screen that reads as
 * shorter than the one before it.
 */
export function Disclosure({
  label,
  children,
}: {
  label: string;
  children: ReactNode;
}) {
  const [open, setOpen] = useState(false);

  return (
    <View>
      <Pressable
        className="min-h-touch flex-row items-center justify-center"
        accessibilityRole="button"
        accessibilityState={{ expanded: open }}
        accessibilityLabel={label}
        onPress={() => setOpen((value) => !value)}
      >
        <Text className="font-sans-bold text-sm text-indigo">{label}</Text>
        <Ionicons
          name={open ? "chevron-up" : "chevron-down"}
          size={16}
          color={tokens.colors.indigo}
        />
      </Pressable>
      {open ? children : null}
    </View>
  );
}

/** The one way any of these screens opens a list up. */
export function SeeAll({
  total,
  label,
  onPress,
}: {
  total: number;
  label: string;
  onPress: () => void;
}) {
  return (
    <Pressable
      className="min-h-touch items-center justify-center rounded-button border border-border bg-white"
      accessibilityRole="button"
      accessibilityLabel={`See all ${total} ${label}`}
      onPress={onPress}
    >
      <Text className="font-sans-bold text-sm text-indigo">
        See all {total}
      </Text>
    </Pressable>
  );
}

/**
 * A badge, drawn whole. Nothing on these screens ever dims one: the shelf is
 * append-only and an earned badge that looks faded reads as one that was taken
 * back.
 */
export function BadgeMedallion({
  tier,
  title,
  caption,
}: {
  tier: SevaAwardTier | null;
  title: string;
  caption: string | null;
}) {
  const icon = tier ? sevaTierIcons[tier] : "leaf";
  const highlight = tier === "garland" || tier === "maha_prasad";

  return (
    <View className="w-24 items-center">
      <View
        className={`h-16 w-16 items-center justify-center rounded-pill border-2 ${
          highlight
            ? "border-marigold bg-marigoldSoft"
            : "border-peacock bg-peacockSoft"
        }`}
      >
        <Ionicons
          name={icon}
          size={28}
          color={highlight ? tokens.colors.stone : tokens.colors.peacock}
        />
      </View>
      <Text
        className="mt-2 text-center font-sans-bold text-xs leading-4 text-stone"
        numberOfLines={2}
      >
        {title}
      </Text>
      {caption ? (
        <Text
          className="mt-0.5 text-center font-sans text-[10px] leading-3 text-stoneMuted"
          numberOfLines={1}
        >
          {caption}
        </Text>
      ) : null}
    </View>
  );
}

/** A small medallion, at list size rather than at shelf size. */
function LegendMark({ tier }: { tier: SevaAwardTier }) {
  const highlight = tier === "garland" || tier === "maha_prasad";
  return (
    <View
      className={`h-9 w-9 flex-shrink-0 items-center justify-center rounded-pill border ${
        highlight
          ? "border-marigold bg-marigoldSoft"
          : "border-peacock bg-peacockSoft"
      }`}
    >
      <Ionicons
        name={sevaTierIcons[tier]}
        size={16}
        color={highlight ? tokens.colors.stone : tokens.colors.peacock}
      />
    </View>
  );
}

/**
 * The two legends, behind one disclosure.
 *
 * Every badge is listed whether or not the devotee holds it: the question the
 * legend answers is "what is there", and a legend of only your own badges
 * answers it wrong. What earns a badge is said for the same reason.
 *
 * The gifts are the opposite case and the difference is deliberate. The temple
 * asked for what the gifts ARE and asked, in as many words, that the app not
 * say who receives one or when. So there is no rule beside a gift, no tier, no
 * count and no period — a gift is something the temple gives according to your
 * seva, and everything past that is the temple's to say in person.
 *
 * `badges` is the whole of what `list_seva_badge_legend()` answered, gifts
 * included, because one function answers for both. Splitting it here rather
 * than at the call site means no screen can forget to.
 */
export function SevaAwardLegend({
  badges,
}: {
  badges: readonly SevaBadgeLegendEntry[];
}) {
  const badgeEntries = sevaLegendBadges(badges);

  return (
    <View className="mt-1 rounded-card border border-border bg-white px-card py-4">
      <Text className="font-sans-bold text-[11px] uppercase tracking-widest text-peacock">
        Badges
      </Text>
      <Text className="mt-1 font-sans text-xs leading-5 text-stoneMuted">
        Every badge the temple gives, and what earns it.
      </Text>

      {badgeEntries.map((badge, index) => (
        <View
          key={badge.code}
          className={`flex-row items-start pt-3 ${
            index ? "mt-3 border-t border-border" : ""
          }`}
        >
          <LegendMark tier={badge.tier} />
          <View className="ml-3 min-w-0 flex-1">
            <Text className="font-sans-bold text-sm leading-5 text-stone">
              {badge.title}
            </Text>
            <Text className="mt-0.5 font-sans text-xs leading-5 text-stone">
              {badge.description}
            </Text>
            <Text className="mt-0.5 font-sans text-xs leading-5 text-stoneMuted">
              {badge.earned_by}
            </Text>
          </View>
        </View>
      ))}

      <View className="mt-4 border-t border-border pt-4">
        <Text className="font-sans-bold text-[11px] uppercase tracking-widest text-marigold">
          Gifts
        </Text>
        <Text className="mt-1 font-sans text-xs leading-5 text-stoneMuted">
          What the temple gives, according to your seva.
        </Text>

        {sevaGiftLegend.map((gift) => (
          <View key={gift.title} className="mt-3">
            <Text className="font-sans-bold text-sm leading-5 text-stone">
              {gift.title}
            </Text>
            <Text className="mt-0.5 font-sans text-xs leading-5 text-stone">
              {gift.description}
            </Text>
            {gift.items ? (
              <View className="mt-1.5 flex-row flex-wrap gap-1.5">
                {gift.items.map((item) => (
                  <View
                    key={item}
                    className="rounded-pill bg-marigoldSoft px-2.5 py-1"
                  >
                    <Text className="font-sans text-xs text-stone">{item}</Text>
                  </View>
                ))}
              </View>
            ) : null}
          </View>
        ))}
      </View>
    </View>
  );
}
