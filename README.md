# ISKCON Chicago Community App

Expo + React Native app for iOS and Android. Authentication is connected to
Supabase. Temple presence, the devotee directory, access requests, service
coordination, and the in-app notification inbox use live Supabase data.

## Supabase authentication

Create `.env.local` with:

```bash
EXPO_PUBLIC_SUPABASE_URL=your-project-url
EXPO_PUBLIC_SUPABASE_KEY=your-publishable-key
```

Email/password and Google are enabled in Supabase Authentication providers.
Google uses this native callback:

```text
iskconchicago://auth/callback
```

Add that exact callback under **Authentication → URL Configuration → Redirect
URLs** in the Supabase dashboard.

## Temple presence

The Home screen uses a daily manual check-in for ISKCON Chicago at 1716 W Lunt
Ave. Location never changes temple presence automatically. With “While Using”
access, the app can detect a likely temple arrival while open; with
“Always”/“All the time” access, it also registers a 75-meter arrival geofence.
An accurate arrival creates at most one reminder per Chicago day, asking the
devotee to confirm their own status. Only a manual switch change shows the small
one-second toast. Confirmed daily presence is stored in Supabase and updates the
shared “At the temple today” list across signed-in iOS and Android devices in
real time.

## Review on this Mac

Install dependencies once:

```bash
npm install
```

Start the development server:

```bash
npm start
```

Then open the installed **ISKCON Chicago** app in either simulator. Changes
refresh automatically while the development server is running.

To rebuild the native simulator app after native dependencies or app
configuration change:

```bash
npm run ios
npm run android
```

## Quality checks

```bash
npm run typecheck
npm test -- --runInBand
npx expo-doctor
```

The milestone uses live profiles and services; no sample people or service
schedules are rendered. Push-token registration and local temple-arrival
reminders are wired, while remote delivery still requires production Expo push
credentials and a server-side delivery worker.

## Access-level preview

The Profile screen has a testing-only switcher for President, Tech Member, Core
Member, Volunteer, and Devotee. It lets you review each presentation and test a
local request/approve/deny flow without creating five accounts. Changing the
preview never changes Supabase permissions.

The production access schema and RLS policies are in:

```text
supabase/migrations/202608020001_access_levels.sql
```

To activate production access, open **Supabase Dashboard → SQL Editor**, create
a new query, paste the complete migration, and run it. Do not add a Supabase
service-role key to the Expo `.env.local` file. After the migration is applied,
it must be seeded and verified with real Devotee, Volunteer, Core, Tech, and
President accounts before the testing-only switcher is removed.
# Seva operations upgrade (August 3, 2026)

Before opening the updated Seva tab, run the complete contents of
`supabase/migrations/202608030008_service_operations_and_reports.sql` once in
Supabase Dashboard → SQL Editor, followed by
`supabase/verification/service_operations_and_reports.sql`. Next, run
`supabase/migrations/202608030009_weekly_seva_visibility_and_coverage.sql`,
followed by:

```text
supabase/verification/weekly_seva_visibility_and_coverage.sql
```

Their final rows must say `service operations verification passed` and
`weekly seva schema verification passed` respectively. The functional weekly
verification is intended only for a disposable local/test database because it
creates test accounts inside a transaction before rolling everything back.

This migration enables custom and QR seva with planned endings, automatic
completion, secure activity deletion, reports, multi-day Weekly Seva,
time-scoped coverage, role-targeted notifications, and physical-device push
token registration. Until it is applied, the Services screen intentionally
shows a load error because the new protected RPCs do not exist remotely yet.

## Enable background push on physical phones

The real-time notification bell works immediately after the migration. For
background push when the app is closed:

1. Initialize/link the Expo project with `npx eas-cli@latest init` and put the
   resulting project ID in `.env.local`:
   `EXPO_PUBLIC_EAS_PROJECT_ID=your-project-id`.
2. Link the Supabase CLI project, set a strong webhook secret, and deploy:
   `npx supabase secrets set NOTIFICATION_WEBHOOK_SECRET=your-secret`
   `npx supabase functions deploy send-service-notification --no-verify-jwt`
3. In Supabase Dashboard → Database → Webhooks, create an `INSERT` webhook for
   `public.app_notifications` that calls the deployed
   `send-service-notification` function. Add request header
   `x-notification-secret` with the same secret from step 2.
4. Rebuild the development app on each physical phone. Expo push tokens do not
   work on iOS or Android simulators; the app safely retries registration on a
   physical device.
