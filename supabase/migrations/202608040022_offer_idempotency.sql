-- Answering an invitation twice is not an error.
--
-- Accepting coverage refetches the whole seva dashboard, which takes a moment.
-- The card stayed on screen while that ran, so a devotee tapped Accept again —
-- and the second call found the offer already answered and raised "This
-- weekly-seva offer is no longer available." Repeating the same answer now
-- returns the offer unchanged; only a genuinely different answer is refused.
-- Requires 202608040021_notification_wording.sql.


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
  service_name text;
  covered_instance record;
  lapsed record;
  covered_count integer := 0;
begin
  select * into offer_record from public.service_offers
  where id = p_offer_id and offer_kind = 'coverage_range' for update;
  if offer_record.id is null or offer_record.offered_to <> auth.uid() then
    raise exception 'This weekly-seva offer is no longer available.';
  end if;

  -- Already answered the same way: hand back what is already recorded rather
  -- than failing a devotee who tapped twice while the screen caught up.
  if offer_record.status = (case when p_accept then 'accepted' else 'declined' end)
  then
    return offer_record;
  end if;

  if offer_record.status <> 'pending' then
    raise exception 'You have already answered this weekly-seva request.';
  end if;
  select * into plan_record from public.service_coverage_plans
  where id = offer_record.service_coverage_plan_id for update;
  if p_accept and not exists (
    select 1 from public.service_exceptions
    where request_group_id = plan_record.request_group_id and status = 'pending'
    for update
  ) then raise exception 'This weekly seva has already been covered.'; end if;

  update public.service_offers
  set status = case when p_accept then 'accepted' else 'declined' end,
      responded_at = now()
  where id = p_offer_id returning * into updated_offer;
  update public.service_coverage_plans
  set status = case when p_accept then 'accepted' else 'declined' end,
      responded_at = now()
  where id = plan_record.id;

  select name into devotee_name from public.users where id = auth.uid();
  service_name := coalesce(
    (select service_types.name from public.service_templates templates
      join public.service_types on service_types.id = templates.service_type_id
      where templates.id = plan_record.service_template_id),
    (select custom_name from public.service_templates
      where id = plan_record.service_template_id), 'Temple seva'
  );

  if p_accept then
    -- The original devotee steps off these dates first, so their places are
    -- free before the substitute is counted against capacity.
    update public.service_assignments assignments
    set status = 'withdrawn', completed_at = null
    from public.service_instances instances
    where assignments.service_instance_id = instances.id
      and instances.template_id = plan_record.service_template_id
      and assignments.devotee_id = plan_record.original_devotee_id
      and assignments.status in ('assigned', 'confirmed')
      and instances.date >= plan_record.date_from
      and (plan_record.date_to is null or instances.date <= plan_record.date_to)
      and extract(dow from instances.date)::integer = any(plan_record.days_of_week);

    if plan_record.scope = 'forever' then
      update public.service_template_assignees
      set status = case
            when cardinality(array(
              select day_value from unnest(days_of_week) day_value
              where not (day_value = any(plan_record.days_of_week))
            )) = 0 then 'withdrawn'
            else 'active'
          end,
          days_of_week = case
            when cardinality(array(
              select day_value from unnest(days_of_week) day_value
              where not (day_value = any(plan_record.days_of_week))
            )) = 0 then plan_record.days_of_week
            else array(
              select day_value from unnest(days_of_week) day_value
              where not (day_value = any(plan_record.days_of_week)) order by day_value
            )
          end,
          updated_at = now()
      where service_template_id = plan_record.service_template_id
        and devotee_id = plan_record.original_devotee_id and status = 'active';

      insert into public.service_template_assignees (
        service_template_id, devotee_id, assigned_by, status, days_of_week
      ) values (
        plan_record.service_template_id, auth.uid(), plan_record.created_by,
        'active', plan_record.days_of_week
      ) on conflict (service_template_id, devotee_id) do update set
        status = 'active', assigned_by = excluded.assigned_by,
        days_of_week = array(
          select distinct day_value from unnest(
            public.service_template_assignees.days_of_week || excluded.days_of_week
          ) day_value order by day_value
        ), updated_at = now();
    end if;

    -- One occurrence at a time so a date somebody else already picked up is
    -- skipped rather than overfilled.
    for covered_instance in
      select instances.id, instances.slots_needed
      from public.service_instances instances
      where instances.template_id = plan_record.service_template_id
        and instances.status not in ('cancelled', 'completed')
        and instances.date >= plan_record.date_from
        and (plan_record.date_to is null or instances.date <= plan_record.date_to)
        and extract(dow from instances.date)::integer = any(plan_record.days_of_week)
      for update
    loop
      if (
        select count(*) from public.service_assignments
        where service_instance_id = covered_instance.id
          and status in ('assigned', 'confirmed', 'completed')
          and devotee_id <> auth.uid()
      ) < covered_instance.slots_needed then
        insert into public.service_assignments (
          service_instance_id, devotee_id, assignment_method, assigned_by,
          status, verification
        ) values (
          covered_instance.id, auth.uid(), 'accepted_coverage_offer',
          plan_record.created_by, 'confirmed', 'self_report'
        ) on conflict (service_instance_id, devotee_id) do update set
          status = 'confirmed', assigned_by = excluded.assigned_by,
          assignment_method = 'accepted_coverage_offer', completed_at = null;

        update public.service_exceptions exceptions set
          status = 'resolved', resolution_kind = 'substitute',
          substitute_devotee_id = auth.uid(), resolved_at = now(),
          resolved_by = plan_record.created_by
        where exceptions.request_group_id = plan_record.request_group_id
          and exceptions.status = 'pending'
          and exceptions.service_instance_id = covered_instance.id;

        covered_count := covered_count + 1;
        perform public.refresh_service_instance_capacity(covered_instance.id);
      end if;
    end loop;

    -- Competing asks for the dates now covered are withdrawn, and the devotees
    -- holding them are told instead of being left waiting on a dead request.
    for lapsed in
      select plans.id as plan_id, plans.substitute_devotee_id, offers.id as offer_id
      from public.service_coverage_plans plans
      left join public.service_offers offers
        on offers.service_coverage_plan_id = plans.id and offers.status = 'pending'
      where plans.request_group_id = plan_record.request_group_id
        and plans.id <> plan_record.id
        and plans.status = 'pending'
        and plans.date_from >= plan_record.date_from
        and (plan_record.date_to is null or plans.date_from <= plan_record.date_to)
    loop
      update public.service_coverage_plans
      set status = 'cancelled', responded_at = now() where id = lapsed.plan_id;
      if lapsed.offer_id is not null then
        update public.service_offers
        set status = 'expired', responded_at = now() where id = lapsed.offer_id;
        perform public.queue_app_notification(
          lapsed.substitute_devotee_id, 'service_offer_response',
          'A weekly seva has been covered',
          devotee_name || ' is covering "' || service_name
            || '", so nothing is needed from you.',
          jsonb_build_object('serviceTemplateId', plan_record.service_template_id)
        );
      end if;
    end loop;
  end if;

  perform public.notify_service_oversight(
    'service_offer_response',
    case when p_accept then 'Weekly coverage accepted' else 'Weekly coverage declined' end,
    devotee_name || case when p_accept then ' accepted coverage for "'
      else ' declined coverage for "' end || service_name || '".'
      || case when p_accept and covered_count = 0
           then ' No dates were free, so nothing changed.' else '' end,
    jsonb_build_object(
      'serviceTemplateId', plan_record.service_template_id,
      'serviceCoveragePlanId', plan_record.id,
      'coverageRequestGroupId', plan_record.request_group_id
    ), auth.uid()
  );

  if p_accept then
    perform public.queue_app_notification(
      plan_record.original_devotee_id, 'service_coverage_resolved',
      'Your weekly seva coverage is arranged',
      devotee_name || ' will cover "' || service_name || '" for the accepted period.',
      jsonb_build_object(
        'serviceTemplateId', plan_record.service_template_id,
        'serviceCoveragePlanId', plan_record.id
      )
    );
  else
    -- A decline used to reach oversight only. The devotee waiting on cover is
    -- the one who most needs to know the search is still open.
    perform public.queue_app_notification(
      plan_record.original_devotee_id, 'service_coverage_needed',
      'Still looking for cover',
      devotee_name || ' cannot cover "' || service_name
        || '". A coordinator is still arranging it.',
      jsonb_build_object(
        'serviceTemplateId', plan_record.service_template_id,
        'coverageRequestGroupId', plan_record.request_group_id
      )
    );
  end if;

  return updated_offer;
end;
$$;

revoke all on function public.respond_to_coverage_range_offer(uuid, boolean) from public, anon;
grant execute on function public.respond_to_coverage_range_offer(uuid, boolean) to authenticated;


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
      -- Room is counted per weekday, matching join_weekly_service and the
      -- capacity trigger. Anything else either locks devotees out of free
      -- weekdays or lets two people stand on the same one.
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

      -- One occurrence at a time so a date that is already full is skipped.
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

      -- Competing invitations only expire for weekdays that are now full, and
      -- the devotees holding them are told rather than left waiting.
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

        -- Competing asks lapse, and the devotees holding them are told rather
        -- than left waiting on a request that can no longer be accepted.
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

do $$
begin
  raise notice 'seva offer idempotency applied';
end;
$$;
