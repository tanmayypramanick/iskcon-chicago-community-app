import type { MainTabParamList } from "../../navigation/types";

export type NotificationTarget = {
  tab: keyof MainTabParamList;
  params: unknown;
};

/**
 * React Navigation normally treats a nested screen supplied while a tab is
 * first mounting as that stack's initial route. A notification that opened
 * ServiceDetail, Chat, or Announcements could therefore create a one-screen
 * stack with no back button. `initial: false` keeps the stack's declared root
 * underneath the notification destination, including on a cold app launch.
 */
export function withNotificationBackHistory(
  target: NotificationTarget,
): NotificationTarget {
  if (!target.params || typeof target.params !== "object") return target;
  return {
    ...target,
    params: { ...target.params, initial: false },
  };
}

type NotificationLike = {
  kind?: string | null;
  data: Record<string, unknown>;
};

/**
 * The single routing contract for both operating-system push taps and rows in
 * the in-app bell. Keeping this pure makes every notification kind testable
 * without mounting navigation or a native notification module.
 */
export function getNotificationTarget({
  kind: suppliedKind,
  data,
}: NotificationLike): NotificationTarget | null {
  const text = (key: string) =>
    typeof data[key] === "string" ? (data[key] as string) : null;
  const kind = suppliedKind ?? text("kind") ?? "remote";

  if (
    text("announcementId") ||
    [
      "announcement_posted",
      "announcement_commented",
      "announcement_comment_replied",
      "birthday_today",
    ].includes(kind)
  ) {
    return { tab: "Home", params: { screen: "Announcements" } };
  }

  // The congregation is told the Deities have been dressed; what they want is
  // the photographs, not the inbox row they tapped.
  if (kind === "darshan_posted" || text("darshanId")) {
    return { tab: "Home", params: { screen: "DailyDarshan" } };
  }

  if (kind === "care_reply") {
    return { tab: "Home", params: { screen: "DevoteeCare" } };
  }
  if (kind === "feedback_reviewed") {
    return { tab: "Home", params: { screen: "Feedback" } };
  }
  if (["newsletter_posted", "newsletter_reviewed"].includes(kind)) {
    return { tab: "Home", params: { screen: "Newsletter" } };
  }
  if (kind === "sponsorship_fulfilled") {
    return { tab: "Home", params: { screen: "MyDonations" } };
  }
  if (kind === "seva_award_earned") {
    return { tab: "Home", params: { screen: "SevaYatra" } };
  }
  // A devotee reading "today is Ekadasi" or "the fast may be broken between
  // 7:15 and 8:48" wants the calendar, not the inbox they tapped from.
  if (["vaisnava_tomorrow", "vaisnava_today", "vaisnava_parana"].includes(kind)) {
    return { tab: "Home", params: { screen: "VaisnavaCalendar" } };
  }

  if (kind === "message_received") {
    const conversationId = text("conversationId");
    const devoteeId = text("devoteeId");
    const name = text("name");
    if (conversationId && devoteeId && name) {
      return {
        tab: "Devotees",
        params: {
          screen: "Chat",
          params: { conversationId, devoteeId, name },
        },
      };
    }
    return {
      tab: "Devotees",
      params: { screen: "DevoteesHome", params: { section: "messages" } },
    };
  }

  if (kind === "sanga_message_received") {
    const sangaId = text("sangaId");
    const name = text("sangaName");
    if (sangaId && name) {
      return {
        tab: "Devotees",
        params: { screen: "SangaChat", params: { sangaId, name } },
      };
    }
    return {
      tab: "Devotees",
      params: { screen: "DevoteesHome", params: { section: "sanga" } },
    };
  }

  if (kind.startsWith("sanga_") || text("sangaId")) {
    // Some sanga events remove access or concern a rejected request, so the
    // stable destination is the sanga list rather than a chat that may refuse
    // the devotee or no longer exist.
    return {
      tab: "Devotees",
      params: { screen: "DevoteesHome", params: { section: "sanga" } },
    };
  }
  if (kind === "devotee_joined") {
    return {
      tab: "Devotees",
      params: { screen: "DevoteesHome", params: { section: "directory" } },
    };
  }

  const exceptionId = text("serviceExceptionId");
  if (kind === "service_coverage_needed" && exceptionId) {
    return {
      tab: "Services",
      params: {
        screen: "CoverageDetail",
        params: { exceptionId },
      },
    };
  }

  if (text("serviceVerificationId")) {
    return {
      tab: "Services",
      params: {
        screen:
          kind === "seva_verification_requested"
            ? "SevaApprovals"
            : "ServicesHome",
      },
    };
  }
  if (text("serviceOfferCounterId")) {
    return { tab: "Services", params: { screen: "SevaApprovals" } };
  }

  const accessRequestId = text("accessRequestId");
  if (kind === "access_request_submitted" && accessRequestId) {
    return {
      tab: "Profile",
      params: {
        screen: "AccessRequestReview",
        params: { requestId: accessRequestId },
      },
    };
  }
  if (accessRequestId || kind.startsWith("access_")) {
    return { tab: "Profile", params: { screen: "ProfileHome" } };
  }
  if (kind === "profile_incomplete") {
    return { tab: "Profile", params: { screen: "ProfileDetails" } };
  }

  const serviceId = text("serviceInstanceId");
  if (serviceId) {
    // A deleted seva has no detail left to open.
    if (kind === "service_deleted") {
      return { tab: "Services", params: { screen: "ServicesHome" } };
    }
    return {
      tab: "Services",
      params: { screen: "ServiceDetail", params: { serviceId } },
    };
  }
  if (text("serviceOfferId")) {
    return { tab: "Services", params: { screen: "ServicesHome" } };
  }
  const templateId = text("serviceTemplateId");
  if (templateId) {
    return {
      tab: "Services",
      params: { screen: "WeeklySevaDetail", params: { templateId } },
    };
  }
  if (text("recurringInterestId")) {
    return {
      tab: "Profile",
      params: {
        screen:
          kind === "recurring_interest_submitted"
            ? "RecurringInterestInbox"
            : "RecurringInterest",
      },
    };
  }
  if (text("serviceSessionId")) {
    return { tab: "Services", params: { screen: "ServicesHome" } };
  }

  return null;
}
