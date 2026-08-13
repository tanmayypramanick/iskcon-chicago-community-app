import { Ionicons } from "@expo/vector-icons";
import { useMemo } from "react";
import { Text, View } from "react-native";

import tokens from "../../design-tokens.json";
import {
  EmptyOrOffline,
  ListScreen,
  LoadFailure,
  ScreenTitle,
  SectionHeader,
} from "../components/ui";
import {
  useMyDonations,
  useMySponsorships,
} from "../features/donations/hooks";
import {
  donationKindLabel,
  formatCents,
  formatSponsorshipDate,
  partitionSponsorships,
  totalsByCurrency,
  type MyDonation,
  type MySponsorship,
} from "../features/donations/types";
import { errorMessage } from "../features/services/format";
import { formatChicagoShortDate } from "../lib/chicagoDate";
import { useServerReachable } from "../lib/connectivity";
import { useNow } from "../lib/useNow";
import { usePrototypeSession } from "../store/usePrototypeSession";

/**
 * A devotee's record of giving — and only of giving.
 *
 * A sponsorship booking is a date taken off the calendar while the devotee goes
 * to Zeffy to pay. Most are paid for and become `confirmed`; the rest lapse,
 * are released, or are cancelled, and the date goes back. Those last three are
 * not gifts, and this screen once listed all four side by side with the amount
 * set in the same display type as a received donation — so a devotee who
 * reserved the Sunday Feast twice and paid once read their history as $1,102.
 *
 * So: `confirmed` sponsorships and received donations are giving. A live hold
 * is shown apart, in words that say it is not money yet, because a devotee
 * halfway through paying needs to find it. Anything lapsed is not shown at all.
 */
type GivingItem =
  | { key: string; kind: "heading"; title: string; subtitle?: string }
  | { key: string; kind: "sponsorship"; row: MySponsorship }
  | { key: string; kind: "reserved"; row: MySponsorship }
  | { key: string; kind: "donation"; row: MyDonation };

function SponsorshipRow({ row }: { row: MySponsorship }) {
  return (
    <View className="mb-3 rounded-card border border-border bg-white p-card">
      <View className="flex-row items-start justify-between">
        <View className="min-w-0 flex-1 pr-3">
          <Text className="font-sans-bold text-base text-stone">
            {row.type_name}
          </Text>
          <Text className="mt-0.5 font-sans text-sm text-stoneMuted">
            {row.on_date
              ? formatSponsorshipDate(row.on_date)
              : "No date — offered towards the deity dress"}
          </Text>
        </View>
        <View className="rounded-pill bg-peacockSoft px-2.5 py-1">
          <Text className="font-sans-bold text-[11px] text-peacock">
            Sponsored
          </Text>
        </View>
      </View>
      <View className="mt-3 flex-row flex-wrap items-center justify-between gap-y-1">
        <Text className="font-display text-xl text-stone">
          {formatCents(row.amount_cents)}
        </Text>
        {row.donation_id ? null : (
          <Text className="font-sans text-xs text-stoneMuted">
            Payment being matched
          </Text>
        )}
      </View>

      {/* A dress is offered when it is ready. Without this the devotee would
          pay and never hear of it again. */}
      {row.fulfilled_on ? (
        <View className="mt-3 flex-row items-start rounded-button bg-peacockSoft px-3 py-2">
          <Ionicons
            name="checkmark-circle-outline"
            size={15}
            color={tokens.colors.peacock}
          />
          <Text className="ml-2 min-w-0 flex-1 font-sans text-xs leading-4 text-peacock">
            Offered on {formatSponsorshipDate(row.fulfilled_on)}
            {row.fulfilment_note ? ` — ${row.fulfilment_note}` : ""}
          </Text>
        </View>
      ) : !row.on_date ? (
        <Text className="mt-2 font-sans text-xs leading-4 text-stoneMuted">
          The temple will tell you the day it is offered.
        </Text>
      ) : null}
    </View>
  );
}

/**
 * A date held while the devotee pays. Deliberately unlike a gift: no card of
 * its own colour, no display type on the amount, and the figure is named as
 * what it would cost rather than what was given.
 */
function ReservedRow({ row }: { row: MySponsorship }) {
  return (
    <View className="mb-3 rounded-card border border-border bg-ivory p-card">
      <View className="flex-row items-start justify-between">
        <View className="min-w-0 flex-1 pr-3">
          <Text className="font-sans-bold text-base text-stone">
            {row.type_name}
          </Text>
          <Text className="mt-0.5 font-sans text-sm text-stoneMuted">
            {row.on_date
              ? formatSponsorshipDate(row.on_date)
              : "No date — offered towards the deity dress"}
          </Text>
        </View>
        <View className="rounded-pill bg-marigoldSoft px-2.5 py-1">
          <Text className="font-sans-bold text-[11px] text-stone">
            Awaiting payment
          </Text>
        </View>
      </View>
      <Text className="mt-2.5 font-sans text-sm text-stoneMuted">
        {formatCents(row.amount_cents)} when you pay. Nothing has been taken
        yet, and this is not counted in your giving.
      </Text>
    </View>
  );
}

function DonationRow({ row }: { row: MyDonation }) {
  const receivedAt = new Date(row.received_at);
  const pendingMatch = row.match_status === "unmatched";
  const mismatched = row.amount_matches === false;

  return (
    <View className="mb-3 rounded-card border border-border bg-white p-card">
      <View className="flex-row items-start justify-between">
        <View className="min-w-0 flex-1 pr-3">
          <Text className="font-display text-2xl text-stone">
            {formatCents(row.amount_cents, row.currency)}
          </Text>
          <Text className="mt-0.5 font-sans text-sm text-stoneMuted">
            {donationKindLabel(row)}
          </Text>
        </View>
        <Text className="font-sans text-xs text-stoneMuted">
          {formatChicagoShortDate(receivedAt)}
        </Text>
      </View>

      {row.sponsorship_type_name ? (
        <View className="mt-3 flex-row items-center rounded-button bg-ivory px-3 py-2">
          <Ionicons
            name="calendar-outline"
            size={15}
            color={tokens.colors.peacock}
          />
          <Text className="ml-2 min-w-0 flex-1 font-sans text-xs leading-4 text-stoneMuted">
            {row.sponsorship_type_name}
            {row.sponsorship_on_date
              ? ` — ${formatSponsorshipDate(row.sponsorship_on_date)}`
              : ""}
          </Text>
        </View>
      ) : null}

      {mismatched && row.expected_amount_cents != null ? (
        <Text className="mt-2 font-sans text-xs leading-4 text-vermilion">
          The sponsorship was {formatCents(row.expected_amount_cents)}. The
          temple has both figures and will be in touch.
        </Text>
      ) : null}

      {pendingMatch ? (
        <Text className="mt-2 font-sans text-xs leading-4 text-stoneMuted">
          Received. The temple is still tying this to the sponsorship you
          booked.
        </Text>
      ) : null}
    </View>
  );
}

/**
 * Everything this devotee has offered. Nothing here is anybody else's: both
 * calls behind it return only the caller's own rows, whatever their role.
 */
export function MyDonationsScreen() {
  const activeUserId = usePrototypeSession((state) => state.activeUserId);
  const reachable = useServerReachable();
  // A hold runs out on the clock rather than on any change to the data, so the
  // screen needs a clock of its own to stop showing an expired one as live.
  const now = useNow(60_000);

  const donations = useMyDonations(activeUserId);
  const sponsorships = useMySponsorships(activeUserId);

  const donationRows = useMemo(() => donations.data ?? [], [donations.data]);
  const sponsorshipRows = sponsorships.data;

  const loading = donations.isLoading || sponsorships.isLoading;
  const failed =
    (donations.isError && donations.data === undefined) ||
    (sponsorships.isError && sponsorships.data === undefined);

  // Released and cancelled bookings fall out here and are never referred to
  // again — not in a list, not in a count, not in a total.
  const { given, reserved } = useMemo(
    () => partitionSponsorships(sponsorshipRows ?? [], now),
    [now, sponsorshipRows],
  );

  /**
   * The figure that has to agree with Zeffy. Donations only — a booking is a
   * promise, and a confirmed booking's money is already in this list as the
   * donation that confirmed it, so adding bookings would count it twice.
   */
  const received = useMemo(
    () => totalsByCurrency(donationRows),
    [donationRows],
  );
  const [primaryTotal, ...otherTotals] = received;

  const items: GivingItem[] = [
    ...(given.length
      ? [
          {
            key: "heading-sponsorships",
            kind: "heading" as const,
            title: "Sponsorships",
            subtitle: "The days the temple has recorded as yours",
          },
          ...given.map((row) => ({
            key: `sponsorship-${row.id}`,
            kind: "sponsorship" as const,
            row,
          })),
        ]
      : []),
    ...(donationRows.length
      ? [
          {
            key: "heading-donations",
            kind: "heading" as const,
            title: "Donations",
            subtitle: "Every gift the temple has received from you",
          },
          ...donationRows.map((row) => ({
            key: `donation-${row.id}`,
            kind: "donation" as const,
            row,
          })),
        ]
      : []),
    ...(reserved.length
      ? [
          {
            key: "heading-reserved",
            kind: "heading" as const,
            title: "Waiting to be paid",
            subtitle: "Dates you are holding. Not part of your giving yet.",
          },
          ...reserved.map((row) => ({
            key: `reserved-${row.id}`,
            kind: "reserved" as const,
            row,
          })),
        ]
      : []),
  ];

  return (
    <ListScreen
      topInset={false}
      data={items}
      keyExtractor={(item) => item.key}
      header={
        <>
          <ScreenTitle eyebrow="Your giving">
            Donations and sponsorships
          </ScreenTitle>
          {primaryTotal ? (
            <View className="mb-section rounded-card border border-border bg-white px-card py-4">
              <Text className="font-sans-bold text-xs uppercase tracking-widest text-peacock">
                Received by the temple
              </Text>
              <Text className="mt-1 font-display text-[28px] leading-9 text-stone">
                {formatCents(primaryTotal.cents, primaryTotal.currency)}
              </Text>
              <Text className="mt-0.5 font-sans text-xs leading-4 text-stoneMuted">
                Across {primaryTotal.count} gift
                {primaryTotal.count === 1 ? "" : "s"}
              </Text>
              {otherTotals.map((total) => (
                <Text
                  key={total.currency}
                  className="mt-1 font-sans-bold text-sm text-stone"
                >
                  {formatCents(total.cents, total.currency)} across{" "}
                  {total.count} gift{total.count === 1 ? "" : "s"}
                </Text>
              ))}
              {reserved.length ? (
                <Text className="mt-2 font-sans text-xs leading-4 text-stoneMuted">
                  A date you are holding is not counted here until the payment
                  reaches the temple.
                </Text>
              ) : null}
            </View>
          ) : null}
          {failed ? (
            <View className="mb-section">
              <LoadFailure
                reachable={reachable}
                message={errorMessage(donations.error ?? sponsorships.error, "")}
                onRetry={() => {
                  void donations.refetch();
                  void sponsorships.refetch();
                }}
              />
            </View>
          ) : null}
        </>
      }
      renderItem={(item) => {
        if (item.kind === "heading") {
          return (
            <SectionHeader title={item.title} subtitle={item.subtitle} />
          );
        }
        if (item.kind === "sponsorship") {
          return <SponsorshipRow row={item.row} />;
        }
        if (item.kind === "reserved") {
          return <ReservedRow row={item.row} />;
        }
        return <DonationRow row={item.row} />;
      }}
      empty={
        failed ? null : (
          <EmptyOrOffline
            reachable={reachable}
            loading={loading}
            loadingLabel="Looking up your giving…"
            empty={
              <View className="items-center rounded-card border border-border bg-white px-card py-10">
                <View className="h-14 w-14 items-center justify-center rounded-pill bg-marigoldSoft">
                  <Ionicons
                    name="gift-outline"
                    size={26}
                    color={tokens.colors.stone}
                  />
                </View>
                <Text className="mt-4 text-center font-display text-xl text-stone">
                  Nothing here yet
                </Text>
                <Text className="mt-2 max-w-80 text-center font-sans text-sm leading-6 text-stoneMuted">
                  Whatever you offer — a donation or a sponsored seva — will
                  appear here as soon as the temple receives it.
                </Text>
              </View>
            }
          />
        )
      }
    />
  );
}
