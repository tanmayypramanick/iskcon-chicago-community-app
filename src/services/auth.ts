import type { Session } from "@supabase/supabase-js";
import { makeRedirectUri } from "expo-auth-session";
import * as QueryParams from "expo-auth-session/build/QueryParams";
import * as WebBrowser from "expo-web-browser";

import { getSupabaseClient, getSupabaseConfiguration } from "../lib/supabase";

WebBrowser.maybeCompleteAuthSession();

export const GOOGLE_REDIRECT_URI = makeRedirectUri({
  scheme: "iskconchicago",
  path: "auth/callback",
});

/**
 * Where a password-reset or magic-link email sends the devotee back to.
 *
 * Without this Supabase falls back to the project's Site URL, which is a web
 * address — on a phone that opens a browser that has no way to hand the
 * session to the app, so the link appears to do nothing. This URL must also be
 * allow-listed under Authentication -> URL Configuration in Supabase.
 */
export const AUTH_RECOVERY_URI = makeRedirectUri({
  scheme: "iskconchicago",
  path: "auth/recover",
});

export type AuthProviderAvailability = {
  email: boolean;
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
}): Promise<Session | null> {
  const { data, error } = await getSupabaseClient().auth.signUp({
    email: input.email.trim(),
    password: input.password,
    options: {
      data: {
        full_name: input.name.trim(),
      },
    },
  });

  if (error) throw error;
  return data.session;
}

async function createSessionFromOAuthUrl(url: string) {
  const { errorCode, params } = QueryParams.getQueryParams(url);
  const oauthError =
    params.error_description ?? params.error ?? errorCode ?? undefined;

  if (oauthError) {
    throw new Error(oauthError);
  }

  const accessToken = params.access_token;
  const refreshToken = params.refresh_token;

  if (!accessToken || !refreshToken) {
    throw new Error("Google sign-in did not return a valid session.");
  }

  const { data, error } = await getSupabaseClient().auth.setSession({
    access_token: accessToken,
    refresh_token: refreshToken,
  });

  if (error) throw error;
  return data.session;
}

export async function signInWithGoogle(): Promise<Session | null> {
  const { data, error } = await getSupabaseClient().auth.signInWithOAuth({
    provider: "google",
    options: {
      redirectTo: GOOGLE_REDIRECT_URI,
      skipBrowserRedirect: true,
      queryParams: {
        prompt: "select_account",
      },
    },
  });

  if (error) throw error;
  if (!data.url) {
    throw new Error("Supabase did not return a Google sign-in URL.");
  }

  const result = await WebBrowser.openAuthSessionAsync(
    data.url,
    GOOGLE_REDIRECT_URI,
  );

  if (result.type === "cancel" || result.type === "dismiss") {
    return null;
  }

  if (result.type !== "success") {
    throw new Error("Google sign-in could not be completed.");
  }

  return createSessionFromOAuthUrl(result.url);
}

export async function requestPasswordReset(email: string) {
  const { error } = await getSupabaseClient().auth.resetPasswordForEmail(
    email.trim(),
    { redirectTo: AUTH_RECOVERY_URI },
  );

  if (error) throw error;
}

/**
 * Turns a recovery or magic link the operating system handed us into a signed
 * in session. Returns null for any other link so unrelated deep links are
 * ignored rather than reported as a failure.
 */
export async function createSessionFromRecoveryUrl(
  url: string,
): Promise<Session | null> {
  const { errorCode, params } = QueryParams.getQueryParams(url);
  const failure = params.error_description ?? params.error ?? errorCode;
  if (failure) {
    throw new Error(
      String(failure).replace(/\+/g, " ") ||
        "That link is no longer valid. Please request a new one.",
    );
  }

  const accessToken = params.access_token;
  const refreshToken = params.refresh_token;
  if (!accessToken || !refreshToken) return null;

  const { data, error } = await getSupabaseClient().auth.setSession({
    access_token: accessToken,
    refresh_token: refreshToken,
  });
  if (error) throw error;
  return data.session;
}

/** True when the link is specifically a password recovery. */
export function isRecoveryUrl(url: string): boolean {
  const { params } = QueryParams.getQueryParams(url);
  return params.type === "recovery";
}

export async function setNewPassword(password: string) {
  const { error } = await getSupabaseClient().auth.updateUser({ password });
  if (error) throw error;
}

export async function signOutFromSupabase() {
  const { error } = await getSupabaseClient().auth.signOut();
  if (error) throw error;
}
