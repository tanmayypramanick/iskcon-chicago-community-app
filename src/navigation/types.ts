import type { NavigatorScreenParams } from "@react-navigation/native";

export type FeatureKey =
  | "communities"
  | "courses"
  | "forum"
  | "rankings"
  | "newsletter"
  | "announcements"
  | "donations"
  | "feedback";

export type MainTabParamList = {
  Home: undefined;
  Services: undefined;
  Directory: undefined;
  Profile: undefined;
};

export type RootStackParamList = {
  Welcome: undefined;
  MainTabs: NavigatorScreenParams<MainTabParamList> | undefined;
  Feature: {
    feature: FeatureKey;
    title: string;
  };
};
