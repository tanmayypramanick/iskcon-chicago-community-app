-- Functional verification for 202608040059_seva_mala_fairness.sql.
--
-- Rolled back at the end. Every local is prefixed v_ so it can never shadow a
-- column name. Anything that must be refused is attempted as the devotee who
-- would really attempt it, under `set local role authenticated`, so the row
-- level security, the grants and the permission checks are what is being
-- tested rather than superuser rights waving everything through.
--
-- 0059 makes two corrections, and this file exists to prove both of them
-- happened and that nothing else did.
--
-- ---------------------------------------------------------------------------
-- 1. The balance rule, inverted.
--
--    score = ( max(s, g) + beta * min(s, g) ) / (1 + beta)      beta = 0.5
--
--    so the LARGER of a devotee's two offerings counts whole and the smaller
--    counts for half of itself. Serving and not giving, and giving and not
--    serving, both reach 2/3; doing both wholly reaches 1.
--
-- 2. Weekly seva earns its points on completion, with no verification and no
--    attendance mark, because a recurring instance carries posted_by null and
--    there was nobody left who could confirm it. Being marked absent, excused,
--    withdrawn or a no-show still zeroes it.
--
-- ---------------------------------------------------------------------------
-- The fixture is arithmetic, not decoration.
--
-- Eighteen devotees in the scoring cohort — well past 0055's minimum of eight,
-- so every congregation-relative reference in this file is a real percentile of
-- a real congregation. Every act of seva is 180 minutes and every gift is a
-- single gift, so the two units fall out by construction and nothing depends on
-- a median nobody can check:
--
--   v_s = 180 minutes    every devotee's median act is 180, so the median of
--                        medians is 180
--   v_g = 25,000 cents   ten donors, one gift each, the fifth and sixth of
--                        which are $200 and $300
--
-- Everything sits strictly BEFORE the current Chicago week begins, anchored on
-- last Sunday, which is what makes the script deterministic on any day of any
-- week: the lifetime period always contains the whole fixture and is the board
-- every ranking assertion is made against, and the running week always contains
-- none of it. Nobody's daily (480) or weekly (1800) cap is reached, so credited
-- minutes are served minutes and the arithmetic below is unclipped.
--
-- The seva side, u_s = ln(1 + S/180) over the ten devotees who serve:
--
--   sevak 2880 min  ln(17) = 2.8332133      s5    360 min  ln(3) = 1.0986123
--   both  1080 min  ln(7)  = 1.9459101      s6    180 min  ln(2) = 0.6931472
--   s1     900 min  ln(6)  = 1.7917595      s7    180 min  ln(2) = 0.6931472
--   s2     720 min  ln(5)  = 1.6094379      mixed 360 min  ln(3) = 1.0986123
--   s3     540 min  ln(4)  = 1.3862944
--   s4     540 min  ln(4)  = 1.3862944
--
--   ref_s = P80 of those ten = ln(6) + 0.2*(ln(7) - ln(6)) = 1.8225896
--
-- The giving side, u_g = ln(1 + G/25000) over the ten devotees who give:
--
--   donor $2,500  ln(11)  = 1.9459101       g4    $200  ln(1.8) = 0.5877867
--   both    $900  ln(4.6) = 1.5260563       mixed $150  ln(1.6) = 0.4700036
--   g1      $600  ln(3.4) = 1.2237754       g5    $100  ln(1.4) = 0.3364722
--   g2      $450  ln(2.8) = 1.0296194       g6     $50  ln(1.2) = 0.1823216
--   g3      $300  ln(2.2) = 0.7884574       g7     $25  ln(1.1) = 0.0953102
--
--   ref_g = P80 of those ten = ln(3.4) + 0.2*(ln(4.6) - ln(3.4)) = 1.2842316
--
-- Which puts the four archetypes the temple argued about exactly here:
--
--   sevak   48 hours, nothing given    s = 1.066173  g = 0.000000  0.710782
--   donor   $2,500, no time to serve   s = 0.000000  g = 1.093665  0.729110
--   both    18 hours and $900          s = 1.009821  g = 1.025879  1.020526
--   mixed   6 hours and $150           s = 0.602775  g = 0.365980  0.523843
--
-- 202608040062 made the cap soft. The first three devotees are all past their
-- reference and all three moved up from where 0055's cap held them — 0.666667,
-- 0.666667 and 1.000000 — while mixed, below both references, did not move by a
-- digit. sevak and donor are therefore no longer EQUAL: they were only ever
-- equal because the cap had made them the same number, and they do not stand at
-- the same multiple of their own reference (1.554 against 1.867). Equality at
-- EQUAL standing is what the temple asked for and it is proved at two standings
-- in fair_scaling.sql; what this file still asserts is that the two paths land
-- within five points of each other and adjacent on the board.
--
-- mixed — moderate at both — still comes behind both of them. Under 0055's rule
-- mixed scored 0.444912 and sevak and donor scored 0.333333 each, so that single
-- row is the whole change 0059 made: a devotee who is moderate at both no longer
-- outranks a devotee who is exceptional at one.
--
-- The cast:
--   sevak   ...0001  forty-eight hours, nothing given
--   donor   ...0002  $2,500, no seva. Gives $10,000 more in section 6, to no
--                    effect whatever, because the cap already holds them at 1
--   both    ...0003  eighteen hours and $900 — first outright
--   mixed   ...0004  six hours and $150 — moderate at both, and eighth
--   s1..s7  ...0005+ seva only, in descending order
--   g1..g7  ...0012+ giving only, in descending order
--   whale   ...0019  arrives in section 7 having served seventy-two hours, and
--                    drags the congregation's eightieth percentile up with him
--   pres    ...0020  app.view_all
--   wkly    ...0021  weekly seva, closed out and nothing else
--   wabs    ...0022  the same weekly seva, marked absent
--   wnos    ...0023  the same weekly seva, a no-show
--   wwdr    ...0024  the same weekly seva, withdrawn
--   wopen   ...0025  a weekly seva nobody closed out
--   once    ...0026  a one-off, still judged by 202608040057's whole rule
--
-- The final row must read: seva mala fairness verification passed

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
--    The dials this file's arithmetic is a function of, the two rules 0059
--    claims to have left alone, and the grants it claims not to have widened.
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
  loop
    if v_expected <> v_actual then
      raise exception 'Seva Mala dial mismatch: expected %, found %.', v_expected, v_actual;
    end if;
  end loop;

  -- Both arities must exist. The three-argument one is 202608040057's rule and
  -- is what one-off seva is still judged by; the four-argument one is 0059's.
  if to_regprocedure('public.seva_points_status(text, text, text)') is null then
    raise exception 'The three-argument rule is gone; one-off seva has nothing to be judged by.';
  end if;
  if to_regprocedure('public.seva_points_status(text, text, text, boolean)') is null then
    raise exception 'The four-argument rule is missing; 202608040059 did not apply.';
  end if;
  if to_regprocedure('public.seva_mala_score(numeric, numeric, numeric)') is null then
    raise exception 'public.seva_mala_score is missing; the balance is inline again.';
  end if;

  -- The four-argument overload must carry NO default, so a three-argument call
  -- can never silently pick up a recurrence flag nobody passed.
  if (
    select pronargdefaults from pg_proc
    where oid = 'public.seva_points_status(text, text, text, boolean)'::regprocedure
  ) <> 0 then
    raise exception
      'The recurrence flag has a default, so a three-argument call is now ambiguous.';
  end if;

  -- The balance must still be read from app_settings rather than typed into a
  -- function body, and it must be read by the named function rather than
  -- rewritten inline.
  if position('seva_mala.balance_beta' in pg_get_functiondef(
       'public.recompute_seva_mala_period(uuid)'::regprocedure)) = 0
  then
    raise exception 'balance_beta is no longer read from app_settings.';
  end if;
  if position('seva_mala_score' in pg_get_functiondef(
       'public.recompute_seva_mala_period(uuid)'::regprocedure)) = 0
  then
    raise exception 'The recompute no longer scores through public.seva_mala_score.';
  end if;
  if position('seva_mala.reference_quantile' in pg_get_functiondef(
       'public.recompute_seva_mala_period(uuid)'::regprocedure)) = 0
  then
    raise exception 'The reference percentile is not read from app_settings.';
  end if;

  -- Recurrence is read off the instance and nowhere else.
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'service_instances'
      and column_name = 'template_id'
  ) then
    raise exception 'public.service_instances has no template_id.';
  end if;

  -- Nothing here widened the components.
  if has_table_privilege('authenticated', 'public.period_scores', 'select')
    or has_table_privilege('authenticated', 'public.seva_mala_periods', 'select')
    or has_table_privilege('authenticated', 'public.app_settings', 'select')
  then
    raise exception 'authenticated can read the Seva Mala components.';
  end if;

  -- seva_mala_score is arithmetic over two numbers the caller supplies, so it
  -- is the devotee's to run. The recompute and the act list are not.
  if not has_function_privilege(
       'authenticated', 'public.seva_mala_score(numeric, numeric, numeric)', 'execute')
  then
    raise exception 'A devotee cannot check the working of their own score.';
  end if;
  if has_function_privilege(
       'authenticated', 'public.recompute_seva_mala_period(uuid)', 'execute')
    or has_function_privilege('authenticated', 'public.seva_mala_acts(uuid)', 'execute')
    or has_function_privilege(
         'authenticated', 'public.seva_mala_number(text, numeric)', 'execute')
  then
    raise exception 'A signed-in devotee can run the scoring machinery.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 1. The balance, as arithmetic, before any fixture exists.
--
--    The formula on its own terms, over the cases the temple named in words.
--    A pure sevak and a pure donor land on the same number; doing both wins;
--    doing a moderate amount of both does not beat doing one thing wholly; and
--    beta is a weight on the SMALLER offering, which is what makes 0 and 1 the
--    ends of the range and anything outside it a rule the temple rejected.
-- ---------------------------------------------------------------------------

do $$
declare
  v_case record;
  v_got numeric;
begin
  for v_case in
    select * from (values
      -- seva, giving, expected
      (1.0, 0.0, 0.666667),   -- serves and does not give
      (0.0, 1.0, 0.666667),   -- gives and has no time to serve
      (1.0, 1.0, 1.000000),   -- both, wholly
      (0.5, 0.5, 0.500000),   -- moderate at both, and behind either of the first two
      (1.0, 0.3, 0.766667),   -- serves wholly and gives a little
      (0.3, 1.0, 0.766667),   -- gives wholly and serves a little — the mirror image
      (0.0, 0.0, 0.000000)
    ) as c(seva, giving, expected)
  loop
    v_got := public.seva_mala_score(v_case.seva, v_case.giving, 0.5);
    if v_got <> v_case.expected then
      raise exception 'seva_mala_score(%, %, 0.5) is % rather than %.',
        v_case.seva, v_case.giving, v_got, v_case.expected;
    end if;
  end loop;

  -- The rule is symmetric in its two arguments. Whatever the pair, swapping
  -- seva for giving cannot change the number: that is "it depends on the
  -- devotees, not hardcoded" stated as an identity.
  if exists (
    select 1
    from generate_series(0, 10) as a(i)
    cross join generate_series(0, 10) as b(j)
    where public.seva_mala_score(a.i / 10.0, b.j / 10.0, 0.5)
       <> public.seva_mala_score(b.j / 10.0, a.i / 10.0, 0.5)
  ) then
    raise exception 'The balance is not symmetric: seva and giving are not interchangeable.';
  end if;

  -- And it is the LARGER offering that counts whole. If the terms were the
  -- other way round — 0055's rule — a devotee at (1, 0) would score 0.333333.
  if public.seva_mala_score(1.0, 0.0, 0.5) <= public.seva_mala_score(0.5, 0.5, 0.5) then
    raise exception
      'Giving one thing wholly does not beat being moderate at both. The smaller offering is still being weighted double.';
  end if;
  if public.seva_mala_score(1.0, 0.0, 0.5) <> 0.666667 then
    raise exception 'A one-dimensional devotee tops out at % rather than two thirds.',
      public.seva_mala_score(1.0, 0.0, 0.5);
  end if;

  -- The ends of the range mean what section 1 of the migration says they mean.
  if public.seva_mala_score(1.0, 1.0, 0) <> public.seva_mala_score(1.0, 0.0, 0) then
    raise exception 'At beta = 0 the second offering is still buying something.';
  end if;
  if public.seva_mala_score(1.0, 0.0, 1) <> 0.5 then
    raise exception 'At beta = 1 the rule is not the plain average.';
  end if;

  -- Nulls are nothing given, not an error and not a hole in the ranking.
  if public.seva_mala_score(null, 1.0, 0.5) <> 0.666667
    or public.seva_mala_score(1.0, null, 0.5) <> 0.666667
  then
    raise exception 'A missing offering is not read as zero.';
  end if;
end;
$$;

-- Beta outside [0, 1] would weight the smaller offering more than the larger,
-- which is the rule this migration inverted sneaking back in through the dial.
-- Refused, and refused to the devotee as well as to the machine.
set local role authenticated;

do $$
declare
  v_got numeric;
begin
  begin
    v_got := public.seva_mala_score(1.0, 0.0, 2);
    raise exception 'beta = 2 was accepted and scored %; the inverted rule is reachable through the dial.', v_got;
  exception
    when others then
      if sqlstate = 'P0001' and position('must lie in [0, 1]' in sqlerrm) = 0 then raise; end if;
  end;

  begin
    v_got := public.seva_mala_score(1.0, 0.0, 1.0001);
    raise exception 'beta just above 1 was accepted and scored %.', v_got;
  exception
    when others then
      if sqlstate = 'P0001' and position('must lie in [0, 1]' in sqlerrm) = 0 then raise; end if;
  end;

  begin
    v_got := public.seva_mala_score(1.0, 0.0, -0.5);
    raise exception 'A negative beta was accepted and scored %.', v_got;
  exception
    when others then
      if sqlstate = 'P0001' and position('must lie in [0, 1]' in sqlerrm) = 0 then raise; end if;
  end;

  begin
    v_got := public.seva_mala_score(1.0, 0.0, null);
    raise exception 'A null beta was accepted and scored %.', v_got;
  exception
    when others then
      if sqlstate = 'P0001' and position('must lie in [0, 1]' in sqlerrm) = 0 then raise; end if;
  end;
end;
$$;

reset role;

-- ---------------------------------------------------------------------------
-- 2. The eligibility rule, over its entire domain.
--
--    Five assignment statuses, four attendance marks, four verification levels:
--    eighty cells, asserted three times over. The one-off answer must be
--    202608040057's rule to the letter, whether it is asked of the three-
--    argument function, of the four-argument one with false, or of the four-
--    argument one with null — because "we do not know what kind of seva this
--    is" must withhold points rather than hand them out. The recurring answer
--    must be 0059's rule: closed out on its day is enough, and nothing else is.
--
--    Both rules are typed out here rather than borrowed from the migration, so
--    this stays an independent statement of what the temple asked for.
-- ---------------------------------------------------------------------------

do $$
declare
  v_status text;
  v_attendance text;
  v_verification text;
  v_expected_oneoff text;
  v_expected_recurring text;
  v_got text;
  v_cells integer := 0;
  v_differ integer := 0;
begin
  foreach v_status in array array['assigned', 'confirmed', 'completed', 'no_show', 'withdrawn'] loop
    foreach v_attendance in array array['served', 'absent', 'excused', '(null)'] loop
      foreach v_verification in array array['self_report', 'qr_scan', 'live_timer', 'member_verified'] loop
        v_cells := v_cells + 1;

        v_expected_oneoff := case
          when v_status in ('no_show', 'withdrawn') then 'not_served'
          when v_attendance in ('absent', 'excused') then 'not_served'
          when v_status <> 'completed' then 'awaiting_completion'
          when v_verification not in ('live_timer', 'qr_scan', 'member_verified')
            then 'awaiting_verification'
          when v_attendance <> 'served' then 'awaiting_confirmation'
          else 'counted'
        end;

        v_expected_recurring := case
          when v_status in ('no_show', 'withdrawn') then 'not_served'
          when v_attendance in ('absent', 'excused') then 'not_served'
          when v_status <> 'completed' then 'awaiting_completion'
          else 'counted'
        end;

        if v_expected_oneoff <> v_expected_recurring then
          v_differ := v_differ + 1;
        end if;

        -- One-off, asked three ways.
        v_got := public.seva_points_status(
          v_status, nullif(v_attendance, '(null)'), v_verification);
        if v_got is distinct from v_expected_oneoff then
          raise exception
            'The three-argument rule answers % for (%, %, %) rather than %. 202608040057''s rule has moved.',
            v_got, v_status, v_attendance, v_verification, v_expected_oneoff;
        end if;

        v_got := public.seva_points_status(
          v_status, nullif(v_attendance, '(null)'), v_verification, false);
        if v_got is distinct from v_expected_oneoff then
          raise exception
            'One-off seva (%, %, %) reads % rather than %. The weekly exemption is leaking into one-off seva.',
            v_status, v_attendance, v_verification, v_got, v_expected_oneoff;
        end if;

        v_got := public.seva_points_status(
          v_status, nullif(v_attendance, '(null)'), v_verification, null);
        if v_got is distinct from v_expected_oneoff then
          raise exception
            'Seva of unknown kind (%, %, %) reads % rather than the stricter %.',
            v_status, v_attendance, v_verification, v_got, v_expected_oneoff;
        end if;

        -- Recurring.
        v_got := public.seva_points_status(
          v_status, nullif(v_attendance, '(null)'), v_verification, true);
        if v_got is distinct from v_expected_recurring then
          raise exception
            'Weekly seva (%, %, %) reads % rather than %.',
            v_status, v_attendance, v_verification, v_got, v_expected_recurring;
        end if;
      end loop;
    end loop;
  end loop;

  if v_cells <> 80 then
    raise exception 'The rule was asked about % cells rather than 80.', v_cells;
  end if;

  -- The two rules must actually be different rules. If a mutation made them
  -- identical in either direction, every cell above would still pass its own
  -- comparison and only this would notice.
  -- Five, exactly: an act that is completed and not contradicted, where a
  -- one-off would still be waiting on a verification level (self_report, with
  -- attendance served or silent) or on somebody to say "served" (the three
  -- trusted levels, with attendance silent). Everything else the two rules
  -- already agreed about.
  if v_differ <> 5 then
    raise exception
      'Weekly and one-off seva differ in % of eighty cells rather than 5.', v_differ;
  end if;

  -- The four cells that are the whole point, spelled out.
  if public.seva_points_status('completed', null, 'self_report', true) <> 'counted' then
    raise exception 'A completed weekly act with no verification and no attendance is not counted.';
  end if;
  if public.seva_points_status('completed', null, 'self_report', false) <> 'awaiting_verification' then
    raise exception 'A completed one-off act with no verification is counted.';
  end if;
  if public.seva_points_status('completed', 'absent', 'member_verified', true) <> 'not_served' then
    raise exception 'A weekly act marked absent still earns.';
  end if;
  if public.seva_points_status('no_show', null, 'self_report', true) <> 'not_served' then
    raise exception 'A weekly no-show still earns.';
  end if;

  -- awaiting_verification and awaiting_confirmation are unreachable for weekly
  -- seva. A devotee must never be told a weekly act is waiting on somebody who
  -- was never going to come.
  if exists (
    select 1
    from unnest(array['assigned', 'confirmed', 'completed', 'no_show', 'withdrawn']) as s(status)
    cross join unnest(array['served', 'absent', 'excused', null]) as a(attendance)
    cross join unnest(array['self_report', 'qr_scan', 'live_timer', 'member_verified']) as v(level)
    where public.seva_points_status(s.status, a.attendance, v.level, true)
          in ('awaiting_verification', 'awaiting_confirmation')
  ) then
    raise exception 'Weekly seva can still read as waiting to be verified or confirmed.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. The congregation.
-- ---------------------------------------------------------------------------

do $$
declare
  v_who text;
  v_i integer := 0;
begin
  foreach v_who in array array[
    'sevak', 'donor', 'both', 'mixed',
    's1', 's2', 's3', 's4', 's5', 's6', 's7',
    'g1', 'g2', 'g3', 'g4', 'g5', 'g6', 'g7',
    'whale', 'pres', 'wkly', 'wabs', 'wnos', 'wwdr', 'wopen', 'once'
  ] loop
    v_i := v_i + 1;
    insert into auth.users (id, email, raw_user_meta_data)
    values (
      ('59000000-0000-0000-0000-0000000000' || lpad(v_i::text, 2, '0'))::uuid,
      'fv-' || v_who || '@example.test',
      jsonb_build_object('name', initcap(v_who) || ' Das')
    );
  end loop;
end;
$$;

update public.users
set role_id = (select roles.id from public.roles where roles.name = 'president')
where users.email = 'fv-pres@example.test';

update public.users
set leaderboard_visible = true
where users.email like 'fv-%@example.test';

-- Ordinary table rather than a temporary one, so reading it under the
-- authenticated role needs no assumptions about the temp schema. The whole
-- script is rolled back, so it never outlives the transaction.
create table public.seva_fv_ids (key text primary key, id uuid not null);
grant select on public.seva_fv_ids to authenticated;

insert into public.seva_fv_ids (key, id)
select split_part(split_part(users.email, '@', 1), 'fv-', 2), users.id
from public.users
where users.email like 'fv-%@example.test';

create table public.seva_fv_snapshots (
  label text not null,
  devotee_id uuid not null,
  seva_norm numeric,
  giving_norm numeric,
  giving_cents bigint,
  score numeric,
  primary key (label, devotee_id)
);

create table public.seva_fv_acts (key text primary key, assignment_id uuid not null);
grant select on public.seva_fv_acts to authenticated;

-- ---------------------------------------------------------------------------
-- 4. The facts.
--
--    Every act 180 minutes, so v_s is 180 by construction. Every gift a single
--    gift, so v_g is the plain median of ten. All of it strictly before this
--    week began, anchored on last Sunday, and laid out at most two acts a day
--    and eight a week so that no devotee reaches the 480-minute day or the
--    1,800-minute week and the credited minutes are the served minutes.
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
      ('sevak', 16, 2),
      ('both',   6, 1),
      ('s1',     5, 1),
      ('s2',     4, 1),
      ('s3',     3, 1),
      ('s4',     3, 1),
      ('mixed',  2, 1),
      ('s5',     2, 1),
      ('s6',     1, 1),
      ('s7',     1, 1)
    ) as plan(who, acts, per_day)
  loop
    for v_n in 1 .. v_plan.acts loop
      -- Blocks of four days a week, so a devotee serving twice a day still
      -- lands eight acts in a week and never reaches the weekly cap.
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
        (select ids.id from public.seva_fv_ids ids where ids.key = v_plan.who),
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
      ('donor', 250000),
      ('both',   90000),
      ('g1',     60000),
      ('g2',     45000),
      ('g3',     30000),
      ('g4',     20000),
      ('mixed',  15000),
      ('g5',     10000),
      ('g6',      5000),
      ('g7',      2500)
    ) as gift(who, cents)
  loop
    insert into public.donations (
      donor_id, donor_name, amount_cents, kind, external_payment_id, received_at
    ) values (
      (select ids.id from public.seva_fv_ids ids where ids.key = v_gift.who),
      v_gift.who, v_gift.cents, 'one_time', 'fv-' || v_gift.who || '-1',
      ((v_anchor - 2) + time '10:00') at time zone 'America/Chicago'
    );
  end loop;
end;
$$;

select public.recompute_seva_mala() as periods_computed;

-- ---------------------------------------------------------------------------
-- 5. The units, the references, and every score re-derived.
--
--    Checked before anything is concluded from them, so a moved median fails
--    here and says so rather than surfacing as a mysteriously wrong score forty
--    assertions later.
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
  if round(v_period.seva_reference, 6) <> 1.822590 then
    raise exception 'ref_s is % rather than 1.822590 = ln(6) + 0.2*(ln(7) - ln(6)).',
      round(v_period.seva_reference, 6);
  end if;
  if round(v_period.giving_reference, 6) <> 1.284232 then
    raise exception 'ref_g is % rather than 1.284232 = ln(3.4) + 0.2*(ln(4.6) - ln(3.4)).',
      round(v_period.giving_reference, 6);
  end if;
  if v_period.participant_count <> 18 then
    raise exception 'The lifetime cohort is % rather than 18.', v_period.participant_count;
  end if;
  if v_period.participant_count
     < public.seva_mala_number('seva_mala.minimum_cohort', 8) then
    raise exception 'The fixture is below the minimum cohort, so no reference means anything.';
  end if;

  -- The reference is a percentile of the congregation, not its maximum. If it
  -- were the maximum it would be sevak's ln(17) = 2.833213.
  if round(v_period.seva_reference, 4) = 2.8332 then
    raise exception 'ref_s is the maximum utility rather than a percentile of the congregation.';
  end if;

  -- One service type, so the measured scarcity weight is exactly 1.0 and the
  -- seva arithmetic above is unweighted.
  select count(*) into v_weights
  from public.seva_type_weights where weight <> 1.0;
  if v_weights <> 0 then
    raise exception '% service types carry a scarcity weight other than 1.0.', v_weights;
  end if;

  -- And nobody's day or week was clipped, so credited minutes are served
  -- minutes and every u_s above is the number it claims to be.
  select count(*) into v_capped
  from public.seva_mala_acts() acts
  where acts.day_factor <> 1.0 or acts.week_factor <> 1.0;
  if v_capped <> 0 then
    raise exception '% acts in the fixture were clipped by a cap.', v_capped;
  end if;
end;
$$;

-- Every stored score re-derived from the stored inputs, for all eighteen at
-- once. The published formula is typed out here rather than borrowed from
-- seva_mala_score, so this survives a refactor of the function body and fails
-- if the two terms are ever swapped back.
do $$
declare
  v_bad text;
  v_rows integer;
begin
  select string_agg(
           users.name || ': stored ' || checked.stored || ', re-derived ' || checked.derived,
           '; '),
         count(*)
  into v_bad, v_rows
  from (
    select
      scores.devotee_id,
      scores.score as stored,
      round(
        (
          greatest(scores.seva_norm, scores.giving_norm)
          + 0.5 * least(scores.seva_norm, scores.giving_norm)
        ) / 1.5, 6
      ) as derived
    from public.period_scores scores
    join public.seva_mala_periods periods on periods.id = scores.period_id
    where periods.period_kind = 'lifetime'
  ) checked
  join public.users on users.id = checked.devotee_id
  where abs(checked.stored - checked.derived) > 0.0000005;

  if v_rows > 0 then
    raise exception 'The stored score does not follow the published formula for %.', v_bad;
  end if;
end;
$$;

-- And the normalised offerings themselves re-derived from the period's own
-- units and references, so "s = 1" below is a fact about the congregation
-- rather than a number this file asserted into existence.
do $$
declare
  v_bad text;
begin
  select string_agg(users.name || ': ' || checked.stored_s || ' / ' || checked.derived_s
                    || ' and ' || checked.stored_g || ' / ' || checked.derived_g, '; ')
  into v_bad
  from (
    select
      scores.devotee_id,
      scores.seva_norm as stored_s,
      scores.giving_norm as stored_g,
      -- 202608040062 made the cap soft: a plain ratio up to the congregation's
      -- reference, 1 + alpha*ln(u/ref) past it, railed at 1 + beta. Typed out
      -- here rather than borrowed from seva_mala_normalise, so this stays an
      -- independent re-derivation.
      round(case
        when ln(1 + scores.seva_minutes / periods.seva_unit_minutes)
             <= periods.seva_reference
        then ln(1 + scores.seva_minutes / periods.seva_unit_minutes)
             / periods.seva_reference
        else least(1.5, 1 + 0.15 * ln(
               ln(1 + scores.seva_minutes / periods.seva_unit_minutes)
               / periods.seva_reference))
      end, 6) as derived_s,
      round(case
        when ln(1 + scores.giving_cents::numeric / periods.giving_unit_cents)
             <= periods.giving_reference
        then ln(1 + scores.giving_cents::numeric / periods.giving_unit_cents)
             / periods.giving_reference
        else least(1.5, 1 + 0.15 * ln(
               ln(1 + scores.giving_cents::numeric / periods.giving_unit_cents)
               / periods.giving_reference))
      end, 6) as derived_g
    from public.period_scores scores
    join public.seva_mala_periods periods on periods.id = scores.period_id
    where periods.period_kind = 'lifetime'
  ) checked
  join public.users on users.id = checked.devotee_id
  where abs(checked.stored_s - checked.derived_s) > 0.0000005
     or abs(checked.stored_g - checked.derived_g) > 0.0000005;

  if v_bad is not null then
    raise exception 'The normalised offerings are not log-compressed and scaled as published: %.', v_bad;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. The four archetypes, with their real numbers.
--
--    Forty-eight hours and nothing given, against $2,500 and no time to serve:
--    EQUAL, to the sixth decimal place, and sharing a dense rank of 2 behind
--    the one devotee who does both. Six hours and $150 — moderate at both —
--    comes eighth, behind both of them, which is the correction 0059 made.
-- ---------------------------------------------------------------------------

do $$
declare
  v_row record;
  v_sevak numeric;
  v_donor numeric;
  v_both numeric;
  v_mixed numeric;
  v_rank integer;
begin
  for v_row in
    select * from (values
      -- who,     s,         g,         score
      -- 202608040062 made the cap soft. sevak, donor and both are all past
      -- their reference and all three moved; mixed is below both references and
      -- did not move by a digit, which is the property most of the congregation
      -- cares about.
      ('sevak', 1.066173, 0.000000, 0.710782),
      ('donor', 0.000000, 1.093665, 0.729110),
      ('both',  1.009821, 1.025879, 1.020526),
      ('mixed', 0.602775, 0.365980, 0.523843)
    ) as expected(who, seva_norm, giving_norm, score)
  loop
    select scores.seva_norm, scores.giving_norm, scores.score
    into v_sevak, v_donor, v_both
    from public.period_scores scores
    join public.seva_mala_periods periods on periods.id = scores.period_id
    join public.seva_fv_ids ids on ids.id = scores.devotee_id
    where periods.period_kind = 'lifetime' and ids.key = v_row.who;

    if v_sevak <> v_row.seva_norm then
      raise exception '% has s = % rather than %.', v_row.who, v_sevak, v_row.seva_norm;
    end if;
    if v_donor <> v_row.giving_norm then
      raise exception '% has g = % rather than %.', v_row.who, v_donor, v_row.giving_norm;
    end if;
    if v_both <> v_row.score then
      raise exception '% scores % rather than %.', v_row.who, v_both, v_row.score;
    end if;
  end loop;

  select scores.score into v_sevak
  from public.period_scores scores
  join public.seva_mala_periods periods on periods.id = scores.period_id
  join public.seva_fv_ids ids on ids.id = scores.devotee_id
  where periods.period_kind = 'lifetime' and ids.key = 'sevak';

  select scores.score into v_donor
  from public.period_scores scores
  join public.seva_mala_periods periods on periods.id = scores.period_id
  join public.seva_fv_ids ids on ids.id = scores.devotee_id
  where periods.period_kind = 'lifetime' and ids.key = 'donor';

  select scores.score into v_both
  from public.period_scores scores
  join public.seva_mala_periods periods on periods.id = scores.period_id
  join public.seva_fv_ids ids on ids.id = scores.devotee_id
  where periods.period_kind = 'lifetime' and ids.key = 'both';

  select scores.score into v_mixed
  from public.period_scores scores
  join public.seva_mala_periods periods on periods.id = scores.period_id
  join public.seva_fv_ids ids on ids.id = scores.devotee_id
  where periods.period_kind = 'lifetime' and ids.key = 'mixed';

  -- Under 0055's hard cap these two were EQUAL because both had been held at
  -- 1.0. 202608040062 removed that flattening, and they are equal only if they
  -- stand at the same multiple of their own reference — which these two do not:
  -- forty-eight hours is 1.554 times the seva reference and $2,500 is 1.867
  -- times the giving reference. Equality AT EQUAL STANDING, which is what the
  -- temple asked for, is proved at two standings in fair_scaling.sql. What must
  -- still be true here is that neither path is penalised for being the path it
  -- is: both are two thirds of the way up and both are within a few points of
  -- each other despite one being hours and the other dollars.
  if abs(v_sevak - v_donor) > 0.05 then
    raise exception
      'Forty-eight hours scores % and $2,500 scores %; one path is being penalised for being that path.',
      v_sevak, v_donor;
  end if;
  if v_sevak <= 0.666667 or v_donor <= 0.666667 then
    raise exception
      'One offering alone is still held at the old cap: % and %.', v_sevak, v_donor;
  end if;
  if v_both <= v_sevak then
    raise exception 'Doing both (%) does not beat doing one (%).', v_both, v_sevak;
  end if;
  if v_mixed >= v_sevak then
    raise exception
      'Six hours and $150 scores % — ahead of forty-eight hours at %. The old rule is back.',
      v_mixed, v_sevak;
  end if;
  if v_mixed >= v_donor then
    raise exception
      'Six hours and $150 scores % — ahead of $2,500 at %. The old rule is back.',
      v_mixed, v_donor;
  end if;

  -- Near the top, and provably: exactly one devotee in a congregation of
  -- eighteen scores above either of them, and they share their rank.
  select count(*) into v_rank
  from public.period_scores scores
  join public.seva_mala_periods periods on periods.id = scores.period_id
  where periods.period_kind = 'lifetime' and scores.score > v_sevak;
  if v_rank > 2 then
    raise exception
      '% devotees out of eighteen outscore the pure sevak. Excelling at one thing is not near the top.',
      v_rank;
  end if;

  -- And the only devotees above them are the one who did both and the one who
  -- stands further above their own reference. Under 0055's cap the pure donor
  -- was tied with the sevak; under 202608040062 they are ahead of them, and by
  -- the width of their standing rather than the width of their cheque.
  if exists (
    select 1
    from public.period_scores scores
    join public.seva_mala_periods periods on periods.id = scores.period_id
    left join public.seva_fv_ids ids on ids.id = scores.devotee_id
    where periods.period_kind = 'lifetime'
      and scores.score > v_sevak
      and coalesce(ids.key, '?') not in ('both', 'donor')
  ) then
    raise exception
      'Somebody other than the devotee who did both, and the devotee standing further above their own reference, is ahead of the pure sevak.';
  end if;

  -- They no longer share a rank, because the soft cap has told them apart by
  -- where each stands against their own reference. They are still adjacent, and
  -- still with exactly one devotee above them.
  select count(distinct ranked.standing) into v_rank
  from (
    select scores.devotee_id, dense_rank() over (order by scores.score desc) as standing
    from public.period_scores scores
    join public.seva_mala_periods periods on periods.id = scores.period_id
    where periods.period_kind = 'lifetime'
  ) ranked
  join public.seva_fv_ids ids on ids.id = ranked.devotee_id
  where ids.key in ('sevak', 'donor');
  if v_rank <> 2 then
    raise exception
      'The pure sevak and the pure donor share a rank although they stand at different multiples of their references.';
  end if;
  select max(ranked.standing) - min(ranked.standing) into v_rank
  from (
    select scores.devotee_id, dense_rank() over (order by scores.score desc) as standing
    from public.period_scores scores
    join public.seva_mala_periods periods on periods.id = scores.period_id
    where periods.period_kind = 'lifetime'
  ) ranked
  join public.seva_fv_ids ids on ids.id = ranked.devotee_id
  where ids.key in ('sevak', 'donor');
  if v_rank <> 1 then
    raise exception
      'The pure sevak and the pure donor are % places apart rather than adjacent.', v_rank;
  end if;

  -- Under 0055's rule mixed scored (0.365980 + 0.5*0.602775)/1.5 = 0.444912 and
  -- beat both of them at 0.333333. The whole of the temple's complaint, and the
  -- whole of the correction, is that this comparison now runs the other way.
  if round((0.365980 + 0.5 * 0.602775) / 1.5, 6) <= round((0.000000 + 0.5 * 1.000000) / 1.5, 6)
  then
    raise exception 'The old rule did not favour the moderate devotee, so this fixture proves nothing.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. The cap, which is what makes the two of them equal rather than close.
--
--    donor is already held at g = 1 by least(1, ...). A second gift four times
--    the size of the first must therefore be worth exactly nothing — to donor,
--    and to everybody else, because v_g is a median of medians and ref_g is a
--    percentile that does not reach the top of the distribution.
-- ---------------------------------------------------------------------------

insert into public.seva_fv_snapshots (label, devotee_id, seva_norm, giving_norm, giving_cents, score)
select 'before-second-gift', scores.devotee_id, scores.seva_norm, scores.giving_norm,
       scores.giving_cents, scores.score
from public.period_scores scores
join public.seva_mala_periods periods on periods.id = scores.period_id
where periods.period_kind = 'lifetime';

insert into public.donations (
  donor_id, donor_name, amount_cents, kind, external_payment_id, received_at
)
select ids.id, 'donor', 1000000, 'one_time', 'fv-donor-2',
       ((public.seva_mala_week_start(public.seva_mala_today()) - 3) + time '10:00')
         at time zone 'America/Chicago'
from public.seva_fv_ids ids where ids.key = 'donor';

select public.recompute_seva_mala() as periods_recomputed;

do $$
declare
  v_moved text;
  v_cents bigint;
  v_score numeric;
  v_before_second numeric;
begin
  select scores.giving_cents, scores.score into v_cents, v_score
  from public.period_scores scores
  join public.seva_mala_periods periods on periods.id = scores.period_id
  join public.seva_fv_ids ids on ids.id = scores.devotee_id
  where periods.period_kind = 'lifetime' and ids.key = 'donor';

  -- The gift landed. Otherwise "nothing changed" would be trivially true.
  if v_cents <> 1250000 then
    raise exception 'The second gift did not reach the ledger: % cents.', v_cents;
  end if;
  -- 202608040062 made the cap soft, so a gift four times the size of the first
  -- is no longer worth literally nothing — that flattening is the thing the
  -- temple asked to have removed. What must still be true is that FIVE TIMES
  -- the money is worth a few percent, and that it does not carry the donor past
  -- the devotee who gave both their hands and their means.
  select before.score into v_before_second
  from public.seva_fv_snapshots before
  join public.seva_fv_ids ids on ids.id = before.devotee_id
  where before.label = 'before-second-gift' and ids.key = 'donor';

  if v_score <= v_before_second then
    raise exception
      'A $10,000 gift left the pure donor at % after %; giving more counts for nothing again.',
      v_score, v_before_second;
  end if;
  if v_score / v_before_second > 1.10 then
    raise exception
      'Five times the money moved the pure donor from % to %, which is not diminishing returns.',
      v_before_second, v_score;
  end if;
  if v_score >= (
    select scores.score from public.period_scores scores
    join public.seva_mala_periods periods on periods.id = scores.period_id
    join public.seva_fv_ids ids on ids.id = scores.devotee_id
    where periods.period_kind = 'lifetime' and ids.key = 'both'
  ) then
    raise exception '$12,500 and no seva has passed the devotee who did both.';
  end if;

  -- And it moved NOBODY ELSE. v_g is a median of medians and ref_g is a
  -- percentile that does not reach the top of the distribution, so one donor
  -- giving five times more cannot re-scale the congregation.
  select string_agg(users.name || ': ' || before.score || ' -> ' || scores.score, '; ')
  into v_moved
  from public.seva_fv_snapshots before
  join public.period_scores scores on scores.devotee_id = before.devotee_id
  join public.seva_mala_periods periods on periods.id = scores.period_id
  join public.users on users.id = before.devotee_id
  join public.seva_fv_ids ids on ids.id = before.devotee_id
  where before.label = 'before-second-gift'
    and periods.period_kind = 'lifetime'
    and ids.key <> 'donor'
    and scores.score is distinct from before.score;

  if v_moved is not null then
    raise exception 'A second enormous gift moved somebody else: %.', v_moved;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. The references are the congregation's, not a developer's.
--
--    "It depends on the devotees, not hardcoded." A devotee arrives having
--    served seventy-two hours — half again as much as the fixture's best — and
--    the eightieth percentile the whole congregation is scaled against must
--    move up to meet him. It moves from ln(6) + 0.2*(ln(7) - ln(6)) = 1.822590
--    to exactly ln(7) = 1.945910, because eleven servers put the eightieth
--    percentile on the ninth of them rather than between the eighth and ninth.
--
--    Under 0055's hard cap the devotees held at s = 1 stayed at s = 1 and only
--    the congregation below the reference felt it. 202608040062 removed that
--    ceiling on the evidence, so now EVERY devotee whose seva is scaled against
--    that reference is scaled down by it — the pure sevak included — while the
--    pure donor, whose dimension did not move, does not move at all. That is a
--    stronger statement of "relative to the congregation" than the cap could
--    make, and it is what is asserted below.
-- ---------------------------------------------------------------------------

insert into public.seva_fv_snapshots (label, devotee_id, seva_norm, giving_norm, giving_cents, score)
select 'before-whale', scores.devotee_id, scores.seva_norm, scores.giving_norm,
       scores.giving_cents, scores.score
from public.period_scores scores
join public.seva_mala_periods periods on periods.id = scores.period_id
where periods.period_kind = 'lifetime';

do $$
declare
  v_type uuid;
  v_anchor date := public.seva_mala_week_start(public.seva_mala_today()) - 1;
  v_instance uuid;
  v_day date;
  v_n integer;
begin
  select service_types.id into v_type
  from public.service_types where service_types.name = 'Pot Washing';

  for v_n in 1 .. 24 loop
    v_day := v_anchor - (7 * ((v_n - 1) / 8)) - (((v_n - 1) % 8) / 2);

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
      (select ids.id from public.seva_fv_ids ids where ids.key = 'whale'),
      'self_joined', 'completed', 'member_verified', 'served',
      (v_day + time '12:00') at time zone 'America/Chicago'
    );
  end loop;
end;
$$;

select public.recompute_seva_mala() as periods_recomputed;

do $$
declare
  v_period public.seva_mala_periods;
  v_before numeric;
  v_after numeric;
  v_who text;
  v_lowered integer;
begin
  select * into v_period from public.seva_mala_periods where period_kind = 'lifetime';

  if round(v_period.seva_reference, 6) <> 1.945910 then
    raise exception
      'A devotee serving seventy-two hours left the seva reference at % rather than moving it to ln(7) = 1.945910.',
      round(v_period.seva_reference, 6);
  end if;
  if round(v_period.giving_reference, 6) <> 1.284232 then
    raise exception 'Seva moved the GIVING reference to %.', round(v_period.giving_reference, 6);
  end if;
  if v_period.seva_unit_minutes <> 180 then
    raise exception 'The whale moved the unit act to % minutes.', v_period.seva_unit_minutes;
  end if;
  if v_period.participant_count <> 19 then
    raise exception 'The cohort is % rather than 19.', v_period.participant_count;
  end if;

  -- The devotee whose dimension did not move does not move. The pure donor gave
  -- nothing more and nobody gave more money, so their standing is untouched by a
  -- congregation that served more.
  select before.score into v_before
  from public.seva_fv_snapshots before
  join public.seva_fv_ids ids on ids.id = before.devotee_id
  where before.label = 'before-whale' and ids.key = 'donor';
  select scores.score into v_after
  from public.period_scores scores
  join public.seva_mala_periods periods on periods.id = scores.period_id
  join public.seva_fv_ids ids on ids.id = scores.devotee_id
  where periods.period_kind = 'lifetime' and ids.key = 'donor';
  if v_before <> v_after then
    raise exception
      'Somebody else''s seva moved the pure donor from % to %.', v_before, v_after;
  end if;

  -- And the devotees whose dimension DID move are scaled down by the new
  -- reference, above it as well as below it.
  foreach v_who in array array['sevak', 'both'] loop
    select before.score into v_before
    from public.seva_fv_snapshots before
    join public.seva_fv_ids ids on ids.id = before.devotee_id
    where before.label = 'before-whale' and ids.key = v_who;

    select scores.score into v_after
    from public.period_scores scores
    join public.seva_mala_periods periods on periods.id = scores.period_id
    join public.seva_fv_ids ids on ids.id = scores.devotee_id
    where periods.period_kind = 'lifetime' and ids.key = v_who;

    if v_after >= v_before then
      raise exception
        '% scored % after the congregation raised its bar, against % before. The score is not relative.',
        v_who, v_after, v_before;
    end if;
  end loop;

  -- And everybody who was below the reference is scaled down by the new one.
  select count(*) into v_lowered
  from public.seva_fv_snapshots before
  join public.period_scores scores on scores.devotee_id = before.devotee_id
  join public.seva_mala_periods periods on periods.id = scores.period_id
  where before.label = 'before-whale'
    and periods.period_kind = 'lifetime'
    and before.seva_norm < 1.0 and before.seva_norm > 0
    and scores.seva_norm >= before.seva_norm;
  if v_lowered > 0 then
    raise exception
      '% devotees below the reference kept their old normalised seva after the reference rose.',
      v_lowered;
  end if;

  -- Which is only meaningful if it actually reached the scores.
  select scores.score into v_after
  from public.period_scores scores
  join public.seva_mala_periods periods on periods.id = scores.period_id
  join public.seva_fv_ids ids on ids.id = scores.devotee_id
  where periods.period_kind = 'lifetime' and ids.key = 'mixed';
  select before.score into v_before
  from public.seva_fv_snapshots before
  join public.seva_fv_ids ids on ids.id = before.devotee_id
  where before.label = 'before-whale' and ids.key = 'mixed';
  if v_after >= v_before then
    raise exception
      'The moderate devotee scored % after the congregation raised its bar, against % before.',
      v_after, v_before;
  end if;
end;
$$;

-- The dial is refused by the recompute as well as by the score, so a temple
-- that sets beta to 2 gets an exception rather than a whole congregation
-- silently re-scored by the rule the temple rejected.
do $$
declare
  v_period uuid;
  v_caught boolean := false;
begin
  select id into v_period from public.seva_mala_periods where period_kind = 'lifetime';

  update public.app_settings set value = '2' where key = 'seva_mala.balance_beta';
  begin
    perform public.recompute_seva_mala_period(v_period);
  exception
    when others then
      if sqlstate <> 'P0001' then raise; end if;
      -- Only the recompute's own guard names the setting by its qualified key.
      -- If the rejection came from seva_mala_score instead, the period had
      -- already been half rebuilt before anybody objected.
      if position('seva_mala.balance_beta' in sqlerrm) = 0 then
        raise exception
          'A beta of 2 was refused by seva_mala_score rather than by the recompute: %', sqlerrm;
      end if;
      v_caught := true;
  end;

  if not v_caught then
    raise exception 'The recompute accepted a beta of 2 and re-scored the congregation.';
  end if;

  update public.app_settings set value = '0.5' where key = 'seva_mala.balance_beta';
  perform public.recompute_seva_mala_period(v_period);
end;
$$;

-- ---------------------------------------------------------------------------
-- 9. Weekly seva, through the real generator and the real RPCs.
--
--    Not a hand-written row with template_id set. Two real service_templates
--    rows, real standing assignees, public.generate_service_instances, and the
--    President pressing complete_service_instance — which is the ONE action the
--    temple has left to do, where 0057 needed three and two of the three had no
--    plausible actor at all.
--
--    Nobody verifies anything here and nobody marks anybody served. That is the
--    point.
--
--    ON WHICH DAY. 202608040070 moved the completion bar from a seva's start to
--    its END, so the two hours these templates run for have to be two hours
--    that are already over before the President may press anything. The
--    generator only ever writes today forward, and at 00:05 Chicago today does
--    not contain a finished two-hour seva at all: the fractions-of-the-elapsed-
--    day arithmetic that used to sit here only moved the failure from "before
--    dawn" to "before 02:40".
--
--    Shortening the seva would have carried into every minute figure in section
--    10, so the occurrences are moved instead. The generator places them on
--    today, as it does in the temple every night, and the fixture then moves
--    those same generated rows back one day — which is the state a President
--    actually finds them in: yesterday's occurrence, generated by the sweep,
--    still waiting for somebody to close it out. Fixed hours of 05:00 and 06:00
--    are then exactly as safe at 00:05 as at 17:00, and 120 minutes stays 120
--    minutes everywhere below.
-- ---------------------------------------------------------------------------

do $$
declare
  v_type uuid;
  v_today date := public.seva_mala_today();
  -- The day both occurrences are moved to. Yesterday is inside the 90-day
  -- window list_seva_awaiting_confirmation reads and inside every window
  -- seva_mala_acts reads, so section 10 and section 11 ask the same questions
  -- of it that they asked of today.
  v_yesterday date := public.seva_mala_today() - 1;
  v_pres uuid;
  v_template uuid;
  v_second_template uuid;
  v_who text;
  v_first time := time '05:00';
  v_second time := time '06:00';
begin
  select service_types.id into v_type
  from public.service_types where service_types.name = 'Pot Washing';
  select ids.id into v_pres from public.seva_fv_ids ids where ids.key = 'pres';

  -- The weekly seva four devotees are rostered on and the President closes out.
  -- Every day of the week is a serving day, so the generator places an
  -- occurrence whatever today is, and the template's own start_date reaches
  -- back to the day its occurrence is moved to.
  insert into public.service_templates (
    service_type_id, day_of_week, days_of_week, start_time, duration_minutes,
    slots_needed, participation_mode, start_date, created_by, active
  ) values (
    v_type, extract(dow from v_yesterday)::integer, array[0, 1, 2, 3, 4, 5, 6],
    v_first, 120, 4, 'open', v_yesterday, v_pres, true
  ) returning id into v_template;

  foreach v_who in array array['wkly', 'wabs', 'wnos', 'wwdr'] loop
    insert into public.service_template_assignees (
      service_template_id, devotee_id, assigned_by, status, days_of_week
    )
    select v_template, ids.id, v_pres, 'active', array[0, 1, 2, 3, 4, 5, 6]
    from public.seva_fv_ids ids where ids.key = v_who;
  end loop;

  -- The weekly seva nobody closed out, so the queue has something true to say.
  insert into public.service_templates (
    service_type_id, day_of_week, days_of_week, start_time, duration_minutes,
    slots_needed, participation_mode, start_date, created_by, active
  ) values (
    v_type, extract(dow from v_yesterday)::integer, array[0, 1, 2, 3, 4, 5, 6],
    v_second, 120, 1, 'open', v_yesterday, v_pres, true
  ) returning id into v_second_template;

  insert into public.service_template_assignees (
    service_template_id, devotee_id, assigned_by, status, days_of_week
  )
  select v_second_template, ids.id, v_pres, 'active', array[0, 1, 2, 3, 4, 5, 6]
  from public.seva_fv_ids ids where ids.key = 'wopen';

  perform public.generate_service_instances(1);

  -- Today's two occurrences, moved back a day. Tomorrow's are left exactly
  -- where the generator put them: a seva that has not happened yet is a real
  -- state and nothing here may quietly turn it into a past one.
  update public.service_instances instances
  set date = v_yesterday
  where instances.template_id in (v_template, v_second_template)
    and instances.date = v_today;

  if not exists (
    select 1 from public.service_instances instances
    where instances.template_id = v_template
      and instances.date = v_yesterday
  ) then
    raise exception 'The generator placed no occurrence on today to move back.';
  end if;
end;
$$;

-- The one-off, for the comparison that makes the exemption mean something.
do $$
declare
  v_type uuid;
  -- Yesterday, for the same reason as the weekly occurrences above and with
  -- one less step: nothing generates a one-off, so it is simply written on the
  -- day it happened. The President completes it and then verifies it below,
  -- and 202608040070's bar wants its two hours over while
  -- verify_seva_assignment wants it started — yesterday 07:00 to 09:00
  -- satisfies both at every hour, where 0.75 of the elapsed day satisfied the
  -- first only after 08:00 Chicago.
  v_yesterday date := public.seva_mala_today() - 1;
  v_pres uuid;
  v_instance uuid;
  v_assignment uuid;
  v_start time := time '07:00';
begin
  select service_types.id into v_type
  from public.service_types where service_types.name = 'Pot Washing';
  select ids.id into v_pres from public.seva_fv_ids ids where ids.key = 'pres';

  insert into public.service_instances (
    service_type_id, date, start_time, duration_minutes, slots_needed,
    participation_mode, posted_by, status
  ) values (v_type, v_yesterday, v_start, 120, 1, 'open', v_pres, 'open')
  returning id into v_instance;

  insert into public.service_assignments (
    service_instance_id, devotee_id, assignment_method, status, verification
  )
  select v_instance, ids.id, 'self_joined', 'confirmed', 'self_report'
  from public.seva_fv_ids ids where ids.key = 'once'
  returning id into v_assignment;

  insert into public.seva_fv_acts (key, assignment_id) values ('once', v_assignment);
end;
$$;

-- Every recurring assignment as generated: confirmed, self-reported, nobody
-- has marked anybody anything. Which is to say the state every recurring
-- assignment in the temple is in right now.
do $$
declare
  v_who text;
  v_assignment uuid;
  v_status text;
begin
  foreach v_who in array array['wkly', 'wabs', 'wnos', 'wwdr', 'wopen'] loop
    select assignments.id into v_assignment
    from public.service_assignments assignments
    join public.service_instances instances
      on instances.id = assignments.service_instance_id
    where assignments.devotee_id = (select ids.id from public.seva_fv_ids ids where ids.key = v_who)
      and instances.template_id is not null
      and instances.date = public.seva_mala_today() - 1;

    if v_assignment is null then
      raise exception 'The generator did not place % on yesterday''s weekly instance.', v_who;
    end if;

    insert into public.seva_fv_acts (key, assignment_id) values (v_who, v_assignment);

    select acts.points_status into v_status
    from public.seva_mala_acts() acts where acts.assignment_id = v_assignment;
    if v_status <> 'awaiting_completion' then
      raise exception
        'A freshly generated weekly assignment for % reads % rather than awaiting_completion.',
        v_who, v_status;
    end if;
  end loop;
end;
$$;

-- The President closes the first weekly seva out, and does nothing else at all.
set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.seva_fv_ids ids where ids.key = 'pres'), true);

do $$
declare
  v_instance uuid;
  v_opens_at timestamptz;
begin
  select assignments.service_instance_id into v_instance
  from public.service_assignments assignments
  join public.seva_fv_acts acts on acts.assignment_id = assignments.id
  where acts.key = 'wkly';

  -- Said before the button is pressed, because complete_service_instance
  -- refuses the clock and the roster with different sentences and this file
  -- must never be reading one as the other.
  select public.seva_completion_opens_at(
           instances.date, instances.start_time, instances.duration_minutes)
    into v_opens_at
  from public.service_instances instances where instances.id = v_instance;
  if v_opens_at > now() then
    raise exception
      'The weekly occurrence the President closes out is not over until %.', v_opens_at;
  end if;

  perform public.complete_service_instance(v_instance);

end;
$$;

reset role;

-- One word from a coordinator, and one devotee's act is zeroed.
--
-- Written directly rather than through record_seva_attendance, because
-- 202608310098 closed that door for weekly seva: a rota runs by itself and a
-- devotee who cannot make their day asks for coverage instead of being marked
-- away. The RULE is untouched — seva_points_status still zeroes an act whose
-- attendance reads 'absent', and rows written before that change still carry
-- one — so this keeps proving the rule while no longer pretending the app can
-- still make the mark. Outside the authenticated role, because a client has no
-- write on this table and is not meant to.
update public.service_assignments
set attendance = 'absent'
where id = (select acts.assignment_id from public.seva_fv_acts acts
            where acts.key = 'wabs');
select set_config('request.jwt.claim.sub', '', true);

-- The other two terminal states, which have no RPC of their own.
update public.service_assignments set status = 'no_show'
where id = (select acts.assignment_id from public.seva_fv_acts acts where acts.key = 'wnos');
update public.service_assignments set status = 'withdrawn'
where id = (select acts.assignment_id from public.seva_fv_acts acts where acts.key = 'wwdr');

-- ---------------------------------------------------------------------------
-- 10. Act by act: what a closed-out weekly seva earned, and what it did not.
-- ---------------------------------------------------------------------------

do $$
declare
  v_act record;
  v_case record;
begin
  for v_case in
    select * from (values
      -- who,   points_status,        recurring, quality, verification, attendance
      ('wkly',  'counted',            true,  1.0),
      ('wabs',  'not_served',         true,  0.0),
      ('wnos',  'not_served',         true,  0.0),
      ('wwdr',  'not_served',         true,  0.0),
      ('wopen', 'awaiting_completion',true,  0.0),
      ('once',  'awaiting_completion',false, 0.0)
    ) as expected(who, points_status, is_recurring, quality)
  loop
    select acts.* into v_act
    from public.seva_mala_acts() acts
    join public.seva_fv_acts fixture on fixture.assignment_id = acts.assignment_id
    where fixture.key = v_case.who;

    if v_act.assignment_id is null then
      raise exception '% has no act at all.', v_case.who;
    end if;
    if v_act.is_recurring <> v_case.is_recurring then
      raise exception '% reads is_recurring = % rather than %.',
        v_case.who, v_act.is_recurring, v_case.is_recurring;
    end if;
    if v_act.points_status <> v_case.points_status then
      raise exception '% reads % rather than %.',
        v_case.who, v_act.points_status, v_case.points_status;
    end if;
    if v_act.quality <> v_case.quality then
      raise exception '% carries a quality of % rather than %.',
        v_case.who, v_act.quality, v_case.quality;
    end if;

    -- Hours are kept whatever the status. "We are still confirming this" and
    -- "this never happened" are different sentences.
    if v_act.raw_minutes <> 120 then
      raise exception '% lost its minutes: %.', v_case.who, v_act.raw_minutes;
    end if;
    if v_case.quality = 0 and v_act.weighted_minutes <> 0 then
      raise exception '% earned % weighted minutes while reading %.',
        v_case.who, v_act.weighted_minutes, v_case.points_status;
    end if;
    if v_case.quality > 0 and v_act.weighted_minutes <> 120 then
      raise exception '% earned % weighted minutes rather than 120.',
        v_case.who, v_act.weighted_minutes;
    end if;
  end loop;

  -- And the state the counted weekly act is actually in: nobody verified it and
  -- nobody confirmed attendance, which is the whole of the change.
  select acts.* into v_act
  from public.seva_mala_acts() acts
  join public.seva_fv_acts fixture on fixture.assignment_id = acts.assignment_id
  where fixture.key = 'wkly';

  if v_act.verification <> 'self_report' then
    raise exception
      'The counted weekly act carries verification %, so this proves nothing about the exemption.',
      v_act.verification;
  end if;
  if v_act.attendance is not null then
    raise exception
      'The counted weekly act carries attendance %, so this proves nothing about the exemption.',
      v_act.attendance;
  end if;

  -- The same three facts on a ONE-OFF instance earn nothing. Same status, same
  -- verification, same silence — and 0057's rule still holds it back.
  if public.seva_points_status('completed', null, 'self_report', false) <> 'awaiting_verification'
  then
    raise exception 'The exemption reached one-off seva.';
  end if;
end;
$$;

-- The absent devotee is not merely unpaid, they are zeroed, and the difference
-- between silence and evidence is the difference between wkly and wabs.
do $$
declare
  v_wkly numeric;
  v_wabs numeric;
begin
  select sum(acts.weighted_minutes) into v_wkly
  from public.seva_mala_acts((select ids.id from public.seva_fv_ids ids where ids.key = 'wkly')) acts;
  select sum(acts.weighted_minutes) into v_wabs
  from public.seva_mala_acts((select ids.id from public.seva_fv_ids ids where ids.key = 'wabs')) acts;

  if v_wkly <> 120 then
    raise exception 'The closed-out weekly devotee earned % weighted minutes rather than 120.', v_wkly;
  end if;
  if v_wabs <> 0 then
    raise exception 'The devotee marked absent earned % weighted minutes.', v_wabs;
  end if;
end;
$$;

-- The one-off, taken the rest of the way, one requirement at a time. Each step
-- unblocks exactly one thing, and none of them may be skipped.
set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.seva_fv_ids ids where ids.key = 'pres'), true);

-- Each step is taken by the President, under the authenticated role, through
-- the RPC a President would actually press; each reading is taken back as the
-- temple, because seva_mala_acts is nobody's to run.
do $$
declare
  v_instance uuid;
  v_opens_at timestamptz;
begin
  select assignments.service_instance_id into v_instance
  from public.service_assignments assignments
  join public.seva_fv_acts acts on acts.assignment_id = assignments.id
  where acts.key = 'once';

  select public.seva_completion_opens_at(
           instances.date, instances.start_time, instances.duration_minutes)
    into v_opens_at
  from public.service_instances instances where instances.id = v_instance;
  if v_opens_at > now() then
    raise exception 'The one-off the President closes out is not over until %.', v_opens_at;
  end if;

  perform public.complete_service_instance(v_instance);
end;
$$;

reset role;

do $$
declare
  v_status text;
begin
  select acts.points_status into v_status
  from public.seva_mala_acts() acts
  join public.seva_fv_acts fixture on fixture.assignment_id = acts.assignment_id
  where fixture.key = 'once';
  if v_status <> 'awaiting_verification' then
    raise exception 'A completed one-off act reads % rather than awaiting_verification.', v_status;
  end if;
end;
$$;

set local role authenticated;

do $$
begin
  perform public.verify_seva_assignment(
    (select acts.assignment_id from public.seva_fv_acts acts where acts.key = 'once'));
end;
$$;

reset role;

do $$
declare
  v_status text;
begin
  select acts.points_status into v_status
  from public.seva_mala_acts() acts
  join public.seva_fv_acts fixture on fixture.assignment_id = acts.assignment_id
  where fixture.key = 'once';
  if v_status <> 'awaiting_confirmation' then
    raise exception 'A completed and verified one-off act reads % rather than awaiting_confirmation.',
      v_status;
  end if;
end;
$$;

set local role authenticated;

do $$
begin
  perform public.record_seva_attendance(
    (select acts.assignment_id from public.seva_fv_acts acts where acts.key = 'once'), 'served');
end;
$$;

reset role;

do $$
declare
  v_status text;
begin
  select acts.points_status into v_status
  from public.seva_mala_acts() acts
  join public.seva_fv_acts fixture on fixture.assignment_id = acts.assignment_id
  where fixture.key = 'once';
  if v_status <> 'counted' then
    raise exception 'A completed, verified and confirmed one-off act reads % rather than counted.',
      v_status;
  end if;
end;
$$;

set local role authenticated;

-- ---------------------------------------------------------------------------
-- 11. The queue, truthfully shortened.
--
--     A weekly act that has completed is no longer waiting on anybody and must
--     stop appearing on the President's screen. A weekly roster slot nobody has
--     closed out is still there, because that is the one action left.
-- ---------------------------------------------------------------------------

do $$
declare
  v_row record;
  v_case record;
begin
  for v_case in
    select * from (values
      ('wkly',  false, null),
      ('wabs',  false, null),
      ('wnos',  false, null),
      ('wwdr',  false, null),
      ('wopen', true,  'awaiting_completion'),
      ('once',  false, null)
    ) as expected(who, listed, points_status)
  loop
    select queue.* into v_row
    from public.list_seva_awaiting_confirmation() queue
    join public.seva_fv_acts fixture on fixture.assignment_id = queue.assignment_id
    where fixture.key = v_case.who;

    if v_case.listed and v_row.assignment_id is null then
      raise exception 'A weekly roster slot nobody closed out is missing from the queue (%).',
        v_case.who;
    end if;
    if not v_case.listed and v_row.assignment_id is not null then
      raise exception
        '% still reads as "%" on the President''s screen. A weekly act that has completed is waiting on nobody.',
        v_case.who, v_row.points_status;
    end if;
    if v_case.listed and v_row.points_status <> v_case.points_status then
      raise exception '% is queued as % rather than %.',
        v_case.who, v_row.points_status, v_case.points_status;
    end if;
    if v_case.listed and not v_row.is_recurring then
      raise exception 'The queued weekly slot does not read as recurring.';
    end if;
    if v_case.listed and v_row.posted_by is not null then
      raise exception 'A recurring instance acquired a poster.';
    end if;
  end loop;

  -- Nothing in the queue is a settled act. Every row is somebody's to clear.
  if exists (
    select 1 from public.list_seva_awaiting_confirmation() queue
    where queue.points_status in ('counted', 'not_served')
  ) then
    raise exception 'The queue contains acts that are already settled.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);

-- ---------------------------------------------------------------------------
-- 12. Nothing here opened a door.
--
--     Every refusal attempted as the devotee who would really attempt it.
-- ---------------------------------------------------------------------------

-- The lifetime period's id, handed over the fence so the devotee below can ask
-- about their own score without being able to read the table it lives in.
insert into public.seva_fv_ids (key, id)
select 'lifetime-period', periods.id
from public.seva_mala_periods periods where periods.period_kind = 'lifetime';

set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.seva_fv_ids ids where ids.key = 'sevak'), true);

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
    execute 'select count(*) from public.app_settings' into v_count;
    raise exception 'A signed-in devotee read the dials.';
  exception
    when insufficient_privilege then null;
    when others then
      if sqlstate = 'P0001' then raise; end if;
  end;

  begin
    execute 'select count(*) from public.seva_mala_acts()' into v_count;
    raise exception 'A signed-in devotee read the whole congregation''s acts.';
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

  begin
    execute format(
      'select public.recompute_seva_mala_period(%L)',
      (select id from public.seva_mala_periods limit 1)) into v_count;
    raise exception 'A signed-in devotee rebuilt a period.';
  exception
    when insufficient_privilege then null;
    when others then
      if sqlstate = 'P0001' then raise; end if;
  end;

  -- Their own score, through the only door there is, and the whole arithmetic
  -- behind it including the weight their smaller offering carried.
  select count(*) into v_count from public.my_seva_mala('lifetime');
  if v_count <> 1 then
    raise exception 'my_seva_mala returned % rows.', v_count;
  end if;

  -- The queue belongs to the poster and to app.view_all. A plain devotee sees
  -- nothing of the weekly roster, whatever 0059 shortened it to.
  select count(*) into v_count from public.list_seva_awaiting_confirmation();
  if v_count <> 0 then
    raise exception 'A plain devotee read % rows of the weekly queue.', v_count;
  end if;
end;
$$;

-- explain_my_score hands the devotee the same beta the board used, so they can
-- put their own two numbers back through seva_mala_score and get their score.
do $$
declare
  v_explained record;
  v_recomputed numeric;
begin
  select explained.* into v_explained
  from public.explain_my_score(
    (select ids.id from public.seva_fv_ids ids where ids.key = 'lifetime-period')
  ) explained;

  if v_explained.balance_beta <> 0.5 then
    raise exception 'The devotee is shown a beta of % rather than 0.5.', v_explained.balance_beta;
  end if;

  v_recomputed := public.seva_mala_score(
    v_explained.seva_norm, v_explained.giving_norm, v_explained.balance_beta);
  if v_recomputed <> v_explained.score then
    raise exception
      'A devotee checking their own working gets % where the board stored %.',
      v_recomputed, v_explained.score;
  end if;
  -- 202608040062 added the two dials that make the norm itself re-derivable,
  -- so the devotee can now check the whole chain and not only its last step.
  if v_explained.soft_cap_alpha <> 0.15
    or v_explained.norm_ceiling <> 1 + v_explained.balance_beta then
    raise exception 'The devotee is shown alpha % and a ceiling of %.',
      v_explained.soft_cap_alpha, v_explained.norm_ceiling;
  end if;
  if public.seva_mala_normalise(
       v_explained.seva_utility, v_explained.seva_reference,
       v_explained.soft_cap_alpha, v_explained.norm_ceiling)
     <> v_explained.seva_norm then
    raise exception
      'A devotee re-deriving their own normalised seva from what they were handed gets a different number.';
  end if;
  -- The pure sevak is past the congregation's reference and therefore above the
  -- old cap of two thirds, and still below the devotee who did both.
  if v_explained.seva_norm <= 1.0 or v_explained.score <= 0.666667 then
    raise exception
      'The pure sevak is shown s = % and a score of %.',
      v_explained.seva_norm, v_explained.score;
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);

do $$
begin
  raise notice 'all seva mala fairness checks passed';
end;
$$;

select 'seva mala fairness verification passed' as result;

rollback;
