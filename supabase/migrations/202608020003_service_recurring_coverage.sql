-- Recurring service templates, standing assignees, unavailable exceptions,
-- broadcast reopening, and targeted coverage offers.
-- Requires 202608020002_service_core.sql.

create table public.service_templates (
  id uuid primary key default gen_random_uuid(),
  service_type_id uuid not null references public.service_types(id),
  day_of_week integer not null check (day_of_week between 0 and 6),
  start_time time not null,
  duration_minutes integer not null check (
    duration_minutes between 30 and 720 and duration_minutes % 30 = 0
  ),
  slots_needed integer not null check (slots_needed between 1 and 100),
  participation_mode text not null default 'invite_only' check (
    participation_mode in ('open', 'invite_only')
  ),
  start_date date not null,
  end_date date,
  created_by uuid not null references public.users(id),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint service_template_date_order check (
    end_date is null or end_date >= start_date
  )
);

create index service_templates_active_schedule_idx
  on public.service_templates(active, day_of_week, start_date);

alter table public.service_instances
  add constraint service_instances_template_id_fkey
  foreign key (template_id) references public.service_templates(id) on delete set null;

create unique index service_instances_template_date_key
  on public.service_instances(template_id, date)
  where template_id is not null;

create table public.service_template_assignees (
  id uuid primary key default gen_random_uuid(),
  service_template_id uuid not null references public.service_templates(id) on delete cascade,
  devotee_id uuid not null references public.users(id) on delete cascade,
  assigned_by uuid not null references public.users(id),
  status text not null default 'active' check (
    status in ('active', 'withdrawn')
  ),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (service_template_id, devotee_id)
);

create index service_template_assignees_devotee_idx
  on public.service_template_assignees(devotee_id, status);

create table public.service_exceptions (
  id uuid primary key default gen_random_uuid(),
  service_instance_id uuid not null references public.service_instances(id) on delete cascade,
  devotee_id uuid not null references public.users(id) on delete cascade,
  reason text,
  status text not null default 'pending' check (
    status in ('pending', 'resolved')
  ),
  resolution_kind text check (
    resolution_kind in ('broadcast', 'substitute')
  ),
  substitute_devotee_id uuid references public.users(id),
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid references public.users(id),
  constraint service_exception_resolution_consistency check (
    (status = 'pending' and resolved_at is null and resolved_by is null)
    or
    (status = 'resolved' and resolved_at is not null and resolved_by is not null)
  ),
  unique (service_instance_id, devotee_id)
);

create index service_exceptions_status_created_idx
  on public.service_exceptions(status, created_at desc);

alter table public.service_offers
  drop constraint service_offers_service_instance_id_offered_to_key;

alter table public.service_offers
  alter column service_instance_id drop not null,
  add column service_template_id uuid references public.service_templates(id) on delete cascade,
  add column service_exception_id uuid references public.service_exceptions(id) on delete cascade;

alter table public.service_offers
  drop constraint service_offers_offer_kind_check;

alter table public.service_offers
  add constraint service_offers_offer_kind_check check (
    offer_kind in ('one_time', 'recurring', 'coverage')
  ),
  add constraint service_offer_context_check check (
    (
      offer_kind = 'one_time'
      and service_instance_id is not null
      and service_template_id is null
      and service_exception_id is null
    )
    or
    (
      offer_kind = 'recurring'
      and service_instance_id is null
      and service_template_id is not null
      and service_exception_id is null
    )
    or
    (
      offer_kind = 'coverage'
      and service_instance_id is not null
      and service_template_id is null
      and service_exception_id is not null
    )
  );

create unique index service_offers_one_time_recipient_key
  on public.service_offers(service_instance_id, offered_to)
  where offer_kind = 'one_time';

create unique index service_offers_recurring_recipient_key
  on public.service_offers(service_template_id, offered_to)
  where offer_kind = 'recurring';

create unique index service_offers_coverage_recipient_key
  on public.service_offers(service_exception_id, offered_to)
  where offer_kind = 'coverage';

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
      'service_coverage_needed',
      'service_coverage_resolved',
      'remote'
    )
  );

create or replace function public.generate_service_instances(
  p_days_ahead integer default 28
)
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

  if auth.uid() is not null
    and not public.has_permission('services.manage_recurring')
  then
    raise exception 'You are not allowed to generate recurring services.';
  end if;

  for template_record in
    select *
    from public.service_templates
    where active
      and start_date <= chicago_today + p_days_ahead
      and (end_date is null or end_date >= chicago_today)
  loop
    for scheduled_date in
      select generated_day::date
      from generate_series(
        greatest(template_record.start_date, chicago_today)::timestamp,
        least(
          coalesce(template_record.end_date, chicago_today + p_days_ahead),
          chicago_today + p_days_ahead
        )::timestamp,
        interval '1 day'
      ) as generated_day
      where extract(dow from generated_day)::integer = template_record.day_of_week
    loop
      instance_id := null;

      insert into public.service_instances (
        template_id,
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
        template_record.id,
        template_record.service_type_id,
        null,
        scheduled_date,
        template_record.start_time,
        template_record.duration_minutes,
        template_record.slots_needed,
        template_record.participation_mode,
        null,
        'open'
      )
      on conflict (template_id, date) where template_id is not null do nothing
      returning id into instance_id;

      if instance_id is not null then
        generated_count := generated_count + 1;
      else
        select id into instance_id
        from public.service_instances
        where template_id = template_record.id
          and date = scheduled_date;
      end if;

      insert into public.service_assignments (
        service_instance_id,
        devotee_id,
        assignment_method,
        assigned_by,
        status,
        verification
      )
      select
        instance_id,
        service_template_assignees.devotee_id,
        'recurring_assignment',
        service_template_assignees.assigned_by,
        'confirmed',
        'self_report'
      from public.service_template_assignees
      where service_template_assignees.service_template_id = template_record.id
        and service_template_assignees.status = 'active'
      on conflict (service_instance_id, devotee_id) do nothing;

      perform public.refresh_service_instance_capacity(instance_id);
    end loop;
  end loop;

  return generated_count;
end;
$$;

create or replace function public.create_service_template(
  p_service_type_id uuid,
  p_day_of_week integer,
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
  created_template public.service_templates;
  invitee_id uuid;
  created_offer_id uuid;
  coordinator_name text;
  service_name text;
begin
  if not public.has_permission('services.manage_recurring') then
    raise exception 'Only an authorized coordinator can create recurring services.';
  end if;

  if p_day_of_week < 0 or p_day_of_week > 6 then
    raise exception 'Choose a valid day of the week.';
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

  if p_start_date < (now() at time zone 'America/Chicago')::date
    or (p_end_date is not null and p_end_date < p_start_date)
  then
    raise exception 'Choose a valid current or future date range.';
  end if;

  select name into service_name
  from public.service_types
  where id = p_service_type_id and is_active;

  if service_name is null then
    raise exception 'The selected service is not available.';
  end if;

  insert into public.service_templates (
    service_type_id,
    day_of_week,
    start_time,
    duration_minutes,
    slots_needed,
    participation_mode,
    start_date,
    end_date,
    created_by
  )
  values (
    p_service_type_id,
    p_day_of_week,
    p_start_time,
    p_duration_minutes,
    p_slots_needed,
    p_participation_mode,
    p_start_date,
    p_end_date,
    auth.uid()
  )
  returning * into created_template;

  select name into coordinator_name
  from public.users
  where id = auth.uid();

  for invitee_id in
    select distinct unnest(coalesce(p_invitee_ids, '{}'::uuid[]))
  loop
    if not exists (select 1 from public.users where id = invitee_id) then
      raise exception 'An invited devotee could not be found.';
    end if;

    insert into public.service_offers (
      service_instance_id,
      service_template_id,
      service_exception_id,
      offered_to,
      offered_by,
      offer_kind,
      status
    )
    values (
      null,
      created_template.id,
      null,
      invitee_id,
      auth.uid(),
      'recurring',
      'pending'
    )
    on conflict (service_template_id, offered_to)
      where offer_kind = 'recurring'
    do update set
      offered_by = excluded.offered_by,
      status = 'pending',
      created_at = now(),
      responded_at = null
    returning id into created_offer_id;

    perform public.queue_app_notification(
      invitee_id,
      'service_recurring_offer',
      'A weekly seva invitation',
      coordinator_name || ' is asking if you can help with "' || service_name ||
        '" every ' || (array[
          'Sunday', 'Monday', 'Tuesday', 'Wednesday',
          'Thursday', 'Friday', 'Saturday'
        ])[created_template.day_of_week + 1] ||
        ' at ' || to_char(created_template.start_time, 'FMHH12:MI AM') || '.',
      jsonb_build_object(
        'serviceTemplateId', created_template.id,
        'serviceOfferId', created_offer_id
      )
    );
  end loop;

  perform public.generate_service_instances(28);
  return created_template.id;
end;
$$;

create or replace function public.report_service_unavailable(
  p_instance_id uuid,
  p_reason text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  instance_record public.service_instances;
  exception_id uuid;
  devotee_name text;
begin
  if not public.has_permission('services.report_unavailable') then
    raise exception 'You are not allowed to report unavailability.';
  end if;

  select * into instance_record
  from public.service_instances
  where id = p_instance_id
  for update;

  if instance_record.id is null or instance_record.template_id is null
    or instance_record.status in ('cancelled', 'completed')
    or instance_record.date < (now() at time zone 'America/Chicago')::date
  then
    raise exception 'This recurring service can no longer be changed.';
  end if;

  update public.service_assignments
  set status = 'withdrawn', completed_at = null
  where service_instance_id = p_instance_id
    and devotee_id = auth.uid()
    and status in ('assigned', 'confirmed');

  if not found then
    raise exception 'You are not assigned to this recurring service.';
  end if;

  insert into public.service_exceptions (
    service_instance_id,
    devotee_id,
    reason,
    status,
    resolution_kind,
    substitute_devotee_id,
    resolved_at,
    resolved_by
  )
  values (
    p_instance_id,
    auth.uid(),
    nullif(trim(p_reason), ''),
    'pending',
    null,
    null,
    null,
    null
  )
  on conflict (service_instance_id, devotee_id) do update set
    reason = excluded.reason,
    status = 'pending',
    resolution_kind = null,
    substitute_devotee_id = null,
    created_at = now(),
    resolved_at = null,
    resolved_by = null
  returning id into exception_id;

  perform public.refresh_service_instance_capacity(p_instance_id);
  select name into devotee_name from public.users where id = auth.uid();

  insert into public.app_notifications (user_id, kind, title, body, data)
  select
    users.id,
    'service_coverage_needed',
    'Help is needed for a recurring seva',
    devotee_name || ' is unavailable for "' ||
      public.service_instance_name(instance_record) || '" on ' ||
      to_char(instance_record.date, 'FMDay, FMMonth FMDD') || ' at ' ||
      to_char(instance_record.start_time, 'FMHH12:MI AM') || '.',
    jsonb_build_object(
      'serviceInstanceId', instance_record.id,
      'serviceExceptionId', exception_id
    )
  from public.users
  join public.role_permissions
    on role_permissions.role_id = users.role_id
   and role_permissions.permission_key = 'services.resolve_coverage'
  where users.id <> auth.uid();

  return exception_id;
end;
$$;

create or replace function public.reopen_service_exception(
  p_exception_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  exception_record public.service_exceptions;
begin
  if not public.has_permission('services.resolve_coverage') then
    raise exception 'You are not allowed to arrange service coverage.';
  end if;

  select * into exception_record
  from public.service_exceptions
  where id = p_exception_id
  for update;

  if exception_record.id is null or exception_record.status <> 'pending' then
    raise exception 'This coverage request is no longer pending.';
  end if;

  update public.service_exceptions
  set resolution_kind = 'broadcast'
  where id = p_exception_id;

  update public.service_instances
  set participation_mode = 'open', status = 'open'
  where id = exception_record.service_instance_id
    and status not in ('cancelled', 'completed');

  insert into public.app_notifications (user_id, kind, title, body, data)
  select
    users.id,
    'service_open',
    'A recurring seva needs help',
    'A place is open for "' || public.service_instance_name(service_instances) ||
      '" on ' || to_char(service_instances.date, 'FMDay, FMMonth FMDD') ||
      ' at ' || to_char(service_instances.start_time, 'FMHH12:MI AM') || '.',
    jsonb_build_object(
      'serviceInstanceId', service_instances.id,
      'serviceExceptionId', exception_record.id
    )
  from public.users
  cross join public.service_instances
  where service_instances.id = exception_record.service_instance_id
    and users.id <> exception_record.devotee_id;
end;
$$;

create or replace function public.offer_service_coverage(
  p_exception_id uuid,
  p_devotee_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  exception_record public.service_exceptions;
  instance_record public.service_instances;
  created_offer_id uuid;
  coordinator_name text;
begin
  if not public.has_permission('services.resolve_coverage') then
    raise exception 'You are not allowed to arrange service coverage.';
  end if;

  select * into exception_record
  from public.service_exceptions
  where id = p_exception_id
  for update;

  if exception_record.id is null or exception_record.status <> 'pending' then
    raise exception 'This coverage request is no longer pending.';
  end if;

  if p_devotee_id = exception_record.devotee_id
    or not exists (select 1 from public.users where id = p_devotee_id)
  then
    raise exception 'Choose another available devotee.';
  end if;

  select * into instance_record
  from public.service_instances
  where id = exception_record.service_instance_id;

  if exists (
    select 1 from public.service_assignments
    where service_instance_id = instance_record.id
      and devotee_id = p_devotee_id
      and status in ('assigned', 'confirmed', 'completed')
  ) then
    raise exception 'This devotee is already assigned.';
  end if;

  insert into public.service_offers (
    service_instance_id,
    service_template_id,
    service_exception_id,
    offered_to,
    offered_by,
    offer_kind,
    status
  )
  values (
    instance_record.id,
    null,
    exception_record.id,
    p_devotee_id,
    auth.uid(),
    'coverage',
    'pending'
  )
  on conflict (service_exception_id, offered_to)
    where offer_kind = 'coverage'
  do update set
    offered_by = excluded.offered_by,
    status = 'pending',
    created_at = now(),
    responded_at = null
  returning id into created_offer_id;

  select name into coordinator_name from public.users where id = auth.uid();
  perform public.queue_app_notification(
    p_devotee_id,
    'service_offer',
    'Can you cover this seva?',
    coordinator_name || ' is asking for your help with "' ||
      public.service_instance_name(instance_record) || '" on ' ||
      to_char(instance_record.date, 'FMDay, FMMonth FMDD') || ' at ' ||
      to_char(instance_record.start_time, 'FMHH12:MI AM') ||
      '. Please tell them if you are available.',
    jsonb_build_object(
      'serviceInstanceId', instance_record.id,
      'serviceExceptionId', exception_record.id,
      'serviceOfferId', created_offer_id
    )
  );

  return created_offer_id;
end;
$$;

create or replace function public.resolve_broadcast_exception_after_assignment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  resolved_exception_id uuid;
begin
  if new.status not in ('assigned', 'confirmed', 'completed') then
    return new;
  end if;

  update public.service_exceptions
  set
    status = 'resolved',
    resolution_kind = 'substitute',
    substitute_devotee_id = new.devotee_id,
    resolved_at = now(),
    resolved_by = new.devotee_id
  where id = (
    select id
    from public.service_exceptions
    where service_instance_id = new.service_instance_id
      and devotee_id <> new.devotee_id
      and status = 'pending'
      and resolution_kind = 'broadcast'
    order by created_at
    limit 1
    for update skip locked
  )
  returning id into resolved_exception_id;

  if resolved_exception_id is not null then
    update public.service_offers
    set status = 'expired', responded_at = now()
    where service_exception_id = resolved_exception_id
      and status = 'pending';
  end if;

  return new;
end;
$$;

create trigger resolve_broadcast_exception_after_assignment
after insert or update of status on public.service_assignments
for each row execute function public.resolve_broadcast_exception_after_assignment();

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

  if offer_record.offer_kind = 'recurring' then
    select * into template_record
    from public.service_templates
    where id = offer_record.service_template_id
    for update;

    if p_accept and (template_record.id is null or not template_record.active) then
      raise exception 'This recurring service is no longer active.';
    end if;

    if p_accept then
      select count(*) into active_recurring_assignees
      from public.service_template_assignees
      where service_template_id = template_record.id
        and status = 'active';

      if active_recurring_assignees >= template_record.slots_needed and not exists (
        select 1
        from public.service_template_assignees
        where service_template_id = template_record.id
          and devotee_id = auth.uid()
          and status = 'active'
      ) then
        update public.service_offers
        set status = 'expired', responded_at = now()
        where id = p_offer_id
        returning * into updated_offer;
        return updated_offer;
      end if;

      insert into public.service_template_assignees (
        service_template_id,
        devotee_id,
        assigned_by,
        status
      )
      values (
        template_record.id,
        auth.uid(),
        offer_record.offered_by,
        'active'
      )
      on conflict (service_template_id, devotee_id) do update set
        assigned_by = excluded.assigned_by,
        status = 'active',
        updated_at = now();

      perform public.generate_service_instances(28);

      insert into public.service_assignments (
        service_instance_id,
        devotee_id,
        assignment_method,
        assigned_by,
        status,
        verification
      )
      select
        service_instances.id,
        auth.uid(),
        'recurring_assignment',
        offer_record.offered_by,
        'confirmed',
        'self_report'
      from public.service_instances
      where service_instances.template_id = template_record.id
        and service_instances.date >= (now() at time zone 'America/Chicago')::date
        and service_instances.status not in ('cancelled', 'completed')
      on conflict (service_instance_id, devotee_id) do nothing;

      for future_instance in
        select id from public.service_instances
        where template_id = template_record.id
          and date >= (now() at time zone 'America/Chicago')::date
      loop
        perform public.refresh_service_instance_capacity(future_instance.id);
      end loop;

      update public.service_offers
      set status = 'expired', responded_at = now()
      where service_template_id = template_record.id
        and id <> offer_record.id
        and status = 'pending'
        and (
          select count(*)
          from public.service_template_assignees
          where service_template_id = template_record.id
            and status = 'active'
        ) >= template_record.slots_needed;
    end if;

    select name into service_name
    from public.service_types
    where id = template_record.service_type_id;
  else
    select * into instance_record
    from public.service_instances
    where id = offer_record.service_instance_id
    for update;

    service_name := public.service_instance_name(instance_record);

    if offer_record.offer_kind = 'coverage' then
      select * into exception_record
      from public.service_exceptions
      where id = offer_record.service_exception_id
      for update;

      if p_accept and (
        exception_record.id is null or exception_record.status <> 'pending'
      ) then
        raise exception 'This service coverage has already been resolved.';
      end if;
    end if;

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
        case
          when offer_record.offer_kind = 'coverage'
            then 'accepted_coverage_offer'
          else 'accepted_offer'
        end,
        offer_record.offered_by,
        'confirmed',
        'self_report'
      )
      on conflict (service_instance_id, devotee_id) do update set
        assignment_method = excluded.assignment_method,
        assigned_by = excluded.assigned_by,
        status = 'confirmed',
        verification = 'self_report',
        completed_at = null;

      if offer_record.offer_kind = 'coverage' then
        update public.service_exceptions
        set
          status = 'resolved',
          resolution_kind = 'substitute',
          substitute_devotee_id = auth.uid(),
          resolved_at = now(),
          resolved_by = offer_record.offered_by
        where id = offer_record.service_exception_id;

        update public.service_offers
        set status = 'expired', responded_at = now()
        where service_exception_id = offer_record.service_exception_id
          and id <> offer_record.id
          and status = 'pending';
      end if;

      perform public.refresh_service_instance_capacity(instance_record.id);
    end if;
  end if;

  update public.service_offers
  set
    status = case when p_accept then 'accepted' else 'declined' end,
    responded_at = now()
  where id = p_offer_id
  returning * into updated_offer;

  select name into devotee_name from public.users where id = auth.uid();
  perform public.queue_app_notification(
    offer_record.offered_by,
    'service_offer_response',
    case when p_accept then 'Service offer accepted' else 'Service offer declined' end,
    devotee_name || case
      when p_accept then ' accepted "'
      else ' is not available for "'
    end || service_name || '".',
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

create or replace function public.set_service_template_active(
  p_template_id uuid,
  p_active boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.has_permission('services.manage_recurring') then
    raise exception 'You are not allowed to manage recurring services.';
  end if;

  update public.service_templates
  set active = p_active, updated_at = now()
  where id = p_template_id;

  if not found then
    raise exception 'This recurring service could not be found.';
  end if;

  if p_active then
    perform public.generate_service_instances(28);
  else
    update public.service_instances
    set status = 'cancelled'
    where template_id = p_template_id
      and date >= (now() at time zone 'America/Chicago')::date
      and status not in ('completed', 'cancelled');

    update public.service_offers
    set status = 'expired', responded_at = now()
    where service_template_id = p_template_id
      and status = 'pending';
  end if;
end;
$$;

alter table public.service_templates enable row level security;
alter table public.service_template_assignees enable row level security;
alter table public.service_exceptions enable row level security;

create policy "Authenticated users can read recurring service templates"
  on public.service_templates for select
  to authenticated
  using (true);

create policy "Authenticated users can read recurring assignees"
  on public.service_template_assignees for select
  to authenticated
  using (true);

create policy "Users and coordinators can read service exceptions"
  on public.service_exceptions for select
  to authenticated
  using (
    devotee_id = auth.uid()
    or public.has_permission('services.resolve_coverage')
  );

revoke all on public.service_templates from anon, authenticated;
revoke all on public.service_template_assignees from anon, authenticated;
revoke all on public.service_exceptions from anon, authenticated;

grant select on public.service_templates to authenticated;
grant select on public.service_template_assignees to authenticated;
grant select on public.service_exceptions to authenticated;

revoke all on function public.generate_service_instances(integer) from public;
revoke all on function public.create_service_template(uuid, integer, time, integer, integer, text, date, date, uuid[]) from public;
revoke all on function public.report_service_unavailable(uuid, text) from public;
revoke all on function public.reopen_service_exception(uuid) from public;
revoke all on function public.offer_service_coverage(uuid, uuid) from public;
revoke all on function public.resolve_broadcast_exception_after_assignment() from public;
revoke all on function public.set_service_template_active(uuid, boolean) from public;

grant execute on function public.generate_service_instances(integer) to authenticated;
grant execute on function public.create_service_template(uuid, integer, time, integer, integer, text, date, date, uuid[]) to authenticated;
grant execute on function public.report_service_unavailable(uuid, text) to authenticated;
grant execute on function public.reopen_service_exception(uuid) to authenticated;
grant execute on function public.offer_service_coverage(uuid, uuid) to authenticated;
grant execute on function public.set_service_template_active(uuid, boolean) to authenticated;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'service_templates'
  ) then
    alter publication supabase_realtime add table public.service_templates;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'service_template_assignees'
  ) then
    alter publication supabase_realtime add table public.service_template_assignees;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'service_exceptions'
  ) then
    alter publication supabase_realtime add table public.service_exceptions;
  end if;
end;
$$;
