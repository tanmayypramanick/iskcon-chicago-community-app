import { Ionicons } from "@expo/vector-icons";
import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import { useEffect, useState } from "react";
import {
  ActivityIndicator,
  KeyboardAvoidingView,
  Platform,
  Pressable,
  Text,
  TextInput,
  View,
  type TextInputProps,
} from "react-native";

import tokens from "../../design-tokens.json";
import { Screen, ScreenTitle } from "../components/ui";
import { COMMUNITY_EMAIL } from "../config/contact";
import type { ProfileStackParamList } from "../navigation/types";
import {
  changePassword,
  getAuthAccount,
  PASSWORD_MIN_LENGTH,
  type AuthAccount,
  type PasswordChangeFailure,
} from "../services/auth";

type Props = NativeStackScreenProps<ProfileStackParamList, "ChangePassword">;

/**
 * One sentence per way this can fail, each saying what happened and what to do
 * next.
 *
 * `changePassword` hands back a reason and never an error, so there is no path
 * on which a Supabase string — "Invalid login credentials", "AuthApiError" —
 * can reach a devotee standing in the temple lobby.
 */
const FAILURE_MESSAGE: Record<PasswordChangeFailure, string> = {
  wrongCurrentPassword:
    "That is not your current password. Nothing has been changed — check it and try again.",
  noPasswordIdentity:
    "This account signs in with Google, so there is no password here to change.",
  sessionExpired:
    "You have been signed out. Sign in again, then change your password.",
  sameAsCurrent:
    "That is the password you already have. Choose a different one.",
  weakPassword: `That password was refused as too easy to guess. Choose at least ${PASSWORD_MIN_LENGTH} characters that are not a common word.`,
  tooManyAttempts:
    "Too many attempts just now. Wait a minute, then try once more.",
  network:
    "The temple could not be reached. Your password has not changed — check your connection and try again.",
  unknown:
    "Your password could not be changed just now. Nothing has been altered. Please try again in a moment.",
};

/** The app's field, matched to WelcomeScreen so the two forms read as one. */
function PasswordField({
  icon,
  accessibilityLabel,
  revealed,
  onToggleReveal,
  ...inputProps
}: TextInputProps & {
  icon: keyof typeof Ionicons.glyphMap;
  accessibilityLabel: string;
  revealed: boolean;
  onToggleReveal: () => void;
}) {
  return (
    <View className="h-12 flex-row items-center rounded-pill border border-border bg-white px-4">
      <Ionicons name={icon} size={18} color={tokens.colors.indigo} />
      <TextInput
        className="ml-3 flex-1 py-2 font-sans text-[15px] text-stone"
        placeholderTextColor={tokens.colors.stoneMuted}
        accessibilityLabel={accessibilityLabel}
        secureTextEntry={!revealed}
        autoCapitalize="none"
        autoCorrect={false}
        spellCheck={false}
        {...inputProps}
      />
      <Pressable
        accessibilityRole="button"
        accessibilityLabel={revealed ? "Hide password" : "Show password"}
        hitSlop={12}
        onPress={onToggleReveal}
      >
        <Ionicons
          name={revealed ? "eye-off-outline" : "eye-outline"}
          size={18}
          color={tokens.colors.stoneMuted}
        />
      </Pressable>
    </View>
  );
}

function Notice({
  tone,
  children,
}: {
  tone: "error" | "success";
  children: string;
}) {
  const failed = tone === "error";
  return (
    <View
      className={`mt-4 flex-row items-start rounded-button px-4 py-3 ${
        failed ? "bg-vermilionSoft" : "bg-peacockSoft"
      }`}
      accessibilityLiveRegion="polite"
    >
      <Ionicons
        name={failed ? "alert-circle-outline" : "checkmark-circle-outline"}
        size={20}
        color={failed ? tokens.colors.vermilion : tokens.colors.peacock}
      />
      <Text
        className={`ml-3 min-w-0 flex-1 font-sans text-sm leading-5 ${
          failed ? "text-vermilion" : "text-peacock"
        }`}
      >
        {children}
      </Text>
    </View>
  );
}

/**
 * Changing a password from inside the app, without a trip to the inbox.
 *
 * This used to email a reset link to a devotee who was already signed in —
 * verification they had already done by being here, and on Gmail the link
 * often never came back to the app at all. The current password is the
 * verification instead.
 */
export function ChangePasswordScreen(_: Props) {
  const [account, setAccount] = useState<AuthAccount | null>(null);
  const [loadFailed, setLoadFailed] = useState(false);
  const [loading, setLoading] = useState(true);

  const [currentPassword, setCurrentPassword] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [confirmation, setConfirmation] = useState("");
  const [revealed, setRevealed] = useState(false);

  const [saving, setSaving] = useState(false);
  const [saved, setSaved] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let active = true;
    getAuthAccount()
      .then((value) => {
        if (active) setAccount(value);
      })
      .catch(() => {
        if (active) setLoadFailed(true);
      })
      .finally(() => {
        if (active) setLoading(false);
      });
    return () => {
      active = false;
    };
  }, []);

  const submit = async () => {
    // Guards the second tap of a double-press: `saving` is already true by the
    // time the first press has returned from the first await.
    if (saving) return;

    setError(null);
    setSaved(false);

    if (!currentPassword) {
      setError("Enter your current password to confirm it is you.");
      return;
    }
    if (newPassword.length < PASSWORD_MIN_LENGTH) {
      setError(
        `Your new password needs at least ${PASSWORD_MIN_LENGTH} characters.`,
      );
      return;
    }
    if (newPassword !== confirmation) {
      setError("The two new passwords do not match.");
      return;
    }
    if (newPassword === currentPassword) {
      setError(
        "That is the password you already have. Choose a different one.",
      );
      return;
    }

    setSaving(true);
    try {
      const result = await changePassword({
        currentPassword,
        newPassword,
      });

      if (!result.ok) {
        setError(FAILURE_MESSAGE[result.reason]);
        return;
      }

      setSaved(true);
      setCurrentPassword("");
      setNewPassword("");
      setConfirmation("");
    } catch {
      // changePassword resolves rather than throws; this is the last resort so
      // an unforeseen fault still says something rather than freezing the form.
      setError(FAILURE_MESSAGE.unknown);
    } finally {
      setSaving(false);
    }
  };

  const googleOnly = Boolean(account && !account.hasPassword);
  const canSubmit =
    !saving &&
    Boolean(currentPassword) &&
    Boolean(newPassword) &&
    Boolean(confirmation);

  return (
    <KeyboardAvoidingView
      className="flex-1"
      // Android resizes the window for the keyboard on its own; on iOS the
      // confirm field and the button would sit underneath it.
      behavior={Platform.OS === "ios" ? "padding" : undefined}
    >
      <Screen topInset={false}>
        <ScreenTitle eyebrow="Account security">Change password</ScreenTitle>

        {loading ? (
          <View
            className="rounded-card border border-border bg-white p-card"
            accessibilityLiveRegion="polite"
          >
            <View className="flex-row items-center">
              <ActivityIndicator color={tokens.colors.indigo} />
              <Text className="ml-3 font-sans text-sm text-stoneMuted">
                Checking how you sign in…
              </Text>
            </View>
          </View>
        ) : loadFailed ? (
          <View className="rounded-card border border-border bg-white p-card">
            <Notice tone="error">
              Your account details could not be loaded. Check your connection,
              then open this screen again.
            </Notice>
          </View>
        ) : googleOnly ? (
          // No password exists on this account, so there is nothing to confirm
          // and nothing to replace. Showing the form anyway would be three
          // fields that cannot be filled in truthfully.
          <View className="rounded-card border border-border bg-white p-card">
            <View className="h-12 w-12 items-center justify-center rounded-pill bg-indigoSoft">
              <Ionicons
                name="logo-google"
                size={22}
                color={tokens.colors.indigo}
              />
            </View>
            <Text className="mt-4 font-display text-xl text-stone">
              You sign in with Google
            </Text>
            <Text className="mt-2 font-sans text-sm leading-6 text-stoneMuted">
              This account has no password of its own — Google confirms who you
              are each time you sign in. To change what protects it, change your
              Google Account password in Google&apos;s own settings.
            </Text>
            {account?.email ? (
              <View className="mt-5 rounded-button bg-sandalwood px-4 py-3">
                <Text className="font-sans text-xs uppercase tracking-wider text-stoneMuted">
                  Signed in as
                </Text>
                <Text className="mt-1 font-sans text-base text-indigo">
                  {account.email}
                </Text>
              </View>
            ) : null}
          </View>
        ) : (
          <View className="rounded-card border border-border bg-white p-card">
            <View className="h-12 w-12 items-center justify-center rounded-pill bg-indigoSoft">
              <Ionicons
                name="shield-checkmark-outline"
                size={24}
                color={tokens.colors.indigo}
              />
            </View>
            <Text className="mt-4 font-display text-xl text-stone">
              Choose a new password
            </Text>
            <Text className="mt-2 font-sans text-sm leading-6 text-stoneMuted">
              Confirm the password you use now, then choose the one you would
              like instead — at least {PASSWORD_MIN_LENGTH} characters. It
              changes straight away; no email is involved.
            </Text>

            {account?.email ? (
              <View className="mt-5 rounded-button bg-sandalwood px-4 py-3">
                <Text className="font-sans text-xs uppercase tracking-wider text-stoneMuted">
                  Signed in as
                </Text>
                <Text className="mt-1 font-sans text-base text-indigo">
                  {account.email}
                </Text>
              </View>
            ) : null}

            <View className="mt-5 gap-2">
              <PasswordField
                icon="lock-closed-outline"
                accessibilityLabel="Current password"
                placeholder="Current password"
                value={currentPassword}
                onChangeText={setCurrentPassword}
                revealed={revealed}
                onToggleReveal={() => setRevealed((shown) => !shown)}
                // iOS offers the saved password for this account here, and
                // offers to store the new one below.
                textContentType="password"
                autoComplete="current-password"
              />
              <PasswordField
                icon="key-outline"
                accessibilityLabel="New password"
                placeholder="New password"
                value={newPassword}
                onChangeText={setNewPassword}
                revealed={revealed}
                onToggleReveal={() => setRevealed((shown) => !shown)}
                textContentType="newPassword"
                autoComplete="new-password"
              />
              <PasswordField
                icon="checkmark-circle-outline"
                accessibilityLabel="Confirm new password"
                placeholder="Confirm new password"
                value={confirmation}
                onChangeText={setConfirmation}
                revealed={revealed}
                onToggleReveal={() => setRevealed((shown) => !shown)}
                textContentType="newPassword"
                autoComplete="new-password"
                returnKeyType="done"
                onSubmitEditing={() => void submit()}
              />
            </View>

            {saved ? (
              <Notice tone="success">
                Your password is changed. Use the new one the next time you sign
                in.
              </Notice>
            ) : null}

            {error ? <Notice tone="error">{error}</Notice> : null}

            <Pressable
              className={`mt-5 min-h-touch flex-row items-center justify-center rounded-button bg-marigold px-5 py-3 ${
                canSubmit ? "" : "opacity-60"
              }`}
              accessibilityRole="button"
              accessibilityLabel="Change my password"
              accessibilityState={{ disabled: !canSubmit, busy: saving }}
              disabled={!canSubmit}
              onPress={() => void submit()}
            >
              {saving ? (
                <ActivityIndicator color={tokens.colors.stone} />
              ) : (
                <>
                  <Ionicons
                    name="lock-closed-outline"
                    size={20}
                    color={tokens.colors.stone}
                  />
                  <Text className="ml-2 font-sans-bold text-base text-stone">
                    Change my password
                  </Text>
                </>
              )}
            </Pressable>
          </View>
        )}

        <View className="mt-section flex-row items-start rounded-card border border-border bg-ivory p-card">
          <Ionicons
            name="information-circle-outline"
            size={20}
            color={tokens.colors.peacock}
          />
          <Text className="ml-3 min-w-0 flex-1 font-sans text-sm leading-6 text-stoneMuted">
            The temple will never ask you for your password. Authentic ISKCON
            Chicago emails identify {COMMUNITY_EMAIL} as the sender.
          </Text>
        </View>
      </Screen>
    </KeyboardAvoidingView>
  );
}
