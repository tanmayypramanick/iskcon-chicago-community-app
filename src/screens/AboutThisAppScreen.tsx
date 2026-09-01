import { Ionicons } from "@expo/vector-icons";
import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import Constants from "expo-constants";
import { Alert, Linking, Text, View } from "react-native";

import tokens from "../../design-tokens.json";
import { CommunityEmailLink } from "../components/CommunityEmailLink";
import { Screen, ScreenTitle, SectionHeader } from "../components/ui";
import type { ProfileStackParamList } from "../navigation/types";

type Props = NativeStackScreenProps<ProfileStackParamList, "AboutThisApp">;

const builderUrl = "https://tanmaypramanick.vercel.app/";

type Tone = "peacock" | "indigo" | "marigold";

const toneStyles: Record<Tone, { bubble: string; color: string }> = {
  peacock: { bubble: "bg-peacockSoft", color: tokens.colors.peacock },
  indigo: { bubble: "bg-indigoSoft", color: tokens.colors.indigo },
  marigold: { bubble: "bg-marigoldSoft", color: tokens.colors.stone },
};

function AreaCard({
  icon,
  tone = "indigo",
  title,
  body,
}: {
  icon: keyof typeof Ionicons.glyphMap;
  tone?: Tone;
  title: string;
  body: string;
}) {
  const { bubble, color } = toneStyles[tone];

  return (
    <View className="mb-3 flex-row rounded-card border border-border bg-white p-card">
      <View
        className={`h-10 w-10 items-center justify-center rounded-pill ${bubble}`}
      >
        <Ionicons name={icon} size={19} color={color} />
      </View>
      <View className="ml-3 min-w-0 flex-1">
        <Text className="font-sans-bold text-base text-stone">{title}</Text>
        <Text className="mt-1 font-sans text-sm leading-5 text-stoneMuted">
          {body}
        </Text>
      </View>
    </View>
  );
}

export function AboutThisAppScreen(_: Props) {
  // Read from the manifest rather than hardcoded, so a released build can never
  // show a version it is not.
  const version = Constants.expoConfig?.version;

  const openBuilderSite = () => {
    void Linking.openURL(builderUrl).catch(() => {
      Alert.alert("That link could not be opened.");
    });
  };

  return (
    <Screen topInset={false}>
      <ScreenTitle eyebrow="About">About this app</ScreenTitle>

      <Text className="mb-section font-sans text-sm leading-6 text-stoneMuted">
        This is the community app for ISKCON Chicago. Devotees use it to find
        and register for seva, follow the temple's schedule, keep their details
        current with the temple, message one another, and join a sanga.
      </Text>

      <SectionHeader title="What each part does" />

      <AreaCard
        icon="home-outline"
        tone="peacock"
        title="Home"
        body="Check in when you arrive, see which devotees are at the temple today, and find your next seva at a glance."
      />
      <AreaCard
        icon="heart-outline"
        tone="marigold"
        title="Seva"
        body="The temple’s schedule and every open request. Find a way to help, record completed seva for a community leader to verify, arrange coverage when you cannot attend, and follow your seva history."
      />
      <AreaCard
        icon="people-outline"
        tone="indigo"
        title="Devotees"
        body="Your messages with other devotees, the sangas you can join, and a directory of the congregation by name and face."
      />
      <AreaCard
        icon="person-circle-outline"
        tone="indigo"
        title="Profile"
        body="Your details as the temple holds them, the access level you have and what it allows, and how the app notifies you."
      />

      <View className="mt-section">
        <SectionHeader title="Why it was made" />
      </View>

      <View className="mb-section rounded-card border border-border bg-white p-card">
        <Text className="font-sans text-sm leading-6 text-stoneMuted">
          The temple's seva used to live in spreadsheets and group chats, where
          a request is easy to miss and easy to forget. This app gathers it into
          one place so that taking part in the temple's service and community
          life is simple — see what is needed, offer your help, and keep the
          temple up to date with you.
        </Text>
      </View>

      <SectionHeader title="Who made it" />

      <View className="rounded-card border border-border bg-white p-card">
        <View className="flex-row items-center">
          <View className="h-10 w-10 items-center justify-center rounded-pill bg-indigoSoft">
            <Ionicons
              name="code-slash-outline"
              size={19}
              color={tokens.colors.indigo}
            />
          </View>
          <View className="ml-3 min-w-0 flex-1">
            <Text className="font-sans text-sm leading-5 text-stoneMuted">
              Designed and built by
            </Text>
            <Text
              className="mt-0.5 font-sans-bold text-base leading-6 text-indigo underline"
              accessibilityRole="link"
              accessibilityHint="Opens tanmaypramanick.vercel.app in your browser"
              onPress={openBuilderSite}
            >
              Tanmay Pramanick
            </Text>
          </View>
          <Ionicons
            name="open-outline"
            size={19}
            color={tokens.colors.stoneMuted}
          />
        </View>

        <View className="mt-4 flex-row border-t border-border pt-4">
          <Ionicons
            name="leaf-outline"
            size={19}
            color={tokens.colors.peacock}
          />
          <Text className="ml-3 flex-1 font-sans text-sm leading-6 text-stone">
            Created as a humble offering of seva to Śrī Śrī Kiśora-Kiśorī and
            the devotees of ISKCON Chicago. May it bring our temple family
            closer, make service easier, and help every devotee feel at home.
          </Text>
        </View>
      </View>

      <View className="mt-section">
        <SectionHeader title="Contact ISKCON Chicago" />
      </View>

      <View className="rounded-card border border-border bg-white p-card">
        <View className="flex-row items-start">
          <View className="h-10 w-10 items-center justify-center rounded-pill bg-peacockSoft">
            <Ionicons
              name="mail-outline"
              size={19}
              color={tokens.colors.peacock}
            />
          </View>
          <View className="ml-3 min-w-0 flex-1">
            <Text className="font-sans text-sm leading-5 text-stoneMuted">
              For account help, privacy questions, or support with the app,
              write to our temple technology seva.
            </Text>
            <View className="mt-2">
              <CommunityEmailLink subject="ISKCON Chicago app support" />
            </View>
          </View>
        </View>
      </View>

      {version ? (
        <Text className="mt-section text-center font-sans text-xs text-stoneMuted">
          Version {version}
        </Text>
      ) : null}
    </Screen>
  );
}
