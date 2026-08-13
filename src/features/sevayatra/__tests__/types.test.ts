import {
  careRowHours,
  formatSevaPoints,
  pendingSevaPhrase,
  profileWindowForRange,
  scoredPeriodForRange,
  sevaBadgeLegend,
  sevaBoardModeLabel,
  sevaGiftLegend,
  sevaGivingFigure,
  sevaPoints,
  sevaRangeChips,
  sevaRangeLabels,
  sevaRanges,
  SEVA_POINTS_CEILING,
} from "../types";

/**
 * `seva_mala_points(norm)` on a replica of the temple's own database:
 *
 *   greatest(10, round(least(seva_mala_norm_ceiling(), norm) * 1000 / 10.0) * 10)
 *
 * with `seva_mala_norm_ceiling()` = 1 + `seva_mala.balance_beta`, and 0064 put
 * that setting at 0.3. Every expectation below is what that replica answered.
 */
describe("points, as the server prices them", () => {
  it("stops where the server's ceiling does, not two hundred points above it", () => {
    expect(SEVA_POINTS_CEILING).toBe(1300);
    expect(sevaPoints(1.3)).toBe(1300);
    // Past the soft cap is where money would buy the top, so the server refuses
    // to go further and so must anything restating it.
    expect(sevaPoints(1.9)).toBe(1300);
    expect(sevaPoints(12)).toBe(1300);
  });

  /**
   * The one that used to disagree. 1.005 is held as 1.00499… in a binary
   * double, so `Math.round(value * 100)` rounded it down and published 1000
   * where the server published 1010 — for the same devotee, on a screen that
   * now shows both figures.
   */
  it("rounds the halves the way `numeric` does, not the way doubles do", () => {
    expect(sevaPoints(1.005)).toBe(1010);
    expect(sevaPoints(0.105)).toBe(110);
    expect(sevaPoints(0.115)).toBe(120);
    expect(sevaPoints(1.045)).toBe(1050);
  });

  it("agrees with the integer the server published for the same score", () => {
    expect(sevaPoints(0.503045)).toBe(500);
    expect(sevaPoints(0.42)).toBe(420);
    expect(sevaPoints(0.4249)).toBe(420);
    expect(sevaPoints(0.4251)).toBe(430);
  });

  /** `greatest(10, …)`: a devotee who served at all has not scored nothing. */
  it("never prices real seva at nothing, and nothing at ten", () => {
    expect(sevaPoints(0.0000001)).toBe(10);
    expect(sevaPoints(0)).toBe(0);
    expect(sevaPoints(null)).toBe(0);
    expect(sevaPoints(undefined)).toBe(0);
    expect(sevaPoints(-1)).toBe(0);
    expect(sevaPoints(Number.NaN)).toBe(0);
  });

  it("separates the thousands the lifetime board reaches", () => {
    expect(formatSevaPoints(1.3)).toBe("1,300");
    expect(formatSevaPoints(0.42)).toBe("420");
  });
});

describe("naming a board", () => {
  /**
   * The drill-down says which board a rank is a place on, and it must say it in
   * the words the Leaderboard's own chooser used a tap earlier.
   */
  it("uses the chooser's own words", () => {
    expect(sevaBoardModeLabel("combined")).toBe("Seva & Giving");
    expect(sevaBoardModeLabel("seva")).toBe("Seva only");
    expect(sevaBoardModeLabel("supporters")).toBe("Supporters");
  });
});

describe("the four ranges", () => {
  it("offers week, month, year and all time, in that order", () => {
    expect(sevaRanges).toEqual(["week", "month", "year", "lifetime"]);
  });

  it("has a chip and a full label for every one of them", () => {
    for (const range of sevaRanges) {
      expect(sevaRangeChips[range]).toBeTruthy();
      expect(sevaRangeLabels[range]).toBeTruthy();
    }
  });

  /**
   * The chips sit on one line of a 320dp phone, which is the screen the temple
   * reported the clipped leaderboard pill on. Twenty-four characters across all
   * four is the budget that keeps them there.
   */
  it("keeps the chip labels short enough to fit a narrow phone", () => {
    const across = sevaRanges.reduce(
      (total, range) => total + sevaRangeChips[range].length,
      0,
    );
    expect(across).toBeLessThanOrEqual(24);
  });

  it("ranks every range except the calendar year", () => {
    expect(scoredPeriodForRange("week")).toBe("week");
    expect(scoredPeriodForRange("month")).toBe("month");
    expect(scoredPeriodForRange("lifetime")).toBe("lifetime");
    expect(scoredPeriodForRange("year")).toBeNull();
  });

  it("has a profile window for every range except all time", () => {
    expect(profileWindowForRange("week")).toBe("week");
    expect(profileWindowForRange("month")).toBe("month");
    expect(profileWindowForRange("year")).toBe("year");
    expect(profileWindowForRange("lifetime")).toBeNull();
  });
});

describe("Seva Care hours", () => {
  it("leads with the quarter both lists are measured over", () => {
    expect(
      careRowHours({
        hours_this_week: 4,
        hours_this_month: 15,
        hours_trailing_quarter: 39,
      }),
    ).toEqual({ quarter: 39, week: 4, month: 15 });
  });

  /**
   * `list_seva_narrowness` publishes a quarter and nothing finer. Its rows used
   * to have a week and a month divided out of it — 39/13 printed under "A week"
   * — and the temple read them as this week's. A figure the server never sent
   * is not shown at all now.
   */
  it("invents no week or month for a row that carries neither", () => {
    expect(careRowHours({ hours_trailing_quarter: 39 })).toEqual({
      quarter: 39,
      week: null,
      month: null,
    });
  });

  // A half-migrated row, which could otherwise print a real week beside a
  // month that was arithmetic.
  it("keeps a row with only one of the two columns silent about both", () => {
    const figures = careRowHours({
      hours_this_week: 4,
      hours_trailing_quarter: 39,
    });
    expect(figures.week).toBeNull();
    expect(figures.month).toBeNull();
    expect(figures.quarter).toBe(39);
  });

  /**
   * The figure a burnout row leads with is never nought for a devotee who is on
   * the list at all. Syamasundara Das served six hours this month and none this
   * week, and the row led with "0 hours".
   */
  it("is never nought for a devotee the quarter put on the list", () => {
    expect(
      careRowHours({
        hours_this_week: 0,
        hours_this_month: 6,
        hours_trailing_quarter: 21,
      }).quarter,
    ).toBe(21);
  });
});

describe("the badge legend", () => {
  it("names all ten badges", () => {
    expect(sevaBadgeLegend).toHaveLength(10);
  });

  it("says what each badge is and what earns it", () => {
    for (const badge of sevaBadgeLegend) {
      expect(badge.title.length).toBeGreaterThan(0);
      expect(badge.description.length).toBeGreaterThan(0);
      expect(badge.earned_by.length).toBeGreaterThan(0);
    }
  });

  it("gives each badge its own code", () => {
    const codes = new Set(sevaBadgeLegend.map((badge) => badge.code));
    expect(codes.size).toBe(sevaBadgeLegend.length);
  });
});

describe("the gift legend", () => {
  it("names Maha Prasad and the seven Deity garlands", () => {
    const titles = sevaGiftLegend.map((gift) => gift.title);
    expect(titles).toContain("Maha Prasad");

    const garlands = sevaGiftLegend.find(
      (gift) => gift.title === "The Deity garlands",
    );
    expect(garlands?.items).toHaveLength(7);
  });

  /**
   * Every title here against `award_definitions` on a replica of the temple's
   * own database, which is where "Maha Burfi" was advertised for a year and
   * never existed: the maha_prasad tier holds Maha Prasad and the President's
   * Gift, and there is no burfi in any tier. A legend that promises a sweet the
   * temple has no definition for is a devotee asking the kitchen for it.
   */
  it("promises no gift the database does not define", () => {
    const seeded = new Set([
      "Maha Prasad",
      "The President's Gift",
      "Mystery Gift",
      // The three temple garlands and the seven Deity ones, each drawn as one
      // lateral entry rather than as a column.
      "The temple's garlands",
      "The Deity garlands",
    ]);
    for (const gift of sevaGiftLegend) {
      expect(seeded.has(gift.title)).toBe(true);
    }
    expect(sevaGiftLegend.map((gift) => gift.title)).not.toContain(
      "Maha Burfi",
    );
  });

  /**
   * Every gift-tier definition 0055 and 0063 seeded is named here, because the
   * gifts half is the app's own copy — the server's rows carry their rule in
   * every column it sends — and a curated list is only honest while it is the
   * whole list. The three lateral garlands are one entry for the reason the
   * seven are: a column of them is a ranking whatever the wording says.
   */
  it("covers every gift the temple has seeded", () => {
    const titles = sevaGiftLegend.map((gift) => gift.title);
    expect(titles).toContain("The President's Gift");
    // Seeded under a badge tier, and a gift all the same — so it is named here
    // rather than under a heading promising to say what earns it.
    expect(titles).toContain("Mystery Gift");

    const temple = sevaGiftLegend.find(
      (gift) => gift.title === "The temple's garlands",
    );
    expect(temple?.items).toEqual(["Sevā", "Dāna", "Samatva"]);
  });

  /**
   * The temple was explicit: the legend says what the gifts ARE. Who receives
   * one and when is the temple's to say in person, and a rule printed beside a
   * gift turns it into a prize. This is the guard on that.
   */
  it("never says who receives a gift, or when", () => {
    const forbidden =
      /\b(top|first|second|third|rank|ranked|place|winner|awarded|weekly|monthly|week|month|period|given to|highest|best)\b/i;
    for (const gift of sevaGiftLegend) {
      expect(`${gift.title} ${gift.description}`).not.toMatch(forbidden);
    }
  });
});

/**
 * `seva_yatra_devotee_summary` sends no cash figure at all to a caller without
 * `may_view_all_giving`, and the null has to survive the trip to the screen.
 * "$0.00" beside a devotee's name is the congregation being told they gave
 * nothing, which is the reading the server's null exists to prevent.
 */
describe("the giving figure on the drill-down", () => {
  it("shows the cents to a caller the server sent them to", () => {
    expect(
      sevaGivingFigure({
        giving_withheld: false,
        giving_cents: 12500,
        supported: true,
      }),
    ).toEqual({ label: "Given", value: "$125.00" });
  });

  it("still shows a real zero to that caller", () => {
    expect(
      sevaGivingFigure({
        giving_withheld: false,
        giving_cents: 0,
        supported: false,
      }).value,
    ).toBe("$0.00");
  });

  it("never renders a withheld figure as nothing given", () => {
    const withheld = sevaGivingFigure({
      giving_withheld: true,
      giving_cents: null,
      gifts: null,
      supported: true,
    } as Parameters<typeof sevaGivingFigure>[0]);
    expect(withheld.value).not.toContain("$");
    expect(withheld).toEqual({ label: "Gave", value: "Yes" });
  });

  it("says nothing at all about a devotee who did not give", () => {
    expect(
      sevaGivingFigure({
        giving_withheld: true,
        giving_cents: null,
        supported: false,
      }),
    ).toEqual({ label: "Gave", value: "—" });
  });

  // A row from a database or a caller this app has not met. Treated as withheld
  // rather than as zero, because guessing the wrong way publishes a figure.
  it("treats a missing cents figure as withheld", () => {
    expect(sevaGivingFigure({ supported: true }).value).toBe("Yes");
  });
});

/**
 * The three states 0057 distinguishes and the temple is about to demo. They are
 * not one state: an act nobody has marked done is waiting on the devotee
 * reading the screen, and telling them to wait for a confirmation sends them to
 * the office about something they could finish themselves.
 */
describe("why an act has not counted yet", () => {
  it("names each of the three on its own", () => {
    expect(pendingSevaPhrase(["awaiting_completion"])).toBe("marked done");
    expect(pendingSevaPhrase(["awaiting_verification"])).toBe("verified");
    expect(pendingSevaPhrase(["awaiting_confirmation"])).toBe("confirmed");
  });

  it("names only the ones a window actually holds", () => {
    expect(
      pendingSevaPhrase(["counted", "awaiting_verification", "not_served"]),
    ).toBe("verified");
  });

  it("reads as a sentence when a window holds all three", () => {
    expect(
      pendingSevaPhrase([
        "awaiting_confirmation",
        "awaiting_completion",
        "awaiting_verification",
      ]),
    ).toBe("marked done, verified and confirmed");
  });

  // The calendar year counts its waiting acts without saying what they wait on.
  it("stays true where nothing says which state", () => {
    expect(pendingSevaPhrase([])).toBe("signed off");
    expect(pendingSevaPhrase(["counted"])).toBe("signed off");
  });
});
