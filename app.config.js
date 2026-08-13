const fs = require("fs");
const path = require("path");

const tokens = require("./design-tokens.json");

// Android push goes through Firebase Cloud Messaging, which needs this file to
// exist before Expo can issue a token. It is referenced only when it is
// actually present so that a checkout without it still builds — the app simply
// runs without push rather than failing to compile.
const googleServicesFile = path.join(__dirname, "google-services.json");
const hasGoogleServices = fs.existsSync(googleServicesFile);

module.exports = {
  expo: {
    name: "ISKCON Chicago",
    slug: "iskcon-chicago-community",
    // Pinned to the temple's Expo account rather than left to whoever happens
    // to be logged in, so a build from another machine cannot quietly create a
    // second project and issue push tokens nobody is listening for.
    owner: "iskcon-chicagoil",
    scheme: "iskconchicago",
    version: "1.0.0",
    extra: {
      eas: {
        projectId: process.env.EXPO_PUBLIC_EAS_PROJECT_ID,
      },
    },
    orientation: "portrait",
    icon: "./assets/icon.png",
    userInterfaceStyle: "light",
    splash: {
      image: "./assets/splash-icon.png",
      resizeMode: "contain",
      backgroundColor: tokens.colors.ivory,
    },
    ios: {
      supportsTablet: true,
      bundleIdentifier: "org.iskconchicago.community",
      infoPlist: {
        NSCameraUsageDescription:
          "Allow ISKCON Chicago to scan temple service QR codes.",
      },
    },
    android: {
      package: "org.iskconchicago.community",
      ...(hasGoogleServices ? { googleServicesFile: "./google-services.json" } : {}),
      adaptiveIcon: {
        backgroundColor: tokens.colors.ivory,
        foregroundImage: "./assets/android-icon-foreground.png",
        backgroundImage: "./assets/android-icon-background.png",
        monochromeImage: "./assets/android-icon-monochrome.png",
      },
      predictiveBackGestureEnabled: true,
    },
    web: {
      bundler: "metro",
      favicon: "./assets/favicon.png",
    },
    plugins: [
      "@react-native-community/datetimepicker",
      [
        "expo-camera",
        {
          cameraPermission:
            "Allow ISKCON Chicago to scan temple service QR codes.",
          recordAudioAndroid: false,
          barcodeScannerEnabled: true,
        },
      ],
      "expo-asset",
      "expo-font",
      "expo-splash-screen",
      "expo-sqlite",
      "expo-sharing",
      "expo-web-browser",
      [
        "expo-notifications",
        {
          icon: "./assets/android-icon-monochrome.png",
          color: tokens.colors.indigo,
          defaultChannel: "temple-reminders",
        },
      ],
      [
        "expo-location",
        {
          locationWhenInUsePermission:
            "Allow ISKCON Chicago to use your location while the app is open to detect when you are at the temple.",
          locationAlwaysAndWhenInUsePermission:
            "Allow ISKCON Chicago to detect temple arrival and departure for your At Temple status.",
          isIosBackgroundLocationEnabled: true,
          isAndroidBackgroundLocationEnabled: true,
          isAndroidForegroundServiceEnabled: false,
        },
      ],
    ],
  },
};
