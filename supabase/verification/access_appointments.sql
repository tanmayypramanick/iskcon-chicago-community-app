-- Functional verification for 202608040047_access_appointments.sql.
--
-- Rolled back at the end. Every local is prefixed v_ so it can never shadow a
-- column name. Anything that must be refused is attempted as the devotee who
-- would really attempt it, under `set local role authenticated`, so the row
-- level security policies and the column grants are the thing being tested
-- rather than superuser rights quietly waving everything through. Notification
-- assertions are made after `reset role`, because a devotee cannot — and should
-- not be able to — read somebody else's inbox.
--
-- The nine people in this script:
--   President  ...0001  appoints and revokes anybody
--   Head A     ...0002  Community Head; appoints, and may revoke only her own
--   Head B     ...0003  the other Community Head, whose grants Head A must not
--                       be able to touch
--   Devotee A  ...0004  appointed by Head A and revoked by Head A
--   Devotee B  ...0005  appointed by Head B; Head A must be refused
--   Volunteer  ...0006  holds Volunteer with no grant behind it (set before
--                       this record existed) — must not be able to appoint,
--                       and no Community Head may revoke him
--   Devotee C  ...0007  the President's appointee, then the request flow
--   Tech       ...0008  the other office holder; nobody may move him
--   Devotee D  ...0009  appointed by Head B and raised by Head A
--
-- The final row must read: access appointments verification passed

begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('a7000000-0000-0000-0000-000000000001', 'ap-president@example.test', '{"name":"Ap President"}'),
  ('a7000000-0000-0000-0000-000000000002', 'ap-head-a@example.test', '{"name":"Ap Head A"}'),
  ('a7000000-0000-0000-0000-000000000003', 'ap-head-b@example.test', '{"name":"Ap Head B"}'),
  ('a7000000-0000-0000-0000-000000000004', 'ap-devotee-a@example.test', '{"name":"Ap Devotee A"}'),
  ('a7000000-0000-0000-0000-000000000005', 'ap-devotee-b@example.test', '{"name":"Ap Devotee B"}'),
  ('a7000000-0000-0000-0000-000000000006', 'ap-volunteer@example.test', '{"name":"Ap Volunteer"}'),
  ('a7000000-0000-0000-0000-000000000007', 'ap-devotee-c@example.test', '{"name":"Ap Devotee C"}'),
  ('a7000000-0000-0000-0000-000000000008', 'ap-tech@example.test', '{"name":"Ap Tech"}'),
  ('a7000000-0000-0000-0000-000000000009', 'ap-devotee-d@example.test', '{"name":"Ap Devotee D"}');

update public.users
set role_id = (select roles.id from public.roles where roles.name = 'president')
where email = 'ap-president@example.test';

update public.users
set role_id = (select roles.id from public.roles where roles.name = 'tech')
where email = 'ap-tech@example.test';

update public.users
set role_id = (select roles.id from public.roles where roles.name = 'core')
where email in ('ap-head-a@example.test', 'ap-head-b@example.test');

-- Set by hand, the way somebody's access was set before this record existed:
-- a Volunteer with no grant row behind him.
update public.users
set role_id = (select roles.id from public.roles where roles.name = 'volunteer')
where email = 'ap-volunteer@example.test';

-- Ordinary table rather than a temporary one, so reading it under the
-- authenticated role needs no assumptions about the temp schema. The whole
-- script is rolled back, so it never outlives the transaction.
create table public.access_appointment_test_ids (key text primary key, id uuid not null);
grant select, insert on public.access_appointment_test_ids to authenticated;

-- ---------------------------------------------------------------------------
-- 0. The ladder this feature assumes is still the ladder that exists.
--
--    Every guard below is written in terms of two permission keys. If a later
--    migration hands services.manage_recurring to Volunteers, or adds a sixth
--    rung, the rules in this file quietly mean something else and every test
--    would still pass.
-- ---------------------------------------------------------------------------

do $$
declare
  v_roles text;
  v_appointers text;
  v_reviewers text;
begin
  select string_agg(roles.name, ',' order by roles.name) into v_roles
  from public.roles;
  if v_roles is distinct from 'core,devotee,president,tech,volunteer' then
    raise exception 'The role ladder is now % — a rung was added or removed.', v_roles;
  end if;

  select string_agg(roles.name, ',' order by roles.name) into v_appointers
  from public.role_permissions
  join public.roles on roles.id = role_permissions.role_id
  where role_permissions.permission_key = 'services.manage_recurring';
  if v_appointers is distinct from 'core,president,tech' then
    raise exception
      'services.manage_recurring is held by % — appointment assumes core, president, tech.',
      v_appointers;
  end if;

  select string_agg(roles.name, ',' order by roles.name) into v_reviewers
  from public.role_permissions
  join public.roles on roles.id = role_permissions.role_id
  where role_permissions.permission_key = 'access.review_requests';
  if v_reviewers is distinct from 'president,tech' then
    raise exception
      'access.review_requests is held by % — appointment assumes president, tech.',
      v_reviewers;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 0b. Every notification kind that existed before this migration still exists
--     after it.
--
--     app_notifications_kind_check cannot be altered, only dropped and
--     recreated, so each migration that adds a kind has to restate the whole
--     list — and a migration that restates it from an older copy silently
--     outlaws every kind added since. That has broken this database four times.
--     The two new kinds are checked alongside them, so the constraint and
--     src/features/notifications/types.ts can be read against one list.
--
--     Each kind is inserted for real rather than pattern-matched against
--     pg_get_constraintdef, because what matters is whether the database will
--     accept the row at 3am, not whether the text of the constraint mentions it.
-- ---------------------------------------------------------------------------

do $$
declare
  v_kind text;
  v_missing text[] := '{}';
begin
  foreach v_kind in array array[
    'service_open', 'service_offer', 'service_recurring_offer',
    'service_offer_response', 'service_joined', 'service_left',
    'service_started', 'service_completed', 'service_cancelled',
    'service_deleted', 'service_coverage_needed',
    'service_coverage_resolved', 'recurring_interest_submitted',
    'recurring_interest_reviewed',
    'seva_verification_requested', 'seva_verification_reviewed',
    'weekly_offer_countered', 'weekly_offer_counter_reviewed',
    'access_request_submitted', 'access_request_reviewed',
    'devotee_joined', 'profile_incomplete',
    'sanga_created', 'sanga_reviewed',
    'sanga_join_requested', 'sanga_join_reviewed',
    'sanga_member_added', 'sanga_member_removed', 'sanga_member_left',
    'sanga_admin_transferred', 'sanga_deleted',
    'announcement_posted',
    'feedback_reviewed',
    'care_reply',
    'birthday_today',
    'newsletter_posted',
    'newsletter_reviewed',
    'access_appointed',
    'access_revoked',
    'remote'
  ]
  loop
    begin
      insert into public.app_notifications (user_id, kind, title, body)
      values ('a7000000-0000-0000-0000-000000000001', v_kind, 'probe', 'probe');
    exception when check_violation then
      v_missing := v_missing || v_kind;
    end;
  end loop;

  if cardinality(v_missing) > 0 then
    raise exception
      'The kind constraint no longer accepts %. It was restated from an older copy.',
      array_to_string(v_missing, ', ');
  end if;

  -- The probes must not be mistaken for anything this feature sent.
  delete from public.app_notifications where title = 'probe' and body = 'probe';
end;
$$;

-- ---------------------------------------------------------------------------
-- 1. A plain devotee and a Volunteer can do neither thing.
--
--    A Volunteer is the interesting half: he is on the ladder, he holds four
--    service permissions, and he must still be as powerless here as somebody
--    who joined this morning.
-- ---------------------------------------------------------------------------

do $$
declare
  v_who record;
  v_message text;
begin
  for v_who in
    select * from (values
      ('a7000000-0000-0000-0000-000000000007'::uuid, 'A plain devotee'),
      ('a7000000-0000-0000-0000-000000000006'::uuid, 'A Volunteer')
    ) as caller(id, label)
  loop
    perform set_config('request.jwt.claim.sub', v_who.id::text, true);
    execute 'set local role authenticated';

    if public.may_appoint_access() then
      raise exception '% may appoint access.', v_who.label;
    end if;

    v_message := null;
    begin
      perform public.appoint_access(
        'a7000000-0000-0000-0000-000000000004', 'volunteer', 'because I say so'
      );
    exception when others then
      v_message := sqlerrm;
    end;
    if v_message is null then
      raise exception '% appointed a Volunteer.', v_who.label;
    end if;
    if v_message not like '%Community Head%' then
      raise exception 'Refusing % said "%", not the readable guard.', v_who.label, v_message;
    end if;

    v_message := null;
    begin
      perform public.revoke_access('a7000000-0000-0000-0000-000000000006', null);
    exception when others then
      v_message := sqlerrm;
    end;
    if v_message is null then
      raise exception '% revoked somebody''s access.', v_who.label;
    end if;
    -- The refusal must be the one about rank. Anything else means they got
    -- past the door and were stopped by a rule that happens to also apply.
    if v_message not like 'Only a Community Head%' then
      raise exception 'Refusing a revocation by % said "%".', v_who.label, v_message;
    end if;

    execute 'reset role';
  end loop;
end;
$$;

reset role;

do $$
begin
  if exists (
    select 1 from public.access_appointments
    where access_appointments.devotee_id = 'a7000000-0000-0000-0000-000000000004'
  ) then
    raise exception 'A refused appointment still wrote a row into the record.';
  end if;
  if (
    select roles.name from public.users
    join public.roles on roles.id = users.role_id
    where users.id = 'a7000000-0000-0000-0000-000000000004'
  ) <> 'devotee' then
    raise exception 'A refused appointment still changed the devotee''s access level.';
  end if;
  if (
    select roles.name from public.users
    join public.roles on roles.id = users.role_id
    where users.id = 'a7000000-0000-0000-0000-000000000006'
  ) <> 'volunteer' then
    raise exception 'A refused revocation still changed the Volunteer''s access level.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. The President appoints, promotes and revokes — and is refused the three
--    things nobody may do.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'a7000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
  v_grant public.access_appointments;
  v_again public.access_appointments;
  v_promoted public.access_appointments;
  v_message text;
  v_bad text;
begin
  v_grant := public.appoint_access(
    'a7000000-0000-0000-0000-000000000007', 'volunteer', '  Runs the book table.  '
  );

  if v_grant.id is null then
    raise exception 'The President could not appoint a Volunteer.';
  end if;
  if v_grant.appointed_by <> 'a7000000-0000-0000-0000-000000000001' then
    raise exception 'The grant did not record who made it.';
  end if;
  if v_grant.note <> 'Runs the book table.' then
    raise exception 'The note was not trimmed: [%].', v_grant.note;
  end if;
  if v_grant.source <> 'appointment' or v_grant.revoked_at is not null then
    raise exception 'A fresh grant came back as % / revoked %.', v_grant.source, v_grant.revoked_at;
  end if;
  if (
    select roles.name from public.users
    join public.roles on roles.id = users.role_id
    where users.id = 'a7000000-0000-0000-0000-000000000007'
  ) <> 'volunteer' then
    raise exception 'The appointment did not change the devotee''s access level.';
  end if;

  -- Doing it twice is the same grant, not a second one with today's date.
  v_again := public.appoint_access('a7000000-0000-0000-0000-000000000007', 'volunteer');
  if v_again.id <> v_grant.id or v_again.appointed_at <> v_grant.appointed_at then
    raise exception 'Re-appointing the same access started a new grant.';
  end if;

  -- Raising them. The old grant ends as superseded, not as a revocation.
  v_promoted := public.appoint_access(
    'a7000000-0000-0000-0000-000000000007', 'core', 'Kitchen coordinator.'
  );
  if v_promoted.id = v_grant.id then
    raise exception 'Promoting somebody rewrote the grant instead of starting a new one.';
  end if;
  select revoke_reason into v_bad from public.access_appointments
  where access_appointments.id = v_grant.id;
  if v_bad is distinct from 'superseded' then
    raise exception 'The replaced grant ended as [%] rather than superseded.', v_bad;
  end if;
  if (
    select roles.name from public.users
    join public.roles on roles.id = users.role_id
    where users.id = 'a7000000-0000-0000-0000-000000000007'
  ) <> 'core' then
    raise exception 'The promotion did not change the devotee''s access level.';
  end if;

  insert into public.access_appointment_test_ids values
    ('c-volunteer-grant', v_grant.id),
    ('c-core-grant', v_promoted.id);

  -- Nobody appoints themselves.
  v_message := null;
  begin
    perform public.appoint_access('a7000000-0000-0000-0000-000000000001', 'core');
  exception when others then
    v_message := sqlerrm;
  end;
  if v_message is null then
    raise exception 'The President appointed themselves.';
  end if;
  if v_message not like '%your own%' then
    raise exception 'Refusing self-appointment said "%".', v_message;
  end if;

  -- Nobody appoints to president or tech, and revocation is the only road to
  -- Devotee.
  foreach v_bad in array array['president', 'tech', 'devotee'] loop
    v_message := null;
    begin
      perform public.appoint_access('a7000000-0000-0000-0000-000000000007', v_bad);
    exception when others then
      v_message := sqlerrm;
    end;
    if v_message is null then
      raise exception 'The President appointed somebody to %.', v_bad;
    end if;
    if v_message not like '%Volunteer or Community Head%' then
      raise exception 'Refusing an appointment to % said "%".', v_bad, v_message;
    end if;
  end loop;

  -- An office holder cannot be moved through this door at all.
  v_message := null;
  begin
    perform public.appoint_access('a7000000-0000-0000-0000-000000000008', 'volunteer');
  exception when others then
    v_message := sqlerrm;
  end;
  if v_message is null then
    raise exception 'The Tech Admin was appointed to Volunteer.';
  end if;
  if v_message not like '%outside the app%' then
    raise exception 'Refusing to move the Tech Admin said "%".', v_message;
  end if;

  v_message := null;
  begin
    perform public.revoke_access('a7000000-0000-0000-0000-000000000008', null);
  exception when others then
    v_message := sqlerrm;
  end;
  if v_message is null then
    raise exception 'The President revoked the Tech Admin.';
  end if;
end;
$$;

-- Taking it back, from somebody the President appointed.
do $$
declare
  v_ended public.access_appointments;
begin
  v_ended := public.revoke_access(
    'a7000000-0000-0000-0000-000000000007', '  Stepping back for a year.  '
  );

  if v_ended.revoked_by <> 'a7000000-0000-0000-0000-000000000001' then
    raise exception 'The revocation did not record who made it.';
  end if;
  if v_ended.revoke_reason <> 'revoked' then
    raise exception 'A revocation was recorded as [%].', v_ended.revoke_reason;
  end if;
  if v_ended.revoke_note <> 'Stepping back for a year.' then
    raise exception 'The revocation note was not trimmed: [%].', v_ended.revoke_note;
  end if;
  if (
    select roles.name from public.users
    join public.roles on roles.id = users.role_id
    where users.id = 'a7000000-0000-0000-0000-000000000007'
  ) <> 'devotee' then
    raise exception 'Revoking did not return the devotee to Devotee.';
  end if;
  if exists (
    select 1 from public.access_appointments
    where access_appointments.devotee_id = 'a7000000-0000-0000-0000-000000000007'
      and access_appointments.revoked_at is null
  ) then
    raise exception 'A revoked devotee still has a live grant.';
  end if;
end;
$$;

reset role;

do $$
begin
  if not exists (
    select 1 from public.app_notifications
    where app_notifications.user_id = 'a7000000-0000-0000-0000-000000000007'
      and app_notifications.kind = 'access_appointed'
      and app_notifications.body like '%Ap President%'
      and app_notifications.body like '%Community Head%'
  ) then
    raise exception 'The devotee was not told who appointed them.';
  end if;

  if not exists (
    select 1 from public.app_notifications
    where app_notifications.user_id = 'a7000000-0000-0000-0000-000000000007'
      and app_notifications.kind = 'access_revoked'
      and app_notifications.body like '%Ap President%'
  ) then
    raise exception 'The devotee was not told their access had been taken back.';
  end if;

  if exists (
    select 1 from public.app_notifications
    where app_notifications.user_id = 'a7000000-0000-0000-0000-000000000001'
      and app_notifications.kind in ('access_appointed', 'access_revoked')
  ) then
    raise exception 'The appointer was notified about their own decision.';
  end if;

  -- The other coordinators hear about it; a Volunteer and a plain devotee do not.
  if not exists (
    select 1 from public.app_notifications
    where app_notifications.user_id = 'a7000000-0000-0000-0000-000000000002'
      and app_notifications.kind = 'access_appointed'
      and app_notifications.body like '%Ap Devotee C%'
  ) then
    raise exception 'A Community Head was not told that an access level changed.';
  end if;
  if exists (
    select 1 from public.app_notifications
    where app_notifications.user_id in (
        'a7000000-0000-0000-0000-000000000006',
        'a7000000-0000-0000-0000-000000000004'
      )
      and app_notifications.kind in ('access_appointed', 'access_revoked')
  ) then
    raise exception 'Somebody outside the coordinators was told about an appointment.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. A Community Head appoints.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'a7000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_grant public.access_appointments;
  v_message text;
begin
  if not public.may_appoint_access() then
    raise exception 'A Community Head may not appoint access.';
  end if;

  v_grant := public.appoint_access(
    'a7000000-0000-0000-0000-000000000004', 'volunteer', 'Sunday kitchen, every week.'
  );
  if v_grant.appointed_by <> 'a7000000-0000-0000-0000-000000000002' then
    raise exception 'The Community Head''s grant did not record her.';
  end if;
  if (
    select roles.name from public.users
    join public.roles on roles.id = users.role_id
    where users.id = 'a7000000-0000-0000-0000-000000000004'
  ) <> 'volunteer' then
    raise exception 'A Community Head''s appointment did not take effect.';
  end if;
  insert into public.access_appointment_test_ids values ('a-grant', v_grant.id);

  -- A Community Head may appoint another Community Head.
  v_grant := public.appoint_access('a7000000-0000-0000-0000-000000000009', 'volunteer');
  insert into public.access_appointment_test_ids values ('d-first-grant', v_grant.id);

  -- And is refused the same three things the President was.
  v_message := null;
  begin
    perform public.appoint_access('a7000000-0000-0000-0000-000000000002', 'core');
  exception when others then
    v_message := sqlerrm;
  end;
  if v_message is null then
    raise exception 'A Community Head appointed herself.';
  end if;

  v_message := null;
  begin
    perform public.appoint_access('a7000000-0000-0000-0000-000000000004', 'president');
  exception when others then
    v_message := sqlerrm;
  end;
  if v_message is null then
    raise exception 'A Community Head appointed somebody President.';
  end if;

  v_message := null;
  begin
    perform public.appoint_access('a7000000-0000-0000-0000-000000000001', 'volunteer');
  exception when others then
    v_message := sqlerrm;
  end;
  if v_message is null then
    raise exception 'A Community Head moved the President.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'a7000000-0000-0000-0000-000000000003', true);
set local role authenticated;

do $$
declare
  v_grant public.access_appointments;
begin
  v_grant := public.appoint_access('a7000000-0000-0000-0000-000000000005', 'core', 'Youth group.');
  insert into public.access_appointment_test_ids values ('b-grant', v_grant.id);
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. A Community Head revokes her own appointee, and nobody else's.
--
--    Four refusals, and the third and fourth are the ones that would be easy
--    to lose: a Head may not walk down another Head's grant through
--    appoint_access either, and may not touch an office holder at all.
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', 'a7000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_ended public.access_appointments;
  v_message text;
begin
  -- Her own: allowed.
  v_ended := public.revoke_access('a7000000-0000-0000-0000-000000000004', 'Moved away.');
  if v_ended.revoked_by <> 'a7000000-0000-0000-0000-000000000002' then
    raise exception 'A Community Head''s revocation did not record her.';
  end if;
  if (
    select roles.name from public.users
    join public.roles on roles.id = users.role_id
    where users.id = 'a7000000-0000-0000-0000-000000000004'
  ) <> 'devotee' then
    raise exception 'A Community Head''s revocation did not take effect.';
  end if;

  -- Another Head's appointee: refused.
  v_message := null;
  begin
    perform public.revoke_access('a7000000-0000-0000-0000-000000000005', null);
  exception when others then
    v_message := sqlerrm;
  end;
  if v_message is null then
    raise exception 'A Community Head revoked another Community Head''s appointee.';
  end if;
  if v_message not like '%granted themselves%' then
    raise exception 'Refusing the cross-Head revocation said "%".', v_message;
  end if;

  -- The President: refused.
  v_message := null;
  begin
    perform public.revoke_access('a7000000-0000-0000-0000-000000000001', null);
  exception when others then
    v_message := sqlerrm;
  end;
  if v_message is null then
    raise exception 'A Community Head revoked the President.';
  end if;
  if v_message not like '%outside the app%' then
    raise exception 'Refusing to revoke the President said "%".', v_message;
  end if;

  -- The Tech Admin: refused.
  v_message := null;
  begin
    perform public.revoke_access('a7000000-0000-0000-0000-000000000008', null);
  exception when others then
    v_message := sqlerrm;
  end;
  if v_message is null then
    raise exception 'A Community Head revoked the Tech Admin.';
  end if;

  -- Access nobody is recorded as having granted: refused.
  v_message := null;
  begin
    perform public.revoke_access('a7000000-0000-0000-0000-000000000006', null);
  exception when others then
    v_message := sqlerrm;
  end;
  if v_message is null then
    raise exception 'A Community Head revoked a grant nobody made.';
  end if;

  -- Walking another Head's grant down is a revocation wearing a promotion's
  -- clothes, and is refused as one.
  v_message := null;
  begin
    perform public.appoint_access('a7000000-0000-0000-0000-000000000005', 'volunteer');
  exception when others then
    v_message := sqlerrm;
  end;
  if v_message is null then
    raise exception 'A Community Head demoted another Community Head''s appointee.';
  end if;
  if v_message not like '%granted themselves%' then
    raise exception 'Refusing the cross-Head demotion said "%".', v_message;
  end if;
  if (
    select roles.name from public.users
    join public.roles on roles.id = users.role_id
    where users.id = 'a7000000-0000-0000-0000-000000000005'
  ) <> 'core' then
    raise exception 'A refused demotion still changed the devotee''s access level.';
  end if;

  -- Raising somebody another Head appointed is an appointment, and is allowed.
  perform public.appoint_access('a7000000-0000-0000-0000-000000000009', 'core');
  if (
    select roles.name from public.users
    join public.roles on roles.id = users.role_id
    where users.id = 'a7000000-0000-0000-0000-000000000009'
  ) <> 'core' then
    raise exception 'A Community Head could not raise another''s appointee.';
  end if;

  -- Somebody already at Devotee: a readable refusal, not a silent success.
  v_message := null;
  begin
    perform public.revoke_access('a7000000-0000-0000-0000-000000000007', null);
  exception when others then
    v_message := sqlerrm;
  end;
  if v_message is null then
    raise exception 'Revoking a plain devotee was accepted.';
  end if;
  if v_message not like '%already%' then
    raise exception 'Refusing to revoke a plain devotee said "%".', v_message;
  end if;
end;
$$;

-- The President can take back access that has no grant behind it — the record
-- gains the revocation even though it never saw the appointment.
reset role;
select set_config('request.jwt.claim.sub', 'a7000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
  v_ended public.access_appointments;
begin
  v_ended := public.revoke_access('a7000000-0000-0000-0000-000000000006', 'No longer serving.');
  if v_ended.appointed_by is not null or v_ended.source <> 'backfill' then
    raise exception 'A grant nobody made was recorded as % by %.',
      v_ended.source, v_ended.appointed_by;
  end if;
  if v_ended.revoke_reason <> 'revoked' then
    raise exception 'Revoking unrecorded access ended as [%].', v_ended.revoke_reason;
  end if;
  if (
    select roles.name from public.users
    join public.roles on roles.id = users.role_id
    where users.id = 'a7000000-0000-0000-0000-000000000006'
  ) <> 'devotee' then
    raise exception 'The President could not return the Volunteer to Devotee.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. The record shows who appointed whom — to the coordinators, and to nobody
--    else.
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', 'a7000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
  v_row record;
  v_rows integer;
begin
  select count(*)::integer into v_rows
  from public.list_access_appointments('a7000000-0000-0000-0000-000000000007');
  -- Volunteer, then Community Head, both now ended.
  if v_rows <> 2 then
    raise exception 'Devotee C''s history has % rows rather than 2.', v_rows;
  end if;

  select * into v_row
  from public.list_access_appointments('a7000000-0000-0000-0000-000000000005');
  if v_row.appointed_by_name <> 'Ap Head B' then
    raise exception 'The record says [%] appointed Devotee B.', v_row.appointed_by_name;
  end if;
  if v_row.role_label <> 'Community Head' then
    raise exception 'The record labels the grant [%].', v_row.role_label;
  end if;
  if not v_row.is_active then
    raise exception 'A live grant is not marked active.';
  end if;
  if not v_row.can_revoke then
    raise exception 'The President is not offered a way to revoke a live grant.';
  end if;

  -- The whole record, unfiltered.
  select count(*)::integer into v_rows from public.list_access_appointments(null::uuid);
  if v_rows < 7 then
    raise exception 'The whole record has only % rows.', v_rows;
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'a7000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_row record;
begin
  -- A Community Head reads the record, including grants that are not hers.
  select * into v_row
  from public.list_access_appointments('a7000000-0000-0000-0000-000000000005');
  if v_row.appointed_by_name <> 'Ap Head B' then
    raise exception 'A Community Head cannot see who appointed Devotee B.';
  end if;
  if v_row.can_revoke then
    raise exception 'A Community Head is offered a way to revoke another Head''s grant.';
  end if;

  if (select count(*) from public.access_appointments) = 0 then
    raise exception 'A Community Head reads no rows at the table itself.';
  end if;
end;
$$;

reset role;

do $$
declare
  v_who record;
  v_rows integer;
begin
  for v_who in
    select * from (values
      ('a7000000-0000-0000-0000-000000000007'::uuid, 'A plain devotee'),
      ('a7000000-0000-0000-0000-000000000006'::uuid, 'A former Volunteer'),
      ('a7000000-0000-0000-0000-000000000004'::uuid, 'A devotee reading their own history')
    ) as reader(id, label)
  loop
    perform set_config('request.jwt.claim.sub', v_who.id::text, true);
    execute 'set local role authenticated';

    select count(*)::integer into v_rows from public.list_access_appointments(null::uuid);
    if v_rows <> 0 then
      raise exception '% reads % rows of the access record.', v_who.label, v_rows;
    end if;

    select count(*)::integer into v_rows
    from public.list_access_appointments(v_who.id);
    if v_rows <> 0 then
      raise exception '% reads their own access record.', v_who.label;
    end if;

    -- And straight at the table, which is where a PostgREST client would try.
    select count(*)::integer into v_rows from public.access_appointments;
    if v_rows <> 0 then
      raise exception '% reads % appointment rows at the table.', v_who.label, v_rows;
    end if;

    execute 'reset role';
  end loop;
end;
$$;

-- Nobody writes the record by hand, whatever their rank.
reset role;
select set_config('request.jwt.claim.sub', 'a7000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_message text := null;
begin
  begin
    insert into public.access_appointments (devotee_id, role_id, appointed_by)
    values (
      'a7000000-0000-0000-0000-000000000007',
      (select roles.id from public.roles where roles.name = 'core'),
      'a7000000-0000-0000-0000-000000000002'
    );
  exception when others then
    v_message := sqlerrm;
  end;
  if v_message is null then
    raise exception 'A Community Head wrote straight into the access record.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. The request flow still works, and an approval lands in the same record.
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', 'a7000000-0000-0000-0000-000000000007', true);
set local role authenticated;

do $$
declare
  v_request public.access_requests;
begin
  v_request := public.create_access_request(
    'volunteer',
    'I would like to help with the book table again.',
    'a7000000-0000-0000-0000-000000000001'
  );
  if v_request.id is null then
    raise exception 'A devotee could no longer ask for access.';
  end if;
  insert into public.access_appointment_test_ids values ('c-request', v_request.id);
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'a7000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
  v_request uuid := (
    select id from public.access_appointment_test_ids where key = 'c-request'
  );
  v_reviewed public.access_requests;
  v_grant record;
begin
  v_reviewed := public.review_access_request(v_request, 'approved', 'Gladly.');
  if v_reviewed.status <> 'approved' then
    raise exception 'The approval did not take.';
  end if;
  if (
    select roles.name from public.users
    join public.roles on roles.id = users.role_id
    where users.id = 'a7000000-0000-0000-0000-000000000007'
  ) <> 'volunteer' then
    raise exception 'An approved request did not change the access level.';
  end if;

  select * into v_grant
  from public.list_access_appointments('a7000000-0000-0000-0000-000000000007')
  where is_active;

  if v_grant.id is null then
    raise exception 'An approved request left no grant in the record.';
  end if;
  if v_grant.source <> 'request' then
    raise exception 'An approved request was recorded as source [%].', v_grant.source;
  end if;
  if v_grant.appointed_by <> 'a7000000-0000-0000-0000-000000000001' then
    raise exception 'An approved request did not credit the reviewer.';
  end if;
  if v_grant.access_request_id <> v_request then
    raise exception 'The grant does not point back at the request.';
  end if;
  if v_grant.note <> 'Gladly.' then
    raise exception 'The reviewer''s note did not reach the record: [%].', v_grant.note;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. The congregation view can say who granted the access it shows.
--
--    A companion to list_devotee_profiles rather than three columns appended
--    to it, so that function's pinned result shape is left exactly as
--    birthdays_and_congregation.sql found it.
-- ---------------------------------------------------------------------------

do $$
declare
  v_row record;
  v_profiles integer;
  v_result text;
begin
  select * into v_row
  from public.list_devotee_access_grants('a7000000-0000-0000-0000-000000000005');
  if v_row.appointed_by_name <> 'Ap Head B' then
    raise exception 'The congregation view says [%] granted Devotee B''s access.',
      v_row.appointed_by_name;
  end if;
  if v_row.role_label <> 'Community Head' or v_row.appointed_at is null then
    raise exception 'The live grant came back as % at %.', v_row.role_label, v_row.appointed_at;
  end if;

  select * into v_row
  from public.list_devotee_access_grants('a7000000-0000-0000-0000-000000000007');
  if v_row.appointed_by_name <> 'Ap President' or v_row.source <> 'request' then
    raise exception 'An approved request does not show in the congregation view.';
  end if;

  -- Somebody whose access was taken back has no live grant at all.
  if exists (
    select 1 from public.list_devotee_access_grants('a7000000-0000-0000-0000-000000000004')
  ) then
    raise exception 'A revoked devotee still shows a live grant.';
  end if;

  -- Exactly the three people this script left holding a grant: Devotee B,
  -- Devotee C and Devotee D. The two Community Heads were set by hand, the way
  -- access was set before this record existed, and correctly appear nowhere.
  select count(*)::integer into v_profiles
  from public.list_devotee_access_grants(null::uuid)
  where devotee_id in (
    'a7000000-0000-0000-0000-000000000005',
    'a7000000-0000-0000-0000-000000000007',
    'a7000000-0000-0000-0000-000000000009'
  );
  if v_profiles <> 3 then
    raise exception 'The live-grant view shows % of the 3 devotees holding access.', v_profiles;
  end if;
  if exists (
    select 1 from public.list_devotee_access_grants(null::uuid) live
    where live.devotee_id in (
      'a7000000-0000-0000-0000-000000000002',
      'a7000000-0000-0000-0000-000000000003',
      'a7000000-0000-0000-0000-000000000004',
      'a7000000-0000-0000-0000-000000000006'
    )
  ) then
    raise exception 'Somebody with no grant, or whose grant was revoked, still shows one.';
  end if;

  -- And no live grant is held by somebody who is not, in fact, at that level.
  if exists (
    select 1 from public.list_devotee_access_grants(null::uuid) live
    join public.users congregant on congregant.id = live.devotee_id
    join public.roles held on held.id = congregant.role_id
    where held.name not in ('volunteer', 'core')
       or held.name <> live.role_name
  ) then
    raise exception 'A live grant disagrees with the access level the devotee actually holds.';
  end if;

  -- And the function it sits beside was left alone: the column another
  -- migration's script pins is still the last one.
  select pg_get_function_result(pg_proc.oid) into v_result
  from pg_proc
  join pg_namespace on pg_namespace.oid = pg_proc.pronamespace
  where pg_namespace.nspname = 'public'
    and pg_proc.proname = 'list_devotee_profiles';
  if v_result !~ 'completion integer, sanga_names text\)$' then
    raise exception 'list_devotee_profiles was widened after all: %', v_result;
  end if;
end;
$$;

-- The companion is shut to everybody the record is shut to.
reset role;
select set_config('request.jwt.claim.sub', 'a7000000-0000-0000-0000-000000000006', true);
set local role authenticated;

do $$
begin
  if exists (select 1 from public.list_devotee_access_grants(null::uuid)) then
    raise exception 'A plain devotee reads who granted the congregation their access.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'a7000000-0000-0000-0000-000000000001', true);
set local role authenticated;

-- ---------------------------------------------------------------------------
-- 7b. Nobody steps off their own ladder, and a coordinator who stops being one
--     stops being able to act — including on the people they appointed.
--
--     The second half is the reason revoke_access asks whether the caller is a
--     coordinator at all rather than trusting the "did you grant this?" test to
--     stand alone: a Community Head who is returned to Devotee still shows as
--     appointed_by on every grant she made, and that must become a piece of
--     history rather than a key she kept.
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', 'a7000000-0000-0000-0000-000000000009', true);
set local role authenticated;

do $$
declare
  v_message text;
begin
  -- Devotee D is a Community Head, appointed by Head A.
  v_message := null;
  begin
    perform public.revoke_access('a7000000-0000-0000-0000-000000000009', null);
  exception when others then
    v_message := sqlerrm;
  end;
  if v_message is null then
    raise exception 'A Community Head revoked their own access.';
  end if;
  if v_message not like '%your own%' then
    raise exception 'Refusing self-revocation said "%".', v_message;
  end if;

  v_message := null;
  begin
    perform public.appoint_access('a7000000-0000-0000-0000-000000000009', 'volunteer');
  exception when others then
    v_message := sqlerrm;
  end;
  if v_message is null then
    raise exception 'A Community Head moved their own access level.';
  end if;
  if v_message not like '%your own%' then
    raise exception 'Refusing to move one''s own access said "%".', v_message;
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'a7000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
  v_ended public.access_appointments;
begin
  v_ended := public.revoke_access(
    'a7000000-0000-0000-0000-000000000003', 'Stepping down from the council.'
  );
  if v_ended.revoke_reason <> 'revoked' then
    raise exception 'A Community Head could not be returned to Devotee.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'a7000000-0000-0000-0000-000000000003', true);
set local role authenticated;

do $$
declare
  v_message text;
begin
  if public.may_appoint_access() then
    raise exception 'A former Community Head may still appoint access.';
  end if;

  -- Devotee B holds a grant she made herself, and it is no longer hers to end.
  v_message := null;
  begin
    perform public.revoke_access('a7000000-0000-0000-0000-000000000005', null);
  exception when others then
    v_message := sqlerrm;
  end;
  if v_message is null then
    raise exception 'A former Community Head revoked the devotee she had appointed.';
  end if;
  if v_message not like 'Only a Community Head%' then
    raise exception 'Refusing a former Community Head said "%".', v_message;
  end if;

  if exists (select 1 from public.list_access_appointments(null::uuid)) then
    raise exception 'A former Community Head can still read the access record.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'a7000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
  v_row record;
begin
  -- And she is still, correctly, the person who appointed Devotee B.
  select * into v_row
  from public.list_devotee_access_grants('a7000000-0000-0000-0000-000000000005');
  if v_row.appointed_by_name <> 'Ap Head B' then
    raise exception 'A grant lost its appointer when the appointer stepped down.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. The shape of the record itself.
-- ---------------------------------------------------------------------------

reset role;

do $$
declare
  v_devotee uuid;
begin
  if not exists (
    select 1 from pg_class
    join pg_namespace on pg_namespace.oid = pg_class.relnamespace
    where pg_namespace.nspname = 'public'
      and pg_class.relname = 'access_appointments'
      and pg_class.relrowsecurity
  ) then
    raise exception 'The access record has row level security switched off.';
  end if;

  select access_appointments.devotee_id into v_devotee
  from public.access_appointments
  where access_appointments.revoked_at is null
  group by access_appointments.devotee_id
  having count(*) > 1;
  if v_devotee is not null then
    raise exception 'Devotee % holds two live grants at once.', v_devotee;
  end if;

  -- Nothing was overwritten: the grants this script ended are all still there.
  if not exists (
    select 1 from public.access_appointments
    where access_appointments.id = (
      select id from public.access_appointment_test_ids where key = 'c-volunteer-grant'
    )
  ) then
    raise exception 'A superseded grant was deleted rather than kept.';
  end if;

  if exists (
    select 1 from public.access_appointments
    where (access_appointments.revoked_at is null) <> (access_appointments.revoke_reason is null)
  ) then
    raise exception 'A grant ended without saying why, or says why without having ended.';
  end if;
end;
$$;

do $$
begin
  raise notice 'all access appointment checks passed';
end;
$$;

select 'access appointments verification passed' as result;

rollback;
