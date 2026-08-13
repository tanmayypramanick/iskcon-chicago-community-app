-- Birthdays become a prompt to the temple, not a broadcast to everybody.
--
-- 202608040044_birthdays_and_congregation.sql told the whole congregation, once
-- a day, that it was somebody's birthday. The temple has asked for that to
-- stop, and the reason is worth writing down rather than treating this as a
-- volume complaint: a greeting that arrives on two hundred phones because a
-- cron job read a date is not the temple wishing anybody anything. It is the
-- database doing it. What the President and the Tech Admin want is to be told
-- privately — "it is Ananda's birthday today" — and then to decide, as people,
-- whether the temple says something and in what words.
--
-- So there are three pieces here, and the split matters:
--
--   * todays_birthdays()               — the fact. Who is celebrating today.
--   * prompt_birthday_wishes()         — the nudge. Sent to app.view_all only.
--   * suggested_birthday_announcement()— the words, ready to be edited.
--
-- The third exists so that the temple's voice lives in the temple's database
-- rather than in a string literal in a React Native screen. The President taps
-- "It's Ananda's birthday today, wish them", the composer opens already filled
-- in, and they change whatever they like before posting. Nothing is posted for
-- them: the announcement, if there is one, goes through create_announcement
-- like every other notice, with a human's name on it.
--
-- Nobody but the President and the Tech Admin learns anything automatically.
-- app.view_all is held by exactly those two roles
-- (202608020001_access_levels.sql), and it is the same key
-- list_devotee_profiles already uses for the congregation record — the birthday
-- of a devotee who has not published it is the same class of fact.
--
-- Requires 202608040030_devotee_profiles.sql, 202608040040_announcements.sql
-- and 202608040044_birthdays_and_congregation.sql (birthday_falls_on,
-- is_birthday_today and the guard index this file keeps using).

-- ---------------------------------------------------------------------------
-- 0. The notification kind.
--
--    Deliberately NOT restated here, and this is the one place in this file
--    where the house style is not followed on purpose.
--
--    'birthday_today' has been in the constraint since 0044 and is still in it
--    at 202608040050_sponsorship_campaigns.sql, the most recent migration to
--    touch it. This migration introduces no new kind — it changes who receives
--    an existing one — so dropping and re-adding the constraint here would buy
--    nothing and would cost the one thing that keeps going wrong: a list
--    restated by hand at position N silently outlaws every kind added by a
--    migration between N and here. That has broken this repo repeatedly, and
--    another migration is being written in parallel with this one.
--
--    What is worth doing is asserting the dependency instead of assuming it, so
--    that a later partial restatement fails loudly here, while it is being
--    applied, rather than quietly at 7am when the job runs.
-- ---------------------------------------------------------------------------

do $$
declare
  v_definition text;
begin
  select pg_get_constraintdef(pg_constraint.oid) into v_definition
  from pg_constraint
  where conname = 'app_notifications_kind_check'
    and conrelid = 'public.app_notifications'::regclass;

  if v_definition is null then
    raise exception
      'The app_notifications kind constraint is missing; apply the earlier migrations first.';
  end if;

  if position('''birthday_today''' in v_definition) = 0 then
    raise exception
      'The kind birthday_today has been dropped from app_notifications_kind_check by a later migration. Restate that list whole, including birthday_today.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 1. Whose birthday it is today.
--
--    Today in Chicago, never in UTC and never in the caller's session: the
--    President opening the app from a phone still set to a holiday timezone
--    must see the same list as the Tech Admin sitting in the temple office.
--    That whole question is already settled by is_birthday_today, which is
--    birthday_falls_on asked about `(now() at time zone 'America/Chicago')::date`
--    — the same reading 202608040040_announcements.sql uses to decide when a
--    notice has run out.
--
--    The 29th of February follows the rule 0044 chose and documented, unchanged
--    here: a devotee born on a leap day is greeted on the 28th in a year that
--    has no 29th, rather than on the 1st of March and rather than being skipped
--    for three years out of four. The 1st of March would be defensible in the
--    abstract and is wrong here for a concrete reason — a congregation that
--    greets somebody in a different month from the one they were born in looks
--    like it got it wrong, and February is where their birthday is.
--
--    turning_age is the difference of the calendar years, which is what anybody
--    writing the announcement wants ("Ananda turns 40 today"). It is null when
--    the year of birth would make it nonsense — a devotee who gave 1900 as a
--    placeholder is not turning 126 in a notice the temple posts.
--
--    Empty for everybody else. Not an error, an empty set: this function backs
--    a card that a plain devotee's app may perfectly reasonably ask for and
--    simply must not draw, and a raised exception there is an error screen for
--    something that is not an error. The refusal that must be loud is
--    suggested_birthday_announcement below, which is the temple speaking.
-- ---------------------------------------------------------------------------

create or replace function public.todays_birthdays()
returns table (
  devotee_id uuid,
  name text,
  photo_url text,
  date_of_birth date,
  turning_age integer
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    users.id,
    users.name,
    users.photo_url,
    users.date_of_birth,
    case
      when extract(year from (now() at time zone 'America/Chicago')::date)
             - extract(year from users.date_of_birth) between 0 and 120
      then (
        extract(year from (now() at time zone 'America/Chicago')::date)
          - extract(year from users.date_of_birth)
      )::integer
    end
  from public.users
  where public.has_permission('app.view_all')
    and users.date_of_birth is not null
    and public.is_birthday_today(users.date_of_birth)
  order by users.name
$$;

comment on function public.todays_birthdays() is
  'The devotees whose birthday falls today in America/Chicago, for the President and the Tech Admin. Empty for everybody else. A 29 February birthday appears on 28 February in a year that has no 29th.';

revoke all on function public.todays_birthdays() from public, anon;
grant execute on function public.todays_birthdays() to authenticated;

-- ---------------------------------------------------------------------------
-- 2. The words the temple would use, if it decides to say something.
--
--    Warm, short, and entirely editable. The point of putting it here rather
--    than in the client is that the temple's voice is the temple's: when the
--    President asks for "Hare Krishna" at the end instead of "Hari bol", that
--    is one migration, not an app release that half the congregation will not
--    install for a month.
--
--    they/them throughout, and nothing below reads gender. The column exists,
--    is usually empty, and a public greeting that guesses wrong about a real
--    person is worse in every way than one that does not guess — 0044 made that
--    call for the notification and it holds all the more for an announcement
--    that goes on the noticeboard under somebody's name.
--
--    Refused outright rather than returning nothing, because unlike the list
--    above this is nobody's idle read: a caller here is composing something the
--    congregation will see.
--
--    It does not require the birthday to be today. The President who opens the
--    prompt at eleven at night and posts it over morning tea is still posting a
--    birthday greeting, and a function that refused them at 00:01 would be
--    pedantry that costs the temple the message.
-- ---------------------------------------------------------------------------

create or replace function public.suggested_birthday_announcement(
  p_devotee_id uuid
)
returns table (
  title text,
  body text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_name text;
begin
  if auth.uid() is null then
    raise exception 'Sign in to write a birthday announcement.';
  end if;

  if not public.has_permission('app.view_all') then
    raise exception 'Only the President or the Tech Admin can see whose birthday it is.';
  end if;

  select nullif(trim(coalesce(users.name, '')), '') into v_name
  from public.users
  where users.id = p_devotee_id;

  if not found then
    raise exception 'That devotee could not be found.';
  end if;

  if v_name is null then
    -- A row with no usable name. Rare, and no reason to hand back a greeting
    -- addressed to an empty string.
    title := 'Happy birthday!';
    body := 'One of our devotees celebrates their birthday today. '
      || 'Please join us in wishing them a very happy birthday and a beautiful '
      || 'year ahead in Krishna''s service. Hare Krishna!';
  else
    title := 'Happy birthday, ' || v_name || '!';
    body := 'Today is ' || v_name || '''s birthday. '
      || 'Please join us in wishing them a very happy birthday and a beautiful '
      || 'year ahead in Krishna''s service. Hare Krishna!';
  end if;

  return next;
end;
$$;

comment on function public.suggested_birthday_announcement(uuid) is
  'The prefilled wording for a birthday announcement, for the President and the Tech Admin to edit before posting. Refuses everybody else.';

revoke all on function public.suggested_birthday_announcement(uuid) from public, anon;
grant execute on function public.suggested_birthday_announcement(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. The prompt, replacing the broadcast.
--
--    announce_birthdays queued one notification per devotee per birthday. It is
--    dropped rather than left in place returning zero: a function called
--    "announce" that no longer announces is a trap for the next person reading
--    this schema, and a shim kept for the cron job is a shim nobody removes.
--    The pg_cron entry is re-pointed at the bottom of this section, which is
--    the whole of what depended on it — nothing in supabase/migrations and
--    nothing in src/ ever called it.
--
--    It never wrote an announcements row, so there is nothing to unwind on the
--    noticeboard; what it wrote was app_notifications rows, and those are last
--    week's greetings, already read. They are left alone.
--
--    Who is told: holders of app.view_all — the President and the Tech Admin,
--    and nobody else. Not the celebrant, even when the celebrant is the
--    President: they know it is their birthday, and a prompt asking them to
--    consider wishing themselves is a bug with a straight face. The other
--    holder still gets it and can still post.
--
--    Body and payload: the body names the devotee, because a notification that
--    says "a birthday today" and nothing else is a notification you have to
--    open the app to understand. The payload carries devoteeId and name so the
--    button — "It's Ananda's birthday today, wish them" — can be drawn from the
--    notification alone, and so that tapping it can open the composer without a
--    round trip to find out who it was about.
--
--    Idempotence, unchanged from 0044 and from remind_incomplete_profiles
--    before it: the job looks for its own kind, for this celebrant, inside the
--    last twenty hours. A retry, a manual poke, an overlapping tick — none of
--    them prompt twice. The guard is keyed on the celebrant in the payload
--    rather than on the recipient, because the thing that happens once is the
--    birthday: a Tech Admin appointed between two runs is not a reason to
--    prompt the President again. app_notifications_birthday_guard_idx, created
--    by 0044 on exactly that expression, still serves it.
-- ---------------------------------------------------------------------------

drop function if exists public.announce_birthdays();

create or replace function public.prompt_birthday_wishes()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  celebrant record;
  recipient record;
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
    for recipient in
      select distinct users.id
      from public.users
      join public.role_permissions
        on role_permissions.role_id = users.role_id
       and role_permissions.permission_key = 'app.view_all'
      where users.id <> celebrant.id
    loop
      perform public.queue_app_notification(
        recipient.id,
        'birthday_today',
        'A birthday today',
        'It''s ' || coalesce(nullif(trim(celebrant.name), ''), 'a devotee')
          || '''s birthday today — you can post an announcement to wish them.',
        jsonb_build_object(
          'devoteeId', celebrant.id,
          'name', coalesce(nullif(trim(celebrant.name), ''), 'A devotee')
        )
      );
      sent := sent + 1;
    end loop;
  end loop;
  return sent;
end;
$$;

comment on function public.prompt_birthday_wishes() is
  'Tells the President and the Tech Admin, and nobody else, whose birthday falls today in Chicago, so they can decide whether to post about it. Returns the number of prompts queued. Safe to run more than once a day.';

revoke all on function public.prompt_birthday_wishes() from public, anon, authenticated;

-- The same early morning as before — 13:00 UTC is 8am in Chicago through the
-- summer and 7am through the winter — so the prompt is waiting when the
-- President picks up their phone and there is a whole day left to post in.
--
-- The old job is removed by name before the new one is added, so a database
-- that has run 0044 does not keep calling a function this migration just
-- dropped. Guarded on pg_cron the way 0030 and 0044 guard theirs: nothing
-- happens at all where the extension is absent, which is every local and CI
-- database this file is applied to.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    if exists (select 1 from cron.job where jobname = 'announce-birthdays') then
      perform cron.unschedule('announce-birthdays');
    end if;
    if exists (select 1 from cron.job where jobname = 'prompt-birthday-wishes') then
      perform cron.unschedule('prompt-birthday-wishes');
    end if;
    perform cron.schedule(
      'prompt-birthday-wishes', '0 13 * * *',
      'select public.prompt_birthday_wishes();'
    );
  end if;
end;
$$;

do $$
begin
  raise notice 'birthday prompts applied';
end;
$$;
