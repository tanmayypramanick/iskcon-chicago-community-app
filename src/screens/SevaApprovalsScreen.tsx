import { Ionicons } from "@expo/vector-icons";
import { useState } from "react";
import { Pressable, Text, TextInput, View } from "react-native";

import tokens from "../../design-tokens.json";
import { Avatar, Screen, ScreenTitle, SectionHeader } from "../components/ui";
import { hasAccessPermission } from "../features/access/model";
import { useCurrentAccessProfile } from "../features/access/hooks";
import { FormError } from "../features/services/components";
import {
  errorMessage,
  formatDuration,
  formatServiceTime,
  formatWeekdayList,
} from "../features/services/format";
import {
  useRespondToSevaVerification,
  useRespondToWeeklyOfferCounter,
  useServiceDashboard,
} from "../features/services/hooks";
import {
  formatChicagoShortDate,
  formatChicagoTime,
} from "../lib/chicagoDate";
import { usePrototypeSession } from "../store/usePrototypeSession";

/** Always the temple's clock, whatever zone the reviewing phone is set to. */
function formatWindow(startAt: string, endAt: string) {
  const start = new Date(startAt);
  const end = new Date(endAt);
  return `${formatChicagoShortDate(start)} · ${formatChicagoTime(start)} – ${formatChicagoTime(end)}`;
}

/**
 * One place for the decisions only a Community Head, Tech Admin or the
 * President can make: verifying a devotee's logged seva, and answering a
 * devotee who suggested different days for a weekly seva.
 */
export function SevaApprovalsScreen() {
  const activeUserId = usePrototypeSession((state) => state.activeUserId);
  const previewRole = usePrototypeSession((state) => state.previewRole);
  const profile = useCurrentAccessProfile(activeUserId);
  const dashboard = useServiceDashboard(activeUserId);
  const respondVerification = useRespondToSevaVerification();
  const respondCounter = useRespondToWeeklyOfferCounter();
  const [note, setNote] = useState("");

  const actualRole = profile.data?.role ?? "devotee";
  const effectiveRole = __DEV__ && previewRole ? previewRole : actualRole;
  const canManage = hasAccessPermission(
    effectiveRole,
    "services.manage_recurring",
  );

  // A Tech Admin or the President may verify anything, whoever the devotee
  // originally named. Everyone else sees only what was addressed to them.
  const canOverrideAnyone = hasAccessPermission(effectiveRole, "app.view_all");
  const verifications = (
    canOverrideAnyone
      ? (dashboard.data?.verifications ?? []).filter(
          (row) => row.status === "pending",
        )
      : (dashboard.data?.verificationInbox ?? [])
  ).filter(
    // Never your own. app.view_all reaches every registration in the temple
    // including the holder's, and the server refuses it — "your own seva has
    // to be verified by somebody else" — so leaving it in the list only offers
    // a Tech Admin or President two buttons that can do nothing but error.
    (row) => row.devotee_id !== activeUserId,
  );
  const counters = (dashboard.data?.offerCounters ?? []).filter(
    (counter) => counter.status === "pending",
  );
  const devoteeById = new Map(
    (dashboard.data?.devotees ?? []).map((devotee) => [devotee.id, devotee]),
  );

  const error =
    respondVerification.error instanceof Error
      ? respondVerification.error.message
      : errorMessage(respondCounter.error, "Something went wrong.");

  if (!canManage) {
    return (
      <Screen>
        <View className="items-center rounded-card border border-border bg-white px-card py-8">
          <Ionicons
            name="lock-closed-outline"
            size={28}
            color={tokens.colors.stoneMuted}
          />
          <Text className="mt-3 text-center font-sans-bold text-base text-stone">
            Community Head, Tech Admin, or President access is required.
          </Text>
        </View>
      </Screen>
    );
  }

  return (
    <Screen>
      <ScreenTitle eyebrow="Needs your decision">Seva approvals</ScreenTitle>

      {error ? <FormError message={error} /> : null}

      <SectionHeader title="Seva waiting to be verified" />
      {verifications.length ? (
        <View className="mb-section gap-3">
          {verifications.map((row) => (
            <View
              key={row.id}
              className="rounded-card border border-marigold bg-white p-card"
            >
              <View className="flex-row items-start">
                <Avatar
                  name={row.devotee?.name ?? "Devotee"}
                  photoUrl={row.devotee?.photo_url}
                  size="small"
                  tone="marigold"
                />
                <View className="ml-3 min-w-0 flex-1">
                  <Text className="font-display text-lg leading-6 text-stone">
                    {row.name}
                  </Text>
                  <Text className="mt-1 font-sans-bold text-sm text-indigo">
                    {row.devotee?.name ?? "A devotee"}
                  </Text>
                  <Text className="mt-1 font-sans text-sm text-stoneMuted">
                    {formatWindow(row.start_at, row.end_at)}
                  </Text>
                  {canOverrideAnyone && row.verifier_id !== activeUserId ? (
                    <Text className="mt-1 font-sans text-xs text-indigo">
                      Asked of {row.verifier?.name ?? "another member"} — you
                      can verify it anyway
                    </Text>
                  ) : null}
                  <Text className="mt-0.5 font-sans text-sm text-stoneMuted">
                    {row.location_text}
                  </Text>
                </View>
              </View>
              <View className="mt-4 flex-row gap-3">
                <Pressable
                  className="min-h-touch flex-1 items-center justify-center rounded-button border border-border"
                  accessibilityRole="button"
                  accessibilityLabel={`Decline ${row.name}`}
                  disabled={respondVerification.isPending}
                  onPress={() =>
                    respondVerification.mutate({
                      verificationId: row.id,
                      approve: false,
                      note: note.trim() || null,
                    })
                  }
                >
                  <Text className="font-sans-bold text-base text-stoneMuted">
                    Not verified
                  </Text>
                </Pressable>
                <Pressable
                  className="min-h-touch flex-1 items-center justify-center rounded-button bg-peacock"
                  accessibilityRole="button"
                  accessibilityLabel={`Verify ${row.name}`}
                  disabled={respondVerification.isPending}
                  onPress={() =>
                    respondVerification.mutate({
                      verificationId: row.id,
                      approve: true,
                      note: note.trim() || null,
                    })
                  }
                >
                  <Text className="font-sans-bold text-base text-white">
                    Verify seva
                  </Text>
                </Pressable>
              </View>
            </View>
          ))}
        </View>
      ) : (
        <View className="mb-section items-center rounded-card border border-border bg-white px-card py-7">
          <Ionicons
            name="checkmark-done-outline"
            size={28}
            color={tokens.colors.peacock}
          />
          <Text className="mt-2 text-center font-sans-bold text-base text-stone">
            Nothing waiting to be verified
          </Text>
        </View>
      )}

      <SectionHeader title="Suggested weekly times" />
      {counters.length ? (
        <View className="mb-section gap-3">
          {counters.map((counter) => {
            const devotee = devoteeById.get(counter.devotee_id);
            return (
              <View
                key={counter.id}
                className="rounded-card border border-indigo bg-white p-card"
              >
                <View className="flex-row items-start">
                  <Avatar
                    name={devotee?.name ?? "Devotee"}
                    photoUrl={devotee?.photo_url}
                    size="small"
                  />
                  <View className="ml-3 min-w-0 flex-1">
                    <Text className="font-sans-bold text-base text-stone">
                      {devotee?.name ?? "A devotee"}
                    </Text>
                    <Text className="mt-1 font-sans text-sm leading-5 text-stoneMuted">
                      Cannot serve as invited. They suggested{" "}
                      <Text className="font-sans-bold text-indigo">
                        {formatWeekdayList(counter.proposed_days)}
                      </Text>{" "}
                      at {formatServiceTime(counter.proposed_start_time)} for{" "}
                      {formatDuration(counter.proposed_duration_minutes)}.
                    </Text>
                    {counter.note ? (
                      <Text className="mt-2 font-sans text-sm italic leading-5 text-stoneMuted">
                        “{counter.note}”
                      </Text>
                    ) : null}
                  </View>
                </View>
                <Text className="mt-3 font-sans text-xs leading-4 text-stoneMuted">
                  Accepting records their availability and notifies them. You
                  then edit the weekly seva yourself.
                </Text>
                <View className="mt-3 flex-row gap-3">
                  <Pressable
                    className="min-h-touch flex-1 items-center justify-center rounded-button border border-border"
                    accessibilityRole="button"
                    accessibilityLabel="Decline suggested time"
                    disabled={respondCounter.isPending}
                    onPress={() =>
                      respondCounter.mutate({
                        counterId: counter.id,
                        approve: false,
                        note: note.trim() || null,
                      })
                    }
                  >
                    <Text className="font-sans-bold text-base text-stoneMuted">
                      Cannot use
                    </Text>
                  </Pressable>
                  <Pressable
                    className="min-h-touch flex-1 items-center justify-center rounded-button bg-indigo"
                    accessibilityRole="button"
                    accessibilityLabel="Accept suggested time"
                    disabled={respondCounter.isPending}
                    onPress={() =>
                      respondCounter.mutate({
                        counterId: counter.id,
                        approve: true,
                        note: note.trim() || null,
                      })
                    }
                  >
                    <Text className="font-sans-bold text-base text-white">
                      Accept time
                    </Text>
                  </Pressable>
                </View>
              </View>
            );
          })}
        </View>
      ) : (
        <View className="mb-section items-center rounded-card border border-border bg-white px-card py-7">
          <Ionicons
            name="calendar-outline"
            size={28}
            color={tokens.colors.peacock}
          />
          <Text className="mt-2 text-center font-sans-bold text-base text-stone">
            No suggested times to review
          </Text>
        </View>
      )}

      <SectionHeader title="Add a note (optional)" />
      <View className="min-h-touch justify-center rounded-button border border-border bg-white px-4">
        <TextInput
          className="py-3 font-sans text-base text-stone"
          accessibilityLabel="Note to send with your decision"
          placeholder="Sent with your decision"
          placeholderTextColor={tokens.colors.stoneMuted}
          value={note}
          onChangeText={setNote}
          multiline
        />
      </View>
    </Screen>
  );
}
