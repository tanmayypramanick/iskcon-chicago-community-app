-- Functional verification for 202608040020_seva_completeness.sql.
--
-- Everything runs inside a transaction that is rolled back, so it is safe
-- against any database. Each block proves a fix by exercising it, not by
-- reading a function definition.
--
-- Every local is prefixed v_ so it can never shadow a column name. Without
-- that, `where template_id = template_id` compares a column with itself and
-- silently matches every row, which would make these checks pass regardless.
--
-- The final row must read: seva completeness verification passed

begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('30000000-0000-0000-0000-000000000001', 'complete-president@example.test', '{"name":"Completeness President"}'),
  ('30000000-0000-0000-0000-000000000002', 'complete-core@example.test', '{"name":"Completeness Core"}'),
  ('30000000-0000-0000-0000-000000000003', 'complete-devotee-a@example.test', '{"name":"Completeness Devotee A"}'),
  ('30000000-0000-0000-0000-000000000004', 'complete-devotee-b@example.test', '{"name":"Completeness Devotee B"}'),
  ('30000000-0000-0000-0000-000000000005', 'complete-substitute@example.test', '{"name":"Completeness Substitute"}');

update public.users users
set role_id = roles.id
from public.roles roles
where (users.email, roles.name) in (
  ('complete-president@example.test', 'president'),
  ('complete-core@example.test', 'core'),
  ('complete-devotee-a@example.test', 'devotee'),
  ('complete-devotee-b@example.test', 'devotee'),
  ('complete-substitute@example.test', 'devotee')
);

create temporary table completeness_ids (key text primary key, id uuid not null);
grant all on table completeness_ids to authenticated;

-- ---------------------------------------------------------------------------
-- 1. A verified seva that had not finished settles once its end time passes.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', '30000000-0000-0000-0000-000000000003', true);

do $$
declare
  v_registration public.service_verifications;
begin
  v_registration := public.request_seva_verification(
    null, 'Completeness altar cleaning',
    now() + interval '2 hours', now() + interval '3 hours',
    'Temple room', '30000000-0000-0000-0000-000000000001', null
  );
  insert into completeness_ids values ('registration', v_registration.id);
end;
$$;

select set_config('request.jwt.claim.sub', '30000000-0000-0000-0000-000000000001', true);

do $$
declare
  v_reviewed public.service_verifications;
  v_status text;
  v_settled integer;
begin
  v_reviewed := public.respond_to_seva_verification(
    (select id from completeness_ids where key = 'registration'), true, null
  );
  if v_reviewed.service_instance_id is null then
    raise exception 'Verifying did not create the seva record.';
  end if;
  insert into completeness_ids values ('verified_instance', v_reviewed.service_instance_id);

  select status into v_status from public.service_instances
  where id = v_reviewed.service_instance_id;
  if v_status <> 'closed' then
    raise exception 'A seva still ahead of us should not read as finished, got %', v_status;
  end if;

  -- The seva now finishes. Before 0020 this record stayed 'closed' for good.
  update public.service_verifications
  set start_at = now() - interval '2 hours', end_at = now() - interval '1 hour'
  where id = v_reviewed.id;

  v_settled := public.settle_finished_verified_seva();
  if v_settled < 1 then
    raise exception 'Finished verified seva was not settled.';
  end if;

  select status into v_status from public.service_instances
  where id = v_reviewed.service_instance_id;
  if v_status <> 'completed' then
    raise exception 'Settled seva did not become completed, got %', v_status;
  end if;

  if not exists (
    select 1 from public.service_assignments
    where service_instance_id = v_reviewed.service_instance_id
      and devotee_id = '30000000-0000-0000-0000-000000000003'
      and status = 'completed'
      and completed_at is not null
  ) then
    raise exception 'Settling did not finish the devotee''s own record.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Overlapping registrations are ACCEPTED. The clash is a warning, not a bar.
--
--    The temple's rule: "only accept if you manage to serve". The devotee is
--    told about the overlap and decides. 202608310081 dropped the exclusion
--    constraint that used to decide for them; this is the test that keeps it
--    dropped.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', '30000000-0000-0000-0000-000000000004', true);

do $$
begin
  perform public.request_seva_verification(
    null, 'Completeness kitchen help',
    now() + interval '1 hour', now() + interval '3 hours',
    'Kitchen', '30000000-0000-0000-0000-000000000001', null
  );

  -- The second one overlaps the first by an hour and must be allowed through.
  begin
    perform public.request_seva_verification(
      null, 'Completeness overlapping help',
      now() + interval '2 hours', now() + interval '4 hours',
      'Kitchen', '30000000-0000-0000-0000-000000000001', null
    );
  exception when others then
    raise exception
      'Overlapping seva was refused (%). Clashes must warn, never block.',
      sqlerrm;
  end;

  if (
    select count(*) from public.service_verifications
    where devotee_id = '30000000-0000-0000-0000-000000000004'
      and custom_name in (
        'Completeness kitchen help', 'Completeness overlapping help'
      )
  ) <> 2 then
    raise exception 'Both overlapping registrations should have been stored.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Accepting a weekly invitation only claims weekdays that have room.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', '30000000-0000-0000-0000-000000000002', true);

do $$
declare
  v_template uuid;
begin
  -- Monday and Thursday, one place each.
  v_template := public.create_service_template_v2(
    null, 'Completeness weekly garlands', array[1, 4], '17:00:00', 60, 1,
    'invite_only', (now() at time zone 'America/Chicago')::date, null,
    array['30000000-0000-0000-0000-000000000004'::uuid]
  );
  insert into completeness_ids values ('weekly_template', v_template);
end;
$$;

-- Devotee A already stands on Mondays.
insert into public.service_template_assignees (
  service_template_id, devotee_id, assigned_by, status, days_of_week
) values (
  (select id from completeness_ids where key = 'weekly_template'),
  '30000000-0000-0000-0000-000000000003',
  '30000000-0000-0000-0000-000000000002', 'active', array[1]
);

select public.generate_service_instances(60);

select set_config('request.jwt.claim.sub', '30000000-0000-0000-0000-000000000004', true);

do $$
declare
  v_offer uuid;
  v_days integer[];
  v_monday_assignments integer;
  v_thursday_assignments integer;
begin
  select id into v_offer from public.service_offers
  where service_template_id = (select id from completeness_ids where key = 'weekly_template')
    and offered_to = '30000000-0000-0000-0000-000000000004'
    and offer_kind = 'recurring' and status = 'pending';
  if v_offer is null then
    raise exception 'setup: the weekly invitation was never sent.';
  end if;

  perform public.respond_to_service_offer(v_offer, true);

  select days_of_week into v_days from public.service_template_assignees
  where service_template_id = (select id from completeness_ids where key = 'weekly_template')
    and devotee_id = '30000000-0000-0000-0000-000000000004';

  -- Before 0020 the count was template-wide, so this accept was refused
  -- outright even though every Thursday was empty.
  if v_days is distinct from array[4] then
    raise exception 'Accepting claimed the wrong weekdays: %', v_days;
  end if;

  select count(*) into v_monday_assignments
  from public.service_assignments assignments
  join public.service_instances instances on instances.id = assignments.service_instance_id
  where instances.template_id = (select id from completeness_ids where key = 'weekly_template')
    and assignments.devotee_id = '30000000-0000-0000-0000-000000000004'
    and extract(dow from instances.date)::integer = 1;
  if v_monday_assignments <> 0 then
    raise exception 'Accepting put a second devotee on a full Monday % times.',
      v_monday_assignments;
  end if;

  select count(*) into v_thursday_assignments
  from public.service_assignments assignments
  join public.service_instances instances on instances.id = assignments.service_instance_id
  where instances.template_id = (select id from completeness_ids where key = 'weekly_template')
    and assignments.devotee_id = '30000000-0000-0000-0000-000000000004'
    and extract(dow from instances.date)::integer = 4;
  if v_thursday_assignments = 0 then
    raise exception 'Accepting did not stand the devotee on any free Thursday.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Coverage: no duplicate asks, no dates that have already gone, and the
--    devotee holding a superseded ask is told.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', '30000000-0000-0000-0000-000000000003', true);

do $$
declare
  v_first_monday date;
  v_group uuid;
begin
  select min(instances.date) into v_first_monday
  from public.service_instances instances
  join public.service_assignments assignments
    on assignments.service_instance_id = instances.id
   and assignments.devotee_id = '30000000-0000-0000-0000-000000000003'
   and assignments.status in ('assigned', 'confirmed')
  where instances.template_id = (select id from completeness_ids where key = 'weekly_template');

  if v_first_monday is null then
    raise exception 'setup: devotee A was never stood on a Monday.';
  end if;

  v_group := public.report_weekly_service_unavailable(
    (select id from completeness_ids where key = 'weekly_template'),
    'occurrence', v_first_monday, null, array[1], 'Travelling'
  );
  insert into completeness_ids values ('group_one', v_group);
end;
$$;

select set_config('request.jwt.claim.sub', '30000000-0000-0000-0000-000000000002', true);

do $$
declare
  v_exception uuid;
  v_date date;
  v_offer uuid;
  v_refused boolean := false;
begin
  select exceptions.id, instances.date into v_exception, v_date
  from public.service_exceptions exceptions
  join public.service_instances instances on instances.id = exceptions.service_instance_id
  where exceptions.request_group_id = (select id from completeness_ids where key = 'group_one')
    and exceptions.status = 'pending'
  limit 1;

  v_offer := public.offer_service_coverage_range(
    v_exception, '30000000-0000-0000-0000-000000000005', 'occurrence', v_date, v_date
  );
  insert into completeness_ids values
    ('coverage_exception', v_exception), ('coverage_offer', v_offer);

  -- A devotee asked to cover must be able to read when, without opening the
  -- app: weekday, date and clock time all in the message.
  if not exists (
    select 1 from public.app_notifications
    where user_id = '30000000-0000-0000-0000-000000000005'
      and kind = 'service_offer'
      and body like '%' || to_char(v_date, 'FMDay') || '%'
      and body like '%' || to_char(v_date, 'FMMonth FMDD') || '%'
      and body like '% at %:%M%'
  ) then
    raise exception 'The coverage request does not say which day and time: %',
      (select body from public.app_notifications
       where user_id = '30000000-0000-0000-0000-000000000005'
         and kind = 'service_offer'
       order by created_at desc limit 1);
  end if;

  -- Asking the same devotee again while they are still deciding is refused.
  begin
    perform public.offer_service_coverage_range(
      v_exception, '30000000-0000-0000-0000-000000000005', 'occurrence', v_date, v_date
    );
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'The same devotee was asked to cover the same date twice.';
  end if;

  -- A date that has already gone is refused.
  v_refused := false;
  begin
    perform public.offer_service_coverage_range(
      v_exception, '30000000-0000-0000-0000-000000000004', 'occurrence',
      (now() at time zone 'America/Chicago')::date - 3,
      (now() at time zone 'America/Chicago')::date - 3
    );
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'Coverage was arranged for a date that has already passed.';
  end if;
end;
$$;

-- Reporting the same dates twice is refused outright, because the first report
-- already stood the devotee down from them.
select set_config('request.jwt.claim.sub', '30000000-0000-0000-0000-000000000003', true);

do $$
declare
  v_first_monday date;
  v_refused boolean := false;
begin
  select instances.date into v_first_monday
  from public.service_exceptions exceptions
  join public.service_instances instances on instances.id = exceptions.service_instance_id
  where exceptions.id = (select id from completeness_ids where key = 'coverage_exception');

  begin
    perform public.report_weekly_service_unavailable(
      (select id from completeness_ids where key = 'weekly_template'),
      'occurrence', v_first_monday, null, array[1], 'Still travelling'
    );
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'The same dates were reported unavailable twice.';
  end if;
end;
$$;

-- Should a future path ever re-stamp a devotee's exceptions into a new request
-- group, the asks already sent for the old one must be withdrawn rather than
-- left pointing at a group with nothing pending — the devotee holding one
-- could otherwise only ever be told 'this has already been covered'.
do $$
declare
  v_instance uuid;
  v_withdrawn integer;
begin
  select service_instance_id into v_instance from public.service_exceptions
  where id = (select id from completeness_ids where key = 'coverage_exception');

  v_withdrawn := public.withdraw_superseded_coverage_asks(
    '30000000-0000-0000-0000-000000000003', array[v_instance]
  );
  if v_withdrawn <> 1 then
    raise exception 'Expected one outstanding ask to be withdrawn, got %', v_withdrawn;
  end if;

  if not exists (
    select 1 from public.service_offers
    where id = (select id from completeness_ids where key = 'coverage_offer')
      and status = 'expired'
  ) then
    raise exception 'A superseded coverage ask was left outstanding.';
  end if;

  if not exists (
    select 1 from public.service_coverage_plans
    where request_group_id = (select id from completeness_ids where key = 'group_one')
      and substitute_devotee_id = '30000000-0000-0000-0000-000000000005'
      and status = 'cancelled'
  ) then
    raise exception 'The coverage plan behind a withdrawn ask stayed pending.';
  end if;

  if not exists (
    select 1 from public.app_notifications
    where user_id = '30000000-0000-0000-0000-000000000005'
      and kind = 'service_cancelled'
      and title = 'A coverage request was withdrawn'
  ) then
    raise exception 'The devotee holding a withdrawn coverage ask was never told.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Opening coverage to the community, and closing it when somebody joins.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', '30000000-0000-0000-0000-000000000002', true);

do $$
declare
  v_exception uuid;
begin
  select id into v_exception from public.service_exceptions
  where devotee_id = '30000000-0000-0000-0000-000000000003' and status = 'pending'
  limit 1;
  perform public.reopen_service_exception(v_exception);
  insert into completeness_ids values ('broadcast_exception', v_exception);
end;
$$;

select set_config('request.jwt.claim.sub', '30000000-0000-0000-0000-000000000005', true);

do $$
declare
  v_instance uuid;
begin
  select service_instance_id into v_instance from public.service_exceptions
  where id = (select id from completeness_ids where key = 'broadcast_exception');

  perform public.join_service_instance(v_instance);

  if not exists (
    select 1 from public.service_exceptions
    where id = (select id from completeness_ids where key = 'broadcast_exception')
      and status = 'resolved'
      and substitute_devotee_id = '30000000-0000-0000-0000-000000000005'
  ) then
    raise exception 'Joining an opened date did not close the coverage request.';
  end if;

  if not exists (
    select 1 from public.app_notifications
    where user_id = '30000000-0000-0000-0000-000000000003'
      and kind = 'service_coverage_resolved'
  ) then
    raise exception 'The devotee who needed cover was never told it was arranged.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Removing a seva request keeps what people actually did.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', '30000000-0000-0000-0000-000000000002', true);

do $$
declare
  v_instance uuid;
begin
  v_instance := public.create_service_requirement(
    null, 'Completeness hall setup',
    (now() at time zone 'America/Chicago')::date + 2,
    '09:00:00', 60, 2, 'open', '{}'::uuid[]
  );
  insert into completeness_ids values ('served_request', v_instance);
end;
$$;

insert into public.service_assignments (
  service_instance_id, devotee_id, assignment_method, assigned_by,
  status, verification, completed_at
) values (
  (select id from completeness_ids where key = 'served_request'),
  '30000000-0000-0000-0000-000000000004', 'self_joined',
  '30000000-0000-0000-0000-000000000004', 'completed', 'self_report', now()
), (
  (select id from completeness_ids where key = 'served_request'),
  '30000000-0000-0000-0000-000000000005', 'self_joined',
  '30000000-0000-0000-0000-000000000005', 'confirmed', 'self_report', null
);

do $$
declare
  v_status text;
begin
  perform public.delete_service_requirement(
    (select id from completeness_ids where key = 'served_request')
  );

  select status into v_status from public.service_instances
  where id = (select id from completeness_ids where key = 'served_request');
  if v_status is null then
    raise exception 'Removing a served seva request destroyed the record of it.';
  end if;
  if v_status <> 'cancelled' then
    raise exception 'A served seva request should be cancelled, got %', v_status;
  end if;

  if not exists (
    select 1 from public.service_assignments
    where service_instance_id = (select id from completeness_ids where key = 'served_request')
      and devotee_id = '30000000-0000-0000-0000-000000000004'
      and status = 'completed'
  ) then
    raise exception 'A devotee lost seva they had already completed.';
  end if;

  if exists (
    select 1 from public.service_assignments
    where service_instance_id = (select id from completeness_ids where key = 'served_request')
      and devotee_id = '30000000-0000-0000-0000-000000000005'
  ) then
    raise exception 'A place nobody completed was left standing on a cancelled seva.';
  end if;

  if not exists (
    select 1 from public.app_notifications
    where user_id = '30000000-0000-0000-0000-000000000005'
      and kind = 'service_deleted'
  ) then
    raise exception 'The devotee holding a cancelled place was never told.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. A request with no history is still removed outright.
-- ---------------------------------------------------------------------------

do $$
declare
  v_instance uuid;
begin
  v_instance := public.create_service_requirement(
    null, 'Completeness unserved request',
    (now() at time zone 'America/Chicago')::date + 3,
    '09:00:00', 60, 1, 'open', '{}'::uuid[]
  );
  perform public.delete_service_requirement(v_instance);
  if exists (select 1 from public.service_instances where id = v_instance) then
    raise exception 'A seva request nobody served was kept as clutter.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. Asking for more access, and hearing back about it.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', '30000000-0000-0000-0000-000000000004', true);

do $$
declare
  v_request public.access_requests;
begin
  -- 0030 requires a reason: it is the whole substance of the decision.
  v_request := public.create_access_request(
    'volunteer', 'I would like to help with kitchen seva every week.',
    '30000000-0000-0000-0000-000000000001'
  );
  insert into completeness_ids values ('access_request', v_request.id);

  if not exists (
    select 1 from public.app_notifications
    where user_id = '30000000-0000-0000-0000-000000000001'
      and kind = 'access_request_submitted'
      and body like '%Volunteer%'
  ) then
    raise exception 'The President was never told a devotee asked for access.';
  end if;
end;
$$;

select set_config('request.jwt.claim.sub', '30000000-0000-0000-0000-000000000001', true);

do $$
begin
  perform public.review_access_request(
    (select id from completeness_ids where key = 'access_request'), 'approved'
  );

  if not exists (
    select 1 from public.users
    where id = '30000000-0000-0000-0000-000000000004'
      and role_id = (select id from public.roles where name = 'volunteer')
  ) then
    raise exception 'Approving an access request did not change the access level.';
  end if;

  if not exists (
    select 1 from public.app_notifications
    where user_id = '30000000-0000-0000-0000-000000000004'
      and kind = 'access_request_reviewed'
      and body like '%Volunteer%'
  ) then
    raise exception 'The devotee was never told their access level changed.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 9. Shortening a weekly seva's run actually removes the later dates.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', '30000000-0000-0000-0000-000000000002', true);

do $$
declare
  v_template uuid := (select id from completeness_ids where key = 'weekly_template');
  v_new_end date := (now() at time zone 'America/Chicago')::date + 10;
  v_live_after integer;
  v_live_within integer;
begin
  perform public.update_service_template_v2(
    v_template, null, 'Completeness weekly garlands', array[1, 4], '17:00:00',
    60, 1, 'invite_only', (now() at time zone 'America/Chicago')::date,
    v_new_end, '{}'::uuid[]
  );

  select count(*) into v_live_after from public.service_instances
  where template_id = v_template
    and date > v_new_end
    and status not in ('cancelled', 'completed');
  if v_live_after <> 0 then
    raise exception '% dates past the new end date are still scheduled.', v_live_after;
  end if;

  select count(*) into v_live_within from public.service_instances
  where template_id = v_template
    and date <= v_new_end
    and date >= (now() at time zone 'America/Chicago')::date
    and status not in ('cancelled', 'completed');
  if v_live_within = 0 then
    raise exception 'Shortening the run removed the dates it should have kept.';
  end if;
end;
$$;

do $$
begin
  raise notice 'all completeness checks passed';
end;
$$;

select 'seva completeness verification passed' as result;

rollback;
