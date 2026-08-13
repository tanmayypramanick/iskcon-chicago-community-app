-- Functional verification for 202608040046_removals.sql.
--
-- Rolled back at the end. Every local is prefixed v_ so it can never shadow a
-- column name. Anything that must be refused is attempted as the devotee who
-- would really attempt it, under `set local role authenticated`, so the row
-- level security policies and the column grants are the thing being tested
-- rather than superuser rights quietly waving everything through. Row counts
-- and notification assertions are made after `reset role`, because a devotee
-- cannot — and should not be able to — read somebody else's inbox.
--
-- The six people in this script:
--   President  ...0001  holds app.view_all; may remove anybody's feedback
--   Devotee A  ...0002  writes most of what is removed here; holds nothing
--   Devotee B  ...0003  the other ordinary devotee; must never remove A's
--   Tech       ...0004  the other holder of app.view_all
--   Core       ...0005  the Community Head. Strong everywhere else in this app
--                       and deliberately powerless over feedback, which is
--                       addressed to the President and may well be about them.
--   Editor E   ...0006  an ordinary devotee, appointed newsletter editor half
--                       way through and revoked again near the end. The whole
--                       asymmetry between the two features lives in this one
--                       person: while appointed E may remove anybody's story
--                       and still not a word of anybody's feedback.
--
-- The final row must read: removals verification passed

begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('4e000000-0000-0000-0000-000000000001', 'rm-president@example.test', '{"name":"Rm President"}'),
  ('4e000000-0000-0000-0000-000000000002', 'rm-devotee-a@example.test', '{"name":"Rm Devotee A"}'),
  ('4e000000-0000-0000-0000-000000000003', 'rm-devotee-b@example.test', '{"name":"Rm Devotee B"}'),
  ('4e000000-0000-0000-0000-000000000004', 'rm-tech@example.test', '{"name":"Rm Tech"}'),
  ('4e000000-0000-0000-0000-000000000005', 'rm-core@example.test', '{"name":"Rm Core"}'),
  ('4e000000-0000-0000-0000-000000000006', 'rm-editor@example.test', '{"name":"Rm Editor"}');

update public.users
set role_id = (select roles.id from public.roles where roles.name = 'president')
where email = 'rm-president@example.test';

update public.users
set role_id = (select roles.id from public.roles where roles.name = 'tech')
where email = 'rm-tech@example.test';

update public.users
set role_id = (select roles.id from public.roles where roles.name = 'core')
where email = 'rm-core@example.test';

-- Ordinary table rather than a temporary one, so reading it under the
-- authenticated role needs no assumptions about the temp schema. The whole
-- script is rolled back, so it never outlives the transaction.
create table public.removal_test_ids (key text primary key, id uuid not null);
grant select, insert on public.removal_test_ids to authenticated;

-- ---------------------------------------------------------------------------
-- 0. The two authorities being relied on are the existing ones, and no third
--    key was invented for removal.
--
--    If a later migration hands app.view_all to a fourth role, the right to
--    delete another devotee's feedback widens with it silently. That is worth
--    failing loudly over here rather than discovering it when a volunteer
--    quietly removes a complaint about themselves.
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
      'app.view_all is held by % — removal assumes president, tech.', v_holders;
  end if;

  -- services.delete_any is an unrelated, pre-existing key about seva. What must
  -- not appear is a key of this feature's own — a second answer to "who may
  -- remove this" that can drift from app.view_all and the editor appointment.
  if exists (
    select 1 from public.role_permissions
    where role_permissions.permission_key like '%feedback%'
       or role_permissions.permission_key like '%newsletter%'
  ) then
    raise exception 'A separate feedback or newsletter permission key was registered.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 1. The shape of what was added, before any of it is exercised.
--
--    Both RPCs exist with exactly the signature the client will call, both
--    return the row they removed rather than void or boolean, and neither is
--    reachable by anon. The four lists carry can_delete last, so a client
--    reading positionally is not shifted, and each list exists exactly once —
--    a leftover overload with defaults is what makes a later call ambiguous,
--    and that has broken this repo before.
-- ---------------------------------------------------------------------------

do $$
declare
  v_case record;
  v_oid oid;
begin
  for v_case in
    select * from (values
      ('public.delete_feedback(uuid)', 'public.feedback'),
      ('public.delete_newsletter_submission(uuid)', 'public.newsletter_submissions'),
      ('public.may_delete_feedback(uuid)', 'pg_catalog.bool'),
      ('public.may_delete_newsletter_submission(uuid)', 'pg_catalog.bool')
    ) as wanted(signature, return_type)
  loop
    v_oid := to_regprocedure(v_case.signature);
    if v_oid is null then
      raise exception '% was not created.', v_case.signature;
    end if;

    if (select prorettype from pg_proc where oid = v_oid)
       is distinct from to_regtype(v_case.return_type) then
      raise exception '% does not return %.', v_case.signature, v_case.return_type;
    end if;

    if not has_function_privilege('authenticated', v_oid, 'execute') then
      raise exception 'A signed-in devotee cannot execute %.', v_case.signature;
    end if;
    if has_function_privilege('anon', v_oid, 'execute') then
      raise exception 'anon can execute %.', v_case.signature;
    end if;
  end loop;
end;
$$;

do $$
declare
  v_case record;
  v_columns text;
  v_overloads integer;
begin
  for v_case in
    select * from (values
      (
        'public.list_my_feedback()',
        'list_my_feedback',
        'id,category,body,status,reply,replied_by_name,replied_at,created_at,can_delete'
      ),
      (
        'public.list_all_feedback()',
        'list_all_feedback',
        'id,devotee_id,devotee_name,devotee_photo_url,category,body,status,reply,'
          || 'replied_by,replied_by_name,replied_at,created_at,can_delete'
      ),
      (
        'public.list_my_newsletter_submissions()',
        'list_my_newsletter_submissions',
        'id,body,image_urls,file_url,status,reply,replied_by_name,replied_at,'
          || 'created_at,can_manage,can_delete'
      ),
      (
        'public.list_all_newsletter_submissions()',
        'list_all_newsletter_submissions',
        'id,devotee_id,devotee_name,devotee_photo_url,body,image_urls,file_url,'
          || 'status,reply,replied_by,replied_by_name,replied_at,created_at,'
          || 'can_manage,can_delete'
      )
    ) as wanted(signature, name, columns)
  loop
    if to_regprocedure(v_case.signature) is null then
      raise exception '% is missing.', v_case.signature;
    end if;

    select count(*)::integer into v_overloads
    from pg_proc
    join pg_namespace on pg_namespace.oid = pg_proc.pronamespace
    where pg_namespace.nspname = 'public'
      and pg_proc.proname = v_case.name;

    if v_overloads <> 1 then
      raise exception
        '% has % versions; a leftover overload makes the call ambiguous.',
        v_case.name, v_overloads;
    end if;

    select string_agg(output.name, ',' order by output.ord) into v_columns
    from pg_proc,
      unnest(pg_proc.proargnames, pg_proc.proargmodes)
        with ordinality as output(name, mode, ord)
    where pg_proc.oid = to_regprocedure(v_case.signature)
      and output.mode = 't';

    if v_columns is distinct from v_case.columns then
      raise exception '% returns (%) rather than (%).',
        v_case.name, v_columns, v_case.columns;
    end if;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Something to remove.
--
--    Every row is sent through the real RPC by the devotee who owns it, so
--    nothing here is a superuser insert that skipped a constraint.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', '4e000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_case record;
  v_row public.feedback;
begin
  for v_case in
    select * from (values
      ('fb_a_own', 'temple', 'The parking on Sunday is impossible.'),
      ('fb_a_president', 'app', 'The seva list scrolls back to the top.'),
      ('fb_a_guarded', 'community', 'Something I said in temper about a devotee.'),
      ('fb_a_keep', 'temple', 'The 4:30 arati was beautiful. Thank you.')
    ) as sent(key, category, body)
  loop
    v_row := public.submit_feedback(v_case.category, v_case.body);
    insert into public.removal_test_ids (key, id) values (v_case.key, v_row.id);
  end loop;
end;
$$;

do $$
declare
  v_row public.newsletter_submissions;
  v_case record;
begin
  for v_case in
    select * from (values
      ('sub_a_own', 'A photograph of my daughter at her first Ratha Yatra.'),
      ('sub_a_editor', 'A duplicate of the same story, sent twice by mistake.'),
      ('sub_a_guarded', 'A story about the Sunday feast.'),
      ('sub_a_keep', 'A story about the new Deity outfits.')
    ) as sent(key, body)
  loop
    v_row := public.submit_newsletter_story(v_case.body);
    insert into public.removal_test_ids (key, id) values (v_case.key, v_row.id);
  end loop;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '4e000000-0000-0000-0000-000000000003', true);
set local role authenticated;

do $$
declare
  v_row public.feedback;
begin
  v_row := public.submit_feedback('app', 'The notifications arrive twice.');
  insert into public.removal_test_ids (key, id) values ('fb_b_keep', v_row.id);
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '4e000000-0000-0000-0000-000000000005', true);
set local role authenticated;

do $$
declare
  v_row public.feedback;
begin
  v_row := public.submit_feedback('temple', 'The Community Head has an opinion too.');
  insert into public.removal_test_ids (key, id) values ('fb_core_own', v_row.id);
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '4e000000-0000-0000-0000-000000000006', true);
set local role authenticated;

do $$
declare
  v_row public.newsletter_submissions;
  v_case record;
begin
  for v_case in
    select * from (values
      ('sub_e_own', 'The editor sent a story in before they were appointed.'),
      ('sub_e_keep', 'And another one, which survives this script.')
    ) as sent(key, body)
  loop
    v_row := public.submit_newsletter_story(v_case.body);
    insert into public.removal_test_ids (key, id) values (v_case.key, v_row.id);
  end loop;
end;
$$;

reset role;

do $$
declare
  v_feedback integer;
  v_submissions integer;
begin
  select count(*)::integer into v_feedback from public.feedback;
  select count(*)::integer into v_submissions from public.newsletter_submissions;

  if v_feedback <> 6 then
    raise exception 'Expected 6 pieces of feedback to start with, found %.', v_feedback;
  end if;
  if v_submissions <> 6 then
    raise exception 'Expected 6 story submissions to start with, found %.', v_submissions;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. The devotee who wrote it removes their own feedback.
--
--    The removed row comes back whole — the client needs the body for an undo
--    or a confirmation, and a function that answered `true` would have given it
--    nothing a tombstone would not.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', '4e000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_id uuid := (select id from public.removal_test_ids where key = 'fb_a_own');
  v_removed public.feedback;
begin
  v_removed := public.delete_feedback(v_id);

  if v_removed.id is distinct from v_id then
    raise exception 'delete_feedback returned the wrong row.';
  end if;
  if v_removed.devotee_id <> '4e000000-0000-0000-0000-000000000002' then
    raise exception 'The removed row came back attributed to somebody else.';
  end if;
  if v_removed.body <> 'The parking on Sunday is impossible.' then
    raise exception 'The removed row came back without its body.';
  end if;
  if exists (select 1 from public.feedback where feedback.id = v_id) then
    raise exception 'The feedback the author removed is still there.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. The President removes another devotee's feedback.
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', '4e000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
  v_id uuid := (select id from public.removal_test_ids where key = 'fb_a_president');
  v_removed public.feedback;
begin
  v_removed := public.delete_feedback(v_id);

  if v_removed.id is distinct from v_id then
    raise exception 'The President removed the wrong row.';
  end if;
  if v_removed.devotee_id <> '4e000000-0000-0000-0000-000000000002' then
    raise exception 'The President removed somebody else''s row than the one asked for.';
  end if;
  if exists (select 1 from public.feedback where feedback.id = v_id) then
    raise exception 'The feedback the President removed is still there.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. A plain devotee cannot remove somebody else's feedback.
--
--    Devotee B holds nothing, and the row is not theirs. The refusal has to
--    come with the row still present afterwards — an exception raised after the
--    delete would read the same to the client and be a catastrophe. That half
--    is asserted after `reset role`, because B cannot see A's feedback at all:
--    under B's own row level security "still there" and "gone" look identical.
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', '4e000000-0000-0000-0000-000000000003', true);
set local role authenticated;

do $$
declare
  v_id uuid := (select id from public.removal_test_ids where key = 'fb_a_guarded');
  v_message text;
begin
  begin
    perform public.delete_feedback(v_id);
  exception when others then
    v_message := sqlerrm;
  end;

  if v_message is null then
    raise exception 'A plain devotee removed somebody else''s feedback.';
  end if;
  if v_message not like '%your own%' then
    raise exception 'Refusing a plain devotee said "%", which does not say whose feedback they may remove.',
      v_message;
  end if;
end;
$$;

reset role;

do $$
declare
  v_id uuid := (select id from public.removal_test_ids where key = 'fb_a_guarded');
begin
  if not exists (select 1 from public.feedback where feedback.id = v_id) then
    raise exception 'Refusing a plain devotee still removed the row.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. A Community Head cannot remove feedback. It is not their business.
--
--    Core is the strongest role below the two office holders, it may post
--    announcements and run recurring seva, and none of that reaches a
--    complaint addressed to the President — which, on the community category,
--    may perfectly well be a complaint about the Community Head.
--
--    The second half of this section is the control: Core removes their own
--    feedback without trouble. That is what proves the refusal above is about
--    authority over somebody else's row and not about the role being blocked
--    from the function altogether.
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', '4e000000-0000-0000-0000-000000000005', true);
set local role authenticated;

do $$
declare
  v_case record;
  v_message text;
begin
  for v_case in
    select removal_test_ids.key, removal_test_ids.id
    from public.removal_test_ids
    where removal_test_ids.key in ('fb_a_guarded', 'fb_a_keep', 'fb_b_keep')
  loop
    v_message := null;
    begin
      perform public.delete_feedback(v_case.id);
    exception when others then
      v_message := sqlerrm;
    end;

    if v_message is null then
      raise exception 'A Community Head removed % — feedback is not theirs to remove.',
        v_case.key;
    end if;
  end loop;

  if public.may_review_feedback() then
    raise exception 'A Community Head can review feedback; the ladder moved underneath this script.';
  end if;
  if public.may_delete_feedback('4e000000-0000-0000-0000-000000000002') then
    raise exception 'may_delete_feedback says a Community Head may remove another devotee''s feedback.';
  end if;
end;
$$;

reset role;

do $$
declare
  v_case record;
begin
  for v_case in
    select removal_test_ids.key, removal_test_ids.id
    from public.removal_test_ids
    where removal_test_ids.key in ('fb_a_guarded', 'fb_a_keep', 'fb_b_keep')
  loop
    if not exists (select 1 from public.feedback where feedback.id = v_case.id) then
      raise exception 'Refusing the Community Head still removed %.', v_case.key;
    end if;
  end loop;
end;
$$;

select set_config('request.jwt.claim.sub', '4e000000-0000-0000-0000-000000000005', true);
set local role authenticated;

do $$
declare
  v_id uuid := (select id from public.removal_test_ids where key = 'fb_core_own');
  v_removed public.feedback;
begin
  if not public.may_delete_feedback('4e000000-0000-0000-0000-000000000005') then
    raise exception 'A Community Head cannot remove their own feedback.';
  end if;

  v_removed := public.delete_feedback(v_id);

  if v_removed.id is distinct from v_id then
    raise exception 'The Community Head removed the wrong row of their own.';
  end if;
  if exists (select 1 from public.feedback where feedback.id = v_id) then
    raise exception 'The Community Head''s own feedback is still there.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. The Tech Admin — the other holder of app.view_all — removes another
--    devotee's feedback, and a piece of feedback that has already been read and
--    answered is still removable.
--
--    The notification the devotee was already sent stays exactly where it is.
--    "The temple replied to your feedback" was true when it was sent and does
--    not become false because the row was later withdrawn; the alternative is a
--    delete that reaches into somebody's inbox and rewrites history there.
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', '4e000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
  v_id uuid := (select id from public.removal_test_ids where key = 'fb_a_guarded');
begin
  perform public.review_feedback(v_id, 'Thank you for telling us. We will speak to them.');
end;
$$;

reset role;

do $$
declare
  v_id uuid := (select id from public.removal_test_ids where key = 'fb_a_guarded');
  v_notifications integer;
begin
  select count(*)::integer into v_notifications
  from public.app_notifications
  where app_notifications.kind = 'feedback_reviewed'
    and app_notifications.data ->> 'feedbackId' = v_id::text;

  if v_notifications <> 1 then
    raise exception 'Reviewing the feedback queued % notifications, not 1.', v_notifications;
  end if;
end;
$$;

select set_config('request.jwt.claim.sub', '4e000000-0000-0000-0000-000000000004', true);
set local role authenticated;

do $$
declare
  v_id uuid := (select id from public.removal_test_ids where key = 'fb_a_guarded');
  v_removed public.feedback;
begin
  v_removed := public.delete_feedback(v_id);

  if v_removed.status <> 'reviewed' then
    raise exception 'The reviewed row did not come back reviewed.';
  end if;
  if v_removed.reply is null then
    raise exception 'The removed row came back without the reply it carried.';
  end if;
  if exists (select 1 from public.feedback where feedback.id = v_id) then
    raise exception 'The Tech Admin''s removal left the row behind.';
  end if;
end;
$$;

reset role;

do $$
declare
  v_id uuid := (select id from public.removal_test_ids where key = 'fb_a_guarded');
  v_notifications integer;
begin
  select count(*)::integer into v_notifications
  from public.app_notifications
  where app_notifications.kind = 'feedback_reviewed'
    and app_notifications.data ->> 'feedbackId' = v_id::text;

  if v_notifications <> 1 then
    raise exception
      'Removing the feedback also removed the notification the devotee was already shown.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. can_delete on the two feedback lists.
--
--    Two rows are left: A's and B's. Every row either list hands back is a row
--    the caller may remove — list_my_feedback only ever returns your own, and
--    list_all_feedback is gated on the very permission that grants removal — so
--    the flag is true throughout, and the assertions below say so row by row
--    rather than trusting a constant. The false half of the rule is proved
--    where it is actually reachable: on the predicate itself, against an author
--    who is not the caller, and end to end by the refusals in sections 5 and 6.
--
--    The mutation that matters is dropping one branch of the predicate. Lose
--    the author branch and Devotee A's own list goes false; lose the
--    app.view_all branch and the President's queue goes false on somebody
--    else's row. Both are caught here.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', '4e000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_row record;
  v_rows integer := 0;
begin
  for v_row in select * from public.list_my_feedback() loop
    v_rows := v_rows + 1;
    if v_row.can_delete is not true then
      raise exception 'A devotee is told they cannot remove their own feedback.';
    end if;
  end loop;

  if v_rows <> 1 then
    raise exception 'Devotee A should have 1 piece of feedback left, has %.', v_rows;
  end if;

  -- A plain devotee sees nothing at all through the President's queue, so there
  -- is no row there on which can_delete could be wrongly true.
  if exists (select 1 from public.list_all_feedback()) then
    raise exception 'A plain devotee can read the whole feedback queue.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '4e000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
  v_row record;
  v_own integer := 0;
  v_others integer := 0;
begin
  for v_row in select * from public.list_all_feedback() loop
    if v_row.can_delete is not true then
      raise exception
        'The President is told they cannot remove the feedback of %.', v_row.devotee_name;
    end if;
    if v_row.can_delete is distinct from public.may_delete_feedback(v_row.devotee_id) then
      raise exception 'can_delete disagrees with may_delete_feedback for %.', v_row.id;
    end if;
    if v_row.devotee_id = '4e000000-0000-0000-0000-000000000001' then
      v_own := v_own + 1;
    else
      v_others := v_others + 1;
    end if;
  end loop;

  if v_others <> 2 then
    raise exception
      'The President should see 2 pieces of other devotees'' feedback, sees %.', v_others;
  end if;
  if v_own <> 0 then
    raise exception 'The President wrote no feedback in this script but sees % of their own.', v_own;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 9. A devotee removes their own newsletter story.
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', '4e000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_id uuid := (select id from public.removal_test_ids where key = 'sub_a_own');
  v_removed public.newsletter_submissions;
begin
  v_removed := public.delete_newsletter_submission(v_id);

  if v_removed.id is distinct from v_id then
    raise exception 'delete_newsletter_submission returned the wrong row.';
  end if;
  if v_removed.body <> 'A photograph of my daughter at her first Ratha Yatra.' then
    raise exception 'The removed story came back without its body.';
  end if;
  if exists (
    select 1 from public.newsletter_submissions where newsletter_submissions.id = v_id
  ) then
    raise exception 'The story the author removed is still there.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 10. An appointed newsletter editor removes another devotee's story — and
--     still cannot touch a word of anybody's feedback.
--
--     This is the asymmetry the temple asked for, in one person. A story
--     submission is raw material for an issue somebody is producing; feedback
--     is correspondence addressed to the President. Editor E holds no role at
--     all — the appointment is a grant, not a rung — so if removal ever leaked
--     across from one to the other, it would show up right here.
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', '4e000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
begin
  perform public.appoint_newsletter_editor('4e000000-0000-0000-0000-000000000006');
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '4e000000-0000-0000-0000-000000000006', true);
set local role authenticated;

do $$
declare
  v_id uuid := (select id from public.removal_test_ids where key = 'sub_a_editor');
  v_removed public.newsletter_submissions;
begin
  if not public.may_manage_newsletter() then
    raise exception 'The appointed editor may not manage the newsletter.';
  end if;

  v_removed := public.delete_newsletter_submission(v_id);

  if v_removed.id is distinct from v_id then
    raise exception 'The editor removed the wrong story.';
  end if;
  if v_removed.devotee_id <> '4e000000-0000-0000-0000-000000000002' then
    raise exception 'The editor removed a story belonging to somebody unexpected.';
  end if;
  if exists (
    select 1 from public.newsletter_submissions where newsletter_submissions.id = v_id
  ) then
    raise exception 'The story the editor removed is still there.';
  end if;
end;
$$;

do $$
declare
  v_case record;
  v_message text;
begin
  for v_case in
    select removal_test_ids.key, removal_test_ids.id
    from public.removal_test_ids
    where removal_test_ids.key in ('fb_a_keep', 'fb_b_keep')
  loop
    v_message := null;
    begin
      perform public.delete_feedback(v_case.id);
    exception when others then
      v_message := sqlerrm;
    end;

    if v_message is null then
      raise exception 'A newsletter editor removed %, which is feedback.', v_case.key;
    end if;
  end loop;

  if public.may_delete_feedback('4e000000-0000-0000-0000-000000000002') then
    raise exception 'Editing the newsletter has leaked into removing feedback.';
  end if;
  if exists (select 1 from public.list_all_feedback()) then
    raise exception 'A newsletter editor can read the feedback queue.';
  end if;
end;
$$;

reset role;

do $$
declare
  v_case record;
begin
  for v_case in
    select removal_test_ids.key, removal_test_ids.id
    from public.removal_test_ids
    where removal_test_ids.key in ('fb_a_keep', 'fb_b_keep')
  loop
    if not exists (select 1 from public.feedback where feedback.id = v_case.id) then
      raise exception 'Refusing the newsletter editor still removed %.', v_case.key;
    end if;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- 11. A plain devotee cannot remove somebody else's story.
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', '4e000000-0000-0000-0000-000000000003', true);
set local role authenticated;

do $$
declare
  v_id uuid := (select id from public.removal_test_ids where key = 'sub_a_guarded');
  v_message text;
begin
  if public.may_manage_newsletter() then
    raise exception 'A plain devotee may manage the newsletter.';
  end if;

  begin
    perform public.delete_newsletter_submission(v_id);
  exception when others then
    v_message := sqlerrm;
  end;

  if v_message is null then
    raise exception 'A plain devotee removed somebody else''s newsletter story.';
  end if;
  if v_message not like '%your own%' then
    raise exception 'Refusing a plain devotee said "%", which does not say whose story they may remove.',
      v_message;
  end if;
end;
$$;

reset role;

do $$
declare
  v_id uuid := (select id from public.removal_test_ids where key = 'sub_a_guarded');
begin
  if not exists (
    select 1 from public.newsletter_submissions where newsletter_submissions.id = v_id
  ) then
    raise exception 'Refusing a plain devotee still removed the story.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 12. can_delete on the two newsletter lists, while E is still an editor.
--
--     The contrast worth looking at is on list_my_newsletter_submissions: for
--     Devotee A can_manage is false and can_delete is true on the very same
--     row. The two flags answer different questions, and a client that reused
--     one for the other would hide the remove button from every devotee who is
--     not an editor — which is the whole feature.
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', '4e000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_row record;
  v_rows integer := 0;
begin
  for v_row in select * from public.list_my_newsletter_submissions() loop
    v_rows := v_rows + 1;
    if v_row.can_manage is not false then
      raise exception 'A plain devotee is told they manage the newsletter.';
    end if;
    if v_row.can_delete is not true then
      raise exception 'A devotee is told they cannot remove their own story.';
    end if;
  end loop;

  if v_rows <> 2 then
    raise exception 'Devotee A should have 2 stories left, has %.', v_rows;
  end if;

  if exists (select 1 from public.list_all_newsletter_submissions()) then
    raise exception 'A plain devotee can read the whole newsletter queue.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '4e000000-0000-0000-0000-000000000006', true);
set local role authenticated;

do $$
declare
  v_row record;
  v_rows integer := 0;
  v_others integer := 0;
begin
  for v_row in select * from public.list_my_newsletter_submissions() loop
    v_rows := v_rows + 1;
    if v_row.can_manage is not true then
      raise exception 'The appointed editor is told they do not manage the newsletter.';
    end if;
    if v_row.can_delete is not true then
      raise exception 'The editor cannot remove their own story.';
    end if;
  end loop;

  if v_rows <> 2 then
    raise exception 'The editor should see 2 stories of their own, sees %.', v_rows;
  end if;

  v_rows := 0;
  for v_row in select * from public.list_all_newsletter_submissions() loop
    v_rows := v_rows + 1;
    if v_row.can_delete is not true then
      raise exception 'The editor is told they cannot remove the story of %.',
        v_row.devotee_name;
    end if;
    if v_row.can_delete
       is distinct from public.may_delete_newsletter_submission(v_row.devotee_id) then
      raise exception
        'can_delete disagrees with may_delete_newsletter_submission for %.', v_row.id;
    end if;
    if v_row.devotee_id <> '4e000000-0000-0000-0000-000000000006' then
      v_others := v_others + 1;
    end if;
  end loop;

  if v_rows <> 4 then
    raise exception 'The editor should see all 4 remaining stories, sees %.', v_rows;
  end if;
  if v_others <> 2 then
    raise exception
      'The editor should see 2 stories belonging to other devotees, sees %.', v_others;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 13. A revoked editor cannot remove somebody else's story, and never could
--     again — but their own is still their own.
--
--     Being asked to stop editing the newsletter and being able to clear out
--     other people's submissions on the way out are not the same thing. This is
--     the same shape delete_newsletter already has, and the reason the
--     predicate reads the appointment live rather than caching anything.
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', '4e000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
begin
  perform public.revoke_newsletter_editor('4e000000-0000-0000-0000-000000000006');
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '4e000000-0000-0000-0000-000000000006', true);
set local role authenticated;

do $$
declare
  v_case record;
  v_message text;
begin
  if public.may_manage_newsletter() then
    raise exception 'A revoked editor still manages the newsletter.';
  end if;

  for v_case in
    select removal_test_ids.key, removal_test_ids.id
    from public.removal_test_ids
    where removal_test_ids.key in ('sub_a_guarded', 'sub_a_keep')
  loop
    v_message := null;
    begin
      perform public.delete_newsletter_submission(v_case.id);
    exception when others then
      v_message := sqlerrm;
    end;

    if v_message is null then
      raise exception 'A revoked editor removed %.', v_case.key;
    end if;
  end loop;

  if public.may_delete_newsletter_submission('4e000000-0000-0000-0000-000000000002') then
    raise exception 'may_delete_newsletter_submission still says yes to a revoked editor.';
  end if;
  if exists (select 1 from public.list_all_newsletter_submissions()) then
    raise exception 'A revoked editor can still read the newsletter queue.';
  end if;
end;
$$;

reset role;

do $$
declare
  v_case record;
begin
  for v_case in
    select removal_test_ids.key, removal_test_ids.id
    from public.removal_test_ids
    where removal_test_ids.key in ('sub_a_guarded', 'sub_a_keep')
  loop
    if not exists (
      select 1 from public.newsletter_submissions
      where newsletter_submissions.id = v_case.id
    ) then
      raise exception 'Refusing the revoked editor still removed %.', v_case.key;
    end if;
  end loop;
end;
$$;

select set_config('request.jwt.claim.sub', '4e000000-0000-0000-0000-000000000006', true);
set local role authenticated;

do $$
declare
  v_row record;
  v_id uuid := (select id from public.removal_test_ids where key = 'sub_e_own');
  v_removed public.newsletter_submissions;
  v_rows integer := 0;
begin
  for v_row in select * from public.list_my_newsletter_submissions() loop
    v_rows := v_rows + 1;
    if v_row.can_manage is not false then
      raise exception 'A revoked editor is still told they manage the newsletter.';
    end if;
    if v_row.can_delete is not true then
      raise exception 'A revoked editor cannot remove their own story.';
    end if;
  end loop;

  if v_rows <> 2 then
    raise exception 'The revoked editor should still see their own 2 stories, sees %.', v_rows;
  end if;

  v_removed := public.delete_newsletter_submission(v_id);
  if v_removed.id is distinct from v_id then
    raise exception 'The revoked editor removed the wrong story of their own.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 14. The predicates say no in exactly the cases the RPCs refuse.
--
--     The flag the client draws a button from and the check the delete makes
--     are the same function, so this is where the false half of can_delete is
--     nailed down: against an author who is not the caller, for every persona
--     in the script.
-- ---------------------------------------------------------------------------

reset role;

do $$
declare
  v_case record;
  v_actual boolean;
begin
  for v_case in
    select * from (values
      -- caller, author, may remove feedback, may remove a story
      ('4e000000-0000-0000-0000-000000000002', '4e000000-0000-0000-0000-000000000002', true,  true),
      ('4e000000-0000-0000-0000-000000000002', '4e000000-0000-0000-0000-000000000003', false, false),
      ('4e000000-0000-0000-0000-000000000003', '4e000000-0000-0000-0000-000000000002', false, false),
      ('4e000000-0000-0000-0000-000000000005', '4e000000-0000-0000-0000-000000000002', false, false),
      ('4e000000-0000-0000-0000-000000000006', '4e000000-0000-0000-0000-000000000002', false, false),
      ('4e000000-0000-0000-0000-000000000001', '4e000000-0000-0000-0000-000000000002', true,  true),
      ('4e000000-0000-0000-0000-000000000004', '4e000000-0000-0000-0000-000000000002', true,  true)
    ) as expected(caller, author, feedback_ok, story_ok)
  loop
    perform set_config('request.jwt.claim.sub', v_case.caller, true);

    v_actual := public.may_delete_feedback(v_case.author::uuid);
    if v_actual is distinct from v_case.feedback_ok then
      raise exception 'may_delete_feedback(% as %) is % and should be %.',
        v_case.author, v_case.caller, v_actual, v_case.feedback_ok;
    end if;

    v_actual := public.may_delete_newsletter_submission(v_case.author::uuid);
    if v_actual is distinct from v_case.story_ok then
      raise exception 'may_delete_newsletter_submission(% as %) is % and should be %.',
        v_case.author, v_case.caller, v_actual, v_case.story_ok;
    end if;
  end loop;

  -- Signed out, nobody may remove anything, not even a row whose author id is
  -- also null.
  perform set_config('request.jwt.claim.sub', '', true);
  if public.may_delete_feedback(null) then
    raise exception 'may_delete_feedback says yes to a signed-out caller.';
  end if;
  if public.may_delete_newsletter_submission(null) then
    raise exception 'may_delete_newsletter_submission says yes to a signed-out caller.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 15. Signed out, and asked for something that is not there.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', '', true);
set local role authenticated;

do $$
declare
  v_case record;
  v_message text;
begin
  for v_case in
    select removal_test_ids.key, removal_test_ids.id
    from public.removal_test_ids
    where removal_test_ids.key in ('fb_a_keep', 'sub_a_keep')
  loop
    v_message := null;
    begin
      if v_case.key like 'fb%' then
        perform public.delete_feedback(v_case.id);
      else
        perform public.delete_newsletter_submission(v_case.id);
      end if;
    exception when others then
      v_message := sqlerrm;
    end;

    if v_message is null then
      raise exception 'A signed-out caller removed %.', v_case.key;
    end if;
    if v_message not like 'Sign in%' then
      raise exception 'A signed-out caller was told "%" rather than to sign in.', v_message;
    end if;
  end loop;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '4e000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
  v_message text;
begin
  v_message := null;
  begin
    perform public.delete_feedback('4e000000-0000-0000-0000-0000000000ff');
  exception when others then
    v_message := sqlerrm;
  end;
  if v_message is null or v_message not like '%could not be found%' then
    raise exception 'Removing feedback that does not exist said "%".', v_message;
  end if;

  v_message := null;
  begin
    perform public.delete_newsletter_submission('4e000000-0000-0000-0000-0000000000ff');
  exception when others then
    v_message := sqlerrm;
  end;
  if v_message is null or v_message not like '%could not be found%' then
    raise exception 'Removing a story that does not exist said "%".', v_message;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 16. Gone means gone, and nothing else went with it.
--
--     A hard delete was chosen because nothing references either table, so the
--     row can simply leave. Two things follow that are worth pinning down: no
--     tombstone column crept in, so no future reader has to remember to filter
--     on one; and the deletes took exactly the rows they were asked for and no
--     others.
-- ---------------------------------------------------------------------------

reset role;

do $$
declare
  v_column text;
  v_table text;
begin
  foreach v_table in array array['feedback', 'newsletter_submissions'] loop
    for v_column in
      select columns.column_name
      from information_schema.columns
      where columns.table_schema = 'public'
        and columns.table_name = v_table
        and columns.column_name in ('deleted_at', 'deleted_by', 'is_deleted', 'removed_at')
    loop
      raise exception
        'public.% grew a % column; this feature was specified as a hard delete.',
        v_table, v_column;
    end loop;
  end loop;

  -- Nothing points at either table, which is the fact the hard delete rests on.
  if exists (
    select 1
    from pg_constraint
    where pg_constraint.contype = 'f'
      and pg_constraint.confrelid in (
        'public.feedback'::regclass, 'public.newsletter_submissions'::regclass
      )
  ) then
    raise exception
      'Something now references feedback or newsletter_submissions; a hard delete is no longer safe.';
  end if;
end;
$$;

do $$
declare
  v_feedback integer;
  v_submissions integer;
  v_key text;
begin
  select count(*)::integer into v_feedback from public.feedback;
  select count(*)::integer into v_submissions from public.newsletter_submissions;

  if v_feedback <> 2 then
    raise exception 'Expected 2 pieces of feedback to survive, found %.', v_feedback;
  end if;
  if v_submissions <> 3 then
    raise exception 'Expected 3 story submissions to survive, found %.', v_submissions;
  end if;

  foreach v_key in array array['fb_a_keep', 'fb_b_keep'] loop
    if not exists (
      select 1 from public.feedback
      where feedback.id = (select id from public.removal_test_ids where key = v_key)
    ) then
      raise exception '% was removed by something that was never asked to.', v_key;
    end if;
  end loop;

  foreach v_key in array array['sub_a_guarded', 'sub_a_keep', 'sub_e_keep'] loop
    if not exists (
      select 1 from public.newsletter_submissions
      where newsletter_submissions.id = (select id from public.removal_test_ids where key = v_key)
    ) then
      raise exception '% was removed by something that was never asked to.', v_key;
    end if;
  end loop;
end;
$$;

do $$
begin
  raise notice 'all removal checks passed';
end;
$$;

select 'removals verification passed' as result;

rollback;
