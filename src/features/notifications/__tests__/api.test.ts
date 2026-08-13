/// <reference types="jest" />

import { getSupabaseClient } from "../../../lib/supabase";
import { clearAppNotifications, deleteAppNotification } from "../api";

jest.mock("../../../lib/supabase", () => ({
  getSupabaseClient: jest.fn(),
}));

const mockGetSupabaseClient = jest.mocked(getSupabaseClient);

describe("notification inbox API", () => {
  it("deletes one notification owned by the signed-in user", async () => {
    const builder = {
      delete: jest.fn(),
      eq: jest.fn().mockResolvedValue({ error: null }),
    };
    builder.delete.mockReturnValue(builder);
    mockGetSupabaseClient.mockReturnValue({
      from: jest.fn(() => builder),
    } as never);

    await deleteAppNotification("notification-1");

    expect(builder.delete).toHaveBeenCalledTimes(1);
    expect(builder.eq).toHaveBeenCalledWith("id", "notification-1");
  });

  it("clears the signed-in user's notification inbox", async () => {
    const builder = {
      delete: jest.fn(),
      eq: jest.fn().mockResolvedValue({ error: null }),
    };
    builder.delete.mockReturnValue(builder);
    mockGetSupabaseClient.mockReturnValue({
      from: jest.fn(() => builder),
    } as never);

    await clearAppNotifications("user-1");

    expect(builder.delete).toHaveBeenCalledTimes(1);
    expect(builder.eq).toHaveBeenCalledWith("user_id", "user-1");
  });
});
