-- A devotee can step back from a posted seva before it starts.
-- Requires 202608310096_seva_origin_separates_the_flows.sql.
--
-- A devotee accepts a seva on Monday and something comes up. Until now their
-- only options were to not turn up, or to reach the coordinator outside the
-- app — and the coordinator found out when nobody arrived. Weekly seva has had
-- coverage since 202608020003; a posted one-off had nothing.
--
-- The two participation modes want different things, and this is the whole
-- design:
--
--   OPEN         The place is freed immediately. Anyone may take it, which is
--                exactly what "open" already means, so there is nothing to
--                arrange — and holding the place until somebody accepted would
--                hide the gap rather than close it. The devotee who posted it
--                is told a place has opened.
--
--   INVITE-ONLY  Nobody else can simply take it, so freeing it silently would
--                leave a seva short with no way for anyone to notice. A
--                coverage request opens instead, addressed to the devotee who
--                posted it and invited them, who can then open the day to
--                everyone or ask somebody else. This is the same machinery
--                weekly seva uses, and it lands in the same coverage inbox.
--
-- NOT for a self-added seva. The devotee wrote that record themselves and
-- removes it with delete_seva_registration; coverage there would be a
-- middleman for a conversation with oneself. NOT for weekly either, which has
-- report_weekly_service_unavailable and a rota to consider.
--
-- Only BEFORE the seva starts. After that the seva is under way and the
-- question is no longer "can somebody else go" but "were you there", which is
-- the coordinator's to record. Allowing a step back afterwards would also be a
-- way to walk away from an absence that had already been marked.
--
-- A Volunteer may post a one-off seva and already holds
-- services.resolve_coverage (202608020001), so the coverage request reaches
-- them without any new permission: the inbox they already have is the one it
-- arrives in.

create or replace function public.step_back_from_seva(
  p_instance_id uuid,
  p_reason text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  instance_record public.service_instances;
  assignment_record public.service_assignments;
  exception_id uuid;
  devotee_name text;
  seva_name text;
begin
  if auth.uid() is null then
    raise exception 'Sign in to step back from a seva.';
  end if;

  select * into instance_record from public.service_instances
  where id = p_instance_id for update;
  if instance_record.id is null then
    raise exception 'This seva could not be found.';
  end if;

  if instance_record.template_id is not null then
    raise exception 'This is a weekly seva. Ask for coverage for the day you cannot make.';
  end if;

  if not public.seva_is_servable(instance_record.id) then
    raise exception 'You added this seva yourself. Remove it instead of stepping back from it.';
  end if;

  if instance_record.status in ('cancelled', 'completed') then
    raise exception 'This seva is already closed.';
  end if;

  if ((instance_record.date + instance_record.start_time)
      at time zone 'America/Chicago') <= now()
  then
    raise exception 'This seva has already started. Whoever posted it records who served.';
  end if;

  select * into assignment_record from public.service_assignments
  where service_instance_id = p_instance_id
    and devotee_id = auth.uid()
    and status in ('assigned', 'confirmed')
  for update;

  if assignment_record.id is null then
    raise exception 'You do not hold a place on this seva.';
  end if;

  -- The place is given up either way. What differs is whether anybody has to
  -- be asked to fill it.
  update public.service_assignments
  set status = 'withdrawn', completed_at = null
  where id = assignment_record.id;

  select users.name into devotee_name from public.users where users.id = auth.uid();
  seva_name := public.service_instance_name(instance_record);

  if instance_record.participation_mode = 'invite_only' then
    insert into public.service_exceptions (
      service_instance_id, devotee_id, reason, status,
      unavailable_scope, unavailable_from, unavailable_to, unavailable_days
    )
    values (
      p_instance_id, auth.uid(), nullif(trim(coalesce(p_reason, '')), ''),
      'pending',
      'occurrence', instance_record.date, instance_record.date,
      array[extract(dow from instance_record.date)::integer]
    )
    returning id into exception_id;

    -- Addressed to whoever posted it, because they are the one who invited
    -- this devotee and the one who can open the day or ask somebody else.
    if instance_record.posted_by is not null
      and instance_record.posted_by <> auth.uid()
    then
      perform public.queue_app_notification(
        instance_record.posted_by,
        'service_coverage_needed',
        'A seva needs cover',
        coalesce(devotee_name, 'A devotee') || ' cannot make "' || seva_name
          || '" on ' || public.format_seva_when(
               instance_record.date, instance_record.start_time)
          || '. Open it to everyone, or ask somebody else.',
        jsonb_build_object(
          'serviceInstanceId', p_instance_id,
          'serviceExceptionId', exception_id
        )
      );
    end if;
  else
    -- Open seva: the place is simply free again, which is what open means.
    if instance_record.posted_by is not null
      and instance_record.posted_by <> auth.uid()
    then
      perform public.queue_app_notification(
        instance_record.posted_by,
        'service_left',
        'A place opened up',
        coalesce(devotee_name, 'A devotee') || ' stepped back from "' || seva_name
          || '" on ' || public.format_seva_when(
               instance_record.date, instance_record.start_time)
          || '. The place is open for anyone again.',
        jsonb_build_object('serviceInstanceId', p_instance_id)
      );
    end if;
  end if;

  -- A seva that was full is not full any more, whichever mode it is in.
  update public.service_instances
  set status = 'open'
  where id = p_instance_id
    and status = 'full';

  return exception_id;
end;
$$;

revoke all on function public.step_back_from_seva(uuid, text) from public, anon;
grant execute on function public.step_back_from_seva(uuid, text) to authenticated;

comment on function public.step_back_from_seva(uuid, text) is
  'A devotee gives up their place on a posted one-off seva before it starts. An open seva simply frees the place; an invite-only one opens a coverage request for whoever posted it. Returns the exception id, or null when none was needed.';

-- ---------------------------------------------------------------------------
-- Proof, run at migration time. Seeded and rolled back, never deleted.
-- ---------------------------------------------------------------------------
do $$
declare
  v_poster uuid := '7d000000-0000-0000-0000-000000000001';
  v_dev    uuid := '7d000000-0000-0000-0000-000000000002';
  v_head   uuid := '7d000000-0000-0000-0000-000000000003';
  v_type uuid;
  v_open uuid;
  v_invite uuid;
  v_started uuid;
  v_exception uuid;
  v_refused boolean;
  v_tomorrow date := (now() at time zone 'America/Chicago')::date + 1;
begin
  begin
    insert into auth.users (id, email, raw_user_meta_data) values
      (v_poster, 'sb-poster@example.test', jsonb_build_object('name', 'Volunteer Poster')),
      (v_dev,    'sb-dev@example.test',    jsonb_build_object('name', 'Stepping Devotee')),
      (v_head,   'sb-head@example.test',   jsonb_build_object('name', 'The President'));

    update public.users
    set role_id = (select id from public.roles where name = 'volunteer')
    where id = v_poster;
    update public.users
    set role_id = (select id from public.roles where name = 'president')
    where id = v_head;

    insert into public.service_types (name, category)
    values ('Step Back Proof Seva', 'other')
    returning id into v_type;

    -- An OPEN seva tomorrow.
    insert into public.service_instances
      (service_type_id, date, start_time, duration_minutes, slots_needed,
       participation_mode, posted_by, status)
    values (v_type, v_tomorrow, time '09:00', 60, 2, 'open', v_poster, 'open')
    returning id into v_open;

    insert into public.service_assignments
      (service_instance_id, devotee_id, assignment_method, assigned_by,
       status, verification)
    values (v_open, v_dev, 'self_joined', v_dev, 'confirmed', 'self_report');

    perform set_config('request.jwt.claim.sub', v_dev::text, true);
    v_exception := public.step_back_from_seva(v_open, 'Work came up.');
    perform set_config('request.jwt.claim.sub', '', true);

    if v_exception is not null then
      raise exception 'stepping back from an OPEN seva opened a coverage request';
    end if;
    if (select assignments.status from public.service_assignments assignments
        where assignments.service_instance_id = v_open
          and assignments.devotee_id = v_dev) <> 'withdrawn'
    then
      raise exception 'the place was not given up';
    end if;

    -- An INVITE-ONLY seva tomorrow.
    insert into public.service_instances
      (service_type_id, date, start_time, duration_minutes, slots_needed,
       participation_mode, posted_by, status)
    values (v_type, v_tomorrow, time '14:00', 60, 1, 'invite_only', v_poster, 'open')
    returning id into v_invite;

    insert into public.service_assignments
      (service_instance_id, devotee_id, assignment_method, assigned_by,
       status, verification)
    values (v_invite, v_dev, 'accepted_offer', v_poster, 'confirmed', 'self_report');

    perform set_config('request.jwt.claim.sub', v_dev::text, true);
    v_exception := public.step_back_from_seva(v_invite, null);
    perform set_config('request.jwt.claim.sub', '', true);

    if v_exception is null then
      raise exception 'stepping back from an INVITE-ONLY seva opened no coverage request';
    end if;
    if not exists (
      select 1 from public.service_exceptions
      where id = v_exception and status = 'pending'
    ) then
      raise exception 'the coverage request was not left pending';
    end if;
    -- Its own group, so it cannot merge with any other request.
    if (select request_group_id from public.service_exceptions
        where id = v_exception) is null
    then
      raise exception 'the coverage request has no group of its own';
    end if;
    -- And the devotee who posted it was told.
    if not exists (
      select 1 from public.app_notifications
      where user_id = v_poster
        and kind = 'service_coverage_needed'
        and data ->> 'serviceInstanceId' = v_invite::text
    ) then
      raise exception 'whoever posted the seva was not told it needs cover';
    end if;

    -- A seva that has already started cannot be stepped back from.
    insert into public.service_instances
      (service_type_id, date, start_time, duration_minutes, slots_needed,
       participation_mode, posted_by, status)
    values (v_type, (now() at time zone 'America/Chicago')::date - 1,
            time '09:00', 60, 1, 'open', v_poster, 'open')
    returning id into v_started;

    insert into public.service_assignments
      (service_instance_id, devotee_id, assignment_method, assigned_by,
       status, verification)
    values (v_started, v_dev, 'self_joined', v_dev, 'confirmed', 'self_report');

    perform set_config('request.jwt.claim.sub', v_dev::text, true);
    v_refused := false;
    begin
      perform public.step_back_from_seva(v_started, null);
    exception when others then
      v_refused := true;
    end;
    perform set_config('request.jwt.claim.sub', '', true);
    if not v_refused then
      raise exception 'a devotee stepped back from a seva that had already started';
    end if;

    raise exception 'ISKCON_PROOF_ROLLBACK';
  exception
    when others then
      if sqlerrm <> 'ISKCON_PROOF_ROLLBACK' then
        raise;
      end if;
  end;

  raise notice 'a devotee can step back from a posted seva before it starts';
end;
$$;
