-- Marking a devotee absent takes their points away, however late it is said.
-- Requires 202608040068_completion_truthfulness.sql and 202608040062_fair_scaling.sql.
--
-- The temple's rule has no expiry date on it: absent or excused earns nothing.
-- Two mechanisms together were quietly breaking it.
--
--   * public.recompute_seva_mala_period returns 0 without doing anything when
--     the period is frozen (0062 section ~587), and the nightly run freezes a
--     week on its first pass after the week's last day (0062 ~829).
--   * public.record_seva_attendance calls only
--     reconcile_service_instance_completion — it has never asked Seva Mala to
--     recount, and it deliberately has NO upper time bound, because a
--     coordinator correcting a record days later is exactly what it is for.
--
-- So: a recurring seva auto-completes, every rostered devotee is credited,
-- Monday's run freezes the week, and on Tuesday the coordinator marks Bhakta X
-- absent. X keeps the points, and keeps any badge those points earned.
--
-- The correction is the authority here, not the freeze. A period is frozen so
-- the board stops moving on its own, not so a coordinator can be overruled by
-- the calendar — so an attendance correction reopens the periods it touches
-- and has them counted again.

create or replace function public.record_seva_attendance(
  p_assignment_id uuid,
  p_attendance text
)
returns public.service_assignments
language plpgsql
security definer
set search_path = ''
as $$
declare
  assignment_record public.service_assignments;
  instance_record public.service_instances;
  updated_assignment public.service_assignments;
  actor_name text;
  v_period record;
begin
  if p_attendance is not null
    and p_attendance not in ('served', 'absent', 'excused')
  then
    raise exception 'Attendance is served, absent, or excused.';
  end if;

  select * into assignment_record from public.service_assignments
  where id = p_assignment_id for update;
  if assignment_record.id is null then
    raise exception 'This seva place could not be found.';
  end if;

  select * into instance_record from public.service_instances
  where id = assignment_record.service_instance_id;

  -- The same authority that closes a seva says who was there for it.
  if instance_record.posted_by is distinct from auth.uid()
    and not public.has_permission('app.view_all')
  then
    raise exception 'Only the devotee who posted this seva, a Tech Admin, or the President can record attendance.';
  end if;

  if ((instance_record.date + instance_record.start_time)
      at time zone 'America/Chicago') > now() then
    raise exception 'Attendance can be recorded once the seva has started.';
  end if;

  update public.service_assignments
  set attendance = p_attendance
  where id = p_assignment_id
  returning * into updated_assignment;

  select name into actor_name from public.users where id = auth.uid();

  -- Being marked absent is worth knowing about; being marked present is not.
  if p_attendance = 'absent' and assignment_record.devotee_id <> auth.uid() then
    perform public.queue_app_notification(
      assignment_record.devotee_id, 'service_left',
      'Marked as not attending',
      actor_name || ' recorded that you were not able to attend "'
        || public.service_instance_name(instance_record) || '" on '
        || public.format_seva_when(instance_record.date, instance_record.start_time)
        || '. Tell them if that is wrong.',
      jsonb_build_object('serviceInstanceId', instance_record.id)
    );
  end if;

  -- Sentence 2. One word from a coordinator can be the last word on whether
  -- this seva happened at all, in either direction.
  perform public.reconcile_service_instance_completion(instance_record.id);

  -- Sentence 3, and the reason this migration exists. Every Seva Mala period
  -- covering the day of this seva is reopened and recounted, so the points
  -- follow the correction instead of outliving it. Only when the attendance
  -- actually changed: an idempotent re-save must not thaw a frozen week.
  if updated_assignment.attendance is distinct from assignment_record.attendance
  then
    for v_period in
      select periods.id
      from public.seva_mala_periods periods
      where instance_record.date between periods.starts_on and periods.ends_on
    loop
      update public.seva_mala_periods
      set frozen_at = null
      where id = v_period.id;

      perform public.recompute_seva_mala_period(v_period.id);
    end loop;
  end if;

  return updated_assignment;
end;
$$;

revoke all on function public.record_seva_attendance(uuid, text) from public, anon;
grant execute on function public.record_seva_attendance(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Proof, run at migration time.
-- ---------------------------------------------------------------------------
do $$
declare
  v_frozen integer;
begin
  -- The guard that used to swallow the recount is still there — this migration
  -- does not remove it, it stops depending on it.
  if not exists (
    select 1 from pg_proc
    where proname = 'recompute_seva_mala_period'
      and pronamespace = 'public'::regnamespace
  ) then
    raise exception 'recompute_seva_mala_period is missing';
  end if;

  if pg_get_functiondef(
       'public.record_seva_attendance(uuid, text)'::regprocedure
     ) not like '%recompute_seva_mala_period%'
  then
    raise exception
      'record_seva_attendance still does not recount Seva Mala; absence would outlive the freeze';
  end if;

  if pg_get_functiondef(
       'public.record_seva_attendance(uuid, text)'::regprocedure
     ) not like '%frozen_at = null%'
  then
    raise exception 'record_seva_attendance does not reopen the frozen period';
  end if;

  select count(*) into v_frozen from public.seva_mala_periods;
  raise notice
    'attendance corrections reopen and recount their periods (% periods present)',
    v_frozen;
end;
$$;
