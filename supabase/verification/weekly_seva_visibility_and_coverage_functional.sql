-- Functional verification for migration 202608030009. Every write is rolled
-- back. Run this only against a disposable database with migrations 001-009.

begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('20000000-0000-0000-0000-000000000001', 'weekly-president@example.test', '{"name":"Weekly President"}'),
  ('20000000-0000-0000-0000-000000000002', 'weekly-core@example.test', '{"name":"Weekly Core"}'),
  ('20000000-0000-0000-0000-000000000003', 'weekly-volunteer@example.test', '{"name":"Weekly Volunteer"}'),
  ('20000000-0000-0000-0000-000000000004', 'weekly-devotee@example.test', '{"name":"Weekly Devotee"}'),
  ('20000000-0000-0000-0000-000000000005', 'weekly-substitute@example.test', '{"name":"Weekly Substitute"}');

update public.users users
set role_id = roles.id
from public.roles roles
where (users.email, roles.name) in (
  ('weekly-president@example.test', 'president'),
  ('weekly-core@example.test', 'core'),
  ('weekly-volunteer@example.test', 'volunteer'),
  ('weekly-devotee@example.test', 'devotee'),
  ('weekly-substitute@example.test', 'devotee')
);

create temporary table weekly_test_ids (
  key text primary key,
  id uuid not null
);
grant all on table weekly_test_ids to authenticated;

select set_config('request.jwt.claim.sub', '20000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
  covered_template uuid;
  hidden_template uuid;
  partial_template uuid;
  closed_instance uuid;
begin
  covered_template := public.create_service_template_v2(
    null, 'Functional flower garlands', array[1,4,6], '17:00:00',
    90, 1, 'invite_only',
    (now() at time zone 'America/Chicago')::date, null,
    array['20000000-0000-0000-0000-000000000004'::uuid]
  );
  hidden_template := public.create_service_template_v2(
    null, 'Hidden coordinator schedule', array[2], '09:00:00',
    60, 1, 'invite_only',
    (now() at time zone 'America/Chicago')::date, null, '{}'::uuid[]
  );
  partial_template := public.create_service_template_v2(
    null, 'Partially open weekly seva', array[1,4], '10:00:00',
    60, 1, 'open',
    (now() at time zone 'America/Chicago')::date, null, '{}'::uuid[]
  );

  -- An invite-only seva request must name at least one devotee (0015/0016):
  -- inviting nobody produced a request nobody could ever answer. The substitute
  -- is invited so the devotee under test still cannot see it.
  closed_instance := public.create_service_requirement(
    null, 'Coordinator-only seva request',
    (now() at time zone 'America/Chicago')::date + 7,
    '11:00:00', 60, 1, 'invite_only',
    array['20000000-0000-0000-0000-000000000005'::uuid]
  );

  insert into weekly_test_ids values
    ('covered_template', covered_template),
    ('hidden_template', hidden_template),
    ('partial_template', partial_template),
    ('closed_instance', closed_instance);
end;
$$;

reset role;

insert into public.service_template_assignees (
  service_template_id, devotee_id, assigned_by, status, days_of_week
) values (
  (select id from weekly_test_ids where key = 'partial_template'),
  '20000000-0000-0000-0000-000000000004',
  '20000000-0000-0000-0000-000000000001', 'active', array[1]
);
select public.generate_service_instances(180);

select set_config('request.jwt.claim.sub', '20000000-0000-0000-0000-000000000004', true);
set local role authenticated;

do $$
declare
  weekly_offer uuid;
  request_group uuid;
  first_date date;
  final_date date;
begin
  select id into weekly_offer
  from public.service_offers
  where service_template_id = (
      select id from weekly_test_ids where key = 'covered_template'
    )
    and offered_to = '20000000-0000-0000-0000-000000000004'
    and offer_kind = 'recurring'
    and status = 'pending';
  perform public.respond_to_service_offer(weekly_offer, true);

  select min(instances.date), min(instances.date) + 21
  into first_date, final_date
  from public.service_instances instances
  join public.service_assignments assignments
    on assignments.service_instance_id = instances.id
   and assignments.devotee_id = '20000000-0000-0000-0000-000000000004'
   and assignments.status in ('assigned', 'confirmed')
  where instances.template_id = (
    select id from weekly_test_ids where key = 'covered_template'
  );

  request_group := public.report_weekly_service_unavailable(
    (select id from weekly_test_ids where key = 'covered_template'),
    'date_range', first_date, final_date, array[1,4],
    'Functional grouped-unavailability test'
  );
  insert into weekly_test_ids values ('request_group', request_group);

  if (
    select count(*) from public.service_exceptions
    where request_group_id = request_group and status = 'pending'
  ) < 2 then
    raise exception 'Weekly unavailability was not grouped across occurrences.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '20000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
  pending_exception uuid;
  occurrence_date date;
  coverage_offer uuid;
begin
  select exceptions.id, instances.date
  into pending_exception, occurrence_date
  from public.service_exceptions exceptions
  join public.service_instances instances
    on instances.id = exceptions.service_instance_id
  where exceptions.request_group_id = (
      select id from weekly_test_ids where key = 'request_group'
    )
    and exceptions.status = 'pending'
  order by instances.date
  limit 1;

  coverage_offer := public.offer_service_coverage_range(
    pending_exception,
    '20000000-0000-0000-0000-000000000005',
    'occurrence', occurrence_date, occurrence_date
  );
  insert into weekly_test_ids values
    ('covered_exception', pending_exception),
    ('coverage_offer', coverage_offer);
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '20000000-0000-0000-0000-000000000005', true);
set local role authenticated;

do $$
begin
  perform public.respond_to_coverage_range_offer(
    (select id from weekly_test_ids where key = 'coverage_offer'), true
  );
end;
$$;

reset role;

do $$
begin
  if not exists (
    select 1 from public.service_exceptions
    where id = (select id from weekly_test_ids where key = 'covered_exception')
      and status = 'resolved'
      and substitute_devotee_id = '20000000-0000-0000-0000-000000000005'
  ) then
    raise exception 'Accepted one-day weekly coverage was not assigned.';
  end if;
  if not exists (
    select 1 from public.service_exceptions
    where request_group_id = (select id from weekly_test_ids where key = 'request_group')
      and status = 'pending'
  ) then
    raise exception 'One-day coverage incorrectly resolved the whole date range.';
  end if;
end;
$$;

select set_config('request.jwt.claim.sub', '20000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
  pending_exception uuid;
begin
  select id into pending_exception
  from public.service_exceptions
  where request_group_id = (select id from weekly_test_ids where key = 'request_group')
    and status = 'pending'
  limit 1;
  perform public.reopen_service_exception(pending_exception);
  if exists (
    select 1 from public.service_exceptions
    where request_group_id = (select id from weekly_test_ids where key = 'request_group')
      and status = 'pending' and resolution_kind is distinct from 'broadcast'
  ) then
    raise exception 'Open-to-everyone did not broadcast every uncovered occurrence.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '20000000-0000-0000-0000-000000000003', true);
set local role authenticated;

do $$
declare
  posted_open uuid;
  posted_invite uuid;
  joined_days integer[];
  invite_rejected boolean := false;
begin
  -- 0015 gave services.offer_assignment back to a Volunteer on purpose: they
  -- post seva requests, so they must be able to invite devotees to them. The
  -- coordinator boundary is unchanged.
  if not public.has_permission('services.post_requirement')
    or not public.has_permission('services.offer_assignment')
    or public.has_permission('services.view_all')
    or public.has_permission('services.oversee_activity')
    or public.has_permission('services.complete_requirement')
    or public.has_permission('services.resolve_coverage')
  then
    raise exception 'Volunteer permission boundary is incorrect.';
  end if;

  if exists (
    select 1 from public.service_templates
    where id = (select id from weekly_test_ids where key = 'hidden_template')
  ) or exists (
    select 1 from public.service_instances
    where id = (select id from weekly_test_ids where key = 'closed_instance')
  ) then
    raise exception 'Volunteer can see a coordinator-only community schedule item.';
  end if;

  if not exists (
    select 1 from public.service_templates
    where id = (select id from weekly_test_ids where key = 'covered_template')
  ) then
    raise exception 'Broadcast weekly coverage is not visible as an open requirement.';
  end if;

  posted_open := public.create_service_requirement(
    null, 'Volunteer-created open need',
    (now() at time zone 'America/Chicago')::date + 8,
    '12:00:00', 60, 2, 'open', '{}'::uuid[]
  );
  if not exists (select 1 from public.service_instances where id = posted_open) then
    raise exception 'Volunteer could not see their own open service need.';
  end if;

  -- A Volunteer may now invite specific devotees to a seva request they post.
  posted_invite := public.create_service_requirement(
    null, 'Volunteer invite-only seva request',
    (now() at time zone 'America/Chicago')::date + 9,
    '12:00:00', 60, 1, 'invite_only',
    array['20000000-0000-0000-0000-000000000004'::uuid]
  );
  if not exists (
    select 1 from public.service_offers
    where service_instance_id = posted_invite
      and offered_to = '20000000-0000-0000-0000-000000000004'
      and status = 'pending'
  ) then
    raise exception 'Volunteer invitation did not reach the devotee.';
  end if;

  -- More invitations than places is still refused, whoever is posting.
  begin
    perform public.create_service_requirement(
      null, 'Volunteer over-invited seva request',
      (now() at time zone 'America/Chicago')::date + 10,
      '12:00:00', 60, 1, 'invite_only',
      array[
        '20000000-0000-0000-0000-000000000004'::uuid,
        '20000000-0000-0000-0000-000000000005'::uuid
      ]
    );
  exception when others then
    invite_rejected := true;
  end;
  if not invite_rejected then
    raise exception 'Two devotees were invited to a seva with one place.';
  end if;

  select days_of_week into joined_days
  from public.join_weekly_service(
    (select id from weekly_test_ids where key = 'partial_template')
  );
  if joined_days <> array[4] then
    raise exception 'Weekly self-join did not keep only the available weekday: %', joined_days;
  end if;
end;
$$;

reset role;

do $$
begin
  if not exists (
    select 1 from public.app_notifications
    where user_id = '20000000-0000-0000-0000-000000000005'
      and kind = 'service_offer'
      and data ? 'serviceCoveragePlanId'
  ) then
    raise exception 'Targeted weekly coverage notification was not queued.';
  end if;
  if not exists (
    select 1 from public.app_notifications
    where user_id = '20000000-0000-0000-0000-000000000003'
      and kind = 'service_open'
      and data ? 'coverageRequestGroupId'
  ) then
    raise exception 'Broadcast weekly opening notification was not queued.';
  end if;
end;
$$;

rollback;

select 'weekly seva visibility and coverage functional verification passed' as result;
