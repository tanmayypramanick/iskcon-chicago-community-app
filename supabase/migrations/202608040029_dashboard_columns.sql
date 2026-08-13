-- The dashboard read names its columns.
--
-- 0028 built the payload with to_jsonb(row), which returns whatever columns
-- happen to exist. Nothing sensitive is exposed today — but the moment someone
-- adds a private note, a phone number or a token to any of these tables, it
-- starts flowing to every signed-in device with no code change and no review.
-- That is exactly how the qr_token leak happened before: a select that took
-- more than it needed.
--
-- Naming the columns makes the payload a deliberate contract. Adding a column
-- to a table no longer changes what the app receives; someone has to come here
-- and decide.
-- Requires 202608040028_dashboard_read.sql.

create or replace function public.seva_dashboard(
  p_history_days integer default 180
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  history_from date;
  payload jsonb;
begin
  if auth.uid() is null then
    raise exception 'Sign in to load seva.';
  end if;

  history_from := (now() at time zone 'America/Chicago')::date
    - least(greatest(coalesce(p_history_days, 180), 1), 365);

  with windowed_instances as (
    select
      id, template_id, service_type_id, custom_name, date, start_time,
      duration_minutes, slots_needed, participation_mode, posted_by, status,
      created_at
    from public.service_instances
    where date >= history_from
  )
  select jsonb_build_object(
    'historyFrom', history_from,

    -- qr_token is deliberately absent. Reading it client-side let any devotee
    -- replay a temple code from anywhere and earn the stronger verification.
    'serviceTypes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', id, 'name', name, 'category', category, 'is_active', is_active
      ) order by category, name)
      from public.service_types where is_active
    ), '[]'::jsonb),

    'instances', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', id, 'template_id', template_id,
        'service_type_id', service_type_id, 'custom_name', custom_name,
        'date', date, 'start_time', start_time,
        'duration_minutes', duration_minutes, 'slots_needed', slots_needed,
        'participation_mode', participation_mode, 'posted_by', posted_by,
        'status', status, 'created_at', created_at
      ) order by date, start_time)
      from windowed_instances
    ), '[]'::jsonb),

    -- Scoped to the window rather than capped, so no participant is ever
    -- silently missing from a seva the tab is showing.
    'assignments', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', id, 'service_instance_id', service_instance_id,
        'devotee_id', devotee_id, 'assignment_method', assignment_method,
        'assigned_by', assigned_by, 'status', status,
        'verification', verification, 'attendance', attendance,
        'qr_scanned_at', qr_scanned_at, 'created_at', created_at,
        'completed_at', completed_at
      ))
      from public.service_assignments
      where service_instance_id in (select id from windowed_instances)
    ), '[]'::jsonb),

    -- An offer may hang off an instance, a template, or neither (a coverage
    -- plan), so only the instance-bound ones are narrowed by the window.
    'offers', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', id, 'service_instance_id', service_instance_id,
        'service_template_id', service_template_id,
        'service_exception_id', service_exception_id,
        'service_coverage_plan_id', service_coverage_plan_id,
        'offered_to', offered_to, 'offered_by', offered_by,
        'offer_kind', offer_kind, 'status', status,
        'created_at', created_at, 'responded_at', responded_at
      ))
      from public.service_offers
      where service_instance_id is null
         or service_instance_id in (select id from windowed_instances)
    ), '[]'::jsonb),

    'templates', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', id, 'service_type_id', service_type_id,
        'custom_name', custom_name, 'day_of_week', day_of_week,
        'days_of_week', days_of_week, 'start_time', start_time,
        'duration_minutes', duration_minutes, 'slots_needed', slots_needed,
        'participation_mode', participation_mode, 'start_date', start_date,
        'end_date', end_date, 'created_by', created_by, 'active', active,
        'created_at', created_at, 'updated_at', updated_at
      ) order by active desc, day_of_week, start_time)
      from public.service_templates
    ), '[]'::jsonb),

    'templateAssignees', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', id, 'service_template_id', service_template_id,
        'devotee_id', devotee_id, 'assigned_by', assigned_by,
        'status', status, 'days_of_week', days_of_week,
        'created_at', created_at, 'updated_at', updated_at
      ))
      from public.service_template_assignees
    ), '[]'::jsonb),

    'exceptions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', id, 'service_instance_id', service_instance_id,
        'devotee_id', devotee_id, 'reason', reason, 'status', status,
        'resolution_kind', resolution_kind,
        'substitute_devotee_id', substitute_devotee_id,
        'created_at', created_at, 'resolved_at', resolved_at,
        'resolved_by', resolved_by, 'request_group_id', request_group_id,
        'unavailable_scope', unavailable_scope,
        'unavailable_from', unavailable_from, 'unavailable_to', unavailable_to,
        'unavailable_days', unavailable_days
      ))
      from public.service_exceptions
      where service_instance_id in (select id from windowed_instances)
    ), '[]'::jsonb),

    'coveragePlans', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', id, 'service_exception_id', service_exception_id,
        'request_group_id', request_group_id,
        'service_template_id', service_template_id,
        'original_devotee_id', original_devotee_id,
        'substitute_devotee_id', substitute_devotee_id,
        'scope', scope, 'date_from', date_from, 'date_to', date_to,
        'days_of_week', days_of_week, 'status', status,
        'created_by', created_by, 'created_at', created_at,
        'responded_at', responded_at
      ))
      from public.service_coverage_plans
      where date_to is null or date_to >= history_from
    ), '[]'::jsonb),

    'interests', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', id, 'devotee_id', devotee_id, 'skills', skills,
        'desired_service_type_ids', desired_service_type_ids,
        'other_service', other_service, 'availability', availability,
        'currently_serving', currently_serving,
        'current_service_details', current_service_details,
        'status', status, 'submitted_at', submitted_at,
        'updated_at', updated_at, 'reviewed_at', reviewed_at,
        'reviewed_by', reviewed_by, 'review_note', review_note
      ) order by submitted_at desc)
      from public.recurring_service_interests
      where status = 'pending' or submitted_at >= history_from
    ), '[]'::jsonb),

    'verifications', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', id, 'devotee_id', devotee_id,
        'service_type_id', service_type_id, 'custom_name', custom_name,
        'start_at', start_at, 'end_at', end_at,
        'location_text', location_text, 'verifier_id', verifier_id,
        'status', status, 'review_note', review_note,
        'service_instance_id', service_instance_id,
        'verified_by', verified_by, 'created_at', created_at,
        'responded_at', responded_at
      ) order by created_at desc)
      from public.service_verifications
      where start_at >= history_from
    ), '[]'::jsonb),

    'counters', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', id, 'service_offer_id', service_offer_id,
        'devotee_id', devotee_id, 'proposed_days', proposed_days,
        'proposed_date', proposed_date,
        'proposed_start_time', proposed_start_time,
        'proposed_duration_minutes', proposed_duration_minutes,
        'note', note, 'status', status, 'review_note', review_note,
        'created_at', created_at, 'responded_at', responded_at,
        'responded_by', responded_by
      ) order by created_at desc)
      from public.service_offer_counters
    ), '[]'::jsonb),

    'devotees', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', devotees.id, 'name', devotees.name,
        'photo_url', devotees.photo_url, 'role_name', devotees.role_name
      ) order by devotees.name)
      from public.list_service_devotees() devotees
    ), '[]'::jsonb)
  ) into payload;

  return payload;
end;
$$;

revoke all on function public.seva_dashboard(integer) from public, anon;
grant execute on function public.seva_dashboard(integer) to authenticated;

do $$
begin
  raise notice 'seva dashboard columns applied';
end;
$$;
