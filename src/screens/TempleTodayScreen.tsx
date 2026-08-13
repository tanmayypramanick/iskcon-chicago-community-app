import { Ionicons } from "@expo/vector-icons";
import { useIsFocused } from "@react-navigation/native";
import { useEffect, useState } from "react";
import { Text, View } from "react-native";

import tokens from "../../design-tokens.json";
import {
  Avatar,
  AvatarViewer,
  EmptyOrOffline,
  ListScreen,
  LoadFailure,
} from "../components/ui";
import { useTemplePresence } from "../features/presence/hooks";
import type { TemplePresencePerson } from "../features/presence/types";
import { errorMessage } from "../features/services/format";
import { formatChicagoTime } from "../lib/chicagoDate";
import { useServerReachable } from "../lib/connectivity";
import { usePrototypeSession } from "../store/usePrototypeSession";
import { RowsSkeleton } from "./DevoteesScreen";

/** When the devotee put themselves on today's list, said plainly. */
function checkedInLine(person: TemplePresencePerson) {
  const at = new Date(person.checked_in_at ?? person.updated_at);
  if (Number.isNaN(at.getTime())) return "Checked in";
  return `Checked in at ${formatChicagoTime(at)}`;
}

/** One devotee's row on today's list. */
function PresenceRow({
  person,
  isFirst,
  isLast,
  onOpenPhoto,
}: {
  person: TemplePresencePerson;
  isFirst: boolean;
  isLast: boolean;
  onOpenPhoto: () => void;
}) {
  const line = checkedInLine(person);

  return (
    <View
      className={`min-h-[76px] flex-row items-center border-x border-border bg-white px-card py-3 ${
        isFirst ? "rounded-t-card border-t" : ""
      } ${isLast ? "rounded-b-card border-b" : "border-b"}`}
      accessibilityLabel={`${person.name}, ${line}`}
    >
      <Avatar
        name={person.name}
        photoUrl={person.photo_url}
        tone="peacock"
        onPress={onOpenPhoto}
      />
      <View className="ml-4 min-w-0 flex-1">
        <Text className="font-sans-bold text-lg text-stone" numberOfLines={2}>
          {person.name}
        </Text>
        <View className="mt-0.5 flex-row items-center">
          <Ionicons
            name="checkmark-circle-outline"
            size={14}
            color={tokens.colors.stoneMuted}
          />
          <Text
            className="ml-1.5 min-w-0 flex-1 font-sans text-sm text-stoneMuted"
            numberOfLines={2}
          >
            {line}
          </Text>
        </View>
      </View>
    </View>
  );
}

export function TempleTodayScreen() {
  const isFocused = useIsFocused();
  const activeUserId = usePrototypeSession((state) => state.activeUserId);
  const presence = useTemplePresence(activeUserId);
  const reachable = useServerReachable();

  const [viewingPerson, setViewingPerson] = useState<{
    name: string;
    photo_url?: string | null;
    subtitle?: string;
  } | null>(null);

  const people = presence.data?.people ?? [];

  useEffect(() => {
    if (!isFocused || !activeUserId) return;
    void presence.refetch();
  }, [activeUserId, isFocused, presence.refetch]);

  const presenceFailed = presence.isError && presence.data === undefined;

  const listHeader = (
    <>
      <AvatarViewer
        person={viewingPerson}
        onClose={() => setViewingPerson(null)}
      />

      {/* Withheld until a list has actually arrived: "0 people" while it loads
          is a claim about the temple rather than about the request. */}
      {presence.data ? (
        <Text className="mb-3 mt-1 font-sans text-sm text-stoneMuted">
          {people.length === 1
            ? "1 person at the temple today"
            : `${people.length} people at the temple today`}
        </Text>
      ) : null}
    </>
  );

  return (
    <ListScreen
      topInset={false}
      data={people}
      keyExtractor={(person) => person.user_id}
      header={listHeader}
      renderItem={(person, index) => (
        <PresenceRow
          person={person}
          isFirst={index === 0}
          isLast={index === people.length - 1}
          onOpenPhoto={() =>
            setViewingPerson({
              name: person.name,
              photo_url: person.photo_url,
              subtitle: checkedInLine(person),
            })
          }
        />
      )}
      empty={
        presence.isLoading ? (
          <RowsSkeleton />
        ) : presenceFailed ? (
          <LoadFailure
            reachable={reachable}
            message={errorMessage(
              presence.error,
              "Today’s temple presence could not be loaded.",
            )}
            onRetry={() => void presence.refetch()}
          />
        ) : (
          <EmptyOrOffline
            reachable={reachable}
            loading={false}
            empty={
              <View className="items-center rounded-card border border-border bg-white px-card py-9">
                <Ionicons
                  name="leaf-outline"
                  size={32}
                  color={tokens.colors.peacock}
                />
                <Text className="mt-3 text-center font-sans-bold text-base text-stone">
                  The first check-in is still ahead
                </Text>
                <Text className="mt-1 text-center font-sans text-sm leading-5 text-stoneMuted">
                  Check in from Home when you arrive, and you will appear here
                  for the rest of the day.
                </Text>
              </View>
            }
          />
        )
      }
    />
  );
}
