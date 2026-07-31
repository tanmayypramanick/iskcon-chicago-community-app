import { Ionicons } from "@expo/vector-icons";
import { createBottomTabNavigator } from "@react-navigation/bottom-tabs";

import tokens from "../../design-tokens.json";
import type { MainTabParamList } from "./types";
import { DirectoryScreen } from "../screens/DirectoryScreen";
import { HomeScreen } from "../screens/HomeScreen";
import { ProfileScreen } from "../screens/ProfileScreen";
import { ServicesScreen } from "../screens/ServicesScreen";

const Tab = createBottomTabNavigator<MainTabParamList>();

const icons: Record<
  keyof MainTabParamList,
  { active: keyof typeof Ionicons.glyphMap; inactive: keyof typeof Ionicons.glyphMap }
> = {
  Home: { active: "home", inactive: "home-outline" },
  Services: { active: "heart", inactive: "heart-outline" },
  Directory: { active: "people", inactive: "people-outline" },
  Profile: { active: "person", inactive: "person-outline" },
};

export function MainTabs({ onSignOut }: { onSignOut: () => void }) {
  return (
    <Tab.Navigator
      screenOptions={({ route }) => ({
        headerShown: false,
        tabBarActiveTintColor: tokens.colors.indigo,
        tabBarInactiveTintColor: tokens.colors.stoneMuted,
        tabBarLabelStyle: {
          fontFamily: "AtkinsonHyperlegible_700Bold",
          fontSize: 13,
          paddingBottom: 2,
        },
        tabBarStyle: {
          backgroundColor: tokens.colors.white,
          borderTopColor: tokens.colors.border,
          height: 76,
          paddingTop: 8,
        },
        tabBarIcon: ({ color, focused, size }) => (
          <Ionicons
            name={focused ? icons[route.name].active : icons[route.name].inactive}
            color={color}
            size={size}
          />
        ),
      })}
    >
      <Tab.Screen name="Home" component={HomeScreen} />
      <Tab.Screen name="Services" component={ServicesScreen} />
      <Tab.Screen name="Directory" component={DirectoryScreen} />
      <Tab.Screen name="Profile">
        {() => <ProfileScreen onSignOut={onSignOut} />}
      </Tab.Screen>
    </Tab.Navigator>
  );
}
