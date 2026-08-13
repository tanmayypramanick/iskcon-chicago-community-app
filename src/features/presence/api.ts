import { getChicagoDateKey } from "../../lib/chicagoDate";
import { getSupabaseClient } from "../../lib/supabase";
import type {
  TemplePresenceDashboard,
  TemplePresencePerson,
  TemplePresenceRow,
  TemplePresenceSource,
} from "./types";

const PRESENCE_COLUMNS =
  "user_id,is_at_temple,presence_date,source,checked_in_at,checked_out_at,updated_at";

async function fetchCurrentRow(userId: string) {
  const { data, error } = await getSupabaseClient()
    .from("temple_presence")
    .select(PRESENCE_COLUMNS)
    .eq("user_id", userId)
    .maybeSingle<TemplePresenceRow>();

  if (error) throw error;
  return data;
}

export async function fetchTemplePresence(
  currentUserId: string,
): Promise<TemplePresenceDashboard> {
  const supabase = getSupabaseClient();
  const [current, peopleResult] = await Promise.all([
    fetchCurrentRow(currentUserId),
    supabase.rpc("list_temple_presence_today"),
  ]);

  if (peopleResult.error) throw peopleResult.error;

  const today = current?.presence_date === getChicagoDateKey() ? current : null;
  return {
    current: today,
    people: (peopleResult.data ?? []) as unknown as TemplePresencePerson[],
  };
}

export async function setMyTemplePresence(
  isAtTemple: boolean,
  source: TemplePresenceSource = "manual",
) {
  const { data, error } = await getSupabaseClient().rpc(
    "set_my_temple_presence",
    {
      p_is_at_temple: isAtTemple,
      p_source: source,
    },
  );

  if (error) throw error;
  return data as TemplePresenceRow;
}
