-- Functional verification for 202608040062_fair_scaling.sql.
--
-- Rolled back at the end. Every local is prefixed v_ so it can never shadow a
-- column name. Anything a devotee could really attempt is attempted as that
-- devotee, under `set local role authenticated`, so the grants, the row level
-- security and the permission checks are what is being tested rather than
-- superuser rights waving everything through.
--
-- 0062 does two things and this file exists to prove both, and to prove that
-- everything 0055 and 0059 built underneath them is still standing.
--
--   1. THE HARD CAP BECAME SOFT. least(1, u/ref) becomes u/ref below the
--      congregation's reference and 1 + alpha*ln(u/ref) above it, alpha = 0.15,
--      railed at 1 + beta = 1.5. So $2,500 and $600 stop being the same number,
--      and the ratio between them is compressed rather than linear.
--
--   2. A DEVOTEE CAN SEE WHERE THEIR POINTS CAME FROM. my_seva_act_points and
--      my_giving_points attribute the window's points across the acts and the
--      gifts that made them, as SHARES of a non-linear total, summing to the
--      whole exactly, with the honest sentence travelling in the rows.
--
-- ---------------------------------------------------------------------------
-- The fixture is arithmetic, not decoration.
--
-- Thirty-three devotees in the scoring cohort, which is four times 0055's
-- minimum of eight, so every congregation-relative reference here is a real
-- percentile of a real congregation. The two units and the two references fall
-- out by construction and nothing depends on a median nobody can check:
--
--   v_s = 180 minutes    sixteen of the seventeen servers do 180-minute acts,
--                        so the median of the per-devotee medians is 180
--   v_g = 25,000 cents   the eighteen donors' per-donor medians have $250 in
--                        both middle positions
--   ref_s = ln(6)     = 1.7917594692   the P80 server's 900 weighted minutes
--   ref_g = ln(2.8) = 1.0296194172   the P80 donor's $450 total
--
-- Both percentiles land exactly on a devotee rather than between two, which is
-- what makes every number below exact rather than nearly right. Everything sits
-- strictly BEFORE the current Chicago week begins, anchored on last Sunday, so
-- the script is deterministic on any day of any week: the lifetime period always
-- holds the whole fixture and is the board every assertion is made against, and
-- the running week always holds none of it.
--
-- THE GIVING SIDE, u_g = ln(1 + G/25000), and what each gift is now worth:
--
--   gift      u_g        u/ref     OLD norm   NEW norm   score     board points
--   ---------------------------------------------------------------------------
--   $100      0.336472   0.326793  0.326793   0.326793   0.217862      220
--   $450      1.029619   1.000000  1.000000   1.000000   0.666667      670
--   $600      1.223775   1.188571  1.000000   1.025913   0.683942      680
--   $1,710    2.059239   2.000000  1.000000   1.103972   0.735981      740
--   $2,500    2.397895   2.328914  1.000000   1.126810   0.751207      750
--
-- The three rows in the middle are the temple's complaint and its answer: under
-- 0055 a $600 gift and a $2,500 gift both cleared the eightieth percentile, both
-- were held at exactly 1.000000, and both published exactly 670 points. They now
-- publish 680 and 750. Four and a sixth times the money buys 1.098 times the
-- points, which is meaningfully more and is nowhere near twice as much.
--
-- THE SEVA SIDE is the same function of the same shape, because normalise() is a
-- function of u/ref and cannot tell which dimension it is in:
--
--   minutes   u_s        u/ref     OLD norm   NEW norm
--   ----------------------------------------------------
--   180       0.693147   0.386853  0.386853   0.386853
--   480       1.299283   0.725144  0.725144   0.725144
--   900       1.791759   1.000000  1.000000   1.000000
--   2,700     2.772589   1.547411  1.000000   1.065488
--   6,300     3.583519   2.000000  1.000000   1.103972
--
-- THE ARCHETYPES, which is where the two tables meet:
--
--   sevak_ref   900 minutes, nothing given    s=1.000000 g=0        0.666667
--   donor_ref   $450, no time to serve        s=0        g=1.000000 0.666667
--   sevak_two   6,300 minutes, nothing given  s=1.103972 g=0        0.735981
--   donor_two   $1,710, no time to serve      s=0        g=1.103972 0.735981
--   both_ref    900 minutes AND $450          s=1.000000 g=1.000000 1.000000
--
-- Two pairs, equal to the sixth decimal place: one at the congregation's
-- reference and one at exactly twice it, so the equality is proved where the
-- soft cap is doing nothing and again where it is doing all its work. And
-- both_ref, who merely reached the reference in both dimensions, beats every
-- single-dimension devotee in the fixture including the $2,500 donor. That is
-- the sentence the ceiling exists to keep true.
--
-- THE ATTRIBUTION FIXTURE is one devotee, `mixed`, built so the shares are not
-- all equal and the arithmetic can be checked by eye:
--
--   four acts   60, 120 and 300 counted minutes, and a 90-minute act marked
--               ABSENT which is listed, is worth zero, and says why
--   three gifts $50, $150 and $250
--
--   s = 0.725144   g = 1.000000   score 0.908381   =>  908 points
--   giving is the larger, so it carries the whole weight and seva carries beta:
--     seva_points  = round(1000 * 0.5*0.725144/1.5)  = 242
--     giving_points = 908 - 242                      = 666
--   the four acts take 30, 61, 151 and 0 of those 242
--   the three gifts take 74, 222 and 370 of those 666
--
-- The cast:
--   sevak_ref   900 min                the seva archetype at the reference
--   sevak_two   6,300 min              at exactly twice it
--   sevak_mid   2,700 min              between the two
--   s_extra     900 min                the third devotee at the P80, so the
--                                      percentile lands on a devotee
--   s01..s11    720 down to 180 min    the body of the congregation
--   mixed       480 min and $450       the attribution fixture
--   both_ref    900 min and $450       first outright, at 1.000000
--   donor_ref   $450                   the giving archetype at the reference
--   donor_two   $1,710                 at exactly twice it
--   donor_big   $2,500                 the temple's question
--   donor_mid   $600                   the other half of the temple's question
--   donor_small $100                   below the reference, and unmoved by any
--                                      of this
--   g01..g11    $25 to $400            the body of the congregation
--   pres        nothing                app.view_all
--   whale1..5   $2,500 each            arrive in section 10 and drag the
--                                      congregation's eightieth percentile up
--                                      with them
--
-- The final row must read: fair scaling verification passed

begin;

-- ---------------------------------------------------------------------------
-- THE BALANCE DIAL, PINNED TO THE VALUE THIS FILE'S ARITHMETIC WAS DERIVED AT.
--
-- 202608040064 carried the temple's decision to move seva_mala.balance_beta
-- from 0.5 to 0.3. Every expected score, norm, ceiling and published point in
-- this file was derived at 0.5, which is what the migration it verifies
-- shipped with and what that migration was proved at, and re-deriving them at
-- 0.3 would not check that migration again — it would replace the record of
-- what it was checked against.
--
-- So the dial is set back for the length of this transaction and rolled back
-- with everything else in it. The ground check below still runs, and still
-- fails loudly if any OTHER dial has moved. That the deployed dial is 0.3, and
-- that the stored scores follow the published formula at 0.3, is proved in
-- board_access_and_beta.sql.
-- ---------------------------------------------------------------------------

update public.app_settings
set value = '0.5'
where key = 'seva_mala.balance_beta';

-- ---------------------------------------------------------------------------
-- 0. The ground.
--
--    The dials this file's arithmetic is a function of, the rules 0062 claims
--    to have left alone, and the grants it claims not to have widened.
-- ---------------------------------------------------------------------------

do $$
declare
  v_expected text;
  v_actual text;
begin
  for v_expected, v_actual in
    select expected.key || '=' || expected.value,
           expected.key || '=' || coalesce(settings.value, '(absent)')
    from (values
      ('seva_mala.balance_beta', '0.5'),
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

  -- 0059's balance rule, untouched. The ceiling is derived from it.
  if public.seva_mala_score(1.0, 0.0, 0.5) <> 0.666667
    or public.seva_mala_score(0.0, 1.0, 0.5) <> 0.666667
    or public.seva_mala_score(1.0, 1.0, 0.5) <> 1.000000
  then
    raise exception 'The balance rule is not 202608040059''s.';
  end if;

  -- 0055 section 4, in the part nothing here reverses.
  if has_table_privilege('authenticated', 'public.period_scores', 'select')
    or has_table_privilege('authenticated', 'public.seva_mala_periods', 'select')
    or has_table_privilege('authenticated', 'public.app_settings', 'select')
    or has_table_privilege('authenticated', 'public.donations', 'select')
  then
    raise exception 'authenticated can read the Seva Mala components or the amounts.';
  end if;

  -- The engine under both pairs of lists takes a devotee id and is therefore
  -- nobody's to call.
  if has_function_privilege('authenticated', 'public.seva_mala_window_points(uuid, date, date)', 'execute')
    or has_function_privilege('anon', 'public.seva_mala_window_points(uuid, date, date)', 'execute')
  then
    raise exception
      'seva_mala_window_points takes a devotee id and is executable by a client role.';
  end if;

  -- No new door is open to a signed-out visitor.
  if has_function_privilege('anon', 'public.my_seva_act_points(date, date)', 'execute')
    or has_function_privilege('anon', 'public.my_giving_points(date, date)', 'execute')
    or has_function_privilege('anon', 'public.list_devotee_seva_act_points(uuid, date, date)', 'execute')
    or has_function_privilege('anon', 'public.list_devotee_giving_points(uuid, date, date)', 'execute')
    or has_function_privilege('anon', 'public.seva_mala_normalise(numeric, numeric, numeric, numeric)', 'execute')
    or has_function_privilege('anon', 'public.seva_mala_norm_ceiling()', 'execute')
  then
    raise exception 'A signed-out visitor can read the new Seva Mala functions.';
  end if;

  -- And all four lists are open to any signed-in devotee.
  if not has_function_privilege('authenticated', 'public.my_seva_act_points(date, date)', 'execute')
    or not has_function_privilege('authenticated', 'public.my_giving_points(date, date)', 'execute')
    or not has_function_privilege('authenticated', 'public.list_devotee_seva_act_points(uuid, date, date)', 'execute')
    or not has_function_privilege('authenticated', 'public.list_devotee_giving_points(uuid, date, date)', 'execute')
  then
    raise exception 'A devotee cannot read the lists 0062 exists to serve.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 1. The signatures, and the two shapes that must match column for column.
--
--    0061 section 8's rule: the President's variant renders in the same client
--    component as the devotee's own, so the two return types must be identical
--    apart from the argument.
-- ---------------------------------------------------------------------------

do $$
declare
  v_shape text;
  v_mine text;
  v_theirs text;
begin
  for v_shape, v_mine in
    select expected.name, coalesce(
      (select pg_get_function_identity_arguments(proc.oid)
       from pg_proc proc
       join pg_namespace spaces on spaces.oid = proc.pronamespace
       where spaces.nspname = 'public' and proc.proname = expected.name), '(missing)')
    from (values
      ('my_seva_act_points', 'p_from date, p_to date'),
      ('my_giving_points', 'p_from date, p_to date'),
      ('list_devotee_seva_act_points', 'p_devotee_id uuid, p_from date, p_to date'),
      ('list_devotee_giving_points', 'p_devotee_id uuid, p_from date, p_to date'),
      ('seva_mala_window_points', 'p_devotee_id uuid, p_from date, p_to date'),
      ('seva_mala_normalise',
       'p_utility numeric, p_reference numeric, p_alpha numeric, p_ceiling numeric'),
      ('seva_mala_norm_ceiling', '')
    ) as expected(name, args)
    where expected.args is distinct from coalesce(
      (select pg_get_function_identity_arguments(proc.oid)
       from pg_proc proc
       join pg_namespace spaces on spaces.oid = proc.pronamespace
       where spaces.nspname = 'public' and proc.proname = expected.name), '(missing)')
  loop
    raise exception 'public.% takes (%).', v_shape, v_mine;
  end loop;

  -- Exactly one of each, so no defaulted overload can make a call ambiguous.
  for v_shape in
    select proc.proname
    from pg_proc proc
    join pg_namespace spaces on spaces.oid = proc.pronamespace
    where spaces.nspname = 'public'
      and proc.proname in (
        'my_seva_act_points', 'my_giving_points',
        'list_devotee_seva_act_points', 'list_devotee_giving_points',
        'seva_mala_window_points', 'seva_mala_normalise',
        'seva_mala_norm_ceiling', 'seva_mala_points', 'explain_my_score')
    group by proc.proname
    having count(*) <> 1
  loop
    raise exception 'There is more than one public.%; a defaulted overload is ambiguous.', v_shape;
  end loop;

  -- The two pairs, column for column and in the same order.
  for v_shape in select unnest(array['seva_act_points', 'giving_points']) loop
    select string_agg(parameters.parameter_name, ', ' order by parameters.ordinal_position)
    into v_mine
    from information_schema.parameters parameters
    where parameters.specific_schema = 'public'
      and parameters.specific_name like
        (case v_shape when 'seva_act_points' then 'my_seva_act_points%'
                      else 'my_giving_points%' end)
      and parameters.parameter_mode = 'OUT';

    select string_agg(parameters.parameter_name, ', ' order by parameters.ordinal_position)
    into v_theirs
    from information_schema.parameters parameters
    where parameters.specific_schema = 'public'
      and parameters.specific_name like ('list_devotee_' || v_shape || '%')
      and parameters.parameter_mode = 'OUT';

    if v_mine is null or v_mine is distinct from v_theirs then
      raise exception
        'The devotee''s % list returns (%) and the President''s returns (%). One component renders both or neither.',
        v_shape, coalesce(v_mine, '(none)'), coalesce(v_theirs, '(none)');
    end if;
  end loop;

  -- The columns a client is being promised, named out loud.
  select string_agg(parameters.parameter_name, ', ' order by parameters.ordinal_position)
  into v_mine
  from information_schema.parameters parameters
  where parameters.specific_schema = 'public'
    and parameters.specific_name like 'my_seva_act_points%'
    and parameters.parameter_mode = 'OUT';
  if v_mine <> 'assignment_id, service_instance_id, seva_name, occurred_on, weekday, '
              || 'started_at_local, minutes, credited_minutes, counted_minutes, '
              || 'points_status, points_note, share, points, seva_points, giving_points, '
              || 'total_points, window_from, window_to, scaled_against, is_whole_period, '
              || 'attribution' then
    raise exception 'my_seva_act_points returns (%).', v_mine;
  end if;

  select string_agg(parameters.parameter_name, ', ' order by parameters.ordinal_position)
  into v_mine
  from information_schema.parameters parameters
  where parameters.specific_schema = 'public'
    and parameters.specific_name like 'my_giving_points%'
    and parameters.parameter_mode = 'OUT';
  if v_mine <> 'donation_id, received_on, weekday, amount_cents, currency, kind, '
              || 'recurrence, sponsorship_type_name, share, points, seva_points, '
              || 'giving_points, total_points, window_from, window_to, scaled_against, '
              || 'is_whole_period, attribution' then
    raise exception 'my_giving_points returns (%).', v_mine;
  end if;

  -- explain_my_score gained the two dials and lost nothing.
  select string_agg(parameters.parameter_name, ', ' order by parameters.ordinal_position)
  into v_mine
  from information_schema.parameters parameters
  where parameters.specific_schema = 'public'
    and parameters.specific_name like 'explain_my_score%'
    and parameters.parameter_mode = 'OUT';
  if v_mine not like '%balance_beta, soft_cap_alpha, norm_ceiling, score%' then
    raise exception
      'explain_my_score returns (%) and cannot show a devotee how their norm was derived.',
      v_mine;
  end if;
end;
$$;

-- No component leaks out of the new functions. The set of things an ordinary
-- devotee may execute that returns a norm, a reference or a unit is 0060's set
-- and has not grown.
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
-- 2. The soft cap as arithmetic, before any fixture exists.
--
--    Everything here is a property of public.seva_mala_normalise over numbers
--    this file supplies, so it holds whatever the congregation happens to be.
-- ---------------------------------------------------------------------------

do $$
declare
  v_ceiling numeric := public.seva_mala_norm_ceiling();
  v_alpha numeric := 0.15;
  v_ref numeric := 1.0296194172;
  v_case record;
  v_got numeric;
  v_last numeric;
  v_step numeric;
  v_prev_step numeric;
begin
  -- The ceiling is 1 + beta and is derived, not typed in.
  if v_ceiling <> 1.5 then
    raise exception 'The ceiling is % rather than 1 + beta = 1.5.', v_ceiling;
  end if;
  if v_ceiling <> 1 + public.seva_mala_number('seva_mala.balance_beta', 0.5) then
    raise exception 'The ceiling is not 1 + balance_beta; the two can drift apart.';
  end if;

  -- Continuous at the reference, and exactly 1 there.
  if public.seva_mala_normalise(v_ref, v_ref, v_alpha, v_ceiling) <> 1.0 then
    raise exception 'A devotee exactly at the congregation''s reference is not at 1.0.';
  end if;
  if abs(public.seva_mala_normalise(v_ref * 1.000001, v_ref, v_alpha, v_ceiling) - 1.0)
     > 0.000002 then
    raise exception 'normalise jumps at the reference; the cap is not continuous.';
  end if;

  -- Below the reference NOTHING MOVED. This is 0055's arm and most of the
  -- congregation stands on it.
  for v_case in select generate_series(1, 99) / 100.0 as ratio loop
    if public.seva_mala_normalise(v_case.ratio * v_ref, v_ref, v_alpha, v_ceiling)
       <> round(v_case.ratio, 6) then
      raise exception
        'A devotee at % of the reference reads % rather than the plain ratio.',
        v_case.ratio,
        public.seva_mala_normalise(v_case.ratio * v_ref, v_ref, v_alpha, v_ceiling);
    end if;
  end loop;

  -- Strictly increasing above it: giving more always counts for something.
  v_last := 0;
  for v_case in select generate_series(1, 400) / 100.0 as ratio loop
    v_got := public.seva_mala_normalise(v_case.ratio * v_ref, v_ref, v_alpha, v_ceiling);
    if v_got <= v_last then
      raise exception
        'normalise is not strictly increasing at % of the reference (% after %).',
        v_case.ratio, v_got, v_last;
    end if;
    v_last := v_got;
  end loop;

  -- And STEEPLY DIMINISHING: each further tenth of a reference is worth less
  -- than the one before it, everywhere above the reference.
  v_prev_step := null;
  for v_case in select 1.0 + generate_series(1, 40) / 10.0 as ratio loop
    v_step := public.seva_mala_normalise(v_case.ratio * v_ref, v_ref, v_alpha, v_ceiling)
            - public.seva_mala_normalise((v_case.ratio - 0.1) * v_ref, v_ref, v_alpha, v_ceiling);
    if v_prev_step is not null and v_step >= v_prev_step then
      raise exception
        'The %th tenth beyond the reference is worth % after %; returns are not diminishing.',
        v_case.ratio, v_step, v_prev_step;
    end if;
    v_prev_step := v_step;
  end loop;

  -- The rail is at u/ref = exp(beta/alpha) = 28.03, which is a COMPRESSED
  -- offering twenty-eight times the congregation's own, and it holds beyond it.
  if public.seva_mala_normalise(20 * v_ref, v_ref, v_alpha, v_ceiling) >= v_ceiling then
    raise exception
      'The ceiling is already reached at twenty times the congregation''s compressed reference.';
  end if;
  if public.seva_mala_normalise(30 * v_ref, v_ref, v_alpha, v_ceiling) <> v_ceiling
    or public.seva_mala_normalise(1e6 * v_ref, v_ref, v_alpha, v_ceiling) <> v_ceiling
  then
    raise exception 'The ceiling does not hold past the crossing point.';
  end if;

  -- MONEY STILL CANNOT BUY THE TOP, and this is the assertion that says so in
  -- dollars rather than in utilities. Every gift from one dollar to TEN BILLION
  -- DOLLARS, in this congregation's own units, scores strictly less than a
  -- devotee who merely reached the reference in both dimensions.
  for v_case in select power(10, generate_series(2, 12))::numeric as cents loop
    if public.seva_mala_score(
         0,
         public.seva_mala_normalise(ln(1 + v_case.cents / 25000.0), v_ref, v_alpha, v_ceiling),
         0.5) >= public.seva_mala_score(1.0, 1.0, 0.5)
    then
      raise exception
        'A gift of %$ and nothing else reaches a devotee who gave both their hands and their means.',
        round(v_case.cents / 100.0);
    end if;
  end loop;

  -- And nowhere at all, however absurd the number, may one dimension beat two.
  for v_case in select generate_series(1, 400) / 4.0 as ratio loop
    if public.seva_mala_score(
         public.seva_mala_normalise(v_case.ratio * v_ref, v_ref, v_alpha, v_ceiling),
         0, 0.5) > public.seva_mala_score(1.0, 1.0, 0.5)
    then
      raise exception
        'At % times the reference, one dimension alone passes a devotee at the reference in both.',
        v_case.ratio;
    end if;
  end loop;

  -- alpha = 0 IS 0055's hard cap, exactly. The temple can go back.
  if public.seva_mala_normalise(50 * v_ref, v_ref, 0, v_ceiling) <> 1.0
    or public.seva_mala_normalise(0.4 * v_ref, v_ref, 0, v_ceiling) <> 0.4
  then
    raise exception 'alpha = 0 is not the hard cap 202608040055 shipped.';
  end if;

  -- Nothing offered is nothing scored, and a negative is not a credit.
  if public.seva_mala_normalise(0, v_ref, v_alpha, v_ceiling) <> 0
    or public.seva_mala_normalise(null, v_ref, v_alpha, v_ceiling) <> 0
    or public.seva_mala_normalise(-5, v_ref, v_alpha, v_ceiling) <> 0
  then
    raise exception 'normalise pays something for nothing.';
  end if;
end;
$$;

-- A FUNCTION OF u/ref ALONE. This is the whole reason a pure sevak and a pure
-- donor at the same relative standing cannot come apart, so it is asserted over
-- a grid of standings and a grid of references rather than at one point.
do $$
declare
  v_ceiling numeric := public.seva_mala_norm_ceiling();
  v_case record;
begin
  for v_case in
    select ratios.ratio, refs.ref_s, refs.ref_g
    from (select generate_series(1, 60) / 20.0 as ratio) ratios
    cross join (values
      (1.7917594692, 1.0296194172),
      (0.6931471806, 3.5000000000),
      (2.5000000000, 2.5000000000)
    ) as refs(ref_s, ref_g)
  loop
    if public.seva_mala_normalise(v_case.ratio * v_case.ref_s, v_case.ref_s, 0.15, v_ceiling)
       is distinct from
       public.seva_mala_normalise(v_case.ratio * v_case.ref_g, v_case.ref_g, 0.15, v_ceiling)
    then
      raise exception
        'At % of the reference, seva scaled against % and giving scaled against % come to different numbers.',
        v_case.ratio, v_case.ref_s, v_case.ref_g;
    end if;

    -- And therefore the two archetypes score the same, and are both beaten by a
    -- devotee who reached the reference in both.
    if public.seva_mala_score(
         public.seva_mala_normalise(v_case.ratio * v_case.ref_s, v_case.ref_s, 0.15, v_ceiling),
         0, 0.5)
       <> public.seva_mala_score(
         0,
         public.seva_mala_normalise(v_case.ratio * v_case.ref_g, v_case.ref_g, 0.15, v_ceiling),
         0.5)
    then
      raise exception 'A pure sevak and a pure donor at % of the reference score differently.',
        v_case.ratio;
    end if;
  end loop;
end;
$$;

-- Every guard, refused out loud rather than silently coerced.
do $$
declare
  v_case record;
  v_message text;
  v_got numeric;
begin
  for v_case in
    select * from (values
      (1.0, 0::numeric, 0.15, 1.5, 'positive'),
      (1.0, -1::numeric, 0.15, 1.5, 'positive'),
      (1.0, null::numeric, 0.15, 1.5, 'positive'),
      (1.0, 1.2, -0.1, 1.5, '[0, 1]'),
      (1.0, 1.2, 1.5, 1.5, '[0, 1]'),
      (1.0, 1.2, null::numeric, 1.5, '[0, 1]'),
      (1.0, 1.2, 0.15, 0.9, 'at least 1'),
      (1.0, 1.2, 0.15, null::numeric, 'at least 1')
    ) as bad(utility, reference, alpha, ceiling, expected)
  loop
    v_message := null;
    begin
      v_got := public.seva_mala_normalise(
        v_case.utility, v_case.reference, v_case.alpha, v_case.ceiling);
      raise exception 'FS-SERVED: normalise(%, %, %, %) answered %.',
        v_case.utility, coalesce(v_case.reference::text, 'null'),
        coalesce(v_case.alpha::text, 'null'), coalesce(v_case.ceiling::text, 'null'),
        v_got;
    exception when others then
      v_message := sqlerrm;
    end;
    if v_message like 'FS-SERVED%' then
      raise exception '%', v_message;
    end if;
    if position(v_case.expected in v_message) = 0 then
      raise exception 'The refusal reads "%" and does not say the argument must be %.',
        v_message, v_case.expected;
    end if;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. The published scale, told where its top is.
--
--    0060's grid of ten, with 0060's floor of ten, capped at the new ceiling.
-- ---------------------------------------------------------------------------

do $$
declare
  v_case record;
  v_got integer;
begin
  for v_case in
    select * from (values
      (null::numeric,     0),
      (0::numeric,        0),
      (-0.4::numeric,     0),
      (0.000001::numeric, 10),
      (0.666667::numeric, 670),
      (0.751207::numeric, 750),
      (0.683942::numeric, 680),
      (0.217862::numeric, 220),
      (1.0::numeric,      1000),
      -- Above a thousand, which 0060 could not publish and this file must.
      (1.103972::numeric, 1100),
      (1.126810::numeric, 1130),
      (1.5::numeric,      1500),
      -- And railed there.
      (2.4::numeric,      1500)
    ) as expected(norm, points)
  loop
    v_got := public.seva_mala_points(v_case.norm);
    if v_got is distinct from v_case.points then
      raise exception 'seva_mala_points(%) is % rather than %.',
        coalesce(v_case.norm::text, 'null'), v_got, v_case.points;
    end if;
  end loop;

  -- The grid over the whole new range: a multiple of ten, never above the
  -- ceiling in points, never below ten for anything positive.
  if exists (
    select 1 from generate_series(1, 1500) step
    where public.seva_mala_points(step / 1000.0) % 10 <> 0
       or public.seva_mala_points(step / 1000.0) > 1500
       or public.seva_mala_points(step / 1000.0) < 10
  ) then
    raise exception 'The published points are not on a grid of ten from 10 to 1500.';
  end if;

  -- Monotone, so coarsening can tie two devotees and can never reorder them.
  if exists (
    select 1 from generate_series(1, 1499) step
    where public.seva_mala_points(step / 1000.0)
        > public.seva_mala_points((step + 1) / 1000.0)
  ) then
    raise exception 'The published points are not monotone in the score.';
  end if;

  -- The ceiling in points is the ceiling in norms, and moves with it.
  if public.seva_mala_points(99.0) <> (public.seva_mala_norm_ceiling() * 1000)::integer then
    raise exception 'The published ceiling is % rather than the norm ceiling in points.',
      public.seva_mala_points(99.0);
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. The congregation.
-- ---------------------------------------------------------------------------

create table public.fs_ids (key text primary key, id uuid not null);
grant select on public.fs_ids to authenticated;

do $$
declare
  v_who record;
  v_i integer := 0;
begin
  for v_who in
    select * from (values
      ('sevak_ref',   'Sevak Ref Das'),
      ('sevak_two',   'Sevak Two Das'),
      ('sevak_mid',   'Sevak Mid Das'),
      ('s_extra',     'Sevaka Extra Das'),
      ('s01', 'Server One Das'),     ('s02', 'Server Two Das'),
      ('s03', 'Server Three Das'),   ('s04', 'Server Four Das'),
      ('s05', 'Server Five Das'),    ('s06', 'Server Six Das'),
      ('s07', 'Server Seven Das'),   ('s08', 'Server Eight Das'),
      ('s09', 'Server Nine Das'),    ('s10', 'Server Ten Das'),
      ('s11', 'Server Eleven Das'),
      ('mixed',       'Mixed Devi'),
      ('both_ref',    'Both Ref Das'),
      ('donor_ref',   'Donor Ref Das'),
      ('donor_two',   'Donor Two Das'),
      ('donor_big',   'Donor Big Das'),
      ('donor_mid',   'Donor Mid Das'),
      ('donor_small', 'Donor Small Devi'),
      ('g01', 'Giver One Das'),      ('g02', 'Giver Two Das'),
      ('g03', 'Giver Three Das'),    ('g04', 'Giver Four Das'),
      ('g05', 'Giver Five Das'),     ('g06', 'Giver Six Das'),
      ('g07', 'Giver Seven Das'),    ('g08', 'Giver Eight Das'),
      ('g09', 'Giver Nine Das'),     ('g10', 'Giver Ten Das'),
      ('g11', 'Giver Eleven Das'),
      ('pres', 'Narayana Das'),
      ('whale1', 'Whale One Das'),   ('whale2', 'Whale Two Das'),
      ('whale3', 'Whale Three Das'), ('whale4', 'Whale Four Das'),
      ('whale5', 'Whale Five Das')
    ) as cast_member(key, name)
  loop
    v_i := v_i + 1;
    insert into auth.users (id, email, raw_user_meta_data)
    values (
      ('62000000-0000-0000-0000-0000000000' || lpad(v_i::text, 2, '0'))::uuid,
      'fs-' || v_who.key || '@example.test',
      jsonb_build_object('name', v_who.name)
    );

    update public.users
    set name = v_who.name
    where users.email = 'fs-' || v_who.key || '@example.test';

    insert into public.fs_ids (key, id)
    select v_who.key, users.id
    from public.users where users.email = 'fs-' || v_who.key || '@example.test';
  end loop;
end;
$$;

update public.users
set role_id = (select roles.id from public.roles where roles.name = 'president')
where users.email = 'fs-pres@example.test';

-- Everybody is on the board. Opting out is 0060's subject, not this file's.
update public.users
set leaderboard_visible = true
where users.email like 'fs-%@example.test';

-- ---------------------------------------------------------------------------
-- 5. The facts.
--
--    Every act 180 minutes except the four `mixed` serves, so v_s is 180 by
--    construction. At most two acts a day and eight a week, so nobody reaches
--    the 480-minute day or the 1,800-minute week and credited minutes are served
--    minutes. All of it strictly before this week began.
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
      ('sevak_two', 35, 2),
      ('sevak_mid', 15, 2),
      ('sevak_ref',  5, 1),
      ('both_ref',   5, 1),
      ('s_extra',    5, 1),
      ('s01',        4, 1),
      ('s02',        4, 1),
      ('s03',        3, 1),
      ('s04',        3, 1),
      ('s05',        3, 1),
      ('s06',        2, 1),
      ('s07',        2, 1),
      ('s08',        2, 1),
      ('s09',        1, 1),
      ('s10',        1, 1),
      ('s11',        1, 1)
    ) as plan(who, acts, per_day)
  loop
    for v_n in 1 .. v_plan.acts loop
      v_day := v_anchor
             - (7 * ((v_n - 1) / (v_plan.per_day * 4)))
             - (((v_n - 1) % (v_plan.per_day * 4)) / v_plan.per_day);

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
        (select ids.id from public.fs_ids ids where ids.key = v_plan.who),
        'self_joined', 'completed', 'member_verified', 'served',
        (v_day + time '12:00') at time zone 'America/Chicago'
      );
    end loop;
  end loop;
end;
$$;

-- The attribution fixture: four acts of three different lengths, one of them
-- marked absent, on four separate days so the running total is unambiguous.
do $$
declare
  v_type uuid;
  v_anchor date := public.seva_mala_week_start(public.seva_mala_today()) - 1;
  v_act record;
  v_instance uuid;
begin
  select service_types.id into v_type
  from public.service_types where service_types.name = 'Pot Washing';

  for v_act in
    select * from (values
      (21, 60,  'served'),
      (14, 120, 'served'),
      (7,  300, 'served'),
      (3,  90,  'absent')
    ) as plan(days_back, minutes, attendance)
  loop
    insert into public.service_instances (
      service_type_id, date, start_time, duration_minutes, slots_needed,
      participation_mode, posted_by, status
    ) values (
      v_type, v_anchor - v_act.days_back, time '06:00', v_act.minutes, 1,
      'open', null, 'completed'
    ) returning id into v_instance;

    insert into public.service_assignments (
      service_instance_id, devotee_id, assignment_method, status,
      verification, attendance, completed_at
    ) values (
      v_instance,
      (select ids.id from public.fs_ids ids where ids.key = 'mixed'),
      'self_joined', 'completed', 'member_verified', v_act.attendance,
      ((v_anchor - v_act.days_back) + time '08:00') at time zone 'America/Chicago'
    );
  end loop;
end;
$$;

-- One gift each, so a donor's median gift is their gift and v_g is the plain
-- median of the eighteen.
do $$
declare
  v_anchor date := public.seva_mala_week_start(public.seva_mala_today()) - 1;
  v_gift record;
begin
  for v_gift in
    select * from (values
      ('donor_big',   250000),
      ('donor_two',   171000),
      ('donor_mid',    60000),
      ('donor_ref',    45000),
      ('both_ref',     45000),
      ('g11',          40000),
      ('g10',          35000),
      ('g09',          30000),
      ('g08',          25000),
      ('g07',          25000),
      ('g06',          25000),
      ('g05',          20000),
      ('g04',          12500),
      ('donor_small',  10000),
      ('g03',           7500),
      ('g02',           5000),
      ('g01',           2500)
    ) as gift(who, cents)
  loop
    insert into public.donations (
      donor_id, donor_name, amount_cents, kind, external_payment_id, received_at
    ) values (
      (select ids.id from public.fs_ids ids where ids.key = v_gift.who),
      v_gift.who, v_gift.cents, 'one_time', 'fs-' || v_gift.who || '-1',
      ((v_anchor - 2) + time '10:00') at time zone 'America/Chicago'
    );
  end loop;
end;
$$;

-- And three gifts for the attribution fixture, on three separate days, totalling
-- $450 with a median of $150.
do $$
declare
  v_anchor date := public.seva_mala_week_start(public.seva_mala_today()) - 1;
  v_gift record;
begin
  for v_gift in
    select * from (values
      (20,  5000),
      (13, 15000),
      (6,  25000)
    ) as plan(days_back, cents)
  loop
    insert into public.donations (
      donor_id, donor_name, amount_cents, kind, external_payment_id, received_at
    ) values (
      (select ids.id from public.fs_ids ids where ids.key = 'mixed'),
      'mixed', v_gift.cents, 'one_time', 'fs-mixed-' || v_gift.days_back,
      ((v_anchor - v_gift.days_back) + time '10:00') at time zone 'America/Chicago'
    );
  end loop;
end;
$$;

select public.recompute_seva_mala() as periods_computed;

-- ---------------------------------------------------------------------------
-- 6. The units and the references, checked before anything is concluded from
--    them, so a moved median fails here and says so.
--
--    THE REFERENCES ARE THE CONGREGATION'S. Re-derived from the fixture's own
--    facts rather than compared against a constant this file typed: the P80 of
--    what the eighteen donors actually gave, and the P80 of what the seventeen
--    servers actually served.
-- ---------------------------------------------------------------------------

do $$
declare
  v_period public.seva_mala_periods;
  v_derived numeric;
  v_weights integer;
  v_capped integer;
begin
  select * into v_period from public.seva_mala_periods where period_kind = 'lifetime';

  if v_period.seva_unit_minutes <> 180 then
    raise exception 'v_s is % rather than the 180-minute median act.', v_period.seva_unit_minutes;
  end if;
  if v_period.giving_unit_cents <> 25000 then
    raise exception 'v_g is % rather than the 25,000-cent median gift.', v_period.giving_unit_cents;
  end if;
  if round(v_period.seva_reference, 10) <> round(ln(6.0), 10) then
    raise exception 'ref_s is % rather than ln(6) = %.',
      round(v_period.seva_reference, 10), round(ln(6.0), 10);
  end if;
  if round(v_period.giving_reference, 10) <> round(ln(2.8), 10) then
    raise exception 'ref_g is % rather than ln(2.8) = %.',
      round(v_period.giving_reference, 10), round(ln(2.8), 10);
  end if;

  -- The same two numbers, computed from the facts instead of from the scoring,
  -- so "congregation-derived" is demonstrated rather than asserted.
  select percentile_cont(0.8) within group (order by ln(1 + served.minutes / 180.0))
  into v_derived
  from (
    select acts.devotee_id, sum(acts.weighted_minutes) as minutes
    from public.seva_mala_acts() acts
    where acts.quality > 0
    group by acts.devotee_id
  ) served;
  if round(v_derived, 10) <> round(v_period.seva_reference, 10) then
    raise exception
      'The stored seva reference is % but the congregation''s own eightieth percentile is %.',
      round(v_period.seva_reference, 10), round(v_derived, 10);
  end if;

  select percentile_cont(0.8) within group (order by ln(1 + given.cents / 25000.0))
  into v_derived
  from (
    select donations.donor_id, sum(donations.amount_cents)::numeric as cents
    from public.donations
    where donations.donor_id is not null
    group by donations.donor_id
  ) given;
  if round(v_derived, 10) <> round(v_period.giving_reference, 10) then
    raise exception
      'The stored giving reference is % but the congregation''s own eightieth percentile is %.',
      round(v_period.giving_reference, 10), round(v_derived, 10);
  end if;

  if v_period.participant_count <> 33 then
    raise exception 'The lifetime cohort is % rather than 33.', v_period.participant_count;
  end if;
  if v_period.participant_count
     < public.seva_mala_number('seva_mala.minimum_cohort', 8) then
    raise exception 'The fixture is below the minimum cohort, so no board publishes.';
  end if;

  select count(*) into v_weights from public.seva_type_weights where weight <> 1.0;
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

-- ---------------------------------------------------------------------------
-- 7. The temple's question, answered in real numbers.
--
--    $2,500 above $600 above $100, all three read out of public.period_scores
--    rather than recomputed here; the two larger gifts were IDENTICAL under
--    0055 and are not now; and the separation between them is compressed rather
--    than linear.
-- ---------------------------------------------------------------------------

do $$
declare
  v_row record;
begin
  for v_row in
    select * from (values
      ('donor_small', 0.326793, 0.217862,  220),
      ('donor_ref',   1.000000, 0.666667,  670),
      ('donor_mid',   1.025913, 0.683942,  680),
      ('donor_two',   1.103972, 0.735981,  740),
      ('donor_big',   1.126810, 0.751207,  750)
    ) as expected(who, giving_norm, score, points)
  loop
    if not exists (
      select 1 from public.period_scores scores
      join public.seva_mala_periods periods on periods.id = scores.period_id
      join public.fs_ids ids on ids.id = scores.devotee_id
      where periods.period_kind = 'lifetime'
        and ids.key = v_row.who
        and scores.seva_norm = 0
        and scores.giving_norm = v_row.giving_norm
        and scores.score = v_row.score
        and public.seva_mala_points(scores.score) = v_row.points
    ) then
      raise exception
        '% is not (g=%, score=%, points=%). Their stored row is %.',
        v_row.who, v_row.giving_norm, v_row.score, v_row.points,
        (select format('g=%s score=%s points=%s',
                       scores.giving_norm, scores.score,
                       public.seva_mala_points(scores.score))
         from public.period_scores scores
         join public.seva_mala_periods periods on periods.id = scores.period_id
         join public.fs_ids ids on ids.id = scores.devotee_id
         where periods.period_kind = 'lifetime' and ids.key = v_row.who);
    end if;
  end loop;
end;
$$;

do $$
declare
  v_big numeric;
  v_mid numeric;
  v_small numeric;
  v_ref numeric;
  v_old_big numeric;
  v_old_mid numeric;
begin
  select scores.giving_norm into v_big
  from public.period_scores scores
  join public.seva_mala_periods periods on periods.id = scores.period_id
  join public.fs_ids ids on ids.id = scores.devotee_id
  where periods.period_kind = 'lifetime' and ids.key = 'donor_big';

  select scores.giving_norm into v_mid
  from public.period_scores scores
  join public.seva_mala_periods periods on periods.id = scores.period_id
  join public.fs_ids ids on ids.id = scores.devotee_id
  where periods.period_kind = 'lifetime' and ids.key = 'donor_mid';

  select scores.giving_norm into v_small
  from public.period_scores scores
  join public.seva_mala_periods periods on periods.id = scores.period_id
  join public.fs_ids ids on ids.id = scores.devotee_id
  where periods.period_kind = 'lifetime' and ids.key = 'donor_small';

  -- The complaint, restated: under 0055 these two were the same number, because
  -- both utilities clear the congregation's eightieth percentile.
  select periods.giving_reference into v_ref
  from public.seva_mala_periods periods where periods.period_kind = 'lifetime';

  select least(1.0, scores.giving_utility / v_ref) into v_old_big
  from public.period_scores scores
  join public.seva_mala_periods periods on periods.id = scores.period_id
  join public.fs_ids ids on ids.id = scores.devotee_id
  where periods.period_kind = 'lifetime' and ids.key = 'donor_big';

  select least(1.0, scores.giving_utility / v_ref) into v_old_mid
  from public.period_scores scores
  join public.seva_mala_periods periods on periods.id = scores.period_id
  join public.fs_ids ids on ids.id = scores.devotee_id
  where periods.period_kind = 'lifetime' and ids.key = 'donor_mid';

  if v_old_big <> 1.0 or v_old_mid <> 1.0 then
    raise exception
      'The $2,500 and $600 gifts do not both clear the reference (% and % under the old rule), so this fixture does not reproduce the temple''s complaint.',
      v_old_big, v_old_mid;
  end if;

  -- And they are not the same number now.
  if v_big <= v_mid then
    raise exception '$2,500 reads % and $600 reads %; the flattening is still there.',
      v_big, v_mid;
  end if;
  if v_mid <= v_small then
    raise exception '$600 reads % and $100 reads %.', v_mid, v_small;
  end if;

  -- COMPRESSED, NOT LINEAR. Four and a sixth times the money buys less than a
  -- tenth more points, and a devotee cannot read the dollars off the board.
  if v_big / v_mid >= 1.25 then
    raise exception
      '$2,500 is % times $600 in points, which is not "nowhere near twice as much".',
      round(v_big / v_mid, 4);
  end if;
  if v_big / v_mid <= 1.02 then
    raise exception
      '$2,500 is only % times $600 in points, which is not meaningfully more.',
      round(v_big / v_mid, 4);
  end if;
  -- Sublinear against the money by more than an order of magnitude.
  if (v_big / v_mid - 1) * 10 >= (250000.0 / 60000.0 - 1) then
    raise exception 'The points gap is not an order of magnitude below the money gap.';
  end if;

  -- Below the reference NOTHING MOVED: $100 is the plain ratio it always was.
  if v_small <> round(
       (select scores.giving_utility from public.period_scores scores
        join public.seva_mala_periods periods on periods.id = scores.period_id
        join public.fs_ids ids on ids.id = scores.devotee_id
        where periods.period_kind = 'lifetime' and ids.key = 'donor_small') / v_ref, 6)
  then
    raise exception 'A gift below the reference has been re-scaled by this migration.';
  end if;
end;
$$;

-- The seva equivalents, on the same ladder.
do $$
declare
  v_row record;
begin
  for v_row in
    select * from (values
      ('s09',       0.386853, 0.257902),
      ('mixed',     0.725144, 0.908381),
      ('sevak_ref', 1.000000, 0.666667),
      ('sevak_mid', 1.065488, 0.710325),
      ('sevak_two', 1.103972, 0.735981)
    ) as expected(who, seva_norm, score)
  loop
    if not exists (
      select 1 from public.period_scores scores
      join public.seva_mala_periods periods on periods.id = scores.period_id
      join public.fs_ids ids on ids.id = scores.devotee_id
      where periods.period_kind = 'lifetime'
        and ids.key = v_row.who
        and scores.seva_norm = v_row.seva_norm
        and scores.score = v_row.score
    ) then
      raise exception '% is not (s=%, score=%). Their stored row is %.',
        v_row.who, v_row.seva_norm, v_row.score,
        (select format('s=%s g=%s score=%s',
                       scores.seva_norm, scores.giving_norm, scores.score)
         from public.period_scores scores
         join public.seva_mala_periods periods on periods.id = scores.period_id
         join public.fs_ids ids on ids.id = scores.devotee_id
         where periods.period_kind = 'lifetime' and ids.key = v_row.who);
    end if;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. The archetypes, in the fixture, at two different standings.
-- ---------------------------------------------------------------------------

do $$
declare
  v_sevak numeric;
  v_donor numeric;
  v_both numeric;
  v_pair record;
begin
  for v_pair in
    select * from (values
      ('sevak_ref', 'donor_ref', 'at the congregation''s reference'),
      ('sevak_two', 'donor_two', 'at exactly twice it')
    ) as pairs(sevak, donor, where_they_stand)
  loop
    select scores.score into v_sevak
    from public.period_scores scores
    join public.seva_mala_periods periods on periods.id = scores.period_id
    join public.fs_ids ids on ids.id = scores.devotee_id
    where periods.period_kind = 'lifetime' and ids.key = v_pair.sevak;

    select scores.score into v_donor
    from public.period_scores scores
    join public.seva_mala_periods periods on periods.id = scores.period_id
    join public.fs_ids ids on ids.id = scores.devotee_id
    where periods.period_kind = 'lifetime' and ids.key = v_pair.donor;

    if v_sevak is null or v_donor is null then
      raise exception 'One of % and % has no score at all.', v_pair.sevak, v_pair.donor;
    end if;
    if v_sevak <> v_donor then
      raise exception
        'The pure sevak scores % and the pure donor % %, and they are the same standing.',
        v_sevak, v_donor, v_pair.where_they_stand;
    end if;
  end loop;

  -- And a devotee who did both, merely to the congregation's reference, beats
  -- every single-dimension devotee in the fixture — including the $2,500 donor.
  select scores.score into v_both
  from public.period_scores scores
  join public.seva_mala_periods periods on periods.id = scores.period_id
  join public.fs_ids ids on ids.id = scores.devotee_id
  where periods.period_kind = 'lifetime' and ids.key = 'both_ref';

  if v_both <> 1.000000 then
    raise exception 'The devotee at the reference in both scores % rather than 1.', v_both;
  end if;

  if exists (
    select 1
    from public.period_scores scores
    join public.seva_mala_periods periods on periods.id = scores.period_id
    where periods.period_kind = 'lifetime'
      and (scores.seva_norm = 0 or scores.giving_norm = 0)
      and scores.score >= v_both
  ) then
    raise exception
      'A devotee who did only one of the two things reaches the devotee who did both.';
  end if;

  -- Nobody is above the ceiling, and the ceiling is where section 2 says.
  if exists (
    select 1 from public.period_scores scores
    where scores.seva_norm > public.seva_mala_norm_ceiling()
       or scores.giving_norm > public.seva_mala_norm_ceiling()
       or scores.score > public.seva_mala_norm_ceiling()
  ) then
    raise exception 'A stored score is above the ceiling.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 9. Where the points came from.
--
--    Read as the devotee, under `set local role authenticated`, and kept for
--    inspection. Every assertion afterwards is made against public.period_scores,
--    which the devotee who read them cannot see.
-- ---------------------------------------------------------------------------

create table public.fs_acts (
  ord integer, assignment_id uuid, seva_name text, occurred_on date,
  minutes numeric, counted_minutes numeric, points_status text, points_note text,
  share numeric, points integer, seva_points integer, giving_points integer,
  total_points integer, window_from date, window_to date, scaled_against text,
  is_whole_period boolean, attribution text
);
create table public.fs_gifts (
  ord integer, donation_id uuid, received_on date, amount_cents integer,
  share numeric, points integer, seva_points integer, giving_points integer,
  total_points integer, is_whole_period boolean, attribution text
);
grant select, insert on public.fs_acts to authenticated;
grant select, insert on public.fs_gifts to authenticated;

set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.fs_ids ids where ids.key = 'mixed'), true);

insert into public.fs_acts
select
  listed.ord, listed.assignment_id, listed.seva_name, listed.occurred_on,
  listed.minutes, listed.counted_minutes, listed.points_status, listed.points_note,
  listed.share, listed.points, listed.seva_points, listed.giving_points,
  listed.total_points, listed.window_from, listed.window_to, listed.scaled_against,
  listed.is_whole_period, listed.attribution
from public.my_seva_act_points(date '1970-01-01', public.seva_mala_today())
     with ordinality as listed(
       assignment_id, service_instance_id, seva_name, occurred_on, weekday,
       started_at_local, minutes, credited_minutes, counted_minutes,
       points_status, points_note, share, points, seva_points, giving_points,
       total_points, window_from, window_to, scaled_against, is_whole_period,
       attribution, ord
     );

insert into public.fs_gifts
select
  listed.ord, listed.donation_id, listed.received_on, listed.amount_cents,
  listed.share, listed.points, listed.seva_points, listed.giving_points,
  listed.total_points, listed.is_whole_period, listed.attribution
from public.my_giving_points(date '1970-01-01', public.seva_mala_today())
     with ordinality as listed(
       donation_id, received_on, weekday, amount_cents, currency, kind,
       recurrence, sponsorship_type_name, share, points, seva_points,
       giving_points, total_points, window_from, window_to, scaled_against,
       is_whole_period, attribution, ord
     );

reset role;
select set_config('request.jwt.claim.sub', '', true);

do $$
declare
  v_score numeric;
  v_sum integer;
  v_row record;
begin
  select scores.score into v_score
  from public.period_scores scores
  join public.seva_mala_periods periods on periods.id = scores.period_id
  join public.fs_ids ids on ids.id = scores.devotee_id
  where periods.period_kind = 'lifetime' and ids.key = 'mixed';

  -- THE WINDOW IS THE WHOLE PERIOD, so the total is the board's own number.
  if not exists (select 1 from public.fs_acts where is_whole_period) then
    raise exception 'A window covering the whole lifetime period did not say so.';
  end if;
  if (select distinct scaled_against from public.fs_acts) <> 'lifetime' then
    raise exception 'The window was priced against % rather than the lifetime period.',
      (select distinct scaled_against from public.fs_acts);
  end if;
  if (select distinct total_points from public.fs_acts) <> round(v_score * 1000)::integer then
    raise exception
      'The attributed total is % but the board''s score is %, which is % points.',
      (select distinct total_points from public.fs_acts), v_score,
      round(v_score * 1000)::integer;
  end if;

  -- THE PARTS SUM TO THE WHOLE, on both sides and between them.
  select sum(points) into v_sum from public.fs_acts;
  if v_sum is distinct from (select distinct seva_points from public.fs_acts) then
    raise exception 'The acts come to % points and seva_points is %.',
      v_sum, (select distinct seva_points from public.fs_acts);
  end if;

  select sum(points) into v_sum from public.fs_gifts;
  if v_sum is distinct from (select distinct giving_points from public.fs_gifts) then
    raise exception 'The gifts come to % points and giving_points is %.',
      v_sum, (select distinct giving_points from public.fs_gifts);
  end if;

  if (select distinct seva_points + giving_points from public.fs_acts)
     is distinct from (select distinct total_points from public.fs_acts) then
    raise exception 'seva_points and giving_points do not add to total_points.';
  end if;

  -- The two lists agree about the split, which they must, because they are the
  -- same function underneath.
  if (select distinct seva_points from public.fs_acts)
       is distinct from (select distinct seva_points from public.fs_gifts)
    or (select distinct giving_points from public.fs_acts)
       is distinct from (select distinct giving_points from public.fs_gifts)
    or (select distinct total_points from public.fs_acts)
       is distinct from (select distinct total_points from public.fs_gifts)
  then
    raise exception 'The seva list and the giving list disagree about the split.';
  end if;

  -- The numbers themselves, so a change to the scheme has to be made on purpose.
  if (select distinct seva_points from public.fs_acts) <> 242
    or (select distinct giving_points from public.fs_acts) <> 666
    or (select distinct total_points from public.fs_acts) <> 908
  then
    raise exception 'The split is %/% of %, rather than 242/666 of 908.',
      (select distinct seva_points from public.fs_acts),
      (select distinct giving_points from public.fs_acts),
      (select distinct total_points from public.fs_acts);
  end if;

  -- SHARES ARE PROPORTIONAL to what entered the logarithm, and an act that
  -- earned nothing is listed, is worth zero, and says why.
  for v_row in
    select * from (values
      (60::numeric,  0.125000, 30, 'counted'),
      (120::numeric, 0.250000, 61, 'counted'),
      (300::numeric, 0.625000, 151, 'counted'),
      (0::numeric,   0.000000, 0,  'not_served')
    ) as expected(counted, share, points, status)
  loop
    if not exists (
      select 1 from public.fs_acts acts
      where acts.counted_minutes = v_row.counted
        and acts.share = v_row.share
        and acts.points = v_row.points
        and acts.points_status = v_row.status
    ) then
      raise exception
        'No act with % counted minutes has share % and % points and status %. The list is: %.',
        v_row.counted, v_row.share, v_row.points, v_row.status,
        (select string_agg(format('%s min share %s -> %s (%s)',
                                  acts.counted_minutes, acts.share, acts.points,
                                  acts.points_status), '; ' order by acts.ord)
         from public.fs_acts acts);
    end if;
  end loop;

  -- The zero act keeps its hours and its explanation.
  if not exists (
    select 1 from public.fs_acts
    where points = 0 and minutes = 90 and points_note is not null
      and points_note ilike '%not served%'
  ) then
    raise exception 'The act that was marked absent is missing, silent, or has been paid for.';
  end if;

  -- The gifts, likewise.
  for v_row in
    select * from (values
      (5000,  0.111111, 74),
      (15000, 0.333333, 222),
      (25000, 0.555556, 370)
    ) as expected(cents, share, points)
  loop
    if not exists (
      select 1 from public.fs_gifts gifts
      where gifts.amount_cents = v_row.cents
        and gifts.share = v_row.share
        and gifts.points = v_row.points
    ) then
      raise exception 'No gift of % cents has share % and % points. The list is: %.',
        v_row.cents, v_row.share, v_row.points,
        (select string_agg(format('%s cents share %s -> %s',
                                  gifts.amount_cents, gifts.share, gifts.points),
                           '; ' order by gifts.ord)
         from public.fs_gifts gifts);
    end if;
  end loop;

  -- THE HONEST SENTENCE TRAVELS IN THE ROWS. A client cannot render this list
  -- as "what each act earned" without contradicting the text beside it.
  if exists (
    select 1 from public.fs_acts
    where attribution is null
       or attribution not ilike '%shares%'
       or attribution not ilike '%logarithm%'
       or attribution not ilike '%without adding up%'
  ) then
    raise exception 'The seva rows do not carry the attribution note: %.',
      coalesce((select distinct attribution from public.fs_acts), '(null)');
  end if;
  if exists (
    select 1 from public.fs_gifts
    where attribution is null or attribution not ilike '%shares of your giving points%'
  ) then
    raise exception 'The giving rows do not carry the attribution note.';
  end if;
end;
$$;

-- Every devotee in the congregation, not only the convenient one: for all
-- thirty-three, the acts sum to seva_points and the gifts to giving_points, and
-- the two add to the board's number. Read through the President's variant,
-- which is also how that variant gets exercised at all.
set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.fs_ids ids where ids.key = 'pres'), true);

create table public.fs_sums (
  devotee_id uuid, act_points integer, gift_points integer,
  seva_points integer, giving_points integer, total_points integer
);
grant select, insert on public.fs_sums to authenticated;

insert into public.fs_sums
select
  ids.id,
  coalesce((select sum(listed.points)
            from public.list_devotee_seva_act_points(
              ids.id, date '1970-01-01', public.seva_mala_today()) listed), 0),
  coalesce((select sum(listed.points)
            from public.list_devotee_giving_points(
              ids.id, date '1970-01-01', public.seva_mala_today()) listed), 0),
  coalesce((select max(listed.seva_points)
            from public.list_devotee_seva_act_points(
              ids.id, date '1970-01-01', public.seva_mala_today()) listed),
           (select max(listed.seva_points)
            from public.list_devotee_giving_points(
              ids.id, date '1970-01-01', public.seva_mala_today()) listed), 0),
  coalesce((select max(listed.giving_points)
            from public.list_devotee_giving_points(
              ids.id, date '1970-01-01', public.seva_mala_today()) listed),
           (select max(listed.giving_points)
            from public.list_devotee_seva_act_points(
              ids.id, date '1970-01-01', public.seva_mala_today()) listed), 0),
  coalesce((select max(listed.total_points)
            from public.list_devotee_seva_act_points(
              ids.id, date '1970-01-01', public.seva_mala_today()) listed),
           (select max(listed.total_points)
            from public.list_devotee_giving_points(
              ids.id, date '1970-01-01', public.seva_mala_today()) listed), 0)
from public.fs_ids ids
where ids.key <> 'pres' and ids.key not like 'whale%';

reset role;
select set_config('request.jwt.claim.sub', '', true);

do $$
declare
  v_bad text;
begin
  select string_agg(format('%s: acts %s vs %s', users.name,
                           sums.act_points, sums.seva_points), '; ')
  into v_bad
  from public.fs_sums sums
  join public.users on users.id = sums.devotee_id
  where sums.act_points is distinct from sums.seva_points;
  if v_bad is not null then
    raise exception 'The per-act points do not sum to seva_points for %.', v_bad;
  end if;

  select string_agg(format('%s: gifts %s vs %s', users.name,
                           sums.gift_points, sums.giving_points), '; ')
  into v_bad
  from public.fs_sums sums
  join public.users on users.id = sums.devotee_id
  where sums.gift_points is distinct from sums.giving_points;
  if v_bad is not null then
    raise exception 'The per-gift points do not sum to giving_points for %.', v_bad;
  end if;

  select string_agg(format('%s: %s + %s <> %s', users.name, sums.seva_points,
                           sums.giving_points, sums.total_points), '; ')
  into v_bad
  from public.fs_sums sums
  join public.users on users.id = sums.devotee_id
  where sums.seva_points + sums.giving_points is distinct from sums.total_points;
  if v_bad is not null then
    raise exception 'The two dimensions do not add to the total for %.', v_bad;
  end if;

  -- And the total is the board's, for every one of them.
  select string_agg(format('%s: attributed %s, board %s', users.name,
                           sums.total_points, round(scores.score * 1000)::integer), '; ')
  into v_bad
  from public.fs_sums sums
  join public.users on users.id = sums.devotee_id
  join public.period_scores scores on scores.devotee_id = sums.devotee_id
  join public.seva_mala_periods periods on periods.id = scores.period_id
  where periods.period_kind = 'lifetime'
    and sums.total_points is distinct from round(scores.score * 1000)::integer;
  if v_bad is not null then
    raise exception 'The attributed total is not the board''s score for %.', v_bad;
  end if;

  if (select count(*) from public.fs_sums where total_points > 0) < 30 then
    raise exception
      'Only % devotees were attributed anything at all; the sweep proves little.',
      (select count(*) from public.fs_sums where total_points > 0);
  end if;
end;
$$;

-- THE NARROWEST PERIOD THAT CONTAINS THE WINDOW is the one the window is priced
-- against, so a devotee asking about this week is answered in this week's units
-- and against this week's references rather than the lifetime's. Asserted
-- against the engine directly, which only the database may call.
do $$
declare
  v_today date := public.seva_mala_today();
  v_case record;
  v_got text;
  v_whole boolean;
begin
  for v_case in
    select
      windows.from_on,
      windows.to_on,
      windows.whole,
      -- The narrowest containing period, found by span rather than by the name
      -- of the kind, so this is an independent statement of the same rule.
      (select periods.period_kind
       from public.seva_mala_periods periods
       where periods.starts_on <= windows.from_on
         and periods.ends_on >= windows.to_on
         and periods.computed_at is not null
       order by periods.ends_on - periods.starts_on, periods.starts_on desc
       limit 1) as kind
    from (values
      (public.seva_mala_week_start(v_today), v_today, true),
      (date_trunc('month', v_today::timestamp)::date, v_today, true),
      (date '1970-01-01', v_today, true),
      (v_today - 400, v_today, false)
    ) as windows(from_on, to_on, whole)
  loop
    select points.scaled_against, points.is_whole_period into v_got, v_whole
    from public.seva_mala_window_points(
      (select ids.id from public.fs_ids ids where ids.key = 'mixed'),
      v_case.from_on, v_case.to_on) points;

    if v_got is distinct from v_case.kind then
      raise exception 'The window % to % was priced against the % period rather than the %.',
        v_case.from_on, v_case.to_on, coalesce(v_got, '(none)'), coalesce(v_case.kind, '(none)');
    end if;
    if v_whole is distinct from v_case.whole then
      raise exception 'The window % to % reports is_whole_period %.',
        v_case.from_on, v_case.to_on, v_whole;
    end if;
  end loop;

  -- And the week and the lifetime are genuinely different scales, so "narrowest"
  -- is a choice with consequences rather than a distinction without one.
  if (select points.scaled_against
      from public.seva_mala_window_points(
        (select ids.id from public.fs_ids ids where ids.key = 'mixed'),
        public.seva_mala_week_start(v_today), v_today) points) <> 'week'
  then
    raise exception 'This week was not priced against this week.';
  end if;
end;
$$;

-- A window that is only part of a period says so, and still adds up.
set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.fs_ids ids where ids.key = 'mixed'), true);

do $$
declare
  v_anchor date := public.seva_mala_week_start(public.seva_mala_today()) - 1;
  v_whole boolean;
  v_sum integer;
  v_seva integer;
  v_rows integer;
begin
  select count(*), max(listed.seva_points), sum(listed.points), bool_or(listed.is_whole_period)
  into v_rows, v_seva, v_sum, v_whole
  from public.my_seva_act_points(v_anchor - 16, v_anchor - 10) listed;

  if v_rows <> 1 then
    raise exception 'A window holding one act listed % acts.', v_rows;
  end if;
  if v_whole then
    raise exception 'Seven days were reported as a whole period.';
  end if;
  if v_sum is distinct from v_seva then
    raise exception 'A partial window''s acts come to % rather than its seva_points of %.',
      v_sum, v_seva;
  end if;
  if v_seva <= 0 then
    raise exception 'A window holding a real act is worth nothing.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 10. Nothing here opened a door.
--
--     Attempted as the devotee who would really attempt it.
-- ---------------------------------------------------------------------------

do $$
declare
  v_count integer;
  v_mine uuid := (select ids.id from public.fs_ids ids where ids.key = 'mixed');
begin
  -- The lists are the caller's own and there is no argument that could make
  -- them anybody else's.
  if exists (
    select 1 from public.my_seva_act_points(date '1970-01-01', public.seva_mala_today()) listed
    join public.service_assignments assignments on assignments.id = listed.assignment_id
    where assignments.devotee_id <> v_mine
  ) then
    raise exception 'my_seva_act_points returned somebody else''s seva.';
  end if;

  if exists (
    select 1 from public.my_giving_points(date '1970-01-01', public.seva_mala_today()) listed
    join public.donations on donations.id = listed.donation_id
    where donations.donor_id is distinct from v_mine
  ) then
    raise exception 'my_giving_points returned somebody else''s gift.';
  end if;

  -- The President's variants are app.view_all's, and this devotee is not.
  select count(*) into v_count
  from public.list_devotee_seva_act_points(
    (select ids.id from public.fs_ids ids where ids.key = 'sevak_two'),
    date '1970-01-01', public.seva_mala_today());
  if v_count <> 0 then
    raise exception
      'A devotee without app.view_all read % rows of another devotee''s act points.', v_count;
  end if;

  select count(*) into v_count
  from public.list_devotee_giving_points(
    (select ids.id from public.fs_ids ids where ids.key = 'donor_big'),
    date '1970-01-01', public.seva_mala_today());
  if v_count <> 0 then
    raise exception
      'A devotee without app.view_all read % rows of another devotee''s giving.', v_count;
  end if;

  -- Not even about themselves through the President's door, which is a
  -- different function with a different rule.
  select count(*) into v_count
  from public.list_devotee_seva_act_points(v_mine, date '1970-01-01', public.seva_mala_today());
  if v_count <> 0 then
    raise exception 'The President''s list answered a devotee about themselves.';
  end if;

  -- The engine is nobody's to call.
  begin
    execute format(
      'select count(*) from public.seva_mala_window_points(%L, date ''1970-01-01'', current_date)',
      v_mine) into v_count;
    raise exception 'FS-SERVED: a devotee called seva_mala_window_points directly.';
  exception
    when insufficient_privilege then null;
    when others then
      if sqlerrm like 'FS-SERVED%' then raise; end if;
  end;

  -- And 0055 section 4 still holds.
  begin
    execute 'select count(*) from public.period_scores' into v_count;
    raise exception 'FS-SERVED: a devotee read % rows from period_scores.', v_count;
  exception
    when insufficient_privilege then null;
    when others then
      if sqlerrm like 'FS-SERVED%' then raise; end if;
  end;

  begin
    execute 'select count(*) from public.seva_mala_periods' into v_count;
    raise exception 'FS-SERVED: a devotee read the period references.';
  exception
    when insufficient_privilege then null;
    when others then
      if sqlerrm like 'FS-SERVED%' then raise; end if;
  end;

  begin
    execute 'select count(*) from public.app_settings' into v_count;
    raise exception 'FS-SERVED: a devotee read the dials.';
  exception
    when insufficient_privilege then null;
    when others then
      if sqlerrm like 'FS-SERVED%' then raise; end if;
  end;

  -- public.donations has its own row level security: the caller sees their own
  -- three gifts and none of the congregation's twenty.
  select count(*) into v_count from public.donations;
  if v_count <> 3 then
    raise exception
      'A devotee who made three gifts can see % rows of public.donations.', v_count;
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);

-- Signed out, the lists are empty rather than everybody's.
set local role authenticated;
do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from public.my_seva_act_points(date '1970-01-01', public.seva_mala_today());
  if v_count <> 0 then
    raise exception 'A caller with no auth.uid() read % acts.', v_count;
  end if;
  select count(*) into v_count
  from public.my_giving_points(date '1970-01-01', public.seva_mala_today());
  if v_count <> 0 then
    raise exception 'A caller with no auth.uid() read % gifts.', v_count;
  end if;
  select count(*) into v_count
  from public.list_devotee_seva_act_points(
    (select ids.id from public.fs_ids ids where ids.key = 'mixed'),
    date '1970-01-01', public.seva_mala_today());
  if v_count <> 0 then
    raise exception 'A caller with no auth.uid() read % of a devotee''s acts.', v_count;
  end if;
end;
$$;
reset role;

-- The President may look, and a null devotee id is not "everybody".
set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.fs_ids ids where ids.key = 'pres'), true);

do $$
declare
  v_count integer;
  v_sum integer;
begin
  select count(*), sum(listed.points) into v_count, v_sum
  from public.list_devotee_seva_act_points(
    (select ids.id from public.fs_ids ids where ids.key = 'mixed'),
    date '1970-01-01', public.seva_mala_today()) listed;
  if v_count <> 4 then
    raise exception 'The President sees % of the four acts.', v_count;
  end if;
  if v_sum <> 242 then
    raise exception 'The President''s copy of the list comes to % rather than 242.', v_sum;
  end if;

  -- seva_mala_acts reads a null argument as "everybody", so a null that slipped
  -- through would hand over the whole congregation's history.
  select count(*) into v_count
  from public.list_devotee_seva_act_points(null, date '1970-01-01', public.seva_mala_today());
  if v_count <> 0 then
    raise exception 'A null devotee id returned % rows — the whole congregation.', v_count;
  end if;
  select count(*) into v_count
  from public.list_devotee_giving_points(null, date '1970-01-01', public.seva_mala_today());
  if v_count <> 0 then
    raise exception 'A null devotee id returned % gifts.', v_count;
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);

-- ---------------------------------------------------------------------------
-- 11. The relativity, which the soft cap must not have weakened.
--
--     Five devotees arrive, each giving $2,500. Not one existing donor gives a
--     cent more or less. The congregation's own eightieth percentile moves, and
--     therefore so does everybody's standing — which is the temple's "it depends
--     on the devotees, not hardcoded", demonstrated rather than claimed.
-- ---------------------------------------------------------------------------

do $$
declare
  v_anchor date := public.seva_mala_week_start(public.seva_mala_today()) - 1;
  v_who text;
begin
  foreach v_who in array array['whale1', 'whale2', 'whale3', 'whale4', 'whale5'] loop
    insert into public.donations (
      donor_id, donor_name, amount_cents, kind, external_payment_id, received_at
    ) values (
      (select ids.id from public.fs_ids ids where ids.key = v_who),
      v_who, 250000, 'one_time', 'fs-' || v_who,
      ((v_anchor - 2) + time '11:00') at time zone 'America/Chicago'
    );
  end loop;
end;
$$;

do $$
declare
  v_ref_before numeric;
  v_ref_after numeric;
  v_big_before numeric;
  v_big_after numeric;
  v_mid_after numeric;
  v_cents_before bigint;
  v_cents_after bigint;
begin
  select periods.giving_reference into v_ref_before
  from public.seva_mala_periods periods where periods.period_kind = 'lifetime';
  select scores.giving_norm, scores.giving_cents into v_big_before, v_cents_before
  from public.period_scores scores
  join public.seva_mala_periods periods on periods.id = scores.period_id
  join public.fs_ids ids on ids.id = scores.devotee_id
  where periods.period_kind = 'lifetime' and ids.key = 'donor_big';

  perform public.recompute_seva_mala();

  select periods.giving_reference into v_ref_after
  from public.seva_mala_periods periods where periods.period_kind = 'lifetime';
  select scores.giving_norm, scores.giving_cents into v_big_after, v_cents_after
  from public.period_scores scores
  join public.seva_mala_periods periods on periods.id = scores.period_id
  join public.fs_ids ids on ids.id = scores.devotee_id
  where periods.period_kind = 'lifetime' and ids.key = 'donor_big';

  select scores.giving_norm into v_mid_after
  from public.period_scores scores
  join public.seva_mala_periods periods on periods.id = scores.period_id
  join public.fs_ids ids on ids.id = scores.devotee_id
  where periods.period_kind = 'lifetime' and ids.key = 'donor_mid';

  if v_cents_after is distinct from v_cents_before then
    raise exception 'The $2,500 donor''s giving changed; this proves nothing.';
  end if;
  if v_ref_after <= v_ref_before then
    raise exception
      'Five more $2,500 donors did not move the congregation''s reference (% then %).',
      v_ref_before, v_ref_after;
  end if;
  if v_big_after >= v_big_before then
    raise exception
      'The $2,500 donor reads % after the congregation grew and % before, having given exactly the same.',
      v_big_after, v_big_before;
  end if;

  -- And they are now at the reference rather than above it, so the soft cap has
  -- stopped applying to them entirely — the arm a devotee stands on is decided
  -- by the congregation and by nothing else.
  if v_big_after <> 1.000000 then
    raise exception
      'The $2,500 donor is at % rather than exactly at the new eightieth percentile.',
      v_big_after;
  end if;
  if v_mid_after >= 1.0 then
    raise exception
      'The $600 donor is still at or above the reference (%) after it moved.', v_mid_after;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 12. And a bad dial is refused rather than obeyed.
--
--     The recompute reads alpha and the ceiling before it writes anything, so a
--     temple that types 2 into soft_cap_alpha gets an exception and keeps the
--     scores it had, rather than a period rebuilt under a rule nobody chose.
-- ---------------------------------------------------------------------------

do $$
declare
  v_period uuid;
  v_message text;
begin
  select periods.id into v_period
  from public.seva_mala_periods periods where periods.period_kind = 'lifetime';

  update public.app_settings set value = '2' where key = 'seva_mala.soft_cap_alpha';
  v_message := null;
  begin
    perform public.recompute_seva_mala_period(v_period);
    raise exception 'FS-SERVED: the recompute obeyed an alpha of 2.';
  exception when others then
    v_message := sqlerrm;
  end;
  if v_message like 'FS-SERVED%' then
    raise exception '%', v_message;
  end if;
  if v_message not like '%soft_cap_alpha%' or v_message not like '%[0, 1]%' then
    raise exception 'The refusal of alpha = 2 reads "%".', v_message;
  end if;

  update public.app_settings set value = '0.15' where key = 'seva_mala.soft_cap_alpha';

  -- And a beta outside [0, 1] leaves no ceiling to derive.
  update public.app_settings set value = '3' where key = 'seva_mala.balance_beta';
  v_message := null;
  begin
    perform public.seva_mala_norm_ceiling();
    raise exception 'FS-SERVED: a beta of 3 produced a ceiling.';
  exception when others then
    v_message := sqlerrm;
  end;
  if v_message like 'FS-SERVED%' then
    raise exception '%', v_message;
  end if;
  if v_message not like '%balance_beta%' then
    raise exception 'The refusal of beta = 3 reads "%".', v_message;
  end if;

  update public.app_settings set value = '0.5' where key = 'seva_mala.balance_beta';

  -- The ceiling follows beta rather than sitting at 1.5 for ever.
  update public.app_settings set value = '0.8' where key = 'seva_mala.balance_beta';
  if public.seva_mala_norm_ceiling() <> 1.8 then
    raise exception 'The ceiling is % when beta is 0.8.', public.seva_mala_norm_ceiling();
  end if;
  if public.seva_mala_points(99) <> 1800 then
    raise exception 'The published ceiling did not follow beta.';
  end if;
  update public.app_settings set value = '0.5' where key = 'seva_mala.balance_beta';
end;
$$;

do $$
begin
  raise notice 'all fair scaling checks passed';
end;
$$;

select 'fair scaling verification passed' as result;

rollback;
