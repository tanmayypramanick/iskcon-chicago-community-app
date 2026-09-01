import { Ionicons } from "@expo/vector-icons";
import { Pressable, Text, View } from "react-native";

import tokens from "../../../design-tokens.json";
import { SectionHeader } from "../../components/ui";
import { FormError } from "./components";
import { errorMessage, formatServiceDate } from "./format";
import {
  useAnswerMyWeeklySeva,
  useDismissMyWeeklySevaAnswer,
  useMyWeeklySevaToAnswer,
} from "./hooks";
import type { WeeklySevaToAnswer } from "./types";

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
