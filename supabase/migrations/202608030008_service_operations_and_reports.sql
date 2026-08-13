-- Full service-operations upgrade: custom live seva, planned end times,
-- automatic completion, secure deletion/reporting, multi-day recurring
-- schedules, editable templates, and date-scoped coverage substitutions.
-- Requires 202608030007_reliable_service_activity_and_interests.sql.

insert into public.role_permissions (role_id, permission_key)
select roles.id, permissions.permission_key
from public.roles
cross join (
  values
    ('services.oversee_activity'),
    ('services.complete_requirement')
) as permissions(permission_key)
where roles.name in ('president', 'tech', 'core', 'volunteer')
on conflict (role_id, permission_key) do nothing;

insert into public.role_permissions (role_id, permission_key)
select roles.id, permissions.permission_key
from public.roles
cross join (
  values
    ('services.delete_any'),
    ('services.export_reports')
) as permissions(permission_key)
where roles.name in ('president', 'tech')
on conflict (role_id, permission_key) do nothing;

-- Volunteers may post and invite for one-time seva, but recurring coverage is
-- intentionally limited to Core, Tech, and President.
delete from public.role_permissions
where permission_key = 'services.resolve_coverage'
  and role_id = (select id from public.roles where name = 'volunteer');

alter table public.service_qr_sessions
  alter column service_type_id drop not null,
  add column if not exists custom_name text,
  add column if not exists planned_end_at timestamptz,
  add column if not exists location_text text not null default 'ISKCON Chicago Temple',
  add column if not exists auto_completed boolean not null default false;

update public.service_qr_sessions
set planned_end_at = least(started_at + interval '1 hour', started_at + interval '12 hours')
where planned_end_at is null;

alter table public.service_qr_sessions
  alter column planned_end_at set not null;

alter table public.service_qr_sessions
  drop constraint if exists service_session_started_via_check,
  add constraint service_session_started_via_check check (
    started_via in ('qr', 'service_list', 'custom')
  ),
  add constraint service_session_has_one_name check (
    (service_type_id is not null and custom_name is null)
    or
    (service_type_id is null and length(trim(custom_name)) between 2 and 100)
  ),
  add constraint service_session_planned_time_check check (
    planned_end_at > started_at
    and planned_end_at <= started_at + interval '12 hours'
  ),
  add constraint service_session_location_check check (
    length(trim(location_text)) between 2 and 120
  );

alter table public.service_instances
  drop constraint if exists service_instances_duration_minutes_check;

alter table public.service_instances
  add constraint service_instances_duration_minutes_check check (
    duration_minutes between 1 and 720
  );

alter table public.service_templates
  alter column service_type_id drop not null,
  add column if not exists custom_name text,
  add column if not exists days_of_week integer[];

alter table public.service_templates
  drop constraint if exists service_templates_duration_minutes_check;

alter table public.service_templates
  add constraint service_templates_duration_minutes_check check (
    duration_minutes between 1 and 720
  );

update public.service_templates
set days_of_week = array[day_of_week]
where days_of_week is null;

alter table public.service_templates
  alter column days_of_week set not null,
  alter column days_of_week set default '{}'::integer[],
  add constraint service_template_has_one_name check (
    (service_type_id is not null and custom_name is null)
    or
    (service_type_id is null and length(trim(custom_name)) between 2 and 100)
  ),
  add constraint service_template_days_check check (
    cardinality(days_of_week) between 1 and 7
    and days_of_week <@ array[0,1,2,3,4,5,6]
  );

create table public.service_coverage_plans (
  id uuid primary key default gen_random_uuid(),
  service_exception_id uuid references public.service_exceptions(id) on delete cascade,
  service_template_id uuid not null references public.service_templates(id) on delete cascade,
  original_devotee_id uuid not null references public.users(id) on delete cascade,
  substitute_devotee_id uuid not null references public.users(id) on delete cascade,
  scope text not null check (scope in ('occurrence', 'date_range', 'forever')),
  date_from date not null,
  date_to date,
  status text not null default 'pending' check (
    status in ('pending', 'accepted', 'declined', 'cancelled')
  ),
  created_by uuid not null references public.users(id),
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  constraint service_coverage_plan_people_check check (
    original_devotee_id <> substitute_devotee_id
  ),
  constraint service_coverage_plan_dates_check check (
    (scope = 'occurrence' and date_to = date_from)
    or (scope = 'date_range' and date_to is not null and date_to >= date_from)
    or (scope = 'forever' and date_to is null)
  )
);

create table public.device_push_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  expo_push_token text not null unique,
  platform text not null check (platform in ('ios', 'android')),
  device_name text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  constraint device_push_token_shape check (
    expo_push_token ~ '^(ExponentPushToken|ExpoPushToken)[[][A-Za-z0-9_-]+[]]$'
  )
);

create index device_push_tokens_user_active_idx
  on public.device_push_tokens(user_id, active);

create or replace function public.register_device_push_token(
  p_expo_push_token text,
  p_platform text,
  p_device_name text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  token_id uuid;
begin
  if auth.uid() is null then raise exception 'Sign in to enable notifications.'; end if;
  if p_platform not in ('ios', 'android') then raise exception 'Unsupported device platform.'; end if;
  if trim(p_expo_push_token) !~ '^(ExponentPushToken|ExpoPushToken)[[][A-Za-z0-9_-]+[]]$' then
    raise exception 'Invalid Expo push token.';
  end if;
  insert into public.device_push_tokens (
    user_id, expo_push_token, platform, device_name, active, last_seen_at
  ) values (
    auth.uid(), trim(p_expo_push_token), p_platform,
    nullif(trim(p_device_name), ''), true, now()
  ) on conflict (expo_push_token) do update set
    user_id = auth.uid(), platform = excluded.platform,
    device_name = excluded.device_name, active = true, last_seen_at = now()
  returning id into token_id;
  return token_id;
end;
$$;

create index service_coverage_plans_template_dates_idx
  on public.service_coverage_plans(service_template_id, date_from, date_to, status);

alter table public.service_offers
  add column if not exists service_coverage_plan_id uuid
    references public.service_coverage_plans(id) on delete cascade;

alter table public.service_offers
  drop constraint if exists service_offers_offer_kind_check,
  drop constraint if exists service_offer_context_check;

alter table public.service_offers
  add constraint service_offers_offer_kind_check check (
    offer_kind in ('one_time', 'recurring', 'coverage', 'coverage_range')
  ),
  add constraint service_offer_context_check check (
    (
      offer_kind = 'one_time'
      and service_instance_id is not null
      and service_template_id is null
      and service_exception_id is null
      and service_coverage_plan_id is null
    )
    or (
      offer_kind = 'recurring'
      and service_instance_id is null
      and service_template_id is not null
      and service_exception_id is null
      and service_coverage_plan_id is null
    )
    or (
      offer_kind = 'coverage'
      and service_instance_id is not null
      and service_template_id is null
      and service_exception_id is not null
      and service_coverage_plan_id is null
    )
    or (
      offer_kind = 'coverage_range'
      and service_instance_id is null
      and service_template_id is not null
      and service_exception_id is null
      and service_coverage_plan_id is not null
    )
  );

create unique index service_offers_coverage_plan_recipient_key
  on public.service_offers(service_coverage_plan_id, offered_to)
  where offer_kind = 'coverage_range';

alter table public.app_notifications
  drop constraint app_notifications_kind_check;

alter table public.app_notifications
  add constraint app_notifications_kind_check check (
    kind in (
      'service_open', 'service_offer', 'service_recurring_offer',
      'service_offer_response', 'service_joined', 'service_left',
      'service_started', 'service_completed', 'service_cancelled',
      'service_deleted', 'service_coverage_needed',
      'service_coverage_resolved', 'recurring_interest_submitted',
      'recurring_interest_reviewed', 'remote'
    )
  );

create or replace function public.service_session_name(
  p_session public.service_qr_sessions
)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(service_types.name, p_session.custom_name, 'Temple seva')
  from (select 1) as singleton
  left join public.service_types on service_types.id = p_session.service_type_id;
$$;

create or replace function public.finalize_service_session_internal(
  p_session_id uuid,
  p_auto boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  session_record public.service_qr_sessions;
  finished_at timestamptz;
  chicago_started timestamp;
  duration_minutes integer;
  created_instance_id uuid;
  devotee_name text;
  seva_name text;
begin
  select * into session_record
  from public.service_qr_sessions
  where id = p_session_id
  for update;

  if session_record.id is null or session_record.status <> 'active' then
    return session_record.service_instance_id;
  end if;

  if p_auto and now() < session_record.planned_end_at then
    return null;
  end if;

  finished_at := case
    when p_auto then session_record.planned_end_at
    else least(now(), session_record.planned_end_at)
  end;
  finished_at := greatest(finished_at, session_record.started_at + interval '1 minute');
  duration_minutes := greatest(
    1,
    least(720, ceil(extract(epoch from (finished_at - session_record.started_at)) / 60.0)::integer)
  );
  chicago_started := session_record.started_at at time zone 'America/Chicago';

  insert into public.service_instances (
    service_type_id, custom_name, date, start_time, duration_minutes,
    slots_needed, participation_mode, posted_by, status
  )
  values (
    session_record.service_type_id,
    session_record.custom_name,
    chicago_started::date,
    chicago_started::time,
    duration_minutes,
    1,
    'invite_only',
    session_record.devotee_id,
    'completed'
  )
  returning id into created_instance_id;

  insert into public.service_assignments (
    service_instance_id, devotee_id, assignment_method, assigned_by,
    status, verification, qr_scanned_at, completed_at
  )
  values (
    created_instance_id,
    session_record.devotee_id,
    case when session_record.started_via = 'qr' then 'qr_scan' else 'live_timer' end,
    null,
    'completed',
    case when session_record.started_via = 'qr' then 'qr_scan' else 'live_timer' end,
    case when session_record.started_via = 'qr' then session_record.started_at else null end,
    finished_at
  );

  update public.service_qr_sessions
  set status = 'completed', completed_at = finished_at,
      service_instance_id = created_instance_id, auto_completed = p_auto,
      updated_at = now()
  where id = session_record.id;

  select name into devotee_name from public.users where id = session_record.devotee_id;
  seva_name := public.service_session_name(session_record);
  perform public.notify_service_oversight(
    'service_completed',
    case when p_auto then 'Scheduled seva completed' else 'A devotee completed seva' end,
    devotee_name || ' completed "' || seva_name || '".',
    jsonb_build_object(
      'serviceInstanceId', created_instance_id,
      'serviceSessionId', session_record.id,
      'devoteeId', session_record.devotee_id,
      'autoCompleted', p_auto
    ),
    session_record.devotee_id
  );

  return created_instance_id;
end;
$$;

create or replace function public.complete_due_service_sessions()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  due_session record;
  completed_count integer := 0;
begin
  for due_session in
    select id
    from public.service_qr_sessions
    where status = 'active' and planned_end_at <= now()
    order by planned_end_at
    for update skip locked
  loop
    perform public.finalize_service_session_internal(due_session.id, true);
    completed_count := completed_count + 1;
  end loop;
  return completed_count;
end;
$$;

create or replace function public.start_service_session(
  p_service_type_id uuid,
  p_custom_name text,
  p_started_via text,
  p_start_at timestamptz,
  p_end_at timestamptz,
  p_location_text text
)
returns public.service_qr_sessions
language plpgsql
security definer
set search_path = ''
as $$
declare
  active_session public.service_qr_sessions;
  created_session public.service_qr_sessions;
  devotee_name text;
  seva_name text;
  effective_start timestamptz := coalesce(p_start_at, now());
  effective_end timestamptz := coalesce(p_end_at, coalesce(p_start_at, now()) + interval '1 hour');
begin
  if auth.uid() is null or not public.has_permission('services.track_live') then
    raise exception 'You are not allowed to start a seva timer.';
  end if;
  perform public.complete_due_service_sessions();

  if p_started_via not in ('service_list', 'custom') then
    raise exception 'Choose a valid way to start seva.';
  end if;
  if (p_service_type_id is null) = (length(trim(coalesce(p_custom_name, ''))) < 2) then
    raise exception 'Choose one seva or type a meaningful seva name.';
  end if;
  if p_service_type_id is not null and not exists (
    select 1 from public.service_types where id = p_service_type_id and is_active
  ) then
    raise exception 'The selected seva is not available.';
  end if;
  if effective_start < now() - interval '15 minutes'
    or effective_start > now() + interval '15 minutes'
  then
    raise exception 'A live seva must start now. Adjust the start time to within 15 minutes.';
  end if;
  if effective_end <= effective_start or effective_end > effective_start + interval '12 hours' then
    raise exception 'End time must be after start time and within 12 hours.';
  end if;

  select * into active_session
  from public.service_qr_sessions
  where devotee_id = auth.uid() and status = 'active'
  for update;
  if active_session.id is not null then
    raise exception 'Finish or cancel your current seva timer first.';
  end if;

  insert into public.service_qr_sessions (
    devotee_id, service_type_id, custom_name, started_at, planned_end_at,
    started_via, location_text
  )
  values (
    auth.uid(), p_service_type_id, nullif(trim(p_custom_name), ''),
    effective_start, effective_end, p_started_via,
    coalesce(nullif(trim(p_location_text), ''), 'ISKCON Chicago Temple')
  )
  returning * into created_session;

  select name into devotee_name from public.users where id = auth.uid();
  seva_name := public.service_session_name(created_session);
  perform public.notify_service_oversight(
    'service_started', 'A devotee started seva',
    devotee_name || ' started "' || seva_name || '".',
    jsonb_build_object(
      'serviceSessionId', created_session.id,
      'devoteeId', auth.uid(),
      'plannedEndAt', created_session.planned_end_at
    ),
    auth.uid()
  );
  return created_session;
end;
$$;

create or replace function public.start_list_service_session(p_service_type_id uuid)
returns public.service_qr_sessions
language sql
security definer
set search_path = ''
as $$
  select public.start_service_session(
    p_service_type_id, null, 'service_list', now(), now() + interval '1 hour',
    'ISKCON Chicago Temple'
  );
$$;

create or replace function public.start_planned_service_session(
  p_service_type_id uuid,
  p_custom_name text,
  p_start_at timestamptz,
  p_end_at timestamptz,
  p_location_text text
)
returns public.service_qr_sessions
language sql
security definer
set search_path = ''
as $$
  select public.start_service_session(
    p_service_type_id,
    p_custom_name,
    case when p_service_type_id is null then 'custom' else 'service_list' end,
    p_start_at, p_end_at, p_location_text
  );
$$;

create or replace function public.start_planned_qr_service_session(
  p_qr_token text,
  p_start_at timestamptz,
  p_end_at timestamptz,
  p_location_text text
)
returns public.service_qr_sessions
language plpgsql
security definer
set search_path = ''
as $$
declare
  selected_type public.service_types;
  created_session public.service_qr_sessions;
  effective_start timestamptz := coalesce(p_start_at, now());
  effective_end timestamptz := coalesce(p_end_at, coalesce(p_start_at, now()) + interval '1 hour');
  devotee_name text;
begin
  if auth.uid() is null or not public.has_permission('services.track_live') then
    raise exception 'You are not allowed to start a seva timer.';
  end if;
  perform public.complete_due_service_sessions();
  select * into selected_type from public.service_types
  where qr_token = trim(p_qr_token) and is_active;
  if selected_type.id is null then
    raise exception 'This is not an active ISKCON Chicago seva QR code.';
  end if;
  if effective_start < now() - interval '15 minutes'
    or effective_start > now() + interval '15 minutes'
    or effective_end <= effective_start
    or effective_end > effective_start + interval '12 hours'
  then
    raise exception 'Choose a current start time and an end time within 12 hours.';
  end if;
  if exists (
    select 1 from public.service_qr_sessions
    where devotee_id = auth.uid() and status = 'active'
  ) then
    raise exception 'Finish or cancel your current seva timer first.';
  end if;
  insert into public.service_qr_sessions (
    devotee_id, service_type_id, custom_name, started_at, planned_end_at,
    started_via, location_text
  ) values (
    auth.uid(), selected_type.id, null, effective_start, effective_end, 'qr',
    coalesce(nullif(trim(p_location_text), ''), 'ISKCON Chicago Temple')
  ) returning * into created_session;
  select name into devotee_name from public.users where id = auth.uid();
  perform public.notify_service_oversight(
    'service_started', 'QR-verified seva started',
    devotee_name || ' scanned the QR for "' || selected_type.name || '".',
    jsonb_build_object('serviceSessionId', created_session.id, 'devoteeId', auth.uid()),
    auth.uid()
  );
  return created_session;
end;
$$;

create or replace function public.start_qr_service_session(p_qr_token text)
returns public.service_qr_sessions
language sql
security definer
set search_path = ''
as $$
  select public.start_planned_qr_service_session(
    p_qr_token, now(), now() + interval '1 hour', 'ISKCON Chicago Temple'
  );
$$;

create or replace function public.complete_service_session(p_session_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  owner_id uuid;
begin
  select devotee_id into owner_id from public.service_qr_sessions where id = p_session_id;
  if owner_id is null or owner_id <> auth.uid() then
    raise exception 'Only the devotee doing this seva can finish it.';
  end if;
  return public.finalize_service_session_internal(p_session_id, false);
end;
$$;

create or replace function public.cancel_service_session(p_session_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  session_record public.service_qr_sessions;
  actor_name text;
begin
  select * into session_record from public.service_qr_sessions
  where id = p_session_id for update;
  if session_record.id is null or session_record.status <> 'active' then
    raise exception 'This seva timer is no longer active.';
  end if;
  if session_record.devotee_id <> auth.uid()
    and not public.has_permission('services.delete_any')
  then
    raise exception 'Only this devotee, a Tech member, or the President can cancel it.';
  end if;
  update public.service_qr_sessions
  set status = 'cancelled', cancelled_at = now(), updated_at = now()
  where id = p_session_id;
  select name into actor_name from public.users where id = auth.uid();
  perform public.queue_app_notification(
    session_record.devotee_id, 'service_cancelled', 'Live seva timer cancelled',
    case when session_record.devotee_id = auth.uid()
      then 'Your live seva timer was cancelled.'
      else actor_name || ' cancelled your live seva timer.' end,
    jsonb_build_object('serviceSessionId', p_session_id)
  );
end;
$$;

create or replace function public.delete_service_activity(p_session_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  session_record public.service_qr_sessions;
  actor_name text;
begin
  select * into session_record from public.service_qr_sessions
  where id = p_session_id for update;
  if session_record.id is null then raise exception 'This seva activity was not found.'; end if;
  if session_record.devotee_id <> auth.uid()
    and not public.has_permission('services.delete_any')
  then
    raise exception 'Only this devotee, a Tech member, or the President can remove it.';
  end if;
  if session_record.status = 'active'
    and not public.has_permission('services.delete_any')
  then
    raise exception 'Cancel this live seva before removing it.';
  end if;
  delete from public.service_qr_sessions where id = p_session_id;
  if session_record.service_instance_id is not null then
    delete from public.service_instances where id = session_record.service_instance_id;
  end if;
  if session_record.devotee_id <> auth.uid() then
    select name into actor_name from public.users where id = auth.uid();
    perform public.queue_app_notification(
      session_record.devotee_id, 'service_deleted', 'Seva activity removed',
      actor_name || ' removed a seva activity record from your history.',
      jsonb_build_object('serviceSessionId', p_session_id)
    );
  end if;
end;
$$;

create or replace function public.delete_service_requirement(p_instance_id uuid)
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
  select * into instance_record from public.service_instances
  where id = p_instance_id for update;
  if instance_record.id is null then raise exception 'This service was not found.'; end if;
  if not public.has_permission('services.delete_any')
    and (instance_record.posted_by is null or instance_record.posted_by <> auth.uid())
  then
    raise exception 'Only the poster, a Tech member, or the President can remove it.';
  end if;
  if instance_record.template_id is not null and not public.has_permission('services.delete_any') then
    raise exception 'Recurring occurrences are managed from the recurring service.';
  end if;
  select name into actor_name from public.users where id = auth.uid();
  for participant in
    select distinct devotee_id from public.service_assignments
    where service_instance_id = p_instance_id and devotee_id <> auth.uid()
  loop
    perform public.queue_app_notification(
      participant.devotee_id, 'service_deleted', 'A seva requirement was removed',
      actor_name || ' removed a service requirement and its assignment.',
      jsonb_build_object('serviceInstanceId', p_instance_id)
    );
  end loop;
  delete from public.service_qr_sessions where service_instance_id = p_instance_id;
  delete from public.service_instances where id = p_instance_id;
end;
$$;

create or replace function public.delete_service_assignment_activity(p_assignment_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  assignment_record public.service_assignments;
begin
  select * into assignment_record
  from public.service_assignments
  where id = p_assignment_id
  for update;
  if assignment_record.id is null then
    raise exception 'This completed seva activity was not found.';
  end if;
  if assignment_record.status <> 'completed' then
    raise exception 'Only completed seva activity can be removed here.';
  end if;
  if assignment_record.devotee_id <> auth.uid()
    and not public.has_permission('services.delete_any')
  then
    raise exception 'Only this devotee, a Tech member, or the President can remove it.';
  end if;
  if exists (
    select 1 from public.service_qr_sessions
    where service_instance_id = assignment_record.service_instance_id
  ) then
    raise exception 'Remove this live seva from its activity record.';
  end if;
  delete from public.service_assignments where id = assignment_record.id;
  perform public.refresh_service_instance_capacity(assignment_record.service_instance_id);
end;
$$;

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
  if not public.has_permission('services.complete_requirement') then
    raise exception 'You are not allowed to complete an entire service requirement.';
  end if;
  update public.service_instances set status = 'completed'
  where id = p_instance_id and status not in ('completed', 'cancelled');
  if not found then raise exception 'This service can no longer be completed.'; end if;
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
    'service_completed', 'A service requirement was completed',
    actor_name || ' completed "' || public.service_instance_name(instance_record) || '".',
    jsonb_build_object('serviceInstanceId', p_instance_id), auth.uid()
  );
end;
$$;

create or replace function public.generate_service_instances(p_days_ahead integer default 28)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  chicago_today date := (now() at time zone 'America/Chicago')::date;
  template_record public.service_templates;
  scheduled_date date;
  instance_id uuid;
  generated_count integer := 0;
begin
  if p_days_ahead < 1 or p_days_ahead > 180 then
    raise exception 'Generation window must be between 1 and 180 days.';
  end if;
  for template_record in
    select * from public.service_templates
    where active and start_date <= chicago_today + p_days_ahead
      and (end_date is null or end_date >= chicago_today)
  loop
    for scheduled_date in
      select generated_day::date
      from generate_series(
        greatest(template_record.start_date, chicago_today)::timestamp,
        least(coalesce(template_record.end_date, chicago_today + p_days_ahead),
              chicago_today + p_days_ahead)::timestamp,
        interval '1 day'
      ) as generated_day
      where extract(dow from generated_day)::integer = any(template_record.days_of_week)
    loop
      instance_id := null;
      insert into public.service_instances (
        template_id, service_type_id, custom_name, date, start_time,
        duration_minutes, slots_needed, participation_mode, posted_by, status
      ) values (
        template_record.id, template_record.service_type_id, template_record.custom_name,
        scheduled_date, template_record.start_time, template_record.duration_minutes,
        template_record.slots_needed, template_record.participation_mode, null, 'open'
      ) on conflict (template_id, date) where template_id is not null do update set
        service_type_id = excluded.service_type_id,
        custom_name = excluded.custom_name,
        start_time = excluded.start_time,
        duration_minutes = excluded.duration_minutes,
        slots_needed = excluded.slots_needed,
        participation_mode = excluded.participation_mode
      returning id into instance_id;

      insert into public.service_assignments (
        service_instance_id, devotee_id, assignment_method, assigned_by, status, verification
      )
      select instance_id, assignees.devotee_id, 'recurring_assignment',
        assignees.assigned_by, 'confirmed', 'self_report'
      from public.service_template_assignees as assignees
      where assignees.service_template_id = template_record.id
        and assignees.status = 'active'
      on conflict (service_instance_id, devotee_id) do nothing;
      perform public.refresh_service_instance_capacity(instance_id);
      generated_count := generated_count + 1;
    end loop;
  end loop;
  return generated_count;
end;
$$;

-- The earlier offer responder assumed every recurring template had a catalog
-- service type. Recurring custom seva needs the same atomic accept/decline path.
create or replace function public.respond_to_service_offer(
  p_offer_id uuid,
  p_accept boolean
)
returns public.service_offers
language plpgsql
security definer
set search_path = ''
as $$
declare
  offer_record public.service_offers;
  instance_record public.service_instances;
  template_record public.service_templates;
  exception_record public.service_exceptions;
  updated_offer public.service_offers;
  filled_slots integer;
  devotee_name text;
  service_name text;
  future_instance record;
  active_recurring_assignees integer;
begin
  select * into offer_record from public.service_offers
  where id = p_offer_id for update;
  if offer_record.id is null or offer_record.offered_to <> auth.uid() then
    raise exception 'This service offer is not available to you.';
  end if;
  if offer_record.status <> 'pending' then
    raise exception 'This service offer has already been answered.';
  end if;
  if offer_record.offer_kind = 'coverage_range' then
    raise exception 'Use the recurring coverage response for this offer.';
  end if;

  if offer_record.offer_kind = 'recurring' then
    select * into template_record from public.service_templates
    where id = offer_record.service_template_id for update;
    if p_accept and (template_record.id is null or not template_record.active) then
      raise exception 'This recurring service is no longer active.';
    end if;
    service_name := coalesce(
      (select name from public.service_types where id = template_record.service_type_id),
      template_record.custom_name,
      'Temple seva'
    );

    if p_accept then
      select count(*) into active_recurring_assignees
      from public.service_template_assignees
      where service_template_id = template_record.id and status = 'active';
      if active_recurring_assignees >= template_record.slots_needed and not exists (
        select 1 from public.service_template_assignees
        where service_template_id = template_record.id
          and devotee_id = auth.uid() and status = 'active'
      ) then
        update public.service_offers set status = 'expired', responded_at = now()
        where id = p_offer_id returning * into updated_offer;
        return updated_offer;
      end if;
      insert into public.service_template_assignees (
        service_template_id, devotee_id, assigned_by, status
      ) values (
        template_record.id, auth.uid(), offer_record.offered_by, 'active'
      ) on conflict (service_template_id, devotee_id) do update set
        assigned_by = excluded.assigned_by, status = 'active', updated_at = now();
      perform public.generate_service_instances(56);
      insert into public.service_assignments (
        service_instance_id, devotee_id, assignment_method, assigned_by,
        status, verification
      )
      select instances.id, auth.uid(), 'recurring_assignment',
        offer_record.offered_by, 'confirmed', 'self_report'
      from public.service_instances instances
      where instances.template_id = template_record.id
        and instances.date >= (now() at time zone 'America/Chicago')::date
        and instances.status not in ('cancelled', 'completed')
      on conflict (service_instance_id, devotee_id) do nothing;
      for future_instance in
        select id from public.service_instances
        where template_id = template_record.id
          and date >= (now() at time zone 'America/Chicago')::date
      loop
        perform public.refresh_service_instance_capacity(future_instance.id);
      end loop;
      update public.service_offers set status = 'expired', responded_at = now()
      where service_template_id = template_record.id
        and id <> offer_record.id and status = 'pending'
        and (
          select count(*) from public.service_template_assignees
          where service_template_id = template_record.id and status = 'active'
        ) >= template_record.slots_needed;
    end if;
  else
    select * into instance_record from public.service_instances
    where id = offer_record.service_instance_id for update;
    service_name := public.service_instance_name(instance_record);
    if offer_record.offer_kind = 'coverage' then
      select * into exception_record from public.service_exceptions
      where id = offer_record.service_exception_id for update;
      if p_accept and (exception_record.id is null or exception_record.status <> 'pending') then
        raise exception 'This service coverage has already been resolved.';
      end if;
    end if;
    if p_accept then
      if instance_record.status not in ('open', 'full') then
        raise exception 'This service is no longer available.';
      end if;
      select count(*) into filled_slots from public.service_assignments
      where service_instance_id = instance_record.id
        and status in ('assigned', 'confirmed', 'completed');
      if filled_slots >= instance_record.slots_needed and not exists (
        select 1 from public.service_assignments
        where service_instance_id = instance_record.id and devotee_id = auth.uid()
          and status in ('assigned', 'confirmed', 'completed')
      ) then
        update public.service_offers set status = 'expired', responded_at = now()
        where id = p_offer_id returning * into updated_offer;
        return updated_offer;
      end if;
      insert into public.service_assignments (
        service_instance_id, devotee_id, assignment_method, assigned_by,
        status, verification
      ) values (
        instance_record.id, auth.uid(),
        case when offer_record.offer_kind = 'coverage'
          then 'accepted_coverage_offer' else 'accepted_offer' end,
        offer_record.offered_by, 'confirmed', 'self_report'
      ) on conflict (service_instance_id, devotee_id) do update set
        assignment_method = excluded.assignment_method,
        assigned_by = excluded.assigned_by, status = 'confirmed',
        verification = 'self_report', completed_at = null;
      if offer_record.offer_kind = 'coverage' then
        update public.service_exceptions set
          status = 'resolved', resolution_kind = 'substitute',
          substitute_devotee_id = auth.uid(), resolved_at = now(),
          resolved_by = offer_record.offered_by
        where id = offer_record.service_exception_id;
        update public.service_offers set status = 'expired', responded_at = now()
        where service_exception_id = offer_record.service_exception_id
          and id <> offer_record.id and status = 'pending';
      end if;
      perform public.refresh_service_instance_capacity(instance_record.id);
    end if;
  end if;

  update public.service_offers
  set status = case when p_accept then 'accepted' else 'declined' end,
      responded_at = now()
  where id = p_offer_id returning * into updated_offer;
  select name into devotee_name from public.users where id = auth.uid();
  perform public.queue_app_notification(
    offer_record.offered_by, 'service_offer_response',
    case when p_accept then 'Service offer accepted' else 'Service offer declined' end,
    devotee_name || case when p_accept then ' accepted "'
      else ' is not available for "' end || service_name || '".',
    jsonb_strip_nulls(jsonb_build_object(
      'serviceInstanceId', offer_record.service_instance_id,
      'serviceTemplateId', offer_record.service_template_id,
      'serviceExceptionId', offer_record.service_exception_id,
      'serviceOfferId', offer_record.id
    ))
  );
  return updated_offer;
end;
$$;

create or replace function public.create_service_template_v2(
  p_service_type_id uuid,
  p_custom_name text,
  p_days_of_week integer[],
  p_start_time time,
  p_duration_minutes integer,
  p_slots_needed integer,
  p_participation_mode text,
  p_start_date date,
  p_end_date date,
  p_invitee_ids uuid[]
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  created_id uuid;
begin
  if not public.has_permission('services.manage_recurring') then
    raise exception 'Only Core, Tech, or President can create recurring seva.';
  end if;
  if cardinality(p_days_of_week) < 1 or not p_days_of_week <@ array[0,1,2,3,4,5,6] then
    raise exception 'Choose at least one valid weekday.';
  end if;
  if (p_service_type_id is null) = (length(trim(coalesce(p_custom_name, ''))) < 2) then
    raise exception 'Choose one seva or type a meaningful seva name.';
  end if;
  insert into public.service_templates (
    service_type_id, custom_name, day_of_week, days_of_week, start_time,
    duration_minutes, slots_needed, participation_mode, start_date, end_date,
    created_by
  ) values (
    p_service_type_id, nullif(trim(p_custom_name), ''), p_days_of_week[1],
    (select array_agg(distinct day order by day) from unnest(p_days_of_week) day),
    p_start_time, p_duration_minutes, p_slots_needed, p_participation_mode,
    p_start_date, p_end_date, auth.uid()
  ) returning id into created_id;
  perform public.update_service_template_v2(
    created_id, p_service_type_id, p_custom_name, p_days_of_week, p_start_time,
    p_duration_minutes, p_slots_needed, p_participation_mode, p_start_date,
    p_end_date, p_invitee_ids
  );
  return created_id;
end;
$$;

create or replace function public.update_service_template_v2(
  p_template_id uuid,
  p_service_type_id uuid,
  p_custom_name text,
  p_days_of_week integer[],
  p_start_time time,
  p_duration_minutes integer,
  p_slots_needed integer,
  p_participation_mode text,
  p_start_date date,
  p_end_date date,
  p_invitee_ids uuid[]
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  invitee_id uuid;
  coordinator_name text;
  seva_name text;
  offer_id uuid;
begin
  if not public.has_permission('services.manage_recurring') then
    raise exception 'Only Core, Tech, or President can update recurring seva.';
  end if;
  if cardinality(p_days_of_week) < 1 or not p_days_of_week <@ array[0,1,2,3,4,5,6] then
    raise exception 'Choose at least one valid weekday.';
  end if;
  if (p_service_type_id is null) = (length(trim(coalesce(p_custom_name, ''))) < 2) then
    raise exception 'Choose one seva or type a meaningful seva name.';
  end if;
  update public.service_templates set
    service_type_id = p_service_type_id,
    custom_name = nullif(trim(p_custom_name), ''),
    day_of_week = p_days_of_week[1],
    days_of_week = (select array_agg(distinct day order by day) from unnest(p_days_of_week) day),
    start_time = p_start_time,
    duration_minutes = p_duration_minutes,
    slots_needed = p_slots_needed,
    participation_mode = p_participation_mode,
    start_date = p_start_date,
    end_date = p_end_date,
    updated_at = now()
  where id = p_template_id;
  if not found then raise exception 'This recurring seva was not found.'; end if;

  -- Regenerate future occurrences so time/day/capacity edits are immediately visible.
  delete from public.service_instances
  where template_id = p_template_id
    and date >= (now() at time zone 'America/Chicago')::date
    and status <> 'completed';

  select name into coordinator_name from public.users where id = auth.uid();
  select coalesce(service_types.name, templates.custom_name) into seva_name
  from public.service_templates templates
  left join public.service_types on service_types.id = templates.service_type_id
  where templates.id = p_template_id;

  for invitee_id in select distinct unnest(coalesce(p_invitee_ids, '{}'::uuid[]))
  loop
    if not exists (select 1 from public.users where id = invitee_id) then
      raise exception 'An invited devotee could not be found.';
    end if;
    if not exists (
      select 1 from public.service_template_assignees
      where service_template_id = p_template_id and devotee_id = invitee_id and status = 'active'
    ) then
      insert into public.service_offers (
        service_instance_id, service_template_id, service_exception_id,
        service_coverage_plan_id, offered_to, offered_by, offer_kind, status
      ) values (
        null, p_template_id, null, null, invitee_id, auth.uid(), 'recurring', 'pending'
      ) on conflict (service_template_id, offered_to) where offer_kind = 'recurring'
      do update set offered_by = excluded.offered_by, status = 'pending',
        created_at = now(), responded_at = null
      returning id into offer_id;
      perform public.queue_app_notification(
        invitee_id, 'service_recurring_offer', 'A recurring seva invitation',
        coordinator_name || ' is asking if you can help with "' || seva_name || '".',
        jsonb_build_object('serviceTemplateId', p_template_id, 'serviceOfferId', offer_id)
      );
    end if;
  end loop;
  perform public.generate_service_instances(56);
end;
$$;

create or replace function public.delete_service_template(p_template_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  assignee record;
  actor_name text;
begin
  if not public.has_permission('services.manage_recurring') then
    raise exception 'Only Core, Tech, or President can delete recurring seva.';
  end if;
  select name into actor_name from public.users where id = auth.uid();
  for assignee in
    select devotee_id from public.service_template_assignees
    where service_template_id = p_template_id and status = 'active'
      and devotee_id <> auth.uid()
  loop
    perform public.queue_app_notification(
      assignee.devotee_id, 'service_deleted', 'Recurring seva ended',
      actor_name || ' removed a recurring seva from the schedule.',
      jsonb_build_object('serviceTemplateId', p_template_id)
    );
  end loop;
  delete from public.service_instances
  where template_id = p_template_id and status <> 'completed';
  delete from public.service_templates where id = p_template_id;
  if not found then raise exception 'This recurring seva was not found.'; end if;
end;
$$;

create or replace function public.offer_service_coverage_range(
  p_exception_id uuid,
  p_devotee_id uuid,
  p_scope text,
  p_date_from date,
  p_date_to date
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  exception_record public.service_exceptions;
  instance_record public.service_instances;
  plan_id uuid;
  offer_id uuid;
  coordinator_name text;
begin
  if not public.has_permission('services.resolve_coverage') then
    raise exception 'Only Core, Tech, or President can arrange recurring coverage.';
  end if;
  select * into exception_record from public.service_exceptions
  where id = p_exception_id and status = 'pending' for update;
  if exception_record.id is null then raise exception 'This coverage request is no longer pending.'; end if;
  select * into instance_record from public.service_instances
  where id = exception_record.service_instance_id;
  if instance_record.template_id is null then
    raise exception 'Date-range coverage is only available for recurring seva.';
  end if;
  if p_devotee_id = exception_record.devotee_id
    or not exists (select 1 from public.users where id = p_devotee_id)
  then
    raise exception 'Choose another active devotee for coverage.';
  end if;
  if p_scope not in ('occurrence', 'date_range', 'forever') then
    raise exception 'Choose a valid coverage period.';
  end if;
  if p_scope = 'occurrence' then
    p_date_from := instance_record.date;
    p_date_to := instance_record.date;
  end if;
  if p_scope = 'forever' then p_date_to := null; end if;
  if p_date_from < instance_record.date then
    raise exception 'Coverage cannot begin before the unavailable occurrence.';
  end if;
  if exists (
    select 1 from public.service_coverage_plans
    where service_exception_id = exception_record.id
      and substitute_devotee_id = p_devotee_id and status = 'pending'
  ) then
    raise exception 'This devotee already has a pending coverage request.';
  end if;
  insert into public.service_coverage_plans (
    service_exception_id, service_template_id, original_devotee_id,
    substitute_devotee_id, scope, date_from, date_to, created_by
  ) values (
    exception_record.id, instance_record.template_id, exception_record.devotee_id,
    p_devotee_id, p_scope, p_date_from, p_date_to, auth.uid()
  ) returning id into plan_id;
  insert into public.service_offers (
    service_instance_id, service_template_id, service_exception_id,
    service_coverage_plan_id, offered_to, offered_by, offer_kind, status
  ) values (
    null, instance_record.template_id, null, plan_id, p_devotee_id,
    auth.uid(), 'coverage_range', 'pending'
  ) returning id into offer_id;
  select name into coordinator_name from public.users where id = auth.uid();
  perform public.queue_app_notification(
    p_devotee_id, 'service_offer', 'Can you cover this recurring seva?',
    coordinator_name || ' is asking for your help with "' ||
      public.service_instance_name(instance_record) || '" from ' ||
      to_char(p_date_from, 'FMMon FMDD, YYYY') ||
      case when p_scope = 'forever' then ' onward.'
           when p_date_to = p_date_from then '.'
           else ' through ' || to_char(p_date_to, 'FMMon FMDD, YYYY') || '.' end,
    jsonb_build_object(
      'serviceTemplateId', instance_record.template_id,
      'serviceCoveragePlanId', plan_id,
      'serviceOfferId', offer_id
    )
  );
  return offer_id;
end;
$$;

create or replace function public.respond_to_coverage_range_offer(
  p_offer_id uuid,
  p_accept boolean
)
returns public.service_offers
language plpgsql
security definer
set search_path = ''
as $$
declare
  offer_record public.service_offers;
  plan_record public.service_coverage_plans;
  updated_offer public.service_offers;
  devotee_name text;
begin
  select * into offer_record from public.service_offers
  where id = p_offer_id and offer_kind = 'coverage_range' for update;
  if offer_record.id is null or offer_record.offered_to <> auth.uid()
    or offer_record.status <> 'pending'
  then raise exception 'This coverage offer is no longer available.'; end if;
  select * into plan_record from public.service_coverage_plans
  where id = offer_record.service_coverage_plan_id for update;

  if p_accept and not exists (
    select 1 from public.service_exceptions
    where id = plan_record.service_exception_id and status = 'pending'
    for update
  ) then
    raise exception 'This recurring seva has already been covered.';
  end if;

  update public.service_offers
  set status = case when p_accept then 'accepted' else 'declined' end,
      responded_at = now()
  where id = p_offer_id returning * into updated_offer;
  update public.service_coverage_plans
  set status = case when p_accept then 'accepted' else 'declined' end,
      responded_at = now()
  where id = plan_record.id;

  if p_accept then
    if plan_record.scope = 'forever' then
      update public.service_template_assignees set status = 'withdrawn', updated_at = now()
      where service_template_id = plan_record.service_template_id
        and devotee_id = plan_record.original_devotee_id;
      insert into public.service_template_assignees (
        service_template_id, devotee_id, assigned_by, status
      ) values (
        plan_record.service_template_id, auth.uid(), plan_record.created_by, 'active'
      ) on conflict (service_template_id, devotee_id) do update set
        status = 'active', assigned_by = excluded.assigned_by, updated_at = now();
    end if;

    update public.service_assignments assignments
    set status = 'withdrawn', completed_at = null
    from public.service_instances instances
    where assignments.service_instance_id = instances.id
      and instances.template_id = plan_record.service_template_id
      and assignments.devotee_id = plan_record.original_devotee_id
      and assignments.status in ('assigned', 'confirmed')
      and instances.date >= plan_record.date_from
      and (plan_record.date_to is null or instances.date <= plan_record.date_to);

    insert into public.service_assignments (
      service_instance_id, devotee_id, assignment_method, assigned_by,
      status, verification
    )
    select instances.id, auth.uid(), 'accepted_coverage_offer',
      plan_record.created_by, 'confirmed', 'self_report'
    from public.service_instances instances
    where instances.template_id = plan_record.service_template_id
      and instances.status not in ('cancelled', 'completed')
      and instances.date >= plan_record.date_from
      and (plan_record.date_to is null or instances.date <= plan_record.date_to)
    on conflict (service_instance_id, devotee_id) do update set
      status = 'confirmed', assigned_by = excluded.assigned_by,
      assignment_method = 'accepted_coverage_offer', completed_at = null;

    update public.service_exceptions set
      status = 'resolved', resolution_kind = 'substitute',
      substitute_devotee_id = auth.uid(), resolved_at = now(),
      resolved_by = plan_record.created_by
    where id = plan_record.service_exception_id;

    update public.service_coverage_plans
    set status = 'cancelled'
    where service_exception_id = plan_record.service_exception_id
      and id <> plan_record.id and status = 'pending';
    update public.service_offers offers
    set status = 'expired', responded_at = now()
    from public.service_coverage_plans plans
    where offers.service_coverage_plan_id = plans.id
      and plans.service_exception_id = plan_record.service_exception_id
      and plans.id <> plan_record.id and offers.status = 'pending';
  end if;

  select name into devotee_name from public.users where id = auth.uid();
  perform public.notify_service_oversight(
    'service_offer_response',
    case when p_accept then 'Coverage accepted' else 'Coverage declined' end,
    devotee_name || case when p_accept then ' accepted the recurring coverage request.'
      else ' is not available for the recurring coverage request.' end,
    jsonb_build_object(
      'serviceTemplateId', plan_record.service_template_id,
      'serviceCoveragePlanId', plan_record.id
    ),
    auth.uid()
  );
  return updated_offer;
end;
$$;

alter table public.service_coverage_plans enable row level security;
alter table public.device_push_tokens enable row level security;

drop policy if exists "Users can read visible live service sessions"
  on public.service_qr_sessions;
drop policy if exists "Users and recurring coordinators can read live seva sessions"
  on public.service_qr_sessions;
create policy "Users can read visible live service sessions"
  on public.service_qr_sessions for select to authenticated
  using (
    devotee_id = auth.uid()
    or public.has_permission('services.oversee_activity')
  );

drop policy if exists "Users can read permitted service participation"
  on public.service_assignments;
create policy "Users can read permitted service participation"
  on public.service_assignments for select to authenticated
  using (
    assignment_method <> 'recurring_assignment'
    or devotee_id = auth.uid()
    or public.has_permission('services.oversee_activity')
  );

create policy "Coordinators can read coverage plans"
  on public.service_coverage_plans for select to authenticated
  using (
    original_devotee_id = auth.uid()
    or substitute_devotee_id = auth.uid()
    or public.has_permission('services.resolve_coverage')
  );

create policy "Users manage their own push devices"
  on public.device_push_tokens for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

revoke all on public.service_coverage_plans from anon, authenticated;
grant select on public.service_coverage_plans to authenticated;
revoke all on public.device_push_tokens from anon, authenticated;
grant select, delete on public.device_push_tokens to authenticated;

revoke all on function public.finalize_service_session_internal(uuid, boolean) from public;
revoke all on function public.complete_due_service_sessions() from public;
revoke all on function public.generate_service_instances(integer) from public;
revoke execute on function public.generate_service_instances(integer) from authenticated;
revoke all on function public.start_service_session(uuid, text, text, timestamptz, timestamptz, text) from public;
revoke all on function public.start_planned_service_session(uuid, text, timestamptz, timestamptz, text) from public;
revoke all on function public.start_planned_qr_service_session(text, timestamptz, timestamptz, text) from public;
revoke all on function public.delete_service_activity(uuid) from public;
revoke all on function public.delete_service_requirement(uuid) from public;
revoke all on function public.delete_service_assignment_activity(uuid) from public;
revoke all on function public.create_service_template_v2(uuid, text, integer[], time, integer, integer, text, date, date, uuid[]) from public;
revoke all on function public.update_service_template_v2(uuid, uuid, text, integer[], time, integer, integer, text, date, date, uuid[]) from public;
revoke all on function public.delete_service_template(uuid) from public;
revoke all on function public.offer_service_coverage_range(uuid, uuid, text, date, date) from public;
revoke all on function public.respond_to_coverage_range_offer(uuid, boolean) from public;
revoke all on function public.register_device_push_token(text, text, text) from public;

grant execute on function public.complete_due_service_sessions() to authenticated;
grant execute on function public.start_planned_service_session(uuid, text, timestamptz, timestamptz, text) to authenticated;
grant execute on function public.start_planned_qr_service_session(text, timestamptz, timestamptz, text) to authenticated;
grant execute on function public.delete_service_activity(uuid) to authenticated;
grant execute on function public.delete_service_requirement(uuid) to authenticated;
grant execute on function public.delete_service_assignment_activity(uuid) to authenticated;
grant execute on function public.create_service_template_v2(uuid, text, integer[], time, integer, integer, text, date, date, uuid[]) to authenticated;
grant execute on function public.update_service_template_v2(uuid, uuid, text, integer[], time, integer, integer, text, date, date, uuid[]) to authenticated;
grant execute on function public.delete_service_template(uuid) to authenticated;
grant execute on function public.offer_service_coverage_range(uuid, uuid, text, date, date) to authenticated;
grant execute on function public.respond_to_coverage_range_offer(uuid, boolean) to authenticated;
grant execute on function public.register_device_push_token(text, text, text) to authenticated;

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    execute 'create extension if not exists pg_cron with schema extensions';
    if exists (select 1 from pg_extension where extname = 'pg_cron') then
      execute $cron$
        select cron.schedule(
          'complete-due-seva-sessions',
          '* * * * *',
          'select public.complete_due_service_sessions();'
        )
        where not exists (
          select 1 from cron.job where jobname = 'complete-due-seva-sessions'
        )
      $cron$;
    end if;
  end if;
exception when others then
  raise notice 'Enable Supabase Cron for minute-accurate background completion; app refresh remains a fallback.';
end;
$$;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public'
      and tablename = 'service_coverage_plans'
  ) then
    alter publication supabase_realtime add table public.service_coverage_plans;
  end if;
end;
$$;
