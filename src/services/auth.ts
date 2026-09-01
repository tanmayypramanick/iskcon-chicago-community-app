import type { Session } from "@supabase/supabase-js";
import { makeRedirectUri } from "expo-auth-session";
import * as QueryParams from "expo-auth-session/build/QueryParams";
import * as WebBrowser from "expo-web-browser";

import { getSupabaseClient, getSupabaseConfiguration } from "../lib/supabase";

WebBrowser.maybeCompleteAuthSession();

export const AUTH_CALLBACK_URI = makeRedirectUri({
  scheme: "iskconchicago",
  path: "auth/callback",
});

/**
 * Google sign-in must stay on the custom scheme, and this is not negotiable.
 *
 * `WebBrowser.openAuthSessionAsync` watches for exactly this URL to know the
 * browser sheet is finished and to hand the result back. Point it at an https
 * page and the sheet never closes, the tokens land on a web page instead of in
 * the app, and Google sign-in stops working altogether. Only the *email*
 * redirects move to the web page below.
 */
export const GOOGLE_REDIRECT_URI = AUTH_CALLBACK_URI;

/**
 * Kept because the web page hands recovery back to the app at this address.
 *
 * It is no longer what the reset email redirects to — see
 * `getAuthEmailRedirectUri` — but it is still what the "Open in the ISKCON
 * Chicago app" button on that page builds, so it must stay allow-listed under
 * Authentication -> URL Configuration in Supabase.
 */
export const AUTH_RECOVERY_URI = makeRedirectUri({
  scheme: "iskconchicago",
  path: "auth/recover",
});

/**
 * Where the temple's auth emails send a devotee back to: a web page, not the
 * app's own scheme.
 *
 * The custom scheme was the obvious choice and it was wrong for most devotees.
 * Gmail and Outlook open links inside their own embedded browser, and an
 * embedded browser will not hand `iskconchicago://` to another application —
 * the devotee taps, a browser appears, and nothing happens. On a laptop there
 * is no app at all, so the link could never work there. A password reset that
 * only succeeds if you happen to read your mail in Apple Mail is not a reset.
 *
 * So every email now points at the page in `docs/`, which every mail client
 * will open because it is https, and which finishes the job itself — including
 * setting the new password. Nothing is lost for the devotees the old path
 * already served: that page carries the same tokens straight back to
 * `iskconchicago://auth/recover` or `auth/callback` behind one button.
 *
 * It is on GitHub Pages rather than a Supabase edge function, which is where it
 * started. Supabase will not serve HTML from a function — the platform rewrites
 * the response's content-type to text/plain and its CSP to a bare `sandbox`, an
 * anti-phishing measure on supabase.co — so the devotee was shown the raw
 * markup as text. Pages serves it as a page.
 *
 * Hard-coded rather than derived from the project URL, because it no longer
 * lives on the project. It must stay identical to `CONFIG.pageUrl` in
 * docs/auth-link.js and to the entry allow-listed under Authentication -> URL
 * Configuration; Supabase refuses a `redirect_to` it has not been told about,
 * including on the trailing slash.
 */
export const AUTH_EMAIL_PAGE_URL =
  "https://tanmayypramanick.github.io/iskcon-chicago-community-app/";

export function getAuthEmailRedirectUri(): string {
  return AUTH_EMAIL_PAGE_URL;
}

/**
 * Mirrors `password_min_length` on the Supabase project, which is 6.
 *
 * Every screen that states a rule reads it from here. When the two drifted, the
 * app claimed eight characters while the server accepted six — so the copy was
 * telling devotees something that was not true of the account they were making.
 * If the project setting is ever raised, raise this in the same commit.
 */
export const PASSWORD_MIN_LENGTH = 6;

/**
 * The six digits Supabase puts in every auth email as `{{ .Token }}`.
 *
 * The templates print it beside the button because a button is not enough:
 * Gmail and Outlook open links in their own embedded browser, and an embedded
 * browser will not hand `iskconchicago://` to an app. A code needs no hosting,
 * no scheme and no browser — the devotee reads it and types it.
 */
export const EMAIL_CODE_LENGTH = 6;

/**
 * How long a mailed code stays good, mirroring `mailer_otp_exp` (3600s) on the
 * temple's project. Raise both together if that setting ever changes.
 *
 * This is here because it is the only way the app can tell an expired code from
 * a mistyped one. GoTrue answers a wrong code, a spent code and an hours-old
 * code with the identical `otp_expired` / "Token has expired or is invalid"
 * pair, so the server cannot be asked which it was. When the app knows when the
 * email was requested it can answer that itself.
 */
export const EMAIL_CODE_TTL_MS = 3_600_000;

/** Which email the code came out of, and so which OTP the server must check. */
export type EmailCodePurpose = "recovery" | "signup" | "magicLink";

const EMAIL_OTP_TYPES: Record<
  EmailCodePurpose,
  "recovery" | "signup" | "magiclink"
> = {
  recovery: "recovery",
  signup: "signup",
  magicLink: "magiclink",
};

/**
 * Why a code was not accepted, as a closed set rather than an error — for the
 * same reason `PasswordChangeFailure` is one: a screen that is never handed a
 * Supabase string can never draw one.
 */
export type EmailCodeFailure =
  | "noAddress"
  | "malformed"
  /** Known from this app's own clock to be past its hour; never sent. */
  | "expiredCode"
  /** Refused while still inside its hour, so it was mistyped or already spent. */
  | "wrongCode"
  /** Refused, and the app cannot know which of the three reasons it was. */
  | "codeNotAccepted"
  | "tooManyAttempts"
  | "network"
  | "noSession"
  | "unknown";

export type EmailCodeResult =
  { ok: true; session: Session } | { ok: false; reason: EmailCodeFailure };

function classifyEmailCodeFailure(
  error: unknown,
  requestedAt: number | null | undefined,
): EmailCodeFailure {
  const raw = messageOf(error);
  const status = (error as { status?: number } | null | undefined)?.status;

  if (isNetworkFailure(raw)) return "network";
  if (
    status === 429 ||
    /rate.?limit|too many|over_request|over_email/i.test(raw)
  ) {
    return "tooManyAttempts";
  }

  if (/otp_expired|expired|invalid|not found|token/i.test(raw)) {
    // One server answer, three possible causes. Knowing the email is still
    // inside its hour rules the third out, and lets the screen say something
    // more useful than a list of everything that might have happened.
    const withinTheHour =
      typeof requestedAt === "number" &&
      Date.now() - requestedAt <= EMAIL_CODE_TTL_MS;
    return withinTheHour ? "wrongCode" : "codeNotAccepted";
  }

  return "unknown";
}

/**
 * Exchanges the six digits from an auth email for a session.
 *
 * This is the same hop the tapped link makes, arriving by hand instead: for
 * recovery it produces exactly the session the deep link produces, so both
 * paths can end on the same "Choose a new password" screen rather than becoming
 * two half-finished flows.
 *
 * `requestedAt` is when this app asked for the email, when it knows — it is
 * only ever used to sharpen the wording of a failure, never to allow anything.
 */
export async function verifyEmailCode(input: {
  email: string;
  code: string;
  purpose: EmailCodePurpose;
  requestedAt?: number | null;
}): Promise<EmailCodeResult> {
  const email = input.email.trim();
  // Devotees copy the code with a stray space, or out of a "code: 123456"
  // line. Stripping is kinder than refusing.
  const code = input.code.replace(/\D/g, "");

  if (!email) return { ok: false, reason: "noAddress" };
  if (code.length !== EMAIL_CODE_LENGTH) {
    return { ok: false, reason: "malformed" };
  }

  // Refused here rather than sent. The server would answer a stale code with
  // the string it also uses for a mistyped one, and the devotee would be told
  // to check their typing when the remedy is a fresh email.
  if (
    typeof input.requestedAt === "number" &&
    Date.now() - input.requestedAt > EMAIL_CODE_TTL_MS
  ) {
    return { ok: false, reason: "expiredCode" };
  }

  try {
    const { data, error } = await getSupabaseClient().auth.verifyOtp({
      email,
      token: code,
      type: EMAIL_OTP_TYPES[input.purpose],
    });

    if (error) {
      return {
        ok: false,
        reason: classifyEmailCodeFailure(error, input.requestedAt),
      };
    }
    // A recovery with no session cannot set a password, so an accepted code
    // that produced nothing is a failure here rather than a quiet success.
    if (!data?.session) return { ok: false, reason: "noSession" };
    return { ok: true, session: data.session };
  } catch (error) {
    return {
      ok: false,
      reason: classifyEmailCodeFailure(error, input.requestedAt),
    };
  }
}

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
      emailRedirectTo: getAuthEmailRedirectUri(),
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
    { redirectTo: getAuthEmailRedirectUri() },
  );

  if (error) throw error;
}

/**
 * Turns a signup confirmation, recovery or magic link handed to the app into
 * a signed-in session. Returns null when a valid callback has no session
 * tokens, so unrelated values are ignored rather than reported as failures.
 */
export async function createSessionFromAuthUrl(
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

  // A link that came back as `?code=...` is the PKCE shape. The app asks for
  // implicit links (see src/lib/supabase.ts), so this means the link was made
  // before that changed, or by another client. Saying so beats the silence
  // this used to return -- a devotee tapped something and nothing happened at
  // all, which reads as the app being broken rather than the link being stale.
  if (!accessToken || !refreshToken) {
    if (params.code) {
      throw new Error(
        "That link was made by an older version of the app. Please ask for a new one.",
      );
    }
    return null;
  }

  const { data, error } = await getSupabaseClient().auth.setSession({
    access_token: accessToken,
    refresh_token: refreshToken,
  });
  if (error) throw error;
  return data.session;
}

/** Kept for callers and tests written before signup confirmation used the same handler. */
export const createSessionFromRecoveryUrl = createSessionFromAuthUrl;

/** True when the link is specifically a password recovery. */
export function isRecoveryUrl(url: string): boolean {
  const { params } = QueryParams.getQueryParams(url);
  return params.type === "recovery";
}

/**
 * Which kind of email a link came from. Supabase stamps this as `type` in the
 * fragment, and the four kinds want four different endings: recovery must ask
 * for a new password, a signup or an address change is a verification worth
 * acknowledging, and a magic link is simply a sign-in.
 */
export type AuthLinkKind =
  "recovery" | "signup" | "emailChange" | "magicLink" | "unknown";

export function getAuthLinkKind(url: string): AuthLinkKind {
  const { params } = QueryParams.getQueryParams(url);
  switch (params.type) {
    case "recovery":
      return "recovery";
    case "signup":
    case "invite":
      return "signup";
    case "email_change":
      return "emailChange";
    case "magiclink":
      return "magicLink";
  }

  // No `type` at all is the NORMAL shape of the most likely failure: when a
  // reset link has expired or been spent, Supabase redirects with only
  // `error`, `error_code` and `error_description` — the type is gone.
  //
  // The path still knows. `auth/recover` is built for password recovery and
  // nothing else (docs/auth-link.js:103), so reading it back is not a guess.
  // Without this the screen treats an expired reset as "unknown", and an
  // unknown link is offered no six-digit code — withholding the fallback in
  // exactly the case it was written for.
  if (url.includes("auth/recover")) return "recovery";

  // `auth/callback` deliberately stays "unknown": it carries signup,
  // magic-link, email-change AND Google sign-in, so the path proves nothing
  // and a wrong guess would check the devotee's digits as the wrong type and
  // call a perfectly good code invalid.
  return "unknown";
}

/** True when opening this link proved the devotee owns the address. */
function isVerification(kind: AuthLinkKind) {
  return kind === "signup" || kind === "emailChange";
}

export type AuthLinkProblem = {
  title: string;
  body: string;
  /**
   * Whether a fresh link is the remedy. False for a dropped connection, where
   * the link the devotee already holds is still perfectly good and sending
   * another would only teach them to distrust the first.
   */
  canResend: boolean;
};

/**
 * Turns what Supabase said into what a devotee can act on.
 *
 * The raw strings are written for developers — "Invalid JWT structure" tells
 * somebody standing in the temple lobby nothing at all, and an alert carrying
 * it leaves them with no next step. These three cases cover what actually
 * reaches this code: the link aged out, the link is unusable, or the phone
 * never reached the server.
 */
export function describeAuthLinkProblem(
  error: unknown,
  kind: AuthLinkKind,
): AuthLinkProblem {
  const raw = error instanceof Error ? error.message : String(error ?? "");
  const thing = kind === "recovery" ? "reset link" : "confirmation link";

  if (/network|failed to fetch|timeout|offline/i.test(raw)) {
    return {
      title: "The temple could not be reached",
      body: `Your ${thing} is still good — nothing has been used up. Reconnect and open it again from your email.`,
      canResend: false,
    };
  }

  if (/expired|otp_expired/i.test(raw)) {
    return {
      title: "That link has expired",
      body: `For your protection a ${thing} opens only for a short while. Ask for a fresh one below and it will reach you in a moment.`,
      canResend: true,
    };
  }

  return {
    title: "That link could not be opened",
    // No device claim: implicit links carry the session in the URL, so a
    // devotee may open one on any phone, tablet or computer they read their
    // mail on. The only real limits are that it opens once and does not last
    // forever.
    body: `A ${thing} opens once, and does not last forever. If it has already been used, or has been sitting a while, ask for a fresh one below.`,
    canResend: true,
  };
}

/**
 * What opening a link should lead to. Null means the URL was not ours, or
 * carried no session — an unrelated deep link must pass through in silence
 * rather than be reported to the devotee as a failure.
 */
export type AuthLinkOutcome =
  | { kind: "recovery" }
  | { kind: "verified"; hadSession: boolean }
  | { kind: "problem"; problem: AuthLinkProblem; linkKind: AuthLinkKind }
  | null;

function isAuthLinkUrl(url: string) {
  return url.includes("auth/recover") || url.includes("auth/callback");
}

/**
 * The whole of what a tapped email link means, decided in one place so the
 * gate in App.tsx only has to render the answer.
 *
 * `hadSession` is read before the link is exchanged, because it decides how the
 * confirmation should arrive: a devotee already inside the app should not have
 * it torn away by a full screen.
 *
 * Only signup and email-change links produce a confirmation. A magic link or a
 * Google callback also lands here with a valid session, and announcing "your
 * email is verified" for either would be congratulating somebody on an ordinary
 * sign-in they did not ask to have celebrated.
 */
export async function consumeAuthLink(
  url: string | null,
  { hadSession }: { hadSession: boolean },
): Promise<AuthLinkOutcome> {
  if (!url || !isAuthLinkUrl(url)) return null;

  const linkKind = getAuthLinkKind(url);
  try {
    const session = await createSessionFromAuthUrl(url);
    if (!session) return null;
    if (linkKind === "recovery") return { kind: "recovery" };
    if (isVerification(linkKind)) return { kind: "verified", hadSession };
    return null;
  } catch (error) {
    return {
      kind: "problem",
      problem: describeAuthLinkProblem(error, linkKind),
      linkKind,
    };
  }
}

/**
 * Sends whichever link the devotee was trying to open in the first place.
 *
 * Like `requestPasswordReset`, this must not reveal whether the address has an
 * account: Supabase answers a resend for an unknown address as a success, and
 * the screens above are written to say only that a link is on its way.
 */
export async function requestReplacementLink(
  email: string,
  kind: AuthLinkKind,
): Promise<void> {
  const address = email.trim();
  if (kind === "recovery") {
    await requestPasswordReset(address);
    return;
  }

  const { error } = await getSupabaseClient().auth.resend({
    type: "signup",
    email: address,
    options: { emailRedirectTo: getAuthEmailRedirectUri() },
  });

  // An address that is already confirmed is not a problem the devotee needs
  // reporting — it means they can simply sign in, which the screen already says.
  if (
    error &&
    !/already (been )?confirmed|already registered/i.test(error.message)
  ) {
    throw error;
  }
}

/**
 * What the account signs in with, so a screen can stop guessing.
 *
 * `identities` is the honest answer — it is the list of ways this account can
 * actually authenticate. `app_metadata` is the fallback for a session minted
 * before identities were returned, and it carries the provider under two
 * different keys depending on age, so both are read.
 */
export type AuthAccount = {
  email: string | null;
  /** Every provider connected to the account: "email", "google", … */
  providers: string[];
  /**
   * True when there is an email+password identity to confirm against. False
   * for a devotee who has only ever tapped "Continue with Google" — they have
   * no password here, and asking them for one is asking for something that
   * does not exist.
   */
  hasPassword: boolean;
};

export async function getAuthAccount(): Promise<AuthAccount> {
  const { data, error } = await getSupabaseClient().auth.getUser();
  if (error) throw error;

  const user = data.user;
  if (!user) {
    throw new Error("You are not signed in on this device.");
  }

  const metadata = user.app_metadata as
    { provider?: string; providers?: string[] } | undefined;
  const fromIdentities = (user.identities ?? [])
    .map((identity) => identity.provider)
    .filter(Boolean);
  const fromMetadata =
    metadata?.providers ?? (metadata?.provider ? [metadata.provider] : []);
  const providers = Array.from(
    new Set(fromIdentities.length ? fromIdentities : fromMetadata),
  );

  return {
    email: user.email ?? null,
    providers,
    hasPassword: providers.includes("email"),
  };
}

/**
 * Why a password change did not happen, in terms a screen can turn into a
 * sentence a devotee can act on.
 *
 * Deliberately a closed set rather than an error: Supabase's strings are
 * written for developers, and the only way to guarantee none of them is ever
 * drawn on a screen is for the screen never to be handed one.
 */
export type PasswordChangeFailure =
  | "wrongCurrentPassword"
  | "noPasswordIdentity"
  | "sessionExpired"
  | "sameAsCurrent"
  | "weakPassword"
  | "tooManyAttempts"
  | "network"
  | "unknown";

export type PasswordChangeResult =
  { ok: true } | { ok: false; reason: PasswordChangeFailure };

function messageOf(error: unknown): string {
  if (!error) return "";
  const withCode = error as { code?: string; message?: string };
  return `${withCode.code ?? ""} ${withCode.message ?? ""}`;
}

function isNetworkFailure(raw: string) {
  return /network|failed to fetch|timeout|offline|connection/i.test(raw);
}

function classifyReauthFailure(error: unknown): PasswordChangeFailure {
  const raw = messageOf(error);
  if (isNetworkFailure(raw)) return "network";
  if (/rate.?limit|too many requests|over_request/i.test(raw)) {
    return "tooManyAttempts";
  }
  // The catch-all is deliberately the strict one. Anything the re-authenticate
  // call refused, for a reason we do not recognise, has NOT proved the devotee
  // knows the password — so it must read as a refusal, never as an aside that
  // lets the update run anyway.
  return "wrongCurrentPassword";
}

function classifyUpdateFailure(error: unknown): PasswordChangeFailure {
  const raw = messageOf(error);
  if (isNetworkFailure(raw)) return "network";
  if (/same.?password|should be different/i.test(raw)) return "sameAsCurrent";
  if (
    /weak.?password|password.*(short|length|characters)|pwned|compromis/i.test(
      raw,
    )
  ) {
    return "weakPassword";
  }
  if (/rate.?limit|too many requests|over_request/i.test(raw)) {
    return "tooManyAttempts";
  }
  if (/session|jwt|not authenticated|refresh.?token/i.test(raw)) {
    return "sessionExpired";
  }
  return "unknown";
}

/**
 * Changes the password of the devotee who is already signed in, without
 * sending anybody to their inbox.
 *
 * The temple's project has both `security_update_password_require_reauthentication`
 * and `security_update_password_require_current_password` off, so Supabase
 * would accept `updateUser({ password })` on its own. That is exactly why the
 * current password is checked here: without it, anyone holding an unlocked
 * phone could take the account silently. The check is a real sign-in against
 * the *session's own* email — not an address the devotee typed, which would
 * let a second account's credentials satisfy the gate — so it is the server,
 * not this code, that decides whether the password was right.
 *
 * Every failure path returns. There is no branch on which a rejected or
 * unrecognised re-authentication continues to the update.
 */
export async function changePassword(input: {
  currentPassword: string;
  newPassword: string;
}): Promise<PasswordChangeResult> {
  const supabase = getSupabaseClient();

  const { data: current, error: userError } = await supabase.auth.getUser();
  if (userError) {
    const raw = messageOf(userError);
    return {
      ok: false,
      reason: isNetworkFailure(raw) ? "network" : "sessionExpired",
    };
  }

  const user = current.user;
  if (!user?.email) return { ok: false, reason: "sessionExpired" };

  const identities = (user.identities ?? []).map((one) => one.provider);
  const metadata = user.app_metadata as
    { provider?: string; providers?: string[] } | undefined;
  const providers = identities.length
    ? identities
    : (metadata?.providers ?? (metadata?.provider ? [metadata.provider] : []));
  if (providers.length && !providers.includes("email")) {
    return { ok: false, reason: "noPasswordIdentity" };
  }

  const { data: reauth, error: reauthError } =
    await supabase.auth.signInWithPassword({
      email: user.email,
      password: input.currentPassword,
    });

  if (reauthError) {
    return { ok: false, reason: classifyReauthFailure(reauthError) };
  }
  // A success that produced no session proved nothing, and a session for a
  // different account is not this devotee re-authenticating. Both stop here.
  if (!reauth?.session) return { ok: false, reason: "wrongCurrentPassword" };
  if (reauth.session.user?.id !== user.id) {
    return { ok: false, reason: "wrongCurrentPassword" };
  }

  const { error: updateError } = await supabase.auth.updateUser({
    password: input.newPassword,
  });
  if (updateError) {
    return { ok: false, reason: classifyUpdateFailure(updateError) };
  }

  return { ok: true };
}

export async function setNewPassword(password: string) {
  const { error } = await getSupabaseClient().auth.updateUser({ password });
  if (error) throw error;
}

export async function getCurrentAuthEmail() {
  const { data, error } = await getSupabaseClient().auth.getUser();
  if (error) throw error;
  if (!data.user?.email) {
    throw new Error("No email address is connected to this account.");
  }
  return data.user.email;
}

export async function signOutFromSupabase() {
  const { error } = await getSupabaseClient().auth.signOut();
  if (error) throw error;
}

/**
 * Why a sign-in did not happen, in words a devotee can act on.
 *
 * The same reasoning as describeAuthLinkProblem and PasswordChangeFailure:
 * GoTrue's strings are written for developers, and the only way to be sure
 * none of them is ever drawn on a screen is for the screen never to render
 * one. The sign-in form was the last place still passing error.message
 * straight through, so devotees were being shown "Invalid login credentials"
 * and "For security purposes, you can only request this after 21 seconds".
 */
export function describeSignInFailure(error: unknown): string {
  const text = (
    error instanceof Error
      ? error.message
      : typeof error === "string"
        ? error
        : ""
  )
    .trim()
    .toLowerCase();

  if (!text) return "Something went wrong. Please try again.";

  if (
    text.includes("invalid login credentials") ||
    text.includes("invalid email or password")
  ) {
    return "That email and password do not match. Check both, or use “Forgot password”.";
  }
  if (text.includes("email not confirmed")) {
    return "This address has not been confirmed yet. Open the email we sent, or ask for a new one below.";
  }
  if (text.includes("user already registered") || text.includes("already been registered")) {
    return "There is already an account for this address. Sign in instead, or use “Forgot password”.";
  }
  if (text.includes("email rate limit") || text.includes("you can only request")) {
    return "That was just tried. Please wait a moment and try again.";
  }
  if (text.includes("over_request_rate_limit") || text.includes("too many requests")) {
    return "Too many attempts just now. Please wait a minute and try again.";
  }
  if (text.includes("password should be at least") || text.includes("weak password")) {
    return `Please choose a password of at least ${PASSWORD_MIN_LENGTH} characters.`;
  }
  if (text.includes("cancel")) {
    return "Sign-in was cancelled.";
  }
  if (
    text.includes("network request failed") ||
    text.includes("connection appears to be offline") ||
    text.includes("failed to fetch")
  ) {
    return "Could not reach the temple server. Check your connection and try again.";
  }
  return "Something went wrong. Please try again.";
}
