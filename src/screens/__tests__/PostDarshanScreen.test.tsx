/// <reference types="jest" />

import { act, fireEvent, render } from "@testing-library/react-native";
import { Alert } from "react-native";

import { pickDarshanImages } from "../../features/dailyDarshan/hooks";
import { PostDarshanScreen } from "../PostDarshanScreen";

const TODAY = "2026-08-26";

jest.mock("@react-navigation/native", () => ({ useIsFocused: () => false }));

jest.mock("../../lib/chicagoDate", () => ({
  ...jest.requireActual("../../lib/chicagoDate"),
  getChicagoDateKey: () => TODAY,
}));

jest.mock("../../lib/supabase", () => ({ getSupabaseClient: jest.fn() }));

let mockRole = "core";

jest.mock("../../features/access/hooks", () => ({
  useCurrentAccessProfile: () => ({
    data: { role: mockRole },
    error: null,
    isLoading: false,
    refetch: jest.fn(),
  }),
}));

const mockMutate = jest.fn();

/**
 * What the catalogue answers. Empty stands for a database without 0080 — the
 * read itself falls back there, so the screen sees the three the temple named
 * and never an empty picker.
 */
let mockDeities = [
  { id: null, name: "Kisora Kisori" },
  { id: null, name: "Gaura Nitai" },
  { id: null, name: "Jagannath Baldev Subhadra" },
];

jest.mock("../../features/dailyDarshan/hooks", () => ({
  ...jest.requireActual("../../features/dailyDarshan/hooks"),
  pickDarshanImages: jest.fn(),
  useDailyDarshan: () => ({ data: [], error: null, isLoading: false }),
  useDarshanDeities: () => ({
    data: mockDeities,
    error: null,
    isLoading: false,
  }),
  usePublishDailyDarshan: () => ({
    mutate: mockMutate,
    isPending: false,
    error: null,
    reset: jest.fn(),
  }),
}));

const mockPick = jest.mocked(pickDarshanImages);
const goBack = jest.fn();
const navigation = { navigate: jest.fn(), goBack } as never;

/** The picker is reached through an action sheet; this presses "Choose from
 * library" for it so the test can get at what the picker returns. */
function autoChooseFromLibrary() {
  jest
    .spyOn(Alert, "alert")
    .mockImplementation((_title, _message, buttons) => {
      const choice = buttons?.find((button) =>
        /library/i.test(button.text ?? ""),
      );
      choice?.onPress?.();
    });
}

function picture(name: string) {
  return { uri: `file:///${name}`, mimeType: "image/jpeg", fileName: name };
}

beforeEach(() => {
  jest.clearAllMocks();
  mockRole = "core";
  mockDeities = [
    { id: null, name: "Kisora Kisori" },
    { id: null, name: "Gaura Nitai" },
    { id: null, name: "Jagannath Baldev Subhadra" },
  ];
});

async function renderScreen() {
  return render(
    <PostDarshanScreen navigation={navigation} route={{} as never} />,
  );
}

describe("composing a day of darshan", () => {
  it("shows an ordinary devotee no composer at all", async () => {
    mockRole = "devotee";
    const view = await renderScreen();

    expect(
      view.getByText("Posting darshan is for temple leaders"),
    ).toBeTruthy();
    expect(view.queryByLabelText("Choose the day's pictures")).toBeNull();
    expect(view.queryByText("Post darshan")).toBeNull();
  });

  it("carries each picture's Deities and dresser through to the post", async () => {
    autoChooseFromLibrary();
    mockPick.mockResolvedValue([picture("a.jpg"), picture("b.jpg")]);

    const view = await renderScreen();
    // The picker is asynchronous and its result lands in state, so the press
    // and the promise it starts have to settle inside the same act.
    await act(async () => {
      fireEvent.press(view.getByLabelText("Choose the day's pictures"));
    });

    // Two pictures chosen, so two frames in the strip and one of them open.
    // The Deities are chosen from the list; the dresser is a person's name and
    // stays typed.
    const named = async (deity: string, dresser: string) => {
      await act(async () => {
        fireEvent.press(view.getByLabelText(deity));
      });
      await act(async () => {
        fireEvent.changeText(
          view.getByLabelText("Who dressed the Deities in this picture"),
          dresser,
        );
      });
    };

    await named("Kisora Kisori", "Rukmini devi dasi");
    // Moving to the second picture keeps the first one's caption with the
    // first one's photograph — that pairing is the whole feature.
    await act(async () => {
      fireEvent.press(
        view.getByLabelText("Open a picture that still needs a name"),
      );
    });
    await named("Gaura Nitai", "Bhakta Arjun");

    await act(async () => {
      fireEvent.press(view.getByText("Post darshan"));
    });

    expect(mockMutate).toHaveBeenCalledTimes(1);
    const [variables] = mockMutate.mock.calls[0];
    expect(variables.darshanOn).toBe(TODAY);
    expect(
      variables.images.map(
        (image: { uri: string; deity: string; dressedBy: string }) => [
          image.uri,
          image.deity,
          image.dressedBy,
        ],
      ),
    ).toEqual([
      ["file:///a.jpg", "Kisora Kisori", "Rukmini devi dasi"],
      ["file:///b.jpg", "Gaura Nitai", "Bhakta Arjun"],
    ]);
  });

  it("asks the library for only as many pictures as the day has room for", async () => {
    autoChooseFromLibrary();
    mockPick.mockResolvedValue([
      picture("a.jpg"),
      picture("b.jpg"),
      picture("c.jpg"),
    ]);

    const view = await renderScreen();
    // The picker is asynchronous and its result lands in state, so the press
    // and the promise it starts have to settle inside the same act.
    await act(async () => {
      fireEvent.press(view.getByLabelText("Choose the day's pictures"));
    });

    expect(mockPick).toHaveBeenLastCalledWith("library", 5);

    // Three in, so only two more may be added — and the button says so.
    await act(async () => {
      fireEvent.press(view.getByLabelText("Add pictures, 2 of 5 still free"));
    });
    expect(mockPick).toHaveBeenLastCalledWith("library", 2);
  });

  it("will not post a picture whose Deities nobody named", async () => {
    autoChooseFromLibrary();
    mockPick.mockResolvedValue([picture("a.jpg")]);

    const view = await renderScreen();
    // The picker is asynchronous and its result lands in state, so the press
    // and the promise it starts have to settle inside the same act.
    await act(async () => {
      fireEvent.press(view.getByLabelText("Choose the day's pictures"));
    });

    await act(async () => {
      fireEvent.press(view.getByText("Post darshan"));
    });

    expect(mockMutate).not.toHaveBeenCalled();
    expect(
      view.getByText("Name the Deities in each picture before posting."),
    ).toBeTruthy();
  });

  it("will not post a day with no pictures in it", async () => {
    const view = await renderScreen();
    await act(async () => {
      fireEvent.press(view.getByText("Post darshan"));
    });

    expect(mockMutate).not.toHaveBeenCalled();
    expect(
      view.getByText("Add at least one picture of the Deities."),
    ).toBeTruthy();
  });
});

describe("choosing which Deities", () => {
  it("offers the three the temple named when the catalogue is not there yet", async () => {
    autoChooseFromLibrary();
    mockPick.mockResolvedValue([picture("a.jpg")]);

    const view = await renderScreen();
    await act(async () => {
      fireEvent.press(view.getByLabelText("Choose the day's pictures"));
    });

    // A picker with nothing in it would stop the day being posted at all.
    for (const name of [
      "Kisora Kisori",
      "Gaura Nitai",
      "Jagannath Baldev Subhadra",
    ]) {
      expect(view.getByLabelText(name)).toBeTruthy();
    }
    // Nothing is chosen until it is chosen, and nothing is typed by default.
    expect(
      view.queryByLabelText("Which Deities are in this picture"),
    ).toBeNull();
  });

  it("marks the chosen Deities and leaves the dresser to be typed", async () => {
    autoChooseFromLibrary();
    mockPick.mockResolvedValue([picture("a.jpg")]);

    const view = await renderScreen();
    await act(async () => {
      fireEvent.press(view.getByLabelText("Choose the day's pictures"));
    });
    await act(async () => {
      fireEvent.press(view.getByLabelText("Gaura Nitai"));
    });

    expect(
      view.getByLabelText("Gaura Nitai").props.accessibilityState,
    ).toMatchObject({ selected: true });
    expect(
      view.getByLabelText("Kisora Kisori").props.accessibilityState,
    ).toMatchObject({ selected: false });
  });

  it("still lets a Head name a Deity the catalogue has not heard of", async () => {
    autoChooseFromLibrary();
    mockPick.mockResolvedValue([picture("a.jpg")]);

    const view = await renderScreen();
    await act(async () => {
      fireEvent.press(view.getByLabelText("Choose the day's pictures"));
    });

    // A visiting or festival Deity must never stop a day being posted.
    await act(async () => {
      fireEvent.press(view.getByLabelText("Another Deity"));
    });
    await act(async () => {
      fireEvent.changeText(
        view.getByLabelText("Which Deities are in this picture"),
        "Sri Sri Radha Govinda",
      );
    });
    await act(async () => {
      fireEvent.press(view.getByText("Post darshan"));
    });

    const [variables] = mockMutate.mock.calls[0];
    expect(variables.images[0].deity).toBe("Sri Sri Radha Govinda");
  });
});
