import { Ionicons } from "@expo/vector-icons";
import { createBottomTabNavigator } from "@react-navigation/bottom-tabs";
import { StackActions } from "@react-navigation/native";

import tokens from "../../design-tokens.json";
import type { MainTabParamList } from "./types";
import { DevoteesStack } from "./DevoteesStack";
import { HomeStack } from "./HomeStack";
import { ProfileStack } from "./ProfileStack";
import { ServicesStack } from "./ServicesStack";

const Tab = createBottomTabNavigator<MainTabParamList>();

const icons: Record<
  keyof MainTabParamList,
  {
    active: keyof typeof Ionicons.glyphMap;
    inactive: keyof typeof Ionicons.glyphMap;
  }
> = {
  Home: { active: "home", inactive: "home-outline" },
  Services: { active: "heart", inactive: "heart-outline" },
  Devotees: { active: "people", inactive: "people-outline" },
  Profile: { active: "person", inactive: "person-outline" },
};

export function MainTabs({ onSignOut }: { onSignOut: () => void }) {
  return (
    <Tab.Navigator
      detachInactiveScreens
      /**
       * A tab bar tap means "show me this tab", not "put me back wherever I
       * left off in it". Each tab keeps its own stack history across switches,
       * so Announcements → Seva → Home used to land back on Announcements.
       *
       * The tab's stack is popped rather than reset, so its root screen keeps
       * the state it has already built up. `popToTopOnBlur` would be less code
       * but it fires on every blur, including the hop to another tab a screen
       * makes on its own — a comment thread opening a devotee's profile — and
       * would throw away a half-written comment nobody asked to discard. Only
       * an explicit tab press resets, and nothing here touches a stack's own
       * history, so the Android back button and the iOS back swipe still walk
       * it one screen at a time.
       */
      screenListeners={({ navigation }) => ({
        tabPress: (event) => {
          const stack = navigation
            .getState()
            .routes.find((route) => route.key === event.target)?.state;
          if (!stack?.key) return;

          const index = stack.index ?? stack.routes.length - 1;
          if (index < 1) return;

          // Targeted, because this runs before the tab switch: an untargeted
          // pop would land on whichever tab is still focused.
          navigation.dispatch({
            ...StackActions.popToTop(),
            target: stack.key,
          });
        },
      })}
      screenOptions={({ route }) => ({
        headerShown: false,
        // All four tabs used to mount eagerly and stay unfrozen, so a single
        // dashboard cache update re-rendered Home, Seva, Devotees and Profile
        // together. On a slow device that stalled the JS thread long enough to
        // delay the temple check-in switch. Background tabs are now frozen and
        // Seva/Devotees/Profile mount on first visit.
        lazy: true,
        freezeOnBlur: true,
        tabBarActiveTintColor: tokens.colors.indigo,
        tabBarInactiveTintColor: tokens.colors.stoneMuted,
        tabBarLabelStyle: {
          fontFamily: "SourceSans3_700Bold",
          fontSize: 11,
          paddingBottom: 1,
        },
        tabBarStyle: {
          backgroundColor: tokens.colors.white,
          borderTopColor: tokens.colors.border,
          height: 66,
          paddingTop: 5,
        },
        tabBarIcon: ({ color, focused, size }) => (
          <Ionicons
            name={
              focused ? icons[route.name].active : icons[route.name].inactive
            }
            color={color}
            size={size}
          />
        ),
      })}
    >
      <Tab.Screen name="Home" component={HomeStack} />
      <Tab.Screen
        name="Services"
        component={ServicesStack}
        options={{ tabBarLabel: "Seva" }}
      />
      <Tab.Screen
        name="Devotees"
        component={DevoteesStack}
        options={{ tabBarLabel: "Devotees" }}
      />
      <Tab.Screen name="Profile">
        {() => <ProfileStack onSignOut={onSignOut} />}
      </Tab.Screen>
    </Tab.Navigator>
  );
}
