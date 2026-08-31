-- Chicago Vaiṣṇava Calendar
--
-- Calendar dates and pāraṇa windows depend on location. The app therefore
-- publishes one reviewed Chicago calendar per Gregorian year rather than
-- mixing dates copied from other cities. Everyone signed in may read it;
-- Community Heads, Tech Admins, and the President replace a complete year
-- atomically from an ICS file.

create table if not exists public.vaisnava_calendar_publications (
  calendar_year integer primary key check (calendar_year between 2020 and 2100),
  city text not null default 'Chicago, Illinois',
  time_zone text not null default 'America/Chicago',
  source_name text not null,
  source_url text,
  file_name text not null,
  source_file_text text,
  event_count integer not null check (event_count between 1 and 1000),
  published_at timestamptz not null default now(),
  published_by uuid references public.users(id)
);

create table if not exists public.vaisnava_calendar_events (
  id uuid primary key default gen_random_uuid(),
  calendar_year integer not null references public.vaisnava_calendar_publications(calendar_year)
    on delete cascade,
  event_date date not null,
  title text not null,
  description text,
  event_kind text not null check (
    event_kind in (
      'ekadasi', 'parana', 'fasting', 'festival',
      'appearance', 'disappearance', 'observance', 'other'
    )
  ),
  source_uid text not null,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  unique (calendar_year, source_uid)
);

create index if not exists vaisnava_calendar_events_date_idx
  on public.vaisnava_calendar_events(event_date, sort_order, title);

alter table public.vaisnava_calendar_publications enable row level security;
alter table public.vaisnava_calendar_events enable row level security;

drop policy if exists "Signed in devotees read calendar publications"
  on public.vaisnava_calendar_publications;
create policy "Signed in devotees read calendar publications"
  on public.vaisnava_calendar_publications
  for select to authenticated
  using (true);

drop policy if exists "Signed in devotees read calendar events"
  on public.vaisnava_calendar_events;
create policy "Signed in devotees read calendar events"
  on public.vaisnava_calendar_events
  for select to authenticated
  using (true);

revoke all on public.vaisnava_calendar_publications from anon, authenticated;
revoke all on public.vaisnava_calendar_events from anon, authenticated;
grant select on public.vaisnava_calendar_publications to authenticated;
grant select on public.vaisnava_calendar_events to authenticated;

create or replace function public.replace_vaisnava_calendar_year(
  p_year integer,
  p_source_name text,
  p_source_url text,
  p_file_name text,
  p_source_file_text text,
  p_events jsonb
)
returns public.vaisnava_calendar_publications
language plpgsql
security definer
set search_path = ''
as $$
declare
  published public.vaisnava_calendar_publications;
  event_total integer;
begin
  if auth.uid() is null
    or not public.has_permission('services.manage_recurring')
  then
    raise exception 'Community Head, Tech Admin, or President access is required.';
  end if;

  if p_year < 2020 or p_year > 2100 then
    raise exception 'Choose a calendar year between 2020 and 2100.';
  end if;

  if nullif(trim(p_source_name), '') is null
    or nullif(trim(p_file_name), '') is null
  then
    raise exception 'The calendar source and file name are required.';
  end if;

  if p_source_file_text is null
    or octet_length(p_source_file_text) < 100
    or octet_length(p_source_file_text) > 2 * 1024 * 1024
  then
    raise exception 'Choose a valid ICS calendar file smaller than 2 MB.';
  end if;

  if jsonb_typeof(p_events) <> 'array' then
    raise exception 'The calendar events must be a JSON array.';
  end if;

  event_total := jsonb_array_length(p_events);
  if event_total < 10 or event_total > 1000 then
    raise exception 'A yearly calendar must contain between 10 and 1000 events.';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_events) event
    where nullif(trim(event->>'title'), '') is null
      or nullif(trim(event->>'sourceUid'), '') is null
      or (event->>'date') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
      or coalesce(event->>'kind', '') not in (
        'ekadasi', 'parana', 'fasting', 'festival',
        'appearance', 'disappearance', 'observance', 'other'
      )
  ) then
    raise exception 'Every event needs a valid date, title, type, and source identifier for the selected year.';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_events) event
    where extract(year from (event->>'date')::date)::integer <> p_year
  ) then
    raise exception 'Every calendar event must belong to the selected year.';
  end if;

  insert into public.vaisnava_calendar_publications (
    calendar_year, city, time_zone, source_name, source_url, file_name,
    source_file_text, event_count, published_at, published_by
  ) values (
    p_year,
    'Chicago, Illinois',
    'America/Chicago',
    trim(p_source_name),
    nullif(trim(p_source_url), ''),
    trim(p_file_name),
    p_source_file_text,
    event_total,
    now(),
    auth.uid()
  )
  on conflict (calendar_year) do update set
    source_name = excluded.source_name,
    source_url = excluded.source_url,
    file_name = excluded.file_name,
    source_file_text = excluded.source_file_text,
    event_count = excluded.event_count,
    published_at = excluded.published_at,
    published_by = excluded.published_by
  returning * into published;

  delete from public.vaisnava_calendar_events
  where calendar_year = p_year;

  insert into public.vaisnava_calendar_events (
    calendar_year, event_date, title, description, event_kind,
    source_uid, sort_order
  )
  select
    p_year,
    (event->>'date')::date,
    trim(event->>'title'),
    nullif(trim(event->>'description'), ''),
    event->>'kind',
    trim(event->>'sourceUid'),
    row_number() over ()::integer
  from jsonb_array_elements(p_events) event;

  return published;
end;
$$;

revoke all on function public.replace_vaisnava_calendar_year(
  integer, text, text, text, text, jsonb
) from public, anon;
grant execute on function public.replace_vaisnava_calendar_year(
  integer, text, text, text, text, jsonb
) to authenticated;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'vaisnava_calendar_publications'
  ) then
    alter publication supabase_realtime
      add table public.vaisnava_calendar_publications;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'vaisnava_calendar_events'
  ) then
    alter publication supabase_realtime
      add table public.vaisnava_calendar_events;
  end if;
end;
$$;
