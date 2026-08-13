-- Destructive-looking operations in this file are enclosed in a transaction
-- and rolled back. Run only in a test database, never in production tooling.

begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('10000000-0000-0000-0000-000000000001', 'ops-president@example.test', '{"name":"Ops President"}'),
  ('10000000-0000-0000-0000-000000000002', 'ops-tech@example.test', '{"name":"Ops Tech"}'),
  ('10000000-0000-0000-0000-000000000003', 'ops-core@example.test', '{"name":"Ops Core"}'),
  ('10000000-0000-0000-0000-000000000004', 'ops-volunteer@example.test', '{"name":"Ops Volunteer"}'),
  ('10000000-0000-0000-0000-000000000005', 'ops-devotee@example.test', '{"name":"Ops Devotee"}'),
  ('10000000-0000-0000-0000-000000000006', 'ops-substitute@example.test', '{"name":"Ops Substitute"}');

update public.users users
set role_id = roles.id
from public.roles roles
where roles.name = split_part(split_part(users.email, '@', 1), '-', 2)
  and users.email like 'ops-%@example.test';

create temporary table ops_ids (key text primary key, id uuid not null);

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);

do $$
declare
  created_template uuid;
begin
  created_template := public.create_service_template_v2(
    null,
    'Welcome desk and books',
    array[1,4],
    '17:05:00',
    75,
    2,
    'invite_only',
    (now() at time zone 'America/Chicago')::date,
    null,
    array['10000000-0000-0000-0000-000000000005'::uuid]
  );
  if not exists (
    select 1 from public.service_templates
    where id = created_template
      and custom_name = 'Welcome desk and books'
      and days_of_week = array[1,4]
      and duration_minutes = 75
  ) then
    raise exception 'Multi-day custom recurring seva was not created correctly.';
  end if;
  insert into ops_ids values ('template', created_template);
end;
$$;

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000005', true);

do $$
declare
  session_record public.service_qr_sessions;
  completed_count integer;
  push_token_id uuid;
begin
  push_token_id := public.register_device_push_token(
    'ExpoPushToken[functional_test_123]', 'ios', 'Functional iPhone'
  );
  if not exists (
    select 1 from public.device_push_tokens
    where id = push_token_id and user_id = auth.uid() and active
  ) then
    raise exception 'Physical-device push token registration failed.';
  end if;
  session_record := public.start_planned_service_session(
    null,
    'Organize the prasadam hall',
    now(),
    now() + interval '30 minutes',
    'Prasadam hall'
  );
  update public.service_qr_sessions
  set started_at = now() - interval '30 minutes',
      planned_end_at = now() - interval '1 minute'
  where id = session_record.id;
  completed_count := public.complete_due_service_sessions();
  if completed_count <> 1 or not exists (
    select 1 from public.service_qr_sessions
    where id = session_record.id and status = 'completed'
      and auto_completed and service_instance_id is not null
  ) then
    raise exception 'Planned live seva did not auto-complete reliably.';
  end if;
end;
$$;

do $$
declare
  offer_id uuid;
  occurrence_id uuid;
  exception_id uuid;
begin
  select offers.id into offer_id
  from public.service_offers offers
  where offers.service_template_id = (select id from ops_ids where key = 'template')
    and offers.offered_to = auth.uid() and offers.offer_kind = 'recurring';
  perform public.respond_to_service_offer(offer_id, true);
  select instances.id into occurrence_id
  from public.service_instances instances
  join public.service_assignments assignments on assignments.service_instance_id = instances.id
  where instances.template_id = (select id from ops_ids where key = 'template')
    and assignments.devotee_id = auth.uid()
    and instances.date >= (now() at time zone 'America/Chicago')::date
  order by instances.date limit 1;

  -- report_service_unavailable was retired in 0018: it predated the grouped
  -- unavailability columns and could only ever raise. The single reachable
  -- path is the weekly report, narrowed to one occurrence.
  perform public.report_weekly_service_unavailable(
    (select id from ops_ids where key = 'template'),
    'occurrence',
    (select date from public.service_instances where id = occurrence_id),
    null,
    array[extract(dow from (
      select date from public.service_instances where id = occurrence_id
    ))::integer],
    'Functional coverage test'
  );
  select id into exception_id from public.service_exceptions
  where service_instance_id = occurrence_id and devotee_id = auth.uid();
  if exception_id is null then
    raise exception 'Reporting unavailability did not record an exception.';
  end if;
  insert into ops_ids values ('exception', exception_id), ('occurrence', occurrence_id);
end;
$$;

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);

do $$
declare
  offer_id uuid;
begin
  offer_id := public.offer_service_coverage_range(
    (select id from ops_ids where key = 'exception'),
    '10000000-0000-0000-0000-000000000006',
    'occurrence',
    (select date from public.service_instances
      where id = (select id from ops_ids where key = 'occurrence')),
    null
  );
  insert into ops_ids values ('coverage_offer', offer_id);
end;
$$;

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000006', true);

do $$
begin
  perform public.respond_to_coverage_range_offer(
    (select id from ops_ids where key = 'coverage_offer'), true
  );
  if not exists (
    select 1 from public.service_assignments
    where service_instance_id = (select id from ops_ids where key = 'occurrence')
      and devotee_id = auth.uid() and status = 'confirmed'
      and assignment_method = 'accepted_coverage_offer'
  ) then
    raise exception 'Accepted occurrence coverage was not assigned.';
  end if;
  if not exists (
    select 1 from public.service_exceptions
    where id = (select id from ops_ids where key = 'exception')
      and status = 'resolved' and substitute_devotee_id = auth.uid()
  ) then
    raise exception 'Accepted coverage did not resolve its exception.';
  end if;
end;
$$;

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000004', true);

do $$
begin
  -- 0009 made a Volunteer a participant and poster, not a coordinator: they
  -- lost oversight, requirement completion, and coverage resolution. 0015 gave
  -- back services.offer_assignment only, so a Volunteer can invite people to
  -- the seva they post.
  if public.has_permission('services.resolve_coverage')
    or public.has_permission('services.oversee_activity')
    or public.has_permission('services.complete_requirement')
  then
    raise exception 'Volunteer unexpectedly has coordinator access.';
  end if;
  if not public.has_permission('services.post_requirement')
    or not public.has_permission('services.offer_assignment')
  then
    raise exception 'Volunteer cannot post a seva request and invite devotees.';
  end if;
end;
$$;

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000002', true);

do $$
begin
  if not public.has_permission('services.delete_any')
    or not public.has_permission('services.export_reports')
  then
    raise exception 'Tech full activity authority is incomplete.';
  end if;
end;
$$;

rollback;

select 'service operations functional verification passed' as result;
