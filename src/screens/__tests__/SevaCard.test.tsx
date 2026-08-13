/// <reference types="jest" />

import { render } from "@testing-library/react-native";
import type { ComponentProps } from "react";

import type { AccessRole } from "../../features/access/model";
import { weekdayOfKey } from "../../features/schedule/layout";
import type { TempleProgrammeOccurrence } from "../../features/schedule/types";
import {
  SEVA_CARD_HEIGHT,
  SEVA_CARD_HEIGHT_WITH_PEOPLE,
  SevaCard,
} from "../../features/services/components";
import { getChicagoDateKey } from "../../lib/chicagoDate";
import { usePrototypeSession } from "../../store/usePrototypeSession";
import { SevaListScreen } from "../SevaListScreen";

let mockActualRole: AccessRole = "devotee";

jest.mock("../../features/access/hooks", () => ({
  useCurrentAccessProfile: () => ({
    data: { role: mockActualRole },
    error: null,
    isLoading: false,
    refetch: jest.fn(),
  }),
}));

const mockDashboard: any = {
  serviceTypes: [],
  devotees: [],
  services: [],
  pendingOffers: [],
  recurringTemplates: [],
  pendingRecurringOffers: [],
  coverageRequests: [],
  coveragePlans: [],
  activeSessions: [],
  activitySessions: [],
  recurringInterests: [],
  verifications: [],
  myVerifications: [],
  verificationInbox: [],
  offerCounters: [],
  sevaNeedingAnswer: [],
};

jest.mock("../../features/services/hooks", () => ({
  useServiceDashboard: () => ({
    data: mockDashboard,
    error: null,
    isLoading: false,
    isError: false,
  }),
}));

/** `list_temple_programme` rows, as migration 0069 returns them. */
let mockProgramme: TempleProgrammeOccurrence[] = [];

jest.mock("../../features/schedule/hooks", () => ({
  useTempleProgramme: () => ({
    data: mockProgramme,
    error: null,
    isLoading: false,
  }),
}));

const ME = {
  id: "seva-card-test-user",
  name: "Current Devotee",
  photo_url: null,
  role_name: "devotee",
};

/** A date key a few days out, so nothing is filtered as already finished. */
function soon(days: number) {
  const date = new Date();
  date.setDate(date.getDate() + days);
  return getChicagoDateKey(date);
}

/**
 * The height the card was drawn at. NativeWind merges its classes into an
 * array of styles, so every entry is flattened before the height is read.
 */
function heightOf(node: { props: { style?: unknown } }) {
  const flattened = [node.props.style].flat(4) as Array<
    { height?: number } | null | undefined
  >;
  return flattened.find((entry) => entry && typeof entry.height === "number")
    ?.height;
}

async function measure(props: ComponentProps<typeof SevaCard>) {
  const screen = await render(<SevaCard {...props} />);
  const card = screen.getByText(props.name).parent!.parent!.parent!;
  const height = heightOf(card);
  await screen.unmount();
  return height;
}

describe("one seva card, one height", () => {
  it("measures the same for a one-line request and a crowded weekly seva", async () => {
    expect(
      await measure({ name: "Aarti", when: "Thu, Aug 6 · 5:00 AM", minutes: 60 }),
    ).toBe(SEVA_CARD_HEIGHT);
    expect(
      await measure({
        name: "Sunday Feast Kitchen Preparation and Cleanup Afterwards",
        when: "Thu, Aug 6 · 5:00 AM",
        minutes: 60,
        weekly: true,
        isMine: true,
        people: [
          { id: "a", name: "Arpita Jadhav" },
          { id: "b", name: "Tanmay Pramanick" },
          { id: "c", name: "Third Devotee" },
          { id: "d", name: "Fourth Devotee" },
        ],
      }),
    ).toBe(SEVA_CARD_HEIGHT);
  });

  it("adds one fixed row, not a variable one, where who is serving is shown", async () => {
    // A seva with three devotees on it and a seva with none are the same card:
    // the row is there either way, which is what keeps a list even.
    expect(
      await measure({
        name: "Aarti",
        when: "Thu, Aug 6",
        minutes: 60,
        showPeople: true,
      }),
    ).toBe(SEVA_CARD_HEIGHT_WITH_PEOPLE);
    expect(
      await measure({
        name: "Garlands",
        when: "Thu, Aug 6",
        minutes: 60,
        showPeople: true,
        people: [
          { id: "a", name: "Arpita Jadhav" },
          { id: "b", name: "Tanmay Pramanick" },
          { id: "c", name: "Third Devotee" },
        ],
      }),
    ).toBe(SEVA_CARD_HEIGHT_WITH_PEOPLE);
  });

  it("carries only what the temple asked for", async () => {
    const screen = await render(
      <SevaCard
        name="Flower Garlands"
        when="Thu, Aug 6 · 5:00 AM"
        minutes={90}
        weekly
        isMine
      />,
    );

    expect(screen.getByText("Flower Garlands")).toBeTruthy();
    expect(screen.getByText("Thu, Aug 6 · 5:00 AM")).toBeTruthy();
    expect(screen.getByText("1 hr 30 min")).toBeTruthy();
    expect(screen.getByText("Weekly")).toBeTruthy();
    expect(screen.getByText("My seva")).toBeTruthy();
    await screen.unmount();
  });
});

describe("See all lists a weekly seva once", () => {
  beforeEach(() => {
    mockActualRole = "devotee";
    mockDashboard.services = [];
    mockDashboard.recurringTemplates = [];
    mockDashboard.devotees = [ME];
    mockProgramme = [];
    usePrototypeSession.setState({ activeUserId: ME.id, previewRole: null });
  });

  it("shows one card for a weekly seva, not one per generated date", async () => {
    // The temple asked for this explicitly. "See all" used to name a weekly
    // seva once as a roster card and then again for every date it generated.
    mockDashboard.recurringTemplates = [
      {
        id: "weekly-flower-garlands",
        name: "Flower Garlands",
        active: true,
        participation_mode: "invite_only",
        days_of_week: [1, 4, 6],
        start_time: "05:00:00",
        duration_minutes: 90,
        slots_needed: 1,
        start_date: "2020-01-01",
        end_date: null,
        created_by: "someone-else",
        assignees: [{ ...ME, assignedDays: [1, 4, 6] }],
      },
    ];
    mockDashboard.services = [1, 3, 5].map((days) => ({
      id: `occ-${days}`,
      template_id: "weekly-flower-garlands",
      name: "Flower Garlands",
      date: soon(days),
      start_time: "05:00:00",
      duration_minutes: 90,
      slots_needed: 1,
      filledSlots: 1,
      status: "open",
      participation_mode: "invite_only",
      participants: [
        {
          assignment: {
            id: `asg-${days}`,
            status: "confirmed",
            attendance: null,
          },
          devotee: ME,
        },
      ],
      currentUserAssignment: null,
    }));

    const screen = await render(
      <SevaListScreen
        navigation={{ navigate: jest.fn() } as never}
        route={
          {
            key: "seva-list",
            name: "SevaList",
            params: { kind: "my_upcoming" },
          } as never
        }
      />,
    );

    expect(screen.getAllByText("Flower Garlands")).toHaveLength(1);
    await screen.unmount();
  });
});

/**
 * "Temple schedule will be along with shift schedule along with community
 * schedule, just read only."
 *
 * The temple's fixed rhythm has to be on the community schedule as well as on
 * the timetable, sitting among the seva at its own hours — and it has to be
 * impossible to mistake for seva anybody could be put on.
 */
describe("the temple programme on the community schedule", () => {
  /** The seva the day is built around, three days out. */
  const DATE = soon(3);

  function programme(
    overrides: Partial<TempleProgrammeOccurrence> = {},
  ): TempleProgrammeOccurrence {
    return {
      programme_id: "prog-mangala",
      kind: "temple_programme",
      name: "Mangala Arati",
      occurs_on: DATE,
      day_of_week: weekdayOfKey(DATE),
      starts_at_local: "04:30:00",
      ends_at_local: null,
      duration_minutes: null,
      starts_at: `${DATE}T09:30:00.000Z`,
      ends_at: null,
      sort_order: 10,
      ...overrides,
    };
  }

  beforeEach(() => {
    // The community schedule is for the President, the Tech Admin and the
    // Community Heads; a Volunteer is shown a locked panel instead.
    mockActualRole = "president";
    mockDashboard.recurringTemplates = [];
    mockDashboard.devotees = [ME];
    mockDashboard.services = [
      {
        id: "one-off-cutting",
        template_id: null,
        name: "Vegetable Cutting",
        date: DATE,
        start_time: "16:15:00",
        duration_minutes: 90,
        slots_needed: 2,
        filledSlots: 1,
        status: "open",
        participation_mode: "invite_only",
        participants: [],
        currentUserAssignment: null,
      },
    ];
    mockProgramme = [
      programme(),
      programme({
        programme_id: "prog-bhagavatam",
        name: "Srimad Bhagavatam Class",
        starts_at_local: "07:30:00",
        ends_at_local: "08:30:00",
        duration_minutes: 60,
        sort_order: 40,
      }),
    ];
    usePrototypeSession.setState({ activeUserId: ME.id, previewRole: null });
  });

  async function renderSchedule() {
    return render(
      <SevaListScreen
        navigation={{ navigate: jest.fn() } as never}
        route={
          {
            key: "seva-list",
            name: "SevaList",
            params: { kind: "community_schedule" },
          } as never
        }
      />,
    );
  }

  it("draws the temple's day alongside the seva, once each", async () => {
    const screen = await renderSchedule();

    expect(screen.getAllByText("Mangala Arati")).toHaveLength(1);
    expect(screen.getAllByText("Srimad Bhagavatam Class")).toHaveLength(1);
    expect(screen.getAllByText("Vegetable Cutting")).toHaveLength(1);
    await screen.unmount();
  });

  it("says a start with no end as a moment, never as an invented range", async () => {
    const screen = await renderSchedule();

    // Mangala Arati has duration_minutes null: the temple named a start and no
    // end, and "4:30 AM to 4:30 AM" would be the app inventing one.
    expect(screen.getByText("4:30 AM")).toBeTruthy();
    expect(screen.queryByText(/4:30 AM to/)).toBeNull();
    // One that does have an end still reads as a range.
    expect(screen.getByText("7:30 AM to 8:30 AM")).toBeTruthy();
    await screen.unmount();
  });

  it("is read only — not a button, and nobody's seva", async () => {
    const screen = await renderSchedule();

    const arati = screen.getByLabelText(
      "Mangala Arati, temple programme, 4:30 AM, read only",
    );
    expect(arati.props.accessibilityRole).toBe("text");
    expect(arati.props.onPress).toBeUndefined();
    // The seva beside it is still openable, so this is not the whole list
    // having gone inert.
    expect(screen.getByLabelText(/^Open Vegetable Cutting/)).toBeTruthy();
    await screen.unmount();
  });

  it("does not count the temple's own programme as a seva result", async () => {
    const screen = await renderSchedule();

    // One seva is one result. Ten unchanging temple entries every day would
    // make an empty week read as a full one.
    expect(screen.getByText(/^1 result\b/)).toBeTruthy();
    await screen.unmount();
  });

  it("shows nothing of the programme where there is none to show", async () => {
    mockProgramme = [];
    const screen = await renderSchedule();

    expect(screen.queryByText("Mangala Arati")).toBeNull();
    expect(screen.queryByText(/It is read only/)).toBeNull();
    await screen.unmount();
  });
});
