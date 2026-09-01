import { Ionicons } from "@expo/vector-icons";
import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import { Pressable, RefreshControl, Text, View } from "react-native";

import tokens from "../../design-tokens.json";
import {
  EmptyOrOffline,
  ListScreen,
  LoadFailure,
  ScreenTitle,
  Skeleton,
} from "../components/ui";
import { useCurrentAccessProfile } from "../features/access/hooks";
import {
  DarshanWeekLead,
  DarshanWeekRow,
  useDarshanDayKeys,
} from "../features/dailyDarshan/components";
import {
  canPostDailyDarshan,
  useDailyDarshan,
} from "../features/dailyDarshan/hooks";
import { errorMessage } from "../features/services/format";
import { useServerReachable } from "../lib/connectivity";
import { useRefreshOnFocus } from "../lib/useRefreshOnFocus";
import type { HomeStackParamList } from "../navigation/types";
import { usePrototypeSession } from "../store/usePrototypeSession";

type Props = NativeStackScreenProps<HomeStackParamList, "DailyDarshan">;

/**
 * The wait is drawn as the week's own shape — one large day above a couple of
 * rows — so a devotee on temple wifi sees what is coming rather than a spinner.
 */
function WeekSkeleton() {
  return (
    <View>
      <View className="mb-3">
        <Skeleton height={230} />
      </View>
      <View className="mb-3">
        <Skeleton height={94} />
      </View>
      <View className="mb-3">
        <Skeleton height={94} />
      </View>
    </View>
  );
}

/**
 * The week of darshan, one entry per day.
 *
 * The temple's words were "it shouldn't be one by one … for one day only one
 * thing inside, and they can check everything on that day". So this screen is
 * the week — at most seven days, because the server keeps one week — and every
 * day is a single tile that opens everything posted on it. The photographs
 * themselves live one screen deeper, where a day is looked at rather than
 * scrolled past.
 *
 * Read by every devotee. Posting belongs to the three roles the server
 * recognises; taking a day down happens on the day itself, where what would go
 * can be seen before it goes.
 */
export function DailyDarshanScreen({ navigation }: Props) {
  const activeUserId = usePrototypeSession((state) => state.activeUserId);
  const profile = useCurrentAccessProfile(activeUserId);
  const role =
    (profile.data?.role ?? "devotee");
  const canPost = canPostDailyDarshan(role);

  const reachable = useServerReachable();
  const darshan = useDailyDarshan();
  const { todayKey, yesterdayKey } = useDarshanDayKeys();

  useRefreshOnFocus([darshan]);

  const days = darshan.data ?? [];
  const failed = darshan.isError && darshan.data === undefined;

  const openDay = (id: string, darshanOn: string) =>
    navigation.navigate("DarshanDay", { darshanId: id, darshanOn });

  return (
    <ListScreen
      topInset={false}
      data={days}
      keyExtractor={(day) => day.id}
      refreshControl={
        <RefreshControl
          refreshing={darshan.isRefetching}
          onRefresh={() => void darshan.refetch()}
          tintColor={tokens.colors.indigo}
          colors={[tokens.colors.indigo]}
        />
      }
      header={
        <ScreenTitle
          eyebrow="This week at the altar"
          action={
            // A devotee who may not post is offered nothing at all, rather
            // than a button that the server would refuse.
            canPost ? (
              <Pressable
                className="min-h-touch flex-row items-center justify-center rounded-pill bg-marigold px-4"
                accessibilityRole="button"
                accessibilityLabel="Post today’s darshan"
                onPress={() => navigation.navigate("PostDarshan")}
              >
                <Ionicons name="add" size={18} color={tokens.colors.stone} />
                <Text className="ml-1 font-sans-bold text-base text-stone">
                  Post
                </Text>
              </Pressable>
            ) : undefined
          }
        >
          Daily Darshan
        </ScreenTitle>
      }
      renderItem={(day, index) =>
        // The newest day is drawn large: it is almost always today's darshan
        // and is what the screen was opened for. The rest of the week is a
        // list beneath it, every row the same height.
        index === 0 ? (
          <DarshanWeekLead
            darshan={day}
            todayKey={todayKey}
            yesterdayKey={yesterdayKey}
            onPress={() => openDay(day.id, day.darshan_on)}
          />
        ) : (
          <DarshanWeekRow
            darshan={day}
            todayKey={todayKey}
            yesterdayKey={yesterdayKey}
            onPress={() => openDay(day.id, day.darshan_on)}
          />
        )
      }
      footer={
        days.length ? (
          <Text className="mt-1 px-1 font-sans text-xs leading-5 text-stoneMuted">
            Darshan is kept for the current week. A new week begins each Monday.
          </Text>
        ) : null
      }
      empty={
        darshan.isLoading ? (
          <WeekSkeleton />
        ) : failed ? (
          <LoadFailure
            reachable={reachable}
            message={errorMessage(darshan.error, "Darshan could not be loaded.")}
            onRetry={() => void darshan.refetch()}
          />
        ) : (
          <EmptyOrOffline
            reachable={reachable}
            loading={false}
            empty={
              <View className="items-center rounded-card border border-border bg-white px-card py-9">
                <View className="h-14 w-14 items-center justify-center rounded-pill bg-marigoldSoft">
                  <Ionicons
                    name="flower-outline"
                    size={26}
                    color={tokens.colors.marigold}
                  />
                </View>
                <Text className="mt-4 text-center font-display text-xl text-stone">
                  No darshan yet
                </Text>
                <Text className="mt-2 max-w-80 text-center font-sans text-sm leading-6 text-stoneMuted">
                  {canPost
                    ? "The day’s pictures of the Deities, and who dressed Them, will appear here once you post them."
                    : "The day’s pictures of the Deities, and who dressed Them, will appear here."}
                </Text>
              </View>
            }
          />
        )
      }
    />
  );
}
