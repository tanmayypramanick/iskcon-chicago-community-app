/// <reference types="jest" />

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { act, renderHook, waitFor } from "@testing-library/react-native";
import type { PropsWithChildren } from "react";

import { fetchSevaClashes } from "../api";
import { useClashGate, useSevaClashLookup } from "../hooks";
import type { SevaClash } from "../types";

// hooks.ts reaches the Supabase client for its Realtime channel, and building
// one for real opens the device's SQLite session store.
jest.mock("../../../lib/supabase", () => ({
  getSupabaseClient: () => ({
    channel: () => ({ on: () => ({ on: () => ({}) }), subscribe: () => ({}) }),
    removeChannel: jest.fn(),
  }),
}));

jest.mock("../api", () => ({
  fetchSevaClashes: jest.fn(),
}));

const mockFetch = jest.mocked(fetchSevaClashes);

const CLASH: SevaClash = {
  service_instance_id: "other-seva",
  template_id: null,
  from_weekly_template: false,
  seva_name: "Kitchen Preparation",
  name_visible: true,
  occurs_on: "2099-08-06",
  starts_at_local: "12:00:00",
  ends_at_local: "13:30:00",
  ends_next_day: false,
  starts_at: "2099-08-06T17:00:00Z",
  ends_at: "2099-08-06T18:30:00Z",
  status: "open",
  assignment_status: "confirmed",
  is_substitute: false,
  overlap_minutes: 15,
  overlap_starts_at: "2099-08-06T18:15:00Z",
  overlap_ends_at: "2099-08-06T18:30:00Z",
  covers_whole_request: false,
};

const TARGET = {
  name: "Ravi Das",
  devoteeId: "ravi",
  date: "2099-08-06",
  startTime: "13:15:00",
  durationMinutes: 75,
};

let queryClient: QueryClient;

function wrapper({ children }: PropsWithChildren) {
  return (
    <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
  );
}

beforeEach(() => {
  jest.clearAllMocks();
  queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });
});

describe("the gate in front of asking a devotee", () => {
  it("asks straight away when the devotee is free", async () => {
    mockFetch.mockResolvedValue([]);
    const proceed = jest.fn();
    const view = await renderHook(() => useClashGate(proceed), { wrapper });

    await act(async () => {
      view.result.current.ask(TARGET);
    });
    await waitFor(() => expect(proceed).toHaveBeenCalledWith(TARGET));

    expect(view.result.current.warning).toBeNull();
  });

  it("holds the invitation back and says why when they are not", async () => {
    mockFetch.mockResolvedValue([CLASH]);
    const proceed = jest.fn();
    const view = await renderHook(() => useClashGate(proceed), { wrapper });

    await act(async () => {
      view.result.current.ask(TARGET);
    });
    await waitFor(() => expect(view.result.current.warning).not.toBeNull());

    expect(proceed).not.toHaveBeenCalled();
    expect(view.result.current.warning?.target.name).toBe("Ravi Das");
    expect(view.result.current.warning?.clashes).toEqual([CLASH]);
  });

  it("never refuses: accepting sends the invitation anyway", async () => {
    mockFetch.mockResolvedValue([CLASH]);
    const proceed = jest.fn();
    const view = await renderHook(() => useClashGate(proceed), { wrapper });

    await act(async () => {
      view.result.current.ask(TARGET);
    });
    await waitFor(() => expect(view.result.current.warning).not.toBeNull());
    await act(async () => {
      view.result.current.accept();
    });

    expect(proceed).toHaveBeenCalledWith(TARGET);
    expect(view.result.current.warning).toBeNull();
  });

  it("sends nothing when the warning is simply dismissed", async () => {
    mockFetch.mockResolvedValue([CLASH]);
    const proceed = jest.fn();
    const view = await renderHook(() => useClashGate(proceed), { wrapper });

    await act(async () => {
      view.result.current.ask(TARGET);
    });
    await waitFor(() => expect(view.result.current.warning).not.toBeNull());
    await act(async () => {
      view.result.current.dismiss();
    });

    expect(proceed).not.toHaveBeenCalled();
    expect(view.result.current.warning).toBeNull();
  });

  it("takes the warning down when the clash goes away underneath it", async () => {
    mockFetch.mockResolvedValue([CLASH]);
    const proceed = jest.fn();
    const view = await renderHook(() => useClashGate(proceed), { wrapper });

    await act(async () => {
      view.result.current.ask(TARGET);
    });
    await waitFor(() => expect(view.result.current.warning).not.toBeNull());

    // The clashing seva is cancelled, and useServiceRealtime says so.
    mockFetch.mockResolvedValue([]);
    await act(async () => {
      await queryClient.invalidateQueries({ queryKey: ["services"] });
    });

    await waitFor(() => expect(view.result.current.warning).toBeNull());
    // A warning that clears is not an answer, so nothing was sent.
    expect(proceed).not.toHaveBeenCalled();
  });
});

describe("clash answers asked for up front", () => {
  const REQUEST = { ...TARGET, key: "ravi" };

  it("hands each answer back under the caller's own key", async () => {
    mockFetch.mockResolvedValue([CLASH]);
    const view = await renderHook(() => useSevaClashLookup([REQUEST]), {
      wrapper,
    });

    await waitFor(() =>
      expect(view.result.current.get("ravi")).toEqual([CLASH]),
    );
  });

  it("replaces the answer when realtime says the seva board moved", async () => {
    mockFetch.mockResolvedValue([CLASH]);
    const view = await renderHook(() => useSevaClashLookup([REQUEST]), {
      wrapper,
    });
    await waitFor(() =>
      expect(view.result.current.get("ravi")).toEqual([CLASH]),
    );

    // The clashing seva is handed to somebody else. useServiceRealtime
    // invalidates the whole "services" prefix, which is what this stands in for.
    mockFetch.mockResolvedValue([]);
    await act(async () => {
      await queryClient.invalidateQueries({ queryKey: ["services"] });
    });

    await waitFor(() => expect(view.result.current.get("ravi")).toEqual([]));
    expect(mockFetch).toHaveBeenCalledTimes(2);
  });

  it("holds a true warning steady while its refetch is in the air", async () => {
    // Every unrelated seva change on the tab invalidates this key too. Reading
    // a refetch in flight as "no clash" would take a real warning off screen,
    // and the screens do not put a dismissed one back.
    mockFetch.mockResolvedValue([CLASH]);
    const view = await renderHook(() => useSevaClashLookup([REQUEST]), {
      wrapper,
    });
    await waitFor(() =>
      expect(view.result.current.get("ravi")).toEqual([CLASH]),
    );

    let settle: (clashes: SevaClash[]) => void = () => {};
    mockFetch.mockReturnValue(
      new Promise<SevaClash[]>((resolve) => {
        settle = resolve;
      }),
    );
    await act(async () => {
      void queryClient.invalidateQueries({ queryKey: ["services"] });
    });

    expect(view.result.current.get("ravi")).toEqual([CLASH]);

    await act(async () => {
      settle([CLASH]);
    });
    await waitFor(() =>
      expect(view.result.current.get("ravi")).toEqual([CLASH]),
    );
  });

  it("asks nothing at all for a request the caller has switched off", async () => {
    mockFetch.mockResolvedValue([CLASH]);
    const view = await renderHook(
      () => useSevaClashLookup([{ ...REQUEST, enabled: false }]),
      { wrapper },
    );

    expect(mockFetch).not.toHaveBeenCalled();
    expect(view.result.current.get("ravi")).toEqual([]);
  });
});
