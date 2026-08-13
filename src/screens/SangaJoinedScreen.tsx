import { Ionicons } from "@expo/vector-icons";
import type { NavigationProp } from "@react-navigation/native";
import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import { useMemo } from "react";
import { Pressable, Text, View } from "react-native";

import tokens from "../../design-tokens.json";
import {
  EmptyOrOffline,
  ListScreen,
  LoadFailure,
  ScreenTitle,
  SectionHeader,
} from "../components/ui";
import {
  MySangaRow,
  SangaRowsSkeleton,
  sangaDisplayStatus,
} from "../features/sanga/components";
import { useMySangas } from "../features/sanga/hooks";
import type { MySangaSummary } from "../features/sanga/types";
import { errorMessage } from "../features/services/format";
import { useServerReachable } from "../lib/connectivity";
import type {
  MainTabParamList,
  ProfileStackParamList,
} from "../navigation/types";

type Props = NativeStackScreenProps<ProfileStackParamList, "SangaJoined">;

type Row =
  | { kind: "heading"; id: string; title: string; subtitle?: string }
  | {
      kind: "sanga";
      id: string;
      sanga: MySangaSummary;
      isFirst: boolean;
      isLast: boolean;
    };

/**
 * The devotee's own sangas, reached from the profile — including the ones they
 * proposed and the President has not answered yet, which exist nowhere else in
 * the app. The full list of what else is running lives on the Devotees tab, so
 * this screen sends them there rather than keeping a second copy of it.
 */
export function SangaJoinedScreen({ navigation }: Props) {
  const reachable = useServerReachable();
  const mine = useMySangas();

  const failed = mine.isError && mine.data === undefined;
  const tabs = navigation.getParent<NavigationProp<MainTabParamList>>();

  // A sanga the devotee is actually in opens on its conversation — that thread
  // is what being in a circle means, and a page about it first is a step in the
  // way. One they only proposed, or are merely overseeing, keeps its overview.
  const openSanga = (sanga: MySangaSummary) =>
    tabs?.navigate(
      "Devotees",
      sanga.is_member
        ? {
            screen: "SangaChat",
            params: { sangaId: sanga.id, name: sanga.name },
          }
        : {
            screen: "SangaDetail",
            params: { sangaId: sanga.id, name: sanga.name },
          },
    );

  const browseSangas = () =>
    tabs?.navigate("Devotees", {
      screen: "DevoteesHome",
      params: { section: "sanga" },
    });

  const startSanga = () =>
    tabs?.navigate("Devotees", { screen: "CreateSanga" });

  const rows = useMemo<Row[]>(() => {
    const all = mine.data ?? [];
    const running = all.filter(
      (sanga) => sangaDisplayStatus(sanga) === "approved",
    );
    const waiting = all.filter((sanga) => sanga.status === "pending");
    const closed = all.filter(
      (sanga) =>
        sanga.status === "declined" || sangaDisplayStatus(sanga) === "retired",
    );

    const group = (items: MySangaSummary[]): Row[] =>
      items.map((sanga, index) => ({
        kind: "sanga" as const,
        id: sanga.id,
        sanga,
        isFirst: index === 0,
        isLast: index === items.length - 1,
      }));

    const section = (title: string, subtitle: string, items: MySangaSummary[]) =>
      items.length
        ? [
            { kind: "heading" as const, id: `heading-${title}`, title, subtitle },
            ...group(items),
          ]
        : [];

    return [
      ...section("Your sangas", "The circles you are in", running),
      // A sanga can only be pending if this devotee proposed it: the server
      // makes its founder its admin the moment it is created.
      ...section(
        "Proposed by you",
        "The temple President has not answered these yet",
        waiting,
      ),
      ...section("Closed", "No longer running", closed),
    ];
  }, [mine.data]);

  return (
    <ListScreen
      topInset={false}
      data={rows}
      keyExtractor={(row) => `${row.kind}-${row.id}`}
      header={
        <ScreenTitle eyebrow="Your community groups">My sangas</ScreenTitle>
      }
      renderItem={(row, index) => {
        if (row.kind === "heading") {
          return (
            <View className={index ? "mt-section" : ""}>
              <SectionHeader title={row.title} subtitle={row.subtitle} />
            </View>
          );
        }

        return (
          <MySangaRow
            sanga={row.sanga}
            isFirst={row.isFirst}
            isLast={row.isLast}
            onPress={() => openSanga(row.sanga)}
          />
        );
      }}
      empty={
        mine.isLoading ? (
          <SangaRowsSkeleton />
        ) : failed ? (
          <LoadFailure
            reachable={reachable}
            message={errorMessage(mine.error, "Sangas could not be loaded.")}
            onRetry={() => void mine.refetch()}
          />
        ) : (
          <EmptyOrOffline
            reachable={reachable}
            loading={false}
            empty={
              <View className="items-center rounded-card border border-border bg-white px-card py-9">
                <View className="h-14 w-14 items-center justify-center rounded-pill bg-peacockSoft">
                  <Ionicons
                    name="people-circle-outline"
                    size={26}
                    color={tokens.colors.peacock}
                  />
                </View>
                <Text className="mt-4 text-center font-display text-xl text-stone">
                  No sangas yet
                </Text>
                <Text className="mt-2 max-w-80 text-center font-sans text-sm leading-6 text-stoneMuted">
                  Sangas are the smaller circles inside the congregation. Ask to
                  join one, or start your own and the temple will look at it.
                </Text>
              </View>
            }
          />
        )
      }
      footer={
        <View className="mt-section gap-2">
          <Pressable
            className="min-h-touch flex-row items-center justify-center rounded-button border border-border bg-white px-4"
            accessibilityRole="button"
            accessibilityLabel="Browse all sangas"
            onPress={browseSangas}
          >
            <Ionicons name="search" size={18} color={tokens.colors.indigo} />
            <Text className="ml-2 font-sans-bold text-base text-indigo">
              Browse all sangas
            </Text>
          </Pressable>
          <Pressable
            className="min-h-touch flex-row items-center justify-center rounded-button border border-border bg-white px-4"
            accessibilityRole="button"
            accessibilityLabel="Start a sanga"
            onPress={startSanga}
          >
            <Ionicons
              name="add-circle-outline"
              size={18}
              color={tokens.colors.indigo}
            />
            <Text className="ml-2 font-sans-bold text-base text-indigo">
              Start a sanga
            </Text>
          </Pressable>
        </View>
      }
    />
  );
}
