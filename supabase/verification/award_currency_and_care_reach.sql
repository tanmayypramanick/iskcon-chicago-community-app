-- Functional verification for 202608040067_award_currency_and_care_reach.sql.
--
-- Rolled back at the end. Every local is prefixed v_ so it can never shadow a
-- column name. Anything a devotee could really attempt is attempted as that
-- devotee, under `set local role authenticated`, so the grants, the row level
-- security and the permission checks are what is being tested rather than
-- superuser rights waving everything through.
--
-- 0067 makes four claims and this file exists to break all four if they are not
-- true.
--
--   1. A BADGE ON AN OPEN PERIOD IS SHOWN ONLY WHILE IT IS STILL EARNED, AND A
--      BADGE ON A CLOSED PERIOD IS NEVER RE-JUDGED. Madhava Priya Das holds
--      award ROWS for weekly recognition and for Dhairya on the week happening
--      now and satisfies neither; both are gone from his profile, both are
--      still on his shelf, and re-running the awarding neither gives them back
--      nor takes them away. The same two badges, on the week that has CLOSED,
--      are untouched — and unfreezing that week is what makes them vanish,
--      which is how we know the frozen arm is the thing holding them up.
--
--   2. SEVA CARE REACHES THE DEVOTEES IT EXISTS TO FIND. Syamasundara Das,
--      Madhava Priya Das and Gopala Krishna Das are each below the
--      congregation-wide weekly bar 0058 gated on, and each is now on the list.
--      The list is FIVE rows, not twenty: everybody doing a normal amount of
--      their own seva is still off it, however many hours that is.
--
--   3. THE FALLBACK IS A FALLBACK. The stand-in for a seva with too few
--      servers is below the median weekly load it replaces, is in the same
--      unit, and is above half the temple's seva normals and below half of
--      them. A sole server no longer faces the hardest gate in the function.
--
--   4. THE BOARD RANKS ON THE NUMBER IT PRINTS, AND MY OWN CARD LEAKS NOBODY.
--      Two devotees publishing 850 share the gold; two publishing 340 share
--      sixth. `standing` and `board_standing` are the same number for every
--      devotee on the board, so their difference can no longer be read as a
--      count of the devotees who are hiding — and a devotee who opted out
--      still gets their own honest place.
--
-- ---------------------------------------------------------------------------
-- The fixture. A small model of the temple this file was written against.
--
-- Twenty-nine devotees, fourteen seva, thirteen weeks. Week 0 is the week
-- happening now and week k is k weeks back; every act is placed on a Monday, so
-- nothing in the fixture can land after today whatever day of the week this is
-- run on.
--
-- The cast, by hours a week in the seva named, and by the unbroken run of weeks
-- they have given it:
--
--   Bhakta Ramesh Patel      Pot Washing           10.00 h/wk   13 weeks
--   Tanmay Pramanick         Mangal Arati Setup     4.50        13     [President]
--   Gopala Krishna Das       Mangal Arati Setup     2.40        13
--                            Sunday Feast Cleanup   1.80        13
--   Syamasundara Das         Kitchen Preparation    2.40        13
--   Madhava Priya Das        Flower Garlands        2.22        12     [sole server]
--   Jahnava Devi Dasi        Temple Room Cleaning   1.80        12
--   six Temple Room servers  Temple Room Cleaning   1.90        12
--   three Kitchen hands      Kitchen Preparation    0.50        12
--   a fourth Kitchen hand    Kitchen Preparation    1.30        stopped
--   Haridasa Das             Pot Washing            2.00        stopped
--   Gauranga Das             Mangal Arati Setup     1.75        stopped
--   Gopinatha Das            Sunday Feast Cleanup   2.00        stopped
--   nine quiet devotees      one seva each      0.30 - 1.00     stopped
--
-- Which makes, and every one of these is asserted below rather than assumed:
--
--   median weekly load          1.75 h/wk   -> the congregation-wide bar, 2.625
--   the run the temple expects  12 weeks
--   a normal seva's normal      1.00 h/wk   -> the stand-in, and the gate 2.00
--
-- So the three devotees the audit named are each under 2.625 hours a week and
-- each over twice the normal for their own seva, which is the whole of the
-- change. Two devotees are over both, and they are the two the list already
-- had.
--
-- Tanmay and one Temple Room server opted OUT of the board, which is what makes
-- claim 4's leak a leak rather than an arithmetic identity.
--
-- The final row must read: award currency and care reach verification passed

begin;

-- ---------------------------------------------------------------------------
-- 0. The ground.
-- ---------------------------------------------------------------------------

do $$
declare
  v_holders text;
begin
  if to_regprocedure('public.seva_mala_award_holds_now(uuid, uuid, uuid)') is null
    or to_regprocedure('public.current_devotee_awards(uuid)') is null
    or to_regprocedure('public.list_seva_concentration(integer, numeric)') is null
    or to_regprocedure('public.list_seva_garland(text, integer, text)') is null
    or to_regprocedure('public.my_seva_mala(text)') is null
    or to_regprocedure('public.list_all_seva_scores(text)') is null
    or to_regprocedure('public.seva_yatra_devotee_summary(uuid, text)') is null
  then
    raise exception '202608040067 is not applied.';
  end if;

  -- Claim 1 is a read-side rule and is only honest while the row underneath it
  -- cannot be deleted. Without this trigger, "the display stopped matching" and
  -- "somebody took it away" would be the same thing.
  if not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.devotee_awards'::regclass
      and tgname = 'devotee_awards_append_only'
      and not tgisinternal
  ) then
    raise exception 'The append-only trigger on devotee_awards is gone.';
  end if;

  select string_agg(roles.name, ',' order by roles.name) into v_holders
  from public.role_permissions
  join public.roles on roles.id = role_permissions.role_id
  where role_permissions.permission_key = 'app.view_all';
  if v_holders is distinct from 'president,tech' then
    raise exception 'app.view_all is held by %.', v_holders;
  end if;

  -- Every promise below about what is withheld is only a promise while the
  -- tables themselves stay shut.
  if has_table_privilege('authenticated', 'public.period_scores', 'select')
    or has_table_privilege('authenticated', 'public.seva_mala_periods', 'select')
    or has_table_privilege('authenticated', 'public.app_settings', 'select')
  then
    raise exception 'A devotee can read something 0067 answers about.';
  end if;

  -- The fixture is laid out under these five numbers.
  if public.seva_mala_number('seva_mala.minimum_cohort', 8) <> 8 then
    raise exception 'The minimum cohort is not eight.';
  end if;
  if public.seva_mala_number('seva_balance.frequency_multiple', 2.0) <> 2.0 then
    raise exception 'The frequency multiple is not two.';
  end if;
  if public.seva_mala_number('seva_balance.frequency_min_peers', 3) <> 3 then
    raise exception 'The peer minimum is not three.';
  end if;
  if public.seva_mala_number('seva_balance.frequency_normal_quantile', 0.5) <> 0.5 then
    raise exception 'A seva''s own normal is no longer its median.';
  end if;
  if public.seva_mala_number('seva_balance.frequency_fallback_quantile', 0.5) <> 0.5 then
    raise exception 'The stand-in is no longer the middle of the seva normals.';
  end if;
  if public.seva_mala_number('seva_balance.window_weeks', 13) <> 13 then
    raise exception 'The window is not thirteen weeks; every date below is wrong.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 1. The doors, and what may not go through them.
-- ---------------------------------------------------------------------------

do $$
declare
  v_columns text;
  v_name text;
begin
  -- Nothing 0067 touched changed shape. Four shipped screens read these.
  select string_agg(parameters.parameter_name, ', ' order by parameters.ordinal_position)
  into v_columns
  from information_schema.parameters parameters
  where parameters.specific_schema = 'public'
    and parameters.specific_name like 'list\_seva\_garland%'
    and parameters.parameter_mode = 'OUT';
  if v_columns <> 'standing, devotee_id, devotee_name, devotee_photo_url, points, '
                  || 'tier, is_you, gathering' then
    raise exception 'list_seva_garland returns (%).', v_columns;
  end if;

  select string_agg(parameters.parameter_name, ', ' order by parameters.ordinal_position)
  into v_columns
  from information_schema.parameters parameters
  where parameters.specific_schema = 'public'
    and parameters.specific_name like 'my\_seva\_mala%'
    and parameters.parameter_mode = 'OUT';
  if v_columns not like '%standing, board_standing, cohort_size%' then
    raise exception 'my_seva_mala returns (%).', v_columns;
  end if;

  select string_agg(parameters.parameter_name, ', ' order by parameters.ordinal_position)
  into v_columns
  from information_schema.parameters parameters
  where parameters.specific_schema = 'public'
    and parameters.specific_name like 'list\_seva\_concentration%'
    and parameters.parameter_mode = 'OUT';
  if v_columns not like '%min_hours_used, min_weeks_used, min_multiple_used, note' then
    raise exception
      'list_seva_concentration no longer ends with the three thresholds and the note: (%).',
      v_columns;
  end if;

  -- THE COMPONENTS ARE STILL NOT DECLARED ANYWHERE A DEVOTEE CAN REACH. 0060
  -- section 3 and 0066 section 5; restated because 0067 rewrote four reads.
  select string_agg(distinct proc.proname, ', ' order by proc.proname) into v_columns
  from pg_proc proc
  join pg_namespace spaces on spaces.oid = proc.pronamespace
  where spaces.nspname = 'public'
    and has_function_privilege('authenticated', proc.oid, 'execute')
    and (
      pg_get_function_result(proc.oid) like '%seva_norm%'
      or pg_get_function_result(proc.oid) like '%giving_norm%'
    );
  if v_columns is distinct from 'explain_my_score, list_all_seva_scores' then
    raise exception 'The functions returning a component are now: %.', v_columns;
  end if;

  -- The read-time re-ask answers a question about the whole congregation's
  -- distribution. It is machinery, not a door.
  foreach v_name in array array[
    'public.seva_mala_award_holds_now(uuid, uuid, uuid)',
    'public.current_devotee_awards(uuid)',
    'public.seva_mala_period_measures(text, date, date, text)',
    'public.award_seva_mala_for_period(uuid)',
    'public.seva_balance_references()'
  ] loop
    if has_function_privilege('authenticated', v_name, 'execute') then
      raise exception 'A devotee can execute %.', v_name;
    end if;
  end loop;

  -- And the doors are still doors.
  foreach v_name in array array[
    'public.my_seva_mala(text)',
    'public.list_seva_garland(text, integer, text)',
    'public.list_devotee_badges(uuid)',
    'public.list_devotee_award_shelf(uuid)',
    'public.list_seva_concentration(integer, numeric)',
    'public.list_all_seva_scores(text)',
    'public.seva_yatra_devotee_summary(uuid, text)'
  ] loop
    if not has_function_privilege('authenticated', v_name, 'execute') then
      raise exception 'authenticated may not execute %.', v_name;
    end if;
    if has_function_privilege('anon', v_name, 'execute') then
      raise exception 'A signed-out visitor may execute %.', v_name;
    end if;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. The congregation.
-- ---------------------------------------------------------------------------

create table public.ac_ids (key text primary key, id uuid not null);
grant select on public.ac_ids to authenticated;

do $$
declare
  v_who record;
  v_i integer := 0;
begin
  for v_who in
    select * from (values
      ('ramesh',    'Bhakta Ramesh Patel'),
      ('tanmay',    'Tanmay Pramanick'),
      ('gopala',    'Gopala Krishna Das'),
      ('syama',     'Syamasundara Das'),
      ('madhava',   'Madhava Priya Das'),
      ('jahnava',   'Jahnava Devi Dasi'),
      ('trc1',      'Temple Room One Das'),
      ('trc2',      'Temple Room Two Das'),
      ('trc3',      'Temple Room Three Das'),
      ('trc4',      'Temple Room Four Das'),
      ('trc5',      'Temple Room Five Das'),
      ('trc6',      'Temple Room Six Das'),
      ('kit1',      'Kitchen Hand One Das'),
      ('kit2',      'Kitchen Hand Two Das'),
      ('kit3',      'Kitchen Hand Three Das'),
      ('kit4',      'Kitchen Hand Four Das'),
      ('haridasa',  'Haridasa Das'),
      ('gauranga',  'Gauranga Das'),
      ('gopinatha', 'Gopinatha Das'),
      ('arpita',    'Arpita Jadhav'),
      ('sundari',   'Sundari Gopi Devi Dasi'),
      ('anjali',    'Bhaktin Anjali Sharma'),
      ('nitai',     'Nitai Charan Das'),
      ('haribhakta','Hari Bhakta Das'),
      ('kaustubha', 'Kaustubha Das'),
      ('kirtan',    'Krsna Kirtan Das'),
      ('ananta',    'Ananta Sesa Das'),
      ('radha',     'Radha Vallabha Devi Dasi'),
      ('acyuta',    'Acyuta Gopal Das')
    ) as cast_member(key, name)
  loop
    v_i := v_i + 1;
    insert into auth.users (id, email, raw_user_meta_data)
    values (
      ('67000000-0000-0000-0000-0000000000' || lpad(v_i::text, 2, '0'))::uuid,
      'ac-' || v_who.key || '@example.test',
      jsonb_build_object('name', v_who.name)
    );

    update public.users set name = v_who.name
    where users.email = 'ac-' || v_who.key || '@example.test';

    insert into public.ac_ids (key, id)
    select v_who.key, users.id
    from public.users where users.email = 'ac-' || v_who.key || '@example.test';
  end loop;
end;
$$;

-- The President, who is also the second-heaviest server in the temple and who
-- has opted out of the board. Both of those are load-bearing: the first is what
-- makes Seva Care a list he is on, and the second is what makes the leak in
-- section 8 a leak.
update public.users
set role_id = (select roles.id from public.roles where roles.name = 'president')
where users.email = 'ac-tanmay@example.test';

update public.users
set leaderboard_visible = (users.email not in
  ('ac-tanmay@example.test', 'ac-trc6@example.test'))
where users.email like 'ac-%@example.test';

-- ---------------------------------------------------------------------------
-- 3. The facts.
--
--    One helper, so that four hundred acts read as a plan. Every act is on a
--    Monday: week 0's Monday is this week's, which is on or before today
--    whatever day this runs on, so no act can fall in the future and no
--    assertion can depend on the weekday.
-- ---------------------------------------------------------------------------

create function public.ac_serve(
  p_key text,
  p_seva text,
  p_on date,
  p_minutes integer
)
returns void
language plpgsql
as $$
declare
  v_instance uuid;
begin
  insert into public.service_instances (
    service_type_id, date, start_time, duration_minutes, slots_needed,
    participation_mode, posted_by, status
  )
  select service_types.id, p_on, time '09:00', p_minutes, 1, 'open', null, 'completed'
  from public.service_types where service_types.name = p_seva
  returning id into v_instance;

  if v_instance is null then
    raise exception 'There is no service type called %.', p_seva;
  end if;

  insert into public.service_assignments (
    service_instance_id, devotee_id, assignment_method, status,
    verification, attendance, completed_at
  ) values (
    v_instance,
    (select ids.id from public.ac_ids ids where ids.key = p_key),
    'self_joined', 'completed', 'member_verified', 'served',
    (p_on + time '12:00') at time zone 'America/Chicago'
  );
end;
$$;

-- A run of weeks in one seva, from week p_last back through p_weeks of them,
-- p_minutes a week. Weeks are counted back from this week's Monday.
create function public.ac_run(
  p_key text, p_seva text, p_minutes integer, p_weeks integer, p_last integer default 0
)
returns void
language plpgsql
as $$
declare
  v_monday date := public.seva_mala_week_start(public.seva_mala_today());
  v_k integer;
begin
  for v_k in p_last .. (p_last + p_weeks - 1) loop
    perform public.ac_serve(p_key, p_seva, v_monday - 7 * v_k, p_minutes);
  end loop;
end;
$$;

do $$
declare
  v_who text;
begin
  -- ---- The five the list must end up holding. ----------------------------
  perform public.ac_run('ramesh',  'Pot Washing',          600, 13);
  perform public.ac_run('tanmay',  'Mangal Arati Setup',   270, 13);
  perform public.ac_run('gopala',  'Mangal Arati Setup',   144, 13);
  perform public.ac_run('gopala',  'Sunday Feast Cleanup', 108, 13);
  perform public.ac_run('syama',   'Kitchen Preparation',  144, 13);

  -- Madhava, the sole server of Flower Garlands. Twelve weeks, and a quarter of
  -- an hour in the week happening now — which is what puts him below this
  -- week's median score while leaving his twelve-week run intact. Both of those
  -- are what section 6 is about.
  perform public.ac_run('madhava', 'Flower Garlands',      144, 11, 1);
  perform public.ac_serve('madhava', 'Flower Garlands',
                          public.seva_mala_week_start(public.seva_mala_today()), 15);

  -- ---- The devotees who must NOT be on it, for the right reasons. ---------
  -- Jahnava gives a shade LESS than the six others who clean the temple room,
  -- and all seven of them are doing a normal amount of a seva seven people
  -- share. Twelve weeks each, so it is the ratio and not the run that keeps
  -- them off.
  perform public.ac_run('jahnava', 'Temple Room Cleaning', 108, 12);
  foreach v_who in array array['trc1', 'trc2', 'trc3', 'trc4', 'trc5', 'trc6'] loop
    perform public.ac_run(v_who, 'Temple Room Cleaning', 114, 12);
  end loop;

  -- The kitchen hands are Syamasundara's peers: three of them at half an hour a
  -- week for twelve weeks, and a fourth who used to give an hour and twenty and
  -- stopped a month ago. They are not all the same number on purpose — a peer
  -- group with no spread in it cannot tell a median from any other quantile,
  -- and mutation 7 is the assertion that the median is the median.
  foreach v_who in array array['kit1', 'kit2', 'kit3'] loop
    perform public.ac_run(v_who, 'Kitchen Preparation', 30, 12);
  end loop;
  perform public.ac_run('kit4', 'Kitchen Preparation', 78, 5, 4);

  -- ---- And the devotees who stopped. Their runs ended four weeks ago, so
  --      they are nobody's current concern and they count zero weeks running.
  perform public.ac_run('haridasa',  'Pot Washing',          120, 3, 4);
  perform public.ac_run('gauranga',  'Mangal Arati Setup',   105, 4, 4);
  perform public.ac_run('gopinatha', 'Sunday Feast Cleanup', 120, 7, 4);
  perform public.ac_run('arpita',    'Guest Welcome',         60, 5, 4);
  perform public.ac_run('sundari',   'Guest Welcome',         60, 5, 4);
  perform public.ac_run('anjali',    'Guest Welcome',         30, 5, 4);
  perform public.ac_run('nitai',     'Vegetable Cutting',     60, 5, 4);
  perform public.ac_run('haribhakta','Book Table',            45, 5, 4);
  perform public.ac_run('kaustubha', 'Shoe Room',             30, 5, 4);
  perform public.ac_run('kirtan',    'Kirtana Support',       24, 5, 4);
  perform public.ac_run('ananta',    'General Temple Service',18, 5, 4);
  perform public.ac_run('radha',     'Prasadam Serving',      60, 5, 4);
  perform public.ac_run('acyuta',    'Festival Decoration',   36, 5, 4);
end;
$$;

-- The fixture's own premise, said out loud over the WHOLE database rather than
-- over this file's cast, because everything below is arithmetic on these.
do $$
declare
  v_refs record;
  v_standing_in numeric;
  v_sevas integer;
  v_without_normal integer;
begin
  select * into v_refs from public.seva_balance_references();

  if v_refs.devotees_considered <> 29 then
    raise exception 'The congregation is % devotees rather than 29.',
      v_refs.devotees_considered;
  end if;
  if v_refs.gathering then
    raise exception 'Twenty-nine devotees read as still gathering.';
  end if;
  if v_refs.median_weekly_hours <> 1.75 then
    raise exception 'The median weekly load is % rather than 1.75.',
      v_refs.median_weekly_hours;
  end if;
  if v_refs.weekly_hours_threshold <> 2.625 then
    raise exception
      'The congregation-wide weekly bar is % rather than 2.625; the three devotees this file is about are meant to be UNDER it.',
      v_refs.weekly_hours_threshold;
  end if;
  if v_refs.consecutive_weeks_threshold <> 12 then
    raise exception 'The run the temple expects is % weeks rather than 12.',
      v_refs.consecutive_weeks_threshold;
  end if;

  -- And the number this migration invented: what a normal seva's normal is.
  -- Computed here the long way rather than read off the function, so that a
  -- change to the function is caught rather than mirrored.
  with acts as (select * from public.seva_balance_acts()),
  windowed as (
    select * from acts
    where acts.occurred_on between v_refs.window_starts_on and v_refs.window_ends_on
  ),
  active as (
    select windowed.devotee_id, count(distinct windowed.week_start)::numeric as weeks
    from windowed group by 1
  ),
  by_type as (
    select windowed.devotee_id, windowed.seva_key,
           sum(windowed.served_minutes) / 60.0 as hours
    from windowed group by 1, 2
  ),
  rates as (
    select by_type.devotee_id, by_type.seva_key, by_type.hours / active.weeks as per_week
    from by_type join active on active.devotee_id = by_type.devotee_id
  ),
  normals as (
    select rates.seva_key,
           count(*) as servers,
           percentile_cont(0.5) within group (order by rates.per_week)::numeric as normal
    from rates group by 1
  )
  select
    (select percentile_cont(0.5) within group (order by normals.normal)::numeric
       from normals),
    (select count(*)::integer from normals),
    (select count(*)::integer from normals where normals.servers < 4)
  into v_standing_in, v_sevas, v_without_normal;

  if v_sevas <> 14 then
    raise exception 'The temple serves % kinds of seva rather than 14.', v_sevas;
  end if;
  if round(v_standing_in, 4) <> 1.0000 then
    raise exception 'A normal seva''s normal is % rather than 1.00 hours a week.',
      round(v_standing_in, 4);
  end if;

  -- CLAIM 3, at the level of the two numbers. The stand-in is BELOW the median
  -- weekly load it replaces, and the thing it replaces was above most of the
  -- real per-seva normals — which is the whole finding.
  if v_standing_in >= v_refs.median_weekly_hours then
    raise exception
      'The stand-in (%) is not below the median weekly load (%) it replaces; it is not a fallback.',
      v_standing_in, v_refs.median_weekly_hours;
  end if;
  if v_without_normal < 8 then
    raise exception
      'Only % of the temple''s seva have too few servers to have a normal of their own; the fallback is not the common case and this fixture proves nothing.',
      v_without_normal;
  end if;
end;
$$;

-- The stand-in is a MIDDLE, which is the property that makes it a fallback
-- rather than a wall: above half the temple's seva normals and below half.
do $$
declare
  v_above integer;
  v_below integer;
begin
  with acts as (select * from public.seva_balance_acts()),
  refs as (select * from public.seva_balance_references()),
  windowed as (
    select acts.* from acts, refs
    where acts.occurred_on between refs.window_starts_on and refs.window_ends_on
  ),
  active as (
    select windowed.devotee_id, count(distinct windowed.week_start)::numeric as weeks
    from windowed group by 1
  ),
  by_type as (
    select windowed.devotee_id, windowed.seva_key,
           sum(windowed.served_minutes) / 60.0 as hours
    from windowed group by 1, 2
  ),
  rates as (
    select by_type.devotee_id, by_type.seva_key, by_type.hours / active.weeks as per_week
    from by_type join active on active.devotee_id = by_type.devotee_id
  ),
  normals as (
    select rates.seva_key,
           percentile_cont(0.5) within group (order by rates.per_week)::numeric as normal
    from rates group by 1
  ),
  middle as (
    select percentile_cont(0.5) within group (order by normals.normal)::numeric as m
    from normals
  )
  select
    count(*) filter (where normals.normal > middle.m),
    count(*) filter (where normals.normal < middle.m)
  into v_above, v_below
  from normals cross join middle;

  if v_above = 0 or v_below = 0 then
    raise exception
      'The stand-in is above % seva normals and below %; a stand-in at the edge of the distribution is the bug 0067 section 3 is about.',
      v_below, v_above;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. CLAIM 2 AND CLAIM 3: Seva Care reaches them, and stays short.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.ac_ids ids where ids.key = 'tanmay'), true);

do $$
declare
  v_names text;
  v_rows integer;
  v_old integer;
  v_row record;
begin
  select count(*)::integer,
         string_agg(listed.devotee_name || ' / ' || listed.seva_name, '; '
                    order by listed.devotee_name)
  into v_rows, v_names
  from public.list_seva_concentration() listed;

  -- FIVE. Not two, and not twenty. The temple's original complaint was that
  -- this list was too long and they will not thank anybody for fixing an
  -- exclusion by returning the congregation.
  if v_rows <> 5 then
    raise exception 'Seva Care returned % rows: [%].', v_rows, coalesce(v_names, '(nobody)');
  end if;

  foreach v_names in array array[
    'Bhakta Ramesh Patel', 'Tanmay Pramanick', 'Gopala Krishna Das',
    'Syamasundara Das', 'Madhava Priya Das'
  ] loop
    if not exists (
      select 1 from public.list_seva_concentration() listed
      where listed.devotee_name = v_names
    ) then
      raise exception '% is not on the Seva Care list.', v_names;
    end if;
  end loop;

  -- THE LIST 0058 AND 0066 PRODUCED, recovered from the row itself: the rows at
  -- or above the congregation-wide weekly bar, which is what the old gate was.
  -- Two of them, which is what the audit found on the temple's own data.
  select count(*)::integer into v_old
  from public.list_seva_concentration() listed
  where listed.hours_per_week >= listed.min_hours_used;
  if v_old <> 2 then
    raise exception
      'The congregation-wide bar would have surfaced % of these rows rather than 2.',
      v_old;
  end if;

  -- And the three the audit named are each UNDER it — which is to say each of
  -- them was excluded by the wrong comparison and by nothing else.
  for v_row in
    select * from public.list_seva_concentration()
    where devotee_name in ('Gopala Krishna Das', 'Syamasundara Das', 'Madhava Priya Das')
  loop
    if v_row.hours_per_week >= v_row.min_hours_used then
      raise exception
        '% gives %h a week against a congregation-wide bar of %h; he was not excluded by it and proves nothing.',
        v_row.devotee_name, v_row.hours_per_week, v_row.min_hours_used;
    end if;
    if v_row.hours_vs_peers < v_row.min_multiple_used then
      raise exception
        '% reads %x the normal for % against a multiple of %.',
        v_row.devotee_name, v_row.hours_vs_peers, v_row.seva_name, v_row.min_multiple_used;
    end if;
  end loop;

  -- EVERY row on the list is at or above the multiple for its own seva, and
  -- both numbers that decided it travel with it, so a President can always ask
  -- "compared to what?".
  if exists (
    select 1 from public.list_seva_concentration() listed
    where listed.hours_vs_peers < listed.min_multiple_used
       or listed.consecutive_weeks < listed.min_weeks_used
       or listed.min_multiple_used <> 2.00
       or listed.min_weeks_used <> 12
  ) then
    raise exception 'A row is on the list without clearing the two gates it reports.';
  end if;

  -- 0058's note survives, because a shipped screen renders it.
  select * into v_row from public.list_seva_concentration()
  where devotee_name = 'Syamasundara Das';
  if v_row.note not like '%Syamasundara Das has given 2.4 hours a week to Kitchen Preparation for 13 weeks running%'
     or v_row.note not like '%Worth asking how they are finding it%' then
    raise exception 'The note reads: %', v_row.note;
  end if;
  if v_row.note ~* '(burn ?out|overwork|problem|violation|flag|warn|must )' then
    raise exception 'The note reads as a verdict rather than a conversation: %', v_row.note;
  end if;
end;
$$;

-- NOT ON IT, AND FOR THE RIGHT REASON. Seven devotees clean the temple room at
-- around the same rate for twelve weeks each; four give half an hour a week to
-- the kitchen for twelve weeks each. Every one of them clears the run and none
-- of them is doing more of their seva than that seva takes.
do $$
declare
  v_offender text;
begin
  select string_agg(listed.devotee_name, ', ' order by listed.devotee_name)
  into v_offender
  from public.list_seva_concentration() listed
  where listed.devotee_name like 'Temple Room%'
     or listed.devotee_name like 'Kitchen Hand%'
     or listed.devotee_name = 'Jahnava Devi Dasi';
  if v_offender is not null then
    raise exception
      'A devotee doing a normal amount of their own seva was surfaced: %.', v_offender;
  end if;

  -- Gopala is on the list for Mangal Arati and NOT for Sunday Feast Cleanup,
  -- although he has given that one thirteen unbroken weeks too. The gate is
  -- per seva, not per devotee.
  if exists (
    select 1 from public.list_seva_concentration() listed
    where listed.devotee_name = 'Gopala Krishna Das'
      and listed.seva_name = 'Sunday Feast Cleanup'
  ) then
    raise exception 'Gopala was surfaced for a normal amount of Sunday Feast Cleanup.';
  end if;
end;
$$;

-- THE SOLE SERVER, WHICH IS THE WHOLE OF CLAIM 3. Madhava is the only devotee
-- who has ever made a garland. Under the old fallback he was judged against the
-- busiest devotees in the temple; under the new one he is judged against what a
-- seva normally takes.
do $$
declare
  v_refs record;
  v_row record;
  v_old_bar numeric;
  v_new_bar numeric;
begin
  select * into v_refs from public.seva_balance_references();
  select * into v_row from public.list_seva_concentration()
  where devotee_name = 'Madhava Priya Das';

  if v_row.share_of_their_seva <> 1 then
    raise exception 'Madhava is not the sole server of his own seva; his share reads %.',
      v_row.share_of_their_seva;
  end if;

  v_old_bar := 2.0 * v_refs.median_weekly_hours;
  v_new_bar := v_row.hours_per_week / v_row.hours_vs_peers * 2.0;

  if v_new_bar >= v_old_bar then
    raise exception
      'A sole server now faces %h a week against the old %h. The fallback did not get looser.',
      round(v_new_bar, 3), round(v_old_bar, 3);
  end if;
  if v_row.hours_per_week >= v_old_bar then
    raise exception
      'Madhava clears the OLD bar too (%h a week against %h), so this proves nothing.',
      v_row.hours_per_week, v_old_bar;
  end if;
end;
$$;

-- A NAMED THRESHOLD IS STILL THE CALLER'S QUESTION. 0066 section 4's rule: a
-- derived gate that silently overrode an explicit one would make the parameter
-- a lie.
do $$
declare
  v_rows integer;
begin
  select count(*)::integer into v_rows
  from public.list_seva_concentration(p_min_weeks => 12, p_min_hours => 5) listed;
  if v_rows <> 1 then
    raise exception
      'An explicit five hours a week returned % rows; only Ramesh gives that much.', v_rows;
  end if;
  if (select min(listed.min_multiple_used)
      from public.list_seva_concentration(p_min_weeks => 12, p_min_hours => 5) listed) <> 0 then
    raise exception 'The row does not say the per-seva gate was stood down.';
  end if;

  -- A named bar BELOW the derived one still answers the caller's question and
  -- is not quietly raised back up to it.
  select count(*)::integer into v_rows
  from public.list_seva_concentration(p_min_weeks => 12, p_min_hours => 0.4) listed;
  if v_rows <= 5 then
    raise exception
      'A named bar of 0.4 hours a week returned % rows — no more than the derived list, so the parameter is not being honoured.',
      v_rows;
  end if;

  -- And 0058's own refusals are unchanged.
  begin
    perform * from public.list_seva_concentration(p_min_weeks => 0);
    raise exception 'Zero weeks was accepted.';
  exception when others then
    if sqlerrm not like '%at least one week%' then
      raise exception 'Zero weeks was answered with: %', sqlerrm;
    end if;
  end;
end;
$$;

select set_config('request.jwt.claim.sub', '', true);

-- ---------------------------------------------------------------------------
-- 5. The periods.
--
--    Week A and week B close; the week happening now and the lifetime stay
--    open. Week B is what carries a badge across the gap, and the week
--    happening now is what section 6 is about.
-- ---------------------------------------------------------------------------

create table public.ac_periods (label text primary key, id uuid not null);
grant select on public.ac_periods to authenticated;

insert into public.ac_periods (label, id)
select 'A', public.ensure_seva_mala_period('week',
  public.seva_mala_week_start(public.seva_mala_today()) - 14);
select public.recompute_seva_mala_period((select id from public.ac_periods where label = 'A'))
  as week_a;

insert into public.ac_periods (label, id)
select 'B', public.ensure_seva_mala_period('week',
  public.seva_mala_week_start(public.seva_mala_today()) - 7);
select public.recompute_seva_mala_period((select id from public.ac_periods where label = 'B'))
  as week_b;

insert into public.ac_periods (label, id)
select 'W0', public.ensure_seva_mala_period('week',
  public.seva_mala_week_start(public.seva_mala_today()));
select public.recompute_seva_mala_period((select id from public.ac_periods where label = 'W0'))
  as week_now;

insert into public.ac_periods (label, id)
select 'L', public.ensure_seva_mala_period('lifetime', public.seva_mala_today());
select public.recompute_seva_mala_period((select id from public.ac_periods where label = 'L'))
  as lifetime;

do $$
declare
  v_row record;
begin
  for v_row in
    select periods.frozen_at, periods.participant_count, ac_periods.label
    from public.ac_periods
    join public.seva_mala_periods periods on periods.id = ac_periods.id
  loop
    if v_row.label in ('A', 'B') and v_row.frozen_at is null then
      raise exception 'Week % did not close.', v_row.label;
    end if;
    if v_row.label in ('W0', 'L') and v_row.frozen_at is not null then
      raise exception 'Period % closed; it is meant to be open.', v_row.label;
    end if;
    if v_row.label in ('B', 'W0')
       and v_row.participant_count < public.seva_mala_number('seva_mala.minimum_cohort', 8)
    then
      raise exception 'Week % is below the cohort, so no badge would publish.', v_row.label;
    end if;
  end loop;

  if (select period_id from public.current_award_periods() where period_kind = 'week')
     is distinct from (select id from public.ac_periods where label = 'B')
  then
    raise exception 'Week B is not the current weekly leaderboard.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. CLAIM 1: a badge is worn while it is still being earned.
--
--    The premise first, computed from the same two functions the awarding uses,
--    because everything below is a claim about these two facts:
--
--      Madhava's run of twelve weeks is BELOW the bar Dhairya is set at.
--      Madhava's score this week is BELOW the median weekly recognition is set
--      at.
--
--    and Ramesh is above both. Neither is written down here; both are derived.
-- ---------------------------------------------------------------------------

do $$
declare
  v_w0 uuid := (select id from public.ac_periods where label = 'W0');
  v_madhava uuid := (select ids.id from public.ac_ids ids where ids.key = 'madhava');
  v_ramesh uuid := (select ids.id from public.ac_ids ids where ids.key = 'ramesh');
  v_from date;
  v_to date;
  v_bar numeric;
  v_his numeric;
  v_hers numeric;
begin
  select periods.starts_on, least(periods.ends_on, public.seva_mala_today())
  into v_from, v_to
  from public.seva_mala_periods periods where periods.id = v_w0;

  -- Dhairya: the eighty-fifth percentile of the runs that reach this week.
  select percentile_cont(0.85) within group (order by measures.value)
           filter (where measures.value > 0),
         max(measures.value) filter (where measures.devotee_id = v_madhava),
         max(measures.value) filter (where measures.devotee_id = v_ramesh)
  into v_bar, v_his, v_hers
  from public.seva_mala_period_measures('week', v_from, v_to, 'longest_run_weeks') measures;

  if v_his is null or v_his >= v_bar then
    raise exception
      'Madhava runs % weeks against a Dhairya bar of %; he still earns it and section 6 proves nothing.',
      coalesce(v_his, 0), v_bar;
  end if;
  if v_hers < v_bar then
    raise exception
      'Ramesh runs % weeks against a bar of % — the control does not earn it either.',
      v_hers, v_bar;
  end if;

  -- Weekly recognition: the median of this week's positive scores.
  select percentile_cont(0.5) within group (order by scores.score)
           filter (where scores.score > 0),
         max(scores.score) filter (where scores.devotee_id = v_madhava),
         max(scores.score) filter (where scores.devotee_id = v_ramesh)
  into v_bar, v_his, v_hers
  from public.period_scores scores where scores.period_id = v_w0;

  if v_his is null or v_his >= v_bar then
    raise exception
      'Madhava scores % against a median of %; he still earns weekly recognition.',
      coalesce(v_his, 0), v_bar;
  end if;
  if v_hers < v_bar then
    raise exception 'Ramesh scores % against a median of %.', v_hers, v_bar;
  end if;
end;
$$;

-- Tuesday's awards, written down. This is not the test cheating: it is exactly
-- what public.devotee_awards holds in production, because a derived_threshold
-- badge is handed out live and the row records the moment the devotee was above
-- the bar, not the moment somebody last looked.
do $$
declare
  v_madhava uuid := (select ids.id from public.ac_ids ids where ids.key = 'madhava');
  v_w0 uuid := (select id from public.ac_periods where label = 'W0');
  v_b uuid := (select id from public.ac_periods where label = 'B');
  v_code text;
begin
  foreach v_code in array array['weekly_dhairya', 'weekly_recognition'] loop
    -- On the week happening now, which is open and which has moved under him.
    insert into public.devotee_awards (award_definition_id, devotee_id, period_id)
    select definitions.id, v_madhava, v_w0
    from public.award_definitions definitions where definitions.code = v_code
    on conflict do nothing;

    -- And on the week that has CLOSED, which must never be re-judged.
    insert into public.devotee_awards (award_definition_id, devotee_id, period_id)
    select definitions.id, v_madhava, v_b
    from public.award_definitions definitions where definitions.code = v_code
    on conflict do nothing;
  end loop;

  if (select count(*) from public.devotee_awards awards
      join public.award_definitions definitions on definitions.id = awards.award_definition_id
      where awards.devotee_id = v_madhava
        and awards.period_id in (v_w0, v_b)
        and definitions.code in ('weekly_dhairya', 'weekly_recognition')) <> 4
  then
    raise exception 'The four award rows this section is about were not written.';
  end if;
end;
$$;

-- THE OPEN WEEK'S TWO ARE GONE FROM HIS PROFILE. THE CLOSED WEEK'S TWO ARE NOT.
do $$
declare
  v_madhava uuid := (select ids.id from public.ac_ids ids where ids.key = 'madhava');
  v_ramesh uuid := (select ids.id from public.ac_ids ids where ids.key = 'ramesh');
  v_w0_start date := (select periods.starts_on from public.seva_mala_periods periods
                      where periods.id = (select id from public.ac_periods where label = 'W0'));
  v_b_start date := (select periods.starts_on from public.seva_mala_periods periods
                     where periods.id = (select id from public.ac_periods where label = 'B'));
  v_row record;
  v_code text;
begin
  perform set_config('request.jwt.claim.sub', v_madhava::text, true);

  foreach v_code in array array['weekly_dhairya', 'weekly_recognition'] loop
    select * into v_row from public.list_devotee_badges(v_madhava)
    where award_code = v_code;

    if v_row.award_code is null then
      raise exception
        '% vanished from Madhava''s profile altogether. The closed week''s copy must still be worn — nothing is taken back once a period ends.',
        v_code;
    end if;
    if v_row.period_start = v_w0_start then
      raise exception
        '% is still worn for the OPEN week, which he no longer earns it in.', v_code;
    end if;
    if v_row.period_start <> v_b_start then
      raise exception '% is worn for the week beginning % rather than %.',
        v_code, v_row.period_start, v_b_start;
    end if;
  end loop;

  -- NOTHING WAS DELETED. Both open-week rows are on his shelf, flagged as not
  -- currently displayed, which is the whole difference between an expiry that
  -- is a join and an expiry that is a DELETE.
  if (select count(*) from public.list_devotee_award_shelf(v_madhava) shelf
      where shelf.period_start = v_w0_start
        and shelf.award_code in ('weekly_dhairya', 'weekly_recognition')
        and not shelf.is_current) <> 2
  then
    raise exception
      'The two stale awards are not on Madhava''s shelf as earned-but-not-current.';
  end if;
  if (select count(*) from public.list_devotee_award_shelf(v_madhava) shelf
      where shelf.period_start = v_b_start
        and shelf.award_code in ('weekly_dhairya', 'weekly_recognition')
        and shelf.is_current) <> 2
  then
    raise exception 'The closed week''s awards stopped being current.';
  end if;

  -- AND THE CONTROL. Ramesh is above both bars, holds both on the week
  -- happening now, and wears them for the week happening now — 0066 section 3's
  -- rule, which 0067 must not have quietly undone.
  perform set_config('request.jwt.claim.sub', v_ramesh::text, true);
  foreach v_code in array array['weekly_dhairya', 'weekly_recognition'] loop
    select * into v_row from public.list_devotee_badges(v_ramesh) where award_code = v_code;
    if v_row.award_code is null then
      raise exception 'Ramesh earns % this week and is not wearing it.', v_code;
    end if;
    if v_row.period_start <> v_w0_start then
      raise exception
        'Ramesh wears % for the week beginning % rather than the one happening now.',
        v_code, v_row.period_start;
    end if;
  end loop;

  perform set_config('request.jwt.claim.sub', '', true);
end;
$$;

-- RE-RUNNING THE AWARDING ADDS NOTHING AND REMOVES NOTHING, which is the audit's
-- own sentence and the reason the fix could not live in the awarding.
do $$
declare
  v_w0 uuid := (select id from public.ac_periods where label = 'W0');
  v_before bigint;
  v_after bigint;
  v_given integer;
begin
  select count(*) into v_before from public.devotee_awards where period_id = v_w0;
  v_given := public.award_seva_mala_for_period(v_w0);
  select count(*) into v_after from public.devotee_awards where period_id = v_w0;

  if v_after <> v_before then
    raise exception 'Re-awarding the open week changed the row count from % to %.',
      v_before, v_after;
  end if;
  if v_given <> 0 then
    raise exception 'Re-awarding the open week handed out % more awards.', v_given;
  end if;
  if not exists (
    select 1 from public.devotee_awards awards
    join public.award_definitions definitions on definitions.id = awards.award_definition_id
    where awards.period_id = v_w0
      and awards.devotee_id = (select ids.id from public.ac_ids ids where ids.key = 'madhava')
      and definitions.code = 'weekly_dhairya'
  ) then
    raise exception 'Re-awarding removed a stale award. Nothing in Seva Mala revokes.';
  end if;
end;
$$;

-- AND AN AWARD IS NOT DELETABLE, so "it stopped being displayed" and "somebody
-- took it away" cannot be confused for one another.
do $$
declare
  v_message text := '(nothing)';
begin
  begin
    delete from public.devotee_awards
    where id = (select id from public.devotee_awards limit 1);
  exception when others then v_message := sqlerrm;
  end;
  if v_message not like '%cannot be taken back%' then
    raise exception 'An award was deleted, and the answer was: %', v_message;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. CLAIM 4a: the board ranks on the number it prints.
--
--    Two pairs, planted with the exact scores the audit found in production.
--    Written into public.period_scores directly and NOT recomputed afterwards:
--    the claim is about the ranking, and steering a whole scoring model to land
--    two devotees eight ten-thousandths apart would be testing the wrong file.
-- ---------------------------------------------------------------------------

do $$
declare
  v_w0 uuid := (select id from public.ac_periods where label = 'W0');
begin
  update public.period_scores set score = 0.850155
  where period_id = v_w0
    and devotee_id = (select ids.id from public.ac_ids ids where ids.key = 'ramesh');
  update public.period_scores set score = 0.847477
  where period_id = v_w0
    and devotee_id = (select ids.id from public.ac_ids ids where ids.key = 'gopala');
  update public.period_scores set score = 0.342752
  where period_id = v_w0
    and devotee_id = (select ids.id from public.ac_ids ids where ids.key = 'syama');
  update public.period_scores set score = 0.335203
  where period_id = v_w0
    and devotee_id = (select ids.id from public.ac_ids ids where ids.key = 'jahnava');

  if (select count(*) from public.period_scores
      where period_id = v_w0
        and score in (0.850155, 0.847477, 0.342752, 0.335203)) <> 4
  then
    raise exception 'The four planted scores did not land.';
  end if;
end;
$$;

do $$
declare
  v_w0 uuid := (select id from public.ac_periods where label = 'W0');
  v_a integer;
  v_b integer;
  v_rows integer;
begin
  perform set_config('request.jwt.claim.sub',
    (select ids.id::text from public.ac_ids ids where ids.key = 'arpita'), true);

  -- THE PODIUM. Two devotees publish 850 and their exact scores differ, so the
  -- old rule split them into gold and silver. They share the gold.
  select garland.standing into v_a from public.list_seva_garland('week', 20, 'combined') garland
  where garland.devotee_name = 'Bhakta Ramesh Patel';
  select garland.standing into v_b from public.list_seva_garland('week', 20, 'combined') garland
  where garland.devotee_name = 'Gopala Krishna Das';
  if v_a is null or v_b is null then
    raise exception 'The planted pair is not on the board (% and %).', v_a, v_b;
  end if;
  if v_a <> v_b then
    raise exception 'Two devotees publishing 850 stand at % and %.', v_a, v_b;
  end if;
  if v_a <> 1 then
    raise exception 'The shared place is % rather than the gold.', v_a;
  end if;

  -- THE SIXTH PLACE. Same again, lower down.
  select garland.standing into v_a from public.list_seva_garland('week', 20, 'combined') garland
  where garland.devotee_name = 'Syamasundara Das';
  select garland.standing into v_b from public.list_seva_garland('week', 20, 'combined') garland
  where garland.devotee_name = 'Jahnava Devi Dasi';
  if v_a is distinct from v_b then
    raise exception 'Two devotees publishing 340 stand at % and %.', v_a, v_b;
  end if;

  -- THE OLD RULE REALLY WOULD HAVE SPLIT THEM, so neither pair is a tie the
  -- scoring handed us.
  if (select count(distinct scores.score) from public.period_scores scores
      where scores.period_id = v_w0
        and scores.devotee_id in (
          select ids.id from public.ac_ids ids where ids.key in ('ramesh', 'gopala'))) <> 2
  then
    raise exception 'The podium pair have the same exact score; the tie is not a tie.';
  end if;

  -- AND OVER THE WHOLE BOARD, IN BOTH MODES: equal points, equal place; and the
  -- places are still dense, so nobody can read an absence out of a gap.
  foreach v_a in array array[1, 2] loop
    select count(*)::integer into v_rows
    from public.list_seva_garland('week', 200,
           case when v_a = 1 then 'combined' else 'seva' end) higher
    join public.list_seva_garland('week', 200,
           case when v_a = 1 then 'combined' else 'seva' end) lower
      on lower.points = higher.points
    where lower.standing is distinct from higher.standing;
    if v_rows > 0 then
      raise exception '% pairs publish the same points at different places.', v_rows;
    end if;

    select count(*)::integer into v_rows
    from public.list_seva_garland('week', 200,
           case when v_a = 1 then 'combined' else 'seva' end) higher
    join public.list_seva_garland('week', 200,
           case when v_a = 1 then 'combined' else 'seva' end) lower
      on lower.standing > higher.standing
    where lower.points > higher.points;
    if v_rows > 0 then
      raise exception '% pairs are ranked against their own points.', v_rows;
    end if;

    select (select count(distinct garland.standing)
            from public.list_seva_garland('week', 200,
                   case when v_a = 1 then 'combined' else 'seva' end) garland)
         - (select max(garland.standing)
            from public.list_seva_garland('week', 200,
                   case when v_a = 1 then 'combined' else 'seva' end) garland)
    into v_rows;
    if v_rows <> 0 then
      raise exception 'The board has gaps in its places; the ranking is not dense.';
    end if;
  end loop;

  perform set_config('request.jwt.claim.sub', '', true);
end;
$$;

-- THE DRILL-DOWN AND THE PRESIDENT'S BOARD AGREE WITH THE GARLAND, place for
-- place. A devotee who taps a name must not be shown a different place from the
-- one they tapped.
do $$
declare
  v_row record;
  v_summary integer;
  v_all integer;
begin
  perform set_config('request.jwt.claim.sub',
    (select ids.id::text from public.ac_ids ids where ids.key = 'arpita'), true);

  for v_row in select * from public.list_seva_garland('week', 200, 'combined') loop
    select summary.standing into v_summary
    from public.seva_yatra_devotee_summary(v_row.devotee_id, 'week') summary;
    if v_summary is distinct from v_row.standing then
      raise exception
        'The garland puts % at % and the drill-down at %.',
        v_row.devotee_name, v_row.standing, v_summary;
    end if;
  end loop;

  -- The President's whole-congregation board is a different POPULATION — it
  -- includes the devotees who opted out — so its places are its own. What must
  -- be true of it is what was wrong with it: equal published points, equal
  -- place.
  perform set_config('request.jwt.claim.sub',
    (select ids.id::text from public.ac_ids ids where ids.key = 'tanmay'), true);
  select count(*)::integer into v_all
  from public.list_all_seva_scores('week') higher
  join public.list_all_seva_scores('week') lower on lower.points = higher.points
  where lower.standing is distinct from higher.standing;
  if v_all > 0 then
    raise exception
      '% pairs on the President''s board publish the same points at different places.', v_all;
  end if;

  perform set_config('request.jwt.claim.sub', '', true);
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. CLAIM 4b: my own card no longer counts the devotees who are hiding.
-- ---------------------------------------------------------------------------

create table public.ac_mine (
  name text primary key,
  visible boolean not null,
  standing integer,
  board_standing integer
);

do $$
declare
  v_who record;
  v_row record;
begin
  for v_who in
    select ac_ids.key, users.id, users.name, users.leaderboard_visible
    from public.ac_ids join public.users on users.id = ac_ids.id
  loop
    perform set_config('request.jwt.claim.sub', v_who.id::text, true);
    select * into v_row from public.my_seva_mala('week');
    if v_row.period_id is not null then
      insert into public.ac_mine (name, visible, standing, board_standing)
      values (v_who.name, v_who.leaderboard_visible, v_row.standing, v_row.board_standing);
    end if;
  end loop;
  perform set_config('request.jwt.claim.sub', '', true);
end;
$$;

do $$
declare
  v_leaks integer;
  v_row record;
  v_hidden_above integer;
begin
  -- THE FIXTURE'S OWN PREMISE. There really are devotees on this board who are
  -- outranked by somebody they cannot see; without that, the assertion below is
  -- an arithmetic identity rather than a fix.
  select count(*)::integer into v_hidden_above
  from public.period_scores hidden
  join public.users on users.id = hidden.devotee_id
  where hidden.period_id = (select id from public.ac_periods where label = 'W0')
    and hidden.score > 0
    and not users.leaderboard_visible;
  if v_hidden_above < 2 then
    raise exception
      'Only % devotees opted out and still scored; there is nothing for the pair of columns to leak.',
      v_hidden_above;
  end if;

  -- THE LEAK, CLOSED. For every devotee on the board the two places are the
  -- same number, so their difference is identically zero and there is nothing
  -- left to subtract.
  select count(*)::integer into v_leaks
  from public.ac_mine
  where visible and standing is distinct from board_standing;
  if v_leaks > 0 then
    raise exception
      '% devotees can subtract their own two places and count the devotees above them who opted out.',
      v_leaks;
  end if;

  -- AND THE DEVOTEE'S OWN HONEST RANK SURVIVES. A devotee who opted out is not
  -- on the board and has no board place — and is still told where they stand.
  for v_row in select * from public.ac_mine where not visible loop
    if v_row.board_standing is not null then
      raise exception
        '% opted out of the board and was given a place on it.', v_row.name;
    end if;
    if v_row.standing is null then
      raise exception
        '% opted out and was told nothing about their own standing. The rank is theirs to know.',
        v_row.name;
    end if;
  end loop;

  -- The President opted out and is the second heaviest server in the temple.
  -- His own card still says so.
  if (select standing from public.ac_mine where name = 'Tanmay Pramanick') is null then
    raise exception 'The President cannot read his own place.';
  end if;

  -- And a devotee's own place is the place the board would give them, which is
  -- what makes it honest rather than merely private: everybody on the board
  -- reads the same number on both screens.
  if exists (
    select 1 from public.ac_mine
    where visible and standing is null and board_standing is not null
  ) then
    raise exception 'A devotee on the board has a board place and no place of their own.';
  end if;
end;
$$;

-- Nothing about a dismissal, a place or a badge reached a devotee. 0058 rule 2.
do $$
begin
  if pg_get_functiondef(to_regprocedure('public.my_seva_mala(text)'))
     ~* '(queue_app_notification|app_notifications)'
  then
    raise exception 'Reading your own standing notifies somebody.';
  end if;
  if pg_get_functiondef(to_regprocedure('public.list_seva_concentration(integer, numeric)'))
     ~* '(insert\s+into|delete\s+from|queue_app_notification)'
  then
    raise exception 'The concentration list has learned to write or to notify.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 9. Every guard, mutated.
--
--    Each row below breaks exactly one thing 0067 relies on and re-reads one
--    number through the real function. A guard whose mutation changes nothing
--    is a guard that was not doing anything, and the table says so out loud.
--
--    The mutation is undone by raising inside a plpgsql block, which is a
--    subtransaction; the probe is read a third time afterwards and must match
--    the first, or the harness itself is lying.
-- ---------------------------------------------------------------------------

create table public.ac_mutations (
  n integer primary key,
  guard text not null,
  mutation text not null,
  probe text not null,
  intact text not null,
  mutated text not null,
  killed boolean not null
);

create function public.ac_mutate(
  p_n integer, p_as text, p_guard text, p_mutation text, p_probe text,
  p_apply text, p_query text
)
returns void
language plpgsql
as $$
declare
  v_intact text;
  v_mutated text;
  v_restored text;
begin
  perform set_config('request.jwt.claim.sub',
    (select ids.id::text from public.ac_ids ids where ids.key = p_as), true);

  execute p_query into v_intact;

  begin
    execute p_apply;
    execute p_query into v_mutated;
    raise exception using errcode = 'PT667', message = coalesce(v_mutated, '(null)');
  exception when sqlstate 'PT667' then
    v_mutated := sqlerrm;
  end;

  execute p_query into v_restored;
  if v_restored is distinct from v_intact then
    raise exception
      'Mutation % did not roll back: the probe read % before and % after.',
      p_n, coalesce(v_intact, '(null)'), coalesce(v_restored, '(null)');
  end if;

  insert into public.ac_mutations (n, guard, mutation, probe, intact, mutated, killed)
  values (p_n, p_guard, p_mutation, p_probe,
          coalesce(v_intact, '(null)'), v_mutated,
          v_mutated is distinct from coalesce(v_intact, '(null)'));
end;
$$;

do $$
declare
  v_madhava uuid := (select ids.id from public.ac_ids ids where ids.key = 'madhava');
  v_w0 uuid := (select id from public.ac_periods where label = 'W0');
  v_b uuid := (select id from public.ac_periods where label = 'B');
  v_madhava_dhairya text := format(
    $q$select coalesce(max(badges.period_start)::text, '(none)')
       from public.list_devotee_badges(%L::uuid) badges
       where badges.award_code = 'weekly_dhairya'$q$, v_madhava);
  v_care text := 'select count(*)::text from public.list_seva_concentration()';
begin
  -- ---- Section 1: the read-time re-ask, and its frozen short circuit. -----
  perform public.ac_mutate(
    1, 'madhava', 'current_devotee_awards: seva_mala_award_holds_now',
    'the re-ask forced to true, which is 0066''s behaviour',
    'the week Madhava''s Dhairya is worn for',
    $m$create or replace function public.seva_mala_award_holds_now(
         p_award_definition_id uuid, p_period_id uuid, p_devotee_id uuid)
       returns boolean language sql stable set search_path = '' as $f$ select true $f$ $m$,
    v_madhava_dhairya);

  perform public.ac_mutate(
    2, 'madhava', 'seva_mala_award_holds_now: seva_mala_periods.frozen_at',
    'the CLOSED week re-opened',
    'the week Madhava''s Dhairya is worn for',
    format($m$update public.seva_mala_periods set frozen_at = null where id = %L::uuid$m$, v_b),
    v_madhava_dhairya);

  perform public.ac_mutate(
    3, 'madhava', 'seva_mala_award_holds_now: award_definitions.threshold_quantile',
    'Dhairya''s quantile dropped to the bottom, so the bar falls to the shortest run',
    'the week Madhava''s Dhairya is worn for',
    $m$update public.award_definitions set threshold_quantile = 0.01
       where code = 'weekly_dhairya'$m$,
    v_madhava_dhairya);

  perform public.ac_mutate(
    4, 'ramesh', 'seva_mala_award_holds_now: award_definitions.threshold_floor',
    'Dhairya''s floor raised above every run in the temple',
    'the week Ramesh''s Dhairya is worn for',
    $m$update public.award_definitions set threshold_floor = 999
       where code = 'weekly_dhairya'$m$,
    format($q$select coalesce(max(badges.period_start)::text, '(none)')
              from public.list_devotee_badges(%L::uuid) badges
              where badges.award_code = 'weekly_dhairya'$q$,
           (select ids.id from public.ac_ids ids where ids.key = 'ramesh')));

  perform public.ac_mutate(
    5, 'madhava', 'seva_mala_award_holds_now: period_scores for the open period',
    'Madhava''s score this week raised above everybody''s',
    'the week Madhava''s weekly recognition is worn for',
    format($m$update public.period_scores set score = 0.99
             where period_id = %L::uuid and devotee_id = %L::uuid$m$, v_w0, v_madhava),
    format($q$select coalesce(max(badges.period_start)::text, '(none)')
              from public.list_devotee_badges(%L::uuid) badges
              where badges.award_code = 'weekly_recognition'$q$, v_madhava));

  -- ---- Sections 2 and 3: the Seva Care gates. ----------------------------
  perform public.ac_mutate(
    6, 'tanmay', 'list_seva_concentration: seva_balance.frequency_fallback_quantile',
    'the stand-in taken from the TOP of the seva normals instead of the middle',
    'rows on the Seva Care list',
    $m$update public.app_settings set value = '1.0'
       where key = 'seva_balance.frequency_fallback_quantile'$m$,
    v_care);

  perform public.ac_mutate(
    7, 'tanmay', 'list_seva_concentration: seva_balance.frequency_normal_quantile',
    'a seva''s own normal taken from its busiest server instead of its middle one',
    'Syamasundara on the list',
    $m$update public.app_settings set value = '0.99'
       where key = 'seva_balance.frequency_normal_quantile'$m$,
    $q$select count(*)::text from public.list_seva_concentration() listed
       where listed.devotee_name = 'Syamasundara Das'$q$);

  perform public.ac_mutate(
    8, 'tanmay', 'list_seva_concentration: seva_balance.frequency_multiple',
    'the multiple raised to four',
    'rows on the Seva Care list',
    $m$update public.app_settings set value = '4.0'
       where key = 'seva_balance.frequency_multiple'$m$,
    v_care);

  perform public.ac_mutate(
    9, 'tanmay', 'list_seva_concentration: seva_balance.frequency_min_peers',
    'one other server declared enough to be a normal, so Mangal Arati gets one',
    'Gopala on the list',
    $m$update public.app_settings set value = '1'
       where key = 'seva_balance.frequency_min_peers'$m$,
    $q$select count(*)::text from public.list_seva_concentration() listed
       where listed.devotee_name = 'Gopala Krishna Das'$q$);

  perform public.ac_mutate(
    10, 'tanmay', 'list_seva_concentration: consecutive_weeks_threshold',
    'the run the temple expects pushed up to the longest in the congregation',
    'rows on the Seva Care list',
    $m$update public.app_settings set value = '0.99'
       where key = 'seva_balance.weeks_quantile'$m$,
    v_care);

  perform public.ac_mutate(
    11, 'arpita', 'list_seva_concentration: has_permission(''app.view_all'')',
    'public.has_permission forced true',
    'rows a plain devotee sees',
    $m$create or replace function public.has_permission(requested_permission text)
       returns boolean language sql stable set search_path = '' as $f$ select true $f$ $m$,
    v_care);

  perform public.ac_mutate(
    12, 'tanmay', 'list_seva_concentration: seva_care_dismissals',
    'Madhava cleared through the RPC',
    'Madhava on the Seva Care list',
    format($m$select public.dismiss_seva_care(%L::uuid, null, null)$m$, v_madhava),
    $q$select count(*)::text from public.list_seva_concentration() listed
       where listed.devotee_name = 'Madhava Priya Das'$q$);

  -- ---- Section 4: the ranking and the leak. ------------------------------
  perform public.ac_mutate(
    13, 'arpita', 'list_seva_garland: dense_rank over seva_mala_points',
    'points published at the full resolution of the score',
    'devotees sharing the gold',
    $m$create or replace function public.seva_mala_points(p_norm numeric)
       returns integer language sql stable set search_path = '' as $f$
         select case when p_norm is null or p_norm <= 0 then 0
                     else greatest(10, round(p_norm * 1000000))::integer end $f$ $m$,
    $q$select count(*)::text from public.list_seva_garland('week', 200, 'combined') garland
       where garland.standing = 1$q$);

  perform public.ac_mutate(
    14, 'syama', 'my_seva_mala: users.leaderboard_visible in the visible population',
    'everybody opted back in, so the population the caller may see is everybody',
    'Syamasundara''s own place',
    $m$update public.users set leaderboard_visible = true
       where users.email like 'ac-%@example.test'$m$,
    $q$select coalesce(max(mine.standing)::text, '(none)')
       from public.my_seva_mala('week') mine$q$);

  perform public.ac_mutate(
    15, 'arpita', 'seva_yatra_devotee_summary: dense_rank over seva_mala_points',
    'points published at the full resolution of the score',
    'the place the drill-down gives Ramesh',
    $m$create or replace function public.seva_mala_points(p_norm numeric)
       returns integer language sql stable set search_path = '' as $f$
         select case when p_norm is null or p_norm <= 0 then 0
                     else greatest(10, round(p_norm * 1000000))::integer end $f$ $m$,
    format($q$select coalesce(max(summary.standing)::text, '(none)')
              from public.seva_yatra_devotee_summary(%L::uuid, 'week') summary$q$,
           (select ids.id from public.ac_ids ids where ids.key = 'gopala')));
end;
$$;

select set_config('request.jwt.claim.sub', '', true);

do $$
declare
  v_survivors text;
begin
  select string_agg(ac_mutations.n || ': ' || ac_mutations.guard, E'\n  ')
  into v_survivors
  from public.ac_mutations where not ac_mutations.killed;
  if v_survivors is not null then
    raise exception
      'These guards survived being broken, so nothing is holding them up:%s%',
      E'\n  ', v_survivors;
  end if;
  if (select count(*) from public.ac_mutations) <> 15 then
    raise exception 'Only % mutations ran.', (select count(*) from public.ac_mutations);
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 10. The tables a reader wants.
-- ---------------------------------------------------------------------------

select
  ac_mutations.n,
  ac_mutations.guard,
  ac_mutations.mutation,
  ac_mutations.probe,
  ac_mutations.intact,
  ac_mutations.mutated,
  case when ac_mutations.killed then 'killed' else 'SURVIVED' end as verdict
from public.ac_mutations
order by ac_mutations.n;

select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.ac_ids ids where ids.key = 'tanmay'), true);

select
  listed.devotee_name,
  listed.seva_name,
  listed.hours_per_week,
  listed.consecutive_weeks,
  listed.hours_vs_peers as times_the_normal_for_this_seva,
  listed.min_hours_used as congregation_wide_bar,
  case when listed.hours_per_week >= listed.min_hours_used
       then 'was already listed' else 'reached by 0067' end as how
from public.list_seva_concentration() listed;

select set_config('request.jwt.claim.sub', '', true);

do $$
begin
  raise notice 'all award currency and care reach checks passed';
end;
$$;

select 'award currency and care reach verification passed' as result;

rollback;
