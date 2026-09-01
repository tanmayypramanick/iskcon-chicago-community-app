import { Ionicons } from "@expo/vector-icons";
import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import { useEffect, useState } from "react";
import { Alert, Pressable, Text, TextInput, View } from "react-native";

import tokens from "../../design-tokens.json";
import { Button, InitialAvatar, Screen, SectionHeader } from "../components/ui";
import { useCurrentAccessProfile } from "../features/access/hooks";
import { hasAccessPermission } from "../features/access/model";
import { registrationInstanceIds } from "../features/services/registrations";
import {
  ClashWarningSheet,
  FormError,
  ServingList,
} from "../features/services/components";
import {
  clashWarningMessage,
  clashWarningTitle,
  windowEnd,
} from "../features/services/clashes";
import {
  servedParticipants,
  servingParticipants,
  unconfirmedAssignmentIds,
} from "../features/services/selectors";
import {
  errorMessage,
  formatDuration,
  hasServiceFinished,
  hasServiceStarted,
  formatServiceDate,
  formatServiceTime,
} from "../features/services/format";
import {
  useCompleteService,
  useCompleteMyServiceAssignment,
  useRecordSevaAttendance,
  useDeleteServiceRequirement,
  useJoinService,
  useLeaveService,
  useOfferService,
  useRespondToServiceOffer,
  useServiceDashboard,
  useClashGate,
  useSevaClashes,
} from "../features/services/hooks";
import type { ServicesStackParamList } from "../navigation/types";
import { useNow } from "../lib/useNow";
import { usePrototypeSession } from "../store/usePrototypeSession";

type Props = NativeStackScreenProps<ServicesStackParamList, "ServiceDetail">;

function initials(name: string) {
  return name
    .split(/\s+/)
    .slice(0, 2)
    .map((part) => part[0]?.toUpperCase())
    .join("");
}

export function ServiceDetailScreen({ navigation, route }: Props) {
  const activeUserId = usePrototypeSession((state) => state.activeUserId);
  const previewRole = usePrototypeSession((state) => state.previewRole);
  const profile = useCurrentAccessProfile(activeUserId);
  const dashboard = useServiceDashboard(activeUserId);
  const [devoteeSearch, setDevoteeSearch] = useState("");
  const [showAllDevotees, setShowAllDevotees] = useState(false);
  const joinService = useJoinService();
  const leaveService = useLeaveService();
  const offerService = useOfferService();
  const respondToOffer = useRespondToServiceOffer();
  const completeService = useCompleteService();
  const completeMyAssignment = useCompleteMyServiceAssignment();
  const recordAttendance = useRecordSevaAttendance();
  const deleteRequirement = useDeleteServiceRequirement();
  // Ticking, not captured: a seva that starts in five minutes has to gain its
  // completion controls where the devotee is already standing, without a pull
  // to refresh. Nothing else on this screen re-renders at that instant.
  const now = useNow();
  const service = dashboard.data?.services.find(
    (item) => item.id === route.params.serviceId,
  );
  const actualRole = profile.data?.role ?? "devotee";
  const effectiveRole = __DEV__ && previewRole ? previewRole : actualRole;
  const canOffer = hasAccessPermission(
    effectiveRole,
    "services.offer_assignment",
  );
  // 0023: closing a seva request belongs to whoever posted it, plus the two
  // levels that override anything.
  /**
   * A seva the devotee only REGISTERED is not a seva they close out.
   *
   * Approving a self-added or logged seva creates its instance with posted_by
   * = the devotee (202608040025), so the "did you post this?" test says yes to
   * them for their own seva and handed them the coordinator's controls over
   * it. The temple's rule is the other way round: whoever posted a seva says
   * whether it was served, and a devotee just serves. A self-added seva has no
   * "mark served" step at all — the member who was asked to verify it settles
   * it.
   *
   * The server refuses the write either way (202608310095); this is so the
   * controls are not offered.
   */
  const isMyRegistration = Boolean(
    service &&
      dashboard.data &&
      registrationInstanceIds(dashboard.data).has(service.id),
  );
  const canCloseThisSeva = Boolean(
    service &&
      !isMyRegistration &&
      (service.posted_by === activeUserId ||
        hasAccessPermission(effectiveRole, "app.view_all")),
  );
  /**
   * Two instants, two different questions.
   *
   * Completion is gated on the seva being OVER. The temple: "after the seva has
   * been done and the time has passed, only then can anyone mark this seva
   * completed." Gating on the start let a 9:00–10:00 seva be marked completed
   * at 9:01, with an hour of it still to happen. The server is being brought to
   * the same line, so anything offered earlier is a button the RPC refuses.
   *
   * Attendance is gated on the seva having BEGUN, and stays there on purpose:
   * whoever is running it marks devotees in as they arrive, and "Seva happening
   * now" reads those marks to say who is actually in the kitchen. Making it
   * wait for the end would leave the temple unable to record anything while the
   * seva it is recording is going on.
   */
  const hasStarted = Boolean(service && hasServiceStarted(service, now));
  const hasFinished = Boolean(service && hasServiceFinished(service, now));
  const canCompleteWholeService = canCloseThisSeva && hasFinished;
  const canRecordAttendance = Boolean(
    service && canCloseThisSeva && hasStarted &&
      servingParticipants(service).length > 0,
  );
  const canDeleteRequirement = Boolean(
    service &&
      (service.posted_by === activeUserId ||
        hasAccessPermission(effectiveRole, "services.delete_any")),
  );
  const mutationError =
    joinService.error ??
    leaveService.error ??
    offerService.error ??
    respondToOffer.error ??
    completeService.error ??
    completeMyAssignment.error ??
    // An attendance mark shows before the server has agreed to it, so a
    // rejection has to say so — the row silently reverting looks like a bug.
    recordAttendance.error ??
    deleteRequirement.error;

  /**
   * Whether this devotee is already down for something over these hours. Asked
   * for the seva they are looking at, so it is ready whether they answer an
   * invitation or simply join.
   */
  const myClashes = useSevaClashes(
    service && activeUserId
      ? {
          devoteeId: activeUserId,
          date: service.date,
          startTime: service.start_time,
          durationMinutes: service.duration_minutes,
          // Without this a devotee already on this seva is told it clashes
          // with itself.
          excludeInstanceId: service.id,
        }
      : null,
    // Nothing to warn about on a seva that can no longer be joined or
    // accepted, so the question is not put at all.
    //
    // A waiting invitation counts as "can still be accepted" whatever the
    // status says. `respond_to_service_offer` takes `open` and `full` alike, so
    // a devotee invited to a seva that filled up and then had somebody stand
    // down can still say yes — and with the question never asked, `myClashes`
    // was empty and they said yes to an hour they were already committed for.
    // The identical offer on the Seva tab has always warned them.
    service?.status === "open" || Boolean(service?.currentUserOffer),
  );
  const [ownPrompt, setOwnPrompt] = useState<"accept" | "join" | null>(null);
  useEffect(() => {
    if (ownPrompt && !myClashes.length) setOwnPrompt(null);
  }, [myClashes.length, ownPrompt]);

  // Asking somebody else is one question about one devotee, put when the
  // coordinator picks them rather than about every name in the list.
  const askGate = useClashGate(({ devoteeId }) =>
    offerService.mutate({ instanceId: route.params.serviceId, devoteeId }),
  );

  const ownWording = {
    audience: "self" as const,
    startTime: service?.start_time ?? "00:00:00",
    durationMinutes: service?.duration_minutes ?? 0,
  };
  const askWording = {
    audience: "other" as const,
    devoteeName: askGate.warning?.target.name,
    startTime: service?.start_time ?? "00:00:00",
    durationMinutes: service?.duration_minutes ?? 0,
  };

  if (dashboard.isLoading || !service) {
    return (
      <Screen topInset={false}>
        <Text className="font-sans text-base text-stoneMuted">
          {dashboard.isLoading
            ? "Loading service details…"
            : "This service could not be found."}
        </Text>
      </Screen>
    );
  }

  const canJoin =
    service.status === "open" &&
    (service.participation_mode === "open" || canOffer || service.posted_by === activeUserId) &&
    !service.currentUserAssignment;
  const canLeave =
    Boolean(
      service.currentUserAssignment &&
        ["assigned", "confirmed"].includes(service.currentUserAssignment.status),
    ) &&
    !["completed", "cancelled"].includes(service.status);
  const holdsAPlace = Boolean(
    service.currentUserAssignment &&
    ["assigned", "confirmed"].includes(service.currentUserAssignment.status) &&
    !["completed", "cancelled"].includes(service.status),
  );
  const canCompleteOwnAssignment = holdsAPlace && hasFinished;
  // Said only to the devotee who is actually waiting for the button, so the
  // absence of a control reads as "not yet" rather than as a missing feature.
  const awaitingEnd = holdsAPlace && !hasFinished;
  const endsAt = windowEnd(service.start_time, service.duration_minutes);
  const isRecurringAssignment = Boolean(
    service.template_id && service.currentUserAssignment,
  );
  // Whoever is serving right now. A devotee who stood down is not on this list
  // and so may be asked again, which is the whole point of a swap.
  const serving = servingParticipants(service);
  // Who it counted for. The roster above stays whole — a coordinator has to see
  // an absent devotee to change their mind about them — but anything that says
  // how much seva happened is counted from this.
  const served = servedParticipants(service);
  const unmarked = unconfirmedAssignmentIds(service).length;
  const availableDevotees = (dashboard.data?.devotees.filter(
      (devotee) =>
        !serving.some(
          (participant) => participant.devotee.id === devotee.id,
        ) && `${devotee.name} ${devotee.role_name}`.toLocaleLowerCase().includes(devoteeSearch.trim().toLocaleLowerCase()),
    ) ?? []).sort((left, right) => {
      if (left.id === activeUserId) return -1;
      if (right.id === activeUserId) return 1;
      return left.name.localeCompare(right.name);
    });
  const visibleDevotees = showAllDevotees || devoteeSearch.trim()
    ? availableDevotees
    : availableDevotees.slice(0, 6);

  // Both of the devotee's own ways onto this seva go through the same warning,
  // and neither is ever stopped by it.
  const acceptInvitation = () => {
    const offerId = service.currentUserOffer?.id;
    if (!offerId) return;
    if (myClashes.length) {
      setOwnPrompt("accept");
      return;
    }
    respondToOffer.mutate({ offerId, accept: true });
  };
  const joinThisSeva = () => {
    if (myClashes.length) {
      setOwnPrompt("join");
      return;
    }
    joinService.mutate(service.id);
  };

  return (
    <Screen topInset={false}>
      <View className="rounded-card bg-indigo p-card">
        <View className="flex-row items-center justify-between">
          <View className="rounded-pill bg-white/15 px-3 py-1.5">
            <Text className="font-sans-bold text-xs uppercase tracking-wider text-marigoldSoft">
              {service.status}
            </Text>
          </View>
          <Ionicons name="heart" size={23} color={tokens.colors.marigoldSoft} />
        </View>
        <Text className="mt-4 font-display text-[28px] leading-9 text-white">
          {service.name}
        </Text>
        <View className="mt-4 flex-row items-center">
          <Ionicons
            name="calendar-outline"
            size={20}
            color={tokens.colors.white}
          />
          <Text className="ml-2 font-sans text-base text-white">
            {formatServiceDate(service.date)} ·{" "}
            {formatServiceTime(service.start_time)}
          </Text>
        </View>
        <View className="mt-2 flex-row items-center">
          <Ionicons name="time-outline" size={20} color={tokens.colors.white} />
          <Text className="ml-2 font-sans text-base text-white">
            {formatDuration(service.duration_minutes)}
          </Text>
        </View>
        {/* The card carries only name, when and hours now, so the facts that
            used to sit beside them there are said here instead. */}
        {/* Places filled is a fact about the roster and reads as one until the
            seva is over, at which point the only interesting number is how
            many devotees actually served — "3 of 3 places filled" on a seva
            one of them was marked absent for is the app insisting otherwise. */}
        <Text className="mt-4 font-sans-bold text-sm text-marigoldSoft">
          {service.status === "completed"
            ? `${served.length} of ${service.slots_needed} served`
            : `${service.filledSlots} of ${service.slots_needed} places filled`}
          {service.participation_mode === "invite_only"
            ? " · Invited devotees only"
            : " · Open to everyone"}
        </Text>
        {service.template_id ? (
          <Text className="mt-1 font-sans text-sm text-white">
            One date of a weekly seva.
          </Text>
        ) : null}
        {service.pendingInvitees?.length ? (
          <Text className="mt-1 font-sans text-sm text-white">
            Waiting on{" "}
            {service.pendingInvitees.map((devotee) => devotee.name).join(", ")}
            {" "}to answer.
          </Text>
        ) : null}
      </View>

      {service.currentUserOffer ? (
        <View className="mt-section rounded-card border border-marigold bg-white p-card">
          <Text className="font-display text-xl text-stone">Can you help?</Text>
          <Text className="mt-2 font-sans text-base leading-6 text-stoneMuted">
            A coordinator invited you to take this service.
          </Text>
          <View className="mt-4 flex-row gap-3">
            <Pressable
              className="min-h-touch flex-1 items-center justify-center rounded-button border border-border"
              accessibilityRole="button"
              onPress={() =>
                respondToOffer.mutate({
                  offerId: service.currentUserOffer!.id,
                  accept: false,
                })
              }
            >
              <Text className="font-sans-bold text-base text-stoneMuted">
                Not available
              </Text>
            </Pressable>
            <Pressable
              className="min-h-touch flex-1 items-center justify-center rounded-button bg-peacock"
              accessibilityRole="button"
              onPress={acceptInvitation}
            >
              <Text className="font-sans-bold text-base text-white">
                Accept seva
              </Text>
            </Pressable>
          </View>
        </View>
      ) : null}

      {/* One list, not two. Who is serving and what happened to each of them
          is the same question asked of the same people, and splitting it made
          a coordinator scroll between a name and its answer. */}
      <View className="mt-section">
        <SectionHeader
          title="Serving together"
          subtitle={
            canRecordAttendance
              ? unmarked
                ? `${unmarked} of ${serving.length} still to mark. Recording this keeps the temple's history honest.`
                : "Everyone is marked."
              : undefined
          }
        />
        {serving.length ? (
          <ServingList
            participants={serving}
            currentUserId={activeUserId}
            canRecord={canRecordAttendance}
            onRecord={(assignmentId, attendance) =>
              recordAttendance.mutate({ assignmentId, attendance })
            }
          />
        ) : (
          <View className="rounded-card border border-border bg-white p-card">
            <Text className="font-sans text-base text-stoneMuted">
              No one has joined yet. The first offering can be yours.
            </Text>
          </View>
        )}
      </View>

      {canJoin ? (
        <View className="mt-section">
          <Button
            icon="hand-left-outline"
            disabled={joinService.isPending}
            onPress={joinThisSeva}
          >
            {joinService.isPending ? "Joining…" : "Join this service"}
          </Button>
        </View>
      ) : null}
      {canLeave && isRecurringAssignment ? (
        <View className="mt-3">
          <Button
            variant="secondary"
            icon="calendar-clear-outline"
            onPress={() =>
              navigation.navigate("ReportUnavailable", {
                serviceId: service.id,
              })
            }
          >
            I can’t make this occurrence
          </Button>
        </View>
      ) : null}
      {canLeave && !isRecurringAssignment ? (
        <View className="mt-3">
          <Button
            variant="secondary"
            icon="exit-outline"
            disabled={leaveService.isPending}
            onPress={() => leaveService.mutate(service.id)}
          >
            {leaveService.isPending ? "Updating…" : "Leave this service"}
          </Button>
        </View>
      ) : null}

      {canCompleteOwnAssignment ? (
        <View className="mt-3">
          <Button
            icon="checkmark-circle-outline"
            disabled={completeMyAssignment.isPending}
            onPress={() => completeMyAssignment.mutate(service.id)}
          >
            {completeMyAssignment.isPending
              ? "Completing…"
              : "Mark my seva completed"}
          </Button>
        </View>
      ) : null}
      {awaitingEnd ? (
        <View className="mt-3 flex-row rounded-button border border-border bg-white px-4 py-3">
          <Ionicons
            name="time-outline"
            size={20}
            color={tokens.colors.stoneMuted}
          />
          <Text className="ml-3 flex-1 font-sans text-sm leading-5 text-stoneMuted">
            You can mark this seva completed once it is over, on{" "}
            {formatServiceDate(service.date)} at{" "}
            {formatServiceTime(endsAt.time)}
            {endsAt.nextDay ? " the next day" : ""}.
          </Text>
        </View>
      ) : null}

      {canOffer && service.status === "open" ? (
        <View className="mt-section">
          <SectionHeader title="Ask a devotee" />
          <Text className="mb-3 font-sans text-base leading-6 text-stoneMuted">
            You can assign yourself immediately. Everyone else receives an invitation and must accept before assignment.
          </Text>
          <View className="mb-2 flex-row items-center rounded-button border border-border bg-white px-4">
            <Ionicons name="search" size={19} color={tokens.colors.indigo} />
            <TextInput
              className="min-h-touch min-w-0 flex-1 px-3 font-sans text-base text-stone"
              value={devoteeSearch}
              onChangeText={setDevoteeSearch}
              placeholder="Search devotee by name"
              placeholderTextColor={tokens.colors.stoneMuted}
            />
          </View>
          <View className="overflow-hidden rounded-card border border-border bg-white">
            {visibleDevotees.map((devotee, index) => (
              <Pressable
                key={devotee.id}
                className={`min-h-[68px] flex-row items-center px-card ${
                  index < visibleDevotees.length - 1
                    ? "border-b border-border"
                    : ""
                }`}
                accessibilityRole="button"
                accessibilityLabel={`Ask ${devotee.name} to help`}
                disabled={
                  offerService.isPending ||
                  joinService.isPending ||
                  askGate.checking
                }
                onPress={() =>
                  devotee.id === activeUserId
                    ? joinThisSeva()
                    : askGate.ask({
                        name: devotee.name,
                        devoteeId: devotee.id,
                        date: service.date,
                        startTime: service.start_time,
                        durationMinutes: service.duration_minutes,
                        excludeInstanceId: service.id,
                      })
                }
              >
                <InitialAvatar initials={initials(devotee.name)} size="small" />
                <Text className="ml-3 flex-1 font-sans-bold text-base text-stone">
                  {devotee.name}{devotee.id === activeUserId ? " (You)" : ""}
                </Text>
                <Ionicons
                  name={devotee.id === activeUserId ? "person-add-outline" : "paper-plane-outline"}
                  size={21}
                  color={tokens.colors.indigo}
                />
              </Pressable>
            ))}
          </View>
          {!devoteeSearch.trim() && availableDevotees.length > 6 ? (
            <Pressable className="mt-2 min-h-touch items-center justify-center rounded-button bg-indigoSoft" onPress={() => setShowAllDevotees((value) => !value)}>
              <Text className="font-sans-bold text-sm text-indigo">
                {showAllDevotees ? "Show fewer" : `See all ${availableDevotees.length} devotees`}
              </Text>
            </Pressable>
          ) : null}
        </View>
      ) : null}

      {canCompleteWholeService &&
      !["completed", "cancelled"].includes(service.status) ? (
        <View className="mt-section">
          <Button
            variant="secondary"
            icon="checkmark-done-outline"
            disabled={completeService.isPending}
            onPress={() => completeService.mutate(service.id)}
          >
            Complete entire service
          </Button>
        </View>
      ) : null}

      {canDeleteRequirement ? (
        <View className="mt-3">
          <Button
            variant="secondary"
            icon="trash-outline"
            disabled={deleteRequirement.isPending}
            onPress={() =>
              Alert.alert(
                "Remove this seva request?",
                "Its assignments and invitations will be permanently removed.",
                [
                  { text: "Keep", style: "cancel" },
                  {
                    text: "Remove",
                    style: "destructive",
                    onPress: () =>
                      deleteRequirement.mutate(service.id, {
                        onSuccess: () => navigation.goBack(),
                      }),
                  },
                ],
              )
            }
          >
            Remove seva request
          </Button>
        </View>
      ) : null}

      {mutationError ? (
        // `errorMessage`, never `instanceof Error`: Supabase hands back a
        // PostgrestError as a plain object, so the guard was always false and
        // every refusal the server took care to word — "A seva filled up
        // first", "This seva has not started yet" — was being replaced with
        // this screen's own generic sentence.
        <FormError
          message={
            errorMessage(mutationError, "The service could not be updated.") ??
            "The service could not be updated."
          }
        />
      ) : null}

      <ClashWarningSheet
        visible={Boolean(ownPrompt)}
        title={clashWarningTitle(ownWording)}
        message={clashWarningMessage(ownWording, myClashes)}
        proceedLabel={ownPrompt === "join" ? "Join anyway" : "Accept anyway"}
        onProceed={() => {
          const answering = ownPrompt;
          setOwnPrompt(null);
          if (answering === "join") joinService.mutate(service.id);
          else if (service.currentUserOffer) {
            respondToOffer.mutate({
              offerId: service.currentUserOffer.id,
              accept: true,
            });
          }
        }}
        onClose={() => setOwnPrompt(null)}
        // Only an invitation can be answered with a different time; there is
        // nobody to answer when a devotee simply joins an open seva.
        alternative={
          ownPrompt === "accept" && service.currentUserOffer
            ? {
                label: "I am available another time",
                onPress: () => {
                  const offerId = service.currentUserOffer!.id;
                  setOwnPrompt(null);
                  navigation.navigate("ProposeServiceTime", { offerId });
                },
              }
            : undefined
        }
      />

      <ClashWarningSheet
        visible={Boolean(askGate.warning)}
        title={clashWarningTitle(askWording)}
        message={clashWarningMessage(askWording, askGate.warning?.clashes ?? [])}
        proceedLabel="Ask anyway"
        onProceed={askGate.accept}
        onClose={askGate.dismiss}
      />
    </Screen>
  );
}
