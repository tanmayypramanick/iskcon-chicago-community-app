-- Restore the ON CONFLICT predicate on one-time seva invitations.
-- Requires 202608040016_invite_within_places.sql.
--
-- public.service_offers lost its plain unique constraint in migration 0003 and
-- gained partial unique indexes, one per offer_kind. An ON CONFLICT clause has
-- to repeat that predicate to match the index. Migration 0006 corrected this,
-- but the correction was lost when create_service_requirement was rewritten in
-- 0010, so inviting a devotee while posting a seva request failed with
-- "there is no unique or exclusion constraint matching the ON CONFLICT
-- specification".

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
  distinct_invitees uuid[];
  invitee_count integer;
begin
  if not public.has_permission('services.post_requirement') then
    raise exception 'You are not allowed to post seva requests.';
  end if;

  select coalesce(array_agg(distinct invitee), '{}'::uuid[])
  into distinct_invitees
  from unnest(coalesce(p_invitee_ids, '{}'::uuid[])) as invitee
  where invitee <> auth.uid();

  invitee_count := coalesce(cardinality(distinct_invitees), 0);

  if invitee_count > 0 and not public.has_permission('services.offer_assignment') then
    raise exception 'Your access level cannot invite particular devotees.';
  end if;

  if p_slots_needed < 1 or p_slots_needed > 100 then
    raise exception 'Places needed must be between 1 and 100.';
  end if;

  if invitee_count > p_slots_needed then
    raise exception 'You chose % devotees for % place(s). Add more places or choose fewer devotees.',
      invitee_count, p_slots_needed;
  end if;

  if p_date < (now() at time zone 'America/Chicago')::date then
    raise exception 'A seva request cannot be posted in the past.';
  end if;

  if p_duration_minutes < 30 or p_duration_minutes > 720
    or p_duration_minutes % 30 <> 0
  then
    raise exception 'Duration must use 30-minute increments.';
  end if;

  if p_participation_mode not in ('open', 'invite_only') then
    raise exception 'Choose open or invite-only participation.';
  end if;

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

  select name into coordinator_name from public.users where id = auth.uid();
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
    where users.id <> auth.uid()
      and not (users.id = any(distinct_invitees));
  end if;

  foreach invitee_id in array distinct_invitees
  loop
    if not exists (select 1 from public.users where id = invitee_id) then
      raise exception 'An invited devotee could not be found.';
    end if;

    insert into public.service_offers (
      service_instance_id, offered_to, offered_by, offer_kind, status
    )
    values (
      created_instance.id, invitee_id, auth.uid(), 'one_time', 'pending'
    )
    -- service_offers has partial unique indexes per offer_kind (migration
    -- 0003), so ON CONFLICT must repeat the predicate or Postgres cannot
    -- match an index. Migration 0006 fixed this once; it was lost when the
    -- function was rewritten in 0010.
    on conflict (service_instance_id, offered_to)
      where offer_kind = 'one_time'
    do update
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


do $$
begin
  raise notice 'one-time invitation conflict predicate restored';
end;
$$;
