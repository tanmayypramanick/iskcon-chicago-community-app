import { View } from "react-native";

import { Screen, ScreenTitle } from "../components/ui";
import { useCurrentAccessProfile } from "../features/access/hooks";
import { hasAccessPermission } from "../features/access/model";
import {
  WeeklySevaAnswerList,
  WeeklySevaAnswersSection,
} from "../features/services/weeklyAnswer";
import { usePrototypeSession } from "../store/usePrototypeSession";

/**
 * The weekly question, in full.
 *
 * The seva board shows two of these and sends the rest here, the way every
 * other section on that tab does — it is already a long scroll, and this is a
 * question nobody is obliged to answer.
 *
 * Whoever set the rota up sees what was answered underneath, because a missed
 * day is the thing somebody has to know about.
 */
export function WeeklySevaAnswersScreen() {
  const activeUserId = usePrototypeSession((state) => state.activeUserId);
  const previewRole = usePrototypeSession((state) => state.previewRole);
  const profile = useCurrentAccessProfile(activeUserId);
  const role =
    __DEV__ && previewRole ? previewRole : (profile.data?.role ?? "devotee");
  const coordinates = hasAccessPermission(role, "services.resolve_coverage");

  return (
    <Screen topInset={false}>
      <ScreenTitle eyebrow="Weekly seva">Did you serve?</ScreenTitle>
      <WeeklySevaAnswerList />

      {coordinates ? (
        <View className="mt-section">
          <WeeklySevaAnswersSection limit={50} />
        </View>
      ) : null}
    </Screen>
  );
}
