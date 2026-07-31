# ISKCON Chicago Community App

Expo + React Native UI prototype for iOS and Android. All content is local mock
data during the design-review phase.

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

The current prototype contains sample people, schedules, services, and feature
content. It does not connect to Supabase or send notifications.
