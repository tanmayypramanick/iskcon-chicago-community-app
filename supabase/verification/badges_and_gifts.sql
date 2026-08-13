-- Functional verification for 202608040063_badges_and_gifts.sql.
--
-- Rolled back at the end. Every local is prefixed v_ so it can never shadow a
-- column name. Anything a devotee could really attempt is attempted as that
-- devotee, under `set local role authenticated`, so the grants, the row level
-- security and the permission checks are what is being tested rather than
-- superuser rights waving everything through.
--
-- 0063 makes five claims and this file exists to break all five if they are
-- not true.
--
--   1. The eleven gifts the temple named exist as definitions, weekly, and the
--      seven garlands are LATERAL — identical in every column that could be
--      read as a grade, and taking turns rather than stacking. Over seven
--      consecutive weeks each of the seven is offered exactly once.
--
--   2. Closing a period awards first place, the top three and the top ten, and
--      it awards exactly the devotees a dense_rank over public.period_scores
--      picks out. The expected winners are DERIVED FROM THE SCORES AT RUNTIME
--      rather than written down here, so this file proves the awarding rule
--      without depending on the scoring arithmetic — which is 202608040059's,
--      is being changed again by 202608040062, and is not what is under test.
--
--   3. Re-running the close awards nothing, even when the rotation cycle has
--      been changed underneath it between the two runs.
--
--   4. A badge earned for last week is publicly displayed this week, stops
--      being displayed the moment the next week's badges land, and NEVER
--      leaves the devotee's shelf.
--
--   5. The public badge function leaks no number, the opt-out is honoured on
--      it, and the President sees everything.
--
-- ---------------------------------------------------------------------------
-- The fixture, and why it is shaped this way.
--
-- Twelve devotees in the scoring cohort, past 0055's minimum of eight, plus a
-- President with app.view_all and no activity of his own.
--
-- Three windows, laid out so that they cannot overlap on any day of any year:
--
--   week A   the week beginning fourteen days before this Monday
--   week B   the week beginning seven days before this Monday
--   month M  last Chicago month, with its facts on the FIRST SIX DAYS of it
--
-- Week A begins at least fourteen days after the first of last month, so days
-- one to six of last month are never inside week A or week B. Weeks A and B are
-- therefore made of the weekly fixture alone, whatever today's date is.
--
-- Every act is ninety minutes and every gift is a single gift, so no act comes
-- near the 480-minute day or the 1,800-minute week and credited minutes are
-- served minutes.
--
-- In each window ONE devotee holds both the most seva and the largest gift, and
-- strictly beats every other devotee in both. Whatever the scoring rule does
-- with the two norms — 0055's, 0059's or 0062's — that devotee is uniquely
-- first, because the top three by seva and the top three by giving intersect in
-- exactly one devotee and no one else can reach the cap in both:
--
--   week A   Aravinda   12 acts and $1,200; Devaki gives $1,000 on 3 acts
--   week B   Lochana    the same shape, with the cast reversed
--   month M  Ekanatha   a third devotee again, so no window's winner is another
--                       window's winner and an expired badge cannot be confused
--                       with a re-earned one
--
-- Chandrika is the devotee who OPTED OUT. She is high in week A's ranking and
-- earns real badges for it; none of them appear to anybody but her and the
-- President, and every one of them stays on her shelf.
--
-- The cast, by week A's numbers:
--   Aravinda Das    12 acts, $1,200   uniquely first in week A
--   Bhavani Devi    11 acts, $30
--   Chandrika Devi  10 acts, $40      OPTED OUT of the board
--   Devaki Devi      3 acts, $1,000
--   Ekanatha Das     2 acts, $900     uniquely first in month M
--   Gauranga Das     9 acts, $200
--   Haripriya Devi   8 acts, $150
--   Ishana Das       7 acts, $120
--   Jahnava Devi     6 acts, $100
--   Kanai Das        5 acts, $80
--   Lochana Das      4 acts, $60      uniquely first in week B
--   Mukunda Das      1 act,  $50
--   Nrsimha Das      nothing          app.view_all
--
-- The final row must read: badges and gifts verification passed

begin;

-- ---------------------------------------------------------------------------
-- 0. The ground.
--
--    The things 0063 is a claim about that live in other files, and the dials
--    the fixture's cohort assertions are a function of.
-- ---------------------------------------------------------------------------

do $$
declare
  v_definition text;
  v_holders text;
begin
  if to_regprocedure('public.list_devotee_badges(uuid)') is null
    or to_regprocedure('public.list_devotee_award_shelf(uuid)') is null
    or to_regprocedure('public.current_award_periods()') is null
    or to_regprocedure('public.award_rotation_turn(text, text, date)') is null
    or to_regprocedure('public.seva_mala_period_index(text, date)') is null
  then
    raise exception 'public.202608040063 is not applied.';
  end if;

  -- Expiry in 0063 is a join that stops matching. That is only safe while the
  -- row underneath it cannot be deleted.
  if not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.devotee_awards'::regclass
      and tgname = 'devotee_awards_append_only'
      and not tgisinternal
  ) then
    raise exception 'The append-only trigger on devotee_awards is gone.';
  end if;

  if not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.devotee_awards'::regclass
      and tgname = 'devotee_award_announced'
      and not tgisinternal
  ) then
    raise exception 'Nothing tells a devotee they earned anything.';
  end if;

  select pg_get_constraintdef(pg_constraint.oid) into v_definition
  from pg_constraint
  where conname = 'app_notifications_kind_check'
    and conrelid = 'public.app_notifications'::regclass;
  if v_definition is null or position('''seva_award_earned''' in v_definition) = 0 then
    raise exception 'app_notifications does not permit seva_award_earned.';
  end if;

  select string_agg(roles.name, ',' order by roles.name) into v_holders
  from public.role_permissions
  join public.roles on roles.id = role_permissions.role_id
  where role_permissions.permission_key = 'app.view_all';
  if v_holders is distinct from 'president,tech' then
    raise exception 'app.view_all is held by %.', v_holders;
  end if;

  -- The badge functions publish a tier and a period. That is only a meaningful
  -- promise while the numbers themselves stay shut.
  if has_table_privilege('authenticated', 'public.period_scores', 'select')
    or has_table_privilege('authenticated', 'public.seva_mala_periods', 'select')
    or has_table_privilege('authenticated', 'public.app_settings', 'select')
  then
    raise exception 'authenticated can already read the Seva Mala components.';
  end if;

  if public.seva_mala_number('seva_mala.minimum_cohort', 8) <> 8 then
    raise exception 'The minimum cohort is not eight; the fixture is sized for eight.';
  end if;
  if public.seva_mala_number('seva_mala.daily_cap_minutes', 480) <> 480
    or public.seva_mala_number('seva_mala.weekly_cap_minutes', 1800) <> 1800
  then
    raise exception 'The caps have moved; the fixture is laid out under them.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 1. The gifts the temple named, in the temple's own words.
--
--    Asserted by TITLE and not by code, because the title is what the temple
--    said and the code is ours. All eleven must be live for the week.
-- ---------------------------------------------------------------------------

do $$
declare
  v_missing text;
begin
  select string_agg(wanted.title, ', ' order by wanted.title) into v_missing
  from (values
    ('Maha Prasad'),
    ('Kisora''s garland'),
    ('Kisori''s garland'),
    ('Jagannath''s garland'),
    ('Baldev''s garland'),
    ('Subhadra''s garland'),
    ('Gaura''s garland'),
    ('Nitai''s garland'),
    ('Token of Appreciation'),
    ('Recognition'),
    ('Mystery Gift')
  ) as wanted(title)
  where not exists (
    select 1 from public.award_definitions definitions
    where definitions.title = wanted.title
      and definitions.period_kind = 'week'
      and definitions.is_active
  );

  if v_missing is not null then
    raise exception
      'The temple asked for these weekly and they are not there: %.', v_missing;
  end if;
end;
$$;

-- The three rungs exist for BOTH period kinds — first place, top three, top
-- ten — because the temple asked for a badge every week AND every month.
do $$
declare
  v_kind text;
  v_rungs text;
begin
  foreach v_kind in array array['week', 'month'] loop
    select string_agg(distinct definitions.top_n::text, ',' order by definitions.top_n::text)
    into v_rungs
    from public.award_definitions definitions
    where definitions.is_active
      and definitions.period_kind = v_kind
      and definitions.rule_kind = 'top_n';

    if v_rungs is distinct from '1,10,3' then
      raise exception
        'The % rungs are (%) rather than first place, top three and top ten.',
        v_kind, coalesce(v_rungs, 'none');
    end if;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. The seven garlands are lateral, and they take turns.
--
--    Laterality is not asserted here the way 0055 asserts it of its own three.
--    0055's three are lateral because each ranks on a DIFFERENT thing; seven
--    cannot be, because only three rank_basis values exist. The temple's seven
--    are lateral because they are THE SAME in every respect that could be read
--    as a grade, and which one is offered depends only on the week.
-- ---------------------------------------------------------------------------

do $$
declare
  v_group text;
  v_kind text;
  v_count integer;
begin
  for v_group, v_kind in
    select * from (values
      ('weekly_deity_garland', 'week'),
      ('monthly_deity_garland', 'month')
    ) as cycles(rotation_group, period_kind)
  loop
    select count(*) into v_count from public.award_definitions
    where rotation_group = v_group;
    if v_count <> 7 then
      raise exception 'The % cycle has % garlands rather than seven.', v_group, v_count;
    end if;

    -- Seven Deities, seven seats, and no seat held twice.
    select count(distinct garland_kind) into v_count from public.award_definitions
    where rotation_group = v_group;
    if v_count <> 7 then
      raise exception 'The % cycle does not name seven distinct Deities.', v_group;
    end if;
    select count(distinct rotation_seat) into v_count from public.award_definitions
    where rotation_group = v_group;
    if v_count <> 7 then
      raise exception 'Two garlands in % hold the same seat.', v_group;
    end if;

    -- IDENTICAL IN EVERYTHING THAT COULD BE A GRADE. One tier, one rule, one
    -- top_n, one rank_basis, one sort_order, one period kind, and one
    -- description character for character. A garland given a bigger top_n, a
    -- richer tier, an earlier sort_order or a description saying it is the
    -- special one fails here.
    select count(*) into v_count
    from (
      select distinct tier, rule_kind, period_kind, top_n, rank_basis,
             threshold_quantile, rule_key, sort_order, description, is_active
      from public.award_definitions
      where rotation_group = v_group
    ) shapes;
    if v_count <> 1 then
      raise exception
        'The seven garlands in % differ in % distinct ways beyond the Deity and the seat. Something in them is a ranking.',
        v_group, v_count;
    end if;

    -- The Deity is named in the title and nowhere else in the row.
    if exists (
      select 1 from public.award_definitions definitions
      where definitions.rotation_group = v_group
        and definitions.description ilike '%' || definitions.garland_kind || '%'
    ) then
      raise exception 'A garland in % describes its own Deity, so the seven descriptions are not one text.', v_group;
    end if;

    if exists (
      select 1 from public.award_definitions definitions
      where definitions.rotation_group = v_group
        and (definitions.tier <> 'garland' or definitions.period_kind <> v_kind)
    ) then
      raise exception 'A member of % is not a % garland.', v_group, v_kind;
    end if;
  end loop;
end;
$$;

-- Over seven consecutive periods each garland is offered exactly once, and over
-- fourteen exactly twice. That is the whole content of "rotate rather than
-- stack": no garland is rarer than another, so no garland is worth more.
do $$
declare
  v_anchor date := public.seva_mala_week_start(public.seva_mala_today());
  v_month date := date_trunc('month', public.seva_mala_today())::date;
  v_count integer;
  v_min integer;
  v_max integer;
begin
  select count(distinct turn), min(hits), max(hits) into v_count, v_min, v_max
  from (
    select public.award_rotation_turn('weekly_deity_garland', 'week', v_anchor + 7 * step) as turn,
           count(*) as hits
    from generate_series(0, 13) step
    group by 1
  ) cycle;
  if v_count <> 7 or v_min <> 2 or v_max <> 2 then
    raise exception
      'Over fourteen weeks % distinct garlands were offered, between % and % times each.',
      v_count, v_min, v_max;
  end if;

  select count(distinct turn), min(hits), max(hits) into v_count, v_min, v_max
  from (
    select public.award_rotation_turn(
             'monthly_deity_garland', 'month',
             (v_month + (step || ' months')::interval)::date) as turn,
           count(*) as hits
    from generate_series(0, 13) step
    group by 1
  ) cycle;
  if v_count <> 7 or v_min <> 2 or v_max <> 2 then
    raise exception
      'Over fourteen months % distinct garlands were offered, between % and % times each.',
      v_count, v_min, v_max;
  end if;

  -- The same week always gets the same garland, whoever asks and whenever.
  if public.award_rotation_turn('weekly_deity_garland', 'week', v_anchor)
     is distinct from
     public.award_rotation_turn('weekly_deity_garland', 'week', v_anchor)
  then
    raise exception 'The rotation is not stable.';
  end if;

  -- Any day inside a week resolves to that week's garland, so a job that runs
  -- on Tuesday and a job that runs on Sunday agree.
  if exists (
    select 1 from generate_series(0, 6) day
    where public.award_rotation_turn('weekly_deity_garland', 'week', v_anchor + day)
      is distinct from
          public.award_rotation_turn('weekly_deity_garland', 'week', v_anchor)
  ) then
    raise exception 'The garland offered depends on which day of the week asked.';
  end if;

  -- Consecutive weeks differ, so a devotee on top two weeks running is not
  -- handed the same garland twice.
  if public.award_rotation_turn('weekly_deity_garland', 'week', v_anchor)
     = public.award_rotation_turn('weekly_deity_garland', 'week', v_anchor + 7)
  then
    raise exception 'Two consecutive weeks offer the same garland.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. The two new doors: their shapes, their grants, and what may not go
--    through them.
-- ---------------------------------------------------------------------------

do $$
declare
  v_count integer;
  v_columns text;
begin
  select count(*) into v_count
  from pg_proc proc
  join pg_namespace spaces on spaces.oid = proc.pronamespace
  where spaces.nspname = 'public' and proc.proname = 'list_devotee_badges';
  if v_count <> 1 then
    raise exception 'There are % functions named list_devotee_badges.', v_count;
  end if;

  select string_agg(parameters.parameter_name, ', ' order by parameters.ordinal_position)
  into v_columns
  from information_schema.parameters parameters
  where parameters.specific_schema = 'public'
    and parameters.specific_name like 'list_devotee_badges%'
    and parameters.parameter_mode = 'OUT';
  if v_columns <> 'award_id, award_code, title, description, tier, garland_kind, '
                  || 'period_kind, period_start, period_end, awarded_on' then
    raise exception 'The public badge list returns (%).', v_columns;
  end if;

  select string_agg(parameters.parameter_name, ', ' order by parameters.ordinal_position)
  into v_columns
  from information_schema.parameters parameters
  where parameters.specific_schema = 'public'
    and parameters.specific_name like 'list_devotee_award_shelf%'
    and parameters.parameter_mode = 'OUT';
  if v_columns <> 'award_id, award_code, title, description, tier, garland_kind, '
                  || 'rule_kind, period_kind, period_start, period_end, awarded_on, '
                  || 'awarded_by, citation, fulfilled_on, fulfilment_note, is_current' then
    raise exception 'The shelf returns (%).', v_columns;
  end if;
end;
$$;

-- NOTHING NUMERIC ON THE PUBLIC BADGE LIST. Not a score, not points, not a
-- place, not an hour, not a cent — and not a column called `top_n` or
-- `standing` either, which would publish the rung as a number. Asserted by
-- pattern as well as by the exact list above, so a column somebody adds later
-- under a new name is refused too.
do $$
declare
  v_leaked text;
begin
  select string_agg(parameters.parameter_name, ', ') into v_leaked
  from information_schema.parameters parameters
  where parameters.specific_schema = 'public'
    and parameters.specific_name like 'list_devotee_badges%'
    and parameters.parameter_mode = 'OUT'
    and (
      parameters.parameter_name ilike '%score%'
      or parameters.parameter_name ilike '%point%'
      or parameters.parameter_name ilike '%norm%'
      or parameters.parameter_name ilike '%minute%'
      or parameters.parameter_name ilike '%hour%'
      or parameters.parameter_name ilike '%cent%'
      or parameters.parameter_name ilike '%dollar%'
      or parameters.parameter_name ilike '%amount%'
      or parameters.parameter_name ilike '%total%'
      or parameters.parameter_name ilike '%rank%'
      or parameters.parameter_name ilike '%standing%'
      or parameters.parameter_name ilike '%place%'
      or parameters.parameter_name ilike '%top%'
      or parameters.parameter_name ilike '%utility%'
      or parameters.parameter_name ilike '%reference%'
      or parameters.parameter_name ilike '%giv%'
    );
  if v_leaked is not null then
    raise exception
      'The public badge list returns %. A badge is a name and a period, not a number.',
      v_leaked;
  end if;
end;
$$;

do $$
begin
  if has_function_privilege('anon', 'public.list_devotee_badges(uuid)', 'execute')
    or has_function_privilege('anon', 'public.list_devotee_award_shelf(uuid)', 'execute')
  then
    raise exception 'A signed-out visitor can read badges.';
  end if;

  -- "Show them on their profile which can be seen by anyone" — anyone signed in.
  if not has_function_privilege('authenticated', 'public.list_devotee_badges(uuid)', 'execute') then
    raise exception 'An ordinary devotee cannot read another devotee''s badges.';
  end if;
  if not has_function_privilege('authenticated', 'public.list_devotee_award_shelf(uuid)', 'execute') then
    raise exception 'The shelf is not reachable by the President through PostgREST.';
  end if;

  -- The machinery stays shut.
  if has_function_privilege('authenticated', 'public.award_seva_mala_for_period(uuid)', 'execute')
    or has_function_privilege('authenticated', 'public.current_award_periods()', 'execute')
    or has_function_privilege('authenticated', 'public.award_rotation_turn(text, text, date)', 'execute')
    or has_function_privilege('authenticated', 'public.seva_mala_period_index(text, date)', 'execute')
  then
    raise exception 'A devotee can drive the awarding machinery.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. The congregation.
-- ---------------------------------------------------------------------------

create table public.bg_ids (key text primary key, id uuid not null);
grant select on public.bg_ids to authenticated;

do $$
declare
  v_who record;
  v_i integer := 0;
begin
  for v_who in
    select * from (values
      ('aravinda',  'Aravinda Das'),
      ('bhavani',   'Bhavani Devi'),
      ('chandrika', 'Chandrika Devi'),
      ('devaki',    'Devaki Devi'),
      ('ekanatha',  'Ekanatha Das'),
      ('gauranga',  'Gauranga Das'),
      ('haripriya', 'Haripriya Devi'),
      ('ishana',    'Ishana Das'),
      ('jahnava',   'Jahnava Devi'),
      ('kanai',     'Kanai Das'),
      ('lochana',   'Lochana Das'),
      ('mukunda',   'Mukunda Das'),
      ('nrsimha',   'Nrsimha Das')
    ) as cast_member(key, name)
  loop
    v_i := v_i + 1;
    insert into auth.users (id, email, raw_user_meta_data)
    values (
      ('63000000-0000-0000-0000-0000000000' || lpad(v_i::text, 2, '0'))::uuid,
      'bg-' || v_who.key || '@example.test',
      jsonb_build_object('name', v_who.name)
    );

    update public.users
    set name = v_who.name
    where users.email = 'bg-' || v_who.key || '@example.test';

    insert into public.bg_ids (key, id)
    select v_who.key, users.id
    from public.users where users.email = 'bg-' || v_who.key || '@example.test';
  end loop;
end;
$$;

update public.users
set role_id = (select roles.id from public.roles where roles.name = 'president')
where users.email = 'bg-nrsimha@example.test';

-- Everybody is on the board but Chandrika, who is the whole of the opt-out
-- test: she earns badges and none of them are published.
update public.users
set leaderboard_visible = (users.email <> 'bg-chandrika@example.test')
where users.email like 'bg-%@example.test';

-- ---------------------------------------------------------------------------
-- 5. The facts.
--
--    Three windows, one shape. Ninety-minute acts, two a day, starting on the
--    first day of the window; one gift each, on the window's third day.
-- ---------------------------------------------------------------------------

do $$
declare
  v_type uuid;
  v_anchor date := public.seva_mala_week_start(public.seva_mala_today());
  v_month date := (date_trunc('month', public.seva_mala_today()) - interval '1 month')::date;
  v_window record;
  v_plan record;
  v_from date;
  v_instance uuid;
  v_day date;
  v_n integer;
begin
  select service_types.id into v_type
  from public.service_types where service_types.name = 'Pot Washing';
  if v_type is null then
    raise exception 'The Pot Washing service type is missing from the seed.';
  end if;

  -- The three windows can never overlap: week A begins at least fourteen days
  -- after the first of last month, and the monthly facts stop on its sixth day.
  if v_anchor - 14 <= v_month + 6 then
    raise exception
      'Week A begins on % and the monthly facts run to % — the fixture overlaps itself.',
      v_anchor - 14, v_month + 6;
  end if;

  for v_window in
    select * from (values
      ('A', 0),
      ('B', 0),
      ('M', 0)
    ) as windows(label, unused)
  loop
    v_from := case v_window.label
      when 'A' then v_anchor - 14
      when 'B' then v_anchor - 7
      else v_month
    end;

    for v_plan in
      select * from (values
        -- week A: Aravinda holds both the most seva and the largest gift.
        ('A', 'aravinda',  12, 120000), ('A', 'bhavani',   11,   3000),
        ('A', 'chandrika', 10,   4000), ('A', 'devaki',     3, 100000),
        ('A', 'ekanatha',   2,  90000), ('A', 'gauranga',   9,  20000),
        ('A', 'haripriya',  8,  15000), ('A', 'ishana',     7,  12000),
        ('A', 'jahnava',    6,  10000), ('A', 'kanai',      5,   8000),
        ('A', 'lochana',    4,   6000), ('A', 'mukunda',    1,   5000),
        -- week B: the same shape with Lochana at the top instead.
        ('B', 'lochana',   12, 120000), ('B', 'kanai',     11,   3000),
        ('B', 'jahnava',   10,   4000), ('B', 'ishana',     3, 100000),
        ('B', 'haripriya',  2,  90000), ('B', 'gauranga',   9,  20000),
        ('B', 'ekanatha',   8,  15000), ('B', 'devaki',     7,  12000),
        ('B', 'chandrika',  6,  10000), ('B', 'bhavani',    5,   8000),
        ('B', 'mukunda',    4,   6000), ('B', 'aravinda',   1,   5000),
        -- month M: a third devotee again.
        ('M', 'ekanatha',  12, 120000), ('M', 'devaki',    11,   3000),
        ('M', 'gauranga',  10,   4000), ('M', 'aravinda',   3, 100000),
        ('M', 'bhavani',    2,  90000), ('M', 'chandrika',  9,  20000),
        ('M', 'haripriya',  8,  15000), ('M', 'ishana',     7,  12000),
        ('M', 'jahnava',    6,  10000), ('M', 'kanai',      5,   8000),
        ('M', 'lochana',    4,   6000), ('M', 'mukunda',    1,   5000)
      ) as plan(label, who, acts, cents)
      where plan.label = v_window.label
    loop
      for v_n in 1 .. v_plan.acts loop
        v_day := v_from + ((v_n - 1) / 2);

        insert into public.service_instances (
          service_type_id, date, start_time, duration_minutes, slots_needed,
          participation_mode, posted_by, status
        ) values (
          v_type, v_day,
          case when v_n % 2 = 1 then time '08:00' else time '13:00' end,
          90, 1, 'open', null, 'completed'
        ) returning id into v_instance;

        insert into public.service_assignments (
          service_instance_id, devotee_id, assignment_method, status,
          verification, attendance, completed_at
        ) values (
          v_instance,
          (select ids.id from public.bg_ids ids where ids.key = v_plan.who),
          'self_joined', 'completed', 'member_verified', 'served',
          (v_day + time '12:00') at time zone 'America/Chicago'
        );
      end loop;

      insert into public.donations (
        donor_id, donor_name, amount_cents, kind, external_payment_id, received_at
      ) values (
        (select ids.id from public.bg_ids ids where ids.key = v_plan.who),
        v_plan.who, v_plan.cents, 'one_time',
        'bg-' || v_window.label || '-' || v_plan.who,
        ((v_from + 2) + time '10:00') at time zone 'America/Chicago'
      );
    end loop;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Closing week A.
--
--    ensure_seva_mala_period then recompute_seva_mala_period, which is exactly
--    what the nightly job does for a week whose last day is behind us: compute
--    once more, freeze, and award.
-- ---------------------------------------------------------------------------

create table public.bg_periods (label text primary key, id uuid not null, starts_on date not null);
grant select on public.bg_periods to authenticated;

insert into public.bg_periods (label, id, starts_on)
select 'A',
       public.ensure_seva_mala_period('week', public.seva_mala_week_start(public.seva_mala_today()) - 14),
       public.seva_mala_week_start(public.seva_mala_today()) - 14;

select public.recompute_seva_mala_period(
  (select id from public.bg_periods where label = 'A')
) as week_a_participants;

do $$
declare
  v_period public.seva_mala_periods;
begin
  select * into v_period from public.seva_mala_periods
  where id = (select id from public.bg_periods where label = 'A');

  if v_period.frozen_at is null then
    raise exception 'Week A did not freeze, so no rivalrous award could be decided.';
  end if;
  if v_period.participant_count <> 12 then
    raise exception 'Week A has % participants rather than twelve.', v_period.participant_count;
  end if;
  if v_period.participant_count < public.seva_mala_number('seva_mala.minimum_cohort', 8) then
    raise exception 'Week A is below the cohort, so no badge would publish.';
  end if;

  -- The fixture must still be sharp: exactly one devotee at the top, and it is
  -- Aravinda. If the scoring rule changes so much that this stops being true,
  -- the first-place assertions below would be proving something weaker and this
  -- says so rather than passing quietly.
  if (
    select count(*) from (
      select dense_rank() over (order by scores.score desc) as rk
      from public.period_scores scores
      where scores.period_id = v_period.id and scores.score > 0
    ) ranked where ranked.rk = 1
  ) <> 1 then
    raise exception 'Week A has no single devotee on top; the fixture has gone blunt.';
  end if;

  if not exists (
    select 1 from public.period_scores scores
    join public.bg_ids ids on ids.id = scores.devotee_id
    where scores.period_id = v_period.id
      and ids.key = 'aravinda'
      and scores.score = (
        select max(inner_scores.score) from public.period_scores inner_scores
        where inner_scores.period_id = v_period.id
      )
  ) then
    raise exception 'Aravinda is not on top of week A; the fixture has moved.';
  end if;
end;
$$;

-- FIRST PLACE, TOP THREE, TOP TEN — against a dense_rank computed here, not
-- against a list written down. The garland's code is whichever one the rotation
-- offered, which is itself the point: the rule does not name a Deity anywhere.
do $$
declare
  v_period uuid := (select id from public.bg_periods where label = 'A');
  v_starts date := (select starts_on from public.bg_periods where label = 'A');
  v_case record;
  v_garland text;
begin
  select definitions.code into v_garland
  from public.award_definitions definitions
  where definitions.id =
    public.award_rotation_turn('weekly_deity_garland', 'week', v_starts);
  if v_garland is null then
    raise exception 'No garland was offered for week A.';
  end if;

  for v_case in
    select * from (values
      (v_garland, 1),
      ('weekly_maha_prasad', 3),
      ('weekly_token', 10)
    ) as rung(code, n)
  loop
    if exists (
      select ranked.devotee_id from (
        select scores.devotee_id,
               dense_rank() over (order by scores.score desc) as rk
        from public.period_scores scores
        where scores.period_id = v_period and scores.score > 0
      ) ranked
      where ranked.rk <= v_case.n
      except
      select awards.devotee_id
      from public.devotee_awards awards
      join public.award_definitions definitions
        on definitions.id = awards.award_definition_id
      where awards.period_id = v_period and definitions.code = v_case.code
    ) then
      raise exception 'A devotee in the top % of week A did not get %.', v_case.n, v_case.code;
    end if;

    if exists (
      select awards.devotee_id
      from public.devotee_awards awards
      join public.award_definitions definitions
        on definitions.id = awards.award_definition_id
      where awards.period_id = v_period and definitions.code = v_case.code
      except
      select ranked.devotee_id from (
        select scores.devotee_id,
               dense_rank() over (order by scores.score desc) as rk
        from public.period_scores scores
        where scores.period_id = v_period and scores.score > 0
      ) ranked
      where ranked.rk <= v_case.n
    ) then
      raise exception 'Somebody outside the top % of week A got %.', v_case.n, v_case.code;
    end if;
  end loop;

  -- Exactly one garland from the cycle, and it is the one whose turn it was.
  if (
    select count(distinct definitions.code)
    from public.devotee_awards awards
    join public.award_definitions definitions
      on definitions.id = awards.award_definition_id
    where awards.period_id = v_period
      and definitions.rotation_group = 'weekly_deity_garland'
  ) <> 1 then
    raise exception 'Week A handed out more than one of the seven garlands.';
  end if;
end;
$$;

-- Every award told its devotee, on the kind 0055 declared, and told nobody else.
do $$
declare
  v_awards integer;
  v_sent integer;
begin
  select count(*) into v_awards from public.devotee_awards;
  select count(*) into v_sent from public.app_notifications
  where app_notifications.kind = 'seva_award_earned'
    and (app_notifications.data ->> 'awardId')::uuid in (
      select devotee_awards.id from public.devotee_awards
    );
  if v_sent <> v_awards then
    raise exception '% awards produced % notifications.', v_awards, v_sent;
  end if;

  if exists (
    select 1 from public.app_notifications
    join public.devotee_awards
      on devotee_awards.id = (app_notifications.data ->> 'awardId')::uuid
    where app_notifications.kind = 'seva_award_earned'
      and app_notifications.user_id <> devotee_awards.devotee_id
  ) then
    raise exception 'An award notification went to somebody other than the recipient.';
  end if;

  -- And the garland's notification says which Deity's it was, so the phone can
  -- draw the right thing.
  if not exists (
    select 1 from public.app_notifications
    where app_notifications.kind = 'seva_award_earned'
      and app_notifications.data ->> 'garlandKind' in
          ('kisora', 'kisori', 'jagannath', 'baldev', 'subhadra', 'gaura', 'nitai')
  ) then
    raise exception 'The garland notification does not say whose garland it is.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Running the close again awards nothing — and still awards nothing when
--    the cycle has been changed underneath it in between.
-- ---------------------------------------------------------------------------

do $$
declare
  v_period uuid := (select id from public.bg_periods where label = 'A');
  v_starts date := (select starts_on from public.bg_periods where label = 'A');
  v_before integer;
  v_given integer;
  v_offered uuid;
begin
  select count(*) into v_before from public.devotee_awards;

  v_given := public.award_seva_mala_for_period(v_period);
  if v_given <> 0 then
    raise exception 'A second run of week A gave % more awards.', v_given;
  end if;
  if (select count(*) from public.devotee_awards) <> v_before then
    raise exception 'A second run of week A changed the number of awards.';
  end if;

  -- The recompute path is idempotent too: a frozen period is left alone.
  perform public.recompute_seva_mala_period(v_period);
  if (select count(*) from public.devotee_awards) <> v_before then
    raise exception 'Recomputing a frozen week A awarded something new.';
  end if;

  -- Now the hard case. The President retires the garland that was offered.
  -- The cycle is six long from here, so the turn lands on a DIFFERENT garland
  -- — and week A has already had its garland, so it must still get nothing.
  select public.award_rotation_turn('weekly_deity_garland', 'week', v_starts)
  into v_offered;

  update public.award_definitions set is_active = false where id = v_offered;

  if public.award_rotation_turn('weekly_deity_garland', 'week', v_starts) = v_offered then
    raise exception 'Retiring a garland did not change whose turn it is; the case below is vacuous.';
  end if;

  v_given := public.award_seva_mala_for_period(v_period);
  if v_given <> 0 then
    raise exception
      'Week A was given % more awards after the rotation changed. A closed week has one garland.',
      v_given;
  end if;
  if (
    select count(distinct definitions.code)
    from public.devotee_awards awards
    join public.award_definitions definitions
      on definitions.id = awards.award_definition_id
    where awards.period_id = v_period
      and definitions.rotation_group = 'weekly_deity_garland'
  ) <> 1 then
    raise exception 'Week A now carries two of the seven garlands.';
  end if;

  update public.award_definitions set is_active = true where id = v_offered;

  if (select count(*) from public.devotee_awards) <> v_before then
    raise exception 'The award count moved across the idempotency checks.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. What the congregation sees while week A's badges are current.
--
--    Read as Bhavani, an ordinary devotee with no permission of any kind,
--    looking at somebody else's profile.
-- ---------------------------------------------------------------------------

create table public.bg_seen (
  label text not null,
  subject text not null,
  award_code text,
  title text,
  tier text,
  garland_kind text,
  period_kind text,
  period_start date
);
grant select, insert on public.bg_seen to authenticated;

do $$
declare
  v_current integer;
begin
  select count(*) into v_current from public.current_award_periods();
  if v_current <> 1 then
    raise exception
      'There are % currently displayed periods; only week A has closed and awarded.', v_current;
  end if;
  if (select period_id from public.current_award_periods())
     is distinct from (select id from public.bg_periods where label = 'A')
  then
    raise exception 'The current week is not week A.';
  end if;
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.bg_ids ids where ids.key = 'bhavani'), true);

insert into public.bg_seen (label, subject, award_code, title, tier, garland_kind, period_kind, period_start)
select 'during-A', 'aravinda', badges.award_code, badges.title, badges.tier,
       badges.garland_kind, badges.period_kind, badges.period_start
from public.list_devotee_badges(
  (select ids.id from public.bg_ids ids where ids.key = 'aravinda')
) badges;

insert into public.bg_seen (label, subject, award_code, title, tier, garland_kind, period_kind, period_start)
select 'during-A', 'chandrika', badges.award_code, badges.title, badges.tier,
       badges.garland_kind, badges.period_kind, badges.period_start
from public.list_devotee_badges(
  (select ids.id from public.bg_ids ids where ids.key = 'chandrika')
) badges;

reset role;
select set_config('request.jwt.claim.sub', '', true);

do $$
declare
  v_starts date := (select starts_on from public.bg_periods where label = 'A');
begin
  -- Aravinda was first: a garland, a plate and a token, all of them for week A.
  if not exists (
    select 1 from public.bg_seen
    where label = 'during-A' and subject = 'aravinda' and tier = 'garland'
      and garland_kind in ('kisora', 'kisori', 'jagannath', 'baldev', 'subhadra', 'gaura', 'nitai')
  ) then
    raise exception 'The congregation cannot see the garland Aravinda was given for week A.';
  end if;
  if not exists (
    select 1 from public.bg_seen
    where label = 'during-A' and subject = 'aravinda' and award_code = 'weekly_maha_prasad'
  ) then
    raise exception 'Aravinda''s Maha Prasad is not on his profile.';
  end if;

  -- And every badge shown is for week A and says so.
  if exists (
    select 1 from public.bg_seen
    where label = 'during-A' and subject = 'aravinda'
      and (period_start is distinct from v_starts or period_kind <> 'week')
  ) then
    raise exception 'A badge on the public profile is not labelled with week A.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 9. Closing week B: the badge leaves the profile and stays on the shelf.
--
--    This is the whole of what the temple asked for in clause three, and it is
--    the one behaviour a stored display_until would have got wrong.
-- ---------------------------------------------------------------------------

insert into public.bg_periods (label, id, starts_on)
select 'B',
       public.ensure_seva_mala_period('week', public.seva_mala_week_start(public.seva_mala_today()) - 7),
       public.seva_mala_week_start(public.seva_mala_today()) - 7;

select public.recompute_seva_mala_period(
  (select id from public.bg_periods where label = 'B')
) as week_b_participants;

do $$
declare
  v_a uuid := (select id from public.bg_periods where label = 'A');
  v_b uuid := (select id from public.bg_periods where label = 'B');
  v_b_starts date := (select starts_on from public.bg_periods where label = 'B');
  v_case record;
  v_garland text;
begin
  if (select frozen_at from public.seva_mala_periods where id = v_b) is null then
    raise exception 'Week B did not freeze.';
  end if;

  -- Week B awarded on the same three rungs.
  select definitions.code into v_garland
  from public.award_definitions definitions
  where definitions.id =
    public.award_rotation_turn('weekly_deity_garland', 'week', v_b_starts);

  for v_case in
    select * from (values (v_garland, 1), ('weekly_maha_prasad', 3), ('weekly_token', 10))
      as rung(code, n)
  loop
    if exists (
      select ranked.devotee_id from (
        select scores.devotee_id, dense_rank() over (order by scores.score desc) as rk
        from public.period_scores scores
        where scores.period_id = v_b and scores.score > 0
      ) ranked where ranked.rk <= v_case.n
      except
      select awards.devotee_id from public.devotee_awards awards
      join public.award_definitions definitions on definitions.id = awards.award_definition_id
      where awards.period_id = v_b and definitions.code = v_case.code
    ) or exists (
      select awards.devotee_id from public.devotee_awards awards
      join public.award_definitions definitions on definitions.id = awards.award_definition_id
      where awards.period_id = v_b and definitions.code = v_case.code
      except
      select ranked.devotee_id from (
        select scores.devotee_id, dense_rank() over (order by scores.score desc) as rk
        from public.period_scores scores
        where scores.period_id = v_b and scores.score > 0
      ) ranked where ranked.rk <= v_case.n
    ) then
      raise exception 'Week B''s % did not go to exactly the top %.', v_case.code, v_case.n;
    end if;
  end loop;

  -- A different Deity's garland, because the rotation moved on.
  if (
    select count(distinct definitions.rotation_seat)
    from public.devotee_awards awards
    join public.award_definitions definitions on definitions.id = awards.award_definition_id
    where awards.period_id in (v_a, v_b)
      and definitions.rotation_group = 'weekly_deity_garland'
  ) <> 2 then
    raise exception 'Weeks A and B were given the same garland.';
  end if;

  -- THE CURRENT WEEK IS NOW B, AND ONLY B. Counted before it is read, so a
  -- rule that let every closed week stay on display says so in words rather
  -- than falling over on a subquery.
  if (select count(*) from public.current_award_periods() where period_kind = 'week') <> 1 then
    raise exception
      'There are % weeks on display. Exactly one week — the latest closed one — may be current, or a badge never expires.',
      (select count(*) from public.current_award_periods() where period_kind = 'week');
  end if;
  if (select period_id from public.current_award_periods() where period_kind = 'week')
     is distinct from v_b
  then
    raise exception 'Week A''s badges are still the current ones after week B closed.';
  end if;
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.bg_ids ids where ids.key = 'bhavani'), true);

insert into public.bg_seen (label, subject, award_code, title, tier, garland_kind, period_kind, period_start)
select 'during-B', 'aravinda', badges.award_code, badges.title, badges.tier,
       badges.garland_kind, badges.period_kind, badges.period_start
from public.list_devotee_badges(
  (select ids.id from public.bg_ids ids where ids.key = 'aravinda')
) badges;

insert into public.bg_seen (label, subject, award_code, title, tier, garland_kind, period_kind, period_start)
select 'during-B', 'lochana', badges.award_code, badges.title, badges.tier,
       badges.garland_kind, badges.period_kind, badges.period_start
from public.list_devotee_badges(
  (select ids.id from public.bg_ids ids where ids.key = 'lochana')
) badges;

reset role;
select set_config('request.jwt.claim.sub', '', true);

do $$
declare
  v_a_starts date := (select starts_on from public.bg_periods where label = 'A');
  v_b_starts date := (select starts_on from public.bg_periods where label = 'B');
begin
  -- Nothing from week A is on a public profile any more.
  if exists (
    select 1 from public.bg_seen
    where label = 'during-B' and period_start = v_a_starts
  ) then
    raise exception 'A week A badge is still on a public profile after week B''s badges landed.';
  end if;

  -- Lochana, who is first in week B, now wears the week's garland.
  if not exists (
    select 1 from public.bg_seen
    where label = 'during-B' and subject = 'lochana' and tier = 'garland'
      and period_start = v_b_starts
  ) then
    raise exception 'Week B''s first place is not wearing week B''s garland.';
  end if;

  -- Aravinda was last in week B, so the congregation sees nothing of week A on
  -- him — and this is the case a stored display_until would have had to expire.
  if exists (
    select 1 from public.bg_seen
    where label = 'during-B' and subject = 'aravinda' and tier = 'garland'
  ) then
    raise exception 'Aravinda is still wearing last week''s garland in public.';
  end if;

  -- AND IT IS STILL HIS. On the shelf, forever, with is_current false.
  if not exists (
    select 1 from public.devotee_awards awards
    join public.award_definitions definitions on definitions.id = awards.award_definition_id
    join public.bg_ids ids on ids.id = awards.devotee_id
    where ids.key = 'aravinda'
      and definitions.rotation_group = 'weekly_deity_garland'
      and awards.period_id = (select id from public.bg_periods where label = 'A')
  ) then
    raise exception 'Aravinda''s week A garland was removed from devotee_awards.';
  end if;
end;
$$;

-- The shelf says so too, in Aravinda's own hands.
set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.bg_ids ids where ids.key = 'aravinda'), true);

do $$
declare
  v_me uuid := (select ids.id from public.bg_ids ids where ids.key = 'aravinda');
  v_a_starts date := (select starts_on from public.bg_periods where label = 'A');
  v_shelf integer;
  v_current integer;
begin
  select count(*), count(*) filter (where shelf.is_current)
  into v_shelf, v_current
  from public.list_devotee_award_shelf(v_me) shelf;

  if v_shelf < 3 then
    raise exception 'Aravinda''s shelf holds % awards; he was first in week A.', v_shelf;
  end if;

  if not exists (
    select 1 from public.list_devotee_award_shelf(v_me) shelf
    where shelf.tier = 'garland' and shelf.period_start = v_a_starts
      and not shelf.is_current
  ) then
    raise exception
      'Aravinda''s week A garland is either gone from his shelf or still marked current.';
  end if;

  -- His week B awards, if any, are the current ones. He was last in week B, so
  -- the only thing that could be current is a threshold or a draw — and the
  -- point being made is that expiry is per period and not per award.
  if exists (
    select 1 from public.list_devotee_award_shelf(v_me) shelf
    where shelf.is_current and shelf.period_start = v_a_starts
  ) then
    raise exception 'A week A award on the shelf still claims to be current.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);

-- ---------------------------------------------------------------------------
-- 10. The month runs on its own clock.
--
--     A month badge and a week badge are current at the same time, because
--     "currently displayed" is per period kind.
-- ---------------------------------------------------------------------------

insert into public.bg_periods (label, id, starts_on)
select 'M',
       public.ensure_seva_mala_period(
         'month', (date_trunc('month', public.seva_mala_today()) - interval '1 month')::date),
       (date_trunc('month', public.seva_mala_today()) - interval '1 month')::date;

select public.recompute_seva_mala_period(
  (select id from public.bg_periods where label = 'M')
) as month_participants;

do $$
declare
  v_month uuid := (select id from public.bg_periods where label = 'M');
  v_starts date := (select starts_on from public.bg_periods where label = 'M');
  v_case record;
  v_garland text;
begin
  if (select frozen_at from public.seva_mala_periods where id = v_month) is null then
    raise exception 'Last month did not freeze.';
  end if;

  select definitions.code into v_garland
  from public.award_definitions definitions
  where definitions.id =
    public.award_rotation_turn('monthly_deity_garland', 'month', v_starts);
  if v_garland is null then
    raise exception 'No garland was offered for last month.';
  end if;

  -- The month's own three rungs: 0063's first-place garland, 0055's three
  -- lateral garlands at top three, and 0055's Maha Prasad at top ten.
  for v_case in
    select * from (values
      (v_garland, 1),
      ('garland_seva', 3),
      ('monthly_maha_prasad', 10)
    ) as rung(code, n)
  loop
    if exists (
      select ranked.devotee_id from (
        select scores.devotee_id,
               dense_rank() over (
                 order by case (select rank_basis from public.award_definitions
                                where code = v_case.code)
                   when 'seva' then scores.seva_norm
                   when 'giving' then scores.giving_norm
                   else scores.score
                 end desc
               ) as rk
        from public.period_scores scores
        where scores.period_id = v_month
          and case (select rank_basis from public.award_definitions where code = v_case.code)
                when 'seva' then scores.seva_norm
                when 'giving' then scores.giving_norm
                else scores.score
              end > 0
      ) ranked where ranked.rk <= v_case.n
      except
      select awards.devotee_id from public.devotee_awards awards
      join public.award_definitions definitions on definitions.id = awards.award_definition_id
      where awards.period_id = v_month and definitions.code = v_case.code
    ) then
      raise exception 'A devotee in the month''s top % did not get %.', v_case.n, v_case.code;
    end if;
  end loop;

  -- Both kinds are on display at once.
  if (select count(*) from public.current_award_periods()) <> 2 then
    raise exception 'The month did not join the week on display.';
  end if;
  if (select period_id from public.current_award_periods() where period_kind = 'month')
     is distinct from v_month
  then
    raise exception 'The current month is not last month.';
  end if;
  if (select period_id from public.current_award_periods() where period_kind = 'week')
     is distinct from (select id from public.bg_periods where label = 'B')
  then
    raise exception 'Closing a month moved which week is on display.';
  end if;
end;
$$;

-- Ekanatha, first for the month, wears a month garland and a week badge only if
-- he earned one — read by an ordinary devotee, and both period kinds together.
set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.bg_ids ids where ids.key = 'bhavani'), true);

insert into public.bg_seen (label, subject, award_code, title, tier, garland_kind, period_kind, period_start)
select 'after-M', 'ekanatha', badges.award_code, badges.title, badges.tier,
       badges.garland_kind, badges.period_kind, badges.period_start
from public.list_devotee_badges(
  (select ids.id from public.bg_ids ids where ids.key = 'ekanatha')
) badges;

reset role;
select set_config('request.jwt.claim.sub', '', true);

do $$
begin
  if not exists (
    select 1 from public.bg_seen
    where label = 'after-M' and subject = 'ekanatha'
      and period_kind = 'month' and tier = 'garland'
  ) then
    raise exception 'The month''s first place is not wearing the month''s garland.';
  end if;
  if exists (
    select 1 from public.bg_seen
    where label = 'after-M' and subject = 'ekanatha'
      and period_kind not in ('week', 'month')
  ) then
    raise exception 'A badge is labelled with a period kind that is neither week nor month.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 11. Opting out.
--
--     Chandrika earned real badges. Nobody but Chandrika and the President can
--     see them, and every one of them is still hers.
-- ---------------------------------------------------------------------------

do $$
declare
  v_earned integer;
begin
  select count(*) into v_earned
  from public.devotee_awards awards
  join public.bg_ids ids on ids.id = awards.devotee_id
  where ids.key = 'chandrika';
  if v_earned = 0 then
    raise exception
      'Chandrika earned nothing, so the opt-out case below proves nothing. Opting out must not have stopped her being scored.';
  end if;

  -- Specifically: she is inside a rung that is currently on display.
  if not exists (
    select 1 from public.devotee_awards awards
    join public.bg_ids ids on ids.id = awards.devotee_id
    join public.current_award_periods() current_periods
      on current_periods.period_id = awards.period_id
    where ids.key = 'chandrika'
  ) then
    raise exception 'Chandrika holds no award for a currently displayed period.';
  end if;
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.bg_ids ids where ids.key = 'bhavani'), true);

do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from public.list_devotee_badges(
    (select ids.id from public.bg_ids ids where ids.key = 'chandrika'));
  if v_count <> 0 then
    raise exception
      'A devotee who opted out of the board has % badges on her public profile. The switch would be decoration.',
      v_count;
  end if;

  -- And her shelf is not another way round.
  select count(*) into v_count
  from public.list_devotee_award_shelf(
    (select ids.id from public.bg_ids ids where ids.key = 'chandrika'));
  if v_count <> 0 then
    raise exception 'An ordinary devotee read % rows of somebody else''s shelf.', v_count;
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);

-- She sees her own, through the same public function.
set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.bg_ids ids where ids.key = 'chandrika'), true);

do $$
declare
  v_me uuid := (select ids.id from public.bg_ids ids where ids.key = 'chandrika');
  v_badges integer;
  v_shelf integer;
  v_current integer;
begin
  select count(*) into v_badges from public.list_devotee_badges(v_me);
  if v_badges = 0 then
    raise exception 'Chandrika cannot see her own current badges.';
  end if;

  select count(*), count(*) filter (where shelf.is_current)
  into v_shelf, v_current
  from public.list_devotee_award_shelf(v_me) shelf;
  if v_shelf = 0 then
    raise exception 'Chandrika''s shelf is empty.';
  end if;

  -- is_current means "the public can see this right now", and for a devotee who
  -- opted out the honest answer is no. Nothing was taken away; nothing is shown.
  if v_current <> 0 then
    raise exception
      'Chandrika''s shelf claims % awards are publicly current while she is off the board.',
      v_current;
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);

-- ---------------------------------------------------------------------------
-- 12. The President and the Tech Admin see everything.
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.bg_ids ids where ids.key = 'nrsimha'), true);

do $$
declare
  v_who record;
  v_seen integer;
  v_held integer;
begin
  for v_who in select key, id from public.bg_ids where key <> 'nrsimha' loop
    select count(*) into v_seen from public.list_devotee_award_shelf(v_who.id);
    select count(*) into v_held from public.devotee_awards
    where devotee_awards.devotee_id = v_who.id;
    if v_seen <> v_held then
      raise exception
        'The President sees % of %''s % awards.', v_seen, v_who.key, v_held;
    end if;
  end loop;

  -- Including the expired ones, which is the point of a shelf.
  if not exists (
    select 1 from public.list_devotee_award_shelf(
      (select ids.id from public.bg_ids ids where ids.key = 'aravinda')) shelf
    where not shelf.is_current
  ) then
    raise exception 'The President cannot see Aravinda''s expired week A badges.';
  end if;

  -- And the opted-out devotee is not hidden from the temple.
  if (
    select count(*) from public.list_devotee_badges(
      (select ids.id from public.bg_ids ids where ids.key = 'chandrika'))
  ) = 0 then
    raise exception 'The President cannot see the badges of a devotee who opted out.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);

-- ---------------------------------------------------------------------------
-- 13. The cohort gate.
--
--     0055 will not publish a ranking of a congregation too small to be ranked,
--     and a public badge is a ranking with the number filed off. Raising the
--     minimum above the fixture must empty the public profiles and touch
--     nothing on the shelves.
-- ---------------------------------------------------------------------------

update public.app_settings set value = '50' where key = 'seva_mala.minimum_cohort';

set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.bg_ids ids where ids.key = 'bhavani'), true);

do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from public.list_devotee_badges(
    (select ids.id from public.bg_ids ids where ids.key = 'lochana'));
  if v_count <> 0 then
    raise exception
      'A congregation of twelve under a minimum of fifty published % badges.', v_count;
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);

set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.bg_ids ids where ids.key = 'lochana'), true);

do $$
declare
  v_me uuid := (select ids.id from public.bg_ids ids where ids.key = 'lochana');
  v_count integer;
begin
  select count(*) into v_count from public.list_devotee_award_shelf(v_me);
  if v_count = 0 then
    raise exception 'The cohort gate emptied a devotee''s own shelf.';
  end if;
  if exists (
    select 1 from public.list_devotee_award_shelf(v_me) shelf where shelf.is_current
  ) then
    raise exception 'The shelf still calls an award current under a cohort nobody meets.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);

update public.app_settings set value = '8' where key = 'seva_mala.minimum_cohort';

-- And it comes straight back, because nothing was written down.
set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.bg_ids ids where ids.key = 'bhavani'), true);

do $$
begin
  if (
    select count(*) from public.list_devotee_badges(
      (select ids.id from public.bg_ids ids where ids.key = 'lochana'))
  ) = 0 then
    raise exception 'Lowering the cohort back did not restore the badges.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);

-- ---------------------------------------------------------------------------
-- 14. NOTHING REVOKES. EVER.
--
--     Three ways to try: by hand, by an UPDATE that rewrites which award it
--     was, and by a function somebody adds later. All three are refused.
-- ---------------------------------------------------------------------------

do $$
declare
  v_award uuid;
  v_before integer;
  v_refused boolean;
begin
  select count(*) into v_before from public.devotee_awards;

  -- The oldest expired badge in the fixture — exactly the row an "expire old
  -- badges" job would reach for.
  select awards.id into v_award
  from public.devotee_awards awards
  where awards.period_id = (select id from public.bg_periods where label = 'A')
  limit 1;

  v_refused := false;
  begin
    delete from public.devotee_awards where devotee_awards.id = v_award;
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'An expired badge was deleted.';
  end if;

  v_refused := false;
  begin
    delete from public.devotee_awards
    where devotee_awards.period_id = (select id from public.bg_periods where label = 'A');
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A whole closed week of badges was deleted.';
  end if;

  v_refused := false;
  begin
    update public.devotee_awards set devotee_id = (
      select ids.id from public.bg_ids ids where ids.key = 'mukunda')
    where devotee_awards.id = v_award;
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'An award was moved to a different devotee.';
  end if;

  v_refused := false;
  begin
    update public.devotee_awards set period_id = (
      select id from public.bg_periods where label = 'B')
    where devotee_awards.id = v_award;
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'An award was re-dated into a different period, which is expiry by another name.';
  end if;

  if (select count(*) from public.devotee_awards) <> v_before then
    raise exception 'The award count moved while nothing was allowed to.';
  end if;

  -- The positive control: fulfilment is the one thing that may still be written,
  -- or the checks above would pass on a table nobody can touch at all.
  update public.devotee_awards
  set fulfilled_on = public.seva_mala_today(), fulfilment_note = 'Handed over after the Sunday feast.'
  where devotee_awards.id = v_award;
  if (
    select fulfilled_on from public.devotee_awards where devotee_awards.id = v_award
  ) is null then
    raise exception 'Fulfilment could not be recorded, so the append-only trigger is refusing everything.';
  end if;
end;
$$;

-- No function in this schema can remove an award or rewrite which award it was.
do $$
declare
  v_offenders text;
begin
  select string_agg(proc.proname, ', ' order by proc.proname) into v_offenders
  from pg_proc proc
  join pg_namespace spaces on spaces.oid = proc.pronamespace
  where spaces.nspname = 'public'
    and proc.prokind = 'f'
    and (
      lower(pg_get_functiondef(proc.oid)) like '%delete from public.devotee_awards%'
      or lower(pg_get_functiondef(proc.oid)) like '%update public.devotee_awards%set%award_definition_id%'
      or lower(pg_get_functiondef(proc.oid)) like '%update public.devotee_awards%set%period_id%'
    )
    and proc.proname <> 'devotee_awards_stay_append_only';

  if v_offenders is not null then
    raise exception
      'These functions can take an award back: %. Nothing in this schema may.', v_offenders;
  end if;

  -- And there is no expiry column for a job to sweep, because expiry is a join
  -- that stops matching. A display_until would be a date that drifts.
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'devotee_awards'
      and (column_name ilike '%expire%' or column_name ilike '%display_until%'
           or column_name ilike '%revoked%' or column_name ilike '%visible%')
  ) then
    raise exception 'devotee_awards grew a column that expires or hides an award.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 15. As an ordinary devotee, with nothing but a session.
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.bg_ids ids where ids.key = 'mukunda'), true);

do $$
declare
  v_me uuid := (select ids.id from public.bg_ids ids where ids.key = 'mukunda');
  v_count integer;
begin
  begin
    execute 'select count(*) from public.period_scores' into v_count;
    raise exception 'A signed-in devotee read the scores.';
  exception
    when insufficient_privilege then null;
    when others then if sqlstate = 'P0001' then raise; end if;
  end;

  begin
    execute 'select count(*) from public.seva_mala_periods' into v_count;
    raise exception 'A signed-in devotee read the period references.';
  exception
    when insufficient_privilege then null;
    when others then if sqlstate = 'P0001' then raise; end if;
  end;

  begin
    execute 'select public.award_seva_mala_for_period('''
      || (select id from public.bg_periods where label = 'A') || ''')' into v_count;
    raise exception 'A devotee ran the awarding job.';
  exception
    when insufficient_privilege then null;
    when others then if sqlstate = 'P0001' then raise; end if;
  end;

  begin
    execute 'select count(*) from public.current_award_periods()' into v_count;
    raise exception 'A devotee read the display window directly.';
  exception
    when insufficient_privilege then null;
    when others then if sqlstate = 'P0001' then raise; end if;
  end;

  -- devotee_awards itself is row level secured to their own, and Mukunda's own
  -- is all he gets — not the congregation's.
  select count(*) into v_count from public.devotee_awards
  where devotee_awards.devotee_id <> v_me;
  if v_count <> 0 then
    raise exception 'A devotee read % of somebody else''s award rows.', v_count;
  end if;

  -- He cannot write one either.
  begin
    execute 'insert into public.devotee_awards (award_definition_id, devotee_id) '
      || 'select id, ''' || v_me || ''' from public.award_definitions limit 1';
    raise exception 'A devotee gave themselves an award.';
  exception
    when insufficient_privilege then null;
    when others then if sqlstate = 'P0001' then raise; end if;
  end;

  -- The public badge list still answers about anybody, which is what the temple
  -- asked for, and it answers with names and periods only.
  select count(*) into v_count from public.list_devotee_badges(
    (select ids.id from public.bg_ids ids where ids.key = 'lochana'));
  if v_count = 0 then
    raise exception 'An ordinary devotee cannot see another devotee''s badges at all.';
  end if;

  -- But not about a shelf that is not his.
  select count(*) into v_count from public.list_devotee_award_shelf(
    (select ids.id from public.bg_ids ids where ids.key = 'lochana'));
  if v_count <> 0 then
    raise exception 'An ordinary devotee read somebody else''s shelf.';
  end if;

  -- And a null subject is not a wildcard.
  select count(*) into v_count from public.list_devotee_badges(null);
  if v_count <> 0 then
    raise exception 'A null devotee id returned % badges.', v_count;
  end if;
  select count(*) into v_count from public.list_devotee_award_shelf(null);
  if v_count <> 0 then
    raise exception 'A null devotee id returned % shelf rows.', v_count;
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);

-- Signed out, nothing at all.
set local role authenticated;
select set_config('request.jwt.claim.sub', '', true);

do $$
declare
  v_count integer;
begin
  select count(*) into v_count from public.list_devotee_badges(
    (select ids.id from public.bg_ids ids where ids.key = 'lochana'));
  if v_count <> 0 then
    raise exception 'A session with no devotee behind it read % badges.', v_count;
  end if;
end;
$$;

reset role;

do $$
begin
  raise notice 'all badges and gifts checks passed';
end;
$$;

select 'badges and gifts verification passed' as result;

rollback;
