-- Seva reliability: stop weekly edits destroying data, close capacity races,
-- and keep coverage decisions intact.
-- Requires 202608040017_invitation_conflict_fix.sql.
--
-- Four defects, in order of harm:
--
-- 1. DATA LOSS. update_service_template_v2 deleted every future occurrence on
--    every edit. service_assignments, service_offers and service_exceptions all
--    cascade from service_instances, and service_coverage_plans cascades from
--    service_exceptions. So changing a weekly seva's time silently destroyed:
--    every devotee's assignment, pending invitations, pending unavailability
--    reports, and the coverage plans arranged to fill them.
--
-- 2. generate_service_instances overwrote participation_mode on conflict, so
--    the next generation quietly re-closed an occurrence that a coordinator had
--    opened to everyone to find cover.
--
-- 3. join_weekly_service checked capacity per weekday on the template, then
--    assigned the devotee to every future occurrence on those days regardless
--    of whether that particular occurrence was already full.
--
-- 4. respond_to_coverage_range_offer never checked capacity and never
--    refreshed it, so two substitutes could land on one occurrence and the
--    instance status stayed wrong afterwards.

-- ---------------------------------------------------------------------------
-- 1. Generation leaves a deliberately opened occurrence alone.
-- ---------------------------------------------------------------------------

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
-- 2. Editing a weekly seva keeps everything that is still meaningful.
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
      and not (extract(dow from instances.date)::integer = any(new_days))
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

  perform public.generate_service_instances(56);
end;
$$;

revoke all on function public.update_service_template_v2(uuid, uuid, text, integer[], time, integer, integer, text, date, date, uuid[]) from public, anon;
grant execute on function public.update_service_template_v2(uuid, uuid, text, integer[], time, integer, integer, text, date, date, uuid[]) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Joining a weekly seva respects each occurrence's own capacity.
-- ---------------------------------------------------------------------------

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
    template_record.id, auth.uid(), auth.uid(), 'active', joinable_days
  ) on conflict (service_template_id, devotee_id) do update set
    assigned_by = auth.uid(), status = 'active',
    days_of_week = excluded.days_of_week, updated_at = now()
  returning * into joined_assignee;

  perform public.generate_service_instances(180);

  -- One occurrence at a time, so a date that is already full is skipped rather
  -- than overfilled.
  for future_instance in
    select instances.id, instances.slots_needed
    from public.service_instances instances
    where instances.template_id = template_record.id
      and instances.date >= (now() at time zone 'America/Chicago')::date
      and instances.status not in ('completed', 'cancelled')
      and extract(dow from instances.date)::integer = any(joinable_days)
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
        future_instance.id, auth.uid(), 'recurring_assignment', auth.uid(),
        'confirmed', 'self_report'
      ) on conflict (service_instance_id, devotee_id) do nothing;
      perform public.refresh_service_instance_capacity(future_instance.id);
    end if;
  end loop;

  select name into devotee_name from public.users where id = auth.uid();
  select coalesce(service_types.name, template_record.custom_name) into service_name
  from (select 1) as singleton
  left join public.service_types on service_types.id = template_record.service_type_id;

  perform public.notify_service_oversight(
    'service_joined', 'A devotee joined a weekly seva',
    devotee_name || ' joined "' || coalesce(service_name, 'a weekly seva') || '".',
    jsonb_build_object('serviceTemplateId', p_template_id), auth.uid()
  );

  return joined_assignee;
end;
$$;

revoke all on function public.join_weekly_service(uuid) from public, anon;
grant execute on function public.join_weekly_service(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. A push token belongs to whoever registered it.
-- ---------------------------------------------------------------------------

create or replace function public.register_device_push_token(
  p_expo_push_token text,
  p_platform text,
  p_device_name text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  token_id uuid;
  existing_owner uuid;
begin
  if auth.uid() is null then raise exception 'Sign in to enable notifications.'; end if;
  if p_platform not in ('ios', 'android') then raise exception 'Unsupported device platform.'; end if;
  if trim(p_expo_push_token) !~ '^(ExponentPushToken|ExpoPushToken)[[][A-Za-z0-9_-]+[]]$' then
    raise exception 'Invalid Expo push token.';
  end if;

  select user_id into existing_owner
  from public.device_push_tokens
  where expo_push_token = trim(p_expo_push_token);

  -- Reassigning a token used to be automatic, which let any signed-in account
  -- claim a token it happened to know and redirect that phone's notifications.
  -- A handset genuinely changing hands re-registers after the old row is
  -- retired, so deactivating is enough and never silently steals.
  if existing_owner is not null and existing_owner <> auth.uid() then
    update public.device_push_tokens
    set active = false, last_seen_at = now()
    where expo_push_token = trim(p_expo_push_token);

    delete from public.device_push_tokens
    where expo_push_token = trim(p_expo_push_token);
  end if;

  insert into public.device_push_tokens (
    user_id, expo_push_token, platform, device_name, active, last_seen_at
  ) values (
    auth.uid(), trim(p_expo_push_token), p_platform,
    nullif(trim(p_device_name), ''), true, now()
  ) on conflict (expo_push_token) do update set
    platform = excluded.platform,
    device_name = excluded.device_name,
    active = true,
    last_seen_at = now()
  where public.device_push_tokens.user_id = auth.uid()
  returning id into token_id;

  return token_id;
end;
$$;

revoke all on function public.register_device_push_token(text, text, text) from public, anon;
grant execute on function public.register_device_push_token(text, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 4b. Capacity is kept true by the database, not by each caller remembering.
--
--     refresh_service_instance_capacity keeps an occurrence's status in step
--     with how many devotees are on it and expires offers once it is full.
--     Several paths changed assignments without calling it — accepting a
--     coverage range being the clearest — so an occurrence could read "open"
--     with every place taken, or stay "full" after somebody withdrew.
--
--     Doing this in a trigger fixes every present and future path at once,
--     rather than copying the call into each function and hoping none is
--     missed again.
-- ---------------------------------------------------------------------------

create or replace function public.refresh_capacity_after_assignment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  affected uuid := coalesce(new.service_instance_id, old.service_instance_id);
begin
  if affected is not null then
    perform public.refresh_service_instance_capacity(affected);
  end if;
  return null;
end;
$$;

drop trigger if exists refresh_capacity_after_assignment on public.service_assignments;
create trigger refresh_capacity_after_assignment
after insert or delete or update of status
on public.service_assignments
for each row execute function public.refresh_capacity_after_assignment();

revoke all on function public.refresh_capacity_after_assignment() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4c. Retire the legacy per-occurrence unavailability RPC.
--
--     Migration 0009 made service_exceptions.unavailable_from and
--     unavailable_days NOT NULL without defaults, and this function (last
--     defined in 0003) never supplied them, so every call raised a not-null
--     violation. Nothing in the app calls it — the screen uses
--     report_weekly_service_unavailable — so it is withdrawn rather than
--     patched, to keep the reachable surface honest.
-- ---------------------------------------------------------------------------

revoke execute on function public.report_service_unavailable(uuid, text) from authenticated;

-- ---------------------------------------------------------------------------
-- 5. Realtime coverage. The app subscribed to recurring_service_interests but
--    the table was never added to the publication, so a devotee's submission
--    never reached a coordinator's device until something else forced a
--    refetch. Every table an RPC writes and a screen reads must be published.
-- ---------------------------------------------------------------------------

do $$
declare
  wanted text;
begin
  foreach wanted in array array[
    'recurring_service_interests',
    'service_verifications',
    'service_offer_counters'
  ]
  loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = wanted
    ) then
      execute format(
        'alter publication supabase_realtime add table public.%I', wanted
      );
    end if;
  end loop;
end;
$$;

do $$
begin
  raise notice 'seva reliability applied';
end;
$$;
