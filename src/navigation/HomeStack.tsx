import { createNativeStackNavigator } from "@react-navigation/native-stack";

import tokens from "../../design-tokens.json";
import { AllDonationsScreen } from "../screens/AllDonationsScreen";
import { AnnouncementCommentsScreen } from "../screens/AnnouncementCommentsScreen";
import { AnnouncementLikesScreen } from "../screens/AnnouncementLikesScreen";
import { AnnouncementsScreen } from "../screens/AnnouncementsScreen";
import { BirthdaysScreen } from "../screens/BirthdaysScreen";
import { DailyDarshanScreen } from "../screens/DailyDarshanScreen";
import { DarshanDayScreen } from "../screens/DarshanDayScreen";
import { DevoteeCareScreen } from "../screens/DevoteeCareScreen";
import { DonationsScreen } from "../screens/DonationsScreen";
import { FeedbackScreen } from "../screens/FeedbackScreen";
import { HomeScreen } from "../screens/HomeScreen";
import { MyDonationsScreen } from "../screens/MyDonationsScreen";
import { NewsletterEditorsScreen } from "../screens/NewsletterEditorsScreen";
import { NewsletterScreen } from "../screens/NewsletterScreen";
import { NewsletterSubmissionsScreen } from "../screens/NewsletterSubmissionsScreen";
import { NotificationsScreen } from "../screens/NotificationsScreen";
import { PostDarshanScreen } from "../screens/PostDarshanScreen";
import { SevaBoardDevoteeScreen } from "../screens/SevaBoardDevoteeScreen";
import { SevaCareDevoteeScreen } from "../screens/SevaCareDevoteeScreen";
import { SevaHistoryScreen } from "../screens/SevaHistoryScreen";
import { SevaYatraScreen } from "../screens/SevaYatraScreen";
import { SponsorshipCalendarScreen } from "../screens/SponsorshipCalendarScreen";
import { TempleTodayScreen } from "../screens/TempleTodayScreen";
import { VaisnavaCalendarScreen } from "../screens/VaisnavaCalendarScreen";
import type { HomeStackParamList } from "./types";

const Stack = createNativeStackNavigator<HomeStackParamList>();

export function HomeStack() {
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
        name="HomeDashboard"
        component={HomeScreen}
        options={{ headerShown: false }}
      />
      <Stack.Screen
        name="Notifications"
        component={NotificationsScreen}
        options={{ title: "Notifications" }}
      />
      <Stack.Screen
        name="TempleToday"
        component={TempleTodayScreen}
        options={{ title: "At the temple today" }}
      />
      <Stack.Screen
        name="Announcements"
        component={AnnouncementsScreen}
        options={{ title: "Announcements" }}
      />
      <Stack.Screen
        name="Birthdays"
        component={BirthdaysScreen}
        options={{ title: "Birthdays" }}
      />
      <Stack.Screen
        name="AnnouncementComments"
        component={AnnouncementCommentsScreen}
        options={{ title: "Comments" }}
      />
      <Stack.Screen
        name="AnnouncementLikes"
        component={AnnouncementLikesScreen}
        options={{ title: "Likes" }}
      />
      <Stack.Screen
        name="Feedback"
        component={FeedbackScreen}
        options={{ title: "Feedback" }}
      />
      <Stack.Screen
        name="DevoteeCare"
        component={DevoteeCareScreen}
        options={{ title: "Devotee care" }}
      />
      <Stack.Screen
        name="Newsletter"
        component={NewsletterScreen}
        options={{ title: "Newsletter" }}
      />
      <Stack.Screen
        name="NewsletterSubmissions"
        component={NewsletterSubmissionsScreen}
        options={{ title: "Story requests" }}
      />
      <Stack.Screen
        name="NewsletterEditors"
        component={NewsletterEditorsScreen}
        options={{ title: "Newsletter editors" }}
      />
      <Stack.Screen
        name="Donations"
        component={DonationsScreen}
        options={{ title: "Giving" }}
      />
      <Stack.Screen
        name="SponsorshipCalendar"
        component={SponsorshipCalendarScreen}
        options={{ title: "Sponsor a seva" }}
      />
      <Stack.Screen
        name="MyDonations"
        component={MyDonationsScreen}
        options={{ title: "My giving" }}
      />
      <Stack.Screen
        name="AllDonations"
        component={AllDonationsScreen}
        options={{ title: "All giving" }}
      />
      <Stack.Screen
        name="SevaYatra"
        component={SevaYatraScreen}
        options={{ title: "Seva Yatra" }}
      />
      <Stack.Screen
        name="VaisnavaCalendar"
        component={VaisnavaCalendarScreen}
        options={{ title: "Vaiṣṇava Calendar" }}
      />
      <Stack.Screen
        name="DailyDarshan"
        component={DailyDarshanScreen}
        options={{ title: "Daily Darshan" }}
      />
      <Stack.Screen
        name="DarshanDay"
        component={DarshanDayScreen}
        options={{ title: "Darshan" }}
      />
      <Stack.Screen
        name="PostDarshan"
        component={PostDarshanScreen}
        options={{ title: "Post darshan" }}
      />
      <Stack.Screen
        name="SevaHistory"
        component={SevaHistoryScreen}
        options={{ title: "My seva history" }}
      />
      <Stack.Screen
        name="SevaCareDevotee"
        component={SevaCareDevoteeScreen}
        options={{ title: "Their seva history" }}
      />
      <Stack.Screen
        name="SevaBoardDevotee"
        component={SevaBoardDevoteeScreen}
        options={{ title: "On the board" }}
      />
    </Stack.Navigator>
  );
}
