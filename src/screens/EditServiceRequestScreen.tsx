import { Ionicons } from "@expo/vector-icons";
import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import { useEffect, useMemo, useState } from "react";
import { Alert, Pressable, Text, View } from "react-native";

import tokens from "../../design-tokens.json";
import { Button, Screen, ScreenTitle, SectionHeader } from "../components/ui";
import { useCurrentAccessProfile } from "../features/access/hooks";
import { hasAccessPermission } from "../features/access/model";
import {
  ClashWarningSheet,
  DevoteePicker,
  FormError,
  WhoCanJoinPicker,
} from "../features/services/components";
import {
  coordinatorClashSummary,
  coordinatorClashTitle,
} from "../features/services/clashes";
import {
  errorMessage,
  formatDuration,
  formatServiceDate,
  formatServiceTime,
} from "../features/services/format";
import {
  useDeleteServiceRequirement,
  useServiceDashboard,
  useSevaClashLookup,
  useUpdateServiceRequirement,
} from "../features/services/hooks";
import { servingDevotees } from "../features/services/selectors";
import type { ServicesStackParamList } from "../navigation/types";
import { usePrototypeSession } from "../store/usePrototypeSession";

type Props = NativeStackScreenProps<
  ServicesStackParamList,
  "EditServiceRequest"
>;

/**
 * Reshaping a seva request that did not work out first time: open it to
 * everyone, ask more devotees, change how many are needed, or withdraw it.
 * Whoever posted it, a Tech Admin, or the President.
 */
export function EditServiceRequestScreen({ navigation, route }: Props) {
  const { serviceId } = route.params;
  const activeUserId = usePrototypeSession((state) => state.activeUserId);
  const previewRole = usePrototypeSession((state) => state.previewRole);
  const profile = useCurrentAccessProfile(activeUserId);
  const dashboard = useServiceDashboard(activeUserId);
  const update = useUpdateServiceRequirement();
  const remove = useDeleteServiceRequirement();

  const role =
    __DEV__ && previewRole ? previewRole : (profile.data?.role ?? "devotee");
  const canOverrideAnything = hasAccessPermission(role, "app.view_all");

  const service = dashboard.data?.services.find((row) => row.id === serviceId);
  const mayChange =
    !!service &&
    (canOverrideAnything || service.posted_by === activeUserId);

  const [openToAll, setOpenToAll] = useState(false);
  const [slots, setSlots] = useState(1);
  const [inviteeIds, setInviteeIds] = useState<string[]>([]);
  const [formError, setFormError] = useState<string | null>(null);

  useEffect(() => {
    if (!service) return;
    setOpenToAll(service.participation_mode === "open");
    setSlots(service.slots_needed);
  }, [service]);

  useEffect(() => {
    if (update.isSuccess || remove.isSuccess) navigation.goBack();
  }, [navigation, remove.isSuccess, update.isSuccess]);

  // Only whoever is serving now. A devotee who handed this seva over is free
  // to be invited back to it.
  const alreadyOn = useMemo(
    () =>
      new Set(
        service ? servingDevotees(service).map((devotee) => devotee.id) : [],
      ),
    [service],
  );
  const invitable = (dashboard.data?.devotees ?? []).filter(
    (devotee) => devotee.id !== activeUserId && !alreadyOn.has(devotee.id),
  );
  // `update_service_requirement` never withdraws an invitation, so a devotee
  // already waiting on this seva is shown as such rather than as an empty box
  // whose only effect would be to ask them a second time.
  const alreadyAsked = (service?.pendingInvitees ?? []).map(
    (devotee) => devotee.id,
  );
  const placesLeft = Math.max(0, slots - (service?.filledSlots ?? 0));

  /**
   * Whether anyone about to be asked is already serving over this seva's hours.
   * The seva itself is excluded: somebody already on it is not a clash with the
   * thing they are on.
   */
  const inviteeClashes = useSevaClashLookup(
    service && !openToAll
      ? inviteeIds.map((devoteeId) => ({
          key: devoteeId,
          devoteeId,
          date: service.date,
          startTime: service.start_time,
          durationMinutes: service.duration_minutes,
          excludeInstanceId: service.id,
        }))
      : [],
  );
  const clashing = inviteeIds.map((devoteeId) => ({
    name:
      dashboard.data?.devotees.find((devotee) => devotee.id === devoteeId)
        ?.name ?? "A devotee",
    clashes: inviteeClashes.get(devoteeId) ?? [],
  }));
  const anyClash = clashing.some((entry) => entry.clashes.length > 0);
  const [warning, setWarning] = useState(false);
  useEffect(() => {
    if (warning && !anyClash) setWarning(false);
  }, [anyClash, warning]);

  if (!service || !mayChange) {
    return (
      <Screen topInset={false}>
        <View className="items-center rounded-card border border-border bg-white px-card py-9">
          <Ionicons
            name="lock-closed-outline"
            size={28}
            color={tokens.colors.indigo}
          />
          <Text className="mt-3 text-center font-sans-bold text-base text-stone">
            {dashboard.isLoading
              ? "Loading this seva…"
              : !service
                ? "This seva request is no longer listed"
                : "Only the devotee who posted this can change it"}
          </Text>
        </View>
      </Screen>
    );
  }

  const save = () =>
    update.mutate({
      instanceId: serviceId,
      participationMode: openToAll ? "open" : "invite_only",
      slotsNeeded: slots,
      inviteeIds: openToAll ? [] : inviteeIds,
    });

  const submit = () => {
    setFormError(null);
    if (!openToAll && inviteeIds.length > placesLeft) {
      setFormError(
        `There ${placesLeft === 1 ? "is" : "are"} only ${placesLeft} place${placesLeft === 1 ? "" : "s"} left to fill.`,
      );
      return;
    }
    // Warned before the invitations go out; the save is still one tap away.
    if (anyClash) {
      setWarning(true);
      return;
    }
    save();
  };

  const confirmRemove = () =>
    Alert.alert(
      "Remove this seva request?",
      service.filledSlots > 0
        ? `${service.filledSlots} devotee${service.filledSlots === 1 ? " is" : "s are"} on this. They will be told it is off.`
        : "Nobody is on this yet.",
      [
        { text: "Keep", style: "cancel" },
        {
          text: "Remove",
          style: "destructive",
          onPress: () => remove.mutate(serviceId),
        },
      ],
    );

  return (
    <Screen topInset={false}>
      <ScreenTitle eyebrow="Change this seva">{service.name}</ScreenTitle>

      <View className="mb-section rounded-card border border-border bg-white p-card">
        <Text className="font-sans-bold text-base text-stone">
          {formatServiceDate(service.date)} ·{" "}
          {formatServiceTime(service.start_time)}
        </Text>
        <Text className="mt-1 font-sans text-sm text-stoneMuted">
          {formatDuration(service.duration_minutes)} · {service.filledSlots} of{" "}
          {service.slots_needed} serving
        </Text>
      </View>

      <WhoCanJoinPicker
        value={openToAll ? "open" : "invite_only"}
        detail={{ invite_only: "Ask more, they accept first" }}
        onChange={(value) => setOpenToAll(value === "open")}
      />

      <SectionHeader title="Places needed" />
      <View className="flex-row items-center rounded-button border border-border bg-white px-3 py-2">
        <Pressable
          className="h-11 w-11 items-center justify-center rounded-pill bg-indigoSoft"
          accessibilityRole="button"
          accessibilityLabel="One fewer place"
          onPress={() => setSlots((value) => Math.max(1, value - 1))}
        >
          <Ionicons name="remove" size={20} color={tokens.colors.indigo} />
        </Pressable>
        <Text className="flex-1 text-center font-display text-2xl text-stone">
          {slots}
        </Text>
        <Pressable
          className="h-11 w-11 items-center justify-center rounded-pill bg-indigoSoft"
          accessibilityRole="button"
          accessibilityLabel="One more place"
          onPress={() => setSlots((value) => Math.min(100, value + 1))}
        >
          <Ionicons name="add" size={20} color={tokens.colors.indigo} />
        </Pressable>
      </View>
      <Text className="mt-1.5 font-sans text-sm text-stoneMuted">
        {service.filledSlots} already serving · {placesLeft} still to fill
      </Text>

      {/* Asking specific devotees only makes sense while it is invite only. */}
      {!openToAll ? (
        <>
          <SectionHeader title="Ask more devotees" />
          <DevoteePicker
            devotees={invitable}
            selectedIds={inviteeIds}
            currentUserId={activeUserId}
            maxSelectable={placesLeft}
            locked={{
              ids: alreadyAsked,
              label: "Already asked, waiting to hear back",
            }}
            onToggle={(id) =>
              setInviteeIds((current) =>
                current.includes(id)
                  ? current.filter((value) => value !== id)
                  : [...current, id],
              )
            }
          />
        </>
      ) : null}

      {formError || update.error ? (
        <View className="mt-3">
          <FormError
            message={
              formError ??
              errorMessage(update.error, "This seva could not be changed.") ??
              "This seva could not be changed."
            }
          />
        </View>
      ) : null}

      <View className="mt-section">
        <Button disabled={update.isPending} onPress={submit}>
          {update.isPending ? "Saving…" : "Save changes"}
        </Button>
      </View>

      {remove.error ? (
        <View className="mt-3">
          <FormError
            message={
              errorMessage(remove.error, "This seva could not be removed.") ??
              "This seva could not be removed."
            }
          />
        </View>
      ) : null}

      <View className="mt-3">
        <Button
          variant="secondary"
          disabled={remove.isPending}
          onPress={confirmRemove}
        >
          {remove.isPending ? "Removing…" : "Remove this seva request"}
        </Button>
      </View>

      <ClashWarningSheet
        visible={warning}
        title={coordinatorClashTitle(clashing)}
        message={coordinatorClashSummary(clashing, {
          startTime: service.start_time,
          durationMinutes: service.duration_minutes,
        })}
        proceedLabel="Ask them anyway"
        onProceed={() => {
          setWarning(false);
          save();
        }}
        onClose={() => setWarning(false)}
      />
    </Screen>
  );
}
