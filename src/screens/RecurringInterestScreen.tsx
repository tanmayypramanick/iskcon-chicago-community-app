import { Ionicons } from "@expo/vector-icons";
import { useEffect, useRef, useState } from "react";
import { Pressable, Switch, Text, TextInput, View } from "react-native";

import tokens from "../../design-tokens.json";
import { Button, Screen, SectionHeader } from "../components/ui";
import { FormError } from "../features/services/components";
import {
  useServiceDashboard,
  useSubmitRecurringServiceInterest,
} from "../features/services/hooks";
import { usePrototypeSession } from "../store/usePrototypeSession";

export function RecurringInterestScreen() {
  const activeUserId = usePrototypeSession((state) => state.activeUserId);
  const dashboard = useServiceDashboard(activeUserId);
  const submitInterest = useSubmitRecurringServiceInterest();
  const initialized = useRef(false);
  const [skills, setSkills] = useState("");
  const [availability, setAvailability] = useState("");
  const [desiredServiceTypeIds, setDesiredServiceTypeIds] = useState<string[]>(
    [],
  );
  const [otherService, setOtherService] = useState("");
  const [currentlyServing, setCurrentlyServing] = useState(false);
  const [currentServiceDetails, setCurrentServiceDetails] = useState("");
  const [formError, setFormError] = useState<string | null>(null);
  const ownInterest = dashboard.data?.recurringInterests.find(
    (interest) => interest.devotee_id === activeUserId,
  );

  useEffect(() => {
    if (!ownInterest || initialized.current) return;
    initialized.current = true;
    setSkills(ownInterest.skills);
    setAvailability(ownInterest.availability);
    setDesiredServiceTypeIds(ownInterest.desired_service_type_ids);
    setOtherService(ownInterest.other_service ?? "");
    setCurrentlyServing(ownInterest.currently_serving);
    setCurrentServiceDetails(ownInterest.current_service_details ?? "");
  }, [ownInterest]);

  const submit = () => {
    setFormError(null);
    if (skills.trim().length < 2) {
      setFormError("Please share the skills you can offer.");
      return;
    }
    if (availability.trim().length < 2) {
      setFormError("Please share when you are regularly available.");
      return;
    }
    if (
      !desiredServiceTypeIds.length &&
      otherService.trim().length < 2 &&
      !(currentlyServing && currentServiceDetails.trim().length >= 2)
    ) {
      setFormError("Choose a weekly seva or describe one.");
      return;
    }
    if (currentlyServing && currentServiceDetails.trim().length < 2) {
      setFormError("Please describe the weekly seva you already do.");
      return;
    }

    submitInterest.mutate({
      skills: skills.trim(),
      desiredServiceTypeIds,
      otherService: otherService.trim() || null,
      availability: availability.trim(),
      currentlyServing,
      currentServiceDetails:
        currentlyServing && currentServiceDetails.trim()
          ? currentServiceDetails.trim()
          : null,
    });
  };

  const error =
    formError ??
    (submitInterest.error instanceof Error
      ? submitInterest.error.message
      : submitInterest.error
        ? "Your weekly-seva profile could not be submitted."
        : null);

  return (
    <Screen topInset={false}>
      {ownInterest ? (
        <View
          className={`mb-section flex-row items-center rounded-card border p-card ${
            ownInterest.status === "approved"
              ? "border-peacock bg-peacockSoft"
              : ownInterest.status === "denied"
                ? "border-vermilion bg-white"
                : "border-marigold bg-marigoldSoft"
          }`}
        >
          <View className="h-10 w-10 items-center justify-center rounded-pill bg-white">
            <Ionicons
              name={
                ownInterest.status === "approved"
                  ? "shield-checkmark"
                  : ownInterest.status === "denied"
                    ? "refresh"
                    : "time"
              }
              size={20}
              color={
                ownInterest.status === "denied"
                  ? tokens.colors.vermilion
                  : tokens.colors.peacock
              }
            />
          </View>
          <View className="ml-3 min-w-0 flex-1">
            <Text className="font-sans-bold text-base capitalize text-stone">
              {ownInterest.status === "approved"
                ? "Verified weekly-seva profile"
                : `${ownInterest.status} review`}
            </Text>
            <Text className="mt-0.5 font-sans text-sm text-stoneMuted">
              {ownInterest.status === "approved"
                ? "Coordinators can now use these details when arranging seva."
                : ownInterest.status === "pending"
                  ? "Core, Tech, or President will review these details."
                  : ownInterest.review_note ||
                    "Update the details and resubmit."}
            </Text>
          </View>
        </View>
      ) : null}

      <Text className="font-display text-xl text-stone">
        Offer your gifts in steady seva
      </Text>
      <Text className="mb-section mt-1 font-sans text-sm leading-5 text-stoneMuted">
        This profile helps coordinators understand your skills and availability.
        It never assigns you without a separate invitation and your acceptance.
      </Text>

      <SectionHeader title="Skills you can offer" />
      <TextInput
        className="min-h-[94px] rounded-card border border-border bg-white px-4 py-3 font-sans text-base text-stone"
        multiline
        textAlignVertical="top"
        placeholder="Cooking, organizing, welcoming guests, flowers, music…"
        placeholderTextColor={tokens.colors.stoneMuted}
        value={skills}
        onChangeText={setSkills}
      />

      <View className="mt-section">
        <SectionHeader title="Weekly seva you’re interested in" />
        <View className="flex-row flex-wrap gap-2">
          {(dashboard.data?.serviceTypes ?? []).map((serviceType) => {
            const selected = desiredServiceTypeIds.includes(serviceType.id);
            return (
              <Pressable
                key={serviceType.id}
                className={`rounded-pill border px-3 py-2 ${
                  selected
                    ? "border-indigo bg-indigo"
                    : "border-border bg-white"
                }`}
                accessibilityRole="checkbox"
                accessibilityState={{ checked: selected }}
                onPress={() =>
                  setDesiredServiceTypeIds((current) =>
                    selected
                      ? current.filter((id) => id !== serviceType.id)
                      : [...current, serviceType.id],
                  )
                }
              >
                <Text
                  className={`font-sans-bold text-sm ${
                    selected ? "text-white" : "text-stone"
                  }`}
                >
                  {serviceType.name}
                </Text>
              </Pressable>
            );
          })}
        </View>
        <TextInput
          className="mt-3 rounded-button border border-border bg-white px-4 py-3 font-sans text-base text-stone"
          placeholder="Something else you would love to offer"
          placeholderTextColor={tokens.colors.stoneMuted}
          value={otherService}
          onChangeText={setOtherService}
        />
      </View>

      <View className="mt-section">
        <SectionHeader title="Regular availability" />
        <TextInput
          className="min-h-[82px] rounded-card border border-border bg-white px-4 py-3 font-sans text-base text-stone"
          multiline
          textAlignVertical="top"
          placeholder="For example: Thursdays after 5 PM and Sunday mornings"
          placeholderTextColor={tokens.colors.stoneMuted}
          value={availability}
          onChangeText={setAvailability}
        />
      </View>

      <View className="mt-section rounded-card border border-border bg-white p-card">
        <View className="flex-row items-center">
          <View className="min-w-0 flex-1 pr-3">
            <Text className="font-sans-bold text-base text-stone">
              I already do weekly seva
            </Text>
            <Text className="mt-1 font-sans text-sm text-stoneMuted">
              Share it so the temple schedule can be verified.
            </Text>
          </View>
          <Switch
            value={currentlyServing}
            onValueChange={setCurrentlyServing}
            trackColor={{
              false: tokens.colors.indigoSoft,
              true: tokens.colors.peacock,
            }}
            thumbColor={tokens.colors.white}
          />
        </View>
        {currentlyServing ? (
          <TextInput
            className="mt-3 min-h-[78px] rounded-button border border-border bg-ivory px-4 py-3 font-sans text-base text-stone"
            multiline
            textAlignVertical="top"
            placeholder="What seva, which day, and what time?"
            placeholderTextColor={tokens.colors.stoneMuted}
            value={currentServiceDetails}
            onChangeText={setCurrentServiceDetails}
          />
        ) : null}
      </View>

      {error ? <FormError message={error} /> : null}
      <View className="mt-section">
        <Button
          icon="paper-plane-outline"
          disabled={submitInterest.isPending || dashboard.isLoading}
          onPress={submit}
        >
          {submitInterest.isPending
            ? "Submitting…"
            : ownInterest
              ? "Update and submit for review"
              : "Submit for verification"}
        </Button>
      </View>
    </Screen>
  );
}
