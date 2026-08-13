import { Ionicons } from "@expo/vector-icons";
import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import { Pressable, Text, View } from "react-native";

import tokens from "../../design-tokens.json";
import { Button, Screen, ScreenTitle } from "../components/ui";
import { useCurrentAccessProfile } from "../features/access/hooks";
import { hasAccessPermission } from "../features/access/model";
import { WeeklySevaCard } from "../features/services/components";
import {
  useServiceDashboard,
  useSetRecurringServiceActive,
} from "../features/services/hooks";
import { weeklyRoster } from "../features/services/selectors";
import type { ServicesStackParamList } from "../navigation/types";
import { usePrototypeSession } from "../store/usePrototypeSession";

type Props = NativeStackScreenProps<
  ServicesStackParamList,
  "RecurringServices"
>;

export function RecurringServicesScreen({ navigation }: Props) {
  const activeUserId = usePrototypeSession((state) => state.activeUserId);
  const previewRole = usePrototypeSession((state) => state.previewRole);
  const profile = useCurrentAccessProfile(activeUserId);
  const dashboard = useServiceDashboard(activeUserId);
  const setActive = useSetRecurringServiceActive();
  // Same rule as every other Seva screen, so the role preview is honest here.
  const canManage = hasAccessPermission(
    __DEV__ && previewRole ? previewRole : (profile.data?.role ?? "devotee"),
    "services.manage_recurring",
  );
  const templates = dashboard.data?.recurringTemplates ?? [];

  return (
    <Screen topInset={false}>
      <ScreenTitle eyebrow="Standing weekly seva">
        Weekly seva
      </ScreenTitle>

      {canManage ? (
        <View className="mb-section">
          <Button
            icon="repeat-outline"
            onPress={() => navigation.navigate("CreateRecurringService")}
          >
            Create weekly service
          </Button>
        </View>
      ) : null}

      {dashboard.isLoading ? (
        <View className="rounded-card border border-border bg-white p-card">
          <Text className="font-sans text-base text-stoneMuted">
            Loading weekly seva…
          </Text>
        </View>
      ) : templates.length ? (
        <View className="gap-section">
          {templates.map((template) => {
            // Accepted swaps in force today, so a handed-over weekly seva
            // names and counts whoever is actually serving it.
            const serving = dashboard.data
              ? weeklyRoster(dashboard.data, template)
              : template.assignees;
            return (
              <View key={template.id} className="gap-2">
                {/* The same card as every other seva list. The management
                    controls sit under it rather than inside it, so the card
                    itself stays the one size the temple asked for. */}
                <WeeklySevaCard
                  template={template}
                  roster={serving}
                  showPeople
                  onPress={() =>
                    navigation.navigate("WeeklySevaDetail", {
                      templateId: template.id,
                    })
                  }
                />
                {canManage ? (
                  <View className="flex-row gap-2">
                    <Pressable className="min-h-touch flex-1 flex-row items-center justify-center rounded-button border border-border" accessibilityRole="button" onPress={() => navigation.navigate("CreateRecurringService", { templateId: template.id })}>
                      <Ionicons name="create-outline" size={19} color={tokens.colors.indigo} />
                      <Text className="ml-2 font-sans-bold text-base text-indigo">Edit</Text>
                    </Pressable>
                    <Pressable className="min-h-touch flex-1 flex-row items-center justify-center rounded-button border border-border" accessibilityRole="button" disabled={setActive.isPending} onPress={() => setActive.mutate({ templateId: template.id, active: !template.active })}>
                      <Ionicons name={template.active ? "pause-outline" : "play-outline"} size={19} color={tokens.colors.indigo} />
                      <Text className="ml-2 font-sans-bold text-base text-indigo">{template.active ? "Pause" : "Resume"}</Text>
                    </Pressable>
                  </View>
                ) : null}
              </View>
            );
          })}
        </View>
      ) : (
        <View className="items-center rounded-card border border-border bg-white px-card py-9">
          <Ionicons
            name="repeat-outline"
            size={31}
            color={tokens.colors.peacock}
          />
          <Text className="mt-3 text-center font-sans-bold text-base text-stone">
            No weekly services yet
          </Text>
          <Text className="mt-1 text-center font-sans text-sm text-stoneMuted">
            Authorized coordinators can create the first standing seva.
          </Text>
        </View>
      )}
    </Screen>
  );
}
