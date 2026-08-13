-- Verifies 202608040010_rpc_execution_hardening.sql.
-- Run in Supabase Dashboard -> SQL Editor after applying the migration.
-- The final row must read: rpc execution hardening verification passed

do $$
declare
  anon_executable text[];
  authenticated_internal text[];
  qr_column_grants integer;
  missing_policy_helpers text[];
  missing_client_rpcs text[];
begin
  -- 1. `anon` must not be able to execute anything in public.
  select coalesce(array_agg(routines.routine_name order by routines.routine_name), '{}')
  into anon_executable
  from information_schema.routine_privileges as routines
  where routines.specific_schema = 'public'
    and routines.grantee = 'anon'
    and routines.privilege_type = 'EXECUTE';

  if cardinality(anon_executable) > 0 then
    raise exception 'anon can still execute: %', array_to_string(anon_executable, ', ');
  end if;

  -- 2. Internal helpers must not be reachable by a signed-in client either.
  select coalesce(array_agg(routines.routine_name order by routines.routine_name), '{}')
  into authenticated_internal
  from information_schema.routine_privileges as routines
  where routines.specific_schema = 'public'
    and routines.grantee = 'authenticated'
    and routines.privilege_type = 'EXECUTE'
    and routines.routine_name in (
      'queue_app_notification',
      'notify_service_oversight',
      'refresh_service_instance_capacity',
      'finalize_service_session_internal',
      'generate_service_instances',
      'log_completed_service',
      'start_service_session',
      'add_service_type',
      'cancel_qr_service_session',
      'complete_qr_service_session',
      'cancel_service_instance',
      'create_service_template'
    );

  if cardinality(authenticated_internal) > 0 then
    raise exception 'authenticated can still execute internal helpers: %',
      array_to_string(authenticated_internal, ', ');
  end if;

  -- 3. qr_token must be off the authenticated grant.
  select count(*) into qr_column_grants
  from information_schema.column_privileges
  where table_schema = 'public'
    and table_name = 'service_types'
    and column_name = 'qr_token'
    and grantee in ('authenticated', 'anon');

  if qr_column_grants > 0 then
    raise exception 'qr_token is still readable by authenticated or anon.';
  end if;

  -- 4. RLS policy helpers must remain executable or every read breaks.
  select coalesce(array_agg(needed.name order by needed.name), '{}')
  into missing_policy_helpers
  from (values
    ('has_permission'),
    ('can_view_service_instance'),
    ('can_view_service_template')
  ) as needed(name)
  where not exists (
    select 1 from information_schema.routine_privileges as routines
    where routines.specific_schema = 'public'
      and routines.grantee = 'authenticated'
      and routines.privilege_type = 'EXECUTE'
      and routines.routine_name = needed.name
  );

  if cardinality(missing_policy_helpers) > 0 then
    raise exception 'RLS helper lost EXECUTE for authenticated: %',
      array_to_string(missing_policy_helpers, ', ');
  end if;

  -- 5. Every RPC the app calls must still be executable by a signed-in user.
  select coalesce(array_agg(needed.name order by needed.name), '{}')
  into missing_client_rpcs
  from (values
    ('complete_my_service_assignment'), ('complete_service_instance'),
    ('create_access_request'),
    ('create_service_requirement'), ('create_service_template_v2'),
    ('delete_seva_registration'),
    ('delete_service_activity'), ('delete_service_assignment_activity'),
    ('delete_service_requirement'), ('delete_service_template'),
    ('join_service_instance'), ('join_weekly_service'),
    ('leave_service_instance'), ('list_service_devotees'),
    ('list_service_qr_tokens'), ('list_seva_verifiers'),
    ('list_temple_presence_today'),
    ('offer_service_coverage'), ('offer_service_coverage_range'),
    ('offer_service_instance'), ('propose_weekly_offer_alternative'),
    ('register_device_push_token'),
    ('reopen_service_exception'),
    ('report_weekly_service_unavailable'), ('request_seva_verification'),
    ('resend_seva_verification'), ('respond_to_coverage_range_offer'),
    ('respond_to_service_offer'), ('respond_to_seva_verification'),
    ('respond_to_weekly_offer_counter'), ('review_access_request'),
    ('review_recurring_service_interest'), ('set_my_temple_presence'),
    ('set_service_template_active'),
    ('submit_recurring_service_interest'),
    ('update_service_template_v2')
  ) as needed(name)
  where not exists (
    select 1 from information_schema.routine_privileges as routines
    where routines.specific_schema = 'public'
      and routines.grantee = 'authenticated'
      and routines.privilege_type = 'EXECUTE'
      and routines.routine_name = needed.name
  );

  if cardinality(missing_client_rpcs) > 0 then
    raise exception 'client RPC lost EXECUTE for authenticated: %',
      array_to_string(missing_client_rpcs, ', ');
  end if;
end;
$$;

-- The live timer was removed from the product: seva is registered from the
-- catalogue or a temple QR scan, never by running a clock. These must stay
-- unreachable, and report_service_unavailable with them — it predated the
-- grouped unavailability columns and could only ever raise.
do $$
declare
  still_reachable text[];
begin
  select coalesce(array_agg(distinct retired.name order by retired.name), '{}')
  into still_reachable
  from (values
    ('cancel_service_session'), ('complete_service_session'),
    ('complete_due_service_sessions'),
    ('start_list_service_session'), ('start_planned_qr_service_session'),
    ('start_planned_service_session'), ('start_qr_service_session'),
    ('report_service_unavailable')
  ) as retired(name)
  where exists (
    select 1 from information_schema.routine_privileges as routines
    where routines.specific_schema = 'public'
      and routines.grantee in ('authenticated', 'anon', 'PUBLIC')
      and routines.privilege_type = 'EXECUTE'
      and routines.routine_name = retired.name
  );

  if cardinality(still_reachable) > 0 then
    raise exception 'retired RPC is still callable by clients: %',
      array_to_string(still_reachable, ', ');
  end if;
end;
$$;

select 'rpc execution hardening verification passed' as result;
