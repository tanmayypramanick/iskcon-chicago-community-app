-- Run after the 007 migration and supabase/seed/service_activity.sql.

select
  to_regclass('public.recurring_service_interests') as recurring_interests,
  to_regprocedure('public.start_list_service_session(uuid)') as start_list_rpc,
  to_regprocedure('public.start_qr_service_session(text)') as start_qr_rpc,
  to_regprocedure('public.complete_service_session(uuid)') as complete_timer_rpc,
  to_regprocedure('public.complete_my_service_assignment(uuid)') as complete_own_assignment_rpc,
  to_regprocedure(
    'public.submit_recurring_service_interest(text,uuid[],text,text,boolean,text)'
  ) as submit_interest_rpc,
  to_regprocedure(
    'public.review_recurring_service_interest(uuid,boolean,text)'
  ) as review_interest_rpc;

select
  count(*) as active_service_types,
  count(qr_token) as service_types_with_qr_tokens,
  count(distinct qr_token) as unique_qr_tokens
from public.service_types
where is_active;

select
  column_name,
  data_type,
  is_nullable,
  column_default
from information_schema.columns
where table_schema = 'public'
  and table_name = 'service_qr_sessions'
  and column_name in ('started_via', 'updated_at')
order by column_name;

select
  roles.name as role_name,
  bool_or(
    role_permissions.permission_key = 'services.manage_recurring'
  ) as sees_recurring_oversight,
  bool_or(
    role_permissions.permission_key = 'services.track_live'
  ) as can_track_live_seva,
  bool_or(
    role_permissions.permission_key = 'services.self_log'
  ) as legacy_self_log_still_enabled
from public.roles
left join public.role_permissions
  on role_permissions.role_id = roles.id
group by roles.name
order by case roles.name
  when 'president' then 1
  when 'tech' then 2
  when 'core' then 3
  when 'volunteer' then 4
  when 'devotee' then 5
end;

select
  tablename,
  policyname,
  cmd
from pg_policies
where schemaname = 'public'
  and tablename in (
    'service_qr_sessions',
    'service_assignments',
    'service_template_assignees',
    'recurring_service_interests',
    'app_notifications'
  )
order by tablename, policyname;

select
  tablename,
  exists (
    select 1
    from pg_publication_tables as published
    where published.pubname = 'supabase_realtime'
      and published.schemaname = 'public'
      and published.tablename = requested.tablename
  ) as realtime_enabled
from (
  values
    ('service_qr_sessions'),
    ('recurring_service_interests'),
    ('app_notifications')
) as requested(tablename);
