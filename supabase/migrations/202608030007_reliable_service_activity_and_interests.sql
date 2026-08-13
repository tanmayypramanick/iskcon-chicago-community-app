-- Reliable live seva tracking, devotee-owned completion, recurring-service
-- interest approval, private recurring assignee visibility, and notification
-- clearing. Requires 202608020005 and 202608020006.

insert into public.role_permissions (role_id, permission_key)
select roles.id, 'services.track_live'
from public.roles
where roles.name in ('president', 'tech', 'core', 'volunteer', 'devotee')
on conflict (role_id, permission_key) do nothing;

delete from public.role_permissions
where permission_key = 'services.self_log';

alter table public.service_qr_sessions
  add column if not exists started_via text,
  add column if not exists updated_at timestamptz not null default now();

update public.service_qr_sessions
set started_via = 'qr'
where started_via is null;

alter table public.service_qr_sessions
  alter column started_via set default 'qr',
  alter column started_via set not null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.service_qr_sessions'::regclass
      and conname = 'service_session_started_via_check'
  ) then
    alter table public.service_qr_sessions
      add constraint service_session_started_via_check check (
        started_via in ('qr', 'service_list')
      );
  end if;
end;
$$;

alter table public.service_assignments
  drop constraint if exists service_assignments_assignment_method_check;

alter table public.service_assignments
  add constraint service_assignments_assignment_method_check check (
    assignment_method in (
      'self_joined',
      'accepted_offer',
      'recurring_assignment',
      'accepted_coverage_offer',
      'self_logged',
      'live_timer',
      'qr_scan'
    )
  );

alter table public.service_assignments
  drop constraint if exists service_assignments_verification_check;

alter table public.service_assignments
  add constraint service_assignments_verification_check check (
    verification in ('self_report', 'live_timer', 'qr_scan')
  );

create table public.recurring_service_interests (
  id uuid primary key default gen_random_uuid(),
  devotee_id uuid not null unique references public.users(id) on delete cascade,
  skills text not null,
  desired_service_type_ids uuid[] not null default '{}'::uuid[],
  other_service text,
  availability text not null,
  currently_serving boolean not null default false,
  current_service_details text,
  status text not null default 'pending' check (
    status in ('pending', 'approved', 'denied')
  ),
  submitted_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references public.users(id),
  review_note text,
  constraint recurring_interest_skills_not_blank check (
    length(trim(skills)) between 2 and 1000
  ),
  constraint recurring_interest_availability_not_blank check (
    length(trim(availability)) between 2 and 1000
  ),
  constraint recurring_interest_has_service_choice check (
    cardinality(desired_service_type_ids) > 0
    or length(trim(coalesce(other_service, ''))) >= 2
    or (
      currently_serving
      and length(trim(coalesce(current_service_details, ''))) >= 2
    )
  ),
  constraint recurring_interest_current_service_consistency check (
    not currently_serving
    or length(trim(coalesce(current_service_details, ''))) >= 2
  ),
  constraint recurring_interest_review_consistency check (
    (
      status = 'pending'
      and reviewed_at is null
      and reviewed_by is null
    )
    or (
      status in ('approved', 'denied')
      and reviewed_at is not null
      and reviewed_by is not null
    )
  )
);

create index recurring_service_interests_status_submitted_idx
  on public.recurring_service_interests(status, submitted_at desc);

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
      'service_started',
      'service_completed',
      'service_cancelled',
      'service_coverage_needed',
      'service_coverage_resolved',
      'recurring_interest_submitted',
      'recurring_interest_reviewed',
      'remote'
    )
  );

create or replace function public.notify_service_oversight(
  p_kind text,
  p_title text,
  p_body text,
  p_data jsonb default '{}'::jsonb,
  p_exclude_user_id uuid default null
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  inserted_count integer;
begin
  insert into public.app_notifications (user_id, kind, title, body, data)
  select distinct
    users.id,
    p_kind,
    p_title,
    p_body,
    coalesce(p_data, '{}'::jsonb)
  from public.users
  join public.role_permissions
    on role_permissions.role_id = users.role_id
   and role_permissions.permission_key = 'services.manage_recurring'
  where p_exclude_user_id is null or users.id <> p_exclude_user_id;

  get diagnostics inserted_count = row_count;
  return inserted_count;
end;
$$;

create or replace function public.start_list_service_session(
  p_service_type_id uuid
)
returns public.service_qr_sessions
language plpgsql
security definer
set search_path = ''
as $$
declare
  selected_service_type public.service_types;
  active_session public.service_qr_sessions;
  created_session public.service_qr_sessions;
  devotee_name text;
begin
  if auth.uid() is null then
    raise exception 'Authentication is required.';
  end if;

  if not public.has_permission('services.track_live') then
    raise exception 'You are not allowed to start a seva timer.';
  end if;

  select * into selected_service_type
  from public.service_types
  where id = p_service_type_id
    and is_active;

  if selected_service_type.id is null then
    raise exception 'The selected seva is not available.';
  end if;

  select * into active_session
  from public.service_qr_sessions
  where devotee_id = auth.uid()
    and status = 'active'
  for update;

  if active_session.id is not null then
    if active_session.service_type_id = selected_service_type.id
      and active_session.started_via = 'service_list'
    then
      return active_session;
    end if;
    raise exception 'Finish or cancel your current seva timer first.';
  end if;

  insert into public.service_qr_sessions (
    devotee_id,
    service_type_id,
    started_via
  )
  values (
    auth.uid(),
    selected_service_type.id,
    'service_list'
  )
  returning * into created_session;

  select name into devotee_name
  from public.users
  where id = auth.uid();

  perform public.notify_service_oversight(
    'service_started',
    'A devotee started seva',
    devotee_name || ' started "' || selected_service_type.name || '".',
    jsonb_build_object(
      'serviceSessionId', created_session.id,
      'devoteeId', auth.uid()
    ),
    auth.uid()
  );

  return created_session;
end;
$$;

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
  devotee_name text;
begin
  if auth.uid() is null then
    raise exception 'Authentication is required.';
  end if;

  if not public.has_permission('services.track_live') then
    raise exception 'You are not allowed to start a seva timer.';
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
    if active_session.service_type_id = selected_service_type.id
      and active_session.started_via = 'qr'
    then
      return active_session;
    end if;
    raise exception 'Finish or cancel your current seva timer first.';
  end if;

  insert into public.service_qr_sessions (
    devotee_id,
    service_type_id,
    started_via
  )
  values (
    auth.uid(),
    selected_service_type.id,
    'qr'
  )
  returning * into created_session;

  select name into devotee_name
  from public.users
  where id = auth.uid();

  perform public.notify_service_oversight(
    'service_started',
    'QR-verified seva started',
    devotee_name || ' scanned the QR code for "' ||
      selected_service_type.name || '".',
    jsonb_build_object(
      'serviceSessionId', created_session.id,
      'devoteeId', auth.uid(),
      'verification', 'qr_scan'
    ),
    auth.uid()
  );

  return created_session;
end;
$$;

create or replace function public.complete_service_session(p_session_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  session_record public.service_qr_sessions;
  selected_service_type public.service_types;
  duration_minutes integer;
  chicago_started timestamp;
  created_instance_id uuid;
  devotee_name text;
begin
  if not public.has_permission('services.track_live') then
    raise exception 'You are not allowed to complete a seva timer.';
  end if;

  select * into session_record
  from public.service_qr_sessions
  where id = p_session_id
    and devotee_id = auth.uid()
  for update;

  if session_record.id is null or session_record.status <> 'active' then
    raise exception 'This seva timer is no longer active.';
  end if;

  if now() - session_record.started_at > interval '12 hours' then
    raise exception 'A seva timer cannot exceed 12 hours.';
  end if;

  select * into selected_service_type
  from public.service_types
  where id = session_record.service_type_id;

  duration_minutes := greatest(
    30,
    least(
      720,
      ceil(
        extract(epoch from (now() - session_record.started_at)) / 1800.0
      )::integer * 30
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
    case
      when session_record.started_via = 'qr' then 'qr_scan'
      else 'live_timer'
    end,
    null,
    'completed',
    case
      when session_record.started_via = 'qr' then 'qr_scan'
      else 'live_timer'
    end,
    case
      when session_record.started_via = 'qr' then session_record.started_at
      else null
    end,
    now()
  );

  update public.service_qr_sessions
  set
    status = 'completed',
    completed_at = now(),
    service_instance_id = created_instance_id,
    updated_at = now()
  where id = p_session_id;

  select name into devotee_name
  from public.users
  where id = auth.uid();

  perform public.notify_service_oversight(
    'service_completed',
    'A devotee completed seva',
    devotee_name || ' completed "' || selected_service_type.name || '".',
    jsonb_build_object(
      'serviceInstanceId', created_instance_id,
      'serviceSessionId', session_record.id,
      'devoteeId', auth.uid(),
      'verification', session_record.started_via
    ),
    auth.uid()
  );

  return created_instance_id;
end;
$$;

create or replace function public.complete_qr_service_session(p_session_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  session_method text;
begin
  select started_via into session_method
  from public.service_qr_sessions
  where id = p_session_id
    and devotee_id = auth.uid();

  if session_method is distinct from 'qr' then
    raise exception 'This is not a QR-verified seva timer.';
  end if;

  return public.complete_service_session(p_session_id);
end;
$$;

create or replace function public.cancel_service_session(p_session_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.service_qr_sessions
  set
    status = 'cancelled',
    cancelled_at = now(),
    updated_at = now()
  where id = p_session_id
    and devotee_id = auth.uid()
    and status = 'active';

  if not found then
    raise exception 'This seva timer is no longer active.';
  end if;
end;
$$;

create or replace function public.cancel_qr_service_session(p_session_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.cancel_service_session(p_session_id);
end;
$$;

create or replace function public.complete_my_service_assignment(
  p_instance_id uuid
)
returns public.service_assignments
language plpgsql
security definer
set search_path = ''
as $$
declare
  instance_record public.service_instances;
  completed_assignment public.service_assignments;
  completed_count integer;
  devotee_name text;
begin
  if auth.uid() is null then
    raise exception 'Authentication is required.';
  end if;

  select * into instance_record
  from public.service_instances
  where id = p_instance_id
  for update;

  if instance_record.id is null
    or instance_record.status in ('completed', 'cancelled')
  then
    raise exception 'This service can no longer be completed.';
  end if;

  update public.service_assignments
  set
    status = 'completed',
    completed_at = now()
  where service_instance_id = p_instance_id
    and devotee_id = auth.uid()
    and status in ('assigned', 'confirmed')
  returning * into completed_assignment;

  if completed_assignment.id is null then
    raise exception 'You do not have an active assignment for this service.';
  end if;

  select count(*) into completed_count
  from public.service_assignments
  where service_instance_id = p_instance_id
    and status = 'completed';

  if completed_count >= instance_record.slots_needed then
    update public.service_instances
    set status = 'completed'
    where id = p_instance_id;
  end if;

  select name into devotee_name
  from public.users
  where id = auth.uid();

  perform public.notify_service_oversight(
    'service_completed',
    'Assigned seva completed',
    devotee_name || ' completed "' ||
      public.service_instance_name(instance_record) || '".',
    jsonb_build_object(
      'serviceInstanceId', p_instance_id,
      'devoteeId', auth.uid()
    ),
    auth.uid()
  );

  return completed_assignment;
end;
$$;

create or replace function public.submit_recurring_service_interest(
  p_skills text,
  p_desired_service_type_ids uuid[],
  p_other_service text,
  p_availability text,
  p_currently_serving boolean,
  p_current_service_details text
)
returns public.recurring_service_interests
language plpgsql
security definer
set search_path = ''
as $$
declare
  requested_service_type_id uuid;
  submitted_interest public.recurring_service_interests;
  devotee_name text;
begin
  if auth.uid() is null then
    raise exception 'Authentication is required.';
  end if;

  if length(trim(coalesce(p_skills, ''))) < 2 then
    raise exception 'Please tell us about your skills.';
  end if;

  if length(trim(coalesce(p_availability, ''))) < 2 then
    raise exception 'Please share your recurring availability.';
  end if;

  if cardinality(coalesce(p_desired_service_type_ids, '{}'::uuid[])) = 0
    and length(trim(coalesce(p_other_service, ''))) < 2
    and not (
      coalesce(p_currently_serving, false)
      and length(trim(coalesce(p_current_service_details, ''))) >= 2
    )
  then
    raise exception 'Choose a recurring seva or describe one.';
  end if;

  if coalesce(p_currently_serving, false)
    and length(trim(coalesce(p_current_service_details, ''))) < 2
  then
    raise exception 'Please describe your current recurring seva.';
  end if;

  foreach requested_service_type_id in array coalesce(
    p_desired_service_type_ids,
    '{}'::uuid[]
  )
  loop
    if not exists (
      select 1
      from public.service_types
      where id = requested_service_type_id
        and is_active
    ) then
      raise exception 'One selected recurring seva is unavailable.';
    end if;
  end loop;

  insert into public.recurring_service_interests (
    devotee_id,
    skills,
    desired_service_type_ids,
    other_service,
    availability,
    currently_serving,
    current_service_details,
    status,
    submitted_at,
    updated_at,
    reviewed_at,
    reviewed_by,
    review_note
  )
  values (
    auth.uid(),
    trim(p_skills),
    coalesce(p_desired_service_type_ids, '{}'::uuid[]),
    nullif(trim(p_other_service), ''),
    trim(p_availability),
    coalesce(p_currently_serving, false),
    case
      when coalesce(p_currently_serving, false)
        then nullif(trim(p_current_service_details), '')
      else null
    end,
    'pending',
    now(),
    now(),
    null,
    null,
    null
  )
  on conflict (devotee_id) do update set
    skills = excluded.skills,
    desired_service_type_ids = excluded.desired_service_type_ids,
    other_service = excluded.other_service,
    availability = excluded.availability,
    currently_serving = excluded.currently_serving,
    current_service_details = excluded.current_service_details,
    status = 'pending',
    submitted_at = now(),
    updated_at = now(),
    reviewed_at = null,
    reviewed_by = null,
    review_note = null
  returning * into submitted_interest;

  select name into devotee_name
  from public.users
  where id = auth.uid();

  perform public.notify_service_oversight(
    'recurring_interest_submitted',
    'Recurring seva interest',
    devotee_name || ' submitted recurring seva details for review.',
    jsonb_build_object(
      'recurringInterestId', submitted_interest.id,
      'devoteeId', auth.uid()
    ),
    auth.uid()
  );

  return submitted_interest;
end;
$$;

create or replace function public.review_recurring_service_interest(
  p_interest_id uuid,
  p_approve boolean,
  p_review_note text default null
)
returns public.recurring_service_interests
language plpgsql
security definer
set search_path = ''
as $$
declare
  reviewed_interest public.recurring_service_interests;
  reviewer_name text;
begin
  if not public.has_permission('services.manage_recurring') then
    raise exception 'You are not allowed to review recurring seva interests.';
  end if;

  update public.recurring_service_interests
  set
    status = case when p_approve then 'approved' else 'denied' end,
    reviewed_at = now(),
    reviewed_by = auth.uid(),
    review_note = nullif(trim(p_review_note), ''),
    updated_at = now()
  where id = p_interest_id
    and status = 'pending'
  returning * into reviewed_interest;

  if reviewed_interest.id is null then
    raise exception 'This recurring seva submission is no longer pending.';
  end if;

  select name into reviewer_name
  from public.users
  where id = auth.uid();

  perform public.queue_app_notification(
    reviewed_interest.devotee_id,
    'recurring_interest_reviewed',
    case
      when p_approve then 'Recurring seva profile verified'
      else 'Recurring seva details need an update'
    end,
    reviewer_name || case
      when p_approve then ' verified your recurring seva profile.'
      else ' reviewed your recurring seva profile. Please update and resubmit it.'
    end,
    jsonb_build_object('recurringInterestId', reviewed_interest.id)
  );

  return reviewed_interest;
end;
$$;

alter table public.recurring_service_interests enable row level security;

drop policy if exists "Users can read their QR service sessions"
  on public.service_qr_sessions;
create policy "Users and recurring coordinators can read live seva sessions"
  on public.service_qr_sessions for select
  to authenticated
  using (
    devotee_id = auth.uid()
    or public.has_permission('services.manage_recurring')
  );

drop policy if exists "Authenticated users can read service participation"
  on public.service_assignments;
create policy "Users can read permitted service participation"
  on public.service_assignments for select
  to authenticated
  using (
    assignment_method <> 'recurring_assignment'
    or devotee_id = auth.uid()
    or public.has_permission('services.manage_recurring')
  );

drop policy if exists "Authenticated users can read recurring assignees"
  on public.service_template_assignees;
create policy "Users and recurring coordinators can read recurring assignees"
  on public.service_template_assignees for select
  to authenticated
  using (
    devotee_id = auth.uid()
    or public.has_permission('services.manage_recurring')
  );

create policy "Users and recurring coordinators can read recurring interests"
  on public.recurring_service_interests for select
  to authenticated
  using (
    devotee_id = auth.uid()
    or public.has_permission('services.manage_recurring')
  );

drop policy if exists "Users can clear their app notifications"
  on public.app_notifications;
create policy "Users can clear their app notifications"
  on public.app_notifications for delete
  to authenticated
  using (user_id = auth.uid());

revoke all on public.recurring_service_interests from anon, authenticated;
grant select on public.recurring_service_interests to authenticated;
grant delete on public.app_notifications to authenticated;

revoke execute on function public.log_completed_service(uuid, text, date, time, integer)
  from authenticated;

revoke all on function public.notify_service_oversight(text, text, text, jsonb, uuid) from public;
revoke all on function public.start_list_service_session(uuid) from public;
revoke all on function public.complete_service_session(uuid) from public;
revoke all on function public.cancel_service_session(uuid) from public;
revoke all on function public.complete_my_service_assignment(uuid) from public;
revoke all on function public.submit_recurring_service_interest(text, uuid[], text, text, boolean, text) from public;
revoke all on function public.review_recurring_service_interest(uuid, boolean, text) from public;

grant execute on function public.start_list_service_session(uuid) to authenticated;
grant execute on function public.complete_service_session(uuid) to authenticated;
grant execute on function public.cancel_service_session(uuid) to authenticated;
grant execute on function public.complete_my_service_assignment(uuid) to authenticated;
grant execute on function public.submit_recurring_service_interest(text, uuid[], text, text, boolean, text) to authenticated;
grant execute on function public.review_recurring_service_interest(uuid, boolean, text) to authenticated;

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'service_qr_sessions'
  ) then
    alter publication supabase_realtime
      add table public.service_qr_sessions;
  end if;

  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'recurring_service_interests'
  ) then
    alter publication supabase_realtime
      add table public.recurring_service_interests;
  end if;
end;
$$;
