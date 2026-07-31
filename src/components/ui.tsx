import { Ionicons } from "@expo/vector-icons";
import type { PropsWithChildren, ReactNode } from "react";
import {
  Pressable,
  ScrollView,
  Text,
  View,
  type PressableProps,
} from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";

import tokens from "../../design-tokens.json";

type ScreenProps = PropsWithChildren<{
  scroll?: boolean;
  bottomInset?: boolean;
}>;

export function Screen({
  children,
  scroll = true,
  bottomInset = true,
}: ScreenProps) {
  if (!scroll) {
    return (
      <SafeAreaView className="flex-1 bg-ivory" edges={["top"]}>
        <View className="flex-1 px-screen">{children}</View>
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView className="flex-1 bg-ivory" edges={["top"]}>
      <ScrollView
        className="flex-1"
        contentContainerClassName={`px-screen pt-3 ${bottomInset ? "pb-28" : "pb-8"}`}
        showsVerticalScrollIndicator={false}
      >
        {children}
      </ScrollView>
    </SafeAreaView>
  );
}

export function ScreenTitle({
  eyebrow,
  children,
  action,
}: PropsWithChildren<{ eyebrow?: string; action?: ReactNode }>) {
  return (
    <View className="mb-section flex-row items-end justify-between">
      <View className="flex-1 pr-4">
        {eyebrow ? (
          <Text className="mb-1 font-sans-bold text-sm uppercase tracking-widest text-peacock">
            {eyebrow}
          </Text>
        ) : null}
        <Text
          className="font-display text-[30px] leading-9 text-stone"
          accessibilityRole="header"
        >
          {children}
        </Text>
      </View>
      {action}
    </View>
  );
}

export function SectionHeader({
  title,
  action,
}: {
  title: string;
  action?: string;
}) {
  return (
    <View className="mb-3 mt-2 flex-row items-center justify-between">
      <Text
        className="font-sans-bold text-xl text-stone"
        accessibilityRole="header"
      >
        {title}
      </Text>
      {action ? (
        <Text className="font-sans-bold text-base text-indigo">{action}</Text>
      ) : null}
    </View>
  );
}

export function GarlandDivider() {
  return (
    <View
      className="my-5 flex-row items-center"
      accessibilityElementsHidden
      importantForAccessibility="no-hide-descendants"
    >
      <View className="h-px flex-1 bg-border" />
      <View className="mx-3 flex-row gap-1.5">
        <View className="h-2.5 w-2.5 rounded-pill bg-marigold" />
        <View className="h-2.5 w-2.5 rounded-pill bg-marigoldSoft" />
        <View className="h-2.5 w-2.5 rounded-pill bg-marigold" />
      </View>
      <View className="h-px flex-1 bg-border" />
    </View>
  );
}

type ButtonProps = PressableProps &
  PropsWithChildren<{
    icon?: keyof typeof Ionicons.glyphMap;
    variant?: "primary" | "secondary";
  }>;

export function Button({
  children,
  icon,
  variant = "primary",
  ...pressableProps
}: ButtonProps) {
  const isPrimary = variant === "primary";

  return (
    <Pressable
      className={`min-h-touch flex-row items-center justify-center rounded-button px-5 py-3 ${
        isPrimary ? "bg-marigold" : "border border-border bg-white"
      }`}
      accessibilityRole="button"
      accessibilityLabel={typeof children === "string" ? children : undefined}
      {...pressableProps}
    >
      {icon ? (
        <Ionicons
          name={icon}
          size={20}
          color={isPrimary ? tokens.colors.stone : tokens.colors.indigo}
        />
      ) : null}
      <Text
        className={`font-sans-bold text-base ${
          icon ? "ml-2" : ""
        } ${isPrimary ? "text-stone" : "text-indigo"}`}
      >
        {children}
      </Text>
    </Pressable>
  );
}

export function InitialAvatar({
  initials,
  tone = "indigo",
  size = "medium",
}: {
  initials: string;
  tone?: "indigo" | "marigold" | "peacock";
  size?: "small" | "medium" | "large";
}) {
  const toneClass = {
    indigo: "bg-indigoSoft text-indigo",
    marigold: "bg-marigoldSoft text-stone",
    peacock: "bg-peacockSoft text-peacock",
  }[tone];
  const sizeClass = {
    small: "h-10 w-10 text-sm",
    medium: "h-12 w-12 text-base",
    large: "h-20 w-20 text-2xl",
  }[size];

  return (
    <View className={`${toneClass} ${sizeClass} items-center justify-center rounded-pill`}>
      <Text className={`font-sans-bold ${toneClass}`}>{initials}</Text>
    </View>
  );
}
