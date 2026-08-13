-- A badge that is still true, a Seva Care list that reaches the devotees it is
-- for, and a board that ranks on the number it prints.
--
-- Four findings from two independent audits of 202608040055 through
-- 202608040066, every one of them reproduced against a copy of the temple's
-- own data. They are in one file because they are one complaint said four
-- ways: the app is publishing numbers that were true when they were computed
-- and are not true now, or that are true but answer a different question from
-- the one on the screen.
--
-- ---------------------------------------------------------------------------
-- 1. A BADGE THAT IS STILL BEING EARNED, MEASURED WHEN IT IS LOOKED AT.
--
--    0066 section 3 gave the display anchor the OPEN period, so that a badge
--    crossed on Thursday is worn on Thursday. That was right and it is kept.
--    What it did not carry with it is that a threshold on an open period MOVES.
--
--    public.devotee_awards is append-only and derived_threshold badges are
--    handed out live (0055 section 14). So the award row records a Tuesday, and
--    on Friday the congregation has shifted, the seventy-fifth percentile has
--    walked up past the devotee, and the row is still there saying they are
--    above it. On the copy of production this file was written against,
--    Madhava Priya Das wore Dhairya for a twelve-week run against a bar that
--    had risen to 12.15 weeks, and weekly recognition for a score of 0.3239
--    against a median of 0.3352. Re-running award_seva_mala_for_period added
--    nothing and removed nothing, because there is nothing there to remove: the
--    award was correctly given and is now incorrectly WORN.
--
--    NOTHING IS REVOKED AND THIS FILE ADDS NO WAY TO REVOKE ANYTHING. 0066
--    section 3's principle is that expiry is a join that stops matching, and
--    section 14 refuses to apply if this file learns to UPDATE or DELETE an
--    award. Both are kept, and section 6 below restates the refusal about this
--    file's own work. The fix is therefore entirely in the READ:
--
--      AN AWARD ON A PERIOD THAT IS STILL OPEN IS DISPLAYED ONLY WHILE THE
--      DEVOTEE STILL SATISFIES THE RULE THAT GAVE IT, RE-ASKED AT READ TIME
--      AGAINST THE SAME MEASURES AND THE SAME SCORES THE AWARDING USES.
--
--      AN AWARD ON A FROZEN PERIOD IS FINAL AND IS NEVER RE-JUDGED. The
--      temple's rule is that nothing is taken back once a period closes, and a
--      closed period's numbers cannot move anyway.
--
--    WHICH RULES ARE RE-ASKED, AND WHY THE OTHERS ARE NOT. Only two rule kinds
--    are ever handed out on an open period, and they are the two this file
--    re-asks:
--
--      derived_threshold  the bar is a quantile of the congregation, so it
--                         moves under the devotee. This is the whole finding.
--      personal           personal_best compares the devotee's period score
--                         against their own earlier ones, and a period score is
--                         congregation-relative, so it too can fall back below
--                         a past self while the period is open.
--
--    top_n and draw are refused on an open period by
--    award_seva_mala_for_period itself — 0066 section 8, "handing a badge out
--    on a Wednesday puts it on the wrong devotee for ever" — and discretionary
--    is a person's decision and not a measurement. None of those three is
--    re-asked, because re-asking a rule that was never a measurement would be
--    this file inventing a revocation rather than keeping a display honest.
--
--    THE COST, SAID OUT LOUD, BECAUSE THIS IS READ ON EVERY PROFILE. The
--    re-ask is inside a CASE whose first arm is `frozen_at is not null`, and
--    CASE is the one construct SQL guarantees short-circuits. A devotee's
--    badges are overwhelmingly on frozen periods, and not one of those costs
--    anything at all. What is left is the open period of each kind, which is at
--    most two rows and in practice fewer, and each of those is one pass over
--    one measure — the same single call award_seva_mala_for_period makes, with
--    the devotee's own value picked out of it by a FILTER rather than by a
--    second scan.
--
-- ---------------------------------------------------------------------------
-- 2. SEVA CARE WAS STILL ASKING THE CONGREGATION-WIDE QUESTION.
--
--    0066 section 4 said the comparison had to be against the devotee's OWN
--    SEVA — "a devotee giving six hours a week to a seva everybody else gives
--    ninety minutes to is the devotee the President was asking about" — and
--    then added that comparison as a THIRD gate beside 0058's two, both of
--    which are congregation-wide. The third gate turned out to exclude nobody
--    on real data, and 0058's `hours_per_week >= weekly_hours_threshold` went
--    on doing all the work, at 3.0 hours a week derived from a whole-devotee
--    median. It kept out, in the temple's own data:
--
--      Syamasundara Das      2.727 h/wk of Kitchen Preparation, 5.35x the
--                            median for that seva, 88% of his seva, ten
--                            straight weeks. He is 0066 section 4's own worked
--                            example, and he was missed by sixteen minutes a
--                            week.
--      Madhava Priya Das     the SOLE server of Flower Garlands, 100% of his
--                            seva, twelve straight weeks.
--      Gopala Krishna Das    thirteen straight weeks of Mangal Arati Setup,
--                            third-highest total load in the temple, missed by
--                            seven minutes a week.
--
--    while listing the President himself, whose seva happened to have two other
--    servers rather than three.
--
--    So the congregation-wide hours bar stops being a gate on the temple's own
--    list. What surfaces a row is now exactly two things, and BOTH of them
--    already travel on the row so a President can always ask "compared to
--    what?":
--
--      min_weeks_used        a run of weeks at least as long as the
--                            congregation's own upper tail. 0058's, untouched.
--      min_multiple_used     hours a week in THIS seva at least this multiple
--                            of the normal for THIS seva, read beside
--                            hours_vs_peers.
--
--    min_hours_used KEEPS ITS 0058 MEANING AND ITS 0058 VALUE. It is the
--    congregation-wide weekly figure the call was made with: the gate when a
--    caller names one, the denominator of `pronouncedness` either way, and the
--    thing `weekly_hours_vs_median` is expressed against. It is also pinned by
--    supabase/verification/seva_balance.sql, which is not this migration's file
--    to edit. Moving what that column reports to mean the per-seva bar would
--    have been a second, quieter change to a shipped screen's contract in a
--    migration about a gate.
--
--    A NAMED p_min_hours IS STILL THE CALLER'S QUESTION, unchanged: the
--    multiple stands down and the named bar is the whole gate. 0066 section 4's
--    reason stands — a derived gate that silently overrode an explicit one
--    would make the parameter a lie.
--
-- ---------------------------------------------------------------------------
-- 3. AND THE FALLBACK FOR "THE NORMAL FOR THIS SEVA" WAS THE STRICTEST BAR OF
--    ALL.
--
--    0066 compares a devotee's hours a week in one seva against the median
--    hours a week the OTHER servers of that seva give it, and where there are
--    fewer than frequency_min_peers others it falls back to
--    seva_balance_references().median_weekly_hours. Those are not the same
--    quantity. median_weekly_hours is a WHOLE DEVOTEE'S load across every seva
--    they do; the thing it stands in for is a SINGLE SEVA'S rate. It is
--    therefore at or above nearly every real per-seva normal, and in the
--    temple's data it sat above the true normal for twelve of fourteen seva
--    while nine of fourteen had too few servers to have a true normal at all.
--
--    The consequence is exactly backwards. The devotee with nobody beside them
--    — the sole server, the bus factor of one, the person the President most
--    needs to be sent to — faced the HARDEST bar in the function, because being
--    alone was treated as a reason to be judged against the busiest devotees in
--    the temple.
--
--    A fallback has to be in the same unit as the thing it replaces. So the
--    stand-in for "the median rate among the servers of this seva" is
--
--      THE MEDIAN, ACROSS THE TEMPLE'S SEVA, OF EXACTLY THAT SAME NUMBER.
--
--    What a normal seva's normal is. It is measured in hours a week in ONE
--    seva, it is computed from the same `rates` the true normal comes from, and
--    being a median of the normals it is above half of them and below half of
--    them — which is what a stand-in for an unknown normal should be, and is
--    the property that makes it a fallback rather than a wall. In the temple's
--    data it is 1.38 hours a week against the 2.00 it replaces.
--
--    Both quantiles are dials. seva_balance.frequency_normal_quantile is where
--    a seva's own normal is taken from its servers; frequency_fallback_quantile
--    is where the stand-in is taken from the seva. Both default to the middle,
--    and neither is written into a function body.
--
--    WHAT THIS COSTS IN LENGTH, WHICH IS THE COMPLAINT THAT STARTED SEVA CARE.
--    Nothing. On the temple's own data the list goes from two rows to five —
--    the two it already had, plus the three named above. The gate that replaced
--    the congregation-wide one is strictly a comparison, so a devotee doing a
--    normal amount of a demanding seva is still not on it however many hours
--    that is; that is the assertion supabase/verification/badges_and_reads.sql
--    already makes about Samadarshi and it is still true.
--
-- ---------------------------------------------------------------------------
-- 4. THE BOARD RANKS ON THE NUMBER IT PRINTS.
--
--    Points are published on a grid of ten (0060 section 3) and the ranking was
--    dense_rank over the raw score, which 0059 rounds to six places. So the
--    frozen week's podium showed 850 for the gold and 850 for the silver, and
--    the open week's board showed 340 at sixth place and 340 at seventh. Every
--    number on the screen was true and the screen was unreadable: it was
--    telling a devotee that something it was not showing them had decided who
--    came first.
--
--    Two honest fixes, and only one of them is available. PUBLISHING FINER is
--    refused. 0060 section 3(e) and 0062 section 4 both say what the step of
--    ten is: the width of the interval somebody can estimate a devotee's giving
--    to. Narrowing it to settle a tie would spend a privacy decision the temple
--    made on purpose, to buy a place that nobody can see the difference behind
--    anyway.
--
--    So THE BOARD RANKS ON THE PUBLISHED POINTS. Two devotees whose published
--    figure is the same share a place, which is what dense_rank has always been
--    for and what a reader of the board would assume the moment they saw two
--    equal numbers. The ranking stays dense and stays monotone — points never
--    fall as the basis rises, so no pair can be reordered by this, only tied —
--    and every place the app prints a standing beside points moves together, so
--    a devotee's own card cannot disagree with the garland they are looking at.
--
-- ---------------------------------------------------------------------------
-- 5. AND MY_SEVA_MALA STOPS PUBLISHING THE SIZE OF THE HIDDEN CONGREGATION.
--
--    public.my_seva_mala returns `standing`, dense-ranked over every devotee
--    who scored in the period, and `board_standing`, dense-ranked over the
--    devotees who opted in. The difference between them is the number of
--    devotees ABOVE the caller who chose not to be seen. That number is in
--    every devotee's payload whether or not the client renders it, and a
--    devotee who opted out can compute the same thing without either column, by
--    reading list_seva_garland and placing their own published points on it.
--
--    Showing a devotee their own rank privately is not the problem and is not
--    removed. The problem is the POPULATION it is taken over. So:
--
--      `standing` is the caller's place among the devotees they may see, plus
--      themselves.
--
--    For a devotee who opted in, that population is the board, so standing and
--    board_standing are the same number by construction and their difference is
--    identically zero — there is nothing left to subtract. For a devotee who
--    opted out, board_standing stays null, because they are not on the board;
--    `standing` is their honest place had they been, over a population they can
--    already see and a figure of their own they already know. Nobody loses a
--    rank and nobody gains a fact about somebody who is hiding.
--
--    cohort_size is untouched. It is the period's participant count, it is
--    already implied by `gathering`, and it says nothing about any individual.
--
-- ---------------------------------------------------------------------------
-- Requires 202608040066_badges_and_reads.sql.

-- ---------------------------------------------------------------------------
-- 0. The ground this stands on.
--
--    Every one of these is something an earlier migration decided and a later
--    one could take away.
-- ---------------------------------------------------------------------------

do $$
declare
  v_holders text;
begin
  if to_regprocedure('public.current_devotee_awards(uuid)') is null
    or to_regprocedure('public.seva_mala_period_measures(text, date, date, text)') is null
    or to_regprocedure('public.award_seva_mala_for_period(uuid)') is null
    or to_regprocedure('public.list_seva_concentration(integer, numeric)') is null
    or to_regprocedure('public.seva_balance_references()') is null
    or to_regprocedure('public.seva_balance_acts(uuid)') is null
    or to_regprocedure('public.seva_mala_points(numeric)') is null
    or to_regprocedure('public.list_seva_garland(text, integer, text)') is null
    or to_regprocedure('public.my_seva_mala(text)') is null
    or to_regprocedure('public.list_all_seva_scores(text)') is null
    or to_regprocedure('public.seva_yatra_devotee_summary(uuid, text)') is null
  then
    raise exception
      'Seva Mala is not fully in place; apply 202608040055 through 202608040066 first.';
  end if;

  -- Section 1 is only safe as a read-side rule while the row underneath it
  -- cannot be deleted. If the append-only trigger were gone, "the display
  -- stopped matching" and "the award was taken away" would be indistinguishable.
  if not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.devotee_awards'::regclass
      and tgname = 'devotee_awards_append_only'
      and not tgisinternal
  ) then
    raise exception
      'The append-only trigger on public.devotee_awards is gone. Nothing in this file may be applied until it is back.';
  end if;

  -- Section 1 re-asks exactly the rules 0066 section 8 hands out live. If a
  -- sixth rule kind ever appeared, this file would be silently failing to
  -- re-ask it.
  if exists (
    select 1 from public.award_definitions
    where rule_kind not in
      ('derived_threshold', 'top_n', 'personal', 'discretionary', 'draw')
  ) then
    raise exception
      'award_definitions holds a rule kind 202608040055 did not define; section 1 does not know whether to re-ask it.';
  end if;

  -- Section 2 and section 3 rewrite a President-only list. It is still the
  -- President's.
  select string_agg(roles.name, ',' order by roles.name) into v_holders
  from public.role_permissions
  join public.roles on roles.id = role_permissions.role_id
  where role_permissions.permission_key = 'app.view_all';
  if v_holders is distinct from 'president,tech' then
    raise exception
      'app.view_all is held by % — Seva Care assumes president, tech.', v_holders;
  end if;

  -- Section 4 and section 5 are both promises about what a devotee cannot work
  -- out. They are only promises while the tables themselves stay shut.
  if has_table_privilege('authenticated', 'public.period_scores', 'select')
    or has_table_privilege('authenticated', 'public.seva_mala_periods', 'select')
    or has_table_privilege('authenticated', 'public.app_settings', 'select')
  then
    raise exception 'authenticated can already read the Seva Mala components.';
  end if;

  -- Section 4's whole argument is that the published figure is coarser than the
  -- figure it is derived from. If points ever became the score itself there
  -- would be no ties to settle and nothing here to do.
  if public.seva_mala_points(0.3427) = public.seva_mala_points(0.3352)
     and public.seva_mala_points(0.3427) <> public.seva_mala_points(0.4)
  then
    null;
  else
    raise exception
      'seva_mala_points no longer publishes on a grid coarser than the score; section 4 is describing arithmetic that has changed.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 1. The dials this file adds.
--
--    Two, both about section 3's stand-in, both in public.app_settings with
--    everything else. on conflict do nothing: a temple that has already moved
--    one of these keeps its own value.
-- ---------------------------------------------------------------------------

insert into public.app_settings (key, value) values
  -- Where in a seva's own servers its normal is taken. The middle one, which
  -- is what 0066 section 4 means by "the median hours a week among the OTHER
  -- devotees who serve it" — said as a dial rather than as a 0.5 in a body.
  ('seva_balance.frequency_normal_quantile', '0.5'),
  -- And where the stand-in comes from, when a seva has too few servers to have
  -- a normal of its own: this quantile of the normals the temple's other seva
  -- DO have. The middle one, so the stand-in is above half of them and below
  -- half of them.
  ('seva_balance.frequency_fallback_quantile', '0.5')
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------
-- 2. Is this award still being earned?
--
--    Header section 1. One question, asked about one award, answered with the
--    same expressions public.award_seva_mala_for_period would use if it were
--    run this second — deliberately copied rather than shared, for 0063's and
--    0066's reason about restating a rule whole: a wrapper around a rule that
--    has to be evaluated in two directions is a second place for the rule to
--    live, and here the two directions are "who gets it" and "does this one
--    person still have it".
--
--    TRUE is the answer to everything this function does not judge — a frozen
--    period, a rule kind that is never handed out live, a definition that is no
--    longer there. Nothing is hidden because this function was unsure.
-- ---------------------------------------------------------------------------

create or replace function public.seva_mala_award_holds_now(
  p_award_definition_id uuid,
  p_period_id uuid,
  p_devotee_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_period public.seva_mala_periods;
  v_definition public.award_definitions;
  v_from date;
  v_to date;
  v_threshold numeric;
  v_value numeric;
begin
  if p_award_definition_id is null or p_period_id is null or p_devotee_id is null then
    return true;
  end if;

  select * into v_period from public.seva_mala_periods where id = p_period_id;

  -- A CLOSED PERIOD IS FINAL. The temple's rule is that nothing is taken back
  -- once a period ends, and a frozen period's numbers cannot move anyway.
  if v_period.id is null or v_period.frozen_at is not null then
    return true;
  end if;

  select * into v_definition
  from public.award_definitions where id = p_award_definition_id;
  if v_definition.id is null then
    return true;
  end if;

  -- The same two dates 0066 section 8 measures over: the period's, clipped at
  -- today for an open one, so nothing is asked about days that have not
  -- happened.
  v_from := v_period.starts_on;
  v_to := least(v_period.ends_on, public.seva_mala_today());
  if v_to < v_from then
    return false;
  end if;

  -- ---- A measured threshold. 0066 section 8's first branch. ---------------
  if v_definition.rule_kind = 'derived_threshold'
     and v_definition.rule_measure is not null
  then
    -- One pass over the measure, not two: the bar and this devotee's own value
    -- come out of the same scan, because the alternative is calling
    -- seva_mala_period_measures twice on a read that happens on every profile.
    select
      percentile_cont(coalesce(v_definition.threshold_quantile, 0.5))
        within group (order by measures.value)
        filter (where measures.value > 0),
      max(measures.value) filter (where measures.devotee_id = p_devotee_id)
    into v_threshold, v_value
    from public.seva_mala_period_measures(
           v_period.period_kind, v_from, v_to, v_definition.rule_measure) measures;

    v_threshold := greatest(
      coalesce(v_threshold, 0), coalesce(v_definition.threshold_floor, 0));

    return v_threshold > 0 and coalesce(v_value, 0) >= v_threshold;

  -- ---- 0055's threshold over the scoring's own norms. ---------------------
  elsif v_definition.rule_kind = 'derived_threshold' then
    select
      percentile_cont(v_definition.threshold_quantile)
        within group (order by scores.score)
        filter (where scores.score > 0),
      max(scores.score) filter (where scores.devotee_id = p_devotee_id)
    into v_threshold, v_value
    from public.period_scores scores
    where scores.period_id = v_period.id;

    return v_threshold is not null
      and coalesce(v_value, 0) > 0
      and v_value >= v_threshold;

  -- ---- Better than every earlier period of your own. ----------------------
  --      A period score is congregation-relative, so this can stop being true
  --      while the period is open without the devotee doing anything.
  elsif v_definition.rule_kind = 'personal'
    and v_definition.rule_key = 'personal_best'
  then
    return exists (
      select 1
      from public.period_scores scores
      where scores.period_id = v_period.id
        and scores.devotee_id = p_devotee_id
        and scores.score > 0
        and (
          select count(*) from public.period_scores earlier
          join public.seva_mala_periods periods on periods.id = earlier.period_id
          where earlier.devotee_id = scores.devotee_id
            and periods.period_kind = v_period.period_kind
            and periods.starts_on < v_period.starts_on
            and earlier.score > 0
        ) >= 1
        and not exists (
          select 1 from public.period_scores earlier
          join public.seva_mala_periods periods on periods.id = earlier.period_id
          where earlier.devotee_id = scores.devotee_id
            and periods.period_kind = v_period.period_kind
            and periods.starts_on < v_period.starts_on
            and earlier.score >= scores.score
        )
    );
  end if;

  -- top_n and draw are refused on an open period by the awarding itself;
  -- personal/first_seva is a fact about the past; discretionary is a person's
  -- decision. None of them is a measurement, so none of them is re-measured.
  return true;
end;
$$;

comment on function public.seva_mala_award_holds_now(uuid, uuid, uuid) is
  'Whether one devotee still satisfies the rule that gave them one award, asked against the same measures and scores the awarding uses. True for anything on a frozen period — a closed period is final and is never re-judged — and true for every rule that is not handed out live, because those were never measurements. This never writes; expiry in Seva Mala is a join that stops matching.';

revoke all on function public.seva_mala_award_holds_now(uuid, uuid, uuid)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. Which awards a devotee is wearing right now, re-asked.
--
--    0066 section 10's function with one clause added and nothing else moved.
--    Two anchors, the distinct-on that keeps a devotee from wearing two of the
--    same badge, the same order — and now, for an award on the OPEN anchor
--    only, the question of whether it is still true.
--
--    THE CASE IS LOAD-BEARING AND NOT DECORATION. `frozen_at is not null or
--    f(...)` does not promise not to evaluate f; CASE does. A devotee's badges
--    are almost all on frozen periods, and this is read every time anybody
--    opens a profile.
--
--    A badge dropped from the open period does not disappear if the devotee
--    also holds it on the latest closed one: the distinct-on simply falls
--    through to the frozen copy, which is 0066's rule that a badge is worn for
--    the period it was earned in until a period of its kind closes without
--    them.
-- ---------------------------------------------------------------------------

create or replace function public.current_devotee_awards(p_devotee_id uuid)
returns table (
  award_id uuid,
  award_definition_id uuid,
  period_id uuid,
  period_kind text,
  period_start date,
  period_end date,
  participant_count integer
)
language sql
stable
security definer
set search_path = ''
as $$
  with anchors as (
    -- The period of each kind that is happening now. A badge earned on
    -- Thursday is worn on Thursday.
    select periods.id as period_id
    from public.seva_mala_periods periods
    where periods.frozen_at is null
      and periods.period_kind <> 'lifetime'
      and public.seva_mala_today() between periods.starts_on and periods.ends_on

    union

    -- And the latest closed leaderboard of each kind, which is what carries a
    -- badge across the gap between one period ending and the next being earned.
    select current_periods.period_id
    from public.current_award_periods() current_periods
  )
  select distinct on (awards.award_definition_id)
    awards.id,
    awards.award_definition_id,
    awards.period_id,
    periods.period_kind,
    periods.starts_on,
    periods.ends_on,
    periods.participant_count
  from public.devotee_awards awards
  join public.seva_mala_periods periods on periods.id = awards.period_id
  join anchors on anchors.period_id = awards.period_id
  where p_devotee_id is not null
    and awards.devotee_id = p_devotee_id
    and case
          when periods.frozen_at is not null then true
          else public.seva_mala_award_holds_now(
                 awards.award_definition_id, awards.period_id, p_devotee_id)
        end
  order by awards.award_definition_id, periods.starts_on desc, awards.awarded_on desc
$$;

comment on function public.current_devotee_awards(uuid) is
  'The awards one devotee is wearing right now: their latest holding of each badge, among the period of each kind that is open and the latest closed leaderboard of each kind. A badge on the OPEN period is shown only while its rule is still satisfied, re-asked at read time; a badge on a closed period is final and is never re-judged. Nothing is deleted — this is a join that stops matching.';

revoke all on function public.current_devotee_awards(uuid)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4. Seva Care, reaching the devotees it exists to find.
--
--    Header sections 2 and 3. 0066 section 12's function restated whole, with
--    the argument list untouched — supabase/verification/seva_balance.sql and
--    supabase/verification/board_access_and_beta.sql both name
--    list_seva_concentration(integer, numeric) by signature and neither is this
--    migration's file — and the return shape untouched, because
--    src/screens/SevaCareScreen.tsx renders it.
--
--    What moved, and nothing else did:
--
--      seva_normals       one row per seva: the middle weekly rate among the
--                         devotees who serve it. The thing the fallback is now
--                         a median OF.
--      standing_in        the median of those normals. In the same unit as
--                         everything it stands in for, and above half of the
--                         temple's seva rather than above nearly all of them.
--      the hours gate     for the temple's own list, the per-seva multiple IS
--                         the hours gate. The congregation-wide figure remains
--                         the gate for a caller who names one, and remains
--                         min_hours_used and the denominator of pronouncedness
--                         either way.
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
  hours_this_week numeric,
  hours_this_month numeric,
  hours_trailing_quarter numeric,
  consecutive_weeks integer,
  share_of_their_seva numeric,
  weekly_hours_vs_median numeric,
  share_vs_congregation numeric,
  hours_vs_peers numeric,
  pronouncedness numeric,
  first_served_on date,
  last_served_on date,
  min_hours_used numeric,
  min_weeks_used integer,
  min_multiple_used numeric,
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
  v_multiple numeric;
  v_min_peers integer;
  v_normal_q numeric;
  v_fallback_q numeric;
  v_week_start date;
  v_month_start date;
  v_today date;
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

  -- THE PER-SEVA GATE BELONGS TO THE TEMPLE'S OWN LIST. A caller who names
  -- p_min_hours has said in the call what "more than normal" means to them, and
  -- a derived gate that silently overrode an explicit one would make the
  -- parameter a lie. Header section 2.
  v_multiple := case
    when p_min_hours is not null then 0
    else public.seva_mala_number('seva_balance.frequency_multiple', 2.0)
  end;
  v_min_peers := public.seva_mala_number('seva_balance.frequency_min_peers', 3)::integer;
  v_normal_q := public.seva_mala_number('seva_balance.frequency_normal_quantile', 0.5);
  v_fallback_q := public.seva_mala_number('seva_balance.frequency_fallback_quantile', 0.5);

  v_today := public.seva_mala_today();
  v_week_start := public.seva_mala_week_start(v_today);
  v_month_start := date_trunc('month', v_today)::date;

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
      windowed.service_type_id,
      min(windowed.seva_name) as seva_name,
      min(windowed.category) as category,
      sum(windowed.served_minutes) / 60.0 as type_hours
    from windowed group by 1, 2, 3
  ),
  -- The two figures the office reads out loud. Chicago's week and Chicago's
  -- month, not an average over a quarter — "eleven hours this week" is a
  -- sentence somebody can act on and "8.4 hours a week since May" is not.
  recent as (
    select
      acts.devotee_id,
      acts.seva_key,
      sum(acts.served_minutes) filter (where acts.occurred_on >= v_week_start) / 60.0
        as week_hours,
      sum(acts.served_minutes) filter (where acts.occurred_on >= v_month_start) / 60.0
        as month_hours
    from acts
    where acts.occurred_on <= v_today
    group by 1, 2
  ),
  -- Hours a week in ONE seva, per devotee per kind, over the same window. Every
  -- comparison below is between two numbers drawn from this one table, which is
  -- the whole of what header section 3 is about.
  rates as (
    select
      by_type.devotee_id,
      by_type.seva_key,
      by_type.type_hours / active.active_weeks as per_week
    from by_type
    join active on active.devotee_id = by_type.devotee_id
  ),
  -- What each seva normally takes. percentile_cont answers in double precision
  -- whatever it is given, so the cast is not decoration: without it every ratio
  -- below becomes a float and round(float, 2) does not exist.
  seva_normals as (
    select
      rates.seva_key,
      percentile_cont(v_normal_q) within group (order by rates.per_week)::numeric
        as normal_per_week
    from rates group by 1
  ),
  -- And what a normal seva's normal is: the stand-in when a seva has too few
  -- servers to have one of its own. Header section 3. A median of the normals,
  -- so it is above half the temple's seva and below half of them — a fallback
  -- and not a wall.
  standing_in as (
    select
      percentile_cont(v_fallback_q)
        within group (order by seva_normals.normal_per_week)::numeric as per_week
    from seva_normals
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
      by_type.seva_key,
      by_type.service_type_id,
      by_type.seva_name,
      by_type.category,
      by_type.type_hours / active.active_weeks as per_week,
      by_type.type_hours as quarter_hours,
      coalesce(recent.week_hours, 0) as week_hours,
      coalesce(recent.month_hours, 0) as month_hours,
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
    left join recent
      on recent.devotee_id = by_type.devotee_id
     and recent.seva_key = by_type.seva_key
    join dates
      on dates.devotee_id = by_type.devotee_id
     and dates.seva_key = by_type.seva_key
  ),
  -- Excluding the candidate, or a lone server would be their own normal and no
  -- ratio could ever exceed one. Too few others and there is no normal for this
  -- seva at all, so the median of the temple's other seva normals stands in —
  -- the same quantity, one level up, rather than a whole devotee's load.
  normals as (
    select
      candidates.devotee_id,
      candidates.seva_key,
      coalesce(
        case
          when (select count(*) from rates peers
                where peers.seva_key = candidates.seva_key
                  and peers.devotee_id <> candidates.devotee_id) >= v_min_peers
          then (select percentile_cont(v_normal_q)
                       within group (order by peers.per_week)::numeric
                from rates peers
                where peers.seva_key = candidates.seva_key
                  and peers.devotee_id <> candidates.devotee_id)
        end,
        (select standing_in.per_week from standing_in),
        v_min_hours
      ) as normal_per_week
    from candidates
  ),
  surfaced as (
    select
      candidates.*,
      candidates.per_week / v_min_hours as hours_ratio,
      candidates.weeks_run::numeric / v_min_weeks as weeks_ratio,
      candidates.share / nullif(v_refs.median_top_share, 0) as share_ratio,
      candidates.per_week / nullif(normals.normal_per_week, 0) as peer_ratio
    from candidates
    join normals
      on normals.devotee_id = candidates.devotee_id
     and normals.seva_key = candidates.seva_key
    where candidates.weeks_run >= v_min_weeks
      -- Genuinely higher than normal FOR THIS SEVA, which for the temple's own
      -- list is the whole of the hours question. A caller who named a figure of
      -- their own gets theirs instead, and the multiple stands down.
      and case
            when v_multiple <= 0 then candidates.per_week >= v_min_hours
            else candidates.per_week >= v_multiple * normals.normal_per_week
          end
      -- And nobody the President has already been to see.
      and not exists (
        select 1 from public.seva_care_dismissals dismissals
        where dismissals.devotee_id = candidates.devotee_id
          and dismissals.restored_at is null
          and dismissals.lapses_on >= v_today
          and (dismissals.service_type_id is null
               or dismissals.service_type_id = candidates.service_type_id)
      )
  )
  select
    surfaced.devotee_id,
    users.name,
    surfaced.service_type_id,
    surfaced.seva_name,
    surfaced.category,
    round(surfaced.per_week, 2),
    round(surfaced.week_hours, 2),
    round(surfaced.month_hours, 2),
    round(surfaced.quarter_hours, 2),
    surfaced.weeks_run,
    round(surfaced.share, 4),
    round(surfaced.per_week / nullif(v_refs.median_weekly_hours, 0), 2),
    round(coalesce(surfaced.share_ratio, 1), 2),
    round(coalesce(surfaced.peer_ratio, 1), 2),
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
    round(v_multiple, 2),
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
  'Devotees carrying genuinely more of one seva than is normal FOR THAT SEVA, for long enough to be a pattern, with the hours they have given it this week and this month. The comparison is against the other servers of that seva, and where a seva has too few servers to have a normal it is against the median of the temple''s other seva normals — the same quantity, never a whole devotee''s load, so being the only person doing a thing is not treated as a reason to be judged harder. A list of conversations to have, for the President and the Tech Admin. A row cleared through dismiss_seva_care stays gone until the evidence behind it has left the window. Nothing here acts, and nothing here reaches the devotee.';

revoke all on function public.list_seva_concentration(integer, numeric) from public, anon;
grant execute on function public.list_seva_concentration(integer, numeric) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. The board ranks on the number it prints.
--
--    Header section 4. Four functions, one change, made in all four at once so
--    that a devotee's own card, the public garland, the drill-down behind a
--    name and the President's whole-congregation list cannot say different
--    things about the same place.
--
--    Nothing else in any of them moves: same arguments, same return shapes,
--    same populations, same gates.
-- ---------------------------------------------------------------------------

create or replace function public.list_seva_garland(
  p_period_kind text default 'week',
  p_limit integer default 20,
  p_rank_by text default 'combined'
)
returns table (
  standing integer,
  devotee_id uuid,
  devotee_name text,
  devotee_photo_url text,
  points integer,
  tier text,
  is_you boolean,
  gathering boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_band integer := greatest(1, least(coalesce(p_limit, 20), 200));
begin
  -- Out loud, and before anything is read. A mode nobody implemented must not
  -- quietly fall through to the combined board, and it must not return silence.
  if p_rank_by is null or p_rank_by not in ('combined', 'seva') then
    raise exception
      'The garland is ranked by ''combined'' or ''seva''; "%" is neither.',
      coalesce(p_rank_by, 'null');
  end if;

  return query
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
  publishable as (
    select target.*
    from target cross join minimum
    where target.participant_count >= minimum.cohort
  ),
  ranked as (
    select
      scores.devotee_id,
      users.name as devotee_name,
      users.photo_url as devotee_photo_url,
      -- The one place the mode is read. Everything below ranks, filters and
      -- publishes this single number, so the two modes cannot drift apart.
      case when p_rank_by = 'seva' then scores.seva_norm else scores.score end
        as basis,
      (
        select definitions.tier
        from public.devotee_awards awards
        join public.award_definitions definitions
          on definitions.id = awards.award_definition_id
        where awards.devotee_id = scores.devotee_id
          and awards.period_id = scores.period_id
        order by case definitions.tier
          when 'garland' then 4
          when 'maha_prasad' then 3
          when 'token_of_appreciation' then 2
          else 1
        end desc
        limit 1
      ) as tier,
      scores.devotee_id = auth.uid() as is_you
    from public.period_scores scores
    join publishable on publishable.id = scores.period_id
    join public.users on users.id = scores.devotee_id
    where users.leaderboard_visible
      and (case when p_rank_by = 'seva' then scores.seva_norm else scores.score end) > 0
  ),
  -- THE PUBLISHED FIGURE, COMPUTED ONCE AND THEN RANKED ON. Header section 4:
  -- the board must not order by something it does not show. Points are monotone
  -- in the basis, so this can only tie two neighbours, never reorder them.
  published as (
    select ranked.*, public.seva_mala_points(ranked.basis) as points
    from ranked
  ),
  board as (
    select
      dense_rank() over (order by published.points desc)::integer as standing,
      published.devotee_id,
      published.devotee_name,
      published.devotee_photo_url,
      published.points,
      published.tier,
      published.is_you
    from published
  ),
  band as (
    select board.* from board
    where board.standing <= v_band
  )
  select band.standing, band.devotee_id, band.devotee_name,
         band.devotee_photo_url, band.points, band.tier, band.is_you, false
  from band
  where auth.uid() is not null

  union all

  -- The caller, appended, when they opted in and fell outside the band.
  select board.standing, board.devotee_id, board.devotee_name,
         board.devotee_photo_url, board.points, board.tier, board.is_you, false
  from board
  where auth.uid() is not null
    and board.is_you
    and board.standing > v_band

  union all

  -- Still gathering: one row, and a flag rather than an empty set.
  select null::integer, null::uuid, null::text, null::text, null::integer,
         null::text, false, true
  from target cross join minimum
  where auth.uid() is not null
    and target.participant_count < minimum.cohort

  -- Name last, so that devotees sharing a place come out in a stable order
  -- rather than in whatever order the plan happened to produce. A shared place
  -- is a shared place; it is not an invitation to shuffle.
  order by 8, 1, 3;
end;
$$;

comment on function public.list_seva_garland(text, integer, text) is
  'The public garland: place, coarse points and award tier, for devotees who opted in, dense-ranked among themselves ON THE PUBLISHED POINTS, so two devotees showing the same number share a place. p_rank_by is ''combined'' or ''seva'' and decides both the ordering and what the points count. Points are the score times a thousand rounded to the nearest ten — never the raw score, never seva_norm and giving_norm separately, and never a giving board. 202608040060 section 3 is the honest accounting of what publishing them costs, and 202608040067 section 4 is why the step of ten is not narrowed to settle a tie. Returns a single gathering row while the congregation is under the minimum cohort.';

revoke all on function public.list_seva_garland(text, integer, text) from public, anon;
grant execute on function public.list_seva_garland(text, integer, text) to authenticated;

-- Your own standing. Header sections 4 and 5: the place is over the published
-- points, and `standing` is taken over the devotees you may see plus yourself
-- rather than over a population you cannot.
create or replace function public.my_seva_mala(p_period_kind text default 'week')
returns table (
  period_id uuid,
  period_kind text,
  period_start date,
  period_end date,
  score numeric,
  seva_minutes integer,
  served_minutes integer,
  served_acts integer,
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
  mine as (
    select scores.*
    from public.period_scores scores
    join target on target.id = scores.period_id
    where scores.score > 0
      and scores.devotee_id = auth.uid()
  ),
  -- The board, as the garland draws it, on the figure the garland publishes.
  board as (
    select
      scores.devotee_id,
      dense_rank() over (
        order by public.seva_mala_points(scores.score) desc)::integer as board_standing
    from public.period_scores scores
    join target on target.id = scores.period_id
    join public.users on users.id = scores.devotee_id
    where scores.score > 0 and users.leaderboard_visible
  ),
  -- AND THE CALLER'S OWN PLACE, over the devotees they may see plus themselves.
  -- Header section 5. For a devotee who opted in this is the board, so the two
  -- columns carry the same number and their difference is identically zero; for
  -- a devotee who opted out it is where they would stand, over a population
  -- they can already read and a figure of their own they already know.
  visible as (
    select
      scores.devotee_id,
      dense_rank() over (
        order by public.seva_mala_points(scores.score) desc)::integer as standing
    from public.period_scores scores
    join target on target.id = scores.period_id
    join public.users on users.id = scores.devotee_id
    where scores.score > 0
      and (users.leaderboard_visible or scores.devotee_id = auth.uid())
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
  ),
  -- Everything that is not "they were not there", credited or not.
  served as (
    select
      coalesce(sum(hours.served_minutes), 0) as served_minutes,
      coalesce(sum(hours.served_acts), 0)::integer as served_acts
    from target
    join public.seva_mala_served(target.starts_on, target.ends_on, auth.uid()) hours
      on true
  )
  select
    target.id,
    target.period_kind,
    target.starts_on,
    target.ends_on,
    coalesce(mine.score, 0),
    coalesce(round(mine.credited_minutes), 0)::integer,
    coalesce(round(served.served_minutes), 0)::integer,
    coalesce(served.served_acts, 0),
    coalesce(mine.seva_acts, 0),
    coalesce(waiting.pending_acts, 0),
    coalesce(round(waiting.pending_minutes), 0)::integer,
    coalesce(mine.giving_cents, 0),
    coalesce(mine.gifts, 0),
    case when target.participant_count >= minimum.cohort then visible.standing end,
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
  cross join served
  join public.users on users.id = auth.uid()
  left join mine on true
  left join visible on visible.devotee_id = auth.uid()
  left join board on board.devotee_id = auth.uid()
  where auth.uid() is not null
$$;

comment on function public.my_seva_mala(text) is
  'Your own Seva Mala standing for the current week, month or lifetime. served_minutes is every minute you served, whatever the paperwork says; seva_minutes is what the scoring credited. The first is never smaller than the second, and the difference is what is still waiting on somebody. Both places are dense-ranked on the published points, and `standing` is taken over the devotees you may see plus yourself — so for a devotee on the board it equals board_standing exactly, and the pair can no longer be subtracted to count the devotees who opted out above you.';

revoke all on function public.my_seva_mala(text) from public, anon;
grant execute on function public.my_seva_mala(text) to authenticated;

-- The President's and the Community Head's whole-congregation board. Same
-- change, so that "you are seventh" on this screen is the seventh the
-- congregation is looking at.
create or replace function public.list_all_seva_scores(p_period_kind text default 'week')
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
    dense_rank() over (order by public.seva_mala_points(scores.score) desc)::integer,
    scores.devotee_id,
    users.name,
    -- The published figure, on 0060's grid of ten and under 0062's ceiling.
    -- This is the number on the garland, and it is what makes the Community
    -- Head's board the leaderboard rather than a list of names.
    public.seva_mala_points(scores.score),
    -- The exact score, the two components and the two giving figures. 0066
    -- header §4: score and seva_norm together give giving_norm back exactly, so
    -- the five of them travel together or not at all.
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
  'Every devotee''s Seva Mala standing, including the devotees who opted out of the public garland, flagged is_hidden. For the President, the Tech Admin and the Community Head. All three see the ranking, the published points and the seva figures; only app.view_all sees the exact score, the two norms and the giving, because score and seva_norm together give giving_norm back exactly and giving_norm gives back the gift. giving_withheld says which of the two the caller is holding, so a null cannot be read as a zero. The place is dense-ranked on the published points, so two devotees publishing the same figure share it — the rows are still ordered by the exact score.';

revoke all on function public.list_all_seva_scores(text) from public, anon;
grant execute on function public.list_all_seva_scores(text) to authenticated;

-- And the drill-down behind a name on the garland.
create or replace function public.seva_yatra_devotee_summary(
  p_devotee_id uuid,
  p_period_kind text default 'week'
)
returns table (
  devotee_id uuid,
  devotee_name text,
  devotee_photo_url text,
  period_kind text,
  period_start date,
  period_end date,
  standing integer,
  points integer,
  seva_points integer,
  score numeric,
  served_minutes integer,
  seva_minutes integer,
  seva_acts integer,
  top_seva_name text,
  top_seva_service_type_id uuid,
  top_seva_hours numeric,
  top_seva_share numeric,
  supported boolean,
  giving_cents bigint,
  gifts integer,
  giving_withheld boolean,
  is_you boolean
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
  caller as (
    select
      public.may_view_all_giving() as sees_giving,
      public.has_permission('app.view_all') as sees_everybody
  ),
  -- The board, exactly as list_seva_garland draws it: opted in, scored above
  -- zero, in a period that met the cohort, placed on the published points.
  -- Being on THIS is what makes a devotee askable-about.
  board as (
    select
      scores.devotee_id,
      scores.score,
      scores.seva_norm,
      scores.credited_minutes,
      scores.seva_acts,
      scores.giving_cents,
      scores.gifts,
      dense_rank() over (
        order by public.seva_mala_points(scores.score) desc)::integer as standing
    from public.period_scores scores
    join target on target.id = scores.period_id
    join public.users on users.id = scores.devotee_id
    where scores.score > 0
      and users.leaderboard_visible
      and target.participant_count
          >= public.seva_mala_number('seva_mala.minimum_cohort', 8)
  ),
  -- Everything about the devotee that is not the board's, including the case
  -- the board cannot see: a devotee whose every act is waiting.
  mine as (
    select
      scores.score,
      scores.seva_norm,
      scores.credited_minutes,
      scores.seva_acts,
      scores.giving_cents,
      scores.gifts
    from public.period_scores scores
    join target on target.id = scores.period_id
    where scores.devotee_id = p_devotee_id
  ),
  served as (
    select hours.served_minutes
    from target
    join public.seva_mala_served(target.starts_on, target.ends_on, p_devotee_id) hours
      on true
  ),
  top_seva as (
    select
      acts.seva_name,
      acts.service_type_id,
      sum(acts.raw_minutes) as minutes
    from target
    join public.seva_mala_acts(p_devotee_id) acts
      on acts.occurred_on between target.starts_on and target.ends_on
    where acts.points_status <> 'not_served'
      and acts.raw_minutes > 0
    group by acts.seva_name, acts.service_type_id
    order by sum(acts.raw_minutes) desc, acts.seva_name
    limit 1
  )
  select
    devotee.id,
    devotee.name,
    devotee.photo_url,
    target.period_kind,
    target.starts_on,
    target.ends_on,
    board.standing,
    -- Already public: 0060's garland publishes both of these integers, in its
    -- two modes, for every devotee on the board.
    public.seva_mala_points(mine.score),
    public.seva_mala_points(mine.seva_norm),
    case when caller.sees_giving then mine.score end,
    coalesce(round(served.served_minutes), 0)::integer,
    coalesce(round(mine.credited_minutes), 0)::integer,
    coalesce(mine.seva_acts, 0),
    top_seva.seva_name,
    top_seva.service_type_id,
    round(coalesce(top_seva.minutes, 0) / 60.0, 2),
    case
      when coalesce(served.served_minutes, 0) > 0
      then round(coalesce(top_seva.minutes, 0) / served.served_minutes, 4)
    end,
    -- 0060 section 3 already publishes this, by name, to every devotee.
    coalesce(mine.giving_cents, 0) > 0,
    case when caller.sees_giving then coalesce(mine.giving_cents, 0) end,
    case when caller.sees_giving then coalesce(mine.gifts, 0) end,
    not caller.sees_giving,
    p_devotee_id = auth.uid()
  from target
  cross join caller
  join public.users devotee on devotee.id = p_devotee_id
  left join board on board.devotee_id = p_devotee_id
  left join mine on true
  left join served on true
  left join top_seva on true
  where auth.uid() is not null
    and p_devotee_id is not null
    and (
      p_devotee_id = auth.uid()
      or caller.sees_everybody
      or board.devotee_id is not null
    )
$$;

comment on function public.seva_yatra_devotee_summary(uuid, text) is
  'Why one devotee is where they are on the Seva Yatra board for one period: their published points, the hours they actually served, how many acts, the seva they gave most of those hours to, and whether they supported the temple. The place is the garland''s place, dense-ranked on the published points. Any signed-in devotee may ask about a devotee who is on the board; app.view_all may ask about anybody; you may always ask about yourself. The exact score and the cash figures are app.view_all''s, and seva_norm and giving_norm are not in the return type at all.';

revoke all on function public.seva_yatra_devotee_summary(uuid, text) from public, anon;
grant execute on function public.seva_yatra_devotee_summary(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. Nothing here revokes an award, and the file refuses to have added a way.
--
--    0066 section 14, restated over this file's own work — which is the file
--    that most needed it, because section 1 is about an award ceasing to be
--    displayed and the only honest way to do that is a join that stops
--    matching.
-- ---------------------------------------------------------------------------

do $$
declare
  v_offenders text;
begin
  select string_agg(proc.proname, ', ' order by proc.proname) into v_offenders
  from pg_proc proc
  join pg_namespace spaces on spaces.oid = proc.pronamespace
  where spaces.nspname = 'public'
    and proc.proname in (
      'seva_mala_award_holds_now', 'current_devotee_awards',
      'list_devotee_badges', 'list_devotee_award_shelf',
      'list_seva_concentration', 'list_seva_garland', 'my_seva_mala',
      'list_all_seva_scores', 'seva_yatra_devotee_summary'
    )
    and pg_get_functiondef(proc.oid)
        ~* '(delete\s+from\s+public\.devotee_awards|update\s+public\.devotee_awards)';
  if v_offenders is not null then
    raise exception
      '% can remove or rewrite an award. Nothing in Seva Mala revokes.', v_offenders;
  end if;

  -- Every function this file rewrote is still a read.
  select string_agg(proc.proname, ', ' order by proc.proname) into v_offenders
  from pg_proc proc
  join pg_namespace spaces on spaces.oid = proc.pronamespace
  where spaces.nspname = 'public'
    and proc.proname in (
      'seva_mala_award_holds_now', 'current_devotee_awards',
      'list_seva_concentration', 'list_seva_garland', 'my_seva_mala',
      'list_all_seva_scores', 'seva_yatra_devotee_summary'
    )
    and pg_get_functiondef(proc.oid) ~* '(insert\s+into\s+public\.|delete\s+from\s+public\.)';
  if v_offenders is not null then
    raise exception '% has learned to write.', v_offenders;
  end if;

  -- And the read-time re-ask is not reachable by a devotee: it answers a
  -- question about the whole congregation's distribution and returns it one
  -- boolean at a time.
  if has_function_privilege(
       'authenticated',
       'public.seva_mala_award_holds_now(uuid, uuid, uuid)', 'execute')
  then
    raise exception 'A devotee can execute seva_mala_award_holds_now.';
  end if;
end;
$$;

do $$
begin
  raise notice
    'Award currency, Seva Care reach, the per-seva fallback and the published ranking applied.';
end;
$$;
