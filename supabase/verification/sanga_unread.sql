-- Functional verification for 202608040056_sanga_unread.sql.
--
-- Rolled back at the end. Every local is prefixed v_ so it can never shadow a
-- column name. Anything a devotee does is done as that devotee, under
-- `set local role authenticated`, so the row level security policies, the table
-- grants and the membership guard are the thing under test rather than
-- superuser rights quietly waving everything through.
--
-- The rule under test, in full:
--
--   a member's unread count for a sanga is the number of messages in it that
--   were NOT sent by them, are NOT deleted, and were said AFTER the later of
--   their joined_at and their watermark
--
-- and for anybody who is not a member — including a President reading over the
-- top of the circle through app.view_all — it is zero.
--
-- The four people in this script:
--   Gopal   ...0001  founds the sanga and runs it; member from the first moment
--   Radha   ...0002  member from the first moment; her count must move
--                    independently of Gopal's, which is the assertion a shared
--                    "last message" watermark would fail
--   Mira    ...0003  added to the sanga after seven hours of thread already
--                    exist. She sees ZERO, and starts counting from the moment
--                    she was added. That is the documented answer to "what does
--                    a devotee who joins an existing sanga see" — the whole
--                    thread is still hers to scroll, but two years of a study
--                    group she joined this morning is not a debt, and a badge
--                    reading four thousand is one she clears by never opening
--                    the sanga again.
--   Prez    ...0004  President. Approves the sanga, reads every message in it
--                    through app.view_all, and never joins. His count is zero
--                    throughout and mark_sanga_read refuses him outright.
--
-- On the timeline. now() is fixed for the whole of a transaction, so messages
-- posted here would otherwise all carry the same instant and a rule written
-- with a strict > would count nothing at all — the script would pass while
-- proving nothing. Every message is therefore posted through the real RPC, with
-- its guards, and then stamped onto an explicit timeline as superuser. The
-- times below are the timeline this file asserts against:
--
--   t0      Gopal founds it, Prez approves it, Radha is added
--   t0+1h   M1  Gopal:  counts for Radha, not for Gopal
--   t0+2h   M2  Radha:  counts for Gopal, not for Radha
--   t0+3h   M3  Radha:  deleted at t0+3h30, so it counts for nobody
--   t0+4h       Gopal marks read — the mark clears exactly M2
--   t0+5h   M4  Gopal
--   t0+6h   M5  Radha
--   t0+7h       Mira is added
--   t0+8h   M6  Gopal
--
-- The most important assertion here is the negative one: at t0+7h Mira's count
-- is zero although six messages exist. A change that floors the count at the
-- watermark alone — the obvious implementation — passes every other test in
-- this file and hands a brand new member a badge for a conversation they were
-- not part of.
--
-- The final row must read: sanga unread verification passed

begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('5a000000-0000-0000-0000-000000000001', 'sunread-gopal@example.test', '{"name":"Gopal Das"}'),
  ('5a000000-0000-0000-0000-000000000002', 'sunread-radha@example.test', '{"name":"Radha Devi"}'),
  ('5a000000-0000-0000-0000-000000000003', 'sunread-mira@example.test', '{"name":"Mira Devi"}'),
  ('5a000000-0000-0000-0000-000000000004', 'sunread-prez@example.test', '{"name":"Temple President"}');

update public.users
set role_id = (select roles.id from public.roles where roles.name = 'president')
where users.email = 'sunread-prez@example.test';

-- Ordinary table rather than a temporary one, so reading it under the
-- authenticated role needs no assumptions about the temp schema. The whole
-- script is rolled back, so it never outlives the transaction.
create table public.sanga_unread_test_ids (key text primary key, id uuid not null);
grant select, insert on public.sanga_unread_test_ids to authenticated;

-- ---------------------------------------------------------------------------
-- 0. The shape of the thing, before any of its behaviour.
-- ---------------------------------------------------------------------------

do $$
declare
  v_name text;
  v_overloads integer;
  v_def text;
  v_secdef boolean;
  v_volatile "char";
begin
  -- One of each, so no leftover overload can make a call ambiguous. A defaulted
  -- second candidate left behind by an earlier shape is how this repo has
  -- broken before.
  foreach v_name in array array[
    'sanga_unread_count', 'mark_sanga_read', 'list_sangas', 'list_my_sangas'
  ] loop
    select count(*)::integer into v_overloads
    from pg_proc
    join pg_namespace on pg_namespace.oid = pg_proc.pronamespace
    where pg_namespace.nspname = 'public' and pg_proc.proname = v_name;
    if v_overloads <> 1 then
      raise exception 'public.% has % overloads rather than 1.', v_name, v_overloads;
    end if;
  end loop;

  select pg_proc.prosecdef, pg_proc.provolatile into v_secdef, v_volatile
  from pg_proc
  where pg_proc.oid = 'public.sanga_unread_count(uuid)'::regprocedure;
  if not v_secdef then
    raise exception
      'sanga_unread_count is not security definer, so it answers differently depending on who asks.';
  end if;
  if v_volatile = 'v' then
    raise exception 'sanga_unread_count is volatile.';
  end if;

  -- The rule lives in one place and every caller asks that place. This is the
  -- anti-drift assertion: a future edit that inlines the count back into either
  -- list — which is exactly how a badge and the thread behind it come apart —
  -- fails here rather than in a devotee's hand.
  foreach v_name in array array['list_sangas()', 'list_my_sangas()', 'mark_sanga_read(uuid)']
  loop
    v_def := pg_get_functiondef(('public.' || v_name)::regprocedure);
    if v_def !~ 'sanga_unread_count' then
      raise exception
        'public.% no longer asks sanga_unread_count; the count has drifted from the rule.', v_name;
    end if;
  end loop;

  -- Home orders its sangas by this column by name. A rename here is a silent
  -- breakage there, so the name is asserted rather than assumed.
  foreach v_name in array array['list_sangas()', 'list_my_sangas()'] loop
    if not exists (
      select 1 from pg_proc
      where pg_proc.oid = ('public.' || v_name)::regprocedure
        and 'unread_count' = any (pg_proc.proargnames)
    ) then
      raise exception 'public.% does not return a column called unread_count.', v_name;
    end if;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- 1. A sanga, approved, with two devotees in it.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', '5a000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
  v_sanga public.sangas;
begin
  v_sanga := public.create_sanga('Gita Study Circle', 'Thursdays after arati.');
  insert into public.sanga_unread_test_ids values ('sanga', v_sanga.id);
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '5a000000-0000-0000-0000-000000000004', true);
set local role authenticated;

do $$
begin
  perform public.review_sanga(
    (select ids.id from public.sanga_unread_test_ids ids where ids.key = 'sanga'),
    'approved', null);
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '5a000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
begin
  perform public.add_sanga_member(
    (select ids.id from public.sanga_unread_test_ids ids where ids.key = 'sanga'),
    '5a000000-0000-0000-0000-000000000002');
end;
$$;

reset role;

-- t0. Both founding members are inside from here.
update public.sanga_members
set joined_at = now() - interval '10 hours'
where sanga_members.sanga_id
      = (select ids.id from public.sanga_unread_test_ids ids where ids.key = 'sanga');

-- ---------------------------------------------------------------------------
-- 2. Three messages, on a timeline.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', '5a000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
  v_sent public.sanga_messages;
begin
  v_sent := public.send_sanga_message(
    (select ids.id from public.sanga_unread_test_ids ids where ids.key = 'sanga'),
    'Hare Krsna everyone, we begin chapter two on Thursday.');
  insert into public.sanga_unread_test_ids values ('m1', v_sent.id);
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '5a000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_sent public.sanga_messages;
begin
  v_sent := public.send_sanga_message(
    (select ids.id from public.sanga_unread_test_ids ids where ids.key = 'sanga'),
    'I will bring the prasadam.');
  insert into public.sanga_unread_test_ids values ('m2', v_sent.id);

  v_sent := public.send_sanga_message(
    (select ids.id from public.sanga_unread_test_ids ids where ids.key = 'sanga'),
    'Sorry, wrong group.');
  insert into public.sanga_unread_test_ids values ('m3', v_sent.id);
end;
$$;

reset role;

update public.sanga_messages set created_at = now() - interval '9 hours'
where sanga_messages.id = (select ids.id from public.sanga_unread_test_ids ids where ids.key = 'm1');
update public.sanga_messages set created_at = now() - interval '8 hours'
where sanga_messages.id = (select ids.id from public.sanga_unread_test_ids ids where ids.key = 'm2');
update public.sanga_messages set created_at = now() - interval '7 hours'
where sanga_messages.id = (select ids.id from public.sanga_unread_test_ids ids where ids.key = 'm3');

-- A new message raises the member's count; their own does not. Gopal said M1,
-- so his two are M2 and M3. Radha said both of those, so her one is M1.
do $$
declare
  v_sanga uuid := (select ids.id from public.sanga_unread_test_ids ids where ids.key = 'sanga');
  v_count integer;
begin
  perform set_config('request.jwt.claim.sub', '5a000000-0000-0000-0000-000000000001', true);
  v_count := public.sanga_unread_count(v_sanga);
  if v_count <> 2 then
    raise exception 'Gopal has % unread rather than 2.', v_count;
  end if;

  perform set_config('request.jwt.claim.sub', '5a000000-0000-0000-0000-000000000002', true);
  v_count := public.sanga_unread_count(v_sanga);
  if v_count <> 1 then
    raise exception
      'Radha has % unread rather than 1. Her own two messages must not count against her.', v_count;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. A message taken down stops counting.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', '5a000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
begin
  perform public.delete_sanga_message(
    (select ids.id from public.sanga_unread_test_ids ids where ids.key = 'm3'));
end;
$$;

reset role;

do $$
declare
  v_sanga uuid := (select ids.id from public.sanga_unread_test_ids ids where ids.key = 'sanga');
  v_count integer;
begin
  if not exists (
    select 1 from public.sanga_messages
    where sanga_messages.id = (select ids.id from public.sanga_unread_test_ids ids where ids.key = 'm3')
      and sanga_messages.deleted_at is not null
  ) then
    raise exception 'M3 was not actually deleted, so the next assertion proves nothing.';
  end if;

  perform set_config('request.jwt.claim.sub', '5a000000-0000-0000-0000-000000000001', true);
  v_count := public.sanga_unread_count(v_sanga);
  if v_count <> 1 then
    raise exception
      'Gopal has % unread rather than 1. A deleted message is a tombstone, not news.', v_count;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Marking read clears it, and clears only the caller's.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', '5a000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
  v_cleared integer;
begin
  v_cleared := public.mark_sanga_read(
    (select ids.id from public.sanga_unread_test_ids ids where ids.key = 'sanga'));
  -- The return value is what lets the client leave its caches alone when there
  -- was nothing to clear, so it has to be the count and not a row tally.
  if v_cleared <> 1 then
    raise exception 'mark_sanga_read reported % cleared rather than 1.', v_cleared;
  end if;

  -- And nothing the second time. The chat screen calls this on focus and on
  -- every arriving message, and leaves its caches alone when the answer is
  -- zero; a mark that always reports one is a refetch per message received.
  v_cleared := public.mark_sanga_read(
    (select ids.id from public.sanga_unread_test_ids ids where ids.key = 'sanga'));
  if v_cleared <> 0 then
    raise exception
      'A second mark with nothing new reported % cleared rather than 0.', v_cleared;
  end if;
end;
$$;

reset role;

-- t0+4h, so the mark sits between M3 and M4 on the timeline above.
update public.sanga_reads set last_read_at = now() - interval '6 hours'
where sanga_reads.devotee_id = '5a000000-0000-0000-0000-000000000001';

do $$
declare
  v_sanga uuid := (select ids.id from public.sanga_unread_test_ids ids where ids.key = 'sanga');
  v_count integer;
begin
  perform set_config('request.jwt.claim.sub', '5a000000-0000-0000-0000-000000000001', true);
  v_count := public.sanga_unread_count(v_sanga);
  if v_count <> 0 then
    raise exception 'Gopal still has % unread after marking the sanga read.', v_count;
  end if;

  -- The assertion a shared, per-sanga watermark would fail.
  perform set_config('request.jwt.claim.sub', '5a000000-0000-0000-0000-000000000002', true);
  v_count := public.sanga_unread_count(v_sanga);
  if v_count <> 1 then
    raise exception
      'Radha has % unread rather than 1. Gopal reading the thread must not clear hers.', v_count;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Two more messages, after the mark.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', '5a000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
  v_sent public.sanga_messages;
begin
  v_sent := public.send_sanga_message(
    (select ids.id from public.sanga_unread_test_ids ids where ids.key = 'sanga'),
    'No trouble. Chapter two, verse eleven onwards.');
  insert into public.sanga_unread_test_ids values ('m4', v_sent.id);
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '5a000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_sent public.sanga_messages;
begin
  v_sent := public.send_sanga_message(
    (select ids.id from public.sanga_unread_test_ids ids where ids.key = 'sanga'),
    'Understood, thank you.');
  insert into public.sanga_unread_test_ids values ('m5', v_sent.id);
end;
$$;

reset role;

update public.sanga_messages set created_at = now() - interval '5 hours'
where sanga_messages.id = (select ids.id from public.sanga_unread_test_ids ids where ids.key = 'm4');
update public.sanga_messages set created_at = now() - interval '4 hours'
where sanga_messages.id = (select ids.id from public.sanga_unread_test_ids ids where ids.key = 'm5');

do $$
declare
  v_sanga uuid := (select ids.id from public.sanga_unread_test_ids ids where ids.key = 'sanga');
  v_count integer;
begin
  -- M4 is Gopal's own and M5 is Radha's, so the mark he made holds against one
  -- of them and not the other.
  perform set_config('request.jwt.claim.sub', '5a000000-0000-0000-0000-000000000001', true);
  v_count := public.sanga_unread_count(v_sanga);
  if v_count <> 1 then
    raise exception
      'Gopal has % unread rather than 1 after a message arrived past his mark.', v_count;
  end if;

  -- Radha has never marked, so her floor is still her joined_at: M1, M4.
  perform set_config('request.jwt.claim.sub', '5a000000-0000-0000-0000-000000000002', true);
  v_count := public.sanga_unread_count(v_sanga);
  if v_count <> 2 then
    raise exception 'Radha has % unread rather than 2.', v_count;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. A devotee joins a thread that is already seven hours long.
--
--    Zero, and counting starts from the moment she was added.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', '5a000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
begin
  perform public.add_sanga_member(
    (select ids.id from public.sanga_unread_test_ids ids where ids.key = 'sanga'),
    '5a000000-0000-0000-0000-000000000003');
end;
$$;

reset role;

-- t0+7h.
update public.sanga_members set joined_at = now() - interval '3 hours'
where sanga_members.devotee_id = '5a000000-0000-0000-0000-000000000003';

do $$
declare
  v_sanga uuid := (select ids.id from public.sanga_unread_test_ids ids where ids.key = 'sanga');
  v_count integer;
  v_total integer;
begin
  select count(*)::integer into v_total from public.sanga_messages
  where sanga_messages.sanga_id = v_sanga and sanga_messages.deleted_at is null;
  if v_total <> 4 then
    raise exception
      'There are % live messages rather than 4, so Mira''s zero would prove nothing.', v_total;
  end if;

  perform set_config('request.jwt.claim.sub', '5a000000-0000-0000-0000-000000000003', true);
  v_count := public.sanga_unread_count(v_sanga);
  if v_count <> 0 then
    raise exception
      'Mira joined this morning and has % unread. A new member inherits the thread to read, never a badge to clear.', v_count;
  end if;

  -- She has no watermark row at all yet, which is the case the floor exists
  -- for: without it, coalesce would fall back to the beginning of time.
  if exists (
    select 1 from public.sanga_reads
    where sanga_reads.devotee_id = '5a000000-0000-0000-0000-000000000003'
  ) then
    raise exception 'Mira has a watermark she never wrote.';
  end if;
end;
$$;

select set_config('request.jwt.claim.sub', '5a000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
  v_sent public.sanga_messages;
begin
  v_sent := public.send_sanga_message(
    (select ids.id from public.sanga_unread_test_ids ids where ids.key = 'sanga'),
    'Welcome Mira. We are on chapter two.');
  insert into public.sanga_unread_test_ids values ('m6', v_sent.id);
end;
$$;

reset role;

-- t0+8h, after Mira was added.
update public.sanga_messages set created_at = now() - interval '2 hours'
where sanga_messages.id = (select ids.id from public.sanga_unread_test_ids ids where ids.key = 'm6');

do $$
declare
  v_sanga uuid := (select ids.id from public.sanga_unread_test_ids ids where ids.key = 'sanga');
  v_count integer;
begin
  perform set_config('request.jwt.claim.sub', '5a000000-0000-0000-0000-000000000003', true);
  v_count := public.sanga_unread_count(v_sanga);
  if v_count <> 1 then
    raise exception
      'Mira has % unread rather than 1. A new member''s count starts at her first moment inside, and then behaves like everybody else''s.', v_count;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6b. A second circle, so a count is proved to be about one sanga.
--
--     Radha runs a kirtan group. Gopal is not in it; Mira is in both. A count
--     that forgot which sanga it was counting would pass every assertion above,
--     because until now there has only been one — so Gopal's Gita count is read
--     before and after two messages are said somewhere he does not belong, and
--     Mira's is read in both circles at once.
-- ---------------------------------------------------------------------------

do $$
declare
  v_count integer;
begin
  perform set_config('request.jwt.claim.sub', '5a000000-0000-0000-0000-000000000001', true);
  v_count := public.sanga_unread_count(
    (select ids.id from public.sanga_unread_test_ids ids where ids.key = 'sanga'));
  if v_count <> 1 then
    raise exception
      'Gopal has % unread in the Gita circle rather than 1 before the kirtan group exists.', v_count;
  end if;
end;
$$;

select set_config('request.jwt.claim.sub', '5a000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_sanga public.sangas;
begin
  v_sanga := public.create_sanga('Kirtan Group', 'Saturday evenings.');
  insert into public.sanga_unread_test_ids values ('kirtan', v_sanga.id);
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '5a000000-0000-0000-0000-000000000004', true);
set local role authenticated;

do $$
begin
  perform public.review_sanga(
    (select ids.id from public.sanga_unread_test_ids ids where ids.key = 'kirtan'),
    'approved', null);
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '5a000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_kirtan uuid := (select ids.id from public.sanga_unread_test_ids ids where ids.key = 'kirtan');
  v_sent public.sanga_messages;
begin
  perform public.add_sanga_member(v_kirtan, '5a000000-0000-0000-0000-000000000003');

  v_sent := public.send_sanga_message(v_kirtan, 'Bring the kartals.');
  insert into public.sanga_unread_test_ids values ('k1', v_sent.id);
  v_sent := public.send_sanga_message(v_kirtan, 'And the harmonium if you can.');
  insert into public.sanga_unread_test_ids values ('k2', v_sent.id);
end;
$$;

reset role;

update public.sanga_members set joined_at = now() - interval '3 hours'
where sanga_members.sanga_id
      = (select ids.id from public.sanga_unread_test_ids ids where ids.key = 'kirtan');
update public.sanga_messages set created_at = now() - interval '90 minutes'
where sanga_messages.id = (select ids.id from public.sanga_unread_test_ids ids where ids.key = 'k1');
update public.sanga_messages set created_at = now() - interval '80 minutes'
where sanga_messages.id = (select ids.id from public.sanga_unread_test_ids ids where ids.key = 'k2');

do $$
declare
  v_sanga uuid := (select ids.id from public.sanga_unread_test_ids ids where ids.key = 'sanga');
  v_kirtan uuid := (select ids.id from public.sanga_unread_test_ids ids where ids.key = 'kirtan');
  v_count integer;
begin
  perform set_config('request.jwt.claim.sub', '5a000000-0000-0000-0000-000000000001', true);
  v_count := public.sanga_unread_count(v_sanga);
  if v_count <> 1 then
    raise exception
      'Two messages in a circle Gopal is not in moved his Gita count from 1 to %.', v_count;
  end if;
  v_count := public.sanga_unread_count(v_kirtan);
  if v_count <> 0 then
    raise exception 'Gopal has % unread in a sanga he is not in.', v_count;
  end if;

  -- Mira is in both, which is the case a missing sanga_id would pool.
  perform set_config('request.jwt.claim.sub', '5a000000-0000-0000-0000-000000000003', true);
  v_count := public.sanga_unread_count(v_sanga);
  if v_count <> 1 then
    raise exception 'Mira has % unread in the Gita circle rather than 1.', v_count;
  end if;
  v_count := public.sanga_unread_count(v_kirtan);
  if v_count <> 2 then
    raise exception 'Mira has % unread in the kirtan circle rather than 2.', v_count;
  end if;

  -- Radha said both of them.
  perform set_config('request.jwt.claim.sub', '5a000000-0000-0000-0000-000000000002', true);
  v_count := public.sanga_unread_count(v_kirtan);
  if v_count <> 0 then
    raise exception 'Radha has % unread in the circle she has just spoken in.', v_count;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. The observer.
--
--    The President reads every message in this sanga through app.view_all and
--    is not in it. Reading over the top of a circle is not being in it, and a
--    badge would be telling him to catch up on somebody else's conversation.
-- ---------------------------------------------------------------------------

do $$
declare
  v_sanga uuid := (select ids.id from public.sanga_unread_test_ids ids where ids.key = 'sanga');
  v_count integer;
  v_visible integer;
begin
  perform set_config('request.jwt.claim.sub', '5a000000-0000-0000-0000-000000000004', true);

  if public.is_sanga_member(v_sanga) then
    raise exception 'The President is a member, so the next assertion proves nothing.';
  end if;

  select count(*)::integer into v_visible
  from public.list_sanga_messages(v_sanga);
  if v_visible < 5 then
    raise exception
      'The President can read only % messages, so his zero is about visibility rather than membership.', v_visible;
  end if;

  v_count := public.sanga_unread_count(v_sanga);
  if v_count <> 0 then
    raise exception 'The President has % unread in a sanga he is not in.', v_count;
  end if;
end;
$$;

-- And the same answer through the browse list, where the client actually reads
-- it: a row he can see, with a count of zero and no membership.
select set_config('request.jwt.claim.sub', '5a000000-0000-0000-0000-000000000004', true);
set local role authenticated;

do $$
declare
  v_row record;
begin
  select listed.is_member, listed.unread_count into v_row
  from public.list_sangas() listed
  where listed.id = (select ids.id from public.sanga_unread_test_ids ids where ids.key = 'sanga');

  if v_row is null then
    raise exception 'The President cannot see the sanga in list_sangas at all.';
  end if;
  if v_row.is_member then
    raise exception 'list_sangas calls the President a member.';
  end if;
  if v_row.unread_count is distinct from 0 then
    raise exception
      'list_sangas gives the President an unread count of %. A non-member gets zero, consistently.', v_row.unread_count;
  end if;
end;
$$;

-- The guard: he may not mark a circle read that he is not in.
do $$
declare
  v_message text;
begin
  begin
    perform public.mark_sanga_read(
      (select ids.id from public.sanga_unread_test_ids ids where ids.key = 'sanga'));
  exception when others then
    v_message := sqlerrm;
  end;

  if v_message is null then
    raise exception
      'The President marked a sanga read that he is not in, which would leave one member''s worth of state against a non-member.';
  end if;
  if v_message ~* '(constraint|null value|violates|permission denied)' then
    raise exception 'The refusal was unreadable: %', v_message;
  end if;
  if v_message !~* 'sanga' then
    raise exception 'The refusal does not say what was refused: %', v_message;
  end if;

  if exists (
    select 1 from public.sanga_reads
    where sanga_reads.devotee_id = '5a000000-0000-0000-0000-000000000004'
  ) then
    raise exception 'A refused mark still wrote the President a watermark.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. The watermark is the server's to write, and nobody else's to read.
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', '5a000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_sanga uuid := (select ids.id from public.sanga_unread_test_ids ids where ids.key = 'sanga');
  v_seen integer;
begin
  -- A client that could write its own watermark could clear a count it had not
  -- read, or set one far in the future and never see a badge again.
  begin
    insert into public.sanga_reads (sanga_id, devotee_id, last_read_at)
    values (v_sanga, '5a000000-0000-0000-0000-000000000002', now());
    raise exception 'A devotee wrote their own sanga watermark directly.';
  exception when insufficient_privilege then
    null;
  end;

  begin
    update public.sanga_reads set last_read_at = now();
    raise exception 'A devotee moved a sanga watermark directly.';
  exception when insufficient_privilege then
    null;
  end;

  -- When a devotee last opened a thread is a fact about them, not about what
  -- was said in it.
  select count(*)::integer into v_seen from public.sanga_reads;
  if v_seen <> 0 then
    raise exception 'Radha can see % watermarks; Gopal''s reading is his own.', v_seen;
  end if;
end;
$$;

reset role;

-- A watermark never moves backwards. Two of a devotee's devices marking the
-- same sanga read out of order must not resurrect a count already cleared, so
-- Gopal's mark is pushed into the future and a fresh mark must leave it there.
update public.sanga_reads set last_read_at = now() + interval '1 hour'
where sanga_reads.devotee_id = '5a000000-0000-0000-0000-000000000001';

select set_config('request.jwt.claim.sub', '5a000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
begin
  perform public.mark_sanga_read(
    (select ids.id from public.sanga_unread_test_ids ids where ids.key = 'sanga'));
end;
$$;

reset role;

do $$
declare
  v_mark timestamptz;
begin
  select sanga_reads.last_read_at into v_mark from public.sanga_reads
  where sanga_reads.devotee_id = '5a000000-0000-0000-0000-000000000001';
  if v_mark <= now() then
    raise exception 'A second mark dragged the watermark backwards, to %.', v_mark;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 9. What the two lists actually hand the client.
--
--    Both are read as the member, because the client never calls
--    sanga_unread_count itself — it reads the column on these rows, and Home
--    orders by it.
-- ---------------------------------------------------------------------------

update public.sanga_reads set last_read_at = now() - interval '6 hours'
where sanga_reads.devotee_id = '5a000000-0000-0000-0000-000000000001';

select set_config('request.jwt.claim.sub', '5a000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
  v_sanga uuid := (select ids.id from public.sanga_unread_test_ids ids where ids.key = 'sanga');
  v_browse integer;
  v_mine integer;
begin
  select listed.unread_count into v_browse
  from public.list_sangas() listed where listed.id = v_sanga;
  select listed.unread_count into v_mine
  from public.list_my_sangas() listed where listed.id = v_sanga;

  -- M5 is Radha's and past his mark; M6 is his own.
  if v_browse <> 1 then
    raise exception 'list_sangas gives Gopal % rather than 1.', v_browse;
  end if;
  if v_mine <> 1 then
    raise exception 'list_my_sangas gives Gopal % rather than 1.', v_mine;
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '5a000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_sanga uuid := (select ids.id from public.sanga_unread_test_ids ids where ids.key = 'sanga');
  v_browse integer;
  v_mine integer;
begin
  select listed.unread_count into v_browse
  from public.list_sangas() listed where listed.id = v_sanga;
  select listed.unread_count into v_mine
  from public.list_my_sangas() listed where listed.id = v_sanga;

  -- Radha has never marked: M1, M4 and M6 are Gopal's and all past her joining.
  if v_browse <> 3 then
    raise exception 'list_sangas gives Radha % rather than 3.', v_browse;
  end if;
  if v_mine <> 3 then
    raise exception 'list_my_sangas gives Radha % rather than 3.', v_mine;
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);

do $$
begin
  raise notice 'all sanga unread checks passed';
end;
$$;

select 'sanga unread verification passed' as result;

rollback;
