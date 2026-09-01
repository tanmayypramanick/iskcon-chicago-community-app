/// <reference types="jest" />

import { fireEvent, render, screen } from "@testing-library/react-native";
import { SafeAreaProvider } from "react-native-safe-area-context";

import type { WeeklySevaAnswer } from "../../features/services/types";
import { WeeklySevaUpdatesScreen } from "../WeeklySevaUpdatesScreen";

/** What `list_weekly_seva_answers` answered. */
let mockAnswers: WeeklySevaAnswer[] = [];
/** The window the screen asked for, so the 90 days is not just a comment. */
const mockDays = jest.fn();

jest.mock("../../features/services/hooks", () => ({
  useWeeklySevaAnswers: (_enabled: boolean, days: number) => {
    mockDays(days);
    return {
      data: mockAnswers,
      error: null,
      isLoading: false,
      isError: false,
      refetch: jest.fn(),
    };
  },
}));

function answer(over: Partial<WeeklySevaAnswer>): WeeklySevaAnswer {
  return {
    assignment_id: "a1",
    service_instance_id: "i1",
    devotee_id: "d1",
    devotee_name: "Rukmini Devi Dasi",
    devotee_photo_url: null,
    seva_name: "Prasadam Serving",
    occurred_on: "2026-08-30",
    started_at_local: "13:00:00",
    answer: "served",
    ...over,
  };
}

async function draw() {
  await render(
    <SafeAreaProvider
      initialMetrics={{
        frame: { x: 0, y: 0, width: 390, height: 844 },
        insets: { top: 0, left: 0, right: 0, bottom: 0 },
      }}
    >
      <WeeklySevaUpdatesScreen />
    </SafeAreaProvider>,
  );
  return screen;
}

beforeEach(() => {
  mockAnswers = [];
  mockDays.mockClear();
});

describe("Weekly seva updates", () => {
  it("reads back a season, not a fortnight", async () => {
    await draw();
    expect(mockDays).toHaveBeenCalledWith(90);
  });

  it("says there is nothing to report when nobody has answered", async () => {
    const view = await draw();
    expect(view.getByText("Nothing to report")).toBeTruthy();
    // No search box to offer when there is nothing to search.
    expect(view.queryByLabelText("Search by devotee or seva name")).toBeNull();
  });

  it("lists days newest first", async () => {
    mockAnswers = [
      answer({ assignment_id: "old", occurred_on: "2026-08-16" }),
      answer({ assignment_id: "new", occurred_on: "2026-08-30" }),
      answer({ assignment_id: "mid", occurred_on: "2026-08-23" }),
    ];
    const view = await draw();
    const days = view
      .getAllByText(/^\w{3}, \w{3} \d+$/)
      .map((node) => node.props.children as string);
    expect(days).toEqual(["Sun, Aug 30", "Sun, Aug 23", "Sun, Aug 16"]);
  });

  it("counts the answers and says what the window is", async () => {
    mockAnswers = [
      answer({ assignment_id: "a" }),
      answer({ assignment_id: "b", occurred_on: "2026-08-23" }),
    ];
    const view = await draw();
    expect(view.getByText("2 in the last 90 days · newest first")).toBeTruthy();
  });

  it("searches by devotee name", async () => {
    mockAnswers = [
      answer({ assignment_id: "a", devotee_name: "Rukmini Devi Dasi" }),
      answer({ assignment_id: "b", devotee_name: "Nitai Das" }),
    ];
    const view = await draw();
    await fireEvent.changeText(
      view.getByLabelText("Search by devotee or seva name"),
      "nitai",
    );
    expect(view.getByText("Nitai Das")).toBeTruthy();
    expect(view.queryByText("Rukmini Devi Dasi")).toBeNull();
    expect(view.getByText("1 of 2 · newest first")).toBeTruthy();
  });

  it("searches by seva name too", async () => {
    mockAnswers = [
      answer({ assignment_id: "a", seva_name: "Prasadam Serving" }),
      answer({
        assignment_id: "b",
        seva_name: "Mangal Arati Setup",
        devotee_name: "Nitai Das",
      }),
    ];
    const view = await draw();
    await fireEvent.changeText(
      view.getByLabelText("Search by devotee or seva name"),
      "mangal",
    );
    expect(view.getByText("Nitai Das")).toBeTruthy();
    expect(view.queryByText("Rukmini Devi Dasi")).toBeNull();
  });

  it("filters to the days that went uncovered", async () => {
    mockAnswers = [
      answer({ assignment_id: "a", devotee_name: "Rukmini Devi Dasi" }),
      answer({
        assignment_id: "b",
        devotee_name: "Nitai Das",
        answer: "absent",
      }),
    ];
    const view = await draw();
    await fireEvent.press(view.getByLabelText("Show missed — 1"));
    expect(view.getByText("Nitai Das")).toBeTruthy();
    expect(view.queryByText("Rukmini Devi Dasi")).toBeNull();
  });

  it("does not offer a filter nobody's answer would match", async () => {
    mockAnswers = [answer({ assignment_id: "a" })];
    const view = await draw();
    // Every answer is "served", so there is nothing to filter between.
    expect(view.queryByLabelText("Show missed — 0")).toBeNull();
    expect(view.queryByLabelText(/^Show all/)).toBeNull();
  });

  it("says so when a search matches nothing", async () => {
    mockAnswers = [answer({ assignment_id: "a" })];
    const view = await draw();
    await fireEvent.changeText(
      view.getByLabelText("Search by devotee or seva name"),
      "gopala",
    );
    expect(view.getByText("Nothing matches that")).toBeTruthy();
  });

  it("marks a day that went uncovered", async () => {
    mockAnswers = [
      answer({ assignment_id: "a", answer: "absent" }),
      answer({
        assignment_id: "b",
        devotee_name: "Nitai Das",
        answer: "absent",
      }),
    ];
    const view = await draw();
    expect(view.getByText("2 went uncovered")).toBeTruthy();
  });
});
