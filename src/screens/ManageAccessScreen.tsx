import { Ionicons } from "@expo/vector-icons";
import { useMemo, useState } from "react";
import { Alert, Pressable, Text, TextInput, View } from "react-native";

import tokens from "../../design-tokens.json";
import { ModalScreen } from "../components/ModalScreen";
import {
  Avatar,
  Button,
  EmptyOrOffline,
  ListScreen,
  LoadFailure,
  Screen,
  ScreenTitle,
  SectionHeader,
  SkeletonCard,
} from "../components/ui";
import {
  useAccessAppointments,
  useAppointAccess,
  useMayAppointAccess,
  useRevokeAccess,
} from "../features/access/hooks";
import type { AccessAppointment } from "../features/access/api";
import {
  accessRoleLabels,
  grantableAccessRoles,
  grantableRoleSummaries,
  isAccessRole,
  type GrantableAccessRole,
} from "../features/access/model";
import { FormError } from "../features/services/components";
import { errorMessage } from "../features/services/format";
import { useServiceDashboard } from "../features/services/hooks";
import type { ServiceDevotee } from "../features/services/types";
import { formatChicagoShortDate } from "../lib/chicagoDate";
import { useServerReachable } from "../lib/connectivity";
import { usePrototypeSession } from "../store/usePrototypeSession";

/** Enough names to choose from without turning the picker into a directory. */
const MAX_CANDIDATES = 8;

function dayLabel(value: string) {
  const at = new Date(value);
  if (Number.isNaN(at.getTime())) return null;
  return formatChicagoShortDate(at);
}

function roleLabel(roleName: string) {
  return isAccessRole(roleName) ? accessRoleLabels[roleName] : roleName;
}

/**
 * Why the Revoke button is not on this row. A Community Head sees it on their
 * own appointees and nowhere else, and a button that is simply absent reads as
 * a bug rather than as a rule.
 */
function whyNotRevocable(grant: AccessAppointment, viewerId: string | null) {
  if (grant.devotee_id === viewerId) {
    return "This is your own access. Somebody else changes it.";
  }
  const appointer = grant.appointed_by_name?.trim();
  return appointer
    ? `${appointer} made this appointment, so only they, the President or a Tech Admin can take it back.`
    : "Nobody is recorded as having made this appointment, so only the President or a Tech Admin can take it back.";
}

function GrantRow({
  grant,
  viewerId,
  busy,
  onRevoke,
}: {
  grant: AccessAppointment;
  viewerId: string | null;
  busy: boolean;
  onRevoke: () => void;
}) {
  const appointed = dayLabel(grant.appointed_at);
  const by = grant.appointed_by_name?.trim();

  return (
    <View className="mt-3 rounded-card border border-border bg-white p-card">
      <View className="flex-row items-center">
        <Avatar
          name={grant.devotee_name}
          photoUrl={grant.devotee_photo_url}
          size="small"
          tone="peacock"
        />
        <View className="ml-3 min-w-0 flex-1">
          <Text
            className="font-sans-bold text-base text-stone"
            numberOfLines={1}
          >
            {grant.devotee_name}
          </Text>
          <Text className="font-sans text-xs leading-5 text-stoneMuted">
            {[
              by
                ? `Appointed by ${by}`
                : "Appointed before the app kept a record",
              appointed,
            ]
              .filter(Boolean)
              .join(" · ")}
          </Text>
        </View>
        <View className="ml-2 shrink-0 rounded-pill bg-indigoSoft px-3 py-1">
          <Text className="font-sans-bold text-xs text-indigo">
            {grant.role_label || roleLabel(grant.role_name)}
          </Text>
        </View>
      </View>

      {grant.note?.trim() ? (
        <Text className="mt-2 font-sans text-sm leading-5 text-stoneMuted">
          “{grant.note.trim()}”
        </Text>
      ) : null}

      {grant.can_revoke ? (
        <View className="mt-3 flex-row justify-end">
          <Pressable
            className={`min-h-10 flex-row items-center rounded-pill border border-border px-4 ${
              busy ? "opacity-60" : ""
            }`}
            accessibilityRole="button"
            accessibilityLabel={`Take back ${grant.devotee_name}'s ${
              grant.role_label || roleLabel(grant.role_name)
            } access`}
            accessibilityState={{ disabled: busy }}
            disabled={busy}
            onPress={onRevoke}
          >
            <Ionicons
              name="person-remove-outline"
              size={17}
              color={tokens.colors.vermilion}
            />
            <Text className="ml-2 font-sans-bold text-sm text-vermilion">
              Revoke
            </Text>
          </Pressable>
        </View>
      ) : (
        <Text className="mt-2 font-sans text-xs leading-5 text-stoneMuted">
          {whyNotRevocable(grant, viewerId)}
        </Text>
      )}
    </View>
  );
}

/**
 * Giving and taking back access.
 *
 * The temple does not wait to be asked: a Community Head who has watched
 * somebody run the Sunday kitchen appoints them rather than sending them away
 * to fill in a form. Who may take an appointment back is a question about the
 * past — only the coordinator who made it, or the President and Tech Admin —
 * so `can_revoke` arrives with each row and is never re-derived here.
 */
export function ManageAccessScreen() {
  const activeUserId = usePrototypeSession((state) => state.activeUserId);
  const reachable = useServerReachable();
  const mayAppoint = useMayAppointAccess(activeUserId);
  const appointments = useAccessAppointments(mayAppoint.data === true);
  const dashboard = useServiceDashboard(activeUserId);
  const appoint = useAppointAccess();
  const revoke = useRevokeAccess();

  const [adding, setAdding] = useState(false);
  const [search, setSearch] = useState("");
  const [candidate, setCandidate] = useState<ServiceDevotee | null>(null);
  const [chosenRole, setChosenRole] = useState<GrantableAccessRole>("volunteer");
  const [note, setNote] = useState("");
  const [actionError, setActionError] = useState<string | null>(null);
  const [formError, setFormError] = useState<string | null>(null);

  const active = useMemo(
    () => (appointments.data ?? []).filter((grant) => grant.is_active),
    [appointments.data],
  );

  const candidates = useMemo(() => {
    if (!adding) return [];
    const term = search.trim().toLocaleLowerCase();
    return (dashboard.data?.devotees ?? [])
      .filter(
        (devotee) =>
          devotee.id !== activeUserId &&
          // The two offices are set in the database, outside the app, and the
          // server refuses to touch them either way.
          devotee.role_name !== "president" &&
          devotee.role_name !== "tech" &&
          (!term || devotee.name.toLocaleLowerCase().includes(term)),
      )
      .slice(0, MAX_CANDIDATES);
  }, [activeUserId, adding, dashboard.data?.devotees, search]);

  const closeAppointForm = () => {
    setCandidate(null);
    setNote("");
    setFormError(null);
  };

  const openAppointForm = (devotee: ServiceDevotee) => {
    setActionError(null);
    setFormError(null);
    setNote("");
    // A Volunteer being appointed again is almost always the next rung up.
    setChosenRole(devotee.role_name === "volunteer" ? "core" : "volunteer");
    setCandidate(devotee);
  };

  const confirmAppoint = () => {
    if (!candidate) return;
    setFormError(null);
    appoint.mutate(
      {
        devoteeId: candidate.id,
        roleName: chosenRole,
        note: note.trim() || null,
      },
      {
        onSuccess: () => {
          closeAppointForm();
          setSearch("");
          setAdding(false);
        },
        onError: (caught) =>
          setFormError(
            errorMessage(
              caught,
              `${candidate.name}'s access could not be changed.`,
            ),
          ),
      },
    );
  };

  const confirmRevoke = (grant: AccessAppointment) => {
    setActionError(null);
    Alert.alert(
      `Take back ${grant.devotee_name}'s access?`,
      `They return to Devotee access and lose what ${
        grant.role_label || roleLabel(grant.role_name)
      } gave them. They are told, and so are the other coordinators. Nothing else about their account changes.`,
      [
        { text: "Keep", style: "cancel" },
        {
          text: "Revoke",
          style: "destructive",
          onPress: () =>
            revoke.mutate(
              { devoteeId: grant.devotee_id, note: null },
              {
                onError: (caught) =>
                  setActionError(
                    errorMessage(
                      caught,
                      `${grant.devotee_name}'s access could not be taken back.`,
                    ),
                  ),
              },
            ),
        },
      ],
    );
  };

  if (mayAppoint.isLoading) {
    return (
      <Screen topInset={false}>
        <ScreenTitle eyebrow="Access">Manage access</ScreenTitle>
        <View className="gap-3">
          <SkeletonCard />
          <SkeletonCard />
        </View>
      </Screen>
    );
  }

  // A failed check is not a refusal, and showing the locked card for one would
  // tell a Community Head they are not one.
  if (mayAppoint.isError) {
    return (
      <Screen topInset={false}>
        <ScreenTitle eyebrow="Access">Manage access</ScreenTitle>
        <LoadFailure
          reachable={reachable}
          message={errorMessage(
            mayAppoint.error,
            "Your access could not be checked.",
          )}
          onRetry={() => void mayAppoint.refetch()}
        />
      </Screen>
    );
  }

  if (mayAppoint.data !== true) {
    return (
      <Screen topInset={false}>
        <View className="items-center rounded-card border border-border bg-white px-card py-10">
          <Ionicons
            name="lock-closed-outline"
            size={28}
            color={tokens.colors.indigo}
          />
          <Text className="mt-3 text-center font-sans-bold text-base text-stone">
            Only a Community Head, the President or a Tech Admin can change
            access levels.
          </Text>
        </View>
      </Screen>
    );
  }

  const failed = appointments.isError && appointments.data === undefined;

  return (
    <>
      <ListScreen
        topInset={false}
        data={active}
        keyExtractor={(grant) => grant.id}
        header={
          <>
            <ScreenTitle eyebrow="Access">Manage access</ScreenTitle>

            <Text className="mb-section font-sans text-sm leading-6 text-stoneMuted">
              Volunteer and Community Head are given here. The President and
              Tech Admin levels are set outside the app. Whoever you appoint is
              told, and so are the other coordinators.
            </Text>

            <SectionHeader
              title="Appoint a devotee"
              subtitle="Search the congregation, then choose the level."
              action={adding ? "Done" : "Appoint"}
              onAction={() => {
                setAdding((open) => !open);
                setSearch("");
              }}
            />

            {adding ? (
              <View className="mb-section">
                <View className="mb-2 flex-row items-center rounded-button border border-border bg-white px-4">
                  <Ionicons
                    name="search"
                    size={19}
                    color={tokens.colors.indigo}
                  />
                  <TextInput
                    className="min-h-touch min-w-0 flex-1 px-3 font-sans text-base text-stone"
                    value={search}
                    onChangeText={setSearch}
                    placeholder="Search devotee by name"
                    placeholderTextColor={tokens.colors.stoneMuted}
                    autoCapitalize="words"
                    autoCorrect={false}
                    accessibilityLabel="Search the congregation by name"
                  />
                </View>

                <View className="overflow-hidden rounded-card border border-border bg-white">
                  {candidates.map((devotee, index) => (
                    <Pressable
                      key={devotee.id}
                      className={`min-h-[70px] flex-row items-center px-card py-2.5 ${
                        index < candidates.length - 1
                          ? "border-b border-border"
                          : ""
                      }`}
                      accessibilityRole="button"
                      accessibilityLabel={`Change ${devotee.name}'s access level`}
                      onPress={() => openAppointForm(devotee)}
                    >
                      <Avatar
                        name={devotee.name}
                        photoUrl={devotee.photo_url}
                        size="small"
                      />
                      <View className="ml-3 min-w-0 flex-1">
                        <Text
                          className="font-sans-bold text-base text-stone"
                          numberOfLines={2}
                        >
                          {devotee.name}
                        </Text>
                        <Text className="mt-0.5 font-sans text-xs text-stoneMuted">
                          {roleLabel(devotee.role_name)} today
                        </Text>
                      </View>
                      <Ionicons
                        name="chevron-forward"
                        size={19}
                        color={tokens.colors.stoneMuted}
                      />
                    </Pressable>
                  ))}
                  {!candidates.length ? (
                    <Text className="px-card py-6 text-center font-sans text-base text-stoneMuted">
                      {dashboard.isLoading
                        ? "Loading the congregation…"
                        : search.trim()
                          ? "No devotee matches that name."
                          : "There is nobody here to appoint yet."}
                    </Text>
                  ) : null}
                </View>

                {candidates.length === MAX_CANDIDATES ? (
                  <Text className="mt-2 font-sans text-xs text-stoneMuted">
                    Showing the first {MAX_CANDIDATES}. Type a name to narrow
                    it.
                  </Text>
                ) : null}
              </View>
            ) : null}

            <SectionHeader
              title="Devotees holding access"
              subtitle={
                active.length
                  ? `${active.length} ${active.length === 1 ? "devotee" : "devotees"}, with who appointed them`
                  : undefined
              }
            />

            {actionError ? <FormError message={actionError} /> : null}
          </>
        }
        renderItem={(grant) => (
          <GrantRow
            grant={grant}
            viewerId={activeUserId}
            busy={revoke.isPending}
            onRevoke={() => confirmRevoke(grant)}
          />
        )}
        empty={
          failed ? (
            <LoadFailure
              reachable={reachable}
              message={errorMessage(
                appointments.error,
                "The access record could not be loaded.",
              )}
              onRetry={() => void appointments.refetch()}
            />
          ) : (
            <EmptyOrOffline
              reachable={reachable}
              loading={appointments.isLoading}
              loadingLabel="Loading the access record…"
              empty={
                <View className="items-center rounded-card border border-border bg-white px-card py-9">
                  <View className="h-14 w-14 items-center justify-center rounded-pill bg-peacockSoft">
                    <Ionicons
                      name="key-outline"
                      size={26}
                      color={tokens.colors.peacock}
                    />
                  </View>
                  <Text className="mt-4 text-center font-display text-xl text-stone">
                    Nobody has been appointed yet
                  </Text>
                  <Text className="mt-2 max-w-80 text-center font-sans text-sm leading-6 text-stoneMuted">
                    Appoint the devotees who already carry the seva, and this
                    list will show who gave them their access and when.
                  </Text>
                </View>
              }
            />
          )
        }
      />

      <ModalScreen
        visible={Boolean(candidate)}
        onClose={closeAppointForm}
        eyebrow="Appoint"
        title={candidate?.name ?? "Appoint"}
      >
        {candidate ? (
          <>
            <View className="mb-section flex-row items-center rounded-card border border-border bg-white p-card">
              <Avatar
                name={candidate.name}
                photoUrl={candidate.photo_url}
                size="large"
                tone="peacock"
              />
              <View className="ml-4 min-w-0 flex-1">
                <Text className="font-sans-bold text-lg text-stone">
                  {candidate.name}
                </Text>
                <Text className="mt-1 font-sans text-sm text-stoneMuted">
                  {roleLabel(candidate.role_name)} today
                </Text>
              </View>
            </View>

            <SectionHeader title="Which level?" />
            {grantableAccessRoles.map((role) => {
              const selected = role === chosenRole;
              return (
                <Pressable
                  key={role}
                  className={`mb-3 rounded-card border bg-white p-card ${
                    selected ? "border-marigold" : "border-border"
                  }`}
                  accessibilityRole="radio"
                  accessibilityState={{ selected }}
                  accessibilityLabel={`Appoint as ${accessRoleLabels[role]}`}
                  onPress={() => setChosenRole(role)}
                >
                  <View className="flex-row items-start">
                    <View className="min-w-0 flex-1 pr-3">
                      <Text className="font-sans-bold text-base text-stone">
                        {accessRoleLabels[role]}
                      </Text>
                      <Text className="mt-1 font-sans text-sm leading-5 text-stoneMuted">
                        {grantableRoleSummaries[role]}
                      </Text>
                    </View>
                    <Ionicons
                      name={selected ? "checkmark-circle" : "ellipse-outline"}
                      size={24}
                      color={
                        selected
                          ? tokens.colors.peacock
                          : tokens.colors.stoneMuted
                      }
                    />
                  </View>
                </Pressable>
              );
            })}

            <SectionHeader
              title="Add a note"
              subtitle="Optional. Kept with the record of this appointment."
            />
            <TextInput
              className="min-h-[88px] rounded-button border border-border bg-white px-4 py-3 font-sans text-base text-stone"
              value={note}
              onChangeText={setNote}
              placeholder="Optional — why they are being appointed"
              placeholderTextColor={tokens.colors.stoneMuted}
              multiline
              textAlignVertical="top"
              accessibilityLabel="A note kept with this appointment"
            />

            {formError ? (
              <View className="mt-3">
                <FormError message={formError} />
              </View>
            ) : null}

            <View className="mt-section">
              <Button
                icon="shield-checkmark-outline"
                disabled={appoint.isPending}
                onPress={confirmAppoint}
              >
                {appoint.isPending
                  ? "Saving…"
                  : `Make ${candidate.name} ${accessRoleLabels[chosenRole]}`}
              </Button>
            </View>
          </>
        ) : null}
      </ModalScreen>
    </>
  );
}
