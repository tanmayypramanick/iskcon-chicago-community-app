import { Ionicons } from "@expo/vector-icons";
import { useNavigation, type NavigationProp } from "@react-navigation/native";
import { useMemo, useState, type ReactNode } from "react";
import { Pressable, ScrollView, Text, View } from "react-native";

import tokens from "../../design-tokens.json";
import {
  Avatar,
  Button,
  EmptyOrOffline,
  LoadFailure,
  Screen,
  ScreenTitle,
  SectionHeader,
  Skeleton,
  SkeletonCard,
} from "../components/ui";
import { useCurrentAccessProfile } from "../features/access/hooks";
import { hasAccessPermission } from "../features/access/model";
import { FormError } from "../features/services/components";
import { errorMessage } from "../features/services/format";
import {
  BadgeMedallion,
  Disclosure,
  SeeAll,
  SevaAwardLegend,
  SevaChipRow,
  SevaSegmented,
} from "../features/sevayatra/components";
import {
  useDevoteeAwardShelf,
  useDevoteeBadges,
  useMySevaMala,
  useMySevaProfile,
  useSetLeaderboardVisibility,
  useSevaActPoints,
  useSevaBadgeLegend,
  useSevaGarland,
  useSevaGivingPoints,
  useSevaSupporters,
} from "../features/sevayatra/hooks";
import {
  donationKindLabel,
  formatCents,
  formatHours,
  formatSevaDate,
  formatSevaRange,
  garlandRankForMode,
  pendingSevaPhrase,
  scoredPeriodForRange,
  sevaBoardModes,
  sevaCountLabel,
  sevaPoints,
  sevaRangeChips,
  sevaRangeLabels,
  sevaRanges,
  sevaTierIcons,
  sevaTierLabel,
  type DevoteeShelfAward,
  type SevaActPointsRow,
  type SevaAwardTier,
  type SevaBoardMode,
  type SevaGiftPointsRow,
  type SevaRangeKind,
  type SevaSupporter,
} from "../features/sevayatra/types";
import { useServerReachable } from "../lib/connectivity";
import type { HomeStackParamList, MainTabParamList } from "../navigation/types";
import { usePrototypeSession } from "../store/usePrototypeSession";
import { SevaCarePanel } from "./SevaCareScreen";

type Tab = "profile" | "board" | "care";

/**
 * How many places the board shows, and the `p_limit` the server is asked for.
 * It matters twice: the server appends the caller below the band when they fall
 * outside it, so that row has to be recognised and drawn separately.
 */
const BOARD_BAND = 20;

/**
 * The places a podium draws, and the most columns it can hold them in.
 *
 * Two numbers rather than one because 0067 made them different questions: the
 * podium is the top three PLACES, and a shared place can put more than three
 * devotees on it.
 */
const PODIUM_PLACES = 3;
const PODIUM_COLUMNS = 4;

/** How much of a list is shown before it asks to be opened. */
const DETAIL_ROWS = 4;
const SHELF_ROWS = 3;

const rangeOptions = sevaRanges.map((key) => ({
  key,
  label: sevaRangeChips[key],
}));

/**
 * Gold, silver and bronze drawn from the temple's own palette rather than from
 * metal: marigold, pewter and vermilion sit apart at a glance and belong to the
 * rest of the app, which three literal metallics would not.
 */
const medals: Record<number, { chip: string; label: string; ring: string }> = {
  1: { chip: "bg-marigold", label: "text-stone", ring: "border-marigold" },
  2: { chip: "bg-stoneMuted", label: "text-white", ring: "border-stoneMuted" },
  3: { chip: "bg-vermilion", label: "text-white", ring: "border-vermilion" },
};

/** One row of a board, whichever RPC it came from. */
type BoardEntry = {
  key: string;
  /** Null only for a place the server would not put a name to. */
  devoteeId: string | null;
  standing: number;
  name: string;
  photoUrl: string | null;
  tier: SevaAwardTier | null;
  isYou: boolean;
  /** Null where the server will not tell this caller somebody else's score. */
  points: number | null;
};

/**
 * What the hero and the two figures under it are made of, whichever read
 * answered.
 *
 * `served` and `counted` are kept apart all the way down because the temple
 * flagged the one place they were conflated: a devotee whose acts are all
 * waiting had really served four hours and the screen said "0 hours", because
 * it was showing the credited figure under an uncredited label.
 */
type Standing = {
  /** Null for the calendar year, which the scoring reads but never ranks. */
  points: number | null;
  /** `board_standing` — where they appear publicly. Null when off the board. */
  rank: number | null;
  /**
   * `standing` — where they actually are, which `my_seva_mala` answers only
   * about its own caller. The server sends the two apart precisely so that a
   * devotee who is off the board can still be told their own place.
   *
   * Shown on its own, never as "of N". 0067 section 5 narrowed the population
   * this is taken over to the devotees the caller may see plus themselves,
   * while `cohort_size` stayed the period's whole participant count — so the
   * two belong to different populations and pairing them read as a fraction
   * that was never computed. The rank is also dense, so the largest one on a
   * board is smaller than the number of devotees on it either way.
   */
  yourRank: number | null;
  gathering: boolean;
  servedHours: number;
  countedHours: number;
  givingCents: number;
  pendingActs: number;
  from: string | null;
  to: string | null;
};

/**
 * The hero: what this range came to, and where it puts them.
 *
 * The rank is the server's, and which of its two the screen shows is the whole
 * of the difference between being on the board and being off it. Opting out is
 * a promise about other devotees — the switch below says so in as many words —
 * so `standing` is still theirs to read while `board_standing` is null, and the
 * chip says which of the two it is rather than the screen falling silent. Both
 * are null while the congregation is gathering, and that is the server's answer
 * rather than a rule reimplemented here.
 *
 * A bare 0 was the temple's other complaint. Where nothing has been credited
 * yet the reason is said above the number, so the number is read as a state of
 * the paperwork rather than as a verdict on the devotee.
 */
function PointsHero({
  standing,
  range,
  pendingPhrase,
}: {
  standing: Standing;
  range: SevaRangeKind;
  /** What the waiting acts are waiting for — see `pendingSevaPhrase`. */
  pendingPhrase: string;
}) {
  const medal = standing.rank ? medals[standing.rank] : undefined;
  const ranked = standing.points !== null;
  const nothingCounted =
    ranked && standing.countedHours <= 0 && standing.pendingActs > 0;
  // Shown only where the public one is not, so a devotee never reads two ranks.
  const privateRank = standing.rank ? null : standing.yourRank;
  /**
   * On an unranked range the hero IS the hours served, so how much of that has
   * been counted is said here — on the line the figure already has — rather
   * than in a cell below that would print the same hours over again.
   */
  const measure =
    standing.servedHours <= 0
      ? "of seva"
      : standing.countedHours >= standing.servedHours
        ? "of seva · all of it counted"
        : `of seva · ${formatHours(standing.countedHours)} counted so far`;

  return (
    <View className="items-center rounded-card border border-border bg-white px-card py-8">
      <Text className="font-sans-bold text-xs uppercase tracking-widest text-peacock">
        {sevaRangeLabels[range]}
      </Text>

      {nothingCounted ? (
        <View className="mt-3 flex-row items-center rounded-pill bg-marigoldSoft px-3 py-1.5">
          <Ionicons
            name="hourglass-outline"
            size={13}
            color={tokens.colors.stone}
          />
          <Text className="ml-1.5 font-sans-bold text-xs text-stone">
            {sevaCountLabel(standing.pendingActs, "act")} still to be{" "}
            {pendingPhrase}
          </Text>
        </View>
      ) : null}

      <Text
        className="mt-2 font-display text-[56px] leading-[64px] text-stone"
        numberOfLines={1}
        adjustsFontSizeToFit
      >
        {/* Already through `sevaPoints`, so it is only given a separator here:
            rounding a rounded figure a second time is how a hero and the list
            under it come to disagree by ten. */}
        {ranked
          ? standing.points!.toLocaleString("en-US")
          : formatHours(standing.servedHours)}
      </Text>
      <Text className="font-sans text-sm text-stoneMuted">
        {ranked ? "seva points" : measure}
      </Text>

      {nothingCounted ? (
        <Text className="mt-3 max-w-72 text-center font-sans text-xs leading-5 text-stoneMuted">
          Your points arrive as each act is {pendingPhrase}. Nothing is lost
          while it waits, and the hours below are the ones you actually served.
        </Text>
      ) : standing.rank ? (
        <View
          className={`mt-4 flex-row items-center rounded-pill px-3.5 py-1.5 ${
            medal ? medal.chip : "bg-indigoSoft"
          }`}
        >
          <Ionicons
            name="trophy"
            size={14}
            color={
              medal?.label === "text-white"
                ? tokens.colors.white
                : medal
                  ? tokens.colors.stone
                  : tokens.colors.indigo
            }
          />
          <Text
            className={`ml-1.5 font-sans-bold text-sm ${
              medal ? medal.label : "text-indigo"
            }`}
          >
            Rank {standing.rank}
          </Text>
        </View>
      ) : privateRank ? (
        // Off the board, and told their place anyway. The switch at the foot of
        // this screen promises that being off it "only decides whether other
        // devotees see your name"; dropping the rank they earned would have
        // been the screen quietly breaking that promise.
        <View className="mt-4 flex-row items-center rounded-pill bg-indigoSoft px-3.5 py-1.5">
          <Ionicons
            name="eye-off-outline"
            size={14}
            color={tokens.colors.indigo}
          />
          <Text className="ml-1.5 font-sans-bold text-sm text-indigo">
            Rank {privateRank}, seen only by you
          </Text>
        </View>
      ) : !ranked ? (
        <Text className="mt-4 max-w-72 text-center font-sans text-xs leading-5 text-stoneMuted">
          Points are given by the week, by the month and for all time. A year is
          a read rather than a race.
        </Text>
      ) : standing.gathering ? (
        <Text className="mt-4 max-w-72 text-center font-sans text-xs leading-4 text-stoneMuted">
          Too few devotees have served this period for ranks to be published
          yet. Your seva is counted all the same.
        </Text>
      ) : null}
    </View>
  );
}

/**
 * Whatever the hero did not say, and nothing it did.
 *
 * A ranked range leads with points, so hours served — what a devotee actually
 * stood there and did, signed off or not — is said here, with the counted
 * figure beneath it so the two can never be mistaken for one another. An
 * unranked range leads with those same hours, and this card drops the cell
 * altogether rather than printing them a second time one element down.
 */
function StandingFigures({ standing }: { standing: Standing }) {
  const ranked = standing.points !== null;
  const detail =
    standing.servedHours <= 0
      ? "Nothing yet"
      : standing.countedHours >= standing.servedHours
        ? "All of it counted"
        : `${formatHours(standing.countedHours)} counted so far`;

  return (
    <View className="mt-4 flex-row rounded-card border border-border bg-white px-card py-3.5">
      {ranked ? (
        <View className="min-w-0 flex-1 pr-3">
          <Text className="font-sans text-xs text-stoneMuted">
            Hours served
          </Text>
          <Text className="mt-1 font-sans-bold text-lg text-stone">
            {formatHours(standing.servedHours)}
          </Text>
          <Text className="mt-0.5 font-sans text-xs leading-4 text-stoneMuted">
            {detail}
          </Text>
        </View>
      ) : null}
      <View
        className={`min-w-0 flex-1 ${
          ranked ? "border-l border-border pl-3" : ""
        }`}
      >
        <Text className="font-sans text-xs text-stoneMuted">Given</Text>
        <Text className="mt-1 font-sans-bold text-lg text-stone">
          {formatCents(standing.givingCents)}
        </Text>
      </View>
    </View>
  );
}

/**
 * One list of contributions, with the server's own sentence about what the
 * figures are.
 *
 * `attribution` is written by 0062 for exactly this card and is rendered as it
 * arrives. A per-act figure beside an act reads as what that act was worth on
 * its own, and it is not — it is a share of a total that a logarithm and the
 * congregation's own spread have already bent — so the sentence travels in the
 * rows precisely so that no screen has to invent it, or forget it.
 */
function ContributionCard({
  title,
  measure,
  points,
  note,
  shown,
  total,
  onShowAll,
  children,
}: {
  title: string;
  measure: string;
  points: number;
  note: string;
  shown: number;
  total: number;
  onShowAll: () => void;
  children: ReactNode;
}) {
  return (
    <View className="mb-3 rounded-card border border-border bg-white px-card py-4">
      <View className="flex-row items-baseline justify-between">
        <View className="min-w-0 flex-1 pr-3">
          <Text className="font-sans-bold text-base text-stone">{title}</Text>
          <Text className="mt-0.5 font-sans text-xs text-stoneMuted">
            {measure}
          </Text>
        </View>
        <Text className="flex-shrink-0 font-display text-2xl text-stone">
          {points.toLocaleString("en-US")}
        </Text>
      </View>

      <View className="mt-3">{children}</View>

      {total > shown ? (
        <Pressable
          className="mt-1 min-h-touch items-center justify-center"
          accessibilityRole="button"
          accessibilityLabel={`See all ${total}`}
          onPress={onShowAll}
        >
          <Text className="font-sans-bold text-sm text-indigo">
            See all {total}
          </Text>
        </Pressable>
      ) : null}

      <Text className="mt-3 border-t border-border pt-3 font-sans text-xs leading-5 text-stoneMuted">
        {note}
      </Text>
    </View>
  );
}

/**
 * One line of a contribution list. The points sit last and quietly: the hero is
 * the number a devotee is meant to read, and these are its parts.
 *
 * A row that contributed nothing shows a dash rather than a zero, and carries
 * the server's reason underneath — "why didn't Tuesday count" is the question
 * this list exists to answer, and hiding the row answers it worst.
 */
function ContributionRow({
  title,
  detail,
  points,
  note,
}: {
  title: string;
  detail: string;
  points: number;
  note?: string | null;
}) {
  return (
    <View className="mb-2.5 flex-row items-start">
      <View className="min-w-0 flex-1 pr-3">
        <Text className="font-sans text-sm leading-5 text-stone" numberOfLines={2}>
          {title}
        </Text>
        <Text className="mt-0.5 font-sans text-xs text-stoneMuted">
          {detail}
        </Text>
        {points === 0 && note ? (
          <Text className="mt-0.5 font-sans text-xs leading-4 text-stoneMuted">
            {note}
          </Text>
        ) : null}
      </View>
      <Text className="flex-shrink-0 font-sans-bold text-sm text-stone">
        {points > 0 ? points.toLocaleString("en-US") : "—"}
      </Text>
    </View>
  );
}

/**
 * One award a devotee has been given and is not currently showing. Drawn at
 * full strength — never dimmed, never greyed, because grey is how an app says
 * "no longer valid" and nothing here ever was.
 *
 * It carries no "on show now" chip: what is on show is the strip of medallions
 * above, and this list is everything else. The two used to overlap completely,
 * so three badges arrived as six cards.
 */
function ShelfRow({ award }: { award: DevoteeShelfAward }) {
  const highlight = award.tier === "garland" || award.tier === "maha_prasad";
  /**
   * Which week or month this one was for.
   *
   * The temple seeds Recognition, Token of Appreciation and Maha Prasad once
   * for the week and again for the month, so a devotee with a good quarter has
   * five rows all reading "Recognition · Recognition · earned Aug 12" — the
   * awards land together, so even the date does not separate them. Since 0067
   * some of those five are on show and some are not, and a shelf that cannot
   * say which is which reads as the same badge printed five times.
   *
   * Only a week or a month is named. `lifetime` is the anchor 0063 gives an
   * award earned outside any scored period — "Your First Seva" carries a
   * period starting in 1970 — and drawing that as a date range would be worse
   * than saying nothing.
   */
  const period =
    (award.period_kind === "week" || award.period_kind === "month") &&
    award.period_start &&
    award.period_end
      ? formatSevaRange(award.period_start, award.period_end)
      : null;

  return (
    <View className="mb-2.5 flex-row items-start rounded-card border border-border bg-white px-card py-3.5">
      <View
        className={`h-11 w-11 flex-shrink-0 items-center justify-center rounded-pill border-2 ${
          highlight
            ? "border-marigold bg-marigoldSoft"
            : "border-peacock bg-peacockSoft"
        }`}
      >
        <Ionicons
          name={sevaTierIcons[award.tier]}
          size={20}
          color={highlight ? tokens.colors.stone : tokens.colors.peacock}
        />
      </View>
      <View className="ml-3 min-w-0 flex-1">
        <Text className="font-sans-bold text-base leading-5 text-stone">
          {award.title}
        </Text>
        <Text className="mt-0.5 font-sans text-xs text-stoneMuted">
          {sevaTierLabel(award.tier) ?? "A gift from the temple"} ·{" "}
          {period ?? `earned ${formatSevaDate(award.awarded_on)}`}
        </Text>
        {award.citation ? (
          <Text className="mt-1.5 font-sans text-xs leading-5 text-stone">
            {award.citation}
          </Text>
        ) : null}
      </View>
    </View>
  );
}

/**
 * A ranked place, and the way into what it is made of.
 *
 * Every named row opens: a board that cannot be interrogated is a rumour, and
 * "why are they above me" is a question the temple would rather the app
 * answered than have asked at the door.
 */
function BoardRow({
  entry,
  onOpen,
}: {
  entry: BoardEntry;
  onOpen: (entry: BoardEntry) => void;
}) {
  const medal = medals[entry.standing];
  const icon = entry.tier ? sevaTierIcons[entry.tier] : null;

  return (
    <Pressable
      className={`mb-2 flex-row items-center rounded-card border px-card py-3 ${
        entry.isYou ? "border-indigo bg-indigoSoft" : "border-border bg-white"
      }`}
      accessibilityRole="button"
      accessibilityLabel={`${entry.isYou ? "You" : entry.name}, rank ${
        entry.standing
      }`}
      disabled={!entry.devoteeId}
      onPress={() => onOpen(entry)}
    >
      <View
        className={`h-8 w-8 flex-shrink-0 items-center justify-center rounded-pill ${
          medal ? medal.chip : "bg-ivory"
        }`}
      >
        <Text
          className={`font-sans-bold text-sm ${
            medal ? medal.label : "text-stoneMuted"
          }`}
        >
          {entry.standing}
        </Text>
      </View>
      <View className="ml-3 flex-shrink-0">
        <Avatar
          name={entry.name}
          photoUrl={entry.photoUrl}
          tone={medal ? "marigold" : "peacock"}
          size="small"
        />
      </View>
      <View className="ml-3 min-w-0 flex-1">
        <Text className="font-sans-bold text-base text-stone" numberOfLines={1}>
          {entry.isYou ? "You" : entry.name}
        </Text>
        {icon ? (
          <View className="mt-0.5 flex-row items-center">
            <Ionicons name={icon} size={12} color={tokens.colors.marigold} />
            <Text className="ml-1 font-sans text-xs text-stoneMuted">
              {sevaTierLabel(entry.tier)}
            </Text>
          </View>
        ) : null}
      </View>
      {entry.points === null ? null : (
        <Text className="ml-2 flex-shrink-0 font-display text-lg text-stone">
          {entry.points.toLocaleString("en-US")}
        </Text>
      )}
    </Pressable>
  );
}

/**
 * The first three, given the treatment a game gives them. Second and first and
 * third, left to right, so the tallest column is in the middle where the eye
 * lands first.
 */
function Podium({
  entries,
  onOpen,
}: {
  entries: BoardEntry[];
  onOpen: (entry: BoardEntry) => void;
}) {
  /**
   * Second, first, third — the tallest column in the middle, where the eye
   * lands. Only at exactly three: 0067 lets a shared place put four devotees
   * in the top three, and swapping a fixed pair of a four-column row would
   * have left the fourth off the screen altogether.
   */
  const order =
    entries.length === 3 ? [entries[1], entries[0], entries[2]] : entries;

  return (
    <View className="mb-4 flex-row items-end justify-center gap-2">
      {order.map((entry) => {
        const medal = medals[entry.standing] ?? medals[3];
        const crowned = entry.standing === 1;
        return (
          <Pressable
            key={entry.key}
            className={`min-w-0 flex-1 items-center rounded-card border bg-white px-2 pb-3 ${
              crowned ? "border-marigold pt-4" : "border-border pt-3"
            }`}
            accessibilityRole="button"
            accessibilityLabel={`${entry.isYou ? "You" : entry.name}, rank ${
              entry.standing
            }`}
            disabled={!entry.devoteeId}
            onPress={() => onOpen(entry)}
          >
            <View className={`rounded-pill border-2 ${medal.ring} p-0.5`}>
              <Avatar
                name={entry.name}
                photoUrl={entry.photoUrl}
                tone={crowned ? "marigold" : "peacock"}
                size={crowned ? "medium" : "small"}
              />
            </View>
            <View
              className={`-mt-2 h-6 w-6 items-center justify-center rounded-pill ${medal.chip}`}
            >
              <Text className={`font-sans-bold text-xs ${medal.label}`}>
                {entry.standing}
              </Text>
            </View>
            <Text
              className="mt-1.5 text-center font-sans-bold text-xs leading-4 text-stone"
              numberOfLines={2}
            >
              {entry.isYou ? "You" : entry.name}
            </Text>
            {entry.points === null ? null : (
              <Text className="mt-0.5 font-display text-sm text-stone">
                {entry.points.toLocaleString("en-US")}
              </Text>
            )}
          </Pressable>
        );
      })}
    </View>
  );
}

/**
 * Supporters, deliberately not a board: no order, no places, no amounts. A
 * ranked money list is a donor wall, and the temple asked to recognise giving
 * without ranking it. Drawn as a scatter of names so it cannot be mistaken for
 * a leaderboard that failed to sort.
 */
function SupporterWall({ names }: { names: readonly SevaSupporter[] }) {
  return (
    <View className="rounded-card border border-marigold bg-white px-card py-5">
      <Text className="text-center font-display text-xl text-stone">
        With thanks
      </Text>
      <Text className="mt-1 text-center font-sans text-xs leading-4 text-stoneMuted">
        Everyone who gave this period, in no order at all.
      </Text>
      <View className="mt-4 flex-row flex-wrap justify-center gap-2">
        {names.map((row) => (
          <View
            key={row.devotee_id}
            className="max-w-full flex-row items-center rounded-pill bg-ivory py-1 pl-1 pr-3"
          >
            <Avatar
              name={row.devotee_name}
              photoUrl={row.devotee_photo_url}
              tone="marigold"
              size="tiny"
            />
            <Text
              className="ml-2 min-w-0 shrink font-sans-bold text-xs text-stone"
              numberOfLines={1}
            >
              {row.devotee_name}
            </Text>
          </View>
        ))}
      </View>
    </View>
  );
}

/** One quiet card, for every case where a board cannot be drawn. */
function BoardNotice({
  icon,
  title,
  children,
}: {
  icon: keyof typeof Ionicons.glyphMap;
  title: string;
  children: string;
}) {
  return (
    <View className="items-center rounded-card border border-border bg-white px-card py-9">
      <View className="h-14 w-14 items-center justify-center rounded-pill bg-peacockSoft">
        <Ionicons name={icon} size={26} color={tokens.colors.peacock} />
      </View>
      <Text className="mt-4 text-center font-display text-xl text-stone">
        {title}
      </Text>
      <Text className="mt-2 max-w-80 text-center font-sans text-sm leading-6 text-stoneMuted">
        {children}
      </Text>
    </View>
  );
}

export function SevaYatraScreen() {
  const navigation = useNavigation<NavigationProp<HomeStackParamList>>();
  const activeUserId = usePrototypeSession((state) => state.activeUserId);
  const accessProfile = useCurrentAccessProfile(activeUserId);
  const role =
    (accessProfile.data?.role ?? "devotee");
  const mayViewAll = hasAccessPermission(role, "app.view_all");
  const reachable = useServerReachable();

  const [requestedTab, setRequestedTab] = useState<Tab>("profile");
  const [mode, setMode] = useState<SevaBoardMode>("combined");
  const [range, setRange] = useState<SevaRangeKind>("week");
  const [showAllSeva, setShowAllSeva] = useState(false);
  const [showAllGifts, setShowAllGifts] = useState(false);
  const [showWholeShelf, setShowWholeShelf] = useState(false);
  const [visibilityError, setVisibilityError] = useState<string | null>(null);

  // The role arrives after the first render, so a President who left the app on
  // Seva Care would land on a section they are briefly not allowed to see.
  // Falling back rather than resetting means the tab returns on its own.
  const tab: Tab = requestedTab === "care" && !mayViewAll ? "profile" : requestedTab;
  const onProfile = tab === "profile";
  const onBoard = tab === "board";

  // Null for the calendar year: the scoring reads a year and never ranks one,
  // so there is no period row and no board to ask for.
  const period = scoredPeriodForRange(range);
  const ranked = period !== null;

  // Falls back to the week for the calendar year, which has no period row of
  // its own. Not for the hero — the year's figures come from `windows` below —
  // but because `leaderboard_visible` lives on this row, and a devotee reading
  // their year must not be shown the board switch sitting off.
  const mala = useMySevaMala(activeUserId, period ?? "week");
  // The calendar year's own totals, which `my_seva_profile` has and the period
  // scoring does not. Only asked for when the year is what is on screen.
  const windows = useMySevaProfile(activeUserId, onProfile && !ranked);

  /**
   * Both boards and the wall of thanks are public reads.
   *
   * They used to come from `list_all_seva_scores`, which answers with nothing
   * to anybody without app.view_all — so an ordinary devotee got a board with
   * no numbers on it and was told, untruthfully, that the other two modes were
   * still being built. The server has published all three to the whole
   * congregation since 0060; only the rank is ours to choose.
   */
  const rank = garlandRankForMode(mode);
  const garland = useSevaGarland(
    period ?? "week",
    rank ?? "combined",
    ranked && rank !== null && Boolean(activeUserId),
  );
  const supporters = useSevaSupporters(
    period ?? "week",
    ranked && rank === null && Boolean(activeUserId),
  );
  const setVisibility = useSetLeaderboardVisibility(activeUserId);

  const yearRow = useMemo(
    () => windows.data?.find((row) => row.window_kind === "year") ?? null,
    [windows.data],
  );

  /**
   * One shape for the hero and the figures, whichever read answered. Built here
   * rather than in the hero so that the year — which has hours and giving but
   * no score — travels the same path as a scored period instead of forking the
   * whole section.
   */
  const standing = useMemo<Standing | null>(() => {
    /**
     * A range the server answered about with nothing is still a range the
     * devotee chose, and a screen that draws no hero at all for it reads as a
     * failure. Zeroes with the range's own name on them read as what they are.
     */
    const nothing: Standing = {
      points: ranked ? 0 : null,
      rank: null,
      yourRank: null,
      gathering: false,
      servedHours: 0,
      countedHours: 0,
      givingCents: 0,
      pendingActs: 0,
      from: null,
      to: null,
    };

    if (ranked) {
      const row = mala.data;
      // Undefined is "has not answered"; null is "answered with nothing".
      if (row === undefined) return null;
      if (row === null) return nothing;
      const credited = Number(row.seva_minutes ?? 0) / 60;
      return {
        points: sevaPoints(row.score),
        rank: row.board_standing ?? null,
        yourRank: row.standing ?? null,
        gathering: Boolean(row.gathering),
        // Hours from what they served, points from what the scoring credited.
        // 0066 sends both precisely so that neither has to stand in for the
        // other, and the two are kept apart all the way to the two labels.
        servedHours: Number(row.served_minutes ?? 0) / 60,
        countedHours: credited,
        givingCents: row.giving_cents ?? 0,
        pendingActs: row.pending_acts ?? 0,
        from: row.period_start,
        to: row.period_end,
      };
    }
    if (windows.data === undefined) return null;
    if (!yearRow) return nothing;
    return {
      points: null,
      rank: null,
      // A calendar year is never ranked, publicly or privately.
      yourRank: null,
      gathering: false,
      servedHours: Number(yearRow.hours ?? 0),
      countedHours: Number(yearRow.counted_hours ?? 0),
      givingCents: yearRow.giving_cents ?? 0,
      pendingActs: yearRow.pending_acts ?? 0,
      from: yearRow.window_start,
      to: yearRow.window_end,
    };
  }, [ranked, mala.data, windows.data, yearRow]);

  const standingQuery = ranked ? mala : windows;
  const standingFailed =
    standingQuery.isError && standingQuery.data === undefined;

  const visible = setVisibility.isPending
    ? Boolean(setVisibility.variables)
    : Boolean(mala.data?.leaderboard_visible);
  const canToggle = Boolean(activeUserId) && Boolean(mala.data);

  const garlandRows = garland.data ?? [];
  const gathering =
    garlandRows.some((row) => row.gathering) || Boolean(mala.data?.gathering);

  // The range's own bounds, so the window is the whole of what it is priced
  // against and the rows sum to the hero. Asked for only once the range's row
  // has arrived, because the server's default window is ninety days and would
  // answer with a different stretch's arithmetic.
  const windowFrom = standing?.from ?? null;
  const windowTo = standing?.to ?? null;
  const actPoints = useSevaActPoints(
    activeUserId,
    activeUserId,
    windowFrom,
    windowTo,
    onProfile && Boolean(windowFrom && windowTo),
  );
  const givingPoints = useSevaGivingPoints(
    activeUserId,
    activeUserId,
    windowFrom,
    windowTo,
    onProfile && Boolean(windowFrom && windowTo),
  );
  const badges = useDevoteeBadges(activeUserId, onProfile);
  const shelf = useDevoteeAwardShelf(activeUserId, onProfile);
  const legend = useSevaBadgeLegend(onProfile);

  const actRows = actPoints.data ?? [];
  const giftRows = givingPoints.data ?? [];
  /**
   * Which of the three waiting states the window actually holds. `my_seva_mala`
   * counts the waiting acts but does not say what they wait on; the per-act
   * rows for the same window do, and they are already on the screen.
   */
  const pendingPhrase = useMemo(
    () => pendingSevaPhrase(actRows.map((row) => row.points_status)),
    [actRows],
  );
  // Both halves at once, so the section does not appear in two steps.
  const detailLoading =
    Boolean(windowFrom) && (actPoints.isLoading || givingPoints.isLoading);
  const shelfRows = shelf.data ?? [];
  const badgeRows = badges.data ?? [];
  /**
   * The two badge presentations, made to answer different questions.
   *
   * The medallions are what the congregation sees on this devotee's profile
   * right now. The shelf is everything else they have ever been given — so an
   * award is on the screen once, in whichever half it belongs to, rather than
   * as a medallion and again as a card three lines down.
   *
   * Taken off the award ids rather than off `is_current`, because the two are
   * the same predicate only while both reads have answered: before the badges
   * land the shelf is the whole record, which is still true and still shows
   * nothing twice.
   */
  const onShow = new Set(badgeRows.map((badge) => badge.award_id));
  const keptRows = shelfRows.filter((award) => !onShow.has(award.award_id));
  const shownActs = showAllSeva ? actRows : actRows.slice(0, DETAIL_ROWS);
  const shownGifts = showAllGifts ? giftRows : giftRows.slice(0, DETAIL_ROWS);
  const shownShelf = showWholeShelf ? keptRows : keptRows.slice(0, SHELF_ROWS);

  /**
   * The board, in the order and with the figures the server published.
   *
   * Both rankings are the same function, so one mapping draws both and they
   * cannot come to disagree about ties: the server dense-ranks, and a rank
   * worked out here from a column of scores gave 1, 2, 2, 4 where the temple's
   * own board says 1, 2, 2, 3.
   */
  const boardRows = useMemo<BoardEntry[]>(
    () =>
      garlandRows
        .filter((row) => !row.gathering && row.standing !== null)
        .map((row) => ({
          key: row.devotee_id ?? `place-${row.standing}`,
          devoteeId: row.devotee_id,
          standing: row.standing ?? 0,
          name: row.devotee_name ?? "A devotee",
          photoUrl: row.devotee_photo_url,
          tier: row.tier,
          isYou: row.is_you,
          // Published to every signed-in devotee, and already rounded to the
          // step the hero rounds to. Never recomputed from a score here: the
          // score is app.view_all's, and reading points off it is what left an
          // ordinary devotee looking at a board of names and no numbers.
          points: row.points ?? null,
        })),
    [garlandRows],
  );

  // The server appends the caller underneath when they placed outside the band,
  // in both rankings, so that row has to be lifted out and drawn after the ellipsis.
  const youBelow = boardRows.find(
    (entry) => entry.isYou && entry.standing > BOARD_BAND,
  );
  const board = boardRows.filter((entry) => entry !== youBelow);
  /**
   * The podium holds PLACES, not rows.
   *
   * 0067 ranks the board on the published points, so two devotees showing the
   * same number share a place and a board reads 1, 2, 2, 3. Taking the first
   * three ROWS split a shared place down the middle: of two devotees tied for
   * third, one stood on the podium and the other was the first row of the list
   * underneath, decided by nothing a devotee can see. Filtering on the standing
   * keeps a shared place whole.
   *
   * Past four the columns are slivers on a 320dp phone, so a board that ties
   * that widely across the top three places is drawn as a plain ranked list —
   * which is still exact, and still says 1, 2, 2, 3.
   */
  const topPlaces = board.filter((entry) => entry.standing <= PODIUM_PLACES);
  const podium = topPlaces.length <= PODIUM_COLUMNS ? topPlaces : [];
  // `board` arrives in the server's own order — standing, then name — so the
  // rest is everything the podium did not take, whether or not it took any.
  const rest = board.slice(podium.length);

  const supporterRows = supporters.data ?? [];
  const boardQuery = rank === null ? supporters : garland;
  const boardFailed = boardQuery.isError && boardQuery.data === undefined;

  const openFindSeva = () => {
    navigation
      .getParent<NavigationProp<MainTabParamList>>()
      ?.navigate("Services", { screen: "FindSeva" });
  };

  const openDevotee = (entry: BoardEntry) => {
    if (!entry.devoteeId) return;
    navigation.navigate("SevaBoardDevotee", {
      devoteeId: entry.devoteeId,
      name: entry.name,
      photoUrl: entry.photoUrl,
      range,
    });
  };

  const changeRange = (next: SevaRangeKind) => {
    setRange(next);
    // The lists below belong to the range, so an opened one must not stay
    // opened over a different set of rows.
    setShowAllSeva(false);
    setShowAllGifts(false);
  };

  const toggleVisibility = () => {
    setVisibilityError(null);
    setVisibility.mutate(!visible, {
      onError: (error: unknown) =>
        setVisibilityError(
          errorMessage(
            error,
            "That could not be saved. Your seva is unaffected either way.",
          ),
        ),
    });
  };

  const tabs: { key: Tab; label: string }[] = [
    { key: "profile", label: "Seva Profile" },
    { key: "board", label: "Leaderboard" },
    // Seva Care is a section of Seva Yatra rather than a link off the foot of
    // the leaderboard, which is where the temple kept losing it.
    ...(mayViewAll ? [{ key: "care" as const, label: "Seva Care" }] : []),
  ];

  return (
    <Screen topInset={false}>
      <ScreenTitle eyebrow="Seva Yatra">Your journey of service</ScreenTitle>

      <View className="mb-4">
        <SevaSegmented value={tab} options={tabs} onChange={setRequestedTab} />
      </View>

      {/* The three board modes were pills that sized to their labels, and on a
          320dp Android phone the third one ran off the edge with "Seva only"
          losing its second word. Equal thirds of whatever width there is
          cannot overflow, whatever the labels become. */}
      {onBoard ? (
        <View className="mb-3">
          <SevaSegmented
            value={mode}
            options={sevaBoardModes}
            onChange={setMode}
            accessibilityRole="radio"
          />
        </View>
      ) : null}

      {/* Seva Care is measured over a fixed trailing quarter, so there is no
          range for a chooser to choose. */}
      {tab === "care" ? null : (
        <View className="mb-4">
          <SevaChipRow
            value={range}
            options={rangeOptions}
            onChange={changeRange}
          />
        </View>
      )}

      {onProfile ? (
        <>
          {standingQuery.isLoading ? (
            <SkeletonCard />
          ) : standingFailed ? (
            <LoadFailure
              reachable={reachable}
              message={errorMessage(
                standingQuery.error,
                "Your seva could not be loaded.",
              )}
              onRetry={() => void standingQuery.refetch()}
            />
          ) : standing ? (
            <>
              <PointsHero
                standing={standing}
                range={range}
                pendingPhrase={pendingPhrase}
              />
              <StandingFigures standing={standing} />
            </>
          ) : null}

          {detailLoading ? (
            <View className="mt-section">
              <Skeleton height={132} />
            </View>
          ) : actRows.length || giftRows.length ? (
            <View className="mt-section">
              <SectionHeader
                title={
                  ranked ? "Where these points came from" : "What you offered"
                }
                subtitle={
                  windowFrom && windowTo
                    ? formatSevaRange(windowFrom, windowTo)
                    : undefined
                }
              />

              {actRows.length ? (
                <ContributionCard
                  title="Your seva"
                  // The hours are on the card above and per act below. A third
                  // hours total here would be the same figure said differently,
                  // which is the confusion this screen was redrawn to end.
                  measure={sevaCountLabel(actRows.length, "act")}
                  points={actRows[0].seva_points}
                  note={actRows[0].attribution}
                  shown={shownActs.length}
                  total={actRows.length}
                  onShowAll={() => setShowAllSeva(true)}
                >
                  {shownActs.map((row: SevaActPointsRow) => (
                    <ContributionRow
                      key={row.assignment_id}
                      title={row.seva_name}
                      detail={`${formatSevaDate(row.occurred_on)} · ${formatHours(
                        Number(row.minutes ?? 0) / 60,
                      )}`}
                      points={row.points}
                      note={row.points_note}
                    />
                  ))}
                </ContributionCard>
              ) : null}

              {giftRows.length ? (
                <ContributionCard
                  title="Your giving"
                  measure={sevaCountLabel(giftRows.length, "gift")}
                  points={giftRows[0].giving_points}
                  note={giftRows[0].attribution}
                  shown={shownGifts.length}
                  total={giftRows.length}
                  onShowAll={() => setShowAllGifts(true)}
                >
                  {shownGifts.map((row: SevaGiftPointsRow) => (
                    <ContributionRow
                      key={row.donation_id}
                      title={
                        row.sponsorship_type_name ?? donationKindLabel(row)
                      }
                      detail={`${formatSevaDate(row.received_on)} · ${formatCents(
                        row.amount_cents,
                        row.currency,
                      )}`}
                      points={row.points}
                    />
                  ))}
                </ContributionCard>
              ) : null}
            </View>
          ) : null}

          <View className="mt-section">
            <SectionHeader
              title="Badges"
              // The badges themselves are the same either way. Who can see them
              // is not, and this is the only place on the screen that claims
              // anything about that.
              subtitle={
                visible
                  ? "What other devotees see on your profile."
                  : "This period’s, shown only to you while you are off the board."
              }
            />
            {badges.isLoading ? (
              <Skeleton height={112} />
            ) : badgeRows.length ? (
              <ScrollView
                horizontal
                showsHorizontalScrollIndicator={false}
                contentContainerClassName="gap-3 py-1 pr-4"
              >
                {badgeRows.map((badge) => (
                  <BadgeMedallion
                    key={badge.award_id}
                    tier={badge.tier}
                    title={badge.title}
                    caption={sevaTierLabel(badge.tier)}
                  />
                ))}
              </ScrollView>
            ) : (
              <View className="items-center rounded-card border border-border bg-white px-card py-7">
                <View className="h-14 w-14 items-center justify-center rounded-pill bg-marigoldSoft">
                  <Ionicons
                    name="gift-outline"
                    size={26}
                    color={tokens.colors.stone}
                  />
                </View>
                <Text className="mt-3 max-w-80 text-center font-sans text-sm leading-6 text-stoneMuted">
                  {shelfRows.length
                    ? "Nothing of yours is on show for this period. Everything you have earned is on your shelf below, and it stays there."
                    : "No badge yet. The temple gives these when a week or a month closes, and once given they are never taken back."}
                </Text>
                {shelfRows.length ? null : (
                  <View className="mt-4">
                    <Button
                      variant="secondary"
                      icon="search-outline"
                      onPress={openFindSeva}
                    >
                      Find a seva
                    </Button>
                  </View>
                )}
              </View>
            )}

            {/* Both legends live behind this one line. All ten badges are in
                there whether or not the devotee holds any of them — a legend
                that only lists what you already have is not a legend — and it
                costs the screen a single row of text until it is asked for. */}
            <Disclosure label="What the badges and gifts are">
              <SevaAwardLegend badges={legend.data} />
            </Disclosure>
          </View>

          {/* The shelf, which only ever grows: everything the medallions above
              are not showing. A badge leaves the strip when the next period's
              awards land, and while a devotee is off the board — and neither is
              a loss, which is what the subtitle has to be true about. */}
          {keptRows.length ? (
            <View className="mt-section">
              <SectionHeader
                title="Kept on your shelf"
                subtitle="Not on show right now, and yours for good."
              />
              {shownShelf.map((award) => (
                <ShelfRow key={award.award_id} award={award} />
              ))}
              {keptRows.length > shownShelf.length ? (
                <SeeAll
                  total={keptRows.length}
                  label="on my shelf"
                  onPress={() => setShowWholeShelf(true)}
                />
              ) : null}
            </View>
          ) : null}

          <Pressable
            className="mt-section min-h-touch flex-row items-center rounded-card border border-border bg-white px-card py-3.5"
            accessibilityRole="button"
            accessibilityLabel="See my seva history"
            onPress={() => navigation.navigate("SevaHistory")}
          >
            <Ionicons
              name="time-outline"
              size={20}
              color={tokens.colors.indigo}
            />
            <Text className="ml-3 min-w-0 flex-1 font-sans-bold text-base text-stone">
              See my seva history
            </Text>
            <Ionicons
              name="chevron-forward"
              size={18}
              color={tokens.colors.stoneMuted}
            />
          </Pressable>

          <Pressable
            className={`mt-3 min-h-[72px] flex-row items-center rounded-card border px-card py-3 ${
              visible ? "border-peacock bg-peacock" : "border-border bg-white"
            }`}
            accessibilityRole="switch"
            accessibilityLabel="Show me on the leaderboard"
            // Until the row has arrived the flag is unknown, and a switch drawn
            // off when it is really on would flip a devotee onto the board.
            accessibilityState={{ checked: visible, disabled: !canToggle }}
            disabled={!canToggle}
            onPress={toggleVisibility}
          >
            <View className="min-w-0 flex-1 pr-3">
              <Text
                className={`font-sans-bold text-base leading-5 ${
                  visible ? "text-white" : "text-stone"
                }`}
              >
                Show me on the leaderboard
              </Text>
              <Text
                className={`mt-1 font-sans text-xs leading-4 ${
                  visible ? "text-white" : "text-stoneMuted"
                }`}
              >
                Your points and everything on your shelf are earned either way —
                this only decides whether other devotees see your name.
              </Text>
            </View>
            <View
              pointerEvents="none"
              className={`h-7 w-12 flex-shrink-0 justify-center rounded-pill px-1 ${
                visible ? "bg-marigoldSoft" : "bg-indigo"
              }`}
            >
              <View
                className={`h-5 w-5 rounded-pill bg-white shadow-sm ${
                  visible ? "translate-x-5" : "translate-x-0"
                }`}
              />
            </View>
          </Pressable>
          {visibilityError ? <FormError message={visibilityError} /> : null}
        </>
      ) : null}

      {onBoard ? (
        <>
          {!ranked ? (
            <BoardNotice icon="calendar-outline" title="Not a ranked period">
              The temple ranks the week, the month and all time. A year is a
              read rather than a race — your own year is on Seva Profile.
            </BoardNotice>
          ) : boardFailed ? (
            <LoadFailure
              reachable={reachable}
              message={errorMessage(
                boardQuery.error,
                "The leaderboard could not be loaded.",
              )}
              onRetry={() => void boardQuery.refetch()}
            />
          ) : gathering ? (
            <BoardNotice icon="people-outline" title="Still gathering">
              Too few devotees have served this period for a board to mean
              anything yet. Everything anybody offers is counted, and the board
              opens once the congregation is here.
            </BoardNotice>
          ) : rank === null ? (
            supporterRows.length ? (
              <SupporterWall names={supporterRows} />
            ) : (
              <EmptyOrOffline
                reachable={reachable}
                loading={supporters.isLoading}
                loadingLabel="Reading this period…"
                empty={
                  <View className="items-center rounded-card border border-border bg-white px-card py-9">
                    <Text className="text-center font-sans text-sm leading-6 text-stoneMuted">
                      Nobody has given in this period yet.
                    </Text>
                  </View>
                }
              />
            )
          ) : board.length ? (
            <>
              <Podium entries={podium} onOpen={openDevotee} />
              {rest.map((entry) => (
                <BoardRow key={entry.key} entry={entry} onOpen={openDevotee} />
              ))}
              {youBelow ? (
                <>
                  <View className="my-2 items-center">
                    <Text className="font-sans text-xs text-stoneMuted">
                      • • •
                    </Text>
                  </View>
                  <BoardRow entry={youBelow} onOpen={openDevotee} />
                </>
              ) : null}
            </>
          ) : (
            <EmptyOrOffline
              reachable={reachable}
              loading={boardQuery.isLoading}
              loadingLabel="Reading the board…"
              empty={
                <View className="items-center rounded-card border border-border bg-white px-card py-9">
                  <Text className="text-center font-sans text-sm leading-6 text-stoneMuted">
                    Nobody has appeared on the board for this period yet.
                  </Text>
                </View>
              }
            />
          )}

          {/* Said wherever a devotee is off the board, rather than only under a
              board that happened to have somebody else on it: an empty board is
              exactly where "where am I?" is loudest, and a temple small enough
              for everybody to have opted out is where it looks most broken.
              Never on the wall of thanks, which is not a board and does not
              rank anybody — but the same flag does take a name off it, so it is
              worded as being left off rather than as being left off the board. */}
          {ranked &&
          rank !== null &&
          !visible &&
          !gathering &&
          !boardFailed &&
          canToggle ? (
            <View className="mt-3 rounded-card border border-indigo bg-indigoSoft px-card py-3.5">
              <Text className="font-sans text-sm leading-6 text-stone">
                You asked to be left off, so your name is not here. Your points,
                gifts and badges are all still yours, and your own standing is
                on Seva Profile.
              </Text>
            </View>
          ) : null}
        </>
      ) : null}

      {tab === "care" ? <SevaCarePanel /> : null}
    </Screen>
  );
}
