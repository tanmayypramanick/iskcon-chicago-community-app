import { Ionicons } from "@expo/vector-icons";
import { useMemo, useState } from "react";
import { Text, View } from "react-native";

import tokens from "../../design-tokens.json";
import {
  EmptyOrOffline,
  LoadFailure,
  Screen,
  ScreenTitle,
  SectionHeader,
} from "../components/ui";
import { errorMessage } from "../features/services/format";
import { SeeAll, SevaChipRow } from "../features/sevayatra/components";
import {
  useMySevaActs,
  useMySevaBalance,
  useMySevaBreakdown,
  useMySevaProfile,
} from "../features/sevayatra/hooks";
import {
  formatHours,
  formatSevaDate,
  formatSevaLongDate,
  formatSevaRange,
  isPendingSeva,
  pendingSevaPhrase,
  profileWindowForRange,
  sevaCountLabel,
  sevaRangeChips,
  sevaRangeLabels,
  sevaRanges,
  type MySevaAct,
  type MySevaBalanceRow,
  type MySevaBreakdownRow,
  type SevaPointsStatus,
  type SevaRangeKind,
} from "../features/sevayatra/types";
import { useServerReachable } from "../lib/connectivity";
import { usePrototypeSession } from "../store/usePrototypeSession";

/** How many acts before the list asks to be opened. */
const ACT_ROWS = 8;

const rangeOptions = sevaRanges.map((key) => ({
  key,
  label: sevaRangeChips[key],
}));

/**
 * What one kind of seva is waiting on, said as what it is actually waiting on.
 *
 * "Waiting to be confirmed" was written over all three of the server's pending
 * states, and the temple's complaint about it is the sharpest one on this
 * feature: an act nobody has marked done is waiting on the devotee reading the
 * screen, and telling them somebody else has to confirm it sends them to the
 * office to ask about something they could finish themselves.
 */
function BreakdownRow({
  row,
  waitingOn,
}: {
  row: MySevaBreakdownRow;
  waitingOn: string;
}) {
  return (
    <View className="mb-2 flex-row items-center rounded-card border border-border bg-white px-card py-3">
      <View className="h-2.5 w-2.5 flex-shrink-0 rounded-pill bg-marigold" />
      <View className="ml-3 min-w-0 flex-1">
        <Text className="font-sans-bold text-sm text-stone" numberOfLines={2}>
          {row.seva_name}
        </Text>
        <Text className="mt-0.5 font-sans text-xs text-stoneMuted">
          {sevaCountLabel(row.acts, "act")}
          {row.pending_acts
            ? ` · ${row.pending_acts} still to be ${waitingOn}`
            : ""}
        </Text>
      </View>
      <Text className="ml-3 flex-shrink-0 font-sans-bold text-sm text-stone">
        {formatHours(row.hours)}
      </Text>
    </View>
  );
}

/** The key a breakdown row and an act agree on for the same kind of seva. */
function sevaKey(row: { service_type_id: string | null; seva_name: string }) {
  return `${row.service_type_id ?? "custom"}-${row.seva_name}`;
}

/**
 * One act, with the server's own sentence about it. `points_note` names who has
 * to do what next, so it is shown as written — an act that is waiting must read
 * as waiting rather than as having failed, and inventing wording here is how
 * that distinction gets lost.
 */
function ActRow({ act }: { act: MySevaAct }) {
  const waiting = isPendingSeva(act.points_status);
  const counted = act.points_status === "counted";

  return (
    <View className="mb-2 rounded-card border border-border bg-white px-card py-3">
      <View className="flex-row items-start">
        <View className="min-w-0 flex-1 pr-3">
          <Text className="font-sans-bold text-sm text-stone" numberOfLines={2}>
            {act.seva_name}
          </Text>
          <Text className="mt-0.5 font-sans text-xs text-stoneMuted">
            {formatSevaDate(act.occurred_on)} · {formatHours(act.hours)}
            {act.is_recurring ? " · weekly seva" : ""}
          </Text>
        </View>
        <View
          className={`flex-shrink-0 flex-row items-center rounded-pill px-2 py-1 ${
            counted
              ? "bg-peacockSoft"
              : waiting
                ? "bg-marigoldSoft"
                : "bg-sandalwood"
          }`}
        >
          <Ionicons
            name={
              counted
                ? "checkmark-circle"
                : waiting
                  ? "hourglass-outline"
                  : "remove-circle-outline"
            }
            size={13}
            color={counted ? tokens.colors.peacock : tokens.colors.stone}
          />
          <Text
            className={`ml-1 font-sans-bold text-[10px] uppercase tracking-wide ${
              counted ? "text-peacock" : "text-stone"
            }`}
          >
            {counted ? "Counted" : waiting ? "Waiting" : "Not served"}
          </Text>
        </View>
      </View>
      {act.points_note ? (
        <Text className="mt-2 font-sans text-xs leading-4 text-stoneMuted">
          {act.points_note}
        </Text>
      ) : null}
    </View>
  );
}

function BalanceRow({ row }: { row: MySevaBalanceRow }) {
  return (
    <View className="mb-2 flex-row items-center rounded-card border border-border bg-white px-card py-3">
      <View className="min-w-0 flex-1 pr-3">
        <Text className="font-sans-bold text-sm text-stone" numberOfLines={2}>
          {row.seva_name}
        </Text>
        <Text className="mt-0.5 font-sans text-xs text-stoneMuted">
          Since {formatSevaLongDate(row.first_served_on)}
        </Text>
      </View>
      <Text className="flex-shrink-0 font-sans-bold text-sm text-stone">
        {formatHours(row.hours_all_time)}
      </Text>
    </View>
  );
}

/**
 * Everything the Seva Yatra profile deliberately leaves out.
 *
 * The profile answers "how am I doing" in three seconds; this answers "what
 * exactly did I do", which is a rarer question and a longer read. Splitting
 * them is what let the profile become scannable at all.
 */
export function SevaHistoryScreen() {
  const activeUserId = usePrototypeSession((state) => state.activeUserId);
  const reachable = useServerReachable();

  const [range, setRange] = useState<SevaRangeKind>("week");
  const [showAllActs, setShowAllActs] = useState(false);

  const profile = useMySevaProfile(activeUserId);
  const breakdown = useMySevaBreakdown(activeUserId);
  const balance = useMySevaBalance(activeUserId);

  const balanceRows = useMemo(() => balance.data ?? [], [balance.data]);
  // Null for all time, which `my_seva_profile` has no window for.
  const window = profileWindowForRange(range);
  const windowRow = useMemo(
    () => profile.data?.find((row) => row.window_kind === window) ?? null,
    [profile.data, window],
  );

  /**
   * All time has no window row, so its totals are the per-seva balances added
   * up and its bounds are the devotee's own first seva through the end of the
   * calendar year. Real dates from the server, rather than a ninety-day
   * default quietly labelled "all time".
   */
  const lifetime = useMemo(() => {
    if (window) return null;
    let hours = 0;
    let acts = 0;
    let firstServed: string | null = null;
    for (const row of balanceRows) {
      hours += Number(row.hours_all_time ?? 0);
      acts += Number(row.acts_all_time ?? 0);
      if (!firstServed || row.first_served_on < firstServed) {
        firstServed = row.first_served_on;
      }
    }
    const yearEnd =
      profile.data?.find((row) => row.window_kind === "year")?.window_end ??
      null;
    return { hours, acts, firstServed, yearEnd };
  }, [window, balanceRows, profile.data]);

  const acts = useMySevaActs(
    activeUserId,
    windowRow?.window_start ?? lifetime?.firstServed ?? null,
    windowRow?.window_end ?? lifetime?.yearEnd ?? null,
  );

  const breakdownRows = (breakdown.data ?? []).filter(
    (row) => row.window_kind === window,
  );
  const actRows = useMemo(() => acts.data ?? [], [acts.data]);
  const shownActs = showAllActs ? actRows : actRows.slice(0, ACT_ROWS);
  const profileFailed = profile.isError && profile.data === undefined;

  /**
   * Which of the three waiting states this window actually holds, for the whole
   * window and for each kind of seva in it. The counts come from
   * `my_seva_profile` and `my_seva_breakdown`, which say how many acts are
   * waiting but not what on; the acts for the same window are already on the
   * screen and do say, so the sentence is built from them rather than guessed.
   */
  const waitingOn = useMemo(() => {
    const bySeva = new Map<string, SevaPointsStatus[]>();
    for (const act of actRows) {
      if (!isPendingSeva(act.points_status)) continue;
      const key = sevaKey(act);
      bySeva.set(key, [...(bySeva.get(key) ?? []), act.points_status]);
    }
    return {
      window: pendingSevaPhrase(actRows.map((act) => act.points_status)),
      forSeva: (key: string) => pendingSevaPhrase(bySeva.get(key) ?? []),
    };
  }, [actRows]);

  return (
    <Screen topInset={false}>
      <ScreenTitle eyebrow="Seva Yatra">My seva history</ScreenTitle>

      <View className="mb-4">
        <SevaChipRow
          value={range}
          options={rangeOptions}
          onChange={(next) => {
            setRange(next);
            setShowAllActs(false);
          }}
        />
      </View>

      {profileFailed ? (
        <LoadFailure
          reachable={reachable}
          message={errorMessage(profile.error, "Your seva could not be loaded.")}
          onRetry={() => void profile.refetch()}
        />
      ) : windowRow || lifetime ? (
        <View className="rounded-card border border-border bg-white p-card">
          <Text className="font-sans text-xs text-stoneMuted">
            {windowRow
              ? formatSevaRange(windowRow.window_start, windowRow.window_end)
              : lifetime?.firstServed
                ? `Since ${formatSevaLongDate(lifetime.firstServed)}`
                : "All time"}
          </Text>
          <Text className="mt-2 font-display text-[30px] leading-10 text-stone">
            {formatHours(windowRow ? windowRow.hours : (lifetime?.hours ?? 0))}
          </Text>
          <Text className="mt-0.5 font-sans text-sm text-stoneMuted">
            {sevaCountLabel(
              windowRow ? windowRow.acts : (lifetime?.acts ?? 0),
              "act",
            )}{" "}
            of seva
            {windowRow?.pending_acts
              ? ` · ${windowRow.pending_acts} still to be ${waitingOn.window}`
              : ""}
          </Text>
        </View>
      ) : null}

      {/* One list of seva by kind, for whichever range is on screen: the window
          rows for a week, a month or a year, and the all-time balances for all
          time. There used to be a second list underneath naming the same sevas
          with their all-time totals beside the window's, so a devotee read
          "Pot washing" twice with two different figures and no way to tell
          which range either belonged to. All time is a chip away. */}
      {window ? (
        breakdownRows.length ? (
          <View className="mt-section">
            <SectionHeader
              title="Seva by kind"
              subtitle={sevaRangeLabels[range].toLowerCase()}
            />
            {breakdownRows.map((row) => (
              <BreakdownRow
                key={sevaKey(row)}
                row={row}
                waitingOn={waitingOn.forSeva(sevaKey(row))}
              />
            ))}
          </View>
        ) : null
      ) : balanceRows.length ? (
        <View className="mt-section">
          <SectionHeader
            title="Seva by kind"
            subtitle="Everything you have offered. Thank you for every hour of it."
          />
          {balanceRows.map((row) => (
            <BalanceRow
              key={`${row.service_type_id ?? "custom"}-${row.seva_name}`}
              row={row}
            />
          ))}
        </View>
      ) : null}

      <View className="mt-section">
        <SectionHeader
          title="Act by act"
          subtitle="What counted, and what is still waiting."
        />
        {actRows.length ? (
          <>
            {shownActs.map((act) => (
              <ActRow key={act.assignment_id} act={act} />
            ))}
            {actRows.length > shownActs.length ? (
              <SeeAll
                total={actRows.length}
                label="acts"
                onPress={() => setShowAllActs(true)}
              />
            ) : null}
          </>
        ) : (
          <EmptyOrOffline
            reachable={reachable}
            loading={acts.isLoading}
            loadingLabel="Reading your seva…"
            empty={
              <View className="items-center rounded-card border border-border bg-white px-card py-9">
                <Text className="text-center font-sans text-sm leading-6 text-stoneMuted">
                  Nothing recorded in this window.
                </Text>
              </View>
            }
          />
        )}
      </View>
    </Screen>
  );
}
