import "expo-sqlite/localStorage/install";

import { registerRootComponent } from "expo";
import { Platform } from "react-native";
import { enableScreens } from "react-native-screens";

import App from "./App";

// React Native Screens 4.x can hit a Fabric view re-parenting crash when a
// lazily mounted bottom tab is first opened on Android. The JS-backed screen
// containers avoid that native crash while retaining native stacks on iOS.
enableScreens(Platform.OS !== "android");

// registerRootComponent calls AppRegistry.registerComponent('main', () => App);
// It also ensures that whether you load the app in Expo Go or in a native build,
// the environment is set up appropriately
registerRootComponent(App);
