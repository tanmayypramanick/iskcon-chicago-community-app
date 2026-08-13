-- Functional verification for 202608040052_announcement_reactions.sql.
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
--   Poster   ...0001  President; puts the notice up, and so is the one person
--                     a comment on it is allowed to reach
--   Head     ...0002  Community Head; takes somebody else's comment down
--   Asha     ...0003  plain devotee; likes, unlikes, comments, and owns the
--                     comment that gets replied to
--   Bhakta   ...0004  plain devotee; likes and replies
--   Chandra  ...0005  plain devotee; likes, comments, and must be refused when
--                     they reach for somebody else's words
--
-- The claim this script exists to defend is the quiet one. Announcements go to
-- the whole congregation, which is right — but if the conversation underneath
-- one did too, the third comment of the day would teach four hundred people to
-- mute the app, and the temple would lose its announcements along with the
-- chatter. So the notification assertions are never "the poster was told". They
-- are "the poster was told and the count across every single user in the
-- database is exactly what it should be", which is the only form of the
-- assertion that fails when somebody adds a well-meaning loop. And a like, the
-- single easiest tap in the app to turn into four hundred pushes a day, must
-- move that total by zero.
--
-- The final row must read: announcement reactions verification passed

begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('e0000000-0000-0000-0000-000000000001', 'react-poster@example.test', '{"name":"Rasika Poster"}'),
  ('e0000000-0000-0000-0000-000000000002', 'react-head@example.test', '{"name":"Radha Head"}'),
  ('e0000000-0000-0000-0000-000000000003', 'react-asha@example.test', '{"name":"Asha Devi"}'),
  ('e0000000-0000-0000-0000-000000000004', 'react-bhakta@example.test', '{"name":"Bhakta Das"}'),
  ('e0000000-0000-0000-0000-000000000005', 'react-chandra@example.test', '{"name":"Chandra Devi"}');

update public.users
set role_id = (select roles.id from public.roles where roles.name = 'president')
where email = 'react-poster@example.test';

update public.users
set role_id = (select roles.id from public.roles where roles.name = 'core')
where email = 'react-head@example.test';

-- Asha, Bhakta and Chandra keep the role the signup trigger gave them, which is
-- the whole point: a plain devotee must be able to like, comment and reply.
do $$
declare
  v_role text;
  v_person text;
begin
  for v_person in
    select users.email from public.users
    where users.email in ('react-asha@example.test', 'react-bhakta@example.test',
                          'react-chandra@example.test')
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
create table public.reaction_test_ids (key text primary key, id uuid not null);
grant select, insert on public.reaction_test_ids to authenticated;

-- ---------------------------------------------------------------------------
-- 0. The ground this feature stands on.
--
--    If a later migration widens services.manage_recurring, moderation of these
--    threads widens with it silently. That is worth failing loudly over here.
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
      'services.manage_recurring is held by % — announcement reactions assume core, president, tech.',
      v_holders;
  end if;

  -- No new permission key was invented for this feature.
  if exists (
    select 1 from public.role_permissions
    where role_permissions.permission_key like '%reaction%'
       or role_permissions.permission_key like '%comment%'
  ) then
    raise exception 'A separate reaction permission key was registered.';
  end if;
end;
$$;

-- Row level security is actually on, on both tables. Everything below is
-- meaningless if it is not.
do $$
declare
  v_table text;
begin
  foreach v_table in array array['announcement_likes', 'announcement_comments'] loop
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

-- Liking twice must be one like because the key says so, not because a function
-- remembered to check.
do $$
declare
  v_key text;
begin
  select string_agg(attname, ',' order by attnum) into v_key
  from pg_index
  join pg_attribute on pg_attribute.attrelid = pg_index.indrelid
    and pg_attribute.attnum = any(pg_index.indkey)
  where pg_index.indrelid = 'public.announcement_likes'::regclass
    and pg_index.indisprimary;
  if v_key is distinct from 'announcement_id,devotee_id' then
    raise exception
      'announcement_likes is keyed on % rather than (announcement_id, devotee_id).', v_key;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 0b. The kind constraint still accepts every kind that came before it.
--
--     This list has been truncated by a careless rewrite six times. The
--     constraint is replaced rather than altered, so a partial restatement
--     outlaws kinds that live code still queues — and nothing fails until a
--     devotee's phone should have buzzed and did not. So: a sample from every
--     era of this app is pushed through the constraint here, along with the two
--     new kinds, and a nonsense kind is confirmed to still be refused.
-- ---------------------------------------------------------------------------

do $$
declare
  v_kind text;
  v_refused boolean;
begin
  foreach v_kind in array array[
    'service_open', 'service_completed', 'service_coverage_needed',
    'recurring_interest_reviewed', 'seva_verification_requested',
    'weekly_offer_counter_reviewed', 'access_request_submitted',
    'devotee_joined', 'profile_incomplete',
    'sanga_created', 'sanga_member_left', 'sanga_admin_transferred',
    'sanga_deleted', 'announcement_posted', 'feedback_reviewed',
    'care_reply', 'birthday_today', 'newsletter_posted',
    'newsletter_reviewed', 'access_appointed', 'access_revoked',
    'sponsorship_fulfilled', 'remote',
    'announcement_commented', 'announcement_comment_replied'
  ] loop
    begin
      insert into public.app_notifications (user_id, kind, title, body)
      values ('e0000000-0000-0000-0000-000000000001', v_kind, 'probe', 'probe');
    exception when others then
      raise exception
        'The notification kind "%" was dropped from app_notifications_kind_check.', v_kind;
    end;
  end loop;

  -- And the constraint is still a constraint.
  v_refused := false;
  begin
    insert into public.app_notifications (user_id, kind, title, body)
    values ('e0000000-0000-0000-0000-000000000001', 'announcement_yelled', 'probe', 'probe');
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'app_notifications now accepts any kind at all.';
  end if;

  -- The probes are not part of anything counted below.
  delete from public.app_notifications where title = 'probe' and body = 'probe';
end;
$$;

-- ---------------------------------------------------------------------------
-- 1. Two notices go up. The second exists only so that a reply can be aimed at
--    a comment on the wrong one.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'e0000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
  v_ann public.announcements;
begin
  v_ann := public.create_announcement(
    'Janmashtami midnight arati',
    'The midnight arati begins at 11pm in the main hall. Prasadam follows.'
  );
  insert into public.reaction_test_ids values ('announcement', v_ann.id);

  v_ann := public.create_announcement(
    'Parking lot closed Sunday',
    'Resurfacing. Please use the street parking on Ridge Avenue.'
  );
  insert into public.reaction_test_ids values ('other_announcement', v_ann.id);
end;
$$;

reset role;

-- Everything queued up to this point — the signup traffic and the two
-- announcement_posted fan-outs — is the baseline. What grows past it from here
-- is exactly what this feature sent, and nothing else.
create table public.reaction_test_baseline as
select count(*)::integer as notifications from public.app_notifications;

-- ---------------------------------------------------------------------------
-- 2. Liking, unliking, and liking again — idempotent in both directions.
--
--    The double-tap is the case that matters. A retried request over the
--    temple's wifi must not produce a second like, and a devotee who unlikes
--    something they never liked must not be shown an error.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'e0000000-0000-0000-0000-000000000003', true);
set local role authenticated;

do $$
declare
  v_ann uuid;
  v_liked boolean;
  v_rows integer;
begin
  select ids.id into v_ann from public.reaction_test_ids ids where ids.key = 'announcement';

  v_liked := public.toggle_announcement_like(v_ann);
  if not v_liked then
    raise exception 'Liking a notice reported that it is not liked.';
  end if;

  select count(*)::integer into v_rows from public.announcement_likes
  where announcement_likes.announcement_id = v_ann;
  if v_rows <> 1 then
    raise exception 'One like wrote % rows.', v_rows;
  end if;

  -- Unliking.
  v_liked := public.toggle_announcement_like(v_ann);
  if v_liked then
    raise exception 'Unliking a notice reported that it is still liked.';
  end if;
  select count(*)::integer into v_rows from public.announcement_likes
  where announcement_likes.announcement_id = v_ann;
  if v_rows <> 0 then
    raise exception 'Unliking left % rows behind.', v_rows;
  end if;

  -- Unliking twice is not an error. A phone that missed the first response
  -- retries, and the devotee must not be shown a failure for it.
  v_liked := public.toggle_announcement_like(v_ann);
  if not v_liked then
    raise exception 'The third tap did not like the notice again.';
  end if;
  v_liked := public.toggle_announcement_like(v_ann);
  v_liked := public.toggle_announcement_like(v_ann);
  if not v_liked then
    raise exception 'Toggling settled in the wrong state.';
  end if;

  select count(*)::integer into v_rows from public.announcement_likes
  where announcement_likes.announcement_id = v_ann;
  if v_rows <> 1 then
    raise exception 'After five taps Asha holds % likes rather than 1.', v_rows;
  end if;
end;
$$;

-- Two more devotees like it, so "like_count" is not one lucky row.
reset role;
select set_config('request.jwt.claim.sub', 'e0000000-0000-0000-0000-000000000004', true);
set local role authenticated;

do $$
declare
  v_ann uuid;
begin
  select ids.id into v_ann from public.reaction_test_ids ids where ids.key = 'announcement';
  if not public.toggle_announcement_like(v_ann) then
    raise exception 'A second plain devotee could not like the notice.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'e0000000-0000-0000-0000-000000000005', true);
set local role authenticated;

do $$
declare
  v_ann uuid;
begin
  select ids.id into v_ann from public.reaction_test_ids ids where ids.key = 'announcement';
  if not public.toggle_announcement_like(v_ann) then
    raise exception 'A third plain devotee could not like the notice.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. The like list names everyone, and the board's counts are per viewer.
-- ---------------------------------------------------------------------------

do $$
declare
  v_ann uuid;
  v_other uuid;
  v_names text;
  v_row record;
  v_previous timestamptz;
begin
  select ids.id into v_ann from public.reaction_test_ids ids where ids.key = 'announcement';
  select ids.id into v_other from public.reaction_test_ids ids where ids.key = 'other_announcement';

  select string_agg(listed.name, ',' order by listed.created_at desc) into v_names
  from public.list_announcement_likes(v_ann) listed;
  if v_names is distinct from 'Chandra Devi,Bhakta Das,Asha Devi' then
    raise exception 'The like list reads %.', coalesce(v_names, '(nothing)');
  end if;

  -- Newest first, as returned rather than as re-sorted above.
  v_previous := null;
  for v_row in select * from public.list_announcement_likes(v_ann) loop
    if v_previous is not null and v_row.created_at > v_previous then
      raise exception 'The like list is not ordered newest first.';
    end if;
    v_previous := v_row.created_at;
    if v_row.devotee_id is null then
      raise exception 'A like came back without a devotee.';
    end if;
  end loop;

  -- A notice nobody liked lists nobody.
  if exists (select 1 from public.list_announcement_likes(v_other)) then
    raise exception 'A notice nobody liked lists somebody.';
  end if;
end;
$$;

-- Chandra, who liked it, sees liked_by_me true; the Head, who did not, false.
do $$
declare
  v_ann uuid;
  v_row record;
begin
  select ids.id into v_ann from public.reaction_test_ids ids where ids.key = 'announcement';
  select * into v_row from public.list_announcements() listed where listed.id = v_ann;
  if v_row.like_count <> 3 then
    raise exception 'The board shows % likes rather than 3.', v_row.like_count;
  end if;
  if not v_row.liked_by_me then
    raise exception 'A devotee who liked the notice is told they did not.';
  end if;
  if v_row.comment_count <> 0 then
    raise exception 'An uncommented notice shows % comments.', v_row.comment_count;
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'e0000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_ann uuid;
  v_other uuid;
  v_row record;
begin
  select ids.id into v_ann from public.reaction_test_ids ids where ids.key = 'announcement';
  select ids.id into v_other from public.reaction_test_ids ids where ids.key = 'other_announcement';

  select * into v_row from public.list_announcements() listed where listed.id = v_ann;
  if v_row.like_count <> 3 then
    raise exception 'The Head sees % likes rather than 3.', v_row.like_count;
  end if;
  if v_row.liked_by_me then
    raise exception 'A devotee who never liked the notice is told they did.';
  end if;

  -- The counts belong to the row they are on, not to the table.
  select * into v_row from public.list_announcements() listed where listed.id = v_other;
  if v_row.like_count <> 0 or v_row.liked_by_me then
    raise exception 'The unliked notice carries the other notice''s likes.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. And every one of those taps notified nobody.
--
--    Asserted here, before a single comment exists, so the zero cannot be
--    borrowed from anywhere.
-- ---------------------------------------------------------------------------

reset role;

do $$
declare
  v_growth integer;
begin
  select count(*)::integer - (select baseline.notifications from public.reaction_test_baseline baseline)
    into v_growth
  from public.app_notifications;
  if v_growth <> 0 then
    raise exception 'Six likes queued % notifications. A like must notify nobody.', v_growth;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Commenting and replying.
--
--    Built in a deliberate order, because section 7 counts the result:
--      comment_asha     Asha comments        -> tells the Poster
--      comment_chandra  Chandra comments     -> tells the Poster
--      comment_poster   Poster comments      -> tells nobody (their own notice)
--      reply_bhakta     Bhakta -> Asha       -> tells Asha
--      reply_chandra    Chandra -> Asha      -> tells Asha
--      reply_asha_own   Asha -> Asha         -> tells nobody
--      reply_asha_chand Asha -> Chandra      -> tells Chandra
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'e0000000-0000-0000-0000-000000000003', true);
set local role authenticated;

do $$
declare
  v_ann uuid;
  v_comment public.announcement_comments;
begin
  select ids.id into v_ann from public.reaction_test_ids ids where ids.key = 'announcement';

  v_comment := public.add_announcement_comment(v_ann, 'Is that the main hall or the annexe?');
  if v_comment.id is null then
    raise exception 'A plain devotee could not comment.';
  end if;
  if v_comment.author_id <> 'e0000000-0000-0000-0000-000000000003' then
    raise exception 'The comment did not record who wrote it.';
  end if;
  if v_comment.parent_comment_id is not null then
    raise exception 'A top-level comment came back with a parent.';
  end if;
  if v_comment.deleted_at is not null or v_comment.deleted_by is not null then
    raise exception 'A brand new comment is already marked as removed.';
  end if;
  insert into public.reaction_test_ids values ('comment_asha', v_comment.id);
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'e0000000-0000-0000-0000-000000000005', true);
set local role authenticated;

do $$
declare
  v_ann uuid;
  v_comment public.announcement_comments;
begin
  select ids.id into v_ann from public.reaction_test_ids ids where ids.key = 'announcement';
  v_comment := public.add_announcement_comment(v_ann, 'Can I bring my mother?');
  insert into public.reaction_test_ids values ('comment_chandra', v_comment.id);
end;
$$;

-- The Poster answers on their own notice. Nobody is told: they do not need
-- pushing their own words.
reset role;
select set_config('request.jwt.claim.sub', 'e0000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
  v_ann uuid;
  v_comment public.announcement_comments;
begin
  select ids.id into v_ann from public.reaction_test_ids ids where ids.key = 'announcement';
  v_comment := public.add_announcement_comment(v_ann, 'Main hall. Everyone is welcome.');
  insert into public.reaction_test_ids values ('comment_poster', v_comment.id);
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'e0000000-0000-0000-0000-000000000004', true);
set local role authenticated;

do $$
declare
  v_ann uuid;
  v_parent uuid;
  v_comment public.announcement_comments;
begin
  select ids.id into v_ann from public.reaction_test_ids ids where ids.key = 'announcement';
  select ids.id into v_parent from public.reaction_test_ids ids where ids.key = 'comment_asha';

  v_comment := public.add_announcement_comment(v_ann, 'Main hall, I asked yesterday.', v_parent);
  if v_comment.parent_comment_id <> v_parent then
    raise exception 'The reply was not filed under the comment it answers.';
  end if;
  insert into public.reaction_test_ids values ('reply_bhakta', v_comment.id);
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'e0000000-0000-0000-0000-000000000005', true);
set local role authenticated;

do $$
declare
  v_ann uuid;
  v_parent uuid;
  v_comment public.announcement_comments;
begin
  select ids.id into v_ann from public.reaction_test_ids ids where ids.key = 'announcement';
  select ids.id into v_parent from public.reaction_test_ids ids where ids.key = 'comment_asha';
  v_comment := public.add_announcement_comment(v_ann, 'Same, the main hall.', v_parent);
  insert into public.reaction_test_ids values ('reply_chandra', v_comment.id);
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'e0000000-0000-0000-0000-000000000003', true);
set local role authenticated;

do $$
declare
  v_ann uuid;
  v_mine uuid;
  v_chandra uuid;
  v_comment public.announcement_comments;
begin
  select ids.id into v_ann from public.reaction_test_ids ids where ids.key = 'announcement';
  select ids.id into v_mine from public.reaction_test_ids ids where ids.key = 'comment_asha';
  select ids.id into v_chandra from public.reaction_test_ids ids where ids.key = 'comment_chandra';

  -- Replying under her own comment: notifies nobody at all.
  v_comment := public.add_announcement_comment(v_ann, 'Thank you both.', v_mine);
  insert into public.reaction_test_ids values ('reply_asha_own', v_comment.id);

  -- Replying to Chandra: notifies Chandra, and not the Poster.
  v_comment := public.add_announcement_comment(v_ann, 'Of course, please do.', v_chandra);
  insert into public.reaction_test_ids values ('reply_asha_chand', v_comment.id);
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. One level, and one level only.
--
--    Refused through the RPC with words a devotee can read, and refused again
--    at the table for anybody who finds another way in.
-- ---------------------------------------------------------------------------

do $$
declare
  v_ann uuid;
  v_other uuid;
  v_reply uuid;
  v_comment uuid;
  v_message text;
begin
  select ids.id into v_ann from public.reaction_test_ids ids where ids.key = 'announcement';
  select ids.id into v_other from public.reaction_test_ids ids where ids.key = 'other_announcement';
  select ids.id into v_reply from public.reaction_test_ids ids where ids.key = 'reply_bhakta';
  select ids.id into v_comment from public.reaction_test_ids ids where ids.key = 'comment_asha';

  v_message := null;
  begin
    perform public.add_announcement_comment(v_ann, 'And what time exactly?', v_reply);
  exception when others then
    v_message := sqlerrm;
  end;
  if v_message is null then
    raise exception 'A reply to a reply was accepted.';
  end if;
  if v_message !~* 'reply' or v_message ~* '(constraint|null value|violates)' then
    raise exception 'A reply to a reply was refused unreadably: %', v_message;
  end if;
  -- And refused by the RPC's own guard, in the RPC's own words, rather than by
  -- the trigger underneath it. The two are worded differently precisely so this
  -- assertion can tell them apart: if the readable guard is ever deleted, the
  -- trigger keeps the data right but starts showing a devotee a sentence with a
  -- uuid in it, and that must fail here rather than in somebody's hand.
  if v_message !~ 'but not to a reply' then
    raise exception
      'A devotee was shown the table''s integrity message rather than the RPC''s: %',
      v_message;
  end if;

  -- Nothing was written on the way to being refused.
  if exists (
    select 1 from public.announcement_comments
    where announcement_comments.parent_comment_id = v_reply
  ) then
    raise exception 'The refused reply-to-a-reply was written anyway.';
  end if;

  -- A parent on a different notice is not a parent.
  v_message := null;
  begin
    perform public.add_announcement_comment(v_other, 'Wrong thread.', v_comment);
  exception when others then
    v_message := sqlerrm;
  end;
  if v_message is null then
    raise exception 'A reply was filed under a comment on another announcement.';
  end if;

  -- A comment on a notice that does not exist.
  v_message := null;
  begin
    perform public.add_announcement_comment(
      '00000000-0000-0000-0000-0000000000ff', 'Into the void.');
  exception when others then
    v_message := sqlerrm;
  end;
  if v_message is null then
    raise exception 'A comment was accepted on a notice that does not exist.';
  end if;

  -- A parent that does not exist.
  v_message := null;
  begin
    perform public.add_announcement_comment(
      v_ann, 'Under nothing.', '00000000-0000-0000-0000-0000000000ff');
  exception when others then
    v_message := sqlerrm;
  end;
  if v_message is null then
    raise exception 'A reply was accepted under a comment that does not exist.';
  end if;
end;
$$;

-- The table itself refuses it too, not merely the RPC's manners. Attempted as
-- the owner, because a devotee has no write grant on the table at all — which
-- is the point: this is the guard that survives a future function forgetting.
reset role;

do $$
declare
  v_ann uuid;
  v_reply uuid;
  v_refused boolean;
  v_message text;
begin
  select ids.id into v_ann from public.reaction_test_ids ids where ids.key = 'announcement';
  select ids.id into v_reply from public.reaction_test_ids ids where ids.key = 'reply_bhakta';

  v_message := null;
  begin
    insert into public.announcement_comments (
      announcement_id, parent_comment_id, author_id, body
    )
    values (v_ann, v_reply, 'e0000000-0000-0000-0000-000000000004', 'Straight in.');
  exception when others then
    v_message := sqlerrm;
  end;
  if v_message is null then
    raise exception 'The table accepted a reply nested under another reply.';
  end if;
  if v_message !~* 'one level deep' then
    raise exception 'The table refused it for some other reason: %', v_message;
  end if;

  -- And a top-level comment cannot be reparented under a reply afterwards.
  v_refused := false;
  begin
    update public.announcement_comments
    set parent_comment_id = v_reply
    where announcement_comments.id = (
      select ids.id from public.reaction_test_ids ids where ids.key = 'comment_poster'
    );
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A comment was reparented under a reply after the fact.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. The quiet part, asserted across every user in the database.
--
--    Two comments reached the Poster. Two replies reached Asha, one reached
--    Chandra. Nothing reached anybody else, of any kind, ever — the baseline
--    from section 1 subtracts the announcement fan-out, so what is left is
--    exactly what this feature sent.
-- ---------------------------------------------------------------------------

do $$
declare
  v_growth integer;
  v_count integer;
  v_body text;
  v_person record;
begin
  select count(*)::integer - (select baseline.notifications from public.reaction_test_baseline baseline)
    into v_growth
  from public.app_notifications;
  if v_growth <> 5 then
    raise exception
      'Announcement reactions queued % notifications in total rather than 5.', v_growth;
  end if;

  select count(*)::integer into v_count
  from public.app_notifications where kind = 'announcement_commented';
  if v_count <> 2 then
    raise exception '% announcement_commented notifications were queued rather than 2.', v_count;
  end if;

  select count(*)::integer into v_count
  from public.app_notifications where kind = 'announcement_comment_replied';
  if v_count <> 3 then
    raise exception '% announcement_comment_replied notifications were queued rather than 3.', v_count;
  end if;

  -- The poster, and not one other soul, hears that their notice was commented
  -- on. This is the assertion that fails when somebody adds a helpful loop.
  select count(*)::integer into v_count
  from public.app_notifications
  where kind = 'announcement_commented'
    and user_id <> 'e0000000-0000-0000-0000-000000000001';
  if v_count <> 0 then
    raise exception '% devotees other than the poster were told about a comment.', v_count;
  end if;

  -- A reply reaches the comment's author and stops there. In particular it does
  -- not also reach the poster, whose notice it is: they asked to hear that
  -- their notice was discussed, not to follow every sub-thread it grows.
  select count(*)::integer into v_count
  from public.app_notifications
  where kind = 'announcement_comment_replied'
    and user_id not in (
      'e0000000-0000-0000-0000-000000000003',
      'e0000000-0000-0000-0000-000000000005'
    );
  if v_count <> 0 then
    raise exception
      '% people other than the replied-to comment''s author were told about a reply.', v_count;
  end if;

  select count(*)::integer into v_count
  from public.app_notifications
  where kind = 'announcement_comment_replied'
    and user_id = 'e0000000-0000-0000-0000-000000000003';
  if v_count <> 2 then
    raise exception 'Asha was told about % of the 2 replies to her comment.', v_count;
  end if;

  select count(*)::integer into v_count
  from public.app_notifications
  where kind = 'announcement_comment_replied'
    and user_id = 'e0000000-0000-0000-0000-000000000005';
  if v_count <> 1 then
    raise exception 'Chandra was told about % of the 1 reply to her comment.', v_count;
  end if;

  -- Spelled out per person too, so a failure says who was pinged.
  for v_person in
    select users.id, users.name from public.users
    where users.email like 'react-%@example.test'
  loop
    select count(*)::integer into v_count
    from public.app_notifications
    where app_notifications.user_id = v_person.id
      and app_notifications.kind in
        ('announcement_commented', 'announcement_comment_replied');

    if v_person.id = 'e0000000-0000-0000-0000-000000000001' and v_count <> 2 then
      raise exception 'The poster holds % reaction notifications rather than 2.', v_count;
    elsif v_person.id = 'e0000000-0000-0000-0000-000000000003' and v_count <> 2 then
      raise exception 'Asha holds % reaction notifications rather than 2.', v_count;
    elsif v_person.id = 'e0000000-0000-0000-0000-000000000005' and v_count <> 1 then
      raise exception 'Chandra holds % reaction notifications rather than 1.', v_count;
    elsif v_person.id in (
            'e0000000-0000-0000-0000-000000000002',
            'e0000000-0000-0000-0000-000000000004'
          ) and v_count <> 0 then
      raise exception '% was pinged by a thread they are not in.', v_person.name;
    end if;
  end loop;

  -- Speaking to yourself tells nobody.
  if exists (
    select 1 from public.app_notifications
    where app_notifications.data ->> 'commentId' in (
      select ids.id::text from public.reaction_test_ids ids
      where ids.key in ('comment_poster', 'reply_asha_own')
    )
  ) then
    raise exception 'Commenting or replying to yourself notified somebody.';
  end if;

  -- And the words read like something a devotee can act on.
  select app_notifications.title || ' / ' || app_notifications.body into v_body
  from public.app_notifications
  where kind = 'announcement_commented'
    and app_notifications.data ->> 'commentId' = (
      select ids.id::text from public.reaction_test_ids ids where ids.key = 'comment_asha'
    );
  if v_body !~* 'comment' then
    raise exception 'The notification does not read as a comment: %', v_body;
  end if;
  if v_body !~ 'Asha Devi' then
    raise exception 'The notification does not name who commented: %', v_body;
  end if;
  if v_body !~ 'Janmashtami midnight arati' then
    raise exception 'The notification does not name the notice: %', v_body;
  end if;

  select app_notifications.title || ' / ' || app_notifications.body into v_body
  from public.app_notifications
  where kind = 'announcement_comment_replied'
    and app_notifications.data ->> 'commentId' = (
      select ids.id::text from public.reaction_test_ids ids where ids.key = 'reply_bhakta'
    );
  if v_body !~* 'repl' then
    raise exception 'The notification does not read as a reply: %', v_body;
  end if;
  if v_body !~ 'Bhakta Das' then
    raise exception 'The notification does not name who replied: %', v_body;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. The thread reads as a thread.
--
--    Top-level comments oldest first, each followed by its own replies. The
--    order is the client's whole rendering strategy, so it is asserted exactly
--    rather than approximately.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'e0000000-0000-0000-0000-000000000004', true);
set local role authenticated;

do $$
declare
  v_ann uuid;
  v_row record;
  v_seen text;
  v_rows integer;
begin
  select ids.id into v_ann from public.reaction_test_ids ids where ids.key = 'announcement';

  v_seen := '';
  for v_row in select * from public.list_announcement_comments(v_ann) loop
    v_seen := v_seen || v_row.author_name
      || case when v_row.parent_comment_id is null then '' else '>' end || '|';
  end loop;
  if v_seen <> 'Asha Devi|Bhakta Das>|Chandra Devi>|Asha Devi>|'
              || 'Chandra Devi|Asha Devi>|Rasika Poster|' then
    raise exception 'The thread reads %.', v_seen;
  end if;

  select count(*)::integer into v_rows from public.list_announcement_comments(v_ann);
  if v_rows <> 7 then
    raise exception 'The thread has % rows rather than 7.', v_rows;
  end if;

  -- reply_count belongs to the comment replies hang off, and is zero on a reply.
  select * into v_row from public.list_announcement_comments(v_ann) listed
  where listed.id = (select ids.id from public.reaction_test_ids ids where ids.key = 'comment_asha');
  if v_row.reply_count <> 3 then
    raise exception 'Asha''s comment shows % replies rather than 3.', v_row.reply_count;
  end if;
  if v_row.author_photo_url is not null then
    raise exception 'An author with no photo was given one.';
  end if;
  if v_row.can_remove then
    raise exception 'A plain devotee was told they could remove somebody else''s comment.';
  end if;

  select * into v_row from public.list_announcement_comments(v_ann) listed
  where listed.id = (select ids.id from public.reaction_test_ids ids where ids.key = 'reply_bhakta');
  if v_row.reply_count <> 0 then
    raise exception 'A reply shows % replies of its own.', v_row.reply_count;
  end if;
  if not v_row.can_remove then
    raise exception 'A devotee was told they could not remove their own reply.';
  end if;

  -- The board's count follows the thread.
  select * into v_row from public.list_announcements() listed where listed.id = v_ann;
  if v_row.comment_count <> 7 then
    raise exception 'The board shows % comments rather than 7.', v_row.comment_count;
  end if;

  -- A notice with no conversation under it has none of somebody else's.
  select * into v_row from public.list_announcements() listed
  where listed.id = (select ids.id from public.reaction_test_ids ids where ids.key = 'other_announcement');
  if v_row.comment_count <> 0 then
    raise exception 'The quiet notice shows % comments.', v_row.comment_count;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 9. Blank comments are refused, readably.
--
--    Both halves are asserted: that the refusal happened, and that it came from
--    the guard rather than from the table constraint underneath it. A devotee
--    shown "violates check constraint announcement_comment_body_not_blank" has
--    been told nothing they can act on.
-- ---------------------------------------------------------------------------

do $$
declare
  v_ann uuid;
  v_parent uuid;
  v_message text;
  v_before integer;
  v_after integer;
begin
  select ids.id into v_ann from public.reaction_test_ids ids where ids.key = 'announcement';
  select ids.id into v_parent from public.reaction_test_ids ids where ids.key = 'comment_asha';
  select count(*)::integer into v_before from public.announcement_comments;

  v_message := null;
  begin
    perform public.add_announcement_comment(v_ann, '   ');
  exception when others then
    v_message := sqlerrm;
  end;
  if v_message is null then
    raise exception 'A blank comment was accepted.';
  end if;
  if v_message ~* '(constraint|null value|violates)' then
    raise exception 'A blank comment was refused unreadably: %', v_message;
  end if;

  -- Blank is not only spaces. The comment box in the app is multi-line, so the
  -- easiest way to submit nothing is to press return twice — and plain trim()
  -- strips spaces alone, so a newline-only body sails past a guard written with
  -- it and lands on the thread as an empty bubble.
  v_message := null;
  begin
    perform public.add_announcement_comment(v_ann, e'\n\t \r\n');
  exception when others then
    v_message := sqlerrm;
  end;
  if v_message is null then
    raise exception 'A comment of nothing but newlines and tabs was accepted.';
  end if;
  if v_message ~* '(constraint|null value|violates)' then
    raise exception 'A whitespace-only comment was refused unreadably: %', v_message;
  end if;

  -- The same on the reply path.
  v_message := null;
  begin
    perform public.add_announcement_comment(v_ann, e'\r\n \v', v_parent);
  exception when others then
    v_message := sqlerrm;
  end;
  if v_message is null then
    raise exception 'A whitespace-only reply was accepted.';
  end if;

  v_message := null;
  begin
    perform public.add_announcement_comment(v_ann, null);
  exception when others then
    v_message := sqlerrm;
  end;
  if v_message is null then
    raise exception 'A null comment was accepted.';
  end if;

  select count(*)::integer into v_after from public.announcement_comments;
  if v_after <> v_before then
    raise exception 'A refused blank comment was written anyway.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 10. A plain devotee cannot remove somebody else's words.
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', 'e0000000-0000-0000-0000-000000000005', true);
set local role authenticated;

do $$
declare
  v_ann uuid;
  v_comment uuid;
  v_reply uuid;
  v_refused boolean;
begin
  select ids.id into v_ann from public.reaction_test_ids ids where ids.key = 'announcement';
  select ids.id into v_comment from public.reaction_test_ids ids where ids.key = 'comment_asha';
  select ids.id into v_reply from public.reaction_test_ids ids where ids.key = 'reply_bhakta';

  v_refused := false;
  begin
    perform public.delete_announcement_comment(v_comment);
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A plain devotee removed somebody else''s comment.';
  end if;

  v_refused := false;
  begin
    perform public.delete_announcement_comment(v_reply);
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A plain devotee removed somebody else''s reply.';
  end if;

  if (select count(*) from public.list_announcement_comments(v_ann) listed
      where listed.id in (v_comment, v_reply) and listed.deleted_at is null) <> 2 then
    raise exception 'The words a devotee could not remove are gone anyway.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 11. An author removes their own comment, and the thread keeps its shape.
--
--     This is the reason removal is soft. Asha's question sits above three
--     answers to it. Delete the row and "Main hall, I asked yesterday" hangs
--     under nothing. So the comment keeps its place, loses its words, and the
--     replies beneath it read exactly as they did.
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', 'e0000000-0000-0000-0000-000000000003', true);
set local role authenticated;

do $$
declare
  v_ann uuid;
  v_comment uuid;
  v_removed public.announcement_comments;
  v_row record;
  v_seen text;
  v_rows integer;
  v_refused boolean;
begin
  select ids.id into v_ann from public.reaction_test_ids ids where ids.key = 'announcement';
  select ids.id into v_comment from public.reaction_test_ids ids where ids.key = 'comment_asha';

  v_removed := public.delete_announcement_comment(v_comment);
  if v_removed.deleted_at is null then
    raise exception 'Removing a comment left no tombstone.';
  end if;
  if v_removed.deleted_by is distinct from 'e0000000-0000-0000-0000-000000000003'::uuid then
    raise exception 'The removal did not record who made it.';
  end if;

  -- Seven rows still, in the same order, with the removed one silent.
  select count(*)::integer into v_rows from public.list_announcement_comments(v_ann);
  if v_rows <> 7 then
    raise exception 'The thread lost its shape: % rows rather than 7.', v_rows;
  end if;

  v_seen := '';
  for v_row in select * from public.list_announcement_comments(v_ann) loop
    v_seen := v_seen || coalesce(v_row.body, '[removed]') || ' / ';
    if v_row.id = v_comment then
      if v_row.body is not null then
        raise exception 'A removed comment still returns its words: %', v_row.body;
      end if;
      if v_row.deleted_at is null then
        raise exception 'A removed comment does not say it was removed.';
      end if;
      if v_row.can_remove then
        raise exception 'An already-removed comment can be removed again.';
      end if;
      if v_row.author_name is null then
        raise exception 'A removed comment lost the shape of who wrote it.';
      end if;
    end if;
  end loop;
  if v_seen !~ '\[removed\]' then
    raise exception 'The removed comment left no tombstone in the thread: %', v_seen;
  end if;
  -- The replies under it kept their words.
  if v_seen !~ 'Main hall, I asked yesterday' then
    raise exception 'Removing a comment silenced the replies under it: %', v_seen;
  end if;

  -- The words themselves are unreachable, not merely omitted by the function.
  if exists (
    select 1 from public.announcement_comments
    where announcement_comments.id = v_comment
  ) then
    raise exception 'A devotee can still read a removed comment straight off the table.';
  end if;

  -- Removing twice is a mistake, not a licence: a second call would rewrite
  -- deleted_by and the record would name the wrong person.
  v_refused := false;
  begin
    perform public.delete_announcement_comment(v_comment);
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A comment was removed twice.';
  end if;

  -- And a reply cannot be aimed at a comment that has been taken down.
  v_refused := false;
  begin
    perform public.add_announcement_comment(v_ann, 'Late to this.', v_comment);
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A reply was filed under a removed comment.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 12. A Community Head removes somebody else's, and the count follows.
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', 'e0000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_ann uuid;
  v_comment uuid;
  v_removed public.announcement_comments;
  v_row record;
  v_rows integer;
begin
  select ids.id into v_ann from public.reaction_test_ids ids where ids.key = 'announcement';
  select ids.id into v_comment from public.reaction_test_ids ids where ids.key = 'comment_chandra';

  -- The Head is told they may, per row, so the client need not work it out.
  select * into v_row from public.list_announcement_comments(v_ann) listed
  where listed.id = v_comment;
  if not v_row.can_remove then
    raise exception 'A Community Head was told they could not remove a comment.';
  end if;
  if (select count(*) from public.list_announcement_comments(v_ann) listed
      where listed.can_remove) <> 6 then
    raise exception 'A Community Head may remove other than every live comment.';
  end if;

  v_removed := public.delete_announcement_comment(v_comment);
  if v_removed.deleted_by is distinct from 'e0000000-0000-0000-0000-000000000002'::uuid then
    raise exception 'The moderator''s removal named somebody else.';
  end if;

  -- Two of the seven are gone; the shape is not.
  select count(*)::integer into v_rows from public.list_announcement_comments(v_ann);
  if v_rows <> 7 then
    raise exception 'Moderation reshaped the thread: % rows rather than 7.', v_rows;
  end if;

  -- reply_count and comment_count both exclude what was removed.
  select * into v_row from public.list_announcements() listed where listed.id = v_ann;
  if v_row.comment_count <> 5 then
    raise exception 'The board counts % comments rather than the 5 still standing.',
      v_row.comment_count;
  end if;
  if v_row.like_count <> 3 then
    raise exception 'Removing comments changed the like count to %.', v_row.like_count;
  end if;
end;
$$;

-- A removed comment's replies still count against the comment they hang under.
reset role;
select set_config('request.jwt.claim.sub', 'e0000000-0000-0000-0000-000000000004', true);
set local role authenticated;

do $$
declare
  v_ann uuid;
  v_reply uuid;
  v_removed public.announcement_comments;
  v_row record;
begin
  select ids.id into v_ann from public.reaction_test_ids ids where ids.key = 'announcement';
  select ids.id into v_reply from public.reaction_test_ids ids where ids.key = 'reply_bhakta';

  v_removed := public.delete_announcement_comment(v_reply);
  if v_removed.deleted_at is null then
    raise exception 'An author could not remove their own reply.';
  end if;

  select * into v_row from public.list_announcement_comments(v_ann) listed
  where listed.id = (select ids.id from public.reaction_test_ids ids where ids.key = 'comment_asha');
  if v_row.reply_count <> 2 then
    raise exception 'The removed reply is still counted: % rather than 2.', v_row.reply_count;
  end if;

  select * into v_row from public.list_announcements() listed where listed.id = v_ann;
  if v_row.comment_count <> 4 then
    raise exception 'The board counts % comments rather than 4.', v_row.comment_count;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 13. Nothing was made noisier on the way past.
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', '', true);

do $$
declare
  v_growth integer;
begin
  -- Removals notify nobody either. Same baseline, same five rows.
  select count(*)::integer - (select baseline.notifications from public.reaction_test_baseline baseline)
    into v_growth
  from public.app_notifications;
  if v_growth <> 5 then
    raise exception
      'Announcement reactions queued % notifications across their whole life rather than 5.',
      v_growth;
  end if;
end;
$$;

do $$
begin
  raise notice 'all announcement reaction checks passed';
end;
$$;

select 'announcement reactions verification passed' as result;

rollback;
