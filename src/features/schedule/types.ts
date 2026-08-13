import type {
  ServiceCategory,
  ServiceInstanceStatus,
} from "../services/types";

/**
 * The timetable's rows, exactly as migration 0069 returns them.
 *
 * Column names are left in the server's snake_case rather than mapped: every
 * one of them is asserted in a test against the RPC's own signature, and a
 * mapping layer is one more place for the two to drift apart silently.
 */

/**
 * One devotee on one occurrence, after coverage swaps have been applied by the
 * server. `assignmentId` is null for a substitute on an occurrence generated
 * after their acceptance — they are genuinely serving it, there is simply no
 * assignment row of their own to point at.
 */
export type SevaScheduleServer = {
  devoteeId: string;
  name: string;
  assignmentId: string | null;
  assignmentStatus: string | null;
  attendance: string | null;
  pointsStatus: string | null;
  isSubstitute: boolean;
  /** Null when the reader may not be told whose Thursday this was. */
  coveringForDevoteeId: string | null;
  coveringForName: string | null;
};

export type SevaScheduleOccurrence = {
  service_instance_id: string;
  /** Null when the reader may not see the weekly seva behind this occurrence. */
  template_id: string | null;
  from_weekly_template: boolean;
  seva_name: string;
  service_type_id: string | null;
  service_category: ServiceCategory | null;
  occurs_on: string;
  /** 0 = Sunday, Postgres dow. */
  day_of_week: number;
  starts_at_local: string;
  ends_at_local: string;
  ends_next_day: boolean;
  duration_minutes: number;
  starts_at: string;
  ends_at: string;
  status: ServiceInstanceStatus;
  nobody_served: boolean;
  participation_mode: "open" | "invite_only";
  posted_by: string | null;
  slots_needed: number;
  filled_slots: number;
  open_slots: number;
  /** False means: draw the block and the reader's own place, name nobody else. */
  roster_visible: boolean;
  /** Always an array, never null, sorted by name. */
  servers: SevaScheduleServer[];
};

export type TempleProgrammeOccurrence = {
  programme_id: string;
  kind: "temple_programme";
  name: string;
  occurs_on: string;
  day_of_week: number;
  starts_at_local: string;
  /** Null where the temple named a start and no end. */
  ends_at_local: string | null;
  duration_minutes: number | null;
  starts_at: string;
  ends_at: string | null;
  sort_order: number;
};

export type TimetableHours = {
  day_starts_at: string;
  day_ends_at: string;
};

/**
 * Why the timetable has nothing to draw. The temple's whole reason for the
 * server raising rather than answering with zero rows: a grid must be able to
 * tell "nobody serves this week" from "this is not yours to read".
 */
export type ScheduleFailure =
  | "denied"
  | "window"
  | "unavailable"
  | "offline"
  | "unknown";

/** A block's colour, by what kind of seva it is. */
export const categoryTone: Record<ServiceCategory | "unknown", {
  fill: string;
  border: string;
  text: string;
}> = {
  kitchen: { fill: "bg-peacockSoft", border: "border-peacock/30", text: "text-peacock" },
  cleaning: { fill: "bg-indigoSoft", border: "border-indigo/25", text: "text-indigo" },
  "deity-worship": {
    fill: "bg-marigoldSoft",
    border: "border-marigold/40",
    text: "text-stone",
  },
  event: { fill: "bg-vermilionSoft", border: "border-vermilion/30", text: "text-vermilion" },
  other: { fill: "bg-sandalwood", border: "border-border", text: "text-stone" },
  unknown: { fill: "bg-sandalwood", border: "border-border", text: "text-stone" },
};

export function toneForCategory(category: ServiceCategory | null) {
  return categoryTone[category ?? "unknown"] ?? categoryTone.unknown;
}

export const categoryLabels: Record<ServiceCategory, string> = {
  kitchen: "Kitchen",
  cleaning: "Cleaning",
  "deity-worship": "Deity worship",
  event: "Event",
  other: "Other",
};
