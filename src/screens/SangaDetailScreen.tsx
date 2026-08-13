import { Ionicons } from "@expo/vector-icons";
import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import { useEffect, useState } from "react";
import { Text, View } from "react-native";

import tokens from "../../design-tokens.json";
import { LoadFailure, Screen, SkeletonCard } from "../components/ui";
import {
  SangaActionButton,
  memberCountLabel,
  sangaAffordance,
} from "../features/sanga/components";
import {
  useAskToJoinSanga,
  useSangaRealtime,
  useSangaViewer,
} from "../features/sanga/hooks";
import { FormError } from "../features/services/components";
import { errorMessage } from "../features/services/format";
import { useServerReachable } from "../lib/connectivity";
import type { DevoteesStackParamList } from "../navigation/types";

type Props = NativeStackScreenProps<DevoteesStackParamList, "SangaDetail">;

/**
 * The door into a sanga the devotee is standing outside of.
 *
 * Anybody who is already in — and the President or Tech Admin, who may act on
 * any sanga without joining it — never sees this page: tapping a sanga takes
 * them straight to its thread. So this one has a single job, which is to say
 * what the circle is and let them ask to be let in.
 *
 * It deliberately does not show who is in it. Who a devotee sits with on a
 * Tuesday evening is the circle's business until the circle has said yes; the
 * one person named is whoever started it, because that is who the ask is
 * addressed to.
 */
export function SangaDetailScreen({ navigation, route }: Props) {
  const { sangaId, name } = route.params;
  const reachable = useServerReachable();
  const viewer = useSangaViewer(sangaId, { withRoll: false });
  const { capabilities, sangas, summary } = viewer;
  // An ask answered while this page is open should open the door on it.
  useSangaRealtime(sangaId);

  const { ask, askingSangaId } = useAskToJoinSanga();
  const [askError, setAskError] = useState<string | null>(null);

  // A sanga is only in the browse list once it is approved, so an absent
  // summary on a first load is "not arrived yet", not "gone".
  const summaryFailed = sangas.isError && sangas.data === undefined;
  const loadingSummary = sangas.isLoading && !summary;

  /**
   * The page every other entry point can safely land on. Whoever may go
   * straight in is sent straight in — replaced rather than pushed, so the back
   * button returns to wherever they came from rather than to this page they
   * were never meant to see.
   */
  const mayEnter = capabilities.isMember || capabilities.overseesApp;
  useEffect(() => {
    if (!mayEnter) return;
    navigation.replace("SangaChat", { sangaId, name: summary?.name ?? name });
  }, [mayEnter, name, navigation, sangaId, summary?.name]);

  const affordance = summary ? sangaAffordance(summary) : "ask";
  const sangaName = summary?.name ?? name;

  const requestToJoin = () => {
    setAskError(null);
    ask(sangaId, (caught) =>
      setAskError(
        errorMessage(caught, `Your ask to join ${sangaName} did not send.`),
      ),
    );
  };

  return (
    <Screen topInset={false}>
      <View className="rounded-card border border-border bg-white p-card">
        <View className="flex-row items-start">
          <View className="h-12 w-12 items-center justify-center rounded-pill border border-peacock/10 bg-peacockSoft">
            <Ionicons
              name="people-outline"
              size={22}
              color={tokens.colors.peacock}
            />
          </View>
          <View className="ml-3 min-w-0 flex-1">
            <Text
              className="font-display text-xl leading-7 text-stone"
              accessibilityRole="header"
              numberOfLines={3}
            >
              {sangaName}
            </Text>
            <Text className="mt-0.5 font-sans text-sm leading-5 text-stoneMuted">
              {viewer.memberCount === null
                ? "Loading…"
                : memberCountLabel(viewer.memberCount)}
            </Text>
          </View>
        </View>

        <Text className="mt-3 font-sans text-sm leading-6 text-stone">
          {summary?.description?.trim() ||
            "This sanga has not written a description yet."}
        </Text>

        {summary?.created_by_name ? (
          <Text className="mt-3 font-sans text-sm text-stoneMuted">
            Started by {summary.created_by_name}
          </Text>
        ) : null}

        {/* The one thing a devotee outside can do. It is an ask, not a join:
            the sanga's admin answers it. */}
        <View className="mt-4 flex-row">
          <SangaActionButton
            name={sangaName}
            affordance={affordance}
            busy={askingSangaId === sangaId}
            onPress={requestToJoin}
          />
        </View>
      </View>

      {askError ? <FormError message={askError} /> : null}

      {loadingSummary ? (
        <View className="mt-section">
          <SkeletonCard />
        </View>
      ) : summaryFailed ? (
        <View className="mt-section">
          <LoadFailure
            reachable={reachable}
            message={errorMessage(sangas.error, "This sanga could not load.")}
            onRetry={() => void sangas.refetch()}
          />
        </View>
      ) : (
        <View className="mt-section rounded-card border border-border bg-white px-card py-6">
          <Text className="text-center font-sans text-sm leading-5 text-stoneMuted">
            {affordance === "requested"
              ? "Once the sanga's admin says yes, the group chat opens here and you will see who else is in it."
              : "Ask to join, and the group chat opens here once the sanga's admin says yes."}
          </Text>
        </View>
      )}
    </Screen>
  );
}
