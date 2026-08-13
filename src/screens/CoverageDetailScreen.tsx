import { Ionicons } from "@expo/vector-icons";
import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import { useEffect, useMemo, useState } from "react";
import { Pressable, Text, TextInput, View } from "react-native";

import tokens from "../../design-tokens.json";
import { Button, InitialAvatar, Screen } from "../components/ui";
import {
  ClashWarningSheet,
  DateField,
  FormError,
  type JoinAudience,
  WhoCanJoinPicker,
} from "../features/services/components";
import {
  clashWarningMessage,
  clashWarningTitle,
  weekdayNameForDate,
} from "../features/services/clashes";
import {
  dateToKey,
  errorMessage,
  formatServiceDate,
  formatServiceTime,
  formatWeekdayList,
} from "../features/services/format";
import {
  useClashGate,
  useOfferServiceCoverageRange,
  useReopenServiceException,
  useServiceDashboard,
} from "../features/services/hooks";
import type { CoverageScope } from "../features/services/types";
import type { ServicesStackParamList } from "../navigation/types";
import { usePrototypeSession } from "../store/usePrototypeSession";

type Props = NativeStackScreenProps<ServicesStackParamList, "CoverageDetail">;

function initials(name: string) {
  return name
    .split(/\s+/)
    .slice(0, 2)
    .map((part) => part[0]?.toUpperCase())
    .join("");
}

function dateFromKey(key: string) {
  const [year, month, day] = key.split("-").map(Number);
  return new Date(year, month - 1, day, 12);
}

export function CoverageDetailScreen({ navigation, route }: Props) {
  const activeUserId = usePrototypeSession((state) => state.activeUserId);
  const dashboard = useServiceDashboard(activeUserId);
  const reopen = useReopenServiceException();
  const offerCoverage = useOfferServiceCoverageRange();
  // Two mutually exclusive ways to resolve this: broadcast the uncovered dates,
  // or ask one devotee at a time. Only the chosen one is on screen, so the
  // question reads the same here as it does when posting a seva request.
  const [audience, setAudience] = useState<JoinAudience>("open");
  const [scope, setScope] = useState<CoverageScope>("occurrence");
  /**
   * The range start, and nothing else.
   *
   * The occurrence chips used to write into this too, so tapping a date and
   * then switching to "All unavailable days" silently sent a range beginning at
   * whichever chip was last pressed — a fortnight of cover quietly truncated to
   * its last few days. One date each: the chips choose an occurrence, this
   * chooses where a range starts, and neither moves the other.
   */
  const [fromDate, setFromDate] = useState(() => new Date());
  const [toDate, setToDate] = useState(() => new Date());
  const [occurrenceKey, setOccurrenceKey] = useState<string | null>(null);
  const [initialized, setInitialized] = useState(false);
  const [search, setSearch] = useState("");
  const [showAll, setShowAll] = useState(false);
  const [sentToName, setSentToName] = useState<string | null>(null);
  const request = dashboard.data?.coverageRequests.find(({ exceptions }) =>
    exceptions.some((exception) => exception.id === route.params.exceptionId),
  );

  useEffect(() => {
    if (!request || initialized) return;
    // `offer_service_coverage_range` refuses a start date that has already
    // passed, and an unavailability reported a fortnight ago still carries its
    // original from-date. Opening on that date offered the coordinator a form
    // that could only fail, so the ask begins today at the earliest.
    const notBeforeToday = (key: string) => {
      const chosen = dateFromKey(key);
      const today = dateFromKey(dateToKey(new Date()));
      return chosen < today ? today : chosen;
    };
    const from = notBeforeToday(request.exception.unavailable_from);
    setFromDate(from);
    const to = notBeforeToday(
      request.exception.unavailable_to ?? request.exception.unavailable_from,
    );
    setToDate(to < from ? from : to);
    setInitialized(true);
  }, [initialized, request]);

  const occurrenceDates = useMemo(() => {
    if (!request || !dashboard.data) return [];
    return request.exceptions
      .filter((exception) => exception.status === "pending")
      .flatMap((exception) => {
        const service = dashboard.data?.services.find(
          (item) => item.id === exception.service_instance_id,
        );
        return service ? [{ exceptionId: exception.id, date: service.date }] : [];
      })
      .sort((left, right) => left.date.localeCompare(right.date));
  }, [dashboard.data, request]);

  // Hoisted above the two early returns below so the clash gate can be set up
  // unconditionally — hooks may not sit behind a `return`.
  const selectedOccurrence =
    occurrenceDates.find(({ date }) => date === occurrenceKey) ??
    occurrenceDates[0];
  const coverageService = request?.service;
  const rangeStart = dateToKey(fromDate);
  // For a range or a standing handover the substitute takes the same weekday
  // week after week, so the question is put on the first date they would cover
  // — the first uncovered occurrence the range actually reaches, not whichever
  // chip happens to be selected above.
  const askDate =
    scope === "occurrence"
      ? selectedOccurrence?.date
      : (occurrenceDates.find(({ date }) => date >= rangeStart)?.date ??
        rangeStart);

  const sendCoverageOffer = (devoteeId: string, name: string) => {
    if (!selectedOccurrence) return;
    offerCoverage.mutate(
      {
        exceptionId: selectedOccurrence.exceptionId,
        devoteeId,
        scope,
        dateFrom:
          scope === "occurrence" ? selectedOccurrence.date : rangeStart,
        dateTo:
          scope === "occurrence"
            ? selectedOccurrence.date
            : scope === "date_range"
              ? dateToKey(toDate)
              : null,
      },
      { onSuccess: () => setSentToName(name) },
    );
  };
  const askGate = useClashGate((target) =>
    sendCoverageOffer(
      target.devoteeId,
      `${target.name}${target.devoteeId === activeUserId ? " (You)" : ""}`,
    ),
  );
  const askWording = {
    audience: "other" as const,
    devoteeName: askGate.warning?.target.name,
    startTime: coverageService?.start_time ?? "00:00:00",
    durationMinutes: coverageService?.duration_minutes ?? 0,
    // A one-day cover is one date; anything longer repeats, and is said so.
    weekday:
      scope !== "occurrence" && askDate ? weekdayNameForDate(askDate) : undefined,
  };

  if (!request) {
    return (
      <Screen topInset={false}>
        <Text className="font-sans text-base text-stoneMuted">
          {dashboard.isLoading
            ? "Loading coverage request…"
            : "This weekly-seva coverage request is already resolved."}
        </Text>
      </Screen>
    );
  }

  if (!occurrenceDates.length && !dashboard.isLoading) {
    return (
      <Screen topInset={false}>
        <View className="items-center rounded-card border border-border bg-white px-card py-9">
          <Ionicons
            name="checkmark-done"
            size={30}
            color={tokens.colors.peacock}
          />
          <Text className="mt-3 text-center font-sans-bold text-base text-stone">
            This coverage request is resolved
          </Text>
          <Text className="mt-1 text-center font-sans text-sm text-stoneMuted">
            No uncovered weekly-seva dates remain in this request.
          </Text>
        </View>
      </Screen>
    );
  }

  const { exception, service, unavailableDevotee } = request;
  const matchingDevotees = (dashboard.data?.devotees ?? [])
    .filter(
      (devotee) =>
        devotee.id !== unavailableDevotee.id &&
        `${devotee.name} ${devotee.role_name}`
          .toLocaleLowerCase()
          .includes(search.trim().toLocaleLowerCase()),
    )
    .sort((left, right) => {
      if (left.id === activeUserId) return -1;
      if (right.id === activeUserId) return 1;
      return left.name.localeCompare(right.name);
    });
  const visibleDevotees = showAll || search.trim()
    ? matchingDevotees
    : matchingDevotees.slice(0, 6);
  const error = reopen.error ?? offerCoverage.error;

  return (
    <Screen topInset={false}>
      <View className="rounded-card bg-indigo p-card">
        <Text className="font-sans-bold text-xs uppercase tracking-wider text-marigoldSoft">
          Weekly seva coverage
        </Text>
        <Text className="mt-2 font-display text-[26px] leading-8 text-white">
          {service.name}
        </Text>
        <Text className="mt-2 font-sans-bold text-base text-marigoldSoft">
          {formatWeekdayList(exception.unavailable_days)} · {formatServiceTime(service.start_time)}
        </Text>
        <Text className="mt-3 font-sans text-base leading-6 text-white">
          {unavailableDevotee.name} is unavailable
          {exception.unavailable_scope === "occurrence"
            ? ` on ${formatServiceDate(exception.unavailable_from)}`
            : exception.unavailable_scope === "forever"
              ? ` from ${formatServiceDate(exception.unavailable_from)} onward`
              : ` from ${formatServiceDate(exception.unavailable_from)} through ${formatServiceDate(exception.unavailable_to ?? exception.unavailable_from)}`}
          {exception.reason ? `: ${exception.reason}` : "."}
        </Text>
      </View>

      <View className="mt-section">
        <WhoCanJoinPicker
          value={audience}
          detail={{
            open: "Publish every uncovered date",
            invite_only: "One devotee accepts first",
          }}
          onChange={setAudience}
        />
      </View>

      {audience === "open" ? (
      <View className="mt-section">
        <Text className="mb-3 font-sans text-base leading-6 text-stoneMuted">
          Publish all still-uncovered dates as open weekly-seva requirements so any devotee can join an occurrence.
        </Text>
        <Button
          icon="megaphone-outline"
          disabled={reopen.isPending}
          onPress={() =>
            reopen.mutate(exception.id, {
              onSuccess: () => navigation.goBack(),
            })
          }
        >
          {reopen.isPending ? "Opening…" : "Open uncovered dates to everyone"}
        </Button>
      </View>
      ) : (
      <View className="mt-section">
        <Text className="mb-3 font-sans text-base leading-6 text-stoneMuted">
          The selected devotee receives an actionable notification with the exact requested period and must accept before assignment.
        </Text>
        <View className="mb-4 gap-2">
          {([
            ["occurrence", "Just one uncovered day", "Choose one date below"],
            ["date_range", "All unavailable days", "Cover the selected unavailable period"],
            ["forever", "From now onward", "Take these selected weekdays permanently"],
          ] as const).map(([value, title, detail]) => (
            <Pressable
              key={value}
              className={`min-h-touch rounded-button border px-4 py-3 ${
                scope === value ? "border-indigo bg-indigo" : "border-border bg-white"
              }`}
              onPress={() => setScope(value)}
            >
              <Text className={`font-sans-bold text-base ${scope === value ? "text-white" : "text-stone"}`}>
                {title}
              </Text>
              <Text className={`font-sans text-xs ${scope === value ? "text-white" : "text-stoneMuted"}`}>
                {detail}
              </Text>
            </Pressable>
          ))}
          {scope === "occurrence" ? (
            <View className="flex-row flex-wrap gap-2">
              {occurrenceDates.map(({ date }) => {
                const selected = selectedOccurrence?.date === date;
                return (
                  <Pressable
                    key={date}
                    className={`min-h-11 items-center justify-center rounded-pill border px-4 ${selected ? "border-indigo bg-indigo" : "border-border bg-white"}`}
                    onPress={() => setOccurrenceKey(date)}
                  >
                    <Text className={`font-sans-bold text-sm ${selected ? "text-white" : "text-stone"}`}>
                      {formatServiceDate(date)}
                    </Text>
                  </Pressable>
                );
              })}
            </View>
          ) : (
            <DateField label="Coverage starts" value={fromDate} onChange={setFromDate} minimumDate={new Date()} />
          )}
          {scope === "date_range" ? (
            <DateField label="Coverage ends" value={toDate} onChange={setToDate} minimumDate={fromDate} />
          ) : null}
        </View>

        {sentToName ? (
          <View className="mb-3 flex-row items-center rounded-button bg-peacockSoft px-4 py-3">
            <Ionicons name="checkmark-circle" size={20} color={tokens.colors.peacock} />
            <Text className="ml-2 flex-1 font-sans-bold text-sm text-peacock">
              Request sent to {sentToName}
            </Text>
          </View>
        ) : null}

        <View className="mb-2 flex-row items-center rounded-button border border-border bg-white px-4">
          <Ionicons name="search" size={19} color={tokens.colors.indigo} />
          <TextInput
            className="min-h-touch min-w-0 flex-1 px-3 font-sans text-base text-stone"
            value={search}
            onChangeText={setSearch}
            placeholder="Search devotee by name"
            placeholderTextColor={tokens.colors.stoneMuted}
          />
        </View>
        <View className="overflow-hidden rounded-card border border-border bg-white">
          {visibleDevotees.map((devotee, index) => (
            <Pressable
              key={devotee.id}
              className={`min-h-[68px] flex-row items-center px-card py-2 ${index < visibleDevotees.length - 1 ? "border-b border-border" : ""}`}
              accessibilityRole="button"
              accessibilityLabel={`Ask ${devotee.name} to cover this weekly seva`}
              disabled={
                offerCoverage.isPending || !selectedOccurrence || askGate.checking
              }
              // Warned if they are already serving then, and asked regardless
              // the moment the coordinator says so.
              onPress={() =>
                askDate &&
                askGate.ask({
                  name: devotee.name,
                  devoteeId: devotee.id,
                  date: askDate,
                  startTime: service.start_time,
                  durationMinutes: service.duration_minutes,
                })
              }
            >
              <InitialAvatar initials={initials(devotee.name)} size="small" />
              <View className="ml-3 min-w-0 flex-1">
                <Text className="font-sans-bold text-base text-stone">
                  {devotee.name}{devotee.id === activeUserId ? " (You)" : ""}
                </Text>
                <Text className="font-sans text-sm capitalize text-stoneMuted">
                  {devotee.role_name.replace("_", " ")}
                </Text>
              </View>
              <Ionicons name="paper-plane-outline" size={20} color={tokens.colors.indigo} />
            </Pressable>
          ))}
        </View>
        {!search.trim() && matchingDevotees.length > 6 ? (
          <Pressable className="mt-2 min-h-touch items-center justify-center rounded-button bg-indigoSoft" onPress={() => setShowAll((value) => !value)}>
            <Text className="font-sans-bold text-sm text-indigo">
              {showAll ? "Show fewer" : `See all ${matchingDevotees.length} devotees`}
            </Text>
          </Pressable>
        ) : null}
      </View>
      )}

      {error ? (
        <FormError
          message={
            errorMessage(error, "The coverage request could not be updated.") ??
            "The coverage request could not be updated."
          }
        />
      ) : null}

      <ClashWarningSheet
        visible={Boolean(askGate.warning)}
        title={clashWarningTitle(askWording)}
        message={clashWarningMessage(askWording, askGate.warning?.clashes ?? [])}
        proceedLabel="Ask anyway"
        onProceed={askGate.accept}
        onClose={askGate.dismiss}
      />
    </Screen>
  );
}
