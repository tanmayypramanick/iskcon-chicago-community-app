import { Ionicons } from "@expo/vector-icons";
import {
  useIsFocused,
  useNavigation,
  type NavigationProp,
} from "@react-navigation/native";
import * as Location from "expo-location";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { AppState, Pressable, ScrollView, Text, View } from "react-native";

import tokens from "../../design-tokens.json";
import {
  Avatar,
  AvatarViewer,
  GarlandDivider,
  InitialAvatar,
  LoadFailure,
  Screen,
  ScreenTitle,
  SectionHeader,
  Skeleton,
  SkeletonCard,
} from "../components/ui";
import { useCurrentAccessProfile } from "../features/access/hooks";
import {
  useAnnouncements,
  useToggleAnnouncementLike,
} from "../features/announcements/hooks";
import type { Announcement } from "../features/announcements/types";
import {
  useSetTemplePresence,
  useTemplePresence,
} from "../features/presence/hooks";
import { useAppNotifications } from "../features/notifications/hooks";
import type { TemplePresencePerson } from "../features/presence/types";
import { memberCountLabel } from "../features/sanga/components";
import { useMySangas } from "../features/sanga/hooks";
import type { MySangaSummary } from "../features/sanga/types";
import {
  errorMessage,
  formatDuration,
  formatServiceDate,
  formatServiceTime,
  isUpcomingService,
} from "../features/services/format";
import { useServiceDashboard } from "../features/services/hooks";
import {
  chicagoWallClockToInstant,
  formatChicagoDate,
  formatChicagoShortDate,
  getChicagoDateKey,
} from "../lib/chicagoDate";
import { useServerReachable } from "../lib/connectivity";
import { useNow } from "../lib/useNow";
import type { HomeStackParamList, MainTabParamList } from "../navigation/types";
import {
  getCurrentTempleProximity,
  startTempleGeofencingIfAllowed,
} from "../services/templeLocation";
import {
  initializeNotifications,
  registerPushToken,
  sendTempleArrivalReminder,
} from "../services/notifications";
import { usePrototypeSession } from "../store/usePrototypeSession";

const manualPresenceToggleLocks = new Map<string, number>();
const PRESENCE_TOGGLE_LOCK_MS = 350;

/** How many joined sangas and live notices Home shows before deferring. */
const HOME_SANGA_LIMIT = 2;
const HOME_ANNOUNCEMENT_LIMIT = 2;

/**
 * `list_my_sangas` carries no unread column yet, so this reads one defensively:
 * the moment the count lands on the row, a sanga with new messages outranks a
 * quiet one on Home. Until then every sanga scores zero and the server's own
 * order stands.
 */
function sangaUnreadCount(sanga: MySangaSummary) {
  return (
    (sanga as MySangaSummary & { unread_count?: number | null }).unread_count ??
    0
  );
}

type CommunityFeature = {
  title: string;
  detail: string;
  icon: keyof typeof Ionicons.glyphMap;
  iconClass: string;
  iconColor: string;
  route:
    | "Announcements"
    | "Feedback"
    | "DevoteeCare"
    | "Newsletter"
    | "Donations"
    | "SevaYatra";
};

/**
 * Only what a devotee can open right now — the route is required, so a card
 * here can never be a dead tap. Anything still being built belongs in
 * comingSoonFeatures instead.
 *
 * Six cards fill three even rows. Giving and Seva Yatra share the last one,
 * which is the right pairing: the leaderboard counts giving alongside seva, and
 * a devotee who taps one is often about to want the other.
 */
const communityFeatures: CommunityFeature[] = [
  {
    title: "Announcements",
    detail: "Temple updates in one clear place",
    icon: "megaphone-outline",
    iconClass: "bg-peacockSoft",
    iconColor: tokens.colors.peacock,
    route: "Announcements",
  },
  {
    title: "Devotee care",
    detail: "Ask for support and be looked after",
    icon: "heart-circle-outline",
    iconClass: "bg-vermilionSoft",
    iconColor: tokens.colors.vermilion,
    route: "DevoteeCare",
  },
  {
    title: "Newsletter",
    detail: "Monthly stories from our community",
    icon: "newspaper-outline",
    iconClass: "bg-marigoldSoft",
    iconColor: tokens.colors.stone,
    route: "Newsletter",
  },
  {
    title: "Feedback",
    detail: "Tell the temple what would help",
    icon: "chatbox-ellipses-outline",
    iconClass: "bg-indigoSoft",
    iconColor: tokens.colors.indigo,
    route: "Feedback",
  },
  {
    title: "Donations",
    detail: "Give, or sponsor a seva on a day of your own",
    icon: "gift-outline",
    iconClass: "bg-marigoldSoft",
    iconColor: tokens.colors.stone,
    route: "Donations",
  },
  {
    title: "Seva Yatra",
    detail: "Your seva profile, and the temple's leaderboard",
    icon: "trophy-outline",
    iconClass: "bg-marigoldSoft",
    iconColor: tokens.colors.marigold,
    route: "SevaYatra",
  },
];

type ComingSoonFeature = Pick<CommunityFeature, "title" | "detail" | "icon">;

/** Carries no colour and no route: these are not switched on yet, and naming
 * them plainly is better than a card that swallows a tap. */
const comingSoonFeatures: ComingSoonFeature[] = [
  {
    title: "Courses",
    detail: "Learn and grow in Krsna consciousness",
    icon: "book-outline",
  },
  {
    title: "Forum",
    detail: "Share thoughtful community discussions",
    icon: "chatbubbles-outline",
  },
];

function useCurrentChicagoDate() {
  const [now, setNow] = useState(() => new Date());

  useEffect(() => {
    const refreshDate = () => setNow(new Date());
    const timer = setInterval(refreshDate, 60_000);
    const subscription = AppState.addEventListener("change", (state) => {
      if (state === "active") refreshDate();
    });

    return () => {
      clearInterval(timer);
      subscription.remove();
    };
  }, []);

  return {
    dateKey: getChicagoDateKey(now),
    dateLabel: formatChicagoDate(now),
  };
}

function initials(name: string) {
  return (
    name
      .split(/\s+/)
      .filter(Boolean)
      .slice(0, 2)
      .map((part) => part[0]?.toUpperCase())
      .join("") || "HK"
  );
}

function PresencePreview({
  person,
  onOpen,
}: {
  person: TemplePresencePerson;
  onOpen: () => void;
}) {
  const firstName = person.name.trim().split(/\s+/)[0] || person.name;
  return (
    <View className="w-[72px] items-center">
      <Avatar
        name={person.name}
        photoUrl={person.photo_url}
        tone="peacock"
        onPress={onOpen}
      />
      <Text
        className="mt-1.5 w-full text-center font-sans-bold text-xs text-stone"
        numberOfLines={1}
      >
        {firstName}
      </Text>
    </View>
  );
}

/** The shape of the presence strip, so the wait reads as "people are coming". */
function PresenceStripSkeleton() {
  return (
    <View className="mb-section flex-row gap-2 px-1">
      {[0, 1, 2, 3].map((slot) => (
        <View key={slot} className="w-[72px] items-center">
          <View className="h-12 w-12 overflow-hidden rounded-pill">
            <Skeleton height={48} width={48} />
          </View>
          <View className="mt-1.5 w-11">
            <Skeleton height={10} />
          </View>
        </View>
      ))}
    </View>
  );
}

/** Rows in the shape of the real ones, so an unloaded list is never an empty
 * one. Two, because that is roughly what Home shows. */
function StackedRowsSkeleton({ rows = 2 }: { rows?: number }) {
  return (
    <View className="overflow-hidden rounded-card border border-border bg-white">
      {Array.from({ length: rows }, (_, slot) => (
        <View
          key={slot}
          className={`flex-row items-center px-card py-3 ${
            slot ? "border-t border-border" : ""
          }`}
        >
          <View className="h-9 w-9 overflow-hidden rounded-pill">
            <Skeleton height={36} width={36} />
          </View>
          <View className="ml-3 flex-1">
            <Skeleton height={16} width="58%" />
            <View className="mt-2">
              <Skeleton height={11} width="34%" />
            </View>
          </View>
        </View>
      ))}
    </View>
  );
}

/**
 * One joined sanga, compact. list_my_sangas carries no last-message column, so
 * the member count is the only activity Home can show without a round trip per
 * sanga — the thread itself is one tap away.
 */
function SangaPreviewRow({
  sanga,
  isFirst,
  isLast,
  onPress,
}: {
  sanga: MySangaSummary;
  isFirst: boolean;
  isLast: boolean;
  onPress: () => void;
}) {
  return (
    <Pressable
      className={`min-h-[60px] flex-row items-center border-x border-border bg-white px-card py-3 ${
        isFirst ? "rounded-t-card border-t" : ""
      } ${isLast ? "rounded-b-card border-b" : "border-b"}`}
      accessibilityRole="button"
      accessibilityLabel={`Open ${sanga.name} chat, ${memberCountLabel(sanga.member_count)}`}
      onPress={onPress}
    >
      <View className="h-9 w-9 items-center justify-center rounded-pill bg-peacockSoft">
        <Ionicons
          name="people-outline"
          size={18}
          color={tokens.colors.peacock}
        />
      </View>
      <View className="ml-3 min-w-0 flex-1">
        <Text className="font-sans-bold text-base text-stone" numberOfLines={1}>
          {sanga.name}
        </Text>
        <Text className="mt-0.5 font-sans text-xs text-stoneMuted">
          {memberCountLabel(sanga.member_count)}
        </Text>
      </View>
      <Ionicons
        name="chatbubble-outline"
        size={17}
        color={tokens.colors.stoneMuted}
      />
    </Pressable>
  );
}

/**
 * A snippet's two actions are icons at the right edge of the row, not the
 * board's bar beneath it: at two lines of notice, a full-width strip of
 * controls outweighs the words it belongs to.
 *
 * They sit outside the row's own Pressable rather than inside it: a heart
 * nested in a card-wide tap target is an argument about which press wins, and
 * on Android it is not always the inner one. Each reaches 44pt through hitSlop
 * — a min-width of 28 plus 8 either side, and 13 above and below an 18pt icon —
 * so a thumb-sized target costs the row no height. The 16pt between them is
 * exactly the two slops, so neither steals the other's press.
 */
function AnnouncementAction({
  icon,
  count,
  color,
  accessibilityLabel,
  selected,
  onPress,
}: {
  icon: keyof typeof Ionicons.glyphMap;
  count: number;
  color: string;
  accessibilityLabel: string;
  selected?: boolean;
  onPress: () => void;
}) {
  return (
    <Pressable
      className="min-w-[28px] flex-row items-center justify-center"
      accessibilityRole="button"
      accessibilityLabel={accessibilityLabel}
      accessibilityState={selected === undefined ? undefined : { selected }}
      hitSlop={{ top: 13, bottom: 13, left: 8, right: 8 }}
      onPress={onPress}
    >
      <Ionicons name={icon} size={18} color={color} />
      {count > 0 ? (
        <Text
          className="ml-1 font-sans-bold text-xs"
          style={{ color }}
          numberOfLines={1}
        >
          {count}
        </Text>
      ) : null}
    </Pressable>
  );
}

function AnnouncementPreviewRow({
  announcement,
  isFirst,
  isLast,
  onPress,
  onToggleLike,
  onOpenComments,
}: {
  announcement: Announcement;
  isFirst: boolean;
  isLast: boolean;
  onPress: () => void;
  onToggleLike: () => void;
  onOpenComments: () => void;
}) {
  const posted = formatChicagoShortDate(new Date(announcement.created_at));
  const meta = [posted, announcement.posted_by_name?.trim() || null]
    .filter(Boolean)
    .join(" · ");
  const liked = announcement.liked_by_me;
  const comments = announcement.comment_count;

  return (
    <View
      className={`flex-row items-center border-x border-border bg-white px-card py-3 ${
        isFirst ? "rounded-t-card border-t" : ""
      } ${isLast ? "rounded-b-card border-b" : "border-b"}`}
    >
      <Pressable
        className="min-w-0 flex-1 flex-row items-start"
        accessibilityRole="button"
        accessibilityLabel={`Announcement: ${announcement.title}`}
        onPress={onPress}
      >
        <View className="h-9 w-9 items-center justify-center rounded-pill bg-marigoldSoft">
          <Ionicons
            name="megaphone-outline"
            size={18}
            color={tokens.colors.stone}
          />
        </View>
        <View className="ml-3 min-w-0 flex-1">
          <Text
            className="font-sans-bold text-base text-stone"
            numberOfLines={2}
          >
            {announcement.title}
          </Text>
          <Text
            className="mt-0.5 font-sans text-sm leading-5 text-stoneMuted"
            numberOfLines={2}
          >
            {announcement.body}
          </Text>
          <Text className="mt-1 font-sans text-xs text-stoneMuted">{meta}</Text>
        </View>
      </Pressable>
      <View className="ml-2 flex-row items-center gap-4">
        <AnnouncementAction
          icon={liked ? "heart" : "heart-outline"}
          count={announcement.like_count}
          color={liked ? tokens.colors.vermilion : tokens.colors.stoneMuted}
          selected={liked}
          accessibilityLabel={
            liked
              ? `Unlike ${announcement.title}`
              : `Like ${announcement.title}`
          }
          onPress={onToggleLike}
        />
        <AnnouncementAction
          icon="chatbubble-outline"
          count={comments}
          color={tokens.colors.indigo}
          accessibilityLabel={
            comments === 0
              ? `Comment on ${announcement.title}`
              : `Read the ${comments} ${
                  comments === 1 ? "comment" : "comments"
                } on ${announcement.title}`
          }
          onPress={onOpenComments}
        />
      </View>
    </View>
  );
}

/** A quiet card offering a way in, for a section a devotee has nothing in. */
function InvitationCard({
  icon,
  iconClass,
  iconColor,
  title,
  detail,
  actionLabel,
  onPress,
}: {
  icon: keyof typeof Ionicons.glyphMap;
  iconClass: string;
  iconColor: string;
  title: string;
  detail: string;
  actionLabel: string;
  onPress: () => void;
}) {
  return (
    <Pressable
      className="flex-row items-center rounded-card border border-border bg-white px-card py-3.5"
      accessibilityRole="button"
      accessibilityLabel={actionLabel}
      onPress={onPress}
    >
      <View
        className={`h-10 w-10 items-center justify-center rounded-pill ${iconClass}`}
      >
        <Ionicons name={icon} size={20} color={iconColor} />
      </View>
      <View className="ml-3 min-w-0 flex-1">
        <Text className="font-sans-bold text-sm text-stone">{title}</Text>
        <Text className="mt-0.5 font-sans text-xs leading-4 text-stoneMuted">
          {detail}
        </Text>
      </View>
      <Ionicons
        name="chevron-forward"
        size={18}
        color={tokens.colors.stoneMuted}
      />
    </Pressable>
  );
}

/**
 * The same card, switched off: a View rather than a Pressable so there is no
 * tap to swallow, on the page's own ivory instead of a raised white surface,
 * with the icon drained of the colour that marks a live feature. The "Soon"
 * pill it carries is the one the grid used to show on unbuilt cards; it gains
 * a hairline only because sandalwood on ivory has none of its own.
 */
function ComingSoonCard({ feature }: { feature: ComingSoonFeature }) {
  return (
    <View
      className="min-h-[118px] min-w-[46%] flex-1 rounded-card border border-border bg-ivory p-3"
      accessible
      accessibilityLabel={`${feature.title}, coming soon`}
    >
      <View className="flex-row items-start justify-between">
        <View className="h-9 w-9 items-center justify-center rounded-pill bg-sandalwood">
          <Ionicons
            name={feature.icon}
            size={19}
            color={tokens.colors.stoneMuted}
          />
        </View>
        <View className="rounded-pill border border-border bg-sandalwood px-2 py-0.5">
          <Text className="font-sans-bold text-[10px] uppercase tracking-wide text-stoneMuted">
            Soon
          </Text>
        </View>
      </View>
      <Text className="mt-3 font-sans-bold text-base text-stoneMuted">
        {feature.title}
      </Text>
      <Text className="mt-1 font-sans text-xs leading-4 text-stoneMuted">
        {feature.detail}
      </Text>
    </View>
  );
}

export function HomeScreen() {
  const navigation = useNavigation<NavigationProp<HomeStackParamList>>();
  const isFocused = useIsFocused();
  const { dateKey, dateLabel } = useCurrentChicagoDate();
  const activeUserId = usePrototypeSession((state) => state.activeUserId);
  const profile = useCurrentAccessProfile(activeUserId);
  const presence = useTemplePresence(activeUserId);
  const setPresence = useSetTemplePresence(activeUserId);
  const now = useNow();
  const [viewingPerson, setViewingPerson] = useState<{
    name: string;
    photo_url?: string | null;
    subtitle?: string;
  } | null>(null);
  const services = useServiceDashboard(activeUserId);
  const appNotifications = useAppNotifications(activeUserId);
  const mySangas = useMySangas(Boolean(activeUserId));
  // Home shows only the newest few; the shared cache means opening the board
  // itself costs nothing. It is the same query key the board reads, so a like
  // left here is already on the board by the time it is opened.
  const announcements = useAnnouncements(Boolean(activeUserId));
  const toggleAnnouncementLike = useToggleAnnouncementLike();
  const reachable = useServerReachable();
  const [hasForegroundPermission, setHasForegroundPermission] = useState(false);
  const [toastMessage, setToastMessage] = useState<string | null>(null);
  const permissionInitialized = useRef(false);
  const locationCheckInFlight = useRef(false);
  const toastTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const currentPresence = presence.data?.current;
  const isAtTemple = Boolean(
    currentPresence?.presence_date === dateKey && currentPresence.is_at_temple,
  );
  const peopleAtTemple = presence.data?.people ?? [];
  const localUnreadCount = usePrototypeSession((state) =>
    activeUserId
      ? (state.notificationsByUser[activeUserId] ?? []).filter(
          (notification) => !notification.isRead,
        ).length
      : 0,
  );
  const unreadNotificationCount =
    localUnreadCount +
    (appNotifications.data ?? []).filter(
      (notification) => !notification.read_at,
    ).length;
  const firstName = profile.data?.name.trim().split(/\s+/)[0] ?? "";
  // "Next" means it has not finished yet. Comparing the date alone left a
  // seva that ended at 3 AM sitting here as the devotee's next seva all day.
  const nextService = useMemo(
    () =>
      services.data?.services.find((service) => {
        if (["completed", "cancelled"].includes(service.status)) return false;
        if (!service.currentUserAssignment) return false;
        const endsAt =
          chicagoWallClockToInstant(
            service.date,
            service.start_time,
          ).getTime() +
          service.duration_minutes * 60_000;
        return endsAt > now.getTime();
      }) ?? null,
    [now, services.data?.services],
  );

  // Only sangas the devotee is actually inside: list_my_sangas also returns the
  // ones they proposed and the President has not answered, and a pending sanga
  // has no thread to open.
  const joinedSangas = useMemo(
    () =>
      (mySangas.data ?? [])
        .filter(
          (sanga) =>
            sanga.is_member && sanga.status === "approved" && sanga.active,
        )
        // The index tie-break keeps the server's order among sangas that are
        // equally unread, rather than trusting sort() to be stable.
        .map((sanga, index) => ({ sanga, index }))
        .sort(
          (a, b) =>
            sangaUnreadCount(b.sanga) - sangaUnreadCount(a.sanga) ||
            a.index - b.index,
        )
        .slice(0, HOME_SANGA_LIMIT)
        .map((entry) => entry.sanga),
    [mySangas.data],
  );
  const latestAnnouncements = useMemo(
    () => (announcements.data ?? []).slice(0, HOME_ANNOUNCEMENT_LIMIT),
    [announcements.data],
  );

  const showToast = useCallback((message: string) => {
    if (toastTimer.current) clearTimeout(toastTimer.current);
    setToastMessage(message);
    toastTimer.current = setTimeout(() => {
      setToastMessage(null);
      toastTimer.current = null;
    }, 1_000);
  }, []);

  useEffect(
    () => () => {
      if (toastTimer.current) clearTimeout(toastTimer.current);
    },
    [],
  );

  // Registration is retried on its own rather than riding along with the
  // one-shot permission prompt below: a device that failed once — no network
  // at launch, permission granted afterwards — would otherwise stay unable to
  // receive anything until the app was killed and reopened.
  useEffect(() => {
    if (!activeUserId) return;
    let active = true;
    let attempt = 0;

    const tryRegister = async () => {
      const result = await registerPushToken();
      if (!active || result.ok) return;
      if (__DEV__) {
        console.warn(`[push] not registered: ${result.reason}`);
      }
      // A permission the devotee has not granted is a decision, not a fault,
      // so it is left alone. Anything else is worth a few backing-off tries.
      if (result.reason.includes("allowed notifications")) return;
      if (attempt >= 3) return;
      attempt += 1;
      setTimeout(tryRegister, attempt * 5000);
    };

    void tryRegister();
    return () => {
      active = false;
    };
  }, [activeUserId]);

  useEffect(() => {
    if (!activeUserId || permissionInitialized.current) return;
    permissionInitialized.current = true;
    let active = true;

    const requestLocationAccess = async () => {
      try {
        await initializeNotifications(activeUserId);
        let foregroundPermission =
          await Location.getForegroundPermissionsAsync();

        if (!foregroundPermission.granted && foregroundPermission.canAskAgain) {
          foregroundPermission =
            await Location.requestForegroundPermissionsAsync();
        }

        if (!active) return;
        setHasForegroundPermission(foregroundPermission.granted);
        if (!foregroundPermission.granted) return;

        const backgroundPermission =
          await Location.getBackgroundPermissionsAsync();
        if (backgroundPermission.granted) {
          await startTempleGeofencingIfAllowed();
        }
      } catch {
        // Manual check-in remains available if system permissions are denied.
      }
    };

    void requestLocationAccess();
    return () => {
      active = false;
    };
  }, [activeUserId]);

  const runLocationCheck = useCallback(async () => {
    if (!activeUserId || locationCheckInFlight.current) return;
    locationCheckInFlight.current = true;
    try {
      const proximity = await getCurrentTempleProximity();
      if (!proximity.isAccurateEnough || !proximity.isInside) return;
      await sendTempleArrivalReminder(activeUserId);
    } catch {
      // Location only triggers a reminder; it never silently checks someone in.
    } finally {
      locationCheckInFlight.current = false;
    }
  }, [activeUserId]);

  useEffect(() => {
    if (!isFocused || !activeUserId || !hasForegroundPermission) return;
    void runLocationCheck();
  }, [activeUserId, hasForegroundPermission, isFocused, runLocationCheck]);

  useEffect(() => {
    if (!isFocused || !activeUserId) return;
    void Promise.all([
      presence.refetch(),
      services.refetch(),
      appNotifications.refetch(),
      profile.refetch(),
      mySangas.refetch(),
      announcements.refetch(),
    ]);
  }, [
    activeUserId,
    announcements.refetch,
    appNotifications.refetch,
    isFocused,
    mySangas.refetch,
    presence.refetch,
    profile.refetch,
    services.refetch,
  ]);

  const openServices = useCallback(
    (screen: "ServicesHome" | "ServiceDetail", serviceId?: string) => {
      const tabs = navigation.getParent<NavigationProp<MainTabParamList>>();
      if (screen === "ServiceDetail" && serviceId) {
        tabs?.navigate("Services", {
          screen,
          params: { serviceId },
        });
        return;
      }
      tabs?.navigate("Services", { screen: "ServicesHome" });
    },
    [navigation],
  );

  // Sangas live in the Devotees tab, so reaching one means hopping stacks
  // through the tab navigator — the same route NotificationsScreen takes.
  const openDevotees = useCallback(
    (params: { screen: string; params?: Record<string, unknown> }) => {
      const tabs = navigation.getParent<NavigationProp<MainTabParamList>>();
      tabs?.navigate("Devotees", params as never);
    },
    [navigation],
  );

  const openSangaChat = useCallback(
    (sanga: MySangaSummary) =>
      openDevotees({
        screen: "SangaChat",
        params: { sangaId: sanga.id, name: sanga.name },
      }),
    [openDevotees],
  );

  const browseSangas = useCallback(
    () =>
      openDevotees({ screen: "DevoteesHome", params: { section: "sanga" } }),
    [openDevotees],
  );

  useEffect(() => {
    const subscription = AppState.addEventListener("change", (state) => {
      if (state === "active" && isFocused && hasForegroundPermission) {
        void runLocationCheck();
      }
    });
    return () => subscription.remove();
  }, [hasForegroundPermission, isFocused, runLocationCheck]);

  const toggleManualPresence = () => {
    if (!activeUserId) return;
    // A short guard against a double-tap on one press. It used to be three
    // seconds, which swallowed genuine taps and made the switch feel dead.
    const now = Date.now();
    const lastToggle = manualPresenceToggleLocks.get(activeUserId) ?? 0;
    if (now - lastToggle < PRESENCE_TOGGLE_LOCK_MS) return;
    manualPresenceToggleLocks.set(activeUserId, now);
    const nextValue = !isAtTemple;
    // The toast fires with the tap, matching the optimistic switch, instead of
    // waiting on the network.
    showToast(nextValue ? "Checked in at the temple" : "Check-out saved");
    setPresence.mutate({
      isAtTemple: nextValue,
      source: "manual",
      selfName: profile.data?.name,
      selfPhotoUrl: profile.data?.photo_url ?? null,
    });
  };

  // A failed read now speaks for itself inside the presence section, so this
  // banner is only ever about a check-in that did not reach the temple.
  const presenceError = errorMessage(
    setPresence.error,
    "Something went wrong.",
  );
  // A refetch that fails while yesterday's answer is still cached is not worth
  // reporting — React Query keeps the data and tries again. Only a section
  // left with nothing gets a failure state.
  const presenceFailed = presence.isError && presence.data === undefined;
  const servicesFailed = services.isError && services.data === undefined;
  const sangasFailed = mySangas.isError && mySangas.data === undefined;
  const announcementsFailed =
    announcements.isError && announcements.data === undefined;

  return (
    <View className="flex-1 bg-ivory">
      <AvatarViewer
        person={viewingPerson}
        onClose={() => setViewingPerson(null)}
      />
      <Screen>
        <ScreenTitle
          eyebrow={dateLabel}
          action={
            <Pressable
              className="relative h-10 w-10 items-center justify-center rounded-pill border border-border bg-white"
              accessibilityRole="button"
              accessibilityLabel="Notifications"
              onPress={() => navigation.navigate("Notifications")}
            >
              <Ionicons
                name="notifications-outline"
                size={21}
                color={tokens.colors.indigo}
              />
              {unreadNotificationCount ? (
                <View className="absolute -right-0.5 -top-0.5 min-h-4 min-w-4 items-center justify-center rounded-pill bg-vermilion px-1">
                  <Text className="font-sans-bold text-[10px] text-white">
                    {Math.min(unreadNotificationCount, 9)}
                    {unreadNotificationCount > 9 ? "+" : ""}
                  </Text>
                </View>
              ) : null}
            </Pressable>
          }
        >
          {firstName ? `Hare Krsna, ${firstName}!` : "Hare Krsna!"}
        </ScreenTitle>

        <Pressable
          className={`mb-section min-h-[72px] flex-row items-center rounded-card border px-card py-3 ${
            isAtTemple
              ? "border-peacock bg-peacock"
              : "border-border bg-indigoSoft"
          }`}
          accessibilityRole="switch"
          accessibilityLabel="At the temple"
          accessibilityHint="Double tap to check in or check out"
          // Not disabled while the write is in flight: the optimistic value is
          // already correct, so blocking the control only makes it feel slow.
          accessibilityState={{ checked: isAtTemple, disabled: !activeUserId }}
          disabled={!activeUserId}
          onPress={toggleManualPresence}
        >
          <View
            className={`mr-3 h-9 w-9 flex-shrink-0 items-center justify-center rounded-pill ${
              isAtTemple ? "bg-white/20" : "bg-white"
            }`}
          >
            <Ionicons
              name={isAtTemple ? "location" : "location-outline"}
              size={20}
              color={isAtTemple ? tokens.colors.white : tokens.colors.indigo}
            />
          </View>
          <View className="min-w-0 flex-1 pr-3">
            <Text
              className={`font-sans-bold text-base leading-5 ${
                isAtTemple ? "text-white" : "text-indigo"
              }`}
              numberOfLines={2}
            >
              {isAtTemple ? "You’re at the temple" : "Check in at the temple"}
            </Text>
            <Text
              className={`font-sans text-xs ${
                isAtTemple ? "text-white" : "text-stoneMuted"
              }`}
              numberOfLines={2}
            >
              {isAtTemple
                ? "Tap when you leave"
                : "Let the community know you’re here"}
            </Text>
          </View>
          <View
            pointerEvents="none"
            className={`h-7 w-12 flex-shrink-0 justify-center rounded-pill px-1 ${
              isAtTemple ? "bg-marigoldSoft" : "bg-indigo"
            }`}
          >
            <View
              className={`h-5 w-5 rounded-pill bg-white shadow-sm ${
                isAtTemple ? "translate-x-5" : "translate-x-0"
              }`}
            />
          </View>
        </Pressable>

        {presenceError ? (
          <View className="mb-section rounded-button border border-vermilion bg-white px-4 py-3">
            <Text className="font-sans-bold text-sm text-vermilion">
              Check-in could not sync
            </Text>
            <Text className="mt-1 font-sans text-sm text-stoneMuted">
              {presenceError}
            </Text>
          </View>
        ) : null}

        <SectionHeader
          title="At the temple today"
          action="See all"
          onAction={() => navigation.navigate("TempleToday")}
        />
        {presence.isLoading ? (
          <PresenceStripSkeleton />
        ) : presenceFailed ? (
          <View className="mb-section">
            <LoadFailure
              reachable={reachable}
              message={errorMessage(
                presence.error,
                "Today’s temple presence could not be loaded.",
              )}
              onRetry={() => void presence.refetch()}
            />
          </View>
        ) : peopleAtTemple.length ? (
          <ScrollView
            horizontal
            className="mb-section"
            contentContainerClassName="gap-2 px-1 pb-1"
            showsHorizontalScrollIndicator={false}
          >
            {peopleAtTemple.slice(0, 8).map((person) => (
              <PresencePreview
                key={person.user_id}
                person={person}
                onOpen={() =>
                  setViewingPerson({
                    name: person.name,
                    photo_url: person.photo_url,
                    subtitle: "At the temple today",
                  })
                }
              />
            ))}
          </ScrollView>
        ) : (
          <View className="mb-section flex-row items-center rounded-card border border-border bg-white px-card py-3">
            <View className="h-10 w-10 items-center justify-center rounded-pill bg-sandalwood">
              <Ionicons
                name="people-outline"
                size={20}
                color={tokens.colors.indigo}
              />
            </View>
            <View className="ml-3 min-w-0 flex-1">
              <Text className="font-sans-bold text-sm text-stone">
                No one is listed yet
              </Text>
              <Text className="mt-0.5 font-sans text-xs text-stoneMuted">
                Today’s temple community will appear here live.
              </Text>
            </View>
          </View>
        )}

        <SectionHeader
          title="Your next seva"
          action="See seva"
          onAction={() => openServices("ServicesHome")}
        />
        {services.isLoading ? (
          <SkeletonCard />
        ) : servicesFailed ? (
          <LoadFailure
            reachable={reachable}
            message={errorMessage(
              services.error,
              "Your seva schedule could not be loaded.",
            )}
            onRetry={() => void services.refetch()}
          />
        ) : nextService ? (
          <Pressable
            className="rounded-card bg-indigo px-card py-3"
            accessibilityRole="button"
            accessibilityLabel={`Open ${nextService.name}`}
            onPress={() => openServices("ServiceDetail", nextService.id)}
          >
            <View className="mb-2 flex-row items-start justify-between">
              <View className="max-w-[82%] rounded-pill bg-white/15 px-2.5 py-1">
                <Text
                  className="font-sans-bold text-xs text-white"
                  numberOfLines={2}
                >
                  {formatServiceDate(nextService.date)} ·{" "}
                  {formatServiceTime(nextService.start_time)}
                </Text>
              </View>
              <Ionicons
                name="heart"
                size={19}
                color={tokens.colors.marigoldSoft}
              />
            </View>
            <Text className="font-display text-lg text-white">
              {nextService.name}
            </Text>
            <Text className="mt-1 font-sans text-sm text-white">
              {formatDuration(nextService.duration_minutes)} ·{" "}
              {nextService.filledSlots} of {nextService.slots_needed} serving
            </Text>
          </Pressable>
        ) : (
          <View className="rounded-card border border-border bg-white p-card">
            <View className="flex-row items-center">
              <View className="h-11 w-11 items-center justify-center rounded-pill bg-marigoldSoft">
                <Ionicons
                  name="heart-outline"
                  size={22}
                  color={tokens.colors.stone}
                />
              </View>
              <View className="ml-3 min-w-0 flex-1">
                <Text className="font-sans-bold text-base text-stone">
                  No upcoming seva assigned
                </Text>
                <Text className="mt-1 font-sans text-sm text-stoneMuted">
                  Open seva requests are waiting in Seva.
                </Text>
              </View>
            </View>
          </View>
        )}

        <View className="mt-section">
          <SectionHeader
            title="Announcements"
            action="See all"
            onAction={() => navigation.navigate("Announcements")}
          />
          {announcements.isLoading ? (
            <StackedRowsSkeleton />
          ) : announcementsFailed ? (
            <LoadFailure
              reachable={reachable}
              message={errorMessage(
                announcements.error,
                "The noticeboard could not be loaded.",
              )}
              onRetry={() => void announcements.refetch()}
            />
          ) : latestAnnouncements.length ? (
            <View>
              {latestAnnouncements.map((announcement, index) => (
                <AnnouncementPreviewRow
                  key={announcement.id}
                  announcement={announcement}
                  isFirst={index === 0}
                  isLast={index === latestAnnouncements.length - 1}
                  onPress={() => navigation.navigate("Announcements")}
                  // Nothing is awaited and nothing is reported, as on the board:
                  // the heart has already moved, and a like that could not be
                  // saved puts itself back rather than interrupting Home.
                  onToggleLike={() =>
                    toggleAnnouncementLike.mutate(announcement.id)
                  }
                  onOpenComments={() =>
                    navigation.navigate("AnnouncementComments", {
                      announcementId: announcement.id,
                      title: announcement.title,
                    })
                  }
                />
              ))}
            </View>
          ) : (
            <InvitationCard
              icon="megaphone-outline"
              iconClass="bg-marigoldSoft"
              iconColor={tokens.colors.stone}
              title="Nothing on the board"
              detail="Temple notices will appear here as they are posted."
              actionLabel="Open announcements"
              onPress={() => navigation.navigate("Announcements")}
            />
          )}
        </View>

        <View className="mt-section">
          <SectionHeader
            title="Your sangas"
            action="See all"
            onAction={browseSangas}
          />
          {mySangas.isLoading ? (
            <StackedRowsSkeleton />
          ) : sangasFailed ? (
            <LoadFailure
              reachable={reachable}
              message={errorMessage(
                mySangas.error,
                "Your sangas could not be loaded.",
              )}
              onRetry={() => void mySangas.refetch()}
            />
          ) : joinedSangas.length ? (
            <View>
              {joinedSangas.map((sanga, index) => (
                <SangaPreviewRow
                  key={sanga.id}
                  sanga={sanga}
                  isFirst={index === 0}
                  isLast={index === joinedSangas.length - 1}
                  onPress={() => openSangaChat(sanga)}
                />
              ))}
            </View>
          ) : (
            <InvitationCard
              icon="people-circle-outline"
              iconClass="bg-peacockSoft"
              iconColor={tokens.colors.peacock}
              title="You’re not in a sanga yet"
              detail="Browse the circles devotees gather in and ask to join one."
              actionLabel="Browse sangas"
              onPress={browseSangas}
            />
          )}
        </View>

        <View className="mt-section">
          <SectionHeader title="Explore the community" />
          <View className="flex-row flex-wrap gap-3">
            {communityFeatures.map((feature) => (
              <Pressable
                key={feature.title}
                className="min-h-[118px] min-w-[46%] flex-1 rounded-card border border-border bg-white p-3"
                accessibilityRole="button"
                accessibilityLabel={feature.title}
                onPress={() => navigation.navigate(feature.route)}
              >
                <View
                  className={`h-9 w-9 items-center justify-center rounded-pill ${feature.iconClass}`}
                >
                  <Ionicons
                    name={feature.icon}
                    size={19}
                    color={feature.iconColor}
                  />
                </View>
                <Text className="mt-3 font-sans-bold text-base text-stone">
                  {feature.title}
                </Text>
                <Text className="mt-1 font-sans text-xs leading-4 text-stoneMuted">
                  {feature.detail}
                </Text>
              </Pressable>
            ))}
          </View>
        </View>

        <View className="mt-section">
          <SectionHeader
            title="Coming soon"
            subtitle="Being built now — they’ll open here once they’re ready."
          />
          <View className="flex-row flex-wrap gap-3">
            {comingSoonFeatures.map((feature) => (
              <ComingSoonCard key={feature.title} feature={feature} />
            ))}
          </View>
        </View>

        <GarlandDivider />
        <View className="items-center px-4 pb-2">
          <Ionicons
            name="leaf-outline"
            size={24}
            color={tokens.colors.peacock}
          />
          <Text className="mt-2 text-center font-display-italic text-lg leading-7 text-stoneMuted">
            Every offering of seva brings our community closer in Krsna
            consciousness.
          </Text>
        </View>
      </Screen>

      {toastMessage ? (
        <View
          pointerEvents="none"
          className="absolute bottom-4 left-5 right-5 items-center"
          accessibilityLiveRegion="polite"
        >
          <View className="max-w-[340px] flex-row items-center rounded-pill bg-indigo px-4 py-2.5 shadow-sm">
            <Ionicons
              name="location"
              size={15}
              color={tokens.colors.marigoldSoft}
            />
            <Text className="ml-2 flex-shrink font-sans-bold text-xs text-white">
              {toastMessage}
            </Text>
          </View>
        </View>
      ) : null}
    </View>
  );
}
