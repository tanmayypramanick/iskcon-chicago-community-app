import { Ionicons } from "@expo/vector-icons";
import { useState } from "react";
import { Pressable, Text, TextInput, View } from "react-native";

import tokens from "../../design-tokens.json";
import { Screen, ScreenTitle } from "../components/ui";
import { useForgetMe, useLeaveTheCommunity } from "../features/account/hooks";
import { useCurrentAccessProfile } from "../features/access/hooks";
import { errorMessage } from "../features/services/format";
import { usePrototypeSession } from "../store/usePrototypeSession";

/**
 * Leaving, and being forgotten.
 *
 * Two requests that get confused with each other constantly, so they are drawn
 * as two different things rather than one control with a warning attached.
 * Most people who stop coming want the first, and would be dismayed to find
 * the second had happened; the few who want the second mean it.
 *
 * The temple's own congregation roll is not this app, and leaving does not
 * touch it. Being forgotten does not touch it either — it cannot; it is not
 * here. That is said out loud on the screen so nobody discovers it later.
 */

const CONFIRMATION = "DELETE";

function Line({ children, kept }: { children: string; kept: boolean }) {
  return (
    <View className="mt-2 flex-row items-start">
      <Ionicons
        name={kept ? "checkmark-circle-outline" : "close-circle-outline"}
        size={17}
        color={kept ? tokens.colors.peacock : tokens.colors.vermilion}
        style={{ marginTop: 2 }}
      />
      <Text className="ml-2 min-w-0 flex-1 font-sans text-sm leading-5 text-stone">
        {children}
      </Text>
    </View>
  );
}

export function LeaveOrForgetScreen() {
  const activeUserId = usePrototypeSession((state) => state.activeUserId);
  const signOut = usePrototypeSession((state) => state.signOut);
  const profile = useCurrentAccessProfile(activeUserId);
  const leave = useLeaveTheCommunity();
  const forget = useForgetMe();

  const [confirmation, setConfirmation] = useState("");
  const [showForget, setShowForget] = useState(false);

  const busy = leave.isPending || forget.isPending;
  const mayForget = confirmation.trim().toUpperCase() === CONFIRMATION;

  const failure =
    errorMessage(leave.error, "That could not be saved.") ??
    errorMessage(forget.error, "Your account could not be erased.");

  return (
    <Screen topInset={false}>
      <ScreenTitle eyebrow="Your account">Leaving</ScreenTitle>

      {/* ------------------------------------------------------------------ */}
      <View className="mb-section rounded-card border border-border bg-white p-card">
        <Text className="font-serif text-xl leading-7 text-stone">
          Step away for now
        </Text>
        <Text className="mt-2 font-sans text-sm leading-6 text-stoneMuted">
          The app stops asking anything of you. Nothing is erased, and nothing
          is lost — sign in whenever you like and everything is where you left
          it.
        </Text>

        <Line kept>Your profile and your seva stay exactly as they are</Line>
        <Line kept>The temple keeps you on its roll</Line>
        <Line kept={false}>Notifications stop</Line>

        <View className="mt-4">
          <Pressable
            className="min-h-touch flex-row items-center justify-center rounded-button border border-border bg-white px-5 py-3"
            accessibilityRole="button"
            accessibilityLabel="Step away for now"
            disabled={busy}
            onPress={() =>
              leave.mutate(undefined, { onSuccess: () => void signOut() })
            }
          >
            <Ionicons
              name="moon-outline"
              size={19}
              color={tokens.colors.indigo}
            />
            <Text className="ml-2 font-sans-bold text-base text-indigo">
              {leave.isPending ? "Stepping away…" : "Step away for now"}
            </Text>
          </Pressable>
        </View>
      </View>

      {/* ------------------------------------------------------------------ */}
      <View className="mb-section rounded-card border border-border bg-white p-card">
        <Text className="font-serif text-xl leading-7 text-stone">
          Be forgotten
        </Text>
        <Text className="mt-2 font-sans text-sm leading-6 text-stoneMuted">
          The temple stops holding who you are. This cannot be undone, and
          there is no way to bring any of it back afterwards.
        </Text>

        <Text className="mt-4 font-sans-bold text-xs uppercase tracking-wider text-stoneMuted">
          Erased for good
        </Text>
        <Line kept={false}>
          Your name, email, phone, address, date of birth and photograph
        </Line>
        <Line kept={false}>
          Your family, health and dietary notes, and your emergency contact
        </Line>
        <Line kept={false}>Your messages, and your sign-in</Line>

        <Text className="mt-4 font-sans-bold text-xs uppercase tracking-wider text-stoneMuted">
          Kept, with nobody’s name on it
        </Text>
        <Line kept>
          The seva that was served, so the temple’s hours still add up
        </Line>
        <Line kept>
          Giving records, which a temple must keep for its accounts
        </Line>
        <Text className="mt-2 font-sans text-xs leading-5 text-stoneMuted">
          Anything the temple holds outside this app — its own congregation
          records — is not touched by this. Ask the temple directly about those.
        </Text>

        {showForget ? (
          <View className="mt-4">
            <Text className="font-sans text-sm leading-5 text-stone">
              Type {CONFIRMATION} to confirm.
            </Text>
            <TextInput
              className="mt-2 min-h-touch rounded-button border border-border bg-white px-4 py-3 font-sans text-base text-stone"
              accessibilityLabel={`Type ${CONFIRMATION} to confirm erasing your account`}
              autoCapitalize="characters"
              autoCorrect={false}
              value={confirmation}
              onChangeText={setConfirmation}
              placeholder={CONFIRMATION}
              placeholderTextColor={tokens.colors.stoneMuted}
            />
            <Pressable
              className={`mt-3 min-h-touch flex-row items-center justify-center rounded-button px-5 py-3 ${
                mayForget && !busy ? "bg-vermilion" : "bg-vermilionSoft"
              }`}
              accessibilityRole="button"
              accessibilityLabel="Erase my account for good"
              accessibilityState={{ disabled: !mayForget || busy }}
              disabled={!mayForget || busy}
              onPress={() =>
                forget.mutate(profile.data?.photo_url ?? null, {
                  onSuccess: () => void signOut(),
                })
              }
            >
              <Text
                className={`font-sans-bold text-base ${
                  mayForget && !busy ? "text-white" : "text-vermilion"
                }`}
              >
                {forget.isPending ? "Erasing…" : "Erase my account for good"}
              </Text>
            </Pressable>
          </View>
        ) : (
          <View className="mt-4">
            <Pressable
              className="min-h-touch flex-row items-center justify-center rounded-button border border-vermilion bg-white px-5 py-3"
              accessibilityRole="button"
              accessibilityLabel="Be forgotten"
              disabled={busy}
              onPress={() => setShowForget(true)}
            >
              <Ionicons
                name="trash-outline"
                size={19}
                color={tokens.colors.vermilion}
              />
              <Text className="ml-2 font-sans-bold text-base text-vermilion">
                Be forgotten
              </Text>
            </Pressable>
          </View>
        )}
      </View>

      {failure ? (
        <View className="mb-section rounded-card border border-vermilion bg-vermilionSoft p-card">
          <Text className="font-sans text-sm leading-5 text-stone">
            {failure}
          </Text>
        </View>
      ) : null}
    </Screen>
  );
}
