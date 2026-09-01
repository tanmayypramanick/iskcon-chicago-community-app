# ISKCON Chicago Community App — Current Product Specification

Status baseline: 12 August 2026. This document describes the application that
exists now, not the original prototype plan.

## Product purpose

A single, clear mobile home for ISKCON Chicago devotees to stay connected,
serve reliably and participate in temple community life. The interface should
remain spiritual, calm, modern, highly legible and usable across age groups on
small iPhones and Android phones.

## Identity and account rules

- Authentication: email/password or Google through Supabase Auth.
- Email confirmation is required according to the Supabase project setting.
- Phone is mandatory contact information but is not used for sign-in or OTP.
- Required profile: photo, name, phone, date of birth, occupation and gender.
- Users cannot delete their own account. Authorised temple administration may
  close or disable accounts.
- Current Arpita/sample congregation content is test/demo data and must be
  reviewed and removed or replaced before production launch.

## Access levels

1. Devotee
2. Volunteer
3. Community Head (`core` in the database)
4. Tech Admin (`tech` in the database)
5. President

Access is enforced by PostgreSQL functions, RLS and permissions. UI visibility
is not treated as security. President and Tech Admin hold whole-app oversight.
Access request, appointment, review and revocation flows are implemented.

## Implemented modules

### Home

- Personal greeting and Chicago-local date
- Manual At the temple status and shared live presence roster
- A daily reminder at four in the afternoon that reminds rather than checks in
- Notification bell and actionable notification inbox
- Community module cards

### Seva

- One-time/open requirements and custom typed seva
- Weekly Seva templates, multi-day schedules and assignments
- Invitations, accept/decline/counter flows and self-assignment
- Time-bounded unavailability and coverage replacement
- QR or list-started seva sessions with live/planned start and end times
- Attendance, completion, verification and correction controls
- Role-aware community schedule, searchable lists and Excel reports
- Seva Yatra awards, boards, history, care and reliability views

### Devotees

- Directory and public devotee profiles
- Direct realtime messaging, photos, typing and delivery/read states
- Delete-for-me and delete-for-everyone message behavior
- Per-devotee complete-conversation removal without record destruction
- Sangas, membership, join review, chat and management

### Community content

- Announcements, scheduling, images/files, reactions and comments
- Birthday prompts
- Feedback with response workflow
- Confidential devotee care posts and replies
- Newsletter issues, submissions, reviews and editor appointments

### Giving

- General one-time and recurring Zeffy donation page
- Multiple campaign-specific Zeffy sponsorship forms
- Date holds, campaign availability and donation reconciliation
- Personal giving history and authorised temple-wide records
- Sponsorship fulfilment and notification workflow

### Profile and governance

- Editable contact, household, family and spiritual information
- Access request/appointment management
- Notification settings
- Privacy and visibility explanation
- Terms of Service
- About this app

## Privacy and record visibility

Every signed-in devotee may see another devotee's name, photo, access level,
joined date, email, gender, date of birth, derived age and occupation.

Phone, address, birthplace, family/children, emergency, initiation, mentor,
guru and practice details are restricted to the devotee and authorised roles.

Direct messages and attached photos are retained as temple records. Retracting
a message clears the participant-facing content while retaining its original
content in protected columns. Clearing a conversation is per devotee and
time-based: existing messages disappear from that devotee's inbox, a newer
message restores the thread, and authorised oversight continues to see the
complete record.

## Notifications

The database notification kind is the source of truth. Notifications can be
targeted to one devotee, role holders or the community according to the action.
Every database kind has an intentional client destination. Operating-system
push taps and in-app bell taps use the same resolver.

Delivery path:

1. A protected database function creates `app_notifications` rows.
2. A signed Supabase database webhook calls `send-service-notification`.
3. The Edge Function re-reads the trusted row and sends through Expo Push.
4. Invalid device tokens are deactivated.
5. The in-app inbox reads the retained notification row in realtime.

Android remote delivery requires Firebase/FCM V1 configuration. iOS remote
delivery requires a paid Apple Developer account/APNs credentials. Neither
simulator alone is sufficient release evidence.

## Donations and Zeffy

General donations open
`https://www.zeffy.com/en-US/donation-form/donate-789`, which offers one-time
and recurring giving.

Each sponsorship campaign may have its own Zeffy URL stored in Supabase. Zeffy
HTML embed snippets are web components and are not inserted into this native
app. The app opens the hosted form in the system browser for payment security,
Apple Pay/Google Pay compatibility and a visible Zeffy origin.

## Not yet implemented

- Courses
- Forum
- Persistent offline cache across a cold restart
- Persistent private crash reporting
- CI and reproducible release pipelines
- Production Android/iOS push credentials and completed physical test matrix

## Release requirements

- Remove or replace all confirmed test/demo accounts and content.
- Complete Android FCM and Apple APNs configuration.
- Test two real accounts across one Android phone and one iPhone.
- Validate foreground, background and terminated notification delivery and
  every actionable deep link.
- Validate OAuth and media/file selection.
- Have temple leadership and appropriate legal counsel review Terms of Service
  and privacy wording.
- Confirm every live Zeffy campaign URL and production webhook secret.
