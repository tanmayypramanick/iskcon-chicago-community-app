import { Ionicons } from "@expo/vector-icons";
import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import { useMemo, useState } from "react";
import { Alert, Pressable, Text, View } from "react-native";

import tokens from "../../design-tokens.json";
import {
  Button,
  LoadFailure,
  Screen,
  ScreenTitle,
  SectionHeader,
  Skeleton,
} from "../components/ui";
import { useCurrentAccessProfile } from "../features/access/hooks";
import { openZeffyPage } from "../features/donations/api";
import {
  useHoldSponsorship,
  useMySponsorships,
  useReleaseSponsorshipHold,
  useSponsorshipAvailability,
  useSponsorshipTypes,
} from "../features/donations/hooks";
import {
  dateKeyWeekday,
  formatCents,
  formatSponsorshipDate,
  SPONSORSHIP_HOLD_MINUTES,
  sponsorshipIsPayable,
  sponsorshipNeedsDate,
  type SponsorshipAvailability,
  type SponsorshipType,
} from "../features/donations/types";
import { FormError } from "../features/services/components";
import { errorMessage } from "../features/services/format";
import {
  formatChicagoTime,
  getChicagoDateKey,
  getChicagoWallClock,
  getChicagoZoneAbbreviation,
} from "../lib/chicagoDate";
import { useServerReachable } from "../lib/connectivity";
import { useNow } from "../lib/useNow";
import type { HomeStackParamList } from "../navigation/types";
import { usePrototypeSession } from "../store/usePrototypeSession";

type Props = NativeStackScreenProps<
  HomeStackParamList,
  "SponsorshipCalendar"
>;

/** How far ahead the calendar will walk. The temple books a season, not a decade. */
const MONTHS_AHEAD = 12;

const WEEKDAY_INITIALS = ["S", "M", "T", "W", "T", "F", "S"];

function pad(value: number) {
  return String(value).padStart(2, "0");
}

function dateKeyFor(year: number, month: number, day: number) {
  return `${year}-${pad(month)}-${pad(day)}`;
}

/**
 * The grid is built from arithmetic on UTC instants rather than from a
 * calendar library or from `new Date(y, m, d)`. A device-local Date would put
 * the first of the month on the previous day for anybody east of Greenwich,
 * and a devotee in Delhi would be shown a month shifted by one square.
 */
function daysInMonth(year: number, month: number) {
  return new Date(Date.UTC(year, month, 0)).getUTCDate();
}

function firstWeekdayOfMonth(year: number, month: number) {
  return new Date(Date.UTC(year, month - 1, 1)).getUTCDay();
}

function monthLabel(year: number, month: number) {
  return new Intl.DateTimeFormat("en-US", {
    timeZone: "UTC",
    month: "long",
    year: "numeric",
  }).format(new Date(Date.UTC(year, month - 1, 1)));
}

function addMonths(year: number, month: number, delta: number) {
  const zeroBased = year * 12 + (month - 1) + delta;
  return { year: Math.floor(zeroBased / 12), month: (zeroBased % 12) + 1 };
}

function monthIndex(year: number, month: number) {
  return year * 12 + (month - 1);
}

/**
 * "Sunday Feast" and "Sunday Feast (higher)" are two rows in the sponsorship
 * table because they are two prices, but they are one page on Zeffy and one
 * seva to a devotee. The campaign slug is what says so — 0050 lets several
 * price tiers share one, and makes them agree about how they are booked — so
 * that is the grouping key rather than anything read out of the name.
 *
 * A sponsorship with no campaign yet stands alone, keyed by its own id: two
 * unconfigured sevas must not be folded together just because both are null.
 */
function campaignKey(type: SponsorshipType) {
  return type.zeffy_campaign_slug?.trim() || `type:${type.id}`;
}

/** The tier suffix is the price's label, not the seva's name. */
function tierBaseName(name: string) {
  return name.replace(/\s*\([^()]*\)\s*$/, "").trim() || name;
}

type TierGroup = { key: string; base: string; tiers: SponsorshipType[] };

function groupIntoTiers(types: SponsorshipType[]): TierGroup[] {
  const order: string[] = [];
  const byCampaign = new Map<string, SponsorshipType[]>();
  for (const type of types) {
    const key = campaignKey(type);
    const existing = byCampaign.get(key);
    if (existing) {
      existing.push(type);
    } else {
      byCampaign.set(key, [type]);
      order.push(key);
    }
  }
  return order.map((key) => {
    const tiers = byCampaign.get(key) ?? [];
    return { key, base: tierBaseName(tiers[0]?.name ?? ""), tiers };
  });
}

/** A sponsorship this devotee is holding right now, whichever call found it. */
type LiveHold = {
  id: string;
  onDate: string | null;
  heldUntil: string | null;
  amountCents: number;
};

function Badge({
  label,
  tone,
}: {
  label: string;
  tone: "peacock" | "marigold" | "muted";
}) {
  const { box, text } = {
    peacock: { box: "bg-peacockSoft", text: "text-peacock" },
    marigold: { box: "bg-marigoldSoft", text: "text-stone" },
    muted: { box: "bg-sandalwood", text: "text-stoneMuted" },
  }[tone];
  return (
    <View className={`rounded-pill px-2.5 py-1 ${box}`}>
      <Text className={`font-sans-bold text-[11px] ${text}`}>{label}</Text>
    </View>
  );
}

function TierGroupCard({
  group,
  onChoose,
}: {
  group: TierGroup;
  onChoose: (type: SponsorshipType) => void;
}) {
  const first = group.tiers[0];
  if (!first) return null;

  const sundayOnly = group.tiers.some((tier) => tier.sunday_only);
  const undated = group.tiers.every((tier) => !sponsorshipNeedsDate(tier));
  const payable = group.tiers.some(sponsorshipIsPayable);
  const multiTier = group.tiers.length > 1;

  return (
    <View className="mb-3 rounded-card border border-border bg-white p-card">
      <View className="flex-row items-start justify-between">
        <Text className="min-w-0 flex-1 pr-3 font-sans-bold text-base text-stone">
          {group.base}
        </Text>
        {sundayOnly ? <Badge label="Sundays only" tone="peacock" /> : null}
        {undated ? <Badge label="No date needed" tone="marigold" /> : null}
      </View>

      {multiTier ? (
        <Text className="mt-1 font-sans text-xs leading-4 text-stoneMuted">
          Offered at two tiers. Choose the one you wish to give.
        </Text>
      ) : null}

      {payable ? (
        <View className="mt-3 flex-row flex-wrap gap-2">
          {group.tiers.map((tier) => {
            const tierPayable = sponsorshipIsPayable(tier);
            return (
              <Pressable
                key={tier.id}
                className={`min-h-touch grow flex-row items-center justify-between rounded-button border px-4 py-3 ${
                  tierPayable
                    ? "border-border bg-ivory"
                    : "border-border bg-sandalwood"
                }`}
                accessibilityRole="button"
                accessibilityState={{ disabled: !tierPayable }}
                accessibilityLabel={`${tier.name}, ${formatCents(tier.amount_cents)}${
                  tierPayable ? "" : ", not yet payable in the app"
                }`}
                disabled={!tierPayable}
                onPress={() => onChoose(tier)}
              >
                <Text
                  className={`font-sans-bold text-base ${
                    tierPayable ? "text-stone" : "text-stoneMuted"
                  }`}
                >
                  {formatCents(tier.amount_cents)}
                </Text>
                <Ionicons
                  name="chevron-forward"
                  size={18}
                  color={
                    tierPayable ? tokens.colors.indigo : tokens.colors.stoneMuted
                  }
                />
              </Pressable>
            );
          })}
        </View>
      ) : (
        <View className="mt-3">
          <Text className="font-sans text-sm leading-5 text-stoneMuted">
            {formatCents(first.amount_cents)} — the temple has not opened its
            payment page for this one yet. Please ask at the office.
          </Text>
        </View>
      )}
    </View>
  );
}

type DayCell = {
  key: string;
  day: number;
  dateKey: string;
  past: boolean;
  offered: boolean;
  taken: boolean;
  mine: boolean;
};

function CalendarGrid({
  cells,
  leadingBlanks,
  selectedDate,
  onSelect,
}: {
  cells: DayCell[];
  leadingBlanks: number;
  selectedDate: string | null;
  onSelect: (dateKey: string) => void;
}) {
  const squares: Array<DayCell | null> = [
    ...Array.from({ length: leadingBlanks }, () => null),
    ...cells,
  ];
  while (squares.length % 7 !== 0) squares.push(null);

  const weeks: Array<Array<DayCell | null>> = [];
  for (let index = 0; index < squares.length; index += 7) {
    weeks.push(squares.slice(index, index + 7));
  }

  return (
    <View>
      <View className="flex-row">
        {WEEKDAY_INITIALS.map((initial, index) => (
          <View key={index} className="flex-1 items-center py-1.5">
            <Text className="font-sans-bold text-[11px] text-stoneMuted">
              {initial}
            </Text>
          </View>
        ))}
      </View>

      {weeks.map((week, weekIndex) => (
        <View key={weekIndex} className="flex-row">
          {week.map((cell, dayIndex) => (
            <View
              key={cell?.key ?? `blank-${weekIndex}-${dayIndex}`}
              className="flex-1 p-0.5"
              style={{ aspectRatio: 1 }}
            >
              {cell ? (
                <DaySquare
                  cell={cell}
                  selected={selectedDate === cell.dateKey}
                  onSelect={onSelect}
                />
              ) : null}
            </View>
          ))}
        </View>
      ))}
    </View>
  );
}

function DaySquare({
  cell,
  selected,
  onSelect,
}: {
  cell: DayCell;
  selected: boolean;
  onSelect: (dateKey: string) => void;
}) {
  const free = cell.offered && !cell.taken && !cell.past;

  // A day that cannot be booked must not merely look different — it must not
  // answer a tap at all, or a devotee taps a taken date three times before
  // believing it.
  const disabled = !free;

  const box = selected
    ? "border-indigo bg-indigo"
    : cell.mine
      ? "border-peacock bg-peacockSoft"
      : cell.taken
        ? "border-border bg-sandalwood"
        : free
          ? "border-border bg-white"
          : "border-transparent bg-transparent";

  const label = selected
    ? "text-white"
    : cell.mine
      ? "text-peacock"
      : cell.taken
        ? "text-stoneMuted"
        : free
          ? "text-stone"
          : "text-stoneMuted opacity-40";

  const state = cell.past
    ? "already passed"
    : !cell.offered
      ? "not offered on this day"
      : cell.mine
        ? "sponsored by you"
        : cell.taken
          ? "already sponsored"
          : "free";

  return (
    <Pressable
      className={`flex-1 items-center justify-center rounded-button border ${box}`}
      accessibilityRole="button"
      accessibilityState={{ disabled, selected }}
      accessibilityLabel={`${formatSponsorshipDate(cell.dateKey)}, ${state}`}
      disabled={disabled}
      onPress={() => onSelect(cell.dateKey)}
    >
      <Text className={`font-sans-bold text-sm ${label}`}>{cell.day}</Text>
      {cell.taken && !selected ? (
        <View
          className={`mt-0.5 h-1 w-1 rounded-pill ${
            cell.mine ? "bg-peacock" : "bg-stoneMuted"
          }`}
        />
      ) : null}
    </Pressable>
  );
}

function LegendDot({
  boxClass,
  label,
}: {
  boxClass: string;
  label: string;
}) {
  return (
    <View className="flex-row items-center">
      <View className={`h-3.5 w-3.5 rounded-[5px] border ${boxClass}`} />
      <Text className="ml-1.5 font-sans text-xs text-stoneMuted">{label}</Text>
    </View>
  );
}

export function SponsorshipCalendarScreen({ route, navigation }: Props) {
  const activeUserId = usePrototypeSession((state) => state.activeUserId);
  const profile = useCurrentAccessProfile(activeUserId);
  const reachable = useServerReachable();
  const now = useNow(15_000);

  const types = useSponsorshipTypes();
  const mySponsorships = useMySponsorships(activeUserId);
  const hold = useHoldSponsorship(activeUserId);
  const release = useReleaseSponsorshipHold(activeUserId);

  const [selectedTypeId, setSelectedTypeId] = useState<string | null>(
    route.params?.typeId ?? null,
  );
  const [selectedDate, setSelectedDate] = useState<string | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);
  const [justHeldId, setJustHeldId] = useState<string | null>(null);

  const todayKey = getChicagoDateKey(now);
  const templeToday = getChicagoWallClock(now);
  const [visibleMonth, setVisibleMonth] = useState(() => {
    const clock = getChicagoWallClock();
    return { year: clock.year, month: clock.month };
  });

  const activeTypes = useMemo(
    () => (types.data ?? []).filter((type) => type.is_active),
    [types.data],
  );

  const selectedType = useMemo(
    () => activeTypes.find((type) => type.id === selectedTypeId) ?? null,
    [activeTypes, selectedTypeId],
  );

  const needsDate = selectedType ? sponsorshipNeedsDate(selectedType) : true;

  const monthFrom = dateKeyFor(visibleMonth.year, visibleMonth.month, 1);
  const monthTo = dateKeyFor(
    visibleMonth.year,
    visibleMonth.month,
    daysInMonth(visibleMonth.year, visibleMonth.month),
  );

  const availability = useSponsorshipAvailability(
    monthFrom,
    monthTo,
    Boolean(selectedType) && needsDate,
  );

  const availabilityByDate = useMemo(() => {
    const map = new Map<string, SponsorshipAvailability>();
    if (!selectedTypeId) return map;
    for (const row of availability.data ?? []) {
      if (row.sponsorship_type_id === selectedTypeId) {
        map.set(row.on_date, row);
      }
    }
    return map;
  }, [availability.data, selectedTypeId]);

  const cells = useMemo<DayCell[]>(() => {
    if (!selectedType || !needsDate) return [];
    const total = daysInMonth(visibleMonth.year, visibleMonth.month);
    return Array.from({ length: total }, (_, index) => {
      const day = index + 1;
      const dateKey = dateKeyFor(visibleMonth.year, visibleMonth.month, day);
      const row = availabilityByDate.get(dateKey);
      // The server leaves out the days a sponsorship is not offered on, so a
      // missing row is "not offered" rather than "free". The Sunday test is
      // repeated here so a database that only has migration 0048 — where the
      // rule does not exist yet — still refuses a Sunday Feast on a Thursday.
      const sundayBlocked =
        Boolean(selectedType.sunday_only) && dateKeyWeekday(dateKey) !== 0;
      return {
        key: dateKey,
        day,
        dateKey,
        past: dateKey < todayKey,
        offered: Boolean(row) && !sundayBlocked,
        taken: Boolean(row?.is_taken),
        mine: Boolean(row?.is_mine),
      };
    });
  }, [
    availabilityByDate,
    needsDate,
    selectedType,
    todayKey,
    visibleMonth.month,
    visibleMonth.year,
  ]);

  /**
   * A hold the devotee already has, whether it was taken a moment ago on this
   * screen or half an hour ago before they walked away. The freshly held
   * booking wins because the list it would otherwise come from is still being
   * refetched.
   */
  const liveHold = useMemo<LiveHold | null>(() => {
    if (!selectedTypeId) return null;
    const held = (mySponsorships.data ?? []).filter(
      (row) =>
        row.sponsorship_type_id === selectedTypeId &&
        row.status === "held" &&
        row.held_until !== null &&
        new Date(row.held_until).getTime() > now.getTime(),
    );
    const preferred =
      held.find((row) => row.id === justHeldId) ?? held[0] ?? null;
    if (!preferred) return null;
    return {
      id: preferred.id,
      onDate: preferred.on_date,
      heldUntil: preferred.held_until,
      amountCents: preferred.amount_cents,
    };
  }, [justHeldId, mySponsorships.data, now, selectedTypeId]);

  const openPaymentPage = (type: SponsorshipType) => {
    if (!type.zeffy_campaign_url) return;
    openZeffyPage(type.zeffy_campaign_url, profile.data?.email).catch(
      (error: unknown) =>
        setActionError(
          errorMessage(error, "The payment page could not be opened."),
        ),
    );
  };

  const confirmHold = () => {
    if (!selectedType) return;
    setActionError(null);
    hold.mutate(
      {
        typeId: selectedType.id,
        // Null is the whole point for a sponsorship without a day: the server
        // decides whether that is allowed, and says so plainly if it is not.
        onDate: needsDate ? selectedDate : null,
      },
      {
        onSuccess: (booking) => {
          setJustHeldId(booking.id);
          setSelectedDate(null);
          openPaymentPage(selectedType);
        },
        onError: (error: unknown) =>
          setActionError(
            errorMessage(error, "That sponsorship could not be held."),
          ),
      },
    );
  };

  const confirmRelease = (bookingId: string) => {
    Alert.alert(
      "Give the date back?",
      "The day goes back on the calendar for anybody to sponsor. You can take it again if it is still free.",
      [
        { text: "Keep it", style: "cancel" },
        {
          text: "Give it back",
          style: "destructive",
          onPress: () => {
            setActionError(null);
            release.mutate(bookingId, {
              onSuccess: () => setJustHeldId(null),
              onError: (error: unknown) =>
                setActionError(
                  errorMessage(error, "That hold could not be released."),
                ),
            });
          },
        },
      ],
    );
  };

  const typesFailed = types.isError && types.data === undefined;
  const currentMonthIndex = monthIndex(templeToday.year, templeToday.month);
  const visibleIndex = monthIndex(visibleMonth.year, visibleMonth.month);
  const canGoBack = visibleIndex > currentMonthIndex;
  const canGoForward = visibleIndex < currentMonthIndex + MONTHS_AHEAD;
  const freeDaysThisMonth = cells.filter(
    (cell) => cell.offered && !cell.taken && !cell.past,
  ).length;

  const holdMinutesLeft = liveHold?.heldUntil
    ? Math.max(
        0,
        Math.ceil(
          (new Date(liveHold.heldUntil).getTime() - now.getTime()) / 60_000,
        ),
      )
    : 0;

  if (typesFailed) {
    return (
      <Screen topInset={false}>
        <ScreenTitle eyebrow="Sponsor a seva">Choose a sponsorship</ScreenTitle>
        <LoadFailure
          reachable={reachable}
          message={errorMessage(types.error, "")}
          onRetry={() => void types.refetch()}
        />
      </Screen>
    );
  }

  if (!selectedType) {
    return (
      <Screen topInset={false}>
        <ScreenTitle eyebrow="Sponsor a seva">Choose a sponsorship</ScreenTitle>
        <Text className="mb-section font-sans text-sm leading-6 text-stoneMuted">
          Each sponsorship is offered by one devotee on one day. Pick what you
          would like to offer, then the day.
        </Text>

        {types.isLoading ? (
          <View className="gap-3">
            {[0, 1, 2].map((slot) => (
              <View
                key={slot}
                className="rounded-card border border-border bg-white p-card"
              >
                <Skeleton height={16} width="52%" />
                <View className="mt-3">
                  <Skeleton height={44} />
                </View>
              </View>
            ))}
          </View>
        ) : activeTypes.length === 0 ? (
          <View className="items-center rounded-card border border-border bg-white px-card py-10">
            <View className="h-14 w-14 items-center justify-center rounded-pill bg-sandalwood">
              <Ionicons
                name="calendar-outline"
                size={26}
                color={tokens.colors.stone}
              />
            </View>
            <Text className="mt-4 text-center font-display text-xl text-stone">
              Nothing to sponsor yet
            </Text>
            <Text className="mt-2 max-w-80 text-center font-sans text-sm leading-6 text-stoneMuted">
              The temple has not opened its sponsorship calendar. A donation can
              still be given at any time.
            </Text>
          </View>
        ) : (
          groupIntoTiers(activeTypes).map((group) => (
            <TierGroupCard
              key={group.key}
              group={group}
              onChoose={(type) => {
                setActionError(null);
                setSelectedDate(null);
                setSelectedTypeId(type.id);
              }}
            />
          ))
        )}
      </Screen>
    );
  }

  return (
    <Screen topInset={false}>
      <ScreenTitle eyebrow="Sponsor a seva">{selectedType.name}</ScreenTitle>

      <View className="mb-section flex-row items-center justify-between rounded-card border border-border bg-white px-card py-3">
        <View className="min-w-0 flex-1 pr-3">
          <Text className="font-display text-2xl text-stone">
            {formatCents(selectedType.amount_cents)}
          </Text>
          {selectedType.sunday_only ? (
            <Text className="mt-0.5 font-sans text-xs text-stoneMuted">
              Offered on Sundays only
            </Text>
          ) : null}
        </View>
        <Pressable
          className="min-h-10 flex-row items-center rounded-pill bg-indigoSoft px-3"
          accessibilityRole="button"
          accessibilityLabel="Choose a different sponsorship"
          onPress={() => {
            setSelectedTypeId(null);
            setSelectedDate(null);
            setActionError(null);
          }}
        >
          <Text className="font-sans-bold text-sm text-indigo">Change</Text>
        </Pressable>
      </View>

      {liveHold ? (
        <View className="mb-section rounded-card border border-marigold bg-white p-card">
          <View className="flex-row items-center">
            <Ionicons
              name="time-outline"
              size={20}
              color={tokens.colors.marigold}
            />
            <Text className="ml-2 font-sans-bold text-base text-stone">
              Held for you
            </Text>
          </View>
          <Text className="mt-2 font-sans text-sm leading-6 text-stoneMuted">
            {liveHold.onDate
              ? `${formatSponsorshipDate(liveHold.onDate)} is yours while you pay. `
              : "This sponsorship is yours while you pay. "}
            {liveHold.heldUntil
              ? `Nobody else can take it until ${formatChicagoTime(
                  new Date(liveHold.heldUntil),
                )} ${getChicagoZoneAbbreviation(now)} — about ${holdMinutesLeft} minute${
                  holdMinutesLeft === 1 ? "" : "s"
                } from now. `
              : `Nobody else can take it for about ${SPONSORSHIP_HOLD_MINUTES} minutes. `}
            Finish the payment on Zeffy before then, and the sponsorship is
            confirmed as soon as the money reaches the temple.
          </Text>
          <View className="mt-4 gap-2">
            <Button
              icon="open-outline"
              onPress={() => openPaymentPage(selectedType)}
            >
              Open the payment page
            </Button>
            <Button
              variant="secondary"
              icon="close-circle-outline"
              disabled={release.isPending}
              onPress={() => confirmRelease(liveHold.id)}
            >
              {release.isPending ? "Releasing…" : "Give the date back"}
            </Button>
          </View>
        </View>
      ) : null}

      {!needsDate ? (
        <View className="rounded-card border border-border bg-white p-card">
          <SectionHeader title="No day to choose" />
          <Text className="font-sans text-sm leading-6 text-stoneMuted">
            The deity dress is not booked on a day. Several devotees may offer
            towards the same dressing, so there is no calendar here — offer what
            you wish and the temple records it against your name.
          </Text>
          {liveHold ? null : (
            <View className="mt-4">
              <Button
                icon="heart-outline"
                disabled={hold.isPending}
                onPress={confirmHold}
              >
                {hold.isPending
                  ? "Preparing…"
                  : `Sponsor for ${formatCents(selectedType.amount_cents)}`}
              </Button>
            </View>
          )}
        </View>
      ) : (
        <>
          <View className="mb-2 flex-row items-center justify-between">
            <Pressable
              className="h-11 w-11 items-center justify-center rounded-pill"
              accessibilityRole="button"
              accessibilityLabel="Previous month"
              accessibilityState={{ disabled: !canGoBack }}
              disabled={!canGoBack}
              onPress={() =>
                setVisibleMonth((current) =>
                  addMonths(current.year, current.month, -1),
                )
              }
            >
              <Ionicons
                name="chevron-back"
                size={22}
                color={
                  canGoBack ? tokens.colors.indigo : tokens.colors.border
                }
              />
            </Pressable>
            <Text
              className="font-sans-bold text-base text-stone"
              accessibilityRole="header"
            >
              {monthLabel(visibleMonth.year, visibleMonth.month)}
            </Text>
            <Pressable
              className="h-11 w-11 items-center justify-center rounded-pill"
              accessibilityRole="button"
              accessibilityLabel="Next month"
              accessibilityState={{ disabled: !canGoForward }}
              disabled={!canGoForward}
              onPress={() =>
                setVisibleMonth((current) =>
                  addMonths(current.year, current.month, 1),
                )
              }
            >
              <Ionicons
                name="chevron-forward"
                size={22}
                color={
                  canGoForward ? tokens.colors.indigo : tokens.colors.border
                }
              />
            </Pressable>
          </View>

          <View className="rounded-card border border-border bg-white p-2">
            {availability.isLoading ? (
              <View className="gap-1 p-1">
                {[0, 1, 2, 3, 4].map((slot) => (
                  <Skeleton key={slot} height={40} />
                ))}
              </View>
            ) : (
              <CalendarGrid
                cells={cells}
                leadingBlanks={firstWeekdayOfMonth(
                  visibleMonth.year,
                  visibleMonth.month,
                )}
                selectedDate={selectedDate}
                onSelect={(dateKey) => {
                  setActionError(null);
                  setSelectedDate((current) =>
                    current === dateKey ? null : dateKey,
                  );
                }}
              />
            )}
          </View>

          <View className="mt-3 flex-row flex-wrap gap-x-4 gap-y-2">
            <LegendDot boxClass="border-border bg-white" label="Free" />
            <LegendDot
              boxClass="border-border bg-sandalwood"
              label="Already sponsored"
            />
            <LegendDot boxClass="border-peacock bg-peacockSoft" label="Yours" />
          </View>

          {!availability.isLoading && freeDaysThisMonth === 0 ? (
            <Text className="mt-3 font-sans text-sm leading-5 text-stoneMuted">
              No days are open for this sponsorship in{" "}
              {monthLabel(visibleMonth.year, visibleMonth.month)}. Try the month
              ahead.
            </Text>
          ) : null}

          {selectedDate ? (
            <View className="mt-section rounded-card border border-indigo bg-white p-card">
              <Text className="font-sans-bold text-base text-stone">
                {formatSponsorshipDate(selectedDate)}
              </Text>
              <Text className="mt-1.5 font-sans text-sm leading-6 text-stoneMuted">
                {selectedType.name} for{" "}
                {formatCents(selectedType.amount_cents)}. The day is held for
                you for {SPONSORSHIP_HOLD_MINUTES} minutes while you pay on
                Zeffy, which opens in your browser.
              </Text>
              <View className="mt-4">
                <Button
                  icon="lock-closed-outline"
                  disabled={hold.isPending}
                  onPress={confirmHold}
                >
                  {hold.isPending ? "Holding the date…" : "Hold and pay"}
                </Button>
              </View>
            </View>
          ) : null}
        </>
      )}

      {actionError ? <FormError message={actionError} /> : null}

      <View className="mt-section">
        <Pressable
          className="min-h-touch flex-row items-center justify-center"
          accessibilityRole="button"
          accessibilityLabel="See my donations and sponsorships"
          onPress={() => navigation.navigate("MyDonations")}
        >
          <Text className="font-sans-bold text-sm text-indigo">
            See everything you have offered
          </Text>
          <Ionicons
            name="chevron-forward"
            size={16}
            color={tokens.colors.indigo}
          />
        </Pressable>
      </View>
    </Screen>
  );
}
