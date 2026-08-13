-- Functional verification for 202608040043_sanga_powers.sql.
--
-- Rolled back at the end. Every local is prefixed v_ so it can never shadow a
-- column name. Everything that must succeed, and everything that must be
-- refused, is attempted as the devotee who would really attempt it, under
-- `set local role authenticated`, so the row level security policies, the
-- column grants and the function guards are what is being tested rather than
-- superuser rights quietly waving it all through. Notification assertions are
-- made after `reset role`, because a devotee cannot — and should not be able
-- to — read somebody else's inbox.
--
-- The seven people in this script:
--   President  ...0001  holds app.view_all, and joins nothing
--   Admin      ...0002  starts both sangas and runs them
--   Member     ...0003  an ordinary member, who must stay one
--   Newcomer   ...0004  asks to join, and the President lets them in
--   Outsider   ...0005  in nothing, and must be refused everything
--   Tech       ...0006  the other holder of app.view_all
--   Visitor    ...0007  added and removed by the President, and never asked
--
-- The final row must read: sanga powers verification passed

begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('a0000000-0000-0000-0000-000000000001', 'power-president@example.test', '{"name":"Power President"}'),
  ('a0000000-0000-0000-0000-000000000006', 'power-tech@example.test', '{"name":"Power Tech"}');

update public.users
set role_id = (select roles.id from public.roles where roles.name = 'president')
where email = 'power-president@example.test';

update public.users
set role_id = (select roles.id from public.roles where roles.name = 'tech')
where email = 'power-tech@example.test';

insert into auth.users (id, email, raw_user_meta_data) values
  ('a0000000-0000-0000-0000-000000000002', 'power-admin@example.test', '{"name":"Power Admin"}'),
  ('a0000000-0000-0000-0000-000000000003', 'power-member@example.test', '{"name":"Power Member"}'),
  ('a0000000-0000-0000-0000-000000000004', 'power-newcomer@example.test', '{"name":"Power Newcomer"}'),
  ('a0000000-0000-0000-0000-000000000005', 'power-outsider@example.test', '{"name":"Power Outsider"}'),
  ('a0000000-0000-0000-0000-000000000007', 'power-visitor@example.test', '{"name":"Power Visitor"}');

-- Ordinary table rather than a temporary one, so reading it under the
-- authenticated role needs no assumptions about the temp schema. The whole
-- script is rolled back, so it never outlives the transaction.
create table public.sanga_power_ids (key text primary key, id uuid not null);
grant select, insert on public.sanga_power_ids to authenticated;

-- ---------------------------------------------------------------------------
-- 0. Two roles hold app.view_all, and only those two. If that ever changes,
--    every claim this script makes changes with it, so it is checked first.
-- ---------------------------------------------------------------------------

do $$
declare
  v_roles text;
begin
  select string_agg(roles.name, ', ' order by roles.name) into v_roles
  from public.role_permissions
  join public.roles on roles.id = role_permissions.role_id
  where role_permissions.permission_key = 'app.view_all';
  if v_roles is distinct from 'president, tech' then
    raise exception 'app.view_all is held by "%" rather than president, tech.', v_roles;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 1. The ground: two sangas the temple runs, a thread, and two devotees asking.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_gita public.sangas;
  v_walk public.sangas;
begin
  v_gita := public.create_sanga('Gita Study Sanga', 'Thursday evenings in the library.');
  v_walk := public.create_sanga('Morning Walk Sanga', 'Six o''clock, whatever the weather.');
  insert into public.sanga_power_ids values ('gita', v_gita.id), ('walk', v_walk.id);
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
begin
  perform public.review_sanga(
    (select ids.id from public.sanga_power_ids ids where ids.key = 'gita'), 'approved');
  perform public.review_sanga(
    (select ids.id from public.sanga_power_ids ids where ids.key = 'walk'), 'approved');
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_gita uuid := (select ids.id from public.sanga_power_ids ids where ids.key = 'gita');
  v_said public.sanga_messages;
begin
  perform public.add_sanga_member(v_gita, 'a0000000-0000-0000-0000-000000000003');
  v_said := public.send_sanga_message(v_gita, 'Chapter three this week.');
  insert into public.sanga_power_ids values ('msg_admin', v_said.id);
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000003', true);
set local role authenticated;

do $$
declare
  v_gita uuid := (select ids.id from public.sanga_power_ids ids where ids.key = 'gita');
  v_said public.sanga_messages;
begin
  v_said := public.send_sanga_message(v_gita, 'I will bring the books.');
  insert into public.sanga_power_ids values ('msg_member', v_said.id);
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000004', true);
set local role authenticated;

do $$
declare
  v_asked public.sanga_join_requests;
begin
  v_asked := public.request_to_join_sanga(
    (select ids.id from public.sanga_power_ids ids where ids.key = 'gita'),
    'I have been reading on my own and would rather not.');
  insert into public.sanga_power_ids values ('req_newcomer', v_asked.id);
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000005', true);
set local role authenticated;

do $$
declare
  v_asked public.sanga_join_requests;
begin
  v_asked := public.request_to_join_sanga(
    (select ids.id from public.sanga_power_ids ids where ids.key = 'gita'),
    'May I sit in?');
  insert into public.sanga_power_ids values ('req_outsider', v_asked.id);
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. The President acts on a sanga they are not in — and is still not in it.
--
--    Six powers, one after another, each with the state it changed checked
--    afterwards, and the membership checked after every one of them.
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
  v_gita uuid := (select ids.id from public.sanga_power_ids ids where ids.key = 'gita');
  v_msg_member uuid := (select ids.id from public.sanga_power_ids ids where ids.key = 'msg_member');
  v_req_newcomer uuid := (select ids.id from public.sanga_power_ids ids where ids.key = 'req_newcomer');
  v_req_outsider uuid := (select ids.id from public.sanga_power_ids ids where ids.key = 'req_outsider');
  v_sent public.sanga_messages;
  v_gone public.sanga_messages;
  v_added public.sanga_members;
  v_removed boolean;
  v_decided public.sanga_join_requests;
  v_sanga record;
  v_rows integer;
begin
  if not public.has_permission('app.view_all') then
    raise exception 'The President does not hold app.view_all, so this section proves nothing.';
  end if;
  if public.is_sanga_member(v_gita) or public.is_sanga_admin(v_gita) then
    raise exception 'The President is already in the sanga, so this section proves nothing.';
  end if;

  -- Posting.
  v_sent := public.send_sanga_message(v_gita, 'The library is locked on Thursday; use the hall.');
  if v_sent.id is null then
    raise exception 'The President could not post in the sanga.';
  end if;
  if v_sent.sender_id <> 'a0000000-0000-0000-0000-000000000001' then
    raise exception 'The message did not record the President as its sender.';
  end if;
  if v_sent.sanga_id <> v_gita then
    raise exception 'The message was filed against the wrong sanga.';
  end if;
  if v_sent.body is distinct from 'The library is locked on Thursday; use the hall.' then
    raise exception 'What the President said did not survive (got %).', v_sent.body;
  end if;
  insert into public.sanga_power_ids values ('msg_president', v_sent.id);

  select count(*)::integer into v_rows from public.list_sanga_messages(v_gita);
  if v_rows <> 3 then
    raise exception 'After the President posted, the thread holds % messages rather than 3.', v_rows;
  end if;

  -- Posting did not enrol them.
  if public.is_sanga_member(v_gita) or public.is_sanga_admin(v_gita) then
    raise exception 'Posting put the President into the sanga.';
  end if;
  select count(*)::integer into v_rows from public.sanga_members members
  where members.sanga_id = v_gita
    and members.devotee_id = 'a0000000-0000-0000-0000-000000000001';
  if v_rows <> 0 then
    raise exception 'Posting made a membership row for the President.';
  end if;
  select * into v_sanga from public.list_sangas() listed where listed.id = v_gita;
  if v_sanga.is_member or v_sanga.is_admin then
    raise exception 'After posting, list_sangas reports the President as member or admin.';
  end if;
  if v_sanga.member_count <> 2 then
    raise exception 'After the President posted, the sanga reports % members rather than 2.', v_sanga.member_count;
  end if;

  -- Taking somebody else's message down.
  v_gone := public.delete_sanga_message(v_msg_member);
  if v_gone.deleted_at is null then
    raise exception 'The President could not take down a message.';
  end if;
  if v_gone.body is not null or v_gone.image_url is not null then
    raise exception 'A message the President took down still shows what it held.';
  end if;
  select count(*)::integer into v_rows from public.list_sanga_messages(v_gita);
  if v_rows <> 3 then
    raise exception 'Taking a message down changed the thread to % messages.', v_rows;
  end if;

  -- Adding a devotee.
  v_added := public.add_sanga_member(v_gita, 'a0000000-0000-0000-0000-000000000007');
  if v_added.devotee_id <> 'a0000000-0000-0000-0000-000000000007' then
    raise exception 'The President could not add a devotee to the sanga.';
  end if;
  if v_added.role <> 'member' then
    raise exception 'A devotee the President added arrived as %.', v_added.role;
  end if;
  if v_added.added_by <> 'a0000000-0000-0000-0000-000000000001' then
    raise exception 'The membership does not record who added them.';
  end if;
  select * into v_sanga from public.list_sangas() listed where listed.id = v_gita;
  if v_sanga.member_count <> 3 then
    raise exception 'After the President added a devotee the sanga reports % members.', v_sanga.member_count;
  end if;

  -- Removing a devotee.
  v_removed := public.remove_sanga_member(v_gita, 'a0000000-0000-0000-0000-000000000007');
  if not v_removed then
    raise exception 'The President could not remove a devotee from the sanga.';
  end if;
  select * into v_sanga from public.list_sangas() listed where listed.id = v_gita;
  if v_sanga.member_count <> 2 then
    raise exception 'After the President removed a devotee the sanga reports % members.', v_sanga.member_count;
  end if;

  -- The inbox is readable, which is how the request below is found at all.
  select count(*)::integer into v_rows from public.list_sanga_join_requests(v_gita);
  if v_rows <> 2 then
    raise exception 'The President reads % of the sanga''s 2 requests to join.', v_rows;
  end if;

  -- Approving one.
  v_decided := public.review_sanga_join_request(v_req_newcomer, 'approved');
  if v_decided.status <> 'approved' then
    raise exception 'The President approving a request left it at %.', v_decided.status;
  end if;
  if v_decided.decided_by <> 'a0000000-0000-0000-0000-000000000001'
     or v_decided.decided_at is null then
    raise exception 'The decision did not record who made it, or when.';
  end if;
  select count(*)::integer into v_rows from public.sanga_members members
  where members.sanga_id = v_gita
    and members.devotee_id = 'a0000000-0000-0000-0000-000000000004';
  if v_rows <> 1 then
    raise exception 'Approving one request made % memberships.', v_rows;
  end if;

  -- And declining another.
  v_decided := public.review_sanga_join_request(v_req_outsider, 'declined');
  if v_decided.status <> 'declined' then
    raise exception 'The President declining a request left it at %.', v_decided.status;
  end if;
  select count(*)::integer into v_rows from public.sanga_members members
  where members.sanga_id = v_gita
    and members.devotee_id = 'a0000000-0000-0000-0000-000000000005';
  if v_rows <> 0 then
    raise exception 'A declined request still put the devotee into the sanga.';
  end if;

  -- After all six, the President is exactly where they started.
  if public.is_sanga_member(v_gita) or public.is_sanga_admin(v_gita) then
    raise exception 'Acting on the sanga put the President into it.';
  end if;
  select count(*)::integer into v_rows from public.sanga_members members
  where members.devotee_id = 'a0000000-0000-0000-0000-000000000001';
  if v_rows <> 0 then
    raise exception 'The President holds % membership rows across every sanga.', v_rows;
  end if;
  select * into v_sanga from public.list_sangas() listed where listed.id = v_gita;
  if v_sanga.is_member or v_sanga.is_admin then
    raise exception 'list_sangas reports the President as member or admin of the sanga.';
  end if;
  if v_sanga.member_count <> 3 then
    raise exception 'The sanga finally reports % members rather than 3.', v_sanga.member_count;
  end if;
  if v_sanga.admin_name is distinct from 'Power Admin' then
    raise exception 'The sanga is now run by % rather than the devotee who started it.', v_sanga.admin_name;
  end if;
  select count(*)::integer into v_rows from public.list_my_sangas() mine
  where mine.id = v_gita;
  if v_rows <> 0 then
    raise exception 'The sanga turned up among the President''s own.';
  end if;
  select count(*)::integer into v_rows from public.list_sanga_members(v_gita) members
  where members.id = 'a0000000-0000-0000-0000-000000000001';
  if v_rows <> 0 then
    raise exception 'The President appears in the sanga''s member list.';
  end if;
end;
$$;

reset role;

do $$
declare
  v_told integer;
begin
  select count(*)::integer into v_told from public.app_notifications
  where user_id = 'a0000000-0000-0000-0000-000000000007'
    and kind = 'sanga_member_added';
  if v_told <> 1 then
    raise exception 'The devotee the President added was told % times.', v_told;
  end if;

  select count(*)::integer into v_told from public.app_notifications
  where user_id = 'a0000000-0000-0000-0000-000000000007'
    and kind = 'sanga_member_removed';
  if v_told <> 1 then
    raise exception 'The devotee the President removed was told % times.', v_told;
  end if;

  select count(*)::integer into v_told from public.app_notifications
  where user_id = 'a0000000-0000-0000-0000-000000000004'
    and kind = 'sanga_join_reviewed';
  if v_told <> 1 then
    raise exception 'The devotee whose request was approved was told % times.', v_told;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. The Tech Admin holds the same key, so the same door opens.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000006', true);
set local role authenticated;

do $$
declare
  v_gita uuid := (select ids.id from public.sanga_power_ids ids where ids.key = 'gita');
  v_sent public.sanga_messages;
  v_rows integer;
begin
  v_sent := public.send_sanga_message(v_gita, 'The books are in the second cupboard.');
  if v_sent.id is null then
    raise exception 'A Tech Admin could not post in the sanga.';
  end if;
  select count(*)::integer into v_rows from public.sanga_members members
  where members.sanga_id = v_gita
    and members.devotee_id = 'a0000000-0000-0000-0000-000000000006';
  if v_rows <> 0 then
    raise exception 'Posting made a membership row for the Tech Admin.';
  end if;
  select count(*)::integer into v_rows from public.list_sanga_messages(v_gita);
  if v_rows <> 4 then
    raise exception 'The thread holds % messages rather than 4.', v_rows;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Everybody else is exactly where 202608040039_sangas.sql left them.
--
--    A devotee in nothing, and an ordinary member of the sanga itself. Neither
--    holds app.view_all, and neither runs the sanga.
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000005', true);
set local role authenticated;

do $$
declare
  v_gita uuid := (select ids.id from public.sanga_power_ids ids where ids.key = 'gita');
  v_msg_admin uuid := (select ids.id from public.sanga_power_ids ids where ids.key = 'msg_admin');
  v_asked public.sanga_join_requests;
  v_refused boolean;
  v_rows integer;
begin
  if public.has_permission('app.view_all') then
    raise exception 'A plain devotee holds app.view_all, so this section proves nothing.';
  end if;

  v_refused := false;
  begin
    perform public.send_sanga_message(v_gita, 'Hello, everyone.');
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A devotee outside the sanga posted in it.';
  end if;

  v_refused := false;
  begin
    perform public.delete_sanga_message(v_msg_admin);
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A devotee outside the sanga took a message down.';
  end if;

  v_refused := false;
  begin
    perform public.add_sanga_member(v_gita, 'a0000000-0000-0000-0000-000000000005');
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A devotee outside the sanga added somebody to it.';
  end if;

  v_refused := false;
  begin
    perform public.remove_sanga_member(v_gita, 'a0000000-0000-0000-0000-000000000003');
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A devotee outside the sanga removed somebody from it.';
  end if;

  v_refused := false;
  begin
    perform public.delete_sanga(v_gita);
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A devotee outside the sanga deleted it.';
  end if;

  -- A declined request does not block a later one, so there is a fresh pending
  -- ask for the ordinary member below to fail to answer.
  v_asked := public.request_to_join_sanga(v_gita, 'Asking again, properly.');
  insert into public.sanga_power_ids values ('req_again', v_asked.id);

  -- Nothing above landed.
  select count(*)::integer into v_rows from public.sangas where sangas.id = v_gita;
  if v_rows <> 1 then
    raise exception 'The sanga is no longer readable, so a refusal did land.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000003', true);
set local role authenticated;

do $$
declare
  v_gita uuid := (select ids.id from public.sanga_power_ids ids where ids.key = 'gita');
  v_msg_admin uuid := (select ids.id from public.sanga_power_ids ids where ids.key = 'msg_admin');
  v_msg_president uuid := (select ids.id from public.sanga_power_ids ids where ids.key = 'msg_president');
  v_req_again uuid := (select ids.id from public.sanga_power_ids ids where ids.key = 'req_again');
  v_refused boolean;
  v_rows integer;
begin
  if not public.is_sanga_member(v_gita) then
    raise exception 'The ordinary member is not in the sanga, so this section proves nothing.';
  end if;
  if public.is_sanga_admin(v_gita) or public.has_permission('app.view_all') then
    raise exception 'The ordinary member runs the sanga or holds app.view_all.';
  end if;

  v_refused := false;
  begin
    perform public.delete_sanga_message(v_msg_admin);
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'An ordinary member took down somebody else''s message.';
  end if;

  v_refused := false;
  begin
    perform public.delete_sanga_message(v_msg_president);
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'An ordinary member took down a message the office posted.';
  end if;

  v_refused := false;
  begin
    perform public.add_sanga_member(v_gita, 'a0000000-0000-0000-0000-000000000005');
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'An ordinary member added somebody to the sanga.';
  end if;

  v_refused := false;
  begin
    perform public.remove_sanga_member(v_gita, 'a0000000-0000-0000-0000-000000000004');
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'An ordinary member removed somebody from the sanga.';
  end if;

  v_refused := false;
  begin
    perform public.review_sanga_join_request(v_req_again, 'approved');
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'An ordinary member answered a request to join.';
  end if;

  v_refused := false;
  begin
    perform public.delete_sanga(v_gita);
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'An ordinary member deleted the sanga.';
  end if;

  -- The inbox stays the admin's business.
  select count(*)::integer into v_rows from public.list_sanga_join_requests(v_gita);
  if v_rows <> 0 then
    raise exception 'An ordinary member reads % of the admin''s join requests.', v_rows;
  end if;

  -- And none of it landed: three members, and only the one message taken down.
  select count(*)::integer into v_rows from public.list_sanga_members(v_gita);
  if v_rows <> 3 then
    raise exception 'After the refusals the sanga holds % members rather than 3.', v_rows;
  end if;
  select count(*)::integer into v_rows from public.list_sanga_messages(v_gita) said
  where said.deleted_at is not null;
  if v_rows <> 1 then
    raise exception 'After the refusals % messages had been taken down rather than 1.', v_rows;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. The devotee who runs a sanga still does all six for their own.
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_walk uuid := (select ids.id from public.sanga_power_ids ids where ids.key = 'walk');
  v_sent public.sanga_messages;
begin
  perform public.add_sanga_member(v_walk, 'a0000000-0000-0000-0000-000000000003');
  perform public.add_sanga_member(v_walk, 'a0000000-0000-0000-0000-000000000004');
  v_sent := public.send_sanga_message(v_walk, 'Meeting at the east gate.');
  if v_sent.id is null then
    raise exception 'The admin could not post in the sanga they run.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000004', true);
set local role authenticated;

do $$
declare
  v_sent public.sanga_messages;
begin
  v_sent := public.send_sanga_message(
    (select ids.id from public.sanga_power_ids ids where ids.key = 'walk'),
    'I will be five minutes late.');
  insert into public.sanga_power_ids values ('msg_walk_member', v_sent.id);
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000005', true);
set local role authenticated;

do $$
declare
  v_asked public.sanga_join_requests;
begin
  v_asked := public.request_to_join_sanga(
    (select ids.id from public.sanga_power_ids ids where ids.key = 'walk'),
    'I am usually up anyway.');
  insert into public.sanga_power_ids values ('req_walk', v_asked.id);
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_walk uuid := (select ids.id from public.sanga_power_ids ids where ids.key = 'walk');
  v_theirs uuid := (select ids.id from public.sanga_power_ids ids where ids.key = 'msg_walk_member');
  v_req uuid := (select ids.id from public.sanga_power_ids ids where ids.key = 'req_walk');
  v_gone public.sanga_messages;
  v_decided public.sanga_join_requests;
  v_removed boolean;
  v_rows integer;
begin
  v_gone := public.delete_sanga_message(v_theirs);
  if v_gone.deleted_at is null then
    raise exception 'The admin could not take down a member''s message.';
  end if;

  v_decided := public.review_sanga_join_request(v_req, 'approved');
  if v_decided.status <> 'approved' then
    raise exception 'The admin approving a request left it at %.', v_decided.status;
  end if;
  select count(*)::integer into v_rows from public.list_sanga_members(v_walk);
  if v_rows <> 4 then
    raise exception 'After the admin approved a request the sanga holds % members.', v_rows;
  end if;

  v_removed := public.remove_sanga_member(v_walk, 'a0000000-0000-0000-0000-000000000005');
  if not v_removed then
    raise exception 'The admin could not remove a member from the sanga they run.';
  end if;
  select count(*)::integer into v_rows from public.list_sanga_members(v_walk);
  if v_rows <> 3 then
    raise exception 'After the admin removed a member the sanga holds % members.', v_rows;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. The last-admin rule holds, and it holds for the President too.
--
--    A sanga has exactly one devotee responsible for it. The sole admin is
--    refused rather than removed, and the refusal names the two things that
--    can be done instead.
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
  v_gita uuid := (select ids.id from public.sanga_power_ids ids where ids.key = 'gita');
  v_said text := null;
  v_admins integer;
  v_runner uuid;
begin
  begin
    perform public.remove_sanga_member(v_gita, 'a0000000-0000-0000-0000-000000000002');
  exception when others then
    v_said := sqlerrm;
  end;
  if v_said is null then
    raise exception 'The President removed the only devotee responsible for a sanga.';
  end if;
  if v_said !~* 'responsible' then
    raise exception 'The refusal does not say why (got "%").', v_said;
  end if;
  if v_said !~* 'delete' then
    raise exception 'The refusal does not name deleting the sanga as the alternative (got "%").', v_said;
  end if;

  select count(*)::integer into v_admins from public.sanga_members members
  where members.sanga_id = v_gita and members.role = 'admin';
  if v_admins <> 1 then
    raise exception 'The sanga has % admins.', v_admins;
  end if;
  select sangas.admin_id into v_runner from public.sangas where sangas.id = v_gita;
  if v_runner <> 'a0000000-0000-0000-0000-000000000002' then
    raise exception 'The sanga is recorded as run by % rather than its admin.', v_runner;
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_gita uuid := (select ids.id from public.sanga_power_ids ids where ids.key = 'gita');
  v_refused boolean;
  v_handed public.sangas;
begin
  -- Unchanged for the admin themselves.
  v_refused := false;
  begin
    perform public.remove_sanga_member(v_gita, 'a0000000-0000-0000-0000-000000000002');
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'The only admin removed themselves.';
  end if;

  v_refused := false;
  begin
    perform public.leave_sanga(v_gita);
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'The only admin walked out.';
  end if;

  -- Handing over is still theirs alone, and once done there are two ordinary
  -- members and the rule no longer bites.
  v_handed := public.transfer_sanga_admin(v_gita, 'a0000000-0000-0000-0000-000000000003');
  if v_handed.admin_id <> 'a0000000-0000-0000-0000-000000000003' then
    raise exception 'Handing the sanga over did not change who runs it.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
  v_gita uuid := (select ids.id from public.sanga_power_ids ids where ids.key = 'gita');
  v_removed boolean;
  v_admins integer;
  v_rows integer;
begin
  -- The devotee who used to run it is an ordinary member now, so the President
  -- may remove them: the rule was about the sanga having somebody responsible,
  -- not about that particular devotee.
  v_removed := public.remove_sanga_member(v_gita, 'a0000000-0000-0000-0000-000000000002');
  if not v_removed then
    raise exception 'The President could not remove a former admin who is now an ordinary member.';
  end if;

  select count(*)::integer into v_admins from public.sanga_members members
  where members.sanga_id = v_gita and members.role = 'admin';
  if v_admins <> 1 then
    raise exception 'After the removal the sanga has % admins.', v_admins;
  end if;
  select count(*)::integer into v_rows from public.list_sanga_members(v_gita);
  if v_rows <> 2 then
    raise exception 'After the removal the sanga holds % members rather than 2.', v_rows;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Deleting a sanga.
--
--    The row and its history stay; the sanga stops existing for everybody.
--    First a holder of app.view_all deleting one they do not run, then its own
--    admin deleting the other.
-- ---------------------------------------------------------------------------

do $$
declare
  v_walk uuid := (select ids.id from public.sanga_power_ids ids where ids.key = 'walk');
  v_gone public.sangas;
  v_refused boolean;
  v_rows integer;
begin
  v_gone := public.delete_sanga(v_walk);
  if v_gone.deleted_at is null then
    raise exception 'Deleting the sanga did not mark it deleted.';
  end if;
  if v_gone.active then
    raise exception 'A deleted sanga is still active.';
  end if;

  -- Gone from the President's own view of the world too.
  select count(*)::integer into v_rows from public.list_sangas() listed where listed.id = v_walk;
  if v_rows <> 0 then
    raise exception 'A deleted sanga is still on offer.';
  end if;

  v_refused := false;
  begin
    perform public.delete_sanga(v_walk);
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A sanga was deleted twice.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_walk uuid := (select ids.id from public.sanga_power_ids ids where ids.key = 'walk');
  v_rows integer;
  v_touched integer;
  v_refused boolean;
begin
  -- Its own admin cannot find it, in any list.
  select count(*)::integer into v_rows from public.list_sangas() listed where listed.id = v_walk;
  if v_rows <> 0 then
    raise exception 'A deleted sanga is on the browse list of the devotee who ran it.';
  end if;
  select count(*)::integer into v_rows from public.list_my_sangas() mine where mine.id = v_walk;
  if v_rows <> 0 then
    raise exception 'A deleted sanga is still among its admin''s own sangas.';
  end if;
  select count(*)::integer into v_rows from public.sangas where sangas.id = v_walk;
  if v_rows <> 0 then
    raise exception 'Row level security let the former admin read a deleted sanga.';
  end if;
  select count(*)::integer into v_rows from public.list_sanga_members(v_walk);
  if v_rows <> 0 then
    raise exception 'A deleted sanga still lists % members.', v_rows;
  end if;
  select count(*)::integer into v_rows from public.list_sanga_messages(v_walk);
  if v_rows <> 0 then
    raise exception 'A deleted sanga still lists % messages.', v_rows;
  end if;
  select count(*)::integer into v_rows from public.sanga_messages
  where sanga_messages.sanga_id = v_walk;
  if v_rows <> 0 then
    raise exception 'Row level security showed % messages of a deleted sanga.', v_rows;
  end if;
  select count(*)::integer into v_rows from public.list_sanga_join_requests(v_walk);
  if v_rows <> 0 then
    raise exception 'A deleted sanga still lists % requests to join.', v_rows;
  end if;

  -- It cannot be posted in.
  v_refused := false;
  begin
    perform public.send_sanga_message(v_walk, 'Are we still walking?');
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A devotee posted in a deleted sanga.';
  end if;

  -- Nor added to, nor handed on.
  v_refused := false;
  begin
    perform public.add_sanga_member(v_walk, 'a0000000-0000-0000-0000-000000000005');
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A devotee was added to a deleted sanga.';
  end if;

  v_refused := false;
  begin
    perform public.transfer_sanga_admin(v_walk, 'a0000000-0000-0000-0000-000000000003');
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A deleted sanga was handed to somebody else.';
  end if;

  -- And it cannot be brought back by flipping the shutter. active is a granted
  -- column, so this is the policy doing the refusing.
  update public.sangas set active = true where sangas.id = v_walk;
  get diagnostics v_touched = row_count;
  if v_touched <> 0 then
    raise exception 'A deleted sanga was made active again.';
  end if;
end;
$$;

-- The Outsider, who was in this sanga and was removed from it in section 5, so
-- "you are already in it" cannot be what refuses them.
reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000005', true);
set local role authenticated;

do $$
declare
  v_walk uuid := (select ids.id from public.sanga_power_ids ids where ids.key = 'walk');
  v_refused boolean := false;
begin
  if public.is_sanga_member(v_walk) then
    raise exception 'The devotee asking to join is already in the sanga, so this proves nothing.';
  end if;

  begin
    perform public.request_to_join_sanga(v_walk, 'Can I still come?');
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A devotee asked to join a deleted sanga.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7b. deleted_at carries the weight on its own.
--
--     public.delete_sanga clears active as well, and every guard that predates
--     202608040043_sanga_powers.sql tests active. So the sanga is put back to
--     active behind the policies — which is a thing no devotee can do, and the
--     block above has just shown that — and every claim in section 7 is made
--     again. Anything that passes now is reading deleted_at rather than
--     borrowing the answer from a column that happens to agree with it.
-- ---------------------------------------------------------------------------

reset role;

update public.sangas set active = true
where sangas.id = (select ids.id from public.sanga_power_ids ids where ids.key = 'walk');

select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000004', true);
set local role authenticated;

do $$
declare
  v_walk uuid := (select ids.id from public.sanga_power_ids ids where ids.key = 'walk');
  v_rows integer;
  v_refused boolean;
begin
  select count(*)::integer into v_rows from public.list_sangas() listed where listed.id = v_walk;
  if v_rows <> 0 then
    raise exception 'A deleted sanga came back onto the browse list when active was set.';
  end if;
  select count(*)::integer into v_rows from public.list_my_sangas() mine where mine.id = v_walk;
  if v_rows <> 0 then
    raise exception 'A deleted sanga came back among a member''s own when active was set.';
  end if;
  select count(*)::integer into v_rows from public.sangas where sangas.id = v_walk;
  if v_rows <> 0 then
    raise exception 'Row level security showed a deleted sanga when active was set.';
  end if;
  select count(*)::integer into v_rows from public.list_sanga_members(v_walk);
  if v_rows <> 0 then
    raise exception 'A deleted sanga listed % members when active was set.', v_rows;
  end if;

  v_refused := false;
  begin
    perform public.send_sanga_message(v_walk, 'Are we on?');
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A devotee posted in a deleted sanga when active was set.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000005', true);
set local role authenticated;

do $$
declare
  v_walk uuid := (select ids.id from public.sanga_power_ids ids where ids.key = 'walk');
  v_refused boolean := false;
begin
  if public.is_sanga_member(v_walk) then
    raise exception 'The devotee asking to join is already in the sanga, so this proves nothing.';
  end if;

  begin
    perform public.request_to_join_sanga(v_walk, 'It looks open again.');
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A devotee asked to join a deleted sanga when active was set.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
  v_walk uuid := (select ids.id from public.sanga_power_ids ids where ids.key = 'walk');
  v_rows integer;
  v_refused boolean;
begin
  select count(*)::integer into v_rows from public.list_sangas() listed where listed.id = v_walk;
  if v_rows <> 0 then
    raise exception 'A deleted sanga is on the President''s browse list when active is set.';
  end if;

  v_refused := false;
  begin
    perform public.add_sanga_member(v_walk, 'a0000000-0000-0000-0000-000000000005');
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A devotee was added to a deleted sanga when active was set.';
  end if;

  v_refused := false;
  begin
    perform public.send_sanga_message(v_walk, 'A word from the office.');
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'The President posted in a deleted sanga when active was set.';
  end if;
end;
$$;

reset role;

-- Left as delete_sanga leaves it, so the rest of the script sees the real thing.
update public.sangas set active = false
where sangas.id = (select ids.id from public.sanga_power_ids ids where ids.key = 'walk');

reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000005', true);
set local role authenticated;

do $$
declare
  v_fresh public.sangas;
begin
  -- The name is free again, on the same reasoning that frees a declined one.
  v_fresh := public.create_sanga('Morning Walk Sanga', 'Starting it up again.');
  if v_fresh.status <> 'pending' then
    raise exception 'A sanga re-proposed under a deleted name read % rather than pending.', v_fresh.status;
  end if;
end;
$$;

reset role;

do $$
declare
  v_told integer;
  v_kept integer;
begin
  -- Everybody who was in it heard, and the President who closed it did not
  -- write to themselves.
  select count(*)::integer into v_told from public.app_notifications
  where kind = 'sanga_deleted';
  if v_told <> 3 then
    raise exception 'A sanga with 3 members other than the caller produced % notices.', v_told;
  end if;
  select count(*)::integer into v_told from public.app_notifications
  where kind = 'sanga_deleted'
    and user_id = 'a0000000-0000-0000-0000-000000000001';
  if v_told <> 0 then
    raise exception 'The devotee who deleted the sanga was told about it.';
  end if;

  -- The history is kept. This is the whole reason it is not a hard delete.
  select count(*)::integer into v_kept from public.sanga_members
  where sanga_members.sanga_id = (select ids.id from public.sanga_power_ids ids where ids.key = 'walk');
  if v_kept <> 3 then
    raise exception 'Deleting the sanga left % of its 3 membership rows.', v_kept;
  end if;
  select count(*)::integer into v_kept from public.sanga_messages
  where sanga_messages.sanga_id = (select ids.id from public.sanga_power_ids ids where ids.key = 'walk');
  if v_kept <> 2 then
    raise exception 'Deleting the sanga left % of its 2 messages.', v_kept;
  end if;
end;
$$;

-- The other sanga, deleted by the devotee who runs it.
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000003', true);
set local role authenticated;

do $$
declare
  v_gita uuid := (select ids.id from public.sanga_power_ids ids where ids.key = 'gita');
  v_gone public.sangas;
  v_rows integer;
begin
  if not public.is_sanga_admin(v_gita) then
    raise exception 'The devotee deleting the sanga does not run it, so this proves nothing.';
  end if;

  v_gone := public.delete_sanga(v_gita);
  if v_gone.deleted_at is null then
    raise exception 'The admin could not delete the sanga they run.';
  end if;

  select count(*)::integer into v_rows from public.list_sangas() listed where listed.id = v_gita;
  if v_rows <> 0 then
    raise exception 'A sanga its admin deleted is still on offer.';
  end if;
  select count(*)::integer into v_rows from public.list_my_sangas() mine where mine.id = v_gita;
  if v_rows <> 0 then
    raise exception 'A sanga its admin deleted is still among their own.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
  v_gita uuid := (select ids.id from public.sanga_power_ids ids where ids.key = 'gita');
  v_rows integer;
  v_refused boolean := false;
begin
  select count(*)::integer into v_rows from public.list_sangas() listed where listed.id = v_gita;
  if v_rows <> 0 then
    raise exception 'A deleted sanga is still on offer to the President.';
  end if;
  select count(*)::integer into v_rows from public.sangas where sangas.id = v_gita;
  if v_rows <> 0 then
    raise exception 'Row level security let the President read a deleted sanga.';
  end if;
  select count(*)::integer into v_rows from public.list_sanga_messages(v_gita);
  if v_rows <> 0 then
    raise exception 'A deleted sanga still shows % messages to the President.', v_rows;
  end if;

  begin
    perform public.send_sanga_message(v_gita, 'One last thing.');
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'The President posted in a deleted sanga.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. Realtime, so a devotee does not have to leave the screen and come back.
--
--    A filtered postgres_changes subscription on a table with row level
--    security cannot evaluate its filter from the default replica identity.
--    All four tables the sanga screens are built from need both halves.
-- ---------------------------------------------------------------------------

reset role;

do $$
declare
  v_table text;
  v_identity "char";
  v_rows integer;
begin
  foreach v_table in array array['sangas', 'sanga_members', 'sanga_join_requests', 'sanga_messages']
  loop
    select relreplident into v_identity
    from pg_class
    join pg_namespace on pg_namespace.oid = pg_class.relnamespace
    where pg_namespace.nspname = 'public' and pg_class.relname = v_table;
    if v_identity is distinct from 'f' then
      raise exception '% carries replica identity % rather than full, so a filtered subscription cannot evaluate its filter.', v_table, v_identity;
    end if;

    if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
      select count(*)::integer into v_rows from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = v_table;
      if v_rows <> 1 then
        raise exception '% appears % times in the supabase_realtime publication rather than once.', v_table, v_rows;
      end if;
    end if;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- 9. What the database says about itself.
--
--    Comments and messages describe the mechanism and nothing more. This is a
--    deliberate constraint of the temple's, so it is checked rather than
--    trusted to review.
-- ---------------------------------------------------------------------------

do $$
declare
  v_bad text;
begin
  select string_agg(described.text, ' | ') into v_bad
  from (
    select col_description(pg_class.oid, pg_attribute.attnum) as text
    from pg_class
    join pg_namespace on pg_namespace.oid = pg_class.relnamespace
    join pg_attribute on pg_attribute.attrelid = pg_class.oid
    where pg_namespace.nspname = 'public'
      and pg_class.relname in ('sangas', 'sanga_members', 'sanga_join_requests', 'sanga_messages')
      and pg_attribute.attnum > 0
    union all
    select obj_description(pg_proc.oid, 'pg_proc')
    from pg_proc
    join pg_namespace on pg_namespace.oid = pg_proc.pronamespace
    where pg_namespace.nspname = 'public'
      and pg_proc.proname like '%sanga%'
  ) described
  where described.text ~* '(monitor|oversight|surveill|without being a member|without joining|not a member of)';
  if v_bad is not null then
    raise exception 'A stored description says more than the mechanism: %', v_bad;
  end if;
end;
$$;

do $$
begin
  raise notice 'all sanga power checks passed';
end;
$$;

select 'sanga powers verification passed' as result;

rollback;
