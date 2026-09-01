import { Ionicons } from "@expo/vector-icons";
import { useRef, useState } from "react";
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
  EMAIL_CODE_LENGTH,
  PASSWORD_MIN_LENGTH,
  requestReplacementLink,
  verifyEmailCode,
  type EmailCodeFailure,
  type EmailCodePurpose,
} from "../services/auth";

/**
 * Where verifying a code leaves the devotee. "recovery" must end on *Choose a
 * new password*, exactly where the deep link ends — anything else would leave
 * them signed in holding a password they still do not know.
 */
export type EmailCodeOutcome = "recovery" | "signedIn";

const WORDING: Record<
  EmailCodePurpose,
  { title: string; lead: string; action: string }
> = {
  recovery: {
    title: "Enter your reset code",
    lead: "choose a new password",
    action: "Continue to a new password",
  },
  signup: {
    title: "Enter your confirmation code",
    lead: "confirm your email and come in",
    action: "Confirm my email",
  },
  magicLink: {
    title: "Enter your sign-in code",
    lead: "sign in without a password",
    action: "Sign me in",
  },
};

/**
 * Says what actually happened, in a sentence with a next step in it.
 *
 * Three of these are deliberately different from one another because a devotee
 * acts on them differently: a wrong code means look again, an expired one means
 * ask for another, and a rate limit means wait — telling all three "that code
 * was not accepted" would send two of them round a loop that cannot work.
 */
export function describeEmailCodeFailure(reason: EmailCodeFailure): string {
  switch (reason) {
    case "noAddress":
      return "Enter the email address the code was sent to.";
    case "malformed":
      return `Enter all ${EMAIL_CODE_LENGTH} digits from the email.`;
    case "expiredCode":
      return "That code was sent more than an hour ago, so it has expired. Ask for a fresh one below and it will reach you in a moment.";
    case "wrongCode":
      return "Those digits were not right, or that code has already been used. Check the most recent email — asking for another replaces the one before it.";
    case "codeNotAccepted":
      return "That code was not accepted. It may have been mistyped, already used, or older than an hour. Ask for a fresh one below and try again.";
    case "tooManyAttempts":
      return "Too many tries just now. Wait a few minutes before entering another code — there is nothing wrong with your account.";
    case "network":
      return "The temple could not be reached. Your code is still good — reconnect and try again.";
    case "noSession":
      return "That code was accepted but did not finish signing you in. Ask for a fresh one below and try once more.";
    default:
      return "That code could not be checked just now. Please try again.";
  }
}

/**
 * The one message slot this screen has, matching WelcomeScreen's.
 *
 * Drawn on a tinted panel with an icon rather than as a coloured line: a class
 * naming a colour the tokens do not have is dropped silently by NativeWind, and
 * when that happened on a password screen every failure rendered as ordinary
 * body text. Every colour here is in design-tokens.json.
 */
function FormMessage({
  text,
  tone,
}: {
  text: string;
  tone: "error" | "success";
}) {
  const failed = tone === "error";
  return (
    <View
      className={`mt-3 flex-row items-start rounded-card px-3 py-2 ${
        failed ? "bg-vermilionSoft" : "bg-peacockSoft"
      }`}
      // Assertive for a refusal, because it is the answer to something the
      // devotee just did and they are waiting on it; polite for a confirmation.
      accessibilityLiveRegion={failed ? "assertive" : "polite"}
      accessibilityRole="alert"
      // Groups the icon and the sentence into one announcement, so a screen
      // reader reads the whole message rather than an unlabelled glyph.
      accessible
    >
      <Ionicons
        name={failed ? "alert-circle-outline" : "checkmark-circle-outline"}
        size={16}
        color={failed ? tokens.colors.vermilion : tokens.colors.peacock}
      />
      <Text
        className={`ml-2 min-w-0 flex-1 font-sans text-sm leading-5 ${
          failed ? "text-vermilion" : "text-peacock"
        }`}
      >
        {text}
      </Text>
    </View>
  );
}

/**
 * The fallback for every devotee the email button cannot reach.
 *
 * Gmail and Outlook open links inside their own embedded browser, and an
 * embedded browser refuses to hand a custom scheme to an app — the devotee taps
 * and nothing happens. On a laptop there is no app to hand it to at all. So the
 * same auth emails carry the six digits Supabase already generates, and this
 * screen spends them on `verifyOtp`, reaching the identical session the link
 * would have produced.
 *
 * It is a fallback, not a replacement: the button is still there and is still
 * one tap for the devotees it works for.
 *
 * `email` is carried in from wherever the devotee just typed it — asking for it
 * twice, on the screen they reached *because* something already failed, is how
 * somebody gives up. When it is genuinely unknown (a link opened cold, with no
 * request behind it) the screen asks, and says why.
 */
export function EmailCodeScreen({
  purpose,
  email: knownEmail,
  requestedAt,
  onVerified,
  onCancel,
  cancelLabel = "Back to sign in",
}: {
  purpose: EmailCodePurpose;
  /** The address the code was sent to, when the previous screen knows it. */
  email?: string | null;
  /** When this app asked for that email, if it did. Sharpens the failures. */
  requestedAt?: number | null;
  onVerified: (outcome: EmailCodeOutcome) => void;
  onCancel: () => void;
  /**
   * Where cancelling actually lands, in the caller's own words. Cancelling
   * returns to whichever screen opened this one, and that is not always the
   * sign-in form: from the failed-link screen it goes back to the failed-link
   * screen. Naming the destination wrongly is worse than not naming it, so
   * each caller states its own.
   */
  cancelLabel?: string;
}) {
  const carried = (knownEmail ?? "").trim();
  const [address, setAddress] = useState(carried);
  const [editingAddress, setEditingAddress] = useState(!carried);
  const [code, setCode] = useState("");
  const [sentAt, setSentAt] = useState<number | null>(requestedAt ?? null);
  const [message, setMessage] = useState("");
  const [tone, setTone] = useState<"error" | "success">("error");
  const [verifying, setVerifying] = useState(false);
  const [resending, setResending] = useState(false);
  // The exact digits an auto-submit was already spent on. Without it a refused
  // code re-submits itself on every keystroke that returns to six characters,
  // which fights the devotee correcting it.
  const autoSubmitted = useRef("");

  const words = WORDING[purpose];
  const busy = verifying || resending;

  const fail = (text: string) => {
    setTone("error");
    setMessage(text);
  };

  const submit = async (digits: string) => {
    if (busy) return;
    setMessage("");
    setVerifying(true);
    try {
      const result = await verifyEmailCode({
        email: address,
        code: digits,
        purpose,
        requestedAt: sentAt,
      });

      if (!result.ok) {
        fail(describeEmailCodeFailure(result.reason));
        if (result.reason === "noAddress") setEditingAddress(true);
        return;
      }

      onVerified(purpose === "recovery" ? "recovery" : "signedIn");
    } catch {
      // `verifyEmailCode` answers with a reason rather than throwing, so this
      // is only reached if something above it breaks. Saying so beats a button
      // that spins and then does nothing at all.
      fail(describeEmailCodeFailure("unknown"));
    } finally {
      setVerifying(false);
    }
  };

  /**
   * Auto-submits only on the keystroke that completes a code we have not tried
   * yet. A devotee still typing, correcting, or re-reading their email is never
   * interrupted by a request they did not ask for.
   */
  const changeCode = (next: string) => {
    const digits = next.replace(/\D/g, "").slice(0, EMAIL_CODE_LENGTH);
    const completedNow =
      digits.length === EMAIL_CODE_LENGTH && code.length < EMAIL_CODE_LENGTH;
    setCode(digits);
    if (message && tone === "error") setMessage("");

    if (completedNow && digits !== autoSubmitted.current && address.trim()) {
      autoSubmitted.current = digits;
      void submit(digits);
    }
  };

  const sendAnother = async () => {
    if (busy) return;
    setMessage("");
    if (!address.trim()) {
      setEditingAddress(true);
      fail(describeEmailCodeFailure("noAddress"));
      return;
    }

    setResending(true);
    try {
      await requestReplacementLink(
        address,
        purpose === "recovery" ? "recovery" : "signup",
      );
      setSentAt(Date.now());
      setCode("");
      autoSubmitted.current = "";
      setTone("success");
      // Says only that something is on its way. Naming whether the address has
      // an account would give away in the app what Supabase refuses to give
      // away over the wire.
      setMessage(
        `If that address is with us, a new email with a fresh code is on its way from ${COMMUNITY_EMAIL}.`,
      );
    } catch {
      fail(
        "A new code could not be sent just now. Check your connection and try again.",
      );
    } finally {
      setResending(false);
    }
  };

  return (
    <SafeAreaView className="flex-1 bg-sandalwood" edges={["top", "bottom"]}>
      <KeyboardAvoidingView
        className="flex-1"
        behavior={Platform.OS === "ios" ? "padding" : "height"}
      >
        <ScrollView
          contentContainerStyle={{ flexGrow: 1, justifyContent: "center" }}
          keyboardShouldPersistTaps="handled"
          keyboardDismissMode="interactive"
          showsVerticalScrollIndicator={false}
        >
          <View className="px-6 py-6">
            <View className="w-full max-w-[430px] self-center rounded-[28px] border border-border bg-ivory px-6 py-7">
              <View className="h-14 w-14 items-center justify-center rounded-pill bg-indigoSoft">
                <Ionicons
                  name="keypad-outline"
                  size={26}
                  color={tokens.colors.indigo}
                />
              </View>

              <Text
                className="mt-5 font-display text-[23px] leading-7 text-indigo"
                accessibilityRole="header"
              >
                {words.title}
              </Text>

              {carried && !editingAddress ? (
                <>
                  <Text className="mt-3 font-sans text-sm leading-6 text-stoneMuted">
                    The email sent to {carried} carries {EMAIL_CODE_LENGTH}{" "}
                    digits beside the button. Type them here and you can{" "}
                    {words.lead}
                    {purpose === "recovery"
                      ? ` of at least ${PASSWORD_MIN_LENGTH} characters`
                      : ""}
                    .
                  </Text>
                  <Pressable
                    className="mt-1 h-8 justify-center"
                    accessibilityRole="button"
                    accessibilityLabel="Use a different email address"
                    hitSlop={10}
                    onPress={() => setEditingAddress(true)}
                  >
                    <Text className="font-sans-bold text-xs text-indigo">
                      Use a different email address
                    </Text>
                  </Pressable>
                </>
              ) : (
                <>
                  {/* Reached cold — from a link that failed before anything was
                      typed — so the address is genuinely unknown. Saying why we
                      are asking keeps it from reading as a pointless second
                      form. */}
                  <Text className="mt-3 font-sans text-sm leading-6 text-stoneMuted">
                    Tell us which address the email went to, then type the{" "}
                    {EMAIL_CODE_LENGTH} digits printed beside the button in it.
                  </Text>
                  <View className="mt-4 h-12 flex-row items-center rounded-pill border border-border bg-white px-4">
                    <Ionicons
                      name="mail-outline"
                      size={18}
                      color={tokens.colors.indigo}
                    />
                    <TextInput
                      className="ml-3 flex-1 font-sans text-[15px] text-stone"
                      accessibilityLabel="Email address the code was sent to"
                      placeholder="Email address"
                      placeholderTextColor={tokens.colors.stoneMuted}
                      value={address}
                      onChangeText={setAddress}
                      autoCapitalize="none"
                      autoCorrect={false}
                      keyboardType="email-address"
                      textContentType="emailAddress"
                      editable={!busy}
                    />
                  </View>
                </>
              )}

              <Text className="mt-5 font-sans-bold text-xs uppercase tracking-wider text-stoneMuted">
                Your {EMAIL_CODE_LENGTH}-digit code
              </Text>
              <View className="mt-2 h-14 flex-row items-center rounded-card border border-border bg-white px-4">
                <TextInput
                  className="flex-1 text-center font-sans-bold text-[26px] tracking-[10px] text-indigo"
                  accessibilityLabel={`${EMAIL_CODE_LENGTH}-digit code from your email`}
                  placeholder="000000"
                  placeholderTextColor={tokens.colors.border}
                  value={code}
                  onChangeText={changeCode}
                  keyboardType="number-pad"
                  inputMode="numeric"
                  maxLength={EMAIL_CODE_LENGTH}
                  // Lets iOS and Android offer the code straight from the
                  // notification, and makes a paste land whole.
                  textContentType="oneTimeCode"
                  autoComplete="one-time-code"
                  autoCorrect={false}
                  editable={!busy}
                  returnKeyType="done"
                  onSubmitEditing={() => void submit(code)}
                />
              </View>

              {message ? <FormMessage text={message} tone={tone} /> : null}

              <Pressable
                className={`mt-4 h-12 flex-row items-center justify-center rounded-pill bg-marigold ${
                  busy ? "opacity-60" : ""
                }`}
                accessibilityRole="button"
                accessibilityLabel={words.action}
                accessibilityState={{ disabled: busy, busy: verifying }}
                disabled={busy}
                onPress={() => void submit(code)}
              >
                {verifying ? (
                  <ActivityIndicator color={tokens.colors.indigo} />
                ) : (
                  <Text className="font-sans-bold text-base text-indigo">
                    {words.action}
                  </Text>
                )}
              </Pressable>

              <Pressable
                className={`mt-2 h-11 items-center justify-center ${
                  busy ? "opacity-60" : ""
                }`}
                accessibilityRole="button"
                accessibilityLabel="Send me a new code"
                accessibilityState={{ disabled: busy, busy: resending }}
                disabled={busy}
                hitSlop={8}
                onPress={() => void sendAnother()}
              >
                <Text className="font-sans-bold text-sm text-indigo">
                  {resending ? "Sending…" : "Send me a new code"}
                </Text>
              </Pressable>

              <Pressable
                className="mt-1 h-9 items-center justify-center"
                accessibilityRole="button"
                accessibilityLabel={cancelLabel}
                hitSlop={10}
                onPress={onCancel}
              >
                <Text className="font-sans text-sm text-stoneMuted">
                  {cancelLabel}
                </Text>
              </Pressable>
            </View>

            <View className="mt-4 w-full max-w-[430px] flex-row items-start self-center rounded-card border border-border bg-ivory px-4 py-3">
              <Ionicons
                name="time-outline"
                size={18}
                color={tokens.colors.peacock}
              />
              <Text className="ml-3 min-w-0 flex-1 font-sans text-xs leading-5 text-stoneMuted">
                A code lasts one hour and works once. Asking for a new one
                replaces the code before it, so always use the newest email.
              </Text>
            </View>
          </View>
        </ScrollView>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}
