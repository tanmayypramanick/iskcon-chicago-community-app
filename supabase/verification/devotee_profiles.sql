-- Functional verification for 202608040030_devotee_profiles.sql.
--
-- Rolled back at the end. Every local is prefixed v_ so it can never shadow a
-- column name.
--
-- The final row must read: devotee profiles verification passed

begin;

-- The President is created and given their role FIRST. announce_new_devotee
-- fires the moment a profile row appears, so a reviewer who does not exist yet
-- cannot be told — which is exactly right in production, where the President
-- already has their role long before anybody new signs up.
insert into auth.users (id, email, raw_user_meta_data) values
  ('80000000-0000-0000-0000-000000000001', 'prof-president@example.test', '{"name":"Profile President"}');

update public.users users
set role_id = (select id from public.roles where name = 'president')
where users.email = 'prof-president@example.test';

insert into auth.users (id, email, raw_user_meta_data) values
  ('80000000-0000-0000-0000-000000000002', 'prof-devotee@example.test', '{"name":"Profile Devotee"}'),
  ('80000000-0000-0000-0000-000000000003', 'prof-other@example.test', '{"name":"Profile Other"}');

-- ---------------------------------------------------------------------------
-- 1. Completion rises as a devotee fills their details in.
-- ---------------------------------------------------------------------------

do $$
declare
  v_start integer;
  v_after integer;
begin
  v_start := public.profile_completion('80000000-0000-0000-0000-000000000002');
  if v_start >= 100 then
    raise exception 'A brand new profile cannot already be complete (got %).', v_start;
  end if;

  perform set_config('request.jwt.claim.sub', '80000000-0000-0000-0000-000000000002', true);
  perform public.update_my_profile(
    'Profile Devotee', '+1 312 555 0101', date '1995-04-12', 'Mayapur',
    '1716 W Lunt Ave, Chicago', 'HG Radha Krsna Das',
    false, null, null, false, null, null, false, null, null
  );

  v_after := public.profile_completion('80000000-0000-0000-0000-000000000002');
  if v_after <= v_start then
    raise exception 'Filling details did not raise completion (% -> %).', v_start, v_after;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Answering "not initiated" does not count against a devotee, and saying
--    yes then no clears the details rather than leaving contradictions.
-- ---------------------------------------------------------------------------

do $$
declare
  v_with_yes integer;
begin
  perform public.update_my_profile(
    'Profile Devotee', '+1 312 555 0101', date '1995-04-12', 'Mayapur',
    '1716 W Lunt Ave, Chicago', 'HG Radha Krsna Das',
    true, date '2020-03-01', 'HH Jayapataka Swami',
    true, date '2020-03-01', 'HH Jayapataka Swami',
    false, null, null
  );
  v_with_yes := public.profile_completion('80000000-0000-0000-0000-000000000002');

  if not exists (
    select 1 from public.users
    where id = '80000000-0000-0000-0000-000000000002'
      and diksha_guru = 'HH Jayapataka Swami'
      and initiation_date = date '2020-03-01'
  ) then
    raise exception 'Initiation details were not saved.';
  end if;

  -- Now say no. The details must not linger.
  perform public.update_my_profile(
    'Profile Devotee', '+1 312 555 0101', date '1995-04-12', 'Mayapur',
    '1716 W Lunt Ave, Chicago', 'HG Radha Krsna Das',
    false, date '2020-03-01', 'HH Jayapataka Swami',
    false, date '2020-03-01', 'HH Jayapataka Swami',
    false, null, null
  );

  if exists (
    select 1 from public.users
    where id = '80000000-0000-0000-0000-000000000002'
      and (diksha_guru is not null or initiation_date is not null
           or first_diksha_guru is not null)
  ) then
    raise exception 'Answering "not initiated" left the old details behind.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. A devotee cannot edit somebody else, and a future birthday is refused.
-- ---------------------------------------------------------------------------

do $$
declare
  v_refused boolean := false;
  v_other_name text;
begin
  begin
    perform public.update_my_profile(
      'Profile Devotee', null, current_date + 1, null, null, null,
      false, null, null, false, null, null, false, null, null
    );
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A date of birth in the future was accepted.';
  end if;

  -- update_my_profile only ever touches auth.uid(), so the other devotee is
  -- untouched no matter what is passed.
  select name into v_other_name from public.users
  where id = '80000000-0000-0000-0000-000000000003';
  if v_other_name <> 'Profile Other' then
    raise exception 'Another devotee''s profile was changed.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. An access request carries a reason, and a bare one is refused.
-- ---------------------------------------------------------------------------

do $$
declare
  v_refused boolean := false;
  v_request public.access_requests;
begin
  begin
    perform public.create_access_request(
      'volunteer', 'plz', '80000000-0000-0000-0000-000000000001'
    );
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'An access request with no real reason was accepted.';
  end if;

  -- 0031: a request is addressed to a named Community Head or President.
  v_request := public.create_access_request(
    'volunteer', 'I cook on Sundays and would like to post kitchen seva myself.',
    '80000000-0000-0000-0000-000000000001'
  );
  if v_request.approver_id is null then
    raise exception 'The request did not record who was asked.';
  end if;
  if v_request.message is null then
    raise exception 'The reason was not stored with the request.';
  end if;

  -- The reviewers must hear about it.
  if not exists (
    select 1 from public.app_notifications
    where user_id = '80000000-0000-0000-0000-000000000001'
      and kind = 'access_request_submitted'
  ) then
    raise exception 'Nobody was told an access request arrived.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Reviewing records who decided, and the devotee can see it.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', '80000000-0000-0000-0000-000000000001', true);

do $$
declare
  v_request uuid;
  v_reviewed public.access_requests;
begin
  select id into v_request from public.access_requests
  where requester_id = '80000000-0000-0000-0000-000000000002' and status = 'pending';

  v_reviewed := public.review_access_request(
    v_request, 'approved', 'Glad to have you helping in the kitchen.'
  );
  if v_reviewed.reviewed_by is null then
    raise exception 'The review did not record who decided.';
  end if;
  if v_reviewed.review_note is null then
    raise exception 'The reviewer''s note was not kept.';
  end if;

  if not exists (
    select 1 from public.users
    where id = '80000000-0000-0000-0000-000000000002'
      and role_id = (select id from public.roles where name = 'volunteer')
  ) then
    raise exception 'Approving did not change the access level.';
  end if;
end;
$$;

select set_config('request.jwt.claim.sub', '80000000-0000-0000-0000-000000000002', true);

do $$
declare
  v_reviewer text;
begin
  select reviewed_by_name into v_reviewer
  from public.list_my_access_requests() limit 1;
  if v_reviewer is distinct from 'Profile President' then
    raise exception 'The devotee cannot see who approved them (got %).', v_reviewer;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. The congregation list is for the President and Tech Admin only.
-- ---------------------------------------------------------------------------

do $$
declare
  v_rows integer;
begin
  -- Still signed in as the devotee.
  select count(*) into v_rows from public.list_devotee_profiles();
  if v_rows <> 0 then
    raise exception 'A devotee could read the whole congregation list.';
  end if;
end;
$$;

select set_config('request.jwt.claim.sub', '80000000-0000-0000-0000-000000000001', true);

do $$
declare
  v_rows integer;
  v_completion integer;
begin
  select count(*) into v_rows from public.list_devotee_profiles();
  if v_rows < 3 then
    raise exception 'The President sees only % devotees.', v_rows;
  end if;

  select completion into v_completion
  from public.list_devotee_profiles()
  where id = '80000000-0000-0000-0000-000000000002';
  if v_completion is null or v_completion = 0 then
    raise exception 'The list does not show how complete a profile is.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. A new devotee is announced, and reminded until they finish.
-- ---------------------------------------------------------------------------

do $$
declare
  v_sent integer;
  v_again integer;
begin
  if not exists (
    select 1 from public.app_notifications
    where user_id = '80000000-0000-0000-0000-000000000001'
      and kind = 'devotee_joined'
  ) then
    raise exception 'Nobody was told a new devotee joined.';
  end if;

  v_sent := public.remind_incomplete_profiles();
  if v_sent < 1 then
    raise exception 'Nobody with an unfinished profile was reminded.';
  end if;

  -- Running again the same day must not nag twice.
  v_again := public.remind_incomplete_profiles();
  if v_again <> 0 then
    raise exception 'A devotee was reminded % times in one day.', v_again + 1;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. A devotee who is not initiated can still finish their profile.
--
--    This was the reported bug: completion counted fields the edit screen
--    never asked for, so 100% was unreachable and the daily reminder never
--    stopped.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', '80000000-0000-0000-0000-000000000003', true);

do $$
declare
  v_completion integer;
  v_reminded integer;
begin
  perform public.update_my_profile(
    'Profile Other', '+1 312 555 0199', date '1990-01-01', 'Vrindavan',
    '1716 W Lunt Ave, Chicago', 'HG Gauranga Das',
    false, null, null, false, null, null, false, null, null
  );
  update public.users
  set photo_url = 'https://gkkeebhdavavizcvknwy.supabase.co/storage/v1/object/public/devotee-photos/x/y.jpg'
  where id = '80000000-0000-0000-0000-000000000003';

  v_completion := public.profile_completion('80000000-0000-0000-0000-000000000003');
  if v_completion <> 100 then
    raise exception 'A devotee who answered everything is only % percent complete.', v_completion;
  end if;

  -- And so is never nagged again.
  delete from public.app_notifications
  where user_id = '80000000-0000-0000-0000-000000000003'
    and kind = 'profile_incomplete';
  v_reminded := public.remind_incomplete_profiles();

  if exists (
    select 1 from public.app_notifications
    where user_id = '80000000-0000-0000-0000-000000000003'
      and kind = 'profile_incomplete'
  ) then
    raise exception 'A devotee with a finished profile was still reminded.';
  end if;
end;
$$;

do $$
begin
  raise notice 'all devotee profile checks passed';
end;
$$;

select 'devotee profiles verification passed' as result;

rollback;
