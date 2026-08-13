-- Run after 202608030008_service_operations_and_reports.sql.
-- Every block raises an exception if a security or schema guarantee is absent.

do $$
begin
  if exists (
    select 1
    from public.role_permissions permissions
    join public.roles roles on roles.id = permissions.role_id
    where roles.name = 'volunteer'
      and permissions.permission_key = 'services.resolve_coverage'
  ) then
    raise exception 'Volunteer must not have recurring coverage access.';
  end if;

  if (
    select count(*)
    from public.role_permissions permissions
    join public.roles roles on roles.id = permissions.role_id
    where roles.name in ('president', 'tech')
      and permissions.permission_key in ('services.delete_any', 'services.export_reports')
  ) <> 4 then
    raise exception 'President and Tech must both have delete/report authority.';
  end if;

  -- 0009 removed oversight and requirement completion from Volunteer: they
  -- take part and post, they do not coordinate. Only the three coordinator
  -- levels keep these.
  if (
    select count(*)
    from public.role_permissions permissions
    join public.roles roles on roles.id = permissions.role_id
    where roles.name in ('president', 'tech', 'core')
      and permissions.permission_key in ('services.oversee_activity', 'services.complete_requirement')
  ) <> 6 then
    raise exception 'Oversight and requirement completion grants are incomplete.';
  end if;

  if exists (
    select 1
    from public.role_permissions permissions
    join public.roles roles on roles.id = permissions.role_id
    where roles.name in ('volunteer', 'devotee')
      and permissions.permission_key in ('services.oversee_activity', 'services.complete_requirement')
  ) then
    raise exception 'Volunteer or Devotee must not hold coordinator authority.';
  end if;
end;
$$;

do $$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'service_qr_sessions'
      and column_name = 'planned_end_at' and is_nullable = 'NO'
  ) then
    raise exception 'Live seva planned end is not enforced.';
  end if;
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'service_templates'
      and column_name = 'days_of_week'
  ) then
    raise exception 'Multi-day recurring schedules are missing.';
  end if;
  if to_regclass('public.service_coverage_plans') is null then
    raise exception 'Coverage range plans are missing.';
  end if;
  if to_regclass('public.device_push_tokens') is null then
    raise exception 'Physical-device push registration is missing.';
  end if;
end;
$$;

do $$
declare
  required_function text;
begin
  foreach required_function in array array[
    'complete_due_service_sessions',
    'start_planned_service_session',
    'start_planned_qr_service_session',
    'delete_service_activity',
    'delete_service_assignment_activity',
    'delete_service_requirement',
    'create_service_template_v2',
    'update_service_template_v2',
    'delete_service_template',
    'offer_service_coverage_range',
    'respond_to_coverage_range_offer',
    'register_device_push_token'
  ]
  loop
    if not exists (
      select 1 from pg_proc procedures
      join pg_namespace namespaces on namespaces.oid = procedures.pronamespace
      where namespaces.nspname = 'public' and procedures.proname = required_function
    ) then
      raise exception 'Required RPC % is missing.', required_function;
    end if;
  end loop;
end;
$$;

select
  'service operations verification passed' as result,
  count(*) filter (where status = 'active') as active_sessions,
  count(*) filter (where status = 'completed') as completed_sessions
from public.service_qr_sessions;
