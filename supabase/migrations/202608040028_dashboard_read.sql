-- One read for the whole Seva tab.
--
-- The tab was built from twelve table reads in six sequential waves. Two
-- problems came with that:
--
--  1. Every child table was bounded by a row cap (5000 assignments, 2000
--     offers, 1000 exceptions) rather than by the date window. Newest-first
--     ordering means that once a temple passes those counts, rows *inside* the
--     window start disappearing — a seva from three months ago quietly loses
--     its participants. Silent truncation is the worst kind of scale bug: the
--     screen still looks right.
--  2. Six waves of round trips is six chances for a flaky connection to fail,
--     and six times the latency.
--
-- This returns exactly the same row shapes the app already assembles, scoped
-- to the window instead of capped, in one trip. It is SECURITY INVOKER, so
-- row-level security applies precisely as it did before — a devotee sees no
-- more here than they saw across the twelve reads.
-- Requires 202608040027_attendance.sql.

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
    select * from public.service_instances
    where date >= history_from
  )
  select jsonb_build_object(
    'historyFrom', history_from,

    'serviceTypes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', id, 'name', name, 'category', category, 'is_active', is_active
      ) order by category, name)
      from public.service_types where is_active
    ), '[]'::jsonb),

    'instances', coalesce((
      select jsonb_agg(to_jsonb(instances) order by instances.date, instances.start_time)
      from windowed_instances instances
    ), '[]'::jsonb),

    -- Scoped to the window rather than capped, so no participant is ever
    -- silently missing from a seva the tab is showing.
    'assignments', coalesce((
      select jsonb_agg(to_jsonb(assignments))
      from public.service_assignments assignments
      where assignments.service_instance_id in (select id from windowed_instances)
    ), '[]'::jsonb),

    -- An offer may hang off an instance, a template, or neither (a coverage
    -- plan), so only the instance-bound ones are narrowed by the window.
    'offers', coalesce((
      select jsonb_agg(to_jsonb(offers))
      from public.service_offers offers
      where offers.service_instance_id is null
         or offers.service_instance_id in (select id from windowed_instances)
    ), '[]'::jsonb),

    'templates', coalesce((
      select jsonb_agg(to_jsonb(templates)
        order by templates.active desc, templates.day_of_week, templates.start_time)
      from public.service_templates templates
    ), '[]'::jsonb),

    'templateAssignees', coalesce((
      select jsonb_agg(to_jsonb(assignees))
      from public.service_template_assignees assignees
    ), '[]'::jsonb),

    'exceptions', coalesce((
      select jsonb_agg(to_jsonb(exceptions))
      from public.service_exceptions exceptions
      where exceptions.service_instance_id in (select id from windowed_instances)
    ), '[]'::jsonb),

    'coveragePlans', coalesce((
      select jsonb_agg(to_jsonb(plans))
      from public.service_coverage_plans plans
      where plans.date_to is null or plans.date_to >= history_from
    ), '[]'::jsonb),

    'interests', coalesce((
      select jsonb_agg(to_jsonb(interests) order by interests.submitted_at desc)
      from public.recurring_service_interests interests
      where interests.status = 'pending' or interests.submitted_at >= history_from
    ), '[]'::jsonb),

    'verifications', coalesce((
      select jsonb_agg(to_jsonb(verifications) order by verifications.created_at desc)
      from public.service_verifications verifications
      where verifications.start_at >= history_from
    ), '[]'::jsonb),

    'counters', coalesce((
      select jsonb_agg(to_jsonb(counters) order by counters.created_at desc)
      from public.service_offer_counters counters
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

-- ---------------------------------------------------------------------------
-- Indexes the window scoping leans on. Without these the sub-selects above
-- become sequential scans as the temple's history grows.
-- ---------------------------------------------------------------------------

create index if not exists service_instances_date_idx
  on public.service_instances(date);
create index if not exists service_assignments_instance_idx
  on public.service_assignments(service_instance_id);
create index if not exists service_offers_instance_idx
  on public.service_offers(service_instance_id);
create index if not exists service_exceptions_instance_idx
  on public.service_exceptions(service_instance_id);
create index if not exists service_verifications_start_idx
  on public.service_verifications(start_at desc);

do $$
begin
  raise notice 'seva dashboard read applied';
end;
$$;
