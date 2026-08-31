import { Ionicons } from "@expo/vector-icons";
import { useCallback, useEffect, useMemo, useState } from "react";
import { Linking, PanResponder, Pressable, Text, View } from "react-native";

import tokens from "../../design-tokens.json";
import { LoadFailure, Screen, ScreenTitle, SkeletonCard } from "../components/ui";
import { hasAccessPermission } from "../features/access/model";
import { useCurrentAccessProfile } from "../features/access/hooks";
import { errorMessage } from "../features/services/format";
import {
  describeDayTitles,
  findDay,
  findNextDay,
  groupCalendarDays,
  groupCalendarMonths,
  isDayNote,
  nextDayParana,
  observanceCountLabel,
  relativeDayLabel,
  splitEventTitle,
  titledEvents,
  type VaisnavaDay,
} from "../features/vaisnavaCalendar/agenda";
import {
  longCalendarDate,
  monthName,
} from "../features/vaisnavaCalendar/calendarDates";
import { CalendarPublishPanel } from "../features/vaisnavaCalendar/components";
import {
  addMonths,
  dayDotCount,
  describeGridDay,
  monthGridWeeks,
  monthStartKey,
  readSwipe,
  weekdayColumns,
  type MonthGridDay,
} from "../features/vaisnavaCalendar/monthGrid";
import {
  describeParana,
  formatParanaRange,
  formatParanaReason,
  type ParanaWindow,
} from "../features/vaisnavaCalendar/parana";
import {
  useVaisnavaCalendarEvents,
  useVaisnavaCalendarPublications,
  useVaisnavaCalendarRealtime,
} from "../features/vaisnavaCalendar/hooks";
import type { VaisnavaCalendarEvent } from "../features/vaisnavaCalendar/types";
import { getChicagoDateKey } from "../lib/chicagoDate";
import { useRefreshOnFocus } from "../lib/useRefreshOnFocus";
import { usePrototypeSession } from "../store/usePrototypeSession";

/**
 * The Vaiṣṇava Calendar: a month grid, and the chosen day set out beneath it.
 *
 * A grid alone cannot work here — two thirds of the year is empty, and the
 * days that are not carry titles as long as "Srila Bhaktisiddhanta Sarasvati
 * Thakura -- Disappearance", which no 40-point cell will ever hold. A list
 * alone loses the shape of the month, which is the thing everyone recognises
 * as a calendar. So the work is divided the way Google and Apple divide it:
 * the grid carries only marks, and the words all live in the day below it.
 * Nothing has to be squeezed, and nothing has to be tapped to be read.
 */

const COLUMNS = weekdayColumns();

/**
 * The break-fast window, given the weight of the instruction it is.
 *
 * The one component for it, so the times can never be set two ways on one
 * screen — the day's own window and tomorrow's both come through here.
 */
function ParanaBlock({
  window: paranaWindow,
  label,
}: {
  window: ParanaWindow;
  label: string;
}) {
  const reason = formatParanaReason(paranaWindow);
  const times = `${formatParanaRange(paranaWindow)}${
    paranaWindow.zone ? ` ${paranaWindow.zone}` : ""
  }`;

  return (
    <View className="rounded-button border border-peacock/25 bg-peacockSoft px-4 py-3">
      <Text className="font-sans-bold text-[11px] uppercase tracking-widest text-peacock">
        {label}
      </Text>
      <Text className="mt-1 font-display text-[21px] leading-7 text-peacock">
        {times}
      </Text>
      {reason ? (
        <Text className="mt-0.5 font-sans text-[13px] leading-5 text-stoneMuted">
          {reason}
        </Text>
      ) : null}
    </View>
  );
}

/**
 * One observance.
 *
 * "Srila Gopala Bhatta Gosvami -- Appearance" is set as a name followed by a
 * quieter occasion, in one wrapping paragraph with no line limit. Splitting it
 * into two hard lines, or clipping it, is how these turn into nonsense.
 *
 * Three things share this list and used to share one weight, which is what made
 * a five-line day a wall: the day's own observance, the occasion qualifying a
 * name, and a note qualifying the day. One step of size marks the lead — the
 * events arrive sorted by consequence, so the first line is the day — and
 * muted colour marks everything that qualifies something else.
 */
function EventLine({
  event,
  lead = false,
}: {
  event: VaisnavaCalendarEvent;
  /** The first real observance of the day, set a step larger than the rest. */
  lead?: boolean;
}) {
  const { name, qualifier } = splitEventTitle(event.title);

  // Quieter in colour but not in size: "(Fast till noon)" is subordinate to the
  // observance it qualifies, and is still an instruction to a devotee. Muted is
  // how this card already says "this qualifies the line above".
  if (isDayNote(event.title)) {
    return (
      <Text className="font-sans text-[15px] leading-6 text-stoneMuted">
        {name}
      </Text>
    );
  }

  return (
    <Text
      className={`font-sans text-stone ${
        lead ? "text-[17px] leading-7" : "text-[15px] leading-6"
      }`}
    >
      {name}
      {qualifier ? (
        // A no-break space keeps the dash tied to the name it follows, so a
        // title that wraps can never begin a line with a stranded "—".
        <Text className="text-stoneMuted">
          {" — "}
          {qualifier}
        </Text>
      ) : null}
    </Text>
  );
}

/**
 * The one marker on this screen, on the one thing that asks a devotee to act.
 *
 * The word carries the meaning and the marigold only points at it: the label
 * was set in marigold on white, which is about 2.4:1 — a colour a devotee has
 * to already know to read. Colour is never the signal here, only the accent.
 */
function FastingMark() {
  return (
    <View className="mb-2 flex-row items-center">
      <View className="h-2 w-2 rounded-pill bg-marigold" />
      <Text className="ml-2 font-sans-bold text-[11px] uppercase tracking-widest text-stone">
        Fasting
      </Text>
    </View>
  );
}

/**
 * One square of the grid.
 *
 * One fill on the grid, ever, and it is the selection: a filled circle is what
 * "this is the day below" means, and today wearing a second fill made a screen
 * showing 23 January read as though it had two days chosen. Today is a ring on
 * the same circle instead — the distinction is fill against outline rather than
 * one indigo against another, which survives both a colour-blind reader and a
 * phone in sunlight, and which needs no legend because every calendar draws it
 * this way. The ring is on the numeral's circle, not round the cell: a border
 * on the cell reads as a box among boxes, and boxes are what makes a grid look
 * homemade.
 */
function DayCell({
  cell,
  day,
  isToday,
  isSelected,
  inYear,
  onPress,
}: {
  cell: MonthGridDay;
  day: VaisnavaDay | null;
  isToday: boolean;
  isSelected: boolean;
  /** False for the sliver of a neighbouring year, which has no data at all. */
  inYear: boolean;
  onPress: () => void;
}) {
  const dots = dayDotCount(day?.events.length ?? 0);

  // Selected wins over today when they are the same day: two marks on one
  // circle is a ring nobody can see under a fill.
  const circle = isSelected
    ? "bg-indigo"
    : isToday
      ? "border border-indigo/45"
      : "";
  const numeral = isSelected
    ? "text-white"
    : isToday
      ? "text-indigo"
      : "text-stone";

  return (
    <Pressable
      className={`flex-1 items-center py-1 ${cell.inMonth ? "" : "opacity-40"}`}
      disabled={!inYear}
      focusable={inYear}
      accessibilityRole={inYear ? "button" : "none"}
      accessibilityElementsHidden={!inYear}
      importantForAccessibility={inYear ? "yes" : "no-hide-descendants"}
      accessibilityState={{ selected: isSelected }}
      accessibilityLabel={
        inYear ? describeGridDay(cell, day, { isToday }) : undefined
      }
      onPress={onPress}
    >
      <View
        className={`h-9 w-9 items-center justify-center rounded-pill ${circle}`}
      >
        <Text
          className={`text-[15px] ${
            isSelected || isToday ? "font-sans-bold" : "font-sans"
          } ${numeral}`}
        >
          {cell.day}
        </Text>
      </View>
      {/* Held at a fixed height whether or not there are dots, so no row of
          the grid is ever a different height from its neighbours. Smaller and
          closer than they were: at six pixels apiece, three of them under a
          fifteen-point numeral are a second row of marks competing with it. */}
      <View className="mt-1 h-[5px] flex-row items-center">
        {Array.from({ length: dots }, (_, index) => (
          <View
            key={index}
            className={`h-[5px] w-[5px] rounded-pill ${index ? "ml-[3px]" : ""} ${
              day?.fasting ? "bg-marigold" : "bg-stoneMuted"
            }`}
          />
        ))}
      </View>
    </Pressable>
  );
}

/** Where the view is standing: a month on screen, and a day chosen within it. */
type CalendarView = {
  year: number;
  month: number;
  /** "2026-01-14" — the day the list below the grid is showing. */
  date: string;
  /**
   * False only between asking for a year and its events arriving, while the
   * opening month is still a guess. See the settling effect below.
   */
  settled: boolean;
};

export function VaisnavaCalendarScreen() {
  const activeUserId = usePrototypeSession((state) => state.activeUserId);
  const profile = useCurrentAccessProfile(activeUserId);
  const publications = useVaisnavaCalendarPublications();
  useVaisnavaCalendarRealtime(Boolean(activeUserId));

  const today = getChicagoDateKey(new Date());
  const todayYear = Number(today.slice(0, 4));
  const todayMonth = Number(today.slice(5, 7)) - 1;

  const [view, setView] = useState<CalendarView>(() => ({
    year: todayYear,
    month: todayMonth,
    date: today,
    settled: true,
  }));

  const events = useVaisnavaCalendarEvents(
    view.year,
    (publications.data?.length ?? 0) > 0,
  );
  useRefreshOnFocus([profile, publications, events]);

  const publishedYears = useMemo(
    () => (publications.data ?? []).map((publication) => publication.calendar_year),
    [publications.data],
  );

  const days = useMemo(
    () => groupCalendarDays(events.data ?? []),
    [events.data],
  );
  const byDate = useMemo(
    () => new Map(days.map((day) => [day.date, day])),
    [days],
  );
  const months = useMemo(
    () => groupCalendarMonths(days, view.year),
    [days, view.year],
  );

  /**
   * Which day a month opens on. Today when the month holds it; otherwise the
   * first day that has anything, because most months of this calendar are two
   * thirds empty and landing on the 1st would show a devotee "nothing" for a
   * month that in fact holds Gaura Purnima. The dots make the choice legible.
   */
  const openingDate = useCallback(
    (year: number, month: number) => {
      if (year === todayYear && month === todayMonth) return today;
      const first = days.find((day) => day.month === month);
      return first?.date ?? monthStartKey(year, month);
    },
    [days, today, todayMonth, todayYear],
  );

  // Paging is a state change and nothing else — the whole year is already in
  // the cache, so no month ever waits on the network to be drawn.
  const stepMonth = useCallback(
    (delta: number) =>
      setView((current) => {
        const next = addMonths(current.year, current.month, delta);
        // The year switcher owns years; an arrow may not silently fetch one.
        if (next.year !== current.year) return current;
        return {
          ...next,
          date: openingDate(next.year, next.month),
          settled: true,
        };
      }),
    [openingDate],
  );

  const swipe = useMemo(
    () =>
      PanResponder.create({
        // Only on move, and only once the drag is decisively sideways: a tap
        // must still reach the day underneath, and a vertical scroll must
        // still belong to the screen.
        onMoveShouldSetPanResponder: (_event, gesture) =>
          readSwipe(gesture.dx, gesture.dy) !== 0,
        onPanResponderTerminationRequest: () => false,
        onPanResponderRelease: (_event, gesture) => {
          const direction = readSwipe(gesture.dx, gesture.dy);
          if (direction) stepMonth(direction);
        },
      }),
    [stepMonth],
  );

  const focusYear = useCallback(
    (year: number) =>
      setView({
        year,
        month: year === todayYear ? todayMonth : 0,
        date: year === todayYear ? today : monthStartKey(year, 0),
        // A year other than this one has to wait for its events before it
        // knows which month to open on.
        settled: year === todayYear,
      }),
    [today, todayMonth, todayYear],
  );

  useEffect(() => {
    if (!publishedYears.length || publishedYears.includes(view.year)) return;
    // The current year whenever the temple has published it, because that is
    // where the devotee is standing. Falling back to the first row would put
    // them wherever the query happened to sort -- it comes back newest first,
    // so in an ordinary August that is next January.
    focusYear(
      publishedYears.includes(todayYear) ? todayYear : publishedYears[0],
    );
  }, [focusYear, publishedYears, todayYear, view.year]);

  /**
   * A browsed year opens where it has something in it; the current year always
   * opens on today, empty or not, because that is where the devotee is
   * standing. `settled` makes this happen once on arrival and never again, so
   * paging deliberately into an empty month does not snap back.
   */
  useEffect(() => {
    if (view.settled) return;
    // The events on hand may still be the year being left; settling on one of
    // those would jump the grid into a year it is not showing.
    const arrived = days.filter((day) => day.date.startsWith(`${view.year}-`));
    if (!arrived.length) return;
    const first = arrived.find((day) => day.month >= view.month) ?? arrived[0];
    setView({
      year: view.year,
      month: first.month,
      date: first.date,
      settled: true,
    });
  }, [days, view]);

  const role = profile.data?.role ?? "devotee";
  const canPublish = hasAccessPermission(role, "services.manage_recurring");
  const publication = (publications.data ?? []).find(
    (item) => item.calendar_year === view.year,
  );

  const weeks = useMemo(
    () => monthGridWeeks(view.year, view.month),
    [view.month, view.year],
  );
  const monthLabel = months.find((month) => month.month === view.month);
  const monthTitle = monthName(view.year, view.month);

  const selectedDay = findDay(days, view.date);
  const selectedTitles = selectedDay ? titledEvents(selectedDay) : [];
  const isToday = view.date === today;
  const nextDay = findNextDay(days, view.date);

  // The fast and the window that ends it are published a day apart as two
  // unrelated rows. A devotee deciding when to eat needs them together, on the
  // day the fast is actually kept.
  const breakFastTomorrow = selectedDay?.fasting
    ? (nextDayParana(days, view.date)?.window ?? null)
    : null;

  const canReturnToToday =
    publishedYears.includes(todayYear) && view.date !== today;

  const spokenDay = [
    isToday
      ? `Today, ${longCalendarDate(view.date)}.`
      : `${longCalendarDate(view.date)}.`,
    selectedDay?.fasting ? "A fasting day." : null,
    selectedDay
      ? selectedTitles.length
        ? `${describeDayTitles(selectedDay)}.`
        : null
      : days.length
        ? "Nothing is observed on this day."
        : `Nothing is listed for ${view.year} yet.`,
    selectedDay?.parana ? describeParana(selectedDay.parana) : null,
    breakFastTomorrow
      ? `Break fast tomorrow, ${formatParanaRange(breakFastTomorrow)}${
          breakFastTomorrow.zone ? ` ${breakFastTomorrow.zone}` : ""
        }.`
      : null,
  ]
    .filter(Boolean)
    .join(" ");

  const nextSummary = nextDay
    ? describeDayTitles(nextDay) ||
      (nextDay.parana ? describeParana(nextDay.parana) : "")
    : "";

  const queryError =
    errorMessage(publications.error, "The calendar could not be loaded.") ??
    errorMessage(events.error, "The calendar could not be loaded.");

  return (
    <Screen topInset={false}>
      <ScreenTitle
        eyebrow="Chicago · GCal 11"
        action={
          canReturnToToday ? (
            <Pressable
              className="min-h-10 items-center justify-center rounded-pill bg-indigoSoft px-4"
              accessibilityRole="button"
              accessibilityLabel="Go to today"
              onPress={() =>
                setView({
                  year: todayYear,
                  month: todayMonth,
                  date: today,
                  settled: true,
                })
              }
            >
              <Text className="font-sans-bold text-sm text-indigo">Today</Text>
            </Pressable>
          ) : undefined
        }
      >
        Vaiṣṇava Calendar
      </ScreenTitle>

      {queryError ? (
        <LoadFailure
          reachable
          message={queryError}
          onRetry={() => {
            void publications.refetch();
            void events.refetch();
          }}
        />
      ) : publications.isLoading ? (
        <SkeletonCard />
      ) : !publishedYears.length ? (
        <View className="mb-section items-center rounded-card border border-border bg-white px-card py-8">
          <Ionicons name="calendar-outline" size={30} color={tokens.colors.peacock} />
          <Text className="mt-3 text-center font-sans-bold text-base text-stone">
            No calendar has been published yet
          </Text>
          <Text className="mt-1 text-center font-sans text-sm leading-5 text-stoneMuted">
            A Community Head, Tech Admin, or President can add the Chicago ICS file below.
          </Text>
        </View>
      ) : (
        <>
          {/* One switcher only once there is a choice to make. A single
              published year is already named by the month heading. */}
          {publishedYears.length > 1 ? (
            <View className="mb-3 flex-row items-center rounded-pill border border-border bg-white p-1">
              {publishedYears.map((year) => (
                <Pressable
                  key={year}
                  className={`min-h-10 flex-1 items-center justify-center rounded-pill px-3 ${
                    year === view.year ? "bg-indigo" : ""
                  }`}
                  accessibilityRole="button"
                  accessibilityState={{ selected: year === view.year }}
                  accessibilityLabel={`Show the ${year} calendar`}
                  onPress={() => focusYear(year)}
                >
                  <Text
                    className={`font-sans-bold text-sm ${
                      year === view.year ? "text-white" : "text-stoneMuted"
                    }`}
                  >
                    {year}
                  </Text>
                </Pressable>
              ))}
            </View>
          ) : null}

          {events.isLoading ? (
            <SkeletonCard />
          ) : (
            <>
              <View className="mb-2.5 flex-row items-center justify-between">
                <View className="min-w-0 flex-1 pr-2">
                  <Text
                    className="font-display text-[21px] leading-7 text-stone"
                    accessibilityRole="header"
                    numberOfLines={1}
                  >
                    {monthTitle}
                  </Text>
                  <Text className="font-sans text-xs text-stoneMuted">
                    {observanceCountLabel(monthLabel?.eventCount ?? 0)}
                  </Text>
                </View>
                <View className="flex-row items-center">
                  {[-1, 1].map((delta) => {
                    const target = addMonths(view.year, view.month, delta);
                    const available = target.year === view.year;
                    return (
                      <Pressable
                        key={delta}
                        className={`ml-1.5 h-10 w-10 items-center justify-center rounded-pill border border-border bg-white ${
                          available ? "" : "opacity-30"
                        }`}
                        hitSlop={6}
                        disabled={!available}
                        accessibilityRole="button"
                        accessibilityState={{ disabled: !available }}
                        accessibilityLabel={
                          delta < 0 ? "Previous month" : "Next month"
                        }
                        onPress={() => stepMonth(delta)}
                      >
                        <Ionicons
                          name={delta < 0 ? "chevron-back" : "chevron-forward"}
                          size={19}
                          color={tokens.colors.indigo}
                        />
                      </Pressable>
                    );
                  })}
                </View>
              </View>

              <View className="rounded-card border border-border bg-white px-1.5 pb-2 pt-2.5">
                {/* Seven initials, and two of them are "T". They are a visual
                    ruler, not information — every cell says its own weekday in
                    full — so a screen reader is spared them. */}
                <View
                  className="flex-row pb-2"
                  accessibilityElementsHidden
                  importantForAccessibility="no-hide-descendants"
                >
                  {COLUMNS.map((column) => (
                    <View key={column.name} className="flex-1 items-center">
                      {/* No tracking: letter-spacing is added after the last
                          letter too, which pushed every one-letter heading half
                          a space left of the column it labels. And no bold —
                          the ruler was heavier than the dates it measures. */}
                      <Text className="font-sans text-[11px] text-stoneMuted">
                        {column.initial}
                      </Text>
                    </View>
                  ))}
                </View>

                {/* `role` rather than `accessibilityRole`: "grid" and "row" are
                    only in React Native's W3C role set. */}
                <View
                  role="grid"
                  accessibilityLabel={`${monthTitle}, by week`}
                  {...swipe.panHandlers}
                >
                  {weeks.map((week) => (
                    <View key={week[0].date} role="row" className="flex-row">
                      {week.map((cell) => (
                        <DayCell
                          key={cell.date}
                          cell={cell}
                          day={byDate.get(cell.date) ?? null}
                          isToday={cell.date === today}
                          isSelected={cell.date === view.date}
                          inYear={cell.year === view.year}
                          onPress={() =>
                            setView({
                              year: cell.year,
                              month: cell.month,
                              date: cell.date,
                              settled: true,
                            })
                          }
                        />
                      ))}
                    </View>
                  ))}
                </View>
              </View>

              <View className="mt-section rounded-card border border-border bg-white p-card">
                <View accessible accessibilityLiveRegion="polite" accessibilityLabel={spokenDay}>
                  {/* The date is what this card is about, and it was the
                      smallest thing on it — a long weekday set in capitals at
                      eleven points, which is the least readable way to print
                      one. It takes the heading it deserves, and "Today" stays
                      an eyebrow above it, where a marker belongs. */}
                  {isToday ? (
                    <Text className="mb-0.5 font-sans-bold text-[11px] uppercase tracking-widest text-peacock">
                      Today
                    </Text>
                  ) : null}
                  <Text className="font-display text-[19px] leading-7 text-stone">
                    {longCalendarDate(view.date)}
                  </Text>

                  <View className="mt-3">
                    {selectedDay?.fasting ? <FastingMark /> : null}

                    {/* The pāraṇa is the day when it falls on one, so it leads. */}
                    {selectedDay?.parana ? (
                      <View className={selectedTitles.length ? "mb-2.5" : ""}>
                        <ParanaBlock window={selectedDay.parana} label="Break fast" />
                      </View>
                    ) : null}

                    {/* Set apart rather than stacked: five observances at one
                        leading, with nothing between them, read as a paragraph
                        that had its punctuation removed. */}
                    <View className="gap-2">
                      {selectedTitles.map((event, index) => (
                        <EventLine
                          key={event.id}
                          event={event}
                          lead={index === 0}
                        />
                      ))}
                    </View>

                    {selectedDay ? null : (
                      <Text className="font-sans text-[15px] leading-6 text-stoneMuted">
                        {days.length
                          ? "Nothing is observed on this day."
                          : `Nothing is listed for ${view.year} yet.`}
                      </Text>
                    )}

                    {breakFastTomorrow ? (
                      <View className="mt-2.5">
                        <ParanaBlock
                          window={breakFastTomorrow}
                          label="Break fast tomorrow"
                        />
                      </View>
                    ) : null}
                  </View>
                </View>

                {/* On an empty day the useful answer is the next day that is
                    not empty, and one tap takes the grid there. */}
                {!selectedDay && nextDay ? (
                  <Pressable
                    className="mt-3 border-t border-border/60 pt-3"
                    accessibilityRole="button"
                    accessibilityLabel={`Next, ${longCalendarDate(nextDay.date)}, ${relativeDayLabel(
                      view.date,
                      nextDay.date,
                    )}.${nextSummary ? ` ${nextSummary}.` : ""} Show that day.`}
                    onPress={() =>
                      setView({
                        year: Number(nextDay.date.slice(0, 4)),
                        month: nextDay.month,
                        date: nextDay.date,
                        settled: true,
                      })
                    }
                  >
                    <Text className="font-sans-bold text-[11px] uppercase tracking-widest text-stoneMuted">
                      Next · {longCalendarDate(nextDay.date)} ·{" "}
                      {relativeDayLabel(view.date, nextDay.date)}
                    </Text>
                    <View className="mt-1">
                      {titledEvents(nextDay).slice(0, 1).map((event) => (
                        <EventLine key={event.id} event={event} />
                      ))}
                      {!titledEvents(nextDay).length && nextDay.parana ? (
                        <Text className="font-sans text-[15px] leading-6 text-stone">
                          Break fast {formatParanaRange(nextDay.parana)}
                          {nextDay.parana.zone ? ` ${nextDay.parana.zone}` : ""}
                        </Text>
                      ) : null}
                    </View>
                  </Pressable>
                ) : null}
              </View>
            </>
          )}

          {publication ? (
            <Pressable
              className="mt-4 flex-row items-start px-1"
              accessibilityRole={publication.source_url ? "link" : undefined}
              accessibilityLabel={`Dates calculated for Chicago, Illinois by ${publication.source_name}. ${publication.event_count} entries.`}
              disabled={!publication.source_url}
              onPress={() =>
                publication.source_url
                  ? void Linking.openURL(publication.source_url)
                  : undefined
              }
            >
              <Ionicons
                name="location-outline"
                size={15}
                color={tokens.colors.stoneMuted}
              />
              <Text className="ml-1.5 flex-1 font-sans text-xs leading-5 text-stoneMuted">
                Chicago, Illinois · {publication.event_count} entries ·{" "}
                {publication.source_name}
              </Text>
            </Pressable>
          ) : null}
        </>
      )}

      {canPublish ? (
        <CalendarPublishPanel
          publishedYears={publishedYears}
          onPublished={(year: number) => focusYear(year)}
        />
      ) : null}
    </Screen>
  );
}
