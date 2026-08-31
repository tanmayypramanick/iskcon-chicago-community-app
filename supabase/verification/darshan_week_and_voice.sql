-- Functional verification for 202608290079_darshan_week_and_voice.sql.
--
-- Rolled back at the end. Every local is prefixed v_ so it can never shadow a
-- column name. Anything that must be refused is attempted as the devotee who
-- would really attempt it, under `set local role authenticated`, so the grants
-- and the sign-in checks are the thing being tested rather than superuser
-- rights quietly waving everything through.
--
-- Every date is derived from the Chicago clock and from
-- daily_darshan_week_floor(), never written as a literal, so this suite passes
-- on a Monday, on a Sunday, and in the hour either side of both daylight
-- saving changeovers. The one place literal dates appear is section 1, where
-- fixed instants in 2026 are the only way to say what a DST boundary is.
--
-- The people in this script:
--   President      ...0001
--   Community Head ...0002  named "Wanda Weekhead", a string that appears
--                           nowhere in this app but in her own row, so section
--                           3 can prove no notification carries it
--   Tech Admin     ...0003
--   Devotee        ...0004  the lowest access level, who must still see the
--                           week and must never see the ledger
--
-- What this script exists to prove:
--
--    1. "Monday" is public.seva_mala_week_start of the Chicago date -- the
--       app's one definition of a week -- and it turns over at Chicago
--       midnight on both sides of both 2026 DST changeovers.
--    2. The floor is a dial. keep_weeks widens the gallery; below one it
--       raises rather than quietly holding nothing.
--    3. The voice: all twenty-five wordings, verbatim, for one named Deity,
--       two, three, four, and none; the same post always words itself
--       identically; and the poster's name is in none of them.
--    4. A darshan from last week is gone from every read after the sweep and
--       this week's survives, with its pictures.
--    5. The reads exclude last week BEFORE the sweep runs, so the Home card is
--       never last week's for the hour after Chicago midnight on Monday.
--    6. The sweep is idempotent: run twice, run three times, it changes
--       nothing after the first.
--    7. Every file the sweep orphaned is written down exactly once, with the
--       right object path; a file another feature still shows is settled as
--       still in use and never handed to a reaper; and with no reaper
--       configured nothing is lost and nothing raises.
--    8. Publishing is confined to the week the gallery holds, and the backdate
--       guard and the week guard are two guards and not one.
--    9. Nothing added here is a back door: the sweep, the reaper and the
--       wording are closed to every client role.
--   10. Fifteen mutations, each breaking exactly one guard.
--
-- The final row must read: darshan week and voice verification passed

begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('f0000000-0000-0000-0000-000000000001', 'dw-president@example.test', '{"name":"Dee Wu President"}'),
  ('f0000000-0000-0000-0000-000000000002', 'dw-head@example.test', '{"name":"Wanda Weekhead"}'),
  ('f0000000-0000-0000-0000-000000000003', 'dw-tech@example.test', '{"name":"Dee Wu Tech"}'),
  ('f0000000-0000-0000-0000-000000000004', 'dw-devotee@example.test', '{"name":"Dee Wu Devotee"}');

update public.users
set role_id = (select roles.id from public.roles where roles.name = 'president')
where email = 'dw-president@example.test';
update public.users
set role_id = (select roles.id from public.roles where roles.name = 'core')
where email = 'dw-head@example.test';
update public.users
set role_id = (select roles.id from public.roles where roles.name = 'tech')
where email = 'dw-tech@example.test';
update public.users
set role_id = (select roles.id from public.roles where roles.name = 'devotee')
where email = 'dw-devotee@example.test';

-- The account-creation trigger has already written devotee_joined rows.
-- Nothing below counts those, and clearing the table keeps every count in this
-- script about the darshan alone.
delete from public.app_notifications;

-- Ordinary tables rather than temporary ones, so reading them under the
-- authenticated role needs no assumptions about the temp schema. The whole
-- script is rolled back, so they never outlive the transaction.
create table public.dw_ids (key text primary key, id uuid not null);
create table public.dw_urls (key text primary key, url text not null);
grant select, insert on public.dw_ids to authenticated;
grant select, insert on public.dw_urls to authenticated;

-- ---------------------------------------------------------------------------
-- 1. What Monday is, and that it is Chicago's Monday.
--
--    The floor must BE seva_mala_week_start of the Chicago date and not merely
--    agree with it today, because the point of reusing that function is that
--    there is one week in this database. So it is asserted as an identity, and
--    then the identity is exercised across both 2026 changeovers.
--
--    The two changeovers are the whole argument. Chicago's week turns at
--    05:00 UTC in the summer and at 06:00 UTC in the winter, and both of those
--    are midnight on Monday in Chicago. A floor computed in UTC would turn at
--    the same UTC instant in both halves of the year and would therefore be an
--    hour wrong for half of them.
-- ---------------------------------------------------------------------------

do $$
declare
  v_floor date := public.daily_darshan_week_floor();
  v_today date := (now() at time zone 'America/Chicago')::date;
  v_probe date;
  v_n integer;
begin
  if v_floor <> public.seva_mala_week_start(v_today) then
    raise exception
      'The Daily Darshan floor is % but the app''s week starts on %.',
      v_floor, public.seva_mala_week_start(v_today);
  end if;

  if extract(isodow from v_floor) <> 1 then
    raise exception 'The floor % is a %, not a Monday.',
      v_floor, to_char(v_floor, 'FMDay');
  end if;

  if v_floor > v_today or v_today - v_floor > 6 then
    raise exception 'The floor % is not within the week containing %.', v_floor, v_today;
  end if;

  -- Fourteen days around the spring changeover, and fourteen around the
  -- autumn one. Every date must land on the Monday of its own week, including
  -- the 23-hour Sunday and the 25-hour one.
  for v_n in 0..13 loop
    v_probe := date '2026-03-02' + v_n;
    if public.seva_mala_week_start(v_probe)
       <> v_probe - (extract(isodow from v_probe)::integer - 1) then
      raise exception 'The week of % was read as %.',
        v_probe, public.seva_mala_week_start(v_probe);
    end if;
    v_probe := date '2026-10-26' + v_n;
    if public.seva_mala_week_start(v_probe)
       <> v_probe - (extract(isodow from v_probe)::integer - 1) then
      raise exception 'The week of % was read as %.',
        v_probe, public.seva_mala_week_start(v_probe);
    end if;
  end loop;

  -- Spring: the week turns at 05:00 UTC, which is midnight CDT.
  if (timestamptz '2026-03-09 04:59:00+00' at time zone 'America/Chicago')::date
     <> date '2026-03-08'
   or (timestamptz '2026-03-09 05:00:00+00' at time zone 'America/Chicago')::date
     <> date '2026-03-09' then
    raise exception 'The Chicago day does not turn at 05:00 UTC in March 2026.';
  end if;
  if public.seva_mala_week_start(
       (timestamptz '2026-03-09 04:59:00+00' at time zone 'America/Chicago')::date)
     <> date '2026-03-02'
   or public.seva_mala_week_start(
       (timestamptz '2026-03-09 05:00:00+00' at time zone 'America/Chicago')::date)
     <> date '2026-03-09' then
    raise exception 'The Daily Darshan week did not turn over at Chicago midnight in March.';
  end if;

  -- Autumn: the same wall-clock moment, an hour later in UTC.
  if (timestamptz '2026-11-02 05:59:00+00' at time zone 'America/Chicago')::date
     <> date '2026-11-01'
   or (timestamptz '2026-11-02 06:00:00+00' at time zone 'America/Chicago')::date
     <> date '2026-11-02' then
    raise exception 'The Chicago day does not turn at 06:00 UTC in November 2026.';
  end if;
  if public.seva_mala_week_start(
       (timestamptz '2026-11-02 05:59:00+00' at time zone 'America/Chicago')::date)
     <> date '2026-10-26'
   or public.seva_mala_week_start(
       (timestamptz '2026-11-02 06:00:00+00' at time zone 'America/Chicago')::date)
     <> date '2026-11-02' then
    raise exception 'The Daily Darshan week did not turn over at Chicago midnight in November.';
  end if;

  -- And the two UTC instants really are an hour apart, which is the whole
  -- reason the sweep runs hourly and is not pinned to one UTC hour.
  if timestamptz '2026-11-02 06:00:00+00' - timestamptz '2026-03-09 05:00:00+00'
     <> (date '2026-11-02' - date '2026-03-09') * interval '1 day' + interval '1 hour' then
    raise exception 'The two changeover turns are not an hour apart in UTC.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. The floor is a dial, and a dial that refuses nonsense.
-- ---------------------------------------------------------------------------

do $$
declare
  v_floor date := public.daily_darshan_week_floor();
  v_moved date;
  v_message text;
begin
  update public.app_settings set value = '3' where app_settings.key = 'daily_darshan.keep_weeks';
  v_moved := public.daily_darshan_week_floor();
  if v_moved <> v_floor - 14 then
    raise exception 'Three weeks of gallery start at % rather than %.', v_moved, v_floor - 14;
  end if;

  update public.app_settings set value = '0' where app_settings.key = 'daily_darshan.keep_weeks';
  begin
    perform public.daily_darshan_week_floor();
  exception when others then v_message := sqlerrm;
  end;
  if v_message is null or v_message !~ 'at least the current week' then
    raise exception 'keep_weeks of zero was accepted (%).', coalesce(v_message, 'no error');
  end if;

  update public.app_settings set value = '1' where app_settings.key = 'daily_darshan.keep_weeks';
  if public.daily_darshan_week_floor() <> v_floor then
    raise exception 'The floor did not come back to % when keep_weeks did.', v_floor;
  end if;

  -- Every dial this file introduced is really in app_settings, so a President
  -- can move it without a migration.
  if (select count(*) from public.app_settings
      where app_settings.key in (
        'daily_darshan.keep_weeks', 'daily_darshan.max_named_deities',
        'daily_darshan.max_title_chars', 'daily_darshan.max_body_chars',
        'daily_darshan.reap_batch', 'daily_darshan.reap_retry_minutes')) <> 6 then
    raise exception 'One of the Daily Darshan week dials is missing from app_settings.';
  end if;

  -- And the endpoint deliberately is not, because absent means off.
  if exists (select 1 from public.app_settings
             where app_settings.key in ('daily_darshan.reaper_url',
                                        'daily_darshan.reaper_secret')) then
    raise exception 'A reaper endpoint was seeded by the migration; absent must mean off.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. The voice.
--
--    Twenty-five wordings, written out here rather than recomputed, because a
--    test that rebuilds the sentence from the same rule as the function proves
--    only that the rule equals itself. These are the strings a devotee's lock
--    screen will show.
--
--    The days are staged directly into the tables at dates a hundred days
--    behind the current week, so this section says nothing about the clock and
--    cannot collide with the fixture below. Their pictures carry URLs that are
--    not storage URLs, so removing them at the end of the section queues
--    nothing on the ledger section 7 counts.
-- ---------------------------------------------------------------------------

create table public.dw_wording (
  names integer not null,
  shape integer not null,
  expect_title text not null,
  expect_body text not null,
  primary key (names, shape)
);

insert into public.dw_wording (names, shape, expect_title, expect_body) values
  (1, 0, 'Kisora Kisori', 'See how Kisora Kisori is looking today.'),
  (1, 1, 'Kisora Kisori', 'Today''s darshan of Kisora Kisori is here.'),
  (1, 2, 'Kisora Kisori', 'Come and take darshan of Kisora Kisori.'),
  (1, 3, 'Kisora Kisori', 'Today''s pictures of Kisora Kisori are here.'),
  (1, 4, 'Kisora Kisori', 'Kisora Kisori - today''s darshan from the temple.'),

  (2, 0, 'Kisora Kisori and Gaura Nitai',
         'See how Kisora Kisori and Gaura Nitai are looking today.'),
  (2, 1, 'Kisora Kisori and Gaura Nitai',
         'Today''s darshan of Kisora Kisori and Gaura Nitai is here.'),
  (2, 2, 'Kisora Kisori and Gaura Nitai',
         'Come and take darshan of Kisora Kisori and Gaura Nitai.'),
  (2, 3, 'Kisora Kisori and Gaura Nitai',
         'Today''s pictures of Kisora Kisori and Gaura Nitai are here.'),
  (2, 4, 'Kisora Kisori and Gaura Nitai',
         'Kisora Kisori and Gaura Nitai - today''s darshan from the temple.'),

  (3, 0, 'Kisora Kisori, Gaura Nitai and Radha Govinda',
         'See how Kisora Kisori, Gaura Nitai and Radha Govinda are looking today.'),
  (3, 1, 'Kisora Kisori, Gaura Nitai and Radha Govinda',
         'Today''s darshan of Kisora Kisori, Gaura Nitai and Radha Govinda is here.'),
  (3, 2, 'Kisora Kisori, Gaura Nitai and Radha Govinda',
         'Come and take darshan of Kisora Kisori, Gaura Nitai and Radha Govinda.'),
  (3, 3, 'Kisora Kisori, Gaura Nitai and Radha Govinda',
         'Today''s pictures of Kisora Kisori, Gaura Nitai and Radha Govinda are here.'),
  (3, 4, 'Kisora Kisori, Gaura Nitai and Radha Govinda',
         'Kisora Kisori, Gaura Nitai and Radha Govinda - today''s darshan from the temple.'),

  (4, 0, 'Kisora Kisori, Gaura Nitai and the other Deities',
         'See how Kisora Kisori, Gaura Nitai and the other Deities are looking today.'),
  (4, 1, 'Kisora Kisori, Gaura Nitai and the other Deities',
         'Today''s darshan of Kisora Kisori, Gaura Nitai and the other Deities is here.'),
  (4, 2, 'Kisora Kisori, Gaura Nitai and the other Deities',
         'Come and take darshan of Kisora Kisori, Gaura Nitai and the other Deities.'),
  (4, 3, 'Kisora Kisori, Gaura Nitai and the other Deities',
         'Today''s pictures of Kisora Kisori, Gaura Nitai and the other Deities are here.'),
  (4, 4, 'Kisora Kisori, Gaura Nitai and the other Deities',
         'Kisora Kisori, Gaura Nitai and the other Deities - today''s darshan from the temple.'),

  (0, 0, 'Daily Darshan', 'See how the Deities are looking today.'),
  (0, 1, 'Daily Darshan', 'Today''s darshan of the Deities is here.'),
  (0, 2, 'Daily Darshan', 'Come and take darshan of the Deities.'),
  (0, 3, 'Daily Darshan', 'Today''s pictures of the Deities are here.'),
  (0, 4, 'Daily Darshan', 'The Deities - today''s darshan from the temple.');

create function pg_temp.dw_stage(p_on date, p_names integer)
returns void
language plpgsql
as $$
declare
  v_id uuid;
  v_all text[] := array['Kisora Kisori', 'Gaura Nitai', 'Radha Govinda', 'Jagannath'];
  v_n integer;
begin
  delete from public.daily_darshan where daily_darshan.darshan_on = p_on;
  insert into public.daily_darshan (darshan_on, posted_by)
  values (p_on, 'f0000000-0000-0000-0000-000000000002')
  returning daily_darshan.id into v_id;

  if p_names = 0 then
    insert into public.daily_darshan_images (darshan_id, image_url, "position")
    values (v_id, 'local://wording/plain.jpg', 1);
  else
    for v_n in 1..p_names loop
      insert into public.daily_darshan_images (darshan_id, image_url, deity, dressed_by, "position")
      values (v_id, 'local://wording/' || v_n || '.jpg', v_all[v_n], 'Wanda Weekhead', v_n);
    end loop;
  end if;
end;
$$;

do $$
declare
  v_base date := public.daily_darshan_week_floor() - 105;
  v_names integer;
  v_offset integer;
  v_on date;
  v_shape integer;
  v_expected record;
  v_title text;
  v_body text;
  v_checked integer := 0;
  v_bodies text[];
begin
  -- Five consecutive days cover all five shapes, whatever day v_base is.
  foreach v_names in array array[0, 1, 2, 3, 4] loop
    v_bodies := '{}'::text[];
    for v_offset in 0..4 loop
      v_on := v_base + v_offset;
      v_shape := ((v_on - date '1970-01-01') % 5 + 5) % 5;

      perform pg_temp.dw_stage(v_on, v_names);

      select notice.title, notice.body into v_title, v_body
      from public.daily_darshan_notification_text(v_on) as notice;

      select * into v_expected from public.dw_wording
      where dw_wording.names = v_names and dw_wording.shape = v_shape;

      if v_title is distinct from v_expected.expect_title then
        raise exception 'With % name(s), shape % titled the notification %, not %.',
          v_names, v_shape, coalesce(v_title, '(null)'), v_expected.expect_title;
      end if;
      if v_body is distinct from v_expected.expect_body then
        raise exception 'With % name(s), shape % worded the notification %, not %.',
          v_names, v_shape, coalesce(v_body, '(null)'), v_expected.expect_body;
      end if;

      -- Nothing about the poster, and nothing about who dressed Them: the
      -- Deities are the subject.
      if v_title || ' ' || v_body ~ 'Weekhead' then
        raise exception 'The notification named a devotee: % / %', v_title, v_body;
      end if;

      -- Said twice, the same. Not a draw.
      select notice.body into v_body
      from public.daily_darshan_notification_text(v_on) as notice;
      if v_body is distinct from v_expected.expect_body then
        raise exception 'The same day worded itself twice differently.';
      end if;

      v_bodies := v_bodies || v_body;
      v_checked := v_checked + 1;
    end loop;

    -- Five days, five different sentences. The variation is real.
    if (select count(distinct sentence) from unnest(v_bodies) as sentence) <> 5 then
      raise exception 'With % name(s), five consecutive days produced % distinct sentences.',
        v_names, (select count(distinct sentence) from unnest(v_bodies) as sentence);
    end if;
  end loop;

  if v_checked <> 25 then
    raise exception 'Only % of the 25 wordings were checked.', v_checked;
  end if;
end;
$$;

-- The shape is a property of the day and of nothing else: the same date five
-- weeks apart, the same words; the pictures replaced, the same words; a
-- different note, the same words.
do $$
declare
  v_base date := public.daily_darshan_week_floor() - 105;
  v_first text;
  v_again text;
begin
  perform pg_temp.dw_stage(v_base, 2);
  select notice.body into v_first
  from public.daily_darshan_notification_text(v_base) as notice;

  perform pg_temp.dw_stage(v_base + 5, 2);
  select notice.body into v_again
  from public.daily_darshan_notification_text(v_base + 5) as notice;
  if v_again is distinct from v_first then
    raise exception 'Five days apart the shape moved: % then %.', v_first, v_again;
  end if;

  -- The gallery is rebuilt with different files and the same Deities.
  perform pg_temp.dw_stage(v_base, 2);
  update public.daily_darshan set note = 'A new note entirely.'
  where daily_darshan.darshan_on = v_base;
  select notice.body into v_again
  from public.daily_darshan_notification_text(v_base) as notice;
  if v_again is distinct from v_first then
    raise exception 'Re-publishing the day reworded it: % then %.', v_first, v_again;
  end if;
end;
$$;

-- The same Deity photographed five times is one Deity, and the spelling that
-- comes back is the one the Head typed first.
do $$
declare
  v_base date := public.daily_darshan_week_floor() - 105;
  v_id uuid;
  v_body text;
  v_n integer;
begin
  delete from public.daily_darshan where daily_darshan.darshan_on = v_base;
  insert into public.daily_darshan (darshan_on, posted_by)
  values (v_base, 'f0000000-0000-0000-0000-000000000002')
  returning daily_darshan.id into v_id;
  for v_n in 1..5 loop
    insert into public.daily_darshan_images (darshan_id, image_url, deity, "position")
    values (v_id, 'local://wording/dup' || v_n || '.jpg',
            case when v_n = 1 then 'Kisora Kisori' else 'KISORA KISORI' end, v_n);
  end loop;

  select notice.body into v_body
  from public.daily_darshan_notification_text(v_base) as notice;
  if v_body !~ 'Kisora Kisori' or v_body ~ 'KISORA' or v_body ~ ',' then
    raise exception 'Five photographs of one Deity produced: %', v_body;
  end if;
end;
$$;

-- A very long Deity name is cut to fit a lock screen rather than overflowing
-- it, and the dial is what decides where.
do $$
declare
  v_base date := public.daily_darshan_week_floor() - 105;
  v_id uuid;
  v_title text;
  v_body text;
  v_max integer := public.daily_darshan_limit('daily_darshan.max_title_chars');
begin
  delete from public.daily_darshan where daily_darshan.darshan_on = v_base;
  insert into public.daily_darshan (darshan_on, posted_by)
  values (v_base, 'f0000000-0000-0000-0000-000000000002')
  returning daily_darshan.id into v_id;
  insert into public.daily_darshan_images (darshan_id, image_url, deity, "position")
  values (v_id, 'local://wording/long.jpg', repeat('Sri ', 30), 1);

  select notice.title, notice.body into v_title, v_body
  from public.daily_darshan_notification_text(v_base) as notice;

  if length(v_title) <> v_max or right(v_title, 3) <> '...' then
    raise exception 'A 120 character Deity name produced a % character title.', length(v_title);
  end if;
  if length(v_body) > public.daily_darshan_limit('daily_darshan.max_body_chars') then
    raise exception 'The body ran to % characters.', length(v_body);
  end if;
end;
$$;

-- The staged days go, and take nothing with them: none of their pictures was a
-- storage object, so none of them reaches the ledger.
delete from public.daily_darshan
where daily_darshan.darshan_on <= public.daily_darshan_week_floor() - 100;

do $$
begin
  if (select count(*) from public.daily_darshan_reaped_images) <> 0 then
    raise exception 'A picture that was never in the bucket was queued for deletion.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. The fixture: two days from before this week, and this week's.
--
--    The old days are written straight into the tables, because they are days
--    that were published when they were still this week and publish now
--    refuses -- which is section 8's subject. This week's darshan goes up
--    through the RPC as the Head, so section 5 onwards is reading something a
--    real Head really posted.
--
--    One picture of last week's is also the picture of an announcement, which
--    is the case 0078 was worried about and section 7 answers.
-- ---------------------------------------------------------------------------

do $$
declare
  v_floor date := public.daily_darshan_week_floor();
  v_base text := 'https://project.supabase.co/storage/v1/object/public/message-images/'
    || 'f0000000-0000-0000-0000-000000000002/';
  v_id uuid;
begin
  insert into public.dw_urls (key, url) values
    ('last_a', v_base || 'last-a.jpg'),
    ('last_shared', v_base || 'last-shared.jpg'),
    ('older_a', v_base || 'older-a.jpg'),
    ('this_a', v_base || 'this-a.jpg'),
    ('this_b', v_base || 'this-b.jpg'),
    ('monday_a', v_base || 'monday-a.jpg');

  -- Last week: the Friday before this Monday.
  insert into public.daily_darshan (darshan_on, note, posted_by)
  values (v_floor - 3, 'Last week''s darshan.', 'f0000000-0000-0000-0000-000000000002')
  returning daily_darshan.id into v_id;
  insert into public.dw_ids values ('last_week', v_id);
  insert into public.daily_darshan_images (darshan_id, image_url, deity, dressed_by, "position")
  values
    (v_id, v_base || 'last-a.jpg', 'Sri Sri Radha Govinda', 'Mataji Radhika', 1),
    (v_id, v_base || 'last-shared.jpg', 'Sri Sri Gaura Nitai', 'Wanda Weekhead', 2);

  -- The week before that.
  insert into public.daily_darshan (darshan_on, note, posted_by)
  values (v_floor - 10, 'The week before.', 'f0000000-0000-0000-0000-000000000002')
  returning daily_darshan.id into v_id;
  insert into public.dw_ids values ('older', v_id);
  insert into public.daily_darshan_images (darshan_id, image_url, deity, "position")
  values (v_id, v_base || 'older-a.jpg', 'Sri Jagannath', 1);

  -- The announcement that also shows last week's second picture.
  insert into public.announcements (title, body, image_url, posted_by)
  values ('Sunday feast', 'Everybody is welcome.', v_base || 'last-shared.jpg',
          'f0000000-0000-0000-0000-000000000002');
end;
$$;

-- This week's Monday, when that is not today. Written directly, because a
-- second RPC call would need a second notification counted below.
do $$
declare
  v_floor date := public.daily_darshan_week_floor();
  v_today date := (now() at time zone 'America/Chicago')::date;
  v_base text := 'https://project.supabase.co/storage/v1/object/public/message-images/'
    || 'f0000000-0000-0000-0000-000000000002/';
  v_id uuid;
begin
  if v_floor < v_today then
    insert into public.daily_darshan (darshan_on, note, posted_by)
    values (v_floor, 'This Monday.', 'f0000000-0000-0000-0000-000000000002')
    returning daily_darshan.id into v_id;
    insert into public.dw_ids values ('monday', v_id);
    insert into public.daily_darshan_images (darshan_id, image_url, deity, "position")
    values (v_id, v_base || 'monday-a.jpg', 'Sri Sri Radha Govinda', 1);
  end if;
end;
$$;

select set_config('request.jwt.claim.sub', 'f0000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_today date := (now() at time zone 'America/Chicago')::date;
  v_base text := 'https://project.supabase.co/storage/v1/object/public/message-images/'
    || 'f0000000-0000-0000-0000-000000000002/';
  v_id uuid;
begin
  v_id := public.publish_daily_darshan(
    v_today,
    'Sri Sri Kisora Kisori this morning.',
    jsonb_build_array(
      jsonb_build_object('imageUrl', v_base || 'this-a.jpg',
        'deity', 'Kisora Kisori', 'dressedBy', 'Wanda Weekhead', 'position', 1),
      jsonb_build_object('imageUrl', v_base || 'this-b.jpg',
        'deity', 'Kisora Kisori', 'dressedBy', 'Wanda Weekhead', 'position', 2)
    )
  );
  if v_id is null then
    raise exception 'The Head could not post this week''s darshan.';
  end if;
  insert into public.dw_ids values ('today', v_id);
end;
$$;

reset role;

-- ---------------------------------------------------------------------------
-- 5. The reads exclude last week BEFORE anything has been swept.
--
--    This is the hour after Chicago midnight on Monday, and it is the moment
--    the temple cared about most. The rows are still in the table; no read
--    returns them.
-- ---------------------------------------------------------------------------

do $$
begin
  if (select count(*) from public.daily_darshan) <> 3
       + (case when public.daily_darshan_week_floor()
                    < (now() at time zone 'America/Chicago')::date then 1 else 0 end) then
    raise exception 'The fixture is not the four (or three) darshans this suite expects.';
  end if;
end;
$$;

select set_config('request.jwt.claim.sub', 'f0000000-0000-0000-0000-000000000004', true);
set local role authenticated;

do $$
declare
  v_floor date := public.daily_darshan_week_floor();
  v_today date := (now() at time zone 'America/Chicago')::date;
  v_expected integer := 1 + (case when v_floor < v_today then 1 else 0 end);
  v_rows integer;
  v_row record;
  v_latest record;
begin
  select count(*)::integer into v_rows from public.list_daily_darshan();
  if v_rows <> v_expected then
    raise exception 'A devotee sees % darshans this week rather than %.', v_rows, v_expected;
  end if;

  for v_row in select * from public.list_daily_darshan() loop
    if v_row.darshan_on < v_floor then
      raise exception 'The list returned %, which is before this Monday (%).',
        v_row.darshan_on, v_floor;
    end if;
  end loop;

  -- The Home card is today's, never last week's.
  select * into v_latest from public.latest_daily_darshan();
  if v_latest.darshan_on <> v_today then
    raise exception 'The Home card shows % rather than today (%).',
      v_latest.darshan_on, v_today;
  end if;
  if jsonb_array_length(v_latest.images) <> 2 or v_latest.image_count <> 2 then
    raise exception 'The Home card lost the pictures: % of %.',
      jsonb_array_length(v_latest.images), v_latest.image_count;
  end if;

  -- The shape the client is built against has not moved.
  if (v_latest.images -> 0) ?& array['id', 'imageUrl', 'deity', 'dressedBy', 'position'] is not true then
    raise exception 'A picture came back as %.', v_latest.images -> 0;
  end if;
  if v_latest.posted_by_name <> 'Wanda Weekhead' then
    raise exception 'The row no longer carries the poster''s name for the card.';
  end if;

  -- Asking for a hundred does not reach back into last week either.
  select count(*)::integer into v_rows from public.list_daily_darshan(100);
  if v_rows <> v_expected then
    raise exception 'Asking for a hundred returned % darshans.', v_rows;
  end if;
end;
$$;

reset role;

-- ---------------------------------------------------------------------------
-- 6. The sweep.
-- ---------------------------------------------------------------------------

do $$
declare
  v_floor date := public.daily_darshan_week_floor();
  v_today date := (now() at time zone 'America/Chicago')::date;
  v_kept integer := 1 + (case when v_floor < v_today then 1 else 0 end);
  v_removed integer;
  v_before jsonb;
  v_after jsonb;
begin
  select jsonb_agg(darshan.darshan_on order by darshan.darshan_on) into v_before
  from public.daily_darshan darshan where darshan.darshan_on >= v_floor;

  v_removed := public.sweep_daily_darshan();
  if v_removed <> 2 then
    raise exception 'The sweep removed % darshans rather than the 2 from before this week.',
      v_removed;
  end if;

  if exists (select 1 from public.daily_darshan
             where daily_darshan.darshan_on < v_floor) then
    raise exception 'A darshan from before this Monday survived the sweep.';
  end if;

  -- Gone from the images table too, by cascade, with nothing orphaned.
  if exists (
    select 1 from public.daily_darshan_images img
    where not exists (select 1 from public.daily_darshan darshan
                      where darshan.id = img.darshan_id)
  ) then
    raise exception 'An image row was left pointing at a darshan that is gone.';
  end if;
  if (select count(*) from public.daily_darshan_images) <> 2 + (v_kept - 1) then
    raise exception 'The surviving galleries hold % pictures rather than %.',
      (select count(*) from public.daily_darshan_images), 2 + (v_kept - 1);
  end if;

  -- This week's is untouched, to the day.
  select jsonb_agg(darshan.darshan_on order by darshan.darshan_on) into v_after
  from public.daily_darshan darshan;
  if v_after is distinct from v_before then
    raise exception 'This week changed from % to % across the sweep.', v_before, v_after;
  end if;

  -- Twice, and a third time. Nothing more happens.
  if public.sweep_daily_darshan() <> 0 then
    raise exception 'The second sweep removed something.';
  end if;
  if public.sweep_daily_darshan() <> 0 then
    raise exception 'The third sweep removed something.';
  end if;

  select jsonb_agg(darshan.darshan_on order by darshan.darshan_on) into v_after
  from public.daily_darshan darshan;
  if v_after is distinct from v_before then
    raise exception 'Running the sweep three times was not the same as running it once.';
  end if;
end;
$$;

-- And every read agrees, from the devotee's side.
select set_config('request.jwt.claim.sub', 'f0000000-0000-0000-0000-000000000004', true);
set local role authenticated;

do $$
declare
  v_floor date := public.daily_darshan_week_floor();
  v_today date := (now() at time zone 'America/Chicago')::date;
  v_expected integer := 1 + (case when v_floor < v_today then 1 else 0 end);
  v_rows integer;
  v_latest record;
begin
  select count(*)::integer into v_rows from public.list_daily_darshan(100);
  if v_rows <> v_expected then
    raise exception 'After the sweep a devotee sees % darshans rather than %.',
      v_rows, v_expected;
  end if;

  select * into v_latest from public.latest_daily_darshan();
  if v_latest.darshan_on <> v_today or v_latest.image_count <> 2 then
    raise exception 'The Home card after the sweep is % with % pictures.',
      v_latest.darshan_on, v_latest.image_count;
  end if;
end;
$$;

reset role;

-- ---------------------------------------------------------------------------
-- 7. The files.
--
--    Three pictures stopped being referenced by a darshan: last week's two and
--    the week before's one. One of those three is also an announcement's
--    picture and must never be handed to anybody.
-- ---------------------------------------------------------------------------

do $$
declare
  v_shared text := (select url from public.dw_urls where key = 'last_shared');
  v_dead text := (select url from public.dw_urls where key = 'last_a');
  v_alive text := (select url from public.dw_urls where key = 'this_a');
  v_queued integer;
  v_path text;
begin
  select count(*)::integer into v_queued from public.daily_darshan_reaped_images;
  if v_queued <> 3 then
    raise exception 'The sweep wrote down % dead files rather than 3.', v_queued;
  end if;

  -- The path, not the URL, is what a storage client needs.
  select object_path into v_path from public.daily_darshan_reaped_images
  where daily_darshan_reaped_images.image_url = v_dead;
  if v_path <> 'f0000000-0000-0000-0000-000000000002/last-a.jpg' then
    raise exception 'The object path was read as %.', v_path;
  end if;
  if (select count(*) from public.daily_darshan_reaped_images
      where daily_darshan_reaped_images.bucket_id <> 'message-images') <> 0 then
    raise exception 'A dead file was recorded in a bucket that is not message-images.';
  end if;

  -- A picture this week's darshan still shows is not on the ledger at all.
  if exists (select 1 from public.daily_darshan_reaped_images
             where daily_darshan_reaped_images.image_url = v_alive) then
    raise exception 'A picture still on the screen was queued for deletion.';
  end if;

  -- A URL that is not one of ours yields no path, so it can never be queued.
  if public.daily_darshan_object_path('https://example.test/somebody-elses.jpg') is not null
    or public.daily_darshan_object_path(null) is not null
    or public.daily_darshan_object_path('') is not null then
    raise exception 'A foreign URL was read as one of our objects.';
  end if;
  -- A cache-busting query string is part of the link, not of the object.
  if public.daily_darshan_object_path(v_dead || '?t=123')
     <> 'f0000000-0000-0000-0000-000000000002/last-a.jpg' then
    raise exception 'A query string was taken to be part of the object path.';
  end if;

  -- The announcement still shows one of the three.
  if not public.daily_darshan_object_is_referenced(v_shared) then
    raise exception 'The announcement''s picture was not seen to be in use.';
  end if;
  if public.daily_darshan_object_is_referenced(v_dead) then
    raise exception 'A picture nothing points at was thought to be in use.';
  end if;
  if not public.daily_darshan_object_is_referenced(v_alive) then
    raise exception 'This week''s own picture was not seen to be in use.';
  end if;
end;
$$;

-- The reaper, with no reaper deployed.
do $$
declare
  v_handed integer;
  v_shared text := (select url from public.dw_urls where key = 'last_shared');
begin
  v_handed := public.reap_darshan_images();
  if v_handed <> 0 then
    raise exception 'With no endpoint configured, % files were handed off.', v_handed;
  end if;

  -- The one the announcement shows is settled and will never be offered again.
  if (select outcome from public.daily_darshan_reaped_images
      where daily_darshan_reaped_images.image_url = v_shared) <> 'still_in_use' then
    raise exception 'The shared picture was not settled as still in use.';
  end if;

  -- The other two are still waiting, which is the honest state: they are dead
  -- and nothing in this database can remove them.
  if (select count(*) from public.daily_darshan_reaped_images
      where daily_darshan_reaped_images.settled_at is null) <> 2 then
    raise exception 'The two dead files did not stay pending.';
  end if;

  -- Run again: the settled one is not reconsidered, and nothing raises.
  if public.reap_darshan_images() <> 0 then
    raise exception 'A second reaper run handed something off with no endpoint.';
  end if;
  if (select count(*) from public.daily_darshan_reaped_images) <> 3 then
    raise exception 'The reaper invented or lost a ledger row.';
  end if;
end;
$$;

-- With an endpoint configured but pg_net absent -- which is exactly this
-- cluster -- nothing is handed off, nothing is marked done, and nothing
-- raises. Push delivery degrades the same way in 202608040026.
do $$
begin
  insert into public.app_settings (key, value) values
    ('daily_darshan.reaper_url', 'https://project.functions.supabase.co/reap-darshan'),
    ('daily_darshan.reaper_secret', 'not-a-real-secret')
  on conflict (key) do update set value = excluded.value;

  if public.reap_darshan_images() <> 0 then
    raise exception 'Something was handed off on a cluster with no pg_net.';
  end if;
  if exists (select 1 from public.daily_darshan_reaped_images
             where daily_darshan_reaped_images.handed_off_at is not null) then
    raise exception 'A file was recorded as handed off when nothing was posted.';
  end if;

  delete from public.app_settings
  where app_settings.key in ('daily_darshan.reaper_url', 'daily_darshan.reaper_secret');
end;
$$;

-- The reaper confirming what it removed.
do $$
declare
  v_ids uuid[];
  v_settled integer;
begin
  select array_agg(entries.id) into v_ids
  from public.daily_darshan_reaped_images entries
  where entries.settled_at is null;

  v_settled := public.mark_darshan_images_reaped(v_ids);
  if v_settled <> 2 then
    raise exception 'The reaper confirmed % removals rather than 2.', v_settled;
  end if;
  if (select count(*) from public.daily_darshan_reaped_images
      where daily_darshan_reaped_images.outcome = 'unlinked') <> 2 then
    raise exception 'The confirmed removals were not recorded as unlinked.';
  end if;

  -- Confirming twice settles nothing further, and null is not an error.
  if public.mark_darshan_images_reaped(v_ids) <> 0 then
    raise exception 'A repeated confirmation settled something again.';
  end if;
  if public.mark_darshan_images_reaped(null) <> 0
    or public.mark_darshan_images_reaped('{}'::uuid[]) <> 0 then
    raise exception 'An empty confirmation was not a no-op.';
  end if;
end;
$$;

-- Replacing a gallery, and taking a darshan down, put their files on the
-- ledger by the same trigger. And a file queued twice while still pending is
-- queued once.
select set_config('request.jwt.claim.sub', 'f0000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_today date := (now() at time zone 'America/Chicago')::date;
  v_base text := 'https://project.supabase.co/storage/v1/object/public/message-images/'
    || 'f0000000-0000-0000-0000-000000000002/';
begin
  -- this-b.jpg is dropped from the gallery; this-a.jpg stays.
  perform public.publish_daily_darshan(
    v_today,
    'Straightened the second photograph.',
    jsonb_build_array(
      jsonb_build_object('imageUrl', v_base || 'this-a.jpg',
        'deity', 'Kisora Kisori', 'position', 1),
      jsonb_build_object('imageUrl', v_base || 'this-c.jpg',
        'deity', 'Kisora Kisori', 'position', 2))
  );
end;
$$;

reset role;

do $$
declare
  v_pending integer;
  v_b text := (select url from public.dw_urls where key = 'this_b');
begin
  -- Both pictures were deleted and both were queued; a-jpg went straight back
  -- in, which the trigger cannot know and the reaper works out later.
  if not exists (select 1 from public.daily_darshan_reaped_images
                 where daily_darshan_reaped_images.image_url = v_b
                   and daily_darshan_reaped_images.settled_at is null) then
    raise exception 'The dropped photograph was not written down.';
  end if;

  select count(*)::integer into v_pending from public.daily_darshan_reaped_images
  where daily_darshan_reaped_images.settled_at is null;
  if v_pending <> 2 then
    raise exception 'Replacing a two-picture gallery left % entries pending rather than 2.',
      v_pending;
  end if;

  -- The reaper settles the one that went straight back in and keeps the one
  -- that did not. This is the whole reason the question is asked late.
  perform public.reap_darshan_images();
  if (select outcome from public.daily_darshan_reaped_images
      where daily_darshan_reaped_images.image_url
            = (select url from public.dw_urls where key = 'this_a')) <> 'still_in_use' then
    raise exception 'A picture that was re-published was not settled as still in use.';
  end if;
  if (select count(*) from public.daily_darshan_reaped_images
      where daily_darshan_reaped_images.settled_at is null) <> 1 then
    raise exception 'The dropped photograph did not stay pending.';
  end if;
end;
$$;

-- Taking today's darshan down queues the rest of it.
select set_config('request.jwt.claim.sub', 'f0000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_id uuid := (select id from public.dw_ids where key = 'today');
begin
  perform public.delete_daily_darshan(v_id);
end;
$$;

reset role;

do $$
begin
  if not exists (select 1 from public.daily_darshan_reaped_images
                 where daily_darshan_reaped_images.image_url like '%this-c.jpg') then
    raise exception 'Deleting a darshan did not write its files down.';
  end if;

  -- The same pending path is never written twice.
  if exists (
    select 1 from public.daily_darshan_reaped_images
    where settled_at is null
    group by bucket_id, object_path
    having count(*) > 1
  ) then
    raise exception 'A dead file was queued for deletion more than once.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. Publishing lives inside the week, and the two date guards are two guards.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'f0000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_floor date := public.daily_darshan_week_floor();
  v_today date := (now() at time zone 'America/Chicago')::date;
  v_base text := 'https://project.supabase.co/storage/v1/object/public/message-images/'
    || 'f0000000-0000-0000-0000-000000000002/';
  v_one jsonb := jsonb_build_array(jsonb_build_object(
    'imageUrl', 'https://project.supabase.co/storage/v1/object/public/message-images/'
      || 'f0000000-0000-0000-0000-000000000002/probe.jpg', 'position', 1));
  v_message text;
  v_offset integer;
begin
  -- The day before this Monday, and the day before that.
  v_message := null;
  begin
    perform public.publish_daily_darshan(v_floor - 1, 'Last week.', v_one);
  exception when others then v_message := sqlerrm;
  end;
  if v_message is null then
    raise exception 'A darshan was published into a week the gallery does not hold.';
  end if;
  if v_message !~ 'this week only' or v_message !~ v_floor::text then
    raise exception 'The refusal does not say which week or from when: %', v_message;
  end if;

  -- Eight days ago is refused by the BACKDATE guard, whose message is
  -- different, so the two are not one guard wearing two hats.
  v_message := null;
  begin
    perform public.publish_daily_darshan(v_today - 8, 'Long ago.', v_one);
  exception when others then v_message := sqlerrm;
  end;
  if v_message is null or v_message !~ 'last 7 days' then
    raise exception 'Eight days ago was not refused by the backdate guard: %',
      coalesce(v_message, 'no error');
  end if;

  -- Tomorrow is still refused.
  v_message := null;
  begin
    perform public.publish_daily_darshan(v_today + 1, 'Tomorrow.', v_one);
  exception when others then v_message := sqlerrm;
  end;
  if v_message is null or v_message !~ 'has not happened yet' then
    raise exception 'Tomorrow was not refused: %', coalesce(v_message, 'no error');
  end if;

  -- And every day of the week so far is accepted, from this Monday to today,
  -- which on a Monday is one day and on a Sunday is seven.
  for v_offset in 0..(v_today - v_floor) loop
    v_message := null;
    begin
      perform public.publish_daily_darshan(
        v_floor + v_offset, 'Day ' || v_offset || ' of the week.',
        jsonb_build_array(jsonb_build_object(
          'imageUrl', v_base || 'week-' || v_offset || '.jpg',
          'deity', 'Kisora Kisori', 'position', 1)));
    exception when others then v_message := sqlerrm;
    end;
    if v_message is not null then
      raise exception 'A darshan for %, inside this week, was refused: %',
        v_floor + v_offset, v_message;
    end if;
  end loop;

  if (select count(*) from public.daily_darshan) <> v_today - v_floor + 1 then
    raise exception 'The week holds % darshans rather than one for each of its % days so far.',
      (select count(*) from public.daily_darshan), v_today - v_floor + 1;
  end if;
end;
$$;

reset role;

-- ---------------------------------------------------------------------------
-- 9. Nothing added here is a back door.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'f0000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
  v_call text;
  v_message text;
  v_open text := '';
begin
  foreach v_call in array array[
    'select public.sweep_daily_darshan()',
    'select public.reap_darshan_images()',
    'select public.mark_darshan_images_reaped(''{}''::uuid[])',
    'select * from public.daily_darshan_notification_text(current_date)',
    'select public.daily_darshan_deity_names(current_date)',
    'select public.daily_darshan_deity_phrase(''{}''::text[])',
    'select public.daily_darshan_object_path(''x'')',
    'select public.daily_darshan_object_is_referenced(''x'')',
    'select count(*) from public.daily_darshan_reaped_images'
  ] loop
    v_message := null;
    begin
      execute v_call;
    exception when others then v_message := sqlerrm;
    end;
    if v_message is null then
      v_open := v_open || E'\n  ' || v_call;
    end if;
  end loop;

  if v_open <> '' then
    raise exception E'The President could reach these from the client role:%', v_open;
  end if;
end;
$$;

-- What a signed-in devotee may do: read the floor, and -- for the two who hold
-- app.view_all -- see how much is waiting.
do $$
declare
  v_floor date;
begin
  v_floor := public.daily_darshan_week_floor();
  if v_floor is null then
    raise exception 'A devotee cannot read the week the gallery holds.';
  end if;
  if (select count(*) from public.pending_darshan_image_reaps()) <> 1 then
    raise exception 'The President cannot see the reaping backlog.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'f0000000-0000-0000-0000-000000000004', true);
set local role authenticated;

do $$
begin
  -- An ordinary devotee gets no row at all, not a row of zeros: a row of zeros
  -- would say whether a reaper is configured.
  if (select count(*) from public.pending_darshan_image_reaps()) <> 0 then
    raise exception 'A plain devotee was shown the reaping backlog.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', null, true);
set local role anon;

do $$
declare
  v_message text;
begin
  v_message := null;
  begin
    perform public.daily_darshan_week_floor();
  exception when others then v_message := sqlerrm;
  end;
  if v_message is null then
    raise exception 'Anon could read the Daily Darshan week.';
  end if;
end;
$$;

reset role;

-- The wording function cannot name a devotee because it never reads them.
do $$
declare
  v_source text := pg_get_functiondef('public.daily_darshan_notification_text(date)'::regprocedure);
begin
  if v_source ~* 'public\.users' or v_source ~* 'auth\.uid' then
    raise exception 'The wording function reads the devotee table.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 10. Every guard, mutated.
--
--     Each row below breaks exactly one thing this file relies on and re-reads
--     one answer through the real function. A guard whose mutation changes
--     nothing was not doing anything, and the table says so out loud.
--
--     Both readings roll back whatever they would have written -- dw_probe
--     runs its statement inside a subtransaction and then raises -- so a probe
--     that deletes the week does not leave the week deleted, and the same
--     question can honestly be asked twice. The probe is read a third time
--     after the mutation is undone and must match the first, or the harness
--     itself is lying.
-- ---------------------------------------------------------------------------

-- The fixture is rebuilt: sections 7 and 8 have been moving it about.
delete from public.daily_darshan;
delete from public.daily_darshan_reaped_images;
delete from public.app_notifications;

do $$
declare
  v_floor date := public.daily_darshan_week_floor();
  v_today date := (now() at time zone 'America/Chicago')::date;
  v_base text := 'https://project.supabase.co/storage/v1/object/public/message-images/'
    || 'f0000000-0000-0000-0000-000000000002/';
  v_id uuid;
begin
  -- Last week carries three pictures, and each of them is also an
  -- announcement's picture, so the reaper has three entries to settle and a
  -- batch size is something that can be seen from outside.
  insert into public.daily_darshan (darshan_on, note, posted_by)
  values (v_floor - 3, 'Last week.', 'f0000000-0000-0000-0000-000000000002')
  returning daily_darshan.id into v_id;
  insert into public.daily_darshan_images (darshan_id, image_url, deity, "position")
  values
    (v_id, v_base || 'm-last.jpg', 'Kisora Kisori', 1),
    (v_id, v_base || 'm-last2.jpg', 'Kisora Kisori', 2),
    (v_id, v_base || 'm-last3.jpg', 'Kisora Kisori', 3);

  insert into public.daily_darshan (darshan_on, note, posted_by)
  values (v_today, 'Today.', 'f0000000-0000-0000-0000-000000000002')
  returning daily_darshan.id into v_id;
  insert into public.daily_darshan_images (darshan_id, image_url, deity, "position")
  values
    (v_id, v_base || 'm-a.jpg', 'Kisora Kisori', 1),
    (v_id, v_base || 'm-b.jpg', 'Gaura Nitai', 2),
    (v_id, v_base || 'm-c.jpg', 'Radha Govinda', 3);

  -- The announcements that hold them, so the still-in-use path has something
  -- to find and the batch size has something to bound.
  insert into public.announcements (title, body, image_url, posted_by)
  values
    ('Held one', 'Held.', v_base || 'm-last.jpg', 'f0000000-0000-0000-0000-000000000002'),
    ('Held two', 'Held.', v_base || 'm-last2.jpg', 'f0000000-0000-0000-0000-000000000002'),
    ('Held three', 'Held.', v_base || 'm-last3.jpg', 'f0000000-0000-0000-0000-000000000002'),
    -- And one picture NO darshan has ever pointed at, so mutation 13 can ask
    -- about a file whose only reference is the announcement's.
    ('Held alone', 'Held.', v_base || 'm-orphan.jpg', 'f0000000-0000-0000-0000-000000000002');
end;
$$;

-- The Head is signed in for the whole of this section, so probes that publish
-- and probes that read see the same caller.
select set_config('request.jwt.claim.sub', 'f0000000-0000-0000-0000-000000000002', true);

create table dw_mutations (
  n integer primary key,
  guard text not null,
  mutation text not null,
  probe text not null,
  intact text not null,
  mutated text not null,
  killed boolean not null
);

create function pg_temp.dw_probe(p_sql text)
returns text
language plpgsql
as $$
declare
  v_answer text;
begin
  begin
    execute p_sql into v_answer;
    raise exception using errcode = 'PT790', message = coalesce(v_answer, '(null)');
  exception when sqlstate 'PT790' then
    return sqlerrm;
  end;
end;
$$;

-- For probes whose answer is whether something was refused, and what it said.
create function pg_temp.dw_try(p_sql text)
returns text
language plpgsql
as $$
begin
  execute p_sql;
  return 'accepted';
exception when others then
  return 'refused: ' || left(sqlerrm, 60);
end;
$$;

-- Three probes that need more than one statement, so they are named rather
-- than spelled into the mutation table. Each runs entirely inside dw_probe's
-- subtransaction and is rolled back with it.
create function pg_temp.dw_written_probe()
returns text
language plpgsql
as $$
declare
  v_swept integer;
begin
  v_swept := public.sweep_daily_darshan();
  return v_swept || ' swept, '
    || (select count(*) from public.daily_darshan_reaped_images) || ' written';
end;
$$;

create function pg_temp.dw_reap_probe()
returns text
language plpgsql
as $$
begin
  perform public.sweep_daily_darshan();
  perform public.reap_darshan_images();
  return (select count(*) from public.daily_darshan_reaped_images
          where settled_at is not null) || ' settled';
end;
$$;

create function pg_temp.dw_retry_probe()
returns text
language plpgsql
as $$
begin
  perform public.sweep_daily_darshan();
  -- Every entry was handed to a reaper half an hour ago and never confirmed.
  update public.daily_darshan_reaped_images
  set handed_off_at = now() - interval '30 minutes'
  where settled_at is null;
  perform public.reap_darshan_images();
  return (select count(*) from public.daily_darshan_reaped_images
          where settled_at is not null) || ' settled';
end;
$$;

create function pg_temp.dw_mutate(
  p_n integer, p_guard text, p_mutation text, p_probe text,
  p_apply text, p_query text
)
returns void
language plpgsql
as $$
declare
  v_intact text;
  v_mutated text;
  v_restored text;
begin
  v_intact := pg_temp.dw_probe(p_query);

  begin
    execute p_apply;
    v_mutated := pg_temp.dw_probe(p_query);
    raise exception using errcode = 'PT791', message = v_mutated;
  exception when sqlstate 'PT791' then
    v_mutated := sqlerrm;
  end;

  v_restored := pg_temp.dw_probe(p_query);
  if v_restored is distinct from v_intact then
    raise exception 'Mutation % did not roll back: the probe read % before and % after.',
      p_n, v_intact, v_restored;
  end if;

  insert into dw_mutations (n, guard, mutation, probe, intact, mutated, killed)
  values (p_n, p_guard, p_mutation, p_probe, v_intact, v_mutated,
          v_mutated is distinct from v_intact);
end;
$$;

do $$
declare
  v_floor date := public.daily_darshan_week_floor();
  v_today date := (now() at time zone 'America/Chicago')::date;
  v_one text :=
    'jsonb_build_array(jsonb_build_object(''imageUrl'', '
    || '''https://project.supabase.co/storage/v1/object/public/message-images/'
    || 'f0000000-0000-0000-0000-000000000002/probe.jpg'', ''position'', 1))';
begin
  perform pg_temp.dw_mutate(
    1,
    'the week is the app''s one week, from seva_mala_week_start',
    'seva_mala_week_start redefined to start on Sunday',
    'daily_darshan_week_floor()',
    'create or replace function public.seva_mala_week_start(p_on date) '
      || 'returns date language sql immutable set search_path = '''' as '
      || '$f$ select p_on - (extract(dow from p_on)::integer) $f$',
    'select public.daily_darshan_week_floor()::text');

  perform pg_temp.dw_mutate(
    2,
    'keep_weeks widens the gallery',
    'keep_weeks 1 -> 3',
    'daily_darshan_week_floor()',
    'update public.app_settings set value = ''3'' where key = ''daily_darshan.keep_weeks''',
    'select public.daily_darshan_week_floor()::text');

  perform pg_temp.dw_mutate(
    3,
    'keep_weeks below one raises rather than holding nothing',
    'keep_weeks 1 -> 0',
    'daily_darshan_week_floor(), refused or not',
    'update public.app_settings set value = ''0'' where key = ''daily_darshan.keep_weeks''',
    'select pg_temp.dw_try(''select public.daily_darshan_week_floor()'')');

  perform pg_temp.dw_mutate(
    4,
    'the reads start at the floor',
    'keep_weeks 1 -> 3',
    'darshans list_daily_darshan returns',
    'update public.app_settings set value = ''3'' where key = ''daily_darshan.keep_weeks''',
    'select count(*)::text from public.list_daily_darshan(100)');

  perform pg_temp.dw_mutate(
    5,
    'the sweep deletes below the floor',
    'keep_weeks 1 -> 3',
    'darshans sweep_daily_darshan() removes',
    'update public.app_settings set value = ''3'' where key = ''daily_darshan.keep_weeks''',
    'select public.sweep_daily_darshan()::text');

  perform pg_temp.dw_mutate(
    6,
    'publish refuses a day the gallery will not hold',
    'keep_weeks 1 -> 3',
    format('publish_daily_darshan(%L, ...), refused or not', v_floor - 1),
    'update public.app_settings set value = ''3'' where key = ''daily_darshan.keep_weeks''',
    format('select pg_temp.dw_try(%L)',
           format('select public.publish_daily_darshan(%L, ''Probe.'', %s)',
                  v_floor - 1, v_one)));

  perform pg_temp.dw_mutate(
    7,
    'the week guard is not hiding behind the backdate guard',
    'max_backdate_days 7 -> 60',
    format('publish_daily_darshan(%L, ...), and what it says', v_today - 8),
    'update public.app_settings set value = ''60'' where key = ''daily_darshan.max_backdate_days''',
    format('select pg_temp.dw_try(%L)',
           format('select public.publish_daily_darshan(%L, ''Probe.'', %s)',
                  v_today - 8, v_one)));

  perform pg_temp.dw_mutate(
    8,
    'max_named_deities decides when the list collapses',
    'max_named_deities 3 -> 2',
    format('the wording for %L', v_today),
    'update public.app_settings set value = ''2'' where key = ''daily_darshan.max_named_deities''',
    format('select notice.body from public.daily_darshan_notification_text(%L) as notice',
           v_today));

  perform pg_temp.dw_mutate(
    9,
    'a cap below two is refused rather than making a phrase with nothing in front of it',
    'max_named_deities 3 -> 1',
    'daily_darshan_deity_phrase, refused or not',
    'update public.app_settings set value = ''1'' where key = ''daily_darshan.max_named_deities''',
    'select pg_temp.dw_try(''select public.daily_darshan_deity_phrase('
      || '''''{A,B}''''::text[])'')');

  perform pg_temp.dw_mutate(
    10,
    'max_title_chars cuts the title to a lock screen',
    'max_title_chars 60 -> 12',
    format('the title for %L', v_today),
    'update public.app_settings set value = ''12'' where key = ''daily_darshan.max_title_chars''',
    format('select notice.title from public.daily_darshan_notification_text(%L) as notice',
           v_today));

  perform pg_temp.dw_mutate(
    11,
    'max_body_chars cuts the body to a lock screen',
    'max_body_chars 120 -> 20',
    format('the body for %L', v_today),
    'update public.app_settings set value = ''20'' where key = ''daily_darshan.max_body_chars''',
    format('select notice.body from public.daily_darshan_notification_text(%L) as notice',
           v_today));

  perform pg_temp.dw_mutate(
    12,
    'a deleted picture is written down for the reaper',
    'the remember_reaped_darshan_image trigger disabled',
    'ledger entries after sweep_daily_darshan()',
    'alter table public.daily_darshan_images disable trigger remember_reaped_darshan_image',
    'select pg_temp.dw_written_probe()');

  perform pg_temp.dw_mutate(
    13,
    'a file another feature still shows is never reaped',
    'announcements.image_url renamed out of the convention',
    'daily_darshan_object_is_referenced of a file only an announcement shows',
    'alter table public.announcements rename column image_url to picture_link',
    'select public.daily_darshan_object_is_referenced('
      || '''https://project.supabase.co/storage/v1/object/public/message-images/'
      || 'f0000000-0000-0000-0000-000000000002/m-orphan.jpg'')::text');

  perform pg_temp.dw_mutate(
    14,
    'reap_batch bounds one tick',
    'reap_batch 50 -> 1',
    'entries settled by one sweep and one reap',
    'update public.app_settings set value = ''1'' where key = ''daily_darshan.reap_batch''',
    'select pg_temp.dw_reap_probe()');

  perform pg_temp.dw_mutate(
    15,
    'an unconfirmed hand-off waits reap_retry_minutes before being offered again',
    'reap_retry_minutes 60 -> 0',
    'entries a reap run reconsiders after one was handed off an hour ago',
    'update public.app_settings set value = ''0'' where key = ''daily_darshan.reap_retry_minutes''',
    'select pg_temp.dw_retry_probe()');
end;
$$;

do $$
declare
  v_survivors text;
  v_count integer;
begin
  select count(*)::integer into v_count from dw_mutations;
  if v_count <> 15 then
    raise exception 'Only % mutations ran.', v_count;
  end if;

  select string_agg(dw_mutations.n || ': ' || dw_mutations.guard, E'\n  ')
  into v_survivors
  from dw_mutations where not dw_mutations.killed;

  if v_survivors is not null then
    raise exception E'These guards survived being broken:\n  %', v_survivors;
  end if;

  -- The probes rolled back everything: the week is still there, nothing was
  -- swept, and nothing reached the ledger.
  if (select count(*) from public.daily_darshan) <> 2 then
    raise exception 'A mutation probe left the gallery swept; the harness is lying.';
  end if;
  if (select count(*) from public.daily_darshan_reaped_images) <> 0 then
    raise exception 'A mutation probe left entries on the ledger; the harness is lying.';
  end if;
  if (select count(*) from public.app_notifications) <> 0 then
    raise exception 'A mutation probe left the congregation notified; the harness is lying.';
  end if;
end;
$$;

select
  dw_mutations.n,
  dw_mutations.guard,
  dw_mutations.mutation,
  dw_mutations.probe,
  dw_mutations.intact,
  dw_mutations.mutated,
  case when dw_mutations.killed then 'killed' else 'SURVIVED' end as verdict
from dw_mutations
order by dw_mutations.n;

do $$
begin
  raise notice 'all darshan week and voice checks passed';
end;
$$;

select 'darshan week and voice verification passed' as result;

rollback;
