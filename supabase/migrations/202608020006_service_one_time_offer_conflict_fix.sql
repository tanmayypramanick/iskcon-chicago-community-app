-- Fix one-time service offers after recurring/coverage offers changed the
-- uniqueness rule to a partial index. Requires 202608020003.

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
    on conflict (service_instance_id, offered_to)
      where offer_kind = 'one_time'
    do update set
      offered_by = excluded.offered_by,
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
  select * into instance_record
  from public.service_instances
  where id = p_instance_id;

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
  on conflict (service_instance_id, offered_to)
    where offer_kind = 'one_time'
  do update set
    offered_by = excluded.offered_by,
    status = 'pending',
    created_at = now(),
    responded_at = null
  returning id into created_offer_id;

  select name into coordinator_name
  from public.users
  where id = auth.uid();

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

