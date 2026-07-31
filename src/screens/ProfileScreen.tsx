import { Ionicons } from "@expo/vector-icons";
import { Pressable, Text, View } from "react-native";

import tokens from "../../design-tokens.json";
import {
  Button,
  GarlandDivider,
  InitialAvatar,
  Screen,
  ScreenTitle,
  SectionHeader,
} from "../components/ui";
import {
  type AccessRole,
  usePrototypeSession,
} from "../store/usePrototypeSession";

type RolePresentation = {
  shortLabel: string;
  title: string;
  description: string;
  badgeClass: string;
  badgeTextClass: string;
  icon: keyof typeof Ionicons.glyphMap;
  access: Array<{
    icon: keyof typeof Ionicons.glyphMap;
    title: string;
    detail: string;
  }>;
};

const roles: Record<AccessRole, RolePresentation> = {
  president: {
    shortLabel: "President",
    title: "President access",
    description:
      "A clear leadership view for temple-wide service, communication, and oversight.",
    badgeClass: "bg-marigoldSoft",
    badgeTextClass: "text-stone",
    icon: "shield-checkmark",
    access: [
      {
        icon: "heart-outline",
        title: "Assign and coordinate seva",
        detail: "Create recurring assignments and support service teams.",
      },
      {
        icon: "megaphone-outline",
        title: "Publish announcements",
        detail: "Share important temple updates with the community.",
      },
      {
        icon: "wallet-outline",
        title: "Review donation records",
        detail: "Open the private donation and reporting workspace.",
      },
      {
        icon: "grid-outline",
        title: "Guide community spaces",
        detail: "Approve courses, create communities, and moderate the forum.",
      },
    ],
  },
  tech: {
    shortLabel: "Tech",
    title: "Tech access",
    description:
      "A focused technical workspace for keeping the app reliable and supporting its users.",
    badgeClass: "bg-indigoSoft",
    badgeTextClass: "text-indigo",
    icon: "code-slash",
    access: [
      {
        icon: "pulse-outline",
        title: "App health and issue reports",
        detail: "Review reported problems and service status in one place.",
      },
      {
        icon: "key-outline",
        title: "Access configuration review",
        detail: "See role settings before approved changes are applied.",
      },
      {
        icon: "construct-outline",
        title: "Content support tools",
        detail: "Help authorized leaders resolve app and content issues.",
      },
    ],
  },
  core: {
    shortLabel: "Core member",
    title: "Core member access",
    description:
      "Practical coordination tools for trusted members helping with daily community life.",
    badgeClass: "bg-peacockSoft",
    badgeTextClass: "text-peacock",
    icon: "people",
    access: [
      {
        icon: "calendar-outline",
        title: "Coordinate open seva",
        detail: "Help organize service needs and keep teams informed.",
      },
      {
        icon: "chatbubbles-outline",
        title: "Support community updates",
        detail: "Prepare helpful updates for the groups you support.",
      },
      {
        icon: "book-outline",
        title: "Assist learning and discussion",
        detail: "Support assigned courses and healthy conversations.",
      },
    ],
  },
  devotee: {
    shortLabel: "Devotee",
    title: "Devotee access",
    description:
      "A peaceful personal space for seva, temple connection, and spiritual growth.",
    badgeClass: "bg-sandalwood",
    badgeTextClass: "text-stone",
    icon: "heart",
    access: [
      {
        icon: "hand-left-outline",
        title: "Join and record seva",
        detail: "Find open services and keep track of your participation.",
      },
      {
        icon: "location-outline",
        title: "Share temple availability",
        detail: "Let the community know when you are at the temple.",
      },
      {
        icon: "people-outline",
        title: "Connect with devotees",
        detail: "Use the directory and take part in community spaces.",
      },
      {
        icon: "leaf-outline",
        title: "Continue spiritual learning",
        detail: "See courses, announcements, and your personal journey.",
      },
    ],
  },
};

function RoleSelector({
  selectedRole,
  onSelect,
}: {
  selectedRole: AccessRole;
  onSelect: (role: AccessRole) => void;
}) {
  return (
    <View className="flex-row flex-wrap justify-between gap-y-2">
      {(Object.keys(roles) as AccessRole[]).map((role) => {
        const selected = role === selectedRole;

        return (
          <Pressable
            key={role}
            className={`min-h-touch w-[49%] flex-row items-center justify-center rounded-button border px-2 py-2 ${
              selected ? "border-indigo bg-indigo" : "border-border bg-white"
            }`}
            accessibilityRole="button"
            accessibilityState={{ selected }}
            accessibilityLabel={`Preview ${roles[role].shortLabel} access`}
            onPress={() => onSelect(role)}
          >
            <Ionicons
              name={roles[role].icon}
              size={18}
              color={selected ? tokens.colors.white : tokens.colors.indigo}
            />
            <Text
              className={`ml-2 font-sans-bold text-sm ${
                selected ? "text-white" : "text-indigo"
              }`}
            >
              {roles[role].shortLabel}
            </Text>
          </Pressable>
        );
      })}
    </View>
  );
}

export function ProfileScreen({ onSignOut }: { onSignOut: () => void }) {
  const role = usePrototypeSession((state) => state.role);
  const setRole = usePrototypeSession((state) => state.setRole);
  const selectedRole = roles[role];

  return (
    <Screen>
      <ScreenTitle eyebrow="Your space">Profile</ScreenTitle>

      <View className="overflow-hidden rounded-card border border-border bg-white">
        <View className="h-2 bg-marigold" />
        <View className="items-center p-card">
          <InitialAvatar initials="GS" tone="marigold" size="large" />
          <Text className="mt-4 text-center font-display text-2xl text-stone">
            Gauranga Sharma
          </Text>
          <Text className="mt-1 font-sans text-base text-stoneMuted">
            Chicago community
          </Text>
          <View
            className={`mt-4 flex-row items-center rounded-pill px-4 py-2 ${selectedRole.badgeClass}`}
          >
            <Ionicons
              name={selectedRole.icon}
              size={17}
              color={
                role === "president"
                  ? tokens.colors.stone
                  : role === "tech"
                    ? tokens.colors.indigo
                    : role === "core"
                      ? tokens.colors.peacock
                      : tokens.colors.stone
              }
            />
            <Text
              className={`ml-2 font-sans-bold text-sm ${selectedRole.badgeTextClass}`}
            >
              {selectedRole.title}
            </Text>
          </View>
          <View className="mt-4 flex-row items-center rounded-pill bg-peacockSoft px-4 py-2">
            <View className="mr-2 h-2.5 w-2.5 rounded-pill bg-peacock" />
            <Text className="font-sans-bold text-sm text-peacock">
              At the temple
            </Text>
          </View>
        </View>
      </View>

      <GarlandDivider />

      <SectionHeader title="Preview access level" />
      <Text className="mb-4 font-sans text-base leading-6 text-stoneMuted">
        Compare how this profile adapts for each role before the final
        permission rules are approved.
      </Text>
      <RoleSelector selectedRole={role} onSelect={setRole} />

      <View className="my-section rounded-card bg-indigo p-card">
        <View className="flex-row items-center">
          <View className="h-11 w-11 items-center justify-center rounded-pill bg-white">
            <Ionicons
              name={selectedRole.icon}
              size={23}
              color={tokens.colors.indigo}
            />
          </View>
          <View className="ml-4 flex-1">
            <Text className="font-display text-xl text-white">
              {selectedRole.title}
            </Text>
            <Text className="mt-1 font-sans-bold text-sm text-marigoldSoft">
              Proposed UI access
            </Text>
          </View>
        </View>
        <Text className="mt-4 font-sans text-base leading-6 text-white">
          {selectedRole.description}
        </Text>
      </View>

      <SectionHeader title="What this role can do" />
      <View className="mb-section overflow-hidden rounded-card border border-border bg-white">
        {selectedRole.access.map((item, index) => (
          <View
            key={item.title}
            className={`flex-row px-card py-4 ${
              index < selectedRole.access.length - 1
                ? "border-b border-border"
                : ""
            }`}
          >
            <View className="h-11 w-11 items-center justify-center rounded-pill bg-indigoSoft">
              <Ionicons
                name={item.icon}
                size={21}
                color={tokens.colors.indigo}
              />
            </View>
            <View className="ml-4 flex-1">
              <Text className="font-sans-bold text-base text-stone">
                {item.title}
              </Text>
              <Text className="mt-1 font-sans text-sm leading-5 text-stoneMuted">
                {item.detail}
              </Text>
            </View>
          </View>
        ))}
      </View>

      <SectionHeader title="My seva" action="See all" />
      <View className="mb-section rounded-card bg-indigo p-card">
        <Text className="font-sans-bold text-sm uppercase tracking-wider text-marigoldSoft">
          Next assignment
        </Text>
        <Text className="mt-3 font-display text-xl text-white">
          Sunday Feast Kitchen
        </Text>
        <Text className="mt-1 font-sans text-base text-white">
          Today · 3:30 PM
        </Text>
      </View>

      <SectionHeader title="Profile and settings" />
      <View className="mb-4 overflow-hidden rounded-card border border-border bg-white">
        {[
          { icon: "person-outline", label: "Personal information" },
          { icon: "notifications-outline", label: "Notifications" },
          { icon: "shield-checkmark-outline", label: "Privacy and visibility" },
          { icon: "help-circle-outline", label: "Help and support" },
        ].map((item, index, list) => (
          <Pressable
            key={item.label}
            className={`min-h-touch flex-row items-center px-card py-3 ${
              index < list.length - 1 ? "border-b border-border" : ""
            }`}
          >
            <Ionicons
              name={item.icon as keyof typeof Ionicons.glyphMap}
              size={22}
              color={tokens.colors.indigo}
            />
            <Text className="ml-4 flex-1 font-sans text-base text-stone">
              {item.label}
            </Text>
            <Ionicons
              name="chevron-forward"
              size={19}
              color={tokens.colors.stoneMuted}
            />
          </Pressable>
        ))}
      </View>

      <View className="mb-4 rounded-button bg-sandalwood px-4 py-3">
        <Text className="font-sans text-sm leading-5 text-stoneMuted">
          Role switching on this screen is for UI review. Production access
          will be enforced securely by Supabase permissions.
        </Text>
      </View>

      <Button variant="secondary" icon="log-out-outline" onPress={onSignOut}>
        Sign out
      </Button>
    </Screen>
  );
}
