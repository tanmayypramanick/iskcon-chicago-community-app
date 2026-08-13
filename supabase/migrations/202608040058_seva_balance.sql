-- Seva balance — noticing when somebody is carrying too much of one thing.
--
-- "A devotee is doing pot washing two hours a day for two weeks — that's too
-- much, and actually they shouldn't be doing that. So the President and Tech
-- Admin should know, so they can switch them to a different seva and consider
-- someone else for it."
--
-- This file is a care mechanism, not a metric. Nothing in it scores anybody,
-- nothing in it ranks devotees against each other, and nothing in it acts. It
-- exists so that a human being can start a conversation that would otherwise
-- never happen, because the devotee washing pots every evening is precisely the
-- devotee who will not complain.
--
-- Two shapes are worth a coordinator's eye, and they are opposites:
--
--   CONCENTRATION  too much of one seva, for too long. The burnout risk the
--                  temple actually described. list_seva_concentration.
--
--   NARROWNESS     only ever the one kind of seva, never the other kind. Not
--                  burnout — nobody burns out from kirtan — but a devotee who
--                  has never once done the ground work is a devotee the temple
--                  has quietly shaped, and the President should know that
--                  before the next rota is drawn. list_seva_narrowness.
--
-- ---------------------------------------------------------------------------
-- Four rules this file will not break.
--
--   1. app.view_all, and nothing wider. The President and the Tech Admin, who
--      already read every devotee's hours through list_all_seva_scores. NOT
--      services.manage_recurring — a Community Head runs a rota, which is a
--      reason to know who is free, not a reason to be handed a reading of
--      another devotee's tiredness. Section 0 asserts that distinction rather
--      than trusting it, because the two permissions are one word apart and a
--      later migration that hands core app.view_all would silently widen this.
--
--   2. Nothing leaks to the devotee. There is a devotee-facing function here —
--      my_seva_balance — and it is deliberately built from a different set of
--      columns. It has no share, no streak, no threshold, no comparison to
--      anybody, and no way to tell from it whether you appear on a
--      coordinator's list. It says "you have given forty hours to the kitchen
--      this month", full stop, because that is a true and good thing to be
--      told, and it is the only sentence this feature owes a devotee.
--
--   3. Nothing here acts. Every function is STABLE and read-only. No trigger,
--      no notification, no write, no automatic reassignment. A devotee who
--      loves washing pots and has done it happily every Saturday for nine years
--      is not a problem to be solved, and the only thing that can tell the
--      difference between that devotee and an exhausted one is a person asking.
--      The verification asserts the absence of writes, because the day somebody
--      adds "and notify the devotee" to this file is the day it becomes
--      surveillance.
--
--   4. Thresholds are the congregation's, not ours. "Twelve hours a week is too
--      much" is meaningless without knowing what this congregation does. Every
--      default here is derived from the temple's own distribution and every
--      one of them is overridable by the caller. See section 3.
--
-- ---------------------------------------------------------------------------
-- Where the hours come from.
--
-- 202608040055_seva_mala.sql already answers the hard half of this question:
-- which assignments count as served, whether to believe the planned duration
-- or a measured one, what a cancelled instance means, what an absence means.
-- public.seva_mala_acts() is that answer and this file reuses it whole rather
-- than deriving a second, divergent notion of "an hour of seva".
--
-- Three deliberate departures from how Seva Mālā reads its own rows:
--
--   * raw_minutes, not credited_minutes. The day and week caps exist so that
--     nobody can farm a leaderboard. A report whose whole purpose is to notice
--     that somebody served too much must not clip the hours at exactly the
--     point where they start to be worrying.
--
--   * points_status, not quality. This is the important one.
--     202608040057_seva_points_eligibility.sql narrowed what EARNS POINTS to
--     completed-and-verified-and-marked-served, which means quality is now zero
--     for the great majority of real acts — every weekly seva sitting at
--     self_report that nobody has got round to confirming. Reading hours off
--     quality would make this feature blind to almost the entire temple, and
--     blind first of all to exactly the devotee it was built for: the one
--     quietly washing pots on a recurring assignment nobody ever verifies.
--     0057 says it in as many words — "hours are NOT withheld, a pending act
--     keeps its minutes; only the points wait" — so what is counted here is
--     every act whose points_status is not 'not_served'. Tiredness does not
--     wait on the paperwork.
--
--   * no quality multiplier and no scarcity weight. Twelve hours of pot
--     washing is twelve hours of pot washing. Weighting tiredness by how hard a
--     seva was to fill would be scoring, and scoring is the thing this file is
--     not.
--
-- Requires 202608040057_seva_points_eligibility.sql.

-- ---------------------------------------------------------------------------
-- 0. The ground this stands on.
--
--    Asserted, not assumed. Each of these is something a later migration could
--    change out from under a care report, and a care report that is quietly
--    wrong is worse than one that is loudly broken.
-- ---------------------------------------------------------------------------

do $$
declare
  v_holders text;
  v_categories text;
begin
  select string_agg(roles.name, ',' order by roles.name) into v_holders
  from public.role_permissions
  join public.roles on roles.id = role_permissions.role_id
  where role_permissions.permission_key = 'app.view_all';

  if v_holders is distinct from 'president,tech' then
    raise exception
      'app.view_all is held by % — seva balance is written for president, tech.', v_holders;
  end if;

  -- The distinction this file turns on, stated as an assertion. A Community
  -- Head holds services.manage_recurring and must NOT hold app.view_all.
  if exists (
    select 1
    from public.role_permissions manage
    join public.roles on roles.id = manage.role_id
    join public.role_permissions view_all
      on view_all.role_id = manage.role_id
     and view_all.permission_key = 'app.view_all'
    where manage.permission_key = 'services.manage_recurring'
      and roles.name = 'core'
  ) then
    raise exception
      'The Community Head role now holds app.view_all; seva balance would become visible to every rota runner.';
  end if;

  -- Narrowness needs a grouping of seva into kinds. service_types.category is
  -- the temple's own, maintained in 202608020002, and this file uses it rather
  -- than inventing a taxonomy of glamorous and unglamorous seva.
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'service_types'
      and column_name = 'category'
  ) then
    raise exception 'public.service_types has no category column; narrowness has nothing to group by.';
  end if;

  select string_agg(distinct service_types.category, ',' order by service_types.category)
  into v_categories
  from public.service_types;

  if coalesce(array_length(string_to_array(v_categories, ','), 1), 0) < 2 then
    raise exception
      'public.service_types carries fewer than two categories (%); narrowness cannot mean anything.', v_categories;
  end if;

  -- The act source. If its shape moves, every hour in this file moves with it.
  if to_regprocedure('public.seva_mala_acts(uuid)') is null then
    raise exception
      'public.seva_mala_acts is missing; apply 202608040055_seva_mala.sql first.';
  end if;

  -- points_status is 0057's, and it is what separates "they served it and
  -- nobody has confirmed it yet" from "they were not there". Reading hours off
  -- quality instead would hide every unconfirmed act, which is most of them.
  if not exists (
    select 1 from pg_proc
    where pg_proc.oid = to_regprocedure('public.seva_mala_acts(uuid)')
      and 'points_status' = any (pg_proc.proargnames)
  ) then
    raise exception
      'public.seva_mala_acts has no points_status; apply 202608040057_seva_points_eligibility.sql first.';
  end if;

  if public.seva_points_status('completed', 'served', 'self_report') = 'not_served'
     or public.seva_points_status('completed', null, 'self_report') = 'not_served'
     or public.seva_points_status('no_show', 'served', 'qr_scan') <> 'not_served'
     or public.seva_points_status('completed', 'absent', 'qr_scan') <> 'not_served'
  then
    raise exception
      'seva_points_status no longer means what this file reads it as: not_served must be exactly "they were not there".';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 1. The dials.
--
--    In app_settings, which is granted to nobody and read only by definer
--    functions, seeded ON CONFLICT DO NOTHING so re-applying never stamps on a
--    value the temple has since changed. Read through
--    public.seva_mala_number, which is the reader 0055 already wrote.
--
--    Not one of these is a threshold. They are the shape of a question asked of
--    the congregation's own distribution — a multiple, two quantiles, a window.
--    The thresholds themselves are computed in section 3 and change on their
--    own as the temple changes.
-- ---------------------------------------------------------------------------

insert into public.app_settings (key, value)
values
  -- Thirteen ISO weeks ending with the current one: the quarter behind them.
  -- Long enough that a fortnight of pot washing is visible against a normal
  -- season, short enough that last spring does not vote on this week.
  ('seva_balance.window_weeks', '13'),

  -- Concern begins above this multiple of what a typical devotee gives the
  -- temple in a whole week. 1.5 says: one seva alone is taking half again as
  -- much of you as the median devotee gives to everything put together.
  ('seva_balance.weekly_load_multiple', '1.5'),

  -- ...and never below the congregation's own upper tail. In a temple where
  -- everybody serves heavily the multiple alone would surface half the
  -- congregation; this quantile is what keeps the list to the tail.
  ('seva_balance.weekly_hours_quantile', '0.85'),

  -- How persistent is persistent, asked of the congregation. If most devotees
  -- run two weeks in their main seva, six weeks is a long time.
  ('seva_balance.weeks_quantile', '0.85'),

  -- One week is not "consecutive weeks". This is the meaning of the word, not
  -- a claim about this congregation, and the temple said "for two weeks".
  ('seva_balance.minimum_weeks_floor', '2'),

  -- Narrowness: how much of a devotee's seva must sit in one category, asked
  -- of the congregation, and never below the floor. "Entirely in one category"
  -- is what was asked for; 0.90 is that, with room for the one Sunday they
  -- helped in the kitchen.
  ('seva_balance.category_share_quantile', '0.90'),
  ('seva_balance.narrow_category_share_floor', '0.90'),

  -- Below this many serving devotees there is no distribution to derive from —
  -- with five servers somebody is always above the median by arithmetic, and
  -- handing the President that as a concern is exactly the harm this file is
  -- meant to avoid. Below it both lists stay silent unless the caller states
  -- thresholds of their own. Same number as Seva Mālā's minimum cohort, and
  -- for the same reason.
  ('seva_balance.minimum_cohort', '8')
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------
-- 2. The window, and the acts in it.
--
--    Chicago throughout, by going through 0055's date helpers and nowhere else.
--    A President reading this from India sees the temple's week.
--
--    seva_balance_acts windows nothing. Hours are a question about a window;
--    "how long have they been doing this" and "when did they first" are not,
--    and a streak truncated at the edge of a thirteen-week window would report
--    a devotee of three years' standing as thirteen weeks running. Callers
--    window the hours and leave the dates alone.
-- ---------------------------------------------------------------------------

create or replace function public.seva_balance_window_start()
returns date
language sql
stable
security definer
set search_path = ''
as $$
  select public.seva_mala_week_start(public.seva_mala_today())
    - (7 * (public.seva_mala_number('seva_balance.window_weeks', 13)::integer - 1))
$$;

comment on function public.seva_balance_window_start() is
  'The Monday that opens the trailing quarter every seva balance figure is measured over.';

revoke all on function public.seva_balance_window_start() from public, anon, authenticated;

create or replace function public.seva_balance_acts(p_devotee_id uuid default null)
returns table (
  devotee_id uuid,
  service_type_id uuid,
  seva_key text,
  seva_name text,
  category text,
  occurred_on date,
  week_start date,
  served_minutes numeric
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    acts.devotee_id,
    acts.service_type_id,
    -- Custom-named seva has no type id. Folding every custom seva into one
    -- null key would merge "Janmastami rangoli" with "gate duty" and invent a
    -- concentration nobody has; keying custom seva by its own name does not.
    coalesce(acts.service_type_id::text, 'custom:' || lower(acts.seva_name)),
    acts.seva_name,
    types.category,
    acts.occurred_on,
    public.seva_mala_week_start(acts.occurred_on),
    acts.raw_minutes
  from public.seva_mala_acts(p_devotee_id) acts
  left join public.service_types types on types.id = acts.service_type_id
  -- Everything except "they were not there". An act still waiting on somebody
  -- to complete, verify or confirm it earns no points and was still served, and
  -- the devotee who served it is exactly as tired either way.
  where acts.points_status <> 'not_served'
    and acts.raw_minutes > 0
$$;

comment on function public.seva_balance_acts(uuid) is
  'Every act of seva a devotee actually served — confirmed or still waiting to be — with its kind and its category, in real minutes before Seva Mala''s caps. Windows nothing.';

revoke all on function public.seva_balance_acts(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. The thresholds, derived.
--
--    This is the section the feature stands or falls on. There is no number
--    here that says how much seva is too much; there is only a reading of what
--    this congregation does, and a devotee is surfaced for being unlike it.
--
--    Over the window, for every devotee with any seva:
--
--      total_hours     everything they served
--      active_weeks    weeks in which they served anything at all. The
--                      denominator, rather than a flat thirteen, so a devotee
--                      who joined a month ago and has served heavily every week
--                      since reads as heavy — which is precisely the devotee
--                      the temple was worried about — instead of being divided
--                      into invisibility by ten weeks they were not here for.
--      weekly_hours    total_hours / active_weeks
--      top_weekly      the same for their single largest seva type
--      top_share       that type's share of everything they do
--
--    and from those, three thresholds:
--
--      weekly_hours_threshold
--        = greatest( median(weekly_hours) × multiple,
--                    quantile(q, top_weekly) )
--
--      The first term is the temple's question — "how does their weekly load
--      compare to the median?" — and on its own it is not enough: in a lightly
--      serving congregation with a median of one hour it would surface anybody
--      who gave three, and in a heavy one it would surface half the temple. The
--      second term fixes both ends by insisting the devotee is also in the
--      congregation's own upper tail. Taking the greater of the two means both
--      must be true, which is the conservative direction, which is the right
--      direction for a list a President will read as a worry.
--
--      consecutive_weeks_threshold
--        = greatest( floor, ceil(quantile(q, best current streak)) )
--
--      Persistence measured against the congregation's own persistence. A
--      temple whose devotees hold a weekly seva for months does not need a
--      report about somebody holding one for six weeks.
--
--      top_category_share_threshold
--        = greatest( quantile(q, top category share), floor )
--
--    Every one of these moves on its own when the congregation changes, and
--    every one is overridable at the call. The floors are semantic, not
--    empirical: they are what the words "consecutive weeks" and "entirely in
--    one category" mean.
--
--    Below the minimum cohort, gathering is true and both lists return nothing.
--    An empty list is the safe failure for a care feature — a false silence
--    costs a conversation that was not going to happen anyway, while a false
--    alarm costs a devotee being told the temple thinks they are struggling.
-- ---------------------------------------------------------------------------

create or replace function public.seva_balance_references()
returns table (
  window_starts_on date,
  window_ends_on date,
  devotees_considered integer,
  gathering boolean,
  median_weekly_hours numeric,
  median_total_hours numeric,
  median_top_share numeric,
  weekly_hours_threshold numeric,
  consecutive_weeks_threshold integer,
  top_category_share_threshold numeric,
  congregation_categories text[]
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_from date := public.seva_balance_window_start();
  v_to date := public.seva_mala_today();
  v_this_week date := public.seva_mala_week_start(public.seva_mala_today());
  v_multiple numeric := public.seva_mala_number('seva_balance.weekly_load_multiple', 1.5);
  v_hours_q numeric := public.seva_mala_number('seva_balance.weekly_hours_quantile', 0.85);
  v_weeks_q numeric := public.seva_mala_number('seva_balance.weeks_quantile', 0.85);
  v_weeks_floor numeric := public.seva_mala_number('seva_balance.minimum_weeks_floor', 2);
  v_cat_q numeric := public.seva_mala_number('seva_balance.category_share_quantile', 0.90);
  v_cat_floor numeric := public.seva_mala_number('seva_balance.narrow_category_share_floor', 0.90);
  v_cohort numeric := public.seva_mala_number('seva_balance.minimum_cohort', 8);
begin
  return query
  with acts as (
    select * from public.seva_balance_acts()
  ),
  windowed as (
    select * from acts where acts.occurred_on between v_from and v_to
  ),
  active as (
    select windowed.devotee_id, count(distinct windowed.week_start)::numeric as active_weeks
    from windowed group by 1
  ),
  totals as (
    select windowed.devotee_id, sum(windowed.served_minutes) / 60.0 as total_hours
    from windowed group by 1
  ),
  by_type as (
    select
      windowed.devotee_id,
      windowed.seva_key,
      sum(windowed.served_minutes) / 60.0 as type_hours
    from windowed group by 1, 2
  ),
  -- Streaks come from the unwindowed acts: see section 2.
  type_weeks as (
    select acts.devotee_id, acts.seva_key, acts.week_start
    from acts group by 1, 2, 3
  ),
  islands as (
    select
      type_weeks.devotee_id,
      type_weeks.seva_key,
      type_weeks.week_start,
      type_weeks.week_start
        - (row_number() over (
            partition by type_weeks.devotee_id, type_weeks.seva_key
            order by type_weeks.week_start))::integer * 7 as island
    from type_weeks
  ),
  runs as (
    select
      islands.devotee_id,
      islands.seva_key,
      count(*)::integer as weeks_run,
      max(islands.week_start) as last_week
    from islands group by 1, 2, islands.island
  ),
  -- A streak that ended in March is not a streak. Current week or the one
  -- before it, so a Monday morning does not zero everybody.
  current_runs as (
    select
      runs.devotee_id,
      max(case when runs.last_week >= v_this_week - 7 then runs.weeks_run else 0 end)
        as weeks_run
    from runs group by 1
  ),
  per_devotee as (
    select
      totals.devotee_id,
      totals.total_hours,
      totals.total_hours / active.active_weeks as weekly_hours,
      max(by_type.type_hours) / active.active_weeks as top_weekly,
      max(by_type.type_hours) / totals.total_hours as top_share,
      coalesce(max(current_runs.weeks_run), 0) as weeks_run
    from totals
    join active on active.devotee_id = totals.devotee_id
    join by_type on by_type.devotee_id = totals.devotee_id
    left join current_runs on current_runs.devotee_id = totals.devotee_id
    group by totals.devotee_id, totals.total_hours, active.active_weeks
  ),
  -- Category work ignores uncategorised seva entirely rather than inventing a
  -- category for it: a custom-named seva carries no information about whether
  -- this devotee has ever swept a floor.
  categorised as (
    select * from windowed where windowed.category is not null
  ),
  by_category as (
    select
      categorised.devotee_id,
      categorised.category,
      sum(categorised.served_minutes) as minutes
    from categorised group by 1, 2
  ),
  category_totals as (
    select by_category.devotee_id, sum(by_category.minutes) as minutes
    from by_category group by 1
  ),
  category_share as (
    select
      category_totals.devotee_id,
      max(by_category.minutes) / category_totals.minutes as top_share
    from category_totals
    join by_category on by_category.devotee_id = category_totals.devotee_id
    group by category_totals.devotee_id, category_totals.minutes
  )
  select
    v_from,
    v_to,
    (select count(*)::integer from per_devotee),
    (select count(*) from per_devotee) < v_cohort,
    (select round(percentile_cont(0.5) within group (order by p.weekly_hours)::numeric, 4)
       from per_devotee p),
    (select round(percentile_cont(0.5) within group (order by p.total_hours)::numeric, 4)
       from per_devotee p),
    (select round(percentile_cont(0.5) within group (order by p.top_share)::numeric, 4)
       from per_devotee p),
    (select round(greatest(
              percentile_cont(0.5) within group (order by p.weekly_hours) * v_multiple,
              percentile_cont(v_hours_q) within group (order by p.top_weekly)
            )::numeric, 4)
       from per_devotee p),
    (select greatest(
              v_weeks_floor,
              ceil(percentile_cont(v_weeks_q) within group (order by p.weeks_run))
            )::integer
       from per_devotee p),
    (select round(greatest(
              percentile_cont(v_cat_q) within group (order by c.top_share),
              v_cat_floor
            )::numeric, 4)
       from category_share c),
    (select array_agg(distinct b.category order by b.category) from by_category b);
end;
$$;

comment on function public.seva_balance_references() is
  'What this congregation does, over the trailing quarter, and the thresholds derived from it. Every default in list_seva_concentration and list_seva_narrowness comes from here.';

revoke all on function public.seva_balance_references() from public, anon, authenticated;

-- The same numbers, for the two people allowed to read them. A President who
-- is shown a list of devotees is owed the answer to "compared to what?", and a
-- threshold nobody can inspect is a threshold nobody can argue with.
create or replace function public.seva_balance_thresholds()
returns table (
  window_starts_on date,
  window_ends_on date,
  devotees_considered integer,
  gathering boolean,
  median_weekly_hours numeric,
  median_total_hours numeric,
  median_top_share numeric,
  weekly_hours_threshold numeric,
  consecutive_weeks_threshold integer,
  top_category_share_threshold numeric,
  congregation_categories text[]
)
language sql
stable
security definer
set search_path = ''
as $$
  select refs.*
  from public.seva_balance_references() refs
  where public.has_permission('app.view_all')
$$;

comment on function public.seva_balance_thresholds() is
  'The congregation''s own distribution and the thresholds derived from it, for the President and the Tech Admin. Nothing here is about any one devotee.';

revoke all on function public.seva_balance_thresholds() from public, anon;
grant execute on function public.seva_balance_thresholds() to authenticated;

-- ---------------------------------------------------------------------------
-- 4. One devotee, seva by seva.
--
--    The answer to "what is this devotee actually carrying?" — enough for a
--    coordinator to read "pot washing, twelve hours a week, six weeks running,
--    seventy-eight percent of everything they do" off one row and then go and
--    ask them about it.
--
--    Hours are windowed three ways. Week and month are the temple's own
--    calendar boundaries, Chicago, Monday-start, because those are the words
--    the office already speaks in. The quarter is the trailing thirteen weeks
--    rather than a calendar quarter, deliberately: on the second of April a
--    calendar quarter tells a coordinator nothing at all, and exhaustion does
--    not observe fiscal boundaries.
--
--    first_served_on, last_served_on and consecutive_weeks are NOT windowed.
--    "They have washed pots since 2019" is the sentence that most often turns
--    a worry into a happy shrug, and it cannot be said by a function that only
--    remembers a quarter.
-- ---------------------------------------------------------------------------

create or replace function public.seva_balance_for_devotee(p_devotee_id uuid)
returns table (
  service_type_id uuid,
  seva_name text,
  category text,
  hours_this_week numeric,
  hours_this_month numeric,
  hours_trailing_quarter numeric,
  hours_all_time numeric,
  share_of_their_seva numeric,
  consecutive_weeks integer,
  acts_trailing_quarter integer,
  first_served_on date,
  last_served_on date
)
language sql
stable
security definer
set search_path = ''
as $$
  with bounds as (
    select
      public.seva_mala_today() as today,
      public.seva_mala_week_start(public.seva_mala_today()) as week_from,
      public.seva_mala_period_start('month', public.seva_mala_today()) as month_from,
      public.seva_balance_window_start() as quarter_from
  ),
  acts as (
    select acts.*
    from public.seva_balance_acts(p_devotee_id) acts
    -- Read by the two people this is for, about one devotee they named. A null
    -- devotee would ask seva_mala_acts for the whole congregation.
    where public.has_permission('app.view_all')
      and p_devotee_id is not null
  ),
  by_type as (
    select
      acts.service_type_id,
      acts.seva_key,
      min(acts.seva_name) as seva_name,
      min(acts.category) as category,
      sum(acts.served_minutes) filter (where acts.occurred_on >= bounds.week_from)
        / 60.0 as week_hours,
      sum(acts.served_minutes) filter (where acts.occurred_on >= bounds.month_from)
        / 60.0 as month_hours,
      sum(acts.served_minutes) filter (where acts.occurred_on >= bounds.quarter_from)
        / 60.0 as quarter_hours,
      sum(acts.served_minutes) / 60.0 as all_time_hours,
      count(*) filter (where acts.occurred_on >= bounds.quarter_from)::integer as quarter_acts,
      min(acts.occurred_on) as first_on,
      max(acts.occurred_on) as last_on
    from acts cross join bounds
    group by acts.service_type_id, acts.seva_key
  ),
  total as (
    select sum(by_type.quarter_hours) as quarter_hours from by_type
  ),
  type_weeks as (
    select acts.seva_key, acts.week_start from acts group by 1, 2
  ),
  islands as (
    select
      type_weeks.seva_key,
      type_weeks.week_start,
      type_weeks.week_start
        - (row_number() over (
            partition by type_weeks.seva_key order by type_weeks.week_start))::integer * 7
        as island
    from type_weeks
  ),
  runs as (
    select
      islands.seva_key,
      count(*)::integer as weeks_run,
      max(islands.week_start) as last_week
    from islands group by islands.seva_key, islands.island
  ),
  current_runs as (
    select
      runs.seva_key,
      max(case
            when runs.last_week
                 >= public.seva_mala_week_start(public.seva_mala_today()) - 7
            then runs.weeks_run else 0
          end) as weeks_run
    from runs group by 1
  )
  select
    by_type.service_type_id,
    by_type.seva_name,
    by_type.category,
    round(coalesce(by_type.week_hours, 0), 2),
    round(coalesce(by_type.month_hours, 0), 2),
    round(coalesce(by_type.quarter_hours, 0), 2),
    round(by_type.all_time_hours, 2),
    round(coalesce(by_type.quarter_hours, 0) / nullif(total.quarter_hours, 0), 4),
    coalesce(current_runs.weeks_run, 0),
    by_type.quarter_acts,
    by_type.first_on,
    by_type.last_on
  from by_type
  cross join total
  left join current_runs on current_runs.seva_key = by_type.seva_key
  order by coalesce(by_type.quarter_hours, 0) desc, by_type.last_on desc, by_type.seva_name
$$;

comment on function public.seva_balance_for_devotee(uuid) is
  'What one devotee has been carrying, seva by seva, for the President and the Tech Admin. A reading to start a conversation from, not a verdict.';

revoke all on function public.seva_balance_for_devotee(uuid) from public, anon;
grant execute on function public.seva_balance_for_devotee(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Concentration — too much of one thing, for too long.
--
--    Gated on exactly the two stated parameters, both defaulting to section 3's
--    derived values: hours per active week in a SINGLE seva type, and
--    consecutive weeks in it. An evenly spread devotee falls out of this
--    without a third hidden rule, and by construction: twelve hours a week
--    split five ways is 2.4 hours in each, nowhere near a threshold derived
--    from what a whole devotee gives in a week.
--
--    Share is not a gate. It is what tells the difference between somebody who
--    is doing a great deal and somebody whose life at the temple has narrowed
--    to one sink, and it belongs in the ranking, where it changes the order of
--    a conversation rather than whether it happens.
--
--    pronouncedness is the geometric mean of the three ratios — hours against
--    the threshold, weeks against the threshold, share against the
--    congregation's median share. A geometric mean because these are
--    dimensionless multiples of different things and adding them would be
--    nonsense, and because no single term can run away with the ranking.
--    Anything surfaced is at or above 1 on the first two by definition.
--
--    The note column is the point of the whole function. A President opening
--    this reads English, not arithmetic, and the English is written to send
--    them to ask a question rather than to make a decision.
-- ---------------------------------------------------------------------------

create or replace function public.list_seva_concentration(
  p_min_weeks integer default null,
  p_min_hours numeric default null
)
returns table (
  devotee_id uuid,
  devotee_name text,
  service_type_id uuid,
  seva_name text,
  category text,
  hours_per_week numeric,
  hours_trailing_quarter numeric,
  consecutive_weeks integer,
  share_of_their_seva numeric,
  weekly_hours_vs_median numeric,
  share_vs_congregation numeric,
  pronouncedness numeric,
  first_served_on date,
  last_served_on date,
  min_hours_used numeric,
  min_weeks_used integer,
  note text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_refs record;
  v_min_hours numeric;
  v_min_weeks integer;
begin
  if p_min_weeks is not null and p_min_weeks < 1 then
    raise exception 'A run of seva is at least one week; % is not a number of weeks.', p_min_weeks;
  end if;
  if p_min_hours is not null and p_min_hours <= 0 then
    raise exception 'The hours a week to look above must be more than zero, not %.', p_min_hours;
  end if;

  if not public.has_permission('app.view_all') then
    return;
  end if;

  select * into v_refs from public.seva_balance_references();

  -- With too few serving devotees there is no distribution to be unlike. The
  -- caller may still ask a question of their own by naming both thresholds.
  if v_refs.gathering and (p_min_weeks is null or p_min_hours is null) then
    return;
  end if;

  v_min_hours := coalesce(p_min_hours, v_refs.weekly_hours_threshold);
  v_min_weeks := coalesce(p_min_weeks, v_refs.consecutive_weeks_threshold);

  if v_min_hours is null or v_min_weeks is null then
    return;
  end if;

  return query
  with acts as (
    select * from public.seva_balance_acts()
  ),
  windowed as (
    select * from acts
    where acts.occurred_on between v_refs.window_starts_on and v_refs.window_ends_on
  ),
  active as (
    select windowed.devotee_id, count(distinct windowed.week_start)::numeric as active_weeks
    from windowed group by 1
  ),
  totals as (
    select windowed.devotee_id, sum(windowed.served_minutes) / 60.0 as total_hours
    from windowed group by 1
  ),
  by_type as (
    select
      windowed.devotee_id,
      windowed.seva_key,
      -- seva_key is built from service_type_id, so grouping by both groups by
      -- neither more nor less than the kind of seva.
      windowed.service_type_id,
      min(windowed.seva_name) as seva_name,
      min(windowed.category) as category,
      sum(windowed.served_minutes) / 60.0 as type_hours
    from windowed group by 1, 2, 3
  ),
  type_weeks as (
    select acts.devotee_id, acts.seva_key, acts.week_start from acts group by 1, 2, 3
  ),
  islands as (
    select
      type_weeks.devotee_id,
      type_weeks.seva_key,
      type_weeks.week_start
        - (row_number() over (
            partition by type_weeks.devotee_id, type_weeks.seva_key
            order by type_weeks.week_start))::integer * 7 as island,
      type_weeks.week_start
    from type_weeks
  ),
  runs as (
    select
      islands.devotee_id,
      islands.seva_key,
      count(*)::integer as weeks_run,
      max(islands.week_start) as last_week
    from islands group by 1, 2, islands.island
  ),
  current_runs as (
    select
      runs.devotee_id,
      runs.seva_key,
      max(case
            when runs.last_week
                 >= public.seva_mala_week_start(v_refs.window_ends_on) - 7
            then runs.weeks_run else 0
          end) as weeks_run
    from runs group by 1, 2
  ),
  dates as (
    select acts.devotee_id, acts.seva_key,
           min(acts.occurred_on) as first_on, max(acts.occurred_on) as last_on
    from acts group by 1, 2
  ),
  candidates as (
    select
      by_type.devotee_id,
      by_type.service_type_id,
      by_type.seva_name,
      by_type.category,
      by_type.type_hours / active.active_weeks as per_week,
      by_type.type_hours as quarter_hours,
      coalesce(current_runs.weeks_run, 0) as weeks_run,
      by_type.type_hours / totals.total_hours as share,
      dates.first_on,
      dates.last_on
    from by_type
    join active on active.devotee_id = by_type.devotee_id
    join totals on totals.devotee_id = by_type.devotee_id
    left join current_runs
      on current_runs.devotee_id = by_type.devotee_id
     and current_runs.seva_key = by_type.seva_key
    join dates
      on dates.devotee_id = by_type.devotee_id
     and dates.seva_key = by_type.seva_key
  ),
  surfaced as (
    select
      candidates.*,
      candidates.per_week / v_min_hours as hours_ratio,
      candidates.weeks_run::numeric / v_min_weeks as weeks_ratio,
      candidates.share / nullif(v_refs.median_top_share, 0) as share_ratio
    from candidates
    where candidates.per_week >= v_min_hours
      and candidates.weeks_run >= v_min_weeks
  )
  select
    surfaced.devotee_id,
    users.name,
    surfaced.service_type_id,
    surfaced.seva_name,
    surfaced.category,
    round(surfaced.per_week, 2),
    round(surfaced.quarter_hours, 2),
    surfaced.weeks_run,
    round(surfaced.share, 4),
    round(surfaced.per_week / nullif(v_refs.median_weekly_hours, 0), 2),
    round(coalesce(surfaced.share_ratio, 1), 2),
    round(
      power(
        surfaced.hours_ratio * surfaced.weeks_ratio * coalesce(surfaced.share_ratio, 1),
        1.0 / 3.0
      )::numeric, 3
    ),
    surfaced.first_on,
    surfaced.last_on,
    round(v_min_hours, 2),
    v_min_weeks,
    users.name || ' has given '
      || to_char(round(surfaced.per_week, 1), 'FM999990.0')
      || ' hours a week to ' || surfaced.seva_name || ' for '
      || surfaced.weeks_run || ' weeks running — '
      || round(surfaced.share * 100)::text || '% of their seva'
      || case when surfaced.first_on < v_refs.window_starts_on
              then ', and they have been doing it since '
                   || to_char(surfaced.first_on, 'FMMonth YYYY')
              else '' end
      || '. Worth asking how they are finding it, and whether a rest or a change '
      || 'of seva would be welcome — and whether somebody else could take a turn.'
  from surfaced
  join public.users on users.id = surfaced.devotee_id
  order by
    power(
      surfaced.hours_ratio * surfaced.weeks_ratio * coalesce(surfaced.share_ratio, 1),
      1.0 / 3.0
    ) desc,
    surfaced.per_week desc,
    users.name;
end;
$$;

comment on function public.list_seva_concentration(integer, numeric) is
  'Devotees carrying a great deal of one seva for a long time, measured against what this congregation actually does. A list of conversations to have, for the President and the Tech Admin. Nothing here acts, and nothing here reaches the devotee.';

revoke all on function public.list_seva_concentration(integer, numeric) from public, anon;
grant execute on function public.list_seva_concentration(integer, numeric) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. Narrowness — the inverse.
--
--    "Someone doing kirtan all the time but no ground work like cleaning or
--    pot washing."
--
--    The temple's ask is directional, and this function deliberately is not.
--    service_types.category exists — kitchen, cleaning, deity-worship, event,
--    other — and it is a real grouping the temple maintains, so nothing needed
--    inventing. What did NOT exist, and what this file refuses to add, is an
--    ordering of those categories by how pleasant they are. Ranking seva by
--    glamour would be a political document with a developer's name on it, and
--    it would be wrong within a year of the first devotee who finds the kitchen
--    restful and the microphone terrifying.
--
--    So narrowness is stated without a value judgement: this devotee's seva
--    sits almost entirely in one category, and here are the categories the
--    congregation serves that they have never once touched, with how much of
--    the temple's work happens there. A President reading "all forty hours in
--    event; kitchen and cleaning, which are sixty-one percent of the temple's
--    hours, untouched" draws the conclusion themselves, and it is a conclusion
--    about a rota rather than about a person.
--
--    Ranked by hours × the share of the congregation's work they have never
--    done, so the devotee who serves the most while touching the least of the
--    temple comes first.
--
--    Uncategorised seva — custom-named, with no service type — is left out of
--    this entirely rather than being given a category of its own. It carries no
--    information about whether somebody has ever swept a floor.
-- ---------------------------------------------------------------------------

create or replace function public.list_seva_narrowness(p_min_hours numeric default null)
returns table (
  devotee_id uuid,
  devotee_name text,
  category text,
  hours_trailing_quarter numeric,
  category_share numeric,
  untouched_categories text[],
  untouched_share_of_congregation numeric,
  min_hours_used numeric,
  min_share_used numeric,
  note text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_refs record;
  v_min_hours numeric;
  v_min_share numeric;
begin
  if p_min_hours is not null and p_min_hours <= 0 then
    raise exception 'The hours to look above must be more than zero, not %.', p_min_hours;
  end if;

  if not public.has_permission('app.view_all') then
    return;
  end if;

  select * into v_refs from public.seva_balance_references();

  if v_refs.gathering and p_min_hours is null then
    return;
  end if;

  -- A devotee is only worth remarking on for what they have never done once
  -- they have done a fair amount. Below the congregation's median, "you only
  -- ever do one thing" says nothing except "you are new".
  v_min_hours := coalesce(p_min_hours, v_refs.median_total_hours);
  v_min_share := v_refs.top_category_share_threshold;

  if v_min_hours is null or v_min_share is null then
    return;
  end if;

  -- A congregation that serves one category, or none, needs no guard of its
  -- own here: every devotee's untouched set is then empty, and the gate at the
  -- end of this query already returns nothing. An early return for it would be
  -- unreachable code standing where a rule appears to be.

  return query
  with windowed as (
    select acts.*
    from public.seva_balance_acts() acts
    where acts.occurred_on between v_refs.window_starts_on and v_refs.window_ends_on
      and acts.category is not null
  ),
  by_category as (
    select
      windowed.devotee_id,
      windowed.category,
      sum(windowed.served_minutes) as minutes
    from windowed group by 1, 2
  ),
  congregation as (
    select
      by_category.category,
      sum(by_category.minutes) as minutes,
      sum(by_category.minutes) / sum(sum(by_category.minutes)) over () as share
    from by_category group by 1
  ),
  per_devotee as (
    select
      by_category.devotee_id,
      sum(by_category.minutes) as minutes,
      array_agg(distinct by_category.category) as served_categories
    from by_category group by 1
  ),
  top_category as (
    select distinct on (by_category.devotee_id)
      by_category.devotee_id,
      by_category.category,
      by_category.minutes
    from by_category
    order by by_category.devotee_id, by_category.minutes desc, by_category.category
  ),
  candidates as (
    select
      per_devotee.devotee_id,
      top_category.category,
      per_devotee.minutes / 60.0 as hours,
      top_category.minutes::numeric / per_devotee.minutes as share,
      (
        select coalesce(array_agg(congregation.category order by congregation.category), '{}')
        from congregation
        where not (congregation.category = any (per_devotee.served_categories))
      ) as untouched,
      (
        select coalesce(sum(congregation.share), 0)
        from congregation
        where not (congregation.category = any (per_devotee.served_categories))
      ) as untouched_share
    from per_devotee
    join top_category on top_category.devotee_id = per_devotee.devotee_id
  ),
  surfaced as (
    select * from candidates
    where candidates.hours >= v_min_hours
      and candidates.share >= v_min_share
      and coalesce(array_length(candidates.untouched, 1), 0) > 0
  )
  select
    surfaced.devotee_id,
    users.name,
    surfaced.category,
    round(surfaced.hours, 2),
    round(surfaced.share, 4),
    surfaced.untouched,
    round(surfaced.untouched_share, 4),
    round(v_min_hours, 2),
    round(v_min_share, 4),
    users.name || ' has given '
      || to_char(round(surfaced.hours, 1), 'FM999990.0')
      || ' hours this quarter, '
      || round(surfaced.share * 100)::text || '% of it to ' || surfaced.category
      || ' seva, and none at all to '
      || array_to_string(surfaced.untouched, ', ', 'other')
      || ' — '
      || round(surfaced.untouched_share * 100)::text
      || '% of what the congregation does. Not a problem in itself. Worth knowing '
      || 'before the next rota, and worth asking whether they would like to try '
      || 'something else.'
  from surfaced
  join public.users on users.id = surfaced.devotee_id
  order by surfaced.hours * surfaced.untouched_share desc, users.name;
end;
$$;

comment on function public.list_seva_narrowness(numeric) is
  'Devotees whose seva sits almost entirely in one category, with the categories of the temple''s work they have never touched. The inverse of list_seva_concentration, and just as much a conversation rather than a verdict.';

revoke all on function public.list_seva_narrowness(numeric) from public, anon;
grant execute on function public.list_seva_narrowness(numeric) to authenticated;

-- ---------------------------------------------------------------------------
-- 7. What the devotee sees.
--
--    Yes, the devotee should see their own hours, and no, they should not see
--    any of the above.
--
--    A devotee who is told "you have given forty hours to the kitchen this
--    month" is being thanked, and being thanked for something true and
--    specific is one of the few things an app can do for a temple that a
--    temple could not already do for itself. A devotee who is told "you are
--    doing rather a lot of pot washing" is being watched — by software, about
--    something they never asked it to notice, in a sentence that arrives at
--    eleven at night with nobody attached to it. The second sentence is the
--    thing the President is supposed to say, in person, having decided to.
--
--    So this function is built from a different set of columns on purpose. No
--    share, because share is the concentration measure. No streak, because a
--    streak reads as a tally. No threshold, no median, no ranking, no
--    comparison to any other devotee, and nothing at all that changes when a
--    devotee crosses a line — a devotee who watched this screen carefully every
--    day could not tell whether they appear on a coordinator's list, because
--    nothing in it moves when they do.
--
--    Everything here is already the devotee's own: these are their own hours,
--    which they served.
-- ---------------------------------------------------------------------------

create or replace function public.my_seva_balance()
returns table (
  service_type_id uuid,
  seva_name text,
  category text,
  hours_this_month numeric,
  hours_this_quarter numeric,
  hours_all_time numeric,
  acts_all_time integer,
  first_served_on date,
  last_served_on date
)
language sql
stable
security definer
set search_path = ''
as $$
  with bounds as (
    select
      public.seva_mala_period_start('month', public.seva_mala_today()) as month_from,
      public.seva_balance_window_start() as quarter_from
  ),
  acts as (
    select acts.*
    from public.seva_balance_acts(auth.uid()) acts
    where auth.uid() is not null
  )
  select
    acts.service_type_id,
    min(acts.seva_name),
    min(acts.category),
    round(coalesce(
      sum(acts.served_minutes) filter (where acts.occurred_on >= bounds.month_from), 0
    ) / 60.0, 2),
    round(coalesce(
      sum(acts.served_minutes) filter (where acts.occurred_on >= bounds.quarter_from), 0
    ) / 60.0, 2),
    round(sum(acts.served_minutes) / 60.0, 2),
    count(*)::integer,
    min(acts.occurred_on),
    max(acts.occurred_on)
  from acts cross join bounds
  group by acts.seva_key, acts.service_type_id
  order by round(sum(acts.served_minutes) / 60.0, 2) desc, min(acts.seva_name)
$$;

comment on function public.my_seva_balance() is
  'Your own seva, kind by kind, in hours. A thank-you note, not a report: no comparison to anybody, nothing that says you have been noticed, nothing that moves when a coordinator looks.';

revoke all on function public.my_seva_balance() from public, anon;
grant execute on function public.my_seva_balance() to authenticated;

do $$
begin
  raise notice 'seva balance applied';
end;
$$;
