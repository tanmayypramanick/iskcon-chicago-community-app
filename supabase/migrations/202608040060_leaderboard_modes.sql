-- Three ways to read the garland, and points on the public board.
--
-- The client offers the congregation three leaderboards — Seva & Giving, Seva
-- only, and Supporters — and until now only the first of them could be served
-- to an ordinary devotee, and even that one came back as a bare list of places.
-- This migration serves all three, and it publishes a number beside each place,
-- which is a thing 202608040055 refused to do on purpose. Most of this header
-- is about that refusal and what it costs to withdraw it, because a privacy
-- property that is given up quietly is given up twice.
--
-- ---------------------------------------------------------------------------
-- 1. What the temple asked for.
--
--    "Show the points and the ranks." Said plainly, more than once, and about
--    a screen the temple has already designed: a game profile with a points
--    hero at the top and a ranked board beneath it. A board of positions with
--    no numbers on it reads, to the devotee looking at it, as a board whose
--    numbers are being kept from them — which is exactly what it was.
--
--    So: list_seva_garland now returns points, and it now takes a mode. And
--    list_seva_supporters names the devotees who gave in the period, because
--    "who supported the temple this month" is a question a congregation is
--    allowed to ask out loud.
--
-- ---------------------------------------------------------------------------
-- 2. What 202608040055 section 4 said, and why it said it.
--
--    NOBODY MAY READ ANYBODY'S GIVING OUT OF THIS. public.period_scores is not
--    selectable by `authenticated` in any form, the board returns POSITION OR
--    TIER ONLY, and the reason is one line of arithmetic:
--
--        giving_norm  ĝ = ln(1 + G/v_g) / ref_g       =>  G = v_g·(e^(ĝ·ref_g) − 1)
--
--    A devotee who learns ĝ, and who knows v_g and ref_g, reads another
--    devotee's giving in dollars. 0055 assumed v_g and ref_g were "learnable by
--    anyone patient enough to watch their own numbers move". That was
--    pessimistic in the wrong direction and it should be written down here:
--    they are not learnable, they are PUBLISHED. explain_my_score returns
--    seva_unit_minutes, giving_unit_cents, seva_reference and giving_reference,
--    and those four are properties of the PERIOD and not of the caller. Any
--    devotee with a score in a period already holds v_g and ref_g exactly.
--
--    So ĝ was the only missing term, and 0055's board withheld it completely.
--
-- ---------------------------------------------------------------------------
-- 3. What this migration publishes, and exactly what it costs.
--
--    Not the raw numeric score. A COARSE INTEGER: the score multiplied by a
--    thousand and rounded to the nearest ten, so the board reads 670 and 520
--    and 1,000 rather than 0.666667. One number, public.seva_mala_points, and
--    the same grid in both modes.
--
--    Take the honest accounting one leak at a time.
--
--    (a) COMBINED POINTS ALONE ARE ONE EQUATION IN TWO UNKNOWNS.
--
--            score = ( max(ŝ,ĝ) + β·min(ŝ,ĝ) ) / (1 + β)
--
--        Knowing the score tells you nothing about ĝ unless you already know ŝ.
--        For a devotee who serves and gives, it stays two unknowns and there is
--        no inversion. For a devotee who gives and does not serve at all — and
--        the seva board is where you find out who those are — ŝ = 0 and
--        ĝ = (1+β)·score, and the inversion runs.
--
--    (b) THE TWO MODES TOGETHER DO INVERT, AND PRETENDING OTHERWISE WOULD BE A
--        LIE. Nothing stops a devotee calling this function twice, once in each
--        mode, and joining the two boards on devotee_id. That hands them score
--        and ŝ for the same devotee, and the formula above rearranges:
--
--            ĝ ≤ ŝ :   ĝ = (1+β)·score/β − ŝ/β   =   3·score − 2·ŝ   at β = 0.5
--            ĝ > ŝ :   ĝ = (1+β)·score − β·ŝ     = 1.5·score − 0.5·ŝ at β = 0.5
--
--        and only one of the two branches is self-consistent, so there is no
--        ambiguity to hide behind. This is inherent in publishing a combined
--        score beside one of its two components. No rounding prevents it.
--        Rounding only widens the answer.
--
--    (c) SO WHAT THE ROUNDING BUYS, IN DOLLARS. A published value on a grid of
--        ten pins the underlying norm to ±0.005. Propagating that through the
--        rearrangements above, and then through ΔG ≈ ref_g·(v_g + G)·Δĝ:
--
--            published                     Δĝ        ΔG as a share of (v_g + G)
--            ------------------------------------------------------------------
--            raw numeric score (6 dp)    0.0000015   0.0002%   to the cent
--            round(score × 1000)         0.0015      0.19%     $1.90 in $1,000
--            THIS FILE: nearest ten      0.010       1.3%      $13 in $1,000
--            nearest ten, seva-dominant  0.025       3.2%      $32 in $1,000
--
--        (ref_g ≈ 1.28 in the congregation the verification builds; it is the
--        temple's own eightieth percentile and moves with the temple.)
--
--        One order of magnitude against the scale the client was already
--        rendering, and four against the stored score. It is the difference
--        between reading a devotee's giving and estimating it. It is not the
--        difference between reading it and not.
--
--    (d) WHAT STILL HOLDS, AND IT IS NOT NOTHING.
--
--        THE CAP. ŝ and ĝ are least(1, ...). Every devotee at or above the
--        congregation's eightieth percentile of giving has ĝ = 1 exactly and
--        publishes the identical number, so the inversion returns "at least the
--        congregation's generous end" and stops. The largest gifts — the ones
--        whose disclosure would matter most, and the ones a donor is most
--        likely to have wanted kept quiet — are the ones this cannot see at all.
--        That was always the best property in 0055's design and it survives the
--        reversal untouched.
--
--        THE COMPONENTS ARE STILL NEVER PUBLISHED AS COMPONENTS. There is no
--        'giving' mode and there will not be one: it would hand ĝ over directly
--        and turn a 3% estimate into an exact figure. giving_norm does not
--        appear in any devotee-callable return in this file or in 0055, and
--        seva_norm appears only as coarse points and only as the thing the
--        'seva' board is ranked by. public.period_scores, public.seva_mala_periods
--        and public.app_settings are still unreadable by `authenticated`, and
--        section 0 refuses to apply this migration if that has changed.
--
--        THE OPT-IN. Only devotees who set leaderboard_visible are on either
--        board or on the supporters list. A devotee who does not want to be
--        estimated has one switch and it works.
--
--    (e) WHY TEN AND NOT ONE, FIVE, TWENTY-FIVE OR FIFTY. One and five cost the
--        display nothing and buy correspondingly little; ten is the coarsest
--        grid that still separates adjacent devotees on a twenty-row board in a
--        congregation of this size, and it is a clean factor of ten against the
--        scale the client was already rendering. Twenty-five and fifty leave 41
--        and 21 distinct values for a whole board and collapse neighbours into
--        shared numbers often enough that the points stop looking like points.
--        The step is a constant in one function rather than a dial in
--        app_settings, for 0055's reason: a dial is a thing somebody widens
--        later without noticing what it guarded.
--
--    (f) SAID PLAINLY. This is a REDUCTION IN PRIVACY. 0055 section 4 no longer
--        describes this system. A devotee who is willing to call two RPCs and do
--        five lines of algebra can estimate any opted-in devotee's giving for a
--        period to within a few percent, unless that devotee is at the cap. The
--        temple asked for points and ranks on the board knowing this, and it is
--        the temple's congregation and the temple's call. What is owed in return
--        is that the cost is written down where the next person to touch this
--        will read it, rather than discovered by a devotee.
--
-- ---------------------------------------------------------------------------
-- 4. Supporters is recognition, not a donor wall.
--
--    list_seva_supporters returns names and faces and NOTHING ELSE. No amount,
--    no count of gifts, no total — no amount column exists in the return type at
--    all, so there is nothing for a later edit to widen. And it is ordered BY
--    NAME, deliberately, because an ordering is a ranking that has had its
--    numbers taken off: a list sorted by giving tells you who gave most just as
--    surely as printing the figure would. Alphabetical order carries no
--    information about anybody.
--
--    It reuses leaderboard_visible as its one consent. That is the switch the
--    congregation already understands and the only one that exists. If the
--    temple later wants "on the board but not on the supporters list" to be a
--    separate answer, that is a second column and a second toggle and an honest
--    thing to add; it is not something to fake by inferring intent from a flag
--    that was offered for something else.
--
--    The minimum cohort does not gate it. That rule protects a small
--    congregation from being RANKED in public, and this is not a ranking.
--
-- ---------------------------------------------------------------------------
-- 5. The mode, and why the whole signature had to be dropped.
--
--    list_seva_garland gains a return column and a third argument. Both of
--    those require dropping the function rather than replacing it, and the drop
--    must name BOTH the old two-argument signature and the new three-argument
--    one. Leaving public.list_seva_garland(text, integer) in place beside
--    public.list_seva_garland(text, integer, text) makes the two-argument call
--    every existing caller makes ambiguous, and Postgres refuses it with
--    "function is not unique". That has broken this repository before.
--
--    The function is plpgsql now, and that is not a style choice: an invalid
--    p_rank_by has to be refused out loud, and a guard inside a `language sql`
--    body is only evaluated if the planner happens to need the branch it sits
--    in. A board that returned silence for a typo would be worse than one that
--    returned the wrong ranking.
--
-- Requires 202608040055_seva_mala.sql and 202608040059_seva_mala_fairness.sql.

-- ---------------------------------------------------------------------------
-- 0. The ground this stands on.
--
--    Asserted rather than assumed. Everything section 3 claims about what is
--    still protected is a claim about grants and functions that live in other
--    files, and a claim that stops being true silently is worse than no claim.
-- ---------------------------------------------------------------------------

do $$
declare
  v_holders text;
  v_beta numeric;
begin
  if to_regprocedure('public.list_seva_garland(text, integer)') is null
    and to_regprocedure('public.list_seva_garland(text, integer, text)') is null
  then
    raise exception
      'public.list_seva_garland is missing; apply 202608040055 first.';
  end if;

  if to_regprocedure('public.seva_mala_score(numeric, numeric, numeric)') is null
    or to_regprocedure('public.my_seva_mala(text)') is null
    or to_regprocedure('public.explain_my_score(uuid)') is null
  then
    raise exception
      'Seva Mala is not in place; apply 202608040055 and 202608040059 first.';
  end if;

  -- The inversion in section 3 is bounded by the balance rule being 0059's.
  -- If the two terms are ever swapped back, the arithmetic in the header is
  -- describing a different function and the published points mean something
  -- else. Checked by value rather than by reading the body.
  if public.seva_mala_score(1.0, 0.0, 0.5) <> 0.666667
    or public.seva_mala_score(0.0, 1.0, 0.5) <> 0.666667
    or public.seva_mala_score(1.0, 1.0, 0.5) <> 1.000000
  then
    raise exception
      'public.seva_mala_score is no longer 202608040059''s rule; the published points would mean something this file has not reasoned about.';
  end if;

  v_beta := public.seva_mala_number('seva_mala.balance_beta', 0.5);
  if v_beta is null or v_beta < 0 or v_beta > 1 then
    raise exception
      'seva_mala.balance_beta is %, which is outside [0, 1].', v_beta;
  end if;

  -- 0055 section 4, in the part of it this migration does NOT reverse. The
  -- components and the references stay unreadable; only a coarse combined
  -- figure and a coarse seva figure leave the database.
  if has_table_privilege('authenticated', 'public.period_scores', 'select')
    or has_table_privilege('authenticated', 'public.seva_mala_periods', 'select')
    or has_table_privilege('authenticated', 'public.app_settings', 'select')
  then
    raise exception 'authenticated can already read the Seva Mala components.';
  end if;

  -- The supporters list reads who gave. It must not become a second way to read
  -- how much, so the table that holds the amounts stays the President's.
  if has_table_privilege('authenticated', 'public.donations', 'select') then
    raise exception 'authenticated can read public.donations directly.';
  end if;

  select string_agg(roles.name, ',' order by roles.name) into v_holders
  from public.role_permissions
  join public.roles on roles.id = role_permissions.role_id
  where role_permissions.permission_key = 'app.view_all';
  if v_holders is distinct from 'president,tech' then
    raise exception
      'app.view_all is held by % — Seva Mala assumes president, tech.', v_holders;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 1. The published scale, in one place.
--
--    A score is a ratio on [0, 1] against what this congregation itself did.
--    "0.42" is a statistic; the temple asked for a game profile, and a game
--    shows points. A thousand is the unit, and a step of ten is the resolution.
--
--    Both are constants and neither is a dial. seva_mala.balance_beta is the
--    temple's number because it is a statement about what the temple values;
--    this is not that. It is the width of the interval a devotee's giving can
--    be estimated to, and section 3(e) is why it is not somewhere a President
--    can lower it to 1 on a Tuesday without knowing what they have done.
--
--    Floored at one step for anything strictly positive, so a devotee who gave
--    two dollars and is genuinely on the board is not shown "0 points" beside
--    their own name. Capped at the thousand, because the norms are capped at 1
--    and the ceiling should be visible here rather than inferred.
-- ---------------------------------------------------------------------------

create or replace function public.seva_mala_points(p_norm numeric)
returns integer
language sql
immutable
set search_path = ''
as $$
  select case
    when p_norm is null or p_norm <= 0 then 0
    else greatest(10, round(least(1.0, p_norm) * 1000 / 10.0) * 10)::integer
  end
$$;

comment on function public.seva_mala_points(numeric) is
  'A Seva Mala norm published as points: multiplied by a thousand and rounded to the nearest ten, capped at 1000 and floored at 10 for anything positive. The step is the width of the interval somebody can estimate a devotee''s giving to, and it is a constant rather than a dial for that reason. 202608040060 section 3 has the arithmetic.';

revoke all on function public.seva_mala_points(numeric) from public, anon;
-- Granted for 0059's reason: it is arithmetic over a number the caller has to
-- supply and it reveals nothing. A client that wants its own hero to agree with
-- the board asks for the scale rather than re-implementing it and drifting.
grant execute on function public.seva_mala_points(numeric) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. The garland, with points and a mode.
--
--    Both signatures dropped first — see section 5 of the header. The two-
--    argument form has to go or every existing two-argument call becomes
--    ambiguous against the defaulted three-argument one.
--
--    What has NOT changed: opted-in devotees only, dense ranking over the
--    opted-in set so the board has no gaps for anybody to read an absence out
--    of, the caller appended below the band when they fall outside it, and the
--    single gathering row while the congregation is under the minimum cohort.
--    The mode changes what the board is sorted by and what the number beside
--    each name counts. It changes nothing else.
--
--    'combined'  ranked by score. Points are the combined score.
--    'seva'      ranked by seva_norm. Points are the seva figure, on the same
--                grid. Devotees with no seva in the period are not on it —
--                the basis is the filter as well as the ordering, exactly as
--                award_seva_mala_for_period's top_n rules already work.
--
--    There is no 'giving' mode. Header section 3(d).
-- ---------------------------------------------------------------------------

drop function if exists public.list_seva_garland(text, integer);
drop function if exists public.list_seva_garland(text, integer, text);

create function public.list_seva_garland(
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
  board as (
    select
      dense_rank() over (order by ranked.basis desc)::integer as standing,
      ranked.devotee_id,
      ranked.devotee_name,
      ranked.devotee_photo_url,
      public.seva_mala_points(ranked.basis) as points,
      ranked.tier,
      ranked.is_you
    from ranked
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

  order by 8, 1;
end;
$$;

comment on function public.list_seva_garland(text, integer, text) is
  'The public garland: place, coarse points and award tier, for devotees who opted in, dense-ranked among themselves. p_rank_by is ''combined'' or ''seva'' and decides both the ordering and what the points count. Points are the score times a thousand rounded to the nearest ten — never the raw score, never seva_norm and giving_norm separately, and never a giving board. 202608040060 section 3 is the honest accounting of what publishing them costs. Returns a single gathering row while the congregation is under the minimum cohort.';

revoke all on function public.list_seva_garland(text, integer, text) from public, anon;
grant execute on function public.list_seva_garland(text, integer, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Who gave, and nothing about how much.
--
--    Read off public.period_scores rather than public.donations, for two
--    reasons. It is the same window the garland is drawn from, so the two
--    screens agree with each other and are as of the same nightly recompute
--    rather than differing by a day for reasons no devotee could guess. And it
--    means the one devotee-callable function that answers a question about
--    giving never touches the table that holds the amounts.
--
--    giving_cents > 0 is the whole of the test, and giving_cents does not
--    appear in the return. A devotee who gave nothing in the period is simply
--    not here; there is no zero row to count.
-- ---------------------------------------------------------------------------

create or replace function public.list_seva_supporters(p_period_kind text)
returns table (
  devotee_id uuid,
  devotee_name text,
  devotee_photo_url text
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
  )
  select
    scores.devotee_id,
    users.name,
    users.photo_url
  from public.period_scores scores
  join target on target.id = scores.period_id
  join public.users on users.id = scores.devotee_id
  where auth.uid() is not null
    and scores.giving_cents > 0
    and users.leaderboard_visible
  -- BY NAME. An ordering is a ranking with the numbers taken off, and a
  -- supporters list sorted by giving would say who gave most as plainly as
  -- printing the figure. The id is only a tiebreak between two devotees of the
  -- same name; it is a random uuid and says nothing about either of them.
  order by users.name, scores.devotee_id
$$;

comment on function public.list_seva_supporters(text) is
  'The devotees who gave to the temple in the period, for any devotee to read. Opted-in only, no amount, no gift count, no total, and ordered by name rather than by giving so no ranking can be reconstructed from the order. Recognition, not a donor wall.';

revoke all on function public.list_seva_supporters(text) from public, anon;
grant execute on function public.list_seva_supporters(text) to authenticated;

do $$
begin
  raise notice 'leaderboard modes applied';
end;
$$;
