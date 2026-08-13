import { Ionicons } from "@expo/vector-icons";
import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import { Linking, Text, View } from "react-native";

import tokens from "../../design-tokens.json";
import { Button, Screen, ScreenTitle, SectionHeader } from "../components/ui";
import type { ProfileStackParamList } from "../navigation/types";

type Props = NativeStackScreenProps<
  ProfileStackParamList,
  "NotificationSettings"
>;

type NotificationGroup = {
  icon: keyof typeof Ionicons.glyphMap;
  title: string;
  /** One line, in devotee language, for when the app actually sends it. */
  when: string;
};

const groups: NotificationGroup[] = [
  {
    icon: "hand-left-outline",
    title: "Seva invitations and answers",
    when: "When a seva opens that you can join, when somebody asks you to take one, and when a devotee accepts, declines, proposes another time, or joins or leaves a seva you posted.",
  },
  {
    icon: "swap-horizontal-outline",
    title: "Coverage requests",
    when: "When a devotee cannot serve their weekly seva and cover is needed, and again once somebody has taken it up.",
  },
  {
    icon: "shield-checkmark-outline",
    title: "Verification requests and outcomes",
    when: "When a devotee asks you to confirm seva they served, and when your own registered seva or your weekly-seva profile is verified or sent back.",
  },
  {
    icon: "alarm-outline",
    title: "Reminders before your seva",
    when: "About an hour before a seva you are assigned to begins, once per seva. You are also told if that seva is cancelled, removed, or marked complete.",
  },
  {
    icon: "key-outline",
    title: "Access requests",
    when: "When your request for additional access is decided — and, if your access level allows it, when a devotee submits one.",
  },
  {
    icon: "person-outline",
    title: "Profile reminders",
    when: "Once a day at most while your profile is still incomplete. It stops on its own the moment you finish it.",
  },
];

export function NotificationSettingsScreen(_: Props) {
  return (
    <Screen topInset={false}>
      <ScreenTitle eyebrow="Notifications">What the app sends you</ScreenTitle>

      <Text className="mb-section font-sans text-sm leading-5 text-stoneMuted">
        Everything below arrives in your notification bell inside the app. It
        also reaches your phone as a banner if you have allowed it there.
      </Text>

      <SectionHeader title="Why you hear from us" />

      {groups.map((group) => (
        <View
          key={group.title}
          className="mb-3 flex-row rounded-card border border-border bg-white p-card"
        >
          <View className="h-10 w-10 items-center justify-center rounded-pill bg-peacockSoft">
            <Ionicons
              name={group.icon}
              size={19}
              color={tokens.colors.peacock}
            />
          </View>
          <View className="ml-3 min-w-0 flex-1">
            <Text className="font-sans-bold text-base text-stone">
              {group.title}
            </Text>
            <Text className="mt-1 font-sans text-sm leading-5 text-stoneMuted">
              {group.when}
            </Text>
          </View>
        </View>
      ))}

      <View className="mt-section">
        <SectionHeader title="Banners on your phone" />
      </View>

      <View className="rounded-card border border-border bg-white p-card">
        <View className="flex-row items-center">
          <View className="h-10 w-10 items-center justify-center rounded-pill bg-marigoldSoft">
            <Ionicons
              name="notifications-outline"
              size={19}
              color={tokens.colors.stone}
            />
          </View>
          <Text className="ml-3 min-w-0 flex-1 font-sans-bold text-base text-stone">
            Push needs your device's permission
          </Text>
        </View>
        <Text className="mt-3 font-sans text-sm leading-5 text-stoneMuted">
          Push notifications are granted by your phone, not by this app, so they
          are turned on and off in your device settings. On Android they arrive
          in two channels — “Temple reminders” and “Community and seva updates”
          — which can be adjusted separately.
        </Text>
        <Text className="mt-3 font-sans text-sm leading-5 text-stoneMuted">
          Turning banners off never stops a notification reaching you here. It
          waits for you in the bell either way.
        </Text>
        <View className="mt-4">
          <Button
            icon="settings-outline"
            accessibilityLabel="Open notification settings"
            onPress={() => void Linking.openSettings()}
          >
            Open notification settings
          </Button>
        </View>
      </View>
    </Screen>
  );
}
