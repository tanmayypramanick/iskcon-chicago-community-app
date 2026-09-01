import { addChicagoDays } from "../../lib/chicagoDate";
import { isConnectionProblem } from "./format";
import { reportReachability } from "../../lib/connectivity";
import { getSupabaseClient } from "../../lib/supabase";
import { isLiveAssignment } from "./selectors";
import type {
  ClosedUnservedRow,
  CreateRequirementInput,
  CreateRecurringServiceInput,
  CoverageRangeInput,
  SevaClash,
  SevaClashQuery,
  RecurringServiceInterestInput,
  RecurringServiceInterestRow,
  ServiceAssignmentRow,
  ServiceCoveragePlanRow,
  ServiceDashboard,
  ServiceDevotee,
  ServiceInstanceRow,
  ServiceExceptionRow,
  ServiceOfferCounterRow,
  ServiceOfferRow,
  ServiceSessionRow,
  ServiceVerificationRow,
  SevaVerifier,
  RequestVerificationInput,
  LogCompletedSevaInput,
  ProposeAlternativeInput,
  ServiceTemplateAssigneeRow,
  ServiceTemplateRow,
  ServiceType,
  UpdateRecurringServiceInput,
  WeeklySevaAnswer,
  WeeklySevaToAnswer,
  WeeklyUnavailableInput,
} from "./types";

/**
 * A table or column that a not-yet-applied migration will add. Tolerating these
 * keeps the whole Seva tab usable while the temple's database catches up,
 * rather than blanking every list because one new feature is missing.
 *   42P01 / PGRST205 — relation does not exist
 *   42703 / PGRST204 — column does not exist
 */
function missingRelationTolerated(error: { code?: string } | null) {
  if (!error) return null;
  // PGRST202 / 42883 are "that function does not exist yet", which is the
  // normal state of a database between deploying the app and running the
  // migration. Treated like a missing table: fall back, do not blank the tab.
  const pending = [
    "42P01",
    "PGRST205",
    "42703",
    "PGRST204",
    "PGRST202",
    "42883",
  ];
  return pending.includes(error.code ?? "") ? null : error;
}

/**
 * How far back the Seva tab loads. Everything on that tab is about now and the
 * near past, so an unbounded fetch would grow without limit as the temple
 * accumulates years of seva. Reports and activity read from the same window;
 * anything older lives in the exported spreadsheets.
 */
export const DASHBOARD_HISTORY_DAYS = 180;

type DashboardRows = {
  serviceTypes: ServiceType[];
  instances: ServiceInstanceRow[];
  assignments: ServiceAssignmentRow[];
  offers: ServiceOfferRow[];
  templates: ServiceTemplateRow[];
  templateAssignees: ServiceTemplateAssigneeRow[];
  exceptions: ServiceExceptionRow[];
  coveragePlans: ServiceCoveragePlanRow[];
  interests: RecurringServiceInterestRow[];
  verifications: ServiceVerificationRow[];
  counters: ServiceOfferCounterRow[];
  devotees: ServiceDevotee[];
};

/**
 * One round trip for the whole tab, scoped to the history window server-side.
 * Returns null when the function is not deployed yet, so the app keeps working
 * against a database that has not had migration 0028 applied.
 */
async function loadDashboardRows(): Promise<DashboardRows | null> {
  const { data, error } = await getSupabaseClient().rpc("seva_dashboard", {
    p_history_days: DASHBOARD_HISTORY_DAYS,
  });
  if (error) {
    if (missingRelationTolerated(error) === null) return null;
    throw error;
  }
  if (!data || typeof data !== "object") return null;
  return data as DashboardRows;
}

export async function fetchServiceDashboard(
  currentUserId: string,
): Promise<ServiceDashboard> {
  const supabase = getSupabaseClient();
  const historyFrom = addChicagoDays(-DASHBOARD_HISTORY_DAYS);
  const single = await loadDashboardRows();
  if (single) {
    reportReachability(true);
    return assembleDashboard(currentUserId, {
      serviceTypes: single.serviceTypes ?? [],
      instanceRows: single.instances ?? [],
      assignments: single.assignments ?? [],
      offers: single.offers ?? [],
      templates: single.templates ?? [],
      templateAssignees: single.templateAssignees ?? [],
      exceptions: single.exceptions ?? [],
      coveragePlans: single.coveragePlans ?? [],
      interests: single.interests ?? [],
      verifications: single.verifications ?? [],
      counters: single.counters ?? [],
      devotees: single.devotees ?? [],
    });
  }

  // Keep request bursts small. Large parallel batches repeatedly triggered
  // CFNetwork TLS failures in long-running iOS simulator sessions.
  const [typesResult, instancesResult, assignmentsResult] = await Promise.all([
    supabase
      .from("service_types")
      // The active catalog exposes only names and categories. Historical QR
      // fields remain in the database for old records, but new app versions
      // have no QR entry or scanning flow.
      .select("id,name,category,is_active")
      .eq("is_active", true)
      .order("category")
      .order("name")
      .returns<ServiceType[]>(),
    supabase
      .from("service_instances")
      .select(
        "id,template_id,service_type_id,custom_name,date,start_time,duration_minutes,slots_needed,participation_mode,posted_by,status,created_at",
      )
      .gte("date", historyFrom)
      .order("date", { ascending: true })
      .order("start_time", { ascending: true })
      .returns<ServiceInstanceRow[]>(),
    supabase
      .from("service_assignments")
      .select(
        // attendance belongs here too: without it every devotee reads as
        // unmarked on the fallback path, so a coordinator cannot see who they
        // have already answered for.
        "id,service_instance_id,devotee_id,assignment_method,assigned_by,status,attendance,verification,qr_scanned_at,created_at,completed_at",
      )
      .order("created_at", { ascending: false })
      .limit(5000)
      .returns<ServiceAssignmentRow[]>(),
  ]);
  const [offersResult, devoteesResult, templatesResult] = await Promise.all([
    supabase
      .from("service_offers")
      .select(
        "id,service_instance_id,service_template_id,service_exception_id,service_coverage_plan_id,offered_to,offered_by,offer_kind,status,created_at,responded_at",
      )
      .order("created_at", { ascending: false })
      .limit(2000)
      .returns<ServiceOfferRow[]>(),
    supabase.rpc("list_service_devotees"),
    supabase
      .from("service_templates")
      .select(
        "id,service_type_id,custom_name,day_of_week,days_of_week,start_time,duration_minutes,slots_needed,participation_mode,start_date,end_date,created_by,active,created_at,updated_at",
      )
      .order("active", { ascending: false })
      .order("day_of_week")
      .order("start_time")
      .returns<ServiceTemplateRow[]>(),
  ]);
  const [templateAssigneesResult, exceptionsResult] = await Promise.all([
    supabase
      .from("service_template_assignees")
      .select(
        "id,service_template_id,devotee_id,assigned_by,status,days_of_week,created_at,updated_at",
      )
      .returns<ServiceTemplateAssigneeRow[]>(),
    supabase
      .from("service_exceptions")
      .select(
        "id,service_instance_id,devotee_id,reason,status,resolution_kind,substitute_devotee_id,created_at,resolved_at,resolved_by,request_group_id,unavailable_scope,unavailable_from,unavailable_to,unavailable_days",
      )
      .order("created_at", { ascending: false })
      .limit(1000)
      .returns<ServiceExceptionRow[]>(),
  ]);
  const [verificationsResult, countersResult] = await Promise.all([
    supabase
      .from("service_verifications")
      .select(
        "id,devotee_id,service_type_id,custom_name,start_at,end_at,location_text,verifier_id,status,review_note,service_instance_id,verified_by,created_at,responded_at",
      )
      // Bounded by the same window as everything else rather than by a row
      // count, so a pending request can never fall off the approvals inbox.
      .gte("start_at", `${historyFrom}T00:00:00Z`)
      .order("created_at", { ascending: false })
      .limit(2000)
      .returns<ServiceVerificationRow[]>(),
    supabase
      .from("service_offer_counters")
      .select(
        "id,service_offer_id,devotee_id,proposed_days,proposed_date,proposed_start_time,proposed_duration_minutes,note,status,review_note,created_at,responded_at,responded_by",
      )
      .order("created_at", { ascending: false })
      .limit(1000)
      .returns<ServiceOfferCounterRow[]>(),
  ]);
  const [coveragePlansResult, interestsResult] = await Promise.all([
    supabase
      .from("service_coverage_plans")
      .select(
        "id,service_exception_id,request_group_id,service_template_id,original_devotee_id,substitute_devotee_id,scope,date_from,date_to,days_of_week,status,created_by,created_at,responded_at",
      )
      .order("created_at", { ascending: false })
      .limit(1000)
      .returns<ServiceCoveragePlanRow[]>(),
    supabase
      .from("recurring_service_interests")
      .select(
        "id,devotee_id,skills,desired_service_type_ids,other_service,availability,currently_serving,current_service_details,status,submitted_at,updated_at,reviewed_at,reviewed_by,review_note",
      )
      .order("submitted_at", { ascending: false })
      .limit(500)
      .returns<RecurringServiceInterestRow[]>(),
  ]);

  const firstError =
    typesResult.error ??
    instancesResult.error ??
    assignmentsResult.error ??
    offersResult.error ??
    devoteesResult.error ??
    templatesResult.error ??
    templateAssigneesResult.error ??
    exceptionsResult.error ??
    coveragePlansResult.error ??
    interestsResult.error ??
    // The verification and counter-offer tables arrive in migration 0012. Until
    // it is applied they simply do not exist, and a missing-relation error must
    // not blank the whole Seva tab — those two features just stay empty.
    missingRelationTolerated(verificationsResult.error) ??
    missingRelationTolerated(countersResult.error);
  if (firstError) throw firstError;

  return assembleDashboard(currentUserId, {
    serviceTypes: typesResult.data ?? [],
    instanceRows: instancesResult.data ?? [],
    assignments: assignmentsResult.data ?? [],
    offers: offersResult.data ?? [],
    templates: templatesResult.data ?? [],
    templateAssignees: templateAssigneesResult.data ?? [],
    exceptions: exceptionsResult.data ?? [],
    coveragePlans: coveragePlansResult.data ?? [],
    interests: interestsResult.data ?? [],
    verifications: verificationsResult.data ?? [],
    counters: countersResult.data ?? [],
    devotees: (devoteesResult.data ?? []) as unknown as ServiceDevotee[],
  });
}

/**
 * Turns the raw row-sets into what the Seva tab renders. Shared by the single
 * server-side read and the per-table fallback, so the two can never drift.
 *
 * Exported for tests: this is where a seva gets its participants, its filled
 * count and its outstanding answers, and every one of those has already been
 * wrong once. Testing it through a mocked Supabase client tests the mock.
 */
export function assembleDashboard(
  currentUserId: string,
  rows: {
    serviceTypes: ServiceType[];
    instanceRows: ServiceInstanceRow[];
    assignments: ServiceAssignmentRow[];
    offers: ServiceOfferRow[];
    templates: ServiceTemplateRow[];
    templateAssignees: ServiceTemplateAssigneeRow[];
    exceptions: ServiceExceptionRow[];
    coveragePlans: ServiceCoveragePlanRow[];
    interests: RecurringServiceInterestRow[];
    verifications: ServiceVerificationRow[];
    counters: ServiceOfferCounterRow[];
    devotees: ServiceDevotee[];
  },
): ServiceDashboard {
  const {
    serviceTypes,
    instanceRows,
    assignments,
    offers,
    templates,
    templateAssignees,
    exceptions,
    coveragePlans,
    interests,
    devotees,
  } = rows;
  const sessions: ServiceSessionRow[] = [];
  const typeById = new Map(
    serviceTypes.map((serviceType) => [serviceType.id, serviceType]),
  );
  const devoteeById = new Map(devotees.map((devotee) => [devotee.id, devotee]));

  // Indexed once instead of scanning every assignment and offer for every
  // instance. The nested filters were O(instances x assignments), which is the
  // kind of work that blocks the JS thread and makes unrelated taps feel slow.
  const assignmentsByInstance = new Map<string, ServiceAssignmentRow[]>();
  for (const assignment of assignments) {
    const list = assignmentsByInstance.get(assignment.service_instance_id);
    if (list) list.push(assignment);
    else assignmentsByInstance.set(assignment.service_instance_id, [assignment]);
  }
  const myPendingOfferByInstance = new Map<string, ServiceOfferRow>();
  /**
   * Everyone already asked to take a place on a dated seva and yet to answer.
   *
   * Kept because `update_service_requirement` only ever adds invitations, so
   * the screen that changes a request has to be able to say who is already
   * waiting on it. Without this the coordinator was shown an unticked row for a
   * devotee they had asked yesterday, and ticking it resent the invitation.
   */
  const pendingInviteeIdsByInstance = new Map<string, string[]>();
  for (const offer of offers) {
    if (
      offer.service_instance_id &&
      offer.offer_kind === "one_time" &&
      offer.status === "pending"
    ) {
      const asked = pendingInviteeIdsByInstance.get(offer.service_instance_id);
      if (asked) asked.push(offer.offered_to);
      else pendingInviteeIdsByInstance.set(offer.service_instance_id, [offer.offered_to]);
    }
    if (
      offer.service_instance_id &&
      offer.offered_to === currentUserId &&
      offer.status === "pending"
    ) {
      myPendingOfferByInstance.set(offer.service_instance_id, offer);
    }
  }

  const services = instanceRows.map((instance) => {
    const instanceAssignments = assignmentsByInstance.get(instance.id) ?? [];
    // Same rule the screens apply, from the same helper: a withdrawn place
    // belongs to a devotee who no longer serves this seva.
    const activeAssignments = instanceAssignments.filter(isLiveAssignment);
    const participants = activeAssignments.flatMap((assignment) => {
      const devotee = devoteeById.get(assignment.devotee_id);
      return devotee ? [{ assignment, devotee }] : [];
    });
    const serviceType = instance.service_type_id
      ? (typeById.get(instance.service_type_id) ?? null)
      : null;

    return {
      ...instance,
      name: serviceType?.name ?? instance.custom_name ?? "Temple service",
      serviceType,
      filledSlots: activeAssignments.length,
      participants,
      currentUserAssignment:
        activeAssignments.find(
          (assignment) => assignment.devotee_id === currentUserId,
        ) ?? null,
      currentUserOffer: myPendingOfferByInstance.get(instance.id) ?? null,
      pendingInvitees: (pendingInviteeIdsByInstance.get(instance.id) ?? []).flatMap(
        (devoteeId) => {
          const devotee = devoteeById.get(devoteeId);
          return devotee ? [devotee] : [];
        },
      ),
      postedByName: instance.posted_by
        ? (devoteeById.get(instance.posted_by)?.name ?? null)
        : null,
    };
  });

  const serviceById = new Map(services.map((service) => [service.id, service]));
  const pendingOffers = offers.flatMap((offer) => {
    if (["recurring", "coverage_range"].includes(offer.offer_kind)) return [];
    if (offer.offered_to !== currentUserId || offer.status !== "pending")
      return [];
    if (!offer.service_instance_id) return [];
    const service = serviceById.get(offer.service_instance_id);
    if (!service) return [];
    return [
      {
        offer,
        service,
        offeredByName:
          devoteeById.get(offer.offered_by)?.name ?? "A coordinator",
      },
    ];
  });

  /**
   * Answers on a seva request that still need giving: a decline leaves a place
   * to fill, a suggestion needs a yes or no. Without this, a "no" simply
   * vanished and the request quietly went unfilled.
   *
   * Who may give the answer is not decided here. The RPC accepts the poster or
   * a holder of `app.view_all`, and this function is handed a user id and no
   * role, so testing `posted_by` alone was the wrong half of the rule — it hid
   * counters a Tech Admin or the President was entitled to answer. RLS already
   * limits which offers and counters reach this device; `sevaNeedingMyAnswer`
   * applies the role on top.
   */
  const counters = rows.counters;
  const counterByOfferId = new Map(
    counters.map((counter) => [counter.service_offer_id, counter]),
  );
  type SevaNeedingAnswer = ServiceDashboard["sevaNeedingAnswer"][number];
  const sevaNeedingAnswer: ServiceDashboard["sevaNeedingAnswer"] = offers.flatMap(
    (offer): SevaNeedingAnswer[] => {
      if (offer.offer_kind === "recurring" || offer.offer_kind === "coverage_range") {
        return [];
      }
      if (!offer.service_instance_id) return [];
      const service = serviceById.get(offer.service_instance_id);
      if (!service) return [];
      if (["completed", "cancelled"].includes(service.status)) return [];

      const counter = counterByOfferId.get(offer.id) ?? null;
      if (offer.status === "countered" && counter?.status === "pending") {
        return [
          {
            kind: "countered" as const,
            offer,
            counter,
            service,
            devoteeName: devoteeById.get(offer.offered_to)?.name ?? "A devotee",
          },
        ];
      }
      if (offer.status === "declined" && service.filledSlots < service.slots_needed) {
        return [
          {
            kind: "declined" as const,
            offer,
            counter: null,
            service,
            devoteeName: devoteeById.get(offer.offered_to)?.name ?? "A devotee",
          },
        ];
      }
      return [];
    },
  );

  const recurringTemplates = templates.flatMap((template) => {
    const serviceType = template.service_type_id
      ? (typeById.get(template.service_type_id) ?? null)
      : null;
    return [
      {
        ...template,
        serviceType,
        name: serviceType?.name ?? template.custom_name ?? "Temple seva",
        assignees: templateAssignees.flatMap((assignee) => {
          if (
            assignee.service_template_id !== template.id ||
            assignee.status !== "active"
          ) {
            return [];
          }
          const devotee = devoteeById.get(assignee.devotee_id);
          return devotee
            ? [{ ...devotee, assignedDays: assignee.days_of_week }]
            : [];
        }),
      },
    ];
  });
  const recurringTemplateById = new Map(
    recurringTemplates.map((template) => [template.id, template]),
  );
  const pendingRecurringOffers: ServiceDashboard["pendingRecurringOffers"] =
    offers.flatMap((offer) => {
    if (
      offer.offer_kind !== "recurring" ||
      offer.offered_to !== currentUserId ||
      offer.status !== "pending" ||
      !offer.service_template_id
    ) {
      return [];
    }
    const template = recurringTemplateById.get(offer.service_template_id);
    if (!template) return [];
    return [
      {
        offer,
        template,
        offeredByName:
          devoteeById.get(offer.offered_by)?.name ?? "A coordinator",
        coveragePlan: null,
      },
    ];
    });
  for (const offer of offers) {
    if (
      offer.offer_kind === "coverage_range" &&
      offer.offered_to === currentUserId &&
      offer.status === "pending" &&
      offer.service_template_id
    ) {
      const template = recurringTemplateById.get(offer.service_template_id);
      if (template) {
        pendingRecurringOffers.push({
          offer,
          template,
          offeredByName:
            devoteeById.get(offer.offered_by)?.name ?? "A coordinator",
          coveragePlan:
            coveragePlans.find(
              (plan) => plan.id === offer.service_coverage_plan_id,
            ) ?? null,
        });
      }
    }
  }
  const exceptionGroups = new Map<string, ServiceExceptionRow[]>();
  for (const exception of exceptions) {
    exceptionGroups.set(exception.request_group_id, [
      ...(exceptionGroups.get(exception.request_group_id) ?? []),
      exception,
    ]);
  }
  const coverageRequests = [...exceptionGroups.values()].flatMap(
    (groupExceptions) => {
      const sorted = [...groupExceptions].sort((left, right) => {
        const leftService = serviceById.get(left.service_instance_id);
        const rightService = serviceById.get(right.service_instance_id);
        return (leftService?.date ?? "").localeCompare(rightService?.date ?? "");
      });
      const exception =
        sorted.find((item) => item.status === "pending") ?? sorted[0];
      const service = serviceById.get(exception.service_instance_id);
      const unavailableDevotee = devoteeById.get(exception.devotee_id);
      if (!service || !unavailableDevotee) return [];
      return [
        {
          exception,
          exceptions: sorted,
          service,
          unavailableDevotee,
          substituteDevotee: exception.substitute_devotee_id
            ? (devoteeById.get(exception.substitute_devotee_id) ?? null)
            : null,
        },
      ];
    },
  );

  const activitySessions = sessions.flatMap((session) => {
    const serviceType = session.service_type_id
      ? (typeById.get(session.service_type_id) ?? null)
      : null;
    const devotee = devoteeById.get(session.devotee_id);
    return devotee
      ? [{
          session,
          serviceType,
          name: serviceType?.name ?? session.custom_name ?? "Temple seva",
          devotee,
        }]
      : [];
  });
  const activeSessions = activitySessions.filter(
    ({ session }) => session.status === "active",
  );

  const recurringInterests = interests.flatMap((interest) => {
    const devotee = devoteeById.get(interest.devotee_id);
    if (!devotee) return [];
    return [
      {
        ...interest,
        devotee,
        desiredServiceTypes: interest.desired_service_type_ids.flatMap((id) => {
          const serviceType = typeById.get(id);
          return serviceType ? [serviceType] : [];
        }),
      },
    ];
  });

  const verifications = (rows.verifications).map((row) => ({
    ...row,
    name:
      (row.service_type_id ? typeById.get(row.service_type_id)?.name : null) ??
      row.custom_name ??
      "Temple seva",
    devotee: devoteeById.get(row.devotee_id) ?? null,
    verifier: devoteeById.get(row.verifier_id) ?? null,
    verifiedBy: row.verified_by ? (devoteeById.get(row.verified_by) ?? null) : null,
  }));

  return {
    serviceTypes,
    devotees,
    services,
    verifications,
    myVerifications: verifications.filter(
      (row) => row.devotee_id === currentUserId,
    ),
    verificationInbox: verifications.filter(
      (row) => row.verifier_id === currentUserId && row.status === "pending",
    ),
    offerCounters: counters,
    sevaNeedingAnswer,
    pendingOffers,
    recurringTemplates,
    pendingRecurringOffers,
    coverageRequests,
    coveragePlans,
    activeSessions,
    activitySessions,
    recurringInterests,
  };
}

async function runRpc(name: string, params: Record<string, unknown>) {
  const { data, error } = await getSupabaseClient().rpc(name, params);
  // A transport failure means the server is unreachable; a Postgres error
  // means it answered, so the connection is fine.
  reportReachability(!error || !isConnectionProblem(error));
  if (error) throw error;
  return data;
}

export function createServiceRequirement(input: CreateRequirementInput) {
  return runRpc("create_service_requirement", {
    p_service_type_id: input.serviceTypeId,
    p_custom_name: input.customName,
    p_date: input.date,
    p_start_time: input.startTime,
    p_duration_minutes: input.durationMinutes,
    p_slots_needed: input.slotsNeeded,
    p_participation_mode: input.participationMode,
    p_invitee_ids: input.inviteeIds,
  });
}

export function joinService(instanceId: string) {
  return runRpc("join_service_instance", { p_instance_id: instanceId });
}

export function leaveService(instanceId: string) {
  return runRpc("leave_service_instance", { p_instance_id: instanceId });
}

export function offerService(instanceId: string, devoteeId: string) {
  return runRpc("offer_service_instance", {
    p_instance_id: instanceId,
    p_devotee_id: devoteeId,
  });
}

export function respondToServiceOffer(offerId: string, accept: boolean) {
  return runRpc("respond_to_service_offer", {
    p_offer_id: offerId,
    p_accept: accept,
  });
}

export function completeService(instanceId: string) {
  return runRpc("complete_service_instance", { p_instance_id: instanceId });
}

export function completeMyServiceAssignment(instanceId: string) {
  return runRpc("complete_my_service_assignment", {
    p_instance_id: instanceId,
  });
}





export function deleteServiceActivity(sessionId: string) {
  return runRpc("delete_service_activity", { p_session_id: sessionId });
}

export function deleteServiceRequirement(instanceId: string) {
  return runRpc("delete_service_requirement", { p_instance_id: instanceId });
}

export function deleteServiceAssignmentActivity(assignmentId: string) {
  return runRpc("delete_service_assignment_activity", {
    p_assignment_id: assignmentId,
  });
}

export function submitRecurringServiceInterest(
  input: RecurringServiceInterestInput,
) {
  return runRpc("submit_recurring_service_interest", {
    p_skills: input.skills,
    p_desired_service_type_ids: input.desiredServiceTypeIds,
    p_other_service: input.otherService,
    p_availability: input.availability,
    p_currently_serving: input.currentlyServing,
    p_current_service_details: input.currentServiceDetails,
  });
}

export function reviewRecurringServiceInterest(
  interestId: string,
  approve: boolean,
  reviewNote: string | null,
) {
  return runRpc("review_recurring_service_interest", {
    p_interest_id: interestId,
    p_approve: approve,
    p_review_note: reviewNote,
  });
}

export function createRecurringService(input: CreateRecurringServiceInput) {
  return runRpc("create_service_template_v2", {
    p_service_type_id: input.serviceTypeId,
    p_custom_name: input.customName,
    p_days_of_week: input.daysOfWeek,
    p_start_time: input.startTime,
    p_duration_minutes: input.durationMinutes,
    p_slots_needed: input.slotsNeeded,
    p_participation_mode: input.participationMode,
    p_start_date: input.startDate,
    p_end_date: input.endDate,
    p_invitee_ids: input.inviteeIds,
  });
}

export function updateRecurringService(input: UpdateRecurringServiceInput) {
  return runRpc("update_service_template_v2", {
    p_template_id: input.templateId,
    p_service_type_id: input.serviceTypeId,
    p_custom_name: input.customName,
    p_days_of_week: input.daysOfWeek,
    p_start_time: input.startTime,
    p_duration_minutes: input.durationMinutes,
    p_slots_needed: input.slotsNeeded,
    p_participation_mode: input.participationMode,
    p_start_date: input.startDate,
    p_end_date: input.endDate,
    p_invitee_ids: input.inviteeIds,
  });
}

export function deleteRecurringService(templateId: string) {
  return runRpc("delete_service_template", { p_template_id: templateId });
}

export function reportWeeklyServiceUnavailable(input: WeeklyUnavailableInput) {
  return runRpc("report_weekly_service_unavailable", {
    p_template_id: input.templateId,
    p_scope: input.scope,
    p_date_from: input.dateFrom,
    p_date_to: input.dateTo,
    p_days_of_week: input.daysOfWeek,
    p_reason: input.reason,
  });
}

export function joinWeeklyService(templateId: string) {
  return runRpc("join_weekly_service", { p_template_id: templateId });
}

export function reopenServiceException(exceptionId: string) {
  return runRpc("reopen_service_exception", {
    p_exception_id: exceptionId,
  });
}

export function offerServiceCoverage(exceptionId: string, devoteeId: string) {
  return runRpc("offer_service_coverage", {
    p_exception_id: exceptionId,
    p_devotee_id: devoteeId,
  });
}

export function offerServiceCoverageRange(input: CoverageRangeInput) {
  return runRpc("offer_service_coverage_range", {
    p_exception_id: input.exceptionId,
    p_devotee_id: input.devoteeId,
    p_scope: input.scope,
    p_date_from: input.dateFrom,
    p_date_to: input.dateTo,
  });
}

export function respondToCoverageRangeOffer(offerId: string, accept: boolean) {
  return runRpc("respond_to_coverage_range_offer", {
    p_offer_id: offerId,
    p_accept: accept,
  });
}

export function setRecurringServiceActive(templateId: string, active: boolean) {
  return runRpc("set_service_template_active", {
    p_template_id: templateId,
    p_active: active,
  });
}

/** Community Heads, Tech Admins and the President, for the verifier picker. */
export async function fetchSevaVerifiers(): Promise<SevaVerifier[]> {
  const { data, error } = await getSupabaseClient().rpc("list_seva_verifiers");
  if (error) throw error;
  return (data ?? []) as unknown as SevaVerifier[];
}

export function requestSevaVerification(input: RequestVerificationInput) {
  return runRpc("request_seva_verification", {
    p_service_type_id: input.serviceTypeId,
    p_custom_name: input.customName,
    p_start_at: input.startAt,
    p_end_at: input.endAt,
    p_location_text: input.locationText,
    p_verifier_id: input.verifierId,
    // The database keeps this legacy argument until older installed builds
    // have aged out. New app versions never expose or submit QR codes.
    p_qr_token: null,
  });
}

export function logCompletedSeva(input: LogCompletedSevaInput) {
  return runRpc("log_completed_seva", {
    p_service_type_id: input.serviceTypeId,
    p_custom_name: input.customName,
    p_start_at: input.startAt,
    p_end_at: input.endAt,
    p_location_text: input.locationText,
    p_verifier_id: input.verifierId,
  });
}

export function resendSevaVerification(
  verificationId: string,
  verifierId: string,
) {
  return runRpc("resend_seva_verification", {
    p_verification_id: verificationId,
    p_verifier_id: verifierId,
  });
}

export function respondToSevaVerification(
  verificationId: string,
  approve: boolean,
  note: string | null,
) {
  return runRpc("respond_to_seva_verification", {
    p_verification_id: verificationId,
    p_approve: approve,
    p_note: note,
  });
}

export function proposeServiceOfferAlternative(input: {
  offerId: string;
  date: string;
  startTime: string;
  durationMinutes: number;
  note: string | null;
}) {
  return runRpc("propose_service_offer_alternative", {
    p_offer_id: input.offerId,
    p_date: input.date,
    p_start_time: input.startTime,
    p_duration_minutes: input.durationMinutes,
    p_note: input.note,
  });
}

export function respondToServiceOfferCounter(
  counterId: string,
  accept: boolean,
  note: string | null,
) {
  return runRpc("respond_to_service_offer_counter", {
    p_counter_id: counterId,
    p_accept: accept,
    p_note: note,
  });
}

export function recordSevaAttendance(
  assignmentId: string,
  attendance: "served" | "absent" | "excused" | null,
) {
  return runRpc("record_seva_attendance", {
    p_assignment_id: assignmentId,
    p_attendance: attendance,
  });
}

/**
 * Answers every place on a seva that nobody has answered for, in one
 * statement, deciding server-side which those are.
 *
 * Replaces a client-side loop over ids read from the dashboard snapshot. That
 * loop overwrote attendance unconditionally, so a devotee another coordinator
 * had just marked absent was flipped back to served by a screen up to thirty
 * seconds out of date — and it was not atomic, so a failure part-way left some
 * places written while the cache rolled all of them back.
 */
export function recordUnansweredSevaAttendance(
  instanceId: string,
  attendance: "served" | "absent" | "excused" = "served",
) {
  return runRpc("record_unanswered_seva_attendance", {
    p_instance_id: instanceId,
    p_attendance: attendance,
  });
}

export function updateServiceRequirement(input: {
  instanceId: string;
  participationMode: "open" | "invite_only";
  slotsNeeded: number;
  inviteeIds: string[];
}) {
  return runRpc("update_service_requirement", {
    p_instance_id: input.instanceId,
    p_participation_mode: input.participationMode,
    p_slots_needed: input.slotsNeeded,
    p_invitee_ids: input.inviteeIds,
  });
}

export function proposeWeeklyOfferAlternative(input: ProposeAlternativeInput) {
  return runRpc("propose_weekly_offer_alternative", {
    p_offer_id: input.offerId,
    p_days: input.daysOfWeek,
    p_start_time: input.startTime,
    p_duration_minutes: input.durationMinutes,
    p_note: input.note,
  });
}

export function respondToWeeklyOfferCounter(
  counterId: string,
  approve: boolean,
  note: string | null,
) {
  return runRpc("respond_to_weekly_offer_counter", {
    p_counter_id: counterId,
    p_approve: approve,
    p_note: note,
  });
}

export function deleteSevaRegistration(verificationId: string) {
  return runRpc("delete_seva_registration", {
    p_verification_id: verificationId,
  });
}

/**
 * What else this devotee is already down for during a proposed window.
 *
 * Facts for a warning and nothing else — 0069 made the function `stable`, and
 * it refuses nothing. A database that has not had 0069 applied yet answers
 * "nothing known", so a temple mid-deploy simply gets no warnings rather than
 * an error on every seva screen.
 */
export async function fetchSevaClashes(
  query: SevaClashQuery,
): Promise<SevaClash[]> {
  const { data, error } = await getSupabaseClient().rpc("list_seva_clashes", {
    p_devotee_id: query.devoteeId,
    p_date: query.date,
    p_start_time: query.startTime,
    p_duration_minutes: query.durationMinutes,
    p_exclude_instance_id: query.excludeInstanceId ?? null,
  });
  if (error) {
    if (missingRelationTolerated(error) === null) return [];
    throw error;
  }
  return (data ?? []) as unknown as SevaClash[];
}

/**
 * Seva that 0068 took out of the completed list because every place on it was
 * answered absent or excused.
 *
 * The RPC decides who may read this — its poster, the Tech Admin and the
 * President — and answers nobody else a single row, so there is no role test
 * here to drift from the one in the schema. `service_instances_unserved` itself
 * is granted to no client role and must never be read directly.
 */
export async function fetchClosedUnservedSeva(): Promise<ClosedUnservedRow[]> {
  const { data, error } = await getSupabaseClient().rpc(
    "list_seva_closed_unserved",
    { p_from: addChicagoDays(-DASHBOARD_HISTORY_DAYS), p_to: null },
  );
  if (error) {
    if (missingRelationTolerated(error) === null) return [];
    throw error;
  }
  return (data ?? []) as unknown as ClosedUnservedRow[];
}


/**
 * The devotee's own weekly seva that has finished and that they have not
 * answered for. The server decides whose it is; there is nothing to scope here.
 */
export async function fetchMyWeeklySevaToAnswer(): Promise<WeeklySevaToAnswer[]> {
  const { data, error } = await getSupabaseClient().rpc(
    "list_my_weekly_seva_to_answer",
    { p_days: 14 },
  );
  reportReachability(!error || !isConnectionProblem(error));
  if (error) {
    // The prompt arrives with its own migration; a temple that has not applied
    // it yet simply has nothing to answer rather than a red box on the board.
    if (["PGRST202", "42883", "42P01", "PGRST205"].includes(error.code ?? "")) {
      return [];
    }
    throw error;
  }
  return (data ?? []) as unknown as WeeklySevaToAnswer[];
}

/** "I served it" or "I missed it", for one of the devotee's own weekly places. */
export function answerMyWeeklySeva(assignmentId: string, served: boolean) {
  return runRpc("answer_my_weekly_seva", {
    p_assignment_id: assignmentId,
    p_served: served,
  });
}

/** What devotees answered, for whoever set the rota up, plus Tech and President. */
export async function fetchWeeklySevaAnswers(
  days = 14,
): Promise<WeeklySevaAnswer[]> {
  const { data, error } = await getSupabaseClient().rpc(
    "list_weekly_seva_answers",
    { p_days: days },
  );
  reportReachability(!error || !isConnectionProblem(error));
  if (error) {
    if (["PGRST202", "42883", "42P01", "PGRST205"].includes(error.code ?? "")) {
      return [];
    }
    throw error;
  }
  return (data ?? []) as unknown as WeeklySevaAnswer[];
}


/**
 * Gives up a place on a posted seva before it starts.
 *
 * An open seva simply frees the place. An invite-only one opens a coverage
 * request for whoever posted it, who can open the day to everyone or ask
 * somebody else. Returns the coverage request's id, or null when none was
 * needed.
 */
export function stepBackFromSeva(instanceId: string, reason?: string | null) {
  return runRpc("step_back_from_seva", {
    p_instance_id: instanceId,
    p_reason: reason ?? null,
  });
}


/** Puts the weekly "did you serve this?" question away without answering it. */
export function dismissMyWeeklySevaAnswer(assignmentId: string) {
  return runRpc("dismiss_my_weekly_seva_answer", {
    p_assignment_id: assignmentId,
  });
}
