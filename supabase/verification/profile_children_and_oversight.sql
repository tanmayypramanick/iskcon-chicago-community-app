-- Functional verification for 202608040037_profile_children_and_oversight.sql.
--
-- Rolled back at the end. Every local is prefixed v_ so it can never shadow a
-- column name.
--
-- The final row must read: profile children and oversight verification passed

begin;

-- The President is created and given their role FIRST, exactly as in
-- devotee_profiles.sql: announce_new_devotee fires the moment a profile row
-- appears, and there must be somebody there to be told.
insert into auth.users (id, email, raw_user_meta_data) values
  ('81000000-0000-0000-0000-000000000001', 'kids-president@example.test', '{"name":"Kids President"}');

update public.users users
set role_id = (select id from public.roles where name = 'president')
where users.email = 'kids-president@example.test';

insert into auth.users (id, email, raw_user_meta_data) values
  ('81000000-0000-0000-0000-000000000002', 'kids-devotee@example.test', '{"name":"Kids Devotee"}'),
  ('81000000-0000-0000-0000-000000000003', 'kids-friend@example.test', '{"name":"Kids Friend"}');

-- ---------------------------------------------------------------------------
-- 1. Children round-trip, and the count follows the list.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', '81000000-0000-0000-0000-000000000002', true);

do $$
declare
  v_children jsonb;
  v_count integer;
begin
  -- The caller deliberately passes a count of 9 that disagrees with the two
  -- children it sends. The list must win.
  perform public.update_my_profile_community(
    'male', 'married', 'Radhika Devi Dasi', 9, 16,
    'English, Hindi', 'A friend brought me', true, false, 'Kirtan',
    '[{"name":"Nimai","age":7,"gender":"male","practices":true,"practicing_since":"since he could walk"},
      {"name":"Gauri","age":0,"gender":"female","practices":false,"practicing_since":null}]'::jsonb
  );

  select users.children, users.children_count into v_children, v_count
  from public.users where users.id = '81000000-0000-0000-0000-000000000002';

  if jsonb_array_length(v_children) <> 2 then
    raise exception 'The children did not round-trip (got %).', v_children;
  end if;
  if v_children -> 0 ->> 'name' <> 'Nimai'
     or (v_children -> 0 ->> 'age')::integer <> 7
     or v_children -> 0 ->> 'gender' <> 'male'
     or (v_children -> 0 ->> 'practices')::boolean is not true
     or v_children -> 0 ->> 'practicing_since' <> 'since he could walk' then
    raise exception 'A child came back changed: %.', v_children -> 0;
  end if;
  -- Age zero and a null practicing_since are both legitimate answers.
  if (v_children -> 1 ->> 'age')::integer <> 0
     or v_children -> 1 -> 'practicing_since' <> 'null'::jsonb then
    raise exception 'A newborn with no start date was not stored as given: %.', v_children -> 1;
  end if;
  if v_count <> 2 then
    raise exception 'children_count did not follow the list (got %, expected 2).', v_count;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Malformed children are refused, whichever way they arrive.
-- ---------------------------------------------------------------------------

do $$
declare
  v_case record;
  v_refused boolean;
  v_before jsonb;
begin
  select users.children into v_before
  from public.users where users.id = '81000000-0000-0000-0000-000000000002';

  for v_case in
    select * from (values
      ('a gender nobody offered',
       '[{"name":"Nimai","age":7,"gender":"other","practices":true}]'),
      ('an impossible age',
       '[{"name":"Nimai","age":300,"gender":"male","practices":true}]'),
      ('a negative age',
       '[{"name":"Nimai","age":-1,"gender":"male","practices":true}]'),
      ('an age that is not a number',
       '[{"name":"Nimai","age":"seven","gender":"male","practices":true}]'),
      ('a name that is not text',
       '[{"name":42,"age":7,"gender":"male","practices":true}]'),
      ('practices as a string',
       '[{"name":"Nimai","age":7,"gender":"male","practices":"yes"}]'),
      ('a key the app never sends',
       '[{"name":"Nimai","age":7,"gender":"male","practices":true,"school":"Bhaktivedanta"}]'),
      ('an entry that is not an object',
       '["Nimai"]'),
      ('an object where an array belongs',
       '{"name":"Nimai"}')
    ) as bad(label, payload)
  loop
    -- a) Through the RPC.
    v_refused := false;
    begin
      perform public.update_my_profile_community(
        'male', 'married', 'Radhika Devi Dasi', null, 16,
        'English', null, true, false, null, v_case.payload::jsonb
      );
    exception when others then
      v_refused := true;
    end;
    if not v_refused then
      raise exception 'update_my_profile_community accepted %.', v_case.label;
    end if;

    -- b) And straight at the table, which is where a client that talks to
    --    PostgREST directly would try.
    v_refused := false;
    begin
      update public.users
      set children = v_case.payload::jsonb, children_count = null
      where id = '81000000-0000-0000-0000-000000000002';
    exception when others then
      v_refused := true;
    end;
    if not v_refused then
      raise exception 'The table accepted % written directly.', v_case.label;
    end if;
  end loop;

  -- Nothing that was refused may have landed.
  if (select users.children from public.users
      where users.id = '81000000-0000-0000-0000-000000000002') is distinct from v_before then
    raise exception 'A refused write still changed the stored children.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2b. A half-filled child is kept, not refused.
--
--     A devotee types their children in over more than one sitting. Rejecting
--     a row that is missing an age would throw away everything else they had
--     just entered, so only the shape of a value that is present is policed.
-- ---------------------------------------------------------------------------

do $$
declare
  v_saved jsonb;
begin
  perform public.update_my_profile_community(
    'male', 'married', 'Radhika Devi Dasi', null, 16,
    'English', null, true, false, null,
    '[{"name":"Nimai","practices":false},
      {"name":"","age":null,"gender":null,"practices":true},
      {"age":9,"gender":"female","practices":true}]'::jsonb
  );

  select children into v_saved from public.users
  where id = '81000000-0000-0000-0000-000000000002';

  if jsonb_array_length(v_saved) <> 3 then
    raise exception 'A partly filled set of children was not kept whole (got %).',
      jsonb_array_length(v_saved);
  end if;
  if v_saved -> 0 ->> 'name' is distinct from 'Nimai' then
    raise exception 'The one child who was named lost their name.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. The count cannot be made to disagree with the list.
-- ---------------------------------------------------------------------------

do $$
declare
  v_refused boolean := false;
  v_count integer;
begin
  begin
    update public.users
    set children_count = 5
    where id = '81000000-0000-0000-0000-000000000002';
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'children_count was allowed to disagree with the list.';
  end if;

  -- An empty list leaves the count alone: a devotee who never filled the
  -- details in still told us how many children they have.
  update public.users
  set children = '[]'::jsonb, children_count = 4
  where id = '81000000-0000-0000-0000-000000000002';

  select users.children_count into v_count
  from public.users where users.id = '81000000-0000-0000-0000-000000000002';
  if v_count <> 4 then
    raise exception 'A bare count alongside an empty list was not kept (got %).', v_count;
  end if;

  -- And putting the list back brings the count with it.
  perform public.update_my_profile_community(
    'male', 'married', 'Radhika Devi Dasi', 4, 16,
    'English', null, true, false, null,
    '[{"name":"Nimai","age":7,"gender":"male","practices":true,"practicing_since":"since he could walk"}]'::jsonb
  );
  select users.children_count into v_count
  from public.users where users.id = '81000000-0000-0000-0000-000000000002';
  if v_count <> 1 then
    raise exception 'children_count did not come back down with the list (got %).', v_count;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. How long they have been coming saves, and a nonsense unit does not.
-- ---------------------------------------------------------------------------

do $$
declare
  v_amount integer;
  v_unit text;
  v_joined date;
  v_refused boolean := false;
begin
  perform public.update_my_profile_extras(
    'Kids Friend', '+1 312 555 0144', null, null, 'Hindi', 'Teacher',
    date '2019-08-01', 3, 'years'
  );

  select users.temple_since_amount, users.temple_since_unit, users.joined_temple_on
  into v_amount, v_unit, v_joined
  from public.users where users.id = '81000000-0000-0000-0000-000000000002';

  if v_amount <> 3 or v_unit <> 'years' then
    raise exception 'The temple-since pair did not save (got %, %).', v_amount, v_unit;
  end if;
  -- joined_temple_on is not dropped: other code still reads it.
  if v_joined <> date '2019-08-01' then
    raise exception 'joined_temple_on stopped being written (got %).', v_joined;
  end if;

  begin
    perform public.update_my_profile_extras(
      'Kids Friend', null, null, null, null, null, null, 3, 'fortnights'
    );
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A unit nobody offered was accepted.';
  end if;

  v_refused := false;
  begin
    update public.users set temple_since_amount = -2
    where id = '81000000-0000-0000-0000-000000000002';
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A negative length of time was accepted.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. A deleted message still reads "deleted" to the devotees in the thread.
-- ---------------------------------------------------------------------------

do $$
declare
  v_conversation uuid;
  v_message public.messages;
  v_deleted public.messages;
begin
  v_conversation := public.open_conversation('81000000-0000-0000-0000-000000000003');
  v_message := public.send_message(
    v_conversation, 'Could you bring the flowers on Sunday?',
    'https://example.test/message-images/flowers.jpg'
  );

  v_deleted := public.delete_message(v_message.id);
  if v_deleted.deleted_at is null then
    raise exception 'Deleting did not mark the message deleted.';
  end if;
  if v_deleted.body is not null or v_deleted.image_url is not null then
    raise exception 'Deleting left the message showing in the thread.';
  end if;

  -- Deleting twice must not wipe what was moved aside the first time.
  perform public.delete_message(v_message.id);
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. The conversation reads in full for a holder of app.view_all, and not at
--    all for anybody else.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', '81000000-0000-0000-0000-000000000001', true);

do $$
declare
  v_conversation uuid;
  v_row record;
  v_rows integer;
begin
  select conversations.id into v_conversation
  from public.conversations
  where conversations.lower_devotee_id in (
          '81000000-0000-0000-0000-000000000002',
          '81000000-0000-0000-0000-000000000003')
    and conversations.higher_devotee_id in (
          '81000000-0000-0000-0000-000000000002',
          '81000000-0000-0000-0000-000000000003');

  select count(*) into v_rows
  from public.list_conversation_messages(v_conversation);
  if v_rows <> 1 then
    raise exception 'The conversation came back with % messages, expected 1.', v_rows;
  end if;

  select * into v_row
  from public.list_conversation_messages(v_conversation) limit 1;

  if v_row.sender_name <> 'Kids Devotee' then
    raise exception 'The sender was not named (got %).', v_row.sender_name;
  end if;
  if v_row.deleted_at is null then
    raise exception 'The row did not come back marked deleted.';
  end if;
  if v_row.body is not null or v_row.image_url is not null then
    raise exception 'The live columns were not cleared by deletion.';
  end if;
  if v_row.original_body <> 'Could you bring the flowers on Sunday?' then
    raise exception 'The retained text did not come back (got %).', v_row.original_body;
  end if;
  if v_row.original_image_url <> 'https://example.test/message-images/flowers.jpg' then
    raise exception 'The retained picture did not come back (got %).', v_row.original_image_url;
  end if;
end;
$$;

select set_config('request.jwt.claim.sub', '81000000-0000-0000-0000-000000000002', true);

do $$
declare
  v_conversation uuid;
  v_rows integer;
begin
  select conversations.id into v_conversation
  from public.conversations
  where conversations.lower_devotee_id in (
          '81000000-0000-0000-0000-000000000002',
          '81000000-0000-0000-0000-000000000003')
    and conversations.higher_devotee_id in (
          '81000000-0000-0000-0000-000000000002',
          '81000000-0000-0000-0000-000000000003');

  -- The devotee is in this very conversation, and still gets nothing: the
  -- function is for app.view_all and nothing else.
  select count(*) into v_rows
  from public.list_conversation_messages(v_conversation);
  if v_rows <> 0 then
    raise exception 'A devotee without app.view_all read % rows.', v_rows;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. The retained columns are off the devotee grant entirely.
-- ---------------------------------------------------------------------------

do $$
declare
  v_grants integer;
begin
  select count(*) into v_grants
  from information_schema.column_privileges
  where table_schema = 'public'
    and table_name = 'messages'
    and column_name in ('original_body', 'original_image_url')
    and grantee in ('authenticated', 'anon', 'PUBLIC');
  if v_grants > 0 then
    raise exception 'The retained columns are still granted to a client role.';
  end if;

  -- The columns devotees do need must not have been lost along the way.
  select count(*) into v_grants
  from information_schema.column_privileges
  where table_schema = 'public'
    and table_name = 'messages'
    and privilege_type = 'SELECT'
    and grantee = 'authenticated'
    and column_name in (
      'id', 'conversation_id', 'sender_id', 'body', 'image_url',
      'created_at', 'read_at', 'delivered_at', 'deleted_at'
    );
  if v_grants <> 9 then
    raise exception 'A devotee lost a message column they need (% of 9).', v_grants;
  end if;
end;
$$;

do $$
declare
  v_refused boolean := false;
  v_probe text;
begin
  begin
    perform set_config('role', 'authenticated', true);
    execute 'select messages.original_body from public.messages limit 1' into v_probe;
  exception when insufficient_privilege then
    -- The subtransaction rolls back, and the role with it.
    v_refused := true;
  end;

  if not v_refused then
    raise exception 'A devotee could select the retained text off the table.';
  end if;
end;
$$;

reset role;

do $$
begin
  raise notice 'all profile children and oversight checks passed';
end;
$$;

select 'profile children and oversight verification passed' as result;

rollback;
