import { Ionicons } from "@expo/vector-icons";
import { useMemo, useState } from "react";
import { Alert, Pressable, Text, View } from "react-native";

import tokens from "../../design-tokens.json";
import {
  EmptyOrOffline,
  ListScreen,
  LoadFailure,
  ScreenTitle,
} from "../components/ui";
import { useCurrentAccessProfile } from "../features/access/hooks";
import { hasAccessPermission } from "../features/access/model";
import {
  useAllDonations,
  useAllSponsorships,
  useAttachDonationToBooking,
  useUnmatchedDonations,
} from "../features/donations/hooks";
import {
  donationKindLabel,
  formatCents,
  formatSponsorshipDate,
  formatSponsorshipShortDate,
  lapsedSponsorshipLabel,
  partitionSponsorships,
  sponsorshipStatusLabels,
  totalsByCurrency,
  unmatchedReasonLabels,
  type AllDonation,
  type AllSponsorship,
  type SponsorshipStanding,
  type UnmatchedDonation,
} from "../features/donations/types";
import { FormError } from "../features/services/components";
import { errorMessage } from "../features/services/format";
import {
  addChicagoDays,
  formatChicagoShortDate,
  getChicagoDateKey,
  getChicagoWallClock,
} from "../lib/chicagoDate";
import { useServerReachable } from "../lib/connectivity";
import { useNow } from "../lib/useNow";
import { usePrototypeSession } from "../store/usePrototypeSession";

type Face = "donations" | "sponsorships" | "queue";
type Period = "month" | "days30" | "year" | "all";

const faces: Array<{ key: Face; label: string }> = [
  { key: "donations", label: "Donations" },
  { key: "sponsorships", label: "Sponsorships" },
  { key: "queue", label: "To settle" },
];

const periods: Array<{ key: Period; label: string }> = [
  { key: "month", label: "This month" },
  { key: "days30", label: "Last 30 days" },
  { key: "year", label: "This year" },
  { key: "all", label: "All time" },
];

/**
 * The sponsorship face defaults to `given` so that the President's record of
 * giving is the same set of bookings a devotee sees in My Donations — the
 * temple asked for the two views to agree. The other two are reachable because
 * a lapsed booking is exactly what somebody has to look at when Zeffy's figure
 * and the calendar disagree, but they are never presented as gifts.
 */
const standings: Array<{ key: SponsorshipStanding; label: string }> = [
  { key: "given", label: "Sponsored" },
  { key: "reserved", label: "Awaiting payment" },
  { key: "lapsed", label: "Given back" },
];

/**
 * The window, in temple dates. `list_all_donations` compares them against
 * Chicago dates too, so a gift received at 7pm on the 31st falls in that
 * month's total — which it would not if either side used UTC.
 */
function periodRange(period: Period, now: Date) {
  if (period === "all") return { from: null, to: null };
  const today = getChicagoDateKey(now);
  const { year, month } = getChicagoWallClock(now);
  if (period === "month") {
    return { from: `${year}-${String(month).padStart(2, "0")}-01`, to: today };
  }
  if (period === "year") return { from: `${year}-01-01`, to: today };
  return { from: addChicagoDays(-29, now), to: today };
}

function Pill({
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
      className={`min-h-10 items-center justify-center rounded-pill border px-3 ${
        selected ? "border-indigo bg-indigo" : "border-border bg-white"
      }`}
      accessibilityRole="button"
      accessibilityState={{ selected }}
      accessibilityLabel={label}
      onPress={onPress}
    >
      <Text
        className={`font-sans-bold text-xs ${selected ? "text-white" : "text-stone"}`}
      >
        {label}
      </Text>
    </Pressable>
  );
}

function donorLabel(row: { donor_name: string | null; donor_email: string | null }) {
  return row.donor_name?.trim() || row.donor_email?.trim() || "Donor unknown";
}

/**
 * The temple asked for one thing above everything else: that Zeffy's figure and
 * the temple's expectation are both on the screen and agree. When they do not,
 * the row says so in words and in numbers rather than quietly showing one of
 * them.
 */
function AmountDiscrepancy({
  amountCents,
  expectedCents,
  differenceCents,
  currency,
}: {
  amountCents: number;
  expectedCents: number;
  differenceCents: number | null | undefined;
  currency: string;
}) {
  const difference = differenceCents ?? amountCents - expectedCents;
  const short = difference < 0;
  return (
    <View className="mt-3 rounded-button border border-vermilion bg-white px-3 py-2.5">
      <View className="flex-row items-center">
        <Ionicons
          name="alert-circle-outline"
          size={15}
          color={tokens.colors.vermilion}
        />
        <Text className="ml-2 font-sans-bold text-xs text-vermilion">
          {short ? "Short by" : "Over by"} {formatCents(Math.abs(difference))}
        </Text>
      </View>
      <Text className="mt-1 font-sans text-xs leading-4 text-stoneMuted">
        Zeffy took {formatCents(amountCents, currency)}; the temple expected{" "}
        {formatCents(expectedCents)}.
      </Text>
    </View>
  );
}

function DonationRow({ row }: { row: AllDonation }) {
  const mismatched =
    row.amount_matches === false && row.expected_amount_cents != null;

  return (
    <View className="mb-3 rounded-card border border-border bg-white p-card">
      <View className="flex-row items-start justify-between">
        <View className="min-w-0 flex-1 pr-3">
          <Text className="font-sans-bold text-base text-stone" numberOfLines={1}>
            {donorLabel(row)}
          </Text>
          <Text className="mt-0.5 font-sans text-xs text-stoneMuted">
            {donationKindLabel(row)}
          </Text>
        </View>
        <View className="items-end">
          <Text className="font-display text-xl text-stone">
            {formatCents(row.amount_cents, row.currency)}
          </Text>
          <Text className="mt-0.5 font-sans text-xs text-stoneMuted">
            {formatChicagoShortDate(new Date(row.received_at))}
          </Text>
        </View>
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
              ? ` — ${formatSponsorshipShortDate(row.sponsorship_on_date)}`
              : ""}
          </Text>
        </View>
      ) : null}

      {mismatched ? (
        <AmountDiscrepancy
          amountCents={row.amount_cents}
          expectedCents={row.expected_amount_cents as number}
          differenceCents={row.amount_difference_cents}
          currency={row.currency}
        />
      ) : null}
    </View>
  );
}

/**
 * Only a `given` booking is money. A reserved or lapsed one keeps the amount
 * out of the display type and names it as what it would have been, so that
 * nothing on this screen can be read off as a figure to reconcile against
 * Zeffy — the donations face is the only place a total belongs.
 */
function SponsorshipRow({
  row,
  standing,
}: {
  row: AllSponsorship;
  standing: SponsorshipStanding;
}) {
  const given = standing === "given";
  const label =
    standing === "lapsed"
      ? lapsedSponsorshipLabel(row)
      : standing === "reserved"
        ? "Awaiting payment"
        : sponsorshipStatusLabels.confirmed;

  return (
    <View
      className={`mb-3 rounded-card border border-border p-card ${
        given ? "bg-white" : "bg-ivory"
      }`}
    >
      <View className="flex-row items-start justify-between">
        <View className="min-w-0 flex-1 pr-3">
          <Text className="font-sans-bold text-base text-stone">
            {row.type_name}
          </Text>
          <Text className="mt-0.5 font-sans text-sm text-stoneMuted">
            {row.on_date ? formatSponsorshipDate(row.on_date) : "No date"}
          </Text>
          <Text className="mt-1 font-sans text-xs text-stoneMuted" numberOfLines={1}>
            {row.devotee_name?.trim() || row.devotee_email?.trim() || "Unknown devotee"}
          </Text>
        </View>
        <View className="items-end">
          <Text
            className={
              given
                ? "font-display text-xl text-stone"
                : "font-sans-bold text-sm text-stoneMuted"
            }
          >
            {formatCents(row.amount_cents)}
          </Text>
          <Text className="mt-1 font-sans text-xs text-stoneMuted">{label}</Text>
        </View>
      </View>

      {given && !row.donation_id ? (
        <Text className="mt-2 font-sans text-xs leading-4 text-vermilion">
          Confirmed with no payment attached.
        </Text>
      ) : null}

      {/* A released booking never had money against it; a cancelled one
          usually did, and that money is still the temple's to answer for. */}
      {standing === "lapsed" ? (
        <Text
          className={`mt-2 font-sans text-xs leading-4 ${
            row.donation_id ? "text-vermilion" : "text-stoneMuted"
          }`}
        >
          {row.donation_id
            ? "Given back with a payment attached. The money is in the donations list, not here."
            : "The date went back on the calendar. Nothing was received for it."}
        </Text>
      ) : null}

      {row.fulfilled_on ? (
        <Text className="mt-2 font-sans text-xs leading-4 text-peacock">
          Offered on {formatSponsorshipShortDate(row.fulfilled_on)}
          {row.fulfilment_note ? ` — ${row.fulfilment_note}` : ""}
        </Text>
      ) : null}
    </View>
  );
}

function QueueRow({
  row,
  busy,
  onAttach,
}: {
  row: UnmatchedDonation;
  busy: boolean;
  onAttach: (donationId: string, bookingId: string) => void;
}) {
  return (
    <View className="mb-3 rounded-card border border-border bg-white p-card">
      <View className="flex-row items-start justify-between">
        <View className="min-w-0 flex-1 pr-3">
          <Text className="font-sans-bold text-base text-stone" numberOfLines={1}>
            {donorLabel(row)}
          </Text>
          <Text className="mt-0.5 font-sans text-xs text-stoneMuted">
            {formatChicagoShortDate(new Date(row.received_at))} · Zeffy{" "}
            {row.external_payment_id}
          </Text>
        </View>
        <Text className="font-display text-xl text-stone">
          {formatCents(row.amount_cents, row.currency)}
        </Text>
      </View>

      {row.unmatched_reason ? (
        <View className="mt-3 rounded-button bg-marigoldSoft px-3 py-2">
          <Text className="font-sans-bold text-xs text-stone">
            {unmatchedReasonLabels[row.unmatched_reason]}
          </Text>
        </View>
      ) : null}

      {row.expected_amount_cents != null && row.amount_matches === false ? (
        <AmountDiscrepancy
          amountCents={row.amount_cents}
          expectedCents={row.expected_amount_cents}
          differenceCents={row.amount_difference_cents}
          currency={row.currency}
        />
      ) : null}

      {row.expected_type_name ? (
        <Text className="mt-2 font-sans text-xs leading-4 text-stoneMuted">
          Paid on the {row.expected_type_name} page.
        </Text>
      ) : null}

      {row.candidate_booking_id ? (
        <View className="mt-3 rounded-button border border-border bg-ivory px-3 py-3">
          <Text className="font-sans-bold text-xs uppercase tracking-widest text-peacock">
            Suggested sponsorship
          </Text>
          <Text className="mt-1 font-sans-bold text-sm text-stone">
            {row.candidate_type_name}
            {row.candidate_on_date
              ? ` — ${formatSponsorshipShortDate(row.candidate_on_date)}`
              : ""}
          </Text>
          <Text className="mt-0.5 font-sans text-xs text-stoneMuted">
            {row.candidate_amount_cents != null
              ? formatCents(row.candidate_amount_cents)
              : "Amount unknown"}
            {row.candidate_status
              ? ` · ${sponsorshipStatusLabels[row.candidate_status]}`
              : ""}
          </Text>
          {row.candidate_count > 1 ? (
            <Text className="mt-1.5 font-sans text-xs leading-4 text-vermilion">
              {row.candidate_count} bookings could be this payment. Check before
              attaching.
            </Text>
          ) : null}
          <Pressable
            className="mt-3 min-h-touch flex-row items-center justify-center rounded-button bg-marigold px-4 py-2.5"
            accessibilityRole="button"
            accessibilityState={{ disabled: busy }}
            accessibilityLabel="Attach this payment to the suggested sponsorship"
            disabled={busy}
            onPress={() =>
              onAttach(row.donation_id, row.candidate_booking_id as string)
            }
          >
            <Ionicons name="link-outline" size={18} color={tokens.colors.stone} />
            <Text className="ml-2 font-sans-bold text-sm text-stone">
              {busy ? "Attaching…" : "Attach to this sponsorship"}
            </Text>
          </Pressable>
        </View>
      ) : (
        <Text className="mt-3 font-sans text-xs leading-4 text-stoneMuted">
          No booking near this payment. It may be a plain gift given on a
          sponsorship page.
        </Text>
      )}
    </View>
  );
}

type Item =
  | { key: string; kind: "donation"; row: AllDonation }
  | { key: string; kind: "sponsorship"; row: AllSponsorship; standing: SponsorshipStanding }
  | { key: string; kind: "queue"; row: UnmatchedDonation };

/**
 * The whole congregation's giving. Every call behind it answers with an empty
 * set to anybody without `app.view_all`, so this screen showing nothing is the
 * server's decision rather than the client's — and it cannot be probed by
 * watching which calls error.
 */
export function AllDonationsScreen() {
  const activeUserId = usePrototypeSession((state) => state.activeUserId);
  const previewRole = usePrototypeSession((state) => state.previewRole);
  const profile = useCurrentAccessProfile(activeUserId);
  const role =
    __DEV__ && previewRole ? previewRole : (profile.data?.role ?? "devotee");
  const mayViewAll = hasAccessPermission(role, "app.view_all");
  const reachable = useServerReachable();
  const now = useNow(60_000);

  const [face, setFace] = useState<Face>("donations");
  const [period, setPeriod] = useState<Period>("month");
  const [standing, setStanding] = useState<SponsorshipStanding>("given");
  const [actionError, setActionError] = useState<string | null>(null);
  const [attachingId, setAttachingId] = useState<string | null>(null);

  const range = useMemo(() => periodRange(period, now), [now, period]);

  const donations = useAllDonations(range.from, range.to, mayViewAll);
  const sponsorships = useAllSponsorships(mayViewAll && face === "sponsorships");
  const queue = useUnmatchedDonations(mayViewAll);
  const attach = useAttachDonationToBooking(activeUserId);

  const donationRows = useMemo(() => donations.data ?? [], [donations.data]);
  const sponsorshipRows = sponsorships.data;
  const queueRows = queue.data ?? [];

  /**
   * The only total on this screen, and it is built from received donations
   * alone. A booking — held, confirmed, released or cancelled — is never added
   * in: a confirmed one's money is already here as the donation that confirmed
   * it, and the other three are not money at all.
   */
  const received = useMemo(
    () => totalsByCurrency(donationRows),
    [donationRows],
  );
  const [primaryTotal, ...otherTotals] = received;

  const byStanding = useMemo(
    () => partitionSponsorships(sponsorshipRows ?? [], now),
    [now, sponsorshipRows],
  );
  const shownSponsorships = byStanding[standing];

  const mismatchCount = donationRows.filter(
    (row) => row.amount_matches === false,
  ).length;

  const query =
    face === "donations" ? donations : face === "sponsorships" ? sponsorships : queue;
  const failed = query.isError && query.data === undefined;

  const items: Item[] =
    face === "donations"
      ? donationRows.map((row) => ({
          key: `donation-${row.id}`,
          kind: "donation" as const,
          row,
        }))
      : face === "sponsorships"
        ? shownSponsorships.map((row) => ({
            key: `sponsorship-${row.id}`,
            kind: "sponsorship" as const,
            row,
            standing,
          }))
        : queueRows.map((row) => ({
            key: `queue-${row.donation_id}`,
            kind: "queue" as const,
            row,
          }));

  const confirmAttach = (donationId: string, bookingId: string) => {
    Alert.alert(
      "Attach this payment?",
      "The sponsorship is confirmed and the date becomes the donor's. This cannot be undone from the app.",
      [
        { text: "Not yet", style: "cancel" },
        {
          text: "Attach",
          onPress: () => {
            setActionError(null);
            setAttachingId(donationId);
            attach.mutate(
              { donationId, bookingId },
              {
                onError: (error: unknown) =>
                  setActionError(
                    errorMessage(
                      error,
                      "That payment could not be attached to the sponsorship.",
                    ),
                  ),
                onSettled: () => setAttachingId(null),
              },
            );
          },
        },
      ],
    );
  };

  return (
    <ListScreen
      topInset={false}
      data={items}
      keyExtractor={(item) => item.key}
      header={
        <>
          <ScreenTitle eyebrow="The temple's giving">All donations</ScreenTitle>

          {!mayViewAll ? (
            <View className="mb-section rounded-card border border-border bg-white px-card py-6">
              <Text className="text-center font-sans text-sm leading-6 text-stoneMuted">
                Only the President and a Tech Admin can see the congregation's
                giving.
              </Text>
            </View>
          ) : null}

          <View className="mb-3 flex-row flex-wrap gap-2">
            {faces.map((option) => (
              <Pill
                key={option.key}
                label={
                  option.key === "queue" && queueRows.length
                    ? `${option.label} (${queueRows.length})`
                    : option.label
                }
                selected={face === option.key}
                onPress={() => setFace(option.key)}
              />
            ))}
          </View>

          {face === "donations" ? (
            <>
              <View className="mb-3 flex-row flex-wrap gap-2">
                {periods.map((option) => (
                  <Pill
                    key={option.key}
                    label={option.label}
                    selected={period === option.key}
                    onPress={() => setPeriod(option.key)}
                  />
                ))}
              </View>

              <View className="mb-section rounded-card border border-border bg-white px-card py-4">
                <Text className="font-sans-bold text-xs uppercase tracking-widest text-peacock">
                  {periods.find((option) => option.key === period)?.label}
                </Text>
                <Text className="mt-1 font-display text-[28px] leading-9 text-stone">
                  {primaryTotal
                    ? formatCents(primaryTotal.cents, primaryTotal.currency)
                    : formatCents(0)}
                </Text>
                <Text className="mt-0.5 font-sans text-xs leading-4 text-stoneMuted">
                  {donationRows.length} gift
                  {donationRows.length === 1 ? "" : "s"} received
                  {range.from
                    ? ` · from ${formatSponsorshipShortDate(range.from)}`
                    : ""}
                </Text>
                {otherTotals.map((other) => (
                  <Text
                    key={other.currency}
                    className="mt-1 font-sans-bold text-sm text-stone"
                  >
                    {formatCents(other.cents, other.currency)} across{" "}
                    {other.count} gift{other.count === 1 ? "" : "s"}
                  </Text>
                ))}
                {mismatchCount ? (
                  <Text className="mt-2 font-sans text-xs leading-4 text-vermilion">
                    {mismatchCount} gift{mismatchCount === 1 ? "" : "s"} do not
                    match what the temple expected.
                  </Text>
                ) : null}
              </View>
            </>
          ) : null}

          {face === "sponsorships" ? (
            <>
              <View className="mb-3 flex-row flex-wrap gap-2">
                {standings.map((option) => (
                  <Pill
                    key={option.key}
                    label={`${option.label} (${byStanding[option.key].length})`}
                    selected={standing === option.key}
                    onPress={() => setStanding(option.key)}
                  />
                ))}
              </View>
              <Text className="mb-section font-sans text-sm leading-6 text-stoneMuted">
                {standing === "given"
                  ? "The days the temple has been paid for. This is the same set the devotee sees in their own giving."
                  : standing === "reserved"
                    ? "Dates held while a devotee pays. No money has arrived for these and none is counted anywhere."
                    : "Dates that went back on the calendar — released, cancelled, or a hold that ran out. Not giving."}
              </Text>
            </>
          ) : null}

          {face === "queue" && queueRows.length ? (
            <Text className="mb-3 font-sans text-sm leading-6 text-stoneMuted">
              Zeffy sends no booking reference, so a payment that could not be
              matched with certainty waits here rather than being guessed at.
            </Text>
          ) : null}

          {actionError ? <FormError message={actionError} /> : null}

          {failed ? (
            <View className="mb-section">
              <LoadFailure
                reachable={reachable}
                message={errorMessage(query.error, "")}
                onRetry={() => void query.refetch()}
              />
            </View>
          ) : null}
        </>
      }
      renderItem={(item) => {
        if (item.kind === "donation") return <DonationRow row={item.row} />;
        if (item.kind === "sponsorship")
          return <SponsorshipRow row={item.row} standing={item.standing} />;
        return (
          <QueueRow
            row={item.row}
            busy={attachingId === item.row.donation_id}
            onAttach={confirmAttach}
          />
        );
      }}
      empty={
        failed || !mayViewAll ? null : (
          <EmptyOrOffline
            reachable={reachable}
            loading={query.isLoading}
            loadingLabel="Reading the temple's giving…"
            empty={
              <View className="items-center rounded-card border border-border bg-white px-card py-10">
                <View className="h-14 w-14 items-center justify-center rounded-pill bg-peacockSoft">
                  <Ionicons
                    name={
                      face === "queue"
                        ? "checkmark-done-outline"
                        : "documents-outline"
                    }
                    size={26}
                    color={tokens.colors.peacock}
                  />
                </View>
                <Text className="mt-4 text-center font-display text-xl text-stone">
                  {face === "queue"
                    ? "Nothing to settle"
                    : face === "sponsorships"
                      ? `No ${standings.find((option) => option.key === standing)?.label.toLowerCase()} bookings`
                      : "Nothing in this period"}
                </Text>
                <Text className="mt-2 max-w-80 text-center font-sans text-sm leading-6 text-stoneMuted">
                  {face === "queue"
                    ? "Every payment has found the sponsorship it paid for."
                    : face === "sponsorships"
                      ? "Try one of the other two."
                      : "Try a wider period, or check back once the next gift arrives."}
                </Text>
              </View>
            }
          />
        )
      }
    />
  );
}
