-- Nobody verifies their own seva, and nobody is told about their own action.
--
-- respond_to_seva_verification let anyone with app.view_all answer any pending
-- registration. That override exists so a Tech Admin or the President can
-- confirm seva when the named member is unavailable — but it also let them
-- approve seva they had registered themselves, which is the one thing
-- verification is for.
-- Requires 202608040024_seva_request_negotiation.sql.


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
      status, verification, completed_at
    )
    values (
      created_instance_id, pending_request.devotee_id, 'member_verified',
      auth.uid(),
      case when pending_request.end_at <= now() then 'completed' else 'confirmed' end,
      'member_verified',
      case when pending_request.end_at <= now() then pending_request.end_at else null end
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

revoke all on function public.respond_to_seva_verification(uuid, boolean, text) from public, anon;
grant execute on function public.respond_to_seva_verification(uuid, boolean, text) to authenticated;


create or replace function public.reopen_service_exception(p_exception_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  exception_record public.service_exceptions;
  template_record public.service_templates;
  service_name text;
begin
  if not public.has_permission('services.resolve_coverage') then
    raise exception 'Only a Community Head, Tech Admin, or the President can arrange weekly-seva coverage.';
  end if;
  select * into exception_record from public.service_exceptions
  where id = p_exception_id and status = 'pending' for update;
  if exception_record.id is null then raise exception 'This coverage request is no longer pending.'; end if;

  update public.service_exceptions
  set resolution_kind = 'broadcast'
  where request_group_id = exception_record.request_group_id
    and status = 'pending';
  update public.service_instances instances
  set participation_mode = 'open', status = 'open'
  from public.service_exceptions exceptions
  where exceptions.request_group_id = exception_record.request_group_id
    and exceptions.status = 'pending'
    and instances.id = exceptions.service_instance_id
    and instances.status not in ('cancelled', 'completed');

  select templates.* into template_record
  from public.service_templates templates
  join public.service_instances instances on instances.template_id = templates.id
  where instances.id = exception_record.service_instance_id;
  service_name := coalesce(
    (select name from public.service_types where id = template_record.service_type_id),
    template_record.custom_name, 'Temple seva'
  );

  -- Only devotees who can actually take seva are told, and not the person who
  -- reported the unavailability.
  insert into public.app_notifications (user_id, kind, title, body, data)
  select users.id, 'service_open', 'Weekly seva needs help',
    'Open weekly-seva dates are available for "' || service_name || '".',
    jsonb_build_object(
      'serviceTemplateId', template_record.id,
      'serviceExceptionId', exception_record.id,
      'coverageRequestGroupId', exception_record.request_group_id,
      'weeklyOpen', true
    )
  from public.users
  where users.id <> exception_record.devotee_id
    and public.user_has_permission(users.id, 'services.participate');

  -- A coordinator who reported their own unavailability and then opened it
  -- up does not need telling about what they just did.
  if exception_record.devotee_id <> auth.uid() then
  perform public.queue_app_notification(
    exception_record.devotee_id, 'service_coverage_needed',
    'Your seva was opened to the community',
    'Your dates for "' || service_name
      || '" are now open for any devotee to pick up.',
    jsonb_build_object(
      'serviceTemplateId', template_record.id,
      'coverageRequestGroupId', exception_record.request_group_id
    )
  );
  end if;
end;
$$;

revoke all on function public.reopen_service_exception(uuid) from public, anon;
grant execute on function public.reopen_service_exception(uuid) to authenticated;

do $$
begin
  raise notice 'seva verification integrity applied';
end;
$$;
