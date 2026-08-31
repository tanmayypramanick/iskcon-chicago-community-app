import { Alert, Linking, Text } from "react-native";

import { COMMUNITY_EMAIL, communityEmailUrl } from "../config/contact";

export function CommunityEmailLink({
  subject,
  className = "font-sans text-sm text-indigo underline",
}: {
  subject?: string;
  className?: string;
}) {
  const open = () => {
    void Linking.openURL(communityEmailUrl(subject)).catch(() => {
      Alert.alert(
        "Email could not be opened",
        `Please write to ${COMMUNITY_EMAIL}.`,
      );
    });
  };

  return (
    <Text
      className={className}
      accessibilityRole="link"
      accessibilityLabel={`Email ISKCON Chicago at ${COMMUNITY_EMAIL}`}
      onPress={open}
    >
      {COMMUNITY_EMAIL}
    </Text>
  );
}
