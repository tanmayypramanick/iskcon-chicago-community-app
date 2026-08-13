-- Functional verification for 202608040041_feedback.sql.
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
--   President  ...0001  holds app.view_all; sees everything, may reply
--   Devotee A  ...0002  writes most of the feedback checked here
--   Devotee B  ...0003  must never see a word of A's
--   Tech       ...0004  the other holder of app.view_all
--   Core       ...0005  the strongest role that must still be shut out
--
-- The final row must read: feedback verification passed

begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('fb000000-0000-0000-0000-000000000001', 'fb-president@example.test', '{"name":"Fb President"}'),
  ('fb000000-0000-0000-0000-000000000002', 'fb-devotee-a@example.test', '{"name":"Fb Devotee A"}'),
  ('fb000000-0000-0000-0000-000000000003', 'fb-devotee-b@example.test', '{"name":"Fb Devotee B"}'),
  ('fb000000-0000-0000-0000-000000000004', 'fb-tech@example.test', '{"name":"Fb Tech"}'),
  ('fb000000-0000-0000-0000-000000000005', 'fb-core@example.test', '{"name":"Fb Core"}');

update public.users
set role_id = (select roles.id from public.roles where roles.name = 'president')
where email = 'fb-president@example.test';

update public.users
set role_id = (select roles.id from public.roles where roles.name = 'tech')
where email = 'fb-tech@example.test';

update public.users
set role_id = (select roles.id from public.roles where roles.name = 'core')
where email = 'fb-core@example.test';

update public.users
set photo_url = 'https://project.supabase.co/storage/v1/object/public/devotee-photos/a.jpg'
where email = 'fb-devotee-a@example.test';

-- Ordinary table rather than a temporary one, so reading it under the
-- authenticated role needs no assumptions about the temp schema. The whole
-- script is rolled back, so it never outlives the transaction.
create table public.feedback_test_ids (key text primary key, id uuid not null);
grant select, insert on public.feedback_test_ids to authenticated;

-- ---------------------------------------------------------------------------
-- 0. The permission being relied on is the existing one, held by exactly the
--    two people the temple named, and no new key was invented for feedback.
--
--    If a later migration hands app.view_all to a third role, feedback widens
--    with it silently. That is worth failing loudly over here rather than
--    discovering it when a volunteer reads a complaint about themselves.
-- ---------------------------------------------------------------------------

do $$
declare
  v_holders text;
begin
  select string_agg(roles.name, ',' order by roles.name) into v_holders
  from public.role_permissions
  join public.roles on roles.id = role_permissions.role_id
  where role_permissions.permission_key = 'app.view_all';

  if v_holders is distinct from 'president,tech' then
    raise exception
      'app.view_all is held by % — feedback assumes president, tech.', v_holders;
  end if;

  if exists (
    select 1 from public.role_permissions
    where role_permissions.permission_key like '%feedback%'
  ) then
    raise exception 'A separate feedback permission key was registered.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 1. Any devotee can send feedback, and all three categories are accepted.
--
--    Devotee A holds no permission whatsoever. That is the whole point of the
--    feature: the quietest person in the congregation gets a door.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'fb000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_case record;
  v_row public.feedback;
begin
  for v_case in
    select * from (values
      ('temple', 'The 4:30 arati was beautiful. Thank you.'),
      ('app', 'The seva list scrolls back to the top when I come back to it.'),
      ('community', 'Nobody greeted the new family on Sunday.')
    ) as sent(category, body)
  loop
    v_row := public.submit_feedback(v_case.category, v_case.body);

    if v_row.id is null then
      raise exception 'A devotee could not send % feedback.', v_case.category;
    end if;
    if v_row.devotee_id <> 'fb000000-0000-0000-0000-000000000002' then
      raise exception 'Feedback was filed against the wrong devotee.';
    end if;
    if v_row.category <> v_case.category then
      raise exception 'The category came back as % rather than %.',
        v_row.category, v_case.category;
    end if;
    if v_row.body <> v_case.body then
      raise exception 'The body did not survive the round trip.';
    end if;
    if v_row.status <> 'new' then
      raise exception 'New feedback arrived as % rather than new.', v_row.status;
    end if;
    if v_row.reply is not null
       or v_row.replied_by is not null
       or v_row.replied_at is not null then
      raise exception 'Unreviewed feedback arrived already answered.';
    end if;

    insert into public.feedback_test_ids values (v_case.category, v_row.id);
  end loop;
end;
$$;

-- A label the app itself renders capitalised must not be refused for being
-- capitalised, and the surrounding whitespace of a form field is not an error.
do $$
declare
  v_row public.feedback;
begin
  v_row := public.submit_feedback('  Temple  ', '  The parking lot floods.  ');
  if v_row.category <> 'temple' then
    raise exception 'A capitalised category was stored as %.', v_row.category;
  end if;
  if v_row.body <> 'The parking lot floods.' then
    raise exception 'The body was not trimmed: [%].', v_row.body;
  end if;
  insert into public.feedback_test_ids values ('parking', v_row.id);
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. A fourth category is refused, and so is a blank body — both with a message
--    a devotee could act on rather than the constraint underneath it.
-- ---------------------------------------------------------------------------

do $$
declare
  v_case record;
  v_message text;
  v_before integer;
  v_after integer;
begin
  select count(*)::integer into v_before from public.feedback;

  for v_case in
    select * from (values
      ('a fourth category', 'kitchen', 'The dal was cold.'),
      ('an empty category', '', 'The dal was cold.'),
      ('a whitespace category', '   ', 'The dal was cold.'),
      ('a null category', null, 'The dal was cold.'),
      ('a near miss on a real category', 'temples', 'The dal was cold.')
    ) as bad(label, category, body)
  loop
    v_message := null;
    begin
      perform public.submit_feedback(v_case.category, v_case.body);
    exception when others then
      v_message := sqlerrm;
    end;

    if v_message is null then
      raise exception 'submit_feedback accepted %.', v_case.label;
    end if;
    if v_message not like '%temple%' or v_message not like '%community%' then
      raise exception 'Refusing % said "%", which does not tell the devotee what to pick.',
        v_case.label, v_message;
    end if;
  end loop;

  for v_case in
    select * from (values
      ('an empty body', 'temple', ''),
      ('a whitespace body', 'temple', '     '),
      ('a newline-only body', 'app', E'\n\n'),
      ('a null body', 'community', null)
    ) as bad(label, category, body)
  loop
    v_message := null;
    begin
      perform public.submit_feedback(v_case.category, v_case.body);
    exception when others then
      v_message := sqlerrm;
    end;

    if v_message is null then
      raise exception 'submit_feedback accepted %.', v_case.label;
    end if;
    if v_message not like '%write your feedback%' then
      raise exception 'Refusing % said "%", not the readable guard.',
        v_case.label, v_message;
    end if;
  end loop;

  select count(*)::integer into v_after from public.feedback;
  if v_after <> v_before then
    raise exception 'A refused submission still wrote a row.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Devotee B sends one of their own, so there is something for A not to see.
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', 'fb000000-0000-0000-0000-000000000003', true);
set local role authenticated;

do $$
declare
  v_row public.feedback;
begin
  v_row := public.submit_feedback(
    'community',
    'I am being ignored in the kitchen and I would rather nobody knew I said so.'
  );
  insert into public.feedback_test_ids values ('devotee-b', v_row.id);
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. A devotee sees their own and nothing else — through the function and
--    straight at the table, which is where a client using PostgREST would try.
-- ---------------------------------------------------------------------------

do $$
declare
  v_rows integer;
  v_leaked integer;
  v_a_id uuid := (select id from public.feedback_test_ids where key = 'temple');
begin
  -- a) Through list_my_feedback.
  select count(*)::integer into v_rows from public.list_my_feedback();
  if v_rows <> 1 then
    raise exception 'Devotee B sees % of their own feedback rather than 1.', v_rows;
  end if;

  select count(*)::integer into v_leaked
  from public.list_my_feedback() mine
  where mine.body like '%arati%' or mine.body like '%parking lot floods%';
  if v_leaked <> 0 then
    raise exception 'list_my_feedback handed devotee B % of devotee A''s rows.', v_leaked;
  end if;

  -- b) Straight at the table, by id: the row exists and must still be invisible.
  select count(*)::integer into v_leaked
  from public.feedback where feedback.id = v_a_id;
  if v_leaked <> 0 then
    raise exception 'Devotee B read devotee A''s feedback row directly from the table.';
  end if;

  -- c) And unfiltered.
  select count(*)::integer into v_rows from public.feedback;
  if v_rows <> 1 then
    raise exception 'Devotee B can see % rows of the feedback table rather than 1.', v_rows;
  end if;

  -- d) The devotee_id column is not a side channel either.
  select count(*)::integer into v_leaked
  from public.feedback
  where feedback.devotee_id = 'fb000000-0000-0000-0000-000000000002';
  if v_leaked <> 0 then
    raise exception 'Devotee B can count devotee A''s feedback.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. list_all_feedback is empty for anyone without app.view_all — including a
--    Community Head, who is otherwise trusted with a great deal.
-- ---------------------------------------------------------------------------

do $$
declare
  v_rows integer;
begin
  select count(*)::integer into v_rows from public.list_all_feedback();
  if v_rows <> 0 then
    raise exception 'A plain devotee saw % rows of everybody''s feedback.', v_rows;
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'fb000000-0000-0000-0000-000000000005', true);
set local role authenticated;

do $$
declare
  v_rows integer;
begin
  select count(*)::integer into v_rows from public.list_all_feedback();
  if v_rows <> 0 then
    raise exception 'A Community Head saw % rows of everybody''s feedback.', v_rows;
  end if;

  -- Nor at the table, where the policy is the only thing standing in the way.
  select count(*)::integer into v_rows from public.feedback;
  if v_rows <> 0 then
    raise exception 'A Community Head read % feedback rows from the table.', v_rows;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. The President sees all of it, with the devotee's name and photo. So does
--    the Tech Admin.
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', 'fb000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
  v_rows integer;
  v_total integer;
  v_row record;
  v_previous timestamptz;
begin
  select count(*)::integer into v_total from public.feedback;
  select count(*)::integer into v_rows from public.list_all_feedback();
  -- Four from devotee A, one from devotee B.
  if v_rows <> v_total or v_total <> 5 then
    raise exception 'The President saw % of % feedback rows.', v_rows, v_total;
  end if;

  -- Devotee B's row is in there, which is the point of the screen.
  if not exists (
    select 1 from public.list_all_feedback() all_feedback
    where all_feedback.devotee_id = 'fb000000-0000-0000-0000-000000000003'
  ) then
    raise exception 'The President cannot see devotee B''s feedback.';
  end if;

  select * into v_row
  from public.list_all_feedback() all_feedback
  where all_feedback.id = (select id from public.feedback_test_ids where key = 'temple');

  if v_row.devotee_name is distinct from 'Fb Devotee A' then
    raise exception 'The devotee''s name came back as %.', v_row.devotee_name;
  end if;
  if v_row.devotee_photo_url is null then
    raise exception 'The devotee''s photo was dropped.';
  end if;
  if v_row.category <> 'temple' or v_row.status <> 'new' then
    raise exception 'The row came back as % / %.', v_row.category, v_row.status;
  end if;

  -- Newest first, so the President works the top of the queue.
  v_previous := null;
  for v_row in select * from public.list_all_feedback() loop
    if v_previous is not null and v_row.created_at > v_previous then
      raise exception 'list_all_feedback is not newest first.';
    end if;
    v_previous := v_row.created_at;
  end loop;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'fb000000-0000-0000-0000-000000000004', true);
set local role authenticated;

do $$
declare
  v_rows integer;
begin
  select count(*)::integer into v_rows from public.list_all_feedback();
  if v_rows <> 5 then
    raise exception 'The Tech Admin saw % feedback rows rather than 5.', v_rows;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Only a holder of app.view_all can review. A devotee cannot, not even
--    their own; a Community Head cannot either.
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', 'fb000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_message text;
  v_id uuid := (select id from public.feedback_test_ids where key = 'temple');
begin
  v_message := null;
  begin
    perform public.review_feedback(v_id, 'We have read this and are looking into it.');
  exception when others then
    v_message := sqlerrm;
  end;
  if v_message is null then
    raise exception 'A devotee reviewed their own feedback.';
  end if;
  if v_message not like '%President%' then
    raise exception 'Refusing a devotee said "%", not the readable guard.', v_message;
  end if;

  if (select status from public.feedback where feedback.id = v_id) <> 'new' then
    raise exception 'A refused review still marked the feedback reviewed.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'fb000000-0000-0000-0000-000000000005', true);
set local role authenticated;

do $$
declare
  v_refused boolean := false;
  v_id uuid := (select id from public.feedback_test_ids where key = 'temple');
begin
  begin
    perform public.review_feedback(v_id, 'We have read this.');
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A Community Head reviewed feedback.';
  end if;
end;
$$;

-- Writing straight at the table is not a way round the RPC either.
do $$
declare
  v_refused boolean := false;
  v_id uuid := (select id from public.feedback_test_ids where key = 'temple');
begin
  begin
    update public.feedback
    set status = 'reviewed', reply = 'Sorted.', replied_at = now()
    where feedback.id = v_id;
  exception when others then
    v_refused := true;
  end;
  if not v_refused
     and (select status from public.feedback where feedback.id = v_id) = 'reviewed' then
    raise exception 'A Community Head updated a feedback row directly.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. The President reviews with a reply, and the devotee is notified.
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', 'fb000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
  v_reviewed public.feedback;
  v_id uuid := (select id from public.feedback_test_ids where key = 'app');
begin
  v_reviewed := public.review_feedback(
    v_id, '  We have read this and are looking into it. Thank you.  '
  );

  if v_reviewed.status <> 'reviewed' then
    raise exception 'Reviewing left the status at %.', v_reviewed.status;
  end if;
  if v_reviewed.reply is distinct from 'We have read this and are looking into it. Thank you.' then
    raise exception 'The reply was stored as [%].', v_reviewed.reply;
  end if;
  if v_reviewed.replied_by is distinct from 'fb000000-0000-0000-0000-000000000001'::uuid then
    raise exception 'The reply was attributed to %.', v_reviewed.replied_by;
  end if;
  if v_reviewed.replied_at is null then
    raise exception 'A reviewed row has no replied_at.';
  end if;
  -- Reviewing one piece of feedback must not touch another.
  if (select status from public.feedback
      where feedback.id = (select id from public.feedback_test_ids where key = 'temple'))
     <> 'new' then
    raise exception 'Reviewing one row marked another reviewed.';
  end if;
end;
$$;

reset role;

do $$
declare
  v_notification record;
  v_id uuid := (select id from public.feedback_test_ids where key = 'app');
begin
  select * into v_notification
  from public.app_notifications
  where app_notifications.user_id = 'fb000000-0000-0000-0000-000000000002'
    and app_notifications.kind = 'feedback_reviewed'
    and app_notifications.data ->> 'feedbackId' = v_id::text;

  if v_notification.id is null then
    raise exception 'The devotee was not told their feedback had been answered.';
  end if;
  if v_notification.body not like '%We have read this and are looking into it.%' then
    raise exception 'The notification did not carry the reply: %.', v_notification.body;
  end if;
  if v_notification.body not like '%Fb President%' then
    raise exception 'The notification did not say who replied: %.', v_notification.body;
  end if;

  -- Only the devotee who wrote it. Nobody else's inbox is involved, least of
  -- all the other devotee's.
  if exists (
    select 1 from public.app_notifications
    where app_notifications.kind = 'feedback_reviewed'
      and app_notifications.user_id <> 'fb000000-0000-0000-0000-000000000002'
  ) then
    raise exception 'Somebody other than the author was notified about the reply.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 9. And the devotee can read the reply against their own feedback.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'fb000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_row record;
  v_id uuid := (select id from public.feedback_test_ids where key = 'app');
begin
  select * into v_row from public.list_my_feedback() mine where mine.id = v_id;

  if v_row.id is null then
    raise exception 'The devotee lost sight of their own feedback once it was reviewed.';
  end if;
  if v_row.status <> 'reviewed' then
    raise exception 'The devotee still sees the feedback as %.', v_row.status;
  end if;
  if v_row.reply is distinct from 'We have read this and are looking into it. Thank you.' then
    raise exception 'The devotee sees the reply as [%].', v_row.reply;
  end if;
  if v_row.replied_by_name is distinct from 'Fb President' then
    raise exception 'The devotee sees the replier as [%].', v_row.replied_by_name;
  end if;
  if v_row.replied_at is null then
    raise exception 'The devotee sees no time on the reply.';
  end if;

  -- Newest first here too.
  if (select count(*)::integer from public.list_my_feedback()) <> 4 then
    raise exception 'The devotee no longer sees all four of their own.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 10. The reply is optional: reviewing with nothing typed still marks the row
--     read and still tells the devotee, and reviewing again does not silently
--     wipe an acknowledgement they have already been shown.
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', 'fb000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
  v_reviewed public.feedback;
  v_id uuid := (select id from public.feedback_test_ids where key = 'temple');
begin
  -- Called with the argument omitted altogether, as a client would.
  v_reviewed := public.review_feedback(v_id);
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
  v_reviewed := public.review_feedback(
    (select id from public.feedback_test_ids where key = 'community'), '   '
  );
  if v_reviewed.reply is not null then
    raise exception 'A whitespace reply was stored as [%].', v_reviewed.reply;
  end if;

  -- Re-reviewing the answered one with nothing typed keeps the answer.
  v_reviewed := public.review_feedback(
    (select id from public.feedback_test_ids where key = 'app')
  );
  if v_reviewed.reply is distinct from 'We have read this and are looking into it. Thank you.' then
    raise exception 'Re-reviewing wiped the reply: [%].', v_reviewed.reply;
  end if;

  -- And amending the reply is allowed.
  v_reviewed := public.review_feedback(v_id, 'Fixed, thank you for telling us.');
  if v_reviewed.reply is distinct from 'Fixed, thank you for telling us.' then
    raise exception 'The amended reply was stored as [%].', v_reviewed.reply;
  end if;
end;
$$;

reset role;

do $$
declare
  v_rows integer;
  v_body text;
  v_temple uuid := (select id from public.feedback_test_ids where key = 'temple');
begin
  -- Reviewed with no reply: still notified, and told so in plain words.
  select count(*)::integer into v_rows
  from public.app_notifications
  where app_notifications.kind = 'feedback_reviewed'
    and app_notifications.data ->> 'feedbackId' = v_temple::text;
  -- One for the wordless review, one for the amendment. Not three: the
  -- re-review of the 'app' row changed nothing and must have said nothing.
  if v_rows <> 2 then
    raise exception 'The wordless review and its amendment produced % notifications.', v_rows;
  end if;

  select app_notifications.body into v_body
  from public.app_notifications
  where app_notifications.kind = 'feedback_reviewed'
    and app_notifications.data ->> 'feedbackId' = v_temple::text
  order by app_notifications.created_at
  limit 1;
  if coalesce(v_body, '') not like '%has read your feedback%' then
    raise exception 'A wordless review told the devotee: %.', v_body;
  end if;

  -- The unchanged re-review of the answered row notified nobody a second time.
  select count(*)::integer into v_rows
  from public.app_notifications
  where app_notifications.kind = 'feedback_reviewed'
    and app_notifications.data ->> 'feedbackId'
        = (select id from public.feedback_test_ids where key = 'app')::text;
  if v_rows <> 1 then
    raise exception 'Re-reviewing with no change notified the devotee % times.', v_rows;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 11. Devotee B is still shut out of everything, now that there are replies
--     worth reading, and can neither review nor rewrite their own words.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'fb000000-0000-0000-0000-000000000003', true);
set local role authenticated;

do $$
declare
  v_rows integer;
  v_refused boolean;
  v_own uuid := (select id from public.feedback_test_ids where key = 'devotee-b');
begin
  select count(*)::integer into v_rows from public.feedback;
  if v_rows <> 1 then
    raise exception 'Devotee B can now see % feedback rows.', v_rows;
  end if;

  select count(*)::integer into v_rows
  from public.feedback where feedback.reply is not null;
  if v_rows <> 0 then
    raise exception 'Devotee B can read % replies meant for somebody else.', v_rows;
  end if;

  select count(*)::integer into v_rows from public.list_all_feedback();
  if v_rows <> 0 then
    raise exception 'list_all_feedback handed devotee B % rows.', v_rows;
  end if;

  -- Sent is sent: the President may already have read it.
  v_refused := false;
  begin
    update public.feedback set body = 'Actually, never mind.'
    where feedback.id = v_own;
  exception when others then
    v_refused := true;
  end;
  if not v_refused
     and (select body from public.feedback where feedback.id = v_own)
         = 'Actually, never mind.' then
    raise exception 'Devotee B rewrote their feedback after sending it.';
  end if;

  v_refused := false;
  begin
    delete from public.feedback where feedback.id = v_own;
  exception when others then
    v_refused := true;
  end;
  if not v_refused
     and not exists (select 1 from public.feedback where feedback.id = v_own) then
    raise exception 'Devotee B deleted their feedback after sending it.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 12. Reviewing something that does not exist is a readable refusal rather
--     than a silent success.
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', 'fb000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
  v_message text := null;
begin
  begin
    perform public.review_feedback(
      'fb000000-0000-0000-0000-0000000000ff', 'Thank you.'
    );
  exception when others then
    v_message := sqlerrm;
  end;
  if v_message is null then
    raise exception 'Reviewing feedback that does not exist succeeded.';
  end if;
  if v_message not like '%could not be found%' then
    raise exception 'A missing row was refused with "%".', v_message;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 13. The reply is not a chat. Nothing here created a conversation, a thread,
--     or a message, and the feature cannot be entangled with direct messages
--     by accident later.
-- ---------------------------------------------------------------------------

reset role;

do $$
declare
  v_rows integer;
begin
  if to_regclass('public.messages') is not null then
    execute 'select count(*)::integer from public.messages' into v_rows;
    if v_rows <> 0 then
      raise exception 'Replying to feedback wrote % direct messages.', v_rows;
    end if;
  end if;
  if to_regclass('public.conversations') is not null then
    execute 'select count(*)::integer from public.conversations' into v_rows;
    if v_rows <> 0 then
      raise exception 'Replying to feedback opened % conversations.', v_rows;
    end if;
  end if;
end;
$$;

do $$
begin
  raise notice 'all feedback checks passed';
end;
$$;

select 'feedback verification passed' as result;

rollback;
