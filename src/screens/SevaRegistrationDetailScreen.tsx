import { Ionicons } from "@expo/vector-icons";
import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import { useEffect } from "react";
import { Alert, Text, View } from "react-native";

import tokens from "../../design-tokens.json";
import { Avatar, Button, Screen, ScreenTitle } from "../components/ui";
import { FormError } from "../features/services/components";
import { errorMessage } from "../features/services/format";
import {
  useDeleteSevaRegistration,
  useServiceDashboard,
} from "../features/services/hooks";
import { registrationStatusLabel } from "../features/services/components";
import {
  canRemoveRegistration,
  sevaTiming,
} from "../features/services/registrations";
import type { ServiceVerification } from "../features/services/types";
import { useCurrentAccessProfile } from "../features/access/hooks";
import { hasAccessPermission } from "../features/access/model";
import {
  formatChicagoLongDateTime,
  formatChicagoTime,
} from "../lib/chicagoDate";
import { useNow } from "../lib/useNow";
import type { ServicesStackParamList } from "../navigation/types";
import { usePrototypeSession } from "../store/usePrototypeSession";

type Props = NativeStackScreenProps<
  ServicesStackParamList,
  "SevaRegistrationDetail"
>;

function Row({
  icon,
  label,
  value,
}: {
  icon: keyof typeof Ionicons.glyphMap;
  label: string;
  value: string;
}) {
  return (
    <View className="flex-row items-start py-2.5">
      <Ionicons name={icon} size={19} color={tokens.colors.stoneMuted} />
      <View className="ml-3 min-w-0 flex-1">
        <Text className="font-sans text-xs uppercase tracking-wider text-stoneMuted">
          {label}
        </Text>
        <Text className="mt-0.5 font-sans text-base leading-6 text-stone">
          {value}
        </Text>
      </View>
    </View>
  );
}

/**
 * Everything about one registered seva, and the only place it can be changed.
 * The list cards stay deliberately plain — the badge, who verified it, and the
 * actions that alter it all live here.
 */
export function SevaRegistrationDetailScreen({ navigation, route }: Props) {
  const { verificationId } = route.params;
  const activeUserId = usePrototypeSession((state) => state.activeUserId);
  const profile = useCurrentAccessProfile(activeUserId);
  const dashboard = useServiceDashboard(activeUserId);
  const remove = useDeleteSevaRegistration();
  const now = useNow();

  const role =
    (profile.data?.role ?? "devotee");
  const canManage = hasAccessPermission(role, "services.manage_recurring");

  const registration: ServiceVerification | undefined = [
    ...(dashboard.data?.verifications ?? []),
    ...(dashboard.data?.myVerifications ?? []),
  ].find((row) => row.id === verificationId);

  // Removing it from here means this screen no longer has anything to show.
  useEffect(() => {
    if (remove.isSuccess) navigation.goBack();
  }, [navigation, remove.isSuccess]);

  if (!registration) {
    return (
      <Screen topInset={false}>
        <View className="items-center rounded-card border border-border bg-white px-card py-9">
          <Ionicons
            name="leaf-outline"
            size={28}
            color={tokens.colors.peacock}
          />
          <Text className="mt-3 text-center font-sans-bold text-base text-stone">
            {dashboard.isLoading
              ? "Loading this seva…"
              : "This seva is no longer listed"}
          </Text>
        </View>
      </Screen>
    );
  }

  const start = new Date(registration.start_at);
  const end = new Date(registration.end_at);
  const timing = sevaTiming(registration, now);
  const verified = registration.status === "verified";
  const declined = registration.status === "declined";
  const isMine = registration.devotee_id === activeUserId;
  const badge = registrationStatusLabel(registration, timing);

  const confirmRemove = () =>
    Alert.alert(
      "Remove this seva?",
      `"${registration.name}" will be removed for good.`,
      [
        { text: "Keep", style: "cancel" },
        {
          text: "Remove",
          style: "destructive",
          onPress: () => remove.mutate(registration.id),
        },
      ],
    );

  return (
    <Screen topInset={false}>
      <ScreenTitle eyebrow="Registered seva">{registration.name}</ScreenTitle>

      <View className="rounded-card border border-border bg-white p-card">
        <View className="flex-row items-center">
          <View
            className={`rounded-pill px-3 py-1 ${
              verified
                ? "bg-peacockSoft"
                : declined
                  ? "bg-sandalwood"
                  : "bg-marigoldSoft"
            }`}
          >
            <Text
              className={`font-sans-bold text-xs uppercase tracking-wider ${
                verified
                  ? "text-peacock"
                  : declined
                    ? "text-vermilion"
                    : "text-stone"
              }`}
            >
              {badge}
            </Text>
          </View>
          {isMine ? (
            <View className="ml-2 rounded-pill bg-indigoSoft px-3 py-1">
              <Text className="font-sans-bold text-xs uppercase tracking-wider text-indigo">
                My seva
              </Text>
            </View>
          ) : null}
        </View>

        {verified ? (
          <View className="mt-3 flex-row items-center">
            <Ionicons
              name="checkmark-circle"
              size={18}
              color={tokens.colors.peacock}
            />
            <Text className="ml-2 font-sans-bold text-base text-peacock">
              Verified by {registration.verifiedBy?.name ?? "a member"}
            </Text>
          </View>
        ) : declined ? (
          <Text className="mt-3 font-sans text-base leading-6 text-vermilion">
            {registration.verifier?.name ?? "A member"} cannot verify this seva.
            {registration.review_note
              ? ` “${registration.review_note}”`
              : " Ask someone else to verify it."}
          </Text>
        ) : (
          <Text className="mt-3 font-sans text-base leading-6 text-stoneMuted">
            Waiting for {registration.verifier?.name ?? "a member"} to verify
            this seva.
          </Text>
        )}

        <View className="mt-2 border-t border-border pt-1">
          <Row
            icon="calendar-outline"
            label="When"
            value={`${formatChicagoLongDateTime(start)} – ${formatChicagoTime(end)}`}
          />
          <Row
            icon="location-outline"
            label="Where"
            value={registration.location_text}
          />
        </View>

        {registration.devotee ? (
          <View className="mt-2 flex-row items-center border-t border-border pt-4">
            <Avatar
              name={registration.devotee.name}
              photoUrl={registration.devotee.photo_url}
              size="small"
              tone={verified ? "peacock" : "marigold"}
            />
            <View className="ml-3 min-w-0 flex-1">
              <Text className="font-sans-bold text-base text-stone">
                {registration.devotee.name}
              </Text>
              <Text className="font-sans text-sm text-stoneMuted">
                Offered this seva
              </Text>
            </View>
          </View>
        ) : null}
      </View>

      {remove.error ? (
        <View className="mt-3">
          <FormError
            message={
              errorMessage(remove.error, "This seva could not be removed.") ??
              "This seva could not be removed."
            }
          />
        </View>
      ) : null}

      {isMine && !verified ? (
        <View className="mt-section">
          <Button
            onPress={() =>
              navigation.navigate("AskAnotherVerifier", {
                verificationId: registration.id,
              })
            }
          >
            Ask someone else to verify
          </Button>
        </View>
      ) : null}

      {canRemoveRegistration(registration, activeUserId, canManage) ? (
        <View className="mt-3">
          <Button
            variant="secondary"
            disabled={remove.isPending}
            onPress={confirmRemove}
          >
            {remove.isPending ? "Removing…" : "Remove this seva"}
          </Button>
        </View>
      ) : null}
    </Screen>
  );
}
