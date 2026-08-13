/// <reference types="jest" />

import { readFileSync } from "fs";
import { join } from "path";

import { render } from "@testing-library/react-native";

import { SevaAwardLegend } from "../components";
import {
  sevaBadgeLegend,
  sevaLegendBadges,
  type SevaBadgeLegendEntry,
} from "../types";

/**
 * 202608040066 is deployed. The app still carries the ten so the legend is on
 * the screen the instant it is opened, which makes the app's copy a promise
 * about a row in the temple's database — and a promise nobody checks is how a
 * legend comes to name a badge that does not exist, or to reword one the
 * President did not reword.
 */
const approved = [
  "Śrama-dāna",
  "Nitya-sevā",
  "Aruṇodaya",
  "Dhairya",
  "Ruci",
  "Navadhā",
  "Dhruva-dāna",
  "Tan-mana-dhana",
  "Brāhma-muhūrta",
  "Bhakti-latā",
];

const migration = readFileSync(
  join(
    __dirname,
    "../../../../supabase/migrations/202608040066_badges_and_reads.sql",
  ),
  "utf8",
);

/** A Postgres string literal doubles its apostrophes, and these names have them. */
function quoted(value: string) {
  return `'${value.replace(/'/g, "''")}'`;
}

/** The one `values` tuple in 0066 section 7 that seeds this badge. */
function seedTuple(code: string) {
  const start = migration.indexOf(`('${code}',`);
  expect(start).toBeGreaterThan(-1);
  const end = migration.indexOf("\n\n", start);
  return migration.slice(start, end === -1 ? undefined : end);
}

describe("the badge legend the app paints first", () => {
  it("renders the ten badges the temple approved", async () => {
    const { getByText } = await render(
      <SevaAwardLegend badges={sevaBadgeLegend} />,
    );

    for (const title of approved) {
      expect(getByText(title)).toBeTruthy();
    }
  });

  it("names those ten and nothing else", () => {
    expect(sevaBadgeLegend.map((badge) => badge.title)).toEqual(approved);
  });

  // Five for a week and five for a month, which is what makes them ten
  // different reasons rather than one reason at ten thresholds.
  it("keeps the weekly five and the monthly five apart", () => {
    const codes = sevaBadgeLegend.map((badge) => badge.code);
    expect(codes.filter((code) => code.startsWith("weekly_"))).toHaveLength(5);
    expect(codes.filter((code) => code.startsWith("monthly_"))).toHaveLength(5);
  });

  it("says what earns each one, in the temple's own words", async () => {
    const { getByText } = await render(
      <SevaAwardLegend badges={sevaBadgeLegend} />,
    );

    expect(
      getByText("Serving a kind of seva you had never served before."),
    ).toBeTruthy();
    expect(
      getByText(
        "Serving more of the month's minutes before seven in the morning than anybody else.",
      ),
    ).toBeTruthy();
  });
});

/**
 * The first paint against the deployed seed, word for word. If these two ever
 * differ the legend rewrites itself a beat after a devotee opens it, which is
 * the temple reading one thing and then another about what it gives.
 */
describe("the first paint against 202608040066", () => {
  it("seeds exactly the ten the app carries", () => {
    const block = migration.slice(
      migration.indexOf(
        "insert into public.award_definitions\n  (code, title, description, earned_by, tier, rule_kind, period_kind,",
      ),
      migration.indexOf("on conflict (code) do nothing;"),
    );
    expect(block).not.toBe("");
    expect(block.match(/\n {2}\('/g)).toHaveLength(sevaBadgeLegend.length);
  });

  it.each(sevaBadgeLegend.map((badge) => [badge.code, badge] as const))(
    "%s matches the migration's title, wording, tier and period",
    (_code, badge: SevaBadgeLegendEntry) => {
      const tuple = seedTuple(badge.code);
      expect(tuple).toContain(quoted(badge.title));
      expect(tuple).toContain(quoted(badge.description));
      expect(tuple).toContain(quoted(badge.earned_by));
      expect(tuple).toContain(quoted(badge.tier));
      expect(tuple).toContain(quoted(badge.period_kind));
    },
  );
});

/**
 * `list_seva_badge_legend()` answers with every active definition, so the gifts
 * arrive down the same wire as the badges — and every one of them says in its
 * own wording who receives it and when. The temple asked for the opposite, so
 * the split has to happen before anything is drawn.
 */
describe("the gifts the legend function also returns", () => {
  const fromServer: SevaBadgeLegendEntry[] = [
    ...sevaBadgeLegend,
    {
      code: "weekly_maha_prasad",
      title: "Maha Prasad",
      description:
        "A plate from the altar, for the three devotees who carried this week.",
      earned_by: "Being among the three devotees who carried the week.",
      tier: "maha_prasad",
      period_kind: "week",
    },
    {
      code: "weekly_garland_kisora",
      title: "Kisora's garland",
      description:
        "A garland from the altar, for the devotee at the top of the week. The seven garlands take turns, and not one of them stands above another.",
      earned_by:
        "Standing at the top of the period whose turn this garland is. The seven take turns and not one of them stands above another.",
      tier: "garland",
      period_kind: "week",
    },
    {
      code: "monthly_garland_kisora",
      title: "Kisora's garland",
      description:
        "A garland from the altar, for the devotee at the top of the month. The seven garlands take turns, and not one of them stands above another.",
      earned_by:
        "Standing at the top of the period whose turn this garland is. The seven take turns and not one of them stands above another.",
      tier: "garland",
      period_kind: "month",
    },
    {
      code: "presidents_gift",
      title: "The President's Gift",
      description:
        "Given by the President, for something an algorithm would never have seen.",
      earned_by:
        "Something an algorithm would never have seen. The President decides.",
      tier: "maha_prasad",
      period_kind: "lifetime",
    },
    {
      code: "weekly_token",
      title: "Token of Appreciation",
      description:
        "For the ten devotees at the top of the week. Given for a week of service and giving, not for a total.",
      earned_by: "Being among the ten devotees at the top of the week.",
      tier: "token_of_appreciation",
      period_kind: "week",
    },
  ];

  it("keeps every gift out of the badges", () => {
    for (const badge of sevaLegendBadges(fromServer)) {
      expect(badge.tier).not.toBe("garland");
      expect(badge.tier).not.toBe("maha_prasad");
    }
  });

  // A badge may say "the top of the week" — that is what earns it. Only the
  // gifts may not.
  it("keeps a badge that happens to rank people", () => {
    expect(
      sevaLegendBadges(fromServer).map((badge) => badge.code),
    ).toContain("weekly_token");
  });

  it("leaves the ten where the phone already drew them", () => {
    expect(
      sevaLegendBadges(fromServer)
        .slice(0, sevaBadgeLegend.length)
        .map((badge) => badge.title),
    ).toEqual(approved);
  });

  it("never puts a Deity garland in a column", async () => {
    const { queryByText, getByText } = await render(
      <SevaAwardLegend badges={fromServer} />,
    );

    // Not as a row of its own, in either period, and not with the sentence that
    // says who it goes to.
    expect(queryByText("Kisora's garland")).toBeNull();
    expect(
      queryByText(
        "Standing at the top of the period whose turn this garland is. The seven take turns and not one of them stands above another.",
      ),
    ).toBeNull();
    // One lateral entry, with the seven beside each other.
    expect(getByText("The Deity garlands")).toBeTruthy();
    expect(getByText("Kisora")).toBeTruthy();
    expect(getByText("Nitai")).toBeTruthy();
  });
});

/**
 * The legend as the deployed database actually answers it.
 *
 * `list_seva_badge_legend()` returned thirty-eight active definitions on a
 * replica of the temple's own data: seventeen garlands and three maha prasad,
 * which are gifts, and eighteen of the two badge tiers. Three of those eighteen
 * are the same badge seeded twice — once judged over a week and once over a
 * month — so the list a devotee reads has to be fifteen, not eighteen with
 * three names repeated.
 */
describe("the legend the temple's own database publishes", () => {
  /** The badge-tier half of `list_seva_badge_legend()`, code for code. */
  const deployed: SevaBadgeLegendEntry[] = [
    ["weekly_arunodaya", "Aruṇodaya", "token_of_appreciation", "week"],
    ["monthly_bhakti_lata", "Bhakti-latā", "recognition", "month"],
    ["monthly_brahma_muhurta", "Brāhma-muhūrta", "token_of_appreciation", "month"],
    ["weekly_dhairya", "Dhairya", "recognition", "week"],
    ["monthly_dhruva_dana", "Dhruva-dāna", "recognition", "month"],
    ["mystery_gift", "Mystery Gift", "token_of_appreciation", "month"],
    ["weekly_mystery_gift", "Mystery Gift", "token_of_appreciation", "week"],
    ["monthly_navadha", "Navadhā", "recognition", "month"],
    ["weekly_nitya_seva", "Nitya-sevā", "recognition", "week"],
    ["monthly_recognition", "Recognition", "recognition", "month"],
    ["weekly_recognition", "Recognition", "recognition", "week"],
    ["weekly_ruci", "Ruci", "recognition", "week"],
    ["monthly_tan_mana_dhana", "Tan-mana-dhana", "token_of_appreciation", "month"],
    ["weekly_token", "Token of Appreciation", "token_of_appreciation", "week"],
    ["monthly_token", "Token of Appreciation", "token_of_appreciation", "month"],
    ["personal_best_month", "Your Best Month", "token_of_appreciation", "month"],
    ["first_seva", "Your First Seva", "recognition", "lifetime"],
    ["weekly_shrama_dana", "Śrama-dāna", "token_of_appreciation", "week"],
  ].map(([code, title, tier, period_kind]) => ({
    code,
    title,
    description: `${title} description`,
    earned_by: `${title} rule`,
    tier,
    period_kind,
  })) as SevaBadgeLegendEntry[];

  it("names no badge twice", () => {
    const titles = sevaLegendBadges(deployed).map((badge) => badge.title);

    expect(titles).toHaveLength(new Set(titles).size);
    expect(titles.filter((title) => title === "Recognition")).toHaveLength(1);
  });

  it("draws each of the repeated ones once", async () => {
    const { getAllByText } = await render(<SevaAwardLegend badges={deployed} />);

    for (const repeated of ["Recognition", "Token of Appreciation"]) {
      expect(getAllByText(repeated)).toHaveLength(1);
    }
  });

  /**
   * The one row on the wrong side of the line. 0063 seeded the Mystery Gift
   * with `token_of_appreciation`, so the tier — which is the split everywhere
   * else — put a gift under a heading that promises to say what earns each row,
   * where it sat with a rule beside it. It is a thing somebody makes and hands
   * over, so it belongs to the half that says what the gifts are and no more.
   */
  it("sorts the Mystery Gift into the gifts, tier or no tier", async () => {
    expect(sevaLegendBadges(deployed).map((badge) => badge.title)).not.toContain(
      "Mystery Gift",
    );

    const { getAllByText } = await render(<SevaAwardLegend badges={deployed} />);
    // Once on the screen, in the gifts half, and without its rule.
    expect(getAllByText("Mystery Gift")).toHaveLength(1);
    expect(getAllByText("Gifts")).toHaveLength(1);
  });

  /**
   * Collapsing must never cost the temple a badge, and must never let a
   * server-seeded row displace one of the ten the temple approved.
   */
  it("keeps every distinct badge, the approved ten first", () => {
    const badges = sevaLegendBadges(deployed);
    const badgeTitles = new Set(
      deployed
        .filter((entry) => entry.title !== "Mystery Gift")
        .map((entry) => entry.title),
    );

    expect(badges).toHaveLength(badgeTitles.size);
    expect(badges.slice(0, sevaBadgeLegend.length).map((b) => b.code)).toEqual(
      sevaBadgeLegend.map((b) => b.code),
    );
  });

  /**
   * Collapsing orders by seed but never rewrites: the row it keeps is the
   * server's, so a President who rewords a badge still sees their own wording
   * rather than the copy the app was shipped with.
   */
  it("draws the server's wording, not the app's, for a reworded badge", async () => {
    const reworded = deployed.map((badge) =>
      badge.code === "weekly_ruci"
        ? { ...badge, earned_by: "Trying a seva you have never tried." }
        : badge,
    );

    expect(
      sevaLegendBadges(reworded).find((badge) => badge.code === "weekly_ruci")
        ?.earned_by,
    ).toBe("Trying a seva you have never tried.");

    const { getByText, queryByText } = await render(
      <SevaAwardLegend badges={reworded} />,
    );
    expect(getByText("Trying a seva you have never tried.")).toBeTruthy();
    expect(
      queryByText("Serving a kind of seva you had never served before."),
    ).toBeNull();
  });
});
