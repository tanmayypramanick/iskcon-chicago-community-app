import { Ionicons } from "@expo/vector-icons";
import { useCallback, useEffect, useRef, useState } from "react";
import {
  Animated,
  Easing,
  Modal,
  Pressable,
  ScrollView,
  Text,
  View,
  type LayoutChangeEvent,
} from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";

import tokens from "../../design-tokens.json";
import { Button } from "./ui";

export type ActionSheetAction = {
  label: string;
  icon?: keyof typeof Ionicons.glyphMap;
  /** Draws the row in vermilion. */
  destructive?: boolean;
  /** Puts a second step in front of the action, inside the same sheet. */
  confirm?: { title: string; message?: string; confirmLabel: string };
  onPress: () => void;
};

type ActionSheetProps = {
  visible: boolean;
  title: string;
  /** A line under the title, for why an action is missing or what this is. */
  message?: string;
  actions: readonly ActionSheetAction[];
  cancelLabel?: string;
  onClose: () => void;
};

const ENTER_MS = 220;
const EXIT_MS = 160;
/** Far enough below the fold to hide any sheet before it has been measured. */
const UNMEASURED_OFFSET = 1000;

/**
 * A bottom sheet of choices, in place of Alert.alert.
 *
 * Android's native alert only has three buttons — positive, negative and
 * neutral — so any menu longer than that silently loses actions there. This
 * draws the same list itself and behaves identically on both platforms.
 */
export function ActionSheet({
  visible,
  title,
  message,
  actions,
  cancelLabel = "Cancel",
  onClose,
}: ActionSheetProps) {
  const insets = useSafeAreaInsets();
  const progress = useRef(new Animated.Value(0)).current;
  const [mounted, setMounted] = useState(false);
  // Measured rather than guessed: the slide has to begin exactly one sheet
  // below the fold, whatever the actions add up to.
  const [sheetHeight, setSheetHeight] = useState<number | null>(null);
  const [confirming, setConfirming] = useState<ActionSheetAction | null>(null);
  /**
   * Run once the sheet has gone, never while it is dismissing: an Alert raised
   * against a modal that is still on screen is refused on iOS.
   */
  const afterClose = useRef<(() => void) | null>(null);

  useEffect(() => {
    if (visible) setMounted(true);
  }, [visible]);

  const measured = sheetHeight !== null;

  useEffect(() => {
    if (!mounted) return;
    // Nothing to slide in from until the sheet has been laid out once.
    if (visible && !measured) return;

    const animation = Animated.timing(progress, {
      toValue: visible ? 1 : 0,
      duration: visible ? ENTER_MS : EXIT_MS,
      easing: visible ? Easing.out(Easing.cubic) : Easing.in(Easing.cubic),
      useNativeDriver: true,
    });
    animation.start(({ finished }) => {
      if (!finished || visible) return;
      setMounted(false);
      setSheetHeight(null);
      setConfirming(null);
      const run = afterClose.current;
      afterClose.current = null;
      run?.();
    });
    return () => animation.stop();
    // Only whether a height is known matters, not what it is — a later
    // measurement must not restart the entrance.
  }, [measured, mounted, progress, visible]);

  const onSheetLayout = useCallback((event: LayoutChangeEvent) => {
    setSheetHeight(event.nativeEvent.layout.height);
  }, []);

  const runAction = useCallback(
    (action: ActionSheetAction) => {
      afterClose.current = action.onPress;
      onClose();
    },
    [onClose],
  );

  const selectAction = useCallback(
    (action: ActionSheetAction) => {
      if (action.confirm) {
        setConfirming(action);
        return;
      }
      runAction(action);
    },
    [runAction],
  );

  const pendingConfirm = confirming?.confirm;
  const translateY = progress.interpolate({
    inputRange: [0, 1],
    outputRange: [sheetHeight ?? UNMEASURED_OFFSET, 0],
  });

  return (
    <Modal
      visible={mounted}
      transparent
      animationType="none"
      statusBarTranslucent
      onRequestClose={onClose}
    >
      <View className="flex-1 justify-end">
        <Animated.View
          className="absolute inset-0 bg-stone/60"
          style={{ opacity: progress }}
        />
        <Pressable
          className="flex-1"
          accessibilityRole="button"
          accessibilityLabel={`Close ${title}`}
          onPress={onClose}
        />
        <Animated.View
          className="max-h-[85%] rounded-t-card bg-ivory px-screen pt-3"
          style={{
            transform: [{ translateY }],
            paddingBottom: Math.max(insets.bottom, 12),
          }}
          onLayout={onSheetLayout}
          accessibilityViewIsModal
          accessibilityLiveRegion="polite"
        >
          <View className="mb-3 h-1 w-10 self-center rounded-pill bg-border" />

          {confirming && pendingConfirm ? (
            <>
              <Text
                className="font-display text-xl text-stone"
                accessibilityRole="header"
              >
                {pendingConfirm.title}
              </Text>
              {pendingConfirm.message ? (
                <Text className="mt-1.5 font-sans text-sm leading-6 text-stoneMuted">
                  {pendingConfirm.message}
                </Text>
              ) : null}
              <Pressable
                className="mt-5 min-h-touch flex-row items-center justify-center rounded-button bg-vermilion px-5 py-3"
                accessibilityRole="button"
                accessibilityLabel={pendingConfirm.confirmLabel}
                onPress={() => runAction(confirming)}
              >
                <Ionicons
                  name={confirming.icon ?? "trash-outline"}
                  size={20}
                  color={tokens.colors.white}
                />
                <Text className="ml-2 font-sans-bold text-base text-white">
                  {pendingConfirm.confirmLabel}
                </Text>
              </Pressable>
              <View className="mt-2">
                <Button variant="secondary" onPress={() => setConfirming(null)}>
                  Back
                </Button>
              </View>
            </>
          ) : (
            <>
              <Text
                className="font-display text-xl text-stone"
                accessibilityRole="header"
              >
                {title}
              </Text>
              {message ? (
                <Text className="mt-1.5 font-sans text-sm leading-6 text-stoneMuted">
                  {message}
                </Text>
              ) : null}

              {actions.length ? (
                // shrink, so a long list scrolls inside the sheet's max height
                // instead of pushing Cancel off the bottom of the screen.
                <ScrollView
                  className="mt-4 shrink"
                  bounces={false}
                  showsVerticalScrollIndicator={false}
                >
                  <View className="overflow-hidden rounded-card border border-border bg-white">
                    {actions.map((action, index) => (
                      <Pressable
                        key={action.label}
                        className={`min-h-touch flex-row items-center px-card py-3 ${
                          index < actions.length - 1
                            ? "border-b border-border"
                            : ""
                        }`}
                        accessibilityRole="button"
                        accessibilityLabel={action.label}
                        accessibilityHint={
                          action.confirm ? "You will be asked to confirm" : undefined
                        }
                        onPress={() => selectAction(action)}
                      >
                        {action.icon ? (
                          <Ionicons
                            name={action.icon}
                            size={20}
                            color={
                              action.destructive
                                ? tokens.colors.vermilion
                                : tokens.colors.indigo
                            }
                          />
                        ) : null}
                        <Text
                          className={`${action.icon ? "ml-3" : ""} font-sans-bold text-base ${
                            action.destructive ? "text-vermilion" : "text-stone"
                          }`}
                        >
                          {action.label}
                        </Text>
                      </Pressable>
                    ))}
                  </View>
                </ScrollView>
              ) : null}

              <View className="mt-3">
                <Button variant="secondary" onPress={onClose}>
                  {cancelLabel}
                </Button>
              </View>
            </>
          )}
        </Animated.View>
      </View>
    </Modal>
  );
}
