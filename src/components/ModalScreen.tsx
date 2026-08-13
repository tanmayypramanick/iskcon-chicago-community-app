import { Ionicons } from "@expo/vector-icons";
import type { PropsWithChildren, ReactNode } from "react";
import { Modal, Pressable, ScrollView, Text, View } from "react-native";
import { SafeAreaProvider, SafeAreaView } from "react-native-safe-area-context";

import tokens from "../../design-tokens.json";
import { BotanicalBackdrop } from "./botanical";

type ModalScreenProps = PropsWithChildren<{
  visible: boolean;
  /** Both the back button and Android's hardware back. */
  onClose: () => void;
  title: string;
  /** The small line above the title, as on ScreenTitle. */
  eyebrow?: string;
  /** The right-hand end of the header, for a screen that needs one. */
  action?: ReactNode;
  /** What the back button announces. Defaults to naming the title. */
  backLabel?: string;
  /** Off when the body scrolls itself — a list, or its own Screen. */
  scroll?: boolean;
  /** Dark chrome over a full-bleed photograph. */
  tone?: "light" | "dark";
}>;

/**
 * A form or a photograph opened over the screen behind it, with the header
 * every one of them was missing: somewhere to go back to, a title saying where
 * you are, and top padding that matches the window it is actually in.
 *
 * That last one is the whole reason this exists. A Modal is its own window, so
 * the insets reaching it through React context are the *parent* window's and
 * the parent screen's own padding is not inherited at all. Under edge-to-edge —
 * which React Native forces on for a Modal whenever the app is edge-to-edge,
 * whatever `statusBarTranslucent` says, and which Android 15 enforces on the
 * app — the modal window starts at y=0, so a hand-rolled close button landed
 * underneath the status bar. On an iOS page sheet the opposite is true: the
 * sheet already starts below the status bar, so padding by the parent's inset
 * would push the header down by a status bar that is not there.
 *
 * The nested SafeAreaProvider settles both. It measures its own root view
 * against the window it is in, so the header below it pads by what genuinely
 * overlaps it — the status bar on Android, nothing on a page sheet — instead of
 * by a number carried in from another window.
 */
export function ModalScreen({
  visible,
  onClose,
  title,
  eyebrow,
  action,
  backLabel,
  scroll = true,
  tone = "light",
  children,
}: ModalScreenProps) {
  const dark = tone === "dark";

  return (
    <Modal
      visible={visible}
      animationType={dark ? "fade" : "slide"}
      transparent={dark}
      // A page sheet leaves the screen behind it in view on iOS. Android has no
      // equivalent and opens a full-screen window of its own regardless.
      presentationStyle={dark ? undefined : "pageSheet"}
      onRequestClose={onClose}
    >
      <SafeAreaProvider>
        <View className={`flex-1 ${dark ? "bg-black/95" : "bg-ivory"}`}>
          {dark ? null : <BotanicalBackdrop />}

          <SafeAreaView edges={["top"]}>
            <View
              className={`flex-row items-center px-screen py-2 ${
                dark ? "" : "border-b border-border"
              }`}
            >
              <Pressable
                className="-ml-2 mr-1 h-11 w-11 items-center justify-center rounded-pill"
                accessibilityRole="button"
                accessibilityLabel={backLabel ?? `Go back from ${title}`}
                onPress={onClose}
              >
                <Ionicons
                  name="chevron-back"
                  size={24}
                  color={dark ? tokens.colors.ivory : tokens.colors.indigo}
                />
              </Pressable>

              <View className="min-w-0 flex-1">
                {eyebrow ? (
                  <Text className="font-sans-bold text-[11px] uppercase tracking-widest text-peacock">
                    {eyebrow}
                  </Text>
                ) : null}
                <Text
                  className={`font-sans-bold text-base ${
                    dark ? "text-ivory" : "text-stone"
                  }`}
                  accessibilityRole="header"
                  numberOfLines={1}
                >
                  {title}
                </Text>
              </View>

              {action}
            </View>
          </SafeAreaView>

          {scroll ? (
            <ScrollView
              className="flex-1"
              contentContainerClassName="px-screen pt-2 pb-16"
              showsVerticalScrollIndicator={false}
              // As on Screen: without this the tap that reaches past the
              // keyboard only dismisses it, and the button underneath is never
              // pressed.
              keyboardShouldPersistTaps="handled"
            >
              {children}
            </ScrollView>
          ) : (
            <View className="flex-1">{children}</View>
          )}
        </View>
      </SafeAreaProvider>
    </Modal>
  );
}
