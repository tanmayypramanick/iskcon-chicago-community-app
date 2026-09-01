import { Ionicons } from "@expo/vector-icons";
import { Pressable, Text, View } from "react-native";

import tokens from "../../../design-tokens.json";
import { Avatar, SectionHeader } from "../../components/ui";
import { FormError } from "./components";
import { errorMessage, formatServiceDate } from "./format";
import {
  useAnswerMyWeeklySeva,
  useDismissMyWeeklySevaAnswer,
  useMyWeeklySevaToAnswer,
  useWeeklySevaAnswers,
} from "./hooks";
import type { WeeklySevaAnswer, WeeklySevaToAnswer } from "./types";

/*
 * Kept out of components.tsx on purpose.
 *
 * That module is presentational: it takes props and draws. These read the
 * server for themselves, so putting them there made every screen that renders
 * any seva component pull in the data layer — and with it the native storage
 * the Supabase client opens, which a screen test has no business needing.
 */

/** How many rows a section shows before it defers to its own screen. */
const PREVIEW = 2;

/**
 * One line: which seva, when, and the three small answers.
 *
 * Deliberately plain. The seva board is already long, and this is a question
 * nobody has to answer — it earns a row, not a card.
 */
function AnswerRow({
  row,
  busy,
  onServed,
  onMissed,
  onDismiss,
}: {
  row: WeeklySevaToAnswer;
  busy: boolean;
  onServed: () => void;
  onMissed: () => void;
  onDismiss: () => void;
}) {
  return (
    <View className="flex-row items-center border-t border-border py-2.5">
      <View className="min-w-0 flex-1 pr-2">
        <Text className="font-sans text-sm leading-5 text-stone" numberOfLines={1}>
          {row.seva_name}
        </Text>
        <Text className="font-sans text-xs text-stoneMuted" numberOfLines={1}>
          {formatServiceDate(row.occurred_on)}
        </Text>
      </View>

      <Pressable
        className="ml-1 h-11 w-11 items-center justify-center rounded-pill bg-peacockSoft"
        accessibilityRole="button"
        accessibilityLabel={`I served ${row.seva_name}`}
        disabled={busy}
        onPress={onServed}
      >
        <Ionicons name="checkmark" size={18} color={tokens.colors.peacock} />
      </Pressable>

      <Pressable
        className="ml-1 h-11 w-11 items-center justify-center rounded-pill bg-sandalwood"
        accessibilityRole="button"
        accessibilityLabel={`I missed ${row.seva_name}`}
        accessibilityHint="Gives up the hours for that day and tells the coordinator"
        disabled={busy}
        onPress={onMissed}
      >
        <Ionicons name="close" size={18} color={tokens.colors.stone} />
      </Pressable>

      <Pressable
        className="ml-1 h-11 w-11 items-center justify-center rounded-pill"
        accessibilityRole="button"
        accessibilityLabel={`Stop asking about ${row.seva_name}`}
        accessibilityHint="Answers nothing; your hours stay as they are"
        disabled={busy}
        onPress={onDismiss}
      >
        <Ionicons
          name="close-circle-outline"
          size={18}
          color={tokens.colors.stoneMuted}
        />
      </Pressable>
    </View>
  );
}

/**
 * "Did you serve?" — a section on the seva board, not a card.
 *
 * Two rows and a way to see the rest, like every other section on that tab.
 * It draws nothing when there is nothing to answer, which is most days.
 */
export function WeeklySevaAnswerSection({ onSeeAll }: { onSeeAll: () => void }) {
  const rows = useMyWeeklySevaToAnswer();
  const answer = useAnswerMyWeeklySeva();
  const dismiss = useDismissMyWeeklySevaAnswer();
  const pending = rows.data ?? [];

  if (!pending.length) return null;

  const failure = errorMessage(answer.error, "That answer could not be saved.");

  return (
    <>
      <SectionHeader
        title={pending.length > 1 ? "Did you serve these?" : "Did you serve this?"}
        subtitle="Only you can say. Leaving it changes nothing."
        action={pending.length > PREVIEW ? "See all" : undefined}
        onAction={pending.length > PREVIEW ? onSeeAll : undefined}
      />
      <View className="mb-section rounded-card border border-border bg-white px-card">
        {pending.slice(0, PREVIEW).map((row) => (
          <AnswerRow
            key={row.assignment_id}
            row={row}
            busy={
              (answer.isPending &&
                answer.variables?.assignmentId === row.assignment_id) ||
              (dismiss.isPending && dismiss.variables === row.assignment_id)
            }
            onServed={() =>
              answer.mutate({ assignmentId: row.assignment_id, served: true })
            }
            onMissed={() =>
              answer.mutate({ assignmentId: row.assignment_id, served: false })
            }
            onDismiss={() => dismiss.mutate(row.assignment_id)}
          />
        ))}
        {failure ? <FormError message={failure} /> : null}
      </View>
    </>
  );
}

/** The same question, all of it, on its own screen. */
export function WeeklySevaAnswerList() {
  const rows = useMyWeeklySevaToAnswer();
  const answer = useAnswerMyWeeklySeva();
  const dismiss = useDismissMyWeeklySevaAnswer();
  const pending = rows.data ?? [];

  if (!pending.length) {
    return (
      <Text className="font-sans text-base leading-6 text-stoneMuted">
        Nothing to answer. Weekly seva counts on its own; this only ever asks
        so you can hand back a day you missed.
      </Text>
    );
  }

  const failure = errorMessage(answer.error, "That answer could not be saved.");

  return (
    <View className="rounded-card border border-border bg-white px-card">
      {pending.map((row) => (
        <AnswerRow
          key={row.assignment_id}
          row={row}
          busy={
            (answer.isPending &&
              answer.variables?.assignmentId === row.assignment_id) ||
            (dismiss.isPending && dismiss.variables === row.assignment_id)
          }
          onServed={() =>
            answer.mutate({ assignmentId: row.assignment_id, served: true })
          }
          onMissed={() =>
            answer.mutate({ assignmentId: row.assignment_id, served: false })
          }
          onDismiss={() => dismiss.mutate(row.assignment_id)}
        />
      ))}
      {failure ? <FormError message={failure} /> : null}
    </View>
  );
}

/** One answered day, for whoever set the rota up. */
function AnsweredRow({ row }: { row: WeeklySevaAnswer }) {
  const served = row.answer === "served";
  return (
    <View className="flex-row items-center border-t border-border py-2.5">
      <Avatar
        name={row.devotee_name?.trim() || "A devotee"}
        photoUrl={row.devotee_photo_url}
        size="small"
        tone={served ? "peacock" : "marigold"}
      />
      <View className="ml-3 min-w-0 flex-1">
        <Text className="font-sans text-sm text-stone" numberOfLines={1}>
          {row.devotee_name?.trim() || "A devotee"}
        </Text>
        <Text className="font-sans text-xs text-stoneMuted" numberOfLines={1}>
          {row.seva_name} · {formatServiceDate(row.occurred_on)}
        </Text>
      </View>
      <Text
        className={`ml-2 flex-shrink-0 font-sans-bold text-xs ${
          served ? "text-peacock" : "text-stone"
        }`}
      >
        {served ? "Served" : "Missed"}
      </Text>
    </View>
  );
}

/**
 * What devotees said about their own weekly seva, for whoever set the rota up
 * plus the Tech Admin and the President.
 *
 * Missed days first: they are the reason this exists. A day that was served is
 * shown too, quietly, so the list does not read as a register of failures.
 */
export function WeeklySevaAnswersSection({
  onSeeAll,
  limit = PREVIEW,
}: {
  onSeeAll?: () => void;
  limit?: number;
}) {
  const rows = useWeeklySevaAnswers();
  const answers = [...(rows.data ?? [])].sort((left, right) => {
    const leftMissed = left.answer !== "served" ? 0 : 1;
    const rightMissed = right.answer !== "served" ? 0 : 1;
    if (leftMissed !== rightMissed) return leftMissed - rightMissed;
    return right.occurred_on.localeCompare(left.occurred_on);
  });

  if (!answers.length) return null;

  const missed = answers.filter((row) => row.answer !== "served").length;

  return (
    <>
      <SectionHeader
        title="Weekly seva, answered"
        subtitle={
          missed
            ? missed > 1
              ? `${missed} days went uncovered`
              : "One day went uncovered"
            : undefined
        }
        action={onSeeAll && answers.length > limit ? "See all" : undefined}
        onAction={onSeeAll && answers.length > limit ? onSeeAll : undefined}
      />
      <View className="mb-section rounded-card border border-border bg-white px-card">
        {answers.slice(0, limit).map((row) => (
          <AnsweredRow key={row.assignment_id} row={row} />
        ))}
      </View>
    </>
  );
}
