# ISKCON Chicago Community App — Build Spec v1

## 1. Master feature list (confirmed scope)

| # | Feature | Notes |
|---|---|---|
| 1 | Service board | Post a need (pot washing, cooking, cleaning, etc.), notify all users, people join until slots filled, auto-close. Free-text service if not on preset list. |
| 2 | Self-logged services | "I'm doing X from [time]," 30-min increments, no request required. |
| 3 | Availability status | "At Temple" / "Not at temple," visible to others. |
| 4 | Festival help requests | Art, chart, painting, acting, dance practice, kirtan/kirtan practice, general "need help with X." |
| 5 | Communities | User-created groups, admin-approved join, chat, file/photo sharing. |
| 6 | Courses | President-approved to list; instructor-approved to join; materials/links/files; attendance %, exams; upcoming/ongoing/finished states; date/time/place or virtual link. |
| 7 | Rankings | Gamified progress: services + community activity + course completion, weekly/monthly/overall. |
| 8 | Access levels | President, VP, Cabinet, Members, Brahmacaris, Devotees, Volunteers. |
| 9 | Newsletter | Monthly, uploaded by designated members. |
| 10 | Announcements | Push-notified, image/file attachments, role-gated posting. |
| 11 | Donations | Role-gated visibility (president/authorized only). |
| 12 | Feedback | Role-gated visibility. |
| 13 | Forum | Open posting board; like, comment, repost, share-into-a-community. |
| 14 | **Devotee database + schedule** | Who's doing what, on what day — the backbone the service system reads/writes against. |
| 15 | **Service assignment** | Core members (president, etc.) assign a specific devotee to a specific service. |
| 16 | **Recurring services** | Standing weekly (or other cadence) assignments — e.g., Devotee A every Thursday. |

Priority order for build: **14 → 15 → 16 → 1 → 2 → 3**, then everything else.

---

## 2. Core data model (service system — build this first)

```
users
  id, name, phone, email, photo_url, ashram_status (profile tag, NOT permission),
  role_id (FK), joined_at

roles
  id, name  -- president, vp, cabinet, brahmacari, member, volunteer

role_permissions
  role_id, permission_key
  -- e.g. assign_service, approve_course, view_donations,
  --      post_announcement, create_community, moderate_forum

service_templates
  id, name, description, is_recurring (bool),
  recurrence_rule (see §3), default_slots_needed, created_by (FK users)

service_instances
  id, template_id (FK, nullable — null = one-off ad-hoc),
  date, start_time, duration_minutes, slots_needed,
  status (open/full/closed/completed), created_by

service_assignments
  id, service_instance_id (FK), devotee_id (FK),
  assigned_by (FK, nullable — null = self-joined),
  status (assigned/confirmed/declined/completed/no-show)

service_exceptions
  id, service_instance_id (FK), devotee_id (FK),
  type (skip/substitute), substitute_devotee_id (nullable), reason
```

**Why `service_exceptions` matters:** a recurring assignment ("Devotee A, every Thursday") breaks down the first time Devotee A is sick or traveling. Without an exception/override mechanism, the schedule silently goes stale. This table lets someone skip one instance or hand it to a substitute without touching the recurring template.

**Why `ashram_status` is a profile field, not a role:** a brahmacari isn't automatically an app admin, and a president isn't necessarily a brahmacari. Keep spiritual designation and app permission as two separate axes — collapsing them causes access-control bugs later.

---

## 3. Recurring-service engine — two options

**Option A (recommended to start):** store `day_of_week + start_time + start_date + optional end_date`. A nightly/weekly job generates `service_instances` on a rolling window (e.g., always 4 weeks out). Covers weekly recurrence — the large majority of real temple patterns (Thursday class, Sunday kitchen crew).

**Option B (more powerful, more complex):** store an RFC 5545 RRULE string (the iCalendar standard — same thing Google Calendar uses under the hood) and expand it with a library (e.g., `rrule.js`). Needed only for patterns like "first Saturday of the month" or "every 2 weeks."

Start with A. Migrating A → B later is a schema addition, not a rewrite, since both just populate the same `service_instances` table.

---

## 4. "Presidential access" — recommend a separate web dashboard, not just mobile screens

Assigning recurring services to dozens of devotees, approving courses, and reviewing donations are bulk, table-heavy admin tasks. These are painful to build well on a phone screen and much faster to build (and use) as a role-gated web table view.

Recommendation: same Postgres backend, two frontends —
- **Mobile app (Expo/React Native):** devotee-facing — service board, self-log, communities, courses, forum, plus lightweight president actions (approve a join request, post an announcement).
- **Web admin (Next.js, or a low-code layer like Retool on the same DB):** bulk service assignment, course/community approval, donation visibility, newsletter upload.

If you'd rather keep everything in the one mobile app, that's workable too — just expect the bulk-assignment screens to take longer to get right (multi-select, filters, drag-assign UI on a small screen).

---

## 5. Step-by-step build order

0. **Setup** — Expo (React Native) project, Supabase project (Postgres + Auth + Storage), repo, CI.
1. **Schema** — migrate the tables in §2.
2. **Auth** — phone/email + OTP via Supabase Auth. Seed president/VP roles manually at first; decide self-registration vs. invite-only (open item, see §6).
3. **Devotee directory** — list + profile screen (name, photo, ashram status, contact). Needed before assignment makes sense.
4. **Service board (ad-hoc)** — create request, notify, join, auto-close at capacity. Get this working with a handful of real devotees before building anything else.
5. **Recurring templates** — president creates "Every Thursday 6–8pm Kitchen Prep," assigns devotees; nightly job generates instances 4 weeks out.
6. **Exceptions** — devotee marks "can't make it this week" → slot reopens or president is notified.
7. **Push notifications** — Expo push, wired into steps 4–6.
8. **Presidential web dashboard** — bulk assignment, oversight.
9. **Everything else, in this order:** Communities → Courses → Rankings → Donations → Newsletter/Announcements → Forum.

---

## 6. Open decisions (defaults assumed — confirm or override)

- **Onboarding:** self-registration with president approval (assumed) vs. invite-only. Changes the auth flow and directory-seeding approach.
- **Ashram status visibility:** public on profile (assumed) vs. private/president-only.
- **Self-logged service trust:** honor-system self-report (assumed, fine for a small community) vs. requiring a confirming devotee/QR check-in — matters more once rankings are tied to it, since self-report is gameable.

---

## 7. Working with Claude Code

Feed this file to Claude Code as project context (e.g., `CLAUDE.md`) and build table-by-table, screen-by-screen — don't ask it to scaffold the whole app in one prompt. Given your existing Claude Code Router / OpenRouter setup, this slots in directly: schema migration first, verify with a seed script and a couple of test queries, then build the service-board screens against it before moving to recurring templates.
