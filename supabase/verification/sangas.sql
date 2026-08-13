-- Functional verification for 202608040039_sangas.sql.
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
--   President  ...0001  approves that the temple runs a sanga at all
--   Founder    ...0002  starts three, and runs the youth one
--   Friend     ...0003  asks to join, is let in, is removed, asks again
--   Newcomer   ...0004  is added directly, and is later handed the sanga
--   Outsider   ...0005  is in nothing, and must be refused everything
--
-- The final row must read: sangas verification passed

begin;

-- The President exists and holds their role before anything is proposed, so
-- the "a devotee proposed a new sanga" notification has somebody to reach.
insert into auth.users (id, email, raw_user_meta_data) values
  ('90000000-0000-0000-0000-000000000001', 'sanga-president@example.test', '{"name":"Sanga President"}');

update public.users
set role_id = (select roles.id from public.roles where roles.name = 'president')
where email = 'sanga-president@example.test';

insert into auth.users (id, email, raw_user_meta_data) values
  ('90000000-0000-0000-0000-000000000002', 'sanga-founder@example.test', '{"name":"Sanga Founder"}'),
  ('90000000-0000-0000-0000-000000000003', 'sanga-friend@example.test', '{"name":"Sanga Friend"}'),
  ('90000000-0000-0000-0000-000000000004', 'sanga-newcomer@example.test', '{"name":"Sanga Newcomer"}'),
  ('90000000-0000-0000-0000-000000000005', 'sanga-outsider@example.test', '{"name":"Sanga Outsider"}');

-- Ordinary table rather than a temporary one, so reading it under the
-- authenticated role needs no assumptions about the temp schema. The whole
-- script is rolled back, so it never outlives the transaction.
create table public.sanga_test_ids (key text primary key, id uuid not null);
grant select, insert on public.sanga_test_ids to authenticated;

-- ---------------------------------------------------------------------------
-- 1. Any signed-in devotee can start a sanga, and it waits for the President.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_youth public.sangas;
  v_kirtan public.sangas;
  v_story public.sangas;
  v_refused boolean;
  v_members integer;
  v_role text;
begin
  v_youth := public.create_sanga('Youth Sanga', 'Devotees in their teens and twenties.');
  if v_youth.id is null then
    raise exception 'A plain devotee could not start a sanga.';
  end if;
  if v_youth.status <> 'pending' then
    raise exception 'A brand new sanga was % rather than pending.', v_youth.status;
  end if;
  if v_youth.reviewed_at is not null or v_youth.reviewed_by is not null then
    raise exception 'A sanga nobody has looked at claims to have been reviewed.';
  end if;
  if v_youth.created_by <> '90000000-0000-0000-0000-000000000002' then
    raise exception 'The sanga did not record who started it.';
  end if;
  if v_youth.admin_id <> '90000000-0000-0000-0000-000000000002' then
    raise exception 'The devotee who started the sanga is not its admin.';
  end if;
  if not v_youth.active then
    raise exception 'A brand new sanga was not active.';
  end if;

  -- The founder is in their own circle, running it, from the first moment.
  select count(*)::integer into v_members
  from public.list_sanga_members(v_youth.id);
  if v_members <> 1 then
    raise exception 'A brand new sanga has % members rather than its founder.', v_members;
  end if;
  select members.role into v_role
  from public.list_sanga_members(v_youth.id) members
  where members.id = '90000000-0000-0000-0000-000000000002';
  if v_role is distinct from 'admin' then
    raise exception 'The founder is in the sanga as % rather than admin.', v_role;
  end if;

  v_kirtan := public.create_sanga('Kirtan Sanga', 'Wednesday evening kirtan.');
  v_story := public.create_sanga('Sunday Story Hour', 'Stories for the little ones.');

  insert into public.sanga_test_ids values
    ('youth', v_youth.id),
    ('kirtan', v_kirtan.id),
    ('story', v_story.id);

  v_refused := false;
  begin
    perform public.create_sanga('   ', 'No name at all.');
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A sanga with a blank name was accepted.';
  end if;

  -- Same circle, different capitals — and the first one has not even been
  -- approved yet. Accepting this would split one group across two rows nobody
  -- could tell apart.
  v_refused := false;
  begin
    perform public.create_sanga('youth sanga', 'The same circle again.');
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A second sanga with the same name was accepted.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. A pending sanga is invisible to everybody else, and cannot be joined.
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000005', true);
set local role authenticated;

do $$
declare
  v_youth uuid := (select ids.id from public.sanga_test_ids ids where ids.key = 'youth');
  v_rows integer;
  v_refused boolean;
begin
  select count(*)::integer into v_rows
  from public.list_sangas() listed
  where listed.id in (select ids.id from public.sanga_test_ids ids);
  if v_rows <> 0 then
    raise exception 'A devotee can browse % sangas that are still waiting for approval.', v_rows;
  end if;

  -- Not through the RPC and not through the table either.
  select count(*)::integer into v_rows from public.sangas where sangas.id = v_youth;
  if v_rows <> 0 then
    raise exception 'Row level security let a devotee read a pending sanga.';
  end if;

  select count(*)::integer into v_rows from public.list_sanga_members(v_youth);
  if v_rows <> 0 then
    raise exception 'A devotee can see who is in a sanga that has not been approved.';
  end if;

  v_refused := false;
  begin
    perform public.request_to_join_sanga(v_youth, 'Let me in early.');
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A devotee asked to join a sanga that has not been approved.';
  end if;

  -- The approval queue belongs to the President alone.
  select count(*)::integer into v_rows from public.list_pending_sangas();
  if v_rows <> 0 then
    raise exception 'A plain devotee can see % sangas awaiting approval.', v_rows;
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_youth uuid := (select ids.id from public.sanga_test_ids ids where ids.key = 'youth');
  v_mine record;
begin
  -- The founder is not left staring at nothing while they wait.
  select * into v_mine from public.list_my_sangas() mine where mine.id = v_youth;
  if v_mine.id is null then
    raise exception 'The devotee who proposed a sanga cannot see it.';
  end if;
  if v_mine.status <> 'pending' then
    raise exception 'Their own sanga reads % rather than pending.', v_mine.status;
  end if;
  if not v_mine.is_admin or not v_mine.is_member then
    raise exception 'The founder is not shown as running their own sanga.';
  end if;
  if v_mine.member_count <> 1 then
    raise exception 'A brand new sanga reports % members.', v_mine.member_count;
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
  v_youth uuid := (select ids.id from public.sanga_test_ids ids where ids.key = 'youth');
  v_waiting record;
  v_rows integer;
begin
  select count(*)::integer into v_rows from public.list_pending_sangas();
  if v_rows <> 3 then
    raise exception 'The President sees % sangas waiting rather than 3.', v_rows;
  end if;

  select * into v_waiting from public.list_pending_sangas() waiting
  where waiting.id = v_youth;
  if v_waiting.created_by_name is distinct from 'Sanga Founder' then
    raise exception 'The approval queue does not say who asked (got %).', v_waiting.created_by_name;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Only the President decides. Not the founder, not a passer-by.
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000005', true);
set local role authenticated;

do $$
declare
  v_youth uuid := (select ids.id from public.sanga_test_ids ids where ids.key = 'youth');
  v_refused boolean := false;
begin
  begin
    perform public.review_sanga(v_youth, 'approved');
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A plain devotee approved a sanga.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_youth uuid := (select ids.id from public.sanga_test_ids ids where ids.key = 'youth');
  v_refused boolean := false;
begin
  -- Running a sanga is not the same as being allowed to bring it into being.
  begin
    perform public.review_sanga(v_youth, 'approved');
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'The founder approved their own sanga.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
  v_youth uuid := (select ids.id from public.sanga_test_ids ids where ids.key = 'youth');
  v_kirtan uuid := (select ids.id from public.sanga_test_ids ids where ids.key = 'kirtan');
  v_story uuid := (select ids.id from public.sanga_test_ids ids where ids.key = 'story');
  v_decided public.sangas;
  v_refused boolean;
begin
  v_decided := public.review_sanga(v_youth, 'approved');
  if v_decided.status <> 'approved' then
    raise exception 'Approving left the sanga at %.', v_decided.status;
  end if;
  if v_decided.reviewed_by <> '90000000-0000-0000-0000-000000000001'
     or v_decided.reviewed_at is null then
    raise exception 'The decision did not record who made it, or when.';
  end if;

  perform public.review_sanga(v_kirtan, 'approved');

  v_decided := public.review_sanga(v_story, 'declined', 'The children''s programme already covers this.');
  if v_decided.status <> 'declined' then
    raise exception 'Declining left the sanga at %.', v_decided.status;
  end if;
  if v_decided.review_note is null then
    raise exception 'The President''s reason was not kept.';
  end if;

  -- Deciding twice is not allowed; nor is inventing a third answer.
  v_refused := false;
  begin
    perform public.review_sanga(v_youth, 'declined');
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A sanga was decided twice.';
  end if;

  v_refused := false;
  begin
    perform public.review_sanga(v_kirtan, 'maybe');
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A decision of "maybe" was accepted.';
  end if;
end;
$$;

reset role;

do $$
declare
  v_told integer;
begin
  select count(*)::integer into v_told from public.app_notifications
  where user_id = '90000000-0000-0000-0000-000000000001'
    and kind = 'sanga_created';
  if v_told <> 3 then
    raise exception 'The President was told about % of the 3 proposed sangas.', v_told;
  end if;

  select count(*)::integer into v_told from public.app_notifications
  where user_id = '90000000-0000-0000-0000-000000000002'
    and kind = 'sanga_reviewed';
  if v_told <> 3 then
    raise exception 'The founder heard back about % of their 3 sangas.', v_told;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Approved sangas are browsable; declined ones are not, and free their name.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000005', true);
set local role authenticated;

do $$
declare
  v_youth uuid := (select ids.id from public.sanga_test_ids ids where ids.key = 'youth');
  v_story uuid := (select ids.id from public.sanga_test_ids ids where ids.key = 'story');
  v_listed integer;
  v_sanga record;
  v_revived public.sangas;
  v_refused boolean;
begin
  select count(*)::integer into v_listed
  from public.list_sangas() listed
  where listed.id in (select ids.id from public.sanga_test_ids ids);
  if v_listed <> 2 then
    raise exception 'A devotee browses % sangas rather than the 2 approved ones.', v_listed;
  end if;

  select count(*)::integer into v_listed
  from public.list_sangas() listed where listed.id = v_story;
  if v_listed <> 0 then
    raise exception 'A declined sanga is on offer.';
  end if;

  select * into v_sanga from public.list_sangas() listed where listed.id = v_youth;
  if v_sanga.member_count <> 1 then
    raise exception 'The youth sanga reports % members rather than 1.', v_sanga.member_count;
  end if;
  if v_sanga.is_member or v_sanga.is_admin then
    raise exception 'A devotee who has joined nothing is shown as a member or admin.';
  end if;
  if v_sanga.request_status is not null then
    raise exception 'A devotee who has asked nothing has request status %.', v_sanga.request_status;
  end if;
  if v_sanga.admin_name is distinct from 'Sanga Founder' then
    raise exception 'The browse list does not say who runs the sanga (got %).', v_sanga.admin_name;
  end if;
  if v_sanga.created_by_name is distinct from 'Sanga Founder' then
    raise exception 'The browse list does not say who started the sanga.';
  end if;
  if v_sanga.description is distinct from 'Devotees in their teens and twenties.' then
    raise exception 'The description did not survive.';
  end if;

  -- A name the President turned down is free for somebody to propose properly.
  v_revived := public.create_sanga('Sunday Story Hour', 'Proposed again, with a plan this time.');
  if v_revived.status <> 'pending' then
    raise exception 'A re-proposed sanga did not start pending.';
  end if;
  insert into public.sanga_test_ids values ('revived', v_revived.id);

  -- An approved name is not.
  v_refused := false;
  begin
    perform public.create_sanga('YOUTH SANGA', 'Shouting the same name.');
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A second sanga took the name of an approved one.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. The admin adds a devotee straight in. Nobody else can.
-- ---------------------------------------------------------------------------

do $$
declare
  v_youth uuid := (select ids.id from public.sanga_test_ids ids where ids.key = 'youth');
  v_refused boolean := false;
begin
  -- Still the outsider, who runs nothing.
  begin
    perform public.add_sanga_member(v_youth, '90000000-0000-0000-0000-000000000005');
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A devotee added themselves to a sanga they do not run.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_youth uuid := (select ids.id from public.sanga_test_ids ids where ids.key = 'youth');
  v_revived uuid := (select ids.id from public.sanga_test_ids ids where ids.key = 'revived');
  v_added public.sanga_members;
  v_again public.sanga_members;
  v_sanga record;
  v_member record;
  v_refused boolean;
begin
  v_added := public.add_sanga_member(v_youth, '90000000-0000-0000-0000-000000000004');
  if v_added.devotee_id <> '90000000-0000-0000-0000-000000000004' then
    raise exception 'Adding a devotee did not record who was added.';
  end if;
  if v_added.role <> 'member' then
    raise exception 'A devotee added to a sanga arrived as %.', v_added.role;
  end if;
  if v_added.added_by <> '90000000-0000-0000-0000-000000000002' then
    raise exception 'The membership does not record which admin added them.';
  end if;

  select * into v_sanga from public.list_sangas() listed where listed.id = v_youth;
  if v_sanga.member_count <> 2 then
    raise exception 'After one devotee was added the sanga reports % members.', v_sanga.member_count;
  end if;

  select * into v_member from public.list_sanga_members(v_youth) members
  where members.id = '90000000-0000-0000-0000-000000000004';
  if v_member.added_by_name is distinct from 'Sanga Founder' then
    raise exception 'The member list does not say who added them (got %).', v_member.added_by_name;
  end if;

  -- The admin taps twice. Nothing duplicates, and nothing is reset.
  v_again := public.add_sanga_member(v_youth, '90000000-0000-0000-0000-000000000004');
  if v_again.joined_at <> v_added.joined_at then
    raise exception 'Adding twice reset when the devotee joined.';
  end if;
  select * into v_sanga from public.list_sangas() listed where listed.id = v_youth;
  if v_sanga.member_count <> 2 then
    raise exception 'Adding twice made the sanga report % members.', v_sanga.member_count;
  end if;

  -- Adding the admin themselves must not quietly demote them.
  perform public.add_sanga_member(v_youth, '90000000-0000-0000-0000-000000000002');
  select * into v_member from public.list_sanga_members(v_youth) members
  where members.id = '90000000-0000-0000-0000-000000000002';
  if v_member.role <> 'admin' then
    raise exception 'Re-adding the admin demoted them to %.', v_member.role;
  end if;

  v_refused := false;
  begin
    perform public.add_sanga_member(v_youth, '90000000-0000-0000-0000-0000000000ff');
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A devotee who does not exist was added to a sanga.';
  end if;

  -- The founder does not run the re-proposed sanga, and it is not running.
  v_refused := false;
  begin
    perform public.add_sanga_member(v_revived, '90000000-0000-0000-0000-000000000004');
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A devotee was added to a sanga that has not been approved.';
  end if;
end;
$$;

reset role;

do $$
declare
  v_told integer;
begin
  select count(*)::integer into v_told from public.app_notifications
  where user_id = '90000000-0000-0000-0000-000000000004'
    and kind = 'sanga_member_added';
  if v_told <> 1 then
    raise exception 'A devotee added once was told % times.', v_told;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. An ordinary member is not an admin.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000004', true);
set local role authenticated;

do $$
declare
  v_youth uuid := (select ids.id from public.sanga_test_ids ids where ids.key = 'youth');
  v_refused boolean;
  v_rows integer;
begin
  v_refused := false;
  begin
    perform public.add_sanga_member(v_youth, '90000000-0000-0000-0000-000000000005');
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'An ordinary member added somebody to the sanga.';
  end if;

  v_refused := false;
  begin
    perform public.remove_sanga_member(v_youth, '90000000-0000-0000-0000-000000000002');
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'An ordinary member removed somebody from the sanga.';
  end if;

  v_refused := false;
  begin
    perform public.transfer_sanga_admin(v_youth, '90000000-0000-0000-0000-000000000004');
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'An ordinary member handed the sanga to themselves.';
  end if;

  -- Who asked and was turned down is the admin's business, not every member's.
  select count(*)::integer into v_rows from public.list_sanga_join_requests(v_youth);
  if v_rows <> 0 then
    raise exception 'An ordinary member can read % of the admin''s join requests.', v_rows;
  end if;

  -- And a member cannot ask to join what they are already in.
  v_refused := false;
  begin
    perform public.request_to_join_sanga(v_youth, 'Let me in.');
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A member of a sanga asked to join it again.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Asking to join is idempotent, and the admin hears about it once.
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000003', true);
set local role authenticated;

do $$
declare
  v_youth uuid := (select ids.id from public.sanga_test_ids ids where ids.key = 'youth');
  v_first public.sanga_join_requests;
  v_again public.sanga_join_requests;
  v_rows integer;
  v_sanga record;
begin
  v_first := public.request_to_join_sanga(v_youth, 'I am nineteen and new to the temple.');
  if v_first.status <> 'pending' then
    raise exception 'A brand new request reads %.', v_first.status;
  end if;
  if v_first.message is null then
    raise exception 'What the devotee wrote was not kept.';
  end if;

  -- The second tap is the same ask.
  v_again := public.request_to_join_sanga(v_youth, 'Asking again because nothing happened.');
  if v_again.id <> v_first.id then
    raise exception 'Asking twice made a second request.';
  end if;

  select count(*)::integer into v_rows from public.sanga_join_requests asked
  where asked.sanga_id = v_youth
    and asked.devotee_id = '90000000-0000-0000-0000-000000000003';
  if v_rows <> 1 then
    raise exception 'Asking twice left % request rows.', v_rows;
  end if;

  select * into v_sanga from public.list_sangas() listed where listed.id = v_youth;
  if v_sanga.request_status is distinct from 'pending' then
    raise exception 'The browse list shows the request as % rather than pending.', v_sanga.request_status;
  end if;
  if v_sanga.is_member then
    raise exception 'Asking to join made the devotee a member outright.';
  end if;
  if v_sanga.member_count <> 2 then
    raise exception 'Asking to join changed the member count to %.', v_sanga.member_count;
  end if;

  -- Kept for the sections below, which need an id that the devotees being
  -- refused could never look up for themselves.
  insert into public.sanga_test_ids values ('friend_request', v_first.id);
end;
$$;

reset role;

do $$
declare
  v_told integer;
begin
  select count(*)::integer into v_told from public.app_notifications
  where user_id = '90000000-0000-0000-0000-000000000002'
    and kind = 'sanga_join_requested';
  if v_told <> 1 then
    raise exception 'The admin was told % times about one request.', v_told;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. Only the admin answers a request, and approving makes exactly one
--    membership.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000005', true);
set local role authenticated;

do $$
declare
  v_youth uuid := (select ids.id from public.sanga_test_ids ids where ids.key = 'youth');
  v_request uuid := (select ids.id from public.sanga_test_ids ids where ids.key = 'friend_request');
  v_rows integer;
  v_refused boolean := false;
begin
  -- The outsider cannot even read the request, let alone answer it.
  select count(*)::integer into v_rows from public.sanga_join_requests asked
  where asked.sanga_id = v_youth;
  if v_rows <> 0 then
    raise exception 'An outsider can read % of a sanga''s join requests.', v_rows;
  end if;

  begin
    perform public.review_sanga_join_request(v_request, 'approved');
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'An outsider answered a join request.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000004', true);
set local role authenticated;

do $$
declare
  v_youth uuid := (select ids.id from public.sanga_test_ids ids where ids.key = 'youth');
  v_request uuid := (select ids.id from public.sanga_test_ids ids where ids.key = 'friend_request');
  v_rows integer;
  v_refused boolean := false;
begin
  -- An ordinary member of the same sanga sees nothing of the inbox either.
  select count(*)::integer into v_rows from public.sanga_join_requests asked
  where asked.sanga_id = v_youth;
  if v_rows <> 0 then
    raise exception 'An ordinary member can read % of a sanga''s join requests.', v_rows;
  end if;

  begin
    perform public.review_sanga_join_request(v_request, 'approved');
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'An ordinary member approved a request to join.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000003', true);
set local role authenticated;

do $$
declare
  v_youth uuid := (select ids.id from public.sanga_test_ids ids where ids.key = 'youth');
  v_rows integer;
begin
  -- The devotee who asked can always see their own ask.
  select count(*)::integer into v_rows from public.sanga_join_requests asked
  where asked.sanga_id = v_youth
    and asked.devotee_id = '90000000-0000-0000-0000-000000000003';
  if v_rows <> 1 then
    raise exception 'A devotee sees % of the one request they made themselves.', v_rows;
  end if;
end;
$$;

-- The President could once do none of this, and this is where that was proved.
-- 202608040043_sanga_powers.sql reversed it at the temple's request: a holder
-- of app.view_all may now answer a request to join, add and remove a devotee,
-- post, take a message down, and delete the sanga. All of that, and the fact
-- that none of it enrols them, is proved in supabase/verification/sanga_powers.sql.

reset role;
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_youth uuid := (select ids.id from public.sanga_test_ids ids where ids.key = 'youth');
  v_request uuid := (select ids.id from public.sanga_test_ids ids where ids.key = 'friend_request');
  v_decided public.sanga_join_requests;
  v_rows integer;
  v_sanga record;
  v_refused boolean;
  v_inbox record;
begin
  select count(*)::integer into v_rows from public.list_sanga_join_requests(v_youth);
  if v_rows <> 1 then
    raise exception 'The admin''s inbox holds % requests rather than 1.', v_rows;
  end if;
  select * into v_inbox from public.list_sanga_join_requests(v_youth) inbox limit 1;
  if v_inbox.devotee_name is distinct from 'Sanga Friend' then
    raise exception 'The inbox does not say who is asking (got %).', v_inbox.devotee_name;
  end if;

  v_decided := public.review_sanga_join_request(v_request, 'approved');
  if v_decided.status <> 'approved' then
    raise exception 'Approving a request left it at %.', v_decided.status;
  end if;
  if v_decided.decided_by <> '90000000-0000-0000-0000-000000000002'
     or v_decided.decided_at is null then
    raise exception 'The decision did not record who made it, or when.';
  end if;

  select count(*)::integer into v_rows from public.sanga_members members
  where members.sanga_id = v_youth
    and members.devotee_id = '90000000-0000-0000-0000-000000000003';
  if v_rows <> 1 then
    raise exception 'Approving one request made % memberships.', v_rows;
  end if;

  select * into v_sanga from public.list_sangas() listed where listed.id = v_youth;
  if v_sanga.member_count <> 3 then
    raise exception 'After the request was approved the sanga reports % members.', v_sanga.member_count;
  end if;

  v_refused := false;
  begin
    perform public.review_sanga_join_request(v_request, 'declined');
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A request was answered twice.';
  end if;
end;
$$;

reset role;

do $$
declare
  v_told integer;
begin
  select count(*)::integer into v_told from public.app_notifications
  where user_id = '90000000-0000-0000-0000-000000000003'
    and kind = 'sanga_join_reviewed';
  if v_told <> 1 then
    raise exception 'The devotee who asked was told % times.', v_told;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 9. Removing a member clears their request with them.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_youth uuid := (select ids.id from public.sanga_test_ids ids where ids.key = 'youth');
  v_removed boolean;
  v_again boolean;
  v_sanga record;
  v_rows integer;
begin
  v_removed := public.remove_sanga_member(v_youth, '90000000-0000-0000-0000-000000000003');
  if not v_removed then
    raise exception 'Removing a member of the sanga did nothing.';
  end if;

  select * into v_sanga from public.list_sangas() listed where listed.id = v_youth;
  if v_sanga.member_count <> 2 then
    raise exception 'After a removal the sanga reports % members.', v_sanga.member_count;
  end if;

  -- The answered request goes with the membership. Left behind it would show
  -- the devotee as approved for a sanga they are not in.
  select count(*)::integer into v_rows from public.list_sanga_join_requests(v_youth);
  if v_rows <> 0 then
    raise exception 'Removing a member left % of their requests behind.', v_rows;
  end if;

  -- Removing twice is quiet.
  v_again := public.remove_sanga_member(v_youth, '90000000-0000-0000-0000-000000000003');
  if v_again then
    raise exception 'Removing twice claimed to remove a membership that was gone.';
  end if;
end;
$$;

reset role;

do $$
declare
  v_told integer;
begin
  select count(*)::integer into v_told from public.app_notifications
  where user_id = '90000000-0000-0000-0000-000000000003'
    and kind = 'sanga_member_removed';
  if v_told <> 1 then
    raise exception 'A devotee removed once was told % times.', v_told;
  end if;
end;
$$;

select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000003', true);
set local role authenticated;

do $$
declare
  v_youth uuid := (select ids.id from public.sanga_test_ids ids where ids.key = 'youth');
  v_sanga record;
  v_fresh public.sanga_join_requests;
begin
  select * into v_sanga from public.list_sangas() listed where listed.id = v_youth;
  if v_sanga.is_member then
    raise exception 'A devotee who was removed is still shown as a member.';
  end if;
  if v_sanga.request_status is not null then
    raise exception 'A removed devotee still carries request status %.', v_sanga.request_status;
  end if;

  -- And they may ask again from a clean slate.
  v_fresh := public.request_to_join_sanga(v_youth, 'I would like to come back.');
  if v_fresh.status <> 'pending' then
    raise exception 'A devotee who was removed could not ask again.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 10. A sanga always has somebody responsible for it.
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_youth uuid := (select ids.id from public.sanga_test_ids ids where ids.key = 'youth');
  v_refused boolean;
  v_admins integer;
begin
  v_refused := false;
  begin
    perform public.remove_sanga_member(v_youth, '90000000-0000-0000-0000-000000000002');
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'The only admin removed themselves and left the sanga unowned.';
  end if;

  v_refused := false;
  begin
    perform public.leave_sanga(v_youth);
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'The only admin walked out and left the sanga unowned.';
  end if;

  -- Still exactly one admin, and still them.
  select count(*)::integer into v_admins from public.sanga_members members
  where members.sanga_id = v_youth and members.role = 'admin';
  if v_admins <> 1 then
    raise exception 'The sanga has % admins.', v_admins;
  end if;

  -- Handing over needs a real successor, already inside the circle.
  v_refused := false;
  begin
    perform public.transfer_sanga_admin(v_youth, '90000000-0000-0000-0000-000000000005');
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A sanga was handed to somebody who is not in it.';
  end if;

  v_refused := false;
  begin
    perform public.transfer_sanga_admin(v_youth, '90000000-0000-0000-0000-000000000002');
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A sanga was handed to the devotee who already runs it.';
  end if;
end;
$$;

do $$
declare
  v_youth uuid := (select ids.id from public.sanga_test_ids ids where ids.key = 'youth');
  v_handed public.sangas;
  v_admins integer;
  v_sanga record;
  v_left boolean;
  v_again boolean;
  v_refused boolean;
begin
  v_handed := public.transfer_sanga_admin(v_youth, '90000000-0000-0000-0000-000000000004');
  if v_handed.admin_id <> '90000000-0000-0000-0000-000000000004' then
    raise exception 'Handing the sanga over did not change who runs it.';
  end if;

  select count(*)::integer into v_admins from public.sanga_members members
  where members.sanga_id = v_youth and members.role = 'admin';
  if v_admins <> 1 then
    raise exception 'After a handover the sanga has % admins.', v_admins;
  end if;

  select * into v_sanga from public.list_sangas() listed where listed.id = v_youth;
  if v_sanga.is_admin then
    raise exception 'The previous admin is still shown as running the sanga.';
  end if;
  if not v_sanga.is_member then
    raise exception 'Handing the sanga over pushed the previous admin out of it.';
  end if;

  -- Now that somebody else is responsible, they may go.
  v_left := public.leave_sanga(v_youth);
  if not v_left then
    raise exception 'A member who handed the sanga on could not leave it.';
  end if;

  select * into v_sanga from public.list_sangas() listed where listed.id = v_youth;
  if v_sanga.is_member then
    raise exception 'A devotee who left is still shown as a member.';
  end if;
  if v_sanga.member_count <> 1 then
    raise exception 'After the handover and the departure the sanga reports % members.', v_sanga.member_count;
  end if;

  v_again := public.leave_sanga(v_youth);
  if v_again then
    raise exception 'Leaving twice claimed to remove a membership that was gone.';
  end if;

  -- And they can no longer act as its admin.
  v_refused := false;
  begin
    perform public.add_sanga_member(v_youth, '90000000-0000-0000-0000-000000000005');
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A devotee who handed the sanga on can still add members.';
  end if;
end;
$$;

reset role;

do $$
declare
  v_told integer;
begin
  select count(*)::integer into v_told from public.app_notifications
  where user_id = '90000000-0000-0000-0000-000000000004'
    and kind = 'sanga_admin_transferred';
  if v_told <> 1 then
    raise exception 'The new admin was told % times that they now run the sanga.', v_told;
  end if;

  select count(*)::integer into v_told from public.app_notifications
  where user_id = '90000000-0000-0000-0000-000000000004'
    and kind = 'sanga_member_left';
  if v_told <> 1 then
    raise exception 'The admin was told % times that somebody left.', v_told;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 11. Nothing is writable directly except an admin's own name and shutter.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000005', true);
set local role authenticated;

do $$
declare
  v_youth uuid := (select ids.id from public.sanga_test_ids ids where ids.key = 'youth');
  v_refused boolean;
  v_touched integer;
begin
  v_refused := false;
  begin
    insert into public.sanga_members (sanga_id, devotee_id)
    values (v_youth, '90000000-0000-0000-0000-000000000005');
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A devotee signed themselves into a sanga behind the admin''s back.';
  end if;

  v_refused := false;
  begin
    insert into public.sanga_join_requests (sanga_id, devotee_id, status)
    values (v_youth, '90000000-0000-0000-0000-000000000005', 'approved');
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A devotee wrote themselves an approved join request.';
  end if;

  v_refused := false;
  begin
    delete from public.sanga_members
    where sanga_members.sanga_id = v_youth;
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A devotee emptied a sanga''s membership.';
  end if;

  -- status is not a granted column, so there is no way to approve a sanga by
  -- updating the table.
  v_refused := false;
  begin
    update public.sangas set status = 'approved'
    where sangas.id = (select ids.id from public.sanga_test_ids ids where ids.key = 'revived');
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A devotee approved their own sanga with a plain update.';
  end if;

  -- Renaming is granted, but the policy only lets the admin through.
  update public.sangas set name = 'Renamed By A Passer By' where sangas.id = v_youth;
  get diagnostics v_touched = row_count;
  if v_touched <> 0 then
    raise exception 'A devotee renamed a sanga they do not run.';
  end if;

  update public.sangas set active = false where sangas.id = v_youth;
  get diagnostics v_touched = row_count;
  if v_touched <> 0 then
    raise exception 'A devotee retired a sanga they do not run.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000004', true);
set local role authenticated;

do $$
declare
  v_youth uuid := (select ids.id from public.sanga_test_ids ids where ids.key = 'youth');
  v_touched integer;
  v_refused boolean;
begin
  update public.sangas
  set name = 'Youth and Young Adults Sanga',
      description = 'Renamed by the devotee who runs it.'
  where sangas.id = v_youth;
  get diagnostics v_touched = row_count;
  if v_touched <> 1 then
    raise exception 'The admin could not rename their own sanga.';
  end if;

  -- Not onto a name somebody else is already using.
  v_refused := false;
  begin
    update public.sangas set name = 'kirtan sanga' where sangas.id = v_youth;
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A sanga was renamed onto another sanga''s name.';
  end if;

  update public.sangas set active = false where sangas.id = v_youth;
  get diagnostics v_touched = row_count;
  if v_touched <> 1 then
    raise exception 'The admin could not retire their own sanga.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000005', true);
set local role authenticated;

do $$
declare
  v_youth uuid := (select ids.id from public.sanga_test_ids ids where ids.key = 'youth');
  v_rows integer;
  v_refused boolean := false;
begin
  select count(*)::integer into v_rows
  from public.list_sangas() listed where listed.id = v_youth;
  if v_rows <> 0 then
    raise exception 'A retired sanga is still on offer.';
  end if;

  begin
    perform public.request_to_join_sanga(v_youth, 'Is this still running?');
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A devotee asked to join a retired sanga.';
  end if;

  v_refused := false;
  begin
    perform public.request_to_join_sanga('90000000-0000-0000-0000-0000000000ff', 'Anybody there?');
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A devotee asked to join a sanga that does not exist.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 12. What everyone is left holding.
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000004', true);
set local role authenticated;

do $$
declare
  v_youth uuid := (select ids.id from public.sanga_test_ids ids where ids.key = 'youth');
  v_mine record;
begin
  -- The admin still sees their retired sanga, and can bring it back.
  select * into v_mine from public.list_my_sangas() mine where mine.id = v_youth;
  if v_mine.id is null then
    raise exception 'The admin lost sight of the sanga they retired.';
  end if;
  if v_mine.active then
    raise exception 'A retired sanga still reads as active.';
  end if;
  if v_mine.member_count <> 1 then
    raise exception 'The retired sanga holds % members rather than its admin alone.', v_mine.member_count;
  end if;

  update public.sangas set active = true where sangas.id = v_youth;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000005', true);
set local role authenticated;

do $$
declare
  v_youth uuid := (select ids.id from public.sanga_test_ids ids where ids.key = 'youth');
  v_revived uuid := (select ids.id from public.sanga_test_ids ids where ids.key = 'revived');
  v_sanga record;
  v_mine record;
  v_names text;
begin
  select * into v_sanga from public.list_sangas() listed where listed.id = v_youth;
  if v_sanga.id is null then
    raise exception 'A revived sanga did not come back onto the list.';
  end if;
  if v_sanga.member_count <> 1 then
    raise exception 'The revived sanga reports % members.', v_sanga.member_count;
  end if;
  if v_sanga.admin_name is distinct from 'Sanga Newcomer' then
    raise exception 'The list names % as running the sanga.', v_sanga.admin_name;
  end if;
  if v_sanga.created_by_name is distinct from 'Sanga Founder' then
    raise exception 'The sanga forgot who first proposed it.';
  end if;

  select string_agg(members.name, ', ' order by members.name) into v_names
  from public.list_sanga_members(v_youth) members;
  if v_names is distinct from 'Sanga Newcomer' then
    raise exception 'The member list reads "%".', v_names;
  end if;

  -- The outsider's own re-proposed sanga is still waiting, and only they and
  -- the President can see it.
  select * into v_mine from public.list_my_sangas() mine where mine.id = v_revived;
  if v_mine.status <> 'pending' then
    raise exception 'The re-proposed sanga reads % rather than pending.', v_mine.status;
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_revived uuid := (select ids.id from public.sanga_test_ids ids where ids.key = 'revived');
  v_rows integer;
begin
  select count(*)::integer into v_rows from public.sangas where sangas.id = v_revived;
  if v_rows <> 0 then
    raise exception 'Somebody else''s pending sanga is visible to a devotee.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 13. The sanga is a group chat. Members talk; nobody outside it does.
--
--     Where the script leaves off, the youth sanga is running again and the
--     Newcomer runs it alone. They let the Friend back in, and the two of them
--     have a thread.
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000004', true);
set local role authenticated;

do $$
declare
  v_youth uuid := (select ids.id from public.sanga_test_ids ids where ids.key = 'youth');
  v_first public.sanga_messages;
  v_refused boolean;
begin
  perform public.add_sanga_member(v_youth, '90000000-0000-0000-0000-000000000003');

  v_first := public.send_sanga_message(v_youth, 'Kirtan at six on Friday.');
  if v_first.id is null then
    raise exception 'The devotee who runs the sanga could not post in it.';
  end if;
  if v_first.sender_id <> '90000000-0000-0000-0000-000000000004' then
    raise exception 'The message did not record who sent it.';
  end if;
  if v_first.sanga_id <> v_youth then
    raise exception 'The message was filed against the wrong sanga.';
  end if;
  if v_first.body is distinct from 'Kirtan at six on Friday.' then
    raise exception 'What was said did not survive (got %).', v_first.body;
  end if;
  if v_first.deleted_at is not null then
    raise exception 'A message that was just sent is already deleted.';
  end if;
  insert into public.sanga_test_ids values ('admin_message', v_first.id);

  v_refused := false;
  begin
    perform public.send_sanga_message(v_youth, '   ');
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A message with nothing in it was accepted.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000003', true);
set local role authenticated;

do $$
declare
  v_youth uuid := (select ids.id from public.sanga_test_ids ids where ids.key = 'youth');
  v_one public.sanga_messages;
  v_two public.sanga_messages;
  v_rows integer;
  v_said record;
  v_refused boolean;
begin
  v_one := public.send_sanga_message(v_youth, 'I will bring the kartals.');
  insert into public.sanga_test_ids values ('friend_message_one', v_one.id);

  -- A picture with no words, carried in the bucket direct messages already use.
  v_two := public.send_sanga_message(
    v_youth, null,
    'https://example.test/storage/v1/object/public/message-images/90000000-0000-0000-0000-000000000003/kartals.jpg'
  );
  if v_two.image_url is null then
    raise exception 'The picture attached to a message was dropped.';
  end if;
  if v_two.body is not null then
    raise exception 'A message with no words came back with a body of "%".', v_two.body;
  end if;
  insert into public.sanga_test_ids values ('friend_message_two', v_two.id);

  -- A member reads the whole thread, oldest first.
  select count(*)::integer into v_rows from public.list_sanga_messages(v_youth);
  if v_rows <> 3 then
    raise exception 'A member of the sanga reads % of its 3 messages.', v_rows;
  end if;

  -- Picked out by id rather than by position: the whole script runs in one
  -- transaction, so now() is the same instant for every message and the order
  -- they come back in is a tie this script cannot break.
  select * into v_said from public.list_sanga_messages(v_youth) said
  where said.id = (select ids.id from public.sanga_test_ids ids where ids.key = 'admin_message');
  if v_said.body is distinct from 'Kirtan at six on Friday.' then
    raise exception 'The thread lost what was said (got %).', v_said.body;
  end if;
  if v_said.sender_name is distinct from 'Sanga Newcomer' then
    raise exception 'The thread does not say who spoke (got %).', v_said.sender_name;
  end if;
  if v_said.sanga_id <> v_youth then
    raise exception 'The thread returned a message from another sanga.';
  end if;

  -- And through the table as well, so the policy is doing the work too.
  select count(*)::integer into v_rows from public.sanga_messages
  where sanga_messages.sanga_id = v_youth;
  if v_rows <> 3 then
    raise exception 'Row level security showed a member % of the 3 messages.', v_rows;
  end if;

  -- What a deleted message used to hold is outside the grant, so no query a
  -- devotee's client can write reaches it.
  v_refused := false;
  begin
    execute 'select original_body from public.sanga_messages limit 1';
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A devotee can read what a deleted message used to say.';
  end if;

  -- A sanga still waiting for the President is closed to a devotee who has
  -- nothing to do with it. The section below is the contrast.
  select count(*)::integer into v_rows
  from public.list_sanga_members(
    (select ids.id from public.sanga_test_ids ids where ids.key = 'revived')
  );
  if v_rows <> 0 then
    raise exception 'A devotee sees % members of a sanga that is still waiting.', v_rows;
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000005', true);
set local role authenticated;

do $$
declare
  v_youth uuid := (select ids.id from public.sanga_test_ids ids where ids.key = 'youth');
  v_revived uuid := (select ids.id from public.sanga_test_ids ids where ids.key = 'revived');
  v_admin_message uuid := (select ids.id from public.sanga_test_ids ids where ids.key = 'admin_message');
  v_asked public.sanga_join_requests;
  v_rows integer;
  v_refused boolean;
begin
  -- The outsider is in nothing, and the thread is closed to them both ways.
  select count(*)::integer into v_rows from public.list_sanga_messages(v_youth);
  if v_rows <> 0 then
    raise exception 'A devotee who is not in the sanga read % of its messages.', v_rows;
  end if;

  select count(*)::integer into v_rows from public.sanga_messages
  where sanga_messages.sanga_id = v_youth;
  if v_rows <> 0 then
    raise exception 'Row level security let a devotee outside the sanga read % of its messages.', v_rows;
  end if;

  v_refused := false;
  begin
    perform public.send_sanga_message(v_youth, 'Hello, everyone.');
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A devotee who is not in the sanga posted in it.';
  end if;

  v_refused := false;
  begin
    perform public.delete_sanga_message(v_admin_message);
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A devotee outside the sanga took down a message in it.';
  end if;

  -- Their own sanga is still waiting for the President, so it has no thread yet
  -- — even though they run it.
  v_refused := false;
  begin
    perform public.send_sanga_message(v_revived, 'Anybody here?');
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A devotee posted in a sanga that has not been approved.';
  end if;

  -- Left pending on purpose: the section below needs a request nobody has
  -- answered yet.
  v_asked := public.request_to_join_sanga(v_youth, 'May I come along on Friday?');
  insert into public.sanga_test_ids values ('outsider_request', v_asked.id);
end;
$$;

-- ---------------------------------------------------------------------------
-- 14. A holder of app.view_all reads the sanga, and reading does not enrol them.
--
--     This section once also proved they could not act. 202608040043_sanga_powers.sql
--     gave them the powers a sanga's own admin has, so what they may now do is
--     proved in supabase/verification/sanga_powers.sql and what is left here is
--     the read path and the membership it must not create. Handing the sanga to
--     somebody else stayed with its admin, and is still refused below.
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
  v_youth uuid := (select ids.id from public.sanga_test_ids ids where ids.key = 'youth');
  v_revived uuid := (select ids.id from public.sanga_test_ids ids where ids.key = 'revived');
  v_request uuid := (select ids.id from public.sanga_test_ids ids where ids.key = 'outsider_request');
  v_admin_message uuid := (select ids.id from public.sanga_test_ids ids where ids.key = 'admin_message');
  v_rows integer;
  v_sanga record;
  v_said record;
  v_refused boolean;
begin
  if not public.has_permission('app.view_all') then
    raise exception 'The President does not hold app.view_all, so this section proves nothing.';
  end if;
  if public.is_sanga_member(v_youth) or public.is_sanga_admin(v_youth) then
    raise exception 'The President is in the sanga, so this section proves nothing.';
  end if;

  select count(*)::integer into v_rows from public.list_sanga_messages(v_youth);
  if v_rows <> 3 then
    raise exception 'The President reads % of the sanga''s 3 messages.', v_rows;
  end if;

  select * into v_said from public.list_sanga_messages(v_youth) said
  where said.id = v_admin_message;
  if v_said.body is distinct from 'Kirtan at six on Friday.' then
    raise exception 'The President''s copy of the thread is empty where a message should be.';
  end if;
  if v_said.sender_name is distinct from 'Sanga Newcomer' then
    raise exception 'The President''s copy of the thread does not say who spoke.';
  end if;

  select count(*)::integer into v_rows from public.sanga_messages
  where sanga_messages.sanga_id = v_youth;
  if v_rows <> 3 then
    raise exception 'Row level security showed the President % of the 3 messages.', v_rows;
  end if;

  select count(*)::integer into v_rows from public.list_sanga_members(v_youth);
  if v_rows <> 2 then
    raise exception 'The President sees % of the sanga''s 2 members.', v_rows;
  end if;

  -- Reading it does not put them in it.
  select count(*)::integer into v_rows from public.list_sanga_members(v_youth) members
  where members.id = '90000000-0000-0000-0000-000000000001';
  if v_rows <> 0 then
    raise exception 'The President appears in the sanga''s member list.';
  end if;

  select count(*)::integer into v_rows from public.sanga_members members
  where members.sanga_id = v_youth
    and members.devotee_id = '90000000-0000-0000-0000-000000000001';
  if v_rows <> 0 then
    raise exception 'The President holds a membership row in a sanga they never joined.';
  end if;

  -- Any sanga, not only the ones on offer. The re-proposed one is still
  -- waiting, and the section above showed it is closed to an ordinary devotee.
  select count(*)::integer into v_rows from public.list_sanga_members(v_revived);
  if v_rows <> 1 then
    raise exception 'The President sees % of the waiting sanga''s 1 member.', v_rows;
  end if;
  select count(*)::integer into v_rows from public.sanga_members members
  where members.sanga_id = v_revived
    and members.devotee_id = '90000000-0000-0000-0000-000000000001';
  if v_rows <> 0 then
    raise exception 'The President holds a membership row in the waiting sanga.';
  end if;

  -- And the browse list says so plainly, so the client can tell "I can see
  -- this" from "I belong to this".
  select * into v_sanga from public.list_sangas() listed where listed.id = v_youth;
  if v_sanga.id is null then
    raise exception 'The President cannot browse the sanga at all.';
  end if;
  if v_sanga.is_member then
    raise exception 'list_sangas reports the President as a member of the sanga.';
  end if;
  if v_sanga.is_admin then
    raise exception 'list_sangas reports the President as running the sanga.';
  end if;
  if v_sanga.member_count <> 2 then
    raise exception 'The sanga reports % members to the President rather than 2.', v_sanga.member_count;
  end if;

  -- Choosing who runs a sanga stayed with the devotee running it.
  v_refused := false;
  begin
    perform public.transfer_sanga_admin(v_youth, '90000000-0000-0000-0000-000000000003');
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'The President handed a sanga they do not run to somebody else.';
  end if;

  -- Reading left no mark. The request kept for the block below is untouched,
  -- and the id of a message this section only read is carried no further.
  if v_request is null or v_admin_message is null then
    raise exception 'This section lost the ids it was checking against.';
  end if;
  select count(*)::integer into v_rows from public.list_sanga_members(v_youth);
  if v_rows <> 2 then
    raise exception 'After reading, the sanga holds % members rather than 2.', v_rows;
  end if;
  select count(*)::integer into v_rows from public.list_sanga_messages(v_youth) said
  where said.deleted_at is not null;
  if v_rows <> 0 then
    raise exception 'After reading, % messages had been taken down.', v_rows;
  end if;
end;
$$;

reset role;

do $$
declare
  v_status text;
begin
  select asked.status into v_status from public.sanga_join_requests asked
  where asked.id = (select ids.id from public.sanga_test_ids ids where ids.key = 'outsider_request');
  if v_status is distinct from 'pending' then
    raise exception 'The request to join was left at % rather than pending.', v_status;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 15. Taking a message down: your own always, anyone's if you run the sanga.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000003', true);
set local role authenticated;

do $$
declare
  v_admin_message uuid := (select ids.id from public.sanga_test_ids ids where ids.key = 'admin_message');
  v_mine uuid := (select ids.id from public.sanga_test_ids ids where ids.key = 'friend_message_one');
  v_gone public.sanga_messages;
  v_again public.sanga_messages;
  v_refused boolean;
begin
  -- A member is not an admin, and somebody else's words are not theirs to take.
  v_refused := false;
  begin
    perform public.delete_sanga_message(v_admin_message);
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A member took down somebody else''s message.';
  end if;

  v_gone := public.delete_sanga_message(v_mine);
  if v_gone.deleted_at is null then
    raise exception 'Deleting a message did not mark it deleted.';
  end if;
  if v_gone.body is not null or v_gone.image_url is not null then
    raise exception 'A deleted message still shows what it held.';
  end if;

  -- The second tap must not overwrite what was moved aside by the first.
  v_again := public.delete_sanga_message(v_mine);
  if v_again.body is not null then
    raise exception 'Deleting twice brought the message back.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000004', true);
set local role authenticated;

do $$
declare
  v_youth uuid := (select ids.id from public.sanga_test_ids ids where ids.key = 'youth');
  v_theirs uuid := (select ids.id from public.sanga_test_ids ids where ids.key = 'friend_message_two');
  v_gone public.sanga_messages;
  v_rows integer;
begin
  -- The admin may take down anybody's message in the sanga they run.
  v_gone := public.delete_sanga_message(v_theirs);
  if v_gone.deleted_at is null then
    raise exception 'The admin could not take down a member''s message.';
  end if;
  if v_gone.image_url is not null then
    raise exception 'A deleted message still carries its picture.';
  end if;

  -- The thread keeps its shape: the rows stay, emptied.
  select count(*)::integer into v_rows from public.list_sanga_messages(v_youth);
  if v_rows <> 3 then
    raise exception 'After two deletions the thread holds % messages rather than 3.', v_rows;
  end if;
  select count(*)::integer into v_rows from public.list_sanga_messages(v_youth) said
  where said.deleted_at is not null and said.body is null and said.image_url is null;
  if v_rows <> 2 then
    raise exception '% of the 2 deleted messages came back emptied.', v_rows;
  end if;
end;
$$;

reset role;

do $$
declare
  v_one uuid := (select ids.id from public.sanga_test_ids ids where ids.key = 'friend_message_one');
  v_two uuid := (select ids.id from public.sanga_test_ids ids where ids.key = 'friend_message_two');
  v_kept text;
  v_kept_image text;
begin
  select sanga_messages.original_body into v_kept
  from public.sanga_messages where sanga_messages.id = v_one;
  if v_kept is distinct from 'I will bring the kartals.' then
    raise exception 'A deleted message did not keep what it said (got %).', v_kept;
  end if;

  select sanga_messages.original_image_url into v_kept_image
  from public.sanga_messages where sanga_messages.id = v_two;
  if v_kept_image is null then
    raise exception 'A deleted message did not keep the picture it carried.';
  end if;
  if v_kept_image not like '%message-images%' then
    raise exception 'The kept picture is not in the message-images bucket (%).', v_kept_image;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 16. Realtime, and one bucket rather than two.
-- ---------------------------------------------------------------------------

do $$
declare
  v_identity "char";
  v_rows integer;
begin
  select relreplident into v_identity
  from pg_class
  join pg_namespace on pg_namespace.oid = pg_class.relnamespace
  where pg_namespace.nspname = 'public' and pg_class.relname = 'sanga_messages';
  if v_identity is distinct from 'f' then
    raise exception 'sanga_messages has replica identity % rather than full, so a filtered subscription cannot evaluate its filter.', v_identity;
  end if;

  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    select count(*)::integer into v_rows from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'sanga_messages';
    if v_rows <> 1 then
      raise exception 'sanga_messages is not published for realtime.';
    end if;
  end if;

  if not exists (select 1 from storage.buckets where id = 'message-images') then
    raise exception 'The message-images bucket is missing.';
  end if;
  select count(*)::integer into v_rows from storage.buckets
  where buckets.id ilike '%sanga%';
  if v_rows <> 0 then
    raise exception 'A second bucket was made for sanga pictures.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 17. What the database says about itself.
--
--     Comments and messages describe the mechanism and nothing more. This is a
--     deliberate constraint of the temple's, so it is checked rather than
--     trusted to review.
-- ---------------------------------------------------------------------------

do $$
declare
  v_bad text;
begin
  select string_agg(described.text, ' | ') into v_bad
  from (
    select col_description('public.sanga_messages'::regclass, pg_attribute.attnum) as text
    from pg_attribute
    where pg_attribute.attrelid = 'public.sanga_messages'::regclass
      and pg_attribute.attnum > 0
    union all
    select obj_description('public.sanga_messages'::regclass, 'pg_class')
    union all
    select obj_description(pg_proc.oid, 'pg_proc')
    from pg_proc
    join pg_namespace on pg_namespace.oid = pg_proc.pronamespace
    where pg_namespace.nspname = 'public'
      and pg_proc.proname like '%sanga%'
  ) described
  where described.text ~* '(monitor|oversight|surveill|without being a member|without joining)';
  if v_bad is not null then
    raise exception 'A stored description says more than the mechanism: %', v_bad;
  end if;
end;
$$;

reset role;

do $$
begin
  raise notice 'all sanga checks passed';
end;
$$;

select 'sangas verification passed' as result;

rollback;
