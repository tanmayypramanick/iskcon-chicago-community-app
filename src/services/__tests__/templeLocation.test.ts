/// <reference types="jest" />

jest.mock("../notifications", () => ({
  sendTempleArrivalReminder: jest.fn(),
}));

import {
  evaluateTempleProximity,
  ISKCON_CHICAGO_LOCATION,
} from "../templeLocation";

describe("temple location detection", () => {
  it("recognizes an accurate reading at the temple", () => {
    expect(
      evaluateTempleProximity({
        latitude: ISKCON_CHICAGO_LOCATION.latitude,
        longitude: ISKCON_CHICAGO_LOCATION.longitude,
        accuracy: 10,
      }),
    ).toMatchObject({
      isAccurateEnough: true,
      isInside: true,
    });
  });

  it("does not auto-check-in from an imprecise reading", () => {
    expect(
      evaluateTempleProximity({
        latitude: ISKCON_CHICAGO_LOCATION.latitude,
        longitude: ISKCON_CHICAGO_LOCATION.longitude,
        accuracy: 250,
      }),
    ).toMatchObject({
      isAccurateEnough: false,
      isInside: false,
    });
  });

  it("recognizes a precise reading outside the temple area", () => {
    expect(
      evaluateTempleProximity({
        latitude: 41.8781,
        longitude: -87.6298,
        accuracy: 10,
      }),
    ).toMatchObject({
      isAccurateEnough: true,
      isInside: false,
    });
  });
});
