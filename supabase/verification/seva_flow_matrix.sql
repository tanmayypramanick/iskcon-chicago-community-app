-- Every way a seva can be settled, and what each one earns.
--
-- The temple runs three flows and they settle differently. seva_points_status
-- is already walked exhaustively by seva_points_eligibility.sql — all eighty
-- combinations of status x attendance x verification. That proves the RULE.
-- It does not prove that the FLOWS put the right values in, and twice they did
-- not: a logged seva verified by a member never had its attendance recorded
-- (202608310093), and a posted seva marked served never had its verification
-- recorded (202608310094). Both read as zero for ever, and both were invisible
-- to a test of the rule alone.
--
-- So this drives the real RPCs end to end and asserts what a devotee actually
-- earns.
--
--   POSTED       a coordinator posts it, a devotee takes a place, the
--                coordinator records attendance and closes it. No verification
--                step exists in this flow.
--   LOGGED       the devotee describes seva they did and names a member; that
--                member verifies it. No attendance step exists in this flow.
--   WEEKLY       a template's occurrence, completed on its day. Neither step
--                is owed: 202608040059 counts it on completion alone.
--
-- Everything is rolled back at the end, so the script is re-runnable.

begin;

-- ---------------------------------------------------------------------------
-- The cast and the fixtures.
-- ---------------------------------------------------------------------------

create temporary table sfm_ids (key text primary key, id uuid not null)
  on commit drop;

do $$
declare
  v_who record;
  v_i integer := 0;
  v_id uuid;
begin
  for v_who in
    select * from (values
      ('head',    'Flow Coordinator'),
      ('served',  'Devotee Served'),
      ('absent',  'Devotee Absent'),
      ('excused', 'Devotee Excused'),
      ('silent',  'Devotee Unmarked'),
      ('logger',  'Devotee Logging'),
      ('weekly',  'Devotee Weekly'),
      ('scanner', 'Devotee Scanned'),
      -- A second member who may verify, so the "not even the President may
      -- verify their own" case has somebody legitimate to name.
      ('head2',   'Second Coordinator')
    ) as cast_member(key, name)
  loop
    v_i := v_i + 1;
    v_id := ('76000000-0000-0000-0000-0000000000' || lpad(v_i::text, 2, '0'))::uuid;
    insert into auth.users (id, email, raw_user_meta_data)
    values (v_id, 'sfm-' || v_who.key || '@example.test',
            jsonb_build_object('name', v_who.name));
    insert into sfm_ids (key, id) values (v_who.key, v_id);
  end loop;

  -- The coordinator is the President, so they may post, record attendance and
  -- verify. That is the authority the flows actually run on.
  update public.users
  set role_id = (select id from public.roles where name = 'president')
  where id = (select id from sfm_ids where key = 'head');

  update public.users
  set role_id = (select id from public.roles where name = 'tech')
  where id = (select id from sfm_ids where key = 'head2');
end;
$$;

/** A one-off seva posted by the coordinator, yesterday morning, one place. */
create or replace function pg_temp.sfm_post(p_slots integer default 1)
returns uuid
language plpgsql
as $$
declare
  v_type uuid;
  v_inst uuid;
begin
  select id into v_type from public.service_types
  where name = 'Flow Matrix Seva';
  if v_type is null then
    insert into public.service_types (name, category)
    values ('Flow Matrix Seva', 'other')
    returning id into v_type;
  end if;

  insert into public.service_instances
    (service_type_id, date, start_time, duration_minutes, slots_needed,
     participation_mode, posted_by, status)
  values (
    v_type, public.seva_mala_today() - 1, time '09:00', 60, p_slots, 'open',
    (select id from sfm_ids where key = 'head'), 'open'
  )
  returning id into v_inst;
  return v_inst;
end;
$$;

/** Exactly what join_service writes (202608030009): self_report, confirmed. */
create or replace function pg_temp.sfm_join(p_inst uuid, p_who text)
returns uuid
language plpgsql
as $$
declare
  v_assignment uuid;
begin
  insert into public.service_assignments
    (service_instance_id, devotee_id, assignment_method, assigned_by,
     status, verification)
  values (
    p_inst, (select id from sfm_ids where key = p_who), 'self_joined',
    (select id from sfm_ids where key = p_who), 'confirmed', 'self_report'
  )
  returning id into v_assignment;
  return v_assignment;
end;
$$;

/** What the devotee earned for one seva, as the board would score it. */
create or replace function pg_temp.sfm_points(p_inst uuid, p_who text)
returns text
language sql
stable
as $$
  select coalesce(
    (
      select acts.points_status
      from public.seva_mala_acts((select id from sfm_ids where key = p_who)) acts
      where acts.service_instance_id = p_inst
    ),
    '<no act>'
  );
$$;

create or replace function pg_temp.sfm_minutes(p_inst uuid, p_who text)
returns numeric
language sql
stable
as $$
  select coalesce(
    (
      select acts.credited_minutes
      from public.seva_mala_acts((select id from sfm_ids where key = p_who)) acts
      where acts.service_instance_id = p_inst
    ),
    0
  );
$$;

create or replace function pg_temp.sfm_expect(
  p_case text, p_inst uuid, p_who text, p_points text, p_earns boolean
)
returns void
language plpgsql
as $$
declare
  v_points text := pg_temp.sfm_points(p_inst, p_who);
  v_minutes numeric := pg_temp.sfm_minutes(p_inst, p_who);
begin
  if v_points is distinct from p_points then
    raise exception '%: points_status is % rather than %',
      p_case, v_points, p_points;
  end if;
  if p_earns and v_minutes <= 0 then
    raise exception '%: counted but credited % minutes', p_case, v_minutes;
  end if;
  if not p_earns and v_minutes <> 0 then
    raise exception '%: earns nothing but credited % minutes', p_case, v_minutes;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 1. POSTED seva. The coordinator records attendance; there is no verification
--    step, and recording attendance is what stands in its place.
-- ---------------------------------------------------------------------------

do $$
declare
  v_head uuid := (select id from sfm_ids where key = 'head');
  v_inst uuid;
  v_served uuid;
  v_absent uuid;
  v_excused uuid;
  v_silent uuid;
begin
  v_inst := pg_temp.sfm_post(4);
  v_served  := pg_temp.sfm_join(v_inst, 'served');
  v_absent  := pg_temp.sfm_join(v_inst, 'absent');
  v_excused := pg_temp.sfm_join(v_inst, 'excused');
  v_silent  := pg_temp.sfm_join(v_inst, 'silent');

  perform set_config('request.jwt.claim.sub', v_head::text, true);
  perform public.record_seva_attendance(v_served, 'served');
  perform public.record_seva_attendance(v_absent, 'absent');
  perform public.record_seva_attendance(v_excused, 'excused');
  -- v_silent is deliberately left unanswered.
  perform public.complete_service_instance(v_inst);
  perform set_config('request.jwt.claim.sub', '', true);

  -- Served: the coordinator said so, and that is the verification.
  perform pg_temp.sfm_expect(
    'posted + served', v_inst, 'served', 'counted', true);

  -- Absent and excused earn nothing. The temple's rule, and terminal.
  perform pg_temp.sfm_expect(
    'posted + absent', v_inst, 'absent', 'not_served', false);
  perform pg_temp.sfm_expect(
    'posted + excused', v_inst, 'excused', 'not_served', false);

  -- Silence is not service. Nobody said this devotee was there, so nothing
  -- was recorded and nothing is owed to them: attendance stayed null AND the
  -- verification upgrade never fired, so the rule reports the verification arm
  -- first. Either way it earns nothing, which is the part that matters.
  perform pg_temp.sfm_expect(
    'posted + nobody answered', v_inst, 'silent', 'awaiting_verification', false);

  -- And the mark itself must be recorded as a member's word.
  if (select verification from public.service_assignments where id = v_served)
     is distinct from 'member_verified'
  then
    raise exception 'the coordinator marked them served and verification did not follow';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Nobody records their own attendance, whoever they are.
--
--    202608040025's principle: verification means somebody else saw it happen.
--    202608310095 makes it a refusal rather than a silent nil, so a coordinator
--    who served a seva they posted is told to ask somebody else instead of
--    wondering why their hours never appeared.
-- ---------------------------------------------------------------------------

do $$
declare
  v_head uuid := (select id from sfm_ids where key = 'head');
  v_inst uuid;
  v_own uuid;
  v_refused boolean := false;
  v_marked integer;
begin
  v_inst := pg_temp.sfm_post(1);
  insert into public.service_assignments
    (service_instance_id, devotee_id, assignment_method, assigned_by,
     status, verification)
  values (v_inst, v_head, 'self_joined', v_head, 'confirmed', 'self_report')
  returning id into v_own;

  perform set_config('request.jwt.claim.sub', v_head::text, true);
  begin
    perform public.record_seva_attendance(v_own, 'served');
  exception when others then
    v_refused := true;
  end;

  -- And the one-tap form skips their own place rather than answering it.
  v_marked := public.record_unanswered_seva_attendance(v_inst, 'served');
  -- They can still close the seva out; it is only the attendance that needs
  -- another pair of eyes.
  perform public.complete_service_instance(v_inst);
  perform set_config('request.jwt.claim.sub', '', true);

  if not v_refused then
    raise exception 'a coordinator recorded their own attendance';
  end if;
  if v_marked <> 0 then
    raise exception
      'the one-tap form answered the coordinator''s own place (% marked)', v_marked;
  end if;
  if (select verification from public.service_assignments where id = v_own)
     <> 'self_report'
  then
    raise exception 'a coordinator verified their own seva';
  end if;

  perform pg_temp.sfm_expect(
    'posted + coordinator serves their own', v_inst, 'head',
    'awaiting_verification', false);
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. A stronger record is never overwritten by a weaker one.
--
--    A QR scan says more about an act than a member's recollection. Recording
--    attendance must not replace it.
-- ---------------------------------------------------------------------------

do $$
declare
  v_head uuid := (select id from sfm_ids where key = 'head');
  v_inst uuid;
  v_scan uuid;
begin
  v_inst := pg_temp.sfm_post(1);
  insert into public.service_assignments
    (service_instance_id, devotee_id, assignment_method, assigned_by,
     status, verification)
  values (
    v_inst, (select id from sfm_ids where key = 'scanner'), 'qr_scan',
    v_head, 'confirmed', 'qr_scan'
  )
  returning id into v_scan;

  perform set_config('request.jwt.claim.sub', v_head::text, true);
  perform public.record_seva_attendance(v_scan, 'served');
  perform public.complete_service_instance(v_inst);
  perform set_config('request.jwt.claim.sub', '', true);

  if (select verification from public.service_assignments where id = v_scan)
     <> 'qr_scan'
  then
    raise exception 'a QR scan was overwritten by a weaker record';
  end if;
  perform pg_temp.sfm_expect(
    'posted + qr scan + served', v_inst, 'scanner', 'counted', true);
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. A correction is the last word, and partial absence still completes.
--
--    The temple's rule: absence still completes the seva, crediting only the
--    devotees who actually served. And a seva NOBODY served must not read as
--    completed — 202608040068 argues at length that its honest terminal state
--    is 'cancelled', because 'closed' would be picked up and completed again.
-- ---------------------------------------------------------------------------

do $$
declare
  v_head uuid := (select id from sfm_ids where key = 'head');
  v_inst uuid;
  v_stayed uuid;
  v_left uuid;
  v_status text;
begin
  -- Two places. One devotee serves, one is corrected to absent afterwards.
  v_inst := pg_temp.sfm_post(2);
  v_stayed := pg_temp.sfm_join(v_inst, 'served');
  v_left   := pg_temp.sfm_join(v_inst, 'weekly');

  perform set_config('request.jwt.claim.sub', v_head::text, true);
  perform public.record_seva_attendance(v_stayed, 'served');
  perform public.record_seva_attendance(v_left, 'served');
  perform public.complete_service_instance(v_inst);
  perform pg_temp.sfm_expect(
    'partial absence, before the correction', v_inst, 'weekly', 'counted', true);

  -- One of them was not there after all.
  perform public.record_seva_attendance(v_left, 'absent');
  perform set_config('request.jwt.claim.sub', '', true);

  select instances.status into v_status
  from public.service_instances instances where instances.id = v_inst;
  if v_status <> 'completed' then
    raise exception
      'one devotee absent un-completed a seva somebody else served (status %)',
      v_status;
  end if;

  perform pg_temp.sfm_expect(
    'partial absence: the one who served', v_inst, 'served', 'counted', true);
  perform pg_temp.sfm_expect(
    'partial absence: the one who did not', v_inst, 'weekly', 'not_served', false);
end;
$$;

do $$
declare
  v_head uuid := (select id from sfm_ids where key = 'head');
  v_inst uuid;
  v_only uuid;
  v_status text;
begin
  -- The only devotee on it is corrected to absent, so nobody served it.
  v_inst := pg_temp.sfm_post(1);
  v_only := pg_temp.sfm_join(v_inst, 'absent');

  perform set_config('request.jwt.claim.sub', v_head::text, true);
  perform public.record_seva_attendance(v_only, 'served');
  perform public.complete_service_instance(v_inst);
  perform pg_temp.sfm_expect(
    'before the correction', v_inst, 'absent', 'counted', true);

  perform public.record_seva_attendance(v_only, 'absent');
  perform set_config('request.jwt.claim.sub', '', true);

  select instances.status into v_status
  from public.service_instances instances where instances.id = v_inst;
  if v_status = 'completed' then
    raise exception 'a seva nobody served still reads as completed';
  end if;
  if v_status <> 'cancelled' then
    raise exception
      'a seva nobody served settled as % rather than cancelled', v_status;
  end if;

  -- And it earns nothing. The act leaves the board with the seva.
  if pg_temp.sfm_minutes(v_inst, 'absent') <> 0 then
    raise exception 'a seva nobody served still credited minutes';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. LOGGED seva. A member verifies it; there is no attendance step, and the
--    verification stands in its place.
-- ---------------------------------------------------------------------------

do $$
declare
  v_head uuid := (select id from sfm_ids where key = 'head');
  v_logger uuid := (select id from sfm_ids where key = 'logger');
  v_type uuid := (select id from public.service_types where name = 'Flow Matrix Seva');
  v_req public.service_verifications;
  v_inst uuid;
  v_points text;
begin
  -- Pending: described, not yet answered. It earns nothing and exists nowhere.
  perform set_config('request.jwt.claim.sub', v_logger::text, true);
  v_req := public.log_completed_seva(
    v_type, null, now() - interval '3 hours', now() - interval '2 hours',
    'ISKCON Chicago Temple', v_head
  );

  if exists (select 1 from public.seva_mala_acts(v_logger)) then
    raise exception 'an unanswered log already counted as an act of seva';
  end if;

  -- The devotee who logged it cannot answer it. They are not the member it
  -- names, so the authority check refuses them first — which is the guard that
  -- actually stands between a devotee and their own points.
  begin
    perform public.respond_to_seva_verification(v_req.id, true, null);
    raise exception 'the devotee who logged it answered their own verification';
  exception
    when others then
      if position('can answer this' in sqlerrm) = 0
         and position('somebody else' in sqlerrm) = 0
      then
        raise;
      end if;
  end;

  -- The member verifies it, and that IS the confirmation.
  perform set_config('request.jwt.claim.sub', v_head::text, true);
  perform public.respond_to_seva_verification(v_req.id, true, null);
  perform set_config('request.jwt.claim.sub', '', true);

  select acts.service_instance_id into v_inst
  from public.seva_mala_acts(v_logger) acts limit 1;
  if v_inst is null then
    raise exception 'a verified log produced no act of seva';
  end if;

  perform pg_temp.sfm_expect(
    'logged + verified', v_inst, 'logger', 'counted', true);
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. A refused log earns nothing and leaves nothing behind.
-- ---------------------------------------------------------------------------

do $$
declare
  v_head uuid := (select id from sfm_ids where key = 'head');
  v_who uuid := (select id from sfm_ids where key = 'silent');
  v_type uuid := (select id from public.service_types where name = 'Flow Matrix Seva');
  v_req public.service_verifications;
  v_before integer;
  v_after integer;
begin
  select count(*)::integer into v_before from public.seva_mala_acts(v_who);

  perform set_config('request.jwt.claim.sub', v_who::text, true);
  v_req := public.log_completed_seva(
    v_type, null, now() - interval '5 hours', now() - interval '4 hours',
    'ISKCON Chicago Temple', v_head
  );

  perform set_config('request.jwt.claim.sub', v_head::text, true);
  perform public.respond_to_seva_verification(v_req.id, false, 'Not this one.');
  perform set_config('request.jwt.claim.sub', '', true);

  select count(*)::integer into v_after from public.seva_mala_acts(v_who);
  if v_after <> v_before then
    raise exception 'a refused log added % acts of seva', v_after - v_before;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6b. Not even the President may verify their own seva.
--
--     app.view_all reaches every registration in the temple, including their
--     own, so 202608040025 excludes their own explicitly. Without that, the one
--     person who can answer anything could award themselves points.
-- ---------------------------------------------------------------------------

do $$
declare
  v_head uuid := (select id from sfm_ids where key = 'head');
  v_other uuid := (select id from sfm_ids where key = 'head2');
  v_type uuid := (select id from public.service_types where name = 'Flow Matrix Seva');
  v_req public.service_verifications;
  v_refused boolean := false;
begin
  -- The President logs seva of their own, naming somebody else.
  perform set_config('request.jwt.claim.sub', v_head::text, true);
  v_req := public.log_completed_seva(
    v_type, null, now() - interval '7 hours', now() - interval '6 hours',
    'ISKCON Chicago Temple', v_other
  );

  -- And then tries to answer it themselves, which app.view_all would allow if
  -- the explicit exclusion were ever removed.
  begin
    perform public.respond_to_seva_verification(v_req.id, true, null);
  exception when others then
    v_refused := true;
  end;
  perform set_config('request.jwt.claim.sub', '', true);

  if not v_refused then
    raise exception 'the President verified their own seva';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. WEEKLY seva. Completed on its day is the whole of it: no verification
--    level and no attendance mark are owed (202608040059 section 4).
-- ---------------------------------------------------------------------------

do $$
declare
  v_head uuid := (select id from sfm_ids where key = 'head');
  v_weekly uuid := (select id from sfm_ids where key = 'weekly');
  v_type uuid := (select id from public.service_types where name = 'Flow Matrix Seva');
  v_template uuid;
  v_inst uuid;
  v_assignment uuid;
  v_on date := public.seva_mala_today() - 1;
begin
  insert into public.service_templates
    (service_type_id, day_of_week, start_time, duration_minutes, slots_needed,
     participation_mode, start_date, created_by, days_of_week)
  values (
    v_type, extract(dow from v_on)::integer, time '07:00', 60, 1,
    'invite_only', v_on - 30, v_head, array[extract(dow from v_on)::integer]
  )
  returning id into v_template;

  insert into public.service_instances
    (template_id, service_type_id, date, start_time, duration_minutes,
     slots_needed, participation_mode, posted_by, status)
  values (v_template, v_type, v_on, time '07:00', 60, 1, 'invite_only',
          v_head, 'completed')
  returning id into v_inst;

  -- Completed, and nothing else. No attendance, no member verification.
  insert into public.service_assignments
    (service_instance_id, devotee_id, assignment_method, assigned_by,
     status, verification, completed_at)
  values (
    v_inst, v_weekly, 'recurring_assignment', v_head, 'completed',
    'self_report', (v_on + time '08:00') at time zone 'America/Chicago'
  )
  returning id into v_assignment;

  perform pg_temp.sfm_expect(
    'weekly + completed', v_inst, 'weekly', 'counted', true);

  -- And being marked absent still zeroes it, which is the one thing that
  -- outranks the roster. This occurrence has one place, so marking it absent
  -- also means nobody served it, and 202608040068's rule applies: the honest
  -- terminal state is 'cancelled', and the act leaves the board with the seva.
  perform set_config('request.jwt.claim.sub', v_head::text, true);
  perform public.record_seva_attendance(v_assignment, 'absent');
  perform set_config('request.jwt.claim.sub', '', true);

  if (select instances.status from public.service_instances instances
      where instances.id = v_inst) = 'completed'
  then
    raise exception 'a weekly seva nobody served still reads as completed';
  end if;
  if pg_temp.sfm_minutes(v_inst, 'weekly') <> 0 then
    raise exception 'a weekly seva marked absent still credited minutes';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. A weekly occurrence nobody finished is not seva that happened.
-- ---------------------------------------------------------------------------

do $$
declare
  v_head uuid := (select id from sfm_ids where key = 'head');
  v_who uuid := (select id from sfm_ids where key = 'excused');
  v_type uuid := (select id from public.service_types where name = 'Flow Matrix Seva');
  v_template uuid;
  v_inst uuid;
  v_on date := public.seva_mala_today() - 2;
begin
  insert into public.service_templates
    (service_type_id, day_of_week, start_time, duration_minutes, slots_needed,
     participation_mode, start_date, created_by, days_of_week)
  values (v_type, extract(dow from v_on)::integer, time '06:00', 60, 1,
          'invite_only', v_on - 30, v_head,
          array[extract(dow from v_on)::integer])
  returning id into v_template;

  insert into public.service_instances
    (template_id, service_type_id, date, start_time, duration_minutes,
     slots_needed, participation_mode, posted_by, status)
  values (v_template, v_type, v_on, time '06:00', 60, 1, 'invite_only',
          v_head, 'closed')
  returning id into v_inst;

  insert into public.service_assignments
    (service_instance_id, devotee_id, assignment_method, assigned_by,
     status, verification)
  values (v_inst, v_who, 'recurring_assignment', v_head, 'confirmed',
          'self_report');

  perform pg_temp.sfm_expect(
    'weekly + never finished', v_inst, 'excused', 'awaiting_completion', false);
end;
$$;

do $$
begin
  raise notice 'every seva flow settles the way the temple says it does';
end;
$$;

rollback;
