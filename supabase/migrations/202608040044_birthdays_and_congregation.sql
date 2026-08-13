-- Birthdays, and sangas in the congregation record.
--
-- Two small things the temple asked for, both about knowing the people in it.
--
-- The first is a birthday. A congregation that does not notice one is a
-- mailing list. When it is a devotee's birthday, everybody else is told, in
-- those words, once — "It's Ananda's birthday — wish them a happy birthday!"
--
-- The wording is deliberately they/them. The gender column exists and is
-- usually empty, and a greeting that guesses wrong about a real person, in
-- front of the whole congregation, is worse in every way than one that does
-- not guess at all. Nothing below branches on gender.
--
-- The second is the congregation spreadsheet the President and the Tech Admin
-- export. It already carries who somebody is; it did not carry which circles
-- of the temple they actually stand in, which is the first thing anybody
-- reading that sheet wants to know.
--
-- Requires 202608040030_devotee_profiles.sql (list_devotee_profiles and the
-- shape of remind_incomplete_profiles, which the birthday job mirrors),
-- 202608040039_sangas.sql (sangas, sanga_members, sangas.active) and
-- 202608040043_sanga_powers.sql (sangas.deleted_at, and the notification kind
-- list this file restates).

-- ---------------------------------------------------------------------------
-- 1. Whether a date of birth falls on a given day.
--
--    Pure, and takes the day rather than reading the clock, because the two
--    interesting rules here — the 29th of February, and which day it is in
--    Chicago — are separate questions and are far easier to prove separately.
--
--    The rules:
--
--      * no date of birth: never. A devotee who has not told us when they were
--        born is not greeted on a guess, and is not nagged about it here.
--      * the ordinary case: same month, same day.
--      * 29 February: greeted on the 28th in a year that has no 29th. Someone
--        born on a leap day has a birthday every year like everybody else, and
--        the alternative is a congregation that greets them once every four
--        years and looks like it forgot them the other three.
--
--    A devotee born on 28 February is greeted on the 28th, in every year,
--    including leap years — the leap-day clause only fires in a year where the
--    29th does not exist, so the two never collide and nobody is greeted twice.
--
--    Whether the year has a 29th is asked of the calendar rather than of the
--    divisible-by-400 rule: the day before the 1st of March is the last day of
--    February, and Postgres knows which year that is 28 and which 29.
-- ---------------------------------------------------------------------------

create or replace function public.birthday_falls_on(
  p_date_of_birth date,
  p_on_date date
)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select case
    when p_date_of_birth is null or p_on_date is null then false
    else
      (
        extract(month from p_date_of_birth) = extract(month from p_on_date)
        and extract(day from p_date_of_birth) = extract(day from p_on_date)
      )
      or (
        extract(month from p_date_of_birth) = 2
        and extract(day from p_date_of_birth) = 29
        and extract(month from p_on_date) = 2
        and extract(day from p_on_date) = 28
        and extract(
          day from (make_date(extract(year from p_on_date)::integer, 3, 1) - 1)
        ) = 28
      )
  end
$$;

comment on function public.birthday_falls_on(date, date) is
  'True when this date of birth should be greeted on that day. A 29 February birthday is greeted on 28 February in a year that has no 29th.';

revoke all on function public.birthday_falls_on(date, date) from public, anon;
grant execute on function public.birthday_falls_on(date, date) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. ...and whether that day is today, in Chicago.
--
--    Separate from the rule above, and separately named rather than a
--    defaulted second argument, because two overloads that differ only by a
--    default are ambiguous the moment anybody calls the short form.
--
--    Chicago, never UTC and never the caller's session. now() is an instant;
--    from 7pm Chicago onwards that instant is already tomorrow in UTC, so a
--    birthday test written against current_date greets the whole congregation
--    a day early every evening. current_date and now()::date are worse still —
--    they follow whatever timezone the caller's session happens to carry, so
--    the answer changes with who is asking. The rest of this codebase reads
--    `(now() at time zone 'America/Chicago')::date`, and so does this.
-- ---------------------------------------------------------------------------

create or replace function public.is_birthday_today(p_date_of_birth date)
returns boolean
language sql
stable
set search_path = ''
as $$
  select public.birthday_falls_on(
    p_date_of_birth,
    (now() at time zone 'America/Chicago')::date
  )
$$;

comment on function public.is_birthday_today(date) is
  'True when this date of birth is being celebrated today in America/Chicago.';

revoke all on function public.is_birthday_today(date) from public, anon;
grant execute on function public.is_birthday_today(date) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. The kind, restated whole.
--
--    The constraint is replaced rather than altered, so every kind already in
--    use has to be listed again or it is silently outlawed. This is
--    202608040043_sanga_powers.sql's list — sanga_deleted included — with
--    birthday_today appended.
--
--    src/features/notifications/types.ts carries the same list, and a jest
--    test compares the two. It must gain birthday_today as well.
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
      'remote'
    )
  );

-- The re-run guard below asks "has this devotee already been wished today?",
-- which is a lookup by the celebrant's id inside the payload. Small table or
-- not, the job walks it once per birthday and this keeps that free.
create index if not exists app_notifications_birthday_guard_idx
  on public.app_notifications ((data ->> 'devoteeId'), created_at desc)
  where kind = 'birthday_today';

-- ---------------------------------------------------------------------------
-- 4. Telling the congregation.
--
--    The same shape as remind_incomplete_profiles: a definer function
--    returning how many notifications it queued, revoked from everybody, run
--    by pg_cron.
--
--    And the same guard, for the same reason. The job may be run twice in a
--    day — a retry, a manual poke, an overlapping cron tick — and a devotee
--    should not be wished a happy birthday twice by the same person's phone.
--    remind_incomplete_profiles looks for its own kind within the last twenty
--    hours before it nags again; this looks for its own kind, for this
--    celebrant, within the same window. A birthday comes round once a year, so
--    the guard that makes it once a day also makes it once a year.
--
--    The guard is keyed on the celebrant rather than the recipient, because
--    the thing that must happen once is the birthday, not the delivery: a
--    devotee who joins between the two runs is not a reason to greet everybody
--    again.
--
--    The birthday devotee is left out of their own announcement. They know.
-- ---------------------------------------------------------------------------

create or replace function public.announce_birthdays()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  celebrant record;
  devotee record;
  sent integer := 0;
begin
  for celebrant in
    select users.id, users.name
    from public.users
    where users.date_of_birth is not null
      and public.is_birthday_today(users.date_of_birth)
      and not exists (
        select 1 from public.app_notifications already
        where already.kind = 'birthday_today'
          and already.data ->> 'devoteeId' = users.id::text
          and already.created_at > now() - interval '20 hours'
      )
    order by users.name
  loop
    for devotee in
      select others.id from public.users others where others.id <> celebrant.id
    loop
      perform public.queue_app_notification(
        devotee.id,
        'birthday_today',
        'A birthday today',
        'It''s ' || coalesce(nullif(trim(celebrant.name), ''), 'A devotee')
          || '''s birthday — wish them a happy birthday!',
        jsonb_build_object('devoteeId', celebrant.id)
      );
      sent := sent + 1;
    end loop;
  end loop;
  return sent;
end;
$$;

comment on function public.announce_birthdays() is
  'Wishes every devotee whose birthday falls today in Chicago, telling everybody else and not them. Returns the number of notifications queued. Safe to run more than once a day.';

revoke all on function public.announce_birthdays() from public, anon, authenticated;

-- Early morning in Chicago, so the greeting is waiting when a devotee picks up
-- their phone rather than arriving at lunchtime. pg_cron reads the server's
-- clock, which on Supabase is UTC: 13:00 UTC is 8am in Chicago through the
-- summer and 7am through the winter, and both are the morning.
--
-- Guarded the way 202608030009_weekly_seva_visibility_and_coverage.sql guards
-- its schedule: nothing happens at all where pg_cron is not installed, which
-- is every local and CI database this file is applied to.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    if not exists (select 1 from cron.job where jobname = 'announce-birthdays') then
      perform cron.schedule(
        'announce-birthdays', '0 13 * * *',
        'select public.announce_birthdays();'
      );
    end if;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Sangas in the congregation record.
--
--    The export already answers "who is this devotee?" and now answers "and
--    which circles of the temple are they actually in?" — as a plain
--    comma-separated list of names, because the sheet is read by a person and
--    a column of uuids is a column nobody reads.
--
--    Only the circles that presently exist: a retired sanga (active = false)
--    and a deleted one (deleted_at set) are two different kinds of gone, and
--    both are gone. A sanga still waiting on the President, or one they turned
--    down, is not the temple's yet and is not part of anybody's record of
--    standing in it, so the list is approved sangas only. A devotee in none
--    gets an empty cell rather than a null, which is what a spreadsheet wants.
--
--    Postgres will not change a function's return type in place, so the old
--    one is dropped first, by its full argument list. It takes no arguments,
--    but the habit matters: a defaulted overload left behind makes every call
--    ambiguous, and that has broken this repo before.
-- ---------------------------------------------------------------------------

drop function if exists public.list_devotee_profiles();

create or replace function public.list_devotee_profiles()
returns table (
  id uuid,
  name text,
  email text,
  phone text,
  photo_url text,
  role_name text,
  joined_at timestamptz,
  date_of_birth date,
  birth_place text,
  address text,
  spiritual_mentor text,
  is_initiated boolean,
  initiation_date date,
  diksha_guru text,
  has_first_initiation boolean,
  first_initiation_date date,
  first_diksha_guru text,
  has_second_initiation boolean,
  second_initiation_date date,
  second_diksha_guru text,
  profile_updated_at timestamptz,
  completion integer,
  sanga_names text
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    users.id, users.name, users.email, users.phone, users.photo_url,
    roles.name, users.joined_at, users.date_of_birth, users.birth_place,
    users.address, users.spiritual_mentor, users.is_initiated,
    users.initiation_date, users.diksha_guru, users.has_first_initiation,
    users.first_initiation_date, users.first_diksha_guru,
    users.has_second_initiation, users.second_initiation_date,
    users.second_diksha_guru, users.profile_updated_at,
    public.profile_completion(users.id),
    coalesce(
      (
        select string_agg(sanga.name, ', ' order by lower(sanga.name))
        from public.sanga_members membership
        join public.sangas sanga on sanga.id = membership.sanga_id
        where membership.devotee_id = users.id
          and sanga.status = 'approved'
          and sanga.active
          and sanga.deleted_at is null
      ),
      ''
    )
  from public.users
  join public.roles on roles.id = users.role_id
  where public.has_permission('app.view_all')
  order by users.joined_at desc
$$;

comment on function public.list_devotee_profiles() is
  'The congregation record for the President and Tech Admin, one row per devotee, with their live sanga memberships as a comma-separated list.';

revoke all on function public.list_devotee_profiles() from public, anon;
grant execute on function public.list_devotee_profiles() to authenticated;

do $$
begin
  raise notice 'birthdays and congregation sangas applied';
end;
$$;
