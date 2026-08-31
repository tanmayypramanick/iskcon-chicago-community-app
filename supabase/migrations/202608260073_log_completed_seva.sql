-- Completed seva is deliberately separate from planning seva.
--
-- `request_seva_verification` accepts only seva that is happening now or in
-- the future. This RPC accepts only seva that has already ended, creates the
-- same private pending-verification record, and notifies only the Community
-- Head / Tech Admin / President selected by the devotee. No completed entry is
-- added to history or seva totals until an authorised member verifies it.

create or replace function public.log_completed_seva(
  p_service_type_id uuid,
  p_custom_name text,
  p_start_at timestamptz,
  p_end_at timestamptz,
  p_location_text text,
  p_verifier_id uuid
)
returns public.service_verifications
language plpgsql
security definer
set search_path = ''
as $$
declare
  created_request public.service_verifications;
  resolved_custom text := nullif(trim(p_custom_name), '');
  devotee_name text;
  seva_name text;
begin
  if auth.uid() is null or not public.has_permission('services.participate') then
    raise exception 'Sign in to log completed seva.';
  end if;

  if not public.user_has_permission(p_verifier_id, 'services.manage_recurring') then
    raise exception 'Choose a Community Head, Tech Admin, or the President to verify this seva.';
  end if;

  if p_verifier_id = auth.uid() then
    raise exception 'Choose someone else to verify your seva.';
  end if;

  if (p_service_type_id is null) = (resolved_custom is null) then
    raise exception 'Choose a temple seva or enter one seva name.';
  end if;

  if p_service_type_id is not null and not exists (
    select 1
    from public.service_types
    where id = p_service_type_id and is_active
  ) then
    raise exception 'The selected seva is not available.';
  end if;

  if p_end_at <= p_start_at
    or p_end_at > p_start_at + interval '12 hours'
  then
    raise exception 'Choose an end time within 12 hours of the start.';
  end if;

  if p_end_at > now() then
    raise exception 'Completed seva must end before the current time.';
  end if;

  if p_start_at < now() - interval '180 days' then
    raise exception 'Completed seva can be logged for up to 180 days.';
  end if;

  insert into public.service_verifications (
    devotee_id,
    service_type_id,
    custom_name,
    start_at,
    end_at,
    location_text,
    verifier_id
  )
  values (
    auth.uid(),
    p_service_type_id,
    resolved_custom,
    p_start_at,
    p_end_at,
    coalesce(nullif(trim(p_location_text), ''), 'ISKCON Chicago Temple'),
    p_verifier_id
  )
  returning * into created_request;

  select name into devotee_name
  from public.users
  where id = auth.uid();

  seva_name := coalesce(
    (select name from public.service_types where id = created_request.service_type_id),
    created_request.custom_name
  );

  perform public.queue_app_notification(
    p_verifier_id,
    'seva_verification_requested',
    'Please verify completed seva',
    devotee_name || ' logged "' || seva_name || '" and asked you to verify it.',
    jsonb_build_object(
      'serviceVerificationId', created_request.id,
      'entryMode', 'completed'
    )
  );

  return created_request;
exception
  when unique_violation then
    raise exception 'You already logged this seva for that time.';
  when exclusion_violation then
    raise exception 'You already have seva that overlaps this time.';
end;
$$;

revoke all on function public.log_completed_seva(
  uuid, text, timestamptz, timestamptz, text, uuid
) from public, anon;

grant execute on function public.log_completed_seva(
  uuid, text, timestamptz, timestamptz, text, uuid
) to authenticated;

do $$
begin
  raise notice 'completed seva logging applied';
end;
$$;
