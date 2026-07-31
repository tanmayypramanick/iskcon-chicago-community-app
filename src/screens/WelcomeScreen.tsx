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

type AuthView = "signIn" | "createAccount" | "resetPassword";

const portraitShadow = {
  shadowColor: tokens.colors.marigold,
  shadowOffset: { width: 0, height: 12 },
  shadowOpacity: 0.22,
  shadowRadius: 18,
  elevation: 5,
};

function BrandMark({ compact = false }: { compact?: boolean }) {
  return (
    <Image
      source={require("../../assets/iskcon-chicago-logo.png")}
      className={compact ? "h-11 w-12" : "h-[92px] w-[104px]"}
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
        <BrandMark compact />
        <Text className="ml-3 font-sans-bold text-xs uppercase tracking-[2px] text-indigo">
          ISKCON Chicago
        </Text>
      </View>
    );
  }

  const isCondensed = condensed || compactHeight;

  return (
    <View
      className={`items-center overflow-hidden bg-ivory px-screen ${
        isCondensed ? "h-[350px] pt-2" : "h-[466px] pt-3"
      }`}
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

      <BrandMark />

      <View
        className={`overflow-hidden border border-marigold bg-sandalwood p-1 ${
          isCondensed
            ? "mt-2 h-[150px] w-[132px] rounded-t-[72px] rounded-b-[18px]"
            : "mt-4 h-[224px] w-[190px] rounded-t-[104px] rounded-b-[22px]"
        }`}
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
          isCondensed ? "mt-0.5 text-[10px]" : "mt-1 text-xs"
        }`}
      >
        Home of Śrī Śrī Kiśora-Kiśorī
      </Text>

      {!isCondensed ? (
        <>
          <GarlandAccent />
          <Text
            className="text-center font-display text-[21px] leading-6 text-indigo"
            accessibilityRole="header"
            adjustsFontSizeToFit
            minimumFontScale={0.8}
            numberOfLines={1}
          >
            Come as you are
          </Text>
          <Text
            className="text-center font-display text-[21px] leading-6 text-indigo"
            adjustsFontSizeToFit
            minimumFontScale={0.8}
            numberOfLines={1}
          >
            Grow closer to Kṛṣṇa together
          </Text>
          <Text className="mt-1 text-center font-sans text-xs leading-4 text-stoneMuted">
            A loving community connected through seva, sādhana, and kīrtana.
          </Text>
        </>
      ) : null}
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
  onPress,
}: {
  children: string;
  icon: keyof typeof Ionicons.glyphMap;
  variant?: "primary" | "secondary";
  onPress: () => void;
}) {
  const primary = variant === "primary";

  return (
    <Pressable
      className={`h-11 flex-row items-center justify-center rounded-pill ${
        primary ? "bg-marigold" : "border border-border bg-white"
      }`}
      accessibilityRole="button"
      accessibilityLabel={children}
      onPress={onPress}
    >
      <Ionicons name={icon} size={20} color={tokens.colors.indigo} />
      <Text className="ml-2 font-sans-bold text-base text-indigo">
        {children}
      </Text>
    </Pressable>
  );
}

function FinePrint() {
  return (
    <Text className="text-center font-sans text-[10px] text-stoneMuted">
      By continuing, you agree to our Terms &amp; Privacy Policy.
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
    if (!validateEmail()) return;
    if (password.length < 6) {
      setMessage("Password must be at least 6 characters.");
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
    if (!validatePhone()) return;
    if (!otpSent) {
      setOtpSent(true);
      setMessage("Enter the 6-digit code sent to your phone.");
      return;
    }
    if (otp.replace(/\D/g, "").length !== 6) {
      setMessage("Enter the 6-digit verification code.");
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

  return (
    <SafeAreaView className="flex-1 bg-ivory" edges={["top", "bottom"]}>
      <KeyboardAvoidingView
        className="flex-1 bg-ivory"
        behavior={Platform.OS === "ios" ? "padding" : "height"}
      >
        <SpiritualHero
          keyboardVisible={keyboardVisible}
          compactHeight={compactHeight}
          condensed={!isSignIn}
        />

        <View
          className={`flex-1 bg-sandalwood px-6 ${
            keyboardVisible ? "justify-center py-2" : "justify-end pb-2 pt-3"
          }`}
        >
          {isSignIn ? (
            <View className="gap-1.5">
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
                <Text
                  className="text-center font-sans text-xs text-vermilion"
                  accessibilityLiveRegion="polite"
                >
                  {message}
                </Text>
              ) : null}

              <ActionButton icon="arrow-forward" onPress={submitSignIn}>
                Sign in
              </ActionButton>

              {!keyboardVisible ? (
                <>
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
                    onPress={showGoogleSetup}
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
          ) : null}

          {isCreateAccount ? (
            <View className="gap-2">
              {!keyboardVisible ? (
                <View>
                  <Text className="font-sans-bold text-lg text-stone">
                    Create your account
                  </Text>
                  <Text className="font-sans text-xs text-stoneMuted">
                    Your phone is used only for OTP verification.
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

              {!otpSent ? (
                <Field
                  icon="call-outline"
                  accessibilityLabel="Phone number"
                  value={phone}
                  onChangeText={setPhone}
                  placeholder="Phone number"
                  keyboardType="phone-pad"
                  textContentType="telephoneNumber"
                />
              ) : (
                <>
                  <View className="h-8 flex-row items-center rounded-pill bg-peacockSoft px-3">
                    <Ionicons
                      name="checkmark-circle"
                      size={16}
                      color={tokens.colors.peacock}
                    />
                    <Text className="ml-2 flex-1 font-sans-bold text-xs text-peacock">
                      Code sent to {phone}
                    </Text>
                    <Pressable
                      accessibilityRole="button"
                      accessibilityLabel="Change phone number"
                      hitSlop={12}
                      onPress={() => {
                        setOtpSent(false);
                        setOtp("");
                        setMessage("");
                      }}
                    >
                      <Text className="font-sans-bold text-xs text-indigo">
                        Change
                      </Text>
                    </Pressable>
                  </View>
                  <Field
                    icon="keypad-outline"
                    accessibilityLabel="Verification code"
                    value={otp}
                    onChangeText={setOtp}
                    placeholder="6-digit verification code"
                    keyboardType="number-pad"
                    maxLength={6}
                    textContentType="oneTimeCode"
                  />
                </>
              )}

              {message ? (
                <Text
                  className="text-center font-sans text-xs text-vermilion"
                  accessibilityLiveRegion="polite"
                >
                  {message}
                </Text>
              ) : null}

              <ActionButton
                icon={otpSent ? "checkmark-circle-outline" : "call-outline"}
                onPress={submitCreateAccount}
              >
                {otpSent
                  ? "Verify and create account"
                  : "Send phone verification"}
              </ActionButton>

              {!keyboardVisible ? (
                <>
                  <Pressable
                    className="h-6 items-center justify-center"
                    accessibilityRole="button"
                    accessibilityLabel="Return to sign in"
                    hitSlop={12}
                    onPress={() => changeView("signIn")}
                  >
                    <Text className="font-sans text-xs text-stoneMuted">
                      Already have an account?{" "}
                      <Text className="font-sans-bold text-indigo">
                        Sign in
                      </Text>
                    </Text>
                  </Pressable>
                  <FinePrint />
                </>
              ) : null}
            </View>
          ) : null}

          {view === "resetPassword" ? (
            <View className="gap-3">
              <Text className="font-sans-bold text-lg text-stone">
                Reset your password
              </Text>
              <Text className="font-sans text-xs text-stoneMuted">
                We will send a secure reset link to your email.
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
                <Text
                  className="text-center font-sans text-xs text-vermilion"
                  accessibilityLiveRegion="polite"
                >
                  {message}
                </Text>
              ) : null}
              <ActionButton icon="mail-unread-outline" onPress={submitReset}>
                Send reset link
              </ActionButton>
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
            </View>
          ) : null}
        </View>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}
