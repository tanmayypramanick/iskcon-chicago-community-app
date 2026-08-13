-- Functional verification for 202608040028_dashboard_read.sql.
--
-- The single read replaced twelve table reads the app used to make. The thing
-- that matters is that it returns the SAME rows — a dashboard that quietly
-- omits an assignment looks fine and is wrong. So this compares the function's
-- output against the tables directly, as the devotee whose seva it is.
--
-- Rolled back at the end. Every local is prefixed v_ so it can never shadow a
-- column name.
--
-- The final row must read: dashboard read verification passed

begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('70000000-0000-0000-0000-000000000001', 'dash-president@example.test', '{"name":"Dash President"}'),
  ('70000000-0000-0000-0000-000000000002', 'dash-devotee@example.test', '{"name":"Dash Devotee"}'),
  ('70000000-0000-0000-0000-000000000003', 'dash-other@example.test', '{"name":"Dash Other"}');

update public.users users
set role_id = roles.id
from public.roles roles
where (users.email, roles.name) in (
  ('dash-president@example.test', 'president'),
  ('dash-devotee@example.test', 'devotee'),
  ('dash-other@example.test', 'devotee')
);

create temporary table dash_ids (key text primary key, id uuid not null);

-- ---------------------------------------------------------------------------
-- Some seva to read back: one today, one inside the window, one long outside.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', '70000000-0000-0000-0000-000000000001', true);

do $$
declare
  v_today uuid;
  v_recent uuid;
  v_ancient uuid;
begin
  v_today := public.create_service_requirement(
    null, 'Dashboard today seva',
    (now() at time zone 'America/Chicago')::date + 1,
    '09:00:00', 60, 2, 'open', '{}'::uuid[]
  );
  insert into dash_ids values ('today', v_today);

  -- Inside the window but in the past, so it exercises the history side.
  insert into public.service_instances (
    service_type_id, custom_name, date, start_time, duration_minutes,
    slots_needed, participation_mode, posted_by, status
  ) values (
    null, 'Dashboard recent seva',
    (now() at time zone 'America/Chicago')::date - 30,
    '09:00:00', 60, 1, 'open', '70000000-0000-0000-0000-000000000001', 'completed'
  ) returning id into v_recent;
  insert into dash_ids values ('recent', v_recent);

  -- Far outside the window; the function must not return it.
  insert into public.service_instances (
    service_type_id, custom_name, date, start_time, duration_minutes,
    slots_needed, participation_mode, posted_by, status
  ) values (
    null, 'Dashboard ancient seva',
    (now() at time zone 'America/Chicago')::date - 900,
    '09:00:00', 60, 1, 'open', '70000000-0000-0000-0000-000000000001', 'completed'
  ) returning id into v_ancient;
  insert into dash_ids values ('ancient', v_ancient);

  insert into public.service_assignments (
    service_instance_id, devotee_id, assignment_method, assigned_by,
    status, verification
  ) values
    (v_recent, '70000000-0000-0000-0000-000000000002', 'self_joined',
     '70000000-0000-0000-0000-000000000002', 'completed', 'self_report'),
    (v_ancient, '70000000-0000-0000-0000-000000000002', 'self_joined',
     '70000000-0000-0000-0000-000000000002', 'completed', 'self_report');
end;
$$;

-- ---------------------------------------------------------------------------
-- 1. The window is honoured in both directions.
-- ---------------------------------------------------------------------------

do $$
declare
  v_payload jsonb := public.seva_dashboard(180);
  v_ids text[];
begin
  select coalesce(array_agg(value ->> 'id'), '{}')
  into v_ids
  from jsonb_array_elements(v_payload -> 'instances');

  if not ((select id from dash_ids where key = 'today')::text = any(v_ids)) then
    raise exception 'Tomorrow''s seva is missing from the dashboard.';
  end if;
  if not ((select id from dash_ids where key = 'recent')::text = any(v_ids)) then
    raise exception 'A seva inside the window is missing from the dashboard.';
  end if;
  if (select id from dash_ids where key = 'ancient')::text = any(v_ids) then
    raise exception 'A seva far outside the window was returned.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Assignments follow their instance, so no participant goes missing.
--
--    This is what the row caps used to get wrong: a seva inside the window
--    keeping its card but losing the devotees on it.
-- ---------------------------------------------------------------------------

do $$
declare
  v_payload jsonb := public.seva_dashboard(180);
  v_assignments integer;
  v_expected integer;
begin
  select count(*) into v_assignments
  from jsonb_array_elements(v_payload -> 'assignments') as entry
  where entry ->> 'service_instance_id'
        = (select id from dash_ids where key = 'recent')::text;
  if v_assignments <> 1 then
    raise exception 'A seva in the window came back without its devotee.';
  end if;

  -- Nothing belonging to an out-of-window seva leaks in.
  if exists (
    select 1 from jsonb_array_elements(v_payload -> 'assignments') as entry
    where entry ->> 'service_instance_id'
          = (select id from dash_ids where key = 'ancient')::text
  ) then
    raise exception 'An assignment for an out-of-window seva was returned.';
  end if;

  -- Every assignment returned belongs to an instance that was also returned:
  -- an orphan would render as a participant with no seva.
  select count(*) into v_expected
  from jsonb_array_elements(v_payload -> 'assignments') as entry
  where not exists (
    select 1 from jsonb_array_elements(v_payload -> 'instances') as instance
    where instance ->> 'id' = entry ->> 'service_instance_id'
  );
  if v_expected <> 0 then
    raise exception '% assignments came back without their seva.', v_expected;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Every key the app reads is present, and an empty temple returns arrays
--    rather than nulls — a null would crash the assembler.
-- ---------------------------------------------------------------------------

do $$
declare
  v_payload jsonb := public.seva_dashboard(180);
  v_key text;
begin
  foreach v_key in array array[
    'serviceTypes', 'instances', 'assignments', 'offers', 'templates',
    'templateAssignees', 'exceptions', 'coveragePlans', 'interests',
    'verifications', 'counters', 'devotees'
  ]
  loop
    if not (v_payload ? v_key) then
      raise exception 'The dashboard is missing "%".', v_key;
    end if;
    if jsonb_typeof(v_payload -> v_key) <> 'array' then
      raise exception '"%" came back as %, not an array.',
        v_key, jsonb_typeof(v_payload -> v_key);
    end if;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Row-level security still applies. The function is SECURITY INVOKER, so a
--    devotee must see exactly what they saw across the twelve reads — no more.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', '70000000-0000-0000-0000-000000000003', true);
set local role authenticated;

do $$
declare
  v_payload jsonb := public.seva_dashboard(180);
  v_from_function integer;
  v_from_tables integer;
begin
  select count(*) into v_from_function
  from jsonb_array_elements(v_payload -> 'instances');

  select count(*) into v_from_tables
  from public.service_instances
  where date >= (now() at time zone 'America/Chicago')::date - 180;

  if v_from_function <> v_from_tables then
    raise exception
      'The single read returned % seva but the tables show % to this devotee.',
      v_from_function, v_from_tables;
  end if;
end;
$$;

reset role;

-- ---------------------------------------------------------------------------
-- 5. Signed out, it refuses rather than leaking.
-- ---------------------------------------------------------------------------

do $$
declare
  v_refused boolean := false;
begin
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  begin
    perform public.seva_dashboard(180);
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'The dashboard loaded without anybody signed in.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. The payload is a named contract, not "whatever columns exist".
--
--    Adding a column to one of these tables must not silently start shipping
--    it to every device. If a column is genuinely wanted on the client, it is
--    added to the function and to this list, deliberately.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', '70000000-0000-0000-0000-000000000001', true);

do $$
declare
  v_payload jsonb := public.seva_dashboard(180);
  v_section text;
  v_allowed text[];
  v_actual text[];
  v_extra text[];
begin
  foreach v_section in array array['instances', 'assignments', 'offers'] loop
    v_allowed := case v_section
      when 'instances' then array[
        'id','template_id','service_type_id','custom_name','date','start_time',
        'duration_minutes','slots_needed','participation_mode','posted_by',
        'status','created_at']
      when 'assignments' then array[
        'id','service_instance_id','devotee_id','assignment_method',
        'assigned_by','status','verification','attendance','qr_scanned_at',
        'created_at','completed_at']
      else array[
        'id','service_instance_id','service_template_id','service_exception_id',
        'service_coverage_plan_id','offered_to','offered_by','offer_kind',
        'status','created_at','responded_at']
    end;

    select coalesce(array_agg(distinct key), '{}')
    into v_actual
    from jsonb_array_elements(v_payload -> v_section) as entry,
         jsonb_object_keys(entry) as key;

    select coalesce(array_agg(name), '{}') into v_extra
    from unnest(v_actual) as name
    where not (name = any(v_allowed));

    if cardinality(v_extra) > 0 then
      raise exception '"%" is shipping unnamed columns: %',
        v_section, array_to_string(v_extra, ', ');
    end if;
  end loop;
end;
$$;

-- The temple's QR codes must never reach a device.
do $$
declare
  v_payload jsonb := public.seva_dashboard(180);
begin
  if v_payload::text like '%qr_token%' then
    raise exception 'The dashboard payload contains a temple QR token.';
  end if;
end;
$$;

do $$
begin
  raise notice 'all dashboard read checks passed';
end;
$$;

select 'dashboard read verification passed' as result;

rollback;
