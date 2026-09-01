import { Ionicons } from "@expo/vector-icons";
import { Pressable, Text, View } from "react-native";

import tokens from "../../../design-tokens.json";
import { Avatar } from "../../components/ui";
import { FormError } from "./components";
import { errorMessage, formatServiceDate, formatServiceTime } from "./format";
import {
  useAnswerMyWeeklySeva,
  useMyWeeklySevaToAnswer,
  useWeeklySevaAnswers,
} from "./hooks";
import type { WeeklySevaAnswer, WeeklySevaToAnswer } from "./types";

/*
 * Kept out of components.tsx on purpose.
 *
 * That module is presentational: it takes props and draws. These two read the
 * server for themselves, so putting them there made every screen that renders
 * any seva component pull in the data layer — and with it the native storage
 * the Supabase client opens, which a screen test has no business needing.
 */

/**
 * "Did you serve this seva?"
 *
 * A weekly rota counts on completion alone, so this asks nothing of a devotee
 * who ignores it — the hours stay. The answer that matters is "I missed it",
 * which hands the credit back and tells whoever set the rota up that the day
 * went uncovered. Drawn only when there is something to answer, which on most
 * days is nothing.
 */
export function WeeklySevaAnswerCard() {
  const rows = useMyWeeklySevaToAnswer();
  const answer = useAnswerMyWeeklySeva();
  const pending = rows.data ?? [];

  if (!pending.length) return null;

  const failure = errorMessage(answer.error, "That answer could not be saved.");

  return (
    <View className="mb-3 rounded-card border border-marigold bg-marigoldSoft p-card">
      <View className="flex-row items-center">
        <View className="h-10 w-10 items-center justify-center rounded-pill bg-white">
          <Ionicons
            name="help-circle-outline"
            size={22}
            color={tokens.colors.marigold}
          />
        </View>
        <View className="ml-3 min-w-0 flex-1">
          <Text className="font-sans-bold text-base leading-6 text-stone">
            {pending.length > 1
              ? `Did you serve these ${pending.length} seva?`
              : "Did you serve this seva?"}
          </Text>
          <Text className="mt-0.5 font-sans text-sm leading-5 text-stone">
            Only you can say. Leaving it is fine — your hours stay either way.
          </Text>
        </View>
      </View>

      {pending.map((row: WeeklySevaToAnswer) => {
        const busy =
          answer.isPending && answer.variables?.assignmentId === row.assignment_id;
        return (
          <View
            key={row.assignment_id}
            className="mt-4 border-t border-marigold/40 pt-4"
          >
            <Text
              className="font-sans-bold text-base leading-6 text-stone"
              numberOfLines={2}
            >
              {row.seva_name}
            </Text>
            <Text className="mt-0.5 font-sans text-sm text-stone">
              {formatServiceDate(row.occurred_on)} ·{" "}
              {formatServiceTime(row.started_at_local)}
            </Text>

            <View className="mt-3 flex-row gap-3">
              <View className="flex-1">
                <Pressable
                  className="min-h-touch flex-row items-center justify-center rounded-button bg-peacock px-3"
                  accessibilityRole="button"
                  accessibilityLabel={`I served ${row.seva_name}`}
                  disabled={busy}
                  onPress={() =>
                    answer.mutate({
                      assignmentId: row.assignment_id,
                      served: true,
                    })
                  }
                >
                  <Ionicons
                    name="checkmark"
                    size={18}
                    color={tokens.colors.white}
                  />
                  <Text className="ml-2 font-sans-bold text-sm text-white">
                    I served it
                  </Text>
                </Pressable>
              </View>
              <View className="flex-1">
                <Pressable
                  className="min-h-touch flex-row items-center justify-center rounded-button border border-stone bg-white px-3"
                  accessibilityRole="button"
                  accessibilityLabel={`I missed ${row.seva_name}`}
                  accessibilityHint="This gives up the hours for that day and lets the coordinator know"
                  disabled={busy}
                  onPress={() =>
                    answer.mutate({
                      assignmentId: row.assignment_id,
                      served: false,
                    })
                  }
                >
                  <Ionicons name="close" size={18} color={tokens.colors.stone} />
                  <Text className="ml-2 font-sans-bold text-sm text-stone">
                    I missed it
                  </Text>
                </Pressable>
              </View>
            </View>
          </View>
        );
      })}

      {failure ? <FormError message={failure} /> : null}
    </View>
  );
}

/**
 * What devotees said about their own weekly seva, for whoever set the rota up
 * plus the Tech Admin and the President.
 *
 * A missed day is the point: it is the thing somebody has to know about, and
 * before this nobody did. Days that were served are shown too, quietly, so the
 * list does not read as a register of failures.
 */
export function WeeklySevaAnswersCard() {
  const rows = useWeeklySevaAnswers();
  const answers = rows.data ?? [];

  if (!answers.length) return null;

  const missed = answers.filter((row: WeeklySevaAnswer) => row.answer !== "served");

  return (
    <View className="mb-3 rounded-card border border-border bg-white p-card">
      <Text className="font-sans-bold text-base leading-6 text-stone">
        {missed.length
          ? missed.length > 1
            ? `${missed.length} weekly days went uncovered`
            : "A weekly day went uncovered"
          : "Weekly seva, answered"}
      </Text>
      <Text className="mt-0.5 font-sans text-sm leading-5 text-stoneMuted">
        What devotees said about their own rota. Only you and the other temple
        admins see this.
      </Text>

      {answers.slice(0, 8).map((row: WeeklySevaAnswer) => {
        const served = row.answer === "served";
        return (
          <View
            key={row.assignment_id}
            className="mt-3 flex-row items-center border-t border-border pt-3"
          >
            <Avatar
              name={row.devotee_name?.trim() || "A devotee"}
              photoUrl={row.devotee_photo_url}
              size="small"
              tone={served ? "peacock" : "marigold"}
            />
            <View className="ml-3 min-w-0 flex-1">
              <Text
                className="font-sans-bold text-sm text-stone"
                numberOfLines={1}
              >
                {row.devotee_name?.trim() || "A devotee"}
              </Text>
              <Text className="mt-0.5 font-sans text-xs text-stoneMuted" numberOfLines={1}>
                {row.seva_name} · {formatServiceDate(row.occurred_on)}
              </Text>
            </View>
            <View
              className={`ml-2 flex-shrink-0 rounded-pill px-2.5 py-1 ${
                served ? "bg-peacockSoft" : "bg-marigoldSoft"
              }`}
            >
              <Text
                className={`font-sans-bold text-xs ${
                  served ? "text-peacock" : "text-stone"
                }`}
              >
                {served ? "Served" : "Missed"}
              </Text>
            </View>
          </View>
        );
      })}
    </View>
  );
}
