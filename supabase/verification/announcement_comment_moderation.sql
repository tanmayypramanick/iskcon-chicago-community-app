-- Functional verification for 202608040054_announcement_comment_moderation.sql.
--
-- Rolled back at the end. Every local is prefixed v_ so it can never shadow a
-- column name. Anything that must be refused is attempted as the devotee who
-- would really attempt it, under `set local role authenticated`, so the row
-- level security policies, the column grants and the permission checks are the
-- thing being tested rather than superuser rights quietly waving everything
-- through. Notification counts are read after `reset role`, because a devotee
-- cannot — and should not be able to — read somebody else's inbox.
--
-- The rule under test, in full:
--
--   a comment or reply on an announcement may be taken down by its author,
--   OR by the devotee who posted THAT announcement,
--   OR by a Community Head, Tech Admin or President (services.manage_recurring)
--
-- and by nobody else, ever.
--
-- The six people in this script:
--   Nitai    ...0001  posts notice A while a Community Head, then steps down to
--                     a plain devotee. Everything he is allowed to do from that
--                     point on he is allowed to do BECAUSE THE NOTICE IS HIS,
--                     and for no other reason.
--   Head     ...0002  Community Head throughout; removes anybody's, anywhere
--   Asha     ...0003  plain devotee; comments on both notices
--   Bhakta   ...0004  plain devotee; replies
--   Chandra  ...0005  plain devotee; comments and replies, and is the devotee
--                     whose words other people reach for
--   Gauri    ...0006  posts notice B, then steps down exactly as Nitai does
--
-- Why two ex-Community-Heads rather than two plain devotees who posted: today
-- create_announcement requires services.manage_recurring, so every poster holds
-- it at the moment of posting. If the script left them holding it, every
-- assertion about a poster's authority would pass on the strength of the
-- permission and would say nothing whatever about the new rule. Stepping them
-- down is what makes "the poster may" a claim with teeth — and it is the real
-- case the temple has, since coordinators rotate and the notices they put up
-- stay on the board with their name on them.
--
-- The most important assertion in this file is the negative one: Nitai, who
-- posted notice A, is REFUSED on a comment sitting under Gauri's notice B. A
-- change that grants a poster authority over every announcement instead of
-- their own passes every other test here and fails that one. It is asserted
-- both ways — Nitai refused on B, Gauri refused on A — and then paired with
-- Gauri successfully removing the very comment Nitai could not, so that the
-- refusal is proved to be about scope rather than about that comment being
-- beyond everybody's reach.
--
-- can_remove is asserted as a full per-viewer matrix over every comment on both
-- notices, before anything is removed, because the client draws its Remove
-- action from that flag alone and must never re-derive the rule. A flag that
-- disagrees with the guard is the failure this migration exists to make
-- impossible: a button the server then refuses teaches a devotee that the app
-- lies to them.
--
-- The final row must read: announcement comment moderation verification passed

begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('c1000000-0000-0000-0000-000000000001', 'cmod-nitai@example.test', '{"name":"Nitai Das"}'),
  ('c1000000-0000-0000-0000-000000000002', 'cmod-head@example.test', '{"name":"Radha Head"}'),
  ('c1000000-0000-0000-0000-000000000003', 'cmod-asha@example.test', '{"name":"Asha Devi"}'),
  ('c1000000-0000-0000-0000-000000000004', 'cmod-bhakta@example.test', '{"name":"Bhakta Das"}'),
  ('c1000000-0000-0000-0000-000000000005', 'cmod-chandra@example.test', '{"name":"Chandra Devi"}'),
  ('c1000000-0000-0000-0000-000000000006', 'cmod-gauri@example.test', '{"name":"Gauri Devi"}');

-- Nitai, the Head and Gauri all start as Community Heads, because only those
-- three roles may put a notice up at all. Two of them will step down again.
update public.users
set role_id = (select roles.id from public.roles where roles.name = 'core')
where users.email in ('cmod-nitai@example.test', 'cmod-head@example.test',
                      'cmod-gauri@example.test');

-- Ordinary table rather than a temporary one, so reading it under the
-- authenticated role needs no assumptions about the temp schema. The whole
-- script is rolled back, so it never outlives the transaction.
create table public.moderation_test_ids (key text primary key, id uuid not null);
grant select, insert on public.moderation_test_ids to authenticated;

-- ---------------------------------------------------------------------------
-- 0. The ground this change stands on.
-- ---------------------------------------------------------------------------

do $$
declare
  v_holders text;
begin
  -- If a later migration widens services.manage_recurring, moderation of every
  -- thread on the board widens with it silently.
  select string_agg(roles.name, ',' order by roles.name) into v_holders
  from public.role_permissions
  join public.roles on roles.id = role_permissions.role_id
  where role_permissions.permission_key = 'services.manage_recurring';

  if v_holders is distinct from 'core,president,tech' then
    raise exception
      'services.manage_recurring is held by % — comment moderation assumes core, president, tech.',
      v_holders;
  end if;

  -- No new permission key was invented for this. A poster's authority comes
  -- from the notice being theirs, not from a key somebody can be handed.
  if exists (
    select 1 from public.role_permissions
    where role_permissions.permission_key like '%moderat%'
       or role_permissions.permission_key like '%comment%'
  ) then
    raise exception 'A separate comment moderation permission key was registered.';
  end if;
end;
$$;

-- The rule lives in one place, and both sides of it call that place. This is
-- the anti-drift assertion: a future edit that inlines the rule back into
-- either function — which is exactly how the guard and the flag came apart
-- before — fails here rather than in a devotee's hand.
do $$
declare
  v_def text;
  v_secdef boolean;
  v_volatile "char";
  v_overloads integer;
  v_name text;
begin
  if to_regprocedure('public.may_remove_announcement_comment(uuid)') is null then
    raise exception 'may_remove_announcement_comment(uuid) does not exist.';
  end if;

  select pg_proc.prosecdef, pg_proc.provolatile into v_secdef, v_volatile
  from pg_proc
  where pg_proc.oid = 'public.may_remove_announcement_comment(uuid)'::regprocedure;
  if not v_secdef then
    raise exception
      'may_remove_announcement_comment is not security definer, so it answers differently depending on who asks.';
  end if;
  if v_volatile = 'v' then
    raise exception 'may_remove_announcement_comment is volatile.';
  end if;

  v_def := pg_get_functiondef('public.delete_announcement_comment(uuid)'::regprocedure);
  if v_def !~ 'may_remove_announcement_comment' then
    raise exception
      'delete_announcement_comment no longer asks may_remove_announcement_comment; the guard has drifted from the flag.';
  end if;

  v_def := pg_get_functiondef('public.list_announcement_comments(uuid)'::regprocedure);
  if v_def !~ 'may_remove_announcement_comment' then
    raise exception
      'list_announcement_comments no longer asks may_remove_announcement_comment; can_remove has drifted from the guard.';
  end if;

  -- One of each, so no leftover overload can make a call ambiguous.
  foreach v_name in array array[
    'may_remove_announcement_comment',
    'delete_announcement_comment',
    'list_announcement_comments'
  ] loop
    select count(*)::integer into v_overloads
    from pg_proc
    join pg_namespace on pg_namespace.oid = pg_proc.pronamespace
    where pg_namespace.nspname = 'public' and pg_proc.proname = v_name;
    if v_overloads <> 1 then
      raise exception 'public.% has % overloads rather than 1.', v_name, v_overloads;
    end if;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- 1. Two notices go up, each by a different devotee, and both of those devotees
--    then step down to plain devotees.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
  v_ann public.announcements;
begin
  v_ann := public.create_announcement(
    'Janmashtami midnight arati',
    'The midnight arati begins at 11pm in the main hall. Prasadam follows.'
  );
  insert into public.moderation_test_ids values ('ann_a', v_ann.id);
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000006', true);
set local role authenticated;

do $$
declare
  v_ann public.announcements;
begin
  v_ann := public.create_announcement(
    'Parking lot closed Sunday',
    'Resurfacing. Please use the street parking on Ridge Avenue.'
  );
  insert into public.moderation_test_ids values ('ann_b', v_ann.id);
end;
$$;

reset role;

-- They step down. From here on, whatever either of them may do rests entirely
-- on the notice being theirs.
update public.users
set role_id = (select roles.id from public.roles where roles.name = 'devotee')
where users.email in ('cmod-nitai@example.test', 'cmod-gauri@example.test');

do $$
declare
  v_role text;
  v_person text;
begin
  foreach v_person in array array[
    'cmod-nitai@example.test', 'cmod-gauri@example.test',
    'cmod-asha@example.test', 'cmod-bhakta@example.test', 'cmod-chandra@example.test'
  ] loop
    select roles.name into v_role
    from public.users join public.roles on roles.id = users.role_id
    where users.email = v_person;
    if v_role <> 'devotee' then
      raise exception '% is a % rather than a plain devotee.', v_person, v_role;
    end if;
  end loop;

  -- And the notices survived the demotion with their posters' names on them.
  if (select announcements.posted_by from public.announcements
      where announcements.id = (select ids.id from public.moderation_test_ids ids
                                where ids.key = 'ann_a'))
     is distinct from 'c1000000-0000-0000-0000-000000000001'::uuid then
    raise exception 'Notice A is not attributed to Nitai.';
  end if;
  if (select announcements.posted_by from public.announcements
      where announcements.id = (select ids.id from public.moderation_test_ids ids
                                where ids.key = 'ann_b'))
     is distinct from 'c1000000-0000-0000-0000-000000000006'::uuid then
    raise exception 'Notice B is not attributed to Gauri.';
  end if;
end;
$$;

-- Asserted as themselves, through the very function the rule consults: neither
-- poster carries any temple-wide moderation right any more. Without this, every
-- assertion below about a poster would prove nothing about posting.
select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
begin
  if public.may_post_announcements() then
    raise exception 'Nitai still holds temple-wide announcement rights after stepping down.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000006', true);
set local role authenticated;

do $$
begin
  if public.may_post_announcements() then
    raise exception 'Gauri still holds temple-wide announcement rights after stepping down.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. A conversation under each notice.
--
--    Notice A:  a1  Asha, top level
--               a3  Bhakta   -> a1
--               a4  Chandra  -> a1
--               a5  Asha     -> a1
--               a2  Chandra, top level
--    Notice B:  b1  Asha, top level
--               b2  Chandra  -> b1
--
--    Both notices carry a comment by the same devotee (Asha) and a reply by the
--    same devotee (Chandra), on purpose: the only thing that differs between
--    the two threads is whose notice they hang under, which is the one variable
--    the scoping tests are allowed to turn.
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000003', true);
set local role authenticated;

do $$
declare
  v_a uuid;
  v_b uuid;
  v_comment public.announcement_comments;
begin
  select ids.id into v_a from public.moderation_test_ids ids where ids.key = 'ann_a';
  select ids.id into v_b from public.moderation_test_ids ids where ids.key = 'ann_b';

  v_comment := public.add_announcement_comment(v_a, 'Is that the main hall or the annexe?');
  insert into public.moderation_test_ids values ('a1', v_comment.id);

  v_comment := public.add_announcement_comment(v_b, 'Is the Ridge Avenue side open?');
  insert into public.moderation_test_ids values ('b1', v_comment.id);
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000004', true);
set local role authenticated;

do $$
declare
  v_a uuid;
  v_parent uuid;
  v_comment public.announcement_comments;
begin
  select ids.id into v_a from public.moderation_test_ids ids where ids.key = 'ann_a';
  select ids.id into v_parent from public.moderation_test_ids ids where ids.key = 'a1';
  v_comment := public.add_announcement_comment(v_a, 'Main hall, I asked yesterday.', v_parent);
  insert into public.moderation_test_ids values ('a3', v_comment.id);
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000005', true);
set local role authenticated;

do $$
declare
  v_a uuid;
  v_b uuid;
  v_parent uuid;
  v_comment public.announcement_comments;
begin
  select ids.id into v_a from public.moderation_test_ids ids where ids.key = 'ann_a';
  select ids.id into v_b from public.moderation_test_ids ids where ids.key = 'ann_b';
  select ids.id into v_parent from public.moderation_test_ids ids where ids.key = 'a1';

  v_comment := public.add_announcement_comment(v_a, 'Nonsense, it is always the annexe.', v_parent);
  insert into public.moderation_test_ids values ('a4', v_comment.id);

  v_comment := public.add_announcement_comment(v_a, 'Can I bring my mother?');
  insert into public.moderation_test_ids values ('a2', v_comment.id);

  select ids.id into v_parent from public.moderation_test_ids ids where ids.key = 'b1';
  v_comment := public.add_announcement_comment(v_b, 'It was shut last time too.', v_parent);
  insert into public.moderation_test_ids values ('b2', v_comment.id);
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000003', true);
set local role authenticated;

do $$
declare
  v_a uuid;
  v_parent uuid;
  v_comment public.announcement_comments;
begin
  select ids.id into v_a from public.moderation_test_ids ids where ids.key = 'ann_a';
  select ids.id into v_parent from public.moderation_test_ids ids where ids.key = 'a1';
  v_comment := public.add_announcement_comment(v_a, 'Thank you both.', v_parent);
  insert into public.moderation_test_ids values ('a5', v_comment.id);
end;
$$;

-- Both threads read as they should before anybody touches them. The shape is
-- captured here so that section 6 can prove a removal did not disturb it.
do $$
declare
  v_a uuid;
  v_row record;
  v_seen text;
begin
  select ids.id into v_a from public.moderation_test_ids ids where ids.key = 'ann_a';
  v_seen := '';
  for v_row in select * from public.list_announcement_comments(v_a) loop
    v_seen := v_seen || v_row.author_name
      || case when v_row.parent_comment_id is null then '' else '>' end || '|';
  end loop;
  if v_seen <> 'Asha Devi|Bhakta Das>|Chandra Devi>|Asha Devi>|Chandra Devi|' then
    raise exception 'Notice A''s thread reads %.', v_seen;
  end if;
end;
$$;

-- Everything queued to this point is the baseline. Section 7 proves that not
-- one removal below added to it.
reset role;
create table public.moderation_test_baseline as
select count(*)::integer as notifications from public.app_notifications;

-- ---------------------------------------------------------------------------
-- 3. can_remove, per viewer, over every comment on both notices.
--
--    The client draws its Remove action from this flag and nothing else, so it
--    is asserted exhaustively rather than sampled. Each row below is one
--    viewer's complete answer for one thread, in key order.
--
--    The two rows that carry this migration:
--      Nitai on notice A — true on every comment, including four he did not
--                          write, because the notice is his
--      Nitai on notice B — false on every comment, because that notice is not
--
--    The whole matrix is read under the authenticated role — the loop only
--    changes which devotee the session claims to be — so the grants are being
--    exercised alongside the rule.
-- ---------------------------------------------------------------------------

set local role authenticated;

do $$
declare
  v_a uuid;
  v_b uuid;
  v_viewer record;
  v_seen text;
begin
  select ids.id into v_a from public.moderation_test_ids ids where ids.key = 'ann_a';
  select ids.id into v_b from public.moderation_test_ids ids where ids.key = 'ann_b';

  for v_viewer in
    select * from (values
      -- Asha wrote a1 and a5, and b1 on the other notice.
      ('c1000000-0000-0000-0000-000000000003'::uuid, 'Asha',
       'a1=true a2=false a3=false a4=false a5=true', 'b1=true b2=false'),
      -- Bhakta wrote a3 and nothing else, anywhere.
      ('c1000000-0000-0000-0000-000000000004'::uuid, 'Bhakta',
       'a1=false a2=false a3=true a4=false a5=false', 'b1=false b2=false'),
      -- Chandra wrote a2, a4 and b2.
      ('c1000000-0000-0000-0000-000000000005'::uuid, 'Chandra',
       'a1=false a2=true a3=false a4=true a5=false', 'b1=false b2=true'),
      -- Nitai wrote none of them. Notice A is his and notice B is not.
      ('c1000000-0000-0000-0000-000000000001'::uuid, 'Nitai',
       'a1=true a2=true a3=true a4=true a5=true', 'b1=false b2=false'),
      -- Gauri, the same claim mirrored, so a rule that simply favours notice A
      -- cannot pass.
      ('c1000000-0000-0000-0000-000000000006'::uuid, 'Gauri',
       'a1=false a2=false a3=false a4=false a5=false', 'b1=true b2=true'),
      -- The Community Head: everything, everywhere, as before this change.
      ('c1000000-0000-0000-0000-000000000002'::uuid, 'the Community Head',
       'a1=true a2=true a3=true a4=true a5=true', 'b1=true b2=true')
    ) as viewers(id, who, expected_a, expected_b)
  loop
    perform set_config('request.jwt.claim.sub', v_viewer.id::text, true);

    select string_agg(ids.key || '=' || listed.can_remove::text, ' ' order by ids.key)
      into v_seen
    from public.list_announcement_comments(v_a) listed
    join public.moderation_test_ids ids on ids.id = listed.id;
    if v_seen is distinct from v_viewer.expected_a then
      raise exception 'can_remove on notice A for %: got [%], expected [%].',
        v_viewer.who, coalesce(v_seen, '(nothing)'), v_viewer.expected_a;
    end if;

    select string_agg(ids.key || '=' || listed.can_remove::text, ' ' order by ids.key)
      into v_seen
    from public.list_announcement_comments(v_b) listed
    join public.moderation_test_ids ids on ids.id = listed.id;
    if v_seen is distinct from v_viewer.expected_b then
      raise exception 'can_remove on notice B for %: got [%], expected [%].',
        v_viewer.who, coalesce(v_seen, '(nothing)'), v_viewer.expected_b;
    end if;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Everything the server must refuse.
--
--    Every one of these is attempted as the devotee who would really attempt
--    it, under the authenticated role, and every one of them is a case where
--    section 3 said can_remove was false. The guard and the flag are being held
--    against each other here.
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000005', true);
set local role authenticated;

do $$
declare
  v_message text;
begin
  -- A plain devotee reaching for somebody else's comment.
  v_message := null;
  begin
    perform public.delete_announcement_comment(
      (select ids.id from public.moderation_test_ids ids where ids.key = 'a1'));
  exception when others then
    v_message := sqlerrm;
  end;
  if v_message is null then
    raise exception 'A plain devotee removed somebody else''s comment.';
  end if;
  if v_message ~* '(constraint|null value|violates|permission denied)' then
    raise exception 'The refusal was unreadable: %', v_message;
  end if;
  if v_message !~* 'remove' then
    raise exception 'The refusal does not say what was refused: %', v_message;
  end if;

  -- And somebody else's reply.
  v_message := null;
  begin
    perform public.delete_announcement_comment(
      (select ids.id from public.moderation_test_ids ids where ids.key = 'a3'));
  exception when others then
    v_message := sqlerrm;
  end;
  if v_message is null then
    raise exception 'A plain devotee removed somebody else''s reply.';
  end if;
end;
$$;

-- The scoping test. Nitai posted notice A. Notice B is Gauri's, and neither the
-- comment nor the reply under it is his business.
reset role;
select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
  v_message text;
begin
  v_message := null;
  begin
    perform public.delete_announcement_comment(
      (select ids.id from public.moderation_test_ids ids where ids.key = 'b1'));
  exception when others then
    v_message := sqlerrm;
  end;
  if v_message is null then
    raise exception
      'Posting notice A let Nitai remove a comment on somebody else''s notice. A poster''s authority must not leave their own announcement.';
  end if;
  if v_message ~* '(constraint|null value|violates|permission denied)' then
    raise exception 'The scoping refusal was unreadable: %', v_message;
  end if;

  v_message := null;
  begin
    perform public.delete_announcement_comment(
      (select ids.id from public.moderation_test_ids ids where ids.key = 'b2'));
  exception when others then
    v_message := sqlerrm;
  end;
  if v_message is null then
    raise exception
      'Posting notice A let Nitai remove a reply on somebody else''s notice.';
  end if;
end;
$$;

-- Mirrored, so that a rule which happens to favour whichever notice was posted
-- first cannot slip through.
reset role;
select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000006', true);
set local role authenticated;

do $$
declare
  v_message text;
begin
  v_message := null;
  begin
    perform public.delete_announcement_comment(
      (select ids.id from public.moderation_test_ids ids where ids.key = 'a1'));
  exception when others then
    v_message := sqlerrm;
  end;
  if v_message is null then
    raise exception 'Gauri removed a comment on Nitai''s notice.';
  end if;

  v_message := null;
  begin
    perform public.delete_announcement_comment(
      (select ids.id from public.moderation_test_ids ids where ids.key = 'a4'));
  exception when others then
    v_message := sqlerrm;
  end;
  if v_message is null then
    raise exception 'Gauri removed a reply on Nitai''s notice.';
  end if;
end;
$$;

-- Nothing that was refused was written anyway.
reset role;

do $$
declare
  v_live integer;
begin
  select count(*)::integer into v_live
  from public.announcement_comments
  where announcement_comments.deleted_at is null;
  if v_live <> 7 then
    raise exception 'A refused removal took something down: % of 7 comments still stand.', v_live;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Everything the server must allow.
--
--    In order, so the counts below mean something:
--      Nitai removes a2  — the new power, on a top-level comment he did not
--                          write, under the notice he posted
--      Nitai removes a4  — the same, on a reply
--      Asha  removes a1  — an author still takes their own words down
--      Head  removes a3  — a Community Head still removes anybody's
--      Gauri removes b2  — the comment Nitai was refused four sections ago,
--                          taken down without argument by the devotee whose
--                          notice it is. This is what proves the refusal above
--                          was about scope and not about b2 being untouchable.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
  v_a uuid;
  v_a1 uuid;
  v_removed public.announcement_comments;
  v_row record;
  v_refused boolean;
begin
  select ids.id into v_a from public.moderation_test_ids ids where ids.key = 'ann_a';
  select ids.id into v_a1 from public.moderation_test_ids ids where ids.key = 'a1';

  v_removed := public.delete_announcement_comment(
    (select ids.id from public.moderation_test_ids ids where ids.key = 'a2'));
  if v_removed.deleted_at is null then
    raise exception 'The poster could not remove a comment on their own notice.';
  end if;
  if v_removed.deleted_by is distinct from 'c1000000-0000-0000-0000-000000000001'::uuid then
    raise exception 'The removal did not record the poster as the one who made it.';
  end if;

  -- The same authority reaches a reply, not only a top-level comment.
  v_removed := public.delete_announcement_comment(
    (select ids.id from public.moderation_test_ids ids where ids.key = 'a4'));
  if v_removed.deleted_at is null then
    raise exception 'The poster could not remove a reply on their own notice.';
  end if;
  if v_removed.parent_comment_id is distinct from v_a1 then
    raise exception 'The removed reply lost the comment it hung under.';
  end if;

  -- Already-removed rows are offered to nobody, not even to the poster who
  -- removed them a moment ago.
  select * into v_row from public.list_announcement_comments(v_a) listed
  where listed.id = (select ids.id from public.moderation_test_ids ids where ids.key = 'a2');
  if v_row.can_remove then
    raise exception 'A comment the poster already removed can be removed again.';
  end if;
  if v_row.body is not null then
    raise exception 'A removed comment still returns its words: %', v_row.body;
  end if;

  -- And a second attempt really is refused, not merely undrawn. Removing twice
  -- would rewrite deleted_by and the record would name the wrong person.
  v_refused := false;
  begin
    perform public.delete_announcement_comment(
      (select ids.id from public.moderation_test_ids ids where ids.key = 'a2'));
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A comment was removed twice.';
  end if;

  -- The comment two of its replies were taken from still shows the one left.
  select * into v_row from public.list_announcement_comments(v_a) listed
  where listed.id = v_a1;
  if v_row.reply_count <> 2 then
    raise exception 'Asha''s comment shows % replies rather than the 2 still standing.',
      v_row.reply_count;
  end if;
end;
$$;

-- An author still removes their own, and the replies beneath keep their words.
reset role;
select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000003', true);
set local role authenticated;

do $$
declare
  v_a uuid;
  v_a1 uuid;
  v_removed public.announcement_comments;
  v_row record;
begin
  select ids.id into v_a from public.moderation_test_ids ids where ids.key = 'ann_a';
  select ids.id into v_a1 from public.moderation_test_ids ids where ids.key = 'a1';

  v_removed := public.delete_announcement_comment(v_a1);
  if v_removed.deleted_at is null then
    raise exception 'An author could not remove their own comment.';
  end if;
  if v_removed.deleted_by is distinct from 'c1000000-0000-0000-0000-000000000003'::uuid then
    raise exception 'The author''s removal named somebody else.';
  end if;

  select * into v_row from public.list_announcement_comments(v_a) listed
  where listed.id = (select ids.id from public.moderation_test_ids ids where ids.key = 'a3');
  if v_row.body is distinct from 'Main hall, I asked yesterday.' then
    raise exception 'Removing a comment silenced a reply under it.';
  end if;
end;
$$;

-- A Community Head still removes anybody's, on a notice that is not theirs.
reset role;
select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_a uuid;
  v_removed public.announcement_comments;
  v_row record;
begin
  select ids.id into v_a from public.moderation_test_ids ids where ids.key = 'ann_a';

  v_removed := public.delete_announcement_comment(
    (select ids.id from public.moderation_test_ids ids where ids.key = 'a3'));
  if v_removed.deleted_at is null then
    raise exception 'A Community Head could not remove somebody else''s reply.';
  end if;
  if v_removed.deleted_by is distinct from 'c1000000-0000-0000-0000-000000000002'::uuid then
    raise exception 'The Community Head''s removal named somebody else.';
  end if;

  select * into v_row from public.list_announcement_comments(v_a) listed
  where listed.id = (select ids.id from public.moderation_test_ids ids where ids.key = 'a1');
  if v_row.reply_count <> 1 then
    raise exception 'The removed reply is still counted: % rather than 1.', v_row.reply_count;
  end if;
end;
$$;

-- The pair to the scoping refusal: the very comment Nitai could not touch comes
-- down when its own notice's poster asks.
reset role;
select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000006', true);
set local role authenticated;

do $$
declare
  v_removed public.announcement_comments;
begin
  v_removed := public.delete_announcement_comment(
    (select ids.id from public.moderation_test_ids ids where ids.key = 'b2'));
  if v_removed.deleted_at is null then
    raise exception 'The poster of notice B could not remove a reply on it.';
  end if;
  if v_removed.deleted_by is distinct from 'c1000000-0000-0000-0000-000000000006'::uuid then
    raise exception 'The removal on notice B named somebody else.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Four removals later, the thread still reads as a thread.
--
--    This is the whole reason removal is soft. "Thank you both" is an answer to
--    a question that is no longer on the board; delete the row outright and it
--    hangs under nothing.
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000004', true);
set local role authenticated;

do $$
declare
  v_a uuid;
  v_b uuid;
  v_row record;
  v_seen text;
  v_rows integer;
begin
  select ids.id into v_a from public.moderation_test_ids ids where ids.key = 'ann_a';
  select ids.id into v_b from public.moderation_test_ids ids where ids.key = 'ann_b';

  -- Same rows, same order, same names, same nesting as section 2 recorded
  -- before a single removal.
  v_seen := '';
  for v_row in select * from public.list_announcement_comments(v_a) loop
    v_seen := v_seen || v_row.author_name
      || case when v_row.parent_comment_id is null then '' else '>' end || '|';
  end loop;
  if v_seen <> 'Asha Devi|Bhakta Das>|Chandra Devi>|Asha Devi>|Chandra Devi|' then
    raise exception 'Four removals reshaped notice A''s thread: %.', v_seen;
  end if;

  select count(*)::integer into v_rows from public.list_announcement_comments(v_a);
  if v_rows <> 5 then
    raise exception 'Notice A''s thread has % rows rather than 5.', v_rows;
  end if;

  -- The removed ones kept their place and lost their words; the one still
  -- standing kept both.
  for v_row in select * from public.list_announcement_comments(v_a) loop
    if v_row.id in (
      select ids.id from public.moderation_test_ids ids
      where ids.key in ('a1', 'a2', 'a3', 'a4')
    ) then
      if v_row.body is not null then
        raise exception 'A removed comment still returns its words: %', v_row.body;
      end if;
      if v_row.deleted_at is null then
        raise exception 'A removed comment does not say it was removed.';
      end if;
      if v_row.author_name is null then
        raise exception 'A removed comment lost the shape of who wrote it.';
      end if;
      if v_row.can_remove then
        raise exception 'A removed comment is still offered for removal.';
      end if;
    else
      if v_row.body is distinct from 'Thank you both.' then
        raise exception 'The surviving reply reads %.', coalesce(v_row.body, '(nothing)');
      end if;
    end if;
  end loop;

  -- Notice B kept its shape too, with its own removal in place.
  select count(*)::integer into v_rows from public.list_announcement_comments(v_b);
  if v_rows <> 2 then
    raise exception 'Notice B''s thread has % rows rather than 2.', v_rows;
  end if;

  -- The board counts only what still stands.
  select * into v_row from public.list_announcements() listed where listed.id = v_a;
  if v_row.comment_count <> 1 then
    raise exception 'Notice A shows % comments rather than the 1 still standing.',
      v_row.comment_count;
  end if;
  select * into v_row from public.list_announcements() listed where listed.id = v_b;
  if v_row.comment_count <> 1 then
    raise exception 'Notice B shows % comments rather than the 1 still standing.',
      v_row.comment_count;
  end if;

  -- The words are unreachable rather than merely omitted: no query a devotee
  -- can phrase against the table returns what was taken down.
  if exists (
    select 1 from public.announcement_comments
    where announcement_comments.id in (
      select ids.id from public.moderation_test_ids ids
      where ids.key in ('a1', 'a2', 'a3', 'a4', 'b2')
    )
  ) then
    raise exception 'A devotee can still read a removed comment straight off the table.';
  end if;
end;
$$;

-- can_remove is false on every removed row for the two viewers with the widest
-- reach, so the flag agrees with the guard's refusal to remove twice.
do $$
declare
  v_a uuid;
  v_viewer uuid;
  v_offered integer;
begin
  select ids.id into v_a from public.moderation_test_ids ids where ids.key = 'ann_a';

  foreach v_viewer in array array[
    'c1000000-0000-0000-0000-000000000001'::uuid,  -- the poster of notice A
    'c1000000-0000-0000-0000-000000000002'::uuid   -- the Community Head
  ] loop
    perform set_config('request.jwt.claim.sub', v_viewer::text, true);
    select count(*)::integer into v_offered
    from public.list_announcement_comments(v_a) listed
    where listed.can_remove;
    if v_offered <> 1 then
      raise exception
        'Viewer % is offered % removable comments rather than the 1 still standing.',
        v_viewer, v_offered;
    end if;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. A removal is not news anybody asked for.
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', '', true);

do $$
declare
  v_growth integer;
begin
  select count(*)::integer
    - (select baseline.notifications from public.moderation_test_baseline baseline)
    into v_growth
  from public.app_notifications;
  if v_growth <> 0 then
    raise exception 'Five removals queued % notifications. A removal tells nobody.', v_growth;
  end if;
end;
$$;

do $$
begin
  raise notice 'all announcement comment moderation checks passed';
end;
$$;

select 'announcement comment moderation verification passed' as result;

rollback;
