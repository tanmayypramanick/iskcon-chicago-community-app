import { Ionicons } from "@expo/vector-icons";
import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import { useState } from "react";
import { Alert, Image, Pressable, Text, View } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";

import tokens from "../../design-tokens.json";
import { ModalScreen } from "../components/ModalScreen";
import {
  RemoteImage,
  Screen,
  ScreenTitle,
  Skeleton,
} from "../components/ui";
import {
  DarshanPhoto,
  darshanPictureCount,
  formatDarshanDay,
  useDarshanDayKeys,
} from "../features/dailyDarshan/components";
import {
  useDailyDarshan,
  useDeleteDailyDarshan,
} from "../features/dailyDarshan/hooks";
import { FormError } from "../features/services/components";
import { errorMessage } from "../features/services/format";
import { sharePicture } from "../lib/sharePicture";
import type { HomeStackParamList } from "../navigation/types";

type Props = NativeStackScreenProps<HomeStackParamList, "DarshanDay">;

/**
 * One day of darshan, in full.
 *
 * Everything the temple posted on that day and nothing from any other — the
 * pictures at the size the Deities deserve, each with Whom it shows and whose
 * hands dressed Them, the note, and who posted it. There is no card border and
 * no carousel: the photographs are stacked the way the temple would print them,
 * and chrome is what a devotee has to look past to see the Deities.
 */
export function DarshanDayScreen({ navigation, route }: Props) {
  const { darshanId, darshanOn } = route.params;
  const { todayKey, yesterdayKey } = useDarshanDayKeys();
  // The week is already in the cache — the day is read out of it rather than
  // fetched again, so opening a day shows a picture that is already on screen
  // instead of a spinner over it.
  const week = useDailyDarshan();
  const day = (week.data ?? []).find((row) => row.id === darshanId) ?? null;
  const remove = useDeleteDailyDarshan();

  const [removeError, setRemoveError] = useState<string | null>(null);
  const [viewingImage, setViewingImage] = useState<string | null>(null);
  const [savingImage, setSavingImage] = useState(false);

  const dayLabel = formatDarshanDay(darshanOn, todayKey, yesterdayKey);

  const savePicture = (url: string) => {
    setSavingImage(true);
    void sharePicture(url, "darshan")
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

  /**
   * Taking a day down is irreversible and takes the whole day with it, so the
   * question names all three of the things that go — the pictures, the Deities'
   * names and the dressers — and says how many, rather than asking "are you
   * sure" about an amount the devotee has to remember for themselves.
   */
  const confirmDelete = () => {
    if (!day) return;
    setRemoveError(null);
    Alert.alert(
      `Take down ${dayLabel}'s darshan?`,
      `${
        day.images.length === 1
          ? "The picture"
          : `All ${day.images.length} pictures`
      } from ${dayLabel}, the Deities' names and who dressed Them will be removed for every devotee. This cannot be undone.`,
      [
        { text: "Keep", style: "cancel" },
        {
          text: "Take down",
          style: "destructive",
          onPress: () =>
            remove.mutate(day.id, {
              // The day is gone from the week the moment it is asked for, so
              // going back lands on a list that no longer holds it.
              onSuccess: () => navigation.goBack(),
              onError: (caught) =>
                setRemoveError(
                  errorMessage(caught, "That darshan could not be taken down."),
                ),
            }),
        },
      ],
    );
  };

  if (!day) {
    return (
      <Screen>
        {week.isLoading ? (
          <View className="mt-2">
            <Skeleton height={14} width="30%" />
            <View className="mt-4">
              <Skeleton height={360} />
            </View>
          </View>
        ) : (
          <View className="mt-section items-center rounded-card border border-border bg-white px-card py-9">
            <View className="h-14 w-14 items-center justify-center rounded-pill bg-sandalwood">
              <Ionicons
                name="flower-outline"
                size={26}
                color={tokens.colors.stoneMuted}
              />
            </View>
            <Text className="mt-4 text-center font-display text-xl text-stone">
              This darshan is no longer posted
            </Text>
            <Text className="mt-2 max-w-80 text-center font-sans text-sm leading-6 text-stoneMuted">
              Darshan is kept for the current week, and a day can also be taken
              down by the temple.
            </Text>
          </View>
        )}
      </Screen>
    );
  }

  const poster = day.posted_by_name?.trim();

  return (
    <>
      <Screen>
        <ScreenTitle
          eyebrow={darshanPictureCount(day)}
          action={
            // Whether this devotee may take the day down is the server's
            // answer, carried on the row. Nothing here re-derives the rule.
            day.can_delete ? (
              <Pressable
                className="min-h-touch flex-row items-center justify-center rounded-pill border border-border bg-white px-4"
                accessibilityRole="button"
                accessibilityLabel={`Take down the darshan for ${dayLabel}`}
                onPress={confirmDelete}
              >
                <Ionicons
                  name="trash-outline"
                  size={17}
                  color={tokens.colors.vermilion}
                />
                <Text className="ml-1.5 font-sans-bold text-sm text-vermilion">
                  Take down
                </Text>
              </Pressable>
            ) : undefined
          }
        >
          {dayLabel}
        </ScreenTitle>

        {removeError ? <FormError message={removeError} /> : null}

        {day.note ? (
          <Text className="font-sans text-base leading-6 text-stone">
            {day.note}
          </Text>
        ) : null}

        {day.images.map((image) => (
          <DarshanPhoto
            key={`${image.position}-${image.imageUrl}`}
            image={image}
            dayLabel={dayLabel}
            onOpen={setViewingImage}
          />
        ))}

        {poster ? (
          <Text className="mt-5 font-sans text-xs text-stoneMuted">
            {`Posted by ${poster}`}
          </Text>
        ) : null}
      </Screen>

      <ModalScreen
        visible={viewingImage !== null}
        onClose={() => setViewingImage(null)}
        title="Darshan"
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
            <RemoteImage
              uri={viewingImage}
              style={{ width: "100%", height: "82%" }}
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
