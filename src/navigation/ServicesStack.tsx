import { createNativeStackNavigator } from "@react-navigation/native-stack";

import tokens from "../../design-tokens.json";
import { CreateServiceScreen } from "../screens/CreateServiceScreen";
import { FindSevaScreen } from "../screens/FindSevaScreen";
import { CreateRecurringServiceScreen } from "../screens/CreateRecurringServiceScreen";
import { CoverageDetailScreen } from "../screens/CoverageDetailScreen";
import { CoverageInboxScreen } from "../screens/CoverageInboxScreen";
import { AskAnotherVerifierScreen } from "../screens/AskAnotherVerifierScreen";
import { SevaRegistrationDetailScreen } from "../screens/SevaRegistrationDetailScreen";
import { ProposeServiceTimeScreen } from "../screens/ProposeServiceTimeScreen";
import { EditServiceRequestScreen } from "../screens/EditServiceRequestScreen";
import { MyServiceHistoryScreen } from "../screens/MyServiceHistoryScreen";
import { ProposeAlternativeScreen } from "../screens/ProposeAlternativeScreen";
import { SevaApprovalsScreen } from "../screens/SevaApprovalsScreen";
import { RecurringServicesScreen } from "../screens/RecurringServicesScreen";
import { ReportUnavailableScreen } from "../screens/ReportUnavailableScreen";
import { ScheduleScreen } from "../screens/ScheduleScreen";
import { ServiceDetailScreen } from "../screens/ServiceDetailScreen";
import { ServiceActivityScreen } from "../screens/ServiceActivityScreen";
import { ServicesScreen } from "../screens/ServicesScreen";
import { SevaListScreen } from "../screens/SevaListScreen";
import { WeeklySevaAnswersScreen } from "../screens/WeeklySevaAnswersScreen";
import { WeeklySevaDetailScreen } from "../screens/WeeklySevaDetailScreen";
import { WeeklySevaUpdatesScreen } from "../screens/WeeklySevaUpdatesScreen";
import type { ServicesStackParamList } from "./types";

const Stack = createNativeStackNavigator<ServicesStackParamList>();

export function ServicesStack() {
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
      <Stack.Screen
        name="ServicesHome"
        component={ServicesScreen}
        options={{ headerShown: false }}
      />
      <Stack.Screen
        name="ServiceDetail"
        component={ServiceDetailScreen}
        options={{ title: "Service details" }}
      />
      <Stack.Screen
        name="CreateService"
        component={CreateServiceScreen}
        options={{ title: "Post a requirement" }}
      />
      <Stack.Screen
        name="FindSeva"
        component={FindSevaScreen}
        options={({ route }) => ({
          title:
            route.params?.mode === "completed"
              ? "Log your seva"
              : "Find a way to help",
        })}
      />
      <Stack.Screen
        name="RecurringServices"
        component={RecurringServicesScreen}
        options={{ title: "Weekly seva" }}
      />
      <Stack.Screen
        name="CreateRecurringService"
        component={CreateRecurringServiceScreen}
        options={{ title: "New weekly seva" }}
      />
      <Stack.Screen
        name="ReportUnavailable"
        component={ReportUnavailableScreen}
        options={{ title: "Can’t make this seva" }}
      />
      <Stack.Screen
        name="CoverageInbox"
        component={CoverageInboxScreen}
        options={{ title: "Coverage inbox" }}
      />
      <Stack.Screen
        name="CoverageDetail"
        component={CoverageDetailScreen}
        options={{ title: "Arrange coverage" }}
      />
      <Stack.Screen
        name="AskAnotherVerifier"
        component={AskAnotherVerifierScreen}
        options={{ title: "Ask another member" }}
      />
      <Stack.Screen
        name="ProposeServiceTime"
        component={ProposeServiceTimeScreen}
        options={{ title: "Offer another time" }}
      />
      <Stack.Screen
        name="EditServiceRequest"
        component={EditServiceRequestScreen}
        options={{ title: "Change this seva" }}
      />
      <Stack.Screen
        name="SevaRegistrationDetail"
        component={SevaRegistrationDetailScreen}
        options={{ title: "Registered seva" }}
      />
      <Stack.Screen
        name="SevaApprovals"
        component={SevaApprovalsScreen}
        options={{ title: "Seva approvals" }}
      />
      <Stack.Screen
        name="ProposeAlternative"
        component={ProposeAlternativeScreen}
        options={{ title: "Offer another time" }}
      />
      <Stack.Screen
        name="MyServiceHistory"
        component={MyServiceHistoryScreen}
        options={{ title: "My seva and history" }}
      />
      <Stack.Screen
        name="ServiceActivity"
        component={ServiceActivityScreen}
        options={{ title: "Completed seva report" }}
      />
      <Stack.Screen
        name="WeeklySevaDetail"
        component={WeeklySevaDetailScreen}
        options={{ title: "Weekly seva" }}
      />
      <Stack.Screen
        name="SevaList"
        component={SevaListScreen}
        options={{ title: "Seva" }}
      />
      <Stack.Screen
        name="WeeklySevaAnswers"
        component={WeeklySevaAnswersScreen}
        options={{ title: "Did you serve?" }}
      />
      <Stack.Screen
        name="WeeklySevaUpdates"
        component={WeeklySevaUpdatesScreen}
        options={{ title: "Weekly seva updates" }}
      />
      {/* The title is set by the screen: whose timetable it is decides it. */}
      <Stack.Screen
        name="Schedule"
        component={ScheduleScreen}
        options={{ title: "Timetable" }}
      />
    </Stack.Navigator>
  );
}
