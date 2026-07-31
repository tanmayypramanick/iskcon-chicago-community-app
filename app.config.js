const tokens = require("./design-tokens.json");

module.exports = {
  expo: {
    name: "ISKCON Chicago",
    slug: "iskcon-chicago-community",
    version: "1.0.0",
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
    },
    android: {
      package: "org.iskconchicago.community",
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
    plugins: ["expo-asset", "expo-font", "expo-splash-screen", "expo-sqlite"],
  },
};
