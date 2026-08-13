import "./global.css";
import "react-native-gesture-handler";

import {
  AtkinsonHyperlegible_400Regular,
  AtkinsonHyperlegible_700Bold,
} from "@expo-google-fonts/atkinson-hyperlegible";
import {
  Lora_500Medium_Italic,
  Lora_600SemiBold,
} from "@expo-google-fonts/lora";
import {
  createNavigationContainerRef,
  NavigationContainer,
  type Theme,
} from "@react-navigation/native";
import { createNativeStackNavigator } from "@react-navigation/native-stack";
import {
  focusManager,
  QueryClient,
  QueryClientProvider,
} from "@tanstack/react-query";
import { useFonts } from "expo-font";
import { StatusBar } from "expo-status-bar";
import { useEffect, useState, type ReactNode } from "react";
import {
  ActivityIndicator,
  AppState,
  Alert,
  Linking,
  LogBox,
  Text,
  View,
} from "react-native";
import { GestureHandlerRootView } from "react-native-gesture-handler";
import { SafeAreaProvider } from "react-native-safe-area-context";

import tokens from "./design-tokens.json";
import { ErrorBoundary } from "./src/components/ErrorBoundary";
import { ConnectionBar } from "./src/components/ui";
import { CompleteProfileScreen } from "./src/screens/CompleteProfileScreen";
import { SetNewPasswordScreen } from "./src/screens/SetNewPasswordScreen";
import { useRequiredProfile } from "./src/features/access/hooks";
import {
  createSessionFromRecoveryUrl,
  isRecoveryUrl,
} from "./src/services/auth";
import { useServerReachable } from "./src/lib/connectivity";
import { useAppNotificationsRealtime } from "./src/features/notifications/hooks";
import { getNotificationTarget } from "./src/features/notifications/navigation";
import { useTemplePresenceRealtime } from "./src/features/presence/hooks";
import { useServiceRealtime } from "./src/features/services/hooks";
import { getSupabaseClient } from "./src/lib/supabase";
import { MainTabs } from "./src/navigation/MainTabs";
import type { RootStackParamList } from "./src/navigation/types";
import { WelcomeScreen } from "./src/screens/WelcomeScreen";
import { signOutFromSupabase } from "./src/services/auth";
import { subscribeToNotifications } from "./src/services/notifications";
import { usePrototypeSession } from "./src/store/usePrototypeSession";

// The LogBox toast is a development overlay that sits above the tab bar and
// renders as a near-blank box when a log has no readable message. It never
// ships in a release build; suppressing the overlay keeps the screen honest
// while testing, and real warnings still print to the Metro console.
if (__DEV__) LogBox.ignoreAllLogs(true);

/**
 * Shown while the fonts, the stored sign-in and the devotee's profile are still
 * being read. All three are normally instant; when they are not, something is
 * wrong and saying so beats a blank screen the devotee cannot interpret.
 */
function StartupScreen({
  fontsLoaded,
  authReady,
}: {
  fontsLoaded: boolean;
  authReady: boolean;
}) {
  const [slow, setSlow] = useState(false);
  useEffect(() => {
    const timer = setTimeout(() => setSlow(true), 6000);
    return () => clearTimeout(timer);
  }, []);

  const waitingFor = !fontsLoaded
    ? "Preparing the app\u2019s text\u2026"
    : !authReady
      ? "Checking that you are still signed in\u2026"
      : "Reading your profile\u2026";

  return (
    <View
      style={{
        flex: 1,
        alignItems: "center",
        justifyContent: "center",
        backgroundColor: tokens.colors.ivory,
        paddingHorizontal: 32,
      }}
    >
      <ActivityIndicator size="large" color={tokens.colors.indigo} />
      <Text
        style={{
          marginTop: 20,
          fontSize: 15,
          textAlign: "center",
          color: tokens.colors.stone,
        }}
      >
        Hare Krsna
      </Text>
      {slow ? (
        <Text
          style={{
            marginTop: 10,
            fontSize: 13,
            lineHeight: 19,
            textAlign: "center",
            color: tokens.colors.stoneMuted,
          }}
        >
          {waitingFor}
          {"\n"}This is taking longer than usual — check your connection.
        </Text>
      ) : null}
    </View>
  );
}

function ConnectionBanner() {
  return <ConnectionBar reachable={useServerReachable()} />;
}

const Stack = createNativeStackNavigator<RootStackParamList>();
const navigationRef = createNavigationContainerRef<RootStackParamList>();
const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 3_000,
      refetchOnMount: "always",
      refetchOnWindowFocus: true,
      retry: 1,
    },
  },
});

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

/**
 * Stands between a signed-in devotee and the app until the temple holds the six
 * answers it asks of everyone: photo, name, number, birthday, profession and
 * how to address them.
 *
 * The answer comes from the profile the server returns, never from a flag kept
 * on this phone, so a devotee who filled these in on another device — or years
 * ago — walks straight past. It lives inside the query provider because that is
 * where the profile is read, and reuses the same query as every other screen so
 * standing here costs no extra request.
 *
 * It sits behind the password gate rather than in front of it: someone who does
 * not know their password has a sign-in that is already broken, and asking them
 * for a birthday first would leave that broken while they typed.
 */
function RequiredProfileGate({
  onSignOut,
  children,
}: {
  onSignOut: () => void;
  children: ReactNode;
}) {
  const activeUserId = usePrototypeSession((state) => state.activeUserId);
  const required = useRequiredProfile(activeUserId);

  if (required.status === "checking") {
    return <StartupScreen fontsLoaded authReady />;
  }

  if (required.status === "blocked") {
    return (
      <CompleteProfileScreen missing={required.missing} onSignOut={onSignOut} />
    );
  }

  return <>{children}</>;
}

function LiveSubscriptions() {
  useTemplePresenceRealtime();
  useServiceRealtime();
  useAppNotificationsRealtime();
  return null;
}

function openNotificationDestination(data: Record<string, unknown>) {
  if (!navigationRef.isReady()) return;
  const target = getNotificationTarget({
    kind: typeof data.kind === "string" ? data.kind : null,
    data,
  });
  if (!target) return;

  navigationRef.navigate("MainTabs", {
    screen: target.tab,
    params: target.params as never,
  });
}

export default function App() {
  const authenticate = usePrototypeSession((state) => state.authenticate);
  const signOut = usePrototypeSession((state) => state.signOut);
  const setActiveUserId = usePrototypeSession((state) => state.setActiveUserId);
  const [authReady, setAuthReady] = useState(false);
  const [hasSession, setHasSession] = useState(false);
  const [mustSetPassword, setMustSetPassword] = useState(false);
  const [fontsLoaded] = useFonts({
    AtkinsonHyperlegible_400Regular,
    AtkinsonHyperlegible_700Bold,
    Lora_500Medium_Italic,
    Lora_600SemiBold,
  });

  useEffect(() => {
    const supabase = getSupabaseClient();

    supabase.auth
      .getSession()
      .then(({ data }) => {
        setHasSession(Boolean(data.session));
        setActiveUserId(data.session?.user.id ?? null);
      })
      .finally(() => {
        setAuthReady(true);
      });

    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_event, session) => {
      setHasSession(Boolean(session));
      setActiveUserId(session?.user.id ?? null);
      if (!session) queryClient.clear();
      setAuthReady(true);
    });

    return () => subscription.unsubscribe();
  }, [setActiveUserId]);

  // A reset or magic link arrives as a deep link. It carries the session in
  // the URL, so it has to be exchanged here rather than left to the browser.
  useEffect(() => {
    let active = true;

    const consume = async (url: string | null) => {
      if (!url || !url.includes("auth/recover")) return;
      try {
        const session = await createSessionFromRecoveryUrl(url);
        if (!active || !session) return;
        // A magic link signs them straight in; only a recovery link means the
        // password itself is unknown and has to be replaced.
        if (isRecoveryUrl(url)) setMustSetPassword(true);
      } catch (error) {
        Alert.alert(
          "That link did not work",
          error instanceof Error
            ? error.message
            : "Please request a new link and try again.",
        );
      }
    };

    void Linking.getInitialURL().then(consume);
    const subscription = Linking.addEventListener("url", ({ url }) =>
      consume(url),
    );
    return () => {
      active = false;
      subscription.remove();
    };
  }, []);

  useEffect(() => {
    if (!hasSession) return;
    return subscribeToNotifications(openNotificationDestination);
  }, [hasSession]);

  useEffect(() => {
    focusManager.setFocused(AppState.currentState === "active");
    const subscription = AppState.addEventListener("change", (state) => {
      focusManager.setFocused(state === "active");
    });
    return () => subscription.remove();
  }, []);

  // Signing out from the profile gate has no navigator to return to — the gate
  // stands in place of one — so dropping the session is the whole of it: the
  // Welcome screen is what mounts once there is no longer a devotee signed in.
  const leaveTheApp = () => {
    void signOutFromSupabase()
      .catch(() => undefined)
      .finally(() => signOut());
  };

  if (!fontsLoaded || !authReady) {
    // Rendering nothing here used to leave a blank screen with no way to tell
    // whether the app was working or wedged — and no way to tell which of the
    // two was stuck. A slow network is the common case, so it says so.
    return <StartupScreen fontsLoaded={fontsLoaded} authReady={authReady} />;
  }

  // Stands in front of everything: the devotee is signed in from the link but
  // still does not know their password, and sending them into the app would
  // leave the next sign-in failing exactly as before.
  if (mustSetPassword) {
    return (
      <GestureHandlerRootView className="flex-1">
        <SafeAreaProvider>
          <ErrorBoundary>
            <SetNewPasswordScreen onDone={() => setMustSetPassword(false)} />
          </ErrorBoundary>
        </SafeAreaProvider>
      </GestureHandlerRootView>
    );
  }

  return (
    <GestureHandlerRootView className="flex-1">
      <SafeAreaProvider>
        <ErrorBoundary>
          <ConnectionBanner />
        <QueryClientProvider client={queryClient}>
          {hasSession ? <LiveSubscriptions /> : null}
          <RequiredProfileGate onSignOut={leaveTheApp}>
            <NavigationContainer ref={navigationRef} theme={navigationTheme}>
              <StatusBar style="dark" />
              <Stack.Navigator
                initialRouteName={hasSession ? "MainTabs" : "Welcome"}
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
                      onAuthenticated={() => {
                        authenticate();
                        navigation.replace("MainTabs");
                      }}
                    />
                  )}
                </Stack.Screen>
                <Stack.Screen name="MainTabs" options={{ headerShown: false }}>
                  {({ navigation }) => (
                    <MainTabs
                      onSignOut={() => {
                        void signOutFromSupabase()
                          .catch(() => undefined)
                          .finally(() => {
                            signOut();
                            navigation.replace("Welcome");
                          });
                      }}
                    />
                  )}
                </Stack.Screen>
              </Stack.Navigator>
            </NavigationContainer>
          </RequiredProfileGate>
        </QueryClientProvider>
        </ErrorBoundary>
      </SafeAreaProvider>
    </GestureHandlerRootView>
  );
}
