import { Ionicons } from "@expo/vector-icons";
import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import { useState } from "react";
import {
  Alert,
  Image,
  Pressable,
  RefreshControl,
  Text,
  View,
} from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";

import tokens from "../../design-tokens.json";
import { ModalScreen } from "../components/ModalScreen";
import {
  EmptyOrOffline,
  ListScreen,
  LoadFailure,
  ScreenTitle,
  SkeletonCard,
} from "../components/ui";
import { useCurrentAccessProfile } from "../features/access/hooks";
import {
  AnnouncementCard,
  useAnnouncementDayKeys,
} from "../features/announcements/components";
import {
  canPostAnnouncements,
  useAnnouncements,
  useDeleteAnnouncement,
  useToggleAnnouncementLike,
} from "../features/announcements/hooks";
import type { Announcement } from "../features/announcements/types";
import { FormError } from "../features/services/components";
import { errorMessage } from "../features/services/format";
import { sharePicture } from "../lib/sharePicture";
import { useServerReachable } from "../lib/connectivity";
import type { HomeStackParamList } from "../navigation/types";
import { usePrototypeSession } from "../store/usePrototypeSession";
import { BirthdayPrompt } from "../features/birthdays/components";
import {
  CreateAnnouncementModal,
  type AnnouncementPrefill,
} from "./CreateAnnouncementScreen";

type Props = NativeStackScreenProps<HomeStackParamList, "Announcements">;

/**
 * The temple's noticeboard. Everything live, newest first, read by every
 * devotee; posting and taking down belong to the three roles the server
 * recognises, and it is the server that says which rows this devotee may
 * remove.
 */
export function AnnouncementsScreen({ navigation }: Props) {
  const activeUserId = usePrototypeSession((state) => state.activeUserId);
  const previewRole = usePrototypeSession((state) => state.previewRole);
  const profile = useCurrentAccessProfile(activeUserId);
  const role =
    __DEV__ && previewRole ? previewRole : (profile.data?.role ?? "devotee");
  const canPost = canPostAnnouncements(role);

  const reachable = useServerReachable();
  const announcements = useAnnouncements();
  const remove = useDeleteAnnouncement();
  const toggleLike = useToggleAnnouncementLike();
  const [composerOpen, setComposerOpen] = useState(false);
  // A birthday prompt opens the same composer, already worded. The wording is
  // the server's so the temple's voice is not frozen in an app release.
  const [prefill, setPrefill] = useState<AnnouncementPrefill | null>(null);
  const [removeError, setRemoveError] = useState<string | null>(null);
  const [viewingImage, setViewingImage] = useState<string | null>(null);
  const [savingImage, setSavingImage] = useState(false);

  const savePicture = (url: string) => {
    setSavingImage(true);
    void sharePicture(url, "announcement")
      .catch((error: unknown) =>
        Alert.alert(
          "Not saved",
          error instanceof Error
            ? error.message
            : "That picture could not be saved.",
        ),
      )
      .finally(() => setSavingImage(false));
  };

  const { todayKey, yesterdayKey } = useAnnouncementDayKeys();

  const rows = announcements.data ?? [];
  const failed = announcements.isError && announcements.data === undefined;

  const confirmDelete = (announcement: Announcement) => {
    setRemoveError(null);
    Alert.alert(
      "Take this announcement down?",
      `“${announcement.title}” will disappear for everyone. This cannot be undone.`,
      [
        { text: "Keep", style: "cancel" },
        {
          text: "Take down",
          style: "destructive",
          onPress: () =>
            remove.mutate(announcement.id, {
              onError: (caught) =>
                setRemoveError(
                  errorMessage(
                    caught,
                    "That announcement could not be taken down.",
                  ),
                ),
            }),
        },
      ],
    );
  };

  return (
    <>
      <ListScreen
        topInset={false}
        data={rows}
        keyExtractor={(announcement) => announcement.id}
        refreshControl={
          <RefreshControl
            refreshing={announcements.isRefetching}
            onRefresh={() => void announcements.refetch()}
            tintColor={tokens.colors.indigo}
            colors={[tokens.colors.indigo]}
          />
        }
        header={
          <>
            <ScreenTitle
              eyebrow="From the temple"
              action={
                canPost ? (
                  <Pressable
                    className="min-h-touch flex-row items-center justify-center rounded-pill bg-marigold px-4"
                    accessibilityRole="button"
                    accessibilityLabel="Post an announcement"
                    onPress={() => setComposerOpen(true)}
                  >
                    <Ionicons
                      name="add"
                      size={18}
                      color={tokens.colors.stone}
                    />
                    <Text className="ml-1 font-sans-bold text-base text-stone">
                      Post
                    </Text>
                  </Pressable>
                ) : undefined
              }
            >
              Announcements
            </ScreenTitle>
            <BirthdayPrompt
              onWish={(words) => {
                setPrefill(words);
                setComposerOpen(true);
              }}
            />
            {removeError ? <FormError message={removeError} /> : null}
          </>
        }
        renderItem={(announcement) => (
          <AnnouncementCard
            announcement={announcement}
            todayKey={todayKey}
            yesterdayKey={yesterdayKey}
            onDelete={() => confirmDelete(announcement)}
            onOpenImage={setViewingImage}
            onToggleLike={() => {
              // Nothing is awaited and nothing is reported: the heart has
              // already moved, and a like that could not be saved puts itself
              // back rather than interrupting a devotee who is reading.
              setRemoveError(null);
              toggleLike.mutate(announcement.id);
            }}
            onOpenLikes={() =>
              navigation.navigate("AnnouncementLikes", {
                announcementId: announcement.id,
                title: announcement.title,
              })
            }
            onOpenComments={() =>
              navigation.navigate("AnnouncementComments", {
                announcementId: announcement.id,
                title: announcement.title,
              })
            }
          />
        )}
        empty={
          announcements.isLoading ? (
            <View className="gap-3">
              <SkeletonCard />
              <SkeletonCard />
              <SkeletonCard />
            </View>
          ) : failed ? (
            <LoadFailure
              reachable={reachable}
              message={errorMessage(
                announcements.error,
                "Announcements could not be loaded.",
              )}
              onRetry={() => void announcements.refetch()}
            />
          ) : (
            <EmptyOrOffline
              reachable={reachable}
              loading={false}
              empty={
                <View className="items-center rounded-card border border-border bg-white px-card py-9">
                  <View className="h-14 w-14 items-center justify-center rounded-pill bg-marigoldSoft">
                    <Ionicons
                      name="megaphone-outline"
                      size={26}
                      color={tokens.colors.marigold}
                    />
                  </View>
                  <Text className="mt-4 text-center font-display text-xl text-stone">
                    Nothing on the board
                  </Text>
                  <Text className="mt-2 max-w-80 text-center font-sans text-sm leading-6 text-stoneMuted">
                    {canPost
                      ? "Festivals, closures and anything else the congregation should know will appear here once you post it."
                      : "Festivals, closures and anything else the congregation should know will appear here."}
                  </Text>
                </View>
              }
            />
          )
        }
      />
      {canPost ? (
        <CreateAnnouncementModal
          visible={composerOpen}
          prefill={prefill}
          onClose={() => {
            setComposerOpen(false);
            setPrefill(null);
          }}
        />
      ) : null}

      <ModalScreen
        visible={viewingImage !== null}
        onClose={() => setViewingImage(null)}
        title="Photo"
        backLabel="Close the picture"
        tone="dark"
        scroll={false}
      >
        <Pressable
          className="flex-1 items-center justify-center"
          accessibilityRole="button"
          accessibilityLabel="Close the picture"
          onPress={() => setViewingImage(null)}
        >
          {viewingImage ? (
            <Image
              source={{ uri: viewingImage }}
              style={{ width: "100%", height: "78%" }}
              resizeMode="contain"
              accessibilityIgnoresInvertColors
            />
          ) : null}
        </Pressable>
        <SafeAreaView edges={["bottom"]}>
          <View className="flex-row justify-center px-screen pb-4">
            <Pressable
              className="flex-row items-center rounded-pill bg-white/15 px-5 py-3"
              accessibilityRole="button"
              accessibilityLabel="Save this picture"
              disabled={savingImage}
              onPress={() => viewingImage && savePicture(viewingImage)}
            >
              <Ionicons
                name="download-outline"
                size={18}
                color={tokens.colors.ivory}
              />
              <Text className="ml-2 font-sans-bold text-sm text-ivory">
                {savingImage ? "Preparing…" : "Save"}
              </Text>
            </Pressable>
          </View>
        </SafeAreaView>
      </ModalScreen>
    </>
  );
}
