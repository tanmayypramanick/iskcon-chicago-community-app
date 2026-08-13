import { Ionicons } from "@expo/vector-icons";
import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import { useQuery } from "@tanstack/react-query";
import { useState } from "react";
import { Pressable, Text, View } from "react-native";

import tokens from "../../design-tokens.json";
import {
  Avatar,
  LoadFailure,
  Screen,
  ScreenTitle,
  Skeleton,
} from "../components/ui";
import { useCurrentAccessProfile } from "../features/access/hooks";
import { hasAccessPermission } from "../features/access/model";
import { errorMessage, isConnectionProblem } from "../features/services/format";
import { Disclosure, SevaChipRow } from "../features/sevayatra/components";
import { useSevaYatraDevoteeSummary } from "../features/sevayatra/hooks";
import {
  formatHours,
  formatSevaRange,
  sevaBoardModeLabel,
  sevaCountLabel,
  sevaGivingFigure,
  sevaRangeChips,
  sevaRanges,
  scoredPeriodForRange,
  type SevaRangeKind,
} from "../features/sevayatra/types";
import {
  chicagoWallClockToInstant,
  formatChicagoShortDate,
  getChicagoWallClock,
} from "../lib/chicagoDate";
import { reportReachability, useServerReachable } from "../lib/connectivity";
import { getSupabaseClient } from "../lib/supabase";
import type { HomeStackParamList } from "../navigation/types";
import { usePrototypeSession } from "../store/usePrototypeSession";

type Props = NativeStackScreenProps<HomeStackParamList, "SevaBoardDevotee">;

/**
 * The two boards, by the names the Leaderboard's own chooser gives them.
 *
 * `seva_yatra_devotee_summary` dense-ranks by the combined score and by nothing
 * else, so `standing` is a place on one particular board however the reader got
 * here. A devotee who tapped second place on "Seva only" and was shown a bare
 * "Rank 3" read it as their place there and concluded the board had moved them.
 * Naming the board makes the same integer true from either one.
 */
const COMBINED_BOARD = sevaBoardModeLabel("combined");
const SEVA_BOARD = sevaBoardModeLabel("seva");

/**
 * What `devotee_public_profile` returns. The private columns come back null
 * unless the viewer is the devotee themselves or holds `app.view_all`, which
 * `can_see_everything` reports — so this screen shows a President everything
 * and an ordinary devotee only what the congregation may see, without
 * containing a rule of its own about which is which.
 */
type DevoteePublicProfile = {
  id: string;
  name: string;
  email: string | null;
  photo_url: string | null;
  role_name: string;
  joined_at: string;
  date_of_birth: string | null;
  gender: string | null;
  age: number | null;
  occupation: string | null;
  phone: string | null;
  birth_place: string | null;
  address: string | null;
  spiritual_mentor: string | null;
  is_initiated: boolean | null;
  diksha_guru: string | null;
  can_see_everything: boolean;
};

async function fetchDevoteePublicProfile(
  devoteeId: string,
): Promise<DevoteePublicProfile | null> {
  const { data, error } = await getSupabaseClient().rpc(
    "devotee_public_profile",
    { p_devotee_id: devoteeId },
  );
  reportReachability(!error || !isConnectionProblem(error));
  if (error) throw error;
  return ((data ?? []) as DevoteePublicProfile[])[0] ?? null;
}

/**
 * A stored date is a plain "YYYY-MM-DD" with no time in it. Reading it as an
 * instant lands on UTC midnight, which is still the previous evening in
 * Chicago, so every such date would render a day early.
 */
function dayLabel(value: string | null) {
  if (!value) return null;
  const instant = value.includes("T")
    ? new Date(value)
    : chicagoWallClockToInstant(value, "12:00");
  if (Number.isNaN(instant.getTime())) return null;
  return `${formatChicagoShortDate(instant)}, ${getChicagoWallClock(instant).year}`;
}

function DetailRow({ label, value }: { label: string; value: string | null }) {
  if (!value) return null;
  return (
    <View className="mt-3 flex-row">
      <Text className="w-[124px] font-sans-bold text-xs uppercase tracking-wider text-stoneMuted">
        {label}
      </Text>
      <Text className="min-w-0 flex-1 font-sans text-sm leading-5 text-stone">
        {value}
      </Text>
    </View>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <View className="min-w-0 flex-1">
      <Text className="font-sans text-[11px] uppercase tracking-wider text-stoneMuted">
        {label}
      </Text>
      <Text
        className="mt-1 font-sans-bold text-base text-stone"
        numberOfLines={1}
        adjustsFontSizeToFit
        minimumFontScale={0.8}
      >
        {value}
      </Text>
    </View>
  );
}

/**
 * Why a name is where it is on the board.
 *
 * A leaderboard that cannot be interrogated is a rumour: a devotee sees a
 * position and has no way to learn what it is made of, and the temple gets
 * asked instead. This is the answer — their points, their hours, their giving
 * and the seva they carry most, for the period the board was showing — beside
 * their profile as the congregation may read it.
 *
 * Every figure comes from `seva_yatra_devotee_summary`, which decides for
 * itself what this caller may know. Nothing here reconstructs a number the
 * server declined to send.
 */
export function SevaBoardDevoteeScreen({ navigation, route }: Props) {
  const { devoteeId, name, photoUrl } = route.params;
  const activeUserId = usePrototypeSession((state) => state.activeUserId);
  const viewer = useCurrentAccessProfile(activeUserId);
  const mayViewAll = hasAccessPermission(
    viewer.data?.role ?? "devotee",
    "app.view_all",
  );
  const reachable = useServerReachable();

  const [range, setRange] = useState<SevaRangeKind>(route.params.range);
  // The calendar year is a reading window with no score behind it, so there is
  // no period to ask the summary about. Said on the screen rather than by
  // leaving the year out of the chooser.
  const period = scoredPeriodForRange(range);

  const summary = useSevaYatraDevoteeSummary(
    devoteeId,
    period ?? "week",
    Boolean(period),
  );
  const profile = useQuery({
    queryKey: ["devotee-public-profile", devoteeId],
    queryFn: () => fetchDevoteePublicProfile(devoteeId),
  });

  const row = summary.data ?? null;
  const summaryFailed = summary.isError && summary.data === undefined;
  const them = profile.data ?? null;

  // Hours from what they served, points from what the scoring credited — the
  // same rule the devotee's own profile follows, so the two never disagree.
  const servedHours = Number(row?.served_minutes ?? 0) / 60;
  // A fraction of THEIR seva. The temple's own total is not in this row and is
  // not what the sentence beside it claims.
  const share = Number(row?.top_seva_share ?? 0);
  const giving = row ? sevaGivingFigure(row) : null;
  // The two published integers. The hero is the combined one because the rank
  // beside it is; the seva-only figure is said out loud whenever it differs,
  // which is the number the "Seva only" board showed against this same name.
  const points = Number(row?.points ?? 0);
  const sevaOnlyPoints = Number(row?.seva_points ?? 0);
  const boardsDiffer = sevaOnlyPoints > 0 && sevaOnlyPoints !== points;

  return (
    <Screen topInset={false}>
      <ScreenTitle eyebrow="Seva Yatra">{name}</ScreenTitle>

      <View className="mb-4">
        <SevaChipRow
          value={range}
          options={sevaRanges.map((key) => ({
            key,
            label: sevaRangeChips[key],
          }))}
          onChange={setRange}
        />
      </View>

      <View className="items-center rounded-card border border-border bg-white px-card py-6">
        <Avatar
          name={name}
          photoUrl={photoUrl ?? them?.photo_url ?? null}
          size="large"
          tone="peacock"
        />
        {!period ? (
          <Text className="mt-4 max-w-72 text-center font-sans text-sm leading-6 text-stoneMuted">
            The temple gives points by the week, by the month and for all time.
            A year is a read rather than a race, so there is no place to show
            for one.
          </Text>
        ) : summary.isLoading ? (
          <View className="mt-4 w-full items-center gap-2">
            <Skeleton height={40} width="45%" />
            <Skeleton height={14} width="30%" />
          </View>
        ) : summaryFailed ? (
          <View className="mt-4 w-full">
            <LoadFailure
              reachable={reachable}
              message={errorMessage(summary.error, "")}
              onRetry={() => void summary.refetch()}
            />
          </View>
        ) : row ? (
          <>
            {/* The published integer, not the norm behind it: `score` is
                app.view_all's and arrives null for everybody else, which read
                as this devotee having scored nothing. */}
            <Text className="mt-4 font-display text-[44px] leading-[52px] text-stone">
              {points.toLocaleString("en-US")}
            </Text>
            <Text className="font-sans text-sm text-stoneMuted">
              seva points
            </Text>
            {row.standing ? (
              <View className="mt-3 flex-row items-center rounded-pill bg-marigoldSoft px-3.5 py-1.5">
                <Ionicons
                  name="trophy"
                  size={14}
                  color={tokens.colors.stone}
                />
                <Text className="ml-1.5 font-sans-bold text-sm text-stone">
                  Rank {row.standing} · {COMBINED_BOARD}
                </Text>
              </View>
            ) : null}
            {boardsDiffer ? (
              <Text className="mt-2 font-sans text-xs text-stoneMuted">
                {SEVA_BOARD} · {sevaOnlyPoints.toLocaleString("en-US")} points
              </Text>
            ) : null}
            {row.period_start && row.period_end ? (
              <Text className="mt-2 font-sans text-xs text-stoneMuted">
                {formatSevaRange(row.period_start, row.period_end)}
              </Text>
            ) : null}
          </>
        ) : (
          // The server answers with nothing about a devotee who is not on this
          // period's board, and makes "opted out" and "did nothing" look the
          // same on purpose. One sentence has to be true of both. Their profile
          // below still loads either way.
          <Text className="mt-4 max-w-72 text-center font-sans text-sm leading-6 text-stoneMuted">
            There is nothing published for this period.
          </Text>
        )}
      </View>

      {row && giving ? (
        <View className="mt-3 flex-row rounded-card border border-border bg-white px-card py-3.5">
          <Stat label="Hours served" value={formatHours(servedHours)} />
          {/* Cents to whoever may read them, and to everybody else the one
              thing about giving that is already public — that they gave. Never
              a zero standing in for a figure the server withheld. */}
          <Stat label={giving.label} value={giving.value} />
          {/* The counted acts, which is what the points were made of. Labelled
              as such beside hours that are deliberately not: a devotee whose
              seva is all waiting has hours here and no acts, and "Acts" over a
              nought would read as a contradiction of the figure beside it. */}
          <Stat
            label="Acts counted"
            value={String(Number(row.seva_acts ?? 0).toLocaleString("en-US"))}
          />
        </View>
      ) : null}

      {row?.top_seva_name ? (
        <View className="mt-3 rounded-card border border-peacock bg-peacockSoft px-card py-4">
          <Text className="font-sans-bold text-[11px] uppercase tracking-widest text-peacock">
            What they carry most
          </Text>
          <Text
            className="mt-1 font-display text-2xl leading-8 text-stone"
            numberOfLines={2}
          >
            {row.top_seva_name}
          </Text>
          <Text className="mt-1 font-sans text-sm leading-6 text-stone">
            {formatHours(row.top_seva_hours ?? 0)}
            {share > 0 ? ` · ${Math.round(share * 100)}% of their seva` : ""}
          </Text>
        </View>
      ) : null}

      <View className="mt-section">
        <Disclosure label="Their profile">
          <View className="mt-1 rounded-card border border-border bg-white px-card pb-4 pt-1">
            {profile.isLoading ? (
              <View className="gap-2 py-3">
                <Skeleton height={14} width="60%" />
                <Skeleton height={14} width="45%" />
              </View>
            ) : profile.isError && them === null ? (
              <View className="py-3">
                <LoadFailure
                  reachable={reachable}
                  message={errorMessage(profile.error, "")}
                  onRetry={() => void profile.refetch()}
                />
              </View>
            ) : them ? (
              <>
                <DetailRow label="Name" value={them.name} />
                <DetailRow label="Role" value={them.role_name} />
                <DetailRow label="With us since" value={dayLabel(them.joined_at)} />
                <DetailRow label="Seva" value={them.occupation} />
                <DetailRow
                  label="Initiated"
                  value={
                    them.is_initiated === null
                      ? null
                      : them.is_initiated
                        ? (them.diksha_guru ?? "Yes")
                        : "Not yet"
                  }
                />
                <DetailRow label="Guidance" value={them.spiritual_mentor} />
                <DetailRow label="Birthday" value={dayLabel(them.date_of_birth)} />
                <DetailRow
                  label="Age"
                  value={them.age === null ? null : String(them.age)}
                />
                <DetailRow label="Gender" value={them.gender} />
                <DetailRow label="From" value={them.birth_place} />
                <DetailRow label="Phone" value={them.phone} />
                <DetailRow label="Email" value={them.email} />
                <DetailRow label="Address" value={them.address} />
                {/* The server decides what is null here. Said out loud only to
                    whoever it decided to show everything to, so a devotee is
                    never told there is a fuller record they cannot see. */}
                {them.can_see_everything ? (
                  <Text className="mt-4 border-t border-border pt-3 font-sans text-xs leading-5 text-stoneMuted">
                    You are seeing the temple's whole record because of the
                    access you hold. Other devotees see the name, the role and
                    what this devotee chose to share.
                  </Text>
                ) : null}
              </>
            ) : (
              <Text className="py-3 font-sans text-sm leading-6 text-stoneMuted">
                This devotee has not shared a profile.
              </Text>
            )}
          </View>
        </Disclosure>
      </View>

      {mayViewAll ? (
        <Pressable
          className="mt-3 min-h-touch flex-row items-center rounded-card border border-border bg-white px-card py-3.5"
          accessibilityRole="button"
          accessibilityLabel={`See ${name}'s seva history`}
          onPress={() =>
            navigation.navigate("SevaCareDevotee", { devoteeId, name })
          }
        >
          <Ionicons name="time-outline" size={20} color={tokens.colors.indigo} />
          <Text className="ml-3 min-w-0 flex-1 font-sans-bold text-base text-stone">
            {/* One name for one destination, wherever it is reached from. */}
            Their seva history
          </Text>
          <Ionicons
            name="chevron-forward"
            size={18}
            color={tokens.colors.stoneMuted}
          />
        </Pressable>
      ) : null}

      {row && row.gifts ? (
        <Text className="mt-3 font-sans text-xs leading-5 text-stoneMuted">
          {sevaCountLabel(row.gifts, "gift")} counted towards this period.
        </Text>
      ) : null}
    </Screen>
  );
}
