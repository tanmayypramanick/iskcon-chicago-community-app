import { Ionicons } from "@expo/vector-icons";
import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import { Text, View } from "react-native";

import tokens from "../../design-tokens.json";
import { Screen, ScreenTitle, SectionHeader } from "../components/ui";
import type { ProfileStackParamList } from "../navigation/types";

type Props = NativeStackScreenProps<ProfileStackParamList, "PrivacyVisibility">;

type Tone = "peacock" | "indigo" | "marigold";

const toneStyles: Record<Tone, { bubble: string; color: string }> = {
  peacock: { bubble: "bg-peacockSoft", color: tokens.colors.peacock },
  indigo: { bubble: "bg-indigoSoft", color: tokens.colors.indigo },
  marigold: { bubble: "bg-marigoldSoft", color: tokens.colors.stone },
};

function RuleCard({
  icon,
  tone = "peacock",
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

/**
 * What the app holds about a devotee and who can reach it — a different
 * question from the Terms of Service, which is the agreement itself. Every line
 * here is checked against the schema and the screens, not against intent. The
 * app has no per-field privacy switches, and showing toggles that changed
 * nothing would be a lie told in a friendly voice.
 */
export function PrivacyVisibilityScreen(_: Props) {
  return (
    <Screen topInset={false}>
      <ScreenTitle eyebrow="Privacy">Your information</ScreenTitle>

      <Text className="mb-section font-sans text-sm leading-5 text-stoneMuted">
        What the app keeps about you, and who can see it. This describes the app
        as it works today. Nothing below is aspirational.
      </Text>

      <SectionHeader title="What the community sees" />

      <RuleCard
        icon="people-outline"
        title="Your name and photo"
        body="Every signed-in devotee can find you in the Directory by your name and your photo. The same name and photo appear beside you in seva lists and in any sanga you belong to, along with your access level."
      />
      {/* devotee_public_profile returns email and date of birth to every
          signed-in devotee, and DevoteeProfileScreen renders both. Listing them
          as private, as this screen once did, was simply untrue. */}
      <RuleCard
        icon="person-circle-outline"
        title="Your profile page"
        body="Opening your name in the Directory shows a devotee your photo, access level, joined date, email address, gender, date of birth, age and occupation. Your phone number, home address, family information and spiritual details are not shown to the wider community."
      />
      <RuleCard
        icon="time-outline"
        title="Your seva"
        body="Most devotees see only their own seva and the open needs anyone can join. The whole schedule and every devotee's completed seva are kept as part of the temple's records, which a community head or the President works from, because arranging seva depends on it. Seva you register yourself stays between you and the devotee you asked to confirm it until it is verified."
      />
      <RuleCard
        icon="checkmark-done-outline"
        title="Whether you turned up"
        body="Once a seva has started, the devotee who posted it can record you as having served, been absent, or been excused. That stays in the temple's records with the seva. If you are marked as not attending, the app tells you, so you can say if it is wrong."
      />
      <RuleCard
        icon="location-outline"
        title="Your presence at the temple"
        body="The At the temple switch is yours. While it is on, every signed-in devotee sees you on today's list; switching it off takes you off that list at once. The times you checked in and out stay in the temple's records. The app never checks you in by itself — if you allow location, your phone works out on its own whether you are near the temple and reminds you here. Where you are is never sent to the temple."
      />

      <View className="mt-section">
        <SectionHeader title="What the temple's records hold" />
      </View>

      <RuleCard
        icon="lock-closed-outline"
        tone="marigold"
        title="Your personal details"
        body="Your address, phone number, birth place, marital status, and details of your spouse and children are kept as part of the temple's records — the same details a temple has always kept about its congregation. They are not shown to the community and never appear in the Directory."
      />
      <RuleCard
        icon="flower-outline"
        tone="marigold"
        title="Your spiritual details"
        body="Whether you are initiated, your initiation dates, your diksha guru, your spiritual mentor and your daily rounds are kept the same way, and are not shown to the community. The temple keeps them so weekly seva can be offered that suits where you are in your practice. None of it is a requirement for seva."
      />
      {/* delete_message nulls body/image_url but moves the old values into
          original_body/original_image_url (202608040037). This card must not
          promise that deleting destroys anything. */}
      <RuleCard
        icon="chatbubble-ellipses-outline"
        tone="marigold"
        title="Your messages"
        body="Messages and photos are retained as part of the temple's records. Deleting a message removes it from the devotees' thread but retains its original content for authorised oversight. Removing a complete conversation clears the existing thread from your own Messages view only; it does not erase the temple record, and a new message will bring the conversation back."
      />
      <RuleCard
        icon="key-outline"
        tone="indigo"
        title="Nobody outside the temple"
        body="The app needs a signed-in account for every screen. There is no public page and no guest view, so nothing here is visible to anyone outside the temple community."
      />

      <View className="mt-section">
        <SectionHeader title="What is in your hands" />
      </View>

      <RuleCard
        icon="notifications-outline"
        tone="indigo"
        title="Notifications"
        body="The app writes to you about seva invitations and answers, coverage that is needed, verification asked of you or given to you, a reminder about an hour before your seva, decisions on access requests, and a daily nudge while your profile is unfinished. Notification settings lists every one of them, and takes you to where banners are turned on and off. A notification always waits for you in the bell here either way."
      />
      <RuleCard
        icon="create-outline"
        tone="indigo"
        title="Keeping your details correct"
        body="Profile details is where you change what the temple holds — your name, your photo, your contact details, your family and your spiritual life. What you save takes effect straight away, everywhere the app shows it. If something is wrong and you cannot change it yourself, please speak to a community head or the President."
      />

      <View className="mt-section rounded-card border border-border bg-white p-card">
        <View className="flex-row items-center">
          <Ionicons
            name="information-circle-outline"
            size={19}
            color={tokens.colors.stoneMuted}
          />
          <Text className="ml-2 font-sans-bold text-base text-stone">
            Why there are no switches here
          </Text>
        </View>
        <Text className="mt-2 font-sans text-sm leading-5 text-stoneMuted">
          The app does not yet have per-field visibility controls, so this page
          explains what is held rather than pretending to change it.
        </Text>
        <Text className="mt-3 font-sans text-sm leading-5 text-stone">
          If anything here concerns you, please speak to a community head or the
          President.
        </Text>
      </View>
    </Screen>
  );
}
