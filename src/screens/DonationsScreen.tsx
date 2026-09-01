import { Ionicons } from "@expo/vector-icons";
import { useNavigation } from "@react-navigation/native";
import type { NativeStackNavigationProp } from "@react-navigation/native-stack";
import { useState } from "react";
import { Pressable, Text, View } from "react-native";

import tokens from "../../design-tokens.json";
import {
  GarlandDivider,
  Screen,
  ScreenTitle,
  SectionHeader,
} from "../components/ui";
import { useCurrentAccessProfile } from "../features/access/hooks";
import { hasAccessPermission } from "../features/access/model";
import { openZeffyPage } from "../features/donations/api";
import { GENERAL_DONATION_URL } from "../features/donations/types";
import { FormError } from "../features/services/components";
import { errorMessage } from "../features/services/format";
import type { HomeStackParamList } from "../navigation/types";
import { usePrototypeSession } from "../store/usePrototypeSession";

/**
 * One of the two ways to give, as a card big enough to be the whole point of
 * the screen. Everything else here is a row.
 */
function GivingCard({
  icon,
  iconClass,
  iconColor,
  title,
  detail,
  actionLabel,
  busy,
  onPress,
}: {
  icon: keyof typeof Ionicons.glyphMap;
  iconClass: string;
  iconColor: string;
  title: string;
  detail: string;
  actionLabel: string;
  busy?: boolean;
  onPress: () => void;
}) {
  return (
    <Pressable
      className="mb-3 rounded-card border border-border bg-white p-card"
      accessibilityRole="button"
      accessibilityLabel={`${title}. ${detail}`}
      accessibilityState={{ disabled: Boolean(busy) }}
      disabled={busy}
      onPress={onPress}
    >
      <View className="flex-row items-start">
        <View
          className={`h-11 w-11 items-center justify-center rounded-pill ${iconClass}`}
        >
          <Ionicons name={icon} size={22} color={iconColor} />
        </View>
        <View className="ml-3 min-w-0 flex-1">
          <Text className="font-display text-xl leading-7 text-stone">
            {title}
          </Text>
          <Text className="mt-1.5 font-sans text-sm leading-6 text-stoneMuted">
            {detail}
          </Text>
        </View>
      </View>
      <View className="mt-4 flex-row items-center">
        <Text className="font-sans-bold text-base text-indigo">
          {busy ? "Opening…" : actionLabel}
        </Text>
        <Ionicons
          name="chevron-forward"
          size={17}
          color={tokens.colors.indigo}
        />
      </View>
    </Pressable>
  );
}

function LinkRow({
  icon,
  title,
  detail,
  isFirst,
  isLast,
  onPress,
}: {
  icon: keyof typeof Ionicons.glyphMap;
  title: string;
  detail: string;
  isFirst: boolean;
  isLast: boolean;
  onPress: () => void;
}) {
  return (
    <Pressable
      className={`min-h-touch flex-row items-center border-x border-border bg-white px-card py-3.5 ${
        isFirst ? "rounded-t-card border-t" : ""
      } ${isLast ? "rounded-b-card border-b" : "border-b"}`}
      accessibilityRole="button"
      accessibilityLabel={`${title}. ${detail}`}
      onPress={onPress}
    >
      <View className="h-9 w-9 items-center justify-center rounded-pill bg-indigoSoft">
        <Ionicons name={icon} size={18} color={tokens.colors.indigo} />
      </View>
      <View className="ml-3 min-w-0 flex-1">
        <Text className="font-sans-bold text-base text-stone">{title}</Text>
        <Text className="mt-0.5 font-sans text-xs leading-4 text-stoneMuted">
          {detail}
        </Text>
      </View>
      <Ionicons
        name="chevron-forward"
        size={18}
        color={tokens.colors.stoneMuted}
      />
    </Pressable>
  );
}

/**
 * Where giving starts. Two paths, because they are genuinely different acts: a
 * donation is an amount, and a sponsorship is a named seva on a named day that
 * nobody else can then take.
 */
export function DonationsScreen() {
  const navigation =
    useNavigation<NativeStackNavigationProp<HomeStackParamList>>();
  const activeUserId = usePrototypeSession((state) => state.activeUserId);
  const profile = useCurrentAccessProfile(activeUserId);
  const role =
    (profile.data?.role ?? "devotee");
  const mayViewAll = hasAccessPermission(role, "app.view_all");

  const [opening, setOpening] = useState(false);
  const [openError, setOpenError] = useState<string | null>(null);

  const openGeneralForm = () => {
    setOpenError(null);
    setOpening(true);
    // The address is prefilled so the payment can be matched back to this
    // devotee; Zeffy tells us nothing else about who paid.
    openZeffyPage(GENERAL_DONATION_URL, profile.data?.email)
      .catch((error: unknown) =>
        setOpenError(
          errorMessage(error, "The donation page could not be opened."),
        ),
      )
      .finally(() => setOpening(false));
  };

  return (
    <Screen topInset={false}>
      <ScreenTitle eyebrow="Giving">Support the temple</ScreenTitle>

      <Text className="mb-section font-sans text-sm leading-6 text-stoneMuted">
        Payment is taken by Zeffy, which charges the temple nothing — every
        dollar and cent you give arrives here. The page opens in your browser so
        Apple Pay and Google Pay work as they should.
      </Text>

      <GivingCard
        icon="gift-outline"
        iconClass="bg-marigoldSoft"
        iconColor={tokens.colors.stone}
        title="Give a donation"
        detail="Any amount, once or repeating — monthly, quarterly or yearly."
        actionLabel="Open the donation form"
        busy={opening}
        onPress={openGeneralForm}
      />

      <GivingCard
        icon="calendar-outline"
        iconClass="bg-peacockSoft"
        iconColor={tokens.colors.peacock}
        title="Sponsor a seva"
        detail="Mangal aarti, a garland, the Sunday Feast, the deity dress — offered on a day that becomes yours."
        actionLabel="Choose a sponsorship"
        onPress={() => navigation.navigate("SponsorshipCalendar")}
      />

      {openError ? <FormError message={openError} /> : null}

      <View className="mt-section">
        <SectionHeader title="Your giving" />
        <View className="overflow-hidden rounded-card">
          <LinkRow
            icon="receipt-outline"
            title="My donations and sponsorships"
            detail="Everything you have offered, and where each gift stands"
            isFirst
            isLast={!mayViewAll}
            onPress={() => navigation.navigate("MyDonations")}
          />
          {mayViewAll ? (
            <LinkRow
              icon="stats-chart-outline"
              title="All giving"
              detail="Every donation, totals, and payments still to be settled"
              isFirst={false}
              isLast
              onPress={() => navigation.navigate("AllDonations")}
            />
          ) : null}
        </View>
      </View>

      <GarlandDivider />
      <View className="items-center px-4 pb-2">
        <Ionicons name="leaf-outline" size={24} color={tokens.colors.peacock} />
        <Text className="mt-2 text-center font-display-italic text-lg leading-7 text-stoneMuted">
          What is offered with love is never small.
        </Text>
      </View>
    </Screen>
  );
}
