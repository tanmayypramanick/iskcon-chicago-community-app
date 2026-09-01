-- A weekly seva is not marked served or absent.
-- Requires 202608310096.
--
-- The temple's rule, in the President's words: for weekly seva there is no
-- need to be served, absent and so on — it is automatic, and a devotee who
-- cannot make their day asks for coverage.
--
-- That is already how it counts: 202608040059 credits a recurring act on
-- completion alone, with no verification level and no attendance mark owed.
-- Marking somebody absent on a rota was a second, quieter way of saying "they
-- were not there" which settled nothing — the day still had nobody on it, and
-- nobody had been asked to take it. Coverage is the mechanism that actually
-- does something: it names a substitute, or opens the day, or asks another
-- devotee.
--
-- So attendance is refused on a recurring occurrence, the way it is already
-- refused on a registration. Three kinds of seva, three ways of settling, and
-- none of them borrowing another's controls:
--
--   POSTED        marked served by whoever posted it
--   REGISTRATION  verified by the member the devotee named
--   WEEKLY        automatic on completion; coverage when somebody cannot go
--
-- WHAT THIS DOES NOT DO, said plainly. seva_points_status still zeroes an act
-- whose attendance reads 'absent' or 'excused' — that rule is untouched and
-- its eighty-combination test still passes — so any weekly row already
-- carrying an absence keeps it. Nothing rewrites history here. What changes is
-- that no new one can be written.
--
-- The consequence is worth stating too: a devotee who quietly misses their
-- weekly day, and does not ask for coverage, now keeps the credit for it.
-- That is what "automatic" costs, and it is the temple's call to make.

create or replace function public.record_seva_attendance(
  p_assignment_id uuid,
  p_attendance text
)
returns public.service_assignments
language plpgsql
security definer
set search_path = ''
as $$
declare
  assignment_record public.service_assignments;
  instance_record public.service_instances;
  updated_assignment public.service_assignments;
  actor_name text;
  v_period record;
begin
  if p_attendance is not null
    and p_attendance not in ('served', 'absent', 'excused')
  then
    raise exception 'Attendance is served, absent, or excused.';
  end if;

  select * into assignment_record from public.service_assignments
  where id = p_assignment_id for update;
  if assignment_record.id is null then
    raise exception 'This seva place could not be found.';
  end if;

  select * into instance_record from public.service_instances
  where id = assignment_record.service_instance_id;

  -- The same authority that closes a seva says who was there for it.
  if instance_record.posted_by is distinct from auth.uid()
    and not public.has_permission('app.view_all')
  then
    raise exception 'Only the devotee who posted this seva, a Tech Admin, or the President can record attendance.';
  end if;




  -- Weekly seva has no attendance step, and no absence either.
  --
  -- The temple's rule: a weekly rota runs by itself. It counts on completion
  -- alone (202608040059) and a devotee who cannot make their day asks for
  -- coverage — that is the mechanism, and it names a substitute rather than
  -- leaving a hole. Marking somebody absent on a rota was a second, quieter
  -- way of saying the same thing, and it settled nothing: the day still had
  -- nobody on it.
  if instance_record.template_id is not null then
    raise exception 'A weekly seva is not marked served or absent. If a devotee cannot make their day, arrange coverage for it.';
  end if;

  -- A registration is not servable, by anybody. The devotee added this seva
  -- themselves and named a member to confirm it; verifying it IS saying it
  -- happened. Offering a second, different way to say the same thing is how
  -- the two flows drifted into each other, and it is what put a "mark served"
  -- control on a seva that has no such step.
  if not public.seva_is_servable(instance_record.id) then
    raise exception 'This seva was added by the devotee and is settled by verifying it, not by recording attendance.';
  end if;

  -- Nobody records their own attendance, whoever they are.
  --
  -- A self-added or logged seva creates its instance with posted_by = THE
  -- DEVOTEE (202608040025), so the "did you post this?" test above says yes to
  -- them for their own seva. For one planned ahead, the approver leaves
  -- attendance null — nobody can say yet whether they were there — and once
  -- the time passed the devotee could mark themselves served and complete the
  -- act: completed + member_verified + served, which is full points awarded by
  -- the devotee to themselves.
  --
  -- 202608040025 states the principle this closes: verification means somebody
  -- else saw it happen. A self-added seva is settled by the member who was
  -- asked to verify it; there is no "mark served" step in that flow, and this
  -- is what makes that true rather than merely intended.
  if assignment_record.devotee_id = auth.uid() then
    raise exception 'Somebody else records whether you served. Seva you added yourself is settled by the member you asked to verify it.';
  end if;

  if ((instance_record.date + instance_record.start_time)
      at time zone 'America/Chicago') > now() then
    raise exception 'Attendance can be recorded once the seva has started.';
  end if;

  update public.service_assignments
  set attendance = p_attendance,
      -- Recording that a devotee served IS the verification, when the person
      -- recording it is somebody else. A posted seva has no verification step
      -- — the coordinator who posted it closes it out — so the assignment kept
      -- the 'self_report' it was given on joining, and a one-off act needs
      -- completed AND verified AND served together. The seva was served, the
      -- coordinator said so, and it still earned nothing.
      --
      -- Only from 'self_report': a qr_scan or a live_timer is a better record
      -- of the same fact and must not be overwritten by a weaker one.
      --
      -- And only when the devotee is not marking themselves. 0025 states the
      -- principle this rests on — "verification means somebody else saw it
      -- happen" — so a coordinator serving a seva they posted themselves still
      -- needs another member, exactly as before.
      verification = case
        when p_attendance = 'served'
          and service_assignments.verification = 'self_report'
          and service_assignments.devotee_id <> auth.uid()
        then 'member_verified'
        else service_assignments.verification
      end
  where id = p_assignment_id
  returning * into updated_assignment;

  select name into actor_name from public.users where id = auth.uid();

  -- Being marked absent is worth knowing about; being marked present is not.
  if p_attendance = 'absent' and assignment_record.devotee_id <> auth.uid() then
    perform public.queue_app_notification(
      assignment_record.devotee_id, 'service_left',
      'Marked as not attending',
      actor_name || ' recorded that you were not able to attend "'
        || public.service_instance_name(instance_record) || '" on '
        || public.format_seva_when(instance_record.date, instance_record.start_time)
        || '. Tell them if that is wrong.',
      jsonb_build_object('serviceInstanceId', instance_record.id)
    );
  end if;

  -- Sentence 2. One word from a coordinator can be the last word on whether
  -- this seva happened at all, in either direction.
  perform public.reconcile_service_instance_completion(instance_record.id);

  -- Sentence 3, and the reason this migration exists. Every Seva Mala period
  -- covering the day of this seva is reopened and recounted, so the points
  -- follow the correction instead of outliving it. Only when the attendance
  -- actually changed: an idempotent re-save must not thaw a frozen week.
  if updated_assignment.attendance is distinct from assignment_record.attendance
  then
    for v_period in
      select periods.id
      from public.seva_mala_periods periods
      where instance_record.date between periods.starts_on and periods.ends_on
    loop
      update public.seva_mala_periods
      set frozen_at = null
      where id = v_period.id;

      perform public.recompute_seva_mala_period(v_period.id);
    end loop;
  end if;

  return updated_assignment;
end;
$$;

create or replace function public.record_unanswered_seva_attendance(
  p_instance_id uuid,
  p_attendance text default 'served'
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  instance_record public.service_instances;
  v_marked integer;
begin
  if p_attendance not in ('served', 'absent', 'excused') then
    raise exception 'Attendance is served, absent, or excused.';
  end if;

  select * into instance_record from public.service_instances
  where id = p_instance_id;
  if instance_record.id is null then
    raise exception 'This seva could not be found.';
  end if;

  -- The same authority as record_seva_attendance, checked here rather than
  -- inherited, because this does not go through it.
  if instance_record.posted_by is distinct from auth.uid()
    and not public.has_permission('app.view_all')
  then
    raise exception 'Only the devotee who posted this seva, a Tech Admin, or the President can record attendance.';
  end if;



  -- The same rule as record_seva_attendance: a weekly rota is not marked.
  if instance_record.template_id is not null then
    raise exception 'A weekly seva is not marked served or absent. If a devotee cannot make their day, arrange coverage for it.';
  end if;

  -- The same rule as record_seva_attendance: a registration has no attendance
  -- step. Refused rather than silently answering nothing, so a caller is told
  -- why instead of watching a tap do nothing.
  if not public.seva_is_servable(p_instance_id) then
    raise exception 'This seva was added by the devotee and is settled by verifying it, not by recording attendance.';
  end if;

  if ((instance_record.date + instance_record.start_time)
      at time zone 'America/Chicago') > now() then
    raise exception 'Attendance can be recorded once the seva has started.';
  end if;

  -- `attendance is null` is the whole guard: an answered place is somebody
  -- else's decision and is not this tap's to revisit.
  with marked as (
    update public.service_assignments
    set attendance = p_attendance,
        -- Recording that a devotee served IS the verification, when the person
        -- recording it is somebody else. A posted seva has no verification step
        -- — the coordinator who posted it closes it out — so the assignment kept
        -- the 'self_report' it was given on joining, and a one-off act needs
        -- completed AND verified AND served together. The seva was served, the
        -- coordinator said so, and it still earned nothing.
        --
        -- Only from 'self_report': a qr_scan or a live_timer is a better record
        -- of the same fact and must not be overwritten by a weaker one.
        --
        -- And only when the devotee is not marking themselves. 0025 states the
        -- principle this rests on — "verification means somebody else saw it
        -- happen" — so a coordinator serving a seva they posted themselves still
        -- needs another member, exactly as before.
        verification = case
          when p_attendance = 'served'
            and service_assignments.verification = 'self_report'
            and service_assignments.devotee_id <> auth.uid()
          then 'member_verified'
          else service_assignments.verification
        end
    where service_instance_id = p_instance_id
      and attendance is null
      and status in ('assigned', 'confirmed', 'completed')
      -- Never the caller's own place. One tap that answers everybody's silence
      -- must not quietly answer the tapper's own: see the guard in
      -- record_seva_attendance for why.
      and devotee_id <> auth.uid()
    returning id
  )
  select count(*) into v_marked from marked;

  -- One word from a coordinator can be the last word on whether this seva
  -- happened at all, in either direction — the same sentence
  -- record_seva_attendance ends on.
  perform public.reconcile_service_instance_completion(p_instance_id);

  -- And the same reopening 202608310084 added, for the same reason: a
  -- correction must not be outlived by a frozen week.
  if v_marked > 0 then
    update public.seva_mala_periods
    set frozen_at = null
    where instance_record.date between starts_on and ends_on;

    perform public.recompute_seva_mala_period(periods.id)
    from public.seva_mala_periods periods
    where instance_record.date between periods.starts_on and periods.ends_on;
  end if;

  return v_marked;
end;
$$;

revoke all on function public.record_seva_attendance(uuid, text) from public, anon;
grant execute on function public.record_seva_attendance(uuid, text) to authenticated;

revoke all on function public.record_unanswered_seva_attendance(uuid, text)
  from public, anon;
grant execute on function public.record_unanswered_seva_attendance(uuid, text)
  to authenticated;

-- ---------------------------------------------------------------------------
-- Proof, run at migration time. Seeded and rolled back, never deleted.
-- ---------------------------------------------------------------------------
do $$
declare
  v_head uuid := '7b000000-0000-0000-0000-000000000001';
  v_dev  uuid := '7b000000-0000-0000-0000-000000000002';
  v_type uuid;
  v_template uuid;
  v_inst uuid;
  v_asg uuid;
  v_on date := (now() at time zone 'America/Chicago')::date - 1;
  v_refused boolean := false;
  v_marked integer;
  v_points text;
begin
  begin
    insert into auth.users (id, email, raw_user_meta_data) values
      (v_head, 'wk-head@example.test', jsonb_build_object('name', 'Weekly Head')),
      (v_dev,  'wk-dev@example.test',  jsonb_build_object('name', 'Weekly Devotee'));

    update public.users
    set role_id = (select id from public.roles where name = 'president')
    where id = v_head;

    insert into public.service_types (name, category)
    values ('Weekly Absence Proof Seva', 'other')
    returning id into v_type;

    insert into public.service_templates
      (service_type_id, day_of_week, start_time, duration_minutes, slots_needed,
       participation_mode, start_date, created_by, days_of_week)
    values (v_type, extract(dow from v_on)::integer, time '07:00', 60, 1,
            'invite_only', v_on - 30, v_head,
            array[extract(dow from v_on)::integer])
    returning id into v_template;

    insert into public.service_instances
      (template_id, service_type_id, date, start_time, duration_minutes,
       slots_needed, participation_mode, posted_by, status)
    values (v_template, v_type, v_on, time '07:00', 60, 1, 'invite_only',
            v_head, 'completed')
    returning id into v_inst;

    insert into public.service_assignments
      (service_instance_id, devotee_id, assignment_method, assigned_by,
       status, verification, completed_at)
    values (v_inst, v_dev, 'recurring_assignment', v_head, 'completed',
            'self_report', (v_on + time '08:00') at time zone 'America/Chicago')
    returning id into v_asg;

    perform set_config('request.jwt.claim.sub', v_head::text, true);

    begin
      perform public.record_seva_attendance(v_asg, 'absent');
    exception when others then
      v_refused := true;
    end;
    if not v_refused then
      raise exception 'a devotee was marked absent on a weekly seva';
    end if;

    v_refused := false;
    begin
      perform public.record_seva_attendance(v_asg, 'served');
    exception when others then
      v_refused := true;
    end;
    if not v_refused then
      raise exception 'a devotee was marked served on a weekly seva';
    end if;

    v_refused := false;
    begin
      v_marked := public.record_unanswered_seva_attendance(v_inst, 'served');
    exception when others then
      v_refused := true;
    end;
    if not v_refused then
      raise exception 'the one-tap form answered a weekly seva';
    end if;

    perform set_config('request.jwt.claim.sub', '', true);

    -- And it still counts, on completion alone, exactly as before.
    select acts.points_status into v_points
    from public.seva_mala_acts(v_dev) acts
    where acts.service_instance_id = v_inst;
    if v_points is distinct from 'counted' then
      raise exception
        'a completed weekly seva reads as % rather than counted',
        coalesce(v_points, '<no act>');
    end if;

    raise exception 'ISKCON_PROOF_ROLLBACK';
  exception
    when others then
      if sqlerrm <> 'ISKCON_PROOF_ROLLBACK' then
        raise;
      end if;
  end;

  raise notice 'a weekly seva is not marked served or absent';
end;
$$;
