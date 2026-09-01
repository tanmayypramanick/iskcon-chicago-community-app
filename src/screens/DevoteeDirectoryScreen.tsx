import { Ionicons } from "@expo/vector-icons";
import type { NavigationProp } from "@react-navigation/native";
import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import { File, Paths } from "expo-file-system";
import * as Sharing from "expo-sharing";
import { useMemo, useState } from "react";
import { Pressable, Text, TextInput, View } from "react-native";

import tokens from "../../design-tokens.json";
import {
  Avatar,
  ListScreen,
  Screen,
  ScreenTitle,
  Skeleton,
} from "../components/ui";
import type { DevoteeProfileRow } from "../features/access/api";
import {
  useCurrentAccessProfile,
  useDevoteeProfiles,
} from "../features/access/hooks";
import {
  accessRoleLabels,
  accessRoles,
  hasAccessPermission,
  isAccessRole,
  type AccessRole,
} from "../features/access/model";
import { useAllDonations } from "../features/donations/hooks";
import {
  centsAsDecimal,
  formatCents,
  totalsByCurrency,
  type AllDonation,
} from "../features/donations/types";
import {
  congregationSevaRanges,
  congregationSevaRows,
  devoteeSevaRanges,
  sevaRangeCaptions,
  sevaRangeEmpty,
  sevaRangeLabels,
  type CongregationSevaRow,
} from "../features/profile/sevaHours";
import { useDevoteeSevaBalance } from "../features/profile/sevaHoursApi";
import {
  SevaNameHoursList,
  SevaRangeSwitch,
} from "../features/profile/sevaHoursCard";
import { FormError } from "../features/services/components";
import { useAllSevaHours, useAllSevaScores } from "../features/sevayatra/hooks";
import { formatHours, type SevaPeriodKind } from "../features/sevayatra/types";
import {
  chicagoWallClockToInstant,
  formatChicagoShortDate,
  getChicagoDateKey,
  getChicagoWallClock,
} from "../lib/chicagoDate";
import type {
  MainTabParamList,
  ProfileStackParamList,
} from "../navigation/types";
import { usePrototypeSession } from "../store/usePrototypeSession";

type Props = NativeStackScreenProps<ProfileStackParamList, "DevoteeDirectory">;

/**
 * What the congregation record carries about a devotee beyond their details:
 * how much seva, and how much giving. Hours and amounts only.
 *
 * Deliberately no score, no standing and no award. The temple asked for those
 * to live in Seva Yatra and not in a record — a rank next to somebody's address
 * turns a roster into a league table, and a roster is what this is.
 */
export type DevoteeSummary = {
  /**
   * Hours served and acts, per range the temple-wide read can answer: this
   * week, this month, all time.
   *
   * There is deliberately no calendar year here. `seva_mala_periods.period_kind`
   * is constrained to week/month/lifetime, and the only way to a year across
   * two hundred devotees would be two hundred act-list requests. The year lives
   * on a devotee's own record, and the header says so rather than the record
   * quietly relabelling something else as a year.
   */
  hours: Record<SevaPeriodKind, number>;
  acts: Record<SevaPeriodKind, number>;
  /** One entry per currency the devotee gave in. Never added together. */
  given: { currency: string; cents: number; gifts: number }[];
  gifts: number;
  lastGiftAt: string | null;
};

const emptySummary: DevoteeSummary = {
  hours: { week: 0, month: 0, lifetime: 0 },
  acts: { week: 0, month: 0, lifetime: 0 },
  given: [],
  gifts: 0,
  lastGiftAt: null,
};

/**
 * The two temple-wide reads, turned into one lookup by devotee.
 *
 * The ledger is grouped here rather than by the server because there is no
 * per-donor grouped total to ask for: `donation_totals` answers about one donor
 * at a time, and a directory of two hundred devotees is not two hundred round
 * trips. A devotee's own screen does use it — see DevoteeSevaProfileScreen.
 *
 * The last gift is taken as the greatest `received_at` rather than the first
 * row, so it does not quietly depend on the order the ledger came back in.
 */
export function buildDevoteeSummaries(
  seva: Readonly<Record<SevaPeriodKind, readonly CongregationSevaRow[]>>,
  gifts: readonly AllDonation[],
) {
  const summaries = new Map<string, DevoteeSummary>();

  const giftsByDonor = new Map<string, AllDonation[]>();
  for (const gift of gifts) {
    // A gift from somebody who has never opened the app belongs to no devotee's
    // record until the President attaches it, and matching on the name would be
    // guessing at whose it is.
    if (!gift.donor_id) continue;
    const running = giftsByDonor.get(gift.donor_id) ?? [];
    running.push(gift);
    giftsByDonor.set(gift.donor_id, running);
  }

  const of = (devoteeId: string) => {
    const existing = summaries.get(devoteeId);
    if (existing) return existing;
    const created: DevoteeSummary = {
      ...emptySummary,
      hours: { ...emptySummary.hours },
      acts: { ...emptySummary.acts },
      given: [],
    };
    summaries.set(devoteeId, created);
    return created;
  };

  for (const period of congregationSevaRanges) {
    for (const row of seva[period] ?? []) {
      // Hours served, not credited, and for every devotee the read names —
      // including the ones whose acts are all still waiting on somebody, who
      // have no score row at all and used to be absent from this record.
      const summary = of(row.devotee_id);
      summary.hours[period] = row.hours;
      summary.acts[period] = row.acts;
    }
  }

  for (const [donorId, theirs] of giftsByDonor) {
    const summary = of(donorId);
    summary.given = totalsByCurrency(theirs).map((total) => ({
      currency: total.currency,
      cents: total.cents,
      gifts: total.count,
    }));
    summary.gifts = theirs.length;
    summary.lastGiftAt =
      theirs.reduce<string | null>(
        (latest, gift) =>
          !latest || gift.received_at > latest ? gift.received_at : latest,
        null,
      ) ?? null;
  }

  return summaries;
}

/** "$551.00", or both currencies side by side. Never one added figure. */
function givenLabel(summary: DevoteeSummary) {
  if (!summary.given.length) return null;
  return summary.given
    .map((total) => formatCents(total.cents, total.currency))
    .join(" · ");
}

/**
 * The two facts a row states, open or closed: what they serve over the range on
 * screen, and what they have given.
 */
export function devoteeSummaryLine(
  summary: DevoteeSummary,
  range: SevaPeriodKind,
) {
  const label = sevaRangeLabels[range].toLowerCase();
  const hours = summary.hours[range];
  return `${
    hours > 0 ? `${formatHours(hours)} ${label}` : `No seva ${label}`
  } · ${givenLabel(summary) ?? "No gifts yet"}`;
}

/**
 * What opening a row adds about giving, which is deliberately not the amount.
 *
 * The amount and the hours are on the line above whether the row is open or
 * shut; the expanded body used to restate both of them as labelled rows, so a
 * coordinator read "$551.00" twice and "12 hours" twice, three lines apart, and
 * the temple counted it as the record saying everything twice. What opening
 * actually adds is how many gifts there were and when the last one came.
 */
export function devoteeGiftsLine(
  summary: DevoteeSummary,
  lastGift: string | null,
) {
  if (!summary.gifts) return null;
  return `${summary.gifts} gift${summary.gifts === 1 ? "" : "s"}${
    lastGift ? `, last ${lastGift}` : ""
  }`;
}

type CompletenessFilter = "all" | "complete" | "incomplete";
type AccessFilter = "all" | AccessRole;
type JoinedFilter = "all" | "7" | "30" | "365";

const completenessOptions: Array<{ key: CompletenessFilter; label: string }> = [
  { key: "all", label: "All profiles" },
  { key: "complete", label: "Complete" },
  { key: "incomplete", label: "Incomplete" },
];

const joinedOptions: Array<{ key: JoinedFilter; label: string; days: number }> =
  [
    { key: "all", label: "Any time", days: 0 },
    { key: "7", label: "Last 7 days", days: 7 },
    { key: "30", label: "Last 30 days", days: 30 },
    { key: "365", label: "Last year", days: 365 },
  ];

const DAY_MS = 86_400_000;

/**
 * A stored date is a plain "YYYY-MM-DD" with no time in it. Reading it as an
 * instant lands on UTC midnight, which is still the previous evening in
 * Chicago, so every such date would render a day early. Anchoring at Chicago
 * noon keeps the day the devotee actually typed.
 */
function dayLabel(value: string | null) {
  if (!value) return null;
  const instant = value.includes("T")
    ? new Date(value)
    : chicagoWallClockToInstant(value, "12:00");
  if (Number.isNaN(instant.getTime())) return null;
  return `${formatChicagoShortDate(instant)}, ${getChicagoWallClock(instant).year}`;
}

function roleOf(row: DevoteeProfileRow): AccessRole {
  return isAccessRole(row.role_name) ? row.role_name : "devotee";
}

type SheetValue = string | number | boolean | null;

function escapeHtml(value: unknown) {
  return String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

/** A blank cell keeps the column sortable; a dash would read as data. */
function sheetCell(value: SheetValue) {
  if (value === null || value === "") return "<td></td>";
  if (typeof value === "boolean") return `<td>${value ? "Yes" : "No"}</td>`;
  return `<td>${escapeHtml(value)}</td>`;
}

const profileHeadings = [
  "Name",
  "Email",
  "Phone",
  "Access level",
  "Joined",
  "Profile completion %",
  "Date of birth",
  "Birth place",
  "Address",
  "Spiritual mentor",
  "Initiated",
  "Initiation date",
  "Diksha guru",
  "First initiation",
  "First initiation date",
  "First diksha guru",
  "Second initiation",
  "Second initiation date",
  "Second diksha guru",
  "Profile last updated",
];

/**
 * Which currencies the exported devotees actually gave in, so the sheet can
 * carry a money column for each.
 *
 * One column per currency rather than one "Given" column and a "Currency"
 * beside it: a devotee who has given in two would otherwise need two rows or a
 * total that adds unlike things. Almost always this returns exactly ["USD"],
 * and it returns that even when nobody has given, so the report's shape does
 * not change with its contents.
 */
function exportedCurrencies(summaries: readonly DevoteeSummary[]) {
  const seen = new Set<string>(["USD"]);
  for (const summary of summaries) {
    for (const total of summary.given) seen.add(total.currency);
  }
  return [...seen].sort();
}

/**
 * A column of hours and a column of acts for each range the congregation read
 * answers, so the office can sort on any of them without going devotee by
 * devotee. Named for the window they actually cover — there is no calendar-year
 * column because there is no calendar-year read, and an approximate one in a
 * spreadsheet is the kind of figure that ends up in a report.
 */
function summaryHeadings(currencies: readonly string[]) {
  return [
    ...congregationSevaRanges.flatMap((period) => [
      `Seva hours (${sevaRangeLabels[period].toLowerCase()})`,
      `Seva acts (${sevaRangeLabels[period].toLowerCase()})`,
    ]),
    ...currencies.map((currency) => `Given (${currency})`),
    "Gifts",
    "Last gift",
  ];
}

function sheetValues(
  row: DevoteeProfileRow,
  summary: DevoteeSummary,
  currencies: readonly string[],
): SheetValue[] {
  return [
    row.name,
    row.email,
    row.phone,
    accessRoleLabels[roleOf(row)],
    getChicagoDateKey(new Date(row.joined_at)),
    // A bare number so Excel sorts the column numerically; the "%" lives in the heading.
    row.completion,
    row.date_of_birth,
    row.birth_place,
    row.address,
    row.spiritual_mentor,
    row.is_initiated,
    row.initiation_date,
    row.diksha_guru,
    row.has_first_initiation,
    row.first_initiation_date,
    row.first_diksha_guru,
    row.has_second_initiation,
    row.second_initiation_date,
    row.second_diksha_guru,
    row.profile_updated_at
      ? getChicagoDateKey(new Date(row.profile_updated_at))
      : null,
    // Blank rather than 0 where there is nothing: a devotee with no seva
    // recorded has not served nought hours, they have no record at all, and a
    // zero would average into whatever the temple does with the column next.
    ...congregationSevaRanges.flatMap((period) => [
      summary.hours[period] > 0
        ? Math.round(summary.hours[period] * 100) / 100
        : null,
      summary.acts[period] > 0 ? summary.acts[period] : null,
    ]),
    ...currencies.map((currency) => {
      const total = summary.given.find((entry) => entry.currency === currency);
      return total ? centsAsDecimal(total.cents) : null;
    }),
    summary.gifts > 0 ? summary.gifts : null,
    summary.lastGiftAt ? getChicagoDateKey(new Date(summary.lastGiftAt)) : null,
  ];
}

export function buildDevoteeWorkbook(
  rows: readonly DevoteeProfileRow[],
  summaries: ReadonlyMap<string, DevoteeSummary>,
) {
  const generated = new Intl.DateTimeFormat("en-US", {
    dateStyle: "long",
    timeStyle: "short",
    timeZone: "America/Chicago",
  }).format(new Date());
  const completed = rows.filter((row) => row.completion >= 100).length;
  const forRow = (row: DevoteeProfileRow) =>
    summaries.get(row.id) ?? emptySummary;
  const currencies = exportedCurrencies(rows.map(forRow));

  const hours = rows.reduce(
    (total, row) => total + forRow(row).hours.lifetime,
    0,
  );
  // Summed per currency, and only ever within one: the footline is the same
  // arithmetic the columns are, not a figure of its own.
  const givenTotals = currencies
    .map((currency) => ({
      currency,
      cents: rows.reduce(
        (total, row) =>
          total +
          (forRow(row).given.find((entry) => entry.currency === currency)
            ?.cents ?? 0),
        0,
      ),
    }))
    .filter((total) => total.cents > 0);

  const headings = [...profileHeadings, ...summaryHeadings(currencies)];
  const body = rows
    .map(
      (row) =>
        `<tr>${sheetValues(row, forRow(row), currencies).map(sheetCell).join("")}</tr>`,
    )
    .join("");

  return `<!doctype html>
<html><head><meta charset="utf-8"><style>
body{font-family:Arial,sans-serif;color:#3A342B}h1{color:#2B3A67;margin-bottom:4px}
.summary{margin:0 0 18px;color:#6B6355}table{border-collapse:collapse;width:100%}
th{background:#2B3A67;color:#fff;font-weight:700;padding:9px;border:1px solid #D8C9AF}
td{padding:8px;border:1px solid #D8C9AF;vertical-align:top}tr:nth-child(even){background:#FBF7EF}
</style></head><body>
<h1>ISKCON Chicago — Congregation</h1>
<p class="summary">Generated ${escapeHtml(generated)} · ${rows.length} devotee${rows.length === 1 ? "" : "s"} · ${completed} completed profile${completed === 1 ? "" : "s"} · ${escapeHtml(formatHours(hours))} of seva all time${givenTotals
    .map(
      (total) =>
        ` · ${escapeHtml(formatCents(total.cents, total.currency))} given`,
    )
    .join(
      "",
    )}<br>Seva hours are hours served, over the week from Monday, the calendar month, and all time. A calendar year is kept per devotee rather than for the whole congregation, and is on each devotee's own seva record.</p>
<table><thead><tr>${headings.map((heading) => `<th>${heading}</th>`).join("")}</tr></thead><tbody>${body}</tbody></table>
</body></html>`;
}

export async function shareDevoteeList(
  rows: readonly DevoteeProfileRow[],
  summaries: ReadonlyMap<string, DevoteeSummary>,
) {
  const workbook = buildDevoteeWorkbook(rows, summaries);
  const stamp = getChicagoDateKey();
  const file = new File(
    Paths.cache,
    `iskcon-chicago-congregation-${stamp}.xls`,
  );
  file.create({ overwrite: true });
  file.write(workbook);
  if (!(await Sharing.isAvailableAsync())) {
    throw new Error("Sharing is not available on this device.");
  }
  await Sharing.shareAsync(file.uri, {
    mimeType: "application/vnd.ms-excel",
    dialogTitle: "Share devotee list",
    UTI: "com.microsoft.excel.xls",
  });
}

function FilterChip({
  label,
  selected,
  onPress,
}: {
  label: string;
  selected: boolean;
  onPress: () => void;
}) {
  return (
    <Pressable
      className={`min-h-10 items-center justify-center rounded-pill border px-3 ${
        selected ? "border-indigo bg-indigo" : "border-border bg-white"
      }`}
      accessibilityRole="button"
      accessibilityState={{ selected }}
      accessibilityLabel={`Filter by ${label}`}
      onPress={onPress}
    >
      <Text
        className={`font-sans-bold text-xs ${selected ? "text-white" : "text-stone"}`}
      >
        {label}
      </Text>
    </Pressable>
  );
}

function DetailRow({ label, value }: { label: string; value: string | null }) {
  if (!value) return null;
  return (
    <View className="mt-2 flex-row">
      <Text className="w-[132px] font-sans-bold text-xs uppercase tracking-wider text-stoneMuted">
        {label}
      </Text>
      <Text className="min-w-0 flex-1 font-sans text-sm leading-5 text-stone">
        {value}
      </Text>
    </View>
  );
}

export function DevoteeDirectoryScreen({ navigation }: Props) {
  const activeUserId = usePrototypeSession((state) => state.activeUserId);
  const previewRole = usePrototypeSession((state) => state.previewRole);
  const profile = useCurrentAccessProfile(activeUserId);
  const role =
    __DEV__ && previewRole ? previewRole : (profile.data?.role ?? "devotee");
  const canViewAll = hasAccessPermission(role, "app.view_all");
  const devotees = useDevoteeProfiles(canViewAll);

  // The record's two summaries. Each period's read carries hours and acts for
  // every devotee at once, so the three ranges are three requests rather than
  // three per devotee; the ledger is read whole because there is no per-donor
  // grouped total to ask the server for. All of them answer nothing without
  // `app.view_all`, so `enabled` only spares a pointless request.
  const weekHours = useAllSevaHours("week", canViewAll);
  const monthHours = useAllSevaHours("month", canViewAll);
  const lifetimeHours = useAllSevaHours("lifetime", canViewAll);
  const hoursReads = [weekHours, monthHours, lifetimeHours];

  // Null means the temple has not had 0066, and only then is the old credited
  // read worth asking for — three more requests, and only until it deploys.
  const beforeSevaHours = hoursReads.some((query) => query.data === null);
  const weekScores = useAllSevaScores("week", canViewAll && beforeSevaHours);
  const monthScores = useAllSevaScores("month", canViewAll && beforeSevaHours);
  const lifetimeScores = useAllSevaScores(
    "lifetime",
    canViewAll && beforeSevaHours,
  );
  const donations = useAllDonations(null, null, canViewAll);

  const [range, setRange] = useState<SevaPeriodKind>("lifetime");
  const [search, setSearch] = useState("");
  const [completeness, setCompleteness] = useState<CompletenessFilter>("all");
  const [accessLevel, setAccessLevel] = useState<AccessFilter>("all");
  const [joined, setJoined] = useState<JoinedFilter>("all");
  const [expandedId, setExpandedId] = useState<string | null>(null);
  const [exporting, setExporting] = useState(false);
  const [exportError, setExportError] = useState<string | null>(null);

  const rows = useMemo(() => devotees.data ?? [], [devotees.data]);

  const summaries = useMemo(
    () =>
      buildDevoteeSummaries(
        {
          week: congregationSevaRows(weekHours.data, weekScores.data),
          month: congregationSevaRows(monthHours.data, monthScores.data),
          lifetime: congregationSevaRows(
            lifetimeHours.data,
            lifetimeScores.data,
          ),
        },
        donations.data ?? [],
      ),
    [
      weekHours.data,
      monthHours.data,
      lifetimeHours.data,
      weekScores.data,
      monthScores.data,
      lifetimeScores.data,
      donations.data,
    ],
  );
  /** Nothing to say yet, rather than a zero the devotee has not earned. */
  const summariesPending =
    hoursReads.some((query) => query.isLoading) ||
    weekScores.isLoading ||
    monthScores.isLoading ||
    lifetimeScores.isLoading ||
    donations.isLoading;
  /**
   * A read that failed must not read as "they serve nothing and give nothing".
   * The line comes off and the footer says which half is missing. An hours read
   * that came back null did not fail — the fallback answered for it.
   */
  const sevaFailed = [
    ...hoursReads,
    ...(beforeSevaHours ? [weekScores, monthScores, lifetimeScores] : []),
  ].some((query) => query.isError && query.data === undefined);
  const summariesFailed =
    sevaFailed || (donations.isError && donations.data === undefined);

  const filtered = useMemo(() => {
    const term = search.trim().toLocaleLowerCase();
    const days =
      joinedOptions.find((option) => option.key === joined)?.days ?? 0;
    const cutoff = days ? Date.now() - days * DAY_MS : null;

    return rows.filter((row) => {
      if (
        term &&
        !`${row.name} ${row.email}`.toLocaleLowerCase().includes(term)
      ) {
        return false;
      }
      if (completeness === "complete" && row.completion < 100) return false;
      if (completeness === "incomplete" && row.completion >= 100) return false;
      if (accessLevel !== "all" && roleOf(row) !== accessLevel) return false;
      if (cutoff !== null && new Date(row.joined_at).getTime() < cutoff) {
        return false;
      }
      return true;
    });
  }, [accessLevel, completeness, joined, rows, search]);

  const completedCount = rows.filter((row) => row.completion >= 100).length;

  /**
   * The full record lives in the Devotees tab, so this crosses tabs rather than
   * pushing a second copy of that screen onto the Profile stack — the same path
   * Seva Care takes to the same place, so a coordinator only ever has one of
   * these open.
   */
  const openFullRecord = (row: DevoteeProfileRow) => {
    navigation
      .getParent<NavigationProp<MainTabParamList>>()
      ?.navigate("Devotees", {
        screen: "DevoteeSevaProfile",
        params: {
          devoteeId: row.id,
          name: row.name,
          photoUrl: row.photo_url,
        },
      } as never);
  };

  const exportList = async () => {
    setExportError(null);
    setExporting(true);
    try {
      await shareDevoteeList(filtered, summaries);
    } catch (caught) {
      setExportError(
        caught instanceof Error
          ? caught.message
          : "The devotee list could not be shared.",
      );
    } finally {
      setExporting(false);
    }
  };

  if (!canViewAll) {
    return (
      <Screen topInset={false}>
        <View className="items-center rounded-card border border-border bg-white px-card py-9">
          <Ionicons
            name="lock-closed-outline"
            size={30}
            color={tokens.colors.indigo}
          />
          <Text className="mt-3 text-center font-sans-bold text-base text-stone">
            President or Tech Admin access required
          </Text>
          <Text className="mt-1 text-center font-sans text-sm text-stoneMuted">
            The community roster stays available to you in Directory.
          </Text>
        </View>
      </Screen>
    );
  }

  return (
    <ListScreen
      topInset={false}
      data={filtered}
      keyExtractor={(row) => row.id}
      header={
        <>
          <ScreenTitle eyebrow="Congregation records">
            Devotee directory
          </ScreenTitle>

          <Pressable
            className="mb-section min-h-touch flex-row items-center justify-center rounded-button bg-indigo px-4"
            accessibilityRole="button"
            accessibilityLabel="Download devotee list"
            // Not until the summaries are in: a sheet exported early, or after
            // a read that failed, would carry empty seva and giving columns and
            // look like a temple where nobody serves or gives.
            disabled={
              !filtered.length ||
              exporting ||
              summariesPending ||
              summariesFailed
            }
            onPress={exportList}
          >
            <Ionicons
              name="download-outline"
              size={20}
              color={tokens.colors.white}
            />
            <Text className="ml-2 font-sans-bold text-base text-white">
              {summariesFailed
                ? "Seva and giving unavailable"
                : exporting || summariesPending
                  ? "Preparing list…"
                  : "Download devotee list"}
            </Text>
          </Pressable>

          <View className="min-h-touch flex-row items-center rounded-button border border-border bg-white px-4">
            <Ionicons name="search" size={19} color={tokens.colors.indigo} />
            <TextInput
              className="min-w-0 flex-1 px-3 py-3 font-sans text-base text-stone"
              accessibilityLabel="Search devotees by name or email"
              autoCapitalize="none"
              autoCorrect={false}
              value={search}
              onChangeText={setSearch}
              placeholder="Search by name or email"
              placeholderTextColor={tokens.colors.stoneMuted}
            />
          </View>

          <View className="mt-3 flex-row flex-wrap gap-2">
            {completenessOptions.map((option) => (
              <FilterChip
                key={option.key}
                label={option.label}
                selected={completeness === option.key}
                onPress={() => setCompleteness(option.key)}
              />
            ))}
          </View>

          <View className="mt-2 flex-row flex-wrap gap-2">
            <FilterChip
              label="All access"
              selected={accessLevel === "all"}
              onPress={() => setAccessLevel("all")}
            />
            {accessRoles.map((option) => (
              <FilterChip
                key={option}
                label={accessRoleLabels[option]}
                selected={accessLevel === option}
                onPress={() => setAccessLevel(option)}
              />
            ))}
          </View>

          <View className="mt-2 flex-row flex-wrap gap-2">
            {joinedOptions.map((option) => (
              <FilterChip
                key={option.key}
                label={option.label}
                selected={joined === option.key}
                onPress={() => setJoined(option.key)}
              />
            ))}
          </View>

          {/* Which window every devotee's hours are read over. Three, not
              four: there is no calendar-year period across the congregation,
              and the note underneath says where the year is kept rather than
              letting a coordinator assume "All time" is one. */}
          <View className="mt-3">
            <SevaRangeSwitch
              value={range}
              onChange={(next) => setRange(next as SevaPeriodKind)}
              options={congregationSevaRanges}
              subject="everybody’s seva"
            />
            <Text className="mt-2 font-sans text-xs leading-4 text-stoneMuted">
              Hours served, {sevaRangeCaptions[range].toLowerCase()}. A calendar
              year is kept per devotee — open one to read it.
            </Text>
          </View>

          <Text className="my-3 font-sans-bold text-sm text-peacock">
            {rows.length} devotee{rows.length === 1 ? "" : "s"} ·{" "}
            {completedCount} completed profile
            {completedCount === 1 ? "" : "s"}
            {filtered.length === rows.length
              ? ""
              : ` · showing ${filtered.length}`}
          </Text>
        </>
      }
      renderItem={(row) => (
        <DevoteeRow
          row={row}
          range={range}
          summary={summaries.get(row.id) ?? emptySummary}
          summariesPending={summariesPending}
          summariesFailed={summariesFailed}
          expanded={expandedId === row.id}
          onToggle={() => setExpandedId(expandedId === row.id ? null : row.id)}
          onOpenFullRecord={() => openFullRecord(row)}
        />
      )}
      empty={
        devotees.isLoading ? null : (
          <View className="items-center rounded-card border border-border bg-white px-card py-8">
            <Ionicons
              name="people-outline"
              size={30}
              color={tokens.colors.peacock}
            />
            <Text className="mt-3 text-center font-sans-bold text-base text-stone">
              No devotee matches these filters
            </Text>
            <Text className="mt-1 text-center font-sans text-sm text-stoneMuted">
              Try a shorter search or widen the access level and joined filters.
            </Text>
          </View>
        )
      }
      footer={
        exportError || devotees.error || summariesFailed ? (
          <FormError
            message={
              exportError ??
              (devotees.error instanceof Error
                ? devotees.error.message
                : devotees.error
                  ? "The devotee list could not be loaded."
                  : // The details are all here; only the two summaries are
                    // missing, and saying so is better than a row that reads
                    // as a devotee who has never served or given.
                    "Seva and giving could not be read, so those summaries are left off. The profile details below are complete.")
            }
          />
        ) : null
      }
    />
  );
}

/**
 * One devotee in the record.
 *
 * Its own component because expanding it asks the server which sevas they
 * actually serve, and a hook cannot live inside a list's render callback. The
 * request is made on expansion rather than for the whole roster: a coordinator
 * opens one or two rows, and two hundred per-devotee reads to fill a list
 * nobody has looked at yet would be a different screen entirely.
 */
function DevoteeRow({
  row,
  range,
  summary,
  summariesPending,
  summariesFailed,
  expanded,
  onToggle,
  onOpenFullRecord,
}: {
  row: DevoteeProfileRow;
  range: SevaPeriodKind;
  summary: DevoteeSummary;
  summariesPending: boolean;
  summariesFailed: boolean;
  expanded: boolean;
  onToggle: () => void;
  onOpenFullRecord: () => void;
}) {
  const roleLabel = accessRoleLabels[roleOf(row)];
  const complete = row.completion >= 100;
  const acts = summary.acts[range];
  const summaryLine = devoteeSummaryLine(summary, range);

  const balance = useDevoteeSevaBalance(row.id, expanded);
  const sevas = useMemo(
    () => devoteeSevaRanges(balance.data ?? [], [])[range],
    [balance.data, range],
  );

  return (
    <Pressable
      className="mb-3 rounded-card border border-border bg-white p-card"
      accessibilityRole="button"
      accessibilityState={{ expanded }}
      accessibilityLabel={`${row.name}, ${roleLabel}, profile ${row.completion} percent complete${
        summariesPending || summariesFailed ? "" : `. ${summaryLine}`
      }`}
      onPress={onToggle}
    >
      <View className="flex-row items-start">
        <Avatar
          name={row.name}
          photoUrl={row.photo_url}
          tone={complete ? "peacock" : "indigo"}
        />
        <View className="ml-3 min-w-0 flex-1">
          <Text className="font-sans-bold text-lg text-stone" numberOfLines={2}>
            {row.name}
          </Text>
          <Text className="mt-0.5 font-sans text-sm text-stoneMuted">
            {roleLabel} · Joined {dayLabel(row.joined_at) ?? "—"}
          </Text>
          <View className="mt-2 flex-row items-center">
            <View className="h-1.5 min-w-0 flex-1 overflow-hidden rounded-pill bg-sandalwood">
              <View
                className={complete ? "h-1.5 bg-peacock" : "h-1.5 bg-marigold"}
                style={{
                  width: `${Math.max(0, Math.min(100, row.completion))}%`,
                }}
              />
            </View>
            <Text
              className={`ml-2 font-sans-bold text-xs ${
                complete ? "text-peacock" : "text-stoneMuted"
              }`}
            >
              {row.completion}%
            </Text>
          </View>
        </View>
        <Ionicons
          name={expanded ? "chevron-up" : "chevron-down"}
          size={18}
          color={tokens.colors.stoneMuted}
        />
      </View>

      {/* Two figures, in the order a coordinator asks for them: what they
                serve, then what they give. Nothing that ranks them. */}
      {summariesPending || summariesFailed ? null : (
        <Text className="mt-2 font-sans text-sm text-stoneMuted">
          {summaryLine}
        </Text>
      )}

      {expanded ? (
        <View className="mt-3 border-t border-border pt-2">
          {/* The hours and the amount are on the line above, expanded or not,
              so opening a row adds to them rather than saying them again. What
              it adds about giving is how many gifts and when the last one was;
              what it adds about seva is which sevas, at the foot of this
              block. */}
          <DetailRow
            label="Gifts"
            value={devoteeGiftsLine(summary, dayLabel(summary.lastGiftAt))}
          />
          <DetailRow label="Email" value={row.email} />
          <DetailRow label="Phone" value={row.phone} />
          <DetailRow
            label="Date of birth"
            value={dayLabel(row.date_of_birth)}
          />
          <DetailRow label="Birth place" value={row.birth_place} />
          <DetailRow label="Address" value={row.address} />
          <DetailRow label="Spiritual mentor" value={row.spiritual_mentor} />
          <DetailRow
            label="Initiated"
            value={row.is_initiated ? "Yes" : "Not yet"}
          />
          <DetailRow label="Initiation" value={dayLabel(row.initiation_date)} />
          <DetailRow label="Diksha guru" value={row.diksha_guru} />
          <DetailRow
            label="First initiation"
            value={
              row.has_first_initiation
                ? (dayLabel(row.first_initiation_date) ?? "Received")
                : null
            }
          />
          <DetailRow label="First diksha guru" value={row.first_diksha_guru} />
          <DetailRow
            label="Second initiation"
            value={
              row.has_second_initiation
                ? (dayLabel(row.second_initiation_date) ?? "Received")
                : null
            }
          />
          <DetailRow
            label="Second diksha guru"
            value={row.second_diksha_guru}
          />
          <DetailRow
            label="Profile updated"
            value={dayLabel(row.profile_updated_at)}
          />

          {/* Which sevas, by name, for the range the record is showing.
                    Asked for only now, because this is the moment a
                    coordinator has a particular devotee in mind. */}
          <View className="mt-3 rounded-button border border-border bg-ivory px-3 py-3">
            <Text className="font-sans-bold text-xs uppercase tracking-wider text-stoneMuted">
              What they serve · {sevaRangeLabels[range].toLowerCase()}
              {acts > 0 ? ` · ${acts} act${acts === 1 ? "" : "s"}` : ""}
            </Text>
            <View className="mt-2">
              {balance.isLoading ? (
                <View className="gap-2">
                  <Skeleton height={13} width="60%" />
                  <Skeleton height={13} width="45%" />
                </View>
              ) : balance.isError && balance.data === undefined ? (
                <Text className="font-sans text-sm text-stoneMuted">
                  Their sevas could not be read.
                </Text>
              ) : (
                <SevaNameHoursList
                  totals={sevas}
                  empty={sevaRangeEmpty[range]}
                />
              )}
            </View>
          </View>

          {/* The record stops at hours and amounts. Seva act by act, what
                    one devotee carries most, and every gift live one tap on,
                    where there is room to read them. */}
          <Pressable
            className="mt-3 min-h-touch flex-row items-center justify-between rounded-button border border-border bg-ivory px-3"
            accessibilityRole="button"
            accessibilityLabel={`Open ${row.name}'s seva and giving in full`}
            onPress={onOpenFullRecord}
          >
            <Text className="font-sans-bold text-sm text-indigo">
              Their seva and giving in full
            </Text>
            <Ionicons
              name="chevron-forward"
              size={18}
              color={tokens.colors.indigo}
            />
          </Pressable>
        </View>
      ) : null}
    </Pressable>
  );
}
