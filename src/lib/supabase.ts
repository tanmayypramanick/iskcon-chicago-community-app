import "react-native-url-polyfill/auto";
import "expo-sqlite/localStorage/install";

import { createClient, type SupabaseClient } from "@supabase/supabase-js";

const supabaseUrl = process.env.EXPO_PUBLIC_SUPABASE_URL;
const supabasePublishableKey =
  process.env.EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY ??
  process.env.EXPO_PUBLIC_SUPABASE_KEY;

let client: SupabaseClient | undefined;

export function getSupabaseConfiguration() {
  if (!supabaseUrl || !supabasePublishableKey) {
    throw new Error(
      "Supabase is not configured. Add the project URL and publishable key to .env.local, then restart Expo.",
    );
  }

  return {
    supabaseUrl,
    supabasePublishableKey,
  };
}

export function getSupabaseClient() {
  if (client) return client;

  const configuration = getSupabaseConfiguration();

  client = createClient(
    configuration.supabaseUrl,
    configuration.supabasePublishableKey,
    {
      auth: {
        storage: localStorage,
        autoRefreshToken: true,
        persistSession: true,
        detectSessionInUrl: false,
        // Implicit, not the library's default PKCE, and this is the whole
        // reason email links work.
        //
        // PKCE keeps a code_verifier in THIS device's storage and sends the
        // devotee back with `?code=...`, which is only redeemable on the phone
        // that asked for the link. A devotee who requests a reset on their
        // phone and opens the mail on an iPad gets nothing. Worse, the link
        // then carries no access_token at all, so the handler found nothing to
        // do and returned quietly -- a tap that did nothing and said nothing.
        //
        // Implicit returns the session in the URL fragment instead, so the
        // link opens wherever the devotee happens to read their mail. The
        // trade is that tokens ride in the fragment; on a custom scheme handed
        // straight to the app that is a small exposure, and being unable to
        // reset your password at all is a larger one.
        flowType: "implicit",
      },
    },
  );

  return client;
}
