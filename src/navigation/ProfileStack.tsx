import { createNativeStackNavigator } from "@react-navigation/native-stack";

import tokens from "../../design-tokens.json";
import { ProfileScreen } from "../screens/ProfileScreen";
import { RecurringInterestInboxScreen } from "../screens/RecurringInterestInboxScreen";
import { RecurringInterestScreen } from "../screens/RecurringInterestScreen";
import { AboutThisAppScreen } from "../screens/AboutThisAppScreen";
import { AccessRequestReviewScreen } from "../screens/AccessRequestReviewScreen";
import {
  DevoteeConversationScreen,
  DevoteeConversationsScreen,
} from "../screens/DevoteeConversationsScreen";
import { DevoteeDirectoryScreen } from "../screens/DevoteeDirectoryScreen";
import { ManageAccessScreen } from "../screens/ManageAccessScreen";
import { NotificationSettingsScreen } from "../screens/NotificationSettingsScreen";
import { PrivacyVisibilityScreen } from "../screens/PrivacyVisibilityScreen";
import { ProfileDetailsScreen } from "../screens/ProfileDetailsScreen";
import { RequestAccessScreen } from "../screens/RequestAccessScreen";
import { TermsOfServiceScreen } from "../screens/TermsOfServiceScreen";
import { ChangePasswordScreen } from "../screens/ChangePasswordScreen";
import { AllDonationsScreen } from "../screens/AllDonationsScreen";
import { MyDonationsScreen } from "../screens/MyDonationsScreen";
import { MyServiceHistoryScreen } from "../screens/MyServiceHistoryScreen";
import { AskAnotherVerifierScreen } from "../screens/AskAnotherVerifierScreen";
import { CreateRecurringServiceScreen } from "../screens/CreateRecurringServiceScreen";
import { ProposeServiceTimeScreen } from "../screens/ProposeServiceTimeScreen";
import { ReportUnavailableScreen } from "../screens/ReportUnavailableScreen";
import { SangaJoinedScreen } from "../screens/SangaJoinedScreen";
import { ServiceDetailScreen } from "../screens/ServiceDetailScreen";
import { SevaListScreen } from "../screens/SevaListScreen";
import { SevaRegistrationDetailScreen } from "../screens/SevaRegistrationDetailScreen";
import { WeeklySevaDetailScreen } from "../screens/WeeklySevaDetailScreen";
import type { ProfileStackParamList } from "./types";

const Stack = createNativeStackNavigator<ProfileStackParamList>();

export function ProfileStack({ onSignOut }: { onSignOut: () => void }) {
  return (
    <Stack.Navigator
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
      <Stack.Screen name="ProfileHome" options={{ headerShown: false }}>
        {() => <ProfileScreen onSignOut={onSignOut} />}
      </Stack.Screen>
      <Stack.Screen
        name="RecurringInterest"
        component={RecurringInterestScreen}
        options={{ title: "Weekly seva profile" }}
      />
      <Stack.Screen
        name="RecurringInterestInbox"
        component={RecurringInterestInboxScreen}
        options={{ title: "Weekly seva interests" }}
      />
      <Stack.Screen
        name="ProfileDetails"
        component={ProfileDetailsScreen}
        options={{ title: "Your details" }}
      />
      <Stack.Screen
        name="DevoteeDirectory"
        component={DevoteeDirectoryScreen}
        options={{ title: "Congregation" }}
      />
      <Stack.Screen
        name="DevoteeConversations"
        component={DevoteeConversationsScreen}
        options={{ title: "Devotee conversations" }}
      />
      <Stack.Screen
        name="DevoteeConversation"
        component={DevoteeConversationScreen}
        // The header carries both names, so the stack never shows two threads
        // with the same title.
        options={({ route }) => ({
          title: `${route.params.firstName} & ${route.params.secondName}`,
        })}
      />
      <Stack.Screen
        name="RequestAccess"
        component={RequestAccessScreen}
        options={{ title: "Request access" }}
      />
      <Stack.Screen
        name="AccessRequestReview"
        component={AccessRequestReviewScreen}
        options={{ title: "Access request" }}
      />
      <Stack.Screen
        name="ManageAccess"
        component={ManageAccessScreen}
        options={{ title: "Manage access" }}
      />
      <Stack.Screen
        name="PrivacyVisibility"
        component={PrivacyVisibilityScreen}
        options={{ title: "Privacy and visibility" }}
      />
      <Stack.Screen
        name="TermsOfService"
        component={TermsOfServiceScreen}
        options={{ title: "Terms of Service" }}
      />
      <Stack.Screen
        name="ChangePassword"
        component={ChangePasswordScreen}
        options={{ title: "Change password" }}
      />
      <Stack.Screen
        name="NotificationSettings"
        component={NotificationSettingsScreen}
        options={{ title: "Notifications" }}
      />
      <Stack.Screen
        name="MyServiceHistory"
        component={MyServiceHistoryScreen}
        options={{ title: "My seva and history" }}
      />
      {/*
        Everything "My seva and history" opens, registered here as well as in
        ServicesStack. The screen is reachable from two tabs on purpose, and
        without these four every card tap and every "See all" from the Profile
        tab failed with "not handled by any navigator" — silently, because a
        navigation that goes nowhere raises only in development.
      */}
      <Stack.Screen
        name="ServiceDetail"
        component={ServiceDetailScreen}
        options={{ title: "Service details" }}
      />
      <Stack.Screen
        name="WeeklySevaDetail"
        component={WeeklySevaDetailScreen}
        options={{ title: "Weekly seva" }}
      />
      <Stack.Screen
        name="SevaRegistrationDetail"
        component={SevaRegistrationDetailScreen}
        options={{ title: "Seva record" }}
      />
      <Stack.Screen
        name="SevaList"
        component={SevaListScreen}
        options={{ title: "Seva" }}
      />
      <Stack.Screen
        name="ReportUnavailable"
        component={ReportUnavailableScreen}
        options={{ title: "Can’t make this seva" }}
      />
      <Stack.Screen
        name="ProposeServiceTime"
        component={ProposeServiceTimeScreen}
        options={{ title: "Offer another time" }}
      />
      <Stack.Screen
        name="AskAnotherVerifier"
        component={AskAnotherVerifierScreen}
        options={{ title: "Ask another member" }}
      />
      <Stack.Screen
        name="CreateRecurringService"
        component={CreateRecurringServiceScreen}
        options={{ title: "New weekly seva" }}
      />
      <Stack.Screen
        name="AllDonations"
        component={AllDonationsScreen}
        options={{ title: "All giving" }}
      />
      <Stack.Screen
        name="MyDonations"
        component={MyDonationsScreen}
        options={{ title: "My donations" }}
      />
      <Stack.Screen
        name="SangaJoined"
        component={SangaJoinedScreen}
        options={{ title: "My sangas" }}
      />
      <Stack.Screen
        name="AboutThisApp"
        component={AboutThisAppScreen}
        options={{ title: "About this app" }}
      />
    </Stack.Navigator>
  );
}
