-- Functional verification for 202608040038_children_initiation.sql.
--
-- Rolled back at the end. Every local is prefixed v_ so it can never shadow a
-- column name.
--
-- The final row must read: children initiation verification passed

begin;

-- The President exists first, as in profile_children_and_oversight.sql:
-- announce_new_devotee fires as soon as a profile row appears, and there must
-- be somebody there to be told.
insert into auth.users (id, email, raw_user_meta_data) values
  ('82000000-0000-0000-0000-000000000001', 'diksha-president@example.test', '{"name":"Diksha President"}');

update public.users users
set role_id = (select id from public.roles where name = 'president')
where users.email = 'diksha-president@example.test';

insert into auth.users (id, email, raw_user_meta_data) values
  ('82000000-0000-0000-0000-000000000002', 'diksha-devotee@example.test', '{"name":"Diksha Devotee"}');

select set_config('request.jwt.claim.sub', '82000000-0000-0000-0000-000000000002', true);

-- ---------------------------------------------------------------------------
-- 1. An initiated child keeps all three answers.
-- ---------------------------------------------------------------------------

do $$
declare
  v_children jsonb;
begin
  perform public.update_my_profile_community(
    'male', 'married', 'Radhika Devi Dasi', null, 16,
    'English', null, true, false, null,
    '[{"name":"Nimai","age":17,"gender":"male","practices":true,
       "practicing_since":"since he could walk","initiated":true,
       "initiation_date":"2023-04-09","diksha_guru":"His Holiness Giriraj Swami"}]'::jsonb
  );

  select users.children into v_children
  from public.users where users.id = '82000000-0000-0000-0000-000000000002';

  if (v_children -> 0 ->> 'initiated')::boolean is not true
     or v_children -> 0 ->> 'initiation_date' <> '2023-04-09'
     or v_children -> 0 ->> 'diksha_guru' <> 'His Holiness Giriraj Swami' then
    raise exception 'An initiated child did not round-trip: %.', v_children -> 0;
  end if;
  -- The answers that were already there must not have been disturbed.
  if v_children -> 0 ->> 'name' <> 'Nimai'
     or (v_children -> 0 ->> 'age')::integer <> 17
     or v_children -> 0 ->> 'practicing_since' <> 'since he could walk' then
    raise exception 'The rest of the child came back changed: %.', v_children -> 0;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. "No" clears the date and the guru rather than refusing the save.
--
--    A devotee who ticks yes, types a guru and then corrects themselves must
--    not be left with a child who is both uninitiated and has a diksha guru,
--    and must not lose the rest of what they typed to say so.
-- ---------------------------------------------------------------------------

do $$
declare
  v_children jsonb;
begin
  perform public.update_my_profile_community(
    'male', 'married', 'Radhika Devi Dasi', null, 16,
    'English', null, true, false, null,
    '[{"name":"Nimai","age":17,"gender":"male","practices":true,
       "initiated":false,"initiation_date":"2023-04-09",
       "diksha_guru":"His Holiness Giriraj Swami"},
      {"name":"Gauri","age":4,"gender":"female","practices":true,
       "initiation_date":"2024-01-02","diksha_guru":"Somebody"}]'::jsonb
  );

  select users.children into v_children
  from public.users where users.id = '82000000-0000-0000-0000-000000000002';

  if v_children -> 0 ->> 'initiation_date' is not null
     or v_children -> 0 ->> 'diksha_guru' is not null then
    raise exception 'An uninitiated child kept their initiation details: %.',
      v_children -> 0;
  end if;
  if (v_children -> 0 ->> 'initiated')::boolean is not false then
    raise exception 'The answer itself was not kept: %.', v_children -> 0;
  end if;
  if v_children -> 0 ->> 'name' <> 'Nimai'
     or (v_children -> 0 ->> 'age')::integer <> 17 then
    raise exception 'Clearing the initiation took the rest of the child with it: %.',
      v_children -> 0;
  end if;
  -- A child who was never asked counts as not initiated, so the same holds.
  if v_children -> 1 ->> 'initiation_date' is not null
     or v_children -> 1 ->> 'diksha_guru' is not null then
    raise exception 'A child with no answer at all kept a date or a guru: %.',
      v_children -> 1;
  end if;
  -- Order matters: these are two different children.
  if v_children -> 1 ->> 'name' <> 'Gauri' then
    raise exception 'The children came back out of order: %.', v_children;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. The new keys are accepted, half-filled included.
-- ---------------------------------------------------------------------------

do $$
declare
  v_saved jsonb;
begin
  if not public.children_details_are_valid(
    '[{"initiated":true,"initiation_date":"2020-12-31","diksha_guru":"A guru"},
      {"initiated":null,"initiation_date":null,"diksha_guru":null},
      {"initiated":true}]'::jsonb
  ) then
    raise exception 'The validator did not learn the new keys.';
  end if;

  -- Ticked yes, nothing typed underneath yet: still savable, as every other
  -- half-filled child is.
  perform public.update_my_profile_community(
    'male', 'married', 'Radhika Devi Dasi', null, 16,
    'English', null, true, false, null,
    '[{"name":"Nimai","initiated":true},
      {"name":"Gauri","initiated":true,"diksha_guru":"His Holiness Giriraj Swami"}]'::jsonb
  );

  select users.children into v_saved from public.users
  where users.id = '82000000-0000-0000-0000-000000000002';

  if jsonb_array_length(v_saved) <> 2 then
    raise exception 'A half-filled initiation was not kept (got %).', v_saved;
  end if;
  if v_saved -> 1 ->> 'diksha_guru' <> 'His Holiness Giriraj Swami' then
    raise exception 'A guru without a date was dropped: %.', v_saved -> 1;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. A malformed value for any of the three is still refused, whichever way
--    it arrives.
-- ---------------------------------------------------------------------------

do $$
declare
  v_case record;
  v_refused boolean;
  v_before jsonb;
begin
  select users.children into v_before
  from public.users where users.id = '82000000-0000-0000-0000-000000000002';

  for v_case in
    select * from (values
      ('initiated as a string',
       '[{"name":"Nimai","initiated":"yes"}]'),
      ('initiated as a number',
       '[{"name":"Nimai","initiated":1}]'),
      ('an initiation date that is not text',
       '[{"name":"Nimai","initiated":true,"initiation_date":2023}]'),
      ('an initiation date that is not a date',
       '[{"name":"Nimai","initiated":true,"initiation_date":"last Gaura Purnima"}]'),
      ('an initiation date with a thirteenth month',
       '[{"name":"Nimai","initiated":true,"initiation_date":"2023-13-09"}]'),
      ('a diksha guru that is not text',
       '[{"name":"Nimai","initiated":true,"diksha_guru":42}]'),
      ('a diksha guru that is an object',
       '[{"name":"Nimai","initiated":true,"diksha_guru":{"name":"A guru"}}]'),
      ('a near miss on one of the new keys',
       '[{"name":"Nimai","initiation_guru":"A guru"}]')
    ) as bad(label, payload)
  loop
    if public.children_details_are_valid(v_case.payload::jsonb) then
      raise exception 'The validator accepted %.', v_case.label;
    end if;

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
      where id = '82000000-0000-0000-0000-000000000002';
    exception when others then
      v_refused := true;
    end;
    if not v_refused then
      raise exception 'The table accepted % written directly.', v_case.label;
    end if;
  end loop;

  if (select users.children from public.users
      where users.id = '82000000-0000-0000-0000-000000000002') is distinct from v_before then
    raise exception 'A refused write still changed the stored children.';
  end if;
end;
$$;

do $$
begin
  raise notice 'all children initiation checks passed';
end;
$$;

select 'children initiation verification passed' as result;

rollback;
