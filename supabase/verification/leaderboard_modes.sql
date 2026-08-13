-- Functional verification for 202608040060_leaderboard_modes.sql.
--
-- Rolled back at the end. Every local is prefixed v_ so it can never shadow a
-- column name. Anything a devotee could really attempt is attempted as that
-- devotee, under `set local role authenticated`, so the grants, the row level
-- security and the permission checks are what is being tested rather than
-- superuser rights waving everything through.
--
-- 0060 does three things, and this file exists to prove all three happened and
-- that the parts of 202608040055 section 4 it did NOT reverse are still standing.
--
--   1. list_seva_garland publishes POINTS: the score times a thousand, rounded
--      to the nearest ten. Coarse on purpose — 0060 section 3 is the arithmetic
--      of what publishing them costs — so the test is not "there is a number"
--      but "the number is on the published grid and is not the raw score".
--
--   2. list_seva_garland takes a MODE. 'combined' ranks by score, 'seva' ranks
--      by seva_norm and publishes the seva figure on the same grid. The two
--      modes must be able to order the same two devotees differently, or the
--      parameter is decoration.
--
--   3. list_seva_supporters names who gave, with no amount, no gift count and
--      no ordering that could be a ranking.
--
-- ---------------------------------------------------------------------------
-- The fixture is arithmetic, not decoration.
--
-- Twelve devotees in the scoring cohort — past 0055's minimum of eight, so every
-- congregation-relative reference here is a real percentile of a real
-- congregation. Every act of seva is 180 minutes and every gift is a single
-- gift, so the two units fall out by construction:
--
--   v_s = 180 minutes    every devotee's median act is 180
--   v_g = 25,000 cents   ten donors, one gift each, the fifth and sixth of
--                        which are $200 and $300
--
-- Everything sits strictly BEFORE the current Chicago week begins, anchored on
-- last Sunday, which is what makes the script deterministic on any day of any
-- week: the lifetime period always contains the whole fixture and is the board
-- every ranking assertion is made against, and the running week always contains
-- none of it and is therefore the gathering case.
--
-- The seva side, u_s = ln(1 + S/180) over the eleven devotees who serve:
--
--   Ananta   2880 ln(17)=2.833213     Gopala    540 ln(4)=1.386294
--   Lalita   1080 ln(7) =1.945910     Haridasa  540 ln(4)=1.386294
--   Chandra   900 ln(6) =1.791759     Bhakta    360 ln(3)=1.098612
--   Ekadashi  720 ln(5) =1.609438     Ishvari   360 ln(3)=1.098612
--   Madhava   720 ln(5) =1.609438     Jagannatha180 ln(2)=0.693147
--                                     Kesava    180 ln(2)=0.693147
--
--   ref_s = P80 of eleven = the ninth smallest exactly = ln(6) = 1.791759
--
-- The giving side, u_g = ln(1 + G/25000) over the ten devotees who give:
--
--   Bhakta  $2,500 ln(11) =2.397895   Jagannatha $200 ln(1.8)=0.587787
--   Madhava   $900 ln(4.6)=1.526056   Haridasa   $150 ln(1.6)=0.470004
--   Damodara  $600 ln(3.4)=1.223775   Ekadashi   $100 ln(1.4)=0.336472
--   Gopala    $450 ln(2.8)=1.029619   Ishvari     $50 ln(1.2)=0.182322
--   Chandra   $300 ln(2.2)=0.788457   Kesava      $25 ln(1.1)=0.095310
--
--   ref_g = P80 of ten = ln(3.4) + 0.2*(ln(4.6) - ln(3.4)) = 1.284232
--
-- Which puts the two devotees the mode parameter exists for exactly here:
--
--   Ananta  48 hours, nothing given   s = 1.068732  g = 0.000000  score 0.712488
--   Bhakta  6 hours and $2,500        s = 0.613147  g = 1.093665  score 0.933492
--
-- (202608040062 made the cap soft, so both of these devotees, each past their
-- reference in one dimension, sit a little above where 0055 held them: Ananta at
-- 1.000000 and 0.666667 and Bhakta at 1.000000 and 0.871049 before it.)
--
-- Bhakta stands high on the combined board and Ananta well below; on the seva
-- board Ananta is FIRST and Bhakta far below. One fixture, two orders, and the
-- pair reversed between them, which is the whole content of p_rank_by.
--
-- And Ananta is the arithmetic the points assertion turns on. A score of
-- 0.712488 is 712.488 points raw; round(score * 1000) would publish 712; the
-- published grid publishes 710. 712 is not a multiple of ten, so that single
-- devotee proves the coarsening happened rather than being claimed. On the seva
-- board the same devotee publishes 1070, which is a number 0055's hard cap and
-- 0060's clamp at a thousand could not have produced.
--
-- The cast:
--   Ananta Das      16 acts, no gift    the pure sevak, and the points witness
--   Bhakta Rupa      2 acts, $2,500     second on combined, joint fourth on seva
--   Chandra Devi     5 acts, $300      first on combined, and ties Bhakta at 870
--   Damodara Das     0 acts, $600       gives only; not on the seva board at all
--   Ekadashi Devi    4 acts, $100
--   Gopala Das       3 acts, $450
--   Haridasa Das     3 acts, $150
--   Ishvari Devi     2 acts, $50
--   Jagannatha Das   1 act,  $200
--   Kesava Das       1 act,  $25
--   Lalita Devi      6 acts, no gift    serves and never gave — absent from
--                                       the supporters list
--   Madhava Das      4 acts, $900       OPTED OUT. On neither board and not a
--                                       supporter, though he gave the second
--                                       largest gift in the congregation
--   Narayana Das     nothing            app.view_all
--
-- The final row must read: leaderboard modes verification passed

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
--    The dials this file's arithmetic is a function of, the scoring rule the
--    published points are a function of, and the grants 0060 claims not to have
--    widened.
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

  -- The balance rule the published points are a rounding of.
  if public.seva_mala_score(1.0, 0.0, 0.5) <> 0.666667
    or public.seva_mala_score(0.0, 1.0, 0.5) <> 0.666667
    or public.seva_mala_score(1.0, 1.0, 0.5) <> 1.000000
  then
    raise exception 'The balance rule is not 202608040059''s.';
  end if;

  -- The half of 0055 section 4 that 0060 did NOT reverse.
  if has_table_privilege('authenticated', 'public.period_scores', 'select')
    or has_table_privilege('authenticated', 'public.seva_mala_periods', 'select')
    or has_table_privilege('authenticated', 'public.app_settings', 'select')
    or has_table_privilege('authenticated', 'public.donations', 'select')
  then
    raise exception 'authenticated can read the Seva Mala components or the amounts.';
  end if;

  -- Neither new door is open to anon.
  if has_function_privilege('anon', 'public.list_seva_garland(text, integer, text)', 'execute')
    or has_function_privilege('anon', 'public.list_seva_supporters(text)', 'execute')
    or has_function_privilege('anon', 'public.seva_mala_points(numeric)', 'execute')
  then
    raise exception 'A signed-out visitor can read the garland.';
  end if;

  -- And both are open to any signed-in devotee, which is what the temple asked
  -- for: this is recognition, not an administrative report.
  if not has_function_privilege('authenticated', 'public.list_seva_garland(text, integer, text)', 'execute')
    or not has_function_privilege('authenticated', 'public.list_seva_supporters(text)', 'execute')
  then
    raise exception 'An ordinary devotee cannot read the boards 0060 exists to serve.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 1. The signatures, and the overload that had to go.
--
--    A leftover public.list_seva_garland(text, integer) beside the defaulted
--    three-argument form makes every existing two-argument call ambiguous.
--    Asserted by counting the function and then by making the call.
-- ---------------------------------------------------------------------------

do $$
declare
  v_count integer;
  v_shape text;
begin
  select count(*) into v_count
  from pg_proc proc
  join pg_namespace spaces on spaces.oid = proc.pronamespace
  where spaces.nspname = 'public' and proc.proname = 'list_seva_garland';
  if v_count <> 1 then
    raise exception
      'There are % functions named list_seva_garland. A leftover defaulted overload is ambiguous.',
      v_count;
  end if;

  select pg_get_function_identity_arguments(proc.oid) into v_shape
  from pg_proc proc
  join pg_namespace spaces on spaces.oid = proc.pronamespace
  where spaces.nspname = 'public' and proc.proname = 'list_seva_garland';
  if v_shape <> 'p_period_kind text, p_limit integer, p_rank_by text' then
    raise exception 'list_seva_garland takes (%).', v_shape;
  end if;

  select pg_get_function_identity_arguments(proc.oid) into v_shape
  from pg_proc proc
  join pg_namespace spaces on spaces.oid = proc.pronamespace
  where spaces.nspname = 'public' and proc.proname = 'list_seva_supporters';
  if v_shape is distinct from 'p_period_kind text' then
    raise exception 'list_seva_supporters takes (%).', coalesce(v_shape, '(missing)');
  end if;
end;
$$;

-- The return shapes, in order, both of them. A column added to either of these
-- is a decision somebody has to make on purpose.
do $$
declare
  v_columns text;
begin
  select string_agg(parameters.parameter_name, ', ' order by parameters.ordinal_position)
  into v_columns
  from information_schema.parameters parameters
  where parameters.specific_schema = 'public'
    and parameters.specific_name like 'list_seva_garland%'
    and parameters.parameter_mode = 'OUT';
  if v_columns <> 'standing, devotee_id, devotee_name, devotee_photo_url, points, tier, is_you, gathering' then
    raise exception 'The garland returns (%).', v_columns;
  end if;

  select string_agg(parameters.parameter_name, ', ' order by parameters.ordinal_position)
  into v_columns
  from information_schema.parameters parameters
  where parameters.specific_schema = 'public'
    and parameters.specific_name like 'list_seva_supporters%'
    and parameters.parameter_mode = 'OUT';
  if v_columns <> 'devotee_id, devotee_name, devotee_photo_url' then
    raise exception 'The supporters list returns (%).', v_columns;
  end if;
end;
$$;

-- NO AMOUNT COLUMN AT ALL. Not a null one, not a rounded one, not a bucketed
-- one. Asserted by pattern as well as by the exact list above, so a column
-- called `given` or `cents_given` or `supporter_total` is refused too.
do $$
declare
  v_leaked text;
begin
  select string_agg(parameters.parameter_name, ', ') into v_leaked
  from information_schema.parameters parameters
  where parameters.specific_schema = 'public'
    and parameters.specific_name like 'list_seva_supporters%'
    and parameters.parameter_mode = 'OUT'
    and (
      parameters.parameter_name ilike '%amount%'
      or parameters.parameter_name ilike '%cent%'
      or parameters.parameter_name ilike '%dollar%'
      or parameters.parameter_name ilike '%gift%'
      or parameters.parameter_name ilike '%giv%'
      or parameters.parameter_name ilike '%total%'
      or parameters.parameter_name ilike '%sum%'
      or parameters.parameter_name ilike '%score%'
      or parameters.parameter_name ilike '%norm%'
      or parameters.parameter_name ilike '%point%'
      or parameters.parameter_name ilike '%rank%'
      or parameters.parameter_name ilike '%standing%'
    );
  if v_leaked is not null then
    raise exception
      'The supporters list returns %. It is recognition, not a donor wall.', v_leaked;
  end if;
end;
$$;

-- And the garland still publishes no component, no minutes and no cents. 0055's
-- own check, restated here because 0060 is the migration that added a number to
-- this board and this is the line it must not have crossed.
do $$
declare
  v_leaked text;
begin
  select string_agg(parameters.parameter_name, ', ') into v_leaked
  from information_schema.parameters parameters
  where parameters.specific_schema = 'public'
    and parameters.specific_name like 'list_seva_garland%'
    and parameters.parameter_mode = 'OUT'
    and (
      parameters.parameter_name ilike '%score%'
      or parameters.parameter_name ilike '%minute%'
      or parameters.parameter_name ilike '%cent%'
      or parameters.parameter_name ilike '%norm%'
      or parameters.parameter_name ilike '%hour%'
      or parameters.parameter_name ilike '%utility%'
      or parameters.parameter_name ilike '%unit%'
      or parameters.parameter_name ilike '%reference%'
    );
  if v_leaked is not null then
    raise exception
      'The public garland returns %. Points and a place, and nothing that inverts.',
      v_leaked;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. The published scale, as arithmetic, before any fixture exists.
--
--    A thousand to the unit, ten to the step, capped at the thousand and
--    floored at the step for anything positive.
-- ---------------------------------------------------------------------------

do $$
declare
  v_case record;
  v_got integer;
begin
  for v_case in
    select * from (values
      (null::numeric,    0),
      (0::numeric,       0),
      (-0.4::numeric,    0),
      -- Two dollars' worth of giving is still a place on the board, and a
      -- devotee standing on it is not shown "0 points" beside their own name.
      (0.000001::numeric, 10),
      (0.004::numeric,   10),
      (0.0051::numeric,  10),
      (0.014::numeric,   10),
      (0.016::numeric,   20),
      -- The witness the whole fixture turns on: 667 raw, 670 published.
      (0.666667::numeric, 670),
      (0.664999::numeric, 660),
      (0.665::numeric,    670),
      (0.523843::numeric, 520),
      (0.871049::numeric, 870),
      (1.0::numeric,     1000),
      -- 202608040062 made the cap soft and raised the ceiling to 1 + beta, so a
      -- norm above 1 publishes above a thousand and stops at 1500.
      (1.4::numeric,     1400),
      (1.5::numeric,     1500),
      (2.4::numeric,     1500)
    ) as expected(norm, points)
  loop
    v_got := public.seva_mala_points(v_case.norm);
    if v_got is distinct from v_case.points then
      raise exception 'seva_mala_points(%) is % rather than %.',
        coalesce(v_case.norm::text, 'null'), v_got, v_case.points;
    end if;
  end loop;

  -- The grid itself, over the whole range, rather than at the points this file
  -- happened to pick: every published value is a multiple of ten, never above a
  -- thousand, and never below ten for a positive norm.
  if exists (
    select 1 from generate_series(1, 1500) step
    where public.seva_mala_points(step / 1000.0) % 10 <> 0
       or public.seva_mala_points(step / 1000.0) > 1500
       or public.seva_mala_points(step / 1000.0) < 10
  ) then
    raise exception 'The published points are not on a grid of ten from 10 to 1500.';
  end if;

  -- Monotone, so coarsening can tie two devotees but can never reorder them.
  if exists (
    select 1 from generate_series(1, 999) step
    where public.seva_mala_points(step / 1000.0)
        > public.seva_mala_points((step + 1) / 1000.0)
  ) then
    raise exception 'The published points are not monotone in the score.';
  end if;

  -- And it is genuinely coarser than the scale the client was rendering. If
  -- these two ever agree everywhere, the step has been set back to one.
  if (select count(*) from generate_series(1, 1000) step
      where public.seva_mala_points(step / 1000.0) <> round(step / 1000.0 * 1000)) < 500
  then
    raise exception
      'The published points are round(score * 1000) in all but a handful of cases; nothing was coarsened.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. The congregation.
-- ---------------------------------------------------------------------------

create table public.lm_ids (key text primary key, id uuid not null);
grant select on public.lm_ids to authenticated;

do $$
declare
  v_who record;
  v_i integer := 0;
begin
  for v_who in
    select * from (values
      ('ananta',     'Ananta Das'),
      ('bhakta',     'Bhakta Rupa'),
      ('chandra',    'Chandra Devi'),
      ('damodara',   'Damodara Das'),
      ('ekadashi',   'Ekadashi Devi'),
      ('gopala',     'Gopala Das'),
      ('haridasa',   'Haridasa Das'),
      ('ishvari',    'Ishvari Devi'),
      ('jagannatha', 'Jagannatha Das'),
      ('kesava',     'Kesava Das'),
      ('lalita',     'Lalita Devi'),
      ('madhava',    'Madhava Das'),
      ('narayana',   'Narayana Das')
    ) as cast_member(key, name)
  loop
    v_i := v_i + 1;
    insert into auth.users (id, email, raw_user_meta_data)
    values (
      ('60000000-0000-0000-0000-0000000000' || lpad(v_i::text, 2, '0'))::uuid,
      'lm-' || v_who.key || '@example.test',
      jsonb_build_object('name', v_who.name)
    );

    update public.users
    set name = v_who.name,
        photo_url = 'https://lh3.googleusercontent.com/' || v_who.key
    where users.email = 'lm-' || v_who.key || '@example.test';

    insert into public.lm_ids (key, id)
    select v_who.key, users.id
    from public.users where users.email = 'lm-' || v_who.key || '@example.test';
  end loop;
end;
$$;

update public.users
set role_id = (select roles.id from public.roles where roles.name = 'president')
where users.email = 'lm-narayana@example.test';

-- Everybody opts in but Madhava, who is the devotee this file uses to prove
-- that opting out is honoured in both modes and on the supporters list.
update public.users
set leaderboard_visible = (users.email <> 'lm-madhava@example.test')
where users.email like 'lm-%@example.test';

-- ---------------------------------------------------------------------------
-- 4. The facts.
--
--    Every act 180 minutes, so v_s is 180 by construction. Every gift a single
--    gift, so v_g is the plain median of ten. All of it strictly before this
--    week began, anchored on last Sunday, and laid out at most two acts a day
--    and eight a week so that nobody reaches the 480-minute day or the
--    1,800-minute week and credited minutes are served minutes.
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
      ('ananta',     16, 2),
      ('lalita',      6, 1),
      ('chandra',     5, 1),
      ('ekadashi',    4, 1),
      ('madhava',     4, 1),
      ('gopala',      3, 1),
      ('haridasa',    3, 1),
      ('bhakta',      2, 1),
      ('ishvari',     2, 1),
      ('jagannatha',  1, 1),
      ('kesava',      1, 1)
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
        (select ids.id from public.lm_ids ids where ids.key = v_plan.who),
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
      ('bhakta',     250000),
      ('madhava',     90000),
      ('damodara',    60000),
      ('gopala',      45000),
      ('chandra',     30000),
      ('jagannatha',  20000),
      ('haridasa',    15000),
      ('ekadashi',    10000),
      ('ishvari',      5000),
      ('kesava',       2500)
    ) as gift(who, cents)
  loop
    insert into public.donations (
      donor_id, donor_name, amount_cents, kind, external_payment_id, received_at
    ) values (
      (select ids.id from public.lm_ids ids where ids.key = v_gift.who),
      v_gift.who, v_gift.cents, 'one_time', 'lm-' || v_gift.who || '-1',
      ((v_anchor - 2) + time '10:00') at time zone 'America/Chicago'
    );
  end loop;
end;
$$;

select public.recompute_seva_mala() as periods_computed;

-- ---------------------------------------------------------------------------
-- 5. The units and the references, checked before anything is concluded from
--    them, so a moved median fails here and says so.
-- ---------------------------------------------------------------------------

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
  if v_period.giving_unit_cents <> 25000 then
    raise exception 'v_g is % rather than the 25,000-cent median gift.', v_period.giving_unit_cents;
  end if;
  if round(v_period.seva_reference, 6) <> 1.791759 then
    raise exception 'ref_s is % rather than ln(6) = 1.791759.', round(v_period.seva_reference, 6);
  end if;
  if round(v_period.giving_reference, 6) <> 1.284232 then
    raise exception 'ref_g is % rather than 1.284232.', round(v_period.giving_reference, 6);
  end if;
  if v_period.participant_count <> 12 then
    raise exception 'The lifetime cohort is % rather than 12.', v_period.participant_count;
  end if;
  if v_period.participant_count
     < public.seva_mala_number('seva_mala.minimum_cohort', 8) then
    raise exception 'The fixture is below the minimum cohort, so no board publishes.';
  end if;

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

-- The two devotees the mode parameter exists for, with their real numbers.
do $$
declare
  v_row record;
begin
  for v_row in
    select * from (values
      -- 202608040062 made the cap soft: both of these devotees are past their
      -- reference in one dimension, so both moved up.
      ('ananta', 1.068732, 0.000000, 0.712488),
      ('bhakta', 0.613147, 1.093665, 0.933492)
    ) as expected(who, seva_norm, giving_norm, score)
  loop
    if not exists (
      select 1 from public.period_scores scores
      join public.seva_mala_periods periods on periods.id = scores.period_id
      join public.lm_ids ids on ids.id = scores.devotee_id
      where periods.period_kind = 'lifetime'
        and ids.key = v_row.who
        and scores.seva_norm = v_row.seva_norm
        and scores.giving_norm = v_row.giving_norm
        and scores.score = v_row.score
    ) then
      raise exception
        '% is not (s=%, g=%, score=%) but %.',
        v_row.who, v_row.seva_norm, v_row.giving_norm, v_row.score,
        (select format('(s=%s, g=%s, score=%s)', scores.seva_norm, scores.giving_norm, scores.score)
         from public.period_scores scores
         join public.seva_mala_periods periods on periods.id = scores.period_id
         join public.lm_ids ids on ids.id = scores.devotee_id
         where periods.period_kind = 'lifetime' and ids.key = v_row.who);
    end if;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. The boards, read as an ordinary devotee and kept for inspection.
--
--    Captured here, under `authenticated`, and every assertion about them made
--    afterwards against public.period_scores, which the devotee who read them
--    cannot see.
-- ---------------------------------------------------------------------------

create table public.lm_board (
  mode text not null,
  ord integer not null,
  standing integer,
  devotee_id uuid,
  devotee_name text,
  devotee_photo_url text,
  points integer,
  tier text,
  is_you boolean,
  gathering boolean
);
grant select, insert on public.lm_board to authenticated;

create table public.lm_supporters (
  ord integer not null,
  devotee_id uuid,
  devotee_name text,
  devotee_photo_url text
);
grant select, insert on public.lm_supporters to authenticated;

set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.lm_ids ids where ids.key = 'kesava'), true);

insert into public.lm_board (
  mode, ord, standing, devotee_id, devotee_name, devotee_photo_url,
  points, tier, is_you, gathering
)
select 'combined', garland.ord, garland.standing, garland.devotee_id,
       garland.devotee_name, garland.devotee_photo_url, garland.points,
       garland.tier, garland.is_you, garland.gathering
from public.list_seva_garland('lifetime', 50, 'combined')
     with ordinality as garland(
       standing, devotee_id, devotee_name, devotee_photo_url,
       points, tier, is_you, gathering, ord
     );

insert into public.lm_board (
  mode, ord, standing, devotee_id, devotee_name, devotee_photo_url,
  points, tier, is_you, gathering
)
select 'seva', garland.ord, garland.standing, garland.devotee_id,
       garland.devotee_name, garland.devotee_photo_url, garland.points,
       garland.tier, garland.is_you, garland.gathering
from public.list_seva_garland('lifetime', 50, 'seva')
     with ordinality as garland(
       standing, devotee_id, devotee_name, devotee_photo_url,
       points, tier, is_you, gathering, ord
     );

-- The two-argument call every existing caller makes still resolves, and still
-- means 'combined'.
insert into public.lm_board (
  mode, ord, standing, devotee_id, devotee_name, devotee_photo_url,
  points, tier, is_you, gathering
)
select 'default', garland.ord, garland.standing, garland.devotee_id,
       garland.devotee_name, garland.devotee_photo_url, garland.points,
       garland.tier, garland.is_you, garland.gathering
from public.list_seva_garland('lifetime', 50)
     with ordinality as garland(
       standing, devotee_id, devotee_name, devotee_photo_url,
       points, tier, is_you, gathering, ord
     );

insert into public.lm_supporters (ord, devotee_id, devotee_name, devotee_photo_url)
select supporters.ord, supporters.devotee_id, supporters.devotee_name,
       supporters.devotee_photo_url
from public.list_seva_supporters('lifetime')
     with ordinality as supporters(devotee_id, devotee_name, devotee_photo_url, ord);

reset role;
select set_config('request.jwt.claim.sub', '', true);

-- ---------------------------------------------------------------------------
-- 7. Points, published, and matching the stored score on the published scale.
--
--    Re-derived from public.period_scores rather than compared against numbers
--    typed into this file, so a change to the scoring cannot be papered over by
--    a change to the expectations.
-- ---------------------------------------------------------------------------

do $$
declare
  v_bad text;
  v_rows integer;
begin
  -- Combined mode: the points are the stored score on the grid.
  select string_agg(
           checked.devotee_name || ': published ' || checked.points
             || ', stored score ' || checked.score
             || ' which is ' || checked.expected, '; '),
         count(*)
  into v_bad, v_rows
  from (
    select board.devotee_name, board.points, scores.score,
           round(scores.score * 1000 / 10.0) * 10 as expected
    from public.lm_board board
    join public.period_scores scores on scores.devotee_id = board.devotee_id
    join public.seva_mala_periods periods on periods.id = scores.period_id
    where board.mode = 'combined'
      and periods.period_kind = 'lifetime'
  ) checked
  where checked.points is distinct from checked.expected::integer;

  if v_rows > 0 then
    raise exception 'The combined board publishes points that are not the stored score: %.', v_bad;
  end if;

  -- Seva mode: the points are seva_norm on the SAME grid, and not the score.
  select string_agg(
           checked.devotee_name || ': published ' || checked.points
             || ', stored seva_norm ' || checked.seva_norm, '; '),
         count(*)
  into v_bad, v_rows
  from (
    select board.devotee_name, board.points, scores.seva_norm,
           round(scores.seva_norm * 1000 / 10.0) * 10 as expected
    from public.lm_board board
    join public.period_scores scores on scores.devotee_id = board.devotee_id
    join public.seva_mala_periods periods on periods.id = scores.period_id
    where board.mode = 'seva'
      and periods.period_kind = 'lifetime'
  ) checked
  where checked.points is distinct from checked.expected::integer;

  if v_rows > 0 then
    raise exception 'The seva board publishes points that are not seva_norm: %.', v_bad;
  end if;
end;
$$;

do $$
declare
  v_points integer;
  v_rows integer;
begin
  -- Every published number is on the grid, and every devotee on a board has one.
  if exists (
    select 1 from public.lm_board board
    where not board.gathering
      and (board.points is null or board.points % 10 <> 0
           or board.points < 10 or board.points > 1500)
  ) then
    raise exception 'A board published points off the grid.';
  end if;

  -- The pure sevak: 0.712488 stored, 712 on the client's old scale, 710 here.
  -- One devotee is enough to prove the coarsening is real rather than nominal.
  select board.points into v_points
  from public.lm_board board
  join public.lm_ids ids on ids.id = board.devotee_id
  where board.mode = 'combined' and ids.key = 'ananta';
  if v_points <> 710 then
    raise exception 'Ananta publishes % rather than 710 combined points.', v_points;
  end if;
  if v_points = 712 then
    raise exception 'Ananta publishes the raw round(score * 1000).';
  end if;

  -- On the seva board the same devotee is past the congregation's reference,
  -- which 202608040062 publishes ABOVE a thousand rather than flattening to it.
  select board.points into v_points
  from public.lm_board board
  join public.lm_ids ids on ids.id = board.devotee_id
  where board.mode = 'seva' and ids.key = 'ananta';
  if v_points <> 1070 then
    raise exception 'Ananta publishes % rather than 1070 seva points.', v_points;
  end if;

  -- Points never rise as the place falls, in either mode. Coarsening may tie
  -- two neighbours; it must never reorder them.
  select count(*) into v_rows
  from public.lm_board higher
  join public.lm_board lower
    on lower.mode = higher.mode
   and lower.standing > higher.standing
  where higher.mode in ('combined', 'seva')
    and lower.points > higher.points;
  if v_rows > 0 then
    raise exception '% pairs of devotees are ranked against their own points.', v_rows;
  end if;

  -- The defaulted two-argument call is the combined board, row for row.
  if exists (
    select 1 from public.lm_board defaulted
    full outer join public.lm_board combined
      on combined.mode = 'combined' and combined.ord = defaulted.ord
    where defaulted.mode = 'default'
      and (combined.devotee_id is distinct from defaulted.devotee_id
           or combined.points is distinct from defaulted.points
           or combined.standing is distinct from defaulted.standing)
  ) then
    raise exception 'list_seva_garland(text, integer) is no longer the combined board.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. The mode is not decoration: two devotees, two orders.
-- ---------------------------------------------------------------------------

do $$
declare
  v_ananta_combined integer;
  v_bhakta_combined integer;
  v_ananta_seva integer;
  v_bhakta_seva integer;
  v_rows integer;
begin
  select board.standing into v_ananta_combined from public.lm_board board
  join public.lm_ids ids on ids.id = board.devotee_id
  where board.mode = 'combined' and ids.key = 'ananta';
  select board.standing into v_bhakta_combined from public.lm_board board
  join public.lm_ids ids on ids.id = board.devotee_id
  where board.mode = 'combined' and ids.key = 'bhakta';
  select board.standing into v_ananta_seva from public.lm_board board
  join public.lm_ids ids on ids.id = board.devotee_id
  where board.mode = 'seva' and ids.key = 'ananta';
  select board.standing into v_bhakta_seva from public.lm_board board
  join public.lm_ids ids on ids.id = board.devotee_id
  where board.mode = 'seva' and ids.key = 'bhakta';

  if v_bhakta_combined >= v_ananta_combined then
    raise exception
      'Bhakta ($2,500 and six hours) stands at % and Ananta (forty-eight hours) at % on the combined board.',
      v_bhakta_combined, v_ananta_combined;
  end if;
  if v_ananta_seva >= v_bhakta_seva then
    raise exception
      'Ananta stands at % and Bhakta at % on the SEVA board — the mode changed nothing.',
      v_ananta_seva, v_bhakta_seva;
  end if;
  if v_ananta_seva <> 1 then
    raise exception 'The devotee with the most seva is % on the seva board.', v_ananta_seva;
  end if;

  -- The seva board is ranked by seva and by nothing else: every stored
  -- seva_norm ordering is honoured, and dense, over the opted-in.
  select count(*) into v_rows
  from public.lm_board higher
  join public.period_scores high_scores on high_scores.devotee_id = higher.devotee_id
  join public.lm_board lower on lower.mode = higher.mode
  join public.period_scores low_scores on low_scores.devotee_id = lower.devotee_id
  join public.seva_mala_periods periods on periods.id = high_scores.period_id
  where higher.mode = 'seva'
    and periods.period_kind = 'lifetime'
    and low_scores.period_id = high_scores.period_id
    and higher.standing < lower.standing
    and high_scores.seva_norm <= low_scores.seva_norm;
  if v_rows > 0 then
    raise exception 'The seva board is not ordered by seva_norm (% inversions).', v_rows;
  end if;

  -- Dense: the places run 1..n with no gaps, in both modes.
  for v_rows in
    select 1 from (values ('combined'), ('seva')) as modes(mode)
    where (select count(distinct board.standing) from public.lm_board board
           where board.mode = modes.mode)
        <> (select max(board.standing) from public.lm_board board
            where board.mode = modes.mode)
  loop
    raise exception 'A board has gaps in its places; the ranking is not dense.';
  end loop;

  -- A devotee who gave and never served is on the combined board and is NOT on
  -- the seva board. The basis is the filter as well as the ordering.
  if not exists (
    select 1 from public.lm_board board
    join public.lm_ids ids on ids.id = board.devotee_id
    where board.mode = 'combined' and ids.key = 'damodara'
  ) then
    raise exception 'Damodara gave $600 and is not on the combined board.';
  end if;
  if exists (
    select 1 from public.lm_board board
    join public.lm_ids ids on ids.id = board.devotee_id
    where board.mode = 'seva' and ids.key = 'damodara'
  ) then
    raise exception 'Damodara never served and is on the seva board.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 9. Opting out is honoured in both modes and on the supporters list.
--
--    Madhava has the second largest gift in the congregation and a score that
--    would place him near the top. He asked not to be seen.
-- ---------------------------------------------------------------------------

do $$
declare
  v_score numeric;
begin
  select scores.score into v_score
  from public.period_scores scores
  join public.seva_mala_periods periods on periods.id = scores.period_id
  join public.lm_ids ids on ids.id = scores.devotee_id
  where periods.period_kind = 'lifetime' and ids.key = 'madhava';
  if coalesce(v_score, 0) <= 0 then
    raise exception
      'Madhava has no score, so his absence from the boards proves nothing about opting out.';
  end if;

  if exists (
    select 1 from public.lm_board board
    join public.lm_ids ids on ids.id = board.devotee_id
    where ids.key = 'madhava'
  ) then
    raise exception 'The devotee who opted out is on a board.';
  end if;

  if exists (
    select 1 from public.lm_supporters supporters
    join public.lm_ids ids on ids.id = supporters.devotee_id
    where ids.key = 'madhava'
  ) then
    raise exception 'The devotee who opted out is named as a supporter.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 10. Supporters: who gave, and nothing else about it.
-- ---------------------------------------------------------------------------

do $$
declare
  v_rows integer;
  v_names text;
  v_amounts text;
  v_up integer;
  v_down integer;
begin
  select count(*) into v_rows from public.lm_supporters;
  if v_rows <> 9 then
    raise exception
      'The supporters list names % devotees rather than the nine opted-in givers.', v_rows;
  end if;

  -- Every name on it gave something in the period, and everybody who gave and
  -- opted in is on it.
  if exists (
    select 1 from public.lm_supporters supporters
    where not exists (
      select 1 from public.period_scores scores
      join public.seva_mala_periods periods on periods.id = scores.period_id
      where scores.devotee_id = supporters.devotee_id
        and periods.period_kind = 'lifetime'
        and scores.giving_cents > 0
    )
  ) then
    raise exception 'Somebody who gave nothing is named as a supporter.';
  end if;

  select count(*) into v_rows
  from public.period_scores scores
  join public.seva_mala_periods periods on periods.id = scores.period_id
  join public.users on users.id = scores.devotee_id
  where periods.period_kind = 'lifetime'
    and scores.giving_cents > 0
    and users.leaderboard_visible
    and not exists (
      select 1 from public.lm_supporters supporters
      where supporters.devotee_id = scores.devotee_id
    );
  if v_rows > 0 then
    raise exception '% opted-in givers are missing from the supporters list.', v_rows;
  end if;

  -- The two devotees who served and never gave are absent. Serving is not
  -- supporting, on this screen.
  if exists (
    select 1 from public.lm_supporters supporters
    join public.lm_ids ids on ids.id = supporters.devotee_id
    where ids.key in ('ananta', 'lalita')
  ) then
    raise exception 'A devotee who gave nothing is on the supporters list.';
  end if;

  -- ORDERED BY NAME. The order the function returned, compared against the
  -- order sorting the same names would produce.
  select string_agg(supporters.devotee_name, ' | ' order by supporters.ord)
  into v_names from public.lm_supporters supporters;
  if v_names <> (
    select string_agg(supporters.devotee_name, ' | ' order by supporters.devotee_name)
    from public.lm_supporters supporters
  ) then
    raise exception 'The supporters list came back in the order: %.', v_names;
  end if;

  -- And NOT by giving, in either direction. The amounts, read in the order the
  -- list came back, must rise somewhere and fall somewhere — a sequence that
  -- only rises or only falls is an amount ranking with the numbers hidden.
  select
    count(*) filter (where later.cents > earlier.cents),
    count(*) filter (where later.cents < earlier.cents),
    string_agg(earlier.cents::text, ' > ' order by earlier.ord)
  into v_up, v_down, v_amounts
  from (
    select supporters.ord, scores.giving_cents as cents
    from public.lm_supporters supporters
    join public.period_scores scores on scores.devotee_id = supporters.devotee_id
    join public.seva_mala_periods periods on periods.id = scores.period_id
    where periods.period_kind = 'lifetime'
  ) earlier
  left join (
    select supporters.ord, scores.giving_cents as cents
    from public.lm_supporters supporters
    join public.period_scores scores on scores.devotee_id = supporters.devotee_id
    join public.seva_mala_periods periods on periods.id = scores.period_id
    where periods.period_kind = 'lifetime'
  ) later on later.ord = earlier.ord + 1;

  if v_up = 0 or v_down = 0 then
    raise exception
      'The supporters list is monotone in giving (% rises, % falls): %. That is a ranking.',
      v_up, v_down, v_amounts;
  end if;

  -- The largest giver in the congregation is not first, and the smallest is not
  -- last. Stated separately because it is the thing a reader would check by eye.
  if (select supporters.devotee_name from public.lm_supporters supporters
      where supporters.ord = 1) <> 'Bhakta Rupa' then
    raise exception 'The supporters list does not begin alphabetically.';
  end if;
  if (select supporters.devotee_name from public.lm_supporters supporters
      order by supporters.ord desc limit 1) <> 'Kesava Das' then
    raise exception 'The supporters list does not end alphabetically.';
  end if;
end;
$$;

-- Any devotee may call it, including one who has never given a rupee, and it
-- says the same thing to all of them.
set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.lm_ids ids where ids.key = 'ananta'), true);

do $$
declare
  v_seen text;
begin
  select string_agg(supporters.devotee_name, ' | ' order by supporters.devotee_name)
  into v_seen from public.list_seva_supporters('lifetime') supporters;

  if v_seen is distinct from (
    select string_agg(supporters.devotee_name, ' | ' order by supporters.devotee_name)
    from public.lm_supporters supporters
  ) then
    raise exception 'A devotee who never gave sees a different supporters list.';
  end if;

  -- A signed-in devotee, and only a signed-in devotee.
  if (select count(*) from public.list_seva_supporters('lifetime')) = 0 then
    raise exception 'A signed-in devotee sees no supporters at all.';
  end if;
end;
$$;

select set_config('request.jwt.claim.sub', '', true);

do $$
declare
  v_rows integer;
begin
  select count(*) into v_rows from public.list_seva_supporters('lifetime');
  if v_rows <> 0 then
    raise exception 'A caller with no auth.uid() read % supporters.', v_rows;
  end if;
  select count(*) into v_rows from public.list_seva_garland('lifetime', 50, 'combined');
  if v_rows <> 0 then
    raise exception 'A caller with no auth.uid() read % rows of the garland.', v_rows;
  end if;
end;
$$;

reset role;

-- ---------------------------------------------------------------------------
-- 11. The gathering rule, in both modes.
--
--     The running week contains none of the fixture, so it is a congregation of
--     nobody and neither mode may publish a ranking of it. One row, everything
--     null, and a flag — not an empty set, because an empty board and a withheld
--     board must not look the same to a phone.
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.lm_ids ids where ids.key = 'ananta'), true);

do $$
declare
  v_mode text;
  v_row record;
  v_rows integer;
begin
  foreach v_mode in array array['combined', 'seva'] loop
    execute format(
      'select count(*) from public.list_seva_garland(''week'', 20, %L)', v_mode)
    into v_rows;
    if v_rows <> 1 then
      raise exception
        'A week with nobody in it returned % rows in % mode rather than one gathering row.',
        v_rows, v_mode;
    end if;

    execute format(
      'select garland.standing, garland.points, garland.gathering, garland.devotee_id
       from public.list_seva_garland(''week'', 20, %L) garland', v_mode)
    into v_row;

    if not v_row.gathering then
      raise exception 'The thin week did not raise the gathering flag in % mode.', v_mode;
    end if;
    if v_row.standing is not null or v_row.devotee_id is not null then
      raise exception 'The thin week published a place in % mode.', v_mode;
    end if;
    if v_row.points is not null then
      raise exception
        'The thin week published % points in % mode. A withheld board publishes nothing.',
        v_row.points, v_mode;
    end if;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- 12. An unknown mode is refused, out loud.
--
--     Not silently treated as 'combined', and not silently returning nothing:
--     a board that answers a typo with an empty list is a board somebody will
--     ship a broken screen against.
-- ---------------------------------------------------------------------------

do $$
declare
  v_case text;
  v_count integer;
  v_message text;
begin
  foreach v_case in array array['giving', 'Combined', 'SEVA', '', 'dana', ' seva'] loop
    v_message := null;
    begin
      select count(*) into v_count
      from public.list_seva_garland('lifetime', 50, v_case);
      raise exception 'LM-SERVED: the garland answered to the mode "%" with % rows.',
        v_case, v_count;
    exception when others then
      v_message := sqlerrm;
    end;

    if v_message like 'LM-SERVED%' then
      raise exception '%', v_message;
    end if;
    if v_message not like '%combined%' or v_message not like '%seva%' then
      raise exception
        'The refusal of the mode "%" reads "%" and does not name the modes there are.',
        v_case, v_message;
    end if;
  end loop;

  -- Null is not a mode either. It is the reading "we do not know what board you
  -- asked for", and the safe answer to that is to ask again.
  v_message := null;
  begin
    select count(*) into v_count
    from public.list_seva_garland('lifetime', 50, null);
    raise exception 'LM-SERVED: the garland answered to a null mode with % rows.', v_count;
  exception when others then
    v_message := sqlerrm;
  end;
  if v_message like 'LM-SERVED%' then
    raise exception '%', v_message;
  end if;
  if v_message not like '%combined%' then
    raise exception 'The refusal of a null mode reads "%".', v_message;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 13. Nothing here opened a door.
--
--     The half of 0055 section 4 that 0060 did not reverse, proved as the
--     devotee who would really attempt it.
-- ---------------------------------------------------------------------------

do $$
declare
  v_count integer;
begin
  begin
    execute 'select count(*) from public.period_scores' into v_count;
    raise exception 'A signed-in devotee read % rows from period_scores.', v_count;
  exception
    when insufficient_privilege then null;
    when others then
      if sqlstate = 'P0001' then raise; end if;
  end;

  begin
    execute 'select count(*) from public.seva_mala_periods' into v_count;
    raise exception 'A signed-in devotee read the period references.';
  exception
    when insufficient_privilege then null;
    when others then
      if sqlstate = 'P0001' then raise; end if;
  end;

  -- public.donations has its own row level security and a column grant, so the
  -- test is not that the read is refused but that it returns NOTHING that is not
  -- the caller's own. Ananta never gave; the congregation made ten gifts.
  select count(*) into v_count from public.donations;
  if v_count <> 0 then
    raise exception
      'A devotee who never gave can see % of the congregation''s ten gifts.', v_count;
  end if;

  begin
    execute 'select count(*) from public.app_settings' into v_count;
    raise exception 'A signed-in devotee read the dials.';
  exception
    when insufficient_privilege then null;
    when others then
      if sqlstate = 'P0001' then raise; end if;
  end;

  -- The one function that does return the components refuses to answer anybody
  -- without app.view_all, and Ananta does not have it.
  select count(*) into v_count from public.list_all_seva_scores('lifetime');
  if v_count <> 0 then
    raise exception
      'A plain devotee read % rows of seva_norm and giving_norm out of list_all_seva_scores.',
      v_count;
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);

-- The components are not published to a non-admin ANYWHERE. Every function an
-- ordinary devotee may execute is checked, and the only one whose return
-- mentions a norm must be the admin board — which section 13 has just shown
-- answers a plain devotee with nothing.
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

-- And the President still sees everything, so nothing in 0060 narrowed the one
-- board that is allowed to be complete.
set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.lm_ids ids where ids.key = 'narayana'), true);

do $$
declare
  v_count integer;
  v_hidden integer;
begin
  select count(*), count(*) filter (where everyone.is_hidden)
  into v_count, v_hidden
  from public.list_all_seva_scores('lifetime') everyone;

  if v_count <> 12 then
    raise exception 'The President sees % devotees rather than 12.', v_count;
  end if;
  if v_hidden <> 1 then
    raise exception 'The President sees % devotees flagged as hidden rather than one.', v_hidden;
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);

do $$
begin
  raise notice 'all leaderboard modes checks passed';
end;
$$;

select 'leaderboard modes verification passed' as result;

rollback;
