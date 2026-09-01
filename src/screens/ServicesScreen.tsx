import { Ionicons } from "@expo/vector-icons";
import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import { useEffect, useState } from "react";
import { Pressable, Text, View } from "react-native";

import tokens from "../../design-tokens.json";
import {
  GroupLabel,
  LoadFailure,
  Screen,
  ScreenTitle,
  SectionHeader,
  Skeleton,
  SkeletonCard,
} from "../components/ui";
import { useCurrentAccessProfile } from "../features/access/hooks";
import { hasAccessPermission } from "../features/access/model";
import { TimetableLink } from "../features/schedule/components";
import {
  ClashWarningSheet,
  ClosedUnservedNotice,
  FormError,
  RegisteredSevaCard,
  ServiceCard,
  SevaCard,
  WeeklySevaCard,
} from "../features/services/components";
import { WeeklySevaAnswerSection } from "../features/services/weeklyAnswer";
import {
  clashWarningMessage,
  clashWarningTitle,
  nextDateOnWeekday,
  weekdayNameForDate,
} from "../features/services/clashes";
import {
  completedRegistrations,
  myUnverifiedRegistrations,
  registrationInstanceIds,
  registrationsHappeningNow,
  sevaTiming,
  upcomingRegistrations,
} from "../features/services/registrations";
import {
  errorMessage,
  formatDuration,
  formatServiceDate,
  formatServiceTime,
  formatWeekdayList,
} from "../features/services/format";
import {
  useClosedUnservedSeva,
  useMarkSevaServed,
  useRespondToServiceOffer,
  useRespondToCoverageRangeOffer,
  useDeleteServiceActivity,
  useServiceDashboard,
  useSevaClashLookup,
} from "../features/services/hooks";
import {
  awaitingCompletionServices,
  communityScheduleForDay,
  communityWeeklySeva,
  didServeAny,
  foldCompletedSeva,
  myCompletedServices,
  myNextWeeklyOccurrence,
  myOtherUpcomingSeva,
  myWeeklySeva,
  openOneTimeRequirements,
  openWeeklySeva,
  recentlyCompletedServices,
  servingParticipants,
  servedDevotees,
  sevaHappeningNow,
  sevaNeedingMyAnswer,
  weeklyRoster,
  type WeeklySeva,
} from "../features/services/selectors";
import type { ServiceListItem } from "../features/services/types";
import type { ServicesStackParamList } from "../navigation/types";
import {
  formatChicagoDate,
  getChicagoDateKey,
  getChicagoWeekday,
} from "../lib/chicagoDate";
import { useNow } from "../lib/useNow";
import { useServerReachable } from "../lib/connectivity";
import { useRefreshOnFocus } from "../lib/useRefreshOnFocus";
import { usePrototypeSession } from "../store/usePrototypeSession";

type Props = NativeStackScreenProps<ServicesStackParamList, "ServicesHome">;

function mutationMessage(error: unknown) {
  return errorMessage(error, "The service could not be updated.") ?? "The service could not be updated.";
}

/** The one line of when, said the same way on every card. */
function whenLine(service: ServiceListItem) {
  return `${formatServiceDate(service.date)} \u00b7 ${formatServiceTime(service.start_time)}`;
}

export function ServicesScreen({ navigation }: Props) {
  const activeUserId = usePrototypeSession((state) => state.activeUserId);
  const profileQuery = useCurrentAccessProfile(activeUserId);
  const dashboardQuery = useServiceDashboard(activeUserId);
  const respondToOffer = useRespondToServiceOffer();
  const respondToCoverage = useRespondToCoverageRangeOffer();
  const deleteActivity = useDeleteServiceActivity();
  const markServed = useMarkSevaServed();
  const reachable = useServerReachable();
  // Seva changes section as the clock moves, not because data changed.
  const now = useNow();

  useRefreshOnFocus([dashboardQuery]);

  const effectiveRole = profileQuery.data?.role ?? "devotee";
  const canPost = hasAccessPermission(
    effectiveRole,
    "services.post_requirement",
  );
  const canManageRecurring = hasAccessPermission(
    effectiveRole,
    "services.manage_recurring",
  );
  const canResolveCoverage = hasAccessPermission(
    effectiveRole,
    "services.resolve_coverage",
  );
  const canOversee = hasAccessPermission(effectiveRole, "services.oversee_activity");
  const canDeleteAny = hasAccessPermission(effectiveRole, "services.delete_any");
  // Only Core, Tech, and President see the temple-wide schedule and the
  // community's completed seva. A Devotee or Volunteer sees their own seva
  // only, so the "My seva" tag would be on every card and is dropped for them.
  const canViewCommunity = canOversee;
  const dashboard = dashboardQuery.data;
  // Seva already shown as a registration card must not appear a second time
  // through the service-driven lists.
  const registrationInstances = dashboard
    ? registrationInstanceIds(dashboard)
    : new Set<string>();
  // Every service-derived list excludes instances that exist only because a
  // registration was verified — those are shown as registration cards.
  const notARegistration = (service: { id: string }) =>
    !registrationInstances.has(service.id);

  /**
   * NOTHING IS NAMED TWICE ON THIS SCREEN.
   *
   * THE RULE, ONCE, AND IT RUNS ONE WAY ONLY:
   *
   *   A seva is named by the highest section on the screen that carries it,
   *   and every section below drops it. Exclusions run downwards, never
   *   upwards. A section may only be thinned once its emptiness claims
   *   nothing, so any section that made a promise has had its wording changed
   *   until it claims nothing rather than being left un-thinned. And what a
   *   section excludes is exactly what it renders — a preview cap may never
   *   shrink the set another section is excluding against, or the card is not
   *   moved but lost.
   *
   * Every one of these lists is built by its own selector from the same
   * dashboard, so a seva that is running now, is this devotee's, is on an open
   * request and is on the temple's day is genuinely in four of them — and
   * because they all draw the identical `SevaCard`, it read as the same card
   * four times. That is the repetition the temple keeps reporting.
   *
   * The order of the screen is therefore the order of the rule: happening now,
   * then what I am down for, then what still needs somebody, then the temple's
   * day, then what is over. Each of the last three drops whatever the ones
   * above it have named.
   *
   * One list per idea, too. Registered seva is not an "upcoming" of its own —
   * it is a one-off commitment of this devotee's, and it belongs in the same
   * group as every other one-off commitment of theirs. Finished weekly seva is
   * one card, never one card per date; `completedSevaHistory` is the only way
   * this screen or its See-all may ask for it.
   */
  const happeningNow = dashboard
    ? sevaHappeningNow(dashboard, {
        userId: activeUserId,
        seesEveryone: canOversee,
        seesOwnPosts: canPost,
        excludeInstanceIds: registrationInstances,
      }, now)
    : [];
  const happeningNowIds = new Set(
    happeningNow.flatMap((entry) => (entry.kind === "one_time" ? [entry.id] : [])),
  );
  const happeningNowTemplateIds = new Set(
    happeningNow.flatMap((entry) => (entry.kind === "weekly" ? [entry.id] : [])),
  );

  // A seva being served at this minute is not "upcoming", and it is already a
  // card an inch further up the screen.
  //
  // Every one of them is rendered, uncapped, and that is deliberate: the ids
  // below suppress the dated rows of each of these weekly seva, so capping the
  // list at three took a devotee's fourth weekly seva off the tab altogether —
  // a disappearance rather than a duplicate. The rule is that what a section
  // excludes is exactly what it renders, and this is the section that has to
  // obey it most.
  const myWeekly = (
    dashboard && activeUserId ? myWeeklySeva(dashboard, activeUserId, now) : []
  ).filter((template) => !happeningNowTemplateIds.has(template.id));
  const myWeeklyIds = new Set(myWeekly.map((template) => template.id));
  // Everything dated that is not already a card above. A weekly seva with a
  // roster card carries its own next date now, so repeating it here named the
  // same seva twice on one screen; a covered occurrence whose template this
  // devotee cannot read has no card, and still belongs here.
  const myUpcoming =
    dashboard && activeUserId
      ? myOtherUpcomingSeva(dashboard, activeUserId, myWeeklyIds, now)
          .filter(notARegistration)
          .filter((service) => !happeningNowIds.has(service.id))
      : [];
  // When this devotee is next down to serve each of their weekly seva. Read
  // from the occurrences, so a substitute sees the dates they are covering and
  // the devotee they cover for sees theirs resume.
  const nextWeeklyDate = (template: WeeklySeva) => {
    if (!dashboard || !activeUserId) return undefined;
    const occurrence = myNextWeeklyOccurrence(
      dashboard,
      activeUserId,
      template.id,
      now,
    );
    if (!occurrence) return undefined;
    return formatServiceDate(occurrence.date);
  };
  // Who is on a weekly seva today, swaps applied — never the standing roster.
  const rosterFor = (template: WeeklySeva) =>
    dashboard ? weeklyRoster(dashboard, template, now) : template.assignees;
  const weeklyOpenings = dashboard
    ? openWeeklySeva(dashboard, now).filter(
        (template) => !myWeeklyIds.has(template.id),
      )
    : [];
  // A partly-filled open request the reader has already joined is their own
  // upcoming seva — or the seva they are standing in the kitchen serving — and
  // it was being named a second time here, with a "My seva" pill the card above
  // did not carry. It is thinned now because the section's empty state no
  // longer promises that every need is covered; see the wording below.
  const myUpcomingIds = new Set(myUpcoming.map((service) => service.id));
  const oneTimeOpenings = dashboard
    ? openOneTimeRequirements(dashboard, now)
        .filter(notARegistration)
        .filter(
          (service) =>
            !happeningNowIds.has(service.id) && !myUpcomingIds.has(service.id),
        )
    : [];
  const weeklySchedule =
    dashboard && canViewCommunity ? communityWeeklySeva(dashboard, now) : [];
  const todaysWeekday = getChicagoWeekday(now);
  // The Seva screen shows the temple's day. Any other span — a week, a range,
  // a particular devotee — is chosen in the full view behind "See all".
  const todayKey = getChicagoDateKey(now);
  // Today's schedule now carries both kinds in one chronological list, weekly
  // occurrences included.
  const todaysScheduleAll =
    dashboard && canViewCommunity
      ? communityScheduleForDay(dashboard, todayKey, now).filter(notARegistration)
      : [];
  // A weekly seva whose row for today already exists is in the list above with
  // its real hour on it; naming it a second time as a roster card is the
  // repetition the temple keeps asking us to stop. What is left is the weekly
  // seva today whose occurrence has not been generated, which would otherwise
  // drop off the temple's day altogether.
  //
  // Computed from the whole day, before the exclusions below: a weekly seva
  // dropped from the dated list for being named above must not come straight
  // back as a roster card.
  const scheduledTemplateIds = new Set(
    todaysScheduleAll.flatMap((service) =>
      service.template_id ? [service.template_id] : [],
    ),
  );

  // Everything the sections above have already named. The community schedule is
  // the temple's whole day and so is a superset of all of them by construction.
  const namedAboveIds = new Set([
    ...happeningNowIds,
    ...myUpcoming.map((service) => service.id),
    ...oneTimeOpenings.map((service) => service.id),
  ]);
  const namedAboveTemplateIds = new Set([
    ...happeningNowTemplateIds,
    ...myWeeklyIds,
    ...weeklyOpenings.map((template) => template.id),
  ]);

  const todaysSchedule = todaysScheduleAll.filter(
    (service) =>
      !namedAboveIds.has(service.id) &&
      !(service.template_id && namedAboveTemplateIds.has(service.template_id)),
  );
  const todaysWeekly = weeklySchedule.filter(
    (template) =>
      template.active &&
      template.days_of_week.includes(todaysWeekday) &&
      !scheduledTemplateIds.has(template.id) &&
      !namedAboveTemplateIds.has(template.id),
  );
  // Three cards of the temple's day, shared between the three kinds it holds.
  const scheduleShownWeekly = Math.min(todaysWeekly.length, 3);
  const scheduleShownDated = Math.min(
    todaysSchedule.length,
    3 - scheduleShownWeekly,
  );
  const scheduleRoomLeft = 3 - scheduleShownWeekly - scheduleShownDated;
  const completedHistory =
    dashboard && canViewCommunity
      ? foldCompletedSeva(
          recentlyCompletedServices(dashboard, now).filter(notARegistration),
        )
      : [];
  // Seva whose time has passed and which is still owed an answer: either it was
  // never closed off, or nobody has said who served. It is not upcoming and not
  // history — it waits on whoever posted it.
  const canOverrideAnything = hasAccessPermission(effectiveRole, "app.view_all");
  // Only whoever posted it, a Tech Admin or the President may answer for it.
  const canConfirmSeva = (service: ServiceListItem) =>
    canOverrideAnything || service.posted_by === activeUserId;
  const awaitingClose = dashboard
    ? awaitingCompletionServices(dashboard, now)
        .filter(notARegistration)
        // A devotee who served it sees it waiting too. They cannot clear it,
        // but their own seva must not simply vanish from the tab while it is
        // held between "over" and "history".
        .filter(
          (service) =>
            canConfirmSeva(service) ||
            servingParticipants(service).some(
              (participant) => participant.devotee.id === activeUserId,
            ),
        )
    : [];
  // A devotee's completed history is their own only — and folded the same way,
  // so a plain devotee's weekly seva is one finished card here too.
  const myCompleted =
    dashboard && activeUserId && !canViewCommunity
      ? foldCompletedSeva(
          myCompletedServices(dashboard, activeUserId, now).filter(
            notARegistration,
          ),
        )
      : [];
  const registrationScope = {
    userId: activeUserId,
    seesEveryone: canOversee,
  };
  // Anything still awaiting a decision lives in "Waiting to be verified",
  // which is where the Ask-someone-else and Remove actions are. Showing it in
  // the timed sections as well listed the same seva twice.
  const settled = (row: { status: string }) => row.status === "verified";
  const liveRegistrations = dashboard
    ? registrationsHappeningNow(dashboard, registrationScope, now).filter(settled)
    : [];
  const upcomingRegistered = dashboard
    ? upcomingRegistrations(dashboard, registrationScope, now).filter(settled)
    : [];
  // A registration is a one-off commitment like any other, so this devotee's
  // own go into "My upcoming seva" beside their other one-off seva. They had a
  // heading of their own four sections higher, which for a plain devotee was
  // their own upcoming seva announced twice under two names — and its "See all"
  // opened a list that returned no registrations at all.
  const myUpcomingRegistered = upcomingRegistered.filter(
    (row) => row.devotee_id === activeUserId,
  );
  // Somebody else's registered seva is not this reader's commitment. It is part
  // of the temple's day, which is where a coordinator now reads it.
  const otherRegisteredToday = upcomingRegistered.filter(
    (row) =>
      row.devotee_id !== activeUserId &&
      getChicagoDateKey(new Date(row.start_at)) === todayKey,
  );
  const completedRegistered = dashboard
    ? completedRegistrations(dashboard, registrationScope, now)
    : [];
  const myPendingVerifications = dashboard
    ? myUnverifiedRegistrations(dashboard, activeUserId)
    : [];
  // Recently completed is one stream ordered by when the seva happened, newest
  // first, so a mixed history reads as a single list rather than three.
  //
  // One card per seva, weekly seva included: a Monday/Thursday/Saturday rota
  // finished three times last week and filled all three visible rows with the
  // same name. The card is dated by the most recent occurrence that actually
  // happened — never by the next one, which is how a history card ended up
  // announcing a date in the future.
  const history = [
    ...completedHistory.map((entry) => ({
      key: entry.key,
      at: entry.at,
      node:
        entry.kind === "one_time" ? (
          <ServiceCard
            service={entry.service}
            showMyTag={canViewCommunity}
            showPeople={canViewCommunity}
            onPress={() =>
              navigation.navigate("ServiceDetail", { serviceId: entry.service.id })
            }
          />
        ) : (
          <SevaCard
            name={entry.name}
            weekly
            when={whenLine(entry.latest)}
            minutes={entry.latest.duration_minutes}
            isMine={
              canViewCommunity && didServeAny(entry.occurrences, activeUserId)
            }
            people={servedDevotees(entry.latest)}
            showPeople={canViewCommunity}
            peopleEmptyLabel="Nobody served this"
            onPress={() =>
              navigation.navigate("WeeklySevaDetail", {
                templateId: entry.templateId,
              })
            }
          />
        ),
    })),
    ...completedRegistered.map((row) => ({
      key: `registration-${row.id}`,
      at: row.start_at,
      node: (
        <RegisteredSevaCard
          registration={row}
          timing="finished"
          isMine={row.devotee_id === activeUserId}
          showPeople={canViewCommunity}
          onPress={() =>
            navigation.navigate("SevaRegistrationDetail", {
              verificationId: row.id,
            })
          }
        />
      ),
    })),
  ].sort((left, right) => right.at.localeCompare(left.at));

  // Answers owed on a seva request. A Tech Admin and the President may answer
  // for anyone, so the badge has to count what they can actually act on.
  const postedAttentionCount = dashboard
    ? sevaNeedingMyAnswer(dashboard, activeUserId, canOverrideAnything).length
    : 0;
  const coverageInboxCount =
    (dashboard?.coverageRequests.filter(
      ({ exception }) => exception.status === "pending",
    ).length ?? 0) + postedAttentionCount;
  const approvalCount =
    (hasAccessPermission(effectiveRole, "app.view_all")
      ? (dashboard?.verifications ?? []).filter((row) => row.status === "pending")
          .length
      : (dashboard?.verificationInbox?.length ?? 0)) +
    (dashboard?.offerCounters?.filter((counter) => counter.status === "pending")
      .length ?? 0);
  // A failed background refetch while the tab is already showing seva is not
  // worth alarming anyone about — React Query keeps the last good data and
  // tries again. Only a fetch that leaves the screen with nothing is reported,
  // alongside anything the devotee actually did.
  const actionError =
    respondToOffer.error ??
    respondToCoverage.error ??
    deleteActivity.error ??
    markServed.error;
  const loadFailed = dashboardQuery.isError && dashboard === undefined;

  /**
   * What else this devotee is already down for when each invitation lands.
   *
   * Asked for every waiting invitation up front rather than on the tap: the
   * answer has to be there the moment they press "Yes, I can help", and a
   * devotee is never waiting on more than a handful of these.
   *
   * Weekly invitations and coverage ranges are asked about too, and they are
   * the ones that matter most — accepting a rota commits every week, so a
   * standing collision is a standing problem. A repeating commitment has no one
   * date to ask about, so the question is put on the first date it would
   * actually fall, which is the same reading of a rota the coordinator side
   * already uses.
   */
  const weeklyOfferWindows = (dashboard?.pendingRecurringOffers ?? []).map(
    ({ offer, template, coveragePlan }) => {
      const days = coveragePlan?.days_of_week?.length
        ? coveragePlan.days_of_week
        : template.days_of_week;
      const notBeforeToday =
        coveragePlan && coveragePlan.date_from > todayKey
          ? coveragePlan.date_from
          : todayKey;
      const first = days
        .map((day) => nextDateOnWeekday(notBeforeToday, day))
        .sort()[0];
      return {
        offerId: offer.id,
        date: first ?? notBeforeToday,
        startTime: template.start_time,
        durationMinutes: template.duration_minutes,
        // A single covered date is one date; anything else repeats, and the
        // warning says so rather than naming a day that is not the point.
        repeats: !coveragePlan || coveragePlan.scope !== "occurrence",
      };
    },
  );
  const offerClashes = useSevaClashLookup([
    ...(dashboard?.pendingOffers ?? []).map(({ offer, service }) => ({
      key: offer.id,
      devoteeId: activeUserId ?? "",
      date: service.date,
      startTime: service.start_time,
      durationMinutes: service.duration_minutes,
      excludeInstanceId: service.id,
    })),
    ...weeklyOfferWindows.map((window) => ({
      key: window.offerId,
      devoteeId: activeUserId ?? "",
      date: window.date,
      startTime: window.startTime,
      durationMinutes: window.durationMinutes,
    })),
  ]);
  const [clashPrompt, setClashPrompt] = useState<string | null>(null);
  const promptOffer = dashboard?.pendingOffers.find(
    ({ offer }) => offer.id === clashPrompt,
  );
  const promptWeekly = dashboard?.pendingRecurringOffers.find(
    ({ offer }) => offer.id === clashPrompt,
  );
  const promptWeeklyWindow = weeklyOfferWindows.find(
    (window) => window.offerId === clashPrompt,
  );
  const promptClashes = clashPrompt ? (offerClashes.get(clashPrompt) ?? []) : [];
  // The temple asked for clashes that keep up with devotees rearranging their
  // seva. A warning about a seva that has just been cancelled, moved or handed
  // to somebody else is simply untrue, so it goes the moment the clash does.
  useEffect(() => {
    if (clashPrompt && !promptClashes.length) setClashPrompt(null);
  }, [clashPrompt, promptClashes.length]);

  const acceptOffer = (offerId: string) => {
    if ((offerClashes.get(offerId) ?? []).length) {
      setClashPrompt(offerId);
      return;
    }
    respondToOffer.mutate({ offerId, accept: true });
  };
  /** Which mutation answers a weekly invitation — a plain rota, or a cover. */
  const weeklyResponder = (offerKind: string | undefined) =>
    offerKind === "coverage_range" ? respondToCoverage : respondToOffer;
  const acceptWeeklyOffer = (offerId: string, offerKind: string) => {
    if ((offerClashes.get(offerId) ?? []).length) {
      setClashPrompt(offerId);
      return;
    }
    weeklyResponder(offerKind).mutate({ offerId, accept: true });
  };
  const promptWording = promptWeekly
    ? {
        audience: "self" as const,
        startTime: promptWeekly.template.start_time,
        durationMinutes: promptWeekly.template.duration_minutes,
        weekday:
          promptWeeklyWindow?.repeats && promptWeeklyWindow.date
            ? weekdayNameForDate(promptWeeklyWindow.date)
            : undefined,
      }
    : {
        audience: "self" as const,
        startTime: promptOffer?.service.start_time ?? "00:00:00",
        durationMinutes: promptOffer?.service.duration_minutes ?? 0,
      };

  // Only a poster or `app.view_all` can have any of these; the RPC answers
  // everybody else an empty list, so nothing here needs to know the role.
  const closedUnserved = useClosedUnservedSeva(
    Boolean(activeUserId) && (canPost || canOverrideAnything),
  );

  return (
    <Screen>
      <ScreenTitle eyebrow="Seva together">Seva</ScreenTitle>

      <View className="mb-section gap-3">
        <Pressable
          className="min-h-[82px] flex-row items-center rounded-card bg-indigo px-card py-3"
          accessibilityRole="button"
          accessibilityLabel="Find a way to help"
          accessibilityHint="Plan seva for now or a future time"
          onPress={() => navigation.navigate("FindSeva", { mode: "plan" })}
        >
          <View className="h-11 w-11 items-center justify-center rounded-pill bg-white/15">
            <Ionicons name="heart" size={23} color={tokens.colors.marigoldSoft} />
          </View>
          <View className="ml-3 min-w-0 flex-1">
            <Text className="font-sans-bold text-base text-white">Find a way to help</Text>
            <Text className="mt-0.5 font-sans text-xs leading-4 text-white">
              Start now or plan a seva for later
            </Text>
          </View>
          <Ionicons name="chevron-forward" size={21} color={tokens.colors.white} />
        </Pressable>
        <Pressable
          className="min-h-[82px] flex-row items-center rounded-card border border-border bg-white px-card py-3"
          accessibilityRole="button"
          accessibilityLabel="Log your seva"
          accessibilityHint="Record completed seva and ask a community leader to verify it"
          onPress={() => navigation.navigate("FindSeva", { mode: "completed" })}
        >
          <View className="h-11 w-11 items-center justify-center rounded-pill bg-peacockSoft">
            <Ionicons name="checkmark-done" size={23} color={tokens.colors.peacock} />
          </View>
          <View className="ml-3 min-w-0 flex-1">
            <Text className="font-sans-bold text-base text-stone">Log your seva</Text>
            <Text className="mt-0.5 font-sans text-xs leading-4 text-stoneMuted">
              Record completed seva for verification
            </Text>
          </View>
          <Ionicons name="chevron-forward" size={21} color={tokens.colors.indigo} />
        </Pressable>
      </View>

      <View className="mb-section overflow-hidden rounded-card border border-border bg-white">
        {canPost ? (
          <Pressable
            className="min-h-[56px] flex-row items-center px-card"
            accessibilityRole="button"
            accessibilityLabel="Post a seva request"
            onPress={() => navigation.navigate("CreateService")}
          >
            <View className="h-9 w-9 items-center justify-center rounded-pill bg-marigoldSoft">
              <Ionicons
                name="add-circle-outline"
                size={18}
                color={tokens.colors.stone}
              />
            </View>
            <Text className="ml-3 min-w-0 flex-1 font-sans-bold text-base text-stone">
              Post a seva request
            </Text>
            <Ionicons
              name="chevron-forward"
              size={20}
              color={tokens.colors.indigo}
            />
          </Pressable>
        ) : null}
        <Pressable
          className={`min-h-[56px] flex-row items-center px-card ${
            canPost ? "border-t border-border" : ""
          }`}
          accessibilityRole="button"
          accessibilityLabel="See my complete seva history"
          onPress={() => navigation.navigate("MyServiceHistory")}
        >
          <View className="h-9 w-9 items-center justify-center rounded-pill bg-peacockSoft">
            <Ionicons
              name="time-outline"
              size={18}
              color={tokens.colors.peacock}
            />
          </View>
          <Text className="ml-3 min-w-0 flex-1 font-sans-bold text-base text-stone">
            My seva and history
          </Text>
          <Ionicons
            name="chevron-forward"
            size={20}
            color={tokens.colors.indigo}
          />
        </Pressable>
        {canManageRecurring ? (
          <Pressable
            className="min-h-[56px] flex-row items-center border-t border-border px-card"
            accessibilityRole="button"
            accessibilityLabel="Open seva approvals"
            onPress={() => navigation.navigate("SevaApprovals")}
          >
            <View className="h-9 w-9 items-center justify-center rounded-pill bg-marigoldSoft">
              <Ionicons
                name="checkmark-circle-outline"
                size={18}
                color={tokens.colors.stone}
              />
            </View>
            <Text className="ml-3 min-w-0 flex-1 font-sans-bold text-base text-stone">
              Seva approvals
            </Text>
            {approvalCount ? (
              <View className="mr-2 min-w-6 items-center rounded-pill bg-vermilion px-2 py-1">
                <Text className="font-sans-bold text-xs text-white">
                  {approvalCount}
                </Text>
              </View>
            ) : null}
            <Ionicons
              name="chevron-forward"
              size={20}
              color={tokens.colors.indigo}
            />
          </Pressable>
        ) : null}
        {canOversee ? (
          <Pressable
            className="min-h-[56px] flex-row items-center border-t border-border px-card"
            accessibilityRole="button"
            accessibilityLabel="Open the completed seva report"
            onPress={() => navigation.navigate("ServiceActivity")}
          >
            <View className="h-9 w-9 items-center justify-center rounded-pill bg-peacockSoft">
              <Ionicons name="analytics-outline" size={18} color={tokens.colors.peacock} />
            </View>
            {/* One name for one screen. This row, the header it pushes and the
                title inside it used to be three different names for the hours
                report, which read as three places completed seva might be. */}
            <Text className="ml-3 min-w-0 flex-1 font-sans-bold text-base text-stone">Completed seva report</Text>
            <Ionicons name="chevron-forward" size={20} color={tokens.colors.indigo} />
          </Pressable>
        ) : null}
        {canManageRecurring ? (
          <Pressable
            className="min-h-[56px] flex-row items-center border-t border-border px-card"
            accessibilityRole="button"
            accessibilityLabel="Manage weekly seva"
            onPress={() => navigation.navigate("RecurringServices")}
          >
            <View className="h-9 w-9 items-center justify-center rounded-pill bg-marigoldSoft">
              <Ionicons
                name="repeat-outline"
                size={18}
                color={tokens.colors.stone}
              />
            </View>
            <Text className="ml-3 min-w-0 flex-1 font-sans-bold text-base text-stone">
              Weekly seva
            </Text>
            <Ionicons
              name="chevron-forward"
              size={20}
              color={tokens.colors.indigo}
            />
          </Pressable>
        ) : null}
        {/* A Volunteer posts seva too, so the inbox opens for anyone with an
            answer waiting on them, not only coordinators. */}
        {canResolveCoverage || postedAttentionCount ? (
          <Pressable
            className="min-h-[56px] flex-row items-center border-t border-border px-card"
            accessibilityRole="button"
            accessibilityLabel="Open coverage inbox"
            onPress={() => navigation.navigate("CoverageInbox")}
          >
            <View className="h-9 w-9 items-center justify-center rounded-pill bg-indigoSoft">
              <Ionicons
                name="people-outline"
                size={18}
                color={tokens.colors.indigo}
              />
            </View>
            <Text className="ml-3 min-w-0 flex-1 font-sans-bold text-base text-stone">
              Coverage inbox
            </Text>
            {coverageInboxCount ? (
              <View className="mr-2 min-w-6 items-center rounded-pill bg-vermilion px-2 py-1">
                <Text className="font-sans-bold text-xs text-white">
                  {coverageInboxCount}
                </Text>
              </View>
            ) : null}
            <Ionicons
              name="chevron-forward"
              size={20}
              color={tokens.colors.indigo}
            />
          </Pressable>
        ) : null}
      </View>

      {dashboardQuery.isLoading ? (
        <View className="mb-section gap-3">
          <Skeleton height={18} width="44%" />
          <SkeletonCard />
          <SkeletonCard />
          <SkeletonCard />
        </View>
      ) : loadFailed ? (
        <View className="mb-section">
          <LoadFailure
            reachable={reachable}
            message={errorMessage(
              dashboardQuery.error,
              "Seva could not be loaded.",
            )}
            onRetry={() => void dashboardQuery.refetch()}
          />
        </View>
      ) : null}

      {actionError ? <FormError message={mutationMessage(actionError)} /> : null}


      {liveRegistrations.length || happeningNow.length ? (
        <>
          <SectionHeader
            title="Seva happening now"
            action="See all"
            onAction={() => navigation.navigate("SevaList", { kind: "happening_now" })}
          />
          {/* The same card as every other list. This strip used to be its own
              shape — a joined band of rows that could not even be opened. */}
          <View className="mb-section gap-3">
            {liveRegistrations.map((row) => (
              <RegisteredSevaCard
                key={row.id}
                registration={row}
                timing="now"
                isMine={row.devotee_id === activeUserId}
                showPeople={canViewCommunity}
                onPress={() =>
                  navigation.navigate("SevaRegistrationDetail", {
                    verificationId: row.id,
                  })
                }
              />
            ))}
            {happeningNow.map((entry) =>
              entry.kind === "one_time" ? (
                <ServiceCard
                  key={`one_time-${entry.id}`}
                  service={entry.service}
                  showMyTag={canViewCommunity}
                  showPeople={canViewCommunity}
                  onPress={() =>
                    navigation.navigate("ServiceDetail", { serviceId: entry.id })
                  }
                />
              ) : (
                <SevaCard
                  key={`weekly-${entry.id}`}
                  name={entry.name}
                  weekly
                  when={`${formatServiceDate(todayKey)} · ${formatServiceTime(entry.template.start_time)}`}
                  minutes={entry.template.duration_minutes}
                  isMine={
                    canViewCommunity &&
                    entry.people.some((person) => person.id === activeUserId)
                  }
                  people={entry.people}
                  showPeople={canViewCommunity}
                  onPress={() =>
                    navigation.navigate("WeeklySevaDetail", {
                      templateId: entry.id,
                    })
                  }
                />
              ),
            )}
          </View>
        </>
      ) : null}

      {dashboard?.pendingOffers.length ? (
        <>
          <SectionHeader title="Someone asked for your help" />
          <View className="mb-section gap-3">
            {dashboard.pendingOffers.map(
              ({ offer, service, offeredByName }) => (
                <View
                  key={offer.id}
                  className="rounded-card border border-marigold bg-white p-card"
                >
                  <View className="flex-row items-start">
                    <View className="h-11 w-11 items-center justify-center rounded-pill bg-marigoldSoft">
                      <Ionicons
                        name="hand-left"
                        size={22}
                        color={tokens.colors.stone}
                      />
                    </View>
                    <View className="ml-3 min-w-0 flex-1">
                      <Text className="font-display text-xl text-stone">
                        {service.name}
                      </Text>
                      {/* A devotee cannot say yes or no without knowing when
                          they are being asked for. */}
                      <View className="mt-1.5 flex-row items-center">
                        <Ionicons
                          name="calendar-outline"
                          size={15}
                          color={tokens.colors.stoneMuted}
                        />
                        <Text className="ml-1.5 font-sans-bold text-sm text-stone">
                          {formatServiceDate(service.date)} ·{" "}
                          {formatServiceTime(service.start_time)}
                        </Text>
                      </View>
                      <View className="mt-1 flex-row items-center">
                        <Ionicons
                          name="time-outline"
                          size={15}
                          color={tokens.colors.stoneMuted}
                        />
                        <Text className="ml-1.5 font-sans text-sm text-stoneMuted">
                          {formatDuration(service.duration_minutes)} ·{" "}
                          {service.filledSlots} of {service.slots_needed} serving
                        </Text>
                      </View>
                      <Text className="mt-1.5 font-sans text-sm leading-5 text-stoneMuted">
                        {offeredByName} is asking if you are available to help.
                      </Text>
                    </View>
                  </View>
                  {/* A devotee who wants to help but cannot make the hour
                      asked for now has somewhere to say so. */}
                  <Pressable
                    className="mt-4 min-h-touch items-center justify-center rounded-button border border-indigo"
                    accessibilityRole="button"
                    accessibilityLabel={`Offer another time for ${service.name}`}
                    onPress={() =>
                      navigation.navigate("ProposeServiceTime", {
                        offerId: offer.id,
                      })
                    }
                  >
                    <Text className="font-sans-bold text-base text-indigo">
                      I am available another time
                    </Text>
                  </Pressable>
                  <View className="mt-3 flex-row gap-3">
                    <Pressable
                      className="min-h-touch flex-1 items-center justify-center rounded-button border border-border"
                      accessibilityRole="button"
                      accessibilityLabel={`Decline ${service.name}`}
                      disabled={respondToOffer.isPending}
                      onPress={() =>
                        respondToOffer.mutate({
                          offerId: offer.id,
                          accept: false,
                        })
                      }
                    >
                      <Text className="font-sans-bold text-base text-stoneMuted">
                        Not available
                      </Text>
                    </Pressable>
                    <Pressable
                      className="min-h-touch flex-1 items-center justify-center rounded-button bg-peacock"
                      accessibilityRole="button"
                      accessibilityLabel={`Accept ${service.name}`}
                      disabled={respondToOffer.isPending}
                      // Warned about a clash first, never stopped by one.
                      onPress={() => acceptOffer(offer.id)}
                    >
                      <Text className="font-sans-bold text-base text-white">
                        Yes, I can help
                      </Text>
                    </Pressable>
                  </View>
                </View>
              ),
            )}
          </View>
        </>
      ) : null}

      {dashboard?.pendingRecurringOffers.length ? (
        <>
          <SectionHeader title="A weekly seva invitation" />
          <View className="mb-section gap-3">
            {dashboard.pendingRecurringOffers.map(
              ({ offer, template, offeredByName, coveragePlan }) => (
                <View
                  key={offer.id}
                  className="rounded-card border border-marigold bg-white p-card"
                >
                  <View className="flex-row items-start">
                    <View className="h-11 w-11 items-center justify-center rounded-pill bg-marigoldSoft">
                      <Ionicons
                        name="repeat"
                        size={22}
                        color={tokens.colors.stone}
                      />
                    </View>
                    <View className="ml-3 min-w-0 flex-1">
                      <Text className="font-display text-xl text-stone">
                        {template.name}
                      </Text>
                      <Text className="mt-1 font-sans text-sm leading-5 text-stoneMuted">
                        {offeredByName} is asking you to help with this weekly seva
                        {coveragePlan
                          ? coveragePlan.scope === "forever"
                            ? ` from ${formatServiceDate(coveragePlan.date_from)} onward.`
                            : coveragePlan.date_to === coveragePlan.date_from
                              ? ` on ${formatServiceDate(coveragePlan.date_from)}.`
                              : ` from ${formatServiceDate(coveragePlan.date_from)} through ${formatServiceDate(coveragePlan.date_to ?? coveragePlan.date_from)}.`
                          : ` every ${formatWeekdayList(template.days_of_week)}.`}
                      </Text>
                    </View>
                  </View>
                  <View className="mt-4 flex-row gap-3">
                    <Pressable
                      className="min-h-touch flex-1 items-center justify-center rounded-button border border-border"
                      accessibilityRole="button"
                      disabled={respondToOffer.isPending || respondToCoverage.isPending}
                      onPress={() =>
                        (offer.offer_kind === "coverage_range" ? respondToCoverage : respondToOffer).mutate({
                          offerId: offer.id,
                          accept: false,
                        })
                      }
                    >
                      <Text className="font-sans-bold text-base text-stoneMuted">
                        Not available
                      </Text>
                    </Pressable>
                    <Pressable
                      className="min-h-touch flex-1 items-center justify-center rounded-button bg-peacock"
                      accessibilityRole="button"
                      accessibilityLabel={
                        offer.offer_kind === "coverage_range"
                          ? `Accept coverage for ${template.name}`
                          : `Accept weekly seva ${template.name}`
                      }
                      disabled={respondToOffer.isPending || respondToCoverage.isPending}
                      // Warned about a standing clash first, never stopped by
                      // one. This is the invitation worth warning about most:
                      // saying yes commits every week, not one morning.
                      onPress={() =>
                        acceptWeeklyOffer(offer.id, offer.offer_kind)
                      }
                    >
                      <Text className="font-sans-bold text-base text-white">
                        {offer.offer_kind === "coverage_range" ? "Accept coverage" : "Accept weekly seva"}
                      </Text>
                    </Pressable>
                  </View>
                  {/* The third answer: neither yes nor no, but a different
                      day and time that does work for this devotee. */}
                  <Pressable
                    className="mt-3 min-h-touch items-center justify-center rounded-button border border-indigo bg-indigoSoft"
                    accessibilityRole="button"
                    // One action, one wording. The tab used to offer "I am
                    // available another time" on a dated invitation and "I am
                    // free at another time" on a weekly one, an inch apart.
                    accessibilityLabel={`Offer another time for ${template.name}`}
                    disabled={respondToOffer.isPending || respondToCoverage.isPending}
                    onPress={() =>
                      navigation.navigate("ProposeAlternative", {
                        offerId: offer.id,
                      })
                    }
                  >
                    <Text className="font-sans-bold text-base text-indigo">
                      I am available another time
                    </Text>
                  </Pressable>
                </View>
              ),
            )}
          </View>
        </>
      ) : null}

      {/* One section, two groups. The temple read "My weekly seva" and "My
          upcoming seva" as two answers to the same question — what am I down
          for — so the two headings became one, with the kinds labelled inside
          it. Weekly first: it is the standing commitment the rest sits around.
          "See all" opens the same two groups in the same order. */}
      {myWeekly.length || myUpcoming.length || myUpcomingRegistered.length ? (
        <>
          <SectionHeader
            title="My upcoming seva"
            action="See all"
            onAction={() => navigation.navigate("SevaList", { kind: "my_upcoming" })}
          />
          <View className="mb-section gap-3">
            {myWeekly.length ? <GroupLabel>Weekly seva</GroupLabel> : null}
            {myWeekly.map((template) => (
              <WeeklySevaCard
                key={template.id}
                template={template}
                roster={rosterFor(template)}
                next={nextWeeklyDate(template)}
                isMine={canViewCommunity}
                showPeople={canViewCommunity}
                onPress={() => navigation.navigate("WeeklySevaDetail", { templateId: template.id })}
              />
            ))}
            {myUpcomingRegistered.length || myUpcoming.length ? (
              <GroupLabel>One-off seva</GroupLabel>
            ) : null}
            {/* A seva this devotee registered is one of their one-off
                commitments, in the same group and the same order as My seva and
                history already shows them. */}
            {myUpcomingRegistered.slice(0, 3).map((row) => (
              <RegisteredSevaCard
                key={row.id}
                registration={row}
                timing="upcoming"
                isMine={canViewCommunity}
                showPeople={canViewCommunity}
                onPress={() =>
                  navigation.navigate("SevaRegistrationDetail", {
                    verificationId: row.id,
                  })
                }
              />
            ))}
            {myUpcoming.slice(0, 3).map((service) => (
              <ServiceCard key={service.id} service={service} showMyTag={canViewCommunity} showPeople={canViewCommunity} onPress={() => navigation.navigate("ServiceDetail", { serviceId: service.id })} />
            ))}
          </View>
        </>
      ) : null}

      {/* The temple's "calendar-look button" on upcoming seva, and it is offered
          to every devotee whether or not they are down for anything: an empty
          week is the answer to "am I free on Thursday" as much as a full one
          is, and `list_seva_schedule` takes a devotee's own id from anybody. */}
      {activeUserId ? (
        <TimetableLink
          label="My seva as a timetable, week by week"
          hint="Opens your own schedule with the times down the side"
          onPress={() =>
            navigation.navigate("Schedule", { devoteeId: activeUserId })
          }
        />
      ) : null}

      {/*
        A section among the sections, not a card at the top. The board is
        already a long scroll and this asks nothing of anybody: two rows, a way
        to see the rest, and a cross for a devotee who would rather not be
        asked.
      */}
      <WeeklySevaAnswerSection
        onSeeAll={() => navigation.navigate("WeeklySevaAnswers")}
      />

      {weeklyOpenings.length ? (
        <>
          <SectionHeader
            title="Open weekly seva"
            action="See all"
            onAction={() => navigation.navigate("SevaList", { kind: "open_requirements" })}
          />
          <View className="mb-section gap-3">
            {weeklyOpenings.slice(0, 3).map((template) => (
              <WeeklySevaCard
                key={template.id}
                template={template}
                roster={rosterFor(template)}
                showPeople={canViewCommunity}
                onPress={() => navigation.navigate("WeeklySevaDetail", { templateId: template.id })}
              />
            ))}
          </View>
        </>
      ) : null}

      <SectionHeader
        title="Open seva requests"
        action="See all"
        onAction={() => navigation.navigate("SevaList", { kind: "open_requirements" })}
      />
      {oneTimeOpenings.length ? (
        <View className="mb-section gap-3">
          {oneTimeOpenings.slice(0, 3).map((service) => (
            <ServiceCard
              key={service.id}
              service={service}
              // The same answer as every other section gives. This was the one
              // call site left on the default, so the duplicate down here wore
              // a "My seva" pill the card it duplicated did not.
              showMyTag={canViewCommunity}
              showPeople={canViewCommunity}
              onPress={() =>
                navigation.navigate("ServiceDetail", { serviceId: service.id })
              }
            />
          ))}
        </View>
      ) : dashboard ? (
        <View className="mb-section items-center rounded-card border border-border bg-white px-card py-6">
          <Ionicons
            name="leaf-outline"
            size={25}
            color={tokens.colors.peacock}
          />
          {/* Worded so its emptiness claims nothing. It used to say "All
              current needs are covered", which is a promise — and a section
              that promises may not be thinned, so a request the reader had
              already joined had to stay here and be named twice. Saying
              "nothing else" instead is what lets the rule reach this far down
              the screen, exactly as it does for the community schedule. */}
          <Text className="mt-3 font-sans-bold text-base text-stone">
            Nothing else needs help right now
          </Text>
          <Text className="mt-1 text-center font-sans text-sm text-stoneMuted">
            Seva you have already joined is above. New requests appear here for
            everyone.
          </Text>
        </View>
      ) : null}

      {/* Today at a glance. The section stays even on an empty day, because
          "See all" is how a coordinator reaches any other date. */}
      {canViewCommunity ? (
        <>
          <SectionHeader
            title="Community schedule"
            subtitle={formatChicagoDate(now)}
            action="See all"
            onAction={() => navigation.navigate("SevaList", { kind: "community_schedule" })}
          />
          {/* Weekly and dated seva together — one schedule, not two. The dated
              rows are both kinds in one chronological run; the roster cards
              after them are the weekly seva today with no row generated yet. */}
          <View className="mb-section gap-3">
            {todaysSchedule.length ||
            todaysWeekly.length ||
            otherRegisteredToday.length ? (
              <>
                {todaysWeekly.slice(0, scheduleShownWeekly).map((template) => (
                  <WeeklySevaCard
                    key={template.id}
                    template={template}
                    roster={rosterFor(template)}
                    next={formatServiceDate(todayKey)}
                    showPeople={canViewCommunity}
                    onPress={() => navigation.navigate("WeeklySevaDetail", { templateId: template.id })}
                  />
                ))}
                {todaysSchedule
                  .slice(0, scheduleShownDated)
                  .map((service) => (
                    <ServiceCard key={service.id} service={service} showMyTag={canViewCommunity} showPeople={canViewCommunity} onPress={() => navigation.navigate("ServiceDetail", { serviceId: service.id })} />
                  ))}
                {/* Another devotee's registered seva today. It is part of the
                    temple's day, and this is the only section that claims to
                    describe the temple's day — it used to sit under an
                    "Upcoming seva" heading of its own, which for a plain
                    devotee was their own seva announced a second time. */}
                {otherRegisteredToday
                  .slice(0, scheduleRoomLeft)
                  .map((row) => (
                    <RegisteredSevaCard
                      key={row.id}
                      registration={row}
                      timing="upcoming"
                      isMine={false}
                      showPeople={canViewCommunity}
                      onPress={() =>
                        navigation.navigate("SevaRegistrationDetail", {
                          verificationId: row.id,
                        })
                      }
                    />
                  ))}
              </>
            ) : dashboard ? (
              <View className="rounded-card border border-border bg-white px-card py-6">
                <Text className="text-center font-sans text-base text-stoneMuted">
                  Nothing else is scheduled today.
                </Text>
                <Text className="mt-1 text-center font-sans text-sm text-stoneMuted">
                  Tap See all for another day or a whole week.
                </Text>
              </View>
            ) : null}
          </View>
          {/* The same schedule as a week rather than a day: every devotee's
              seva laid out against the clock, which is what the temple asked
              the community schedule to become. The server gates it on the same
              three roles this section is already gated on. */}
          <TimetableLink
            label="The whole week as a timetable"
            hint="Everyone’s seva, hour by hour, with the temple programme behind it"
            onPress={() => navigation.navigate("Schedule")}
          />
        </>
      ) : null}

      {/* Seva that has happened but is not confirmed: finished requests waiting
          for whoever posted them, and registrations waiting for the member the
          devotee named. Both are the same question — did this happen? */}
      {awaitingClose.length || myPendingVerifications.length ? (
        <>
          <SectionHeader
            title="Waiting to be verified"
            subtitle="These are over. Marking who served moves them into history."
            action="See all"
            onAction={() => navigation.navigate("SevaList", { kind: "awaiting_close" })}
          />
          <View className="mb-section gap-3">
            {awaitingClose.slice(0, 3).map((service) => (
              <SevaCard
                key={service.id}
                name={service.name}
                weekly={Boolean(service.template_id)}
                when={whenLine(service)}
                minutes={service.duration_minutes}
                isMine={canViewCommunity && Boolean(service.currentUserAssignment)}
                // These are over, so the row is a claim about who served — a
                // devotee already marked absent must not be among them.
                people={servedDevotees(service)}
                showPeople={canViewCommunity}
                peopleEmptyLabel="Nobody served this"
                action={
                  canConfirmSeva(service)
                    ? {
                        label: "Mark served",
                        accessibilityLabel: `Mark ${service.name} served`,
                        disabled: markServed.isPending,
                        onPress: () => markServed.mutate(service),
                      }
                    : undefined
                }
                onPress={() => navigation.navigate("ServiceDetail", { serviceId: service.id })}
              />
            ))}
            {myPendingVerifications.slice(0, 3).map((row) => (
              <RegisteredSevaCard
                key={row.id}
                registration={row}
                timing={sevaTiming(row, now)}
                isMine={canViewCommunity}
                showPeople={canViewCommunity}
                onPress={() =>
                  navigation.navigate("SevaRegistrationDetail", {
                    verificationId: row.id,
                  })
                }
              />
            ))}
          </View>
        </>
      ) : null}

      {canViewCommunity && history.length ? (
        <>
          <SectionHeader
            title="Recently completed"
            action="See all"
            onAction={() => navigation.navigate("SevaList", { kind: "completed" })}
          />
          <View className="mb-section gap-3">
            {history.slice(0, 3).map((row) => (
              <View key={row.key}>{row.node}</View>
            ))}
          </View>
        </>
      ) : null}

      {!canViewCommunity && (myCompleted.length || completedRegistered.length) ? (
        <>
          <SectionHeader
            title="Your completed seva"
            action="See all"
            onAction={() => navigation.navigate("SevaList", { kind: "my_seva" })}
          />
          <View className="mb-section gap-3">
            {completedRegistered.slice(0, 3).map((row) => (
              <RegisteredSevaCard
                key={row.id}
                registration={row}
                timing="finished"
                isMine={false}
                onPress={() =>
                  navigation.navigate("SevaRegistrationDetail", {
                    verificationId: row.id,
                  })
                }
              />
            ))}
            {myCompleted.slice(0, 3).map((entry) =>
              entry.kind === "one_time" ? (
                <ServiceCard
                  key={entry.key}
                  service={entry.service}
                  showMyTag={false}
                  onPress={() =>
                    navigation.navigate("ServiceDetail", {
                      serviceId: entry.service.id,
                    })
                  }
                />
              ) : (
                <SevaCard
                  key={entry.key}
                  name={entry.name}
                  weekly
                  when={whenLine(entry.latest)}
                  minutes={entry.latest.duration_minutes}
                  onPress={() =>
                    navigation.navigate("WeeklySevaDetail", {
                      templateId: entry.templateId,
                    })
                  }
                />
              ),
            )}
          </View>
        </>
      ) : null}

      {/* Last on the tab and quiet on purpose. A seva nobody served is a
          handful of rows a year and belongs where its poster will find it
          rather than at the top of everybody's morning. */}
      <ClosedUnservedNotice seva={closedUnserved.data ?? []} />

      {/* One sheet for both kinds of invitation. What it proceeds with and
          where "another time" goes are the only things that differ, and both
          are read off the invitation the prompt belongs to. */}
      <ClashWarningSheet
        visible={Boolean(clashPrompt)}
        title={clashWarningTitle(promptWording)}
        message={clashWarningMessage(promptWording, promptClashes)}
        proceedLabel="Accept anyway"
        onProceed={() => {
          const offerId = clashPrompt;
          const kind = promptWeekly?.offer.offer_kind;
          setClashPrompt(null);
          if (!offerId) return;
          if (promptWeekly) {
            weeklyResponder(kind).mutate({ offerId, accept: true });
          } else {
            respondToOffer.mutate({ offerId, accept: true });
          }
        }}
        onClose={() => setClashPrompt(null)}
        alternative={{
          label: "I am available another time",
          onPress: () => {
            const offerId = clashPrompt;
            const weekly = Boolean(promptWeekly);
            setClashPrompt(null);
            if (!offerId) return;
            navigation.navigate(
              weekly ? "ProposeAlternative" : "ProposeServiceTime",
              { offerId },
            );
          },
        }}
      />
    </Screen>
  );
}
