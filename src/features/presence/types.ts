export type TemplePresenceSource = "manual" | "location_confirmed";

export type TemplePresenceRow = {
  user_id: string;
  is_at_temple: boolean;
  presence_date: string;
  source: TemplePresenceSource;
  checked_in_at: string | null;
  checked_out_at: string | null;
  updated_at: string;
};

export type TemplePresencePerson = {
  user_id: string;
  name: string;
  photo_url: string | null;
  checked_in_at: string;
  updated_at: string;
};

export type TemplePresenceDashboard = {
  current: TemplePresenceRow | null;
  people: TemplePresencePerson[];
};
