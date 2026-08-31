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
import { COMMUNITY_EMAIL } from "../config/contact";
import {
  requestReplacementLink,
  type AuthLinkKind,
  type AuthLinkProblem,
  type EmailCodePurpose,
} from "../services/auth";
import { EmailCodeScreen, type EmailCodeOutcome } from "./EmailCodeScreen";

/**
 * Which OTP the six digits in that email belong to.
 *
 * Null for the two kinds that have no code to offer: the change-email template
 * deliberately carries none, and an "unknown" link never said what it was, so
 * guessing would send the devotee's digits to be checked as the wrong type and
 * report a perfectly good code as wrong.
 */
function codePurposeFor(kind: AuthLinkKind): EmailCodePurpose | null {
  switch (kind) {
    case "recovery":
      return "recovery";
    case "signup":
      return "signup";
    case "magicLink":
      return "magicLink";
    default:
      return null;
  }
}

/**
 * What a devotee sees when an email link does not open.
 *
 * This replaces an Alert that carried the raw Supabase string — "Invalid JWT
 * structure" — and then dropped the devotee back where they started with no way
 * forward. An expired or spent link is the single most likely failure in this
 * whole flow, so the remedy lives on this screen: type the address, tap once, a
 * fresh link is sent. Making them find the sign-in screen and remember which of
 * the two links they needed is how somebody gives up.
 */
export function AuthLinkProblemScreen({
  problem,
  linkKind,
  onDismiss,
  onVerified,
}: {
  problem: AuthLinkProblem;
  linkKind: AuthLinkKind;
  onDismiss: () => void;
  /**
   * A code was accepted here instead of the link. "recovery" has to raise the
   * same "Choose a new password" gate the link would have raised — this screen
   * has nothing behind it, so only App.tsx can do that.
   */
  onVerified: (outcome: EmailCodeOutcome) => void;
}) {
  const [email, setEmail] = useState("");
  const [sending, setSending] = useState(false);
  const [sent, setSent] = useState(false);
  const [sentAt, setSentAt] = useState<number | null>(null);
  const [error, setError] = useState("");
  const [enteringCode, setEnteringCode] = useState(false);
  const codePurpose = codePurposeFor(linkKind);

  const sendAnother = async () => {
    setError("");
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email.trim())) {
      setError("Enter a valid email address.");
      return;
    }

    setSending(true);
    try {
      await requestReplacementLink(email, linkKind);
      setSentAt(Date.now());
      setSent(true);
    } catch (caught) {
      setError(
        caught instanceof Error
          ? "The link could not be sent just now. Check your connection and try once more."
          : "The link could not be sent just now. Please try once more.",
      );
    } finally {
      setSending(false);
    }
  };

  // This screen is where a devotee lands when a link fails, so it is exactly
  // where the code has to be reachable. The address they may have typed for a
  // replacement is carried across rather than asked for a second time.
  if (enteringCode && codePurpose) {
    return (
      <EmailCodeScreen
        purpose={codePurpose}
        email={email.trim() || null}
        requestedAt={sentAt}
        onCancel={() => setEnteringCode(false)}
        onVerified={onVerified}
      />
    );
  }

  return (
    <SafeAreaView className="flex-1 bg-sandalwood" edges={["top", "bottom"]}>
      <KeyboardAvoidingView
        className="flex-1"
        behavior={Platform.OS === "ios" ? "padding" : "height"}
      >
        <ScrollView
          contentContainerStyle={{ flexGrow: 1, justifyContent: "center" }}
          keyboardShouldPersistTaps="handled"
          showsVerticalScrollIndicator={false}
        >
          <View className="px-6 py-6">
            <View className="w-full max-w-[430px] self-center rounded-[28px] border border-border bg-ivory px-6 py-7">
              <View className="h-14 w-14 items-center justify-center rounded-pill bg-vermilionSoft">
                <Ionicons
                  name="link-outline"
                  size={26}
                  color={tokens.colors.vermilion}
                />
              </View>

              <Text
                className="mt-5 font-display text-[23px] leading-7 text-indigo"
                accessibilityRole="header"
              >
                {problem.title}
              </Text>
              <Text className="mt-3 font-sans text-sm leading-6 text-stoneMuted">
                {problem.body}
              </Text>

              {problem.canResend ? (
                sent ? (
                  // Deliberately says only that a link is on its way. Naming
                  // whether the address has an account here would give away in
                  // the app exactly what Supabase refuses to give away over the
                  // wire.
                  <View
                    className="mt-6 flex-row items-start rounded-button bg-peacockSoft px-4 py-3"
                    accessibilityLiveRegion="polite"
                  >
                    <Ionicons
                      name="mail-open-outline"
                      size={20}
                      color={tokens.colors.peacock}
                    />
                    <Text className="ml-3 min-w-0 flex-1 font-sans text-sm leading-5 text-peacock">
                      If that address is with us, a new link is on its way from{" "}
                      {COMMUNITY_EMAIL}. Open it on this phone.
                    </Text>
                  </View>
                ) : (
                  <>
                    <Text className="mt-6 font-sans-bold text-xs uppercase tracking-wider text-stoneMuted">
                      Send me a new link
                    </Text>
                    <View className="mt-2 h-12 flex-row items-center rounded-pill border border-border bg-white px-4">
                      <Ionicons
                        name="mail-outline"
                        size={18}
                        color={tokens.colors.indigo}
                      />
                      <TextInput
                        className="ml-3 flex-1 font-sans text-[15px] text-stone"
                        accessibilityLabel="Email address for a new link"
                        placeholder="Email address"
                        placeholderTextColor={tokens.colors.stoneMuted}
                        value={email}
                        onChangeText={setEmail}
                        autoCapitalize="none"
                        keyboardType="email-address"
                        textContentType="emailAddress"
                      />
                    </View>

                    {error ? (
                      <Text
                        className="mt-2 font-sans text-xs text-vermilion"
                        accessibilityLiveRegion="polite"
                      >
                        {error}
                      </Text>
                    ) : null}

                    <Pressable
                      className={`mt-3 h-12 flex-row items-center justify-center rounded-pill bg-marigold ${
                        sending ? "opacity-60" : ""
                      }`}
                      accessibilityRole="button"
                      accessibilityLabel="Send me a new link"
                      accessibilityState={{ disabled: sending, busy: sending }}
                      disabled={sending}
                      onPress={sendAnother}
                    >
                      {sending ? (
                        <ActivityIndicator color={tokens.colors.indigo} />
                      ) : (
                        <Text className="font-sans-bold text-base text-indigo">
                          Send me a new link
                        </Text>
                      )}
                    </Pressable>
                  </>
                )
              ) : null}

              {codePurpose ? (
                <>
                  <View className="mt-5 h-px bg-border" />
                  <Text className="mt-4 font-sans text-xs leading-5 text-stoneMuted">
                    That email also carries a six-digit code, printed beside the
                    button. A code needs no browser at all.
                  </Text>
                  <Pressable
                    className="mt-2 h-11 flex-row items-center justify-center rounded-pill border border-border bg-white"
                    accessibilityRole="button"
                    accessibilityLabel="Enter a code instead"
                    onPress={() => setEnteringCode(true)}
                  >
                    <Ionicons
                      name="keypad-outline"
                      size={18}
                      color={tokens.colors.indigo}
                    />
                    <Text className="ml-2 font-sans-bold text-sm text-indigo">
                      Enter a code instead
                    </Text>
                  </Pressable>
                </>
              ) : null}

              <Pressable
                className="mt-4 h-9 items-center justify-center"
                accessibilityRole="button"
                accessibilityLabel="Back to sign in"
                hitSlop={10}
                onPress={onDismiss}
              >
                <Text className="font-sans-bold text-sm text-indigo">
                  Back to sign in
                </Text>
              </Pressable>
            </View>

            {/* Honest about a limitation we cannot fix from here: Gmail's
                in-app browser often refuses to hand a custom scheme to the
                app, and a devotee whose link "does nothing" deserves to know
                where to open it instead of assuming the app is broken. */}
            <View className="mt-4 w-full max-w-[430px] flex-row items-start self-center rounded-card border border-border bg-ivory px-4 py-3">
              <Ionicons
                name="information-circle-outline"
                size={18}
                color={tokens.colors.peacock}
              />
              <Text className="ml-3 min-w-0 flex-1 font-sans text-xs leading-5 text-stoneMuted">
                If the link opened a browser instead of the app, open the same
                email in Mail or Safari and tap it there.
              </Text>
            </View>
          </View>
        </ScrollView>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}
