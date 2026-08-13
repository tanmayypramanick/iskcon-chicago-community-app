-- Core Services milestone: catalog, open/targeted requirements, participation,
-- one-time offers, self-logged seva, and durable in-app notifications.
-- Requires 202608020001_access_levels.sql.

insert into public.role_permissions (role_id, permission_key)
select roles.id, 'services.manage_catalog'
from public.roles
where roles.name in ('president', 'tech', 'core')
on conflict (role_id, permission_key) do nothing;

create table if not exists public.service_types (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  category text not null check (
    category in ('kitchen', 'cleaning', 'deity-worship', 'event', 'other')
  ),
  qr_token text unique,
  is_active boolean not null default true,
  created_by uuid references public.users(id),
  created_at timestamptz not null default now(),
  constraint service_type_name_not_blank check (length(trim(name)) between 2 and 80)
);

create table if not exists public.service_instances (
  id uuid primary key default gen_random_uuid(),
  template_id uuid,
  service_type_id uuid references public.service_types(id),
  custom_name text,
  date date not null,
  start_time time not null,
  duration_minutes integer not null check (
    duration_minutes between 30 and 720 and duration_minutes % 30 = 0
  ),
  slots_needed integer not null check (slots_needed between 1 and 100),
  participation_mode text not null default 'open' check (
    participation_mode in ('open', 'invite_only')
  ),
  posted_by uuid references public.users(id),
  status text not null default 'open' check (
    status in ('open', 'full', 'closed', 'cancelled', 'completed')
  ),
  created_at timestamptz not null default now(),
  constraint service_instance_has_one_name check (
    (service_type_id is not null and custom_name is null)
    or
    (service_type_id is null and length(trim(custom_name)) between 2 and 100)
  )
);

create index if not exists service_instances_schedule_idx
  on public.service_instances(date, start_time, status);
create index if not exists service_instances_posted_by_idx
  on public.service_instances(posted_by, date desc);

create table if not exists public.service_assignments (
  id uuid primary key default gen_random_uuid(),
  service_instance_id uuid not null references public.service_instances(id) on delete cascade,
  devotee_id uuid not null references public.users(id) on delete cascade,
  assignment_method text not null check (
    assignment_method in (
      'self_joined',
      'accepted_offer',
      'recurring_assignment',
      'accepted_coverage_offer',
      'self_logged',
      'qr_scan'
    )
  ),
  assigned_by uuid references public.users(id),
  status text not null check (
    status in ('assigned', 'confirmed', 'completed', 'no_show', 'withdrawn')
  ),
  verification text not null default 'self_report' check (
    verification in ('self_report', 'qr_scan')
  ),
  qr_scanned_at timestamptz,
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  unique (service_instance_id, devotee_id)
);

create index if not exists service_assignments_devotee_schedule_idx
  on public.service_assignments(devotee_id, status, service_instance_id);

create table if not exists public.service_offers (
  id uuid primary key default gen_random_uuid(),
  service_instance_id uuid not null references public.service_instances(id) on delete cascade,
  offered_to uuid not null references public.users(id) on delete cascade,
  offered_by uuid not null references public.users(id),
  offer_kind text not null default 'one_time' check (
    offer_kind in ('one_time', 'coverage')
  ),
  status text not null default 'pending' check (
    status in ('pending', 'accepted', 'declined', 'expired')
  ),
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  unique (service_instance_id, offered_to)
);

create index if not exists service_offers_recipient_status_idx
  on public.service_offers(offered_to, status, created_at desc);

create table if not exists public.app_notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  kind text not null check (
    kind in (
      'service_open',
      'service_offer',
      'service_offer_response',
      'service_joined',
      'service_left',
      'service_completed',
      'service_coverage_needed',
      'remote'
    )
  ),
  title text not null,
  body text not null,
  data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  read_at timestamptz
);

create index if not exists app_notifications_user_created_idx
  on public.app_notifications(user_id, created_at desc);

insert into public.service_types (name, category)
values
  ('Pot Washing', 'kitchen'),
  ('Vegetable Cutting', 'kitchen'),
  ('Kitchen Preparation', 'kitchen'),
  ('Prasadam Serving', 'kitchen'),
  ('Sunday Feast Cleanup', 'cleaning'),
  ('Temple Room Cleaning', 'cleaning'),
  ('Flower Garlands', 'deity-worship'),
  ('Mangal Arati Setup', 'deity-worship'),
  ('Festival Decoration', 'event'),
  ('Guest Welcome', 'event'),
  ('Book Table', 'event'),
  ('Shoe Room', 'event'),
  ('Kirtana Support', 'event'),
  ('General Temple Service', 'other')
on conflict (name) do update
set category = excluded.category, is_active = true;

create or replace function public.queue_app_notification(
  p_user_id uuid,
  p_kind text,
  p_title text,
  p_body text,
  p_data jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  notification_id uuid;
begin
  insert into public.app_notifications (user_id, kind, title, body, data)
  values (p_user_id, p_kind, p_title, p_body, coalesce(p_data, '{}'::jsonb))
  returning id into notification_id;

  return notification_id;
end;
$$;

create or replace function public.service_instance_name(p_instance public.service_instances)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(service_types.name, p_instance.custom_name)
  from (select 1) as singleton
  left join public.service_types on service_types.id = p_instance.service_type_id;
$$;

create or replace function public.refresh_service_instance_capacity(p_instance_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  instance_record public.service_instances;
  filled_slots integer;
begin
  select * into instance_record
  from public.service_instances
  where id = p_instance_id
  for update;

  if instance_record.id is null then
    return;
  end if;

  select count(*) into filled_slots
  from public.service_assignments
  where service_instance_id = p_instance_id
    and status in ('assigned', 'confirmed', 'completed');

  if instance_record.status in ('open', 'full') then
    update public.service_instances
    set status = case
      when filled_slots >= instance_record.slots_needed then 'full'
      else 'open'
    end
    where id = p_instance_id;
  end if;

  if filled_slots >= instance_record.slots_needed then
    update public.service_offers
    set status = 'expired', responded_at = now()
    where service_instance_id = p_instance_id
      and status = 'pending';
  end if;
end;
$$;

create or replace function public.list_service_devotees()
returns table (
  id uuid,
  name text,
  photo_url text,
  role_name text
)
language sql
stable
security definer
set search_path = ''
as $$
  select users.id, users.name, users.photo_url, roles.name
  from public.users
  join public.roles on roles.id = users.role_id
  where auth.uid() is not null
  order by users.name;
$$;

create or replace function public.add_service_type(
  p_name text,
  p_category text
)
returns public.service_types
language plpgsql
security definer
set search_path = ''
as $$
declare
  created_type public.service_types;
begin
  if not public.has_permission('services.manage_catalog') then
    raise exception 'You are not allowed to manage the service catalog.';
  end if;

  if p_category not in ('kitchen', 'cleaning', 'deity-worship', 'event', 'other') then
    raise exception 'Choose a valid service category.';
  end if;

  insert into public.service_types (name, category, created_by)
  values (trim(p_name), p_category, auth.uid())
  on conflict (name) do update
  set category = excluded.category, is_active = true
  returning * into created_type;

  return created_type;
end;
$$;

create or replace function public.create_service_requirement(
  p_service_type_id uuid,
  p_custom_name text,
  p_date date,
  p_start_time time,
  p_duration_minutes integer,
  p_slots_needed integer,
  p_participation_mode text,
  p_invitee_ids uuid[]
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  created_instance public.service_instances;
  invitee_id uuid;
  created_offer_id uuid;
  coordinator_name text;
  display_name text;
begin
  if not public.has_permission('services.post_requirement') then
    raise exception 'You are not allowed to post service requirements.';
  end if;

  if p_date < (now() at time zone 'America/Chicago')::date then
    raise exception 'A service requirement cannot be posted in the past.';
  end if;

  if p_duration_minutes < 30 or p_duration_minutes > 720
    or p_duration_minutes % 30 <> 0
  then
    raise exception 'Duration must use 30-minute increments.';
  end if;

  if p_slots_needed < 1 or p_slots_needed > 100 then
    raise exception 'Slots needed must be between 1 and 100.';
  end if;

  if p_participation_mode not in ('open', 'invite_only') then
    raise exception 'Choose open or invite-only participation.';
  end if;

  if (p_service_type_id is null) = (nullif(trim(p_custom_name), '') is null) then
    raise exception 'Choose a catalog service or enter one custom name.';
  end if;

  if p_service_type_id is not null and not exists (
    select 1 from public.service_types
    where id = p_service_type_id and is_active
  ) then
    raise exception 'The selected service is not available.';
  end if;

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
    p_service_type_id,
    nullif(trim(p_custom_name), ''),
    p_date,
    p_start_time,
    p_duration_minutes,
    p_slots_needed,
    p_participation_mode,
    auth.uid(),
    'open'
  )
  returning * into created_instance;

  select name into coordinator_name
  from public.users
  where id = auth.uid();

  display_name := public.service_instance_name(created_instance);

  if p_participation_mode = 'open' then
    insert into public.app_notifications (user_id, kind, title, body, data)
    select
      users.id,
      'service_open',
      'Seva help requested',
      coordinator_name || ' posted "' || display_name || '" for ' ||
        to_char(created_instance.date, 'FMDay, FMMonth FMDD') || ' at ' ||
        to_char(created_instance.start_time, 'FMHH12:MI AM') || '.',
      jsonb_build_object('serviceInstanceId', created_instance.id)
    from public.users
    where users.id <> auth.uid();
  end if;

  for invitee_id in
    select distinct unnest(coalesce(p_invitee_ids, '{}'::uuid[]))
  loop
    if not exists (select 1 from public.users where id = invitee_id) then
      raise exception 'An invited devotee could not be found.';
    end if;

    insert into public.service_offers (
      service_instance_id,
      offered_to,
      offered_by,
      offer_kind,
      status
    )
    values (
      created_instance.id,
      invitee_id,
      auth.uid(),
      'one_time',
      'pending'
    )
    on conflict (service_instance_id, offered_to) do update
    set
      offered_by = excluded.offered_by,
      offer_kind = excluded.offer_kind,
      status = 'pending',
      created_at = now(),
      responded_at = null
    returning id into created_offer_id;

    perform public.queue_app_notification(
      invitee_id,
      'service_offer',
      'Can you help with this seva?',
      coordinator_name || ' is asking for your help with "' || display_name ||
        '" on ' || to_char(created_instance.date, 'FMDay, FMMonth FMDD') ||
        ' at ' || to_char(created_instance.start_time, 'FMHH12:MI AM') ||
        '. Please let them know if you are available.',
      jsonb_build_object(
        'serviceInstanceId', created_instance.id,
        'serviceOfferId', created_offer_id
      )
    );
  end loop;

  return created_instance.id;
end;
$$;

create or replace function public.join_service_instance(p_instance_id uuid)
returns public.service_assignments
language plpgsql
security definer
set search_path = ''
as $$
declare
  instance_record public.service_instances;
  joined_assignment public.service_assignments;
  filled_slots integer;
  devotee_name text;
begin
  if auth.uid() is null then
    raise exception 'Authentication is required.';
  end if;

  select * into instance_record
  from public.service_instances
  where id = p_instance_id
  for update;

  if instance_record.id is null then
    raise exception 'This service could not be found.';
  end if;

  if instance_record.status <> 'open' or instance_record.participation_mode <> 'open' then
    raise exception 'This service is not open for self-joining.';
  end if;

  select count(*) into filled_slots
  from public.service_assignments
  where service_instance_id = p_instance_id
    and status in ('assigned', 'confirmed', 'completed');

  if filled_slots >= instance_record.slots_needed then
    perform public.refresh_service_instance_capacity(p_instance_id);
    raise exception 'This service is already full.';
  end if;

  insert into public.service_assignments (
    service_instance_id,
    devotee_id,
    assignment_method,
    assigned_by,
    status,
    verification
  )
  values (
    p_instance_id,
    auth.uid(),
    'self_joined',
    null,
    'confirmed',
    'self_report'
  )
  on conflict (service_instance_id, devotee_id) do update
  set
    assignment_method = 'self_joined',
    assigned_by = null,
    status = 'confirmed',
    verification = 'self_report',
    completed_at = null
  returning * into joined_assignment;

  perform public.refresh_service_instance_capacity(p_instance_id);

  if instance_record.posted_by is not null and instance_record.posted_by <> auth.uid() then
    select name into devotee_name from public.users where id = auth.uid();
    perform public.queue_app_notification(
      instance_record.posted_by,
      'service_joined',
      'A devotee joined your service',
      devotee_name || ' joined "' || public.service_instance_name(instance_record) || '".',
      jsonb_build_object('serviceInstanceId', p_instance_id)
    );
  end if;

  return joined_assignment;
end;
$$;

create or replace function public.leave_service_instance(p_instance_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  instance_record public.service_instances;
  devotee_name text;
begin
  select * into instance_record
  from public.service_instances
  where id = p_instance_id
  for update;

  if instance_record.id is null or instance_record.status in ('completed', 'cancelled') then
    raise exception 'This service can no longer be left.';
  end if;

  update public.service_assignments
  set status = 'withdrawn', completed_at = null
  where service_instance_id = p_instance_id
    and devotee_id = auth.uid()
    and status in ('assigned', 'confirmed');

  if not found then
    raise exception 'You are not currently assigned to this service.';
  end if;

  perform public.refresh_service_instance_capacity(p_instance_id);

  if instance_record.posted_by is not null and instance_record.posted_by <> auth.uid() then
    select name into devotee_name from public.users where id = auth.uid();
    perform public.queue_app_notification(
      instance_record.posted_by,
      'service_left',
      'A service place reopened',
      devotee_name || ' left "' || public.service_instance_name(instance_record) || '".',
      jsonb_build_object('serviceInstanceId', p_instance_id)
    );
  end if;
end;
$$;

create or replace function public.log_completed_service(
  p_service_type_id uuid,
  p_custom_name text,
  p_date date,
  p_start_time time,
  p_duration_minutes integer
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  created_instance_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication is required.';
  end if;

  if p_date > (now() at time zone 'America/Chicago')::date then
    raise exception 'A completed service cannot be logged in the future.';
  end if;

  if p_duration_minutes < 30 or p_duration_minutes > 720
    or p_duration_minutes % 30 <> 0
  then
    raise exception 'Duration must use 30-minute increments.';
  end if;

  if (p_service_type_id is null) = (nullif(trim(p_custom_name), '') is null) then
    raise exception 'Choose a catalog service or enter one custom name.';
  end if;

  if p_service_type_id is not null and not exists (
    select 1 from public.service_types
    where id = p_service_type_id and is_active
  ) then
    raise exception 'The selected service is not available.';
  end if;

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
    p_service_type_id,
    nullif(trim(p_custom_name), ''),
    p_date,
    p_start_time,
    p_duration_minutes,
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
    completed_at
  )
  values (
    created_instance_id,
    auth.uid(),
    'self_logged',
    null,
    'completed',
    'self_report',
    now()
  );

  return created_instance_id;
end;
$$;

create or replace function public.offer_service_instance(
  p_instance_id uuid,
  p_devotee_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  instance_record public.service_instances;
  created_offer_id uuid;
  coordinator_name text;
begin
  if not public.has_permission('services.offer_assignment') then
    raise exception 'You are not allowed to ask a devotee to take this service.';
  end if;

  select * into instance_record
  from public.service_instances
  where id = p_instance_id
  for update;

  if instance_record.id is null or instance_record.status not in ('open', 'full') then
    raise exception 'This service is not accepting offers.';
  end if;

  perform public.refresh_service_instance_capacity(p_instance_id);
  select * into instance_record from public.service_instances where id = p_instance_id;
  if instance_record.status = 'full' then
    raise exception 'This service is already full.';
  end if;

  if not exists (select 1 from public.users where id = p_devotee_id) then
    raise exception 'The selected devotee could not be found.';
  end if;

  if exists (
    select 1 from public.service_assignments
    where service_instance_id = p_instance_id
      and devotee_id = p_devotee_id
      and status in ('assigned', 'confirmed', 'completed')
  ) then
    raise exception 'This devotee is already assigned.';
  end if;

  insert into public.service_offers (
    service_instance_id,
    offered_to,
    offered_by,
    offer_kind,
    status
  )
  values (p_instance_id, p_devotee_id, auth.uid(), 'one_time', 'pending')
  on conflict (service_instance_id, offered_to) do update
  set
    offered_by = excluded.offered_by,
    offer_kind = excluded.offer_kind,
    status = 'pending',
    created_at = now(),
    responded_at = null
  returning id into created_offer_id;

  select name into coordinator_name from public.users where id = auth.uid();
  perform public.queue_app_notification(
    p_devotee_id,
    'service_offer',
    'Can you help with this seva?',
    coordinator_name || ' is asking for your help with "' ||
      public.service_instance_name(instance_record) || '" on ' ||
      to_char(instance_record.date, 'FMDay, FMMonth FMDD') || ' at ' ||
      to_char(instance_record.start_time, 'FMHH12:MI AM') ||
      '. Please let them know if you are available.',
    jsonb_build_object(
      'serviceInstanceId', p_instance_id,
      'serviceOfferId', created_offer_id
    )
  );

  return created_offer_id;
end;
$$;

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
  updated_offer public.service_offers;
  filled_slots integer;
  devotee_name text;
begin
  select * into offer_record
  from public.service_offers
  where id = p_offer_id
  for update;

  if offer_record.id is null or offer_record.offered_to <> auth.uid() then
    raise exception 'This service offer is not available to you.';
  end if;

  if offer_record.status <> 'pending' then
    raise exception 'This service offer has already been answered.';
  end if;

  select * into instance_record
  from public.service_instances
  where id = offer_record.service_instance_id
  for update;

  if p_accept then
    if instance_record.status not in ('open', 'full') then
      raise exception 'This service is no longer available.';
    end if;

    select count(*) into filled_slots
    from public.service_assignments
    where service_instance_id = instance_record.id
      and status in ('assigned', 'confirmed', 'completed');

    if filled_slots >= instance_record.slots_needed and not exists (
      select 1 from public.service_assignments
      where service_instance_id = instance_record.id
        and devotee_id = auth.uid()
        and status in ('assigned', 'confirmed', 'completed')
    ) then
      update public.service_offers
      set status = 'expired', responded_at = now()
      where id = p_offer_id
      returning * into updated_offer;
      return updated_offer;
    end if;

    insert into public.service_assignments (
      service_instance_id,
      devotee_id,
      assignment_method,
      assigned_by,
      status,
      verification
    )
    values (
      instance_record.id,
      auth.uid(),
      'accepted_offer',
      offer_record.offered_by,
      'confirmed',
      'self_report'
    )
    on conflict (service_instance_id, devotee_id) do update
    set
      assignment_method = 'accepted_offer',
      assigned_by = offer_record.offered_by,
      status = 'confirmed',
      verification = 'self_report',
      completed_at = null;

    update public.service_offers
    set status = 'accepted', responded_at = now()
    where id = p_offer_id
    returning * into updated_offer;

    perform public.refresh_service_instance_capacity(instance_record.id);
  else
    update public.service_offers
    set status = 'declined', responded_at = now()
    where id = p_offer_id
    returning * into updated_offer;
  end if;

  select name into devotee_name from public.users where id = auth.uid();
  perform public.queue_app_notification(
    offer_record.offered_by,
    'service_offer_response',
    case when p_accept then 'Service offer accepted' else 'Service offer declined' end,
    devotee_name || case
      when p_accept then ' accepted "'
      else ' is not available for "'
    end || public.service_instance_name(instance_record) || '".',
    jsonb_build_object(
      'serviceInstanceId', instance_record.id,
      'serviceOfferId', offer_record.id
    )
  );

  return updated_offer;
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
begin
  select * into instance_record
  from public.service_instances
  where id = p_instance_id
  for update;

  if instance_record.id is null then
    raise exception 'This service could not be found.';
  end if;

  if instance_record.posted_by is distinct from auth.uid()
    and not public.has_permission('services.manage_recurring')
  then
    raise exception 'You are not allowed to complete this service.';
  end if;

  update public.service_instances
  set status = 'completed'
  where id = p_instance_id
    and status not in ('cancelled', 'completed');

  update public.service_assignments
  set status = 'completed', completed_at = now()
  where service_instance_id = p_instance_id
    and status in ('assigned', 'confirmed');

  insert into public.app_notifications (user_id, kind, title, body, data)
  select
    service_assignments.devotee_id,
    'service_completed',
    'Seva completed',
    'Thank you for helping with "' || public.service_instance_name(instance_record) || '".',
    jsonb_build_object('serviceInstanceId', p_instance_id)
  from public.service_assignments
  where service_instance_id = p_instance_id
    and status = 'completed';
end;
$$;

alter table public.service_types enable row level security;
alter table public.service_instances enable row level security;
alter table public.service_assignments enable row level security;
alter table public.service_offers enable row level security;
alter table public.app_notifications enable row level security;

drop policy if exists "Authenticated users can read active service types"
  on public.service_types;
create policy "Authenticated users can read active service types"
  on public.service_types for select
  to authenticated
  using (is_active or public.has_permission('services.manage_catalog'));

drop policy if exists "Authenticated users can read service schedules"
  on public.service_instances;
create policy "Authenticated users can read service schedules"
  on public.service_instances for select
  to authenticated
  using (true);

drop policy if exists "Authenticated users can read service participation"
  on public.service_assignments;
create policy "Authenticated users can read service participation"
  on public.service_assignments for select
  to authenticated
  using (true);

drop policy if exists "Offer participants and coordinators can read service offers"
  on public.service_offers;
create policy "Offer participants and coordinators can read service offers"
  on public.service_offers for select
  to authenticated
  using (
    offered_to = auth.uid()
    or offered_by = auth.uid()
    or public.has_permission('services.offer_assignment')
  );

drop policy if exists "Users can read their app notifications"
  on public.app_notifications;
create policy "Users can read their app notifications"
  on public.app_notifications for select
  to authenticated
  using (user_id = auth.uid());

drop policy if exists "Users can mark their app notifications read"
  on public.app_notifications;
create policy "Users can mark their app notifications read"
  on public.app_notifications for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

revoke all on public.service_types from anon, authenticated;
revoke all on public.service_instances from anon, authenticated;
revoke all on public.service_assignments from anon, authenticated;
revoke all on public.service_offers from anon, authenticated;
revoke all on public.app_notifications from anon, authenticated;

grant select on public.service_types to authenticated;
grant select on public.service_instances to authenticated;
grant select on public.service_assignments to authenticated;
grant select on public.service_offers to authenticated;
grant select on public.app_notifications to authenticated;
grant update (read_at) on public.app_notifications to authenticated;

revoke all on function public.queue_app_notification(uuid, text, text, text, jsonb) from public;
revoke all on function public.service_instance_name(public.service_instances) from public;
revoke all on function public.refresh_service_instance_capacity(uuid) from public;
revoke all on function public.list_service_devotees() from public;
revoke all on function public.add_service_type(text, text) from public;
revoke all on function public.create_service_requirement(uuid, text, date, time, integer, integer, text, uuid[]) from public;
revoke all on function public.join_service_instance(uuid) from public;
revoke all on function public.leave_service_instance(uuid) from public;
revoke all on function public.log_completed_service(uuid, text, date, time, integer) from public;
revoke all on function public.offer_service_instance(uuid, uuid) from public;
revoke all on function public.respond_to_service_offer(uuid, boolean) from public;
revoke all on function public.complete_service_instance(uuid) from public;

grant execute on function public.list_service_devotees() to authenticated;
grant execute on function public.add_service_type(text, text) to authenticated;
grant execute on function public.create_service_requirement(uuid, text, date, time, integer, integer, text, uuid[]) to authenticated;
grant execute on function public.join_service_instance(uuid) to authenticated;
grant execute on function public.leave_service_instance(uuid) to authenticated;
grant execute on function public.log_completed_service(uuid, text, date, time, integer) to authenticated;
grant execute on function public.offer_service_instance(uuid, uuid) to authenticated;
grant execute on function public.respond_to_service_offer(uuid, boolean) to authenticated;
grant execute on function public.complete_service_instance(uuid) to authenticated;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'service_instances'
  ) then
    alter publication supabase_realtime add table public.service_instances;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'service_assignments'
  ) then
    alter publication supabase_realtime add table public.service_assignments;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'service_offers'
  ) then
    alter publication supabase_realtime add table public.service_offers;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'app_notifications'
  ) then
    alter publication supabase_realtime add table public.app_notifications;
  end if;
end;
$$;
