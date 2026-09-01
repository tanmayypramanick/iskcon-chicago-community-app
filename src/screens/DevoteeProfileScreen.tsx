import { Ionicons } from "@expo/vector-icons";
import type { NavigationProp } from "@react-navigation/native";
import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import { useQuery } from "@tanstack/react-query";
import { useMemo, useState } from "react";
import { Pressable, Text, View } from "react-native";

import tokens from "../../design-tokens.json";
import {
  Avatar,
  AvatarViewer,
  Button,
  Screen,
  ScreenTitle,
  Skeleton,
} from "../components/ui";
import {
  useCurrentAccessProfile,
  useDevoteeAccessGrants,
  useDevoteeProfiles,
} from "../features/access/hooks";
import {
  accessRoleLabels,
  hasAccessPermission,
  isAccessRole,
} from "../features/access/model";
import { useDonationTotals } from "../features/donations/hooks";
import { formatCents } from "../features/donations/types";
import { openConversation } from "../features/messaging/api";
import {
  devoteeSevaRanges,
  sevaActsWindow,
  sevaRangeCaptions,
  sevaRangeEmpty,
  type SevaRange,
} from "../features/profile/sevaHours";
import {
  useDevoteeSevaActs,
  useDevoteeSevaBalance,
} from "../features/profile/sevaHoursApi";
import {
  SevaNameHoursList,
  SevaRangeSwitch,
} from "../features/profile/sevaHoursCard";
import { TimetableLink } from "../features/schedule/components";
import { useAllSevaScores } from "../features/sevayatra/hooks";
import { formatHours, sevaCountLabel } from "../features/sevayatra/types";
import { FormError } from "../features/services/components";
import {
  chicagoWallClockToInstant,
  formatChicagoShortDate,
  getChicagoWallClock,
} from "../lib/chicagoDate";
import { getSupabaseClient } from "../lib/supabase";
import type {
  DevoteesStackParamList,
  MainTabParamList,
} from "../navigation/types";
import { usePrototypeSession } from "../store/usePrototypeSession";

type Props = NativeStackScreenProps<DevoteesStackParamList, "DevoteeProfile">;

/**
 * What `devotee_public_profile` returns. The private columns come back null
 * unless the viewer is the devotee themselves or holds `app.view_all`, which
 * `can_see_everything` reports.
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
  /** Derived from the date of birth by the server, so nobody counts years. */
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
  if (error) throw error;
  const rows = (data ?? []) as DevoteePublicProfile[];
  return rows[0] ?? null;
}

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

function genderLabel(value: string | null) {
  if (value === "male") return "Male";
  if (value === "female") return "Female";
  if (value === "prefer_not_to_say") return "Prefer not to say";
  return null;
}

/** How the devotee came by the access they hold. */
const grantSourceLabels: Record<string, string> = {
  appointment: "Appointed directly",
  request: "They asked and it was approved",
  backfill: "Held before the app kept a record",
};

function DetailRow({ label, value }: { label: string; value: string | null }) {
  if (!value) return null;
  return (
    <View className="mt-3 flex-row">
      <Text className="w-[132px] font-sans-bold text-xs uppercase tracking-wider text-stoneMuted">
        {label}
      </Text>
      <Text className="min-w-0 flex-1 font-sans text-sm leading-5 text-stone">
        {value}
      </Text>
    </View>
  );
}

export function DevoteeProfileScreen({ navigation, route }: Props) {
  const { devoteeId } = route.params;
  const activeUserId = usePrototypeSession((state) => state.activeUserId);
  const [viewingPhoto, setViewingPhoto] = useState(false);
  const [opening, setOpening] = useState(false);
  const [chatError, setChatError] = useState<string | null>(null);

  const profile = useQuery({
    queryKey: ["devotee-public-profile", devoteeId],
    queryFn: () => fetchDevoteePublicProfile(devoteeId),
  });

  // The record is for whoever runs the temple's seva, which is the same
  // predicate the server gates it on. It answers empty to anybody else, so this
  // only saves a pointless request.
  const viewer = useCurrentAccessProfile(activeUserId);
  const viewerRole = viewer.data?.role ?? "devotee";
  const maySeeGrant = hasAccessPermission(
    viewerRole,
    "services.manage_recurring",
  );
  // The seva profile is the President's and the Tech Admin's alone. Rendered
  // conditionally rather than disabled, so an ordinary devotee is never shown
  // that there is something here they cannot open.
  const maySeeSevaProfile = hasAccessPermission(viewerRole, "app.view_all");
  // The client's copy of `may_view_whole_seva_board()` — one devotee's
  // timetable is open to a Community Head as well as to the two above, which
  // `app.view_all` alone would have shut them out of.
  const maySeeTimetable =
    hasAccessPermission(viewerRole, "services.manage_recurring") ||
    hasAccessPermission(viewerRole, "app.view_all");
  const grants = useDevoteeAccessGrants(devoteeId, maySeeGrant);
  const grant = grants.data?.[0] ?? null;

  /**
   * The seva and giving summaries the temple asked to see on a profile: hours
   * and amounts, and nothing that ranks anybody. Every read here answers
   * nothing without `app.view_all`.
   *
   * The hours come from the balance function rather than from the score, so
   * they are hours SERVED — the score publishes credited minutes, which the
   * fairness caps trim, and a devotee who stayed four hours would be told they
   * served three. These are also the two reads the full seva record makes, so
   * opening it from here costs nothing.
   */
  const [range, setRange] = useState<SevaRange>("month");
  const actsWindow = useMemo(() => sevaActsWindow(), []);
  const balance = useDevoteeSevaBalance(devoteeId, maySeeSevaProfile);
  const sevaActs = useDevoteeSevaActs(devoteeId, maySeeSevaProfile);
  const ranges = useMemo(
    () =>
      devoteeSevaRanges(
        balance.data ?? [],
        sevaActs.data ?? [],
        actsWindow.yearStart,
      ),
    [balance.data, sevaActs.data, actsWindow.yearStart],
  );
  const selected = ranges[range];

  /**
   * Lifetime scores are the only all-time act count published for another
   * devotee, and they are recomputed nightly — a seva served this morning
   * reaches the hours above before it reaches this number.
   */
  const scores = useAllSevaScores("lifetime", maySeeSevaProfile);
  const givingTotals = useDonationTotals(
    null,
    null,
    devoteeId,
    maySeeSevaProfile,
  );
  const lifetime =
    scores.data?.find((row) => row.devotee_id === devoteeId) ?? null;
  const given = givingTotals.data ?? [];
  // The year is the one range assembled from the act list, so it is the one
  // that can be missing on its own; a zero would read as "nothing since January".
  const sevaUnread =
    (balance.isError && balance.data === undefined) ||
    (range === "year" && sevaActs.isError && sevaActs.data === undefined);
  const sevaLoading =
    balance.isLoading || (range === "year" && sevaActs.isLoading);
  const givingUnread = givingTotals.isError && givingTotals.data === undefined;

  /**
   * The initiation history, which `devotee_public_profile` does not return and
   * the congregation record does. Read from the roster the directory already
   * caches rather than left off the screen: a President opening a devotee
   * should not have to go back to a list to learn who initiated them. A
   * per-devotee read would be better and would need a new function.
   */
  const congregation = useDevoteeProfiles(maySeeSevaProfile);
  const record = congregation.data?.find((row) => row.id === devoteeId) ?? null;

  const devotee = profile.data ?? null;
  const roleLabel =
    devotee && isAccessRole(devotee.role_name)
      ? accessRoleLabels[devotee.role_name]
      : "Devotee";
  const isSelf = devoteeId === activeUserId;

  const startChat = async () => {
    if (!devotee) return;
    setChatError(null);
    setOpening(true);
    try {
      const conversationId = await openConversation(devotee.id);
      navigation.navigate("Chat", {
        conversationId,
        devoteeId: devotee.id,
        name: devotee.name,
      });
    } catch (caught) {
      setChatError(
        caught instanceof Error
          ? caught.message
          : "That conversation could not be opened.",
      );
    } finally {
      setOpening(false);
    }
  };

  if (profile.isLoading) {
    return (
      <Screen topInset={false}>
        <View className="items-center rounded-card border border-border bg-white p-card">
          <Text className="font-sans text-base text-stoneMuted">
            Loading this devotee…
          </Text>
        </View>
      </Screen>
    );
  }

  if (profile.error || !devotee) {
    return (
      <Screen topInset={false}>
        <View className="items-center rounded-card border border-border bg-white px-card py-9">
          <Ionicons
            name="person-outline"
            size={30}
            color={tokens.colors.indigo}
          />
          <Text className="mt-3 text-center font-sans-bold text-base text-stone">
            This devotee could not be found
          </Text>
          <Text className="mt-1 text-center font-sans text-sm text-stoneMuted">
            They may have left the congregation, or your connection dropped.
          </Text>
        </View>
      </Screen>
    );
  }

  return (
    <Screen topInset={false}>
      <ScreenTitle eyebrow={roleLabel}>{devotee.name}</ScreenTitle>

      <AvatarViewer
        person={
          viewingPhoto
            ? {
                name: devotee.name,
                photo_url: devotee.photo_url,
                subtitle: roleLabel,
              }
            : null
        }
        onClose={() => setViewingPhoto(false)}
      />

      <View className="items-center rounded-card border border-border bg-white px-card py-6">
        <Avatar
          name={devotee.name}
          photoUrl={devotee.photo_url}
          size="xlarge"
          tone="peacock"
          onPress={() => setViewingPhoto(true)}
        />
        <Text className="mt-4 text-center font-display text-2xl text-stone">
          {devotee.name}
        </Text>
        <View className="mt-2 rounded-pill bg-indigoSoft px-3 py-1">
          <Text className="font-sans-bold text-xs text-indigo">
            {roleLabel}
          </Text>
        </View>
        <Text className="mt-2 font-sans text-sm text-stoneMuted">
          Joined {dayLabel(devotee.joined_at) ?? "the temple"}
        </Text>

        {isSelf ? null : (
          <View className="mt-5 w-full">
            <Button
              icon="chatbubble-ellipses-outline"
              disabled={opening}
              onPress={() => void startChat()}
            >
              {opening ? "Opening…" : "Message"}
            </Button>
          </View>
        )}
      </View>

      <View className="mt-section rounded-card border border-border bg-white p-card">
        {/* Named for what it holds now that age and occupation sit here too. */}
        <Text className="font-sans-bold text-lg text-stone">About</Text>
        <DetailRow label="Email" value={devotee.email} />
        <DetailRow
          label="Date of birth"
          value={dayLabel(devotee.date_of_birth)}
        />
        <DetailRow label="Gender" value={genderLabel(devotee.gender)} />
        <DetailRow
          label="Age"
          value={devotee.age === null ? null : `${devotee.age}`}
        />
        <DetailRow label="Occupation" value={devotee.occupation} />
        {devotee.can_see_everything ? (
          <DetailRow label="Phone" value={devotee.phone} />
        ) : null}
      </View>

      {devotee.can_see_everything ? (
        <View className="mt-section rounded-card border border-border bg-white p-card">
          <Text className="font-sans-bold text-lg text-stone">
            {isSelf ? "Your private details" : "Private details"}
          </Text>
          <Text className="mt-1 font-sans text-sm text-stoneMuted">
            {isSelf
              ? "These are kept as part of the temple’s records and are not shown to the community."
              : "Visible to you because of your access level."}
          </Text>
          <DetailRow label="Birth place" value={devotee.birth_place} />
          <DetailRow label="Address" value={devotee.address} />
          <DetailRow
            label="Spiritual mentor"
            value={devotee.spiritual_mentor}
          />
          <DetailRow
            label="Initiated"
            value={devotee.is_initiated ? "Yes" : "Not yet"}
          />
          <DetailRow
            label="Initiation"
            value={dayLabel(record?.initiation_date ?? null)}
          />
          <DetailRow label="Diksha guru" value={devotee.diksha_guru} />
          <DetailRow
            label="First initiation"
            value={
              record?.has_first_initiation
                ? (dayLabel(record.first_initiation_date) ?? "Received")
                : null
            }
          />
          <DetailRow
            label="First diksha guru"
            value={record?.first_diksha_guru ?? null}
          />
          <DetailRow
            label="Second initiation"
            value={
              record?.has_second_initiation
                ? (dayLabel(record.second_initiation_date) ?? "Received")
                : null
            }
          />
          <DetailRow
            label="Second diksha guru"
            value={record?.second_diksha_guru ?? null}
          />
        </View>
      ) : null}

      {/* Below the profile details, not above them. The temple reads a
          devotee before it reads their hours: who they are comes first, and
          the seva and giving figures answer the next question. */}
      {maySeeSevaProfile ? (
        <View className="mt-section rounded-card border border-border bg-white px-card py-4">
          <View className="flex-row">
            <View className="min-w-0 flex-1 pr-3">
              <Text className="font-sans-bold text-[11px] uppercase tracking-widest text-stoneMuted">
                Seva
              </Text>
              {sevaLoading ? (
                <Skeleton height={26} width="70%" />
              ) : sevaUnread ? (
                // A read that failed is not a devotee who has served nothing.
                <Text className="mt-1 font-sans text-sm leading-8 text-stoneMuted">
                  Could not be read
                </Text>
              ) : (
                <>
                  <Text className="mt-1 font-display text-2xl leading-8 text-stone">
                    {formatHours(selected.hours)}
                  </Text>
                  <Text className="mt-0.5 font-sans text-sm leading-5 text-stoneMuted">
                    {sevaRangeCaptions[range]}
                  </Text>
                </>
              )}
            </View>
            <View className="min-w-0 flex-1">
              <Text className="font-sans-bold text-[11px] uppercase tracking-widest text-stoneMuted">
                Given
              </Text>
              {givingTotals.isLoading ? (
                <Skeleton height={26} width="70%" />
              ) : givingUnread ? (
                <Text className="mt-1 font-sans text-sm leading-8 text-stoneMuted">
                  Could not be read
                </Text>
              ) : given.length === 0 ? (
                <>
                  <Text className="mt-1 font-display text-2xl leading-8 text-stone">
                    $0.00
                  </Text>
                  <Text className="mt-0.5 font-sans text-sm text-stoneMuted">
                    No gift recorded
                  </Text>
                </>
              ) : (
                // One figure per currency. Two currencies are two units and are
                // never added together.
                given.map((total) => (
                  <View key={total.currency}>
                    <Text className="mt-1 font-display text-2xl leading-8 text-stone">
                      {formatCents(total.total_cents, total.currency)}
                    </Text>
                    <Text className="mt-0.5 font-sans text-sm text-stoneMuted">
                      {sevaCountLabel(total.gifts, "gift")}
                    </Text>
                  </View>
                ))
              )}
            </View>
          </View>

          {/* One switch, four ranges. The temple asked to read a devotee's
              hours over a week, a month, a year and all time; four stacked
              blocks would make a coordinator find the one they meant before
              they could read it. */}
          <View className="mt-3.5">
            <SevaRangeSwitch
              value={range}
              onChange={setRange}
              subject={`${devotee.name}'s seva`}
            />
          </View>

          {sevaLoading || sevaUnread ? null : (
            <View className="mt-3.5">
              {/* Which sevas, by name. "Eight hours" is a figure; "eight hours
                  of pot washing" is a conversation. */}
              <SevaNameHoursList
                totals={selected}
                limit={3}
                empty={sevaRangeEmpty[range]}
              />
              {lifetime ? (
                <Text className="mt-2.5 font-sans text-xs text-stoneMuted">
                  {sevaCountLabel(lifetime.seva_acts, "act")} of seva all told
                </Text>
              ) : null}
            </View>
          )}

          <Pressable
            className="mt-3 min-h-touch flex-row items-center justify-between border-t border-border pt-3"
            accessibilityRole="button"
            accessibilityLabel={`Open ${devotee.name}'s seva profile`}
            onPress={() =>
              navigation.navigate("DevoteeSevaProfile", {
                devoteeId: devotee.id,
                name: devotee.name,
                photoUrl: devotee.photo_url,
              })
            }
          >
            <Text className="min-w-0 flex-1 pr-3 font-sans-bold text-sm text-indigo">
              What {isSelf ? "you serve" : "they serve"}, act by act, and every
              gift
            </Text>
            <Ionicons
              name="chevron-forward"
              size={20}
              color={tokens.colors.indigo}
            />
          </Pressable>
        </View>
      ) : null}

      {/* Why this is here at all, in the temple's words: "this can be viewed by
          President, Tech Admin and Community Heads to see if they are free at
          what time to assign them seva." So it sits on the profile, where the
          asking is about to happen, and it crosses to the Seva tab rather than
          pushing a second copy of the timetable onto this stack. */}
      {maySeeTimetable && !isSelf ? (
        <View className="mt-section">
          <TimetableLink
            label={`When ${devotee.name.split(" ")[0]} is free, week by week`}
            hint="Opens their seva as a timetable before you ask them for more"
            onPress={() =>
              navigation
                .getParent<NavigationProp<MainTabParamList>>()
                ?.navigate("Services", {
                  screen: "Schedule",
                  params: {
                    devoteeId: devotee.id,
                    name: devotee.name,
                    photoUrl: devotee.photo_url,
                  },
                } as never)
            }
          />
        </View>
      ) : null}

      {maySeeGrant ? (
        <View className="mt-section rounded-card border border-border bg-white p-card">
          <Text className="font-sans-bold text-lg text-stone">Access</Text>
          <Text className="mt-1 font-sans text-sm leading-5 text-stoneMuted">
            Who gave {isSelf ? "you" : "them"} this access, and when. Visible to
            Community Heads, the President and the Tech Admin.
          </Text>
          {grants.isLoading ? (
            <View className="mt-4 gap-2">
              <Skeleton height={14} width="60%" />
              <Skeleton height={14} width="45%" />
            </View>
          ) : grant ? (
            <>
              <DetailRow label="Access level" value={grant.role_label} />
              <DetailRow
                label="Appointed by"
                value={grant.appointed_by_name?.trim() || "Not recorded"}
              />
              <DetailRow
                label="Appointed on"
                value={dayLabel(grant.appointed_at)}
              />
              <DetailRow
                label="How"
                value={grantSourceLabels[grant.source] ?? null}
              />
              <DetailRow label="Note" value={grant.note} />
            </>
          ) : (
            <Text className="mt-3 font-sans text-sm leading-5 text-stoneMuted">
              {roleLabel === accessRoleLabels.devotee
                ? "No access has been appointed — Devotee is where everybody starts."
                : `Their ${roleLabel} access has no appointment on record.`}
            </Text>
          )}
        </View>
      ) : null}

      {chatError ? <FormError message={chatError} /> : null}
    </Screen>
  );
}
