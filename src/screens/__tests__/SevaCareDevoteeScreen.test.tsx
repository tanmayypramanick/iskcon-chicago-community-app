/// <reference types="jest" />

/**
 * The temple had four coordinator views of one devotee's seva, reached by three
 * routes, and Seva Care's was the fourth: its own read of
 * `seva_balance_for_devotee`, its own row component, its own sentences about
 * the same hours the Devotees tab already had a screen for. A President who
 * reached Ramesh from Seva Care and Gopal from the congregation read two
 * different things about the same question.
 *
 * This is the guard on the consolidation: the Seva Care route draws the
 * Devotees tab's own panel, and the only thing it keeps of its own is the way
 * to say something — which is what Seva Care is for.
 */

import { cleanup, render } from "@testing-library/react-native";

jest.mock("../../lib/supabase", () => ({
  getSupabaseClient: () => ({ rpc: jest.fn() }),
}));

jest.mock("../../features/access/hooks", () => ({
  useCurrentAccessProfile: () => ({ data: { role: "president" } }),
}));

jest.mock("../../features/messaging/api", () => ({
  openConversation: jest.fn(),
}));

/** Whatever the screen handed the shared panel, if it drew one at all. */
let panelProps: Record<string, unknown> | null = null;

jest.mock("../DevoteeSevaProfileScreen", () => ({
  DevoteeSevaProfilePanel: (props: Record<string, unknown>) => {
    panelProps = props;
    return null;
  },
}));

import { SevaCareDevoteeScreen } from "../SevaCareDevoteeScreen";

const route = {
  key: "SevaCareDevotee-1",
  name: "SevaCareDevotee" as const,
  params: { devoteeId: "d-ramesh", name: "Bhakta Ramesh Patel" },
};

const navigation = {
  navigate: jest.fn(),
  getParent: () => ({ navigate: jest.fn() }),
};

function open() {
  return render(
    <SevaCareDevoteeScreen
      route={route as never}
      navigation={navigation as never}
    />,
  );
}

beforeEach(() => {
  panelProps = null;
});

afterEach(cleanup);

describe("one devotee's seva history, off a Seva Care row", () => {
  it("draws the same panel the Devotees tab draws", async () => {
    await open();

    expect(panelProps).toEqual({
      devoteeId: "d-ramesh",
      name: "Bhakta Ramesh Patel",
    });
  });

  it("keeps the one thing Seva Care needs of its own", async () => {
    const { getByLabelText, getByText } = await open();

    expect(getByLabelText("Message Bhakta Ramesh Patel")).toBeTruthy();
    expect(getByText("Message Bhakta")).toBeTruthy();
  });
});
