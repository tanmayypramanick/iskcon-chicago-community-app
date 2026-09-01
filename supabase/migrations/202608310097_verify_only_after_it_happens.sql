-- Nothing is verified before it happens, and what was already is settled.
-- Requires 202608310093 and 202608310096.
--
-- The temple's rule, in the President's words: verification cannot be ahead of
-- time — once the seva has been done, only then can it be verified.
--
-- respond_to_seva_verification accepted an approval at any moment. Approving a
-- seva that had not happened created the instance 'closed' with attendance
-- null, because on that day nobody could yet say whether the devotee was
-- there. It then had nowhere to go: a self-added seva is verifiable and not
-- servable, so no attendance step exists to finish it, and the act sat at
-- 'awaiting_confirmation' earning nothing. A devotee could plan seva, have it
-- verified, do it, and never be credited.
--
-- Two halves.
--
--   GOING FORWARD, approval is refused until the seva has ended. Declining
--   stays open at any time: refusing to vouch for something is not a claim
--   about whether it happened, and a verifier should be able to turn down a
--   request the moment they see it is wrong.
--
--   FOR WHAT ALREADY EXISTS, settle_finished_verified_seva records the
--   attendance the verifier attested once the seva has ended — and it is
--   scheduled, which it never was. Nothing in this schema ever called it, so
--   those rows sat at 'closed' indefinitely and even the completion never
--   arrived.

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

  -- Nothing is verified before it happens.
  --
  -- A devotee may ADD seva ahead of time, but verifying it is a member saying
  -- "yes, they did this", and nobody can say that about a seva that has not
  -- happened yet. Approval used to be accepted at any time, which created the
  -- instance 'closed' with no attendance — a seva stuck between planned and
  -- done, earning nothing, with no step left in its flow to finish it.
  --
  -- Declining is still allowed at any time: refusing to vouch for something is
  -- not a claim about whether it happened, and a verifier should be able to
  -- turn down a request the moment they see it is wrong.
  if p_approve and pending_request.end_at > now() then
    raise exception 'This seva has not finished yet. It can be verified once it is done.';
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

create or replace function public.settle_finished_verified_seva()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  moved uuid[];
  moved_instance uuid;
begin
  with due as (
    select verifications.id as verification_id,
           verifications.service_instance_id,
           verifications.devotee_id,
           verifications.end_at
    from public.service_verifications verifications
    join public.service_instances instances
      on instances.id = verifications.service_instance_id
    where verifications.status = 'verified'
      and verifications.end_at <= now()
      and instances.status = 'closed'
  ), moved_assignments as (
    update public.service_assignments assignments
    set status = 'completed',
        completed_at = coalesce(assignments.completed_at, due.end_at),
        -- The member verified this seva, and it has now ended. The same
        -- reasoning as 202608310093, applied to the rows that were approved
        -- early before that was refused: without it they reach completed +
        -- member_verified + NULL, which earns nothing and has no step left to
        -- fix it. coalesce, not an overwrite — an absence somebody recorded in
        -- the meantime is their decision and outranks the clock.
        attendance = coalesce(assignments.attendance, 'served')
    from due
    where assignments.service_instance_id = due.service_instance_id
      and assignments.devotee_id = due.devotee_id
      and assignments.status in ('assigned', 'confirmed')
    returning assignments.id
  ), moved_instances as (
    update public.service_instances instances
    set status = 'completed'
    from due
    where instances.id = due.service_instance_id
    returning instances.id
  )
  select coalesce(array_agg(moved_instances.id), '{}'::uuid[])
  into moved
  from moved_instances;

  foreach moved_instance in array moved loop
    perform public.reconcile_service_instance_completion(moved_instance);
  end loop;

  return coalesce(array_length(moved, 1), 0);
end;
$$;

revoke all on function public.settle_finished_verified_seva()
  from public, anon, authenticated;


-- Hourly, so a seva that ends is settled within the hour rather than never.
-- Guarded on pg_cron the way every other schedule in this repo is: nothing
-- happens at all where the extension is absent, which is every local and CI
-- database this file is applied to.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    if exists (select 1 from cron.job where jobname = 'settle-finished-verified-seva') then
      perform cron.unschedule('settle-finished-verified-seva');
    end if;
    perform cron.schedule(
      'settle-finished-verified-seva', '15 * * * *',
      'select public.settle_finished_verified_seva();'
    );
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Proof, run at migration time. Seeded and rolled back, never deleted.
-- ---------------------------------------------------------------------------
do $$
declare
  v_head uuid := '7a000000-0000-0000-0000-000000000001';
  v_dev  uuid := '7a000000-0000-0000-0000-000000000002';
  v_type uuid;
  v_req public.service_verifications;
  v_inst uuid;
  v_points text;
  v_refused boolean := false;
begin
  begin
    insert into auth.users (id, email, raw_user_meta_data) values
      (v_head, 'sf-head@example.test', jsonb_build_object('name', 'Settling Head')),
      (v_dev,  'sf-dev@example.test',  jsonb_build_object('name', 'Planning Devotee'));

    update public.users
    set role_id = (select id from public.roles where name = 'president')
    where id = v_head;

    insert into public.service_types (name, category)
    values ('Settle Proof Seva', 'other')
    returning id into v_type;

    -- Planned for later today, and the member tries to verify it now.
    perform set_config('request.jwt.claim.sub', v_dev::text, true);
    v_req := public.request_seva_verification(
      v_type, null, now() + interval '30 minutes', now() + interval '90 minutes',
      'ISKCON Chicago Temple', v_head, null
    );

    perform set_config('request.jwt.claim.sub', v_head::text, true);
    begin
      perform public.respond_to_seva_verification(v_req.id, true, null);
    exception when others then
      v_refused := true;
    end;
    if not v_refused then
      raise exception 'a seva that had not happened yet was verified';
    end if;

    -- Declining it is still allowed, because that is not a claim about
    -- whether it happened.
    perform public.respond_to_seva_verification(v_req.id, false, 'Not this one.');
    perform set_config('request.jwt.claim.sub', '', true);

    -- And a seva that HAS finished verifies and counts, unchanged.
    perform set_config('request.jwt.claim.sub', v_dev::text, true);
    v_req := public.log_completed_seva(
      v_type, null, now() - interval '3 hours', now() - interval '2 hours',
      'ISKCON Chicago Temple', v_head
    );
    perform set_config('request.jwt.claim.sub', v_head::text, true);
    perform public.respond_to_seva_verification(v_req.id, true, null);
    perform set_config('request.jwt.claim.sub', '', true);

    select verifications.service_instance_id into v_inst
    from public.service_verifications verifications
    where verifications.id = v_req.id;

    select acts.points_status into v_points
    from public.seva_mala_acts(v_dev) acts
    where acts.service_instance_id = v_inst;

    if v_points is distinct from 'counted' then
      raise exception
        'seva done then verified reads as % rather than counted',
        coalesce(v_points, '<no act>');
    end if;

    raise exception 'ISKCON_PROOF_ROLLBACK';
  exception
    when others then
      if sqlerrm <> 'ISKCON_PROOF_ROLLBACK' then
        raise;
      end if;
  end;

  raise notice 'nothing is verified before it happens';
end;
$$;
