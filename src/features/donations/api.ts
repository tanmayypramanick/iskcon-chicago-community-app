import * as WebBrowser from "expo-web-browser";

import { reportReachability } from "../../lib/connectivity";
import { getSupabaseClient } from "../../lib/supabase";
import { isConnectionProblem } from "../services/format";
import type {
  AllDonation,
  AllSponsorship,
  DonationTotal,
  MyDonation,
  MySponsorship,
  SponsorshipAvailability,
  SponsorshipBooking,
  SponsorshipType,
  UnmatchedDonation,
} from "./types";

/**
 * Giving arrives in migrations 0048, 0049 and 0050, and a temple's database may
 * not have had them applied yet.
 *   PGRST202 / 42883 — that function does not exist
 *   42P01 / PGRST205 — that relation does not exist
 * Reads treat that as "there is nothing to show" rather than as a failure: a
 * devotee cannot act on a migration that has not been run, and a red error
 * where a quiet empty state belongs reads as the app being broken.
 */
function isMigrationPending(error: { code?: string } | null) {
  return ["PGRST202", "42883", "42P01", "PGRST205"].includes(error?.code ?? "");
}

async function listRpc<Row>(
  name: string,
  params: Record<string, unknown> = {},
): Promise<Row[]> {
  const { data, error } = await getSupabaseClient().rpc(name, params);
  // A transport failure means the server is unreachable; a Postgres error
  // means it answered, so the connection is fine.
  reportReachability(!error || !isConnectionProblem(error));
  if (error) {
    if (isMigrationPending(error)) return [];
    throw error;
  }
  return (data ?? []) as unknown as Row[];
}

/**
 * The writes do not tolerate a missing migration. Holding a date, releasing it
 * and settling a payment all either happen or do not, and a tap that silently
 * does nothing is worse than a sentence saying why.
 */
async function runRpc(
  name: string,
  params: Record<string, unknown> = {},
): Promise<unknown> {
  const { data, error } = await getSupabaseClient().rpc(name, params);
  reportReachability(!error || !isConnectionProblem(error));
  if (error) throw error;
  return data;
}

/** What can be sponsored, in the temple's own order. */
export function fetchSponsorshipTypes(): Promise<SponsorshipType[]> {
  return listRpc<SponsorshipType>("list_sponsorship_types");
}

/**
 * Which days are free between two temple dates. The server leaves out the days
 * a sponsorship is not offered on at all — a Sunday Feast on a Wednesday — so
 * a missing row means "not offered", not "free".
 */
export function fetchSponsorshipAvailability(
  from: string,
  to: string,
): Promise<SponsorshipAvailability[]> {
  return listRpc<SponsorshipAvailability>("sponsorship_availability", {
    p_from: from,
    p_to: to,
  });
}

/**
 * Takes the date while the devotee pays for it. `onDate` is null only for a
 * sponsorship that has no date at all, and the server is what decides whether
 * that is allowed.
 */
export async function holdSponsorship(
  typeId: string,
  onDate: string | null,
): Promise<SponsorshipBooking> {
  const data = await runRpc("hold_sponsorship", {
    p_type_id: typeId,
    p_on_date: onDate,
  });
  return data as SponsorshipBooking;
}

/** Gives a held date back — the devotee closed the payment page. */
export async function releaseSponsorshipHold(
  bookingId: string,
): Promise<SponsorshipBooking> {
  const data = await runRpc("release_sponsorship_hold", {
    p_booking_id: bookingId,
  });
  return data as SponsorshipBooking;
}

export function fetchMyDonations(): Promise<MyDonation[]> {
  return listRpc<MyDonation>("list_my_donations");
}

export function fetchMySponsorships(): Promise<MySponsorship[]> {
  return listRpc<MySponsorship>("list_my_sponsorships");
}

/**
 * Every gift in a window of temple dates, or one donor's. The server answers
 * with an empty set to anybody without `app.view_all`, so calling it is safe
 * whatever the viewer's role.
 *
 * `p_donor_id` arrives with 0061 and is only sent when a donor was named, so
 * the temple-wide call keeps the two-argument shape a database that is behind
 * on that migration still answers.
 */
export function fetchAllDonations(
  from: string | null,
  to: string | null,
  donorId: string | null = null,
): Promise<AllDonation[]> {
  return listRpc<AllDonation>("list_all_donations", {
    p_from: from,
    p_to: to,
    ...(donorId ? { p_donor_id: donorId } : {}),
  });
}

/**
 * What the temple received, added up in the database — one row per currency,
 * and never to be summed across them.
 *
 * The window is passed explicitly, nulls included, because `donation_totals`
 * defaults neither bound: a caller asking for a total must say over what, or
 * a lifetime figure ends up under a heading that says "this month".
 */
export function fetchDonationTotals(
  from: string | null,
  to: string | null,
  donorId: string | null = null,
): Promise<DonationTotal[]> {
  return listRpc<DonationTotal>("donation_totals", {
    p_from: from,
    p_to: to,
    p_donor_id: donorId,
  });
}

export function fetchAllSponsorships(): Promise<AllSponsorship[]> {
  return listRpc<AllSponsorship>("list_all_sponsorships");
}

export function fetchUnmatchedDonations(): Promise<UnmatchedDonation[]> {
  return listRpc<UnmatchedDonation>("list_unmatched_donations");
}

/** Ties a payment to the sponsorship it paid for, and confirms that booking. */
export async function attachDonationToBooking(
  donationId: string,
  bookingId: string,
) {
  return runRpc("attach_donation_to_booking", {
    p_donation_id: donationId,
    p_booking_id: bookingId,
  });
}

/**
 * Zeffy's hosted page carries no booking reference, so the one thing the app
 * can hand it is the devotee's address: `record_donation` matches a payment
 * back to the hold through the buyer email, and a devotee who retypes a
 * different one lands in the President's queue instead.
 *
 * Appended by hand rather than through URL: the campaign link is whatever the
 * temple pasted out of Zeffy's dashboard and may already carry a query string.
 */
export function zeffyUrlWithEmail(url: string, email?: string | null) {
  const address = email?.trim();
  if (!address) return url;
  return `${url}${url.includes("?") ? "&" : "?"}email=${encodeURIComponent(address)}`;
}

/**
 * Opens a payment page outside the app — SFSafariViewController on iOS, a
 * Chrome Custom Tab on Android.
 *
 * Never a WebView. Apple Pay and Google Pay do not run in one, so a devotee
 * would be left typing a card number that their phone already knows, and App
 * Review requires payment on the web to happen in the system browser rather
 * than in a view the app could be reading.
 */
export async function openZeffyPage(url: string, email?: string | null) {
  await WebBrowser.openBrowserAsync(zeffyUrlWithEmail(url, email), {
    // The address stays on screen while they pay, so it is visible that the
    // card is being given to Zeffy and not to us.
    enableBarCollapsing: false,
  });
}
