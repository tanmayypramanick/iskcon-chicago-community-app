import { Ionicons } from "@expo/vector-icons";
import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import { useEffect, useState } from "react";
import { Alert, Text, View } from "react-native";

import tokens from "../../design-tokens.json";
import { Button, InitialAvatar, Screen, SectionHeader } from "../components/ui";
import { useCurrentAccessProfile } from "../features/access/hooks";
import { hasAccessPermission } from "../features/access/model";
import {
  ClashWarningSheet,
  FormError,
  ServiceCard,
} from "../features/services/components";
import {
  clashWarningMessage,
  clashWarningTitle,
  nextDateOnWeekday,
  weekdayNameForDate,
} from "../features/services/clashes";
import { getChicagoDateKey } from "../lib/chicagoDate";
import {
  formatDuration,
  formatServiceDate,
  formatServiceTime,
  formatWeekdayList,
  isUpcomingService,
} from "../features/services/format";
import {
  useDeleteRecurringService,
  useJoinWeeklyService,
  useServiceDashboard,
  useSevaClashes,
} from "../features/services/hooks";
import { errorMessage } from "../features/services/format";
import {
  broadcastWeeklyOccurrenceCount,
  hasBroadcastWeeklyOpening,
  hasWeeklyOpening,
  weeklyOccurrences,
  weeklyRoster,
} from "../features/services/selectors";
import type { ServicesStackParamList } from "../navigation/types";
import { usePrototypeSession } from "../store/usePrototypeSession";

type Props = NativeStackScreenProps<ServicesStackParamList, "WeeklySevaDetail">;

function initials(name: string) {
  return name
    .split(/\s+/)
    .slice(0, 2)
    .map((part) => part[0]?.toUpperCase())
    .join("");
}

export function WeeklySevaDetailScreen({ navigation, route }: Props) {
  const activeUserId = usePrototypeSession((state) => state.activeUserId);
  const previewRole = usePrototypeSession((state) => state.previewRole);
  const profile = useCurrentAccessProfile(activeUserId);
  const dashboard = useServiceDashboard(activeUserId);
  const joinWeekly = useJoinWeeklyService();
  const removeWeekly = useDeleteRecurringService();
  const template = dashboard.data?.recurringTemplates.find(
    (item) => item.id === route.params.templateId,
  );
  const role =
    __DEV__ && previewRole
      ? previewRole
      : (profile.data?.role ?? "devotee");
  const canManage = hasAccessPermission(role, "services.manage_recurring");
  // Same rule as the server: the coordinator who created it, a Community Head,
  // a Tech Admin, or the President.
  const canRemoveWeekly =
    canManage ||
    hasAccessPermission(role, "app.view_all") ||
    template?.created_by === activeUserId;

  /**
   * Whether joining this rota would collide with something this devotee is
   * already down for.
   *
   * A rota repeats without end, so there is no one date to ask about; the
   * question is put on the first date it actually falls, which is how a
   * standing commitment is checked everywhere else in the app. Hoisted above
   * the early return below — hooks may not sit behind a `return`.
   */
  const todayKey = getChicagoDateKey();
  const joinDate = template?.days_of_week.length
    ? template.days_of_week
        .map((day) => nextDateOnWeekday(todayKey, day))
        .sort()[0]
    : undefined;
  const joinClashes = useSevaClashes(
    template && activeUserId && joinDate
      ? {
          devoteeId: activeUserId,
          date: joinDate,
          startTime: template.start_time,
          durationMinutes: template.duration_minutes,
        }
      : null,
  );
  const [joinPrompt, setJoinPrompt] = useState(false);
  // A warning about a seva that has just moved or been handed on is simply
  // untrue, so it goes the moment the clash does.
  useEffect(() => {
    if (joinPrompt && !joinClashes.length) setJoinPrompt(false);
  }, [joinClashes.length, joinPrompt]);
  const joinWording = {
    audience: "self" as const,
    startTime: template?.start_time ?? "00:00:00",
    durationMinutes: template?.duration_minutes ?? 0,
    weekday: joinDate ? weekdayNameForDate(joinDate) : undefined,
  };

  if (!template || !dashboard.data) {
    return (
      <Screen topInset={false}>
        <Text className="font-sans text-base text-stoneMuted">
          {dashboard.isLoading
            ? "Loading weekly seva…"
            : "This weekly seva is not available to your access level."}
        </Text>
      </Screen>
    );
  }

  const occurrences = weeklyOccurrences(dashboard.data, template.id)
    .filter(
      (service) =>
        isUpcomingService(service.date) &&
        !["completed", "cancelled"].includes(service.status),
    )
    .sort((left, right) => left.date.localeCompare(right.date));
  const myNextOccurrence = occurrences.find(
    (service) => service.currentUserAssignment,
  );
  // Who is actually down to serve today, once accepted swaps are applied. The
  // standing roster still names whoever handed the seva over, which is what
  // made a covered weekly seva keep showing the original devotee.
  const roster = weeklyRoster(dashboard.data, template);
  const isStandingAssignee = roster.some(
    (assignee) => assignee.id === activeUserId,
  );
  const canJoinStanding =
    !isStandingAssignee && hasWeeklyOpening(template, roster);
  const broadcastOpen = hasBroadcastWeeklyOpening(dashboard.data, template.id);
  // Both of these used to be printed on the card. They are the kind of standing
  // detail the temple asked to move behind it, and this is where they landed.
  const datesNeedingCover = broadcastWeeklyOccurrenceCount(
    dashboard.data,
    template.id,
  );
  const coveredDays = template.days_of_week.filter((day) =>
    roster.some((assignee) => assignee.assignedDays.includes(day)),
  ).length;
  const openOccurrenceIds = new Set(
    dashboard.data.coverageRequests.flatMap(({ exceptions, service }) =>
      service.template_id === template.id
        ? exceptions
            .filter(
              (exception) =>
                exception.status === "pending" &&
                exception.resolution_kind === "broadcast",
            )
            .map((exception) => exception.service_instance_id)
        : [],
    ),
  );
  const openOccurrences = occurrences.filter((service) =>
    openOccurrenceIds.has(service.id),
  );
  const error = dashboard.error ?? joinWeekly.error;

  return (
    <Screen topInset={false}>
      <View className="rounded-card bg-indigo p-card">
        <View className="h-11 w-11 items-center justify-center rounded-pill bg-white/15">
          <Ionicons name="repeat" size={22} color={tokens.colors.marigoldSoft} />
        </View>
        <Text className="mt-3 font-sans-bold text-xs uppercase tracking-wider text-marigoldSoft">
          Weekly seva
        </Text>
        <Text className="mt-2 font-display text-[28px] leading-9 text-white">
          {template.name}
        </Text>
        <Text className="mt-3 font-sans-bold text-base leading-6 text-white">
          Every {formatWeekdayList(template.days_of_week)}
        </Text>
        <Text className="mt-1 font-sans text-base text-white">
          {formatServiceTime(template.start_time)} · {formatDuration(template.duration_minutes)}
        </Text>
        {!template.active ? (
          <Text className="mt-3 font-sans-bold text-sm text-marigoldSoft">
            Paused — no new dates are being generated.
          </Text>
        ) : null}
        {datesNeedingCover ? (
          <Text className="mt-3 font-sans-bold text-sm text-marigoldSoft">
            {datesNeedingCover} upcoming date
            {datesNeedingCover === 1 ? "" : "s"} need coverage.
          </Text>
        ) : null}
      </View>

      {canJoinStanding ? (
        <View className="mt-section">
          <Button
            icon="heart-outline"
            disabled={joinWeekly.isPending}
            // Warned about a standing clash first, never stopped by one. Taking
            // on a rota commits every week, so this is the join most worth
            // warning about — and it was the one join with no warning at all.
            onPress={() => {
              if (joinClashes.length) setJoinPrompt(true);
              else joinWeekly.mutate(template.id);
            }}
          >
            {joinWeekly.isPending ? "Joining…" : "Join this weekly seva"}
          </Button>
        </View>
      ) : null}

      <ClashWarningSheet
        visible={joinPrompt}
        title={clashWarningTitle(joinWording)}
        message={clashWarningMessage(joinWording, joinClashes)}
        proceedLabel="Join anyway"
        onProceed={() => {
          setJoinPrompt(false);
          joinWeekly.mutate(template.id);
        }}
        onClose={() => setJoinPrompt(false)}
      />

      {myNextOccurrence ? (
        <View className="mt-3">
          <Button
            variant="secondary"
            icon="calendar-clear-outline"
            onPress={() =>
              navigation.navigate("ReportUnavailable", {
                serviceId: myNextOccurrence.id,
              })
            }
          >
            I can’t do this weekly seva
          </Button>
        </View>
      ) : null}

      {canManage ? (
        <View className="mt-3">
          <Button
            variant="secondary"
            icon="create-outline"
            onPress={() =>
              navigation.navigate("CreateRecurringService", {
                templateId: template.id,
              })
            }
          >
            Edit weekly seva
          </Button>
        </View>
      ) : null}

      <View className="mt-section">
        <SectionHeader
          title="Serving this weekly seva"
          subtitle={`${roster.length} assigned · ${coveredDays} of ${template.days_of_week.length} days covered`}
        />
        <View className="overflow-hidden rounded-card border border-border bg-white">
          {roster.length ? (
            roster.map((assignee, index) => (
              <View
                key={assignee.id}
                className={`min-h-[66px] flex-row items-center px-card py-2 ${
                  index < roster.length - 1
                    ? "border-b border-border"
                    : ""
                }`}
              >
                <InitialAvatar initials={initials(assignee.name)} size="small" />
                <View className="ml-3 min-w-0 flex-1">
                  <Text className="font-sans-bold text-base text-stone">
                    {assignee.name}{assignee.id === activeUserId ? " (You)" : ""}
                  </Text>
                  <Text className="font-sans text-sm text-stoneMuted">
                    {formatWeekdayList(assignee.assignedDays)}
                  </Text>
                </View>
              </View>
            ))
          ) : (
            <Text className="px-card py-6 text-center font-sans text-base text-stoneMuted">
              No standing devotee is assigned yet.
            </Text>
          )}
        </View>
      </View>

      {broadcastOpen ? (
        <View className="mt-section">
          <SectionHeader title="Open weekly dates needing help" />
          <View className="gap-3">
            {openOccurrences.slice(0, 4).map((service) => (
              <ServiceCard
                key={service.id}
                service={service}
                onPress={() =>
                  navigation.navigate("ServiceDetail", { serviceId: service.id })
                }
              />
            ))}
          </View>
        </View>
      ) : null}

      <View className="mt-section">
        <SectionHeader title="Next scheduled dates" />
        <View className="overflow-hidden rounded-card border border-border bg-white">
          {occurrences.slice(0, 4).map((service, index) => (
            <View
              key={service.id}
              className={`flex-row items-center px-card py-3 ${
                index < Math.min(occurrences.length, 4) - 1
                  ? "border-b border-border"
                  : ""
              }`}
            >
              <Ionicons name="calendar-outline" size={18} color={tokens.colors.peacock} />
              <Text className="ml-3 min-w-0 flex-1 font-sans-bold text-sm text-stone">
                {formatServiceDate(service.date)} · {formatServiceTime(service.start_time)}
              </Text>
              {service.currentUserAssignment ? (
                <Text className="font-sans-bold text-xs text-indigo">My seva</Text>
              ) : null}
            </View>
          ))}
        </View>
      </View>

      {canRemoveWeekly && template ? (
        <View className="mt-section">
          <Button
            variant="secondary"
            icon="trash-outline"
            disabled={removeWeekly.isPending}
            onPress={() =>
              Alert.alert(
                "Remove this weekly seva?",
                `"${template.name}" and its future occurrences will be removed. Seva already served stays in the records.`,
                [
                  { text: "Keep", style: "cancel" },
                  {
                    text: "Remove",
                    style: "destructive",
                    onPress: () =>
                      removeWeekly.mutate(template.id, {
                        onSuccess: () => navigation.goBack(),
                      }),
                  },
                ],
              )
            }
          >
            {removeWeekly.isPending ? "Removing…" : "Remove weekly seva"}
          </Button>
        </View>
      ) : null}

      {error || removeWeekly.error ? (
        <FormError
          message={
            errorMessage(
              error ?? removeWeekly.error,
              "The weekly seva could not be updated.",
            ) ?? "The weekly seva could not be updated."
          }
        />
      ) : null}
    </Screen>
  );
}
