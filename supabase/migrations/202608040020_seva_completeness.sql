-- Seva completeness: the gaps that were left after 0018 and 0019.
--
-- Every change here either stops something being lost, stops something being
-- overfilled, or tells somebody what happened to a request they are waiting on.
-- Requires 202608040019_seva_hardening.sql.

-- ---------------------------------------------------------------------------
-- 1. A verified seva that had not finished yet stayed 'closed' for good.
--
--    respond_to_seva_verification builds the record from the clock at the
--    moment of verifying. Verify a seva that is still ahead and the instance
--    is created 'closed' with a 'confirmed' assignment, and nothing ever moves
--    it on. The devotee's confirmed seva never reaches their completed history.
--
--    A reconciler settles them once the end time passes. It is called from
--    generate_service_instances, which every seva read path already reaches,
--    so it works with or without pg_cron.
-- ---------------------------------------------------------------------------

create or replace function public.settle_finished_verified_seva()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  settled integer := 0;
begin
  with due as (
    select verifications.id as verification_id,
           verifications.service_instance_id,
           verifications.devotee_id,
           verifications.end_at
    from public.service_verifications verifications
    join public.service_instances instances
      on instances.id = verifications.service_instance_id
    where verifications.status = 'verified'
      and verifications.end_at <= now()
      and instances.status = 'closed'
  ), moved_assignments as (
    update public.service_assignments assignments
    set status = 'completed',
        completed_at = coalesce(assignments.completed_at, due.end_at)
    from due
    where assignments.service_instance_id = due.service_instance_id
      and assignments.devotee_id = due.devotee_id
      and assignments.status in ('assigned', 'confirmed')
    returning assignments.id
  ), moved_instances as (
    update public.service_instances instances
    set status = 'completed'
    from due
    where instances.id = due.service_instance_id
    returning instances.id
  )
  select count(*) into settled from moved_instances;

  return settled;
end;
$$;

revoke all on function public.settle_finished_verified_seva() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. Registering: overlaps now raise a readable message.
--
--    0019 replaced the unique index with an exclusion constraint, so the
--    `when unique_violation` handler no longer catches a clash and the devotee
--    saw a raw Postgres error instead.
-- ---------------------------------------------------------------------------

create or replace function public.request_seva_verification(
  p_service_type_id uuid,
  p_custom_name text,
  p_start_at timestamptz,
  p_end_at timestamptz,
  p_location_text text,
  p_verifier_id uuid,
  p_qr_token text default null
)
returns public.service_verifications
language plpgsql
security definer
set search_path = ''
as $$
declare
  created_request public.service_verifications;
  resolved_type_id uuid := p_service_type_id;
  resolved_custom text := nullif(trim(p_custom_name), '');
  scanned_at_temple boolean := false;
  devotee_name text;
  seva_name text;
begin
  if auth.uid() is null or not public.has_permission('services.participate') then
    raise exception 'Sign in to register seva.';
  end if;

  -- Registering is the busiest seva write, so it is also where finished
  -- verified seva is settled promptly rather than waiting for the nightly job.
  perform public.settle_finished_verified_seva();

  if not public.user_has_permission(p_verifier_id, 'services.manage_recurring') then
    raise exception 'Choose a Community Head, Tech Admin, or the President to verify this seva.';
  end if;

  if p_verifier_id = auth.uid() then
    raise exception 'Choose someone else to verify your seva.';
  end if;

  if nullif(trim(p_qr_token), '') is not null then
    select id into resolved_type_id
    from public.service_types
    where qr_token = trim(p_qr_token) and is_active;

    if resolved_type_id is null then
      raise exception 'This is not an active ISKCON Chicago seva QR code.';
    end if;
    resolved_custom := null;
    scanned_at_temple := true;
  end if;

  if (resolved_type_id is null) = (resolved_custom is null) then
    raise exception 'Choose a temple seva or enter one seva name.';
  end if;

  if resolved_type_id is not null and not scanned_at_temple and not exists (
    select 1 from public.service_types where id = resolved_type_id and is_active
  ) then
    raise exception 'The selected seva is not available.';
  end if;

  if p_end_at <= p_start_at
    or p_end_at > p_start_at + interval '12 hours'
  then
    raise exception 'Choose an end time within 12 hours of the start.';
  end if;

  -- Seva already finished cannot be registered. Anything still running or
  -- still ahead is fine, so a devotee can register before they begin.
  if p_end_at <= now() then
    raise exception 'That seva has already finished. Register seva for now or for a time ahead.';
  end if;

  if p_start_at > now() + interval '180 days' then
    raise exception 'Register seva within the next six months.';
  end if;

  insert into public.service_verifications (
    devotee_id, service_type_id, custom_name, start_at, end_at,
    location_text, verifier_id
  )
  values (
    auth.uid(), resolved_type_id, resolved_custom, p_start_at, p_end_at,
    coalesce(nullif(trim(p_location_text), ''), 'ISKCON Chicago Temple'),
    p_verifier_id
  )
  returning * into created_request;

  select name into devotee_name from public.users where id = auth.uid();
  seva_name := coalesce(
    (select name from public.service_types where id = created_request.service_type_id),
    created_request.custom_name
  );

  -- Only the named member is told.
  perform public.queue_app_notification(
    p_verifier_id,
    'seva_verification_requested',
    'Please verify a devotee''s seva',
    devotee_name || ' registered "' || seva_name || '" and asked you to verify it'
      || case when scanned_at_temple then ' (temple QR scanned).' else '.' end,
    jsonb_build_object('serviceVerificationId', created_request.id)
  );

  return created_request;
exception
  when unique_violation then
    raise exception 'You already registered this seva for that time.';
  when exclusion_violation then
    raise exception 'You already have seva registered that overlaps this time.';
end;
$$;

revoke all on function public.request_seva_verification(uuid, text, timestamptz, timestamptz, text, uuid, text) from public, anon;
grant execute on function public.request_seva_verification(uuid, text, timestamptz, timestamptz, text, uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Generation also settles finished verified seva.
-- ---------------------------------------------------------------------------

-- This is 0018's body with one line added at the top. Everything else — the
-- window validation, the conflict predicate, the standing-assignee insert that
-- skips full occurrences, and leaving participation_mode alone — is unchanged.
create or replace function public.generate_service_instances(
  p_days_ahead integer default 90
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

  -- Verified seva whose end time has now passed becomes finished history.
  perform public.settle_finished_verified_seva();

  for template_record in
    select * from public.service_templates
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
      where extract(dow from generated_day)::integer = any(template_record.days_of_week)
    loop
      instance_id := null;
      insert into public.service_instances (
        template_id, service_type_id, custom_name, date, start_time,
        duration_minutes, slots_needed, participation_mode, posted_by, status
      ) values (
        template_record.id, template_record.service_type_id,
        template_record.custom_name, scheduled_date,
        template_record.start_time, template_record.duration_minutes,
        template_record.slots_needed, template_record.participation_mode,
        null, 'open'
      ) on conflict (template_id, date) where template_id is not null do update set
        service_type_id = excluded.service_type_id,
        custom_name = excluded.custom_name,
        start_time = excluded.start_time,
        duration_minutes = excluded.duration_minutes,
        slots_needed = excluded.slots_needed
        -- participation_mode is deliberately NOT refreshed. An occurrence
        -- opened to everyone to find cover must stay open until the coverage
        -- request is resolved.
      returning id into instance_id;

      insert into public.service_assignments (
        service_instance_id, devotee_id, assignment_method, assigned_by,
        status, verification
      )
      select instance_id, assignees.devotee_id, 'recurring_assignment',
        assignees.assigned_by, 'confirmed', 'self_report'
      from public.service_template_assignees assignees
      where assignees.service_template_id = template_record.id
        and assignees.status = 'active'
        and extract(dow from scheduled_date)::integer = any(assignees.days_of_week)
        -- Never push a standing assignee onto an occurrence that is full.
        and (
          select count(*) from public.service_assignments existing
          where existing.service_instance_id = instance_id
            and existing.status in ('assigned', 'confirmed', 'completed')
            and existing.devotee_id <> assignees.devotee_id
        ) < template_record.slots_needed
      on conflict (service_instance_id, devotee_id) do nothing;

      perform public.refresh_service_instance_capacity(instance_id);
      generated_count := generated_count + 1;
    end loop;
  end loop;
  return generated_count;
end;
$$;

revoke all on function public.generate_service_instances(integer) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4. A second unavailability report no longer strands an outstanding ask.
--
--    The report re-stamps request_group_id on the occurrences it touches. Any
--    coverage plan or offer already sent for the old group then points at a
--    group with no pending exceptions, so the devotee holding it could only
--    ever be told 'this weekly seva has already been covered'. Those asks are
--    now withdrawn properly, and the devotee is told.
-- ---------------------------------------------------------------------------

create or replace function public.withdraw_superseded_coverage_asks(
  p_devotee_id uuid,
  p_instance_ids uuid[]
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  stale record;
  withdrawn integer := 0;
  seva_name text;
begin
  for stale in
    select distinct plans.id as plan_id, plans.substitute_devotee_id,
           plans.service_template_id, offers.id as offer_id
    from public.service_coverage_plans plans
    join public.service_exceptions exceptions
      on exceptions.request_group_id = plans.request_group_id
    left join public.service_offers offers
      on offers.service_coverage_plan_id = plans.id and offers.status = 'pending'
    where plans.status = 'pending'
      and plans.original_devotee_id = p_devotee_id
      and exceptions.service_instance_id = any(p_instance_ids)
  loop
    update public.service_coverage_plans
    set status = 'cancelled', responded_at = now()
    where id = stale.plan_id;

    if stale.offer_id is not null then
      update public.service_offers
      set status = 'expired', responded_at = now()
      where id = stale.offer_id;
    end if;

    select coalesce(service_types.name, templates.custom_name, 'a weekly seva')
    into seva_name
    from public.service_templates templates
    left join public.service_types on service_types.id = templates.service_type_id
    where templates.id = stale.service_template_id;

    perform public.queue_app_notification(
      stale.substitute_devotee_id, 'service_cancelled',
      'A coverage request was withdrawn',
      'The request to cover "' || seva_name
        || '" was withdrawn because the dates changed. Nothing is needed from you.',
      jsonb_build_object('serviceTemplateId', stale.service_template_id)
    );
    withdrawn := withdrawn + 1;
  end loop;

  return withdrawn;
end;
$$;

revoke all on function public.withdraw_superseded_coverage_asks(uuid, uuid[]) from public, anon, authenticated;

create or replace function public.report_weekly_service_unavailable(
  p_template_id uuid,
  p_scope text,
  p_date_from date,
  p_date_to date,
  p_days_of_week integer[],
  p_reason text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  template_record public.service_templates;
  request_group uuid := gen_random_uuid();
  selected_days integer[];
  selected_instance record;
  created_count integer := 0;
  first_exception uuid;
  devotee_name text;
  service_name text;
  effective_to date;
  touched_instances uuid[] := '{}';
begin
  if auth.uid() is null or not public.has_permission('services.report_unavailable') then
    raise exception 'You are not allowed to report weekly-seva unavailability.';
  end if;
  select * into template_record from public.service_templates
  where id = p_template_id and active for update;
  if template_record.id is null then raise exception 'This weekly seva is no longer active.'; end if;
  if p_scope not in ('occurrence', 'date_range', 'forever') then
    raise exception 'Choose one day, a date range, or from a date onward.';
  end if;
  selected_days := array(
    select distinct day_value
    from unnest(coalesce(p_days_of_week, '{}'::integer[])) day_value
    where day_value = any(template_record.days_of_week)
    order by day_value
  );
  if cardinality(selected_days) = 0 then
    raise exception 'Choose at least one scheduled weekday.';
  end if;
  if p_date_from < (now() at time zone 'America/Chicago')::date then
    raise exception 'Unavailability cannot begin in the past.';
  end if;
  if p_scope = 'occurrence' then
    p_date_to := p_date_from;
    selected_days := array[extract(dow from p_date_from)::integer];
  elsif p_scope = 'date_range' then
    if p_date_to is null or p_date_to < p_date_from
      or p_date_to > p_date_from + 180
    then raise exception 'Choose an end date within 180 days.'; end if;
  else
    p_date_to := null;
  end if;
  if not (extract(dow from p_date_from)::integer = any(template_record.days_of_week))
    and p_scope = 'occurrence'
  then raise exception 'The selected date is not part of this weekly seva.'; end if;

  perform public.generate_service_instances(180);
  effective_to := coalesce(p_date_to, p_date_from + 180);

  select coalesce(array_agg(instances.id), '{}')
  into touched_instances
  from public.service_instances instances
  join public.service_assignments assignments
    on assignments.service_instance_id = instances.id
   and assignments.devotee_id = auth.uid()
   and assignments.status in ('assigned', 'confirmed')
  where instances.template_id = template_record.id
    and instances.date between p_date_from and effective_to
    and extract(dow from instances.date)::integer = any(selected_days)
    and instances.status not in ('cancelled', 'completed');

  if cardinality(touched_instances) = 0 then
    raise exception 'No assigned weekly occurrences match those dates and days.';
  end if;

  -- Withdraw anything already asked of somebody for these same dates before
  -- the group id is re-stamped, so no one is left holding a dead request.
  perform public.withdraw_superseded_coverage_asks(auth.uid(), touched_instances);

  for selected_instance in
    select instances.id, instances.date
    from public.service_instances instances
    where instances.id = any(touched_instances)
    order by instances.date
  loop
    update public.service_assignments
    set status = 'withdrawn', completed_at = null
    where service_instance_id = selected_instance.id
      and devotee_id = auth.uid()
      and status in ('assigned', 'confirmed');

    insert into public.service_exceptions (
      service_instance_id, devotee_id, reason, status, resolution_kind,
      substitute_devotee_id, request_group_id, unavailable_scope,
      unavailable_from, unavailable_to, unavailable_days,
      resolved_at, resolved_by
    ) values (
      selected_instance.id, auth.uid(), nullif(trim(p_reason), ''),
      'pending', null, null, request_group, p_scope,
      p_date_from, p_date_to, selected_days, null, null
    ) on conflict (service_instance_id, devotee_id) do update set
      reason = excluded.reason, status = 'pending', resolution_kind = null,
      substitute_devotee_id = null,
      request_group_id = excluded.request_group_id,
      unavailable_scope = excluded.unavailable_scope,
      unavailable_from = excluded.unavailable_from,
      unavailable_to = excluded.unavailable_to,
      unavailable_days = excluded.unavailable_days,
      created_at = now(), resolved_at = null, resolved_by = null
    returning id into first_exception;
    created_count := created_count + 1;
    perform public.refresh_service_instance_capacity(selected_instance.id);
  end loop;

  if p_scope = 'forever' then
    update public.service_template_assignees
    set status = case
          when cardinality(array(
            select day_value from unnest(days_of_week) day_value
            where not (day_value = any(selected_days))
          )) = 0 then 'withdrawn'
          else 'active'
        end,
        days_of_week = case
          when cardinality(array(
            select day_value from unnest(days_of_week) day_value
            where not (day_value = any(selected_days))
          )) = 0 then selected_days
          else array(
            select day_value from unnest(days_of_week) day_value
            where not (day_value = any(selected_days)) order by day_value
          )
        end,
        updated_at = now()
    where service_template_id = template_record.id
      and devotee_id = auth.uid() and status = 'active';
  end if;

  select name into devotee_name from public.users where id = auth.uid();
  service_name := coalesce(
    (select name from public.service_types where id = template_record.service_type_id),
    template_record.custom_name, 'Temple seva'
  );
  perform public.notify_service_oversight(
    'service_coverage_needed', 'Weekly seva coverage needed',
    devotee_name || ' is unavailable for "' || service_name || '" ' ||
      case when p_scope = 'occurrence'
        then 'on ' || to_char(p_date_from, 'FMDay, FMMon FMDD') || '.'
        when p_scope = 'forever'
        then 'from ' || to_char(p_date_from, 'FMMon FMDD, YYYY') || ' onward.'
        else 'from ' || to_char(p_date_from, 'FMMon FMDD') || ' through ' ||
          to_char(p_date_to, 'FMMon FMDD, YYYY') || '.' end,
    jsonb_build_object(
      'serviceTemplateId', template_record.id,
      'serviceExceptionId', first_exception,
      'coverageRequestGroupId', request_group
    ), auth.uid()
  );
  return request_group;
end;
$$;

revoke all on function public.report_weekly_service_unavailable(uuid, text, date, date, integer[], text) from public, anon;
grant execute on function public.report_weekly_service_unavailable(uuid, text, date, date, integer[], text) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Accepting a weekly invitation respects each weekday's places.
--
--    The check counted assignees across the whole template while slots_needed
--    is per occurrence, so a Mon+Thu seva with one place refused a second
--    devotee outright — and when it did let someone in, it assigned them to
--    every future occurrence including ones already full.
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

-- ---------------------------------------------------------------------------
-- 6. Removing a seva request keeps what people actually did.
--
--    delete_service_requirement hard-deleted the occurrence, and the cascade
--    took every assignment with it. Devotees who had already completed that
--    seva lost it from their history with no way back. When there is history,
--    the occurrence is cancelled instead — the same rule delete_service_template
--    already follows.
-- ---------------------------------------------------------------------------

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
  has_history boolean;
begin
  select * into instance_record from public.service_instances
  where id = p_instance_id for update;
  if instance_record.id is null then raise exception 'This seva request was not found.'; end if;
  if not public.has_permission('services.delete_any')
    and (instance_record.posted_by is null or instance_record.posted_by <> auth.uid())
  then
    raise exception 'Only the poster, a Tech Admin, or the President can remove it.';
  end if;
  if instance_record.template_id is not null and not public.has_permission('services.delete_any') then
    raise exception 'Weekly occurrences are managed from the weekly seva.';
  end if;

  select exists (
    select 1 from public.service_assignments
    where service_instance_id = p_instance_id and status = 'completed'
  ) or exists (
    select 1 from public.service_qr_sessions
    where service_instance_id = p_instance_id and status = 'completed'
  ) into has_history;

  select name into actor_name from public.users where id = auth.uid();
  for participant in
    select distinct devotee_id from public.service_assignments
    where service_instance_id = p_instance_id and devotee_id <> auth.uid()
      and status <> 'completed'
  loop
    perform public.queue_app_notification(
      participant.devotee_id, 'service_deleted', 'A seva request was removed',
      actor_name || ' removed "' || public.service_instance_name(instance_record)
        || '" and the place you were holding.',
      jsonb_build_object('serviceInstanceId', p_instance_id)
    );
  end loop;

  update public.service_offers
  set status = 'expired', responded_at = now()
  where service_instance_id = p_instance_id and status = 'pending';

  if has_history then
    -- Somebody served this. Close it and keep what they did; only the places
    -- nobody completed are cleared.
    delete from public.service_assignments
    where service_instance_id = p_instance_id and status <> 'completed';
    delete from public.service_qr_sessions
    where service_instance_id = p_instance_id and status <> 'completed';
    update public.service_instances
    set status = 'cancelled' where id = p_instance_id;
  else
    delete from public.service_qr_sessions where service_instance_id = p_instance_id;
    delete from public.service_instances where id = p_instance_id;
  end if;
end;
$$;

revoke all on function public.delete_service_requirement(uuid) from public, anon;
grant execute on function public.delete_service_requirement(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 7. Asking somebody to cover: no duplicates, no dates in the past.
--
--    0009 rewrote this function and lost both guards, so the same devotee could
--    be asked repeatedly for the same dates and a coordinator could ask for
--    coverage of a day that had already gone.
-- ---------------------------------------------------------------------------

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
  selected_days integer[];
  service_name text;
  chicago_today date := (now() at time zone 'America/Chicago')::date;
begin
  if not public.has_permission('services.resolve_coverage') then
    raise exception 'Only a Community Head, Tech Admin, or the President can arrange weekly-seva coverage.';
  end if;
  select * into exception_record from public.service_exceptions
  where id = p_exception_id and status = 'pending' for update;
  if exception_record.id is null then raise exception 'This coverage request is no longer pending.'; end if;
  select * into instance_record from public.service_instances
  where id = exception_record.service_instance_id;
  if p_devotee_id = exception_record.devotee_id
    or not exists (select 1 from public.users where id = p_devotee_id)
  then raise exception 'Choose another active devotee for coverage.'; end if;
  if p_scope not in ('occurrence', 'date_range', 'forever') then
    raise exception 'Choose one day, all unavailable dates, or from now onward.';
  end if;

  if p_date_from is null or p_date_from < chicago_today then
    raise exception 'Coverage cannot start on a date that has already passed.';
  end if;

  if p_scope = 'occurrence' then
    p_date_to := p_date_from;
    selected_days := array[extract(dow from p_date_from)::integer];
    if not exists (
      select 1 from public.service_exceptions exceptions
      join public.service_instances instances on instances.id = exceptions.service_instance_id
      where exceptions.request_group_id = exception_record.request_group_id
        and exceptions.status = 'pending' and instances.date = p_date_from
    ) then raise exception 'That occurrence is not awaiting coverage.'; end if;
  else
    selected_days := exception_record.unavailable_days;
  end if;
  if p_scope = 'date_range' then
    if p_date_to is null or p_date_to < p_date_from then
      raise exception 'Choose a valid coverage date range.';
    end if;
  elsif p_scope = 'forever' then
    p_date_to := null;
  end if;

  -- One outstanding ask per devotee per coverage request. Asking twice left
  -- them with two invitations for the same dates and no way to tell them apart.
  if exists (
    select 1 from public.service_coverage_plans
    where request_group_id = exception_record.request_group_id
      and substitute_devotee_id = p_devotee_id
      and status = 'pending'
  ) then
    raise exception 'This devotee has already been asked and has not answered yet.';
  end if;

  insert into public.service_coverage_plans (
    service_exception_id, request_group_id, service_template_id,
    original_devotee_id, substitute_devotee_id, scope, date_from, date_to,
    days_of_week, created_by
  ) values (
    exception_record.id, exception_record.request_group_id,
    instance_record.template_id, exception_record.devotee_id,
    p_devotee_id, p_scope, p_date_from, p_date_to, selected_days, auth.uid()
  ) returning id into plan_id;
  insert into public.service_offers (
    service_instance_id, service_template_id, service_exception_id,
    service_coverage_plan_id, offered_to, offered_by, offer_kind, status
  ) values (
    null, instance_record.template_id, null, plan_id, p_devotee_id,
    auth.uid(), 'coverage_range', 'pending'
  ) returning id into offer_id;

  select name into coordinator_name from public.users where id = auth.uid();
  service_name := public.service_instance_name(instance_record);
  perform public.queue_app_notification(
    p_devotee_id, 'service_offer', 'Can you cover this weekly seva?',
    coordinator_name || ' is asking you to cover "' || service_name || '" ' ||
      case when p_scope = 'occurrence'
        then 'on ' || to_char(p_date_from, 'FMDay, FMMon FMDD') || '.'
        when p_scope = 'forever'
        then 'from ' || to_char(p_date_from, 'FMMon FMDD, YYYY') || ' onward.'
        else 'from ' || to_char(p_date_from, 'FMMon FMDD') || ' through ' ||
          to_char(p_date_to, 'FMMon FMDD, YYYY') || '.' end ||
      ' Please accept or decline.',
    jsonb_build_object(
      'serviceTemplateId', instance_record.template_id,
      'serviceCoveragePlanId', plan_id,
      'serviceOfferId', offer_id,
      'coverageRequestGroupId', exception_record.request_group_id
    )
  );
  return offer_id;
end;
$$;

revoke all on function public.offer_service_coverage_range(uuid, uuid, text, date, date) from public, anon;
grant execute on function public.offer_service_coverage_range(uuid, uuid, text, date, date) to authenticated;

-- ---------------------------------------------------------------------------
-- 8. Accepting coverage: fill only what has room, and tell everyone waiting.
--
--    The insert claimed every matching occurrence regardless of how many places
--    were already taken, and competing offers were expired in silence.
-- ---------------------------------------------------------------------------

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
  if offer_record.id is null or offer_record.offered_to <> auth.uid()
    or offer_record.status <> 'pending'
  then raise exception 'This weekly-seva offer is no longer available.'; end if;
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

-- ---------------------------------------------------------------------------
-- 9. Suggesting another time closes the coverage plan behind the invitation.
--
--    Countering set the offer to 'countered' but left the plan 'pending', so
--    the coordinator's screen showed a request still out with nobody on it,
--    and offer_service_coverage_range's duplicate guard would have refused to
--    ask anybody else.
-- ---------------------------------------------------------------------------

create or replace function public.propose_weekly_offer_alternative(
  p_offer_id uuid,
  p_days integer[],
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
  created_counter public.service_offer_counters;
  devotee_name text;
  template_name text;
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

  if target_offer.offer_kind not in ('recurring', 'coverage_range') then
    raise exception 'Only a weekly seva invitation can be answered with another time.';
  end if;

  if coalesce(cardinality(p_days), 0) = 0 then
    raise exception 'Choose at least one day you are available.';
  end if;

  if p_duration_minutes < 30 or p_duration_minutes > 720
    or p_duration_minutes % 30 <> 0
  then
    raise exception 'Duration must use 30-minute increments.';
  end if;

  insert into public.service_offer_counters (
    service_offer_id, devotee_id, proposed_days, proposed_start_time,
    proposed_duration_minutes, note
  )
  values (
    p_offer_id, auth.uid(), p_days, p_start_time, p_duration_minutes,
    nullif(trim(p_note), '')
  )
  returning * into created_counter;

  update public.service_offers
  set status = 'countered', responded_at = now()
  where id = p_offer_id;

  -- The plan behind a coverage invitation is settled too, so the coordinator
  -- is free to ask somebody else while this suggestion is considered.
  if target_offer.service_coverage_plan_id is not null then
    update public.service_coverage_plans
    set status = 'declined', responded_at = now()
    where id = target_offer.service_coverage_plan_id and status = 'pending';
  end if;

  select name into devotee_name from public.users where id = auth.uid();
  select coalesce(service_types.name, service_templates.custom_name)
  into template_name
  from public.service_templates
  left join public.service_types
    on service_types.id = service_templates.service_type_id
  where service_templates.id = target_offer.service_template_id;

  perform public.queue_app_notification(
    target_offer.offered_by,
    'weekly_offer_countered',
    'A devotee suggested another time',
    devotee_name || ' cannot take "' || coalesce(template_name, 'the weekly seva')
      || '" as offered, and suggested a different day and time.',
    jsonb_build_object(
      'serviceOfferId', p_offer_id,
      'serviceOfferCounterId', created_counter.id,
      'serviceTemplateId', target_offer.service_template_id
    )
  );

  return created_counter;
exception
  when unique_violation then
    raise exception 'You already suggested another time for this invitation.';
end;
$$;

revoke all on function public.propose_weekly_offer_alternative(uuid, integer[], time, integer, text) from public, anon;
grant execute on function public.propose_weekly_offer_alternative(uuid, integer[], time, integer, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 10. Opening coverage to the community, and closing it when somebody steps up.
--
--     reopen_service_exception told every user in the temple, including people
--     who cannot take weekly seva, and nothing ever resolved the exception when
--     a devotee actually joined the opened occurrence. The original devotee was
--     never told their seva was covered.
-- ---------------------------------------------------------------------------

create or replace function public.reopen_service_exception(p_exception_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  exception_record public.service_exceptions;
  template_record public.service_templates;
  service_name text;
begin
  if not public.has_permission('services.resolve_coverage') then
    raise exception 'Only a Community Head, Tech Admin, or the President can arrange weekly-seva coverage.';
  end if;
  select * into exception_record from public.service_exceptions
  where id = p_exception_id and status = 'pending' for update;
  if exception_record.id is null then raise exception 'This coverage request is no longer pending.'; end if;

  update public.service_exceptions
  set resolution_kind = 'broadcast'
  where request_group_id = exception_record.request_group_id
    and status = 'pending';
  update public.service_instances instances
  set participation_mode = 'open', status = 'open'
  from public.service_exceptions exceptions
  where exceptions.request_group_id = exception_record.request_group_id
    and exceptions.status = 'pending'
    and instances.id = exceptions.service_instance_id
    and instances.status not in ('cancelled', 'completed');

  select templates.* into template_record
  from public.service_templates templates
  join public.service_instances instances on instances.template_id = templates.id
  where instances.id = exception_record.service_instance_id;
  service_name := coalesce(
    (select name from public.service_types where id = template_record.service_type_id),
    template_record.custom_name, 'Temple seva'
  );

  -- Only devotees who can actually take seva are told, and not the person who
  -- reported the unavailability.
  insert into public.app_notifications (user_id, kind, title, body, data)
  select users.id, 'service_open', 'Weekly seva needs help',
    'Open weekly-seva dates are available for "' || service_name || '".',
    jsonb_build_object(
      'serviceTemplateId', template_record.id,
      'serviceExceptionId', exception_record.id,
      'coverageRequestGroupId', exception_record.request_group_id,
      'weeklyOpen', true
    )
  from public.users
  where users.id <> exception_record.devotee_id
    and public.user_has_permission(users.id, 'services.participate');

  perform public.queue_app_notification(
    exception_record.devotee_id, 'service_coverage_needed',
    'Your seva was opened to the community',
    'Your dates for "' || service_name
      || '" are now open for any devotee to pick up.',
    jsonb_build_object(
      'serviceTemplateId', template_record.id,
      'coverageRequestGroupId', exception_record.request_group_id
    )
  );
end;
$$;

revoke all on function public.reopen_service_exception(uuid) from public, anon;
grant execute on function public.reopen_service_exception(uuid) to authenticated;

-- Somebody picking up an opened date already closed the coverage request, via
-- this trigger — but in complete silence. The devotee who needed cover, the
-- coordinators arranging it, and anyone still holding an invitation for the
-- same date all learned nothing. Notifying here rather than in one RPC covers
-- every path that can fill the place: self-join, accepted invitation, and a
-- standing assignee returning.
create or replace function public.resolve_broadcast_exception_after_assignment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  resolved_exception public.service_exceptions;
  instance_record public.service_instances;
  lapsed record;
  seva_name text;
  devotee_name text;
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
  returning * into resolved_exception;

  if resolved_exception.id is null then
    return new;
  end if;

  select * into instance_record from public.service_instances
  where id = new.service_instance_id;
  seva_name := public.service_instance_name(instance_record);
  select name into devotee_name from public.users where id = new.devotee_id;

  for lapsed in
    select id, offered_to from public.service_offers
    where service_exception_id = resolved_exception.id and status = 'pending'
  loop
    update public.service_offers
    set status = 'expired', responded_at = now() where id = lapsed.id;
    perform public.queue_app_notification(
      lapsed.offered_to, 'service_offer_response', 'This seva has been covered',
      '"' || seva_name || '" is covered, so nothing is needed from you.',
      jsonb_build_object('serviceInstanceId', new.service_instance_id)
    );
  end loop;

  perform public.queue_app_notification(
    resolved_exception.devotee_id, 'service_coverage_resolved',
    'Your seva is covered',
    coalesce(devotee_name, 'A devotee') || ' picked up "' || seva_name || '" for you.',
    jsonb_build_object('serviceInstanceId', new.service_instance_id)
  );

  perform public.notify_service_oversight(
    'service_coverage_resolved', 'Weekly seva coverage filled',
    coalesce(devotee_name, 'A devotee') || ' picked up an open date for "'
      || seva_name || '".',
    jsonb_build_object(
      'serviceInstanceId', new.service_instance_id,
      'coverageRequestGroupId', resolved_exception.request_group_id
    ),
    new.devotee_id
  );

  return new;
end;
$$;

revoke all on function public.resolve_broadcast_exception_after_assignment()
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 11. The last live-timer RPC left reachable.
--
--     0013 retired the timer and 0018 swept the rest, but this one kept its
--     grant. Nothing in the app calls it; a client could still drive it.
-- ---------------------------------------------------------------------------

do $$
declare
  retired record;
begin
  for retired in
    select pg_proc.oid::regprocedure as signature
    from pg_proc
    join pg_namespace on pg_namespace.oid = pg_proc.pronamespace
    where pg_namespace.nspname = 'public'
      and pg_proc.proname in (
        'complete_due_service_sessions', 'cancel_service_session'
      )
  loop
    execute format(
      'revoke all on function %s from public, anon, authenticated',
      retired.signature
    );
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- 12. Access requests were completely silent.
--
--     A devotee asked to become a Volunteer and nobody was told; it was
--     approved and they were never told either. Access level is what decides
--     what a devotee may do in the Seva tab, so both ends now get a message.
-- ---------------------------------------------------------------------------

-- The names devotees actually see. Kept in step with accessRoleLabels in
-- src/features/access/model.ts.
create or replace function public.access_level_label(p_role_name text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case p_role_name
    when 'president' then 'President'
    when 'tech' then 'Tech Admin'
    when 'core' then 'Community Head'
    when 'volunteer' then 'Volunteer'
    when 'devotee' then 'Devotee'
    else coalesce(p_role_name, 'a member')
  end
$$;

revoke all on function public.access_level_label(text) from public, anon;
grant execute on function public.access_level_label(text) to authenticated;

alter table public.app_notifications
  drop constraint if exists app_notifications_kind_check;

alter table public.app_notifications
  add constraint app_notifications_kind_check check (
    kind in (
      'service_open', 'service_offer', 'service_recurring_offer',
      'service_offer_response', 'service_joined', 'service_left',
      'service_started', 'service_completed', 'service_cancelled',
      'service_deleted', 'service_coverage_needed',
      'service_coverage_resolved', 'recurring_interest_submitted',
      'recurring_interest_reviewed',
      'seva_verification_requested', 'seva_verification_reviewed',
      'weekly_offer_countered', 'weekly_offer_counter_reviewed',
      'access_request_submitted', 'access_request_reviewed',
      'remote'
    )
  );

create or replace function public.create_access_request(requested_role_name text)
returns public.access_requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  requested_role public.roles;
  created_request public.access_requests;
  requester_name text;
  reviewer record;
begin
  if auth.uid() is null then
    raise exception 'Authentication is required.';
  end if;

  select * into requested_role
  from public.roles
  where name = requested_role_name;

  if requested_role.id is null
    or not public.can_request_access_role(auth.uid(), requested_role.id)
  then
    raise exception 'This access-level change is not allowed.';
  end if;

  insert into public.access_requests (requester_id, requested_role_id)
  values (auth.uid(), requested_role.id)
  returning * into created_request;

  select name into requester_name from public.users where id = auth.uid();

  for reviewer in
    select distinct users.id
    from public.users
    join public.role_permissions
      on role_permissions.role_id = users.role_id
     and role_permissions.permission_key = 'access.review_requests'
    where users.id <> auth.uid()
  loop
    perform public.queue_app_notification(
      reviewer.id, 'access_request_submitted', 'A devotee asked for more access',
      coalesce(requester_name, 'A devotee') || ' asked to become '
        || public.access_level_label(requested_role.name) || '.',
      jsonb_build_object('accessRequestId', created_request.id)
    );
  end loop;

  return created_request;
exception
  when unique_violation then
    raise exception 'You already have a pending access request.';
end;
$$;

revoke all on function public.create_access_request(text) from public, anon;
grant execute on function public.create_access_request(text) to authenticated;

create or replace function public.review_access_request(
  access_request_id uuid,
  decision text
)
returns public.access_requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  pending_request public.access_requests;
  reviewed_request public.access_requests;
  reviewer_name text;
  role_label text;
begin
  if not public.has_permission('access.review_requests') then
    raise exception 'Only the President or a Tech Admin can review access requests.';
  end if;

  if decision not in ('approved', 'denied') then
    raise exception 'Decision must be approved or denied.';
  end if;

  select * into pending_request
  from public.access_requests
  where id = access_request_id
  for update;

  if pending_request.id is null or pending_request.status <> 'pending' then
    raise exception 'This access request is no longer pending.';
  end if;

  if decision = 'approved' then
    update public.users
    set role_id = pending_request.requested_role_id
    where id = pending_request.requester_id;
  end if;

  update public.access_requests
  set
    status = decision,
    reviewed_at = now(),
    reviewed_by = auth.uid()
  where id = pending_request.id
  returning * into reviewed_request;

  select name into reviewer_name from public.users where id = auth.uid();
  select public.access_level_label(roles.name) into role_label
  from public.roles where roles.id = pending_request.requested_role_id;

  if pending_request.requester_id <> auth.uid() then
    perform public.queue_app_notification(
      pending_request.requester_id, 'access_request_reviewed',
      case when decision = 'approved'
        then 'Your access level changed'
        else 'Your access request was not approved' end,
      case when decision = 'approved'
        then coalesce(reviewer_name, 'A reviewer') || ' made you '
             || role_label || '.'
        else coalesce(reviewer_name, 'A reviewer')
             || ' did not approve your request to become ' || role_label || '.'
      end,
      jsonb_build_object('accessRequestId', reviewed_request.id)
    );
  end if;

  return reviewed_request;
end;
$$;

revoke all on function public.review_access_request(uuid, text) from public, anon;
grant execute on function public.review_access_request(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 14. Editing a weekly seva's dates actually moves its dates.
--
--     The new start_date and end_date were written to the template, but only
--     occurrences on dropped weekdays were pruned. Shortening a run left every
--     date past the new end still scheduled, with people standing on them.
--     Those dates are now dropped by the same rule: removed if nobody is
--     attached, cancelled if somebody is, and the devotees are told.
-- ---------------------------------------------------------------------------

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
  new_days integer[];
  dropped record;
  affected record;
begin
  if not public.has_permission('services.manage_recurring') then
    raise exception 'Only a Community Head, Tech Admin, or the President can update weekly seva.';
  end if;
  if cardinality(p_days_of_week) < 1 or not p_days_of_week <@ array[0,1,2,3,4,5,6] then
    raise exception 'Choose at least one valid weekday.';
  end if;
  if (p_service_type_id is null) = (length(trim(coalesce(p_custom_name, ''))) < 2) then
    raise exception 'Choose one seva or type a meaningful seva name.';
  end if;
  if p_slots_needed < 1 or p_slots_needed > 100 then
    raise exception 'Places needed must be between 1 and 100.';
  end if;

  new_days := (select array_agg(distinct day order by day) from unnest(p_days_of_week) day);

  update public.service_templates set
    service_type_id = p_service_type_id,
    custom_name = nullif(trim(p_custom_name), ''),
    day_of_week = new_days[1],
    days_of_week = new_days,
    start_time = p_start_time,
    duration_minutes = p_duration_minutes,
    slots_needed = p_slots_needed,
    participation_mode = p_participation_mode,
    start_date = p_start_date,
    end_date = p_end_date,
    updated_at = now()
  where id = p_template_id;
  if not found then raise exception 'This weekly seva was not found.'; end if;

  select name into coordinator_name from public.users where id = auth.uid();
  select coalesce(service_types.name, templates.custom_name) into seva_name
  from public.service_templates templates
  left join public.service_types on service_types.id = templates.service_type_id
  where templates.id = p_template_id;

  -- A standing assignee must not remain scheduled on a weekday the seva no
  -- longer runs. Anyone left with no days at all steps down.
  update public.service_template_assignees
  set days_of_week = array(
        select day_value from unnest(days_of_week) day_value
        where day_value = any(new_days) order by day_value
      ),
      updated_at = now()
  where service_template_id = p_template_id
    and status = 'active'
    and not (days_of_week <@ new_days);

  for affected in
    select devotee_id from public.service_template_assignees
    where service_template_id = p_template_id
      and status = 'active'
      and cardinality(days_of_week) = 0
      and devotee_id <> auth.uid()
  loop
    perform public.queue_app_notification(
      affected.devotee_id, 'service_deleted', 'A weekly seva day was removed',
      coordinator_name || ' changed "' || coalesce(seva_name, 'a weekly seva')
        || '" and the day you were serving is no longer scheduled.',
      jsonb_build_object('serviceTemplateId', p_template_id)
    );
  end loop;

  update public.service_template_assignees
  set status = 'withdrawn', updated_at = now()
  where service_template_id = p_template_id
    and status = 'active'
    and cardinality(days_of_week) = 0;

  -- Occurrences on a weekday that is no longer scheduled. Anything nobody is
  -- attached to is removed; anything with people or an open coverage question
  -- is cancelled instead, so assignments, unavailability reports and coverage
  -- plans survive and stay visible.
  for dropped in
    select instances.id, instances.date
    from public.service_instances instances
    where instances.template_id = p_template_id
      and instances.date >= (now() at time zone 'America/Chicago')::date
      and instances.status not in ('completed', 'cancelled')
      and (
        not (extract(dow from instances.date)::integer = any(new_days))
        -- Shortening the run left every date outside the new window live, so
        -- devotees kept seeing and serving a seva that no longer runs then.
        or instances.date < p_start_date
        or (p_end_date is not null and instances.date > p_end_date)
      )
  loop
    if exists (
      select 1 from public.service_assignments
      where service_instance_id = dropped.id
        and status in ('assigned', 'confirmed', 'completed')
    ) or exists (
      select 1 from public.service_exceptions
      where service_instance_id = dropped.id and status = 'pending'
    ) then
      update public.service_instances
      set status = 'cancelled' where id = dropped.id;

      for affected in
        select distinct devotee_id from public.service_assignments
        where service_instance_id = dropped.id
          and status in ('assigned', 'confirmed')
          and devotee_id <> auth.uid()
      loop
        perform public.queue_app_notification(
          affected.devotee_id, 'service_cancelled', 'A weekly seva date was cancelled',
          coordinator_name || ' changed "' || coalesce(seva_name, 'a weekly seva')
            || '", so ' || to_char(dropped.date, 'FMDay, FMMonth FMDD')
            || ' is no longer scheduled.',
          jsonb_build_object('serviceInstanceId', dropped.id)
        );
      end loop;
    else
      delete from public.service_instances where id = dropped.id;
    end if;
  end loop;

  for invitee_id in select distinct unnest(coalesce(p_invitee_ids, '{}'::uuid[]))
  loop
    if invitee_id = auth.uid() then continue; end if;
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
        invitee_id, 'service_recurring_offer', 'A weekly seva invitation',
        coordinator_name || ' is asking if you can help with "'
          || coalesce(seva_name, 'a weekly seva') || '".',
        jsonb_build_object('serviceTemplateId', p_template_id, 'serviceOfferId', offer_id)
      );
    end if;
  end loop;

  -- 180 days, matching every other generation call. 56 left the calendar
  -- short whenever a coordinator extended the run.
  perform public.generate_service_instances(180);
end;
$$;

revoke all on function public.update_service_template_v2(uuid, uuid, text, integer[], time, integer, integer, text, date, date, uuid[]) from public, anon;
grant execute on function public.update_service_template_v2(uuid, uuid, text, integer[], time, integer, integer, text, date, date, uuid[]) to authenticated;

-- ---------------------------------------------------------------------------
-- 15. Keep the rolling generation job honest about settling verified seva.
-- ---------------------------------------------------------------------------

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    if exists (select 1 from cron.job where jobname = 'generate-weekly-seva-instances') then
      perform cron.unschedule('generate-weekly-seva-instances');
    end if;
    perform cron.schedule(
      'generate-weekly-seva-instances', '15 2 * * *',
      'select public.generate_service_instances(90);'
    );
  end if;
end;
$$;

do $$
begin
  raise notice 'seva completeness applied';
end;
$$;
