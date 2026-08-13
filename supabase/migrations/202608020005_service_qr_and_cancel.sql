-- Durable QR service timers and coordinator cancellation.
-- Requires 202608020003_service_recurring_coverage.sql.

update public.service_types
set qr_token = 'iskcon-chicago:seva:' || id::text
where qr_token is null;

create table public.service_qr_sessions (
  id uuid primary key default gen_random_uuid(),
  devotee_id uuid not null references public.users(id) on delete cascade,
  service_type_id uuid not null references public.service_types(id),
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  cancelled_at timestamptz,
  status text not null default 'active' check (
    status in ('active', 'completed', 'cancelled')
  ),
  service_instance_id uuid references public.service_instances(id),
  constraint service_qr_session_completion_consistency check (
    (
      status = 'active'
      and completed_at is null
      and cancelled_at is null
      and service_instance_id is null
    )
    or
    (
      status = 'completed'
      and completed_at is not null
      and cancelled_at is null
      and service_instance_id is not null
    )
    or
    (
      status = 'cancelled'
      and cancelled_at is not null
      and completed_at is null
      and service_instance_id is null
    )
  )
);

create unique index one_active_qr_session_per_devotee
  on public.service_qr_sessions(devotee_id)
  where status = 'active';

alter table public.app_notifications
  drop constraint app_notifications_kind_check;

alter table public.app_notifications
  add constraint app_notifications_kind_check check (
    kind in (
      'service_open',
      'service_offer',
      'service_recurring_offer',
      'service_offer_response',
      'service_joined',
      'service_left',
      'service_completed',
      'service_cancelled',
      'service_coverage_needed',
      'service_coverage_resolved',
      'remote'
    )
  );

create or replace function public.start_qr_service_session(p_qr_token text)
returns public.service_qr_sessions
language plpgsql
security definer
set search_path = ''
as $$
declare
  selected_service_type public.service_types;
  active_session public.service_qr_sessions;
  created_session public.service_qr_sessions;
begin
  if auth.uid() is null then
    raise exception 'Authentication is required.';
  end if;

  select * into selected_service_type
  from public.service_types
  where qr_token = trim(p_qr_token)
    and is_active;

  if selected_service_type.id is null then
    raise exception 'This is not an active ISKCON Chicago service QR code.';
  end if;

  select * into active_session
  from public.service_qr_sessions
  where devotee_id = auth.uid()
    and status = 'active'
  for update;

  if active_session.id is not null then
    if active_session.service_type_id = selected_service_type.id then
      return active_session;
    end if;
    raise exception 'Finish or cancel your current QR service timer first.';
  end if;

  insert into public.service_qr_sessions (devotee_id, service_type_id)
  values (auth.uid(), selected_service_type.id)
  returning * into created_session;

  return created_session;
end;
$$;

create or replace function public.complete_qr_service_session(p_session_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  session_record public.service_qr_sessions;
  duration_minutes integer;
  chicago_started timestamp;
  created_instance_id uuid;
begin
  select * into session_record
  from public.service_qr_sessions
  where id = p_session_id
    and devotee_id = auth.uid()
  for update;

  if session_record.id is null or session_record.status <> 'active' then
    raise exception 'This QR service timer is no longer active.';
  end if;

  if now() - session_record.started_at > interval '12 hours' then
    raise exception 'A QR service timer cannot exceed 12 hours.';
  end if;

  duration_minutes := greatest(
    30,
    least(
      720,
      ceil(extract(epoch from (now() - session_record.started_at)) / 1800.0)::integer * 30
    )
  );
  chicago_started := session_record.started_at at time zone 'America/Chicago';

  insert into public.service_instances (
    service_type_id,
    custom_name,
    date,
    start_time,
    duration_minutes,
    slots_needed,
    participation_mode,
    posted_by,
    status
  )
  values (
    session_record.service_type_id,
    null,
    chicago_started::date,
    chicago_started::time,
    duration_minutes,
    1,
    'invite_only',
    auth.uid(),
    'completed'
  )
  returning id into created_instance_id;

  insert into public.service_assignments (
    service_instance_id,
    devotee_id,
    assignment_method,
    assigned_by,
    status,
    verification,
    qr_scanned_at,
    completed_at
  )
  values (
    created_instance_id,
    auth.uid(),
    'qr_scan',
    null,
    'completed',
    'qr_scan',
    session_record.started_at,
    now()
  );

  update public.service_qr_sessions
  set
    status = 'completed',
    completed_at = now(),
    service_instance_id = created_instance_id
  where id = p_session_id;

  return created_instance_id;
end;
$$;

create or replace function public.cancel_qr_service_session(p_session_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.service_qr_sessions
  set status = 'cancelled', cancelled_at = now()
  where id = p_session_id
    and devotee_id = auth.uid()
    and status = 'active';

  if not found then
    raise exception 'This QR service timer is no longer active.';
  end if;
end;
$$;

create or replace function public.cancel_service_instance(p_instance_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  instance_record public.service_instances;
begin
  select * into instance_record
  from public.service_instances
  where id = p_instance_id
  for update;

  if instance_record.id is null
    or instance_record.status in ('completed', 'cancelled')
  then
    raise exception 'This service can no longer be cancelled.';
  end if;

  if instance_record.posted_by is distinct from auth.uid()
    and not public.has_permission('services.manage_recurring')
  then
    raise exception 'You are not allowed to cancel this service.';
  end if;

  insert into public.app_notifications (user_id, kind, title, body, data)
  select
    service_assignments.devotee_id,
    'service_cancelled',
    'Service cancelled',
    '"' || public.service_instance_name(instance_record) || '" on ' ||
      to_char(instance_record.date, 'FMDay, FMMonth FMDD') ||
      ' has been cancelled.',
    jsonb_build_object('serviceInstanceId', instance_record.id)
  from public.service_assignments
  where service_assignments.service_instance_id = instance_record.id
    and service_assignments.status in ('assigned', 'confirmed')
    and service_assignments.devotee_id <> auth.uid();

  update public.service_instances
  set status = 'cancelled'
  where id = p_instance_id;

  update public.service_assignments
  set status = 'withdrawn'
  where service_instance_id = p_instance_id
    and status in ('assigned', 'confirmed');

  update public.service_offers
  set status = 'expired', responded_at = now()
  where service_instance_id = p_instance_id
    and status = 'pending';
end;
$$;

alter table public.service_qr_sessions enable row level security;

create policy "Users can read their QR service sessions"
  on public.service_qr_sessions for select
  to authenticated
  using (devotee_id = auth.uid());

revoke all on public.service_qr_sessions from anon, authenticated;
grant select on public.service_qr_sessions to authenticated;

revoke all on function public.start_qr_service_session(text) from public;
revoke all on function public.complete_qr_service_session(uuid) from public;
revoke all on function public.cancel_qr_service_session(uuid) from public;
revoke all on function public.cancel_service_instance(uuid) from public;

grant execute on function public.start_qr_service_session(text) to authenticated;
grant execute on function public.complete_qr_service_session(uuid) to authenticated;
grant execute on function public.cancel_qr_service_session(uuid) to authenticated;
grant execute on function public.cancel_service_instance(uuid) to authenticated;
