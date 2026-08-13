import { createNativeStackNavigator } from "@react-navigation/native-stack";

import tokens from "../../design-tokens.json";
import { ChatScreen } from "../screens/ChatScreen";
import { CreateSangaScreen } from "../screens/CreateSangaScreen";
import { DevoteeProfileScreen } from "../screens/DevoteeProfileScreen";
import { DevoteeSevaProfileScreen } from "../screens/DevoteeSevaProfileScreen";
import { DevoteesScreen } from "../screens/DevoteesScreen";
import { SangaApprovalsScreen } from "../screens/SangaApprovalsScreen";
import { SangaChatScreen } from "../screens/SangaChatScreen";
import { SangaDetailScreen } from "../screens/SangaDetailScreen";
import { SangaInfoScreen } from "../screens/SangaInfoScreen";
import type { DevoteesStackParamList } from "./types";

const Stack = createNativeStackNavigator<DevoteesStackParamList>();

export function DevoteesStack() {
  return (
    <Stack.Navigator
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
      <Stack.Screen
        name="DevoteesHome"
        component={DevoteesScreen}
        options={{ headerShown: false }}
      />
      <Stack.Screen
        name="DevoteeProfile"
        component={DevoteeProfileScreen}
        options={{ title: "Devotee" }}
      />
      <Stack.Screen
        name="DevoteeSevaProfile"
        component={DevoteeSevaProfileScreen}
        options={{ title: "Seva profile" }}
      />
      <Stack.Screen
        name="SangaDetail"
        component={SangaDetailScreen}
        // The sanga's own name in the header, so several open at once are
        // still tellable apart.
        options={({ route }) => ({ title: route.params.name })}
      />
      <Stack.Screen
        name="SangaChat"
        component={SangaChatScreen}
        // The title is set from the screen itself, which draws the sanga's
        // name over its member count and makes both a way into its info.
        options={({ route }) => ({ title: route.params.name })}
      />
      <Stack.Screen
        name="SangaInfo"
        component={SangaInfoScreen}
        options={({ route }) => ({ title: route.params.name })}
      />
      <Stack.Screen
        name="CreateSanga"
        component={CreateSangaScreen}
        options={{ title: "Start a sanga" }}
      />
      <Stack.Screen
        name="SangaApprovals"
        component={SangaApprovalsScreen}
        options={{ title: "Sanga approvals" }}
      />
      <Stack.Screen
        name="Chat"
        component={ChatScreen}
        // The header carries the other devotee's name, so a thread is never
        // just "Chat" once several are open in the stack.
        options={({ route }) => ({ title: route.params.name })}
      />
    </Stack.Navigator>
  );
}
