-- Push notifications actually leave the database, and devotees get reminded
-- before their seva.
--
-- Everything for push was already built: devices register tokens, and the
-- send-service-notification function turns a row into an Expo push. Nothing
-- connected the two — no trigger, no webhook, no client call — so a devotee
-- only ever learned about seva if their app happened to be open. This wires
-- the delivery, and adds the reminder nobody was getting.
-- Requires 202608040025_verification_integrity.sql.

-- pg_net is present on Supabase and absent from a plain Postgres. Its absence
-- must not stop the rest of this migration: in-app notifications keep working,
-- and push simply stays off until the extension and settings are there.
do $$
begin
  create extension if not exists pg_net;
exception when others then
  raise notice 'pg_net is unavailable; push delivery will stay off (%)', sqlerrm;
end;
$$;

-- ---------------------------------------------------------------------------
-- 1. Where to send, and the secret to send it with.
--
--    Held in a table rather than hardcoded so the same migration runs against
--    any project. Readable only by the definer functions below — never by a
--    signed-in devotee, because it holds the push secret.
-- ---------------------------------------------------------------------------

create table if not exists public.app_settings (
  key text primary key,
  value text not null,
  updated_at timestamptz not null default now()
);

alter table public.app_settings enable row level security;
revoke all on table public.app_settings from public, anon, authenticated;

comment on table public.app_settings is
  'Deployment settings. Set push_function_url and push_function_secret to turn on push delivery.';

create or replace function public.app_setting(p_key text)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select value from public.app_settings where key = p_key
$$;

revoke all on function public.app_setting(text) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. Every queued notification is handed to the push function.
--
--    pg_net posts asynchronously, so a slow or failing push never blocks or
--    rolls back the seva action that caused it. If the settings are absent the
--    trigger does nothing at all: in-app notifications keep working and no
--    error is raised.
-- ---------------------------------------------------------------------------

create or replace function public.deliver_app_notification()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  endpoint text;
  secret text;
  poster text;
begin
  endpoint := public.app_setting('push_function_url');
  secret := public.app_setting('push_function_secret');
  if endpoint is null or secret is null then
    return null;
  end if;

  -- http_post lives in whichever schema pg_net was installed into, so it is
  -- resolved at call time rather than baked in.
  select nspname into poster
  from pg_proc
  join pg_namespace on pg_namespace.oid = pg_proc.pronamespace
  where proname = 'http_post'
  limit 1;

  if poster is null then
    return null;
  end if;

  execute format(
    'select %I.http_post(url := $1, headers := $2, body := $3, timeout_milliseconds := 5000)',
    poster
  )
  using
    endpoint,
    jsonb_build_object(
      'Content-Type', 'application/json',
      'x-notification-secret', secret
    ),
    jsonb_build_object('record', jsonb_build_object('id', new.id));
  return null;
exception when others then
  -- A push that cannot be handed off must never undo the seva action that
  -- produced it. The row is already saved and the app will show it.
  raise warning 'push delivery for % could not be queued: %', new.id, sqlerrm;
  return null;
end;
$$;

revoke all on function public.deliver_app_notification() from public, anon, authenticated;

drop trigger if exists deliver_app_notification on public.app_notifications;
create trigger deliver_app_notification
after insert on public.app_notifications
for each row execute function public.deliver_app_notification();

-- ---------------------------------------------------------------------------
-- 3. Reminders before seva starts.
--
--    A devotee who agreed to something days ago is reminded an hour before.
--    Covers dated seva and weekly occurrences alike, and records what it has
--    already sent so a re-run never reminds twice.
-- ---------------------------------------------------------------------------

create table if not exists public.service_reminders_sent (
  service_instance_id uuid not null references public.service_instances(id) on delete cascade,
  devotee_id uuid not null references public.users(id) on delete cascade,
  kind text not null,
  sent_at timestamptz not null default now(),
  primary key (service_instance_id, devotee_id, kind)
);

alter table public.service_reminders_sent enable row level security;
revoke all on table public.service_reminders_sent from public, anon, authenticated;

create or replace function public.send_seva_reminders(
  p_lead_minutes integer default 60
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  due record;
  sent integer := 0;
  starts_at timestamptz;
begin
  for due in
    select
      instances.id as instance_id,
      instances.date,
      instances.start_time,
      assignments.devotee_id,
      public.service_instance_name(instances.*) as seva_name
    from public.service_instances instances
    join public.service_assignments assignments
      on assignments.service_instance_id = instances.id
     and assignments.status in ('assigned', 'confirmed')
    where instances.status not in ('cancelled', 'completed')
      and (instances.date + instances.start_time) at time zone 'America/Chicago'
          between now() and now() + make_interval(mins => p_lead_minutes)
      and not exists (
        select 1 from public.service_reminders_sent reminders
        where reminders.service_instance_id = instances.id
          and reminders.devotee_id = assignments.devotee_id
          and reminders.kind = 'starting_soon'
      )
  loop
    starts_at := (due.date + due.start_time) at time zone 'America/Chicago';

    insert into public.service_reminders_sent (
      service_instance_id, devotee_id, kind
    ) values (due.instance_id, due.devotee_id, 'starting_soon')
    on conflict do nothing;

    if found then
      perform public.queue_app_notification(
        due.devotee_id, 'service_started', 'Your seva is coming up',
        '"' || due.seva_name || '" starts at '
          || to_char(due.start_time, 'FMHH12:MI AM') || ', in about '
          || greatest(1, round(extract(epoch from (starts_at - now())) / 60))
          || ' minutes.',
        jsonb_build_object('serviceInstanceId', due.instance_id)
      );
      sent := sent + 1;
    end if;
  end loop;

  return sent;
end;
$$;

revoke all on function public.send_seva_reminders(integer) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4. Run it on a schedule, alongside the nightly generation job.
-- ---------------------------------------------------------------------------

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    if exists (select 1 from cron.job where jobname = 'send-seva-reminders') then
      perform cron.unschedule('send-seva-reminders');
    end if;
    -- Every ten minutes: fine-grained enough that "in about 55 minutes" is
    -- honest, cheap enough to be invisible.
    perform cron.schedule(
      'send-seva-reminders', '*/10 * * * *',
      'select public.send_seva_reminders(60);'
    );
  end if;
end;
$$;

do $$
begin
  raise notice 'push delivery and reminders applied';
end;
$$;
