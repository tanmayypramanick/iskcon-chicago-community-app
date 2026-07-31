import { Ionicons } from "@expo/vector-icons";
import { Pressable, Text, View } from "react-native";

import tokens from "../../design-tokens.json";
import {
  Button,
  GarlandDivider,
  InitialAvatar,
  Screen,
  ScreenTitle,
  SectionHeader,
} from "../components/ui";

export function ProfileScreen() {
  return (
    <Screen>
      <ScreenTitle eyebrow="Your space">Profile</ScreenTitle>

      <View className="items-center rounded-card border border-border bg-white p-card">
        <InitialAvatar initials="GS" tone="marigold" size="large" />
        <Text className="mt-4 font-display text-2xl text-stone">Gauranga Sharma</Text>
        <Text className="mt-1 font-sans text-base text-stoneMuted">Member · Chicago</Text>
        <View className="mt-4 rounded-pill bg-peacockSoft px-4 py-2">
          <Text className="font-sans-bold text-sm text-peacock">At the temple</Text>
        </View>
      </View>

      <GarlandDivider />
      <SectionHeader title="My seva" action="See all" />
      <View className="mb-section rounded-card bg-indigo p-card">
        <Text className="font-sans-bold text-sm uppercase tracking-wider text-marigoldSoft">
          Next assignment
        </Text>
        <Text className="mt-3 font-display text-xl text-white">Sunday Feast Kitchen</Text>
        <Text className="mt-1 font-sans text-base text-white">Today · 3:30 PM</Text>
      </View>

      <SectionHeader title="Profile and settings" />
      <View className="mb-4 overflow-hidden rounded-card border border-border bg-white">
        {[
          { icon: "person-outline", label: "Personal information" },
          { icon: "notifications-outline", label: "Notifications" },
          { icon: "shield-checkmark-outline", label: "Privacy and visibility" },
          { icon: "help-circle-outline", label: "Help" },
        ].map((item, index, list) => (
          <Pressable
            key={item.label}
            className={`min-h-touch flex-row items-center px-card py-3 ${
              index < list.length - 1 ? "border-b border-border" : ""
            }`}
          >
            <Ionicons
              name={item.icon as keyof typeof Ionicons.glyphMap}
              size={22}
              color={tokens.colors.indigo}
            />
            <Text className="ml-4 flex-1 font-sans text-base text-stone">{item.label}</Text>
            <Ionicons name="chevron-forward" size={19} color={tokens.colors.stoneMuted} />
          </Pressable>
        ))}
      </View>

      <Button variant="secondary" icon="log-out-outline" onPress={() => undefined}>
        Return to sign in
      </Button>
    </Screen>
  );
}
