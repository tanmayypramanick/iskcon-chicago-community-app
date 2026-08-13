-- Functional verification for 202608040026_push_delivery_and_reminders.sql.
--
-- Rolled back at the end. Every local is prefixed v_ so it can never shadow a
-- column name.
--
-- The final row must read: push and reminders verification passed

begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('60000000-0000-0000-0000-000000000001', 'push-core@example.test', '{"name":"Push Core"}'),
  ('60000000-0000-0000-0000-000000000002', 'push-devotee@example.test', '{"name":"Push Devotee"}');

update public.users users
set role_id = roles.id
from public.roles roles
where (users.email, roles.name) in (
  ('push-core@example.test', 'core'),
  ('push-devotee@example.test', 'devotee')
);

-- ---------------------------------------------------------------------------
-- 1. The delivery trigger is attached and stays out of the way.
-- ---------------------------------------------------------------------------

do $$
begin
  if not exists (
    select 1 from pg_trigger
    where tgname = 'deliver_app_notification'
      and tgrelid = 'public.app_notifications'::regclass
      and not tgisinternal
  ) then
    raise exception 'Queued notifications are not handed to the push function.';
  end if;
end;
$$;

-- With no settings configured the trigger must be a silent no-op: in-app
-- notifications keep working and nothing raises.
do $$
declare
  v_id uuid;
begin
  delete from public.app_settings where key in ('push_function_url', 'push_function_secret');

  insert into public.app_notifications (user_id, kind, title, body, data)
  values (
    '60000000-0000-0000-0000-000000000002', 'remote', 'Unconfigured push',
    'This must still be saved.', '{}'::jsonb
  ) returning id into v_id;

  if not exists (select 1 from public.app_notifications where id = v_id) then
    raise exception 'A notification was lost when push was not configured.';
  end if;
end;
$$;

-- A configured but unreachable endpoint must not undo the seva action either.
do $$
declare
  v_id uuid;
begin
  insert into public.app_settings (key, value) values
    ('push_function_url', 'http://127.0.0.1:9/never-listening'),
    ('push_function_secret', 'test-secret')
  on conflict (key) do update set value = excluded.value;

  insert into public.app_notifications (user_id, kind, title, body, data)
  values (
    '60000000-0000-0000-0000-000000000002', 'remote', 'Unreachable push',
    'This must still be saved.', '{}'::jsonb
  ) returning id into v_id;

  if not exists (select 1 from public.app_notifications where id = v_id) then
    raise exception 'A notification was lost when the push endpoint failed.';
  end if;
end;
$$;

-- The settings table holds a secret, so it must be unreadable by clients.
do $$
begin
  if exists (
    select 1 from information_schema.table_privileges
    where table_schema = 'public' and table_name = 'app_settings'
      and grantee in ('anon', 'authenticated', 'PUBLIC')
  ) then
    raise exception 'The push secret is readable by signed-in clients.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. A devotee is reminded before their seva, once.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', '60000000-0000-0000-0000-000000000001', true);

create temporary table push_ids (key text primary key, id uuid not null);

do $$
declare
  v_instance uuid;
  v_soon timestamp;
begin
  -- Half an hour from now on the temple's clock.
  v_soon := (now() at time zone 'America/Chicago') + interval '30 minutes';

  v_instance := public.create_service_requirement(
    null, 'Push reminder seva', v_soon::date, v_soon::time, 60, 1, 'open', '{}'::uuid[]
  );
  insert into push_ids values ('instance', v_instance);
end;
$$;

select set_config('request.jwt.claim.sub', '60000000-0000-0000-0000-000000000002', true);

do $$
begin
  perform public.join_service_instance((select id from push_ids where key = 'instance'));
end;
$$;

do $$
declare
  v_sent integer;
  v_reminders integer;
begin
  v_sent := public.send_seva_reminders(60);
  if v_sent < 1 then
    raise exception 'Nobody was reminded about seva starting in half an hour.';
  end if;

  if not exists (
    select 1 from public.app_notifications
    where user_id = '60000000-0000-0000-0000-000000000002'
      and title = 'Your seva is coming up'
      and body like '%Push reminder seva%'
  ) then
    raise exception 'The reminder did not name the seva.';
  end if;

  -- Running again must remind nobody twice.
  v_sent := public.send_seva_reminders(60);
  if v_sent <> 0 then
    raise exception 'Running reminders again sent % more.', v_sent;
  end if;

  select count(*) into v_reminders
  from public.app_notifications
  where user_id = '60000000-0000-0000-0000-000000000002'
    and title = 'Your seva is coming up';
  if v_reminders <> 1 then
    raise exception 'A devotee was reminded % times.', v_reminders;
  end if;
end;
$$;

-- Seva further out than the window is left alone.
do $$
declare
  v_instance uuid;
  v_later timestamp := (now() at time zone 'America/Chicago') + interval '5 hours';
begin
  perform set_config('request.jwt.claim.sub', '60000000-0000-0000-0000-000000000001', true);
  v_instance := public.create_service_requirement(
    null, 'Push distant seva', v_later::date, v_later::time, 60, 1, 'open', '{}'::uuid[]
  );
  perform set_config('request.jwt.claim.sub', '60000000-0000-0000-0000-000000000002', true);
  perform public.join_service_instance(v_instance);

  if public.send_seva_reminders(60) <> 0 then
    raise exception 'Seva hours away was reminded about too early.';
  end if;
end;
$$;

-- A cancelled seva reminds nobody.
do $$
declare
  v_instance uuid;
  v_soon timestamp := (now() at time zone 'America/Chicago') + interval '20 minutes';
begin
  perform set_config('request.jwt.claim.sub', '60000000-0000-0000-0000-000000000001', true);
  v_instance := public.create_service_requirement(
    null, 'Push cancelled seva', v_soon::date, v_soon::time, 60, 1, 'open', '{}'::uuid[]
  );
  perform set_config('request.jwt.claim.sub', '60000000-0000-0000-0000-000000000002', true);
  perform public.join_service_instance(v_instance);

  update public.service_instances set status = 'cancelled' where id = v_instance;

  if public.send_seva_reminders(60) <> 0 then
    raise exception 'A cancelled seva still sent a reminder.';
  end if;
end;
$$;

do $$
begin
  raise notice 'all push and reminder checks passed';
end;
$$;

select 'push and reminders verification passed' as result;

rollback;
