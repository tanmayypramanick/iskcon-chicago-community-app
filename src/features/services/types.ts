export type ServiceCategory =
  "kitchen" | "cleaning" | "deity-worship" | "event" | "other";

export type ServiceType = {
  id: string;
  name: string;
  category: ServiceCategory;
  is_active: boolean;
};

export type ServiceInstanceStatus =
  "open" | "full" | "closed" | "cancelled" | "completed";

export type ServiceInstanceRow = {
  id: string;
  template_id: string | null;
  service_type_id: string | null;
  custom_name: string | null;
  date: string;
  start_time: string;
  duration_minutes: number;
  slots_needed: number;
  participation_mode: "open" | "invite_only";
  posted_by: string | null;
  status: ServiceInstanceStatus;
  created_at: string;
};

export type SevaAttendance = "served" | "absent" | "excused";

export type ServiceAssignmentRow = {
  id: string;
  service_instance_id: string;
  devotee_id: string;
  assignment_method:
    | "self_joined"
    | "accepted_offer"
    | "recurring_assignment"
    | "accepted_coverage_offer"
    | "self_logged"
    | "live_timer"
    | "qr_scan"
    | "member_verified";
  assigned_by: string | null;
  status: "assigned" | "confirmed" | "completed" | "no_show" | "withdrawn";
  /** Null until somebody records who actually turned up. */
  attendance: SevaAttendance | null;
  verification: "self_report" | "live_timer" | "qr_scan" | "member_verified";
  qr_scanned_at: string | null;
  created_at: string;
  completed_at: string | null;
};

export type ServiceOfferRow = {
  id: string;
  service_instance_id: string | null;
  service_template_id: string | null;
  service_exception_id: string | null;
  service_coverage_plan_id: string | null;
  offered_to: string;
  offered_by: string;
  offer_kind: "one_time" | "recurring" | "coverage" | "coverage_range";
  status: "pending" | "accepted" | "declined" | "expired" | "countered";
  created_at: string;
  responded_at: string | null;
};

export type ServiceTemplateRow = {
  id: string;
  service_type_id: string | null;
  custom_name: string | null;
  day_of_week: number;
  days_of_week: number[];
  start_time: string;
  duration_minutes: number;
  slots_needed: number;
  participation_mode: "open" | "invite_only";
  start_date: string;
  end_date: string | null;
  created_by: string;
  active: boolean;
  created_at: string;
  updated_at: string;
};

export type ServiceTemplateAssigneeRow = {
  id: string;
  service_template_id: string;
  devotee_id: string;
  assigned_by: string;
  status: "active" | "withdrawn";
  days_of_week: number[];
  created_at: string;
  updated_at: string;
};

export type ServiceExceptionRow = {
  id: string;
  service_instance_id: string;
  devotee_id: string;
  reason: string | null;
  status: "pending" | "resolved";
  resolution_kind: "broadcast" | "substitute" | null;
  substitute_devotee_id: string | null;
  created_at: string;
  resolved_at: string | null;
  resolved_by: string | null;
  request_group_id: string;
  unavailable_scope: CoverageScope;
  unavailable_from: string;
  unavailable_to: string | null;
  unavailable_days: number[];
};

export type ServiceCoveragePlanRow = {
  id: string;
  service_exception_id: string | null;
  request_group_id: string;
  service_template_id: string;
  original_devotee_id: string;
  substitute_devotee_id: string;
  scope: CoverageScope;
  date_from: string;
  date_to: string | null;
  days_of_week: number[];
  status: "pending" | "accepted" | "declined" | "cancelled";
  created_by: string;
  created_at: string;
  responded_at: string | null;
};

export type ServiceDevotee = {
  id: string;
  name: string;
  photo_url: string | null;
  role_name: string;
};

export type ServiceSessionRow = {
  id: string;
  devotee_id: string;
  service_type_id: string | null;
  custom_name: string | null;
  started_at: string;
  completed_at: string | null;
  cancelled_at: string | null;
  status: "active" | "completed" | "cancelled";
  service_instance_id: string | null;
  started_via: "qr" | "service_list" | "custom";
  planned_end_at: string;
  location_text: string;
  auto_completed: boolean;
  updated_at: string;
};

export type RecurringServiceInterestRow = {
  id: string;
  devotee_id: string;
  skills: string;
  desired_service_type_ids: string[];
  other_service: string | null;
  availability: string;
  currently_serving: boolean;
  current_service_details: string | null;
  status: "pending" | "approved" | "denied";
  submitted_at: string;
  updated_at: string;
  reviewed_at: string | null;
  reviewed_by: string | null;
  review_note: string | null;
};

export type ServiceParticipant = {
  assignment: ServiceAssignmentRow;
  devotee: ServiceDevotee;
};

export type ServiceListItem = ServiceInstanceRow & {
  name: string;
  serviceType: ServiceType | null;
  filledSlots: number;
  participants: ServiceParticipant[];
  currentUserAssignment: ServiceAssignmentRow | null;
  currentUserOffer: ServiceOfferRow | null;
  /** Asked to take a place and yet to answer. Only ever added to, never removed. */
  pendingInvitees: ServiceDevotee[];
  postedByName: string | null;
};

export type ServiceDashboard = {
  serviceTypes: ServiceType[];
  devotees: ServiceDevotee[];
  services: ServiceListItem[];
  pendingOffers: Array<{
    offer: ServiceOfferRow;
    service: ServiceListItem;
    offeredByName: string;
  }>;
  recurringTemplates: Array<
    ServiceTemplateRow & {
      serviceType: ServiceType | null;
      name: string;
      assignees: Array<ServiceDevotee & { assignedDays: number[] }>;
    }
  >;
  pendingRecurringOffers: Array<{
    offer: ServiceOfferRow;
    template: ServiceTemplateRow & { serviceType: ServiceType | null; name: string };
    offeredByName: string;
    coveragePlan: ServiceCoveragePlanRow | null;
  }>;
  coverageRequests: Array<{
    exception: ServiceExceptionRow;
    exceptions: ServiceExceptionRow[];
    service: ServiceListItem;
    unavailableDevotee: ServiceDevotee;
    substituteDevotee: ServiceDevotee | null;
  }>;
  coveragePlans: ServiceCoveragePlanRow[];
  activeSessions: Array<{
    session: ServiceSessionRow;
    serviceType: ServiceType | null;
    name: string;
    devotee: ServiceDevotee;
  }>;
  activitySessions: Array<{
    session: ServiceSessionRow;
    serviceType: ServiceType | null;
    name: string;
    devotee: ServiceDevotee;
  }>;
  recurringInterests: Array<
    RecurringServiceInterestRow & {
      devotee: ServiceDevotee;
      desiredServiceTypes: ServiceType[];
    }
  >;
  /** Every registration RLS let this account see. */
  verifications: ServiceVerification[];
  /** This devotee's own registrations, in every state. */
  myVerifications: ServiceVerification[];
  /** Registrations waiting on the signed-in member's decision. */
  verificationInbox: ServiceVerification[];
  /** Alternative days a devotee suggested for a weekly invitation. */
  offerCounters: ServiceOfferCounterRow[];
  /**
   * Every decline or suggested time still owed an answer, on any seva this
   * account was allowed to read.
   *
   * Deliberately not narrowed to the seva this devotee posted. The SQL lets the
   * poster *or* a holder of `app.view_all` answer, and assembling the dashboard
   * has no role to test against — narrowing here hid a counter a Tech Admin or
   * the President was permitted to answer. `sevaNeedingMyAnswer` applies the
   * role, at the screens that know it.
   */
  sevaNeedingAnswer: Array<{
    kind: "declined" | "countered";
    offer: ServiceOfferRow;
    counter: ServiceOfferCounterRow | null;
    service: ServiceListItem;
    devoteeName: string;
  }>;
};

export type CreateRequirementInput = {
  serviceTypeId: string | null;
  customName: string | null;
  date: string;
  startTime: string;
  durationMinutes: number;
  slotsNeeded: number;
  participationMode: "open" | "invite_only";
  inviteeIds: string[];
};

export type RecurringServiceInterestInput = {
  skills: string;
  desiredServiceTypeIds: string[];
  otherService: string | null;
  availability: string;
  currentlyServing: boolean;
  currentServiceDetails: string | null;
};

export type CreateRecurringServiceInput = {
  serviceTypeId: string | null;
  customName: string | null;
  daysOfWeek: number[];
  startTime: string;
  durationMinutes: number;
  slotsNeeded: number;
  participationMode: "open" | "invite_only";
  startDate: string;
  endDate: string | null;
  inviteeIds: string[];
};

export type PlannedServiceSessionInput = {
  serviceTypeId: string | null;
  customName: string | null;
  qrToken?: string | null;
  startAt: string;
  endAt: string;
  locationText: string;
};

export type UpdateRecurringServiceInput = CreateRecurringServiceInput & {
  templateId: string;
};

export type CoverageScope = "occurrence" | "date_range" | "forever";

export type CoverageRangeInput = {
  exceptionId: string;
  devoteeId: string;
  scope: CoverageScope;
  dateFrom: string;
  dateTo: string | null;
};

export type WeeklyUnavailableInput = {
  templateId: string;
  scope: CoverageScope;
  dateFrom: string;
  dateTo: string | null;
  daysOfWeek: number[];
  reason: string;
};

// --- Member-verified seva -------------------------------------------------

export type ServiceVerificationStatus = "pending" | "verified" | "declined";

export type ServiceVerificationRow = {
  id: string;
  devotee_id: string;
  service_type_id: string | null;
  custom_name: string | null;
  start_at: string;
  end_at: string;
  location_text: string;
  verifier_id: string;
  status: ServiceVerificationStatus;
  review_note: string | null;
  service_instance_id: string | null;
  verified_by: string | null;
  created_at: string;
  responded_at: string | null;
};

export type ServiceVerification = ServiceVerificationRow & {
  name: string;
  devotee: ServiceDevotee | null;
  /** The member the devotee named. */
  verifier: ServiceDevotee | null;
  /** Who actually confirmed it — may be a Tech Admin or the President. */
  verifiedBy: ServiceDevotee | null;
};

/** Community Heads, Tech Admins and the President. */
export type SevaVerifier = {
  id: string;
  name: string;
  photo_url: string | null;
  role_name: string;
};

export type RequestVerificationInput = {
  serviceTypeId: string | null;
  customName: string | null;
  startAt: string;
  endAt: string;
  locationText: string;
  verifierId: string;
};

/** Completed seva uses the same fields, but a separate server operation. */
export type LogCompletedSevaInput = RequestVerificationInput;

// --- Weekly invitation counter-proposal -----------------------------------

export type ServiceOfferCounterStatus = "pending" | "approved" | "declined";

export type ServiceOfferCounterRow = {
  id: string;
  service_offer_id: string;
  devotee_id: string;
  proposed_days: number[];
  /** Set for a dated seva request; null for a weekly one. */
  proposed_date: string | null;
  proposed_start_time: string;
  proposed_duration_minutes: number;
  note: string | null;
  status: ServiceOfferCounterStatus;
  review_note: string | null;
  created_at: string;
  responded_at: string | null;
  responded_by: string | null;
};

export type ProposeAlternativeInput = {
  offerId: string;
  daysOfWeek: number[];
  startTime: string;
  durationMinutes: number;
  note: string | null;
};

// --- Seva clashes ---------------------------------------------------------

/**
 * One seva a devotee is already down for that overlaps a proposed window, as
 * `list_seva_clashes` returns it.
 *
 * `seva_name` is null with `name_visible` false when the caller may see that
 * the devotee is busy but not what they are busy with. Nothing may invent a
 * name to fill that gap.
 */
export type SevaClash = {
  service_instance_id: string;
  template_id: string | null;
  from_weekly_template: boolean;
  seva_name: string | null;
  name_visible: boolean;
  occurs_on: string;
  starts_at_local: string;
  ends_at_local: string;
  ends_next_day: boolean;
  starts_at: string;
  ends_at: string;
  status: string;
  assignment_status: string;
  is_substitute: boolean;
  overlap_minutes: number;
  overlap_starts_at: string;
  overlap_ends_at: string;
  covers_whole_request: boolean;
};

/** One "is this devotee free then?" question. */
export type SevaClashQuery = {
  devoteeId: string;
  /** Chicago calendar day, `yyyy-mm-dd`. */
  date: string;
  /** Chicago wall clock, `HH:MM:SS`. */
  startTime: string;
  durationMinutes: number;
  /**
   * The seva being asked about, when it already exists. Without it every check
   * made from a seva's own page reports that seva as a total clash with itself.
   */
  excludeInstanceId?: string | null;
};

// --- Seva nobody served ---------------------------------------------------

/** One place on one seva that 0068 closed because nobody served it. */
export type ClosedUnservedRow = {
  service_instance_id: string;
  seva_name: string;
  occurred_on: string;
  weekday: string;
  started_at_local: string;
  planned_minutes: number;
  is_recurring: boolean;
  posted_by: string | null;
  closed_at: string;
  devotee_id: string;
  devotee_name: string;
  assignment_status: string;
  attendance: string | null;
  points_status: string;
};

/** The same rows folded into one entry per seva, which is how they are read. */
export type ClosedUnservedSeva = {
  serviceInstanceId: string;
  name: string;
  occurredOn: string;
  weekday: string;
  startedAt: string;
  plannedMinutes: number;
  isRecurring: boolean;
  closedAt: string;
  places: Array<{
    devoteeId: string;
    name: string;
    attendance: string | null;
    assignmentStatus: string;
  }>;
};

/**
 * One weekly occurrence a devotee has finished and not yet answered for.
 *
 * A rota counts on completion alone, so this is never a bill to be paid — it
 * is an opportunity to say "I missed that one" and give the credit back.
 * Ignoring it changes nothing.
 */
export type WeeklySevaToAnswer = {
  assignment_id: string;
  service_instance_id: string;
  seva_name: string;
  /** "YYYY-MM-DD" */
  occurred_on: string;
  /** "HH:MM:SS" */
  started_at_local: string;
  duration_minutes: number;
};

/** What a devotee answered, for whoever set the rota up. */
export type WeeklySevaAnswer = {
  assignment_id: string;
  service_instance_id: string;
  devotee_id: string;
  devotee_name: string | null;
  devotee_photo_url: string | null;
  seva_name: string;
  occurred_on: string;
  started_at_local: string;
  answer: "served" | "absent" | "excused";
};
