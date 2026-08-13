-- Functional verification for 202608040018_seva_reliability.sql.
--
-- Runs inside a transaction that is rolled back, so it is safe against any
-- database — nothing it creates survives. It proves the reliability fixes by
-- exercising them rather than by inspecting definitions.
--
-- Every local is prefixed v_ so it can never shadow a column name. Without
-- that, `where template_id = template_id` compares a column with itself and
-- silently matches every row, which would make these checks pass regardless.
--
-- The final row must read: seva reliability verification passed

begin;

do $$
declare
  v_head uuid := gen_random_uuid();
  v_devotee uuid := gen_random_uuid();
  v_core_role uuid;
  v_devotee_role uuid;
  v_template uuid;
  v_seva_type uuid;
  v_monday date;
  v_tuesday date;
  v_monday_instance uuid;
  v_tuesday_instance uuid;
  v_exception uuid;
  v_count integer;
  v_status text;
  v_mode text;
  v_today date := (now() at time zone 'America/Chicago')::date;
begin
  select id into v_core_role from public.roles where name = 'core';
  select id into v_devotee_role from public.roles where name = 'devotee';

  insert into auth.users (id, email) values
    (v_head, 'reliability-head@test.invalid'),
    (v_devotee, 'reliability-devotee@test.invalid')
  on conflict (id) do nothing;

  insert into public.users (id, name, email, role_id) values
    (v_head, 'Reliability Head', 'reliability-head@test.invalid', v_core_role),
    (v_devotee, 'Reliability Devotee', 'reliability-devotee@test.invalid', v_devotee_role)
  on conflict (id) do update set role_id = excluded.role_id;

  insert into public.service_types (name, category)
  values ('Reliability Test Seva', 'other')
  on conflict (name) do update set is_active = true
  returning id into v_seva_type;

  perform set_config('request.jwt.claims',
    json_build_object('sub', v_head, 'role', 'authenticated')::text, true);

  -- The next Monday and Tuesday on the temple's calendar.
  v_monday := v_today + (((1 - extract(dow from v_today)::integer) + 7) % 7) + 7;
  v_tuesday := v_monday + 1;

  select public.create_service_template_v2(
    v_seva_type, null, array[1, 2], '18:00'::time, 60, 2, 'open',
    v_today, null, array[]::uuid[]
  ) into v_template;

  perform public.generate_service_instances(60);

  select id into v_monday_instance from public.service_instances
  where service_instances.template_id = v_template and service_instances.date = v_monday;
  select id into v_tuesday_instance from public.service_instances
  where service_instances.template_id = v_template and service_instances.date = v_tuesday;

  if v_monday_instance is null or v_tuesday_instance is null then
    raise exception 'setup: expected occurrences on both scheduled days (mon=%, tue=%)',
      v_monday, v_tuesday;
  end if;

  insert into public.service_assignments (
    service_instance_id, devotee_id, assignment_method, assigned_by, status, verification
  ) values
    (v_monday_instance, v_devotee, 'recurring_assignment', v_head, 'confirmed', 'self_report'),
    (v_tuesday_instance, v_devotee, 'recurring_assignment', v_head, 'confirmed', 'self_report');

  -- service_exception_unavailable_dates_check requires unavailable_to on any
  -- scope other than 'forever', so both ends are given explicitly here.
  insert into public.service_exceptions (
    service_instance_id, devotee_id, reason, status,
    unavailable_scope, unavailable_from, unavailable_to, unavailable_days
  ) values (
    v_tuesday_instance, v_devotee, 'Travelling', 'pending',
    'occurrence', v_tuesday, v_tuesday,
    array[extract(dow from v_tuesday)::integer]
  ) returning id into v_exception;

  -- ---- 1. Editing keeps assignments and the pending unavailability ----
  perform public.update_service_template_v2(
    v_template, v_seva_type, null, array[1, 2], '19:30'::time, 90, 2, 'open',
    v_today, null, array[]::uuid[]
  );

  select count(*) into v_count
  from public.service_assignments
  where service_instance_id in (v_monday_instance, v_tuesday_instance)
    and service_assignments.devotee_id = v_devotee;
  if v_count <> 2 then
    raise exception 'edit destroyed assignments: % of 2 survived', v_count;
  end if;

  select count(*) into v_count
  from public.service_exceptions
  where service_exceptions.id = v_exception and service_exceptions.status = 'pending';
  if v_count <> 1 then
    raise exception 'edit destroyed the pending unavailability report';
  end if;

  if not exists (
    select 1 from public.service_instances
    where id = v_monday_instance and start_time = '19:30'::time and duration_minutes = 90
  ) then
    raise exception 'edit did not apply the new time to the existing occurrence';
  end if;

  -- ---- 2. Dropping a weekday cancels rather than deletes an attended date ----
  perform public.update_service_template_v2(
    v_template, v_seva_type, null, array[1], '19:30'::time, 90, 2, 'open',
    v_today, null, array[]::uuid[]
  );

  select status into v_status from public.service_instances where id = v_tuesday_instance;
  if v_status is null then
    raise exception 'dropping a weekday deleted an occurrence people were attached to';
  end if;
  if v_status <> 'cancelled' then
    raise exception 'expected the dropped Tuesday to be cancelled, got %', v_status;
  end if;
  if not exists (select 1 from public.service_exceptions where id = v_exception) then
    raise exception 'dropping a weekday destroyed the unavailability report';
  end if;

  select count(*) into v_count
  from public.service_template_assignees
  where service_template_id = v_template and status = 'active' and 2 = any(days_of_week);
  if v_count <> 0 then
    raise exception 'assignee left scheduled on a weekday the seva no longer runs';
  end if;

  -- ---- 3. Generation must not re-close an occurrence opened for cover ----
  update public.service_instances
  set participation_mode = 'open' where id = v_monday_instance;
  update public.service_templates
  set participation_mode = 'invite_only' where id = v_template;

  perform public.generate_service_instances(60);

  select participation_mode into v_mode
  from public.service_instances where id = v_monday_instance;
  if v_mode <> 'open' then
    raise exception 'generation re-closed an occurrence that was opened for coverage';
  end if;

  raise notice 'all reliability checks passed';
end;
$$;

select 'seva reliability verification passed' as result;

rollback;
