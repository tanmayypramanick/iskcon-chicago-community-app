import { Ionicons } from "@expo/vector-icons";
import { useState } from "react";
import { Pressable, Text, TextInput, View } from "react-native";

import tokens from "../../design-tokens.json";
import {
  Avatar,
  EmptyOrOffline,
  ListScreen,
  LoadFailure,
  Screen,
  ScreenTitle,
  SkeletonCard,
} from "../components/ui";
import { useCurrentAccessProfile } from "../features/access/hooks";
import { hasAccessPermission } from "../features/access/model";
import { usePendingSangas, useReviewSanga } from "../features/sanga/hooks";
import type { PendingSanga } from "../features/sanga/types";
import { FormError } from "../features/services/components";
import { errorMessage } from "../features/services/format";
import { formatChicagoShortDate } from "../lib/chicagoDate";
import { useServerReachable } from "../lib/connectivity";
import { usePrototypeSession } from "../store/usePrototypeSession";

function proposedLabel(sanga: PendingSanga) {
  const at = new Date(sanga.created_at);
  const who = sanga.created_by_name ?? "A devotee";
  if (Number.isNaN(at.getTime())) return `Proposed by ${who}`;
  return `Proposed by ${who} · ${formatChicagoShortDate(at)}`;
}

function PendingSangaCard({
  sanga,
  busy,
  declining,
  note,
  onNoteChange,
  onApprove,
  onStartDecline,
  onCancelDecline,
  onConfirmDecline,
}: {
  sanga: PendingSanga;
  busy: boolean;
  declining: boolean;
  note: string;
  onNoteChange: (value: string) => void;
  onApprove: () => void;
  onStartDecline: () => void;
  onCancelDecline: () => void;
  onConfirmDecline: () => void;
}) {
  return (
    <View className="mb-3 rounded-card border border-marigold bg-white p-card">
      <View className="flex-row items-start">
        <Avatar
          name={sanga.created_by_name ?? "Devotee"}
          photoUrl={sanga.created_by_photo_url}
          size="small"
          tone="marigold"
        />
        <View className="ml-3 min-w-0 flex-1">
          <Text
            className="font-display text-lg leading-6 text-stone"
            numberOfLines={3}
          >
            {sanga.name}
          </Text>
          <Text className="mt-1 font-sans text-sm text-stoneMuted">
            {proposedLabel(sanga)}
          </Text>
        </View>
      </View>

      <Text className="mt-3 font-sans text-sm leading-5 text-stone">
        {sanga.description?.trim() ||
          "The devotee did not describe this sanga."}
      </Text>

      {declining ? (
        // The second step. A decline is the one answer the devotee cannot undo
        // themselves, so it is never a single tap, and the reason travels with
        // it because "no" without one is what makes people ask again.
        <View className="mt-4 rounded-card border border-border bg-ivory p-card">
          <Text className="font-sans-bold text-base text-stone">
            Decline {sanga.name}?
          </Text>
          <Text className="mt-1 font-sans text-sm leading-5 text-stoneMuted">
            It will not open, and {sanga.created_by_name ?? "the devotee"} will
            see your answer.
          </Text>
          <View className="mt-3 min-h-touch justify-center rounded-button border border-border bg-white px-4">
            <TextInput
              className="py-3 font-sans text-base text-stone"
              accessibilityLabel={`Reason for declining ${sanga.name}`}
              maxLength={280}
              multiline
              placeholder="Optional reason for the devotee"
              placeholderTextColor={tokens.colors.stoneMuted}
              value={note}
              onChangeText={onNoteChange}
            />
          </View>
          <View className="mt-3 flex-row gap-3">
            <Pressable
              className="min-h-touch flex-1 items-center justify-center rounded-button border border-border bg-white px-3"
              accessibilityRole="button"
              accessibilityLabel={`Keep ${sanga.name} waiting`}
              disabled={busy}
              onPress={onCancelDecline}
            >
              <Text className="font-sans-bold text-base text-indigo">
                Keep waiting
              </Text>
            </Pressable>
            <Pressable
              className={`min-h-touch flex-1 items-center justify-center rounded-button bg-vermilion px-3 ${
                busy ? "opacity-60" : ""
              }`}
              accessibilityRole="button"
              accessibilityLabel={`Confirm declining ${sanga.name}`}
              disabled={busy}
              onPress={onConfirmDecline}
            >
              <Text className="font-sans-bold text-base text-white">
                Decline
              </Text>
            </Pressable>
          </View>
        </View>
      ) : (
        <View className="mt-4 flex-row gap-3">
          <Pressable
            className="min-h-touch flex-1 items-center justify-center rounded-button border border-border bg-white px-3"
            accessibilityRole="button"
            accessibilityLabel={`Decline ${sanga.name}`}
            disabled={busy}
            onPress={onStartDecline}
          >
            <Text className="font-sans-bold text-base text-vermilion">
              Decline
            </Text>
          </Pressable>
          <Pressable
            className={`min-h-touch flex-1 items-center justify-center rounded-button bg-peacock px-3 ${
              busy ? "opacity-60" : ""
            }`}
            accessibilityRole="button"
            accessibilityLabel={`Approve ${sanga.name}`}
            disabled={busy}
            onPress={onApprove}
          >
            <Text className="font-sans-bold text-base text-white">Approve</Text>
          </Pressable>
        </View>
      )}
    </View>
  );
}

/**
 * The one judgement the congregation wants from its President: whether the
 * temple has this sanga at all. Who is in it is the sanga admin's business,
 * and is answered on the sanga's own roll.
 */
export function SangaApprovalsScreen() {
  const activeUserId = usePrototypeSession((state) => state.activeUserId);
  const previewRole = usePrototypeSession((state) => state.previewRole);
  const profile = useCurrentAccessProfile(activeUserId);
  const reachable = useServerReachable();

  const actualRole = profile.data?.role ?? "devotee";
  const role = __DEV__ && previewRole ? previewRole : actualRole;
  const mayReview = hasAccessPermission(role, "app.view_all");

  const pending = usePendingSangas(mayReview);
  const review = useReviewSanga();
  const [decliningId, setDecliningId] = useState<string | null>(null);
  const [note, setNote] = useState("");
  const [actionError, setActionError] = useState<string | null>(null);

  if (!mayReview) {
    return (
      <Screen topInset={false}>
        <View className="items-center rounded-card border border-border bg-white px-card py-10">
          <Ionicons
            name="lock-closed-outline"
            size={28}
            color={tokens.colors.stoneMuted}
          />
          <Text className="mt-3 text-center font-sans-bold text-base text-stone">
            Tech Admin or President access is required.
          </Text>
        </View>
      </Screen>
    );
  }

  const rows = pending.data ?? [];
  const failed = pending.isError && pending.data === undefined;

  const decide = (sanga: PendingSanga, decision: "approved" | "declined") => {
    setActionError(null);
    review.mutate(
      {
        sangaId: sanga.id,
        decision,
        note: decision === "declined" ? note.trim() || null : null,
      },
      {
        onSuccess: () => {
          setDecliningId(null);
          setNote("");
        },
        onError: (caught) =>
          setActionError(
            errorMessage(caught, `${sanga.name} could not be answered.`),
          ),
      },
    );
  };

  return (
    <ListScreen
      topInset={false}
      data={rows}
      keyExtractor={(sanga) => sanga.id}
      header={
        <>
          <ScreenTitle eyebrow="Needs your decision">
            Sanga approvals
          </ScreenTitle>
          {actionError ? <FormError message={actionError} /> : null}
        </>
      }
      renderItem={(sanga) => (
        <PendingSangaCard
          sanga={sanga}
          busy={review.isPending && review.variables?.sangaId === sanga.id}
          declining={decliningId === sanga.id}
          note={note}
          onNoteChange={setNote}
          onApprove={() => decide(sanga, "approved")}
          onStartDecline={() => {
            setActionError(null);
            setNote("");
            setDecliningId(sanga.id);
          }}
          onCancelDecline={() => {
            setDecliningId(null);
            setNote("");
          }}
          onConfirmDecline={() => decide(sanga, "declined")}
        />
      )}
      empty={
        pending.isLoading ? (
          <SkeletonCard />
        ) : failed ? (
          <LoadFailure
            reachable={reachable}
            message={errorMessage(
              pending.error,
              "The waiting sangas could not be loaded.",
            )}
            onRetry={() => void pending.refetch()}
          />
        ) : (
          <EmptyOrOffline
            reachable={reachable}
            loading={false}
            empty={
              <View className="items-center rounded-card border border-border bg-white px-card py-9">
                <View className="h-14 w-14 items-center justify-center rounded-pill bg-peacockSoft">
                  <Ionicons
                    name="checkmark-done-outline"
                    size={26}
                    color={tokens.colors.peacock}
                  />
                </View>
                <Text className="mt-4 text-center font-display text-xl text-stone">
                  Nothing waiting
                </Text>
                <Text className="mt-2 max-w-80 text-center font-sans text-sm leading-6 text-stoneMuted">
                  When a devotee starts a sanga, it will wait here for your
                  answer.
                </Text>
              </View>
            }
          />
        )
      }
    />
  );
}
