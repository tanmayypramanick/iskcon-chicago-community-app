import { Ionicons } from "@expo/vector-icons";
import { Pressable, ScrollView, Text, View } from "react-native";

import tokens from "../../../design-tokens.json";
import {
  blockGeometry,
  formatClock,
  hourLines,
  gridHeight,
  layOutDay,
  minutesFromTime,
  offsetForMinutes,
  slotMinutesFromOffset,
  slotSegments,
  weekdayOfKey,
  type GridBounds,
} from "./layout";
import {
  occurrenceAccessibilityLabel,
  programmeAccessibilityLabel,
  programmeTimeLabel,
  type DayDensity,
} from "./selectors";
import {
  toneForCategory,
  type SevaScheduleOccurrence,
  type TempleProgrammeOccurrence,
} from "./types";

/** Wide enough for "12:30 PM" at the size the grid labels hours. */
export const TIME_GUTTER_WIDTH = 44;

const WEEKDAY_INITIALS = ["S", "M", "T", "W", "T", "F", "S"];
const WEEKDAY_SHORT = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
const MONTH_SHORT = [
  "Jan",
  "Feb",
  "Mar",
  "Apr",
  "May",
  "Jun",
  "Jul",
  "Aug",
  "Sep",
  "Oct",
  "Nov",
  "Dec",
];

export function dayNumber(dateKey: string) {
  return Number(dateKey.slice(8, 10));
}

export function shortDateLabel(dateKey: string) {
  const month = MONTH_SHORT[Number(dateKey.slice(5, 7)) - 1] ?? "";
  return `${month} ${dayNumber(dateKey)}`;
}

export function longDayLabel(dateKey: string) {
  return `${WEEKDAY_SHORT[weekdayOfKey(dateKey)]}, ${shortDateLabel(dateKey)}`;
}

export function monthLabel(dateKey: string) {
  const month = MONTH_SHORT[Number(dateKey.slice(5, 7)) - 1] ?? "";
  return `${month} ${dateKey.slice(0, 4)}`;
}

/**
 * The dates across the top — the part of a school timetable the temple named
 * first, and the part that has to stay put while the hours scroll under it.
 *
 * It doubles as the day picker, because on a phone the week grid is the shape
 * of the week and one day at full width is where it is actually read.
 */
export function WeekDateHeader({
  dayKeys,
  todayKey,
  selectedKey,
  onSelectDay,
}: {
  dayKeys: readonly string[];
  todayKey: string;
  /** Null in week mode: no single day is being read. */
  selectedKey: string | null;
  onSelectDay: (dateKey: string) => void;
}) {
  return (
    <View className="flex-row" accessibilityRole="tablist">
      <View style={{ width: TIME_GUTTER_WIDTH }} />
      {dayKeys.map((dateKey) => {
        const isToday = dateKey === todayKey;
        const isSelected = dateKey === selectedKey;
        return (
          <Pressable
            key={dateKey}
            className={`min-h-11 flex-1 items-center justify-center rounded-button py-1 ${
              isSelected ? "bg-indigo" : ""
            }`}
            accessibilityRole="tab"
            accessibilityState={{ selected: isSelected }}
            accessibilityLabel={`${longDayLabel(dateKey)}${isToday ? ", today" : ""}`}
            accessibilityHint="Shows this day on its own"
            onPress={() => onSelectDay(dateKey)}
          >
            <Text
              className={`font-sans text-[10px] uppercase tracking-wider ${
                isSelected ? "text-white" : "text-stoneMuted"
              }`}
            >
              {WEEKDAY_INITIALS[weekdayOfKey(dateKey)]}
            </Text>
            <View
              className={`mt-0.5 h-6 w-6 items-center justify-center rounded-pill ${
                isToday && !isSelected ? "border border-vermilion" : ""
              }`}
            >
              <Text
                className={`font-sans-bold text-sm ${
                  isSelected
                    ? "text-white"
                    : isToday
                      ? "text-vermilion"
                      : "text-stone"
                }`}
              >
                {dayNumber(dateKey)}
              </Text>
            </View>
          </Pressable>
        );
      })}
    </View>
  );
}

export type TimetableColumn = {
  dateKey: string;
  occurrences: readonly SevaScheduleOccurrence[];
  programme: readonly TempleProgrammeOccurrence[];
};

/**
 * One seva, drawn.
 *
 * The face carries the kind of seva and its name and nothing else — the
 * temple's own rule for what a block may say. Everything else about it travels
 * in the accessibility label, so a screen reader user is not left with a button
 * called "Kitchen".
 */
function SevaBlock({
  occurrence,
  top,
  height,
  left,
  width,
  compact,
  onPress,
}: {
  occurrence: SevaScheduleOccurrence;
  top: number;
  height: number;
  left: number;
  width: number;
  compact: boolean;
  onPress: () => void;
}) {
  const tone = toneForCategory(occurrence.service_category);
  const cancelled = occurrence.status === "cancelled";
  // A place still open is the one thing a coordinator scans a week for, so it
  // earns a mark on the face even though it is not a word.
  const needsPeople = occurrence.open_slots > 0 && !cancelled;

  return (
    <Pressable
      className={`absolute overflow-hidden rounded-[10px] border px-1 py-0.5 ${tone.fill} ${
        cancelled ? "border-border opacity-60" : tone.border
      }`}
      style={{ top, height, left, width }}
      // Small blocks are still real buttons; the slop reaches past the drawn
      // edge without moving it.
      hitSlop={{ top: 2, bottom: 2 }}
      accessibilityRole="button"
      accessibilityLabel={occurrenceAccessibilityLabel(occurrence)}
      accessibilityHint="Opens the full details"
      onPress={onPress}
    >
      {needsPeople ? (
        <View className="absolute right-1 top-1 h-1.5 w-1.5 rounded-pill bg-vermilion" />
      ) : null}
      <Text
        className={`font-sans-bold ${compact ? "text-[9px] leading-[11px]" : "text-xs leading-4"} ${tone.text} ${
          cancelled ? "line-through" : ""
        }`}
        numberOfLines={compact ? 3 : 2}
      >
        {occurrence.seva_name}
      </Text>
      {!compact ? (
        <Text className="mt-0.5 font-sans text-[11px] leading-4 text-stoneMuted">
          {formatClock(minutesFromTime(occurrence.starts_at_local))}
          {occurrence.from_weekly_template ? " · weekly" : ""}
        </Text>
      ) : null}
    </Pressable>
  );
}

/**
 * The temple's fixed daily rhythm, behind the seva.
 *
 * Never a seva block: nobody is assigned to it, nothing can clash with it, and
 * it is not tappable in the sense the seva blocks are. The three aratis the
 * temple gave a start and no end are drawn as moments — a line and a name —
 * because a block height for them would be invented.
 */
function ProgrammeLayer({
  entries,
  bounds,
  pixelsPerHour,
  width,
  showLabels,
}: {
  entries: readonly TempleProgrammeOccurrence[];
  bounds: GridBounds;
  pixelsPerHour: number;
  width: number;
  showLabels: boolean;
}) {
  return (
    // Never in the tap path, at any size: the whole layer is behind the seva
    // and cannot be pressed, which is what "read only" means here.
    <View className="absolute inset-0" pointerEvents="none">
      {entries.map((entry) => {
        const from = minutesFromTime(entry.starts_at_local);
        const top = offsetForMinutes(from, bounds, pixelsPerHour);
        // Named to a screen reader only where it is named on screen. In the
        // week grid there are seven columns of these and reading ten temple
        // events per day aloud would bury the seva; the day view carries them.
        const reader = showLabels
          ? {
              accessible: true,
              accessibilityRole: "text" as const,
              accessibilityLabel: programmeAccessibilityLabel(entry),
            }
          : {
              accessibilityElementsHidden: true,
              importantForAccessibility: "no-hide-descendants" as const,
            };
        if (entry.duration_minutes === null) {
          // A start with no end. Drawn as a moment — a dot and a hairline —
          // because giving it a block height would invent the end the temple
          // deliberately did not name.
          return (
            <View
              key={`${entry.programme_id}-${entry.occurs_on}`}
              className="absolute flex-row items-center"
              style={{ top: top - 4, left: 0, width }}
              {...reader}
            >
              <View className="h-1.5 w-1.5 rounded-pill bg-marigold" />
              <View className="h-px flex-1 bg-marigold/40" />
              {showLabels ? (
                <Text className="ml-1 font-sans text-[10px] text-marigold">
                  {entry.name}
                </Text>
              ) : null}
            </View>
          );
        }
        const height = (entry.duration_minutes / 60) * pixelsPerHour;
        return (
          <View
            key={`${entry.programme_id}-${entry.occurs_on}`}
            className="absolute border-l-2 border-marigold/30 bg-marigoldSoft/25"
            style={{ top, height, left: 0, width }}
            {...reader}
          >
            {showLabels ? (
              <Text
                className="ml-1 mt-0.5 font-sans text-[10px] text-stoneMuted"
                numberOfLines={1}
              >
                {entry.name}
              </Text>
            ) : null}
          </View>
        );
      })}
    </View>
  );
}

function DayColumn({
  column,
  bounds,
  pixelsPerHour,
  width,
  compact,
  showProgrammeLabels,
  onSelectOccurrence,
  onSelectSlot,
}: {
  column: TimetableColumn;
  bounds: GridBounds;
  pixelsPerHour: number;
  width: number;
  compact: boolean;
  showProgrammeLabels: boolean;
  onSelectOccurrence: (occurrence: SevaScheduleOccurrence) => void;
  onSelectSlot: ((dateKey: string, minutes: number) => void) | null;
}) {
  const laidOut = layOutDay(column.occurrences);
  const minBlockHeight = compact ? 18 : 34;

  return (
    <View
      className="border-l border-border/60"
      style={{ width, height: gridHeight(bounds, pixelsPerHour) }}
    >
      {/* Empty grid first, so a block always wins the tap that lands on it. */}
      {onSelectSlot
        ? slotSegments(bounds).map((segment) => {
            const top = offsetForMinutes(segment.fromMinutes, bounds, pixelsPerHour);
            const height =
              ((segment.toMinutes - segment.fromMinutes) / 60) * pixelsPerHour;
            return (
              <Pressable
                key={segment.fromMinutes}
                className="absolute left-0"
                style={{ top, height, width }}
                // In the week grid these are 45 points wide and there are 126 of
                // them; naming every one would bury the seva in a screen
                // reader's list. The day view carries the labelled version.
                accessible={!compact}
                accessibilityRole="button"
                accessibilityLabel={`Post a seva on ${longDayLabel(column.dateKey)} at ${formatClock(segment.fromMinutes)}`}
                onPress={(event) =>
                  onSelectSlot(
                    column.dateKey,
                    slotMinutesFromOffset(
                      top + (event.nativeEvent.locationY ?? 0),
                      bounds,
                      pixelsPerHour,
                    ),
                  )
                }
              />
            );
          })
        : null}

      <ProgrammeLayer
        entries={column.programme}
        bounds={bounds}
        pixelsPerHour={pixelsPerHour}
        width={width}
        showLabels={showProgrammeLabels}
      />

      {laidOut.map(({ item, lane, lanes }) => {
        const geometry = blockGeometry(item, bounds, pixelsPerHour, minBlockHeight);
        const laneWidth = width / lanes;
        return (
          <SevaBlock
            key={item.service_instance_id}
            occurrence={item}
            top={geometry.top}
            height={geometry.height}
            left={lane * laneWidth + 1}
            width={laneWidth - 2}
            compact={compact}
            onPress={() => onSelectOccurrence(item)}
          />
        );
      })}
    </View>
  );
}

/**
 * The timetable itself: hours down the side, days across, blocks in the middle.
 *
 * The hours scroll and the dates do not — the dates live above this, so paging
 * a week never loses the thing that says which week you are on.
 */
export function TimetableGrid({
  columns,
  bounds,
  pixelsPerHour,
  columnWidth,
  compact,
  nowMinutes,
  todayKey,
  onSelectOccurrence,
  onSelectSlot,
  slotsFrom,
}: {
  columns: readonly TimetableColumn[];
  bounds: GridBounds;
  pixelsPerHour: number;
  columnWidth: number;
  /** The week grid, where a block is too narrow for anything but a name. */
  compact: boolean;
  /** Chicago minutes past midnight, or null when today is not on screen. */
  nowMinutes: number | null;
  todayKey: string;
  onSelectOccurrence: (occurrence: SevaScheduleOccurrence) => void;
  onSelectSlot: ((dateKey: string, minutes: number) => void) | null;
  /** The first day an empty square may be posted into. Earlier days are read-only. */
  slotsFrom?: string;
}) {
  const height = gridHeight(bounds, pixelsPerHour);
  const todayIndex = columns.findIndex((column) => column.dateKey === todayKey);
  const showNow =
    nowMinutes !== null &&
    todayIndex >= 0 &&
    nowMinutes >= bounds.startMinutes &&
    nowMinutes <= bounds.endMinutes;

  return (
    <ScrollView
      className="flex-1"
      contentContainerStyle={{ paddingBottom: 32 }}
      showsVerticalScrollIndicator={false}
    >
      <View className="flex-row" style={{ height }}>
        <View style={{ width: TIME_GUTTER_WIDTH, height }}>
          {hourLines(bounds).map((minutes) => (
            <Text
              key={minutes}
              className="absolute right-1 font-sans text-[10px] text-stoneMuted"
              style={{ top: offsetForMinutes(minutes, bounds, pixelsPerHour) - 6 }}
            >
              {formatClock(minutes)}
            </Text>
          ))}
        </View>

        <View className="flex-1" style={{ height }}>
          {/* The hour rules, under everything and out of the tap path. */}
          <View className="absolute inset-0" pointerEvents="none">
            {hourLines(bounds).map((minutes) => (
              <View
                key={minutes}
                className="absolute left-0 right-0 h-px bg-border/70"
                style={{ top: offsetForMinutes(minutes, bounds, pixelsPerHour) }}
              />
            ))}
          </View>

          <View className="flex-row">
            {columns.map((column) => (
              <DayColumn
                key={column.dateKey}
                column={column}
                bounds={bounds}
                pixelsPerHour={pixelsPerHour}
                width={columnWidth}
                compact={compact}
                showProgrammeLabels={!compact}
                onSelectOccurrence={onSelectOccurrence}
                onSelectSlot={
                  slotsFrom && column.dateKey < slotsFrom ? null : onSelectSlot
                }
              />
            ))}
          </View>

          {showNow ? (
            <View
              className="absolute left-0 right-0 flex-row items-center"
              pointerEvents="none"
              style={{
                top: offsetForMinutes(nowMinutes, bounds, pixelsPerHour) - 3,
              }}
            >
              <View
                className="h-1.5 w-1.5 rounded-pill bg-vermilion"
                style={{ marginLeft: todayIndex * columnWidth }}
              />
              <View className="h-px flex-1 bg-vermilion/70" />
            </View>
          ) : null}
        </View>
      </View>
    </ScrollView>
  );
}

/**
 * A month, at the only fidelity a phone can tell the truth at.
 *
 * Thirty days of a seventeen-and-a-half-hour timetable is a block two pixels
 * tall; what is left after that shrink is not a timetable, it is a smear. So a
 * month answers the two questions a month is opened for — how busy is that
 * week, and is anything still short of devotees — and hands the day itself to
 * the timetable with one tap.
 */
export function MonthDensityGrid({
  cells,
  density,
  todayKey,
  anchorMonth,
  onSelectDay,
}: {
  cells: readonly (string | null)[];
  density: Map<string, DayDensity>;
  todayKey: string;
  /** "2026-08" — used only to say which cells are outside this month. */
  anchorMonth: string;
  onSelectDay: (dateKey: string) => void;
}) {
  const rows: Array<Array<string | null>> = [];
  for (let index = 0; index < cells.length; index += 7) {
    rows.push(cells.slice(index, index + 7));
  }
  // A trailing row of nothing but other-month cells is a row of nothing.
  const usedRows = rows.filter((row) => row.some((cell) => cell !== null));

  return (
    <View>
      <View className="flex-row">
        {["M", "T", "W", "T", "F", "S", "S"].map((initial, index) => (
          <Text
            key={`${initial}-${index}`}
            className="flex-1 text-center font-sans text-[10px] uppercase tracking-wider text-stoneMuted"
          >
            {initial}
          </Text>
        ))}
      </View>
      {usedRows.map((row, rowIndex) => (
        <View key={rowIndex} className="mt-1 flex-row">
          {row.map((dateKey, cellIndex) => {
            if (!dateKey) {
              return (
                <View
                  key={`${rowIndex}-${cellIndex}`}
                  className="flex-1"
                  accessibilityElementsHidden
                />
              );
            }
            const day = density.get(dateKey);
            const isToday = dateKey === todayKey;
            const count = day?.seva ?? 0;
            const open = day?.openSlots ?? 0;
            return (
              <Pressable
                key={dateKey}
                className={`mx-0.5 min-h-14 flex-1 items-center rounded-button border py-1 ${
                  isToday ? "border-vermilion bg-white" : "border-border bg-white"
                }`}
                accessibilityRole="button"
                accessibilityLabel={`${longDayLabel(dateKey)}${isToday ? ", today" : ""}, ${
                  count === 0
                    ? "no seva"
                    : `${count} seva${open > 0 ? `, ${open} place${open === 1 ? "" : "s"} still open` : ""}`
                }`}
                accessibilityHint="Opens this day's timetable"
                onPress={() => onSelectDay(dateKey)}
              >
                <Text
                  className={`font-sans-bold text-xs ${
                    isToday ? "text-vermilion" : "text-stone"
                  }`}
                >
                  {dayNumber(dateKey)}
                </Text>
                {count > 0 ? (
                  <>
                    <Text className="mt-0.5 font-sans text-[10px] text-stoneMuted">
                      {count}
                    </Text>
                    <View className="mt-0.5 flex-row gap-0.5">
                      {Array.from({ length: Math.min(count, 3) }).map((_, dot) => (
                        <View
                          key={dot}
                          className={`h-1 w-1 rounded-pill ${
                            open > 0 ? "bg-vermilion" : "bg-peacock"
                          }`}
                        />
                      ))}
                    </View>
                  </>
                ) : null}
              </Pressable>
            );
          })}
        </View>
      ))}
      <Text className="mt-3 font-sans text-xs leading-5 text-stoneMuted">
        {`A dot for each seva, up to three. Vermilion means places are still open. ${monthLabel(`${anchorMonth}-01`)} only — the pale cells belong to another month and are not loaded.`}
      </Text>
    </View>
  );
}

/**
 * What the colours mean, said once rather than guessed at seven times.
 *
 * Hidden from screen readers on purpose: every block already says its own kind
 * of seva in words, so this is a key to a visual shorthand only.
 */
export function ScheduleLegend({
  entries,
}: {
  entries: readonly { label: string; fill: string }[];
}) {
  return (
    <View
      className="mt-2 flex-row flex-wrap items-center gap-x-3 gap-y-1"
      accessibilityElementsHidden
      importantForAccessibility="no-hide-descendants"
    >
      {entries.map((entry) => (
        <View key={entry.label} className="flex-row items-center">
          <View className={`h-2.5 w-2.5 rounded-[3px] ${entry.fill}`} />
          <Text className="ml-1 font-sans text-[11px] text-stoneMuted">
            {entry.label}
          </Text>
        </View>
      ))}
      <View className="flex-row items-center">
        <View className="h-1.5 w-1.5 rounded-pill bg-vermilion" />
        <Text className="ml-1 font-sans text-[11px] text-stoneMuted">
          Places still open
        </Text>
      </View>
      {/* Without this the pale marigold bands behind the seva are unexplained
          furniture — and in the week grid, where they are too narrow to carry
          their own names, they are all a reader has to go on. */}
      <View className="flex-row items-center">
        <View className="h-2.5 w-2.5 rounded-[3px] border-l-2 border-marigold/40 bg-marigoldSoft/40" />
        <Text className="ml-1 font-sans text-[11px] text-stoneMuted">
          Temple programme (read-only)
        </Text>
      </View>
    </View>
  );
}

/**
 * One temple programme entry, where a schedule is read as a list rather than
 * as a grid.
 *
 * Deliberately not a `SevaCard` and deliberately not a `Pressable`. The
 * temple's words are "just read only": this is the house's own rhythm, nobody
 * is assigned to it, it counts as nobody's service and there is nothing to
 * open. Making it look like the seva rows it sits between would invite exactly
 * the tap that has nowhere to go — so it is shorter, marigold, unpressable,
 * and says what it is in words rather than relying on the colour.
 *
 * A start with no end is drawn with the same dot the timetable gives it, so a
 * coordinator reading the list and the grid sees one convention, not two.
 */
export function ProgrammeRow({
  entry,
}: {
  entry: TempleProgrammeOccurrence;
}) {
  const isMoment = entry.duration_minutes === null;
  return (
    <View
      className="min-h-11 flex-row items-center rounded-button border border-marigold/30 bg-marigoldSoft/40 px-3 py-2"
      accessible
      accessibilityRole="text"
      accessibilityLabel={`${programmeAccessibilityLabel(entry)}, read only`}
    >
      <View
        className={
          isMoment
            ? "h-1.5 w-1.5 rounded-pill bg-marigold"
            : "h-4 w-1 rounded-pill bg-marigold"
        }
      />
      <Text
        className="ml-3 min-w-0 flex-1 font-sans-bold text-sm text-stone"
        numberOfLines={1}
      >
        {entry.name}
      </Text>
      <Text className="ml-2 flex-shrink-0 font-sans text-sm text-stoneMuted">
        {programmeTimeLabel(entry)}
      </Text>
    </View>
  );
}

/**
 * What the programme rows in a list are, said once above them.
 *
 * The rows carry a colour and a shape; only this says out loud that the temple
 * programme is not seva and cannot be joined, which is the half of the
 * temple's requirement a colour cannot express.
 */
export function ProgrammeNote() {
  return (
    <Text className="mb-2 font-sans text-xs leading-5 text-stoneMuted">
      The temple’s own programme is shown on each day for reference. It is read
      only — it is nobody’s seva and cannot be joined.
    </Text>
  );
}

/**
 * The way in to a timetable, from wherever a schedule is being read as a list.
 *
 * One component for all three doors — the community schedule, a devotee's own
 * upcoming seva, and a coordinator standing on somebody's profile wondering
 * when they are free — because to a devotee they are the same offer: see this
 * as a week rather than as a list.
 */
export function TimetableLink({
  label,
  hint,
  onPress,
}: {
  label: string;
  hint?: string;
  onPress: () => void;
}) {
  return (
    <Pressable
      className="mb-section min-h-touch flex-row items-center rounded-card border border-border bg-white px-card py-3"
      accessibilityRole="button"
      accessibilityLabel={label}
      accessibilityHint={hint}
      onPress={onPress}
    >
      <View className="h-9 w-9 items-center justify-center rounded-pill bg-peacockSoft">
        <Ionicons
          name="grid-outline"
          size={18}
          color={tokens.colors.peacock}
        />
      </View>
      <Text className="ml-3 min-w-0 flex-1 font-sans-bold text-sm text-stone">
        {label}
      </Text>
      <Ionicons name="chevron-forward" size={20} color={tokens.colors.indigo} />
    </Pressable>
  );
}

/** The pager: which week or month, and the two arrows that move it. */
export function RangePager({
  label,
  onPrevious,
  onNext,
  onToday,
  showToday,
}: {
  label: string;
  onPrevious: () => void;
  onNext: () => void;
  onToday: () => void;
  showToday: boolean;
}) {
  return (
    <View className="flex-row items-center justify-between">
      <Pressable
        className="h-11 w-11 items-center justify-center rounded-pill bg-indigoSoft"
        accessibilityRole="button"
        accessibilityLabel="Previous"
        onPress={onPrevious}
      >
        <Ionicons name="chevron-back" size={20} color={tokens.colors.indigo} />
      </Pressable>
      <View className="min-w-0 flex-1 items-center px-2">
        <Text
          className="font-sans-bold text-base text-stone"
          accessibilityRole="header"
          numberOfLines={1}
        >
          {label}
        </Text>
        {showToday ? (
          <Pressable
            className="mt-0.5 min-h-8 justify-center"
            accessibilityRole="button"
            accessibilityLabel="Back to this week"
            onPress={onToday}
          >
            <Text className="font-sans-bold text-xs text-indigo">Today</Text>
          </Pressable>
        ) : null}
      </View>
      <Pressable
        className="h-11 w-11 items-center justify-center rounded-pill bg-indigoSoft"
        accessibilityRole="button"
        accessibilityLabel="Next"
        onPress={onNext}
      >
        <Ionicons name="chevron-forward" size={20} color={tokens.colors.indigo} />
      </Pressable>
    </View>
  );
}
