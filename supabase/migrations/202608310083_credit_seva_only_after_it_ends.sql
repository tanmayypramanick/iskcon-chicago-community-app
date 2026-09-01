-- Seva is credited only once it has actually happened.
-- Requires 202608040059_seva_mala_fairness.sql.
--
-- public.seva_mala_acts bounded its rows on `instances.date <=
-- seva_mala_today()` — the DATE, with no end-time check — and raw_minutes
-- falls back to planned_minutes whatever the status. So from midnight, every
-- seva scheduled later that day was already counted at its full planned
-- length: hours served, Seva Mala points, and the President's balance view
-- all included seva nobody had begun.
--
-- This is the same function, with one condition added: the seva's Chicago end
-- instant must have passed. Chicago and only Chicago, so the answer does not
-- move with the reader's device.

create or replace function public.seva_mala_acts(p_devotee_id uuid default null)
returns table (
  assignment_id uuid,
  devotee_id uuid,
  service_instance_id uuid,
  service_type_id uuid,
  seva_name text,
  occurred_on date,
  started_at_local time,
  planned_minutes integer,
  actual_minutes integer,
  raw_minutes numeric,
  quality numeric,
  weight numeric,
  day_factor numeric,
  week_factor numeric,
  credited_minutes numeric,
  weighted_minutes numeric,
  assignment_status text,
  verification text,
  attendance text,
  is_recurring boolean,
  points_status text
)
language sql
stable
security definer
set search_path = ''
as $$
  with caps as (
    select
      public.seva_mala_number('seva_mala.daily_cap_minutes', 480) as day_cap,
      public.seva_mala_number('seva_mala.weekly_cap_minutes', 1800) as week_cap
  ),
  base as (
    select
      assignments.id as assignment_id,
      assignments.devotee_id,
      instances.id as service_instance_id,
      instances.service_type_id,
      public.service_instance_name(instances) as seva_name,
      instances.date as occurred_on,
      instances.start_time as started_at_local,
      instances.duration_minutes as planned_minutes,
      coalesce(session.actual_minutes, verified.actual_minutes) as actual_minutes,
      assignments.status as assignment_status,
      assignments.verification,
      assignments.attendance,
      instances.template_id is not null as is_recurring,
      public.seva_points_status(
        assignments.status, assignments.attendance, assignments.verification,
        instances.template_id is not null
      ) as points_status,
      case
        when public.seva_points_status(
               assignments.status, assignments.attendance, assignments.verification,
               instances.template_id is not null
             ) <> 'counted' then 0
        when assignments.verification = 'live_timer'
          and coalesce(session.auto_completed, false) then 0.7
        else 1.0
      end::numeric as quality,
      coalesce(weights.weight, 1.0) as weight
    from public.service_assignments assignments
    join public.service_instances instances
      on instances.id = assignments.service_instance_id
    left join public.seva_type_weights weights
      on weights.service_type_id = instances.service_type_id
    left join lateral (
      select
        ceil(
          extract(epoch from (sessions.completed_at - sessions.started_at)) / 60.0
        )::integer as actual_minutes,
        sessions.auto_completed
      from public.service_qr_sessions sessions
      where sessions.service_instance_id = instances.id
        and sessions.status = 'completed'
        and sessions.devotee_id = assignments.devotee_id
      order by sessions.completed_at desc
      limit 1
    ) session on true
    left join lateral (
      select
        ceil(
          extract(epoch from (verifications.end_at - verifications.start_at)) / 60.0
        )::integer as actual_minutes
      from public.service_verifications verifications
      where verifications.service_instance_id = instances.id
        and verifications.devotee_id = assignments.devotee_id
        and verifications.status = 'verified'
      order by verifications.responded_at desc nulls last
      limit 1
    ) verified on true
    where instances.status <> 'cancelled'
      and instances.date <= public.seva_mala_today()
      -- The seva must have actually HAPPENED. The date alone let a seva that
      -- had not started count its planned minutes: at nine in the morning a
      -- devotee already saw tonight's seven o'clock arati in "This week",
      -- "This month" and "All time", and the President saw it in their
      -- balance. raw_minutes falls back to planned_minutes regardless of
      -- status, so nothing downstream caught it.
      --
      -- Two ways to have happened, and both are needed. A seva marked
      -- completed HAS been served, whatever the clock says — 0070 already
      -- refuses to mark one completed before its window opens, so the status
      -- is trustworthy, and a seva that finished early would otherwise be
      -- withheld from the devotee who served it. Otherwise the bar is the
      -- Chicago end instant, and Chicago only, so the answer does not move
      -- with the reader's device.
      and (
        instances.status = 'completed'
        or ((instances.date + instances.start_time) at time zone 'America/Chicago')
             + make_interval(mins => coalesce(instances.duration_minutes, 0))
           <= now()
      )
      and (p_devotee_id is null or assignments.devotee_id = p_devotee_id)
  ),
  measured as (
    select
      base.*,
      greatest(
        0,
        least(
          base.planned_minutes,
          coalesce(base.actual_minutes, base.planned_minutes)
        )
      )::numeric as raw_minutes
    from base
  ),
  -- Only work that earns something spends the cap.
  billable as (
    select
      measured.*,
      case when measured.quality > 0 then measured.raw_minutes else 0 end as cap_basis
    from measured
  ),
  by_day as (
    select
      billable.devotee_id,
      billable.occurred_on,
      sum(billable.cap_basis) as day_minutes
    from billable
    group by 1, 2
  ),
  day_factors as (
    select
      by_day.devotee_id,
      by_day.occurred_on,
      case
        when by_day.day_minutes > caps.day_cap then caps.day_cap / by_day.day_minutes
        else 1.0
      end as day_factor
    from by_day cross join caps
  ),
  by_week as (
    select
      day_factors.devotee_id,
      public.seva_mala_week_start(day_factors.occurred_on) as week_start,
      sum(by_day.day_minutes * day_factors.day_factor) as week_minutes
    from day_factors
    join by_day
      on by_day.devotee_id = day_factors.devotee_id
     and by_day.occurred_on = day_factors.occurred_on
    group by 1, 2
  ),
  week_factors as (
    select
      by_week.devotee_id,
      by_week.week_start,
      case
        when by_week.week_minutes > caps.week_cap then caps.week_cap / by_week.week_minutes
        else 1.0
      end as week_factor
    from by_week cross join caps
  )
  select
    billable.assignment_id,
    billable.devotee_id,
    billable.service_instance_id,
    billable.service_type_id,
    billable.seva_name,
    billable.occurred_on,
    billable.started_at_local,
    billable.planned_minutes,
    billable.actual_minutes,
    billable.raw_minutes,
    billable.quality,
    billable.weight,
    day_factors.day_factor,
    week_factors.week_factor,
    billable.cap_basis * day_factors.day_factor * week_factors.week_factor,
    billable.raw_minutes * billable.quality * billable.weight
      * day_factors.day_factor * week_factors.week_factor,
    billable.assignment_status,
    billable.verification,
    billable.attendance,
    billable.is_recurring,
    billable.points_status
  from billable
  join day_factors
    on day_factors.devotee_id = billable.devotee_id
   and day_factors.occurred_on = billable.occurred_on
  join week_factors
    on week_factors.devotee_id = billable.devotee_id
   and week_factors.week_start = public.seva_mala_week_start(billable.occurred_on)
$$;

-- ---------------------------------------------------------------------------
-- Proof, run at migration time.
-- ---------------------------------------------------------------------------
do $$
declare
  -- Seeded, not borrowed: reading an existing devotee made this proof
  -- early-return on every database without a congregation, so it passed
  -- locally while never actually running.
  v_devotee uuid := '70000000-0000-0000-0000-000000000001';
  v_type uuid;
  v_instance uuid;
  v_counted integer;
begin
  insert into auth.users (id, email, raw_user_meta_data)
  values (v_devotee, 'credit-proof@example.test',
          jsonb_build_object('name', 'Credit Proof Devotee'));

  insert into public.service_types (name, category)
  values ('Credit Proof Seva', 'other')
  returning id into v_type;

  -- A seva later TODAY, which therefore has not happened yet.
  insert into public.service_instances
    (service_type_id, date, start_time, duration_minutes, slots_needed,
     participation_mode, status, posted_by)
  values
    (v_type, public.seva_mala_today(), time '23:30', 60, 1,
     'open', 'open', v_devotee)
  returning id into v_instance;

  insert into public.service_assignments
    (service_instance_id, devotee_id, assignment_method, status)
  values (v_instance, v_devotee, 'self_joined', 'confirmed');

  select count(*)::integer into v_counted
  from public.seva_mala_acts(v_devotee) acts
  where acts.service_instance_id = v_instance;

  if v_counted <> 0 then
    delete from public.service_assignments where service_instance_id = v_instance;
    delete from public.service_instances where id = v_instance;
    delete from public.service_types where id = v_type;
    delete from auth.users where id = v_devotee;
    raise exception
      'a seva at 23:30 today was credited before it happened (% rows)', v_counted;
  end if;

  -- And the control, so the rule is pinned in both directions: the same seva,
  -- once marked completed, IS credited. A seva that finished early must not be
  -- withheld from the devotee who served it.
  update public.service_instances
  set status = 'completed'
  where id = v_instance;
  update public.service_assignments
  set status = 'completed', attendance = 'served'
  where service_instance_id = v_instance;

  select count(*)::integer into v_counted
  from public.seva_mala_acts(v_devotee) acts
  where acts.service_instance_id = v_instance;

  delete from public.service_assignments where service_instance_id = v_instance;
  delete from public.service_instances where id = v_instance;
  delete from public.service_types where id = v_type;
  delete from auth.users where id = v_devotee;

  if v_counted <> 1 then
    raise exception
      'a completed seva was not credited (% rows); early finishes are being withheld',
      v_counted;
  end if;

  raise notice 'seva is credited once it has happened, and not before';
end;
$$;
