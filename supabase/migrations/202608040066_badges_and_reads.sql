-- Hours served, ten badges, a quieter Seva Care list, and the reason a name is
-- on the board.
--
-- Four things the temple asked for after living with 202608040055 through
-- 202608040065 for a fortnight. They are in one file because they are one
-- conversation: what a devotee is told they did, what the temple gives them for
-- it, who the President is sent to talk to, and what a devotee may find out
-- about somebody else's place on the garland.
--
-- ---------------------------------------------------------------------------
-- 1. HOURS SERVED IS NOT HOURS CREDITED, AND THE TEMPLE MEANT HOURS SERVED.
--
--    "Hours counted should be everything, unless verification is remaining."
--
--    public.my_seva_mala.seva_minutes is CREDITED minutes: 0062 writes it from
--    public.seva_mala_acts.credited_minutes, which is zero for every act whose
--    points_status is not 'counted'. A devotee who washed pots for six evenings
--    on a recurring assignment nobody has confirmed reads SIX HOURS AS ZERO,
--    and is told so on their own screen. That is not a rounding error in a
--    leaderboard; it is the temple telling somebody they did not do a thing
--    they did.
--
--    So served_minutes joins it. Every act whose points_status is not
--    'not_served', in raw minutes, before the quality multiplier, before the
--    scarcity weight and before the daily and weekly caps — which is the same
--    definition 202608040058 already uses for seva balance and 0057 already
--    uses for my_seva_profile, reused rather than re-derived. Two numbers, both
--    true, and the client shows hours from one and points from the other:
--
--      served_minutes  what you did. Withheld from nobody, waiting on nobody.
--      seva_minutes    what the scoring paid for. Still zero until the act is
--                      closed out, because points are the thing verification
--                      is for.
--
--    served_minutes >= seva_minutes always, for every devotee and every
--    period. The verification asserts it over the whole fixture rather than in
--    one case, because a served figure that could dip below the credited one
--    would mean the two are measuring different acts.
--
--    THE ADMIN EQUIVALENT IS A NEW FUNCTION AND NOT A WIDER
--    public.list_all_seva_scores, and the reason is worth writing down.
--    supabase/verification/board_access_and_beta.sql pins that function's OUT
--    list character for character — it is 0064's function and 0064's
--    verification, and neither is this migration's to edit. So the President's
--    hours arrive as public.list_all_seva_hours, which carries what
--    list_all_seva_scores cannot and one thing it never could:
--
--      A DEVOTEE WHOSE EVERY ACT IS PENDING IS NOT ON THE BOARD AT ALL.
--      public.period_scores holds a row only where weighted minutes or cents
--      are above zero (0062 section 3), so the devotee this whole section is
--      about is not merely reported as zero on the President's screen — they
--      are absent from it. list_all_seva_hours is a full outer join and they
--      are on it, with their hours, flagged awaiting_only.
--
-- ---------------------------------------------------------------------------
-- 2. TEN BADGES, TEN DIFFERENT REASONS.
--
--    "Spiritual, meaningful, insightful ISKCON names, like games" — five for
--    the week, five for the month, and each one earned for something else.
--    Not five copies of "top N" with the N changed.
--
--    The names are Gaudiya Vaishnava terms chosen because they say what the
--    badge is for, not because they sound like a temple. Each is listed in
--    section 7 with the one line the app's legend shows.
--
--    THE RULE VARIES, NOT THE THRESHOLD. 0055 gave award_definitions five rule
--    kinds and two things to rank by — score, seva_norm, giving_norm — and all
--    three of those are the scoring's own compressed, capped, congregation-
--    relative numbers. Ranking ten badges over three norms would make ten
--    badges about one thing. So this file adds a MEASURE: a plain, uncompressed
--    quantity about a devotee in a period, of which there are ten, one per
--    badge:
--
--      served_hours          hours actually served
--      days_served           how many different days they turned up on
--      seva_categories       how much of the temple's work they touched
--      longest_run_weeks     the current unbroken run of weeks in one seva
--      giving_weeks          how many separate weeks they gave in
--      predawn_minutes       minutes served before seven in the morning
--      scarce_earliest       how early they took a seva the temple struggles to fill
--      reached_both_medians  at or above the middle devotee in hours AND giving
--      served_a_new_seva     a kind of seva they had never served before
--      beat_own_best_hours   more hours than any earlier period of their own
--
--    NO NEW rule_kind. supabase/verification/seva_mala.sql asserts that
--    award_definitions holds exactly 0055's five rule kinds and no more — "so
--    none of them is dead code" — and that is a good assertion to keep true.
--    The three measures that are really yes-or-no questions emit the value 1
--    and are configured as a derived_threshold with a floor of 1, which is the
--    honest reading of "everybody who did it": a threshold over a column of
--    ones is one.
--
--    threshold_floor is the other new column and it is not decoration. 0058
--    section 3 already takes greatest(quantile, floor) everywhere for a
--    reason: with only five service categories in the whole schema, the
--    seventy-fifth percentile of "how many categories did you serve in" is one
--    in most congregations, and a quantile on its own would hand the breadth
--    badge to everybody who served once. The floor is what the words "three
--    different categories" mean; the quantile is what this congregation
--    happens to be. A devotee has to clear both.
--
--    ALL TEN ARE CONFIG. rule_measure, threshold_quantile, threshold_floor,
--    top_n, the title, the description and the line the legend shows are
--    columns on public.award_definitions, which 0055 and 0063 established the
--    President may edit without a migration. Nothing about the ten is a branch
--    in a function body. The rotation mechanism is untouched and unused here:
--    rotation is for gifts that are LATERAL — the seven Deity garlands, which
--    are the same gift offered on the same terms — and these ten are not
--    lateral, they are ten different questions, so every one of them is
--    offered every period.
--
-- ---------------------------------------------------------------------------
-- 3. A BADGE STAYS UP WHILE THE DEVOTEE IS STILL EARNING IT.
--
--    "That badge will be there for a week or month based on the badge, and if
--    they are still doing the same job and eligible for the same badge or a
--    different badge, it will still show after the week/month ends."
--
--    0063 answered the second half of that and not the first. Its rule is: an
--    award is displayed if its period is the most recent FROZEN period of its
--    kind that awarded anything. Which means a badge earned in the period that
--    is HAPPENING RIGHT NOW is not displayed at all. Seven of the ten badges
--    below are non-rivalrous and are awarded live, the moment the devotee
--    crosses the line — 0055 section 14's rule, unchanged — and under 0063 a
--    devotee who earns Nitya-sevā on Thursday would be shown nothing for it
--    until the following Monday, and then shown it for a week whether or not
--    they were still serving. That is exactly backwards from what the temple
--    said.
--
--    So the display anchor gains the open period:
--
--      AN AWARD IS CURRENTLY DISPLAYED IF ITS PERIOD IS EITHER THE PERIOD OF
--      ITS KIND THAT IS OPEN NOW, OR THE MOST RECENT FROZEN PERIOD OF ITS KIND
--      THAT AWARDED ANYTHING — AND, WHERE A DEVOTEE HOLDS THE SAME BADGE FOR
--      BOTH, IT IS THE LATER ONE THAT IS SHOWN.
--
--    Read against the temple's sentence. A devotee serving on four days a week
--    every week holds Nitya-sevā for the open week from the day they cross it,
--    holds it again for that week once it closes, and holds it for the next
--    week from the day they cross it again. It never comes down, because they
--    never stopped. A devotee who stops holds it until their last week closes
--    and the next one closes without them — "only drops when they stop". A
--    devotee who stops doing one thing and starts another wears the new badge
--    instead of the old one, which is "the same badge or a different badge".
--
--    Per definition, not per row: the distinct-on in section 10 means a badge
--    re-earned in the open period replaces its own closed-period copy rather
--    than appearing twice. A devotee cannot wear two Nitya-sevās.
--
--    LIFETIME IS STILL NEVER DISPLAYED. The lifetime period spans 1970 to 9999
--    and is therefore open forever; if it were an anchor, "Your First Seva"
--    would be published on a devotee's profile permanently, which 0063 section
--    3 refuses out loud and for a good reason. It is excluded by name.
--
--    NOTHING IS REVOKED, AND THIS FILE ADDS NO WAY TO REVOKE ANYTHING. Expiry
--    is still a join that stops matching. public.list_devotee_award_shelf still
--    returns every award ever earned, and section 14 refuses to apply if this
--    file has written an UPDATE or a DELETE against public.devotee_awards.
--
-- ---------------------------------------------------------------------------
-- 4. SEVA CARE: ONLY GENUINE OUTLIERS, AND DISMISSIBLE.
--
--    Two complaints, and they are the same complaint. The list is too long,
--    and a President who has already had the conversation is shown the row
--    again tomorrow.
--
--    TOO LONG. 0058's gate is "more hours a week in one seva than the
--    congregation's own upper tail, for longer than the congregation's own
--    runs". Both terms compare a devotee to the WHOLE congregation, and that is
--    the wrong comparison for the question the temple actually asks. Pot
--    washing is not kirtan. A devotee giving six hours a week to the one seva
--    that six other people also give six hours a week to is doing a normal
--    amount of a demanding thing; a devotee giving six hours a week to a seva
--    everybody else gives ninety minutes to is the devotee the President was
--    asking about. So a third gate, and it is a comparison against the
--    devotee's OWN SEVA rather than against the temple:
--
--      hours a week in this seva >= multiple x the normal for THIS seva
--
--    where the normal is the median hours a week among the OTHER devotees who
--    serve it — excluding the candidate, or a lone server would be their own
--    normal and no ratio could ever exceed one — and, where there are too few
--    others to have a normal at all, the congregation's median weekly load
--    instead. The multiple is seva_balance.frequency_multiple, default 2.0,
--    and it is a dial like every other number in 0058.
--
--    THE THIRD GATE APPLIES ONLY TO THE TEMPLE'S OWN LIST. A caller who names
--    p_min_hours has said in the call what "more than normal" means to them,
--    and 0058 already treats a named threshold as a different question — it is
--    what lets a coordinator ask past the gathering rule. A derived gate that
--    silently overrode an explicit one would make the parameters a lie.
--
--    THE ROW. Week hours and month hours, which are the two figures the office
--    reads out loud, on the temple's own Chicago calendar. The row keeps every
--    column 0058 gave it: src/screens/SevaCareScreen.tsx renders `note` and
--    src/features/sevayatra/types.ts declares the two new columns OPTIONAL
--    beside the old ones, so a deployed client reading this list would crash on
--    a narrower row. Trimming a shape a shipped screen decodes is not
--    simplification, it is an outage. What the screen shows is the screen's
--    business; what this function must not do is send a President to talk to
--    somebody who is fine, and that is the gate, not the column list.
--
--    DISMISSAL. public.seva_care_dismissals, plus dismiss_seva_care and
--    restore_seva_care, both app.view_all and nobody else. A dismissal with a
--    null service type is the whole devotee — the temple's words are "dismiss a
--    devotee from the list" — and a dismissal naming a service type is that one
--    seva, because a President who has settled the pot washing has not
--    necessarily settled the 4am flower duty.
--
--    IT LAPSES AFTER NINETY DAYS, and the number is not arbitrary. Ninety days
--    is seva_balance.window_weeks: the trailing quarter every figure in 0058 is
--    measured over. When a dismissal lapses, every hour that produced the
--    original concern has left the window, so a devotee who resurfaces does so
--    on entirely fresh evidence and the President is never shown a conversation
--    they already had. seva_balance.dismissal_days is the dial.
--
--    A DISMISSAL IS NOT A JUDGEMENT AND IS NOT VISIBLE TO THE DEVOTEE. Nothing
--    in this section is granted to anybody but app.view_all, nothing notifies,
--    and public.my_seva_balance is untouched. 0058 rule 2 stands: a devotee
--    must not be able to tell from anything they can read whether they appear
--    on a coordinator's list, or whether somebody dismissed them from it.
--
-- ---------------------------------------------------------------------------
-- 5. WHY THAT NAME IS ON THE BOARD.
--
--    public.seva_yatra_devotee_summary(p_devotee_id, p_period_kind). Tap a
--    name on the garland and read what put them there: the published points,
--    the hours they served, how many acts, the seva they gave most of those
--    hours to, and whether they gave.
--
--    AND NOT THE COMPONENTS. 0055 section 4 and 0060 section 3 are the whole of
--    the reason and they have not weakened: giving_norm plus a knowable
--    reference inverts to the devotee's giving to the dollar, and score plus
--    seva_norm gives giving_norm back exactly. So seva_norm and giving_norm are
--    not in the return type at all — not gated, ABSENT, because a column that
--    exists is a column somebody can un-gate in a hurry — and the exact score
--    and the cash figures are may_view_all_giving's, exactly as
--    list_all_seva_scores has them, with giving_withheld saying which caller
--    you are so a null cannot be read as a zero.
--
--    `supported` is the one thing about giving an ordinary devotee gets, and it
--    is not new: public.list_seva_supporters already publishes "this devotee
--    gave in this period" to every signed-in devotee, by name, with no amount.
--    Restating a fact that is already public costs nothing; withholding it here
--    while publishing it there would only be confusing.
--
--    points and seva_points are already public too, and by construction: 0060's
--    list_seva_garland publishes seva_mala_points(score) in its 'combined' mode
--    and seva_mala_points(seva_norm) in its 'seva' mode, to any devotee, for
--    every devotee on the board. Two calls and a join by devotee_id give both
--    integers today. The verification proves the equality rather than asserting
--    the argument, so if 0060's board ever stops publishing one of them this
--    function is caught publishing something new.
--
--    WHO MAY ASK. Any signed-in devotee, about a devotee who is ON THE BOARD —
--    opted in, scored above zero in that period, and in a period that met the
--    minimum cohort. About anybody else: nothing at all, not a row of nulls,
--    because an empty answer for an opted-out devotee and an empty answer for
--    a devotee who did nothing must look the same. app.view_all may ask about
--    anybody, and a devotee may always ask about themselves.
--
-- Requires 202608040065_recurring_autocomplete.sql.

-- ---------------------------------------------------------------------------
-- 0. The ground this stands on.
--
--    Asserted rather than assumed. Every one of these is something an earlier
--    migration decided and a later one could take away, and all four features
--    below are built on top of them.
-- ---------------------------------------------------------------------------

do $$
declare
  v_holders text;
  v_definition text;
begin
  if to_regprocedure('public.seva_mala_acts(uuid)') is null
    or to_regprocedure('public.seva_mala_number(text, numeric)') is null
    or to_regprocedure('public.seva_mala_week_start(date)') is null
    or to_regprocedure('public.seva_mala_today()') is null
    or to_regprocedure('public.seva_mala_points(numeric)') is null
    or to_regprocedure('public.award_seva_mala_for_period(uuid)') is null
    or to_regprocedure('public.current_award_periods()') is null
    or to_regprocedure('public.list_devotee_badges(uuid)') is null
    or to_regprocedure('public.list_devotee_award_shelf(uuid)') is null
    or to_regprocedure('public.list_seva_concentration(integer, numeric)') is null
    or to_regprocedure('public.seva_balance_acts(uuid)') is null
    or to_regprocedure('public.seva_balance_references()') is null
    or to_regprocedure('public.may_view_whole_seva_board()') is null
    or to_regprocedure('public.may_view_all_giving()') is null
  then
    raise exception
      'Seva Mala is not fully in place; apply 202608040055 through 202608040065 first.';
  end if;

  -- Section 3. Expiry stays a join that stops matching, and that is only safe
  -- while the row underneath it cannot be deleted.
  if not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.devotee_awards'::regclass
      and tgname = 'devotee_awards_append_only'
      and not tgisinternal
  ) then
    raise exception
      'The append-only trigger on public.devotee_awards is gone. Nothing in this file may be applied until it is back.';
  end if;

  select string_agg(roles.name, ',' order by roles.name) into v_holders
  from public.role_permissions
  join public.roles on roles.id = role_permissions.role_id
  where role_permissions.permission_key = 'app.view_all';
  if v_holders is distinct from 'president,tech' then
    raise exception
      'app.view_all is held by % — Seva Care dismissal and the whole-board reads assume president, tech.',
      v_holders;
  end if;

  -- Section 1 and section 5 both promise that the components stay shut. That is
  -- only a promise worth making while the table itself is unreadable.
  if has_table_privilege('authenticated', 'public.period_scores', 'select')
    or has_table_privilege('authenticated', 'public.seva_mala_periods', 'select')
    or has_table_privilege('authenticated', 'public.app_settings', 'select')
  then
    raise exception 'authenticated can already read the Seva Mala components.';
  end if;

  -- Section 1's whole argument. If credited minutes were not zeroed for a
  -- pending act there would be nothing here to fix, and served_minutes would be
  -- a second name for a number that already existed.
  if public.seva_points_status('completed', 'unknown', 'self_report', false)
     <> 'awaiting_verification'
  then
    raise exception
      'A completed, unverified one-off act no longer reads as awaiting_verification; section 1 is describing a rule that has changed.';
  end if;

  -- Section 2 leans on there being exactly five rule kinds and on the five
  -- being 0055's. This file adds a measure, not a sixth kind.
  select pg_get_constraintdef(pg_constraint.oid) into v_definition
  from pg_constraint
  where conrelid = 'public.award_definitions'::regclass
    and contype = 'c'
    and pg_get_constraintdef(pg_constraint.oid) like '%rule_kind%';
  if v_definition is null
    or position('''derived_threshold''' in v_definition) = 0
    or position('''top_n''' in v_definition) = 0
    or position('''personal''' in v_definition) = 0
    or position('''discretionary''' in v_definition) = 0
    or position('''draw''' in v_definition) = 0
  then
    raise exception 'award_definitions.rule_kind is no longer 0055''s five kinds.';
  end if;

  -- Section 4's category floor is a statement about a list that lives in
  -- 202608020002. Three of five is a meaningful breadth; three of twenty is not.
  if (select count(distinct service_types.category) from public.service_types) is null then
    raise exception 'public.service_types has no categories; Navadha would measure nothing.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 1. The dials this file adds.
--
--    Four numbers, in public.app_settings with everything else, none of them
--    written into a function body. on conflict do nothing throughout: a temple
--    that has already moved one of these keeps its own value.
-- ---------------------------------------------------------------------------

insert into public.app_settings (key, value) values
  -- Section 2. A seva is "hard to fill" when its measured scarcity weight is in
  -- this quantile of the temple's own service types. Not a hardcoded list of
  -- unpopular seva, which would go stale and which somebody would have to
  -- defend at a council meeting.
  ('seva_mala.scarce_seva_quantile', '0.75'),
  -- Section 2. Before this hour is "before dawn" for Brahma-muhurta. Chicago,
  -- like every other boundary in Seva Mala.
  ('seva_mala.predawn_hour', '7'),
  -- Section 4. How many times the normal for a seva a devotee has to be doing
  -- of it before the President is sent to ask.
  ('seva_balance.frequency_multiple', '2.0'),
  -- Section 4. How many OTHER devotees have to serve a seva before their median
  -- is a normal rather than an anecdote.
  ('seva_balance.frequency_min_peers', '3'),
  -- Section 4. A dismissal lasts one trailing quarter, which is exactly how
  -- long the evidence that produced it takes to leave the window.
  ('seva_balance.dismissal_days', '90')
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------
-- 2. Hours served.
--
--    One definition, in one place, called by everything below. Every act whose
--    points_status is not 'not_served', in raw minutes.
--
--    RAW MINUTES, not credited. The caps in 0055 exist so nobody can farm a
--    leaderboard, and a figure whose whole purpose is to tell a devotee what
--    they did must not clip it. 0058 section "Where the hours come from" makes
--    the same three choices for the same reasons and this is the same number;
--    it is stated separately only because 0058's version is windowless and this
--    one is asked about a period.
-- ---------------------------------------------------------------------------

create or replace function public.seva_mala_served(
  p_from date,
  p_to date,
  p_devotee_id uuid default null
)
returns table (
  devotee_id uuid,
  served_minutes numeric,
  served_acts integer
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    acts.devotee_id,
    sum(acts.raw_minutes),
    count(*)::integer
  from public.seva_mala_acts(p_devotee_id) acts
  where p_from is not null
    and p_to is not null
    and acts.occurred_on between p_from and p_to
    and acts.points_status <> 'not_served'
  group by acts.devotee_id
$$;

comment on function public.seva_mala_served(date, date, uuid) is
  'Minutes a devotee actually served in a window and how many acts they were, before the quality multiplier, the scarcity weight and the daily and weekly caps. Everything except "they were not there". Never smaller than the credited figure, because credited minutes are these minutes with things taken away.';

revoke all on function public.seva_mala_served(date, date, uuid)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. Your own standing, with the hours you actually served.
--
--    0057 section 4's function with two columns added and nothing else touched.
--    Dropped and recreated because the return shape moves; the argument list
--    does not, so one DROP names both the old function and the new one and no
--    overload can be left behind.
--
--    served_minutes is counted from the acts and not from public.period_scores,
--    for the reason 0057 gives about pending_minutes: the devotee whose every
--    act is waiting has no row in period_scores at all, and is precisely the
--    devotee this column exists for.
-- ---------------------------------------------------------------------------

drop function if exists public.my_seva_mala(text);

create function public.my_seva_mala(p_period_kind text default 'week')
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
  ranked as (
    select
      scores.*,
      dense_rank() over (order by scores.score desc)::integer as overall_standing
    from public.period_scores scores
    join target on target.id = scores.period_id
    where scores.score > 0
  ),
  board as (
    select
      scores.devotee_id,
      dense_rank() over (order by scores.score desc)::integer as board_standing
    from public.period_scores scores
    join target on target.id = scores.period_id
    join public.users on users.id = scores.devotee_id
    where scores.score > 0 and users.leaderboard_visible
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
    coalesce(ranked.score, 0),
    coalesce(round(ranked.credited_minutes), 0)::integer,
    coalesce(round(served.served_minutes), 0)::integer,
    coalesce(served.served_acts, 0),
    coalesce(ranked.seva_acts, 0),
    coalesce(waiting.pending_acts, 0),
    coalesce(round(waiting.pending_minutes), 0)::integer,
    coalesce(ranked.giving_cents, 0),
    coalesce(ranked.gifts, 0),
    case when target.participant_count >= minimum.cohort then ranked.overall_standing end,
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
  left join ranked on ranked.devotee_id = auth.uid()
  left join board on board.devotee_id = auth.uid()
  where auth.uid() is not null
$$;

comment on function public.my_seva_mala(text) is
  'Your own Seva Mala standing for the current week, month or lifetime. served_minutes is every minute you served, whatever the paperwork says; seva_minutes is what the scoring credited. The first is never smaller than the second, and the difference is what is still waiting on somebody.';

revoke all on function public.my_seva_mala(text) from public, anon;
grant execute on function public.my_seva_mala(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. The same two figures, for everybody, for the President.
--
--    A companion to public.list_all_seva_scores rather than a widening of it —
--    header section 1 has the reason, and it is a verification file this
--    migration does not own.
--
--    Who may read it is may_view_whole_seva_board, which is 0064's named
--    predicate and therefore the same three people who already read the board.
--    NOT may_view_all_giving: there is no cash figure and no norm here, and
--    gating hours on the giving permission would say hours are as private as
--    money, which the temple has never said.
--
--    A full outer join, and that is the point of the function.
-- ---------------------------------------------------------------------------

create or replace function public.list_all_seva_hours(p_period_kind text default 'week')
returns table (
  devotee_id uuid,
  devotee_name text,
  period_id uuid,
  period_start date,
  period_end date,
  served_minutes integer,
  served_acts integer,
  credited_minutes integer,
  credited_acts integer,
  awaiting_minutes integer,
  awaiting_acts integer,
  points integer,
  awaiting_only boolean,
  is_hidden boolean
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
  served as (
    select hours.*
    from target
    join public.seva_mala_served(target.starts_on, target.ends_on) hours on true
  ),
  waiting as (
    select
      acts.devotee_id,
      sum(acts.raw_minutes) as minutes,
      count(*)::integer as acts
    from target
    join public.seva_mala_acts() acts
      on acts.occurred_on between target.starts_on and target.ends_on
    where acts.points_status in (
      'awaiting_completion', 'awaiting_verification', 'awaiting_confirmation'
    )
    group by acts.devotee_id
  ),
  everybody as (
    select
      coalesce(served.devotee_id, scores.devotee_id) as devotee_id,
      coalesce(served.served_minutes, 0) as served_minutes,
      coalesce(served.served_acts, 0) as served_acts,
      coalesce(scores.credited_minutes, 0) as credited_minutes,
      coalesce(scores.seva_acts, 0) as credited_acts,
      scores.score as score,
      scores.devotee_id is null as awaiting_only
    from served
    full outer join (
      select period_scores.*
      from public.period_scores
      join target on target.id = period_scores.period_id
    ) scores on scores.devotee_id = served.devotee_id
  )
  select
    everybody.devotee_id,
    users.name,
    target.id,
    target.starts_on,
    target.ends_on,
    round(everybody.served_minutes)::integer,
    everybody.served_acts,
    round(everybody.credited_minutes)::integer,
    everybody.credited_acts,
    round(coalesce(waiting.minutes, 0))::integer,
    coalesce(waiting.acts, 0),
    public.seva_mala_points(everybody.score),
    everybody.awaiting_only,
    not users.leaderboard_visible
  from everybody
  cross join target
  join public.users on users.id = everybody.devotee_id
  left join waiting on waiting.devotee_id = everybody.devotee_id
  where auth.uid() is not null
    and public.may_view_whole_seva_board()
  order by everybody.served_minutes desc, users.name
$$;

comment on function public.list_all_seva_hours(text) is
  'Hours served and hours credited for every devotee in the current period, for the President, the Tech Admin and the Community Head. Includes the devotees public.period_scores has no row for at all — the ones whose every act is still waiting on somebody — flagged awaiting_only, because a devotee who served twelve hours nobody has confirmed is the devotee this list exists to find. No score, no norm and no cent.';

revoke all on function public.list_all_seva_hours(text) from public, anon;
grant execute on function public.list_all_seva_hours(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. What a badge may be measured on.
--
--    Three columns, all config, all editable by the President without a
--    migration, and all null on every row 0055 and 0063 wrote — which is what
--    makes this a widening rather than a change. A definition with a null
--    rule_measure is judged exactly as it was yesterday.
-- ---------------------------------------------------------------------------

alter table public.award_definitions
  add column if not exists rule_measure text,
  add column if not exists threshold_floor numeric,
  add column if not exists earned_by text;

comment on column public.award_definitions.rule_measure is
  'A plain quantity about a devotee in a period — hours, days, categories, weeks running — that this badge is decided on, instead of the scoring''s compressed norms. Null means the 0055 behaviour: rank_basis over public.period_scores.';

comment on column public.award_definitions.threshold_floor is
  'The semantic minimum a derived threshold may fall to. "Three different categories" means three whatever the congregation''s seventy-fifth percentile happens to be; the quantile is what this temple is, the floor is what the words mean. Both must be cleared.';

comment on column public.award_definitions.earned_by is
  'One line saying what earns this badge, shown in the app''s legend. Editable, because the President rewording a badge should not need a release.';

alter table public.award_definitions
  drop constraint if exists award_rule_measure_known;
alter table public.award_definitions
  add constraint award_rule_measure_known check (
    rule_measure is null or rule_measure in (
      'served_hours', 'days_served', 'seva_categories', 'longest_run_weeks',
      'giving_weeks', 'predawn_minutes', 'scarce_earliest',
      'reached_both_medians', 'served_a_new_seva', 'beat_own_best_hours'
    )
  );

alter table public.award_definitions
  drop constraint if exists award_rule_measure_kind;
alter table public.award_definitions
  add constraint award_rule_measure_kind check (
    rule_measure is null or rule_kind in ('top_n', 'derived_threshold')
  );

alter table public.award_definitions
  drop constraint if exists award_threshold_floor_positive;
alter table public.award_definitions
  add constraint award_threshold_floor_positive check (
    threshold_floor is null or threshold_floor > 0
  );

alter table public.award_definitions
  drop constraint if exists award_earned_by_shape;
alter table public.award_definitions
  add constraint award_earned_by_shape check (
    earned_by is null or length(trim(earned_by)) between 4 and 300
  );

-- 0055's top_n rule wanted a rank_basis because ranking over period_scores was
-- the only ranking there was. A measured badge ranks over its measure instead,
-- and the constraint is restated to say "one or the other" rather than being
-- dropped, because a top_n with neither is a badge that ranks on nothing.
alter table public.award_definitions
  drop constraint if exists award_top_n_rule_complete;
alter table public.award_definitions
  add constraint award_top_n_rule_complete check (
    rule_kind <> 'top_n'
    or (top_n is not null and (rank_basis is not null or rule_measure is not null))
  );

-- The legend is public in the same sense the award list already was: 0055
-- granted authenticated a named list of columns on this table, and the line
-- saying what earns a badge belongs beside the line saying what it is.
grant select (
  id, code, title, description, earned_by, tier, garland_kind, rule_kind,
  period_kind, is_active, sort_order
) on public.award_definitions to authenticated;

-- ---------------------------------------------------------------------------
-- 6. The ten measures.
--
--    One function, one row per devotee per measure, computed only for the
--    measure asked for. Everything is read through public.seva_mala_acts and
--    public.donations, which is to say through the same facts the scoring uses,
--    so a badge and a score can never come to disagree about whether somebody
--    served.
--
--    Every measure counts SERVED acts — points_status <> 'not_served' — for
--    header section 1's reason. A badge for turning up must not wait on the
--    paperwork either.
--
--    Three of the measures are windowless by design and say so where they are:
--    a run of weeks, a seva you have never served before and a personal best
--    are all questions about a devotee's whole history, and truncating them at
--    the edge of a period would answer a different one.
-- ---------------------------------------------------------------------------

create or replace function public.seva_mala_period_measures(
  p_period_kind text,
  p_from date,
  p_to date,
  p_measure text default null
)
returns table (
  devotee_id uuid,
  measure text,
  value numeric
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_scarce numeric;
  v_predawn time := make_time(
    least(23, greatest(0, public.seva_mala_number('seva_mala.predawn_hour', 7)::integer)),
    0, 0);
  v_bucket date;
begin
  if p_from is null or p_to is null or p_to < p_from then
    return;
  end if;

  -- Hours actually served. The badge the temple names first.
  if p_measure is null or p_measure = 'served_hours' then
    return query
    select hours.devotee_id, 'served_hours'::text, round(hours.served_minutes / 60.0, 4)
    from public.seva_mala_served(p_from, p_to) hours
    where hours.served_minutes > 0;
  end if;

  -- How many separate days they turned up on. Not hours: a devotee who gives
  -- one hour on five days is more present in the temple's life than a devotee
  -- who gives five hours on one, and this is the badge that says so.
  if p_measure is null or p_measure = 'days_served' then
    return query
    select acts.devotee_id, 'days_served'::text, count(distinct acts.occurred_on)::numeric
    from public.seva_mala_acts() acts
    where acts.occurred_on between p_from and p_to
      and acts.points_status <> 'not_served'
      and acts.raw_minutes > 0
    group by acts.devotee_id;
  end if;

  -- How much of the temple's work they touched. Custom-named seva carries no
  -- service type and therefore no category, and is left out entirely rather
  -- than being given a category of its own — 0058 section 6's rule, for the
  -- same reason: it says nothing about whether they have ever swept a floor.
  if p_measure is null or p_measure = 'seva_categories' then
    return query
    select acts.devotee_id, 'seva_categories'::text, count(distinct types.category)::numeric
    from public.seva_mala_acts() acts
    join public.service_types types on types.id = acts.service_type_id
    where acts.occurred_on between p_from and p_to
      and acts.points_status <> 'not_served'
      and acts.raw_minutes > 0
    group by acts.devotee_id;
  end if;

  -- Minutes before the temple is awake. 0055 already measures "hour
  -- unusualness" per service type for the scarcity weight; this is the same
  -- observation made about a devotee instead of about a seva.
  if p_measure is null or p_measure = 'predawn_minutes' then
    return query
    select acts.devotee_id, 'predawn_minutes'::text, sum(acts.raw_minutes)
    from public.seva_mala_acts() acts
    where acts.occurred_on between p_from and p_to
      and acts.points_status <> 'not_served'
      and acts.started_at_local < v_predawn
    group by acts.devotee_id
    having sum(acts.raw_minutes) > 0;
  end if;

  -- How many separate weeks they gave in. Never how much: the whole content of
  -- this badge is that a hundred dollars in four weeks is steadier than four
  -- hundred in one, and a measure that could see the amount would be a giving
  -- board with an extra step.
  if p_measure is null or p_measure = 'giving_weeks' then
    return query
    select
      donations.donor_id,
      'giving_weeks'::text,
      count(distinct public.seva_mala_week_start(
        (donations.received_at at time zone 'America/Chicago')::date))::numeric
    from public.donations
    where donations.donor_id is not null
      and donations.amount_cents > 0
      and (donations.received_at at time zone 'America/Chicago')::date
          between p_from and p_to
    group by donations.donor_id;
  end if;

  -- The current unbroken run of weeks in ONE kind of seva. Windowless, then
  -- required to reach the last week of the period: 0058 section 2's rule, and
  -- for its reason — a streak truncated at the window edge reports a devotee of
  -- three years' standing as thirteen weeks, and a streak that ended in March
  -- is not a streak.
  if p_measure is null or p_measure = 'longest_run_weeks' then
    return query
    with kinds as (
      select
        acts.devotee_id as who,
        coalesce(acts.service_type_id::text, 'custom:' || lower(acts.seva_name)) as seva_key,
        public.seva_mala_week_start(acts.occurred_on) as week_start
      from public.seva_mala_acts() acts
      where acts.occurred_on <= p_to
        and acts.points_status <> 'not_served'
        and acts.raw_minutes > 0
      group by 1, 2, 3
    ),
    islands as (
      select
        kinds.who,
        kinds.seva_key,
        kinds.week_start,
        kinds.week_start
          - (row_number() over (
              partition by kinds.who, kinds.seva_key order by kinds.week_start))::integer * 7
          as island
      from kinds
    ),
    runs as (
      select
        islands.who,
        islands.seva_key,
        count(*)::numeric as weeks_run,
        max(islands.week_start) as last_week
      from islands
      group by 1, 2, islands.island
    )
    select runs.who, 'longest_run_weeks'::text, max(runs.weeks_run)
    from runs
    where runs.last_week >= public.seva_mala_week_start(p_to)
    group by runs.who;
  end if;

  -- Who got to the hard seva first. "Hard" is the temple's own measured
  -- scarcity weight, not a list somebody typed: 0055 section 5 derives it from
  -- fill rate, declines, how few people will do it and how odd its hours are.
  -- The value counts DOWN from the end of the period, so the earliest act is
  -- the largest number and the ordinary top_n rule picks it out without a
  -- second code path. Ties share, which is 0055's dense_rank and correct: two
  -- devotees who arrived at the same hour both arrived first.
  if p_measure is null or p_measure = 'scarce_earliest' then
    select percentile_cont(
             public.seva_mala_number('seva_mala.scarce_seva_quantile', 0.75)
           ) within group (order by weights.weight)
    into v_scarce
    from public.seva_type_weights weights;

    if v_scarce is not null then
      return query
      select
        acts.devotee_id,
        'scarce_earliest'::text,
        max(extract(epoch from (
          ((p_to + 1)::date + time '00:00')
          - (acts.occurred_on + coalesce(acts.started_at_local, time '00:00'))
        )))::numeric
      from public.seva_mala_acts() acts
      join public.seva_type_weights weights
        on weights.service_type_id = acts.service_type_id
      where acts.occurred_on between p_from and p_to
        and acts.points_status <> 'not_served'
        and acts.raw_minutes > 0
        and weights.weight >= v_scarce
      group by acts.devotee_id;
    end if;
  end if;

  -- Body, mind and wealth. One if they reached the congregation's middle
  -- devotee in BOTH hours served and giving in this period, and no row at all
  -- otherwise. The medians are taken among the devotees active in each
  -- dimension separately, which is 0062's rule for the references and is here
  -- for the same reason: a temple where a fifth of people give must not have
  -- its giving median dragged to zero by the four fifths who serve instead.
  if p_measure is null or p_measure = 'reached_both_medians' then
    return query
    with served as (
      select hours.devotee_id as who, hours.served_minutes as minutes
      from public.seva_mala_served(p_from, p_to) hours
      where hours.served_minutes > 0
    ),
    giving as (
      select donations.donor_id as who, sum(donations.amount_cents)::numeric as cents
      from public.donations
      where donations.donor_id is not null
        and (donations.received_at at time zone 'America/Chicago')::date
            between p_from and p_to
      group by donations.donor_id
      having sum(donations.amount_cents) > 0
    ),
    marks as (
      select
        (select percentile_cont(0.5) within group (order by served.minutes) from served)
          as seva_mark,
        (select percentile_cont(0.5) within group (order by giving.cents) from giving)
          as giving_mark
    )
    select served.who, 'reached_both_medians'::text, 1::numeric
    from served
    join giving on giving.who = served.who
    cross join marks
    where marks.seva_mark is not null
      and marks.giving_mark is not null
      and served.minutes >= marks.seva_mark
      and giving.cents >= marks.giving_mark;
  end if;

  -- A kind of seva they had never served before this period. Windowless on the
  -- "before" side by necessity: the question is about their whole history.
  if p_measure is null or p_measure = 'served_a_new_seva' then
    return query
    with every_act as (
      select
        acts.devotee_id as who,
        coalesce(acts.service_type_id::text, 'custom:' || lower(acts.seva_name)) as seva_key,
        acts.occurred_on
      from public.seva_mala_acts() acts
      where acts.points_status <> 'not_served'
        and acts.raw_minutes > 0
        and acts.occurred_on <= p_to
    ),
    inside as (
      select distinct every_act.who, every_act.seva_key
      from every_act
      where every_act.occurred_on between p_from and p_to
    ),
    before as (
      select distinct every_act.who, every_act.seva_key
      from every_act
      where every_act.occurred_on < p_from
    )
    select distinct inside.who, 'served_a_new_seva'::text, 1::numeric
    from inside
    where not exists (
      select 1 from before
      where before.who = inside.who and before.seva_key = inside.seva_key
    );
  end if;

  -- More hours than in any earlier period of the same kind they served in. One
  -- if so; no row if they have no earlier period at all, because a devotee's
  -- first week is not a personal best — it is a first, and 0055 already has a
  -- badge for that.
  if p_measure is null or p_measure = 'beat_own_best_hours' then
    v_bucket := case
      when p_period_kind = 'week' then public.seva_mala_week_start(p_from)
      else date_trunc('month', p_from)::date
    end;

    return query
    with buckets as (
      select
        acts.devotee_id as who,
        case
          when p_period_kind = 'week' then public.seva_mala_week_start(acts.occurred_on)
          else date_trunc('month', acts.occurred_on)::date
        end as bucket,
        sum(acts.raw_minutes) as minutes
      from public.seva_mala_acts() acts
      where acts.occurred_on <= p_to
        and acts.points_status <> 'not_served'
        and acts.raw_minutes > 0
      group by 1, 2
    ),
    now_bucket as (
      select buckets.who, buckets.minutes from buckets where buckets.bucket = v_bucket
    ),
    best_before as (
      select buckets.who, max(buckets.minutes) as minutes
      from buckets where buckets.bucket < v_bucket
      group by buckets.who
    )
    select now_bucket.who, 'beat_own_best_hours'::text, 1::numeric
    from now_bucket
    join best_before on best_before.who = now_bucket.who
    where now_bucket.minutes > best_before.minutes;
  end if;
end;
$$;

comment on function public.seva_mala_period_measures(text, date, date, text) is
  'The ten plain quantities a badge can be decided on, per devotee, for one period. Hours, days, categories, weeks running, giving weeks, pre-dawn minutes, who reached a scarce seva first, who met both medians, who served something new and who beat their own best. Every one counts served acts rather than credited ones.';

revoke all on function public.seva_mala_period_measures(text, date, date, text)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 7. The ten.
--
--    Five weekly, five monthly, ten different reasons. on conflict (code) do
--    nothing throughout, for 0055's reason: re-applying this file must never
--    stamp on a row the President has since edited.
--
--    Tier is 'recognition' for the seven nobody can lose by somebody else
--    arriving and 'token_of_appreciation' for the three that are decided at the
--    top of a period. NOT 'garland': a garland is a physical object from the
--    altar that somebody has to make and hand over, and inventing ten more of
--    them would be a promise the kitchen never agreed to.
-- ---------------------------------------------------------------------------

insert into public.award_definitions
  (code, title, description, earned_by, tier, rule_kind, period_kind,
   rule_measure, threshold_quantile, threshold_floor, top_n, sort_order)
values
  -- ---- the week -----------------------------------------------------------
  ('weekly_shrama_dana',
   'Śrama-dāna',
   'The gift of labour. For the devotee who gave the temple the most of their hours this week.',
   'Serving more hours than anybody else in the week. Hours count from the moment you serve them, whether or not the confirmation has caught up.',
   'token_of_appreciation', 'top_n', 'week',
   'served_hours', null, null, 1, 200),

  ('weekly_nitya_seva',
   'Nitya-sevā',
   'Unceasing service. Not the most hours — the most days. The temple was not empty of you.',
   'Turning up on at least three different days in one week, and on as many days as the most regular part of the congregation.',
   'recognition', 'derived_threshold', 'week',
   'days_served', 0.80, 3, null, 210),

  ('weekly_arunodaya',
   'Aruṇodaya',
   'Daybreak. The first light on a seva that was still waiting for somebody.',
   'Being the first devotee in the week to take up one of the seva the temple finds hardest to fill.',
   'token_of_appreciation', 'top_n', 'week',
   'scarce_earliest', null, null, 1, 220),

  ('weekly_dhairya',
   'Dhairya',
   'Perseverance. The same seva, week after week, with nobody watching.',
   'Holding one seva for at least four unbroken weeks, and for as long a run as the steadiest part of the congregation.',
   'recognition', 'derived_threshold', 'week',
   'longest_run_weeks', 0.85, 4, null, 230),

  ('weekly_ruci',
   'Ruci',
   'A new taste. The stage where devotion stops being duty and starts being appetite.',
   'Serving a kind of seva you had never served before.',
   'recognition', 'derived_threshold', 'week',
   'served_a_new_seva', 0.50, 1, null, 240),

  -- ---- the month ----------------------------------------------------------
  ('monthly_navadha',
   'Navadhā',
   'The ninefold. Devotion has many limbs, and this devotee has used more than one of them.',
   'Serving in at least three different categories of the temple''s work in one month.',
   'recognition', 'derived_threshold', 'month',
   'seva_categories', 0.75, 3, null, 250),

  ('monthly_dhruva_dana',
   'Dhruva-dāna',
   'The unwavering gift. Dhruva did not move, and neither does this.',
   'Giving in at least three separate weeks of the month. How much never enters it.',
   'recognition', 'derived_threshold', 'month',
   'giving_weeks', 0.75, 3, null, 260),

  ('monthly_tan_mana_dhana',
   'Tan-mana-dhana',
   'Body, mind and wealth — Narottama''s three, offered together rather than one instead of another.',
   'Reaching the congregation''s middle devotee in both hours served and giving, in the same month.',
   'token_of_appreciation', 'derived_threshold', 'month',
   'reached_both_medians', 0.50, 1, null, 270),

  ('monthly_brahma_muhurta',
   'Brāhma-muhūrta',
   'The hour before dawn. The temple is loveliest and emptiest then, and somebody is always there.',
   'Serving more of the month''s minutes before seven in the morning than anybody else.',
   'token_of_appreciation', 'top_n', 'month',
   'predawn_minutes', null, null, 1, 280),

  ('monthly_bhakti_lata',
   'Bhakti-latā',
   'The creeper of devotion, which grows. Measured against nobody but your own past.',
   'Serving more hours this month than in any month you have served before.',
   'recognition', 'derived_threshold', 'month',
   'beat_own_best_hours', 0.50, 1, null, 290)
on conflict (code) do nothing;

-- The legend line for the gifts that were already here. earned_by did not
-- exist until this file, so nothing here can be stamping on a President's
-- edit — the column was null on every row a moment ago, and the guard says so
-- rather than trusting it.
update public.award_definitions
set earned_by = wording.earned_by
from (values
  ('weekly_recognition',
   'Reaching the level of the congregation''s median active devotee over a week.'),
  ('monthly_recognition',
   'Reaching the level of the congregation''s median active devotee over a month.'),
  ('monthly_token',
   'Standing among the more giving three-quarters of the congregation in a month.'),
  ('weekly_maha_prasad',
   'Being among the three devotees who carried the week.'),
  ('monthly_maha_prasad',
   'Being among the ten devotees who carried the month.'),
  ('weekly_token',
   'Being among the ten devotees at the top of the week.'),
  ('garland_seva',
   'Service that carried the temple through a month.'),
  ('garland_dana',
   'Generosity that carried the temple through a month.'),
  ('garland_samatva',
   'Giving both your hands and your means through a month.'),
  ('mystery_gift',
   'Nothing. It is drawn at random from everyone who took part, and that is the point.'),
  ('weekly_mystery_gift',
   'Nothing. It is drawn at random from everyone who took part, and that is the point.'),
  ('first_seva',
   'Serving once. There is only one of these.'),
  ('personal_best_month',
   'Passing your own best month. Measured against nobody but yourself.'),
  ('presidents_gift',
   'Something an algorithm would never have seen. The President decides.')
) as wording(code, earned_by)
where award_definitions.code = wording.code
  and award_definitions.earned_by is null;

-- The seven Deity garlands, in one statement over the rotation group rather
-- than seven rows, so that no two of them can be given different wording and
-- become a ranking.
update public.award_definitions
set earned_by =
  'Standing at the top of the period whose turn this garland is. The seven take turns and not one of them stands above another.'
where rotation_group in ('weekly_deity_garland', 'monthly_deity_garland')
  and earned_by is null;

-- ---------------------------------------------------------------------------
-- 8. Awarding, restated whole, with the measures in it.
--
--    202608040063 section 5 unchanged, plus one branch at the top of each rule.
--    Restated in full rather than wrapped, for 0063's reason: a wrapper around a
--    rule this file needs to modify is a second place for the rule to live.
--
--    A definition with a null rule_measure takes 0063's path, expression for
--    expression. A definition with one takes the measured path:
--
--      top_n              rank the measure, dense_rank, frozen periods only,
--                         because nothing here is ever revoked and handing a
--                         "most hours this week" badge out on a Wednesday puts
--                         it on the wrong devotee for ever.
--      derived_threshold  greatest(quantile of the positive values, floor),
--                         awarded live, because a non-rivalrous badge is a
--                         statement about you and not about who else showed up.
--
--    The two windows are the period's, clipped at today for an open one, so a
--    measure is never asked about days that have not happened.
-- ---------------------------------------------------------------------------

create or replace function public.award_seva_mala_for_period(p_period_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_period public.seva_mala_periods;
  v_definition public.award_definitions;
  v_frozen boolean;
  v_threshold numeric;
  v_given integer := 0;
  v_rows integer;
  v_from date;
  v_to date;
begin
  select * into v_period from public.seva_mala_periods where id = p_period_id;
  if v_period.id is null then
    return 0;
  end if;
  v_frozen := v_period.frozen_at is not null;
  v_from := v_period.starts_on;
  v_to := least(v_period.ends_on, public.seva_mala_today());

  for v_definition in
    select * from public.award_definitions
    where is_active
      and period_kind = v_period.period_kind
      and rule_kind <> 'discretionary'
    order by sort_order, code
  loop
    if v_definition.rotation_group is not null then
      -- Not this garland's week.
      if v_definition.id is distinct from public.award_rotation_turn(
           v_definition.rotation_group, v_period.period_kind, v_period.starts_on)
      then
        continue;
      end if;

      -- This group has already had its turn in this period. One garland a
      -- week, whatever the cycle looked like the last time this ran.
      if exists (
        select 1
        from public.devotee_awards awards
        join public.award_definitions others
          on others.id = awards.award_definition_id
        where awards.period_id = v_period.id
          and others.rotation_group = v_definition.rotation_group
      ) then
        continue;
      end if;
    end if;

    -- ---------------------------------------------------------------------
    -- The measured rules. 202608040066 section 6.
    -- ---------------------------------------------------------------------
    if v_definition.rule_measure is not null then
      if v_to < v_from then
        continue;
      end if;

      if v_definition.rule_kind = 'derived_threshold' then
        select percentile_cont(coalesce(v_definition.threshold_quantile, 0.5))
               within group (order by measures.value)
        into v_threshold
        from public.seva_mala_period_measures(
               v_period.period_kind, v_from, v_to, v_definition.rule_measure) measures
        where measures.value > 0;

        v_threshold := greatest(
          coalesce(v_threshold, 0), coalesce(v_definition.threshold_floor, 0));

        if v_threshold > 0 then
          insert into public.devotee_awards (
            award_definition_id, devotee_id, period_id
          )
          select v_definition.id, measures.devotee_id, v_period.id
          from public.seva_mala_period_measures(
                 v_period.period_kind, v_from, v_to, v_definition.rule_measure) measures
          where measures.value >= v_threshold
          on conflict do nothing;
          get diagnostics v_rows = row_count;
          v_given := v_given + v_rows;
        end if;

      elsif v_definition.rule_kind = 'top_n' and v_frozen then
        insert into public.devotee_awards (
          award_definition_id, devotee_id, period_id
        )
        select v_definition.id, ranked.devotee_id, v_period.id
        from (
          select
            measures.devotee_id,
            dense_rank() over (order by measures.value desc) as rank_position
          from public.seva_mala_period_measures(
                 v_period.period_kind, v_from, v_to, v_definition.rule_measure) measures
          where measures.value > 0
        ) ranked
        where ranked.rank_position <= v_definition.top_n
        on conflict do nothing;
        get diagnostics v_rows = row_count;
        v_given := v_given + v_rows;
      end if;

      continue;
    end if;

    -- ---------------------------------------------------------------------
    -- 202608040055 and 202608040063's rules, unchanged.
    -- ---------------------------------------------------------------------
    if v_definition.rule_kind = 'derived_threshold' then
      select percentile_cont(v_definition.threshold_quantile)
             within group (order by scores.score)
      into v_threshold
      from public.period_scores scores
      where scores.period_id = v_period.id and scores.score > 0;

      if v_threshold is not null then
        insert into public.devotee_awards (
          award_definition_id, devotee_id, period_id
        )
        select v_definition.id, scores.devotee_id, v_period.id
        from public.period_scores scores
        where scores.period_id = v_period.id
          and scores.score > 0
          and scores.score >= v_threshold
        on conflict do nothing;
        get diagnostics v_rows = row_count;
        v_given := v_given + v_rows;
      end if;

    elsif v_definition.rule_kind = 'top_n' and v_frozen then
      insert into public.devotee_awards (
        award_definition_id, devotee_id, period_id
      )
      select v_definition.id, ranked.devotee_id, v_period.id
      from (
        select
          scores.devotee_id,
          dense_rank() over (
            order by case v_definition.rank_basis
              when 'seva' then scores.seva_norm
              when 'giving' then scores.giving_norm
              else scores.score
            end desc
          ) as rank_position
        from public.period_scores scores
        where scores.period_id = v_period.id
          and case v_definition.rank_basis
                when 'seva' then scores.seva_norm
                when 'giving' then scores.giving_norm
                else scores.score
              end > 0
      ) ranked
      where ranked.rank_position <= v_definition.top_n
      on conflict do nothing;
      get diagnostics v_rows = row_count;
      v_given := v_given + v_rows;

    elsif v_definition.rule_kind = 'draw' and v_frozen then
      insert into public.devotee_awards (
        award_definition_id, devotee_id, period_id
      )
      select v_definition.id, drawn.devotee_id, v_period.id
      from (
        select scores.devotee_id
        from public.period_scores scores
        where scores.period_id = v_period.id and scores.score > 0
        order by md5(v_period.id::text || scores.devotee_id::text)
        limit 1
      ) drawn
      on conflict do nothing;
      get diagnostics v_rows = row_count;
      v_given := v_given + v_rows;

    elsif v_definition.rule_kind = 'personal'
      and v_definition.rule_key = 'first_seva'
    then
      insert into public.devotee_awards (
        award_definition_id, devotee_id, period_id
      )
      select v_definition.id, firsts.devotee_id, v_period.id
      from (
        select acts.devotee_id, min(acts.occurred_on) as first_on
        from public.seva_mala_acts() acts
        where acts.quality > 0
        group by acts.devotee_id
      ) firsts
      where firsts.first_on between v_period.starts_on and v_period.ends_on
      on conflict do nothing;
      get diagnostics v_rows = row_count;
      v_given := v_given + v_rows;

    elsif v_definition.rule_kind = 'personal'
      and v_definition.rule_key = 'personal_best'
    then
      insert into public.devotee_awards (
        award_definition_id, devotee_id, period_id
      )
      select v_definition.id, scores.devotee_id, v_period.id
      from public.period_scores scores
      where scores.period_id = v_period.id
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
      on conflict do nothing;
      get diagnostics v_rows = row_count;
      v_given := v_given + v_rows;
    end if;
  end loop;

  return v_given;
end;
$$;

comment on function public.award_seva_mala_for_period(uuid) is
  'Hands out every non-discretionary award a period has earned, on the scoring''s norms or on one of 202608040066''s ten measures. Rivalrous rules still wait for the period to close, because nothing here is ever revoked. A rotation group has exactly one turn per period, and having had it once it is skipped on every later run.';

revoke all on function public.award_seva_mala_for_period(uuid)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 9. What there is to earn, and what earns it.
--
--    The legend. Readable by any signed-in devotee, because "what is there to
--    earn" is a question a devotee is entitled to an answer to before they have
--    earned anything, and because the answer must come from the row the
--    President can edit rather than from a list compiled into the app.
--
--    No rule and no threshold: earned_by is English written for a devotee, and
--    "the eighty-fifth percentile of consecutive weeks" is not that. Nothing
--    here says who holds a badge or how many exist.
-- ---------------------------------------------------------------------------

create or replace function public.list_seva_badge_legend()
returns table (
  code text,
  title text,
  description text,
  earned_by text,
  tier text,
  period_kind text
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    definitions.code,
    definitions.title,
    definitions.description,
    coalesce(definitions.earned_by, definitions.description),
    definitions.tier,
    definitions.period_kind
  from public.award_definitions definitions
  where auth.uid() is not null
    and definitions.is_active
  order by definitions.period_kind, definitions.sort_order, definitions.code
$$;

comment on function public.list_seva_badge_legend() is
  'Every gift the temple currently offers and the one line saying what earns it, for any signed-in devotee. Read from award_definitions so the President can reword a badge without an app release. Never who holds one.';

revoke all on function public.list_seva_badge_legend() from public, anon;
grant execute on function public.list_seva_badge_legend() to authenticated;

-- ---------------------------------------------------------------------------
-- 10. Which awards a devotee is wearing right now.
--
--     Header section 3. Two anchors per period kind — the period open now, and
--     the most recent frozen period that awarded anything — and the devotee's
--     latest holding of each definition among them.
--
--     0063's public.current_award_periods is unchanged and still means what it
--     said: the latest closed leaderboard of each kind. It is one of the two
--     anchors rather than the whole rule now, and its comment is restated to
--     say so, because a comment that describes the old rule is worse than no
--     comment.
--
--     LIFETIME IS EXCLUDED BY NAME from the open anchor. It spans 1970 to 9999
--     and would otherwise be open forever, publishing "Your First Seva" on a
--     profile permanently — which 0063 section 3 refuses, and for the reason it
--     gives: it announces that a devotee is new, for ever, and nobody decided
--     that out loud.
-- ---------------------------------------------------------------------------

comment on function public.current_award_periods() is
  'The most recent closed period of each kind that awarded anything — the latest leaderboard. One of the two anchors 202608040066 displays badges against; the other is the period currently open, so a badge earned this week is worn this week.';

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
  order by awards.award_definition_id, periods.starts_on desc, awards.awarded_on desc
$$;

comment on function public.current_devotee_awards(uuid) is
  'The awards one devotee is wearing right now: their latest holding of each badge, among the period of each kind that is open and the latest closed leaderboard of each kind. A badge stays while they keep earning it and comes down only when a period of its kind closes without them. Nothing is deleted — this is a join that stops matching.';

revoke all on function public.current_devotee_awards(uuid)
  from public, anon, authenticated;

-- 0063 section 7's function, with the display rule replaced and nothing else
-- moved. Same return shape, same three ways a row is visible, same cohort gate
-- — now applied to the award's OWN period, which under the new rule is not
-- always the latest one.
create or replace function public.list_devotee_badges(p_devotee_id uuid)
returns table (
  award_id uuid,
  award_code text,
  title text,
  description text,
  tier text,
  garland_kind text,
  period_kind text,
  period_start date,
  period_end date,
  awarded_on date
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    awards.id,
    definitions.code,
    definitions.title,
    definitions.description,
    definitions.tier,
    definitions.garland_kind,
    current_awards.period_kind,
    current_awards.period_start,
    current_awards.period_end,
    awards.awarded_on
  from public.current_devotee_awards(p_devotee_id) current_awards
  join public.devotee_awards awards on awards.id = current_awards.award_id
  join public.award_definitions definitions
    on definitions.id = awards.award_definition_id
  join public.users devotee on devotee.id = awards.devotee_id
  where auth.uid() is not null
    and p_devotee_id is not null
    and current_awards.participant_count
        >= public.seva_mala_number('seva_mala.minimum_cohort', 8)
    and (
      p_devotee_id = auth.uid()
      or devotee.leaderboard_visible
      or public.has_permission('app.view_all')
    )
  order by current_awards.period_start desc, definitions.code
$$;

comment on function public.list_devotee_badges(uuid) is
  'A devotee''s currently displayed badges, readable by any signed-in devotee: the gift, its tier, whose garland it was and which period it was for. Never a score, a place, an hour or a cent. A badge stays up while the devotee keeps earning it. A devotee who opted out of the board is not published here either — the badge is still earned, still on their shelf and still handed over.';

revoke all on function public.list_devotee_badges(uuid) from public, anon;
grant execute on function public.list_devotee_badges(uuid) to authenticated;

-- The shelf. Everything, forever, unchanged except that is_current now asks
-- the new predicate — which is the point of it: the President must see the
-- profile a visitor sees, and would otherwise be reasoning about a rule this
-- file replaced.
create or replace function public.list_devotee_award_shelf(p_devotee_id uuid)
returns table (
  award_id uuid,
  award_code text,
  title text,
  description text,
  tier text,
  garland_kind text,
  rule_kind text,
  period_kind text,
  period_start date,
  period_end date,
  awarded_on date,
  awarded_by uuid,
  citation text,
  fulfilled_on date,
  fulfilment_note text,
  is_current boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  with showing as (
    select * from public.current_devotee_awards(p_devotee_id)
  )
  select
    awards.id,
    definitions.code,
    definitions.title,
    definitions.description,
    definitions.tier,
    definitions.garland_kind,
    definitions.rule_kind,
    definitions.period_kind,
    periods.starts_on,
    periods.ends_on,
    awards.awarded_on,
    awards.awarded_by,
    awards.citation,
    awards.fulfilled_on,
    awards.fulfilment_note,
    coalesce(
      devotee.leaderboard_visible
      and exists (
        select 1 from showing
        where showing.award_id = awards.id
          and showing.participant_count
              >= public.seva_mala_number('seva_mala.minimum_cohort', 8)
      ),
      false
    )
  from public.devotee_awards awards
  join public.award_definitions definitions
    on definitions.id = awards.award_definition_id
  join public.users devotee on devotee.id = awards.devotee_id
  left join public.seva_mala_periods periods on periods.id = awards.period_id
  where auth.uid() is not null
    and p_devotee_id is not null
    and awards.devotee_id = p_devotee_id
    and (p_devotee_id = auth.uid() or public.has_permission('app.view_all'))
  order by awards.awarded_on desc, definitions.code
$$;

comment on function public.list_devotee_award_shelf(uuid) is
  'Every award a devotee ever earned, current or long expired, for the devotee themselves and for the President and the Tech Admin. is_current says whether the public can see it right now, on 202608040066''s rule. Nothing is ever removed from this list.';

revoke all on function public.list_devotee_award_shelf(uuid) from public, anon;
grant execute on function public.list_devotee_award_shelf(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 11. Dismissing a Seva Care row once it has been handled.
--
--     Header section 4. Not granted to anybody: every read and every write goes
--     through the four functions below, and all four are app.view_all's.
-- ---------------------------------------------------------------------------

create table if not exists public.seva_care_dismissals (
  id uuid primary key default gen_random_uuid(),
  devotee_id uuid not null references public.users(id) on delete cascade,
  -- Null is the whole devotee. The temple's words are "dismiss a devotee from
  -- the list"; naming a service type narrows it to that one seva, because a
  -- President who has settled the pot washing has not settled the 4am flowers.
  service_type_id uuid references public.service_types(id) on delete cascade,
  dismissed_by uuid not null references public.users(id),
  dismissed_at timestamptz not null default now(),
  lapses_on date not null,
  note text,
  restored_at timestamptz,
  restored_by uuid references public.users(id),
  restore_note text,
  constraint seva_care_dismissal_note_shape check (
    note is null or length(trim(note)) between 2 and 500
  ),
  constraint seva_care_dismissal_restore_note_shape check (
    restore_note is null or length(trim(restore_note)) between 2 and 500
  ),
  constraint seva_care_dismissal_restore_pair check (
    (restored_at is null) = (restored_by is null)
  ),
  constraint seva_care_dismissal_restore_note_needs_restore check (
    restore_note is null or restored_at is not null
  )
);

comment on table public.seva_care_dismissals is
  'A conversation the President has already had. Hides a devotee, or a devotee and one seva, from list_seva_concentration until it lapses. Never visible to the devotee, never a judgement, and never a reason not to count their hours.';

-- One live dismissal per devotee per seva. A lapsed one is not live and does
-- not block a fresh dismissal; dismiss_seva_care extends the live one rather
-- than inserting beside it.
create unique index if not exists seva_care_dismissals_live
  on public.seva_care_dismissals (
    devotee_id,
    coalesce(service_type_id, '00000000-0000-0000-0000-000000000000'::uuid)
  )
  where restored_at is null;

create index if not exists seva_care_dismissals_lapse_idx
  on public.seva_care_dismissals (lapses_on) where restored_at is null;

alter table public.seva_care_dismissals enable row level security;
revoke all on table public.seva_care_dismissals from public, anon, authenticated;

create or replace function public.seva_care_dismissal_days()
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select greatest(
    1,
    least(3650, public.seva_mala_number('seva_balance.dismissal_days', 90)::integer)
  )
$$;

comment on function public.seva_care_dismissal_days() is
  'How long a Seva Care dismissal lasts. Ninety days by default, which is seva_balance.window_weeks — one trailing quarter, exactly as long as the evidence that produced the dismissal takes to leave the window.';

revoke all on function public.seva_care_dismissal_days() from public, anon, authenticated;

create or replace function public.dismiss_seva_care(
  p_devotee_id uuid,
  p_service_type_id uuid default null,
  p_note text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_lapses date := public.seva_mala_today() + public.seva_care_dismissal_days();
begin
  if not public.has_permission('app.view_all') then
    raise exception
      'Only the President and the Tech Admin may clear a Seva Care row.';
  end if;
  if p_devotee_id is null then
    raise exception 'Which devotee has been spoken to?';
  end if;
  if not exists (select 1 from public.users where users.id = p_devotee_id) then
    raise exception 'That devotee could not be found.';
  end if;
  if p_service_type_id is not null
    and not exists (select 1 from public.service_types where service_types.id = p_service_type_id)
  then
    raise exception 'That kind of seva could not be found.';
  end if;
  if p_note is not null and length(trim(p_note)) not between 2 and 500 then
    raise exception 'A note is between 2 and 500 characters, or nothing at all.';
  end if;

  -- Dismissing again is extending, not duplicating: the clock restarts from
  -- the conversation that just happened.
  update public.seva_care_dismissals
  set lapses_on = v_lapses,
      dismissed_at = now(),
      dismissed_by = auth.uid(),
      note = coalesce(nullif(trim(coalesce(p_note, '')), ''), seva_care_dismissals.note)
  where seva_care_dismissals.devotee_id = p_devotee_id
    and seva_care_dismissals.service_type_id is not distinct from p_service_type_id
    and seva_care_dismissals.restored_at is null
  returning seva_care_dismissals.id into v_id;

  if v_id is null then
    insert into public.seva_care_dismissals (
      devotee_id, service_type_id, dismissed_by, lapses_on, note
    ) values (
      p_devotee_id, p_service_type_id, auth.uid(), v_lapses,
      nullif(trim(coalesce(p_note, '')), '')
    )
    returning id into v_id;
  end if;

  return v_id;
end;
$$;

comment on function public.dismiss_seva_care(uuid, uuid, text) is
  'Clear a devotee from the Seva Care list once the conversation has happened. A null service type clears the devotee; naming one clears that seva alone. Lapses after seva_care_dismissal_days so a devotee still carrying too much next quarter comes back on fresh evidence. Never seen by the devotee, and it changes no hours and no points.';

revoke all on function public.dismiss_seva_care(uuid, uuid, text) from public, anon;
grant execute on function public.dismiss_seva_care(uuid, uuid, text) to authenticated;

-- The name the app already ships. src/features/sevayatra/api.ts calls
-- dismiss_seva_care_row with two arguments, and a wrapper is cheaper than a
-- client release; the rule lives in one place and this is not it.
create or replace function public.dismiss_seva_care_row(
  p_devotee_id uuid,
  p_service_type_id uuid default null
)
returns uuid
language sql
security definer
set search_path = ''
as $$
  select public.dismiss_seva_care(p_devotee_id, p_service_type_id, null)
$$;

comment on function public.dismiss_seva_care_row(uuid, uuid) is
  'dismiss_seva_care under the name the app already calls. Carries no note and decides nothing of its own.';

revoke all on function public.dismiss_seva_care_row(uuid, uuid) from public, anon;
grant execute on function public.dismiss_seva_care_row(uuid, uuid) to authenticated;

create or replace function public.restore_seva_care(
  p_devotee_id uuid,
  p_service_type_id uuid default null,
  p_note text default null
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rows integer;
begin
  if not public.has_permission('app.view_all') then
    raise exception
      'Only the President and the Tech Admin may put a Seva Care row back.';
  end if;
  if p_devotee_id is null then
    raise exception 'Which devotee should come back to the list?';
  end if;
  if p_note is not null and length(trim(p_note)) not between 2 and 500 then
    raise exception 'A note is between 2 and 500 characters, or nothing at all.';
  end if;

  update public.seva_care_dismissals
  set restored_at = now(),
      restored_by = auth.uid(),
      restore_note = nullif(trim(coalesce(p_note, '')), '')
  where seva_care_dismissals.devotee_id = p_devotee_id
    and seva_care_dismissals.service_type_id is not distinct from p_service_type_id
    and seva_care_dismissals.restored_at is null;

  get diagnostics v_rows = row_count;
  return v_rows;
end;
$$;

comment on function public.restore_seva_care(uuid, uuid, text) is
  'Undo a dismissal. Returns how many were undone, so a caller can tell "put back" from "there was nothing there". The dismissal is kept with who undid it and when, because who has looked at a devotee''s load is itself a thing the temple should be able to read back.';

revoke all on function public.restore_seva_care(uuid, uuid, text) from public, anon;
grant execute on function public.restore_seva_care(uuid, uuid, text) to authenticated;

create or replace function public.list_seva_care_dismissals(p_include_lapsed boolean default false)
returns table (
  dismissal_id uuid,
  devotee_id uuid,
  devotee_name text,
  service_type_id uuid,
  seva_name text,
  dismissed_by uuid,
  dismissed_by_name text,
  dismissed_at timestamptz,
  lapses_on date,
  days_left integer,
  note text,
  is_live boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    dismissals.id,
    dismissals.devotee_id,
    devotee.name,
    dismissals.service_type_id,
    types.name,
    dismissals.dismissed_by,
    clearer.name,
    dismissals.dismissed_at,
    dismissals.lapses_on,
    (dismissals.lapses_on - public.seva_mala_today())::integer,
    dismissals.note,
    dismissals.restored_at is null and dismissals.lapses_on >= public.seva_mala_today()
  from public.seva_care_dismissals dismissals
  join public.users devotee on devotee.id = dismissals.devotee_id
  left join public.users clearer on clearer.id = dismissals.dismissed_by
  left join public.service_types types on types.id = dismissals.service_type_id
  where auth.uid() is not null
    and public.has_permission('app.view_all')
    and (
      coalesce(p_include_lapsed, false)
      or (dismissals.restored_at is null
          and dismissals.lapses_on >= public.seva_mala_today())
    )
  order by dismissals.dismissed_at desc
$$;

comment on function public.list_seva_care_dismissals(boolean) is
  'Who has been cleared from the Seva Care list, by whom, and when it lapses. Nothing is hidden from the President by a feature whose whole purpose is to hide rows from them.';

revoke all on function public.list_seva_care_dismissals(boolean) from public, anon;
grant execute on function public.list_seva_care_dismissals(boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- 12. Concentration, tightened, with the two figures the office reads.
--
--     0058 section 5, dropped and recreated because the return shape moves.
--     The argument list does NOT move — supabase/verification/seva_balance.sql
--     and supabase/verification/board_access_and_beta.sql both name
--     list_seva_concentration(integer, numeric) by signature, and they are not
--     this migration's files — so the frequency multiple is a dial rather than
--     a third parameter, which is where 0058 puts every other number anyway.
--
--     What is new, in order of how much it matters:
--
--       the third gate     hours a week in this seva against the normal for
--                          THIS seva, not against the congregation at large.
--                          Header section 4.
--       week and month     the two figures the office reads out loud, on the
--                          temple's Chicago calendar rather than as an average
--                          over a quarter.
--       the dismissal      a row a President has handled does not come back
--                          until the evidence is new.
--
--     Everything else is 0058's, expression for expression, including the note.
-- ---------------------------------------------------------------------------

drop function if exists public.list_seva_concentration(integer, numeric);

create function public.list_seva_concentration(
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

  -- THE THIRD GATE APPLIES ONLY TO THE TEMPLE'S OWN LIST. A caller who names
  -- p_min_hours has said in the call what "more than normal" means to them, and
  -- a derived gate that silently overrode an explicit one would make the
  -- parameter a lie. Header section 4.
  v_multiple := case
    when p_min_hours is not null then 0
    else public.seva_mala_number('seva_balance.frequency_multiple', 2.0)
  end;
  v_min_peers := public.seva_mala_number('seva_balance.frequency_min_peers', 3)::integer;

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
  -- The normal for this seva, which is the whole of what "genuinely higher than
  -- normal" needed. Per devotee per kind, over the same window.
  rates as (
    select
      by_type.devotee_id,
      by_type.seva_key,
      by_type.type_hours / active.active_weeks as per_week
    from by_type
    join active on active.devotee_id = by_type.devotee_id
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
  -- seva at all, so the congregation's median weekly load stands in.
  normals as (
    select
      candidates.devotee_id,
      candidates.seva_key,
      coalesce(
        case
          when (select count(*) from rates peers
                where peers.seva_key = candidates.seva_key
                  and peers.devotee_id <> candidates.devotee_id) >= v_min_peers
          -- percentile_cont answers in double precision whatever it is given,
          -- so the cast is not decoration: without it every ratio below becomes
          -- a float and round(float, 2) does not exist.
          then (select percentile_cont(0.5) within group (order by peers.per_week)::numeric
                from rates peers
                where peers.seva_key = candidates.seva_key
                  and peers.devotee_id <> candidates.devotee_id)
        end,
        nullif(v_refs.median_weekly_hours, 0),
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
    where candidates.per_week >= v_min_hours
      and candidates.weeks_run >= v_min_weeks
      -- Genuinely higher than normal for this seva, not merely present in it.
      and (
        v_multiple <= 0
        or candidates.per_week >= v_multiple * coalesce(normals.normal_per_week, 0)
      )
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
  'Devotees carrying genuinely more of one seva than is normal FOR THAT SEVA, for long enough to be a pattern, with the hours they have given it this week and this month. A list of conversations to have, for the President and the Tech Admin. A row cleared through dismiss_seva_care stays gone until the evidence behind it has left the window. Nothing here acts, and nothing here reaches the devotee.';

revoke all on function public.list_seva_concentration(integer, numeric) from public, anon;
grant execute on function public.list_seva_concentration(integer, numeric) to authenticated;

-- ---------------------------------------------------------------------------
-- 13. Why that name is on the board.
--
--     Header section 5. One devotee, one period, and the server decides what
--     this caller may know.
--
--     THE COMPONENTS ARE NOT IN THE RETURN TYPE. Not gated — absent. A gated
--     column is a column somebody widens on a Friday; a column that was never
--     declared is a change somebody has to make on purpose and explain.
-- ---------------------------------------------------------------------------

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
  -- zero, in a period that met the cohort. Being on THIS is what makes a
  -- devotee askable-about.
  board as (
    select
      scores.devotee_id,
      scores.score,
      scores.seva_norm,
      scores.credited_minutes,
      scores.seva_acts,
      scores.giving_cents,
      scores.gifts,
      dense_rank() over (order by scores.score desc)::integer as standing
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
  'Why one devotee is where they are on the Seva Yatra board for one period: their published points, the hours they actually served, how many acts, the seva they gave most of those hours to, and whether they supported the temple. Any signed-in devotee may ask about a devotee who is on the board; app.view_all may ask about anybody; you may always ask about yourself. The exact score and the cash figures are app.view_all''s, and seva_norm and giving_norm are not in the return type at all.';

revoke all on function public.seva_yatra_devotee_summary(uuid, text) from public, anon;
grant execute on function public.seva_yatra_devotee_summary(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 14. Nothing here revokes an award, and the file refuses to have added a way.
--
--     Checked after the functions exist rather than before, so it is this
--     file's own work being audited.
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
      'seva_mala_served', 'list_all_seva_hours', 'seva_mala_period_measures',
      'award_seva_mala_for_period', 'current_devotee_awards',
      'list_devotee_badges', 'list_devotee_award_shelf', 'list_seva_badge_legend',
      'list_seva_concentration', 'seva_yatra_devotee_summary', 'my_seva_mala'
    )
    and pg_get_functiondef(proc.oid) ~* '(delete\s+from\s+public\.devotee_awards|update\s+public\.devotee_awards)';
  if v_offenders is not null then
    raise exception
      '% can remove or rewrite an award. Nothing in Seva Mala revokes.', v_offenders;
  end if;

  -- Seva Care is still a read, apart from the dismissal it was asked for, and
  -- the dismissal writes to its own table and nothing else.
  if pg_get_functiondef(to_regprocedure('public.list_seva_concentration(integer, numeric)'))
     ~* '(insert\s+into|update\s+public|delete\s+from)'
  then
    raise exception 'The concentration list has learned to write.';
  end if;

  -- And no dismissal may reach a devotee. 0058 rule 2.
  if pg_get_functiondef(to_regprocedure('public.dismiss_seva_care(uuid, uuid, text)'))
     ~* '(queue_app_notification|app_notifications)'
  then
    raise exception 'Dismissing a devotee from a care list notifies them.';
  end if;
end;
$$;

do $$
begin
  raise notice
    'Hours served, ten badges, Seva Care dismissal and the board drill-down applied.';
end;
$$;
