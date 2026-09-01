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
  useWeeklySevaAnswers,
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

  // The server already decides who may read these — it answers with nothing
  // for anybody else — so the row appears when there is something to read, and
  // for a coordinator always, so they can find it before there is.
  const answers = useWeeklySevaAnswers();
  const missed = (answers.data ?? []).filter(
    (row) => row.answer !== "served",
  ).length;
  const showUpdates = canManage || (answers.data?.length ?? 0) > 0;

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

      {/*
        A rota runs by itself, so this is the one thing about it that ever
        needs reading: the days a devotee said they missed. It sits here rather
        than on the seva board because it belongs to whoever set the rota up,
        and only they can do anything about it.
      */}
      {showUpdates ? (
        <Pressable
          className="mb-section min-h-touch flex-row items-center rounded-card border border-border bg-white px-card py-4"
          accessibilityRole="button"
          accessibilityLabel="Weekly seva updates"
          accessibilityHint="What devotees said about the rota days they held"
          onPress={() => navigation.navigate("WeeklySevaUpdates")}
        >
          <View className="h-11 w-11 items-center justify-center rounded-pill bg-peacockSoft">
            <Ionicons
              name="chatbox-ellipses-outline"
              size={20}
              color={tokens.colors.peacock}
            />
          </View>
          <View className="ml-3 min-w-0 flex-1">
            <Text className="font-sans-bold text-base text-stone">
              Weekly seva updates
            </Text>
            <Text className="font-sans text-sm text-stoneMuted" numberOfLines={1}>
              {missed
                ? missed > 1
                  ? `${missed} days went uncovered`
                  : "One day went uncovered"
                : "What devotees said about their days"}
            </Text>
          </View>
          {missed ? (
            <View className="ml-2 min-w-7 items-center justify-center rounded-pill bg-vermilion px-2 py-0.5">
              <Text className="font-sans-bold text-xs text-white">{missed}</Text>
            </View>
          ) : null}
          <Ionicons
            name="chevron-forward"
            size={20}
            color={tokens.colors.indigo}
          />
        </Pressable>
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
