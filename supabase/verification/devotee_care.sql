-- Functional verification for 202608040042_devotee_care.sql.
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
--   President  ...0001  one of the three who may remove anybody's words
--   Head       ...0002  Community Head; does the moderating checked here
--   Asha       ...0003  plain devotee; asks for help, and owns the thread
--   Bhakta     ...0004  plain devotee; replies to Asha
--   Chandra    ...0005  plain devotee; replies too, and must be refused when
--                       they reach for somebody else's post
--
-- The claim this script exists to defend is the quiet one. A care board that
-- pushes to the congregation is a care board every devotee mutes, taking the
-- temple's announcements with it. So the notification assertions are not "the
-- author was told" — they are "the author was told and the count across every
-- single user in the database is exactly what it should be", which is the only
-- form of the assertion that fails when somebody adds a well-meaning loop.
--
-- The final row must read: devotee care verification passed

begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('c0000000-0000-0000-0000-000000000001', 'care-president@example.test', '{"name":"Care President"}'),
  ('c0000000-0000-0000-0000-000000000002', 'care-head@example.test', '{"name":"Care Head"}'),
  ('c0000000-0000-0000-0000-000000000003', 'care-asha@example.test', '{"name":"Asha Devi"}'),
  ('c0000000-0000-0000-0000-000000000004', 'care-bhakta@example.test', '{"name":"Bhakta Das"}'),
  ('c0000000-0000-0000-0000-000000000005', 'care-chandra@example.test', '{"name":"Chandra Devi"}');

update public.users
set role_id = (select roles.id from public.roles where roles.name = 'president')
where email = 'care-president@example.test';

update public.users
set role_id = (select roles.id from public.roles where roles.name = 'core')
where email = 'care-head@example.test';

-- Asha, Bhakta and Chandra keep the role the signup trigger gave them, which
-- is the whole point: a plain devotee must be able to post and to reply.
do $$
declare
  v_role text;
  v_person text;
begin
  for v_person in
    select users.email from public.users
    where users.email in ('care-asha@example.test', 'care-bhakta@example.test',
                          'care-chandra@example.test')
  loop
    select roles.name into v_role
    from public.users join public.roles on roles.id = users.role_id
    where users.email = v_person;
    if v_role <> 'devotee' then
      raise exception '% starts as a % rather than a plain devotee.', v_person, v_role;
    end if;
  end loop;
end;
$$;

-- Ordinary table rather than a temporary one, so reading it under the
-- authenticated role needs no assumptions about the temp schema. The whole
-- script is rolled back, so it never outlives the transaction.
create table public.care_test_ids (key text primary key, id uuid not null);
grant select, insert on public.care_test_ids to authenticated;

-- Everything queued before the feature is touched. Section 5 subtracts this,
-- so the signup notifications the triggers fire above cannot be mistaken for
-- something the care board sent.
create table public.care_test_baseline as
select count(*)::integer as notifications from public.app_notifications;

-- ---------------------------------------------------------------------------
-- 0. The permission being relied on is the one the temple already uses for
--    "Community Head, Tech Admin, President", and no fourth role has it.
--
--    If a later migration widens services.manage_recurring, moderation widens
--    with it silently. That is worth failing loudly over here.
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
      'services.manage_recurring is held by % — devotee care assumes core, president, tech.',
      v_holders;
  end if;

  -- No new permission key was invented for this feature.
  if exists (
    select 1 from public.role_permissions
    where role_permissions.permission_key like '%care%'
  ) then
    raise exception 'A separate care permission key was registered.';
  end if;
end;
$$;

-- Row level security is actually on, on both tables. Everything below is
-- meaningless if it is not.
do $$
declare
  v_table text;
begin
  foreach v_table in array array['care_posts', 'care_replies'] loop
    if not exists (
      select 1 from pg_class
      join pg_namespace on pg_namespace.oid = pg_class.relnamespace
      where pg_namespace.nspname = 'public'
        and pg_class.relname = v_table
        and pg_class.relrowsecurity
    ) then
      raise exception 'Row level security is not enabled on public.%.', v_table;
    end if;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- 1. Any devotee can ask for help. No role, no permission, no approval.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'c0000000-0000-0000-0000-000000000003', true);
set local role authenticated;

do $$
declare
  v_post public.care_posts;
begin
  v_post := public.create_care_post(
    'Lift to the Sunday feast',
    'My car is off the road until Thursday and I live near Devon Avenue. '
      || 'Is anybody driving in on Sunday morning?',
    'https://project.supabase.co/storage/v1/object/public/message-images/'
      || 'c0000000-0000-0000-0000-000000000003/route.jpg'
  );

  if v_post.id is null then
    raise exception 'A plain devotee could not post a request for help.';
  end if;
  if v_post.author_id <> 'c0000000-0000-0000-0000-000000000003' then
    raise exception 'The post did not record who asked.';
  end if;
  if v_post.title <> 'Lift to the Sunday feast' then
    raise exception 'The title came back as %.', v_post.title;
  end if;
  if v_post.image_url is null then
    raise exception 'The photo was dropped.';
  end if;
  if v_post.deleted_at is not null or v_post.deleted_by is not null then
    raise exception 'A brand new post is already marked as removed.';
  end if;

  insert into public.care_test_ids values ('post_asha', v_post.id);
end;
$$;

-- A second plain devotee posts too, so "any devotee" is not one lucky row.
reset role;
select set_config('request.jwt.claim.sub', 'c0000000-0000-0000-0000-000000000005', true);
set local role authenticated;

do $$
declare
  v_post public.care_posts;
begin
  v_post := public.create_care_post(
    'Spare tulsi plant',
    'Mine did not survive the winter. Does anyone have a cutting to share?'
  );
  if v_post.id is null then
    raise exception 'A second plain devotee could not post.';
  end if;
  if v_post.image_url is not null then
    raise exception 'A post with no photo was given one.';
  end if;
  insert into public.care_test_ids values ('post_chandra', v_post.id);
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Blank titles and blank bodies are refused, readably.
--
--    Both halves are asserted: that the refusal happened, and that it came
--    from the guard rather than from the table constraint underneath it. A
--    devotee shown "violates check constraint care_post_title_not_blank" has
--    been told nothing they can act on.
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', 'c0000000-0000-0000-0000-000000000003', true);
set local role authenticated;

do $$
declare
  v_message text;
  v_post uuid;
begin
  v_message := null;
  begin
    perform public.create_care_post('   ', 'A body with no title.');
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
    perform public.create_care_post('A title with no body', '   ');
  exception when others then
    v_message := sqlerrm;
  end;
  if v_message is null then
    raise exception 'A blank body was accepted.';
  end if;
  if v_message ~* '(constraint|null value|violates)' then
    raise exception 'A blank body was refused unreadably: %', v_message;
  end if;

  -- Blank is not only spaces. The body box in the app is multi-line, so the
  -- easiest way to submit nothing is to press return twice — and plain trim()
  -- strips spaces alone, so a newline-only body sails past a guard written
  -- with it and lands on the board as an empty request.
  v_message := null;
  begin
    perform public.create_care_post('A title with no body', e'\n\t \r\n');
  exception when others then
    v_message := sqlerrm;
  end;
  if v_message is null then
    raise exception 'A body of nothing but newlines and tabs was accepted.';
  end if;
  if v_message ~* '(constraint|null value|violates)' then
    raise exception 'A whitespace-only body was refused unreadably: %', v_message;
  end if;

  v_message := null;
  begin
    perform public.create_care_post(e'\n \t', 'A body with a whitespace title.');
  exception when others then
    v_message := sqlerrm;
  end;
  if v_message is null then
    raise exception 'A title of nothing but newlines and tabs was accepted.';
  end if;
  if v_message !~* 'title' then
    raise exception 'A whitespace-only title was refused unreadably: %', v_message;
  end if;

  -- Null is the same as blank as far as a devotee is concerned.
  v_message := null;
  begin
    perform public.create_care_post(null, null);
  exception when others then
    v_message := sqlerrm;
  end;
  if v_message is null then
    raise exception 'A post with no title and no body at all was accepted.';
  end if;

  -- A photo from somewhere other than the app is refused: the column is
  -- otherwise a tracking pixel pointed at every devotee's phone.
  v_message := null;
  begin
    perform public.create_care_post(
      'Elsewhere', 'A photo from another host.',
      'https://tracker.example.com/pixel.png'
    );
  exception when others then
    v_message := sqlerrm;
  end;
  if v_message is null then
    raise exception 'A photo hosted outside the app was accepted.';
  end if;

  -- And a blank reply is refused on the same terms.
  select ids.id into v_post from public.care_test_ids ids where ids.key = 'post_chandra';
  v_message := null;
  begin
    perform public.reply_to_care_post(v_post, e'  \n\t ');
  exception when others then
    v_message := sqlerrm;
  end;
  if v_message is null then
    raise exception 'A blank reply was accepted.';
  end if;
  if v_message !~* 'reply' or v_message ~* '(constraint|null value|violates)' then
    raise exception 'A blank reply was refused unreadably: %', v_message;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Everyone reads everything — the board and, through it, the table.
-- ---------------------------------------------------------------------------

do $$
declare
  v_person record;
  v_titles text;
  v_direct integer;
begin
  for v_person in
    select users.id, users.name from public.users
    where users.email like 'care-%@example.test'
    order by users.email
  loop
    perform set_config('request.jwt.claim.sub', v_person.id::text, true);

    select string_agg(listed.title, ',' order by listed.title) into v_titles
    from public.list_care_posts() listed;
    if v_titles is distinct from 'Lift to the Sunday feast,Spare tulsi plant' then
      raise exception '% sees % on the care board.', v_person.name, v_titles;
    end if;

    -- Straight off the table as well, so the read policy is doing its job and
    -- not merely the definer function.
    select count(*)::integer into v_direct from public.care_posts;
    if v_direct <> 2 then
      raise exception '% reads % care posts straight off the table rather than 2.',
        v_person.name, v_direct;
    end if;
  end loop;
end;
$$;

-- The board carries the author and the reply count so a card needs no second
-- round trip, and it is ordered newest first.
reset role;
select set_config('request.jwt.claim.sub', 'c0000000-0000-0000-0000-000000000004', true);
set local role authenticated;

do $$
declare
  v_row record;
  v_previous timestamptz;
begin
  select * into v_row from public.list_care_posts() listed
  where listed.title = 'Lift to the Sunday feast';
  if v_row.author_name is distinct from 'Asha Devi' then
    raise exception 'The board named the author as %.', v_row.author_name;
  end if;
  if v_row.author_photo_url is not null then
    raise exception 'An author with no photo was given one.';
  end if;
  if v_row.image_url is null then
    raise exception 'The post photo is missing from the board.';
  end if;
  if v_row.reply_count <> 0 then
    raise exception 'An unanswered post shows % replies.', v_row.reply_count;
  end if;
  if v_row.can_remove then
    raise exception 'A plain devotee was told they could remove somebody else''s post.';
  end if;

  v_previous := null;
  for v_row in select * from public.list_care_posts() loop
    if v_previous is not null and v_row.created_at > v_previous then
      raise exception 'The care board is not ordered newest first.';
    end if;
    v_previous := v_row.created_at;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Any devotee replies, and the thread reads oldest first.
-- ---------------------------------------------------------------------------

do $$
declare
  v_post uuid;
  v_reply public.care_replies;
begin
  select ids.id into v_post from public.care_test_ids ids where ids.key = 'post_asha';

  -- Bhakta, a plain devotee, answers somebody else's request.
  v_reply := public.reply_to_care_post(v_post, 'I can drive you. I leave at 8:30.');
  if v_reply.id is null then
    raise exception 'A plain devotee could not reply.';
  end if;
  if v_reply.post_id <> v_post
     or v_reply.author_id <> 'c0000000-0000-0000-0000-000000000004' then
    raise exception 'The reply was not filed against the right post or author.';
  end if;
  insert into public.care_test_ids values ('reply_one', v_reply.id);
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'c0000000-0000-0000-0000-000000000005', true);
set local role authenticated;

do $$
declare
  v_post uuid;
  v_reply public.care_replies;
begin
  select ids.id into v_post from public.care_test_ids ids where ids.key = 'post_asha';
  v_reply := public.reply_to_care_post(v_post, 'So can I, if Bhakta cannot.');
  insert into public.care_test_ids values ('reply_two', v_reply.id);
end;
$$;

-- Asha replies to her own post. This is the case that must notify nobody: she
-- does not need pushing her own words.
reset role;
select set_config('request.jwt.claim.sub', 'c0000000-0000-0000-0000-000000000003', true);
set local role authenticated;

do $$
declare
  v_post uuid;
  v_reply public.care_replies;
begin
  select ids.id into v_post from public.care_test_ids ids where ids.key = 'post_asha';
  v_reply := public.reply_to_care_post(v_post, 'Thank you both, that is a relief.');
  insert into public.care_test_ids values ('reply_three', v_reply.id);
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'c0000000-0000-0000-0000-000000000004', true);
set local role authenticated;

do $$
declare
  v_post uuid;
  v_reply public.care_replies;
  v_row record;
  v_seen text;
  v_previous timestamptz;
begin
  select ids.id into v_post from public.care_test_ids ids where ids.key = 'post_asha';
  v_reply := public.reply_to_care_post(v_post, 'See you at 8:30 on the corner.');
  insert into public.care_test_ids values ('reply_four', v_reply.id);

  -- Oldest first, all four, with the author travelling alongside.
  v_seen := '';
  v_previous := null;
  for v_row in select * from public.list_care_replies(v_post) loop
    v_seen := v_seen || v_row.author_name || '|';
    if v_previous is not null and v_row.created_at < v_previous then
      raise exception 'The thread is not ordered oldest first.';
    end if;
    v_previous := v_row.created_at;
  end loop;
  if v_seen <> 'Bhakta Das|Chandra Devi|Asha Devi|Bhakta Das|' then
    raise exception 'The thread reads %.', v_seen;
  end if;

  -- The board's count follows the thread.
  select * into v_row from public.list_care_posts() listed where listed.id = v_post;
  if v_row.reply_count <> 4 then
    raise exception 'The board shows % replies rather than 4.', v_row.reply_count;
  end if;

  -- A devotee may remove their own reply and nobody else's, and the thread
  -- says so per row rather than making the client work it out.
  if (select count(*) from public.list_care_replies(v_post) listed
      where listed.can_remove) <> 2 then
    raise exception 'Bhakta may remove other than exactly his own two replies.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. The quiet part, asserted across every user in the database.
--
--    Three replies came from somebody other than the author, so Asha has three
--    notifications. Her own reply produced none. Two posts went up and
--    produced none. And the care board queued nothing of any other kind — the
--    baseline captured before any of this subtracts the signup traffic, so
--    what is left is exactly what this feature sent.
-- ---------------------------------------------------------------------------

reset role;

do $$
declare
  v_total integer;
  v_asha integer;
  v_elsewhere integer;
  v_growth integer;
  v_body text;
  v_person record;
begin
  select count(*)::integer into v_total
  from public.app_notifications where kind = 'care_reply';
  if v_total <> 3 then
    raise exception '% care_reply notifications were queued rather than 3.', v_total;
  end if;

  -- Not "mostly Asha": every other user in the database, named or otherwise,
  -- has none at all.
  select count(*)::integer into v_elsewhere
  from public.app_notifications
  where kind = 'care_reply'
    and user_id <> 'c0000000-0000-0000-0000-000000000003';
  if v_elsewhere <> 0 then
    raise exception '% devotees other than the post''s author were notified of a reply.',
      v_elsewhere;
  end if;

  select count(*)::integer into v_asha
  from public.app_notifications
  where kind = 'care_reply'
    and user_id = 'c0000000-0000-0000-0000-000000000003';
  if v_asha <> 3 then
    raise exception 'The post''s author was told about % of the 3 replies.', v_asha;
  end if;

  -- Spelled out per person too, so a failure says who was pinged.
  for v_person in
    select users.id, users.name from public.users
    where users.email like 'care-%@example.test'
      and users.id <> 'c0000000-0000-0000-0000-000000000003'
  loop
    if exists (
      select 1 from public.app_notifications
      where app_notifications.user_id = v_person.id
        and app_notifications.kind = 'care_reply'
    ) then
      raise exception '% was pinged by the care board.', v_person.name;
    end if;
  end loop;

  -- Nothing was queued under some other kind either — posting is silent, and
  -- replying sends one row and no more.
  select count(*)::integer - (select baseline.notifications from public.care_test_baseline baseline)
    into v_growth
  from public.app_notifications;
  if v_growth <> 3 then
    raise exception 'The care board queued % notifications in total rather than 3.', v_growth;
  end if;

  -- Asha's own reply is not among them.
  if exists (
    select 1 from public.app_notifications
    where kind = 'care_reply'
      and app_notifications.data ->> 'replyId' = (
        select ids.id::text from public.care_test_ids ids where ids.key = 'reply_three'
      )
  ) then
    raise exception 'Replying to your own post notified somebody.';
  end if;

  select app_notifications.title || ' / ' || app_notifications.body into v_body
  from public.app_notifications
  where kind = 'care_reply'
    and app_notifications.data ->> 'replyId' = (
      select ids.id::text from public.care_test_ids ids where ids.key = 'reply_one'
    );
  if v_body !~* 'reply' then
    raise exception 'The notification does not read as a reply: %', v_body;
  end if;
  if v_body !~ 'Bhakta Das' then
    raise exception 'The notification does not name who replied: %', v_body;
  end if;
  if v_body !~ 'Lift to the Sunday feast' then
    raise exception 'The notification does not name the post replied to: %', v_body;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. A plain devotee cannot remove somebody else's post or reply.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'c0000000-0000-0000-0000-000000000005', true);
set local role authenticated;

do $$
declare
  v_refused boolean;
  v_post uuid;
  v_reply uuid;
begin
  select ids.id into v_post from public.care_test_ids ids where ids.key = 'post_asha';
  select ids.id into v_reply from public.care_test_ids ids where ids.key = 'reply_one';

  v_refused := false;
  begin
    perform public.delete_care_post(v_post);
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A plain devotee removed somebody else''s post.';
  end if;
  if not exists (select 1 from public.list_care_posts() listed where listed.id = v_post) then
    raise exception 'The post a devotee could not remove is gone anyway.';
  end if;

  v_refused := false;
  begin
    perform public.delete_care_reply(v_reply);
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A plain devotee removed somebody else''s reply.';
  end if;
  if not exists (
    select 1 from public.list_care_replies(v_post) listed
    where listed.id = v_reply and listed.deleted_at is null
  ) then
    raise exception 'The reply a devotee could not remove is gone anyway.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. An author removes their own reply, and the thread keeps its shape.
--
--    This is the reason removal is soft. Chandra's reply sits between Bhakta's
--    offer and Asha's thanks. Delete the row and "Thank you both" hangs under
--    half a conversation. So the reply keeps its place, loses its words, and
--    the three around it read exactly as they did.
-- ---------------------------------------------------------------------------

do $$
declare
  v_post uuid;
  v_reply uuid;
  v_removed public.care_replies;
  v_row record;
  v_seen text;
  v_rows integer;
  v_refused boolean;
begin
  select ids.id into v_post from public.care_test_ids ids where ids.key = 'post_asha';
  select ids.id into v_reply from public.care_test_ids ids where ids.key = 'reply_two';

  v_removed := public.delete_care_reply(v_reply);
  if v_removed.deleted_at is null then
    raise exception 'Removing a reply left no tombstone.';
  end if;
  if v_removed.deleted_by is distinct from 'c0000000-0000-0000-0000-000000000005'::uuid then
    raise exception 'The removal did not record who made it.';
  end if;

  -- Four rows still, in the same order, with the removed one silent.
  select count(*)::integer into v_rows from public.list_care_replies(v_post);
  if v_rows <> 4 then
    raise exception 'The thread lost its shape: % rows rather than 4.', v_rows;
  end if;

  v_seen := '';
  for v_row in select * from public.list_care_replies(v_post) loop
    v_seen := v_seen || coalesce(v_row.body, '[removed]') || ' / ';
    if v_row.id = v_reply then
      if v_row.body is not null then
        raise exception 'A removed reply still returns its words: %', v_row.body;
      end if;
      if v_row.deleted_at is null then
        raise exception 'A removed reply does not say it was removed.';
      end if;
      if v_row.can_remove then
        raise exception 'An already-removed reply can be removed again.';
      end if;
    end if;
  end loop;
  if v_seen <> 'I can drive you. I leave at 8:30. / [removed] / '
               || 'Thank you both, that is a relief. / See you at 8:30 on the corner. / ' then
    raise exception 'The thread now reads %.', v_seen;
  end if;

  -- The words are not reachable anywhere a devotee can look.
  if exists (select 1 from public.care_replies where care_replies.id = v_reply) then
    raise exception 'A removed reply is still readable straight off the table.';
  end if;
  if exists (
    select 1 from public.list_care_replies(v_post) listed
    where listed.body like '%if Bhakta cannot%'
  ) then
    raise exception 'The removed reply''s words came back through the thread.';
  end if;

  -- The board's count drops, because a removed reply is not an answer.
  select listed.reply_count into v_rows
  from public.list_care_posts() listed where listed.id = v_post;
  if v_rows <> 3 then
    raise exception 'The board counts % replies after one was removed rather than 3.', v_rows;
  end if;

  -- Twice is a mistake, not a licence — a second call would rewrite who
  -- removed it.
  v_refused := false;
  begin
    perform public.delete_care_reply(v_reply);
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'Removing the same reply twice was accepted.';
  end if;
end;
$$;

-- The author of a post removes their own reply on it, too.
reset role;
select set_config('request.jwt.claim.sub', 'c0000000-0000-0000-0000-000000000003', true);
set local role authenticated;

do $$
declare
  v_post uuid;
  v_reply uuid;
begin
  select ids.id into v_post from public.care_test_ids ids where ids.key = 'post_asha';
  select ids.id into v_reply from public.care_test_ids ids where ids.key = 'reply_three';
  perform public.delete_care_reply(v_reply);
  if exists (
    select 1 from public.list_care_replies(v_post) listed
    where listed.id = v_reply and listed.body is not null
  ) then
    raise exception 'An author could not silence their own reply.';
  end if;
  if (select count(*) from public.list_care_replies(v_post)) <> 4 then
    raise exception 'The thread lost a row when its author removed a reply.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. A Community Head removes somebody else's reply, and somebody else's post.
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', 'c0000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_post uuid;
  v_other uuid;
  v_reply uuid;
  v_removed public.care_posts;
begin
  select ids.id into v_post from public.care_test_ids ids where ids.key = 'post_asha';
  select ids.id into v_other from public.care_test_ids ids where ids.key = 'post_chandra';
  select ids.id into v_reply from public.care_test_ids ids where ids.key = 'reply_four';

  -- The board tells a Community Head they may remove everything on it.
  if exists (select 1 from public.list_care_posts() listed where not listed.can_remove) then
    raise exception 'A Community Head was told there is a post they cannot remove.';
  end if;
  if exists (
    select 1 from public.list_care_replies(v_post) listed
    where listed.deleted_at is null and not listed.can_remove
  ) then
    raise exception 'A Community Head was told there is a reply they cannot remove.';
  end if;

  perform public.delete_care_reply(v_reply);
  if exists (
    select 1 from public.list_care_replies(v_post) listed
    where listed.id = v_reply and listed.body is not null
  ) then
    raise exception 'A Community Head could not remove another devotee''s reply.';
  end if;

  v_removed := public.delete_care_post(v_other);
  if v_removed.deleted_at is null then
    raise exception 'Removing a post left no tombstone.';
  end if;
  if v_removed.deleted_by is distinct from 'c0000000-0000-0000-0000-000000000002'::uuid then
    raise exception 'The post removal did not record who made it.';
  end if;
  if exists (select 1 from public.list_care_posts() listed where listed.id = v_other) then
    raise exception 'A Community Head could not remove another devotee''s post.';
  end if;
end;
$$;

-- Nobody may reply to a post that has been taken down, and its thread goes
-- with it.
reset role;
select set_config('request.jwt.claim.sub', 'c0000000-0000-0000-0000-000000000004', true);
set local role authenticated;

do $$
declare
  v_other uuid;
  v_refused boolean := false;
begin
  select ids.id into v_other from public.care_test_ids ids where ids.key = 'post_chandra';
  begin
    perform public.reply_to_care_post(v_other, 'I have a cutting.');
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A removed post still accepts replies.';
  end if;
  if exists (select 1 from public.care_posts where care_posts.id = v_other) then
    raise exception 'A removed post is still readable straight off the table.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 9. An author removes their own post.
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', 'c0000000-0000-0000-0000-000000000003', true);
set local role authenticated;

do $$
declare
  v_post uuid;
  v_removed public.care_posts;
  v_refused boolean := false;
begin
  select ids.id into v_post from public.care_test_ids ids where ids.key = 'post_asha';
  v_removed := public.delete_care_post(v_post);
  if v_removed.id <> v_post then
    raise exception 'Removing a post did not return the row removed.';
  end if;
  if exists (select 1 from public.list_care_posts() listed where listed.id = v_post) then
    raise exception 'An author could not remove their own post.';
  end if;
  if (select count(*) from public.list_care_replies(v_post)) <> 0 then
    raise exception 'A removed post still shows its thread.';
  end if;

  begin
    perform public.delete_care_post(v_post);
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'Removing the same post twice was accepted.';
  end if;

  -- The board is empty and says so without complaint.
  if (select count(*) from public.list_care_posts()) <> 0 then
    raise exception 'The care board still has posts on it.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 10. The tables are not a back door.
--
--     Every write goes through an RPC, so a devotee's own rights must carry no
--     insert, update or delete however they phrase the statement — including
--     the update that would quietly un-remove somebody else's post.
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', 'c0000000-0000-0000-0000-000000000004', true);
set local role authenticated;

do $$
declare
  v_refused boolean;
begin
  v_refused := false;
  begin
    insert into public.care_posts (author_id, title, body)
    values ('c0000000-0000-0000-0000-000000000004', 'Sneaked in', 'Straight into the table.');
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A devotee wrote straight into the care_posts table.';
  end if;

  v_refused := false;
  begin
    insert into public.care_replies (post_id, author_id, body)
    select ids.id, 'c0000000-0000-0000-0000-000000000004', 'Straight into the table.'
    from public.care_test_ids ids where ids.key = 'post_asha';
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A devotee wrote straight into the care_replies table.';
  end if;

  v_refused := false;
  begin
    update public.care_posts set deleted_at = null, deleted_by = null;
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A devotee un-removed a post straight off the table.';
  end if;

  v_refused := false;
  begin
    update public.care_replies set body = 'Rewritten';
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A devotee rewrote the care_replies table.';
  end if;

  v_refused := false;
  begin
    delete from public.care_posts;
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A devotee deleted straight from the care_posts table.';
  end if;

  v_refused := false;
  begin
    delete from public.care_replies;
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A devotee deleted straight from the care_replies table.';
  end if;
end;
$$;

-- Signed out, the board is closed. auth.uid() is null and the definer
-- functions must return nothing rather than the whole congregation's business.
reset role;
select set_config('request.jwt.claim.sub', '', true);
set local role authenticated;

do $$
begin
  if (select count(*) from public.list_care_posts()) <> 0 then
    raise exception 'A signed-out caller can read the care board.';
  end if;
  if (select count(*) from public.care_posts) <> 0 then
    raise exception 'A signed-out caller can read the care_posts table.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 11. Nothing was made noisier on the way past, and no second bucket appeared.
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', '', true);

do $$
declare
  v_growth integer;
  v_rows integer;
begin
  -- Removals notify nobody either. Same baseline, same three rows.
  select count(*)::integer - (select baseline.notifications from public.care_test_baseline baseline)
    into v_growth
  from public.app_notifications;
  if v_growth <> 3 then
    raise exception
      'The care board queued % notifications across its whole life rather than 3.', v_growth;
  end if;

  if not exists (select 1 from storage.buckets where id = 'message-images') then
    raise exception 'The message-images bucket is missing.';
  end if;
  select count(*)::integer into v_rows from storage.buckets
  where buckets.id ilike '%care%';
  if v_rows <> 0 then
    raise exception 'A second bucket was made for care post pictures.';
  end if;
end;
$$;

do $$
begin
  raise notice 'all devotee care checks passed';
end;
$$;

select 'devotee care verification passed' as result;

rollback;
