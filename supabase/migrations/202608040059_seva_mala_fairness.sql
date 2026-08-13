-- Fairness: the balance rule inverted, and weekly seva that counts itself.
--
-- Two things the temple has said plainly since 0055 and 0057 shipped, and both
-- of them are corrections rather than additions.
--
-- ---------------------------------------------------------------------------
-- 1. The balance rule was backwards.
--
--    "Sometimes devotees don't donate but do seva a lot — they can be on top
--     too. Sometimes people donate so much but don't have time to do seva —
--     they can be on top too. Sometimes they donate less and do more seva —
--     they can be on top too. It depends on the devotees, not hardcoded. It
--     shouldn't be unfair to those who do more seva than donation, or more
--     donation than seva. Find some middle ground."
--
--    0055 scored (min(ŝ,ĝ) + β·max(ŝ,ĝ)) / (1 + β), which weights the SMALLER
--    of a devotee's two offerings fully and the larger only partially. With
--    β = 0.5 that puts a ceiling of 0.333 on any devotee who gives one thing
--    and not the other — a ceiling they cannot rise above by giving more of
--    the thing they give. Sixty hours of seva and six hundred both score 0.333
--    against a devotee who gave four hours and seventy-five dollars and scored
--    0.351. 0055's own verification asserted that as the feature. It is the
--    thing the temple has now asked to be removed.
--
--    So the two terms swap:
--
--        score = ( max(ŝ,ĝ) + β·min(ŝ,ĝ) ) / (1 + β)
--
--    The larger offering counts whole; the smaller counts for β of itself.
--    With β = 0.5:
--
--        top sevak, gives nothing      ŝ=1.0  ĝ=0.0   0.666667
--        top donor, no time to serve   ŝ=0.0  ĝ=1.0   0.666667   equal, exactly
--        top at both                   ŝ=1.0  ĝ=1.0   1.000000
--        moderate at both              ŝ=0.5  ĝ=0.5   0.500000
--        top seva and a little giving  ŝ=1.0  ĝ=0.3   0.766667
--
--    Which is the temple's sentence, arithmetically: excelling at either puts
--    you near the top, excelling at both wins outright, and neither path is
--    penalised for being the path it is. A devotee who serves and does not give
--    is no longer told, by a number, that two thirds of their standing was
--    withheld for something they were never asked for.
--
--    WHY β STAYS 0.5. Note first that this change could have been made without
--    touching the formula at all: (min + 2·max)/3 is the same function as
--    (max + 0.5·min)/1.5, so setting balance_beta to 2 would have produced
--    identical scores. It is written the other way round on purpose, because a
--    dial is only useful if a President can read it. Under this form β is the
--    weight on your SECOND string — how much the smaller of your two offerings
--    counts beside the larger — and it lives on [0, 1] where both ends mean
--    something:
--
--        β = 0    only your strongest dimension counts. Giving as well as
--                 serving would gain you nothing at all, so the temple's
--                 "excelling at both wins" is lost.
--        β = 0.5  the second string counts a half. A devotee who gives one
--                 thing wholly reaches two thirds; a devotee who gives both
--                 wholly reaches all of it. A 1.5× premium for the whole
--                 garland, and two thirds of the way for one string of it.
--        β = 1    the plain average. A single-dimension devotee tops out at
--                 exactly half of a two-dimension one — milder than 0.333, but
--                 the same complaint in a smaller voice.
--
--    0.5 is the midpoint of the range that is still a balance, it is the value
--    the temple already set and has never changed, and it needs no re-scoring
--    of anybody's history to keep. Anything above 1 would weight the smaller
--    offering MORE than the larger, which is the rule being inverted here
--    sneaking back in through the dial, so section 2 refuses it out loud.
--
--    Nothing else about the scoring moves. The log compression, the
--    congregation-relative P80 references, the shrinkage toward the trailing
--    quarter, the median-of-medians units and the cap at 1.0 are exactly what
--    make the score relative to what this congregation actually does rather
--    than to a number a developer typed, and the temple restated that as a
--    requirement in the same breath. They are untouched.
--
-- ---------------------------------------------------------------------------
-- 2. Weekly seva needs no verification.
--
--    "Weekly seva doesn't need any verification — use that when it completes
--     that day."
--
--    0057 required completed AND verified AND marked served for any act to earn
--    points, and 0057's own header flagged what that does to a roster: a
--    recurring instance is generated with posted_by null, so 202608040027's
--    authority leaves the President and the Tech Admin as the only two people
--    in the temple who can verify or confirm weekly seva. A congregation whose
--    seva is mostly weekly had put its entire points ledger on two screens.
--
--    So a RECURRING act — one on an instance generated from a service_templates
--    row, which is to say service_instances.template_id is not null — earns its
--    points when it is closed out on its day. No verification level is
--    required. No attendance confirmation is required. One-off seva keeps
--    0057's stricter rule, whole and unchanged, which is why the three-argument
--    seva_points_status survives here untouched and is still exactly that rule.
--
--    THE RULE, EXACTLY. For an act on a recurring instance:
--
--      not_served           assignment status is no_show or withdrawn, OR
--                           attendance is absent or excused
--      awaiting_completion  the assignment is not 'completed'
--      counted              otherwise — whatever the verification level, and
--                           whether or not anybody has marked attendance
--
--    awaiting_verification and awaiting_confirmation are unreachable for
--    recurring seva, which is the point: a weekly act that has completed reads
--    as counted rather than as waiting on somebody who was never going to come.
--
--    WHY ABSENT STILL ZEROES IT. Nobody having confirmed attendance and
--    somebody having recorded absence are not the same fact. The first is
--    silence, and the temple has said silence should not cost a devotee their
--    seva. The second is a coordinator saying out loud that the devotee was not
--    there, and it is the only evidence in the system that outranks the roster.
--    So absence, excusal, withdrawal and a recorded no-show all still zero the
--    act, and they are tested first, before completion is even looked at.
--
--    THE ABUSE SURFACE, STATED RATHER THAN GLOSSED. A devotee may close their
--    own assignment: complete_my_service_assignment (202608030007, hardened in
--    202608040019) is granted to authenticated and closes the caller's own row
--    once the seva has started. Under this rule that is enough to earn the
--    points. That is not an oversight, it is the temple's instruction, and what
--    bounds it is worth writing down because none of it is obvious:
--
--      * The roster is the gate. service_templates and
--        service_template_assignees are select-only to authenticated
--        (202608020003); every write goes through a definer RPC. A devotee can
--        put themselves on a weekly seva only through join_weekly_service, only
--        while the template is participation_mode 'open', and only into a slot
--        that is actually free. They cannot invent a weekly seva.
--      * The hours are the temple's, not the devotee's. A recurring instance
--        takes its duration_minutes from the template, which only a Community
--        Head or above can create. Closing your own roster slot claims the
--        slot's length and not a minute more.
--      * The caps still bind. Eight hours a Chicago day, thirty a week, and
--        0055's cap at ŝ = 1 means the marginal value of another claimed hour
--        falls away well before it could carry anybody.
--      * A coordinator can undo it with one word. record_seva_attendance
--        'absent' zeroes the act and notifies the devotee that it happened,
--        which is a conversation rather than a silent deduction.
--
--    What this does NOT do is award points for a roster slot nobody closed.
--    An open recurring instance whose day has passed still reads
--    awaiting_completion, and the President closing it is still one action per
--    instance — one, where 0057 needed three, and where two of the three had no
--    plausible actor at all.
--
-- Requires 202608040058_seva_balance.sql.

-- ---------------------------------------------------------------------------
-- 0. The ground this stands on.
--
--    Asserted rather than assumed. This migration rewrites the last line of the
--    scoring and the first line of the eligibility rule, and both of them are
--    read by files that were deployed before it existed.
-- ---------------------------------------------------------------------------

do $$
declare
  v_holders text;
  v_beta numeric;
begin
  if to_regprocedure('public.seva_mala_acts(uuid)') is null
    or to_regprocedure('public.seva_points_status(text, text, text)') is null
    or to_regprocedure('public.recompute_seva_mala_period(uuid)') is null
    or to_regprocedure('public.list_seva_awaiting_confirmation(date, date)') is null
  then
    raise exception
      'Seva Mala is not in place; apply 202608040055 and 202608040057 first.';
  end if;

  -- The three-argument rule is 0057's and stays 0057's: it is what one-off
  -- seva is still judged by, and section 4 delegates to it in as many words.
  -- If it has moved, the delegation below means something else.
  if public.seva_points_status('completed', 'served', 'member_verified') <> 'counted'
    or public.seva_points_status('completed', null, 'member_verified') <> 'awaiting_confirmation'
    or public.seva_points_status('completed', 'served', 'self_report') <> 'awaiting_verification'
    or public.seva_points_status('confirmed', 'served', 'qr_scan') <> 'awaiting_completion'
    or public.seva_points_status('completed', 'absent', 'qr_scan') <> 'not_served'
    or public.seva_points_status('no_show', 'served', 'qr_scan') <> 'not_served'
  then
    raise exception
      'public.seva_points_status(text, text, text) is no longer 202608040057''s rule for one-off seva.';
  end if;

  -- Recurrence is read off the instance and nowhere else.
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'service_instances'
      and column_name = 'template_id'
  ) then
    raise exception
      'public.service_instances has no template_id; there is nothing to call recurring.';
  end if;

  -- The dial the whole of section 1 is about.
  v_beta := public.seva_mala_number('seva_mala.balance_beta', 0.5);
  if v_beta is null or v_beta < 0 or v_beta > 1 then
    raise exception
      'seva_mala.balance_beta is %, which is outside [0, 1] and cannot be a weight on the smaller offering.',
      v_beta;
  end if;

  -- 0055 section 4, restated: the components stay unreadable. Nothing here may
  -- have widened that, and the new score helper must not become the crack.
  if has_table_privilege('authenticated', 'public.period_scores', 'select')
    or has_table_privilege('authenticated', 'public.seva_mala_periods', 'select')
    or has_table_privilege('authenticated', 'public.app_settings', 'select')
  then
    raise exception 'authenticated can read the Seva Mala components.';
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
-- 1. The dial, restated with its new meaning.
--
--    ON CONFLICT DO NOTHING, so this never stamps on a value the temple has
--    since changed — and so a temple that had already moved beta keeps whatever
--    it moved it to. The comment is the point of this block: the key is the
--    same key 0055 seeded and it now means the opposite end of the same
--    fraction, and the only place that can be written down is here.
-- ---------------------------------------------------------------------------

insert into public.app_settings (key, value)
values
  -- The weight on the SMALLER of a devotee's two offerings, beside a full
  -- weight on the larger:  score = (max + beta*min) / (1 + beta).
  --
  -- 0.5 means the second string of the garland counts a half. A devotee who
  -- gives one thing wholly and the other not at all reaches two thirds; a
  -- devotee who gives both wholly reaches all of it.
  --
  -- Lives on [0, 1]. 0 makes the second offering worth nothing, so doing both
  -- stops beating doing one. 1 is the plain average. Above 1 the smaller
  -- offering would outweigh the larger, which is the rule this migration
  -- inverted, and seva_mala_score refuses it rather than quietly scoring the
  -- whole congregation by a rule the temple rejected.
  ('seva_mala.balance_beta', '0.5')
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------
-- 2. The balance, in one function.
--
--    0055 wrote the formula inline in the last UPDATE of a three-hundred-line
--    recompute, which is why the only way to check it was to re-type it in a
--    verification script and hope. It is a named, pure, four-line function now:
--    one place to read, one place to change, one place to mutate when somebody
--    wants to know whether the tests would notice.
--
--    Immutable and granted to authenticated, deliberately. It reveals nothing —
--    it is arithmetic over two numbers the caller has to supply — and
--    explain_my_score exists so that a devotee can check the working rather
--    than be asked to trust it. A devotee who can read their own ŝ and ĝ should
--    be able to put them back through the same function the board used.
-- ---------------------------------------------------------------------------

create or replace function public.seva_mala_score(
  p_seva_norm numeric,
  p_giving_norm numeric,
  p_beta numeric
)
returns numeric
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_seva numeric := coalesce(p_seva_norm, 0);
  v_giving numeric := coalesce(p_giving_norm, 0);
begin
  if p_beta is null or p_beta < 0 or p_beta > 1 then
    raise exception
      'balance_beta is the weight on the SMALLER offering and must lie in [0, 1]; % would weight the smaller more than the larger, which is the rule the temple asked to be inverted.',
      p_beta;
  end if;

  -- The larger offering whole, the smaller for beta of itself. Rounded to six
  -- places before anything ranks it, so two devotees who are genuinely equal
  -- are stored as equal and share a place rather than being separated by the
  -- last bit of a numeric — which is exactly what a pure sevak and a pure donor
  -- now are.
  return round(
    (greatest(v_seva, v_giving) + p_beta * least(v_seva, v_giving)) / (1 + p_beta),
    6
  );
end;
$$;

comment on function public.seva_mala_score(numeric, numeric, numeric) is
  'One devotee''s Seva Mala score from their two capped offerings: the larger counts whole, the smaller counts for beta of itself. Excelling at either reaches (1+0)/(1+beta); excelling at both reaches 1.';

revoke all on function public.seva_mala_score(numeric, numeric, numeric) from public, anon;
grant execute on function public.seva_mala_score(numeric, numeric, numeric) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. The recompute, with the last line changed and nothing else.
--
--    Restated whole because that is what replacing a function means, and
--    reviewed line by line against 0055 section 13 so that "nothing else" is
--    true rather than hoped for. The units are still the median of medians, the
--    totals are still period totals, the compression is still ln(1 + x/unit),
--    the references are still the congregation's own eightieth percentile
--    shrunk toward the trailing quarter and floored at ln(2), the cap is still
--    least(1.0, ...), and a frozen period is still left alone.
--
--    Two changes, both in the last third:
--
--      * beta is checked against [0, 1] before anything is written, so a temple
--        that sets it to 2 gets an exception instead of a silent return to the
--        rule this migration inverted;
--      * the score comes from public.seva_mala_score.
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
  v_quantile := public.seva_mala_number('seva_mala.reference_quantile', 0.80);
  v_shrink := public.seva_mala_number('seva_mala.reference_shrink_k', 12);
  v_floor := public.seva_mala_number('seva_mala.reference_floor', 0.6931471805599453);
  v_trail_from := v_to - (public.seva_mala_number('seva_mala.trailing_days', 90)::integer - 1);

  -- Refused here as well as inside seva_mala_score, so a bad dial costs a
  -- period nothing rather than costing it a half-written rebuild.
  if v_beta is null or v_beta < 0 or v_beta > 1 then
    raise exception
      'seva_mala.balance_beta is %, which is outside [0, 1]. It is the weight on the smaller of a devotee''s two offerings.',
      v_beta;
  end if;

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
  -- This is what "it depends on the devotees, not hardcoded" is, mechanically.
  -- A devotee is at ŝ = 1 because of where the congregation's eightieth
  -- percentile sits this month, and it moves when the congregation moves.
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
  -- Scaling, capping, and the balance.
  --
  -- least(1, ...) is still the load-bearing expression: it is what stops a
  -- second enormous gift from buying anything, and under the inverted rule it
  -- is also what makes a pure sevak and a pure donor land on the same number
  -- rather than on two numbers that happen to be close.
  -- -------------------------------------------------------------------------
  update public.period_scores
  set seva_norm = round(least(1.0, period_scores.seva_utility / v_ref_seva), 6),
      giving_norm = round(least(1.0, period_scores.giving_utility / v_ref_giving), 6),
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
  'Rebuilds one period from the facts: units, totals, compression, references, cap and balance. The larger of a devotee''s two offerings counts whole and the smaller counts for beta of itself, so serving alone and giving alone both reach the same place near the top. Frozen periods are left alone.';

revoke all on function public.recompute_seva_mala_period(uuid) from public, anon, authenticated;

comment on function public.explain_my_score(uuid) is
  'The whole arithmetic behind your own score for one period, including the references it was scaled against and any minutes the daily or weekly cap held back. balance_beta is the weight your SMALLER offering carried beside your larger one: score = (max + beta*min) / (1 + beta). Only ever your own.';

-- ---------------------------------------------------------------------------
-- 4. The eligibility rule, told which kind of seva it is looking at.
--
--    A fourth argument rather than a changed one. The three-argument function
--    is 0057's rule and stays 0057's rule, word for word, because that is what
--    one-off seva is still judged by — and because 202608040058's ground check
--    and 0057's own verification both read it as exactly that. This overload
--    carries no default, so a three-argument call is never ambiguous and never
--    silently picks up a recurrence flag nobody passed.
--
--    A null recurrence flag is treated as NOT recurring: the stricter of the
--    two rules is the safe reading of "we do not know what kind of seva this
--    is", because it withholds points rather than handing them out.
--
--    The one-off branches below are 0057's branches unchanged, which is a
--    property the verification asserts over the whole eighty-cell cross product
--    rather than a claim made here.
-- ---------------------------------------------------------------------------

create or replace function public.seva_points_status(
  p_assignment_status text,
  p_attendance text,
  p_verification text,
  p_is_recurring boolean
)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    -- Terminal, and first for both kinds of seva. Somebody saying out loud that
    -- the devotee was not there outranks the roster, and it is the difference
    -- between silence and evidence. Nobody is waiting on anybody.
    when p_assignment_status in ('no_show', 'withdrawn') then 'not_served'
    when p_attendance in ('absent', 'excused') then 'not_served'

    -- Both kinds still have to be closed out. A roster slot on a day that has
    -- passed and that nobody has finished is not seva that happened.
    when p_assignment_status is distinct from 'completed' then 'awaiting_completion'

    -- Weekly seva: completed on its day, and nothing further is owed. No
    -- verification level, no attendance confirmation. This is the whole of the
    -- change, and everything above it is what keeps it honest.
    when coalesce(p_is_recurring, false) then 'counted'

    -- One-off seva, exactly as 202608040057 left it.
    when p_verification not in ('live_timer', 'qr_scan', 'member_verified')
      then 'awaiting_verification'
    when p_attendance is distinct from 'served' then 'awaiting_confirmation'
    else 'counted'
  end
$$;

comment on function public.seva_points_status(text, text, text, boolean) is
  'Whether one act of seva earned points, and if not, what is still owed. Weekly seva counts when it is completed on its day; one-off seva still needs completed, verified and served together. Being marked absent, excused, withdrawn or a no-show zeroes either kind.';

revoke all on function public.seva_points_status(text, text, text, boolean) from public, anon;
grant execute on function public.seva_points_status(text, text, text, boolean) to authenticated;

comment on function public.seva_points_status(text, text, text) is
  'The one-off rule, from 202608040057: completed, verified and served together, or nothing. Recurring seva is judged by the four-argument overload; anything that knows whether an act came from a template must pass that fourth argument rather than call this.';

-- ---------------------------------------------------------------------------
-- 5. Every act, re-judged.
--
--    0057 section 2 with one substitution: is_recurring was already being
--    computed for the return, and it is now also an input to the rule. The
--    return shape does not move, so this is a plain in-place replacement and no
--    overload can be left behind.
--
--    quality is NOT discounted for an unverified recurring act. Weighting
--    weekly seva at some fraction because nobody scanned a code would be
--    exactly the hidden penalty the temple asked to have removed, only spelled
--    with a decimal point instead of a zero. The 0.7 for a live timer nobody
--    switched off survives untouched, because that is a statement about how
--    well we know the LENGTH of an act and not about whether it happened.
-- ---------------------------------------------------------------------------

create or replace function public.seva_mala_acts(p_devotee_id uuid default null)
returns table (
  assignment_id uuid,
  devotee_id uuid,
  service_instance_id uuid,
  service_type_id uuid,
  seva_name text,
  occurred_on date,
  started_at_local time,
  planned_minutes integer,
  actual_minutes integer,
  raw_minutes numeric,
  quality numeric,
  weight numeric,
  day_factor numeric,
  week_factor numeric,
  credited_minutes numeric,
  weighted_minutes numeric,
  assignment_status text,
  verification text,
  attendance text,
  is_recurring boolean,
  points_status text
)
language sql
stable
security definer
set search_path = ''
as $$
  with caps as (
    select
      public.seva_mala_number('seva_mala.daily_cap_minutes', 480) as day_cap,
      public.seva_mala_number('seva_mala.weekly_cap_minutes', 1800) as week_cap
  ),
  base as (
    select
      assignments.id as assignment_id,
      assignments.devotee_id,
      instances.id as service_instance_id,
      instances.service_type_id,
      public.service_instance_name(instances) as seva_name,
      instances.date as occurred_on,
      instances.start_time as started_at_local,
      instances.duration_minutes as planned_minutes,
      coalesce(session.actual_minutes, verified.actual_minutes) as actual_minutes,
      assignments.status as assignment_status,
      assignments.verification,
      assignments.attendance,
      instances.template_id is not null as is_recurring,
      public.seva_points_status(
        assignments.status, assignments.attendance, assignments.verification,
        instances.template_id is not null
      ) as points_status,
      case
        when public.seva_points_status(
               assignments.status, assignments.attendance, assignments.verification,
               instances.template_id is not null
             ) <> 'counted' then 0
        when assignments.verification = 'live_timer'
          and coalesce(session.auto_completed, false) then 0.7
        else 1.0
      end::numeric as quality,
      coalesce(weights.weight, 1.0) as weight
    from public.service_assignments assignments
    join public.service_instances instances
      on instances.id = assignments.service_instance_id
    left join public.seva_type_weights weights
      on weights.service_type_id = instances.service_type_id
    left join lateral (
      select
        ceil(
          extract(epoch from (sessions.completed_at - sessions.started_at)) / 60.0
        )::integer as actual_minutes,
        sessions.auto_completed
      from public.service_qr_sessions sessions
      where sessions.service_instance_id = instances.id
        and sessions.status = 'completed'
        and sessions.devotee_id = assignments.devotee_id
      order by sessions.completed_at desc
      limit 1
    ) session on true
    left join lateral (
      select
        ceil(
          extract(epoch from (verifications.end_at - verifications.start_at)) / 60.0
        )::integer as actual_minutes
      from public.service_verifications verifications
      where verifications.service_instance_id = instances.id
        and verifications.devotee_id = assignments.devotee_id
        and verifications.status = 'verified'
      order by verifications.responded_at desc nulls last
      limit 1
    ) verified on true
    where instances.status <> 'cancelled'
      and instances.date <= public.seva_mala_today()
      and (p_devotee_id is null or assignments.devotee_id = p_devotee_id)
  ),
  measured as (
    select
      base.*,
      greatest(
        0,
        least(
          base.planned_minutes,
          coalesce(base.actual_minutes, base.planned_minutes)
        )
      )::numeric as raw_minutes
    from base
  ),
  -- Only work that earns something spends the cap.
  billable as (
    select
      measured.*,
      case when measured.quality > 0 then measured.raw_minutes else 0 end as cap_basis
    from measured
  ),
  by_day as (
    select
      billable.devotee_id,
      billable.occurred_on,
      sum(billable.cap_basis) as day_minutes
    from billable
    group by 1, 2
  ),
  day_factors as (
    select
      by_day.devotee_id,
      by_day.occurred_on,
      case
        when by_day.day_minutes > caps.day_cap then caps.day_cap / by_day.day_minutes
        else 1.0
      end as day_factor
    from by_day cross join caps
  ),
  by_week as (
    select
      day_factors.devotee_id,
      public.seva_mala_week_start(day_factors.occurred_on) as week_start,
      sum(by_day.day_minutes * day_factors.day_factor) as week_minutes
    from day_factors
    join by_day
      on by_day.devotee_id = day_factors.devotee_id
     and by_day.occurred_on = day_factors.occurred_on
    group by 1, 2
  ),
  week_factors as (
    select
      by_week.devotee_id,
      by_week.week_start,
      case
        when by_week.week_minutes > caps.week_cap then caps.week_cap / by_week.week_minutes
        else 1.0
      end as week_factor
    from by_week cross join caps
  )
  select
    billable.assignment_id,
    billable.devotee_id,
    billable.service_instance_id,
    billable.service_type_id,
    billable.seva_name,
    billable.occurred_on,
    billable.started_at_local,
    billable.planned_minutes,
    billable.actual_minutes,
    billable.raw_minutes,
    billable.quality,
    billable.weight,
    day_factors.day_factor,
    week_factors.week_factor,
    billable.cap_basis * day_factors.day_factor * week_factors.week_factor,
    billable.raw_minutes * billable.quality * billable.weight
      * day_factors.day_factor * week_factors.week_factor,
    billable.assignment_status,
    billable.verification,
    billable.attendance,
    billable.is_recurring,
    billable.points_status
  from billable
  join day_factors
    on day_factors.devotee_id = billable.devotee_id
   and day_factors.occurred_on = billable.occurred_on
  join week_factors
    on week_factors.devotee_id = billable.devotee_id
   and week_factors.week_start = public.seva_mala_week_start(billable.occurred_on)
$$;

comment on function public.seva_mala_acts(uuid) is
  'Every past act of seva with its points_status, credited minutes, quality multiplier, scarcity weight and cap factors. Weekly seva earns its points on completion; one-off seva needs completed, verified and served. Hours are kept whatever the status. Windows nothing: the caps belong to the day and the week.';

revoke all on function public.seva_mala_acts(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 6. The queue, truthfully shortened.
--
--    0057's list, judged by the same rule the points are. A completed weekly
--    act is no longer waiting on anybody and stops appearing here, which is the
--    whole practical content of the change: what remains on the President's
--    screen for weekly seva is the roster slots nobody has closed out, and
--    nothing else.
--
--    Recurring instances still carry posted_by null, so what is left of the
--    weekly queue is still app.view_all's. That is 202608040027's authority and
--    not this file's choice; it is simply a very much shorter list.
-- ---------------------------------------------------------------------------

create or replace function public.list_seva_awaiting_confirmation(
  p_from date default null,
  p_to date default null
)
returns table (
  assignment_id uuid,
  service_instance_id uuid,
  devotee_id uuid,
  devotee_name text,
  seva_name text,
  occurred_on date,
  weekday text,
  started_at_local time,
  planned_minutes integer,
  is_recurring boolean,
  posted_by uuid,
  points_status text,
  points_note text
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    assignments.id,
    instances.id,
    assignments.devotee_id,
    users.name,
    public.service_instance_name(instances),
    instances.date,
    trim(to_char(instances.date, 'FMDay')),
    instances.start_time,
    instances.duration_minutes,
    instances.template_id is not null,
    instances.posted_by,
    public.seva_points_status(
      assignments.status, assignments.attendance, assignments.verification,
      instances.template_id is not null),
    public.seva_points_note(
      public.seva_points_status(
        assignments.status, assignments.attendance, assignments.verification,
        instances.template_id is not null))
  from public.service_assignments assignments
  join public.service_instances instances
    on instances.id = assignments.service_instance_id
  join public.users on users.id = assignments.devotee_id
  where auth.uid() is not null
    and instances.status <> 'cancelled'
    and instances.date <= public.seva_mala_today()
    and instances.date
        between coalesce(p_from, public.seva_mala_today() - 89)
            and coalesce(p_to, public.seva_mala_today())
    and public.seva_points_status(
          assignments.status, assignments.attendance, assignments.verification,
          instances.template_id is not null
        ) in ('awaiting_completion', 'awaiting_verification', 'awaiting_confirmation')
    and (
      instances.posted_by = auth.uid()
      or public.has_permission('app.view_all')
    )
  order by instances.date desc, instances.start_time desc, users.name
$$;

comment on function public.list_seva_awaiting_confirmation(date, date) is
  'Seva that has not earned points yet and is waiting on somebody, for the devotee who posted it and for the President and Tech Admin. Weekly seva appears only until it is closed out, and only to app.view_all, because a recurring instance carries no poster.';

revoke all on function public.list_seva_awaiting_confirmation(date, date) from public, anon;
grant execute on function public.list_seva_awaiting_confirmation(date, date) to authenticated;

-- ---------------------------------------------------------------------------
-- 7. What this migration deliberately does NOT do.
--
--    It does not recompute. The nightly job at ten past midnight Chicago
--    rebuilds every open period — the week, the month and the lifetime board —
--    and it will do it under the new rule without being asked. Calling
--    recompute_seva_mala() from here would also call ensure_seva_mala_period,
--    which creates last week's and last month's periods and then freezes them
--    because their last day is behind us. On a database being built from these
--    migrations that would freeze two empty periods before any facts existed,
--    and a frozen period is never recomputed. A migration must not decide that
--    last week had nobody in it.
--
--    Scores already frozen stay frozen, and stay as they were computed. A
--    devotee who was second in a closed September was second under September's
--    rule and September's references, and 0055's whole reason for writing the
--    inputs down beside the outputs was so that the answer to "why" survives a
--    change like this one.
-- ---------------------------------------------------------------------------

do $$
begin
  raise notice 'seva mala fairness applied';
end;
$$;
