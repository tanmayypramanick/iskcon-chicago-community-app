-- Registered seva: the devotee's own record, confirmed by a chosen member.
-- Requires 202608040013_seva_request_flow.sql.
--
-- Lifecycle, and who may see each stage:
--
--   pending   the devotee registered it. Visible to the devotee, to the member
--             they named, and to Tech Admin / President. Nobody else — an
--             unconfirmed claim is not community information yet.
--   verified  confirmed. Now visible to every access level that may see seva,
--             and it carries the name of whoever confirmed it.
--   declined  the named member could not confirm it. The devotee keeps the
--             registration and sends it to somebody else.
--
-- Where it appears is decided purely by the clock, never by status:
--   start_at <= now < end_at  -> Seva happening now
--   now < start_at            -> Upcoming seva
--   now >= end_at             -> Completed (listed only once verified)
--
-- Registration is never blocked by verification. Seva that is already wholly
-- in the past cannot be registered at all.

-- ---------------------------------------------------------------------------
-- 1. A devotee may hold several registrations at once (one now, others later).
-- ---------------------------------------------------------------------------

drop index if exists public.one_pending_service_verification_per_devotee;

-- Same seva, same window, twice is a mistake rather than an intent.
create unique index if not exists one_registration_per_seva_window
  on public.service_verifications(devotee_id, start_at, end_at)
  where status <> 'declined';

-- Who actually confirmed it, which may be a Tech Admin or the President
-- overriding the member the devotee originally named.
alter table public.service_verifications
  add column if not exists verified_by uuid references public.users(id);

create index if not exists service_verifications_window_idx
  on public.service_verifications(status, start_at, end_at);

-- ---------------------------------------------------------------------------
-- 2. Registering: now or later, never wholly in the past.
-- ---------------------------------------------------------------------------

create or replace function public.request_seva_verification(
  p_service_type_id uuid,
  p_custom_name text,
  p_start_at timestamptz,
  p_end_at timestamptz,
  p_location_text text,
  p_verifier_id uuid,
  p_qr_token text default null
)
returns public.service_verifications
language plpgsql
security definer
set search_path = ''
as $$
declare
  created_request public.service_verifications;
  resolved_type_id uuid := p_service_type_id;
  resolved_custom text := nullif(trim(p_custom_name), '');
  scanned_at_temple boolean := false;
  devotee_name text;
  seva_name text;
begin
  if auth.uid() is null or not public.has_permission('services.participate') then
    raise exception 'Sign in to register seva.';
  end if;

  if not public.user_has_permission(p_verifier_id, 'services.manage_recurring') then
    raise exception 'Choose a Community Head, Tech Admin, or the President to verify this seva.';
  end if;

  if p_verifier_id = auth.uid() then
    raise exception 'Choose someone else to verify your seva.';
  end if;

  if nullif(trim(p_qr_token), '') is not null then
    select id into resolved_type_id
    from public.service_types
    where qr_token = trim(p_qr_token) and is_active;

    if resolved_type_id is null then
      raise exception 'This is not an active ISKCON Chicago seva QR code.';
    end if;
    resolved_custom := null;
    scanned_at_temple := true;
  end if;

  if (resolved_type_id is null) = (resolved_custom is null) then
    raise exception 'Choose a temple seva or enter one seva name.';
  end if;

  if resolved_type_id is not null and not scanned_at_temple and not exists (
    select 1 from public.service_types where id = resolved_type_id and is_active
  ) then
    raise exception 'The selected seva is not available.';
  end if;

  if p_end_at <= p_start_at
    or p_end_at > p_start_at + interval '12 hours'
  then
    raise exception 'Choose an end time within 12 hours of the start.';
  end if;

  -- Seva already finished cannot be registered. Anything still running or
  -- still ahead is fine, so a devotee can register before they begin.
  if p_end_at <= now() then
    raise exception 'That seva has already finished. Register seva for now or for a time ahead.';
  end if;

  if p_start_at > now() + interval '180 days' then
    raise exception 'Register seva within the next six months.';
  end if;

  insert into public.service_verifications (
    devotee_id, service_type_id, custom_name, start_at, end_at,
    location_text, verifier_id
  )
  values (
    auth.uid(), resolved_type_id, resolved_custom, p_start_at, p_end_at,
    coalesce(nullif(trim(p_location_text), ''), 'ISKCON Chicago Temple'),
    p_verifier_id
  )
  returning * into created_request;

  select name into devotee_name from public.users where id = auth.uid();
  seva_name := coalesce(
    (select name from public.service_types where id = created_request.service_type_id),
    created_request.custom_name
  );

  -- Only the named member is told.
  perform public.queue_app_notification(
    p_verifier_id,
    'seva_verification_requested',
    'Please verify a devotee''s seva',
    devotee_name || ' registered "' || seva_name || '" and asked you to verify it'
      || case when scanned_at_temple then ' (temple QR scanned).' else '.' end,
    jsonb_build_object('serviceVerificationId', created_request.id)
  );

  return created_request;
exception
  when unique_violation then
    raise exception 'You already registered this seva for that time.';
end;
$$;

revoke all on function public.request_seva_verification(uuid, text, timestamptz, timestamptz, text, uuid, text) from public, anon;
grant execute on function public.request_seva_verification(uuid, text, timestamptz, timestamptz, text, uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Verifying. The named member may confirm it; a Tech Admin or the President
--    may confirm or override anything.
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

-- ---------------------------------------------------------------------------
-- 4. Sending a declined registration to somebody else, without re-entering it.
-- ---------------------------------------------------------------------------

create or replace function public.resend_seva_verification(
  p_verification_id uuid,
  p_verifier_id uuid
)
returns public.service_verifications
language plpgsql
security definer
set search_path = ''
as $$
declare
  existing_request public.service_verifications;
  updated_request public.service_verifications;
  devotee_name text;
  seva_name text;
begin
  select * into existing_request
  from public.service_verifications
  where id = p_verification_id
  for update;

  if existing_request.id is null or existing_request.devotee_id <> auth.uid() then
    raise exception 'This seva registration could not be found.';
  end if;

  if existing_request.status = 'verified' then
    raise exception 'This seva has already been verified.';
  end if;

  if not public.user_has_permission(p_verifier_id, 'services.manage_recurring') then
    raise exception 'Choose a Community Head, Tech Admin, or the President to verify this seva.';
  end if;

  if p_verifier_id = auth.uid() then
    raise exception 'Choose someone else to verify your seva.';
  end if;

  if p_verifier_id = existing_request.verifier_id then
    raise exception 'That is the same member. Choose somebody else.';
  end if;

  update public.service_verifications
  set verifier_id = p_verifier_id,
      status = 'pending',
      review_note = null,
      responded_at = null,
      verified_by = null
  where id = p_verification_id
  returning * into updated_request;

  select name into devotee_name from public.users where id = auth.uid();
  seva_name := coalesce(
    (select name from public.service_types where id = updated_request.service_type_id),
    updated_request.custom_name
  );

  perform public.queue_app_notification(
    p_verifier_id,
    'seva_verification_requested',
    'Please verify a devotee''s seva',
    devotee_name || ' asked you to verify "' || seva_name || '".',
    jsonb_build_object('serviceVerificationId', updated_request.id)
  );

  return updated_request;
end;
$$;

revoke all on function public.resend_seva_verification(uuid, uuid) from public, anon;
grant execute on function public.resend_seva_verification(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Removing a registration. The devotee who registered it, a Community Head,
--    a Tech Admin, or the President. Any confirmed record goes with it.
-- ---------------------------------------------------------------------------

create or replace function public.delete_seva_registration(p_verification_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  target public.service_verifications;
  actor_name text;
  seva_name text;
begin
  select * into target
  from public.service_verifications
  where id = p_verification_id
  for update;

  if target.id is null then
    raise exception 'This seva registration could not be found.';
  end if;

  if target.devotee_id <> auth.uid()
    and not public.has_permission('services.manage_recurring')
    and not public.has_permission('app.view_all')
  then
    raise exception 'Only this devotee, a Community Head, a Tech Admin, or the President can remove it.';
  end if;

  select name into actor_name from public.users where id = auth.uid();
  seva_name := coalesce(
    (select name from public.service_types where id = target.service_type_id),
    target.custom_name
  );

  if target.service_instance_id is not null then
    delete from public.service_instances where id = target.service_instance_id;
  end if;

  delete from public.service_verifications where id = p_verification_id;

  if target.devotee_id <> auth.uid() then
    perform public.queue_app_notification(
      target.devotee_id,
      'service_deleted',
      'A seva registration was removed',
      actor_name || ' removed your "' || seva_name || '" seva registration.',
      jsonb_build_object('serviceVerificationId', p_verification_id)
    );
  end if;
end;
$$;

revoke all on function public.delete_seva_registration(uuid) from public, anon;
grant execute on function public.delete_seva_registration(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. Visibility. An unconfirmed registration is the devotee's own business,
--    plus the member asked to confirm it, plus Tech Admin / President.
--    Once verified it becomes community information.
-- ---------------------------------------------------------------------------

drop policy if exists "Devotee verifier and oversight can read seva verifications"
  on public.service_verifications;
drop policy if exists "Registered seva is private until it is verified"
  on public.service_verifications;

create policy "Registered seva is private until it is verified"
  on public.service_verifications for select to authenticated
  using (
    devotee_id = auth.uid()
    or verifier_id = auth.uid()
    or public.has_permission('app.view_all')
    or (status = 'verified' and public.has_permission('services.oversee_activity'))
  );

do $$
begin
  raise notice 'seva registration applied';
end;
$$;
