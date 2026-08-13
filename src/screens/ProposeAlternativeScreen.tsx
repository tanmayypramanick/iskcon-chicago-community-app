import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import { useState } from "react";
import { Pressable, Text, TextInput, View } from "react-native";

import tokens from "../../design-tokens.json";
import { Button, Screen, SectionHeader } from "../components/ui";
import { FormError, TimeField } from "../features/services/components";
import {
  errorMessage,
  weekdayNames,
} from "../features/services/format";
import {
  useProposeWeeklyOfferAlternative,
  useServiceDashboard,
} from "../features/services/hooks";
import type { ServicesStackParamList } from "../navigation/types";
import { usePrototypeSession } from "../store/usePrototypeSession";

type Props = NativeStackScreenProps<
  ServicesStackParamList,
  "ProposeAlternative"
>;

const DURATIONS = [30, 60, 90, 120, 180, 240];

/**
 * The third answer to a weekly seva invitation: neither yes nor no, but
 * "I can serve on these days at this time instead".
 */
export function ProposeAlternativeScreen({ navigation, route }: Props) {
  const { offerId } = route.params;
  const activeUserId = usePrototypeSession((state) => state.activeUserId);
  const dashboard = useServiceDashboard(activeUserId);
  const propose = useProposeWeeklyOfferAlternative();

  const invitation = dashboard.data?.pendingRecurringOffers.find(
    ({ offer }) => offer.id === offerId,
  );

  const [days, setDays] = useState<number[]>([]);
  const [startTime, setStartTime] = useState(() => {
    const value = new Date();
    value.setHours(18, 0, 0, 0);
    return value;
  });
  const [durationMinutes, setDurationMinutes] = useState(60);
  const [note, setNote] = useState("");
  const [formError, setFormError] = useState<string | null>(null);

  const toggleDay = (day: number) =>
    setDays((current) =>
      current.includes(day)
        ? current.filter((value) => value !== day)
        : [...current, day].sort(),
    );

  const submit = () => {
    setFormError(null);
    if (!days.length) {
      setFormError("Choose at least one day you can serve.");
      return;
    }
    propose.mutate(
      {
        offerId,
        daysOfWeek: days,
        startTime: `${String(startTime.getHours()).padStart(2, "0")}:${String(
          startTime.getMinutes(),
        ).padStart(2, "0")}:00`,
        durationMinutes,
        note: note.trim() || null,
      },
      { onSuccess: () => navigation.goBack() },
    );
  };

  const error =
    formError ?? errorMessage(propose.error, "Something went wrong.");

  return (
    <Screen>
      <View className="mb-section rounded-card border border-border bg-white p-card">
        <Text className="font-display text-xl text-stone">
          Suggest another time
        </Text>
        <Text className="mt-1.5 font-sans text-sm leading-5 text-stoneMuted">
          {invitation
            ? `You were invited to "${invitation.template.name}". Tell the coordinator which days and time would work for you instead.`
            : "Tell the coordinator which days and time would work for you instead."}
        </Text>
      </View>

      {error ? <FormError message={error} /> : null}

      <SectionHeader title="Days I can serve" />
      <View className="mb-section flex-row flex-wrap gap-2">
        {weekdayNames.map((name, day) => {
          const selected = days.includes(day);
          return (
            <Pressable
              key={name}
              className={`min-h-touch flex-1 basis-[30%] items-center justify-center rounded-button border px-2 ${
                selected ? "border-indigo bg-indigo" : "border-border bg-white"
              }`}
              accessibilityRole="checkbox"
              accessibilityState={{ checked: selected }}
              accessibilityLabel={name}
              onPress={() => toggleDay(day)}
            >
              <Text
                className={`font-sans-bold text-sm ${
                  selected ? "text-white" : "text-stone"
                }`}
              >
                {name.slice(0, 3)}
              </Text>
            </Pressable>
          );
        })}
      </View>

      <SectionHeader title="Time I can start" />
      <View className="mb-section flex-row gap-3">
        <TimeField label="Start" value={startTime} onChange={setStartTime} />
      </View>

      <SectionHeader title="How long" />
      <View className="mb-section flex-row flex-wrap gap-2">
        {DURATIONS.map((minutes) => {
          const selected = minutes === durationMinutes;
          return (
            <Pressable
              key={minutes}
              className={`min-h-touch flex-1 basis-[30%] items-center justify-center rounded-button border px-2 ${
                selected ? "border-peacock bg-peacock" : "border-border bg-white"
              }`}
              accessibilityRole="radio"
              accessibilityState={{ selected }}
              accessibilityLabel={`${minutes} minutes`}
              onPress={() => setDurationMinutes(minutes)}
            >
              <Text
                className={`font-sans-bold text-sm ${
                  selected ? "text-white" : "text-stone"
                }`}
              >
                {minutes < 60 ? `${minutes} min` : `${minutes / 60} hr`}
              </Text>
            </Pressable>
          );
        })}
      </View>

      <SectionHeader title="Anything to add" />
      <View className="mb-section min-h-touch justify-center rounded-button border border-border bg-white px-4">
        <TextInput
          className="py-3 font-sans text-base text-stone"
          accessibilityLabel="Note for the coordinator"
          placeholder="Optional note for the coordinator"
          placeholderTextColor={tokens.colors.stoneMuted}
          value={note}
          onChangeText={setNote}
          multiline
        />
      </View>

      <Button
        icon="calendar-outline"
        disabled={propose.isPending}
        onPress={submit}
      >
        {propose.isPending ? "Sending…" : "Send my suggestion"}
      </Button>
    </Screen>
  );
}
