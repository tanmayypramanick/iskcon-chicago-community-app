/// <reference types="jest" />

import { getSupabaseClient } from "../../../lib/supabase";
import { removeConversationForMe } from "../api";

jest.mock("../../../lib/supabase", () => ({
  getSupabaseClient: jest.fn(),
}));

const mockGetSupabaseClient = jest.mocked(getSupabaseClient);

describe("messaging API", () => {
  beforeEach(() => jest.clearAllMocks());

  it("clears a conversation through the per-devotee RPC", async () => {
    const rpc = jest.fn().mockResolvedValue({ data: null, error: null });
    mockGetSupabaseClient.mockReturnValue({ rpc } as never);

    await removeConversationForMe("conversation-1");

    expect(rpc).toHaveBeenCalledWith("remove_conversation_for_me", {
      p_conversation_id: "conversation-1",
    });
  });

  it("surfaces a refused conversation removal", async () => {
    const rpc = jest.fn().mockResolvedValue({
      data: null,
      error: { message: "This conversation is not yours.", code: "P0001" },
    });
    mockGetSupabaseClient.mockReturnValue({ rpc } as never);

    await expect(removeConversationForMe("conversation-2")).rejects.toEqual(
      expect.objectContaining({ message: "This conversation is not yours." }),
    );
  });
});
