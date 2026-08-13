import { Ionicons } from "@expo/vector-icons";
import { Text, View } from "react-native";

import tokens from "../../design-tokens.json";
import { Button, InitialAvatar, Screen } from "../components/ui";
import { useCurrentAccessProfile } from "../features/access/hooks";
import { hasAccessPermission } from "../features/access/model";
import { FormError } from "../features/services/components";
import {
  useReviewRecurringServiceInterest,
  useServiceDashboard,
} from "../features/services/hooks";
import { usePrototypeSession } from "../store/usePrototypeSession";

function initials(name: string) {
  return name
    .split(/\s+/)
    .slice(0, 2)
    .map((part) => part[0]?.toUpperCase())
    .join("");
}

export function RecurringInterestInboxScreen() {
  const activeUserId = usePrototypeSession((state) => state.activeUserId);
  const profile = useCurrentAccessProfile(activeUserId);
  const dashboard = useServiceDashboard(activeUserId);
  const review = useReviewRecurringServiceInterest();
  const role = profile.data?.role ?? "devotee";

  if (!hasAccessPermission(role, "services.manage_recurring")) {
    return (
      <Screen topInset={false}>
        <View className="items-center rounded-card border border-border bg-white px-card py-10">
          <Ionicons
            name="lock-closed-outline"
            size={28}
            color={tokens.colors.indigo}
          />
          <Text className="mt-3 text-center font-sans-bold text-base text-stone">
            Community Head, Tech Admin, or President access is required.
          </Text>
        </View>
      </Screen>
    );
  }

  const interests = [...(dashboard.data?.recurringInterests ?? [])].sort(
    (a, b) => {
      if (a.status === b.status)
        return b.submitted_at.localeCompare(a.submitted_at);
      if (a.status === "pending") return -1;
      if (b.status === "pending") return 1;
      return a.status.localeCompare(b.status);
    },
  );

  return (
    <Screen topInset={false}>
      {interests.length ? (
        <View className="gap-3">
          {interests.map((interest) => (
            <View
              key={interest.id}
              className="rounded-card border border-border bg-white p-card"
            >
              <View className="flex-row items-center">
                <InitialAvatar
                  initials={initials(interest.devotee.name)}
                  tone={interest.status === "approved" ? "peacock" : "marigold"}
                  size="small"
                />
                <View className="ml-3 min-w-0 flex-1">
                  <Text className="font-sans-bold text-base text-stone">
                    {interest.devotee.name}
                  </Text>
                  <Text
                    className={`mt-0.5 font-sans-bold text-xs uppercase tracking-wider ${
                      interest.status === "approved"
                        ? "text-peacock"
                        : interest.status === "denied"
                          ? "text-vermilion"
                          : "text-marigold"
                    }`}
                  >
                    {interest.status}
                  </Text>
                </View>
              </View>

              <Text className="mt-4 font-sans-bold text-sm text-stone">
                Skills
              </Text>
              <Text className="mt-1 font-sans text-sm leading-5 text-stoneMuted">
                {interest.skills}
              </Text>
              <Text className="mt-3 font-sans-bold text-sm text-stone">
                Interested in
              </Text>
              <Text className="mt-1 font-sans text-sm leading-5 text-stoneMuted">
                {[
                  ...interest.desiredServiceTypes.map((type) => type.name),
                  interest.other_service,
                ]
                  .filter(Boolean)
                  .join(" · ") || "Current weekly seva"}
              </Text>
              <Text className="mt-3 font-sans-bold text-sm text-stone">
                Availability
              </Text>
              <Text className="mt-1 font-sans text-sm leading-5 text-stoneMuted">
                {interest.availability}
              </Text>
              {interest.currently_serving ? (
                <View className="mt-3 rounded-button bg-peacockSoft px-3 py-2.5">
                  <Text className="font-sans-bold text-xs uppercase tracking-wider text-peacock">
                    Currently serving
                  </Text>
                  <Text className="mt-1 font-sans text-sm text-stone">
                    {interest.current_service_details}
                  </Text>
                </View>
              ) : null}

              {interest.status === "pending" ? (
                <View className="mt-4 flex-row gap-3">
                  <View className="flex-1">
                    <Button
                      variant="secondary"
                      disabled={review.isPending}
                      onPress={() =>
                        review.mutate({
                          interestId: interest.id,
                          approve: false,
                          reviewNote: "Please update the details and resubmit.",
                        })
                      }
                    >
                      Needs update
                    </Button>
                  </View>
                  <View className="flex-1">
                    <Button
                      icon="shield-checkmark-outline"
                      disabled={review.isPending}
                      onPress={() =>
                        review.mutate({
                          interestId: interest.id,
                          approve: true,
                          reviewNote: null,
                        })
                      }
                    >
                      Verify
                    </Button>
                  </View>
                </View>
              ) : null}
            </View>
          ))}
        </View>
      ) : (
        <View className="items-center rounded-card border border-border bg-white px-card py-10">
          <Ionicons
            name="leaf-outline"
            size={30}
            color={tokens.colors.peacock}
          />
          <Text className="mt-3 font-sans-bold text-base text-stone">
            No weekly-seva profiles yet
          </Text>
        </View>
      )}

      {review.error ? (
        <FormError
          message={
            review.error instanceof Error
              ? review.error.message
              : "The weekly-seva profile could not be reviewed."
          }
        />
      ) : null}
    </Screen>
  );
}
