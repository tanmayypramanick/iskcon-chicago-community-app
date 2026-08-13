-- Functional verification for 202608040053_birthday_prompts.sql.
--
-- Rolled back at the end. Every local is prefixed v_ so it can never shadow a
-- column name. Anything that must be refused is attempted as the devotee who
-- would really attempt it, under `set local role authenticated`, so the grants
-- and the permission checks are the thing being tested rather than superuser
-- rights quietly waving everything through. Inbox assertions are made after
-- `reset role`, because a devotee cannot — and should not be able to — read
-- somebody else's notifications.
--
-- The people in this script:
--   President  ...0001  holds app.view_all
--   Tech       ...0002  holds app.view_all, and is the second half of "only"
--   Ananda     ...0003  born on today's day of the year, in Chicago
--   Bhakta     ...0004  born on tomorrow's, and must hear nothing today
--   Volunteer  ...0005  the nearest access level below, and must hear nothing
--   Head       ...0006  a Community Head — may post announcements, may NOT be
--                       told whose birthday it is. The likeliest wrong answer.
--   Leap       ...0007  born on 29 February; dated only inside section 8
--
-- What this script exists to prove:
--
--   1. todays_birthdays finds today's birthday and nobody else's.
--   2. It is empty for anybody without app.view_all — including a Community
--      Head, who can post announcements and still may not read this.
--   3. Today means today in Chicago from any session timezone.
--   4. The prompt reaches exactly the President and the Tech Admin. THE COUNT
--      IS ASSERTED ACROSS THE WHOLE TABLE, not just per recipient, because the
--      regression this migration exists to prevent is the old broadcast coming
--      back and a per-recipient check cannot see it.
--   5. The birthday devotee is not told about their own birthday, including
--      when the birthday devotee is the Tech Admin.
--   6. Running the job twice in a day prompts once.
--   7. The 29 February rule: greeted on the 28th in a year with no 29th, on the
--      29th in a year that has one, and never on 1 March.
--   8. suggested_birthday_announcement gives editable words to app.view_all and
--      refuses everybody else.
--
-- The clock cannot be moved inside a transaction, so the 29 February rule is
-- proved against public.birthday_falls_on, which takes the day as an argument
-- for exactly that reason, and section 8 then proves that todays_birthdays —
-- the function the app actually calls — is that same rule asked about Chicago.
--
-- The final row must read: birthday prompts verification passed

begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('bd000000-0000-0000-0000-000000000001', 'bp-president@example.test', '{"name":"BP President"}'),
  ('bd000000-0000-0000-0000-000000000002', 'bp-tech@example.test', '{"name":"BP Tech"}'),
  ('bd000000-0000-0000-0000-000000000003', 'bp-ananda@example.test', '{"name":"BP Ananda"}'),
  ('bd000000-0000-0000-0000-000000000004', 'bp-bhakta@example.test', '{"name":"BP Bhakta"}'),
  ('bd000000-0000-0000-0000-000000000005', 'bp-volunteer@example.test', '{"name":"BP Volunteer"}'),
  ('bd000000-0000-0000-0000-000000000006', 'bp-head@example.test', '{"name":"BP Head"}'),
  ('bd000000-0000-0000-0000-000000000007', 'bp-leap@example.test', '{"name":"BP Leap"}');

update public.users
set role_id = (select roles.id from public.roles where roles.name = 'president')
where email = 'bp-president@example.test';

update public.users
set role_id = (select roles.id from public.roles where roles.name = 'tech')
where email = 'bp-tech@example.test';

update public.users
set role_id = (select roles.id from public.roles where roles.name = 'volunteer')
where email = 'bp-volunteer@example.test';

update public.users
set role_id = (select roles.id from public.roles where roles.name = 'core')
where email = 'bp-head@example.test';

-- 1988 is a leap year, so a day-of-year taken from today or tomorrow can be
-- rebuilt in it without falling off the calendar.
update public.users
set date_of_birth = make_date(
      1988,
      extract(month from (now() at time zone 'America/Chicago')::date)::integer,
      extract(day from (now() at time zone 'America/Chicago')::date)::integer
    ),
    photo_url = 'https://example.supabase.co/storage/v1/object/public/devotee-photos/ananda.jpg'
where email = 'bp-ananda@example.test';

update public.users
set date_of_birth = make_date(
  1988,
  extract(month from (now() at time zone 'America/Chicago')::date + 1)::integer,
  extract(day from (now() at time zone 'America/Chicago')::date + 1)::integer
)
where email = 'bp-bhakta@example.test';

-- The Volunteer and the Head have told us nothing, which is also the case that
-- must never be guessed at.

-- The account creation trigger has already written devotee_joined rows to the
-- two holders of app.view_all. Nothing below counts those, but clearing the
-- table keeps every count in this script about birthdays alone.
delete from public.app_notifications;

-- ---------------------------------------------------------------------------
-- 0. app.view_all is exactly the President and the Tech Admin.
--
--    Every claim in this script about "only two people" rests on that, and it
--    is a fact about 202608020001_access_levels.sql rather than about this
--    migration. If a third role is ever given the key, this fails here and
--    names the role, rather than failing four sections later as an off-by-one
--    in a notification count.
-- ---------------------------------------------------------------------------

do $$
declare
  v_roles text;
begin
  select string_agg(roles.name, ', ' order by roles.name) into v_roles
  from public.roles
  join public.role_permissions on role_permissions.role_id = roles.id
  where role_permissions.permission_key = 'app.view_all';

  if v_roles is distinct from 'president, tech' then
    raise exception 'app.view_all is held by (%) rather than by president and tech.', v_roles;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 1. Whose birthday it is today, read by the President.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'bd000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
  v_row record;
  v_count integer;
begin
  select count(*)::integer into v_count from public.todays_birthdays();
  if v_count <> 1 then
    raise exception 'The President was shown % birthdays today rather than 1.', v_count;
  end if;

  select * into v_row from public.todays_birthdays();

  if v_row.devotee_id <> 'bd000000-0000-0000-0000-000000000003' then
    raise exception 'The wrong devotee was named as having a birthday: %', v_row.devotee_id;
  end if;
  if v_row.name is distinct from 'BP Ananda' then
    raise exception 'The birthday row does not carry the devotee''s name: %', v_row.name;
  end if;
  if v_row.photo_url is null then
    raise exception 'The birthday row does not carry the devotee''s photo.';
  end if;
  if v_row.date_of_birth is null then
    raise exception 'The birthday row does not carry the date of birth.';
  end if;

  -- The age is the difference of the calendar years, which is what anybody
  -- writing "Ananda turns 40 today" needs.
  if v_row.turning_age is distinct from
     (extract(year from (now() at time zone 'America/Chicago')::date)::integer - 1988)
  then
    raise exception 'The devotee is turning % rather than %.',
      v_row.turning_age,
      extract(year from (now() at time zone 'America/Chicago')::date)::integer - 1988;
  end if;
end;
$$;

reset role;

-- The Tech Admin sees the same list. "Only the President" would pass every
-- other assertion in this script.
select set_config('request.jwt.claim.sub', 'bd000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_count integer;
begin
  select count(*)::integer into v_count
  from public.todays_birthdays()
  where todays_birthdays.devotee_id = 'bd000000-0000-0000-0000-000000000003';
  if v_count <> 1 then
    raise exception 'The Tech Admin was not shown today''s birthday.';
  end if;

  -- Tomorrow's birthday is not today's, and a devotee who has told us nothing
  -- is not given a birthday on a guess.
  select count(*)::integer into v_count
  from public.todays_birthdays()
  where todays_birthdays.devotee_id in (
    'bd000000-0000-0000-0000-000000000004',
    'bd000000-0000-0000-0000-000000000005',
    'bd000000-0000-0000-0000-000000000006'
  );
  if v_count <> 0 then
    raise exception '% devotees without a birthday today were listed.', v_count;
  end if;
end;
$$;

reset role;

-- ---------------------------------------------------------------------------
-- 2. Everybody else gets an empty set.
--
--    The Community Head is the one that matters. They may post announcements —
--    may_post_announcements is services.manage_recurring, which they hold — so
--    the tempting implementation gates this on "can post" and hands the Head
--    the congregation's dates of birth. app.view_all is the gate.
-- ---------------------------------------------------------------------------

do $$
declare
  v_person text;
  v_count integer;
begin
  foreach v_person in array array[
    'bd000000-0000-0000-0000-000000000003',  -- the birthday devotee themselves
    'bd000000-0000-0000-0000-000000000004',
    'bd000000-0000-0000-0000-000000000005',  -- volunteer
    'bd000000-0000-0000-0000-000000000006'   -- community head
  ]
  loop
    perform set_config('request.jwt.claim.sub', v_person, true);
    set local role authenticated;

    select count(*)::integer into v_count from public.todays_birthdays();

    reset role;

    if v_count <> 0 then
      raise exception
        'A devotee without app.view_all (%) was shown % birthdays.', v_person, v_count;
    end if;
  end loop;
end;
$$;

reset role;

-- ---------------------------------------------------------------------------
-- 3. Today means today in Chicago, whoever is asking and from wherever.
--
--    The likeliest mistake is current_date or now()::date, both of which read
--    the caller's session timezone rather than the temple's. Asking the same
--    question from five session timezones spanning UTC-12 to UTC+14 catches it
--    at any hour: at least one of them is always on a different calendar day
--    from Chicago, so an implementation that follows the session must give a
--    different answer to at least one of these.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'bd000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
  v_zone text;
  v_today integer;
  v_tomorrow integer;
begin
  foreach v_zone in array
    array['UTC', 'Pacific/Kiritimati', 'Etc/GMT+12', 'Asia/Tokyo', 'America/Chicago']
  loop
    perform set_config('timezone', v_zone, true);

    select count(*)::integer into v_today
    from public.todays_birthdays()
    where todays_birthdays.devotee_id = 'bd000000-0000-0000-0000-000000000003';

    select count(*)::integer into v_tomorrow
    from public.todays_birthdays()
    where todays_birthdays.devotee_id = 'bd000000-0000-0000-0000-000000000004';

    if v_today <> 1 then
      raise exception
        'The devotee whose birthday is today in Chicago was missed when the caller sat in % (session date %).',
        v_zone, (now())::date;
    end if;
    if v_tomorrow <> 0 then
      raise exception
        'The devotee whose birthday is tomorrow in Chicago was listed when the caller sat in % (session date %).',
        v_zone, (now())::date;
    end if;
  end loop;

  perform set_config('timezone', 'UTC', true);
end;
$$;

reset role;
reset timezone;

-- ---------------------------------------------------------------------------
-- 4. The prompt goes to app.view_all and stops there.
--
--    This is the section the migration exists for. The old job queued one row
--    per devotee; the count below is taken across the entire table, so a
--    reinstated broadcast fails here even though every individual recipient
--    assertion would still be satisfied by it.
-- ---------------------------------------------------------------------------

do $$
declare
  v_sent integer;
  v_total integer;
  v_told integer;
  v_person record;
begin
  v_sent := public.prompt_birthday_wishes();

  -- One birthday, two holders of app.view_all, neither of them the celebrant.
  if v_sent <> 2 then
    raise exception 'The job reported % prompts rather than 2.', v_sent;
  end if;

  select count(*)::integer into v_total
  from public.app_notifications
  where app_notifications.kind = 'birthday_today';
  if v_total <> 2 then
    raise exception
      'The job wrote % birthday rows across the whole table rather than 2. The congregation is being broadcast to again.',
      v_total;
  end if;

  -- Named, not counted: each of the seven people in this script, one at a time.
  for v_person in
    select users.id, users.name, users.email from public.users
    where users.email like 'bp-%@example.test'
    order by users.email
  loop
    select count(*)::integer into v_told
    from public.app_notifications
    where app_notifications.user_id = v_person.id
      and app_notifications.kind = 'birthday_today';

    if v_person.email in ('bp-president@example.test', 'bp-tech@example.test') then
      if v_told <> 1 then
        raise exception '% was prompted % times rather than once.', v_person.name, v_told;
      end if;
    else
      if v_told <> 0 then
        raise exception
          '% holds no app.view_all and was told about the birthday % times.',
          v_person.name, v_told;
      end if;
    end if;
  end loop;

  -- Said plainly, because it is the temple's actual request: the birthday
  -- devotee is not told about their own birthday.
  select count(*)::integer into v_told
  from public.app_notifications
  where app_notifications.user_id = 'bd000000-0000-0000-0000-000000000003'
    and app_notifications.kind = 'birthday_today';
  if v_told <> 0 then
    raise exception 'The birthday devotee was sent a prompt about themselves.';
  end if;
end;
$$;

-- The same claim again, asked of the permission rather than of this script's
-- list of emails: nobody lacking app.view_all holds a birthday notification.
-- A devotee added to this database by any other means is covered too.
do $$
declare
  v_leaked integer;
begin
  select count(*)::integer into v_leaked
  from public.app_notifications
  join public.users on users.id = app_notifications.user_id
  where app_notifications.kind = 'birthday_today'
    and not exists (
      select 1 from public.role_permissions
      where role_permissions.role_id = users.role_id
        and role_permissions.permission_key = 'app.view_all'
    );
  if v_leaked <> 0 then
    raise exception
      '% birthday notifications reached devotees without app.view_all.', v_leaked;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. The words and the payload: enough to draw the button without a round trip.
-- ---------------------------------------------------------------------------

do $$
declare
  v_title text;
  v_body text;
  v_data jsonb;
begin
  select app_notifications.title, app_notifications.body, app_notifications.data
  into v_title, v_body, v_data
  from public.app_notifications
  where app_notifications.user_id = 'bd000000-0000-0000-0000-000000000001'
    and app_notifications.kind = 'birthday_today';

  if v_body is null then
    raise exception 'The President was not prompted at all.';
  end if;
  if v_body !~ 'BP Ananda' then
    raise exception 'The prompt does not name the devotee: %', v_body;
  end if;
  if v_body !~* 'birthday' or v_title !~* 'birthday' then
    raise exception 'The prompt does not mention a birthday: % / %', v_title, v_body;
  end if;
  -- they/them, and no guess at gender however the sentence is arranged. The
  -- gender column is set on nobody here, which is the ordinary case.
  if v_body !~ '\mthem\M' then
    raise exception 'The prompt does not use they/them: %', v_body;
  end if;
  if v_body ~* '\m(he|she|him|her|hers|his)\M' then
    raise exception 'The prompt guesses at gender: %', v_body;
  end if;

  -- `is distinct from`, not `<>`: a payload that has lost the key altogether
  -- compares NULL, and `if null then` is not `if false then` — it is the branch
  -- never being taken. The missing key is precisely what this is looking for.
  if v_data ->> 'devoteeId' is distinct from 'bd000000-0000-0000-0000-000000000003' then
    raise exception 'The payload does not carry the devotee id: %', v_data;
  end if;
  if v_data ->> 'name' is distinct from 'BP Ananda' then
    raise exception 'The payload does not carry the devotee name: %', v_data;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Running it again the same day prompts nobody a second time.
-- ---------------------------------------------------------------------------

do $$
declare
  v_again integer;
  v_before integer;
  v_after integer;
begin
  select count(*)::integer into v_before
  from public.app_notifications where kind = 'birthday_today';

  v_again := public.prompt_birthday_wishes();
  if v_again <> 0 then
    raise exception 'A second run the same day queued % more prompts.', v_again;
  end if;

  -- Reported zero and meant it.
  select count(*)::integer into v_after
  from public.app_notifications where kind = 'birthday_today';
  if v_after <> v_before then
    raise exception 'A second run wrote % extra rows while reporting none.',
      v_after - v_before;
  end if;

  -- A third, for the retry that comes an hour after the retry.
  if public.prompt_birthday_wishes() <> 0 then
    raise exception 'A third run the same day prompted again.';
  end if;

  select count(*)::integer into v_after
  from public.app_notifications where kind = 'birthday_today';
  if v_after <> v_before then
    raise exception 'A third run wrote % extra rows.', v_after - v_before;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. When the birthday belongs to one of the two people who would be told.
--
--    The Tech Admin does not need a notification asking them to consider
--    wishing themselves a happy birthday. The President still gets one, and can
--    still post.
-- ---------------------------------------------------------------------------

delete from public.app_notifications where kind = 'birthday_today';

update public.users
set date_of_birth = make_date(
  1975,
  extract(month from (now() at time zone 'America/Chicago')::date)::integer,
  extract(day from (now() at time zone 'America/Chicago')::date)::integer
)
where email = 'bp-tech@example.test';

do $$
declare
  v_sent integer;
  v_total integer;
  v_told integer;
begin
  v_sent := public.prompt_birthday_wishes();

  -- Two celebrants. Ananda's birthday reaches both holders; the Tech Admin's
  -- reaches the President only.
  if v_sent <> 3 then
    raise exception 'The job reported % prompts rather than 3.', v_sent;
  end if;

  select count(*)::integer into v_total
  from public.app_notifications where kind = 'birthday_today';
  if v_total <> 3 then
    raise exception 'The job wrote % rows across the whole table rather than 3.', v_total;
  end if;

  select count(*)::integer into v_told
  from public.app_notifications
  where app_notifications.kind = 'birthday_today'
    and app_notifications.user_id = 'bd000000-0000-0000-0000-000000000002'
    and app_notifications.data ->> 'devoteeId' = 'bd000000-0000-0000-0000-000000000002';
  if v_told <> 0 then
    raise exception 'The Tech Admin was prompted to wish themselves a happy birthday.';
  end if;

  select count(*)::integer into v_told
  from public.app_notifications
  where app_notifications.kind = 'birthday_today'
    and app_notifications.user_id = 'bd000000-0000-0000-0000-000000000001'
    and app_notifications.data ->> 'devoteeId' = 'bd000000-0000-0000-0000-000000000002';
  if v_told <> 1 then
    raise exception 'The President was not told about the Tech Admin''s birthday.';
  end if;
end;
$$;

update public.users set date_of_birth = null where email = 'bp-tech@example.test';
delete from public.app_notifications where kind = 'birthday_today';

-- ---------------------------------------------------------------------------
-- 8. The 29th of February.
--
--    The rule, restated because this migration depends on it: a devotee born on
--    a leap day is greeted on 28 February in a year that has no 29th — never on
--    1 March, and never skipped for three years out of four.
--
--    The clock cannot be moved inside a transaction, so the rule itself is
--    proved against birthday_falls_on, which takes the day as an argument. The
--    second half then wires it into the function the app calls: a devotee born
--    on 29 February is listed by todays_birthdays exactly when the rule says
--    they should be, for whatever today happens to be in Chicago when this runs.
-- ---------------------------------------------------------------------------

do $$
begin
  -- A year that has a 29th: the real day, and only the real day.
  if not public.birthday_falls_on(date '2000-02-29', date '2028-02-29') then
    raise exception 'A leap-day devotee was not greeted on the 29th of a leap year.';
  end if;
  if public.birthday_falls_on(date '2000-02-29', date '2028-02-28') then
    raise exception 'A leap-day devotee was greeted early in a year that has a 29th.';
  end if;
  if public.birthday_falls_on(date '2000-02-29', date '2028-03-01') then
    raise exception 'A leap-day devotee was greeted on 1 March of a leap year.';
  end if;

  -- A year that has none: the 28th, which is the rule this repo chose.
  if not public.birthday_falls_on(date '2000-02-29', date '2027-02-28') then
    raise exception 'A leap-day devotee was skipped in a non-leap year.';
  end if;
  if public.birthday_falls_on(date '2000-02-29', date '2027-03-01') then
    raise exception 'A leap-day devotee was greeted on 1 March instead of 28 February.';
  end if;

  -- 1900 was not a leap year, whatever divisible-by-four says.
  if not public.birthday_falls_on(date '2000-02-29', date '1900-02-28') then
    raise exception 'The century rule was got wrong: 1900 had no 29th of February.';
  end if;

  -- And a devotee born on the 28th keeps the 28th in every year, without being
  -- displaced by the leap-day clause or greeted twice.
  if not public.birthday_falls_on(date '1990-02-28', date '2028-02-28') then
    raise exception 'A devotee born on the 28th was not greeted in a leap year.';
  end if;
  if public.birthday_falls_on(date '1990-02-28', date '2028-02-29') then
    raise exception 'A devotee born on the 28th was also greeted on the 29th.';
  end if;
end;
$$;

update public.users
set date_of_birth = date '2000-02-29'
where email = 'bp-leap@example.test';

select set_config('request.jwt.claim.sub', 'bd000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
  v_listed boolean;
  v_expected boolean;
begin
  select exists (
    select 1 from public.todays_birthdays()
    where todays_birthdays.devotee_id = 'bd000000-0000-0000-0000-000000000007'
  ) into v_listed;

  v_expected := public.birthday_falls_on(
    date '2000-02-29',
    (now() at time zone 'America/Chicago')::date
  );

  if v_listed is distinct from v_expected then
    raise exception
      'todays_birthdays disagrees with the leap-day rule: listed %, rule says % (Chicago %).',
      v_listed, v_expected, (now() at time zone 'America/Chicago')::date;
  end if;
end;
$$;

reset role;

update public.users set date_of_birth = null where email = 'bp-leap@example.test';

-- The wiring, and the reason this section can be trusted on the other 364 days
-- of the year.
--
-- The two assertions above are only sharp when the script happens to run on the
-- 28th or 29th of February; on 11 August they agree that nobody is celebrating
-- and prove nothing. So the leap rule is carried in structurally instead: the
-- rule itself is proved against birthday_falls_on at the top of this section on
-- any day, and both functions here are pinned to reaching it through
-- is_birthday_today rather than reimplementing "same month, same day" inline.
-- An implementation that open-codes the comparison — which is exactly how the
-- 29th of February gets lost — fails this whether or not it is February.
--
-- Read from the function's own text because plpgsql bodies record no
-- dependency on what they call, so there is nothing in pg_depend to ask.
do $$
declare
  v_name text;
  v_definition text;
begin
  foreach v_name in array array['todays_birthdays', 'prompt_birthday_wishes']
  loop
    select pg_get_functiondef(pg_proc.oid) into v_definition
    from pg_proc
    join pg_namespace on pg_namespace.oid = pg_proc.pronamespace
    where pg_namespace.nspname = 'public' and pg_proc.proname = v_name;

    if v_definition !~ 'is_birthday_today' then
      raise exception
        '% decides whose birthday it is without going through is_birthday_today, so the 29 February rule and the Chicago rule are not the ones being applied.',
        v_name;
    end if;
  end loop;
end;
$$;

-- And the whole selection, not one devotee: what todays_birthdays lists is
-- exactly who the rule says is celebrating today in Chicago. Catches a filter
-- that quietly gains or loses somebody, on any day of the year.
select set_config('request.jwt.claim.sub', 'bd000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
  v_listed integer;
  v_expected integer;
  v_agree integer;
begin
  select count(*)::integer into v_listed from public.todays_birthdays();

  select count(*)::integer into v_expected
  from public.users
  where public.birthday_falls_on(
    users.date_of_birth, (now() at time zone 'America/Chicago')::date
  );

  select count(*)::integer into v_agree
  from public.todays_birthdays()
  join public.users on users.id = todays_birthdays.devotee_id
  where public.birthday_falls_on(
    users.date_of_birth, (now() at time zone 'America/Chicago')::date
  );

  if v_listed <> v_expected or v_agree <> v_listed then
    raise exception
      'todays_birthdays listed % devotees, the rule says %, and % of the listed ones match it.',
      v_listed, v_expected, v_agree;
  end if;
end;
$$;

reset role;

-- ---------------------------------------------------------------------------
-- 9. The suggested wording.
--
--    Given to the two who may post about a birthday, refused to everybody else.
--    Refused rather than empty, because a caller here is composing something
--    the whole congregation will read.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'bd000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
  v_row record;
begin
  select * into v_row
  from public.suggested_birthday_announcement('bd000000-0000-0000-0000-000000000003');

  if v_row.title is null or v_row.body is null then
    raise exception 'The suggested announcement came back empty.';
  end if;
  if v_row.title !~ 'BP Ananda' then
    raise exception 'The suggested title does not name the devotee: %', v_row.title;
  end if;
  if v_row.body !~ 'BP Ananda' then
    raise exception 'The suggested body does not name the devotee: %', v_row.body;
  end if;
  if v_row.title !~* 'birthday' or v_row.body !~* 'birthday' then
    raise exception 'The suggested wording does not mention a birthday: % / %',
      v_row.title, v_row.body;
  end if;
  if v_row.body !~ '\mthem\M' then
    raise exception 'The suggested wording does not use they/them: %', v_row.body;
  end if;
  if v_row.body ~* '\m(he|she|him|her|hers|his)\M' then
    raise exception 'The suggested wording guesses at gender: %', v_row.body;
  end if;

  -- Long enough to be a notice rather than a placeholder the President has to
  -- write from scratch.
  if length(v_row.body) < 60 then
    raise exception 'The suggested body is too short to post as it stands: %', v_row.body;
  end if;
end;
$$;

reset role;

-- The Tech Admin gets it too.
select set_config('request.jwt.claim.sub', 'bd000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_title text;
begin
  select suggested.title into v_title
  from public.suggested_birthday_announcement('bd000000-0000-0000-0000-000000000003') suggested;
  if v_title is null then
    raise exception 'The Tech Admin was given no suggested wording.';
  end if;
end;
$$;

reset role;

-- And nobody else does. The Community Head is again the one that matters: they
-- may post the announcement, and still may not be handed the birthday.
do $$
declare
  v_person text;
  v_refused boolean;
begin
  foreach v_person in array array[
    'bd000000-0000-0000-0000-000000000003',
    'bd000000-0000-0000-0000-000000000004',
    'bd000000-0000-0000-0000-000000000005',
    'bd000000-0000-0000-0000-000000000006'
  ]
  loop
    perform set_config('request.jwt.claim.sub', v_person, true);
    set local role authenticated;

    v_refused := false;
    begin
      perform public.suggested_birthday_announcement('bd000000-0000-0000-0000-000000000003');
    exception when others then
      v_refused := true;
    end;

    reset role;

    if not v_refused then
      raise exception
        'A devotee without app.view_all (%) was handed the suggested birthday wording.', v_person;
    end if;
  end loop;
end;
$$;

reset role;

-- A devotee who does not exist is an error, not an empty greeting addressed to
-- nobody.
select set_config('request.jwt.claim.sub', 'bd000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
  v_refused boolean := false;
begin
  begin
    perform public.suggested_birthday_announcement('bd000000-0000-0000-0000-0000000000ff');
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A suggested announcement was written about a devotee who does not exist.';
  end if;
end;
$$;

reset role;

-- ---------------------------------------------------------------------------
-- 10. The job is not something a devotee can set off.
-- ---------------------------------------------------------------------------

do $$
declare
  v_person text;
  v_refused boolean;
begin
  foreach v_person in array array[
    'bd000000-0000-0000-0000-000000000001',  -- not even the President
    'bd000000-0000-0000-0000-000000000005',
    'bd000000-0000-0000-0000-000000000006'
  ]
  loop
    perform set_config('request.jwt.claim.sub', v_person, true);
    set local role authenticated;

    v_refused := false;
    begin
      perform public.prompt_birthday_wishes();
    exception when others then
      v_refused := true;
    end;

    reset role;

    if not v_refused then
      raise exception 'A signed-in devotee (%) ran the birthday job by hand.', v_person;
    end if;
  end loop;
end;
$$;

reset role;

-- ---------------------------------------------------------------------------
-- 11. The shapes, and the broadcast that is gone.
--
--    Result columns are pinned in order, because a client reading by position
--    is silently handed the wrong field when one is inserted in the middle.
-- ---------------------------------------------------------------------------

do $$
declare
  v_count integer;
  v_result text;
begin
  -- The old broadcast is not merely unused. It is gone.
  select count(*)::integer into v_count
  from pg_proc
  join pg_namespace on pg_namespace.oid = pg_proc.pronamespace
  where pg_namespace.nspname = 'public'
    and pg_proc.proname = 'announce_birthdays';
  if v_count <> 0 then
    raise exception 'announce_birthdays is still defined; the broadcast can still be run.';
  end if;

  foreach v_result in array array[
    'todays_birthdays', 'prompt_birthday_wishes', 'suggested_birthday_announcement'
  ]
  loop
    select count(*)::integer into v_count
    from pg_proc
    join pg_namespace on pg_namespace.oid = pg_proc.pronamespace
    where pg_namespace.nspname = 'public'
      and pg_proc.proname = v_result;
    if v_count <> 1 then
      raise exception 'There are % versions of %.', v_count, v_result;
    end if;
  end loop;

  select pg_get_function_result(pg_proc.oid) into v_result
  from pg_proc
  join pg_namespace on pg_namespace.oid = pg_proc.pronamespace
  where pg_namespace.nspname = 'public' and pg_proc.proname = 'todays_birthdays';
  if v_result <> 'TABLE(devotee_id uuid, name text, photo_url text, date_of_birth date, turning_age integer)' then
    raise exception 'todays_birthdays returns %', v_result;
  end if;

  select pg_get_function_result(pg_proc.oid) into v_result
  from pg_proc
  join pg_namespace on pg_namespace.oid = pg_proc.pronamespace
  where pg_namespace.nspname = 'public'
    and pg_proc.proname = 'suggested_birthday_announcement';
  if v_result <> 'TABLE(title text, body text)' then
    raise exception 'suggested_birthday_announcement returns %', v_result;
  end if;

  select pg_get_function_result(pg_proc.oid) into v_result
  from pg_proc
  join pg_namespace on pg_namespace.oid = pg_proc.pronamespace
  where pg_namespace.nspname = 'public' and pg_proc.proname = 'prompt_birthday_wishes';
  if v_result <> 'integer' then
    raise exception 'prompt_birthday_wishes returns % rather than a count.', v_result;
  end if;

  -- The kind this migration writes is still allowed. A later migration that
  -- restates the CHECK without it takes the prompt down silently otherwise.
  select count(*)::integer into v_count
  from pg_constraint
  where conname = 'app_notifications_kind_check'
    and conrelid = 'public.app_notifications'::regclass
    and position('''birthday_today''' in pg_get_constraintdef(pg_constraint.oid)) > 0;
  if v_count <> 1 then
    raise exception 'birthday_today is no longer allowed by app_notifications_kind_check.';
  end if;
end;
$$;

do $$
begin
  raise notice 'all birthday prompt checks passed';
end;
$$;

select 'birthday prompts verification passed' as result;

rollback;
