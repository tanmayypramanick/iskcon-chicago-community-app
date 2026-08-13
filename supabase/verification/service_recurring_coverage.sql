-- Run after 202608020003_service_recurring_coverage.sql.
-- These checks are read-only and do not create a recurring service.

select
  to_regclass('public.service_templates') as service_templates,
  to_regclass('public.service_template_assignees') as service_template_assignees,
  to_regclass('public.service_exceptions') as service_exceptions;

select column_name, is_nullable, data_type
from information_schema.columns
where table_schema = 'public'
  and table_name = 'service_offers'
  and column_name in (
    'service_instance_id',
    'service_template_id',
    'service_exception_id',
    'offer_kind'
  )
order by ordinal_position;

select routine_name
from information_schema.routines
where routine_schema = 'public'
  and routine_name in (
    'generate_service_instances',
    'create_service_template',
    'report_service_unavailable',
    'reopen_service_exception',
    'offer_service_coverage',
    'respond_to_service_offer',
    'set_service_template_active'
  )
order by routine_name;

select schemaname, tablename, policyname
from pg_policies
where schemaname = 'public'
  and tablename in (
    'service_templates',
    'service_template_assignees',
    'service_exceptions'
  )
order by tablename, policyname;

select tablename
from pg_publication_tables
where pubname = 'supabase_realtime'
  and schemaname = 'public'
  and tablename in (
    'service_templates',
    'service_template_assignees',
    'service_exceptions'
  )
order by tablename;
