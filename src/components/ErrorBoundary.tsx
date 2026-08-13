import { Ionicons } from "@expo/vector-icons";
import { Component, type ErrorInfo, type ReactNode } from "react";
import { Pressable, Text, View } from "react-native";

import tokens from "../../design-tokens.json";
import { reportCrash } from "../services/crashReporting";

type Props = { children: ReactNode };
type State = { error: Error | null };

/**
 * The last line before a white screen.
 *
 * A render error anywhere in the tree unmounts everything, which on a phone
 * looks like the app dying. This catches it, tells the devotee something they
 * can act on, and records it so the crash is not lost to whoever hit it.
 */
export class ErrorBoundary extends Component<Props, State> {
  state: State = { error: null };

  static getDerivedStateFromError(error: Error): State {
    return { error };
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    reportCrash(error, { componentStack: info.componentStack ?? undefined });
  }

  render() {
    const { error } = this.state;
    if (!error) return this.props.children;

    return (
      <View className="flex-1 items-center justify-center bg-ivory px-8">
        <View className="h-16 w-16 items-center justify-center rounded-pill bg-marigoldSoft">
          <Ionicons
            name="leaf-outline"
            size={30}
            color={tokens.colors.stone}
          />
        </View>
        <Text className="mt-5 text-center font-display text-2xl text-stone">
          Something went wrong
        </Text>
        <Text className="mt-2 max-w-80 text-center font-sans text-base leading-6 text-stoneMuted">
          Your seva is safe. Try again, and if this keeps happening please tell
          a Tech Admin.
        </Text>
        {__DEV__ ? (
          <Text className="mt-4 text-center font-sans text-xs text-vermilion">
            {error.message}
          </Text>
        ) : null}
        <Pressable
          className="mt-7 min-h-touch items-center justify-center rounded-button bg-marigold px-8"
          accessibilityRole="button"
          accessibilityLabel="Try again"
          onPress={() => this.setState({ error: null })}
        >
          <Text className="font-sans-bold text-base text-stone">Try again</Text>
        </Pressable>
      </View>
    );
  }
}
