import { Ionicons } from "@expo/vector-icons";
import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import type { ReactNode } from "react";
import { Text, View } from "react-native";

import tokens from "../../design-tokens.json";
import { CommunityEmailLink } from "../components/CommunityEmailLink";
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
      <ScreenTitle eyebrow="ISKCON Chicago">Terms of Service</ScreenTitle>

      <Text className="mb-section font-sans text-sm leading-6 text-stoneMuted">
        These Terms of Service govern your use of the ISKCON Chicago community
        app. Please read them together with Privacy and visibility, which
        explains what information is held and who may see it.
      </Text>

      <Card icon="checkmark-circle-outline" title="Agreement">
        <Paragraph>
          By creating an account or using the app, you agree to these terms. If
          you do not agree, please do not use the app and contact the President
          or an authorised temple administrator.
        </Paragraph>
      </Card>

      <Card icon="people-outline" title="Community access">
        <Paragraph>
          The app is intended for devotees and well-wishers participating in the
          ISKCON Chicago community. Every person must use their own account, and
          access levels are assigned according to temple responsibilities.
        </Paragraph>
        <Paragraph>
          ISKCON Chicago may approve, decline, change, suspend or revoke access
          when reasonably necessary to protect devotees, temple operations or
          the integrity of community records.
        </Paragraph>
      </Card>

      <Card icon="person-circle-outline" title="Account responsibility">
        <Paragraph>
          You must provide accurate information, including a current phone
          number, and keep your profile up to date. Do not share your password,
          allow another person to use your account or impersonate another
          devotee.
        </Paragraph>
        <Paragraph>
          Activity performed through your signed-in account may be treated as
          activity performed by you. Report suspected unauthorised access to an
          authorised temple administrator promptly.
        </Paragraph>
      </Card>

      <Card icon="heart-outline" title="Respectful community conduct">
        <Paragraph>
          Communicate with devotees respectfully and use messages, sangas,
          announcements and other community spaces only for appropriate temple
          and community purposes.
        </Paragraph>
        <Paragraph>
          Harassment, abusive or unlawful content, impersonation, unsolicited
          promotion, personal fundraising, misuse of private information and
          attempts to interfere with the app are prohibited.
        </Paragraph>
      </Card>

      <Card icon="hand-left-outline" title="Seva commitments and records">
        <Paragraph>
          Register only for seva you genuinely intend to perform. If your
          availability changes, update the app or contact the appropriate
          coordinator as early as possible so coverage can be arranged.
        </Paragraph>
        <Paragraph>
          Seva time, attendance, completion and verification must be recorded
          honestly. Authorised members may correct or review these records when
          needed for scheduling, accountability and temple administration.
        </Paragraph>
      </Card>

      <Card icon="image-outline" title="Content you share">
        <Paragraph>
          You retain ownership of content you submit. You give ISKCON Chicago
          permission to store, process and display that content within the app
          as needed to operate its community features and records.
        </Paragraph>
        <Paragraph>
          Share only content you are entitled to share. Exercise particular care
          with personal information and images of other devotees, especially
          children.
        </Paragraph>
      </Card>

      <Card icon="chatbubble-ellipses-outline" title="Messages and retention">
        <Paragraph>
          Messages and attached photos are retained as temple community records
          and may be viewed by specifically authorised leadership. Deleting a
          message or removing a conversation from your own inbox does not erase
          the retained record.
        </Paragraph>
        <Paragraph>
          This retention supports safety, accountability and continuity of
          temple administration. See Privacy and visibility for the exact
          behavior presented in the app.
        </Paragraph>
      </Card>

      <Card icon="cash-outline" title="Donations and third-party services">
        <Paragraph>
          Donation and sponsorship payments are completed on Zeffy, a
          third-party payment service. Zeffy's own terms and privacy practices
          apply to payment information submitted there. The app does not collect
          or store card details.
        </Paragraph>
      </Card>

      <Card
        icon="shield-checkmark-outline"
        title="Moderation and account closure"
      >
        <Paragraph>
          Authorised temple leadership may moderate content, restrict features,
          suspend access or close an account when these terms are breached or
          when reasonably required for community safety and temple operations.
          Users cannot delete their own account in the app; account questions or
          closure requests must be directed to an authorised administrator.
        </Paragraph>
      </Card>

      <Card
        icon="cloud-offline-outline"
        title="Availability and urgent matters"
      >
        <Paragraph>
          The app is provided for community coordination and may occasionally be
          unavailable, delayed or contain errors. It is not an emergency
          service. For urgent matters, contact the temple directly rather than
          relying on an app message or notification.
        </Paragraph>
      </Card>

      <Card icon="refresh-outline" title="Updates to these terms">
        <Paragraph>
          These terms may be updated as the app and temple services evolve. The
          revised date will be shown here. Continued use after an update means
          you accept the revised terms.
        </Paragraph>
      </Card>

      <View className="mt-section">
        <SectionHeader title="Questions" />
        <Paragraph>
          Contact the President or an authorised temple administrator with any
          question about these Terms of Service, your account or the temple's
          records.
        </Paragraph>
        <CommunityEmailLink subject="Terms of Service question" />
        <Text className="mt-4 font-sans text-xs uppercase tracking-wider text-stoneMuted">
          Effective 31 August 2026
        </Text>
      </View>
    </Screen>
  );
}
