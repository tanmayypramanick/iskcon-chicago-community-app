-- Seva request flow: one way to offer seva, verified by a chosen member.
-- Requires 202608040012_seva_verification_and_counter_offers.sql.
--
-- 1. The live timer is withdrawn. A devotee identifies the seva by scanning the
--    temple QR or picking it from the catalog, states the start and end time,
--    and names the member who will verify it. Nothing self-completes.
-- 2. Whoever posted an open seva request can mark it completed, not only a
--    Community Head. Until they do, the finished seva stays out of the
--    community's completed list.
-- 3. President and Tech Admin keep unconditional access to everything.

-- ---------------------------------------------------------------------------
-- 1. Retire the live timer at the privilege layer, so it cannot come back by
--    accident. The tables stay for the history they already hold.
-- ---------------------------------------------------------------------------

revoke execute on function public.start_list_service_session(uuid) from authenticated;
revoke execute on function public.start_qr_service_session(text) from authenticated;
revoke execute on function public.start_planned_service_session(uuid, text, timestamptz, timestamptz, text) from authenticated;
revoke execute on function public.start_planned_qr_service_session(text, timestamptz, timestamptz, text) from authenticated;
revoke execute on function public.complete_service_session(uuid) from authenticated;

-- Cancelling and deleting stay available so any timer still open from before
-- this migration can be cleared by its owner or by Tech/President.

-- ---------------------------------------------------------------------------
-- 2. A scanned temple QR identifies the seva for a verification request.
--    The token is resolved server-side; it is never sent to a client.
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
    raise exception 'Sign in to offer seva.';
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

  -- The seva must already be under way: a request cannot be filed for a time
  -- that has not arrived, and cannot be backdated more than a day.
  if p_start_at > now() + interval '15 minutes' then
    raise exception 'Seva can only be offered once it has started.';
  end if;

  if p_start_at < now() - interval '24 hours' then
    raise exception 'Seva must be offered on the day it is done.';
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

  -- Only the named member is told. No broadcast: this is one devotee asking
  -- one member to confirm what they saw.
  perform public.queue_app_notification(
    p_verifier_id,
    'seva_verification_requested',
    'Please verify a devotee''s seva',
    devotee_name || ' is asking you to verify "' || seva_name || '"'
      || case when scanned_at_temple then ' (temple QR scanned).' else '.' end,
    jsonb_build_object('serviceVerificationId', created_request.id)
  );

  return created_request;
exception
  when unique_violation then
    raise exception 'You already have a seva waiting to be verified.';
end;
$$;

revoke all on function public.request_seva_verification(uuid, text, timestamptz, timestamptz, text, uuid, text) from public, anon;
grant execute on function public.request_seva_verification(uuid, text, timestamptz, timestamptz, text, uuid, text) to authenticated;

-- The six-argument version is superseded; drop it so PostgREST cannot pick it.
drop function if exists public.request_seva_verification(uuid, text, timestamptz, timestamptz, text, uuid);

-- ---------------------------------------------------------------------------
-- 3. The devotee who posted a seva request closes it out.
--    A finished seva only reaches the community's completed list at that point.
-- ---------------------------------------------------------------------------

create or replace function public.complete_service_instance(p_instance_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  instance_record public.service_instances;
  participant record;
  actor_name text;
begin
  select * into instance_record
  from public.service_instances
  where id = p_instance_id
  for update;

  if instance_record.id is null then
    raise exception 'This seva request could not be found.';
  end if;

  -- Whoever posted it may close it, as may anyone with temple-wide access.
  if instance_record.posted_by is distinct from auth.uid()
    and not public.has_permission('services.complete_requirement')
    and not public.has_permission('app.view_all')
  then
    raise exception 'Only the devotee who posted this seva request, a Tech Admin, or the President can complete it.';
  end if;

  update public.service_instances set status = 'completed'
  where id = p_instance_id and status not in ('completed', 'cancelled');
  if not found then raise exception 'This seva can no longer be completed.'; end if;

  update public.service_assignments
  set status = 'completed', completed_at = coalesce(completed_at, now())
  where service_instance_id = p_instance_id
    and status in ('assigned', 'confirmed');

  select * into instance_record from public.service_instances where id = p_instance_id;
  select name into actor_name from public.users where id = auth.uid();

  for participant in
    select distinct devotee_id from public.service_assignments
    where service_instance_id = p_instance_id and devotee_id <> auth.uid()
  loop
    perform public.queue_app_notification(
      participant.devotee_id, 'service_completed', 'Seva marked completed',
      actor_name || ' marked "' || public.service_instance_name(instance_record) || '" completed.',
      jsonb_build_object('serviceInstanceId', p_instance_id)
    );
  end loop;

  perform public.notify_service_oversight(
    'service_completed', 'A seva request was completed',
    actor_name || ' completed "' || public.service_instance_name(instance_record) || '".',
    jsonb_build_object('serviceInstanceId', p_instance_id), auth.uid()
  );
end;
$$;

revoke all on function public.complete_service_instance(uuid) from public, anon;
grant execute on function public.complete_service_instance(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. President and Tech Admin see everything, unconditionally.
--    `app.view_all` is their marker; wire it into the read paths that only
--    checked the narrower service permissions.
-- ---------------------------------------------------------------------------

create or replace function public.can_view_service_instance(p_instance_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.service_instances instances
    where instances.id = p_instance_id
      and (
        public.has_permission('app.view_all')
        or public.has_permission('services.view_all')
        or instances.posted_by = auth.uid()
        or (
          instances.status = 'open'
          and instances.participation_mode = 'open'
        )
        or exists (
          select 1 from public.service_assignments assignments
          where assignments.service_instance_id = instances.id
            and assignments.devotee_id = auth.uid()
            and assignments.status in ('assigned', 'confirmed', 'completed')
        )
        or exists (
          select 1 from public.service_offers offers
          where offers.service_instance_id = instances.id
            and offers.offered_to = auth.uid()
            and offers.status = 'pending'
        )
      )
  );
$$;

revoke all on function public.can_view_service_instance(uuid) from public, anon;
grant execute on function public.can_view_service_instance(uuid) to authenticated;

do $$
begin
  raise notice 'seva request flow applied';
end;
$$;
