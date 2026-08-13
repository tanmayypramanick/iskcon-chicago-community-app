import { Ionicons } from "@expo/vector-icons";
import {
  useIsFocused,
  useNavigation,
  type NavigationProp,
} from "@react-navigation/native";
import { useEffect, useState } from "react";
import { Modal, Pressable, Text, View } from "react-native";

import tokens from "../../design-tokens.json";
import {
  Avatar,
  AvatarViewer,
  Button,
  GarlandDivider,
  InitialAvatar,
  Screen,
  ScreenTitle,
  SectionHeader,
} from "../components/ui";
import {
  accessRoleLabels,
  getRequestableAccessRoles,
  hasAccessPermission,
  type AccessRole,
} from "../features/access/model";
import {
  useCreateAccessRequest,
  useCurrentAccessProfile,
  usePendingAccessRequests,
  useReviewAccessRequest,
} from "../features/access/hooks";
import { useTemplePresence } from "../features/presence/hooks";
import {
  useRemoveDevoteePhoto,
  useUpdateDevoteePhoto,
} from "../features/profile/hooks";
import { photoGuidelines } from "../features/profile/guidelines";
import { FormError } from "../features/services/components";
import { useServiceDashboard } from "../features/services/hooks";
import type { ProfileStackParamList } from "../navigation/types";
import { usePrototypeSession } from "../store/usePrototypeSession";

type RolePresentation = {
  shortLabel: string;
  title: string;
  description: string;
  badgeClass: string;
  badgeTextClass: string;
  icon: keyof typeof Ionicons.glyphMap;
  access: Array<{
    icon: keyof typeof Ionicons.glyphMap;
    title: string;
    detail: string;
  }>;
};

const roles: Record<AccessRole, RolePresentation> = {
  president: {
    shortLabel: "President",
    title: "President",
    description:
      "A clear leadership view for temple-wide service, communication, and oversight.",
    badgeClass: "bg-marigoldSoft",
    badgeTextClass: "text-stone",
    icon: "shield-checkmark",
    access: [
      {
        icon: "heart-outline",
        title: "Complete service coordination",
        detail: "Post, assign, cover, and manage weekly seva.",
      },
      {
        icon: "checkmark-circle-outline",
        title: "Review access requests",
        detail: "Approve or deny Volunteer and Community Head requests.",
      },
      {
        icon: "calendar-outline",
        title: "See every service schedule",
        detail: "View upcoming and completed services for the community.",
      },
      {
        icon: "grid-outline",
        title: "Full app visibility",
        detail: "Access every authorized area as features are released.",
      },
    ],
  },
  tech: {
    shortLabel: "Tech Admin",
    title: "Tech Admin",
    description:
      "A focused technical workspace for keeping the app reliable and supporting its users.",
    badgeClass: "bg-indigoSoft",
    badgeTextClass: "text-indigo",
    icon: "code-slash",
    access: [
      {
        icon: "heart-outline",
        title: "Complete service coordination",
        detail: "Post, assign, cover, and manage weekly seva.",
      },
      {
        icon: "checkmark-circle-outline",
        title: "Review access requests",
        detail: "Approve or deny Volunteer and Community Head requests.",
      },
      {
        icon: "grid-outline",
        title: "Full app visibility",
        detail: "See every authorized area and support app operations.",
      },
    ],
  },
  core: {
    shortLabel: "Community Head",
    title: "Community Head",
    description:
      "Practical coordination tools for trusted members helping with daily community life.",
    badgeClass: "bg-peacockSoft",
    badgeTextClass: "text-peacock",
    icon: "people",
    access: [
      {
        icon: "add-circle-outline",
        title: "Post and coordinate seva",
        detail: "Post requirements and ask a devotee to help.",
      },
      {
        icon: "repeat-outline",
        title: "Manage weekly seva",
        detail: "Arrange coverage when an assigned devotee is unavailable.",
      },
      {
        icon: "calendar-outline",
        title: "See every service schedule",
        detail: "View upcoming and completed services for the community.",
      },
    ],
  },
  volunteer: {
    shortLabel: "Volunteer",
    title: "Volunteer",
    description:
      "A simple service view for posting needs, joining open requirements, and following personal seva.",
    badgeClass: "bg-marigoldSoft",
    badgeTextClass: "text-stone",
    icon: "hand-left",
    access: [
      {
        icon: "add-circle-outline",
        title: "Post seva requests",
        detail: "Share an open seva request with the community.",
      },
      {
        icon: "hand-left-outline",
        title: "Join open requirements",
        detail: "See and join places where help is currently needed.",
      },
      {
        icon: "heart-outline",
        title: "Follow personal seva",
        detail: "See only your own assigned weekly and dated seva.",
      },
    ],
  },
  devotee: {
    shortLabel: "Devotee",
    title: "Devotee",
    description:
      "A peaceful personal space for seva, temple connection, and spiritual growth.",
    badgeClass: "bg-sandalwood",
    badgeTextClass: "text-stone",
    icon: "heart",
    access: [
      {
        icon: "hand-left-outline",
        title: "Offer and track seva",
        detail:
          "Join open seva requests, or offer seva for a member to verify.",
      },
      {
        icon: "chatbox-ellipses-outline",
        title: "Respond to requests",
        detail: "Accept or decline when a coordinator asks for your help.",
      },
      {
        icon: "alert-circle-outline",
        title: "Report unavailability",
        detail: "Let coordinators know when you cannot attend an assignment.",
      },
      {
        icon: "calendar-outline",
        title: "See every service schedule",
        detail: "View upcoming and completed services for the community.",
      },
    ],
  },
};

function getInitials(name: string) {
  return (
    name
      .split(/\s+/)
      .filter(Boolean)
      .slice(0, 2)
      .map((part) => part[0]?.toUpperCase())
      .join("") || "YOU"
  );
}

function RoleSelector({
  selectedRole,
  onSelect,
}: {
  selectedRole: AccessRole;
  onSelect: (role: AccessRole) => void;
}) {
  return (
    <View className="flex-row flex-wrap justify-between gap-y-2">
      {(Object.keys(roles) as AccessRole[]).map((role) => {
        const selected = role === selectedRole;

        return (
          <Pressable
            key={role}
            className={`min-h-touch flex-row items-center justify-center rounded-button border px-2 py-2 ${
              role === "devotee" ? "w-full" : "w-[49%]"
            } ${
              selected ? "border-indigo bg-indigo" : "border-border bg-white"
            }`}
            accessibilityRole="button"
            accessibilityState={{ selected }}
            accessibilityLabel={`Preview ${roles[role].shortLabel} access`}
            onPress={() => onSelect(role)}
          >
            <Ionicons
              name={roles[role].icon}
              size={18}
              color={selected ? tokens.colors.white : tokens.colors.indigo}
            />
            <Text
              className={`ml-2 font-sans-bold text-sm ${
                selected ? "text-white" : "text-indigo"
              }`}
            >
              {roles[role].shortLabel}
            </Text>
          </Pressable>
        );
      })}
    </View>
  );
}

export function ProfileScreen({ onSignOut }: { onSignOut: () => void }) {
  const isFocused = useIsFocused();
  const navigation = useNavigation<NavigationProp<ProfileStackParamList>>();
  const previewRole = usePrototypeSession((state) => state.previewRole);
  const setPreviewRole = usePrototypeSession((state) => state.setPreviewRole);
  const prototypeAccessRequests = usePrototypeSession(
    (state) => state.accessRequests,
  );
  const requestPrototypeAccess = usePrototypeSession(
    (state) => state.requestAccess,
  );
  const reviewPrototypeAccessRequest = usePrototypeSession(
    (state) => state.reviewAccessRequest,
  );
  const activeUserId = usePrototypeSession((state) => state.activeUserId);
  const presenceQuery = useTemplePresence(activeUserId);
  const servicesQuery = useServiceDashboard(activeUserId);
  const profileQuery = useCurrentAccessProfile(activeUserId);
  const accessRequestsQuery = usePendingAccessRequests(activeUserId);
  const createAccessRequest = useCreateAccessRequest(activeUserId);
  const reviewAccessRequest = useReviewAccessRequest(activeUserId);

  useEffect(() => {
    if (!isFocused || !activeUserId) return;
    void Promise.all([
      presenceQuery.refetch(),
      servicesQuery.refetch(),
      profileQuery.refetch(),
      accessRequestsQuery.refetch(),
    ]);
  }, [
    accessRequestsQuery.refetch,
    activeUserId,
    isFocused,
    presenceQuery.refetch,
    profileQuery.refetch,
    servicesQuery.refetch,
  ]);
  const updatePhoto = useUpdateDevoteePhoto(activeUserId);
  const removePhoto = useRemoveDevoteePhoto(activeUserId);
  const [photoSheetOpen, setPhotoSheetOpen] = useState(false);
  const [photoError, setPhotoError] = useState<string | null>(null);
  const [viewingPerson, setViewingPerson] = useState<{
    name: string;
    photo_url?: string | null;
    subtitle?: string;
  } | null>(null);

  const runPhotoChange = (source: "library" | "camera") => {
    setPhotoError(null);
    updatePhoto.mutate(source, {
      onSuccess: (result) => {
        if (result !== null) setPhotoSheetOpen(false);
      },
      onError: (error) =>
        setPhotoError(
          error instanceof Error
            ? error.message
            : "That photo could not be saved.",
        ),
    });
  };

  const actualRole = profileQuery.data?.role ?? "devotee";
  const isPreviewing = __DEV__ && previewRole !== null;
  const role = isPreviewing ? previewRole : actualRole;
  const selectedRole = roles[role];
  const requesterName = profileQuery.data?.name ?? "Your account";
  const profileInitials = getInitials(requesterName);
  const myPhotoUrl = profileQuery.data?.photo_url ?? null;
  const displayedAccessRequests = isPreviewing
    ? prototypeAccessRequests
    : (accessRequestsQuery.data ?? []);
  const requestableRoles = getRequestableAccessRoles(role);
  const pendingOwnRequest = displayedAccessRequests.find((request) => {
    if (request.status !== "pending") return false;
    if (isPreviewing) return request.requesterName === requesterName;
    return "requesterId" in request
      ? request.requesterId === profileQuery.data?.id
      : false;
  });
  const pendingReviewRequests = displayedAccessRequests.filter(
    (request) => request.status === "pending",
  );
  const reviewerRole = role === "president" || role === "tech" ? role : null;
  const isAtTemple = Boolean(presenceQuery.data?.current?.is_at_temple);
  // `servicesQuery` is read for the recurring-interest rows below and for
  // nothing else: the two seva lists this screen used to build from it were
  // never drawn, and the cards that would have drawn them were imported and
  // never used.
  const ownRecurringInterest = servicesQuery.data?.recurringInterests?.find(
    (interest) => interest.devotee_id === activeUserId,
  );
  const pendingRecurringInterests =
    servicesQuery.data?.recurringInterests?.filter(
      (interest) => interest.status === "pending",
    ).length ?? 0;
  const accessError =
    createAccessRequest.error ??
    reviewAccessRequest.error ??
    profileQuery.error ??
    accessRequestsQuery.error;

  const submitAccessRequest = (requestedRole: AccessRole) => {
    if (isPreviewing) {
      requestPrototypeAccess(requesterName, role, requestedRole);
      return;
    }
    if (requestedRole !== "volunteer" && requestedRole !== "core") return;
    navigation.navigate("RequestAccess", { role: requestedRole });
  };

  const completion = profileQuery.data?.completion ?? 0;
  const pendingReviewCount = displayedAccessRequests.filter(
    (request) => request.status === "pending",
  ).length;
  const canOverrideAnything = hasAccessPermission(role, "app.view_all");
  const canReviewAccess =
    hasAccessPermission(role, "access.review_requests") ||
    hasAccessPermission(role, "services.manage_recurring");

  // The list a devotee reaches everything else through. Coordinator-only rows
  // are simply absent rather than shown disabled, so nobody is invited to tap
  // something that will refuse them.
  const settingsEntries: Array<{
    icon: keyof typeof Ionicons.glyphMap;
    label: string;
    detail?: string;
    badge?: number;
    onPress: () => void;
  }> = [
    {
      icon: "person-outline",
      label: "Profile information",
      detail: completion < 100 ? `${completion}% complete` : "Complete",
      onPress: () => navigation.navigate("ProfileDetails"),
    },
    {
      icon: "gift-outline",
      label: "My giving",
      detail: "Donations and sponsorships",
      onPress: () => navigation.navigate("MyDonations"),
    },
    {
      icon: "people-circle-outline",
      label: "My sangas",
      onPress: () => navigation.navigate("SangaJoined"),
    },
    {
      icon: "time-outline",
      label: "My seva and history",
      // Kept inside the profile stack. Jumping to the Seva tab left a devotee
      // in a different tab with no way back to where they started.
      onPress: () => navigation.navigate("MyServiceHistory"),
    },
    {
      icon: "notifications-outline",
      label: "Notifications",
      onPress: () => navigation.navigate("NotificationSettings"),
    },
    {
      icon: "shield-checkmark-outline",
      label: "Privacy and visibility",
      onPress: () => navigation.navigate("PrivacyVisibility"),
    },
    {
      icon: "document-text-outline",
      label: "Terms of Service",
      onPress: () => navigation.navigate("TermsOfService"),
    },
    // The congregation record is every devotee's private details in one list.
    // Coordinating seva does not need it, so it stays with the two roles that
    // hold the whole app: President and Tech Admin.
    ...(canOverrideAnything
      ? [
          {
            icon: "people-outline" as const,
            label: "Congregation",
            detail: "Every devotee and their details",
            onPress: () => navigation.navigate("DevoteeDirectory"),
          },
          {
            icon: "chatbubbles-outline" as const,
            label: "Devotee conversations",
            onPress: () => navigation.navigate("DevoteeConversations"),
          },
          {
            icon: "cash-outline" as const,
            label: "All giving",
            detail: "Every donation and sponsorship",
            onPress: () => navigation.navigate("AllDonations"),
          },
        ]
      : []),
    // `services.manage_recurring` is exactly the predicate may_appoint_access()
    // uses, so this row appears for the same three levels the server will let
    // through — and the screen itself still asks the server before offering
    // anything.
    ...(hasAccessPermission(role, "services.manage_recurring")
      ? [
          {
            icon: "key-outline" as const,
            label: "Manage access",
            detail: "Appoint or revoke Volunteer and Community Head",
            onPress: () => navigation.navigate("ManageAccess"),
          },
        ]
      : []),
    ...(canReviewAccess && pendingReviewCount
      ? [
          {
            icon: "key-outline" as const,
            label: "Access requests",
            badge: pendingReviewCount,
            onPress: () =>
              navigation.navigate("AccessRequestReview", {
                requestId:
                  displayedAccessRequests.find(
                    (request) => request.status === "pending",
                  )?.id ?? "",
              }),
          },
        ]
      : []),
    // Kept last on purpose: it is the least urgent row, and it stays last even
    // for coordinators, whose extra rows are appended above it.
    {
      icon: "information-circle-outline",
      label: "About this app",
      onPress: () => navigation.navigate("AboutThisApp"),
    },
  ];

  const submitAccessReview = (
    requestId: string,
    decision: "approved" | "denied",
  ) => {
    if (!reviewerRole) return;
    if (isPreviewing) {
      reviewPrototypeAccessRequest(requestId, decision, reviewerRole);
      return;
    }
    reviewAccessRequest.mutate({ requestId, decision });
  };

  return (
    <Screen>
      <ScreenTitle eyebrow="Your space">Profile</ScreenTitle>

      <AvatarViewer
        person={viewingPerson}
        onClose={() => setViewingPerson(null)}
      />

      <Modal
        visible={photoSheetOpen}
        transparent
        animationType="slide"
        onRequestClose={() => setPhotoSheetOpen(false)}
      >
        <Pressable
          className="flex-1 justify-end bg-stone/60"
          accessibilityRole="button"
          accessibilityLabel="Close photo options"
          onPress={() => setPhotoSheetOpen(false)}
        >
          <Pressable className="rounded-t-card bg-ivory px-screen pb-10 pt-5">
            <Text className="font-display text-2xl text-stone">
              Your profile photo
            </Text>
            <Text className="mt-1 font-sans text-sm leading-5 text-stoneMuted">
              A clear face helps devotees recognise you at the temple.
            </Text>

            <View className="mt-4 rounded-card border border-border bg-white p-card">
              {photoGuidelines.map((guideline) => (
                <View key={guideline} className="mb-2.5 flex-row last:mb-0">
                  <Ionicons
                    name="checkmark-circle"
                    size={18}
                    color={tokens.colors.peacock}
                  />
                  <Text className="ml-2.5 flex-1 font-sans text-sm leading-5 text-stone">
                    {guideline}
                  </Text>
                </View>
              ))}
            </View>

            {photoError ? (
              <View className="mt-4">
                <FormError message={photoError} />
              </View>
            ) : null}

            <View className="mt-4 gap-3">
              <Button
                icon="camera-outline"
                disabled={updatePhoto.isPending}
                onPress={() => runPhotoChange("camera")}
              >
                {updatePhoto.isPending ? "Working…" : "Take a photo"}
              </Button>
              <Button
                variant="secondary"
                icon="images-outline"
                disabled={updatePhoto.isPending}
                onPress={() => runPhotoChange("library")}
              >
                Choose from library
              </Button>
              {myPhotoUrl ? (
                <Pressable
                  className="min-h-touch items-center justify-center rounded-button"
                  accessibilityRole="button"
                  accessibilityLabel="Remove your profile photo"
                  disabled={removePhoto.isPending}
                  onPress={() => {
                    setPhotoError(null);
                    removePhoto.mutate(undefined, {
                      onSuccess: () => setPhotoSheetOpen(false),
                      onError: (error) =>
                        setPhotoError(
                          error instanceof Error
                            ? error.message
                            : "That photo could not be removed.",
                        ),
                    });
                  }}
                >
                  <Text className="font-sans-bold text-base text-vermilion">
                    Remove photo
                  </Text>
                </Pressable>
              ) : null}
            </View>
          </Pressable>
        </Pressable>
      </Modal>
      {/* The card a devotee sees first. Their face, their name, where they
          stand in the temple, and how much of their profile is still to fill. */}
      <View className="overflow-hidden rounded-card border border-border bg-white">
        <View className="h-1.5 bg-marigold" />
        <View className="p-card">
          <View className="flex-row items-center">
            <Pressable
              accessibilityRole="button"
              accessibilityLabel={
                myPhotoUrl ? "View your profile photo" : "Add a profile photo"
              }
              onPress={() =>
                myPhotoUrl
                  ? setViewingPerson({
                      name: requesterName,
                      photo_url: myPhotoUrl,
                      subtitle: selectedRole.title,
                    })
                  : setPhotoSheetOpen(true)
              }
            >
              <Avatar
                name={requesterName}
                photoUrl={myPhotoUrl}
                tone="marigold"
                size="large"
              />
              {!myPhotoUrl ? (
                <View className="absolute -bottom-1 -right-1 h-7 w-7 items-center justify-center rounded-pill border-2 border-white bg-marigold">
                  <Ionicons name="add" size={16} color={tokens.colors.stone} />
                </View>
              ) : null}
            </Pressable>

            <View className="ml-4 min-w-0 flex-1">
              <Text
                className="font-display text-xl leading-7 text-stone"
                numberOfLines={2}
              >
                {requesterName}
              </Text>
              <View className="mt-1.5 flex-row flex-wrap items-center gap-2">
                <View
                  className={`flex-row items-center rounded-pill px-2.5 py-1 ${selectedRole.badgeClass}`}
                >
                  <Ionicons
                    name={selectedRole.icon}
                    size={13}
                    color={
                      role === "president"
                        ? tokens.colors.stone
                        : role === "tech"
                          ? tokens.colors.indigo
                          : role === "core"
                            ? tokens.colors.peacock
                            : tokens.colors.stone
                    }
                  />
                  <Text
                    className={`ml-1.5 font-sans-bold text-xs ${selectedRole.badgeTextClass}`}
                    numberOfLines={1}
                  >
                    {selectedRole.title}
                  </Text>
                </View>
                <View
                  className={`flex-row items-center rounded-pill px-2.5 py-1 ${
                    isAtTemple ? "bg-peacockSoft" : "bg-indigoSoft"
                  }`}
                >
                  <View
                    className={`mr-1.5 h-2 w-2 rounded-pill ${
                      isAtTemple ? "bg-peacock" : "bg-stoneMuted"
                    }`}
                  />
                  <Text
                    className={`font-sans-bold text-xs ${
                      isAtTemple ? "text-peacock" : "text-indigo"
                    }`}
                    numberOfLines={1}
                  >
                    {isAtTemple ? "At the temple" : "Not at the temple"}
                  </Text>
                </View>
              </View>
            </View>
          </View>

          {/* Completion is a nudge, not a scold: it only appears while there
              is something left to add. */}
          {completion < 100 ? (
            <View className="mt-4">
              <View className="flex-row items-end justify-between">
                <Text className="font-sans text-sm text-stoneMuted">
                  Your profile is {completion}% complete
                </Text>
                <Text className="font-sans-bold text-sm text-peacock">
                  {completion}%
                </Text>
              </View>
              <View className="mt-1.5 h-2 overflow-hidden rounded-pill bg-peacockSoft">
                <View
                  className="h-full rounded-pill bg-peacock"
                  style={{ width: `${Math.max(4, completion)}%` }}
                />
              </View>
              <Text className="mt-2 font-sans text-xs leading-5 text-stoneMuted">
                Adding the rest helps the temple know you and welcome you
                properly.
              </Text>
            </View>
          ) : null}

          <View className="mt-4 flex-row gap-3">
            <Pressable
              className="min-h-touch flex-1 flex-row items-center justify-center rounded-button bg-indigo"
              accessibilityRole="button"
              accessibilityLabel="Edit your profile details"
              onPress={() => navigation.navigate("ProfileDetails")}
            >
              <Ionicons
                name="create-outline"
                size={18}
                color={tokens.colors.white}
              />
              <Text className="ml-2 font-sans-bold text-base text-white">
                Edit profile
              </Text>
            </Pressable>
          </View>

          {isPreviewing ? (
            <Text className="mt-3 font-sans-bold text-[10px] uppercase tracking-wider text-vermilion">
              Previewing · Real access is {accessRoleLabels[actualRole]}
            </Text>
          ) : null}
        </View>
      </View>

      {/* "Your seva" used to be here. The temple moved it to "My seva and
          history", which is the page a devotee opens to read what they have
          served — one row below in this very list. */}

      <SectionHeader title="Profile and settings" />
      <View className="mb-section overflow-hidden rounded-card border border-border bg-white">
        {settingsEntries.map((item, index, list) => (
          <Pressable
            key={item.label}
            className={`min-h-touch flex-row items-center px-card py-3.5 ${
              index < list.length - 1 ? "border-b border-border" : ""
            }`}
            accessibilityRole="button"
            accessibilityLabel={item.label}
            onPress={item.onPress}
          >
            <View className="h-9 w-9 items-center justify-center rounded-pill bg-indigoSoft">
              <Ionicons
                name={item.icon}
                size={18}
                color={tokens.colors.indigo}
              />
            </View>
            <View className="ml-3 min-w-0 flex-1">
              <Text className="font-sans text-base text-stone">
                {item.label}
              </Text>
              {item.detail ? (
                <Text className="mt-0.5 font-sans text-xs text-stoneMuted">
                  {item.detail}
                </Text>
              ) : null}
            </View>
            {item.badge ? (
              <View className="mr-2 min-w-6 items-center rounded-pill bg-vermilion px-2 py-0.5">
                <Text className="font-sans-bold text-xs text-white">
                  {item.badge}
                </Text>
              </View>
            ) : null}
            <Ionicons
              name="chevron-forward"
              size={19}
              color={tokens.colors.stoneMuted}
            />
          </Pressable>
        ))}
      </View>

      {requestableRoles.length > 0 ? (
        <>
          <SectionHeader title="Request more access" />
          <View className="mb-section rounded-card border border-border bg-white p-card">
            {pendingOwnRequest ? (
              <View className="flex-row items-start">
                <View className="h-11 w-11 items-center justify-center rounded-pill bg-marigoldSoft">
                  <Ionicons
                    name="time-outline"
                    size={22}
                    color={tokens.colors.stone}
                  />
                </View>
                <View className="ml-4 flex-1">
                  <Text className="font-sans-bold text-base text-stone">
                    {accessRoleLabels[pendingOwnRequest.requestedRole]} request
                    pending
                  </Text>
                  <Text className="mt-1 font-sans text-sm leading-5 text-stoneMuted">
                    A President or Tech Admin can approve or deny this request.
                  </Text>
                </View>
              </View>
            ) : (
              <>
                <Text className="font-sans text-base leading-6 text-stoneMuted">
                  Choose the access level that matches how you help the temple.
                </Text>
                <View className="mt-4 gap-3">
                  {requestableRoles.map((requestedRole) => (
                    <Pressable
                      key={requestedRole}
                      className="min-h-touch flex-row items-center justify-between rounded-button bg-indigo px-4 py-3"
                      accessibilityRole="button"
                      accessibilityLabel={`Request ${accessRoleLabels[requestedRole]} access`}
                      onPress={() => submitAccessRequest(requestedRole)}
                    >
                      <Text className="font-sans-bold text-base text-white">
                        Request {accessRoleLabels[requestedRole]} access
                      </Text>
                      <Ionicons
                        name="arrow-forward"
                        size={20}
                        color={tokens.colors.white}
                      />
                    </Pressable>
                  ))}
                </View>
              </>
            )}
          </View>
        </>
      ) : null}

      {reviewerRole &&
      hasAccessPermission(reviewerRole, "access.review_requests") ? (
        <>
          <SectionHeader title="Access requests to review" />
          <View className="mb-section overflow-hidden rounded-card border border-border bg-white">
            {!isPreviewing && accessRequestsQuery.isLoading ? (
              <View className="items-center px-card py-7">
                <Text className="font-sans text-base text-stoneMuted">
                  Checking for access requests…
                </Text>
              </View>
            ) : pendingReviewRequests.length === 0 ? (
              <View className="items-center px-card py-7">
                <View className="h-12 w-12 items-center justify-center rounded-pill bg-peacockSoft">
                  <Ionicons
                    name="checkmark-done"
                    size={24}
                    color={tokens.colors.peacock}
                  />
                </View>
                <Text className="mt-3 font-sans-bold text-base text-stone">
                  No pending requests
                </Text>
                <Text className="mt-1 text-center font-sans text-sm text-stoneMuted">
                  New Volunteer and Community Head requests will appear here.
                </Text>
              </View>
            ) : (
              pendingReviewRequests.map((request, index) => (
                <View
                  key={request.id}
                  className={`p-card ${
                    index < pendingReviewRequests.length - 1
                      ? "border-b border-border"
                      : ""
                  }`}
                >
                  <View className="flex-row items-center">
                    <InitialAvatar
                      initials={getInitials(request.requesterName)}
                      tone="marigold"
                      size="small"
                    />
                    <View className="ml-3 flex-1">
                      <Text className="font-sans-bold text-base text-stone">
                        {request.requesterName}
                      </Text>
                      <Text className="mt-0.5 font-sans text-sm text-stoneMuted">
                        {accessRoleLabels[request.currentRole]} →{" "}
                        {accessRoleLabels[request.requestedRole]}
                      </Text>
                    </View>
                  </View>
                  <View className="mt-4 flex-row gap-3">
                    <Pressable
                      className="min-h-touch flex-1 items-center justify-center rounded-button border border-border bg-white px-3"
                      accessibilityRole="button"
                      accessibilityLabel={`Deny ${request.requesterName}'s access request`}
                      onPress={() => submitAccessReview(request.id, "denied")}
                    >
                      <Text className="font-sans-bold text-base text-vermilion">
                        Deny
                      </Text>
                    </Pressable>
                    <Pressable
                      className="min-h-touch flex-1 items-center justify-center rounded-button bg-peacock px-3"
                      accessibilityRole="button"
                      accessibilityLabel={`Approve ${request.requesterName}'s access request`}
                      onPress={() => submitAccessReview(request.id, "approved")}
                    >
                      <Text className="font-sans-bold text-base text-white">
                        Approve
                      </Text>
                    </Pressable>
                  </View>
                </View>
              ))
            )}
          </View>
        </>
      ) : null}

      {accessError ? (
        <View className="mb-section flex-row rounded-button border border-vermilion bg-white px-4 py-3">
          <Ionicons
            name="alert-circle-outline"
            size={20}
            color={tokens.colors.vermilion}
          />
          <Text className="ml-3 flex-1 font-sans text-sm leading-5 text-vermilion">
            {accessError instanceof Error
              ? accessError.message
              : "Access information could not be updated."}
          </Text>
        </View>
      ) : null}

      <SectionHeader title="Weekly seva" />
      <View className="mb-section overflow-hidden rounded-card border border-border bg-white">
        <Pressable
          className="min-h-[68px] flex-row items-center px-card py-3"
          accessibilityRole="button"
          accessibilityLabel="Open weekly seva profile"
          onPress={() => navigation.navigate("RecurringInterest")}
        >
          <View className="h-10 w-10 items-center justify-center rounded-pill bg-marigoldSoft">
            <Ionicons name="repeat" size={20} color={tokens.colors.stone} />
          </View>
          <View className="ml-3 min-w-0 flex-1">
            <Text className="font-sans-bold text-base text-stone">
              Want to offer weekly seva?
            </Text>
            <Text className="mt-0.5 font-sans text-sm text-stoneMuted">
              {ownRecurringInterest
                ? ownRecurringInterest.status === "approved"
                  ? "Your weekly-seva profile is verified."
                  : ownRecurringInterest.status === "pending"
                    ? "Your details are waiting for review."
                    : "Update your details and submit again."
                : "Share your skills, interests, and availability."}
            </Text>
          </View>
          {ownRecurringInterest ? (
            <View
              className={`mr-2 h-2.5 w-2.5 rounded-pill ${
                ownRecurringInterest.status === "approved"
                  ? "bg-peacock"
                  : ownRecurringInterest.status === "denied"
                    ? "bg-vermilion"
                    : "bg-marigold"
              }`}
            />
          ) : null}
          <Ionicons
            name="chevron-forward"
            size={20}
            color={tokens.colors.indigo}
          />
        </Pressable>
        {hasAccessPermission(role, "services.manage_recurring") ? (
          <Pressable
            className="min-h-[64px] flex-row items-center border-t border-border px-card py-3"
            accessibilityRole="button"
            accessibilityLabel="Review weekly-seva interests"
            onPress={() => navigation.navigate("RecurringInterestInbox")}
          >
            <View className="h-10 w-10 items-center justify-center rounded-pill bg-peacockSoft">
              <Ionicons
                name="people-outline"
                size={20}
                color={tokens.colors.peacock}
              />
            </View>
            <Text className="ml-3 min-w-0 flex-1 font-sans-bold text-base text-stone">
              Review weekly-seva interests
            </Text>
            {pendingRecurringInterests ? (
              <View className="mr-2 min-w-6 items-center rounded-pill bg-vermilion px-2 py-1">
                <Text className="font-sans-bold text-xs text-white">
                  {pendingRecurringInterests}
                </Text>
              </View>
            ) : null}
            <Ionicons
              name="chevron-forward"
              size={20}
              color={tokens.colors.indigo}
            />
          </Pressable>
        ) : null}
      </View>

      <GarlandDivider />

      {__DEV__ ? (
        <>
          <SectionHeader title="Test access levels" />
          <RoleSelector selectedRole={role} onSelect={setPreviewRole} />

          {isPreviewing ? (
            <Pressable
              className="mt-3 min-h-touch items-center justify-center"
              accessibilityRole="button"
              accessibilityLabel={`Return to real ${accessRoleLabels[actualRole]} access`}
              onPress={() => setPreviewRole(null)}
            >
              <Text className="font-sans-bold text-sm text-indigo">
                Return to my real {accessRoleLabels[actualRole]} access
              </Text>
            </Pressable>
          ) : null}

          <View className="mt-3 flex-row rounded-button border border-border bg-sandalwood px-3 py-2.5">
            <Ionicons
              name="flask-outline"
              size={18}
              color={tokens.colors.indigo}
            />
            <Text className="ml-3 flex-1 font-sans text-sm leading-5 text-stoneMuted">
              Testing only: switching this preview changes visible UI, never
              your real Supabase permissions.
            </Text>
          </View>
        </>
      ) : null}

      <View className="my-section rounded-card bg-indigo p-card">
        <View className="flex-row items-center">
          <View className="h-9 w-9 items-center justify-center rounded-pill bg-white">
            <Ionicons
              name={selectedRole.icon}
              size={19}
              color={tokens.colors.indigo}
            />
          </View>
          <View className="ml-3 flex-1">
            <Text className="font-display text-lg text-white">
              {selectedRole.title}
            </Text>
            <Text className="mt-1 font-sans-bold text-sm text-marigoldSoft">
              {isPreviewing ? "Preview UI access" : "Verified Supabase access"}
            </Text>
          </View>
        </View>
        <Text className="mt-3 font-sans text-sm leading-5 text-white">
          {selectedRole.description}
        </Text>
      </View>

      <Button variant="secondary" icon="log-out-outline" onPress={onSignOut}>
        Sign out
      </Button>
    </Screen>
  );
}
