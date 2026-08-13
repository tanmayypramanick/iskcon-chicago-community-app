-- Weekly-seva information architecture, volunteer visibility, grouped
-- unavailability, day-specific standing assignments, and secure self-join.
-- Requires 202608030008_service_operations_and_reports.sql.

-- A volunteer can post an open need and participate, but is not a schedule or
-- activity coordinator. Devotees retain the community schedule requested for
-- the general community experience; Core, Tech, and President retain it too.
delete from public.role_permissions
where role_id = (select id from public.roles where name = 'volunteer')
  and permission_key in (
    'services.view_all',
    'services.offer_assignment',
    'services.oversee_activity',
    'services.complete_requirement',
    'services.resolve_coverage',
    'services.manage_recurring',
    'services.export_reports',
    'services.delete_any'
  );

create or replace function public.enforce_service_need_access()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.posted_by = auth.uid()
    and new.participation_mode <> 'open'
    and not public.has_permission('services.offer_assignment')
  then
    raise exception 'Your access level can post open service needs only.';
  end if;
  return new;
end;
$$;

drop trigger if exists enforce_service_need_access on public.service_instances;
create trigger enforce_service_need_access
before insert or update of participation_mode on public.service_instances
for each row execute function public.enforce_service_need_access();

-- A multi-day weekly template needs day-specific standing assignees so a
-- devotee can be unavailable on Monday without losing Thursday and Saturday.
alter table public.service_template_assignees
  add column if not exists days_of_week integer[];

update public.service_template_assignees assignees
set days_of_week = templates.days_of_week
from public.service_templates templates
where templates.id = assignees.service_template_id
  and assignees.days_of_week is null;

alter table public.service_template_assignees
  alter column days_of_week set not null,
  add constraint service_template_assignee_days_check check (
    cardinality(days_of_week) between 1 and 7
    and days_of_week <@ array[0,1,2,3,4,5,6]
  );

create or replace function public.fill_weekly_assignee_days()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.days_of_week is null or cardinality(new.days_of_week) = 0 then
    select days_of_week into new.days_of_week
    from public.service_templates
    where id = new.service_template_id;
  end if;
  return new;
end;
$$;

drop trigger if exists fill_weekly_assignee_days
  on public.service_template_assignees;
create trigger fill_weekly_assignee_days
before insert or update of service_template_id, days_of_week
on public.service_template_assignees
for each row execute function public.fill_weekly_assignee_days();

-- One user submission may cover one day, selected days in a range, or selected
-- weekdays from a date onward. Individual occurrence rows remain atomic while
-- request_group_id lets the app show one understandable coverage request.
alter table public.service_exceptions
  add column if not exists request_group_id uuid default gen_random_uuid(),
  add column if not exists unavailable_scope text default 'occurrence',
  add column if not exists unavailable_from date,
  add column if not exists unavailable_to date,
  add column if not exists unavailable_days integer[];

update public.service_exceptions exceptions
set request_group_id = coalesce(exceptions.request_group_id, gen_random_uuid()),
    unavailable_scope = coalesce(exceptions.unavailable_scope, 'occurrence'),
    unavailable_from = coalesce(exceptions.unavailable_from, instances.date),
    unavailable_to = coalesce(exceptions.unavailable_to, instances.date),
    unavailable_days = coalesce(
      exceptions.unavailable_days,
      array[extract(dow from instances.date)::integer]
    )
from public.service_instances instances
where instances.id = exceptions.service_instance_id;

alter table public.service_exceptions
  alter column request_group_id set not null,
  alter column unavailable_scope set not null,
  alter column unavailable_from set not null,
  alter column unavailable_days set not null,
  add constraint service_exception_unavailable_scope_check check (
    unavailable_scope in ('occurrence', 'date_range', 'forever')
  ),
  add constraint service_exception_unavailable_days_check check (
    cardinality(unavailable_days) between 1 and 7
    and unavailable_days <@ array[0,1,2,3,4,5,6]
  ),
  add constraint service_exception_unavailable_dates_check check (
    (unavailable_scope = 'forever' and unavailable_to is null)
    or
    (unavailable_scope <> 'forever' and unavailable_to is not null
      and unavailable_to >= unavailable_from)
  );

create index if not exists service_exceptions_group_status_idx
  on public.service_exceptions(request_group_id, status, created_at);

alter table public.service_coverage_plans
  add column if not exists request_group_id uuid,
  add column if not exists days_of_week integer[];

update public.service_coverage_plans plans
set request_group_id = exceptions.request_group_id,
    days_of_week = exceptions.unavailable_days
from public.service_exceptions exceptions
where exceptions.id = plans.service_exception_id
  and (plans.request_group_id is null or plans.days_of_week is null);

alter table public.service_coverage_plans
  alter column request_group_id set not null,
  alter column days_of_week set not null,
  add constraint service_coverage_plan_days_check check (
    cardinality(days_of_week) between 1 and 7
    and days_of_week <@ array[0,1,2,3,4,5,6]
  );

create index if not exists service_coverage_plans_group_status_idx
  on public.service_coverage_plans(request_group_id, status, date_from);

-- Generated occurrences respect the weekdays owned by each standing devotee.
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
        slots_needed = excluded.slots_needed,
        participation_mode = excluded.participation_mode
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
      on conflict (service_instance_id, devotee_id) do nothing;

      perform public.refresh_service_instance_capacity(instance_id);
      generated_count := generated_count + 1;
    end loop;
  end loop;
  return generated_count;
end;
$$;

-- Secure helpers keep volunteer schedule filtering in RLS, not only React.
create or replace function public.can_view_service_instance(p_instance_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.service_instances instances
    where instances.id = p_instance_id
      and (
        public.has_permission('services.view_all')
        or instances.posted_by = auth.uid()
        or (
          instances.status = 'open'
          and instances.participation_mode = 'open'
        )
        or exists (
          select 1 from public.service_assignments assignments
          where assignments.service_instance_id = instances.id
            and assignments.devotee_id = auth.uid()
            and assignments.status in ('assigned', 'confirmed', 'completed')
        )
        or exists (
          select 1 from public.service_offers offers
          where offers.service_instance_id = instances.id
            and offers.offered_to = auth.uid()
            and offers.status = 'pending'
        )
      )
  );
$$;

create or replace function public.can_view_service_template(p_template_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.service_templates templates
    where templates.id = p_template_id
      and (
        public.has_permission('services.view_all')
        or templates.created_by = auth.uid()
        or exists (
          select 1 from public.service_template_assignees assignees
          where assignees.service_template_id = templates.id
            and assignees.devotee_id = auth.uid()
            and assignees.status = 'active'
        )
        or exists (
          select 1 from public.service_offers offers
          where offers.service_template_id = templates.id
            and offers.offered_to = auth.uid()
            and offers.status = 'pending'
        )
        or (
          templates.active
          and templates.participation_mode = 'open'
          and exists (
            select 1 from unnest(templates.days_of_week) scheduled_day
            where (
              select count(*)
              from public.service_template_assignees assignees
              where assignees.service_template_id = templates.id
                and assignees.status = 'active'
                and scheduled_day = any(assignees.days_of_week)
            ) < templates.slots_needed
          )
        )
        or exists (
          select 1
          from public.service_exceptions exceptions
          join public.service_instances instances
            on instances.id = exceptions.service_instance_id
          where instances.template_id = templates.id
            and exceptions.status = 'pending'
            and exceptions.resolution_kind = 'broadcast'
        )
      )
  );
$$;

drop policy if exists "Authenticated users can read service schedules"
  on public.service_instances;
create policy "Users can read permitted seva schedules"
  on public.service_instances for select to authenticated
  using (public.can_view_service_instance(id));

drop policy if exists "Authenticated users can read recurring service templates"
  on public.service_templates;
create policy "Users can read permitted weekly seva templates"
  on public.service_templates for select to authenticated
  using (public.can_view_service_template(id));

drop policy if exists "Users can read permitted service participation"
  on public.service_assignments;
create policy "Users can read permitted service participation"
  on public.service_assignments for select to authenticated
  using (
    devotee_id = auth.uid()
    or public.has_permission('services.oversee_activity')
    or public.can_view_service_instance(service_instance_id)
  );

drop policy if exists "Users and recurring coordinators can read recurring assignees"
  on public.service_template_assignees;
drop policy if exists "Authenticated users can read recurring assignees"
  on public.service_template_assignees;
create policy "Users can read permitted weekly seva assignees"
  on public.service_template_assignees for select to authenticated
  using (
    devotee_id = auth.uid()
    or public.has_permission('services.manage_recurring')
    or public.has_permission('services.view_all')
    or public.can_view_service_template(service_template_id)
  );

-- Open requirements remain self-joinable for everyone. A coordinator or the
-- person who posted an invite-only need can also assign themselves directly.
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
  if auth.uid() is null or not public.has_permission('services.participate') then
    raise exception 'Sign in to join this seva.';
  end if;
  select * into instance_record from public.service_instances
  where id = p_instance_id for update;
  if instance_record.id is null then raise exception 'This seva could not be found.'; end if;
  if instance_record.status <> 'open' then raise exception 'This seva is not open.'; end if;
  if instance_record.participation_mode <> 'open'
    and instance_record.posted_by is distinct from auth.uid()
    and not public.has_permission('services.offer_assignment')
  then raise exception 'This invite-only seva is not open for self-assignment.'; end if;

  select count(*) into filled_slots from public.service_assignments
  where service_instance_id = p_instance_id
    and status in ('assigned', 'confirmed', 'completed')
    and devotee_id <> auth.uid();
  if filled_slots >= instance_record.slots_needed then
    perform public.refresh_service_instance_capacity(p_instance_id);
    raise exception 'This seva is already full.';
  end if;

  insert into public.service_assignments (
    service_instance_id, devotee_id, assignment_method, assigned_by,
    status, verification
  ) values (
    p_instance_id, auth.uid(), 'self_joined', auth.uid(),
    'confirmed', 'self_report'
  ) on conflict (service_instance_id, devotee_id) do update set
    assignment_method = 'self_joined', assigned_by = auth.uid(),
    status = 'confirmed', verification = 'self_report', completed_at = null
  returning * into joined_assignment;
  perform public.refresh_service_instance_capacity(p_instance_id);

  select name into devotee_name from public.users where id = auth.uid();
  if instance_record.posted_by is not null and instance_record.posted_by <> auth.uid() then
    perform public.queue_app_notification(
      instance_record.posted_by, 'service_joined', 'A devotee joined your seva',
      devotee_name || ' joined "' || public.service_instance_name(instance_record) || '".',
      jsonb_build_object('serviceInstanceId', p_instance_id)
    );
  end if;
  return joined_assignment;
end;
$$;

-- Join an open standing weekly seva once; generated occurrences inherit it.
create or replace function public.join_weekly_service(p_template_id uuid)
returns public.service_template_assignees
language plpgsql
security definer
set search_path = ''
as $$
declare
  template_record public.service_templates;
  joined_assignee public.service_template_assignees;
  joinable_days integer[];
  devotee_name text;
  service_name text;
  future_instance record;
begin
  if auth.uid() is null or not public.has_permission('services.participate') then
    raise exception 'Sign in to join this weekly seva.';
  end if;
  select * into template_record from public.service_templates
  where id = p_template_id for update;
  if template_record.id is null or not template_record.active
    or template_record.participation_mode <> 'open'
  then raise exception 'This weekly seva is not open for self-assignment.'; end if;

  joinable_days := array(
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
  if cardinality(joinable_days) = 0 then
    raise exception 'This weekly seva is already fully covered.';
  end if;

  insert into public.service_template_assignees (
    service_template_id, devotee_id, assigned_by, status, days_of_week
  ) values (
    template_record.id, auth.uid(), auth.uid(), 'active',
    joinable_days
  ) on conflict (service_template_id, devotee_id) do update set
    assigned_by = auth.uid(), status = 'active',
    days_of_week = excluded.days_of_week, updated_at = now()
  returning * into joined_assignee;

  perform public.generate_service_instances(180);
  insert into public.service_assignments (
    service_instance_id, devotee_id, assignment_method, assigned_by,
    status, verification
  )
  select instances.id, auth.uid(), 'recurring_assignment', auth.uid(),
    'confirmed', 'self_report'
  from public.service_instances instances
  where instances.template_id = template_record.id
    and instances.date >= (now() at time zone 'America/Chicago')::date
    and extract(dow from instances.date)::integer = any(joinable_days)
    and instances.status not in ('cancelled', 'completed')
  on conflict (service_instance_id, devotee_id) do update set
    status = 'confirmed', assignment_method = 'recurring_assignment',
    assigned_by = auth.uid(), completed_at = null;

  for future_instance in
    select id from public.service_instances
    where template_id = template_record.id
      and date >= (now() at time zone 'America/Chicago')::date
  loop
    perform public.refresh_service_instance_capacity(future_instance.id);
  end loop;

  select name into devotee_name from public.users where id = auth.uid();
  service_name := coalesce(
    (select name from public.service_types where id = template_record.service_type_id),
    template_record.custom_name, 'Temple seva'
  );
  perform public.notify_service_oversight(
    'service_joined', 'A weekly seva was joined',
    devotee_name || ' joined "' || service_name || '" as a weekly seva.',
    jsonb_build_object('serviceTemplateId', template_record.id), auth.uid()
  );
  return joined_assignee;
end;
$$;

-- Create one grouped request and atomic occurrence exceptions for exactly the
-- selected weekdays and date window.
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

  for selected_instance in
    select instances.id, instances.date
    from public.service_instances instances
    join public.service_assignments assignments
      on assignments.service_instance_id = instances.id
     and assignments.devotee_id = auth.uid()
     and assignments.status in ('assigned', 'confirmed')
    where instances.template_id = template_record.id
      and instances.date between p_date_from and effective_to
      and extract(dow from instances.date)::integer = any(selected_days)
      and instances.status not in ('cancelled', 'completed')
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

  if created_count = 0 then
    raise exception 'No assigned weekly occurrences match those dates and days.';
  end if;

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

-- Opening a grouped request makes only its still-uncovered occurrences public.
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
    raise exception 'Only Core, Tech, or President can arrange weekly-seva coverage.';
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
  where users.id <> exception_record.devotee_id;
end;
$$;

-- Ask one devotee for one occurrence, all selected unavailable dates, or the
-- selected weekdays from now onward.
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
begin
  if not public.has_permission('services.resolve_coverage') then
    raise exception 'Only Core, Tech, or President can arrange weekly-seva coverage.';
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
  pending_left integer;
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

  if p_accept then
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
      and extract(dow from instances.date)::integer = any(plan_record.days_of_week)
    on conflict (service_instance_id, devotee_id) do update set
      status = 'confirmed', assigned_by = excluded.assigned_by,
      assignment_method = 'accepted_coverage_offer', completed_at = null;

    update public.service_exceptions exceptions set
      status = 'resolved', resolution_kind = 'substitute',
      substitute_devotee_id = auth.uid(), resolved_at = now(),
      resolved_by = plan_record.created_by
    from public.service_instances instances
    where exceptions.request_group_id = plan_record.request_group_id
      and exceptions.status = 'pending'
      and instances.id = exceptions.service_instance_id
      and instances.date >= plan_record.date_from
      and (plan_record.date_to is null or instances.date <= plan_record.date_to)
      and extract(dow from instances.date)::integer = any(plan_record.days_of_week);

    update public.service_coverage_plans
    set status = 'cancelled'
    where request_group_id = plan_record.request_group_id
      and id <> plan_record.id and status = 'pending'
      and date_from >= plan_record.date_from
      and (plan_record.date_to is null or date_from <= plan_record.date_to);
    update public.service_offers offers
    set status = 'expired', responded_at = now()
    from public.service_coverage_plans plans
    where offers.service_coverage_plan_id = plans.id
      and plans.request_group_id = plan_record.request_group_id
      and plans.id <> plan_record.id and offers.status = 'pending'
      and plans.status = 'cancelled';
  end if;

  select name into devotee_name from public.users where id = auth.uid();
  service_name := coalesce(
    (select service_types.name from public.service_templates templates
      join public.service_types on service_types.id = templates.service_type_id
      where templates.id = plan_record.service_template_id),
    (select custom_name from public.service_templates
      where id = plan_record.service_template_id), 'Temple seva'
  );
  perform public.notify_service_oversight(
    'service_offer_response',
    case when p_accept then 'Weekly coverage accepted' else 'Weekly coverage declined' end,
    devotee_name || case when p_accept then ' accepted coverage for "'
      else ' declined coverage for "' end || service_name || '".',
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
  end if;
  select count(*) into pending_left from public.service_exceptions
  where request_group_id = plan_record.request_group_id and status = 'pending';
  return updated_offer;
end;
$$;

revoke all on function public.fill_weekly_assignee_days() from public;
revoke all on function public.enforce_service_need_access() from public;
revoke all on function public.can_view_service_instance(uuid) from public;
revoke all on function public.can_view_service_template(uuid) from public;
revoke all on function public.join_weekly_service(uuid) from public;
revoke all on function public.report_weekly_service_unavailable(uuid, text, date, date, integer[], text) from public;

grant execute on function public.can_view_service_instance(uuid) to authenticated;
grant execute on function public.can_view_service_template(uuid) to authenticated;
grant execute on function public.join_weekly_service(uuid) to authenticated;
grant execute on function public.report_weekly_service_unavailable(uuid, text, date, date, integer[], text) to authenticated;

-- Keep weekly instances available on a rolling horizon when pg_cron exists.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    if not exists (select 1 from cron.job where jobname = 'generate-weekly-seva-instances') then
      perform cron.schedule(
        'generate-weekly-seva-instances', '15 2 * * *',
        'select public.generate_service_instances(90);'
      );
    end if;
  end if;
end;
$$;
