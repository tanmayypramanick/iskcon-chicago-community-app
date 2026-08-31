import { Ionicons } from "@expo/vector-icons";
import { useEffect } from "react";
import { AccessibilityInfo, Modal, Pressable, Text, View } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";

import tokens from "../../design-tokens.json";

/**
 * The acknowledgement a devotee gets for tapping "Confirm my email".
 *
 * Until now this moment was silent: the link was consumed, a session appeared,
 * and the app simply opened — leaving the devotee to guess whether the tap had
 * worked at all. The confirmation email promises "one tap to confirm"; this is
 * the app keeping that promise.
 *
 * It takes two shapes, chosen by whether the devotee was already inside the app
 * when the link was opened. Somebody arriving fresh from their inbox has no
 * context and nothing to lose, so the confirmation is the whole screen and
 * doubles as the welcome. Somebody already signed in — confirming a changed
 * address, or re-opening a link out of doubt — is in the middle of something,
 * and taking the screen away from them to deliver good news would cost more
 * than it gives, so that case gets a dialog over the app instead.
 */

const VERIFIED_ANNOUNCEMENT =
  "Your email address is verified. Welcome to the ISKCON Chicago community.";

function VerifiedCard({
  headline,
  body,
  actionLabel,
  onContinue,
}: {
  headline: string;
  body: string;
  actionLabel: string;
  onContinue: () => void;
}) {
  // Drawn confirmation alone never reaches a devotee using VoiceOver or
  // TalkBack — the live region covers a reader already on the screen, and the
  // announcement covers the far commoner case of the screen having just
  // replaced whatever the reader was reading.
  useEffect(() => {
    AccessibilityInfo.announceForAccessibility(VERIFIED_ANNOUNCEMENT);
  }, []);

  return (
    <View
      className="w-full max-w-[430px] self-center items-center rounded-[28px] border border-border bg-ivory px-6 py-7"
      accessibilityLiveRegion="polite"
    >
      <View className="h-16 w-16 items-center justify-center rounded-pill bg-peacockSoft">
        <Ionicons
          name="checkmark-circle"
          size={34}
          color={tokens.colors.peacock}
        />
      </View>

      <Text className="mt-5 text-center font-display-italic text-sm text-marigold">
        Hare Kṛṣṇa
      </Text>
      <Text
        className="mt-1 text-center font-display text-[24px] leading-8 text-indigo"
        accessibilityRole="header"
      >
        {headline}
      </Text>
      <Text className="mt-3 text-center font-sans text-sm leading-6 text-stoneMuted">
        {body}
      </Text>

      <Pressable
        className="mt-6 h-12 w-full flex-row items-center justify-center rounded-pill bg-marigold"
        accessibilityRole="button"
        accessibilityLabel={actionLabel}
        onPress={onContinue}
      >
        <Text className="font-sans-bold text-base text-indigo">
          {actionLabel}
        </Text>
      </Pressable>

      <Text className="mt-4 text-center font-sans text-[11px] text-stoneMuted">
        Your servant, ISKCON Chicago
      </Text>
    </View>
  );
}

/** For a devotee who came straight from their inbox and is not in the app yet. */
export function EmailVerifiedScreen({
  onContinue,
}: {
  onContinue: () => void;
}) {
  return (
    <SafeAreaView
      className="flex-1 justify-center bg-sandalwood px-6"
      edges={["top", "bottom"]}
    >
      <VerifiedCard
        headline="Your email is verified"
        body="Your place in the temple community is open. The Deities’ darshan each morning, the seva that needs your hands, and every notice from the temple are yours from here."
        actionLabel="Enter the temple app"
        onContinue={onContinue}
      />
    </SafeAreaView>
  );
}

/** For a devotee who was already signed in; keeps them where they were. */
export function EmailVerifiedModal({
  visible,
  onDismiss,
}: {
  visible: boolean;
  onDismiss: () => void;
}) {
  return (
    <Modal
      visible={visible}
      transparent
      animationType="fade"
      onRequestClose={onDismiss}
    >
      {/* Literal rgba rather than an opacity utility: the scrim has to be the
          same on both platforms, and a missing colour here shows as an opaque
          black sheet over the app. */}
      <View
        className="flex-1 justify-center px-6"
        style={{ backgroundColor: "rgba(58, 52, 43, 0.6)" }}
      >
        <VerifiedCard
          headline="Your email is verified"
          body="Thank you — your address is confirmed and nothing further is needed. You can carry on exactly where you were."
          actionLabel="Continue"
          onContinue={onDismiss}
        />
      </View>
    </Modal>
  );
}
