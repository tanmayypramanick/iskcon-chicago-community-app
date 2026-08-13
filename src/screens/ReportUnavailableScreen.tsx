import { Ionicons } from "@expo/vector-icons";
import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import { useEffect, useState } from "react";
import { Pressable, Text, TextInput, View } from "react-native";

import tokens from "../../design-tokens.json";
import { Button, Screen, SectionHeader } from "../components/ui";
import { DateField, FormError } from "../features/services/components";
import {
  dateToKey,
  errorMessage,
  formatServiceDate,
  formatServiceTime,
  formatWeekdayList,
  weekdayNames,
} from "../features/services/format";
import {
  useReportWeeklyServiceUnavailable,
  useServiceDashboard,
} from "../features/services/hooks";
import type { CoverageScope } from "../features/services/types";
import type { ServicesStackParamList } from "../navigation/types";
import { usePrototypeSession } from "../store/usePrototypeSession";

type Props = NativeStackScreenProps<ServicesStackParamList, "ReportUnavailable">;

function dateFromKey(key: string) {
  const [year, month, day] = key.split("-").map(Number);
  return new Date(year, month - 1, day, 12);
}

export function ReportUnavailableScreen({ navigation, route }: Props) {
  const activeUserId = usePrototypeSession((state) => state.activeUserId);
  const dashboard = useServiceDashboard(activeUserId);
  const reportUnavailable = useReportWeeklyServiceUnavailable();
  const service = dashboard.data?.services.find(
    (item) => item.id === route.params.serviceId,
  );
  const template = service?.template_id
    ? dashboard.data?.recurringTemplates.find(
        (item) => item.id === service.template_id,
      )
    : null;
  const [scope, setScope] = useState<CoverageScope>("occurrence");
  const [fromDate, setFromDate] = useState(() => new Date());
  const [toDate, setToDate] = useState(() => {
    const date = new Date();
    date.setDate(date.getDate() + 28);
    return date;
  });
  const [daysOfWeek, setDaysOfWeek] = useState<number[]>([]);
  const [reason, setReason] = useState("");
  const [formError, setFormError] = useState<string | null>(null);
  const [initialized, setInitialized] = useState(false);

  // Prefill exactly once. Keying this off `daysOfWeek.length` meant clearing
  // the last weekday counted as "not filled in yet", so unticking it silently
  // reticked every day and threw away the dates the devotee had chosen.
  useEffect(() => {
    if (!service || !template || initialized) return;
    const occurrenceDate = dateFromKey(service.date);
    setFromDate(occurrenceDate);
    const end = new Date(occurrenceDate);
    end.setDate(end.getDate() + 28);
    setToDate(end);
    setDaysOfWeek(template.days_of_week);
    setInitialized(true);
  }, [initialized, service, template]);

  if (!service || !template) {
    return (
      <Screen topInset={false}>
        <Text className="font-sans text-base text-stoneMuted">
          {dashboard.isLoading
            ? "Loading weekly seva…"
            : "This weekly seva is no longer available."}
        </Text>
      </Screen>
    );
  }

  const submit = () => {
    setFormError(null);
    const selectedDays =
      scope === "occurrence" ? [fromDate.getDay()] : daysOfWeek;
    if (!selectedDays.length) {
      setFormError("Choose at least one weekly-seva day.");
      return;
    }
    if (scope === "date_range") {
      const rangeDays = Math.ceil(
        (toDate.getTime() - fromDate.getTime()) / 86_400_000,
      );
      if (rangeDays < 0 || rangeDays > 180) {
        setFormError("Choose an end date within 180 days of the start.");
        return;
      }
    }
    reportUnavailable.mutate(
      {
        templateId: template.id,
        scope,
        dateFrom: dateToKey(fromDate),
        dateTo: scope === "occurrence"
          ? dateToKey(fromDate)
          : scope === "date_range"
            ? dateToKey(toDate)
            : null,
        daysOfWeek: selectedDays,
        reason: reason.trim(),
      },
      { onSuccess: () => navigation.popToTop() },
    );
  };
  const error =
    formError ??
    errorMessage(reportUnavailable.error, "Something went wrong.");

  return (
    <Screen topInset={false}>
      <View className="rounded-card bg-indigo p-card">
        <Ionicons name="repeat" size={24} color={tokens.colors.marigoldSoft} />
        <Text className="mt-3 font-display text-2xl text-white">
          {service.name}
        </Text>
        <Text className="mt-2 font-sans-bold text-base text-white">
          Every {formatWeekdayList(template.days_of_week)}
        </Text>
        <Text className="mt-1 font-sans text-base text-white">
          {formatServiceTime(service.start_time)}
        </Text>
      </View>

      <Text className="mt-section font-display text-2xl text-stone">
        When are you unavailable?
      </Text>
      <Text className="mt-2 font-sans text-base leading-6 text-stoneMuted">
        Choose one occurrence, selected weekly days in a date range, or selected days from a date onward. Coordinators will receive one clear coverage request.
      </Text>

      <View className="mt-5 gap-2">
        {([
          ["occurrence", "Just one day", "Only the selected date"],
          ["date_range", "A date range", "Selected weekly days between two dates"],
          ["forever", "From a date onward", "Permanently release the selected weekly days"],
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
      </View>

      <View className="mt-section gap-3">
        <SectionHeader title={scope === "occurrence" ? "Unavailable date" : "Unavailable period"} />
        <DateField
          label="Starts"
          value={fromDate}
          onChange={setFromDate}
          minimumDate={new Date()}
        />
        {scope === "date_range" ? (
          <DateField label="Ends" value={toDate} onChange={setToDate} minimumDate={fromDate} />
        ) : null}
      </View>

      {scope !== "occurrence" ? (
        <View className="mt-section">
          <SectionHeader title="Which weekly days?" />
          <View className="flex-row flex-wrap gap-2">
            {template.days_of_week.map((day) => {
              const selected = daysOfWeek.includes(day);
              return (
                <Pressable
                  key={day}
                  className={`min-h-11 min-w-[29%] flex-1 items-center justify-center rounded-pill border px-3 ${
                    selected ? "border-indigo bg-indigo" : "border-border bg-white"
                  }`}
                  onPress={() =>
                    setDaysOfWeek((current) =>
                      selected
                        ? current.filter((value) => value !== day)
                        : [...current, day].sort(),
                    )
                  }
                >
                  <Text className={`font-sans-bold text-sm ${selected ? "text-white" : "text-stone"}`}>
                    {weekdayNames[day]}
                  </Text>
                </Pressable>
              );
            })}
          </View>
        </View>
      ) : (
        <Text className="mt-3 font-sans-bold text-sm text-indigo">
          {formatServiceDate(dateToKey(fromDate))}
        </Text>
      )}

      <TextInput
        className="mt-section min-h-[110px] rounded-card border border-border bg-white px-4 py-4 font-sans text-base text-stone"
        accessibilityLabel="Optional reason for being unavailable"
        placeholder="Reason (optional)"
        placeholderTextColor={tokens.colors.stoneMuted}
        multiline
        maxLength={300}
        textAlignVertical="top"
        value={reason}
        onChangeText={setReason}
      />

      {error ? <FormError message={error} /> : null}
      <View className="mt-section">
        <Button
          icon="alert-circle-outline"
          disabled={reportUnavailable.isPending}
          onPress={submit}
        >
          {reportUnavailable.isPending
            ? "Notifying coordinators…"
            : "Request weekly-seva coverage"}
        </Button>
      </View>
    </Screen>
  );
}
