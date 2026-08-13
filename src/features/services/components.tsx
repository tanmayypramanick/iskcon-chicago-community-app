import DateTimePicker from "@react-native-community/datetimepicker";
import { Ionicons } from "@expo/vector-icons";
import React from "react";
import {
  Modal,
  Platform,
  Pressable,
  Text,
  TextInput,
  useWindowDimensions,
  View,
} from "react-native";

import tokens from "../../../design-tokens.json";
import { ActionSheet } from "../../components/ActionSheet";
import { ModalScreen } from "../../components/ModalScreen";
import {
  Avatar,
  AvatarStack,
  InitialAvatar,
  SectionHeader,
} from "../../components/ui";
import {
  formatChicagoShortDate,
  formatChicagoTime,
} from "../../lib/chicagoDate";
import { unservedPlaceReason } from "./clashes";
import {
  formatDuration,
  formatServiceDate,
  formatServiceTime,
  formatWeekdayList,
} from "./format";
import type { SevaTiming } from "./registrations";
import { servedDevotees } from "./selectors";
import type {
  ClosedUnservedSeva,
  ServiceDashboard,
  ServiceDevotee,
  ServiceListItem,
  ServiceParticipant,
  ServiceType,
  ServiceVerification,
  SevaAttendance,
} from "./types";

/**
 * The one height every seva card on the Seva tab is drawn at.
 *
 * Fixed rather than derived, because "derived" is exactly what the temple
 * complained about: a card grew a progress bar when it had places to fill, grew
 * an avatar row when somebody happened to be assigned, and grew a second line
 * when the seva's name was long — so a list of five seva was five heights. Here
 * every row is a set height and every string truncates, and a card with a
 * forty-character name and four devotees on it measures the same as an empty
 * one-line request.
 *
 * The taller figure adds the "who is serving" row, which only the President,
 * Tech Admin and Community Head are shown. That is a property of the reader,
 * not of the seva, so it is still one height per list.
 */
export const SEVA_CARD_HEIGHT = 96;
export const SEVA_CARD_HEIGHT_WITH_PEOPLE = 136;

export type SevaCardPerson = {
  id: string;
  name: string;
  photo_url?: string | null;
};

/**
 * Every seva in every list on the Seva tab, in one card.
 *
 * The temple asked for a card carrying five things and nothing else: the seva's
 * name, its date and time, how long it runs, whether it is weekly, and a "My
 * seva" tag when it is theirs. Coordinators additionally see who is serving.
 * Status badges, slot counts, progress bars, roster days, coverage warnings and
 * attendance tallies have all moved onto the detail screen the card opens.
 */
export function SevaCard({
  name,
  when,
  minutes,
  weekly = false,
  isMine = false,
  people,
  showPeople = false,
  peopleEmptyLabel = "Nobody is serving this yet",
  action,
  onPress,
}: {
  name: string;
  /** "Thu, Aug 6 · 5:00 AM". One line; it truncates rather than wrapping. */
  when: string;
  minutes?: number;
  weekly?: boolean;
  /**
   * Whether this seva is the reader's own. Off for Devotees and Volunteers,
   * whose lists contain nothing else — a tag on every card says nothing.
   */
  isMine?: boolean;
  /** Who is serving. Only rendered where `showPeople` is on. */
  people?: SevaCardPerson[];
  /** `services.view_all` — President, Tech Admin, Community Head. */
  showPeople?: boolean;
  /**
   * What the people row says when nobody is on it. The default looks forward,
   * which is wrong for a seva that is over: one whose every devotee was marked
   * absent has no one left to name, and "yet" would promise a devotee still to
   * come. One line either way, so the card keeps its fixed height.
   */
  peopleEmptyLabel?: string;
  /**
   * The one thing this card is waiting on, answerable without opening it. A
   * pill in the trailing column rather than a footer, so a card that can be
   * acted on is the same height as one that cannot.
   */
  action?: {
    label: string;
    accessibilityLabel: string;
    disabled?: boolean;
    onPress: () => void;
  };
  onPress?: () => void;
}) {
  const serving = people ?? [];

  return (
    <Pressable
      style={{
        height: showPeople ? SEVA_CARD_HEIGHT_WITH_PEOPLE : SEVA_CARD_HEIGHT,
      }}
      className="overflow-hidden rounded-card border border-border bg-white px-card py-3"
      accessibilityRole={onPress ? "button" : undefined}
      accessibilityLabel={`Open ${name}, ${when}`}
      disabled={!onPress}
      onPress={onPress}
    >
      <View className="flex-row items-center">
        <View className="min-w-0 flex-1">
          <View className="h-5 flex-row items-center">
            <View
              className={`rounded-pill px-2 py-0.5 ${
                weekly ? "bg-indigoSoft" : "bg-peacockSoft"
              }`}
            >
              <Text
                className={`font-sans-bold text-[11px] uppercase tracking-wider ${
                  weekly ? "text-indigo" : "text-peacock"
                }`}
                numberOfLines={1}
              >
                {weekly ? "Weekly" : "One-off"}
              </Text>
            </View>
            {isMine ? (
              <View className="ml-2 rounded-pill bg-marigoldSoft px-2 py-0.5">
                <Text className="font-sans-bold text-[11px] uppercase tracking-wider text-stone">
                  My seva
                </Text>
              </View>
            ) : null}
          </View>
          <Text
            className="mt-1.5 h-5 font-sans-bold text-base leading-5 text-stone"
            numberOfLines={1}
          >
            {name}
          </Text>
          {/* Hours are their own node rather than part of `when`: the when line
              is what truncates on a narrow phone, and the hours are the one
              thing on the card that must not be what disappears. */}
          <View className="mt-1 h-[18px] flex-row items-center">
            <Text
              className="min-w-0 flex-1 font-sans text-sm leading-[18px] text-stoneMuted"
              numberOfLines={1}
            >
              {when}
            </Text>
            {typeof minutes === "number" ? (
              <Text className="ml-2 flex-shrink-0 font-sans-bold text-sm leading-[18px] text-stone">
                {formatDuration(minutes)}
              </Text>
            ) : null}
          </View>
        </View>
        {action ? (
          <Pressable
            className="ml-2 min-h-10 flex-shrink-0 items-center justify-center rounded-pill border border-peacock bg-peacockSoft px-3"
            accessibilityRole="button"
            accessibilityLabel={action.accessibilityLabel}
            disabled={action.disabled}
            onPress={action.onPress}
          >
            <Text className="font-sans-bold text-xs text-peacock">
              {action.label}
            </Text>
          </Pressable>
        ) : null}
        {onPress ? (
          <Ionicons
            name="chevron-forward"
            size={19}
            color={tokens.colors.indigo}
          />
        ) : null}
      </View>

      {showPeople ? (
        <View className="mt-2 h-8 flex-row items-center">
          {serving.length ? (
            <>
              <AvatarStack people={serving} max={2} size="tiny" />
              <Text
                className="ml-2.5 min-w-0 flex-1 font-sans text-sm text-stoneMuted"
                numberOfLines={1}
              >
                {serving.map((devotee) => devotee.name).join(", ")}
              </Text>
            </>
          ) : (
            <Text className="font-sans text-sm text-stoneMuted" numberOfLines={1}>
              {peopleEmptyLabel}
            </Text>
          )}
        </View>
      ) : null}
    </Pressable>
  );
}

/**
 * A weekly seva, as one card — never one card per generated date. The date
 * shown is the next one the reader is down for; without one, the days it falls
 * on. Every other date lives on the weekly seva's own screen.
 */
export function WeeklySevaCard({
  template,
  onPress,
  next,
  roster,
  isMine = false,
  showPeople = false,
}: {
  template: ServiceDashboard["recurringTemplates"][number];
  onPress: () => void;
  /** "Thu, Aug 6" — the next date this reader has to be somewhere. */
  next?: string;
  /**
   * Who is on this seva right now, from `weeklyRoster`. Without it the card
   * names the standing roster, which still names a devotee somebody else is
   * covering for — pass it wherever the dashboard is in hand.
   */
  roster?: Array<ServiceDevotee & { assignedDays: number[] }>;
  isMine?: boolean;
  showPeople?: boolean;
}) {
  const serving = roster ?? template.assignees;
  return (
    <SevaCard
      name={template.name}
      weekly
      when={`${next ?? `Every ${formatWeekdayList(template.days_of_week)}`} · ${formatServiceTime(template.start_time)}${template.active ? "" : " · Paused"}`}
      minutes={template.duration_minutes}
      isMine={isMine}
      people={serving}
      showPeople={showPeople}
      onPress={onPress}
    />
  );
}

export function ServiceCard({
  service,
  onPress,
  /** Off for Devotees and Volunteers, whose lists contain only their own seva. */
  showMyTag = true,
  /** On for coordinators, who need to see which devotees are serving. */
  showPeople = false,
}: {
  service: ServiceListItem;
  onPress: () => void;
  showMyTag?: boolean;
  showPeople?: boolean;
}) {
  // `servedDevotees`, never `servingDevotees`: a devotee marked absent or
  // excused held a place but offered nothing, and this row is the app saying
  // who served. On an upcoming seva the two lists are identical — attendance
  // cannot be recorded before the start instant — so this costs nothing there
  // and is the whole point on a seva that is over.
  const people = service.participants ? servedDevotees(service) : [];
  return (
    <SevaCard
      name={service.name}
      // A generated occurrence belongs to a weekly seva, and saying so is the
      // marker the temple asked for.
      weekly={Boolean(service.template_id)}
      when={`${formatServiceDate(service.date)} · ${formatServiceTime(service.start_time)}`}
      minutes={service.duration_minutes}
      isMine={showMyTag && Boolean(service.currentUserAssignment)}
      people={people}
      showPeople={showPeople}
      peopleEmptyLabel={
        service.status === "completed"
          ? "Nobody served this"
          : "Nobody is serving this yet"
      }
      onPress={onPress}
    />
  );
}

export const ATTENDANCE_CHOICES = [
  { value: "served", label: "Served" },
  { value: "absent", label: "Absent" },
  { value: "excused", label: "Excused" },
] as const;

/** How one devotee's place reads when nobody has answered for it yet. */
function attendanceBadge(attendance: SevaAttendance | null) {
  if (attendance === "served") {
    return { label: "Served", bubble: "bg-peacockSoft", text: "text-peacock" };
  }
  if (attendance === "absent") {
    return { label: "Absent", bubble: "bg-white border border-vermilion", text: "text-vermilion" };
  }
  if (attendance === "excused") {
    return { label: "Excused", bubble: "bg-sandalwood", text: "text-stoneMuted" };
  }
  return { label: "Not marked", bubble: "bg-marigoldSoft", text: "text-stone" };
}

/**
 * The devotees on one seva, each with their own answer and their own control.
 *
 * Attendance belongs to a place, not to a seva: three devotees can be rostered
 * and one of them not turn up, so every name carries its own served / absent /
 * excused and marking one must leave the others exactly as they were. The rows
 * are uniform whether or not the controls are shown, so the card is the same
 * shape for a devotee reading it as for the coordinator answering it.
 */
export function ServingList({
  participants,
  currentUserId,
  canRecord,
  onRecord,
}: {
  participants: ServiceParticipant[];
  currentUserId: string | null;
  /** Whoever posted the seva, a Tech Admin or the President, once it has begun. */
  canRecord: boolean;
  onRecord: (assignmentId: string, attendance: SevaAttendance | null) => void;
}) {
  return (
    <View className="overflow-hidden rounded-card border border-border bg-white">
      {participants.map((participant, index) => {
        const { assignment, devotee } = participant;
        // Before a seva starts nobody is expected to be marked, so saying so of
        // every devotee is noise. Once it has begun — which is exactly when the
        // controls appear — an unanswered place is the thing worth seeing.
        const badge =
          assignment.attendance || canRecord
            ? attendanceBadge(assignment.attendance)
            : null;
        return (
          <View
            key={assignment.id}
            className={`px-card py-3 ${
              index < participants.length - 1 ? "border-b border-border" : ""
            }`}
          >
            <View className="min-h-11 flex-row items-center">
              <Avatar
                name={devotee.name}
                photoUrl={devotee.photo_url}
                size="small"
              />
              <View className="ml-3 min-w-0 flex-1 pr-2">
                <Text
                  className="font-sans-bold text-base text-stone"
                  numberOfLines={1}
                >
                  {devotee.name}
                  {devotee.id === currentUserId ? " (You)" : ""}
                </Text>
                <Text className="mt-0.5 font-sans text-sm capitalize text-stoneMuted">
                  {devotee.role_name.replace(/_/g, " ")}
                </Text>
              </View>
              {badge ? (
                <View
                  className={`flex-shrink-0 rounded-pill px-2.5 py-1 ${badge.bubble}`}
                >
                  <Text className={`font-sans-bold text-xs ${badge.text}`}>
                    {badge.label}
                  </Text>
                </View>
              ) : null}
            </View>
            {canRecord ? (
              <View className="mt-2.5 flex-row gap-2">
                {ATTENDANCE_CHOICES.map((choice) => {
                  const chosen = assignment.attendance === choice.value;
                  return (
                    <Pressable
                      key={choice.value}
                      className={`min-h-10 flex-1 items-center justify-center rounded-pill border px-2 ${
                        chosen
                          ? "border-peacock bg-peacockSoft"
                          : "border-border bg-white"
                      }`}
                      accessibilityRole="button"
                      accessibilityState={{ selected: chosen }}
                      accessibilityLabel={`Mark ${devotee.name} ${choice.label.toLowerCase()}`}
                      // Tapping the answer already recorded clears it, so a
                      // mistake can be undone without asking anyone.
                      onPress={() =>
                        onRecord(assignment.id, chosen ? null : choice.value)
                      }
                    >
                      <Text
                        className={`font-sans-bold text-xs ${
                          chosen ? "text-peacock" : "text-stone"
                        }`}
                      >
                        {choice.label}
                      </Text>
                    </Pressable>
                  );
                })}
              </View>
            ) : null}
          </View>
        );
      })}
    </View>
  );
}

export function ServiceTypePicker({
  serviceTypes,
  selectedTypeId,
  customSelected,
  onSelectType,
  onSelectCustom,
  allowCustom = true,
}: {
  serviceTypes: ServiceType[];
  selectedTypeId: string | null;
  customSelected: boolean;
  onSelectType: (id: string) => void;
  onSelectCustom: () => void;
  allowCustom?: boolean;
}) {
  return (
    <View className="gap-2">
      {serviceTypes.map((serviceType) => {
        const selected = serviceType.id === selectedTypeId && !customSelected;
        return (
          <Pressable
            key={serviceType.id}
            className={`min-h-touch flex-row items-center rounded-button border px-4 py-3 ${
              selected ? "border-indigo bg-indigo" : "border-border bg-white"
            }`}
            accessibilityRole="radio"
            accessibilityState={{ checked: selected }}
            accessibilityLabel={serviceType.name}
            onPress={() => onSelectType(serviceType.id)}
          >
            <View
              className={`mr-3 h-5 w-5 items-center justify-center rounded-pill border ${
                selected ? "border-white" : "border-stoneMuted"
              }`}
            >
              {selected ? (
                <View className="h-2.5 w-2.5 rounded-pill bg-white" />
              ) : null}
            </View>
            <Text
              className={`min-w-0 flex-1 pr-2 font-sans-bold text-base ${
                selected ? "text-white" : "text-stone"
              }`}
              numberOfLines={2}
            >
              {serviceType.name}
            </Text>
            <Text
              className={`max-w-[34%] flex-shrink text-right font-sans text-xs uppercase tracking-wider ${
                selected ? "text-marigoldSoft" : "text-stoneMuted"
              }`}
              numberOfLines={2}
            >
              {serviceType.category.replace("-", " ")}
            </Text>
          </Pressable>
        );
      })}
      {allowCustom ? (
        <Pressable
          className={`min-h-touch flex-row items-center rounded-button border px-4 py-3 ${
            customSelected
              ? "border-indigo bg-indigo"
              : "border-border bg-white"
          }`}
          accessibilityRole="radio"
          accessibilityState={{ checked: customSelected }}
          accessibilityLabel="Enter a custom service"
          onPress={onSelectCustom}
        >
          <Ionicons
            name="create-outline"
            size={21}
            color={customSelected ? tokens.colors.white : tokens.colors.indigo}
          />
          <Text
            className={`ml-3 font-sans-bold text-base ${
              customSelected ? "text-white" : "text-indigo"
            }`}
          >
            Enter a custom service
          </Text>
        </Pressable>
      ) : null}
    </View>
  );
}

export function CustomServiceInput({
  value,
  onChangeText,
  placeholder = "Describe the seva needed",
}: {
  value: string;
  onChangeText: (value: string) => void;
  placeholder?: string;
}) {
  return (
    <TextInput
      className="mt-3 min-h-touch rounded-button border border-border bg-white px-4 font-sans text-base text-stone"
      placeholder={placeholder}
      placeholderTextColor={tokens.colors.stoneMuted}
      value={value}
      onChangeText={onChangeText}
      maxLength={100}
      autoCapitalize="sentences"
    />
  );
}

/**
 * iOS renders its date and time pickers at a fixed intrinsic width of roughly
 * 320pt. Dropped inline into a half-width column — a Start/End pair — the
 * second one overflowed off the right edge of the screen. Presenting them over
 * the page instead means the picker is never constrained by its field.
 */
function PickerSheet({
  visible,
  title,
  onClose,
  children,
}: {
  visible: boolean;
  title: string;
  onClose: () => void;
  children: React.ReactNode;
}) {
  if (Platform.OS === "android") {
    // Android's picker is already a system dialog; rendering it is enough.
    return visible ? <>{children}</> : null;
  }
  return (
    <Modal
      visible={visible}
      transparent
      animationType="fade"
      onRequestClose={onClose}
    >
      <Pressable
        className="flex-1 items-center justify-center bg-black/40 px-6"
        accessibilityRole="button"
        accessibilityLabel="Close"
        onPress={onClose}
      >
        <Pressable
          className="w-full max-w-[360px] rounded-card bg-white p-4"
          onPress={(event) => event.stopPropagation()}
        >
          <Text className="mb-2 text-center font-sans-bold text-base text-stone">
            {title}
          </Text>
          <View className="items-center">{children}</View>
          <Pressable
            className="mt-2 min-h-touch items-center justify-center rounded-button bg-indigo"
            accessibilityRole="button"
            onPress={onClose}
          >
            <Text className="font-sans-bold text-base text-white">Done</Text>
          </Pressable>
        </Pressable>
      </Pressable>
    </Modal>
  );
}

export function TimeField({
  label,
  value,
  onChange,
}: {
  label: string;
  value: Date;
  onChange: (value: Date) => void;
}) {
  const [open, setOpen] = React.useState(false);
  const handleValueChange = (_event: unknown, selected: Date) => {
    if (Platform.OS === "android") setOpen(false);
    onChange(selected);
  };
  return (
    <View className="flex-1">
      <Text className="mb-1.5 font-sans-bold text-xs uppercase tracking-wider text-stoneMuted">
        {label}
      </Text>
      <Pressable
        className="min-h-touch flex-row items-center rounded-button border border-border bg-white px-4"
        accessibilityRole="button"
        accessibilityLabel={`Choose ${label.toLowerCase()}`}
        onPress={() => setOpen(true)}
      >
        <Ionicons name="time-outline" size={19} color={tokens.colors.indigo} />
        <Text className="ml-2 font-sans-bold text-base text-stone">
          {formatServiceTime(
            `${String(value.getHours()).padStart(2, "0")}:${String(value.getMinutes()).padStart(2, "0")}`,
          )}
        </Text>
      </Pressable>
      <PickerSheet
        visible={open}
        title={label}
        onClose={() => setOpen(false)}
      >
        <DateTimePicker
          // The spinner itself is the only way this field's value can change,
          // so it needs a handle a test can turn.
          testID={`time-picker-${label.toLowerCase()}`}
          value={value}
          mode="time"
          display={Platform.OS === "ios" ? "spinner" : "default"}
          minuteInterval={5}
          onValueChange={handleValueChange}
          onDismiss={() => setOpen(false)}
        />
      </PickerSheet>
    </View>
  );
}

export function DateField({
  label,
  value,
  onChange,
  minimumDate,
  maximumDate,
  // Seva dates are all within a few weeks, so the year is noise. A birth date
  // is the opposite: "Aug 3" says nothing without it.
  withYear = false,
}: {
  label: string;
  value: Date;
  onChange: (value: Date) => void;
  minimumDate?: Date;
  maximumDate?: Date;
  withYear?: boolean;
}) {
  const [open, setOpen] = React.useState(false);
  const handleValueChange = (_event: unknown, selected: Date) => {
    if (Platform.OS === "android") setOpen(false);
    onChange(selected);
  };
  return (
    <View>
      <Text className="mb-1.5 font-sans-bold text-xs uppercase tracking-wider text-stoneMuted">{label}</Text>
      <Pressable className="min-h-touch flex-row items-center rounded-button border border-border bg-white px-4" onPress={() => setOpen(true)}>
        <Ionicons name="calendar-outline" size={19} color={tokens.colors.indigo} />
        <Text className="ml-2 font-sans-bold text-base text-stone">
          {formatServiceDate(`${value.getFullYear()}-${String(value.getMonth() + 1).padStart(2, "0")}-${String(value.getDate()).padStart(2, "0")}`)}
          {withYear ? `, ${value.getFullYear()}` : ""}
        </Text>
      </Pressable>
      <PickerSheet
        visible={open}
        title={label}
        onClose={() => setOpen(false)}
      >
        <DateTimePicker
          testID={`date-picker-${label.toLowerCase()}`}
          value={value}
          mode="date"
          minimumDate={minimumDate}
          maximumDate={maximumDate}
          display={Platform.OS === "ios" ? "inline" : "default"}
          onValueChange={handleValueChange}
          onDismiss={() => setOpen(false)}
        />
      </PickerSheet>
    </View>
  );
}

export function DurationPicker({
  value,
  onChange,
}: {
  value: number;
  onChange: (minutes: number) => void;
}) {
  return (
    <View className="flex-row flex-wrap gap-2">
      {[30, 60, 90, 120, 180, 240].map((minutes) => {
        const selected = value === minutes;
        return (
          <Pressable
            key={minutes}
            className={`min-h-11 items-center justify-center rounded-pill border px-4 ${
              selected ? "border-indigo bg-indigo" : "border-border bg-white"
            }`}
            accessibilityRole="radio"
            accessibilityState={{ checked: selected }}
            onPress={() => onChange(minutes)}
          >
            <Text
              className={`font-sans-bold text-sm ${
                selected ? "text-white" : "text-stone"
              }`}
            >
              {formatDuration(minutes)}
            </Text>
          </Pressable>
        );
      })}
    </View>
  );
}

export function DateTimeFields({
  date,
  time,
  onDateChange,
  onTimeChange,
  maximumDate,
  minimumDate,
}: {
  date: Date;
  time: Date;
  onDateChange: (date: Date) => void;
  onTimeChange: (time: Date) => void;
  maximumDate?: Date;
  minimumDate?: Date;
}) {
  const [picker, setPicker] = React.useState<"date" | "time" | null>(null);
  const { width } = useWindowDimensions();
  const compact = width < 380;

  const handleValueChange = (_event: unknown, selected: Date) => {
    if (Platform.OS === "android") setPicker(null);
    if (picker === "date") onDateChange(selected);
    if (picker === "time") onTimeChange(selected);
  };

  return (
    <View>
      <View className={compact ? "gap-3" : "flex-row gap-3"}>
        <Pressable
          className={`min-h-touch flex-row items-center rounded-button border border-border bg-white px-4 ${
            compact ? "w-full" : "flex-1"
          }`}
          accessibilityRole="button"
          accessibilityLabel="Choose service date"
          onPress={() => setPicker("date")}
        >
          <Ionicons
            name="calendar-outline"
            size={20}
            color={tokens.colors.indigo}
          />
          <Text
            className="ml-2 min-w-0 flex-1 font-sans-bold text-base text-stone"
            numberOfLines={1}
          >
            {formatServiceDate(
              `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(
                date.getDate(),
              ).padStart(2, "0")}`,
            )}
          </Text>
        </Pressable>
        <Pressable
          className={`min-h-touch flex-row items-center rounded-button border border-border bg-white px-4 ${
            compact ? "w-full" : "flex-1"
          }`}
          accessibilityRole="button"
          accessibilityLabel="Choose service time"
          onPress={() => setPicker("time")}
        >
          <Ionicons
            name="time-outline"
            size={20}
            color={tokens.colors.indigo}
          />
          <Text
            className="ml-2 min-w-0 flex-1 font-sans-bold text-base text-stone"
            numberOfLines={1}
          >
            {formatServiceTime(
              `${String(time.getHours()).padStart(2, "0")}:${String(
                time.getMinutes(),
              ).padStart(2, "0")}`,
            )}
          </Text>
        </Pressable>
      </View>

      {picker ? (
        <View className="mt-3 rounded-card border border-border bg-white p-3">
          <DateTimePicker
            value={picker === "date" ? date : time}
            mode={picker}
            display={Platform.OS === "ios" ? "spinner" : "default"}
            minuteInterval={30}
            minimumDate={picker === "date" ? minimumDate : undefined}
            maximumDate={picker === "date" ? maximumDate : undefined}
            onValueChange={handleValueChange}
            onDismiss={() => setPicker(null)}
          />
          {Platform.OS === "ios" ? (
            <Pressable
              className="min-h-touch items-center justify-center rounded-button bg-indigo"
              accessibilityRole="button"
              accessibilityLabel="Finish choosing date and time"
              onPress={() => setPicker(null)}
            >
              <Text className="font-sans-bold text-base text-white">Done</Text>
            </Pressable>
          ) : null}
        </View>
      ) : null}
    </View>
  );
}

/** Who a seva is addressed to, in the words the database uses. */
export type JoinAudience = "open" | "invite_only";

const JOIN_AUDIENCE_CHOICES: Array<{
  value: JoinAudience;
  title: string;
  detail: string;
  icon: keyof typeof Ionicons.glyphMap;
}> = [
  {
    value: "open",
    title: "Open to everyone",
    detail: "Any devotee can join",
    icon: "people-outline",
  },
  {
    value: "invite_only",
    title: "Ask specific devotees",
    detail: "They accept first",
    icon: "mail-outline",
  },
];

/**
 * The single control for "who can join", used everywhere the question is
 * asked — posting a seva request, changing one, and arranging weekly-seva
 * coverage. The temple asked for the same two buttons in all of them: a
 * control that named only the option you were not on, or that laid the two
 * paths out as separate always-open sections, read as one thing to do rather
 * than a choice between two.
 */
export function WhoCanJoinPicker({
  value,
  onChange,
  title = "Who can join",
  /** Off where whoever is asking has no permission to invite anybody. */
  allowInvite = true,
  detail,
}: {
  value: JoinAudience | null;
  onChange: (value: JoinAudience) => void;
  title?: string;
  allowInvite?: boolean;
  /**
   * What each choice does on this screen. Only the small print varies — the
   * two button titles stay identical so the choice is recognisable anywhere.
   */
  detail?: Partial<Record<JoinAudience, string>>;
}) {
  const choices = allowInvite
    ? JOIN_AUDIENCE_CHOICES
    : JOIN_AUDIENCE_CHOICES.filter((choice) => choice.value === "open");

  return (
    <View>
      <SectionHeader title={title} />
      <View className="flex-row gap-3">
        {choices.map((choice) => {
          const selected = value === choice.value;
          return (
            <Pressable
              key={choice.value}
              className={`min-h-[112px] flex-1 rounded-card border p-4 ${
                selected ? "border-indigo bg-indigo" : "border-border bg-white"
              }`}
              accessibilityRole="radio"
              accessibilityState={{ checked: selected }}
              accessibilityLabel={choice.title}
              onPress={() => onChange(choice.value)}
            >
              <Ionicons
                name={choice.icon}
                size={24}
                color={
                  selected ? tokens.colors.marigoldSoft : tokens.colors.indigo
                }
              />
              <Text
                className={`mt-3 font-sans-bold text-base ${
                  selected ? "text-white" : "text-stone"
                }`}
              >
                {choice.title}
              </Text>
              <Text
                className={`mt-1 font-sans text-sm ${
                  selected ? "text-white" : "text-stoneMuted"
                }`}
              >
                {detail?.[choice.value] ?? choice.detail}
              </Text>
            </Pressable>
          );
        })}
      </View>
    </View>
  );
}

export function DevoteePicker({
  devotees,
  selectedIds,
  onToggle,
  currentUserId,
  /** Never more devotees than there are places to fill. */
  maxSelectable,
  locked,
}: {
  devotees: ServiceDevotee[];
  selectedIds: string[];
  onToggle: (id: string) => void;
  currentUserId?: string | null;
  maxSelectable?: number;
  /**
   * Devotees this save cannot change either way, and the reason to show beside
   * them. Both invitation RPCs only ever *add* — nothing the picker sends can
   * withdraw a standing assignee or an invitation already out — so a row that
   * could be unticked was promising something the temple's database never did.
   */
  locked?: { ids: string[]; label: string };
}) {
  const [search, setSearch] = React.useState("");
  const [showAll, setShowAll] = React.useState(false);
  const ordered = [...devotees].sort((left, right) => {
    if (left.id === currentUserId) return -1;
    if (right.id === currentUserId) return 1;
    return left.name.localeCompare(right.name);
  });
  const matching = ordered.filter((devotee) =>
    `${devotee.name} ${devotee.role_name}`
      .toLocaleLowerCase()
      .includes(search.trim().toLocaleLowerCase()),
  );
  const visible = showAll || search.trim() ? matching : matching.slice(0, 6);
  const atCapacity =
    typeof maxSelectable === "number" && selectedIds.length >= maxSelectable;

  return (
    <View>
      {typeof maxSelectable === "number" ? (
        <Text
          className={`mb-2 font-sans text-sm ${
            atCapacity ? "text-peacock" : "text-stoneMuted"
          }`}
        >
          {selectedIds.length} of {maxSelectable} chosen
          {atCapacity
            ? " — add a place to invite more"
            : `. Choose up to ${maxSelectable}.`}
        </Text>
      ) : null}
      <View className="mb-2 flex-row items-center rounded-button border border-border bg-white px-4">
        <Ionicons name="search" size={19} color={tokens.colors.indigo} />
        <TextInput
          className="min-h-touch min-w-0 flex-1 px-3 font-sans text-base text-stone"
          value={search}
          onChangeText={setSearch}
          placeholder="Search devotee by name"
          placeholderTextColor={tokens.colors.stoneMuted}
          autoCapitalize="words"
        />
      </View>
      <View className="overflow-hidden rounded-card border border-border bg-white">
      {visible.map((devotee, index) => {
        const isLocked = Boolean(locked?.ids.includes(devotee.id));
        const selected = isLocked || selectedIds.includes(devotee.id);
        // Once every place is spoken for, only the chosen can be tapped — to
        // deselect. That keeps the invitation list and the places in step.
        const blocked = isLocked || (atCapacity && !selected);
        return (
          <Pressable
            key={devotee.id}
            className={`min-h-[70px] flex-row items-center px-card ${
              index < visible.length - 1 ? "border-b border-border" : ""
            } ${blocked && !isLocked ? "opacity-40" : ""}`}
            accessibilityRole="checkbox"
            accessibilityState={{ checked: selected, disabled: blocked }}
            accessibilityLabel={`Select ${devotee.name}`}
            disabled={blocked}
            onPress={() => onToggle(devotee.id)}
          >
            <InitialAvatar
              initials={initialsForName(devotee.name)}
              size="small"
            />
            <View className="ml-3 min-w-0 flex-1 pr-2">
              <Text
                className="font-sans-bold text-base text-stone"
                numberOfLines={2}
              >
                {devotee.name}{devotee.id === currentUserId ? " (You)" : ""}
              </Text>
              <Text className="mt-0.5 font-sans text-sm capitalize text-stoneMuted">
                {isLocked
                  ? locked!.label
                  : devotee.role_name.replace("_", " ")}
              </Text>
            </View>
            <Ionicons
              name={
                isLocked
                  ? "lock-closed"
                  : selected
                    ? "checkmark-circle"
                    : "ellipse-outline"
              }
              size={24}
              color={
                isLocked
                  ? tokens.colors.stoneMuted
                  : selected
                    ? tokens.colors.peacock
                    : tokens.colors.stoneMuted
              }
            />
          </Pressable>
        );
      })}
      {!visible.length ? (
        <Text className="px-card py-6 text-center font-sans text-base text-stoneMuted">
          No devotee matches that name.
        </Text>
      ) : null}
      </View>
      {!search.trim() && matching.length > 6 ? (
        <Pressable
          className="mt-2 min-h-touch items-center justify-center rounded-button bg-indigoSoft"
          accessibilityRole="button"
          onPress={() => setShowAll((value) => !value)}
        >
          <Text className="font-sans-bold text-sm text-indigo">
            {showAll ? "Show fewer" : `See all ${matching.length} devotees`}
          </Text>
        </Pressable>
      ) : null}
    </View>
  );
}

/**
 * The clash pop-up, in the app's existing sheet vocabulary.
 *
 * It warns and it never blocks. `ActionSheet` already puts the primary choice
 * first and Cancel last, so "accept anyway" is one tap away and no path through
 * this component can prevent it — the temple was explicit that a fifteen-minute
 * overlap is a judgement the devotee makes, not something the app decides.
 *
 * `visible` is deliberately the caller's `open && clashes.length > 0`: when a
 * clash disappears while the sheet is up — the seva cancelled, handed over, or
 * moved — the live query empties and the warning goes with it rather than
 * standing there describing something that is no longer true.
 */
export function ClashWarningSheet({
  visible,
  title,
  message,
  proceedLabel,
  onProceed,
  onClose,
  alternative,
}: {
  visible: boolean;
  title: string;
  message: string;
  /** "Accept anyway", "Ask anyway", "Post anyway". Always available. */
  proceedLabel: string;
  onProceed: () => void;
  onClose: () => void;
  /** The temple's other answer: say when you are free instead. */
  alternative?: { label: string; onPress: () => void };
}) {
  // The sheet has to survive its own subject vanishing. Callers clear the
  // warning the instant the clash does, so by the time this is animating out
  // there are no words left to draw — these are the last true ones.
  const lastShown = React.useRef<{ title: string; message: string } | null>(
    null,
  );
  if (visible && message) lastShown.current = { title, message };
  const shown = visible && message ? { title, message } : lastShown.current;
  // Nothing has ever clashed on this screen, so there is nothing to keep
  // mounted for the sake of an exit animation that will never run.
  if (!shown) return null;

  const actions = [
    {
      label: proceedLabel,
      icon: "checkmark-circle-outline" as const,
      onPress: onProceed,
    },
    ...(alternative
      ? [
          {
            label: alternative.label,
            icon: "calendar-outline" as const,
            onPress: alternative.onPress,
          },
        ]
      : []),
  ];

  return (
    <ActionSheet
      visible={visible}
      title={shown.title}
      message={shown.message}
      actions={actions}
      cancelLabel="Not now"
      onClose={onClose}
    />
  );
}

/**
 * Seva that was closed because nobody served it, kept quiet on purpose.
 *
 * 0068 takes such a seva out of the completed list by cancelling it, which is
 * what the temple asked for and is also the one way that change could hurt: a
 * cancelled instance is invisible in every list this app builds, so without
 * this the poster simply loses it. One muted line, and only when there is
 * something to say — an empty answer draws nothing at all.
 */
export function ClosedUnservedNotice({
  seva,
}: {
  seva: readonly ClosedUnservedSeva[];
}) {
  const [open, setOpen] = React.useState(false);
  if (!seva.length) return null;

  return (
    <>
      <Pressable
        className="mb-section flex-row items-center rounded-button border border-border bg-white px-4 py-3"
        accessibilityRole="button"
        accessibilityLabel={`See the ${seva.length} seva closed because nobody served ${seva.length === 1 ? "it" : "them"}`}
        onPress={() => setOpen(true)}
      >
        <Ionicons
          name="information-circle-outline"
          size={19}
          color={tokens.colors.stoneMuted}
        />
        <Text className="ml-3 min-w-0 flex-1 font-sans text-sm leading-5 text-stoneMuted">
          {seva.length === 1
            ? "1 seva closed because nobody served it"
            : `${seva.length} seva closed because nobody served them`}
        </Text>
        <Ionicons
          name="chevron-forward"
          size={18}
          color={tokens.colors.stoneMuted}
        />
      </Pressable>

      <ModalScreen
        visible={open}
        onClose={() => setOpen(false)}
        eyebrow="Not in the completed list"
        title="Closed because nobody served"
      >
        <Text className="mb-section font-sans text-sm leading-5 text-stoneMuted">
          Every place on these was answered absent or excused, so they were taken
          out of the completed list rather than counted as seva that happened.
          Correcting an attendance mark puts one back.
        </Text>
        <View className="gap-3">
          {seva.map((item) => (
            <View
              key={item.serviceInstanceId}
              className="rounded-card border border-border bg-white p-card"
            >
              <Text className="font-sans-bold text-base text-stone">
                {item.name}
              </Text>
              <Text className="mt-1 font-sans text-sm text-stoneMuted">
                {formatServiceDate(item.occurredOn)} ·{" "}
                {formatServiceTime(item.startedAt)} ·{" "}
                {formatDuration(item.plannedMinutes)}
                {item.isRecurring ? " · Weekly seva" : ""}
              </Text>
              <View className="mt-3 gap-1">
                {item.places.map((place) => (
                  <Text
                    key={`${item.serviceInstanceId}-${place.devoteeId}`}
                    className="font-sans text-sm leading-5 text-stone"
                  >
                    {place.name} — {unservedPlaceReason(place)}
                  </Text>
                ))}
              </View>
            </View>
          ))}
        </View>
      </ModalScreen>
    </>
  );
}

export function FormError({ message }: { message: string }) {
  // A banner with no words in it is worse than no banner: it tells a devotee
  // something is wrong and nothing about what.
  if (!message || !message.trim()) return null;
  return (
    <View className="mt-4 flex-row rounded-button border border-vermilion bg-white px-4 py-3">
      <Ionicons
        name="alert-circle-outline"
        size={20}
        color={tokens.colors.vermilion}
      />
      <Text className="ml-3 flex-1 font-sans text-sm leading-5 text-vermilion">
        {message}
      </Text>
    </View>
  );
}

function initialsForName(name: string) {
  return (
    name
      .split(/\s+/)
      .slice(0, 2)
      .map((part) => part[0]?.toUpperCase())
      .join("") || "D"
  );
}

/** Badge wording for a registration, shared by the card and its detail. */
export function registrationStatusLabel(
  registration: ServiceVerification,
  timing: SevaTiming,
) {
  if (registration.status === "declined") return "Not verified";
  if (registration.status === "verified" && timing === "finished") {
    return "Verified";
  }
  if (timing === "now") return "Happening now";
  if (timing === "upcoming") return "Upcoming";
  return "Finished";
}

/**
 * A seva a devotee registered, on the same card as everything else. Whether it
 * was verified, who verified it and what can still be done about it are on the
 * detail screen behind it — the card only says what every seva card says.
 */
export function RegisteredSevaCard({
  registration,
  timing,
  isMine,
  showPeople = false,
  onPress,
}: {
  registration: ServiceVerification;
  timing: SevaTiming;
  isMine: boolean;
  showPeople?: boolean;
  onPress?: () => void;
}) {
  const start = new Date(registration.start_at);
  const end = new Date(registration.end_at);
  void timing;

  return (
    <SevaCard
      name={registration.name}
      when={`${formatChicagoShortDate(start)} \u00b7 ${formatChicagoTime(start)}`}
      // A registration carries its two instants rather than a length, but it is
      // the same question the temple asked of every other card.
      minutes={Math.max(
        1,
        Math.round((end.getTime() - start.getTime()) / 60_000),
      )}
      isMine={isMine}
      people={registration.devotee ? [registration.devotee] : []}
      showPeople={showPeople}
      onPress={onPress}
    />
  );
}
