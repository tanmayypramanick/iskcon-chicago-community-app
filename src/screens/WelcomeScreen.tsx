import { Ionicons } from "@expo/vector-icons";
import { useEffect, useState } from "react";
import {
  ActivityIndicator,
  Alert,
  Image,
  Keyboard,
  KeyboardAvoidingView,
  Platform,
  Pressable,
  ScrollView,
  Text,
  TextInput,
  useWindowDimensions,
  View,
  type TextInputProps,
} from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";

import tokens from "../../design-tokens.json";
import { COMMUNITY_EMAIL } from "../config/contact";
import {
  getAuthProviderAvailability,
  PASSWORD_MIN_LENGTH,
  requestPasswordReset,
  requestReplacementLink,
  signInWithEmail,
  signInWithGoogle,
  signUpWithEmail,
  type AuthProviderAvailability,
} from "../services/auth";

type AuthView = "signIn" | "createAccount" | "resetPassword";

const portraitShadow = {
  shadowColor: tokens.colors.marigold,
  shadowOffset: { width: 0, height: 12 },
  shadowOpacity: 0.22,
  shadowRadius: 18,
  elevation: 5,
};

function BrandMark({
  size = "regular",
}: {
  size?: "regular" | "medium" | "compact";
}) {
  const sizeClass = {
    regular: "h-[92px] w-[104px]",
    medium: "h-[68px] w-[78px]",
    compact: "h-11 w-12",
  }[size];

  return (
    <Image
      source={require("../../assets/iskcon-chicago-logo.png")}
      className={sizeClass}
      resizeMode="contain"
      style={{ tintColor: tokens.colors.indigo }}
      accessibilityLabel="ISKCON Chicago logo"
    />
  );
}

function GarlandAccent() {
  return (
    <View
      className="my-2 flex-row items-center justify-center gap-2"
      accessibilityElementsHidden
      importantForAccessibility="no-hide-descendants"
    >
      {[5, 8, 5, 8, 5, 8, 5].map((size, index) => (
        <View
          key={`${size}-${index}`}
          className={size === 8 ? "h-2 w-2" : "h-[5px] w-[5px] opacity-60"}
          style={{
            borderRadius: size,
            backgroundColor: tokens.colors.marigold,
          }}
        />
      ))}
    </View>
  );
}

function SpiritualHero({
  keyboardVisible,
  compactHeight,
  condensed,
}: {
  keyboardVisible: boolean;
  compactHeight: boolean;
  condensed: boolean;
}) {
  if (keyboardVisible) {
    return (
      <View className="h-14 flex-row items-center justify-center bg-ivory px-screen">
        <BrandMark size="compact" />
        <Text className="ml-3 font-sans-bold text-xs uppercase tracking-[2px] text-indigo">
          ISKCON Chicago
        </Text>
      </View>
    );
  }

  const heroHeight = condensed
    ? compactHeight
      ? "h-[210px] pt-1"
      : "h-[288px] pt-2"
    : compactHeight
      ? "h-[360px] pt-2"
      : "h-[466px] pt-3";
  const portraitSize = condensed
    ? compactHeight
      ? "mt-1 h-[104px] w-[92px] rounded-t-[52px] rounded-b-[14px]"
      : "mt-1.5 h-[136px] w-[118px] rounded-t-[64px] rounded-b-[16px]"
    : compactHeight
      ? "mt-2 h-[166px] w-[142px] rounded-t-[76px] rounded-b-[18px]"
      : "mt-4 h-[224px] w-[190px] rounded-t-[104px] rounded-b-[22px]";

  return (
    <View
      className={`items-center overflow-hidden bg-ivory px-screen ${heroHeight}`}
    >
      <View className="absolute -left-7 top-40 -rotate-12 opacity-5">
        <Ionicons name="leaf-outline" size={96} color={tokens.colors.indigo} />
      </View>
      <View className="absolute -right-7 bottom-10 rotate-12 opacity-10">
        <Ionicons
          name="leaf-outline"
          size={116}
          color={tokens.colors.marigold}
        />
      </View>

      <BrandMark size={condensed || compactHeight ? "medium" : "regular"} />

      <View
        className={`overflow-hidden border border-marigold bg-sandalwood p-1 ${portraitSize}`}
        style={portraitShadow}
      >
        <View className="flex-1 overflow-hidden rounded-t-[98px] rounded-b-[17px] border border-marigoldSoft bg-white">
          <Image
            source={require("../../assets/sri-sri-kisora-kisori.jpg")}
            className="h-full w-full"
            resizeMode="cover"
            accessibilityLabel="Sri Sri Kisora-Kisori at ISKCON Chicago"
          />
        </View>
      </View>

      <Text
        className={`text-center font-display-italic text-marigold ${
          condensed || compactHeight ? "mt-0.5 text-[10px]" : "mt-1 text-xs"
        }`}
      >
        Home of Śrī Śrī Kiśora-Kiśorī
      </Text>

      {!condensed ? (
        <>
          {!compactHeight ? <GarlandAccent /> : <View className="h-2" />}
          <Text
            className={`text-center font-display text-indigo ${
              compactHeight ? "text-[17px] leading-5" : "text-[21px] leading-6"
            }`}
            accessibilityRole="header"
            adjustsFontSizeToFit
            minimumFontScale={0.8}
            numberOfLines={1}
          >
            Come as you are
          </Text>
          <Text
            className={`text-center font-display text-indigo ${
              compactHeight ? "text-[17px] leading-5" : "text-[21px] leading-6"
            }`}
            adjustsFontSizeToFit
            minimumFontScale={0.8}
            numberOfLines={1}
          >
            Grow closer to Kṛṣṇa together
          </Text>
          <Text
            className={`mt-1 text-center font-sans text-stoneMuted ${
              compactHeight ? "text-[10px] leading-3" : "text-xs leading-4"
            }`}
          >
            A loving community connected through seva, sādhana, and kīrtana.
          </Text>
        </>
      ) : null}
    </View>
  );
}

/**
 * The one message slot each form has. Confirmations and failures both land
 * here, so the tone has to say which it is — an "email sent" line in error red
 * reads as a failure and sends devotees round the loop again.
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
      className={`flex-row items-start rounded-card px-3 py-2 ${
        failed ? "bg-vermilionSoft" : "bg-peacockSoft"
      }`}
      accessibilityLiveRegion="polite"
    >
      <Ionicons
        name={failed ? "alert-circle-outline" : "checkmark-circle-outline"}
        size={15}
        color={failed ? tokens.colors.vermilion : tokens.colors.peacock}
      />
      <Text
        className={`ml-2 flex-1 font-sans text-xs leading-4 ${
          failed ? "text-vermilion" : "text-peacock"
        }`}
      >
        {text}
      </Text>
    </View>
  );
}

function Field({
  icon,
  accessibilityLabel,
  ...inputProps
}: TextInputProps & {
  icon: keyof typeof Ionicons.glyphMap;
  accessibilityLabel: string;
}) {
  return (
    <View className="h-11 flex-row items-center rounded-pill border border-border bg-white px-4">
      <Ionicons name={icon} size={18} color={tokens.colors.indigo} />
      <TextInput
        className="ml-3 flex-1 py-2 font-sans text-[15px] text-stone"
        placeholderTextColor={tokens.colors.stoneMuted}
        accessibilityLabel={accessibilityLabel}
        {...inputProps}
      />
    </View>
  );
}

function ActionButton({
  children,
  icon,
  variant = "primary",
  loading = false,
  disabled = false,
  onPress,
}: {
  children: string;
  icon: keyof typeof Ionicons.glyphMap;
  variant?: "primary" | "secondary";
  loading?: boolean;
  disabled?: boolean;
  onPress: () => void;
}) {
  const primary = variant === "primary";
  const unavailable = disabled || loading;

  return (
    <Pressable
      className={`h-11 flex-row items-center justify-center rounded-pill ${
        primary ? "bg-marigold" : "border border-border bg-white"
      } ${unavailable ? "opacity-60" : ""}`}
      accessibilityRole="button"
      accessibilityLabel={children}
      accessibilityState={{ disabled: unavailable, busy: loading }}
      disabled={unavailable}
      onPress={onPress}
    >
      {loading ? (
        <ActivityIndicator color={tokens.colors.indigo} />
      ) : (
        <>
          <Ionicons name={icon} size={20} color={tokens.colors.indigo} />
          <Text className="ml-2 font-sans-bold text-base text-indigo">
            {children}
          </Text>
        </>
      )}
    </Pressable>
  );
}

function FinePrint() {
  return (
    <Text className="text-center font-sans text-[10px] text-stoneMuted">
      By continuing, you agree to our Terms of Service &amp; Privacy Policy.
    </Text>
  );
}

export function WelcomeScreen({
  onAuthenticated,
}: {
  onAuthenticated: () => void;
}) {
  const { height } = useWindowDimensions();
  const compactHeight = height < 760;
  const [keyboardVisible, setKeyboardVisible] = useState(false);
  const [view, setView] = useState<AuthView>("signIn");
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [message, setMessage] = useState("");
  const [messageTone, setMessageTone] = useState<"error" | "success">("error");
  const [submitting, setSubmitting] = useState(false);
  const [googleSubmitting, setGoogleSubmitting] = useState(false);
  // Kept across view changes on purpose. Gmail's in-app browser often refuses
  // to hand a custom scheme to the app, so a devotee can be left holding a
  // confirmation link that does nothing; this is what keeps a second link one
  // tap away instead of stranding them on a sign-in that will not work yet.
  const [awaitingConfirmation, setAwaitingConfirmation] = useState("");
  const [resending, setResending] = useState(false);
  const [providers, setProviders] = useState<AuthProviderAvailability | null>(
    null,
  );

  useEffect(() => {
    const showEvent =
      Platform.OS === "ios" ? "keyboardWillShow" : "keyboardDidShow";
    const hideEvent =
      Platform.OS === "ios" ? "keyboardWillHide" : "keyboardDidHide";
    const showSubscription = Keyboard.addListener(showEvent, () =>
      setKeyboardVisible(true),
    );
    const hideSubscription = Keyboard.addListener(hideEvent, () =>
      setKeyboardVisible(false),
    );

    return () => {
      showSubscription.remove();
      hideSubscription.remove();
    };
  }, []);

  useEffect(() => {
    let active = true;

    getAuthProviderAvailability()
      .then((availability) => {
        if (active) setProviders(availability);
      })
      .catch(() => {
        if (active) setProviders(null);
      });

    return () => {
      active = false;
    };
  }, []);

  const changeView = (nextView: AuthView) => {
    setView(nextView);
    setMessage("");
    setMessageTone("error");
  };

  const showError = (text: string) => {
    setMessageTone("error");
    setMessage(text);
  };

  /** Confirmations share the message slot but must not be dressed as faults. */
  const showSuccess = (text: string) => {
    setMessageTone("success");
    setMessage(text);
  };

  const validateEmail = () => {
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email.trim())) {
      showError("Enter a valid email address.");
      return false;
    }
    return true;
  };

  const getErrorMessage = (error: unknown) =>
    error instanceof Error
      ? error.message
      : "Something went wrong. Please try again.";

  const submitSignIn = async () => {
    setMessage("");
    if (!validateEmail()) return;
    if (password.length < PASSWORD_MIN_LENGTH) {
      showError(`Password must be at least ${PASSWORD_MIN_LENGTH} characters.`);
      return;
    }

    setSubmitting(true);
    try {
      const session = await signInWithEmail(email, password);
      if (!session) {
        showError("Sign-in did not return a session. Please try again.");
        return;
      }
      onAuthenticated();
    } catch (error) {
      showError(getErrorMessage(error));
    } finally {
      setSubmitting(false);
    }
  };

  const submitCreateAccount = async () => {
    setMessage("");
    if (name.trim().length < 2) {
      showError("Enter the name you would like shown.");
      return;
    }
    if (!validateEmail()) return;
    // Reads the server's own minimum rather than a stricter number of its own:
    // a rule the copy states has to be the rule the account is actually held to.
    if (password.length < PASSWORD_MIN_LENGTH) {
      showError(
        `Create a password with at least ${PASSWORD_MIN_LENGTH} characters.`,
      );
      return;
    }

    setSubmitting(true);
    try {
      const session = await signUpWithEmail({
        name,
        email,
        password,
      });

      if (!session) {
        setView("signIn");
        setPassword("");
        setAwaitingConfirmation(email.trim());
        showSuccess(
          `Welcome. Open the private verification link sent from ${COMMUNITY_EMAIL} on this phone, then return here to sign in.`,
        );
        return;
      }

      onAuthenticated();
    } catch (error) {
      showError(getErrorMessage(error));
    } finally {
      setSubmitting(false);
    }
  };

  const submitReset = async () => {
    setMessage("");
    if (!validateEmail()) return;

    setSubmitting(true);
    try {
      await requestPasswordReset(email);
      showSuccess(
        `If an account uses this email, a secure link will arrive from ${COMMUNITY_EMAIL}. Open it on this phone to choose a new password.`,
      );
    } catch (error) {
      showError(getErrorMessage(error));
    } finally {
      setSubmitting(false);
    }
  };

  /**
   * Says only that a link is on its way — never whether the address is known.
   * Supabase answers a resend for a stranger's address as a success precisely
   * so the app cannot be used to test who has an account, and the copy here
   * must not undo that.
   */
  const resendConfirmation = async () => {
    if (resending) return;
    setMessage("");
    setResending(true);
    try {
      await requestReplacementLink(awaitingConfirmation, "signup");
      showSuccess(
        `If that address is with us, another link is on its way from ${COMMUNITY_EMAIL}. Open it on this phone.`,
      );
    } catch {
      showError(
        "The link could not be sent just now. Check your connection and try again.",
      );
    } finally {
      setResending(false);
    }
  };

  const submitGoogleSignIn = async () => {
    setMessage("");

    if (providers && !providers.google) {
      Alert.alert(
        "Google sign-in is unavailable",
        "Enable the Google provider in Supabase, then restart the app.",
      );
      return;
    }

    setGoogleSubmitting(true);
    try {
      const session = await signInWithGoogle();
      if (session) onAuthenticated();
    } catch (error) {
      showError(getErrorMessage(error));
    } finally {
      setGoogleSubmitting(false);
    }
  };

  const isSignIn = view === "signIn";
  const isCreateAccount = view === "createAccount";

  return (
    <SafeAreaView className="flex-1 bg-ivory" edges={["top", "bottom"]}>
      <KeyboardAvoidingView
        className="flex-1 bg-ivory"
        behavior={Platform.OS === "ios" ? "padding" : "height"}
      >
        {/* Sign in is the root of this screen, so only the two views reached
            from it offer a way back. Without this a devotee who taps "Forgot
            password?" by mistake has no way out but to kill the app. */}
        {!isSignIn ? (
          <Pressable
            className="absolute left-3 top-2 z-10 h-11 w-11 items-center justify-center rounded-pill"
            accessibilityRole="button"
            accessibilityLabel="Back to sign in"
            hitSlop={8}
            onPress={() => changeView("signIn")}
          >
            <Ionicons
              name="chevron-back"
              size={26}
              color={tokens.colors.indigo}
            />
          </Pressable>
        ) : null}

        <SpiritualHero
          keyboardVisible={keyboardVisible}
          compactHeight={compactHeight}
          condensed={!isSignIn}
        />

        {isSignIn ? (
          // Scrollable rather than a fixed pane: on a short screen with the
          // keyboard up the fields were pushed under it with no way to reach
          // them. flexGrow keeps the form bottom-aligned when it does fit.
          <ScrollView
            className="flex-1 bg-sandalwood"
            contentContainerStyle={{ flexGrow: 1 }}
            keyboardDismissMode="interactive"
            keyboardShouldPersistTaps="handled"
            showsVerticalScrollIndicator={false}
          >
            <View
              className={`flex-1 px-6 ${
                keyboardVisible
                  ? "justify-center py-3"
                  : "justify-end pb-2 pt-3"
              }`}
            >
              <View className="w-full max-w-[430px] self-center gap-1.5">
                <Field
                  icon="mail-outline"
                  accessibilityLabel="Email address"
                  value={email}
                  onChangeText={setEmail}
                  placeholder="Email address"
                  autoCapitalize="none"
                  keyboardType="email-address"
                  textContentType="emailAddress"
                />
                <Field
                  icon="lock-closed-outline"
                  accessibilityLabel="Password"
                  value={password}
                  onChangeText={setPassword}
                  placeholder="Password"
                  secureTextEntry
                  textContentType="password"
                />
                <Pressable
                  className="h-5 self-end justify-center"
                  accessibilityRole="button"
                  accessibilityLabel="Forgot password?"
                  hitSlop={12}
                  onPress={() => changeView("resetPassword")}
                >
                  <Text className="font-sans-bold text-xs text-indigo">
                    Forgot password?
                  </Text>
                </Pressable>

                {message ? (
                  <FormMessage text={message} tone={messageTone} />
                ) : null}

                <ActionButton
                  icon="arrow-forward"
                  loading={submitting}
                  disabled={googleSubmitting}
                  onPress={submitSignIn}
                >
                  Sign in
                </ActionButton>

                {!keyboardVisible ? (
                  <>
                    {awaitingConfirmation ? (
                      <View className="rounded-card border border-border bg-white px-3 py-2.5">
                        <Text className="font-sans text-[11px] leading-4 text-stoneMuted">
                          Still waiting on the link for {awaitingConfirmation}?
                          If it opened a browser rather than the app, open the
                          same email in Mail or Safari and tap it there.
                        </Text>
                        <Pressable
                          className="mt-1.5 h-6 justify-center"
                          accessibilityRole="button"
                          accessibilityLabel="Send the confirmation link again"
                          accessibilityState={{
                            disabled: resending,
                            busy: resending,
                          }}
                          disabled={resending}
                          hitSlop={10}
                          onPress={resendConfirmation}
                        >
                          <Text className="font-sans-bold text-xs text-indigo">
                            {resending
                              ? "Sending…"
                              : "Send the confirmation link again"}
                          </Text>
                        </Pressable>
                      </View>
                    ) : null}

                    <View className="flex-row items-center">
                      <View className="h-px flex-1 bg-border" />
                      <Text className="mx-3 font-sans text-xs text-stoneMuted">
                        OR
                      </Text>
                      <View className="h-px flex-1 bg-border" />
                    </View>
                    <ActionButton
                      variant="secondary"
                      icon="logo-google"
                      loading={googleSubmitting}
                      disabled={submitting}
                      onPress={submitGoogleSignIn}
                    >
                      Continue with Google
                    </ActionButton>
                    <Pressable
                      className="h-7 items-center justify-center"
                      accessibilityRole="button"
                      accessibilityLabel="Create an account"
                      hitSlop={12}
                      onPress={() => changeView("createAccount")}
                    >
                      <Text className="font-sans text-base text-stoneMuted">
                        New here?{" "}
                        <Text className="font-sans-bold text-indigo">
                          Create an account
                        </Text>
                      </Text>
                    </Pressable>
                    <FinePrint />
                  </>
                ) : null}
              </View>
            </View>
          </ScrollView>
        ) : (
          <ScrollView
            className="flex-1 bg-sandalwood"
            contentContainerStyle={{ flexGrow: 1 }}
            keyboardDismissMode="interactive"
            keyboardShouldPersistTaps="handled"
            showsVerticalScrollIndicator={false}
          >
            <View className="flex-1 justify-center px-6 py-3">
              <View className="w-full max-w-[430px] self-center gap-2.5 rounded-[28px] border border-border bg-ivory p-4">
                {isCreateAccount ? (
                  <>
                    {!keyboardVisible ? (
                      <View className="mb-1 items-center">
                        <View className="mb-2 h-1 w-10 rounded-pill bg-marigold" />
                        <Text className="text-center font-display text-[22px] text-indigo">
                          Create your account
                        </Text>
                        <Text className="mt-0.5 text-center font-sans text-sm text-stoneMuted">
                          Join our temple community with your name and email.
                        </Text>
                      </View>
                    ) : null}

                    <Field
                      icon="person-outline"
                      accessibilityLabel="Full name"
                      value={name}
                      onChangeText={setName}
                      placeholder="Full name"
                      autoCapitalize="words"
                      textContentType="name"
                    />
                    <Field
                      icon="mail-outline"
                      accessibilityLabel="Email address"
                      value={email}
                      onChangeText={setEmail}
                      placeholder="Email address"
                      autoCapitalize="none"
                      keyboardType="email-address"
                      textContentType="emailAddress"
                    />
                    <Field
                      icon="lock-closed-outline"
                      accessibilityLabel="Create password"
                      value={password}
                      onChangeText={setPassword}
                      placeholder="Create password"
                      secureTextEntry
                      textContentType="newPassword"
                    />

                    {message ? (
                      <FormMessage text={message} tone={messageTone} />
                    ) : null}

                    <ActionButton
                      icon="person-add-outline"
                      loading={submitting}
                      onPress={submitCreateAccount}
                    >
                      Create account
                    </ActionButton>

                    {!keyboardVisible ? (
                      <>
                        <Pressable
                          className="h-8 items-center justify-center"
                          accessibilityRole="button"
                          accessibilityLabel="Return to sign in"
                          hitSlop={12}
                          onPress={() => changeView("signIn")}
                        >
                          <Text className="font-sans text-base text-stoneMuted">
                            Already have an account?{" "}
                            <Text className="font-sans-bold text-indigo">
                              Sign in
                            </Text>
                          </Text>
                        </Pressable>
                        <FinePrint />
                      </>
                    ) : null}
                  </>
                ) : null}

                {view === "resetPassword" ? (
                  <>
                    <Text className="font-sans-bold text-lg text-stone">
                      Reset your password
                    </Text>
                    {/* Says what we will do, not what we know. Confirming that
                        an address does or does not have an account would turn
                        this form into a way of finding out who is a member. */}
                    <Text className="font-sans text-xs leading-4 text-stoneMuted">
                      Enter your address and we will send a secure link to
                      choose a new password. Open it on this phone.
                    </Text>
                    <Field
                      icon="mail-outline"
                      accessibilityLabel="Reset email address"
                      value={email}
                      onChangeText={setEmail}
                      placeholder="Email address"
                      autoCapitalize="none"
                      keyboardType="email-address"
                      textContentType="emailAddress"
                    />
                    {message ? (
                      <FormMessage text={message} tone={messageTone} />
                    ) : null}
                    <ActionButton
                      icon="mail-unread-outline"
                      loading={submitting}
                      onPress={submitReset}
                    >
                      Send reset link
                    </ActionButton>
                    <Text className="font-sans text-[11px] leading-4 text-stoneMuted">
                      If the link opens a browser rather than the app, open the
                      same email in Mail or Safari and tap it there.
                    </Text>
                    <Pressable
                      className="h-7 items-center justify-center"
                      accessibilityRole="button"
                      accessibilityLabel="Return to sign in"
                      hitSlop={12}
                      onPress={() => changeView("signIn")}
                    >
                      <Text className="font-sans-bold text-xs text-indigo">
                        Back to sign in
                      </Text>
                    </Pressable>
                    <FinePrint />
                  </>
                ) : null}
              </View>
            </View>
          </ScrollView>
        )}
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}
