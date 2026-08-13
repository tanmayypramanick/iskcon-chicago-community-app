/**
 * Giving, as the temple records it.
 *
 * The money never touches our database. Zeffy takes the card on a page of its
 * own — it charges the temple nothing, which is why it was chosen, and in
 * exchange it gives back no calendar, no exclusivity and no record of which
 * seva was sponsored on which day. So the app owns all of that and Zeffy owns
 * only the payment.
 *
 * Every amount here is an integer number of cents, exactly as
 * 202608040048_donations.sql holds it: $551.00 is 55100. Nothing in this
 * feature divides money, sums it as a float, or parses it back out of a
 * formatted string.
 */

/**
 * The temple's general Zeffy form. It handles a one-off gift and a recurring
 * one — monthly, quarterly or yearly — so the app does not need a second link
 * or a second screen for the recurring case.
 */
export const GENERAL_DONATION_URL =
  "https://www.zeffy.com/en-US/donation-form/donate-789";

/**
 * How long `hold_sponsorship` keeps a date. Stated here so the screen can warn
 * a devotee before they leave for Zeffy rather than after the server answers;
 * `held_until` on the booking is the real deadline and is what gets shown once
 * the hold exists.
 */
export const SPONSORSHIP_HOLD_MINUTES = 30;

export type SponsorshipStatus = "held" | "confirmed" | "released" | "cancelled";
export type DonationKind = "one_time" | "recurring";
export type DonationRecurrence = "monthly" | "quarterly" | "yearly";
export type DonationMatchStatus =
  | "general"
  | "matched"
  | "manual"
  | "unmatched";
export type UnmatchedReason =
  | "no_candidate"
  | "several_candidates"
  | "amount_mismatch"
  | "booking_lost_date";

/** A row of `list_sponsorship_types()`. */
export type SponsorshipType = {
  id: string;
  name: string;
  amount_cents: number;
  is_active: boolean;
  display_order: number;
  /** Added by 0049. Null on a database that only has 0048. */
  sunday_only: boolean | null;
  /** Null means the temple has not made the Zeffy page yet. */
  zeffy_campaign_url: string | null;
  zeffy_campaign_slug: string | null;
  /** Added by 0050. Absent until it is deployed — see `sponsorshipNeedsDate`. */
  requires_date?: boolean | null;
};

/** A row of `sponsorship_availability(p_from, p_to)`. */
export type SponsorshipAvailability = {
  sponsorship_type_id: string;
  type_name: string;
  amount_cents: number;
  /** A temple calendar date, "2026-08-16". No time, no zone. */
  on_date: string;
  is_taken: boolean;
  is_mine: boolean;
  /** Withheld from everyone but the sponsor and the two who see everything. */
  booking_id: string | null;
  /** Withheld on the same terms, so an ordinary devotee never learns who. */
  booked_by_name: string | null;
};

/** What `hold_sponsorship` and `release_sponsorship_hold` hand back. */
export type SponsorshipBooking = {
  id: string;
  sponsorship_type_id: string;
  devotee_id: string;
  on_date: string | null;
  status: SponsorshipStatus;
  held_until: string | null;
  amount_cents: number;
  created_at: string;
  updated_at: string;
};

export type MyDonation = {
  id: string;
  amount_cents: number;
  currency: string;
  kind: DonationKind;
  recurrence: DonationRecurrence | null;
  external_payment_id: string;
  received_at: string;
  sponsorship_booking_id: string | null;
  sponsorship_type_name: string | null;
  sponsorship_on_date: string | null;
  /** Added by 0049. */
  match_status?: DonationMatchStatus | null;
  expected_amount_cents?: number | null;
  amount_matches?: boolean | null;
};

export type MySponsorship = {
  id: string;
  sponsorship_type_id: string;
  type_name: string;
  amount_cents: number;
  on_date: string | null;
  status: SponsorshipStatus;
  held_until: string | null;
  created_at: string;
  donation_id: string | null;
  /** Added by 0050. */
  requires_date?: boolean | null;
  /**
   * The day the temple actually offered a dateless sponsorship. A deity dress
   * is sewn and offered when it is ready, so this is the only answer a devotee
   * ever gets to "has mine happened yet".
   */
  fulfilled_on?: string | null;
  fulfilment_note?: string | null;
};

export type AllDonation = {
  id: string;
  donor_id: string | null;
  donor_name: string | null;
  donor_email: string | null;
  amount_cents: number;
  currency: string;
  kind: DonationKind;
  recurrence: DonationRecurrence | null;
  external_payment_id: string;
  received_at: string;
  sponsorship_booking_id: string | null;
  sponsorship_type_name: string | null;
  sponsorship_on_date: string | null;
  match_status?: DonationMatchStatus | null;
  unmatched_reason?: UnmatchedReason | null;
  expected_amount_cents?: number | null;
  amount_difference_cents?: number | null;
  amount_matches?: boolean | null;
  zeffy_campaign_slug?: string | null;
  /**
   * Added by 0061: the standing of the sponsorship this gift paid for, already
   * projected the way `list_all_sponsorships` projects it, so a screen can say
   * where a booking stands without a second read of the booking list. Null when
   * the gift paid for no sponsorship, which is most of them.
   */
  booking_status?: SponsorshipStatus | null;
};

/**
 * A row of `donation_totals` or `my_donation_totals` — added by 0061 so a total
 * is computed where the rows are rather than summed over whatever page the
 * client happens to be holding.
 *
 * One row per currency, always. There is no argument that collapses them and
 * nothing here may add them together.
 */
export type DonationTotal = {
  currency: string;
  total_cents: number;
  gifts: number;
};

export type AllSponsorship = {
  id: string;
  sponsorship_type_id: string;
  type_name: string;
  amount_cents: number;
  on_date: string | null;
  status: SponsorshipStatus;
  held_until: string | null;
  created_at: string;
  devotee_id: string | null;
  devotee_name: string | null;
  devotee_email: string | null;
  donation_id: string | null;
  requires_date?: boolean | null;
  fulfilled_on?: string | null;
  fulfilment_note?: string | null;
};

/** A row of `list_unmatched_donations()` — the queue a human settles by hand. */
export type UnmatchedDonation = {
  donation_id: string;
  external_payment_id: string;
  received_at: string;
  donor_id: string | null;
  donor_name: string | null;
  donor_email: string | null;
  amount_cents: number;
  currency: string;
  expected_amount_cents: number | null;
  amount_difference_cents: number | null;
  amount_matches: boolean | null;
  unmatched_reason: UnmatchedReason | null;
  zeffy_campaign_slug: string | null;
  expected_type_name: string | null;
  linked_booking_id: string | null;
  /** How many bookings a human has to weigh; the row carries the best one. */
  candidate_count: number;
  candidate_booking_id: string | null;
  candidate_type_name: string | null;
  candidate_on_date: string | null;
  candidate_amount_cents: number | null;
  candidate_status: SponsorshipStatus | null;
};

/**
 * Whether a sponsorship is booked on a day at all.
 *
 * Deity Dress is not: several devotees may offer towards the same dressing and
 * there is no date to take off a calendar. `requires_date` says so, and it
 * arrives with migration 0050. Until that is deployed the column is simply not
 * in the answer, and the deployed `hold_sponsorship` refuses a null date — so
 * "it needs a date" is the honest reading of a missing column rather than a
 * guess made from the sponsorship's name.
 */
export function sponsorshipNeedsDate(type: SponsorshipType) {
  return type.requires_date !== false;
}

/** Whether the temple has made the Zeffy page this sponsorship is paid on. */
export function sponsorshipIsPayable(type: SponsorshipType) {
  return Boolean(type.zeffy_campaign_url?.trim());
}

/**
 * Money, exactly. The cents are split with integer arithmetic and only the
 * whole-dollar part is ever handed to Intl, so nothing here can round: dividing
 * by 100 first would turn 55100 into a float and put the temple's accounts at
 * the mercy of binary fractions.
 */
export function formatCents(cents: number, currency = "USD") {
  const whole = Math.trunc(cents);
  const sign = whole < 0 ? "-" : "";
  const magnitude = Math.abs(whole);
  const dollars = new Intl.NumberFormat("en-US").format(
    Math.floor(magnitude / 100),
  );
  const remainder = String(magnitude % 100).padStart(2, "0");
  const prefix = currency && currency !== "USD" ? `${currency} ` : "";
  return `${sign}${prefix}$${dollars}.${remainder}`;
}

/**
 * The same amount as a bare decimal, for a spreadsheet cell: "551.00".
 *
 * A column of "$551.00" is text to Excel and sorts alphabetically, which puts
 * $90 above $551 in a report the temple reads down. The symbol belongs in the
 * heading. Integer arithmetic for the same reason `formatCents` uses it —
 * dividing by 100 first would hand the temple's accounts to binary fractions.
 */
export function centsAsDecimal(cents: number) {
  const whole = Math.trunc(cents);
  const sign = whole < 0 ? "-" : "";
  const magnitude = Math.abs(whole);
  const remainder = String(magnitude % 100).padStart(2, "0");
  return `${sign}${Math.floor(magnitude / 100)}.${remainder}`;
}

/** Adds integer cents. Never a running float. */
export function sumCents(rows: readonly { amount_cents: number }[]) {
  return rows.reduce((total, row) => total + Math.trunc(row.amount_cents), 0);
}

/**
 * What the temple actually received, split by the currency it arrived in.
 *
 * Only `donations` rows belong here. A row in that table means money landed —
 * the schema has no `pending` and no `failed` — so a total built from these is
 * the figure that has to agree with Zeffy's dashboard. A sponsorship booking is
 * a promise of money, not money, and summing one into this would put a number
 * on the screen that reconciles with nothing.
 *
 * Cents of two currencies are two different units. This temple settles in USD
 * and the normal answer is a single entry, but adding them would be arithmetic
 * on unlike things, so they are kept apart rather than silently merged.
 */
export function totalsByCurrency(
  rows: readonly { amount_cents: number; currency: string }[],
) {
  const byCurrency = new Map<string, { cents: number; count: number }>();
  for (const row of rows) {
    const currency = row.currency?.trim() || "USD";
    const running = byCurrency.get(currency) ?? { cents: 0, count: 0 };
    running.cents += Math.trunc(row.amount_cents);
    running.count += 1;
    byCurrency.set(currency, running);
  }
  return [...byCurrency.entries()]
    .map(([currency, running]) => ({ currency, ...running }))
    .sort((a, b) => b.cents - a.cents || a.currency.localeCompare(b.currency));
}

/**
 * What a booking is, as far as a record of giving is concerned.
 *
 *   given     `confirmed` — a payment was matched to it. This is the only
 *             status that is a gift.
 *   reserved  a hold that has not run out. The date is off the calendar, but
 *             nothing has been paid and it may never be.
 *   lapsed    released, cancelled, or a hold whose time has passed. A date the
 *             devotee took and did not pay for. Not giving, and never a total.
 *
 * The expired hold matters. The unique index that guards a date cannot mention
 * now(), so an expired hold keeps its row until a sweep releases it, and
 * `sponsorship_availability` already reports that date as free. Reading a stale
 * `held` row as live would show the devotee a reservation the temple has
 * already given away.
 */
export type SponsorshipStanding = "given" | "reserved" | "lapsed";

type BookingStanding = {
  status: SponsorshipStatus;
  held_until: string | null;
};

export function sponsorshipStanding(
  row: BookingStanding,
  now: Date,
): SponsorshipStanding {
  if (row.status === "confirmed") return "given";
  if (
    row.status === "held" &&
    row.held_until !== null &&
    new Date(row.held_until).getTime() > now.getTime()
  ) {
    return "reserved";
  }
  return "lapsed";
}

/** The three standings, in one pass, keeping each list's server order. */
export function partitionSponsorships<Row extends BookingStanding>(
  rows: readonly Row[],
  now: Date,
) {
  const given: Row[] = [];
  const reserved: Row[] = [];
  const lapsed: Row[] = [];
  for (const row of rows) {
    const standing = sponsorshipStanding(row, now);
    if (standing === "given") given.push(row);
    else if (standing === "reserved") reserved.push(row);
    else lapsed.push(row);
  }
  return { given, reserved, lapsed };
}

/**
 * The instant a bare temple date refers to, read as UTC.
 *
 * `on_date` carries no time and no zone. Parsing it through the device
 * calendar, or rendering it in Chicago, both slide it by a day for somebody:
 * midnight UTC on the 16th is 7pm on the 15th in Chicago. Every date-only
 * value in this feature is built and formatted in UTC so the day the devotee
 * sees is the day the database holds.
 */
export function dateKeyToInstant(dateKey: string) {
  return new Date(`${dateKey}T00:00:00.000Z`);
}

/** 0 = Sunday, matching Postgres and `chicagoDate`'s weekday. */
export function dateKeyWeekday(dateKey: string) {
  return dateKeyToInstant(dateKey).getUTCDay();
}

/** "Sunday, August 16, 2026" */
export function formatSponsorshipDate(dateKey: string) {
  return new Intl.DateTimeFormat("en-US", {
    timeZone: "UTC",
    weekday: "long",
    month: "long",
    day: "numeric",
    year: "numeric",
  }).format(dateKeyToInstant(dateKey));
}

/** "Sun, Aug 16" */
export function formatSponsorshipShortDate(dateKey: string) {
  return new Intl.DateTimeFormat("en-US", {
    timeZone: "UTC",
    weekday: "short",
    month: "short",
    day: "numeric",
  }).format(dateKeyToInstant(dateKey));
}

const recurrenceLabels: Record<DonationRecurrence, string> = {
  monthly: "Every month",
  quarterly: "Every three months",
  yearly: "Every year",
};

/** "One-time gift" or how often a recurring one repeats. */
export function donationKindLabel(donation: {
  kind: DonationKind;
  recurrence: DonationRecurrence | null;
}) {
  if (donation.kind !== "recurring") return "One-time gift";
  return donation.recurrence
    ? `Recurring — ${recurrenceLabels[donation.recurrence].toLowerCase()}`
    : "Recurring gift";
}

/**
 * What to call a booking that is no longer live. An expired hold still carries
 * `held`, and calling it "Held while you pay" would be a lie — the date has
 * gone back on the calendar.
 */
export function lapsedSponsorshipLabel(row: { status: SponsorshipStatus }) {
  return row.status === "cancelled" ? "Cancelled" : "Released";
}

export const sponsorshipStatusLabels: Record<SponsorshipStatus, string> = {
  held: "Held while you pay",
  confirmed: "Sponsored",
  released: "Released",
  cancelled: "Cancelled",
};

export const unmatchedReasonLabels: Record<UnmatchedReason, string> = {
  no_candidate: "No sponsorship was on hold when this arrived",
  several_candidates: "More than one sponsorship fits this payment",
  amount_mismatch: "The amount does not match the sponsorship held",
  booking_lost_date: "The date had gone by the time the money landed",
};
