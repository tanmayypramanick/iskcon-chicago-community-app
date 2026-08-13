import { createClient } from "npm:@supabase/supabase-js@2";

/**
 * Turns a Zeffy `payment.completed` webhook into a row in public.donations.
 *
 * Everything here follows from one fact: Zeffy does not sign its webhooks.
 *
 * There is no HMAC, no timestamp, no shared signing secret — anybody who
 * discovers this URL can POST anything at it. So the body is treated as a
 * rumour rather than a report. Two rules follow, and neither is negotiable:
 *
 *  1. The shared secret header is REQUIRED. It is checked before the body is
 *     even parsed, and a missing ZEFFY_WEBHOOK_SECRET fails the request closed
 *     rather than turning the endpoint into an open ledger-writing relay. This
 *     is the same defence, in the same shape, as send-service-notification's
 *     x-notification-secret, and for the same reason: the function is deployed
 *     with --no-verify-jwt and is reachable by anyone who finds it.
 *
 *  2. Only `data.id` is taken from the request. The amount, the buyer, the
 *     currency and the campaign are all re-read from Zeffy's own API with the
 *     temple's key, and only that response is believed. A caller who guesses
 *     the URL and the secret still cannot dictate that somebody gave $10,000,
 *     because the number is never read from what they sent.
 *
 * What it does NOT do, deliberately
 * ---------------------------------
 * It does not decide which sponsorship the money paid for. Zeffy's ticketing
 * campaigns carry no dates and cannot be prefilled with a booking reference, so
 * matching a payment to a booking is a judgement made from an email, an amount,
 * a campaign and a moment — and that judgement lives in record_donation, in the
 * database, next to the calendar and the unique index that make it safe. This
 * function's whole job is to hand those four facts over truthfully.
 *
 * Environment
 * -----------
 *   ZEFFY_WEBHOOK_SECRET        required; compared against x-zeffy-webhook-secret
 *   ZEFFY_API_KEY               required; bearer token for api.zeffy.com
 *   SUPABASE_URL                required
 *   SUPABASE_SERVICE_ROLE_KEY   required; record_donation is the service role's alone
 *   ZEFFY_API_BASE_URL          optional; defaults to https://api.zeffy.com
 *
 * Nothing above is hardcoded anywhere in this file.
 */

const DEFAULT_ZEFFY_API = "https://api.zeffy.com";

type WebhookBody = {
  type?: string;
  eventType?: string;
  data?: { id?: string };
};

type ZeffyPayment = {
  id?: string;
  /** Integer cents. Zeffy reports money in cents; this file never converts. */
  amount?: number;
  currency?: string;
  status?: string;
  created_at?: string;
  createdAt?: string;
  /** null for a one-off gift; an object carrying `interval` for a standing one. */
  recurring?: { interval?: string } | null;
  buyer?: {
    email?: string;
    first_name?: string;
    last_name?: string;
    firstName?: string;
    lastName?: string;
  } | null;
  campaign?: { slug?: string; url?: string; id?: string } | null;
  campaign_slug?: string;
  campaignSlug?: string;
};

/** Constant-time compare, so the secret cannot be recovered byte by byte. */
function secretsMatch(provided: string, expected: string) {
  const a = new TextEncoder().encode(provided);
  const b = new TextEncoder().encode(expected);
  if (a.length !== b.length) return false;
  let difference = 0;
  for (let index = 0; index < a.length; index += 1) {
    difference |= a[index] ^ b[index];
  }
  return difference === 0;
}

/**
 * Zeffy names a recurring gift's cadence in its own vocabulary, and
 * public.donations accepts three values. Anything outside the mapping is
 * recorded as a one-off rather than guessed at: the money is what the temple
 * must not lose, the schedule is preserved verbatim in the payload, and a gift
 * wrongly filed as monthly would be reported as revenue that is not coming.
 */
function toRecurrence(interval: string | undefined | null) {
  const value = (interval ?? "").toLowerCase();
  if (value.includes("month")) return "monthly";
  if (value.includes("quarter")) return "quarterly";
  if (value.includes("year") || value.includes("annual")) return "yearly";
  return null;
}

/**
 * Which sponsorship page the money came through. It is what lets the database
 * tell a Sunday Feast payment that failed to match from an ordinary gift that
 * never needed to — so it is read from every shape Zeffy might present it in,
 * falling back to the last path segment of a campaign URL.
 */
function campaignSlug(payment: ZeffyPayment) {
  const direct = payment.campaign?.slug ?? payment.campaign_slug ??
    payment.campaignSlug;
  if (typeof direct === "string" && direct.trim()) {
    return direct.trim().toLowerCase();
  }

  const url = payment.campaign?.url;
  if (typeof url === "string" && url.trim()) {
    const segment = url.split("?")[0].split("#")[0].replace(/\/+$/, "")
      .split("/").pop();
    if (segment) return segment.toLowerCase();
  }
  return null;
}

/** Explicitly not-money. Anything Zeffy does not call a failure is recorded. */
function isUnsuccessful(status: string | undefined) {
  const value = (status ?? "").toLowerCase();
  if (!value) return false;
  return ["fail", "refund", "cancel", "declin", "chargeback", "void", "pending"]
    .some((word) => value.includes(word));
}

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  const expectedSecret = Deno.env.get("ZEFFY_WEBHOOK_SECRET");
  if (!expectedSecret) {
    // Fail closed. An unconfigured secret is a deployment mistake, not a reason
    // to accept anonymous writes to the temple's ledger.
    console.error("ZEFFY_WEBHOOK_SECRET is not set; refusing every delivery.");
    return new Response("Not configured", { status: 503 });
  }
  // Zeffy's webhook settings accept a URL and nothing else — there is no field
  // for a custom header — so the secret is also read from the query string.
  // That is weaker (it lands in Zeffy's logs), but it is only spam protection:
  // the payment itself is re-fetched from Zeffy below, so a forged delivery
  // cannot invent a gift even if the secret leaks.
  const providedSecret =
    request.headers.get("x-zeffy-webhook-secret") ??
    new URL(request.url).searchParams.get("s") ??
    "";
  if (!secretsMatch(providedSecret, expectedSecret)) {
    return new Response("Unauthorized", { status: 401 });
  }

  const apiKey = Deno.env.get("ZEFFY_API_KEY");
  if (!apiKey) {
    // 503, not 200. Zeffy must keep trying: a payment we cannot verify yet is
    // not a payment that did not happen.
    console.error("ZEFFY_API_KEY is not set; cannot verify the payment.");
    return new Response("Not configured", { status: 503 });
  }

  let body: WebhookBody;
  try {
    body = (await request.json()) as WebhookBody;
  } catch {
    return new Response("Bad request", { status: 400 });
  }

  // Other event types are acknowledged and ignored: a 202 stops Zeffy retrying
  // something we were never going to act on.
  const eventType = body.type ?? body.eventType ?? "";
  if (eventType && eventType !== "payment.completed") {
    return new Response("Ignored", { status: 202 });
  }

  const paymentId = body.data?.id;
  if (typeof paymentId !== "string" || !paymentId.trim()) {
    return new Response("Ignored", { status: 202 });
  }

  // The only thing taken from the request. Everything else is re-read.
  const base = (Deno.env.get("ZEFFY_API_BASE_URL") ?? DEFAULT_ZEFFY_API)
    .replace(/\/+$/, "");
  const url = `${base}/api/v1/payments/${encodeURIComponent(paymentId.trim())}`;

  let lookup: Response;
  try {
    lookup = await fetch(url, {
      headers: {
        authorization: `Bearer ${apiKey}`,
        accept: "application/json",
      },
    });
  } catch (error) {
    // Zeffy unreachable. Never swallow a payment because a network call failed.
    console.error("Could not reach Zeffy:", error);
    return new Response("Upstream unavailable", { status: 503 });
  }

  if (!lookup.ok) {
    // A bad key (401/403), a payment Zeffy has not published yet (404), or an
    // outage (5xx) are all the same answer here: we do not know, so do not
    // record, and do not tell Zeffy we are done.
    console.error(`Zeffy returned ${lookup.status} for payment ${paymentId}.`);
    return new Response("Upstream error", { status: 502 });
  }

  let payment: ZeffyPayment;
  try {
    payment = (await lookup.json()) as ZeffyPayment;
  } catch (error) {
    console.error("Zeffy's response was not JSON:", error);
    return new Response("Upstream error", { status: 502 });
  }

  if (isUnsuccessful(payment.status)) {
    console.error(
      `Zeffy reports payment ${paymentId} as ${payment.status}; not recording.`,
    );
    return new Response("Ignored", { status: 202 });
  }

  // Money, in integer cents, or nothing. A fractional or negative amount is not
  // something to round into the ledger — the temple's whole donations schema is
  // built on cents being exact.
  const amountCents = payment.amount;
  if (
    typeof amountCents !== "number" || !Number.isInteger(amountCents) ||
    amountCents <= 0
  ) {
    console.error(
      `Zeffy payment ${paymentId} has an unusable amount: ${amountCents}`,
    );
    return new Response("Unprocessable payment", { status: 422 });
  }

  const interval = payment.recurring?.interval;
  const recurrence = payment.recurring ? toRecurrence(interval) : null;
  if (payment.recurring && !recurrence) {
    console.error(
      `Zeffy payment ${paymentId} repeats every "${interval}", which this ` +
        `schema has no name for. Recording it as one-time; the interval is in ` +
        `the payload.`,
    );
  }

  const buyer = payment.buyer ?? {};
  const donorName = [
    buyer.first_name ?? buyer.firstName,
    buyer.last_name ?? buyer.lastName,
  ].filter((part) => typeof part === "string" && part.trim()).join(" ").trim();

  const currency = typeof payment.currency === "string" &&
      /^[A-Za-z]{3}$/.test(payment.currency)
    ? payment.currency.toUpperCase()
    : "USD";

  const receivedAt = payment.created_at ?? payment.createdAt ?? null;
  const slug = campaignSlug(payment);

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // No booking is named. Which sponsorship this paid for — if any — is
  // record_donation's judgement to make, beside the calendar it has to be
  // consistent with.
  const { data: donation, error } = await supabase.rpc("record_donation", {
    p_external_payment_id: payment.id ?? paymentId,
    p_amount_cents: amountCents,
    p_kind: recurrence ? "recurring" : "one_time",
    p_recurrence: recurrence,
    p_currency: currency,
    p_donor_name: donorName || null,
    p_donor_email: buyer.email ?? null,
    p_payload: {
      source: "zeffy",
      campaign_slug: slug,
      // Verbatim, so a gift disputed a year from now is answered by what Zeffy
      // said rather than by this file's reading of it.
      payment,
    },
    p_received_at: receivedAt,
  });

  if (error) {
    // Recording failed. A 500 keeps the delivery in Zeffy's retry queue, and
    // record_donation is idempotent on the payment id, so a retry that arrives
    // after a write that actually succeeded still leaves exactly one gift.
    console.error(`record_donation refused payment ${paymentId}:`, error);
    return Response.json({ error: error.message }, { status: 500 });
  }

  return Response.json({
    recorded: true,
    donation_id: donation?.id ?? null,
    match_status: donation?.match_status ?? null,
  });
});
