/// <reference types="jest" />

import { fireEvent, render } from "@testing-library/react-native";
import { Alert } from "react-native";

import type { DailyDarshan } from "../../features/dailyDarshan/types";
import { DarshanDayScreen } from "../DarshanDayScreen";

/** Chicago's today, pinned, so "Today" means the same thing every run. */
const TODAY = "2026-08-26";

jest.mock("@react-navigation/native", () => ({ useIsFocused: () => false }));

jest.mock("../../lib/chicagoDate", () => ({
  ...jest.requireActual("../../lib/chicagoDate"),
  getChicagoDateKey: () => TODAY,
  addChicagoDays: () => "2026-08-25",
}));

// Reaching the share sheet needs native modules a test runner has not got, and
// nothing here is about saving a picture.
jest.mock("../../lib/sharePicture", () => ({
  sharePicture: jest.fn().mockResolvedValue(undefined),
}));

jest.mock("../../lib/supabase", () => ({ getSupabaseClient: jest.fn() }));

let mockDays: DailyDarshan[] = [];
const mockDelete = jest.fn();

jest.mock("../../features/dailyDarshan/hooks", () => ({
  ...jest.requireActual("../../features/dailyDarshan/hooks"),
  useDailyDarshan: () => ({
    data: mockDays,
    error: null,
    isLoading: false,
    isError: false,
    isRefetching: false,
    isFetching: false,
    dataUpdatedAt: Date.now(),
    refetch: jest.fn(),
  }),
  useDeleteDailyDarshan: () => ({ mutate: mockDelete, isPending: false }),
}));

const goBack = jest.fn();
const navigation = { navigate: jest.fn(), goBack } as never;

function day(
  images: DailyDarshan["images"],
  extra: Partial<DailyDarshan> = {},
): DailyDarshan {
  return {
    id: "darshan-today",
    darshan_on: TODAY,
    note: null,
    images,
    posted_by: "head-1",
    posted_by_name: "Gopal das",
    posted_by_photo_url: null,
    created_at: `${TODAY}T12:00:00.000Z`,
    can_delete: false,
    ...extra,
  };
}

beforeEach(() => {
  jest.clearAllMocks();
  mockDays = [];
});

async function renderScreen() {
  return render(
    <DarshanDayScreen
      navigation={navigation}
      route={
        {
          params: { darshanId: "darshan-today", darshanOn: TODAY },
        } as never
      }
    />,
  );
}

describe("one day of darshan", () => {
  it("shows everything posted on that day, each picture with its own pairing", async () => {
    mockDays = [
      day(
        [
          {
            imageUrl: "https://temple.example/a.jpg",
            deity: "Kisora Kisori",
            dressedBy: "Rukmini devi dasi",
            position: 0,
          },
          {
            imageUrl: "https://temple.example/b.jpg",
            deity: "Gaura Nitai",
            dressedBy: "Bhakta Arjun",
            position: 1,
          },
          {
            imageUrl: "https://temple.example/c.jpg",
            deity: "Srila Prabhupada",
            dressedBy: null,
            position: 2,
          },
        ],
        { note: "Jhulan Yatra" },
      ),
    ];

    const view = await renderScreen();

    expect(view.getByText("Today")).toBeTruthy();
    expect(view.getByText("3 pictures")).toBeTruthy();
    expect(view.getByText("Jhulan Yatra")).toBeTruthy();
    expect(view.getByText("Posted by Gopal das")).toBeTruthy();

    // All three, on the one screen — the day is where the pictures live now.
    expect(
      view.getAllByHintText("Opens it full size, where it can be saved"),
    ).toHaveLength(3);

    // A photograph with no label is invisible to a screen reader, so every one
    // of them carries its own pairing rather than the day's.
    expect(
      view.getByLabelText("Kisora Kisori, dressed by Rukmini devi dasi, Today"),
    ).toBeTruthy();
    expect(
      view.getByLabelText("Gaura Nitai, dressed by Bhakta Arjun, Today"),
    ).toBeTruthy();
    // Nobody wrote down who dressed Srila Prabhupada, so nobody is named.
    expect(view.getByLabelText("Srila Prabhupada, Today")).toBeTruthy();

    // The captions are drawn but kept out of the accessibility tree — the
    // photograph above each one already announces the same words.
    const caption = (text: string) =>
      view.getByText(text, { includeHiddenElements: true });
    expect(caption("Kisora Kisori")).toBeTruthy();
    expect(caption("Rukmini devi dasi")).toBeTruthy();
  });

  it("offers no way to take a day down unless the server said so", async () => {
    mockDays = [
      day([
        {
          imageUrl: "https://temple.example/a.jpg",
          deity: "Kisora Kisori",
          dressedBy: null,
          position: 0,
        },
      ]),
    ];

    const view = await renderScreen();
    expect(
      view.queryByLabelText("Take down the darshan for Today"),
    ).toBeNull();
  });

  it("says exactly what goes before it takes a day down", async () => {
    mockDays = [
      day(
        [
          {
            imageUrl: "https://temple.example/a.jpg",
            deity: "Kisora Kisori",
            dressedBy: "Rukmini devi dasi",
            position: 0,
          },
          {
            imageUrl: "https://temple.example/b.jpg",
            deity: "Gaura Nitai",
            dressedBy: null,
            position: 1,
          },
        ],
        // The server's answer, carried on the row. Nothing re-derives the rule.
        { can_delete: true },
      ),
    ];

    const alert = jest.spyOn(Alert, "alert").mockImplementation(() => {});
    const view = await renderScreen();

    fireEvent.press(view.getByLabelText("Take down the darshan for Today"));

    const [title, body, buttons] = alert.mock.calls[0];
    expect(title).toBe("Take down Today's darshan?");
    expect(body).toBe(
      "All 2 pictures from Today, the Deities' names and who dressed Them will be removed for every devotee. This cannot be undone.",
    );
    // Nothing has gone yet — the question is asked first.
    expect(mockDelete).not.toHaveBeenCalled();

    const takeDown = buttons?.find((button) => button.text === "Take down");
    expect(takeDown?.style).toBe("destructive");
    takeDown?.onPress?.();
    expect(mockDelete).toHaveBeenCalledWith(
      "darshan-today",
      expect.any(Object),
    );
  });

  it("says a day that is gone is gone, rather than showing an empty frame", async () => {
    // The week clears every Monday, and a day can also be taken down while
    // somebody is looking at the list that led here.
    const view = await renderScreen();
    expect(view.getByText("This darshan is no longer posted")).toBeTruthy();
  });
});
