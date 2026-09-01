import { Ionicons } from "@expo/vector-icons";
import { useMemo, useState } from "react";
import { Pressable, Text, TextInput, View } from "react-native";

import tokens from "../../design-tokens.json";
import { Avatar, ListScreen, LoadFailure, ScreenTitle } from "../components/ui";
import { formatServiceDate, formatServiceTime } from "../features/services/format";
import { useWeeklySevaAnswers } from "../features/services/hooks";
import type { WeeklySevaAnswer } from "../features/services/types";

/**
 * Weekly seva updates — what devotees said about the rota days they held.
 *
 * A weekly seva counts on completion alone, so nobody has to say anything. But
 * a devotee can say "I missed that one" and hand the credit back, and this is
 * where whoever set the rota up reads those. It is a record, not an inbox:
 * nothing here is waiting on the reader, so the screen is built to be searched
 * rather than cleared.
 *
 * A season's worth, because a missed Sunday two months ago is exactly the kind
 * of thing somebody comes here looking for.
 */
const WINDOW_DAYS = 90;

type Answer = WeeklySevaAnswer["answer"];

/** Only the kinds that are actually in the data get a chip. */
const answerLabels: Record<Answer, string> = {
  absent: "Missed",
  excused: "Excused",
  served: "Served",
};

/** Missed first: it is the one somebody may still need to act on. */
const answerOrder: Answer[] = ["absent", "excused", "served"];

type Row =
  | { kind: "day"; key: string; label: string; missed: number }
  | { kind: "answer"; key: string; answer: WeeklySevaAnswer };

function matches(answer: WeeklySevaAnswer, needle: string) {
  if (!needle) return true;
  const haystack = `${answer.devotee_name ?? ""} ${answer.seva_name}`;
  return haystack.toLowerCase().includes(needle);
}

function FilterChip({
  label,
  count,
  selected,
  onPress,
}: {
  label: string;
  count: number;
  selected: boolean;
  onPress: () => void;
}) {
  return (
    <Pressable
      className={`min-h-touch flex-row items-center justify-center rounded-pill border px-4 ${
        selected ? "border-indigo bg-indigo" : "border-border bg-white"
      }`}
      accessibilityRole="button"
      accessibilityState={{ selected }}
      accessibilityLabel={`Show ${label.toLowerCase()} — ${count}`}
      onPress={onPress}
    >
      <Text
        className={`font-sans-bold text-sm ${selected ? "text-white" : "text-stone"}`}
      >
        {label}
      </Text>
      <Text
        className={`ml-2 font-sans text-sm ${
          selected ? "text-white/80" : "text-stoneMuted"
        }`}
      >
        {count}
      </Text>
    </Pressable>
  );
}

/** One devotee, one day, and what they said about it. */
function AnswerRow({ answer }: { answer: WeeklySevaAnswer }) {
  const served = answer.answer === "served";
  const name = answer.devotee_name?.trim() || "A devotee";
  return (
    <View className="flex-row items-center border-t border-border py-3">
      <Avatar
        name={name}
        photoUrl={answer.devotee_photo_url}
        size="small"
        tone={served ? "peacock" : "marigold"}
      />
      <View className="ml-3 min-w-0 flex-1">
        <Text className="font-sans-bold text-sm text-stone" numberOfLines={1}>
          {name}
        </Text>
        <Text className="font-sans text-xs text-stoneMuted" numberOfLines={1}>
          {answer.seva_name} · {formatServiceTime(answer.started_at_local)}
        </Text>
      </View>
      <Text
        className={`ml-2 flex-shrink-0 font-sans-bold text-xs ${
          served ? "text-peacock" : "text-vermilion"
        }`}
      >
        {answerLabels[answer.answer]}
      </Text>
    </View>
  );
}

export function WeeklySevaUpdatesScreen() {
  const answers = useWeeklySevaAnswers(true, WINDOW_DAYS);
  const [search, setSearch] = useState("");
  const [filter, setFilter] = useState<Answer | "all">("all");

  const all = useMemo(() => answers.data ?? [], [answers.data]);

  // Which chips to draw. A filter for something nobody has said is a control
  // that can only ever empty the screen, so it is not offered.
  const chips = useMemo(
    () =>
      answerOrder
        .map((answer) => ({
          answer,
          label: answerLabels[answer],
          count: all.filter((row) => row.answer === answer).length,
        }))
        .filter((chip) => chip.count > 0),
    [all],
  );

  const rows = useMemo<Row[]>(() => {
    const needle = search.trim().toLowerCase();
    const kept = all
      .filter((row) => (filter === "all" ? true : row.answer === filter))
      .filter((row) => matches(row, needle))
      // Newest first, and within a day the earliest seva first, so a day reads
      // in the order it was actually served.
      .sort((left, right) => {
        if (left.occurred_on !== right.occurred_on) {
          return right.occurred_on.localeCompare(left.occurred_on);
        }
        if (left.started_at_local !== right.started_at_local) {
          return left.started_at_local.localeCompare(right.started_at_local);
        }
        return (left.devotee_name ?? "").localeCompare(right.devotee_name ?? "");
      });

    const out: Row[] = [];
    let day: string | null = null;
    for (const answer of kept) {
      if (answer.occurred_on !== day) {
        day = answer.occurred_on;
        out.push({
          kind: "day",
          key: `day-${day}`,
          label: formatServiceDate(day),
          missed: kept.filter(
            (row) => row.occurred_on === day && row.answer !== "served",
          ).length,
        });
      }
      out.push({ kind: "answer", key: answer.assignment_id, answer });
    }
    return out;
  }, [all, filter, search]);

  const filtering = filter !== "all" || search.trim().length > 0;
  const shown = rows.filter((row) => row.kind === "answer").length;

  return (
    <ListScreen
      topInset={false}
      data={rows}
      keyExtractor={(row) => row.key}
      header={
        <View>
          <ScreenTitle eyebrow="Weekly seva">Updates</ScreenTitle>

          {all.length ? (
            <>
              <View className="min-h-touch flex-row items-center rounded-button border border-border bg-white px-4">
                <Ionicons name="search" size={19} color={tokens.colors.indigo} />
                <TextInput
                  className="min-w-0 flex-1 px-3 py-3 font-sans text-base text-stone"
                  accessibilityLabel="Search by devotee or seva name"
                  autoCapitalize="none"
                  autoCorrect={false}
                  value={search}
                  onChangeText={setSearch}
                  placeholder="Search by devotee or seva"
                  placeholderTextColor={tokens.colors.stoneMuted}
                  returnKeyType="search"
                />
                {search.length ? (
                  <Pressable
                    className="h-11 w-11 items-center justify-center"
                    accessibilityRole="button"
                    accessibilityLabel="Clear the search"
                    onPress={() => setSearch("")}
                  >
                    <Ionicons
                      name="close-circle"
                      size={19}
                      color={tokens.colors.stoneMuted}
                    />
                  </Pressable>
                ) : null}
              </View>

              {chips.length > 1 ? (
                <View className="mt-3 flex-row flex-wrap gap-2">
                  <FilterChip
                    label="All"
                    count={all.length}
                    selected={filter === "all"}
                    onPress={() => setFilter("all")}
                  />
                  {chips.map((chip) => (
                    <FilterChip
                      key={chip.answer}
                      label={chip.label}
                      count={chip.count}
                      selected={filter === chip.answer}
                      onPress={() => setFilter(chip.answer)}
                    />
                  ))}
                </View>
              ) : null}

              <Text className="mb-2 mt-4 font-sans text-xs text-stoneMuted">
                {filtering
                  ? `${shown} of ${all.length} · newest first`
                  : `${all.length} in the last ${WINDOW_DAYS} days · newest first`}
              </Text>
            </>
          ) : null}
        </View>
      }
      renderItem={(row) =>
        row.kind === "day" ? (
          <View className="mb-1 mt-4 flex-row items-baseline">
            <Text className="font-sans-bold text-xs uppercase tracking-wider text-stoneMuted">
              {row.label}
            </Text>
            {row.missed ? (
              <Text className="ml-2 font-sans text-xs text-vermilion">
                {row.missed > 1
                  ? `${row.missed} went uncovered`
                  : "1 went uncovered"}
              </Text>
            ) : null}
          </View>
        ) : (
          <View className="rounded-card border border-border bg-white px-card">
            <AnswerRow answer={row.answer} />
          </View>
        )
      }
      empty={
        answers.isError ? (
          <LoadFailure
            reachable
            message="Weekly seva updates could not be loaded."
            onRetry={() => void answers.refetch()}
          />
        ) : answers.isLoading ? (
          <Text className="font-sans text-base text-stoneMuted">
            Loading weekly seva updates…
          </Text>
        ) : (
          <View className="items-center rounded-card border border-border bg-white px-card py-9">
            <Ionicons
              name={filtering ? "search-outline" : "checkmark-done-outline"}
              size={31}
              color={tokens.colors.peacock}
            />
            <Text className="mt-3 text-center font-sans-bold text-base text-stone">
              {filtering ? "Nothing matches that" : "Nothing to report"}
            </Text>
            <Text className="mt-1 text-center font-sans text-sm text-stoneMuted">
              {filtering
                ? "Try another name, or clear the filter."
                : "Weekly seva counts on its own. Devotees appear here only when they say they served a day, or missed one."}
            </Text>
          </View>
        )
      }
    />
  );
}
