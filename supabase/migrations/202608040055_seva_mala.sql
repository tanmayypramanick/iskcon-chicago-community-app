-- Sevā Mālā — the garland of service.
--
-- A temple asked for a leaderboard. What it needs is a garland: a way of
-- noticing, out loud, that people are giving their hands and their money to
-- this place, without turning either into a scoreboard that money can win.
--
-- Everything in this file follows from three refusals.
--
--   1. Money must not buy the top. Giving counts, fully and honestly, but
--      both giving and seva are capped at the level of the congregation's own
--      generous end, and the two are combined so that the *smaller* of them
--      carries most of the weight. A devotee who gives $50,000 and no hours
--      cannot out-score a devotee who gives $500 and six evenings, because
--      once you are at the cap in one dimension the only way up is the other.
--
--   2. A big gift must not flatten everybody else. Normalising against the
--      maximum would do exactly that — one $100,000 gift at Diwali and four
--      hundred devotees are rounded to nothing. So the reference is a
--      percentile of the congregation, taken after a logarithm, shrunk toward
--      a trailing ninety-day figure so a quiet week does not invent a hero,
--      and floored so a thin period cannot make a tiny denominator.
--
--   3. Nobody may read anybody's giving out of this. public.period_scores is
--      not selectable by `authenticated` in any form, and that is not
--      defence in depth — it is the whole of the defence. giving_norm is
--      ĝ = ln(1 + G/v_g) / ref_g. A devotee who could read that column, and
--      who can work out v_g and ref_g by watching their own numbers move,
--      can solve for G to the dollar. That would quietly undo the row level
--      security on public.donations for every devotee in the congregation.
--      So the board returns POSITION OR TIER ONLY. No scores, no hours, no
--      dollars, ever, for anybody but yourself.
--
-- ---------------------------------------------------------------------------
-- The scoring, in full.
--
--   S  weighted, quality-adjusted, capped seva minutes in the period
--   G  donation cents in the period
--
--   u_s = ln(1 + S/v_s)      v_s = trailing-90-day median length of one seva
--   u_g = ln(1 + G/v_g)      v_g = trailing-90-day median gift
--
-- The logarithm is what makes a second hour worth less than the first and a
-- second thousand dollars worth less than the first. v_s and v_g are the
-- units it is taken in — "how many typical acts is this?" rather than "how
-- many minutes is this?" — and they are the congregation's own medians, so
-- the scale moves with the temple instead of with a constant somebody typed
-- in 2026. Fallbacks of 60 minutes and $25.00 apply only to an empty history.
--
--   ref = (n·ref_period + k·ref_trailing) / (n + k),  k = 12
--
-- where ref_period is the 80th percentile of u among devotees active in the
-- period and ref_trailing is the same percentile over the trailing ninety
-- days. Shrinkage is the fix for small n: in a week with four active
-- devotees the period's own 80th percentile is noise, and n=4 against k=12
-- means the trailing figure carries three quarters of the answer. By the time
-- forty devotees are active the period speaks for itself. The result is
-- floored at ln(2) — the utility of exactly one typical act — so that a
-- congregation that did almost nothing cannot produce a denominator small
-- enough to make one devotee's single hour look like the whole temple.
--
--   ŝ = least(1, u_s/ref_s)      ĝ = least(1, u_g/ref_g)
--
-- THE CAP IS THE POINT. It is what stops money buying the top. Reaching the
-- congregation's generous end is the whole of what can be reached; going
-- further is not rewarded, is not recorded as further, and cannot be seen.
--
--   score = (min(ŝ,ĝ) + β·max(ŝ,ĝ)) / (1 + β),   β = 0.5
--
-- Balance wins. With β = 0.5 the weaker side is worth twice the stronger. A
-- devotee at the cap in one dimension and zero in the other scores 1/3. Two
-- such devotees — the $2,500-only donor and the sixty-hours-only servant —
-- score exactly the same, which is the temple's position stated in
-- arithmetic: neither of you is more of a devotee than the other. A devotee
-- at the cap in both scores 1, three times either.
--
-- β and the percentile live in public.app_settings, not in a function body,
-- because they are the temple's dials and not ours.
--
-- ---------------------------------------------------------------------------
-- Seva is not all one thing.
--
-- Mangal arati setup at 4am in January and Sunday feast cleanup at 2pm are
-- both an hour of seva and are not the same hour. But a hardcoded table of
-- multipliers is a political document that goes stale and that somebody has
-- to defend. So the weight is measured, per service type, over a trailing
-- ninety days, from four things the temple's own records already know:
--
--   fill rate                 how often the slots posted actually get filled
--   declines per acceptance   how many people said no for each one who said yes
--   distinct servers          how few people are willing or able to do it
--   hour unusualness          how far its start times sit from the temple's own
--
-- Each is turned into a z-score across service types and combined as
-- clamp(1 + Σ γᵢzᵢ, 0.75, 1.75). The clamp matters as much as the formula:
-- the whole spread available to scarcity is 2.33×, while hours span whatever
-- devotees actually serve. Hours still dominate, and no amount of measured
-- scarcity turns twenty minutes into an evening. Custom-named seva, which by
-- definition has no history, is a neutral 1.0.
--
-- ---------------------------------------------------------------------------
-- Periods do not reset, and a score must survive its author.
--
-- Week (Monday-start, Chicago), month (Chicago), lifetime. Nothing resets:
-- a period is a query window over facts that carry occurred_on, and every
-- fact stays exactly where it was. What is stored per period is the reference
-- values, the units and the participant count, so that a score computed today
-- can be re-derived and argued about in a year — when v_g has moved, when the
-- congregation has doubled, when nobody remembers what the eightieth
-- percentile was in August. A closed period is frozen and never recomputed.
--
-- Requires 202608040048_donations.sql, 202608040050_sponsorship_campaigns.sql
-- and 202608040052_announcement_reactions.sql.

-- ---------------------------------------------------------------------------
-- 0. The ground this stands on.
--
--    Asserted rather than assumed. Every one of these is something a later
--    migration could quietly change out from under the scoring, and a scoring
--    system that is silently wrong is worse than one that is loudly broken.
-- ---------------------------------------------------------------------------

do $$
declare
  v_definition text;
  v_holders text;
begin
  select pg_get_constraintdef(pg_constraint.oid) into v_definition
  from pg_constraint
  where conname = 'app_notifications_kind_check'
    and conrelid = 'public.app_notifications'::regclass;

  if v_definition is null then
    raise exception
      'The app_notifications kind constraint is missing; apply the earlier migrations first.';
  end if;

  -- The list restated in section 12 is 0052's. If a migration between 0052 and
  -- here added a kind, restating 0052's list would outlaw it. Check the two
  -- most recently added rather than trusting the file ordering.
  if position('''announcement_comment_replied''' in v_definition) = 0
    or position('''sponsorship_fulfilled''' in v_definition) = 0
  then
    raise exception
      'app_notifications_kind_check is not the list 202608040052 left behind. Restate it whole, including every kind added since.';
  end if;

  -- app.view_all is what "the President and the Tech Admin" means everywhere
  -- in this codebase, and it is who may see a hidden devotee's score.
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
-- 1. The dials.
--
--    In app_settings, which is granted to nobody and read only by definer
--    functions, because these are the temple's numbers. A President who
--    decides balance should matter more changes balance_beta from 0.5 to 0.8
--    with an UPDATE, and the next nightly recompute obeys. No migration, no
--    deploy, no developer.
--
--    Seeded with ON CONFLICT DO NOTHING so re-applying this file never
--    stamps on a value the temple has since changed.
-- ---------------------------------------------------------------------------

insert into public.app_settings (key, value)
values
  ('seva_mala.balance_beta', '0.5'),
  ('seva_mala.reference_quantile', '0.80'),
  ('seva_mala.reference_shrink_k', '12'),
  -- ln(2): the utility of exactly one typical act. A reference lower than
  -- "one act" is not a reference, it is a division by almost zero.
  ('seva_mala.reference_floor', '0.6931471805599453'),
  ('seva_mala.trailing_days', '90'),
  ('seva_mala.seva_unit_fallback_minutes', '60'),
  ('seva_mala.giving_unit_fallback_cents', '2500'),
  ('seva_mala.daily_cap_minutes', '480'),
  ('seva_mala.weekly_cap_minutes', '1800'),
  ('seva_mala.minimum_cohort', '8'),
  ('seva_mala.weight_min', '0.75'),
  ('seva_mala.weight_max', '1.75'),
  ('seva_mala.weight_gamma_fill', '0.10'),
  ('seva_mala.weight_gamma_decline', '0.10'),
  ('seva_mala.weight_gamma_servers', '0.10'),
  ('seva_mala.weight_gamma_hour', '0.10')
on conflict (key) do nothing;

create or replace function public.seva_mala_number(p_key text, p_default numeric)
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (
      select nullif(trim(app_settings.value), '')::numeric
      from public.app_settings
      where app_settings.key = p_key
    ),
    p_default
  )
$$;

comment on function public.seva_mala_number(text, numeric) is
  'One Seva Mala dial, read from app_settings. A malformed value raises rather than being silently ignored: a scoring constant that quietly reverts to a default is a bug nobody finds.';

revoke all on function public.seva_mala_number(text, numeric) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. Chicago, and only Chicago.
--
--    The week starts on Monday in Chicago and the month is Chicago's month,
--    whatever timezone the phone asking is set to. A devotee travelling in
--    India must see the same week the temple office sees. Every boundary in
--    this file goes through these three functions and nowhere else.
--
--    Lifetime is a period like any other so that one code path computes all
--    three. It spans 1970 to 9999, which is to say it never ends, which is to
--    say it is never frozen and never carries a rivalrous award. A lifetime
--    that could be won would not be a lifetime.
-- ---------------------------------------------------------------------------

create or replace function public.seva_mala_today()
returns date
language sql
stable
set search_path = ''
as $$
  select (now() at time zone 'America/Chicago')::date
$$;

create or replace function public.seva_mala_week_start(p_on date)
returns date
language sql
immutable
set search_path = ''
as $$
  select p_on - (extract(isodow from p_on)::integer - 1)
$$;

comment on function public.seva_mala_week_start(date) is
  'The Monday of the week a Chicago date falls in. ISO day-of-week, so Sunday belongs to the week that began six days earlier.';

create or replace function public.seva_mala_period_start(p_period_kind text, p_on date)
returns date
language sql
immutable
set search_path = ''
as $$
  select case p_period_kind
    when 'week' then public.seva_mala_week_start(p_on)
    when 'month' then date_trunc('month', p_on::timestamp)::date
    when 'lifetime' then date '1970-01-01'
  end
$$;

create or replace function public.seva_mala_period_end(p_period_kind text, p_on date)
returns date
language sql
immutable
set search_path = ''
as $$
  select case p_period_kind
    when 'week' then public.seva_mala_week_start(p_on) + 6
    when 'month' then (date_trunc('month', p_on::timestamp) + interval '1 month' - interval '1 day')::date
    when 'lifetime' then date '9999-12-31'
  end
$$;

revoke all on function public.seva_mala_today() from public, anon;
revoke all on function public.seva_mala_week_start(date) from public, anon;
revoke all on function public.seva_mala_period_start(text, date) from public, anon;
revoke all on function public.seva_mala_period_end(text, date) from public, anon;
grant execute on function public.seva_mala_today() to authenticated;
grant execute on function public.seva_mala_week_start(date) to authenticated;
grant execute on function public.seva_mala_period_start(text, date) to authenticated;
grant execute on function public.seva_mala_period_end(text, date) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. What a period was, kept so it can be argued with later.
--
--    The scores in a frozen period are not reproducible from today's data —
--    v_g will have moved, the congregation will have grown, the eightieth
--    percentile will be somewhere else. So the inputs are written down beside
--    the outputs. A devotee who asks in June why they were second in
--    September gets an answer computed from September's numbers.
--
--    frozen_at is the close. A period whose last day is behind us is computed
--    once more and then never again, which is also what makes a rivalrous
--    award safe to hand out: it is decided on final numbers, not on a
--    Wednesday afternoon's.
-- ---------------------------------------------------------------------------

create table if not exists public.seva_mala_periods (
  id uuid primary key default gen_random_uuid(),
  period_kind text not null check (period_kind in ('week', 'month', 'lifetime')),
  starts_on date not null,
  ends_on date not null,
  -- The reference each dimension was scaled against, after shrinkage and
  -- flooring. This is the number that turns "u" into "ŝ".
  seva_reference numeric,
  giving_reference numeric,
  -- The unit each dimension was measured in: one typical act, one typical gift.
  seva_unit_minutes numeric,
  giving_unit_cents numeric,
  -- How many devotees were active at all. Below the minimum cohort the board
  -- does not publish, and this is the number that decides it.
  participant_count integer not null default 0,
  computed_at timestamptz,
  frozen_at timestamptz,
  constraint seva_mala_period_order check (ends_on >= starts_on),
  constraint seva_mala_period_unique unique (period_kind, starts_on)
);

comment on table public.seva_mala_periods is
  'One row per scoring window. Nothing resets — a period is a query over facts carrying occurred_on — but what the window was scaled against is written down so a score stays auditable a year later.';

create index if not exists seva_mala_periods_kind_start_idx
  on public.seva_mala_periods (period_kind, starts_on desc);

create index if not exists seva_mala_periods_open_idx
  on public.seva_mala_periods (ends_on) where frozen_at is null;

-- ---------------------------------------------------------------------------
-- 4. The scores, and the reason nobody may read them.
--
--    Read the header again if you are about to grant anything here.
--    giving_norm plus a knowable giving_reference inverts to a dollar figure:
--
--        G = v_g · (exp(ĝ · ref_g) − 1)
--
--    and v_g and ref_g are learnable by anyone patient enough to watch their
--    own numbers move across a few weeks. A devotee who can SELECT this table
--    can read the congregation's giving to the dollar, and public.donations'
--    row level security becomes decoration.
--
--    So: row level security on, with no SELECT policy for authenticated at
--    all, and every privilege revoked from public, anon and authenticated.
--    Not "a policy that filters to your own row" — no policy, because a
--    policy is a thing somebody can widen later without noticing what it
--    guards. The only ways in are the RPCs in sections 13 to 17, each of
--    which strips the components before returning anything about anybody but
--    the caller.
-- ---------------------------------------------------------------------------

create table if not exists public.period_scores (
  id uuid primary key default gen_random_uuid(),
  period_id uuid not null references public.seva_mala_periods(id) on delete cascade,
  devotee_id uuid not null references public.users(id) on delete cascade,
  -- Credited minutes after the daily and weekly caps, before quality and
  -- scarcity weighting. "How long were you actually here."
  credited_minutes numeric not null default 0,
  -- S: the same minutes after quality and scarcity. What the log is taken of.
  seva_minutes numeric not null default 0,
  seva_acts integer not null default 0,
  giving_cents bigint not null default 0,
  gifts integer not null default 0,
  seva_utility numeric not null default 0,
  giving_utility numeric not null default 0,
  seva_norm numeric not null default 0,
  giving_norm numeric not null default 0,
  score numeric not null default 0,
  computed_at timestamptz not null default now(),
  constraint period_scores_unique unique (period_id, devotee_id)
);

comment on table public.period_scores is
  'NEVER selectable by authenticated. giving_norm plus a knowable giving_reference inverts to the devotee''s exact giving, which would defeat the row level security on public.donations. Reachable only through the RPCs in this migration.';

create index if not exists period_scores_period_score_idx
  on public.period_scores (period_id, score desc);

create index if not exists period_scores_devotee_idx
  on public.period_scores (devotee_id);

-- ---------------------------------------------------------------------------
-- 5. Measured scarcity, per service type.
--
--    Recomputed with the scores. A type with no history in the window is
--    absent from this table and reads as 1.0, which is also what a
--    custom-named seva gets: neutral, because we have measured nothing and
--    guessing would be worse than not weighting at all.
-- ---------------------------------------------------------------------------

create table if not exists public.seva_type_weights (
  service_type_id uuid primary key
    references public.service_types(id) on delete cascade,
  weight numeric not null,
  fill_rate numeric,
  declines_per_acceptance numeric,
  distinct_servers integer,
  hour_unusualness numeric,
  computed_at timestamptz not null default now(),
  constraint seva_type_weight_range check (weight between 0.5 and 2.5)
);

comment on table public.seva_type_weights is
  'Measured, never declared. Fill rate, declines per acceptance, distinct servers and how far this seva''s hours sit from the temple''s own, over a trailing ninety days, clamped so hours still dominate.';

-- ---------------------------------------------------------------------------
-- 6. Opting out of being seen, not out of being counted.
--
--    Default false, so nobody appears on a board they never asked to be on.
--    And opting out is DISPLAY ONLY: the score is computed, the awards are
--    earned, the garland is handed over in person. A devotee who does not
--    want their name on a list has not withdrawn from the congregation, and
--    an implementation that quietly stopped scoring them would be punishing
--    them for a preference.
--
--    Readable — it is not a secret, and the client needs to draw the toggle
--    in the right position. Writable only through set_my_leaderboard_visibility,
--    because the UPDATE grant on public.users names its columns and this is
--    not one of them.
-- ---------------------------------------------------------------------------

alter table public.users
  add column if not exists leaderboard_visible boolean not null default false;

comment on column public.users.leaderboard_visible is
  'Whether this devotee appears on the Seva Mala garland. Default false. Display only — scores and awards are computed for everyone, always.';

-- ---------------------------------------------------------------------------
-- 7. What the temple gives back.
--
--    A table and not a CHECK constraint, so the President can retire the
--    Mystery Gift, add a fourth garland or rename Recognition on a Tuesday
--    without a migration and without us.
--
--    Four tiers. Recognition, Token of Appreciation, Maha Prasad, and a
--    Garland. The three garlands are LATERAL, not ranked: the Seva garland is
--    for hands, the Dana garland for giving, the Samatva garland for balance,
--    and there is no ordering among them because there is no ordering among
--    what they are for. That is why they are three rows with three rank_basis
--    values rather than one award with three grades.
--
--    Five rule kinds:
--
--      derived_threshold  non-rivalrous. "You reached the level of the
--                         congregation's median active devotee." Everybody who
--                         reaches it gets it; nobody loses it because somebody
--                         else arrived. This is the tier the temple wants most
--                         of its people in, and it cannot be competed for.
--      top_n              rivalrous. Decided only when a period closes — see
--                         section 11.
--      personal           against your own past. Firsts and personal bests.
--      discretionary      the President's, and algorithm-untouchable. No
--                         recompute ever creates or considers one of these.
--      draw               the Mystery Gift. Random among every participant,
--                         which is the one award a devotee cannot influence
--                         and therefore the one nobody can be resented for.
-- ---------------------------------------------------------------------------

create table if not exists public.award_definitions (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  title text not null,
  description text not null,
  tier text not null check (
    tier in ('recognition', 'token_of_appreciation', 'maha_prasad', 'garland')
  ),
  -- Which garland, when it is one. Lateral: no order is implied or stored.
  garland_kind text check (garland_kind in ('seva', 'dana', 'samatva')),
  rule_kind text not null check (
    rule_kind in ('derived_threshold', 'top_n', 'personal', 'discretionary', 'draw')
  ),
  period_kind text not null check (period_kind in ('week', 'month', 'lifetime')),
  -- derived_threshold: the quantile of active devotees you must reach. 0.5 is
  -- "the median active devotee", which is the phrasing the temple uses.
  threshold_quantile numeric check (
    threshold_quantile is null or (threshold_quantile > 0 and threshold_quantile < 1)
  ),
  top_n integer check (top_n is null or top_n between 1 and 100),
  -- What top_n ranks by. This is what makes the garlands lateral.
  rank_basis text check (rank_basis in ('score', 'seva', 'giving')),
  -- Which personal rule, among the ones this migration implements.
  rule_key text check (rule_key in ('first_seva', 'personal_best')),
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint award_garland_kind_matches_tier check (
    (tier = 'garland') = (garland_kind is not null)
  ),
  constraint award_threshold_rule_complete check (
    rule_kind <> 'derived_threshold' or threshold_quantile is not null
  ),
  constraint award_top_n_rule_complete check (
    rule_kind <> 'top_n' or (top_n is not null and rank_basis is not null)
  ),
  constraint award_personal_rule_complete check (
    rule_kind <> 'personal' or rule_key is not null
  ),
  constraint award_title_not_blank check (length(trim(title)) between 2 and 80)
);

comment on table public.award_definitions is
  'What the temple gives, and on what rule. A table rather than a constraint so the President can change the awards without a migration. The three garlands are lateral — rank_basis distinguishes them, nothing ranks them.';

insert into public.award_definitions
  (code, title, description, tier, garland_kind, rule_kind, period_kind,
   threshold_quantile, top_n, rank_basis, rule_key, sort_order)
values
  ('weekly_recognition',
   'Recognition',
   'You reached the level of the congregation''s median active devotee this week.',
   'recognition', null, 'derived_threshold', 'week', 0.5, null, null, null, 10),

  ('monthly_recognition',
   'Recognition',
   'You reached the level of the congregation''s median active devotee this month.',
   'recognition', null, 'derived_threshold', 'month', 0.5, null, null, null, 20),

  ('monthly_token',
   'Token of Appreciation',
   'You stood among the more giving three-quarters of the congregation this month.',
   'token_of_appreciation', null, 'derived_threshold', 'month', 0.75, null, null, null, 30),

  ('monthly_maha_prasad',
   'Maha Prasad',
   'A plate from the altar, for ten devotees who carried this month.',
   'maha_prasad', null, 'top_n', 'month', null, 10, 'score', null, 40),

  ('garland_seva',
   'Sevā Garland',
   'For hands. Given to three devotees whose service carried the temple this month.',
   'garland', 'seva', 'top_n', 'month', null, 3, 'seva', null, 50),

  ('garland_dana',
   'Dāna Garland',
   'For giving. Given to three devotees whose generosity carried the temple this month.',
   'garland', 'dana', 'top_n', 'month', null, 3, 'giving', null, 51),

  ('garland_samatva',
   'Samatva Garland',
   'For balance. Given to three devotees who gave both their hands and their means this month.',
   'garland', 'samatva', 'top_n', 'month', null, 3, 'score', null, 52),

  ('mystery_gift',
   'Mystery Gift',
   'Drawn at random from everyone who took part this month. Nothing you did made it more likely, and that is the point.',
   'token_of_appreciation', null, 'draw', 'month', null, null, null, null, 60),

  ('first_seva',
   'Your First Seva',
   'The first time you served. There is only one of these.',
   'recognition', null, 'personal', 'lifetime', null, null, null, 'first_seva', 70),

  ('personal_best_month',
   'Your Best Month',
   'Your own highest month so far. Measured against nobody but yourself.',
   'token_of_appreciation', null, 'personal', 'month', null, null, null, 'personal_best', 80),

  ('presidents_gift',
   'The President''s Gift',
   'Given by the President, for something an algorithm would never have seen.',
   'maha_prasad', null, 'discretionary', 'lifetime', null, null, null, null, 90)
on conflict (code) do nothing;

-- ---------------------------------------------------------------------------
-- 8. What was given, to whom, and whether it has actually been handed over.
--
--    Append-only. An award is a thing the temple said out loud; it is not a
--    state that can be corrected into non-existence because a recompute later
--    disagreed. Nothing here is ever auto-revoked — not when a devotee's
--    score falls, not when a later recompute would have chosen somebody else,
--    not when the President retires the award. The trigger in section 9
--    enforces that against every path, including a future function nobody has
--    written yet.
--
--    fulfilled_on and fulfilment_note mirror public.sponsorship_bookings
--    deliberately and exactly, because a garland is a physical object that
--    somebody has to actually make and actually hand over, and the temple
--    already has one vocabulary for "we said we would and then we did".
-- ---------------------------------------------------------------------------

create table if not exists public.devotee_awards (
  id uuid primary key default gen_random_uuid(),
  award_definition_id uuid not null
    references public.award_definitions(id) on delete restrict,
  devotee_id uuid not null references public.users(id) on delete cascade,
  -- Null for a discretionary award, which belongs to a moment and not a window.
  period_id uuid references public.seva_mala_periods(id) on delete set null,
  awarded_on date not null default (now() at time zone 'America/Chicago')::date,
  awarded_by uuid references public.users(id),
  citation text,
  fulfilled_on date,
  fulfilment_note text,
  created_at timestamptz not null default now(),
  constraint devotee_award_note_needs_fulfilment check (
    fulfilment_note is null or fulfilled_on is not null
  ),
  constraint devotee_award_citation_shape check (
    citation is null or length(trim(citation)) between 2 and 500
  )
);

comment on table public.devotee_awards is
  'Append-only. Never auto-revoked. fulfilled_on and fulfilment_note mirror sponsorship_bookings because a garland is a physical thing somebody has to hand over.';

-- One automatic award per definition per devotee per period. This is what
-- makes recompute idempotent: a second run of the same closed month re-derives
-- the same winners and inserts nothing. Discretionary awards carry a null
-- period_id, nulls are distinct in a unique index, and so the President may
-- give the same gift to the same devotee twice — which is correct, because
-- that is a second occasion and not a duplicate.
create unique index if not exists devotee_awards_one_per_period
  on public.devotee_awards (award_definition_id, devotee_id, period_id)
  where period_id is not null;

create index if not exists devotee_awards_devotee_idx
  on public.devotee_awards (devotee_id, awarded_on desc);

create index if not exists devotee_awards_period_idx
  on public.devotee_awards (period_id);

create index if not exists devotee_awards_unfulfilled_idx
  on public.devotee_awards (awarded_on) where fulfilled_on is null;

-- ---------------------------------------------------------------------------
-- 9. Append-only, enforced rather than promised.
--
--    Two columns may ever change, and only from null: fulfilled_on and
--    fulfilment_note, and the note only alongside the date. Everything else
--    is history. DELETE is refused outright — including by a superuser at a
--    psql prompt, which is the point: the temple should have to think about
--    what it is doing rather than discovering afterwards that a script tidied
--    away six months of garlands.
-- ---------------------------------------------------------------------------

create or replace function public.devotee_awards_stay_append_only()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'An award that was given cannot be taken back. devotee_awards is append-only.';
  end if;

  if new.id is distinct from old.id
    or new.award_definition_id is distinct from old.award_definition_id
    or new.devotee_id is distinct from old.devotee_id
    or new.period_id is distinct from old.period_id
    or new.awarded_on is distinct from old.awarded_on
    or new.awarded_by is distinct from old.awarded_by
    or new.citation is distinct from old.citation
    or new.created_at is distinct from old.created_at
  then
    raise exception 'Only fulfilment may be recorded against an award that was already given.';
  end if;

  if old.fulfilled_on is not null and new.fulfilled_on is distinct from old.fulfilled_on then
    raise exception 'This award was already recorded as fulfilled on %.',
      to_char(old.fulfilled_on, 'FMDD FMMonth YYYY');
  end if;

  return new;
end;
$$;

drop trigger if exists devotee_awards_append_only on public.devotee_awards;
create trigger devotee_awards_append_only
  before update or delete on public.devotee_awards
  for each row execute function public.devotee_awards_stay_append_only();

-- ---------------------------------------------------------------------------
-- 10. Every act of seva, credited.
--
--     Nothing in this schema aggregated minutes before now. Seva reaches
--     public.service_assignments by three roads and this function is where
--     they meet:
--
--       posted seva      a devotee joined, accepted an offer, was placed on a
--                        recurring template, or took a coverage offer. The
--                        instance carries the planned duration.
--       a live timer     public.service_qr_sessions, started by QR or from
--                        the list, which on completion writes an instance
--                        whose duration is the elapsed time and an assignment
--                        beside it. auto_completed lives on the session.
--       member-verified  public.service_verifications, approved by another
--                        devotee, which writes an instance and an assignment.
--
--     Credited minutes are least(planned, actual where known). Never the
--     larger: a devotee who booked two hours and left after forty minutes
--     served forty minutes, and a devotee who booked two hours and stayed
--     four has the temple's gratitude and two hours of credit, because the
--     alternative is a timer nobody switched off becoming a leaderboard.
--
--     QUALITY, in the order the cases are tested — order matters, because a
--     no-show with an attendance mark and a self-report with none must not be
--     decided by whichever branch happened to come first:
--
--       status no_show or withdrawn            0     they did not serve
--       attendance absent or excused           0     somebody says they did not
--       neither completed nor marked served    0     nobody has said they did
--       self_report with no attendance mark    0.6   only they say so
--       live_timer that auto-completed         0.7   a timer nobody stopped
--       everything else                        1.0
--
--     The third case is not in the specification and is here because without
--     it the specification has a hole: an assignment on a seva that happened
--     last Tuesday, still sitting at 'assigned' because nobody closed it out,
--     would otherwise be credited at 0.6 for simply having been signed up
--     for. Signing up is not serving. It is written as a distinct branch
--     rather than a WHERE clause so that explain_my_score can show a devotee
--     the act and the zero beside it, which is the honest answer to "why
--     didn't Tuesday count" — and the fix is for somebody to mark it, not for
--     us to guess.
--
--     THE CAPS. Eight credited hours in a Chicago day, thirty in a Chicago
--     week. These bound the raw minutes, before quality and before weighting,
--     because they are a claim about the physical day: nobody serves nine
--     hours, and a system that will believe they did is a system somebody
--     will eventually feed. A zero-quality act consumes no cap at all — being
--     marked absent must not also spend the eight hours you might genuinely
--     have served later that day.
--
--     The factors are proportional rather than a running total that stops at
--     the limit, so the cap does not depend on the order rows come back in,
--     and so a devotee who is capped keeps the shape of their day: an hour of
--     4am deity worship and an hour of Sunday cleanup are scaled together,
--     not sorted so the weighted one survives. The weekly factor is applied
--     over day-capped minutes, so the two caps compose instead of competing.
--
--     Caps are a property of the day and the week, never of the period, so
--     this function windows nothing. A caller filters occurred_on afterwards
--     and gets the same answer for a week whether it is asked about on its
--     own or as part of a month.
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
  weighted_minutes numeric
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
      case
        when assignments.status in ('no_show', 'withdrawn') then 0
        when assignments.attendance in ('absent', 'excused') then 0
        when assignments.status <> 'completed'
          and assignments.attendance is distinct from 'served' then 0
        when assignments.verification = 'self_report'
          and assignments.attendance is null then 0.6
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
      * day_factors.day_factor * week_factors.week_factor
  from billable
  join day_factors
    on day_factors.devotee_id = billable.devotee_id
   and day_factors.occurred_on = billable.occurred_on
  join week_factors
    on week_factors.devotee_id = billable.devotee_id
   and week_factors.week_start = public.seva_mala_week_start(billable.occurred_on)
$$;

comment on function public.seva_mala_acts(uuid) is
  'Every past act of seva with its credited minutes, quality multiplier, scarcity weight and cap factors. Windows nothing: the caps belong to the day and the week, so a caller filters occurred_on and gets the same answer whichever period it asks about.';

revoke all on function public.seva_mala_acts(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 11. Scarcity, measured.
--
--     Four z-scores across service types, over a trailing ninety days, each
--     signed so that positive means scarce:
--
--       fill rate            negated. Slots that go unfilled are the temple
--                            asking and nobody answering.
--       declines/acceptance  as is. Ten people said no before one said yes.
--       distinct servers     negated. Three people in the whole congregation
--                            know how to do it.
--       hour unusualness     as is, and already an absolute value. Measured
--                            against the temple's OWN distribution of start
--                            times, not against a notion of what an unsociable
--                            hour is — a temple whose life begins at 4am has
--                            no unsociable 4am.
--
--     weight = clamp(1 + Σ γᵢzᵢ, 0.75, 1.75) with each γ at 0.10, so a type
--     that is two standard deviations scarce on all four reaches the ceiling
--     and nothing reaches further. The whole available spread is 2.33×.
--     An hour is an hour is an hour, and this only ever tilts it.
--
--     A type with fewer than two comparable siblings has no z-scores to speak
--     of — stddev over one value is null — and comes out at exactly 1.0,
--     which is right: with nothing to compare against, scarcity is not a
--     measurement, it is an opinion.
-- ---------------------------------------------------------------------------

create or replace function public.recompute_seva_type_weights()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_from date;
  v_to date;
  v_written integer;
begin
  v_to := public.seva_mala_today();
  v_from := v_to - (public.seva_mala_number('seva_mala.trailing_days', 90)::integer - 1);

  with windowed as (
    select instances.*
    from public.service_instances instances
    where instances.date between v_from and v_to
      and instances.status <> 'cancelled'
      and instances.service_type_id is not null
  ),
  temple_hours as (
    -- The temple's own clock. One row.
    select
      avg(extract(hour from windowed.start_time))::numeric as mean_hour,
      nullif(stddev_samp(extract(hour from windowed.start_time)), 0)::numeric as sd_hour
    from windowed
  ),
  per_type as (
    select
      windowed.service_type_id,
      sum(windowed.slots_needed)::numeric as slots_needed,
      sum(
        (
          select count(*)
          from public.service_assignments filled
          where filled.service_instance_id = windowed.id
            and filled.status not in ('withdrawn', 'no_show')
        )
      )::numeric as slots_filled,
      sum(
        (
          select count(*) from public.service_offers offers
          where offers.service_instance_id = windowed.id
            and offers.status = 'declined'
        )
      )::numeric as declines,
      sum(
        (
          select count(*) from public.service_offers offers
          where offers.service_instance_id = windowed.id
            and offers.status = 'accepted'
        )
      )::numeric as acceptances,
      count(distinct servers.devotee_id)::integer as distinct_servers,
      avg(extract(hour from windowed.start_time))::numeric as mean_hour
    from windowed
    left join public.service_assignments servers
      on servers.service_instance_id = windowed.id
     and servers.status not in ('withdrawn', 'no_show')
    group by windowed.service_type_id
  ),
  metrics as (
    select
      per_type.service_type_id,
      case
        when per_type.slots_needed > 0
          then least(1.0, per_type.slots_filled / per_type.slots_needed)
        else 1.0
      end as fill_rate,
      -- Declines per acceptance. A type nobody has ever accepted but has been
      -- offered is as scarce as the declines say; the +1 keeps it finite.
      per_type.declines / (per_type.acceptances + 1) as declines_per_acceptance,
      per_type.distinct_servers,
      case
        when temple_hours.sd_hour is null then 0::numeric
        else abs((per_type.mean_hour - temple_hours.mean_hour) / temple_hours.sd_hour)
      end as hour_unusualness
    from per_type cross join temple_hours
  ),
  spread as (
    select
      avg(fill_rate) as fill_mean,
      nullif(stddev_samp(fill_rate), 0) as fill_sd,
      avg(declines_per_acceptance) as decline_mean,
      nullif(stddev_samp(declines_per_acceptance), 0) as decline_sd,
      avg(distinct_servers::numeric) as servers_mean,
      nullif(stddev_samp(distinct_servers::numeric), 0) as servers_sd,
      avg(hour_unusualness) as hour_mean,
      nullif(stddev_samp(hour_unusualness), 0) as hour_sd
    from metrics
  ),
  scored as (
    select
      metrics.*,
      -- Negated: a low fill rate is scarcity.
      coalesce(-((metrics.fill_rate - spread.fill_mean) / spread.fill_sd), 0)
        * public.seva_mala_number('seva_mala.weight_gamma_fill', 0.10)
      + coalesce(
          (metrics.declines_per_acceptance - spread.decline_mean) / spread.decline_sd, 0)
        * public.seva_mala_number('seva_mala.weight_gamma_decline', 0.10)
      -- Negated: few servers is scarcity.
      + coalesce(
          -((metrics.distinct_servers::numeric - spread.servers_mean) / spread.servers_sd), 0)
        * public.seva_mala_number('seva_mala.weight_gamma_servers', 0.10)
      + coalesce(
          (metrics.hour_unusualness - spread.hour_mean) / spread.hour_sd, 0)
        * public.seva_mala_number('seva_mala.weight_gamma_hour', 0.10)
        as tilt
    from metrics cross join spread
  )
  insert into public.seva_type_weights as target (
    service_type_id, weight, fill_rate, declines_per_acceptance,
    distinct_servers, hour_unusualness, computed_at
  )
  select
    scored.service_type_id,
    round(
      least(
        public.seva_mala_number('seva_mala.weight_max', 1.75),
        greatest(
          public.seva_mala_number('seva_mala.weight_min', 0.75),
          1 + scored.tilt
        )
      ),
      4
    ),
    round(scored.fill_rate, 4),
    round(scored.declines_per_acceptance, 4),
    scored.distinct_servers,
    round(scored.hour_unusualness, 4),
    now()
  from scored
  on conflict (service_type_id) do update
  set weight = excluded.weight,
      fill_rate = excluded.fill_rate,
      declines_per_acceptance = excluded.declines_per_acceptance,
      distinct_servers = excluded.distinct_servers,
      hour_unusualness = excluded.hour_unusualness,
      computed_at = excluded.computed_at;

  get diagnostics v_written = row_count;

  -- A type with no history in the window keeps no stale weight from three
  -- months ago; it goes back to neutral.
  delete from public.seva_type_weights
  where computed_at < now() - interval '1 second'
    and service_type_id not in (
      select service_type_id from public.service_instances
      where date between v_from and v_to and service_type_id is not null
    );

  return v_written;
end;
$$;

comment on function public.recompute_seva_type_weights() is
  'Measures how scarce each kind of seva is over a trailing ninety days and stores a clamped multiplier. Never a hardcoded table.';

revoke all on function public.recompute_seva_type_weights() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 12. Finding or making a period.
-- ---------------------------------------------------------------------------

create or replace function public.ensure_seva_mala_period(
  p_period_kind text,
  p_on date default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_on date := coalesce(p_on, public.seva_mala_today());
  v_start date;
  v_end date;
  v_id uuid;
begin
  if p_period_kind not in ('week', 'month', 'lifetime') then
    raise exception 'A Seva Mala period is a week, a month, or a lifetime.';
  end if;

  v_start := public.seva_mala_period_start(p_period_kind, v_on);
  v_end := public.seva_mala_period_end(p_period_kind, v_on);

  insert into public.seva_mala_periods (period_kind, starts_on, ends_on)
  values (p_period_kind, v_start, v_end)
  on conflict (period_kind, starts_on) do nothing;

  select id into v_id from public.seva_mala_periods
  where period_kind = p_period_kind and starts_on = v_start;

  return v_id;
end;
$$;

revoke all on function public.ensure_seva_mala_period(text, date) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 13. The recompute.
--
--     One period. Everything the header describes, in order, with the working
--     kept in public.period_scores itself rather than a temp table so the
--     intermediate values are the ones a devotee is later shown.
--
--     A frozen period returns immediately. A period that has not begun
--     returns immediately. Everything else is deleted and rebuilt, because a
--     score is a function of the facts and the facts can change underneath it
--     — a coordinator marking last Tuesday's attendance on Thursday must move
--     Tuesday's numbers.
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

  -- -------------------------------------------------------------------------
  -- The units. One typical act, one typical gift, over the trailing window
  -- ending where this period ends — so a frozen September is measured in
  -- September's units and stays measured in them.
  --
  -- MEDIAN OF MEDIANS, and this is not fussiness. The obvious reading of "the
  -- trailing-90-day median gift" is the median over every gift in the window,
  -- and it has a hole in it big enough to drive the whole feature through:
  --
  --   the units are the only per-TRANSACTION statistic in the scoring, and
  --   one donor can move them on their own.
  --
  -- A devotee who gives $50 as fifty separate one-dollar gifts does not change
  -- their own G by a cent — the totals below are immune, exactly as designed —
  -- but they drag the population median gift from $175 to $1, and every u_g in
  -- the congregation is computed in the new unit. The verification script found
  -- this by doing it: fifty one-dollar gifts raised that devotee's score from
  -- 0.229 to 0.425 without their giving a penny more. The same hole exists on
  -- the seva side for anybody willing to log a thousand one-minute acts.
  --
  -- So the population statistic is taken over ONE VALUE PER PERSON: each
  -- devotee's own median act, each donor's own median gift, and then the median
  -- across people. Splitting a gift now moves only the splitter's own single
  -- contribution to the population figure, which is the most any one person is
  -- allowed to move it. "Points from period totals only" is thereby true of the
  -- whole computation rather than only of its last step.
  --
  -- The temple's honest reading of "median gift" is unharmed: when everybody
  -- gives once, which is the normal case, the median of medians IS the median.
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
  -- which is the whole of the anti-gaming answer to micro-donations: a
  -- hundred one-dollar gifts and one hundred-dollar gift are the same G, so
  -- there is nothing to be gained by splitting.
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
  -- least(1, ...) is the load-bearing expression in this entire migration.
  -- Rounded to six places before it is ranked so that two devotees who are
  -- genuinely equal are stored as equal and share a position, rather than
  -- being separated by the last bit of a numeric.
  -- -------------------------------------------------------------------------
  update public.period_scores
  set seva_norm = round(least(1.0, period_scores.seva_utility / v_ref_seva), 6),
      giving_norm = round(least(1.0, period_scores.giving_utility / v_ref_giving), 6),
      computed_at = now()
  where period_scores.period_id = v_period.id;

  update public.period_scores
  set score = round(
        (
          least(period_scores.seva_norm, period_scores.giving_norm)
          + v_beta * greatest(period_scores.seva_norm, period_scores.giving_norm)
        ) / (1 + v_beta),
        6
      )
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
  'Rebuilds one period from the facts: units, totals, compression, references, cap and balance. Frozen periods are left alone.';

revoke all on function public.recompute_seva_mala_period(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 14. Awarding.
--
--     Split by whether the rule is rivalrous, because "never auto-revoked"
--     and "decided while the period is still running" cannot both be true.
--
--       derived_threshold, personal   fire on any recompute. Reaching the
--                                     median does not stop being true because
--                                     somebody else also reached it, so a
--                                     devotee sees their Recognition on
--                                     Wednesday and keeps it.
--
--       top_n, draw                   fire only when the period is frozen.
--                                     Handing a garland to whoever happens to
--                                     be third on a Wednesday, and then never
--                                     taking it back, would put nine garlands
--                                     on a three-garland month.
--
--     Lifetime never freezes, so lifetime carries no rivalrous award, which
--     is why the only lifetime definition seeded above is a personal one and
--     the President's discretionary gift.
--
--     Everybody is considered, including devotees who have opted out of the
--     board. Opting out is display; it is not withdrawal, and a devotee who
--     does not want their name on a list still made the garlands the temple
--     will hand over.
--
--     The draw is seeded from the period id, so it is decided once and stays
--     decided: a second recompute of the same frozen month re-derives the same
--     winner rather than drawing again, and the unique index would refuse the
--     second row anyway.
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
      -- The first act of seva anybody ever credited to them falls inside this
      -- window. Asked of the facts rather than of a flag, so it is still true
      -- after a backfill and cannot be earned twice.
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
      -- Their own highest period of this kind, and only once they have a past
      -- to beat. A first month is not a personal best, it is a first month.
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
  'Hands out every non-discretionary award a period has earned. Rivalrous rules wait for the period to close, because nothing here is ever revoked.';

revoke all on function public.award_seva_mala_for_period(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 15. Telling a devotee.
--
--     A trigger rather than a line in each of the two award paths, so a rule
--     added later cannot forget. After insert only: recording that a garland
--     was finally handed over is not a second award.
-- ---------------------------------------------------------------------------

create or replace function public.announce_devotee_award()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_definition public.award_definitions;
begin
  select * into v_definition from public.award_definitions
  where id = new.award_definition_id;

  perform public.queue_app_notification(
    new.devotee_id,
    'seva_award_earned',
    v_definition.title,
    coalesce(new.citation, v_definition.description),
    jsonb_build_object(
      'awardId', new.id,
      'awardCode', v_definition.code,
      'tier', v_definition.tier,
      'garlandKind', v_definition.garland_kind,
      'periodId', new.period_id
    )
  );

  return null;
end;
$$;

drop trigger if exists devotee_award_announced on public.devotee_awards;
create trigger devotee_award_announced
  after insert on public.devotee_awards
  for each row execute function public.announce_devotee_award();

-- ---------------------------------------------------------------------------
-- 16. The kind, restated whole.
--
--     The list below is 202608040052_announcement_reactions.sql's — the most
--     recent migration to declare this constraint — plus seva_award_earned.
--     Restating a shorter list would outlaw every kind added since, which has
--     broken this repository before. Section 0 asserts that the constraint
--     found here is in fact 0052's before this runs.
--
--     src/features/notifications/types.ts must learn 'seva_award_earned' too.
--     This migration does not own that file.
-- ---------------------------------------------------------------------------

alter table public.app_notifications
  drop constraint if exists app_notifications_kind_check;

alter table public.app_notifications
  add constraint app_notifications_kind_check check (
    kind in (
      'service_open', 'service_offer', 'service_recurring_offer',
      'service_offer_response', 'service_joined', 'service_left',
      'service_started', 'service_completed', 'service_cancelled',
      'service_deleted', 'service_coverage_needed',
      'service_coverage_resolved', 'recurring_interest_submitted',
      'recurring_interest_reviewed',
      'seva_verification_requested', 'seva_verification_reviewed',
      'weekly_offer_countered', 'weekly_offer_counter_reviewed',
      'access_request_submitted', 'access_request_reviewed',
      'devotee_joined', 'profile_incomplete',
      'sanga_created', 'sanga_reviewed',
      'sanga_join_requested', 'sanga_join_reviewed',
      'sanga_member_added', 'sanga_member_removed', 'sanga_member_left',
      'sanga_admin_transferred', 'sanga_deleted',
      'announcement_posted',
      'feedback_reviewed',
      'care_reply',
      'birthday_today',
      'newsletter_posted',
      'newsletter_reviewed',
      'access_appointed',
      'access_revoked',
      'sponsorship_fulfilled',
      'announcement_commented',
      'announcement_comment_replied',
      'seva_award_earned',
      'remote'
    )
  );

-- ---------------------------------------------------------------------------
-- 17. The whole job.
--
--     Ensures today's three periods and yesterday's week and month — the
--     latter so that a week which closed at midnight is computed and frozen
--     on the first run of the new week rather than being missed — then
--     recomputes every period that is not yet frozen.
--
--     Backend only. A devotee who could call this could not change their own
--     score by doing so, but they could make the temple's database do a
--     hundred percentile scans on request.
-- ---------------------------------------------------------------------------

create or replace function public.recompute_seva_mala()
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

  perform public.recompute_seva_type_weights();

  perform public.ensure_seva_mala_period('lifetime', v_today);
  perform public.ensure_seva_mala_period('week', v_today);
  perform public.ensure_seva_mala_period('month', v_today);
  perform public.ensure_seva_mala_period('week', v_today - 1);
  perform public.ensure_seva_mala_period('month', v_today - 1);

  for v_period in
    select id from public.seva_mala_periods
    where frozen_at is null and starts_on <= v_today
    order by period_kind, starts_on
  loop
    perform public.recompute_seva_mala_period(v_period.id);
    v_periods := v_periods + 1;
  end loop;

  return v_periods;
end;
$$;

comment on function public.recompute_seva_mala() is
  'The nightly Seva Mala job: scarcity weights, then every open period, freezing the ones that have closed.';

revoke all on function public.recompute_seva_mala() from public, anon, authenticated;
grant execute on function public.recompute_seva_mala() to service_role;

-- ---------------------------------------------------------------------------
-- 18. Row level security.
--
--     period_scores gets RLS and NO policy. seva_mala_periods and
--     seva_type_weights get RLS and no policy either — the references and the
--     units are exactly the other half of the inversion described in section
--     4, and a devotee holding ref_g needs only one more number to read
--     somebody's giving. award_definitions is public reading, because what
--     the temple gives is not a secret. devotee_awards is your own, or
--     everything if you are the President or the Tech Admin.
--
--     Not one INSERT, UPDATE or DELETE is granted on any table here to any
--     client role. Every write goes through a function in this file.
-- ---------------------------------------------------------------------------

alter table public.seva_mala_periods enable row level security;
alter table public.period_scores enable row level security;
alter table public.seva_type_weights enable row level security;
alter table public.award_definitions enable row level security;
alter table public.devotee_awards enable row level security;

revoke all on table public.seva_mala_periods from public, anon, authenticated;
revoke all on table public.period_scores from public, anon, authenticated;
revoke all on table public.seva_type_weights from public, anon, authenticated;
revoke all on table public.award_definitions from public, anon, authenticated;
revoke all on table public.devotee_awards from public, anon, authenticated;

drop policy if exists "Devotees read the award list" on public.award_definitions;
create policy "Devotees read the award list"
  on public.award_definitions for select to authenticated
  using (auth.uid() is not null and is_active);

grant select (
  id, code, title, description, tier, garland_kind, rule_kind, period_kind,
  is_active, sort_order
) on public.award_definitions to authenticated;

drop policy if exists "Devotees read their own awards" on public.devotee_awards;
create policy "Devotees read their own awards"
  on public.devotee_awards for select to authenticated
  using (
    auth.uid() is not null
    and (devotee_id = auth.uid() or public.has_permission('app.view_all'))
  );

grant select (
  id, award_definition_id, devotee_id, period_id, awarded_on, awarded_by,
  citation, fulfilled_on, fulfilment_note, created_at
) on public.devotee_awards to authenticated;

-- ---------------------------------------------------------------------------
-- 19. Your own standing.
--
--     Your own numbers, in full, because they are yours. Your position among
--     everybody, because that is the truth about where you stand — and
--     alongside it board_standing, which is where you appear on the garland
--     among the devotees who opted in, or null if you opted out. Two honest
--     numbers rather than one that has to be explained.
--
--     gathering is the minimum-cohort flag: under eight active devotees the
--     board does not publish, because in a congregation of five a ranking is
--     not recognition, it is a comment about four people. Your own numbers
--     still come back; only the standing is withheld.
-- ---------------------------------------------------------------------------

create or replace function public.my_seva_mala(p_period_kind text default 'week')
returns table (
  period_id uuid,
  period_kind text,
  period_start date,
  period_end date,
  score numeric,
  seva_minutes integer,
  seva_acts integer,
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
  )
  select
    target.id,
    target.period_kind,
    target.starts_on,
    target.ends_on,
    coalesce(ranked.score, 0),
    coalesce(round(ranked.credited_minutes), 0)::integer,
    coalesce(ranked.seva_acts, 0),
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
  join public.users on users.id = auth.uid()
  left join ranked on ranked.devotee_id = auth.uid()
  left join board on board.devotee_id = auth.uid()
  where auth.uid() is not null
$$;

comment on function public.my_seva_mala(text) is
  'Your own Seva Mala standing for the current week, month or lifetime. Your numbers are yours; your standing is withheld while the congregation is still gathering.';

revoke all on function public.my_seva_mala(text) from public, anon;
grant execute on function public.my_seva_mala(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 20. The garland.
--
--     POSITION OR TIER ONLY. No score, no minutes, no cents, no norms, not
--     rounded, not bucketed, not "approximately". Read section 4 before
--     adding a column here.
--
--     Only devotees who opted in, and dense-ranked over the opted-in set, so
--     the board has no gaps for anybody to read an absence out of. The caller
--     is appended below the band if they opted in and fell outside it — the
--     one thing a devotee most wants from a board they are not near the top
--     of is to know where they actually are.
--
--     A congregation still gathering returns exactly one row, everything null
--     but gathering true. That is the contract: the client reads the flag, not
--     the emptiness, because an empty result and a withheld result should not
--     look the same to a phone.
-- ---------------------------------------------------------------------------

create or replace function public.list_seva_garland(
  p_period_kind text default 'week',
  p_limit integer default 20
)
returns table (
  standing integer,
  devotee_id uuid,
  devotee_name text,
  devotee_photo_url text,
  tier text,
  is_you boolean,
  gathering boolean
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
  publishable as (
    select target.*
    from target cross join minimum
    where target.participant_count >= minimum.cohort
  ),
  board as (
    select
      dense_rank() over (order by scores.score desc)::integer as standing,
      scores.devotee_id,
      users.name as devotee_name,
      users.photo_url as devotee_photo_url,
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
    where scores.score > 0 and users.leaderboard_visible
  ),
  band as (
    select board.* from board
    where board.standing <= greatest(1, least(coalesce(p_limit, 20), 200))
  )
  select band.standing, band.devotee_id, band.devotee_name,
         band.devotee_photo_url, band.tier, band.is_you, false
  from band
  where auth.uid() is not null

  union all

  -- The caller, appended, when they opted in and fell outside the band.
  select board.standing, board.devotee_id, board.devotee_name,
         board.devotee_photo_url, board.tier, board.is_you, false
  from board
  where auth.uid() is not null
    and board.is_you
    and board.standing > greatest(1, least(coalesce(p_limit, 20), 200))

  union all

  -- Still gathering: one row, and a flag rather than an empty set.
  select null::integer, null::uuid, null::text, null::text, null::text, false, true
  from target cross join minimum
  where auth.uid() is not null
    and target.participant_count < minimum.cohort

  order by 7, 1
$$;

comment on function public.list_seva_garland(text, integer) is
  'The public garland: standing and award tier, for devotees who opted in, dense-ranked among themselves. Never a score, never hours, never dollars. Returns a single gathering row while the congregation is under the minimum cohort.';

revoke all on function public.list_seva_garland(text, integer) from public, anon;
grant execute on function public.list_seva_garland(text, integer) to authenticated;

-- ---------------------------------------------------------------------------
-- 21. What the President sees.
--
--     Everyone, including the devotees who opted out, flagged as hidden so
--     the President knows the board they are looking at is not the board the
--     congregation sees. With the components, because app.view_all already
--     means every donation in public.donations is theirs to read and pretending
--     otherwise here would be theatre.
--
--     The minimum cohort does not apply. It protects a small congregation from
--     being ranked in public; the President reading their own temple's numbers
--     is not the public.
-- ---------------------------------------------------------------------------

create or replace function public.list_all_seva_scores(p_period_kind text default 'week')
returns table (
  standing integer,
  devotee_id uuid,
  devotee_name text,
  score numeric,
  seva_minutes integer,
  seva_acts integer,
  giving_cents bigint,
  gifts integer,
  seva_norm numeric,
  giving_norm numeric,
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
  )
  select
    dense_rank() over (order by scores.score desc)::integer,
    scores.devotee_id,
    users.name,
    scores.score,
    round(scores.credited_minutes)::integer,
    scores.seva_acts,
    scores.giving_cents,
    scores.gifts,
    scores.seva_norm,
    scores.giving_norm,
    not users.leaderboard_visible
  from public.period_scores scores
  join target on target.id = scores.period_id
  join public.users on users.id = scores.devotee_id
  where public.has_permission('app.view_all')
  order by scores.score desc, users.name
$$;

comment on function public.list_all_seva_scores(text) is
  'Every devotee''s Seva Mala standing, for the President and the Tech Admin. Includes devotees who opted out of the board, flagged is_hidden.';

revoke all on function public.list_all_seva_scores(text) from public, anon;
grant execute on function public.list_all_seva_scores(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 22. Opting in and out.
--
--     Says plainly in its return what it did. Nothing else about the devotee
--     changes: no score is recomputed, no award is withdrawn, nothing is
--     deleted. This flag is read by exactly one thing — the garland — and
--     that is the whole of its power.
-- ---------------------------------------------------------------------------

create or replace function public.set_my_leaderboard_visibility(p_visible boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_visible boolean;
begin
  if auth.uid() is null then
    raise exception 'Sign in to change whether you appear on the Seva Mala.';
  end if;
  if p_visible is null then
    raise exception 'Say whether you would like to appear on the Seva Mala.';
  end if;

  update public.users
  set leaderboard_visible = p_visible
  where users.id = auth.uid()
  returning users.leaderboard_visible into v_visible;

  return v_visible;
end;
$$;

comment on function public.set_my_leaderboard_visibility(boolean) is
  'Appear on the Seva Mala garland, or do not. Display only — your score is computed and your awards are earned either way.';

revoke all on function public.set_my_leaderboard_visibility(boolean) from public, anon;
grant execute on function public.set_my_leaderboard_visibility(boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- 23. The President's gift.
--
--     The one award no algorithm may touch, in either direction: a recompute
--     never creates one and never considers one, and this function refuses
--     any definition that is not discretionary. It is the temple's answer to
--     the devotee who sat with a dying man for a week, which no fill rate will
--     ever see.
--
--     A citation, because a gift with a reason attached is a different thing
--     from a gift.
-- ---------------------------------------------------------------------------

create or replace function public.award_discretionary_gift(
  p_devotee_id uuid,
  p_award_code text,
  p_citation text default null
)
returns public.devotee_awards
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_definition public.award_definitions;
  v_devotee public.users;
  v_award public.devotee_awards;
begin
  if auth.uid() is null then
    raise exception 'Sign in to give an award.';
  end if;
  if not public.has_permission('app.view_all') then
    raise exception 'Only the President or a Tech Admin can give this award.';
  end if;

  select * into v_devotee from public.users where users.id = p_devotee_id;
  if v_devotee.id is null then
    raise exception 'That devotee could not be found.';
  end if;

  select * into v_definition from public.award_definitions
  where award_definitions.code = p_award_code;
  if v_definition.id is null then
    raise exception 'There is no award with that code.';
  end if;
  if not v_definition.is_active then
    raise exception '"%" is not being given at the moment.', v_definition.title;
  end if;
  if v_definition.rule_kind <> 'discretionary' then
    raise exception
      '"%" is earned rather than given. Only a discretionary award can be given by hand.',
      v_definition.title;
  end if;

  insert into public.devotee_awards (
    award_definition_id, devotee_id, period_id, awarded_by, citation
  )
  values (
    v_definition.id, p_devotee_id, null, auth.uid(),
    nullif(trim(coalesce(p_citation, '')), '')
  )
  returning * into v_award;

  return v_award;
end;
$$;

comment on function public.award_discretionary_gift(uuid, text, text) is
  'The President gives an award by hand, with a citation. Only a discretionary definition may be given this way, and no recompute ever touches one.';

revoke all on function public.award_discretionary_gift(uuid, text, text) from public, anon;
grant execute on function public.award_discretionary_gift(uuid, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 24. Recording that it was actually handed over.
--
--     Mirrors mark_sponsorship_fulfilled, including the refusal to do it
--     twice and the refusal to date it in the future. A garland is a physical
--     object; the record of having made it and given it is the temple's, not
--     the recipient's, which is why a devotee cannot mark their own.
-- ---------------------------------------------------------------------------

create or replace function public.record_award_fulfilment(
  p_award_id uuid,
  p_fulfilled_on date default null,
  p_note text default null
)
returns public.devotee_awards
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_award public.devotee_awards;
  v_on date;
  v_note text;
  v_updated public.devotee_awards;
begin
  if auth.uid() is null then
    raise exception 'Sign in to record a fulfilment.';
  end if;
  if not public.has_permission('app.view_all') then
    raise exception 'Only the President or a Tech Admin can record that an award was given out.';
  end if;

  select * into v_award from public.devotee_awards
  where devotee_awards.id = p_award_id
  for update;
  if v_award.id is null then
    raise exception 'That award could not be found.';
  end if;
  if v_award.fulfilled_on is not null then
    raise exception 'That award was already recorded as given out on %.',
      to_char(v_award.fulfilled_on, 'FMDD FMMonth YYYY');
  end if;

  v_on := coalesce(p_fulfilled_on, public.seva_mala_today());
  if v_on > public.seva_mala_today() then
    raise exception 'An award cannot be recorded as given out before it happens.';
  end if;
  if v_on < v_award.awarded_on then
    raise exception 'An award cannot be given out before it was awarded.';
  end if;

  v_note := nullif(trim(coalesce(p_note, '')), '');

  update public.devotee_awards
  set fulfilled_on = v_on,
      fulfilment_note = v_note
  where devotee_awards.id = v_award.id
  returning * into v_updated;

  return v_updated;
end;
$$;

comment on function public.record_award_fulfilment(uuid, date, text) is
  'Records that a garland, a plate or a token actually reached the devotee. Once and once only, and never by the devotee themselves.';

revoke all on function public.record_award_fulfilment(uuid, date, text) from public, anon;
grant execute on function public.record_award_fulfilment(uuid, date, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 25. Showing your working.
--
--     Every component of YOUR OWN score, and the period's references beside
--     them, so a devotee can check the arithmetic rather than being asked to
--     trust it. This is the only place ŝ, ĝ and the references ever leave the
--     database, and it is strictly about the caller: there is no parameter for
--     whose score to explain, and auth.uid() is the only devotee it will
--     answer about.
--
--     minutes_lost_to_caps is the difference between what the caps allowed and
--     what was served, which is the question a devotee who served ten hours on
--     Gaura Purnima will actually ask.
-- ---------------------------------------------------------------------------

create or replace function public.explain_my_score(p_period_id uuid)
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
  'The whole arithmetic behind your own score for one period, including the references it was scaled against and any minutes the daily or weekly cap held back. Only ever your own.';

revoke all on function public.explain_my_score(uuid) from public, anon;
grant execute on function public.explain_my_score(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 26. The schedule.
--
--     Guarded on pg_available_extensions exactly as 0008 is, so this migration
--     applies unchanged to a local Postgres with no pg_cron. Nightly at ten
--     past midnight Chicago — after the day has closed, before anybody opens
--     the app. Supabase's cron runs in UTC, so 05:10 UTC in winter; the job is
--     idempotent and a run at the wrong hour costs nothing but a scan.
-- ---------------------------------------------------------------------------

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    execute 'create extension if not exists pg_cron with schema extensions';
    if exists (select 1 from pg_extension where extname = 'pg_cron') then
      execute $cron$
        select cron.schedule(
          'recompute-seva-mala',
          '10 5 * * *',
          'select public.recompute_seva_mala();'
        )
        where not exists (
          select 1 from cron.job where jobname = 'recompute-seva-mala'
        )
      $cron$;
    end if;
  end if;
exception when others then
  raise notice 'Enable Supabase Cron to recompute Seva Mala nightly.';
end;
$$;

do $$
begin
  raise notice 'seva mala applied';
end;
$$;
