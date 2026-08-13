-- Shared daily temple check-in state.
-- This replaces device-local prototype presence so iOS and Android see the
-- same people in real time. Requires 202608020001_access_levels.sql.

create table public.temple_presence (
  user_id uuid primary key references public.users(id) on delete cascade,
  is_at_temple boolean not null default false,
  presence_date date not null default (
    (now() at time zone 'America/Chicago')::date
  ),
  source text not null default 'manual' check (
    source in ('manual', 'location_confirmed')
  ),
  checked_in_at timestamptz,
  checked_out_at timestamptz,
  updated_at timestamptz not null default now(),
  constraint temple_presence_timestamp_consistency check (
    (is_at_temple and checked_in_at is not null)
    or
    (not is_at_temple and checked_out_at is not null)
  )
);

create index temple_presence_daily_active_idx
  on public.temple_presence(presence_date, is_at_temple, updated_at desc);

create or replace function public.set_my_temple_presence(
  p_is_at_temple boolean,
  p_source text default 'manual'
)
returns public.temple_presence
language plpgsql
security definer
set search_path = ''
as $$
declare
  updated_presence public.temple_presence;
  chicago_today date := (now() at time zone 'America/Chicago')::date;
begin
  if auth.uid() is null then
    raise exception 'Authentication is required.';
  end if;

  if p_source not in ('manual', 'location_confirmed') then
    raise exception 'Choose a valid temple-presence source.';
  end if;

  insert into public.temple_presence (
    user_id,
    is_at_temple,
    presence_date,
    source,
    checked_in_at,
    checked_out_at,
    updated_at
  )
  values (
    auth.uid(),
    p_is_at_temple,
    chicago_today,
    p_source,
    case when p_is_at_temple then now() else null end,
    case when p_is_at_temple then null else now() end,
    now()
  )
  on conflict (user_id) do update set
    is_at_temple = excluded.is_at_temple,
    presence_date = excluded.presence_date,
    source = excluded.source,
    checked_in_at = case
      when excluded.is_at_temple then now()
      else public.temple_presence.checked_in_at
    end,
    checked_out_at = case
      when excluded.is_at_temple then null
      else now()
    end,
    updated_at = now()
  returning * into updated_presence;

  return updated_presence;
end;
$$;

create or replace function public.list_temple_presence_today()
returns table (
  user_id uuid,
  name text,
  photo_url text,
  checked_in_at timestamptz,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    temple_presence.user_id,
    users.name,
    users.photo_url,
    temple_presence.checked_in_at,
    temple_presence.updated_at
  from public.temple_presence
  join public.users on users.id = temple_presence.user_id
  where auth.uid() is not null
    and temple_presence.is_at_temple
    and temple_presence.presence_date =
      (now() at time zone 'America/Chicago')::date
  order by temple_presence.checked_in_at, users.name;
$$;

alter table public.temple_presence enable row level security;

create policy "Authenticated users can read temple presence"
  on public.temple_presence for select
  to authenticated
  using (true);

revoke all on public.temple_presence from anon, authenticated;
grant select on public.temple_presence to authenticated;

revoke all on function public.set_my_temple_presence(boolean, text) from public;
revoke all on function public.list_temple_presence_today() from public;
grant execute on function public.set_my_temple_presence(boolean, text) to authenticated;
grant execute on function public.list_temple_presence_today() to authenticated;

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'temple_presence'
  ) then
    alter publication supabase_realtime add table public.temple_presence;
  end if;
end;
$$;
