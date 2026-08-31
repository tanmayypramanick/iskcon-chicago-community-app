import { Ionicons } from "@expo/vector-icons";
import { useState } from "react";
import {
  ActivityIndicator,
  KeyboardAvoidingView,
  Platform,
  Pressable,
  ScrollView,
  Text,
  TextInput,
  View,
} from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";

import tokens from "../../design-tokens.json";
import { PASSWORD_MIN_LENGTH, setNewPassword } from "../services/auth";

/**
 * Says what actually went wrong when saving fails.
 *
 * Supabase's own strings are written for developers, and the one that reaches
 * devotees most often — the recovery session lapsing while the form sat open —
 * arrives as "Auth session missing!", which reads as a fault in the app rather
 * than a link that needs asking for again.
 */
function describeSaveFailure(error: unknown) {
  const raw = error instanceof Error ? error.message : "";

  if (/session|jwt|not authenticated/i.test(raw)) {
    return "Your reset link has lapsed before this could be saved. Ask for a new link and choose your password again.";
  }
  if (/same.*password|should be different/i.test(raw)) {
    return "That is the password you already have. Choose a different one.";
  }
  if (/weak.?password|pwned|compromis/i.test(raw)) {
    return `That password was refused as too easy to guess. Choose at least ${PASSWORD_MIN_LENGTH} characters that are not a common word.`;
  }
  if (/network|failed to fetch|timeout/i.test(raw)) {
    return "The temple could not be reached. Check your connection and try again.";
  }
  return "That password could not be saved. Please try again.";
}

/**
 * The one message slot this form has, matching WelcomeScreen's.
 *
 * Drawn on a tinted panel rather than as a coloured line, because the colour
 * alone is what failed here before: the class named a colour the tokens do not
 * have, NativeWind dropped it, and every failure was rendered as ordinary body
 * text. A panel and an icon still read as a problem if a colour goes missing.
 */
function FormMessage({ text }: { text: string }) {
  return (
    <View
      className="mt-3 flex-row items-start rounded-card bg-vermilionSoft px-3 py-2"
      accessibilityLiveRegion="assertive"
    >
      <Ionicons
        name="alert-circle-outline"
        size={16}
        color={tokens.colors.vermilion}
      />
      <Text className="ml-2 min-w-0 flex-1 font-sans text-sm leading-5 text-vermilion">
        {text}
      </Text>
    </View>
  );
}

/**
 * Shown when a devotee opens a password-reset link. By the time this appears
 * the recovery token has already been exchanged for a session, so the devotee
 * is technically signed in — but they still do not know their password, and
 * leaving them in the app without setting one means the next sign-in fails the
 * same way. So this stands in front of everything until a password is set.
 *
 * `onCancel` is the way out, and it is a sign-out rather than a dismissal.
 * There is no screen behind this one to return to, and the state it would
 * return them to is the odd one: signed in on a link, holding a password they
 * do not know, one app restart away from being locked out with no warning.
 * Signing out puts them somewhere coherent — the sign-in screen, account
 * untouched, free to use their old password or ask for a fresh link.
 */
export function SetNewPasswordScreen({
  onDone,
  onCancel,
}: {
  onDone: () => void;
  onCancel: () => void | Promise<void>;
}) {
  const [password, setPassword] = useState("");
  const [confirmation, setConfirmation] = useState("");
  const [visible, setVisible] = useState(false);
  const [message, setMessage] = useState("");
  const [saving, setSaving] = useState(false);
  const [leaving, setLeaving] = useState(false);
  const [saved, setSaved] = useState(false);

  const busy = saving || leaving;

  const submit = async () => {
    // A second tap while the first is in flight would send a second update.
    if (busy) return;
    setMessage("");

    if (password.length < PASSWORD_MIN_LENGTH) {
      setMessage(`Use at least ${PASSWORD_MIN_LENGTH} characters.`);
      return;
    }
    if (password !== confirmation) {
      setMessage("Both passwords must match.");
      return;
    }

    setSaving(true);
    try {
      await setNewPassword(password);
      // Saving used to drop straight into the app, which looks the same as the
      // screen giving up. A devotee who has just changed the key to their
      // account should be told plainly that it took.
      setSaved(true);
    } catch (error) {
      setMessage(describeSaveFailure(error));
    } finally {
      setSaving(false);
    }
  };

  const leave = async () => {
    if (busy) return;
    setMessage("");
    setLeaving(true);
    try {
      await onCancel();
    } catch {
      setMessage(
        "You could not be signed out just now. Check your connection and try again.",
      );
      setLeaving(false);
    }
  };

  if (saved) {
    return (
      <SafeAreaView className="flex-1 bg-ivory" edges={["top", "bottom"]}>
        <View className="flex-1 justify-center px-6">
          <View
            className="w-full max-w-[430px] self-center items-center"
            accessibilityLiveRegion="polite"
          >
            <View className="h-16 w-16 items-center justify-center rounded-pill bg-peacockSoft">
              <Ionicons
                name="checkmark-circle"
                size={34}
                color={tokens.colors.peacock}
              />
            </View>
            <Text
              className="mt-5 text-center font-display text-2xl text-indigo"
              accessibilityRole="header"
            >
              Your new password is saved
            </Text>
            <Text className="mt-3 text-center font-sans text-sm leading-6 text-stoneMuted">
              Use it the next time you sign in. Hare Kṛṣṇa.
            </Text>
            <Pressable
              className="mt-6 h-12 w-full flex-row items-center justify-center rounded-pill bg-marigold"
              accessibilityRole="button"
              accessibilityLabel="Continue to the app"
              onPress={onDone}
            >
              <Text className="font-sans-bold text-base text-indigo">
                Continue to the app
              </Text>
            </Pressable>
          </View>
        </View>
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView className="flex-1 bg-ivory" edges={["top", "bottom"]}>
      <KeyboardAvoidingView
        className="flex-1"
        behavior={Platform.OS === "ios" ? "padding" : "height"}
      >
        {/* Centred when it fits, scrollable when the keyboard means it does
            not: on a short phone the confirm field and the button were both
            under the keyboard with no way to reach them. */}
        <ScrollView
          className="flex-1"
          contentContainerStyle={{ flexGrow: 1, justifyContent: "center" }}
          keyboardShouldPersistTaps="handled"
          keyboardDismissMode="interactive"
          showsVerticalScrollIndicator={false}
        >
          <View className="w-full max-w-[430px] self-center px-6 py-8">
            <View className="mb-6 h-14 w-14 items-center justify-center rounded-pill bg-indigoSoft">
              <Ionicons
                name="lock-open-outline"
                size={26}
                color={tokens.colors.indigo}
              />
            </View>

            <Text
              className="font-display text-2xl text-stone"
              accessibilityRole="header"
            >
              Choose a new password
            </Text>
            <Text className="mt-2 font-sans text-sm leading-5 text-stoneMuted">
              You are signed in from your email link. Choose a password so you
              can sign in normally next time — at least {PASSWORD_MIN_LENGTH}{" "}
              characters.
            </Text>

            <View className="mt-6 flex-row items-center rounded-card border border-border bg-white px-4">
              <Ionicons
                name="lock-closed-outline"
                size={18}
                color={tokens.colors.stoneMuted}
              />
              <TextInput
                className="ml-3 h-12 flex-1 font-sans text-base text-stone"
                accessibilityLabel="New password"
                placeholder="New password"
                placeholderTextColor={tokens.colors.stoneMuted}
                value={password}
                onChangeText={setPassword}
                secureTextEntry={!visible}
                autoCapitalize="none"
                autoCorrect={false}
                spellCheck={false}
                textContentType="newPassword"
                autoComplete="new-password"
              />
              <Pressable
                accessibilityRole="button"
                accessibilityLabel={visible ? "Hide password" : "Show password"}
                hitSlop={12}
                onPress={() => setVisible((shown) => !shown)}
              >
                <Ionicons
                  name={visible ? "eye-off-outline" : "eye-outline"}
                  size={18}
                  color={tokens.colors.stoneMuted}
                />
              </Pressable>
            </View>

            <View className="mt-2 flex-row items-center rounded-card border border-border bg-white px-4">
              <Ionicons
                name="checkmark-circle-outline"
                size={18}
                color={tokens.colors.stoneMuted}
              />
              <TextInput
                className="ml-3 h-12 flex-1 font-sans text-base text-stone"
                accessibilityLabel="Confirm new password"
                placeholder="Confirm new password"
                placeholderTextColor={tokens.colors.stoneMuted}
                value={confirmation}
                onChangeText={setConfirmation}
                secureTextEntry={!visible}
                autoCapitalize="none"
                autoCorrect={false}
                spellCheck={false}
                textContentType="newPassword"
                autoComplete="new-password"
                returnKeyType="done"
                onSubmitEditing={() => void submit()}
              />
            </View>

            {message ? <FormMessage text={message} /> : null}

            <Pressable
              className={`mt-5 h-12 flex-row items-center justify-center rounded-pill bg-marigold ${
                busy ? "opacity-60" : ""
              }`}
              accessibilityRole="button"
              accessibilityLabel="Save new password"
              accessibilityState={{ disabled: busy, busy: saving }}
              disabled={busy}
              onPress={() => void submit()}
            >
              {saving ? (
                <ActivityIndicator color={tokens.colors.indigo} />
              ) : (
                <Text className="font-sans-bold text-base text-indigo">
                  Save password
                </Text>
              )}
            </Pressable>

            <Pressable
              className={`mt-2 h-12 flex-row items-center justify-center rounded-pill border border-border bg-white ${
                busy ? "opacity-60" : ""
              }`}
              accessibilityRole="button"
              accessibilityLabel="Cancel and sign out"
              accessibilityState={{ disabled: busy, busy: leaving }}
              disabled={busy}
              onPress={() => void leave()}
            >
              {leaving ? (
                <ActivityIndicator color={tokens.colors.indigo} />
              ) : (
                <>
                  <Ionicons
                    name="log-out-outline"
                    size={18}
                    color={tokens.colors.indigo}
                  />
                  <Text className="ml-2 font-sans-bold text-base text-indigo">
                    Cancel and sign out
                  </Text>
                </>
              )}
            </Pressable>
            <Text className="mt-2 text-center font-sans text-xs leading-4 text-stoneMuted">
              Your password stays as it is, and you return to the sign-in
              screen. Ask for a fresh link whenever you are ready.
            </Text>
          </View>
        </ScrollView>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}
