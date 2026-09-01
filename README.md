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
- Manual temple check-in with a daily reminder at four in the afternoon
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
[`docs/seva-flows.docx`](docs/seva-flows.docx), rebuilt by
`python3 docs/build-seva-flows-docx.py`. The rules both describe are
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
- A devotee can step away from the app without losing anything, or ask to be
  forgotten, from Profile. Being forgotten erases every personal detail and the
  sign-in; the seva and giving records stay, with nobody's name on them, because
  the temple's hours have to still add up and a charity must keep its books.

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

## Releasing

`eas.json` holds four build profiles and a submit skeleton. Builds consume the
temple's EAS quota, so run them only for a real release:

```bash
eas build --profile development --platform all   # dev client, internal
eas build --profile preview --platform all       # internal test build, Android APK
eas build --profile production --platform all    # store build, Android app bundle
```

`development-simulator` is the same development profile with an iOS Simulator
build instead of a device build.

`cli.appVersionSource` is `remote`, and `production` sets `autoIncrement`, so
EAS raises `ios.buildNumber` and `android.versionCode` on every production
build. The marketing version stays in `app.config.js`.

**Where the secrets live.** Each build profile names an EAS environment
(`development`, `preview`, `production`) rather than carrying values. Set these
three in each environment under EAS → Environment variables; they never belong
in the repository:

```text
EXPO_PUBLIC_SUPABASE_URL
EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY   (the app also accepts EXPO_PUBLIC_SUPABASE_KEY)
EXPO_PUBLIC_EAS_PROJECT_ID
```

All three are `EXPO_PUBLIC_`, so they are compiled into the bundle and are not
secret in the cryptographic sense; the Supabase publishable key is meant for app
clients. A service-role key, an FCM service-account key or an Apple signing key
must never be added here.

**Before a first submit**, replace every `REPLACE-ME-` placeholder in the
`submit` section of `eas.json`:

- `ascAppId` — the App Store Connect app ID
- `appleId` — the Apple ID the temple's App Store Connect account uses
- `appleTeamId` — the Apple Developer Team ID
- `serviceAccountKeyPath` — path to the Google Play service-account JSON, kept
  outside the repository (`credentials/` is gitignored)

Both stores also need a public privacy policy URL. The two documents are
published from `docs/` on GitHub Pages, and the sign-in screen links to them:

- [`docs/privacy-policy.html`](docs/privacy-policy.html) —
  <https://tanmayypramanick.github.io/iskcon-chicago-community-app/privacy-policy.html>
- [`docs/terms-of-service.html`](docs/terms-of-service.html) —
  <https://tanmayypramanick.github.io/iskcon-chicago-community-app/terms-of-service.html>

Both carry placeholders for the temple's contact email, postal address and
governing-law county, and both still need leadership and legal approval. No
build has been run against this configuration yet, and neither app-store listing
exists; this is the configuration ready for a release, not a release.

## Quality checks

```bash
npm run typecheck
npm test -- --runInBand
npx expo-doctor
```

Simulator checks cannot prove background/terminated push,
APNs/FCM credentials, OAuth handoff in an installed build or
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
