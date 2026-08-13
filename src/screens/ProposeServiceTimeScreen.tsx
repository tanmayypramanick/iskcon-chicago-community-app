import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import { useEffect, useState } from "react";
import { Text, TextInput, View } from "react-native";

import { Button, Screen, ScreenTitle, SectionHeader } from "../components/ui";
import {
  DateField,
  FormError,
  TimeField,
} from "../features/services/components";
import {
  dateToKey,
  errorMessage,
  formatDuration,
  formatServiceDate,
  formatServiceTime,
  storedSuggestionDuration,
  timeToDatabaseValue,
} from "../features/services/format";
import {
  useProposeServiceOfferAlternative,
  useServiceDashboard,
} from "../features/services/hooks";
import { getChicagoZoneAbbreviation } from "../lib/chicagoDate";
import type { ServicesStackParamList } from "../navigation/types";
import { usePrototypeSession } from "../store/usePrototypeSession";

type Props = NativeStackScreenProps<
  ServicesStackParamList,
  "ProposeServiceTime"
>;

/**
 * The third answer to a dated seva request. A devotee who wants to help but
 * cannot make the hour asked for says when they can, and whoever posted it
 * decides — the same back-and-forth weekly seva already had.
 */
export function ProposeServiceTimeScreen({ navigation, route }: Props) {
  const { offerId } = route.params;
  const activeUserId = usePrototypeSession((state) => state.activeUserId);
  const dashboard = useServiceDashboard(activeUserId);
  const propose = useProposeServiceOfferAlternative();

  const pending = dashboard.data?.pendingOffers.find(
    (entry) => entry.offer.id === offerId,
  );
  const service = pending?.service;

  const [day, setDay] = useState(() => new Date());
  const [startTime, setStartTime] = useState(() => new Date());
  const [endTime, setEndTime] = useState(
    () => new Date(Date.now() + 60 * 60 * 1000),
  );
  const [note, setNote] = useState("");
  const [formError, setFormError] = useState<string | null>(null);

  // Start from the seva as asked, so the devotee edits rather than re-enters.
  useEffect(() => {
    if (!service) return;
    const [year, month, date] = service.date.split("-").map(Number);
    const [hour, minute] = service.start_time.split(":").map(Number);
    const start = new Date(year, month - 1, date, hour, minute);
    setDay(start);
    setStartTime(start);
    setEndTime(new Date(start.getTime() + service.duration_minutes * 60_000));
  }, [service]);

  useEffect(() => {
    if (propose.isSuccess) navigation.goBack();
  }, [navigation, propose.isSuccess]);

  const zone = getChicagoZoneAbbreviation();

  const pickedMinutes = Math.round(
    (endTime.getTime() - startTime.getTime()) / 60_000,
  );
  // What the temple will actually hold. Sent rather than the raw span so the
  // devotee is committed to the hours this screen says, not to a longer one the
  // RPC rounded them up to behind their back.
  const savedMinutes = storedSuggestionDuration(pickedMinutes);
  const savedEnd = new Date(startTime.getTime() + savedMinutes * 60_000);

  const submit = () => {
    setFormError(null);
    if (pickedMinutes < 15) {
      setFormError("The end time must be at least 15 minutes after the start.");
      return;
    }
    if (savedMinutes > 720) {
      setFormError("A seva may be up to 12 hours long.");
      return;
    }
    propose.mutate({
      offerId,
      date: dateToKey(day),
      startTime: timeToDatabaseValue(startTime),
      durationMinutes: savedMinutes,
      note: note.trim() || null,
    });
  };

  if (!service) {
    return (
      <Screen topInset={false}>
        <View className="items-center rounded-card border border-border bg-white px-card py-9">
          <Text className="text-center font-sans-bold text-base text-stone">
            {dashboard.isLoading
              ? "Loading this invitation…"
              : "This invitation is no longer waiting for you"}
          </Text>
        </View>
      </Screen>
    );
  }

  return (
    <Screen topInset={false}>
      <ScreenTitle eyebrow="Offer another time">{service.name}</ScreenTitle>

      <View className="mb-section rounded-card border border-border bg-white p-card">
        <Text className="font-sans text-sm text-stoneMuted">
          {pending?.offeredByName ?? "A coordinator"} asked for
        </Text>
        <Text className="mt-1 font-sans-bold text-base text-stone">
          {formatServiceDate(service.date)} ·{" "}
          {formatServiceTime(service.start_time)}
        </Text>
        <Text className="mt-2 font-sans text-sm leading-5 text-stoneMuted">
          Say when you could do it instead. They will be asked to accept, and
          the seva moves to your time if they do.
        </Text>
      </View>

      <SectionHeader title={`When you can help (${zone})`} />
      <View className="mb-3">
        <DateField label="Day" value={day} onChange={setDay} />
      </View>
      <View className="flex-row gap-3">
        <TimeField label="Start" value={startTime} onChange={setStartTime} />
        <TimeField label="End" value={endTime} onChange={setEndTime} />
      </View>
      {/* Seva is kept in half hours. Saying so beats silently lengthening the
          offer after the devotee has sent it. */}
      {pickedMinutes >= 15 && savedMinutes !== pickedMinutes ? (
        <Text className="mb-section mt-2 font-sans text-sm leading-5 text-stoneMuted">
          Seva is recorded in half hours, so this will be sent as{" "}
          {formatServiceTime(timeToDatabaseValue(startTime))} to{" "}
          {formatServiceTime(timeToDatabaseValue(savedEnd))} (
          {formatDuration(savedMinutes)}).
        </Text>
      ) : (
        <View className="mb-section" />
      )}

      <SectionHeader title="Anything to add" />
      <TextInput
        className="min-h-[88px] rounded-button border border-border bg-white px-4 py-3 font-sans text-base text-stone"
        value={note}
        onChangeText={setNote}
        placeholder="Optional — why this time suits you better"
        placeholderTextColor="#8A8178"
        multiline
        textAlignVertical="top"
      />

      {formError || propose.error ? (
        <View className="mt-3">
          <FormError
            message={
              formError ??
              errorMessage(propose.error, "This could not be sent.") ??
              "This could not be sent."
            }
          />
        </View>
      ) : null}

      <View className="mt-section">
        <Button disabled={propose.isPending} onPress={submit}>
          {propose.isPending ? "Sending…" : "Send this time"}
        </Button>
      </View>
    </Screen>
  );
}
