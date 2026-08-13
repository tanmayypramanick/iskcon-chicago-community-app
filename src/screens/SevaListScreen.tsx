import { Ionicons } from "@expo/vector-icons";
import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import { useMemo, useState } from "react";
import { Pressable, Share, Text, TextInput, View } from "react-native";

import tokens from "../../design-tokens.json";
import {
  ListScreen,
  Screen,
  ScreenTitle,
  SectionHeader,
} from "../components/ui";
import { useCurrentAccessProfile } from "../features/access/hooks";
import { hasAccessPermission } from "../features/access/model";
import {
  DateField,
  RegisteredSevaCard,
  ServiceCard,
  SevaCard,
  WeeklySevaCard,
} from "../features/services/components";
import {
  dateToKey,
  formatServiceDate,
  formatServiceTime,
  weekdayNames,
} from "../features/services/format";
import {
  ProgrammeNote,
  ProgrammeRow,
} from "../features/schedule/components";
import { useTempleProgramme } from "../features/schedule/hooks";
import { addDaysKey, weekdayOfKey } from "../features/schedule/layout";
import { programmeByWeekday } from "../features/schedule/selectors";
import type { TempleProgrammeOccurrence } from "../features/schedule/types";
import {
  formatChicagoShortDate,
  getChicagoDateKey,
} from "../lib/chicagoDate";
import { useServiceDashboard } from "../features/services/hooks";
import {
  completedRegistrations,
  myUnverifiedRegistrations,
  registrationInstanceIds,
  registrationsHappeningNow,
  upcomingRegistrations,
} from "../features/services/registrations";
import {
  awaitingCompletionServices,
  communitySchedule,
  communityWeeklySeva,
  didServe,
  didServeAny,
  foldCompletedSeva,
  recentlyCompletedServices,
  servedDevotees,
  servingDevotees,
  sevaHappeningNow,
  myNextWeeklyOccurrence,
  myOtherUpcomingSeva,
  myWeeklySeva,
  openOneTimeRequirements,
  openWeeklySeva,
  serviceSearchText,
  servingParticipants,
  weeklyRoster,
  weeklySearchText,
  type CompletedSevaEntry,
  type WeeklyAssignee,
  type WeeklySeva,
} from "../features/services/selectors";
import type {
  ServiceListItem,
  ServiceVerification,
} from "../features/services/types";
import { useNow } from "../lib/useNow";
import type { ServicesStackParamList } from "../navigation/types";
import { usePrototypeSession } from "../store/usePrototypeSession";

type Props = NativeStackScreenProps<ServicesStackParamList, "SevaList">;

const headings = {
  my_upcoming: ["Your commitments", "My upcoming seva"],
  open_requirements: ["Places where help is needed", "Open seva requests"],
  community_schedule: ["Temple seva at a glance", "Community schedule"],
  completed: ["Searchable service history", "Completed seva"],
  my_seva: ["Your offerings", "My seva"],
  happening_now: ["Being served right now", "Seva happening now"],
  awaiting_close: ["Over, not yet confirmed", "Waiting to be verified"],
  my_registrations: ["Sent for verification", "Waiting to be verified"],
} as const;

type RangePreset = {
  key: string;
  label: string;
  /** Days either side of today; negative reaches back into history. */
  from: number;
  to: number;
};

/**
 * Quick spans, so finding "this week" is one tap rather than two date pickers.
 * Weeks run from today rather than from Sunday: a coordinator asking "what is
 * on this week" means the next seven days.
 */
const UPCOMING_PRESETS: RangePreset[] = [
  { key: "week", label: "This week", from: 0, to: 6 },
  { key: "next", label: "Next week", from: 7, to: 13 },
  { key: "month", label: "Next 30 days", from: 0, to: 30 },
  { key: "all", label: "All", from: 0, to: 365 },
];

const HISTORY_PRESETS: RangePreset[] = [
  { key: "week", label: "Past week", from: -6, to: 0 },
  { key: "month", label: "Past month", from: -30, to: 0 },
  { key: "quarter", label: "Past 3 months", from: -90, to: 0 },
  { key: "all", label: "All", from: -180, to: 0 },
];

function shiftDays(days: number) {
  const date = new Date();
  date.setDate(date.getDate() + days);
  return date;
}

type ListRow =
  | { kind: "heading"; id: string; title: string }
  | { kind: "weekly"; id: string; template: WeeklySeva }
  | {
      /** A finished weekly seva as one card, dated by its last occurrence. */
      kind: "completedWeekly";
      id: string;
      name: string;
      templateId: string;
      latest: ServiceListItem;
      isMine: boolean;
    }
  | { kind: "service"; id: string; service: ServiceListItem }
  | { kind: "programme"; id: string; entry: TempleProgrammeOccurrence }
  | { kind: "registration"; id: string; registration: ServiceVerification };

function dayForDate(dateKey: string) {
  const [year, month, day] = dateKey.split("-").map(Number);
  return new Date(year, month - 1, day, 12).getDay();
}

export function SevaListScreen({ navigation, route }: Props) {
  const activeUserId = usePrototypeSession((state) => state.activeUserId);
  const previewRole = usePrototypeSession((state) => state.previewRole);
  const profile = useCurrentAccessProfile(activeUserId);
  const dashboard = useServiceDashboard(activeUserId);
  const mode = route.params.kind;
  const isCommunitySchedule = mode === "community_schedule";
  const completedMode =
    mode === "completed" || mode === "my_seva" || mode === "awaiting_close";
  const now = useNow();
  const role =
    __DEV__ && previewRole ? previewRole : (profile.data?.role ?? "devotee");
  const canViewCommunity = hasAccessPermission(role, "services.view_all");
  const [search, setSearch] = useState("");
  const [weekday, setWeekday] = useState<number | null>(null);
  const [preset, setPreset] = useState<string | null>(null);
  // Waiting-to-be-verified spans both sides of today: a finished request is in
  // the past, a registration awaiting its verifier may still be ahead.
  const spansBothWays = mode === "awaiting_close";
  const [fromDate, setFromDate] = useState(() => {
    const date = new Date();
    if (completedMode || spansBothWays) date.setMonth(date.getMonth() - 6);
    return date;
  });
  const [toDate, setToDate] = useState(() => {
    const date = new Date();
    if (!completedMode || spansBothWays) date.setMonth(date.getMonth() + 6);
    return date;
  });

  /**
   * The temple's own programme, drawn on every day of the community schedule.
   *
   * One week is asked for, not the range on screen. The programme is a weekly
   * recurrence, so seven days hold every weekday exactly once and describe it
   * completely — while `list_temple_programme` refuses any window over 35 days,
   * and this list reaches out a year. Asking for the whole range would either
   * fail outright or leave the programme stopping partway down the list, which
   * reads as a bug rather than as a limit.
   */
  const programmeWeekFrom = getChicagoDateKey(now);
  const programme = useTempleProgramme(
    programmeWeekFrom,
    addDaysKey(programmeWeekFrom, 6),
    isCommunitySchedule && Boolean(activeUserId),
  );
  const programmeForWeekday = useMemo(
    () => programmeByWeekday(programme.data ?? []),
    [programme.data],
  );

  const lists = useMemo(() => {
    const data = dashboard.data;
    const empty = {
      weekly: [] as WeeklySeva[],
      oneTime: [] as ServiceListItem[],
      registered: [] as ServiceVerification[],
      completed: [] as CompletedSevaEntry[],
    };
    if (!data || !activeUserId) return empty;
    // Verifying a registration writes a `service_instances` row of its own, so
    // every list built from services has to drop them or the same seva is a
    // plain card and a registration card in the same list. Only two of these
    // modes used to ask, which is how a verified past registration turned up as
    // an unconfirmed service card under "Waiting to be verified".
    const fromRegistration = registrationInstanceIds(data);
    const notARegistration = (service: ServiceListItem) =>
      !fromRegistration.has(service.id);

    if (mode === "my_upcoming") {
      // One card per weekly seva, here as on the tab. This list used to name a
      // weekly seva once as its roster card and then again for every generated
      // date, which is the repetition the temple asked us to stop; the dates
      // themselves are on the weekly seva's own screen. A covered occurrence
      // whose template this devotee cannot read still has no card of its own,
      // and `myOtherUpcomingSeva` keeps it.
      const weekly = myWeeklySeva(data, activeUserId, now);
      return {
        ...empty,
        weekly,
        oneTime: myOtherUpcomingSeva(
          data,
          activeUserId,
          new Set(weekly.map((template) => template.id)),
          now,
        ).filter(notARegistration),
        // The tab folds this devotee's registered seva into the same one-off
        // group; the See-all it opens used to answer with none at all, so the
        // section's own content was unreachable from the button beside it.
        registered: upcomingRegistrations(
          data,
          { userId: activeUserId, seesEveryone: false },
          now,
        ).filter((row) => row.status === "verified"),
      };
    }
    if (mode === "open_requirements") {
      return {
        ...empty,
        weekly: openWeeklySeva(data, now),
        oneTime: openOneTimeRequirements(data, now).filter(notARegistration),
      };
    }
    if (mode === "community_schedule") {
      // Both kinds, in one dated list. A weekly seva with occurrences to come
      // is read there, on the days it actually falls; only the ones with no
      // generated row are still shown as a roster card, so the schedule
      // carries every weekly seva without naming any of them twice.
      const scheduled = communitySchedule(data, now).filter(notARegistration);
      const scheduledTemplateIds = new Set(
        scheduled.flatMap((service) =>
          service.template_id ? [service.template_id] : [],
        ),
      );
      return {
        ...empty,
        weekly: communityWeeklySeva(data, now).filter(
          (template) => !scheduledTemplateIds.has(template.id),
        ),
        oneTime: scheduled,
        // The temple's day includes seva devotees registered for themselves,
        // which is where the tab now reads it too.
        registered: upcomingRegistrations(
          data,
          { userId: activeUserId, seesEveryone: canViewCommunity },
          now,
        ).filter((row) => row.status === "verified"),
      };
    }
    if (mode === "awaiting_close") {
      // The same question in two shapes: a finished request its poster has not
      // confirmed, and a registration the named member has not verified.
      return {
        ...empty,
        // Same scope as the Seva tab: whoever may answer for it, plus the
        // devotee who served it — their own seva must not disappear while it
        // is held between "over" and "history".
        oneTime: awaitingCompletionServices(data, now)
          .filter(notARegistration)
          .filter(
            (service) =>
              canViewCommunity ||
              service.posted_by === activeUserId ||
              servingParticipants(service).some(
                (participant) => participant.devotee.id === activeUserId,
              ),
          ),
        registered: myUnverifiedRegistrations(data, activeUserId),
      };
    }
    if (mode === "happening_now") {
      // The same scope rule as the Seva screen: a Devotee sees their own, a
      // Volunteer theirs plus what they posted, coordinators the whole temple.
      const live = sevaHappeningNow(
        data,
        {
          userId: activeUserId,
          seesEveryone: canViewCommunity,
          seesOwnPosts: hasAccessPermission(role, "services.post_requirement"),
          // Verifying a registration writes a `service_instances` row of its
          // own. Without this, a registered seva being served right now is
          // listed twice on this screen — once as a plain seva card and once as
          // the registration card below it. The Seva tab has always excluded
          // them here; this list was the one place that did not.
          excludeInstanceIds: registrationInstanceIds(data),
        },
        now,
      );
      const liveIds = new Set(
        live.flatMap((entry) => (entry.kind === "one_time" ? [entry.id] : [])),
      );
      const liveTemplateIds = new Set(
        live.flatMap((entry) => (entry.kind === "weekly" ? [entry.id] : [])),
      );
      return {
        ...empty,
        weekly: data.recurringTemplates.filter((template) =>
          liveTemplateIds.has(template.id),
        ),
        oneTime: data.services.filter((service) => liveIds.has(service.id)),
        registered: registrationsHappeningNow(
          data,
          { userId: activeUserId, seesEveryone: canViewCommunity },
          now,
        ).filter((row) => row.status === "verified"),
      };
    }
    if (mode === "my_registrations") {
      return {
        ...empty,
        registered: myUnverifiedRegistrations(data, activeUserId),
      };
    }

    // Completed history, folded the same way the tab folds it: one entry per
    // seva, weekly occurrences included, dated by the most recent one that
    // actually happened. The tab used to list every occurrence and this list
    // collapsed them onto a roster card carrying `myNextWeeklyOccurrence` — a
    // future date printed on a completed card, with "My seva" read off it.
    const completed = recentlyCompletedServices(data, now)
      .filter(notARegistration)
      // The same rule the tab's "Your completed seva" applies, from the same
      // helper: a place marked absent or excused is `not_served` to the temple,
      // and a "See all" that credits it would disagree with the section it
      // opened from.
      .filter(
        (service) => mode !== "my_seva" || didServe(service, activeUserId),
      );
    const folded = foldCompletedSeva(completed);
    return {
      ...empty,
      oneTime: completed.filter((service) => !service.template_id),
      completed: folded.filter((entry) => entry.kind === "weekly"),
      registered: completedRegistrations(
        data,
        {
          userId: activeUserId,
          // "My seva" is the devotee's own history whatever their access level.
          seesEveryone: mode === "completed" && canViewCommunity,
        },
        now,
      ).filter((row) => mode !== "my_seva" || row.devotee_id === activeUserId),
    };
  }, [activeUserId, canViewCommunity, dashboard.data, mode, now]);

  const term = search.trim().toLocaleLowerCase();
  const fromKey = dateToKey(fromDate);
  const toKey = dateToKey(toDate);
  // Who is on a weekly seva today, swaps applied — never the standing roster.
  const rosterFor = (template: WeeklySeva): WeeklyAssignee[] =>
    dashboard.data
      ? weeklyRoster(dashboard.data, template, now)
      : template.assignees;
  const visibleWeekly = lists.weekly.filter(
    (template) =>
      template.start_date <= toKey &&
      (!template.end_date || template.end_date >= fromKey) &&
      (weekday === null || template.days_of_week.includes(weekday)) &&
      (!term ||
        weeklySearchText(template, rosterFor(template)).includes(term)),
  );
  /**
   * Finished weekly seva: one card, dated by the newest occurrence that
   * actually matched the filters — so narrowing to "past week" re-dates the
   * card to that week rather than leaving it announcing a month ago, and no
   * filter can ever put a future date on it.
   */
  const visibleCompletedWeekly = lists.completed.flatMap((entry) => {
    if (entry.kind !== "weekly") return [];
    const matching = entry.occurrences.filter(
      (service) =>
        service.date >= fromKey &&
        service.date <= toKey &&
        (weekday === null || dayForDate(service.date) === weekday) &&
        (!term || serviceSearchText(service).includes(term)),
    );
    if (!matching.length) return [];
    return [{ entry, matching, latest: matching[0] }];
  });
  const visibleOneTime = lists.oneTime.filter(
    (service) =>
      service.date >= fromKey &&
      service.date <= toKey &&
      (weekday === null || dayForDate(service.date) === weekday) &&
      (!term || serviceSearchText(service).includes(term)),
  );
  // Registered seva is filtered on the temple's clock, the same clock the
  // cards read their date from, so a late-evening seva cannot land on the
  // wrong side of a date filter.
  const visibleRegistered = lists.registered.filter((row) => {
    const dateKey = getChicagoDateKey(new Date(row.start_at));
    if (dateKey < fromKey || dateKey > toKey) return false;
    if (weekday !== null && dayForDate(dateKey) !== weekday) return false;
    if (!term) return true;
    return `${row.name} ${row.devotee?.name ?? ""} ${row.location_text ?? ""}`
      .toLocaleLowerCase()
      .includes(term);
  });
  const resultCount =
    visibleWeekly.length +
    visibleCompletedWeekly.length +
    visibleOneTime.length +
    visibleRegistered.length;
  const [eyebrow, title] = headings[mode];
  /** Where registered seva shares the one-off group instead of a heading. */
  const mergedOneOff = mode === "my_upcoming";
  // awaiting_close is scoped inside: a devotee sees their own registrations,
  // a poster their own requests. It needs no extra gate.
  const requiresCommunityAccess =
    mode === "community_schedule" || mode === "completed";

  if (requiresCommunityAccess && !canViewCommunity) {
    return (
      <Screen topInset={false}>
        <View className="items-center rounded-card border border-border bg-white px-card py-9">
          <Ionicons
            name="lock-closed-outline"
            size={30}
            color={tokens.colors.indigo}
          />
          <Text className="mt-3 text-center font-sans-bold text-base text-stone">
            Community schedule access is not included
          </Text>
          <Text className="mt-1 text-center font-sans text-sm text-stoneMuted">
            Volunteers can use open seva requests and their personal seva history.
          </Text>
        </View>
      </Screen>
    );
  }

  // The community schedule is the temple's rota: read day by day rather than
  // as one undifferentiated list, so a date heading introduces its own seva.
  const scheduleRows: ListRow[] = isCommunitySchedule
    ? (() => {
        const byDay = new Map<string, ServiceListItem[]>();
        for (const service of visibleOneTime) {
          const day = byDay.get(service.date) ?? [];
          day.push(service);
          byDay.set(service.date, day);
        }
        return [...byDay.entries()]
          .sort(([left], [right]) => left.localeCompare(right))
          .flatMap(([date, services]) => {
            // The temple's day and the temple's seva in one run, ordered by
            // the clock — which is what "temple schedule along with the shift
            // schedule" asks for, and how the timetable already draws them.
            // Sunday's programme differs from a weekday's, so the weekday of
            // this date is what picks the entries.
            const timed = [
              ...services.map((service) => ({
                at: service.start_time,
                row: {
                  kind: "service" as const,
                  id: `service-${service.id}`,
                  service,
                },
              })),
              ...(programmeForWeekday.get(weekdayOfKey(date)) ?? []).map(
                (entry) => ({
                  at: entry.starts_at_local,
                  row: {
                    kind: "programme" as const,
                    id: `programme-${date}-${entry.programme_id}`,
                    entry,
                  },
                }),
              ),
            ].sort((left, right) => left.at.localeCompare(right.at));

            return [
              {
                kind: "heading" as const,
                id: `day-${date}`,
                title: formatServiceDate(date),
              },
              ...timed.map(({ row }) => row),
            ];
          });
      })()
    : [];

  const shareSchedule = () => {
    const lines = scheduleRows.flatMap((row) => {
      if (row.kind === "heading") return [`\n${row.title}`];
      if (row.kind !== "service") return [];
      // A printed rota naming a devotee who swapped out is worse than none.
      const serving = servingDevotees(row.service);
      const who = serving.length
        ? serving.map((devotee) => devotee.name).join(", ")
        : "needs help";
      return [
        `  ${formatServiceTime(row.service.start_time)}  ${row.service.name} — ${who}`,
      ];
    });
    void Share.share({
      message: `ISKCON Chicago seva schedule\n${lines.join("\n")}`.trim(),
    });
  };

  // One flat, virtualised stream: section headings travel with the rows they
  // introduce, so a six-month history mounts only what is on screen.
  const rows: ListRow[] = isCommunitySchedule ? [
    ...(visibleWeekly.length
      ? [{ kind: "heading" as const, id: "heading-weekly", title: "Weekly seva" }]
      : []),
    ...visibleWeekly.map((template) => ({
      kind: "weekly" as const,
      id: `weekly-${template.id}`,
      template,
    })),
    ...scheduleRows,
    ...(visibleRegistered.length
      ? [{ kind: "heading" as const, id: "heading-registered", title: "Registered seva" }]
      : []),
    ...visibleRegistered.map((row) => ({
      kind: "registration" as const,
      id: `registration-${row.id}`,
      registration: row,
    })),
  ] : [
    ...(visibleWeekly.length || visibleCompletedWeekly.length
      ? [{ kind: "heading" as const, id: "heading-weekly", title: "Weekly seva" }]
      : []),
    ...visibleWeekly.map((template) => ({
      kind: "weekly" as const,
      id: `weekly-${template.id}`,
      template,
    })),
    ...visibleCompletedWeekly.map(({ entry, matching, latest }) => ({
      kind: "completedWeekly" as const,
      id: entry.key,
      name: entry.kind === "weekly" ? entry.name : latest.name,
      templateId: entry.kind === "weekly" ? entry.templateId : "",
      latest,
      isMine: canViewCommunity && didServeAny(matching, activeUserId),
    })),
    ...(visibleOneTime.length || (mergedOneOff && visibleRegistered.length)
      ? [
          {
            kind: "heading" as const,
            id: "heading-seva",
            // The same two groups the Seva tab's "My upcoming seva" shows, in
            // the same order and under the same names.
            title: mergedOneOff ? "One-off seva" : "Seva",
          },
        ]
      : []),
    // A devotee's own registered seva is one of their one-off commitments, so
    // in "My upcoming seva" it shares the group rather than being announced
    // under a heading of its own — the same shape as the tab and as My seva
    // and history.
    ...(mergedOneOff
      ? visibleRegistered.map((row) => ({
          kind: "registration" as const,
          id: `registration-${row.id}`,
          registration: row,
        }))
      : []),
    ...visibleOneTime.map((service) => ({
      kind: "service" as const,
      id: `service-${service.id}`,
      service,
    })),
    ...(!mergedOneOff && visibleRegistered.length
      ? [{ kind: "heading" as const, id: "heading-registered", title: "Registered seva" }]
      : []),
    ...(mergedOneOff
      ? []
      : visibleRegistered.map((row) => ({
          kind: "registration" as const,
          id: `registration-${row.id}`,
          registration: row,
        }))),
  ];

  return (
    <ListScreen
      topInset={false}
      data={rows}
      keyExtractor={(row) => row.id}
      header={
        <>
          <ScreenTitle eyebrow={eyebrow}>{title}</ScreenTitle>

          <View className="flex-row items-center rounded-button border border-border bg-white px-4">
            <Ionicons name="search" size={19} color={tokens.colors.indigo} />
            <TextInput
              className="min-h-touch min-w-0 flex-1 px-3 font-sans text-base text-stone"
              value={search}
              onChangeText={setSearch}
              placeholder="Search seva or devotee name"
              placeholderTextColor={tokens.colors.stoneMuted}
            />
          </View>

          <View className="mt-3 flex-row flex-wrap gap-2">
            <Pressable
              className={`min-h-10 items-center justify-center rounded-pill border px-3 ${
                weekday === null ? "border-indigo bg-indigo" : "border-border bg-white"
              }`}
              onPress={() => setWeekday(null)}
            >
              <Text className={`font-sans-bold text-xs ${weekday === null ? "text-white" : "text-stone"}`}>
                Any day
              </Text>
            </Pressable>
            {weekdayNames.map((day, index) => (
              <Pressable
                key={day}
                className={`min-h-10 items-center justify-center rounded-pill border px-3 ${
                  weekday === index ? "border-indigo bg-indigo" : "border-border bg-white"
                }`}
                onPress={() => setWeekday(index)}
              >
                <Text className={`font-sans-bold text-xs ${weekday === index ? "text-white" : "text-stone"}`}>
                  {day.slice(0, 3)}
                </Text>
              </Pressable>
            ))}
          </View>

          <View className="mt-3 flex-row flex-wrap gap-2">
            {(completedMode ? HISTORY_PRESETS : UPCOMING_PRESETS).map((option) => (
              <Pressable
                key={option.key}
                className={`min-h-10 items-center justify-center rounded-pill border px-3 ${
                  preset === option.key
                    ? "border-peacock bg-peacockSoft"
                    : "border-border bg-white"
                }`}
                accessibilityRole="button"
                accessibilityLabel={`Show ${option.label}`}
                onPress={() => {
                  setPreset(option.key);
                  setFromDate(shiftDays(option.from));
                  setToDate(shiftDays(option.to));
                }}
              >
                <Text
                  className={`font-sans-bold text-xs ${
                    preset === option.key ? "text-peacock" : "text-stone"
                  }`}
                >
                  {option.label}
                </Text>
              </Pressable>
            ))}
          </View>

          <View className="mt-3 flex-row gap-3">
            <View className="flex-1">
              <DateField
                label="From"
                value={fromDate}
                onChange={(value) => {
                  setPreset(null);
                  setFromDate(value);
                }}
              />
            </View>
            <View className="flex-1">
              <DateField
                label="To"
                value={toDate}
                minimumDate={fromDate}
                onChange={(value) => {
                  setPreset(null);
                  setToDate(value);
                }}
              />
            </View>
          </View>

          {isCommunitySchedule ? (
            <Pressable
              className="mt-3 min-h-touch flex-row items-center justify-center rounded-button border border-indigo"
              accessibilityRole="button"
              accessibilityLabel="Share this schedule"
              onPress={shareSchedule}
            >
              <Ionicons
                name="share-outline"
                size={19}
                color={tokens.colors.indigo}
              />
              <Text className="ml-2 font-sans-bold text-base text-indigo">
                Share this schedule
              </Text>
            </Pressable>
          ) : null}

          <Text className="mb-2 mt-4 font-sans-bold text-sm text-peacock">
            {/* The count is seva only. The temple programme is not a result —
                it is the same ten entries every day, and counting it would
                make an empty week look busy. */}
            {resultCount} result{resultCount === 1 ? "" : "s"}
            <Text className="font-sans text-sm text-stoneMuted">
              {"  ·  "}
              {formatChicagoShortDate(fromDate)} – {formatChicagoShortDate(toDate)}
              {weekday === null ? "" : ` · ${weekdayNames[weekday]}s only`}
            </Text>
          </Text>

          {isCommunitySchedule && programme.data?.length ? (
            <ProgrammeNote />
          ) : null}
        </>
      }
      renderItem={(row) => {
        if (row.kind === "heading") {
          return (
            <View className="mt-section">
              <SectionHeader title={row.title} />
            </View>
          );
        }
        if (row.kind === "weekly") {
          // The next date this reader is actually down for, where there is one.
          // Every other date is on the weekly seva's own screen.
          const next =
            dashboard.data && activeUserId
              ? myNextWeeklyOccurrence(
                  dashboard.data,
                  activeUserId,
                  row.template.id,
                  now,
                )
              : null;
          return (
            <View className="mb-3">
              <WeeklySevaCard
                template={row.template}
                roster={rosterFor(row.template)}
                next={next ? formatServiceDate(next.date) : undefined}
                isMine={canViewCommunity && Boolean(next)}
                showPeople={canViewCommunity}
                onPress={() =>
                  navigation.navigate("WeeklySevaDetail", {
                    templateId: row.template.id,
                  })
                }
              />
            </View>
          );
        }
        if (row.kind === "completedWeekly") {
          // Dated by the occurrence that happened, never by the next one. This
          // card used to read `myNextWeeklyOccurrence` — a future date on a
          // completed card, and "My seva" decided by it, so a devotee who had
          // never served it was credited because they are down for it next
          // week.
          return (
            <View className="mb-3">
              <SevaCard
                name={row.name}
                weekly
                when={`${formatServiceDate(row.latest.date)} · ${formatServiceTime(row.latest.start_time)}`}
                minutes={row.latest.duration_minutes}
                isMine={row.isMine}
                people={servedDevotees(row.latest)}
                showPeople={canViewCommunity}
                peopleEmptyLabel="Nobody served this"
                onPress={() =>
                  navigation.navigate("WeeklySevaDetail", {
                    templateId: row.templateId,
                  })
                }
              />
            </View>
          );
        }
        if (row.kind === "programme") {
          return (
            <View className="mb-3">
              <ProgrammeRow entry={row.entry} />
            </View>
          );
        }
        if (row.kind === "service") {
          return (
            <View className="mb-3">
              <ServiceCard
                service={row.service}
                showMyTag={canViewCommunity}
                showPeople={canViewCommunity}
                onPress={() =>
                  navigation.navigate("ServiceDetail", { serviceId: row.service.id })
                }
              />
            </View>
          );
        }
        return (
          <View className="mb-3">
            <RegisteredSevaCard
              registration={row.registration}
              timing="finished"
              isMine={
                canViewCommunity && row.registration.devotee_id === activeUserId
              }
              showPeople={canViewCommunity}
              onPress={() =>
                navigation.navigate("SevaRegistrationDetail", {
                  verificationId: row.registration.id,
                })
              }
            />
          </View>
        );
      }}
      empty={
        dashboard.isLoading ? null : (
          <View className="mt-section items-center rounded-card border border-border bg-white px-card py-8">
            <Ionicons name="leaf-outline" size={27} color={tokens.colors.peacock} />
            <Text className="mt-3 text-center font-sans-bold text-base text-stone">
              No seva matches these filters
            </Text>
            <Text className="mt-1 text-center font-sans text-sm text-stoneMuted">
              Try another name, weekday, or date range.
            </Text>
          </View>
        )
      }
    />
  );
}
