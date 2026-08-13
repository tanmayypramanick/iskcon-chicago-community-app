/// <reference types="jest" />

import { renderHook } from "@testing-library/react-native";

import { useChannelSuffix } from "../channelSuffix";

describe("a Realtime channel name per subscriber", () => {
  it("gives two mounted hooks two different numbers", async () => {
    const first = await renderHook(() => useChannelSuffix());
    const second = await renderHook(() => useChannelSuffix());

    expect(first.result.current).not.toBe(second.result.current);
  });

  it("keeps one hook's number across re-renders", async () => {
    // The channel is torn down and rebuilt if this ever changes, which would
    // drop every subscription the screen has on every render.
    const view = await renderHook(() => useChannelSuffix());
    const first = view.result.current;

    await view.rerender(undefined);

    expect(view.result.current).toBe(first);
  });
});
