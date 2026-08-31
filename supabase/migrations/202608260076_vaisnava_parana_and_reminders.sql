-- The Vaisnava calendar starts speaking: parana windows become real times, and
-- the temple's day is announced the evening before, the morning of, and again
-- when the fast may be broken.
--
-- Three problems, in the order they have to be solved.
--
-- 1. A parana row's time exists only inside its own title. 202608260074 stored
--    what the ICS file said and nothing more, so
--
--      Break fast 07:15 (sunrise) - 08:48 (end of tithi) LT
--
--    is, to the database, a sentence. Nothing can sort it, compare it to now(),
--    decide whether the window has closed, or put "between 7:15 and 8:48 in the
--    morning" on a phone. Sections 1 to 4 give the row columns, parse them out
--    of the title on the way in, and backfill the published 2026 year.
--
-- 2. Nobody is told anything. Sections 5 to 10 add the three reminders the
--    temple asked for -- tomorrow, today, and the parana -- on the temple's own
--    clock, to the whole congregation, once each.
--
-- 3. The app has nothing to read. Section 9 adds the two RPCs a screen needs:
--    what falls today and tomorrow, and when the next fast may be broken.
--
-- The single hardest judgement in this file is not any of that. It is
-- restraint. The 2026 calendar carries 231 events across 127 days, and a job
-- that pushed all of them would put a notification on two hundred phones every
-- third day until the congregation turned the app off -- which costs the temple
-- every other notice it sends, including the ones about seva that somebody is
-- waiting on. What earns a push is argued at section 6 and dialled at
-- section 5; the calendar screen still shows everything.
--
-- Requires 202608260074_vaisnava_calendar.sql (the tables and the import RPC,
-- neither of which is altered here), 202608040026_push_delivery_and_reminders
-- (app_settings, app_setting, and the reminders-sent ledger pattern this file
-- copies), 202608020002 / 202608040010 (queue_app_notification) and
-- 202608040053_birthday_prompts.sql (the daily-job shape).

-- ---------------------------------------------------------------------------
-- 1. The columns a parana row should always have had.
--
--    start / end are times of day, not timestamps, because that is what the
--    source publishes and because a date already sits beside them in the same
--    row. The absolute instant is (event_date + parana_start_time) at time zone
--    'America/Chicago', computed at read time, which is DST-correct for free
--    and cannot go stale if a row is ever moved to another date.
--
--    On the DST / LT marker at the end of every title: it is kept, in
--    parana_clock_marker, and it is deliberately NOT used to interpret the
--    time. The printed value is already Chicago wall clock -- 05:15 DST on 12
--    June is quarter past five on a Chicago clock that morning, and 07:15 LT on
--    15 January is quarter past seven on the same clock in January. The marker
--    records which of the two the source was quoting, and it is worth keeping
--    for exactly one reason: when a devotee says "the app said 7:15 and the
--    website said something else", the marker is the thing that lets somebody
--    check the source row rather than guess. Treating it as an instruction --
--    adding an hour to the DST rows, say -- would move every summer window an
--    hour late and hand the congregation a broken fast.
--
--    Both reasons are stored as the source's own words ('sunrise', '1/4 of
--    tithi', '1/3 of daylight', 'end of tithi') rather than mapped onto an
--    enum. A new year may perfectly well publish a reason nobody here has seen,
--    and an enum would reject the row; the text is shown, not switched on.
-- ---------------------------------------------------------------------------

alter table public.vaisnava_calendar_events
  add column if not exists parana_start_time time,
  add column if not exists parana_start_reason text,
  add column if not exists parana_end_time time,
  add column if not exists parana_end_reason text,
  add column if not exists parana_is_open_ended boolean not null default false,
  add column if not exists parana_clock_marker text;

comment on column public.vaisnava_calendar_events.parana_start_time is
  'When the fast may be broken, as a Chicago wall-clock time of day. Null on every non-parana row, and on a parana row whose title did not match a known wording.';
comment on column public.vaisnava_calendar_events.parana_start_reason is
  'The source''s own words for why the window opens then -- "sunrise", "1/4 of tithi". Shown, never switched on.';
comment on column public.vaisnava_calendar_events.parana_end_time is
  'When the window closes, Chicago wall clock. Null when the window is open-ended or the title did not parse.';
comment on column public.vaisnava_calendar_events.parana_end_reason is
  'The source''s own words for why the window closes then -- "1/3 of daylight", "end of tithi".';
comment on column public.vaisnava_calendar_events.parana_is_open_ended is
  'True for the "Break fast after HH:MM" wording, which publishes a start and no end. No end is invented for it: the row says after, and the app says after.';
comment on column public.vaisnava_calendar_events.parana_clock_marker is
  'DST or LT, exactly as the source printed it. Recorded for traceability. NOT used to interpret the time -- the printed value is already Chicago wall clock either way.';

alter table public.vaisnava_calendar_events
  drop constraint if exists vaisnava_parana_window_shape;
alter table public.vaisnava_calendar_events
  add constraint vaisnava_parana_window_shape check (
    -- Nothing parsed.
    (parana_start_time is null
      and parana_end_time is null
      and not parana_is_open_ended)
    -- A start with no end, said so.
    or (parana_start_time is not null
      and parana_is_open_ended
      and parana_end_time is null)
    -- A real window, and it must run forwards.
    or (parana_start_time is not null
      and not parana_is_open_ended
      and parana_end_time is not null
      and parana_end_time > parana_start_time)
  );

alter table public.vaisnava_calendar_events
  drop constraint if exists vaisnava_parana_clock_marker_check;
alter table public.vaisnava_calendar_events
  add constraint vaisnava_parana_clock_marker_check check (
    parana_clock_marker is null or parana_clock_marker in ('DST', 'LT')
  );

create index if not exists vaisnava_calendar_parana_idx
  on public.vaisnava_calendar_events(event_date, parana_start_time)
  where event_kind = 'parana' and parana_start_time is not null;

-- ---------------------------------------------------------------------------
-- 2. Reading a time out of a sentence, defensively.
--
--    Two wordings are known, and they are the only two in the published years:
--
--      Break fast HH:MM (reason) - HH:MM (reason) [DST|LT]
--      Break fast after HH:MM (reason) [DST|LT]
--
--    Anything else returns all nulls. That is the whole point of this function
--    and it is worth being explicit about why, because the tempting alternative
--    -- raise, so somebody notices -- is wrong here. A year is imported by a
--    Community Head from an ICS file downloaded that morning. If GCal 12 ever
--    prints "Break fast between 07:15 and 08:48", a parser that raises takes
--    down replace_vaisnava_calendar_year and the temple has no calendar at all;
--    a parser that shrugs gives the temple its whole calendar with one row that
--    shows a title instead of a time, which is precisely what the row said
--    before this migration existed. Degrading to the status quo ante beats
--    failing closed.
--
--    Section 4 then asserts that the 2026 rows all parsed, so a silent
--    regression in the parser -- as opposed to a new wording from the source --
--    is caught while the migration is being applied.
--
--    Immutable and strict about its own output: an hour of 24, a minute of 61,
--    or an end at or before the start are all treated as "did not parse"
--    rather than written into a row the check constraint would then reject.
-- ---------------------------------------------------------------------------

create or replace function public.parse_vaisnava_parana(p_title text)
returns table (
  start_time time,
  start_reason text,
  end_time time,
  end_reason text,
  clock_marker text,
  is_open_ended boolean
)
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_title text := trim(coalesce(p_title, ''));
  v_match text[];
begin
  start_time := null;
  start_reason := null;
  end_time := null;
  end_reason := null;
  clock_marker := null;
  is_open_ended := false;

  -- Open-ended first: "Break fast after 07:45 (1/4 of tithi) LT". Tried before
  -- the ranged shape only for readability -- "after" cannot match the range.
  v_match := regexp_match(
    v_title,
    '^Break\s+fast\s+after\s+([0-9]{1,2}):([0-9]{2})\s*\(([^)]*)\)\s*(DST|LT)?\s*$',
    'i'
  );
  if v_match is not null then
    if v_match[1]::integer between 0 and 23 and v_match[2]::integer between 0 and 59 then
      start_time := make_time(v_match[1]::integer, v_match[2]::integer, 0);
      start_reason := nullif(trim(v_match[3]), '');
      clock_marker := upper(nullif(trim(coalesce(v_match[4], '')), ''));
      is_open_ended := true;
    end if;
    return next;
    return;
  end if;

  -- The ranged shape, which is every other parana row in both published years.
  v_match := regexp_match(
    v_title,
    '^Break\s+fast\s+([0-9]{1,2}):([0-9]{2})\s*\(([^)]*)\)\s*-\s*([0-9]{1,2}):([0-9]{2})\s*\(([^)]*)\)\s*(DST|LT)?\s*$',
    'i'
  );
  if v_match is not null then
    if v_match[1]::integer between 0 and 23
      and v_match[2]::integer between 0 and 59
      and v_match[4]::integer between 0 and 23
      and v_match[5]::integer between 0 and 59
      and make_time(v_match[4]::integer, v_match[5]::integer, 0)
          > make_time(v_match[1]::integer, v_match[2]::integer, 0)
    then
      start_time := make_time(v_match[1]::integer, v_match[2]::integer, 0);
      start_reason := nullif(trim(v_match[3]), '');
      end_time := make_time(v_match[4]::integer, v_match[5]::integer, 0);
      end_reason := nullif(trim(v_match[6]), '');
      clock_marker := upper(nullif(trim(coalesce(v_match[7], '')), ''));
    end if;
    return next;
    return;
  end if;

  -- Unknown wording. All nulls, no exception, no time shown.
  return next;
end;
$$;

comment on function public.parse_vaisnava_parana(text) is
  'Pulls the break-fast window out of a parana title. Returns all nulls for any wording it does not recognise, so a future year with new phrasing loses its times rather than its calendar.';

revoke all on function public.parse_vaisnava_parana(text) from public, anon;
grant execute on function public.parse_vaisnava_parana(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Parsed on the way in, for every year that will ever be imported.
--
--    A trigger rather than a change to replace_vaisnava_calendar_year, for two
--    reasons. The import RPC is deployed and its argument list is fixed; and a
--    trigger also covers the backfill below, a hand-corrected row, and whatever
--    writes a calendar event next. There is exactly one place where a title
--    becomes a time.
--
--    Non-parana rows are cleared rather than left alone, so the columns can
--    never carry a stale window from a row whose kind was corrected.
-- ---------------------------------------------------------------------------

create or replace function public.apply_vaisnava_parana_times()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_parsed record;
begin
  if new.event_kind <> 'parana' then
    new.parana_start_time := null;
    new.parana_start_reason := null;
    new.parana_end_time := null;
    new.parana_end_reason := null;
    new.parana_is_open_ended := false;
    new.parana_clock_marker := null;
    return new;
  end if;

  select * into v_parsed from public.parse_vaisnava_parana(new.title);

  new.parana_start_time := v_parsed.start_time;
  new.parana_start_reason := v_parsed.start_reason;
  new.parana_end_time := v_parsed.end_time;
  new.parana_end_reason := v_parsed.end_reason;
  new.parana_is_open_ended := coalesce(v_parsed.is_open_ended, false);
  new.parana_clock_marker := v_parsed.clock_marker;
  return new;
end;
$$;

drop trigger if exists apply_vaisnava_parana_times on public.vaisnava_calendar_events;
create trigger apply_vaisnava_parana_times
before insert or update on public.vaisnava_calendar_events
for each row execute function public.apply_vaisnava_parana_times();

-- ---------------------------------------------------------------------------
-- 4. Backfill the years already published, and prove 2026.
--
--    The update touches every row so the trigger fires on all of them; it is
--    idempotent and cheap at 231 rows a year.
--
--    The assertion is scoped to 2026 on purpose. 2026 is the year this
--    migration was written against and every one of its 24 parana rows must
--    have a real window. A later year is somebody else's import from somebody
--    else's file, and holding this migration hostage to wording nobody has seen
--    yet would be the failing-closed mistake section 2 exists to avoid.
-- ---------------------------------------------------------------------------

update public.vaisnava_calendar_events
set title = title
where event_kind = 'parana';

do $$
declare
  v_total integer;
  v_parsed integer;
  v_worst text;
begin
  select count(*)::integer into v_total
  from public.vaisnava_calendar_events
  where calendar_year = 2026 and event_kind = 'parana';

  if v_total = 0 then
    -- The 2026 calendar is not published in this database. Nothing to prove.
    raise notice 'no 2026 parana rows to backfill';
    return;
  end if;

  select count(*)::integer into v_parsed
  from public.vaisnava_calendar_events
  where calendar_year = 2026
    and event_kind = 'parana'
    and parana_start_time is not null;

  if v_parsed <> v_total then
    select string_agg(title, ' | ') into v_worst
    from public.vaisnava_calendar_events
    where calendar_year = 2026
      and event_kind = 'parana'
      and parana_start_time is null;
    raise exception
      'Only % of % published 2026 parana rows parsed into a window. Unparsed: %',
      v_parsed, v_total, v_worst;
  end if;

  raise notice 'all % parana rows of 2026 carry a window', v_total;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Every dial, in app_settings.
--
--    The hours are Chicago hours, 0-23, and they are read at every tick rather
--    than baked into a cron expression. The jobs below are scheduled hourly and
--    each one asks "is it my hour in Chicago?" before doing anything. That is
--    two things at once: the dial is live -- the President's "make it seven,
--    not six" is an update, not a redeploy -- and the hour does not drift by
--    one twice a year the way a fixed UTC cron entry does. pg_cron reads the
--    server clock, which on Supabase is UTC; America/Chicago is the only clock
--    the temple has.
--
--      tomorrow_hour  18  the evening before. A devotee learns at six that
--                         tomorrow is Ekadasi while there is still an evening
--                         in which to plan around it. Seven in the morning is
--                         too early to care and eleven at night is too late to
--                         act.
--      today_hour      6  before the temple's morning programme.
--      parana_hour     6  see section 8: one notice, early enough for the
--                         earliest window in either published year (05:15) to
--                         still be open when it lands, and specific enough that
--                         a 10:16 window is announced as 10:16 rather than
--                         pushed at 10:16.
--
--    max_named_events caps how many observances a single sentence names before
--    it says "and 2 more". Four is the largest a 2026 notable day actually has.
--
--    notable_kinds and vow_note_pattern are section 6's argument, made
--    adjustable without a migration.
-- ---------------------------------------------------------------------------

insert into public.app_settings (key, value) values
  ('vaisnava_calendar.tomorrow_hour', '18'),
  ('vaisnava_calendar.today_hour', '6'),
  ('vaisnava_calendar.parana_hour', '6'),
  ('vaisnava_calendar.max_named_events', '4'),
  ('vaisnava_calendar.notable_kinds', 'festival,ekadasi,fasting'),
  ('vaisnava_calendar.vow_note_pattern', 'fast')
on conflict (key) do nothing;

create or replace function public.vaisnava_calendar_dial(p_key text)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_value text;
begin
  select nullif(trim(app_settings.value), '') into v_value
  from public.app_settings
  where app_settings.key = p_key;

  if v_value is null then
    raise exception 'The Vaisnava calendar dial % is missing from app_settings.', p_key;
  end if;

  return v_value;
end;
$$;

comment on function public.vaisnava_calendar_dial(text) is
  'One Vaisnava calendar dial, read from app_settings. A missing dial raises rather than falling back to a default: a threshold that quietly reverts is a bug nobody finds.';

revoke all on function public.vaisnava_calendar_dial(text) from public, anon, authenticated;

create or replace function public.vaisnava_calendar_hour(p_key text)
returns integer
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_raw text := public.vaisnava_calendar_dial(p_key);
  v_hour integer;
begin
  begin
    v_hour := v_raw::integer;
  exception when others then
    raise exception 'The Vaisnava calendar dial % is not a whole hour: %', p_key, v_raw;
  end;

  if v_hour < 0 or v_hour > 23 then
    raise exception 'The Vaisnava calendar dial % is % rather than an hour between 0 and 23.', p_key, v_hour;
  end if;

  return v_hour;
end;
$$;

revoke all on function public.vaisnava_calendar_hour(text) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 6. What a day is, in words -- and which days are worth waking anybody for.
--
--    Three kinds of row live in this calendar and only one of them is an event:
--
--      * headline rows      "Sri Krsna Janmastami: Appearance of Lord Sri
--                            Krsna", "Lord Balarama -- Appearance",
--                            "Jhulana Yatra ends".
--      * qualifier rows     "(Fast till noon)", "(yogurt fast for one month)",
--                            "(Fasting is done yesterday, today is feast)".
--                            Parenthesised, and never the subject of anything
--                            -- they are a footnote on the headline beside
--                            them. A notice that reads "Today is (Fast till
--                            noon)" is the database talking.
--      * furniture          "--------- Dhanus Sankranti (Sun enters Sagittarius
--                            on 15 Dec, 22:49 LT) ---------", a separator the
--                            ICS file draws with hyphens.
--
--    So the sentence is built from the headline rows, and the qualifier rows
--    become the instruction at the end of it. That single decision is most of
--    what makes the notification read like a temple notice.
--
--    WHICH DAYS EARN A PUSH.
--
--    A day is notable when either
--
--      (a) it carries an event of a notable kind -- festival, ekadasi (the
--          Mahadvadasis), or fasting (the Ekadasi fasts). These are the days
--          the temple keeps: something is asked of the devotee, or something
--          is held at the temple.
--
--      (b) it carries a qualifier row that mentions a fast. This is the good
--          one, and it is why there is no hardcoded list of festival names
--          anywhere in this file. This calendar marks a vow day by hanging
--          "(Fast till noon)" underneath it, and that mark -- not the row's
--          own kind -- is what separates Balarama Purnima from an ordinary
--          appearance day. Nineteen days in 2026 carry it, and every one of
--          them is real: Gaura Purnima, Janmastami, Nrsimha Caturdasi,
--          Radhastami, Rama Navami, Srila Prabhupada's appearance and
--          disappearance, Balarama's appearance, and the rest. Kind alone
--          would have filed Vyasa Puja as one of the year's 84 acarya
--          appearance and disappearance days and said nothing.
--
--    WHAT DOES NOT EARN ONE, and why that is the point.
--
--    The 2026 calendar has 84 appearance and disappearance rows and 88
--    observances. Pushing them is a notification every third day, and there is
--    no version of that where the congregation reads them all; there is only
--    the version where they mute the app and stop seeing the seva that needed
--    covering on Saturday. So an acarya's appearance day with no fast attached
--    is on the calendar screen and not on the lock screen. So is "First day of
--    Daylight Saving Time", "Last day of the third Caturmasya month", and the
--    23rd of January -- which carries seven events, six of them acarya days,
--    and stays quiet. Fifty of 127 dated days are notable, which is roughly one
--    notice a week rather than one every third day.
--
--    Parana is not in notable_kinds. A break-fast window gets its own notice at
--    section 8, at its own hour, with the time in it; counting it here would
--    make every Dvadasi morning arrive twice.
-- ---------------------------------------------------------------------------

-- The one place a raw title becomes something you can put in a sentence.
create or replace function public.vaisnava_event_phrase(p_title text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    -- "Srila Prabhupada -- Appearance" is a database row. "the appearance day
    -- of Srila Prabhupada" is what somebody says out loud.
    when cleaned ~ '\s--\s*Appearance$'
      then 'the appearance day of ' || regexp_replace(cleaned, '\s--\s*Appearance$', '')
    when cleaned ~ '\s--\s*Disappearance$'
      then 'the disappearance day of ' || regexp_replace(cleaned, '\s--\s*Disappearance$', '')
    -- The fast is said once, at the end of the sentence, not inside every name.
    when cleaned ~ '^Fasting for '
      then regexp_replace(cleaned, '^Fasting for\s+', '')
    else cleaned
  end
  from (
    select
      -- Internal full stops ("Go Puja. Go Krda. Govardhana Puja.") would end
      -- the sentence three times over; a trailing one would end it early; and
      -- "[PURNIMA SYSTEM]" is a note to a calendar editor, not to a devotee.
      regexp_replace(
        regexp_replace(
          regexp_replace(trim(coalesce(p_title, '')), '\s*\[[^\]]*\]\s*$', ''),
          '\.\s*$', ''
        ),
        '\.\s+', ', ', 'g'
      ) as cleaned
  ) as prepared
$$;

comment on function public.vaisnava_event_phrase(text) is
  'Turns one calendar title into a phrase that can sit inside a sentence. The temple''s voice lives here rather than in a string literal in the app.';

revoke all on function public.vaisnava_event_phrase(text) from public, anon;
grant execute on function public.vaisnava_event_phrase(text) to authenticated;

-- Priority for choosing what a day is *called* when several things fall on it.
-- Festival first; then the Mahadvadasis and the Ekadasi fasts, which are what
-- the day is for; then the acaryas, whose day it also is; then everything else.
create or replace function public.vaisnava_kind_rank(p_kind text)
returns integer
language sql
immutable
set search_path = ''
as $$
  select case p_kind
    when 'festival' then 1
    when 'ekadasi' then 2
    when 'fasting' then 3
    when 'appearance' then 4
    when 'disappearance' then 5
    when 'observance' then 6
    else 7
  end
$$;

revoke all on function public.vaisnava_kind_rank(text) from public, anon;
grant execute on function public.vaisnava_kind_rank(text) to authenticated;

-- "between 7:15 am and 8:48 am" / "any time after 7:45 am".
create or replace function public.vaisnava_parana_phrase(
  p_start time,
  p_end time,
  p_open_ended boolean
)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_start is null then null
    when coalesce(p_open_ended, false) or p_end is null
      then 'any time after ' || to_char(p_start, 'FMHH12:MI am')
    else 'between ' || to_char(p_start, 'FMHH12:MI am')
      || ' and ' || to_char(p_end, 'FMHH12:MI am')
  end
$$;

revoke all on function public.vaisnava_parana_phrase(time, time, boolean) from public, anon;
grant execute on function public.vaisnava_parana_phrase(time, time, boolean) to authenticated;

-- Everything one day is, reduced to the pieces a sentence needs.
create or replace function public.vaisnava_day_summary(p_date date)
returns table (
  event_date date,
  is_notable boolean,
  named_count integer,
  lead_phrase text,
  phrase_list text,
  fasting_note text,
  has_fast boolean,
  event_count integer
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_kinds text[] := string_to_array(
    public.vaisnava_calendar_dial('vaisnava_calendar.notable_kinds'), ','
  );
  v_note_pattern text := public.vaisnava_calendar_dial('vaisnava_calendar.vow_note_pattern');
  v_max integer := public.vaisnava_calendar_dial('vaisnava_calendar.max_named_events')::integer;
  v_phrases text[];
  v_notes text[];
  v_shown text[];
  v_extra integer;
begin
  event_date := p_date;

  select
    coalesce(array_agg(
      public.vaisnava_event_phrase(events.title)
      order by public.vaisnava_kind_rank(events.event_kind), events.sort_order, events.title
    ), '{}'::text[])
  into v_phrases
  from public.vaisnava_calendar_events events
  where events.event_date = p_date
    and events.event_kind <> 'parana'
    and trim(events.title) not like '(%'
    and trim(events.title) !~ '^-{3,}';

  select coalesce(array_agg(
      upper(left(trim(both '()' from trim(events.title)), 1))
      || substr(trim(both '()' from trim(events.title)), 2)
      order by events.sort_order
    ), '{}'::text[])
  into v_notes
  from public.vaisnava_calendar_events events
  where events.event_date = p_date
    and trim(events.title) like '(%';

  select count(*)::integer into event_count
  from public.vaisnava_calendar_events events
  where events.event_date = p_date;

  named_count := cardinality(v_phrases);

  has_fast := exists (
    select 1 from public.vaisnava_calendar_events events
    where events.event_date = p_date and events.event_kind = 'fasting'
  );

  is_notable :=
    exists (
      select 1 from public.vaisnava_calendar_events events
      where events.event_date = p_date
        and events.event_kind = any (v_kinds)
    )
    or exists (
      select 1 from unnest(v_notes) note where note ~* v_note_pattern
    );

  -- A day of nothing but qualifier rows or separators is not a day with a name.
  if named_count = 0 then
    is_notable := false;
  end if;

  lead_phrase := case when named_count > 0 then v_phrases[1] end;

  if named_count = 0 then
    phrase_list := null;
  elsif named_count <= v_max then
    phrase_list := case
      when named_count = 1 then v_phrases[1]
      else array_to_string(v_phrases[1 : named_count - 1], ', ')
        || ' and ' || v_phrases[named_count]
    end;
  else
    v_shown := v_phrases[1 : v_max];
    v_extra := named_count - v_max;
    phrase_list := array_to_string(v_shown, ', ')
      || ' and ' || v_extra || ' more';
  end if;

  fasting_note := nullif(
    (select string_agg(note || '.', ' ') from unnest(v_notes) note),
    ''
  );

  return next;
end;
$$;

comment on function public.vaisnava_day_summary(date) is
  'One day of the Vaisnava calendar, reduced to the pieces a sentence needs: whether it is worth telling anybody about, what to call it, the observances in priority order, and the fasting instruction the calendar hangs underneath them.';

revoke all on function public.vaisnava_day_summary(date) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 7. The words themselves, for one day and one scope.
--
--    One function, used by the two jobs AND by the read RPC, so that the card
--    in the app and the notification on the lock screen cannot drift apart.
--
--    Two sentence shapes, chosen because a single one cannot be grammatical
--    for both cases:
--
--      one observance   Today is Gaura Purnima: Appearance of Sri Caitanya
--                       Mahaprabhu. Fast till moonrise.
--
--      several          Four observances fall today: Sri Visvarupa Mahotsava,
--                       Bhadra Purnima, Acceptance of sannyasa by Srila
--                       Prabhupada and Third month of Caturmasya begins. Milk
--                       fast for one month.
--
--    "Today is A, B and C" reads wrong the moment one of the phrases is a
--    clause ("Jhulana Yatra ends"), which on this calendar is often. Naming the
--    count first fixes it and, as a bonus, tells a devotee glancing at a
--    notification that there is more than one thing before they read a word.
--
--    The title always names the lead observance rather than saying "the temple
--    calendar", because a push whose title is a category is a push nobody
--    opens.
--
--    The fast, said once. If the calendar hung an instruction under the day,
--    that instruction is used verbatim -- it is more specific than anything
--    this file could compose ("Fast till noon for Varahadeva, with feast
--    tomorrow"). Otherwise, if a fasting row falls on the day, the sentence
--    says so plainly. And on the day itself -- not the evening before, where it
--    would be one clause too many -- the break-fast window from the next
--    morning is added, because a devotee starting an Ekadasi fast wants to know
--    when it ends.
-- ---------------------------------------------------------------------------

create or replace function public.vaisnava_reminder_text(
  p_date date,
  p_scope text
)
returns table (
  title text,
  body text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_day record;
  v_when text;
  v_parana record;
begin
  if p_scope not in ('today', 'tomorrow') then
    raise exception 'A Vaisnava calendar reminder is either for today or for tomorrow, not %.', p_scope;
  end if;

  select * into v_day from public.vaisnava_day_summary(p_date);

  if not v_day.is_notable then
    return;
  end if;

  v_when := p_scope;

  title := case
    when p_scope = 'today' then 'Today is ' || v_day.lead_phrase
    else 'Tomorrow is ' || v_day.lead_phrase
  end;
  if length(title) > 100 then
    title := left(title, 97) || '...';
  end if;

  body := case
    when v_day.named_count = 1
      then initcap(left(v_when, 1)) || substr(v_when, 2) || ' is ' || v_day.phrase_list || '.'
    else
      case v_day.named_count
        when 2 then 'Two'
        when 3 then 'Three'
        when 4 then 'Four'
        when 5 then 'Five'
        when 6 then 'Six'
        when 7 then 'Seven'
        else v_day.named_count::text
      end
      || ' observances fall ' || v_when || ': ' || v_day.phrase_list || '.'
  end;

  if v_day.fasting_note is not null then
    body := body || ' ' || v_day.fasting_note;
  elsif v_day.has_fast then
    body := body || ' Devotees fast ' || v_when || '.';
  end if;

  -- On the day of a fast, when the fast ends.
  if p_scope = 'today' and v_day.has_fast then
    select
      events.parana_start_time as start_time,
      events.parana_end_time as end_time,
      events.parana_is_open_ended as open_ended
    into v_parana
    from public.vaisnava_calendar_events events
    where events.event_date = p_date + 1
      and events.event_kind = 'parana'
      and events.parana_start_time is not null
    order by events.parana_start_time
    limit 1;

    if found then
      body := body || ' The fast is broken tomorrow '
        || public.vaisnava_parana_phrase(
             v_parana.start_time, v_parana.end_time, v_parana.open_ended
           )
        || '.';
    end if;
  end if;

  return next;
end;
$$;

comment on function public.vaisnava_reminder_text(date, text) is
  'The temple''s wording for one calendar day, for scope today or tomorrow. Returns no row at all for a day that does not earn a notification. Shared by the cron jobs and by the app''s read RPC so the two can never disagree.';

revoke all on function public.vaisnava_reminder_text(date, text) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 8. The notification kinds.
--
--    The list is EXTENDED rather than restated. 202608040053 wrote down, at
--    length, what goes wrong when a migration retypes this constraint by hand:
--    every kind added between that migration and this one is silently outlawed,
--    and the failure shows up at 7am when a job raises. This file cannot avoid
--    touching the constraint -- it adds three kinds -- so it reads the kinds
--    that are presently allowed straight out of the catalogue, adds its own,
--    and writes the union back. Another migration adding a kind in parallel
--    with this one therefore survives, in whichever order the two are applied.
--
--    The sanity floor exists because the whole scheme rests on one regexp: if
--    the constraint is ever rewritten in a shape where the quoted literals are
--    not the kinds, that regexp would quietly return a short list and this
--    would drop kinds instead of adding them. Forty-odd are allowed today, so
--    finding fewer than thirty means the parse went wrong, and it stops.
-- ---------------------------------------------------------------------------

do $$
declare
  v_definition text;
  v_kinds text[];
  v_new text[] := array['vaisnava_tomorrow', 'vaisnava_today', 'vaisnava_parana'];
begin
  select pg_get_constraintdef(pg_constraint.oid) into v_definition
  from pg_constraint
  where conname = 'app_notifications_kind_check'
    and conrelid = 'public.app_notifications'::regclass;

  if v_definition is null then
    raise exception
      'The app_notifications kind constraint is missing; apply the earlier migrations first.';
  end if;

  select array_agg(distinct quoted[1]) into v_kinds
  from regexp_matches(v_definition, '''([a-z_]+)''', 'g') as quoted;

  if v_kinds is null or cardinality(v_kinds) < 30 then
    raise exception
      'Only % notification kinds could be read out of app_notifications_kind_check; refusing to rewrite it.',
      coalesce(cardinality(v_kinds), 0);
  end if;

  select array_agg(distinct kind order by kind) into v_kinds
  from unnest(v_kinds || v_new) as kind;

  execute 'alter table public.app_notifications drop constraint app_notifications_kind_check';
  execute format(
    'alter table public.app_notifications add constraint app_notifications_kind_check check (kind in (%s))',
    (select string_agg(quote_literal(kind), ', ' order by kind) from unnest(v_kinds) as kind)
  );

  raise notice 'app_notifications now allows % kinds', cardinality(v_kinds);
end;
$$;

-- ---------------------------------------------------------------------------
-- 9. Never twice.
--
--    The guarantee is a primary key, not a time window.
--
--    202608040044 guards its birthday broadcast with "nothing of this kind in
--    the last twenty hours", which is right for a fact that recurs annually and
--    wrong here: two Ekadasi notices are twenty-nine hours apart on some pairs
--    of days and a fast day can sit beside a parana day. So each job CLAIMS its
--    day before it sends anything --
--
--      insert into vaisnava_calendar_reminders_sent (kind, event_date)
--      on conflict do nothing;  if not found then return 0; end if;
--
--    -- and the primary key (reminder_kind, event_date) makes a second claim
--    impossible. A late run, a retry, a manual `select
--    send_vaisnava_today_reminder();` from a psql window, two overlapping cron
--    ticks: the first one through inserts, everybody else gets zero rows from
--    the insert and returns without queueing. The claim and the sends are in
--    the same transaction, so a job that dies halfway rolls the claim back with
--    the notifications and the next tick does the whole thing properly.
--
--    Keyed on the date rather than on an event id, which is what makes "one
--    notification for a four-event day" structural rather than a property of
--    the loop: there is one row per kind per day and there is nothing a caller
--    can do to get two.
--
--    Deliberately not a child of vaisnava_calendar_publications. Re-importing
--    2026 from a corrected ICS file replaces every event row; it must not
--    un-send this morning's notification and let the evening tick send it
--    again.
-- ---------------------------------------------------------------------------

create table if not exists public.vaisnava_calendar_reminders_sent (
  reminder_kind text not null check (
    reminder_kind in ('vaisnava_tomorrow', 'vaisnava_today', 'vaisnava_parana')
  ),
  event_date date not null,
  sent_at timestamptz not null default now(),
  recipient_count integer not null default 0,
  primary key (reminder_kind, event_date)
);

comment on table public.vaisnava_calendar_reminders_sent is
  'One row per calendar reminder per day. The primary key is the idempotency guarantee: a job claims its row before it queues anything, so a retry, a late tick or a manual run cannot notify the congregation twice.';

alter table public.vaisnava_calendar_reminders_sent enable row level security;
revoke all on table public.vaisnava_calendar_reminders_sent from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 10. The three jobs.
--
--     Same shape as prompt_birthday_wishes and send_seva_reminders: definer,
--     returning how many notifications it queued, revoked from everybody, run
--     by pg_cron and by nobody else.
--
--     Who receives them: every devotee, which is what create_announcement and
--     announce_birthdays already do for a temple-wide notice. Checked before
--     assuming: this schema has no per-devotee notification preference to
--     respect -- no mute column, no digest setting, no per-kind opt-out
--     anywhere in migrations 0001 to 0075. The one opt-out that does exist is
--     device-level and downstream: device_push_tokens.active, which
--     202608040018 clears when Expo rejects a token and which the
--     send-service-notification function reads. A devotee who has turned push
--     off at the phone therefore still gets the in-app bell and no push, which
--     is exactly right and needs nothing from this file.
--
--     Never about a past event: every job derives its date from now() in
--     Chicago, so "tomorrow" and "today" cannot name a date that has gone, and
--     the parana job additionally refuses a window that has already closed.
-- ---------------------------------------------------------------------------

create or replace function public.send_vaisnava_tomorrow_reminder()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_today date := (now() at time zone 'America/Chicago')::date;
  v_date date := v_today + 1;
  v_hour integer := public.vaisnava_calendar_hour('vaisnava_calendar.tomorrow_hour');
  v_words record;
  v_devotee record;
  v_sent integer := 0;
begin
  if extract(hour from (now() at time zone 'America/Chicago'))::integer <> v_hour then
    return 0;
  end if;

  select * into v_words from public.vaisnava_reminder_text(v_date, 'tomorrow');
  if not found then
    return 0;
  end if;

  insert into public.vaisnava_calendar_reminders_sent (reminder_kind, event_date)
  values ('vaisnava_tomorrow', v_date)
  on conflict do nothing;

  if not found then
    return 0;
  end if;

  for v_devotee in select users.id from public.users
  loop
    perform public.queue_app_notification(
      v_devotee.id,
      'vaisnava_tomorrow',
      v_words.title,
      v_words.body,
      jsonb_build_object('eventDate', v_date, 'scope', 'tomorrow')
    );
    v_sent := v_sent + 1;
  end loop;

  update public.vaisnava_calendar_reminders_sent
  set recipient_count = v_sent
  where reminder_kind = 'vaisnava_tomorrow' and event_date = v_date;

  return v_sent;
end;
$$;

comment on function public.send_vaisnava_tomorrow_reminder() is
  'Tells the congregation, the evening before, what tomorrow is -- but only on a day that earns it. One notification per day however many observances fall on it. Safe to run any number of times.';

revoke all on function public.send_vaisnava_tomorrow_reminder() from public, anon, authenticated;

create or replace function public.send_vaisnava_today_reminder()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_date date := (now() at time zone 'America/Chicago')::date;
  v_hour integer := public.vaisnava_calendar_hour('vaisnava_calendar.today_hour');
  v_words record;
  v_devotee record;
  v_sent integer := 0;
begin
  if extract(hour from (now() at time zone 'America/Chicago'))::integer <> v_hour then
    return 0;
  end if;

  select * into v_words from public.vaisnava_reminder_text(v_date, 'today');
  if not found then
    return 0;
  end if;

  insert into public.vaisnava_calendar_reminders_sent (reminder_kind, event_date)
  values ('vaisnava_today', v_date)
  on conflict do nothing;

  if not found then
    return 0;
  end if;

  for v_devotee in select users.id from public.users
  loop
    perform public.queue_app_notification(
      v_devotee.id,
      'vaisnava_today',
      v_words.title,
      v_words.body,
      jsonb_build_object('eventDate', v_date, 'scope', 'today')
    );
    v_sent := v_sent + 1;
  end loop;

  update public.vaisnava_calendar_reminders_sent
  set recipient_count = v_sent
  where reminder_kind = 'vaisnava_today' and event_date = v_date;

  return v_sent;
end;
$$;

comment on function public.send_vaisnava_today_reminder() is
  'Tells the congregation, on the morning of, what today is -- and, on a fast day, when the fast is broken tomorrow. One notification per day. Safe to run any number of times.';

revoke all on function public.send_vaisnava_today_reminder() from public, anon, authenticated;

-- The parana notice.
--
-- One notice, at parana_hour, naming the window. Not a notice AT the window:
-- the windows in the published years open anywhere between 05:15 and 10:16, so
-- a job that fired when the window opened would be a 5:15am push five times a
-- year, and a job at a fixed later hour would tell a tenth of the congregation
-- about a window that opened three hours ago. A single early notice that says
-- "between 10:16 am and 10:46 am" is both kinder and more useful, and it is
-- what a temple notice board does.
--
-- A window that has already closed is never announced. In practice at 6am none
-- has -- the earliest close in either published year is 08:24 -- but the guard
-- is what makes a hand-run at noon, or a dial somebody moved to 11, behave.
-- An open-ended window has no close and so cannot have passed; it is announced
-- as "any time after 7:45 am".
--
-- A parana row whose title did not parse is skipped entirely. There is nothing
-- honest to say -- no time to print and no closing time to check against -- and
-- "Break fast <unparsed title>" on a lock screen is worse than the calendar
-- screen, which shows the row as the source wrote it.
create or replace function public.send_vaisnava_parana_reminder()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_date date := (now() at time zone 'America/Chicago')::date;
  v_hour integer := public.vaisnava_calendar_hour('vaisnava_calendar.parana_hour');
  v_parana record;
  v_devotee record;
  v_window text;
  v_sent integer := 0;
begin
  if extract(hour from (now() at time zone 'America/Chicago'))::integer <> v_hour then
    return 0;
  end if;

  select
    events.id,
    events.parana_start_time as start_time,
    events.parana_end_time as end_time,
    events.parana_is_open_ended as open_ended
  into v_parana
  from public.vaisnava_calendar_events events
  where events.event_date = v_date
    and events.event_kind = 'parana'
    and events.parana_start_time is not null
    and (
      events.parana_is_open_ended
      or (events.event_date + events.parana_end_time)
           at time zone 'America/Chicago' > now()
    )
  order by events.parana_start_time
  limit 1;

  if not found then
    return 0;
  end if;

  insert into public.vaisnava_calendar_reminders_sent (reminder_kind, event_date)
  values ('vaisnava_parana', v_date)
  on conflict do nothing;

  if not found then
    return 0;
  end if;

  v_window := public.vaisnava_parana_phrase(
    v_parana.start_time, v_parana.end_time, v_parana.open_ended
  );

  for v_devotee in select users.id from public.users
  loop
    perform public.queue_app_notification(
      v_devotee.id,
      'vaisnava_parana',
      'Break your fast this morning',
      'The fast may be broken this morning ' || v_window || ' (Chicago time).',
      jsonb_build_object(
        'eventDate', v_date,
        'eventId', v_parana.id,
        'scope', 'parana'
      )
    );
    v_sent := v_sent + 1;
  end loop;

  update public.vaisnava_calendar_reminders_sent
  set recipient_count = v_sent
  where reminder_kind = 'vaisnava_parana' and event_date = v_date;

  return v_sent;
end;
$$;

comment on function public.send_vaisnava_parana_reminder() is
  'Tells the congregation, on the morning of a parana, when the fast may be broken. Silent on a day with no parana, on a window that has already closed, and on a row whose time could not be read. Safe to run any number of times.';

revoke all on function public.send_vaisnava_parana_reminder() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 11. What the app reads.
--
--     Any signed-in devotee, which is what 202608260074 already grants on the
--     tables themselves. Both refuse to be reached by anon, and both return an
--     empty set rather than raising when nobody is signed in: these back a card
--     the home screen draws, and an app in the middle of signing out should
--     show nothing there, not an error.
--
--     vaisnava_calendar_outlook returns today AND tomorrow, always, notable or
--     not -- the card wants to show "Sri Advaita Acarya's appearance day" on a
--     quiet day even though nobody is pushed about it. is_notable tells the
--     screen whether the temple thought it worth a notification, and headline /
--     summary are literally the strings the push would carry, so the card and
--     the lock screen say the same thing in the same words.
-- ---------------------------------------------------------------------------

create or replace function public.vaisnava_calendar_outlook()
returns table (
  scope text,
  event_date date,
  is_notable boolean,
  headline text,
  summary text,
  fasting_note text,
  event_count integer,
  events jsonb
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_today date := (now() at time zone 'America/Chicago')::date;
  v_scope text;
  v_date date;
  v_day record;
  v_words record;
begin
  if auth.uid() is null then
    return;
  end if;

  foreach v_scope in array array['today', 'tomorrow']
  loop
    v_date := case when v_scope = 'today' then v_today else v_today + 1 end;

    select * into v_day from public.vaisnava_day_summary(v_date);
    select * into v_words from public.vaisnava_reminder_text(v_date, v_scope);

    scope := v_scope;
    event_date := v_date;
    is_notable := v_day.is_notable;
    headline := v_words.title;
    summary := v_words.body;
    fasting_note := v_day.fasting_note;
    event_count := v_day.event_count;

    select coalesce(jsonb_agg(
      jsonb_build_object(
        'id', day_events.id,
        'title', day_events.title,
        'kind', day_events.event_kind,
        'sortOrder', day_events.sort_order,
        'phrase', public.vaisnava_event_phrase(day_events.title),
        'paranaStartTime', day_events.parana_start_time,
        'paranaEndTime', day_events.parana_end_time,
        'paranaStartReason', day_events.parana_start_reason,
        'paranaEndReason', day_events.parana_end_reason,
        'paranaClockMarker', day_events.parana_clock_marker,
        'paranaIsOpenEnded', day_events.parana_is_open_ended,
        'paranaStartsAt', case when day_events.parana_start_time is not null
          then (day_events.event_date + day_events.parana_start_time) at time zone 'America/Chicago' end,
        'paranaEndsAt', case when day_events.parana_end_time is not null
          then (day_events.event_date + day_events.parana_end_time) at time zone 'America/Chicago' end,
        'paranaWindow', public.vaisnava_parana_phrase(
          day_events.parana_start_time, day_events.parana_end_time, day_events.parana_is_open_ended
        )
      )
      order by public.vaisnava_kind_rank(day_events.event_kind), day_events.sort_order
    ), '[]'::jsonb)
    into events
    from public.vaisnava_calendar_events day_events
    where day_events.event_date = v_date;

    return next;
  end loop;
end;
$$;

comment on function public.vaisnava_calendar_outlook() is
  'Today and tomorrow on the Chicago Vaisnava calendar, for any signed-in devotee: every event, plus the exact headline and sentence the notification would carry, plus is_notable so the screen knows whether one was sent. Empty when nobody is signed in.';

revoke all on function public.vaisnava_calendar_outlook() from public, anon;
grant execute on function public.vaisnava_calendar_outlook() to authenticated;

create or replace function public.next_vaisnava_parana()
returns table (
  event_id uuid,
  event_date date,
  title text,
  start_time time,
  end_time time,
  starts_at timestamptz,
  ends_at timestamptz,
  start_reason text,
  end_reason text,
  clock_marker text,
  is_open_ended boolean,
  is_open_now boolean,
  window_phrase text
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    events.id,
    events.event_date,
    events.title,
    events.parana_start_time,
    events.parana_end_time,
    (events.event_date + events.parana_start_time) at time zone 'America/Chicago',
    case when events.parana_end_time is not null
      then (events.event_date + events.parana_end_time) at time zone 'America/Chicago' end,
    events.parana_start_reason,
    events.parana_end_reason,
    events.parana_clock_marker,
    events.parana_is_open_ended,
    now() >= (events.event_date + events.parana_start_time) at time zone 'America/Chicago'
      and (
        events.parana_is_open_ended
        or now() < (events.event_date + events.parana_end_time) at time zone 'America/Chicago'
      ),
    public.vaisnava_parana_phrase(
      events.parana_start_time, events.parana_end_time, events.parana_is_open_ended
    )
  from public.vaisnava_calendar_events events
  where auth.uid() is not null
    and events.event_kind = 'parana'
    and events.parana_start_time is not null
    and events.event_date >= (now() at time zone 'America/Chicago')::date
    and (
      events.parana_is_open_ended
      or (events.event_date + events.parana_end_time)
           at time zone 'America/Chicago' > now()
    )
  order by events.event_date, events.parana_start_time
  limit 1
$$;

comment on function public.next_vaisnava_parana() is
  'The next break-fast window that has not closed, in Chicago time, for any signed-in devotee. Skips parana rows whose title could not be read, because a window with no time is not a window. Empty when nobody is signed in and when no year is published.';

revoke all on function public.next_vaisnava_parana() from public, anon;
grant execute on function public.next_vaisnava_parana() to authenticated;

-- ---------------------------------------------------------------------------
-- 12. On the clock.
--
--     Hourly, with the hour itself decided inside the function from
--     app_settings (section 5). Guarded on pg_cron the way 0026, 0044 and 0053
--     guard theirs: on a database without the extension -- every local and CI
--     database this file is applied to -- nothing is scheduled and nothing
--     fails.
-- ---------------------------------------------------------------------------

do $$
declare
  v_job record;
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    return;
  end if;

  for v_job in
    select * from (values
      ('vaisnava-tomorrow-reminder', 'select public.send_vaisnava_tomorrow_reminder();'),
      ('vaisnava-today-reminder', 'select public.send_vaisnava_today_reminder();'),
      ('vaisnava-parana-reminder', 'select public.send_vaisnava_parana_reminder();')
    ) as jobs(name, command)
  loop
    if exists (select 1 from cron.job where jobname = v_job.name) then
      perform cron.unschedule(v_job.name);
    end if;
    perform cron.schedule(v_job.name, '0 * * * *', v_job.command);
  end loop;
end;
$$;

do $$
begin
  raise notice 'vaisnava parana times and calendar reminders applied';
end;
$$;
