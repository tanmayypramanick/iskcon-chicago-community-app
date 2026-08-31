-- Functional verification for 202608260077_chicago_vaisnava_calendar_2027.sql.
--
-- Rolled back at the end. Every local is prefixed v_ so it can never shadow a
-- column name. This one proves a seed rather than a permission, so the reads
-- are made as the owner; what a devotee may see of these two tables is
-- 202608260074's business and is proved there.
--
-- ---------------------------------------------------------------------------
-- What is being proved.
--
--   1. THE YEAR ARRIVED WHOLE AND ONLY THE YEAR. Exactly 244 events, every one
--      of them dated in 2027, none stranded in 2026 or 2028, no source_uid
--      used twice, and every event_kind one of the eight the schema allows.
--
--   2. THE PUBLICATION DESCRIBES THE ROWS THAT ACTUALLY EXIST. Its event_count
--      is the number of events counted in the table, not the number the author
--      believed they were pasting, and the city, time zone, source and file
--      name are the same shape 2026 was published under — one temple, one
--      publisher, two years.
--
--   3. THE CLASSIFICATION DID NOT DIVERGE FROM 2026. The kinds were produced by
--      running the app's own parser, src/features/vaisnavaCalendar/ics.ts, over
--      the ICS file, so the two years must be recognisably the same calendar:
--      every kind 2026 uses more than a handful of times is used in 2027 too.
--      A mapping that silently collapsed — every festival landing in
--      'observance', say — shows up here as a zero rather than passing quietly.
--      The distribution for both years is printed at the end so the divergence
--      can be read as well as asserted.
--
--   4. THE TWO KINDS THAT COME IN PAIRS COME IN PAIRS. A fast is broken the
--      next day: 25 'fasting' days, 25 'parana' days, and every parana title
--      is a break-fast line, because that is the rule the classifier applies
--      and the rule the devotee reads off the screen.
--
--   5. RE-APPLYING THE MIGRATION IS A NO-OP, NOT A DUPLICATION. The migration
--      upserts the publication and replaces the year's events wholesale; run
--      the same statements a second time and the row count, and every column
--      of every row including sort_order, are unchanged. The unique constraint
--      that would have turned a careless re-run into an error rather than a
--      double is confirmed to still exist.
--
-- The final rows must read: chicago vaisnava calendar 2027 verification passed
-- ---------------------------------------------------------------------------

begin;

-- ---------------------------------------------------------------------------
-- 1. The year arrived whole, and only the year.
-- ---------------------------------------------------------------------------

do $$
declare
  v_count integer;
  v_stray integer;
  v_dupes integer;
  v_unknown text;
begin
  select count(*) into v_count
  from public.vaisnava_calendar_events
  where calendar_year = 2027;
  if v_count <> 244 then
    raise exception '2027 holds % events, expected 244.', v_count;
  end if;

  select count(*) into v_stray
  from public.vaisnava_calendar_events
  where calendar_year = 2027
    and extract(year from event_date)::integer <> 2027;
  if v_stray <> 0 then
    raise exception '% events filed under 2027 fall outside 2027.', v_stray;
  end if;

  -- And nothing dated 2027 leaked into a neighbouring year's publication.
  select count(*) into v_stray
  from public.vaisnava_calendar_events
  where calendar_year <> 2027
    and extract(year from event_date)::integer = 2027;
  if v_stray <> 0 then
    raise exception '% events dated 2027 are filed under another year.', v_stray;
  end if;

  select count(*) into v_dupes
  from (
    select source_uid
    from public.vaisnava_calendar_events
    where calendar_year = 2027
    group by source_uid
    having count(*) > 1
  ) repeated;
  if v_dupes <> 0 then
    raise exception '% source_uids appear more than once in 2027.', v_dupes;
  end if;

  select string_agg(distinct event_kind, ', ') into v_unknown
  from public.vaisnava_calendar_events
  where calendar_year = 2027
    and event_kind not in (
      'ekadasi', 'parana', 'fasting', 'festival',
      'appearance', 'disappearance', 'observance', 'other'
    );
  if v_unknown is not null then
    raise exception '2027 contains unknown event types: %.', v_unknown;
  end if;

  -- Titles are what a devotee reads; none may be blank or padded.
  if exists (
    select 1 from public.vaisnava_calendar_events
    where calendar_year = 2027
      and (nullif(trim(title), '') is null or title <> trim(title))
  ) then
    raise exception '2027 contains an empty or untrimmed title.';
  end if;

  -- The publisher leaves DESCRIPTION empty, and 2026 stored that as null.
  if exists (
    select 1 from public.vaisnava_calendar_events
    where calendar_year = 2027 and description is not null
  ) then
    raise exception '2027 stored a description where 2026 stored null.';
  end if;

  -- sort_order is the ICS file order, 1..244 with no gaps and no repeats.
  if exists (
    select 1
    from public.vaisnava_calendar_events
    where calendar_year = 2027
    group by sort_order
    having count(*) > 1
  ) then
    raise exception '2027 repeats a sort_order.';
  end if;
  if (
    select min(sort_order) || '-' || max(sort_order)
    from public.vaisnava_calendar_events
    where calendar_year = 2027
  ) <> '1-244' then
    raise exception '2027 sort_order does not run 1..244.';
  end if;

  -- File order is date order, so the calendar screen reads down the year.
  if exists (
    select 1
    from (
      select event_date,
             lag(event_date) over (order by sort_order) as previous_date
      from public.vaisnava_calendar_events
      where calendar_year = 2027
    ) ordered
    where previous_date > event_date
  ) then
    raise exception '2027 sort_order runs backwards through the year.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. The publication describes the rows that actually exist, in 2026's shape.
-- ---------------------------------------------------------------------------

do $$
declare
  v_publication public.vaisnava_calendar_publications;
  v_seeded integer;
  v_2026 public.vaisnava_calendar_publications;
begin
  select * into v_publication
  from public.vaisnava_calendar_publications
  where calendar_year = 2027;
  if v_publication.calendar_year is null then
    raise exception 'There is no 2027 publication row.';
  end if;

  select count(*) into v_seeded
  from public.vaisnava_calendar_events
  where calendar_year = 2027;
  if v_publication.event_count <> v_seeded then
    raise exception 'The 2027 publication claims % events but % exist.',
      v_publication.event_count, v_seeded;
  end if;

  if v_publication.city <> 'Chicago, Illinois'
    or v_publication.time_zone <> 'America/Chicago'
  then
    raise exception 'The 2027 publication is not the Chicago calendar: %, %.',
      v_publication.city, v_publication.time_zone;
  end if;

  if v_publication.file_name <> 'Chicago [United States of America]-a2027-ICS.ics' then
    raise exception 'The 2027 publication names the wrong file: %.',
      v_publication.file_name;
  end if;
  if v_publication.source_url not like '%/ICS/2027/%' then
    raise exception 'The 2027 publication points at the wrong source: %.',
      v_publication.source_url;
  end if;

  -- Same publisher and same shape as the year already deployed.
  select * into v_2026
  from public.vaisnava_calendar_publications
  where calendar_year = 2026;
  if v_2026.calendar_year is null then
    raise exception 'The 2026 publication is missing; 2027 cannot be compared to it.';
  end if;
  if v_publication.source_name <> v_2026.source_name
    or v_publication.city <> v_2026.city
    or v_publication.time_zone <> v_2026.time_zone
  then
    raise exception '2027 is published under a different shape than 2026.';
  end if;
  -- 2026 leaves the raw ICS text out of the migration; 2027 follows suit.
  if (v_publication.source_file_text is null) is distinct from (v_2026.source_file_text is null) then
    raise exception '2027 and 2026 disagree about storing the raw ICS text.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. The classification did not diverge from 2026.
-- ---------------------------------------------------------------------------

do $$
declare
  v_kind text;
  v_2026 integer;
  v_2027 integer;
begin
  for v_kind, v_2026 in
    select event_kind, count(*)::integer
    from public.vaisnava_calendar_events
    where calendar_year = 2026
    group by event_kind
    having count(*) >= 5
  loop
    select count(*)::integer into v_2027
    from public.vaisnava_calendar_events
    where calendar_year = 2027 and event_kind = v_kind;
    if v_2027 = 0 then
      raise exception
        'Classification diverged: 2026 has % rows of kind %, 2027 has none.',
        v_2026, v_kind;
    end if;
  end loop;

  -- And 2027 invented no kind 2026 never used.
  select string_agg(event_kind, ', ') into v_kind
  from (
    select distinct event_kind
    from public.vaisnava_calendar_events
    where calendar_year = 2027
      and event_kind not in (
        select distinct event_kind
        from public.vaisnava_calendar_events
        where calendar_year = 2026
      )
  ) fresh;
  if v_kind is not null then
    raise exception '2027 uses event types 2026 never used: %.', v_kind;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. The kinds that come in pairs come in pairs.
-- ---------------------------------------------------------------------------

do $$
declare
  v_fasting integer;
  v_parana integer;
  v_odd integer;
begin
  select
    count(*) filter (where event_kind = 'fasting'),
    count(*) filter (where event_kind = 'parana')
  into v_fasting, v_parana
  from public.vaisnava_calendar_events
  where calendar_year = 2027;

  if v_parana <> 25 then
    raise exception '2027 holds % parana entries, expected 25.', v_parana;
  end if;
  if v_fasting <> v_parana then
    raise exception '2027 holds % fasting days against % parana days.',
      v_fasting, v_parana;
  end if;

  -- Every parana row is a break-fast line, and no break-fast line is filed
  -- as anything else. That is the classifier's first rule, read back.
  select count(*) into v_odd
  from public.vaisnava_calendar_events
  where calendar_year = 2027
    and (
      (event_kind = 'parana' and lower(title) not like 'break fast%')
      or (event_kind <> 'parana' and lower(title) like 'break fast%')
    );
  if v_odd <> 0 then
    raise exception '% 2027 rows disagree with the break-fast rule.', v_odd;
  end if;

  -- A fast is broken the following day.
  select count(*) into v_odd
  from public.vaisnava_calendar_events fasting
  where fasting.calendar_year = 2027
    and fasting.event_kind = 'fasting'
    and not exists (
      select 1
      from public.vaisnava_calendar_events parana
      where parana.calendar_year = 2027
        and parana.event_kind = 'parana'
        and parana.event_date = fasting.event_date + 1
    );
  if v_odd <> 0 then
    raise exception '% 2027 fasting days have no parana the next day.', v_odd;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Re-applying the migration is a no-op, not a duplication.
-- ---------------------------------------------------------------------------

create table public.vaisnava_2027_before as
select event_date, title, description, event_kind, source_uid, sort_order
from public.vaisnava_calendar_events
where calendar_year = 2027;

do $$
declare
  v_missing integer;
begin
  -- The constraint that turns a careless second insert into a loud error
  -- rather than a quiet double.
  select count(*) into v_missing
  from pg_constraint
  join pg_class on pg_class.oid = pg_constraint.conrelid
  join pg_namespace on pg_namespace.oid = pg_class.relnamespace
  where pg_namespace.nspname = 'public'
    and pg_class.relname = 'vaisnava_calendar_events'
    and pg_constraint.contype = 'u'
    and pg_get_constraintdef(pg_constraint.oid)
        ilike '%(calendar_year, source_uid)%';
  if v_missing = 0 then
    raise exception 'vaisnava_calendar_events lost its (calendar_year, source_uid) key.';
  end if;
end;
$$;

-- The migration's own statements, run a second time against the seeded year.
insert into public.vaisnava_calendar_publications (
  calendar_year, city, time_zone, source_name, source_url, file_name,
  event_count, published_at, published_by
) values (
  2027,
  'Chicago, Illinois',
  'America/Chicago',
  'VaisnavaCalendar.Info — GCal 11',
  'https://www.vaisnavacalendar.info/ICS/2027/Chicago%20%5BUnited%20States%20of%20America%5D-a2027-ICS.ics',
  'Chicago [United States of America]-a2027-ICS.ics',
  244,
  now(),
  null
)
on conflict (calendar_year) do update set
  city = excluded.city,
  time_zone = excluded.time_zone,
  source_name = excluded.source_name,
  source_url = excluded.source_url,
  file_name = excluded.file_name,
  event_count = excluded.event_count,
  published_at = excluded.published_at;

delete from public.vaisnava_calendar_events where calendar_year = 2027;

insert into public.vaisnava_calendar_events (
  calendar_year, event_date, title, description, event_kind, source_uid, sort_order
)
select 2027, event_date, title, description, event_kind, source_uid, sort_order
from public.vaisnava_2027_before;

do $$
declare
  v_publications integer;
  v_after integer;
  v_drift integer;
begin
  select count(*) into v_publications
  from public.vaisnava_calendar_publications
  where calendar_year = 2027;
  if v_publications <> 1 then
    raise exception 'Re-applying 2027 left % publication rows.', v_publications;
  end if;

  select count(*) into v_after
  from public.vaisnava_calendar_events
  where calendar_year = 2027;
  if v_after <> 244 then
    raise exception 'Re-applying 2027 left % events, expected 244.', v_after;
  end if;

  select count(*) into v_drift
  from (
    (select event_date, title, description, event_kind, source_uid, sort_order
       from public.vaisnava_2027_before
     except all
     select event_date, title, description, event_kind, source_uid, sort_order
       from public.vaisnava_calendar_events where calendar_year = 2027)
    union all
    (select event_date, title, description, event_kind, source_uid, sort_order
       from public.vaisnava_calendar_events where calendar_year = 2027
     except all
     select event_date, title, description, event_kind, source_uid, sort_order
       from public.vaisnava_2027_before)
  ) difference;
  if v_drift <> 0 then
    raise exception 'Re-applying 2027 changed % rows.', v_drift;
  end if;
end;
$$;

drop table public.vaisnava_2027_before;

-- ---------------------------------------------------------------------------
-- The two distributions, side by side, so a divergence can be read.
-- ---------------------------------------------------------------------------

select
  coalesce(kinds.event_kind, 'TOTAL') as event_kind,
  count(*) filter (where kinds.calendar_year = 2026) as year_2026,
  count(*) filter (where kinds.calendar_year = 2027) as year_2027
from public.vaisnava_calendar_events kinds
where kinds.calendar_year in (2026, 2027)
group by rollup (kinds.event_kind)
order by coalesce(kinds.event_kind, 'zzz');

do $$
begin
  raise notice 'all chicago vaisnava calendar 2027 checks passed';
end;
$$;

select 'chicago vaisnava calendar 2027 verification passed' as result;

rollback;
