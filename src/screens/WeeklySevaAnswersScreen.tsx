import { Screen, ScreenTitle } from "../components/ui";
import { WeeklySevaAnswerList } from "../features/services/weeklyAnswer";

/**
 * The weekly question, in full.
 *
 * The seva board shows two of these and sends the rest here, the way every
 * other section on that tab does — it is already a long scroll, and this is a
 * question nobody is obliged to answer.
 *
 * Only the devotee's own days. What everybody answered is a different thing
 * for a different reader, and lives in Weekly seva updates.
 */
export function WeeklySevaAnswersScreen() {
  return (
    <Screen topInset={false}>
      <ScreenTitle eyebrow="Weekly seva">Did you serve?</ScreenTitle>
      <WeeklySevaAnswerList />
    </Screen>
  );
}
