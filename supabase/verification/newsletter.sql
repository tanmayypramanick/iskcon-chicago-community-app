-- Functional verification for 202608040045_newsletter.sql.
--
-- Rolled back at the end. Every local is prefixed v_ so it can never shadow a
-- column name. Anything that must be refused is attempted as the devotee who
-- would really attempt it, under `set local role authenticated`, so the row
-- level security policies and the column grants are the thing being tested
-- rather than superuser rights quietly waving everything through. Notification
-- assertions are made after `reset role`, because a devotee cannot — and should
-- not be able to — read somebody else's inbox.
--
-- The five people in this script:
--   President  ...0001  holds app.view_all; may post, review and appoint
--   Devotee A  ...0002  an ordinary devotee, appointed editor half way through
--                       and revoked again at the end. The whole feature in one
--                       person.
--   Devotee B  ...0003  sends stories in; must never see anybody else's
--   Tech       ...0004  the other holder of app.view_all
--   Core       ...0005  the strongest role that must still be shut out
--
-- The final row must read: newsletter verification passed

begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('c1000000-0000-0000-0000-000000000001', 'nl-president@example.test', '{"name":"Nl President"}'),
  ('c1000000-0000-0000-0000-000000000002', 'nl-devotee-a@example.test', '{"name":"Nl Devotee A"}'),
  ('c1000000-0000-0000-0000-000000000003', 'nl-devotee-b@example.test', '{"name":"Nl Devotee B"}'),
  ('c1000000-0000-0000-0000-000000000004', 'nl-tech@example.test', '{"name":"Nl Tech"}'),
  ('c1000000-0000-0000-0000-000000000005', 'nl-core@example.test', '{"name":"Nl Core"}');

update public.users
set role_id = (select roles.id from public.roles where roles.name = 'president')
where email = 'nl-president@example.test';

update public.users
set role_id = (select roles.id from public.roles where roles.name = 'tech')
where email = 'nl-tech@example.test';

update public.users
set role_id = (select roles.id from public.roles where roles.name = 'core')
where email = 'nl-core@example.test';

update public.users
set photo_url = 'https://project.supabase.co/storage/v1/object/public/devotee-photos/b.jpg'
where email = 'nl-devotee-b@example.test';

-- Ordinary table rather than a temporary one, so reading it under the
-- authenticated role needs no assumptions about the temp schema. The whole
-- script is rolled back, so it never outlives the transaction.
create table public.newsletter_test_ids (key text primary key, id uuid not null);
grant select, insert on public.newsletter_test_ids to authenticated;

-- ---------------------------------------------------------------------------
-- 0. No new rung was added to the role ladder, and no new permission key was
--    invented for the newsletter. The appointment is a grant, not a rank —
--    which is the one thing the temple asked for and the one thing that would
--    be silently undone by a later migration adding 'editor' to the ladder.
-- ---------------------------------------------------------------------------

do $$
declare
  v_holders text;
  v_roles text;
begin
  select string_agg(roles.name, ',' order by roles.name) into v_holders
  from public.role_permissions
  join public.roles on roles.id = role_permissions.role_id
  where role_permissions.permission_key = 'app.view_all';

  if v_holders is distinct from 'president,tech' then
    raise exception
      'app.view_all is held by % — the newsletter assumes president, tech.', v_holders;
  end if;

  select string_agg(roles.name, ',' order by roles.name) into v_roles
  from public.roles;
  if v_roles is distinct from 'core,devotee,president,tech,volunteer' then
    raise exception 'The role ladder is now % — a rung was added.', v_roles;
  end if;

  if exists (
    select 1 from public.role_permissions
    where role_permissions.permission_key like '%newsletter%'
  ) then
    raise exception 'A separate newsletter permission key was registered.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 0b. Every notification kind that existed before this migration still exists
--     after it.
--
--     app_notifications_kind_check cannot be altered, only dropped and
--     recreated, so each migration that adds a kind has to restate the whole
--     list — and a migration that restates it from an older copy silently
--     outlaws every kind added since. That has broken this database three
--     times. The two new kinds are checked alongside them, so the constraint
--     and src/features/notifications/types.ts can be read against one list.
--
--     Each kind is inserted for real rather than pattern-matched against
--     pg_get_constraintdef, because what matters is whether the database will
--     accept the row at 3am, not whether the text of the constraint mentions it.
-- ---------------------------------------------------------------------------

do $$
declare
  v_kind text;
  v_missing text[] := '{}';
begin
  foreach v_kind in array array[
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
    'newsletter_posted',
    'newsletter_reviewed',
    'remote'
  ]
  loop
    begin
      insert into public.app_notifications (user_id, kind, title, body)
      values ('c1000000-0000-0000-0000-000000000001', v_kind, 'probe', 'probe');
    exception when check_violation then
      v_missing := v_missing || v_kind;
    end;
  end loop;

  if cardinality(v_missing) > 0 then
    raise exception
      'The kind constraint no longer accepts %. It was restated from an older copy.',
      array_to_string(v_missing, ', ');
  end if;

  -- The probes must not be mistaken for anything this feature sent.
  delete from public.app_notifications where title = 'probe' and body = 'probe';
end;
$$;

-- ---------------------------------------------------------------------------
-- 1. A plain devotee cannot post, and neither can a Community Head — the
--    strongest role below the two office holders.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_message text := null;
begin
  if public.may_manage_newsletter() then
    raise exception 'A plain devotee may manage the newsletter before being appointed.';
  end if;

  begin
    perform public.post_newsletter(
      'August 2026',
      date '2026-08-01',
      'https://project.supabase.co/storage/v1/object/public/newsletter-files/'
        || 'c1000000-0000-0000-0000-000000000002/august.pdf'
    );
  exception when others then
    v_message := sqlerrm;
  end;

  if v_message is null then
    raise exception 'A plain devotee posted the newsletter.';
  end if;
  if v_message not like '%President%' then
    raise exception 'Refusing a plain devotee said "%", not the readable guard.', v_message;
  end if;
  if exists (select 1 from public.newsletters) then
    raise exception 'A refused post still wrote a newsletter row.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000005', true);
set local role authenticated;

do $$
declare
  v_refused boolean := false;
begin
  if public.may_manage_newsletter() then
    raise exception 'A Community Head may manage the newsletter.';
  end if;

  begin
    perform public.post_newsletter(
      'August 2026',
      date '2026-08-01',
      'https://project.supabase.co/storage/v1/object/public/newsletter-files/'
        || 'c1000000-0000-0000-0000-000000000005/august.pdf'
    );
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A Community Head posted the newsletter.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. The President can, the fields survive the round trip, the month is pinned
--    to the first, and every other devotee is told.
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
  v_posted public.newsletters;
begin
  -- Sent as the 17th, which is the day the editor sat down. It means August.
  v_posted := public.post_newsletter(
    '  August 2026  ',
    date '2026-08-17',
    'https://project.supabase.co/storage/v1/object/public/newsletter-files/'
      || 'c1000000-0000-0000-0000-000000000001/august.pdf',
    'https://project.supabase.co/storage/v1/object/public/message-images/'
      || 'c1000000-0000-0000-0000-000000000001/august-cover.jpg',
    '  Janmashtami special.  '
  );

  if v_posted.id is null then
    raise exception 'The President could not post the newsletter.';
  end if;
  if v_posted.title <> 'August 2026' then
    raise exception 'The title came back as [%].', v_posted.title;
  end if;
  if v_posted.month <> date '2026-08-01' then
    raise exception 'The month was stored as % rather than the first of August.', v_posted.month;
  end if;
  if v_posted.file_url is null or v_posted.cover_image_url is null then
    raise exception 'The file or the cover was dropped.';
  end if;
  if v_posted.notes <> 'Janmashtami special.' then
    raise exception 'The notes were not trimmed: [%].', v_posted.notes;
  end if;
  if v_posted.posted_by <> 'c1000000-0000-0000-0000-000000000001' then
    raise exception 'The newsletter did not record who posted it.';
  end if;

  insert into public.newsletter_test_ids values ('august', v_posted.id);
end;
$$;

reset role;

do $$
declare
  v_rows integer;
  v_august uuid := (select id from public.newsletter_test_ids where key = 'august');
begin
  select count(*)::integer into v_rows
  from public.app_notifications
  where app_notifications.kind = 'newsletter_posted'
    and app_notifications.data ->> 'newsletterId' = v_august::text;
  -- Five devotees, the poster excluded.
  if v_rows <> 4 then
    raise exception 'Posting the newsletter told % devotees rather than 4.', v_rows;
  end if;

  if exists (
    select 1 from public.app_notifications
    where app_notifications.kind = 'newsletter_posted'
      and app_notifications.data ->> 'newsletterId' = v_august::text
      and app_notifications.user_id = 'c1000000-0000-0000-0000-000000000001'
  ) then
    raise exception 'The poster was notified about their own newsletter.';
  end if;

  if not exists (
    select 1 from public.app_notifications
    where app_notifications.kind = 'newsletter_posted'
      and app_notifications.user_id = 'c1000000-0000-0000-0000-000000000003'
      and app_notifications.body like '%Nl President%'
      and app_notifications.body like '%August 2026%'
  ) then
    raise exception 'The notification did not say who posted what.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Every devotee reads every issue — through the function and straight at
--    the table, which is where a client using PostgREST would try. None of them
--    is offered a delete button they could not use.
-- ---------------------------------------------------------------------------

do $$
declare
  v_who record;
  v_row record;
  v_rows integer;
begin
  for v_who in
    select * from (values
      ('c1000000-0000-0000-0000-000000000002'::uuid, 'a plain devotee'),
      ('c1000000-0000-0000-0000-000000000003'::uuid, 'another devotee'),
      ('c1000000-0000-0000-0000-000000000005'::uuid, 'a Community Head')
    ) as reader(id, label)
  loop
    perform set_config('request.jwt.claim.sub', v_who.id::text, true);
    -- Inside the block, so the policy is the thing being read rather than the
    -- owner's right to ignore it. Postgres reverts a SET made inside a DO block
    -- when the block ends, which is why it is re-issued each time round.
    execute 'set local role authenticated';

    select count(*)::integer into v_rows from public.newsletters;
    if v_rows <> 1 then
      raise exception '% sees % newsletters at the table rather than 1.',
        v_who.label, v_rows;
    end if;

    select * into v_row from public.list_newsletters();
    if v_row.id is null then
      raise exception '% cannot read the newsletter.', v_who.label;
    end if;
    if v_row.file_url is null then
      raise exception '% cannot download the newsletter.', v_who.label;
    end if;
    if v_row.posted_by_name is distinct from 'Nl President' then
      raise exception '% sees the poster as [%].', v_who.label, v_row.posted_by_name;
    end if;
    if v_row.can_delete or v_row.can_manage then
      raise exception '% was offered the newsletter controls.', v_who.label;
    end if;
  end loop;
end;
$$;

-- And cannot take it down either.
select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_refused boolean := false;
  v_august uuid := (select id from public.newsletter_test_ids where key = 'august');
begin
  begin
    perform public.delete_newsletter(v_august);
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A plain devotee deleted the newsletter.';
  end if;

  -- Nor straight at the table.
  v_refused := false;
  begin
    delete from public.newsletters where newsletters.id = v_august;
  exception when others then
    v_refused := true;
  end;
  if not exists (select 1 from public.newsletters where newsletters.id = v_august) then
    raise exception 'A plain devotee deleted the newsletter row directly.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Only a holder of app.view_all may appoint. Not a devotee, not a Community
--    Head, and — the interesting one — not an editor either, or the grant would
--    stop meaning "the President asked this person".
-- ---------------------------------------------------------------------------

do $$
declare
  v_message text := null;
begin
  begin
    perform public.appoint_newsletter_editor('c1000000-0000-0000-0000-000000000002');
  exception when others then
    v_message := sqlerrm;
  end;
  if v_message is null then
    raise exception 'A plain devotee appointed themselves a newsletter editor.';
  end if;
  if v_message not like '%President%' then
    raise exception 'Refusing a plain devotee said "%", not the readable guard.', v_message;
  end if;
  if exists (select 1 from public.newsletter_editors) then
    raise exception 'A refused appointment still wrote a grant.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000005', true);
set local role authenticated;

do $$
declare
  v_refused boolean := false;
begin
  begin
    perform public.appoint_newsletter_editor('c1000000-0000-0000-0000-000000000005');
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A Community Head appointed a newsletter editor.';
  end if;

  -- Writing straight at the table is not a way round the RPC.
  v_refused := false;
  begin
    insert into public.newsletter_editors (devotee_id)
    values ('c1000000-0000-0000-0000-000000000005');
  exception when others then
    v_refused := true;
  end;
  if exists (select 1 from public.newsletter_editors) then
    raise exception 'A Community Head made themselves an editor at the table.';
  end if;
end;
$$;

-- The President appoints devotee A, who remains an ordinary devotee.
reset role;
select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
  v_grant public.newsletter_editors;
  v_again public.newsletter_editors;
begin
  v_grant := public.appoint_newsletter_editor('c1000000-0000-0000-0000-000000000002');
  if v_grant.devotee_id <> 'c1000000-0000-0000-0000-000000000002' then
    raise exception 'The appointment was filed against %.', v_grant.devotee_id;
  end if;
  if v_grant.appointed_by <> 'c1000000-0000-0000-0000-000000000001' then
    raise exception 'The appointment did not record who made it.';
  end if;
  if v_grant.appointed_at is null then
    raise exception 'The appointment has no date on it.';
  end if;

  -- Appointing twice is a question, not an error, and must not reset the date.
  v_again := public.appoint_newsletter_editor('c1000000-0000-0000-0000-000000000002');
  if v_again.appointed_at is distinct from v_grant.appointed_at then
    raise exception 'Re-appointing moved the date from % to %.',
      v_grant.appointed_at, v_again.appointed_at;
  end if;
  if (select count(*) from public.newsletter_editors) <> 1 then
    raise exception 'Re-appointing wrote a second grant.';
  end if;

  -- Somebody who is not a devotee at all.
  declare
    v_message text := null;
  begin
    begin
      perform public.appoint_newsletter_editor('c1000000-0000-0000-0000-0000000000ff');
    exception when others then
      v_message := sqlerrm;
    end;
    if v_message is null then
      raise exception 'A stranger was appointed a newsletter editor.';
    end if;
    if v_message not like '%could not be found%' then
      raise exception 'Appointing a stranger was refused with "%".', v_message;
    end if;
  end;
end;
$$;

-- The role ladder did not move under devotee A.
reset role;

do $$
declare
  v_role text;
begin
  select roles.name into v_role
  from public.users
  join public.roles on roles.id = users.role_id
  where users.id = 'c1000000-0000-0000-0000-000000000002';
  if v_role <> 'devotee' then
    raise exception 'Appointing an editor changed their role to %.', v_role;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. The appointed editor — still an ordinary devotee — can post. That is the
--    feature the temple asked for.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_posted public.newsletters;
  v_row record;
begin
  if not public.may_manage_newsletter() then
    raise exception 'An appointed editor may not manage the newsletter.';
  end if;
  if public.may_appoint_newsletter_editor() then
    raise exception 'An appointed editor can appoint further editors.';
  end if;

  v_posted := public.post_newsletter(
    'September 2026',
    date '2026-09-01',
    'https://project.supabase.co/storage/v1/object/public/newsletter-files/'
      || 'c1000000-0000-0000-0000-000000000002/september.pdf'
  );
  if v_posted.id is null then
    raise exception 'An appointed editor could not post the newsletter.';
  end if;
  insert into public.newsletter_test_ids values ('september', v_posted.id);

  -- Newest month first, and the controls are now offered.
  select * into v_row from public.list_newsletters() limit 1;
  if v_row.month <> date '2026-09-01' then
    raise exception 'list_newsletters is not newest month first; the top is %.', v_row.month;
  end if;
  if not v_row.can_delete or not v_row.can_manage then
    raise exception 'An appointed editor was not offered the newsletter controls.';
  end if;
end;
$$;

-- An editor can neither appoint another editor nor revoke one — including
-- themselves, which is the loophole that would let an editor decide when they
-- stop being one.
do $$
declare
  v_refused boolean := false;
begin
  begin
    perform public.appoint_newsletter_editor('c1000000-0000-0000-0000-000000000003');
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'An appointed editor appointed another editor.';
  end if;
  if (select count(*) from public.newsletter_editors) <> 1 then
    raise exception 'An editor widened the editor list.';
  end if;

  v_refused := false;
  begin
    perform public.revoke_newsletter_editor('c1000000-0000-0000-0000-000000000002');
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'An appointed editor revoked an appointment.';
  end if;
  if not public.may_manage_newsletter() then
    raise exception 'An editor revoked their own appointment.';
  end if;

  -- Nor by deleting the grant at the table.
  v_refused := false;
  begin
    delete from public.newsletter_editors
    where newsletter_editors.devotee_id = 'c1000000-0000-0000-0000-000000000002';
  exception when others then
    v_refused := true;
  end;
  if (select count(*) from public.newsletter_editors) <> 1 then
    raise exception 'An editor deleted a grant straight from the table.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. A file from somewhere else is refused, on every column that holds one.
-- ---------------------------------------------------------------------------

do $$
declare
  v_case record;
  v_message text;
  v_before integer;
begin
  select count(*)::integer into v_before from public.newsletters;

  for v_case in
    select * from (values
      ('a foreign host',
       'https://evil.example.com/storage/v1/object/public/newsletter-files/x.pdf'),
      ('a foreign host wearing the path',
       'https://tracker.example.net/newsletter-files/x.pdf'),
      ('plain http',
       'http://project.supabase.co/storage/v1/object/public/newsletter-files/x.pdf'),
      ('the wrong bucket',
       'https://project.supabase.co/storage/v1/object/public/devotee-photos/x.pdf'),
      ('a bare url', 'https://example.com/newsletter.pdf')
    ) as bad(label, url)
  loop
    v_message := null;
    begin
      perform public.post_newsletter('October 2026', date '2026-10-01', v_case.url);
    exception when others then
      v_message := sqlerrm;
    end;
    if v_message is null then
      raise exception 'post_newsletter accepted % as the file.', v_case.label;
    end if;
    if v_message not like '%uploaded through the app%' then
      raise exception 'Refusing % said "%", not the readable guard.', v_case.label, v_message;
    end if;
  end loop;

  -- The cover image is checked too, and against the picture bucket.
  v_message := null;
  begin
    perform public.post_newsletter(
      'October 2026', date '2026-10-01',
      'https://project.supabase.co/storage/v1/object/public/newsletter-files/'
        || 'c1000000-0000-0000-0000-000000000002/october.pdf',
      'https://evil.example.com/tracker.gif'
    );
  exception when others then
    v_message := sqlerrm;
  end;
  if v_message is null then
    raise exception 'post_newsletter accepted a foreign-host cover image.';
  end if;
  if v_message not like '%cover image%' then
    raise exception 'Refusing a foreign cover said "%".', v_message;
  end if;

  if (select count(*)::integer from public.newsletters) <> v_before then
    raise exception 'A refused post still wrote a newsletter row.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Any devotee can send in a story: text, up to five photographs, and a
--    document. A sixth photograph is refused; empty slots are not an error.
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000003', true);
set local role authenticated;

do $$
declare
  v_sent public.newsletter_submissions;
  v_prefix text :=
    'https://project.supabase.co/storage/v1/object/public/message-images/'
    || 'c1000000-0000-0000-0000-000000000003/';
  v_message text;
begin
  v_sent := public.submit_newsletter_story(
    '  Our family''s first Ratha Yatra, and what the children made of it.  ',
    array[v_prefix || '1.jpg', v_prefix || '2.jpg', v_prefix || '3.jpg',
          v_prefix || '4.jpg', v_prefix || '5.jpg'],
    'https://project.supabase.co/storage/v1/object/public/newsletter-files/'
      || 'c1000000-0000-0000-0000-000000000003/story.pdf'
  );

  if v_sent.id is null then
    raise exception 'A devotee could not send a story.';
  end if;
  if v_sent.devotee_id <> 'c1000000-0000-0000-0000-000000000003' then
    raise exception 'The story was filed against the wrong devotee.';
  end if;
  if v_sent.body <> 'Our family''s first Ratha Yatra, and what the children made of it.' then
    raise exception 'The body was not trimmed: [%].', v_sent.body;
  end if;
  if cardinality(v_sent.image_urls) <> 5 then
    raise exception 'Five photographs arrived as %.', cardinality(v_sent.image_urls);
  end if;
  if v_sent.image_urls[1] <> v_prefix || '1.jpg'
     or v_sent.image_urls[5] <> v_prefix || '5.jpg' then
    raise exception 'The photographs came back out of order.';
  end if;
  if v_sent.file_url is null then
    raise exception 'The document was dropped.';
  end if;
  if v_sent.status <> 'new' then
    raise exception 'A new story arrived as %.', v_sent.status;
  end if;
  if v_sent.reply is not null or v_sent.replied_by is not null
     or v_sent.replied_at is not null then
    raise exception 'A new story arrived already answered.';
  end if;
  insert into public.newsletter_test_ids values ('ratha-yatra', v_sent.id);

  -- Six is one too many, and the refusal says so.
  v_message := null;
  begin
    perform public.submit_newsletter_story(
      'Six photographs.',
      array[v_prefix || '1.jpg', v_prefix || '2.jpg', v_prefix || '3.jpg',
            v_prefix || '4.jpg', v_prefix || '5.jpg', v_prefix || '6.jpg']
    );
  exception when others then
    v_message := sqlerrm;
  end;
  if v_message is null then
    raise exception 'A story with six photographs was accepted.';
  end if;
  if v_message not like '%up to 5 photos%' then
    raise exception 'Refusing six photographs said "%".', v_message;
  end if;

  -- Blank slots left by a picker are dropped, not counted and not refused.
  v_sent := public.submit_newsletter_story(
    'Two photographs and three empty slots.',
    array[v_prefix || '1.jpg', '', '   ', v_prefix || '2.jpg', null]
  );
  if cardinality(v_sent.image_urls) <> 2 then
    raise exception 'Empty picker slots were stored: % photographs.',
      cardinality(v_sent.image_urls);
  end if;
  insert into public.newsletter_test_ids values ('two-photos', v_sent.id);

  -- No photographs at all is a perfectly good story.
  v_sent := public.submit_newsletter_story('Just words this time.');
  if cardinality(v_sent.image_urls) <> 0 then
    raise exception 'A wordless-attachment story invented photographs.';
  end if;
  if v_sent.file_url is not null then
    raise exception 'A story with no document invented one.';
  end if;
  insert into public.newsletter_test_ids values ('words-only', v_sent.id);
end;
$$;

-- A blank story, and attachments from somewhere else, are refused.
do $$
declare
  v_case record;
  v_message text;
  v_before integer;
begin
  select count(*)::integer into v_before from public.newsletter_submissions;

  for v_case in
    select * from (values
      ('an empty body', ''),
      ('a whitespace body', '   '),
      ('a newline-only body', E'\n\n'),
      ('a null body', null)
    ) as bad(label, body)
  loop
    v_message := null;
    begin
      perform public.submit_newsletter_story(v_case.body);
    exception when others then
      v_message := sqlerrm;
    end;
    if v_message is null then
      raise exception 'submit_newsletter_story accepted %.', v_case.label;
    end if;
    if v_message not like '%write your story%' then
      raise exception 'Refusing % said "%", not the readable guard.', v_case.label, v_message;
    end if;
  end loop;

  v_message := null;
  begin
    perform public.submit_newsletter_story(
      'A photograph from elsewhere.',
      array['https://evil.example.com/pixel.gif']
    );
  exception when others then
    v_message := sqlerrm;
  end;
  if v_message is null then
    raise exception 'A foreign-host story photograph was accepted.';
  end if;
  if v_message not like '%uploaded through the app%' then
    raise exception 'Refusing a foreign photograph said "%".', v_message;
  end if;

  -- One good photograph beside one bad one does not launder the bad one.
  v_message := null;
  begin
    perform public.submit_newsletter_story(
      'One of each.',
      array[
        'https://project.supabase.co/storage/v1/object/public/message-images/x/1.jpg',
        'https://evil.example.com/pixel.gif'
      ]
    );
  exception when others then
    v_message := sqlerrm;
  end;
  if v_message is null then
    raise exception 'A foreign photograph hidden behind a good one was accepted.';
  end if;

  v_message := null;
  begin
    perform public.submit_newsletter_story(
      'A document from elsewhere.', null, 'https://evil.example.com/payload.pdf'
    );
  exception when others then
    v_message := sqlerrm;
  end;
  if v_message is null then
    raise exception 'A foreign-host story document was accepted.';
  end if;
  if v_message not like '%uploaded through the app%' then
    raise exception 'Refusing a foreign document said "%".', v_message;
  end if;

  if (select count(*)::integer from public.newsletter_submissions) <> v_before then
    raise exception 'A refused story still wrote a row.';
  end if;
end;
$$;

-- The ceiling is on the table, not only in the function: even a superuser
-- writing straight at it cannot store a sixth photograph.
reset role;

do $$
declare
  v_refused boolean := false;
begin
  begin
    insert into public.newsletter_submissions (devotee_id, body, image_urls)
    values (
      'c1000000-0000-0000-0000-000000000003',
      'Six, at the table.',
      array['a', 'b', 'c', 'd', 'e', 'f']
    );
  exception when check_violation then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'The five-photograph ceiling is not on the table.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. A devotee sees their own submissions and nobody else's — through the
--    function and straight at the table. Devotee A, the editor, has one of
--    their own so there is something for B not to see.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_sent public.newsletter_submissions;
begin
  v_sent := public.submit_newsletter_story('A note from the editor''s own hand.');
  insert into public.newsletter_test_ids values ('editors-own', v_sent.id);
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000003', true);
set local role authenticated;

do $$
declare
  v_rows integer;
  v_editors_own uuid := (select id from public.newsletter_test_ids where key = 'editors-own');
begin
  select count(*)::integer into v_rows from public.list_my_newsletter_submissions();
  if v_rows <> 3 then
    raise exception 'Devotee B sees % of their own stories rather than 3.', v_rows;
  end if;

  if exists (
    select 1 from public.list_my_newsletter_submissions() mine
    where mine.body like '%editor''s own hand%'
  ) then
    raise exception 'list_my_newsletter_submissions handed devotee B somebody else''s story.';
  end if;

  if exists (select 1 from public.list_my_newsletter_submissions() mine where mine.can_manage) then
    raise exception 'A plain devotee was told they may manage the newsletter.';
  end if;

  -- Straight at the table, by id and unfiltered.
  select count(*)::integer into v_rows
  from public.newsletter_submissions
  where newsletter_submissions.id = v_editors_own;
  if v_rows <> 0 then
    raise exception 'Devotee B read the editor''s story row directly.';
  end if;

  select count(*)::integer into v_rows from public.newsletter_submissions;
  if v_rows <> 3 then
    raise exception 'Devotee B can see % submission rows rather than 3.', v_rows;
  end if;

  -- And is handed nothing by the editor's queue.
  select count(*)::integer into v_rows from public.list_all_newsletter_submissions();
  if v_rows <> 0 then
    raise exception 'list_all_newsletter_submissions handed devotee B % rows.', v_rows;
  end if;

  -- Nor the editor list, through the function or at the table. Who the
  -- President has asked to do a job is the President's business.
  select count(*)::integer into v_rows from public.list_newsletter_editors();
  if v_rows <> 0 then
    raise exception 'A plain devotee read the newsletter editor list.';
  end if;
  select count(*)::integer into v_rows from public.newsletter_editors;
  if v_rows <> 0 then
    raise exception 'A plain devotee read % rows of the editor table.', v_rows;
  end if;
end;
$$;

-- A Community Head is shut out of the queue too.
reset role;
select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000005', true);
set local role authenticated;

do $$
declare
  v_rows integer;
begin
  select count(*)::integer into v_rows from public.list_all_newsletter_submissions();
  if v_rows <> 0 then
    raise exception 'A Community Head saw % newsletter submissions.', v_rows;
  end if;
  select count(*)::integer into v_rows from public.newsletter_submissions;
  if v_rows <> 0 then
    raise exception 'A Community Head read % submission rows at the table.', v_rows;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 9. The editor sees all of them, with the photographs, the document, and the
--    devotee behind them.
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_rows integer;
  v_total integer;
  v_row record;
  v_previous timestamptz;
  v_ratha uuid := (select id from public.newsletter_test_ids where key = 'ratha-yatra');
begin
  select count(*)::integer into v_total from public.newsletter_submissions;
  select count(*)::integer into v_rows from public.list_all_newsletter_submissions();
  if v_rows <> v_total or v_total <> 4 then
    raise exception 'The editor saw % of % submissions.', v_rows, v_total;
  end if;

  select * into v_row
  from public.list_all_newsletter_submissions() queue
  where queue.id = v_ratha;

  if v_row.devotee_name is distinct from 'Nl Devotee B' then
    raise exception 'The submitter came back as [%].', v_row.devotee_name;
  end if;
  if v_row.devotee_photo_url is null then
    raise exception 'The submitter''s photo was dropped.';
  end if;
  if cardinality(v_row.image_urls) <> 5 then
    raise exception 'The editor sees % photographs rather than 5.',
      cardinality(v_row.image_urls);
  end if;
  if v_row.file_url is null then
    raise exception 'The editor cannot download the story document.';
  end if;
  if not v_row.can_manage then
    raise exception 'The editor was told they may not manage the newsletter.';
  end if;

  -- Newest first, so the editor works the top of the queue.
  v_previous := null;
  for v_row in select * from public.list_all_newsletter_submissions() loop
    if v_previous is not null and v_row.created_at > v_previous then
      raise exception 'list_all_newsletter_submissions is not newest first.';
    end if;
    v_previous := v_row.created_at;
  end loop;

  -- And can see who else is on the team, without being able to change it.
  select count(*)::integer into v_rows from public.list_newsletter_editors();
  if v_rows <> 1 then
    raise exception 'The editor sees % editors rather than 1.', v_rows;
  end if;
  select * into v_row from public.list_newsletter_editors();
  if v_row.devotee_name is distinct from 'Nl Devotee A'
     or v_row.appointed_by_name is distinct from 'Nl President' then
    raise exception 'The editor list reads % appointed by %.',
      v_row.devotee_name, v_row.appointed_by_name;
  end if;
  if v_row.can_revoke then
    raise exception 'An editor was offered a way to revoke an appointment.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 10. The editor reviews, the submitter is told, and the submitter can read the
--     reply against their own story.
-- ---------------------------------------------------------------------------

do $$
declare
  v_reviewed public.newsletter_submissions;
  v_ratha uuid := (select id from public.newsletter_test_ids where key = 'ratha-yatra');
begin
  v_reviewed := public.review_newsletter_submission(
    v_ratha, '  Thank you — we will run this in September.  '
  );

  if v_reviewed.status <> 'reviewed' then
    raise exception 'Reviewing left the status at %.', v_reviewed.status;
  end if;
  if v_reviewed.reply is distinct from 'Thank you — we will run this in September.' then
    raise exception 'The reply was stored as [%].', v_reviewed.reply;
  end if;
  if v_reviewed.replied_by is distinct from 'c1000000-0000-0000-0000-000000000002'::uuid then
    raise exception 'The reply was attributed to %.', v_reviewed.replied_by;
  end if;
  if v_reviewed.replied_at is null then
    raise exception 'A reviewed story has no replied_at.';
  end if;

  -- Reviewing one story must not touch another.
  if (select status from public.newsletter_submissions
      where newsletter_submissions.id
            = (select id from public.newsletter_test_ids where key = 'two-photos'))
     <> 'new' then
    raise exception 'Reviewing one story marked another reviewed.';
  end if;
end;
$$;

reset role;

do $$
declare
  v_notification record;
  v_ratha uuid := (select id from public.newsletter_test_ids where key = 'ratha-yatra');
begin
  select * into v_notification
  from public.app_notifications
  where app_notifications.user_id = 'c1000000-0000-0000-0000-000000000003'
    and app_notifications.kind = 'newsletter_reviewed'
    and app_notifications.data ->> 'submissionId' = v_ratha::text;

  if v_notification.id is null then
    raise exception 'The submitter was not told their story had been read.';
  end if;
  if v_notification.body not like '%we will run this in September%' then
    raise exception 'The notification did not carry the reply: %.', v_notification.body;
  end if;
  if v_notification.body not like '%Nl Devotee A%' then
    raise exception 'The notification did not say who replied: %.', v_notification.body;
  end if;

  if exists (
    select 1 from public.app_notifications
    where app_notifications.kind = 'newsletter_reviewed'
      and app_notifications.user_id <> 'c1000000-0000-0000-0000-000000000003'
  ) then
    raise exception 'Somebody other than the submitter was told about the review.';
  end if;
end;
$$;

select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000003', true);
set local role authenticated;

do $$
declare
  v_row record;
  v_ratha uuid := (select id from public.newsletter_test_ids where key = 'ratha-yatra');
begin
  select * into v_row
  from public.list_my_newsletter_submissions() mine where mine.id = v_ratha;

  if v_row.id is null then
    raise exception 'The devotee lost sight of their own story once it was reviewed.';
  end if;
  if v_row.status <> 'reviewed' then
    raise exception 'The devotee still sees the story as %.', v_row.status;
  end if;
  if v_row.reply is distinct from 'Thank you — we will run this in September.' then
    raise exception 'The devotee sees the reply as [%].', v_row.reply;
  end if;
  if v_row.replied_by_name is distinct from 'Nl Devotee A' then
    raise exception 'The devotee sees the reviewer as [%].', v_row.replied_by_name;
  end if;
  if v_row.replied_at is null then
    raise exception 'The devotee sees no time on the reply.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 11. The reply is optional, and re-reviewing without changing it says nothing
--     a second time.
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_reviewed public.newsletter_submissions;
  v_two uuid := (select id from public.newsletter_test_ids where key = 'two-photos');
  v_words uuid := (select id from public.newsletter_test_ids where key = 'words-only');
  v_ratha uuid := (select id from public.newsletter_test_ids where key = 'ratha-yatra');
begin
  -- Called with the argument omitted altogether, as a client would.
  v_reviewed := public.review_newsletter_submission(v_two);
  if v_reviewed.status <> 'reviewed' then
    raise exception 'Reviewing without a reply left the status at %.', v_reviewed.status;
  end if;
  if v_reviewed.reply is not null then
    raise exception 'Reviewing without a reply invented one: [%].', v_reviewed.reply;
  end if;
  if v_reviewed.replied_at is null then
    raise exception 'Reviewing without a reply recorded no time.';
  end if;

  -- Blank is the same as absent, not an empty-string reply.
  v_reviewed := public.review_newsletter_submission(v_words, '   ');
  if v_reviewed.reply is not null then
    raise exception 'A whitespace reply was stored as [%].', v_reviewed.reply;
  end if;

  -- Re-reviewing the answered one with nothing typed keeps the answer.
  v_reviewed := public.review_newsletter_submission(v_ratha);
  if v_reviewed.reply is distinct from 'Thank you — we will run this in September.' then
    raise exception 'Re-reviewing wiped the reply: [%].', v_reviewed.reply;
  end if;

  -- And amending is allowed.
  v_reviewed := public.review_newsletter_submission(v_two, 'Lovely photographs, thank you.');
  if v_reviewed.reply is distinct from 'Lovely photographs, thank you.' then
    raise exception 'The amended reply was stored as [%].', v_reviewed.reply;
  end if;
end;
$$;

reset role;

do $$
declare
  v_rows integer;
  v_body text;
  v_two uuid := (select id from public.newsletter_test_ids where key = 'two-photos');
  v_ratha uuid := (select id from public.newsletter_test_ids where key = 'ratha-yatra');
begin
  -- One for the wordless review, one for the amendment.
  select count(*)::integer into v_rows
  from public.app_notifications
  where app_notifications.kind = 'newsletter_reviewed'
    and app_notifications.data ->> 'submissionId' = v_two::text;
  if v_rows <> 2 then
    raise exception 'The wordless review and its amendment produced % notifications.', v_rows;
  end if;

  -- Asserted as a SET rather than "the earliest one".
  --
  -- Both notifications are written inside one transaction, so created_at is
  -- identical for the two and `order by created_at limit 1` picks whichever
  -- row the plan happens to reach first — which shifts with the table's
  -- physical layout, and did, the moment an unrelated migration inserted and
  -- rolled back rows in app_notifications. The intent was never "the first
  -- one"; it is that the wordless review produced its own notification and the
  -- amendment produced a different one saying what was said.
  select count(*)::integer into v_rows
  from public.app_notifications
  where app_notifications.kind = 'newsletter_reviewed'
    and app_notifications.data ->> 'submissionId' = v_two::text
    and app_notifications.body like '%has read your newsletter story%';
  if v_rows <> 1 then
    raise exception
      'the wordless review produced % notifications saying it had been read', v_rows;
  end if;

  select count(*)::integer into v_rows
  from public.app_notifications
  where app_notifications.kind = 'newsletter_reviewed'
    and app_notifications.data ->> 'submissionId' = v_two::text
    and app_notifications.body like '%Lovely photographs, thank you.%';
  if v_rows <> 1 then
    raise exception
      'the amended reply produced % notifications carrying its words', v_rows;
  end if;

  -- The unchanged re-review notified nobody a second time.
  select count(*)::integer into v_rows
  from public.app_notifications
  where app_notifications.kind = 'newsletter_reviewed'
    and app_notifications.data ->> 'submissionId' = v_ratha::text;
  if v_rows <> 1 then
    raise exception 'Re-reviewing with no change notified the devotee % times.', v_rows;
  end if;
end;
$$;

-- A story that does not exist is a readable refusal rather than a silent
-- success, and a devotee cannot rewrite one after sending it.
select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_message text := null;
begin
  begin
    perform public.review_newsletter_submission(
      'c1000000-0000-0000-0000-0000000000ff', 'Thank you.'
    );
  exception when others then
    v_message := sqlerrm;
  end;
  if v_message is null then
    raise exception 'Reviewing a story that does not exist succeeded.';
  end if;
  if v_message not like '%could not be found%' then
    raise exception 'A missing story was refused with "%".', v_message;
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000003', true);
set local role authenticated;

do $$
declare
  v_own uuid := (select id from public.newsletter_test_ids where key = 'ratha-yatra');
  v_refused boolean;
begin
  v_refused := false;
  begin
    update public.newsletter_submissions set body = 'Actually, never mind.'
    where newsletter_submissions.id = v_own;
  exception when others then
    v_refused := true;
  end;
  if not v_refused
     and (select body from public.newsletter_submissions where newsletter_submissions.id = v_own)
         = 'Actually, never mind.' then
    raise exception 'A devotee rewrote their story after sending it.';
  end if;

  v_refused := false;
  begin
    perform public.review_newsletter_submission(v_own, 'I review myself.');
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A devotee reviewed their own story.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 12. Revocation. The moment the President takes the grant back, devotee A can
--     neither post, review, delete, nor see the queue — and none of it needed a
--     role change, which is the whole point of the design.
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
  v_removed public.newsletter_editors;
  v_message text;
begin
  v_removed := public.revoke_newsletter_editor('c1000000-0000-0000-0000-000000000002');
  if v_removed.devotee_id <> 'c1000000-0000-0000-0000-000000000002' then
    raise exception 'The wrong appointment was revoked.';
  end if;
  if exists (select 1 from public.newsletter_editors) then
    raise exception 'The grant survived being revoked.';
  end if;

  -- Revoking somebody who was never appointed is a question with an answer.
  v_message := null;
  begin
    perform public.revoke_newsletter_editor('c1000000-0000-0000-0000-000000000003');
  exception when others then
    v_message := sqlerrm;
  end;
  if v_message is null then
    raise exception 'Revoking a devotee who is not an editor succeeded.';
  end if;
  if v_message not like '%not a newsletter editor%' then
    raise exception 'Revoking a non-editor was refused with "%".', v_message;
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_message text;
  v_rows integer;
  v_row record;
  v_september uuid := (select id from public.newsletter_test_ids where key = 'september');
  v_two uuid := (select id from public.newsletter_test_ids where key = 'two-photos');
begin
  if public.may_manage_newsletter() then
    raise exception 'A revoked editor may still manage the newsletter.';
  end if;

  -- Posting.
  v_message := null;
  begin
    perform public.post_newsletter(
      'October 2026', date '2026-10-01',
      'https://project.supabase.co/storage/v1/object/public/newsletter-files/'
        || 'c1000000-0000-0000-0000-000000000002/october.pdf'
    );
  exception when others then
    v_message := sqlerrm;
  end;
  if v_message is null then
    raise exception 'A revoked editor posted the newsletter.';
  end if;

  -- Reviewing.
  v_message := null;
  begin
    perform public.review_newsletter_submission(v_two, 'Still here.');
  exception when others then
    v_message := sqlerrm;
  end;
  if v_message is null then
    raise exception 'A revoked editor reviewed a story.';
  end if;
  if (select reply from public.newsletter_submissions
      where newsletter_submissions.id = v_two) = 'Still here.' then
    raise exception 'A revoked editor''s reply was stored anyway.';
  end if;

  -- Deleting the issue they posted themselves.
  v_message := null;
  begin
    perform public.delete_newsletter(v_september);
  exception when others then
    v_message := sqlerrm;
  end;
  if v_message is null then
    raise exception 'A revoked editor deleted the issue they had posted.';
  end if;

  -- The queue and the editor list.
  select count(*)::integer into v_rows from public.list_all_newsletter_submissions();
  if v_rows <> 0 then
    raise exception 'A revoked editor still sees % submissions.', v_rows;
  end if;
  select count(*)::integer into v_rows from public.list_newsletter_editors();
  if v_rows <> 0 then
    raise exception 'A revoked editor still reads the editor list.';
  end if;

  -- But they are still a devotee: they read every issue and keep their own
  -- story, with the controls now withdrawn.
  select count(*)::integer into v_rows from public.list_newsletters();
  if v_rows <> 2 then
    raise exception 'A revoked editor sees % newsletters rather than 2.', v_rows;
  end if;
  for v_row in select * from public.list_newsletters() loop
    if v_row.can_delete or v_row.can_manage then
      raise exception 'A revoked editor is still offered the newsletter controls.';
    end if;
  end loop;
  select count(*)::integer into v_rows from public.list_my_newsletter_submissions();
  if v_rows <> 1 then
    raise exception 'A revoked editor sees % of their own stories rather than 1.', v_rows;
  end if;
end;
$$;

-- The President can still take an issue down, and does.
reset role;
select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000004', true);
set local role authenticated;

do $$
declare
  v_removed public.newsletters;
  v_september uuid := (select id from public.newsletter_test_ids where key = 'september');
begin
  if not public.may_manage_newsletter() then
    raise exception 'The Tech Admin may not manage the newsletter.';
  end if;
  v_removed := public.delete_newsletter(v_september);
  if v_removed.id <> v_september then
    raise exception 'The wrong issue was removed.';
  end if;
  if exists (select 1 from public.newsletters where newsletters.id = v_september) then
    raise exception 'The issue survived being deleted.';
  end if;
  if not exists (
    select 1 from public.newsletters
    where newsletters.id = (select id from public.newsletter_test_ids where key = 'august')
  ) then
    raise exception 'Deleting one issue took another with it.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 13. Storage: PDFs got their own bucket because neither existing one accepts
--     them, and photographs still go to the bucket direct messages use.
-- ---------------------------------------------------------------------------

reset role;

do $$
declare
  v_bucket record;
  v_rows integer;
begin
  select * into v_bucket from storage.buckets where buckets.id = 'newsletter-files';
  if v_bucket.id is null then
    raise exception 'The newsletter-files bucket is missing.';
  end if;
  -- PRIVATE, since 202608310088. A public bucket is served at
  -- /object/public/... with no authentication and bypasses row level security
  -- on reads entirely, which put every newsletter PDF on the open internet and
  -- made the `to authenticated` policy below decorative. Readability now comes
  -- from that policy plus a signed URL, not from the bucket being open.
  if v_bucket.public then
    raise exception
      'The newsletter-files bucket is public again; its PDFs are served without sign-in.';
  end if;
  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects'
      and policyname like '%newsletter files%'
      and cmd = 'SELECT'
      and 'authenticated' = any (roles)
  ) then
    raise exception
      'Nothing lets a signed-in devotee read newsletter-files, so no newsletter can be opened.';
  end if;
  if not (v_bucket.allowed_mime_types @> array['application/pdf']) then
    raise exception 'The newsletter-files bucket refuses PDFs: %.',
      v_bucket.allowed_mime_types;
  end if;
  if v_bucket.allowed_mime_types @> array['image/jpeg'] then
    raise exception 'The newsletter-files bucket became a second photo bucket.';
  end if;

  -- No second picture bucket was invented for story photographs.
  select count(*)::integer into v_rows
  from storage.buckets
  where buckets.id ilike '%newsletter%' and buckets.id <> 'newsletter-files';
  if v_rows <> 0 then
    raise exception 'A second newsletter bucket was created.';
  end if;
  if not exists (select 1 from storage.buckets where buckets.id = 'message-images') then
    raise exception 'The message-images bucket is missing.';
  end if;

  -- Writes are confined to the uploader's own folder, reads are for signed-in
  -- devotees, and neither is open to anon.
  select count(*)::integer into v_rows
  from pg_policies
  where schemaname = 'storage' and tablename = 'objects'
    and qual is not null
    and policyname in (
      'Anyone signed in reads newsletter files',
      'Devotees replace their own newsletter files',
      'Devotees remove their own newsletter files'
    );
  if v_rows <> 3 then
    raise exception 'The newsletter-files read/replace/remove policies are missing.';
  end if;

  select count(*)::integer into v_rows
  from pg_policies
  where schemaname = 'storage' and tablename = 'objects'
    and policyname = 'Devotees upload their own newsletter files'
    and with_check like '%foldername%'
    and with_check like '%auth.uid()%';
  if v_rows <> 1 then
    raise exception 'Uploads to newsletter-files are not confined to the uploader''s folder.';
  end if;

  if exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects'
      and policyname like '%newsletter files%'
      and 'anon' = any (roles)
  ) then
    raise exception 'A newsletter-files policy is open to anon.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 14. Nothing here is a chat, and nothing here is granted to anon.
-- ---------------------------------------------------------------------------

do $$
declare
  v_leak text;
begin
  select string_agg(distinct table_name || '.' || privilege_type, ', ')
  into v_leak
  from information_schema.role_table_grants
  where grantee = 'anon'
    and table_schema = 'public'
    and table_name in ('newsletters', 'newsletter_editors', 'newsletter_submissions');
  if v_leak is not null then
    raise exception 'anon holds % on the newsletter tables.', v_leak;
  end if;

  -- The three tables are all behind row level security.
  if exists (
    select 1 from pg_class
    join pg_namespace on pg_namespace.oid = pg_class.relnamespace
    where pg_namespace.nspname = 'public'
      and pg_class.relname in ('newsletters', 'newsletter_editors', 'newsletter_submissions')
      and not pg_class.relrowsecurity
  ) then
    raise exception 'A newsletter table has row level security switched off.';
  end if;
end;
$$;

do $$
begin
  raise notice 'all newsletter checks passed';
end;
$$;

select 'newsletter verification passed' as result;

rollback;
