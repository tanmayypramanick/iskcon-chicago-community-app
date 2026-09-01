import type { NavigatorScreenParams } from "@react-navigation/native";

import type { SevaRangeKind } from "../features/sevayatra/types";

export type MainTabParamList = {
  Home: NavigatorScreenParams<HomeStackParamList> | undefined;
  Services: NavigatorScreenParams<ServicesStackParamList> | undefined;
  Devotees: NavigatorScreenParams<DevoteesStackParamList> | undefined;
  Profile: NavigatorScreenParams<ProfileStackParamList> | undefined;
};

/** Which of the Devotees tab's three lists opens first. */
export type DevoteesSection = "messages" | "sanga" | "directory";

export type DevoteesStackParamList = {
  DevoteesHome: { section?: DevoteesSection } | undefined;
  DevoteeProfile: { devoteeId: string };
  /**
   * One devotee's service and giving in full. The name and photo travel with
   * the id so the screen has a heading before anything loads. Only offered to
   * `app.view_all`, and every function behind it answers nothing to anyone else.
   */
  DevoteeSevaProfile: {
    devoteeId: string;
    name: string;
    photoUrl?: string | null;
  };
  /** The door for a devotee who is not in the sanga yet. */
  SangaDetail: { sangaId: string; name: string };
  SangaChat: { sangaId: string; name: string };
  /** What the sanga is, who is in it, and everything you can do about it. */
  SangaInfo: { sangaId: string; name: string };
  CreateSanga: undefined;
  SangaApprovals: undefined;
  Chat: { conversationId: string; devoteeId: string; name: string };
};

export type HomeStackParamList = {
  HomeDashboard: undefined;
  Notifications: undefined;
  TempleToday: undefined;
  Announcements: undefined;
  /** The birthdays coming up. President and Tech Admin only. */
  Birthdays: undefined;
  /** The title travels with the id so the thread names its notice without
   * waiting for the board to load again. */
  AnnouncementComments: { announcementId: string; title: string };
  AnnouncementLikes: { announcementId: string; title: string };
  Feedback: undefined;
  DevoteeCare: undefined;
  Newsletter: undefined;
  /** The editor's queue; the server returns nothing to anyone else. */
  NewsletterSubmissions: undefined;
  NewsletterEditors: undefined;
  /** Where giving starts: a donation, or a sponsored seva. */
  Donations: undefined;
  /** Opened on a sponsorship when the devotee arrived by tapping one. */
  SponsorshipCalendar: { typeId?: string } | undefined;
  /** Also reachable from the Profile tab; the screen takes no parameters. */
  MyDonations: undefined;
  /** The temple-wide view; the server returns nothing to anyone else. */
  AllDonations: undefined;
  /** The devotee's seva profile, and the congregation's leaderboard. */
  SevaYatra: undefined;
  /** Chicago-specific Ekadasis, parana windows, festivals and holy days. */
  VaisnavaCalendar: undefined;
  /** The week of darshan, one entry per day. Every devotee. */
  DailyDarshan: undefined;
  /**
   * Everything posted on one day. The day travels with the id so the screen can
   * name itself before the week's list has been read again — and so a
   * notification that opens straight onto a day still has a heading.
   */
  DarshanDay: { darshanId: string; darshanOn: string };
  /**
   * Composing a day of darshan. Registered for everyone because a notification
   * or a stale link can reach any route; the screen itself, and the server
   * behind it, answer only the three roles that may post.
   */
  PostDarshan: undefined;
  /** Act by act, behind one link off the profile. */
  SevaHistory: undefined;
  /**
   * One devotee's whole seva and giving, off a Seva Care row or off the board.
   * `app.view_all`'s, and the panel behind it is the Devotees tab's own.
   */
  SevaCareDevotee: { devoteeId: string; name: string };
  /**
   * Why a name is where it is on the board, off the board itself. The range
   * travels with the devotee so the screen opens on the period that was being
   * read; the server decides what the caller may actually be told.
   */
  SevaBoardDevotee: {
    devoteeId: string;
    name: string;
    photoUrl?: string | null;
    range: SevaRangeKind;
  };
};

export type ServicesStackParamList = {
  ServicesHome: undefined;
  ServiceDetail: { serviceId: string };
  /**
   * The day and time an empty square on the timetable stood for, so tapping
   * 4:30 on Thursday opens this form already saying Thursday at 4:30. Both are
   * Chicago wall clock, in the shapes the RPC stores: "2026-08-13", "16:30:00".
   */
  CreateService: { date?: string; startTime?: string } | undefined;
  /**
   * One calm entry form with two honest purposes: plan seva that is starting
   * now or later, or record seva that has already been completed.
   */
  FindSeva: { mode?: "plan" | "completed" } | undefined;
  RecurringServices: undefined;
  /** `templateId` edits an existing weekly seva; the rest prefill a new one. */
  CreateRecurringService:
    | {
        templateId?: string;
        startDate?: string;
        startTime?: string;
        /** 0 = Sunday, the day the tapped square was in. */
        dayOfWeek?: number;
      }
    | undefined;
  /**
   * The week-by-week timetable. No parameter is the whole temple and needs the
   * board permission; a devotee's own id is open to them; anybody else's is the
   * "is she free on Thursday" read, and the server refuses all three to anyone
   * who may not make them.
   */
  Schedule:
    | { devoteeId?: string; name?: string; photoUrl?: string | null }
    | undefined;
  ReportUnavailable: { serviceId: string };
  CoverageInbox: undefined;
  CoverageDetail: { exceptionId: string };
  MyServiceHistory: undefined;
  SevaApprovals: undefined;
  AskAnotherVerifier: { verificationId: string };
  SevaRegistrationDetail: { verificationId: string };
  ProposeAlternative: { offerId: string };
  ProposeServiceTime: { offerId: string };
  EditServiceRequest: { serviceId: string };
  ServiceActivity: undefined;
  WeeklySevaDetail: { templateId: string };
  SevaList: { kind: SevaListKind };
};

/**
 * Which list a "See all" opens. Named rather than inlined because the seva
 * screens are registered in two stacks — a devotee reaches "My seva and
 * history" from the Profile tab and from the Seva tab, and both need the same
 * destinations — and two copies of this union would drift.
 */
export type SevaListKind =
  | "my_upcoming"
  | "open_requirements"
  | "community_schedule"
  | "completed"
  | "my_seva"
  | "happening_now"
  | "awaiting_close"
  | "my_registrations";

export type ProfileStackParamList = {
  ProfileHome: undefined;
  RecurringInterest: undefined;
  RecurringInterestInbox: undefined;
  ProfileDetails: undefined;
  MyServiceHistory: undefined;
  // "My seva and history" lives in this stack deliberately — jumping to the
  // Seva tab left a devotee stranded in a tab they did not open. That only
  // works if everything the screen opens is reachable from here too.
  ServiceDetail: { serviceId: string };
  WeeklySevaDetail: { templateId: string };
  SevaRegistrationDetail: { verificationId: string };
  SevaList: { kind: SevaListKind };
  // …and everything those four open in turn.
  ReportUnavailable: { serviceId: string };
  ProposeServiceTime: { offerId: string };
  AskAnotherVerifier: { verificationId: string };
  CreateRecurringService:
    | {
        templateId?: string;
        startDate?: string;
        startTime?: string;
        /** 0 = Sunday, the day the tapped square was in. */
        dayOfWeek?: number;
      }
    | undefined;
  DevoteeDirectory: undefined;
  DevoteeConversations: undefined;
  DevoteeConversation: {
    conversationId: string;
    firstDevoteeId: string;
    firstName: string;
    secondDevoteeId: string;
    secondName: string;
  };
  /** A level to start on, if the devotee arrived by tapping one. */
  RequestAccess: { role?: "volunteer" | "core" } | undefined;
  AccessRequestReview: { requestId: string };
  ManageAccess: undefined;
  PrivacyVisibility: undefined;
  TermsOfService: undefined;
  ChangePassword: undefined;
  NotificationSettings: undefined;
  MyDonations: undefined;
  /** The temple-wide giving record; the server returns nothing to anyone else. */
  AllDonations: undefined;
  SangaJoined: undefined;
  AboutThisApp: undefined;
};

export type RootStackParamList = {
  Welcome: undefined;
  MainTabs: NavigatorScreenParams<MainTabParamList> | undefined;
};
