/// <reference types="jest" />

import {
  canRequestAccessRole,
  getRequestableAccessRoles,
  hasAccessPermission,
} from "../model";

describe("access model", () => {
  it("gives President and Tech members full access-review authority", () => {
    expect(hasAccessPermission("president", "access.review_requests")).toBe(
      true,
    );
    expect(hasAccessPermission("tech", "access.review_requests")).toBe(true);
    expect(hasAccessPermission("core", "access.review_requests")).toBe(false);
    expect(hasAccessPermission("volunteer", "access.review_requests")).toBe(
      false,
    );
  });

  it("lets a volunteer post and invite, while coverage stays with coordinators", () => {
    for (const role of ["president", "tech", "core"] as const) {
      expect(hasAccessPermission(role, "services.post_requirement")).toBe(true);
      expect(hasAccessPermission(role, "services.offer_assignment")).toBe(true);
      expect(hasAccessPermission(role, "services.oversee_activity")).toBe(true);
    }

    expect(hasAccessPermission("volunteer", "services.post_requirement")).toBe(true);
    // A Volunteer may ask particular devotees when posting a seva request.
    expect(hasAccessPermission("volunteer", "services.offer_assignment")).toBe(true);
    expect(hasAccessPermission("volunteer", "services.oversee_activity")).toBe(false);
    expect(hasAccessPermission("volunteer", "services.view_all")).toBe(false);

    for (const role of ["president", "tech", "core"] as const) {
      expect(hasAccessPermission(role, "services.resolve_coverage")).toBe(true);
    }
    expect(hasAccessPermission("volunteer", "services.resolve_coverage")).toBe(false);

    for (const role of ["president", "tech"] as const) {
      expect(hasAccessPermission(role, "services.delete_any")).toBe(true);
      expect(hasAccessPermission(role, "services.export_reports")).toBe(true);
    }

    expect(hasAccessPermission("devotee", "services.post_requirement")).toBe(
      false,
    );
  });

  it("allows only the approved upward access-request paths", () => {
    expect(getRequestableAccessRoles("devotee")).toEqual(["volunteer", "core"]);
    expect(getRequestableAccessRoles("volunteer")).toEqual(["core"]);
    expect(canRequestAccessRole("devotee", "president")).toBe(false);
    expect(canRequestAccessRole("core", "president")).toBe(false);
    expect(canRequestAccessRole("volunteer", "core")).toBe(true);
  });
});
