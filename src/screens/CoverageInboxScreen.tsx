import { Ionicons } from "@expo/vector-icons";
import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import { useEffect, useState } from "react";
import { Pressable, Text, View } from "react-native";

import tokens from "../../design-tokens.json";
import { Screen, ScreenTitle, SectionHeader } from "../components/ui";
import { useCurrentAccessProfile } from "../features/access/hooks";
import { hasAccessPermission } from "../features/access/model";
import {
  ClashWarningSheet,
  FormError,
} from "../features/services/components";
import {
  clashWarningMessage,
  clashWarningTitle,
} from "../features/services/clashes";
import {
  errorMessage,
  formatDuration,
  formatServiceDate,
  formatServiceTime,
  formatWeekdayList,
} from "../features/services/format";
import {
  useRespondToServiceOfferCounter,
  useServiceDashboard,
  useSevaClashLookup,
} from "../features/services/hooks";
import { sevaNeedingMyAnswer } from "../features/services/selectors";
import type { ServicesStackParamList } from "../navigation/types";
import { usePrototypeSession } from "../store/usePrototypeSession";

type Props = NativeStackScreenProps<ServicesStackParamList, "CoverageInbox">;

export function CoverageInboxScreen({ navigation }: Props) {
  const activeUserId = usePrototypeSession((state) => state.activeUserId);
  const previewRole = usePrototypeSession((state) => state.previewRole);
  const profile = useCurrentAccessProfile(activeUserId);
  const dashboard = useServiceDashboard(activeUserId);
  // Same rule as every other Seva screen. Without it the role preview showed a
  // Devotee this inbox and a Community Head none of it, which is the opposite
  // of what it is for.
  const role =
    __DEV__ && previewRole ? previewRole : (profile.data?.role ?? "devotee");
  const canResolve = hasAccessPermission(role, "services.resolve_coverage");
  const pending = (dashboard.data?.coverageRequests ?? []).filter(
    ({ exception }) => exception.status === "pending",
  );
  // A decline that left a place to fill, or a suggested time needing a yes or
  // no. A Volunteer posts seva too, so this part of the inbox is not gated on
  // coordinator access — and a Tech Admin or the President may answer for a
  // seva somebody else posted, which is what `app.view_all` adds here.
  const attention = dashboard.data
    ? sevaNeedingMyAnswer(
        dashboard.data,
        activeUserId,
        hasAccessPermission(role, "app.view_all"),
      )
    : [];
  const respond = useRespondToServiceOfferCounter();

  /**
   * "Move it" is an accept: it writes the suggested time onto the seva and puts
   * the devotee who suggested it on the roster. It is the one accept path in
   * the app that never asked whether they are free then — and a suggestion made
   * a fortnight ago is exactly the one they may since have committed over.
   *
   * Asked for every waiting suggestion up front, as the Seva tab does, so the
   * answer is on hand the moment the coordinator taps.
   */
  const counters = attention.flatMap((item) =>
    item.kind === "countered" && item.counter ? [item] : [],
  );
  const counterClashes = useSevaClashLookup(
    counters.map((item) => ({
      key: item.counter!.id,
      devoteeId: item.offer.offered_to,
      date: item.counter!.proposed_date ?? item.service.date,
      startTime: item.counter!.proposed_start_time,
      durationMinutes:
        item.counter!.proposed_duration_minutes ?? item.service.duration_minutes,
      // Without this the seva being moved is reported as clashing with itself.
      excludeInstanceId: item.service.id,
    })),
  );
  const [movePrompt, setMovePrompt] = useState<string | null>(null);
  const promptItem = counters.find((item) => item.counter!.id === movePrompt);
  const promptClashes = movePrompt ? (counterClashes.get(movePrompt) ?? []) : [];
  // A warning outlives its clash by nothing.
  useEffect(() => {
    if (movePrompt && !promptClashes.length) setMovePrompt(null);
  }, [movePrompt, promptClashes.length]);
  const moveWording = {
    audience: "other" as const,
    devoteeName: promptItem?.devoteeName,
    startTime: promptItem?.counter?.proposed_start_time ?? "00:00:00",
    durationMinutes:
      promptItem?.counter?.proposed_duration_minutes ??
      promptItem?.service.duration_minutes ??
      0,
  };
  const moveSeva = (counterId: string) => {
    if ((counterClashes.get(counterId) ?? []).length) {
      setMovePrompt(counterId);
      return;
    }
    respond.mutate({ counterId, accept: true, note: null });
  };

  if (!canResolve && !attention.length) {
    return (
      <Screen topInset={false}>
        <View className="items-center rounded-card border border-border bg-white px-card py-9">
          <Ionicons
            name="lock-closed-outline"
            size={30}
            color={tokens.colors.indigo}
          />
          <Text className="mt-3 text-center font-sans-bold text-base text-stone">
            Coordinator access required
          </Text>
        </View>
      </Screen>
    );
  }

  return (
    <Screen topInset={false}>
      <ScreenTitle eyebrow="Help every seva continue">
        Coverage inbox
      </ScreenTitle>

      {attention.length ? (
        <View className="mb-section">
          <SectionHeader title="Your seva requests need you" />
          <View className="gap-3">
            {attention.map((item) => (
              <View
                key={item.offer.id}
                className="rounded-card border border-marigold bg-white p-card"
              >
                <Text className="font-display text-lg text-stone">
                  {item.service.name}
                </Text>
                <Text className="mt-0.5 font-sans text-sm text-stoneMuted">
                  {formatServiceDate(item.service.date)} ·{" "}
                  {formatServiceTime(item.service.start_time)} ·{" "}
                  {item.service.filledSlots} of {item.service.slots_needed}{" "}
                  serving
                </Text>

                {item.kind === "countered" && item.counter ? (
                  <>
                    <Text className="mt-2 font-sans text-sm leading-5 text-stone">
                      {item.devoteeName} cannot make that time, and offered{" "}
                      <Text className="font-sans-bold">
                        {item.counter.proposed_date
                          ? `${formatServiceDate(item.counter.proposed_date)} · ${formatServiceTime(item.counter.proposed_start_time)}`
                          : formatServiceTime(item.counter.proposed_start_time)}
                      </Text>
                      {/* The length as well as the hour. "Move it" writes
                          `proposed_duration_minutes` onto the seva, and
                          `propose_service_offer_alternative` has already
                          rounded it up onto the temple's 30-minute grid — so a
                          poster shown only "9:00 AM" could agree to an hour
                          for a seva they asked 45 minutes for. The weekly
                          approvals screen has always named it. */}
                      {typeof item.counter.proposed_duration_minutes === "number" ? (
                        <>
                          {" for "}
                          <Text className="font-sans-bold">
                            {formatDuration(item.counter.proposed_duration_minutes)}
                          </Text>
                        </>
                      ) : null}{" "}
                      instead.
                    </Text>
                    {item.counter.note ? (
                      <Text className="mt-1 font-sans text-sm italic leading-5 text-stoneMuted">
                        “{item.counter.note}”
                      </Text>
                    ) : null}
                    <View className="mt-3 flex-row gap-3">
                      <Pressable
                        className="min-h-touch flex-1 items-center justify-center rounded-button bg-indigo"
                        accessibilityRole="button"
                        accessibilityLabel={`Move ${item.service.name} to the suggested time`}
                        disabled={respond.isPending}
                        // Warned if they are already serving then, and moved
                        // regardless the moment the coordinator says so.
                        onPress={() => moveSeva(item.counter!.id)}
                      >
                        <Text className="font-sans-bold text-base text-white">
                          Move it
                        </Text>
                      </Pressable>
                      <Pressable
                        className="min-h-touch flex-1 items-center justify-center rounded-button border border-border"
                        accessibilityRole="button"
                        accessibilityLabel={`Decline the suggested time for ${item.service.name}`}
                        disabled={respond.isPending}
                        onPress={() =>
                          respond.mutate({
                            counterId: item.counter!.id,
                            accept: false,
                            note: null,
                          })
                        }
                      >
                        <Text className="font-sans-bold text-base text-stone">
                          Keep the time
                        </Text>
                      </Pressable>
                    </View>
                  </>
                ) : (
                  <Text className="mt-2 font-sans text-sm leading-5 text-stone">
                    {item.devoteeName} is not available. Ask someone else or
                    open it to everyone.
                  </Text>
                )}

                <Pressable
                  className="mt-3 min-h-touch items-center justify-center rounded-button border border-border"
                  accessibilityRole="button"
                  accessibilityLabel={`Change ${item.service.name}`}
                  onPress={() =>
                    navigation.navigate("EditServiceRequest", {
                      serviceId: item.service.id,
                    })
                  }
                >
                  <Text className="font-sans-bold text-base text-indigo">
                    Change this seva
                  </Text>
                </Pressable>
              </View>
            ))}
          </View>
          {respond.error ? (
            <View className="mt-3">
              <FormError
                message={
                  errorMessage(respond.error, "That could not be answered.") ??
                  "That could not be answered."
                }
              />
            </View>
          ) : null}
        </View>
      ) : null}

      {!canResolve ? null : dashboard.isLoading ? (
        <View className="rounded-card border border-border bg-white p-card">
          <Text className="font-sans text-base text-stoneMuted">
            Loading coverage needs…
          </Text>
        </View>
      ) : pending.length ? (
        <View className="gap-3">
          {pending.map(({ exception, service, unavailableDevotee }) => (
            <Pressable
              key={exception.id}
              className="rounded-card border border-marigold bg-white p-card"
              accessibilityRole="button"
              accessibilityLabel={`Arrange coverage for ${service.name}`}
              onPress={() =>
                navigation.navigate("CoverageDetail", {
                  exceptionId: exception.id,
                })
              }
            >
              <View className="flex-row items-start">
                <View className="h-11 w-11 flex-shrink-0 items-center justify-center rounded-pill bg-marigoldSoft">
                  <Ionicons
                    name="people-outline"
                    size={21}
                    color={tokens.colors.stone}
                  />
                </View>
                <View className="ml-3 min-w-0 flex-1">
                  <Text className="font-display text-xl text-stone">
                    {service.name}
                  </Text>
                  <Text className="mt-1 font-sans-bold text-sm text-indigo">
                    {formatServiceDate(service.date)} ·{" "}
                    {formatServiceTime(service.start_time)}
                  </Text>
                  <Text className="mt-2 font-sans text-sm leading-5 text-stoneMuted">
                    {unavailableDevotee.name} is unavailable
                    {exception.reason ? ` · ${exception.reason}` : "."}
                  </Text>
                  <Text className="mt-1 font-sans-bold text-xs text-peacock">
                    {exception.unavailable_scope === "occurrence"
                      ? "One occurrence"
                      : exception.unavailable_scope === "forever"
                        ? `From ${formatServiceDate(exception.unavailable_from)} onward`
                        : `${formatServiceDate(exception.unavailable_from)}–${formatServiceDate(exception.unavailable_to ?? exception.unavailable_from)}`}
                    {` · ${formatWeekdayList(exception.unavailable_days)}`}
                  </Text>
                </View>
                <Ionicons
                  name="chevron-forward"
                  size={20}
                  color={tokens.colors.indigo}
                />
              </View>
            </Pressable>
          ))}
        </View>
      ) : (
        <View className="items-center rounded-card border border-border bg-white px-card py-9">
          <View className="h-14 w-14 items-center justify-center rounded-pill bg-peacockSoft">
            <Ionicons
              name="checkmark-done"
              size={27}
              color={tokens.colors.peacock}
            />
          </View>
          <Text className="mt-4 text-center font-display text-xl text-stone">
            Every weekly seva is covered
          </Text>
          <Text className="mt-1 text-center font-sans text-sm text-stoneMuted">
            New unavailability reports will appear here in real time.
          </Text>
        </View>
      )}

      <ClashWarningSheet
        visible={Boolean(movePrompt)}
        title={clashWarningTitle(moveWording)}
        message={clashWarningMessage(moveWording, promptClashes)}
        proceedLabel="Move it anyway"
        onProceed={() => {
          const counterId = movePrompt;
          setMovePrompt(null);
          if (counterId) {
            respond.mutate({ counterId, accept: true, note: null });
          }
        }}
        onClose={() => setMovePrompt(null)}
      />
    </Screen>
  );
}
