import { Ionicons } from "@expo/vector-icons";
import { useState } from "react";
import {
  KeyboardAvoidingView,
  Platform,
  Pressable,
  Text,
  TextInput,
  View,
} from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";

import tokens from "../../design-tokens.json";
import { setNewPassword } from "../services/auth";

const MINIMUM_LENGTH = 8;

/**
 * Shown when a devotee opens a password-reset link. By the time this appears
 * the recovery token has already been exchanged for a session, so the devotee
 * is technically signed in — but they still do not know their password, and
 * leaving them in the app without setting one means the next sign-in fails the
 * same way. So this stands in front of everything until a password is set.
 */
export function SetNewPasswordScreen({ onDone }: { onDone: () => void }) {
  const [password, setPassword] = useState("");
  const [confirmation, setConfirmation] = useState("");
  const [visible, setVisible] = useState(false);
  const [message, setMessage] = useState("");
  const [saving, setSaving] = useState(false);

  const submit = async () => {
    setMessage("");
    if (password.length < MINIMUM_LENGTH) {
      setMessage(`Use at least ${MINIMUM_LENGTH} characters.`);
      return;
    }
    if (password !== confirmation) {
      setMessage("Both passwords must match.");
      return;
    }

    setSaving(true);
    try {
      await setNewPassword(password);
      onDone();
    } catch (error) {
      setMessage(
        error instanceof Error
          ? error.message
          : "That password could not be saved.",
      );
    } finally {
      setSaving(false);
    }
  };

  return (
    <SafeAreaView className="flex-1 bg-ivory" edges={["top", "bottom"]}>
      <KeyboardAvoidingView
        className="flex-1 justify-center px-6"
        behavior={Platform.OS === "ios" ? "padding" : "height"}
      >
        <View className="w-full max-w-[430px] self-center">
          <View className="mb-6 h-14 w-14 items-center justify-center rounded-pill bg-indigoSoft">
            <Ionicons
              name="lock-open-outline"
              size={26}
              color={tokens.colors.indigo}
            />
          </View>

          <Text className="font-serif text-2xl text-stone">
            Choose a new password
          </Text>
          <Text className="mt-2 font-sans text-sm leading-5 text-stoneMuted">
            You are signed in from your email link. Set a password so you can
            sign in normally next time.
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
              textContentType="newPassword"
            />
            <Pressable
              accessibilityRole="button"
              accessibilityLabel={visible ? "Hide password" : "Show password"}
              hitSlop={10}
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
              textContentType="newPassword"
            />
          </View>

          {message ? (
            <Text className="mt-3 font-sans text-sm text-terracotta">
              {message}
            </Text>
          ) : null}

          <Pressable
            className={`mt-5 h-12 flex-row items-center justify-center rounded-pill ${
              saving ? "bg-marigoldSoft" : "bg-marigold"
            }`}
            accessibilityRole="button"
            accessibilityLabel="Save new password"
            disabled={saving}
            onPress={submit}
          >
            <Text className="font-sans-bold text-base text-indigo">
              {saving ? "Saving…" : "Save password"}
            </Text>
          </Pressable>
        </View>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}
