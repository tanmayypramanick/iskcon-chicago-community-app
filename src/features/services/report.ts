import {
  formatChicagoTime,
  getChicagoDateKey,
  getChicagoWallClock,
} from "../../lib/chicagoDate";
import { File, Paths } from "expo-file-system";
import * as Sharing from "expo-sharing";

import { formatDuration, formatServiceTime } from "./format";
import { registrationWasServed } from "./registrations";
import { didServe } from "./selectors";
import type { ServiceDashboard } from "./types";

/**
 * One line of the temple's hours record: one devotee, one seva, once.
 *
 * The screen that lists these and the spreadsheet that exports them are the
 * same rows. They used to be two builders that agreed by coincidence, and had
 * already stopped: the export required `status === "completed"` and the screen
 * did not, so a coordinator read one list and sent out another.
 */
export type ReportRow = {
  devotee: string;
  seva: string;
  kind: string;
  date: string;
  start: string;
  end: string;
  minutes: string;
  /** The same span the cards show, so the report reads back as the tab did. */
  hours: string;
  location: string;
  verification: string;
  completion: string;
  // --- Not exported. What the on-screen list needs to draw and act on a row.
  /** Stable across renders; the list's key. */
  key: string;
  devoteeId: string;
  /** A generated date of a weekly seva, for the card's marker. */
  weekly: boolean;
  /** Whichever record this row came from — only one is ever set. */
  assignmentId: string | null;
  verificationId: string | null;
  /** Sortable instant, unlike the human `date`/`start` pair. */
  at: string;
};

function escapeHtml(value: unknown) {
  return String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

/**
 * A sortable "when", on the temple's clock and in the same shape whichever
 * record the row came from: `2026-08-04T02:12`.
 */
function templeSortKey(at: Date) {
  const clock = getChicagoWallClock(at);
  const pad = (value: number) => String(value).padStart(2, "0");
  return `${clock.dateKey}T${pad(clock.hour)}:${pad(clock.minute)}`;
}

export function buildCompletedSevaRows(
  dashboard: ServiceDashboard,
  now = new Date(),
): ReportRow[] {
  const rows: ReportRow[] = [];

  // Verified registrations are the primary record of seva a devotee offered.
  // They are reported from the registration itself rather than from the
  // service_instances row it creates: a seva verified while it was still
  // running leaves that row as `closed`, so a status-only filter silently
  // dropped it from every report.
  const registrationInstances = new Set<string>();
  for (const registration of dashboard.verifications ?? []) {
    if (registration.service_instance_id) {
      registrationInstances.add(registration.service_instance_id);
    }
    if (registration.status !== "verified") continue;
    // The hole this report shared with the activity screen: a registration was
    // credited whatever anybody later recorded about the place it created, so a
    // devotee marked absent still left with a full morning in the spreadsheet —
    // the one copy of the record that is hardest to correct.
    if (!registrationWasServed(dashboard, registration)) continue;
    const start = new Date(registration.start_at);
    const end = new Date(registration.end_at);
    if (end.getTime() > now.getTime()) continue; // not finished yet
    const registrationMinutes = Math.max(
      1,
      Math.round((end.getTime() - start.getTime()) / 60_000),
    );
    rows.push({
      devotee: registration.devotee?.name ?? "Devotee",
      seva: registration.name,
      kind: "Registered seva",
      date: getChicagoDateKey(start),
      start: formatChicagoTime(start),
      end: formatChicagoTime(end),
      minutes: String(registrationMinutes),
      hours: formatDuration(registrationMinutes),
      location: registration.location_text,
      verification: `Verified by ${registration.verifiedBy?.name ?? "a member"}`,
      completion: "Verified seva",
      key: `registration-${registration.id}`,
      devoteeId: registration.devotee_id,
      weekly: false,
      assignmentId: null,
      verificationId: registration.id,
      at: templeSortKey(start),
    });
  }

  for (const service of dashboard.services) {
    if (registrationInstances.has(service.id)) continue;
    if (service.status !== "completed") continue;
    for (const participant of service.participants) {
      if (participant.assignment.status !== "completed") continue;
      // `seva_points_status` calls absent and excused `not_served`, and this
      // report is the temple's record of hours actually offered. Counting a
      // devotee a coordinator marked absent handed them a full morning in the
      // export — the one place the mistake is hardest to spot and hardest to
      // undo, because it leaves as a spreadsheet. Asked through the shared
      // helper rather than re-stated here, so the spreadsheet and the screens
      // can never drift apart on who served.
      if (!didServe(service, participant.devotee.id)) continue;
      rows.push({
        devotee: participant.devotee.name,
        seva: service.name,
        kind: service.template_id ? "Weekly seva" : "Seva",
        date: service.date,
        // Read as a time, not as a database value — the registration rows above
        // have always been formatted, and the two are read side by side.
        start: formatServiceTime(service.start_time),
        end: participant.assignment.completed_at
          ? new Date(participant.assignment.completed_at).toLocaleTimeString("en-US", { hour: "numeric", minute: "2-digit", timeZone: "America/Chicago" })
          : "—",
        minutes: String(service.duration_minutes),
        hours: formatDuration(service.duration_minutes),
        location: "ISKCON Chicago Temple",
        verification:
          participant.assignment.verification === "member_verified"
            ? "Member verified"
            : participant.assignment.verification === "qr_scan"
              ? "Temple verified"
              : participant.assignment.verification.replace(/_/g, " "),
        completion: "Completed requirement",
        key: `assignment-${participant.assignment.id}`,
        devoteeId: participant.devotee.id,
        weekly: Boolean(service.template_id),
        assignmentId: participant.assignment.id,
        verificationId: null,
        at: `${service.date}T${service.start_time.slice(0, 5)}`,
      });
    }
  }
  // Sorted on the instants, never on the printed times: "9:00 AM" sorts after
  // "10:00 AM" as text, which put a morning's rows in the wrong order.
  return rows.sort((left, right) => right.at.localeCompare(left.at));
}

export async function shareCompletedSevaReport(dashboard: ServiceDashboard) {
  const rows = buildCompletedSevaRows(dashboard);
  const generated = new Intl.DateTimeFormat("en-US", {
    dateStyle: "long",
    timeStyle: "short",
    timeZone: "America/Chicago",
  }).format(new Date());
  const headings = [
    "Devotee",
    "Seva",
    "Type",
    "Date",
    "Start",
    "End",
    "Minutes",
    "Length",
    "Location",
    "Verification",
    "Completion",
  ];
  const body = rows
    .map((row) => `<tr>${[
      row.devotee,
      row.seva,
      row.kind,
      row.date,
      row.start,
      row.end,
      row.minutes,
      row.hours,
      row.location,
      row.verification,
      row.completion,
    ].map((value) => `<td>${escapeHtml(value)}</td>`).join("")}</tr>`)
    .join("");
  const workbook = `<!doctype html>
<html><head><meta charset="utf-8"><style>
body{font-family:Arial,sans-serif;color:#3A342B}h1{color:#2B3A67;margin-bottom:4px}
.summary{margin:0 0 18px;color:#6B6355}table{border-collapse:collapse;width:100%}
th{background:#2B3A67;color:#fff;font-weight:700;padding:9px;border:1px solid #D8C9AF}
td{padding:8px;border:1px solid #D8C9AF;vertical-align:top}tr:nth-child(even){background:#FBF7EF}
</style></head><body>
<h1>ISKCON Chicago — Completed Seva Report</h1>
<p class="summary">Generated ${escapeHtml(generated)} · ${rows.length} completed offering${rows.length === 1 ? "" : "s"}</p>
<table><thead><tr>${headings.map((heading) => `<th>${heading}</th>`).join("")}</tr></thead><tbody>${body}</tbody></table>
</body></html>`;

  const stamp = getChicagoDateKey();
  const file = new File(Paths.cache, `iskcon-chicago-seva-report-${stamp}.xls`);
  file.create({ overwrite: true });
  file.write(workbook);
  if (!(await Sharing.isAvailableAsync())) {
    throw new Error("Sharing is not available on this device.");
  }
  await Sharing.shareAsync(file.uri, {
    mimeType: "application/vnd.ms-excel",
    dialogTitle: "Share completed seva report",
    UTI: "com.microsoft.excel.xls",
  });
}
