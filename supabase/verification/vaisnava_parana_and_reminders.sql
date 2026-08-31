-- Functional verification for 202608260076_vaisnava_parana_and_reminders.sql.
--
-- Rolled back at the end. Every local is prefixed v_ so it can never shadow a
-- column name. Anything that must be refused is attempted as the devotee who
-- would really attempt it, under `set local role authenticated`, so the grants
-- and the sign-in checks are the thing being tested rather than superuser
-- rights quietly waving everything through.
--
-- Every instant is derived from the Chicago clock, never written as a literal
-- hour, so the suite passes at 2am and at 2pm alike. now() is the
-- transaction's timestamp and this whole file is one transaction, so "today"
-- cannot roll over underneath a later section.
--
-- The people in this script:
--   President   ...0001
--   Tech        ...0002
--   Volunteer   ...0003
--   Devotee     ...0004  the lowest access level, who must still be able to
--                        read the calendar and must still be told what today is
--
-- The synthetic days, all inside the transaction, all rolled back:
--
--   T-2  vow day     an acarya's appearance plus "(Fast till noon)".
--                    Notable ONLY because of the parenthesised vow, which is
--                    the whole of section 6's argument in the migration.
--   T-1  quiet day   two acaryas and an ordinary observance. Notable by
--                    nothing. Also the past day nothing may be sent about.
--   T    today       four headline observances, one vow note, one parana whose
--                    window is open. The four-event day.
--   T+1  tomorrow    one festival.
--   T+2  kind day    one Ekadasi fast and nothing else. Notable ONLY by kind.
--
-- What this script exists to prove:
--
--    1. Every one of the 24 published 2026 parana rows carries a real window.
--    2. Every known wording parses to exactly the right time, reason and marker.
--    3. The open-ended wording parses with a null end and invents nothing.
--    4. An unknown wording degrades to nulls and does not raise.
--    5. The marker is kept and is NOT used to shift the clock.
--    6. The window is read as Chicago wall clock across the DST boundary.
--    7. A quiet day produces no wording and no notification.
--    8. A four-event day produces exactly ONE notification, worded as a notice.
--    9. Each job run twice notifies once.
--   10. Nothing is sent about a past day, or a parana whose window has closed,
--       or a parana whose time could not be read.
--   11. Every hour and threshold is a live dial in app_settings.
--   12. The reads are open to every signed-in devotee and closed to anon.
--   13. No devotee can run any of the three jobs by hand.
--   14. Thirteen mutations, each breaking exactly one guard.
--
-- The final row must read: vaisnava parana and reminders verification passed

begin;

-- This suite builds a parana window that is open "for the rest of today" and
-- one that closed "at the start of today", so it needs a few minutes of Chicago
-- day on either side. Said out loud rather than flaking once a year at 00:00.
do $$
declare
  v_clock time := (now() at time zone 'America/Chicago')::time;
begin
  if v_clock < time '00:05' or v_clock > time '23:55' then
    raise exception
      'This suite needs the Chicago clock between 00:05 and 23:55; it is now %.', v_clock;
  end if;
end;
$$;

insert into auth.users (id, email, raw_user_meta_data) values
  ('bc000000-0000-0000-0000-000000000001', 'vp-president@example.test', '{"name":"VP President"}'),
  ('bc000000-0000-0000-0000-000000000002', 'vp-tech@example.test', '{"name":"VP Tech"}'),
  ('bc000000-0000-0000-0000-000000000003', 'vp-volunteer@example.test', '{"name":"VP Volunteer"}'),
  ('bc000000-0000-0000-0000-000000000004', 'vp-devotee@example.test', '{"name":"VP Devotee"}');

update public.users
set role_id = (select roles.id from public.roles where roles.name = 'president')
where email = 'vp-president@example.test';
update public.users
set role_id = (select roles.id from public.roles where roles.name = 'tech')
where email = 'vp-tech@example.test';
update public.users
set role_id = (select roles.id from public.roles where roles.name = 'volunteer')
where email = 'vp-volunteer@example.test';
update public.users
set role_id = (select roles.id from public.roles where roles.name = 'devotee')
where email = 'vp-devotee@example.test';

-- The account creation trigger has already written devotee_joined rows. Nothing
-- below counts those, and clearing the table keeps every count in this script
-- about the calendar alone.
delete from public.app_notifications;

-- ---------------------------------------------------------------------------
-- 1. Every published 2026 parana row carries a real window.
--
--    The migration asserts this while it is being applied. It is asserted again
--    here, from the other side, because the migration's assertion cannot catch
--    a later migration that adds a parana row by hand or a trigger somebody
--    disables.
-- ---------------------------------------------------------------------------

do $$
declare
  v_total integer;
  v_parsed integer;
  v_bad text;
begin
  select count(*)::integer into v_total
  from public.vaisnava_calendar_events
  where calendar_year = 2026 and event_kind = 'parana';

  if v_total <> 24 then
    raise exception 'The published 2026 calendar has % parana rows rather than 24.', v_total;
  end if;

  select count(*)::integer into v_parsed
  from public.vaisnava_calendar_events
  where calendar_year = 2026
    and event_kind = 'parana'
    and parana_start_time is not null
    and parana_end_time is not null
    and parana_start_reason is not null
    and parana_end_reason is not null
    and parana_clock_marker in ('DST', 'LT');

  if v_parsed <> v_total then
    select string_agg(title, ' | ') into v_bad
    from public.vaisnava_calendar_events
    where calendar_year = 2026 and event_kind = 'parana'
      and (parana_start_time is null or parana_end_time is null
        or parana_start_reason is null or parana_end_reason is null
        or parana_clock_marker not in ('DST', 'LT'));
    raise exception 'Only % of % 2026 parana rows are complete. Incomplete: %',
      v_parsed, v_total, v_bad;
  end if;

  -- Every window runs forwards, and none of them is open-ended: 2026 publishes
  -- the ranged wording throughout.
  if exists (
    select 1 from public.vaisnava_calendar_events
    where calendar_year = 2026 and event_kind = 'parana'
      and (parana_end_time <= parana_start_time or parana_is_open_ended)
  ) then
    raise exception 'A 2026 parana row has a backwards or open-ended window.';
  end if;

  -- And nothing that is not a parana carries a window.
  if exists (
    select 1 from public.vaisnava_calendar_events
    where event_kind <> 'parana'
      and (parana_start_time is not null or parana_end_time is not null
        or parana_is_open_ended or parana_clock_marker is not null)
  ) then
    raise exception 'A non-parana row is carrying a break-fast window.';
  end if;
end;
$$;

-- One published row, read end to end, so the columns are not merely non-null.
do $$
declare
  v_row public.vaisnava_calendar_events;
begin
  select * into v_row
  from public.vaisnava_calendar_events
  where calendar_year = 2026 and event_date = date '2026-01-15' and event_kind = 'parana';

  if v_row.title <> 'Break fast 07:15 (sunrise) - 08:48 (end of tithi) LT' then
    raise exception 'The 15 January 2026 parana row is not the one this suite was written against: %', v_row.title;
  end if;
  if v_row.parana_start_time <> time '07:15' then
    raise exception 'It starts at % rather than 07:15.', v_row.parana_start_time;
  end if;
  if v_row.parana_end_time <> time '08:48' then
    raise exception 'It ends at % rather than 08:48.', v_row.parana_end_time;
  end if;
  if v_row.parana_start_reason <> 'sunrise' then
    raise exception 'Its start reason is % rather than sunrise.', v_row.parana_start_reason;
  end if;
  if v_row.parana_end_reason <> 'end of tithi' then
    raise exception 'Its end reason is % rather than end of tithi.', v_row.parana_end_reason;
  end if;
  if v_row.parana_clock_marker <> 'LT' then
    raise exception 'Its marker is % rather than LT.', v_row.parana_clock_marker;
  end if;
  if v_row.parana_is_open_ended then
    raise exception 'It is marked open-ended.';
  end if;

  if public.vaisnava_parana_phrase(
       v_row.parana_start_time, v_row.parana_end_time, v_row.parana_is_open_ended
     ) <> 'between 7:15 am and 8:48 am'
  then
    raise exception 'It reads as "%".', public.vaisnava_parana_phrase(
      v_row.parana_start_time, v_row.parana_end_time, v_row.parana_is_open_ended);
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Every wording the two published years contain, parsed by hand.
--
--    All seven shapes, including the open-ended one that appears once in 2027
--    and never in 2026, asserted through the parser directly so the suite does
--    not depend on which years happen to be seeded.
-- ---------------------------------------------------------------------------

do $$
declare
  v_case record;
  v_got record;
begin
  for v_case in
    select * from (values
      ('Break fast 07:15 (sunrise) - 08:48 (end of tithi) LT',
       time '07:15', 'sunrise', time '08:48', 'end of tithi', 'LT', false),
      ('Break fast 05:15 (sunrise) - 09:08 (end of tithi) DST',
       time '05:15', 'sunrise', time '09:08', 'end of tithi', 'DST', false),
      ('Break fast 06:11 (sunrise) - 10:38 (1/3 of daylight) DST',
       time '06:11', 'sunrise', time '10:38', '1/3 of daylight', 'DST', false),
      ('Break fast 07:14 (sunrise) - 10:17 (1/3 of daylight) LT',
       time '07:14', 'sunrise', time '10:17', '1/3 of daylight', 'LT', false),
      ('Break fast 10:16 (1/4 of tithi) - 10:46 (1/3 of daylight) DST',
       time '10:16', '1/4 of tithi', time '10:46', '1/3 of daylight', 'DST', false),
      ('Break fast 07:45 (1/4 of tithi) - 10:24 (1/3 of daylight) LT',
       time '07:45', '1/4 of tithi', time '10:24', '1/3 of daylight', 'LT', false),
      -- The open-ended one. A start, no end, and nothing invented for it.
      ('Break fast after 11:12 (1/4 of tithi) LT',
       time '11:12', '1/4 of tithi', null::time, null::text, 'LT', true)
    ) as shapes(title, st, sr, en, er, marker, open_ended)
  loop
    select * into v_got from public.parse_vaisnava_parana(v_case.title);

    if v_got.start_time is distinct from v_case.st then
      raise exception '% started at % rather than %.', v_case.title, v_got.start_time, v_case.st;
    end if;
    if v_got.start_reason is distinct from v_case.sr then
      raise exception '% opened for "%" rather than "%".', v_case.title, v_got.start_reason, v_case.sr;
    end if;
    if v_got.end_time is distinct from v_case.en then
      raise exception '% ended at % rather than %.', v_case.title, v_got.end_time, v_case.en;
    end if;
    if v_got.end_reason is distinct from v_case.er then
      raise exception '% closed for "%" rather than "%".', v_case.title, v_got.end_reason, v_case.er;
    end if;
    if v_got.clock_marker is distinct from v_case.marker then
      raise exception '% carried marker % rather than %.', v_case.title, v_got.clock_marker, v_case.marker;
    end if;
    if v_got.is_open_ended is distinct from v_case.open_ended then
      raise exception '% was read as open_ended=%.', v_case.title, v_got.is_open_ended;
    end if;
  end loop;

  -- Said again on its own, because it is the one shape that must NOT gain an
  -- end: a parser that helpfully filled in "one third of daylight" here would
  -- close a window the source left open.
  select * into v_got from public.parse_vaisnava_parana('Break fast after 11:12 (1/4 of tithi) LT');
  if v_got.end_time is not null or v_got.end_reason is not null then
    raise exception 'The open-ended wording was given an end of % (%).', v_got.end_time, v_got.end_reason;
  end if;
  if public.vaisnava_parana_phrase(v_got.start_time, v_got.end_time, v_got.is_open_ended)
     <> 'any time after 11:12 am'
  then
    raise exception 'The open-ended window reads as "%".',
      public.vaisnava_parana_phrase(v_got.start_time, v_got.end_time, v_got.is_open_ended);
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. An unknown wording loses its time, not the calendar.
-- ---------------------------------------------------------------------------

do $$
declare
  v_title text;
  v_got record;
begin
  foreach v_title in array array[
    'Break fast between 07:15 and 08:48',            -- a plausible future GCal
    'Break fast 07:15 to 08:48 (sunrise) DST',       -- nearly right, still no
    'Break fast 25:00 (sunrise) - 26:30 (x) DST',    -- not a time of day
    'Break fast 07:15 (sunrise) - 07:15 (x) LT',     -- a window of no width
    'Break fast 08:48 (sunrise) - 07:15 (x) LT',     -- backwards
    'Break fast',                                     -- truncated
    'Fasting for Sat-tila Ekadasi',                   -- not a parana at all
    ''
  ]
  loop
    v_got := null;
    begin
      select * into v_got from public.parse_vaisnava_parana(v_title);
    exception when others then
      raise exception 'Parsing "%" raised: %', v_title, sqlerrm;
    end;

    if v_got.start_time is not null or v_got.end_time is not null
      or v_got.start_reason is not null or v_got.end_reason is not null
      or v_got.clock_marker is not null or v_got.is_open_ended
    then
      raise exception 'The unknown wording "%" was given a time.', v_title;
    end if;
  end loop;

  -- Null is not a crash either.
  select * into v_got from public.parse_vaisnava_parana(null);
  if v_got.start_time is not null then
    raise exception 'A null title produced a time.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. The marker is kept, and it is not an instruction.
--
--    05:15 DST in June and 07:15 LT in January must both be read as the Chicago
--    wall clock they are printed in. The test is the UTC offset: a June morning
--    in Chicago is UTC-5 and a January morning is UTC-6, and any parser that
--    "applied" DST would put one of them an hour out.
-- ---------------------------------------------------------------------------

do $$
declare
  v_summer timestamptz;
  v_winter timestamptz;
begin
  select (event_date + parana_start_time) at time zone 'America/Chicago' into v_summer
  from public.vaisnava_calendar_events
  where event_date = date '2026-06-12' and event_kind = 'parana';

  select (event_date + parana_start_time) at time zone 'America/Chicago' into v_winter
  from public.vaisnava_calendar_events
  where event_date = date '2026-01-15' and event_kind = 'parana';

  if v_summer <> timestamptz '2026-06-12 05:15:00-05' then
    raise exception 'The 12 June window opens at % rather than 05:15 Chicago.', v_summer;
  end if;
  if v_winter <> timestamptz '2026-01-15 07:15:00-06' then
    raise exception 'The 15 January window opens at % rather than 07:15 Chicago.', v_winter;
  end if;

  -- And the markers are still on the rows.
  if (select parana_clock_marker from public.vaisnava_calendar_events
      where event_date = date '2026-06-12' and event_kind = 'parana') <> 'DST'
  then
    raise exception 'The 12 June row lost its DST marker.';
  end if;
  if (select parana_clock_marker from public.vaisnava_calendar_events
      where event_date = date '2026-01-15' and event_kind = 'parana') <> 'LT'
  then
    raise exception 'The 15 January row lost its LT marker.';
  end if;
end;
$$;

-- The same restraint, read off the published year rather than a fixture: the
-- 23rd of January 2026 carries seven events, six of them acarya days, and stays
-- quiet; and across the whole of 2026 the calendar speaks about 49 days out of
-- 127, not 127 out of 127.
do $$
declare
  v_notable integer;
  v_days integer;
begin
  if (select count(*) from public.vaisnava_reminder_text(date '2026-01-23', 'today')) <> 0 then
    raise exception 'The seven-event 23 January 2026 would have woken the congregation.';
  end if;

  select count(*)::integer into v_days
  from (select distinct event_date from public.vaisnava_calendar_events
        where calendar_year = 2026) as dated;

  select count(*)::integer into v_notable
  from (select distinct event_date from public.vaisnava_calendar_events
        where calendar_year = 2026) as dated
  where (select summary.is_notable from public.vaisnava_day_summary(dated.event_date) summary);

  if v_days <> 127 then
    raise exception 'The 2026 calendar covers % days rather than 127.', v_days;
  end if;
  if v_notable <> 49 then
    raise exception
      'The 2026 calendar would notify on % of its % days rather than 49. Restraint has changed; re-argue it.',
      v_notable, v_days;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. The fixture: five synthetic days around the Chicago today.
--
--    The published rows on those five days are removed first, so the counts
--    below are about this fixture and nothing else. All of it is rolled back.
-- ---------------------------------------------------------------------------

do $$
declare
  v_today date := (now() at time zone 'America/Chicago')::date;
  v_year integer;
begin
  for v_year in
    select distinct extract(year from d)::integer
    from generate_series(v_today - 2, v_today + 2, interval '1 day') as d
  loop
    insert into public.vaisnava_calendar_publications (
      calendar_year, city, time_zone, source_name, file_name, event_count
    ) values (
      v_year, 'Chicago, Illinois', 'America/Chicago',
      'verification fixture', 'verification.ics', 10
    )
    on conflict (calendar_year) do nothing;
  end loop;

  delete from public.vaisnava_calendar_events
  where event_date between v_today - 2 and v_today + 2;
end;
$$;

do $$
declare
  v_today date := (now() at time zone 'America/Chicago')::date;
  v_open_start time := time '00:01';
  v_open_end time := time '23:59';
begin
  insert into public.vaisnava_calendar_events (
    calendar_year, event_date, title, event_kind, source_uid, sort_order
  ) values
    -- T-2: notable only because of the parenthesised vow.
    (extract(year from v_today - 2)::integer, v_today - 2,
     'Sri Vow Acarya -- Appearance', 'appearance', 'vp-vow-1', 1),
    (extract(year from v_today - 2)::integer, v_today - 2,
     '(Fast till noon)', 'observance', 'vp-vow-2', 2),

    -- T-1: notable by nothing at all. The quiet day, and the past day.
    (extract(year from v_today - 1)::integer, v_today - 1,
     'Sri Quiet Acarya -- Disappearance', 'disappearance', 'vp-quiet-1', 1),
    (extract(year from v_today - 1)::integer, v_today - 1,
     'Sri Second Quiet Acarya -- Appearance', 'appearance', 'vp-quiet-2', 2),
    (extract(year from v_today - 1)::integer, v_today - 1,
     'Some Quiet Observance', 'observance', 'vp-quiet-3', 3),

    -- T: four headline observances, one vow note, one open parana window.
    (extract(year from v_today)::integer, v_today,
     'Sri Test Mahotsava', 'festival', 'vp-today-1', 1),
    (extract(year from v_today)::integer, v_today,
     'Sri Test Purnima', 'observance', 'vp-today-2', 2),
    (extract(year from v_today)::integer, v_today,
     'Sri Testa Thakura -- Disappearance', 'disappearance', 'vp-today-3', 3),
    (extract(year from v_today)::integer, v_today,
     'Test Yatra begins', 'observance', 'vp-today-4', 4),
    (extract(year from v_today)::integer, v_today,
     '(Fast till noon)', 'observance', 'vp-today-5', 5),
    (extract(year from v_today)::integer, v_today,
     'Break fast ' || to_char(v_open_start, 'HH24:MI') || ' (sunrise) - '
       || to_char(v_open_end, 'HH24:MI') || ' (1/3 of daylight) DST',
     'parana', 'vp-today-6', 6),

    -- T+1: one festival, for the evening-before notice.
    (extract(year from v_today + 1)::integer, v_today + 1,
     'Sri Tomorrow Yatra', 'festival', 'vp-tomorrow-1', 1),

    -- T+2: notable only by kind.
    (extract(year from v_today + 2)::integer, v_today + 2,
     'Fasting for Test Ekadasi', 'fasting', 'vp-kind-1', 1);
end;
$$;

-- The trigger parsed the fixture's parana row on the way in, with no help from
-- the import RPC and no backfill.
do $$
declare
  v_row public.vaisnava_calendar_events;
begin
  select * into v_row from public.vaisnava_calendar_events
  where source_uid = 'vp-today-6';

  if v_row.parana_start_time <> time '00:01' or v_row.parana_end_time <> time '23:59' then
    raise exception 'The trigger read the fixture window as % - %.',
      v_row.parana_start_time, v_row.parana_end_time;
  end if;
  if v_row.parana_start_reason <> 'sunrise' or v_row.parana_end_reason <> '1/3 of daylight' then
    raise exception 'The trigger lost the fixture reasons.';
  end if;
end;
$$;

-- And it clears them again if a row stops being a parana, so a corrected kind
-- can never leave a window stranded on an ordinary observance.
do $$
declare
  v_start time;
begin
  update public.vaisnava_calendar_events
  set event_kind = 'observance'
  where source_uid = 'vp-today-6';

  select parana_start_time into v_start
  from public.vaisnava_calendar_events where source_uid = 'vp-today-6';
  if v_start is not null then
    raise exception 'A row that stopped being a parana kept its window.';
  end if;

  update public.vaisnava_calendar_events
  set event_kind = 'parana'
  where source_uid = 'vp-today-6';

  select parana_start_time into v_start
  from public.vaisnava_calendar_events where source_uid = 'vp-today-6';
  if v_start <> time '00:01' then
    raise exception 'A row that became a parana again did not get its window back.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. The quiet day earns nothing, and the two notable days earn it for
--    different reasons.
-- ---------------------------------------------------------------------------

do $$
declare
  v_today date := (now() at time zone 'America/Chicago')::date;
  v_count integer;
  v_day record;
begin
  -- T-1: three real events, none of them a reason to wake anybody.
  select count(*)::integer into v_count
  from public.vaisnava_reminder_text(v_today - 1, 'today');
  if v_count <> 0 then
    raise exception 'The quiet day produced % lines of wording.', v_count;
  end if;

  select * into v_day from public.vaisnava_day_summary(v_today - 1);
  if v_day.is_notable then
    raise exception 'The quiet day is marked notable.';
  end if;
  if v_day.named_count <> 3 then
    raise exception 'The quiet day has % named events rather than 3.', v_day.named_count;
  end if;

  -- T-2: notable only because "(Fast till noon)" hangs underneath it. Its kinds
  -- are appearance and observance, neither of which is in notable_kinds.
  select * into v_day from public.vaisnava_day_summary(v_today - 2);
  if not v_day.is_notable then
    raise exception 'A day carrying a vow note was treated as quiet.';
  end if;
  if v_day.fasting_note is distinct from 'Fast till noon.' then
    raise exception 'The vow day''s instruction reads "%".', v_day.fasting_note;
  end if;
  if v_day.named_count <> 1 then
    raise exception 'The vow note was counted as an observance in its own right.';
  end if;

  -- T+2: notable only by kind, with no note anywhere.
  select * into v_day from public.vaisnava_day_summary(v_today + 2);
  if not v_day.is_notable then
    raise exception 'An Ekadasi fast was treated as quiet.';
  end if;
  if v_day.fasting_note is not null then
    raise exception 'The kind day invented an instruction: %', v_day.fasting_note;
  end if;
  if not v_day.has_fast then
    raise exception 'The kind day is not marked as a fast day.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Four events, one notification, worded as a notice.
-- ---------------------------------------------------------------------------

do $$
declare
  v_today date := (now() at time zone 'America/Chicago')::date;
  v_words record;
begin
  select * into v_words from public.vaisnava_reminder_text(v_today, 'today');

  if v_words.title <> 'Today is Sri Test Mahotsava' then
    raise exception 'The four-event day is titled "%".', v_words.title;
  end if;

  -- Priority, not sort order: the festival leads, the acarya follows, and the
  -- two ordinary observances come last in the order the calendar listed them.
  if v_words.body <> 'Four observances fall today: Sri Test Mahotsava, '
    || 'the disappearance day of Sri Testa Thakura, Sri Test Purnima and '
    || 'Test Yatra begins. Fast till noon.'
  then
    raise exception 'The four-event day reads: %', v_words.body;
  end if;

  -- And the evening before says the same thing about tomorrow.
  select * into v_words from public.vaisnava_reminder_text(v_today, 'tomorrow');
  if v_words.body not like 'Four observances fall tomorrow: %' then
    raise exception 'The evening-before wording reads: %', v_words.body;
  end if;
end;
$$;

-- One observance takes the other sentence, and a fast day is told when the fast
-- ends -- read off the published year, so this is the wording the temple will
-- really send.
do $$
declare
  v_words record;
begin
  select * into v_words from public.vaisnava_reminder_text(date '2026-03-03', 'today');
  if v_words.title <> 'Today is Gaura Purnima: Appearance of Sri Caitanya Mahaprabhu'
    or v_words.body <> 'Today is Gaura Purnima: Appearance of Sri Caitanya Mahaprabhu. Fast till moonrise.'
  then
    raise exception 'Gaura Purnima reads: % / %', v_words.title, v_words.body;
  end if;

  select * into v_words from public.vaisnava_reminder_text(date '2026-02-12', 'today');
  if v_words.body <> 'Today is Vijaya Ekadasi. Devotees fast today. '
    || 'The fast is broken tomorrow between 9:22 am and 10:19 am.'
  then
    raise exception 'Vijaya Ekadasi reads: %', v_words.body;
  end if;

  -- The evening before is deliberately shorter: no break-fast time, because on
  -- the eve you are planning the fast, not ending it.
  select * into v_words from public.vaisnava_reminder_text(date '2026-02-12', 'tomorrow');
  if v_words.body <> 'Tomorrow is Vijaya Ekadasi. Devotees fast tomorrow.' then
    raise exception 'The eve of Vijaya Ekadasi reads: %', v_words.body;
  end if;

  -- A database row becomes a sentence: "--" becomes "the appearance day of",
  -- an editor's bracketed note is dropped, and internal full stops become
  -- commas so one title cannot end the sentence three times.
  if public.vaisnava_event_phrase('Srila Prabhupada -- Appearance')
     <> 'the appearance day of Srila Prabhupada' then
    raise exception 'Prabhupada''s appearance reads "%".',
      public.vaisnava_event_phrase('Srila Prabhupada -- Appearance');
  end if;
  if public.vaisnava_event_phrase('Second month of Caturmasya begins [PURNIMA SYSTEM]')
     <> 'Second month of Caturmasya begins' then
    raise exception 'The bracketed editor note survived.';
  end if;
  if public.vaisnava_event_phrase('Go Puja. Go Krda. Govardhana Puja.')
     <> 'Go Puja, Go Krda, Govardhana Puja' then
    raise exception 'Govardhana Puja reads "%".',
      public.vaisnava_event_phrase('Go Puja. Go Krda. Govardhana Puja.');
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. The jobs: one notification each, to everybody, once.
-- ---------------------------------------------------------------------------

-- Point every dial at the hour this transaction is running in, so the jobs fire.
update public.app_settings
set value = extract(hour from (now() at time zone 'America/Chicago'))::integer::text
where key in (
  'vaisnava_calendar.today_hour',
  'vaisnava_calendar.tomorrow_hour',
  'vaisnava_calendar.parana_hour'
);

do $$
declare
  v_today date := (now() at time zone 'America/Chicago')::date;
  v_people integer := (select count(*)::integer from public.users);
  v_sent integer;
  v_again integer;
  v_rows integer;
  v_bodies integer;
begin
  if v_people <> 4 then
    raise exception 'This suite expected 4 devotees and found %.', v_people;
  end if;

  v_sent := public.send_vaisnava_today_reminder();
  if v_sent <> v_people then
    raise exception 'The today job reached % devotees rather than %.', v_sent, v_people;
  end if;

  -- One notification for a four-event day, not four.
  select count(*)::integer, count(distinct body)::integer into v_rows, v_bodies
  from public.app_notifications where kind = 'vaisnava_today';
  if v_rows <> v_people then
    raise exception 'A four-event day produced % notifications for % devotees.', v_rows, v_people;
  end if;
  if v_bodies <> 1 then
    raise exception 'The congregation was sent % different sentences about one day.', v_bodies;
  end if;

  -- Everybody, and nobody twice.
  if exists (
    select 1 from public.users
    where not exists (
      select 1 from public.app_notifications
      where app_notifications.kind = 'vaisnava_today'
        and app_notifications.user_id = users.id
    )
  ) then
    raise exception 'A devotee was left out of the temple''s calendar notice.';
  end if;

  -- Run it again, the way a retry or a hand-run would.
  v_again := public.send_vaisnava_today_reminder();
  if v_again <> 0 then
    raise exception 'Running the today job twice sent % more notifications.', v_again;
  end if;
  select count(*)::integer into v_rows
  from public.app_notifications where kind = 'vaisnava_today';
  if v_rows <> v_people then
    raise exception 'The second run left % notifications rather than %.', v_rows, v_people;
  end if;

  -- Exactly one claim, for today, and none for any other day.
  select count(*)::integer into v_rows
  from public.vaisnava_calendar_reminders_sent where reminder_kind = 'vaisnava_today';
  if v_rows <> 1 then
    raise exception 'The today job claimed % days.', v_rows;
  end if;
  if not exists (
    select 1 from public.vaisnava_calendar_reminders_sent
    where reminder_kind = 'vaisnava_today'
      and event_date = v_today
      and recipient_count = v_people
  ) then
    raise exception 'The today claim is not for today, or did not record its reach.';
  end if;
end;
$$;

do $$
declare
  v_today date := (now() at time zone 'America/Chicago')::date;
  v_people integer := (select count(*)::integer from public.users);
  v_sent integer;
  v_body text;
begin
  v_sent := public.send_vaisnava_tomorrow_reminder();
  if v_sent <> v_people then
    raise exception 'The tomorrow job reached % devotees rather than %.', v_sent, v_people;
  end if;
  if public.send_vaisnava_tomorrow_reminder() <> 0 then
    raise exception 'Running the tomorrow job twice notified twice.';
  end if;

  select distinct body into v_body
  from public.app_notifications where kind = 'vaisnava_tomorrow';
  if v_body <> 'Tomorrow is Sri Tomorrow Yatra.' then
    raise exception 'The evening-before notice reads: %', v_body;
  end if;

  -- It claimed tomorrow, never a day that has gone.
  if not exists (
    select 1 from public.vaisnava_calendar_reminders_sent
    where reminder_kind = 'vaisnava_tomorrow' and event_date = v_today + 1
  ) then
    raise exception 'The tomorrow job did not claim tomorrow.';
  end if;

  v_sent := public.send_vaisnava_parana_reminder();
  if v_sent <> v_people then
    raise exception 'The parana job reached % devotees rather than %.', v_sent, v_people;
  end if;
  if public.send_vaisnava_parana_reminder() <> 0 then
    raise exception 'Running the parana job twice notified twice.';
  end if;

  select distinct body into v_body
  from public.app_notifications where kind = 'vaisnava_parana';
  if v_body not like '%between 12:01 am and 11:59 pm%' then
    raise exception 'The parana notice reads: %', v_body;
  end if;

  -- Three notices in total on a day that carried six calendar rows.
  if (select count(distinct kind) from public.app_notifications) <> 3 then
    raise exception 'The congregation received % kinds of calendar notice.',
      (select count(distinct kind) from public.app_notifications);
  end if;
  if (select count(*) from public.app_notifications) <> 3 * v_people then
    raise exception 'The congregation received % notifications rather than %.',
      (select count(*) from public.app_notifications), 3 * v_people;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 9. Nothing about a day that has gone, a window that has closed, or a time
--    that could not be read.
-- ---------------------------------------------------------------------------

do $$
declare
  v_today date := (now() at time zone 'America/Chicago')::date;
  v_before integer;
begin
  -- T-2 is notable and T-1 has three events. Neither is ever claimed, because
  -- both jobs derive their date from the Chicago clock rather than from a scan.
  if exists (
    select 1 from public.vaisnava_calendar_reminders_sent
    where event_date < v_today
  ) then
    raise exception 'A day that has already gone was notified about.';
  end if;

  -- A parana on a past day is not "the next parana" and is not announced.
  delete from public.vaisnava_calendar_reminders_sent where reminder_kind = 'vaisnava_parana';
  update public.vaisnava_calendar_events
  set event_date = v_today - 1, calendar_year = extract(year from v_today - 1)::integer
  where source_uid = 'vp-today-6';

  v_before := (select count(*)::integer from public.app_notifications);
  if public.send_vaisnava_parana_reminder() <> 0 then
    raise exception 'Yesterday''s parana was announced this morning.';
  end if;
  if (select count(*)::integer from public.app_notifications) <> v_before then
    raise exception 'The parana job wrote notifications while returning zero.';
  end if;

  -- A window that closed earlier today is not announced either.
  update public.vaisnava_calendar_events
  set event_date = v_today,
      calendar_year = extract(year from v_today)::integer,
      title = 'Break fast 00:01 (sunrise) - 00:02 (end of tithi) DST'
  where source_uid = 'vp-today-6';

  if public.send_vaisnava_parana_reminder() <> 0 then
    raise exception 'A window that closed at two minutes past midnight was announced.';
  end if;

  -- Nor is one whose time could not be read: there is no honest sentence.
  update public.vaisnava_calendar_events
  set title = 'Break fast sometime after the morning programme'
  where source_uid = 'vp-today-6';

  if (select parana_start_time from public.vaisnava_calendar_events
      where source_uid = 'vp-today-6') is not null then
    raise exception 'An unreadable parana title was given a time.';
  end if;
  if public.send_vaisnava_parana_reminder() <> 0 then
    raise exception 'A parana with no readable time was announced anyway.';
  end if;
  if (select count(*)::integer from public.app_notifications) <> v_before then
    raise exception 'The parana job notified about a row it could not read.';
  end if;

  -- Put the fixture back the way section 5 built it.
  update public.vaisnava_calendar_events
  set title = 'Break fast 00:01 (sunrise) - 23:59 (1/3 of daylight) DST'
  where source_uid = 'vp-today-6';
  delete from public.vaisnava_calendar_reminders_sent where reminder_kind = 'vaisnava_parana';
end;
$$;

-- ---------------------------------------------------------------------------
-- 10. The hours are dials, read at every tick.
-- ---------------------------------------------------------------------------

do $$
declare
  v_hour integer := extract(hour from (now() at time zone 'America/Chicago'))::integer;
  v_other text := ((v_hour + 5) % 24)::text;
begin
  delete from public.vaisnava_calendar_reminders_sent;
  delete from public.app_notifications;

  update public.app_settings set value = v_other
  where key in (
    'vaisnava_calendar.today_hour',
    'vaisnava_calendar.tomorrow_hour',
    'vaisnava_calendar.parana_hour'
  );

  if public.send_vaisnava_today_reminder() <> 0
    or public.send_vaisnava_tomorrow_reminder() <> 0
    or public.send_vaisnava_parana_reminder() <> 0
  then
    raise exception 'A job ran outside the hour app_settings gives it.';
  end if;
  if (select count(*) from public.app_notifications) <> 0 then
    raise exception 'A job queued notifications outside its hour.';
  end if;
  if (select count(*) from public.vaisnava_calendar_reminders_sent) <> 0 then
    raise exception 'A job claimed a day outside its hour, blocking the real run.';
  end if;

  -- Moved back, and they fire. The dial is live: no redeploy, no re-schedule.
  update public.app_settings set value = v_hour::text
  where key in (
    'vaisnava_calendar.today_hour',
    'vaisnava_calendar.tomorrow_hour',
    'vaisnava_calendar.parana_hour'
  );
  if public.send_vaisnava_today_reminder() = 0 then
    raise exception 'The today job did not fire on the hour it was dialled to.';
  end if;
end;
$$;

-- A missing or malformed dial raises rather than falling back to a default.
do $$
declare
  v_raised boolean;
  v_case text;
begin
  foreach v_case in array array['delete', 'text', 'range']
  loop
    v_raised := false;
    begin
      if v_case = 'delete' then
        delete from public.app_settings where key = 'vaisnava_calendar.today_hour';
      elsif v_case = 'text' then
        update public.app_settings set value = 'morning'
        where key = 'vaisnava_calendar.today_hour';
      else
        update public.app_settings set value = '31'
        where key = 'vaisnava_calendar.today_hour';
      end if;

      perform public.send_vaisnava_today_reminder();
      raise exception using errcode = 'PT700', message = 'no complaint';
    exception
      when sqlstate 'PT700' then v_raised := false;
      when others then v_raised := true;
    end;

    if not v_raised then
      raise exception 'A % today_hour dial was quietly ignored.', v_case;
    end if;
  end loop;

  -- Restored, because the block above rolled nothing back.
  insert into public.app_settings (key, value)
  values ('vaisnava_calendar.today_hour',
          extract(hour from (now() at time zone 'America/Chicago'))::integer::text)
  on conflict (key) do update set value = excluded.value;
end;
$$;

-- ---------------------------------------------------------------------------
-- 11. What the app reads, and who may read it.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'bc000000-0000-0000-0000-000000000004', true);
set local role authenticated;

do $$
declare
  v_today date := (now() at time zone 'America/Chicago')::date;
  v_rows integer;
  v_row record;
  v_parana record;
begin
  -- The lowest access level in the temple. Every signed-in devotee may read the
  -- calendar; this is the one who proves it.
  select count(*)::integer into v_rows from public.vaisnava_calendar_outlook();
  if v_rows <> 2 then
    raise exception 'The outlook returned % rows rather than today and tomorrow.', v_rows;
  end if;

  select * into v_row from public.vaisnava_calendar_outlook() where scope = 'today';
  if v_row.event_date <> v_today then
    raise exception 'The outlook''s today is %.', v_row.event_date;
  end if;
  if not v_row.is_notable then
    raise exception 'The four-event day is not marked notable to the app.';
  end if;
  if v_row.headline <> 'Today is Sri Test Mahotsava' then
    raise exception 'The card headline is "%" and the push says something else.', v_row.headline;
  end if;
  if v_row.summary not like 'Four observances fall today: %' then
    raise exception 'The card summary is "%".', v_row.summary;
  end if;
  if v_row.fasting_note <> 'Fast till noon.' then
    raise exception 'The card lost the fasting instruction.';
  end if;
  if v_row.event_count <> 6 then
    raise exception 'The card was handed % events rather than all 6.', v_row.event_count;
  end if;
  if jsonb_array_length(v_row.events) <> 6 then
    raise exception 'The card''s event array has % entries.', jsonb_array_length(v_row.events);
  end if;
  -- The parana row arrives with a real window on it, not a sentence.
  if not exists (
    select 1 from jsonb_array_elements(v_row.events) as event
    where event->>'kind' = 'parana'
      and event->>'paranaStartTime' = '00:01:00'
      and event->>'paranaWindow' = 'between 12:01 am and 11:59 pm'
      and (event->>'paranaStartsAt') is not null
  ) then
    raise exception 'The card''s parana event is missing its structured window.';
  end if;

  select * into v_row from public.vaisnava_calendar_outlook() where scope = 'tomorrow';
  if v_row.event_date <> v_today + 1 or v_row.headline <> 'Tomorrow is Sri Tomorrow Yatra' then
    raise exception 'The outlook''s tomorrow is % / %.', v_row.event_date, v_row.headline;
  end if;

  -- The next parana, in Chicago time, open right now.
  select * into v_parana from public.next_vaisnava_parana();
  if v_parana.event_date <> v_today then
    raise exception 'The next parana is on % rather than today.', v_parana.event_date;
  end if;
  if v_parana.start_time <> time '00:01' or v_parana.end_time <> time '23:59' then
    raise exception 'The next parana runs % to %.', v_parana.start_time, v_parana.end_time;
  end if;
  if v_parana.starts_at <> (v_today + time '00:01') at time zone 'America/Chicago' then
    raise exception 'The next parana starts at % in the wrong zone.', v_parana.starts_at;
  end if;
  if not v_parana.is_open_now then
    raise exception 'A window running from one minute past midnight to one minute to midnight is closed.';
  end if;
  if v_parana.window_phrase <> 'between 12:01 am and 11:59 pm' then
    raise exception 'The next parana reads "%".', v_parana.window_phrase;
  end if;
  if v_parana.clock_marker <> 'DST' or v_parana.start_reason <> 'sunrise' then
    raise exception 'The next parana lost its marker or its reason.';
  end if;
end;
$$;

reset role;

-- A quiet day still draws a card; it simply carries no wording, because the
-- calendar screen shows everything and the lock screen shows almost nothing.
do $$
declare
  v_today date := (now() at time zone 'America/Chicago')::date;
begin
  delete from public.vaisnava_calendar_events where event_date = v_today;

  perform set_config('request.jwt.claim.sub', 'bc000000-0000-0000-0000-000000000004', true);
  set local role authenticated;

  if exists (
    select 1 from public.vaisnava_calendar_outlook()
    where scope = 'today' and (is_notable or headline is not null or summary is not null)
  ) then
    reset role;
    raise exception 'An empty day was given a headline.';
  end if;

  reset role;
end;
$$;

reset role;

-- Nobody signed in reads nothing, and is not shown an error screen for it.
set local role authenticated;
select set_config('request.jwt.claim.sub', '', true);

do $$
declare
  v_rows integer;
begin
  select count(*)::integer into v_rows from public.vaisnava_calendar_outlook();
  if v_rows <> 0 then
    raise exception 'A signed-out session was handed % rows of calendar.', v_rows;
  end if;
  select count(*)::integer into v_rows from public.next_vaisnava_parana();
  if v_rows <> 0 then
    raise exception 'A signed-out session was handed a parana.';
  end if;
end;
$$;

reset role;

-- anon cannot reach either read at all.
set local role anon;

do $$
declare
  v_name text;
  v_refused boolean;
begin
  foreach v_name in array array['vaisnava_calendar_outlook', 'next_vaisnava_parana']
  loop
    v_refused := false;
    begin
      execute format('select * from public.%I()', v_name);
    exception when others then
      v_refused := true;
    end;
    if not v_refused then
      raise exception 'anon reached public.%().', v_name;
    end if;
  end loop;
end;
$$;

reset role;

-- ---------------------------------------------------------------------------
-- 12. No devotee runs the temple's jobs by hand -- not even the President.
-- ---------------------------------------------------------------------------

do $$
declare
  v_person text;
  v_job text;
  v_refused boolean;
begin
  foreach v_person in array array[
    'bc000000-0000-0000-0000-000000000001',
    'bc000000-0000-0000-0000-000000000002',
    'bc000000-0000-0000-0000-000000000004'
  ]
  loop
    foreach v_job in array array[
      'send_vaisnava_today_reminder',
      'send_vaisnava_tomorrow_reminder',
      'send_vaisnava_parana_reminder',
      'vaisnava_day_summary',
      'vaisnava_calendar_dial'
    ]
    loop
      perform set_config('request.jwt.claim.sub', v_person, true);
      set local role authenticated;

      v_refused := false;
      begin
        if v_job = 'vaisnava_day_summary' then
          execute 'select * from public.vaisnava_day_summary(current_date)';
        elsif v_job = 'vaisnava_calendar_dial' then
          execute 'select public.vaisnava_calendar_dial(''vaisnava_calendar.today_hour'')';
        else
          execute format('select public.%I()', v_job);
        end if;
      exception when others then
        v_refused := true;
      end;

      reset role;

      if not v_refused then
        raise exception 'A signed-in devotee (%) reached public.%().', v_person, v_job;
      end if;
    end loop;
  end loop;
end;
$$;

reset role;

-- ---------------------------------------------------------------------------
-- 13. Shapes, grants and the kind list.
--
--     Result columns are pinned in order, because a client reading by position
--     is silently handed the wrong field when one is inserted in the middle.
-- ---------------------------------------------------------------------------

do $$
declare
  v_result text;
  v_name text;
  v_count integer;
begin
  foreach v_name in array array[
    'parse_vaisnava_parana', 'apply_vaisnava_parana_times', 'vaisnava_calendar_dial',
    'vaisnava_calendar_hour', 'vaisnava_event_phrase', 'vaisnava_kind_rank',
    'vaisnava_parana_phrase', 'vaisnava_day_summary', 'vaisnava_reminder_text',
    'send_vaisnava_today_reminder', 'send_vaisnava_tomorrow_reminder',
    'send_vaisnava_parana_reminder', 'vaisnava_calendar_outlook', 'next_vaisnava_parana'
  ]
  loop
    select count(*)::integer into v_count
    from pg_proc
    join pg_namespace on pg_namespace.oid = pg_proc.pronamespace
    where pg_namespace.nspname = 'public' and pg_proc.proname = v_name;
    if v_count <> 1 then
      raise exception 'There are % versions of public.%.', v_count, v_name;
    end if;
  end loop;

  select pg_get_function_result(pg_proc.oid) into v_result
  from pg_proc join pg_namespace on pg_namespace.oid = pg_proc.pronamespace
  where pg_namespace.nspname = 'public' and pg_proc.proname = 'parse_vaisnava_parana';
  if v_result <> 'TABLE(start_time time without time zone, start_reason text, '
    || 'end_time time without time zone, end_reason text, clock_marker text, is_open_ended boolean)'
  then
    raise exception 'parse_vaisnava_parana returns %', v_result;
  end if;

  select pg_get_function_result(pg_proc.oid) into v_result
  from pg_proc join pg_namespace on pg_namespace.oid = pg_proc.pronamespace
  where pg_namespace.nspname = 'public' and pg_proc.proname = 'vaisnava_calendar_outlook';
  if v_result <> 'TABLE(scope text, event_date date, is_notable boolean, headline text, '
    || 'summary text, fasting_note text, event_count integer, events jsonb)'
  then
    raise exception 'vaisnava_calendar_outlook returns %', v_result;
  end if;

  select pg_get_function_result(pg_proc.oid) into v_result
  from pg_proc join pg_namespace on pg_namespace.oid = pg_proc.pronamespace
  where pg_namespace.nspname = 'public' and pg_proc.proname = 'next_vaisnava_parana';
  if v_result <> 'TABLE(event_id uuid, event_date date, title text, '
    || 'start_time time without time zone, end_time time without time zone, '
    || 'starts_at timestamp with time zone, ends_at timestamp with time zone, '
    || 'start_reason text, end_reason text, clock_marker text, is_open_ended boolean, '
    || 'is_open_now boolean, window_phrase text)'
  then
    raise exception 'next_vaisnava_parana returns %', v_result;
  end if;

  foreach v_name in array array[
    'send_vaisnava_today_reminder', 'send_vaisnava_tomorrow_reminder',
    'send_vaisnava_parana_reminder'
  ]
  loop
    select pg_get_function_result(pg_proc.oid) into v_result
    from pg_proc join pg_namespace on pg_namespace.oid = pg_proc.pronamespace
    where pg_namespace.nspname = 'public' and pg_proc.proname = v_name;
    if v_result <> 'integer' then
      raise exception 'public.% returns % rather than a count.', v_name, v_result;
    end if;
  end loop;

  -- 202608260074's import RPC is untouched: same name, same six arguments.
  select pg_get_function_identity_arguments(pg_proc.oid) into v_result
  from pg_proc join pg_namespace on pg_namespace.oid = pg_proc.pronamespace
  where pg_namespace.nspname = 'public' and pg_proc.proname = 'replace_vaisnava_calendar_year';
  if v_result <> 'p_year integer, p_source_name text, p_source_url text, '
    || 'p_file_name text, p_source_file_text text, p_events jsonb'
  then
    raise exception 'replace_vaisnava_calendar_year now takes (%).', v_result;
  end if;
end;
$$;

do $$
declare
  v_definition text;
  v_kind text;
begin
  select pg_get_constraintdef(pg_constraint.oid) into v_definition
  from pg_constraint
  where conname = 'app_notifications_kind_check'
    and conrelid = 'public.app_notifications'::regclass;

  -- The three this migration adds.
  foreach v_kind in array array['vaisnava_today', 'vaisnava_tomorrow', 'vaisnava_parana']
  loop
    if position('''' || v_kind || '''' in v_definition) = 0 then
      raise exception 'The kind % is not allowed by app_notifications_kind_check.', v_kind;
    end if;
  end loop;

  -- And a sample of everything that was already allowed, because this migration
  -- rewrites that constraint and a rewrite that drops a kind takes another
  -- feature down silently.
  foreach v_kind in array array[
    'service_open', 'birthday_today', 'announcement_posted', 'message_received',
    'sanga_message_received', 'seva_award_earned', 'sponsorship_fulfilled',
    'newsletter_posted', 'access_appointed', 'care_reply', 'remote'
  ]
  loop
    if position('''' || v_kind || '''' in v_definition) = 0 then
      raise exception 'This migration dropped the pre-existing kind % from the constraint.', v_kind;
    end if;
  end loop;
end;
$$;

-- The window shape and the marker are enforced by the table, not only by the
-- parser. The trigger normally makes a bad window unreachable -- it overwrites
-- whatever a caller supplied -- so the trigger is stood down here, which is the
-- only state in which the constraint is the thing being tested.
do $$
declare
  v_today date := (now() at time zone 'America/Chicago')::date;
  v_refused boolean;
begin
  alter table public.vaisnava_calendar_events
    disable trigger apply_vaisnava_parana_times;

  v_refused := false;
  begin
    insert into public.vaisnava_calendar_events (
      calendar_year, event_date, title, event_kind, source_uid,
      parana_start_time, parana_end_time
    ) values (
      extract(year from v_today)::integer, v_today, 'hand written', 'parana', 'vp-hand-1',
      time '09:00', time '08:00'
    );
  exception when others then v_refused := true;
  end;
  if not v_refused then
    raise exception 'A backwards break-fast window was accepted.';
  end if;

  v_refused := false;
  begin
    insert into public.vaisnava_calendar_events (
      calendar_year, event_date, title, event_kind, source_uid,
      parana_start_time, parana_end_time, parana_is_open_ended
    ) values (
      extract(year from v_today)::integer, v_today, 'hand written', 'parana', 'vp-hand-2',
      time '09:00', time '10:00', true
    );
  exception when others then v_refused := true;
  end;
  if not v_refused then
    raise exception 'A window that is both open-ended and closed was accepted.';
  end if;

  v_refused := false;
  begin
    insert into public.vaisnava_calendar_events (
      calendar_year, event_date, title, event_kind, source_uid, parana_clock_marker
    ) values (
      extract(year from v_today)::integer, v_today, 'hand written', 'observance', 'vp-hand-3', 'EST'
    );
  exception when others then v_refused := true;
  end;
  if not v_refused then
    raise exception 'A clock marker of EST was accepted.';
  end if;

  alter table public.vaisnava_calendar_events
    enable trigger apply_vaisnava_parana_times;
end;
$$;

-- ---------------------------------------------------------------------------
-- 14. Every guard, mutated.
--
--     Each row below breaks exactly one thing 0076 relies on and re-reads one
--     answer through the real function. A guard whose mutation changes nothing
--     is a guard that was not doing anything, and the table says so out loud.
--
--     Both readings roll back whatever they would have written -- vp_probe runs
--     its statement inside a subtransaction and then raises -- so a probe that
--     notifies the congregation does not leave the congregation notified, and
--     the same question can honestly be asked twice. The probe is read a third
--     time after the mutation is undone and must match the first, or the
--     harness itself is lying.
-- ---------------------------------------------------------------------------

-- The fixture is rebuilt, because sections 9 to 11 have been moving it about.
do $$
declare
  v_today date := (now() at time zone 'America/Chicago')::date;
begin
  delete from public.vaisnava_calendar_reminders_sent;
  delete from public.app_notifications;
  delete from public.vaisnava_calendar_events
  where event_date between v_today - 2 and v_today + 2;

  insert into public.vaisnava_calendar_events (
    calendar_year, event_date, title, event_kind, source_uid, sort_order
  ) values
    (extract(year from v_today - 2)::integer, v_today - 2,
     'Sri Vow Acarya -- Appearance', 'appearance', 'vp-vow-1', 1),
    (extract(year from v_today - 2)::integer, v_today - 2,
     '(Fast till noon)', 'observance', 'vp-vow-2', 2),
    (extract(year from v_today)::integer, v_today,
     'Sri Test Mahotsava', 'festival', 'vp-today-1', 1),
    (extract(year from v_today)::integer, v_today,
     'Sri Test Purnima', 'observance', 'vp-today-2', 2),
    (extract(year from v_today)::integer, v_today,
     'Sri Testa Thakura -- Disappearance', 'disappearance', 'vp-today-3', 3),
    (extract(year from v_today)::integer, v_today,
     'Test Yatra begins', 'observance', 'vp-today-4', 4),
    (extract(year from v_today)::integer, v_today,
     '(Fast till noon)', 'observance', 'vp-today-5', 5),
    (extract(year from v_today)::integer, v_today,
     'Break fast 00:01 (sunrise) - 23:59 (1/3 of daylight) DST',
     'parana', 'vp-today-6', 6),
    (extract(year from v_today + 1)::integer, v_today + 1,
     'Sri Tomorrow Yatra', 'festival', 'vp-tomorrow-1', 1),
    (extract(year from v_today + 2)::integer, v_today + 2,
     'Fasting for Test Ekadasi', 'fasting', 'vp-kind-1', 1);
end;
$$;

create table vp_mutations (
  n integer primary key,
  guard text not null,
  mutation text not null,
  probe text not null,
  intact text not null,
  mutated text not null,
  killed boolean not null
);

create function pg_temp.vp_probe(p_sql text)
returns text
language plpgsql
as $$
declare
  v_answer text;
begin
  begin
    execute p_sql into v_answer;
    raise exception using errcode = 'PT780', message = coalesce(v_answer, '(null)');
  exception when sqlstate 'PT780' then
    return sqlerrm;
  end;
end;
$$;

-- The table's own guards, tested with the trigger stood down: the trigger
-- normally rewrites these columns, so it is the only way to put a hand-written
-- value in front of the constraint. Everything here is inside vp_probe's
-- subtransaction, so the stand-down never outlives the probe.
create function pg_temp.vp_try_direct(p_sql text)
returns text
language plpgsql
as $$
declare
  v_answer text;
begin
  alter table public.vaisnava_calendar_events
    disable trigger apply_vaisnava_parana_times;
  begin
    execute p_sql;
    v_answer := 'accepted';
  exception when others then
    v_answer := 'refused';
  end;
  return v_answer;
end;
$$;

create function pg_temp.vp_mutate(
  p_n integer, p_guard text, p_mutation text, p_probe text,
  p_apply text, p_query text
)
returns void
language plpgsql
as $$
declare
  v_intact text;
  v_mutated text;
  v_restored text;
begin
  v_intact := pg_temp.vp_probe(p_query);

  begin
    execute p_apply;
    v_mutated := pg_temp.vp_probe(p_query);
    raise exception using errcode = 'PT781', message = v_mutated;
  exception when sqlstate 'PT781' then
    v_mutated := sqlerrm;
  end;

  v_restored := pg_temp.vp_probe(p_query);
  if v_restored is distinct from v_intact then
    raise exception 'Mutation % did not roll back: the probe read % before and % after.',
      p_n, v_intact, v_restored;
  end if;

  insert into vp_mutations (n, guard, mutation, probe, intact, mutated, killed)
  values (p_n, p_guard, p_mutation, p_probe, v_intact, v_mutated,
          v_mutated is distinct from v_intact);
end;
$$;

do $$
declare
  v_today date := (now() at time zone 'America/Chicago')::date;
  v_hour integer := extract(hour from (now() at time zone 'America/Chicago'))::integer;
  v_other text := ((v_hour + 5) % 24)::text;
begin
  perform pg_temp.vp_mutate(
    1,
    'the today job runs only in its own Chicago hour',
    'today_hour dialled five hours away',
    'devotees reached by send_vaisnava_today_reminder()',
    format('update public.app_settings set value = %L where key = %L',
           v_other, 'vaisnava_calendar.today_hour'),
    'select public.send_vaisnava_today_reminder()::text');

  perform pg_temp.vp_mutate(
    2,
    'the tomorrow job runs only in its own Chicago hour',
    'tomorrow_hour dialled five hours away',
    'devotees reached by send_vaisnava_tomorrow_reminder()',
    format('update public.app_settings set value = %L where key = %L',
           v_other, 'vaisnava_calendar.tomorrow_hour'),
    'select public.send_vaisnava_tomorrow_reminder()::text');

  perform pg_temp.vp_mutate(
    3,
    'the parana job runs only in its own Chicago hour',
    'parana_hour dialled five hours away',
    'devotees reached by send_vaisnava_parana_reminder()',
    format('update public.app_settings set value = %L where key = %L',
           v_other, 'vaisnava_calendar.parana_hour'),
    'select public.send_vaisnava_parana_reminder()::text');

  perform pg_temp.vp_mutate(
    4,
    'a day is claimed once, by primary key, before anything is sent',
    'today already claimed in vaisnava_calendar_reminders_sent',
    'devotees reached by send_vaisnava_today_reminder()',
    format('insert into public.vaisnava_calendar_reminders_sent '
           || '(reminder_kind, event_date) values (%L, %L)',
           'vaisnava_today', v_today),
    'select public.send_vaisnava_today_reminder()::text');

  perform pg_temp.vp_mutate(
    5,
    'a parana whose window has closed is never announced',
    'today''s window moved to 00:01-00:02',
    'devotees reached by send_vaisnava_parana_reminder()',
    format('update public.vaisnava_calendar_events set title = %L where source_uid = %L',
           'Break fast 00:01 (sunrise) - 00:02 (end of tithi) DST', 'vp-today-6'),
    'select public.send_vaisnava_parana_reminder()::text');

  perform pg_temp.vp_mutate(
    6,
    'a parana whose time could not be read is never announced',
    'today''s parana retitled in an unknown wording',
    'devotees reached by send_vaisnava_parana_reminder()',
    format('update public.vaisnava_calendar_events set title = %L where source_uid = %L',
           'Break fast sometime in the morning', 'vp-today-6'),
    'select public.send_vaisnava_parana_reminder()::text');

  perform pg_temp.vp_mutate(
    7,
    'the parana announced is today''s',
    'today''s parana moved back one day',
    'devotees reached by send_vaisnava_parana_reminder()',
    format('update public.vaisnava_calendar_events set event_date = %L, calendar_year = %s '
           || 'where source_uid = %L',
           v_today - 1, extract(year from v_today - 1)::integer, 'vp-today-6'),
    'select public.send_vaisnava_parana_reminder()::text');

  perform pg_temp.vp_mutate(
    8,
    'today means today in Chicago, never a day that has gone',
    'every event of today moved back one day',
    'devotees reached by send_vaisnava_today_reminder()',
    format('update public.vaisnava_calendar_events set event_date = event_date - 1, '
           || 'calendar_year = %s where event_date = %L',
           extract(year from v_today - 1)::integer, v_today),
    'select public.send_vaisnava_today_reminder()::text');

  perform pg_temp.vp_mutate(
    9,
    'a festival, a Mahadvadasi or an Ekadasi fast earns a notice',
    'notable_kinds emptied of all three',
    'the wording for an Ekadasi-fast-only day',
    format('update public.app_settings set value = %L where key = %L',
           'other', 'vaisnava_calendar.notable_kinds'),
    format('select coalesce((select words.title from public.vaisnava_reminder_text(%L, %L) words), ''(silent)'')',
           v_today + 2, 'today'));

  perform pg_temp.vp_mutate(
    10,
    'a parenthesised vow promotes a day the kinds alone would leave quiet',
    'vow_note_pattern set to match nothing',
    'the wording for a vow-note-only day',
    format('update public.app_settings set value = %L where key = %L',
           'zzzznothing', 'vaisnava_calendar.vow_note_pattern'),
    format('select coalesce((select words.title from public.vaisnava_reminder_text(%L, %L) words), ''(silent)'')',
           v_today - 2, 'today'));

  perform pg_temp.vp_mutate(
    11,
    'one sentence names at most max_named_events observances',
    'max_named_events dialled from 4 down to 2',
    'the body of the four-event day',
    format('update public.app_settings set value = %L where key = %L',
           '2', 'vaisnava_calendar.max_named_events'),
    format('select words.body from public.vaisnava_reminder_text(%L, %L) words',
           v_today, 'today'));

  perform pg_temp.vp_mutate(
    12,
    'the table refuses a backwards break-fast window',
    'vaisnava_parana_window_shape dropped',
    'a hand-written 09:00-08:00 window, trigger stood down',
    'alter table public.vaisnava_calendar_events drop constraint vaisnava_parana_window_shape',
    format('select pg_temp.vp_try_direct(%L)',
           format('insert into public.vaisnava_calendar_events '
             || '(calendar_year, event_date, title, event_kind, source_uid, '
             || 'parana_start_time, parana_end_time) values '
             || '(%s, %L, ''probe'', ''parana'', ''vp-probe-12'', ''09:00'', ''08:00'')',
             extract(year from v_today)::integer, v_today)));

  perform pg_temp.vp_mutate(
    13,
    'the table refuses a clock marker that is neither DST nor LT',
    'vaisnava_parana_clock_marker_check dropped',
    'a hand-written marker of EST, trigger stood down',
    'alter table public.vaisnava_calendar_events drop constraint vaisnava_parana_clock_marker_check',
    format('select pg_temp.vp_try_direct(%L)',
           format('insert into public.vaisnava_calendar_events '
             || '(calendar_year, event_date, title, event_kind, source_uid, parana_clock_marker) '
             || 'values (%s, %L, ''probe'', ''observance'', ''vp-probe-13'', ''EST'')',
             extract(year from v_today)::integer, v_today)));
end;
$$;

do $$
declare
  v_survivors text;
  v_count integer;
begin
  select count(*)::integer into v_count from vp_mutations;
  if v_count <> 13 then
    raise exception 'Only % mutations ran.', v_count;
  end if;

  select string_agg(vp_mutations.n || ': ' || vp_mutations.guard, E'\n  ')
  into v_survivors
  from vp_mutations where not vp_mutations.killed;

  if v_survivors is not null then
    raise exception E'These guards survived being broken:\n  %', v_survivors;
  end if;

  -- The probes did not leave the fixture notified or claimed.
  if (select count(*) from public.app_notifications) <> 0
    or (select count(*) from public.vaisnava_calendar_reminders_sent) <> 0
  then
    raise exception 'A mutation probe left the congregation notified; the harness is lying.';
  end if;
end;
$$;

select
  vp_mutations.n,
  vp_mutations.guard,
  vp_mutations.mutation,
  vp_mutations.probe,
  vp_mutations.intact,
  vp_mutations.mutated,
  case when vp_mutations.killed then 'killed' else 'SURVIVED' end as verdict
from vp_mutations
order by vp_mutations.n;

do $$
begin
  raise notice 'all vaisnava parana and reminder checks passed';
end;
$$;

select 'vaisnava parana and reminders verification passed' as result;

rollback;
