import { Ionicons } from "@expo/vector-icons";
import { useEffect, useRef, useState } from "react";
import { KeyboardAvoidingView, Platform, Pressable, Text, View } from "react-native";

import tokens from "../../design-tokens.json";
import { Button, Screen, ScreenTitle, SectionHeader } from "../components/ui";
import {
  missingRequiredProfileFields,
  requiredProfileFieldLabels,
  type ProfileCommunityInput,
  type RequiredProfileField,
} from "../features/access/api";
import {
  useCurrentAccessProfile,
  useUpdateMyProfile,
  useUpdateMyProfileCommunity,
  useUpdateMyProfileExtras,
} from "../features/access/hooks";
import { FormError } from "../features/services/components";
import { dateToKey, errorMessage } from "../features/services/format";
import { usePrototypeSession } from "../store/usePrototypeSession";
import {
  BirthDateRow,
  genderOptions,
  keyToDate,
  PillField,
  ProfilePhotoPicker,
  TextField,
  trimmedOrNull,
} from "./ProfileDetailsScreen";

type Gender = ProfileCommunityInput["gender"];

function namesOf(fields: RequiredProfileField[]) {
  return fields
    .map((field) => requiredProfileFieldLabels[field].toLowerCase())
    .join(", ");
}

/** Why the temple asks, in the words it would use at the door. */
const reasons = [
  {
    icon: "people-outline",
    text: "Your photo and name let devotees recognise you and greet you by name.",
  },
  {
    icon: "call-outline",
    text: "Your number is how the temple reaches you about the seva you take on.",
  },
  {
    icon: "gift-outline",
    text: "Your birthday, work and how to address you help us welcome you properly.",
  },
] as const;

/**
 * Asked once, of a devotee whose account is new. The rest of the profile stays
 * optional and lives on the full details screen; these six are the ones the
 * temple cannot run its congregation without, so the app waits for them.
 *
 * The screen never decides for itself that it is done. It saves, asks the
 * server again, and the gate that put it here re-reads the same answer.
 */
export function CompleteProfileScreen({
  missing,
  onSignOut,
}: {
  missing: RequiredProfileField[];
  onSignOut: () => void;
}) {
  const activeUserId = usePrototypeSession((state) => state.activeUserId);
  const profileQuery = useCurrentAccessProfile(activeUserId);
  const updateProfile = useUpdateMyProfile(activeUserId);
  const updateExtras = useUpdateMyProfileExtras(activeUserId);
  const updateCommunity = useUpdateMyProfileCommunity(activeUserId);
  const profile = profileQuery.data;

  const [name, setName] = useState("");
  const [phone, setPhone] = useState("");
  const [dateOfBirth, setDateOfBirth] = useState<Date | null>(null);
  const [occupation, setOccupation] = useState("");
  const [gender, setGender] = useState<Gender>(null);
  const [formError, setFormError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  // The profile is polled every few seconds; filling the form more than once
  // would overwrite whatever the devotee is part-way through typing.
  const filled = useRef(false);
  useEffect(() => {
    if (!profile || filled.current) return;
    filled.current = true;
    // A Google sign-in already carries a name, and someone sent back here for
    // one missing answer should not have to retype the five they gave.
    setName(profile.name);
    setPhone(profile.phone ?? "");
    setDateOfBirth(keyToDate(profile.details.date_of_birth));
    setOccupation(profile.details.occupation ?? "");
    setGender(profile.details.gender);
  }, [profile]);

  const photoUrl = profile?.photo_url ?? null;

  const submit = async () => {
    setFormError(null);
    if (!photoUrl) {
      setFormError("Please add a profile photo.");
      return;
    }
    if (name.trim().length < 2) {
      setFormError("Please enter your full name.");
      return;
    }
    if (phone.replace(/[^0-9]/g, "").length < 7) {
      setFormError("Please enter a phone number the temple can reach you on.");
      return;
    }
    if (!dateOfBirth) {
      setFormError("Please give your date of birth.");
      return;
    }
    if (!occupation.trim()) {
      setFormError("Please tell us what you do.");
      return;
    }
    if (!gender) {
      setFormError("Please choose how you would like to be addressed.");
      return;
    }

    // Six answers, three functions — name and birthday, profession, gender.
    // Everything the temple already holds is handed back untouched, so filling
    // these in can never blank a detail given on the full profile screen.
    const stored = profile?.details;
    setSaving(true);
    try {
      await updateProfile.mutateAsync({
        name: name.trim(),
        phone: trimmedOrNull(phone),
        dateOfBirth: dateToKey(dateOfBirth),
        birthPlace: stored?.birth_place ?? null,
        address: stored?.address ?? null,
        spiritualMentor: stored?.spiritual_mentor ?? null,
        isInitiated: stored?.is_initiated ?? false,
        initiationDate: stored?.initiation_date ?? null,
        dikshaGuru: stored?.diksha_guru ?? null,
        hasFirstInitiation: stored?.has_first_initiation ?? false,
        firstInitiationDate: stored?.first_initiation_date ?? null,
        firstDikshaGuru: stored?.first_diksha_guru ?? null,
        hasSecondInitiation: stored?.has_second_initiation ?? false,
        secondInitiationDate: stored?.second_initiation_date ?? null,
        secondDikshaGuru: stored?.second_diksha_guru ?? null,
      });
      await updateExtras.mutateAsync({
        emergencyContactName: stored?.emergency_contact_name ?? null,
        emergencyContactPhone: stored?.emergency_contact_phone ?? null,
        dietaryNotes: stored?.dietary_notes ?? null,
        healthNotes: stored?.health_notes ?? null,
        preferredLanguage: stored?.preferred_language ?? null,
        occupation: occupation.trim(),
        joinedTempleOn: stored?.joined_temple_on ?? null,
        templeSinceAmount: stored?.temple_since_amount ?? null,
        templeSinceUnit: stored?.temple_since_unit ?? null,
      });
      await updateCommunity.mutateAsync({
        gender,
        maritalStatus: stored?.marital_status ?? null,
        spouseName: stored?.spouse_name ?? null,
        childrenCount: stored?.children_count ?? null,
        children: stored?.children ?? [],
        chantingRounds: stored?.chanting_rounds ?? null,
        languagesSpoken: stored?.languages_spoken ?? null,
        howTheyFoundUs: stored?.how_they_found_us ?? null,
        canOfferLift: stored?.can_offer_lift ?? false,
        canHostPrograms: stored?.can_host_programs ?? false,
        skills: stored?.skills ?? null,
      });
    } catch (error) {
      setFormError(
        errorMessage(error, "Your details could not be saved.") ??
          "Your details could not be saved.",
      );
      setSaving(false);
      return;
    }

    // The extras and community functions treat a version of themselves that is
    // not deployed as a quiet success, so a save that "worked" is not proof the
    // answers landed. The gate re-reads the server either way; this asks the
    // same question first so a devotee who cannot get past it is told why
    // instead of pressing Save at a door that will not open.
    const refreshed = await profileQuery.refetch();
    setSaving(false);

    if (refreshed.isError || !refreshed.data) {
      setFormError(
        "Your details were saved, but the temple could not be reached to confirm it. This will settle itself once you are connected again.",
      );
      return;
    }

    const stillMissing = missingRequiredProfileFields(refreshed.data);
    if (stillMissing.length) {
      setFormError(
        `Saved, but the temple still has no ${namesOf(stillMissing)}. Its database may not be up to date — please let the temple know.`,
      );
    }
  };

  return (
    <KeyboardAvoidingView
      className="flex-1"
      // Android resizes the window for the keyboard on its own; on iOS the
      // fields at the bottom of this form would sit underneath it.
      behavior={Platform.OS === "ios" ? "padding" : undefined}
    >
      {/* The default bottom padding is what keeps the sign-out link clear of
          the home indicator: there is no tab bar under this screen to do it. */}
      <Screen>
        <ScreenTitle eyebrow="Welcome">A little about you</ScreenTitle>

        <Text className="mb-section font-sans text-base leading-6 text-stoneMuted">
          Hare Krsna. Before you come in, the temple asks six things — no more.
          Everything else on your profile is yours to fill in whenever you like.
        </Text>

        <View className="mb-section rounded-card border border-border bg-white p-card">
          {reasons.map((reason) => (
            <View key={reason.text} className="mb-3 flex-row last:mb-0">
              <Ionicons
                name={reason.icon}
                size={19}
                color={tokens.colors.peacock}
              />
              <Text className="ml-3 flex-1 font-sans text-sm leading-5 text-stone">
                {reason.text}
              </Text>
            </View>
          ))}
        </View>

        <ProfilePhotoPicker
          userId={activeUserId}
          name={name.trim() || profile?.name || "Your account"}
          photoUrl={photoUrl}
          required
        />

        <View className="mt-section">
          <SectionHeader title="Your details" />
          <View className="gap-3">
            <TextField
              label="Full name"
              value={name}
              onChangeText={setName}
              placeholder="The name devotees know you by"
            />
            <TextField
              label="Contact number"
              value={phone}
              onChangeText={setPhone}
              placeholder="So the temple can reach you"
              keyboardType="phone-pad"
              autoCapitalize="none"
            />
            <BirthDateRow dateOfBirth={dateOfBirth} onChange={setDateOfBirth} />
            <TextField
              label="Profession"
              value={occupation}
              onChangeText={setOccupation}
              placeholder="What you do for a living"
            />
            <PillField
              label="Gender"
              value={gender}
              options={genderOptions}
              onChange={setGender}
              hint="Shown to other devotees, so they know how to address you."
            />
          </View>
        </View>

        {formError ? <FormError message={formError} /> : null}

        {/* What the temple holds, not what is typed above — and named rather
            than counted, because "two more" leaves a devotee hunting for which
            two. */}
        <Text className="mt-4 font-sans text-sm leading-5 text-stoneMuted">
          Not on your profile yet: {namesOf(missing)}.
        </Text>

        <View className="mt-section">
          <Button
            icon="checkmark-circle-outline"
            disabled={saving || profileQuery.isLoading}
            onPress={() => void submit()}
          >
            {saving ? "Saving…" : "Save and continue"}
          </Button>
        </View>

        <Pressable
          className="mt-4 min-h-touch items-center justify-center rounded-button"
          accessibilityRole="button"
          accessibilityLabel="Sign out"
          onPress={onSignOut}
        >
          <Text className="font-sans-bold text-base text-indigo">
            Sign out instead
          </Text>
        </Pressable>
      </Screen>
    </KeyboardAvoidingView>
  );
}
