import { Ionicons } from "@expo/vector-icons";
import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import { memo, useCallback, useMemo, useState } from "react";
import { Pressable, Text, TextInput, View } from "react-native";

import tokens from "../../design-tokens.json";
import { ActionSheet, type ActionSheetAction } from "../components/ActionSheet";
import {
  Avatar,
  ListScreen,
  LoadFailure,
  SectionHeader,
} from "../components/ui";
import { memberCountLabel } from "../features/sanga/components";
import {
  soleAdminOf,
  useAddSangaMember,
  useDeleteSanga,
  useLeaveSanga,
  useRemoveSangaMember,
  useReviewSangaJoinRequest,
  useSangaJoinRequests,
  useSangaRealtime,
  useSangaViewer,
  useTransferSangaAdmin,
} from "../features/sanga/hooks";
import type {
  SangaJoinRequest,
  SangaMember,
  SangaViewerCapabilities,
} from "../features/sanga/types";
import { FormError } from "../features/services/components";
import { errorMessage } from "../features/services/format";
import { useServiceDashboard } from "../features/services/hooks";
import { formatChicagoShortDate } from "../lib/chicagoDate";
import { useServerReachable } from "../lib/connectivity";
import type { DevoteesStackParamList } from "../navigation/types";
import { RowsSkeleton } from "./DevoteesScreen";

type Props = NativeStackScreenProps<DevoteesStackParamList, "SangaInfo">;

/** Enough names to choose from without turning the roll into a directory. */
const MAX_CANDIDATES = 8;

function joinedLabel(value: string) {
  const at = new Date(value);
  if (Number.isNaN(at.getTime())) return "Member";
  return `Joined ${formatChicagoShortDate(at)}`;
}

function askedLabel(value: string) {
  const at = new Date(value);
  if (Number.isNaN(at.getTime())) return "Asked to join";
  return `Asked ${formatChicagoShortDate(at)}`;
}

/** What the sanga is, over who runs it and who started it. */
function SangaCard({
  name,
  description,
  memberCount,
  adminName,
  createdByName,
  capabilities,
}: {
  name: string;
  description: string | null | undefined;
  memberCount: number | null;
  adminName: string | null | undefined;
  createdByName: string | null | undefined;
  capabilities: SangaViewerCapabilities;
}) {
  const meta = [
    memberCount === null ? "Loading…" : memberCountLabel(memberCount),
    adminName ? `run by ${adminName}` : null,
  ]
    .filter(Boolean)
    .join(" · ");

  return (
    <View className="mb-section rounded-card border border-border bg-white p-card">
      <View className="flex-row items-start">
        <View className="h-12 w-12 items-center justify-center rounded-pill border border-peacock/10 bg-peacockSoft">
          <Ionicons
            name="people-outline"
            size={22}
            color={tokens.colors.peacock}
          />
        </View>
        <View className="ml-3 min-w-0 flex-1">
          <Text
            className="font-display text-xl leading-7 text-stone"
            accessibilityRole="header"
            numberOfLines={3}
          >
            {name}
          </Text>
          <Text className="mt-0.5 font-sans text-sm leading-5 text-stoneMuted">
            {meta}
          </Text>
        </View>
      </View>

      <Text className="mt-3 font-sans text-sm leading-6 text-stone">
        {description?.trim() || "This sanga has not written a description yet."}
      </Text>

      {createdByName ? (
        <Text className="mt-2 font-sans text-xs text-stoneMuted">
          Started by {createdByName}
        </Text>
      ) : null}

      {/* Said plainly, because everything on this page is offered to them and
          none of it makes them a member. */}
      {capabilities.overseesApp && !capabilities.isMember ? (
        <Text className="mt-3 font-sans text-xs leading-4 text-stoneMuted">
          You can act here because you oversee the app. You are not a member of
          this sanga, and nothing you do here puts you in it.
        </Text>
      ) : null}
    </View>
  );
}

function JoinRequestCard({
  request,
  busy,
  onOpen,
  onApprove,
  onDecline,
}: {
  request: SangaJoinRequest;
  busy: boolean;
  onOpen: (devoteeId: string) => void;
  onApprove: (request: SangaJoinRequest) => void;
  onDecline: (request: SangaJoinRequest) => void;
}) {
  return (
    <View className="mb-2 rounded-card border border-border bg-white p-card">
      <Pressable
        className="flex-row items-center"
        accessibilityRole="button"
        accessibilityLabel={`Open ${request.devotee_name}'s profile`}
        onPress={() => onOpen(request.devotee_id)}
      >
        <Avatar
          name={request.devotee_name}
          photoUrl={request.devotee_photo_url}
          size="small"
        />
        <View className="ml-3 min-w-0 flex-1">
          <Text
            className="font-sans-bold text-base text-stone"
            numberOfLines={2}
          >
            {request.devotee_name}
          </Text>
          <Text className="mt-0.5 font-sans text-sm text-stoneMuted">
            {askedLabel(request.created_at)}
          </Text>
        </View>
      </Pressable>

      {request.message?.trim() ? (
        <Text className="mt-2 font-sans text-sm leading-6 text-stone">
          “{request.message.trim()}”
        </Text>
      ) : null}

      <View className={`mt-3 flex-row ${busy ? "opacity-60" : ""}`}>
        <Pressable
          className="min-h-10 flex-1 flex-row items-center justify-center rounded-pill bg-marigold px-4"
          accessibilityRole="button"
          accessibilityLabel={`Approve ${request.devotee_name}`}
          accessibilityState={{ disabled: busy }}
          disabled={busy}
          onPress={() => onApprove(request)}
        >
          <Ionicons
            name="checkmark"
            size={16}
            color={tokens.colors.stone}
            style={{ marginRight: 4 }}
          />
          <Text className="font-sans-bold text-sm text-stone">Approve</Text>
        </Pressable>
        <Pressable
          className="ml-2 min-h-10 flex-1 flex-row items-center justify-center rounded-pill border border-border bg-white px-4"
          accessibilityRole="button"
          accessibilityLabel={`Decline ${request.devotee_name}`}
          accessibilityState={{ disabled: busy }}
          disabled={busy}
          onPress={() => onDecline(request)}
        >
          <Text className="font-sans-bold text-sm text-indigo">Decline</Text>
        </Pressable>
      </View>
    </View>
  );
}

/** Memoised, with handlers that take the member: a roll of thirty redraws the
 * row that changed and not the other twenty-nine. */
const MemberRow = memo(function MemberRow({
  member,
  isSelf,
  isFirst,
  isLast,
  manageable,
  onOpen,
  onManage,
}: {
  member: SangaMember;
  isSelf: boolean;
  isFirst: boolean;
  isLast: boolean;
  manageable: boolean;
  onOpen: (devoteeId: string) => void;
  onManage: (member: SangaMember) => void;
}) {
  const open = useCallback(() => onOpen(member.id), [member.id, onOpen]);
  const manage = useCallback(() => onManage(member), [member, onManage]);

  return (
    <View
      className={`min-h-[76px] flex-row items-center border-x border-border bg-white px-card py-3 ${
        isFirst ? "rounded-t-card border-t" : ""
      } ${isLast ? "rounded-b-card border-b" : "border-b"}`}
    >
      <Pressable
        className="min-w-0 flex-1 flex-row items-center pr-2"
        accessibilityRole="button"
        accessibilityLabel={`Open ${member.name}'s profile`}
        onPress={open}
      >
        <Avatar name={member.name} photoUrl={member.photo_url} />
        <View className="ml-4 min-w-0 flex-1">
          <View className="flex-row items-center">
            <Text
              className="min-w-0 shrink font-sans-bold text-lg text-stone"
              numberOfLines={2}
            >
              {member.name}
              {isSelf ? " (You)" : ""}
            </Text>
            {member.role === "admin" ? (
              <View className="ml-2 shrink-0 rounded-pill bg-peacockSoft px-2 py-0.5">
                <Text className="font-sans-bold text-xs text-peacock">
                  Admin
                </Text>
              </View>
            ) : null}
          </View>
          <Text className="mt-0.5 font-sans text-sm text-stoneMuted">
            {joinedLabel(member.joined_at)}
          </Text>
        </View>
      </Pressable>
      {manageable ? (
        <Pressable
          className="h-11 w-11 items-center justify-center rounded-pill"
          accessibilityRole="button"
          accessibilityLabel={`More for ${member.name}`}
          hitSlop={6}
          onPress={manage}
        >
          <Ionicons
            name="ellipsis-horizontal"
            size={20}
            color={tokens.colors.indigo}
          />
        </Pressable>
      ) : (
        <Ionicons
          name="chevron-forward"
          size={18}
          color={tokens.colors.stoneMuted}
        />
      )}
    </View>
  );
});

/**
 * What a sanga is and who is in it, reached by tapping its name in the thread.
 *
 * Every management action lives here rather than being scattered: adding and
 * removing, answering who has asked, handing the circle on, leaving it and
 * closing it. The devotee running the sanga sees them, and so does the
 * President — 202608040043_sanga_powers.sql lets them act without joining.
 */
export function SangaInfoScreen({ navigation, route }: Props) {
  const { sangaId, name } = route.params;
  const reachable = useServerReachable();
  const viewer = useSangaViewer(sangaId);
  const { activeUserId, capabilities, members, summary } = viewer;
  // The roll and the inbox move under this screen while it is open — somebody
  // approved on another phone, somebody leaving — so it listens rather than
  // waiting to be reopened.
  useSangaRealtime(sangaId);

  const sangaName = summary?.name ?? name;
  const joinRequests = useSangaJoinRequests(
    sangaId,
    capabilities.canManageMembers,
  );
  // The directory the devotee picker everywhere else reads from, and the tab
  // this screen is reached through has already loaded it.
  const dashboard = useServiceDashboard(activeUserId);
  const addMember = useAddSangaMember();
  const removeMember = useRemoveSangaMember();
  const reviewRequest = useReviewSangaJoinRequest();
  const transferAdmin = useTransferSangaAdmin();
  const leave = useLeaveSanga();
  const deleteSanga = useDeleteSanga();

  const [actionError, setActionError] = useState<string | null>(null);
  const [adding, setAdding] = useState(false);
  const [search, setSearch] = useState("");
  // Held apart from the sheet's contents so it still has something to draw
  // while it slides away.
  const [sheet, setSheet] = useState<{
    title: string;
    message?: string;
    actions: ActionSheetAction[];
  } | null>(null);
  const [sheetOpen, setSheetOpen] = useState(false);

  const rows: SangaMember[] = members.data ?? [];
  const membersFailed = members.isError && members.data === undefined;
  const pendingRequests = useMemo(
    () =>
      (joinRequests.data ?? []).filter(
        (request) => request.status === "pending",
      ),
    [joinRequests.data],
  );

  const selfMember = useMemo(
    () => rows.find((member) => member.id === activeUserId) ?? null,
    [activeUserId, rows],
  );
  // soleAdminOf reads the roll; until it has arrived a viewer the summary calls
  // the admin is taken to be the only one, so the refusal is explained a beat
  // early rather than discovered by tapping Leave.
  const selfIsSoleAdmin = selfMember
    ? soleAdminOf(rows, selfMember)
    : capabilities.isAdmin;

  const memberIds = useMemo(
    () => new Set(rows.map((member) => member.id)),
    [rows],
  );
  const candidates = useMemo(() => {
    if (!adding) return [];
    const query = search.trim().toLocaleLowerCase();
    return (dashboard.data?.devotees ?? [])
      .filter(
        (devotee) =>
          !memberIds.has(devotee.id) &&
          (!query || devotee.name.toLocaleLowerCase().includes(query)),
      )
      .slice(0, MAX_CANDIDATES);
  }, [adding, dashboard.data?.devotees, memberIds, search]);

  const openSheet = useCallback(
    (next: {
      title: string;
      message?: string;
      actions: ActionSheetAction[];
    }) => {
      setSheet(next);
      setSheetOpen(true);
    },
    [],
  );

  const openProfile = useCallback(
    (devoteeId: string) => navigation.navigate("DevoteeProfile", { devoteeId }),
    [navigation],
  );

  const approve = useCallback(
    (request: SangaJoinRequest) => {
      setActionError(null);
      reviewRequest.mutate(
        { requestId: request.id, decision: "approved" },
        {
          onError: (error) =>
            setActionError(
              errorMessage(
                error,
                `${request.devotee_name} could not be added right now.`,
              ),
            ),
        },
      );
    },
    [reviewRequest],
  );

  const confirmDecline = useCallback(
    (request: SangaJoinRequest) => {
      openSheet({
        title: request.devotee_name,
        actions: [
          {
            label: "Decline this request",
            icon: "close-circle-outline",
            destructive: true,
            confirm: {
              title: `Decline ${request.devotee_name}?`,
              message: `They will not join ${sangaName}. They can ask again later.`,
              confirmLabel: "Decline",
            },
            onPress: () => {
              setActionError(null);
              reviewRequest.mutate(
                { requestId: request.id, decision: "declined" },
                {
                  onError: (error) =>
                    setActionError(
                      errorMessage(
                        error,
                        "That request could not be declined.",
                      ),
                    ),
                },
              );
            },
          },
        ],
      });
    },
    [openSheet, reviewRequest, sangaName],
  );

  /**
   * One member's sheet. What is on it depends on the last-admin rule as much
   * as on the viewer: a sanga must always have somebody responsible for it, so
   * its sole admin has no Remove — and is told why, rather than tapping one
   * and being handed the server's refusal.
   */
  const manageMember = useCallback(
    (member: SangaMember) => {
      const isSole = soleAdminOf(rows, member);
      const actions: ActionSheetAction[] = [];

      if (capabilities.canTransferAdmin && member.role !== "admin") {
        actions.push({
          label: `Hand this sanga to ${member.name}`,
          icon: "swap-horizontal-outline",
          confirm: {
            title: `Hand ${sangaName} over?`,
            message: `${member.name} will run ${sangaName} — adding members and answering who asks to join. You stay in it as a member.`,
            confirmLabel: "Hand it over",
          },
          onPress: () => {
            setActionError(null);
            transferAdmin.mutate(
              { sangaId, devoteeId: member.id },
              {
                onError: (error) =>
                  setActionError(
                    errorMessage(
                      error,
                      `${sangaName} could not be handed over.`,
                    ),
                  ),
              },
            );
          },
        });
      }

      if (capabilities.canManageMembers && !isSole) {
        actions.push({
          label: "Remove from this sanga",
          icon: "person-remove-outline",
          destructive: true,
          confirm: {
            title: `Remove ${member.name}?`,
            message: `${member.name} will lose ${sangaName} and its thread. They can ask to join again.`,
            confirmLabel: "Remove",
          },
          onPress: () => {
            setActionError(null);
            removeMember.mutate(
              { sangaId, devoteeId: member.id },
              {
                onError: (error) =>
                  setActionError(
                    errorMessage(error, `${member.name} could not be removed.`),
                  ),
              },
            );
          },
        });
      }

      openSheet({
        title: member.name,
        message: isSole
          ? `${member.name} is the only devotee responsible for ${sangaName} and cannot be removed while that is true. Hand the sanga to another member first, or delete it.`
          : undefined,
        actions,
      });
    },
    [
      capabilities.canManageMembers,
      capabilities.canTransferAdmin,
      openSheet,
      removeMember,
      rows,
      sangaId,
      sangaName,
      transferAdmin,
    ],
  );

  const add = (devotee: {
    id: string;
    name: string;
    photo_url: string | null;
  }) => {
    setActionError(null);
    addMember.mutate(
      {
        sangaId,
        devoteeId: devotee.id,
        devoteeName: devotee.name,
        devoteePhotoUrl: devotee.photo_url,
      },
      {
        onError: (error) =>
          setActionError(
            errorMessage(error, `${devotee.name} could not be added.`),
          ),
      },
    );
  };

  /**
   * Offered from two sheets: the footer's, and the one that tells the sole
   * admin their two ways out, deleting being the second of them.
   */
  const deleteAction = (): ActionSheetAction => {
    const count = viewer.memberCount;
    return {
      label: "Delete this sanga",
      icon: "trash-outline",
      destructive: true,
      confirm: {
        title: `Delete ${sangaName}?`,
        // Named rather than gestured at: this is the one action here that
        // cannot be undone by anybody, including the temple office.
        message: `${sangaName} stops appearing anywhere. ${
          count === null ? "Everyone in it" : `Its ${memberCountLabel(count)}`
        } will lose the group and everything said in its thread, and they are all told it has closed. This cannot be undone.`,
        confirmLabel: "Delete sanga",
      },
      onPress: () => {
        setActionError(null);
        deleteSanga.mutate(
          { sangaId },
          {
            onSuccess: () => navigation.popToTop(),
            onError: (error) =>
              setActionError(
                errorMessage(error, `${sangaName} could not be deleted.`),
              ),
          },
        );
      },
    };
  };

  /**
   * A sanga must always have somebody responsible for it, so leave_sanga turns
   * its sole admin down. They are told the two ways out — hand it on, or close
   * it — and handed the second one here, the first being a member's own row.
   */
  const confirmLeave = () => {
    if (selfIsSoleAdmin) {
      // With nobody else in it there is no successor to name, so only one of
      // the two ways out is honestly on offer.
      const alone = viewer.memberCount === 1;
      openSheet({
        title: sangaName,
        message: alone
          ? `You are the only devotee in ${sangaName} and the one responsible for it, so there is nobody to hand it to. Deleting it is the way out.`
          : `You are the only devotee responsible for ${sangaName}, and it cannot be left without one. Hand it to another member first — tap their name on the roll above — or delete the sanga.`,
        actions: capabilities.canDeleteSanga ? [deleteAction()] : [],
      });
      return;
    }

    openSheet({
      title: sangaName,
      actions: [
        {
          label: "Leave this sanga",
          icon: "exit-outline",
          destructive: true,
          confirm: {
            title: `Leave ${sangaName}?`,
            message: `You lose its thread and everything said in it, and you stop hearing what the group announces. You can ask to join again, and its admin answers.`,
            confirmLabel: "Leave",
          },
          onPress: () => {
            setActionError(null);
            leave.mutate(
              { sangaId, selfId: activeUserId ?? undefined },
              {
                onSuccess: () => navigation.popToTop(),
                onError: (error) =>
                  setActionError(
                    errorMessage(error, `You could not leave ${sangaName}.`),
                  ),
              },
            );
          },
        },
      ],
    });
  };

  const confirmDelete = () => {
    openSheet({ title: sangaName, actions: [deleteAction()] });
  };

  return (
    <ListScreen
      topInset={false}
      data={rows}
      keyExtractor={(member) => member.id}
      header={
        <>
          <ActionSheet
            visible={sheetOpen}
            title={sheet?.title ?? ""}
            message={sheet?.message}
            actions={sheet?.actions ?? []}
            onClose={() => setSheetOpen(false)}
          />

          <SangaCard
            name={sangaName}
            description={summary?.description}
            memberCount={viewer.memberCount}
            adminName={summary?.admin_name}
            createdByName={summary?.created_by_name}
            capabilities={capabilities}
          />

          {capabilities.canManageMembers && pendingRequests.length ? (
            <View className="mb-section">
              <SectionHeader
                title="Waiting to join"
                subtitle={`${pendingRequests.length} ${
                  pendingRequests.length === 1 ? "devotee has" : "devotees have"
                } asked`}
              />
              {pendingRequests.map((request) => (
                <JoinRequestCard
                  key={request.id}
                  request={request}
                  busy={reviewRequest.isPending}
                  onOpen={openProfile}
                  onApprove={approve}
                  onDecline={confirmDecline}
                />
              ))}
            </View>
          ) : null}

          <SectionHeader
            title="Members"
            subtitle={
              viewer.memberCount === null
                ? undefined
                : memberCountLabel(viewer.memberCount)
            }
            action={
              capabilities.canManageMembers
                ? adding
                  ? "Done"
                  : "Add devotee"
                : undefined
            }
            onAction={
              capabilities.canManageMembers
                ? () => {
                    setAdding((open) => !open);
                    setSearch("");
                  }
                : undefined
            }
          />

          {adding ? (
            <View className="mb-3">
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
                />
              </View>
              <View className="overflow-hidden rounded-card border border-border bg-white">
                {candidates.map((devotee, index) => (
                  <View
                    key={devotee.id}
                    className={`min-h-[70px] flex-row items-center px-card py-2.5 ${
                      index < candidates.length - 1
                        ? "border-b border-border"
                        : ""
                    }`}
                  >
                    <Pressable
                      className="min-w-0 flex-1 flex-row items-center pr-2"
                      accessibilityRole="button"
                      accessibilityLabel={`Open ${devotee.name}'s profile`}
                      onPress={() => openProfile(devotee.id)}
                    >
                      <Avatar
                        name={devotee.name}
                        photoUrl={devotee.photo_url}
                        size="small"
                      />
                      <Text
                        className="ml-3 min-w-0 flex-1 font-sans-bold text-base text-stone"
                        numberOfLines={2}
                      >
                        {devotee.name}
                      </Text>
                    </Pressable>
                    <Pressable
                      className={`min-h-10 shrink-0 flex-row items-center justify-center rounded-pill bg-marigold px-4 ${
                        addMember.isPending ? "opacity-60" : ""
                      }`}
                      accessibilityRole="button"
                      accessibilityLabel={`Add ${devotee.name} to ${sangaName}`}
                      accessibilityState={{ disabled: addMember.isPending }}
                      disabled={addMember.isPending}
                      onPress={() => add(devotee)}
                    >
                      <Ionicons
                        name="add"
                        size={16}
                        color={tokens.colors.stone}
                        style={{ marginRight: 4 }}
                      />
                      <Text className="font-sans-bold text-sm text-stone">
                        Add
                      </Text>
                    </Pressable>
                  </View>
                ))}
                {!candidates.length ? (
                  <Text className="px-card py-6 text-center font-sans text-base text-stoneMuted">
                    {dashboard.isLoading
                      ? "Loading the congregation…"
                      : search.trim()
                        ? "No devotee outside this sanga matches that name."
                        : "Everyone in the congregation is already here."}
                  </Text>
                ) : null}
              </View>
              {candidates.length === MAX_CANDIDATES ? (
                <Text className="mt-2 font-sans text-xs text-stoneMuted">
                  Showing the first {MAX_CANDIDATES}. Type a name to narrow it.
                </Text>
              ) : null}
            </View>
          ) : null}

          {actionError ? <FormError message={actionError} /> : null}
        </>
      }
      renderItem={(member, index) => (
        <MemberRow
          member={member}
          isSelf={member.id === activeUserId}
          isFirst={index === 0}
          isLast={index === rows.length - 1}
          // Their own row is not something to manage: leaving is one control
          // for the whole sanga and it is at the foot of this page.
          manageable={
            capabilities.canManageMembers && member.id !== activeUserId
          }
          onOpen={openProfile}
          onManage={manageMember}
        />
      )}
      empty={
        members.isLoading ? (
          <RowsSkeleton />
        ) : membersFailed ? (
          <LoadFailure
            reachable={reachable}
            message={errorMessage(
              members.error,
              "The members could not be loaded.",
            )}
            onRetry={() => void members.refetch()}
          />
        ) : (
          <View className="items-center rounded-card border border-border bg-white px-card py-8">
            <Ionicons
              name="person-add-outline"
              size={30}
              color={tokens.colors.peacock}
            />
            <Text className="mt-3 text-center font-sans-bold text-base text-stone">
              No members yet
            </Text>
            <Text className="mt-1 text-center font-sans text-sm text-stoneMuted">
              {capabilities.canManageMembers
                ? "Add a devotee to start this sanga off."
                : "The first devotees will appear here."}
            </Text>
          </View>
        )
      }
      footer={
        capabilities.canLeave || capabilities.canDeleteSanga ? (
          <View className="mt-section gap-2">
            {capabilities.canLeave ? (
              <Pressable
                className="min-h-touch flex-row items-center justify-center rounded-button border border-border bg-white px-4"
                accessibilityRole="button"
                accessibilityLabel={`Leave ${sangaName}`}
                // Offered rather than disabled: the sole admin taps it and is
                // told how to hand the sanga on, which is the way out.
                accessibilityHint={
                  selfIsSoleAdmin
                    ? "You run this sanga, so you will be shown what to do first"
                    : undefined
                }
                accessibilityState={{ disabled: leave.isPending }}
                disabled={leave.isPending}
                onPress={confirmLeave}
              >
                <Ionicons
                  name="exit-outline"
                  size={18}
                  color={tokens.colors.indigo}
                />
                <Text className="ml-2 font-sans-bold text-base text-indigo">
                  Leave this sanga
                </Text>
              </Pressable>
            ) : null}
            {capabilities.canDeleteSanga ? (
              <Pressable
                className="min-h-touch flex-row items-center justify-center rounded-button border border-vermilion/30 bg-white px-4"
                accessibilityRole="button"
                accessibilityLabel={`Delete ${sangaName}`}
                accessibilityState={{ disabled: deleteSanga.isPending }}
                disabled={deleteSanga.isPending}
                onPress={confirmDelete}
              >
                <Ionicons
                  name="trash-outline"
                  size={18}
                  color={tokens.colors.vermilion}
                />
                <Text className="ml-2 font-sans-bold text-base text-vermilion">
                  Delete this sanga
                </Text>
              </Pressable>
            ) : null}
          </View>
        ) : null
      }
    />
  );
}
