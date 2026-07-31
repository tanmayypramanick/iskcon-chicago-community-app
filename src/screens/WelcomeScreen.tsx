import { Ionicons } from "@expo/vector-icons";
import { Text, View } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";

import tokens from "../../design-tokens.json";
import { Button, GarlandDivider } from "../components/ui";

export function WelcomeScreen({ onEnter }: { onEnter: () => void }) {
  return (
    <SafeAreaView className="flex-1 bg-ivory px-screen" edges={["top", "bottom"]}>
      <View className="flex-1 justify-between py-8">
        <View className="items-center">
          <View className="mb-5 flex-row items-center gap-2">
            <View className="h-2.5 w-2.5 rounded-pill bg-marigoldSoft" />
            <View className="h-3.5 w-3.5 rounded-pill bg-marigold" />
            <View className="h-2.5 w-2.5 rounded-pill bg-marigoldSoft" />
          </View>
          <Text className="font-sans-bold text-sm uppercase tracking-[3px] text-indigo">
            ISKCON Chicago
          </Text>
        </View>

        <View className="items-center">
          <View className="mb-8 h-28 w-28 items-center justify-center rounded-pill bg-sandalwood">
            <View className="h-16 w-16 items-center justify-center rounded-pill bg-marigoldSoft">
              <Ionicons
                name="flame-outline"
                size={38}
                color={tokens.colors.vermilion}
              />
            </View>
          </View>
          <Text
            className="text-center font-display text-[38px] leading-[46px] text-stone"
            accessibilityRole="header"
          >
            A welcoming place for seva and community
          </Text>
          <Text className="mt-5 max-w-sm text-center font-sans text-lg leading-7 text-stoneMuted">
            Stay connected, find opportunities to serve, and grow together.
          </Text>
          <GarlandDivider />
          <View className="rounded-card bg-indigoSoft px-5 py-4">
            <Text className="text-center font-sans text-base leading-6 text-indigo">
              This is a visual prototype. All people, schedules, and activities are sample data.
            </Text>
          </View>
        </View>

        <View className="gap-3">
          <Button onPress={onEnter} icon="arrow-forward">
            Preview the app
          </Button>
          <Button variant="secondary" icon="mail-outline" onPress={() => undefined}>
            Sign in with email or phone
          </Button>
        </View>
      </View>
    </SafeAreaView>
  );
}
