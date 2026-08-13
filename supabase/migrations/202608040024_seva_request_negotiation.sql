-- Answering a seva request with "I can do it, but at another time", and giving
-- whoever posted it somewhere to deal with the answer.
--
-- Weekly seva already had this back-and-forth. A dated seva request had only
-- yes or no, and a no went nowhere the poster would look. This adds the same
-- conversation to dated seva, routes both a decline and a suggestion into the
-- coverage inbox, and lets the poster reshape the request from there.
-- Requires 202608040023_completion_authority.sql.

-- ---------------------------------------------------------------------------
-- 1. A counter-offer can name a date, not only weekdays.
--
--    proposed_days stays populated with the weekday of that date so the
--    existing constraint and the weekly reader both keep working.
-- ---------------------------------------------------------------------------

alter table public.service_offer_counters
  add column if not exists proposed_date date;

-- ---------------------------------------------------------------------------
-- 2. Suggesting another time for a dated seva request.
-- ---------------------------------------------------------------------------

create or replace function public.propose_service_offer_alternative(
  p_offer_id uuid,
  p_date date,
  p_start_time time,
  p_duration_minutes integer,
  p_note text default null
)
returns public.service_offer_counters
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_offer public.service_offers;
  instance_record public.service_instances;
  created_counter public.service_offer_counters;
  devotee_name text;
  seva_name text;
begin
  select * into target_offer
  from public.service_offers
  where id = p_offer_id
  for update;

  if target_offer.id is null or target_offer.offered_to <> auth.uid() then
    raise exception 'This seva invitation could not be found.';
  end if;

  if target_offer.status <> 'pending' then
    raise exception 'You have already answered this invitation.';
  end if;

  if target_offer.offer_kind in ('recurring', 'coverage_range') then
    raise exception 'Use the weekly response for a weekly seva invitation.';
  end if;

  if target_offer.service_instance_id is null then
    raise exception 'This invitation is not for a dated seva.';
  end if;

  select * into instance_record from public.service_instances
  where id = target_offer.service_instance_id;

  if p_date < (now() at time zone 'America/Chicago')::date then
    raise exception 'Choose a day that has not already passed.';
  end if;

  if p_duration_minutes < 15 or p_duration_minutes > 720 then
    raise exception 'Choose a length between 15 minutes and 12 hours.';
  end if;

  insert into public.service_offer_counters (
    service_offer_id, devotee_id, proposed_days, proposed_date,
    proposed_start_time, proposed_duration_minutes, note
  )
  values (
    p_offer_id, auth.uid(),
    array[extract(dow from p_date)::integer], p_date,
    p_start_time, greatest(30, ceil(p_duration_minutes / 30.0) * 30)::integer,
    nullif(trim(p_note), '')
  )
  returning * into created_counter;

  update public.service_offers
  set status = 'countered', responded_at = now()
  where id = p_offer_id;

  perform public.refresh_service_instance_capacity(instance_record.id);

  select name into devotee_name from public.users where id = auth.uid();
  seva_name := public.service_instance_name(instance_record);

  perform public.queue_app_notification(
    target_offer.offered_by,
    'weekly_offer_countered',
    'A devotee suggested another time',
    devotee_name || ' cannot do "' || seva_name || '" as asked, and offered '
      || public.format_seva_when(p_date, p_start_time) || ' instead.',
    jsonb_build_object(
      'serviceOfferId', p_offer_id,
      'serviceOfferCounterId', created_counter.id,
      'serviceInstanceId', instance_record.id
    )
  );

  return created_counter;
exception
  when unique_violation then
    raise exception 'You already suggested another time for this invitation.';
end;
$$;

revoke all on function public.propose_service_offer_alternative(uuid, date, time, integer, text) from public, anon;
grant execute on function public.propose_service_offer_alternative(uuid, date, time, integer, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. The poster answers the suggestion.
--
--    Accepting moves the seva to the time the devotee offered and puts them on
--    it. Moving a seva that other devotees have already joined would change
--    the plan under their feet, so that is refused rather than done quietly.
-- ---------------------------------------------------------------------------

create or replace function public.respond_to_service_offer_counter(
  p_counter_id uuid,
  p_accept boolean,
  p_note text default null
)
returns public.service_offer_counters
language plpgsql
security definer
set search_path = ''
as $$
declare
  counter_record public.service_offer_counters;
  target_offer public.service_offers;
  instance_record public.service_instances;
  reviewed_counter public.service_offer_counters;
  others integer;
  actor_name text;
  seva_name text;
begin
  select * into counter_record from public.service_offer_counters
  where id = p_counter_id for update;
  if counter_record.id is null or counter_record.status <> 'pending' then
    raise exception 'This suggestion has already been answered.';
  end if;
  if counter_record.proposed_date is null then
    raise exception 'Use the weekly response for a weekly suggestion.';
  end if;

  select * into target_offer from public.service_offers
  where id = counter_record.service_offer_id for update;
  select * into instance_record from public.service_instances
  where id = target_offer.service_instance_id for update;
  if instance_record.id is null then
    raise exception 'The seva this suggestion belongs to is gone.';
  end if;

  if instance_record.posted_by is distinct from auth.uid()
    and not public.has_permission('app.view_all')
  then
    raise exception 'Only the devotee who posted this seva request, a Tech Admin, or the President can answer it.';
  end if;

  if p_accept then
    select count(*) into others from public.service_assignments
    where service_instance_id = instance_record.id
      and status in ('assigned', 'confirmed', 'completed')
      and devotee_id <> counter_record.devotee_id;
    if others > 0 then
      raise exception 'Other devotees have already joined this seva, so it cannot be moved. Post a separate seva request for the new time.';
    end if;

    update public.service_instances
    set date = counter_record.proposed_date,
        start_time = counter_record.proposed_start_time,
        duration_minutes = counter_record.proposed_duration_minutes
    where id = instance_record.id;

    insert into public.service_assignments (
      service_instance_id, devotee_id, assignment_method, assigned_by,
      status, verification
    ) values (
      instance_record.id, counter_record.devotee_id, 'accepted_offer',
      auth.uid(), 'confirmed', 'self_report'
    ) on conflict (service_instance_id, devotee_id) do update set
      status = 'confirmed', assignment_method = 'accepted_offer',
      assigned_by = excluded.assigned_by, completed_at = null;

    update public.service_offers
    set status = 'accepted', responded_at = now()
    where id = target_offer.id;

    perform public.refresh_service_instance_capacity(instance_record.id);
  else
    update public.service_offers
    set status = 'declined', responded_at = now()
    where id = target_offer.id;
  end if;

  update public.service_offer_counters
  set status = case when p_accept then 'approved' else 'declined' end,
      review_note = nullif(trim(p_note), ''),
      responded_at = now(),
      responded_by = auth.uid()
  where id = p_counter_id
  returning * into reviewed_counter;

  select * into instance_record from public.service_instances
  where id = instance_record.id;
  select name into actor_name from public.users where id = auth.uid();
  seva_name := public.service_instance_name(instance_record);

  perform public.queue_app_notification(
    counter_record.devotee_id,
    'weekly_offer_counter_reviewed',
    case when p_accept then 'Your suggested time was accepted'
      else 'Your suggested time was not taken up' end,
    case when p_accept
      then actor_name || ' moved "' || seva_name || '" to '
           || public.format_seva_when(instance_record.date, instance_record.start_time)
           || '. You are on it.'
      else actor_name || ' could not move "' || seva_name || '" to the time you offered.'
    end,
    jsonb_build_object(
      'serviceInstanceId', instance_record.id,
      'serviceOfferCounterId', reviewed_counter.id
    )
  );

  return reviewed_counter;
end;
$$;

revoke all on function public.respond_to_service_offer_counter(uuid, boolean, text) from public, anon;
grant execute on function public.respond_to_service_offer_counter(uuid, boolean, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. A declined invitation is the poster's problem to solve, so tell them
--    where to solve it.
-- ---------------------------------------------------------------------------

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
  open_days integer[];
  places_left integer;
begin
  select * into offer_record from public.service_offers
  where id = p_offer_id for update;
  if offer_record.id is null or offer_record.offered_to <> auth.uid() then
    raise exception 'This service offer is not available to you.';
  end if;
  if offer_record.status = (case when p_accept then 'accepted' else 'declined' end)
  then
    return offer_record;
  end if;
  if offer_record.status <> 'pending' then
    raise exception 'You have already answered this seva invitation.';
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
      open_days := array(
        select scheduled_day
        from unnest(template_record.days_of_week) scheduled_day
        where (
          select count(*) from public.service_template_assignees assignees
          where assignees.service_template_id = template_record.id
            and assignees.status = 'active'
            and scheduled_day = any(assignees.days_of_week)
            and assignees.devotee_id <> auth.uid()
        ) < template_record.slots_needed
        order by scheduled_day
      );

      if cardinality(open_days) = 0 then
        update public.service_offers set status = 'expired', responded_at = now()
        where id = p_offer_id returning * into updated_offer;
        perform public.queue_app_notification(
          offer_record.offered_by, 'service_offer_response',
          'A weekly seva filled up first',
          'Every weekday of "' || service_name
            || '" was taken before this invitation could be accepted.',
          jsonb_build_object('serviceTemplateId', template_record.id)
        );
        return updated_offer;
      end if;

      insert into public.service_template_assignees (
        service_template_id, devotee_id, assigned_by, status, days_of_week
      ) values (
        template_record.id, auth.uid(), offer_record.offered_by, 'active', open_days
      ) on conflict (service_template_id, devotee_id) do update set
        assigned_by = excluded.assigned_by, status = 'active',
        days_of_week = array(
          select distinct day_value from unnest(
            public.service_template_assignees.days_of_week || excluded.days_of_week
          ) day_value order by day_value
        ),
        updated_at = now();

      perform public.generate_service_instances(180);

      for future_instance in
        select instances.id, instances.slots_needed
        from public.service_instances instances
        where instances.template_id = template_record.id
          and instances.date >= (now() at time zone 'America/Chicago')::date
          and instances.status not in ('cancelled', 'completed')
          and extract(dow from instances.date)::integer = any(open_days)
        for update
      loop
        if (
          select count(*) from public.service_assignments
          where service_instance_id = future_instance.id
            and status in ('assigned', 'confirmed', 'completed')
            and devotee_id <> auth.uid()
        ) < future_instance.slots_needed then
          insert into public.service_assignments (
            service_instance_id, devotee_id, assignment_method, assigned_by,
            status, verification
          ) values (
            future_instance.id, auth.uid(), 'recurring_assignment',
            offer_record.offered_by, 'confirmed', 'self_report'
          ) on conflict (service_instance_id, devotee_id) do nothing;
          perform public.refresh_service_instance_capacity(future_instance.id);
        end if;
      end loop;

      for future_instance in
        select offers.id, offers.offered_to
        from public.service_offers offers
        where offers.service_template_id = template_record.id
          and offers.id <> offer_record.id
          and offers.status = 'pending'
          and not exists (
            select 1
            from unnest(template_record.days_of_week) scheduled_day
            where (
              select count(*) from public.service_template_assignees assignees
              where assignees.service_template_id = template_record.id
                and assignees.status = 'active'
                and scheduled_day = any(assignees.days_of_week)
                and assignees.devotee_id <> offers.offered_to
            ) < template_record.slots_needed
          )
      loop
        update public.service_offers set status = 'expired', responded_at = now()
        where id = future_instance.id;
        perform public.queue_app_notification(
          future_instance.offered_to, 'service_offer_response',
          'A weekly seva has been covered',
          '"' || service_name
            || '" is now fully covered, so nothing is needed from you.',
          jsonb_build_object('serviceTemplateId', template_record.id)
        );
      end loop;
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
        and status in ('assigned', 'confirmed', 'completed')
        and devotee_id <> auth.uid();
      if filled_slots >= instance_record.slots_needed then
        update public.service_offers set status = 'expired', responded_at = now()
        where id = p_offer_id returning * into updated_offer;
        perform public.queue_app_notification(
          offer_record.offered_by, 'service_offer_response',
          'A seva filled up first',
          '"' || service_name || '" was already full, so the invitation lapsed.',
          jsonb_build_object('serviceInstanceId', instance_record.id)
        );
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

      if offer_record.offer_kind = 'coverage' and exception_record.id is not null then
        update public.service_exceptions set
          status = 'resolved', resolution_kind = 'substitute',
          substitute_devotee_id = auth.uid(), resolved_at = now(),
          resolved_by = offer_record.offered_by
        where id = exception_record.id;

        for future_instance in
          select id, offered_to from public.service_offers
          where service_exception_id = offer_record.service_exception_id
            and id <> offer_record.id and status = 'pending'
        loop
          update public.service_offers set status = 'expired', responded_at = now()
          where id = future_instance.id;
          perform public.queue_app_notification(
            future_instance.offered_to, 'service_offer_response',
            'This seva has been covered',
            '"' || service_name || '" is covered, so nothing is needed from you.',
            jsonb_build_object('serviceInstanceId', instance_record.id)
          );
        end loop;

        perform public.queue_app_notification(
          exception_record.devotee_id, 'service_coverage_resolved',
          'Your seva is covered',
          (select name from public.users where id = auth.uid())
            || ' will cover "' || service_name || '" for you.',
          jsonb_build_object('serviceInstanceId', instance_record.id)
        );
      end if;

      perform public.refresh_service_instance_capacity(instance_record.id);
    end if;
  end if;

  update public.service_offers
  set status = case when p_accept then 'accepted' else 'declined' end,
      responded_at = now()
  where id = p_offer_id returning * into updated_offer;
  select name into devotee_name from public.users where id = auth.uid();

  -- A decline on a dated seva leaves the poster a place to fill, so the
  -- message says how many are still open and points at the request itself.
  if not p_accept and offer_record.service_instance_id is not null then
    select greatest(0, instance_record.slots_needed - count(*)) into places_left
    from public.service_assignments
    where service_instance_id = instance_record.id
      and status in ('assigned', 'confirmed', 'completed');

    perform public.queue_app_notification(
      offer_record.offered_by, 'service_offer_response',
      'A devotee cannot help with your seva',
      devotee_name || ' is not available for "' || service_name || '" on '
        || public.format_seva_when(instance_record.date, instance_record.start_time)
        || '. ' || places_left || ' place'
        || case when places_left = 1 then '' else 's' end
        || ' still to fill — ask someone else or open it to everyone.',
      jsonb_build_object(
        'serviceInstanceId', offer_record.service_instance_id,
        'serviceOfferId', offer_record.id,
        'needsPoster', true
      )
    );
    return updated_offer;
  end if;

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

revoke all on function public.respond_to_service_offer(uuid, boolean) from public, anon;
grant execute on function public.respond_to_service_offer(uuid, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Reshaping a seva request without deleting and re-posting it.
--
--    Open it to everyone, ask more devotees, or change how many places there
--    are. Whoever posted it, a Tech Admin, or the President.
-- ---------------------------------------------------------------------------

create or replace function public.update_service_requirement(
  p_instance_id uuid,
  p_participation_mode text,
  p_slots_needed integer,
  p_invitee_ids uuid[] default '{}'::uuid[]
)
returns public.service_instances
language plpgsql
security definer
set search_path = ''
as $$
declare
  instance_record public.service_instances;
  updated_instance public.service_instances;
  invitee_id uuid;
  offer_id uuid;
  filled integer;
  invitee_count integer;
  coordinator_name text;
  seva_name text;
begin
  select * into instance_record from public.service_instances
  where id = p_instance_id for update;
  if instance_record.id is null then
    raise exception 'This seva request could not be found.';
  end if;
  if instance_record.template_id is not null then
    raise exception 'Weekly occurrences are changed from the weekly seva.';
  end if;
  if instance_record.status in ('completed', 'cancelled') then
    raise exception 'This seva request is closed.';
  end if;
  if instance_record.posted_by is distinct from auth.uid()
    and not public.has_permission('app.view_all')
  then
    raise exception 'Only the devotee who posted this seva request, a Tech Admin, or the President can change it.';
  end if;
  if p_participation_mode not in ('open', 'invite_only') then
    raise exception 'A seva request is either open to everyone or invite only.';
  end if;

  select count(*) into filled from public.service_assignments
  where service_instance_id = p_instance_id
    and status in ('assigned', 'confirmed', 'completed');
  if p_slots_needed < greatest(1, filled) then
    raise exception 'There are already % devotees on this seva.', filled;
  end if;
  if p_slots_needed > 100 then
    raise exception 'Places needed must be 100 or fewer.';
  end if;

  update public.service_instances
  set participation_mode = p_participation_mode,
      slots_needed = p_slots_needed
  where id = p_instance_id
  returning * into updated_instance;

  select name into coordinator_name from public.users where id = auth.uid();
  seva_name := public.service_instance_name(updated_instance);

  -- Nobody may be invited to more places than exist.
  select count(*) into invitee_count
  from unnest(coalesce(p_invitee_ids, '{}'::uuid[])) as candidate
  where candidate <> auth.uid()
    and not exists (
      select 1 from public.service_assignments
      where service_instance_id = p_instance_id and devotee_id = candidate
        and status in ('assigned', 'confirmed', 'completed')
    );
  if invitee_count + filled > p_slots_needed then
    raise exception 'That is more devotees than there are places.';
  end if;

  for invitee_id in
    select distinct unnest(coalesce(p_invitee_ids, '{}'::uuid[]))
  loop
    if invitee_id = auth.uid() then continue; end if;
    if not exists (select 1 from public.users where id = invitee_id) then
      raise exception 'An invited devotee could not be found.';
    end if;
    if exists (
      select 1 from public.service_assignments
      where service_instance_id = p_instance_id and devotee_id = invitee_id
        and status in ('assigned', 'confirmed', 'completed')
    ) then continue; end if;

    insert into public.service_offers (
      service_instance_id, service_template_id, service_exception_id,
      service_coverage_plan_id, offered_to, offered_by, offer_kind, status
    ) values (
      p_instance_id, null, null, null, invitee_id, auth.uid(), 'one_time', 'pending'
    )
    on conflict (service_instance_id, offered_to)
      where offer_kind = 'one_time'
    do update set
      offered_by = excluded.offered_by, status = 'pending',
      created_at = now(), responded_at = null
    returning id into offer_id;

    perform public.queue_app_notification(
      invitee_id, 'service_offer', 'Can you help with this seva?',
      coordinator_name || ' is asking for your help with "' || seva_name
        || '" on '
        || public.format_seva_when(updated_instance.date, updated_instance.start_time)
        || '. Please let them know if you are available.',
      jsonb_build_object(
        'serviceInstanceId', p_instance_id,
        'serviceOfferId', offer_id
      )
    );
  end loop;

  -- Opening it up tells everyone who can take seva that a place is going.
  if p_participation_mode = 'open'
    and instance_record.participation_mode <> 'open'
  then
    insert into public.app_notifications (user_id, kind, title, body, data)
    select users.id, 'service_open', 'A seva request is open to everyone',
      coordinator_name || ' opened "' || seva_name || '" on '
        || public.format_seva_when(updated_instance.date, updated_instance.start_time)
        || ' for any devotee to join.',
      jsonb_build_object('serviceInstanceId', p_instance_id)
    from public.users
    where users.id <> auth.uid()
      and public.user_has_permission(users.id, 'services.participate');
  end if;

  perform public.refresh_service_instance_capacity(p_instance_id);
  select * into updated_instance from public.service_instances where id = p_instance_id;
  return updated_instance;
end;
$$;

revoke all on function public.update_service_requirement(uuid, text, integer, uuid[]) from public, anon;
grant execute on function public.update_service_requirement(uuid, text, integer, uuid[]) to authenticated;

do $$
begin
  raise notice 'seva request negotiation applied';
end;
$$;
