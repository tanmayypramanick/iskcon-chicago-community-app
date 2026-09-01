import { getSupabaseClient } from "../../lib/supabase";
import {
  isAccessRole,
  type AccessRole,
  type AppointableAccessRole,
} from "./model";

// `children` is jsonb: the read gives back whatever was stored, so the row
// holds it untyped and it is checked before it reaches the rest of the app.
type ProfileRow = {
  id: string;
  name: string;
  email: string;
  phone: string | null;
  photo_url: string | null;
  ashram_status: string | null;
  role_id: string;
  joined_at: string;
} & Omit<ProfileDetails, "children"> & { children: unknown };

const childGenders = ["male", "female", "prefer_not_to_say"] as const;
export type ChildGender = (typeof childGenders)[number];

export const templeSinceUnits = ["days", "weeks", "months", "years"] as const;
export type TempleSinceUnit = (typeof templeSinceUnits)[number];

/** One child of the devotee, as the family section collects them. */
export type ChildDetail = {
  name: string;
  age: number | null;
  gender: ChildGender | null;
  practices: boolean;
  practicing_since: string | null;
  initiated: boolean;
  initiation_date: string | null;
  diksha_guru: string | null;
};

function parseTempleSinceUnit(value: unknown): TempleSinceUnit | null {
  return templeSinceUnits.find((unit) => unit === value) ?? null;
}

function parseChildren(value: unknown): ChildDetail[] {
  if (!Array.isArray(value)) return [];
  return value.flatMap((entry) => {
    if (!entry || typeof entry !== "object") return [];
    const child = entry as Record<string, unknown>;
    return [
      {
        name: typeof child.name === "string" ? child.name : "",
        age:
          typeof child.age === "number" && Number.isFinite(child.age)
            ? child.age
            : null,
        gender: childGenders.find((option) => option === child.gender) ?? null,
        practices: child.practices === true,
        practicing_since:
          typeof child.practicing_since === "string"
            ? child.practicing_since
            : null,
        initiated: child.initiated === true,
        initiation_date:
          typeof child.initiation_date === "string"
            ? child.initiation_date
            : null,
        diksha_guru:
          typeof child.diksha_guru === "string" ? child.diksha_guru : null,
      },
    ];
  });
}

/** What a devotee tells the temple about themselves. All optional. */
export type ProfileDetails = {
  date_of_birth: string | null;
  birth_place: string | null;
  address: string | null;
  spiritual_mentor: string | null;
  is_initiated: boolean;
  initiation_date: string | null;
  diksha_guru: string | null;
  has_first_initiation: boolean;
  first_initiation_date: string | null;
  first_diksha_guru: string | null;
  has_second_initiation: boolean;
  second_initiation_date: string | null;
  second_diksha_guru: string | null;
  profile_updated_at: string | null;
  emergency_contact_name: string | null;
  emergency_contact_phone: string | null;
  dietary_notes: string | null;
  health_notes: string | null;
  preferred_language: string | null;
  occupation: string | null;
  joined_temple_on: string | null;
  gender: "male" | "female" | "prefer_not_to_say" | null;
  marital_status: "single" | "married" | "widowed" | "prefer_not_to_say" | null;
  spouse_name: string | null;
  children_count: number | null;
  children: ChildDetail[];
  temple_since_amount: number | null;
  temple_since_unit: TempleSinceUnit | null;
  chanting_rounds: number | null;
  languages_spoken: string | null;
  how_they_found_us: string | null;
  can_offer_lift: boolean;
  can_host_programs: boolean;
  skills: string | null;
};

type RoleRow = {
  id: string;
  name: string;
};

type AccessRequestRow = {
  id: string;
  requester_id: string;
  approver_id: string | null;
  requested_role_id: string;
  status: "pending" | "approved" | "denied";
  created_at: string;
  reviewed_at: string | null;
  reviewed_by: string | null;
};

export type AccessProfile = Omit<ProfileRow, "role_id" | keyof ProfileDetails> & {
  roleId: string;
  role: AccessRole;
  details: ProfileDetails;
  /** 0–100, computed in the database so every screen agrees. */
  completion: number;
  /**
   * Whether the read actually reached the detail columns. False means the
   * deployed database predates them, so every `details` answer below is a
   * default rather than something the devotee did or did not give.
   */
  detailsReadable: boolean;
};

/** The six answers the temple asks for before the app can be used. */
export const requiredProfileFields = [
  "photo",
  "name",
  "phone",
  "date_of_birth",
  "occupation",
  "gender",
] as const;

export type RequiredProfileField = (typeof requiredProfileFields)[number];

export const requiredProfileFieldLabels: Record<RequiredProfileField, string> = {
  photo: "Profile photo",
  name: "Full name",
  phone: "Contact number",
  date_of_birth: "Date of birth",
  occupation: "Profession",
  gender: "Gender",
};

/** Punctuation and spacing are the devotee's business; digits are the temple's. */
function hasDialableDigits(value: string | null) {
  return (value ?? "").replace(/[^0-9]/g, "").length >= 7;
}

/**
 * Which of the six are still unanswered, read from the profile the server
 * returned rather than from anything remembered on the phone.
 *
 * Nothing is reported missing when the detail columns could not be read: the
 * three answers they hold cannot be judged, and the functions that would save
 * them arrive in the same migrations, so gating there would be a door with no
 * key. A database behind on migrations must not lock a temple out of its app.
 */
export function missingRequiredProfileFields(
  profile: AccessProfile,
): RequiredProfileField[] {
  if (!profile.detailsReadable) return [];

  const details = profile.details;
  const missing: RequiredProfileField[] = [];
  if (!profile.photo_url?.trim()) missing.push("photo");
  if (profile.name.trim().length < 2) missing.push("name");
  if (!hasDialableDigits(profile.phone)) missing.push("phone");
  if (!details.date_of_birth) missing.push("date_of_birth");
  if (!details.occupation?.trim()) missing.push("occupation");
  if (!details.gender) missing.push("gender");
  return missing;
}

export type AccessRequestItem = {
  id: string;
  requesterId: string;
  /** The devotee this request named, who may answer it whatever their role. */
  approverId: string | null;
  requesterName: string;
  currentRole: AccessRole;
  requestedRole: AccessRole;
  status: AccessRequestRow["status"];
  createdAt: string;
};

function requireAccessRole(value: unknown): AccessRole {
  if (!isAccessRole(value)) {
    throw new Error("Supabase returned an unsupported access level.");
  }
  return value;
}

export async function fetchCurrentAccessProfile(): Promise<AccessProfile> {
  const supabase = getSupabaseClient();
  const { data: authData, error: authError } = await supabase.auth.getUser();
  if (authError) throw authError;
  if (!authData.user) throw new Error("A signed-in user is required.");

  const BASE_COLUMNS = "id,name,email,phone,photo_url,ashram_status,role_id,joined_at";
  const DETAIL_COLUMNS =
    "date_of_birth,birth_place,address,spiritual_mentor,is_initiated," +
    "initiation_date,diksha_guru,has_first_initiation," +
    "first_initiation_date,first_diksha_guru,has_second_initiation," +
    "second_initiation_date,second_diksha_guru,profile_updated_at," +
    "emergency_contact_name,emergency_contact_phone,dietary_notes," +
    "health_notes,preferred_language,occupation,joined_temple_on," +
    "gender,marital_status,spouse_name,children_count,chanting_rounds," +
    "languages_spoken,how_they_found_us,can_offer_lift,can_host_programs,skills";
  const FAMILY_COLUMNS = "children,temple_since_amount,temple_since_unit";

  // The detail columns arrive in migration 0030 and the family ones later
  // still. Until each is applied they do not exist, and asking for them fails
  // the whole request — which would blank the devotee's own name and access
  // level, not just their birthday. So the read starts as wide as the app can
  // use and is narrowed one step at a time until the deployed schema answers.
  const columnSets = [
    `${BASE_COLUMNS},${DETAIL_COLUMNS},${FAMILY_COLUMNS}`,
    `${BASE_COLUMNS},${DETAIL_COLUMNS}`,
    BASE_COLUMNS,
  ];

  let profile: ProfileRow | null = null;
  let detailsReadable = false;
  for (const columns of columnSets) {
    const attempt = await supabase
      .from("users")
      .select(columns)
      .eq("id", authData.user.id)
      .maybeSingle<ProfileRow>();

    if (!attempt.error) {
      profile = attempt.data;
      // Which step answered is worth keeping: falling all the way back means
      // the details below are defaults, not answers, and callers that decide
      // something from them need to know the difference.
      detailsReadable = columns !== BASE_COLUMNS;
      break;
    }

    const missingColumn = ["42703", "PGRST204"].includes(
      attempt.error.code ?? "",
    );
    if (!missingColumn || columns === BASE_COLUMNS) throw attempt.error;
  }

  if (!profile) throw new Error("Your profile could not be found.");

  const { data: role, error: roleError } = await supabase
    .from("roles")
    .select("id,name")
    .eq("id", profile.role_id)
    .single<RoleRow>();

  if (roleError) throw roleError;

  // One definition of "complete", held in the database, so this screen and the
  // coordinator's list can never disagree about what a percentage means.
  // A profile must still load if that function is not deployed yet, so a
  // missing percentage degrades to zero rather than failing the whole screen.
  let completion: unknown = 0;
  try {
    const result = await supabase.rpc("profile_completion", {
      p_user_id: authData.user.id,
    });
    completion = result?.error ? 0 : result?.data;
  } catch {
    completion = 0;
  }

  return {
    id: profile.id,
    name: profile.name,
    email: profile.email,
    phone: profile.phone,
    photo_url: profile.photo_url,
    ashram_status: profile.ashram_status,
    joined_at: profile.joined_at,
    roleId: profile.role_id,
    role: requireAccessRole(role.name),
    details: {
      date_of_birth: profile.date_of_birth ?? null,
      birth_place: profile.birth_place ?? null,
      address: profile.address ?? null,
      spiritual_mentor: profile.spiritual_mentor ?? null,
      is_initiated: profile.is_initiated ?? false,
      initiation_date: profile.initiation_date ?? null,
      diksha_guru: profile.diksha_guru ?? null,
      has_first_initiation: profile.has_first_initiation ?? false,
      first_initiation_date: profile.first_initiation_date ?? null,
      first_diksha_guru: profile.first_diksha_guru ?? null,
      has_second_initiation: profile.has_second_initiation ?? false,
      second_initiation_date: profile.second_initiation_date ?? null,
      second_diksha_guru: profile.second_diksha_guru ?? null,
      profile_updated_at: profile.profile_updated_at ?? null,
      emergency_contact_name: profile.emergency_contact_name ?? null,
      emergency_contact_phone: profile.emergency_contact_phone ?? null,
      dietary_notes: profile.dietary_notes ?? null,
      health_notes: profile.health_notes ?? null,
      preferred_language: profile.preferred_language ?? null,
      occupation: profile.occupation ?? null,
      joined_temple_on: profile.joined_temple_on ?? null,
      gender: profile.gender ?? null,
      marital_status: profile.marital_status ?? null,
      spouse_name: profile.spouse_name ?? null,
      children_count: profile.children_count ?? null,
      children: parseChildren(profile.children),
      temple_since_amount: profile.temple_since_amount ?? null,
      temple_since_unit: parseTempleSinceUnit(profile.temple_since_unit),
      chanting_rounds: profile.chanting_rounds ?? null,
      languages_spoken: profile.languages_spoken ?? null,
      how_they_found_us: profile.how_they_found_us ?? null,
      can_offer_lift: profile.can_offer_lift ?? false,
      can_host_programs: profile.can_host_programs ?? false,
      skills: profile.skills ?? null,
    },
    completion: typeof completion === "number" ? completion : 0,
    detailsReadable,
  };
}

export type ProfileDetailsInput = {
  name: string;
  phone: string | null;
  dateOfBirth: string | null;
  birthPlace: string | null;
  address: string | null;
  spiritualMentor: string | null;
  isInitiated: boolean;
  initiationDate: string | null;
  dikshaGuru: string | null;
  hasFirstInitiation: boolean;
  firstInitiationDate: string | null;
  firstDikshaGuru: string | null;
  hasSecondInitiation: boolean;
  secondInitiationDate: string | null;
  secondDikshaGuru: string | null;
};

export async function updateMyProfile(input: ProfileDetailsInput) {
  const { error } = await getSupabaseClient().rpc("update_my_profile", {
    p_name: input.name,
    p_phone: input.phone,
    p_date_of_birth: input.dateOfBirth,
    p_birth_place: input.birthPlace,
    p_address: input.address,
    p_spiritual_mentor: input.spiritualMentor,
    p_is_initiated: input.isInitiated,
    p_initiation_date: input.initiationDate,
    p_diksha_guru: input.dikshaGuru,
    p_has_first_initiation: input.hasFirstInitiation,
    p_first_initiation_date: input.firstInitiationDate,
    p_first_diksha_guru: input.firstDikshaGuru,
    p_has_second_initiation: input.hasSecondInitiation,
    p_second_initiation_date: input.secondInitiationDate,
    p_second_diksha_guru: input.secondDikshaGuru,
  });
  if (error) throw error;
}

/**
 * Changing the sign-in address goes through the auth provider, not the profile
 * table: the new address has to be proved before it takes effect, or anyone
 * could point an account at an inbox they do not own.
 */
export async function requestEmailChange(newEmail: string) {
  const { error } = await getSupabaseClient().auth.updateUser({
    email: newEmail.trim(),
  });
  if (error) throw error;
}

/**
 * The extras and community functions arrive with migrations 0033 and 0034,
 * which a temple's database may not have had applied yet.
 *   PGRST202 / 42883 — that function does not exist
 * Treated as "nothing to store there yet" so a devotee can still save the
 * details the deployed database does understand.
 */
function missingFunctionTolerated(error: { code?: string } | null) {
  if (!error) return null;
  return ["PGRST202", "42883"].includes(error.code ?? "") ? null : error;
}

export type ProfileExtrasInput = {
  emergencyContactName: string | null;
  emergencyContactPhone: string | null;
  dietaryNotes: string | null;
  healthNotes: string | null;
  preferredLanguage: string | null;
  occupation: string | null;
  joinedTempleOn: string | null;
  templeSinceAmount: number | null;
  templeSinceUnit: TempleSinceUnit | null;
};

export async function updateMyProfileExtras(input: ProfileExtrasInput) {
  const { error } = await getSupabaseClient().rpc("update_my_profile_extras", {
    p_emergency_contact_name: input.emergencyContactName,
    p_emergency_contact_phone: input.emergencyContactPhone,
    p_dietary_notes: input.dietaryNotes,
    p_health_notes: input.healthNotes,
    p_preferred_language: input.preferredLanguage,
    p_occupation: input.occupation,
    p_joined_temple_on: input.joinedTempleOn,
    p_temple_since_amount: input.templeSinceAmount,
    p_temple_since_unit: input.templeSinceUnit,
  });
  const unexpected = missingFunctionTolerated(error);
  if (unexpected) throw unexpected;
}

export type ProfileCommunityInput = {
  gender: "male" | "female" | "prefer_not_to_say" | null;
  maritalStatus: "single" | "married" | "widowed" | "prefer_not_to_say" | null;
  spouseName: string | null;
  childrenCount: number | null;
  children: ChildDetail[];
  chantingRounds: number | null;
  languagesSpoken: string | null;
  howTheyFoundUs: string | null;
  canOfferLift: boolean;
  canHostPrograms: boolean;
  skills: string | null;
};

export async function updateMyProfileCommunity(input: ProfileCommunityInput) {
  const { error } = await getSupabaseClient().rpc(
    "update_my_profile_community",
    {
      p_gender: input.gender,
      p_marital_status: input.maritalStatus,
      p_spouse_name: input.spouseName,
      p_children_count: input.childrenCount,
      p_chanting_rounds: input.chantingRounds,
      p_languages_spoken: input.languagesSpoken,
      p_how_they_found_us: input.howTheyFoundUs,
      p_can_offer_lift: input.canOfferLift,
      p_can_host_programs: input.canHostPrograms,
      p_skills: input.skills,
      p_children: input.children,
    },
  );
  const unexpected = missingFunctionTolerated(error);
  if (unexpected) throw unexpected;
}

export type DevoteeProfileRow = {
  id: string;
  name: string;
  email: string;
  phone: string | null;
  photo_url: string | null;
  role_name: string;
  joined_at: string;
  date_of_birth: string | null;
  birth_place: string | null;
  address: string | null;
  spiritual_mentor: string | null;
  is_initiated: boolean;
  initiation_date: string | null;
  diksha_guru: string | null;
  has_first_initiation: boolean;
  first_initiation_date: string | null;
  first_diksha_guru: string | null;
  has_second_initiation: boolean;
  second_initiation_date: string | null;
  second_diksha_guru: string | null;
  profile_updated_at: string | null;
  completion: number;
};

export async function fetchDevoteeProfiles(): Promise<DevoteeProfileRow[]> {
  const { data, error } = await getSupabaseClient().rpc(
    "list_devotee_profiles",
  );
  if (error) throw error;
  return (data ?? []) as DevoteeProfileRow[];
}

export type MyAccessRequestRow = {
  id: string;
  requester_id: string;
  requester_name: string;
  requester_photo_url: string | null;
  requester_role: string;
  requested_role: string;
  status: "pending" | "approved" | "denied";
  message: string | null;
  review_note: string | null;
  created_at: string;
  reviewed_at: string | null;
  approver_id: string | null;
  approver_name: string | null;
  reviewed_by_name: string | null;
};

export async function fetchMyAccessRequests(): Promise<MyAccessRequestRow[]> {
  const { data, error } = await getSupabaseClient().rpc(
    "list_my_access_requests",
  );
  if (error) throw error;
  return (data ?? []) as MyAccessRequestRow[];
}

export async function fetchPendingAccessRequests(): Promise<
  AccessRequestItem[]
> {
  const supabase = getSupabaseClient();
  const { data, error } = await supabase
    .from("access_requests")
    .select(
      "id,requester_id,approver_id,requested_role_id,status,created_at,reviewed_at,reviewed_by",
    )
    .eq("status", "pending")
    .order("created_at", { ascending: true })
    .returns<AccessRequestRow[]>();

  if (error) throw error;
  if (!data.length) return [];

  const requesterIds = [...new Set(data.map((item) => item.requester_id))];
  const requestedRoleIds = [
    ...new Set(data.map((item) => item.requested_role_id)),
  ];

  const { data: requesters, error: requesterError } = await supabase
    .from("users")
    .select(
      "id,name,email,phone,photo_url,ashram_status,role_id,joined_at," +
        "date_of_birth,birth_place,address,spiritual_mentor,is_initiated," +
        "initiation_date,diksha_guru,has_first_initiation," +
        "first_initiation_date,first_diksha_guru,has_second_initiation," +
        "second_initiation_date,second_diksha_guru,profile_updated_at",
    )
    .in("id", requesterIds)
    .returns<ProfileRow[]>();
  if (requesterError) throw requesterError;

  const currentRoleIds = requesters.map((requester) => requester.role_id);
  const roleIds = [...new Set([...requestedRoleIds, ...currentRoleIds])];
  const { data: roleRows, error: rolesError } = await supabase
    .from("roles")
    .select("id,name")
    .in("id", roleIds)
    .returns<RoleRow[]>();
  if (rolesError) throw rolesError;

  const requesterById = new Map(
    requesters.map((requester) => [requester.id, requester]),
  );
  const roleById = new Map(roleRows.map((role) => [role.id, role.name]));

  return data.map((request) => {
    const requester = requesterById.get(request.requester_id);
    if (!requester) {
      throw new Error("An access request is missing its requester profile.");
    }

    return {
      id: request.id,
      requesterId: request.requester_id,
      approverId: request.approver_id ?? null,
      requesterName: requester.name,
      currentRole: requireAccessRole(roleById.get(requester.role_id)),
      requestedRole: requireAccessRole(roleById.get(request.requested_role_id)),
      status: request.status,
      createdAt: request.created_at,
    };
  });
}

export type AccessApprover = {
  id: string;
  name: string;
  photo_url: string | null;
  role_name: string;
};

/** The Community Heads, Tech Admins and President a request may be addressed to. */
export async function fetchAccessApprovers(): Promise<AccessApprover[]> {
  const { data, error } = await getSupabaseClient().rpc(
    "list_access_approvers",
  );
  if (error) throw error;
  return (data ?? []) as AccessApprover[];
}

export async function createAccessRequest(
  requestedRole: AccessRole,
  message: string,
  approverId: string,
) {
  if (requestedRole !== "volunteer" && requestedRole !== "core") {
    throw new Error("Only Volunteer or Community Head access can be requested.");
  }

  const { error } = await getSupabaseClient().rpc("create_access_request", {
    requested_role_name: requestedRole,
    p_message: message,
    p_approver_id: approverId,
  });
  if (error) throw error;
}

/**
 * The appointment record arrives with migration 0047, which a temple's
 * database may not have had applied yet.
 *   PGRST202 / 42883 — that function does not exist
 *   42P01 / PGRST205 — that relation does not exist
 * Reads treat that as "no record yet" so a profile still opens; the writes
 * below deliberately do not, because there is nothing to appoint until the
 * migration has run and a silent no-op would look like the tap worked.
 */
function isAccessRecordPending(error: { code?: string } | null) {
  return ["PGRST202", "42883", "42P01", "PGRST205"].includes(error?.code ?? "");
}

export type AccessAppointment = {
  id: string;
  devotee_id: string;
  devotee_name: string;
  devotee_photo_url: string | null;
  role_name: string;
  role_label: string;
  appointed_by: string | null;
  appointed_by_name: string | null;
  appointed_at: string;
  note: string | null;
  revoked_by: string | null;
  revoked_by_name: string | null;
  revoked_at: string | null;
  revoke_note: string | null;
  revoke_reason: "revoked" | "superseded" | null;
  source: "appointment" | "request" | "backfill";
  access_request_id: string | null;
  is_active: boolean;
  /** Computed per row by the database. Never re-derived on the client. */
  can_revoke: boolean;
};

export type DevoteeAccessGrant = {
  devotee_id: string;
  devotee_name: string;
  role_name: string;
  role_label: string;
  appointed_by: string | null;
  appointed_by_name: string | null;
  appointed_at: string;
  note: string | null;
  source: "appointment" | "request" | "backfill";
  access_request_id: string | null;
};

/** Whether to offer the appointing controls. Asked of the server, not guessed. */
export async function fetchMayAppointAccess(): Promise<boolean> {
  const { data, error } = await getSupabaseClient().rpc("may_appoint_access");
  if (error) {
    if (isAccessRecordPending(error)) return false;
    throw error;
  }
  return data === true;
}

/**
 * Whether the whole ladder is theirs to move people up and down — President and
 * Tech Admin included. Arrives with 202609010103; a database without it answers
 * "no", which is what every database meant before that migration existed.
 */
export async function fetchMayAppointAnyAccess(): Promise<boolean> {
  const { data, error } = await getSupabaseClient().rpc(
    "may_appoint_any_access",
  );
  if (error) {
    if (isAccessRecordPending(error)) return false;
    throw error;
  }
  return data === true;
}

export async function fetchAccessAppointments(
  devoteeId: string | null = null,
): Promise<AccessAppointment[]> {
  const { data, error } = await getSupabaseClient().rpc(
    "list_access_appointments",
    { p_devotee_id: devoteeId },
  );
  if (error) {
    if (isAccessRecordPending(error)) return [];
    throw error;
  }
  return (data ?? []) as AccessAppointment[];
}

export async function fetchDevoteeAccessGrants(
  devoteeId: string | null = null,
): Promise<DevoteeAccessGrant[]> {
  const { data, error } = await getSupabaseClient().rpc(
    "list_devotee_access_grants",
    { p_devotee_id: devoteeId },
  );
  if (error) {
    if (isAccessRecordPending(error)) return [];
    throw error;
  }
  return (data ?? []) as DevoteeAccessGrant[];
}

export async function appointAccess(
  devoteeId: string,
  roleName: AppointableAccessRole,
  note: string | null,
) {
  const { error } = await getSupabaseClient().rpc("appoint_access", {
    p_devotee_id: devoteeId,
    p_role_name: roleName,
    p_note: note?.trim() || null,
  });
  if (error) throw error;
}

export async function revokeAccess(devoteeId: string, note: string | null) {
  const { error } = await getSupabaseClient().rpc("revoke_access", {
    p_devotee_id: devoteeId,
    p_note: note?.trim() || null,
  });
  if (error) throw error;
}

export async function reviewAccessRequest(
  requestId: string,
  decision: "approved" | "denied",
  note?: string | null,
) {
  const { error } = await getSupabaseClient().rpc("review_access_request", {
    access_request_id: requestId,
    decision,
    p_note: note ?? null,
  });
  if (error) throw error;
}
