-- A seva is either SERVABLE or VERIFIABLE, never both.
-- Requires 202608040025_verification_integrity.sql and 202608310095.
--
-- The temple runs two one-off flows and they are settled by different people
-- in different ways. Until now the database could not tell them apart, so the
-- wrong control was offered on the wrong seva and the interface was the only
-- thing keeping them separate.
--
--   POSTED — a coordinator posts it and a devotee takes a place, or is asked
--   and accepts. It is SERVABLE: whoever posted it says whether it was served,
--   and so may a Tech Admin or the President. It is NOT verifiable, because
--   the person who would verify it is the person who posted it.
--
--   REGISTRATION — the devotee added it themselves, either planned ahead
--   (request_seva_verification) or logged after the fact (log_completed_seva),
--   naming a member to confirm it. It is VERIFIABLE: only the member they
--   named, or a Tech Admin or the President, answers it. It is NOT servable —
--   there is no "mark served" step in this flow at all, because verifying it
--   IS saying it happened.
--
-- The distinction existed only as an inference: an instance was "really a
-- registration" if some row in service_verifications pointed at it. That is a
-- second list, and it is permission-scoped, so two readers could reach
-- different answers about the same morning — which is also why the exported
-- hours report could disagree with the board.
--
-- So the instance carries it. One column, set where the row is created, and
-- checked by the functions that decide who may do what.

alter table public.service_instances
  add column if not exists origin text not null default 'posted';

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'service_instance_origin_known'
      and conrelid = 'public.service_instances'::regclass
  ) then
    alter table public.service_instances
      add constraint service_instance_origin_known
      check (origin in ('posted', 'registration'));
  end if;
end;
$$;

comment on column public.service_instances.origin is
  'Which flow created this seva. "posted" is servable: whoever posted it records who served. "registration" is verifiable: the devotee added it and the member they named confirms it, and it has no attendance step at all. Set when the row is created, never inferred from another table.';

-- Everything a verification ever created is a registration. This is the whole
-- backfill: the link has always been recorded, it was simply never authoritative.
update public.service_instances instances
set origin = 'registration'
where origin <> 'registration'
  and exists (
    select 1 from public.service_verifications verifications
    where verifications.service_instance_id = instances.id
  );

-- ---------------------------------------------------------------------------
-- Approving a registration marks the instance as one.
-- ---------------------------------------------------------------------------

create or replace function public.mark_instance_as_registration(p_instance_id uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.service_instances
  set origin = 'registration'
  where id = p_instance_id;
$$;

revoke all on function public.mark_instance_as_registration(uuid)
  from public, anon, authenticated;

comment on function public.mark_instance_as_registration(uuid) is
  'Internal. Stamps an instance as registration-derived at the moment a verification creates it. Not callable by a client.';

-- ---------------------------------------------------------------------------
-- A registration is not servable, by anybody.
--
-- 202608310095 stopped a devotee recording their OWN attendance. This is the
-- other half: nobody records attendance on a registration at all, not the
-- devotee, not a Community Head, not the President. Verifying it is what says
-- it happened, and offering a second, different way to say the same thing is
-- how the two flows drifted into each other.
-- ---------------------------------------------------------------------------

create or replace function public.seva_is_servable(p_instance_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select instances.origin = 'posted'
     from public.service_instances instances
     where instances.id = p_instance_id),
    false
  );
$$;

revoke all on function public.seva_is_servable(uuid) from public, anon;
grant execute on function public.seva_is_servable(uuid) to authenticated;

comment on function public.seva_is_servable(uuid) is
  'True for a posted seva, where attendance is recorded. False for a registration, which is settled by verification instead.';

-- ---------------------------------------------------------------------------
-- The three functions, taught the difference.
-- ---------------------------------------------------------------------------

create or replace function public.respond_to_seva_verification(
  p_verification_id uuid,
  p_approve boolean,
  p_note text default null
)
returns public.service_verifications
language plpgsql
security definer
set search_path = ''
as $$
declare
  pending_request public.service_verifications;
  reviewed_request public.service_verifications;
  created_instance_id uuid;
  chicago_started timestamp;
  duration_minutes integer;
  verifier_name text;
  seva_name text;
begin
  select * into pending_request
  from public.service_verifications
  where id = p_verification_id
  for update;

  if pending_request.id is null or pending_request.status <> 'pending' then
    raise exception 'This seva is no longer waiting for a decision.';
  end if;

  if pending_request.verifier_id <> auth.uid()
    and not public.has_permission('app.view_all')
  then
    raise exception 'Only the member this devotee named, a Tech Admin, or the President can answer this.';
  end if;

  -- Verification means somebody else saw it happen. The Tech Admin and
  -- President override reaches every registration in the temple, including
  -- their own, so their own is excluded explicitly.
  if pending_request.devotee_id = auth.uid() then
    raise exception 'Your own seva has to be verified by somebody else.';
  end if;

  if p_approve then
    chicago_started := pending_request.start_at at time zone 'America/Chicago';
    duration_minutes := greatest(
      1,
      least(
        720,
        ceil(extract(epoch from (pending_request.end_at - pending_request.start_at)) / 60.0)::integer
      )
    );

    insert into public.service_instances (
      service_type_id, custom_name, date, start_time, duration_minutes,
      slots_needed, participation_mode, posted_by, status
    )
    values (
      pending_request.service_type_id, pending_request.custom_name,
      chicago_started::date, chicago_started::time, duration_minutes,
      1, 'invite_only', pending_request.devotee_id,
      -- A confirmed seva still ahead of us is not finished; the clock decides
      -- when it reads as completed.
      case when pending_request.end_at <= now() then 'completed' else 'closed' end
    )
    returning id into created_instance_id;

    -- This instance came from a devotee's own registration, and the column
    -- says so rather than leaving it to be inferred from a second table.
    perform public.mark_instance_as_registration(created_instance_id);

    insert into public.service_assignments (
      service_instance_id, devotee_id, assignment_method, assigned_by,
      status, verification, completed_at, attendance
    )
    values (
      created_instance_id, pending_request.devotee_id, 'member_verified',
      auth.uid(),
      case when pending_request.end_at <= now() then 'completed' else 'confirmed' end,
      'member_verified',
      case when pending_request.end_at <= now() then pending_request.end_at else null end,
      -- The verifier has just said this devotee did this seva. For seva that
      -- is already over, that IS the attendance mark: without it the act waits
      -- at 'awaiting_confirmation' for a confirmation nobody was ever going to
      -- give, because the only person who could give it is the devotee whose
      -- seva it is. Still null for seva ahead of us, where nobody can yet say.
      case when pending_request.end_at <= now() then 'served' else null end
    );
  end if;

  update public.service_verifications
  set status = case when p_approve then 'verified' else 'declined' end,
      review_note = nullif(trim(p_note), ''),
      responded_at = now(),
      verified_by = case when p_approve then auth.uid() else null end,
      service_instance_id = created_instance_id
  where id = p_verification_id
  returning * into reviewed_request;

  select name into verifier_name from public.users where id = auth.uid();
  seva_name := coalesce(
    (select name from public.service_types where id = reviewed_request.service_type_id),
    reviewed_request.custom_name
  );

  perform public.queue_app_notification(
    reviewed_request.devotee_id,
    'seva_verification_reviewed',
    case when p_approve then 'Your seva is confirmed' else 'Your seva was not verified' end,
    case when p_approve
      then verifier_name || ' verified "' || seva_name || '". It is now confirmed.'
      else verifier_name || ' cannot verify your "' || seva_name
           || '" seva. Ask someone else to verify it.'
    end,
    jsonb_build_object('serviceVerificationId', reviewed_request.id)
  );

  if p_approve then
    perform public.notify_service_oversight(
      'service_completed',
      'Seva verified',
      verifier_name || ' verified "' || seva_name || '".',
      jsonb_build_object(
        'serviceInstanceId', created_instance_id,
        'serviceVerificationId', reviewed_request.id
      ),
      auth.uid()
    );
  end if;

  return reviewed_request;
end;
$$;

revoke all on function public.respond_to_seva_verification(uuid, boolean, text)
  from public, anon;
grant execute on function public.respond_to_seva_verification(uuid, boolean, text)
  to authenticated;

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
