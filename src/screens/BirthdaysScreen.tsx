import { Ionicons } from "@expo/vector-icons";
import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import { useState } from "react";
import { Pressable, Text, View } from "react-native";

import tokens from "../../design-tokens.json";
import {
  Avatar,
  EmptyOrOffline,
  ListScreen,
  LoadFailure,
  ScreenTitle,
  SkeletonCard,
} from "../components/ui";
import { useCurrentAccessProfile } from "../features/access/hooks";
import {
  canSeeBirthdays,
  useBirthdayAnnouncementDraft,
  useUpcomingBirthdays,
} from "../features/birthdays/hooks";
import { birthdayRowWhen } from "../features/birthdays/summary";
import {
  birthdayAnnouncementPrefill,
  type UpcomingBirthday,
} from "../features/birthdays/types";
import { FormError } from "../features/services/components";
import { errorMessage } from "../features/services/format";
import { useServerReachable } from "../lib/connectivity";
import type { HomeStackParamList } from "../navigation/types";
import { usePrototypeSession } from "../store/usePrototypeSession";
import {
  CreateAnnouncementModal,
  type AnnouncementPrefill,
} from "./CreateAnnouncementScreen";

type Props = NativeStackScreenProps<HomeStackParamList, "Birthdays">;

/** How far ahead the list looks. Two months is a season of the temple's year. */
const HORIZON_DAYS = 60;

function BirthdayCard({
  birthday,
  pending,
  onWish,
}: {
  birthday: UpcomingBirthday;
  pending: boolean;
  onWish: () => void;
}) {
  const name = birthday.name?.trim() || "A devotee";
  const isToday = birthday.days_away === 0;

  return (
    <View
      className={`mb-3 rounded-card border p-card ${
        isToday ? "border-marigold bg-marigoldSoft" : "border-border bg-white"
      }`}
    >
      <View className="flex-row items-center">
        <Avatar
          name={name}
          photoUrl={birthday.photo_url}
          size="medium"
          tone={isToday ? "marigold" : "indigo"}
        />
        <View className="ml-3 min-w-0 flex-1">
          <Text
            className="font-sans-bold text-base leading-6 text-stone"
            numberOfLines={1}
          >
            {name}
          </Text>
          <Text
            className={`mt-0.5 font-sans text-sm leading-5 ${
              isToday ? "text-stone" : "text-stoneMuted"
            }`}
          >
            {birthdayRowWhen(birthday)}
          </Text>
        </View>
        {isToday ? (
          <View className="ml-2 h-9 w-9 items-center justify-center rounded-pill bg-white">
            <Ionicons
              name="gift"
              size={18}
              color={tokens.colors.marigold}
            />
          </View>
        ) : null}
      </View>

      {/*
        The button only appears on the day itself. A greeting posted a week
        early is not a greeting, and offering the button every day invites
        exactly that.
      */}
      {isToday ? (
        <View className="mt-3">
          <Pressable
            className="min-h-touch flex-row items-center justify-center rounded-button bg-marigold px-4 py-3"
            accessibilityRole="button"
            accessibilityLabel={`Post a birthday announcement for ${name}`}
            disabled={pending}
            onPress={onWish}
          >
            <Ionicons
              name="megaphone-outline"
              size={20}
              color={tokens.colors.stone}
            />
            <Text className="ml-2 min-w-0 flex-1 font-sans-bold text-base leading-6 text-stone">
              {pending ? "Opening the composer…" : "Post an announcement"}
            </Text>
          </Pressable>
        </View>
      ) : null}
    </View>
  );
}

/**
 * Every birthday coming up, for the President and the Tech Admin.
 *
 * The congregation never sees this screen and never sees these dates. What the
 * congregation may see is an announcement, and only because a person read this
 * list, pressed the button, read the wording and pressed Post.
 */
export function BirthdaysScreen({ navigation }: Props) {
  const activeUserId = usePrototypeSession((state) => state.activeUserId);
  const previewRole = usePrototypeSession((state) => state.previewRole);
  const profile = useCurrentAccessProfile(activeUserId);
  const role =
    __DEV__ && previewRole ? previewRole : (profile.data?.role ?? "devotee");
  const permitted = canSeeBirthdays(role);

  const reachable = useServerReachable();
  const birthdays = useUpcomingBirthdays(HORIZON_DAYS, permitted);
  const draft = useBirthdayAnnouncementDraft();

  const [prefill, setPrefill] = useState<AnnouncementPrefill | null>(null);
  const [composerOpen, setComposerOpen] = useState(false);

  if (!permitted) {
    return (
      <ListScreen
        topInset={false}
        data={[]}
        keyExtractor={() => "none"}
        renderItem={() => null}
        header={
          <View className="items-center rounded-card border border-border bg-white px-card py-10">
            <Ionicons
              name="lock-closed-outline"
              size={28}
              color={tokens.colors.indigo}
            />
            <Text className="mt-3 text-center font-sans-bold text-base text-stone">
              Only the President and the Tech Admin
            </Text>
            <Text className="mt-1 text-center font-sans text-sm leading-5 text-stoneMuted">
              A devotee’s date of birth is part of the temple’s record, so the
              list of birthdays is not shown to the congregation.
            </Text>
          </View>
        }
      />
    );
  }

  const rows = birthdays.data ?? [];
  const draftError = errorMessage(
    draft.error,
    "The suggested wording could not be read.",
  );

  return (
    <>
      <ListScreen
        topInset={false}
        data={rows}
        keyExtractor={(birthday) => birthday.devotee_id}
        renderItem={(birthday) => (
          <BirthdayCard
            birthday={birthday}
            pending={
              draft.isPending && draft.variables === birthday.devotee_id
            }
            onWish={() =>
              draft.mutate(birthday.devotee_id, {
                onSuccess: (words) => {
                  setPrefill(birthdayAnnouncementPrefill(words));
                  setComposerOpen(true);
                },
              })
            }
          />
        )}
        header={
          <>
            <ScreenTitle eyebrow="The temple’s record">Birthdays</ScreenTitle>
            <Text className="mb-3 font-sans text-sm leading-5 text-stoneMuted">
              The next two months, nearest first. Only you and the other temple
              admins see this.
            </Text>
            {draftError ? <FormError message={draftError} /> : null}
            {birthdays.isError && birthdays.data === undefined ? (
              <View className="mb-3">
                <LoadFailure
                  reachable={reachable}
                  message={errorMessage(
                    birthdays.error,
                    "Birthdays could not be loaded.",
                  )}
                  onRetry={() => void birthdays.refetch()}
                />
              </View>
            ) : null}
          </>
        }
        empty={
          birthdays.isError && birthdays.data === undefined ? null : (
            <EmptyOrOffline
              reachable={reachable}
              loading={birthdays.isLoading}
              loadingLabel="Reading the temple’s record…"
              empty={
                <View className="items-center rounded-card border border-border bg-white px-card py-10">
                  <Ionicons
                    name="gift-outline"
                    size={28}
                    color={tokens.colors.marigold}
                  />
                  <Text className="mt-3 text-center font-sans-bold text-base text-stone">
                    No birthdays in the next two months
                  </Text>
                  <Text className="mt-1 text-center font-sans text-sm leading-5 text-stoneMuted">
                    They appear here as they come up, and on the day one falls
                    you can post an announcement from this list.
                  </Text>
                </View>
              }
            />
          )
        }
      />

      <CreateAnnouncementModal
        visible={composerOpen}
        prefill={prefill}
        onClose={() => {
          setComposerOpen(false);
          setPrefill(null);
          // Back to the noticeboard, where the announcement they just wrote
          // now is: staying on a list of birthdays hides the thing they did.
          navigation.goBack();
        }}
      />
    </>
  );
}
