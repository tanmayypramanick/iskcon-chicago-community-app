import { Ionicons } from "@expo/vector-icons";
import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import { useLayoutEffect, useMemo, useRef, useState } from "react";
import { Pressable, Text, View, useWindowDimensions } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";

import tokens from "../../design-tokens.json";
import { ActionSheet, type ActionSheetAction } from "../components/ActionSheet";
import {
  Avatar,
  BotanicalBackdrop,
  LoadFailure,
  LoadingState,
} from "../components/ui";
import { useCurrentAccessProfile } from "../features/access/hooks";
import { hasAccessPermission } from "../features/access/model";
import { classifyScheduleError } from "../features/schedule/api";
import {
  MonthDensityGrid,
  RangePager,
  ScheduleLegend,
  TimetableGrid,
  WeekDateHeader,
  longDayLabel,
  monthLabel,
  shortDateLabel,
  type TimetableColumn,
} from "../features/schedule/components";
import {
  useScheduleRealtime,
  useSevaSchedule,
  useTempleProgramme,
  useTimetableHours,
} from "../features/schedule/hooks";
import {
  DEFAULT_DAY_ENDS_AT,
  DEFAULT_DAY_STARTS_AT,
  addDaysKey,
  formatClock,
  gridBounds,
  monthBounds,
  monthGridCells,
  shiftMonth,
  timeFromMinutes,
  weekDayKeys,
  weekStartKey,
  weekdayOfKey,
} from "../features/schedule/layout";
import {
  densityByDay,
  occurrencesOn,
  programmeOn,
} from "../features/schedule/selectors";
import { categoryLabels, categoryTone } from "../features/schedule/types";
import type { SevaScheduleOccurrence } from "../features/schedule/types";
import {
  getChicagoDateKey,
  getChicagoMinutesOfDay,
} from "../lib/chicagoDate";
import { useNow } from "../lib/useNow";
import type { ServicesStackParamList } from "../navigation/types";
import { usePrototypeSession } from "../store/usePrototypeSession";

type Props = NativeStackScreenProps<ServicesStackParamList, "Schedule">;

type RangeKind = "week" | "day" | "month";

const RANGES: Array<{ kind: RangeKind; label: string }> = [
  { kind: "week", label: "Week" },
  { kind: "day", label: "Day" },
  { kind: "month", label: "Month" },
];

/** How tall an hour is drawn. A week has to fit seven columns; a day has one. */
const WEEK_PIXELS_PER_HOUR = 52;
const DAY_PIXELS_PER_HOUR = 78;

const LEGEND = (Object.keys(categoryLabels) as Array<keyof typeof categoryLabels>).map(
  (category) => ({
    label: categoryLabels[category],
    fill: categoryTone[category].fill,
  }),
);

/**
 * The temple's timetable — the whole congregation's, a devotee's own, or one
 * devotee's as a coordinator reads it before asking them for anything.
 *
 * ONE SCREEN FOR ALL THREE, because they are one screen: what changes between
 * them is the single argument `list_seva_schedule` takes, and the server
 * decides who may pass which. A second component would be a second place for
 * the layout maths, the swap handling and the roster rules to drift.
 *
 * WHAT A PHONE CAN ACTUALLY DRAW. The temple asked for a school timetable —
 * seven columns, seventeen and a half hours — and for it to be user friendly,
 * and on a 390-point screen those two pull against each other: seven columns
 * leaves 45 points a day, which is a colour and about six characters. So the
 * week is drawn as the real seven-column grid, because that shape is the answer
 * to "who is serving when", and a day at full width is one tap away on the date
 * header for when the answer has to be read rather than scanned. A month is
 * neither: see MonthDensityGrid.
 */
export function ScheduleScreen({ navigation, route }: Props) {
  const { width } = useWindowDimensions();
  const activeUserId = usePrototypeSession((state) => state.activeUserId);
  const previewRole = usePrototypeSession((state) => state.previewRole);
  const profile = useCurrentAccessProfile(activeUserId);
  const role = __DEV__ && previewRole ? previewRole : (profile.data?.role ?? "devotee");

  const devoteeId = route.params?.devoteeId ?? null;
  const devoteeName = route.params?.name ?? null;
  const scope =
    devoteeId === null ? "temple" : devoteeId === activeUserId ? "mine" : "devotee";

  /**
   * The client's copy of `may_view_whole_seva_board()`: Community Head,
   * President, Tech Admin. Used only to decide what to offer — the server
   * refuses regardless — so that a devotee is never shown a timetable that
   * answers with an error they can do nothing about.
   */
  const maySeeBoard =
    hasAccessPermission(role, "services.manage_recurring") ||
    hasAccessPermission(role, "app.view_all");
  const mayPostSeva = hasAccessPermission(role, "services.post_requirement");
  const mayPostWeekly = hasAccessPermission(role, "services.manage_recurring");
  const permitted = scope === "mine" || maySeeBoard;

  // Ticking, because the "now" line moves on its own and nothing else on this
  // screen re-renders at that moment.
  const now = useNow(60_000);
  const todayKey = getChicagoDateKey(now);

  const [range, setRange] = useState<RangeKind>("week");
  const [anchorKey, setAnchorKey] = useState(todayKey);
  const [slot, setSlot] = useState<{ dateKey: string; minutes: number } | null>(
    null,
  );

  const weekStart = weekStartKey(anchorKey);
  const dayKeys = weekDayKeys(weekStart);
  const month = monthBounds(anchorKey);
  const windowFrom = range === "month" ? month.from : weekStart;
  const windowTo = range === "month" ? month.to : dayKeys[6];

  const schedule = useSevaSchedule(windowFrom, windowTo, devoteeId, permitted);
  const programme = useTempleProgramme(windowFrom, windowTo, permitted);
  const hours = useTimetableHours();
  useScheduleRealtime(permitted);

  const title =
    scope === "temple"
      ? "Community timetable"
      : scope === "mine"
        ? "My timetable"
        : `${devoteeName ?? "Devotee"}’s timetable`;

  useLayoutEffect(() => {
    navigation.setOptions({ title });
  }, [navigation, title]);

  const occurrences = useMemo(() => schedule.data ?? [], [schedule.data]);
  const programmeRows = useMemo(() => programme.data ?? [], [programme.data]);
  // The programme widens the grid exactly as seva does. Mangala Arati is at
  // 4:30 whatever the dials say, and a grid that started after it would draw it
  // above its own first hour line.
  const bounds = useMemo(
    () =>
      gridBounds(
        hours.data ?? {
          day_starts_at: DEFAULT_DAY_STARTS_AT,
          day_ends_at: DEFAULT_DAY_ENDS_AT,
        },
        [...occurrences, ...programmeRows],
      ),
    [hours.data, occurrences, programmeRows],
  );

  const columns: TimetableColumn[] = useMemo(() => {
    const keys = range === "day" ? [anchorKey] : dayKeys;
    return keys.map((dateKey) => ({
      dateKey,
      occurrences: occurrencesOn(occurrences, dateKey),
      programme: programmeOn(programmeRows, dateKey),
    }));
    // dayKeys is derived from anchorKey; listing it would rebuild every render.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [anchorKey, occurrences, programmeRows, range]);

  const openOccurrence = (occurrence: SevaScheduleOccurrence) => {
    // The seva's own detail screen, never a second copy of it. Every occurrence
    // has an instance id, weekly and one-off alike, so one route serves both
    // and editing is reached from there as it always was.
    navigation.navigate("ServiceDetail", {
      serviceId: occurrence.service_instance_id,
    });
  };

  // The sheet has to survive its own subject vanishing: choosing an action
  // clears the slot, and the words have to still be there while it animates
  // out. Nothing is mounted until a square has been tapped once, because an
  // unmounted sheet is the difference between a screen that needs a safe-area
  // provider and one that does not.
  const lastSlot = useRef<{ dateKey: string; minutes: number } | null>(null);
  if (slot) lastSlot.current = slot;
  const sheetSlot = slot ?? lastSlot.current;

  const slotActions: ActionSheetAction[] = sheetSlot
    ? [
        {
          label: "Post a one-off seva",
          icon: "add-circle-outline",
          onPress: () => {
            const picked = sheetSlot;
            setSlot(null);
            navigation.navigate("CreateService", {
              date: picked.dateKey,
              startTime: timeFromMinutes(picked.minutes),
            });
          },
        },
        ...(mayPostWeekly
          ? [
              {
                label: "Create a weekly seva at this time",
                icon: "repeat-outline" as const,
                onPress: () => {
                  const picked = sheetSlot;
                  setSlot(null);
                  navigation.navigate("CreateRecurringService", {
                    startDate: picked.dateKey,
                    startTime: timeFromMinutes(picked.minutes),
                    dayOfWeek: weekdayOfKey(picked.dateKey),
                  });
                },
              },
            ]
          : []),
      ]
    : [];

  const rangeLabel =
    range === "month"
      ? monthLabel(month.from)
      : range === "day"
        ? longDayLabel(anchorKey)
        : `${shortDateLabel(weekStart)} – ${shortDateLabel(dayKeys[6])}`;

  const page = (delta: number) => {
    if (range === "month") setAnchorKey(shiftMonth(anchorKey, delta));
    else if (range === "day") setAnchorKey(addDaysKey(anchorKey, delta));
    else setAnchorKey(addDaysKey(anchorKey, delta * 7));
  };

  const failure = schedule.error ? classifyScheduleError(schedule.error) : null;
  const columnWidth = (width - 32 - 44) / (range === "day" ? 1 : 7);

  const body = () => {
    if (!permitted) {
      return (
        <View className="mt-section rounded-card border border-border bg-white px-card py-9">
          <Ionicons
            name="lock-closed-outline"
            size={24}
            color={tokens.colors.stoneMuted}
          />
          <Text className="mt-3 font-sans-bold text-base text-stone">
            This timetable is not yours to read
          </Text>
          <Text className="mt-2 font-sans text-sm leading-6 text-stoneMuted">
            The whole temple’s week, and any other devotee’s, is for the
            President, the Tech Admin and the Community Heads. Your own is
            always open to you.
          </Text>
        </View>
      );
    }

    if (failure) {
      // "Nobody serves this week" and "you may not see this" must never look
      // the same. The server raises rather than answering with zero rows
      // exactly so this screen can tell them apart, so it says which it is.
      if (failure === "denied") {
        return (
          <View className="mt-section rounded-card border border-border bg-white px-card py-9">
            <Ionicons
              name="lock-closed-outline"
              size={24}
              color={tokens.colors.stoneMuted}
            />
            <Text className="mt-3 font-sans-bold text-base text-stone">
              The temple did not open this timetable to you
            </Text>
            <Text className="mt-2 font-sans text-sm leading-6 text-stoneMuted">
              This is not an empty week — it is a week you may not read. Ask the
              President or a Community Head if you need it.
            </Text>
          </View>
        );
      }
      if (failure === "unavailable") {
        return (
          <View className="mt-section rounded-card border border-border bg-white px-card py-9">
            <Text className="font-sans-bold text-base text-stone">
              The timetable is not on this temple’s server yet
            </Text>
            <Text className="mt-2 font-sans text-sm leading-6 text-stoneMuted">
              Nothing is missing from your seva — the schedule feature simply
              has not been installed. Everything else in the Seva tab still
              works.
            </Text>
          </View>
        );
      }
      return (
        <View className="mt-section">
          <LoadFailure
            reachable={failure !== "offline"}
            message={
              failure === "window"
                ? "That is a longer stretch than the timetable will answer for at once."
                : null
            }
            onRetry={() => void schedule.refetch()}
          />
        </View>
      );
    }

    if (schedule.isLoading) {
      return (
        <View className="mt-section">
          <LoadingState label="Reading the temple’s week…" />
        </View>
      );
    }

    if (range === "month") {
      return (
        <View className="mt-3">
          <MonthDensityGrid
            cells={monthGridCells(anchorKey)}
            density={densityByDay(occurrences)}
            todayKey={todayKey}
            anchorMonth={month.from.slice(0, 7)}
            onSelectDay={(dateKey) => {
              setAnchorKey(dateKey);
              setRange("day");
            }}
          />
        </View>
      );
    }

    const empty = occurrences.length === 0;

    return (
      <>
        <WeekDateHeader
          dayKeys={dayKeys}
          todayKey={todayKey}
          selectedKey={range === "day" ? anchorKey : null}
          onSelectDay={(dateKey) => {
            setAnchorKey(dateKey);
            setRange("day");
          }}
        />
        {empty ? (
          <Text className="mt-2 font-sans text-sm leading-5 text-stoneMuted">
            {scope === "mine"
              ? "You have no seva in this week. The temple’s own programme is still drawn below."
              : "No seva is on the board for this week."}
          </Text>
        ) : null}
        <View className="mt-1 flex-1">
          <TimetableGrid
            columns={columns}
            bounds={bounds}
            pixelsPerHour={
              range === "day" ? DAY_PIXELS_PER_HOUR : WEEK_PIXELS_PER_HOUR
            }
            columnWidth={columnWidth}
            compact={range === "week"}
            nowMinutes={getChicagoMinutesOfDay(now)}
            todayKey={todayKey}
            onSelectOccurrence={openOccurrence}
            // Never a control the server would refuse: a devotee without
            // `services.post_requirement` cannot post at all, and no form in
            // this app accepts a date already past — so a week that has been
            // and gone is read-only rather than offering a square that leads
            // to a rejection.
            onSelectSlot={
              mayPostSeva
                ? (dateKey, minutes) => setSlot({ dateKey, minutes })
                : null
            }
            slotsFrom={todayKey}
          />
        </View>
      </>
    );
  };

  return (
    <SafeAreaView className="flex-1 bg-ivory" edges={[]}>
      <BotanicalBackdrop />
      <View className="flex-1 px-screen pt-2">
        {/* Whose week this is, where it is not the reader's own. A coordinator
            arrives here from a list of names and the grid itself carries none —
            without a face at the top, one devotee's week looks like any
            other's. */}
        {scope === "devotee" ? (
          <View className="mb-2 flex-row items-center">
            <Avatar
              name={devoteeName ?? "Devotee"}
              photoUrl={route.params?.photoUrl}
              size="small"
              tone="peacock"
            />
            <Text className="ml-2 min-w-0 flex-1 font-sans-bold text-sm text-stone">
              {devoteeName ?? "This devotee"}
            </Text>
          </View>
        ) : null}

        <RangePager
          label={rangeLabel}
          showToday={weekStartKey(todayKey) !== weekStart}
          onPrevious={() => page(-1)}
          onNext={() => page(1)}
          onToday={() => setAnchorKey(todayKey)}
        />

        <View className="mt-2 flex-row rounded-pill bg-indigoSoft p-1">
          {RANGES.map((option) => {
            const selected = option.kind === range;
            return (
              <Pressable
                key={option.kind}
                className={`min-h-9 flex-1 items-center justify-center rounded-pill ${
                  selected ? "bg-indigo" : ""
                }`}
                accessibilityRole="tab"
                accessibilityState={{ selected }}
                accessibilityLabel={`${option.label} view`}
                onPress={() => setRange(option.kind)}
              >
                <Text
                  className={`font-sans-bold text-sm ${
                    selected ? "text-white" : "text-indigo"
                  }`}
                >
                  {option.label}
                </Text>
              </Pressable>
            );
          })}
        </View>

        {permitted && !failure ? <ScheduleLegend entries={LEGEND} /> : null}

        {body()}
      </View>

      {sheetSlot ? (
        <ActionSheet
          visible={Boolean(slot)}
          title={`${longDayLabel(sheetSlot.dateKey)} at ${formatClock(sheetSlot.minutes)}`}
          message="The date and time are carried into the form; change anything there before posting."
          actions={slotActions}
          onClose={() => setSlot(null)}
        />
      ) : null}
    </SafeAreaView>
  );
}
