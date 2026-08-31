import { Ionicons } from "@expo/vector-icons";
import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import { useMemo, useState } from "react";
import { Modal, Pressable, Text, TextInput, View } from "react-native";

import tokens from "../../design-tokens.json";
import { Avatar, Button, Screen, SectionHeader } from "../components/ui";
import {
  CustomServiceInput,
  DateField,
  FormError,
  ServiceTypePicker,
  TimeField,
} from "../features/services/components";
import { dateToKey, errorMessage } from "../features/services/format";
import {
  useLogCompletedSeva,
  useRequestSevaVerification,
  useServiceDashboard,
  useSevaVerifiers,
} from "../features/services/hooks";
import { validateSevaEntryWindow } from "../features/services/sevaEntry";
import type { SevaVerifier } from "../features/services/types";
import {
  chicagoWallClockToInstant,
  getChicagoZoneAbbreviation,
  toDatabaseTime,
} from "../lib/chicagoDate";
import type { ServicesStackParamList } from "../navigation/types";
import { usePrototypeSession } from "../store/usePrototypeSession";

type Props = NativeStackScreenProps<ServicesStackParamList, "FindSeva">;

function roleLabel(roleName: string) {
  if (roleName === "president") return "President";
  if (roleName === "tech") return "Tech Admin";
  return "Community Head";
}

/**
 * One form, two clearly different intentions:
 * - plan: seva that is beginning now or will happen later;
 * - completed: an honest record of seva that has already happened.
 *
 * Both ask a named community leader to verify the record. Keeping the fields
 * and picker identical means a devotee does not have to learn two workflows.
 */
export function FindSevaScreen({ navigation, route }: Props) {
  const mode = route.params?.mode ?? "plan";
  const completedMode = mode === "completed";
  const activeUserId = usePrototypeSession((state) => state.activeUserId);
  const dashboard = useServiceDashboard(activeUserId);
  const verifiers = useSevaVerifiers();
  const planSeva = useRequestSevaVerification();
  const logSeva = useLogCompletedSeva();

  const initialNow = useMemo(() => new Date(), []);
  const initialStart = useMemo(() => {
    const value = new Date(initialNow);
    if (completedMode) value.setHours(value.getHours() - 1);
    return value;
  }, [completedMode, initialNow]);
  const initialEnd = useMemo(() => {
    const value = new Date(initialNow);
    if (!completedMode) value.setHours(value.getHours() + 1);
    return value;
  }, [completedMode, initialNow]);

  const [serviceTypeId, setServiceTypeId] = useState<string | null>(null);
  const [customSelected, setCustomSelected] = useState(false);
  const [customName, setCustomName] = useState("");
  const [locationText, setLocationText] = useState("ISKCON Chicago Temple");
  const [day, setDay] = useState(initialStart);
  const [startTime, setStartTime] = useState(initialStart);
  const [endTime, setEndTime] = useState(initialEnd);
  const [verifierId, setVerifierId] = useState<string | null>(null);
  const [pickerOpen, setPickerOpen] = useState(false);
  const [search, setSearch] = useState("");
  const [formError, setFormError] = useState<string | null>(null);
  const zone = getChicagoZoneAbbreviation();

  const matchingVerifiers = useMemo(() => {
    const query = search.trim().toLocaleLowerCase();
    return (verifiers.data ?? []).filter(
      (person) => !query || person.name.toLocaleLowerCase().includes(query),
    );
  }, [search, verifiers.data]);

  const selectedVerifier: SevaVerifier | undefined = (verifiers.data ?? []).find(
    (person) => person.id === verifierId,
  );

  const submit = () => {
    setFormError(null);
    if (!serviceTypeId && (!customSelected || customName.trim().length < 2)) {
      setFormError("Choose a seva or briefly describe what you did.");
      return;
    }
    if (!verifierId) {
      setFormError("Choose the community leader who can verify this seva.");
      return;
    }

    // The selected values are Chicago wall-clock times even when a devotee's
    // phone is temporarily set to another time zone.
    const dayKey = dateToKey(day);
    const startAt = chicagoWallClockToInstant(dayKey, toDatabaseTime(startTime));
    let endAt = chicagoWallClockToInstant(dayKey, toDatabaseTime(endTime));
    if (endAt <= startAt) {
      const [year, month, dayOfMonth] = dayKey.split("-").map(Number);
      const nextDayKey = new Date(Date.UTC(year, month - 1, dayOfMonth + 1))
        .toISOString()
        .slice(0, 10);
      endAt = chicagoWallClockToInstant(nextDayKey, toDatabaseTime(endTime));
    }

    const timingError = validateSevaEntryWindow(
      mode,
      startAt,
      endAt,
      new Date(),
    );
    if (timingError) {
      setFormError(timingError);
      return;
    }

    const input = {
      serviceTypeId: customSelected ? null : serviceTypeId,
      customName: customSelected ? customName.trim() : null,
      startAt: startAt.toISOString(),
      endAt: endAt.toISOString(),
      locationText: locationText.trim() || "ISKCON Chicago Temple",
      verifierId,
    };
    const options = { onSuccess: () => navigation.goBack() };
    if (completedMode) logSeva.mutate(input, options);
    else planSeva.mutate(input, options);
  };

  const activeMutation = completedMode ? logSeva : planSeva;
  const error =
    formError ??
    errorMessage(
      activeMutation.error,
      completedMode
        ? "Your completed seva could not be logged."
        : "This seva could not be added.",
    ) ??
    errorMessage(dashboard.error, "Seva choices could not be loaded.");

  return (
    <Screen>
      <Modal
        visible={pickerOpen}
        transparent
        animationType="slide"
        onRequestClose={() => setPickerOpen(false)}
      >
        <Pressable
          className="flex-1 justify-end bg-stone/60"
          accessibilityRole="button"
          accessibilityLabel="Close community leader list"
          onPress={() => setPickerOpen(false)}
        >
          <Pressable className="max-h-[75%] rounded-t-card bg-ivory px-screen pb-10 pt-5">
            <Text className="font-display text-2xl text-stone">
              Who can verify this seva?
            </Text>
            <Text className="mt-1 font-sans text-sm leading-5 text-stoneMuted">
              Choose a Community Head, Tech Admin, or President who knows about
              this seva. Only that person is notified.
            </Text>

            <View className="mt-4 min-h-touch flex-row items-center rounded-button border border-border bg-white px-4">
              <Ionicons name="search" size={19} color={tokens.colors.stoneMuted} />
              <TextInput
                className="ml-3 flex-1 py-3 font-sans text-base text-stone"
                accessibilityLabel="Search community leaders"
                placeholder="Search by name"
                placeholderTextColor={tokens.colors.stoneMuted}
                autoCapitalize="words"
                autoCorrect={false}
                value={search}
                onChangeText={setSearch}
              />
            </View>

            <View className="mt-4 overflow-hidden rounded-card border border-border bg-white">
              {verifiers.isLoading ? (
                <Text className="p-card text-center font-sans text-base text-stoneMuted">
                  Loading community leaders…
                </Text>
              ) : matchingVerifiers.length ? (
                matchingVerifiers.map((person, index) => {
                  const selected = person.id === verifierId;
                  return (
                    <Pressable
                      key={person.id}
                      className={`min-h-touch flex-row items-center px-card py-3 ${
                        index < matchingVerifiers.length - 1
                          ? "border-b border-border"
                          : ""
                      } ${selected ? "bg-indigoSoft" : ""}`}
                      accessibilityRole="radio"
                      accessibilityState={{ selected }}
                      accessibilityLabel={`${person.name}, ${roleLabel(person.role_name)}`}
                      onPress={() => {
                        setVerifierId(person.id);
                        setPickerOpen(false);
                      }}
                    >
                      <Avatar
                        name={person.name}
                        photoUrl={person.photo_url}
                        size="small"
                        tone={selected ? "indigo" : "peacock"}
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
                        name={selected ? "radio-button-on" : "radio-button-off"}
                        size={21}
                        color={selected ? tokens.colors.indigo : tokens.colors.border}
                      />
                    </Pressable>
                  );
                })
              ) : (
                <Text className="p-card text-center font-sans text-sm text-stoneMuted">
                  {search
                    ? "No community leader matches that name."
                    : "No Community Head, Tech Admin, or President is available yet."}
                </Text>
              )}
            </View>
          </Pressable>
        </Pressable>
      </Modal>

      <View
        className={`mb-section rounded-card border p-card ${
          completedMode
            ? "border-peacock/30 bg-peacockSoft"
            : "border-indigo/20 bg-indigoSoft"
        }`}
      >
        <View className="flex-row items-start">
          <View
            className={`h-11 w-11 items-center justify-center rounded-pill ${
              completedMode ? "bg-white" : "bg-indigo"
            }`}
          >
            <Ionicons
              name={completedMode ? "checkmark-done" : "heart"}
              size={23}
              color={
                completedMode ? tokens.colors.peacock : tokens.colors.marigoldSoft
              }
            />
          </View>
          <View className="ml-3 min-w-0 flex-1">
            <Text className="font-display text-xl text-stone">
              {completedMode ? "Record seva already offered" : "Offer your time with intention"}
            </Text>
            <Text className="mt-1 font-sans text-sm leading-5 text-stoneMuted">
              {completedMode
                ? "Add the actual time you served, then ask a community leader who knows about it to verify your seva."
                : "Choose seva you are beginning now or plan it for a future day. A community leader will confirm it."}
            </Text>
          </View>
        </View>
      </View>

      {error ? <FormError message={error} /> : null}

      <SectionHeader title={completedMode ? "What seva did you do?" : "How will you help?"} />
      <View className="mb-section">
        <ServiceTypePicker
          serviceTypes={dashboard.data?.serviceTypes ?? []}
          selectedTypeId={customSelected ? null : serviceTypeId}
          customSelected={customSelected}
          onSelectType={(id) => {
            setCustomSelected(false);
            setServiceTypeId(id);
          }}
          onSelectCustom={() => {
            setCustomSelected(true);
            setServiceTypeId(null);
          }}
        />
        {customSelected ? (
          <CustomServiceInput
            value={customName}
            onChangeText={setCustomName}
            placeholder={
              completedMode
                ? "Briefly describe the seva you completed"
                : "Briefly describe the seva you will do"
            }
          />
        ) : null}
      </View>

      <SectionHeader title={`${completedMode ? "When did you serve" : "When will you serve"} (${zone})`} />
      <View className="mb-3">
        <DateField label="Day" value={day} onChange={setDay} />
      </View>
      <View className="mb-2 flex-row gap-3">
        <TimeField label="Start" value={startTime} onChange={setStartTime} />
        <TimeField label="End" value={endTime} onChange={setEndTime} />
      </View>
      <Text className="mb-section font-sans text-xs leading-4 text-stoneMuted">
        {completedMode
          ? "Use the actual time you served. Completed seva must have ended already and can be logged for up to 180 days."
          : "Use the expected time if you are planning ahead. You can add seva starting now or within the next six months."}
      </Text>

      <SectionHeader title="Where" />
      <View className="mb-section min-h-touch justify-center rounded-button border border-border bg-white px-4">
        <TextInput
          className="font-sans text-base text-stone"
          accessibilityLabel="Where the seva takes place"
          value={locationText}
          onChangeText={setLocationText}
          placeholder="ISKCON Chicago Temple"
          placeholderTextColor={tokens.colors.stoneMuted}
        />
      </View>

      <SectionHeader title="Who can verify it?" />
      <Pressable
        className="mb-2 min-h-touch flex-row items-center rounded-button border border-border bg-white px-4 py-2"
        accessibilityRole="button"
        accessibilityLabel={
          selectedVerifier
            ? `Verifier: ${selectedVerifier.name}. Tap to change.`
            : "Choose a community leader to verify this seva"
        }
        onPress={() => setPickerOpen(true)}
      >
        {selectedVerifier ? (
          <>
            <Avatar
              name={selectedVerifier.name}
              photoUrl={selectedVerifier.photo_url}
              size="small"
              tone="indigo"
            />
            <View className="ml-3 min-w-0 flex-1">
              <Text className="font-sans-bold text-base text-stone" numberOfLines={1}>
                {selectedVerifier.name}
              </Text>
              <Text className="mt-0.5 font-sans text-sm text-stoneMuted">
                {roleLabel(selectedVerifier.role_name)}
              </Text>
            </View>
          </>
        ) : (
          <Text className="flex-1 font-sans text-base text-stoneMuted">
            Choose a community leader
          </Text>
        )}
        <Ionicons name="chevron-down" size={21} color={tokens.colors.indigo} />
      </Pressable>
      <Text className="mb-section font-sans text-xs leading-4 text-stoneMuted">
        They will receive a private notification and can verify or decline the
        entry. Tech Admins and the President can also review it.
      </Text>

      <Button
        icon={completedMode ? "checkmark-circle-outline" : "heart-outline"}
        disabled={activeMutation.isPending}
        onPress={submit}
      >
        {activeMutation.isPending
          ? completedMode
            ? "Sending for verification…"
            : "Adding your seva…"
          : completedMode
            ? "Request verification"
            : "Add to my seva"}
      </Button>
    </Screen>
  );
}
