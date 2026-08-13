-- Functional verification for 202608040040_announcements.sql.
--
-- Rolled back at the end. Every local is prefixed v_ so it can never shadow a
-- column name. Anything that must be refused is attempted as the devotee who
-- would really attempt it, under `set local role authenticated`, so the row
-- level security policies and the column grants are actually the thing being
-- tested rather than superuser rights quietly waving everything through.
-- Notification assertions are made after `reset role`, because a devotee
-- cannot — and should not be able to — read somebody else's inbox.
--
-- The five people in this script:
--   President  ...0001  may post, and may take anybody's notice down
--   Head       ...0002  Community Head; posts most of what is checked here
--   Tech       ...0003  Tech Admin; the third of the three who may post
--   Devotee    ...0004  reads everything, may post nothing, deletes nothing
--   Volunteer  ...0005  the nearest role that must still be refused
--
-- The final row must read: announcements verification passed

begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('a0000000-0000-0000-0000-000000000001', 'ann-president@example.test', '{"name":"Ann President"}'),
  ('a0000000-0000-0000-0000-000000000002', 'ann-head@example.test', '{"name":"Ann Head"}'),
  ('a0000000-0000-0000-0000-000000000003', 'ann-tech@example.test', '{"name":"Ann Tech"}'),
  ('a0000000-0000-0000-0000-000000000004', 'ann-devotee@example.test', '{"name":"Ann Devotee"}'),
  ('a0000000-0000-0000-0000-000000000005', 'ann-volunteer@example.test', '{"name":"Ann Volunteer"}');

update public.users
set role_id = (select roles.id from public.roles where roles.name = 'president')
where email = 'ann-president@example.test';

update public.users
set role_id = (select roles.id from public.roles where roles.name = 'core')
where email = 'ann-head@example.test';

update public.users
set role_id = (select roles.id from public.roles where roles.name = 'tech')
where email = 'ann-tech@example.test';

update public.users
set role_id = (select roles.id from public.roles where roles.name = 'volunteer')
where email = 'ann-volunteer@example.test';

-- Ordinary table rather than a temporary one, so reading it under the
-- authenticated role needs no assumptions about the temp schema. The whole
-- script is rolled back, so it never outlives the transaction.
create table public.announcement_test_ids (key text primary key, id uuid not null);
grant select, insert on public.announcement_test_ids to authenticated;

-- ---------------------------------------------------------------------------
-- 0. The permission being relied on is the one the temple already uses for
--    "Community Head, Tech Admin, President", and no fourth role has it.
--
--    If a later migration widens services.manage_recurring, announcements
--    widen with it silently. That is worth failing loudly over here rather
--    than discovering when a volunteer posts to the whole congregation.
-- ---------------------------------------------------------------------------

do $$
declare
  v_holders text;
begin
  select string_agg(roles.name, ',' order by roles.name) into v_holders
  from public.role_permissions
  join public.roles on roles.id = role_permissions.role_id
  where role_permissions.permission_key = 'services.manage_recurring';

  if v_holders is distinct from 'core,president,tech' then
    raise exception
      'services.manage_recurring is held by % — announcements assume core, president, tech.',
      v_holders;
  end if;

  -- No new permission key was invented for this feature.
  if exists (
    select 1 from public.role_permissions
    where role_permissions.permission_key like '%announcement%'
  ) then
    raise exception 'A separate announcement permission key was registered.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 1. A plain devotee cannot post. Neither can a volunteer.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000004', true);
set local role authenticated;

do $$
declare
  v_refused boolean := false;
begin
  begin
    perform public.create_announcement('Free prasadam', 'Come and get it.');
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A plain devotee posted an announcement.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000005', true);
set local role authenticated;

do $$
declare
  v_refused boolean := false;
begin
  begin
    perform public.create_announcement('Free prasadam', 'Come and get it.');
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A volunteer posted an announcement.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. A Community Head can post, and the fields survive the round trip.
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_posted public.announcements;
  v_chicago_today date := (now() at time zone 'America/Chicago')::date;
begin
  v_posted := public.create_announcement(
    'Janmashtami',
    'Midnight arati begins at 11pm in the main hall. Feast follows.',
    'https://project.supabase.co/storage/v1/object/public/message-images/'
      || 'a0000000-0000-0000-0000-000000000002/janmashtami.jpg',
    v_chicago_today + 5,
    v_chicago_today + 6,
    time '18:00',
    time '01:00'
  );

  if v_posted.id is null then
    raise exception 'A Community Head could not post an announcement.';
  end if;
  if v_posted.posted_by <> 'a0000000-0000-0000-0000-000000000002' then
    raise exception 'The announcement did not record who posted it.';
  end if;
  if v_posted.title <> 'Janmashtami' then
    raise exception 'The title came back as %.', v_posted.title;
  end if;
  if v_posted.image_url is null then
    raise exception 'The photo was dropped.';
  end if;
  if v_posted.starts_on <> v_chicago_today + 5
     or v_posted.ends_on <> v_chicago_today + 6
     or v_posted.starts_at <> time '18:00'
     or v_posted.ends_at <> time '01:00' then
    raise exception 'The schedule did not survive the round trip.';
  end if;

  insert into public.announcement_test_ids values ('janmashtami', v_posted.id);
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. A President can post too, and so can a Tech Admin.
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
  v_posted public.announcements;
begin
  -- No dates at all: the notice that stays until somebody takes it down.
  v_posted := public.create_announcement(
    'Temple hours',
    'The temple is open from 4:30am until 8:30pm every day.'
  );
  if v_posted.id is null then
    raise exception 'The President could not post an announcement.';
  end if;
  if v_posted.ends_on is not null then
    raise exception 'A dateless announcement was given an end.';
  end if;
  insert into public.announcement_test_ids values ('hours', v_posted.id);
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000003', true);
set local role authenticated;

do $$
declare
  v_posted public.announcements;
begin
  v_posted := public.create_announcement(
    'App maintenance',
    'The app will be briefly unavailable on Tuesday morning.'
  );
  if v_posted.id is null then
    raise exception 'A Tech Admin could not post an announcement.';
  end if;
  insert into public.announcement_test_ids values ('maintenance', v_posted.id);
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Blank title, blank body, and an end before a start are all refused,
--    with a message a devotee could act on.
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_message text;
  v_overnight public.announcements;
  v_chicago_today date := (now() at time zone 'America/Chicago')::date;
begin
  -- A message a devotee could act on, not the constraint underneath it. The
  -- table refuses a blank title as well, but landing on that check means the
  -- devotee is shown "violates check constraint", so both halves are asserted:
  -- the refusal, and that the refusal came from the readable guard.
  v_message := null;
  begin
    perform public.create_announcement('   ', 'A body with no title.');
  exception when others then
    v_message := sqlerrm;
  end;
  if v_message is null then
    raise exception 'A blank title was accepted.';
  end if;
  if v_message !~* 'title' or v_message ~* '(constraint|null value|violates)' then
    raise exception 'A blank title was refused unreadably: %', v_message;
  end if;

  v_message := null;
  begin
    perform public.create_announcement('A title with no body', '  ');
  exception when others then
    v_message := sqlerrm;
  end;
  if v_message is null then
    raise exception 'A blank body was accepted.';
  end if;
  if v_message ~* '(constraint|null value|violates)' then
    raise exception 'A blank body was refused unreadably: %', v_message;
  end if;

  v_message := null;
  begin
    perform public.create_announcement(
      'Backwards', 'Ends before it starts.',
      null, v_chicago_today + 10, v_chicago_today + 3
    );
  exception when others then
    v_message := sqlerrm;
  end;
  if v_message is null then
    raise exception 'An announcement ending before it starts was accepted.';
  end if;
  if v_message !~* 'date' or v_message ~* '(constraint|violates)' then
    raise exception 'Backwards dates were refused unreadably: %', v_message;
  end if;

  -- Same day, backwards clock.
  v_message := null;
  begin
    perform public.create_announcement(
      'Backwards clock', 'Ends before it starts.',
      null, v_chicago_today + 3, v_chicago_today + 3, time '19:00', time '17:00'
    );
  exception when others then
    v_message := sqlerrm;
  end;
  if v_message is null then
    raise exception 'An announcement whose times run backwards on one day was accepted.';
  end if;
  if v_message !~* 'time' then
    raise exception 'The backwards-clock message does not mention the times: %', v_message;
  end if;

  -- Two days apart, the same clock times, and now perfectly ordered: an
  -- evening start and a morning end is a real overnight festival, not an error.
  v_overnight := public.create_announcement(
    'Overnight', 'Friday evening through Sunday morning.',
    null, v_chicago_today + 3, v_chicago_today + 5, time '19:00', time '08:00'
  );
  if v_overnight.id is null then
    raise exception 'A legitimate overnight announcement was refused.';
  end if;

  -- A photo from somewhere other than the app is refused.
  v_message := null;
  begin
    perform public.create_announcement(
      'Elsewhere', 'A photo from another host.',
      'https://tracker.example.com/pixel.png'
    );
  exception when others then
    v_message := sqlerrm;
  end;
  if v_message is null then
    raise exception 'A photo hosted outside the app was accepted.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Expiry, decided in Chicago.
--
--    These four go straight into the table rather than through the RPC. Two
--    reasons: an end already in the past is not something a Community Head
--    would ever type, and a notice posted here would queue five more push
--    notifications and muddy the count section 7 depends on.
-- ---------------------------------------------------------------------------

reset role;

do $$
declare
  v_chicago_today date := (now() at time zone 'America/Chicago')::date;
  v_id uuid;
begin
  insert into public.announcements (title, body, posted_by, ends_on)
  values ('Yesterday', 'This finished yesterday.',
          'a0000000-0000-0000-0000-000000000002', v_chicago_today - 1)
  returning id into v_id;
  insert into public.announcement_test_ids values ('yesterday', v_id);

  insert into public.announcements (title, body, posted_by, ends_on)
  values ('Today', 'This runs until the end of today.',
          'a0000000-0000-0000-0000-000000000002', v_chicago_today)
  returning id into v_id;
  insert into public.announcement_test_ids values ('today', v_id);

  -- An end of midnight today is a time that has already passed however early
  -- in the day this script runs, so the clock-level rule is checked without
  -- the result depending on when the run happens.
  insert into public.announcements (title, body, posted_by, ends_on, ends_at)
  values ('Ended this morning', 'The clock, not just the day.',
          'a0000000-0000-0000-0000-000000000002', v_chicago_today, time '00:00')
  returning id into v_id;
  insert into public.announcement_test_ids values ('ended_today', v_id);

  -- A time with no day says nothing about expiry, so this one stands.
  insert into public.announcements (title, body, posted_by, ends_at)
  values ('Time only', 'An end time and no end date.',
          'a0000000-0000-0000-0000-000000000002', time '00:00')
  returning id into v_id;
  insert into public.announcement_test_ids values ('time_only', v_id);
end;
$$;

do $$
declare
  v_chicago_today date := (now() at time zone 'America/Chicago')::date;
  v_utc_today date := (now() at time zone 'UTC')::date;
begin
  -- The whole point of the migration's timezone care. Between roughly 7pm and
  -- midnight in Chicago, v_utc_today is already tomorrow, and an
  -- `ends_on >= current_date` written in UTC retires today's notice hours
  -- early. This assertion is what fails when that mistake is made.
  if not public.announcement_is_live(v_chicago_today, null) then
    raise exception
      'A notice ending today in Chicago is already dead (Chicago %, UTC %).',
      v_chicago_today, v_utc_today;
  end if;
  if public.announcement_is_live(v_chicago_today - 1, null) then
    raise exception 'A notice that ended yesterday in Chicago is still live.';
  end if;
  if not public.announcement_is_live(null, null) then
    raise exception 'A notice with no end date expired anyway.';
  end if;
  if not public.announcement_is_live(null, time '00:00') then
    raise exception 'A notice with an end time but no end date expired anyway.';
  end if;
  if public.announcement_is_live(v_chicago_today, time '00:00') then
    raise exception 'A notice that ended at midnight this morning is still live.';
  end if;
  if not public.announcement_is_live(v_chicago_today + 1, null) then
    raise exception 'A notice ending tomorrow is not live.';
  end if;
end;
$$;

-- The assertion above only bites while Chicago and UTC actually disagree,
-- which is the evening. The likelier mistake — reaching for current_date or
-- now()::date, both of which read the caller's own timezone rather than the
-- temple's — is caught at any hour by asking the same question from four
-- session timezones spanning UTC-12 to UTC+14. At least one of them is always
-- on a different calendar day from Chicago, so an implementation that follows
-- the session must give a different answer to at least one of these.
do $$
declare
  v_chicago_today date := (now() at time zone 'America/Chicago')::date;
  v_zone text;
begin
  foreach v_zone in array
    array['UTC', 'Pacific/Kiritimati', 'Etc/GMT+12', 'Asia/Tokyo', 'America/Chicago']
  loop
    perform set_config('timezone', v_zone, true);
    if not public.announcement_is_live(v_chicago_today, null) then
      raise exception
        'A notice ending today in Chicago died when the caller sat in %.', v_zone;
    end if;
    if public.announcement_is_live(v_chicago_today - 1, null) then
      raise exception
        'A notice that ended yesterday in Chicago revived when the caller sat in %.',
        v_zone;
    end if;
  end loop;
  perform set_config('timezone', 'UTC', true);
end;
$$;

reset role;
reset timezone;

-- ---------------------------------------------------------------------------
-- 6. Every devotee sees the live notices, and only the live ones.
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000004', true);
set local role authenticated;

do $$
declare
  v_titles text;
  v_rows integer;
  v_can_delete boolean;
  v_previous timestamptz;
  v_row record;
begin
  select string_agg(listed.title, ',' order by listed.title) into v_titles
  from public.list_announcements() listed;

  if v_titles is distinct from
     'App maintenance,Janmashtami,Overnight,Temple hours,Time only,Today'
  then
    raise exception 'A plain devotee sees % on the board.', v_titles;
  end if;

  -- Named individually so a failure says which rule broke.
  select count(*)::integer into v_rows from public.list_announcements() listed
  where listed.title = 'Yesterday';
  if v_rows <> 0 then
    raise exception 'A notice that ended yesterday in Chicago is still on the board.';
  end if;

  select count(*)::integer into v_rows from public.list_announcements() listed
  where listed.title = 'Today';
  if v_rows <> 1 then
    raise exception 'A notice ending today in Chicago has already gone.';
  end if;

  select count(*)::integer into v_rows from public.list_announcements() listed
  where listed.title = 'Ended this morning';
  if v_rows <> 0 then
    raise exception 'A notice whose end time passed this morning is still on the board.';
  end if;

  select count(*)::integer into v_rows from public.list_announcements() listed
  where listed.title = 'Temple hours';
  if v_rows <> 1 then
    raise exception 'A notice with no dates at all did not persist.';
  end if;

  -- Who posted it travels with the row, so a card can say so without a lookup.
  select * into v_row from public.list_announcements() listed
  where listed.title = 'Janmashtami';
  if v_row.posted_by_name <> 'Ann Head' then
    raise exception 'The board named the poster as %.', v_row.posted_by_name;
  end if;
  if v_row.posted_by_photo_url is not null then
    raise exception 'A poster with no photo was given one.';
  end if;
  if v_row.image_url is null then
    raise exception 'The announcement photo is missing from the board.';
  end if;

  -- Newest first.
  v_previous := null;
  for v_row in select * from public.list_announcements() loop
    if v_previous is not null and v_row.created_at > v_previous then
      raise exception 'The board is not ordered newest first.';
    end if;
    v_previous := v_row.created_at;
  end loop;

  -- A plain devotee may delete nothing, and the board says so.
  select bool_or(listed.can_delete) into v_can_delete
  from public.list_announcements() listed;
  if v_can_delete then
    raise exception 'A plain devotee was told they could delete an announcement.';
  end if;
end;
$$;

-- The volunteer, who is not a plain devotee but is not one of the three
-- either, sees exactly the same board and the same empty set of buttons.
reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000005', true);
set local role authenticated;

do $$
declare
  v_rows integer;
  v_can_delete boolean;
begin
  select count(*)::integer, coalesce(bool_or(listed.can_delete), false)
    into v_rows, v_can_delete
  from public.list_announcements() listed;
  if v_rows <> 6 then
    raise exception 'A volunteer sees % live announcements rather than 6.', v_rows;
  end if;
  if v_can_delete then
    raise exception 'A volunteer was told they could delete an announcement.';
  end if;
end;
$$;

-- The Community Head sees the same board and may take any of it down.
reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_rows integer;
  v_deletable integer;
begin
  select count(*)::integer into v_rows from public.list_announcements();
  if v_rows <> 6 then
    raise exception 'A Community Head sees % live announcements rather than 6.', v_rows;
  end if;
  select count(*)::integer into v_deletable
  from public.list_announcements() listed where listed.can_delete;
  if v_deletable <> 6 then
    raise exception 'A Community Head may delete only % of the 6 notices.', v_deletable;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Every devotee was told when a notice went up.
--
--    Three notices were posted through the RPC by three different people, plus
--    the overnight one, so each of the five devotees should have heard about
--    every one they did not post themselves.
-- ---------------------------------------------------------------------------

reset role;

do $$
declare
  v_told integer;
  v_expected integer;
  v_posted integer;
  v_body text;
  v_person record;
begin
  -- Four notices went up through the RPC — Janmashtami and Overnight by the
  -- Head, Temple hours by the President, App maintenance by the Tech Admin —
  -- and each reached the other four people.
  select count(*)::integer into v_told
  from public.app_notifications
  where kind = 'announcement_posted';
  if v_told <> 16 then
    raise exception '% announcement notifications were queued rather than 16.', v_told;
  end if;

  -- Not "most devotees": every one of them, individually, for every notice
  -- they did not put up themselves.
  for v_person in
    select users.id, users.name from public.users
    where users.email like 'ann-%@example.test'
  loop
    select count(*)::integer into v_posted
    from public.announcements
    where announcements.posted_by = v_person.id
      and announcements.title in
        ('Janmashtami', 'Overnight', 'Temple hours', 'App maintenance');
    v_expected := 4 - v_posted;

    select count(*)::integer into v_told
    from public.app_notifications
    where app_notifications.user_id = v_person.id
      and app_notifications.kind = 'announcement_posted';
    if v_told <> v_expected then
      raise exception '% was told about % of the % announcements they did not post.',
        v_person.name, v_told, v_expected;
    end if;
  end loop;

  -- The poster is not told about their own notice; they are standing at it.
  select count(*)::integer into v_told
  from public.app_notifications
  where app_notifications.user_id = 'a0000000-0000-0000-0000-000000000002'
    and app_notifications.kind = 'announcement_posted'
    and app_notifications.data ->> 'announcementId' = (
      select ids.id::text from public.announcement_test_ids ids where ids.key = 'janmashtami'
    );
  if v_told <> 0 then
    raise exception 'The poster was pushed their own announcement.';
  end if;

  select app_notifications.title || ' / ' || app_notifications.body into v_body
  from public.app_notifications
  where app_notifications.user_id = 'a0000000-0000-0000-0000-000000000004'
    and app_notifications.kind = 'announcement_posted'
    and app_notifications.data ->> 'announcementId' = (
      select ids.id::text from public.announcement_test_ids ids where ids.key = 'janmashtami'
    );
  if v_body !~* 'New announcement' then
    raise exception 'The notification is not titled as an announcement: %', v_body;
  end if;
  if v_body !~ 'Ann Head' then
    raise exception 'The notification does not name who posted it: %', v_body;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. Taking notices down.
-- ---------------------------------------------------------------------------

-- A plain devotee cannot delete somebody else's notice.
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000004', true);
set local role authenticated;

do $$
declare
  v_refused boolean := false;
  v_target uuid;
begin
  select ids.id into v_target from public.announcement_test_ids ids
  where ids.key = 'janmashtami';
  begin
    perform public.delete_announcement(v_target);
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A plain devotee deleted an announcement.';
  end if;

  -- And the row is genuinely still there, not merely reported as refused.
  if not exists (
    select 1 from public.list_announcements() listed where listed.id = v_target
  ) then
    raise exception 'The announcement a devotee could not delete is gone anyway.';
  end if;
end;
$$;

-- The poster takes their own down.
reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000003', true);
set local role authenticated;

do $$
declare
  v_removed public.announcements;
  v_refused boolean := false;
  v_target uuid;
begin
  select ids.id into v_target from public.announcement_test_ids ids
  where ids.key = 'maintenance';
  v_removed := public.delete_announcement(v_target);
  if v_removed.id <> v_target then
    raise exception 'Deleting an announcement did not return the row removed.';
  end if;
  if exists (
    select 1 from public.list_announcements() listed where listed.id = v_target
  ) then
    raise exception 'A deleted announcement is still on the board.';
  end if;

  -- Twice is a mistake, not a licence.
  begin
    perform public.delete_announcement(v_target);
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'Deleting the same announcement twice was accepted.';
  end if;
end;
$$;

-- A Community Head takes down a notice the President put up.
reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_target uuid;
begin
  select ids.id into v_target from public.announcement_test_ids ids where ids.key = 'hours';
  perform public.delete_announcement(v_target);
  if exists (
    select 1 from public.list_announcements() listed where listed.id = v_target
  ) then
    raise exception 'A Community Head could not remove another devotee''s notice.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 9. The table itself is not a back door.
--
--    Every write goes through an RPC, so a devotee's own rights must carry no
--    insert, update or delete however they phrase the statement.
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000004', true);
set local role authenticated;

do $$
declare
  v_refused boolean;
begin
  v_refused := false;
  begin
    insert into public.announcements (title, body, posted_by)
    values ('Sneaked in', 'Straight into the table.',
            'a0000000-0000-0000-0000-000000000004');
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A devotee wrote straight into the announcements table.';
  end if;

  v_refused := false;
  begin
    delete from public.announcements;
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A devotee deleted straight from the announcements table.';
  end if;

  v_refused := false;
  begin
    update public.announcements set title = 'Rewritten';
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A devotee rewrote the announcements table.';
  end if;

  -- And a direct read of the table still cannot surface an expired notice.
  if exists (select 1 from public.announcements where title = 'Yesterday') then
    raise exception 'An expired notice is readable straight off the table.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 10. Photos reuse the bucket direct messages already use.
-- ---------------------------------------------------------------------------

reset role;

do $$
declare
  v_rows integer;
begin
  if not exists (select 1 from storage.buckets where id = 'message-images') then
    raise exception 'The message-images bucket is missing.';
  end if;
  select count(*)::integer into v_rows from storage.buckets
  where buckets.id ilike '%announcement%';
  if v_rows <> 0 then
    raise exception 'A second bucket was made for announcement pictures.';
  end if;
end;
$$;

do $$
begin
  raise notice 'all announcement checks passed';
end;
$$;

select 'announcements verification passed' as result;

rollback;
