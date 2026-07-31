import { Ionicons } from "@expo/vector-icons";
import { Pressable, Text, View } from "react-native";

import tokens from "../../design-tokens.json";
import { InitialAvatar, Screen, ScreenTitle } from "../components/ui";
import { devotees } from "../data/mock";

export function DirectoryScreen() {
  return (
    <Screen>
      <ScreenTitle eyebrow="Our community">Directory</ScreenTitle>

      <Pressable
        className="mb-section min-h-touch flex-row items-center rounded-button border border-border bg-white px-4"
        accessibilityRole="search"
      >
        <Ionicons name="search" size={21} color={tokens.colors.stoneMuted} />
        <Text className="ml-3 font-sans text-base text-stoneMuted">
          Search by devotee name
        </Text>
      </Pressable>

      <View className="overflow-hidden rounded-card border border-border bg-white">
        {devotees.map((devotee, index) => (
          <Pressable
            key={devotee.name}
            className={`min-h-[76px] flex-row items-center px-card ${
              index < devotees.length - 1 ? "border-b border-border" : ""
            }`}
            accessibilityRole="button"
          >
            <InitialAvatar
              initials={devotee.initials}
              tone={devotee.tone}
            />
            <View className="ml-4 flex-1">
              <Text className="font-sans-bold text-lg text-stone">{devotee.name}</Text>
              <Text
                className={`mt-0.5 font-sans text-sm ${
                  devotee.detail === "At the temple" ? "text-peacock" : "text-stoneMuted"
                }`}
              >
                {devotee.detail}
              </Text>
            </View>
            <Ionicons name="chevron-forward" size={20} color={tokens.colors.indigo} />
          </Pressable>
        ))}
      </View>
    </Screen>
  );
}
