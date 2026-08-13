import { Ionicons } from "@expo/vector-icons";
import type { NavigationProp } from "@react-navigation/native";
import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import { useState } from "react";
import { Pressable, Text } from "react-native";

import tokens from "../../design-tokens.json";
import { Screen, ScreenTitle } from "../components/ui";
import { useCurrentAccessProfile } from "../features/access/hooks";
import { hasAccessPermission } from "../features/access/model";
import { openConversation } from "../features/messaging/api";
import { FormError } from "../features/services/components";
import { errorMessage } from "../features/services/format";
import type { HomeStackParamList, MainTabParamList } from "../navigation/types";
import { usePrototypeSession } from "../store/usePrototypeSession";
import { DevoteeSevaProfilePanel } from "./DevoteeSevaProfileScreen";

type Props = NativeStackScreenProps<HomeStackParamList, "SevaCareDevotee">;

/**
 * One devotee's seva history, off a Seva Care row or off the board.
 *
 * This used to be a fourth coordinator view of the same devotee: its own read
 * of `seva_balance_for_devotee`, its own row component, its own sentences — a
 * shorter and quietly different answer to the question the Devotees tab already
 * answers in full. It now draws that same panel, so a President reaching one
 * devotee from Seva Care and another from their profile reads the same thing
 * about both.
 *
 * The one thing it keeps of its own is the way to say something: Seva Care
 * exists to start a conversation, and the row that sent the President here
 * scrolls away behind the record.
 */
export function SevaCareDevoteeScreen({ navigation, route }: Props) {
  const { devoteeId, name } = route.params;
  const activeUserId = usePrototypeSession((state) => state.activeUserId);
  const previewRole = usePrototypeSession((state) => state.previewRole);
  const profile = useCurrentAccessProfile(activeUserId);
  const role =
    __DEV__ && previewRole ? previewRole : (profile.data?.role ?? "devotee");
  const mayViewAll = hasAccessPermission(role, "app.view_all");

  const [opening, setOpening] = useState(false);
  const [chatError, setChatError] = useState<string | null>(null);

  // The same path the Devotees tab uses: open_conversation returns the thread
  // either way, and the thread itself belongs to that tab.
  const message = async () => {
    setChatError(null);
    setOpening(true);
    try {
      const conversationId = await openConversation(devoteeId);
      navigation.getParent<NavigationProp<MainTabParamList>>()?.navigate(
        "Devotees",
        {
          screen: "Chat",
          params: { conversationId, devoteeId, name },
        } as never,
      );
    } catch (caught) {
      setChatError(
        errorMessage(caught, "That conversation could not be opened.") ?? null,
      );
    } finally {
      setOpening(false);
    }
  };

  return (
    <Screen topInset={false}>
      <ScreenTitle eyebrow="Seva Care">{name}</ScreenTitle>

      {mayViewAll ? (
        <>
          <Pressable
            className="mb-section min-h-touch flex-row items-center justify-center rounded-button bg-indigoSoft px-4"
            accessibilityRole="button"
            accessibilityState={{ disabled: opening }}
            accessibilityLabel={`Message ${name}`}
            disabled={opening}
            onPress={() => void message()}
          >
            <Ionicons
              name="chatbubble-ellipses-outline"
              size={18}
              color={tokens.colors.indigo}
            />
            <Text className="ml-2 font-sans-bold text-base text-indigo">
              {opening ? "Opening…" : `Message ${name.split(" ")[0]}`}
            </Text>
          </Pressable>

          {chatError ? <FormError message={chatError} /> : null}
        </>
      ) : null}

      <DevoteeSevaProfilePanel devoteeId={devoteeId} name={name} />
    </Screen>
  );
}
