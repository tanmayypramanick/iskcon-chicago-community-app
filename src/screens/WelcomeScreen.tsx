import { Ionicons } from "@expo/vector-icons";
import { useEffect, useState } from "react";
import {
  Alert,
  Image,
  Keyboard,
  KeyboardAvoidingView,
  Platform,
  Pressable,
  Text,
  TextInput,
  useWindowDimensions,
  View,
  type TextInputProps,
} from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";

import tokens from "../../design-tokens.json";
import { Button } from "../components/ui";

type AuthView = "signIn" | "createAccount" | "resetPassword";
type SignInMethod = "email" | "phone";

function SpiritualHero({
  keyboardVisible,
  compactHeight,
}: {
  keyboardVisible: boolean;
  compactHeight: boolean;
}) {
  if (keyboardVisible) {
    return (
      <View className="h-14 flex-row items-center justify-center bg-indigo px-screen">
        <Image
          source={require("../../assets/iskcon-chicago-logo.png")}
          className="h-11 w-12"
          resizeMode="contain"
          accessibilityLabel="ISKCON Chicago logo"
        />
        <View className="ml-3">
          <Text className="font-sans-bold text-sm uppercase tracking-[2px] text-marigoldSoft">
            ISKCON Chicago
          </Text>
          <Text className="font-sans text-xs text-marigoldSoft">
            Home of Śrī Śrī Kiśora-Kiśorī
          </Text>
        </View>
      </View>
    );
  }

  return (
    <View
      className={`overflow-hidden bg-ivory px-screen ${
        compactHeight ? "h-[238px] pt-2" : "h-[304px] pt-3"
      }`}
    >
      <View className="absolute -left-10 top-10 opacity-5">
        <Ionicons
          name="flower-outline"
          size={124}
          color={tokens.colors.indigo}
        />
      </View>
      <View className="absolute -right-10 bottom-2 opacity-10">
        <Ionicons
          name="flower-outline"
          size={142}
          color={tokens.colors.marigold}
        />
      </View>
      <View className="absolute right-7 top-7 opacity-20">
        <Ionicons
          name="sparkles-outline"
          size={24}
          color={tokens.colors.marigold}
        />
      </View>

      <View className="items-center">
        <View
          className={`items-center justify-center bg-indigo ${
            compactHeight
              ? "h-[50px] w-[78px] rounded-[18px]"
              : "h-[64px] w-[98px] rounded-[22px]"
          }`}
        >
          <Image
            source={require("../../assets/iskcon-chicago-logo.png")}
            className={compactHeight ? "h-11 w-12" : "h-[58px] w-[66px]"}
            resizeMode="contain"
            accessibilityLabel="ISKCON Chicago logo"
          />
        </View>

        <View
          className={`overflow-hidden border border-marigold bg-sandalwood p-1 ${
            compactHeight
              ? "mt-2 h-[80px] w-[128px] rounded-t-[64px] rounded-b-[18px]"
              : "mt-4 h-[112px] w-[172px] rounded-t-[86px] rounded-b-[22px]"
          }`}
        >
          <View className="flex-1 overflow-hidden rounded-t-[80px] rounded-b-[18px] border border-marigoldSoft bg-white">
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
            compactHeight ? "mt-1 text-[10px]" : "mt-2 text-xs"
          }`}
        >
          Home of Śrī Śrī Kiśora-Kiśorī
        </Text>
        <Text
          className={`max-w-[330px] text-center font-display text-indigo ${
            compactHeight
              ? "mt-1 text-[15px] leading-[19px]"
              : "mt-2 text-[19px] leading-6"
          }`}
          accessibilityRole="header"
        >
          Come as you are. Grow closer to Kṛṣṇa, together.
        </Text>
        <Text
          className={`mt-1 max-w-[320px] text-center font-sans text-stoneMuted ${
            compactHeight
              ? "text-[10px] leading-[14px]"
              : "text-xs leading-4"
          }`}
        >
          A loving community connected through seva, sādhana, and kīrtana.
        </Text>
      </View>
    </View>
  );
}

function Field({
  label,
  icon,
  compact,
  ...inputProps
}: TextInputProps & {
  label: string;
  icon: keyof typeof Ionicons.glyphMap;
  compact?: boolean;
}) {
  return (
    <View>
      <Text className="mb-1 font-sans-bold text-xs text-stone">{label}</Text>
      <View
        className={`flex-row items-center rounded-[14px] border border-border bg-ivory px-3 ${
          compact ? "h-10" : "h-11"
        }`}
      >
        <Ionicons name={icon} size={18} color={tokens.colors.indigo} />
        <TextInput
          className="ml-2 flex-1 py-2 font-sans text-[15px] text-stone"
          placeholderTextColor={tokens.colors.stoneMuted}
          {...inputProps}
        />
      </View>
    </View>
  );
}

function ChoiceSwitch<T extends string>({
  choices,
  value,
  onChange,
  accessibilityPrefix,
}: {
  choices: ReadonlyArray<{ value: T; label: string }>;
  value: T;
  onChange: (value: T) => void;
  accessibilityPrefix: string;
}) {
  return (
    <View className="h-10 flex-row rounded-[14px] bg-sandalwood p-1">
      {choices.map((choice) => {
        const selected = choice.value === value;

        return (
          <Pressable
            key={choice.value}
            className={`flex-1 items-center justify-center rounded-[11px] ${
              selected ? "bg-white" : ""
            }`}
            accessibilityRole="button"
            accessibilityState={{ selected }}
            accessibilityLabel={`${accessibilityPrefix} ${choice.label}`}
            onPress={() => onChange(choice.value)}
          >
            <Text
              className={`font-sans-bold text-sm ${
                selected ? "text-indigo" : "text-stoneMuted"
              }`}
            >
              {choice.label}
            </Text>
          </Pressable>
        );
      })}
    </View>
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
  const [method, setMethod] = useState<SignInMethod>("email");
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [phone, setPhone] = useState("");
  const [password, setPassword] = useState("");
  const [otp, setOtp] = useState("");
  const [otpSent, setOtpSent] = useState(false);
  const [message, setMessage] = useState("");

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

  const changeView = (nextView: AuthView) => {
    setView(nextView);
    if (nextView === "createAccount") {
      setMethod("email");
    }
    setMessage("");
    setOtpSent(false);
    setOtp("");
  };

  const changeMethod = (nextMethod: SignInMethod) => {
    setMethod(nextMethod);
    setMessage("");
    setOtpSent(false);
    setOtp("");
  };

  const validateEmail = () => {
    if (!email.trim().includes("@")) {
      setMessage("Enter a valid email address.");
      return false;
    }
    return true;
  };

  const validatePhone = () => {
    if (phone.replace(/\D/g, "").length < 10) {
      setMessage("Enter a valid phone number, including area code.");
      return false;
    }
    return true;
  };

  const submitSignIn = () => {
    setMessage("");

    if (method === "email") {
      if (!validateEmail()) return;
      if (password.length < 6) {
        setMessage("Password must be at least 6 characters.");
        return;
      }
      onAuthenticated();
      return;
    }

    if (!validatePhone()) return;
    if (!otpSent) {
      setOtpSent(true);
      setMessage("Enter the 6-digit verification code.");
      return;
    }
    if (otp.replace(/\D/g, "").length !== 6) {
      setMessage("Enter the 6-digit verification code.");
      return;
    }
    onAuthenticated();
  };

  const submitCreateAccount = () => {
    setMessage("");
    if (name.trim().length < 2) {
      setMessage("Enter the name you would like shown.");
      return;
    }
    if (!validateEmail()) return;
    if (password.length < 6) {
      setMessage("Create a password with at least 6 characters.");
      return;
    }
    onAuthenticated();
  };

  const submitReset = () => {
    setMessage("");
    if (!validateEmail()) return;
    setMessage(
      "Reset request prepared. Delivery begins when Supabase is connected.",
    );
  };

  const showGoogleSetup = () => {
    Alert.alert(
      "Google sign-in setup needed",
      "Connect Supabase and configure Google OAuth to securely activate this option.",
    );
  };

  const isSignIn = view === "signIn";
  const isCreateAccount = view === "createAccount";
  const activeMethod: SignInMethod = isCreateAccount ? "email" : method;
  const fieldIsCompact = compactHeight || isCreateAccount || keyboardVisible;
  const showSocialSignIn = !keyboardVisible;

  return (
    <SafeAreaView className="flex-1 bg-ivory" edges={["top", "bottom"]}>
      <KeyboardAvoidingView
        className="flex-1 bg-ivory"
        behavior={Platform.OS === "ios" ? "padding" : "height"}
      >
        <SpiritualHero
          keyboardVisible={keyboardVisible}
          compactHeight={compactHeight}
        />

        <View className="-mt-3 flex-1 px-3 pb-2">
          <View
            className={`flex-1 justify-center rounded-card border border-border bg-white ${
              fieldIsCompact ? "p-3" : "p-4"
            }`}
          >
            {view !== "resetPassword" ? (
              <>
                <ChoiceSwitch
                  choices={[
                    { value: "signIn", label: "Sign in" },
                    { value: "createAccount", label: "Create account" },
                  ]}
                  value={isSignIn ? "signIn" : "createAccount"}
                  onChange={(nextView) => changeView(nextView)}
                  accessibilityPrefix="Show"
                />

                {!keyboardVisible ? (
                  <View className="my-2">
                    <Text className="font-display text-xl text-stone">
                      {isSignIn ? "Welcome back" : "Join the community"}
                    </Text>
                    <Text className="font-sans text-sm text-stoneMuted">
                      {isSignIn
                        ? "Continue your journey of devotion and seva."
                        : "Begin with one simple community account."}
                    </Text>
                  </View>
                ) : (
                  <View className="h-2" />
                )}

                {isSignIn ? (
                  <ChoiceSwitch
                    choices={[
                      { value: "email", label: "Email" },
                      { value: "phone", label: "Phone OTP" },
                    ]}
                    value={method}
                    onChange={changeMethod}
                    accessibilityPrefix="Use"
                  />
                ) : (
                  <View className="h-9 flex-row items-center rounded-[14px] bg-indigoSoft px-3">
                    <Ionicons
                      name="mail-outline"
                      size={17}
                      color={tokens.colors.indigo}
                    />
                    <Text className="ml-2 font-sans-bold text-sm text-indigo">
                      Create your account with email
                    </Text>
                  </View>
                )}

                <View className={`gap-2 ${keyboardVisible ? "mt-2" : "mt-3"}`}>
                  {isCreateAccount ? (
                    <Field
                      compact={fieldIsCompact}
                      label="Full name"
                      icon="person-outline"
                      value={name}
                      onChangeText={setName}
                      placeholder="Your name"
                      autoCapitalize="words"
                      textContentType="name"
                    />
                  ) : null}

                  {activeMethod === "email" ? (
                    <Field
                      compact={fieldIsCompact}
                      label="Email address"
                      icon="mail-outline"
                      value={email}
                      onChangeText={setEmail}
                      placeholder="you@example.com"
                      autoCapitalize="none"
                      keyboardType="email-address"
                      textContentType="emailAddress"
                    />
                  ) : (
                    <Field
                      compact={fieldIsCompact}
                      label="Phone number"
                      icon="call-outline"
                      value={phone}
                      onChangeText={setPhone}
                      placeholder="(312) 555-0123"
                      keyboardType="phone-pad"
                      textContentType="telephoneNumber"
                    />
                  )}

                  {activeMethod === "email" ? (
                    <Field
                      compact={fieldIsCompact}
                      label={isCreateAccount ? "Create password" : "Password"}
                      icon="lock-closed-outline"
                      value={password}
                      onChangeText={setPassword}
                      placeholder="At least 6 characters"
                      secureTextEntry
                      textContentType={isCreateAccount ? "newPassword" : "password"}
                    />
                  ) : null}

                  {otpSent && isSignIn ? (
                    <Field
                      compact={fieldIsCompact}
                      label="Verification code"
                      icon="keypad-outline"
                      value={otp}
                      onChangeText={setOtp}
                      placeholder="6-digit code"
                      keyboardType="number-pad"
                      maxLength={6}
                      textContentType="oneTimeCode"
                    />
                  ) : null}
                </View>

                {isSignIn && activeMethod === "email" ? (
                  <Pressable
                    className="h-8 self-end justify-center"
                    accessibilityRole="button"
                    onPress={() => changeView("resetPassword")}
                  >
                    <Text className="font-sans-bold text-sm text-indigo">
                      Forgot password?
                    </Text>
                  </Pressable>
                ) : (
                  <View className="h-2" />
                )}

                {message ? (
                  <Text
                    className="mb-1 text-center font-sans text-xs leading-4 text-vermilion"
                    accessibilityLiveRegion="polite"
                  >
                    {message}
                  </Text>
                ) : null}

                <Button
                  icon={
                    isCreateAccount
                      ? "person-add-outline"
                      : otpSent
                        ? "checkmark-circle-outline"
                        : "arrow-forward"
                  }
                  onPress={isCreateAccount ? submitCreateAccount : submitSignIn}
                >
                  {isCreateAccount
                    ? "Create my account"
                    : otpSent
                      ? "Verify and sign in"
                      : activeMethod === "phone"
                        ? "Send verification code"
                        : "Sign in"}
                </Button>

                {showSocialSignIn ? (
                  <>
                    <View className="my-2 flex-row items-center">
                      <View className="h-px flex-1 bg-border" />
                      <Text className="mx-3 font-sans text-xs text-stoneMuted">
                        or
                      </Text>
                      <View className="h-px flex-1 bg-border" />
                    </View>
                    <Button
                      variant="secondary"
                      icon="logo-google"
                      onPress={showGoogleSetup}
                    >
                      Continue with Google
                    </Button>
                  </>
                ) : null}
              </>
            ) : (
              <View>
                <Pressable
                  className="mb-2 h-10 flex-row items-center self-start"
                  accessibilityRole="button"
                  onPress={() => changeView("signIn")}
                >
                  <Ionicons
                    name="arrow-back"
                    size={19}
                    color={tokens.colors.indigo}
                  />
                  <Text className="ml-2 font-sans-bold text-sm text-indigo">
                    Back to sign in
                  </Text>
                </Pressable>
                <Text className="font-display text-xl text-stone">
                  Reset your password
                </Text>
                <Text className="mb-4 mt-1 font-sans text-sm leading-5 text-stoneMuted">
                  Enter your email and we will send a secure reset link.
                </Text>
                <Field
                  compact={fieldIsCompact}
                  label="Email address"
                  icon="mail-outline"
                  value={email}
                  onChangeText={setEmail}
                  placeholder="you@example.com"
                  autoCapitalize="none"
                  keyboardType="email-address"
                  textContentType="emailAddress"
                />
                {message ? (
                  <Text
                    className="my-2 text-center font-sans text-xs leading-4 text-vermilion"
                    accessibilityLiveRegion="polite"
                  >
                    {message}
                  </Text>
                ) : (
                  <View className="h-3" />
                )}
                <Button icon="mail-unread-outline" onPress={submitReset}>
                  Send reset link
                </Button>
              </View>
            )}
          </View>
        </View>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}
