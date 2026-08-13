import type { ServiceDashboard, ServiceVerification } from "./types";

/**
 * Whether a verified registration still counts as seva the devotee offered.
 *
 * Verifying writes a `service_instances` row with a place on it, and a
 * coordinator can afterwards mark that place absent or excused —
 * `seva_points_status` then calls it `not_served`. Every list built from
 * services asks that question; the registration lists never did, so the same
 * morning was credited in the hours report and disqualified everywhere else.
 *
 * Silence is not an absence. A registration with no instance, an instance
 * outside the dashboard's history window, or an instance carrying no place for
 * this devotee says nothing about them, and nothing is not a reason to strike a
 * verified offering off the record.
 */
export function registrationWasServed(
  dashboard: ServiceDashboard,
  registration: ServiceVerification,
) {
  const instanceId = registration.service_instance_id;
  if (!instanceId) return true;
  const service = (dashboard.services ?? []).find(
    (item) => item.id === instanceId,
  );
  const place = service?.participants?.find(
    (participant) => participant.devotee.id === registration.devotee_id,
  );
  if (!place) return true;
  return (
    place.assignment.attendance !== "absent" &&
    place.assignment.attendance !== "excused"
  );
}

/**
 * Where a registered seva belongs is decided by the clock alone, never by its
 * verification status:
 *
 *   start <= now < end   -> happening now
 *   now < start          -> upcoming
 *   now >= end           -> finished
 *
 * Verification decides who may see it, and whether it counts as completed.
 */
export type SevaTiming = "now" | "upcoming" | "finished";

export function sevaTiming(
  registration: Pick<ServiceVerification, "start_at" | "end_at">,
  now = new Date(),
): SevaTiming {
  const at = now.getTime();
  const start = Date.parse(registration.start_at);
  const end = Date.parse(registration.end_at);
  if (at < start) return "upcoming";
  if (at >= end) return "finished";
  return "now";
}

export type RegistrationScope = {
  userId: string | null;
  /** Community Head, Tech Admin and President may see the temple's seva. */
  seesEveryone: boolean;
};

/**
 * A registration is community information only once it has been verified.
 * Before that it belongs to the devotee who registered it (the member asked to
 * confirm it, and Tech Admin / President, are handled by row-level security —
 * this is the presentation-side rule).
 */
export function visibleRegistrations(
  dashboard: ServiceDashboard,
  scope: RegistrationScope,
): ServiceVerification[] {
  const all = dashboard.verifications ?? [];
  return all.filter((row) => {
    if (row.devotee_id === scope.userId) return true;
    return row.status === "verified" && scope.seesEveryone;
  });
}

/** Registered seva being served at this moment, for whoever may see it. */
export function registrationsHappeningNow(
  dashboard: ServiceDashboard,
  scope: RegistrationScope,
  now = new Date(),
) {
  return visibleRegistrations(dashboard, scope).filter(
    (row) => sevaTiming(row, now) === "now",
  );
}

/** Registered seva that has not started yet. */
export function upcomingRegistrations(
  dashboard: ServiceDashboard,
  scope: RegistrationScope,
  now = new Date(),
) {
  return visibleRegistrations(dashboard, scope)
    .filter((row) => sevaTiming(row, now) === "upcoming")
    .sort((left, right) => left.start_at.localeCompare(right.start_at));
}

/**
 * Finished *and* verified. An unverified registration whose time has passed is
 * never presented as completed seva — it stays in "waiting to be verified"
 * until somebody confirms it.
 */
export function completedRegistrations(
  dashboard: ServiceDashboard,
  scope: RegistrationScope,
  now = new Date(),
) {
  return visibleRegistrations(dashboard, scope)
    .filter(
      (row) => row.status === "verified" && sevaTiming(row, now) === "finished",
    )
    .sort((left, right) => right.start_at.localeCompare(left.start_at));
}

/**
 * The devotee's own registrations still awaiting a decision, newest first.
 * Declined ones stay here so they can be sent to somebody else.
 */
export function myUnverifiedRegistrations(
  dashboard: ServiceDashboard,
  userId: string | null,
) {
  return (dashboard.myVerifications ?? [])
    .filter((row) => row.devotee_id === userId && row.status !== "verified")
    .sort((left, right) => right.created_at.localeCompare(left.created_at));
}

/** Who may take a registration off the list. */
export function canRemoveRegistration(
  registration: ServiceVerification,
  userId: string | null,
  canManage: boolean,
) {
  return registration.devotee_id === userId || canManage;
}

/**
 * Verifying a registration also writes a service_instances row, so the same
 * seva would otherwise appear twice: once as a registration card and once as a
 * scheduled-service card. The instance ids below belong to registrations and
 * are filtered out of the service-driven lists.
 */
export function registrationInstanceIds(dashboard: ServiceDashboard) {
  return new Set(
    (dashboard.verifications ?? []).flatMap((row) =>
      row.service_instance_id ? [row.service_instance_id] : [],
    ),
  );
}
