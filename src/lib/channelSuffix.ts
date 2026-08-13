import { useRef } from "react";

let channelSeq = 0;

/**
 * A number unique to one mounted hook, for building a Realtime channel name.
 *
 * `supabase.channel()` hands back an *existing* channel when the name matches,
 * and adding listeners to one that has already subscribed throws. So any two
 * screens that watch the same thing under the same fixed name break each other
 * the moment both are mounted — which happens on every push transition, where
 * the screen being left and the screen arriving are both alive for a beat.
 */
export function useChannelSuffix() {
  const ref = useRef<number | undefined>(undefined);
  if (ref.current === undefined) {
    channelSeq += 1;
    ref.current = channelSeq;
  }
  return ref.current;
}
