import { Ionicons } from "@expo/vector-icons";
import { useState } from "react";
import {
  Alert,
  Image,
  KeyboardAvoidingView,
  Platform,
  Pressable,
  ScrollView,
  Text,
  TextInput,
  View,
  type TextInputProps,
} from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";

import tokens from "../../design-tokens.json";
import { Button, GarlandDivider } from "../components/ui";

type AuthView = "signIn" | "createAccount" | "resetPassword";
type SignInMethod = "email" | "phone";

function Field({
  label,
  icon,
  ...inputProps
}: TextInputProps & {
  label: string;
  icon: keyof typeof Ionicons.glyphMap;
}) {
  return (
    <View className="gap-2">
      <Text className="font-sans-bold text-sm text-stone">{label}</Text>
      <View className="min-h-touch flex-row items-center rounded-button border border-border bg-ivory px-4">
        <Ionicons name={icon} size={20} color={tokens.colors.indigo} />
        <TextInput
          className="ml-3 flex-1 py-3 font-sans text-base text-stone"
          placeholderTextColor={tokens.colors.stoneMuted}
          {...inputProps}
        />
      </View>
    </View>
  );
}

function MethodSwitch({
  value,
  onChange,
}: {
  value: SignInMethod;
  onChange: (method: SignInMethod) => void;
}) {
  return (
    <View className="flex-row rounded-button bg-sandalwood p-1">
      {(["email", "phone"] as const).map((method) => {
        const selected = value === method;

        return (
          <Pressable
            key={method}
            className={`min-h-touch flex-1 items-center justify-center rounded-[14px] ${
              selected ? "bg-white" : ""
            }`}
            accessibilityRole="button"
            accessibilityState={{ selected }}
            accessibilityLabel={`Use ${method}`}
            onPress={() => onChange(method)}
          >
            <Text
              className={`font-sans-bold text-base capitalize ${
                selected ? "text-indigo" : "text-stoneMuted"
              }`}
            >
              {method}
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
  const [view, setView] = useState<AuthView>("signIn");
  const [method, setMethod] = useState<SignInMethod>("email");
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [phone, setPhone] = useState("");
  const [password, setPassword] = useState("");
  const [otp, setOtp] = useState("");
  const [otpSent, setOtpSent] = useState(false);
  const [message, setMessage] = useState("");

  const changeView = (nextView: AuthView) => {
    setView(nextView);
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
      setMessage("Verification step ready. Enter the 6-digit code.");
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
      setMessage("Tell us the name you would like shown in the community.");
      return;
    }
    if (method === "email" && !validateEmail()) return;
    if (method === "phone" && !validatePhone()) return;
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
      "Reset request prepared. Email delivery will activate when Supabase is connected.",
    );
  };

  const showGoogleSetup = () => {
    Alert.alert(
      "Google sign-in setup needed",
      "Connect Supabase and add the Google OAuth credentials to securely activate this option.",
    );
  };

  const isSignIn = view === "signIn";
  const isCreateAccount = view === "createAccount";

  return (
    <SafeAreaView className="flex-1 bg-ivory" edges={["top", "bottom"]}>
      <KeyboardAvoidingView
        className="flex-1"
        behavior={Platform.OS === "ios" ? "padding" : undefined}
      >
        <ScrollView
          className="flex-1"
          contentContainerClassName="px-screen pb-8 pt-3"
          keyboardShouldPersistTaps="handled"
          showsVerticalScrollIndicator={false}
        >
          <View className="items-center">
            <Image
              source={require("../../assets/iskcon-chicago-logo.png")}
              className="h-24 w-28"
              resizeMode="contain"
              accessibilityLabel="ISKCON Chicago logo"
            />
            <Text className="mt-1 text-center font-sans text-base text-stoneMuted">
              Home of{" "}
              <Text className="font-sans-bold text-indigo">
                Sri Sri Kisora-Kisori
              </Text>
            </Text>

            <View className="mb-4 mt-5 rounded-pill border-2 border-marigold bg-white p-1.5">
              <Image
                source={require("../../assets/sri-sri-kisora-kisori.jpg")}
                className="h-40 w-40 rounded-pill"
                resizeMode="cover"
                accessibilityLabel="Sri Sri Kisora-Kisori at ISKCON Chicago"
              />
            </View>

            <Text
              className="max-w-sm text-center font-display text-[28px] leading-[35px] text-stone"
              accessibilityRole="header"
            >
              Rooted in devotion, united in seva
            </Text>
            <Text className="mt-2 max-w-sm text-center font-sans text-base leading-6 text-stoneMuted">
              Stay connected, grow in Krishna consciousness, and support a
              caring spiritual community.
            </Text>
          </View>

          <GarlandDivider />

          <View className="rounded-card border border-border bg-white p-card">
            {view !== "resetPassword" ? (
              <>
                <View className="mb-5 flex-row rounded-button bg-indigoSoft p-1">
                  <Pressable
                    className={`min-h-touch flex-1 items-center justify-center rounded-[14px] ${
                      isSignIn ? "bg-white" : ""
                    }`}
                    accessibilityRole="button"
                    accessibilityLabel="Show sign in form"
                    accessibilityState={{ selected: isSignIn }}
                    onPress={() => changeView("signIn")}
                  >
                    <Text
                      className={`font-sans-bold text-base ${
                        isSignIn ? "text-indigo" : "text-stoneMuted"
                      }`}
                    >
                      Sign in
                    </Text>
                  </Pressable>
                  <Pressable
                    className={`min-h-touch flex-1 items-center justify-center rounded-[14px] ${
                      isCreateAccount ? "bg-white" : ""
                    }`}
                    accessibilityRole="button"
                    accessibilityLabel="Show create account form"
                    accessibilityState={{ selected: isCreateAccount }}
                    onPress={() => changeView("createAccount")}
                  >
                    <Text
                      className={`font-sans-bold text-base ${
                        isCreateAccount ? "text-indigo" : "text-stoneMuted"
                      }`}
                    >
                      Create account
                    </Text>
                  </Pressable>
                </View>

                <Text className="font-display text-2xl text-stone">
                  {isSignIn ? "Welcome back" : "Join the community"}
                </Text>
                <Text className="mb-5 mt-1 font-sans text-base leading-6 text-stoneMuted">
                  {isSignIn
                    ? "Sign in with email or phone to continue."
                    : "Create one simple account for seva and community life."}
                </Text>

                <MethodSwitch value={method} onChange={changeMethod} />

                <View className="mt-5 gap-4">
                  {isCreateAccount ? (
                    <Field
                      label="Full name"
                      icon="person-outline"
                      value={name}
                      onChangeText={setName}
                      placeholder="Your name"
                      autoCapitalize="words"
                      textContentType="name"
                    />
                  ) : null}

                  {method === "email" ? (
                    <Field
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
                      label="Phone number"
                      icon="call-outline"
                      value={phone}
                      onChangeText={setPhone}
                      placeholder="(312) 555-0123"
                      keyboardType="phone-pad"
                      textContentType="telephoneNumber"
                    />
                  )}

                  {method === "email" || isCreateAccount ? (
                    <Field
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

                {isSignIn && method === "email" ? (
                  <Pressable
                    className="min-h-touch self-end justify-center"
                    accessibilityRole="button"
                    onPress={() => changeView("resetPassword")}
                  >
                    <Text className="font-sans-bold text-base text-indigo">
                      Forgot password?
                    </Text>
                  </Pressable>
                ) : null}

                {message ? (
                  <View
                    className="mb-4 rounded-button bg-indigoSoft px-4 py-3"
                    accessibilityLiveRegion="polite"
                  >
                    <Text className="font-sans text-sm leading-5 text-indigo">
                      {message}
                    </Text>
                  </View>
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
                      : method === "phone"
                        ? "Send verification code"
                        : "Sign in"}
                </Button>

                <View className="my-5 flex-row items-center">
                  <View className="h-px flex-1 bg-border" />
                  <Text className="mx-3 font-sans text-sm text-stoneMuted">or</Text>
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
            ) : (
              <>
                <Pressable
                  className="mb-4 min-h-touch flex-row items-center self-start"
                  accessibilityRole="button"
                  onPress={() => changeView("signIn")}
                >
                  <Ionicons
                    name="arrow-back"
                    size={20}
                    color={tokens.colors.indigo}
                  />
                  <Text className="ml-2 font-sans-bold text-base text-indigo">
                    Back to sign in
                  </Text>
                </Pressable>
                <Text className="font-display text-2xl text-stone">
                  Reset your password
                </Text>
                <Text className="mb-5 mt-2 font-sans text-base leading-6 text-stoneMuted">
                  Enter your email and we will send a secure reset link.
                </Text>
                <Field
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
                  <View
                    className="my-4 rounded-button bg-indigoSoft px-4 py-3"
                    accessibilityLiveRegion="polite"
                  >
                    <Text className="font-sans text-sm leading-5 text-indigo">
                      {message}
                    </Text>
                  </View>
                ) : (
                  <View className="h-5" />
                )}
                <Button icon="mail-unread-outline" onPress={submitReset}>
                  Send reset link
                </Button>
              </>
            )}
          </View>

          <Text className="mt-6 text-center font-sans text-sm leading-5 text-stoneMuted">
            Stay connected. Serve with heart. Deepen your Krishna consciousness.
          </Text>
        </ScrollView>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}
