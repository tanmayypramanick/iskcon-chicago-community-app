import { Ionicons } from "@expo/vector-icons";
import { useIsFocused } from "@react-navigation/native";
import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import { useCallback, useEffect, useMemo, useState } from "react";
import { Pressable, Text, TextInput, View } from "react-native";

import tokens from "../../design-tokens.json";
import { ActionSheet, type ActionSheetAction } from "../components/ActionSheet";
import {
  AlphabetIndexList,
  groupByInitial,
} from "../components/AlphabetIndexList";
import {
  Avatar,
  AvatarViewer,
  Button,
  EmptyOrOffline,
  ListScreen,
  LoadFailure,
  ScreenTitle,
  SectionHeader,
  Skeleton,
} from "../components/ui";
import { useCurrentAccessProfile } from "../features/access/hooks";
import {
  accessRoleLabels,
  hasAccessPermission,
  isAccessRole,
} from "../features/access/model";
import { openConversation } from "../features/messaging/api";
import { useConversations } from "../features/messaging/hooks";
import type { ConversationSummary } from "../features/messaging/types";
import { AtTempleBadge } from "../features/presence/components";
import { useTemplePresence } from "../features/presence/hooks";
import {
  SangaEmpty,
  SangaNote,
  SangaRow,
  SangaRowsSkeleton,
} from "../features/sanga/components";
import {
  matchesSangaSearch,
  useAskToJoinSanga,
  useLeaveSanga,
  usePendingSangas,
  useSangaListRealtime,
  useSangas,
} from "../features/sanga/hooks";
import type { SangaSummary } from "../features/sanga/types";
import { FormError } from "../features/services/components";
import { errorMessage } from "../features/services/format";
import { useServiceDashboard } from "../features/services/hooks";
import type { ServiceDevotee } from "../features/services/types";
import { useServerReachable } from "../lib/connectivity";
import type {
  DevoteesSection,
  DevoteesStackParamList,
} from "../navigation/types";
import { usePrototypeSession } from "../store/usePrototypeSession";
import { ConversationRow, ConversationsEmpty } from "./ConversationsScreen";

type Props = NativeStackScreenProps<DevoteesStackParamList, "DevoteesHome">;

type Row =
  | { kind: "conversation"; id: string; conversation: ConversationSummary }
  | {
      kind: "sanga";
      id: string;
      sanga: SangaSummary;
      isFirst: boolean;
      isLast: boolean;
    }
  | {
      kind: "heading";
      id: string;
      title: string;
      action?: string;
      onAction?: () => void;
    }
  | { kind: "note"; id: string; text: string };

/** How many sangas a group shows before "See all" is offered. */
const SANGA_PREVIEW = 4;

const searchFields: Record<
  DevoteesSection,
  { label: string; placeholder: string }
> = {
  messages: {
    label: "Search messages",
    placeholder: "Search by devotee name",
  },
  sanga: { label: "Search sangas", placeholder: "Search by sanga name" },
  directory: {
    label: "Search devotees",
    placeholder: "Search by devotee name",
  },
};

/**
 * The weekday chip from the seva filters, widened into a two-way toggle. The
 * label is a size up because this one steers the whole screen rather than
 * narrowing a list.
 */
function SegmentButton({
  label,
  selected,
  badge,
  onPress,
}: {
  label: string;
  selected: boolean;
  badge?: number;
  onPress: () => void;
}) {
  return (
    <Pressable
      // Three across has to survive a 320dp phone, so the label gives way
      // before the button does rather than wrapping onto a second line.
      className={`min-h-touch min-w-0 flex-1 flex-row items-center justify-center rounded-pill border px-2 ${
        selected ? "border-indigo bg-indigo" : "border-border bg-white"
      }`}
      accessibilityRole="button"
      accessibilityState={{ selected }}
      accessibilityLabel={
        badge ? `${label}, ${badge} with unread messages` : label
      }
      onPress={onPress}
    >
      <Text
        className={`shrink font-sans-bold text-sm ${
          selected ? "text-white" : "text-stone"
        }`}
        numberOfLines={1}
      >
        {label}
      </Text>
      {badge ? (
        <View
          className={`ml-1.5 min-w-[22px] shrink-0 items-center rounded-pill px-1.5 py-0.5 ${
            selected ? "bg-white" : "bg-peacock"
          }`}
        >
          <Text
            className={`font-sans-bold text-xs ${
              selected ? "text-indigo" : "text-white"
            }`}
          >
            {badge > 99 ? "99+" : badge}
          </Text>
        </View>
      ) : null}
    </Pressable>
  );
}

/**
 * Rows in the shape of the real ones. Directory and message rows are built the
 * same way, so one placeholder serves both. An empty list and an unloaded list
 * used to look identical, which told a devotee the community was empty.
 */
export function RowsSkeleton() {
  return (
    <View className="overflow-hidden rounded-card border border-border bg-white">
      {[0, 1, 2, 3, 4].map((slot) => (
        <View
          key={slot}
          className={`min-h-[76px] flex-row items-center px-card py-3 ${
            slot ? "border-t border-border" : ""
          }`}
        >
          <View className="h-12 w-12 overflow-hidden rounded-pill">
            <Skeleton height={48} width={48} />
          </View>
          <View className="ml-4 flex-1">
            <Skeleton height={16} width="56%" />
            <View className="mt-2">
              <Skeleton height={12} width="34%" />
            </View>
          </View>
        </View>
      ))}
    </View>
  );
}

/** The one shape every "there is nothing here" answer on this screen takes. */
function EmptyCard({
  icon,
  title,
  body,
}: {
  icon: keyof typeof Ionicons.glyphMap;
  title: string;
  body: string;
}) {
  return (
    <View className="items-center rounded-card border border-border bg-white px-card py-8">
      <Ionicons name={icon} size={30} color={tokens.colors.peacock} />
      <Text className="mt-3 text-center font-sans-bold text-base text-stone">
        {title}
      </Text>
      <Text className="mt-1 text-center font-sans text-sm text-stoneMuted">
        {body}
      </Text>
    </View>
  );
}

export function DevoteesScreen({ navigation, route }: Props) {
  const isFocused = useIsFocused();
  const activeUserId = usePrototypeSession((state) => state.activeUserId);
  const dashboard = useServiceDashboard(activeUserId);
  const presence = useTemplePresence(activeUserId);
  const conversations = useConversations();
  const reachable = useServerReachable();
  // Messages first: it is the only list on this screen that changes while a
  // devotee is away from it, so it is the one they came back for.
  const [section, setSection] = useState<DevoteesSection>(
    route.params?.section ?? "messages",
  );
  const [search, setSearch] = useState("");
  const [openingId, setOpeningId] = useState<string | null>(null);
  const [chatError, setChatError] = useState<string | null>(null);
  const [sangaError, setSangaError] = useState<string | null>(null);
  const [viewingPerson, setViewingPerson] = useState<{
    name: string;
    photo_url?: string | null;
    subtitle?: string;
  } | null>(null);

  const [showAllJoined, setShowAllJoined] = useState(false);
  const [showAllMore, setShowAllMore] = useState(false);

  const sangas = useSangas(section === "sanga");
  const { ask, askingSangaId } = useAskToJoinSanga();
  const leave = useLeaveSanga();
  // Held apart from the sheet's contents so it still has something to draw
  // while it slides away.
  const [sangaSheet, setSangaSheet] = useState<{
    title: string;
    message?: string;
    actions: ActionSheetAction[];
  } | null>(null);
  const [sangaSheetOpen, setSangaSheetOpen] = useState(false);
  // Approvals, new members and answered asks all land while this list is on
  // screen, and until 202608040043_sanga_powers.sql put the three tables on
  // Realtime none of them showed without leaving the tab and coming back.
  useSangaListRealtime(section === "sanga");
  const profile = useCurrentAccessProfile(activeUserId);
  const previewRole = usePrototypeSession((state) => state.previewRole);
  const actualRole = profile.data?.role ?? "devotee";
  const role = __DEV__ && previewRole ? previewRole : actualRole;
  // The President and the Tech Admin decide whether the temple has a sanga at
  // all, and may open any of them without joining. Nobody else is shown either
  // door.
  const mayReviewSangas = hasAccessPermission(role, "app.view_all");
  const pendingSangas = usePendingSangas(
    section === "sanga" && mayReviewSangas,
  );
  const pendingSangaCount = pendingSangas.data?.length ?? 0;

  const selectSection = (next: DevoteesSection) => {
    setSection(next);
    // Each section searches a different kind of name, so a devotee's name left
    // in the box would silently hide every sanga.
    setSearch("");
    setSangaError(null);
    setShowAllJoined(false);
    setShowAllMore(false);
  };

  useEffect(() => {
    if (!isFocused || !activeUserId) return;
    void Promise.all([dashboard.refetch(), presence.refetch()]);
  }, [activeUserId, dashboard.refetch, isFocused, presence.refetch]);

  // Another screen can ask for a particular section — Sanga joined, in the
  // profile, sends devotees here to find more.
  const requestedSection = route.params?.section;
  useEffect(() => {
    if (!requestedSection) return;
    setSection(requestedSection);
    setSearch("");
  }, [requestedSection]);

  const atTempleIds = useMemo(
    () => new Set(presence.data?.people.map((person) => person.user_id) ?? []),
    [presence.data?.people],
  );
  const filteredDevotees = useMemo(() => {
    const query = search.trim().toLocaleLowerCase();
    return (dashboard.data?.devotees ?? []).filter(
      (devotee) =>
        // The directory is for finding other devotees. Your own row is noise:
        // you cannot message yourself, and your profile is a tab away.
        devotee.id !== activeUserId &&
        (!query || devotee.name.toLocaleLowerCase().includes(query)),
    );
  }, [activeUserId, dashboard.data?.devotees, search]);

  const conversationRows: ConversationSummary[] = conversations.data ?? [];
  // Counted before the search narrows anything: the badge is about the inbox,
  // not about what is currently on screen.
  const unreadThreads = conversationRows.filter(
    (row) => row.unread_count > 0,
  ).length;
  const filteredConversations = useMemo(() => {
    const query = search.trim().toLocaleLowerCase();
    const all = conversations.data ?? [];
    if (!query) return all;
    return all.filter((row) =>
      row.other_name.toLocaleLowerCase().includes(query),
    );
  }, [conversations.data, search]);

  const searching = Boolean(search.trim());

  /**
   * Joined first, then everything else. A search flattens the two groups into
   * one list: a devotee typing a name wants that sanga, and being told which
   * half of the screen it lives in is an extra step.
   */
  const sangaRows = useMemo<Row[]>(() => {
    if (sangas.data === undefined) return [];
    const matching = sangas.data.filter((sanga) =>
      matchesSangaSearch(sanga, search),
    );
    const group = (items: SangaSummary[]): Row[] =>
      items.map((sanga, index) => ({
        kind: "sanga" as const,
        id: sanga.id,
        sanga,
        isFirst: index === 0,
        isLast: index === items.length - 1,
      }));

    if (search.trim()) return group(matching);

    const joined = matching.filter((sanga) => sanga.is_member);
    const rest = matching.filter((sanga) => !sanga.is_member);
    if (!joined.length && !rest.length) return [];

    // A long list of circles is a wall of text. Each group shows a handful
    // and says how many more there are.
    const preview = (items: SangaSummary[], showAll: boolean) =>
      showAll ? items : items.slice(0, SANGA_PREVIEW);
    const seeAll = (
      items: SangaSummary[],
      showAll: boolean,
      toggle: () => void,
    ) =>
      items.length > SANGA_PREVIEW
        ? {
            action: showAll ? "Show fewer" : `See all ${items.length}`,
            onAction: toggle,
          }
        : {};

    return [
      {
        kind: "heading",
        id: "heading-joined",
        title: "Sangas you’ve joined",
        ...seeAll(joined, showAllJoined, () =>
          setShowAllJoined((value) => !value),
        ),
      },
      ...(joined.length
        ? group(preview(joined, showAllJoined))
        : [
            {
              kind: "note" as const,
              id: "note-joined",
              text: "You are not in a sanga yet. Ask to join one below, or start your own.",
            },
          ]),
      ...(rest.length
        ? [
            {
              kind: "heading" as const,
              id: "heading-more",
              title: "More sangas",
              ...seeAll(rest, showAllMore, () =>
                setShowAllMore((value) => !value),
              ),
            },
            ...group(preview(rest, showAllMore)),
          ]
        : []),
    ];
  }, [sangas.data, search, showAllJoined, showAllMore]);

  // Once a roster has arrived it stays on screen, even if the next refetch
  // fails: a devotee reading a name should not lose it to a dropped request.
  // Presence only decorates a row, so its failure never empties the list.
  const showList = dashboard.data !== undefined;
  const directoryFailed = dashboard.isError && dashboard.data === undefined;
  const messagesFailed =
    conversations.isError && conversations.data === undefined;
  const sangasFailed = sangas.isError && sangas.data === undefined;

  const startChat = async (devoteeId: string, name: string) => {
    setChatError(null);
    setOpeningId(devoteeId);
    try {
      const conversationId = await openConversation(devoteeId);
      navigation.navigate("Chat", { conversationId, devoteeId, name });
    } catch (caught) {
      setChatError(
        caught instanceof Error
          ? caught.message
          : "That conversation could not be opened.",
      );
    } finally {
      setOpeningId(null);
    }
  };

  // Joining is a request the sanga's admin answers, so this only asks. Tapping
  // twice cannot send two.
  const askToJoin = useCallback(
    (sanga: SangaSummary) => {
      setSangaError(null);
      ask(sanga.id, (caught) =>
        setSangaError(
          errorMessage(caught, `Your ask to join ${sanga.name} did not send.`),
        ),
      );
    },
    [ask],
  );

  /**
   * Opening a sanga is opening its thread. Anybody already inside, and the
   * President or Tech Admin who may act on any sanga without joining, goes
   * straight there; the extra landing page in between was a tap that told
   * them nothing they did not already know.
   */
  const openSanga = useCallback(
    (sanga: SangaSummary) => {
      const params = { sangaId: sanga.id, name: sanga.name };
      navigation.navigate(
        sanga.is_member || mayReviewSangas ? "SangaChat" : "SangaDetail",
        params,
      );
    },
    [mayReviewSangas, navigation],
  );

  /**
   * Holding a sanga you are in. Leaving belongs here as well as on the sanga's
   * own page, because this list is where a devotee sees which circles they are
   * in — but it stays behind a hold, so browsing never puts a destructive
   * control under a thumb.
   *
   * Whoever runs a sanga is not offered it: a sanga must always have somebody
   * responsible for it, so they have to hand it on or close it, and both of
   * those live on its info page rather than in a menu over a list.
   */
  const manageSanga = useCallback(
    (sanga: SangaSummary) => {
      const actions: ActionSheetAction[] = [
        {
          label: "Open sanga",
          icon: "chatbubbles-outline",
          onPress: () => openSanga(sanga),
        },
      ];

      if (sanga.is_admin) {
        actions.push({
          label: "About this sanga",
          icon: "information-circle-outline",
          onPress: () =>
            navigation.navigate("SangaInfo", {
              sangaId: sanga.id,
              name: sanga.name,
            }),
        });
      } else {
        actions.push({
          label: "Leave this sanga",
          icon: "exit-outline",
          destructive: true,
          confirm: {
            title: `Leave ${sanga.name}?`,
            message: `You lose its thread and everything said in it, and you stop hearing what the group announces. You can ask to join again, and its admin answers.`,
            confirmLabel: "Leave",
          },
          onPress: () => {
            setSangaError(null);
            leave.mutate(
              { sangaId: sanga.id, selfId: activeUserId ?? undefined },
              {
                onError: (caught) =>
                  setSangaError(
                    errorMessage(caught, `You could not leave ${sanga.name}.`),
                  ),
              },
            );
          },
        });
      }

      setSangaSheet({
        title: sanga.name,
        message: sanga.is_admin
          ? `You run ${sanga.name}, and it cannot be left without somebody responsible for it. Hand it to another member first, or delete it — both are on its info page.`
          : undefined,
        actions,
      });
      setSangaSheetOpen(true);
    },
    // leave.mutate rather than the mutation: it is the stable half, and the
    // rows are memoised on this handler's identity.
    [activeUserId, leave.mutate, navigation, openSanga],
  );

  const rows: Row[] =
    section === "sanga"
      ? sangaRows
      : filteredConversations.map((conversation) => ({
          kind: "conversation" as const,
          id: conversation.id,
          conversation,
        }));

  /**
   * A search flattens the letters into one list: three results filed under
   * three headers is more chrome than answer.
   */
  const directorySections = useMemo(() => {
    if (!showList) return [];
    if (searching) return [{ letter: "", data: filteredDevotees }];
    return groupByInitial(filteredDevotees, (devotee) => devotee.name);
  }, [filteredDevotees, searching, showList]);

  const toggle = (
    <View className="mb-section flex-row gap-2">
      <SegmentButton
        label="Messages"
        selected={section === "messages"}
        badge={unreadThreads || undefined}
        onPress={() => selectSection("messages")}
      />
      <SegmentButton
        label="Sanga"
        selected={section === "sanga"}
        onPress={() => selectSection("sanga")}
      />
      <SegmentButton
        label="Directory"
        selected={section === "directory"}
        onPress={() => selectSection("directory")}
      />
    </View>
  );

  const sectionEmpty = () => {
    if (section === "messages") {
      if (conversations.isLoading) return <RowsSkeleton />;
      if (messagesFailed) {
        return (
          <LoadFailure
            reachable={reachable}
            message={errorMessage(
              conversations.error,
              "Your conversations could not be loaded.",
            )}
            onRetry={() => void conversations.refetch()}
          />
        );
      }
      if (searching) {
        return (
          <EmptyCard
            icon="chatbubbles-outline"
            title="No matching conversation"
            body="Try a shorter name, or open them from the Directory."
          />
        );
      }
      return <ConversationsEmpty />;
    }

    if (section === "sanga") {
      if (sangas.isLoading) return <SangaRowsSkeleton />;
      if (sangasFailed) {
        return (
          <LoadFailure
            reachable={reachable}
            message={errorMessage(sangas.error, "Sangas could not be loaded.")}
            onRetry={() => void sangas.refetch()}
          />
        );
      }
      // A search that matches nothing is not an offline symptom and must not
      // be dressed as one.
      if (searching) return <SangaEmpty searching />;
      return (
        <EmptyOrOffline
          reachable={reachable}
          loading={false}
          empty={<SangaEmpty searching={false} />}
        />
      );
    }

    if (dashboard.isLoading) return <RowsSkeleton />;
    if (directoryFailed) {
      return (
        <LoadFailure
          reachable={reachable}
          message={errorMessage(
            dashboard.error,
            "The directory could not be loaded.",
          )}
          onRetry={() => {
            void dashboard.refetch();
            void presence.refetch();
          }}
        />
      );
    }
    if (!showList) return null;
    return (
      <EmptyCard
        icon="people-outline"
        title={searching ? "No matching devotee" : "No devotee profiles yet"}
        body={
          searching
            ? "Try a different spelling or shorter name."
            : "New verified accounts will appear here."
        }
      />
    );
  };

  const listHeader = (
    <>
      <ScreenTitle eyebrow="Our community">Devotees</ScreenTitle>

      <AvatarViewer
        person={viewingPerson}
        onClose={() => setViewingPerson(null)}
      />

      <ActionSheet
        visible={sangaSheetOpen}
        title={sangaSheet?.title ?? ""}
        message={sangaSheet?.message}
        actions={sangaSheet?.actions ?? []}
        onClose={() => setSangaSheetOpen(false)}
      />

      {toggle}

      <View className="mb-section min-h-touch flex-row items-center rounded-button border border-border bg-white px-4">
        <Ionicons name="search" size={21} color={tokens.colors.stoneMuted} />
        <TextInput
          className="ml-3 flex-1 py-3 font-sans text-base text-stone"
          accessibilityLabel={searchFields[section].label}
          autoCapitalize="words"
          autoCorrect={false}
          placeholder={searchFields[section].placeholder}
          placeholderTextColor={tokens.colors.stoneMuted}
          value={search}
          onChangeText={setSearch}
        />
      </View>

      {section === "sanga" ? (
        <View className="mb-section gap-2">
          <Button
            variant="secondary"
            icon="add-circle-outline"
            onPress={() => navigation.navigate("CreateSanga")}
          >
            Start a sanga
          </Button>
          {mayReviewSangas ? (
            <Pressable
              className="min-h-touch flex-row items-center rounded-button border border-border bg-white px-4 py-2"
              accessibilityRole="button"
              accessibilityLabel={
                pendingSangaCount
                  ? `Sanga approvals, ${pendingSangaCount} waiting`
                  : "Sanga approvals"
              }
              onPress={() => navigation.navigate("SangaApprovals")}
            >
              <Ionicons
                name="shield-checkmark-outline"
                size={20}
                color={tokens.colors.indigo}
              />
              <Text className="ml-2 min-w-0 flex-1 font-sans-bold text-base text-indigo">
                Sanga approvals
              </Text>
              {pendingSangaCount ? (
                <View className="ml-2 min-w-[24px] shrink-0 items-center rounded-pill bg-marigold px-2 py-0.5">
                  <Text className="font-sans-bold text-xs text-stone">
                    {pendingSangaCount > 99 ? "99+" : pendingSangaCount}
                  </Text>
                </View>
              ) : (
                <Text className="ml-2 shrink-0 font-sans text-sm text-stoneMuted">
                  None waiting
                </Text>
              )}
              <Ionicons
                name="chevron-forward"
                size={18}
                color={tokens.colors.stoneMuted}
                style={{ marginLeft: 6 }}
              />
            </Pressable>
          ) : null}
        </View>
      ) : null}

      {chatError ? <FormError message={chatError} /> : null}
      {sangaError ? <FormError message={sangaError} /> : null}
    </>
  );

  const renderDevotee = (
    devotee: ServiceDevotee,
    isFirst: boolean,
    isLast: boolean,
  ) => {
    const isAtTemple = atTempleIds.has(devotee.id);
    const roleLabel = isAccessRole(devotee.role_name)
      ? accessRoleLabels[devotee.role_name]
      : "Devotee";

    return (
      <Pressable
        className={`min-h-[76px] flex-row items-center border-x border-border bg-white px-card py-3 ${
          isFirst ? "rounded-t-card border-t" : ""
        } ${isLast ? "rounded-b-card border-b" : "border-b"}`}
        accessibilityRole="button"
        accessibilityLabel={`Open ${devotee.name}'s profile, ${roleLabel}`}
        onPress={() =>
          navigation.navigate("DevoteeProfile", { devoteeId: devotee.id })
        }
      >
        <Avatar
          name={devotee.name}
          photoUrl={devotee.photo_url}
          tone={isAtTemple ? "peacock" : "indigo"}
          onPress={() =>
            setViewingPerson({
              name: devotee.name,
              photo_url: devotee.photo_url,
              subtitle: roleLabel,
            })
          }
        />
        <View className="ml-4 min-w-0 flex-1">
          <Text className="font-sans-bold text-lg text-stone" numberOfLines={2}>
            {devotee.name}
          </Text>
          <Text className="mt-0.5 font-sans text-sm text-stoneMuted">
            {roleLabel}
          </Text>
        </View>
        {isAtTemple ? <AtTempleBadge /> : null}
        <Pressable
          className="ml-2 h-11 w-11 items-center justify-center rounded-pill bg-indigoSoft"
          accessibilityRole="button"
          accessibilityLabel={`Message ${devotee.name}`}
          disabled={openingId === devotee.id}
          onPress={() => void startChat(devotee.id, devotee.name)}
        >
          <Ionicons
            name={
              openingId === devotee.id
                ? "ellipsis-horizontal"
                : "chatbubble-ellipses-outline"
            }
            size={20}
            color={tokens.colors.indigo}
          />
        </Pressable>
      </Pressable>
    );
  };

  // Remounting on the toggle sends the list back to the top, so switching
  // sections never lands halfway down a list the devotee has not scrolled.
  if (section === "directory") {
    return (
      <AlphabetIndexList
        key={section}
        sections={directorySections}
        keyExtractor={(devotee) => devotee.id}
        // Each letter is its own card, so rounding follows the group.
        renderItem={(devotee, index, group) =>
          renderDevotee(devotee, index === 0, index === group.data.length - 1)
        }
        grouped={!searching}
        header={listHeader}
        empty={sectionEmpty()}
      />
    );
  }

  return (
    <ListScreen
      key={section}
      data={rows}
      keyExtractor={(row) => `${row.kind}-${row.id}`}
      header={listHeader}
      renderItem={(row, index) => {
        if (row.kind === "heading") {
          return (
            <View className={index ? "mt-section" : ""}>
              <SectionHeader
                title={row.title}
                action={row.action}
                onAction={row.onAction}
              />
            </View>
          );
        }

        if (row.kind === "note") {
          return <SangaNote text={row.text} />;
        }

        if (row.kind === "sanga") {
          return (
            <SangaRow
              sanga={row.sanga}
              isFirst={row.isFirst}
              isLast={row.isLast}
              busy={askingSangaId === row.sanga.id}
              mayEnterWithoutJoining={mayReviewSangas}
              onPress={openSanga}
              onAsk={askToJoin}
              onLongPress={row.sanga.is_member ? manageSanga : undefined}
            />
          );
        }

        return (
          <ConversationRow
            row={row.conversation}
            viewerId={activeUserId}
            isFirst={index === 0}
            isLast={index === rows.length - 1}
            // The same presence the directory decorates its rows with: who you
            // are writing to is worth knowing before you ask where they are.
            atTemple={atTempleIds.has(row.conversation.other_devotee_id)}
            onPress={() =>
              navigation.navigate("Chat", {
                conversationId: row.conversation.id,
                devoteeId: row.conversation.other_devotee_id,
                name: row.conversation.other_name,
              })
            }
          />
        );
      }}
      empty={sectionEmpty()}
    />
  );
}
