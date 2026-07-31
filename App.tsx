import "./global.css";
import "react-native-gesture-handler";

import {
  AtkinsonHyperlegible_400Regular,
  AtkinsonHyperlegible_700Bold,
} from "@expo-google-fonts/atkinson-hyperlegible";
import { Lora_600SemiBold } from "@expo-google-fonts/lora";
import { NavigationContainer, type Theme } from "@react-navigation/native";
import { createNativeStackNavigator } from "@react-navigation/native-stack";
import { useFonts } from "expo-font";
import { StatusBar } from "expo-status-bar";
import { useState } from "react";
import { GestureHandlerRootView } from "react-native-gesture-handler";
import { SafeAreaProvider } from "react-native-safe-area-context";

import tokens from "./design-tokens.json";
import { MainTabs } from "./src/navigation/MainTabs";
import type { RootStackParamList } from "./src/navigation/types";
import { FeatureScreen } from "./src/screens/FeatureScreen";
import { WelcomeScreen } from "./src/screens/WelcomeScreen";

const Stack = createNativeStackNavigator<RootStackParamList>();

const navigationTheme: Theme = {
  dark: false,
  colors: {
    primary: tokens.colors.marigold,
    background: tokens.colors.ivory,
    card: tokens.colors.ivory,
    text: tokens.colors.stone,
    border: tokens.colors.border,
    notification: tokens.colors.vermilion,
  },
  fonts: {
    regular: {
      fontFamily: "AtkinsonHyperlegible_400Regular",
      fontWeight: "400",
    },
    medium: {
      fontFamily: "AtkinsonHyperlegible_700Bold",
      fontWeight: "700",
    },
    bold: {
      fontFamily: "AtkinsonHyperlegible_700Bold",
      fontWeight: "700",
    },
    heavy: {
      fontFamily: "AtkinsonHyperlegible_700Bold",
      fontWeight: "700",
    },
  },
};

export default function App() {
  const [hasEnteredPreview, setHasEnteredPreview] = useState(false);
  const [fontsLoaded] = useFonts({
    AtkinsonHyperlegible_400Regular,
    AtkinsonHyperlegible_700Bold,
    Lora_600SemiBold,
  });

  if (!fontsLoaded) {
    return null;
  }

  return (
    <GestureHandlerRootView className="flex-1">
      <SafeAreaProvider>
        <NavigationContainer theme={navigationTheme}>
          <StatusBar style="dark" />
          <Stack.Navigator
            initialRouteName={hasEnteredPreview ? "MainTabs" : "Welcome"}
            screenOptions={{
              headerShadowVisible: false,
              headerBackButtonDisplayMode: "minimal",
              headerStyle: { backgroundColor: tokens.colors.ivory },
              headerTintColor: tokens.colors.indigo,
              headerTitleStyle: {
                fontFamily: "AtkinsonHyperlegible_700Bold",
              },
              contentStyle: { backgroundColor: tokens.colors.ivory },
            }}
          >
            <Stack.Screen name="Welcome" options={{ headerShown: false }}>
              {({ navigation }) => (
                <WelcomeScreen
                  onEnter={() => {
                    setHasEnteredPreview(true);
                    navigation.replace("MainTabs");
                  }}
                />
              )}
            </Stack.Screen>
            <Stack.Screen
              name="MainTabs"
              component={MainTabs}
              options={{ headerShown: false }}
            />
            <Stack.Screen
              name="Feature"
              component={FeatureScreen}
              options={({ route }) => ({ title: route.params.title })}
            />
          </Stack.Navigator>
        </NavigationContainer>
      </SafeAreaProvider>
    </GestureHandlerRootView>
  );
}
