-- The balance dial the temple chose, and the board a Community Head may read.
--
-- Two things, and they arrive together because they touch the same board. The
-- first is a number the temple picked after being shown what each setting does.
-- The second is a widening of who may look at the whole of that board, and most
-- of this header is about how far it goes and where it stops, because a
-- widening that is done quietly is done twice.
--
-- ---------------------------------------------------------------------------
-- 1. beta becomes 0.3.
--
--    0059 made beta the weight on the SMALLER of a devotee's two offerings:
--
--        score = ( max(s-hat, g-hat) + beta * min(s-hat, g-hat) ) / (1 + beta)
--
--    and left it at 0.5 with an argument for why 0.5 was a defensible place to
--    stand. It was never a claim that 0.5 was the temple's answer — 0055 §1 says
--    in as many words that these are the temple's numbers and a President moves
--    them with an UPDATE. The temple has now looked at the comparison and moved
--    this one.
--
--    WHAT 0.3 DOES, against the 0.5 the congregation has been scored at:
--
--        the devotee                     beta = 0.5    beta = 0.3
--        ----------------------------------------------------------
--        top sevak, gives nothing          0.666667      0.769231
--        top donor, no time to serve       0.666667      0.769231
--        top at both                       1.000000      1.000000
--        moderate at both (0.5, 0.5)       0.500000      0.500000
--        top seva and a little giving      0.766667      0.838462
--          (s-hat = 1.0, g-hat = 0.3)
--
--    Read down the first column: the second string counts less, so a devotee who
--    gives one thing wholly and the other not at all rises from two thirds of
--    the board to just over three quarters of it. Excelling at both still wins
--    outright and still cannot be bought past — 1.0 is 1.0 — but the premium for
--    the whole garland falls from 1.5x to 1.3x. That is the temple saying, with
--    a number, that a devotee who has only one thing to give is nearer the top
--    than 0.5 was placing them, without saying that the second string is worth
--    nothing at all, which is what 0 would have said.
--
--    NOTHING ELSE MOVES, and the things that do not move are the ones that make
--    the score the congregation's own: the log compression, the P80 references
--    shrunk toward the trailing quarter, the median-of-medians units, 0062's
--    soft cap and its alpha. What DOES move with beta, and moves on purpose, is
--    the ceiling — 0062 derives it as 1 + beta rather than typing 1.5 in,
--    precisely so that this migration does not have to remember to change it.
--    The per-dimension ceiling becomes 1.3 and the published ceiling becomes
--    1300 points, and both of them follow the dial without a line of code here.
--
-- ---------------------------------------------------------------------------
-- 2. Why this is an UPDATE, and why it is guarded on the old value.
--
--    0055 and 0059 seed the dial with ON CONFLICT DO NOTHING, which is right:
--    re-applying a migration must never stamp on a value the temple has since
--    changed. It also means a plain insert here would do nothing at all.
--
--    So this is an UPDATE, and it carries the same protection in the only form
--    an UPDATE can carry it — a WHERE on the value it is correcting:
--
--        where key = 'seva_mala.balance_beta' and value = '0.5'
--
--    which makes it a ONE-TIME CORRECTION rather than a standing instruction. It
--    fires once, on a database still holding the seeded 0.5. Run it again after
--    it has run and it matches nothing. Run it against a temple that has since
--    moved the dial to 0.4 and it matches nothing there either, and that is the
--    whole point: the dial is the temple's, this file is only carrying one
--    decision the temple has already made, and a migration that re-asserted 0.3
--    every time it was applied would be quietly taking the dial back.
--
-- ---------------------------------------------------------------------------
-- 3. Recomputing, without letting a migration decide that last week was empty.
--
--    A dial that nothing reads until 00:10 Chicago is a dial the temple changed
--    and cannot see. So the open boards are rebuilt here.
--
--    0059 §7 refused to do this and its reasoning is exactly right and is
--    respected rather than overruled. recompute_seva_mala() calls
--    ensure_seva_mala_period for today's week, month and lifetime AND for
--    yesterday's week and month. On a database being built from these migrations
--    that CREATES last week's and last month's periods with nothing in them, and
--    recompute_seva_mala_period then freezes any period whose last day is behind
--    us. A frozen period is never recomputed again. Two empty frozen periods,
--    made by a migration, and last week is empty for ever.
--
--    The rule this file follows instead, in one sentence:
--
--        RECOMPUTE THE PERIODS THAT ALREADY EXIST AND ARE NOT FROZEN. CREATE
--        NOTHING.
--
--    That is public.recompute_open_seva_mala_periods below. It is the loop out
--    of recompute_seva_mala with the five ensure_ calls taken off the front. On
--    a fresh database it finds no periods and does nothing, which is correct: a
--    board that does not exist does not need to reflect a dial. On the temple's
--    database it finds this week, this month and the lifetime, and they read
--    0.3 the moment this migration commits.
--
--    A period that already existed, is not frozen, and whose last day has passed
--    is recomputed and then frozen, exactly as the nightly job would have frozen
--    it tonight. That is not this file creating a closed period; it is this file
--    closing one the schedule was about to close anyway, and closing it under
--    the dial the temple has chosen rather than the one it has replaced.
--
--    It is a named function rather than a DO block for 0059 §2's reason: a rule
--    written inline can only be checked by re-typing it in a verification script
--    and hoping. This one is called by the migration and called again by the
--    verification, against a fixture holding one frozen period and one open one.
--
-- ---------------------------------------------------------------------------
-- 4. A Community Head sees the whole board.
--
--    "Community heads can also see the leaderboard including everyone whether
--     they have chosen to be on public or not, along with tech admin and
--     president."
--
--    The Community Head is services.manage_recurring — core, president and tech,
--    asserted in §0 rather than assumed. It is the key 0042 already means by
--    "the three who speak for us" and 0052 by "the three who may post a notice",
--    and inventing a seva.view_board beside it would give a fourth role that key
--    one day and silently leave this board narrow.
--
--    WHAT THEY GET. The ranking over EVERYBODY, opted-out devotees included and
--    flagged is_hidden, with the coarse published points beside each place and
--    each devotee's seva in minutes and acts.
--
--    WHAT THEY DO NOT GET, AND WHY IT IS MORE THAN JUST THE DOLLARS. Five
--    columns come back null for a Community Head — giving_cents, gifts,
--    giving_norm, seva_norm and score — and the last two are the ones worth
--    explaining, because a reviewer will read them as an over-reaction.
--
--      giving_cents, gifts   The dollars. 0048 §4 settled who may see the
--                            temple's giving and the answer was app.view_all;
--                            this file does not reopen it.
--
--      giving_norm           0060 §2: g-hat plus the period's v_g and ref_g
--                            inverts to a dollar figure exactly, and v_g and
--                            ref_g are not secret — explain_my_score hands them
--                            to every devotee who has a score in the period,
--                            because they are properties of the PERIOD. Publish
--                            g-hat and you have published the gift.
--
--      score AND seva_norm   Together these two ARE giving_norm. 0060 §3(b) did
--                            the algebra for the coarse case and refused to
--                            pretend otherwise; here it would be exact:
--
--                                g-hat <= s-hat:  g = ((1+b)*score - s)/b
--                                g-hat >  s-hat:  g = (1+b)*score - b*s
--
--                            and only one branch is self-consistent, so there is
--                            no ambiguity to hide behind. A Community Head
--                            holding the exact score and the exact s-hat of a
--                            devotee would hold that devotee's giving to the
--                            cent. Withholding giving_norm and handing back the
--                            two numbers it is recoverable from would be a
--                            privacy control that looks like one.
--
--    So the line is not "no dollars". It is:
--
--        A COMMUNITY HEAD SEES THE PUBLISHED BOARD OVER EVERYBODY. THEY SEE NO
--        RAW COMPONENT AND NO EXACT SCORE, BECAUSE ANY TWO OF THOSE GIVE BACK
--        THE THIRD AND THE THIRD GIVES BACK THE GIFT.
--
--    giving_withheld says which of the two boards the caller is holding, and it
--    exists so that a null in giving_cents can be told apart from a devotee who
--    gave nothing. A client that could not tell those apart would eventually
--    render a zero, and a zero is a claim.
--
--    WHY THE SEVA FIGURES ARE FINE AND THE GIVING FIGURES ARE NOT. This is the
--    whole judgement and it is 0058 §1's, restated in the direction it points
--    here rather than the direction it pointed there. 0058 refused a Community
--    Head the seva balance reports on the grounds that "a Community Head runs a
--    rota, which is a reason to know who is free, not a reason to be handed a
--    reading of another devotee's tiredness". The same sentence, read the other
--    way, is the argument FOR this change: running a rota is a reason to know
--    who is serving and how much. Minutes and acts are the rota, seen from
--    behind. Giving is not the rota and never becomes it.
--
--    THE COST, STATED RATHER THAN GLOSSED, in the manner 0060 §3(f) established.
--    This IS a reduction in privacy and it has two parts.
--
--      (a) A devotee who opted out of the garland is now visible, by name and
--          with a number, to every Community Head. 0055 §22 called
--          leaderboard_visible "display only" and 0060 §3(d) called it the one
--          switch a devotee has against being estimated. It still works against
--          the congregation. It no longer works against core. The temple asked
--          for exactly this, in those words, and is_hidden is on every row so a
--          Community Head can see that the devotee in front of them did not
--          choose to be there.
--
--      (b) Coarse points plus an ESTIMATE of s-hat is a coarse estimate of
--          giving. A Community Head does not have s-hat — they have credited
--          minutes, which differ from the weighted minutes the logarithm is
--          taken of by each act's quality and each seva type's scarcity weight
--          — so the inversion is loose rather than exact. On 0060's grid of ten
--          the combined score is known to +/-0.005, which propagates to +/-0.007
--          in g-hat for a giving-dominant devotee and +/-0.022 for a
--          seva-dominant one at beta = 0.3, and thence, through
--          dG ~ ref_g*(v_g + G)*dg-hat, to roughly 0.8% and 2.8% of (v_g + G).
--          That is the same order as the estimate 0060 already publishes to
--          EVERY devotee about every opted-in devotee. What is new here is not
--          the sharpness, it is the audience and the coverage: three roles
--          instead of the congregation, and everybody instead of the opted-in.
--
--    WHAT STAYS WITH app.view_all, deliberately and after being considered:
--
--      * every giving read — list_all_donations, donation_totals,
--        list_all_sponsorships, list_devotee_giving_points;
--      * SEVA CARE, which is 202608040058 — list_seva_concentration,
--        list_seva_narrowness, seva_balance_for_devotee. The temple asked for
--        that separately and 0058 §1 is why: it is a reading of a devotee's
--        tiredness, not a rota, and this file's widening must not reach it. 0058
--        §0 refuses to apply if core ever holds app.view_all, and §0 below
--        asserts the same thing from this side;
--      * list_devotee_seva_acts and list_devotee_seva_act_points, one devotee's
--        history act by act. A board is a board; a file on a devotee is not, and
--        the temple did not ask for one.
--
--    AND THE DEVOTEE'S OWN NUMBERS STAY THEIR OWN. my_seva_mala,
--    explain_my_score, my_seva_acts, my_giving_points and my_donation_totals are
--    untouched, take no devotee argument, and answer about auth.uid() and nobody
--    else. Nothing here gives a Community Head a way in to those.
--
-- Requires 202608040055 through 202608040063.

-- ---------------------------------------------------------------------------
-- 0. The ground this stands on.
--
--    Asserted rather than assumed. Everything §4 claims about what a Community
--    Head is and about what stays narrow is a claim about role grants that live
--    in another file, and a claim that stops being true silently is worse than
--    no claim at all.
-- ---------------------------------------------------------------------------

do $$
declare
  v_holders text;
  v_beta numeric;
begin
  if to_regprocedure('public.list_all_seva_scores(text)') is null
    or to_regprocedure('public.recompute_seva_mala_period(uuid)') is null
    or to_regprocedure('public.seva_mala_score(numeric, numeric, numeric)') is null
    or to_regprocedure('public.seva_mala_points(numeric)') is null
    or to_regprocedure('public.seva_mala_norm_ceiling()') is null
    or to_regprocedure('public.seva_mala_number(text, numeric)') is null
    or to_regprocedure('public.may_view_all_giving()') is null
    or to_regprocedure('public.is_backend_caller()') is null
  then
    raise exception
      'Seva Mala is not in place; apply 202608040055 through 202608040063 first.';
  end if;

  -- The rule beta is the dial of. Checked by value and with beta passed
  -- explicitly, so this says something about the FUNCTION rather than about the
  -- setting this migration is here to move.
  if public.seva_mala_score(1.0, 0.0, 0.5) <> 0.666667
    or public.seva_mala_score(0.0, 1.0, 0.5) <> 0.666667
    or public.seva_mala_score(1.0, 1.0, 0.5) <> 1.000000
  then
    raise exception
      'public.seva_mala_score is no longer 202608040059''s rule; 0.3 would mean something this file has not reasoned about.';
  end if;

  -- And the same rule at the value the temple has chosen, before it is set.
  if public.seva_mala_score(1.0, 0.0, 0.3) <> 0.769231
    or public.seva_mala_score(0.0, 1.0, 0.3) <> 0.769231
    or public.seva_mala_score(1.0, 1.0, 0.3) <> 1.000000
    or public.seva_mala_score(0.5, 0.5, 0.3) <> 0.500000
  then
    raise exception
      'public.seva_mala_score does not produce this file''s table at beta = 0.3.';
  end if;

  v_beta := public.seva_mala_number('seva_mala.balance_beta', 0.5);
  if v_beta is null or v_beta < 0 or v_beta > 1 then
    raise exception
      'seva_mala.balance_beta is %, which is outside [0, 1] and is not a weight on the smaller offering.',
      coalesce(v_beta::text, 'null');
  end if;

  -- app.view_all is still the two it has always been. Every column this file
  -- keeps narrow is kept narrow by that key.
  select string_agg(roles.name, ',' order by roles.name) into v_holders
  from public.role_permissions
  join public.roles on roles.id = role_permissions.role_id
  where role_permissions.permission_key = 'app.view_all';
  if v_holders is distinct from 'president,tech' then
    raise exception
      'app.view_all is held by % — this file widens a board on the assumption it is president, tech.',
      coalesce(v_holders, '(nobody)');
  end if;

  -- And the Community Head is the three the temple means. If a fourth role
  -- acquires services.manage_recurring, whoever grants it is deciding that the
  -- whole Seva Mala board goes with it, and should have to say so here.
  select string_agg(roles.name, ',' order by roles.name) into v_holders
  from public.role_permissions
  join public.roles on roles.id = role_permissions.role_id
  where role_permissions.permission_key = 'services.manage_recurring';
  if v_holders is distinct from 'core,president,tech' then
    raise exception
      'services.manage_recurring is held by % — the Community Head is core, president, tech.',
      coalesce(v_holders, '(nobody)');
  end if;

  -- 202608040058 §0's assertion, made from this side as well. The two keys are
  -- one word apart and this file leans on the distinction between them: a
  -- Community Head gets the board and does not get Seva Care.
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
      'The Community Head role holds app.view_all; the giving columns and Seva Care would open with the board.';
  end if;

  -- 0055 §4, in the part nothing here reverses. The tables stay unreadable; the
  -- only thing that moves is which permission one definer function answers.
  if has_table_privilege('authenticated', 'public.period_scores', 'select')
    or has_table_privilege('authenticated', 'public.seva_mala_periods', 'select')
    or has_table_privilege('authenticated', 'public.app_settings', 'select')
    or has_table_privilege('authenticated', 'public.donations', 'select')
  then
    raise exception 'authenticated can already read the Seva Mala components or the amounts.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 1. The dial, moved once.
--
--    Header §2 is why this is guarded on '0.5' rather than written
--    unconditionally. updated_at is set with it because the column exists to
--    record when a setting last moved and an UPDATE that leaves it stale is
--    writing down a wrong answer to a question somebody will ask.
-- ---------------------------------------------------------------------------

update public.app_settings
set value = '0.3',
    updated_at = now()
where app_settings.key = 'seva_mala.balance_beta'
  -- THE TEMPLE CHOSE 0.3, after being shown what 0, 0.3, 0.5 and 1 each do to a
  -- devotee who has only one thing to give. The weight on the SMALLER of a
  -- devotee's two offerings, beside a full weight on the larger:
  --
  --     score = (max + beta*min) / (1 + beta)
  --
  -- At 0.3 a devotee who gives one thing wholly reaches 0.769231 and a devotee
  -- who gives both wholly reaches 1.0 — a 1.3x premium for the whole garland
  -- where 0.5 made it 1.5x.
  --
  -- Matched on '0.5' so that this is a one-time correction and not a standing
  -- instruction: re-applying this migration will not stamp 0.3 back over a
  -- number the temple has moved since. The dial stays the temple's.
  and app_settings.value = '0.5';

do $$
declare
  v_beta numeric := public.seva_mala_number('seva_mala.balance_beta', 0.5);
begin
  if v_beta is null or v_beta < 0 or v_beta > 1 then
    raise exception
      'seva_mala.balance_beta is now %, which is outside [0, 1].',
      coalesce(v_beta::text, 'null');
  end if;
  if v_beta <> 0.3 then
    -- Not an error. The guard above did its job: somebody has already moved the
    -- dial off the seeded 0.5, and their number is not this file's to overrule.
    raise notice
      'seva_mala.balance_beta is % and was left alone; the temple has moved it since 0.5 was seeded.',
      v_beta;
  else
    raise notice 'seva_mala.balance_beta is 0.3; the ceiling is now %.',
      public.seva_mala_norm_ceiling();
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Recomputing what already exists.
--
--    202608040055 §17's loop with the five ensure_seva_mala_period calls taken
--    off the front, and nothing else changed. Header §3 is the whole argument
--    for why those five calls are the difference between a safe recompute and a
--    migration that decides last week was empty.
--
--    starts_on <= today is 0055's own predicate and is kept: a period that has
--    not begun has nothing in it and recompute_seva_mala_period would return
--    immediately anyway. Frozen periods are excluded by the WHERE rather than
--    left to the early return inside recompute_seva_mala_period, so that the
--    rule this function exists to state is visible in the function that states
--    it and can be mutated on its own.
--
--    Backend only, for 0055 §17's reason: a devotee who could call this could
--    not change their own score by doing so, but they could make the temple's
--    database do a hundred percentile scans on request.
-- ---------------------------------------------------------------------------

create or replace function public.recompute_open_seva_mala_periods()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_today date;
  v_period record;
  v_periods integer := 0;
begin
  if not public.is_backend_caller() then
    raise exception 'Seva Mala is recomputed by the temple''s own schedule, not on request.';
  end if;

  v_today := public.seva_mala_today();

  for v_period in
    select periods.id
    from public.seva_mala_periods periods
    where periods.frozen_at is null
      and periods.starts_on <= v_today
    order by periods.period_kind, periods.starts_on
  loop
    perform public.recompute_seva_mala_period(v_period.id);
    v_periods := v_periods + 1;
  end loop;

  return v_periods;
end;
$$;

comment on function public.recompute_open_seva_mala_periods() is
  'Rebuilds every Seva Mala period that already exists and is not frozen, and creates none. What to reach for after changing a dial, so the boards move now rather than at the next nightly run. Unlike recompute_seva_mala it never calls ensure_seva_mala_period, which would create last week and last month and then freeze them empty.';

revoke all on function public.recompute_open_seva_mala_periods()
  from public, anon, authenticated;
grant execute on function public.recompute_open_seva_mala_periods() to service_role;

-- The boards, at 0.3, now. And a check that this migration created nothing:
-- §3 of the header is a promise, and a promise in a comment is a wish.
do $$
declare
  v_before integer;
  v_after integer;
  v_periods integer;
begin
  select count(*) into v_before from public.seva_mala_periods;

  v_periods := public.recompute_open_seva_mala_periods();

  select count(*) into v_after from public.seva_mala_periods;
  if v_after <> v_before then
    raise exception
      'This migration created % Seva Mala period(s). 202608040059 §7 is why it must not.',
      v_after - v_before;
  end if;

  raise notice
    '% open Seva Mala period(s) recomputed; % period(s) exist and none were created.',
    v_periods, v_after;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Who may read the whole board.
--
--    A named predicate rather than a has_permission call written into the board,
--    for 202608040048 §4's reason: the question "who may see the whole Seva Mala
--    board" is asked in one place today and will be asked in two tomorrow, and
--    the two must not be able to disagree.
--
--    Both keys are named even though every app.view_all holder also holds
--    services.manage_recurring today. §0 asserts that they do; this function is
--    what keeps the President on the board on the day somebody appoints a
--    President who does not run rotas.
-- ---------------------------------------------------------------------------

create or replace function public.may_view_whole_seva_board()
returns boolean
language sql
stable
set search_path = ''
as $$
  select public.has_permission('services.manage_recurring')
      or public.has_permission('app.view_all')
$$;

comment on function public.may_view_whole_seva_board() is
  'True for a Community Head, Tech Admin or President — the three who may see the Seva Mala ranking over everybody, including the devotees who opted out of the public garland. Seeing the board is not seeing the giving behind it: that is may_view_all_giving.';

revoke all on function public.may_view_whole_seva_board() from public, anon;
grant execute on function public.may_view_whole_seva_board() to authenticated;

-- ---------------------------------------------------------------------------
-- 4. The whole board, on two terms.
--
--    Dropped and recreated rather than replaced: two columns are added and
--    `create or replace` cannot change a return shape. The argument list does
--    not move, so one DROP names both the old function and the new one and no
--    overload can be left behind — which matters, because 0060 §5 and 0061 §4
--    are what happens in this repository when one is: the two-argument call
--    every caller makes becomes ambiguous and Postgres refuses it outright.
--
--    ONE FUNCTION AND ONE RETURN SHAPE, not two functions. 0061 §8's rule: the
--    President's screen and the Community Head's screen are the same screen, and
--    a second function with a second row type is a second thing to keep in step.
--    What differs between the two callers is which columns carry a value, and
--    giving_withheld says which caller you are so a client never has to guess
--    whether a null means "not for you" or "none".
--
--    THE ORDER AND THE STANDING ARE COMPUTED FROM score FOR BOTH CALLERS. A
--    Community Head does not receive the score, but the board they receive is
--    ranked by it, which is what makes it the same board the President is
--    looking at rather than a second, differently ordered one. An ordering is a
--    much weaker thing to hold than the number it was made from: 0060 §4 makes
--    the same distinction the other way round when it orders the supporters list
--    by name.
--
--    The minimum cohort still does not apply, for 0055 §21's reason: it protects
--    a small congregation from being ranked in public, and none of these three
--    are the public.
-- ---------------------------------------------------------------------------

drop function if exists public.list_all_seva_scores(text);

create function public.list_all_seva_scores(p_period_kind text default 'week')
returns table (
  standing integer,
  devotee_id uuid,
  devotee_name text,
  points integer,
  score numeric,
  seva_minutes integer,
  seva_acts integer,
  giving_cents bigint,
  gifts integer,
  seva_norm numeric,
  giving_norm numeric,
  is_hidden boolean,
  giving_withheld boolean
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
  -- Both questions asked once, so no column can be gated by a different answer
  -- than the one beside it.
  caller as (
    select
      public.may_view_whole_seva_board() as sees_board,
      public.may_view_all_giving() as sees_giving
  )
  select
    dense_rank() over (order by scores.score desc)::integer,
    scores.devotee_id,
    users.name,
    -- The published figure, on 0060's grid of ten and under 0062's ceiling.
    -- This is the number on the garland, and it is what makes the Community
    -- Head's board the leaderboard rather than a list of names.
    public.seva_mala_points(scores.score),
    -- The exact score, the two components and the two giving figures. Header
    -- §4: score and seva_norm together give giving_norm back exactly, so the
    -- five of them travel together or not at all.
    case when caller.sees_giving then scores.score end,
    round(scores.credited_minutes)::integer,
    scores.seva_acts,
    case when caller.sees_giving then scores.giving_cents end,
    case when caller.sees_giving then scores.gifts end,
    case when caller.sees_giving then scores.seva_norm end,
    case when caller.sees_giving then scores.giving_norm end,
    not users.leaderboard_visible,
    not caller.sees_giving
  from public.period_scores scores
  join target on target.id = scores.period_id
  join public.users on users.id = scores.devotee_id
  cross join caller
  where auth.uid() is not null
    and caller.sees_board
  order by scores.score desc, users.name
$$;

comment on function public.list_all_seva_scores(text) is
  'Every devotee''s Seva Mala standing, including the devotees who opted out of the public garland, flagged is_hidden. For the President, the Tech Admin and the Community Head. All three see the ranking, the published points and the seva figures; only app.view_all sees the exact score, the two norms and the giving, because score and seva_norm together give giving_norm back exactly and giving_norm gives back the gift. giving_withheld says which of the two the caller is holding, so a null cannot be read as a zero.';

revoke all on function public.list_all_seva_scores(text) from public, anon;
grant execute on function public.list_all_seva_scores(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. What this migration deliberately does NOT do.
--
--    It does not touch list_seva_garland. An ordinary devotee still sees only
--    the devotees who opted in, still sees no component, and still cannot tell
--    from the board that anybody is missing from it — 0055 §20's dense ranking
--    over the opted-in set is what keeps an absence unreadable, and widening
--    that would take the opt-out away from the congregation rather than from
--    three named roles.
--
--    It does not touch Seva Care. Header §4 and 202608040058 §1.
--
--    It does not widen one devotee's history, act by act, to anybody.
--    list_devotee_seva_acts and list_devotee_seva_act_points are still
--    app.view_all's.
--
--    It grants nothing to anon, and it changes no table privilege and no row
--    level security policy. The only new door is a definer function that answers
--    a different permission than it used to.
-- ---------------------------------------------------------------------------

do $$
begin
  raise notice 'board access and beta applied';
end;
$$;
