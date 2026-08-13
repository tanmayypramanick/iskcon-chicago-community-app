-- Points are earned, not assumed.
--
-- The temple has narrowed what earns Sevā Mālā points to one sentence:
--
--   "Seva points will only be gained when the seva is marked completed, and
--    someone verified it, and the president / tech admin / the one who posted
--    the seva has marked them served. Only then are points gained."
--
-- 202608040055_seva_mala.sql gave a self-reported act with no attendance mark
-- a 0.6 multiplier — six tenths of a point for "I say I was there". That is
-- the branch this migration deletes. Three things must now all be true:
--
--   1. completed        service_assignments.status = 'completed'. 0055 keys the
--                       act on the assignment, not the instance, because a
--                       coordinator closing a seva closes every assignment on
--                       it (202608040023) while an instance can be 'completed'
--                       with a devotee still sitting at 'assigned'.
--   2. verified         service_assignments.verification is live_timer, qr_scan
--                       or member_verified. Bare self_report is not verification,
--                       it is a claim. Whitelisted rather than "anything but
--                       self_report", so a verification level invented by a
--                       later migration is untrusted until somebody says it is.
--   3. served           service_assignments.attendance = 'served', which
--                       202608040027 lets only the devotee who posted the seva
--                       or a holder of app.view_all — the President and the
--                       Tech Admin — record.
--
-- Anything short of all three earns nothing at all. Not a fraction: nothing.
--
-- ---------------------------------------------------------------------------
-- The consequence, and why half this file is about saying so out loud.
--
-- service_assignments.attendance is nullable, has been nullable since it was
-- added, and nothing in the app has ever prompted anybody to fill it in. On
-- today's data almost every act in the temple's history would score zero. That
-- is a correct implementation of what was asked and a terrible thing to ship
-- silently: four hundred devotees open the app, see nothing where their seva
-- used to be, and conclude the temple lost it.
--
-- So the un-awarded state is made legible instead of invisible. Every act
-- carries a points_status, in the order the workflow actually unblocks:
--
--   not_served              somebody said they were not there, or they withdrew
--                           or were marked a no-show. Terminal. Nobody is
--                           waiting on anybody.
--   awaiting_completion     the seva has not been closed out. The poster, a
--                           Tech Admin or the President closes it.
--   awaiting_verification   only the devotee says it happened. A timer, a QR
--                           scan or another devotee's verification fixes it.
--   awaiting_confirmation   everything is in place and nobody has said "served".
--                           This is the common one, and the one the temple must
--                           see: it is a queue, not a verdict.
--   counted                 all three, and points were earned.
--
-- Hours are NOT withheld. A pending act keeps its minutes, its day, its name
-- and its place in the devotee's history; only the points wait. That is the
-- difference between "we are still confirming this" and "this never happened",
-- and a devotee can tell which they are looking at.
--
-- Five reads come out of that:
--
--   my_seva_mala              gains pending_acts and pending_minutes, so the
--                             devotee's own standing says how much is waiting
--   my_seva_profile           week / month / year, seva hours split by whether
--                             they counted, with the devotee's own giving
--                             beside them
--   my_seva_breakdown         the same three windows, per kind of seva
--   my_seva_acts              act by act, with the reason in words
--   list_seva_awaiting_...    the queue, for whoever can actually clear it
--
-- ---------------------------------------------------------------------------
-- And one write, because the rule as asked for is otherwise unsatisfiable.
--
-- Requiring a trustworthy verification level uncovered a hole nobody had reason
-- to notice while self_report was worth 0.6. Every path that sets verification
-- above self_report — the QR scan in 202608020005, the live timer in
-- 202608030007 and 202608030008, the member verification in 202608040012 and
-- 202608040014 — CREATES ITS OWN service_instance. Not one of them touches an
-- assignment that already exists. Grep the whole schema for an UPDATE that
-- raises service_assignments.verification and there is none.
--
-- Which means: seva a devotee joined, seva they were offered and accepted, and
-- every recurring assignment that 202608030009 generates from a template, all
-- sit at self_report forever, with no action available to anybody that could
-- ever move them. Shipping the rule without a way to satisfy it would not have
-- tightened the temple's points, it would have abolished them for every kind of
-- seva except the ones a devotee logs against themselves — which are precisely
-- the ones the temple trusts least.
--
-- So verify_seva_assignment, in section 9: the poster of the seva, the
-- President or the Tech Admin says out loud that it happened, and somebody who
-- is not the devotee themselves. That is "someone verified it" for seva that
-- was posted rather than self-logged, and it is what lets weekly seva count.
--
-- Requires 202608040055_seva_mala.sql.

-- ---------------------------------------------------------------------------
-- 0. The ground this stands on.
--
--    Every one of these is a thing a later migration could move, and a scoring
--    rule that is silently wrong is worse than one that is loudly broken.
-- ---------------------------------------------------------------------------

do $$
declare
  v_definition text;
  v_source text;
  v_holders text;
begin
  if to_regprocedure('public.seva_mala_acts(uuid)') is null then
    raise exception
      'public.seva_mala_acts is missing; apply 202608040055_seva_mala.sql first.';
  end if;

  select pg_get_constraintdef(pg_constraint.oid) into v_definition
  from pg_constraint
  where conname = 'service_assignment_attendance_check'
    and conrelid = 'public.service_assignments'::regclass;
  if v_definition is null
    or position('''served''' in v_definition) = 0
    or position('''absent''' in v_definition) = 0
    or position('''excused''' in v_definition) = 0
  then
    raise exception
      'service_assignments.attendance is not the served/absent/excused column 202608040027 left behind.';
  end if;

  select pg_get_constraintdef(pg_constraint.oid) into v_definition
  from pg_constraint
  where conname = 'service_assignments_verification_check'
    and conrelid = 'public.service_assignments'::regclass;
  if v_definition is null
    or position('''self_report''' in v_definition) = 0
    or position('''live_timer''' in v_definition) = 0
    or position('''qr_scan''' in v_definition) = 0
    or position('''member_verified''' in v_definition) = 0
  then
    raise exception
      'service_assignments.verification is not the four levels 202608040012 left behind.';
  end if;

  -- "Marked them served" means exactly the authority 0027 grants. If a later
  -- migration widens who may record attendance, it has widened who may hand out
  -- points, and it should have to come here and say so.
  select pg_get_functiondef('public.record_seva_attendance(uuid, text)'::regprocedure)
  into v_source;
  if position('app.view_all' in v_source) = 0
    or position('posted_by' in v_source) = 0
  then
    raise exception
      'record_seva_attendance no longer restricts attendance to the poster and app.view_all.';
  end if;

  select string_agg(roles.name, ',' order by roles.name) into v_holders
  from public.role_permissions
  join public.roles on roles.id = role_permissions.role_id
  where role_permissions.permission_key = 'app.view_all';
  if v_holders is distinct from 'president,tech' then
    raise exception
      'app.view_all is held by % — "the president / tech admin" means president, tech.', v_holders;
  end if;

  -- 0055 section 4: nobody but a definer function may read the components.
  if has_table_privilege('authenticated', 'public.period_scores', 'select') then
    raise exception 'authenticated can read period_scores.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 1. The rule, in one place.
--
--    Written once and called from everywhere, so the scoring and the screen
--    that explains the scoring cannot drift apart. Pure — three text values in,
--    one text value out — so it is immutable and can be used in an index or a
--    generated column later without anybody having to check.
--
--    The order of the branches is the order the temple unblocks them, and it is
--    load-bearing: an act that is both unclosed and unmarked reports the
--    earliest thing that has to happen, not whichever branch was typed first.
-- ---------------------------------------------------------------------------

create or replace function public.seva_points_status(
  p_assignment_status text,
  p_attendance text,
  p_verification text
)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    -- Terminal. Nobody is waiting on anybody.
    when p_assignment_status in ('no_show', 'withdrawn') then 'not_served'
    when p_attendance in ('absent', 'excused') then 'not_served'
    -- Waiting, in the order somebody can act on it.
    when p_assignment_status is distinct from 'completed' then 'awaiting_completion'
    when p_verification not in ('live_timer', 'qr_scan', 'member_verified')
      then 'awaiting_verification'
    when p_attendance is distinct from 'served' then 'awaiting_confirmation'
    else 'counted'
  end
$$;

comment on function public.seva_points_status(text, text, text) is
  'Whether one act of seva earned points, and if not, what is still owed: completion, verification, or somebody saying they were there. Completed, verified and served, or nothing.';

create or replace function public.seva_points_note(p_points_status text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case p_points_status
    when 'counted' then
      'Counted towards your Seva Mala.'
    when 'awaiting_completion' then
      'Waiting for this seva to be marked completed.'
    when 'awaiting_verification' then
      'Waiting to be verified. A timer, a QR scan or another devotee''s verification confirms it.'
    when 'awaiting_confirmation' then
      'Waiting for the temple to confirm you served. Your hours are recorded either way.'
    when 'not_served' then
      'Recorded as not served, so it earns no points.'
  end
$$;

comment on function public.seva_points_note(text) is
  'The sentence a devotee reads beside a seva that has not earned points yet. Never "it did not count" without saying who is meant to do what next.';

revoke all on function public.seva_points_status(text, text, text) from public, anon;
revoke all on function public.seva_points_note(text) from public, anon;
grant execute on function public.seva_points_status(text, text, text) to authenticated;
grant execute on function public.seva_points_note(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Every act, re-credited.
--
--    0055's function, with the eligibility rule replacing the quality ladder's
--    top three rungs and five columns added so the reason survives the trip to
--    the phone. Return shape changes, so it is dropped whole first: a leftover
--    overload with a defaulted argument becomes ambiguous, which has broken
--    this repository before.
--
--    What changed:
--
--      self_report with no attendance mark    0.6  ->  0     the temple's ask
--      live_timer that auto-completed, unmarked
--                                             0.7  ->  0     served is required
--                                                            of every act, not
--                                                            only of the ones
--                                                            nobody timed
--      live_timer that auto-completed, served      ->  0.7   still discounted;
--                                                            a timer nobody
--                                                            stopped is weaker
--                                                            evidence than a
--                                                            timer somebody did
--
--    The 0.7 survives because it is a QUALITY judgement, not an eligibility
--    one. Eligibility asks "did this happen"; quality asks "how well do we know
--    how long it took". An auto-completed timer that a coordinator has since
--    marked served happened — we are simply less sure of its length.
--
--    Everything else is 0055 unchanged, and deliberately so: raw_minutes is
--    still least(planned, actual), the caps are still a property of the Chicago
--    day and week, and a zero-quality act still spends no cap. That last one now
--    matters far more than it did: an act waiting to be confirmed must not eat
--    the eight hours the devotee genuinely served later the same day, or
--    confirming it on Thursday would move Tuesday's numbers down.
-- ---------------------------------------------------------------------------

drop function if exists public.seva_mala_acts(uuid);

create function public.seva_mala_acts(p_devotee_id uuid default null)
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
        assignments.status, assignments.attendance, assignments.verification
      ) as points_status,
      case
        when public.seva_points_status(
               assignments.status, assignments.attendance, assignments.verification
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

comment on function public.seva_mala_acts(uuid) is
  'Every past act of seva with its points_status, credited minutes, quality multiplier, scarcity weight and cap factors. Points require completed, verified and served together; hours are kept whatever the status. Windows nothing: the caps belong to the day and the week.';

revoke all on function public.seva_mala_acts(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. The windows a devotee's own profile is read in.
--
--    Week and month are 0055's, to the day, so a devotee comparing their
--    profile against their standing never sees two different weeks. Year is
--    Chicago's calendar year and is not a scoring period — nothing is ranked or
--    awarded over it — it is there because "how much seva have I done this
--    year" is a question people ask and nothing could answer.
-- ---------------------------------------------------------------------------

create or replace function public.seva_mala_windows()
returns table (
  window_kind text,
  window_start date,
  window_end date,
  window_order integer
)
language sql
stable
set search_path = ''
as $$
  select 'week'::text, public.seva_mala_week_start(public.seva_mala_today()),
         public.seva_mala_week_start(public.seva_mala_today()) + 6, 1
  union all
  select 'month'::text,
         date_trunc('month', public.seva_mala_today()::timestamp)::date,
         (date_trunc('month', public.seva_mala_today()::timestamp)
           + interval '1 month' - interval '1 day')::date, 2
  union all
  select 'year'::text,
         date_trunc('year', public.seva_mala_today()::timestamp)::date,
         (date_trunc('year', public.seva_mala_today()::timestamp)
           + interval '1 year' - interval '1 day')::date, 3
$$;

comment on function public.seva_mala_windows() is
  'This Chicago week, month and calendar year. Week and month are exactly 0055''s scoring periods; year is a reading window and is never ranked.';

revoke all on function public.seva_mala_windows() from public, anon;
grant execute on function public.seva_mala_windows() to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Your own standing, with what is still waiting on it.
--
--    0055's my_seva_mala plus two columns. They do not come from
--    public.period_scores — a devotee whose every act is waiting has no row
--    there at all, which is precisely the devotee who most needs to be told
--    why — so they are counted from the acts directly.
--
--    pending_minutes is minutes SERVED and waiting, not minutes credited: a
--    pending act has no credited minutes by construction, and reporting zero
--    would be answering a different question from the one being asked.
--
--    Return shape changes, so the old one is dropped by its full argument list.
-- ---------------------------------------------------------------------------

drop function if exists public.my_seva_mala(text);

create function public.my_seva_mala(p_period_kind text default 'week')
returns table (
  period_id uuid,
  period_kind text,
  period_start date,
  period_end date,
  score numeric,
  seva_minutes integer,
  seva_acts integer,
  pending_acts integer,
  pending_minutes integer,
  giving_cents bigint,
  gifts integer,
  standing integer,
  board_standing integer,
  cohort_size integer,
  gathering boolean,
  leaderboard_visible boolean,
  awards_earned integer
)
language sql
stable
security definer
set search_path = ''
as $$
  with target as (
    select periods.*
    from public.seva_mala_periods periods
    where periods.period_kind = p_period_kind
      and public.seva_mala_today() between periods.starts_on and periods.ends_on
    order by periods.starts_on desc
    limit 1
  ),
  minimum as (
    select public.seva_mala_number('seva_mala.minimum_cohort', 8) as cohort
  ),
  ranked as (
    select
      scores.*,
      dense_rank() over (order by scores.score desc)::integer as overall_standing
    from public.period_scores scores
    join target on target.id = scores.period_id
    where scores.score > 0
  ),
  board as (
    select
      scores.devotee_id,
      dense_rank() over (order by scores.score desc)::integer as board_standing
    from public.period_scores scores
    join target on target.id = scores.period_id
    join public.users on users.id = scores.devotee_id
    where scores.score > 0 and users.leaderboard_visible
  ),
  waiting as (
    select
      count(*)::integer as pending_acts,
      coalesce(sum(acts.raw_minutes), 0) as pending_minutes
    from target
    join public.seva_mala_acts(auth.uid()) acts
      on acts.occurred_on between target.starts_on and target.ends_on
    where acts.points_status in (
      'awaiting_completion', 'awaiting_verification', 'awaiting_confirmation'
    )
  )
  select
    target.id,
    target.period_kind,
    target.starts_on,
    target.ends_on,
    coalesce(ranked.score, 0),
    coalesce(round(ranked.credited_minutes), 0)::integer,
    coalesce(ranked.seva_acts, 0),
    coalesce(waiting.pending_acts, 0),
    coalesce(round(waiting.pending_minutes), 0)::integer,
    coalesce(ranked.giving_cents, 0),
    coalesce(ranked.gifts, 0),
    case when target.participant_count >= minimum.cohort then ranked.overall_standing end,
    case when target.participant_count >= minimum.cohort then board.board_standing end,
    target.participant_count,
    target.participant_count < minimum.cohort,
    users.leaderboard_visible,
    (
      select count(*)::integer from public.devotee_awards awards
      where awards.devotee_id = auth.uid()
        and (awards.period_id = target.id or awards.period_id is null)
    )
  from target
  cross join minimum
  cross join waiting
  join public.users on users.id = auth.uid()
  left join ranked on ranked.devotee_id = auth.uid()
  left join board on board.devotee_id = auth.uid()
  where auth.uid() is not null
$$;

comment on function public.my_seva_mala(text) is
  'Your own Seva Mala standing for the current week, month or lifetime, with your giving and with how much seva is still waiting to be confirmed. Your numbers are yours; your standing is withheld while the congregation is still gathering.';

revoke all on function public.my_seva_mala(text) from public, anon;
grant execute on function public.my_seva_mala(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Your seva profile: three windows, seva and giving side by side.
--
--    Hours are raw minutes served, not credited minutes, because this is the
--    devotee's own record of what they did rather than the scoring's record of
--    what it will pay for. The two differ exactly when a cap bites, and
--    explain_my_score is where that difference is spelled out.
--
--    Every act appears in exactly one of counted / pending / not_served, and
--    the three sum to the total. A devotee who wants to know how much of their
--    week is hanging in the balance subtracts nothing.
--
--    Giving is the caller's own donations in the same window — the same figure
--    my_seva_mala reports for the period, in the windows this profile uses. It
--    is read from public.donations directly rather than from period_scores so
--    that the year window, which is not a scoring period, has an answer too.
-- ---------------------------------------------------------------------------

create or replace function public.my_seva_profile()
returns table (
  window_kind text,
  window_start date,
  window_end date,
  acts integer,
  hours numeric,
  counted_acts integer,
  counted_hours numeric,
  pending_acts integer,
  pending_hours numeric,
  not_served_acts integer,
  not_served_hours numeric,
  recurring_acts integer,
  recurring_hours numeric,
  giving_cents bigint,
  gifts integer
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    windows.window_kind,
    windows.window_start,
    windows.window_end,
    count(acts.assignment_id)::integer,
    round(coalesce(sum(acts.raw_minutes), 0) / 60.0, 2),
    count(acts.assignment_id) filter (where acts.points_status = 'counted')::integer,
    round(
      coalesce(sum(acts.raw_minutes) filter (where acts.points_status = 'counted'), 0)
      / 60.0, 2),
    count(acts.assignment_id) filter (
      where acts.points_status in (
        'awaiting_completion', 'awaiting_verification', 'awaiting_confirmation')
    )::integer,
    round(
      coalesce(sum(acts.raw_minutes) filter (
        where acts.points_status in (
          'awaiting_completion', 'awaiting_verification', 'awaiting_confirmation')
      ), 0) / 60.0, 2),
    count(acts.assignment_id) filter (where acts.points_status = 'not_served')::integer,
    round(
      coalesce(sum(acts.raw_minutes) filter (where acts.points_status = 'not_served'), 0)
      / 60.0, 2),
    count(acts.assignment_id) filter (where acts.is_recurring)::integer,
    round(
      coalesce(sum(acts.raw_minutes) filter (where acts.is_recurring), 0) / 60.0, 2),
    (
      select coalesce(sum(donations.amount_cents), 0)::bigint
      from public.donations
      where donations.donor_id = auth.uid()
        and (donations.received_at at time zone 'America/Chicago')::date
            between windows.window_start and windows.window_end
    ),
    (
      select count(*)::integer
      from public.donations
      where donations.donor_id = auth.uid()
        and (donations.received_at at time zone 'America/Chicago')::date
            between windows.window_start and windows.window_end
    )
  from public.seva_mala_windows() windows
  left join public.seva_mala_acts(auth.uid()) acts
    on acts.occurred_on between windows.window_start and windows.window_end
  where auth.uid() is not null
  group by windows.window_kind, windows.window_start, windows.window_end,
           windows.window_order
  order by windows.window_order
$$;

comment on function public.my_seva_profile() is
  'Your own seva this week, month and calendar year — hours counted, hours waiting to be confirmed, hours recorded as not served, hours of weekly seva — with your own giving in the same windows. Only ever your own.';

revoke all on function public.my_seva_profile() from public, anon;
grant execute on function public.my_seva_profile() to authenticated;

-- ---------------------------------------------------------------------------
-- 6. The same three windows, per kind of seva.
--
--    One row per window per kind of seva the caller actually served. Grouped by
--    the name rather than only by the id, so custom-named seva — which carries
--    no service_type_id at all and therefore no scarcity weight — keeps its own
--    rows instead of collapsing into one anonymous null bucket.
--
--    Weekly seva is not a separate kind and is not filtered out: recurring seva
--    reaches service_assignments as ordinary assignments on generated
--    instances, so it appears here under its own service type with
--    recurring_acts counting how much of it came from a template.
-- ---------------------------------------------------------------------------

create or replace function public.my_seva_breakdown()
returns table (
  window_kind text,
  window_start date,
  window_end date,
  service_type_id uuid,
  seva_name text,
  acts integer,
  hours numeric,
  counted_acts integer,
  counted_hours numeric,
  pending_acts integer,
  pending_hours numeric,
  not_served_acts integer,
  not_served_hours numeric,
  recurring_acts integer,
  recurring_hours numeric
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    windows.window_kind,
    windows.window_start,
    windows.window_end,
    acts.service_type_id,
    acts.seva_name,
    count(*)::integer,
    round(sum(acts.raw_minutes) / 60.0, 2),
    count(*) filter (where acts.points_status = 'counted')::integer,
    round(
      coalesce(sum(acts.raw_minutes) filter (where acts.points_status = 'counted'), 0)
      / 60.0, 2),
    count(*) filter (
      where acts.points_status in (
        'awaiting_completion', 'awaiting_verification', 'awaiting_confirmation')
    )::integer,
    round(
      coalesce(sum(acts.raw_minutes) filter (
        where acts.points_status in (
          'awaiting_completion', 'awaiting_verification', 'awaiting_confirmation')
      ), 0) / 60.0, 2),
    count(*) filter (where acts.points_status = 'not_served')::integer,
    round(
      coalesce(sum(acts.raw_minutes) filter (where acts.points_status = 'not_served'), 0)
      / 60.0, 2),
    count(*) filter (where acts.is_recurring)::integer,
    round(coalesce(sum(acts.raw_minutes) filter (where acts.is_recurring), 0) / 60.0, 2)
  from public.seva_mala_windows() windows
  join public.seva_mala_acts(auth.uid()) acts
    on acts.occurred_on between windows.window_start and windows.window_end
  where auth.uid() is not null
  group by windows.window_kind, windows.window_start, windows.window_end,
           windows.window_order, acts.service_type_id, acts.seva_name
  order by windows.window_order, sum(acts.raw_minutes) desc, acts.seva_name
$$;

comment on function public.my_seva_breakdown() is
  'Your own seva per kind, for this week, month and calendar year, split into what earned points and what is still waiting. Only ever your own.';

revoke all on function public.my_seva_breakdown() from public, anon;
grant execute on function public.my_seva_breakdown() to authenticated;

-- ---------------------------------------------------------------------------
-- 7. Act by act, with the reason in words.
--
--    Which seva, which day, how long, and what is still owed before it counts.
--    This is the screen that answers "why didn't Tuesday count", and it answers
--    it with a sentence rather than a zero.
--
--    Defaults to the trailing ninety days, which is the same window the scoring
--    measures its units over, so a devotee scrolling their history and a
--    devotee reading their score are looking at the same stretch of time.
-- ---------------------------------------------------------------------------

create or replace function public.my_seva_acts(
  p_from date default null,
  p_to date default null
)
returns table (
  assignment_id uuid,
  service_instance_id uuid,
  service_type_id uuid,
  seva_name text,
  occurred_on date,
  weekday text,
  started_at_local time,
  minutes numeric,
  hours numeric,
  is_recurring boolean,
  assignment_status text,
  verification text,
  attendance text,
  points_status text,
  points_note text
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    acts.assignment_id,
    acts.service_instance_id,
    acts.service_type_id,
    acts.seva_name,
    acts.occurred_on,
    trim(to_char(acts.occurred_on, 'FMDay')),
    acts.started_at_local,
    acts.raw_minutes,
    round(acts.raw_minutes / 60.0, 2),
    acts.is_recurring,
    acts.assignment_status,
    acts.verification,
    acts.attendance,
    acts.points_status,
    public.seva_points_note(acts.points_status)
  from public.seva_mala_acts(auth.uid()) acts
  where auth.uid() is not null
    and acts.occurred_on
        between coalesce(p_from, public.seva_mala_today() - 89)
            and coalesce(p_to, public.seva_mala_today())
  order by acts.occurred_on desc, acts.started_at_local desc, acts.seva_name
$$;

comment on function public.my_seva_acts(date, date) is
  'Your own seva act by act — which seva, which day, how many hours, and in words what is still needed before it earns points. Only ever your own.';

revoke all on function public.my_seva_acts(date, date) from public, anon;
grant execute on function public.my_seva_acts(date, date) to authenticated;

-- ---------------------------------------------------------------------------
-- 8. The queue, for whoever can actually clear it.
--
--    Withholding points until somebody confirms attendance only works if
--    somebody is asked to. This is the list, and its audience is exactly
--    202608040027's authority and no wider: the devotee who posted the seva
--    sees their own, the President and the Tech Admin see everything.
--
--    Recurring seva is generated with posted_by null — nobody posted a
--    template's Tuesday — so weekly seva appears only to app.view_all. That
--    follows from 0027 rather than from a decision made here, and it is the
--    reason a temple running mostly weekly seva will find this list on the
--    President's screen and nowhere else.
--
--    Built from the tables rather than from seva_mala_acts because it asks
--    about everybody: the cap arithmetic is per devotee and per day and none of
--    it is needed to say "this one is waiting".
-- ---------------------------------------------------------------------------

create or replace function public.list_seva_awaiting_confirmation(
  p_from date default null,
  p_to date default null
)
returns table (
  assignment_id uuid,
  service_instance_id uuid,
  devotee_id uuid,
  devotee_name text,
  seva_name text,
  occurred_on date,
  weekday text,
  started_at_local time,
  planned_minutes integer,
  is_recurring boolean,
  posted_by uuid,
  points_status text,
  points_note text
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    assignments.id,
    instances.id,
    assignments.devotee_id,
    users.name,
    public.service_instance_name(instances),
    instances.date,
    trim(to_char(instances.date, 'FMDay')),
    instances.start_time,
    instances.duration_minutes,
    instances.template_id is not null,
    instances.posted_by,
    public.seva_points_status(
      assignments.status, assignments.attendance, assignments.verification),
    public.seva_points_note(
      public.seva_points_status(
        assignments.status, assignments.attendance, assignments.verification))
  from public.service_assignments assignments
  join public.service_instances instances
    on instances.id = assignments.service_instance_id
  join public.users on users.id = assignments.devotee_id
  where auth.uid() is not null
    and instances.status <> 'cancelled'
    and instances.date <= public.seva_mala_today()
    and instances.date
        between coalesce(p_from, public.seva_mala_today() - 89)
            and coalesce(p_to, public.seva_mala_today())
    and public.seva_points_status(
          assignments.status, assignments.attendance, assignments.verification
        ) in ('awaiting_completion', 'awaiting_verification', 'awaiting_confirmation')
    and (
      instances.posted_by = auth.uid()
      or public.has_permission('app.view_all')
    )
  order by instances.date desc, instances.start_time desc, users.name
$$;

comment on function public.list_seva_awaiting_confirmation(date, date) is
  'Seva that has not earned points yet and is waiting on somebody, for the devotee who posted it and for the President and Tech Admin. Weekly seva carries no poster, so it appears only to app.view_all.';

revoke all on function public.list_seva_awaiting_confirmation(date, date) from public, anon;
grant execute on function public.list_seva_awaiting_confirmation(date, date) to authenticated;

-- ---------------------------------------------------------------------------
-- 9. Somebody other than the devotee says it happened.
--
--    The missing half of the rule. Sets an existing assignment's verification
--    to member_verified, which is the level the schema already uses for "another
--    devotee stood behind this" (202608040012), rather than inventing a new one
--    that every reader of the constraint would then have to learn.
--
--    Who may:
--
--      the devotee who posted the seva      they asked for it and they were there
--      a holder of app.view_all             the President and the Tech Admin
--
--    the same authority 202608040027 gives the attendance mark, deliberately
--    and not by coincidence: the temple named one set of people for this, and
--    two different answers to "who runs a seva" would be one answer too many.
--
--    Who may not: the devotee themselves, whoever else they are. A poster who
--    served their own seva may still mark their own attendance — 0027 allows
--    that and this migration does not relitigate it — but they may not be the
--    someone in "someone verified it". That is the whole content of the word.
--
--    Never downgrades. An act that arrived through a QR scan or a live timer
--    already carries harder evidence than a person's word, and confirming it a
--    second time must not quietly replace the machine's account with a human's.
--    Calling this on an already-verified act is a no-op that returns the row.
--
--    Recurring seva is generated with posted_by null, so on weekly seva this is
--    the President's and the Tech Admin's to do. That follows from 0027's
--    authority rather than from anything decided here, and it is worth the
--    temple knowing before it turns the rule on: a congregation whose seva is
--    mostly weekly has put its entire points ledger on two people's screens.
-- ---------------------------------------------------------------------------

create or replace function public.verify_seva_assignment(p_assignment_id uuid)
returns public.service_assignments
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_assignment public.service_assignments;
  v_instance public.service_instances;
  v_updated public.service_assignments;
  v_actor text;
begin
  if auth.uid() is null then
    raise exception 'Sign in to verify a seva.';
  end if;

  select * into v_assignment from public.service_assignments
  where service_assignments.id = p_assignment_id
  for update;
  if v_assignment.id is null then
    raise exception 'This seva place could not be found.';
  end if;

  select * into v_instance from public.service_instances
  where service_instances.id = v_assignment.service_instance_id;

  -- Asked before the authority check, and in this order deliberately. A poster
  -- who served their own seva holds the authority and still may not be the
  -- someone in "someone verified it", so the authority check would give them a
  -- true answer to the wrong question.
  if v_assignment.devotee_id = auth.uid() then
    raise exception 'Somebody other than you has to verify that you served.';
  end if;

  if v_instance.posted_by is distinct from auth.uid()
    and not public.has_permission('app.view_all')
  then
    raise exception
      'Only the devotee who posted this seva, a Tech Admin, or the President can verify it.';
  end if;

  if ((v_instance.date + v_instance.start_time)
      at time zone 'America/Chicago') > now() then
    raise exception 'A seva can be verified once it has started.';
  end if;

  if v_assignment.status in ('no_show', 'withdrawn') then
    raise exception 'This devotee is not recorded as having served this seva.';
  end if;

  -- A machine's account of the seva outranks a person's. Confirming an act that
  -- already carries one changes nothing and says so by returning the row.
  if v_assignment.verification in ('live_timer', 'qr_scan', 'member_verified') then
    return v_assignment;
  end if;

  update public.service_assignments
  set verification = 'member_verified'
  where service_assignments.id = p_assignment_id
  returning * into v_updated;

  select users.name into v_actor from public.users where users.id = auth.uid();

  perform public.queue_app_notification(
    v_assignment.devotee_id, 'seva_verification_reviewed',
    'Your seva was verified',
    v_actor || ' verified that you served "'
      || public.service_instance_name(v_instance) || '" on '
      || public.format_seva_when(v_instance.date, v_instance.start_time) || '.',
    jsonb_build_object(
      'serviceInstanceId', v_instance.id,
      'serviceAssignmentId', v_updated.id
    )
  );

  return v_updated;
end;
$$;

comment on function public.verify_seva_assignment(uuid) is
  'The poster, the President or a Tech Admin — and never the devotee themselves — says an act of seva happened. The one path by which posted and weekly seva reach a verification level that can earn points. Never downgrades a QR scan or a live timer.';

revoke all on function public.verify_seva_assignment(uuid) from public, anon;
grant execute on function public.verify_seva_assignment(uuid) to authenticated;

do $$
begin
  raise notice 'seva points eligibility applied';
end;
$$;
