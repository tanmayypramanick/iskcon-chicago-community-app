-- Functional verification for 202608040044_birthdays_and_congregation.sql.
--
-- Rolled back at the end. Every local is prefixed v_ so it can never shadow a
-- column name. Anything that must be refused is attempted as the devotee who
-- would really attempt it, under `set local role authenticated`, so the grants
-- and the permission checks are the thing being tested rather than superuser
-- rights quietly waving everything through. Inbox assertions are made after
-- `reset role`, because a devotee cannot — and should not be able to — read
-- somebody else's notifications.
--
-- The five people in this script:
--   President  ...0001  holds app.view_all; exports the congregation record
--   Today      ...0002  born on today's day of the year, in Chicago
--   Tomorrow   ...0003  born on tomorrow's, and must hear nothing today
--   Unknown    ...0004  has never told us when they were born
--   Volunteer  ...0005  the nearest access level that must still be refused
--
-- The clock cannot be moved inside a transaction, so the 29 February rule is
-- proved against public.birthday_falls_on, which takes the day as an argument
-- for exactly that reason, and section 2 then proves that is_birthday_today —
-- the function the job actually calls — is that same rule asked about Chicago's
-- today and nobody else's.
--
-- The final row must read: birthdays and congregation verification passed

begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('b0000000-0000-0000-0000-000000000001', 'bday-president@example.test', '{"name":"Bday President"}'),
  ('b0000000-0000-0000-0000-000000000002', 'bday-today@example.test', '{"name":"Bday Today"}'),
  ('b0000000-0000-0000-0000-000000000003', 'bday-tomorrow@example.test', '{"name":"Bday Tomorrow"}'),
  ('b0000000-0000-0000-0000-000000000004', 'bday-unknown@example.test', '{"name":"Bday Unknown"}'),
  ('b0000000-0000-0000-0000-000000000005', 'bday-volunteer@example.test', '{"name":"Bday Volunteer"}');

update public.users
set role_id = (select roles.id from public.roles where roles.name = 'president')
where email = 'bday-president@example.test';

update public.users
set role_id = (select roles.id from public.roles where roles.name = 'volunteer')
where email = 'bday-volunteer@example.test';

-- 1988 is a leap year, so a day-of-year taken from any of today, tomorrow or
-- the 29th of February can be rebuilt in it without falling off the calendar.
update public.users
set date_of_birth = make_date(
  1988,
  extract(month from (now() at time zone 'America/Chicago')::date)::integer,
  extract(day from (now() at time zone 'America/Chicago')::date)::integer
)
where email = 'bday-today@example.test';

update public.users
set date_of_birth = make_date(
  1988,
  extract(month from (now() at time zone 'America/Chicago')::date + 1)::integer,
  extract(day from (now() at time zone 'America/Chicago')::date + 1)::integer
)
where email = 'bday-tomorrow@example.test';

-- ---------------------------------------------------------------------------
-- 0. The kind was added, and no kind already in use was dropped on the way.
--
--    The CHECK constraint is replaced whole rather than extended, so a partial
--    restatement silently outlaws whatever was left out — which has happened
--    here twice. sanga_deleted, the newest kind before this migration, is the
--    one that keeps getting lost, so every kind is checked by actually writing
--    one rather than by reading the constraint text.
-- ---------------------------------------------------------------------------

do $$
declare
  v_kind text;
  v_definition text;
begin
  select pg_get_constraintdef(pg_constraint.oid) into v_definition
  from pg_constraint
  where conname = 'app_notifications_kind_check'
    and conrelid = 'public.app_notifications'::regclass;

  if v_definition is null then
    raise exception 'The app_notifications kind constraint is gone entirely.';
  end if;

  foreach v_kind in array array[
    'service_open', 'service_offer', 'service_recurring_offer',
    'service_offer_response', 'service_joined', 'service_left',
    'service_started', 'service_completed', 'service_cancelled',
    'service_deleted', 'service_coverage_needed', 'service_coverage_resolved',
    'recurring_interest_submitted', 'recurring_interest_reviewed',
    'seva_verification_requested', 'seva_verification_reviewed',
    'weekly_offer_countered', 'weekly_offer_counter_reviewed',
    'access_request_submitted', 'access_request_reviewed',
    'devotee_joined', 'profile_incomplete',
    'sanga_created', 'sanga_reviewed', 'sanga_join_requested',
    'sanga_join_reviewed', 'sanga_member_added', 'sanga_member_removed',
    'sanga_member_left', 'sanga_admin_transferred', 'sanga_deleted',
    'announcement_posted', 'feedback_reviewed', 'care_reply',
    'birthday_today', 'remote'
  ]
  loop
    begin
      insert into public.app_notifications (user_id, kind, title, body)
      values ('b0000000-0000-0000-0000-000000000001', v_kind, 'kind check', 'kind check');
    exception when others then
      raise exception 'The kind % is no longer allowed by the constraint.', v_kind;
    end;
  end loop;

  -- ...and it is still a closed list, not an open one.
  begin
    insert into public.app_notifications (user_id, kind, title, body)
    values ('b0000000-0000-0000-0000-000000000001', 'not_a_kind', 'x', 'x');
    raise exception 'The kind constraint accepts anything at all.';
  exception
    when check_violation then null;
  end;
end;
$$;

delete from public.app_notifications where title = 'kind check';

-- ---------------------------------------------------------------------------
-- 1. The rule itself, including the 29th of February.
-- ---------------------------------------------------------------------------

do $$
begin
  -- The ordinary case.
  if not public.birthday_falls_on(date '1985-07-14', date '2026-07-14') then
    raise exception 'A birthday on the day itself was not recognised.';
  end if;
  if public.birthday_falls_on(date '1985-07-14', date '2026-07-15') then
    raise exception 'A birthday was recognised the day after.';
  end if;
  if public.birthday_falls_on(date '1985-07-14', date '2026-07-13') then
    raise exception 'A birthday was recognised the day before.';
  end if;
  if public.birthday_falls_on(date '1985-07-14', date '2026-06-14') then
    raise exception 'A birthday was recognised in the wrong month.';
  end if;

  -- No date of birth is not a birthday, on any day.
  if public.birthday_falls_on(null, date '2026-07-14') then
    raise exception 'A devotee with no date of birth was given a birthday.';
  end if;

  -- 29 February, in a leap year: the real day, and only the real day.
  if not public.birthday_falls_on(date '2000-02-29', date '2028-02-29') then
    raise exception 'A leap-day devotee was not greeted on the 29th of a leap year.';
  end if;
  if public.birthday_falls_on(date '2000-02-29', date '2028-02-28') then
    raise exception 'A leap-day devotee was greeted early in a year that has a 29th.';
  end if;

  -- 29 February, in the three years out of four that have no 29th: greeted on
  -- the 28th, rather than skipped until the next leap year.
  if not public.birthday_falls_on(date '2000-02-29', date '2027-02-28') then
    raise exception 'A leap-day devotee was skipped in a non-leap year.';
  end if;
  if not public.birthday_falls_on(date '2000-02-29', date '2029-02-28') then
    raise exception 'A leap-day devotee was skipped in the year after a leap year.';
  end if;
  -- 1900 was not a leap year, whatever divisible-by-four says.
  if not public.birthday_falls_on(date '1896-02-29', date '1900-02-28') then
    raise exception 'The century rule was got wrong: 1900 has no 29th of February.';
  end if;
  -- 2000 was.
  if public.birthday_falls_on(date '1996-02-29', date '2000-02-28') then
    raise exception 'The 400-year rule was got wrong: 2000 does have a 29th.';
  end if;

  -- And the greeting does not leak onto the 1st of March, which is where a
  -- naive "day after the 28th" implementation puts it.
  if public.birthday_falls_on(date '2000-02-29', date '2027-03-01') then
    raise exception 'A leap-day devotee was greeted on the 1st of March.';
  end if;

  -- Somebody genuinely born on the 28th is greeted on the 28th every year, and
  -- never on the 29th. The leap-day clause must not steal or duplicate them.
  if not public.birthday_falls_on(date '1990-02-28', date '2028-02-28') then
    raise exception 'A devotee born on the 28th was not greeted in a leap year.';
  end if;
  if public.birthday_falls_on(date '1990-02-28', date '2028-02-29') then
    raise exception 'A devotee born on the 28th was also greeted on the 29th.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Today means today in Chicago, whoever is asking and from wherever.
--
--    The likeliest mistake is current_date or now()::date, both of which read
--    the caller's session timezone rather than the temple's. Asking the same
--    question from five session timezones spanning UTC-12 to UTC+14 catches it
--    at any hour: at least one of them is always on a different calendar day
--    from Chicago, so an implementation that follows the session must give a
--    different answer to at least one of these.
--
--    The second assertion is the wiring: is_birthday_today is birthday_falls_on
--    asked about Chicago's today. That is what carries every rule proved above
--    — the leap day included — into the job itself.
-- ---------------------------------------------------------------------------

do $$
declare
  v_chicago_today date := (now() at time zone 'America/Chicago')::date;
  v_born_today date;
  v_born_tomorrow date;
  v_zone text;
begin
  v_born_today := make_date(1988,
    extract(month from v_chicago_today)::integer,
    extract(day from v_chicago_today)::integer);
  v_born_tomorrow := make_date(1988,
    extract(month from v_chicago_today + 1)::integer,
    extract(day from v_chicago_today + 1)::integer);

  foreach v_zone in array
    array['UTC', 'Pacific/Kiritimati', 'Etc/GMT+12', 'Asia/Tokyo', 'America/Chicago']
  loop
    perform set_config('timezone', v_zone, true);

    if not public.is_birthday_today(v_born_today) then
      raise exception
        'A devotee whose birthday is today in Chicago was missed when the caller sat in % (Chicago %, session %).',
        v_zone, v_chicago_today, (now())::date;
    end if;
    if public.is_birthday_today(v_born_tomorrow) then
      raise exception
        'A devotee whose birthday is tomorrow in Chicago was greeted when the caller sat in % (Chicago %, session %).',
        v_zone, v_chicago_today, (now())::date;
    end if;
    if public.is_birthday_today(null) then
      raise exception 'A null date of birth was a birthday in %.', v_zone;
    end if;

    -- The whole of the rule, not just the two dates above, reaches the job.
    if public.is_birthday_today(date '2000-02-29')
       is distinct from public.birthday_falls_on(date '2000-02-29', v_chicago_today)
    then
      raise exception
        'is_birthday_today disagrees with the rule about a leap-day birthday in %.', v_zone;
    end if;
  end loop;

  perform set_config('timezone', 'UTC', true);
end;
$$;

reset timezone;

-- ---------------------------------------------------------------------------
-- 3. The job: only app.view_all is told, and the birthday devotee is not.
--
--    202608040053_birthday_prompts.sql replaced the broadcast this section used
--    to pin — every devotee told — with a prompt to the President and the Tech
--    Admin alone, and renamed the job to say so. The audience is proved
--    exhaustively in supabase/verification/birthday_prompts.sql; what is kept
--    here is the shape of the run, so that this script's five people still
--    exercise it end to end.
-- ---------------------------------------------------------------------------

do $$
declare
  v_sent integer;
  v_told integer;
  v_person record;
begin
  v_sent := public.prompt_birthday_wishes();

  -- One birthday today, and one holder of app.view_all who is not the
  -- celebrant: the President.
  if v_sent <> 1 then
    raise exception 'The job queued % prompts rather than 1.', v_sent;
  end if;

  -- Not "roughly the right people": nobody without app.view_all heard a word.
  for v_person in
    select users.id, users.name from public.users
    where users.email like 'bday-%@example.test'
      and users.email <> 'bday-president@example.test'
  loop
    select count(*)::integer into v_told
    from public.app_notifications
    where app_notifications.user_id = v_person.id
      and app_notifications.kind = 'birthday_today';
    if v_told <> 0 then
      raise exception '% was told about the birthday % times rather than not at all.',
        v_person.name, v_told;
    end if;
  end loop;

  -- The birthday devotee is not told about their own birthday.
  select count(*)::integer into v_told
  from public.app_notifications
  where app_notifications.user_id = 'b0000000-0000-0000-0000-000000000002'
    and app_notifications.kind = 'birthday_today';
  if v_told <> 0 then
    raise exception 'The birthday devotee was wished a happy birthday by the app.';
  end if;

  -- Only one devotee had a birthday, so every notification names them.
  select count(*)::integer into v_told
  from public.app_notifications
  where app_notifications.kind = 'birthday_today'
    and app_notifications.data ->> 'devoteeId'
        <> 'b0000000-0000-0000-0000-000000000002';
  if v_told <> 0 then
    raise exception
      '% notifications were queued about somebody whose birthday is not today.', v_told;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Tomorrow's birthday, and no birthday at all.
--
--    Both are checked by who was named rather than by who was told: the
--    devotee born tomorrow and the devotee who never gave a date both appear
--    in section 3's list as recipients, and the mistake to catch is either of
--    them being the subject.
-- ---------------------------------------------------------------------------

do $$
declare
  v_named integer;
begin
  select count(*)::integer into v_named
  from public.app_notifications
  where app_notifications.kind = 'birthday_today'
    and app_notifications.data ->> 'devoteeId'
        = 'b0000000-0000-0000-0000-000000000003';
  if v_named <> 0 then
    raise exception 'A devotee whose birthday is tomorrow was greeted today.';
  end if;

  select count(*)::integer into v_named
  from public.app_notifications
  where app_notifications.kind = 'birthday_today'
    and app_notifications.data ->> 'devoteeId'
        = 'b0000000-0000-0000-0000-000000000004';
  if v_named <> 0 then
    raise exception 'A devotee who has given no date of birth was greeted anyway.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Running it again the same day wishes nobody a second time.
-- ---------------------------------------------------------------------------

do $$
declare
  v_again integer;
  v_total_before integer;
  v_total_after integer;
begin
  select count(*)::integer into v_total_before
  from public.app_notifications where kind = 'birthday_today';

  v_again := public.prompt_birthday_wishes();
  if v_again <> 0 then
    raise exception 'A second run the same day queued % more birthday greetings.', v_again;
  end if;

  -- Reported zero and meant it.
  select count(*)::integer into v_total_after
  from public.app_notifications where kind = 'birthday_today';
  if v_total_after <> v_total_before then
    raise exception 'A second run wrote % extra rows while reporting none.',
      v_total_after - v_total_before;
  end if;

  -- A third, for the retry that comes an hour after the retry.
  if public.prompt_birthday_wishes() <> 0 then
    raise exception 'A third run the same day greeted the congregation again.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. The words themselves: they/them, and the devotee named.
--
--    Gender is left unset on everybody in this script, which is the ordinary
--    case in the real table. The greeting must read the same either way.
-- ---------------------------------------------------------------------------

do $$
declare
  v_title text;
  v_body text;
begin
  select app_notifications.title, app_notifications.body into v_title, v_body
  from public.app_notifications
  where app_notifications.user_id = 'b0000000-0000-0000-0000-000000000001'
    and app_notifications.kind = 'birthday_today'
  limit 1;

  if v_body is null then
    raise exception 'The President was not told about the birthday at all.';
  end if;
  if v_body !~ 'Bday Today' then
    raise exception 'The greeting does not name the devotee: %', v_body;
  end if;
  if v_body !~* 'birthday' or v_title !~* 'birthday' then
    raise exception 'The greeting does not mention a birthday: % / %', v_title, v_body;
  end if;
  if v_body !~ '\mthem\M' then
    raise exception 'The greeting does not use they/them: %', v_body;
  end if;
  -- No gendered pronoun anywhere, however the sentence is arranged.
  if v_body ~* '\m(he|she|him|her|hers|his)\M' then
    raise exception 'The greeting guesses at gender: %', v_body;
  end if;
  -- And it asks for something, rather than merely reporting a fact.
  if v_body !~* 'wish' then
    raise exception 'The greeting does not ask anybody to wish them well: %', v_body;
  end if;
end;
$$;

-- Nothing about the job reads gender, so setting it changes not one word.
do $$
declare
  v_with_gender text;
  v_without_gender text;
begin
  select app_notifications.body into v_without_gender
  from public.app_notifications
  where app_notifications.user_id = 'b0000000-0000-0000-0000-000000000001'
    and app_notifications.kind = 'birthday_today'
  limit 1;

  update public.users set gender = 'female'
  where id = 'b0000000-0000-0000-0000-000000000002';
  delete from public.app_notifications where kind = 'birthday_today';

  perform public.prompt_birthday_wishes();

  select app_notifications.body into v_with_gender
  from public.app_notifications
  where app_notifications.user_id = 'b0000000-0000-0000-0000-000000000001'
    and app_notifications.kind = 'birthday_today'
  limit 1;

  if v_with_gender is distinct from v_without_gender then
    raise exception 'The greeting changed once a gender was known: % vs %',
      v_without_gender, v_with_gender;
  end if;

  update public.users set gender = null
  where id = 'b0000000-0000-0000-0000-000000000002';
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. The job is not something a devotee can set off.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-000000000005', true);
set local role authenticated;

do $$
declare
  v_refused boolean := false;
begin
  begin
    perform public.prompt_birthday_wishes();
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A volunteer ran the birthday job.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-000000000004', true);
set local role authenticated;

do $$
declare
  v_refused boolean := false;
begin
  begin
    perform public.prompt_birthday_wishes();
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A plain devotee ran the birthday job.';
  end if;
end;
$$;

reset role;

-- ---------------------------------------------------------------------------
-- 8. Sangas for the congregation record.
--
--    Written straight into the tables rather than through the RPCs: the point
--    here is which rows the export reads, and create_sanga plus a President's
--    approval plus an admin adding a member would queue a dozen notifications
--    that sections above count.
-- ---------------------------------------------------------------------------

insert into public.sangas (id, name, created_by, admin_id, status, reviewed_by, reviewed_at, active)
values
  ('b1000000-0000-0000-0000-000000000001', 'Youth Sanga',
   'b0000000-0000-0000-0000-000000000002', 'b0000000-0000-0000-0000-000000000002',
   'approved', 'b0000000-0000-0000-0000-000000000001', now(), true),
  ('b1000000-0000-0000-0000-000000000002', 'Bhagavad-gita Study',
   'b0000000-0000-0000-0000-000000000002', 'b0000000-0000-0000-0000-000000000002',
   'approved', 'b0000000-0000-0000-0000-000000000001', now(), true),
  ('b1000000-0000-0000-0000-000000000003', 'Retired Kirtan Sanga',
   'b0000000-0000-0000-0000-000000000002', 'b0000000-0000-0000-0000-000000000002',
   'approved', 'b0000000-0000-0000-0000-000000000001', now(), false),
  -- Left active on purpose. delete_sanga sets active = false alongside
  -- deleted_at, which means a record that only filtered on active would look
  -- right while testing nothing: the deleted circle would be hidden by the
  -- retirement rule. This row is deleted and not retired, so it is out of the
  -- record only if deleted_at is genuinely being read.
  ('b1000000-0000-0000-0000-000000000004', 'Deleted Sanga',
   'b0000000-0000-0000-0000-000000000002', 'b0000000-0000-0000-0000-000000000002',
   'approved', 'b0000000-0000-0000-0000-000000000001', now(), true),
  ('b1000000-0000-0000-0000-000000000005', 'Proposed Sanga',
   'b0000000-0000-0000-0000-000000000002', 'b0000000-0000-0000-0000-000000000002',
   'pending', null, null, true);

update public.sangas set deleted_at = now()
where id = 'b1000000-0000-0000-0000-000000000004';

insert into public.sanga_members (sanga_id, devotee_id, role) values
  ('b1000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000002', 'admin'),
  ('b1000000-0000-0000-0000-000000000002', 'b0000000-0000-0000-0000-000000000002', 'admin'),
  ('b1000000-0000-0000-0000-000000000003', 'b0000000-0000-0000-0000-000000000002', 'admin'),
  ('b1000000-0000-0000-0000-000000000004', 'b0000000-0000-0000-0000-000000000002', 'admin'),
  ('b1000000-0000-0000-0000-000000000005', 'b0000000-0000-0000-0000-000000000002', 'admin'),
  -- The volunteer is in one live circle and nothing else, so a devotee with a
  -- single membership is checked as well as one with two.
  ('b1000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000005', 'member');

-- ---------------------------------------------------------------------------
-- 9. Only the President and the Tech Admin may read the record at all.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-000000000005', true);
set local role authenticated;

do $$
declare
  v_rows integer;
begin
  select count(*)::integer into v_rows from public.list_devotee_profiles();
  if v_rows <> 0 then
    raise exception 'A volunteer read the whole congregation record (% rows).', v_rows;
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-000000000004', true);
set local role authenticated;

do $$
declare
  v_rows integer;
begin
  select count(*)::integer into v_rows from public.list_devotee_profiles();
  if v_rows <> 0 then
    raise exception 'A plain devotee read the whole congregation record (% rows).', v_rows;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 10. What the President exports.
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
  v_row record;
  v_sangas text;
begin
  -- Everything the record carried before is still there.
  select * into v_row from public.list_devotee_profiles() listed
  where listed.id = 'b0000000-0000-0000-0000-000000000002';
  if v_row.name <> 'Bday Today' then
    raise exception 'The record lost the devotee''s name.';
  end if;
  if v_row.email <> 'bday-today@example.test' then
    raise exception 'The record lost the devotee''s email.';
  end if;
  if v_row.date_of_birth is null then
    raise exception 'The record lost the date of birth.';
  end if;
  if v_row.completion is null then
    raise exception 'The record lost the completion percentage.';
  end if;

  -- Two live sangas, readable, alphabetical, comma separated.
  if v_row.sanga_names is distinct from 'Bhagavad-gita Study, Youth Sanga' then
    raise exception 'A member''s sangas came out as "%".', v_row.sanga_names;
  end if;

  -- Retired, deleted and not-yet-approved circles are all absent from it.
  if v_row.sanga_names ~ 'Retired' then
    raise exception 'A retired sanga is in the congregation record: %', v_row.sanga_names;
  end if;
  if v_row.sanga_names ~ 'Deleted' then
    raise exception 'A deleted sanga is in the congregation record: %', v_row.sanga_names;
  end if;
  if v_row.sanga_names ~ 'Proposed' then
    raise exception
      'A sanga still waiting on the President is in the congregation record: %',
      v_row.sanga_names;
  end if;

  -- One membership is a name, with no stray separator around it.
  select listed.sanga_names into v_sangas from public.list_devotee_profiles() listed
  where listed.id = 'b0000000-0000-0000-0000-000000000005';
  if v_sangas is distinct from 'Youth Sanga' then
    raise exception 'A devotee in one sanga came out as "%".', v_sangas;
  end if;

  -- A devotee in none gets an empty cell, not a null the spreadsheet renders
  -- as the word NULL.
  select listed.sanga_names into v_sangas from public.list_devotee_profiles() listed
  where listed.id = 'b0000000-0000-0000-0000-000000000003';
  if v_sangas is null then
    raise exception 'A devotee in no sanga got a null instead of an empty cell.';
  end if;
  if v_sangas <> '' then
    raise exception 'A devotee in no sanga was given the sangas "%".', v_sangas;
  end if;

  -- Retiring a live circle takes it off the record without touching the rest.
  if (select listed.sanga_names from public.list_devotee_profiles() listed
      where listed.id = 'b0000000-0000-0000-0000-000000000005') <> 'Youth Sanga' then
    raise exception 'The volunteer''s single sanga vanished before it was retired.';
  end if;
end;
$$;

reset role;
update public.sangas set active = false
where id = 'b1000000-0000-0000-0000-000000000001';

select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
  v_sangas text;
begin
  select listed.sanga_names into v_sangas from public.list_devotee_profiles() listed
  where listed.id = 'b0000000-0000-0000-0000-000000000005';
  if v_sangas <> '' then
    raise exception 'A retired sanga stayed on the record as "%".', v_sangas;
  end if;

  select listed.sanga_names into v_sangas from public.list_devotee_profiles() listed
  where listed.id = 'b0000000-0000-0000-0000-000000000002';
  if v_sangas is distinct from 'Bhagavad-gita Study' then
    raise exception 'Retiring one sanga disturbed the others: "%".', v_sangas;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 11. The recreate left exactly one function behind.
--
--     A defaulted overload left alongside the original makes every call
--     ambiguous, and "function is not unique" has broken this repo before.
-- ---------------------------------------------------------------------------

reset role;

do $$
declare
  v_count integer;
  v_result text;
begin
  select count(*)::integer into v_count
  from pg_proc
  join pg_namespace on pg_namespace.oid = pg_proc.pronamespace
  where pg_namespace.nspname = 'public'
    and pg_proc.proname = 'list_devotee_profiles';
  if v_count <> 1 then
    raise exception 'There are % versions of list_devotee_profiles.', v_count;
  end if;

  select count(*)::integer into v_count
  from pg_proc
  join pg_namespace on pg_namespace.oid = pg_proc.pronamespace
  where pg_namespace.nspname = 'public'
    and pg_proc.proname = 'prompt_birthday_wishes';
  if v_count <> 1 then
    raise exception 'There are % versions of prompt_birthday_wishes.', v_count;
  end if;

  -- The column was appended rather than inserted, so a client reading the
  -- record by position is not silently handed the wrong field.
  select pg_get_function_result(pg_proc.oid) into v_result
  from pg_proc
  join pg_namespace on pg_namespace.oid = pg_proc.pronamespace
  where pg_namespace.nspname = 'public'
    and pg_proc.proname = 'list_devotee_profiles';
  if v_result !~ 'completion integer, sanga_names text\)$' then
    raise exception 'The sangas column is not the last one: %', v_result;
  end if;

  -- And prompt_birthday_wishes is the same shape as remind_incomplete_profiles:
  -- no arguments, an integer count back.
  if (select pg_get_function_result(pg_proc.oid) from pg_proc
      join pg_namespace on pg_namespace.oid = pg_proc.pronamespace
      where pg_namespace.nspname = 'public'
        and pg_proc.proname = 'prompt_birthday_wishes') <> 'integer' then
    raise exception 'prompt_birthday_wishes does not return a count.';
  end if;
end;
$$;

do $$
begin
  raise notice 'all birthday and congregation checks passed';
end;
$$;

select 'birthdays and congregation verification passed' as result;

rollback;
