import type { Session } from "@supabase/supabase-js";

import { getSupabaseClient, getSupabaseConfiguration } from "../lib/supabase";

export type AuthProviderAvailability = {
  email: boolean;
  phone: boolean;
  google: boolean;
  emailConfirmationRequired: boolean;
};

export async function getAuthProviderAvailability(): Promise<AuthProviderAvailability> {
  const { supabaseUrl, supabasePublishableKey } = getSupabaseConfiguration();
  const response = await fetch(`${supabaseUrl}/auth/v1/settings`, {
    headers: {
      apikey: supabasePublishableKey,
    },
  });

  if (!response.ok) {
    throw new Error("Could not read the Supabase authentication settings.");
  }

  const settings = (await response.json()) as {
    external?: Record<string, boolean>;
    mailer_autoconfirm?: boolean;
  };

  return {
    email: Boolean(settings.external?.email),
    phone: Boolean(settings.external?.phone),
    google: Boolean(settings.external?.google),
    emailConfirmationRequired: !settings.mailer_autoconfirm,
  };
}

export async function signInWithEmail(email: string, password: string) {
  const { data, error } = await getSupabaseClient().auth.signInWithPassword({
    email: email.trim(),
    password,
  });

  if (error) throw error;
  return data.session;
}

export async function signUpWithEmail(input: {
  name: string;
  email: string;
  password: string;
  phone: string;
}): Promise<Session | null> {
  const { data, error } = await getSupabaseClient().auth.signUp({
    email: input.email.trim(),
    password: input.password,
    options: {
      data: {
        full_name: input.name.trim(),
        phone_pending: input.phone.trim(),
      },
    },
  });

  if (error) throw error;
  return data.session;
}

export async function requestPhoneVerification(phone: string) {
  const { error } = await getSupabaseClient().auth.updateUser({
    phone: phone.trim(),
  });

  if (error) throw error;
}

export async function verifyPhoneChange(phone: string, token: string) {
  const { error } = await getSupabaseClient().auth.verifyOtp({
    phone: phone.trim(),
    token: token.trim(),
    type: "phone_change",
  });

  if (error) throw error;
}

export async function requestPasswordReset(email: string) {
  const { error } = await getSupabaseClient().auth.resetPasswordForEmail(
    email.trim(),
  );

  if (error) throw error;
}

export async function signOutFromSupabase() {
  const { error } = await getSupabaseClient().auth.signOut();
  if (error) throw error;
}
