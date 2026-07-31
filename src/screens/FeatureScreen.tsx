import { Ionicons } from "@expo/vector-icons";
import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import { Pressable, Text, View } from "react-native";

import tokens from "../../design-tokens.json";
import { Button, GarlandDivider, Screen, ScreenTitle } from "../components/ui";
import { featureContent } from "../data/mock";
import type { RootStackParamList } from "../navigation/types";

type Props = NativeStackScreenProps<RootStackParamList, "Feature">;

export function FeatureScreen({ route }: Props) {
  const content = featureContent[route.params.feature];

  return (
    <Screen>
      <ScreenTitle eyebrow={content.eyebrow}>{route.params.title}</ScreenTitle>

      <View className="rounded-card bg-sandalwood p-card">
        <Text className="font-sans text-lg leading-7 text-stone">{content.intro}</Text>
      </View>

      <GarlandDivider />
      <View className="gap-4">
        {content.cards.map((card, index) => (
          <Pressable
            key={card.title}
            className="rounded-card border border-border bg-white p-card"
            accessibilityRole="button"
          >
            <View className="flex-row items-start justify-between">
              <View className="mr-4 h-11 w-11 items-center justify-center rounded-pill bg-indigoSoft">
                <Ionicons
                  name={index === 0 ? "sparkles-outline" : "leaf-outline"}
                  size={22}
                  color={tokens.colors.indigo}
                />
              </View>
              <View className="flex-1">
                <Text className="font-sans-bold text-lg text-stone">{card.title}</Text>
                <Text className="mt-1 font-sans text-base leading-6 text-stoneMuted">
                  {card.detail}
                </Text>
                <Text className="mt-3 font-sans-bold text-sm text-peacock">{card.meta}</Text>
              </View>
              <Ionicons name="chevron-forward" size={20} color={tokens.colors.indigo} />
            </View>
          </Pressable>
        ))}
      </View>

      <View className="mt-section">
        <Button icon="arrow-forward" onPress={() => undefined}>
          {content.action}
        </Button>
      </View>

      <Text className="mt-4 text-center font-sans text-sm leading-5 text-stoneMuted">
        Preview only—content and actions are not connected to live data yet.
      </Text>
    </Screen>
  );
}
