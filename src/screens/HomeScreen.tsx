import { Ionicons } from "@expo/vector-icons";
import {
  useNavigation,
  type NavigationProp,
} from "@react-navigation/native";
import { Pressable, Text, View } from "react-native";

import tokens from "../../design-tokens.json";
import {
  GarlandDivider,
  InitialAvatar,
  Screen,
  ScreenTitle,
  SectionHeader,
} from "../components/ui";
import { communityFeatures } from "../data/mock";
import type { RootStackParamList } from "../navigation/types";

export function HomeScreen() {
  const navigation = useNavigation<NavigationProp<RootStackParamList>>();

  return (
    <Screen>
      <ScreenTitle eyebrow="Thursday, July 30">Hare Krishna</ScreenTitle>

      <Pressable
        className="mb-section flex-row items-center rounded-card bg-peacock px-card py-card"
        accessibilityRole="switch"
        accessibilityState={{ checked: true }}
      >
        <View className="mr-4 h-12 w-12 items-center justify-center rounded-pill bg-white/20">
          <Ionicons name="location" size={24} color={tokens.colors.white} />
        </View>
        <View className="flex-1">
          <Text className="font-sans-bold text-lg text-white">You’re at the temple</Text>
          <Text className="mt-0.5 font-sans text-sm text-white">
            Tap when you leave
          </Text>
        </View>
        <Ionicons name="toggle" size={35} color={tokens.colors.white} />
      </Pressable>

      <SectionHeader title="At the temple today" action="See all" />
      <View className="mb-section flex-row gap-4 rounded-card border border-border bg-white p-card">
        {[
          { initials: "AD", name: "Ananda" },
          { initials: "BP", name: "Bhakti" },
          { initials: "MD", name: "Madhavi" },
        ].map((person, index) => (
          <View key={person.initials} className="items-center">
            <InitialAvatar
              initials={person.initials}
              tone={index === 1 ? "marigold" : "peacock"}
            />
            <Text className="mt-2 font-sans text-sm text-stone">{person.name}</Text>
          </View>
        ))}
      </View>

      <SectionHeader title="Your next service" action="View schedule" />
      <View className="rounded-card bg-indigo p-card">
        <View className="mb-4 flex-row items-start justify-between">
          <View className="rounded-pill bg-white/15 px-3 py-1.5">
            <Text className="font-sans-bold text-sm text-white">Today · 3:30 PM</Text>
          </View>
          <Ionicons name="heart" size={22} color={tokens.colors.marigoldSoft} />
        </View>
        <Text className="font-display text-2xl text-white">Sunday Feast Kitchen</Text>
        <Text className="mt-2 font-sans text-base text-white">
          Kitchen · 2 hours · Meet near the pantry
        </Text>
      </View>

      <GarlandDivider />
      <SectionHeader title="Explore the community" />
      <View className="flex-row flex-wrap justify-between">
        {communityFeatures.map((feature) => (
          <Pressable
            key={feature.key}
            className="mb-3 min-h-36 w-[48%] justify-between rounded-card border border-border bg-sandalwood p-4"
            accessibilityRole="button"
            onPress={() =>
              navigation.navigate("Feature", {
                feature: feature.key,
                title: feature.title,
              })
            }
          >
            <View className="h-11 w-11 items-center justify-center rounded-pill bg-ivory">
              <Ionicons
                name={feature.icon as keyof typeof Ionicons.glyphMap}
                size={23}
                color={tokens.colors.indigo}
              />
            </View>
            <View>
              <Text className="font-sans-bold text-lg text-stone">{feature.title}</Text>
              <Text className="mt-1 font-sans text-sm leading-5 text-stoneMuted">
                {feature.subtitle}
              </Text>
            </View>
          </Pressable>
        ))}
      </View>
    </Screen>
  );
}
