-- Functional verification for 202608040055_seva_mala.sql.
--
-- Rolled back at the end. Every local is prefixed v_ so it can never shadow a
-- column name. Anything that must be refused is attempted as the devotee who
-- would really attempt it, under `set local role authenticated`, so the row
-- level security policies, the column grants and the permission checks are
-- what is being tested rather than superuser rights waving everything through.
--
-- ---------------------------------------------------------------------------
-- The fixture is arithmetic, not decoration.
--
-- Twelve devotees, one service type (so the measured scarcity weight is
-- exactly 1.0 and the seva arithmetic is clean), fifty-three acts of seva and
-- ten gifts, all placed strictly BEFORE the current Chicago week begins. That
-- last detail is what makes the script deterministic on any day of any week:
--
--   * the lifetime period always contains the whole fixture, so it is the
--     rich board every ranking assertion is made against;
--   * the current week always contains none of it, so it is the thin period
--     the minimum-cohort rule is proved on;
--   * the week the fixture sits in always ended yesterday-or-earlier, so it is
--     the closed period freezing and the rivalrous awards are proved on.
--
-- Every number below was worked out by hand before it was run:
--
--   v_s = 120 minutes   the median of 53 acts: four of 60, thirty-seven of
--                       120, twelve of 300
--   v_g = 17,500 cents  the median of ten gifts
--   ref_s = 2.1916      the 80th percentile of ln(1 + S/120) over ten servers
--   ref_g = 1.2952      the 80th percentile of ln(1 + G/17500) over ten donors
--
-- and the cast is built so that the three devotees the temple argued about
-- land exactly where the design says they must:
--
--   Hands    60 hours, $0        u_s = ln(31) = 3.434 > ref_s  ->  ŝ = 1, ĝ = 0
--   Purse    0 hours, $2,500     u_g = ln(15.3) = 2.727 > ref_g ->  ŝ = 0, ĝ = 1
--   Balance  20 hours, $800      both over reference           ->  ŝ = 1, ĝ = 1
--
--   score(Hands) = score(Purse) = (1 + 0.5·0)/1.5 = 0.666667   EQUAL
--   score(Balance)               = (1 + 0.5·1)/1.5 = 1.000000   HALF AS MUCH AGAIN
--
-- 202608040062_fair_scaling.sql then made that cap SOFT, at the temple's
-- instruction, because holding a $2,500 gift and a $600 gift at the same 1.0 was
-- its own unfairness. Above the reference the norm is 1 + 0.15·ln(u/ref), railed
-- at 1 + beta. All three of the devotees above are past their reference, so all
-- three moved: Hands to 0.711574, Purse to 0.741117 and Balance to 1.032727.
-- Hands and Purse are no longer EQUAL because they were never at the same
-- standing — Purse's giving is 2.11 times the congregation's giving reference
-- and Hands's seva is 1.57 times its seva reference — and equality at equal
-- standing, which is what the temple actually asked for, is proved twice over in
-- fair_scaling.sql. Everything this file asserts about the shape of the answer
-- is unchanged: one offering alone reaches roughly two thirds, doing both wins
-- outright, and doubling the largest gift in the congregation buys a few percent.
--
-- 202608040059_seva_mala_fairness.sql inverted the balance rule at the temple's
-- instruction: the LARGER of a devotee's two offerings counts whole and the
-- smaller counts for beta of itself. Sixty hours and nothing given, and $2,500
-- and no time to serve, are now two thirds of the way up rather than a third,
-- and they are still exactly equal to each other. Giving both still wins
-- outright.
--
-- and Bhakta — four hours and seventy-five dollars — now comes in BEHIND both
-- of them at 0.425978, where under the old rule they beat both at 0.350681.
-- That single row is the change. A devotee moderate at both no longer outranks
-- a devotee who is exceptional at one, because the temple said that was unfair
-- to the devotee who has time but no money and to the devotee who has money but
-- no time. If a change makes that row false, this script fails.
--
-- The cast:
--   Hands    ...0001  sixty hours, nothing given
--   Purse    ...0002  $2,500, no seva. Gives twice more, later, to no effect
--   Balance  ...0003  twenty hours and $800 — the devotee the design is for
--   Steady   ...0004  ten hours and $200
--   Gauri    ...0005  eight hours and $150
--   Asha     ...0006  six hours and $100
--   Bhakta   ...0007  four hours and $75 — beats Hands and Purse
--   Chandra  ...0008  two hours and $50
--   Lila     ...0009  ten hours, nothing given
--   Nanda    ...0010  $300, no seva
--   Kirtan   ...0011  three hours and $25
--   Hidden   ...0012  fifteen hours and $400, and OPTED OUT. Scored, ranked,
--                     awarded, and invisible on the board.
--   Whale    ...0013  arrives late, in section 12, to be an outlier
--   President...0020  app.view_all
--   Caps     ...0021  serves impossible hours, in section 15
--   Q1..Q5   ...0031  the five quality multipliers, in section 14
--
-- The final row must read: seva mala verification passed

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
--    Every dial this migration depends on, asserted rather than assumed. A
--    later migration that changes beta or the percentile changes every number
--    in this file, and it should have to say so here first.
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
      ('seva_mala.minimum_cohort', '8'),
      ('seva_mala.weight_min', '0.75'),
      ('seva_mala.weight_max', '1.75')
    ) as expected(key, value)
    left join public.app_settings settings on settings.key = expected.key
  loop
    if v_expected <> v_actual then
      raise exception 'Seva Mala dial mismatch: expected %, found %.', v_expected, v_actual;
    end if;
  end loop;

  -- Beta and the percentile must live in app_settings and NOT be typed into a
  -- function body. If somebody inlines them, this catches it.
  if position('0.5' in pg_get_functiondef(
       'public.recompute_seva_mala_period(uuid)'::regprocedure)) > 0
     and position('seva_mala.balance_beta' in pg_get_functiondef(
       'public.recompute_seva_mala_period(uuid)'::regprocedure)) = 0
  then
    raise exception 'balance_beta was inlined into recompute_seva_mala_period.';
  end if;

  if position('seva_mala.reference_quantile' in pg_get_functiondef(
       'public.recompute_seva_mala_period(uuid)'::regprocedure)) = 0
  then
    raise exception 'The reference percentile is not read from app_settings.';
  end if;

  -- Nobody may read the dials. They are not secret in themselves, but ref_g
  -- and v_g together are half of a devotee's giving.
  if has_table_privilege('authenticated', 'public.app_settings', 'select') then
    raise exception 'authenticated can read app_settings.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 1. The congregation.
-- ---------------------------------------------------------------------------

do $$
declare
  v_who text;
  v_i integer := 0;
begin
  foreach v_who in array array[
    'hands', 'purse', 'balance', 'steady', 'gauri', 'asha',
    'bhakta', 'chandra', 'lila', 'nanda', 'kirtan', 'hidden', 'whale'
  ] loop
    v_i := v_i + 1;
    insert into auth.users (id, email, raw_user_meta_data)
    values (
      ('50000000-0000-0000-0000-0000000000' || lpad(v_i::text, 2, '0'))::uuid,
      'sm-' || v_who || '@example.test',
      jsonb_build_object('name', initcap(v_who) || ' Das')
    );
  end loop;
end;
$$;

insert into auth.users (id, email, raw_user_meta_data) values
  ('50000000-0000-0000-0000-000000000020', 'sm-president@example.test',
   '{"name":"Radha President"}'),
  ('50000000-0000-0000-0000-000000000021', 'sm-caps@example.test',
   '{"name":"Caps Das"}');

update public.users
set role_id = (select roles.id from public.roles where roles.name = 'president')
where users.email = 'sm-president@example.test';

-- Ordinary table rather than a temporary one, so reading it under the
-- authenticated role needs no assumptions about the temp schema. The whole
-- script is rolled back, so it never outlives the transaction.
create table public.seva_mala_test_ids (key text primary key, id uuid not null);
grant select on public.seva_mala_test_ids to authenticated;

insert into public.seva_mala_test_ids (key, id)
select split_part(split_part(users.email, '@', 1), 'sm-', 2), users.id
from public.users
where users.email like 'sm-%@example.test';

create table public.seva_mala_snapshots (
  label text not null,
  devotee_id uuid not null,
  seva_norm numeric,
  giving_norm numeric,
  giving_utility numeric,
  score numeric,
  primary key (label, devotee_id)
);

-- ---------------------------------------------------------------------------
-- 2. The facts.
--
--    All of it before this week began, so the current week is empty on any day
--    of any week and the week the fixture sits in has always already closed.
--    Anchor is last Sunday: the LAST day of the previous ISO week.
--
--    Hands' twelve five-hour acts are laid out six per week deliberately —
--    1,800 minutes is exactly the weekly cap, and a seventh would be clipped.
--    Sixty hours is the most a devotee can be credited with in a fortnight,
--    and Hands serves exactly that.
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

  for v_plan in
    select * from (values
      ('hands',   12, 300, 1),
      ('balance', 10, 120, 2),
      ('steady',   5, 120, 1),
      ('gauri',    4, 120, 1),
      ('asha',     3, 120, 1),
      ('bhakta',   2, 120, 1),
      ('chandra',  1, 120, 1),
      ('lila',     5, 120, 1),
      ('kirtan',   3,  60, 1),
      ('hidden',   7, 120, 1)
    ) as plan(who, acts, mins, per_day)
  loop
    for v_n in 1 .. v_plan.acts loop
      -- Hands skips the seventh day back so six acts land in each of two
      -- weeks; everybody else walks straight back from the anchor.
      v_day := v_anchor - ((v_n - 1) / v_plan.per_day)
               - (case when v_plan.who = 'hands' and v_n > 6 then 1 else 0 end);

      insert into public.service_instances (
        service_type_id, date, start_time, duration_minutes, slots_needed,
        participation_mode, posted_by, status
      ) values (
        v_type, v_day, time '09:00' + ((v_n % 2) * interval '3 hours'),
        v_plan.mins, 1, 'open', null, 'completed'
      ) returning id into v_instance;

      insert into public.service_assignments (
        service_instance_id, devotee_id, assignment_method, status,
        verification, attendance, completed_at
      ) values (
        v_instance,
        (select ids.id from public.seva_mala_test_ids ids where ids.key = v_plan.who),
        'self_joined', 'completed', 'member_verified', 'served',
        (v_day + time '12:00') at time zone 'America/Chicago'
      );
    end loop;
  end loop;

  -- Hidden's extra hour, which is what makes fifty-three acts and puts the
  -- median exactly on 120.
  insert into public.service_instances (
    service_type_id, date, start_time, duration_minutes, slots_needed,
    participation_mode, posted_by, status
  ) values (v_type, v_anchor - 8, time '07:00', 60, 1, 'open', null, 'completed')
  returning id into v_instance;

  insert into public.service_assignments (
    service_instance_id, devotee_id, assignment_method, status,
    verification, attendance, completed_at
  ) values (
    v_instance,
    (select ids.id from public.seva_mala_test_ids ids where ids.key = 'hidden'),
    'self_joined', 'completed', 'member_verified', 'served',
    ((v_anchor - 8) + time '08:00') at time zone 'America/Chicago'
  );
end;
$$;

do $$
declare
  v_anchor date := public.seva_mala_week_start(public.seva_mala_today()) - 1;
  v_gift record;
begin
  for v_gift in
    select * from (values
      ('purse',   250000),
      ('balance',  80000),
      ('hidden',   40000),
      ('nanda',    30000),
      ('steady',   20000),
      ('gauri',    15000),
      ('asha',     10000),
      ('bhakta',    7500),
      ('chandra',   5000),
      ('kirtan',    2500)
    ) as gift(who, cents)
  loop
    insert into public.donations (
      donor_id, donor_name, amount_cents, kind, external_payment_id, received_at
    ) values (
      (select ids.id from public.seva_mala_test_ids ids where ids.key = v_gift.who),
      v_gift.who, v_gift.cents, 'one_time', 'sm-' || v_gift.who || '-1',
      ((v_anchor - 2) + time '10:00') at time zone 'America/Chicago'
    );
  end loop;
end;
$$;

-- Everyone appears on the board except Hidden, who wants no part of it.
update public.users
set leaderboard_visible = true
where users.email like 'sm-%@example.test' and users.email <> 'sm-hidden@example.test';

-- The closed week the fixture sits in, so freezing and the rivalrous awards
-- have something to happen to.
select public.ensure_seva_mala_period(
  'week', public.seva_mala_week_start(public.seva_mala_today()) - 1
) as closed_week;

select public.recompute_seva_mala() as periods_computed;

-- ---------------------------------------------------------------------------
-- 3. The units and the references, to the digit.
--
--    Everything downstream is a function of these four numbers, so they are
--    checked before anything is concluded from them. If the median moves, this
--    fails here and says so, rather than failing as a mysteriously wrong score
--    forty assertions later.
-- ---------------------------------------------------------------------------

do $$
declare
  v_period public.seva_mala_periods;
begin
  select * into v_period from public.seva_mala_periods where period_kind = 'lifetime';

  if v_period.seva_unit_minutes <> 120 then
    raise exception 'v_s is % rather than the 120-minute median act.', v_period.seva_unit_minutes;
  end if;
  if v_period.giving_unit_cents <> 17500 then
    raise exception 'v_g is % rather than the 17,500-cent median gift.', v_period.giving_unit_cents;
  end if;
  if round(v_period.seva_reference, 4) <> 2.1916 then
    raise exception 'ref_s is % rather than 2.1916.', round(v_period.seva_reference, 4);
  end if;
  if round(v_period.giving_reference, 4) <> 1.2952 then
    raise exception 'ref_g is % rather than 1.2952.', round(v_period.giving_reference, 4);
  end if;
  if v_period.participant_count <> 12 then
    raise exception 'The lifetime cohort is % rather than 12.', v_period.participant_count;
  end if;

  -- The reference is a percentile of the congregation, not its maximum. If it
  -- were the maximum it would equal Hands' utility, ln(31) = 3.434.
  if round(v_period.seva_reference, 2) = 3.43 then
    raise exception 'ref_s is the maximum utility rather than a percentile of the congregation.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Every stored score re-derived from the stored inputs.
--
--    Not "the score looks plausible": the whole formula, recomputed in this
--    script from the period's own references and units, compared to what the
--    migration wrote, for all twelve devotees at once. This is the assertion
--    that survives a refactor of the function body.
-- ---------------------------------------------------------------------------

do $$
declare
  v_bad text;
begin
  select string_agg(
           users.name || ': stored ' || checked.stored || ', re-derived ' || checked.derived,
           '; ')
  into v_bad
  from (
    select
      parts.devotee_id,
      parts.stored,
      -- The published formula, typed out here rather than borrowed from
      -- seva_mala_score and seva_mala_normalise, so this stays an independent
      -- re-derivation: the larger offering whole, the smaller for beta of
      -- itself. 202608040062 made the cap soft — up to the congregation's
      -- reference a plain ratio, past it 1 + alpha*ln(u/ref), railed at
      -- 1 + beta — and it is written here in the u/ref form rather than the
      -- migration's (u - ref)/ref form, which is the same function said
      -- differently and therefore still an independent check.
      round(
        (greatest(parts.seva, parts.giving) + 0.5 * least(parts.seva, parts.giving)) / 1.5,
        5
      ) as derived
    from (
      select
        scores.devotee_id,
        scores.score as stored,
        case
          when round(ln(1 + scores.seva_minutes / periods.seva_unit_minutes), 10)
               <= periods.seva_reference
          then round(ln(1 + scores.seva_minutes / periods.seva_unit_minutes), 10)
               / periods.seva_reference
          else least(1.5, 1 + 0.15 * ln(
                 round(ln(1 + scores.seva_minutes / periods.seva_unit_minutes), 10)
                 / periods.seva_reference))
        end as seva,
        case
          when round(ln(1 + scores.giving_cents::numeric / periods.giving_unit_cents), 10)
               <= periods.giving_reference
          then round(ln(1 + scores.giving_cents::numeric / periods.giving_unit_cents), 10)
               / periods.giving_reference
          else least(1.5, 1 + 0.15 * ln(
                 round(ln(1 + scores.giving_cents::numeric / periods.giving_unit_cents), 10)
                 / periods.giving_reference))
        end as giving
      from public.period_scores scores
      join public.seva_mala_periods periods on periods.id = scores.period_id
      where periods.period_kind = 'lifetime'
    ) parts
  ) checked
  join public.users on users.id = checked.devotee_id
  where abs(checked.stored - checked.derived) > 0.00002;

  if v_bad is not null then
    raise exception 'The stored score does not follow the published formula for %.', v_bad;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. The three rows the temple argued about.
--
--    Sixty hours and nothing given, against $2,500 and no seva: EQUAL, to the
--    sixth decimal place, and sharing a dense rank. Twenty hours and $800:
--    half as much again as either, and first. Four hours and seventy-five
--    dollars: behind both of them, which is the correction 0059 made.
-- ---------------------------------------------------------------------------

do $$
declare
  v_hands numeric;
  v_purse numeric;
  v_balance numeric;
  v_bhakta numeric;
  v_hands_rank integer;
  v_purse_rank integer;
  v_above integer;
  v_below integer;
begin
  select scores.score into v_hands
  from public.period_scores scores
  join public.seva_mala_periods periods on periods.id = scores.period_id
  join public.seva_mala_test_ids ids on ids.id = scores.devotee_id
  where periods.period_kind = 'lifetime' and ids.key = 'hands';

  select scores.score into v_purse
  from public.period_scores scores
  join public.seva_mala_periods periods on periods.id = scores.period_id
  join public.seva_mala_test_ids ids on ids.id = scores.devotee_id
  where periods.period_kind = 'lifetime' and ids.key = 'purse';

  select scores.score into v_balance
  from public.period_scores scores
  join public.seva_mala_periods periods on periods.id = scores.period_id
  join public.seva_mala_test_ids ids on ids.id = scores.devotee_id
  where periods.period_kind = 'lifetime' and ids.key = 'balance';

  select scores.score into v_bhakta
  from public.period_scores scores
  join public.seva_mala_periods periods on periods.id = scores.period_id
  join public.seva_mala_test_ids ids on ids.id = scores.devotee_id
  where periods.period_kind = 'lifetime' and ids.key = 'bhakta';

  -- 202608040062 made the cap soft, and these two devotees are BOTH above the
  -- congregation's reference — which is exactly the case the temple complained
  -- about. They no longer land on the same number, because they no longer stand
  -- at the same place: Purse's giving is 2.11 times the congregation's giving
  -- reference while Hands's seva is 1.57 times its seva reference. Equality at
  -- EQUAL STANDING is what the temple asked for and it is proved, at two
  -- different standings, in fair_scaling.sql. What must still be true here is
  -- that both are two thirds of the way up and that both are beaten by the
  -- devotee who did both.
  if v_hands <= 0.666667 then
    raise exception
      'The sixty-hour devotee scores %, at or below the old cap of 0.666667.', v_hands;
  end if;
  if v_purse <= 0.666667 then
    raise exception
      'The $2,500 donor scores %, at or below the old cap of 0.666667.', v_purse;
  end if;
  if v_hands >= 0.8 or v_purse >= 0.8 then
    raise exception
      'One offering alone reaches % and %; the soft cap is not steep enough to be a cap.',
      v_hands, v_purse;
  end if;
  -- And the ordering between them follows relative standing rather than
  -- dollars or hours. Read off the stored norms rather than assumed.
  if (v_purse > v_hands) <> (
    (select scores.giving_norm from public.period_scores scores
     join public.seva_mala_periods periods on periods.id = scores.period_id
     join public.seva_mala_test_ids ids on ids.id = scores.devotee_id
     where periods.period_kind = 'lifetime' and ids.key = 'purse')
    > (select scores.seva_norm from public.period_scores scores
       join public.seva_mala_periods periods on periods.id = scores.period_id
       join public.seva_mala_test_ids ids on ids.id = scores.devotee_id
       where periods.period_kind = 'lifetime' and ids.key = 'hands')
  ) then
    raise exception
      'Hands (%) and Purse (%) are not ordered by where they stand against their own reference.',
      v_hands, v_purse;
  end if;
  if v_balance <= 1.000000 then
    raise exception
      'The balanced devotee scores % rather than something above 1.000000; both their offerings are past the reference.',
      v_balance;
  end if;
  if v_balance <= v_hands or v_balance <= v_purse then
    raise exception 'Giving both does not beat giving one.';
  end if;

  -- Four hours and seventy-five dollars, against sixty hours and against
  -- $2,500. Under 0055's rule this devotee beat both of them, and the temple
  -- said that was the wrong way round: a devotee who is moderate at both must
  -- not outrank a devotee who is exceptional at one.
  if v_bhakta >= v_hands then
    raise exception
      'Four hours and $75 scores % — ahead of sixty hours at %. The old rule is back.',
      v_bhakta, v_hands;
  end if;
  if v_bhakta >= v_purse then
    raise exception
      'Four hours and $75 scores % — ahead of $2,500 at %. The old rule is back.',
      v_bhakta, v_purse;
  end if;

  -- Mid-board, meaning genuinely in the middle: people above and people below.
  select
    count(*) filter (where scores.score > v_hands),
    count(*) filter (where scores.score < v_hands)
  into v_above, v_below
  from public.period_scores scores
  join public.seva_mala_periods periods on periods.id = scores.period_id
  where periods.period_kind = 'lifetime';

  if v_above < 3 or v_below < 3 then
    raise exception
      'The one-sided devotees are not mid-board: % above, % below.', v_above, v_below;
  end if;

  -- And they share a dense rank rather than being separated by rounding noise.
  select ranked.standing into v_hands_rank from (
    select scores.devotee_id, dense_rank() over (order by scores.score desc) as standing
    from public.period_scores scores
    join public.seva_mala_periods periods on periods.id = scores.period_id
    where periods.period_kind = 'lifetime'
  ) ranked
  join public.seva_mala_test_ids ids on ids.id = ranked.devotee_id
  where ids.key = 'hands';

  select ranked.standing into v_purse_rank from (
    select scores.devotee_id, dense_rank() over (order by scores.score desc) as standing
    from public.period_scores scores
    join public.seva_mala_periods periods on periods.id = scores.period_id
    where periods.period_kind = 'lifetime'
  ) ranked
  join public.seva_mala_test_ids ids on ids.id = ranked.devotee_id
  where ids.key = 'purse';

  -- Under 0055's hard cap these two shared a place, because the cap had made
  -- them the same number. Under 202608040062 they are a place apart and the
  -- better placed is the one standing further above their own reference; two
  -- devotees at the SAME standing still share a place, which fair_scaling.sql
  -- proves twice.
  if v_hands_rank = v_purse_rank then
    raise exception
      'Hands and Purse share place % although they stand at different multiples of their references.',
      v_hands_rank;
  end if;
  if (v_purse_rank < v_hands_rank) <> (v_purse > v_hands) then
    raise exception 'Purse stands at % and Hands at %, against their scores % and %.',
      v_purse_rank, v_hands_rank, v_purse, v_hands;
  end if;
  if v_hands_rank < 3 or v_hands_rank > 9 then
    raise exception 'The one-sided devotees stand at % of twelve.', v_hands_rank;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Sixty hours were credited, and the caps are the reason it is not more.
-- ---------------------------------------------------------------------------

do $$
declare
  v_minutes numeric;
begin
  select scores.credited_minutes into v_minutes
  from public.period_scores scores
  join public.seva_mala_periods periods on periods.id = scores.period_id
  join public.seva_mala_test_ids ids on ids.id = scores.devotee_id
  where periods.period_kind = 'lifetime' and ids.key = 'hands';

  if v_minutes <> 3600 then
    raise exception 'Hands was credited % minutes rather than sixty hours.', v_minutes;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Freezing, and the fact that a frozen period is finished with.
--
--    Snapshot the closed week now. Sections 8 and 12 add money dated inside
--    that week; if any of it moves, freezing does not mean frozen.
-- ---------------------------------------------------------------------------

do $$
declare
  v_period public.seva_mala_periods;
begin
  select * into v_period from public.seva_mala_periods
  where period_kind = 'week'
    and starts_on = public.seva_mala_week_start(public.seva_mala_today() - 7);

  if v_period.id is null then
    raise exception 'The closed week was never created.';
  end if;
  if v_period.frozen_at is null then
    raise exception 'A week that ended on % has not been frozen.', v_period.ends_on;
  end if;
  if v_period.participant_count < 8 then
    raise exception 'The closed week has only % participants.', v_period.participant_count;
  end if;

  -- The current week, by contrast, is open and empty.
  select * into v_period from public.seva_mala_periods
  where period_kind = 'week'
    and starts_on = public.seva_mala_week_start(public.seva_mala_today());
  if v_period.frozen_at is not null then
    raise exception 'The current week has been frozen while it is still running.';
  end if;
end;
$$;

insert into public.seva_mala_snapshots (label, devotee_id, seva_norm, giving_norm, giving_utility, score)
select 'closed_week', scores.devotee_id, scores.seva_norm, scores.giving_norm,
       scores.giving_utility, scores.score
from public.period_scores scores
join public.seva_mala_periods periods on periods.id = scores.period_id
where periods.period_kind = 'week'
  and periods.starts_on = public.seva_mala_week_start(public.seva_mala_today() - 7);

insert into public.seva_mala_snapshots (label, devotee_id, seva_norm, giving_norm, giving_utility, score)
select 'before_second_gift', scores.devotee_id, scores.seva_norm, scores.giving_norm,
       scores.giving_utility, scores.score
from public.period_scores scores
join public.seva_mala_periods periods on periods.id = scores.period_id
where periods.period_kind = 'lifetime';

-- ---------------------------------------------------------------------------
-- 8. THE CAP. A second large gift buys nothing.
--
--    Purse gives another $2,500 — doubling their giving. Their utility rises
--    from ln(15.3) to ln(29.6); the reference moves too, because the
--    congregation's eightieth percentile is a function of everybody. And the
--    score does not move at all, because ĝ was already 1 and 1 is where it
--    stops.
--
--    Asserted as an exact equality rather than "approximately", because
--    "approximately unchanged" is what a broken cap also looks like.
-- ---------------------------------------------------------------------------

insert into public.donations (
  donor_id, donor_name, amount_cents, kind, external_payment_id, received_at
)
select ids.id, 'purse', 250000, 'one_time', 'sm-purse-2',
       ((public.seva_mala_week_start(public.seva_mala_today()) - 1) + time '11:00')
         at time zone 'America/Chicago'
from public.seva_mala_test_ids ids where ids.key = 'purse';

select public.recompute_seva_mala() as after_second_gift;

do $$
declare
  v_before numeric;
  v_after numeric;
  v_cents bigint;
  v_norm numeric;
  v_utility_before numeric;
  v_utility_after numeric;
begin
  select snapshot.score, scores.score, scores.giving_cents, scores.giving_norm,
         snapshot.giving_utility, scores.giving_utility
  into v_before, v_after, v_cents, v_norm, v_utility_before, v_utility_after
  from public.period_scores scores
  join public.seva_mala_periods periods on periods.id = scores.period_id
  join public.seva_mala_test_ids ids on ids.id = scores.devotee_id
  join public.seva_mala_snapshots snapshot
    on snapshot.devotee_id = scores.devotee_id and snapshot.label = 'before_second_gift'
  where periods.period_kind = 'lifetime' and ids.key = 'purse';

  if v_cents <> 500000 then
    raise exception 'The second gift did not land: Purse has % cents.', v_cents;
  end if;
  if v_utility_after <= v_utility_before then
    raise exception 'The second gift did not raise the raw utility, so this proves nothing.';
  end if;
  -- 202608040062 made the cap soft, so a second $2,500 is no longer worth
  -- literally nothing — that flattening is the thing the temple asked to have
  -- removed. What must still be true is that it is worth almost nothing:
  -- DOUBLING the largest gift in the congregation buys a few percent, and it
  -- does not carry the donor past a devotee who gave both their hands and their
  -- means.
  if v_norm <= 1 or v_norm > public.seva_mala_norm_ceiling() then
    raise exception 'Purse is at g-hat = %, which is not above the reference and under the ceiling.',
      v_norm;
  end if;
  if v_after <= v_before then
    raise exception
      'A second $2,500 moved the score from % to %; giving more counts for nothing again.',
      v_before, v_after;
  end if;
  if v_after / v_before > 1.10 then
    raise exception
      'Doubling the largest gift in the congregation moved the score from % to %, which is not diminishing returns.',
      v_before, v_after;
  end if;
  if v_after >= (
    select scores.score from public.period_scores scores
    join public.seva_mala_periods periods on periods.id = scores.period_id
    join public.seva_mala_test_ids ids on ids.id = scores.devotee_id
    where periods.period_kind = 'lifetime' and ids.key = 'balance'
  ) then
    raise exception 'Five thousand dollars and no seva has passed the balanced devotee.';
  end if;
end;
$$;

-- The frozen week did not notice, and must not have.
do $$
declare
  v_moved text;
begin
  select string_agg(users.name, ', ') into v_moved
  from public.period_scores scores
  join public.seva_mala_periods periods on periods.id = scores.period_id
  join public.seva_mala_snapshots snapshot
    on snapshot.devotee_id = scores.devotee_id and snapshot.label = 'closed_week'
  join public.users on users.id = scores.devotee_id
  where periods.period_kind = 'week'
    and periods.starts_on = public.seva_mala_week_start(public.seva_mala_today() - 7)
    and (scores.score <> snapshot.score or scores.giving_norm <> snapshot.giving_norm);

  if v_moved is not null then
    raise exception 'A frozen week moved for %. Frozen means frozen.', v_moved;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 9. Points come from period totals, never from a transaction.
--
--    Chandra's $50 arrives instead as fifty separate one-dollar gifts. Same
--    total, same everything. This is what makes micro-donation spam pointless:
--    there is no per-gift term anywhere in the arithmetic to accumulate.
-- ---------------------------------------------------------------------------

do $$
declare
  v_before numeric;
  v_after numeric;
  v_gifts integer;
  v_n integer;
  v_anchor date := public.seva_mala_week_start(public.seva_mala_today()) - 1;
begin
  select scores.score into v_before
  from public.period_scores scores
  join public.seva_mala_periods periods on periods.id = scores.period_id
  join public.seva_mala_test_ids ids on ids.id = scores.devotee_id
  where periods.period_kind = 'lifetime' and ids.key = 'chandra';

  delete from public.donations where external_payment_id = 'sm-chandra-1';

  for v_n in 1 .. 50 loop
    insert into public.donations (
      donor_id, donor_name, amount_cents, kind, external_payment_id, received_at
    )
    select ids.id, 'chandra', 100, 'one_time', 'sm-chandra-spam-' || v_n,
           ((v_anchor - 2) + time '10:00') at time zone 'America/Chicago'
    from public.seva_mala_test_ids ids where ids.key = 'chandra';
  end loop;

  perform public.recompute_seva_mala();

  select scores.score, scores.gifts into v_after, v_gifts
  from public.period_scores scores
  join public.seva_mala_periods periods on periods.id = scores.period_id
  join public.seva_mala_test_ids ids on ids.id = scores.devotee_id
  where periods.period_kind = 'lifetime' and ids.key = 'chandra';

  if v_gifts <> 50 then
    raise exception 'The fifty gifts did not land: % recorded.', v_gifts;
  end if;
  if v_after > v_before then
    raise exception
      'Splitting $50 into fifty gifts raised the score from % to %. Points are per transaction.',
      v_before, v_after;
  end if;

  -- Put it back so later sections see the fixture they were designed against.
  delete from public.donations where external_payment_id like 'sm-chandra-spam-%';
  insert into public.donations (
    donor_id, donor_name, amount_cents, kind, external_payment_id, received_at
  )
  select ids.id, 'chandra', 5000, 'one_time', 'sm-chandra-1',
         ((v_anchor - 2) + time '10:00') at time zone 'America/Chicago'
  from public.seva_mala_test_ids ids where ids.key = 'chandra';
  perform public.recompute_seva_mala();
end;
$$;

-- ---------------------------------------------------------------------------
-- 10. Awards, on a closed week.
--
--     Recognition is non-rivalrous and everybody at or above the median active
--     devotee has it. The garlands are rivalrous and there are exactly three of
--     each, decided on final numbers. The Mystery Gift went to exactly one
--     devotee, and drawing again does not draw again.
--
--     And Hidden — who does not appear on any board — has awards, because
--     opting out is display and nothing else.
-- ---------------------------------------------------------------------------

do $$
declare
  v_period uuid;
  v_count integer;
  v_hidden integer;
  v_median numeric;
begin
  select periods.id into v_period from public.seva_mala_periods periods
  where periods.period_kind = 'week'
    and periods.starts_on = public.seva_mala_week_start(public.seva_mala_today() - 7);

  -- Recognition: non-rivalrous, and the threshold is the median active devotee.
  select percentile_cont(0.5) within group (order by scores.score) into v_median
  from public.period_scores scores where scores.period_id = v_period and scores.score > 0;

  select count(*) into v_count
  from public.devotee_awards awards
  join public.award_definitions definitions on definitions.id = awards.award_definition_id
  where awards.period_id = v_period and definitions.code = 'weekly_recognition';

  if v_count < 6 then
    raise exception
      'Only % devotees reached the median. Recognition should be non-rivalrous.', v_count;
  end if;

  select count(*) into v_count
  from public.period_scores scores
  where scores.period_id = v_period and scores.score > 0 and scores.score >= v_median
    and not exists (
      select 1 from public.devotee_awards awards
      join public.award_definitions definitions on definitions.id = awards.award_definition_id
      where awards.devotee_id = scores.devotee_id and awards.period_id = v_period
        and definitions.code = 'weekly_recognition'
    );
  if v_count > 0 then
    raise exception '% devotees reached the median and were not recognised.', v_count;
  end if;

  -- Hidden earns everything, and is on no board anywhere.
  select count(*) into v_hidden
  from public.devotee_awards awards
  join public.seva_mala_test_ids ids on ids.id = awards.devotee_id
  where ids.key = 'hidden';
  if v_hidden = 0 then
    raise exception 'The devotee who opted out earned nothing. Opting out is display only.';
  end if;
end;
$$;

-- The month that has closed, if the fixture straddles one, is where the
-- garlands and the draw live. Create and close the month the anchor sits in.
select public.ensure_seva_mala_period(
  'month', public.seva_mala_week_start(public.seva_mala_today()) - 1
) as anchor_month;

select public.recompute_seva_mala() as after_month;

do $$
declare
  v_period uuid;
  v_frozen boolean;
  v_garlands integer;
  v_draw integer;
  v_kinds integer;
  v_again integer;
  v_before integer;
begin
  select periods.id, periods.frozen_at is not null into v_period, v_frozen
  from public.seva_mala_periods periods
  where periods.period_kind = 'month'
    and periods.starts_on = date_trunc(
      'month', (public.seva_mala_week_start(public.seva_mala_today()) - 1)::timestamp)::date;

  if v_period is null then
    raise exception 'The anchor month was never created.';
  end if;

  if not v_frozen then
    -- The fixture sits inside the current month; garlands wait for it to close,
    -- which is the rule under test. Prove the WAIT rather than the award.
    select count(*) into v_garlands
    from public.devotee_awards awards
    join public.award_definitions definitions on definitions.id = awards.award_definition_id
    where awards.period_id = v_period and definitions.rule_kind in ('top_n', 'draw');
    if v_garlands > 0 then
      raise exception
        '% rivalrous awards were given inside a month that is still running.', v_garlands;
    end if;
    return;
  end if;

  -- A closed month: exactly three of each garland, and they are lateral.
  select count(*) into v_garlands
  from public.devotee_awards awards
  join public.award_definitions definitions on definitions.id = awards.award_definition_id
  where awards.period_id = v_period and definitions.code = 'garland_seva';
  if v_garlands <> 3 then
    raise exception 'The Seva garland went to % devotees rather than three.', v_garlands;
  end if;

  select count(distinct definitions.garland_kind) into v_kinds
  from public.devotee_awards awards
  join public.award_definitions definitions on definitions.id = awards.award_definition_id
  where awards.period_id = v_period and definitions.tier = 'garland';
  if v_kinds <> 3 then
    raise exception 'Only % of the three garlands were given.', v_kinds;
  end if;

  select count(*) into v_draw
  from public.devotee_awards awards
  join public.award_definitions definitions on definitions.id = awards.award_definition_id
  where awards.period_id = v_period and definitions.rule_kind = 'draw';
  if v_draw <> 1 then
    raise exception 'The Mystery Gift was drawn % times.', v_draw;
  end if;

  -- Awarding the same closed period again changes nothing.
  select count(*) into v_before from public.devotee_awards where period_id = v_period;
  perform public.award_seva_mala_for_period(v_period);
  select count(*) into v_again from public.devotee_awards where period_id = v_period;
  if v_again <> v_before then
    raise exception 'A second award pass added % rows. Awarding is not idempotent.',
      v_again - v_before;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 11. A thin congregation does not publish.
--
--     The current week has nobody in it, which is the smallest cohort there is.
--     The garland returns a gathering row rather than an empty set, because a
--     phone must be able to tell "we are still gathering" from "you have no
--     signal".
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.seva_mala_test_ids ids where ids.key = 'balance'), true);

do $$
declare
  v_rows integer;
  v_gathering boolean;
  v_standing integer;
  v_flag boolean;
begin
  select count(*) into v_rows from public.list_seva_garland('week', 20);
  if v_rows <> 1 then
    raise exception
      'A week with nobody in it returned % rows rather than one gathering row.', v_rows;
  end if;

  select garland.gathering, garland.standing into v_gathering, v_standing
  from public.list_seva_garland('week', 20) garland;
  if not v_gathering then
    raise exception 'The thin week did not raise the gathering flag.';
  end if;
  if v_standing is not null then
    raise exception 'The thin week published a standing of %.', v_standing;
  end if;

  -- And my own numbers still come back; only the standing is withheld.
  select mine.gathering, mine.standing into v_flag, v_standing
  from public.my_seva_mala('week') mine;
  if not v_flag then
    raise exception 'my_seva_mala did not report the thin week as gathering.';
  end if;
  if v_standing is not null then
    raise exception 'my_seva_mala published a standing of % in a thin week.', v_standing;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 12. The board itself.
--
--     Opted-in only, dense-ranked over the opted-in set so there are no gaps
--     to read an absence out of, and carrying NOTHING but a place and a tier.
-- ---------------------------------------------------------------------------

do $$
declare
  v_rows integer;
  v_hidden integer;
  v_max integer;
  v_you integer;
begin
  select count(*) into v_rows from public.list_seva_garland('lifetime', 20);
  if v_rows <> 11 then
    raise exception 'The garland shows % devotees rather than the eleven who opted in.', v_rows;
  end if;

  select count(*) into v_hidden
  from public.list_seva_garland('lifetime', 20) garland
  join public.seva_mala_test_ids ids on ids.id = garland.devotee_id
  where ids.key = 'hidden';
  if v_hidden <> 0 then
    raise exception 'The devotee who opted out is on the public garland.';
  end if;

  -- Dense over the opted-in set: however many distinct scores there are, the
  -- places run 1..n with no gap for anybody to read an absence out of. Under
  -- 0055's hard cap Hands and Purse tied and the last place was 10; under
  -- 202608040062's soft cap they are a place apart and it is 11. What is being
  -- asserted is denseness, not the number.
  select max(garland.standing) into v_max from public.list_seva_garland('lifetime', 20) garland;
  select count(distinct garland.standing) into v_rows
  from public.list_seva_garland('lifetime', 20) garland;
  if v_max is distinct from v_rows then
    raise exception
      'The garland runs to place % with % distinct places — the ranking is not dense over the opted-in.',
      v_max, v_rows;
  end if;
  if v_max <> 11 then
    raise exception 'The garland has % places for eleven devotees with distinct scores.', v_max;
  end if;

  select count(*) into v_you
  from public.list_seva_garland('lifetime', 20) garland where garland.is_you;
  if v_you <> 1 then
    raise exception 'Balance appears % times on the garland.', v_you;
  end if;
end;
$$;

-- The caller is appended when they fall outside the band.
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.seva_mala_test_ids ids where ids.key = 'kirtan'), true);

do $$
declare
  v_rows integer;
  v_band integer;
  v_mine integer;
begin
  select count(*) into v_rows from public.list_seva_garland('lifetime', 3);
  select count(*) into v_band
  from public.list_seva_garland('lifetime', 3) garland where garland.standing <= 3;
  select garland.standing into v_mine
  from public.list_seva_garland('lifetime', 3) garland where garland.is_you;

  if v_mine is null then
    raise exception 'Kirtan asked for the top three and was not told where they stand.';
  end if;
  if v_mine <= 3 then
    raise exception 'Kirtan stands at %, which is inside the band; this proves nothing.', v_mine;
  end if;

  -- Three PLACES, not three names: Hands and Purse share third under the
  -- inverted rule, so the band is four deep and the caller is one more. Asserted
  -- as band-plus-one rather than as a constant, because a tie at the edge of the
  -- band is a thing that happens and is not a bug.
  if v_band < 3 then
    raise exception 'The top three band holds only % names.', v_band;
  end if;
  if v_rows <> v_band + 1 then
    raise exception
      'The top three (% names) plus the caller is % rows.', v_band, v_rows;
  end if;
end;
$$;

-- A devotee who opted out is not appended either. They asked not to be there.
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.seva_mala_test_ids ids where ids.key = 'hidden'), true);

do $$
declare
  v_you integer;
  v_standing integer;
begin
  select count(*) into v_you
  from public.list_seva_garland('lifetime', 3) garland where garland.is_you;
  if v_you <> 0 then
    raise exception 'The devotee who opted out was appended to the garland anyway.';
  end if;

  -- But they can still see their own true standing, privately.
  select mine.standing into v_standing from public.my_seva_mala('lifetime') mine;
  if v_standing is null then
    raise exception 'The devotee who opted out cannot see their own standing.';
  end if;
  if v_standing <> 2 then
    raise exception 'Hidden stands at % rather than second.', v_standing;
  end if;

  select mine.board_standing into v_standing from public.my_seva_mala('lifetime') mine;
  if v_standing is not null then
    raise exception 'The devotee who opted out has a place on the board at %.', v_standing;
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);

-- The board's shape is part of its security. No score, no minutes, no cents.
do $$
declare
  v_leaked text;
begin
  select string_agg(parameters.parameter_name, ', ') into v_leaked
  from information_schema.parameters
  where specific_schema = 'public'
    and specific_name like 'list_seva_garland%'
    and parameter_mode = 'OUT'
    and (
      parameters.parameter_name ilike '%score%'
      or parameters.parameter_name ilike '%minute%'
      or parameters.parameter_name ilike '%cent%'
      or parameters.parameter_name ilike '%norm%'
      or parameters.parameter_name ilike '%hour%'
      or parameters.parameter_name ilike '%utility%'
    );
  if v_leaked is not null then
    raise exception 'The public garland returns %. Position or tier only.', v_leaked;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 13. An outlier does not flatten the congregation.
--
--     Purse gives a further $100,000 — forty times the largest gift in the
--     fixture. Under a maximum-based normalisation this is the end of everybody
--     else: their ĝ would be divided by ln(1 + 10,500,000/v_g) and collapse to
--     a rounding error. Under a percentile of a logarithm it barely registers.
--
--     Both are computed here, side by side, so the assertion is not "the number
--     did not change much" but "the number did not change much AND the naive
--     alternative would have destroyed it".
-- ---------------------------------------------------------------------------

insert into public.seva_mala_snapshots (label, devotee_id, seva_norm, giving_norm, giving_utility, score)
select 'before_outlier', scores.devotee_id, scores.seva_norm, scores.giving_norm,
       scores.giving_utility, scores.score
from public.period_scores scores
join public.seva_mala_periods periods on periods.id = scores.period_id
where periods.period_kind = 'lifetime';

insert into public.donations (
  donor_id, donor_name, amount_cents, kind, external_payment_id, received_at
)
select ids.id, 'purse', 10000000, 'one_time', 'sm-purse-whale',
       ((public.seva_mala_week_start(public.seva_mala_today()) - 1) + time '13:00')
         at time zone 'America/Chicago'
from public.seva_mala_test_ids ids where ids.key = 'purse';

select public.recompute_seva_mala() as after_outlier;

do $$
declare
  v_worst numeric;
  v_worst_name text;
  v_counterfactual numeric;
  v_ref numeric;
  v_unit numeric;
  v_top numeric;
begin
  select periods.giving_reference, periods.giving_unit_cents
  into v_ref, v_unit
  from public.seva_mala_periods periods where periods.period_kind = 'lifetime';

  select max(scores.giving_utility) into v_top
  from public.period_scores scores
  join public.seva_mala_periods periods on periods.id = scores.period_id
  where periods.period_kind = 'lifetime';

  -- The largest proportional move among everybody who is not the outlier.
  select max(abs(scores.giving_norm - snapshot.giving_norm) / snapshot.giving_norm),
         (array_agg(users.name order by
            abs(scores.giving_norm - snapshot.giving_norm) / snapshot.giving_norm desc))[1]
  into v_worst, v_worst_name
  from public.period_scores scores
  join public.seva_mala_periods periods on periods.id = scores.period_id
  join public.seva_mala_snapshots snapshot
    on snapshot.devotee_id = scores.devotee_id and snapshot.label = 'before_outlier'
  join public.seva_mala_test_ids ids on ids.id = scores.devotee_id
  join public.users on users.id = scores.devotee_id
  where periods.period_kind = 'lifetime'
    and ids.key <> 'purse'
    and snapshot.giving_norm > 0;

  if v_worst > 0.25 then
    raise exception
      'A $100,000 gift moved %s giving by %%%. The outlier is flattening the congregation.',
      v_worst_name, round(v_worst * 100, 1);
  end if;

  -- What normalising against the maximum would have done to the smallest donor.
  select min(scores.giving_utility) / v_top into v_counterfactual
  from public.period_scores scores
  join public.seva_mala_periods periods on periods.id = scores.period_id
  where periods.period_kind = 'lifetime' and scores.giving_utility > 0;

  if v_counterfactual > 0.05 then
    raise exception
      'The maximum-based counterfactual is % — the outlier is not extreme enough to prove anything.',
      round(v_counterfactual, 4);
  end if;

  -- And the devotee who gave both their hands and their means is still at the
  -- top of the board. Under 0055's hard cap that was asserted as "their score is
  -- still exactly 1"; under 202608040062's soft cap a devotee past the reference
  -- in both dimensions scores a little above 1 and the outlier scores a little
  -- above two thirds, so what is asserted is the thing that actually matters:
  -- nobody has bought their way past them.
  if exists (
    select 1
    from public.period_scores others
    join public.seva_mala_periods periods on periods.id = others.period_id
    where periods.period_kind = 'lifetime'
      and others.score > (
        select scores.score
        from public.period_scores scores
        join public.seva_mala_periods inner_periods on inner_periods.id = scores.period_id
        join public.seva_mala_test_ids ids on ids.id = scores.devotee_id
        where inner_periods.period_kind = 'lifetime' and ids.key = 'balance'
      )
  ) then
    raise exception 'The balanced devotee is no longer at the top after one enormous gift.';
  end if;
end;
$$;

delete from public.donations where external_payment_id in ('sm-purse-whale', 'sm-purse-2');
select public.recompute_seva_mala() as restored;

-- ---------------------------------------------------------------------------
-- 14. Quality, per act, in the order the cases are tested.
--
--     Six devotees, one act each, every branch of the multiplier. Asserted
--     against seva_mala_acts rather than against a score, because a score is a
--     sum and a sum can hide a sign error.
--
--     202608040057_seva_points_eligibility.sql retired the two fractional
--     branches that stood in for a missing attendance mark: a self-reported act
--     nobody has confirmed is 0, not 0.6, and an auto-completed timer nobody has
--     confirmed is 0, not 0.7. The 0.7 itself survives for a timer that WAS
--     confirmed, which is the case q_timer now carries. seva_points_eligibility
--     verifies the eligibility rule in full; these six only pin the multiplier.
-- ---------------------------------------------------------------------------

do $$
declare
  v_type uuid;
  v_day date := public.seva_mala_week_start(public.seva_mala_today()) - 3;
  v_case record;
  v_instance uuid;
  v_id uuid;
  v_session uuid;
  v_i integer := 30;
  v_quality numeric;
begin
  select service_types.id into v_type
  from public.service_types where service_types.name = 'Pot Washing';

  for v_case in
    select * from (values
      ('q_absent',    'completed', 'absent',  'self_report',  0.0),
      ('q_noshow',    'no_show',   'served',  'qr_scan',      0.0),
      ('q_unmarked',  'assigned',  null,      'self_report',  0.0),
      ('q_selfsaid',  'completed', null,      'self_report',  0.0),
      ('q_timer',     'completed', 'served',  'live_timer',   0.7),
      ('q_verified',  'completed', 'served',  'member_verified', 1.0)
    ) as spec(who, status, attendance, verification, expected)
  loop
    v_i := v_i + 1;
    v_id := ('50000000-0000-0000-0000-0000000000' || v_i::text)::uuid;
    insert into auth.users (id, email, raw_user_meta_data)
    values (v_id, 'smq-' || v_case.who || '@example.test',
            jsonb_build_object('name', v_case.who));

    insert into public.service_instances (
      service_type_id, date, start_time, duration_minutes, slots_needed,
      participation_mode, posted_by, status
    ) values (v_type, v_day, time '09:00', 120, 1, 'open', null, 'completed')
    returning id into v_instance;

    insert into public.service_assignments (
      service_instance_id, devotee_id, assignment_method, status,
      verification, attendance
    ) values (
      v_instance, v_id, 'self_joined', v_case.status,
      v_case.verification, v_case.attendance
    );

    -- The live-timer case needs a session that nobody switched off.
    if v_case.who = 'q_timer' then
      insert into public.service_qr_sessions (
        devotee_id, service_type_id, started_at, planned_end_at, completed_at,
        status, service_instance_id, started_via, auto_completed
      ) values (
        v_id, v_type,
        (v_day + time '09:00') at time zone 'America/Chicago',
        (v_day + time '11:00') at time zone 'America/Chicago',
        (v_day + time '11:00') at time zone 'America/Chicago',
        'completed', v_instance, 'service_list', true
      ) returning id into v_session;
    end if;

    select acts.quality into v_quality from public.seva_mala_acts(v_id) acts;
    if v_quality is distinct from v_case.expected then
      raise exception
        'Quality for % (% / % / %) is % rather than %.',
        v_case.who, v_case.status, coalesce(v_case.attendance, 'no mark'),
        v_case.verification, v_quality, v_case.expected;
    end if;
  end loop;
end;
$$;

-- Credited minutes are the smaller of planned and actual, in both directions.
do $$
declare
  v_type uuid;
  v_day date := public.seva_mala_week_start(public.seva_mala_today()) - 4;
  v_id uuid := '50000000-0000-0000-0000-000000000040';
  v_other uuid := '50000000-0000-0000-0000-000000000041';
  v_instance uuid;
  v_minutes numeric;
begin
  select service_types.id into v_type
  from public.service_types where service_types.name = 'Pot Washing';

  insert into auth.users (id, email, raw_user_meta_data)
  values (v_id, 'smq-short@example.test', '{"name":"Short Das"}'),
         (v_other, 'smq-long@example.test', '{"name":"Long Das"}');

  -- Planned two hours, verified as forty minutes: forty is credited.
  insert into public.service_instances (
    service_type_id, date, start_time, duration_minutes, slots_needed,
    participation_mode, posted_by, status
  ) values (v_type, v_day, time '09:00', 120, 1, 'open', null, 'completed')
  returning id into v_instance;
  insert into public.service_assignments (
    service_instance_id, devotee_id, assignment_method, status,
    verification, attendance
  ) values (v_instance, v_id, 'self_joined', 'completed', 'member_verified', 'served');
  insert into public.service_verifications (
    devotee_id, service_type_id, start_at, end_at, verifier_id, status,
    service_instance_id, responded_at
  ) values (
    v_id, v_type,
    (v_day + time '09:00') at time zone 'America/Chicago',
    (v_day + time '09:40') at time zone 'America/Chicago',
    (select ids.id from public.seva_mala_test_ids ids where ids.key = 'president'),
    'verified', v_instance, now()
  );

  select acts.credited_minutes into v_minutes from public.seva_mala_acts(v_id) acts;
  if v_minutes <> 40 then
    raise exception 'Two hours booked and forty minutes served credited % minutes.', v_minutes;
  end if;

  -- Planned two hours, verified as five: two hours is credited, not five.
  insert into public.service_instances (
    service_type_id, date, start_time, duration_minutes, slots_needed,
    participation_mode, posted_by, status
  ) values (v_type, v_day, time '13:00', 120, 1, 'open', null, 'completed')
  returning id into v_instance;
  insert into public.service_assignments (
    service_instance_id, devotee_id, assignment_method, status,
    verification, attendance
  ) values (v_instance, v_other, 'self_joined', 'completed', 'member_verified', 'served');
  insert into public.service_verifications (
    devotee_id, service_type_id, start_at, end_at, verifier_id, status,
    service_instance_id, responded_at
  ) values (
    v_other, v_type,
    (v_day + time '13:00') at time zone 'America/Chicago',
    (v_day + time '18:00') at time zone 'America/Chicago',
    (select ids.id from public.seva_mala_test_ids ids where ids.key = 'president'),
    'verified', v_instance, now()
  );

  select acts.credited_minutes into v_minutes from public.seva_mala_acts(v_other) acts;
  if v_minutes <> 120 then
    raise exception
      'A timer left running for five hours on a two-hour seva credited % minutes.', v_minutes;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 15. The caps hold, in both directions, and a zero-quality act spends neither.
-- ---------------------------------------------------------------------------

do $$
declare
  v_type uuid;
  v_id uuid := '50000000-0000-0000-0000-000000000021';
  v_week_start date := public.seva_mala_week_start(public.seva_mala_today()) - 7;
  v_instance uuid;
  v_n integer;
  v_day_minutes numeric;
  v_week_minutes numeric;
begin
  select service_types.id into v_type
  from public.service_types where service_types.name = 'Pot Washing';

  -- Twelve hours in one day, in six two-hour acts.
  for v_n in 1 .. 6 loop
    insert into public.service_instances (
      service_type_id, date, start_time, duration_minutes, slots_needed,
      participation_mode, posted_by, status
    ) values (
      v_type, v_week_start, time '06:00' + ((v_n - 1) * interval '2 hours'),
      120, 1, 'open', null, 'completed'
    ) returning id into v_instance;
    insert into public.service_assignments (
      service_instance_id, devotee_id, assignment_method, status,
      verification, attendance
    ) values (v_instance, v_id, 'self_joined', 'completed', 'member_verified', 'served');
  end loop;

  select sum(acts.credited_minutes) into v_day_minutes
  from public.seva_mala_acts(v_id) acts
  where acts.occurred_on = v_week_start;

  if round(v_day_minutes) <> 480 then
    raise exception 'Twelve hours in one day credited % minutes rather than eight hours.',
      round(v_day_minutes);
  end if;

  -- Eight hours a day for six more days: fifty-six hours offered in a week.
  for v_n in 1 .. 6 loop
    insert into public.service_instances (
      service_type_id, date, start_time, duration_minutes, slots_needed,
      participation_mode, posted_by, status
    ) values (v_type, v_week_start + v_n, time '06:00', 480, 1, 'open', null, 'completed')
    returning id into v_instance;
    insert into public.service_assignments (
      service_instance_id, devotee_id, assignment_method, status,
      verification, attendance
    ) values (v_instance, v_id, 'self_joined', 'completed', 'member_verified', 'served');
  end loop;

  select sum(acts.credited_minutes) into v_week_minutes
  from public.seva_mala_acts(v_id) acts
  where acts.occurred_on between v_week_start and v_week_start + 6;

  if round(v_week_minutes) <> 1800 then
    raise exception 'Fifty-six hours in a week credited % minutes rather than thirty hours.',
      round(v_week_minutes);
  end if;

  -- A day of absences spends none of the next day's cap.
  insert into public.service_instances (
    service_type_id, date, start_time, duration_minutes, slots_needed,
    participation_mode, posted_by, status
  ) values (v_type, v_week_start - 1, time '06:00', 480, 1, 'open', null, 'completed')
  returning id into v_instance;
  insert into public.service_assignments (
    service_instance_id, devotee_id, assignment_method, status,
    verification, attendance
  ) values (v_instance, v_id, 'self_joined', 'completed', 'self_report', 'absent');

  insert into public.service_instances (
    service_type_id, date, start_time, duration_minutes, slots_needed,
    participation_mode, posted_by, status
  ) values (v_type, v_week_start - 1, time '14:00', 480, 1, 'open', null, 'completed')
  returning id into v_instance;
  insert into public.service_assignments (
    service_instance_id, devotee_id, assignment_method, status,
    verification, attendance
  ) values (v_instance, v_id, 'self_joined', 'completed', 'member_verified', 'served');

  -- Summed over the acts that earn something, not over the day: a cap applied
  -- to the absence as well as the seva would still total 480 across the two
  -- rows while quietly halving the eight hours actually served.
  select sum(acts.credited_minutes) into v_day_minutes
  from public.seva_mala_acts(v_id) acts
  where acts.occurred_on = v_week_start - 1 and acts.quality > 0;
  if round(v_day_minutes) <> 480 then
    raise exception
      'Eight hours served alongside eight hours absent credited % minutes.', round(v_day_minutes);
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 15b. A frozen period refuses to be recomputed, asked directly.
--
--      recompute_seva_mala only ever offers it unfrozen periods, so the guard
--      inside recompute_seva_mala_period is unreachable from the nightly job
--      and would never be exercised by testing the job. It is the guard that
--      protects a President at a psql prompt, so it is tested the way a
--      President would trip it.
-- ---------------------------------------------------------------------------

do $$
declare
  v_period uuid;
  v_returned integer;
  v_computed timestamptz;
  v_after timestamptz;
begin
  select periods.id, periods.computed_at into v_period, v_computed
  from public.seva_mala_periods periods
  where periods.period_kind = 'week'
    and periods.starts_on = public.seva_mala_week_start(public.seva_mala_today() - 7);

  v_returned := public.recompute_seva_mala_period(v_period);
  if v_returned <> 0 then
    raise exception 'Recomputing a frozen week rebuilt % rows.', v_returned;
  end if;

  select periods.computed_at into v_after
  from public.seva_mala_periods periods where periods.id = v_period;
  if v_after is distinct from v_computed then
    raise exception 'A frozen week was recomputed when asked directly.';
  end if;

  if exists (
    select 1 from public.period_scores scores
    join public.seva_mala_snapshots snapshot
      on snapshot.devotee_id = scores.devotee_id and snapshot.label = 'closed_week'
    where scores.period_id = v_period and scores.score <> snapshot.score
  ) then
    raise exception 'The frozen week''s scores moved under a direct recompute.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 16. period_scores is not readable by a signed-in devotee. In any form.
--
--     The single most important assertion in this file. Every table, every
--     column, every role, and the internal functions with it.
-- ---------------------------------------------------------------------------

do $$
declare
  v_table text;
  v_column text;
  v_function text;
begin
  foreach v_table in array array[
    'public.period_scores', 'public.seva_mala_periods', 'public.seva_type_weights'
  ] loop
    foreach v_column in array array['select', 'insert', 'update', 'delete'] loop
      if has_table_privilege('authenticated', v_table, v_column) then
        raise exception 'authenticated can % %.', v_column, v_table;
      end if;
      if has_table_privilege('anon', v_table, v_column) then
        raise exception 'anon can % %.', v_column, v_table;
      end if;
    end loop;

    if not (select relrowsecurity from pg_class where oid = v_table::regclass) then
      raise exception 'Row level security is off on %.', v_table;
    end if;

    if exists (
      select 1 from pg_policies
      where schemaname = 'public'
        and tablename = split_part(v_table, '.', 2)
        and 'authenticated' = any(roles)
    ) then
      raise exception 'A policy grants authenticated access to %.', v_table;
    end if;
  end loop;

  -- Column by column, because a column grant is not a table grant.
  for v_column in
    select attname from pg_attribute
    where attrelid = 'public.period_scores'::regclass and attnum > 0 and not attisdropped
  loop
    if has_column_privilege('authenticated', 'public.period_scores', v_column, 'select') then
      raise exception 'authenticated can read period_scores.%.', v_column;
    end if;
  end loop;

  -- The functions that would answer the same question a different way.
  foreach v_function in array array[
    'public.seva_mala_acts(uuid)',
    'public.recompute_seva_mala()',
    'public.recompute_seva_mala_period(uuid)',
    'public.recompute_seva_type_weights()',
    'public.award_seva_mala_for_period(uuid)',
    'public.ensure_seva_mala_period(text, date)',
    'public.seva_mala_number(text, numeric)'
  ] loop
    if has_function_privilege('authenticated', v_function, 'execute') then
      raise exception 'authenticated can execute %.', v_function;
    end if;
    if has_function_privilege('anon', v_function, 'execute') then
      raise exception 'anon can execute %.', v_function;
    end if;
  end loop;

  -- devotee_awards may be read, but only your own; award_definitions is public.
  -- Column grants rather than a table grant, so this is has_any_column, not
  -- has_table — the distinction is exactly what keeps a later column private.
  if not has_any_column_privilege('authenticated', 'public.award_definitions', 'select') then
    raise exception 'A devotee cannot see what the temple gives.';
  end if;
  if not has_any_column_privilege('authenticated', 'public.devotee_awards', 'select') then
    raise exception 'A devotee cannot see their own awards.';
  end if;
  foreach v_column in array array['insert', 'update', 'delete'] loop
    if has_table_privilege('authenticated', 'public.devotee_awards', v_column) then
      raise exception 'authenticated can % devotee_awards.', v_column;
    end if;
    if has_table_privilege('authenticated', 'public.award_definitions', v_column) then
      raise exception 'authenticated can % award_definitions.', v_column;
    end if;
  end loop;

  -- leaderboard_visible may be read but never written directly.
  if has_column_privilege('authenticated', 'public.users', 'leaderboard_visible', 'update') then
    raise exception 'authenticated can update users.leaderboard_visible directly.';
  end if;
end;
$$;

-- And under the role itself, which is the only test that counts.
set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.seva_mala_test_ids ids where ids.key = 'purse'), true);

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

  begin
    execute 'select public.recompute_seva_mala()' into v_count;
    raise exception 'A signed-in devotee ran the recompute.';
  exception
    when insufficient_privilege then null;
    when others then
      if sqlstate = 'P0001' then raise; end if;
  end;

  -- Their own row, through the only door there is, and only their own.
  select count(*) into v_count from public.my_seva_mala('lifetime');
  if v_count <> 1 then
    raise exception 'my_seva_mala returned % rows.', v_count;
  end if;

  begin
    select count(*) into v_count from public.list_all_seva_scores('lifetime');
    if v_count > 0 then
      raise exception 'A plain devotee read % rows of everybody''s scores.', v_count;
    end if;
  exception
    when insufficient_privilege then null;
    when others then
      if sqlstate = 'P0001' then raise; end if;
  end;
end;
$$;

-- explain_my_score is the caller's and nobody else's.
do $$
declare
  v_period uuid;
  v_rows integer;
  v_explained record;
begin
  select mine.period_id into v_period from public.my_seva_mala('lifetime') mine;

  select count(*) into v_rows from public.explain_my_score(v_period);
  if v_rows <> 1 then
    raise exception 'explain_my_score returned % rows for the caller.', v_rows;
  end if;

  select * into v_explained from public.explain_my_score(v_period);

  if v_explained.giving_cents <> 250000 then
    raise exception 'The working shows % cents rather than the caller''s own $2,500.',
      v_explained.giving_cents;
  end if;
  if v_explained.balance_beta <> 0.5 then
    raise exception 'The working reports beta as %.', v_explained.balance_beta;
  end if;
  -- Above the congregation's reference, and under the ceiling: the soft cap,
  -- shown to the devotee it applied to. 202608040062 added the two dials that
  -- make this re-derivable, so they are checked here as well.
  if v_explained.giving_norm <= 1
    or v_explained.giving_norm > v_explained.norm_ceiling then
    raise exception 'The working shows g-hat = % against a ceiling of %.',
      v_explained.giving_norm, v_explained.norm_ceiling;
  end if;
  if v_explained.soft_cap_alpha <> 0.15
    or v_explained.norm_ceiling <> 1 + v_explained.balance_beta then
    raise exception 'The working reports alpha % and a ceiling of %.',
      v_explained.soft_cap_alpha, v_explained.norm_ceiling;
  end if;
  -- And the devotee can re-derive their own norm from what they were handed.
  if public.seva_mala_normalise(
       v_explained.giving_utility, v_explained.giving_reference,
       v_explained.soft_cap_alpha, v_explained.norm_ceiling)
     <> v_explained.giving_norm then
    raise exception 'The working does not re-derive the norm it reports.';
  end if;

  -- The arithmetic in the explanation is the arithmetic that produced the score.
  if round(
       (greatest(v_explained.seva_norm, v_explained.giving_norm)
        + v_explained.balance_beta
          * least(v_explained.seva_norm, v_explained.giving_norm))
       / (1 + v_explained.balance_beta), 6) <> v_explained.score
  then
    raise exception 'The explanation does not reproduce the score it explains.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);

-- ---------------------------------------------------------------------------
-- 17. What the President sees, and only the President.
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.seva_mala_test_ids ids where ids.key = 'president'), true);

do $$
declare
  v_rows integer;
  v_hidden integer;
begin
  select count(*) into v_rows from public.list_all_seva_scores('lifetime');
  if v_rows <> 12 then
    raise exception 'The President sees % devotees rather than all twelve.', v_rows;
  end if;

  select count(*) into v_hidden
  from public.list_all_seva_scores('lifetime') everybody where everybody.is_hidden;
  if v_hidden <> 1 then
    raise exception 'The President sees % hidden devotees rather than one.', v_hidden;
  end if;

  select count(*) into v_hidden
  from public.list_all_seva_scores('lifetime') everybody
  join public.seva_mala_test_ids ids on ids.id = everybody.devotee_id
  where ids.key = 'hidden' and everybody.is_hidden;
  if v_hidden <> 1 then
    raise exception 'The devotee who opted out is not flagged to the President.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 18. Opting in and out changes exactly one thing.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.seva_mala_test_ids ids where ids.key = 'hidden'), true);

do $$
declare
  v_score_before numeric;
  v_score_after numeric;
  v_awards_before integer;
  v_awards_after integer;
  v_on_board integer;
  v_result boolean;
begin
  select mine.score, mine.awards_earned into v_score_before, v_awards_before
  from public.my_seva_mala('lifetime') mine;

  select count(*) into v_on_board
  from public.list_seva_garland('lifetime', 50) garland
  join public.seva_mala_test_ids ids on ids.id = garland.devotee_id
  where ids.key = 'hidden';
  if v_on_board <> 0 then
    raise exception 'Hidden was on the garland before opting in.';
  end if;

  v_result := public.set_my_leaderboard_visibility(true);
  if not v_result then
    raise exception 'set_my_leaderboard_visibility(true) returned %.', v_result;
  end if;

  select count(*) into v_on_board
  from public.list_seva_garland('lifetime', 50) garland
  join public.seva_mala_test_ids ids on ids.id = garland.devotee_id
  where ids.key = 'hidden';
  if v_on_board <> 1 then
    raise exception 'Hidden opted in and is still not on the garland.';
  end if;

  select mine.score, mine.awards_earned into v_score_after, v_awards_after
  from public.my_seva_mala('lifetime') mine;
  if v_score_after <> v_score_before or v_awards_after <> v_awards_before then
    raise exception 'Opting in changed the score or the awards. It is display only.';
  end if;

  perform public.set_my_leaderboard_visibility(false);
end;
$$;

-- A devotee cannot write the flag directly. The id is read from the fixture
-- table rather than from auth.uid(), because `authenticated` has no rights on
-- the auth schema and a failure there would look like the refusal under test.
do $$
declare
  v_me uuid;
begin
  select ids.id into v_me from public.seva_mala_test_ids ids where ids.key = 'hidden';
  begin
    execute format(
      'update public.users set leaderboard_visible = true where id = %L', v_me);
    raise exception 'A devotee set their own leaderboard_visible without the RPC.';
  exception
    when insufficient_privilege then null;
    when others then
      if sqlstate = 'P0001' then raise; end if;
  end;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);

-- ---------------------------------------------------------------------------
-- 19. The President's gift, and the fact that it cannot be reached for.
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.seva_mala_test_ids ids where ids.key = 'president'), true);

do $$
declare
  v_award public.devotee_awards;
  v_hands uuid;
  v_slipped boolean := false;
begin
  select ids.id into v_hands from public.seva_mala_test_ids ids where ids.key = 'hands';

  v_award := public.award_discretionary_gift(
    v_hands, 'presidents_gift', 'For sitting with Govinda Das through his last week.');

  if v_award.citation is null then
    raise exception 'The citation was dropped.';
  end if;
  if v_award.awarded_by is null then
    raise exception 'Nobody is recorded as having given the award.';
  end if;
  if v_award.period_id is not null then
    raise exception 'A discretionary gift was tied to a period.';
  end if;

  -- An earned award cannot be handed out by hand.
  --
  -- The success is recorded in a flag and raised AFTER the block rather than
  -- inside it. Raising inside the block hands the message to the block's own
  -- exception handler, which then decides whether the failure message looks
  -- enough like a refusal to be swallowed — and a message about giving a
  -- garland by hand contains most of the words a refusal would.
  begin
    perform public.award_discretionary_gift(v_hands, 'garland_seva', null);
    v_slipped := true;
  exception
    when others then
      if position('earned rather than given' in sqlerrm) = 0 then raise; end if;
  end;
  if v_slipped then
    raise exception 'A garland was given by hand rather than earned.';
  end if;

  -- The same gift again is a second occasion, not a duplicate.
  perform public.award_discretionary_gift(v_hands, 'presidents_gift', 'And again, in June.');
end;
$$;

-- Fulfilment: once, by the temple, never by the recipient.
do $$
declare
  v_award uuid;
  v_updated public.devotee_awards;
  v_slipped boolean := false;
begin
  select awards.id into v_award
  from public.devotee_awards awards
  join public.award_definitions definitions on definitions.id = awards.award_definition_id
  where definitions.code = 'presidents_gift'
  order by awards.created_at limit 1;

  v_updated := public.record_award_fulfilment(v_award, null, 'Handed over after Sunday feast.');
  if v_updated.fulfilled_on is null then
    raise exception 'The fulfilment date was not recorded.';
  end if;
  if v_updated.fulfilment_note is null then
    raise exception 'The fulfilment note was not recorded.';
  end if;

  begin
    perform public.record_award_fulfilment(v_award, null, 'Again.');
    v_slipped := true;
  exception
    when others then
      if position('already' in sqlerrm) = 0 then raise; end if;
  end;
  if v_slipped then
    raise exception 'An award was recorded as given out twice.';
  end if;
end;
$$;

-- The recipient may not mark their own.
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.seva_mala_test_ids ids where ids.key = 'hands'), true);

do $$
declare
  v_award uuid;
  v_me uuid;
  v_slipped boolean := false;
begin
  select ids.id into v_me from public.seva_mala_test_ids ids where ids.key = 'hands';

  select awards.id into v_award
  from public.devotee_awards awards
  join public.award_definitions definitions on definitions.id = awards.award_definition_id
  where definitions.code = 'presidents_gift' and awards.fulfilled_on is null
  limit 1;

  if v_award is null then
    raise exception 'The recipient cannot even see the award they were given.';
  end if;

  begin
    perform public.record_award_fulfilment(v_award, null, 'I got it, honest.');
    v_slipped := true;
  exception
    when others then
      if position('President' in sqlerrm) = 0 then raise; end if;
  end;
  if v_slipped then
    raise exception 'A devotee recorded their own award as fulfilled.';
  end if;

  begin
    perform public.award_discretionary_gift(v_me, 'presidents_gift', 'For me.');
    v_slipped := true;
  exception
    when others then
      if position('President' in sqlerrm) = 0 then raise; end if;
  end;
  if v_slipped then
    raise exception 'A devotee gave themselves the President''s gift.';
  end if;

  -- A devotee sees their own awards and nobody else's.
  if not exists (
    select 1 from public.devotee_awards awards where awards.devotee_id = v_me
  ) then
    raise exception 'A devotee cannot see their own awards.';
  end if;
  if exists (
    select 1 from public.devotee_awards awards where awards.devotee_id <> v_me
  ) then
    raise exception 'A devotee can read somebody else''s awards.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);

-- Append-only, against every path including this one.
do $$
declare
  v_award uuid;
  v_slipped boolean := false;
begin
  select awards.id into v_award from public.devotee_awards awards limit 1;

  begin
    delete from public.devotee_awards where devotee_awards.id = v_award;
    v_slipped := true;
  exception
    when others then
      if position('append-only' in sqlerrm) = 0 then raise; end if;
  end;
  if v_slipped then raise exception 'An award was deleted.'; end if;

  begin
    update public.devotee_awards set devotee_id = (
      select ids.id from public.seva_mala_test_ids ids where ids.key = 'purse'
    ) where devotee_awards.id = v_award;
    v_slipped := true;
  exception
    when others then
      if position('Only fulfilment' in sqlerrm) = 0 then raise; end if;
  end;
  if v_slipped then raise exception 'An award was moved to another devotee.'; end if;

  begin
    update public.devotee_awards set citation = 'rewritten'
    where devotee_awards.id = v_award;
    v_slipped := true;
  exception
    when others then
      if position('Only fulfilment' in sqlerrm) = 0 then raise; end if;
  end;
  if v_slipped then raise exception 'An award citation was rewritten.'; end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 20. Chicago, from wherever the session happens to be sitting.
--
--     A gift that arrives at 04:30 UTC on a Monday arrived at 23:30 the
--     previous night in Chicago, which is the Sunday that closed the week
--     before. Every session below must agree about that.
-- ---------------------------------------------------------------------------

do $$
declare
  v_zone text;
  v_week date;
  v_month date;
  v_day date;
  v_first date;
  v_expected_week date;
  v_expected_day date;
begin
  -- A Monday, and the moment 04:30 UTC on it.
  v_expected_week := date '2026-08-03';
  v_expected_day := date '2026-08-02';

  foreach v_zone in array array[
    'UTC', 'Asia/Kolkata', 'America/Los_Angeles', 'Pacific/Kiritimati', 'America/Chicago'
  ] loop
    execute format('set local timezone to %L', v_zone);

    v_week := public.seva_mala_period_start('week', date '2026-08-05');
    if v_week <> v_expected_week then
      raise exception 'In % the week of 5 August starts on % rather than %.',
        v_zone, v_week, v_expected_week;
    end if;

    -- Sunday belongs to the week that began six days earlier, not the next one.
    v_week := public.seva_mala_period_start('week', date '2026-08-09');
    if v_week <> v_expected_week then
      raise exception 'In % Sunday 9 August is put in the week starting %.', v_zone, v_week;
    end if;

    v_month := public.seva_mala_period_start('month', date '2026-08-31');
    if v_month <> date '2026-08-01' then
      raise exception 'In % the month of 31 August starts on %.', v_zone, v_month;
    end if;
    v_month := public.seva_mala_period_end('month', date '2026-02-05');
    if v_month <> date '2026-02-28' then
      raise exception 'In % February 2026 ends on %.', v_zone, v_month;
    end if;

    -- The reading that actually decides which period a gift lands in.
    v_day := (timestamptz '2026-08-03 04:30+00' at time zone 'America/Chicago')::date;
    if v_day <> v_expected_day then
      raise exception
        'In % a gift at 04:30 UTC on Monday is dated % rather than the Sunday before.',
        v_zone, v_day;
    end if;
    if public.seva_mala_period_start('week', v_day) >= v_expected_week then
      raise exception 'In % that Sunday gift landed in the following week.', v_zone;
    end if;

    -- Lifetime never ends, in any timezone.
    v_first := public.seva_mala_period_start('lifetime', date '2026-08-05');
    if v_first <> date '1970-01-01' then
      raise exception 'In % lifetime starts on %.', v_zone, v_first;
    end if;
  end loop;

  reset timezone;
end;
$$;

-- The same question asked of the whole machine rather than of the helpers.
--
-- A gift arriving at 04:30 UTC on the Monday this week began arrived at 23:30
-- the previous night in Chicago, on the Sunday that closed the week before. The
-- current week must therefore stay empty. The recompute is run with the SESSION
-- pinned to UTC, which is what makes this decisive: a reading of received_at
-- that used the session's day instead of Chicago's would date the gift Monday,
-- put it in the running week, and this would catch it. Supabase runs its cron
-- in UTC, so this is not a hypothetical session.
do $$
declare
  v_current uuid;
  v_participants integer;
  v_donor uuid;
begin
  select ids.id into v_donor from public.seva_mala_test_ids ids where ids.key = 'nanda';

  insert into public.donations (
    donor_id, donor_name, amount_cents, kind, external_payment_id, received_at
  ) values (
    v_donor, 'nanda', 9900, 'one_time', 'sm-midnight',
    (public.seva_mala_week_start(public.seva_mala_today())::timestamp + interval '4 hours 30 minutes')
      at time zone 'UTC'
  );

  set local timezone to 'UTC';
  perform public.recompute_seva_mala();
  reset timezone;

  select periods.id, periods.participant_count into v_current, v_participants
  from public.seva_mala_periods periods
  where periods.period_kind = 'week'
    and periods.starts_on = public.seva_mala_week_start(public.seva_mala_today());

  if v_participants <> 0 then
    raise exception
      'A gift at 04:30 UTC on Monday put % devotees into the running week. It arrived on Sunday night in Chicago.',
      v_participants;
  end if;
  if exists (select 1 from public.period_scores where period_id = v_current) then
    raise exception 'The Sunday-night gift was scored against the week that had not begun.';
  end if;

  delete from public.donations where external_payment_id = 'sm-midnight';
  perform public.recompute_seva_mala();
end;
$$;

-- Every boundary in the migration goes through Chicago and nothing else.
do $$
declare
  v_function text;
  v_body text;
begin
  foreach v_function in array array[
    'public.seva_mala_acts(uuid)',
    'public.recompute_seva_mala_period(uuid)',
    'public.recompute_seva_type_weights()',
    'public.seva_mala_today()'
  ] loop
    v_body := pg_get_functiondef(v_function::regprocedure);
    if position('current_date' in v_body) > 0 then
      raise exception '% uses current_date, which is the session''s day and not Chicago''s.',
        v_function;
    end if;
    if position('now()::date' in v_body) > 0 then
      raise exception '% casts now() to a date without going through Chicago.', v_function;
    end if;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- 21. Scarcity is measured, and stays inside the clamp.
--
--     Deliberately last, because it adds instances of other service types and
--     therefore moves every weight — including the 1.0 that sections 3 to 13
--     depend on. Three types with a real spread: one nobody will do at an hour
--     nobody keeps, one everybody does at the usual time, one in between.
-- ---------------------------------------------------------------------------

do $$
declare
  v_scarce uuid;
  v_common uuid;
  v_middle uuid;
  v_unfilled uuid;
  v_unfilled_weight numeric;
  v_anchor date := public.seva_mala_week_start(public.seva_mala_today()) - 20;
  v_instance uuid;
  v_n integer;
  v_devotee uuid;
  v_scarce_weight numeric;
  v_common_weight numeric;
  v_custom numeric;
  v_out integer;
begin
  select service_types.id into v_scarce
  from public.service_types where service_types.name = 'Mangal Arati Setup';
  select service_types.id into v_common
  from public.service_types where service_types.name = 'Prasadam Serving';
  select service_types.id into v_middle
  from public.service_types where service_types.name = 'Temple Room Cleaning';
  select service_types.id into v_unfilled
  from public.service_types where service_types.name = 'Sunday Feast Cleanup';

  select ids.id into v_devotee from public.seva_mala_test_ids ids where ids.key = 'lila';

  -- Scarce: 4am, twenty slots asked for, two filled, one person doing it, and
  -- a queue of refusals.
  for v_n in 1 .. 6 loop
    insert into public.service_instances (
      service_type_id, date, start_time, duration_minutes, slots_needed,
      participation_mode, posted_by, status
    ) values (v_scarce, v_anchor + v_n, time '04:00', 120, 20, 'open', null, 'completed')
    returning id into v_instance;

    if v_n <= 2 then
      insert into public.service_assignments (
        service_instance_id, devotee_id, assignment_method, status,
        verification, attendance
      ) values (v_instance, v_devotee, 'self_joined', 'completed', 'member_verified', 'served');
    end if;

    insert into public.service_offers (service_instance_id, offered_to, offered_by, status)
    select v_instance, ids.id,
           (select p.id from public.seva_mala_test_ids p where p.key = 'president'),
           'declined'
    from public.seva_mala_test_ids ids
    where ids.key in ('hands', 'purse', 'balance', 'steady', 'gauri', 'asha');
  end loop;

  -- Common: the usual hour, always filled, by everybody.
  for v_n in 1 .. 6 loop
    insert into public.service_instances (
      service_type_id, date, start_time, duration_minutes, slots_needed,
      participation_mode, posted_by, status
    ) values (v_common, v_anchor + v_n, time '12:00', 120, 2, 'open', null, 'completed')
    returning id into v_instance;

    insert into public.service_assignments (
      service_instance_id, devotee_id, assignment_method, status,
      verification, attendance
    )
    select v_instance, ids.id, 'self_joined', 'completed', 'member_verified', 'served'
    from public.seva_mala_test_ids ids
    where ids.key in (
      (array['hands','purse','balance','steady','gauri','asha'])[v_n],
      (array['bhakta','chandra','lila','nanda','kirtan','hidden'])[v_n]
    );

    insert into public.service_offers (service_instance_id, offered_to, offered_by, status)
    select v_instance, ids.id,
           (select p.id from public.seva_mala_test_ids p where p.key = 'president'),
           'accepted'
    from public.seva_mala_test_ids ids
    where ids.key in ('hands', 'purse', 'balance');
  end loop;

  -- Middle: the usual hour, half filled.
  for v_n in 1 .. 6 loop
    insert into public.service_instances (
      service_type_id, date, start_time, duration_minutes, slots_needed,
      participation_mode, posted_by, status
    ) values (v_middle, v_anchor + v_n, time '11:00', 120, 4, 'open', null, 'completed')
    returning id into v_instance;
    insert into public.service_assignments (
      service_instance_id, devotee_id, assignment_method, status,
      verification, attendance
    )
    select v_instance, ids.id, 'self_joined', 'completed', 'member_verified', 'served'
    from public.seva_mala_test_ids ids
    where ids.key in ('steady', 'gauri');
  end loop;

  -- A fourth type that differs from the popular one in ONE thing only: the
  -- same hour, the same twelve devotees, the same accepted offers, and slots
  -- the temple could not fill. Without it, three of the four scarcity terms
  -- point the same way in this fixture and a sign error in any single one of
  -- them is outvoted by the other three.
  for v_n in 1 .. 6 loop
    insert into public.service_instances (
      service_type_id, date, start_time, duration_minutes, slots_needed,
      participation_mode, posted_by, status
    ) values (v_unfilled, v_anchor + v_n, time '12:00', 120, 30, 'open', null, 'completed')
    returning id into v_instance;

    insert into public.service_assignments (
      service_instance_id, devotee_id, assignment_method, status,
      verification, attendance
    )
    select v_instance, ids.id, 'self_joined', 'completed', 'member_verified', 'served'
    from public.seva_mala_test_ids ids
    where ids.key in (
      (array['hands','purse','balance','steady','gauri','asha'])[v_n],
      (array['bhakta','chandra','lila','nanda','kirtan','hidden'])[v_n]
    );

    insert into public.service_offers (service_instance_id, offered_to, offered_by, status)
    select v_instance, ids.id,
           (select p.id from public.seva_mala_test_ids p where p.key = 'president'),
           'accepted'
    from public.seva_mala_test_ids ids
    where ids.key in ('hands', 'purse', 'balance');
  end loop;

  perform public.recompute_seva_type_weights();

  select weight into v_unfilled_weight from public.seva_type_weights
  where service_type_id = v_unfilled;
  select weight into v_common_weight from public.seva_type_weights
  where service_type_id = v_common;

  if v_unfilled_weight <= v_common_weight then
    raise exception
      'Two seva at the same hour with the same servers weigh % (12 of 30 slots filled) and % (all filled). The fill-rate term has the wrong sign.',
      v_unfilled_weight, v_common_weight;
  end if;

  if (select fill_rate from public.seva_type_weights where service_type_id = v_unfilled)
     >= (select fill_rate from public.seva_type_weights where service_type_id = v_common)
  then
    raise exception 'The fill rate was not measured: the half-empty seva reads as full.';
  end if;

  select weight into v_scarce_weight from public.seva_type_weights
  where service_type_id = v_scarce;
  select weight into v_common_weight from public.seva_type_weights
  where service_type_id = v_common;

  if v_scarce_weight is null or v_common_weight is null then
    raise exception 'Scarcity was not measured for one of the types.';
  end if;
  if v_scarce_weight <= v_common_weight then
    raise exception
      '4am deity worship nobody will do weighs % and the popular midday seva %.',
      v_scarce_weight, v_common_weight;
  end if;

  -- The clamp, which is what keeps hours dominant.
  select count(*) into v_out from public.seva_type_weights
  where weight < 0.75 or weight > 1.75;
  if v_out > 0 then
    raise exception '% service types escaped the clamp.', v_out;
  end if;

  -- The whole available spread is at most 2.33x. An hour is still an hour.
  if (select max(weight) / min(weight) from public.seva_type_weights) > 2.34 then
    raise exception 'The weights span more than the clamp allows.';
  end if;

  -- Custom-named seva is neutral, always: it has no history to measure.
  insert into public.service_instances (
    service_type_id, custom_name, date, start_time, duration_minutes, slots_needed,
    participation_mode, posted_by, status
  ) values (
    null, 'Sitting with a devotee in hospital', v_anchor + 1, time '04:00',
    120, 1, 'open', null, 'completed'
  ) returning id into v_instance;
  insert into public.service_assignments (
    service_instance_id, devotee_id, assignment_method, status,
    verification, attendance
  ) values (v_instance, v_devotee, 'self_joined', 'completed', 'member_verified', 'served');

  select acts.weight into v_custom
  from public.seva_mala_acts(v_devotee) acts
  where acts.service_instance_id = v_instance;
  if v_custom <> 1.0 then
    raise exception 'Custom-named seva was weighted at % rather than neutral.', v_custom;
  end if;

  -- And nothing anywhere hardcodes a per-type multiplier.
  if position('Mangal' in pg_get_functiondef(
       'public.recompute_seva_type_weights()'::regprocedure)) > 0
    or position('kitchen' in pg_get_functiondef(
       'public.seva_mala_acts(uuid)'::regprocedure)) > 0
  then
    raise exception 'A service type or category is named in the weighting code.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 21b. A thin congregation that is not an empty one.
--
--      Section 11 proved the gathering flag on a week with nobody in it, which
--      is the easy case and, on its own, a weak test: a board that publishes
--      everybody it has still returns no rows when it has nobody. Five
--      newcomers serve in the running week — a real congregation, under the
--      minimum of eight — and the board must STILL refuse to rank them. This
--      is deliberately the last thing done to the scores, because it changes
--      the running week and every assertion above was made against the shape
--      the running week had before.
-- ---------------------------------------------------------------------------

do $$
declare
  v_type uuid;
  v_today date := public.seva_mala_today();
  v_id uuid;
  v_instance uuid;
  v_n integer;
  v_count integer;
begin
  select service_types.id into v_type
  from public.service_types where service_types.name = 'Pot Washing';

  for v_n in 1 .. 5 loop
    v_id := ('50000000-0000-0000-0000-0000000000' || (50 + v_n)::text)::uuid;
    insert into auth.users (id, email, raw_user_meta_data)
    values (v_id, 'smt-new' || v_n || '@example.test',
            jsonb_build_object('name', 'Newcomer ' || v_n));
    update public.users set leaderboard_visible = true where users.id = v_id;

    insert into public.service_instances (
      service_type_id, date, start_time, duration_minutes, slots_needed,
      participation_mode, posted_by, status
    ) values (v_type, v_today, time '08:00', 60 * v_n, 1, 'open', null, 'completed')
    returning id into v_instance;

    insert into public.service_assignments (
      service_instance_id, devotee_id, assignment_method, status,
      verification, attendance
    ) values (v_instance, v_id, 'self_joined', 'completed', 'member_verified', 'served');
  end loop;

  perform public.recompute_seva_mala();

  select periods.participant_count into v_count
  from public.seva_mala_periods periods
  where periods.period_kind = 'week' and periods.starts_on = public.seva_mala_week_start(v_today);

  if v_count <> 5 then
    raise exception 'The running week has % devotees rather than the five newcomers.', v_count;
  end if;

  select count(*) into v_count
  from public.period_scores scores
  join public.seva_mala_periods periods on periods.id = scores.period_id
  where periods.period_kind = 'week'
    and periods.starts_on = public.seva_mala_week_start(v_today)
    and scores.score > 0;
  if v_count <> 5 then
    raise exception 'Only % of the five newcomers were scored.', v_count;
  end if;
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub',
  '50000000-0000-0000-0000-000000000051', true);

do $$
declare
  v_rows integer;
  v_gathering boolean;
  v_standing integer;
begin
  select count(*) into v_rows from public.list_seva_garland('week', 20);
  if v_rows <> 1 then
    raise exception
      'Five devotees, a minimum of eight, and the board published % rows.', v_rows;
  end if;

  select garland.gathering into v_gathering from public.list_seva_garland('week', 20) garland;
  if not v_gathering then
    raise exception 'Five devotees published a ranking instead of a gathering flag.';
  end if;

  -- The newcomer's own numbers are theirs; only the standing is withheld.
  select mine.standing into v_standing from public.my_seva_mala('week') mine;
  if v_standing is not null then
    raise exception 'A congregation of five published a standing of %.', v_standing;
  end if;

  select count(*) into v_rows
  from public.my_seva_mala('week') mine where mine.seva_minutes > 0;
  if v_rows <> 1 then
    raise exception 'The newcomer cannot see their own minutes in a thin week.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);

-- ---------------------------------------------------------------------------
-- 15c. The reference floor.
--
--      The floor is the guard against a tiny denominator, and the rest of the
--      design makes it almost impossible to reach: v_s and v_g are medians of
--      the same population the percentile is taken over, so the eightieth
--      percentile of ln(1 + total/median) sits at or above ln(2) by
--      construction. A guard that cannot be reached is a guard that cannot be
--      tested by waiting for it, so it is tested by moving it: raise the floor
--      above every reference in the fixture and every reference must rise to
--      meet it. Then put it back.
-- ---------------------------------------------------------------------------

do $$
declare
  v_below integer;
  v_min numeric;
begin
  -- The invariant, as it stands.
  select count(*) into v_below from public.seva_mala_periods
  where seva_reference < 0.6931471805599453
     or giving_reference < 0.6931471805599453;
  if v_below > 0 then
    raise exception '% periods carry a reference below the floor.', v_below;
  end if;

  update public.app_settings set value = '3.0' where key = 'seva_mala.reference_floor';
  update public.seva_mala_periods set frozen_at = null, computed_at = null;
  perform public.recompute_seva_mala();

  select min(least(seva_reference, giving_reference)) into v_min
  from public.seva_mala_periods;
  if v_min < 3.0 then
    raise exception 'A reference of % survived a floor of 3.0.', v_min;
  end if;

  update public.app_settings set value = '0.6931471805599453'
  where key = 'seva_mala.reference_floor';
  update public.seva_mala_periods set frozen_at = null, computed_at = null;
  perform public.recompute_seva_mala();
end;
$$;

-- ---------------------------------------------------------------------------
-- 22. The notification kind.
-- ---------------------------------------------------------------------------

do $$
declare
  v_definition text;
  v_missing text;
  v_kind text;
  v_sent integer;
begin
  select pg_get_constraintdef(pg_constraint.oid) into v_definition
  from pg_constraint
  where conname = 'app_notifications_kind_check'
    and conrelid = 'public.app_notifications'::regclass;

  if position('''seva_award_earned''' in v_definition) = 0 then
    raise exception 'seva_award_earned is not an allowed notification kind.';
  end if;

  -- The whole of 0052's list survived the restatement.
  foreach v_kind in array array[
    'service_open', 'service_offer', 'service_recurring_offer',
    'service_offer_response', 'service_joined', 'service_left',
    'service_started', 'service_completed', 'service_cancelled',
    'service_deleted', 'service_coverage_needed', 'service_coverage_resolved',
    'recurring_interest_submitted', 'recurring_interest_reviewed',
    'seva_verification_requested', 'seva_verification_reviewed',
    'weekly_offer_countered', 'weekly_offer_counter_reviewed',
    'access_request_submitted', 'access_request_reviewed',
    'devotee_joined', 'profile_incomplete', 'sanga_created', 'sanga_reviewed',
    'sanga_join_requested', 'sanga_join_reviewed', 'sanga_member_added',
    'sanga_member_removed', 'sanga_member_left', 'sanga_admin_transferred',
    'sanga_deleted', 'announcement_posted', 'feedback_reviewed', 'care_reply',
    'birthday_today', 'newsletter_posted', 'newsletter_reviewed',
    'access_appointed', 'access_revoked', 'sponsorship_fulfilled',
    'announcement_commented', 'announcement_comment_replied', 'remote'
  ] loop
    if position('''' || v_kind || '''' in v_definition) = 0 then
      v_missing := concat_ws(', ', v_missing, v_kind);
    end if;
  end loop;
  if v_missing is not null then
    raise exception 'The restated kind list dropped: %.', v_missing;
  end if;

  -- Every award told its devotee, and no award told anybody else.
  select count(*) into v_sent from public.app_notifications
  where app_notifications.kind = 'seva_award_earned';
  if v_sent <> (select count(*) from public.devotee_awards) then
    raise exception '% awards produced % notifications.',
      (select count(*) from public.devotee_awards), v_sent;
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
end;
$$;

-- ---------------------------------------------------------------------------
-- 23. Structure that must not drift.
-- ---------------------------------------------------------------------------

do $$
declare
  v_count integer;
begin
  -- The awards are a table, not a constraint. A President must be able to
  -- change them without a migration.
  if exists (
    select 1 from pg_constraint
    where conrelid = 'public.devotee_awards'::regclass
      and pg_get_constraintdef(oid) ilike '%garland%'
  ) then
    raise exception 'An award name was written into a CHECK constraint.';
  end if;

  -- 202608040055's three garlands are lateral: three definitions, one tier, no
  -- ordering, and each ranking on a different thing so that none of them is a
  -- grade of another.
  --
  -- Scoped to rotation_group is null because 202608040063 added the temple's
  -- seven Deity garlands, which are lateral by a DIFFERENT construction: they
  -- are identical in every respect including rank_basis, and take turns. There
  -- is no way for seven garlands to rank on seven different things — only three
  -- rank_basis values exist — so the rule below cannot be the test for those,
  -- and badges_and_gifts.sql tests them the way they are actually built.
  -- 0055's own three are still checked here exactly as they always were.
  select count(*) into v_count from public.award_definitions
  where tier = 'garland' and rotation_group is null;
  if v_count <> 3 then
    raise exception 'There are % ungrouped garlands rather than three.', v_count;
  end if;
  select count(distinct garland_kind) into v_count from public.award_definitions
  where tier = 'garland' and rotation_group is null;
  if v_count <> 3 then
    raise exception 'The three garlands are not distinguished from one another.';
  end if;
  if exists (
    select 1 from public.award_definitions a
    join public.award_definitions b
      on b.tier = 'garland' and b.rotation_group is null and b.id <> a.id
    where a.tier = 'garland' and a.rotation_group is null
      and a.rank_basis = b.rank_basis
  ) then
    raise exception 'Two garlands rank on the same thing, which makes them a ladder.';
  end if;

  -- All five rule kinds are represented, so none of them is dead code.
  select count(distinct rule_kind) into v_count from public.award_definitions;
  if v_count <> 5 then
    raise exception 'Only % of the five rule kinds are defined.', v_count;
  end if;

  -- Fulfilment mirrors sponsorship_bookings, column for column.
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'devotee_awards'
      and column_name = 'fulfilled_on' and data_type = 'date'
  ) or not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'devotee_awards'
      and column_name = 'fulfilment_note' and data_type = 'text'
  ) then
    raise exception 'devotee_awards does not mirror sponsorship_bookings'' fulfilment.';
  end if;

  -- leaderboard_visible defaults to false. Nobody is opted in by accident.
  if (
    select column_default from information_schema.columns
    where table_schema = 'public' and table_name = 'users'
      and column_name = 'leaderboard_visible'
  ) is distinct from 'false' then
    raise exception 'leaderboard_visible does not default to false.';
  end if;
  if (
    select is_nullable from information_schema.columns
    where table_schema = 'public' and table_name = 'users'
      and column_name = 'leaderboard_visible'
  ) <> 'NO' then
    raise exception 'leaderboard_visible is nullable.';
  end if;
end;
$$;

do $$
begin
  raise notice 'all seva mala checks passed';
end;
$$;

select 'seva mala verification passed' as result;

rollback;
