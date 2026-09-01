# ISKCON Chicago Community App

Expo SDK 57 + React Native application for the ISKCON Chicago community on
iOS and Android. Supabase provides authentication, PostgreSQL, row-level
security, realtime updates, storage and Edge Functions.

The current checkpoint is backed up in the private GitHub repository
`tanmayypramanick/iskcon-chicago-community-app` on branch
`checkpoint/full-app-2026-08-12`.

## Current product

Implemented areas include:

- Email/password and Google sign-in with email verification and password reset
- Required community profile, including a mandatory contact phone number
- Devotee, Volunteer, Community Head, Tech Admin and President access levels
- Manual temple check-in with location-based arrival reminders
- One-time and Weekly Seva, assignments, offers, coverage, attendance,
  verification, QR-started seva, live timers, reports and Seva Yatra
- Devotee directory, direct messages, retained leadership conversation records
- Sangas, announcements, birthdays, feedback and confidential devotee care
- Newsletter publishing/submissions and editor appointments
- Zeffy donations, sponsorship campaigns, matching and fulfilment records
- Realtime in-app notifications and Expo push delivery infrastructure

Courses and Forum are represented in the UI but are not implemented yet.

**How seva is settled** — the three flows (posted, self-added and weekly),
every permutation, who may do what, and what is still open, is written up in
[`docs/seva-flows.html`](docs/seva-flows.html) — open it in a browser, or read
it at
<https://tanmayypramanick.github.io/iskcon-chicago-community-app/seva-flows.html>.
The same document as an editable Word file is
[`docs/seva-flows.docx`](docs/seva-flows.docx). The rules both describe are
enforced in the database and exercised by
`supabase/verification/seva_flow_matrix.sql`.

## Local environment

Create `.env.local` (never commit it):

```bash
EXPO_PUBLIC_SUPABASE_URL=your-project-url
EXPO_PUBLIC_SUPABASE_KEY=your-publishable-key
EXPO_PUBLIC_EAS_PROJECT_ID=your-expo-project-uuid
```

Never place a Supabase service-role key, Firebase service-account key, Apple
signing key or webhook secret in this client file.

Google Auth uses this callback:

```text
iskconchicago://auth/callback
```

Add it in Supabase Dashboard → Authentication → URL Configuration → Redirect
URLs. Email/password and Google must both be enabled under Authentication →
Providers.

## Run locally

```bash
npm install
npx expo start
```

After a native dependency or app configuration change, rebuild locally:

```bash
npx expo run:ios
npx expo run:android
```

Use `--device` to choose a connected physical phone. See
[`docs/physical-device-testing.md`](docs/physical-device-testing.md) for the
full iPhone/Android procedure and notification test matrix.

## Supabase database

Migrations live in `supabase/migrations` and must be applied in filename order.
Verification scripts live in `supabase/verification`.

The newest migration is:

```text
supabase/migrations/202608120071_conversation_removal.sql
```

It adds WhatsApp-style per-devotee conversation removal without destroying the
retained temple record. Run it in Supabase SQL Editor, then run:

```text
supabase/verification/conversation_removal.sql
```

The verification must finish with `conversation removal verification passed`.

## Privacy decisions currently implemented

- Phone number is mandatory profile/contact information, not a sign-in method.
- Signed-in devotees can see another devotee's email, gender, date of birth,
  age and occupation.
- Phone, address, family and spiritual details remain restricted.
- Deleted message content is retained and visible through the authorised
  Devotee conversations record.
- Removing a complete conversation clears it only from that devotee's Messages
  view; a new message brings it back.
- Users cannot delete their own account in the app. An authorised temple
  administrator handles account closure.

The in-app Terms of Service and privacy wording are a product draft and still
require temple leadership/legal approval before public release.

## Zeffy

The standard one-time/recurring donation page is:

```text
https://www.zeffy.com/en-US/donation-form/donate-789
```

Campaign-specific sponsorship URLs are stored separately in
`sponsorship_types.zeffy_campaign_url`. The native app opens each hosted Zeffy
page in the phone's secure browser; it does not inject Zeffy's web-only HTML
embed block into React Native and never receives card details.

## Push notifications

The app already creates Android channels, requests permission, registers Expo
push tokens, stores them per devotee, creates targeted notification rows and
delivers them through the protected `send-service-notification` Edge Function.
Push-banner taps and in-app bell taps share one tested routing contract.

Android still needs `google-services.json` in the repository root and an FCM
V1 service-account credential uploaded to the Expo project. iOS remote push
requires a paid Apple Developer account and APNs credentials. Local/in-app
notifications can work without those production credentials.

## Quality checks

```bash
npm run typecheck
npm test -- --runInBand
npx expo-doctor
```

Simulator checks cannot prove background/terminated push,
APNs/FCM credentials, actual geofencing, OAuth handoff in an installed build or
real photo/file picking. Those must be checked on physical devices.

## Known release work

- Complete Android FCM and Apple APNs credentials
- Run the physical-device matrix on one Android phone and one iPhone
- Add persistent offline query storage; current query cache does not survive a
  cold app restart
- Connect persistent crash reporting; current crash details are memory-only
- Add CI/reproducible release configuration when EAS builds are introduced
- Review and remove confirmed test/demo accounts and content before launch
- Obtain leadership/legal approval for Terms of Service and privacy wording
- Implement Courses and Forum after the existing product is stabilised
