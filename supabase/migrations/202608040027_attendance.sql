-- Who actually turned up.
--
-- The app records who agreed to seva, not who served it. For a temple that is
-- the difference between a plan and a record: a coordinator marking a seva
-- completed today implicitly says everyone attended, even the devotee who
-- never came. Attendance is recorded per devotee, by whoever ran the seva.
-- Requires 202608040026_push_delivery_and_reminders.sql.

alter table public.service_assignments
  add column if not exists attendance text;

alter table public.service_assignments
  drop constraint if exists service_assignment_attendance_check;
alter table public.service_assignments
  add constraint service_assignment_attendance_check check (
    attendance is null or attendance in ('served', 'absent', 'excused')
  );

comment on column public.service_assignments.attendance is
  'Null until somebody says. served / absent / excused, set by the poster, a Tech Admin or the President.';

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

  return updated_assignment;
end;
$$;

revoke all on function public.record_seva_attendance(uuid, text) from public, anon;
grant execute on function public.record_seva_attendance(uuid, text) to authenticated;

do $$
begin
  raise notice 'attendance applied';
end;
$$;
