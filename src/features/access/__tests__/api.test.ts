/// <reference types="jest" />

import { getSupabaseClient } from "../../../lib/supabase";
import {
  createAccessRequest,
  fetchCurrentAccessProfile,
  fetchPendingAccessRequests,
  reviewAccessRequest,
} from "../api";

jest.mock("../../../lib/supabase", () => ({
  getSupabaseClient: jest.fn(),
}));

const mockGetSupabaseClient = jest.mocked(getSupabaseClient);

function queryReturning<T>(result: T) {
  const builder = {
    select: jest.fn(),
    eq: jest.fn(),
    single: jest.fn().mockResolvedValue({ data: result, error: null }),
    // The profile read uses maybeSingle so a missing row is a null rather than
    // an error, which lets the caller narrow its columns and retry.
    maybeSingle: jest.fn().mockResolvedValue({ data: result, error: null }),
  };
  builder.select.mockReturnValue(builder);
  builder.eq.mockReturnValue(builder);
  return builder;
}

describe("access API", () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it("loads the signed-in user's production role", async () => {
    const profileQuery = queryReturning({
      id: "user-1",
      name: "Tanmay Pramanick",
      email: "tanmay@example.com",
      phone: null,
      photo_url: null,
      ashram_status: null,
      role_id: "role-president",
      joined_at: "2026-07-31T07:57:12.370Z",
    });
    const roleQuery = queryReturning({
      id: "role-president",
      name: "president",
    });
    const rpc = jest.fn();

    mockGetSupabaseClient.mockReturnValue({
      auth: {
        getUser: jest.fn().mockResolvedValue({
          data: { user: { id: "user-1" } },
          error: null,
        }),
      },
      from: jest.fn((table: string) =>
        table === "users" ? profileQuery : roleQuery,
      ),
      rpc,
    } as never);

    await expect(fetchCurrentAccessProfile()).resolves.toMatchObject({
      id: "user-1",
      name: "Tanmay Pramanick",
      role: "president",
      roleId: "role-president",
    });
  });

  it("uses the protected RPCs for requesting and reviewing access", async () => {
    const rpc = jest.fn().mockResolvedValue({ error: null });
    mockGetSupabaseClient.mockReturnValue({ rpc } as never);

    await createAccessRequest(
      "volunteer",
      "I would like to post kitchen seva.",
      "approver-1",
    );
    await reviewAccessRequest("request-1", "approved", "Welcome.");

    // A request must carry both a reason and the member it is addressed to;
    // the database refuses it otherwise.
    expect(rpc).toHaveBeenNthCalledWith(1, "create_access_request", {
      requested_role_name: "volunteer",
      p_message: "I would like to post kitchen seva.",
      p_approver_id: "approver-1",
    });
    expect(rpc).toHaveBeenNthCalledWith(2, "review_access_request", {
      access_request_id: "request-1",
      decision: "approved",
      p_note: "Welcome.",
    });
  });

  it("resolves pending requests with requester and role details", async () => {
    const requestBuilder = {
      select: jest.fn(),
      eq: jest.fn(),
      order: jest.fn(),
      returns: jest.fn().mockResolvedValue({
        data: [
          {
            id: "request-1",
            requester_id: "user-2",
            // The devotee this request names, who may answer it whatever
            // their role — carried through so the review screen can tell.
            approver_id: "approver-1",
            requested_role_id: "role-core",
            status: "pending",
            created_at: "2026-08-02T12:00:00.000Z",
            reviewed_at: null,
            reviewed_by: null,
          },
        ],
        error: null,
      }),
    };
    requestBuilder.select.mockReturnValue(requestBuilder);
    requestBuilder.eq.mockReturnValue(requestBuilder);
    requestBuilder.order.mockReturnValue(requestBuilder);

    const requesterBuilder = {
      select: jest.fn(),
      in: jest.fn(),
      returns: jest.fn().mockResolvedValue({
        data: [
          {
            id: "user-2",
            name: "Mohit Sharma",
            email: "mohit@example.com",
            phone: null,
            photo_url: null,
            ashram_status: null,
            role_id: "role-volunteer",
            joined_at: "2026-08-01T12:00:00.000Z",
          },
        ],
        error: null,
      }),
    };
    requesterBuilder.select.mockReturnValue(requesterBuilder);
    requesterBuilder.in.mockReturnValue(requesterBuilder);

    const roleBuilder = {
      select: jest.fn(),
      in: jest.fn(),
      returns: jest.fn().mockResolvedValue({
        data: [
          { id: "role-volunteer", name: "volunteer" },
          { id: "role-core", name: "core" },
        ],
        error: null,
      }),
    };
    roleBuilder.select.mockReturnValue(roleBuilder);
    roleBuilder.in.mockReturnValue(roleBuilder);

    mockGetSupabaseClient.mockReturnValue({
      from: jest.fn((table: string) => {
        if (table === "access_requests") return requestBuilder;
        if (table === "users") return requesterBuilder;
        return roleBuilder;
      }),
    } as never);

    await expect(fetchPendingAccessRequests()).resolves.toEqual([
      {
        id: "request-1",
        requesterId: "user-2",
        approverId: "approver-1",
        requesterName: "Mohit Sharma",
        currentRole: "volunteer",
        requestedRole: "core",
        status: "pending",
        createdAt: "2026-08-02T12:00:00.000Z",
      },
    ]);
  });

  it("does not allow privileged roles to be requested", async () => {
    const rpc = jest.fn();
    mockGetSupabaseClient.mockReturnValue({ rpc } as never);

    await expect(
      createAccessRequest("president", "Please", "approver-1"),
    ).rejects.toThrow(
      "Only Volunteer or Community Head access can be requested.",
    );
    expect(rpc).not.toHaveBeenCalled();
  });
});
