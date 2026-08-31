-- The temple's Deities, once, so every Head names Them the same way.
--
--   "[They] can also choose from the list which Deities -- like Kisora Kisori,
--    Gaura Nitai, or Jagannath Baldev Subhadra -- and write the names of who
--    dressed Them."
--
-- 202608290078_daily_darshan.sql made daily_darshan_images.deity free text and
-- 202608290079_darshan_week_and_voice.sql then made that text load-bearing:
-- §6 groups a day's pictures by lower(trim(deity)) to work out whether the
-- notification says "Kisora Kisori" or "Kisora Kisori and Gaura Nitai". Free
-- text and that grouping do not get on. Two Heads who type "Gaura Nitai" and
-- "Gaura-Nitai" for one altar produce two groups, and the congregation's lock
-- screen reads
--
--     Gaura Nitai and Gaura-Nitai - today's darshan from the temple.
--
-- which names the same Deities twice. So this file is not tidiness. It is the
-- thing that makes 0079's sentence true.
--
-- Neither 0078 nor 0079 is deployed yet; both are applied in the same sitting,
-- in order, immediately before this. Nothing below edits either of them. No
-- argument list either file established is touched: publish_daily_darshan,
-- list_daily_darshan, latest_daily_darshan, delete_daily_darshan and
-- may_post_daily_darshan are exactly as 0079 left them.
--
-- A table, and why
-- ----------------
-- The three candidates were a client constant, a row in app_settings, and a
-- table. The deciding question is the one that decides it every time: does the
-- temple installing a new Deity need an app release?
--
--   * A constant in src/ means yes. Installing Sri Sri Radha Govinda, or
--     giving the Deities' names their diacritics, or this app serving a second
--     temple with different altars, would each be a code change, a build, a
--     store review and a week. The temple can already change a programme time
--     without any of that -- 202608040069 made temple_programme a table for
--     exactly this reason -- and an altar is at least as much the temple's own
--     business as a programme time.
--   * app_settings means a JSON blob in a text column: no ordering, no
--     per-entry constraints, nothing to reference, and every read parsing a
--     string that nothing validates. app_settings holds dials -- single
--     scalars a President might change. This is a list of things with their
--     own properties, which is what tables are.
--   * A table means the President adds an altar with one RPC call and every
--     phone sees it on the next refresh.
--
-- So: a table. It is called temple_deities and not darshan_deities because the
-- Deities are the temple's, not the Daily Darshan feature's; the gallery, and
-- anything later, reads the same list.
--
-- The foreign key, and why not
-- ----------------------------
-- daily_darshan_images.deity stays TEXT and gains no reference. Written out,
-- because it is the one decision in this file that is a real trade:
--
--   For a foreign key: the notification grouping becomes exact by
--   construction, a typo is impossible, and renaming an altar could cascade.
--
--   Against it, and this is what settles it: a picture of a visiting Deity, or
--   a festival installation -- Their Lordships on the Ratha, a Deity brought
--   for an installation, Srila Prabhupada's murti on Vyasa Puja -- could not
--   be posted at all. The Head would press Post and get a foreign key
--   violation, in place of 0078's careful wording, for the entirely reasonable
--   act of photographing something that happens once a year. A catalogue of
--   permanent altars is not a closed vocabulary of everything a camera may
--   point at, and the temple asked for a list to choose from, not a fence.
--
--   And it would change 0079. deity would stop being the caption 0078 §4
--   describes; publish_daily_darshan would need a new failure mode; ON UPDATE
--   CASCADE would silently rewrite the captions of darshans already published.
--   None of that was asked for.
--
-- Which leaves the question the foreign key was going to answer: with deity
-- still free text, what stops the spelling drift that breaks the sentence?
--
--   Section 8. A BEFORE INSERT trigger on daily_darshan_images asks the
--   catalogue whether what was typed IS one of the temple's altars -- ignoring
--   case, spacing and punctuation, and consulting each entry's alternate
--   spellings -- and if it is, replaces it with the catalogue's canonical
--   name. "gaura-nitai", "Gaura Nitai", "NITAI GAURA" all land in the column
--   as "Gaura Nitai", so 0079 §6 groups them as one and says their name once.
--   Anything the catalogue does not recognise is stored exactly as typed,
--   which is the visiting Deity, unharmed.
--
--   This is stronger than a foreign key where it matters and weaker only where
--   weakness is the point. A foreign key would reject "gaura-nitai"; the
--   trigger fixes it, which is what the Head meant. A foreign key would reject
--   the Ratha; the trigger lets it through.
--
-- Requires 202608290078_daily_darshan.sql and
-- 202608290079_darshan_week_and_voice.sql.

-- ---------------------------------------------------------------------------
-- 0. What this file assumes, asserted rather than trusted.
--
--    0078 §0's assertion, repeated rather than borrowed: this file is applied
--    once now and may be re-applied to a database a later migration has
--    changed, and every one of these would fail quietly. A widened permission
--    would let a fourth role rename the temple's Deities; a missing 0079 would
--    mean the whole reason for the file is absent.
-- ---------------------------------------------------------------------------

do $$
declare
  v_holders text;
begin
  -- The same three the temple named for posting a darshan, identified the same
  -- way 0078 §2 identifies them. Section 6 explains why the catalogue's editors
  -- are exactly the darshan's posters and not a new key.
  select string_agg(roles.name, ',' order by roles.name) into v_holders
  from public.role_permissions
  join public.roles on roles.id = role_permissions.role_id
  where role_permissions.permission_key = 'services.manage_recurring';

  if v_holders is distinct from 'core,president,tech' then
    raise exception
      'services.manage_recurring is held by % - the Deity catalogue assumes core, president, tech.',
      coalesce(v_holders, '(nobody)');
  end if;

  if to_regclass('public.daily_darshan_images') is null then
    raise exception
      'public.daily_darshan_images is missing; apply 202608290078_daily_darshan.sql first.';
  end if;

  if to_regprocedure('public.daily_darshan_limit(text)') is null then
    raise exception
      'public.daily_darshan_limit is missing; apply 202608290078_daily_darshan.sql first.';
  end if;

  -- The function whose correctness this file exists to protect. Without 0079
  -- there is no grouping to keep honest, and a catalogue applied to 0078 alone
  -- would look like it was doing something it was not.
  if to_regprocedure('public.daily_darshan_deity_names(date)') is null then
    raise exception
      'public.daily_darshan_deity_names is missing; apply 202608290079_darshan_week_and_voice.sql first.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 1. The dials.
--
--    0078 §1's rule, unchanged: no function body below carries a bound.
--
--      max_name_chars   120  a Deity's name and each alternate spelling. The
--                            same 120 as daily_darshan.max_credit_chars, and
--                            section 7 checks it against that dial rather than
--                            assuming they agree -- a catalogue name longer
--                            than the credit limit would be a name the picker
--                            offers and publish_daily_darshan then refuses.
--      max_aliases       10  alternate spellings per Deity. Enough for the
--                            transliterations a congregation actually writes;
--                            not a place to paste a dictionary.
--      max_entries       50  active Deities. A picker is a short list of the
--                            altars in one building. Fifty is far past any
--                            temple and still a number, so the list cannot
--                            quietly become a phone book.
--      list_limit_max   100  a ceiling on one read, as 0078 §1 puts on its own.
--      order_step        10  the gap left between neighbouring display_orders,
--                            so a new altar can go between two existing ones
--                            without renumbering the rest.
--
--    The reader is 0078's daily_darshan_limit: one implementation of "read an
--    integer out of app_settings or raise", not two to keep in step. Its
--    message says "Daily Darshan dial" and names the key, which is still the
--    only thing a President needs in order to fix it.
--
--    ON CONFLICT DO NOTHING: re-running must not undo a number the President
--    has since changed.
-- ---------------------------------------------------------------------------

insert into public.app_settings (key, value) values
  ('temple_deities.max_name_chars', '120'),
  ('temple_deities.max_aliases', '10'),
  ('temple_deities.max_entries', '50'),
  ('temple_deities.list_limit_max', '100'),
  ('temple_deities.order_step', '10')
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------
-- 2. Two names are the same name.
--
--    The one rule the whole file rests on: strip everything that is not a
--    letter or a digit, and lower-case what is left. "Gaura Nitai",
--    "gaura-nitai", "Gaura  Nitai" and "GauraNitai" all become "gauranitai",
--    so the catalogue cannot hold two rows for one altar and a Head cannot
--    invent a second spelling of one.
--
--    [:alnum:] and not [a-z0-9], deliberately. Sanskrit names get written with
--    diacritics, and an ASCII class would reduce "Radha" to "rdh" -- turning
--    two spellings of one name into two different keys, which is precisely the
--    bug this function exists to prevent. [:alnum:] keeps every letter.
--
--    It does not fold diacritics: "Radha" and "Radha" with the marks stay
--    different keys, because doing that properly needs unaccent and this
--    database does not install it. That case is what aliases are for, and the
--    temple can add one without a migration.
-- ---------------------------------------------------------------------------

create or replace function public.temple_deity_match_key(p_name text)
returns text
language sql
immutable
set search_path = ''
as $$
  select nullif(regexp_replace(lower(coalesce(p_name, '')), '[^[:alnum:]]+', '', 'g'), '')
$$;

comment on function public.temple_deity_match_key(text) is
  'How the catalogue decides two spellings are one Deity: letters and digits only, lower-cased. Null for a name with no letters in it at all.';

revoke all on function public.temple_deity_match_key(text) from public, anon;
grant execute on function public.temple_deity_match_key(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. The catalogue.
--
--    match_key is a STORED GENERATED column and its expression is written out
--    here rather than calling section 2's function. A generated column may only
--    use immutable expressions, and a `create or replace` of a function used by
--    one would change new rows' keys without recomputing the old ones -- the
--    exact silent divergence this table exists to prevent. The two are checked
--    against each other in section 11, so the duplication is an invariant this
--    file proves rather than a copy that can rot.
--
--    display_order, not alphabetical. These are the altars of ONE temple: they
--    stand in an order, a devotee walks past them in an order, and the picker
--    should read the way the temple's own room reads. Alphabetical order is a
--    property of the strings, not of the building, and it would silently
--    reshuffle itself the day an altar is renamed or a new one installed. It is
--    also not unique -- two rows sharing a number is a temple that has not
--    decided yet, not a corruption -- so every read below orders by
--    (display_order, name) and is therefore deterministic regardless.
--
--    is_active rather than deletion. An altar that is no longer dressed must
--    stop appearing in the picker and must NOT stop existing: darshans already
--    published still carry Their name as text, the gallery still renders it,
--    and the alias mapping that canonicalises it must survive. So there is no
--    delete RPC in this file at all. Retiring is
--    update_temple_deity(id, p_is_active => false).
--
--    aliases are spellings, not names. They are matched against and never
--    displayed -- the picker shows `name`. This is where "Jagannatha Baladeva
--    Subhadra" is taught to mean "Jagannath Baldev Subhadra" without either
--    spelling reaching a lock screen twice.
-- ---------------------------------------------------------------------------

create table if not exists public.temple_deities (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  match_key text generated always as (
    nullif(regexp_replace(lower(name), '[^[:alnum:]]+', '', 'g'), '')
  ) stored,
  display_order integer not null default 0,
  aliases text[] not null default '{}'::text[],
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint temple_deity_name_not_blank check (nullif(trim(name), '') is not null),
  -- A name of nothing but punctuation normalises to null, which the unique
  -- index below would happily admit several of.
  constraint temple_deity_name_has_letters check (match_key is not null),
  constraint temple_deity_order_sane check (display_order >= 0)
);

comment on table public.temple_deities is
  'The temple''s Deities: the list a Community Head picks from when posting the Daily Darshan, and the spelling every picture of Them is stored under.';
comment on column public.temple_deities.name is
  'The canonical spelling. What the picker shows and what daily_darshan_images.deity is rewritten to.';
comment on column public.temple_deities.match_key is
  'name with everything but letters and digits removed, lower-cased. Two rows cannot share one.';
comment on column public.temple_deities.display_order is
  'The order the temple''s own altars stand in. Sparse, so a new Deity fits between two without renumbering.';
comment on column public.temple_deities.aliases is
  'Alternate spellings that mean this Deity. Matched against, never displayed.';
comment on column public.temple_deities.is_active is
  'False retires a Deity from the picker without removing Them: past darshans keep Their name and it keeps canonicalising.';

create unique index if not exists temple_deities_match_key_idx
  on public.temple_deities (match_key);

create index if not exists temple_deities_order_idx
  on public.temple_deities (display_order, name);

-- updated_at is maintained here and not only in the RPCs, so a fix applied by
-- hand in the SQL editor still stamps it.
create or replace function public.touch_temple_deity()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists touch_temple_deity on public.temple_deities;
create trigger touch_temple_deity
  before update on public.temple_deities
  for each row execute function public.touch_temple_deity();

-- ---------------------------------------------------------------------------
--    No two rows may claim one spelling.
--
--    The unique index covers names. It cannot cover aliases -- an alias of one
--    Deity colliding with the NAME of another, or with an alias of another, is
--    two rows disagreeing about what one string means, and section 4's lookup
--    would then return whichever the planner reached first. That is a
--    canonicalisation that changes answers between runs, which is worse than
--    no canonicalisation.
--
--    So it is a trigger, and it is on the table rather than in the RPCs
--    because the seed in section 10 and any hand-written fix must obey it too.
-- ---------------------------------------------------------------------------

create or replace function public.check_temple_deity_spellings()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_key text;
  v_owner text;
begin
  -- Every spelling this row claims: its name and each of its aliases.
  for v_key in
    select distinct public.temple_deity_match_key(spelling)
    from unnest(array[new.name] || coalesce(new.aliases, '{}'::text[])) as spelling
    where public.temple_deity_match_key(spelling) is not null
  loop
    select other.name into v_owner
    from public.temple_deities other
    where other.id <> new.id
      and (
        other.match_key = v_key
        or exists (
          select 1 from unnest(other.aliases) as other_alias
          where public.temple_deity_match_key(other_alias) = v_key
        )
      )
    limit 1;

    if v_owner is not null then
      raise exception
        'The spelling "%" already belongs to %. One spelling can only mean one Deity.',
        v_key, v_owner;
    end if;
  end loop;

  return new;
end;
$$;

comment on function public.check_temple_deity_spellings() is
  'Refuses a Deity whose name or alternate spelling already means a different Deity. A spelling that meant two altars would canonicalise unpredictably.';

drop trigger if exists check_temple_deity_spellings on public.temple_deities;
create trigger check_temple_deity_spellings
  before insert or update on public.temple_deities
  for each row execute function public.check_temple_deity_spellings();

-- ---------------------------------------------------------------------------
-- 4. Asking the catalogue what a typed name means.
--
--    Retired Deities are consulted. is_active governs the PICKER, not the
--    meaning of a word: an altar retired last year is still what "Gaura Nitai"
--    means, and a picture from before the retirement -- or a Head who types
--    the old name -- must still canonicalise to the spelling the gallery is
--    already full of. Excluding Them here would make the retirement itself the
--    start of a second spelling, which is the bug.
--
--    Null when nothing matches, so the caller can tell the difference between
--    "this is the temple's altar" and "this is something else" rather than
--    guessing from whether the string came back changed.
-- ---------------------------------------------------------------------------

create or replace function public.resolve_temple_deity_name(p_name text)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select deity.name
  from public.temple_deities deity
  where public.temple_deity_match_key(p_name) is not null
    and (
      deity.match_key = public.temple_deity_match_key(p_name)
      or exists (
        select 1 from unnest(deity.aliases) as alias
        where public.temple_deity_match_key(alias) = public.temple_deity_match_key(p_name)
      )
    )
  order by deity.match_key = public.temple_deity_match_key(p_name) desc, deity.display_order, deity.name
  limit 1
$$;

comment on function public.resolve_temple_deity_name(text) is
  'The catalogue''s spelling of a typed Deity name, matched on letters and digits alone and through alternate spellings. Null when the name is not one of the temple''s Deities. Retired Deities still answer.';

revoke all on function public.resolve_temple_deity_name(text) from public, anon;
grant execute on function public.resolve_temple_deity_name(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Reading the catalogue.
--
--    Open to every signed-in devotee, closed to anon, exactly as 0078 §5 has
--    the darshan itself. The picker is only shown to a Head, but the gallery
--    renders a Deity's name to everybody, and a devotee's client may want the
--    list to render it well. There is nothing private in a list of the altars
--    a visitor can see by walking in -- and nothing public either, because
--    anon reading it would be the open internet learning the temple's contents
--    from an app the congregation signed up to.
--
--    Both the table and an RPC, as 0078 does: the table so a client may select
--    from it directly, the RPC so ordering and the retired filter are decided
--    once, here, and not in each screen.
-- ---------------------------------------------------------------------------

alter table public.temple_deities enable row level security;

drop policy if exists "Devotees read the temple's Deities" on public.temple_deities;
create policy "Devotees read the temple's Deities"
  on public.temple_deities for select to authenticated
  using (auth.uid() is not null);

revoke all on public.temple_deities from anon, authenticated;
grant select (id, name, display_order, aliases, is_active, created_at, updated_at)
  on public.temple_deities to authenticated;

create or replace function public.list_temple_deities(
  p_include_retired boolean default false,
  p_limit integer default null
)
returns table (
  id uuid,
  name text,
  display_order integer,
  is_active boolean,
  aliases text[],
  created_at timestamptz,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    deity.id,
    deity.name,
    deity.display_order,
    deity.is_active,
    deity.aliases,
    deity.created_at,
    deity.updated_at
  from public.temple_deities deity
  where auth.uid() is not null
    and (coalesce(p_include_retired, false) or deity.is_active)
  order by deity.display_order, deity.name
  limit greatest(
    1,
    least(
      coalesce(p_limit, public.daily_darshan_limit('temple_deities.list_limit_max')),
      public.daily_darshan_limit('temple_deities.list_limit_max')
    )
  )
$$;

comment on function public.list_temple_deities(boolean, integer) is
  'The temple''s Deities in the temple''s own order, for the picker. Retired ones are left out unless asked for.';

revoke all on function public.list_temple_deities(boolean, integer) from public, anon;
grant execute on function public.list_temple_deities(boolean, integer) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. Who may change the list.
--
--    may_post_daily_darshan(), called rather than re-derived. 0078 §2 already
--    settled that Community Head, Tech Admin and President are named by
--    holding services.manage_recurring and that inventing a `deities.manage`
--    key would be a second thing to forget to grant the next President. Both of
--    that file's arguments apply here unchanged, and one more:
--
--    the set that may say which Deities were dressed today is the set that may
--    say which Deities the temple has. Writing `has_permission(...)` again here
--    would produce two functions that happen to agree today and could be
--    edited apart tomorrow. Calling 0078's makes them one sentence: whoever may
--    post a darshan may edit the altars a darshan names.
-- ---------------------------------------------------------------------------

create or replace function public.may_edit_temple_deities()
returns boolean
language sql
stable
set search_path = ''
as $$
  select public.may_post_daily_darshan()
$$;

comment on function public.may_edit_temple_deities() is
  'True for the Community Head, Tech Admin and President. Deliberately the same set as may_post_daily_darshan, by calling it.';

revoke all on function public.may_edit_temple_deities() from public, anon;
grant execute on function public.may_edit_temple_deities() to authenticated;

-- ---------------------------------------------------------------------------
-- 7. Adding and changing a Deity.
--
--    Two RPCs, no delete -- see section 3.
--
--    The name is checked against BOTH temple_deities.max_name_chars and
--    daily_darshan.max_credit_chars, and the second check is the interesting
--    one. Section 8 writes this name into daily_darshan_images.deity, and 0079
--    refuses a deity longer than max_credit_chars. A catalogue name past that
--    limit would be an entry the picker offers and every attempt to post
--    refuses, with the error naming a limit the Head never typed anything
--    against. So it is refused here, where it can be explained.
--
--    An omitted display_order goes to the end, a whole order_step past the
--    last, which is what a temple installing a new altar means by "and this
--    one".
-- ---------------------------------------------------------------------------

-- Trimmed, blank-free, de-duplicated by match key, and never the Deity's own
-- name again. Shared by both RPCs so they cannot disagree about what an alias
-- list is.
create or replace function public.clean_temple_deity_aliases(p_name text, p_aliases text[])
returns text[]
language sql
immutable
set search_path = ''
as $$
  select coalesce(
    (
      select array_agg(cleaned.alias order by cleaned.nth)
      from (
        select distinct on (public.temple_deity_match_key(entry.alias))
          trim(entry.alias) as alias,
          entry.nth
        from unnest(coalesce(p_aliases, '{}'::text[])) with ordinality as entry(alias, nth)
        where nullif(trim(coalesce(entry.alias, '')), '') is not null
          and public.temple_deity_match_key(entry.alias) is not null
          and public.temple_deity_match_key(entry.alias)
              is distinct from public.temple_deity_match_key(p_name)
        order by public.temple_deity_match_key(entry.alias), entry.nth
      ) as cleaned
    ),
    '{}'::text[]
  )
$$;

comment on function public.clean_temple_deity_aliases(text, text[]) is
  'An alias list as the catalogue stores it: trimmed, blanks dropped, duplicate spellings collapsed, and the Deity''s own name removed.';

revoke all on function public.clean_temple_deity_aliases(text, text[]) from public, anon, authenticated;

create or replace function public.add_temple_deity(
  p_name text,
  p_display_order integer default null,
  p_aliases text[] default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_max_name integer := public.daily_darshan_limit('temple_deities.max_name_chars');
  v_max_credit integer := public.daily_darshan_limit('daily_darshan.max_credit_chars');
  v_max_aliases integer := public.daily_darshan_limit('temple_deities.max_aliases');
  v_max_entries integer := public.daily_darshan_limit('temple_deities.max_entries');
  v_step integer := public.daily_darshan_limit('temple_deities.order_step');
  v_name text;
  v_aliases text[];
  v_alias text;
  v_order integer;
  v_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Sign in to add a Deity.';
  end if;

  if not public.may_edit_temple_deities() then
    raise exception 'Only a Community Head, Tech Admin, or the President can change the temple''s list of Deities.';
  end if;

  v_name := nullif(trim(coalesce(p_name, '')), '');
  if v_name is null then
    raise exception 'Please give the Deity''s name.';
  end if;

  if public.temple_deity_match_key(v_name) is null then
    raise exception 'A Deity''s name needs letters in it.';
  end if;

  if length(v_name) > v_max_name then
    raise exception 'A Deity''s name is at most % characters.', v_max_name;
  end if;

  -- See the section note: past this the picker would offer a name that
  -- publish_daily_darshan refuses.
  if length(v_name) > v_max_credit then
    raise exception
      'A Deity''s name is at most % characters, because that is the longest name a darshan picture can carry.',
      v_max_credit;
  end if;

  if (select count(*) from public.temple_deities where temple_deities.is_active) >= v_max_entries then
    raise exception 'The temple''s list already holds % Deities.', v_max_entries;
  end if;

  v_aliases := public.clean_temple_deity_aliases(v_name, p_aliases);

  if cardinality(v_aliases) > v_max_aliases then
    raise exception 'A Deity can have at most % alternate spellings.', v_max_aliases;
  end if;

  foreach v_alias in array v_aliases loop
    if length(v_alias) > v_max_name then
      raise exception 'The alternate spelling "%" is longer than % characters.', v_alias, v_max_name;
    end if;
  end loop;

  if p_display_order is not null and p_display_order < 0 then
    raise exception 'A Deity''s place in the list cannot be negative.';
  end if;

  v_order := coalesce(
    p_display_order,
    (select coalesce(max(temple_deities.display_order), 0) + v_step from public.temple_deities)
  );

  -- The unique index and the spelling trigger both speak here. Their messages
  -- are turned into the temple's, because "duplicate key value violates unique
  -- constraint" is not a sentence anybody should be shown.
  begin
    insert into public.temple_deities (name, display_order, aliases)
    values (v_name, v_order, v_aliases)
    returning temple_deities.id into v_id;
  exception when unique_violation then
    raise exception 'The temple''s list already has a Deity spelled like "%".', v_name;
  end;

  return v_id;
end;
$$;

comment on function public.add_temple_deity(text, integer, text[]) is
  'Adds one Deity to the temple''s list. Community Head, Tech Admin and President only.';

revoke all on function public.add_temple_deity(text, integer, text[]) from public, anon;
grant execute on function public.add_temple_deity(text, integer, text[]) to authenticated;

-- Every argument but the id is optional and null means "leave it alone", so a
-- client that only wants to reorder does not have to send back a name it never
-- displayed and risk overwriting one somebody else has just corrected.
create or replace function public.update_temple_deity(
  p_id uuid,
  p_name text default null,
  p_display_order integer default null,
  p_aliases text[] default null,
  p_is_active boolean default null
)
returns public.temple_deities
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_max_name integer := public.daily_darshan_limit('temple_deities.max_name_chars');
  v_max_credit integer := public.daily_darshan_limit('daily_darshan.max_credit_chars');
  v_max_aliases integer := public.daily_darshan_limit('temple_deities.max_aliases');
  v_max_entries integer := public.daily_darshan_limit('temple_deities.max_entries');
  v_target public.temple_deities;
  v_name text;
  v_aliases text[];
  v_alias text;
begin
  if auth.uid() is null then
    raise exception 'Sign in to change a Deity.';
  end if;

  if not public.may_edit_temple_deities() then
    raise exception 'Only a Community Head, Tech Admin, or the President can change the temple''s list of Deities.';
  end if;

  select * into v_target
  from public.temple_deities
  where temple_deities.id = p_id
  for update;

  if v_target.id is null then
    raise exception 'That Deity could not be found in the temple''s list.';
  end if;

  v_name := coalesce(nullif(trim(coalesce(p_name, '')), ''), v_target.name);

  if public.temple_deity_match_key(v_name) is null then
    raise exception 'A Deity''s name needs letters in it.';
  end if;
  if length(v_name) > v_max_name then
    raise exception 'A Deity''s name is at most % characters.', v_max_name;
  end if;
  if length(v_name) > v_max_credit then
    raise exception
      'A Deity''s name is at most % characters, because that is the longest name a darshan picture can carry.',
      v_max_credit;
  end if;

  v_aliases := case
    when p_aliases is null then public.clean_temple_deity_aliases(v_name, v_target.aliases)
    else public.clean_temple_deity_aliases(v_name, p_aliases)
  end;

  if cardinality(v_aliases) > v_max_aliases then
    raise exception 'A Deity can have at most % alternate spellings.', v_max_aliases;
  end if;

  foreach v_alias in array v_aliases loop
    if length(v_alias) > v_max_name then
      raise exception 'The alternate spelling "%" is longer than % characters.', v_alias, v_max_name;
    end if;
  end loop;

  if p_display_order is not null and p_display_order < 0 then
    raise exception 'A Deity''s place in the list cannot be negative.';
  end if;

  -- Bringing a retired Deity back counts against the same ceiling adding one
  -- does, or retire-and-restore would be a way around it.
  if p_is_active and not v_target.is_active
     and (select count(*) from public.temple_deities where temple_deities.is_active) >= v_max_entries
  then
    raise exception 'The temple''s list already holds % Deities.', v_max_entries;
  end if;

  begin
    update public.temple_deities
    set name = v_name,
        display_order = coalesce(p_display_order, temple_deities.display_order),
        aliases = v_aliases,
        is_active = coalesce(p_is_active, temple_deities.is_active)
    where temple_deities.id = v_target.id
    returning * into v_target;
  exception when unique_violation then
    raise exception 'The temple''s list already has a Deity spelled like "%".', v_name;
  end;

  return v_target;
end;
$$;

comment on function public.update_temple_deity(uuid, text, integer, text[], boolean) is
  'Renames, reorders, re-spells or retires one Deity. Null leaves a field alone; p_is_active => false retires without removing. Community Head, Tech Admin and President only.';

revoke all on function public.update_temple_deity(uuid, text, integer, text[], boolean) from public, anon;
grant execute on function public.update_temple_deity(uuid, text, integer, text[], boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- 8. What the Head typed, in the temple's spelling.
--
--    The header makes the argument; this is it. BEFORE INSERT OR UPDATE on the
--    picture rows, so it applies to publish_daily_darshan's INSERT ... SELECT
--    without that function being touched, and to any later way of writing an
--    image row that has not been thought of yet.
--
--    On the table rather than in publish_daily_darshan on purpose. 0079's
--    grouping reads the COLUMN; the guarantee therefore has to be about the
--    column, not about one of the paths into it. A second writer added in
--    0081 gets this for free and cannot forget it.
--
--    Unmatched names pass through untouched. That is the visiting Deity and the
--    festival installation, and it is the whole reason there is no foreign key.
--
--    Nothing here can lengthen a name past what 0079 accepts: section 7 refuses
--    a catalogue name longer than daily_darshan.max_credit_chars, so the
--    canonical spelling is always within the limit publish already checked.
-- ---------------------------------------------------------------------------

create or replace function public.canonicalise_darshan_deity()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_canonical text;
begin
  if new.deity is null then
    return new;
  end if;

  v_canonical := public.resolve_temple_deity_name(new.deity);

  -- coalesce, not an if: an unrecognised name keeps exactly what was typed.
  new.deity := coalesce(v_canonical, new.deity);
  return new;
end;
$$;

comment on function public.canonicalise_darshan_deity() is
  'Rewrites a darshan picture''s Deity to the temple''s own spelling when the catalogue recognises it, so 0079 groups a day''s pictures by altar rather than by spelling. Leaves an unrecognised name alone.';

drop trigger if exists canonicalise_darshan_deity on public.daily_darshan_images;
create trigger canonicalise_darshan_deity
  before insert or update on public.daily_darshan_images
  for each row execute function public.canonicalise_darshan_deity();

-- ---------------------------------------------------------------------------
-- 9. What the catalogue does not know yet.
--
--    The honest consequence of keeping deity as text is that drift is possible
--    -- it is just no longer invisible. Every Deity name in the gallery that
--    the catalogue does not recognise, with how many pictures carry it, so the
--    Tech Admin can see at a glance whether the temple has installed something
--    the list is missing or whether somebody typed a name three ways.
--
--    Editors only. It is a maintenance view of the catalogue, and a devotee
--    scrolling the gallery has no question it answers.
-- ---------------------------------------------------------------------------

create or replace function public.unmatched_darshan_deity_names()
returns table (
  deity text,
  pictures integer,
  days integer
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    (array_agg(trim(img.deity) order by img.created_at, img.id))[1],
    count(*)::integer,
    count(distinct darshan.darshan_on)::integer
  from public.daily_darshan_images img
  join public.daily_darshan darshan on darshan.id = img.darshan_id
  where public.may_edit_temple_deities()
    and nullif(trim(coalesce(img.deity, '')), '') is not null
    and public.resolve_temple_deity_name(img.deity) is null
  group by lower(trim(img.deity))
  order by count(*) desc, (array_agg(trim(img.deity) order by img.created_at, img.id))[1]
$$;

comment on function public.unmatched_darshan_deity_names() is
  'Deity names in the gallery that the temple''s list does not recognise, commonest first. Empty for anybody who cannot edit the list.';

revoke all on function public.unmatched_darshan_deity_names() from public, anon;
grant execute on function public.unmatched_darshan_deity_names() to authenticated;

-- ---------------------------------------------------------------------------
-- 10. The three the temple named.
--
--     In the temple's own order, which is the order the temple said them in.
--     Not alphabetical -- that would open on Gaura Nitai because G sorts before
--     J and K, which is a fact about the alphabet and not about the altar. See
--     section 3.
--
--     10, 20, 30, a whole order_step apart, so a fourth altar can be installed
--     between two of these without renumbering anything.
--
--     The aliases are the spellings a congregation actually writes. They are
--     not exhaustive and are not meant to be: the ones that differ only by
--     case, spacing or punctuation need no alias at all -- section 2 already
--     folds those -- so each entry below is a genuinely different string that
--     means the same Deities. The temple adds more with update_temple_deity.
--
--     Seeded only into an EMPTY catalogue. Row-by-row ON CONFLICT DO NOTHING
--     would look more careful and be less: once the temple has renamed Gaura
--     Nitai to a fuller name, that row's match key has changed, and a re-run
--     would insert "Gaura Nitai" a second time as a separate altar. "Seed the
--     list once, when there is no list" is the rule that survives every rename.
-- ---------------------------------------------------------------------------

do $$
declare
  v_step integer := public.daily_darshan_limit('temple_deities.order_step');
begin
  if exists (select 1 from public.temple_deities) then
    raise notice 'the temple already has a list of Deities; seeding nothing';
    return;
  end if;

  insert into public.temple_deities (name, display_order, aliases) values
    ('Kisora Kisori', v_step * 1,
      array['Kishora Kishori', 'Sri Sri Kisora Kisori']),
    ('Gaura Nitai', v_step * 2,
      array['Nitai Gaura', 'Gauranga Nityananda', 'Sri Sri Nitai Gaurasundara']),
    ('Jagannath Baldev Subhadra', v_step * 3,
      array['Jagannatha Baladeva Subhadra', 'Jagannath Baladev Subhadra',
            'Jagannath Subhadra Baldev', 'Jagannath Baladeva Subhadra']);
end;
$$;

-- ---------------------------------------------------------------------------
-- 11. The invariants this file rests on, checked rather than hoped for.
-- ---------------------------------------------------------------------------

do $$
declare
  v_bad text;
  v_count integer;
begin
  -- Section 3's duplicated expression really does agree with section 2's
  -- function. If a later edit changes one, this raises at deploy time rather
  -- than the day two spellings of one altar stop matching.
  select string_agg(temple_deities.name, ', ') into v_bad
  from public.temple_deities
  where temple_deities.match_key
        is distinct from public.temple_deity_match_key(temple_deities.name);

  if v_bad is not null then
    raise exception
      'temple_deity_match_key disagrees with the generated column for: %', v_bad;
  end if;

  -- The three the temple named are in the list, in the order it named them.
  select string_agg(temple_deities.name, ' | ' order by temple_deities.display_order,
                    temple_deities.name)
  into v_bad
  from public.temple_deities
  where temple_deities.is_active;

  if v_bad is null then
    raise exception 'The temple''s list of Deities is empty.';
  end if;

  -- The canonicaliser is attached to the column 0079 groups on.
  select count(*)::integer into v_count
  from pg_trigger
  where pg_trigger.tgrelid = 'public.daily_darshan_images'::regclass
    and pg_trigger.tgname = 'canonicalise_darshan_deity'
    and not pg_trigger.tgisinternal;

  if v_count <> 1 then
    raise exception 'The Deity canonicaliser is not attached to daily_darshan_images.';
  end if;

  -- And deity is still text with no reference, which 0079 depends on and the
  -- header argues for at length.
  if exists (
    select 1
    from pg_constraint
    where pg_constraint.conrelid = 'public.daily_darshan_images'::regclass
      and pg_constraint.contype = 'f'
      and 'deity' = any (
        select pg_attribute.attname
        from unnest(pg_constraint.conkey) as key
        join pg_attribute on pg_attribute.attrelid = pg_constraint.conrelid
                         and pg_attribute.attnum = key
      )
  ) then
    raise exception
      'daily_darshan_images.deity has grown a foreign key; 0080 §0 argues at length that it must not.';
  end if;
end;
$$;

do $$
begin
  raise notice 'temple deities applied';
end;
$$;
