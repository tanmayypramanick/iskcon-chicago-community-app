import { Ionicons } from "@expo/vector-icons";
import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import { useEffect, useRef, useState } from "react";
import { Modal, Pressable, Text, TextInput, View } from "react-native";

import tokens from "../../design-tokens.json";
import {
  Avatar,
  Button,
  Screen,
  ScreenTitle,
  SectionHeader,
} from "../components/ui";
import type {
  ChildDetail,
  ChildGender,
  ProfileCommunityInput,
  TempleSinceUnit,
} from "../features/access/api";
import {
  useCurrentAccessProfile,
  useRequestEmailChange,
  useUpdateMyProfile,
  useUpdateMyProfileCommunity,
  useUpdateMyProfileExtras,
} from "../features/access/hooks";
import { photoGuidelines } from "../features/profile/guidelines";
import {
  useRemoveDevoteePhoto,
  useUpdateDevoteePhoto,
} from "../features/profile/hooks";
import {
  addressFromCurrentPosition,
  suggestPlaces,
} from "../features/profile/places";
import { DateField, FormError } from "../features/services/components";
import { dateToKey, errorMessage } from "../features/services/format";
import { getChicagoWallClock } from "../lib/chicagoDate";
import type { ProfileStackParamList } from "../navigation/types";
import { usePrototypeSession } from "../store/usePrototypeSession";

type Props = NativeStackScreenProps<ProfileStackParamList, "ProfileDetails">;

type Gender = ProfileCommunityInput["gender"];
type MaritalStatus = ProfileCommunityInput["maritalStatus"];

export const genderOptions = [
  { value: "male", label: "Male" },
  { value: "female", label: "Female" },
  { value: "prefer_not_to_say", label: "Prefer not to say" },
] as const;

const maritalStatusOptions = [
  { value: "single", label: "Single" },
  { value: "married", label: "Married" },
  { value: "widowed", label: "Widowed" },
  { value: "prefer_not_to_say", label: "Prefer not to say" },
] as const;

const templeSinceUnitOptions = [
  { value: "days", label: "Days" },
  { value: "weeks", label: "Weeks" },
  { value: "months", label: "Months" },
  { value: "years", label: "Years" },
] as const;

/** The database rejects anything outside these, so the form asks first. */
const maxChantingRounds = 200;
const maxChildren = 30;
const maxAge = 120;

/** Nobody was born tomorrow, so the picker will not offer it. */
const today = new Date();

/**
 * Whole years lived, counted on the temple's calendar rather than the device's
 * — a devotee travelling east should not gain a birthday a day early.
 *
 * The comparison is month-then-day, which is also what makes 29 February come
 * out right: in a common year, 28 February is still "before the birthday" and
 * the year only turns over on 1 March.
 *
 * Null when the answer cannot be a real age — a date in the future, or one so
 * far back that the database would refuse the number it produces.
 */
function ageInYears(birth: Date): number | null {
  const now = getChicagoWallClock();
  const month = birth.getMonth() + 1;
  const day = birth.getDate();
  const beforeBirthday =
    now.month < month || (now.month === month && now.day < day);
  const age = now.year - birth.getFullYear() - (beforeBirthday ? 1 : 0);
  return age < 0 || age > maxAge ? null : age;
}

/**
 * A sub-form holds its own identity rather than being addressed by position,
 * so removing one child from the middle cannot shuffle what was typed into the
 * others.
 */
type ChildDraft = {
  id: string;
  name: string;
  /**
   * Only the age is stored: `users.children` accepts a fixed set of keys and a
   * date of birth is not one of them. So the picker lives for this sitting,
   * works out the age, and the age is what is saved and read back.
   */
  dateOfBirth: Date | null;
  age: string;
  gender: ChildGender | null;
  practices: boolean;
  practicingSince: string;
  initiated: boolean;
  initiationDate: Date | null;
  dikshaGuru: string;
};

let childDraftCount = 0;

function newChildDraft(child?: ChildDetail): ChildDraft {
  childDraftCount += 1;
  return {
    id: `child-${childDraftCount}`,
    name: child?.name ?? "",
    dateOfBirth: null,
    age: child?.age === undefined ? "" : numberToField(child.age),
    gender: child?.gender ?? null,
    practices: child?.practices ?? false,
    practicingSince: child?.practicing_since ?? "",
    initiated: child?.initiated ?? false,
    initiationDate: keyToDate(child?.initiation_date ?? null),
    dikshaGuru: child?.diksha_guru ?? "",
  };
}

/**
 * Drafts are only ever added. Typing a number passes through smaller ones on
 * the way — 1 before 10 — and clearing the field to retype it must not throw
 * away the sub-forms underneath, so how many are shown is decided separately
 * from how many exist.
 */
function grownToFit(drafts: ChildDraft[], wanted: number) {
  if (wanted <= drafts.length) return drafts;
  const grown = [...drafts];
  while (grown.length < Math.min(wanted, maxChildren)) {
    grown.push(newChildDraft());
  }
  return grown;
}

/** A stored `YYYY-MM-DD` back into a Date the picker can open on. */
export function keyToDate(key: string | null): Date | null {
  if (!key) return null;
  const [year, month, day] = key.split("-").map(Number);
  if (!year || !month || !day) return null;
  // Midday, so no time zone shift can push the date onto the day before.
  return new Date(year, month - 1, day, 12);
}

export function trimmedOrNull(value: string) {
  return value.trim() || null;
}

/** An unanswered count is "not given", never a NaN the database would refuse. */
function countOrNull(value: string) {
  const digits = value.replace(/[^0-9]/g, "");
  if (!digits) return null;
  const parsed = Number.parseInt(digits, 10);
  return Number.isNaN(parsed) ? null : parsed;
}

function numberToField(value: number | null) {
  return value === null ? "" : String(value);
}

function joinParts(parts: string[]) {
  if (parts.length <= 1) return parts[0] ?? "";
  return `${parts.slice(0, -1).join(", ")} and ${parts[parts.length - 1]}`;
}

function FieldLabel({ children }: { children: string }) {
  return (
    <Text className="mb-1.5 font-sans-bold text-xs uppercase tracking-wider text-stoneMuted">
      {children}
    </Text>
  );
}

/**
 * Repeated sub-forms reuse the same short labels, so anything rendered more
 * than once passes a `spokenAs` that tells a screen reader which one it is.
 */
export function TextField({
  label,
  value,
  onChangeText,
  placeholder,
  multiline = false,
  keyboardType = "default",
  autoCapitalize = "words",
  spokenAs,
}: {
  label: string;
  value: string;
  onChangeText: (value: string) => void;
  placeholder: string;
  multiline?: boolean;
  keyboardType?: "default" | "phone-pad";
  autoCapitalize?: "none" | "words" | "sentences";
  spokenAs?: string;
}) {
  return (
    <View>
      <FieldLabel>{label}</FieldLabel>
      <TextInput
        className={`rounded-button border border-border bg-white px-4 font-sans text-base text-stone ${
          multiline ? "min-h-[82px] py-3" : "min-h-touch"
        }`}
        value={value}
        onChangeText={onChangeText}
        placeholder={placeholder}
        placeholderTextColor={tokens.colors.stoneMuted}
        keyboardType={keyboardType}
        autoCapitalize={autoCapitalize}
        multiline={multiline}
        textAlignVertical={multiline ? "top" : "center"}
        accessibilityLabel={spokenAs ?? label}
        // A name, an address or a guru's name has a natural length; nothing
        // here is prose. The longer bound covers the multiline fields.
        maxLength={multiline ? 1000 : 200}
      />
    </View>
  );
}

export function NumberField({
  label,
  value,
  onChangeText,
  placeholder,
  hint,
  spokenAs,
}: {
  label: string;
  value: string;
  onChangeText: (value: string) => void;
  placeholder: string;
  hint?: string;
  spokenAs?: string;
}) {
  return (
    <View>
      <FieldLabel>{label}</FieldLabel>
      <TextInput
        className="min-h-touch rounded-button border border-border bg-white px-4 font-sans text-base text-stone"
        value={value}
        // Digits only, so a stray character can never reach the database as a
        // number that is not one.
        onChangeText={(next) => onChangeText(next.replace(/[^0-9]/g, ""))}
        placeholder={placeholder}
        placeholderTextColor={tokens.colors.stoneMuted}
        keyboardType="number-pad"
        accessibilityLabel={spokenAs ?? label}
      />
      {hint ? (
        <Text className="mt-1 font-sans text-sm leading-5 text-stoneMuted">
          {hint}
        </Text>
      ) : null}
    </View>
  );
}

export function PillField<Value extends string>({
  label,
  value,
  options,
  onChange,
  hint,
  spokenAs,
}: {
  label: string;
  value: Value | null;
  options: readonly { value: Value; label: string }[];
  onChange: (value: Value) => void;
  hint?: string;
  spokenAs?: string;
}) {
  const spoken = spokenAs ?? label;

  return (
    <View>
      <FieldLabel>{label}</FieldLabel>
      <View className="flex-row flex-wrap gap-2">
        {options.map((option) => {
          const selected = value === option.value;
          return (
            <Pressable
              key={option.value}
              className={`min-h-touch items-center justify-center rounded-pill border px-4 ${
                selected ? "border-indigo bg-indigo" : "border-border bg-white"
              }`}
              accessibilityRole="radio"
              accessibilityState={{ checked: selected }}
              accessibilityLabel={`${spoken} ${option.label}`}
              onPress={() => onChange(option.value)}
            >
              <Text
                className={`font-sans-bold text-base ${
                  selected ? "text-white" : "text-stone"
                }`}
              >
                {option.label}
              </Text>
            </Pressable>
          );
        })}
      </View>
      {hint ? (
        <Text className="mt-1.5 font-sans text-sm leading-5 text-stoneMuted">
          {hint}
        </Text>
      ) : null}
    </View>
  );
}

/**
 * The bundled place list only offers: a devotee born somewhere it does not
 * know simply keeps typing, so the suggestions never gate what can be entered.
 */
function PlaceField({
  label,
  value,
  onChangeText,
  placeholder,
  multiline = false,
  children,
}: {
  label: string;
  value: string;
  onChangeText: (value: string) => void;
  placeholder: string;
  multiline?: boolean;
  children?: React.ReactNode;
}) {
  // Suggestions belong to typing, not to what was loaded from the profile, so
  // the list stays shut until the devotee actually edits the field.
  const [typing, setTyping] = useState(false);
  const suggestions = typing ? suggestPlaces(value) : [];
  const settled = suggestions.some(
    (place) => place.toLocaleLowerCase() === value.trim().toLocaleLowerCase(),
  );

  return (
    <View>
      <TextField
        label={label}
        value={value}
        onChangeText={(next) => {
          setTyping(true);
          onChangeText(next);
        }}
        placeholder={placeholder}
        multiline={multiline}
        autoCapitalize={multiline ? "sentences" : "words"}
      />
      {suggestions.length > 0 && !settled ? (
        <View className="mt-1.5 overflow-hidden rounded-button border border-border bg-white">
          {suggestions.map((place, index) => (
            <Pressable
              key={place}
              className={`min-h-touch justify-center px-4 py-2 ${
                index < suggestions.length - 1 ? "border-b border-border" : ""
              }`}
              accessibilityRole="button"
              accessibilityLabel={`Use ${place}`}
              onPress={() => {
                onChangeText(place);
                setTyping(false);
              }}
            >
              <Text className="font-sans text-base text-stone">{place}</Text>
            </Pressable>
          ))}
        </View>
      ) : null}
      {children}
    </View>
  );
}

/**
 * Every date here is optional, and an empty field must not read as today's
 * date, so nothing is shown in the picker until the devotee asks for one.
 */
function OptionalDateField({
  label,
  value,
  onChange,
  spokenAs,
  maximumDate,
  withYear = false,
}: {
  label: string;
  value: Date | null;
  onChange: (value: Date | null) => void;
  spokenAs?: string;
  maximumDate?: Date;
  withYear?: boolean;
}) {
  const spoken = (spokenAs ?? label).toLowerCase();

  if (!value) {
    return (
      <View>
        <FieldLabel>{label}</FieldLabel>
        <Pressable
          className="min-h-touch flex-row items-center rounded-button border border-border bg-white px-4"
          accessibilityRole="button"
          accessibilityLabel={`Add ${spoken}`}
          onPress={() => onChange(new Date())}
        >
          <Ionicons
            name="calendar-outline"
            size={19}
            color={tokens.colors.indigo}
          />
          <Text className="ml-2 font-sans text-base text-stoneMuted">
            Not given yet
          </Text>
        </Pressable>
      </View>
    );
  }

  return (
    <View>
      <DateField
        label={label}
        value={value}
        onChange={onChange}
        maximumDate={maximumDate}
        withYear={withYear}
      />
      <Pressable
        className="mt-1.5 min-h-10 justify-center"
        accessibilityRole="button"
        accessibilityLabel={`Clear ${spoken}`}
        onPress={() => onChange(null)}
      >
        <Text className="font-sans-bold text-sm text-indigo">Clear</Text>
      </Pressable>
    </View>
  );
}

/**
 * The age the date of birth works out to. It is read-only on purpose: an age
 * that can be typed over the moment a date is set gives the temple two answers
 * to one question, and no way to know which is the true one.
 */
function DerivedAgeField({
  age,
  spokenAs,
}: {
  age: number | null;
  spokenAs?: string;
}) {
  const spoken = spokenAs ?? "Age";

  return (
    <View>
      <FieldLabel>Age</FieldLabel>
      <View
        accessible
        accessibilityLabel={
          age === null ? `${spoken} not known` : `${spoken} ${age}`
        }
        className="min-h-touch justify-center rounded-button border border-border bg-ivory px-4"
      >
        <Text
          className={`font-sans-bold text-base ${
            age === null ? "text-stoneMuted" : "text-stone"
          }`}
        >
          {age === null ? "—" : String(age)}
        </Text>
      </View>
    </View>
  );
}

/**
 * Date of birth and the age it gives, side by side. The child repeater asks the
 * same question, so both places ask it the same way.
 */
export function BirthDateRow({
  dateOfBirth,
  onChange,
  spokenDate,
  spokenAge,
  typedAgeField,
}: {
  dateOfBirth: Date | null;
  onChange: (value: Date | null) => void;
  spokenDate?: string;
  spokenAge?: string;
  /** The child repeater falls back to a typed age until a date is given. */
  typedAgeField?: React.ReactNode;
}) {
  return (
    <View className="flex-row items-start gap-3">
      <View className="flex-1">
        <OptionalDateField
          label="Date of birth"
          spokenAs={spokenDate}
          value={dateOfBirth}
          onChange={onChange}
          maximumDate={today}
          withYear
        />
      </View>
      <View className="w-24">
        {!dateOfBirth && typedAgeField ? (
          typedAgeField
        ) : (
          <DerivedAgeField
            age={dateOfBirth ? ageInYears(dateOfBirth) : null}
            spokenAs={spokenAge}
          />
        )}
      </View>
    </View>
  );
}

function YesNoField({
  question,
  value,
  onChange,
  children,
  spokenAs,
}: {
  question: string;
  value: boolean;
  onChange: (value: boolean) => void;
  children?: React.ReactNode;
  spokenAs?: string;
}) {
  const spoken = spokenAs ?? question;
  const options = [
    { label: "Yes", answer: true },
    { label: "No", answer: false },
  ];

  return (
    <View className="rounded-card border border-border bg-white p-card">
      <Text className="font-sans-bold text-base text-stone">{question}</Text>
      <View className="mt-3 flex-row gap-3">
        {options.map((option) => {
          const selected = value === option.answer;
          return (
            <Pressable
              key={option.label}
              className={`min-h-touch flex-1 items-center justify-center rounded-button border ${
                selected ? "border-indigo bg-indigo" : "border-border bg-white"
              }`}
              accessibilityRole="radio"
              accessibilityState={{ checked: selected }}
              accessibilityLabel={`${spoken} ${option.label}`}
              onPress={() => onChange(option.answer)}
            >
              <Text
                className={`font-sans-bold text-base ${
                  selected ? "text-white" : "text-stone"
                }`}
              >
                {option.label}
              </Text>
            </Pressable>
          );
        })}
      </View>
      {value && children ? <View className="mt-4 gap-3">{children}</View> : null}
    </View>
  );
}

function ChildForm({
  position,
  child,
  onChange,
  onRemove,
}: {
  position: number;
  child: ChildDraft;
  onChange: (patch: Partial<ChildDraft>) => void;
  onRemove: () => void;
}) {
  const who = child.name.trim() || `Child ${position}`;

  return (
    <View className="rounded-card border border-border bg-ivory p-card">
      <View className="mb-3 flex-row items-center justify-between">
        <Text className="min-w-0 flex-1 pr-3 font-sans-bold text-base text-stone">
          {who}
        </Text>
        <Pressable
          className="min-h-10 justify-center"
          accessibilityRole="button"
          accessibilityLabel={`Remove ${who}`}
          onPress={onRemove}
        >
          <Text className="font-sans-bold text-sm text-vermilion">Remove</Text>
        </Pressable>
      </View>

      <View className="gap-3">
        <TextField
          label="Name"
          spokenAs={`Child ${position} name`}
          value={child.name}
          onChangeText={(name) => onChange({ name })}
          placeholder="Their name"
        />
        {/* A date the devotee sets takes over the age, but the age they typed
            is kept behind it rather than overwritten: clearing the date hands
            the number straight back to them. */}
        <BirthDateRow
          dateOfBirth={child.dateOfBirth}
          onChange={(dateOfBirth) => onChange({ dateOfBirth })}
          spokenDate={`Child ${position} date of birth`}
          spokenAge={`Child ${position} age`}
          typedAgeField={
            <NumberField
              label="Age"
              spokenAs={`Child ${position} age`}
              value={child.age}
              onChangeText={(age) => onChange({ age })}
              placeholder="0"
            />
          }
        />
        <PillField
          label="Gender"
          spokenAs={`Child ${position} gender`}
          value={child.gender}
          options={genderOptions}
          onChange={(gender) => onChange({ gender })}
        />
        <YesNoField
          question="Practices Kṛṣṇa consciousness?"
          spokenAs={`Child ${position} practices Kṛṣṇa consciousness?`}
          value={child.practices}
          onChange={(practices) => onChange({ practices })}
        >
          <TextField
            label="Since when?"
            spokenAs={`Child ${position} practising since`}
            value={child.practicingSince}
            onChangeText={(practicingSince) => onChange({ practicingSince })}
            placeholder="From birth, 2019, three years…"
            autoCapitalize="sentences"
          />
        </YesNoField>
        <YesNoField
          question="Initiated?"
          spokenAs={`Child ${position} initiated?`}
          value={child.initiated}
          onChange={(initiated) => onChange({ initiated })}
        >
          <OptionalDateField
            label="Date of initiation"
            spokenAs={`Child ${position} date of initiation`}
            value={child.initiationDate}
            onChange={(initiationDate) => onChange({ initiationDate })}
          />
          <TextField
            label="Diksha guru"
            spokenAs={`Child ${position} diksha guru`}
            value={child.dikshaGuru}
            onChangeText={(dikshaGuru) => onChange({ dikshaGuru })}
            placeholder="Their initiating spiritual master"
          />
        </YesNoField>
      </View>
    </View>
  );
}

/**
 * The photo card and the sheet it opens. Shared with the screen that asks a new
 * devotee for their photo, so the picking, the guidelines and the wording are
 * the same in both places rather than two versions drifting apart.
 *
 * The upload happens the moment a photo is picked, so it is never lost by
 * leaving without pressing Save. `required` is for the sign-up gate, where
 * offering to remove the photo would only put the devotee back behind it.
 */
export function ProfilePhotoPicker({
  userId,
  name,
  photoUrl,
  required = false,
}: {
  userId: string | null;
  name: string;
  photoUrl: string | null;
  required?: boolean;
}) {
  const updatePhoto = useUpdateDevoteePhoto(userId);
  const removePhoto = useRemoveDevoteePhoto(userId);
  const [sheetOpen, setSheetOpen] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const busy = updatePhoto.isPending || removePhoto.isPending;
  const canRemove = Boolean(photoUrl) && !required;

  const runChange = (source: "library" | "camera") => {
    setError(null);
    updatePhoto.mutate(source, {
      // A null result means the devotee backed out of the picker, so the
      // sheet stays open for them to choose again.
      onSuccess: (result) => {
        if (result !== null) setSheetOpen(false);
      },
      onError: (problem) =>
        setError(
          problem instanceof Error
            ? problem.message
            : "That photo could not be saved.",
        ),
    });
  };

  const runRemove = () => {
    setError(null);
    removePhoto.mutate(undefined, {
      onSuccess: () => setSheetOpen(false),
      onError: (problem) =>
        setError(
          problem instanceof Error
            ? problem.message
            : "That photo could not be removed.",
        ),
    });
  };

  return (
    <View className="rounded-card border border-border bg-white p-card">
      <View className="flex-row items-center">
        <Avatar name={name} photoUrl={photoUrl} tone="marigold" size="large" />
        <View className="ml-4 min-w-0 flex-1">
          <Text className="font-sans-bold text-base text-stone">
            Profile photo
          </Text>
          <Text className="mt-1 font-sans text-sm leading-5 text-stoneMuted">
            A clear face helps devotees recognise you at the temple.
          </Text>
        </View>
      </View>

      <Pressable
        className="mt-4 min-h-touch items-center justify-center rounded-button border border-border bg-white"
        accessibilityRole="button"
        accessibilityLabel={
          photoUrl ? "Change your profile photo" : "Add a profile photo"
        }
        disabled={busy}
        onPress={() => {
          setError(null);
          setSheetOpen(true);
        }}
      >
        <Text className="font-sans-bold text-base text-indigo">
          {busy ? "Uploading…" : photoUrl ? "Change photo" : "Add a photo"}
        </Text>
      </Pressable>

      {canRemove ? (
        <Pressable
          className="mt-2 min-h-touch items-center justify-center rounded-button"
          accessibilityRole="button"
          accessibilityLabel="Remove your profile photo"
          disabled={busy}
          onPress={runRemove}
        >
          <Text className="font-sans-bold text-base text-vermilion">
            Remove photo
          </Text>
        </Pressable>
      ) : null}

      {/* Shown on the card as well as in the sheet: a removal can fail with the
          sheet already closed, and an error nobody sees is a tap that silently
          did nothing. */}
      {error && !sheetOpen ? <FormError message={error} /> : null}

      <Modal
        visible={sheetOpen}
        transparent
        animationType="slide"
        onRequestClose={() => setSheetOpen(false)}
      >
        <Pressable
          className="flex-1 justify-end bg-stone/60"
          accessibilityRole="button"
          accessibilityLabel="Close photo options"
          onPress={() => setSheetOpen(false)}
        >
          {/* Swallows taps on the sheet itself so choosing an option does not
              close it through the backdrop underneath. */}
          <Pressable className="rounded-t-card bg-ivory px-screen pb-10 pt-5">
            <Text className="font-display text-2xl text-stone">
              Your profile photo
            </Text>
            <Text className="mt-1 font-sans text-sm leading-5 text-stoneMuted">
              A clear face helps devotees recognise you at the temple.
            </Text>

            <View className="mt-4 rounded-card border border-border bg-white p-card">
              {photoGuidelines.map((guideline) => (
                <View key={guideline} className="mb-2.5 flex-row last:mb-0">
                  <Ionicons
                    name="checkmark-circle"
                    size={18}
                    color={tokens.colors.peacock}
                  />
                  <Text className="ml-2.5 flex-1 font-sans text-sm leading-5 text-stone">
                    {guideline}
                  </Text>
                </View>
              ))}
            </View>

            {error ? (
              <View className="mt-4">
                <FormError message={error} />
              </View>
            ) : null}

            <View className="mt-4 gap-3">
              <Button
                icon="camera-outline"
                disabled={busy}
                onPress={() => runChange("camera")}
              >
                {updatePhoto.isPending ? "Uploading…" : "Take a photo"}
              </Button>
              <Button
                variant="secondary"
                icon="images-outline"
                disabled={busy}
                onPress={() => runChange("library")}
              >
                {updatePhoto.isPending ? "Uploading…" : "Choose from library"}
              </Button>
              {canRemove ? (
                <Pressable
                  className="min-h-touch items-center justify-center rounded-button"
                  accessibilityRole="button"
                  accessibilityLabel="Remove your profile photo"
                  disabled={busy}
                  onPress={runRemove}
                >
                  <Text className="font-sans-bold text-base text-vermilion">
                    {removePhoto.isPending ? "Removing…" : "Remove photo"}
                  </Text>
                </Pressable>
              ) : null}
            </View>
          </Pressable>
        </Pressable>
      </Modal>
    </View>
  );
}

export function ProfileDetailsScreen({ navigation }: Props) {
  const activeUserId = usePrototypeSession((state) => state.activeUserId);
  const profileQuery = useCurrentAccessProfile(activeUserId);
  const updateProfile = useUpdateMyProfile(activeUserId);
  const updateExtras = useUpdateMyProfileExtras(activeUserId);
  const updateCommunity = useUpdateMyProfileCommunity(activeUserId);
  const requestEmailChange = useRequestEmailChange();
  const profile = profileQuery.data;

  const [name, setName] = useState("");
  const [phone, setPhone] = useState("");
  const [dateOfBirth, setDateOfBirth] = useState<Date | null>(null);
  const [birthPlace, setBirthPlace] = useState("");
  const [address, setAddress] = useState("");
  const [spiritualMentor, setSpiritualMentor] = useState("");
  const [isInitiated, setIsInitiated] = useState(false);
  const [initiationDate, setInitiationDate] = useState<Date | null>(null);
  const [dikshaGuru, setDikshaGuru] = useState("");
  const [hasFirstInitiation, setHasFirstInitiation] = useState(false);
  const [firstInitiationDate, setFirstInitiationDate] = useState<Date | null>(
    null,
  );
  const [firstDikshaGuru, setFirstDikshaGuru] = useState("");
  const [hasSecondInitiation, setHasSecondInitiation] = useState(false);
  const [secondInitiationDate, setSecondInitiationDate] = useState<Date | null>(
    null,
  );
  const [secondDikshaGuru, setSecondDikshaGuru] = useState("");
  const [gender, setGender] = useState<Gender>(null);
  const [occupation, setOccupation] = useState("");
  const [preferredLanguage, setPreferredLanguage] = useState("");
  const [languagesSpoken, setLanguagesSpoken] = useState("");
  const [maritalStatus, setMaritalStatus] = useState<MaritalStatus>(null);
  const [spouseName, setSpouseName] = useState("");
  const [childrenCount, setChildrenCount] = useState("");
  const [childDrafts, setChildDrafts] = useState<ChildDraft[]>([]);
  const [chantingRounds, setChantingRounds] = useState("");
  const [howTheyFoundUs, setHowTheyFoundUs] = useState("");
  const [canOfferLift, setCanOfferLift] = useState(false);
  const [canHostPrograms, setCanHostPrograms] = useState(false);
  const [skills, setSkills] = useState("");
  const [templeSinceAmount, setTempleSinceAmount] = useState("");
  const [templeSinceUnit, setTempleSinceUnit] =
    useState<TempleSinceUnit | null>(null);
  const [locating, setLocating] = useState(false);
  const [locationNote, setLocationNote] = useState<string | null>(null);
  const [emailOpen, setEmailOpen] = useState(false);
  const [newEmail, setNewEmail] = useState("");
  const [formError, setFormError] = useState<string | null>(null);

  // The profile is polled every few seconds; filling the form more than once
  // would overwrite whatever the devotee is part-way through typing.
  const filled = useRef(false);
  useEffect(() => {
    if (!profile || filled.current) return;
    filled.current = true;
    const details = profile.details;
    setName(profile.name);
    setPhone(profile.phone ?? "");
    setDateOfBirth(keyToDate(details.date_of_birth));
    setBirthPlace(details.birth_place ?? "");
    setAddress(details.address ?? "");
    setSpiritualMentor(details.spiritual_mentor ?? "");
    setIsInitiated(details.is_initiated);
    setInitiationDate(keyToDate(details.initiation_date));
    setDikshaGuru(details.diksha_guru ?? "");
    setHasFirstInitiation(details.has_first_initiation);
    setFirstInitiationDate(keyToDate(details.first_initiation_date));
    setFirstDikshaGuru(details.first_diksha_guru ?? "");
    setHasSecondInitiation(details.has_second_initiation);
    setSecondInitiationDate(keyToDate(details.second_initiation_date));
    setSecondDikshaGuru(details.second_diksha_guru ?? "");
    setGender(details.gender);
    setOccupation(details.occupation ?? "");
    setPreferredLanguage(details.preferred_language ?? "");
    setLanguagesSpoken(details.languages_spoken ?? "");
    setMaritalStatus(details.marital_status);
    setSpouseName(details.spouse_name ?? "");
    setChildrenCount(numberToField(details.children_count));
    // A count saved before any sub-form was filled in still opens that many
    // blank ones, so the answer is never quietly forgotten.
    const storedChildren = details.children.map((child) =>
      newChildDraft(child),
    );
    setChildDrafts(
      grownToFit(
        storedChildren,
        details.children_count ?? storedChildren.length,
      ),
    );
    setChantingRounds(numberToField(details.chanting_rounds));
    setHowTheyFoundUs(details.how_they_found_us ?? "");
    setCanOfferLift(details.can_offer_lift);
    setCanHostPrograms(details.can_host_programs);
    setSkills(details.skills ?? "");
    setTempleSinceAmount(numberToField(details.temple_since_amount));
    setTempleSinceUnit(details.temple_since_unit);
  }, [profile]);

  // How many sub-forms are shown, never more than the drafts that exist.
  const shownChildren = childDrafts.slice(
    0,
    Math.min(countOrNull(childrenCount) ?? 0, maxChildren),
  );

  const changeChildrenCount = (next: string) => {
    setChildrenCount(next);
    const wanted = countOrNull(next);
    if (wanted !== null) setChildDrafts((drafts) => grownToFit(drafts, wanted));
  };

  const changeChild = (id: string, patch: Partial<ChildDraft>) =>
    setChildDrafts((drafts) =>
      drafts.map((draft) => (draft.id === id ? { ...draft, ...patch } : draft)),
    );

  // Removing one child is also one child fewer, so the count follows rather
  // than leaving a blank sub-form to take its place.
  const removeChild = (id: string) => {
    setChildDrafts((drafts) => drafts.filter((draft) => draft.id !== id));
    setChildrenCount((current) => {
      const count = countOrNull(current);
      return count === null ? "" : String(Math.max(0, count - 1));
    });
  };

  const completion = Math.max(0, Math.min(100, profile?.completion ?? 0));
  const photoUrl = profile?.photo_url ?? null;
  const displayName = profile?.name ?? "Your account";

  // The geocoder can refuse, time out, or simply not know where this is. None
  // of those are worth an error screen: the field is left as it was to type.
  const useMyLocation = async () => {
    setLocationNote(null);
    setLocating(true);
    try {
      const found = await addressFromCurrentPosition();
      if (found) setAddress(found);
      else
        setLocationNote(
          "Your location could not be read. Please type your address instead.",
        );
    } catch {
      setLocationNote(
        "Your location could not be read. Please type your address instead.",
      );
    } finally {
      setLocating(false);
    }
  };

  const submit = async () => {
    setFormError(null);
    if (name.trim().length < 2) {
      setFormError("Please enter your full name.");
      return;
    }

    const rounds = countOrNull(chantingRounds);
    if (rounds !== null && rounds > maxChantingRounds) {
      setFormError(
        `Please enter chanting rounds between 0 and ${maxChantingRounds}.`,
      );
      return;
    }

    const children = countOrNull(childrenCount);
    if (children !== null && children > maxChildren) {
      setFormError(
        `Please enter a number of children between 0 and ${maxChildren}.`,
      );
      return;
    }

    const childDetails: ChildDetail[] = shownChildren.map((draft) => ({
      name: draft.name.trim(),
      // A date of birth is the more exact answer, so it wins where there is
      // one. It is not stored itself — `users.children` has no room for it —
      // so the age it gives is the whole of what the temple keeps.
      age: draft.dateOfBirth
        ? ageInYears(draft.dateOfBirth)
        : countOrNull(draft.age),
      gender: draft.gender,
      practices: draft.practices,
      practicing_since: draft.practices
        ? trimmedOrNull(draft.practicingSince)
        : null,
      initiated: draft.initiated,
      // Sent cleared rather than left behind, as the devotee's own initiation
      // is: the database drops these anyway when the answer is no.
      initiation_date:
        draft.initiated && draft.initiationDate
          ? dateToKey(draft.initiationDate)
          : null,
      diksha_guru: draft.initiated ? trimmedOrNull(draft.dikshaGuru) : null,
    }));

    // The emergency, prasadam and health answers no longer have a form, but
    // the extras function writes every column it is handed, so whatever the
    // temple already holds is sent back untouched instead of being blanked by
    // an unrelated save.
    const stored = profile?.details;

    // One Save, three functions. They are run together and reported on
    // together, so a devotee is never told everything saved when part of it
    // did not.
    const results = await Promise.allSettled([
      updateProfile.mutateAsync({
        name: name.trim(),
        phone: trimmedOrNull(phone),
        dateOfBirth: dateOfBirth ? dateToKey(dateOfBirth) : null,
        birthPlace: trimmedOrNull(birthPlace),
        address: trimmedOrNull(address),
        spiritualMentor: trimmedOrNull(spiritualMentor),
        isInitiated,
        initiationDate: initiationDate ? dateToKey(initiationDate) : null,
        dikshaGuru: trimmedOrNull(dikshaGuru),
        hasFirstInitiation,
        firstInitiationDate: firstInitiationDate
          ? dateToKey(firstInitiationDate)
          : null,
        firstDikshaGuru: trimmedOrNull(firstDikshaGuru),
        hasSecondInitiation,
        secondInitiationDate: secondInitiationDate
          ? dateToKey(secondInitiationDate)
          : null,
        secondDikshaGuru: trimmedOrNull(secondDikshaGuru),
      }),
      updateExtras.mutateAsync({
        emergencyContactName: stored?.emergency_contact_name ?? null,
        emergencyContactPhone: stored?.emergency_contact_phone ?? null,
        dietaryNotes: stored?.dietary_notes ?? null,
        healthNotes: stored?.health_notes ?? null,
        preferredLanguage: trimmedOrNull(preferredLanguage),
        occupation: trimmedOrNull(occupation),
        joinedTempleOn: stored?.joined_temple_on ?? null,
        templeSinceAmount: countOrNull(templeSinceAmount),
        templeSinceUnit,
      }),
      updateCommunity.mutateAsync({
        gender,
        maritalStatus,
        spouseName:
          maritalStatus === "married" ? trimmedOrNull(spouseName) : null,
        childrenCount: children,
        children: childDetails,
        chantingRounds: rounds,
        languagesSpoken: trimmedOrNull(languagesSpoken),
        howTheyFoundUs: trimmedOrNull(howTheyFoundUs),
        canOfferLift,
        canHostPrograms,
        skills: trimmedOrNull(skills),
      }),
    ]);

    const partNames = [
      "your name and spiritual details",
      "your profession, language and temple details",
      "your family and community details",
    ];
    const failures = results.flatMap((result, index) =>
      result.status === "rejected"
        ? [{ part: partNames[index], reason: result.reason as unknown }]
        : [],
    );

    if (failures.length) {
      const reason =
        errorMessage(failures[0].reason, "Please try again.") ??
        "Please try again.";
      setFormError(
        `Not everything could be saved — ${joinParts(
          failures.map((failure) => failure.part),
        )} did not go through. ${reason}`,
      );
      return;
    }

    navigation.goBack();
  };

  const sendEmailChange = () => {
    setFormError(null);
    const candidate = newEmail.trim();
    if (!candidate.includes("@") || candidate.length < 5) {
      setFormError("Please enter a complete email address.");
      return;
    }
    requestEmailChange.mutate(candidate);
  };

  const saving =
    updateProfile.isPending ||
    updateExtras.isPending ||
    updateCommunity.isPending;

  const error =
    formError ??
    errorMessage(updateProfile.error, "Your details could not be saved.") ??
    errorMessage(
      requestEmailChange.error,
      "The verification email could not be sent.",
    );

  return (
    <Screen topInset={false}>
      <ScreenTitle eyebrow="Your details">About you</ScreenTitle>

      <Text className="mb-section font-sans text-base leading-6 text-stoneMuted">
        Please share a little about yourself, so the temple knows you and you
        know us. It helps us welcome you properly and serve you better.
      </Text>

      <View
        className="mb-section rounded-card border border-border bg-white p-card"
        accessibilityLabel={`Your profile is ${completion} percent complete`}
      >
        <View className="flex-row items-center justify-between">
          <Text className="font-sans-bold text-base text-stone">
            Profile complete
          </Text>
          <Text className="font-sans-bold text-base text-peacock">
            {completion}%
          </Text>
        </View>
        <View className="mt-2.5 h-2 overflow-hidden rounded-pill bg-peacockSoft">
          <View
            className="h-full rounded-pill bg-peacock"
            style={{ width: `${completion}%` }}
          />
        </View>
        <Text className="mt-2 font-sans text-sm leading-5 text-stoneMuted">
          This updates once your details are saved.
        </Text>
      </View>

      <View className="mb-section">
        <ProfilePhotoPicker
          userId={activeUserId}
          name={displayName}
          photoUrl={photoUrl}
        />
      </View>

      <SectionHeader title="Personal details" />
      <View className="gap-3">
        <TextField
          label="Full name"
          value={name}
          onChangeText={setName}
          placeholder="The name devotees know you by"
        />
        <PillField
          label="Gender"
          value={gender}
          options={genderOptions}
          onChange={setGender}
          hint="Shown to other devotees, so they know how to address you."
        />
        <BirthDateRow dateOfBirth={dateOfBirth} onChange={setDateOfBirth} />
        <PlaceField
          label="Birth place"
          value={birthPlace}
          onChangeText={setBirthPlace}
          placeholder="City and country"
        />
        <PlaceField
          label="Address"
          value={address}
          onChangeText={setAddress}
          placeholder="Where post can reach you"
          multiline
        >
          <View>
            <Pressable
              className="mt-1.5 min-h-10 flex-row items-center"
              accessibilityRole="button"
              accessibilityLabel="Use my current location as my address"
              disabled={locating}
              onPress={() => void useMyLocation()}
            >
              <Ionicons
                name="locate-outline"
                size={18}
                color={tokens.colors.indigo}
              />
              <Text className="ml-2 font-sans-bold text-sm text-indigo">
                {locating ? "Finding you…" : "Use my location"}
              </Text>
            </Pressable>
            {locationNote ? (
              <Text className="font-sans text-sm leading-5 text-stoneMuted">
                {locationNote}
              </Text>
            ) : null}
          </View>
        </PlaceField>
        <TextField
          label="Phone number"
          value={phone}
          onChangeText={setPhone}
          placeholder="So the temple can reach you"
          keyboardType="phone-pad"
          autoCapitalize="none"
        />
        <TextField
          label="Profession"
          value={occupation}
          onChangeText={setOccupation}
          placeholder="What you do for a living"
        />
        <TextField
          label="Preferred language"
          value={preferredLanguage}
          onChangeText={setPreferredLanguage}
          placeholder="The language you are most at ease in"
        />
        <TextField
          label="Languages spoken"
          value={languagesSpoken}
          onChangeText={setLanguagesSpoken}
          placeholder="Hindi, Gujarati, English…"
        />
      </View>

      <View className="mt-section">
        <SectionHeader title="Email" />
        <View className="rounded-card border border-border bg-white p-card">
          <Text className="font-sans-bold text-base text-stone">
            {profile?.email ?? "Loading…"}
          </Text>
          <Text className="mt-1 font-sans text-sm leading-5 text-stoneMuted">
            This is the address you sign in with. It only changes once you
            confirm the new one, so your account cannot be pointed at an inbox
            you do not own.
          </Text>

          {emailOpen ? (
            <View className="mt-3 gap-3">
              <TextInput
                className="min-h-touch rounded-button border border-border bg-ivory px-4 font-sans text-base text-stone"
                value={newEmail}
                onChangeText={setNewEmail}
                placeholder="New email address"
                placeholderTextColor={tokens.colors.stoneMuted}
                keyboardType="email-address"
                autoCapitalize="none"
                autoCorrect={false}
                accessibilityLabel="New email address"
              />
              <View className="flex-row gap-3">
                <Pressable
                  className="min-h-touch flex-1 items-center justify-center rounded-button border border-border bg-white"
                  accessibilityRole="button"
                  accessibilityLabel="Cancel the email change"
                  onPress={() => {
                    setEmailOpen(false);
                    setNewEmail("");
                    requestEmailChange.reset();
                  }}
                >
                  <Text className="font-sans-bold text-base text-indigo">
                    Cancel
                  </Text>
                </Pressable>
                <Pressable
                  className="min-h-touch flex-1 items-center justify-center rounded-button bg-indigo"
                  accessibilityRole="button"
                  accessibilityLabel="Send the verification email"
                  disabled={requestEmailChange.isPending}
                  onPress={sendEmailChange}
                >
                  <Text className="font-sans-bold text-base text-white">
                    {requestEmailChange.isPending
                      ? "Sending…"
                      : "Send verification"}
                  </Text>
                </Pressable>
              </View>
            </View>
          ) : (
            <Pressable
              className="mt-3 min-h-touch items-center justify-center rounded-button border border-border bg-white"
              accessibilityRole="button"
              accessibilityLabel="Change your email address"
              onPress={() => {
                setNewEmail("");
                requestEmailChange.reset();
                setEmailOpen(true);
              }}
            >
              <Text className="font-sans-bold text-base text-indigo">
                Change email
              </Text>
            </Pressable>
          )}

          {requestEmailChange.isSuccess ? (
            <View className="mt-3 flex-row rounded-button border border-peacock bg-peacockSoft px-4 py-3">
              <Ionicons
                name="mail-open-outline"
                size={20}
                color={tokens.colors.peacock}
              />
              <Text className="ml-3 flex-1 font-sans text-sm leading-5 text-peacock">
                Check your new inbox and tap the link to confirm the change.
              </Text>
            </View>
          ) : null}
        </View>
      </View>

      <View className="mt-section">
        <SectionHeader title="Family" />
        <View className="gap-3">
          <PillField
            label="Marital status"
            value={maritalStatus}
            options={maritalStatusOptions}
            onChange={setMaritalStatus}
          />
          {maritalStatus === "married" ? (
            <TextField
              label="Spouse’s name"
              value={spouseName}
              onChangeText={setSpouseName}
              placeholder="The devotee you are married to"
            />
          ) : null}
          <NumberField
            label="Children"
            value={childrenCount}
            onChangeText={changeChildrenCount}
            placeholder="0"
          />
          {shownChildren.map((child, index) => (
            <ChildForm
              key={child.id}
              position={index + 1}
              child={child}
              onChange={(patch) => changeChild(child.id, patch)}
              onRemove={() => removeChild(child.id)}
            />
          ))}
        </View>
      </View>

      <View className="mt-section">
        <SectionHeader
          title="Spiritual life"
          subtitle="Knowing where you are in your practice lets us offer you weekly seva that suits it."
        />
        <View className="gap-3">
          <NumberField
            label="Chanting rounds a day"
            value={chantingRounds}
            onChangeText={setChantingRounds}
            placeholder="16"
            hint={`Your own practice, never a requirement for seva. Up to ${maxChantingRounds}.`}
          />
          <TextField
            label="Spiritual mentor"
            value={spiritualMentor}
            onChangeText={setSpiritualMentor}
            placeholder="The devotee guiding your practice"
          />

          <YesNoField
            question="Are you initiated?"
            value={isInitiated}
            onChange={setIsInitiated}
          >
            <OptionalDateField
              label="Date of initiation"
              value={initiationDate}
              onChange={setInitiationDate}
            />
            <TextField
              label="Diksha guru"
              value={dikshaGuru}
              onChangeText={setDikshaGuru}
              placeholder="Your initiating spiritual master"
            />
          </YesNoField>

          <YesNoField
            question="Have you taken first initiation?"
            value={hasFirstInitiation}
            onChange={setHasFirstInitiation}
          >
            <OptionalDateField
              label="First initiation date"
              value={firstInitiationDate}
              onChange={setFirstInitiationDate}
            />
            <TextField
              label="First diksha guru"
              value={firstDikshaGuru}
              onChangeText={setFirstDikshaGuru}
              placeholder="Who gave first initiation"
            />
          </YesNoField>

          <YesNoField
            question="Have you taken second initiation?"
            value={hasSecondInitiation}
            onChange={setHasSecondInitiation}
          >
            <OptionalDateField
              label="Second initiation date"
              value={secondInitiationDate}
              onChange={setSecondInitiationDate}
            />
            <TextField
              label="Second diksha guru"
              value={secondDikshaGuru}
              onChangeText={setSecondDikshaGuru}
              placeholder="Who gave second initiation"
            />
          </YesNoField>
        </View>
      </View>

      <View className="mt-section">
        <SectionHeader title="Temple life" />
        <View className="gap-3">
          <NumberField
            label="Since when have you been coming to the temple?"
            value={templeSinceAmount}
            onChangeText={setTempleSinceAmount}
            placeholder="6"
          />
          <PillField
            label="Counted in"
            value={templeSinceUnit}
            options={templeSinceUnitOptions}
            onChange={setTempleSinceUnit}
          />
          <TextField
            label="How you found us"
            value={howTheyFoundUs}
            onChangeText={setHowTheyFoundUs}
            placeholder="A friend, a festival, walking past…"
            autoCapitalize="sentences"
          />
          <YesNoField
            question="Can you give other devotees a lift to the temple?"
            value={canOfferLift}
            onChange={setCanOfferLift}
          />
          <YesNoField
            question="Are you open to be a host family?"
            value={canHostPrograms}
            onChange={setCanHostPrograms}
          />
          <TextField
            label="Skills you can offer"
            value={skills}
            onChangeText={setSkills}
            placeholder="Cooking, kirtan, accounts, teaching…"
            multiline
            autoCapitalize="sentences"
          />
        </View>
      </View>

      {error ? <FormError message={error} /> : null}

      <View className="mt-section">
        <Button
          icon="checkmark-circle-outline"
          disabled={saving || profileQuery.isLoading}
          onPress={() => void submit()}
        >
          {saving ? "Saving…" : "Save my details"}
        </Button>
      </View>
    </Screen>
  );
}
