# Physical iPhone and Android testing

This project uses local Expo builds. EAS cloud builds are intentionally deferred.

## Before connecting either phone

1. On the Mac, from the repository root, run `npm install`.
2. Confirm `.env.local` contains the Supabase URL, publishable key and Expo
   project UUID. Do not add server/admin secrets.
3. Keep both phones and the Mac on the same Wi-Fi network.
4. Run `npm run typecheck` and `npm test -- --runInBand`.

## Android: Firebase and local install

### Download `google-services.json`

1. Open Firebase Console and select or create the ISKCON Chicago project.
2. Open Project settings (gear) → General.
3. Under Your apps, add/select the Android app.
4. Use Android package name `org.iskconchicago.community` exactly.
5. Download `google-services.json`.
6. Place it at `/Users/tanmay/ISKCON-Chicago/google-services.json`.
7. Do not rename it. This repository intentionally ignores it.

For actual Expo Push delivery, also open Firebase Project settings → Service
accounts → Generate new private key. Keep that service-account JSON outside the
repository and upload it as the Expo project's FCM V1 push credential through
the Expo dashboard or `eas credentials`. This credential step does not require
using EAS cloud builds.

### Connect and build

1. On Android, open Settings → About phone and tap Build number seven times.
2. Open Developer options and enable USB debugging.
3. Connect the phone by USB and approve the computer on the phone.
4. In Terminal, run `adb devices`; the phone must show as `device`, not
   `unauthorized`.
5. Run `npx expo run:android --device` and select the physical phone.
6. Allow the notification, camera, photo and location permissions requested by
   the app.
7. For later JavaScript-only changes, run `npx expo start` instead of rebuilding.

If Metro cannot connect over Wi-Fi, keep USB attached and run
`adb reverse tcp:8081 tcp:8081`, then start Metro again.

## iPhone: local install

1. Connect the iPhone by cable and tap Trust on both the phone and Mac.
2. Enable Settings → Privacy & Security → Developer Mode, then restart when
   prompted.
3. Open Xcode → Settings → Accounts and add the Apple ID used for development.
4. Run `npx expo run:ios --device` and choose the connected iPhone.
5. If Xcode asks for signing, choose the personal development team for bundle
   identifier `org.iskconchicago.community`.
6. On the phone, trust the developer profile if iOS requests it.
7. Allow the app's notification, camera, photo and location permissions.

A free Apple development team can install a tethered local test build, usually
with short-lived provisioning, but it cannot provide production APNs push
credentials. Closed/background remote iOS push remains blocked until the paid
Apple Developer account is configured.

## Two-account test setup

- iPhone: sign in as President or Tech Admin.
- Android: sign in as a Devotee or Volunteer.
- Use genuine separate Supabase accounts so realtime recipient and permission
  tests are meaningful.
- Keep the Arpita/sample account clearly marked as test/demo until cleanup.

## Required test matrix

Run each row in both directions where applicable.

| Area | Test | Expected result |
| --- | --- | --- |
| Auth | Email/password, Google, sign out/in | Correct account and role restored |
| Profile | Mandatory phone, email, gender, DOB | Required fields enforced; public fields visible |
| Presence | Toggle on one phone | Other phone updates immediately |
| QR | Scan a real printed seva QR | Correct seva opens/starts once |
| Seva | Assign/accept/decline/counter | Only intended devotee and roles are notified |
| Weekly Seva | Report unavailable and replace | Correct period changes; schedule updates |
| Messages | Send text/photo | Realtime delivery/read states are accurate |
| Messages | Swipe-remove complete chat | Clears only that user's inbox; leadership record remains |
| Messages | Send after chat was removed | Conversation reappears with new exchange |
| Notifications | App open | Banner/inbox appears and tap opens correct screen |
| Notifications | App backgrounded | System notification arrives and opens correct screen |
| Notifications | App terminated | System notification cold-opens correct screen |
| Notifications | Wrong recipient check | Other account receives nothing |
| Location | Enter temple radius | Reminder asks for confirmation; no automatic check-in |
| Donations | General and campaign forms | Correct Zeffy hosted page opens |
| Media | Camera, photos and files | Real-device picker/upload works |

For every notification test, also verify that clearing the bell item does not
change the underlying seva/message/announcement record.
