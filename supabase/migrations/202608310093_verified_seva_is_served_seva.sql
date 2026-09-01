-- Verifying seva that has already happened records that it was served.
-- Requires 202608040025_verification_integrity.sql and
-- 202608260073_log_completed_seva.sql.
--
-- "Log your seva" exists for seva that is already over: the devotee describes
-- what they did, names a Community Head, Tech Admin or President, and that
-- person verifies it. 0073's own header says what is meant to follow — "no
-- completed entry is added to history or seva totals until an authorised
-- member verifies it" — which reads as: once verified, it counts.
--
-- It did not count. respond_to_seva_verification created the instance and the
-- assignment with status 'completed' and verification 'member_verified', and
-- left `attendance` NULL. The points rule (0057, restated in 0059) needs three
-- things together for a one-off act — completed, verified AND served — so the
-- act sat at 'awaiting_confirmation' with zero credited minutes, for ever, and
-- nothing in the flow was ever going to mark it.
--
-- THE RULE IS NOT WEAKENED, and deliberately so: 0057's cross-product test
-- walks all eighty combinations and names the row this behaviour exists for —
-- "everything but the attendance mark: zero points, and told so in words".
-- That stays exactly as it is.
--
-- What changes is that the flow now records the fact the verifier just
-- attested. A Community Head answering "yes, they did this seva" IS the
-- confirmation that they served it; there is no second question to ask. The
-- alternative was worse: a logged seva's instance is posted_by the devotee
-- themselves, so the only person able to mark the attendance was the devotee,
-- and points would have rested on self-certification.
--
-- Only for seva that has ENDED. A verification approved for seva still ahead
-- of us keeps attendance null, because nobody can yet say whether they were
-- there — the same `end_at <= now()` test that already decides 'completed'
-- versus 'closed' just below.

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

-- ---------------------------------------------------------------------------
-- Proof, run at migration time. Seeded and rolled back, never deleted.
-- ---------------------------------------------------------------------------
do $$
declare
  v_dev  uuid := '73000000-0000-0000-0000-000000000001';
  v_head uuid := '73000000-0000-0000-0000-000000000002';
  v_type uuid;
  v_req public.service_verifications;
  v_status text;
  v_minutes numeric;
  v_attendance text;
begin
  begin
    insert into auth.users (id, email, raw_user_meta_data) values
      (v_dev,  'lp-dev@example.test',  jsonb_build_object('name','Logging Devotee')),
      (v_head, 'lp-head@example.test', jsonb_build_object('name','Verifying Head'));

    update public.users
    set role_id = (select id from public.roles where name = 'president')
    where id = v_head;

    insert into public.service_types (name, category)
    values ('Log Points Proof Seva', 'other')
    returning id into v_type;

    -- The devotee logs an hour of seva that finished two hours ago.
    perform set_config('request.jwt.claim.sub', v_dev::text, true);
    v_req := public.log_completed_seva(
      v_type, null, now() - interval '3 hours', now() - interval '2 hours',
      'ISKCON Chicago Temple', v_head
    );

    -- Before anybody answers, it earns nothing. That has always been true and
    -- must stay true.
    select acts.points_status into v_status
    from public.seva_mala_acts(v_dev) acts limit 1;
    if v_status is not null then
      raise exception
        'an unanswered log already had a points status of %', v_status;
    end if;

    -- The Head verifies it.
    perform set_config('request.jwt.claim.sub', v_head::text, true);
    perform public.respond_to_seva_verification(v_req.id, true, null);
    perform set_config('request.jwt.claim.sub', '', true);

    select acts.points_status, acts.credited_minutes, acts.attendance
    into v_status, v_minutes, v_attendance
    from public.seva_mala_acts(v_dev) acts limit 1;

    if v_attendance is distinct from 'served' then
      raise exception
        'verifying finished seva left attendance as %', coalesce(v_attendance, 'null');
    end if;
    if v_status is distinct from 'counted' then
      raise exception
        'verified completed seva reads as % rather than counted', v_status;
    end if;
    if coalesce(v_minutes, 0) <= 0 then
      raise exception
        'verified completed seva credited % minutes', coalesce(v_minutes, 0);
    end if;

    raise exception 'ISKCON_PROOF_ROLLBACK';
  exception
    when others then
      if sqlerrm <> 'ISKCON_PROOF_ROLLBACK' then
        raise;
      end if;
  end;

  raise notice 'logged seva earns its points once a member verifies it';
end;
$$;
