import { Ionicons } from "@expo/vector-icons";
import { type NavigationProp } from "@react-navigation/native";
import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import { Pressable, RefreshControl, Text, View } from "react-native";

import tokens from "../../design-tokens.json";
import {
  Avatar,
  EmptyOrOffline,
  ListScreen,
  LoadFailure,
  Skeleton,
} from "../components/ui";
import { useAnnouncementLikes } from "../features/announcements/hooks";
import { errorMessage } from "../features/services/format";
import { useServerReachable } from "../lib/connectivity";
import type { HomeStackParamList, MainTabParamList } from "../navigation/types";
import { formatCareTime } from "./CarePostScreen";

type Props = NativeStackScreenProps<HomeStackParamList, "AnnouncementLikes">;

/**
 * Who liked one notice, by name and face.
 *
 * Nothing here is anonymous, deliberately: the devotee who posted "the parking
 * lot is closed Sunday" wants to know it landed, and the devotee reading it
 * wants to know who else is coming.
 */
export function AnnouncementLikesScreen({ navigation, route }: Props) {
  const { announcementId, title } = route.params;
  const reachable = useServerReachable();
  const likes = useAnnouncementLikes(announcementId);

  const rows = likes.data ?? [];
  const failed = likes.isError && likes.data === undefined;

  // A devotee's profile lives on the Devotees tab, so opening one is a hop
  // between stacks rather than a push onto this one.
  const openDevotee = (devoteeId: string) => {
    navigation
      .getParent<NavigationProp<MainTabParamList>>()
      ?.navigate("Devotees", {
        screen: "DevoteeProfile",
        params: { devoteeId },
      });
  };

  return (
    <ListScreen
      topInset={false}
      bottomInset={false}
      data={rows}
      keyExtractor={(like) => like.devotee_id}
      refreshControl={
        <RefreshControl
          refreshing={likes.isRefetching}
          onRefresh={() => void likes.refetch()}
          tintColor={tokens.colors.indigo}
          colors={[tokens.colors.indigo]}
        />
      }
      header={
        <Text className="mb-3 font-sans text-sm leading-5 text-stoneMuted">
          {rows.length
            ? `${rows.length} ${rows.length === 1 ? "devotee" : "devotees"} liked “${title}”. Tap anyone to open their profile.`
            : `Likes on “${title}”.`}
        </Text>
      }
      renderItem={(like, index) => (
        <Pressable
          className={`flex-row items-center border border-b-0 border-border bg-white px-card py-3 ${
            index === 0 ? "rounded-t-card" : ""
          } ${index === rows.length - 1 ? "rounded-b-card border-b" : ""}`}
          accessibilityRole="button"
          accessibilityLabel={`Open ${like.name}'s profile`}
          onPress={() => openDevotee(like.devotee_id)}
        >
          <Avatar
            name={like.name}
            photoUrl={like.photo_url}
            size="small"
            tone="peacock"
          />
          <View className="ml-3 min-w-0 flex-1">
            <Text
              className="font-sans-bold text-base text-stone"
              numberOfLines={1}
            >
              {like.name}
            </Text>
            <Text className="font-sans text-xs text-stoneMuted">
              {formatCareTime(like.created_at)}
            </Text>
          </View>
          <Ionicons
            name="chevron-forward"
            size={18}
            color={tokens.colors.stoneMuted}
          />
        </Pressable>
      )}
      empty={
        likes.isLoading ? (
          <View className="gap-2 rounded-card border border-border bg-white p-card">
            <Skeleton height={40} />
            <Skeleton height={40} />
            <Skeleton height={40} />
          </View>
        ) : failed ? (
          <LoadFailure
            reachable={reachable}
            message={errorMessage(
              likes.error,
              "The likes could not be loaded.",
            )}
            onRetry={() => void likes.refetch()}
          />
        ) : (
          <EmptyOrOffline
            reachable={reachable}
            loading={false}
            empty={
              <View className="items-center rounded-card border border-border bg-white px-card py-9">
                <View className="h-14 w-14 items-center justify-center rounded-pill bg-vermilionSoft">
                  <Ionicons
                    name="heart-outline"
                    size={26}
                    color={tokens.colors.vermilion}
                  />
                </View>
                <Text className="mt-4 text-center font-display text-xl text-stone">
                  Nobody has liked this yet
                </Text>
                <Text className="mt-2 max-w-80 text-center font-sans text-sm leading-6 text-stoneMuted">
                  A like is the quietest way to say you have seen it.
                </Text>
              </View>
            }
          />
        )
      }
    />
  );
}
