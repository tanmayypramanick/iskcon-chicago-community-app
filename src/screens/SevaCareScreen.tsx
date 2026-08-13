import { Ionicons } from "@expo/vector-icons";
import { useNavigation, type NavigationProp } from "@react-navigation/native";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useMemo, useState } from "react";
import { Pressable, Text, View } from "react-native";

import tokens from "../../design-tokens.json";
import {
  Avatar,
  EmptyOrOffline,
  LoadFailure,
  SectionHeader,
} from "../components/ui";
import { useCurrentAccessProfile } from "../features/access/hooks";
import { hasAccessPermission } from "../features/access/model";
import { openConversation } from "../features/messaging/api";
import { FormError } from "../features/services/components";
import { errorMessage, isConnectionProblem } from "../features/services/format";
import { Disclosure, SeeAll } from "../features/sevayatra/components";
import {
  sevaYatraKeys,
  useDismissSevaCare,
  useSevaBalanceThresholds,
  useSevaConcentration,
  useSevaNarrowness,
} from "../features/sevayatra/hooks";
import {
  careRowHours,
  formatHours,
  formatSevaRange,
  sevaCountLabel,
  type SevaBalanceThresholds,
  type SevaConcentrationRow,
  type SevaNarrownessRow,
} from "../features/sevayatra/types";
import { reportReachability, useServerReachable } from "../lib/connectivity";
import { getSupabaseClient } from "../lib/supabase";
import type { HomeStackParamList, MainTabParamList } from "../navigation/types";
import { usePrototypeSession } from "../store/usePrototypeSession";

/** How many rows before the list asks to be opened. */
const CARE_ROWS = 4;

/**
 * One row's facts, whichever list it came from.
 *
 * The lead figure is the trailing quarter, which is the window both lists are
 * measured over and the one that cannot mislead. It used to be the calendar
 * week, and a devotee who served six hours this month and none this week led
 * with "0 hours" on a list about carrying too much — honest, and read by every
 * President as a fault of the devotee's.
 *
 * `week` and `month` are Chicago's own, and null on a row whose list does not
 * publish them rather than divided out of the quarter. See `careRowHours`.
 *
 * `dismissible` belongs to the row, because only one of the two lists can be
 * cleared at all. See `narrownessEntries`.
 */
export type CareEntry = {
  key: string;
  devoteeId: string;
  name: string;
  serviceTypeId: string | null;
  seva: string;
  quarter: number;
  week: number | null;
  month: number | null;
  dismissible: boolean;
};

/**
 * The concentration list, in the shape a row draws. Post-0066 it is the one
 * list carrying a real week and a real month.
 */
export function concentrationEntries(
  rows: readonly SevaConcentrationRow[],
): CareEntry[] {
  return rows.map((row) => ({
    ...careRowHours(row),
    key: `${row.devotee_id}-${row.service_type_id ?? row.seva_name}`,
    devoteeId: row.devotee_id,
    name: row.devotee_name,
    serviceTypeId: row.service_type_id,
    seva: row.seva_name,
    dismissible: true,
  }));
}

/**
 * The narrowness list, which carries a quarter and nothing finer — and which
 * cannot be cleared.
 *
 * `seva_care_dismissals` is keyed on a devotee and a service type, and a
 * narrowness row is about a whole category rather than one seva, so it has no
 * service type to scope a dismissal to. The only dismissal it could send is the
 * one with no service type at all, and that is the server's own wording for
 * "the whole devotee": `list_seva_concentration` drops every row for a devotee
 * carrying such a dismissal, for ninety days.
 *
 * `list_seva_narrowness` reads `seva_care_dismissals` nowhere, so that write
 * did not take the narrowness row away either. Tapping the cross on a row whose
 * own text says "Not a problem in itself" therefore left it exactly where it
 * was and quietly took the devotee off the burnout list instead — including the
 * most over-concentrated devotee in the temple. There is nothing to clear here
 * until the server can scope a dismissal to a category, so nothing offers to.
 */
export function narrownessEntries(
  rows: readonly SevaNarrownessRow[],
): CareEntry[] {
  return rows.map((row) => ({
    ...careRowHours(row),
    key: `${row.devotee_id}-${row.category}`,
    devoteeId: row.devotee_id,
    serviceTypeId: null,
    name: row.devotee_name,
    seva: row.category,
    dismissible: false,
  }));
}

/**
 * The rota question stands down for the devotee question.
 *
 * Bhakta Ramesh Patel and Madhava Priya Das were on both lists at once, and the
 * temple read the second row as a second problem. Of the two, only "they are
 * carrying one seva far harder than anybody who serves it beside them" has an
 * action on it — a conversation, and a cross that records it — while "they have
 * only ever been asked to one kind of thing" is a note about how the rota was
 * drawn. A devotee already named above is not named again below; the rota
 * reading about them is still true, and it is one tap away on their own record.
 */
export function withoutRepeats(
  narrow: readonly CareEntry[],
  carried: readonly CareEntry[],
): CareEntry[] {
  const named = new Set(carried.map((entry) => entry.devoteeId));
  return narrow.filter((entry) => !named.has(entry.devoteeId));
}

/**
 * What became of a row the President tapped the cross on.
 *
 * Clearing is a write to `seva_care_dismissals` now, not a note this phone keeps
 * to itself, so only a write the server confirmed may take a row away. Anything
 * else puts it straight back: a President who believes a conversation has been
 * recorded, and finds the devotee listed again next week with no idea why, is
 * worse served than one who is told the tap did not land.
 */
export type ClearResult =
  | { kind: "saved" }
  | { kind: "unsupported" }
  | { kind: "failed"; error: unknown };

export function clearOutcome(
  name: string,
  result: ClearResult,
): { stays: boolean; message: string | null } {
  if (result.kind === "saved") return { stays: true, message: null };
  if (result.kind === "unsupported") {
    return {
      stays: false,
      message: `The temple's database cannot record a cleared row yet, so ${name} is still on the list.`,
    };
  }
  return {
    stays: false,
    message:
      errorMessage(
        result.error,
        `${name} could not be cleared, so they are still on the list.`,
      ) ?? null,
  };
}

/**
 * One live row of `list_seva_care_dismissals` — a conversation already had, and
 * how long it holds the devotee off the list.
 */
export type SevaCareDismissal = {
  dismissal_id: string;
  devotee_id: string;
  devotee_name: string;
  service_type_id: string | null;
  seva_name: string | null;
  dismissed_at: string;
  lapses_on: string;
  days_left: number;
  is_live: boolean;
};

const MIGRATION_PENDING = ["PGRST202", "42883", "42P01", "PGRST205"];

/**
 * Read and written here rather than through the Seva Yatra feature because this
 * screen is the only caller of either. Both are `app.view_all`'s, and a temple
 * whose database is behind on 0066 gets an empty list rather than a red failure.
 */
async function fetchSevaCareDismissals(): Promise<SevaCareDismissal[]> {
  const { data, error } = await getSupabaseClient().rpc(
    "list_seva_care_dismissals",
    { p_include_lapsed: false },
  );
  reportReachability(!error || !isConnectionProblem(error));
  if (error) {
    if (MIGRATION_PENDING.includes(error.code ?? "")) return [];
    throw error;
  }
  return (data ?? []) as SevaCareDismissal[];
}

/** How many dismissals were undone. Zero means there was nothing to undo. */
async function restoreSevaCare(
  devoteeId: string,
  serviceTypeId: string | null,
): Promise<number> {
  const { data, error } = await getSupabaseClient().rpc("restore_seva_care", {
    p_devotee_id: devoteeId,
    p_service_type_id: serviceTypeId,
    p_note: null,
  });
  reportReachability(!error || !isConnectionProblem(error));
  if (error) throw error;
  return Number(data ?? 0);
}

const dismissalsKey = ["seva-care", "dismissals"] as const;

/**
 * What the empty list says, which is the state the temple will see most often.
 *
 * 0066 added a third gate — a devotee has to be serving several times the
 * normal for THAT seva among the people who also serve it — so an empty Seva
 * Care is the ordinary reading of a temple whose work is spread about. It has
 * to read as that rather than as a screen which failed to load, and it must not
 * congratulate anybody when the truth is that there was not enough to measure.
 */
export function careEmptyState(input: {
  gathering: boolean;
  handled: number;
}): { title: string; body: string; hint: string | null } {
  if (input.gathering) {
    return {
      title: "Not enough to compare yet",
      body: "Too few devotees have served this quarter for the congregation's own spread to mean anything, so this list is not drawn at all.",
      hint: "It will start to fill in on its own as more seva is recorded.",
    };
  }
  if (input.handled) {
    return {
      title: "All handled",
      body: `${sevaCountLabel(input.handled, "devotee")} cleared, and nobody else stands out. A cleared devotee is not named again until the hours behind it have left the quarter.`,
      hint: null,
    };
  }
  return {
    title: "Nobody stands out",
    body: "No devotee is carrying much more of a seva than the others who serve it. This list is empty most weeks, and an empty one is the temple in good order.",
    hint: "A name appears here only when somebody has been giving one seva several times the hours the devotees beside them give it, week after week.",
  };
}

/**
 * A devotee worth a word: who, what they are carrying, and how much of it.
 *
 * There is no explanation on the row. The server writes a good sentence about
 * why each devotee is listed, and it used to sit here — but a screenful of
 * paragraphs is a case file, and the temple said three times that it was too
 * much to read. The reasoning is a tap away under "How this is worked out"; the
 * list itself is a devotee, a seva, one figure and two things to do about it.
 */
function CareRow({
  entry,
  opening,
  clearing,
  onMessage,
  onHistory,
  onClear,
}: {
  entry: CareEntry;
  opening: boolean;
  /** The write is in flight; the cross must not be tapped a second time. */
  clearing: boolean;
  onMessage: () => void;
  onHistory: () => void;
  /** Absent on a row there is no honest dismissal for. Then there is no cross. */
  onClear?: () => void;
}) {
  // Said only where the server actually sends a week and a month. The rest of
  // the time the quarter above is the whole of what is known.
  const recent =
    entry.week === null || entry.month === null
      ? null
      : `${formatHours(entry.week)} this week · ${formatHours(
          entry.month,
        )} this month`;

  return (
    <View className="mb-2.5 rounded-card border border-border bg-white px-card py-3.5">
      <View className="flex-row items-center">
        <Avatar name={entry.name} size="small" tone="peacock" />
        <View className="ml-3 min-w-0 flex-1">
          <Text
            className="font-sans-bold text-base text-stone"
            numberOfLines={1}
          >
            {entry.name}
          </Text>
          <Text
            className="mt-0.5 font-sans text-xs text-stoneMuted"
            numberOfLines={1}
          >
            {entry.seva}
          </Text>
        </View>
        {/* Handled. Sits apart from the two actions on purpose: it is the one
            control here that changes the list rather than opening something. */}
        {onClear ? (
          <Pressable
            className="-mr-2 ml-2 h-11 w-11 flex-shrink-0 items-center justify-center rounded-pill"
            accessibilityRole="button"
            accessibilityState={{ disabled: clearing }}
            accessibilityLabel={`Clear ${entry.name} from Seva Care`}
            disabled={clearing}
            onPress={onClear}
          >
            <Ionicons
              name={clearing ? "ellipsis-horizontal" : "close"}
              size={20}
              color={tokens.colors.stoneMuted}
            />
          </Pressable>
        ) : null}
      </View>

      <View className="mt-3">
        <Text className="font-sans-bold text-lg text-stone" numberOfLines={1}>
          {formatHours(entry.quarter)}
        </Text>
        <Text className="mt-0.5 font-sans text-xs text-stoneMuted">
          Over the last 13 weeks{recent ? ` · ${recent}` : ""}
        </Text>
      </View>

      <View className="mt-3 flex-row gap-2">
        <Pressable
          className="min-h-touch min-w-0 flex-1 flex-row items-center justify-center rounded-button bg-indigoSoft px-2"
          accessibilityRole="button"
          accessibilityState={{ disabled: opening }}
          accessibilityLabel={`Message ${entry.name}`}
          disabled={opening}
          onPress={onMessage}
        >
          <Ionicons
            name="chatbubble-ellipses-outline"
            size={16}
            color={tokens.colors.indigo}
          />
          <Text
            className="ml-2 font-sans-bold text-sm text-indigo"
            numberOfLines={1}
          >
            {opening ? "Opening…" : "Message"}
          </Text>
        </Pressable>
        <Pressable
          className="min-h-touch min-w-0 flex-1 flex-row items-center justify-center rounded-button border border-border bg-white px-2"
          accessibilityRole="button"
          accessibilityLabel={`See ${entry.name}'s seva history`}
          onPress={onHistory}
        >
          <Ionicons name="time-outline" size={16} color={tokens.colors.stone} />
          <Text
            className="ml-2 font-sans-bold text-sm text-stone"
            numberOfLines={1}
          >
            {/* The temple named this button. */}
            Their seva history
          </Text>
        </Pressable>
      </View>
    </View>
  );
}

/**
 * The empty list, which is what this screen mostly is.
 *
 * Drawn as a finished state rather than as an absence — an icon, a heading and
 * a sentence — because a President opening Seva Care to a blank card would
 * reasonably conclude the screen was broken, and would go looking for the
 * devotees it is not naming.
 */
function CareEmpty({
  title,
  body,
  hint,
}: {
  title: string;
  body: string;
  hint: string | null;
}) {
  return (
    <View className="items-center rounded-card border border-border bg-white px-card py-9">
      <View className="h-14 w-14 items-center justify-center rounded-pill bg-peacockSoft">
        <Ionicons
          name="checkmark-done-outline"
          size={26}
          color={tokens.colors.peacock}
        />
      </View>
      <Text className="mt-4 text-center font-display text-xl text-stone">
        {title}
      </Text>
      <Text className="mt-2 max-w-80 text-center font-sans text-sm leading-6 text-stoneMuted">
        {body}
      </Text>
      {hint ? (
        <Text className="mt-2.5 max-w-80 text-center font-sans text-xs leading-5 text-stoneMuted">
          {hint}
        </Text>
      ) : null}
    </View>
  );
}

/**
 * Who has been cleared, and a way back.
 *
 * Folded away because it is a record rather than a task, and only drawn when
 * there is something in it. Every row here is a devotee the President chose not
 * to be shown, so it is never the first thing on the screen.
 */
function ClearedEarlier({
  rows,
  onPutBack,
}: {
  rows: readonly SevaCareDismissal[];
  onPutBack: (row: SevaCareDismissal) => void;
}) {
  return (
    <View className="mt-section">
      <Disclosure label={`Cleared (${rows.length})`}>
        <View className="mt-1 rounded-card border border-border bg-white px-card py-1.5">
          {rows.map((row, index) => (
            <View
              key={row.dismissal_id}
              className={`flex-row items-center py-2 ${
                index ? "border-t border-border" : ""
              }`}
            >
              <View className="min-w-0 flex-1 pr-3">
                <Text
                  className="font-sans-bold text-sm text-stone"
                  numberOfLines={1}
                >
                  {row.devotee_name}
                </Text>
                <Text
                  className="mt-0.5 font-sans text-xs text-stoneMuted"
                  numberOfLines={1}
                >
                  {/* A dismissal with no seva named is the whole devotee, and
                      saying which it was matters: one is "we spoke about the
                      pot washing", the other is "leave them be". */}
                  {row.seva_name ?? "Every seva"} ·{" "}
                  {row.days_left > 0
                    ? `back in ${sevaCountLabel(row.days_left, "day")}`
                    : "back tomorrow"}
                </Text>
              </View>
              <Pressable
                className="min-h-touch flex-shrink-0 justify-center px-1"
                accessibilityRole="button"
                accessibilityLabel={`Put ${row.devotee_name} back on the list`}
                onPress={() => onPutBack(row)}
              >
                <Text className="font-sans-bold text-sm text-indigo">
                  Put back
                </Text>
              </Pressable>
            </View>
          ))}
        </View>
      </Disclosure>
    </View>
  );
}

/**
 * The arithmetic, folded away.
 *
 * It is not on the main view because a list of devotees to go and talk to
 * should read as a list of devotees, not as a measurement. It is still here,
 * in full, because a President who thinks the list is wrong is usually right
 * about the thresholds and has to be able to see them to say so.
 */
function HowThisIsWorkedOut({
  references,
}: {
  references: SevaBalanceThresholds;
}) {
  return (
    <View className="mt-section">
      <Disclosure label="How this is worked out">
        <View className="mt-1 rounded-card border border-border bg-white px-card py-3.5">
          <Text className="font-sans text-sm leading-6 text-stone">
            {formatSevaRange(
              references.window_starts_on,
              references.window_ends_on,
            )}
            {" · "}
            {sevaCountLabel(references.devotees_considered, "devotee")} serving
          </Text>
          {references.gathering ? (
            <Text className="mt-1.5 font-sans text-xs leading-4 text-stoneMuted">
              Too few devotees have served this quarter for the congregation's
              own spread to mean anything, so neither list is drawn.
            </Text>
          ) : (
            /* The congregation-wide hours bar is deliberately not named here
               any more. 0067 section 2 stopped it gating this list — it had
               been doing all the work at 3 hours a week, and it was keeping out
               the sole server of a seva and the devotee on ten straight weeks,
               who are the two the President most needs. It still travels on the
               row as `min_hours_used`, as the denominator the comparisons are
               expressed against, so `weekly_hours_threshold` is a real number
               that is no longer a floor. Printing it as one had this card
               contradicting the list directly above it: three of the five
               devotees now named serve under it. */
            <Text className="mt-1.5 font-sans text-xs leading-4 text-stoneMuted">
              The middle devotee serves{" "}
              {formatHours(references.median_weekly_hours)} a week. A devotee is
              only mentioned here after{" "}
              {sevaCountLabel(
                references.consecutive_weeks_threshold ?? 0,
                "week",
              )}{" "}
              running on one seva, and only when they are giving it several
              times the hours the other devotees who serve that same seva give
              it. Which is why this list is usually short, and often empty.
            </Text>
          )}
          <Text className="mt-2.5 font-sans text-xs leading-4 text-stoneMuted">
            Nobody here has done anything wrong, and none of this is shown to
            the devotee it is about.
          </Text>
        </View>
      </Disclosure>
    </View>
  );
}

/**
 * Seva Care — the President's and the Tech Admin's list of devotees worth a
 * word, and a way to have that word from the row itself.
 *
 * The body is separate from the screen because Seva Yatra shows it as one of
 * its three sections rather than as a link off the foot of the leaderboard,
 * which the temple found strange. Rendering the same component in both places
 * is what keeps the section and the route from drifting apart.
 *
 * Nothing here ever reaches the devotee it is about: what they see comes from
 * `my_seva_balance`, built from a different set of columns on purpose, so
 * nothing on their own screen moves when they appear on this one.
 */
export function SevaCarePanel() {
  const navigation = useNavigation<NavigationProp<HomeStackParamList>>();
  const activeUserId = usePrototypeSession((state) => state.activeUserId);
  const previewRole = usePrototypeSession((state) => state.previewRole);
  const profile = useCurrentAccessProfile(activeUserId);
  const role =
    __DEV__ && previewRole ? previewRole : (profile.data?.role ?? "devotee");
  const mayViewAll = hasAccessPermission(role, "app.view_all");
  const reachable = useServerReachable();

  // Which row's "Message" is mid-flight, so only that row says "Opening…".
  const [openingFor, setOpeningFor] = useState<string | null>(null);
  const [chatError, setChatError] = useState<string | null>(null);
  const [showAllCare, setShowAllCare] = useState(false);
  const [showAllNarrow, setShowAllNarrow] = useState(false);
  /**
   * Rows the server has confirmed cleared, and rows whose write is still in
   * flight. Both are hidden, and they are kept apart because only the first is
   * something that happened: an in-flight row comes back if the write fails.
   *
   * The confirmed set is still needed once the write lands, because the two
   * lists are refetched rather than edited and there is a moment between the
   * answer and the new list in which the row would otherwise flicker back.
   */
  const [cleared, setCleared] = useState<string[]>([]);
  const [clearing, setClearing] = useState<string[]>([]);

  const queryClient = useQueryClient();
  const thresholds = useSevaBalanceThresholds(mayViewAll);
  const concentration = useSevaConcentration(mayViewAll);
  const narrowness = useSevaNarrowness(mayViewAll);
  const dismiss = useDismissSevaCare();

  /**
   * The conversations already had. A cleared row is a real write now and holds
   * for a quarter, so the President needs somewhere to see what they have
   * cleared and to put back a cross they hit by mistake — otherwise one stray
   * tap hides a devotee until the evidence expires, and nothing in the app ever
   * says so. 0066's own words: nothing is hidden from the President by a
   * feature whose whole purpose is to hide rows from them.
   */
  const dismissals = useQuery({
    queryKey: dismissalsKey,
    queryFn: fetchSevaCareDismissals,
    enabled: mayViewAll,
  });

  const references = thresholds.data ?? null;
  const careFailed = concentration.isError && concentration.data === undefined;

  /**
   * Both readings, in the shape a row draws, heaviest first over the quarter
   * both are measured across — which is also the figure each row leads with.
   *
   * The week-or-month switch that used to order them is gone. It decided which
   * of two figures was drawn in bold, and neither of them is the lead any more.
   */
  const { carried, narrow } = useMemo(() => {
    const byQuarter = (a: CareEntry, b: CareEntry) => b.quarter - a.quarter;
    const heaviest = concentrationEntries(concentration.data ?? []).sort(
      byQuarter,
    );
    return {
      carried: heaviest,
      narrow: withoutRepeats(
        narrownessEntries(narrowness.data ?? []).sort(byQuarter),
        heaviest,
      ),
    };
  }, [concentration.data, narrowness.data]);

  const hidden = (entry: CareEntry) =>
    cleared.includes(entry.key) || clearing.includes(entry.key);
  const visibleCare = carried.filter((entry) => !hidden(entry));
  const visibleNarrow = narrow.filter((entry) => !hidden(entry));
  const shownCare = showAllCare ? visibleCare : visibleCare.slice(0, CARE_ROWS);
  const shownNarrow = showAllNarrow
    ? visibleNarrow
    : visibleNarrow.slice(0, CARE_ROWS);
  const live = (dismissals.data ?? []).filter((row) => row.is_live);

  // The same path the Devotees tab uses: open_conversation returns the thread,
  // existing or new, and the thread itself lives on that tab — so the message
  // has to be sent from there or the devotee ends up in two message lists.
  const message = async (devoteeId: string, name: string) => {
    setChatError(null);
    setOpeningFor(devoteeId);
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
      setOpeningFor(null);
    }
  };

  const history = (devoteeId: string, name: string) =>
    navigation.navigate("SevaCareDevotee", { devoteeId, name });

  /**
   * Clearing a row is the server's write to make, so the row is only gone once
   * the server says it is. A failure is shown and the row comes back, rather
   * than the screen quietly agreeing with a President that a conversation has
   * been recorded when nothing was written.
   */
  const settle = (entry: CareEntry, result: ClearResult) => {
    const outcome = clearOutcome(entry.name, result);
    setClearing((keys) => keys.filter((key) => key !== entry.key));
    if (outcome.stays) setCleared((keys) => [...keys, entry.key]);
    setChatError(outcome.message);
    if (outcome.stays) {
      void queryClient.invalidateQueries({ queryKey: dismissalsKey });
    }
  };

  const clear = (entry: CareEntry) => {
    if (hidden(entry)) return;
    setChatError(null);
    setClearing((keys) => [...keys, entry.key]);
    dismiss.mutate(
      { devoteeId: entry.devoteeId, serviceTypeId: entry.serviceTypeId },
      {
        // `false` is the api saying the function is not there to call, which is
        // a database behind on 0066 rather than a dismissal that happened.
        onSuccess: (persisted: boolean) =>
          settle(entry, persisted ? { kind: "saved" } : { kind: "unsupported" }),
        onError: (caught: unknown) =>
          settle(entry, { kind: "failed", error: caught }),
      },
    );
  };

  /**
   * Undo a dismissal properly — the server's own `restore_seva_care`, so the
   * devotee is on the list again for everybody rather than on this phone.
   */
  const putBack = async (row: SevaCareDismissal) => {
    setChatError(null);
    try {
      await restoreSevaCare(row.devotee_id, row.service_type_id);
      // Only this devotee's rows are unhidden. Dropping the whole set would
      // flash everybody else's row back until the two lists answered again.
      setCleared((keys) =>
        keys.filter((key) => !key.startsWith(`${row.devotee_id}-`)),
      );
      // Not the narrowness list: it reads no dismissal, so neither clearing
      // one nor putting it back can change a row on it.
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: dismissalsKey }),
        queryClient.invalidateQueries({
          queryKey: sevaYatraKeys.concentration(),
        }),
      ]);
    } catch (caught) {
      setChatError(
        errorMessage(
          caught,
          `${row.devotee_name} could not be put back on the list.`,
        ) ?? null,
      );
    }
  };

  const emptyState = careEmptyState({
    gathering: references?.gathering ?? false,
    handled: cleared.length,
  });

  const rowProps = (entry: CareEntry) => ({
    entry,
    opening: openingFor === entry.devoteeId,
    clearing: clearing.includes(entry.key),
    onMessage: () => void message(entry.devoteeId, entry.name),
    onHistory: () => history(entry.devoteeId, entry.name),
    // No cross where there is no dismissal to write. A narrowness row could
    // only send the whole-devotee one, which suppresses the burnout list.
    ...(entry.dismissible ? { onClear: () => clear(entry) } : {}),
  });

  if (!mayViewAll) {
    return (
      <View className="rounded-card border border-border bg-white px-card py-6">
        <Text className="text-center font-sans text-sm leading-6 text-stoneMuted">
          Only the President and a Tech Admin can open this.
        </Text>
      </View>
    );
  }

  return (
    <>
      {chatError ? <FormError message={chatError} /> : null}

      {/* What was actually written, said as what was actually written. The old
          wording promised only that the row would come back on this phone;
          the temple now records the conversation, and for a whole quarter. */}
      {cleared.length ? (
        <View className="mb-2.5 rounded-card border border-border bg-sandalwood px-card py-3">
          <Text className="font-sans text-sm leading-5 text-stone">
            {sevaCountLabel(cleared.length, "devotee")} cleared and recorded.
          </Text>
          <Text className="mt-0.5 font-sans text-xs leading-4 text-stoneMuted">
            They will not be listed again until the hours behind it have left
            the quarter. Nothing about this reaches them.
          </Text>
        </View>
      ) : null}

      {careFailed ? (
        <LoadFailure
          reachable={reachable}
          message={errorMessage(concentration.error, "")}
          onRetry={() => void concentration.refetch()}
        />
      ) : visibleCare.length ? (
        <>
          {shownCare.map((entry) => (
            <CareRow key={entry.key} {...rowProps(entry)} />
          ))}
          {visibleCare.length > shownCare.length ? (
            <SeeAll
              total={visibleCare.length}
              label="devotees"
              onPress={() => setShowAllCare(true)}
            />
          ) : null}
        </>
      ) : (
        <EmptyOrOffline
          reachable={reachable}
          loading={concentration.isLoading}
          loadingLabel="Reading the quarter…"
          empty={<CareEmpty {...emptyState} />}
        />
      )}

      {/* The narrowness reading is a second, quieter question — about the rota
          rather than about the devotee — so it is only drawn when it has
          something to say, never as a co-equal half of the screen, and never
          about a devotee the list above has already named. It is also the one
          list with nothing to clear, and the subtitle says so rather than
          leaving a missing cross to be puzzled over. */}
      {visibleNarrow.length ? (
        <View className="mt-section">
          <SectionHeader
            title="Only ever asked to one thing"
            subtitle="A question about the rota, not about the devotee. There is nothing here to clear."
          />
          {shownNarrow.map((entry) => (
            <CareRow key={entry.key} {...rowProps(entry)} />
          ))}
          {visibleNarrow.length > shownNarrow.length ? (
            <SeeAll
              total={visibleNarrow.length}
              label="devotees"
              onPress={() => setShowAllNarrow(true)}
            />
          ) : null}
        </View>
      ) : null}

      {live.length ? (
        <ClearedEarlier rows={live} onPutBack={(row) => void putBack(row)} />
      ) : null}

      {references ? <HowThisIsWorkedOut references={references} /> : null}
    </>
  );
}

/*
 * There is no `SevaCareScreen` any more, and no `SevaCare` route.
 *
 * The panel above was registered as a screen of its own as well as being drawn
 * as Seva Yatra's third section, and nothing in the app navigated to it — a
 * second way in that only a stale deep link could ever have taken. Seva Care is
 * the tab, and the tab is the only way to it.
 */
