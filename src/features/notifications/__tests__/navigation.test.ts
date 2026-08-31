/// <reference types="jest" />

import { appNotificationKinds } from "../types";
import {
  getNotificationTarget,
  withNotificationBackHistory,
} from "../navigation";

describe("notification navigation", () => {
  it.each([
    ["announcement_posted", "Home", "Announcements"],
    ["announcement_commented", "Home", "Announcements"],
    ["birthday_today", "Home", "Announcements"],
    ["darshan_posted", "Home", "DailyDarshan"],
    ["care_reply", "Home", "DevoteeCare"],
    ["feedback_reviewed", "Home", "Feedback"],
    ["newsletter_posted", "Home", "Newsletter"],
    ["sponsorship_fulfilled", "Home", "MyDonations"],
    ["seva_award_earned", "Home", "SevaYatra"],
    ["vaisnava_tomorrow", "Home", "VaisnavaCalendar"],
    ["vaisnava_today", "Home", "VaisnavaCalendar"],
    ["vaisnava_parana", "Home", "VaisnavaCalendar"],
    ["sanga_member_removed", "Devotees", "DevoteesHome"],
    ["devotee_joined", "Devotees", "DevoteesHome"],
    ["profile_incomplete", "Profile", "ProfileDetails"],
    ["access_appointed", "Profile", "ProfileHome"],
  ])("routes %s to %s/%s", (kind, tab, screen) => {
    expect(getNotificationTarget({ kind, data: {} })).toMatchObject({
      tab,
      params: { screen },
    });
  });

  it("routes coverage and service records by their identifiers", () => {
    expect(
      getNotificationTarget({
        kind: "service_coverage_needed",
        data: { serviceExceptionId: "exception-1" },
      }),
    ).toEqual({
      tab: "Services",
      params: {
        screen: "CoverageDetail",
        params: { exceptionId: "exception-1" },
      },
    });
    expect(
      getNotificationTarget({
        kind: "service_started",
        data: { serviceInstanceId: "service-1" },
      }),
    ).toMatchObject({ tab: "Services", params: { screen: "ServiceDetail" } });
  });

  it("opens an access submission on its exact review screen", () => {
    expect(
      getNotificationTarget({
        kind: "access_request_submitted",
        data: { accessRequestId: "request-1" },
      }),
    ).toEqual({
      tab: "Profile",
      params: {
        screen: "AccessRequestReview",
        params: { requestId: "request-1" },
      },
    });
  });

  it("never routes a deleted seva to a missing detail", () => {
    expect(
      getNotificationTarget({
        kind: "service_deleted",
        data: { serviceInstanceId: "deleted-1" },
      }),
    ).toEqual({ tab: "Services", params: { screen: "ServicesHome" } });
  });

  it("has an intentional answer for every database notification kind", () => {
    const payloads: Record<string, Record<string, string>> = {
      service_open: { serviceInstanceId: "service" },
      service_offer: { serviceOfferId: "offer" },
      service_recurring_offer: { serviceTemplateId: "template" },
      service_offer_response: { serviceOfferId: "offer" },
      service_joined: { serviceInstanceId: "service" },
      service_left: { serviceInstanceId: "service" },
      service_started: { serviceInstanceId: "service" },
      service_completed: { serviceInstanceId: "service" },
      service_cancelled: { serviceInstanceId: "service" },
      service_deleted: { serviceInstanceId: "service" },
      service_coverage_needed: { serviceExceptionId: "exception" },
      service_coverage_resolved: { serviceTemplateId: "template" },
      recurring_interest_submitted: { recurringInterestId: "interest" },
      recurring_interest_reviewed: { recurringInterestId: "interest" },
      seva_verification_requested: { serviceVerificationId: "verification" },
      seva_verification_reviewed: { serviceVerificationId: "verification" },
      weekly_offer_countered: { serviceOfferCounterId: "counter" },
      weekly_offer_counter_reviewed: { serviceOfferCounterId: "counter" },
      access_request_submitted: { accessRequestId: "request" },
      access_request_reviewed: { accessRequestId: "request" },
    };

    for (const kind of appNotificationKinds) {
      if (kind === "remote") continue;
      expect(
        getNotificationTarget({ kind, data: payloads[kind] ?? {} }),
      ).not.toBeNull();
    }
  });

  it("takes a darshan notification to the pictures by its identifier alone", () => {
    // The push payload carries darshanId, so a row whose kind was lost still
    // lands on the gallery rather than nowhere.
    expect(
      getNotificationTarget({ kind: null, data: { darshanId: "darshan-1" } }),
    ).toEqual({ tab: "Home", params: { screen: "DailyDarshan" } });
  });

  it.each([
    ["announcement_posted", {}, "Home", "Announcements"],
    ["darshan_posted", {}, "Home", "DailyDarshan"],
    [
      "message_received",
      { conversationId: "conversation", devoteeId: "devotee", name: "Mira" },
      "Devotees",
      "Chat",
    ],
    ["service_started", { serviceInstanceId: "service" }, "Services", "ServiceDetail"],
    [
      "access_request_submitted",
      { accessRequestId: "request" },
      "Profile",
      "AccessRequestReview",
    ],
  ])(
    "preserves a tab root beneath %s notification destinations",
    (kind, data, tab, screen) => {
      const target = getNotificationTarget({ kind, data });
      expect(target).not.toBeNull();
      expect(withNotificationBackHistory(target!)).toMatchObject({
        tab,
        params: { screen, initial: false },
      });
    },
  );
});
