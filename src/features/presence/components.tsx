import { Text, View } from "react-native";

/**
 * "At temple", in the one form it takes anywhere in the app.
 *
 * It sits at the trailing end of a devotee's row, in the directory and in the
 * message list. The width cap and the shrink are what keep a long name and a
 * badge on the same line on a 320dp phone instead of one shoving the other off
 * the row.
 */
export function AtTempleBadge() {
  return (
    <View className="ml-2 max-w-[104px] flex-shrink flex-row items-center rounded-pill bg-peacockSoft px-2.5 py-1.5">
      <View className="mr-1.5 h-2 w-2 rounded-pill bg-peacock" />
      <Text
        className="flex-shrink font-sans-bold text-xs text-peacock"
        numberOfLines={1}
      >
        At temple
      </Text>
    </View>
  );
}
