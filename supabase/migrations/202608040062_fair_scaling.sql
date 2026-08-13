-- Fair scaling: the cap made soft, and every act told what it was worth.
--
-- Two things the temple has said since 0060 shipped. The first is a correction
-- to the scoring; the second is a hole in what a devotee can see.
--
-- ---------------------------------------------------------------------------
-- 1. "Why does $2,500 have the same seva points as $600?"
--
--    Because 0055 wrote
--
--        s-hat = least(1, u_s/ref_s)      g-hat = least(1, u_g/ref_g)
--
--    and both of those gifts clear the congregation's eightieth percentile, so
--    both are held at exactly 1.0 and score exactly 0.666667 and publish
--    exactly 670 points. 0055 called that cap "the point", and it was: it is
--    what stops money buying the top. But the temple is right that flattening a
--    $2,500 deity dress and a $600 gift into an identical number is its own
--    unfairness, and it is an unfairness the devotee can SEE, because 0060 put
--    the number on the board beside their name.
--
--    So the hard cap becomes a soft one. Above the reference, further giving
--    still counts, with steeply diminishing returns:
--
--        normalised(u, ref) = u / ref                                u <= ref
--                           = 1 + alpha * ln(1 + (u - ref)/ref)      u >  ref
--
--    which is continuous at u = ref (ln(1) = 0, so both arms give 1) and, since
--    1 + (u - ref)/ref is just u/ref, is the same thing as 1 + alpha*ln(u/ref).
--    It is a logarithm ON TOP OF a logarithm: u is already ln(1 + G/v_g), so
--    what a second thousand dollars buys past the reference is the log of the
--    log of it. Beyond the congregation's generous end, money moves the number
--    the way a mountain moves a barometer.
--
--    alpha = 0.15, in public.app_settings, not in a function body.
--
--    WHAT THAT BUYS, in the congregation the verification builds
--    (v_g = $250 the median gift, ref_g = ln(2.8) = 1.0296 the eightieth
--    percentile of ln(1 + G/v_g), so the reference gift is $450):
--
--      gift      u        u/ref    OLD norm  NEW norm   OLD pts   NEW pts
--      ---------------------------------------------------------------------
--      $25       0.0953   0.0926   0.092568  0.092568        60        60
--      $100      0.3365   0.3268   0.326793  0.326793       220       220
--      $250      0.6931   0.6732   0.673207  0.673207       450       450
--      $450      1.0296   1.0000   1.000000  1.000000       670       670
--      $600      1.2238   1.1886   1.000000  1.025913       670       680
--      $1,710    2.0592   2.0000   1.000000  1.103972       670       740
--      $2,500    2.3979   2.3289   1.000000  1.126810       670       750
--
--    (Points are what a devotee who only gives publishes on the garland:
--    score = norm/1.5, times a thousand, on 0060's grid of ten.)
--
--    $2,500 now reads as meaningfully more than $600 — seventy points apart on
--    a board where the whole of the congregation's generous end is worth 670 —
--    and it is nowhere near twice as much: 4.17 times the money buys 1.098
--    times the points. Below the reference NOTHING MOVES AT ALL. A devotee who
--    gave $100 has exactly the score they had yesterday, which matters, because
--    most of the congregation is below the reference and none of them asked for
--    this change.
--
--    The seva side is the same function of the same shape:
--
--      minutes   u        u/ref    OLD norm  NEW norm
--      -----------------------------------------------
--      180       0.6931   0.3869   0.386853  0.386853
--      540       1.3863   0.7737   0.773706  0.773706
--      900       1.7918   1.0000   1.000000  1.000000   the reference, 15 hours
--      2,700     2.7726   1.5474   1.000000  1.065488   45 hours
--      6,300     3.5835   2.0000   1.000000  1.103972   105 hours
--
--    WHY 0.15 AND NOT SOMETHING ELSE. The number that decides it is not the
--    $2,500 row, it is where the surplus would start to be worth more than the
--    second string of the garland. Under 0059's rule a devotee at the reference
--    in one dimension scores 1/(1+beta) = 0.6667, and reaching the reference in
--    the OTHER dimension as well adds beta/(1+beta) = 0.3333. Giving beyond the
--    reference adds alpha*ln(u/ref)/(1+beta). Set those equal and the surplus
--    would exactly replace serving:
--
--        alpha * ln(u/ref) = beta            u/ref = exp(beta/alpha)
--
--    That crossing point IS the ceiling in section 2, and how far away it sits
--    is the whole of the choice:
--
--      alpha   $2,500 vs $600   crossing at u/ref   the gift that reaches it
--      ---------------------------------------------------------------------
--      0.10        1.066              148.4                  $6 x 10^68
--      0.15        1.098               28.0                  $9 x 10^14
--      0.20        1.130               12.2                  $70,000,000
--      0.25        1.161                7.4                     $503,000
--
--    At 0.25 a single capital gift of half a million dollars would reach the
--    ceiling — which is to say the hard cap would come back, at a higher
--    number, and the temple would be having this conversation again with a
--    bigger cheque. At 0.10 the separation the temple asked for barely exists.
--    0.15 answers the complaint and leaves the crossing nine orders of
--    magnitude beyond any gift this temple will ever receive, so the cap is
--    soft everywhere a devotee can actually stand and the ceiling is a rail
--    rather than a wall.
--
--    Stated the other way round, which is how a President should read it: past
--    the congregation's generous end, DOUBLING your compressed offering is
--    worth 0.15*ln(2) = 0.104 — about a tenth of what reaching that end was
--    worth in the first place, and less than a third of what turning up and
--    serving would be worth instead.
--
--    WHAT DOES NOT MOVE. The log compression, the congregation-relative P80
--    references, the shrinkage toward the trailing quarter, the median-of-
--    medians units and 0059's inverted balance rule — the larger offering
--    counts whole, the smaller counts for beta of itself — are untouched, and
--    the verification re-derives all of them. The temple restated in the same
--    breath that the scoring must depend on what devotees actually do rather
--    than on constants, and that is exactly what ref_s and ref_g are. alpha
--    does not scale anybody against anything; it only decides how steeply the
--    ground rises after the congregation's own eightieth percentile.
--
--    THE ARCHETYPES STILL HOLD, and they hold for a reason that is worth
--    writing down: normalised(u, ref) is a function of u/ref ALONE. A devotee
--    at twice the congregation's seva reference and a devotee at twice its
--    giving reference get the identical number — 1.103972 — and therefore the
--    identical score, 0.735981. The soft cap cannot favour one dimension over
--    the other because it never sees which dimension it is in. And a devotee
--    who reached the reference in BOTH still scores 1.000000 and still beats
--    both of them, which is the sentence the whole file exists to keep true.
--
-- ---------------------------------------------------------------------------
-- 2. Scores can now exceed 1. What that means, and where it stops.
--
--    THE CEILING IS 1 + beta, WHICH IS 1.5, and it is derived rather than
--    declared. Section 1 has the derivation: at u/ref = exp(beta/alpha) the
--    normalised value reaches 1 + beta, and at that point a devotee who has
--    only given would tie a devotee who reached the congregation's generous end
--    with both their hands and their means. That tie is the line the temple
--    drew in 0055 and has never moved, so it is where the soft cap stops being
--    soft:
--
--        norm    <= 1 + beta          per dimension
--        score   <= 1 + beta          because score is a weighted mean of the two
--        points  <= 1000 * (1 + beta) = 1500
--
--    It moves with beta and cannot drift away from it. At beta = 0 — the
--    setting that says only your strongest dimension counts — the ceiling is
--    exactly 1 and the hard cap returns, which is right: with no credit for the
--    second string, letting the first one run past the reference WOULD let
--    money buy the top.
--
--    So the new score ceiling is 1.5 and the new published ceiling is 1500
--    points. What is REACHABLE is a different and much smaller number: a
--    devotee at five times the congregation's reference in both dimensions
--    scores 1.24. The rail exists so that the arithmetic is bounded and the
--    client can draw a scale, not because anybody will ever touch it.
--
--    THE TIER BANDS NEED NO CHANGE, and this is worth stating rather than
--    assuming. Every award in public.award_definitions that is decided by a
--    level is a derived_threshold with a threshold_quantile: "the level of the
--    congregation's median active devotee", "the more giving three-quarters".
--    They are percentiles of the scores that were actually computed, so they
--    move with the distribution and there is no constant anywhere that says
--    0.75 is a Token of Appreciation. Section 0 refuses to apply this migration
--    if an absolute threshold has appeared since.
--
-- ---------------------------------------------------------------------------
-- 3. "Show how many seva points are gained on each seva done, each donation
--     done, in a list."
--
--    THINK ABOUT WHAT "POINTS FOR ONE ACT" CAN EVEN MEAN. A score is not a sum
--    of per-act values. It is
--
--        ln(1 + S/v_s)  ->  divided by the congregation's reference
--                       ->  softly capped
--                       ->  mixed with the giving side by max/min
--
--    and every one of those steps is non-linear in S. There is no addend to
--    hand back. Three things a per-act figure could honestly be:
--
--      marginal        what the score would fall by if this act had not
--                      happened. Defensible, and it does NOT add up: the log is
--                      concave, so the marginals of n acts sum to less than the
--                      whole, and each one depends on which other acts you
--                      imagine removing first. A devotee adding up a column
--                      that comes to less than their total is a devotee who has
--                      been misled.
--
--      Shapley         the average marginal over every order. Adds up exactly,
--                      and is not computable in a query a phone waits on.
--
--      SHARE           this act's part of the dimension's points, in proportion
--                      to what it contributed to the total the logarithm was
--                      taken of. Adds up exactly, by construction, and is
--                      cheap.
--
--    THIS FILE RETURNS SHARES, and says so in the rows it returns. Precisely:
--
--      * The window's seva total S and giving total G are computed exactly as
--        the recompute computes them, from the same helper, with the same
--        quality rule and the same caps.
--      * s-hat and g-hat are computed from them against the units and
--        references of a real period, so the arithmetic is the board's.
--      * The score splits into two parts with NO approximation at all, because
--        0059's rule is already a weighted sum of exactly two terms:
--
--            score * (1 + beta) = max(s-hat, g-hat) + beta * min(s-hat, g-hat)
--
--        The first term belongs to whichever dimension is the larger and the
--        second to the other. seva_points + giving_points = total_points,
--        exactly, always.
--      * Within a dimension, an act's share is its weighted minutes over S, and
--        a gift's share is its cents over G. Weighted minutes are what actually
--        entered the logarithm — after quality, after the scarcity weight,
--        after the daily and weekly caps — so an act that was marked absent has
--        a share of zero and is listed with a zero beside it and the reason in
--        words, which is the honest answer to "why didn't Tuesday count".
--      * The integers are apportioned by RUNNING TOTAL: the nth act's points
--        are round(P * cum_n) - round(P * cum_(n-1)). Every row is a whole
--        number of points and the rows sum to round(P) exactly, with no
--        remainder for a devotee to notice.
--
--    WHAT A SHARE IS NOT. It is not what the act would have been worth on its
--    own, and it is not what you would lose by not doing it. Because the
--    logarithm is concave, an act done when you have already served fifty hours
--    is worth less at the margin than the share says, and the first act of the
--    month is worth more. The returned `attribution` column says this in
--    English so no client has to invent a caption for it.
--
--    WHICH PERIOD'S SCALE. The functions take a window, and a window is not
--    always a period. The units and the references come from the NARROWEST
--    computed period that wholly contains the window — the week if the window
--    fits inside this week, else the month, else the lifetime — and
--    `is_whole_period` says whether the window is the whole of it. When it is,
--    total_points is exactly the board's number for that period and the
--    verification asserts precisely that. When it is not, the points are what
--    that window is worth on that period's scale, the parts still sum to the
--    whole, and the note says which it is.
--
--    ON CURRENCY. A gift's share is its amount_cents over the window's total
--    cents, summed across currencies, because that is what public.period_scores
--    has done since 0055 and the points must agree with the board rather than
--    with public.donation_totals, which refuses to sum across currencies for
--    its own good reasons. Said out loud rather than discovered.
--
--    WHO MAY ASK. my_seva_act_points and my_giving_points have NO devotee
--    argument, exactly as my_seva_acts and my_donation_totals have none: there
--    is nothing to pass and therefore nothing to pass somebody else's id to.
--    The President's equivalents are separate functions, take app.view_all, and
--    return the identical shape column for column, so one client component
--    renders either — 0061 section 8's rule, followed.
--
-- Requires 202608040055, 202608040059, 202608040060 and 202608040061.

-- ---------------------------------------------------------------------------
-- 0. The ground this stands on.
--
--    Asserted rather than assumed. This migration changes the last third of the
--    scoring and everything it claims about what is still protected is a claim
--    about grants and functions that live in other files.
-- ---------------------------------------------------------------------------

do $$
declare
  v_holders text;
  v_beta numeric;
  v_absolute integer;
begin
  if to_regprocedure('public.recompute_seva_mala_period(uuid)') is null
    or to_regprocedure('public.seva_mala_score(numeric, numeric, numeric)') is null
    or to_regprocedure('public.seva_mala_points(numeric)') is null
    or to_regprocedure('public.seva_mala_acts(uuid)') is null
    or to_regprocedure('public.explain_my_score(uuid)') is null
    or to_regprocedure('public.my_seva_acts(date, date)') is null
    or to_regprocedure('public.list_devotee_seva_acts(uuid, date, date)') is null
  then
    raise exception
      'Seva Mala is not in place; apply 202608040055 through 202608040061 first.';
  end if;

  -- The balance rule this file's ceiling is derived from. Checked by value: if
  -- the two terms are ever swapped back, 1 + beta is no longer the point at
  -- which a surplus would replace the second string, and section 2 is wrong.
  if public.seva_mala_score(1.0, 0.0, 0.5) <> 0.666667
    or public.seva_mala_score(0.0, 1.0, 0.5) <> 0.666667
    or public.seva_mala_score(1.0, 1.0, 0.5) <> 1.000000
  then
    raise exception
      'public.seva_mala_score is no longer 202608040059''s rule; the ceiling this file derives would mean something else.';
  end if;

  v_beta := public.seva_mala_number('seva_mala.balance_beta', 0.5);
  if v_beta is null or v_beta < 0 or v_beta > 1 then
    raise exception
      'seva_mala.balance_beta is %, which is outside [0, 1] and cannot be the weight on the smaller offering.',
      v_beta;
  end if;

  -- Section 2's claim that no tier band is an absolute number. Every award
  -- decided by a level must still be a quantile of the congregation.
  select count(*) into v_absolute
  from public.award_definitions
  where is_active
    and rule_kind = 'derived_threshold'
    and threshold_quantile is null;
  if v_absolute > 0 then
    raise exception
      '% active awards are decided by a level that is not a quantile of the congregation. A score above 1.0 would mean something this file has not reasoned about.',
      v_absolute;
  end if;

  -- 0055 section 4, in the part nothing here reverses.
  if has_table_privilege('authenticated', 'public.period_scores', 'select')
    or has_table_privilege('authenticated', 'public.seva_mala_periods', 'select')
    or has_table_privilege('authenticated', 'public.app_settings', 'select')
    or has_table_privilege('authenticated', 'public.donations', 'select')
  then
    raise exception 'authenticated can already read the Seva Mala components or the amounts.';
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
-- 1. The dial.
--
--    One number, in app_settings, because how steeply the ground rises past the
--    congregation's generous end is the temple's judgement and not ours. ON
--    CONFLICT DO NOTHING so re-applying never stamps on a value the temple has
--    since changed.
--
--    Zero is a legal setting and it is exactly 0055's hard cap: normalised()
--    returns 1 + 0*ln(...) = 1 for everything above the reference. A President
--    who decides the temple was right the first time sets it to 0 and the next
--    nightly recompute obeys, with no migration and no developer.
-- ---------------------------------------------------------------------------

insert into public.app_settings (key, value)
values
  -- The weight on giving or serving BEYOND the congregation's reference:
  --   norm = 1 + alpha * ln(u / ref)   for u > ref,   and u/ref for u <= ref.
  --
  -- Lives on [0, 1]. 0 is 202608040055's hard cap exactly. 0.15 separates a
  -- $2,500 gift from a $600 one by seventy published points while leaving the
  -- ceiling — the point at which a surplus would be worth as much as serving —
  -- at 28 times the congregation's own eightieth percentile, which is to say
  -- unreachable. Above about 0.2 that crossing comes within reach of a single
  -- capital gift and the flattening the temple complained about comes back at a
  -- higher number.
  ('seva_mala.soft_cap_alpha', '0.15')
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------
-- 2. The ceiling, derived from the balance rule rather than typed in.
--
--    1 + beta. Section 2 of the header is the derivation, and the reason it is
--    a function rather than a constant is that beta is a dial: if a President
--    moves the weight on the second string, the point at which a surplus would
--    replace it moves with it, and a ceiling that stayed at 1.5 would quietly
--    stop meaning what this file says it means.
--
--    Stable rather than immutable because it reads a setting. Definer because
--    seva_mala_number is not granted to anybody — the dials are read by
--    functions, never by clients — and granted onward because the top of the
--    scale is a thing a client needs in order to draw a bar, and because
--    explain_my_score already hands the caller beta.
-- ---------------------------------------------------------------------------

create or replace function public.seva_mala_norm_ceiling()
returns numeric
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_beta numeric := public.seva_mala_number('seva_mala.balance_beta', 0.5);
begin
  if v_beta is null or v_beta < 0 or v_beta > 1 then
    raise exception
      'seva_mala.balance_beta is %, which is outside [0, 1]; there is no ceiling to derive from it.',
      coalesce(v_beta::text, 'null');
  end if;

  -- The point at which giving past the reference would be worth exactly as much
  -- as reaching the reference in the other dimension. Nothing may go further,
  -- because further is where money buys the top.
  return 1 + v_beta;
end;
$$;

comment on function public.seva_mala_norm_ceiling() is
  'The most a single dimension may ever be worth: 1 + balance_beta, which is the point at which giving beyond the congregation''s reference would be worth as much as reaching that reference with your hands. Derived from the dial rather than typed in, so the two cannot drift apart. At beta = 0 it is 1 and 202608040055''s hard cap returns.';

revoke all on function public.seva_mala_norm_ceiling() from public, anon;
grant execute on function public.seva_mala_norm_ceiling() to authenticated;

-- ---------------------------------------------------------------------------
-- 3. The soft cap, in one pure function.
--
--    0059 pulled the balance rule out of the middle of a three-hundred-line
--    recompute for a reason: the only way to check a formula written inline is
--    to re-type it in a verification script and hope. Same reasoning, same
--    treatment. One place to read, one place to change, one place to mutate
--    when somebody wants to know whether the tests would notice.
--
--    Immutable and granted to authenticated: it is arithmetic over four numbers
--    the caller has to supply, it reads nothing, and explain_my_score exists so
--    that a devotee can put their own u and ref back through the same function
--    the board used rather than being asked to trust it.
--
--    Every argument is guarded out loud. A null or non-positive reference is
--    the one that matters most: ref is a denominator, and a silent null here
--    would turn a devotee's whole dimension into a null and then into a zero
--    somewhere downstream, which is a scoring bug nobody finds.
-- ---------------------------------------------------------------------------

create or replace function public.seva_mala_normalise(
  p_utility numeric,
  p_reference numeric,
  p_alpha numeric,
  p_ceiling numeric
)
returns numeric
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_u numeric := coalesce(p_utility, 0);
begin
  if p_reference is null or p_reference <= 0 then
    raise exception
      'A Seva Mala reference is a denominator and must be positive; % is not.',
      coalesce(p_reference::text, 'null');
  end if;
  if p_alpha is null or p_alpha < 0 or p_alpha > 1 then
    raise exception
      'seva_mala.soft_cap_alpha is the weight on offering beyond the congregation''s reference and must lie in [0, 1]; % does not.',
      coalesce(p_alpha::text, 'null');
  end if;
  if p_ceiling is null or p_ceiling < 1 then
    raise exception
      'The Seva Mala ceiling must be at least 1; % would put the congregation''s own reference above it.',
      coalesce(p_ceiling::text, 'null');
  end if;

  -- Nothing offered is nothing scored. Guarded before the division so that a
  -- devotee with no seva at all never reaches the logarithm.
  if v_u <= 0 then
    return 0;
  end if;

  -- Up to the congregation's generous end, a straight ratio: this is 0055's
  -- arm and it is untouched, which is why nobody below the reference moves.
  if v_u <= p_reference then
    return round(v_u / p_reference, 6);
  end if;

  -- Past it, a logarithm on top of the logarithm u already is. Note that
  -- 1 + (u - ref)/ref is u/ref, so this is continuous at u = ref and strictly
  -- increasing after it. Railed, never to be reached — see section 2.
  return round(
    least(
      p_ceiling,
      1 + p_alpha * ln(1 + (v_u - p_reference) / p_reference)
    ),
    6
  );
end;
$$;

comment on function public.seva_mala_normalise(numeric, numeric, numeric, numeric) is
  'One dimension of a devotee''s offering, scaled against the congregation''s reference. Up to the reference it is the plain ratio; past it, 1 + alpha*ln(u/ref) — steeply diminishing, continuous at the reference, and railed at the ceiling. A function of u/ref alone, which is why a devotee at twice the seva reference and a devotee at twice the giving reference get the identical number.';

revoke all on function public.seva_mala_normalise(numeric, numeric, numeric, numeric)
  from public, anon;
grant execute on function public.seva_mala_normalise(numeric, numeric, numeric, numeric)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 4. The published scale, told where its top is.
--
--    0060 published round(norm * 1000) on a grid of ten and clamped it at a
--    thousand because the norms were clamped at 1. They are not any more, and a
--    clamp left at a thousand would reinstate the exact flattening this file
--    exists to remove — at the top of the board, which is where the temple was
--    looking when it complained.
--
--    So the clamp becomes the ceiling: 1500 points, moving with beta. The unit
--    and the STEP do not change. 0060 section 3(e) is why the step of ten is a
--    constant here rather than a dial in app_settings, and it stands: the step
--    is the width of the interval somebody can estimate a devotee's giving to.
--    Nothing about a softer cap makes that estimate sharper — if anything the
--    cap's disappearance at the top is a small LOSS, because 0060 section 3(d)
--    leant on every large donor publishing the identical 1000. Said out loud:
--    above the reference, giving is now estimable rather than indistinguishable,
--    and the devotees that affects are the ones giving most.
--
--    Volatility moves from immutable to stable, and the function becomes a
--    definer, because it now reads the ceiling from the dial rather than
--    carrying it as a literal. The alternative — a 1500 typed in here beside a
--    1 + beta computed there — is two numbers that can disagree.
-- ---------------------------------------------------------------------------

create or replace function public.seva_mala_points(p_norm numeric)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when p_norm is null or p_norm <= 0 then 0
    else greatest(
      10,
      round(least(public.seva_mala_norm_ceiling(), p_norm) * 1000 / 10.0) * 10
    )::integer
  end
$$;

comment on function public.seva_mala_points(numeric) is
  'A Seva Mala norm published as points: multiplied by a thousand and rounded to the nearest ten, floored at 10 for anything positive and capped at the ceiling — 1 + balance_beta, which is 1500 points. The step is the width of the interval somebody can estimate a devotee''s giving to and is a constant rather than a dial for that reason. 202608040060 section 3 has the arithmetic; 202608040062 section 4 has what the soft cap costs it.';

revoke all on function public.seva_mala_points(numeric) from public, anon;
grant execute on function public.seva_mala_points(numeric) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. The recompute, with the scaling line changed and nothing else.
--
--    Restated whole because that is what replacing a function means, and
--    reviewed line by line against 0059 section 3 so that "nothing else" is
--    true rather than hoped for. The units are still the median of medians, the
--    totals are still period totals, the compression is still ln(1 + x/unit),
--    the references are still the congregation's own eightieth percentile
--    shrunk toward the trailing quarter and floored at ln(2), the balance is
--    still 0059's, and a frozen period is still left alone.
--
--    Two changes, both in the last third:
--
--      * alpha and the ceiling are read and checked before anything is written,
--        so a bad dial costs a period nothing rather than costing it a
--        half-written rebuild;
--      * least(1.0, u/ref) becomes public.seva_mala_normalise.
-- ---------------------------------------------------------------------------

create or replace function public.recompute_seva_mala_period(p_period_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_period public.seva_mala_periods;
  v_today date;
  v_from date;
  v_to date;
  v_trail_from date;
  v_beta numeric;
  v_alpha numeric;
  v_ceiling numeric;
  v_quantile numeric;
  v_shrink numeric;
  v_floor numeric;
  v_unit_seva numeric;
  v_unit_giving numeric;
  v_ref_seva numeric;
  v_ref_giving numeric;
  v_ref_seva_period numeric;
  v_ref_seva_trail numeric;
  v_ref_giving_period numeric;
  v_ref_giving_trail numeric;
  v_n_seva integer;
  v_n_giving integer;
  v_participants integer;
  v_rows integer;
begin
  select * into v_period from public.seva_mala_periods
  where id = p_period_id
  for update;

  if v_period.id is null then
    raise exception 'That Seva Mala period could not be found.';
  end if;
  if v_period.frozen_at is not null then
    return 0;
  end if;

  v_today := public.seva_mala_today();
  v_from := v_period.starts_on;
  v_to := least(v_period.ends_on, v_today);
  if v_to < v_from then
    return 0;
  end if;

  v_beta := public.seva_mala_number('seva_mala.balance_beta', 0.5);
  v_alpha := public.seva_mala_number('seva_mala.soft_cap_alpha', 0.15);
  v_quantile := public.seva_mala_number('seva_mala.reference_quantile', 0.80);
  v_shrink := public.seva_mala_number('seva_mala.reference_shrink_k', 12);
  v_floor := public.seva_mala_number('seva_mala.reference_floor', 0.6931471805599453);
  v_trail_from := v_to - (public.seva_mala_number('seva_mala.trailing_days', 90)::integer - 1);

  -- Refused here as well as inside the two helpers, so a bad dial costs a
  -- period nothing rather than costing it a half-written rebuild.
  if v_beta is null or v_beta < 0 or v_beta > 1 then
    raise exception
      'seva_mala.balance_beta is %, which is outside [0, 1]. It is the weight on the smaller of a devotee''s two offerings.',
      v_beta;
  end if;
  if v_alpha is null or v_alpha < 0 or v_alpha > 1 then
    raise exception
      'seva_mala.soft_cap_alpha is %, which is outside [0, 1]. It is the weight on offering beyond the congregation''s reference.',
      v_alpha;
  end if;
  v_ceiling := public.seva_mala_norm_ceiling();

  -- -------------------------------------------------------------------------
  -- The units. One typical act, one typical gift, over the trailing window
  -- ending where this period ends — so a frozen September is measured in
  -- September's units and stays measured in them.
  --
  -- MEDIAN OF MEDIANS: the population statistic is taken over ONE VALUE PER
  -- PERSON, each devotee's own median act and each donor's own median gift,
  -- because the units are the only per-TRANSACTION statistic in the scoring and
  -- without this one donor splitting a gift fifty ways moves every u_g in the
  -- congregation. 0055 section 13 has the whole argument.
  -- -------------------------------------------------------------------------
  select percentile_cont(0.5) within group (order by per_devotee.typical)
  into v_unit_seva
  from (
    select percentile_cont(0.5) within group (order by acts.raw_minutes) as typical
    from public.seva_mala_acts() acts
    where acts.quality > 0
      and acts.occurred_on between v_trail_from and v_to
    group by acts.devotee_id
  ) per_devotee;

  v_unit_seva := coalesce(
    nullif(v_unit_seva, 0),
    public.seva_mala_number('seva_mala.seva_unit_fallback_minutes', 60)
  );

  select percentile_cont(0.5) within group (order by per_donor.typical)
  into v_unit_giving
  from (
    select percentile_cont(0.5) within group (order by donations.amount_cents::numeric)
             as typical
    from public.donations
    where donations.donor_id is not null
      and (donations.received_at at time zone 'America/Chicago')::date
          between v_trail_from and v_to
    group by donations.donor_id
  ) per_donor;

  v_unit_giving := coalesce(
    nullif(v_unit_giving, 0),
    public.seva_mala_number('seva_mala.giving_unit_fallback_cents', 2500)
  );

  -- -------------------------------------------------------------------------
  -- The totals. Points come from period TOTALS and never from a transaction,
  -- which is the whole of the anti-gaming answer to micro-donations.
  -- -------------------------------------------------------------------------
  delete from public.period_scores where period_id = v_period.id;

  insert into public.period_scores (
    period_id, devotee_id, credited_minutes, seva_minutes, seva_acts,
    giving_cents, gifts
  )
  select
    v_period.id,
    totals.devotee_id,
    round(totals.credited, 4),
    round(totals.weighted, 4),
    totals.acts,
    totals.cents,
    totals.gifts
  from (
    select
      coalesce(seva.devotee_id, giving.devotee_id) as devotee_id,
      coalesce(seva.credited, 0) as credited,
      coalesce(seva.weighted, 0) as weighted,
      coalesce(seva.acts, 0) as acts,
      coalesce(giving.cents, 0) as cents,
      coalesce(giving.gifts, 0) as gifts
    from (
      select
        acts.devotee_id,
        sum(acts.credited_minutes) as credited,
        sum(acts.weighted_minutes) as weighted,
        count(*)::integer as acts
      from public.seva_mala_acts() acts
      where acts.quality > 0
        and acts.occurred_on between v_from and v_to
      group by acts.devotee_id
    ) seva
    full outer join (
      select
        donations.donor_id as devotee_id,
        sum(donations.amount_cents)::bigint as cents,
        count(*)::integer as gifts
      from public.donations
      where donations.donor_id is not null
        and (donations.received_at at time zone 'America/Chicago')::date
            between v_from and v_to
      group by donations.donor_id
    ) giving on giving.devotee_id = seva.devotee_id
  ) totals
  join public.users on users.id = totals.devotee_id
  where totals.weighted > 0 or totals.cents > 0;

  get diagnostics v_rows = row_count;
  v_participants := v_rows;

  -- -------------------------------------------------------------------------
  -- Compression.
  -- -------------------------------------------------------------------------
  update public.period_scores
  set seva_utility = round(ln(1 + period_scores.seva_minutes / v_unit_seva), 10),
      giving_utility = round(ln(1 + period_scores.giving_cents::numeric / v_unit_giving), 10)
  where period_scores.period_id = v_period.id;

  -- -------------------------------------------------------------------------
  -- The references. Percentile of the congregation, per dimension, among the
  -- devotees active IN THAT DIMENSION — a temple where a fifth of people give
  -- must not have its giving reference dragged to zero by the four fifths who
  -- serve instead. Shrunk toward the trailing figure by n against k, then
  -- floored.
  --
  -- This is what "it depends on the devotees, not hardcoded" is, mechanically,
  -- and the soft cap does not weaken it by one line: alpha decides how steeply
  -- the ground rises AFTER this number, and this number is still the
  -- congregation's own.
  -- -------------------------------------------------------------------------
  select
    percentile_cont(v_quantile) within group (order by scores.seva_utility),
    count(*)::integer
  into v_ref_seva_period, v_n_seva
  from public.period_scores scores
  where scores.period_id = v_period.id and scores.seva_minutes > 0;

  select
    percentile_cont(v_quantile) within group (order by scores.giving_utility),
    count(*)::integer
  into v_ref_giving_period, v_n_giving
  from public.period_scores scores
  where scores.period_id = v_period.id and scores.giving_cents > 0;

  select percentile_cont(v_quantile) within group (
           order by ln(1 + trail.weighted / v_unit_seva)
         )
  into v_ref_seva_trail
  from (
    select acts.devotee_id, sum(acts.weighted_minutes) as weighted
    from public.seva_mala_acts() acts
    where acts.quality > 0 and acts.occurred_on between v_trail_from and v_to
    group by acts.devotee_id
    having sum(acts.weighted_minutes) > 0
  ) trail;

  select percentile_cont(v_quantile) within group (
           order by ln(1 + trail.cents / v_unit_giving)
         )
  into v_ref_giving_trail
  from (
    select donations.donor_id, sum(donations.amount_cents)::numeric as cents
    from public.donations
    where donations.donor_id is not null
      and (donations.received_at at time zone 'America/Chicago')::date
          between v_trail_from and v_to
    group by donations.donor_id
  ) trail;

  v_ref_seva := greatest(
    v_floor,
    case
      when v_ref_seva_period is null and v_ref_seva_trail is null then v_floor
      when v_ref_seva_trail is null then v_ref_seva_period
      when v_ref_seva_period is null then v_ref_seva_trail
      else (coalesce(v_n_seva, 0) * v_ref_seva_period + v_shrink * v_ref_seva_trail)
           / (coalesce(v_n_seva, 0) + v_shrink)
    end
  );

  v_ref_giving := greatest(
    v_floor,
    case
      when v_ref_giving_period is null and v_ref_giving_trail is null then v_floor
      when v_ref_giving_trail is null then v_ref_giving_period
      when v_ref_giving_period is null then v_ref_giving_trail
      else (coalesce(v_n_giving, 0) * v_ref_giving_period + v_shrink * v_ref_giving_trail)
           / (coalesce(v_n_giving, 0) + v_shrink)
    end
  );

  -- -------------------------------------------------------------------------
  -- Scaling, softly capping, and the balance.
  --
  -- public.seva_mala_normalise is now the load-bearing expression: below the
  -- congregation's generous end it is the ratio 0055 always computed, and above
  -- it the ground rises at alpha and stops at 1 + beta. What it protects is
  -- what least(1.0, ...) protected — that no single gift can carry anybody past
  -- a devotee who gave both their hands and their means — and section 2 is the
  -- arithmetic of why the ceiling is where it is.
  -- -------------------------------------------------------------------------
  update public.period_scores
  set seva_norm = public.seva_mala_normalise(
        period_scores.seva_utility, v_ref_seva, v_alpha, v_ceiling),
      giving_norm = public.seva_mala_normalise(
        period_scores.giving_utility, v_ref_giving, v_alpha, v_ceiling),
      computed_at = now()
  where period_scores.period_id = v_period.id;

  update public.period_scores
  set score = public.seva_mala_score(
        period_scores.seva_norm, period_scores.giving_norm, v_beta)
  where period_scores.period_id = v_period.id;

  update public.seva_mala_periods
  set seva_reference = round(v_ref_seva, 10),
      giving_reference = round(v_ref_giving, 10),
      seva_unit_minutes = round(v_unit_seva, 4),
      giving_unit_cents = round(v_unit_giving, 4),
      participant_count = v_participants,
      computed_at = now(),
      -- Freeze on close, and only on close.
      frozen_at = case when v_period.ends_on < v_today then now() end
  where seva_mala_periods.id = v_period.id;

  perform public.award_seva_mala_for_period(v_period.id);

  return v_participants;
end;
$$;

comment on function public.recompute_seva_mala_period(uuid) is
  'Rebuilds one period from the facts: units, totals, compression, congregation-relative references, the soft cap and the balance. Offering beyond the reference still counts, at alpha per log, up to a ceiling of 1 + beta. Frozen periods are left alone.';

revoke all on function public.recompute_seva_mala_period(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 6. Showing the working, including the two numbers that are new.
--
--    explain_my_score is the one place s-hat, g-hat and the references ever
--    leave the database, and it exists so that a devotee can check the
--    arithmetic rather than being asked to trust it. Without alpha and the
--    ceiling that is no longer possible: given u_s and ref_s a devotee could
--    re-derive s-hat under 0055's rule and cannot under this one.
--
--    Two columns added, so the whole function is dropped and recreated — `create
--    or replace` cannot change a return shape. It is still strictly about the
--    caller: no parameter for whose score to explain, and auth.uid() is the only
--    devotee it will answer about.
-- ---------------------------------------------------------------------------

drop function if exists public.explain_my_score(uuid);

create function public.explain_my_score(p_period_id uuid)
returns table (
  period_kind text,
  period_start date,
  period_end date,
  seva_unit_minutes numeric,
  giving_unit_cents numeric,
  minutes_served numeric,
  minutes_lost_to_caps numeric,
  credited_minutes numeric,
  weighted_seva_minutes numeric,
  seva_acts integer,
  giving_cents bigint,
  gifts integer,
  seva_utility numeric,
  giving_utility numeric,
  seva_reference numeric,
  giving_reference numeric,
  seva_norm numeric,
  giving_norm numeric,
  balance_beta numeric,
  soft_cap_alpha numeric,
  norm_ceiling numeric,
  score numeric,
  participant_count integer
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    periods.period_kind,
    periods.starts_on,
    periods.ends_on,
    periods.seva_unit_minutes,
    periods.giving_unit_cents,
    coalesce(mine.served, 0),
    coalesce(mine.served, 0) - scores.credited_minutes,
    scores.credited_minutes,
    scores.seva_minutes,
    scores.seva_acts,
    scores.giving_cents,
    scores.gifts,
    scores.seva_utility,
    scores.giving_utility,
    periods.seva_reference,
    periods.giving_reference,
    scores.seva_norm,
    scores.giving_norm,
    public.seva_mala_number('seva_mala.balance_beta', 0.5),
    public.seva_mala_number('seva_mala.soft_cap_alpha', 0.15),
    public.seva_mala_norm_ceiling(),
    scores.score,
    periods.participant_count
  from public.period_scores scores
  join public.seva_mala_periods periods on periods.id = scores.period_id
  left join lateral (
    select sum(acts.raw_minutes) as served
    from public.seva_mala_acts(auth.uid()) acts
    where acts.quality > 0
      and acts.occurred_on between periods.starts_on and periods.ends_on
  ) mine on true
  where auth.uid() is not null
    and scores.period_id = p_period_id
    and scores.devotee_id = auth.uid()
$$;

comment on function public.explain_my_score(uuid) is
  'The whole arithmetic behind your own score for one period: the units, the congregation''s references, your two norms and every dial they were computed with. balance_beta is the weight your SMALLER offering carried beside your larger one; soft_cap_alpha is what each doubling beyond the congregation''s reference was worth; norm_ceiling is where that stops. Only ever your own.';

revoke all on function public.explain_my_score(uuid) from public, anon;
grant execute on function public.explain_my_score(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 7. What a window is worth, and how it splits.
--
--    The engine under both pairs of functions in sections 8 and 9, and the only
--    place the split is computed, so a devotee's seva list and their giving
--    list can never disagree about what their points were.
--
--    It takes a devotee id and is therefore revoked from every client role: the
--    two public pairs pass auth.uid() or check app.view_all, and there is no
--    third way in.
--
--    THE SCALE. The narrowest computed period that wholly contains the window.
--    A window inside this week is priced in this week's units and against this
--    week's references; a ninety-day window is priced against the lifetime's.
--    is_whole_period says whether the window is the whole of the period it was
--    priced against, which is the flag a client needs to decide between "this is
--    your week" and "this is what these days are worth".
--
--    THE ARITHMETIC IS THE RECOMPUTE'S, line for line: the same helper, the same
--    quality filter, the same rounding at four places before the logarithm and
--    ten places after it, the same normalise, the same score. That is not
--    tidiness — it is what makes total_points equal the board's number exactly
--    when the window is the whole period, and the verification asserts it.
--
--    THE SPLIT IS EXACT. score * (1 + beta) = max + beta*min, and each of those
--    two terms belongs to one dimension. seva_points is rounded first and
--    giving_points takes the remainder, so the two always add to total_points —
--    one rule, running-total rounding, used again inside each dimension in the
--    sections below.
-- ---------------------------------------------------------------------------

create or replace function public.seva_mala_window_points(
  p_devotee_id uuid,
  p_from date,
  p_to date
)
returns table (
  window_from date,
  window_to date,
  scaled_against text,
  period_id uuid,
  is_whole_period boolean,
  unit_minutes numeric,
  unit_cents numeric,
  seva_scale numeric,
  giving_scale numeric,
  seva_minutes numeric,
  giving_cents bigint,
  seva_standing numeric,
  giving_standing numeric,
  score numeric,
  seva_points integer,
  giving_points integer,
  total_points integer
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_today date := public.seva_mala_today();
  v_from date := coalesce(p_from, v_today - 89);
  v_to date := coalesce(p_to, v_today);
  v_period public.seva_mala_periods;
  v_beta numeric := public.seva_mala_number('seva_mala.balance_beta', 0.5);
  v_alpha numeric := public.seva_mala_number('seva_mala.soft_cap_alpha', 0.15);
  v_ceiling numeric := public.seva_mala_norm_ceiling();
  v_minutes numeric;
  v_cents bigint;
  v_seva numeric;
  v_giving numeric;
  v_score numeric;
  v_seva_part numeric;
  v_total integer;
  v_seva_points integer;
begin
  -- The null guard is here AND in every caller, deliberately. Neither is
  -- redundant with the other in the way that matters: seva_mala_acts reads a
  -- null argument as "the whole congregation", so if this guard alone were
  -- lost, a caller that had also lost its own would total the temple's entire
  -- history into one devotee's points. The verification mutates each of them
  -- alone (masked, which is what defence in depth looks like) and then both
  -- together, which is caught.
  if p_devotee_id is null or v_to < v_from then
    return;
  end if;

  -- The narrowest computed period that wholly contains the window. A period
  -- that has never been computed carries null units and null references and
  -- would price the window against nothing at all, so it is not a candidate.
  select * into v_period
  from public.seva_mala_periods periods
  where periods.starts_on <= v_from
    and periods.ends_on >= v_to
    and periods.computed_at is not null
    and periods.seva_reference is not null
    and periods.giving_reference is not null
  order by case periods.period_kind
             when 'week' then 1 when 'month' then 2 else 3
           end,
           periods.starts_on desc
  limit 1;

  if v_period.id is null then
    return;
  end if;

  -- The recompute's totals, over the window instead of over the period.
  select round(coalesce(sum(acts.weighted_minutes), 0), 4)
  into v_minutes
  from public.seva_mala_acts(p_devotee_id) acts
  where acts.quality > 0
    and acts.occurred_on between v_from and v_to;

  select coalesce(sum(donations.amount_cents), 0)::bigint
  into v_cents
  from public.donations
  where donations.donor_id = p_devotee_id
    and (donations.received_at at time zone 'America/Chicago')::date
        between v_from and v_to;

  v_seva := public.seva_mala_normalise(
    round(ln(1 + v_minutes / v_period.seva_unit_minutes), 10),
    v_period.seva_reference, v_alpha, v_ceiling);
  v_giving := public.seva_mala_normalise(
    round(ln(1 + v_cents::numeric / v_period.giving_unit_cents), 10),
    v_period.giving_reference, v_alpha, v_ceiling);

  v_score := public.seva_mala_score(v_seva, v_giving, v_beta);

  -- The larger offering counts whole and the smaller for beta of itself, so the
  -- score is already a sum of exactly two terms and this is a split rather than
  -- an estimate. Ties go to seva, deterministically, because at a tie the two
  -- terms are equal and it makes no difference which is called which.
  v_seva_part := case
    when v_seva >= v_giving then v_seva / (1 + v_beta)
    else v_beta * v_seva / (1 + v_beta)
  end;

  v_total := round(v_score * 1000)::integer;
  v_seva_points := round(v_seva_part * 1000)::integer;

  return query select
    v_from,
    v_to,
    v_period.period_kind,
    v_period.id,
    v_from <= v_period.starts_on and v_to >= least(v_period.ends_on, v_today),
    v_period.seva_unit_minutes,
    v_period.giving_unit_cents,
    v_period.seva_reference,
    v_period.giving_reference,
    v_minutes,
    v_cents,
    v_seva,
    v_giving,
    v_score,
    v_seva_points,
    v_total - v_seva_points,
    v_total;
end;
$$;

comment on function public.seva_mala_window_points(uuid, date, date) is
  'What one devotee''s window of days is worth in Seva Mala points, and how those points split between seva and giving. Priced against the narrowest computed period that contains the window, with the recompute''s own arithmetic, so that a window which is a whole period comes to exactly the board''s number. Backend only: it takes a devotee id.';

revoke all on function public.seva_mala_window_points(uuid, date, date)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 8. The sentence the client must not have to invent.
--
--    A per-act figure is an attribution and not an addend, and a screen that
--    shows "12 points" beside an act without saying what kind of number that is
--    will be read as "this act was worth 12 points on its own". It was not. So
--    the explanation travels with the rows, in the rows, and every client that
--    renders the list renders the same words.
--
--    Immutable, granted, and a function rather than a literal in two places, so
--    that the seva list and the giving list cannot come to say different things.
-- ---------------------------------------------------------------------------

create or replace function public.seva_mala_attribution_note(
  p_dimension text,
  p_from date,
  p_to date,
  p_scaled_against text,
  p_is_whole_period boolean
)
returns text
language sql
immutable
set search_path = ''
as $$
  select format(
    'These are shares of your %s points for %s to %s, in proportion to %s. They are not what each %s was worth on its own: your total is compressed by a logarithm and then scaled against what this congregation actually did, so the more you have already %s, the less each further one adds. Seva and giving then combine without adding up — the larger of the two counts whole and the smaller counts for a fraction of itself — so these are one part of your points and not all of them. %s',
    case p_dimension when 'seva' then 'seva' else 'giving' end,
    to_char(p_from, 'FMDD FMMon YYYY'),
    to_char(p_to, 'FMDD FMMon YYYY'),
    case p_dimension
      when 'seva' then 'the credited minutes of each act, after quality, scarcity and the daily and weekly caps'
      else 'the amount of each gift'
    end,
    case p_dimension when 'seva' then 'act' else 'gift' end,
    case p_dimension when 'seva' then 'served' else 'given' end,
    case
      when coalesce(p_is_whole_period, false) then
        format('This window is the whole of the %s the board is showing, so these add up to exactly the points beside your name.',
               coalesce(p_scaled_against, 'period'))
      else
        format('This window is only part of the %s it is measured against, so these add up to what these days are worth on that scale rather than to the points beside your name.',
               coalesce(p_scaled_against, 'period'))
    end
  )
$$;

comment on function public.seva_mala_attribution_note(text, date, date, text, boolean) is
  'The sentence that travels with a per-act or per-gift points list, saying that the figures are shares of a non-linear total rather than what each act or gift earned on its own. One function so the two lists cannot come to say different things.';

revoke all on function public.seva_mala_attribution_note(text, date, date, text, boolean)
  from public, anon;
grant execute on function public.seva_mala_attribution_note(text, date, date, text, boolean)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 9. Every act of seva, with the points it accounts for.
--
--    Every act in the window, including the ones that earned nothing — a seva
--    marked absent is listed with a share of zero, a points figure of zero and
--    the reason in words, because "why didn't Tuesday count" is the question
--    this screen exists to answer and hiding the row answers it worst.
--
--    share is the exact ratio and points is the apportioned integer. The
--    integers are made by running total — round(P * cum_n) - round(P * cum_n-1)
--    — so they are whole numbers that sum to seva_points EXACTLY, with no
--    remainder hiding in the last row. A devotee adding up the column gets the
--    number the column header says.
--
--    No devotee argument. Same reasoning as my_donation_totals in 0061: an
--    argument that could name a devotee is an argument somebody will eventually
--    pass somebody else's id to, so there is nothing to pass.
-- ---------------------------------------------------------------------------

drop function if exists public.my_seva_act_points(date, date);

create function public.my_seva_act_points(
  p_from date default null,
  p_to date default null
)
returns table (
  assignment_id uuid,
  service_instance_id uuid,
  seva_name text,
  occurred_on date,
  weekday text,
  started_at_local time,
  minutes numeric,
  credited_minutes numeric,
  counted_minutes numeric,
  points_status text,
  points_note text,
  share numeric,
  points integer,
  seva_points integer,
  giving_points integer,
  total_points integer,
  window_from date,
  window_to date,
  scaled_against text,
  is_whole_period boolean,
  attribution text
)
language sql
stable
security definer
set search_path = ''
as $$
  with window_points as (
    select * from public.seva_mala_window_points(
      auth.uid(),
      coalesce(p_from, public.seva_mala_today() - 89),
      coalesce(p_to, public.seva_mala_today())
    )
  ),
  acts as (
    select
      acts.assignment_id,
      acts.service_instance_id,
      acts.seva_name,
      acts.occurred_on,
      acts.started_at_local,
      acts.raw_minutes,
      acts.credited_minutes,
      -- What actually entered the logarithm for this act.
      case when acts.quality > 0 then acts.weighted_minutes else 0 end as counted,
      acts.points_status
    from public.seva_mala_acts(auth.uid()) acts
    where auth.uid() is not null
      and acts.occurred_on between
        coalesce(p_from, public.seva_mala_today() - 89)
        and coalesce(p_to, public.seva_mala_today())
  ),
  ordered as (
    select
      acts.*,
      sum(acts.counted) over () as total_counted,
      sum(acts.counted) over (
        order by acts.occurred_on, acts.started_at_local, acts.assignment_id
        rows between unbounded preceding and current row
      ) as running_counted
    from acts
  ),
  apportioned as (
    select
      ordered.*,
      window_points.seva_points,
      -- Running-total rounding: the difference of two rounded cumulative
      -- figures is a whole number, and the last one is round(P) exactly.
      round(
        window_points.seva_points
        * (ordered.running_counted / nullif(ordered.total_counted, 0))
      ) as cumulative_points,
      round(
        window_points.seva_points
        * ((ordered.running_counted - ordered.counted)
           / nullif(ordered.total_counted, 0))
      ) as previous_points,
      window_points.giving_points,
      window_points.total_points,
      window_points.window_from,
      window_points.window_to,
      window_points.scaled_against,
      window_points.is_whole_period
    from ordered cross join window_points
  )
  select
    apportioned.assignment_id,
    apportioned.service_instance_id,
    apportioned.seva_name,
    apportioned.occurred_on,
    trim(to_char(apportioned.occurred_on, 'FMDay')),
    apportioned.started_at_local,
    apportioned.raw_minutes,
    apportioned.credited_minutes,
    apportioned.counted,
    apportioned.points_status,
    public.seva_points_note(apportioned.points_status),
    round(coalesce(apportioned.counted / nullif(apportioned.total_counted, 0), 0), 6),
    coalesce(apportioned.cumulative_points - apportioned.previous_points, 0)::integer,
    apportioned.seva_points,
    apportioned.giving_points,
    apportioned.total_points,
    apportioned.window_from,
    apportioned.window_to,
    apportioned.scaled_against,
    apportioned.is_whole_period,
    public.seva_mala_attribution_note(
      'seva', apportioned.window_from, apportioned.window_to,
      apportioned.scaled_against, apportioned.is_whole_period)
  from apportioned
  order by apportioned.occurred_on desc, apportioned.started_at_local desc,
           apportioned.seva_name
$$;

comment on function public.my_seva_act_points(date, date) is
  'Your own seva act by act with the Seva Mala points each one accounts for: its share of your seva points for the window, in proportion to the minutes that actually entered the score. Shares, not addends — the total is a logarithm scaled against the congregation, and the attribution column says so. The rows sum to seva_points exactly. Only ever your own.';

revoke all on function public.my_seva_act_points(date, date) from public, anon;
grant execute on function public.my_seva_act_points(date, date) to authenticated;

-- One devotee's, for whoever may see everything. 0061 section 8's rule: the
-- same shape column for column, app.view_all, an explicit refusal of a null id
-- because seva_mala_acts reads a null as "everybody", and an EMPTY SET rather
-- than an exception for anybody else, because this backs a screen.
drop function if exists public.list_devotee_seva_act_points(uuid, date, date);

create function public.list_devotee_seva_act_points(
  p_devotee_id uuid,
  p_from date default null,
  p_to date default null
)
returns table (
  assignment_id uuid,
  service_instance_id uuid,
  seva_name text,
  occurred_on date,
  weekday text,
  started_at_local time,
  minutes numeric,
  credited_minutes numeric,
  counted_minutes numeric,
  points_status text,
  points_note text,
  share numeric,
  points integer,
  seva_points integer,
  giving_points integer,
  total_points integer,
  window_from date,
  window_to date,
  scaled_against text,
  is_whole_period boolean,
  attribution text
)
language sql
stable
security definer
set search_path = ''
as $$
  with allowed as (
    select p_devotee_id as devotee_id
    where auth.uid() is not null
      and p_devotee_id is not null
      and public.has_permission('app.view_all')
  ),
  window_points as (
    select points.*
    from allowed
    cross join lateral public.seva_mala_window_points(
      allowed.devotee_id,
      coalesce(p_from, public.seva_mala_today() - 89),
      coalesce(p_to, public.seva_mala_today())
    ) points
  ),
  acts as (
    select
      acts.assignment_id,
      acts.service_instance_id,
      acts.seva_name,
      acts.occurred_on,
      acts.started_at_local,
      acts.raw_minutes,
      acts.credited_minutes,
      case when acts.quality > 0 then acts.weighted_minutes else 0 end as counted,
      acts.points_status
    from allowed
    cross join lateral public.seva_mala_acts(allowed.devotee_id) acts
    where acts.occurred_on between
      coalesce(p_from, public.seva_mala_today() - 89)
      and coalesce(p_to, public.seva_mala_today())
  ),
  ordered as (
    select
      acts.*,
      sum(acts.counted) over () as total_counted,
      sum(acts.counted) over (
        order by acts.occurred_on, acts.started_at_local, acts.assignment_id
        rows between unbounded preceding and current row
      ) as running_counted
    from acts
  ),
  apportioned as (
    select
      ordered.*,
      window_points.seva_points,
      round(
        window_points.seva_points
        * (ordered.running_counted / nullif(ordered.total_counted, 0))
      ) as cumulative_points,
      round(
        window_points.seva_points
        * ((ordered.running_counted - ordered.counted)
           / nullif(ordered.total_counted, 0))
      ) as previous_points,
      window_points.giving_points,
      window_points.total_points,
      window_points.window_from,
      window_points.window_to,
      window_points.scaled_against,
      window_points.is_whole_period
    from ordered cross join window_points
  )
  select
    apportioned.assignment_id,
    apportioned.service_instance_id,
    apportioned.seva_name,
    apportioned.occurred_on,
    trim(to_char(apportioned.occurred_on, 'FMDay')),
    apportioned.started_at_local,
    apportioned.raw_minutes,
    apportioned.credited_minutes,
    apportioned.counted,
    apportioned.points_status,
    public.seva_points_note(apportioned.points_status),
    round(coalesce(apportioned.counted / nullif(apportioned.total_counted, 0), 0), 6),
    coalesce(apportioned.cumulative_points - apportioned.previous_points, 0)::integer,
    apportioned.seva_points,
    apportioned.giving_points,
    apportioned.total_points,
    apportioned.window_from,
    apportioned.window_to,
    apportioned.scaled_against,
    apportioned.is_whole_period,
    public.seva_mala_attribution_note(
      'seva', apportioned.window_from, apportioned.window_to,
      apportioned.scaled_against, apportioned.is_whole_period)
  from apportioned
  order by apportioned.occurred_on desc, apportioned.started_at_local desc,
           apportioned.seva_name
$$;

comment on function public.list_devotee_seva_act_points(uuid, date, date) is
  'One devotee''s seva act by act with the points each accounts for, in the same shape my_seva_act_points returns for the caller''s own. President and Tech Admin only; empty for everybody else, because this backs a screen.';

revoke all on function public.list_devotee_seva_act_points(uuid, date, date) from public, anon;
grant execute on function public.list_devotee_seva_act_points(uuid, date, date) to authenticated;

-- ---------------------------------------------------------------------------
-- 10. Every gift, with the points it accounts for.
--
--     The same scheme on the other side: a gift's share is its cents over the
--     window's cents, apportioned by running total, summing to giving_points
--     exactly.
--
--     amount_cents is returned because it is the caller's own giving and they
--     may already read it — public.donations' row level security is what says
--     so, and this function does not widen it by a row. The President's variant
--     is app.view_all, who may already read every donation in the temple.
-- ---------------------------------------------------------------------------

drop function if exists public.my_giving_points(date, date);

create function public.my_giving_points(
  p_from date default null,
  p_to date default null
)
returns table (
  donation_id uuid,
  received_on date,
  weekday text,
  amount_cents integer,
  currency text,
  kind text,
  recurrence text,
  sponsorship_type_name text,
  share numeric,
  points integer,
  seva_points integer,
  giving_points integer,
  total_points integer,
  window_from date,
  window_to date,
  scaled_against text,
  is_whole_period boolean,
  attribution text
)
language sql
stable
security definer
set search_path = ''
as $$
  with window_points as (
    select * from public.seva_mala_window_points(
      auth.uid(),
      coalesce(p_from, public.seva_mala_today() - 89),
      coalesce(p_to, public.seva_mala_today())
    )
  ),
  gifts as (
    select
      donations.id as donation_id,
      (donations.received_at at time zone 'America/Chicago')::date as received_on,
      donations.received_at,
      donations.amount_cents,
      donations.currency,
      donations.kind,
      donations.recurrence,
      types.name as sponsorship_type_name
    from public.donations
    left join public.sponsorship_bookings bookings
      on bookings.id = donations.sponsorship_booking_id
    left join public.sponsorship_types types
      on types.id = bookings.sponsorship_type_id
    where auth.uid() is not null
      and donations.donor_id = auth.uid()
      and (donations.received_at at time zone 'America/Chicago')::date between
        coalesce(p_from, public.seva_mala_today() - 89)
        and coalesce(p_to, public.seva_mala_today())
  ),
  ordered as (
    select
      gifts.*,
      sum(gifts.amount_cents) over ()::numeric as total_cents,
      sum(gifts.amount_cents) over (
        order by gifts.received_at, gifts.donation_id
        rows between unbounded preceding and current row
      )::numeric as running_cents
    from gifts
  ),
  apportioned as (
    select
      ordered.*,
      window_points.giving_points,
      round(
        window_points.giving_points
        * (ordered.running_cents / nullif(ordered.total_cents, 0))
      ) as cumulative_points,
      round(
        window_points.giving_points
        * ((ordered.running_cents - ordered.amount_cents)
           / nullif(ordered.total_cents, 0))
      ) as previous_points,
      window_points.seva_points,
      window_points.total_points,
      window_points.window_from,
      window_points.window_to,
      window_points.scaled_against,
      window_points.is_whole_period
    from ordered cross join window_points
  )
  select
    apportioned.donation_id,
    apportioned.received_on,
    trim(to_char(apportioned.received_on, 'FMDay')),
    apportioned.amount_cents,
    apportioned.currency,
    apportioned.kind,
    apportioned.recurrence,
    apportioned.sponsorship_type_name,
    round(coalesce(apportioned.amount_cents / nullif(apportioned.total_cents, 0), 0), 6),
    coalesce(apportioned.cumulative_points - apportioned.previous_points, 0)::integer,
    apportioned.seva_points,
    apportioned.giving_points,
    apportioned.total_points,
    apportioned.window_from,
    apportioned.window_to,
    apportioned.scaled_against,
    apportioned.is_whole_period,
    public.seva_mala_attribution_note(
      'giving', apportioned.window_from, apportioned.window_to,
      apportioned.scaled_against, apportioned.is_whole_period)
  from apportioned
  order by apportioned.received_at desc, apportioned.donation_id
$$;

comment on function public.my_giving_points(date, date) is
  'Your own giving gift by gift with the Seva Mala points each one accounts for: its share of your giving points for the window, in proportion to its amount. Shares, not addends. The rows sum to giving_points exactly. Cents are summed across currencies exactly as the board sums them. Only ever your own.';

revoke all on function public.my_giving_points(date, date) from public, anon;
grant execute on function public.my_giving_points(date, date) to authenticated;

drop function if exists public.list_devotee_giving_points(uuid, date, date);

create function public.list_devotee_giving_points(
  p_devotee_id uuid,
  p_from date default null,
  p_to date default null
)
returns table (
  donation_id uuid,
  received_on date,
  weekday text,
  amount_cents integer,
  currency text,
  kind text,
  recurrence text,
  sponsorship_type_name text,
  share numeric,
  points integer,
  seva_points integer,
  giving_points integer,
  total_points integer,
  window_from date,
  window_to date,
  scaled_against text,
  is_whole_period boolean,
  attribution text
)
language sql
stable
security definer
set search_path = ''
as $$
  with allowed as (
    select p_devotee_id as devotee_id
    where auth.uid() is not null
      and p_devotee_id is not null
      and public.has_permission('app.view_all')
  ),
  window_points as (
    select points.*
    from allowed
    cross join lateral public.seva_mala_window_points(
      allowed.devotee_id,
      coalesce(p_from, public.seva_mala_today() - 89),
      coalesce(p_to, public.seva_mala_today())
    ) points
  ),
  gifts as (
    select
      donations.id as donation_id,
      (donations.received_at at time zone 'America/Chicago')::date as received_on,
      donations.received_at,
      donations.amount_cents,
      donations.currency,
      donations.kind,
      donations.recurrence,
      types.name as sponsorship_type_name
    from allowed
    join public.donations on donations.donor_id = allowed.devotee_id
    left join public.sponsorship_bookings bookings
      on bookings.id = donations.sponsorship_booking_id
    left join public.sponsorship_types types
      on types.id = bookings.sponsorship_type_id
    where (donations.received_at at time zone 'America/Chicago')::date between
      coalesce(p_from, public.seva_mala_today() - 89)
      and coalesce(p_to, public.seva_mala_today())
  ),
  ordered as (
    select
      gifts.*,
      sum(gifts.amount_cents) over ()::numeric as total_cents,
      sum(gifts.amount_cents) over (
        order by gifts.received_at, gifts.donation_id
        rows between unbounded preceding and current row
      )::numeric as running_cents
    from gifts
  ),
  apportioned as (
    select
      ordered.*,
      window_points.giving_points,
      round(
        window_points.giving_points
        * (ordered.running_cents / nullif(ordered.total_cents, 0))
      ) as cumulative_points,
      round(
        window_points.giving_points
        * ((ordered.running_cents - ordered.amount_cents)
           / nullif(ordered.total_cents, 0))
      ) as previous_points,
      window_points.seva_points,
      window_points.total_points,
      window_points.window_from,
      window_points.window_to,
      window_points.scaled_against,
      window_points.is_whole_period
    from ordered cross join window_points
  )
  select
    apportioned.donation_id,
    apportioned.received_on,
    trim(to_char(apportioned.received_on, 'FMDay')),
    apportioned.amount_cents,
    apportioned.currency,
    apportioned.kind,
    apportioned.recurrence,
    apportioned.sponsorship_type_name,
    round(coalesce(apportioned.amount_cents / nullif(apportioned.total_cents, 0), 0), 6),
    coalesce(apportioned.cumulative_points - apportioned.previous_points, 0)::integer,
    apportioned.seva_points,
    apportioned.giving_points,
    apportioned.total_points,
    apportioned.window_from,
    apportioned.window_to,
    apportioned.scaled_against,
    apportioned.is_whole_period,
    public.seva_mala_attribution_note(
      'giving', apportioned.window_from, apportioned.window_to,
      apportioned.scaled_against, apportioned.is_whole_period)
  from apportioned
  order by apportioned.received_at desc, apportioned.donation_id
$$;

comment on function public.list_devotee_giving_points(uuid, date, date) is
  'One devotee''s giving gift by gift with the points each accounts for, in the same shape my_giving_points returns for the caller''s own. President and Tech Admin only; empty for everybody else.';

revoke all on function public.list_devotee_giving_points(uuid, date, date) from public, anon;
grant execute on function public.list_devotee_giving_points(uuid, date, date) to authenticated;

-- ---------------------------------------------------------------------------
-- 11. What this migration deliberately does NOT do.
--
--     It does not recompute. The nightly job at ten past midnight Chicago
--     rebuilds every open period under the new rule without being asked.
--     Calling recompute_seva_mala() from here would also ensure last week's and
--     last month's periods and then freeze them, and on a database being built
--     from these migrations that would freeze two empty periods before any
--     facts existed. A migration must not decide that last week had nobody in
--     it. 0059 section 7 has the whole argument.
--
--     Scores already frozen stay frozen. A devotee who was second in a closed
--     September was second under September's rule and September's references,
--     and 0055's reason for writing the inputs down beside the outputs was so
--     that the answer to "why" survives a change like this one. What it means
--     in practice is that a frozen period's scores are all at or below 1.0 and a
--     live period's may be above it, which is a thing a client comparing two
--     periods should be told rather than left to discover.
-- ---------------------------------------------------------------------------

do $$
begin
  raise notice 'fair scaling applied';
end;
$$;
