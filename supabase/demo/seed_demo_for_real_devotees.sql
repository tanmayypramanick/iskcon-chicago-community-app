-- ###########################################################################
-- #                                                                         #
-- #   D E M O   H I S T O R Y   F O R   T W O   R E A L   A C C O U N T S   #
-- #                                                                         #
-- #   Tanmay Pramanick (the temple president) and Arpita Jadhav (a devotee) #
-- #   demonstrate the app on their own phones, with their own logins. Their #
-- #   accounts are REAL and empty, so every Sevā Yātrā screen — Seva         #
-- #   Profile, the garland, Seva History, badges, gifts, Giving — looks     #
-- #   broken to the two people showing it off.                              #
-- #                                                                         #
-- #   This script gives those two accounts a seva and giving history that   #
-- #   is invented but INTERNALLY TRUE: every hour, point, badge and place   #
-- #   below is produced by the temple's own rules from the facts seeded     #
-- #   here. Nothing is written straight into period_scores and no award row #
-- #   is inserted by hand — public.recompute_seva_mala() and                #
-- #   public.award_seva_mala_for_period() decide all of it.                 #
-- #                                                                         #
-- #   TO REMOVE IT, RUN:  supabase/demo/remove_demo_for_real_devotees.sql   #
-- #                                                                         #
-- ###########################################################################
--
-- HOW THIS DIFFERS FROM supabase/demo/seed_demo_congregation.sql
--
--   That script invents forty-two people, and everything it touches hangs off
--   an email that cannot exist. THESE TWO ARE REAL. There is no marker to hang
--   on a real account, and putting one there would be editing a row that
--   belongs to somebody. So this file obeys three rules instead:
--
--     1. IT NEVER UPDATES A ROW EITHER OF THEM AUTHORED. public.users is not
--        written to at all — not their name, not their profile, and not
--        leaderboard_visible. Every statement below is an INSERT, or a call to
--        one of the temple's own RPCs made AS one of them.
--
--     2. IT WRITES DOWN EVERY ROW IT CREATED. public.demo_seva_yatra_ledger is
--        a plain list of (table, row id) taken as the difference between a
--        snapshot of every table this script can reach, before and after. That
--        catches the rows this file inserts AND the rows the temple's own RPCs
--        insert underneath it — public.generate_service_instances alone creates
--        occurrences for every active rota in the database. The removal script
--        deletes exactly that list and nothing else, then drops the ledger.
--
--     3. IT REMEMBERS WHAT THE AWARD SHELF LOOKED LIKE FIRST. Every award row
--        that existed before this ran is recorded in the same ledger, because
--        recomputing Sevā Mālā hands out awards and there is no other way to
--        tell afterwards which ones were already there.
--
--   Everything else — one transaction, idempotent, re-runnable, notifying
--   nobody — is that file's convention, followed here exactly.
--
-- WHAT IT NEEDS
--
--   * All migrations up to 202608040066_badges_and_reads.sql.
--   * A session running as `postgres` (the Supabase SQL editor is one). It has
--     to recompute Sevā Mālā and to disable three triggers.
--   * BOTH accounts must already exist. If either is missing this script stops
--     before it writes anything and says which one.
--   * A congregation large enough for seva_mala.minimum_cohort (8 by default).
--     The garland does not render below that, so seeding into a database that
--     cannot reach it would be seeding a screen that stays empty. If the count
--     is short, this script stops and tells you to run
--     supabase/demo/seed_demo_congregation.sql first.
--
-- HOW LONG IT TAKES: under a minute. It ends with a NOTICE listing the hours,
-- the points, the standing and every badge each of them came out holding.
--
-- ---------------------------------------------------------------------------

begin;

-- REPEATABLE READ, and it is not optional. Section 6 works out what this file
-- created by comparing a snapshot of every table before against one after, and
-- under the default READ COMMITTED each of those two statements takes its own
-- fresh snapshot. So a devotee who joined a seva on their phone in the seconds
-- between them would be absent from the first and present in the second, this
-- file would write their row into the ledger as its own, and
-- remove_demo_for_real_devotees.sql would later delete a real devotee's place
-- in a real seva. Under REPEATABLE READ both snapshots see the same instant
-- plus this transaction's own writes, so another session's commits are
-- invisible and cannot be mistaken for ours. If this aborts with a
-- serialization failure, somebody was writing at the same time — run it again.
set transaction isolation level repeatable read;

-- ---------------------------------------------------------------------------
-- 1. Ground checks. Loudly wrong beats quietly wrong.
-- ---------------------------------------------------------------------------

do $$
begin
  if to_regprocedure('public.recompute_seva_mala()') is null
    or to_regprocedure('public.recompute_seva_mala_period(uuid)') is null
    or to_regprocedure('public.ensure_seva_mala_period(text, date)') is null
    or to_regprocedure('public.award_seva_mala_for_period(uuid)') is null
    or to_regprocedure('public.seva_mala_period_measures(text, date, date, text)') is null
    or to_regprocedure('public.seva_yatra_devotee_summary(uuid, text)') is null
    or to_regprocedure('public.report_weekly_service_unavailable(uuid, text, date, date, integer[], text)') is null
    or to_regprocedure('public.offer_service_coverage_range(uuid, uuid, text, date, date)') is null
    or to_regprocedure('public.respond_to_coverage_range_offer(uuid, boolean)') is null
    or to_regprocedure('public.log_completed_service(uuid, text, date, time, integer)') is null
    or to_regprocedure('public.complete_service_instance(uuid)') is null
    or to_regprocedure('public.generate_service_instances(integer)') is null
  then
    raise exception
      'This database is behind the migrations this demo needs. Apply supabase/migrations up to 202608040066 first.';
  end if;

  if not public.is_backend_caller() then
    raise exception
      'Run this as postgres (the Supabase SQL editor does). It has to recompute Seva Mala and disable three triggers.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Who the two of them are.
--
--    Looked up by email, and by name only if the email misses, because an
--    email is the thing the account was actually created with and a name is
--    the thing somebody can change. Never by id: an id typed into a seed
--    script is an id that seeds somebody else the day the account is recreated.
--
--    A missing account, an ambiguous name, or a president who cannot arrange
--    coverage all stop the script HERE, before one row has been written. Half
--    a demo is worse than none: it is a screen that is wrong in a way nobody
--    can see.
-- ---------------------------------------------------------------------------

create temp table dsy_who (
  role_in_demo text primary key,   -- 'president' | 'devotee'
  devotee_id   uuid not null,
  devotee_name text not null
) on commit drop;

do $$
declare
  v_person record;
  v_id uuid;
  v_name text;
  v_count integer;
begin
  for v_person in
    select * from (values
      ('president', 'tanmaypramanick06@gmail.com', 'tanmay pramanick', 'Tanmay Pramanick',
       'He has to sign in once before his history can be seeded.'),
      ('devotee',   'arpitajadhav24k@gmail.com',   'arpita jadhav',    'Arpita Jadhav',
       'She has to sign in once before her history can be seeded.')
    ) as person(role_in_demo, email, name_key, display_name, advice)
  loop
    v_id := null;
    v_name := null;

    select devotees.id, devotees.name into v_id, v_name
    from public.users devotees
    where lower(coalesce(devotees.email, '')) = v_person.email;

    -- The name is the fallback and never the first question: an email is what
    -- the account was created with and a name is what somebody can change.
    if v_id is null then
      select count(*) into v_count
      from public.users devotees
      where lower(trim(coalesce(devotees.name, ''))) = v_person.name_key;

      if v_count = 0 then
        raise exception
          'No account for % (%). % Nothing has been written.',
          v_person.display_name, v_person.email, v_person.advice;
      elsif v_count > 1 then
        raise exception
          'There are % accounts named % and no match on %, so this script cannot tell which one the demo is for. Nothing has been written.',
          v_count, v_person.display_name, v_person.email;
      end if;

      select devotees.id, devotees.name into v_id, v_name
      from public.users devotees
      where lower(trim(coalesce(devotees.name, ''))) = v_person.name_key;
    end if;

    insert into dsy_who values (v_person.role_in_demo, v_id, v_name);
  end loop;

  if (select count(distinct devotee_id) from dsy_who) <> 2 then
    raise exception
      'Tanmay and Arpita resolved to the same account. Nothing has been written.';
  end if;
end;
$$;

-- The two of them are asked to do, through the temple's own RPCs, exactly what
-- their roles let them do. If the roles are not what this demo assumes, the
-- RPC calls in section 9 would fail halfway through with a message about
-- permissions rather than about the demo, so it is asked here instead.
do $$
declare
  v_missing text;
begin
  perform set_config('request.jwt.claim.sub',
    (select devotee_id::text from dsy_who where role_in_demo = 'president'), true);

  v_missing := null;
  if not public.has_permission('services.resolve_coverage') then
    v_missing := 'services.resolve_coverage';
  elsif not public.has_permission('app.view_all') then
    v_missing := 'app.view_all';
  end if;

  if v_missing is not null then
    raise exception
      '% is the president in this demo but does not hold %. Give the account the president role first. Nothing has been written.',
      (select devotee_name from dsy_who where role_in_demo = 'president'), v_missing;
  end if;

  perform set_config('request.jwt.claim.sub',
    (select devotee_id::text from dsy_who where role_in_demo = 'devotee'), true);

  if not public.has_permission('services.report_unavailable') then
    raise exception
      '% cannot report weekly-seva unavailability, so the coverage swap this demo is about cannot be made. Nothing has been written.',
      (select devotee_name from dsy_who where role_in_demo = 'devotee');
  end if;

  perform set_config('request.jwt.claim.sub', '', true);
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. The ledger.
--
--    The whole of how removal knows what to remove. One row per row this
--    script created, plus one row per award that existed BEFORE it ran, plus a
--    sentinel saying the seed happened at all.
--
--    It is a real table rather than a naming convention because a real account
--    cannot be marked. supabase/demo/remove_demo_for_real_devotees.sql reads
--    it, deletes exactly what it names, and drops it.
-- ---------------------------------------------------------------------------

do $$
begin
  if to_regclass('public.demo_seva_yatra_ledger') is null then
    create table public.demo_seva_yatra_ledger (
      id          bigint generated always as identity primary key,
      entry_kind  text not null check (entry_kind in (
                     'seeded', 'row', 'award_before', 'period_open_before')),
      table_name  text,
      row_id      uuid,
      detail      text,
      recorded_at timestamptz not null default now()
    );
    create index demo_seva_yatra_ledger_lookup
      on public.demo_seva_yatra_ledger (entry_kind, table_name);
  end if;
end;
$$;

comment on table public.demo_seva_yatra_ledger is
  'Every row supabase/demo/seed_demo_for_real_devotees.sql created, every award that existed before it ran, and every Seva Mala period that was still open when it ran. Read and dropped by supabase/demo/remove_demo_for_real_devotees.sql. Not part of the schema: if this table exists, demonstration data is live.';

alter table public.demo_seva_yatra_ledger enable row level security;
revoke all on public.demo_seva_yatra_ledger from public, anon, authenticated;

-- The tables this script, and the RPCs it calls, can reach. Listed CHILD
-- FIRST, which is the order the removal deletes in, so the one list is both
-- the thing that gets watched and the thing that gets undone. Change it here
-- and change it in the removal script.
create temp table dsy_tracked (position integer primary key, table_name text not null)
  on commit drop;

insert into dsy_tracked (position, table_name) values
  ( 1, 'donations'),
  ( 2, 'service_verifications'),
  ( 3, 'service_qr_sessions'),
  ( 4, 'service_offer_counters'),
  ( 5, 'service_offers'),
  ( 6, 'service_assignments'),
  ( 7, 'service_coverage_plans'),
  ( 8, 'service_exceptions'),
  ( 9, 'service_instances'),
  (10, 'service_template_assignees'),
  (11, 'service_templates'),
  (12, 'sponsorship_bookings'),
  (13, 'seva_care_dismissals'),
  (14, 'seva_mala_periods');

-- ---------------------------------------------------------------------------
-- 4. Three triggers come off for the length of this transaction, and go back
--    on in section 12, before commit.
--
--      devotee_award_announced     pushes at the devotee. The whole point of
--                                  this file is that a badge appears on their
--                                  screen at breakfast, not that their phone
--                                  buzzes forty times at three in the morning.
--      devotee_awards_append_only  the guard that makes taking an award back
--                                  impossible — which is what clearing a
--                                  previous run of this seed, and leaving the
--                                  rest of the congregation alone, both need.
--      deliver_app_notification    hands every queued notification to the push
--                                  function. The RPCs called in section 9 are
--                                  the real ones and they really do queue
--                                  notifications: at the coverage coordinators,
--                                  at Arpita when her seva is covered, at
--                                  whoever is on an occurrence somebody closes.
--                                  The rows are deleted again in section 11;
--                                  this stops them being sent in the meantime.
--
--    All three are restored inside this same transaction, so a failure
--    anywhere rolls the disabling back with everything else.
-- ---------------------------------------------------------------------------

alter table public.devotee_awards disable trigger devotee_award_announced;
alter table public.devotee_awards disable trigger devotee_awards_append_only;
alter table public.app_notifications disable trigger deliver_app_notification;

-- ---------------------------------------------------------------------------
-- 5. Undo any previous run of THIS seed, so running it twice gives one
--    history rather than two.
--
--    Same order, same rules as the removal script. It is repeated here rather
--    than factored into a function so that this file installs nothing
--    permanent except the ledger. If you change one, change the other.
--
--    The award baseline is deliberately NOT re-taken: the shelf as it stood
--    before the FIRST run is the only correct baseline, and re-snapshotting
--    after a run would freeze this seed's own awards into it for ever.
-- ---------------------------------------------------------------------------

do $$
declare
  v_row record;
begin
  if not exists (
    select 1 from public.demo_seva_yatra_ledger where entry_kind = 'seeded'
  ) then
    return;
  end if;

  -- Awards first: devotee_awards.period_id is ON DELETE SET NULL, so a period
  -- removed before its awards leaves an award row pointing at nothing.
  delete from public.devotee_awards
  where id not in (
    select ledger.row_id from public.demo_seva_yatra_ledger ledger
    where ledger.entry_kind = 'award_before'
  );

  for v_row in select table_name from dsy_tracked order by position loop
    if v_row.table_name = 'service_instances' then
      -- An occurrence this seed created that somebody has since joined is left
      -- where it is, with their place on it. Deleting it would cascade a real
      -- devotee's assignment away, and no cleanup is worth that.
      execute $q$
        delete from public.service_instances instances
        where instances.id in (
          select ledger.row_id from public.demo_seva_yatra_ledger ledger
          where ledger.entry_kind = 'row' and ledger.table_name = 'service_instances'
        )
        and not exists (
          select 1 from public.service_assignments assignments
          where assignments.service_instance_id = instances.id
        )
      $q$;
    else
      execute format($q$
        delete from public.%I
        where id in (
          select ledger.row_id from public.demo_seva_yatra_ledger ledger
          where ledger.entry_kind = 'row' and ledger.table_name = %L
        )
      $q$, v_row.table_name, v_row.table_name);
    end if;
  end loop;

  update public.seva_mala_periods
  set frozen_at = null
  where id in (
    select ledger.row_id from public.demo_seva_yatra_ledger ledger
    where ledger.entry_kind = 'period_open_before'
  );

  -- Everything except the award baseline, which section 6 must not re-take.
  -- The open-period list IS re-derived, and correctly: the line above has just
  -- put every period this seed froze back the way it found it, so "open now"
  -- means the same thing it meant before the first run.
  delete from public.demo_seva_yatra_ledger
  where entry_kind in ('row', 'seeded', 'period_open_before');
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. The two snapshots everything afterwards is measured against.
-- ---------------------------------------------------------------------------

-- Every id in every table this script can reach, right now. The difference at
-- the end is this seed's footprint, whoever inserted the row.
create temp table dsy_before (table_name text not null, row_id uuid not null)
  on commit drop;
create index dsy_before_lookup on dsy_before (table_name, row_id);

do $$
declare
  v_row record;
begin
  for v_row in select table_name from dsy_tracked order by position loop
    execute format(
      'insert into dsy_before (table_name, row_id) select %L, rows.id from public.%I rows',
      v_row.table_name, v_row.table_name);
  end loop;
end;
$$;

-- Notifications are handled separately: they are DELETED at the end of this
-- script rather than recorded, because a demo that leaves a notification
-- behind has notified somebody after all.
create temp table dsy_notifications_before on commit drop as
  select notifications.id from public.app_notifications notifications;

-- The award shelf as it stands. Written to the ledger and not to a temp table,
-- because the removal script — a different session, days later — is the thing
-- that needs it. Only ever taken once; a second run of this seed keeps the
-- first run's baseline (section 5).
insert into public.demo_seva_yatra_ledger (entry_kind, row_id, detail)
select 'award_before', awards.id, 'award held before the demo was seeded'
from public.devotee_awards awards
where not exists (
  select 1 from public.demo_seva_yatra_ledger ledger
  where ledger.entry_kind = 'award_before'
);

-- Which Sevā Mālā periods were still open. Anything this seed's recompute
-- freezes has to be re-opened by the removal, or the period stays frozen at a
-- score that was computed from data that no longer exists.
insert into public.demo_seva_yatra_ledger (entry_kind, row_id, detail)
select 'period_open_before', periods.id,
       periods.period_kind || ' beginning ' || periods.starts_on
from public.seva_mala_periods periods
where periods.frozen_at is null;

insert into public.demo_seva_yatra_ledger (entry_kind, detail)
values ('seeded', 'supabase/demo/seed_demo_for_real_devotees.sql');

-- ---------------------------------------------------------------------------
-- 7. Helpers and dates. Session-local, so this file leaves nothing behind.
--
--    Every date comes from public.seva_mala_today(), which is the temple's own
--    Chicago calendar. current_date is the server's opinion and the server is
--    in UTC; on a Chicago evening the two disagree, and a seva history that
--    disagrees with the leaderboard about which day it is cannot be debugged
--    by looking at it.
-- ---------------------------------------------------------------------------

create or replace function pg_temp.dsy_at(p_on date, p_time time) returns timestamptz
language sql stable as $$
  select (p_on + p_time) at time zone 'America/Chicago'
$$;

create or replace function pg_temp.dsy_as(p_devotee_id uuid) returns void
language sql volatile as $$
  select set_config('request.jwt.claim.sub', p_devotee_id::text, true)::void
$$;

create temp table dsy_when on commit drop as
  select
    public.seva_mala_today()                                as today,
    public.seva_mala_week_start(public.seva_mala_today())   as week0,
    -- The rota starts sixteen Mondays back. Sixteen because Dhairya wants a
    -- run "as long as the steadiest part of the congregation", and the
    -- steadiest part of a demo congregation is thirteen weeks of pot washing.
    public.seva_mala_week_start(public.seva_mala_today()) - 7 * 15 as rota_from,
    public.seva_mala_week_start(public.seva_mala_today()) - 7 * 7  as arpita_rota_from,
    date_trunc('month', public.seva_mala_today())::date            as month0;

create temp table dsy_ids (
  key text primary key,
  id  uuid not null
) on commit drop;

insert into dsy_ids (key, id)
select 'tanmay', devotee_id from dsy_who where role_in_demo = 'president'
union all
select 'arpita', devotee_id from dsy_who where role_in_demo = 'devotee';

-- ---------------------------------------------------------------------------
-- 8. The facts.
--
--    Nothing in this section is a score, a point, a badge or a place. It is
--    only ever "this person served this seva on this day for this long" and
--    "this person gave this much on this day", which is all the temple's own
--    machinery needs, and it is the only honest way to make a demo that
--    behaves like the real thing when somebody taps into it.
-- ---------------------------------------------------------------------------

-- 8a. The two weekly rotas.
--
--     Tanmay opens the temple: Mangal Arati Setup at a quarter past four on
--     Sunday, Monday and Wednesday. It is the seva that gives him his hours,
--     his unbroken run, and every pre-dawn minute he has.
--
--     Arpita serves prasadam after the Sunday feast. One day a week, which is
--     what most of a congregation actually does, and the rota the coverage
--     swap in section 9 is about.

create temp table dsy_template (
  key       text primary key,
  who       text not null,
  type_name text not null,
  dows      integer[] not null,     -- 0 = Sunday
  at        time not null,
  minutes   integer not null,
  slots     integer not null,
  from_key  text not null,          -- column of dsy_when the rota starts on
  id        uuid
) on commit drop;

insert into dsy_template (key, who, type_name, dows, at, minutes, slots, from_key) values
  ('tanmay-mangal', 'tanmay', 'Mangal Arati Setup', array[0,1,3], time '04:15', 90, 4, 'rota_from'),
  ('arpita-prasadam', 'arpita', 'Prasadam Serving', array[0], time '13:00', 120, 4, 'arpita_rota_from');

insert into public.service_templates (
  service_type_id, day_of_week, days_of_week, start_time, duration_minutes,
  slots_needed, participation_mode, start_date, created_by, active
)
select
  types.id, template.dows[1], template.dows, template.at, template.minutes,
  template.slots, 'invite_only',
  case template.from_key when 'rota_from' then when_.rota_from
                         else when_.arpita_rota_from end,
  ids.id,
  true
from dsy_template template
join public.service_types types on types.name = template.type_name
cross join dsy_when when_
join dsy_ids ids on ids.key = 'tanmay';

-- Matched against section 6's snapshot, so a rota the temple ALREADY runs at
-- the same hour on the same days is never mistaken for this one. Hanging
-- fifteen weeks of invented history off a real rota would be writing into
-- somebody else's records, and the removal — which only knows the rows it
-- created — would leave it there.
update dsy_template template
set id = templates.id
from public.service_templates templates
join public.service_types types on types.id = templates.service_type_id
join dsy_ids creator on creator.id = templates.created_by and creator.key = 'tanmay'
where types.name = template.type_name
  and templates.days_of_week = template.dows
  and templates.start_time = template.at
  and not exists (
    select 1 from dsy_before
    where dsy_before.table_name = 'service_templates'
      and dsy_before.row_id = templates.id
  );

do $$
begin
  if exists (select 1 from dsy_template where id is null) then
    raise exception 'A weekly rota could not be identified after insertion; the demo would be half-built.';
  end if;
end;
$$;

-- Standing places on the rota. This is what makes the occurrences the temple's
-- own generator produces from today onward carry their names, which is what
-- "an upcoming weekly seva" means on their screens.
insert into public.service_template_assignees (
  service_template_id, devotee_id, assigned_by, status, days_of_week
)
select template.id, ids.id, tanmay.id, 'active', template.dows
from dsy_template template
join dsy_ids ids on ids.key = template.who
join dsy_ids tanmay on tanmay.key = 'tanmay';

-- 8b. Every act of seva, weekly and one-off, in one place.
--
--     `state` is which of the temple's three questions is still unanswered,
--     and it is the whole of the difference between an hour that shows up as
--     points and an hour that shows up only as hours:
--
--       counted                everything answered
--       awaiting_completion    nobody has closed the occurrence out
--       awaiting_verification  only the devotee says it happened
--       not_served             somebody said out loud that they were not there
--       recent                 a completed occurrence in the past week, left
--                              OPEN here and closed in section 9 by the real
--                              RPC, so "Recently completed" is something the
--                              temple did rather than something this file said

create temp table dsy_act (
  who             text not null,
  template_key    text,
  type_name       text not null,
  occurred_on     date not null,
  at              time not null,
  minutes         integer not null,
  state           text not null,
  instance_id     uuid not null default gen_random_uuid(),
  primary key (who, type_name, occurred_on, at)
) on commit drop;

-- The rotas, back to the day each of them started. Anything in the last seven
-- days is left for the RPC in section 9.
insert into dsy_act (who, template_key, type_name, occurred_on, at, minutes, state)
select
  template.who,
  template.key,
  template.type_name,
  day::date,
  template.at,
  template.minutes,
  case when day::date > when_.today - 7 then 'recent' else 'counted' end
from dsy_template template
cross join dsy_when when_
cross join lateral generate_series(
  (case template.from_key when 'rota_from' then when_.rota_from
                          else when_.arpita_rota_from end)::timestamp,
  (when_.today - 1)::timestamp,
  interval '1 day'
) as day
where extract(dow from day)::int = any (template.dows);

-- Tanmay's one-off seva. Three quiet months and then a loud August, because
-- Bhakti-latā is "more hours this month than in any month you have served
-- before" and a demo of a badge that measures a devotee against their own past
-- has to have a past to measure against.
insert into dsy_act (who, template_key, type_name, occurred_on, at, minutes, state)
select 'tanmay', null, plan.type_name, when_.today - plan.days_ago, plan.at,
       plan.minutes, 'counted'
from (values
  -- ---- the quiet months ------------------------------------------------
  ('Guest Welcome',        88, time '10:00', 120),
  ('Kitchen Preparation',  60, time '13:00', 180),
  ('Temple Room Cleaning', 46, time '10:30', 120),
  ('General Temple Service', 31, time '14:00', 120),
  -- ---- the festival month ----------------------------------------------
  ('Festival Decoration',  11, time '15:00', 240),
  ('Kitchen Preparation',   8, time '13:00', 240),
  ('Temple Room Cleaning',  6, time '10:30', 180),
  ('Guest Welcome',         4, time '10:00', 180),
  -- Monday: a seva he has never served before, which is the whole of Ruci.
  ('Book Table',            2, time '15:00', 120),
  -- Tuesday: the third different day of the week happening now, which is the
  -- whole of Nitya-sevā.
  ('Kitchen Preparation',   1, time '13:00', 180)
) as plan(type_name, days_ago, at, minutes)
cross join dsy_when when_;

-- Arpita's one-off seva, and the three states the temple asked to be able to
-- point at when a devotee asks why they are being shown zero points.
--
-- The three unfinished ones land in the WEEK HAPPENING NOW, on purpose. That is
-- the week whose screen says nought points, and the answer to "why" has to be
-- readable on the same screen as the question: two hours she served that nobody
-- has closed out, two hours nobody has verified, and two hours the temple
-- recorded she did not serve. Her Sunday rota does not fall inside this week at
-- all, so nothing of hers has counted yet — which is exactly the case the
-- temple asked about, produced rather than described.
insert into dsy_act (who, template_key, type_name, occurred_on, at, minutes, state)
select 'arpita', null, plan.type_name, when_.today - plan.days_ago, plan.at,
       plan.minutes, plan.state
from (values
  ('Guest Welcome',        35, time '10:00',  90, 'counted'),
  ('Vegetable Cutting',    21, time '09:30', 120, 'counted'),
  -- She served it; nobody has closed the occurrence out.
  ('Kirtana Support',       2, time '18:00', 120, 'awaiting_completion'),
  -- She was down for this and the temple recorded that she did not make it.
  ('Temple Room Cleaning',  1, time '10:30', 120, 'not_served')
) as plan(type_name, days_ago, at, minutes, state)
cross join dsy_when when_;

-- 8c. The occurrences and the places on them.

insert into public.service_instances (
  id, template_id, service_type_id, date, start_time, duration_minutes,
  slots_needed, participation_mode, posted_by, status, created_at
)
select
  act.instance_id,
  template.id,
  types.id,
  act.occurred_on,
  act.at,
  act.minutes,
  coalesce(template.slots, 1),
  'invite_only',
  tanmay.id,
  case act.state
    when 'awaiting_completion' then 'open'
    when 'recent' then 'full'
    else 'completed'
  end,
  pg_temp.dsy_at(act.occurred_on, act.at)
from dsy_act act
join public.service_types types on types.name = act.type_name
left join dsy_template template on template.key = act.template_key
join dsy_ids tanmay on tanmay.key = 'tanmay';

insert into public.service_assignments (
  service_instance_id, devotee_id, assignment_method, assigned_by, status,
  verification, attendance, created_at, completed_at
)
select
  act.instance_id,
  ids.id,
  case when act.template_key is not null then 'recurring_assignment' else 'self_joined' end,
  tanmay.id,
  case act.state
    when 'awaiting_completion' then 'assigned'
    when 'recent' then 'confirmed'
    else 'completed'
  end,
  -- Weekly seva needs no verification level at all (202608040059); a one-off
  -- that counts needs somebody other than the devotee to have said so.
  case when act.template_key is not null then 'self_report'
       when act.state in ('counted', 'not_served') then 'member_verified'
       else 'self_report' end,
  case act.state when 'counted' then case when act.template_key is null then 'served' end
                 when 'not_served' then 'absent' end,
  pg_temp.dsy_at(act.occurred_on - 3, time '20:00'),
  case when act.state in ('awaiting_completion', 'recent') then null
       else pg_temp.dsy_at(act.occurred_on, act.at + (act.minutes * interval '1 minute')) end
from dsy_act act
join dsy_ids ids on ids.key = act.who
join dsy_ids tanmay on tanmay.key = 'tanmay';

-- 8d. Giving. Integer cents, one currency per row, never summed across
--     currencies — the ledger's rule, and the reason there is no total in this
--     file that adds a dollar to a rupee.
--
--     Tanmay gives in three separate weeks of the current month on purpose:
--     Dhruva-dāna is "at least three separate weeks", and how much never
--     enters it.

insert into public.donations (
  donor_id, donor_name, donor_email, amount_cents, currency, kind, recurrence,
  external_payment_id, payload, received_at, match_status
)
select
  ids.id,
  devotees.name,
  devotees.email,
  gift.amount_cents,
  'USD',
  gift.kind,
  null,
  'demo-seva-yatra-' || gift.who || '-' || gift.tag,
  jsonb_build_object('demo', true, 'source', 'demo seva yatra for real devotees'),
  pg_temp.dsy_at(when_.today - gift.days_ago, time '19:40'),
  'general'
from (values
  ('tanmay', 'spring',        94, 10800, 'one_time'),
  ('tanmay', 'summer',        59, 25100, 'one_time'),
  ('tanmay', 'guru-purnima',  33, 15100, 'one_time'),
  -- Three weeks of the current month, smallest last.
  ('tanmay', 'jhulan',        11, 25100, 'one_time'),
  ('tanmay', 'balarama',       7, 10800, 'one_time'),
  ('tanmay', 'weekly-thanks',  1,  5100, 'one_time'),
  ('arpita', 'first-gift',    38,  2100, 'one_time'),
  ('arpita', 'sunday-feast',   6,  2100, 'one_time')
) as gift(who, tag, days_ago, amount_cents, kind)
join dsy_ids ids on ids.key = gift.who
join public.users devotees on devotees.id = ids.id
cross join dsy_when when_;

-- ---------------------------------------------------------------------------
-- 9. The parts the temple's own RPCs have to do, done by the temple's own
--    RPCs, as the devotee who would really have done them.
--
--    request.jwt.claim.sub is what public.auth.uid() reads, so setting it makes
--    these calls indistinguishable from the app making them: the permission
--    checks, the capacity rules, the withdrawal of the original devotee's
--    place, the resolution of the exception and the notifications all happen
--    for real. `set_config(..., true)` is transaction-local and is cleared
--    again at the end of this section.
-- ---------------------------------------------------------------------------

-- 9a. Occurrences from today onward, which is what "upcoming weekly seva"
--     means. This is the temple's own scheduler and it runs over every active
--     rota in the database, not only these two — every occurrence it makes is
--     in this seed's footprint and is removed with it.
select public.generate_service_instances(180);

-- 9b. The past week's occurrences, closed by the president the way he would
--     close them on a Monday morning.
do $$
declare
  v_instance uuid;
begin
  perform pg_temp.dsy_as((select id from dsy_ids where key = 'tanmay'));

  for v_instance in
    select act.instance_id from dsy_act act
    where act.state = 'recent'
    order by act.occurred_on, act.at
  loop
    perform public.complete_service_instance(v_instance);
  end loop;
end;
$$;

-- 9c. Arpita logs a seva she did on her own, and nobody has verified it yet.
--     This is the temple's own "I served something" button, and the state it
--     leaves behind — completed, self-reported, unconfirmed — is exactly the
--     state the answer screen has to be able to point at.
do $$
declare
  v_when dsy_when%rowtype;
begin
  select * into v_when from dsy_when;
  perform pg_temp.dsy_as((select id from dsy_ids where key = 'arpita'));

  perform public.log_completed_service(
    (select id from public.service_types where name = 'Kitchen Preparation'),
    null,
    v_when.today - 2,
    time '09:00',
    120
  );
end;
$$;

-- 9d. The coverage swap. Arpita hands next Sunday to somebody else, a
--     coordinator asks them, and they say yes — through
--     report_weekly_service_unavailable, offer_service_coverage_range and
--     respond_to_coverage_range_offer, in that order, which is the only order
--     the schema allows.
--
--     THE SUBSTITUTE ENDS UP HOLDING THE PLACE AND ARPITA DOES NOT. Her
--     assignment on that occurrence is withdrawn by the RPC itself, so it
--     reads 'not_served' to the scoring, and the substitute's is 'confirmed'.
--     Whatever that Sunday is eventually worth belongs to whoever turned up.
do $$
declare
  v_when dsy_when%rowtype;
  v_tanmay uuid := (select id from dsy_ids where key = 'tanmay');
  v_arpita uuid := (select id from dsy_ids where key = 'arpita');
  v_template uuid := (select id from dsy_template where key = 'arpita-prasadam');
  v_sunday date;
  v_group uuid;
  v_exception uuid;
  v_substitute uuid;
  v_offer uuid;
begin
  select * into v_when from dsy_when;

  -- The next Sunday that is not today. `report_weekly_service_unavailable`
  -- refuses a date in the past, which is correct and is why this is the one
  -- part of the demo that points forwards.
  v_sunday := v_when.today + (7 - extract(dow from v_when.today)::integer);

  -- Somebody other than Arpita, preferred from the fictional congregation so
  -- that the swap does not need a second real account to exist. Falls back to
  -- the president, who really would cover it.
  select devotees.id into v_substitute
  from public.users devotees
  where lower(coalesce(devotees.email, '')) like '%@demo.iskconchicago.test'
    and devotees.id <> v_arpita
  order by devotees.name, devotees.id
  limit 1;

  v_substitute := coalesce(v_substitute, v_tanmay);

  perform pg_temp.dsy_as(v_arpita);
  v_group := public.report_weekly_service_unavailable(
    v_template, 'occurrence', v_sunday, v_sunday, array[0],
    'Away for a family wedding.');

  select exceptions.id into v_exception
  from public.service_exceptions exceptions
  join public.service_instances instances on instances.id = exceptions.service_instance_id
  where exceptions.request_group_id = v_group
    and instances.date = v_sunday
  limit 1;

  if v_exception is null then
    raise exception 'The coverage request did not produce an exception for %; the swap cannot be demonstrated.', v_sunday;
  end if;

  perform pg_temp.dsy_as(v_tanmay);
  v_offer := public.offer_service_coverage_range(
    v_exception, v_substitute, 'occurrence', v_sunday, v_sunday);

  perform pg_temp.dsy_as(v_substitute);
  perform public.respond_to_coverage_range_offer(v_offer, true);

  perform set_config('request.jwt.claim.sub', '', true);

  -- Said out loud rather than assumed, because "the substitute is the one
  -- credited" is the entire claim this part of the demo makes.
  if not exists (
    select 1
    from public.service_assignments assignments
    join public.service_instances instances on instances.id = assignments.service_instance_id
    where instances.template_id = v_template
      and instances.date = v_sunday
      and assignments.devotee_id = v_substitute
      and assignments.status in ('assigned', 'confirmed', 'completed')
  ) then
    raise exception 'The substitute did not end up holding % after accepting the swap.', v_sunday;
  end if;

  if exists (
    select 1
    from public.service_assignments assignments
    join public.service_instances instances on instances.id = assignments.service_instance_id
    where instances.template_id = v_template
      and instances.date = v_sunday
      and assignments.devotee_id = v_arpita
      and assignments.status in ('assigned', 'confirmed', 'completed')
  ) then
    raise exception 'Arpita is still holding % after handing it over.', v_sunday;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 10. Build the boards, and let the rules hand out what the rules hand out.
--
--     The order is chronological and it matters. Sevā Mālā freezes a period
--     when its end date has passed, and a frozen period is never recomputed —
--     so a closed month has to be created and computed BEFORE the open one, or
--     "more hours than any month you have served before" has no earlier month
--     to compare against and "your personal best" has nothing to beat.
--
--     public.recompute_seva_mala_period calls public.award_seva_mala_for_period
--     itself. It is called again in section 10b anyway, for the reason the
--     temple asked: the awarding is the thing being demonstrated, and a
--     demonstration that relies on a side effect is one refactor from being a
--     demonstration of nothing.
-- ---------------------------------------------------------------------------

-- public.seva_type_weights is a pure cache and
-- public.recompute_seva_type_weights only ever writes rows for the kinds of
-- seva that were active in the trailing window — it never removes one. So a
-- previous run of this seed leaves behind a weight for every kind of seva it
-- invented activity for, and section 5 deleting the acts does not take the
-- weight with them. A stale weight is not cosmetic: it multiplies straight
-- into seva_minutes, which means a second run of an idempotent script would
-- score the whole congregation differently from the first.
--
-- Cleared and rebuilt here, BEFORE the closed periods are computed, so that a
-- frozen June is measured against the same weights whichever run produced it.
-- Nothing is lost: every value in this table is derived.
delete from public.seva_type_weights;
select public.recompute_seva_type_weights();

create temp table dsy_period (position integer primary key, id uuid not null, label text)
  on commit drop;

-- A period this seed opens is given an id derived from what the period IS,
-- rather than a fresh random one. That is not tidiness: public.award_definitions
-- holds two `draw` rules — the Mystery Gift, weekly and monthly — and 0055
-- draws them with `order by md5(period_id || devotee_id)`. A period whose id
-- changed between two runs of an idempotent script would hand the Mystery Gift
-- to a different devotee each time, which is the one thing a raffle must not
-- do. On conflict it defers to whatever is already there, so a temple whose
-- nightly job already opened these periods keeps its own rows and its own draw.
create or replace function pg_temp.dsy_period_id(p_kind text, p_starts_on date)
returns uuid
language sql immutable as $$
  select ('dec0de00-0000-4000-8000-'
          || substr(md5('demo-seva-yatra:' || p_kind || ':' || p_starts_on), 1, 12))::uuid
$$;

do $$
declare
  v_when dsy_when%rowtype;
  v_i integer;
  v_id uuid;
  v_on date;
  v_start date;
begin
  select * into v_when from dsy_when;

  -- The two months before this one, oldest first. Two rather than five: a
  -- period whose participant_count is under seva_mala.minimum_cohort publishes
  -- nothing, and reaching back further than the congregation's own activity
  -- goes only manufactures leaderboards of four people. The SEVA HISTORY runs
  -- further back than this — an act does not need a period to be on the list.
  for v_i in reverse 2 .. 1 loop
    v_on := (v_when.month0 - (v_i || ' months')::interval)::date;
    v_start := public.seva_mala_period_start('month', v_on);

    insert into public.seva_mala_periods (id, period_kind, starts_on, ends_on)
    values (pg_temp.dsy_period_id('month', v_start), 'month', v_start,
            public.seva_mala_period_end('month', v_on))
    on conflict (period_kind, starts_on) do nothing;

    v_id := public.ensure_seva_mala_period('month', v_on);
    insert into dsy_period (position, id, label)
    values (10 - v_i, v_id, 'month beginning ' || v_start);
  end loop;

  -- The week that closed on Sunday. Everything decided at the top of a period
  -- — most hours, first to a hard seva, the garland, Maha Prasad — waits for a
  -- period to close, because nothing here is ever revoked.
  v_start := public.seva_mala_period_start('week', v_when.week0 - 7);

  insert into public.seva_mala_periods (id, period_kind, starts_on, ends_on)
  values (pg_temp.dsy_period_id('week', v_start), 'week', v_start,
          public.seva_mala_period_end('week', v_when.week0 - 7))
  on conflict (period_kind, starts_on) do nothing;

  v_id := public.ensure_seva_mala_period('week', v_when.week0 - 7);
  insert into dsy_period (position, id, label)
  values (20, v_id, 'week beginning ' || v_start);
end;
$$;

do $$
declare
  v_row record;
begin
  for v_row in select id from dsy_period order by position loop
    perform public.recompute_seva_mala_period(v_row.id);
  end loop;
end;
$$;

-- Lifetime, the open week and the open month. This is the temple's own nightly
-- call and it does nothing to a period that is already frozen.
select public.recompute_seva_mala();

-- 10b. And award every period this demo cares about, explicitly.
do $$
declare
  v_row record;
begin
  for v_row in
    select periods.id from public.seva_mala_periods periods
    order by periods.period_kind, periods.starts_on
  loop
    perform public.award_seva_mala_for_period(v_row.id);
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- 11. Tidy up after the temple's own machinery.
--
--     11a. Write the footprint down.
--     11b. Take back every award the recompute handed a REAL devotee who is
--          not one of these two. The recompute ranks and thresholds the whole
--          congregation, so a real devotee can be moved over a line by hours
--          that only exist because of this file. The demo congregation is
--          spared for supabase/demo/seed_demo_congregation.sql's reason: they
--          are fictional and their awards go when they go.
--     11c. Delete every notification this transaction produced. The trigger
--          that pushes them has been off since section 4, so none of them was
--          ever sent; this is what stops them sitting in somebody's list.
-- ---------------------------------------------------------------------------

do $$
declare
  v_row record;
begin
  for v_row in select table_name from dsy_tracked order by position loop
    execute format($q$
      insert into public.demo_seva_yatra_ledger (entry_kind, table_name, row_id)
      select 'row', %L, rows.id
      from public.%I rows
      where not exists (
        select 1 from dsy_before
        where dsy_before.table_name = %L and dsy_before.row_id = rows.id
      )
    $q$, v_row.table_name, v_row.table_name, v_row.table_name);
  end loop;
end;
$$;

delete from public.devotee_awards awards
where awards.id not in (
        select ledger.row_id from public.demo_seva_yatra_ledger ledger
        where ledger.entry_kind = 'award_before')
  and awards.devotee_id not in (select id from dsy_ids)
  and awards.devotee_id not in (
        select devotees.id from public.users devotees
        where lower(coalesce(devotees.email, '')) like '%@demo.iskconchicago.test');

delete from public.app_notifications
where id not in (select id from dsy_notifications_before);

-- ---------------------------------------------------------------------------
-- 12. The triggers go back on, inside this transaction.
-- ---------------------------------------------------------------------------

alter table public.app_notifications enable trigger deliver_app_notification;
alter table public.devotee_awards enable trigger devotee_awards_append_only;
alter table public.devotee_awards enable trigger devotee_award_announced;

-- ---------------------------------------------------------------------------
-- 13. Refuse to have made a garland nobody can see.
--
--     seva_mala.minimum_cohort exists because "in a congregation of five a
--     ranking is not recognition, it is a comment about four people", and the
--     board, the public badges and the drill-down are all shut below it. A
--     demo seeded into a database that cannot reach it is a demo of an empty
--     screen, which is the exact complaint this file was written to answer.
-- ---------------------------------------------------------------------------

do $$
declare
  v_cohort integer := public.seva_mala_number('seva_mala.minimum_cohort', 8)::integer;
  v_week integer;
begin
  select periods.participant_count into v_week
  from public.seva_mala_periods periods
  where periods.period_kind = 'week'
    and public.seva_mala_today() between periods.starts_on and periods.ends_on;

  if coalesce(v_week, 0) < v_cohort then
    raise exception
      'Only % devotee(s) scored anything this week and the garland needs %. Run supabase/demo/seed_demo_congregation.sql first, then run this again. Nothing has been kept.',
      coalesce(v_week, 0), v_cohort;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 14. Say what the rules decided, rather than what this file intended.
--
--     Every number below is read back out of Sevā Mālā. If a badge is not in
--     this list, it was not earned, and the answer is in the facts above and
--     not in a line somebody forgot to write.
-- ---------------------------------------------------------------------------

do $$
declare
  v_row record;
  v_badges text;
  v_rows bigint;
begin
  raise notice '';
  raise notice '=== SEVA YATRA DEMO SEEDED FOR TWO REAL ACCOUNTS ===========';

  for v_row in
    select
      who.role_in_demo,
      who.devotee_name,
      who.devotee_id,
      (select round(sum(acts.raw_minutes) / 60.0, 1)
         from public.seva_mala_acts(who.devotee_id) acts
        where acts.points_status <> 'not_served') as lifetime_hours,
      (select count(*) from public.seva_mala_acts(who.devotee_id) acts) as acts,
      (select public.seva_mala_points(scores.score)
         from public.period_scores scores
         join public.seva_mala_periods periods on periods.id = scores.period_id
        where scores.devotee_id = who.devotee_id
          and periods.period_kind = 'month'
          and public.seva_mala_today() between periods.starts_on and periods.ends_on
       ) as month_points,
      (select count(*) from public.devotee_awards awards
        where awards.devotee_id = who.devotee_id) as awards
    from dsy_who who
    order by who.role_in_demo desc
  loop
    -- One line per KIND of gift, with how many periods earned it, because a
    -- flat list of thirty-seven rows is a wall rather than a summary.
    select string_agg(held.title || case when held.times > 1
                                    then ' x' || held.times else '' end,
                      ', ' order by held.sort_order, held.title)
    into v_badges
    from (
      select definitions.title,
             min(coalesce(definitions.sort_order, 9999)) as sort_order,
             count(*) as times
      from public.devotee_awards awards
      join public.award_definitions definitions on definitions.id = awards.award_definition_id
      where awards.devotee_id = v_row.devotee_id
      group by definitions.title
    ) held;

    raise notice '';
    raise notice '  % — %', v_row.devotee_name, v_row.role_in_demo;
    raise notice '    hours served (lifetime)  %', coalesce(v_row.lifetime_hours, 0);
    raise notice '    acts of seva             %', v_row.acts;
    raise notice '    points this month        %', coalesce(v_row.month_points, 0);
    raise notice '    awards                   %', v_row.awards;
    raise notice '    %', coalesce(v_badges, '(none)');
  end loop;

  -- The one thing this script will not do for them, said out loud rather than
  -- worked around. leaderboard_visible is a devotee's own decision about being
  -- published, it lives on the row they authored, and a demo that flipped it
  -- would be a demo that changed somebody's mind for them. Their own Seva
  -- Profile shows their standing either way; the public garland does not show
  -- them, and neither do their badges on anybody else's screen.
  for v_row in
    select who.devotee_name, devotees.leaderboard_visible
    from dsy_who who
    join public.users devotees on devotees.id = who.devotee_id
    where not devotees.leaderboard_visible
  loop
    raise notice '';
    raise notice '  NOTE: % has not opted in to the garland, so the', v_row.devotee_name;
    raise notice '  public board will not list them and their badges are not';
    raise notice '  shown on anybody else''s screen. Their own Seva Profile,';
    raise notice '  standing, hours and shelf are all there. One tap in the app';
    raise notice '  — Seva Yatra, the leaderboard switch — publishes them.';
    raise notice '  Nothing in this script touches that setting: it is theirs.';
  end loop;

  select count(*) into v_rows
  from public.demo_seva_yatra_ledger where entry_kind = 'row';

  raise notice '';
  raise notice '  % rows recorded in public.demo_seva_yatra_ledger.', v_rows;
  raise notice '  ALL OF IT IS FICTIONAL. To remove every trace, run';
  raise notice '  supabase/demo/remove_demo_for_real_devotees.sql';
  raise notice '===========================================================';
end;
$$;

commit;
