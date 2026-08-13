import { Ionicons } from "@expo/vector-icons";
import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import { useEffect, useState } from "react";
import { Alert, Pressable, Text, View } from "react-native";

import tokens from "../../design-tokens.json";
import { Button, Screen, SectionHeader } from "../components/ui";
import {
  ClashWarningSheet,
  CustomServiceInput,
  DateField,
  DevoteePicker,
  FormError,
  type JoinAudience,
  ServiceTypePicker,
  TimeField,
  WhoCanJoinPicker,
} from "../features/services/components";
import {
  coordinatorClashSummary,
  coordinatorClashTitle,
  nextDateOnWeekday,
  weekdayNameForDate,
} from "../features/services/clashes";
import {
  dateToKey,
  errorMessage,
  timeToDatabaseValue,
  weekdayNames,
} from "../features/services/format";
import {
  useCreateRecurringService,
  useDeleteRecurringService,
  useServiceDashboard,
  useSevaClashLookup,
  useUpdateRecurringService,
} from "../features/services/hooks";
import type { ServicesStackParamList } from "../navigation/types";
import { usePrototypeSession } from "../store/usePrototypeSession";

type Props = NativeStackScreenProps<ServicesStackParamList, "CreateRecurringService">;

function dateFromKey(key: string) {
  const [year, month, day] = key.split("-").map(Number);
  return new Date(year, month - 1, day, 12);
}

function timeFromValue(value: string) {
  const [hour, minute] = value.split(":").map(Number);
  const date = new Date();
  date.setHours(hour, minute, 0, 0);
  return date;
}

export function CreateRecurringServiceScreen({ navigation, route }: Props) {
  const activeUserId = usePrototypeSession((state) => state.activeUserId);
  const dashboard = useServiceDashboard(activeUserId);
  const createTemplate = useCreateRecurringService();
  const updateTemplate = useUpdateRecurringService();
  const deleteTemplate = useDeleteRecurringService();
  const templateId = route.params?.templateId;
  const template = dashboard.data?.recurringTemplates.find((item) => item.id === templateId);
  const [initialized, setInitialized] = useState(false);
  const [serviceTypeId, setServiceTypeId] = useState<string | null>(null);
  const [customSelected, setCustomSelected] = useState(false);
  const [customName, setCustomName] = useState("");
  // A tap on an empty square of the timetable already chose the weekday, the
  // date the rhythm starts and the hour it starts at; the form opens on them
  // rather than on today.
  const prefill = route.params;
  const [daysOfWeek, setDaysOfWeek] = useState<number[]>([
    prefill?.dayOfWeek ?? new Date().getDay(),
  ]);
  const [startDate, setStartDate] = useState(() =>
    prefill?.startDate ? dateFromKey(prefill.startDate) : new Date(),
  );
  const [hasEndDate, setHasEndDate] = useState(false);
  const [endDate, setEndDate] = useState(() => { const date = new Date(); date.setMonth(date.getMonth() + 3); return date; });
  const [startTime, setStartTime] = useState(() =>
    prefill?.startTime ? timeFromValue(prefill.startTime) : new Date(),
  );
  const [endTime, setEndTime] = useState(() => {
    const date = prefill?.startTime ? timeFromValue(prefill.startTime) : new Date();
    date.setHours(date.getHours() + 1);
    return date;
  });
  const [slotsNeeded, setSlotsNeeded] = useState(1);
  const [participationMode, setParticipationMode] = useState<JoinAudience>("invite_only");
  const [inviteeIds, setInviteeIds] = useState<string[]>([]);
  const [formError, setFormError] = useState<string | null>(null);

  useEffect(() => {
    if (!template || initialized) return;
    setServiceTypeId(template.service_type_id);
    setCustomSelected(!template.service_type_id);
    setCustomName(template.custom_name ?? "");
    setDaysOfWeek(template.days_of_week);
    setStartDate(dateFromKey(template.start_date));
    setHasEndDate(Boolean(template.end_date));
    if (template.end_date) setEndDate(dateFromKey(template.end_date));
    const start = timeFromValue(template.start_time);
    const end = new Date(start.getTime() + template.duration_minutes * 60000);
    setStartTime(start); setEndTime(end);
    setSlotsNeeded(template.slots_needed);
    setParticipationMode(template.participation_mode);
    // Standing assignees are deliberately not put in the picker's selection.
    // `update_service_template_v2` skips anyone already active, so sending them
    // back changes nothing; they are shown as locked rows instead, which is the
    // truth — nothing this form sends can take a devotee off a weekly seva.
    setInviteeIds([]);
    setInitialized(true);
  }, [initialized, template]);

  const standingIds = template?.assignees.map((person) => person.id) ?? [];

  const spanStart = startTime.getHours() * 60 + startTime.getMinutes();
  const spanEnd = endTime.getHours() * 60 + endTime.getMinutes();
  const durationMinutes =
    (spanEnd <= spanStart ? spanEnd + 24 * 60 : spanEnd) - spanStart;
  const startTimeValue = timeToDatabaseValue(startTime);
  // A clash check about a date that has already gone answers nothing useful, so
  // an existing rota is checked from today rather than from the date it began.
  const todayKey = dateToKey(new Date());
  const checkFrom =
    dateToKey(startDate) > todayKey ? dateToKey(startDate) : todayKey;

  /**
   * One question per devotee per weekday, on the next occurrence of each — see
   * `nextDateOnWeekday` for why that is the right question for a rota.
   *
   * Bounded, because "every day for a hundred places" is a legal thing to fill
   * this form in with and would otherwise be seven hundred round trips. Past the
   * budget the check simply stops: the app only ever *warns*, and never claims a
   * devotee is free, so a shorter check says less rather than something untrue.
   */
  const clashRequests = (
    participationMode === "invite_only" && durationMinutes >= 1 && durationMinutes <= 720
      ? inviteeIds.flatMap((devoteeId) =>
          [...daysOfWeek].sort().map((day) => ({
            key: `${devoteeId}:${day}`,
            devoteeId,
            date: nextDateOnWeekday(checkFrom, day),
            startTime: startTimeValue,
            durationMinutes,
          })),
        )
      : []
  ).slice(0, 28);
  const rotaClashes = useSevaClashLookup(clashRequests);
  const clashing = inviteeIds.map((devoteeId) => ({
    name:
      dashboard.data?.devotees.find((devotee) => devotee.id === devoteeId)
        ?.name ?? "A devotee",
    clashes: [...daysOfWeek]
      .flatMap((day) => rotaClashes.get(`${devoteeId}:${day}`) ?? [])
      .sort((left, right) => right.overlap_minutes - left.overlap_minutes),
  }));
  const anyClash = clashing.some((entry) => entry.clashes.length > 0);
  // The day the warning is worded around: the one the worst clash falls on.
  const worstClash = clashing
    .flatMap((entry) => entry.clashes)
    .sort((left, right) => right.overlap_minutes - left.overlap_minutes)[0];
  const [warning, setWarning] = useState(false);
  useEffect(() => {
    if (warning && !anyClash) setWarning(false);
  }, [anyClash, warning]);

  const save = () => {
    const input = {
      serviceTypeId,
      customName: serviceTypeId ? null : customName.trim(),
      daysOfWeek,
      startTime: startTimeValue,
      durationMinutes,
      slotsNeeded,
      participationMode,
      startDate: dateToKey(startDate),
      endDate: hasEndDate ? dateToKey(endDate) : null,
      inviteeIds,
    };
    const options = { onSuccess: () => navigation.goBack() };
    if (templateId) updateTemplate.mutate({ ...input, templateId }, options);
    else createTemplate.mutate(input, options);
  };

  const submit = () => {
    setFormError(null);
    if (!serviceTypeId && (!customSelected || customName.trim().length < 2)) {
      setFormError("Choose a listed seva or type a meaningful seva name."); return;
    }
    if (!daysOfWeek.length) { setFormError("Choose at least one day each week."); return; }
    if (durationMinutes > 720) { setFormError("A weekly seva may be up to 12 hours long."); return; }
    if (hasEndDate && endDate < startDate) { setFormError("The schedule end date must be after its start date."); return; }
    // Only when it is first created. On an existing weekly seva the list is
    // purely additive, so "nobody new" is a legitimate save — demanding a name
    // locked every temple weekly seva whose invitations were still unanswered
    // out of being edited at all.
    if (!templateId && participationMode === "invite_only" && !inviteeIds.length) { setFormError("Choose at least one devotee to invite."); return; }
    // Said before the invitations go out, and it stops nothing.
    if (anyClash) { setWarning(true); return; }
    save();
  };

  const mutation = templateId ? updateTemplate : createTemplate;
  const error = formError ?? (mutation.error instanceof Error ? mutation.error.message : mutation.error ? "The weekly seva could not be saved." : null) ?? errorMessage(deleteTemplate.error, "Something went wrong.");

  return (
    <Screen topInset={false}>
      <Text className="mb-2 font-display text-[28px] leading-9 text-stone">{templateId ? "Shape this weekly seva" : "Create a steady rhythm of seva"}</Text>
      <Text className="mb-section font-sans text-base leading-6 text-stoneMuted">Choose several days, exact start and end times, and the devotees to invite. No one is assigned until they accept.</Text>

      <SectionHeader title="Seva" />
      {dashboard.data ? <ServiceTypePicker
        serviceTypes={dashboard.data.serviceTypes}
        selectedTypeId={serviceTypeId}
        customSelected={customSelected}
        onSelectType={(id) => { setServiceTypeId(id); setCustomSelected(false); }}
        onSelectCustom={() => { setCustomSelected(true); setServiceTypeId(null); }}
      /> : <Text className="font-sans text-base text-stoneMuted">Loading seva catalog…</Text>}
      {customSelected ? <CustomServiceInput value={customName} onChangeText={setCustomName} placeholder="Type the weekly seva" /> : null}

      <View className="mt-section">
        <SectionHeader title="Every week on" />
        <View className="flex-row flex-wrap gap-2">
          {weekdayNames.map((day, index) => {
            const selected = daysOfWeek.includes(index);
            return <Pressable key={day} className={`min-h-11 min-w-[29%] flex-1 items-center justify-center rounded-pill border px-3 ${selected ? "border-indigo bg-indigo" : "border-border bg-white"}`} accessibilityRole="checkbox" accessibilityState={{ checked: selected }} onPress={() => setDaysOfWeek((current) => selected ? current.filter((value) => value !== index) : [...current, index].sort())}>
              <Text className={`font-sans-bold text-sm ${selected ? "text-white" : "text-stone"}`}>{day.slice(0, 3)}</Text>
            </Pressable>;
          })}
        </View>
      </View>

      <View className="mt-section">
        <SectionHeader title="Time each selected day" />
        <View className="flex-row gap-3"><TimeField label="Start" value={startTime} onChange={setStartTime} /><TimeField label="End" value={endTime} onChange={setEndTime} /></View>
      </View>

      <View className="mt-section gap-3">
        <SectionHeader title="Schedule dates" />
        <DateField label="Starts" value={startDate} onChange={setStartDate} minimumDate={new Date()} />
        <Pressable className={`min-h-touch flex-row items-center rounded-button border px-4 ${hasEndDate ? "border-indigo bg-indigo" : "border-border bg-white"}`} onPress={() => setHasEndDate((value) => !value)}>
          <Ionicons name={hasEndDate ? "calendar" : "infinite"} size={20} color={hasEndDate ? tokens.colors.white : tokens.colors.indigo} />
          <Text className={`ml-3 font-sans-bold text-base ${hasEndDate ? "text-white" : "text-stone"}`}>{hasEndDate ? "Ends on a date" : "Continues until changed"}</Text>
        </Pressable>
        {hasEndDate ? <DateField label="Ends" value={endDate} onChange={setEndDate} minimumDate={startDate} /> : null}
      </View>

      <View className="mt-section">
        <SectionHeader title="People needed each time" />
        <View className="flex-row items-center justify-between rounded-card border border-border bg-white p-3">
          <Pressable className="h-12 w-12 items-center justify-center rounded-pill bg-indigoSoft" disabled={slotsNeeded === 1} onPress={() => setSlotsNeeded((value) => { const next = Math.max(1, value - 1); setInviteeIds((ids) => ids.slice(0, next)); return next; })}><Ionicons name="remove" size={24} color={tokens.colors.indigo} /></Pressable>
          <Text className="font-display text-3xl text-stone">{slotsNeeded}</Text>
          <Pressable className="h-12 w-12 items-center justify-center rounded-pill bg-indigo" onPress={() => setSlotsNeeded((value) => Math.min(100, value + 1))}><Ionicons name="add" size={24} color={tokens.colors.white} /></Pressable>
        </View>
      </View>

      <View className="mt-section">
        <WhoCanJoinPicker
          value={participationMode}
          detail={{ invite_only: "They accept each week" }}
          onChange={(value) => { setParticipationMode(value); if (value === "open") setInviteeIds([]); }}
        />
      </View>

      {participationMode === "invite_only" && dashboard.data ? <View className="mt-section"><SectionHeader title={templateId ? "Invite more devotee(s)" : "Invite devotee(s)"} />{templateId && standingIds.length ? <Text className="mb-2 font-sans text-sm leading-5 text-stoneMuted">Devotees already serving this weekly seva stay on it. To take someone off, remove the day they serve or ask them to report themselves unavailable from a date onward.</Text> : null}<DevoteePicker devotees={dashboard.data.devotees} currentUserId={activeUserId} selectedIds={inviteeIds} maxSelectable={slotsNeeded} locked={{ ids: standingIds, label: "Already serving this weekly seva" }} onToggle={(id) => setInviteeIds((current) => current.includes(id) ? current.filter((value) => value !== id) : [...current, id])} /></View> : null}

      {error ? <FormError message={error} /> : null}
      <View className="mt-section gap-3"><Button icon="repeat-outline" disabled={mutation.isPending || dashboard.isLoading} onPress={submit}>{mutation.isPending ? "Saving…" : templateId ? "Save weekly seva" : "Create weekly seva"}</Button>
      {templateId ? <Button variant="secondary" icon="trash-outline" disabled={deleteTemplate.isPending} onPress={() => Alert.alert("Delete weekly seva?", "Future occurrences, invitations, and coverage requests will be removed. Completed history remains.", [{ text: "Keep", style: "cancel" }, { text: "Delete", style: "destructive", onPress: () => deleteTemplate.mutate(templateId, { onSuccess: () => navigation.popTo("RecurringServices") }) }])}>Delete weekly seva</Button> : null}</View>

      <ClashWarningSheet
        visible={warning}
        title={coordinatorClashTitle(clashing)}
        message={coordinatorClashSummary(clashing, {
          startTime: startTimeValue,
          durationMinutes,
          // Named from the clash's own date, so "every Thursday" is Thursday
          // because that is the day the collision is actually on.
          weekday: worstClash
            ? weekdayNameForDate(worstClash.occurs_on)
            : undefined,
        })}
        proceedLabel="Invite them anyway"
        onProceed={() => {
          setWarning(false);
          save();
        }}
        onClose={() => setWarning(false)}
      />
    </Screen>
  );
}
