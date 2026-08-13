-- Run after 202608020005_service_qr_and_cancel.sql.

select
  to_regclass('public.service_qr_sessions') as service_qr_sessions,
  to_regprocedure('public.start_qr_service_session(text)') as start_qr_rpc,
  to_regprocedure('public.complete_qr_service_session(uuid)') as complete_qr_rpc,
  to_regprocedure('public.cancel_qr_service_session(uuid)') as cancel_qr_rpc,
  to_regprocedure('public.cancel_service_instance(uuid)') as cancel_service_rpc;

select
  count(*) as active_service_types,
  count(qr_token) as service_types_with_qr_tokens,
  count(distinct qr_token) as unique_qr_tokens
from public.service_types
where is_active;

select schemaname, tablename, policyname
from pg_policies
where schemaname = 'public'
  and tablename = 'service_qr_sessions';
