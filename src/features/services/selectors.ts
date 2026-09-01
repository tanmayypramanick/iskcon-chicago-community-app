import {
  addChicagoDays,
  getChicagoDateKey,
  getChicagoMinutesOfDay,
  getChicagoWeekday,
} from "../../lib/chicagoDate";
import { hasServiceFinished, isUpcomingService } from "./format";
import type {
  ServiceAssignmentRow,
  ServiceDashboard,
  ServiceDevotee,
  ServiceListItem,
  ServiceParticipant,
} from "./types";

export type WeeklySeva = ServiceDashboard["recurringTemplates"][number];

/**
 * The assignment states that mean a devotee is really on this seva.
 *
 * A swap does not edit the original devotee's place, it retires it: 0009 sets
 * their assignment to `withdrawn` and gives the substitute a new one. So a
 * status outside this set is a place somebody used to hold, and naming its
 * devotee is how the temple ended up being told Arpita was still serving a seva
 * Tanmay had taken over.
 */
const LIVE_ASSIGNMENT_STATUSES = new Set<ServiceAssignmentRow["status"]>([
  "assigned",
  "confirmed",
  "completed",
]);

export function isLiveAssignment(assignment: ServiceAssignmentRow) {
  return LIVE_ASSIGNMENT_STATUSES.has(assignment.status);
}

/**
 * Who is serving a seva — and the only way the app should ask.
 *
 * One helper rather than a filter at each call site: a card, a strip or a
 * history row that reads `service.participants` straight is one forgotten
 * condition away from bringing the swapped-devotee bug back, and there are a
 * dozen such places.
 */
export function servingParticipants(
  service: ServiceListItem,
): ServiceParticipant[] {
  return service.participants.filter((participant) =>
    isLiveAssignment(participant.assignment),
  );
}

/** The devotees serving a seva, for an avatar stack or a list of names. */
export function servingDevotees(service: ServiceListItem): ServiceDevotee[] {
  return servingParticipants(service).map((participant) => participant.devotee);
}

/**
 * Whether one devotee really holds a place on this seva right now.
 *
 * The participant list decides whenever there is one. api.ts builds it and
 * `currentUserAssignment` from the same live rows, so consulting both can only
 * ever surface a disagreement — and the disagreement that bites is a place the
 * devotee gave away still answering "yes", which is the swapped-seva bug.
 * `currentUserAssignment` is the fallback for the one case the list cannot
 * answer: a seva whose roster was never loaded.
 */
export function isServingOn(service: ServiceListItem, userId: string) {
  if (service.participants) {
    return servingParticipants(service).some(
      (participant) => participant.devotee.id === userId,
    );
  }
  const mine = service.currentUserAssignment;
  return Boolean(mine && mine.devotee_id === userId && isLiveAssignment(mine));
}

/**
 * The declines and suggested times this account may actually answer.
 *
 * `respond_to_service_offer_counter` accepts the devotee who posted the seva or
 * a holder of `app.view_all`, and nothing else — a Community Head has
 * `services.resolve_coverage` and is still refused. So the rule is exactly
 * those two, and it is applied here because the dashboard is assembled from a
 * user id with no role attached.
 */
export function sevaNeedingMyAnswer(
  dashboard: ServiceDashboard,
  userId: string | null,
  /** `app.view_all` — a Tech Admin or the President, nobody else. */
  canAnswerAnySeva: boolean,
) {
  return (dashboard.sevaNeedingAnswer ?? []).filter(
    (item) => canAnswerAnySeva || item.service.posted_by === userId,
  );
}

/** Earliest first, by the temple's clock. */
function byWhenAscending(left: ServiceListItem, right: ServiceListItem) {
  return `${left.date}${left.start_time}`.localeCompare(
    `${right.date}${right.start_time}`,
  );
}

export function weeklyOccurrences(
  dashboard: ServiceDashboard,
  templateId: string,
) {
  return dashboard.services.filter(
    (service) => service.template_id === templateId,
  );
}

export type WeeklyAssignee = WeeklySeva["assignees"][number];

/**
 * Who is on a weekly seva at this moment, in the same shape as the template's
 * own roster so any card or list can be handed this instead.
 *
 * `template.assignees` is the standing arrangement, and an accepted coverage
 * plan deliberately does not edit it unless the swap is forever — 0009 keeps
 * the original's row so the seva returns to them when the plan runs out. That
 * makes the raw roster the wrong answer to "who is serving this", and it is how
 * the temple kept being shown a devotee somebody else had covered for.
 *
 * Only plans actually in force today are applied. A swap that starts next month
 * has not happened yet, and naming the substitute now would be the same mistake
 * pointing the other way.
 */
export function weeklyRoster(
  dashboard: ServiceDashboard,
  template: WeeklySeva,
  now = new Date(),
): WeeklyAssignee[] {
  const todayKey = getChicagoDateKey(now);
  const inForce = dashboard.coveragePlans.filter(
    (plan) =>
      plan.service_template_id === template.id &&
      plan.status === "accepted" &&
      plan.date_from <= todayKey &&
      (plan.date_to === null || todayKey <= plan.date_to),
  );
  if (!inForce.length) return template.assignees;

  const devoteeById = new Map(
    dashboard.devotees.map((devotee) => [devotee.id, devotee]),
  );
  const daysById = new Map<string, Set<number>>();
  const personById = new Map<string, ServiceDevotee>();
  for (const assignee of template.assignees) {
    daysById.set(assignee.id, new Set(assignee.assignedDays));
    personById.set(assignee.id, assignee);
  }

  for (const plan of inForce) {
    const steppedAside = daysById.get(plan.original_devotee_id);
    for (const day of plan.days_of_week) steppedAside?.delete(day);

    const substitute =
      personById.get(plan.substitute_devotee_id) ??
      devoteeById.get(plan.substitute_devotee_id);
    // A substitute the devotee directory does not carry cannot be named, and
    // silently leaving the original in their place is the bug. Drop the day.
    if (!substitute) continue;
    personById.set(plan.substitute_devotee_id, substitute);
    const taken = daysById.get(plan.substitute_devotee_id) ?? new Set<number>();
    for (const day of plan.days_of_week) taken.add(day);
    daysById.set(plan.substitute_devotee_id, taken);
  }

  return [...daysById.entries()].flatMap(([id, assignedDays]) => {
    const devotee = personById.get(id);
    if (!devotee || !assignedDays.size) return [];
    return [
      { ...devotee, assignedDays: [...assignedDays].sort((a, b) => a - b) },
    ];
  });
}

export function hasWeeklyOpening(
  template: WeeklySeva,
  /** Defaults to the standing roster; pass `weeklyRoster` to respect swaps. */
  roster: WeeklyAssignee[] = template.assignees,
) {
  if (!template.active || template.participation_mode !== "open") return false;
  return template.days_of_week.some(
    (day) =>
      roster.filter((assignee) => assignee.assignedDays.includes(day)).length <
      template.slots_needed,
  );
}

export function hasPendingWeeklyCoverage(
  dashboard: ServiceDashboard,
  templateId: string,
) {
  return dashboard.coverageRequests.some(
    ({ exceptions, service }) =>
      service.template_id === templateId &&
      exceptions.some((exception) => exception.status === "pending"),
  );
}

export function hasBroadcastWeeklyOpening(
  dashboard: ServiceDashboard,
  templateId: string,
) {
  return dashboard.coverageRequests.some(
    ({ exceptions, service }) =>
      service.template_id === templateId &&
      exceptions.some(
        (exception) =>
          exception.status === "pending" &&
          exception.resolution_kind === "broadcast",
      ),
  );
}

export function broadcastWeeklyOccurrenceCount(
  dashboard: ServiceDashboard,
  templateId: string,
) {
  return new Set(
    dashboard.coverageRequests.flatMap(({ exceptions, service }) =>
      service.template_id === templateId
        ? exceptions
            .filter(
              (exception) =>
                exception.status === "pending" &&
                exception.resolution_kind === "broadcast",
            )
            .map((exception) => exception.service_instance_id)
        : [],
    ),
  ).size;
}

export function myWeeklySeva(
  dashboard: ServiceDashboard,
  userId: string,
  now = new Date(),
) {
  return dashboard.recurringTemplates.filter((template) => {
    // Both rosters, on purpose. The standing one keeps a devotee's own weekly
    // seva in front of them while somebody covers a month of it — it is still
    // theirs, and it comes back. The coverage-aware one is what puts the
    // substitute here for as long as they are the one turning up.
    if (template.assignees.some((assignee) => assignee.id === userId)) {
      return true;
    }
    if (
      weeklyRoster(dashboard, template, now).some(
        (assignee) => assignee.id === userId,
      )
    ) {
      return true;
    }
    // A swap arranged occurrence by occurrence leaves no plan in force today,
    // so the generated rows are the only evidence it is theirs.
    return weeklyOccurrences(dashboard, template.id).some(
      (service) =>
        isUpcomingService(service.date, now) && isServingOn(service, userId),
    );
  });
}

export function openWeeklySeva(
  dashboard: ServiceDashboard,
  now = new Date(),
) {
  return dashboard.recurringTemplates.filter(
    (template) =>
      hasWeeklyOpening(template, weeklyRoster(dashboard, template, now)) ||
      hasBroadcastWeeklyOpening(dashboard, template.id),
  );
}

export function communityWeeklySeva(
  dashboard: ServiceDashboard,
  now = new Date(),
) {
  return dashboard.recurringTemplates.filter(
    (template) =>
      template.active &&
      !hasWeeklyOpening(template, weeklyRoster(dashboard, template, now)) &&
      !hasPendingWeeklyCoverage(dashboard, template.id),
  );
}

/**
 * Seva still to come, of every kind. The end instant decides, not the date: an
 * 11:00 AM seva that runs an hour has finished by the afternoon, and calling it
 * upcoming tells a devotee they still have somewhere to be.
 *
 * A weekly occurrence belongs here as much as a dated request does. It is a row
 * with a date, an hour and devotees on it, and the devotee serving it — often a
 * substitute who never appears on the roster — has somewhere to be that day.
 */
export function upcomingServices(
  dashboard: ServiceDashboard,
  now = new Date(),
) {
  return dashboard.services.filter(
    (service) =>
      isUpcomingService(service.date, now) &&
      !["completed", "cancelled"].includes(service.status) &&
      !hasServiceFinished(service, now),
  );
}

/** Only the dated one-offs: open requests and the community schedule. */
export function upcomingOneTimeServices(
  dashboard: ServiceDashboard,
  now = new Date(),
) {
  return upcomingServices(dashboard, now).filter(
    (service) => service.template_id === null,
  );
}

/** Dated seva that is over but has not been closed off, of any kind. */
function finishedButOpenServices(
  dashboard: ServiceDashboard,
  now = new Date(),
) {
  return dashboard.services.filter(
    (service) =>
      service.template_id === null &&
      !["completed", "cancelled"].includes(service.status) &&
      hasServiceFinished(service, now),
  );
}

/**
 * Whether somebody has said what happened to one devotee's place on a seva.
 * Only attendance answers it. A place that was withdrawn or marked a no-show
 * needs no answer either, but those have already left `servingParticipants`,
 * so this is only ever asked of a live place.
 *
 * The verification level (self report, QR, member verified) is deliberately
 * not read here. It gates points, not hours, and no one can raise it from a
 * list — gating a list on it would strand seva in a queue nobody can clear.
 */
function isAttendanceAnswered(assignment: ServiceAssignmentRow) {
  return (
    assignment.attendance === "served" ||
    assignment.attendance === "absent" ||
    assignment.attendance === "excused"
  );
}

/**
 * The places on a seva nobody has said served, absent or excused yet — one id
 * per devotee, because attendance is recorded per place, not per seva.
 */
export function unconfirmedAssignmentIds(service: ServiceListItem) {
  return servingParticipants(service)
    .filter((participant) => !isAttendanceAnswered(participant.assignment))
    .map((participant) => participant.assignment.id);
}

/**
 * Whether a finished seva is settled — marked completed, and with nobody still
 * owed an answer about who actually served.
 *
 * 0059 draws the line: a weekly occurrence earns its place on completion and
 * needs no confirmation, so it settles the moment it is closed out. A one-off
 * seva needs somebody to say who served, which is what the temple asked for.
 * A seva nobody was on has nobody to confirm, so it settles too.
 */
export function isSevaConfirmedServed(service: ServiceListItem) {
  if (service.status !== "completed") return false;
  if (service.template_id !== null) return true;
  return servingParticipants(service).every((participant) =>
    isAttendanceAnswered(participant.assignment),
  );
}

/**
 * An open request whose time has passed. Nobody owns it, so there is nobody to
 * confirm it — it simply lapses into history, whether it was taken up or not.
 */
export function lapsedOpenRequests(
  dashboard: ServiceDashboard,
  now = new Date(),
) {
  return finishedButOpenServices(dashboard, now).filter(
    (service) => service.participation_mode === "open",
  );
}

/**
 * "Waiting to be verified": dated seva that has happened and is still owed an
 * answer. Two shapes of the same question — did this happen, and who served?
 *
 *  - it was never closed off, so it waits on "Complete entire service";
 *  - it was closed off, but nobody has said who served, so it waits on the
 *    attendance mark. The temple asked for this one explicitly: unconfirmed
 *    seva is not history yet.
 *
 * Weekly occurrences are never here. 0059 gives them their points on
 * completion with nothing further owed, and a roster slot carries no poster,
 * so parking one here would strand it in a list nobody can clear.
 */
export function awaitingCompletionServices(
  dashboard: ServiceDashboard,
  now = new Date(),
) {
  return dashboard.services
    .filter(
      (service) =>
        service.template_id === null &&
        service.status !== "cancelled" &&
        hasServiceFinished(service, now) &&
        (service.status === "completed"
          ? !isSevaConfirmedServed(service)
          : // Nobody owns an open request, so there is nobody to ask; it
            // simply lapses into history.
            service.participation_mode !== "open"),
    )
    .sort((left, right) =>
      `${right.date}${right.start_time}`.localeCompare(
        `${left.date}${left.start_time}`,
      ),
    );
}

/**
 * "My upcoming seva": everything this devotee has been assigned or has accepted
 * and has not yet served, soonest first.
 *
 * Deliberately not restricted to one-off requests. A weekly occurrence is a
 * commitment on a particular day, and a devotee covering somebody else's
 * Thursdays holds nothing but occurrences — the roster still names the devotee
 * they stepped in for. Listing only one-off seva left both of them looking at a
 * tab that never mentioned the seva they were actually turning up for.
 */
export function myUpcomingSeva(
  dashboard: ServiceDashboard,
  userId: string,
  now = new Date(),
) {
  return upcomingServices(dashboard, now)
    .filter((service) => isServingOn(service, userId))
    .sort(byWhenAscending);
}

/**
 * The next date a devotee is actually down to serve one weekly seva.
 *
 * This is the fact a roster card was missing. "Every Monday, Thursday and
 * Saturday" says what the commitment is but not when it next falls, so the tab
 * used to answer that by listing the seva a second time as a dated card — the
 * same name twice, a screen-inch apart. One card carrying both facts is what
 * the temple keeps asking for.
 *
 * Occurrences decide, not the roster: a substitute holds nothing but generated
 * rows, and the devotee whose days are covered has none for that stretch even
 * though the seva is still theirs. Either can therefore be null, which reads as
 * "nothing on your calendar yet" rather than as a wrong date.
 */
export function myNextWeeklyOccurrence(
  dashboard: ServiceDashboard,
  userId: string,
  templateId: string,
  now = new Date(),
): ServiceListItem | null {
  return (
    myUpcomingSeva(dashboard, userId, now).find(
      (service) => service.template_id === templateId,
    ) ?? null
  );
}

/**
 * "My upcoming seva" as the Seva tab shows it: every dated commitment that is
 * not already a card in "My weekly seva" above.
 *
 * A weekly seva with a roster card of its own is named there, next date and
 * all, so repeating it here put the same seva on the screen twice. But a
 * covered occurrence can outlive its card: `can_view_service_template` does not
 * grant a substitute the template row — accepting coverage does not make them a
 * roster assignee — so a devotee covering a month of Thursdays may hold the
 * occurrences and not the seva they belong to. Dropping every weekly row would
 * empty the one section that told them where to be.
 *
 * Whatever survives is still capped to the next date per seva, so an invisible
 * template cannot fill the section either.
 */
export function myOtherUpcomingSeva(
  dashboard: ServiceDashboard,
  userId: string,
  /** Template ids already shown as their own card. */
  weeklyAlreadyShown: Set<string>,
  now = new Date(),
) {
  const seenTemplates = new Set<string>();
  return myUpcomingSeva(dashboard, userId, now).filter((service) => {
    if (service.template_id === null) return true;
    if (weeklyAlreadyShown.has(service.template_id)) return false;
    if (seenTemplates.has(service.template_id)) return false;
    seenTemplates.add(service.template_id);
    return true;
  });
}

export function myUpcomingOneTime(
  dashboard: ServiceDashboard,
  userId: string,
  now = new Date(),
) {
  return myUpcomingSeva(dashboard, userId, now).filter(
    (service) => service.template_id === null,
  );
}

/**
 * Open requests with a place still going. A partly-filled one stays here — one
 * devotee joining a seva that needs three does not mean the other two places
 * have been found.
 */
export function openOneTimeRequirements(
  dashboard: ServiceDashboard,
  now = new Date(),
) {
  return upcomingOneTimeServices(dashboard, now).filter(
    (service) =>
      service.participation_mode === "open" &&
      service.status !== "full" &&
      service.filledSlots < service.slots_needed,
  );
}

/**
 * Everything on the temple's calendar for one day. The Seva screen shows today
 * at a glance; the full list is where a range is chosen.
 */
export function communityScheduleForDay(
  dashboard: ServiceDashboard,
  dateKey: string,
  now = new Date(),
) {
  return communitySchedule(dashboard, now).filter(
    (service) => service.date === dateKey,
  );
}

/**
 * The temple's dated seva still to come, of both kinds, in one chronological
 * list.
 *
 * Weekly occurrences belong here as much as one-off requests do. The temple
 * asked for a community schedule and was given half of one: the weekly seva sat
 * above as undated roster cards while the schedule itself listed only dated
 * requests, so a coordinator reading Thursday could not see that the kitchen is
 * covered every Thursday morning. An occurrence is a row with a date, an hour
 * and devotees on it, which is precisely what a schedule is made of.
 *
 * Only upcoming: anything finished has either lapsed into history or is waiting
 * to be closed off, and both of those are listed elsewhere.
 */
export function communitySchedule(
  dashboard: ServiceDashboard,
  now = new Date(),
) {
  return upcomingServices(dashboard, now)
    .filter(
      (service) =>
        // A weekly occurrence is the temple's own standing seva; it is planned
        // whoever ends up on it. An open request nobody has joined is still
        // just a request — once somebody is on it, it is also something the
        // temple has planned, so it appears in both places until it is full.
        service.template_id !== null ||
        service.participation_mode !== "open" ||
        service.filledSlots > 0,
    )
    .sort(byWhenAscending);
}

function minutesFromTime(time: string) {
  const [hour, minute] = time.split(":").map(Number);
  return hour * 60 + minute;
}

/**
 * Whether a seva scheduled for TODAY is running right now.
 *
 * Deliberately split from the past-midnight case below. A single wrapping test
 * — `now >= start || now < end - 1440` — cannot tell "the 23:00 seva that
 * started last night and is still going" from "the 23:00 seva that starts
 * tonight", because both are the same clock times. Paired with a `date ===
 * today` filter it answered yes to the second: a 23:00-01:00 seva was
 * announced as in progress at 00:30, twenty-two hours early, and then hidden
 * after midnight on the night it actually ran.
 */
function isRunningOnItsOwnDay(
  startTime: string,
  durationMinutes: number,
  nowMinutes: number,
) {
  const start = minutesFromTime(startTime);
  const end = Math.min(start + durationMinutes, 24 * 60);
  return nowMinutes >= start && nowMinutes < end;
}

/** Whether a seva that began YESTERDAY is still running after midnight. */
function isRunningFromPreviousDay(
  startTime: string,
  durationMinutes: number,
  nowMinutes: number,
) {
  const end = minutesFromTime(startTime) + durationMinutes;
  if (end <= 24 * 60) return false;
  return nowMinutes < end - 24 * 60;
}

export type HappeningNowEntry =
  | { kind: "one_time"; id: string; name: string; people: ServiceDashboard["devotees"]; service: ServiceListItem }
  | {
      kind: "weekly";
      id: string;
      name: string;
      people: ServiceDashboard["devotees"];
      template: WeeklySeva;
    };

/**
 * Who is really rostered on a weekly seva for one particular day.
 *
 * The standing roster is not the answer on its own. An accepted coverage plan
 * hands a devotee's days to a substitute for a stretch of dates and — unless
 * the swap is forever — leaves the roster untouched, which is exactly the
 * month-long swap the temple reported: the roster still said Arpita while
 * Tanmay was the one turning up. Where a generated occurrence exists its
 * assignments are the truth and this is not consulted; this covers the days
 * whose row has not been generated yet.
 */
export function weeklyServingOn(
  dashboard: ServiceDashboard,
  template: WeeklySeva,
  dateKey: string,
  weekday: number,
): ServiceDevotee[] {
  const covering = dashboard.coveragePlans.filter(
    (plan) =>
      plan.service_template_id === template.id &&
      plan.status === "accepted" &&
      plan.days_of_week.includes(weekday) &&
      plan.date_from <= dateKey &&
      (plan.date_to === null || dateKey <= plan.date_to),
  );
  const steppedAside = new Set(covering.map((plan) => plan.original_devotee_id));
  const serving = template.assignees.filter(
    (assignee) =>
      assignee.assignedDays.includes(weekday) && !steppedAside.has(assignee.id),
  );

  const devoteeById = new Map(
    dashboard.devotees.map((devotee) => [devotee.id, devotee]),
  );
  const seen = new Set(serving.map((person) => person.id));
  const substitutes = covering.flatMap((plan) => {
    if (seen.has(plan.substitute_devotee_id)) return [];
    seen.add(plan.substitute_devotee_id);
    const devotee = devoteeById.get(plan.substitute_devotee_id);
    return devotee ? [devotee] : [];
  });
  return [...serving, ...substitutes];
}

export type HappeningNowScope = {
  userId: string | null;
  /** Community Head, Tech Admin and President see the whole temple. */
  seesEveryone: boolean;
  /** A Volunteer also sees the seva requests they posted. */
  seesOwnPosts: boolean;
  /**
   * Instances created by verifying a registration. They are already presented
   * as registration cards, so including them here would show the seva twice.
   */
  excludeInstanceIds?: Set<string>;
};

/**
 * Everything actually being served at this moment in Chicago: seva waiting to
 * be verified, and any dated or weekly seva whose window contains now with at
 * least one devotee on it.
 *
 * Scope is deliberate. A Devotee sees only their own; a Volunteer sees their
 * own plus what they posted; Community Head, Tech Admin and President see the
 * whole temple.
 */
export function sevaHappeningNow(
  dashboard: ServiceDashboard,
  scope: HappeningNowScope,
  now = new Date(),
): HappeningNowEntry[] {
  const nowMinutes = getChicagoMinutesOfDay(now);
  const weekday = getChicagoWeekday(now);
  const todayKey = getChicagoDateKey(now);
  // Just after midnight, the seva actually in progress belongs to yesterday.
  // The weekday is stepped rather than re-derived, so it cannot disagree with
  // `weekday` across a DST boundary.
  const yesterdayKey = addChicagoDays(-1, now);
  const yesterdayWeekday = (weekday + 6) % 7;

  const oneTime: HappeningNowEntry[] = dashboard.services.flatMap((service) => {
    if (["cancelled", "completed"].includes(service.status)) return [];
    const running =
      service.date === todayKey
        ? isRunningOnItsOwnDay(
            service.start_time,
            service.duration_minutes,
            nowMinutes,
          )
        : service.date === yesterdayKey &&
          isRunningFromPreviousDay(
            service.start_time,
            service.duration_minutes,
            nowMinutes,
          );
    if (!running) return [];
    // Attendance can be marked while a seva runs — whoever is running it marks
    // people in as they arrive — so a devotee already recorded absent is not
    // one of the people serving it now. A seva everybody was marked absent for
    // leaves nobody, and drops off "happening now" rather than claiming a room
    // full of devotees who are not there.
    const people = servedDevotees(service);
    if (!people.length) return [];
    return [
      { kind: "one_time" as const, id: service.id, name: service.name, people, service },
    ];
  });

  // A weekly occurrence that already exists as an instance is covered above;
  // this catches standing assignees on templates with no generated row yet.
  const coveredTemplateIds = new Set(
    dashboard.services
      .filter((service) => service.date === todayKey && service.template_id)
      .map((service) => service.template_id),
  );
  const weekly: HappeningNowEntry[] = dashboard.recurringTemplates.flatMap(
    (template) => {
      if (!template.active || coveredTemplateIds.has(template.id)) return [];
      // Same two cases as the one-time branch: a template running on its own
      // weekday, or one that started on yesterday's weekday and crossed
      // midnight. Testing only today's weekday made a Sunday 23:00 template
      // read as live at 00:30 on Sunday morning.
      const running =
        (template.days_of_week.includes(weekday) &&
          isRunningOnItsOwnDay(
            template.start_time,
            template.duration_minutes,
            nowMinutes,
          )) ||
        (template.days_of_week.includes(yesterdayWeekday) &&
          isRunningFromPreviousDay(
            template.start_time,
            template.duration_minutes,
            nowMinutes,
          ));
      if (!running) return [];
      const people = weeklyServingOn(dashboard, template, todayKey, weekday);
      if (!people.length) return [];
      return [
        { kind: "weekly" as const, id: template.id, name: template.name, people, template },
      ];
    },
  );

  const excluded = scope.excludeInstanceIds;
  const all = [...oneTime, ...weekly].filter(
    (entry) => entry.kind !== "one_time" || !excluded?.has(entry.id),
  );
  if (scope.seesEveryone) return all;

  return all.filter((entry) => {
    if (scope.userId && entry.people.some((person) => person.id === scope.userId)) {
      return true;
    }
    if (!scope.seesOwnPosts) return false;
    if (entry.kind === "one_time") return entry.service.posted_by === scope.userId;
    if (entry.kind === "weekly") return entry.template.created_by === scope.userId;
    return false;
  });
}

/**
 * Whether one live place counts as seva actually offered.
 *
 * `seva_points_status` is the temple's rule and it is unambiguous: an
 * assignment marked `absent` or `excused` is `not_served`, whatever the
 * assignment's own status says. A place nobody has answered for yet still
 * counts — an unmarked weekly occurrence the hourly sweep closed is the
 * ordinary case, and the same rule counts it.
 */
function countsAsService(assignment: ServiceAssignmentRow) {
  return (
    assignment.attendance !== "absent" && assignment.attendance !== "excused"
  );
}

/**
 * The devotees who really served a seva — live places, minus everyone somebody
 * marked absent or excused.
 *
 * This is the list to draw wherever the app says who served: a card's avatar
 * row, a "+N" count, a detail screen, a See-all row. `servingParticipants` is
 * the wrong answer there, because it only retires the places people gave away
 * and still names the devotee who was rostered and never turned up — which is
 * the temple being told somebody offered a morning they were marked absent for.
 *
 * On an upcoming seva the two are the same list: nobody has been marked yet.
 */
export function servedParticipants(
  service: ServiceListItem,
): ServiceParticipant[] {
  return servingParticipants(service).filter((participant) =>
    countsAsService(participant.assignment),
  );
}

/** Who really served, for an avatar stack or a list of names. */
export function servedDevotees(service: ServiceListItem): ServiceDevotee[] {
  return servedParticipants(service).map((participant) => participant.devotee);
}

/**
 * Whether one devotee's place on a seva counts as seva they offered.
 */
export function didServe(service: ServiceListItem, userId: string) {
  return servedParticipants(service).some(
    (participant) => participant.devotee.id === userId,
  );
}

/**
 * A seva that happened but which nobody actually served.
 *
 * The temple's rule: "if there is only one person doing seva, if marked absent
 * or excused, it will get removed from the list and not go in the completed
 * list — as if no one served this, how is this seva completed". The same
 * reasoning holds for two devotees both marked absent, so the test is that
 * every live place was answered absent or excused, not that there was one.
 *
 * A seva nobody was ever assigned to is deliberately not this case. It has no
 * absent devotee to disqualify it, and open requests whose hour simply ran out
 * already reach history through `lapsedOpenRequests`.
 */
export function nobodyServed(service: ServiceListItem) {
  const live = servingParticipants(service);
  return live.length > 0 && !live.some((participant) =>
    countsAsService(participant.assignment),
  );
}

/**
 * A devotee's own finished seva — the only completed history they may see.
 *
 * A seva somebody marked them absent or excused for is not theirs to count.
 * The seva still happened, and the temple-wide list still carries it; this is
 * the list the devotee reads as "what I offered", and it may not claim a
 * morning a coordinator recorded them as not having turned up for.
 */
export function myCompletedServices(
  dashboard: ServiceDashboard,
  userId: string,
  now = new Date(),
) {
  return recentlyCompletedServices(dashboard, now).filter((service) =>
    didServe(service, userId),
  );
}

/**
 * What belongs under "Recently completed": seva that is both marked complete
 * and confirmed served, plus open requests whose time simply ran out. Anything
 * completed that nobody has confirmed is waiting to be verified instead — it
 * moves here the moment someone marks it served.
 *
 * Seva every one of whose devotees was marked absent or excused is dropped:
 * "as if no one served this, how is this seva completed". 0068 is expected to
 * take that seva out of the terminal completed state on the server, so this is
 * not the client deciding a status of its own — the status is still read from
 * the row. It is the client refusing to *claim service* for a row that says
 * nobody offered any, which is what a stale cache or the optimistic
 * `markServedInDashboard` patch can briefly leave behind.
 *
 * completedServices stays strict — the stewardship report counts real
 * offerings, not lapsed requests nobody took up.
 */
export function recentlyCompletedServices(
  dashboard: ServiceDashboard,
  now = new Date(),
) {
  return [
    ...completedServices(dashboard)
      .filter(isSevaConfirmedServed)
      .filter((service) => !nobodyServed(service)),
    ...lapsedOpenRequests(dashboard, now),
  ]
    .sort((left, right) =>
      `${right.date}${right.start_time}`.localeCompare(
        `${left.date}${left.start_time}`,
      ),
    );
}

/**
 * Finished seva as the app is allowed to list it: one entry per seva, never one
 * per date.
 *
 * A weekly seva that runs Monday, Thursday and Saturday finishes three times a
 * week, and a list built straight from the occurrences filled every visible row
 * with the same name — the repetition the temple has now reported four times.
 * So the occurrences of one weekly seva fold into a single entry.
 *
 * The entry is dated by the most recent occurrence that actually happened. A
 * completed card may never carry a future date, which is what reading
 * `myNextWeeklyOccurrence` onto one did — a roster card in a history list
 * announcing next Thursday.
 */
export type CompletedSevaEntry =
  | {
      kind: "one_time";
      key: string;
      /** Sort key: when it happened, temple clock. */
      at: string;
      name: string;
      service: ServiceListItem;
    }
  | {
      kind: "weekly";
      key: string;
      at: string;
      name: string;
      templateId: string;
      /** The most recent finished occurrence — what the card is dated by. */
      latest: ServiceListItem;
      /** Every finished occurrence folded into this entry, newest first. */
      occurrences: ServiceListItem[];
    };

/**
 * The fold itself, over a set of finished seva somebody else has already
 * chosen. Exported so a filtered list — one devotee's own, or one date range —
 * collapses exactly the way the unfiltered one does.
 */
export function foldCompletedSeva(
  services: readonly ServiceListItem[],
): CompletedSevaEntry[] {
  const byTemplate = new Map<string, ServiceListItem[]>();
  const entries: CompletedSevaEntry[] = [];
  for (const service of services) {
    if (service.template_id === null) {
      entries.push({
        kind: "one_time",
        key: `service-${service.id}`,
        at: `${service.date}T${service.start_time}`,
        name: service.name,
        service,
      });
      continue;
    }
    const group = byTemplate.get(service.template_id) ?? [];
    group.push(service);
    byTemplate.set(service.template_id, group);
  }
  for (const [templateId, group] of byTemplate) {
    const occurrences = [...group].sort((left, right) =>
      `${right.date}${right.start_time}`.localeCompare(
        `${left.date}${left.start_time}`,
      ),
    );
    const latest = occurrences[0];
    entries.push({
      kind: "weekly",
      key: `weekly-${templateId}`,
      at: `${latest.date}T${latest.start_time}`,
      name: latest.name,
      templateId,
      latest,
      occurrences,
    });
  }
  return entries.sort((left, right) => right.at.localeCompare(left.at));
}

/** "Recently completed", folded. One card per seva, newest first. */
export function completedSevaHistory(
  dashboard: ServiceDashboard,
  now = new Date(),
) {
  return foldCompletedSeva(recentlyCompletedServices(dashboard, now));
}

/** Whether this devotee served any of the occurrences folded into one entry. */
export function didServeAny(
  services: readonly ServiceListItem[],
  userId: string | null,
) {
  if (!userId) return false;
  return services.some((service) => didServe(service, userId));
}

export function completedServices(dashboard: ServiceDashboard) {
  return [...dashboard.services]
    .filter((service) => service.status === "completed")
    .sort((left, right) =>
      `${right.date}${right.start_time}`.localeCompare(
        `${left.date}${left.start_time}`,
      ),
    );
}

export function serviceSearchText(service: ServiceListItem) {
  return [
    service.name,
    service.postedByName,
    // A devotee who stood down should not be how this seva is found.
    ...servingDevotees(service).map((devotee) => devotee.name),
  ]
    .filter(Boolean)
    .join(" ")
    .toLocaleLowerCase();
}

/**
 * Both rosters are searchable. Typing the substitute's name has to find the
 * seva they are actually covering, and typing the original's has to keep
 * finding the seva that is still theirs — a coordinator looking for "Arpita's
 * Thursday" should not be told it does not exist because Tanmay has it.
 */
export function weeklySearchText(
  template: WeeklySeva,
  roster: WeeklyAssignee[] = template.assignees,
) {
  return [
    template.name,
    ...new Set(
      [...template.assignees, ...roster].map((person) => person.name),
    ),
  ]
    .join(" ")
    .toLocaleLowerCase();
}


/**
 * The temple's week, day by day: every dated seva and every weekly occurrence
 * that falls in the range, grouped by the day it happens on. This is the view
 * a coordinator wants on a notice board.
 */
export function sevaRota(
  dashboard: ServiceDashboard,
  fromKey: string,
  toKey: string,
) {
  const byDay = new Map<string, ServiceListItem[]>();
  for (const service of dashboard.services) {
    if (service.date < fromKey || service.date > toKey) continue;
    if (service.status === "cancelled") continue;
    const day = byDay.get(service.date) ?? [];
    day.push(service);
    byDay.set(service.date, day);
  }
  return [...byDay.entries()]
    .sort(([left], [right]) => left.localeCompare(right))
    .map(([date, services]) => ({
      date,
      services: services.sort((left, right) =>
        left.start_time.localeCompare(right.start_time),
      ),
    }));
}
