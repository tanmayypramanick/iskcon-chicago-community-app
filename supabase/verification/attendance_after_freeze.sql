-- Absent earns nothing, however late the coordinator says it.
--
-- The failure this pins: a seva is served and credited, the nightly run
-- freezes that Seva Mala week, and the coordinator then marks the devotee
-- absent. recompute_seva_mala_period returns 0 without doing anything on a
-- frozen period, and before 202608310084 record_seva_attendance never asked it
-- to recount at all — so public.period_scores kept the devotee's minutes for a
-- seva the temple had recorded them as missing from, and any badge those
-- minutes earned stood with it.
--
-- Asserted against period_scores rather than seva_mala_acts on purpose:
-- seva_mala_acts is computed live from the assignment rows and reflects the
-- correction immediately whether or not anything was recounted, so a test
-- written against it passes on the broken code and proves nothing. The frozen
-- table is the thing that goes stale.
--
-- Everything is rolled back at the end, so the script is re-runnable.

begin;

do $$
declare
  v_president uuid := '6a000000-0000-0000-0000-000000000001';
  v_devotee   uuid := '6a000000-0000-0000-0000-000000000002';
  v_type uuid;
  v_instance uuid;
  v_assignment uuid;
  v_on date;
  v_week uuid;
  v_minutes_before numeric;
  v_minutes_after numeric;
begin
  -- ---- the two devotees this needs ---------------------------------------
  insert into auth.users (id, email, raw_user_meta_data) values
    (v_president, 'af-president@example.test',
     jsonb_build_object('name', 'Attendance President')),
    (v_devotee, 'af-devotee@example.test',
     jsonb_build_object('name', 'Attendance Devotee'));

  update public.users
  set role_id = (select id from public.roles where name = 'president')
  where id = v_president;

  update public.users
  set role_id = (select id from public.roles where name = 'devotee')
  where id = v_devotee;

  insert into public.service_types (name, category)
  values ('Attendance Freeze Test Seva', 'other')
  returning id into v_type;

  -- A day that has certainly finished, so credit is not withheld for the
  -- separate reason 202608310083 introduced.
  v_on := public.seva_mala_today() - 3;

  -- ---- a seva that was served, and completed -----------------------------
  insert into public.service_instances (
    service_type_id, date, start_time, duration_minutes, slots_needed,
    participation_mode, posted_by, status
  )
  values (v_type, v_on, time '09:00', 120, 1, 'open', v_president, 'completed')
  returning id into v_instance;

  insert into public.service_assignments (
    service_instance_id, devotee_id, assignment_method, status,
    verification, attendance, completed_at
  )
  values (
    v_instance, v_devotee, 'self_joined', 'completed',
    'member_verified', 'served',
    (v_on + time '11:00') at time zone 'America/Chicago'
  )
  returning id into v_assignment;

  -- ---- the week, counted while it is still open --------------------------
  select periods.id into v_week
  from public.seva_mala_periods periods
  where periods.period_kind = 'week'
    and v_on between periods.starts_on and periods.ends_on
  limit 1;

  if v_week is null then
    insert into public.seva_mala_periods (period_kind, starts_on, ends_on)
    values (
      'week',
      public.seva_mala_week_start(v_on),
      public.seva_mala_week_start(v_on) + 6
    )
    returning id into v_week;
  end if;

  update public.seva_mala_periods set frozen_at = null where id = v_week;
  perform public.recompute_seva_mala_period(v_week);

  select coalesce(scores.credited_minutes, 0) into v_minutes_before
  from public.period_scores scores
  where scores.period_id = v_week and scores.devotee_id = v_devotee;

  if coalesce(v_minutes_before, 0) <= 0 then
    raise exception
      'the served seva was never counted into period_scores (% minutes); the test would prove nothing',
      coalesce(v_minutes_before, 0);
  end if;

  -- ---- the nightly run freezes the week ----------------------------------
  update public.seva_mala_periods set frozen_at = now() where id = v_week;

  -- ---- and only then does the coordinator correct the record -------------
  perform set_config('request.jwt.claim.sub', v_president::text, true);
  perform public.record_seva_attendance(v_assignment, 'absent');
  perform set_config('request.jwt.claim.sub', '', true);

  select coalesce(scores.credited_minutes, 0) into v_minutes_after
  from public.period_scores scores
  where scores.period_id = v_week and scores.devotee_id = v_devotee;

  if coalesce(v_minutes_after, 0) <> 0 then
    raise exception
      'a devotee marked absent after the week froze kept % credited minutes (was %)',
      v_minutes_after, v_minutes_before;
  end if;

  raise notice
    'absent after the freeze removed the credit (% -> %)',
    v_minutes_before, coalesce(v_minutes_after, 0);
end;
$$;

rollback;
