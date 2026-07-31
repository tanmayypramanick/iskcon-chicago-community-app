import { Ionicons } from "@expo/vector-icons";
import { Pressable, Text, View } from "react-native";

import tokens from "../../design-tokens.json";
import { Screen, ScreenTitle } from "../components/ui";
import { services } from "../data/mock";

export function ServicesScreen() {
  return (
    <View className="flex-1 bg-ivory">
      <Screen>
        <ScreenTitle eyebrow="Find a way to help">Services</ScreenTitle>

        <View className="mb-section flex-row gap-2">
          {["This week", "My services", "Completed"].map((label, index) => (
            <Pressable
              key={label}
              className={`min-h-11 justify-center rounded-pill px-4 ${
                index === 0 ? "bg-indigo" : "border border-border bg-white"
              }`}
            >
              <Text
                className={`font-sans-bold text-sm ${
                  index === 0 ? "text-white" : "text-stone"
                }`}
              >
                {label}
              </Text>
            </Pressable>
          ))}
        </View>

        <View className="gap-4">
          {services.map((service) => (
            <Pressable
              key={service.title}
              className="rounded-card border border-border bg-white p-card"
              accessibilityRole="button"
            >
              <View className="mb-3 flex-row items-center justify-between">
                <View
                  className={`rounded-pill px-3 py-1.5 ${
                    service.status === "Open" ? "bg-peacockSoft" : "bg-sandalwood"
                  }`}
                >
                  <Text
                    className={`font-sans-bold text-sm ${
                      service.status === "Open" ? "text-peacock" : "text-stoneMuted"
                    }`}
                  >
                    {service.status}
                  </Text>
                </View>
                <Ionicons name="chevron-forward" size={21} color={tokens.colors.indigo} />
              </View>
              <Text className="font-display text-[22px] leading-7 text-stone">
                {service.title}
              </Text>
              <View className="mt-3 flex-row items-center">
                <Ionicons name="time-outline" size={18} color={tokens.colors.stoneMuted} />
                <Text className="ml-2 font-sans text-base text-stoneMuted">
                  {service.time} · {service.duration}
                </Text>
              </View>
              <View className="mt-2 flex-row items-center">
                <Ionicons name="people-outline" size={18} color={tokens.colors.stoneMuted} />
                <Text className="ml-2 font-sans text-base text-stoneMuted">{service.slots}</Text>
              </View>
            </Pressable>
          ))}
        </View>
      </Screen>

      <Pressable
        className="absolute bottom-5 right-screen min-h-14 flex-row items-center rounded-pill bg-marigold px-5 shadow-lg"
        accessibilityRole="button"
        accessibilityLabel="Create a service request"
      >
        <Ionicons name="add" size={24} color={tokens.colors.stone} />
        <Text className="ml-2 font-sans-bold text-base text-stone">Create service</Text>
      </Pressable>
    </View>
  );
}
