import { Ionicons } from "@expo/vector-icons";
import { useIsFocused } from "@react-navigation/native";
import { useEffect, useMemo, useState } from "react";
import { Text, TextInput, View } from "react-native";

import tokens from "../../design-tokens.json";
import {
  Avatar,
  AvatarViewer,
  ListScreen,
  ScreenTitle,
} from "../components/ui";
import { accessRoleLabels, isAccessRole } from "../features/access/model";
import { useTemplePresence } from "../features/presence/hooks";
import { useServiceDashboard } from "../features/services/hooks";
import { usePrototypeSession } from "../store/usePrototypeSession";

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

export function DirectoryScreen() {
  const isFocused = useIsFocused();
  const activeUserId = usePrototypeSession((state) => state.activeUserId);
  const dashboard = useServiceDashboard(activeUserId);
  const presence = useTemplePresence(activeUserId);
  const [search, setSearch] = useState("");
  const [viewingPerson, setViewingPerson] = useState<{
    name: string;
    photo_url?: string | null;
    subtitle?: string;
  } | null>(null);

  useEffect(() => {
    if (!isFocused || !activeUserId) return;
    void Promise.all([dashboard.refetch(), presence.refetch()]);
  }, [activeUserId, dashboard.refetch, isFocused, presence.refetch]);

  const atTempleIds = useMemo(
    () => new Set(presence.data?.people.map((person) => person.user_id) ?? []),
    [presence.data?.people],
  );
  const filteredDevotees = useMemo(() => {
    const query = search.trim().toLocaleLowerCase();
    return (dashboard.data?.devotees ?? []).filter(
      (devotee) => !query || devotee.name.toLocaleLowerCase().includes(query),
    );
  }, [dashboard.data?.devotees, search]);

  const error = dashboard.error ?? presence.error;

  // The list waits for a settled load, so an error or spinner in the header
  // is never shown next to a stale roster.
  const showList = !error && !dashboard.isLoading;

  return (
    <ListScreen
      data={showList ? filteredDevotees : []}
      keyExtractor={(devotee) => devotee.id}
      header={
        <>
          <ScreenTitle eyebrow="Our community">Directory</ScreenTitle>

          <AvatarViewer
            person={viewingPerson}
            onClose={() => setViewingPerson(null)}
          />

          <View className="mb-section min-h-touch flex-row items-center rounded-button border border-border bg-white px-4">
            <Ionicons name="search" size={21} color={tokens.colors.stoneMuted} />
            <TextInput
              className="ml-3 flex-1 py-3 font-sans text-base text-stone"
              accessibilityLabel="Search devotees"
              autoCapitalize="words"
              autoCorrect={false}
              placeholder="Search by devotee name"
              placeholderTextColor={tokens.colors.stoneMuted}
              value={search}
              onChangeText={setSearch}
            />
          </View>

          {error ? (
            <View className="rounded-card border border-vermilion bg-white p-card">
              <Text className="font-sans-bold text-base text-vermilion">
                The directory could not be refreshed.
              </Text>
              <Text className="mt-1 font-sans text-sm text-stoneMuted">
                Check your connection and pull the screen open again.
              </Text>
            </View>
          ) : dashboard.isLoading ? (
            <View className="items-center rounded-card border border-border bg-white p-card">
              <Text className="font-sans text-base text-stoneMuted">
                Loading the community…
              </Text>
            </View>
          ) : null}
        </>
      }
      renderItem={(devotee, index) => {
        const isAtTemple = atTempleIds.has(devotee.id);
        const roleLabel = isAccessRole(devotee.role_name)
          ? accessRoleLabels[devotee.role_name]
          : "Devotee";
        const isFirst = index === 0;
        const isLast = index === filteredDevotees.length - 1;

        return (
          <View
            className={`min-h-[76px] flex-row items-center border-x border-border bg-white px-card py-3 ${
              isFirst ? "rounded-t-card border-t" : ""
            } ${isLast ? "rounded-b-card border-b" : "border-b"}`}
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
              <Text
                className="font-sans-bold text-lg text-stone"
                numberOfLines={2}
              >
                {devotee.name}
              </Text>
              <Text className="mt-0.5 font-sans text-sm text-stoneMuted">
                {roleLabel}
              </Text>
            </View>
            {isAtTemple ? (
              <View className="ml-2 max-w-[104px] flex-shrink flex-row items-center rounded-pill bg-peacockSoft px-2.5 py-1.5">
                <View className="mr-1.5 h-2 w-2 rounded-pill bg-peacock" />
                <Text
                  className="flex-shrink font-sans-bold text-xs text-peacock"
                  numberOfLines={1}
                >
                  At temple
                </Text>
              </View>
            ) : null}
          </View>
        );
      }}
      empty={
        showList ? (
          <View className="items-center rounded-card border border-border bg-white px-card py-8">
            <Ionicons
              name="people-outline"
              size={30}
              color={tokens.colors.peacock}
            />
            <Text className="mt-3 text-center font-sans-bold text-base text-stone">
              {search ? "No matching devotee" : "No devotee profiles yet"}
            </Text>
            <Text className="mt-1 text-center font-sans text-sm text-stoneMuted">
              {search
                ? "Try a different spelling or shorter name."
                : "New verified accounts will appear here."}
            </Text>
          </View>
        ) : null
      }
    />
  );
}
