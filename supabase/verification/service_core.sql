-- Run after 202608020002_service_core.sql. These checks are read-only.

select name, category, is_active
from public.service_types
order by category, name;

select
  roles.name as role_name,
  array_agg(role_permissions.permission_key order by role_permissions.permission_key)
    filter (where role_permissions.permission_key like 'services.%')
    as service_permissions
from public.roles
left join public.role_permissions on role_permissions.role_id = roles.id
group by roles.name
order by roles.name;

select
  to_regclass('public.service_types') as service_types,
  to_regclass('public.service_instances') as service_instances,
  to_regclass('public.service_assignments') as service_assignments,
  to_regclass('public.service_offers') as service_offers,
  to_regclass('public.app_notifications') as app_notifications;

select routine_name
from information_schema.routines
where routine_schema = 'public'
  and routine_name in (
    'list_service_devotees',
    'add_service_type',
    'create_service_requirement',
    'join_service_instance',
    'leave_service_instance',
    'log_completed_service',
    'offer_service_instance',
    'respond_to_service_offer',
    'complete_service_instance'
  )
order by routine_name;

select schemaname, tablename, policyname
from pg_policies
where schemaname = 'public'
  and tablename in (
    'service_types',
    'service_instances',
    'service_assignments',
    'service_offers',
    'app_notifications'
  )
order by tablename, policyname;
