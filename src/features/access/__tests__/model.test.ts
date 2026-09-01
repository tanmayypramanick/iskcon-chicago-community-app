/// <reference types="jest" />

import {
  appointableAccessRolesFor,
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

  /**
   * 202609010103. The two offices held identical permissions until this one,
   * and the asymmetry is the point: somebody has to be able to replace the
   * President, and it cannot be the President.
   */
  it("gives only the Tech Admin the power to appoint every level", () => {
    expect(hasAccessPermission("tech", "access.manage_any")).toBe(true);
    for (const role of ["president", "core", "volunteer", "devotee"] as const) {
      expect(hasAccessPermission(role, "access.manage_any")).toBe(false);
    }

    expect(appointableAccessRolesFor(true)).toEqual([
      "volunteer",
      "core",
      "tech",
      "president",
    ]);
    expect(appointableAccessRolesFor(false)).toEqual(["volunteer", "core"]);
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
