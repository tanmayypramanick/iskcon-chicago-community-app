import { createClient } from "npm:@supabase/supabase-js@2";

type WebhookPayload = {
  record?: { id?: string };
};

/**
 * Turns an app_notifications row into an Expo push.
 *
 * Two rules matter here, because this function is deployed with
 * --no-verify-jwt and is therefore reachable by anyone who finds the URL:
 *
 *  1. The shared secret is REQUIRED. It used to be checked only when the
 *     environment variable happened to be set, so a missing secret silently
 *     turned the endpoint into an open push relay for the whole congregation.
 *  2. Only the row id is taken from the request. Title, body and deep-link
 *     data are re-read from the database, so a caller cannot dictate what a
 *     devotee's phone displays or where tapping it leads.
 */

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

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  const expectedSecret = Deno.env.get("NOTIFICATION_WEBHOOK_SECRET");
  if (!expectedSecret) {
    // Fail closed. An unconfigured secret is a deployment mistake, not a
    // reason to accept anonymous push requests.
    console.error("NOTIFICATION_WEBHOOK_SECRET is not set; refusing to send.");
    return new Response("Not configured", { status: 503 });
  }
  const providedSecret = request.headers.get("x-notification-secret") ?? "";
  if (!secretsMatch(providedSecret, expectedSecret)) {
    return new Response("Unauthorized", { status: 401 });
  }

  let payload: WebhookPayload;
  try {
    payload = (await request.json()) as WebhookPayload;
  } catch {
    return new Response("Bad request", { status: 400 });
  }

  const notificationId = payload.record?.id;
  if (!notificationId) return new Response("Ignored", { status: 202 });

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // The row, not the request body, is the source of truth.
  const { data: notification, error: readError } = await supabase
    .from("app_notifications")
    .select("id,user_id,kind,title,body,data")
    .eq("id", notificationId)
    .maybeSingle();
  if (readError) {
    return Response.json({ error: readError.message }, { status: 500 });
  }
  if (!notification) return new Response("Ignored", { status: 202 });

  const { data: devices, error: deviceError } = await supabase
    .from("device_push_tokens")
    .select("id,expo_push_token")
    .eq("user_id", notification.user_id)
    .eq("active", true);
  if (deviceError) {
    return Response.json({ error: deviceError.message }, { status: 500 });
  }
  if (!devices?.length) return Response.json({ sent: 0 });

  const messages = devices.map((device) => ({
    to: device.expo_push_token,
    sound: "default",
    title: notification.title,
    body: notification.body,
    channelId: "community-updates",
    data: {
      ...((notification.data as Record<string, unknown> | null) ?? {}),
      appNotificationId: notification.id,
      kind: notification.kind,
    },
  }));

  const pushResponse = await fetch("https://exp.host/--/api/v2/push/send", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(messages),
  });
  const pushResult = await pushResponse.json();
  const tickets = Array.isArray(pushResult.data) ? pushResult.data : [];
  const invalidIds = devices.flatMap((device, index) =>
    tickets[index]?.details?.error === "DeviceNotRegistered" ? [device.id] : [],
  );
  if (invalidIds.length) {
    await supabase
      .from("device_push_tokens")
      .update({ active: false })
      .in("id", invalidIds);
  }

  return Response.json({ sent: messages.length, accepted: pushResponse.ok });
});
