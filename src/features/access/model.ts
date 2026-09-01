export const accessRoles = [
  "president",
  "tech",
  "core",
  "volunteer",
  "devotee",
] as const;

export type AccessRole = (typeof accessRoles)[number];

export type AccessPermission =
  | "access.review_requests"
  | "access.manage_any"
  | "app.view_all"
  | "services.view_all"
  | "services.participate"
  | "services.track_live"
  | "services.report_unavailable"
  | "services.respond_to_offer"
  | "services.post_requirement"
  | "services.offer_assignment"
  | "services.resolve_coverage"
  | "services.manage_recurring"
  | "services.oversee_activity"
  | "services.complete_requirement"
  | "services.delete_any"
  | "services.export_reports";

const participantPermissions: AccessPermission[] = [
  "services.participate",
  "services.track_live",
  "services.report_unavailable",
  "services.respond_to_offer",
];

// A Devotee sees the open needs they can join and their own seva. The
// community schedule and everyone's completed history belong to coordinators.
const devoteePermissions: AccessPermission[] = [...participantPermissions];

const serviceCoordinatorPermissions: AccessPermission[] = [
  ...devoteePermissions,
  "services.view_all",
  "services.post_requirement",
  "services.offer_assignment",
  "services.oversee_activity",
  "services.complete_requirement",
];

const recurringCoordinatorPermissions: AccessPermission[] = [
  ...serviceCoordinatorPermissions,
  "services.resolve_coverage",
  "services.manage_recurring",
];

export const permissionsByRole: Record<AccessRole, AccessPermission[]> = {
  president: [
    "access.review_requests",
    "app.view_all",
    ...recurringCoordinatorPermissions,
    "services.delete_any",
    "services.export_reports",
  ],
  tech: [
    "access.review_requests",
    // 202609010103: the one level that can appoint or revoke every other one,
    // the President and Tech Admin included. Deliberately not the President's.
    "access.manage_any",
    "app.view_all",
    ...recurringCoordinatorPermissions,
    "services.delete_any",
    "services.export_reports",
  ],
  core: recurringCoordinatorPermissions,
  volunteer: [
    ...participantPermissions,
    "services.post_requirement",
    // A Volunteer may ask particular devotees when posting a seva request.
    "services.offer_assignment",
  ],
  devotee: devoteePermissions,
};

export const accessRoleLabels: Record<AccessRole, string> = {
  president: "President",
  tech: "Tech Admin",
  core: "Community Head",
  volunteer: "Volunteer",
  devotee: "Devotee",
};

/**
 * Every permission said the way a devotee would say it. The keys are the
 * temple's vocabulary; this is the congregation's. Shared rather than written
 * per screen so the level a devotee is offered and the level a coordinator
 * appoints them to are described in the same words.
 */
export const accessPermissionSummaries: Record<AccessPermission, string> = {
  "access.review_requests":
    "Approve or decline access requests from other devotees",
  "access.manage_any":
    "Give or take back any access level, including President and Tech Admin",
  "app.view_all": "Reach every part of the app",
  "services.view_all":
    "See the whole temple’s seva schedule, not only your own",
  "services.participate": "Join open seva requests",
  "services.track_live": "Follow a seva while it is happening",
  "services.report_unavailable":
    "Say when you cannot make a seva you agreed to",
  "services.respond_to_offer":
    "Accept or decline when someone asks you to help",
  "services.post_requirement": "Post seva requests for the community",
  "services.offer_assignment": "Ask particular devotees to take a seva",
  "services.resolve_coverage":
    "Arrange cover when someone cannot make their seva",
  "services.manage_recurring": "Create and manage weekly seva",
  "services.oversee_activity": "See the whole temple’s seva activity",
  "services.complete_requirement": "Close a seva once it has been done",
  "services.delete_any": "Remove any seva request from the schedule",
  "services.export_reports": "Export seva records for the temple",
};

/** The only two levels the app itself can grant. */
export type GrantableAccessRole = Extract<AccessRole, "volunteer" | "core">;

export const grantableAccessRoles: GrantableAccessRole[] = [
  "volunteer",
  "core",
];

/** What the level is for, in one line, ahead of the list of what it adds. */
export const grantableRoleSummaries: Record<GrantableAccessRole, string> = {
  volunteer:
    "A devotee who posts what the temple needs and asks others to help with it.",
  core: "A coordinator who keeps the temple’s weekly seva running, arranges cover when a devotee cannot make theirs, and closes seva once it is done.",
};

/**
 * Every level the app can appoint somebody to. The bottom two are open to any
 * coordinator; the top two need `access.manage_any`, which only the Tech Admin
 * holds. Devotee is absent on purpose — revoking is the road back down, and it
 * writes down that access was taken away rather than merely given differently.
 */
export type AppointableAccessRole = Exclude<AccessRole, "devotee">;

export const appointableAccessRoles: AppointableAccessRole[] = [
  "volunteer",
  "core",
  "tech",
  "president",
];

export const appointableRoleSummaries: Record<AppointableAccessRole, string> = {
  ...grantableRoleSummaries,
  tech: "The person who keeps the app running — and the only level that can give or take back any other, this one included.",
  president:
    "The temple's leadership view: everything a Community Head can do, plus every part of the app.",
};

/** The ladder to offer, given what the server said this coordinator may reach. */
export function appointableAccessRolesFor(
  mayAppointAny: boolean,
): AppointableAccessRole[] {
  return mayAppointAny ? appointableAccessRoles : grantableAccessRoles;
}

/** What moving up to `to` would add to somebody who holds `from` today. */
export function accessPermissionsGained(from: AccessRole, to: AccessRole) {
  const held = permissionsByRole[from];
  return permissionsByRole[to].filter((permission) => !held.includes(permission));
}

export function isAccessRole(value: unknown): value is AccessRole {
  return (
    typeof value === "string" &&
    (accessRoles as readonly string[]).includes(value)
  );
}

export function hasAccessPermission(
  role: AccessRole,
  permission: AccessPermission,
) {
  return permissionsByRole[role].includes(permission);
}

export function getRequestableAccessRoles(role: AccessRole): AccessRole[] {
  if (role === "devotee") return ["volunteer", "core"];
  if (role === "volunteer") return ["core"];
  return [];
}

export function canRequestAccessRole(
  currentRole: AccessRole,
  requestedRole: AccessRole,
) {
  return getRequestableAccessRoles(currentRole).includes(requestedRole);
}
