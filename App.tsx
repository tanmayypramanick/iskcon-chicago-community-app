import "./global.css";
import "react-native-gesture-handler";

import {
  SourceSans3_400Regular,
  SourceSans3_700Bold,
} from "@expo-google-fonts/source-sans-3";
import {
  EBGaramond_500Medium_Italic,
  EBGaramond_600SemiBold,
} from "@expo-google-fonts/eb-garamond";
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
import { useEffect, useRef, useState, type ReactNode } from "react";
import {
  ActivityIndicator,
  AppState,
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
import { AuthLinkProblemScreen } from "./src/screens/AuthLinkProblemScreen";
import { CompleteProfileScreen } from "./src/screens/CompleteProfileScreen";
import {
  EmailVerifiedModal,
  EmailVerifiedScreen,
} from "./src/screens/EmailVerifiedScreen";
import { SetNewPasswordScreen } from "./src/screens/SetNewPasswordScreen";
import { useRequiredProfile } from "./src/features/access/hooks";
import { consumeAuthLink, type AuthLinkOutcome } from "./src/services/auth";
import { useServerReachable } from "./src/lib/connectivity";
import { useAppNotificationsRealtime } from "./src/features/notifications/hooks";
import {
  getNotificationTarget,
  withNotificationBackHistory,
} from "./src/features/notifications/navigation";
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
        Hare Kṛṣṇa
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
      // Realtime carries normal live changes. A three-second stale window made
      // quick tab switches refetch the same dashboards repeatedly.
      staleTime: 30_000,
      refetchOnMount: true,
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
      fontFamily: "SourceSans3_400Regular",
      fontWeight: "400",
    },
    medium: {
      fontFamily: "SourceSans3_700Bold",
      fontWeight: "700",
    },
    bold: {
      fontFamily: "SourceSans3_700Bold",
      fontWeight: "700",
    },
    heavy: {
      fontFamily: "SourceSans3_700Bold",
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
  const rawTarget = getNotificationTarget({
    kind: typeof data.kind === "string" ? data.kind : null,
    data,
  });
  if (!rawTarget) return;
  const target = withNotificationBackHistory(rawTarget);

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
  const [linkOutcome, setLinkOutcome] = useState<AuthLinkOutcome>(null);
  // Read inside the deep-link handler, which closes over its own render's
  // state; the ref is what tells it whether the devotee was already inside the
  // app before the link created a session.
  const hasSessionRef = useRef(false);
  const [fontsLoaded] = useFonts({
    SourceSans3_400Regular,
    SourceSans3_700Bold,
    EBGaramond_500Medium_Italic,
    EBGaramond_600SemiBold,
  });

  useEffect(() => {
    const supabase = getSupabaseClient();

    supabase.auth
      .getSession()
      .then(({ data }) => {
        hasSessionRef.current = Boolean(data.session);
        setHasSession(Boolean(data.session));
        setActiveUserId(data.session?.user.id ?? null);
      })
      .finally(() => {
        setAuthReady(true);
      });

    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_event, session) => {
      hasSessionRef.current = Boolean(session);
      setHasSession(Boolean(session));
      setActiveUserId(session?.user.id ?? null);
      if (!session) queryClient.clear();
      setAuthReady(true);
    });

    return () => subscription.unsubscribe();
  }, [setActiveUserId]);

  // Signup confirmation, reset and magic links arrive as deep links. They
  // carry the session in the URL, so it must be exchanged here rather than
  // left inside the browser.
  //
  // From a cold start `hasSessionRef` may still be false while the stored
  // session is being read. That only decides full screen versus dialog, and a
  // cold start has no place in the app to preserve, so the full screen is the
  // right answer either way.
  useEffect(() => {
    let active = true;

    const consume = async (url: string | null) => {
      const outcome = await consumeAuthLink(url, {
        hadSession: hasSessionRef.current,
      });
      if (active && outcome) setLinkOutcome(outcome);
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

  // Everything an email link can lead to that has to be answered before the
  // app itself. Each stands in front of the navigator for its own reason, and
  // each clears itself once the devotee has been dealt with.
  const standalone =
    linkOutcome?.kind === "recovery" ? (
      // The devotee is signed in from the link but still does not know their
      // password; sending them into the app would leave the next sign-in
      // failing exactly as before.
      <SetNewPasswordScreen
        onDone={() => setLinkOutcome(null)}
        // Awaited before the gate is cleared, so the navigator that mounts
        // behind it is built against a session that has already gone: clearing
        // first would mount MainTabs for a devotee who is on their way out.
        onCancel={async () => {
          await signOutFromSupabase();
          signOut();
          setLinkOutcome(null);
        }}
      />
    ) : linkOutcome?.kind === "problem" ? (
      <AuthLinkProblemScreen
        problem={linkOutcome.problem}
        linkKind={linkOutcome.linkKind}
        onDismiss={() => setLinkOutcome(null)}
      />
    ) : linkOutcome?.kind === "verified" && !linkOutcome.hadSession ? (
      // Arriving from the inbox with nothing on screen to lose: the
      // confirmation is the welcome, and it comes before the profile gate so
      // the first thing they are told is that it worked, not what is missing.
      <EmailVerifiedScreen onContinue={() => setLinkOutcome(null)} />
    ) : null;

  if (standalone) {
    return (
      <GestureHandlerRootView className="flex-1">
        <SafeAreaProvider>
          <ErrorBoundary>{standalone}</ErrorBoundary>
        </SafeAreaProvider>
      </GestureHandlerRootView>
    );
  }

  return (
    <GestureHandlerRootView className="flex-1">
      <SafeAreaProvider>
        <ErrorBoundary>
          <ConnectionBanner />
          {/* Already signed in when the link was opened, so the good news
              arrives over the app rather than in place of it. */}
          <EmailVerifiedModal
            visible={linkOutcome?.kind === "verified"}
            onDismiss={() => setLinkOutcome(null)}
          />
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
                    fontFamily: "SourceSans3_700Bold",
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
