-- Notifications name a weekday, a date and a clock time.
--
-- Coverage messages read "from Aug 5 through Aug 5, 2026" — no weekday, no
-- hour — so a devotee being asked to cover could not tell when they were
-- needed without opening the app and hunting for it. Three helpers below build
-- one consistent phrase, and every notification that names a date uses them.
-- Requires 202608040020_seva_completeness.sql.

-- "Tuesday and Thursday", or "Monday, Wednesday and Friday".
create or replace function public.format_weekday_list(p_days integer[])
returns text
language sql
immutable
set search_path = ''
as $$
  with names as (
    select to_char(date '2024-01-07' + day_value, 'FMDay') as label
    from unnest(coalesce(p_days, '{}'::integer[])) as day_value
    where day_value between 0 and 6
    order by day_value
  ), listed as (
    select array_agg(label) as labels from names
  )
  select case
    when labels is null or cardinality(labels) = 0 then null
    when cardinality(labels) = 1 then labels[1]
    else array_to_string(labels[1:cardinality(labels) - 1], ', ')
         || ' and ' || labels[cardinality(labels)]
  end
  from listed
$$;

revoke all on function public.format_weekday_list(integer[]) from public, anon;
grant execute on function public.format_weekday_list(integer[]) to authenticated;

-- "Tuesday, August 5 at 6:00 PM".
create or replace function public.format_seva_when(
  p_date date,
  p_start_time time
)
returns text
language sql
immutable
set search_path = ''
as $$
  select to_char(p_date, 'FMDay, FMMonth FMDD')
    || case when p_start_time is null then ''
            else ' at ' || to_char(p_start_time, 'FMHH12:MI AM') end
$$;

revoke all on function public.format_seva_when(date, time) from public, anon;
grant execute on function public.format_seva_when(date, time) to authenticated;

-- The whole "when" phrase for a coverage request, without a trailing stop, so
-- callers can follow it with a sentence.
create or replace function public.format_seva_period(
  p_scope text,
  p_date_from date,
  p_date_to date,
  p_days integer[],
  p_start_time time
)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_scope = 'occurrence' or p_date_to = p_date_from
      then 'on ' || public.format_seva_when(p_date_from, p_start_time)
    when p_scope = 'forever'
      then 'every ' || coalesce(
             public.format_weekday_list(p_days),
             to_char(p_date_from, 'FMDay')
           )
           || case when p_start_time is null then ''
                   else ' at ' || to_char(p_start_time, 'FMHH12:MI AM') end
           || ', from ' || to_char(p_date_from, 'FMMonth FMDD, YYYY') || ' onward'
    else 'every ' || coalesce(
           public.format_weekday_list(p_days),
           to_char(p_date_from, 'FMDay')
         )
         || case when p_start_time is null then ''
                 else ' at ' || to_char(p_start_time, 'FMHH12:MI AM') end
         || ', from ' || to_char(p_date_from, 'FMMonth FMDD')
         || ' through ' || to_char(p_date_to, 'FMMonth FMDD, YYYY')
  end
$$;

revoke all on function public.format_seva_period(text, date, date, integer[], time) from public, anon;
grant execute on function public.format_seva_period(text, date, date, integer[], time) to authenticated;


-- ---------------------------------------------------------------------------
-- Reporting unavailability now says which weekday and what time.
-- ---------------------------------------------------------------------------

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
    devotee_name || ' is unavailable for "' || service_name || '" '
      || public.format_seva_period(
           p_scope, p_date_from, p_date_to, selected_days, template_record.start_time
         ) || '.',
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
-- The coverage ask itself. This is the message a devotee acts on, so it
-- carries the weekday, the date and the hour.
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
    coordinator_name || ' is asking you to cover "' || service_name || '" '
      || public.format_seva_period(
           p_scope, p_date_from, p_date_to, selected_days, instance_record.start_time
         )
      || '. Please accept or decline.',
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
-- Cancelling a seva names the hour too, so a devotee with two seva on the
-- same day knows which one is off.
-- ---------------------------------------------------------------------------

create or replace function public.cancel_service_instance(p_instance_id uuid)
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

  if instance_record.id is null
    or instance_record.status in ('completed', 'cancelled')
  then
    raise exception 'This service can no longer be cancelled.';
  end if;

  if instance_record.posted_by is distinct from auth.uid()
    and not public.has_permission('services.manage_recurring')
  then
    raise exception 'You are not allowed to cancel this service.';
  end if;

  insert into public.app_notifications (user_id, kind, title, body, data)
  select
    service_assignments.devotee_id,
    'service_cancelled',
    'Service cancelled',
    '"' || public.service_instance_name(instance_record) || '" on '
      || public.format_seva_when(instance_record.date, instance_record.start_time)
      || ' has been cancelled.',
    jsonb_build_object('serviceInstanceId', instance_record.id)
  from public.service_assignments
  where service_assignments.service_instance_id = instance_record.id
    and service_assignments.status in ('assigned', 'confirmed')
    and service_assignments.devotee_id <> auth.uid();

  update public.service_instances
  set status = 'cancelled'
  where id = p_instance_id;

  update public.service_assignments
  set status = 'withdrawn'
  where service_instance_id = p_instance_id
    and status in ('assigned', 'confirmed');

  update public.service_offers
  set status = 'expired', responded_at = now()
  where service_instance_id = p_instance_id
    and status = 'pending';
end;
$$;

-- Deliberately internal since 0010: cancelling runs through
-- delete_service_requirement and the weekly paths, never straight from a
-- client. The grant is not restored.
revoke all on function public.cancel_service_instance(uuid) from public, anon, authenticated;


-- ---------------------------------------------------------------------------
-- A weekly date that is dropped says which sitting it was.
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
    select instances.id, instances.date, instances.start_time
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
            || '", so ' || public.format_seva_when(dropped.date, dropped.start_time)
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


do $$
begin
  raise notice 'seva notification wording applied';
end;
$$;
