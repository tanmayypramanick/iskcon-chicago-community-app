import type { MainTabParamList } from "../../navigation/types";

export type NotificationTarget = {
  tab: keyof MainTabParamList;
  params: unknown;
};

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

  if (text("accessRequestId") || kind.startsWith("access_")) {
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
