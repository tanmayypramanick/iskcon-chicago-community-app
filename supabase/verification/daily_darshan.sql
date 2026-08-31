-- Functional verification for 202608290078_daily_darshan.sql.
--
-- Rolled back at the end. Every local is prefixed v_ so it can never shadow a
-- column name. Anything that must be refused is attempted as the devotee who
-- would really attempt it, under `set local role authenticated`, so the row
-- level security policies and the column grants are the thing being tested
-- rather than superuser rights quietly waving everything through. Notification
-- assertions are made after `reset role`, because a devotee cannot — and
-- should not be able to — read somebody else's inbox.
--
-- The five people in this script:
--   President  ...0001  may post, and may take anybody's darshan down
--   Head       ...0002  Community Head; posts most of what is checked here
--   Tech       ...0003  Tech Admin; the third of the three who may post
--   Devotee    ...0004  sees everything, may post nothing, deletes nothing
--   Volunteer  ...0005  the nearest role that must still be refused
--
-- What this script exists to prove:
--
--    1. The permission gating the post names exactly Community Head, Tech
--       Admin and President, and no new key was invented.
--    2. A plain devotee and a volunteer are refused; all three of the named
--       roles are accepted.
--    3. More than five pictures is refused. Zero pictures is refused. Both
--       bounds are dials, not literals.
--    4. Every other guard: a photo from another host, a blank photo, two
--       pictures in the same position, a day that has not happened, a day too
--       long ago, an over-long note or credit, a missing list.
--    5. Every signed-in devotee may read; anon may read nothing.
--    6. The pictures come back with the darshan, ordered by position, and as
--       [] rather than null when there are none.
--    7. The congregation is notified once per post — never once per picture —
--       and everybody is told except the poster.
--    8. Re-posting a date REPLACES it: same row, new pictures, no orphans, and
--       no second notification.
--    9. Deleting takes the picture rows with it and leaves the bucket alone.
--   10. Neither table is a back door.
--   11. Thirteen mutations, each breaking exactly one guard.
--
-- The final row must read: daily darshan verification passed

begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('d0000000-0000-0000-0000-000000000001', 'dd-president@example.test', '{"name":"Dee President"}'),
  ('d0000000-0000-0000-0000-000000000002', 'dd-head@example.test', '{"name":"Dee Head"}'),
  ('d0000000-0000-0000-0000-000000000003', 'dd-tech@example.test', '{"name":"Dee Tech"}'),
  ('d0000000-0000-0000-0000-000000000004', 'dd-devotee@example.test', '{"name":"Dee Devotee"}'),
  ('d0000000-0000-0000-0000-000000000005', 'dd-volunteer@example.test', '{"name":"Dee Volunteer"}');

update public.users
set role_id = (select roles.id from public.roles where roles.name = 'president')
where email = 'dd-president@example.test';
update public.users
set role_id = (select roles.id from public.roles where roles.name = 'core')
where email = 'dd-head@example.test';
update public.users
set role_id = (select roles.id from public.roles where roles.name = 'tech')
where email = 'dd-tech@example.test';
update public.users
set role_id = (select roles.id from public.roles where roles.name = 'devotee')
where email = 'dd-devotee@example.test';
update public.users
set role_id = (select roles.id from public.roles where roles.name = 'volunteer')
where email = 'dd-volunteer@example.test';

-- The account-creation trigger has already written devotee_joined rows.
-- Nothing below counts those, and clearing the table keeps every count in this
-- script about the darshan alone.
delete from public.app_notifications;

-- Ordinary table rather than a temporary one, so reading it under the
-- authenticated role needs no assumptions about the temp schema. The whole
-- script is rolled back, so it never outlives the transaction.
create table public.darshan_test_ids (key text primary key, id uuid not null);
grant select, insert on public.darshan_test_ids to authenticated;

-- 202608290079_darshan_week_and_voice.sql made the gallery hold the current
-- Chicago week only: publish_daily_darshan refuses a day the gallery will not
-- hold, and list_daily_darshan starts at that Monday. This script's fixture is
-- three consecutive days ending today, which on a Monday or a Tuesday no
-- one-week gallery can contain -- and the point of this script is the shape of
-- a darshan, not the width of the week, which darshan_week_and_voice.sql
-- proves at length.
--
-- So the width is dialled up for the length of this transaction and rolled
-- back with it. daily_darshan.max_backdate_days is untouched, so the eight-day
-- refusal below is still the backdate guard being tested and not this one.
update public.app_settings
set value = '4'
where app_settings.key = 'daily_darshan.keep_weeks';

-- ---------------------------------------------------------------------------
-- 0. The permission being relied on is the one the temple already uses for
--    "Community Head, Tech Admin, President", no fourth role has it, and no
--    fifth key was registered for this feature.
--
--    If a later migration widens services.manage_recurring, the Daily Darshan
--    widens with it silently. That is worth failing loudly over here rather
--    than discovering it when a volunteer posts to the whole congregation.
-- ---------------------------------------------------------------------------

do $$
declare
  v_holders text;
  v_value text;
begin
  select string_agg(roles.name, ',' order by roles.name) into v_holders
  from public.role_permissions
  join public.roles on roles.id = role_permissions.role_id
  where role_permissions.permission_key = 'services.manage_recurring';

  if v_holders is distinct from 'core,president,tech' then
    raise exception
      'services.manage_recurring is held by % — the Daily Darshan assumes core, president, tech.',
      coalesce(v_holders, '(nobody)');
  end if;

  -- core is the Community Head, tech is the Tech Admin, president is the
  -- President: the three named roles and nothing else in the roles table.
  if (select count(*) from public.roles) <> 5 then
    raise exception 'The roles table no longer holds the five roles this file reasons about.';
  end if;

  -- No new permission key was invented for this feature.
  if exists (
    select 1 from public.role_permissions
    where role_permissions.permission_key ilike '%darshan%'
  ) then
    raise exception 'A separate Daily Darshan permission key was registered.';
  end if;

  -- Every limit is a dial. If one of these is missing, some function body is
  -- carrying a literal instead.
  foreach v_value in array array[
    'daily_darshan.max_images', 'daily_darshan.min_images',
    'daily_darshan.max_note_chars', 'daily_darshan.max_credit_chars',
    'daily_darshan.max_backdate_days', 'daily_darshan.list_limit_max'
  ]
  loop
    if not exists (select 1 from public.app_settings where app_settings.key = v_value) then
      raise exception 'The dial % is not in app_settings.', v_value;
    end if;
  end loop;

  if public.daily_darshan_limit('daily_darshan.max_images') <> 5 then
    raise exception 'The temple asked for five pictures; the dial says %.',
      public.daily_darshan_limit('daily_darshan.max_images');
  end if;
  if public.daily_darshan_limit('daily_darshan.min_images') <> 1 then
    raise exception 'A darshan with no pictures is not a darshan; min_images is %.',
      public.daily_darshan_limit('daily_darshan.min_images');
  end if;

  -- A missing dial raises rather than silently defaulting.
  begin
    perform public.daily_darshan_limit('daily_darshan.no_such_dial');
    raise exception 'A missing dial returned a value instead of raising.';
  exception when others then
    if sqlerrm !~* 'missing' then
      raise exception 'A missing dial raised the wrong thing: %', sqlerrm;
    end if;
  end;
end;
$$;

-- ---------------------------------------------------------------------------
-- 1. A plain devotee cannot post. Neither can a volunteer.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'd0000000-0000-0000-0000-000000000004', true);
set local role authenticated;

do $$
declare
  v_message text := null;
  v_today date := (now() at time zone 'America/Chicago')::date;
begin
  begin
    perform public.publish_daily_darshan(
      v_today, 'Sneaking in.',
      jsonb_build_array(jsonb_build_object(
        'imageUrl', 'https://project.supabase.co/storage/v1/object/public/message-images/'
          || 'd0000000-0000-0000-0000-000000000004/a.jpg',
        'deity', 'Radha Govinda', 'dressedBy', 'Nobody', 'position', 1))
    );
  exception when others then
    v_message := sqlerrm;
  end;
  if v_message is null then
    raise exception 'A plain devotee posted the Daily Darshan.';
  end if;
  if v_message !~* 'Community Head' then
    raise exception 'A devotee was refused unreadably: %', v_message;
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'd0000000-0000-0000-0000-000000000005', true);
set local role authenticated;

do $$
declare
  v_refused boolean := false;
  v_today date := (now() at time zone 'America/Chicago')::date;
begin
  begin
    perform public.publish_daily_darshan(
      v_today, 'Sneaking in.',
      jsonb_build_array(jsonb_build_object(
        'imageUrl', 'https://project.supabase.co/storage/v1/object/public/message-images/'
          || 'd0000000-0000-0000-0000-000000000005/a.jpg',
        'position', 1))
    );
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A volunteer posted the Daily Darshan.';
  end if;
end;
$$;

-- Nothing the two of them tried left a row behind.
reset role;

do $$
begin
  if (select count(*) from public.daily_darshan) <> 0 then
    raise exception 'A refused post wrote a darshan anyway.';
  end if;
  if (select count(*) from public.daily_darshan_images) <> 0 then
    raise exception 'A refused post wrote pictures anyway.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. A Community Head posts today's darshan, and everything survives the round
--    trip — including the ordering, which is deliberately given out of order.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'd0000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_id uuid;
  v_today date := (now() at time zone 'America/Chicago')::date;
  v_base text := 'https://project.supabase.co/storage/v1/object/public/message-images/'
    || 'd0000000-0000-0000-0000-000000000002/';
  v_row public.daily_darshan;
begin
  v_id := public.publish_daily_darshan(
    v_today,
    'Sri Sri Radha Govinda on Their new summer outfits.',
    jsonb_build_array(
      jsonb_build_object('imageUrl', v_base || 'three.jpg',
        'deity', 'Sri Sri Gaura Nitai', 'dressedBy', 'Bhaktin Anjali', 'position', 3),
      jsonb_build_object('imageUrl', v_base || 'one.jpg',
        'deity', 'Sri Sri Radha Govinda', 'dressedBy', 'Mataji Radhika', 'position', 1),
      jsonb_build_object('imageUrl', v_base || 'two.jpg',
        'deity', 'Sri Jagannath', 'dressedBy', null, 'position', 2)
    )
  );

  if v_id is null then
    raise exception 'A Community Head could not post the Daily Darshan.';
  end if;
  insert into public.darshan_test_ids values ('today', v_id);
end;
$$;

reset role;

do $$
declare
  v_row public.daily_darshan;
  v_today date := (now() at time zone 'America/Chicago')::date;
  v_id uuid;
begin
  select ids.id into v_id from public.darshan_test_ids ids where ids.key = 'today';
  select * into v_row from public.daily_darshan where daily_darshan.id = v_id;

  if v_row.darshan_on <> v_today then
    raise exception 'The darshan was filed under % rather than today in Chicago (%).',
      v_row.darshan_on, v_today;
  end if;
  if v_row.posted_by <> 'd0000000-0000-0000-0000-000000000002' then
    raise exception 'The darshan did not record who posted it.';
  end if;
  if v_row.note !~ 'summer outfits' then
    raise exception 'The note did not survive the round trip: %', v_row.note;
  end if;
  if (select count(*) from public.daily_darshan_images
      where daily_darshan_images.darshan_id = v_id) <> 3 then
    raise exception 'Three pictures went up and % came back.',
      (select count(*) from public.daily_darshan_images
       where daily_darshan_images.darshan_id = v_id);
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. The President and the Tech Admin can post too — and the two boundaries,
--    one picture and five pictures, are both accepted.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'd0000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
  v_id uuid;
  v_today date := (now() at time zone 'America/Chicago')::date;
begin
  -- Exactly the minimum, and no note at all: the note is optional.
  v_id := public.publish_daily_darshan(
    v_today - 1, null,
    jsonb_build_array(jsonb_build_object(
      'imageUrl', 'https://project.supabase.co/storage/v1/object/public/message-images/'
        || 'd0000000-0000-0000-0000-000000000001/yesterday.jpg',
      'deity', 'Sri Sri Radha Govinda', 'dressedBy', 'Prabhu Gopal', 'position', 1))
  );
  if v_id is null then
    raise exception 'The President could not post the Daily Darshan.';
  end if;
  insert into public.darshan_test_ids values ('yesterday', v_id);
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'd0000000-0000-0000-0000-000000000003', true);
set local role authenticated;

do $$
declare
  v_id uuid;
  v_today date := (now() at time zone 'America/Chicago')::date;
  v_base text := 'https://project.supabase.co/storage/v1/object/public/message-images/'
    || 'd0000000-0000-0000-0000-000000000003/';
  v_images jsonb := '[]'::jsonb;
  v_n integer;
begin
  -- Exactly the maximum.
  for v_n in 1..5 loop
    v_images := v_images || jsonb_build_array(jsonb_build_object(
      'imageUrl', v_base || v_n || '.jpg',
      'deity', 'Deity ' || v_n, 'dressedBy', 'Devotee ' || v_n, 'position', v_n));
  end loop;

  v_id := public.publish_daily_darshan(v_today - 2, 'Five is the temple''s number.', v_images);
  if v_id is null then
    raise exception 'A Tech Admin could not post five pictures.';
  end if;
  insert into public.darshan_test_ids values ('two_days_ago', v_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Every guard, refused, and with a message a devotee could act on.
--
--    The six-picture and zero-picture cases are the two the temple actually
--    asked for, so both are asserted to name the number rather than merely to
--    fail.
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', 'd0000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_message text;
  v_today date := (now() at time zone 'America/Chicago')::date;
  v_base text := 'https://project.supabase.co/storage/v1/object/public/message-images/'
    || 'd0000000-0000-0000-0000-000000000002/';
  v_images jsonb;
  v_n integer;
  v_target date := (now() at time zone 'America/Chicago')::date - 3;
begin
  -- Six pictures.
  v_images := '[]'::jsonb;
  for v_n in 1..6 loop
    v_images := v_images || jsonb_build_array(jsonb_build_object(
      'imageUrl', v_base || v_n || '.jpg', 'position', v_n));
  end loop;

  v_message := null;
  begin
    perform public.publish_daily_darshan(v_target, 'Too many.', v_images);
  exception when others then v_message := sqlerrm;
  end;
  if v_message is null then
    raise exception 'Six pictures were accepted.';
  end if;
  if v_message !~ '5' or v_message ~* '(constraint|violates|null value)' then
    raise exception 'Six pictures were refused unreadably: %', v_message;
  end if;

  -- No pictures at all.
  v_message := null;
  begin
    perform public.publish_daily_darshan(v_target, 'None at all.', '[]'::jsonb);
  exception when others then v_message := sqlerrm;
  end;
  if v_message is null then
    raise exception 'A darshan with no pictures was accepted.';
  end if;
  if v_message !~* 'at least' or v_message ~* '(constraint|violates)' then
    raise exception 'An empty darshan was refused unreadably: %', v_message;
  end if;

  -- Not a list at all.
  v_message := null;
  begin
    perform public.publish_daily_darshan(v_target, 'An object.', '{"imageUrl":"x"}'::jsonb);
  exception when others then v_message := sqlerrm;
  end;
  if v_message is null then
    raise exception 'A jsonb object was accepted where a list was required.';
  end if;

  v_message := null;
  begin
    perform public.publish_daily_darshan(v_target, 'Nothing.', null);
  exception when others then v_message := sqlerrm;
  end;
  if v_message is null then
    raise exception 'A null picture list was accepted.';
  end if;

  -- A photo from somewhere other than the app: a tracking pixel by another
  -- name, fetched by every devotee's phone the moment the Home card renders.
  v_message := null;
  begin
    perform public.publish_daily_darshan(v_target, 'Elsewhere.',
      jsonb_build_array(jsonb_build_object(
        'imageUrl', 'https://tracker.example.com/pixel.png', 'position', 1)));
  exception when others then v_message := sqlerrm;
  end;
  if v_message is null then
    raise exception 'A photo hosted outside the app was accepted.';
  end if;
  if v_message !~* 'through the app' then
    raise exception 'A foreign photo was refused unreadably: %', v_message;
  end if;

  -- A blank photo.
  v_message := null;
  begin
    perform public.publish_daily_darshan(v_target, 'Blank.',
      jsonb_build_array(jsonb_build_object('imageUrl', '   ', 'position', 1)));
  exception when others then v_message := sqlerrm;
  end;
  if v_message is null then
    raise exception 'A picture with no photo was accepted.';
  end if;

  -- Two pictures in the same position: ordering by a position two rows share
  -- is not an ordering.
  v_message := null;
  begin
    perform public.publish_daily_darshan(v_target, 'Both third.',
      jsonb_build_array(
        jsonb_build_object('imageUrl', v_base || 'a.jpg', 'position', 3),
        jsonb_build_object('imageUrl', v_base || 'b.jpg', 'position', 3)));
  exception when others then v_message := sqlerrm;
  end;
  if v_message is null then
    raise exception 'Two pictures were given the same position.';
  end if;
  if v_message !~* 'same position' then
    raise exception 'Duplicate positions were refused unreadably: %', v_message;
  end if;

  -- A day that has not happened. Chicago's tomorrow, not UTC's.
  v_message := null;
  begin
    perform public.publish_daily_darshan(v_today + 1, 'Tomorrow.',
      jsonb_build_array(jsonb_build_object('imageUrl', v_base || 'a.jpg', 'position', 1)));
  exception when others then v_message := sqlerrm;
  end;
  if v_message is null then
    raise exception 'A darshan was posted for a day that has not happened.';
  end if;

  -- A day too long ago.
  v_message := null;
  begin
    perform public.publish_daily_darshan(v_today - 8, 'Last week.',
      jsonb_build_array(jsonb_build_object('imageUrl', v_base || 'a.jpg', 'position', 1)));
  exception when others then v_message := sqlerrm;
  end;
  if v_message is null then
    raise exception 'A darshan was posted for a day eight days ago.';
  end if;

  -- No day at all.
  v_message := null;
  begin
    perform public.publish_daily_darshan(null, 'No day.',
      jsonb_build_array(jsonb_build_object('imageUrl', v_base || 'a.jpg', 'position', 1)));
  exception when others then v_message := sqlerrm;
  end;
  if v_message is null then
    raise exception 'A darshan was posted with no date.';
  end if;

  -- An over-long note, and an over-long credit.
  v_message := null;
  begin
    perform public.publish_daily_darshan(v_target, repeat('a', 2001),
      jsonb_build_array(jsonb_build_object('imageUrl', v_base || 'a.jpg', 'position', 1)));
  exception when others then v_message := sqlerrm;
  end;
  if v_message is null then
    raise exception 'A note longer than the dial allows was accepted.';
  end if;

  v_message := null;
  begin
    perform public.publish_daily_darshan(v_target, 'Long credit.',
      jsonb_build_array(jsonb_build_object(
        'imageUrl', v_base || 'a.jpg', 'dressedBy', repeat('b', 121), 'position', 1)));
  exception when others then v_message := sqlerrm;
  end;
  if v_message is null then
    raise exception 'A "dressed by" credit longer than the dial allows was accepted.';
  end if;
end;
$$;

-- Not one of those attempts left anything behind. A bad fifth picture must not
-- leave a half-published darshan, and a refused post must not leave a row.
reset role;

do $$
begin
  if (select count(*) from public.daily_darshan) <> 3 then
    raise exception 'A refused post left a darshan behind: % rows.',
      (select count(*) from public.daily_darshan);
  end if;
  if (select count(*) from public.daily_darshan_images) <> 9 then
    raise exception 'A refused post left pictures behind: % rows.',
      (select count(*) from public.daily_darshan_images);
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Every signed-in devotee reads it, with the pictures attached and in
--    order; anon reads nothing.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'd0000000-0000-0000-0000-000000000004', true);
set local role authenticated;

do $$
declare
  v_rows integer;
  v_row record;
  v_previous date;
  v_urls text;
  v_positions text;
  v_can_delete boolean;
  v_today date := (now() at time zone 'America/Chicago')::date;
begin
  select count(*)::integer into v_rows from public.list_daily_darshan();
  if v_rows <> 3 then
    raise exception 'A plain devotee sees % darshans rather than 3.', v_rows;
  end if;

  -- Newest day first.
  v_previous := null;
  for v_row in select * from public.list_daily_darshan() loop
    if v_previous is not null and v_row.darshan_on > v_previous then
      raise exception 'The darshans are not ordered newest first.';
    end if;
    v_previous := v_row.darshan_on;
  end loop;

  select * into v_row from public.list_daily_darshan() listed
  where listed.darshan_on = v_today;

  -- Attribution travels with the row so a card can name the poster without a
  -- second lookup.
  if v_row.posted_by_name <> 'Dee Head' then
    raise exception 'The darshan named the poster as %.', v_row.posted_by_name;
  end if;
  if v_row.posted_by_photo_url is not null then
    raise exception 'A poster with no photo was given one.';
  end if;

  -- The pictures came back with the darshan, ordered by position, even though
  -- they were given as 3, 1, 2.
  if jsonb_typeof(v_row.images) <> 'array' then
    raise exception 'The pictures came back as %.', jsonb_typeof(v_row.images);
  end if;
  if jsonb_array_length(v_row.images) <> 3 or v_row.image_count <> 3 then
    raise exception 'The gallery has % pictures and image_count says %.',
      jsonb_array_length(v_row.images), v_row.image_count;
  end if;

  select string_agg(picture ->> 'position', ',') into v_positions
  from jsonb_array_elements(v_row.images) as picture;
  if v_positions <> '1,2,3' then
    raise exception 'The gallery came back in position order %.', v_positions;
  end if;

  select string_agg(regexp_replace(picture ->> 'imageUrl', '^.*/', ''), ',') into v_urls
  from jsonb_array_elements(v_row.images) as picture;
  if v_urls <> 'one.jpg,two.jpg,three.jpg' then
    raise exception 'The gallery came back as %.', v_urls;
  end if;

  -- Who dressed which Deity is on the picture, not on the post.
  if (v_row.images -> 0 ->> 'deity') <> 'Sri Sri Radha Govinda'
     or (v_row.images -> 0 ->> 'dressedBy') <> 'Mataji Radhika' then
    raise exception 'The first picture lost its credits: %', v_row.images -> 0;
  end if;
  if (v_row.images -> 1 ->> 'dressedBy') is not null then
    raise exception 'A picture with no "dressed by" was given one.';
  end if;

  -- A plain devotee may delete nothing, and the row says so.
  select bool_or(listed.can_delete) into v_can_delete from public.list_daily_darshan() listed;
  if v_can_delete then
    raise exception 'A plain devotee was told they could delete a darshan.';
  end if;

  -- The Home card is the first row of the list and nothing else.
  select count(*)::integer into v_rows from public.latest_daily_darshan();
  if v_rows <> 1 then
    raise exception 'The Home card returned % rows.', v_rows;
  end if;
  select * into v_row from public.latest_daily_darshan();
  if v_row.darshan_on <> v_today then
    raise exception 'The Home card shows % rather than today.', v_row.darshan_on;
  end if;
  if jsonb_array_length(v_row.images) <> 3 then
    raise exception 'The Home card came without its gallery.';
  end if;

  -- p_limit is honoured.
  select count(*)::integer into v_rows from public.list_daily_darshan(1);
  if v_rows <> 1 then
    raise exception 'list_daily_darshan(1) returned % rows.', v_rows;
  end if;
  select count(*)::integer into v_rows from public.list_daily_darshan(2);
  if v_rows <> 2 then
    raise exception 'list_daily_darshan(2) returned % rows.', v_rows;
  end if;
end;
$$;

-- The volunteer — not a plain devotee, and not one of the three either — sees
-- the same darshans and the same empty set of buttons.
reset role;
select set_config('request.jwt.claim.sub', 'd0000000-0000-0000-0000-000000000005', true);
set local role authenticated;

do $$
declare
  v_rows integer;
  v_can_delete boolean;
begin
  select count(*)::integer, coalesce(bool_or(listed.can_delete), false)
    into v_rows, v_can_delete
  from public.list_daily_darshan() listed;
  if v_rows <> 3 then
    raise exception 'A volunteer sees % darshans rather than 3.', v_rows;
  end if;
  if v_can_delete then
    raise exception 'A volunteer was told they could delete a darshan.';
  end if;
end;
$$;

-- The Community Head sees the same three and may take any of them down.
reset role;
select set_config('request.jwt.claim.sub', 'd0000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_deletable integer;
begin
  select count(*)::integer into v_deletable
  from public.list_daily_darshan() listed where listed.can_delete;
  if v_deletable <> 3 then
    raise exception 'A Community Head may delete only % of the 3 darshans.', v_deletable;
  end if;
end;
$$;

-- Anon reads nothing and posts nothing. This is a congregation's app, not a
-- public gallery: a devotee named as having dressed the Deities has not agreed
-- to appear on the open internet.
reset role;
select set_config('request.jwt.claim.sub', '', true);
set local role anon;

do $$
declare
  v_refused boolean;
begin
  v_refused := false;
  begin
    perform public.list_daily_darshan();
  exception when others then v_refused := true;
  end;
  if not v_refused then
    raise exception 'Anon listed the Daily Darshan.';
  end if;

  v_refused := false;
  begin
    perform public.latest_daily_darshan();
  exception when others then v_refused := true;
  end;
  if not v_refused then
    raise exception 'Anon read the Home card.';
  end if;

  v_refused := false;
  begin
    perform 1 from public.daily_darshan;
  exception when others then v_refused := true;
  end;
  if not v_refused then
    raise exception 'Anon read the darshan table directly.';
  end if;

  v_refused := false;
  begin
    perform 1 from public.daily_darshan_images;
  exception when others then v_refused := true;
  end;
  if not v_refused then
    raise exception 'Anon read the darshan pictures directly.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. A darshan with no pictures comes back as [] and never as null.
--
--    Section 4 makes this impossible to create through the RPC, but a
--    hand-written row could still produce it, and a client that has to write
--    `(images ?? []).map(...)` will one day forget the `?? []`. Inserted
--    straight into the table because there is no other way to make one.
-- ---------------------------------------------------------------------------

reset role;

do $$
declare
  v_id uuid;
begin
  insert into public.daily_darshan (darshan_on, note, posted_by)
  values ((now() at time zone 'America/Chicago')::date - 3, 'No pictures.',
          'd0000000-0000-0000-0000-000000000002')
  returning daily_darshan.id into v_id;
  insert into public.darshan_test_ids values ('empty', v_id);
end;
$$;

select set_config('request.jwt.claim.sub', 'd0000000-0000-0000-0000-000000000004', true);
set local role authenticated;

do $$
declare
  v_row record;
begin
  select * into v_row from public.list_daily_darshan() listed
  where listed.note = 'No pictures.';
  if v_row.images is null then
    raise exception 'A darshan with no pictures came back with a null gallery.';
  end if;
  if v_row.images <> '[]'::jsonb then
    raise exception 'An empty gallery came back as %.', v_row.images;
  end if;
  if v_row.image_count <> 0 then
    raise exception 'An empty gallery reported % pictures.', v_row.image_count;
  end if;
end;
$$;

reset role;
delete from public.daily_darshan
where daily_darshan.id = (select ids.id from public.darshan_test_ids ids where ids.key = 'empty');
delete from public.darshan_test_ids where darshan_test_ids.key = 'empty';

-- ---------------------------------------------------------------------------
-- 7. The congregation was told — once per post, never once per picture, and
--    everybody except the poster.
-- ---------------------------------------------------------------------------

do $$
declare
  v_told integer;
  v_expected integer;
  v_posted integer;
  v_body text;
  v_person record;
  v_today_id uuid;
begin
  select ids.id into v_today_id from public.darshan_test_ids ids where ids.key = 'today';

  -- Three darshans went up through the RPC, and each reached the other four
  -- people: twelve rows. The first of them carried three pictures, so a
  -- notification per picture would read fourteen here.
  select count(*)::integer into v_told
  from public.app_notifications where app_notifications.kind = 'darshan_posted';
  if v_told <> 12 then
    raise exception '% darshan notifications were queued rather than 12.', v_told;
  end if;

  -- One post, one notification each, whatever the gallery held.
  select count(*)::integer into v_told
  from public.app_notifications
  where app_notifications.kind = 'darshan_posted'
    and app_notifications.data ->> 'darshanId' = v_today_id::text;
  if v_told <> 4 then
    raise exception
      'A three-picture darshan produced % notifications rather than one per devotee.', v_told;
  end if;

  -- Not "most devotees": every one of them, individually, for every darshan
  -- they did not put up themselves.
  for v_person in
    select users.id, users.name from public.users where users.email like 'dd-%@example.test'
  loop
    select count(*)::integer into v_posted
    from public.daily_darshan where daily_darshan.posted_by = v_person.id;
    v_expected := 3 - v_posted;

    select count(*)::integer into v_told
    from public.app_notifications
    where app_notifications.user_id = v_person.id
      and app_notifications.kind = 'darshan_posted';
    if v_told <> v_expected then
      raise exception '% was told about % of the % darshans they did not post.',
        v_person.name, v_told, v_expected;
    end if;
  end loop;

  -- The poster is not told about their own; they are looking at the pictures.
  select count(*)::integer into v_told
  from public.app_notifications
  where app_notifications.user_id = 'd0000000-0000-0000-0000-000000000002'
    and app_notifications.kind = 'darshan_posted'
    and app_notifications.data ->> 'darshanId' = v_today_id::text;
  if v_told <> 0 then
    raise exception 'The poster was pushed their own darshan.';
  end if;

  select app_notifications.title || ' / ' || app_notifications.body into v_body
  from public.app_notifications
  where app_notifications.user_id = 'd0000000-0000-0000-0000-000000000004'
    and app_notifications.kind = 'darshan_posted'
    and app_notifications.data ->> 'darshanId' = v_today_id::text;
  -- 202608290079 made the Deities the subject, so the title is Their names and
  -- one of the five sentence shapes carries no such word as "darshan" at all.
  -- Asserting the literal word therefore passed on four days in five and failed
  -- on the fifth. What must keep being true is that the notice NAMES the
  -- Deities whose pictures were posted, so that is what is checked; the five
  -- shapes themselves are proved verbatim in darshan_week_and_voice.sql.
  if not exists (
    select 1
    from public.daily_darshan_images img
    join public.daily_darshan darshan on darshan.id = img.darshan_id
    where darshan.id = v_today_id
      and nullif(trim(coalesce(img.deity, '')), '') is not null
      and v_body like '%' || trim(img.deity) || '%'
  ) then
    raise exception
      'The notification names none of the Deities in the darshan it is about: %', v_body;
  end if;
  -- 202608290079 rewrote this voice. The temple asked for "nothing like 'xyz
  -- posted'", so the poster's name must NOT be here -- the assertion is
  -- inverted rather than deleted, because "the poster is never named" is the
  -- thing that now has to keep being true. The wording itself is proved in
  -- darshan_week_and_voice.sql.
  if v_body ~ 'Dee Head' then
    raise exception 'The notification names who posted it: %', v_body;
  end if;

  -- The payload carries what a deep link needs.
  if not exists (
    select 1 from public.app_notifications
    where app_notifications.kind = 'darshan_posted'
      and app_notifications.data ->> 'darshanId' = v_today_id::text
      and (app_notifications.data ->> 'darshanOn')::date
          = (now() at time zone 'America/Chicago')::date
  ) then
    raise exception 'The notification payload does not carry the darshan and its day.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. Posting again on a day that already has a darshan REPLACES it.
--
--    The same row, the new pictures, the old picture rows gone rather than
--    orphaned, the attribution moved to whoever posted what is now on the
--    screen — and not one further notification, because "there is a darshan
--    for today" does not become true a second time.
-- ---------------------------------------------------------------------------

-- now() is the transaction timestamp, and this whole script is one
-- transaction, so a freshly written updated_at is indistinguishable from
-- created_at here. Backdating it first makes the re-stamp visible.
update public.daily_darshan
set updated_at = timestamptz '2000-01-01 00:00+00'
where daily_darshan.darshan_on = (now() at time zone 'America/Chicago')::date;

select set_config('request.jwt.claim.sub', 'd0000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
  v_first uuid;
  v_again uuid;
  v_today date := (now() at time zone 'America/Chicago')::date;
  v_base text := 'https://project.supabase.co/storage/v1/object/public/message-images/'
    || 'd0000000-0000-0000-0000-000000000001/';
begin
  select ids.id into v_first from public.darshan_test_ids ids where ids.key = 'today';

  v_again := public.publish_daily_darshan(
    v_today, 'Photo three was blurred; here are two better ones.',
    jsonb_build_array(
      jsonb_build_object('imageUrl', v_base || 'fixed-one.jpg',
        'deity', 'Sri Sri Radha Govinda', 'dressedBy', 'Mataji Radhika', 'position', 1),
      jsonb_build_object('imageUrl', v_base || 'fixed-two.jpg',
        'deity', 'Sri Jagannath', 'dressedBy', 'Prabhu Gopal', 'position', 2))
  );

  -- The SAME row. A delete-and-reinsert would leave every phone that was
  -- notified this morning holding a dead link.
  if v_again <> v_first then
    raise exception 'Re-posting today made a second darshan (% then %).', v_first, v_again;
  end if;
end;
$$;

reset role;

do $$
declare
  v_id uuid;
  v_row public.daily_darshan;
  v_today date := (now() at time zone 'America/Chicago')::date;
  v_orphans integer;
  v_told integer;
begin
  select ids.id into v_id from public.darshan_test_ids ids where ids.key = 'today';

  -- One darshan for the day, still.
  if (select count(*) from public.daily_darshan
      where daily_darshan.darshan_on = v_today) <> 1 then
    raise exception 'Today has % darshans.',
      (select count(*) from public.daily_darshan where daily_darshan.darshan_on = v_today);
  end if;

  select * into v_row from public.daily_darshan where daily_darshan.id = v_id;
  if v_row.note !~ 'blurred' then
    raise exception 'The replacement note did not take: %', v_row.note;
  end if;
  -- The attribution moved with the pictures.
  if v_row.posted_by <> 'd0000000-0000-0000-0000-000000000001' then
    raise exception 'Re-posting did not move the attribution to the devotee who posted.';
  end if;
  if v_row.updated_at <= timestamptz '2000-01-01 00:00+00' then
    raise exception 'Re-posting did not touch updated_at.';
  end if;

  -- The old pictures are gone, not orphaned, and the new ones are there.
  if (select count(*) from public.daily_darshan_images
      where daily_darshan_images.darshan_id = v_id) <> 2 then
    raise exception 'The replaced gallery holds % pictures rather than 2.',
      (select count(*) from public.daily_darshan_images
       where daily_darshan_images.darshan_id = v_id);
  end if;
  if exists (
    select 1 from public.daily_darshan_images
    where daily_darshan_images.image_url like '%/three.jpg'
  ) then
    raise exception 'A replaced picture is still in the table.';
  end if;

  select count(*)::integer into v_orphans
  from public.daily_darshan_images img
  left join public.daily_darshan darshan on darshan.id = img.darshan_id
  where darshan.id is null;
  if v_orphans <> 0 then
    raise exception 'Re-posting orphaned % picture rows.', v_orphans;
  end if;

  -- And nobody was told twice.
  select count(*)::integer into v_told
  from public.app_notifications where app_notifications.kind = 'darshan_posted';
  if v_told <> 12 then
    raise exception
      'Re-posting the same day notified the congregation again: % rows rather than 12.', v_told;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 9. Taking a darshan down.
-- ---------------------------------------------------------------------------

-- A plain devotee cannot.
select set_config('request.jwt.claim.sub', 'd0000000-0000-0000-0000-000000000004', true);
set local role authenticated;

do $$
declare
  v_refused boolean := false;
  v_target uuid;
begin
  select ids.id into v_target from public.darshan_test_ids ids where ids.key = 'today';
  begin
    perform public.delete_daily_darshan(v_target);
  exception when others then v_refused := true;
  end;
  if not v_refused then
    raise exception 'A plain devotee deleted a darshan.';
  end if;

  -- And the row is genuinely still there, not merely reported as refused.
  if not exists (
    select 1 from public.list_daily_darshan() listed where listed.id = v_target
  ) then
    raise exception 'The darshan a devotee could not delete is gone anyway.';
  end if;
end;
$$;

-- The poster takes their own down, and the picture rows go with it.
reset role;
select set_config('request.jwt.claim.sub', 'd0000000-0000-0000-0000-000000000003', true);
set local role authenticated;

do $$
declare
  v_removed public.daily_darshan;
  v_refused boolean := false;
  v_target uuid;
begin
  select ids.id into v_target from public.darshan_test_ids ids where ids.key = 'two_days_ago';

  if (select count(*) from public.daily_darshan_images
      where daily_darshan_images.darshan_id = v_target) <> 5 then
    raise exception 'The darshan about to be deleted does not have its five pictures.';
  end if;

  v_removed := public.delete_daily_darshan(v_target);
  if v_removed.id <> v_target then
    raise exception 'Deleting a darshan did not return the row removed.';
  end if;
  if exists (select 1 from public.list_daily_darshan() listed where listed.id = v_target) then
    raise exception 'A deleted darshan is still on the list.';
  end if;

  -- Twice is a mistake, not a licence.
  begin
    perform public.delete_daily_darshan(v_target);
  exception when others then v_refused := true;
  end;
  if not v_refused then
    raise exception 'Deleting the same darshan twice was accepted.';
  end if;
end;
$$;

-- A Community Head takes down a darshan the President put up.
reset role;
select set_config('request.jwt.claim.sub', 'd0000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_target uuid;
begin
  select ids.id into v_target from public.darshan_test_ids ids where ids.key = 'yesterday';
  perform public.delete_daily_darshan(v_target);
  if exists (select 1 from public.list_daily_darshan() listed where listed.id = v_target) then
    raise exception 'A Community Head could not remove another devotee''s darshan.';
  end if;
end;
$$;

reset role;

do $$
declare
  v_target uuid;
begin
  select ids.id into v_target from public.darshan_test_ids ids where ids.key = 'two_days_ago';

  -- The picture rows cascaded.
  if exists (
    select 1 from public.daily_darshan_images
    where daily_darshan_images.darshan_id = v_target
  ) then
    raise exception 'Deleting a darshan left its picture rows behind.';
  end if;

  if (select count(*) from public.daily_darshan_images img
      left join public.daily_darshan darshan on darshan.id = img.darshan_id
      where darshan.id is null) <> 0 then
    raise exception 'Deleting a darshan orphaned picture rows.';
  end if;

  -- The files stay in the bucket, which is the documented decision: nothing in
  -- this codebase deletes storage objects from SQL, and the bucket is shared
  -- with direct messages.
  if not exists (select 1 from storage.buckets where storage.buckets.id = 'message-images') then
    raise exception 'The message-images bucket is missing.';
  end if;
  if exists (select 1 from storage.buckets where storage.buckets.id ilike '%darshan%') then
    raise exception 'A second bucket was made for darshan pictures.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 10. Neither table is a back door.
--
--     Every write goes through an RPC, so a devotee's own rights must carry no
--     insert, update or delete however they phrase the statement.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'd0000000-0000-0000-0000-000000000004', true);
set local role authenticated;

do $$
declare
  v_refused boolean;
  v_today date := (now() at time zone 'America/Chicago')::date;
begin
  v_refused := false;
  begin
    insert into public.daily_darshan (darshan_on, note, posted_by)
    values (v_today - 4, 'Straight into the table.',
            'd0000000-0000-0000-0000-000000000004');
  exception when others then v_refused := true;
  end;
  if not v_refused then
    raise exception 'A devotee wrote straight into the daily_darshan table.';
  end if;

  v_refused := false;
  begin
    update public.daily_darshan set note = 'Rewritten';
  exception when others then v_refused := true;
  end;
  if not v_refused then
    raise exception 'A devotee rewrote the daily_darshan table.';
  end if;

  v_refused := false;
  begin
    delete from public.daily_darshan;
  exception when others then v_refused := true;
  end;
  if not v_refused then
    raise exception 'A devotee deleted straight from the daily_darshan table.';
  end if;

  v_refused := false;
  begin
    insert into public.daily_darshan_images (darshan_id, image_url, "position")
    values ((select ids.id from public.darshan_test_ids ids where ids.key = 'today'),
            'https://tracker.example.com/pixel.png', 9);
  exception when others then v_refused := true;
  end;
  if not v_refused then
    raise exception 'A devotee added a picture straight into the table.';
  end if;

  v_refused := false;
  begin
    delete from public.daily_darshan_images;
  exception when others then v_refused := true;
  end;
  if not v_refused then
    raise exception 'A devotee deleted pictures straight from the table.';
  end if;

  -- The dials are not readable by a devotee either.
  v_refused := false;
  begin
    perform 1 from public.app_settings where app_settings.key like 'daily_darshan.%';
  exception when others then v_refused := true;
  end;
  if not v_refused then
    raise exception 'A devotee can read app_settings.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 11. Every guard, mutated.
--
--     Each row below breaks exactly one thing 0078 relies on and re-reads one
--     answer through the real function. A guard whose mutation changes nothing
--     is a guard that was not doing anything, and the table says so out loud.
--     The harness is 202608260076 §14's, unchanged.
--
--     Both readings roll back whatever they would have written — dd_probe runs
--     its statement inside a subtransaction and then raises — so a probe that
--     notifies the congregation does not leave the congregation notified, and
--     the same question can honestly be asked twice. The probe is read a third
--     time after the mutation is undone and must match the first, or the
--     harness itself is lying.
-- ---------------------------------------------------------------------------

reset role;

-- The fixture is rebuilt, because sections 8 and 9 have been moving it about.
-- Two darshans, both the Head's, and today deliberately left free so that a
-- probe which publishes takes the insert path and therefore notifies.
delete from public.daily_darshan;
delete from public.app_notifications;

select set_config('request.jwt.claim.sub', 'd0000000-0000-0000-0000-000000000002', true);

do $$
declare
  v_today date := (now() at time zone 'America/Chicago')::date;
  v_base text := 'https://project.supabase.co/storage/v1/object/public/message-images/'
    || 'd0000000-0000-0000-0000-000000000002/';
begin
  perform public.publish_daily_darshan(v_today - 1, 'Yesterday.',
    jsonb_build_array(
      jsonb_build_object('imageUrl', v_base || 'y1.jpg', 'position', 1),
      jsonb_build_object('imageUrl', v_base || 'y2.jpg', 'position', 2)));
  perform public.publish_daily_darshan(v_today - 2, 'The day before.',
    jsonb_build_array(jsonb_build_object('imageUrl', v_base || 'b1.jpg', 'position', 1)));
end;
$$;

delete from public.app_notifications;

create table dd_mutations (
  n integer primary key,
  guard text not null,
  mutation text not null,
  probe text not null,
  intact text not null,
  mutated text not null,
  killed boolean not null
);

create function pg_temp.dd_probe(p_sql text)
returns text
language plpgsql
as $$
declare
  v_answer text;
begin
  begin
    execute p_sql into v_answer;
    raise exception using errcode = 'PT780', message = coalesce(v_answer, '(null)');
  exception when sqlstate 'PT780' then
    return sqlerrm;
  end;
end;
$$;

create function pg_temp.dd_try_publish(p_on date, p_note text, p_images jsonb)
returns text
language plpgsql
as $$
begin
  perform public.publish_daily_darshan(p_on, p_note, p_images);
  return 'accepted';
exception when others then
  return 'refused';
end;
$$;

create function pg_temp.dd_try_direct(p_sql text)
returns text
language plpgsql
as $$
begin
  execute p_sql;
  return 'accepted';
exception when others then
  return 'refused';
end;
$$;

create function pg_temp.dd_try_delete(p_id uuid)
returns text
language plpgsql
as $$
begin
  perform public.delete_daily_darshan(p_id);
  return 'deleted';
exception when others then
  return 'refused';
end;
$$;

-- Removing the devotee who posted, and counting what survives. The whole thing
-- happens inside dd_probe's subtransaction and is rolled back.
create function pg_temp.dd_orphan(p_user uuid)
returns text
language plpgsql
as $$
declare
  v_count integer;
begin
  delete from public.users where users.id = p_user;
  select count(*)::integer into v_count from public.daily_darshan;
  return v_count::text;
exception when others then
  return 'blocked';
end;
$$;

create function pg_temp.dd_mutate(
  p_n integer, p_guard text, p_mutation text, p_probe text,
  p_apply text[], p_query text
)
returns void
language plpgsql
as $$
declare
  v_intact text;
  v_mutated text;
  v_restored text;
  v_statement text;
begin
  v_intact := pg_temp.dd_probe(p_query);

  begin
    foreach v_statement in array p_apply loop
      execute v_statement;
    end loop;
    v_mutated := pg_temp.dd_probe(p_query);
    raise exception using errcode = 'PT781', message = v_mutated;
  exception when sqlstate 'PT781' then
    v_mutated := sqlerrm;
  end;

  v_restored := pg_temp.dd_probe(p_query);
  if v_restored is distinct from v_intact then
    raise exception 'Mutation % did not roll back: the probe read % before and % after.',
      p_n, v_intact, v_restored;
  end if;

  insert into dd_mutations (n, guard, mutation, probe, intact, mutated, killed)
  values (p_n, p_guard, p_mutation, p_probe, v_intact, v_mutated,
          v_mutated is distinct from v_intact);
end;
$$;

do $$
declare
  v_today date := (now() at time zone 'America/Chicago')::date;
  v_base text := 'https://project.supabase.co/storage/v1/object/public/message-images/'
    || 'd0000000-0000-0000-0000-000000000002/';
  v_three jsonb := jsonb_build_array(
    jsonb_build_object('imageUrl', v_base || 'm1.jpg', 'position', 1),
    jsonb_build_object('imageUrl', v_base || 'm2.jpg', 'deity', 'Sri Sri Radha Govinda',
      'dressedBy', 'Bhaktin Anjali', 'position', 2),
    jsonb_build_object('imageUrl', v_base || 'm3.jpg', 'position', 3));
  v_one jsonb := jsonb_build_array(
    jsonb_build_object('imageUrl', v_base || 'm1.jpg', 'position', 1));
  v_publish_three text;
  v_publish_one text;
  v_yesterday uuid;
begin
  select daily_darshan.id into v_yesterday
  from public.daily_darshan where daily_darshan.darshan_on = v_today - 1;

  v_publish_three := format(
    'select pg_temp.dd_try_publish(%L, %L, %L::jsonb)', v_today, 'A probe.', v_three::text);
  v_publish_one := format(
    'select pg_temp.dd_try_publish(%L, %L, %L::jsonb)', v_today, 'A probe.', v_one::text);

  perform pg_temp.dd_mutate(
    1,
    'at most max_images pictures, server-side',
    'max_images dialled from 5 down to 2',
    'publishing a three-picture darshan',
    array[format('update public.app_settings set value = %L where key = %L',
                 '2', 'daily_darshan.max_images')],
    v_publish_three);

  perform pg_temp.dd_mutate(
    2,
    'at least min_images pictures, server-side',
    'min_images dialled from 1 down to 0',
    'publishing a darshan with an empty picture list',
    array[format('update public.app_settings set value = %L where key = %L',
                 '0', 'daily_darshan.min_images')],
    format('select pg_temp.dd_try_publish(%L, %L, %L::jsonb)', v_today, 'A probe.', '[]'));

  perform pg_temp.dd_mutate(
    3,
    'the note is no longer than max_note_chars',
    'max_note_chars dialled from 2000 down to 3',
    'publishing with an eight-character note',
    array[format('update public.app_settings set value = %L where key = %L',
                 '3', 'daily_darshan.max_note_chars')],
    format('select pg_temp.dd_try_publish(%L, %L, %L::jsonb)',
           v_today, 'A probe.', v_one::text));

  perform pg_temp.dd_mutate(
    4,
    'a "dressed by" credit is no longer than max_credit_chars',
    'max_credit_chars dialled from 120 down to 3',
    'publishing a picture credited to Bhaktin Anjali',
    array[format('update public.app_settings set value = %L where key = %L',
                 '3', 'daily_darshan.max_credit_chars')],
    v_publish_three);

  perform pg_temp.dd_mutate(
    5,
    'a darshan is for a day within max_backdate_days',
    'max_backdate_days dialled from 7 down to 0',
    'publishing for yesterday in Chicago',
    array[format('update public.app_settings set value = %L where key = %L',
                 '0', 'daily_darshan.max_backdate_days')],
    format('select pg_temp.dd_try_publish(%L, %L, %L::jsonb)',
           v_today - 1, 'A probe.', v_one::text));

  perform pg_temp.dd_mutate(
    6,
    'one request pulls at most list_limit_max darshans',
    'list_limit_max dialled from 100 down to 1',
    'rows returned by list_daily_darshan(30)',
    array[format('update public.app_settings set value = %L where key = %L',
                 '1', 'daily_darshan.list_limit_max')],
    'select count(*)::text from public.list_daily_darshan(30)');

  perform pg_temp.dd_mutate(
    7,
    'only a holder of services.manage_recurring may post',
    'services.manage_recurring taken from the Community Head',
    'the Community Head publishing today''s darshan',
    array['delete from public.role_permissions where permission_key = ''services.manage_recurring'''
          || ' and role_id = (select roles.id from public.roles where roles.name = ''core'')'],
    v_publish_three);

  perform pg_temp.dd_mutate(
    8,
    'one darshan per day, promised by the database',
    'the unique index on darshan_on dropped',
    'a second row written straight into the table for yesterday',
    array['drop index public.daily_darshan_on_key'],
    format('select pg_temp.dd_try_direct(%L)',
           format('insert into public.daily_darshan (darshan_on, note) values (%L, %L)',
                  v_today - 1, 'A second one.')));

  perform pg_temp.dd_mutate(
    9,
    'two pictures cannot share a position',
    'the unique index on (darshan_id, position) dropped',
    'a duplicate position written straight into the table',
    array['drop index public.daily_darshan_images_position_key'],
    format('select pg_temp.dd_try_direct(%L)',
           format('insert into public.daily_darshan_images '
                  || '(darshan_id, image_url, "position") values (%L, %L, 1)',
                  v_yesterday, v_base || 'clash.jpg')));

  perform pg_temp.dd_mutate(
    10,
    'a picture is never blank',
    'daily_darshan_image_url_not_blank dropped',
    'a blank image_url written straight into the table',
    array['alter table public.daily_darshan_images '
          || 'drop constraint daily_darshan_image_url_not_blank'],
    format('select pg_temp.dd_try_direct(%L)',
           format('insert into public.daily_darshan_images '
                  || '(darshan_id, image_url, "position") values (%L, ''   '', 9)',
                  v_yesterday)));

  perform pg_temp.dd_mutate(
    11,
    'the pictures go when their darshan goes',
    'the images foreign key changed from cascade to no action',
    'deleting a darshan that still has pictures',
    array['alter table public.daily_darshan_images '
          || 'drop constraint daily_darshan_images_darshan_id_fkey',
          'alter table public.daily_darshan_images '
          || 'add constraint daily_darshan_images_darshan_id_fkey '
          || 'foreign key (darshan_id) references public.daily_darshan(id)'],
    format('select pg_temp.dd_try_delete(%L)', v_yesterday));

  perform pg_temp.dd_mutate(
    12,
    'the darshan survives its poster leaving the congregation',
    'posted_by changed from on delete set null to on delete cascade',
    'darshans left standing after the poster''s account is removed',
    array['alter table public.daily_darshan drop constraint daily_darshan_posted_by_fkey',
          'alter table public.daily_darshan add constraint daily_darshan_posted_by_fkey '
          || 'foreign key (posted_by) references public.users(id) on delete cascade'],
    format('select pg_temp.dd_orphan(%L)', 'd0000000-0000-0000-0000-000000000002'));

  perform pg_temp.dd_mutate(
    13,
    'darshan_posted is a notification kind the congregation can be sent',
    'darshan_posted removed from app_notifications_kind_check',
    'publishing today''s darshan, which notifies four devotees',
    array['alter table public.app_notifications drop constraint app_notifications_kind_check',
          'alter table public.app_notifications add constraint app_notifications_kind_check '
          || 'check (kind <> ''darshan_posted'')'],
    v_publish_three);
end;
$$;

do $$
declare
  v_survivors text;
  v_count integer;
begin
  select count(*)::integer into v_count from dd_mutations;
  if v_count <> 13 then
    raise exception 'Only % mutations ran.', v_count;
  end if;

  select string_agg(dd_mutations.n || ': ' || dd_mutations.guard, E'\n  ')
  into v_survivors
  from dd_mutations where not dd_mutations.killed;

  if v_survivors is not null then
    raise exception E'These guards survived being broken:\n  %', v_survivors;
  end if;

  -- The probes did not leave the fixture published or notified.
  if (select count(*) from public.app_notifications) <> 0 then
    raise exception 'A mutation probe left the congregation notified; the harness is lying.';
  end if;
  if (select count(*) from public.daily_darshan) <> 2 then
    raise exception 'A mutation probe left a darshan behind; the harness is lying.';
  end if;
end;
$$;

select
  dd_mutations.n,
  dd_mutations.guard,
  dd_mutations.mutation,
  dd_mutations.probe,
  dd_mutations.intact,
  dd_mutations.mutated,
  case when dd_mutations.killed then 'killed' else 'SURVIVED' end as verdict
from dd_mutations
order by dd_mutations.n;

do $$
begin
  raise notice 'all daily darshan checks passed';
end;
$$;

select 'daily darshan verification passed' as result;

rollback;
