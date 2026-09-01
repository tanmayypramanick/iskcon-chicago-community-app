-- Nobody records their own attendance.
-- Requires 202608310093 and 202608310094.
--
-- A self-added or logged seva creates its instance with posted_by = the
-- DEVOTEE (202608040025 section on approval), because it is their seva. That
-- means the "did you post this?" authority test in record_seva_attendance says
-- yes to them, for their own seva.
--
-- For seva logged after the fact that costs nothing: 202608310093 already
-- recorded the attendance the verifier attested, so there is nothing left to
-- mark. For seva PLANNED ahead through request_seva_verification it is a hole:
-- the approver leaves attendance null, because on the day of approval nobody
-- can yet say whether the devotee was there. Once the seva's time passed, the
-- devotee could record themselves served and close their own seva out —
-- completed + member_verified + served — and award themselves full points with
-- nobody else involved. Measured before this migration, not inferred.
--
-- The temple's model, in the President's words: a posted seva is marked served
-- by whoever posted it, and a self-added seva does not have a "mark served"
-- step at all — it is settled by the member who was asked to verify it. This
-- is what makes that true in the database rather than only in the interface.
--
-- 202608040025 already states the principle: verification means somebody else
-- saw it happen. It excluded a Tech Admin or President from answering their
-- own verification for exactly this reason; this extends the same rule to
-- attendance, which is the other way an act reaches 'counted'.
--
-- Weekly seva is untouched. complete_my_service_assignment lets a devotee
-- close out their own weekly occurrence, which 202608040059 documents as
-- deliberate, and it writes status rather than attendance — a recurring act
-- counts on completion alone and never needed an attendance mark.

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
  v_head uuid := '79000000-0000-0000-0000-000000000001';
  v_dev  uuid := '79000000-0000-0000-0000-000000000002';
  v_type uuid;
  v_req public.service_verifications;
  v_asg uuid;
  v_inst uuid;
  v_refused boolean := false;
  v_marked integer;
begin
  begin
    insert into auth.users (id, email, raw_user_meta_data) values
      (v_head, 'nc-head@example.test', jsonb_build_object('name', 'Verifying Head')),
      (v_dev,  'nc-dev@example.test',  jsonb_build_object('name', 'Planning Devotee'));

    update public.users
    set role_id = (select id from public.roles where name = 'president')
    where id = v_head;

    insert into public.service_types (name, category)
    values ('No Self Certification Seva', 'other')
    returning id into v_type;

    -- The devotee logs seva and the Head verifies it, which is the flow that
    -- creates an instance the devotee themselves "posted".
    perform set_config('request.jwt.claim.sub', v_dev::text, true);
    v_req := public.log_completed_seva(
      v_type, null, now() - interval '3 hours', now() - interval '2 hours',
      'ISKCON Chicago Temple', v_head
    );
    perform set_config('request.jwt.claim.sub', v_head::text, true);
    perform public.respond_to_seva_verification(v_req.id, true, null);
    perform set_config('request.jwt.claim.sub', '', true);

    select assignments.id, assignments.service_instance_id
    into v_asg, v_inst
    from public.service_assignments assignments
    where assignments.devotee_id = v_dev;

    -- The devotee tries to record their own attendance on their own seva.
    perform set_config('request.jwt.claim.sub', v_dev::text, true);
    begin
      perform public.record_seva_attendance(v_asg, 'served');
    exception when others then
      v_refused := true;
    end;

    -- And tries the one-tap form, which must skip their own place.
    v_marked := public.record_unanswered_seva_attendance(v_inst, 'served');
    perform set_config('request.jwt.claim.sub', '', true);

    if not v_refused then
      raise exception 'a devotee recorded their own attendance';
    end if;
    if v_marked <> 0 then
      raise exception
        'the one-tap form answered the caller''s own place (% marked)', v_marked;
    end if;

    -- The member's verification still settles it, exactly as before.
    if (select assignments.attendance from public.service_assignments assignments
        where assignments.id = v_asg) is distinct from 'served'
    then
      raise exception 'the verifier''s attestation was lost';
    end if;

    raise exception 'ISKCON_PROOF_ROLLBACK';
  exception
    when others then
      if sqlerrm <> 'ISKCON_PROOF_ROLLBACK' then
        raise;
      end if;
  end;

  raise notice 'nobody records their own attendance';
end;
$$;
