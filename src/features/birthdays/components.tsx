import { Ionicons } from "@expo/vector-icons";
import { Pressable, Text, View } from "react-native";

import tokens from "../../../design-tokens.json";
import { Avatar, LoadFailure, Skeleton } from "../../components/ui";
import { useServerReachable } from "../../lib/connectivity";
import { usePrototypeSession } from "../../store/usePrototypeSession";
import { useCurrentAccessProfile } from "../access/hooks";
import { FormError } from "../services/components";
import { errorMessage } from "../services/format";
import {
  canSeeBirthdays,
  useBirthdayAnnouncementDraft,
  useTodaysBirthdays,
  useUpcomingBirthdays,
} from "./hooks";
import { birthdaySummary } from "./summary";
import type { SuggestedAnnouncement, TodaysBirthday } from "./types";

/**
 * The shared Button keeps its label on one line, and this one is a whole
 * sentence with a devotee's name in the middle of it — it does not fit across
 * a small Android phone. Same marigold, same height, same type; only the label
 * is allowed to wrap.
 */
function WishButton({
  label,
  pending,
  onPress,
}: {
  label: string;
  pending: boolean;
  onPress: () => void;
}) {
  return (
    <Pressable
      className="min-h-touch flex-row items-center justify-center rounded-button bg-marigold px-4 py-3"
      accessibilityRole="button"
      accessibilityLabel={label}
      disabled={pending}
      onPress={onPress}
    >
      <Ionicons name="gift-outline" size={20} color={tokens.colors.stone} />
      <Text className="ml-2 min-w-0 flex-1 font-sans-bold text-base leading-6 text-stone">
        {pending ? "Opening the composer…" : label}
      </Text>
    </Pressable>
  );
}

function BirthdayRow({
  birthday,
  divided,
  pending,
  onWish,
}: {
  birthday: TodaysBirthday;
  divided: boolean;
  pending: boolean;
  onWish: () => void;
}) {
  const name = birthday.name?.trim() || "A devotee";

  return (
    <View className={divided ? "mt-4 border-t border-border pt-4" : "mt-4"}>
      <View className="flex-row items-center">
        <Avatar
          name={name}
          photoUrl={birthday.photo_url}
          size="small"
          tone="marigold"
        />
        <View className="ml-3 min-w-0 flex-1">
          <Text className="font-sans-bold text-base text-stone">{name}</Text>
          {birthday.turning_age !== null ? (
            <Text className="mt-0.5 font-sans text-sm text-stoneMuted">
              Turning {birthday.turning_age} today
            </Text>
          ) : null}
        </View>
      </View>
      <View className="mt-3">
        <WishButton
          label={`It’s ${name}’s birthday today — wish them`}
          pending={pending}
          onPress={onWish}
        />
      </View>
    </View>
  );
}

/**
 * "It's Ananda's birthday today — wish them", for the President and the Tech
 * Admin. It draws nothing for anybody else and nothing on a day with nobody
 * celebrating, which is most days.
 *
 * It posts nothing. It reads the temple's suggested wording on a tap and hands
 * it to `onWish`, whose screen opens the composer with it already filled in; a
 * person edits it and presses Post.
 *
 * Self-contained on purpose — it reads its own permission, its own list and
 * its own draft — so that any screen the temple wants it on is one line.
 */
export function BirthdayPrompt({
  onWish,
}: {
  onWish: (prefill: SuggestedAnnouncement) => void;
}) {
  const activeUserId = usePrototypeSession((state) => state.activeUserId);
  const profile = useCurrentAccessProfile(activeUserId);
  const role =
    (profile.data?.role ?? "devotee");
  const permitted = canSeeBirthdays(role);

  const reachable = useServerReachable();
  const birthdays = useTodaysBirthdays(permitted);
  const draft = useBirthdayAnnouncementDraft();

  if (!permitted) return null;

  if (birthdays.isLoading) {
    return (
      <View className="mb-3 rounded-card border border-border bg-white p-card">
        <Skeleton height={14} width="45%" />
        <View className="mt-3">
          <Skeleton height={20} width="70%" />
        </View>
      </View>
    );
  }

  if (birthdays.isError && birthdays.data === undefined) {
    return (
      <View className="mb-3">
        <LoadFailure
          reachable={reachable}
          message={errorMessage(
            birthdays.error,
            "Today’s birthdays could not be loaded.",
          )}
          onRetry={() => void birthdays.refetch()}
        />
      </View>
    );
  }

  const rows = birthdays.data ?? [];
  if (!rows.length) return null;

  const draftError = errorMessage(
    draft.error,
    "The suggested wording could not be read.",
  );

  return (
    <View className="mb-3 rounded-card border border-border bg-white p-card">
      <View className="flex-row items-center">
        <View className="h-10 w-10 items-center justify-center rounded-pill bg-marigoldSoft">
          <Ionicons
            name="gift-outline"
            size={20}
            color={tokens.colors.marigold}
          />
        </View>
        <View className="ml-3 min-w-0 flex-1">
          <Text className="font-display text-xl leading-7 text-stone">
            {rows.length > 1 ? "Birthdays today" : "A birthday today"}
          </Text>
          <Text className="mt-0.5 font-sans text-sm leading-5 text-stoneMuted">
            Only you and the other temple admins see this.
          </Text>
        </View>
      </View>

      {rows.map((birthday, index) => (
        <BirthdayRow
          key={birthday.devotee_id}
          birthday={birthday}
          divided={index > 0}
          pending={draft.isPending && draft.variables === birthday.devotee_id}
          onWish={() =>
            draft.mutate(birthday.devotee_id, { onSuccess: onWish })
          }
        />
      ))}

      {draftError ? <FormError message={draftError} /> : null}
    </View>
  );
}

/**
 * The birthday button on the noticeboard.
 *
 * One compact row rather than the full prompt, because the noticeboard is
 * about announcements and a card per celebrant pushed them all down the page.
 * It says how many are celebrating today and asks the question; the list
 * behind it is where the temple acts.
 *
 * Draws nothing at all for anybody without `app.view_all`, and nothing on a
 * day with no birthday inside the window — which is most days.
 */
export function BirthdaysSummaryButton({
  onOpen,
  days = 60,
}: {
  onOpen: () => void;
  days?: number;
}) {
  const activeUserId = usePrototypeSession((state) => state.activeUserId);
  const profile = useCurrentAccessProfile(activeUserId);
  const role =
    (profile.data?.role ?? "devotee");
  const permitted = canSeeBirthdays(role);

  const birthdays = useUpcomingBirthdays(days, permitted);

  if (!permitted) return null;

  if (birthdays.isLoading) {
    return (
      <View className="mb-3 rounded-card border border-border bg-white p-card">
        <Skeleton height={18} width="60%" />
        <View className="mt-2">
          <Skeleton height={14} width="35%" />
        </View>
      </View>
    );
  }

  // A failure here is silent on purpose. This is a convenience on somebody
  // else's screen, and a red box about birthdays sitting above the temple's
  // announcements reads as the noticeboard being broken.
  const summary = birthdaySummary(birthdays.data ?? []);
  if (!summary) return null;

  return (
    <Pressable
      className={`mb-3 min-h-touch flex-row items-center rounded-card border p-card ${
        summary.today
          ? "border-marigold bg-marigoldSoft"
          : "border-border bg-white"
      }`}
      accessibilityRole="button"
      accessibilityLabel={`${summary.title}. ${summary.detail}`}
      accessibilityHint="Opens the list of upcoming birthdays"
      onPress={onOpen}
    >
      <View
        className={`h-10 w-10 items-center justify-center rounded-pill ${
          summary.today ? "bg-white" : "bg-marigoldSoft"
        }`}
      >
        <Ionicons
          name="gift-outline"
          size={20}
          color={tokens.colors.marigold}
        />
      </View>
      <View className="ml-3 min-w-0 flex-1">
        <Text
          className="font-sans-bold text-base leading-6 text-stone"
          numberOfLines={1}
        >
          {summary.title}
        </Text>
        <Text
          className={`mt-0.5 font-sans text-sm leading-5 ${
            summary.today ? "text-stone" : "text-stoneMuted"
          }`}
          numberOfLines={1}
        >
          {summary.detail}
        </Text>
      </View>
      <Ionicons
        name="chevron-forward"
        size={20}
        color={tokens.colors.stoneMuted}
      />
    </Pressable>
  );
}
