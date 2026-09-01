-- A posted seva earns its points when the coordinator says it was served.
-- Requires 202608310084 and 202608310085.
--
-- The temple runs two different flows and they settle a seva differently.
--
--   POSTED seva — a coordinator posts it, a devotee assigns themselves or is
--   assigned, and the coordinator closes it out. There is no verification
--   step here and there should not be: the person who posted it is the person
--   who says whether it happened.
--
--   SELF-ADDED or LOGGED seva — the devotee describes seva they did, names a
--   Community Head, Tech Admin or President, and that member verifies it.
--   202608310093 made that path record the attendance the verifier attested.
--
-- The points rule needs a one-off act to be completed AND verified AND served
-- together, and joining a posted seva writes verification = 'self_report'
-- (202608030009). Nothing in the posted flow ever changed it. So: devotee
-- serves, coordinator marks them served, coordinator completes the seva — and
-- the act reads 'awaiting_verification' with zero credited minutes, waiting on
-- a step that flow does not have.
--
-- THE RULE IS UNTOUCHED, again. 0057's eighty-combination test still passes
-- unchanged. What changes is that recording attendance now records who
-- recorded it: a coordinator marking a devotee served has verified that seva,
-- and the row now says so.
--
-- Two guards, both deliberate:
--   * only from 'self_report' — a qr_scan or live_timer is a better record of
--     the same fact and is never overwritten by a weaker one;
--   * only when somebody else is marking it, because 0025's principle is that
--     "verification means somebody else saw it happen". A coordinator who
--     serves a seva they posted themselves still needs another member.

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
  v_head uuid := '75000000-0000-0000-0000-000000000001';
  v_dev  uuid := '75000000-0000-0000-0000-000000000002';
  v_type uuid;
  v_inst uuid;
  v_assignment uuid;
  v_status text;
  v_minutes numeric;
  v_verification text;
begin
  begin
    insert into auth.users (id, email, raw_user_meta_data) values
      (v_head, 'pp-head@example.test', jsonb_build_object('name', 'Poster Head')),
      (v_dev,  'pp-dev@example.test',  jsonb_build_object('name', 'Serving Devotee'));

    update public.users
    set role_id = (select id from public.roles where name = 'president')
    where id = v_head;

    insert into public.service_types (name, category)
    values ('Posted Points Proof Seva', 'other')
    returning id into v_type;

    -- Posted for yesterday morning, one place.
    insert into public.service_instances
      (service_type_id, date, start_time, duration_minutes, slots_needed,
       participation_mode, posted_by, status)
    values (v_type, public.seva_mala_today() - 1, time '09:00', 60, 1,
            'open', v_head, 'open')
    returning id into v_inst;

    -- The devotee assigns themselves, exactly as join_service does.
    insert into public.service_assignments
      (service_instance_id, devotee_id, assignment_method, assigned_by,
       status, verification)
    values (v_inst, v_dev, 'self_joined', v_dev, 'confirmed', 'self_report')
    returning id into v_assignment;

    -- The coordinator closes it out.
    perform set_config('request.jwt.claim.sub', v_head::text, true);
    perform public.record_seva_attendance(v_assignment, 'served');
    perform public.complete_service_instance(v_inst);
    perform set_config('request.jwt.claim.sub', '', true);

    select assignments.verification into v_verification
    from public.service_assignments assignments
    where assignments.id = v_assignment;

    select acts.points_status, acts.credited_minutes
    into v_status, v_minutes
    from public.seva_mala_acts(v_dev) acts
    where acts.service_instance_id = v_inst;

    if v_verification is distinct from 'member_verified' then
      raise exception
        'the coordinator marked them served and verification stayed %',
        v_verification;
    end if;
    if v_status is distinct from 'counted' then
      raise exception
        'a posted seva that was served reads as % rather than counted', v_status;
    end if;
    if coalesce(v_minutes, 0) <= 0 then
      raise exception 'a posted seva that was served credited % minutes',
        coalesce(v_minutes, 0);
    end if;

    raise exception 'ISKCON_PROOF_ROLLBACK';
  exception
    when others then
      if sqlerrm <> 'ISKCON_PROOF_ROLLBACK' then
        raise;
      end if;
  end;

  raise notice 'a posted seva earns its points when the coordinator says it was served';
end;
$$;
