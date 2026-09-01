/// <reference types="jest" />

import { fireEvent, render } from "@testing-library/react-native";

import type { DailyDarshan } from "../../features/dailyDarshan/types";
import { DailyDarshanScreen } from "../DailyDarshanScreen";

/** Chicago's today, pinned, so "Today" means the same thing every run. */
const TODAY = "2026-08-26";

jest.mock("@react-navigation/native", () => ({
  useIsFocused: () => false,
}));

/** Yesterday is pinned alongside today, or "Yesterday" would depend on the day
 * the suite happens to be run on. */
jest.mock("../../lib/chicagoDate", () => ({
  ...jest.requireActual("../../lib/chicagoDate"),
  getChicagoDateKey: () => TODAY,
  addChicagoDays: () => "2026-08-25",
}));

jest.mock("../../lib/supabase", () => ({ getSupabaseClient: jest.fn() }));

let mockRole = "devotee";

jest.mock("../../features/access/hooks", () => ({
  useCurrentAccessProfile: () => ({
    data: { role: mockRole },
    error: null,
    isLoading: false,
    isFetching: false,
    dataUpdatedAt: Date.now(),
    refetch: jest.fn(),
  }),
}));

let mockDays: DailyDarshan[] = [];
let mockLoading = false;

jest.mock("../../features/dailyDarshan/hooks", () => ({
  // The real permission rule, deliberately: a test that mocked it would prove
  // only that the mock said no.
  ...jest.requireActual("../../features/dailyDarshan/hooks"),
  useDailyDarshan: () => ({
    data: mockLoading ? undefined : mockDays,
    error: null,
    isLoading: mockLoading,
    isError: false,
    isRefetching: false,
    isFetching: false,
    dataUpdatedAt: Date.now(),
    refetch: jest.fn(),
  }),
}));

const navigate = jest.fn();
const navigation = { navigate } as never;

function picture(deity: string, position: number) {
  return {
    imageUrl: `https://temple.example/${deity}-${position}.jpg`,
    deity,
    dressedBy: null,
    position,
  };
}

function day(
  darshan_on: string,
  images: DailyDarshan["images"],
  extra: Partial<DailyDarshan> = {},
): DailyDarshan {
  return {
    id: `darshan-${darshan_on}`,
    darshan_on,
    note: null,
    images,
    posted_by: "head-1",
    posted_by_name: "Gopal das",
    posted_by_photo_url: null,
    created_at: `${darshan_on}T12:00:00.000Z`,
    can_delete: false,
    ...extra,
  };
}

beforeEach(() => {
  jest.clearAllMocks();
  mockRole = "devotee";
  mockLoading = false;
  mockDays = [];
});

async function renderScreen() {
  return render(
    <DailyDarshanScreen navigation={navigation} route={{} as never} />,
  );
}

describe("the darshan week", () => {
  it("draws one entry for a day however many pictures it holds", async () => {
    // The temple's complaint was a gallery that stacked every picture of every
    // day: five pictures on Tuesday must be one Tuesday, not five entries.
    mockDays = [
      day(TODAY, [
        picture("Kisora Kisori", 0),
        picture("Gaura Nitai", 1),
        picture("Jagannath Baldev Subhadra", 2),
        picture("Srila Prabhupada", 3),
        picture("Tulasi devi", 4),
      ]),
      day("2026-08-25", [picture("Gaura Nitai", 0)]),
      day("2026-08-24", [
        picture("Kisora Kisori", 0),
        picture("Gaura Nitai", 1),
      ]),
    ];

    const view = await renderScreen();

    const entries = view.getAllByHintText(
      "Opens everything posted on that day",
    );
    expect(entries).toHaveLength(3);
    expect(
      entries.map((entry) => entry.props.accessibilityLabel as string),
    ).toStrictEqual([
      "Today, 5 pictures, Kisora Kisori, Gaura Nitai and 3 more",
      "Yesterday, 1 picture, Gaura Nitai",
      "Mon, Aug 24, 2 pictures, Kisora Kisori and Gaura Nitai",
    ]);
  });

  it("opens the whole of one day rather than one picture of it", async () => {
    mockDays = [
      day(TODAY, [picture("Kisora Kisori", 0)]),
      day("2026-08-24", [picture("Gaura Nitai", 0)]),
    ];

    const view = await renderScreen();
    fireEvent.press(
      view.getByLabelText("Mon, Aug 24, 1 picture, Gaura Nitai"),
    );

    // The day travels with the id so the day screen has a heading before it
    // has looked anything up.
    expect(navigate).toHaveBeenCalledWith("DarshanDay", {
      darshanId: "darshan-2026-08-24",
      darshanOn: "2026-08-24",
    });
  });

  it("says how much of a day is behind the tap", async () => {
    mockDays = [
      day(TODAY, [picture("Kisora Kisori", 0), picture("Gaura Nitai", 1)]),
    ];

    const view = await renderScreen();
    expect(
      view.getByText("Today · 2 pictures", { includeHiddenElements: true }),
    ).toBeTruthy();
  });

  it("offers a devotee no way to compose at all", async () => {
    mockDays = [day(TODAY, [picture("Kisora Kisori", 0)])];

    const view = await renderScreen();

    expect(view.queryByLabelText("Post today’s darshan")).toBeNull();
    expect(navigate).not.toHaveBeenCalled();
  });

  it("offers the composer to a Community Head", async () => {
    mockRole = "core";
    const view = await renderScreen();

    fireEvent.press(view.getByLabelText("Post today’s darshan"));
    expect(navigate).toHaveBeenCalledWith("PostDarshan");
  });

  it("says the altar is simply quiet rather than that something broke", async () => {
    const view = await renderScreen();
    expect(view.getByText("No darshan yet")).toBeTruthy();
    // A devotee is not told to go and post it themselves.
    expect(
      view.getByText(
        /The day’s pictures of the Deities, and who dressed Them, will appear here\./,
      ),
    ).toBeTruthy();
  });
});
