import { useCallback, useMemo, useRef, useState, type ReactNode } from "react";
import {
  SectionList,
  Text,
  View,
  type GestureResponderEvent,
  type LayoutChangeEvent,
} from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";

import tokens from "../../design-tokens.json";
import { BotanicalBackdrop } from "./botanical";

export type AlphabetSection<Item> = {
  /** The letter this group files under. `#` collects everything non-Latin. */
  letter: string;
  data: Item[];
};

/** Names that do not start with A–Z are filed together rather than dropped. */
const OTHER = "#";

const SCREEN_PAD = parseInt(tokens.spacing.screen, 10);
/** The visible column of letters, and the gutter the list reserves for it. */
const STRIP_WIDTH = 22;
/** Wider than the letters, so the finger has somewhere forgiving to land. */
const STRIP_HIT_WIDTH = 40;
/** An 11px glyph plus breathing room — below this the letters touch. */
const MIN_ROW_HEIGHT = 13;
/** Matches ListScreen, keeping the strip clear of the tab bar. */
const BOTTOM_PAD = 96;

function initialOf(name: string) {
  const first = name.trim().charAt(0);
  if (!first) return OTHER;
  // Decompose first so "Ānanda" and "Śyāma" file under A and S instead of
  // collapsing into #, which is not where a devotee would look for them.
  const base = (first.normalize ? first.normalize("NFD") : first).charAt(0);
  const upper = base.toLocaleUpperCase("en-US");
  return upper >= "A" && upper <= "Z" ? upper : OTHER;
}

/**
 * Buckets by first letter and sorts within each bucket, so the list reads the
 * way a phone's Contacts does whatever order the server sent.
 */
export function groupByInitial<Item>(
  items: readonly Item[],
  getName: (item: Item) => string,
): AlphabetSection<Item>[] {
  const buckets = new Map<string, Item[]>();
  for (const item of items) {
    const letter = initialOf(getName(item));
    const bucket = buckets.get(letter);
    if (bucket) bucket.push(item);
    else buckets.set(letter, [item]);
  }

  return Array.from(buckets, ([letter, data]) => ({
    letter,
    data: data.sort((a, b) => getName(a).localeCompare(getName(b))),
  })).sort((a, b) => {
    // A name starting with a digit is the exception, not the opening.
    if (a.letter === OTHER) return 1;
    if (b.letter === OTHER) return -1;
    return a.letter.localeCompare(b.letter);
  });
}

/**
 * The column on the right edge, and the letter bubble it raises while a finger
 * is on it.
 *
 * Its own component so that a drag — which changes a letter roughly thirty
 * times on the way down — re-renders twenty-odd labels rather than the list.
 */
function IndexStrip({
  letters,
  bottomInset,
  onJump,
}: {
  letters: readonly string[];
  bottomInset: boolean;
  onJump: (sectionIndex: number) => void;
}) {
  const [height, setHeight] = useState(0);
  const [dragIndex, setDragIndex] = useState<number | null>(null);
  const [selected, setSelected] = useState(0);
  // A refresh can drop the last letter out from under a stale selection.
  const current = Math.min(selected, letters.length - 1);
  // Responder frames arrive faster than state settles, so the guard against
  // firing the same letter twice has to be a ref.
  const lastIndex = useRef<number | null>(null);

  /**
   * Two stages. The labels first share out whatever height there is; only once
   * a row would fall under MIN_ROW_HEIGHT do we start dropping them. Each
   * remaining label sits at the centre of the band the drag maps to it, so the
   * letter under the finger is the letter it jumps to.
   */
  const shown = useMemo(() => {
    const total = letters.length;
    if (!height || !total) return [];
    const capacity = Math.max(1, Math.floor(height / MIN_ROW_HEIGHT));
    if (capacity >= total) return letters;
    return Array.from({ length: capacity }, (_, slot) => {
      const index = Math.floor(((slot + 0.5) * total) / capacity);
      return letters[Math.min(total - 1, index)];
    });
  }, [height, letters]);

  const select = useCallback(
    (index: number) => {
      setSelected(index);
      onJump(index);
    },
    [onJump],
  );

  const trackFinger = useCallback(
    (event: GestureResponderEvent) => {
      const total = letters.length;
      if (!height || !total) return;
      // locationY is relative to the strip because the labels are pointer
      // transparent, which keeps the whole column as the touch target.
      const ratio = event.nativeEvent.locationY / height;
      const index = Math.min(total - 1, Math.max(0, Math.floor(ratio * total)));
      if (lastIndex.current === index) return;
      lastIndex.current = index;
      setDragIndex(index);
      select(index);
    },
    [height, letters.length, select],
  );

  const endTracking = useCallback(() => {
    lastIndex.current = null;
    setDragIndex(null);
  }, []);

  const onLayout = useCallback((event: LayoutChangeEvent) => {
    setHeight(event.nativeEvent.layout.height);
  }, []);

  return (
    <>
      <View
        className="absolute bottom-0 right-0 top-0 flex-row justify-end"
        style={{ paddingTop: 10, paddingBottom: bottomInset ? BOTTOM_PAD : 24 }}
        pointerEvents="box-none"
      >
        <View
          style={{ width: STRIP_HIT_WIDTH }}
          onLayout={onLayout}
          onStartShouldSetResponder={() => true}
          onMoveShouldSetResponder={() => true}
          onResponderGrant={trackFinger}
          onResponderMove={trackFinger}
          onResponderRelease={endTracking}
          onResponderTerminate={endTracking}
          // Without this the list claims the drag as a scroll partway down and
          // the finger stops steering the letters.
          onResponderTerminationRequest={() => false}
          accessible
          accessibilityRole="adjustable"
          accessibilityLabel="Alphabetical index"
          accessibilityHint="Swipe up or down to jump the list to a letter"
          accessibilityValue={{ text: letters[current] }}
          accessibilityActions={[{ name: "increment" }, { name: "decrement" }]}
          onAccessibilityAction={(event) =>
            select(
              event.nativeEvent.actionName === "decrement"
                ? Math.max(0, current - 1)
                : Math.min(letters.length - 1, current + 1),
            )
          }
        >
          <View
            className={`flex-1 items-center justify-around rounded-pill ${
              dragIndex === null ? "" : "bg-white/90"
            }`}
            style={{
              width: STRIP_WIDTH,
              marginLeft: STRIP_HIT_WIDTH - STRIP_WIDTH,
            }}
            pointerEvents="none"
          >
            {shown.map((letter, slot) => (
              <Text
                key={`${letter}-${slot}`}
                className={`font-sans-bold text-[11px] leading-[13px] ${
                  dragIndex !== null && letters[dragIndex] === letter
                    ? "text-peacock"
                    : "text-indigo"
                }`}
              >
                {letter}
              </Text>
            ))}
          </View>
        </View>
      </View>

      {dragIndex === null ? null : (
        <View
          className="absolute inset-0 items-center justify-center"
          pointerEvents="none"
        >
          <View className="h-24 w-24 items-center justify-center rounded-card bg-indigo">
            <Text className="font-display text-4xl text-white">
              {letters[dragIndex]}
            </Text>
          </View>
        </View>
      )}
    </>
  );
}

type Props<Item> = {
  sections: readonly AlphabetSection<Item>[];
  renderItem: (
    item: Item,
    index: number,
    section: AlphabetSection<Item>,
  ) => ReactNode;
  keyExtractor: (item: Item) => string;
  /**
   * Off while a search is running: letter headers and an index over a handful
   * of results are noise, so the same list collapses to a plain one.
   */
  grouped: boolean;
  header?: ReactNode;
  empty?: ReactNode;
  footer?: ReactNode;
  bottomInset?: boolean;
  topInset?: boolean;
};

/**
 * ListScreen's chrome over a SectionList, with the A–Z index a phone Contacts
 * list has: sticky letter headers, and a column on the right edge that jumps
 * the list as a finger drags down it.
 */
export function AlphabetIndexList<Item>({
  sections,
  renderItem,
  keyExtractor,
  grouped,
  header,
  empty,
  footer,
  bottomInset = true,
  topInset = true,
}: Props<Item>) {
  const listRef = useRef<SectionList<Item, AlphabetSection<Item>>>(null);
  const pending = useRef<number | null>(null);
  const retried = useRef(false);

  const visible = useMemo(
    () => sections.filter((section) => section.data.length > 0),
    [sections],
  );
  const letters = useMemo(
    () => (grouped ? visible.map((section) => section.letter) : []),
    [grouped, visible],
  );

  const jumpTo = useCallback((sectionIndex: number) => {
    pending.current = sectionIndex;
    retried.current = false;
    // itemIndex 0 is the section header itself, which is what should come to
    // rest at the top of the viewport.
    listRef.current?.scrollToLocation({
      sectionIndex,
      itemIndex: 0,
      animated: false,
    });
  }, []);

  const onScrollToIndexFailed = useCallback(
    (info: { index: number; averageItemLength: number }) => {
      const target = pending.current;
      if (target === null || retried.current) return;
      retried.current = true;
      // Rows are only measured once mounted, so a jump far past the render
      // window has no offset yet. Land on the estimate, let that batch render,
      // then ask again for the exact position.
      listRef.current?.getScrollResponder()?.scrollTo({
        y: info.averageItemLength * info.index,
        animated: false,
      });
      requestAnimationFrame(() =>
        listRef.current?.scrollToLocation({
          sectionIndex: target,
          itemIndex: 0,
          animated: false,
        }),
      );
    },
    [],
  );

  return (
    <SafeAreaView className="flex-1 bg-ivory" edges={topInset ? ["top"] : []}>
      <BotanicalBackdrop />
      <SectionList
        ref={listRef}
        className="flex-1"
        sections={visible}
        keyExtractor={keyExtractor}
        renderItem={({ item, index, section }) => (
          <>{renderItem(item, index, section)}</>
        )}
        renderSectionHeader={({ section }) =>
          grouped ? (
            <View className="bg-ivory pb-2 pt-4">
              <Text
                className="font-sans-bold text-xs uppercase tracking-widest text-peacock"
                accessibilityRole="header"
              >
                {section.letter}
              </Text>
            </View>
          ) : null
        }
        stickySectionHeadersEnabled={grouped}
        ListHeaderComponent={header ? <>{header}</> : null}
        ListEmptyComponent={empty ? <>{empty}</> : null}
        ListFooterComponent={footer ? <>{footer}</> : null}
        contentContainerStyle={{
          paddingLeft: SCREEN_PAD,
          // The strip's gutter, reserved whether or not it is showing: no row
          // and no search field may sit under it, and a padding that changed
          // as you typed would shuffle the list sideways.
          paddingRight: SCREEN_PAD + STRIP_WIDTH,
          paddingTop: 8,
          paddingBottom: bottomInset ? BOTTOM_PAD : 24,
        }}
        // Also leaves no scrollbar for the strip to collide with.
        showsVerticalScrollIndicator={false}
        keyboardShouldPersistTaps="handled"
        initialNumToRender={12}
        maxToRenderPerBatch={12}
        windowSize={11}
        removeClippedSubviews={false}
        onScrollToIndexFailed={onScrollToIndexFailed}
      />

      {/* One letter is not an index. Scrolling reaches everything regardless. */}
      {letters.length > 1 ? (
        <IndexStrip
          letters={letters}
          bottomInset={bottomInset}
          onJump={jumpTo}
        />
      ) : null}
    </SafeAreaView>
  );
}
