/**
 * Kept in step with the app_notifications kind CHECK constraint. A kind the
 * database can write but the client does not know about would slip past every
 * exhaustive check here, so notificationKinds.test.ts compares the two.
 */
export const appNotificationKinds = [
  "service_open",
  "service_offer",
  "service_recurring_offer",
  "service_offer_response",
  "service_joined",
  "service_left",
  "service_started",
  "service_completed",
  "service_cancelled",
  "service_deleted",
  "service_coverage_needed",
  "service_coverage_resolved",
  "recurring_interest_submitted",
  "recurring_interest_reviewed",
  "seva_verification_requested",
  "seva_verification_reviewed",
  "weekly_offer_countered",
  "weekly_offer_counter_reviewed",
  "access_request_submitted",
  "access_request_reviewed",
  "devotee_joined",
  "profile_incomplete",
  "sanga_created",
  "sanga_reviewed",
  "sanga_join_requested",
  "sanga_join_reviewed",
  "sanga_member_added",
  "sanga_member_removed",
  "sanga_member_left",
  "sanga_admin_transferred",
  "sanga_deleted",
  "announcement_posted",
  "darshan_posted",
  "feedback_reviewed",
  "care_reply",
  "birthday_today",
  "newsletter_posted",
  "newsletter_reviewed",
  "access_appointed",
  "access_revoked",
  "sponsorship_fulfilled",
  "announcement_commented",
  "announcement_comment_replied",
  "seva_award_earned",
  "vaisnava_tomorrow",
  "vaisnava_today",
  "vaisnava_parana",
  "message_received",
  "sanga_message_received",
  "remote",
] as const;

export type AppNotificationRow = {
  id: string;
  user_id: string;
  kind:
    | "service_open"
    | "service_offer"
    | "service_recurring_offer"
    | "service_offer_response"
    | "service_joined"
    | "service_left"
    | "service_started"
    | "service_completed"
    | "service_cancelled"
    | "service_deleted"
    | "service_coverage_needed"
    | "service_coverage_resolved"
    | "recurring_interest_submitted"
    | "recurring_interest_reviewed"
    | "seva_verification_requested"
    | "seva_verification_reviewed"
    | "weekly_offer_countered"
    | "weekly_offer_counter_reviewed"
    | "access_request_submitted"
    | "access_request_reviewed"
    | "devotee_joined"
    | "profile_incomplete"
    | "sanga_created"
    | "sanga_reviewed"
    | "sanga_join_requested"
    | "sanga_join_reviewed"
    | "sanga_member_added"
    | "sanga_member_removed"
    | "sanga_member_left"
    | "sanga_admin_transferred"
    | "sanga_deleted"
    | "announcement_posted"
    | "darshan_posted"
    | "feedback_reviewed"
    | "care_reply"
    | "birthday_today"
    | "newsletter_posted"
    | "newsletter_reviewed"
    | "access_appointed"
    | "access_revoked"
    | "sponsorship_fulfilled"
    | "announcement_commented"
    | "announcement_comment_replied"
    | "seva_award_earned"
    | "vaisnava_tomorrow"
    | "vaisnava_today"
    | "vaisnava_parana"
    | "message_received"
    | "sanga_message_received"
    | "remote";
  title: string;
  body: string;
  data: Record<string, unknown>;
  created_at: string;
  read_at: string | null;
};
