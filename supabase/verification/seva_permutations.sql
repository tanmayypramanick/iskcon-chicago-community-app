-- Every access level against every seva path.
--
-- The other verification files each prove one migration. This one is a matrix:
-- five access levels crossed with the things a devotee can try to do, checking
-- both that the allowed combinations work and that the forbidden ones are
-- refused. Rolled back at the end.
--
-- Every local is prefixed v_ so it can never shadow a column name.
--
-- The final row must read: seva permutation verification passed

begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('50000000-0000-0000-0000-000000000001', 'perm-president@example.test', '{"name":"Perm President"}'),
  ('50000000-0000-0000-0000-000000000002', 'perm-tech@example.test', '{"name":"Perm Tech"}'),
  ('50000000-0000-0000-0000-000000000003', 'perm-core@example.test', '{"name":"Perm Core"}'),
  ('50000000-0000-0000-0000-000000000004', 'perm-volunteer@example.test', '{"name":"Perm Volunteer"}'),
  ('50000000-0000-0000-0000-000000000005', 'perm-devotee@example.test', '{"name":"Perm Devotee"}'),
  ('50000000-0000-0000-0000-000000000006', 'perm-devotee-two@example.test', '{"name":"Perm Devotee Two"}');

update public.users users
set role_id = roles.id
from public.roles roles
where (users.email, roles.name) in (
  ('perm-president@example.test', 'president'),
  ('perm-tech@example.test', 'tech'),
  ('perm-core@example.test', 'core'),
  ('perm-volunteer@example.test', 'volunteer'),
  ('perm-devotee@example.test', 'devotee'),
  ('perm-devotee-two@example.test', 'devotee')
);

create temporary table perm_ids (key text primary key, id uuid not null);

-- A named helper keeps every case below to one readable line.
create or replace function pg_temp.expect_allowed(
  v_actor uuid, v_label text, v_sql text
) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', v_actor::text, true);
  execute v_sql;
exception when others then
  raise exception '% should have been allowed but failed: %', v_label, sqlerrm;
end;
$$;

create or replace function pg_temp.expect_refused(
  v_actor uuid, v_label text, v_sql text
) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', v_actor::text, true);
  begin
    execute v_sql;
  exception when others then
    return;
  end;
  raise exception '% should have been refused but was allowed', v_label;
end;
$$;

-- ---------------------------------------------------------------------------
-- 1. Posting a seva request: who may, and who may not.
-- ---------------------------------------------------------------------------

do $$
declare
  v_tomorrow date := (now() at time zone 'America/Chicago')::date + 1;
begin
  perform pg_temp.expect_allowed(
    '50000000-0000-0000-0000-000000000001', 'President posts an open request',
    format('select public.create_service_requirement(null, %L, %L, %L, 60, 2, %L, %L::uuid[])',
      'Perm president open', v_tomorrow, '09:00:00', 'open', '{}'));
  perform pg_temp.expect_allowed(
    '50000000-0000-0000-0000-000000000003', 'Community Head posts an open request',
    format('select public.create_service_requirement(null, %L, %L, %L, 60, 1, %L, %L::uuid[])',
      'Perm core open', v_tomorrow, '10:00:00', 'open', '{}'));
  perform pg_temp.expect_allowed(
    '50000000-0000-0000-0000-000000000004', 'Volunteer posts an open request',
    format('select public.create_service_requirement(null, %L, %L, %L, 60, 1, %L, %L::uuid[])',
      'Perm volunteer open', v_tomorrow, '11:00:00', 'open', '{}'));
  -- 0015 gave a Volunteer back the ability to invite devotees to what they post.
  perform pg_temp.expect_allowed(
    '50000000-0000-0000-0000-000000000004', 'Volunteer invites a devotee',
    format('select public.create_service_requirement(null, %L, %L, %L, 60, 1, %L, array[%L]::uuid[])',
      'Perm volunteer invite', v_tomorrow, '12:00:00', 'invite_only',
      '50000000-0000-0000-0000-000000000005'));
  -- A Devotee takes part; they do not post.
  perform pg_temp.expect_refused(
    '50000000-0000-0000-0000-000000000005', 'Devotee posts a request',
    format('select public.create_service_requirement(null, %L, %L, %L, 60, 1, %L, %L::uuid[])',
      'Perm devotee open', v_tomorrow, '13:00:00', 'open', '{}'));
  -- Inviting nobody to an invite-only request leaves a request nobody can answer.
  perform pg_temp.expect_refused(
    '50000000-0000-0000-0000-000000000001', 'Invite-only with no invitees',
    format('select public.create_service_requirement(null, %L, %L, %L, 60, 1, %L, %L::uuid[])',
      'Perm empty invite', v_tomorrow, '14:00:00', 'invite_only', '{}'));
  -- More invitations than places.
  perform pg_temp.expect_refused(
    '50000000-0000-0000-0000-000000000001', 'Two invitees for one place',
    format('select public.create_service_requirement(null, %L, %L, %L, 60, 1, %L, array[%L,%L]::uuid[])',
      'Perm over invite', v_tomorrow, '15:00:00', 'invite_only',
      '50000000-0000-0000-0000-000000000005',
      '50000000-0000-0000-0000-000000000006'));
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Weekly seva: only the three coordinator levels may shape one.
-- ---------------------------------------------------------------------------

do $$
declare
  v_today date := (now() at time zone 'America/Chicago')::date;
  v_template uuid;
begin
  perform set_config('request.jwt.claim.sub', '50000000-0000-0000-0000-000000000003', true);
  v_template := public.create_service_template_v2(
    null, 'Perm weekly', array[1, 4], '07:00:00', 60, 1, 'open', v_today, null, '{}'::uuid[]
  );
  insert into perm_ids values ('template', v_template);

  perform pg_temp.expect_refused(
    '50000000-0000-0000-0000-000000000004', 'Volunteer creates weekly seva',
    format('select public.create_service_template_v2(null, %L, array[2], %L, 60, 1, %L, %L, null, %L::uuid[])',
      'Perm volunteer weekly', '08:00:00', 'open', v_today, '{}'));
  perform pg_temp.expect_refused(
    '50000000-0000-0000-0000-000000000005', 'Devotee creates weekly seva',
    format('select public.create_service_template_v2(null, %L, array[2], %L, 60, 1, %L, %L, null, %L::uuid[])',
      'Perm devotee weekly', '08:00:00', 'open', v_today, '{}'));
  perform pg_temp.expect_refused(
    '50000000-0000-0000-0000-000000000004', 'Volunteer pauses weekly seva',
    format('select public.set_service_template_active(%L, false)', v_template));
  perform pg_temp.expect_allowed(
    '50000000-0000-0000-0000-000000000002', 'Tech Admin pauses weekly seva',
    format('select public.set_service_template_active(%L, false)', v_template));
  perform pg_temp.expect_allowed(
    '50000000-0000-0000-0000-000000000002', 'Tech Admin resumes weekly seva',
    format('select public.set_service_template_active(%L, true)', v_template));
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Joining: an open seva is open, an invite-only one is not.
-- ---------------------------------------------------------------------------

-- 'open' is section 4's seva as well as this one's, and section 4 completes it,
-- so 202608040070 requires its hour to have GONE, not merely to have begun.
--
-- Nothing posted today can satisfy that at five past midnight, and no
-- arithmetic over the elapsed day can rescue it: create_service_requirement
-- refuses a date in the past and refuses any duration under 30 minutes, and at
-- 00:05 today does not contain a finished 30-minute seva. Clamping the start to
-- midnight only moved the failure from "before 02:00" to "before 01:00".
--
-- So the request is posted through the real RPC, for the earliest date that RPC
-- accepts, and the fixture then moves that one row back a day. Yesterday's
-- 09:00 seva, over at 10:00, is what a poster is closing out in the temple
-- anyway, and it has ended at every hour of every day rather than at most of
-- them. Joining carries no clock of its own, so nothing in this section
-- notices, and section 4 is left testing authority and nothing else.
do $$
declare
  v_open uuid;
  v_closed uuid;
  v_today date := (now() at time zone 'America/Chicago')::date;
  v_tomorrow date := v_today + 1;
  v_opens_at timestamptz;
begin
  perform set_config('request.jwt.claim.sub', '50000000-0000-0000-0000-000000000001', true);
  v_open := public.create_service_requirement(
    null, 'Perm join open', v_today, '09:00:00', 60, 2, 'open', '{}'::uuid[]);
  v_closed := public.create_service_requirement(
    null, 'Perm join closed', v_tomorrow, '17:00:00', 60, 1, 'invite_only',
    array['50000000-0000-0000-0000-000000000006'::uuid]);
  insert into perm_ids values ('open', v_open), ('closed', v_closed);

  -- The move, and only for the seva section 4 closes out. 'closed' stays where
  -- it was posted: section 5 reshapes and removes a request that has not
  -- happened yet, which is the case that matters there.
  update public.service_instances instances
  set date = v_today - 1
  where instances.id = v_open;

  -- Said out loud, because expect_refused below swallows every reason alike:
  -- this seva has FINISHED — asked of the three-argument bar, which knows how
  -- long the seva is, rather than of the two-argument one, which is the same
  -- clock asked about a seva of no length and would have said yes at 09:01.
  select public.seva_completion_opens_at(
           instances.date, instances.start_time, instances.duration_minutes)
    into v_opens_at
  from public.service_instances instances
  where instances.id = v_open;

  if v_opens_at > now() then
    raise exception
      'The seva section 4 completes cannot be completed until %; the Chicago arithmetic is wrong.',
      v_opens_at;
  end if;

  perform pg_temp.expect_allowed(
    '50000000-0000-0000-0000-000000000005', 'Devotee joins an open seva',
    format('select public.join_service_instance(%L)', v_open));
  perform pg_temp.expect_refused(
    '50000000-0000-0000-0000-000000000005', 'Devotee joins an invite-only seva',
    format('select public.join_service_instance(%L)', v_closed));

  -- Joining twice is harmless; the place is theirs either way.
  perform pg_temp.expect_allowed(
    '50000000-0000-0000-0000-000000000005', 'Devotee joins the same seva twice',
    format('select public.join_service_instance(%L)', v_open));

  -- Second devotee takes the last place; a third finds it full.
  perform pg_temp.expect_allowed(
    '50000000-0000-0000-0000-000000000006', 'Second devotee takes the last place',
    format('select public.join_service_instance(%L)', v_open));
  perform pg_temp.expect_refused(
    '50000000-0000-0000-0000-000000000004', 'Third devotee joins a full seva',
    format('select public.join_service_instance(%L)', v_open));
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Completing: the poster and the two override levels, nobody else.
-- ---------------------------------------------------------------------------

do $$
declare
  v_instance uuid := (select id from perm_ids where key = 'open');
begin
  perform pg_temp.expect_refused(
    '50000000-0000-0000-0000-000000000005', 'Participant completes the whole seva',
    format('select public.complete_service_instance(%L)', v_instance));
  -- 0023: a Community Head no longer closes somebody else's request.
  perform pg_temp.expect_refused(
    '50000000-0000-0000-0000-000000000003', 'Community Head completes another''s seva',
    format('select public.complete_service_instance(%L)', v_instance));
  perform pg_temp.expect_allowed(
    '50000000-0000-0000-0000-000000000001', 'The poster completes their seva',
    format('select public.complete_service_instance(%L)', v_instance));
  perform pg_temp.expect_refused(
    '50000000-0000-0000-0000-000000000001', 'Completing an already finished seva',
    format('select public.complete_service_instance(%L)', v_instance));
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Reshaping and removing a request.
-- ---------------------------------------------------------------------------

do $$
declare
  v_instance uuid := (select id from perm_ids where key = 'closed');
begin
  perform pg_temp.expect_refused(
    '50000000-0000-0000-0000-000000000003', 'Community Head reshapes another''s request',
    format('select public.update_service_requirement(%L, %L, 1, %L::uuid[])',
      v_instance, 'open', '{}'));
  perform pg_temp.expect_refused(
    '50000000-0000-0000-0000-000000000005', 'Devotee reshapes a request',
    format('select public.update_service_requirement(%L, %L, 1, %L::uuid[])',
      v_instance, 'open', '{}'));
  perform pg_temp.expect_allowed(
    '50000000-0000-0000-0000-000000000002', 'Tech Admin reshapes any request',
    format('select public.update_service_requirement(%L, %L, 2, %L::uuid[])',
      v_instance, 'open', '{}'));
  perform pg_temp.expect_refused(
    '50000000-0000-0000-0000-000000000005', 'Devotee removes a request',
    format('select public.delete_service_requirement(%L)', v_instance));
  perform pg_temp.expect_allowed(
    '50000000-0000-0000-0000-000000000001', 'The poster removes their request',
    format('select public.delete_service_requirement(%L)', v_instance));
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Registering seva and verifying it.
-- ---------------------------------------------------------------------------

do $$
declare
  v_registration public.service_verifications;
begin
  perform set_config('request.jwt.claim.sub', '50000000-0000-0000-0000-000000000005', true);
  v_registration := public.request_seva_verification(
    null, 'Perm registered seva', now() + interval '1 hour', now() + interval '2 hours',
    'Temple room', '50000000-0000-0000-0000-000000000003', null
  );
  insert into perm_ids values ('registration', v_registration.id);

  -- The verifier must be a coordinator, and never the devotee themselves.
  perform pg_temp.expect_refused(
    '50000000-0000-0000-0000-000000000005', 'Naming a Devotee as verifier',
    format('select public.request_seva_verification(null, %L, now() + interval ''5 hours'', now() + interval ''6 hours'', %L, %L, null)',
      'Perm bad verifier', 'Temple room', '50000000-0000-0000-0000-000000000006'));
  perform pg_temp.expect_refused(
    '50000000-0000-0000-0000-000000000005', 'Naming yourself as verifier',
    format('select public.request_seva_verification(null, %L, now() + interval ''7 hours'', now() + interval ''8 hours'', %L, %L, null)',
      'Perm self verify', 'Temple room', '50000000-0000-0000-0000-000000000005'));
  -- Seva that already finished cannot be registered.
  perform pg_temp.expect_refused(
    '50000000-0000-0000-0000-000000000005', 'Registering seva already over',
    format('select public.request_seva_verification(null, %L, now() - interval ''3 hours'', now() - interval ''2 hours'', %L, %L, null)',
      'Perm past seva', 'Temple room', '50000000-0000-0000-0000-000000000003'));
  -- Overlapping their own registration is ALLOWED: the clash is reported to
  -- the devotee and the choice is theirs ("only accept if you manage to
  -- serve"). 202608310081 removed the constraint that used to refuse this.
  perform pg_temp.expect_allowed(
    '50000000-0000-0000-0000-000000000005', 'Registering overlapping seva',
    format('select public.request_seva_verification(null, %L, now() + interval ''90 minutes'', now() + interval ''3 hours'', %L, %L, null)',
      'Perm overlap', 'Temple room', '50000000-0000-0000-0000-000000000003'));

  -- Only the named member, a Tech Admin or the President may answer.
  perform pg_temp.expect_refused(
    '50000000-0000-0000-0000-000000000006', 'An uninvolved devotee verifies',
    format('select public.respond_to_seva_verification(%L, true, null)', v_registration.id));
  perform pg_temp.expect_allowed(
    '50000000-0000-0000-0000-000000000002', 'Tech Admin overrides and verifies',
    format('select public.respond_to_seva_verification(%L, true, null)', v_registration.id));
  perform pg_temp.expect_refused(
    '50000000-0000-0000-0000-000000000003', 'Answering an already verified seva',
    format('select public.respond_to_seva_verification(%L, false, null)', v_registration.id));
end;
$$;

-- A Tech Admin's override reaches every registration except their own.
do $$
declare
  v_own public.service_verifications;
begin
  perform set_config('request.jwt.claim.sub', '50000000-0000-0000-0000-000000000002', true);
  v_own := public.request_seva_verification(
    null, 'Perm tech own seva', now() + interval '1 hour', now() + interval '2 hours',
    'Temple room', '50000000-0000-0000-0000-000000000003', null
  );

  perform pg_temp.expect_refused(
    '50000000-0000-0000-0000-000000000002', 'Tech Admin verifies their own seva',
    format('select public.respond_to_seva_verification(%L, true, null)', v_own.id));
  perform pg_temp.expect_refused(
    '50000000-0000-0000-0000-000000000001', 'President verifies their own seva',
    format('select public.respond_to_seva_verification(%L, true, null)',
      (select id from public.service_verifications
       where devotee_id = '50000000-0000-0000-0000-000000000001' limit 1)));
  -- The member actually named still can.
  perform pg_temp.expect_allowed(
    '50000000-0000-0000-0000-000000000003', 'The named member verifies it',
    format('select public.respond_to_seva_verification(%L, true, null)', v_own.id));
end;
$$;

-- A verified registration is a record: a Community Head may not erase it.
do $$
begin
  perform pg_temp.expect_refused(
    '50000000-0000-0000-0000-000000000003', 'Community Head deletes verified seva',
    format('select public.delete_seva_registration(%L)', (select id from perm_ids where key = 'registration')));
  perform pg_temp.expect_allowed(
    '50000000-0000-0000-0000-000000000005', 'The devotee removes their own verified seva',
    format('select public.delete_seva_registration(%L)', (select id from perm_ids where key = 'registration')));
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Reporting unavailability and arranging cover.
-- ---------------------------------------------------------------------------

do $$
declare
  v_template uuid := (select id from perm_ids where key = 'template');
  v_monday date;
  v_group uuid;
  v_exception uuid;
begin
  perform set_config('request.jwt.claim.sub', '50000000-0000-0000-0000-000000000005', true);
  perform public.join_weekly_service(v_template);

  select min(instances.date) into v_monday
  from public.service_instances instances
  join public.service_assignments assignments
    on assignments.service_instance_id = instances.id
   and assignments.devotee_id = '50000000-0000-0000-0000-000000000005'
   and assignments.status in ('assigned', 'confirmed')
  where instances.template_id = v_template;
  if v_monday is null then
    raise exception 'setup: joining the weekly seva assigned nothing.';
  end if;

  v_group := public.report_weekly_service_unavailable(
    v_template, 'occurrence', v_monday, null,
    array[extract(dow from v_monday)::integer], 'Away'
  );
  select id into v_exception from public.service_exceptions
  where request_group_id = v_group and status = 'pending' limit 1;
  insert into perm_ids values ('exception', v_exception);

  -- Only the three coordinator levels arrange cover.
  perform pg_temp.expect_refused(
    '50000000-0000-0000-0000-000000000004', 'Volunteer arranges cover',
    format('select public.offer_service_coverage_range(%L, %L, %L, %L, %L)',
      v_exception, '50000000-0000-0000-0000-000000000006', 'occurrence', v_monday, v_monday));
  perform pg_temp.expect_refused(
    '50000000-0000-0000-0000-000000000005', 'Devotee arranges cover',
    format('select public.offer_service_coverage_range(%L, %L, %L, %L, %L)',
      v_exception, '50000000-0000-0000-0000-000000000006', 'occurrence', v_monday, v_monday));
  perform pg_temp.expect_allowed(
    '50000000-0000-0000-0000-000000000003', 'Community Head arranges cover',
    format('select public.offer_service_coverage_range(%L, %L, %L, %L, %L)',
      v_exception, '50000000-0000-0000-0000-000000000006', 'occurrence', v_monday, v_monday));
  -- Asking the same devotee again while they are deciding.
  perform pg_temp.expect_refused(
    '50000000-0000-0000-0000-000000000003', 'Asking the same devotee twice',
    format('select public.offer_service_coverage_range(%L, %L, %L, %L, %L)',
      v_exception, '50000000-0000-0000-0000-000000000006', 'occurrence', v_monday, v_monday));
  -- Asking the devotee who reported unavailable to cover themselves.
  perform pg_temp.expect_refused(
    '50000000-0000-0000-0000-000000000003', 'Asking the reporter to cover themselves',
    format('select public.offer_service_coverage_range(%L, %L, %L, %L, %L)',
      v_exception, '50000000-0000-0000-0000-000000000005', 'occurrence', v_monday, v_monday));
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. Every notification landed on somebody real, with a kind the app knows.
-- ---------------------------------------------------------------------------

do $$
declare
  v_orphans integer;
  v_blank integer;
begin
  select count(*) into v_orphans
  from public.app_notifications notifications
  where not exists (select 1 from public.users where id = notifications.user_id);
  if v_orphans > 0 then
    raise exception '% notifications were sent to a user that does not exist.', v_orphans;
  end if;

  select count(*) into v_blank
  from public.app_notifications
  where coalesce(trim(title), '') = '' or coalesce(trim(body), '') = '';
  if v_blank > 0 then
    raise exception '% notifications have no title or no body.', v_blank;
  end if;
end;
$$;

-- Nobody is told about their own action.
do $$
declare
  v_self integer;
begin
  select count(*) into v_self
  from public.app_notifications notifications
  join public.service_instances instances
    on instances.id = (notifications.data ->> 'serviceInstanceId')::uuid
  where notifications.kind in ('service_joined', 'service_left')
    and instances.posted_by = notifications.user_id
    and notifications.body like '%' || (
      select name from public.users where id = notifications.user_id
    ) || '%';
  if v_self > 0 then
    raise exception '% notifications tell a devotee about their own action.', v_self;
  end if;
end;
$$;

do $$
begin
  raise notice 'all permutation checks passed';
end;
$$;

select 'seva permutation verification passed' as result;

rollback;
