-- Badges and gifts — what the temple hands over, and what the congregation sees.
--
-- 202608040055 built the machinery: award_definitions holds the rules,
-- devotee_awards holds what was given, and nothing in either is ever revoked.
-- This migration answers three things the temple asked for afterwards.
--
-- ---------------------------------------------------------------------------
-- 1. MANY MORE GIFTS, and seven of them are garlands.
--
--    The temple's list, weekly, in the temple's own words:
--
--      Maha Prasad · Kisora's garland · Kisori's garland · Jagannath's garland
--      Baldev's garland · Subhadra's garland · Gaura's garland · Nitai's garland
--      Token of Appreciation · Recognition · Mystery Gift
--
--    Seven garlands, and they are LATERAL. Ordering the garlands would order
--    the Deities, and that is not a thing a database migration gets to decide.
--    So they are not a hierarchy a devotee climbs — they ROTATE. Every one of
--    the seven is offered on identical terms (top_n = 1, ranked by score) and
--    which one is offered is decided by the period alone: over any seven
--    consecutive weeks each garland is offered exactly once, and over any
--    seven consecutive months likewise. The seven rows are inserted by a loop
--    over a single template precisely so that they cannot drift apart into
--    something that could be read as a ranking. They share a tier, a rule, a
--    top_n, a rank_basis, a sort_order and a description, character for
--    character; they differ in the Deity's name and in a SEAT, and a seat in a
--    cycle is not a place in an order because a cycle has no first.
--
--    rotation_group / rotation_seat are config on the row, not a branch in a
--    function body. A President who wants six garlands rather than seven sets
--    is_active = false on one, and the cycle is six long from the next period.
--
-- ---------------------------------------------------------------------------
-- 2. AUTOMATIC BADGES FOR THE TOP OF EVERY PERIOD.
--
--    "Every week when they are on top, or every month when they are on top,
--    give them a badge — and to the top 10."
--
--    Three rungs, and both period kinds have all three:
--
--                    week                          month
--      first place   the week's Deity garland      the month's Deity garland
--      top three     Maha Prasad                   the Seva / Dana / Samatva
--                                                  garlands, one per basis
--      top ten       Token of Appreciation         Maha Prasad
--
--    The month's rungs are 202608040055's and are left exactly as they are —
--    0055 says these rows belong to the President, and a migration that
--    UPDATEs them would silently overwrite an edit the temple had already
--    made. The only monthly row added here is the first-place garland, which
--    the month did not have. That the same rung carries a bigger gift in a
--    month than in a week is not an accident: a month is harder than a week.
--
--    Every one of these is top_n, so every one of them fires only when the
--    period is FROZEN — 0055 section 14's rule, unchanged and load-bearing.
--    Handing a garland to whoever happens to be third on a Wednesday, and then
--    never taking it back, puts nine garlands on a three-garland week.
--
--    Ties share. dense_rank is what 0055 ranks with and this file does not
--    change it: two devotees genuinely level at the top are both at the top,
--    and both get the garland. The alternative is a tiebreak nobody asked for.
--
-- ---------------------------------------------------------------------------
-- 3. BADGES EXPIRE FROM THE PUBLIC VIEW AND NEVER FROM THE SHELF.
--
--    "Badge will be there after the week ends, month ends and new week or new
--    month starts, and that will be there for the next week or next month
--    until new leaderboard arrives."
--
--    So there are two different questions about one award and they must not be
--    answered by one column:
--
--      EVER EARNED     public.devotee_awards, append-only, never revoked, and
--                      0055's trigger refuses every path that would try.
--      CURRENTLY SHOWN  a property of the PERIOD, not of the award.
--
--    Computed, not stored. A stored display_until drifts the moment a nightly
--    job runs late, a period is recomputed, or a President changes what closes
--    when — and a badge that vanishes early because of a clock is a badge the
--    temple has to apologise for. So:
--
--      AN AWARD IS CURRENTLY DISPLAYED IF ITS PERIOD IS THE MOST RECENT FROZEN
--      PERIOD OF ITS KIND THAT AWARDED ANYTHING AT ALL.
--
--    Read that against what the temple said. Week W closes at midnight on
--    Sunday; the nightly job freezes it and awards it in the small hours of
--    Monday. From that moment W is the most recent frozen week with awards, so
--    W's badges are on public profiles for the whole of week W+1 — "there for
--    the next week". When W+1 is frozen and awarded, W+1 becomes the most
--    recent and W's badges leave the public profile — "until new leaderboard
--    arrives". Nothing was written, nothing was deleted, and nothing has to be
--    cleaned up by a job that might not run.
--
--    "That awarded anything at all" is the difference between "until the next
--    week" and "until the next leaderboard". A week in which nobody qualified
--    produced no leaderboard, so last week's badges stay up. That is what the
--    temple said, and it is also the kinder behaviour.
--
--    Two consequences, both deliberate:
--
--      A week badge and a month badge are current at the same time, because
--      the rule is per period kind. A devotee can wear last week's garland and
--      last month's Maha Prasad together.
--
--      LIFETIME AND DISCRETIONARY AWARDS ARE NEVER "CURRENTLY DISPLAYED".
--      Lifetime never freezes (0055 section 2) and the President's Gift has no
--      period at all. They sit on the shelf, visible to the devotee and to the
--      President, and they are not published. This is on purpose. "Your First
--      Seva" published forever announces that a devotee is new; a discretionary
--      gift published forever is a permanent public ranking the temple never
--      asked for. Both of those are decisions somebody should make out loud
--      rather than inherit from a join.
--
-- ---------------------------------------------------------------------------
-- 4. WHO MAY SEE THEM, AND THE OPT-OUT.
--
--    "Show them on their profile which can be seen by anyone."
--
--    public.list_devotee_badges returns a devotee's currently displayed badges
--    to any signed-in devotee: the gift's name, its tier, which Deity's garland
--    it was, and which period it was for. Nothing else. No score, no points, no
--    minutes, no cents, no standing, no place. 0055 section 4 and 0060 section
--    3 between them decide what may leave this schema about a devotee's
--    numbers, and a badge list is not the place to reopen that.
--
--    THE TENSION, AND THE DECISION. A devotee who set leaderboard_visible
--    false has opted out of the board. Do their badges still show?
--
--    NO — and their badges are still EARNED, still on their own shelf, still
--    the President's to see, and the garland is still made and still handed
--    over in person. 0055 is explicit that opting out is DISPLAY TO OTHERS and
--    never what is earned, and a public badge is display to others of the most
--    direct kind: "Maha Prasad, week of 3 August" is a leaderboard placement
--    with the number filed off. If badges ignored the flag then anyone could
--    walk the directory, read the badges, and rebuild the top ten of a board
--    that devotee had switched themselves off. The toggle would be decoration.
--    So the one switch the congregation already understands governs both
--    surfaces, exactly as 0060 made it govern the supporters list.
--
--    The devotee still sees their own current badges through the same
--    function, and app.view_all still sees everything, so nothing is hidden
--    from the person it belongs to or from the temple.
--
--    THE COHORT GATE comes along for the same reason. 0055 will not publish a
--    ranking of a congregation smaller than seva_mala.minimum_cohort, because
--    "in a congregation of five a ranking is not recognition, it is a comment
--    about four people". A public badge from a period with five participants is
--    that same comment. So a badge is published only if its period met the
--    cohort. It is still earned, still on the shelf, still handed over.
--
-- ---------------------------------------------------------------------------
-- 5. THE PRESIDENT AND THE TECH ADMIN SEE THE WHOLE SHELF.
--
--    public.list_devotee_award_shelf returns every award a devotee ever earned
--    — current or long expired, period or discretionary, fulfilled or still
--    owed — to the devotee themselves and to app.view_all, and to nobody else.
--    is_current on each row says whether the public can see it right now, so
--    the President never has to guess what a profile looks like from outside.
--
-- ---------------------------------------------------------------------------
-- 6. NOTHING AUTO-REVOKES. EVER.
--
--    This file adds no UPDATE and no DELETE against public.devotee_awards, and
--    section 0 refuses to apply if 0055's append-only trigger has gone missing.
--    Expiry here is a JOIN THAT STOPS MATCHING, not a row that stops existing.
--
--    The notification kind is 'seva_award_earned', declared by 0055, which is
--    still the most recent migration to state app_notifications_kind_check.
--    This file adds no kind, so the constraint is asserted rather than
--    restated — restating a list is only correct when you are adding to it.
--    0055's after-insert trigger already announces every award, including the
--    ones this file invents, because it reads the definition rather than a
--    list of codes.
--
-- Requires 202608040055_seva_mala.sql.

-- ---------------------------------------------------------------------------
-- 0. The ground this stands on.
-- ---------------------------------------------------------------------------

do $$
declare
  v_definition text;
  v_holders text;
  v_tiers text;
begin
  if to_regclass('public.award_definitions') is null
    or to_regclass('public.devotee_awards') is null
    or to_regprocedure('public.award_seva_mala_for_period(uuid)') is null
    or to_regprocedure('public.ensure_seva_mala_period(text, date)') is null
    or to_regprocedure('public.seva_mala_number(text, numeric)') is null
  then
    raise exception
      'Seva Mala''s awards are not in place; apply 202608040055 first.';
  end if;

  -- Section 6. Expiry in this file is a join that stops matching, and that is
  -- only safe while the thing underneath it cannot be deleted.
  if not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.devotee_awards'::regclass
      and tgname = 'devotee_awards_append_only'
      and not tgisinternal
  ) then
    raise exception
      'The append-only trigger on public.devotee_awards is gone. Nothing in this file may be applied until it is back.';
  end if;

  select pg_get_constraintdef(pg_constraint.oid) into v_definition
  from pg_constraint
  where conname = 'app_notifications_kind_check'
    and conrelid = 'public.app_notifications'::regclass;

  if v_definition is null then
    raise exception
      'The app_notifications kind constraint is missing; apply the earlier migrations first.';
  end if;

  -- This file adds no notification kind. 'seva_award_earned' is 0055's and
  -- every award below travels on it, so the constraint is checked rather than
  -- restated: restating a list you are not adding to can only ever narrow it.
  if position('''seva_award_earned''' in v_definition) = 0 then
    raise exception
      'app_notifications_kind_check no longer permits seva_award_earned. Restate it whole from the most recent migration that declares it, including every kind added since.';
  end if;

  select string_agg(roles.name, ',' order by roles.name) into v_holders
  from public.role_permissions
  join public.roles on roles.id = role_permissions.role_id
  where role_permissions.permission_key = 'app.view_all';

  if v_holders is distinct from 'president,tech' then
    raise exception
      'app.view_all is held by % — the award shelf assumes president, tech.', v_holders;
  end if;

  -- The four tiers the gifts below are seeded into.
  select pg_get_constraintdef(pg_constraint.oid) into v_tiers
  from pg_constraint
  where conrelid = 'public.award_definitions'::regclass
    and contype = 'c'
    and pg_get_constraintdef(pg_constraint.oid) like '%tier%'
    and pg_get_constraintdef(pg_constraint.oid) like '%maha_prasad%'
  limit 1;

  if v_tiers is null
    or position('''garland''' in v_tiers) = 0
    or position('''recognition''' in v_tiers) = 0
    or position('''token_of_appreciation''' in v_tiers) = 0
  then
    raise exception
      'award_definitions.tier is no longer 0055''s four tiers; the gifts below would not fit.';
  end if;

  -- Public badges publish a tier and a period and nothing numeric, and that is
  -- only a meaningful promise while the numbers themselves are still shut.
  if has_table_privilege('authenticated', 'public.period_scores', 'select')
    or has_table_privilege('authenticated', 'public.seva_mala_periods', 'select')
  then
    raise exception 'authenticated can already read the Seva Mala components.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 1. A seat in a cycle, which is not a place in an order.
--
--    rotation_group names a set of definitions that take turns. rotation_seat
--    is which turn, and it is read modulo the number of active seats — so seat
--    7 is not "last", it is simply the seat that comes up when the period index
--    lands on it, which for a weekly group is one week in every seven.
--
--    Both columns or neither. A group of one is legal and simply means that
--    definition is offered every period, which is the same as not being in a
--    group at all; a group of zero active members offers nothing.
-- ---------------------------------------------------------------------------

alter table public.award_definitions
  add column if not exists rotation_group text,
  add column if not exists rotation_seat integer;

comment on column public.award_definitions.rotation_group is
  'Definitions sharing a rotation_group take turns: exactly one of them is offered in any period. Config, not code — the President retires a garland with is_active and the cycle shortens from the next period.';

comment on column public.award_definitions.rotation_seat is
  'Which turn in the cycle, read modulo the number of active seats. A seat, not a rank: a cycle has no first.';

alter table public.award_definitions
  drop constraint if exists award_rotation_complete;
alter table public.award_definitions
  add constraint award_rotation_complete check (
    (rotation_group is null) = (rotation_seat is null)
  );

alter table public.award_definitions
  drop constraint if exists award_rotation_group_shape;
alter table public.award_definitions
  add constraint award_rotation_group_shape check (
    rotation_group is null or length(trim(rotation_group)) between 2 and 60
  );

-- Two definitions cannot hold the same seat in the same cycle, or one of them
-- would never be offered and the cycle would quietly be short.
create unique index if not exists award_definitions_rotation_seat_unique
  on public.award_definitions (rotation_group, period_kind, rotation_seat)
  where rotation_group is not null;

-- ---------------------------------------------------------------------------
-- 2. The Deities, added to the kinds a garland can be.
--
--    0055's three lateral garlands — Seva for hands, Dana for giving, Samatva
--    for balance — stay exactly as they are. The seven Deities join them in the
--    same column, and the constraint is restated WHOLE rather than replaced by
--    a shorter list, for the reason 0055 gives about the notification kinds: a
--    narrowed list outlaws something that already exists.
-- ---------------------------------------------------------------------------

do $$
declare
  v_name text;
begin
  for v_name in
    select conname from pg_constraint
    where conrelid = 'public.award_definitions'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) like '%garland_kind%'
      and pg_get_constraintdef(oid) not like '%tier%'
  loop
    execute format('alter table public.award_definitions drop constraint %I', v_name);
  end loop;
end;
$$;

alter table public.award_definitions
  add constraint award_definitions_garland_kind_check check (
    garland_kind is null or garland_kind in (
      -- 202608040055's three, for what a garland is FOR.
      'seva', 'dana', 'samatva',
      -- The temple's seven, for WHOSE garland it is. Lateral among themselves
      -- and lateral against the three above.
      'kisora', 'kisori', 'jagannath', 'baldev', 'subhadra', 'gaura', 'nitai'
    )
  );

-- ---------------------------------------------------------------------------
-- 3. The gifts.
--
--    The seven garlands are inserted by a loop over one template, twice — once
--    for the week and once for the month — so that the fourteen rows differ
--    only in the Deity's name, the Deity's kind and the seat. There is no
--    second place in this list to accidentally write.
--
--    ON CONFLICT (code) DO NOTHING throughout, for 0055's reason: re-applying
--    this file must never stamp on a row the President has since edited.
-- ---------------------------------------------------------------------------

do $$
declare
  v_deity record;
  v_period record;
begin
  for v_deity in
    select * from (values
      ('kisora',    'Kisora''s garland',    1),
      ('kisori',    'Kisori''s garland',    2),
      ('jagannath', 'Jagannath''s garland', 3),
      ('baldev',    'Baldev''s garland',    4),
      ('subhadra',  'Subhadra''s garland',  5),
      ('gaura',     'Gaura''s garland',     6),
      ('nitai',     'Nitai''s garland',     7)
    ) as deity(kind, title, seat)
  loop
    for v_period in
      select * from (values
        ('week',  'weekly_garland_',  'weekly_deity_garland',  'week',  100),
        ('month', 'monthly_garland_', 'monthly_deity_garland', 'month', 140)
      ) as span(period_kind, code_prefix, rotation_group, word, sort_order)
    loop
      insert into public.award_definitions (
        code, title, description, tier, garland_kind, rule_kind, period_kind,
        top_n, rank_basis, rotation_group, rotation_seat, sort_order
      ) values (
        v_period.code_prefix || v_deity.kind,
        v_deity.title,
        -- Identical for all seven, character for character. The Deity is named
        -- in the title and nowhere else, so no description can be read as
        -- saying one garland is worth more than another.
        'A garland from the altar, for the devotee at the top of the '
          || v_period.word
          || '. The seven garlands take turns, and not one of them stands above another.',
        'garland',
        v_deity.kind,
        'top_n',
        v_period.period_kind,
        1,
        'score',
        v_period.rotation_group,
        v_deity.seat,
        v_period.sort_order
      )
      on conflict (code) do nothing;
    end loop;
  end loop;
end;
$$;

-- The week's other three rungs, and the week's draw. Recognition already
-- exists weekly as 0055's 'weekly_recognition' — the median rule, which is the
-- one tier that cannot be competed for and the one the temple wants most of
-- its congregation standing in.
insert into public.award_definitions
  (code, title, description, tier, garland_kind, rule_kind, period_kind,
   threshold_quantile, top_n, rank_basis, rule_key, rotation_group,
   rotation_seat, sort_order)
values
  ('weekly_maha_prasad',
   'Maha Prasad',
   'A plate from the altar, for the three devotees who carried this week.',
   'maha_prasad', null, 'top_n', 'week', null, 3, 'score', null, null, null, 110),

  ('weekly_token',
   'Token of Appreciation',
   'For the ten devotees at the top of the week. Given for a week of service and giving, not for a total.',
   'token_of_appreciation', null, 'top_n', 'week', null, 10, 'score', null, null, null, 120),

  ('weekly_mystery_gift',
   'Mystery Gift',
   'Drawn at random from everyone who took part this week. Nothing you did made it more likely, and that is the point.',
   'token_of_appreciation', null, 'draw', 'week', null, null, null, null, null, null, 130)
on conflict (code) do nothing;

-- ---------------------------------------------------------------------------
-- 4. Whose turn it is.
--
--    The period index counts periods from a fixed origin, so the answer depends
--    on the period and on nothing else: the same closed week re-derives the
--    same garland however many times it is recomputed, in any year, on any
--    machine. 1970-01-05 is a Monday, which is the origin the week counts from
--    because 0055's week starts on Monday.
-- ---------------------------------------------------------------------------

create or replace function public.seva_mala_period_index(p_period_kind text, p_on date)
returns integer
language sql
immutable
set search_path = ''
as $$
  select case p_period_kind
    when 'week' then ((public.seva_mala_week_start(p_on) - date '1970-01-05') / 7)::integer
    when 'month' then ((extract(year from p_on)::integer - 1970) * 12
                       + extract(month from p_on)::integer - 1)
    when 'lifetime' then 0
  end
$$;

comment on function public.seva_mala_period_index(text, date) is
  'How many periods of this kind have begun since the origin. Counts weeks from Monday 5 January 1970 and months from January 1970, so a rotation lands on the same seat however often a period is recomputed.';

revoke all on function public.seva_mala_period_index(text, date) from public, anon, authenticated;

create or replace function public.award_rotation_turn(
  p_rotation_group text,
  p_period_kind text,
  p_starts_on date
)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select seat.id
  from (
    select
      definitions.id,
      row_number() over (
        order by definitions.rotation_seat, definitions.code
      ) - 1 as turn,
      count(*) over () as seats
    from public.award_definitions definitions
    where definitions.is_active
      and definitions.rotation_group = p_rotation_group
      and definitions.period_kind = p_period_kind
  ) seat
  where seat.seats > 0
    and seat.turn = public.seva_mala_period_index(p_period_kind, p_starts_on) % seat.seats
$$;

comment on function public.award_rotation_turn(text, text, date) is
  'Which member of a rotation group is offered in the period beginning on this date. Decided by the period index alone, so it is stable across recomputes; over one full cycle every active member is offered exactly once.';

revoke all on function public.award_rotation_turn(text, text, date) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 5. Awarding, restated whole, with the rotation in it.
--
--    Everything here is 202608040055 section 14 unchanged, plus the two guards
--    at the top of the loop. It is restated in full rather than wrapped,
--    because a wrapper around a rule this file needs to modify is a second
--    place for the rule to live.
--
--    Guard one: if the definition belongs to a rotation group, it is skipped
--    unless it is this period's turn.
--
--    Guard two, and it is the idempotency guard: if ANY member of the group has
--    already been awarded for this period, the whole group is skipped. The
--    unique index on (definition, devotee, period) already stops the same
--    garland being given twice — this stops a DIFFERENT garland being given for
--    the same week because somebody retired a definition between two runs and
--    shortened the cycle underneath it. Re-running a closed period must add
--    nothing, and "nothing" has to survive the config changing.
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
begin
  select * into v_period from public.seva_mala_periods where id = p_period_id;
  if v_period.id is null then
    return 0;
  end if;
  v_frozen := v_period.frozen_at is not null;

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
  'Hands out every non-discretionary award a period has earned. Rivalrous rules wait for the period to close, because nothing here is ever revoked. A rotation group has exactly one turn per period, and having had it once it is skipped on every later run.';

revoke all on function public.award_seva_mala_for_period(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 6. Which periods are currently on display.
--
--    Header section 3. One row per period kind: the most recent frozen period
--    of that kind that awarded anything. There is no state here and nothing to
--    expire — the answer changes the instant the next period is frozen and
--    awarded, because it is a query and not a stored date.
--
--    Not granted. It is the inside of the two functions below, and the period
--    bounds a devotee is entitled to come back on their own badges.
-- ---------------------------------------------------------------------------

create or replace function public.current_award_periods()
returns table (
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
  select distinct on (periods.period_kind)
    periods.id,
    periods.period_kind,
    periods.starts_on,
    periods.ends_on,
    periods.participant_count
  from public.seva_mala_periods periods
  where periods.frozen_at is not null
    and exists (
      select 1 from public.devotee_awards awards
      where awards.period_id = periods.id
    )
  order by periods.period_kind, periods.starts_on desc
$$;

comment on function public.current_award_periods() is
  'The most recent closed period of each kind that awarded anything — the periods whose badges are on public profiles right now. Computed rather than stored: a badge stops being public because the next leaderboard arrived, not because a job remembered to expire it.';

revoke all on function public.current_award_periods() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 7. A devotee's badges, as anybody may see them.
--
--    Name, tier, whose garland, and which period. There is no score column, no
--    points column, no place, no minutes and no cents, and there is nothing in
--    the return type for a later edit to widen into one.
--
--    Three ways a row is visible, and header section 4 is why:
--      it is your own                     — always
--      you hold app.view_all              — always
--      the devotee is on the board        — leaderboard_visible, the one switch
--
--    Plus the cohort gate on the period, which is 0055's rule about not
--    publishing a ranking of a congregation too small to be ranked.
-- ---------------------------------------------------------------------------

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
    current_periods.period_kind,
    current_periods.period_start,
    current_periods.period_end,
    awards.awarded_on
  from public.devotee_awards awards
  join public.award_definitions definitions
    on definitions.id = awards.award_definition_id
  join public.current_award_periods() current_periods
    on current_periods.period_id = awards.period_id
  join public.users devotee on devotee.id = awards.devotee_id
  where auth.uid() is not null
    and p_devotee_id is not null
    and awards.devotee_id = p_devotee_id
    and current_periods.participant_count
        >= public.seva_mala_number('seva_mala.minimum_cohort', 8)
    and (
      p_devotee_id = auth.uid()
      or devotee.leaderboard_visible
      or public.has_permission('app.view_all')
    )
  order by current_periods.period_start desc, definitions.code
$$;

comment on function public.list_devotee_badges(uuid) is
  'A devotee''s currently displayed badges, readable by any signed-in devotee: the gift, its tier, whose garland it was and which period it was for. Never a score, a place, an hour or a cent. A devotee who opted out of the board is not published here either — the badge is still earned, still on their shelf and still handed over.';

revoke all on function public.list_devotee_badges(uuid) from public, anon;
grant execute on function public.list_devotee_badges(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 8. The whole shelf.
--
--    Everything, forever, for the devotee themselves and for app.view_all.
--    Nothing here is filtered by period, by opt-out or by cohort: this is the
--    append-only record, and the fact that a badge is no longer on a public
--    profile does not mean it stopped happening.
--
--    is_current is the same predicate the public function applies, so the
--    President can see at a glance which of these a visitor to that profile
--    would find, without having to reason about it.
-- ---------------------------------------------------------------------------

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
      awards.period_id is not null
      and devotee.leaderboard_visible
      and exists (
        select 1
        from public.current_award_periods() current_periods
        where current_periods.period_id = awards.period_id
          and current_periods.participant_count
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
  'Every award a devotee ever earned, current or long expired, for the devotee themselves and for the President and the Tech Admin. is_current says whether the public can see it right now. Nothing is ever removed from this list.';

revoke all on function public.list_devotee_award_shelf(uuid) from public, anon;
grant execute on function public.list_devotee_award_shelf(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 9. Nothing here revokes, and the file refuses to have added a way.
--
--    Checked after the functions are created rather than before, so it is this
--    file's own work being audited. Anything that could remove an award had to
--    have been written above.
-- ---------------------------------------------------------------------------

do $$
declare
  v_offenders text;
begin
  select string_agg(proc.proname, ', ' order by proc.proname) into v_offenders
  from pg_proc proc
  join pg_namespace spaces on spaces.oid = proc.pronamespace
  where spaces.nspname = 'public'
    and proc.prokind = 'f'
    and (
      lower(pg_get_functiondef(proc.oid)) like '%delete from public.devotee_awards%'
      or lower(pg_get_functiondef(proc.oid)) like '%update public.devotee_awards%set%award_definition_id%'
    )
    and proc.proname <> 'devotee_awards_stay_append_only';

  if v_offenders is not null then
    raise exception
      'These functions can remove or rewrite an award: %. Nothing in this schema may revoke one.',
      v_offenders;
  end if;

  if not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.devotee_awards'::regclass
      and tgname = 'devotee_awards_append_only'
      and not tgisinternal
  ) then
    raise exception 'The append-only trigger did not survive this migration.';
  end if;

  if not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.devotee_awards'::regclass
      and tgname = 'devotee_award_announced'
      and not tgisinternal
  ) then
    raise exception
      'The trigger that tells a devotee they earned something is gone; every gift added by this file would land in silence.';
  end if;
end;
$$;

do $$
begin
  raise notice 'badges and gifts applied';
end;
$$;
