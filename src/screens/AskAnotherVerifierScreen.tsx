import { Ionicons } from "@expo/vector-icons";
import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import { useMemo, useState } from "react";
import { Pressable, Text, TextInput, View } from "react-native";

import tokens from "../../design-tokens.json";
import { Avatar, Button, Screen, SectionHeader } from "../components/ui";
import { FormError } from "../features/services/components";
import { errorMessage } from "../features/services/format";
import {
  useResendSevaVerification,
  useServiceDashboard,
  useSevaVerifiers,
} from "../features/services/hooks";
import {
  formatChicagoShortDate,
  formatChicagoTime,
} from "../lib/chicagoDate";
import type { ServicesStackParamList } from "../navigation/types";
import { usePrototypeSession } from "../store/usePrototypeSession";

type Props = NativeStackScreenProps<
  ServicesStackParamList,
  "AskAnotherVerifier"
>;

function roleLabel(roleName: string) {
  if (roleName === "president") return "President";
  if (roleName === "tech") return "Tech Admin";
  return "Community Head";
}

/**
 * When the member a devotee named cannot verify their seva, the registration
 * stays put and is simply sent to somebody else. Nothing is re-entered.
 */
export function AskAnotherVerifierScreen({ navigation, route }: Props) {
  const { verificationId } = route.params;
  const activeUserId = usePrototypeSession((state) => state.activeUserId);
  const dashboard = useServiceDashboard(activeUserId);
  const verifiers = useSevaVerifiers();
  const resend = useResendSevaVerification();
  const [search, setSearch] = useState("");

  const registration = dashboard.data?.myVerifications?.find(
    (row) => row.id === verificationId,
  );

  const candidates = useMemo(() => {
    const query = search.trim().toLocaleLowerCase();
    return (verifiers.data ?? []).filter(
      (person) =>
        // The member who already declined is not offered again.
        person.id !== registration?.verifier_id &&
        (!query || person.name.toLocaleLowerCase().includes(query)),
    );
  }, [registration?.verifier_id, search, verifiers.data]);

  const error = errorMessage(resend.error, "This seva could not be sent again.");

  if (!registration) {
    return (
      <Screen>
        <View className="items-center rounded-card border border-border bg-white px-card py-8">
          <Text className="text-center font-sans-bold text-base text-stone">
            This seva registration is no longer available.
          </Text>
        </View>
      </Screen>
    );
  }

  return (
    <Screen>
      <View className="mb-section rounded-card border border-vermilion bg-white p-card">
        <Text className="font-display text-xl text-stone">
          {registration.name}
        </Text>
        <Text className="mt-1 font-sans text-sm text-stoneMuted">
          {formatChicagoShortDate(new Date(registration.start_at))} ·{" "}
          {formatChicagoTime(new Date(registration.start_at))} –{" "}
          {formatChicagoTime(new Date(registration.end_at))}
        </Text>
        <Text className="mt-2 font-sans text-sm leading-5 text-vermilion">
          {registration.verifier?.name ?? "The member you asked"} could not
          verify this seva.
          {registration.review_note ? ` “${registration.review_note}”` : ""}
        </Text>
        <Text className="mt-2 font-sans text-sm leading-5 text-stoneMuted">
          Choose someone else who saw you serve. Your registration stays exactly
          as it is.
        </Text>
      </View>

      {error ? <FormError message={error} /> : null}

      <SectionHeader title="Ask another member" />
      <View className="mb-3 min-h-touch flex-row items-center rounded-button border border-border bg-white px-4">
        <Ionicons name="search" size={19} color={tokens.colors.stoneMuted} />
        <TextInput
          className="ml-3 flex-1 py-3 font-sans text-base text-stone"
          accessibilityLabel="Search members"
          placeholder="Search by name"
          placeholderTextColor={tokens.colors.stoneMuted}
          autoCapitalize="words"
          autoCorrect={false}
          value={search}
          onChangeText={setSearch}
        />
      </View>

      {candidates.length ? (
        <View className="overflow-hidden rounded-card border border-border bg-white">
          {candidates.map((person, index) => (
            <Pressable
              key={person.id}
              className={`min-h-touch flex-row items-center px-card py-3 ${
                index < candidates.length - 1 ? "border-b border-border" : ""
              }`}
              accessibilityRole="button"
              accessibilityLabel={`Ask ${person.name} to verify this seva`}
              disabled={resend.isPending}
              onPress={() =>
                resend.mutate(
                  { verificationId, verifierId: person.id },
                  { onSuccess: () => navigation.goBack() },
                )
              }
            >
              <Avatar
                name={person.name}
                photoUrl={person.photo_url}
                size="small"
                tone="peacock"
              />
              <View className="ml-3 min-w-0 flex-1">
                <Text
                  className="font-sans-bold text-base text-stone"
                  numberOfLines={1}
                >
                  {person.name}
                </Text>
                <Text className="mt-0.5 font-sans text-sm text-stoneMuted">
                  {roleLabel(person.role_name)}
                </Text>
              </View>
              <Ionicons
                name="chevron-forward"
                size={20}
                color={tokens.colors.indigo}
              />
            </Pressable>
          ))}
        </View>
      ) : (
        <View className="items-center rounded-card border border-border bg-white px-card py-7">
          <Text className="text-center font-sans text-sm leading-5 text-stoneMuted">
            {search
              ? "No other member matches that name."
              : "There is no other Community Head, Tech Admin, or President to ask yet."}
          </Text>
        </View>
      )}

      <View className="mt-section">
        <Button variant="secondary" onPress={() => navigation.goBack()}>
          Not now
        </Button>
      </View>
    </Screen>
  );
}
