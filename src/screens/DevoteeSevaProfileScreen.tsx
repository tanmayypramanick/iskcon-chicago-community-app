import { Ionicons } from "@expo/vector-icons";
import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import { useMemo, useState } from "react";
import { Text, View } from "react-native";

import tokens from "../../design-tokens.json";
import {
  Avatar,
  EmptyOrOffline,
  LoadFailure,
  Screen,
  ScreenTitle,
  SectionHeader,
  Skeleton,
} from "../components/ui";
import { useCurrentAccessProfile } from "../features/access/hooks";
import { hasAccessPermission } from "../features/access/model";
import {
  useAllDonations,
  useDonationTotals,
} from "../features/donations/hooks";
import {
  formatCents,
  totalsByCurrency,
  type DonationTotal,
} from "../features/donations/types";
import {
  devoteeSevaRanges,
  num,
  sevaActsWindow,
  sevaRangeCaptions,
  sevaRangeEmpty,
  type SevaRange,
} from "../features/profile/sevaHours";
import {
  useDevoteeSevaActs,
  useDevoteeSevaBalance,
} from "../features/profile/sevaHoursApi";
import {
  SevaHoursFigure,
  SevaNameHoursList,
  SevaRangeSwitch,
} from "../features/profile/sevaHoursCard";
import { errorMessage } from "../features/services/format";
import {
  useAllSevaScores,
  useSevaConcentration,
} from "../features/sevayatra/hooks";
import {
  formatHours,
  formatSevaDate,
  formatSevaLongDate,
  sevaCountLabel,
} from "../features/sevayatra/types";
import { formatChicagoShortDate } from "../lib/chicagoDate";
import { useServerReachable } from "../lib/connectivity";
import type { DevoteesStackParamList } from "../navigation/types";
import { usePrototypeSession } from "../store/usePrototypeSession";

type Props = NativeStackScreenProps<
  DevoteesStackParamList,
  "DevoteeSevaProfile"
>;

/**
 * One devotee's whole service and giving, for the President and the Tech Admin.
 *
 * The temple asked for this behind a devotee's profile: seva summary, what they
 * serve, where one seva has taken over, their seva act by act, and their
 * giving. Every figure comes from an `app.view_all` function, so it is empty to
 * anybody else even if they reach it.
 *
 * A panel rather than a screen because the temple had four coordinator views of
 * one devotee's seva and Seva Care's was a fourth reading of the same two RPCs,
 * shorter and quietly different. Seva Care's route draws this instead, so the
 * two routes are two ways in to one answer rather than two answers.
 *
 * It is written as care, not as an audit. Nothing on it is shown to the devotee
 * it is about.
 */
export function DevoteeSevaProfilePanel({
  devoteeId,
  name,
  photoUrl,
}: {
  devoteeId: string;
  name: string;
  photoUrl?: string | null;
}) {
  const activeUserId = usePrototypeSession((state) => state.activeUserId);
  const viewer = useCurrentAccessProfile(activeUserId);
  const mayViewAll = hasAccessPermission(
    viewer.data?.role ?? "devotee",
    "app.view_all",
  );
  const reachable = useServerReachable();
  const [range, setRange] = useState<SevaRange>("month");
  const actsWindow = useMemo(() => sevaActsWindow(), []);

  const balance = useDevoteeSevaBalance(devoteeId, mayViewAll);
  const acts = useDevoteeSevaActs(devoteeId, mayViewAll);

  // This devotee's gifts, asked for as this devotee's: 0061 added the donor
  // filter and the server-side total precisely so a per-devotee view stops
  // reading the whole ledger and adding it up on the phone. The total is a
  // separate read because a sum over the rows in hand is the right answer only
  // until the day a page is truncated, and then it is quietly the wrong one.
  const donations = useAllDonations(null, null, mayViewAll, devoteeId);
  const givingTotals = useDonationTotals(null, null, devoteeId, mayViewAll);
  const scores = useAllSevaScores("lifetime", mayViewAll);
  const concentration = useSevaConcentration(mayViewAll);

  const rows = useMemo(() => balance.data ?? [], [balance.data]);

  /** The only act count the balance function publishes: the trailing quarter's. */
  const quarterActs = useMemo(
    () =>
      rows.reduce((total, row) => total + num(row.acts_trailing_quarter), 0),
    [rows],
  );

  /**
   * The four ranges the temple asked for. Week, month and all time are the
   * server's; the year is grouped from the act list, because `seva_mala_periods`
   * has no calendar year and calling the trailing quarter one would be a lie a
   * coordinator would then repeat to a devotee.
   */
  const ranges = useMemo(
    () => devoteeSevaRanges(rows, acts.data ?? [], actsWindow.yearStart),
    [rows, acts.data, actsWindow.yearStart],
  );
  const selected = ranges[range];
  /**
   * The year is the one range assembled from a second read, so it is the one
   * range that can be missing on its own. A zero standing in for an unread year
   * would be read as "they have not served since January".
   */
  const yearWaiting = range === "year" && acts.isLoading;
  const yearUnread =
    range === "year" && acts.isError && acts.data === undefined;

  const firstServed = useMemo(() => {
    let earliest: string | null = null;
    for (const row of rows) {
      if (!earliest || row.first_served_on < earliest)
        earliest = row.first_served_on;
    }
    return earliest;
  }, [rows]);

  // The server already orders these newest first; a screenful is what a
  // coordinator reads before a conversation, and the rest is a report's job.
  const recentActs = useMemo(() => (acts.data ?? []).slice(0, 8), [acts.data]);

  /**
   * `period_scores` counts the acts that earned points, which is the temple's
   * own answer to "how many times have they served" and the only all-time act
   * count exposed for another devotee. It is a nightly recompute, so a seva
   * served this morning reaches the hours above before it reaches this number.
   */
  const lifetime = useMemo(
    () => scores.data?.find((row) => row.devotee_id === devoteeId) ?? null,
    [scores.data, devoteeId],
  );

  const top = rows[0] ?? null;
  /**
   * The care list's own sentence about this devotee, when they are on it. It is
   * written by the server for a coordinator to read and act on, so it is shown
   * as it arrives rather than restated in wording of our own.
   */
  const concentrationNote = useMemo(
    () =>
      concentration.data?.find(
        (row) =>
          row.devotee_id === devoteeId &&
          (row.service_type_id ?? row.seva_name) ===
            (top?.service_type_id ?? top?.seva_name),
      )?.note ?? null,
    [concentration.data, devoteeId, top],
  );

  /**
   * What they have given.
   *
   * A donation row means money was received. A sponsorship later released or
   * cancelled gave back a DATE, not the gift: no money moved, the temple is
   * holding the same dollars, and a total that dropped it would not reconcile
   * against Zeffy. So every gift is counted, and the ones attached to a date
   * that came back are named underneath rather than deducted.
   *
   * `donation_totals` is one row per currency and there is no argument that
   * collapses them, so nothing here adds across currencies either. The client
   * sum is only a fallback for a database still behind on 0061 — same shape,
   * same rule, so the screen reads identically.
   */
  const giving = useMemo(() => {
    const gifts = donations.data ?? [];
    const totals: DonationTotal[] = givingTotals.data?.length
      ? givingTotals.data
      : totalsByCurrency(gifts).map((total) => ({
          currency: total.currency,
          total_cents: total.cents,
          gifts: total.count,
        }));
    const counted = totals.reduce((sum, total) => sum + total.gifts, 0);
    const lapsed = gifts.filter(
      (gift) =>
        gift.booking_status === "released" ||
        gift.booking_status === "cancelled",
    ).length;
    return { gifts, totals, counted, lapsed };
  }, [donations.data, givingTotals.data]);

  if (!mayViewAll) {
    return (
      <View className="rounded-card border border-border bg-white px-card py-6">
        <Text className="text-center font-sans text-sm leading-6 text-stoneMuted">
          Only the President and a Tech Admin can open this.
        </Text>
      </View>
    );
  }

  const sevaFailed = balance.isError && balance.data === undefined;
  // The list is what the section is: a total that could not be read falls back
  // to the rows, but rows that could not be read leave nothing honest to show.
  const givingFailed = donations.isError && donations.data === undefined;
  const givingLoading = donations.isLoading;
  const topShare = num(top?.share_of_their_seva);

  return (
    <>
      <View className="flex-row items-center rounded-card border border-border bg-white px-card py-4">
        <Avatar name={name} photoUrl={photoUrl} size="medium" tone="peacock" />
        <Text className="ml-3 min-w-0 flex-1 font-sans text-sm leading-5 text-stoneMuted">
          Their service and giving, in full. Nothing here is shown to them, and
          it is here for a conversation rather than a record.
        </Text>
      </View>

      {sevaFailed ? (
        <View className="mt-section">
          <LoadFailure
            reachable={reachable}
            message={errorMessage(balance.error, "")}
            onRetry={() => void balance.refetch()}
          />
        </View>
      ) : rows.length === 0 ? (
        <View className="mt-section">
          <EmptyOrOffline
            reachable={reachable}
            loading={balance.isLoading}
            loadingLabel="Reading their seva…"
            empty={
              <View className="items-center rounded-card border border-border bg-white px-card py-9">
                <View className="h-14 w-14 items-center justify-center rounded-pill bg-peacockSoft">
                  <Ionicons
                    name="leaf-outline"
                    size={26}
                    color={tokens.colors.peacock}
                  />
                </View>
                <Text className="mt-4 text-center font-display text-xl text-stone">
                  No seva recorded yet
                </Text>
                <Text className="mt-2 max-w-80 text-center font-sans text-sm leading-6 text-stoneMuted">
                  They have not served a seva the temple has closed. A first
                  invitation is usually the way in.
                </Text>
              </View>
            }
          />
        </View>
      ) : (
        <>
          <View className="mt-section">
            <SectionHeader
              title="Hours of seva"
              subtitle="Which sevas, and how many hours of each."
            />
            <View className="rounded-card border border-border bg-white px-card py-4">
              <SevaRangeSwitch
                value={range}
                onChange={setRange}
                subject="their seva"
              />

              <View className="mt-4">
                {yearUnread ? (
                  // A read that failed is not a devotee who served nothing.
                  <Text className="font-sans text-base leading-10 text-stoneMuted">
                    This year could not be read
                  </Text>
                ) : yearWaiting ? (
                  <Skeleton height={40} width="60%" />
                ) : (
                  <SevaHoursFigure
                    hours={selected.hours}
                    caption={
                      selected.acts > 0
                        ? `${sevaRangeCaptions[range]} · ${sevaCountLabel(selected.acts, "act")}`
                        : sevaRangeCaptions[range]
                    }
                  />
                )}
              </View>

              {yearUnread || yearWaiting ? null : (
                <View className="mt-4 border-t border-border pt-3.5">
                  <SevaNameHoursList
                    totals={selected}
                    empty={sevaRangeEmpty[range]}
                    withBars
                  />
                </View>
              )}

              <Text className="mt-3.5 border-t border-border pt-3 font-sans text-sm leading-5 text-stoneMuted">
                {lifetime
                  ? `${sevaCountLabel(lifetime.seva_acts, "act")} of seva all told`
                  : `${sevaCountLabel(quarterActs, "act")} in the last 13 weeks`}
                {firstServed
                  ? ` · serving since ${formatSevaLongDate(firstServed)}`
                  : ""}
              </Text>
            </View>
          </View>

          {top ? (
            <View className="mt-section rounded-card border border-peacock bg-peacockSoft px-card py-4">
              <Text className="font-sans-bold text-[11px] uppercase tracking-widest text-peacock">
                {topShare >= 0.5 ? "Mostly one seva" : "What they carry most"}
              </Text>
              <Text
                className="mt-1 font-display text-2xl leading-8 text-stone"
                numberOfLines={2}
              >
                {top.seva_name}
              </Text>
              <Text className="mt-1.5 font-sans text-sm leading-6 text-stone">
                {concentrationNote ??
                  (topShare > 0
                    ? `${Math.round(topShare * 100)}% of their seva over the last 13 weeks${
                        top.consecutive_weeks > 0
                          ? `, ${sevaCountLabel(top.consecutive_weeks, "week")} running`
                          : ""
                      }.`
                    : "Their most-served seva, though they have not served it this quarter.")}
              </Text>
              {topShare >= 0.5 ? (
                <Text className="mt-2 font-sans text-sm leading-6 text-stone">
                  Worth asking how they are finding it before the next rota is
                  drawn. Nobody has done anything wrong.
                </Text>
              ) : null}
              <Text className="mt-2.5 font-sans text-xs leading-4 text-stoneMuted">
                Since {formatSevaLongDate(top.first_served_on)} · last served{" "}
                {formatSevaDate(top.last_served_on)}
              </Text>
            </View>
          ) : null}

          <View className="mt-section">
            <SectionHeader
              title="Seva history"
              subtitle={`Act by act, since ${formatSevaLongDate(actsWindow.from)}.`}
            />
            {acts.isError && acts.data === undefined ? (
              <LoadFailure
                reachable={reachable}
                message={errorMessage(acts.error, "")}
                onRetry={() => void acts.refetch()}
              />
            ) : acts.isLoading ? (
              <View className="gap-2 rounded-card border border-border bg-white px-card py-5">
                <Skeleton height={14} width="52%" />
                <Skeleton height={14} width="40%" />
              </View>
            ) : recentActs.length === 0 ? (
              <View className="rounded-card border border-border bg-white px-card py-6">
                <Text className="text-center font-sans text-sm leading-6 text-stoneMuted">
                  Nothing since {formatSevaLongDate(actsWindow.from)}. Their
                  all-time hours above go further back than this list does.
                </Text>
              </View>
            ) : (
              <View className="rounded-card border border-border bg-white px-card">
                {recentActs.map((act, index) => (
                  <View
                    key={act.assignment_id}
                    className={`py-3 ${index ? "border-t border-border" : ""}`}
                  >
                    <View className="flex-row items-baseline">
                      <Text className="w-[92px] flex-shrink-0 font-sans-bold text-xs text-stoneMuted">
                        {formatSevaDate(act.occurred_on)}
                      </Text>
                      <Text
                        className="min-w-0 flex-1 pr-3 font-sans text-sm text-stone"
                        numberOfLines={1}
                      >
                        {act.seva_name}
                      </Text>
                      <Text className="flex-shrink-0 font-sans-bold text-sm text-stone">
                        {formatHours(num(act.hours))}
                      </Text>
                    </View>
                    {/* The server writes this note for exactly this question —
                        why an act has not counted, and who has to do what next
                        — so it is shown as it arrives. */}
                    {act.points_status !== "counted" && act.points_note ? (
                      <Text className="ml-[92px] mt-1 font-sans text-xs leading-4 text-stoneMuted">
                        {act.points_note}
                      </Text>
                    ) : null}
                  </View>
                ))}
                {(acts.data?.length ?? 0) > recentActs.length ? (
                  <Text className="border-t border-border py-3 font-sans text-xs text-stoneMuted">
                    {sevaCountLabel(
                      (acts.data?.length ?? 0) - recentActs.length,
                      "earlier act",
                    )}{" "}
                    in the window, not shown.
                  </Text>
                ) : null}
              </View>
            )}
          </View>
        </>
      )}

      <View className="mt-section">
        <SectionHeader title="Giving" />
        {givingFailed ? (
          <LoadFailure
            reachable={reachable}
            message={errorMessage(donations.error, "")}
            onRetry={() => {
              void donations.refetch();
              void givingTotals.refetch();
            }}
          />
        ) : givingLoading ? (
          <View className="gap-2 rounded-card border border-border bg-white px-card py-5">
            <Skeleton height={14} width="38%" />
            <Skeleton height={28} width="55%" />
          </View>
        ) : giving.gifts.length === 0 ? (
          <View className="items-center rounded-card border border-border bg-white px-card py-8">
            <Text className="text-center font-sans text-sm leading-6 text-stoneMuted">
              No gift has been recorded against their name.
            </Text>
          </View>
        ) : (
          <View className="rounded-card border border-border bg-white px-card py-4">
            <Text className="font-sans-bold text-[11px] uppercase tracking-widest text-stoneMuted">
              Given all told
            </Text>
            {/* One figure per currency, stacked. This temple settles in USD and
                the normal answer is a single line; two are two units, and
                adding them would be arithmetic on unlike things. */}
            {giving.totals.map((total) => (
              <Text
                key={total.currency}
                className="mt-1 font-display text-3xl leading-10 text-stone"
              >
                {formatCents(total.total_cents, total.currency)}
              </Text>
            ))}
            <Text className="mt-0.5 font-sans text-sm text-stoneMuted">
              {sevaCountLabel(giving.counted, "gift")}
            </Text>

            <View className="mt-3 border-t border-border">
              {giving.gifts.slice(0, 4).map((gift) => (
                <View key={gift.id} className="flex-row items-baseline pt-3">
                  <View className="min-w-0 flex-1 pr-3">
                    <Text className="font-sans text-sm text-stone">
                      {formatChicagoShortDate(new Date(gift.received_at))}
                    </Text>
                    {gift.sponsorship_type_name ? (
                      <Text
                        className="mt-0.5 font-sans text-xs text-stoneMuted"
                        numberOfLines={1}
                      >
                        {gift.sponsorship_type_name}
                      </Text>
                    ) : null}
                  </View>
                  <Text className="flex-shrink-0 font-sans-bold text-base text-stone">
                    {formatCents(gift.amount_cents, gift.currency)}
                  </Text>
                </View>
              ))}
            </View>

            {giving.lapsed > 0 ? (
              <Text className="mt-3 border-t border-border pt-3 font-sans text-xs leading-4 text-stoneMuted">
                {sevaCountLabel(giving.lapsed, "gift")} here paid for a
                sponsorship whose date was later given back. The date came back,
                the money did not, so{" "}
                {giving.lapsed === 1 ? "it is" : "they are"} counted — worth a
                word with them rather than a correction.
              </Text>
            ) : null}
          </View>
        )}
      </View>
    </>
  );
}

/** The panel as the Devotees tab's own screen, off a devotee's profile. */
export function DevoteeSevaProfileScreen({ route }: Props) {
  const { devoteeId, name, photoUrl } = route.params;
  return (
    <Screen topInset={false}>
      <ScreenTitle eyebrow="Seva profile">{name}</ScreenTitle>
      <DevoteeSevaProfilePanel
        devoteeId={devoteeId}
        name={name}
        photoUrl={photoUrl}
      />
    </Screen>
  );
}
