-- Inviting devotees alongside an open seva request, and Volunteers inviting.
-- Requires 202608040014_seva_registration.sql.
--
-- Two changes:
--   1. A Volunteer who posts a seva request may also ask particular devotees,
--      not only put it out to everyone.
--   2. An open seva request may carry invitations. "Open to everyone" and
--      "ask these devotees personally" stop being mutually exclusive: the
--      request stays joinable by anybody, and the named devotees additionally
--      get asked directly.

-- ---------------------------------------------------------------------------
-- 1. Volunteers may invite again.
-- ---------------------------------------------------------------------------

insert into public.role_permissions (role_id, permission_key)
select roles.id, 'services.offer_assignment'
from public.roles
where roles.name = 'volunteer'
on conflict (role_id, permission_key) do nothing;

-- ---------------------------------------------------------------------------
-- 2. Invitations are allowed on open requests too.
--
--    The 0009 trigger stops a Volunteer creating an invite-only need, which
--    still holds: what changes is that an *open* need may name devotees, and
--    anyone who can post may do so.
-- ---------------------------------------------------------------------------

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
  invitee_count integer := coalesce(cardinality(p_invitee_ids), 0);
begin
  if not public.has_permission('services.post_requirement') then
    raise exception 'You are not allowed to post seva requests.';
  end if;

  if invitee_count > 0 and not public.has_permission('services.offer_assignment') then
    raise exception 'Your access level cannot invite particular devotees.';
  end if;

  if p_date < (now() at time zone 'America/Chicago')::date then
    raise exception 'A seva request cannot be posted in the past.';
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

  -- Invite-only means somebody has to be invited.
  if p_participation_mode = 'invite_only' and invitee_count = 0 then
    raise exception 'Choose at least one devotee to invite.';
  end if;

  if (p_service_type_id is null) = (nullif(trim(p_custom_name), '') is null) then
    raise exception 'Choose a catalog seva or enter one seva name.';
  end if;

  if p_service_type_id is not null and not exists (
    select 1 from public.service_types
    where id = p_service_type_id and is_active
  ) then
    raise exception 'The selected seva is not available.';
  end if;

  insert into public.service_instances (
    service_type_id, custom_name, date, start_time, duration_minutes,
    slots_needed, participation_mode, posted_by, status
  )
  values (
    p_service_type_id, nullif(trim(p_custom_name), ''), p_date, p_start_time,
    p_duration_minutes, p_slots_needed, p_participation_mode, auth.uid(), 'open'
  )
  returning * into created_instance;

  select name into coordinator_name
  from public.users
  where id = auth.uid();

  display_name := public.service_instance_name(created_instance);

  -- Everybody hears about an open request.
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
    where users.id <> auth.uid()
      -- Anyone personally invited gets the direct ask below instead of the
      -- general announcement, so nobody is notified twice.
      and not (users.id = any(coalesce(p_invitee_ids, '{}'::uuid[])));
  end if;

  for invitee_id in
    select distinct unnest(coalesce(p_invitee_ids, '{}'::uuid[]))
  loop
    if invitee_id = auth.uid() then
      continue;
    end if;

    if not exists (select 1 from public.users where id = invitee_id) then
      raise exception 'An invited devotee could not be found.';
    end if;

    insert into public.service_offers (
      service_instance_id, offered_to, offered_by, offer_kind, status
    )
    values (
      created_instance.id, invitee_id, auth.uid(), 'one_time', 'pending'
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

revoke all on function public.create_service_requirement(uuid, text, date, time, integer, integer, text, uuid[]) from public, anon;
grant execute on function public.create_service_requirement(uuid, text, date, time, integer, integer, text, uuid[]) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Removing a weekly seva. The coordinator who created it, a Community Head,
--    a Tech Admin, or the President — matching how a seva request is removed.
--    Everyone standing on it is told.
-- ---------------------------------------------------------------------------

create or replace function public.delete_service_template(p_template_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  target public.service_templates;
  assignee record;
  actor_name text;
  template_name text;
begin
  select * into target
  from public.service_templates
  where id = p_template_id
  for update;

  if target.id is null then
    raise exception 'This weekly seva could not be found.';
  end if;

  if target.created_by <> auth.uid()
    and not public.has_permission('services.manage_recurring')
    and not public.has_permission('app.view_all')
  then
    raise exception 'Only the coordinator who created it, a Community Head, a Tech Admin, or the President can remove this weekly seva.';
  end if;

  select name into actor_name from public.users where id = auth.uid();
  select coalesce(service_types.name, target.custom_name)
  into template_name
  from (select 1) as singleton
  left join public.service_types on service_types.id = target.service_type_id;

  for assignee in
    select distinct devotee_id
    from public.service_template_assignees
    where service_template_id = p_template_id
      and devotee_id <> auth.uid()
  loop
    perform public.queue_app_notification(
      assignee.devotee_id,
      'service_deleted',
      'A weekly seva was removed',
      actor_name || ' removed the weekly seva "' ||
        coalesce(template_name, 'Temple seva') || '".',
      jsonb_build_object('serviceTemplateId', p_template_id)
    );
  end loop;

  -- Future occurrences nobody has joined go with it; anything already served
  -- stays as history.
  delete from public.service_instances
  where template_id = p_template_id
    and date >= (now() at time zone 'America/Chicago')::date
    and status not in ('completed', 'cancelled')
    and not exists (
      select 1 from public.service_assignments
      where service_assignments.service_instance_id = service_instances.id
        and service_assignments.status = 'completed'
    );

  delete from public.service_templates where id = p_template_id;
end;
$$;

revoke all on function public.delete_service_template(uuid) from public, anon;
grant execute on function public.delete_service_template(uuid) to authenticated;

do $$
begin
  raise notice 'open seva invitations applied';
end;
$$;
