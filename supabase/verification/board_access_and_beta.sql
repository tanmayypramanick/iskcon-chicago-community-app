-- Functional verification for 202608040064_board_access_and_beta.sql.
--
-- Rolled back at the end. Every local is prefixed v_ so it can never shadow a
-- column name. Anything a devotee or a Community Head could really attempt is
-- attempted as that person, under `set local role authenticated`, so the
-- grants, the row level security and the permission checks are what is being
-- tested rather than superuser rights waving everything through.
--
-- 0064 does two things and this file exists to prove both, and to prove that
-- everything 0055 through 0063 built underneath them is still standing.
--
--   1. THE BALANCE DIAL IS 0.3. The temple's choice, carried by an UPDATE that
--      is guarded on the old value so it is a one-time correction rather than a
--      standing instruction, and followed by a recompute of the periods that
--      ALREADY EXIST AND ARE NOT FROZEN — creating none, because 0059 §7 is
--      right that a migration must not decide last week was empty.
--
--   2. A COMMUNITY HEAD SEES THE WHOLE BOARD. The ranking over everybody,
--      opted-out devotees included and flagged, with the published points and
--      the seva figures — and NOT the exact score, NOT either norm and NOT one
--      cent of anybody's giving, because score and seva_norm together give
--      giving_norm back exactly and giving_norm gives back the gift.
--
-- ---------------------------------------------------------------------------
-- What 0.3 changes, which is what most of section 2 is checking:
--
--   the devotee                     beta = 0.5    beta = 0.3
--   ----------------------------------------------------------
--   top sevak, gives nothing          0.666667      0.769231
--   top donor, no time to serve       0.666667      0.769231
--   top at both                       1.000000      1.000000
--   moderate at both (0.5, 0.5)       0.500000      0.500000
--   s-hat = 1.0, g-hat = 0.3          0.766667      0.838462
--   the per-dimension ceiling              1.5           1.3
--   the published ceiling                 1500          1300
--
-- The ceiling moves because 0062 derives it as 1 + beta rather than typing 1.5
-- in, and this file checks that it followed rather than that somebody
-- remembered.
--
-- ---------------------------------------------------------------------------
-- The cast. Sixteen devotees, fifteen of whom carry a score, which is nearly
-- twice 0055's minimum cohort of eight, so the board publishes and the
-- congregation-relative references are percentiles of a real congregation.
-- Fourteen of the fifteen opt in; one does not.
--
--   pres      president   nothing given or served — app.view_all
--   head      core        360 minutes — services.manage_recurring and NOT
--                         app.view_all, which is the whole distinction this
--                         file turns on
--   vol       volunteer   180 minutes — holds neither key, and is the negative
--                         that pins the gate to the permission rather than to
--                         "anybody senior"
--   plain     devotee     180 minutes — the ordinary devotee, made a Community
--                         Head in section 11 without anything else about them
--                         changing
--   hidden    devotee     540 minutes and $300, and leaderboard_visible false
--   sevak     devotee     1,440 minutes, nothing given   the pure sevak
--   donor     devotee     $900, no time to serve         the pure donor
--   both      devotee     720 minutes and $450           the whole garland
--   s1..s4    devotee     seva only, 1,080 down to 180 minutes
--   g1..g4    devotee     $600, $250, $120, $40
--
-- Everything sits strictly before the current Chicago week begins, anchored on
-- last Sunday, so the script is deterministic on any day of any week: the
-- lifetime period always holds the whole fixture and is the board every
-- assertion is made against.
--
-- The final row must read: board access and beta verification passed

begin;

-- ---------------------------------------------------------------------------
-- 0. The ground.
--
--    The dials, the two permissions this file is about, the grants 0064 claims
--    not to have widened, and the one thing that can be proved before a single
--    fixture row exists: that the migration created no Seva Mala period.
-- ---------------------------------------------------------------------------

do $$
declare
  v_expected text;
  v_actual text;
  v_holders text;
  v_periods integer;
begin
  for v_expected, v_actual in
    select expected.key || '=' || expected.value,
           expected.key || '=' || coalesce(settings.value, '(absent)')
    from (values
      -- The whole point of the migration, and every number below depends on it.
      ('seva_mala.balance_beta', '0.3'),
      ('seva_mala.soft_cap_alpha', '0.15'),
      ('seva_mala.reference_quantile', '0.80'),
      ('seva_mala.reference_shrink_k', '12'),
      ('seva_mala.trailing_days', '90'),
      ('seva_mala.seva_unit_fallback_minutes', '60'),
      ('seva_mala.giving_unit_fallback_cents', '2500'),
      ('seva_mala.daily_cap_minutes', '480'),
      ('seva_mala.weekly_cap_minutes', '1800'),
      ('seva_mala.minimum_cohort', '8')
    ) as expected(key, value)
    left join public.app_settings settings on settings.key = expected.key
    where settings.value is distinct from expected.value
  loop
    raise exception 'A dial this file depends on reads % rather than %.',
      v_actual, v_expected;
  end loop;

  -- NO PERIOD WAS CREATED BY THE MIGRATION. 0059 §7's refusal, kept: the
  -- migration recomputes what exists and calls ensure_seva_mala_period never,
  -- so on a database built from these migrations there is still nothing to
  -- freeze and last week has not been declared empty. Every other verification
  -- script rolls back, so anything here would be 0064's.
  select count(*) into v_periods from public.seva_mala_periods;
  if v_periods <> 0 then
    raise exception
      '% Seva Mala period(s) exist before any fixture. The migration created them, and a period a migration creates and freezes is a week nobody can ever score.',
      v_periods;
  end if;

  select string_agg(roles.name, ',' order by roles.name) into v_holders
  from public.role_permissions
  join public.roles on roles.id = role_permissions.role_id
  where role_permissions.permission_key = 'app.view_all';
  if v_holders is distinct from 'president,tech' then
    raise exception 'app.view_all is held by %.', coalesce(v_holders, '(nobody)');
  end if;

  select string_agg(roles.name, ',' order by roles.name) into v_holders
  from public.role_permissions
  join public.roles on roles.id = role_permissions.role_id
  where role_permissions.permission_key = 'services.manage_recurring';
  if v_holders is distinct from 'core,president,tech' then
    raise exception
      'services.manage_recurring is held by % rather than core, president, tech.',
      coalesce(v_holders, '(nobody)');
  end if;

  -- The distinction 0058 §1 drew and 0064 leans on: a Community Head runs a
  -- rota. If core ever holds app.view_all then the giving columns and Seva Care
  -- open with the board and every negative below is vacuous.
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
    raise exception 'The Community Head role holds app.view_all.';
  end if;

  -- 0055 §4, in the part 0064 does not reverse. The tables are still nobody's.
  if has_table_privilege('authenticated', 'public.period_scores', 'select')
    or has_table_privilege('authenticated', 'public.seva_mala_periods', 'select')
    or has_table_privilege('authenticated', 'public.app_settings', 'select')
    or has_table_privilege('authenticated', 'public.donations', 'select')
  then
    raise exception 'authenticated can read the Seva Mala components or the amounts.';
  end if;

  -- The recompute is backend-only. A devotee who could call it could not change
  -- their own score, but they could make the database do a hundred percentile
  -- scans on request.
  if has_function_privilege('authenticated', 'public.recompute_open_seva_mala_periods()', 'execute')
    or has_function_privilege('anon', 'public.recompute_open_seva_mala_periods()', 'execute')
  then
    raise exception 'A client role can run recompute_open_seva_mala_periods.';
  end if;
  if not has_function_privilege('service_role', 'public.recompute_open_seva_mala_periods()', 'execute') then
    raise exception 'The temple''s own schedule cannot run recompute_open_seva_mala_periods.';
  end if;

  -- And no new door is open to a signed-out visitor.
  if has_function_privilege('anon', 'public.may_view_whole_seva_board()', 'execute')
    or has_function_privilege('anon', 'public.list_all_seva_scores(text)', 'execute')
  then
    raise exception 'A signed-out visitor can reach the whole Seva Mala board.';
  end if;
  if not has_function_privilege('authenticated', 'public.may_view_whole_seva_board()', 'execute')
    or not has_function_privilege('authenticated', 'public.list_all_seva_scores(text)', 'execute')
  then
    raise exception 'A signed-in devotee cannot reach the board 0064 exists to serve.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 1. The signatures and the shape.
--
--    A column added to this board is a decision somebody has to make on
--    purpose, and a leftover overload has broken this repository before.
-- ---------------------------------------------------------------------------

do $$
declare
  v_name text;
  v_shape text;
  v_columns text;
begin
  for v_name in
    select proc.proname
    from pg_proc proc
    join pg_namespace spaces on spaces.oid = proc.pronamespace
    where spaces.nspname = 'public'
      and proc.proname in (
        'list_all_seva_scores', 'may_view_whole_seva_board',
        'recompute_open_seva_mala_periods', 'may_view_all_giving',
        'seva_mala_points', 'seva_mala_norm_ceiling')
    group by proc.proname
    having count(*) <> 1
  loop
    raise exception
      'There is more than one public.%; a defaulted overload makes the call ambiguous.',
      v_name;
  end loop;

  for v_name, v_shape in
    select expected.name, coalesce(
      (select pg_get_function_identity_arguments(proc.oid)
       from pg_proc proc
       join pg_namespace spaces on spaces.oid = proc.pronamespace
       where spaces.nspname = 'public' and proc.proname = expected.name), '(missing)')
    from (values
      ('list_all_seva_scores', 'p_period_kind text'),
      ('may_view_whole_seva_board', ''),
      ('recompute_open_seva_mala_periods', '')
    ) as expected(name, args)
    where expected.args is distinct from coalesce(
      (select pg_get_function_identity_arguments(proc.oid)
       from pg_proc proc
       join pg_namespace spaces on spaces.oid = proc.pronamespace
       where spaces.nspname = 'public' and proc.proname = expected.name), '(missing)')
  loop
    raise exception 'public.% takes (%).', v_name, v_shape;
  end loop;

  select string_agg(parameters.parameter_name, ', ' order by parameters.ordinal_position)
  into v_columns
  from information_schema.parameters parameters
  where parameters.specific_schema = 'public'
    and parameters.specific_name like 'list_all_seva_scores%'
    and parameters.parameter_mode = 'OUT';
  if v_columns <> 'standing, devotee_id, devotee_name, points, score, seva_minutes, '
                || 'seva_acts, giving_cents, gifts, seva_norm, giving_norm, is_hidden, '
                || 'giving_withheld' then
    raise exception 'The whole board returns (%).', v_columns;
  end if;
end;
$$;

-- The set of functions an ordinary devotee may execute whose RETURN TYPE names
-- a Seva Mala component is 0060's set and has not grown. 0064 widened who
-- list_all_seva_scores answers; it did not add a second way to ask.
do $$
declare
  v_leaky text;
begin
  select string_agg(distinct proc.proname, ', ' order by proc.proname) into v_leaky
  from pg_proc proc
  join pg_namespace spaces on spaces.oid = proc.pronamespace
  where spaces.nspname = 'public'
    and has_function_privilege('authenticated', proc.oid, 'execute')
    and (
      pg_get_function_result(proc.oid) like '%seva_norm%'
      or pg_get_function_result(proc.oid) like '%giving_norm%'
      or pg_get_function_result(proc.oid) like '%giving_reference%'
      or pg_get_function_result(proc.oid) like '%giving_unit%'
    );
  if v_leaky is distinct from 'explain_my_score, list_all_seva_scores' then
    raise exception
      'The functions an ordinary devotee may execute that return a Seva Mala component are: %. That set has changed.',
      coalesce(v_leaky, '(none)');
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. The dial and its arithmetic, before any fixture exists.
--
--    Everything here is a property of the setting and of two pure functions
--    over numbers this file supplies, so it holds whatever the congregation
--    happens to be.
-- ---------------------------------------------------------------------------

do $$
declare
  v_beta numeric := public.seva_mala_number('seva_mala.balance_beta', 0.5);
  v_case record;
  v_got numeric;
  v_want numeric;
  v_x numeric;
begin
  if v_beta <> 0.3 then
    raise exception 'The balance dial reads % rather than the 0.3 the temple chose.', v_beta;
  end if;

  -- The header's table, cell by cell.
  for v_case in
    select * from (values
      (1.0, 0.0, 0.769231),
      (0.0, 1.0, 0.769231),
      (1.0, 1.0, 1.000000),
      (0.5, 0.5, 0.500000),
      (1.0, 0.3, 0.838462),
      (0.0, 0.0, 0.000000)
    ) as expected(s, g, score)
  loop
    v_got := public.seva_mala_score(v_case.s, v_case.g, v_beta);
    if v_got <> v_case.score then
      raise exception
        'A devotee at s-hat %, g-hat % scores % at beta 0.3 rather than %.',
        v_case.s, v_case.g, v_got, v_case.score;
    end if;
  end loop;

  -- And the rule, re-typed rather than delegated, over a grid. The published
  -- formula is (max + beta*min)/(1 + beta) and this is the only place in this
  -- file that says so in arithmetic rather than by calling the function that
  -- is under test.
  for v_case in
    select gs.s / 10.0 as s, gg.g / 10.0 as g
    from generate_series(0, 13) gs(s), generate_series(0, 13) gg(g)
  loop
    v_want := round(
      (greatest(v_case.s, v_case.g) + 0.3 * least(v_case.s, v_case.g)) / 1.3, 6);
    v_got := public.seva_mala_score(v_case.s, v_case.g, 0.3);
    if v_got <> v_want then
      raise exception
        'seva_mala_score(%, %, 0.3) is % rather than the published %.',
        v_case.s, v_case.g, v_got, v_want;
    end if;
  end loop;

  -- Serving alone and giving alone reach the same place, which is the sentence
  -- 0059 inverted the rule to make true and 0.3 does not disturb.
  for v_x in select generate_series(0, 13) / 10.0 loop
    if public.seva_mala_score(v_x, 0, 0.3) <> public.seva_mala_score(0, v_x, 0.3) then
      raise exception 'The pure sevak and the pure donor part company at %.', v_x;
    end if;
  end loop;

  -- The ceiling followed the dial rather than staying where 0062 found it.
  if public.seva_mala_norm_ceiling() <> 1.3 then
    raise exception 'The per-dimension ceiling is % rather than 1 + 0.3.',
      public.seva_mala_norm_ceiling();
  end if;
  if public.seva_mala_norm_ceiling() <> 1 + v_beta then
    raise exception 'The ceiling is not 1 + balance_beta; the two can drift apart.';
  end if;
  if public.seva_mala_points(1.3) <> 1300
    or public.seva_mala_points(1.9) <> 1300
    or public.seva_mala_points(1.0) <> 1000
    or public.seva_mala_points(0.769231) <> 770
    or public.seva_mala_points(0) <> 0
    or public.seva_mala_points(0.000001) <> 10
  then
    raise exception
      'The published scale did not follow the ceiling down: 1.3 publishes %.',
      public.seva_mala_points(1.3);
  end if;

  -- 0.3 is a weight on the smaller offering and the guards still say so. A dial
  -- outside [0, 1] is the rule the temple rejected coming back through the dial.
  begin
    perform public.seva_mala_score(1.0, 1.0, 1.4);
    raise exception 'seva_mala_score accepted a beta of 1.4.';
  exception
    when others then
      if sqlstate <> 'P0001' then raise; end if;
      if position('[0, 1]' in sqlerrm) = 0 then
        raise exception 'A beta of 1.4 was refused, but not for being out of range: %', sqlerrm;
      end if;
  end;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. The congregation.
-- ---------------------------------------------------------------------------

create table public.ba_ids (key text primary key, id uuid not null);
grant select on public.ba_ids to authenticated;

do $$
declare
  v_who record;
  v_i integer := 0;
begin
  for v_who in
    select * from (values
      ('pres',   'Board President'),
      ('head',   'Community Head Das'),
      ('vol',    'Volunteer Das'),
      ('plain',  'Plain Devotee Das'),
      ('hidden', 'Hidden Das'),
      ('sevak',  'Sevak Das'),
      ('donor',  'Donor Das'),
      ('both',   'Both Das'),
      ('s1',     'S1 Das'), ('s2', 'S2 Das'), ('s3', 'S3 Das'), ('s4', 'S4 Das'),
      ('g1',     'G1 Das'), ('g2', 'G2 Das'), ('g3', 'G3 Das'), ('g4', 'G4 Das')
    ) as cast_member(key, name)
  loop
    v_i := v_i + 1;
    insert into auth.users (id, email, raw_user_meta_data)
    values (
      ('7a000000-0000-0000-0000-0000000000' || lpad(v_i::text, 2, '0'))::uuid,
      'ba-' || v_who.key || '@example.test',
      jsonb_build_object('name', v_who.name)
    );

    update public.users
    set name = v_who.name
    where users.email = 'ba-' || v_who.key || '@example.test';

    insert into public.ba_ids (key, id)
    select v_who.key, users.id
    from public.users where users.email = 'ba-' || v_who.key || '@example.test';
  end loop;
end;
$$;

update public.users users
set role_id = roles.id
from public.roles roles
where (users.email, roles.name) in (
  ('ba-pres@example.test', 'president'),
  ('ba-head@example.test', 'core'),
  ('ba-vol@example.test', 'volunteer')
);

-- One devotee opts out. Everything this file proves about the opt-out is proved
-- about this one row: the congregation must not see her, and a Community Head
-- must.
update public.users
set leaderboard_visible = (users.email <> 'ba-hidden@example.test')
where users.email like 'ba-%@example.test';

-- ---------------------------------------------------------------------------
-- 4. The facts.
--
--    Every act 180 minutes, so v_s is 180 by construction. Every gift a single
--    gift. All of it strictly before this week began, anchored on last Sunday,
--    at most two acts a day and eight a week so that nobody reaches the
--    480-minute day or the 1,800-minute week and credited minutes are served
--    minutes.
-- ---------------------------------------------------------------------------

do $$
declare
  v_type uuid;
  v_anchor date := public.seva_mala_week_start(public.seva_mala_today()) - 1;
  v_plan record;
  v_instance uuid;
  v_day date;
  v_n integer;
begin
  select service_types.id into v_type
  from public.service_types where service_types.name = 'Pot Washing';
  if v_type is null then
    raise exception 'The Pot Washing service type is missing from the seed.';
  end if;

  for v_plan in
    select * from (values
      ('sevak',  8),
      ('both',   4),
      ('s1',     6),
      ('hidden', 3),
      ('head',   2),
      ('s2',     4),
      ('s3',     2),
      ('s4',     1),
      ('vol',    1),
      ('plain',  1)
    ) as plan(who, acts)
  loop
    for v_n in 1 .. v_plan.acts loop
      v_day := v_anchor - (7 * ((v_n - 1) / 4)) - ((v_n - 1) % 4);

      insert into public.service_instances (
        service_type_id, date, start_time, duration_minutes, slots_needed,
        participation_mode, posted_by, status
      ) values (
        v_type, v_day, time '08:00' + ((v_n % 4) * interval '2 hours'),
        180, 1, 'open', null, 'completed'
      ) returning id into v_instance;

      insert into public.service_assignments (
        service_instance_id, devotee_id, assignment_method, status,
        verification, attendance, completed_at
      ) values (
        v_instance,
        (select ids.id from public.ba_ids ids where ids.key = v_plan.who),
        'self_joined', 'completed', 'member_verified', 'served',
        (v_day + time '12:00') at time zone 'America/Chicago'
      );
    end loop;
  end loop;
end;
$$;

do $$
declare
  v_anchor date := public.seva_mala_week_start(public.seva_mala_today()) - 1;
  v_gift record;
begin
  for v_gift in
    select * from (values
      ('donor',   90000),
      ('g1',      60000),
      ('both',    45000),
      ('hidden',  30000),
      ('g2',      25000),
      ('g3',      12000),
      ('g4',       4000)
    ) as gift(who, cents)
  loop
    insert into public.donations (
      donor_id, donor_name, amount_cents, kind, external_payment_id, received_at
    ) values (
      (select ids.id from public.ba_ids ids where ids.key = v_gift.who),
      v_gift.who, v_gift.cents, 'one_time', 'ba-' || v_gift.who || '-1',
      ((v_anchor - 2) + time '10:00') at time zone 'America/Chicago'
    );
  end loop;
end;
$$;

select public.recompute_seva_mala() as periods_computed;

-- The fixture is what this file thinks it is, checked before anything is
-- concluded from it. A moved median fails here and says so, rather than three
-- sections later as a wrong score.
do $$
declare
  v_period public.seva_mala_periods;
  v_weights integer;
  v_capped integer;
begin
  select * into v_period from public.seva_mala_periods where period_kind = 'lifetime';

  if v_period.seva_unit_minutes <> 180 then
    raise exception 'v_s is % rather than the 180-minute median act.', v_period.seva_unit_minutes;
  end if;
  if v_period.participant_count <> 15 then
    raise exception 'The lifetime cohort is % rather than 15.', v_period.participant_count;
  end if;
  if v_period.participant_count
     < public.seva_mala_number('seva_mala.minimum_cohort', 8) then
    raise exception 'The fixture is below the minimum cohort, so no board publishes.';
  end if;
  if v_period.frozen_at is not null then
    raise exception 'The lifetime period is frozen; it never closes.';
  end if;

  -- Credited minutes are served minutes, so the seva figures the Community Head
  -- is handed mean what section 8 says they mean.
  select count(*) into v_weights
  from public.seva_type_weights where weight <> 1.0;
  if v_weights <> 0 then
    raise exception '% service types carry a scarcity weight other than 1.0.', v_weights;
  end if;

  select count(*) into v_capped
  from public.seva_mala_acts() acts
  where acts.day_factor <> 1.0 or acts.week_factor <> 1.0;
  if v_capped <> 0 then
    raise exception '% acts in the fixture were clipped by a cap.', v_capped;
  end if;
end;
$$;

-- The lifetime period's id, put where a signed-in devotee can reach it.
-- public.seva_mala_periods is nobody's to select and stays nobody's, so the one
-- section that has to name a period from inside `set local role authenticated`
-- reads it from here rather than from a table this file is proving is closed.
insert into public.ba_ids (key, id)
select 'lifetime_period', periods.id
from public.seva_mala_periods periods
where periods.period_kind = 'lifetime';

-- ---------------------------------------------------------------------------
-- 5. THE STORED SCORES FOLLOW THE PUBLISHED FORMULA AT 0.3.
--
--    Not "seva_mala_score agrees with itself". The whole chain is re-typed here
--    from the period's own units and references, in the order 0055 §13, 0062 §3
--    and 0059 §2 publish it:
--
--        u    = ln(1 + total/unit)                       rounded at ten places
--        norm = u/ref                       for u <= ref
--             = 1 + alpha*ln(1 + (u-ref)/ref)  above it, railed at 1 + beta
--        score = (max + beta*min) / (1 + beta)           rounded at six
--
--    If 0064 had moved the dial and left the boards standing at 0.5, or moved
--    them under some other rule, this is where it shows.
-- ---------------------------------------------------------------------------

do $$
declare
  v_period public.seva_mala_periods;
  v_alpha numeric := public.seva_mala_number('seva_mala.soft_cap_alpha', 0.15);
  v_ceiling numeric := public.seva_mala_norm_ceiling();
  v_row record;
  v_us numeric;
  v_ug numeric;
  v_s numeric;
  v_g numeric;
  v_score numeric;
  v_old numeric;
  v_moved integer := 0;
  v_pure_sevak integer := 0;
  v_pure_donor integer := 0;
begin
  select * into v_period from public.seva_mala_periods where period_kind = 'lifetime';

  for v_row in
    select scores.*, users.name
    from public.period_scores scores
    join public.users on users.id = scores.devotee_id
    where scores.period_id = v_period.id
  loop
    v_us := round(ln(1 + v_row.seva_minutes / v_period.seva_unit_minutes), 10);
    v_ug := round(ln(1 + v_row.giving_cents::numeric / v_period.giving_unit_cents), 10);

    if v_us <> v_row.seva_utility or v_ug <> v_row.giving_utility then
      raise exception
        'The compression stored for % is (%, %) and re-derives as (%, %).',
        v_row.name, v_row.seva_utility, v_row.giving_utility, v_us, v_ug;
    end if;

    v_s := case
      when v_us <= 0 then 0
      when v_us <= v_period.seva_reference then round(v_us / v_period.seva_reference, 6)
      else round(least(v_ceiling,
        1 + v_alpha * ln(1 + (v_us - v_period.seva_reference) / v_period.seva_reference)), 6)
    end;
    v_g := case
      when v_ug <= 0 then 0
      when v_ug <= v_period.giving_reference then round(v_ug / v_period.giving_reference, 6)
      else round(least(v_ceiling,
        1 + v_alpha * ln(1 + (v_ug - v_period.giving_reference) / v_period.giving_reference)), 6)
    end;

    if v_s <> v_row.seva_norm or v_g <> v_row.giving_norm then
      raise exception
        'The norms stored for % are (%, %) and re-derive as (%, %).',
        v_row.name, v_row.seva_norm, v_row.giving_norm, v_s, v_g;
    end if;
    if v_s > v_ceiling or v_g > v_ceiling then
      raise exception '% is above the ceiling of % at (%, %).',
        v_row.name, v_ceiling, v_s, v_g;
    end if;

    -- The balance, at 0.3, re-typed.
    v_score := round((greatest(v_s, v_g) + 0.3 * least(v_s, v_g)) / 1.3, 6);
    if v_score <> v_row.score then
      raise exception
        'The stored score for % is % and the published formula at beta 0.3 gives %.',
        v_row.name, v_row.score, v_score;
    end if;

    -- AND IT IS NOT 0.5's NUMBER. For anybody whose two offerings differ, the
    -- old rule gives a different answer, so this is the assertion that the
    -- boards actually moved rather than merely being consistent with themselves.
    v_old := round((greatest(v_s, v_g) + 0.5 * least(v_s, v_g)) / 1.5, 6);
    if v_s <> v_g then
      if v_row.score = v_old then
        raise exception
          '%''s score of % is still the number beta = 0.5 would have given.',
          v_row.name, v_row.score;
      end if;
      v_moved := v_moved + 1;
    end if;

    -- The two archetypes, each doing exactly what 0.3 says they should: the
    -- whole of their one offering, over 1.3.
    if v_g = 0 and v_s > 0 then
      if v_row.score <> round(v_s / 1.3, 6) then
        raise exception 'The pure sevak % scores % rather than s-hat/1.3.',
          v_row.name, v_row.score;
      end if;
      v_pure_sevak := v_pure_sevak + 1;
    end if;
    if v_s = 0 and v_g > 0 then
      if v_row.score <> round(v_g / 1.3, 6) then
        raise exception 'The pure donor % scores % rather than g-hat/1.3.',
          v_row.name, v_row.score;
      end if;
      v_pure_donor := v_pure_donor + 1;
    end if;
  end loop;

  if v_moved < 10 then
    raise exception
      'Only % devotees have unequal offerings; the "not 0.5''s number" check is nearly vacuous.',
      v_moved;
  end if;
  if v_pure_sevak < 5 or v_pure_donor < 3 then
    raise exception
      'The fixture holds % pure sevaks and % pure donors; the archetypes are not being exercised.',
      v_pure_sevak, v_pure_donor;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. THE RECOMPUTE RULE: what already exists and is not frozen, and nothing
--    else.
--
--    A frozen period is built by hand with a score nobody could have computed,
--    and every open period has its scores corrupted. Then the function the
--    migration itself called is called again, and the two halves of 0059 §7 are
--    checked separately: the open boards came back, the frozen one did not
--    move, and no period was created.
-- ---------------------------------------------------------------------------

do $$
declare
  v_frozen_period uuid;
  v_frozen_start date := public.seva_mala_week_start(public.seva_mala_today() - 28);
begin
  insert into public.seva_mala_periods (
    period_kind, starts_on, ends_on, seva_reference, giving_reference,
    seva_unit_minutes, giving_unit_cents, participant_count, computed_at, frozen_at
  ) values (
    'week', v_frozen_start, v_frozen_start + 6, 1.0, 1.0, 180, 25000, 1,
    timestamptz '2026-01-01 00:00:00+00', timestamptz '2026-01-01 00:00:00+00'
  ) returning id into v_frozen_period;

  insert into public.period_scores (period_id, devotee_id, score)
  select v_frozen_period, ids.id, 9.999999
  from public.ba_ids ids where ids.key = 'sevak';
end;
$$;

do $$
declare
  v_periods_before integer;
  v_periods_after integer;
  v_open_before integer;
  v_returned integer;
  v_frozen record;
  v_lifetime uuid;
  v_wrong integer;
  v_row record;
  v_score numeric;
begin
  select count(*) into v_periods_before from public.seva_mala_periods;
  select count(*) into v_open_before
  from public.seva_mala_periods
  where frozen_at is null and starts_on <= public.seva_mala_today();

  select id into v_lifetime from public.seva_mala_periods where period_kind = 'lifetime';

  -- Every open board, wrecked.
  update public.period_scores
  set score = 8.888888, seva_norm = 8.888888, giving_norm = 8.888888
  from public.seva_mala_periods periods
  where periods.id = period_scores.period_id
    and periods.frozen_at is null;

  v_returned := public.recompute_open_seva_mala_periods();

  if v_returned <> v_open_before then
    raise exception
      'The recompute touched % periods; % were open and unfrozen.',
      v_returned, v_open_before;
  end if;

  -- NOTHING WAS CREATED. This is the half of 0059 §7 that a careless
  -- implementation loses: ensure_seva_mala_period would have made last week and
  -- last month here and frozen them empty.
  select count(*) into v_periods_after from public.seva_mala_periods;
  if v_periods_after <> v_periods_before then
    raise exception
      'The recompute created % period(s). It must find periods, never make them.',
      v_periods_after - v_periods_before;
  end if;

  -- THE OPEN BOARDS CAME BACK, and came back under the published formula at
  -- 0.3 rather than merely stopping being 8.888888.
  select count(*) into v_wrong
  from public.period_scores scores
  join public.seva_mala_periods periods on periods.id = scores.period_id
  where periods.frozen_at is null and scores.score = 8.888888;
  if v_wrong > 0 then
    raise exception '% rows of an open board were left at the wrecked score.', v_wrong;
  end if;

  for v_row in
    select scores.* from public.period_scores scores
    where scores.period_id = v_lifetime
  loop
    v_score := round(
      (greatest(v_row.seva_norm, v_row.giving_norm)
       + 0.3 * least(v_row.seva_norm, v_row.giving_norm)) / 1.3, 6);
    if v_score <> v_row.score then
      raise exception
        'A rebuilt lifetime row scores % where the formula at 0.3 gives %.',
        v_row.score, v_score;
    end if;
  end loop;

  -- AND THE FROZEN PERIOD DID NOT MOVE. Not its scores, not its computed_at,
  -- not its frozen_at. A frozen September was second under September's rule and
  -- stays second under it.
  select periods.computed_at, periods.frozen_at, scores.score
  into v_frozen
  from public.seva_mala_periods periods
  join public.period_scores scores on scores.period_id = periods.id
  where periods.frozen_at is not null;

  if v_frozen.score <> 9.999999 then
    raise exception
      'The frozen period was recomputed: its score is now % rather than the 9.999999 nobody could have computed.',
      v_frozen.score;
  end if;
  if v_frozen.computed_at <> timestamptz '2026-01-01 00:00:00+00'
    or v_frozen.frozen_at <> timestamptz '2026-01-01 00:00:00+00' then
    raise exception 'The frozen period was rewritten: computed_at is now %.',
      v_frozen.computed_at;
  end if;
end;
$$;

-- The recompute is the temple's schedule's and nobody else's. The grant is
-- checked in section 0; this reaches PAST the grant, by handing it to
-- authenticated for three statements, so that the guard INSIDE the function is
-- what refuses rather than the privilege outside it.
do $$
declare
  v_caught boolean := false;
begin
  grant execute on function public.recompute_open_seva_mala_periods() to authenticated;

  perform set_config('request.jwt.claim.sub',
    (select ids.id::text from public.ba_ids ids where ids.key = 'pres'), true);
  perform set_config('role', 'authenticated', true);

  begin
    perform public.recompute_open_seva_mala_periods();
  exception
    when others then
      if sqlstate <> 'P0001' then raise; end if;
      v_caught := true;
  end;

  perform set_config('role', 'none', true);
  revoke execute on function public.recompute_open_seva_mala_periods() from authenticated;

  if not v_caught then
    raise exception
      'A signed-in caller with the grant ran the recompute; is_backend_caller is not guarding it.';
  end if;
end;
$$;

-- And a bad dial costs the boards nothing. The refusal has to come from the
-- recompute rather than from seva_mala_score, or a period has already been half
-- rebuilt before anybody objected.
do $$
declare
  v_caught boolean := false;
  v_wrecked integer;
begin
  update public.app_settings set value = '2' where key = 'seva_mala.balance_beta';
  begin
    perform public.recompute_open_seva_mala_periods();
  exception
    when others then
      if sqlstate <> 'P0001' then raise; end if;
      if position('seva_mala.balance_beta' in sqlerrm) = 0 then
        raise exception
          'A beta of 2 was refused, but not by the recompute''s own guard: %', sqlerrm;
      end if;
      v_caught := true;
  end;
  update public.app_settings set value = '0.3' where key = 'seva_mala.balance_beta';

  if not v_caught then
    raise exception 'The recompute accepted a beta of 2 and re-scored the congregation.';
  end if;

  select count(*) into v_wrecked from public.period_scores where score = 8.888888;
  if v_wrecked > 0 then
    raise exception 'A refused recompute left % half-written rows behind.', v_wrecked;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. What the President still sees, which is everything.
--
--    Checked first, so that section 8's nulls are known to be a decision about
--    the Community Head rather than a board that has stopped working.
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.ba_ids ids where ids.key = 'pres'), true);

do $$
declare
  v_rows integer;
  v_hidden integer;
  v_null integer;
  v_row record;
begin
  select count(*), count(*) filter (where board.is_hidden)
  into v_rows, v_hidden
  from public.list_all_seva_scores('lifetime') board;

  if v_rows <> 15 then
    raise exception 'The President sees % devotees rather than all fifteen.', v_rows;
  end if;
  if v_hidden <> 1 then
    raise exception 'The President sees % devotees flagged as hidden rather than one.', v_hidden;
  end if;

  select count(*) into v_null
  from public.list_all_seva_scores('lifetime') board
  where board.score is null or board.giving_cents is null or board.gifts is null
     or board.seva_norm is null or board.giving_norm is null
     or board.points is null or board.seva_minutes is null or board.seva_acts is null;
  if v_null > 0 then
    raise exception '% of the President''s rows are missing a column.', v_null;
  end if;

  select count(*) into v_null
  from public.list_all_seva_scores('lifetime') board
  where board.giving_withheld;
  if v_null > 0 then
    raise exception 'The President is told giving was withheld on % rows.', v_null;
  end if;

  -- The devotee who opted out is there, named, and flagged.
  select count(*) into v_hidden
  from public.list_all_seva_scores('lifetime') board
  join public.ba_ids ids on ids.id = board.devotee_id
  where ids.key = 'hidden' and board.is_hidden;
  if v_hidden <> 1 then
    raise exception 'The devotee who opted out is not flagged to the President.';
  end if;

  -- The ranking is a ranking. The best score stands first, standing never
  -- rises as the score falls, and two devotees who are genuinely level share a
  -- place — which is what 0055's dense_rank is for and what 0059 rounds the
  -- score to six places to make possible.
  select count(*) into v_null
  from (
    select board.standing, board.score,
           lag(board.standing) over (order by board.score desc) as prev_standing,
           lag(board.score) over (order by board.score desc) as prev_score
    from public.list_all_seva_scores('lifetime') board
  ) ordered
  where ordered.prev_standing is not null
    and (
      ordered.standing < ordered.prev_standing
      or (ordered.score = ordered.prev_score
          and ordered.standing <> ordered.prev_standing)
    );
  if v_null > 0 then
    raise exception
      '% rows are out of order: the board is not ranked by the score it is ordered by.',
      v_null;
  end if;

  select min(board.standing) into v_null from public.list_all_seva_scores('lifetime') board;
  if v_null <> 1 then
    raise exception 'The top of the board stands % rather than first.', v_null;
  end if;

  -- The published points on this board are the published points, so the
  -- President and the congregation are looking at the same number.
  for v_row in select * from public.list_all_seva_scores('lifetime') loop
    if v_row.points <> public.seva_mala_points(v_row.score) then
      raise exception 'A row scores % and publishes % points.', v_row.score, v_row.points;
    end if;
    if v_row.points > 1300 then
      raise exception 'A row publishes % points, above the ceiling of 1300.', v_row.points;
    end if;
  end loop;
end;
$$;

reset role;

-- The President's board, kept so that section 8 can hold the Community Head's
-- beside it row for row. Still the President's uid — only the role is dropped,
-- because `authenticated` may not create a table and this is a snapshot rather
-- than an assertion.
create table public.ba_president_board as
select board.devotee_id, board.standing, board.points, board.seva_minutes,
       board.seva_acts, board.is_hidden, board.score
from public.list_all_seva_scores('lifetime') board;

grant select on public.ba_president_board to authenticated;

select set_config('request.jwt.claim.sub', '', true);

do $$
declare
  v_rows integer;
begin
  select count(*) into v_rows from public.ba_president_board;
  if v_rows <> 15 then
    raise exception
      'The snapshot of the President''s board holds % rows rather than fifteen.', v_rows;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. WHAT A COMMUNITY HEAD SEES.
--
--    The same board, the same order, the same standings, the same points, the
--    same seva figures, and the same devotees — including the one who opted out.
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.ba_ids ids where ids.key = 'head'), true);

do $$
declare
  v_rows integer;
  v_hidden integer;
  v_bad integer;
begin
  if not public.may_view_whole_seva_board() then
    raise exception 'A Community Head is not on the whole board.';
  end if;
  if public.may_view_all_giving() then
    raise exception 'A Community Head may view all giving; every negative below is vacuous.';
  end if;

  select count(*), count(*) filter (where board.is_hidden)
  into v_rows, v_hidden
  from public.list_all_seva_scores('lifetime') board;

  if v_rows <> 15 then
    raise exception 'A Community Head sees % devotees rather than all fifteen.', v_rows;
  end if;
  if v_hidden <> 1 then
    raise exception
      'A Community Head sees % devotees flagged as hidden rather than one.', v_hidden;
  end if;

  -- THE DEVOTEE WHO OPTED OUT IS VISIBLE TO THEM, which is the sentence the
  -- temple said and the whole reason this change exists.
  select count(*) into v_hidden
  from public.list_all_seva_scores('lifetime') board
  join public.ba_ids ids on ids.id = board.devotee_id
  where ids.key = 'hidden' and board.is_hidden;
  if v_hidden <> 1 then
    raise exception
      'The devotee who opted out is missing from the Community Head''s board, or is not flagged.';
  end if;

  -- IT IS THE SAME BOARD, not a second one that could drift: every standing,
  -- every point, every minute and every act agrees with the President's row for
  -- the same devotee.
  select count(*) into v_bad
  from public.list_all_seva_scores('lifetime') board
  full outer join public.ba_president_board pres
    on pres.devotee_id = board.devotee_id
  where board.devotee_id is null
     or pres.devotee_id is null
     or board.standing is distinct from pres.standing
     or board.points is distinct from pres.points
     or board.seva_minutes is distinct from pres.seva_minutes
     or board.seva_acts is distinct from pres.seva_acts
     or board.is_hidden is distinct from pres.is_hidden;
  if v_bad > 0 then
    raise exception
      '% rows of the Community Head''s board disagree with the President''s.', v_bad;
  end if;

  -- AND THE FIVE COLUMNS THAT INVERT ARE NULL ON EVERY ROW. Not rounded, not
  -- zeroed — absent. score and seva_norm are in this list because the two of
  -- them together give giving_norm back exactly, and giving_norm gives back the
  -- gift.
  select count(*) into v_bad
  from public.list_all_seva_scores('lifetime') board
  where board.score is not null
     or board.giving_cents is not null
     or board.gifts is not null
     or board.seva_norm is not null
     or board.giving_norm is not null;
  if v_bad > 0 then
    raise exception
      '% rows hand a Community Head an exact score, a component or a dollar figure.',
      v_bad;
  end if;

  -- And they are told so, on every row, so a null is never read as a zero.
  select count(*) into v_bad
  from public.list_all_seva_scores('lifetime') board
  where not board.giving_withheld;
  if v_bad > 0 then
    raise exception
      '% rows tell a Community Head that nothing was withheld from them.', v_bad;
  end if;

  -- The seva figures they DO get are real. A rota runner has reason to know who
  -- is serving; the fixture's biggest sevak served eight 180-minute acts.
  select count(*) into v_bad
  from public.list_all_seva_scores('lifetime') board
  join public.ba_ids ids on ids.id = board.devotee_id
  where ids.key = 'sevak'
    and (board.seva_minutes <> 1440 or board.seva_acts <> 8 or board.points is null);
  if v_bad <> 0 then
    raise exception 'The Community Head cannot see that the pure sevak served 1,440 minutes.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 9. WHAT A COMMUNITY HEAD DOES NOT SEE.
--
--    Still the Community Head, still under `set local role authenticated`. Every
--    one of these is app.view_all's and stays app.view_all's: the giving, the
--    per-act history, and Seva Care.
-- ---------------------------------------------------------------------------

do $$
declare
  v_count integer;
  v_case record;
  v_sevak text := '(select ids.id from public.ba_ids ids where ids.key = ''sevak'')';
  v_donor text := '(select ids.id from public.ba_ids ids where ids.key = ''donor'')';
begin
  for v_case in
    select * from (values
      -- The giving reads. 0048 §4 settled who may see the temple's giving and
      -- 0064 does not reopen it.
      ('list_all_donations(date, date, uuid)',
       'select count(*) from public.list_all_donations(null::date, null::date, null::uuid)'),
      ('donation_totals(date, date, uuid)',
       'select count(*) from public.donation_totals(null::date, null::date, null::uuid)'),
      ('list_all_sponsorships(boolean)',
       'select count(*) from public.list_all_sponsorships(true)'),
      ('list_devotee_giving_points(uuid, date, date)',
       'select count(*) from public.list_devotee_giving_points(' || v_donor
       || ', null::date, null::date)'),
      -- One devotee's history, act by act. A board is a board; a file on a
      -- devotee is not, and the temple did not ask for one.
      ('list_devotee_seva_acts(uuid, date, date)',
       'select count(*) from public.list_devotee_seva_acts(' || v_sevak
       || ', null::date, null::date)'),
      ('list_devotee_seva_act_points(uuid, date, date)',
       'select count(*) from public.list_devotee_seva_act_points(' || v_sevak
       || ', null::date, null::date)'),
      -- SEVA CARE. 202608040058 §1: a rota is a reason to know who is free, not
      -- a reason to be handed a reading of another devotee's tiredness. The
      -- temple asked for this one separately and it did not move.
      ('list_seva_concentration(integer, numeric)',
       'select count(*) from public.list_seva_concentration(null::integer, null::numeric)'),
      ('list_seva_narrowness(numeric)',
       'select count(*) from public.list_seva_narrowness(null::numeric)'),
      ('seva_balance_for_devotee(uuid)',
       'select count(*) from public.seva_balance_for_devotee(' || v_sevak || ')'),
      ('seva_balance_thresholds()',
       'select count(*) from public.seva_balance_thresholds()')
    ) as forbidden(signature, statement)
  loop
    -- Named rather than caught: a misspelled function would otherwise raise,
    -- be swallowed as a refusal, and pass for ever.
    if to_regprocedure('public.' || v_case.signature) is null then
      raise exception 'public.% does not exist; this negative proves nothing.',
        v_case.signature;
    end if;

    begin
      execute v_case.statement into v_count;
    exception
      when insufficient_privilege then
        v_count := 0;
      when others then
        -- A refusal that arrives as an error is a refusal too, but only a
        -- deliberate one: anything but the feature's own raise is a real bug.
        if sqlstate <> 'P0001' then raise; end if;
        v_count := 0;
    end;

    if v_count <> 0 then
      raise exception
        'A Community Head read % rows out of public.%.', v_count, v_case.signature;
    end if;
  end loop;

  -- The tables themselves, not just the doors onto them.
  for v_case in
    select * from (values
      ('period_scores',     'select count(*) from public.period_scores'),
      ('seva_mala_periods', 'select count(*) from public.seva_mala_periods'),
      ('app_settings',      'select count(*) from public.app_settings'),
      ('donations',         'select count(*) from public.donations')
    ) as forbidden(signature, statement)
  loop
    begin
      execute v_case.statement into v_count;
    exception
      when insufficient_privilege then
        v_count := 0;
    end;
    if v_count <> 0 then
      raise exception 'A Community Head read % rows of public.%.', v_count, v_case.signature;
    end if;
  end loop;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);

-- ---------------------------------------------------------------------------
-- 10. The ordinary devotee, and the volunteer.
--
--     Nothing about either of them changed, and that is the point: the opt-out
--     still works against the congregation, and the gate is the permission
--     rather than seniority.
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.ba_ids ids where ids.key = 'plain'), true);

do $$
declare
  v_count integer;
  v_hidden integer;
begin
  if public.may_view_whole_seva_board() then
    raise exception 'An ordinary devotee is on the whole board.';
  end if;

  select count(*) into v_count from public.list_all_seva_scores('lifetime');
  if v_count <> 0 then
    raise exception
      'An ordinary devotee read % rows of the whole board.', v_count;
  end if;

  -- The garland is still the opted-in devotees and only them, and the devotee
  -- who opted out cannot be found on it under any mode.
  select count(*) into v_hidden
  from public.list_seva_garland('lifetime', 200, 'combined') board
  join public.ba_ids ids on ids.id = board.devotee_id
  where ids.key = 'hidden';
  if v_hidden <> 0 then
    raise exception 'The devotee who opted out is on the public combined garland.';
  end if;

  select count(*) into v_hidden
  from public.list_seva_garland('lifetime', 200, 'seva') board
  join public.ba_ids ids on ids.id = board.devotee_id
  where ids.key = 'hidden';
  if v_hidden <> 0 then
    raise exception 'The devotee who opted out is on the public seva garland.';
  end if;

  select count(*) into v_hidden
  from public.list_seva_supporters('lifetime') supporters
  join public.ba_ids ids on ids.id = supporters.devotee_id
  where ids.key = 'hidden';
  if v_hidden <> 0 then
    raise exception 'The devotee who opted out is on the public supporters list.';
  end if;

  -- Fourteen of the fifteen opted in, and the board publishes all fourteen.
  select count(*) into v_count
  from public.list_seva_garland('lifetime', 200, 'combined') board
  where not board.gathering;
  if v_count <> 14 then
    raise exception
      'The public garland shows % devotees rather than the fourteen who opted in.', v_count;
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);

set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.ba_ids ids where ids.key = 'vol'), true);

do $$
declare
  v_count integer;
begin
  -- A Volunteer holds services.post_requirement and services.resolve_coverage
  -- and does NOT hold services.manage_recurring. The gate is the key, not the
  -- rank.
  if public.may_view_whole_seva_board() then
    raise exception 'A Volunteer is on the whole board.';
  end if;
  select count(*) into v_count from public.list_all_seva_scores('lifetime');
  if v_count <> 0 then
    raise exception 'A Volunteer read % rows of the whole board.', v_count;
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);

-- ---------------------------------------------------------------------------
-- 11. The gate is the permission, proved by moving one devotee across it.
--
--     The plain devotee, who saw nothing three sections ago, is made a Community
--     Head and sees the whole board — same nulls, same flag. Nothing about the
--     devotee changed but the key they hold.
-- ---------------------------------------------------------------------------

update public.users
set role_id = (select roles.id from public.roles where roles.name = 'core')
where users.email = 'ba-plain@example.test';

set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.ba_ids ids where ids.key = 'plain'), true);

do $$
declare
  v_count integer;
  v_bad integer;
begin
  select count(*) into v_count from public.list_all_seva_scores('lifetime');
  if v_count <> 15 then
    raise exception
      'The newly appointed Community Head sees % devotees rather than fifteen.', v_count;
  end if;

  select count(*) into v_bad
  from public.list_all_seva_scores('lifetime') board
  where board.score is not null or board.giving_cents is not null
     or board.seva_norm is not null or board.giving_norm is not null
     or board.gifts is not null or not board.giving_withheld;
  if v_bad > 0 then
    raise exception
      'The newly appointed Community Head was handed a component or a dollar figure on % rows.',
      v_bad;
  end if;

  -- Their OWN numbers are still their own and are still complete: the withheld
  -- columns are a statement about other devotees, not a devotee being kept from
  -- their own working.
  select count(*) into v_count
  from public.my_seva_mala('lifetime');
  if v_count <> 1 then
    raise exception 'A Community Head reading their own standing got % rows.', v_count;
  end if;
end;
$$;

do $$
declare
  v_period uuid;
  v_rows integer;
  v_beta numeric;
begin
  select ids.id into v_period from public.ba_ids ids where ids.key = 'lifetime_period';

  select count(*) into v_rows from public.explain_my_score(v_period);
  if v_rows <> 1 then
    raise exception 'A Community Head cannot see the working behind their own score.';
  end if;

  select working.balance_beta into v_beta from public.explain_my_score(v_period) working;
  if v_beta <> 0.3 then
    raise exception 'The devotee is shown a beta of % rather than 0.3.', v_beta;
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);

-- ---------------------------------------------------------------------------
-- 12. THE MIGRATION ITSELF, APPLIED A SECOND TIME.
--
--     Everything above tests the state 0064 left behind. This tests the file.
--     It is included from disk — not re-typed, not paraphrased — and applied
--     again over a temple that has, in the meantime, done two things:
--
--       * moved the balance dial off 0.3, to 0.4, which is a President
--         exercising the dial 0055 §1 promised them;
--       * accumulated open boards, which this section wrecks first so that
--         "the migration recomputes" is a fact and not an inference.
--
--     Three properties fall out of one include, and none of them can be proved
--     any other way:
--
--       THE CORRECTION IS ONE-TIME. The dial is still 0.4 afterwards. An
--       unguarded UPDATE would have stamped 0.3 back over the temple's number
--       and taken the dial away from the people it belongs to.
--
--       THE MIGRATION RECOMPUTES. The wrecked open boards come back, so the
--       recompute is something the file does rather than something the
--       verification did for it in section 6.
--
--       AND IT STILL CREATES NOTHING. Not on the second application either,
--       when there are periods to be tempted by and last week is behind us.
-- ---------------------------------------------------------------------------

update public.app_settings
set value = '0.4'
where key = 'seva_mala.balance_beta';

update public.period_scores
set score = 7.777777
from public.seva_mala_periods periods
where periods.id = period_scores.period_id
  and periods.frozen_at is null;

create table public.ba_before_reapply as
select
  (select count(*) from public.seva_mala_periods) as periods,
  (select count(*) from public.period_scores where score = 7.777777) as wrecked;

\ir ../migrations/202608040064_board_access_and_beta.sql

do $$
declare
  v_before record;
  v_beta numeric;
  v_periods integer;
  v_wrecked integer;
  v_frozen numeric;
begin
  select * into v_before from public.ba_before_reapply;

  if v_before.wrecked = 0 then
    raise exception 'The re-application test wrecked nothing, so it proves nothing.';
  end if;

  v_beta := public.seva_mala_number('seva_mala.balance_beta', 0.5);
  if v_beta <> 0.4 then
    raise exception
      'Re-applying the migration moved the dial the temple had set to 0.4 to %. The correction is a standing instruction rather than a one-time one, and the dial is no longer the temple''s.',
      v_beta;
  end if;

  select count(*) into v_periods from public.seva_mala_periods;
  if v_periods <> v_before.periods then
    raise exception
      'Re-applying the migration changed the number of periods from % to %.',
      v_before.periods, v_periods;
  end if;

  select count(*) into v_wrecked from public.period_scores where score = 7.777777;
  if v_wrecked > 0 then
    raise exception
      '% wrecked rows survived the migration; it does not recompute the open boards, so the temple would not see a moved dial until the nightly job ran.',
      v_wrecked;
  end if;

  select scores.score into v_frozen
  from public.period_scores scores
  join public.seva_mala_periods periods on periods.id = scores.period_id
  where periods.frozen_at is not null;
  if v_frozen <> 9.999999 then
    raise exception
      'The migration recomputed the frozen period; its score is now %.', v_frozen;
  end if;
end;
$$;

do $$
begin
  raise notice 'all board access and beta checks passed';
end;
$$;

select 'board access and beta verification passed' as result;

rollback;
