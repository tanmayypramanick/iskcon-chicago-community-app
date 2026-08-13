-- Marking a seva request completed belongs to whoever posted it.
--
-- A finished seva request waits to be verified; confirming it actually happened
-- is the poster's call, or a Tech Admin's or the President's. A Community Head
-- could previously close any request in the temple.
-- Requires 202608040022_offer_idempotency.sql.

create or replace function public.complete_service_instance(p_instance_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  instance_record public.service_instances;
  participant record;
  actor_name text;
begin
  select * into instance_record
  from public.service_instances
  where id = p_instance_id
  for update;

  if instance_record.id is null then
    raise exception 'This seva request could not be found.';
  end if;

  -- Confirming that a seva actually happened belongs to whoever asked for it,
  -- and to the two levels that can override anything. A Community Head holds
  -- services.complete_requirement for the seva they run, but that is no longer
  -- enough to close somebody else's request.
  if instance_record.posted_by is distinct from auth.uid()
    and not public.has_permission('app.view_all')
  then
    raise exception 'Only the devotee who posted this seva request, a Tech Admin, or the President can mark it completed.';
  end if;

  update public.service_instances set status = 'completed'
  where id = p_instance_id and status not in ('completed', 'cancelled');
  if not found then raise exception 'This seva can no longer be completed.'; end if;

  update public.service_assignments
  set status = 'completed', completed_at = coalesce(completed_at, now())
  where service_instance_id = p_instance_id
    and status in ('assigned', 'confirmed');

  select * into instance_record from public.service_instances where id = p_instance_id;
  select name into actor_name from public.users where id = auth.uid();

  for participant in
    select distinct devotee_id from public.service_assignments
    where service_instance_id = p_instance_id and devotee_id <> auth.uid()
  loop
    perform public.queue_app_notification(
      participant.devotee_id, 'service_completed', 'Seva marked completed',
      actor_name || ' marked "' || public.service_instance_name(instance_record) || '" completed.',
      jsonb_build_object('serviceInstanceId', p_instance_id)
    );
  end loop;

  perform public.notify_service_oversight(
    'service_completed', 'A seva request was completed',
    actor_name || ' completed "' || public.service_instance_name(instance_record) || '".',
    jsonb_build_object('serviceInstanceId', p_instance_id), auth.uid()
  );
end;
$$;

revoke all on function public.complete_service_instance(uuid) from public, anon;
grant execute on function public.complete_service_instance(uuid) to authenticated;

do $$
begin
  raise notice 'completion authority applied';
end;
$$;
