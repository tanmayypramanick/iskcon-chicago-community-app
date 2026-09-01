import { Ionicons } from "@expo/vector-icons";
import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import { Pressable, Text, View } from "react-native";
import { useEffect, useState } from "react";

import tokens from "../../design-tokens.json";
import { Button, Screen, SectionHeader } from "../components/ui";
import { useCurrentAccessProfile } from "../features/access/hooks";
import { hasAccessPermission } from "../features/access/model";
import {
  ClashWarningSheet,
  CustomServiceInput,
  DateTimeFields,
  DevoteePicker,
  DurationPicker,
  FormError,
  type JoinAudience,
  ServiceTypePicker,
  WhoCanJoinPicker,
} from "../features/services/components";
import {
  coordinatorClashSummary,
  coordinatorClashTitle,
} from "../features/services/clashes";
import {
  dateToKey,
  errorMessage,
  getDefaultServiceTime,
  timeToDatabaseValue,
} from "../features/services/format";
import {
  useCreateServiceRequirement,
  useServiceDashboard,
  useSevaClashLookup,
} from "../features/services/hooks";
import {
  dateFromKey,
  timeFromValue,
} from "../features/schedule/layout";
import type { ServicesStackParamList } from "../navigation/types";
import { usePrototypeSession } from "../store/usePrototypeSession";

type Props = NativeStackScreenProps<ServicesStackParamList, "CreateService">;

export function CreateServiceScreen({ navigation, route }: Props) {
  const activeUserId = usePrototypeSession((state) => state.activeUserId);
  const profile = useCurrentAccessProfile(activeUserId);
  const dashboard = useServiceDashboard(activeUserId);
  const createRequirement = useCreateServiceRequirement();
  const [selectedTypeId, setSelectedTypeId] = useState<string | null>(null);
  const [customSelected, setCustomSelected] = useState(false);
  const [customName, setCustomName] = useState("");
  // Prefilled when the form was opened by tapping an empty square on the
  // timetable: that tap already said which day and which half hour, and asking
  // again is the difference between "post a seva here" and "post a seva".
  const [date, setDate] = useState(() =>
    route.params?.date ? dateFromKey(route.params.date) : new Date(),
  );
  const [time, setTime] = useState(() =>
    route.params?.startTime
      ? timeFromValue(route.params.startTime)
      : getDefaultServiceTime(),
  );
  const [durationMinutes, setDurationMinutes] = useState(60);
  const [slotsNeeded, setSlotsNeeded] = useState(1);
  const [participationMode, setParticipationMode] =
    useState<JoinAudience>("open");
  const [inviteeIds, setInviteeIds] = useState<string[]>([]);
  const [formError, setFormError] = useState<string | null>(null);
  const role = (profile.data?.role ?? "devotee");
  const canAskDirectly = hasAccessPermission(role, "services.offer_assignment");

  const toggleInvitee = (id: string) => {
    setInviteeIds((current) =>
      current.includes(id)
        ? current.filter((inviteeId) => inviteeId !== id)
        : [...current, id],
    );
  };

  const dateKey = dateToKey(date);
  const startTime = timeToDatabaseValue(time);

  /**
   * Whether each devotee about to be invited is already serving over these
   * hours. Asked as the form is filled in, so the answer is on hand the moment
   * "Post" is pressed rather than a round trip after it.
   */
  const inviteeClashes = useSevaClashLookup(
    canAskDirectly && participationMode === "invite_only"
      ? inviteeIds.map((devoteeId) => ({
          key: devoteeId,
          devoteeId,
          date: dateKey,
          startTime,
          durationMinutes,
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
  // Their day can change while this form is open. A warning that is no longer
  // true takes itself down.
  useEffect(() => {
    if (warning && !anyClash) setWarning(false);
  }, [anyClash, warning]);

  const post = () => {
    createRequirement.mutate(
      {
        serviceTypeId: customSelected ? null : selectedTypeId,
        customName: customSelected ? customName.trim() : null,
        date: dateKey,
        startTime,
        durationMinutes,
        slotsNeeded,
        participationMode,
        inviteeIds,
      },
      { onSuccess: () => navigation.goBack() },
    );
  };

  const submit = () => {
    setFormError(null);
    if (!selectedTypeId && !customSelected) {
      setFormError("Choose a service or enter a custom service name.");
      return;
    }
    if (customSelected && customName.trim().length < 2) {
      setFormError("Enter a meaningful service name.");
      return;
    }
    if (participationMode === "invite_only" && inviteeIds.length === 0) {
      setFormError("Select at least one devotee for an invite-only service.");
      return;
    }
    // Said before the invitation goes out, and never instead of it.
    if (anyClash) {
      setWarning(true);
      return;
    }

    post();
  };

  const error =
    formError ??
    errorMessage(
      createRequirement.error,
      "The seva request could not be posted.",
    );

  return (
    <Screen topInset={false}>
      <Text className="mb-2 font-display text-[28px] leading-9 text-stone">
        Where is help needed?
      </Text>
      <Text className="mb-section font-sans text-base leading-6 text-stoneMuted">
        Share one clear seva need so devotees can respond quickly.
      </Text>

      <SectionHeader title="Service" />
      {dashboard.data ? (
        <ServiceTypePicker
          serviceTypes={dashboard.data.serviceTypes}
          selectedTypeId={selectedTypeId}
          customSelected={customSelected}
          onSelectType={(id) => {
            setSelectedTypeId(id);
            setCustomSelected(false);
          }}
          onSelectCustom={() => {
            setSelectedTypeId(null);
            setCustomSelected(true);
          }}
        />
      ) : (
        <Text className="font-sans text-base text-stoneMuted">
          Loading service catalog…
        </Text>
      )}
      {customSelected ? (
        <CustomServiceInput value={customName} onChangeText={setCustomName} />
      ) : null}

      <View className="mt-section">
        <SectionHeader title="Date and time" />
        <DateTimeFields
          date={date}
          time={time}
          minimumDate={new Date()}
          onDateChange={setDate}
          onTimeChange={setTime}
        />
      </View>

      <View className="mt-section">
        <SectionHeader title="Duration" />
        <DurationPicker value={durationMinutes} onChange={setDurationMinutes} />
      </View>

      <View className="mt-section">
        <SectionHeader title="How many devotees?" />
        <View className="flex-row items-center justify-between rounded-card border border-border bg-white p-3">
          <Pressable
            className="h-12 w-12 items-center justify-center rounded-pill bg-indigoSoft"
            accessibilityRole="button"
            accessibilityLabel="Decrease slots needed"
            disabled={slotsNeeded === 1}
            onPress={() =>
              setSlotsNeeded((value) => {
                const next = Math.max(1, value - 1);
                setInviteeIds((ids) => ids.slice(0, next));
                return next;
              })
            }
          >
            <Ionicons name="remove" size={24} color={tokens.colors.indigo} />
          </Pressable>
          <View className="items-center">
            <Text className="font-display text-3xl text-stone">
              {slotsNeeded}
            </Text>
            <Text className="font-sans text-sm text-stoneMuted">
              places needed
            </Text>
          </View>
          <Pressable
            className="h-12 w-12 items-center justify-center rounded-pill bg-indigo"
            accessibilityRole="button"
            accessibilityLabel="Increase slots needed"
            onPress={() => setSlotsNeeded((value) => Math.min(100, value + 1))}
          >
            <Ionicons name="add" size={24} color={tokens.colors.white} />
          </Pressable>
        </View>
      </View>

      <View className="mt-section">
        <WhoCanJoinPicker
          value={participationMode}
          allowInvite={canAskDirectly}
          onChange={(value) => {
            setParticipationMode(value);
            if (value === "open") setInviteeIds([]);
          }}
        />
      </View>

      {dashboard.data && canAskDirectly && participationMode === "invite_only" ? (
        <View className="mt-section">
          <SectionHeader title="Choose devotee(s)" />
          <DevoteePicker
            devotees={dashboard.data.devotees}
            currentUserId={activeUserId}
            selectedIds={inviteeIds}
            onToggle={toggleInvitee}
            maxSelectable={slotsNeeded}
          />
        </View>
      ) : null}

      {error ? <FormError message={error} /> : null}

      <View className="mt-section">
        <Button
          icon="send-outline"
          disabled={createRequirement.isPending || dashboard.isLoading}
          onPress={submit}
        >
          {createRequirement.isPending
            ? "Posting…"
            : "Post seva request"}
        </Button>
      </View>

      <ClashWarningSheet
        visible={warning}
        title={coordinatorClashTitle(clashing)}
        message={coordinatorClashSummary(clashing, {
          startTime,
          durationMinutes,
        })}
        proceedLabel="Post and ask anyway"
        onProceed={() => {
          setWarning(false);
          post();
        }}
        onClose={() => setWarning(false)}
      />
    </Screen>
  );
}
