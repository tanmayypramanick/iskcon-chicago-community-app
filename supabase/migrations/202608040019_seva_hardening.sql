-- Seva hardening: capacity per weekday, no silent vacating, pause that can be
-- undone, and registrations that cannot overlap.
-- Requires 202608040018_seva_reliability.sql.

create extension if not exists btree_gist;

-- ---------------------------------------------------------------------------
-- 1. CRITICAL. Weekly capacity is per weekday, not per template.
--
--    The trigger added in 0016 counted every active assignee on the template.
--    But slots_needed is copied onto each occurrence, and every other check in
--    the system — join_weekly_service, can_view_service_template, and the
--    client's hasWeeklyOpening — counts per weekday. So on a Mon+Thu seva with
--    one place, a devotee standing on Monday made Thursday unjoinable, and a
--    'forever' coverage handoff could never be accepted because the original
--    devotee still counted while they kept their other days.
-- ---------------------------------------------------------------------------

create or replace function public.enforce_weekly_assignee_capacity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  places integer;
begin
  if new.status <> 'active' then
    return new;
  end if;

  select slots_needed into places
  from public.service_templates
  where id = new.service_template_id;

  if places is null then
    return new;
  end if;

  -- Allowed as long as at least one claimed weekday still has room.
  if not exists (
    select 1
    from unnest(new.days_of_week) as claimed_day
    where (
      select count(*)
      from public.service_template_assignees other
      where other.service_template_id = new.service_template_id
        and other.status = 'active'
        and other.devotee_id <> new.devotee_id
        and claimed_day = any(other.days_of_week)
    ) < places
  ) then
    raise exception
      'Every weekday of this weekly seva already has % place(s) filled.', places;
  end if;

  return new;
end;
$$;

drop trigger if exists enforce_weekly_assignee_capacity
  on public.service_template_assignees;
create trigger enforce_weekly_assignee_capacity
before insert or update of devotee_id, status, days_of_week
on public.service_template_assignees
for each row execute function public.enforce_weekly_assignee_capacity();

revoke all on function public.enforce_weekly_assignee_capacity() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. CRITICAL. A devotee could quietly vacate a seva.
--
--    complete_my_service_assignment had no clock gate, so a devotee could mark
--    a future seva completed; that flipped the whole occurrence to 'completed'
--    once the count was met. delete_service_assignment_activity then let them
--    delete their own row. The occurrence was left 'completed' with nobody on
--    it, refresh_service_instance_capacity refused to touch a completed row,
--    and nobody was told. Three changes close it.
-- ---------------------------------------------------------------------------

create or replace function public.refresh_service_instance_capacity(p_instance_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  instance_record public.service_instances;
  filled_slots integer;
begin
  select * into instance_record
  from public.service_instances
  where id = p_instance_id
  for update;

  if instance_record.id is null then
    return;
  end if;

  select count(*) into filled_slots
  from public.service_assignments
  where service_instance_id = p_instance_id
    and status in ('assigned', 'confirmed', 'completed');

  -- 'completed' is included so an occurrence emptied after the fact can be
  -- reopened rather than stranded as finished with nobody on it.
  if instance_record.status in ('open', 'full', 'completed') then
    update public.service_instances
    set status = case
      when filled_slots = 0 and instance_record.status = 'completed' then 'open'
      when filled_slots >= instance_record.slots_needed
        and instance_record.status <> 'completed' then 'full'
      when instance_record.status = 'completed' then 'completed'
      else 'open'
    end
    where id = p_instance_id;
  end if;

  if filled_slots >= instance_record.slots_needed then
    update public.service_offers
    set status = 'expired', responded_at = now()
    where service_instance_id = p_instance_id
      and status = 'pending';
  end if;
end;
$$;

revoke all on function public.refresh_service_instance_capacity(uuid) from public, anon, authenticated;

-- The return type stays public.service_assignments. Changing it to void would
-- need a DROP first, which briefly removes the function other sessions are
-- calling; keeping the shape means this is a plain in-place replacement.
create or replace function public.complete_my_service_assignment(p_instance_id uuid)
returns public.service_assignments
language plpgsql
security definer
set search_path = ''
as $$
declare
  instance_record public.service_instances;
  completed_assignment public.service_assignments;
  completed_count integer;
  devotee_name text;
  starts_at timestamptz;
begin
  if auth.uid() is null then
    raise exception 'Authentication is required.';
  end if;

  select * into instance_record
  from public.service_instances
  where id = p_instance_id
  for update;

  if instance_record.id is null or instance_record.status = 'cancelled' then
    raise exception 'This seva is no longer available.';
  end if;

  -- Seva cannot be reported finished before it has begun.
  starts_at := (instance_record.date + instance_record.start_time)
    at time zone 'America/Chicago';
  if starts_at > now() then
    raise exception 'You can mark this seva completed once it has started.';
  end if;

  update public.service_assignments
  set status = 'completed', completed_at = coalesce(completed_at, now())
  where service_instance_id = p_instance_id
    and devotee_id = auth.uid()
    and status in ('assigned', 'confirmed')
  returning * into completed_assignment;

  if completed_assignment.id is null then
    raise exception 'You are not currently assigned to this seva.';
  end if;

  select count(*) into completed_count
  from public.service_assignments
  where service_instance_id = p_instance_id and status = 'completed';

  if completed_count >= instance_record.slots_needed then
    update public.service_instances
    set status = 'completed' where id = p_instance_id;
  end if;

  select name into devotee_name from public.users where id = auth.uid();
  if instance_record.posted_by is not null
    and instance_record.posted_by <> auth.uid()
  then
    perform public.queue_app_notification(
      instance_record.posted_by, 'service_completed', 'A devotee finished their seva',
      devotee_name || ' marked their part of "'
        || public.service_instance_name(instance_record) || '" completed.',
      jsonb_build_object('serviceInstanceId', p_instance_id)
    );
  end if;

  return completed_assignment;
end;
$$;

revoke all on function public.complete_my_service_assignment(uuid) from public, anon;
grant execute on function public.complete_my_service_assignment(uuid) to authenticated;

create or replace function public.delete_service_assignment_activity(p_assignment_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  assignment_record public.service_assignments;
  instance_record public.service_instances;
  devotee_name text;
begin
  select * into assignment_record
  from public.service_assignments
  where id = p_assignment_id
  for update;

  if assignment_record.id is null then
    raise exception 'This seva activity could not be found.';
  end if;
  if assignment_record.status <> 'completed' then
    raise exception 'Only completed seva activity can be removed here.';
  end if;
  if assignment_record.devotee_id <> auth.uid()
    and not public.has_permission('services.delete_any')
  then
    raise exception 'Only this devotee, a Tech Admin, or the President can remove it.';
  end if;

  select * into instance_record
  from public.service_instances
  where id = assignment_record.service_instance_id;

  delete from public.service_assignments where id = p_assignment_id;
  perform public.refresh_service_instance_capacity(assignment_record.service_instance_id);

  -- Removing an activity record reopens a place. The coordinator who asked for
  -- the seva is told, so a silently vacated slot cannot go unnoticed.
  select name into devotee_name from public.users where id = auth.uid();
  if instance_record.posted_by is not null
    and instance_record.posted_by <> auth.uid()
  then
    perform public.queue_app_notification(
      instance_record.posted_by, 'service_left', 'A seva place reopened',
      devotee_name || ' removed their activity record for "'
        || public.service_instance_name(instance_record) || '".',
      jsonb_build_object('serviceInstanceId', instance_record.id)
    );
  end if;
end;
$$;

revoke all on function public.delete_service_assignment_activity(uuid) from public, anon;
grant execute on function public.delete_service_assignment_activity(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Pausing a weekly seva must be undoable.
--
--    Pausing cancelled every future occurrence; resuming only regenerated,
--    and generation's ON CONFLICT never touches status. So a resumed weekly
--    seva had a roster and no live dates, for good.
-- ---------------------------------------------------------------------------

create or replace function public.set_service_template_active(
  p_template_id uuid,
  p_active boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  template_record public.service_templates;
  actor_name text;
  seva_name text;
  assignee record;
  affected uuid;
begin
  if not public.has_permission('services.manage_recurring') then
    raise exception 'Only a Community Head, Tech Admin, or the President can pause weekly seva.';
  end if;

  update public.service_templates
  set active = p_active, updated_at = now()
  where id = p_template_id
  returning * into template_record;
  if template_record.id is null then
    raise exception 'This weekly seva was not found.';
  end if;

  select name into actor_name from public.users where id = auth.uid();
  select coalesce(service_types.name, template_record.custom_name) into seva_name
  from (select 1) as singleton
  left join public.service_types on service_types.id = template_record.service_type_id;

  if p_active then
    -- Bring back exactly what pausing cancelled.
    update public.service_instances
    set status = 'open'
    where template_id = p_template_id
      and date >= (now() at time zone 'America/Chicago')::date
      and status = 'cancelled';

    for affected in
      select id from public.service_instances
      where template_id = p_template_id
        and date >= (now() at time zone 'America/Chicago')::date
    loop
      perform public.refresh_service_instance_capacity(affected);
    end loop;

    perform public.generate_service_instances(56);
  else
    update public.service_instances
    set status = 'cancelled'
    where template_id = p_template_id
      and date >= (now() at time zone 'America/Chicago')::date
      and status not in ('completed', 'cancelled');

    update public.service_offers
    set status = 'expired', responded_at = now()
    where service_template_id = p_template_id
      and status = 'pending';
  end if;

  -- Standing assignees are told either way; their schedule just changed.
  for assignee in
    select distinct devotee_id from public.service_template_assignees
    where service_template_id = p_template_id
      and status = 'active'
      and devotee_id <> auth.uid()
  loop
    perform public.queue_app_notification(
      assignee.devotee_id,
      case when p_active then 'service_open' else 'service_cancelled' end,
      case when p_active then 'A weekly seva resumed' else 'A weekly seva was paused' end,
      actor_name || (case when p_active then ' resumed "' else ' paused "' end)
        || coalesce(seva_name, 'a weekly seva') || '".',
      jsonb_build_object('serviceTemplateId', p_template_id)
    );
  end loop;
end;
$$;

revoke all on function public.set_service_template_active(uuid, boolean) from public, anon;
grant execute on function public.set_service_template_active(uuid, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. A verified seva is a record, not a coordinator's to erase.
--
--    delete_seva_registration let any Community Head destroy another devotee's
--    verified history. Pending and declined registrations are still theirs to
--    tidy; a verified one may only be removed by the devotee it belongs to, a
--    Tech Admin, or the President. The verifier is now told either way.
-- ---------------------------------------------------------------------------

create or replace function public.delete_seva_registration(p_verification_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  target public.service_verifications;
  actor_name text;
  seva_name text;
begin
  select * into target
  from public.service_verifications
  where id = p_verification_id
  for update;

  if target.id is null then
    raise exception 'This seva registration could not be found.';
  end if;

  if target.status = 'verified' then
    if target.devotee_id <> auth.uid()
      and not public.has_permission('app.view_all')
    then
      raise exception 'A verified seva can only be removed by the devotee it belongs to, a Tech Admin, or the President.';
    end if;
  elsif target.devotee_id <> auth.uid()
    and not public.has_permission('services.manage_recurring')
    and not public.has_permission('app.view_all')
  then
    raise exception 'Only this devotee, a Community Head, a Tech Admin, or the President can remove it.';
  end if;

  select name into actor_name from public.users where id = auth.uid();
  seva_name := coalesce(
    (select name from public.service_types where id = target.service_type_id),
    target.custom_name
  );

  if target.service_instance_id is not null then
    delete from public.service_instances where id = target.service_instance_id;
  end if;

  delete from public.service_verifications where id = p_verification_id;

  if target.devotee_id <> auth.uid() then
    perform public.queue_app_notification(
      target.devotee_id, 'service_deleted', 'A seva registration was removed',
      actor_name || ' removed your "' || seva_name || '" seva registration.',
      jsonb_build_object('serviceVerificationId', p_verification_id)
    );
  end if;

  -- The member holding the request should not be left with a dead item.
  if target.status = 'pending' and target.verifier_id <> auth.uid() then
    perform public.queue_app_notification(
      target.verifier_id, 'service_deleted', 'A seva request was withdrawn',
      'The "' || seva_name || '" seva you were asked to verify was removed.',
      jsonb_build_object('serviceVerificationId', p_verification_id)
    );
  end if;
end;
$$;

revoke all on function public.delete_seva_registration(uuid) from public, anon;
grant execute on function public.delete_seva_registration(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. One devotee cannot be in two places at once.
--
--    The only guard was a unique index on the exact (devotee, start, end)
--    tuple, so shifting a registration by a minute created an overlapping
--    second one. An exclusion constraint refuses any overlap outright.
-- ---------------------------------------------------------------------------

delete from public.service_verifications outer_row
where status <> 'declined'
  and exists (
    select 1 from public.service_verifications inner_row
    where inner_row.id <> outer_row.id
      and inner_row.devotee_id = outer_row.devotee_id
      and inner_row.status <> 'declined'
      and tstzrange(inner_row.start_at, inner_row.end_at, '[)')
          && tstzrange(outer_row.start_at, outer_row.end_at, '[)')
      and (inner_row.created_at, inner_row.id) < (outer_row.created_at, outer_row.id)
  );

alter table public.service_verifications
  drop constraint if exists service_verification_no_overlap;

alter table public.service_verifications
  add constraint service_verification_no_overlap
  exclude using gist (
    devotee_id with =,
    tstzrange(start_at, end_at, '[)') with &&
  ) where (status <> 'declined');

do $$
begin
  raise notice 'seva hardening applied';
end;
$$;
