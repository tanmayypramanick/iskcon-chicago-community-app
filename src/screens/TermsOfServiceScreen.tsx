import { Ionicons } from "@expo/vector-icons";
import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import type { ReactNode } from "react";
import { Text, View } from "react-native";

import tokens from "../../design-tokens.json";
import { Screen, ScreenTitle, SectionHeader } from "../components/ui";
import type { ProfileStackParamList } from "../navigation/types";

type Props = NativeStackScreenProps<ProfileStackParamList, "TermsOfService">;

function Paragraph({ children }: { children: string }) {
  return (
    <Text className="mb-3 font-sans text-sm leading-6 text-stoneMuted">
      {children}
    </Text>
  );
}

function Card({
  icon,
  title,
  children,
}: {
  icon: keyof typeof Ionicons.glyphMap;
  title: string;
  children: ReactNode;
}) {
  return (
    <View className="mb-3 rounded-card border border-border bg-white p-card">
      <View className="mb-2 flex-row items-center">
        <View className="h-9 w-9 items-center justify-center rounded-pill bg-peacockSoft">
          <Ionicons name={icon} size={18} color={tokens.colors.peacock} />
        </View>
        <Text
          className="ml-3 min-w-0 flex-1 font-sans-bold text-base text-stone"
          accessibilityRole="header"
        >
          {title}
        </Text>
      </View>
      {children}
    </View>
  );
}

export function TermsOfServiceScreen(_: Props) {
  return (
    <Screen topInset={false}>
      <ScreenTitle eyebrow="Terms of use">Using this app</ScreenTitle>

      <Text className="mb-section font-sans text-sm leading-6 text-stoneMuted">
        This app belongs to one temple community, so its terms are short and
        written plainly. Please read them. What information the temple keeps,
        and who can see it, is set out separately on the Privacy and visibility
        page.
      </Text>

      <Card icon="checkmark-circle-outline" title="Accepting these terms">
        <Paragraph>
          Using the app means you accept what is written here. If there is
          something you cannot agree to, please speak to a community head or the
          President before you carry on.
        </Paragraph>
      </Card>

      <Card icon="people-outline" title="Who may use the app">
        <Paragraph>
          It is for the devotees and well-wishers of ISKCON Chicago. An account
          is needed for every screen, and access is granted by the temple.
        </Paragraph>
        <Paragraph>
          The temple may decline a request for access, or withdraw it later.
          That decision rests with a community head or the President, and you
          are always welcome to ask them about it.
        </Paragraph>
      </Card>

      <Card icon="person-circle-outline" title="Your account">
        <Paragraph>
          Keep your details accurate — your name, your photo, and a number or
          address that reaches you. Devotees arranging seva rely on them.
        </Paragraph>
        <Paragraph>
          Your password is yours alone. Please do not share it, and please do
          not sign in as anybody else. Whatever is done from your account is
          treated as done by you, so if you think someone else has got into it,
          tell a community head or the President straight away.
        </Paragraph>
      </Card>

      <Card icon="heart-outline" title="How we treat one another">
        <Paragraph>
          Messages and sangas here are part of temple life. Speak to devotees as
          you would in the temple room, and assume the same of them.
        </Paragraph>
        <Paragraph>
          No harassment, no abusive language, nothing unlawful. Please do not
          use the app to sell things, to raise money of your own, or to send
          devotees messages they have not asked for.
        </Paragraph>
      </Card>

      <Card icon="hand-left-outline" title="Seva you register for">
        <Paragraph>
          Registering for a seva is a commitment, and other devotees arrange
          their day around it. Once your name is against a seva, nobody else is
          looking for someone to fill it. So please offer only what you can
          truly serve. If something changes — as it does — say so as early as
          you can, rather than simply not turning up. Mark yourself unavailable
          in the app, or tell a community head or the President, so that
          somebody else has time to step in. Withdrawing early is not a failure.
          It is part of serving well.
        </Paragraph>
        <Paragraph>
          Register seva honestly, and confirm somebody else's seva only when you
          know it truly happened. The temple's records rest on that.
        </Paragraph>
      </Card>

      <Card icon="image-outline" title="What you post">
        <Paragraph>
          Your photos and your messages remain yours. The temple claims no
          ownership of them, only your permission to show them where you have
          posted them — your photo on your profile, your message in the
          conversation you sent it to.
        </Paragraph>
        <Paragraph>
          Please upload only what is yours to share, and be thoughtful with
          pictures of other devotees, especially children.
        </Paragraph>
      </Card>

      <Card icon="shield-checkmark-outline" title="What the temple may do">
        <Paragraph>
          Where these terms are broken, the temple may remove content, withdraw
          access to parts of the app, or close an account. Anything unsafe or
          unlawful may be acted on at once.
        </Paragraph>
        <Paragraph>
          These decisions are made by a community head or the President, and you
          may always ask them why.
        </Paragraph>
      </Card>

      <Card icon="cloud-offline-outline" title="The app as it is">
        <Paragraph>
          This app is offered as it stands, as a seva to the community, and it
          is not promised to be perfect or always available. It will sometimes
          be slow, down for maintenance, or mistaken. For anything urgent,
          please phone the temple rather than relying on the app alone.
        </Paragraph>
      </Card>

      <Card icon="refresh-outline" title="Changes to these terms">
        <Paragraph>
          These terms will change as the app grows, and the date below changes
          with them. Carrying on using the app after a change means you accept
          it.
        </Paragraph>
      </Card>

      <View className="mt-section">
        <SectionHeader title="Questions, and leaving" />
        <Paragraph>
          A community head or the President can answer anything about your
          account or about these terms.
        </Paragraph>
        <Paragraph>
          If you would like your account removed, ask a community head or the
          President and it will be done for you. There is no button in the app
          for it.
        </Paragraph>
        <Text className="mt-4 font-sans text-xs uppercase tracking-wider text-stoneMuted">
          Last updated 9 August 2026
        </Text>
      </View>
    </Screen>
  );
}
