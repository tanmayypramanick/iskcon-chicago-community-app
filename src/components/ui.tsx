import { Ionicons } from "@expo/vector-icons";
import React, { type PropsWithChildren, type ReactNode } from "react";
import {
  Animated,
  FlatList,
  Image,
  Modal,
  Pressable,
  ScrollView,
  Text,
  View,
  type PressableProps,
} from "react-native";
import {
  SafeAreaView,
  useSafeAreaInsets,
} from "react-native-safe-area-context";

import tokens from "../../design-tokens.json";
import { BotanicalBackdrop, GarlandRule } from "./botanical";

type ScreenProps = PropsWithChildren<{
  scroll?: boolean;
  bottomInset?: boolean;
  topInset?: boolean;
}>;

export { BotanicalBackdrop, GarlandRule };

export function Screen({
  children,
  scroll = true,
  bottomInset = true,
  topInset = true,
}: ScreenProps) {
  if (!scroll) {
    return (
      <SafeAreaView className="flex-1 bg-ivory" edges={topInset ? ["top"] : []}>
        <BotanicalBackdrop />
        <View className="flex-1 px-screen">{children}</View>
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView className="flex-1 bg-ivory" edges={topInset ? ["top"] : []}>
      <BotanicalBackdrop />
      <ScrollView
        className="flex-1"
        contentContainerClassName={`px-screen pt-2 ${bottomInset ? "pb-24" : "pb-6"}`}
        showsVerticalScrollIndicator={false}
        // On a long form the keyboard covers the choice being made. Without
        // this, the tap that reaches past it only dismisses the keyboard and
        // the button underneath is never pressed.
        keyboardShouldPersistTaps="handled"
      >
        {children}
      </ScrollView>
    </SafeAreaView>
  );
}

/**
 * A screen whose body is one long list. Screen's ScrollView renders every
 * child up front, so a devotee with months of seva history paid for all of it
 * on every render; this keeps the same chrome and only mounts what is near the
 * viewport. Everything above the list goes in `header`.
 */
export function ListScreen<Item>({
  data,
  renderItem,
  keyExtractor,
  header,
  empty,
  footer,
  bottomInset = true,
  topInset = true,
  refreshControl,
}: {
  data: readonly Item[];
  renderItem: (item: Item, index: number) => ReactNode;
  keyExtractor: (item: Item, index: number) => string;
  header?: ReactNode;
  empty?: ReactNode;
  footer?: ReactNode;
  bottomInset?: boolean;
  topInset?: boolean;
  refreshControl?: ReactNode;
}) {
  return (
    <SafeAreaView className="flex-1 bg-ivory" edges={topInset ? ["top"] : []}>
      <BotanicalBackdrop />
      <FlatList
        className="flex-1"
        data={data as Item[]}
        keyExtractor={keyExtractor}
        renderItem={({ item, index }) => <>{renderItem(item, index)}</>}
        ListHeaderComponent={header ? <>{header}</> : null}
        ListEmptyComponent={empty ? <>{empty}</> : null}
        ListFooterComponent={footer ? <>{footer}</> : null}
        contentContainerClassName={`px-screen pt-2 ${bottomInset ? "pb-24" : "pb-6"}`}
        showsVerticalScrollIndicator={false}
        keyboardShouldPersistTaps="handled"
        initialNumToRender={12}
        maxToRenderPerBatch={12}
        windowSize={11}
        removeClippedSubviews={false}
        refreshControl={refreshControl as never}
      />
    </SafeAreaView>
  );
}

/**
 * The connection bar, pinned above everything including the status bar area.
 *
 * It says three things a devotee needs and nothing else: that they are
 * offline, that what they are looking at is still real, and that it will fix
 * itself. It also confirms reconnection for a moment rather than vanishing
 * silently, so the recovery is visible.
 */
export function ConnectionBar({ reachable }: { reachable: boolean }) {
  const insets = useSafeAreaInsets();
  const [showRestored, setShowRestored] = React.useState(false);
  const wasOffline = React.useRef(false);

  React.useEffect(() => {
    if (!reachable) {
      wasOffline.current = true;
      setShowRestored(false);
      return;
    }
    if (!wasOffline.current) return;
    wasOffline.current = false;
    setShowRestored(true);
    const timer = setTimeout(() => setShowRestored(false), 2600);
    return () => clearTimeout(timer);
  }, [reachable]);

  if (reachable && !showRestored) return null;

  return (
    <View
      className={reachable ? "bg-peacock" : "bg-stone"}
      style={{ paddingTop: insets.top }}
      accessibilityLiveRegion="polite"
    >
      <View className="flex-row items-center justify-center px-4 py-2">
        <Ionicons
          name={reachable ? "cloud-done-outline" : "cloud-offline-outline"}
          size={16}
          color={tokens.colors.white}
        />
        <Text className="ml-2 font-sans-bold text-xs text-white">
          {reachable
            ? "Back online"
            : "No connection — showing your last saved seva"}
        </Text>
      </View>
    </View>
  );
}


/**
 * A placeholder that reads as "not loaded yet".
 *
 * The distinction matters more than it looks: an empty list and an unloaded
 * list look identical, and a devotee offline was being told the temple had
 * nothing on. A pulsing block says the opposite — something is coming.
 */
export function Skeleton({
  height = 16,
  width,
  className = "",
}: {
  height?: number;
  width?: number | string;
  className?: string;
}) {
  const pulse = React.useRef(new Animated.Value(0.35)).current;

  React.useEffect(() => {
    const loop = Animated.loop(
      Animated.sequence([
        Animated.timing(pulse, {
          toValue: 0.75,
          duration: 850,
          useNativeDriver: true,
        }),
        Animated.timing(pulse, {
          toValue: 0.35,
          duration: 850,
          useNativeDriver: true,
        }),
      ]),
    );
    loop.start();
    return () => loop.stop();
  }, [pulse]);

  return (
    <Animated.View
      className={`rounded-button bg-sandalwood ${className}`}
      style={{ height, width: (width as number | undefined) ?? "100%", opacity: pulse }}
      accessibilityElementsHidden
      importantForAccessibility="no-hide-descendants"
    />
  );
}

/** A card-shaped placeholder, matching the app's real cards. */
export function SkeletonCard() {
  return (
    <View className="rounded-card border border-border bg-white p-card">
      <Skeleton height={14} width="42%" />
      <View className="mt-3">
        <Skeleton height={20} width="72%" />
      </View>
      <View className="mt-3">
        <Skeleton height={14} width="55%" />
      </View>
    </View>
  );
}

/** A calm, unhurried whole-screen wait. Deliberately not a spinner. */
export function LoadingState({ label = "Loading…" }: { label?: string }) {
  const pulse = React.useRef(new Animated.Value(0.5)).current;

  React.useEffect(() => {
    const loop = Animated.loop(
      Animated.sequence([
        Animated.timing(pulse, { toValue: 1, duration: 1100, useNativeDriver: true }),
        Animated.timing(pulse, { toValue: 0.5, duration: 1100, useNativeDriver: true }),
      ]),
    );
    loop.start();
    return () => loop.stop();
  }, [pulse]);

  return (
    <View className="items-center rounded-card border border-border bg-white px-card py-10">
      <Animated.View style={{ opacity: pulse }}>
        <View className="h-14 w-14 items-center justify-center rounded-pill bg-peacockSoft">
          <Ionicons name="leaf-outline" size={26} color={tokens.colors.peacock} />
        </View>
      </Animated.View>
      <Text className="mt-4 font-sans text-base text-stoneMuted">{label}</Text>
    </View>
  );
}

/**
 * Why a section that should have content has none.
 *
 * Offline and broken ask different things of a devotee — one clears itself,
 * the other wants another try — so they must not look the same, and neither
 * may look like "the temple has nothing on".
 */
export function LoadFailure({
  reachable,
  message,
  onRetry,
}: {
  reachable: boolean;
  message?: string | null;
  onRetry?: () => void;
}) {
  const offline = !reachable;

  return (
    <View className="items-center rounded-card border border-border bg-white px-card py-9">
      <View
        className={`h-14 w-14 items-center justify-center rounded-pill ${
          offline ? "bg-sandalwood" : "bg-marigoldSoft"
        }`}
      >
        <Ionicons
          name={offline ? "cloud-offline-outline" : "alert-circle-outline"}
          size={26}
          color={offline ? tokens.colors.stone : tokens.colors.vermilion}
        />
      </View>
      <Text className="mt-4 text-center font-sans-bold text-base text-stone">
        {offline ? "You’re offline" : "This could not be loaded"}
      </Text>
      <Text className="mt-2 max-w-80 text-center font-sans text-sm leading-6 text-stoneMuted">
        {offline
          ? "It will fill in on its own as soon as you are connected again."
          : message?.trim() || "Something went wrong reaching the temple."}
      </Text>
      {!offline && onRetry ? (
        <View className="mt-4">
          <Button variant="secondary" icon="refresh" onPress={onRetry}>
            Retry
          </Button>
        </View>
      ) : null}
    </View>
  );
}

/**
 * Chooses honestly between "still loading", "we cannot reach the temple", and
 * "there is genuinely nothing here". Those three used to look the same.
 */
export function EmptyOrOffline({
  reachable,
  loading,
  empty,
  loadingLabel,
}: {
  reachable: boolean;
  loading: boolean;
  empty: ReactNode;
  loadingLabel?: string;
}) {
  if (loading) return <LoadingState label={loadingLabel} />;
  if (!reachable) return <LoadFailure reachable={false} />;
  return <>{empty}</>;
}

export function ScreenTitle({
  eyebrow,
  children,
  action,
}: PropsWithChildren<{ eyebrow?: string; action?: ReactNode }>) {
  return (
    <View className="mb-section flex-row items-end justify-between">
      <View className="flex-1 pr-4">
        {eyebrow ? (
          <Text className="mb-0.5 font-sans-bold text-xs uppercase tracking-widest text-peacock">
            {eyebrow}
          </Text>
        ) : null}
        <Text
          className="font-display text-[26px] leading-8 text-stone"
          accessibilityRole="header"
          numberOfLines={2}
        >
          {children}
        </Text>
      </View>
      {action}
    </View>
  );
}

export function SectionHeader({
  title,
  subtitle,
  action,
  onAction,
}: {
  title: string;
  /** Narrows what the section is showing, e.g. which day. */
  subtitle?: string;
  action?: string;
  onAction?: () => void;
}) {
  return (
    <View className="mb-2.5 mt-1 flex-row items-center justify-between">
      <View className="min-w-0 flex-1 pr-2">
        <Text
          className="font-sans-bold text-lg text-stone"
          accessibilityRole="header"
        >
          {title}
        </Text>
        {subtitle ? (
          <Text className="mt-0.5 font-sans text-sm text-stoneMuted">
            {subtitle}
          </Text>
        ) : null}
      </View>
      {action && onAction ? (
        <Pressable
          className="min-h-10 flex-row items-center justify-center rounded-pill bg-indigoSoft px-3"
          accessibilityRole="button"
          accessibilityLabel={action}
          onPress={onAction}
        >
          <Text className="font-sans-bold text-sm text-indigo">{action}</Text>
          <Ionicons
            name="chevron-forward"
            size={16}
            color={tokens.colors.indigo}
          />
        </Pressable>
      ) : action ? (
        <Text className="font-sans-bold text-base text-indigo">{action}</Text>
      ) : null}
    </View>
  );
}

/**
 * A group inside a section — "Weekly seva" under "My upcoming seva".
 *
 * Deliberately quieter than a SectionHeader. The temple asked for one section
 * where there were two, and answering that with two more headings would put
 * back exactly what the merge was meant to take off the screen.
 */
export function GroupLabel({ children }: PropsWithChildren) {
  return (
    <Text
      className="font-sans-bold text-xs uppercase tracking-wider text-stoneMuted"
      accessibilityRole="header"
    >
      {children}
    </Text>
  );
}

export function GarlandDivider() {
  return (
    <View
      className="my-5 flex-row items-center"
      accessibilityElementsHidden
      importantForAccessibility="no-hide-descendants"
    >
      <View className="h-px flex-1 bg-border" />
      <View className="mx-3 flex-row gap-1.5">
        <View className="h-2.5 w-2.5 rounded-pill bg-marigold" />
        <View className="h-2.5 w-2.5 rounded-pill bg-marigoldSoft" />
        <View className="h-2.5 w-2.5 rounded-pill bg-marigold" />
      </View>
      <View className="h-px flex-1 bg-border" />
    </View>
  );
}

type ButtonProps = PressableProps &
  PropsWithChildren<{
    icon?: keyof typeof Ionicons.glyphMap;
    variant?: "primary" | "secondary";
  }>;

export function Button({
  children,
  icon,
  variant = "primary",
  ...pressableProps
}: ButtonProps) {
  const isPrimary = variant === "primary";

  return (
    <Pressable
      className={`min-h-touch flex-row items-center justify-center rounded-button px-5 py-3 ${
        isPrimary ? "bg-marigold" : "border border-border bg-white"
      }`}
      accessibilityRole="button"
      accessibilityLabel={typeof children === "string" ? children : undefined}
      {...pressableProps}
    >
      {icon ? (
        <Ionicons
          name={icon}
          size={20}
          color={isPrimary ? tokens.colors.stone : tokens.colors.indigo}
        />
      ) : null}
      <Text
        className={`font-sans-bold text-base ${
          icon ? "ml-2" : ""
        } ${isPrimary ? "text-stone" : "text-indigo"}`}
      >
        {children}
      </Text>
    </Pressable>
  );
}

/**
 * How many new messages are waiting, on the right of a row.
 *
 * One component for conversations and for sangas, because to a devotee they
 * are the same thing — WhatsApp does not draw its group badge differently from
 * its direct one, and two treatments would read as two meanings. It was drawn
 * inline in the conversation row first; sangas needed the same badge, and a
 * second copy is how the two would have drifted apart.
 *
 * Renders nothing at zero: a badge saying 0 is a badge saying "nothing", which
 * is what an absent badge already says more quietly. The count may also arrive
 * undefined from a temple whose database has not had the unread migration
 * applied, and that is the same "nothing to show".
 */
export function UnreadBadge({ count }: { count: number | null | undefined }) {
  if (!count || count < 1) return null;
  return (
    <View className="min-w-[22px] shrink-0 items-center rounded-pill bg-peacock px-1.5 py-0.5">
      {/* Past ninety-nine the exact number stops being information and starts
          being a wide badge squeezing the name beside it. */}
      <Text className="font-sans-bold text-xs text-white">
        {count > 99 ? "99+" : count}
      </Text>
    </View>
  );
}

/** The same count as words, for a row's accessibility label. */
export function unreadLabel(count: number | null | undefined) {
  if (!count || count < 1) return "";
  return `, ${count} new ${count === 1 ? "message" : "messages"}`;
}

/** "Arpita Jadhav" -> "AJ". Falls back to the Hare Krsna initials. */
export function getInitials(name: string) {
  return (
    name
      .split(/\s+/)
      .filter(Boolean)
      .slice(0, 2)
      .map((part) => part[0]?.toUpperCase())
      .join("") || "HK"
  );
}

const avatarPixels = {
  tiny: 32,
  small: 40,
  medium: 48,
  large: 80,
  xlarge: 112,
} as const;

export type AvatarSize = keyof typeof avatarPixels;

/**
 * A devotee's face where they have added one, their initials otherwise. Pass
 * `onPress` to make it open the full-size portrait.
 */
export function Avatar({
  name,
  photoUrl,
  tone = "indigo",
  size = "medium",
  onPress,
}: {
  name: string;
  photoUrl?: string | null;
  tone?: "indigo" | "marigold" | "peacock";
  size?: AvatarSize;
  onPress?: () => void;
}) {
  const pixels = avatarPixels[size];
  const ring = {
    indigo: tokens.colors.indigoSoft,
    marigold: tokens.colors.marigoldSoft,
    peacock: tokens.colors.peacockSoft,
  }[tone];
  const labelColor = {
    indigo: tokens.colors.indigo,
    marigold: tokens.colors.stone,
    peacock: tokens.colors.peacock,
  }[tone];

  const face = photoUrl ? (
    <Image
      source={{ uri: photoUrl }}
      style={{ width: pixels, height: pixels, borderRadius: pixels / 2 }}
      accessibilityIgnoresInvertColors
    />
  ) : (
    <View
      style={{
        width: pixels,
        height: pixels,
        borderRadius: pixels / 2,
        backgroundColor: ring,
        alignItems: "center",
        justifyContent: "center",
      }}
    >
      <Text
        style={{
          color: labelColor,
          fontFamily: "AtkinsonHyperlegible_700Bold",
          fontSize: Math.round(pixels * 0.36),
        }}
      >
        {getInitials(name)}
      </Text>
    </View>
  );

  const framed = (
    <View
      style={{
        width: pixels,
        height: pixels,
        borderRadius: pixels / 2,
        borderWidth: 1,
        borderColor: tokens.colors.border,
        overflow: "hidden",
      }}
    >
      {face}
    </View>
  );

  if (!onPress) return framed;

  return (
    <Pressable
      accessibilityRole="imagebutton"
      accessibilityLabel={
        photoUrl ? `Open ${name}'s photo` : `${name} has no photo yet`
      }
      onPress={onPress}
    >
      {framed}
    </Pressable>
  );
}

/**
 * Overlapping faces for the devotees on a seva card, with a "+N" bubble once
 * the list runs past `max`.
 */
export function AvatarStack({
  people,
  max = 3,
  size = "small",
}: {
  people: Array<{ id: string; name: string; photo_url?: string | null }>;
  max?: number;
  size?: AvatarSize;
}) {
  if (!people.length) return null;
  const shown = people.slice(0, max);
  const overflow = people.length - shown.length;
  const pixels = avatarPixels[size];

  return (
    <View
      className="flex-row items-center"
      accessibilityLabel={`${people.length} devotee${people.length === 1 ? "" : "s"}: ${people.map((person) => person.name).join(", ")}`}
    >
      {shown.map((person, index) => (
        <View key={person.id} style={index ? { marginLeft: -pixels * 0.28 } : undefined}>
          <Avatar name={person.name} photoUrl={person.photo_url} size={size} tone="peacock" />
        </View>
      ))}
      {overflow > 0 ? (
        <View
          style={{
            marginLeft: -pixels * 0.28,
            width: pixels,
            height: pixels,
            borderRadius: pixels / 2,
            borderWidth: 1,
            borderColor: tokens.colors.border,
            backgroundColor: tokens.colors.sandalwood,
            alignItems: "center",
            justifyContent: "center",
          }}
        >
          <Text
            style={{
              color: tokens.colors.stone,
              fontFamily: "AtkinsonHyperlegible_700Bold",
              fontSize: Math.round(pixels * 0.32),
            }}
          >
            +{overflow}
          </Text>
        </View>
      ) : null}
    </View>
  );
}

/** Full-screen portrait, opened by tapping any avatar. */
export function AvatarViewer({
  person,
  onClose,
}: {
  person: { name: string; photo_url?: string | null; subtitle?: string } | null;
  onClose: () => void;
}) {
  return (
    <Modal
      visible={Boolean(person)}
      transparent
      animationType="fade"
      onRequestClose={onClose}
    >
      <Pressable
        className="flex-1 items-center justify-center bg-stone/90 px-screen"
        accessibilityRole="button"
        accessibilityLabel="Close photo"
        onPress={onClose}
      >
        {person ? (
          <View className="w-full items-center">
            {person.photo_url ? (
              <Image
                source={{ uri: person.photo_url }}
                style={{ width: "100%", aspectRatio: 1, borderRadius: 24 }}
                resizeMode="cover"
                accessibilityIgnoresInvertColors
              />
            ) : (
              <View className="w-full items-center justify-center rounded-card bg-ivory py-16">
                <Avatar name={person.name} size="xlarge" tone="peacock" />
                <Text className="mt-4 text-center font-sans text-base text-stoneMuted">
                  No photo added yet
                </Text>
              </View>
            )}
            <Text className="mt-5 text-center font-display text-2xl text-white">
              {person.name}
            </Text>
            {person.subtitle ? (
              <Text className="mt-1 text-center font-sans text-base text-white/80">
                {person.subtitle}
              </Text>
            ) : null}
            <Text className="mt-6 font-sans text-sm text-white/70">
              Tap anywhere to close
            </Text>
          </View>
        ) : null}
      </Pressable>
    </Modal>
  );
}

export function InitialAvatar({
  initials,
  tone = "indigo",
  size = "medium",
}: {
  initials: string;
  tone?: "indigo" | "marigold" | "peacock";
  size?: "small" | "medium" | "large";
}) {
  // The background belongs to the circle and the colour to the label. Applying
  // one combined class to both put a square tinted box behind the initials and
  // left the text-size class on a View, where it does nothing.
  const { ring, label } = {
    indigo: { ring: "bg-indigoSoft border-indigo/10", label: "text-indigo" },
    marigold: { ring: "bg-marigoldSoft border-marigold/20", label: "text-stone" },
    peacock: { ring: "bg-peacockSoft border-peacock/10", label: "text-peacock" },
  }[tone];
  const circleClass = {
    small: "h-10 w-10",
    medium: "h-12 w-12",
    large: "h-20 w-20",
  }[size];
  const textClass = {
    small: "text-sm",
    medium: "text-base",
    large: "text-2xl",
  }[size];

  return (
    <View
      className={`${ring} ${circleClass} items-center justify-center rounded-pill border`}
    >
      <Text className={`font-sans-bold ${label} ${textClass}`}>{initials}</Text>
    </View>
  );
}
