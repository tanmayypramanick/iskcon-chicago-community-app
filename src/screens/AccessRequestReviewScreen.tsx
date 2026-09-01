import { Ionicons } from "@expo/vector-icons";
import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import { useEffect, useState } from "react";
import { Text, TextInput, View } from "react-native";

import tokens from "../../design-tokens.json";
import {
  Avatar,
  Button,
  Screen,
  ScreenTitle,
  SectionHeader,
} from "../components/ui";
import {
  useCurrentAccessProfile,
  useDevoteeProfiles,
  useMyAccessRequests,
  usePendingAccessRequests,
  useReviewAccessRequest,
} from "../features/access/hooks";
import {
  accessRoleLabels,
  hasAccessPermission,
} from "../features/access/model";
import { FormError } from "../features/services/components";
import { errorMessage } from "../features/services/format";
import { formatChicagoLongDateTime } from "../lib/chicagoDate";
import type { ProfileStackParamList } from "../navigation/types";
import { usePrototypeSession } from "../store/usePrototypeSession";

/**
 * The route entry belongs to ProfileStackParamList; intersecting it here keeps
 * this screen typed while that entry lands with the navigator wiring.
 */
type Props = NativeStackScreenProps<
  ProfileStackParamList & { AccessRequestReview: { requestId: string } },
  "AccessRequestReview"
>;

/**
 * One access request, opened. The pending list can only say who asked for what;
 * the decision rests on why they asked, so this screen exists to show that in
 * full alongside the two buttons that answer it.
 */
export function AccessRequestReviewScreen({ navigation, route }: Props) {
  const { requestId } = route.params;
  const activeUserId = usePrototypeSession((state) => state.activeUserId);
  const profile = useCurrentAccessProfile(activeUserId);
  const role = profile.data?.role ?? "devotee";
  const hasReviewPermission = hasAccessPermission(
    role,
    "access.review_requests",
  );

  const pendingRequests = usePendingAccessRequests(activeUserId);
  // `list_my_access_requests` returns every row to a reviewer, and it is the
  // only source that carries the devotee's message.
  const requestRows = useMyAccessRequests(activeUserId);
  const devotees = useDevoteeProfiles(hasReviewPermission);
  const review = useReviewAccessRequest(activeUserId);

  // The devotee this request NAMED may answer it, whatever their role.
  // answer_access_request has always accepted `approver_id = auth.uid()`, and
  // create_access_request notifies exactly that devotee — so a Community Head
  // was being sent a notification that opened a screen telling them they were
  // not allowed. The permission is the other way in, not the only way in.
  const wasAskedPersonally = (pendingRequests.data ?? []).some(
    (item) => item.id === requestId && item.approverId === activeUserId,
  );
  const mayReview = hasReviewPermission || wasAskedPersonally;

  const [note, setNote] = useState("");

  useEffect(() => {
    if (review.isSuccess) navigation.goBack();
  }, [navigation, review.isSuccess]);

  if (!mayReview) {
    return (
      <Screen topInset={false}>
        <View className="items-center rounded-card border border-border bg-white px-card py-10">
          <Ionicons
            name="lock-closed-outline"
            size={28}
            color={tokens.colors.indigo}
          />
          <Text className="mt-3 text-center font-sans-bold text-base text-stone">
            {profile.isLoading
              ? "Loading your access…"
              : "Only the devotee this request was sent to, a Tech Admin, or the President can answer it."}
          </Text>
        </View>
      </Screen>
    );
  }

  const request = pendingRequests.data?.find((item) => item.id === requestId);
  const row = requestRows.data?.find((item) => item.id === requestId);
  const requester = devotees.data?.find(
    (person) => person.id === request?.requesterId,
  );

  if (!request) {
    return (
      <Screen topInset={false}>
        <View className="items-center rounded-card border border-border bg-white px-card py-10">
          <Ionicons
            name="mail-open-outline"
            size={28}
            color={tokens.colors.indigo}
          />
          <Text className="mt-3 text-center font-sans-bold text-base text-stone">
            {pendingRequests.isLoading
              ? "Loading this request…"
              : "This request has already been answered"}
          </Text>
        </View>
      </Screen>
    );
  }

  const decide = (decision: "approved" | "denied") =>
    review.mutate({ requestId, decision, note: note.trim() || null });

  // Both buttons are disabled while a decision is in flight, so the one being
  // saved has to say so or the tap looks like it did nothing.
  const savingDecision = review.isPending ? review.variables.decision : null;

  return (
    <Screen topInset={false}>
      <ScreenTitle eyebrow="Access request">
        {request.requesterName}
      </ScreenTitle>

      <View className="mb-section flex-row items-center rounded-card border border-border bg-white p-card">
        <Avatar
          name={request.requesterName}
          photoUrl={requester?.photo_url}
          size="large"
          tone="peacock"
        />
        <View className="ml-4 min-w-0 flex-1">
          <Text className="font-sans text-sm text-stoneMuted">Asking for</Text>
          <Text className="font-sans-bold text-lg text-stone">
            {accessRoleLabels[request.requestedRole]} access
          </Text>
          <Text className="mt-1.5 font-sans text-sm leading-5 text-stoneMuted">
            Holds {accessRoleLabels[request.currentRole]} access today
          </Text>
        </View>
      </View>

      <SectionHeader title="Why they would like this access" />
      <View className="mb-section rounded-card border border-marigold bg-white p-card">
        <Ionicons
          name="chatbox-ellipses"
          size={20}
          color={tokens.colors.marigold}
        />
        <Text className="mt-2 font-sans text-base leading-6 text-stone">
          {row?.message?.trim() ||
            (requestRows.isLoading
              ? "Loading their message…"
              : "They did not leave a message.")}
        </Text>
        <Text className="mt-4 font-sans text-sm text-stoneMuted">
          Asked on {formatChicagoLongDateTime(new Date(request.createdAt))}
        </Text>
      </View>

      <SectionHeader
        title="Add a note"
        subtitle="Optional. They will see this with your decision."
      />
      <TextInput
        className="min-h-[88px] rounded-button border border-border bg-white px-4 py-3 font-sans text-base text-stone"
        value={note}
        onChangeText={setNote}
        placeholder="Optional — anything you want them to know"
        placeholderTextColor={tokens.colors.stoneMuted}
        multiline
        textAlignVertical="top"
        accessibilityLabel="A note to send with your decision"
      />

      {review.error ? (
        <View className="mt-3">
          <FormError
            message={
              errorMessage(
                review.error,
                "This request could not be reviewed.",
              ) ?? "This request could not be reviewed."
            }
          />
        </View>
      ) : null}

      <View className="mt-section flex-row gap-3">
        <View className="flex-1">
          <Button
            variant="secondary"
            disabled={review.isPending}
            onPress={() => decide("denied")}
          >
            {savingDecision === "denied" ? "Saving…" : "Decline"}
          </Button>
        </View>
        <View className="flex-1">
          <Button
            icon="shield-checkmark-outline"
            disabled={review.isPending}
            onPress={() => decide("approved")}
          >
            {savingDecision === "approved" ? "Saving…" : "Approve"}
          </Button>
        </View>
      </View>
    </Screen>
  );
}
