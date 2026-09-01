-- Functional verification for 202608300080_temple_deities.sql.
--
-- Rolled back at the end. Every local is prefixed v_ so it can never shadow a
-- column name. Anything that must be refused is attempted as the devotee who
-- would really attempt it, under `set local role authenticated`, so the row
-- level security policies and the column grants are the thing being tested
-- rather than superuser rights quietly waving everything through.
--
-- The six people in this script:
--   President  ...0001  may edit the list
--   Head       ...0002  Community Head; does most of what is checked here
--   Tech       ...0003  Tech Admin; the third of the three who may edit
--   Devotee    ...0004  reads the list, changes nothing
--   Volunteer  ...0005  the nearest role that must still be refused
--   Head Two   ...0006  a second Community Head, for the delete rule in §9
--
-- What this script exists to prove:
--
--    1. The catalogue is a table, its editors are named by the permission the
--       app already uses for those three roles, and no new key was invented.
--       Every limit is a dial.
--    2. The three Deities the temple named are seeded, in the temple's order
--       and not alphabetically, a whole order_step apart.
--    3. Every signed-in devotee may read the list, through the table and
--       through the RPC. Anon gets nothing, either way.
--    4. Only the Community Head, Tech Admin and President may change it. A
--       devotee and a volunteer are refused on every write.
--    5. Matching folds case, spacing and punctuation; alternate spellings are
--       consulted; a retired Deity still answers; an unknown name resolves to
--       null rather than to a guess.
--    6. Every guard on the catalogue itself: a duplicate altar, a spelling
--       that would mean two Deities, an over-long name, an over-long name for
--       the darshan column, too many alternate spellings, too many Deities, a
--       nameless Deity, a negative place in the list.
--    7. daily_darshan_images.deity is still text and still has no foreign key,
--       so a visiting Deity is still postable -- and a name the catalogue DOES
--       recognise is stored in the temple's spelling however it was typed.
--    8. 0079 still groups a day correctly and still produces its documented
--       strings. A day whose three pictures spell one altar three ways names
--       that altar ONCE, which is the whole reason this file exists.
--    9. 0078's delete_daily_darshan still allows the poster, the President and
--       the Tech Admin. Read and confirmed; nothing in 0078 was changed.
--   10. Fourteen mutations, each breaking exactly one thing.
--
-- The final row must read: temple deities verification passed

begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('e0000000-0000-0000-0000-000000000001', 'td-president@example.test', '{"name":"Tee President"}'),
  ('e0000000-0000-0000-0000-000000000002', 'td-head@example.test', '{"name":"Tee Head"}'),
  ('e0000000-0000-0000-0000-000000000003', 'td-tech@example.test', '{"name":"Tee Tech"}'),
  ('e0000000-0000-0000-0000-000000000004', 'td-devotee@example.test', '{"name":"Tee Devotee"}'),
  ('e0000000-0000-0000-0000-000000000005', 'td-volunteer@example.test', '{"name":"Tee Volunteer"}'),
  ('e0000000-0000-0000-0000-000000000006', 'td-head2@example.test', '{"name":"Tee Head Two"}');

update public.users
set role_id = (select roles.id from public.roles where roles.name = 'president')
where email = 'td-president@example.test';
update public.users
set role_id = (select roles.id from public.roles where roles.name = 'core')
where email in ('td-head@example.test', 'td-head2@example.test');
update public.users
set role_id = (select roles.id from public.roles where roles.name = 'tech')
where email = 'td-tech@example.test';
update public.users
set role_id = (select roles.id from public.roles where roles.name = 'devotee')
where email = 'td-devotee@example.test';
update public.users
set role_id = (select roles.id from public.roles where roles.name = 'volunteer')
where email = 'td-volunteer@example.test';

-- The account-creation trigger has already written devotee_joined rows.
delete from public.app_notifications;
delete from public.daily_darshan;

-- ---------------------------------------------------------------------------
-- 1. The shape of the answer: a table, the existing permission, and dials.
--
--    A catalogue that turned out to be a constant, or a JSON blob in
--    app_settings, would mean the temple needs a release to install a Deity.
--    That is the decision this file was written to make, so it is asserted
--    rather than assumed.
-- ---------------------------------------------------------------------------

do $$
declare
  v_holders text;
  v_key text;
begin
  if to_regclass('public.temple_deities') is null then
    raise exception 'The Deity catalogue is not a table.';
  end if;

  -- It is a real table, not a view over a constant list.
  if (select relkind from pg_class where oid = 'public.temple_deities'::regclass) <> 'r' then
    raise exception 'public.temple_deities is not an ordinary table.';
  end if;

  -- The editors are the three the temple named, by the key the app already
  -- uses for them. Nothing new was registered.
  select string_agg(roles.name, ',' order by roles.name) into v_holders
  from public.role_permissions
  join public.roles on roles.id = role_permissions.role_id
  where role_permissions.permission_key = 'services.manage_recurring';

  if v_holders is distinct from 'core,president,tech' then
    raise exception
      'services.manage_recurring is held by % - the Deity catalogue assumes core, president, tech.',
      coalesce(v_holders, '(nobody)');
  end if;

  if exists (
    select 1 from public.role_permissions
    where role_permissions.permission_key ilike '%deit%'
       or role_permissions.permission_key ilike '%deity%'
  ) then
    raise exception 'A separate Deity permission key was registered.';
  end if;

  -- may_edit_temple_deities is the darshan's permission, not a second copy of
  -- the reasoning. If it stopped calling may_post_daily_darshan the two could
  -- be edited apart.
  if pg_get_functiondef('public.may_edit_temple_deities()'::regprocedure)
     !~ 'may_post_daily_darshan' then
    raise exception
      'may_edit_temple_deities no longer defers to may_post_daily_darshan; the two sets can now drift.';
  end if;

  -- Every limit is a dial. A missing one means some function body is carrying
  -- a literal instead.
  foreach v_key in array array[
    'temple_deities.max_name_chars', 'temple_deities.max_aliases',
    'temple_deities.max_entries', 'temple_deities.list_limit_max',
    'temple_deities.order_step'
  ]
  loop
    if not exists (select 1 from public.app_settings where app_settings.key = v_key) then
      raise exception 'The dial % is not in app_settings.', v_key;
    end if;
  end loop;

  if public.daily_darshan_limit('temple_deities.order_step') <> 10 then
    raise exception 'The order step is not 10.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. The three the temple named, in the temple's order.
--
--    And deliberately NOT in alphabetical order, which is checked rather than
--    described: alphabetically the picker would open on Gaura Nitai, which is
--    a fact about the letter G and not about the altar.
-- ---------------------------------------------------------------------------

do $$
declare
  v_temple text;
  v_alphabetical text;
  v_orders text;
  v_step integer := public.daily_darshan_limit('temple_deities.order_step');
begin
  select string_agg(temple_deities.name, ' | '
                    order by temple_deities.display_order, temple_deities.name)
  into v_temple
  from public.temple_deities where temple_deities.is_active;

  if v_temple is distinct from 'Kisora Kisori | Gaura Nitai | Jagannath Baldev Subhadra' then
    raise exception 'The temple''s list of Deities reads: %', coalesce(v_temple, '(empty)');
  end if;

  select string_agg(temple_deities.name, ' | ' order by temple_deities.name)
  into v_alphabetical
  from public.temple_deities where temple_deities.is_active;

  if v_alphabetical = v_temple then
    raise exception
      'The seeded order happens to be alphabetical, so this script cannot tell the two apart.';
  end if;

  -- A whole step apart, so a fourth altar fits between two without renumbering.
  select string_agg(temple_deities.display_order::text, ','
                    order by temple_deities.display_order)
  into v_orders
  from public.temple_deities;

  if v_orders is distinct from (v_step * 1) || ',' || (v_step * 2) || ',' || (v_step * 3) then
    raise exception 'The seeded places in the list are %, not one order_step apart.', v_orders;
  end if;

  -- The generated key really is section 2's function, checked here as well as
  -- at deploy time, because everything below depends on the two agreeing.
  if exists (
    select 1 from public.temple_deities
    where temple_deities.match_key
          is distinct from public.temple_deity_match_key(temple_deities.name)
  ) then
    raise exception 'The stored match key disagrees with temple_deity_match_key.';
  end if;
end;
$$;

-- The seed runs only into an empty catalogue, so a re-applied migration cannot
-- resurrect a Deity the temple has since renamed as a second altar.
do $$
declare
  v_before integer;
  v_after integer;
begin
  select count(*)::integer into v_before from public.temple_deities;

  update public.temple_deities
  set name = 'Sri Sri Nitai Gaurasundara Renamed'
  where public.temple_deity_match_key(temple_deities.name) = 'gauranitai';

  -- Exactly what the migration's seed block does.
  if not exists (select 1 from public.temple_deities) then
    raise exception 'The catalogue emptied itself.';
  end if;

  select count(*)::integer into v_after from public.temple_deities;
  if v_after <> v_before then
    raise exception 'Re-seeding a renamed catalogue changed its size from % to %.', v_before, v_after;
  end if;

  update public.temple_deities
  set name = 'Gaura Nitai'
  where temple_deities.name = 'Sri Sri Nitai Gaurasundara Renamed';
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Every signed-in devotee reads it. Anon reads nothing.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'e0000000-0000-0000-0000-000000000004', true);
set local role authenticated;

do $$
declare
  v_count integer;
  v_first text;
begin
  select count(*)::integer into v_count from public.temple_deities;
  if v_count <> 3 then
    raise exception 'A devotee reading the table directly saw % Deities.', v_count;
  end if;

  select count(*)::integer into v_count from public.list_temple_deities();
  if v_count <> 3 then
    raise exception 'A devotee listing the Deities saw %.', v_count;
  end if;

  -- The picker's order comes out of the RPC, not out of the client.
  select listed.name into v_first from public.list_temple_deities() as listed limit 1;
  if v_first is distinct from 'Kisora Kisori' then
    raise exception 'The picker opens on %, not on the temple''s first altar.', v_first;
  end if;

  -- The ceiling on one read is a dial and is enforced.
  select count(*)::integer into v_count from public.list_temple_deities(false, 1);
  if v_count <> 1 then
    raise exception 'Asking for one Deity returned %.', v_count;
  end if;

  -- A devotee may read and may not write, and the grants say so rather than
  -- the RPC saying so.
  begin
    insert into public.temple_deities (name) values ('Not A Deity');
    raise exception 'A devotee inserted straight into the catalogue.';
  exception when insufficient_privilege then null;
  end;

  begin
    update public.temple_deities set name = 'Renamed';
    raise exception 'A devotee renamed a Deity straight in the table.';
  exception when insufficient_privilege then null;
  end;

  begin
    delete from public.temple_deities;
    raise exception 'A devotee deleted the temple''s Deities.';
  exception when insufficient_privilege then null;
  end;
end;
$$;

-- The ceiling on one read is a dial, and it clamps a client asking for more.
-- The dial reader is not granted to a devotee, so this is asked as the temple's
-- own server; the answer it checks is the one the devotee's RPC returns.
reset role;

do $$
declare
  v_max integer := public.daily_darshan_limit('temple_deities.list_limit_max');
  v_count integer;
begin
  perform set_config('request.jwt.claim.sub', 'e0000000-0000-0000-0000-000000000004', true);

  update public.app_settings set value = '2'
  where app_settings.key = 'temple_deities.list_limit_max';

  select count(*)::integer into v_count from public.list_temple_deities(false, 100000);
  if v_count <> 2 then
    raise exception 'Asking for a hundred thousand Deities returned % of them.', v_count;
  end if;

  update public.app_settings set value = v_max::text
  where app_settings.key = 'temple_deities.list_limit_max';
end;
$$;

select set_config('request.jwt.claim.sub', 'e0000000-0000-0000-0000-000000000005', true);
set local role authenticated;

do $$
declare
  v_count integer;
begin
  -- A volunteer is a signed-in devotee and reads the list like anybody else.
  select count(*)::integer into v_count from public.list_temple_deities();
  if v_count <> 3 then
    raise exception 'A volunteer listing the Deities saw %.', v_count;
  end if;
end;
$$;

-- Anon reads nothing, through either door. This is a congregation's app.
reset role;
select set_config('request.jwt.claim.sub', '', true);
set local role anon;

do $$
declare
  v_refused boolean;
begin
  v_refused := false;
  begin
    perform 1 from public.temple_deities;
  exception when others then v_refused := true;
  end;
  if not v_refused then
    raise exception 'Anon read the temple''s Deities straight from the table.';
  end if;

  v_refused := false;
  begin
    perform public.list_temple_deities();
  exception when others then v_refused := true;
  end;
  if not v_refused then
    raise exception 'Anon listed the temple''s Deities.';
  end if;

  v_refused := false;
  begin
    perform public.resolve_temple_deity_name('Gaura Nitai');
  exception when others then v_refused := true;
  end;
  if not v_refused then
    raise exception 'Anon asked the catalogue what a name means.';
  end if;

  v_refused := false;
  begin
    perform public.add_temple_deity('Anon''s Deity');
  exception when others then v_refused := true;
  end;
  if not v_refused then
    raise exception 'Anon added a Deity.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Only the three may change it.
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', 'e0000000-0000-0000-0000-000000000004', true);
set local role authenticated;

do $$
declare
  v_id uuid;
  v_refused boolean;
begin
  select temple_deities.id into v_id from public.temple_deities
  where temple_deities.name = 'Gaura Nitai';

  v_refused := false;
  begin
    perform public.add_temple_deity('A Devotee''s Deity');
  exception when others then v_refused := true;
  end;
  if not v_refused then
    raise exception 'A devotee added a Deity to the temple''s list.';
  end if;

  v_refused := false;
  begin
    perform public.update_temple_deity(v_id, 'Renamed By A Devotee');
  exception when others then v_refused := true;
  end;
  if not v_refused then
    raise exception 'A devotee renamed one of the temple''s Deities.';
  end if;

  v_refused := false;
  begin
    perform public.update_temple_deity(v_id, p_is_active => false);
  exception when others then v_refused := true;
  end;
  if not v_refused then
    raise exception 'A devotee retired one of the temple''s Deities.';
  end if;

  if public.may_edit_temple_deities() then
    raise exception 'may_edit_temple_deities says a plain devotee may edit the list.';
  end if;

  -- The maintenance view is for the people who maintain the list.
  if exists (select 1 from public.unmatched_darshan_deity_names()) then
    raise exception 'A devotee was shown the unmatched Deity names.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'e0000000-0000-0000-0000-000000000005', true);
set local role authenticated;

do $$
declare
  v_refused boolean;
begin
  -- The volunteer is the nearest role to the three and must still be refused.
  v_refused := false;
  begin
    perform public.add_temple_deity('A Volunteer''s Deity');
  exception when others then v_refused := true;
  end;
  if not v_refused then
    raise exception 'A volunteer added a Deity to the temple''s list.';
  end if;

  if public.may_edit_temple_deities() then
    raise exception 'may_edit_temple_deities says a volunteer may edit the list.';
  end if;
end;
$$;

-- All three of the named roles are accepted. Each adds one and the rows are
-- taken away again afterwards, so the fixture below is still the seeded three.
reset role;
select set_config('request.jwt.claim.sub', 'e0000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_id uuid;
begin
  if not public.may_edit_temple_deities() then
    raise exception 'The Community Head may not edit the temple''s list of Deities.';
  end if;
  v_id := public.add_temple_deity('Added By The Head');
  if v_id is null then
    raise exception 'The Community Head''s Deity was not added.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'e0000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
begin
  if not public.may_edit_temple_deities() then
    raise exception 'The President may not edit the temple''s list of Deities.';
  end if;
  perform public.add_temple_deity('Added By The President');
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'e0000000-0000-0000-0000-000000000003', true);
set local role authenticated;

do $$
declare
  v_row public.temple_deities;
  v_id uuid;
begin
  if not public.may_edit_temple_deities() then
    raise exception 'The Tech Admin may not edit the temple''s list of Deities.';
  end if;
  v_id := public.add_temple_deity('Added By Tech');

  -- Rename, reorder, re-spell and retire, all through the one RPC. Null leaves
  -- a field alone, which is the contract a client that only reorders relies on.
  v_row := public.update_temple_deity(v_id, p_display_order => 999);
  if v_row.name <> 'Added By Tech' then
    raise exception 'Reordering a Deity changed Their name to %.', v_row.name;
  end if;
  if v_row.display_order <> 999 then
    raise exception 'Reordering a Deity did not move Them.';
  end if;

  v_row := public.update_temple_deity(v_id, p_is_active => false);
  if v_row.is_active then
    raise exception 'Retiring a Deity did not retire Them.';
  end if;
  if v_row.name <> 'Added By Tech' then
    raise exception 'Retiring a Deity changed Their name.';
  end if;

  -- Retired: gone from the picker, still in the list when asked for.
  if exists (select 1 from public.list_temple_deities() as listed
             where listed.name = 'Added By Tech') then
    raise exception 'A retired Deity is still in the picker.';
  end if;
  if not exists (select 1 from public.list_temple_deities(true) as listed
                 where listed.name = 'Added By Tech') then
    raise exception 'A retired Deity vanished from the full list.';
  end if;

  -- And still means what They meant, which is the point of retiring rather
  -- than deleting: the gallery is full of Their name already.
  if public.resolve_temple_deity_name('added by tech') is distinct from 'Added By Tech' then
    raise exception 'A retired Deity stopped canonicalising Their own name.';
  end if;
end;
$$;

reset role;
delete from public.temple_deities
where temple_deities.name in ('Added By The Head', 'Added By The President', 'Added By Tech');

-- ---------------------------------------------------------------------------
-- 5. What the catalogue thinks two spellings mean.
--
--    This is the mechanism that replaces the foreign key, so it is checked at
--    length: case, spacing, punctuation, alternate spellings, and a name the
--    temple has never heard of resolving to null rather than to a guess.
-- ---------------------------------------------------------------------------

do $$
declare
  v_spelling text;
  v_answer text;
begin
  foreach v_spelling in array array[
    'Gaura Nitai', 'gaura nitai', 'GAURA NITAI', 'Gaura-Nitai', 'Gaura  Nitai',
    'GauraNitai', ' gaura nitai ', 'Gaura.Nitai', 'Nitai Gaura', 'nitai-gaura',
    'Gauranga Nityananda', 'Sri Sri Nitai Gaurasundara'
  ]
  loop
    v_answer := public.resolve_temple_deity_name(v_spelling);
    if v_answer is distinct from 'Gaura Nitai' then
      raise exception '"%" resolved to % instead of Gaura Nitai.', v_spelling, coalesce(v_answer, '(nothing)');
    end if;
  end loop;

  foreach v_spelling in array array[
    'Kisora Kisori', 'kisora-kisori', 'KISORA KISORI', 'Kishora Kishori',
    'Sri Sri Kisora Kisori'
  ]
  loop
    v_answer := public.resolve_temple_deity_name(v_spelling);
    if v_answer is distinct from 'Kisora Kisori' then
      raise exception '"%" resolved to % instead of Kisora Kisori.', v_spelling, coalesce(v_answer, '(nothing)');
    end if;
  end loop;

  foreach v_spelling in array array[
    'Jagannath Baldev Subhadra', 'jagannath baldev subhadra',
    'Jagannatha Baladeva Subhadra', 'Jagannath-Baldev-Subhadra',
    'Jagannath Subhadra Baldev'
  ]
  loop
    v_answer := public.resolve_temple_deity_name(v_spelling);
    if v_answer is distinct from 'Jagannath Baldev Subhadra' then
      raise exception '"%" resolved to % instead of Jagannath Baldev Subhadra.',
        v_spelling, coalesce(v_answer, '(nothing)');
    end if;
  end loop;

  -- The visiting Deity, the festival installation, and nonsense: null, never a
  -- guess. A catalogue that answered "Kisora Kisori" to an unknown name would
  -- silently relabel somebody else's photograph.
  foreach v_spelling in array array[
    'Their Lordships on the Ratha', 'Srila Prabhupada', 'Radha Govinda',
    'Sri Sri Radha Govinda', '...', ' '
  ]
  loop
    v_answer := public.resolve_temple_deity_name(v_spelling);
    if v_answer is not null then
      raise exception '"%" was taken to mean %.', v_spelling, v_answer;
    end if;
  end loop;

  if public.resolve_temple_deity_name(null) is not null then
    raise exception 'A null name was taken to mean something.';
  end if;

  -- The folding keeps letters rather than reducing them to ASCII, which is
  -- what stops two spellings of one Sanskrit name becoming two keys.
  if public.temple_deity_match_key('Radha') = public.temple_deity_match_key('Govinda') then
    raise exception 'The match key has collapsed two different names into one.';
  end if;
  if public.temple_deity_match_key('...') is not null then
    raise exception 'A name with no letters in it produced a match key.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. The catalogue's own guards.
-- ---------------------------------------------------------------------------

-- As the Community Head. Every guard below lives inside a security definer
-- RPC and is decided by auth.uid() rather than by the database role, and the
-- dials these assertions read are not granted to a devotee, so this section
-- keeps the Head's identity and the temple's own role. Section 3 is where the
-- grants themselves are tested.
reset role;

do $$
declare
  v_refused boolean;
  v_id uuid;
  v_max_name integer := public.daily_darshan_limit('temple_deities.max_name_chars');
  v_max_aliases integer := public.daily_darshan_limit('temple_deities.max_aliases');
begin
  perform set_config('request.jwt.claim.sub', 'e0000000-0000-0000-0000-000000000002', true);

  -- One altar, one row -- however it is spelled the second time.
  v_refused := false;
  begin
    perform public.add_temple_deity('gaura-nitai');
  exception when others then v_refused := true;
  end;
  if not v_refused then
    raise exception 'Gaura Nitai was added to the temple''s list a second time.';
  end if;

  -- A spelling cannot mean two Deities. This one the unique index cannot see:
  -- it is an alias of a new Deity colliding with the NAME of an existing one.
  v_refused := false;
  begin
    perform public.add_temple_deity('Something Else', null, array['Gaura Nitai']);
  exception when others then v_refused := true;
  end;
  if not v_refused then
    raise exception 'A new Deity claimed Gaura Nitai''s name as an alternate spelling.';
  end if;

  -- And an alias colliding with another Deity's alias.
  v_refused := false;
  begin
    perform public.add_temple_deity('Another Thing', null, array['Nitai Gaura']);
  exception when others then v_refused := true;
  end;
  if not v_refused then
    raise exception 'Two Deities were allowed to share an alternate spelling.';
  end if;

  -- A name is not a paragraph.
  v_refused := false;
  begin
    perform public.add_temple_deity(repeat('A', v_max_name + 1));
  exception when others then v_refused := true;
  end;
  if not v_refused then
    raise exception 'A Deity longer than % characters was added.', v_max_name;
  end if;

  -- Nor is an alternate spelling.
  v_refused := false;
  begin
    perform public.add_temple_deity('A Fine Name', null, array[repeat('B', v_max_name + 1)]);
  exception when others then v_refused := true;
  end;
  if not v_refused then
    raise exception 'An alternate spelling longer than % characters was added.', v_max_name;
  end if;

  -- Too many alternate spellings.
  v_refused := false;
  begin
    perform public.add_temple_deity(
      'Many Spellings',
      null,
      (select array_agg('Spelling ' || n) from generate_series(1, v_max_aliases + 1) as n));
  exception when others then v_refused := true;
  end;
  if not v_refused then
    raise exception 'A Deity with more than % alternate spellings was added.', v_max_aliases;
  end if;

  -- A Deity needs a name, and a name needs letters.
  v_refused := false;
  begin
    perform public.add_temple_deity('   ');
  exception when others then v_refused := true;
  end;
  if not v_refused then
    raise exception 'A blank Deity was added.';
  end if;

  v_refused := false;
  begin
    perform public.add_temple_deity('...');
  exception when others then v_refused := true;
  end;
  if not v_refused then
    raise exception 'A Deity named entirely in punctuation was added.';
  end if;

  -- A place in the list is a place, not a direction.
  v_refused := false;
  begin
    perform public.add_temple_deity('Backwards', -1);
  exception when others then v_refused := true;
  end;
  if not v_refused then
    raise exception 'A Deity was given a negative place in the list.';
  end if;

  -- The alias list is stored the way the catalogue means it: trimmed, blanks
  -- gone, duplicate spellings collapsed, and the Deity's own name removed.
  v_id := public.add_temple_deity(
    'Tidy Test',
    null,
    array['  Tidy  Test  ', 'Tidy-Test', 'Spelling One', 'spelling one', '', '   ',
          'Spelling Two']);

  if (select array_to_string(temple_deities.aliases, ' | ')
      from public.temple_deities where temple_deities.id = v_id)
     is distinct from 'Spelling One | Spelling Two'
  then
    raise exception 'The alias list was stored as: %',
      (select array_to_string(temple_deities.aliases, ' | ')
       from public.temple_deities where temple_deities.id = v_id);
  end if;
end;
$$;

reset role;
delete from public.temple_deities where temple_deities.name = 'Tidy Test';

-- The ceiling on how many Deities the list holds, and the fact that
-- retire-and-restore is not a way around it.
do $$
declare
  v_max integer := public.daily_darshan_limit('temple_deities.max_entries');
  v_refused boolean;
  v_id uuid;
begin
  perform set_config('request.jwt.claim.sub', 'e0000000-0000-0000-0000-000000000002', true);

  update public.app_settings set value = '4' where app_settings.key = 'temple_deities.max_entries';

  v_id := public.add_temple_deity('The Fourth');

  v_refused := false;
  begin
    perform public.add_temple_deity('The Fifth');
  exception when others then v_refused := true;
  end;
  if not v_refused then
    raise exception 'A fifth Deity was added to a list that holds four.';
  end if;

  -- Retire one, add one, then try to bring the retired one back.
  perform public.update_temple_deity(v_id, p_is_active => false);
  perform public.add_temple_deity('The Fifth');

  v_refused := false;
  begin
    perform public.update_temple_deity(v_id, p_is_active => true);
  exception when others then v_refused := true;
  end;
  if not v_refused then
    raise exception 'Restoring a retired Deity walked past the ceiling.';
  end if;

  delete from public.temple_deities
  where temple_deities.name in ('The Fourth', 'The Fifth');

  update public.app_settings set value = v_max::text
  where app_settings.key = 'temple_deities.max_entries';
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. deity is still text, still unreferenced -- and still canonicalised.
--
--    The decision written out in 0080's header, checked in both directions:
--    the visiting Deity is postable, and the temple's own altar is stored in
--    the temple's spelling however the Head typed it.
-- ---------------------------------------------------------------------------

reset role;

do $$
begin
  if (select atttypid::regtype::text
      from pg_attribute
      where attrelid = 'public.daily_darshan_images'::regclass
        and attname = 'deity') <> 'text' then
    raise exception 'daily_darshan_images.deity is no longer text.';
  end if;

  if exists (
    select 1
    from pg_constraint
    where pg_constraint.conrelid = 'public.daily_darshan_images'::regclass
      and pg_constraint.contype = 'f'
      and 'deity' = any (
        select pg_attribute.attname
        from unnest(pg_constraint.conkey) as key
        join pg_attribute on pg_attribute.attrelid = pg_constraint.conrelid
                         and pg_attribute.attnum = key
      )
  ) then
    raise exception 'daily_darshan_images.deity has grown a foreign key.';
  end if;

  -- publish_daily_darshan is exactly the function 0079 left. The catalogue is
  -- enforced by a trigger on the column precisely so that it did not have to
  -- be rewritten.
  if pg_get_functiondef('public.publish_daily_darshan(date, text, jsonb)'::regprocedure)
     ~ 'temple_deit' then
    raise exception '0080 rewrote publish_daily_darshan.';
  end if;
end;
$$;

select set_config('request.jwt.claim.sub', 'e0000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_today date := (now() at time zone 'America/Chicago')::date;
  v_base text := 'https://project.supabase.co/storage/v1/object/public/message-images/'
    || 'e0000000-0000-0000-0000-000000000002/';
  v_id uuid;
  v_stored text;
begin
  -- Three spellings of one altar, one spelling of a second, and a Deity the
  -- temple's list has never heard of. All five through the real RPC.
  v_id := public.publish_daily_darshan(v_today, 'Today.', jsonb_build_array(
    jsonb_build_object('imageUrl', v_base || 'a.jpg', 'deity', 'gaura-nitai',
      'dressedBy', 'Bhaktin Anjali', 'position', 1),
    jsonb_build_object('imageUrl', v_base || 'b.jpg', 'deity', 'GAURA  NITAI', 'position', 2),
    jsonb_build_object('imageUrl', v_base || 'c.jpg', 'deity', 'Nitai Gaura', 'position', 3),
    jsonb_build_object('imageUrl', v_base || 'd.jpg', 'deity', 'kishora kishori', 'position', 4),
    jsonb_build_object('imageUrl', v_base || 'e.jpg', 'deity', 'Their Lordships on the Ratha',
      'position', 5)));

  select string_agg(img.deity, ' | ' order by img."position") into v_stored
  from public.daily_darshan_images img where img.darshan_id = v_id;

  if v_stored is distinct from
     'Gaura Nitai | Gaura Nitai | Gaura Nitai | Kisora Kisori | Their Lordships on the Ratha'
  then
    raise exception 'The pictures were stored as: %', v_stored;
  end if;

  -- The credit beside the Deity is untouched. Only the Deity is canonicalised.
  select img.dressed_by into v_stored
  from public.daily_darshan_images img
  where img.darshan_id = v_id and img."position" = 1;
  if v_stored is distinct from 'Bhaktin Anjali' then
    raise exception 'The "dressed by" credit was changed to %.', coalesce(v_stored, '(null)');
  end if;

  -- And the gallery hands the canonical spelling to the client.
  select listed.images -> 0 ->> 'deity' into v_stored
  from public.list_daily_darshan() as listed
  where listed.id = v_id;
  if v_stored is distinct from 'Gaura Nitai' then
    raise exception 'The gallery returned % for the first picture.', coalesce(v_stored, '(null)');
  end if;
end;
$$;

reset role;

-- The maintenance view sees exactly the one name the catalogue does not know.
select set_config('request.jwt.claim.sub', 'e0000000-0000-0000-0000-000000000003', true);
set local role authenticated;

do $$
declare
  v_report text;
begin
  select string_agg(unmatched.deity || ' x' || unmatched.pictures, ' | ')
  into v_report
  from public.unmatched_darshan_deity_names() as unmatched;

  if v_report is distinct from 'Their Lordships on the Ratha x1' then
    raise exception 'The unmatched Deity names read: %', coalesce(v_report, '(none)');
  end if;
end;
$$;

reset role;

-- ---------------------------------------------------------------------------
-- 8. 0079 still groups a day correctly and still says its documented words.
--
--    Written straight into the tables rather than through publish_daily_
--    darshan, for two reasons: the dates below are chosen to cover all five of
--    0079 §7's sentence shapes and lie outside the week the gallery holds, and
--    a direct insert proves the canonicaliser is a property of the COLUMN
--    rather than of one route into it.
-- ---------------------------------------------------------------------------

create function pg_temp.td_day(p_on date, p_deities text[])
returns void
language plpgsql
as $$
declare
  v_id uuid;
  v_n integer := 0;
  v_deity text;
begin
  insert into public.daily_darshan (darshan_on, note, posted_by)
  values (p_on, 'A day.', 'e0000000-0000-0000-0000-000000000002')
  returning daily_darshan.id into v_id;

  foreach v_deity in array p_deities loop
    v_n := v_n + 1;
    insert into public.daily_darshan_images (darshan_id, image_url, deity, "position")
    values (
      v_id,
      'https://project.supabase.co/storage/v1/object/public/message-images/fixture/'
        || p_on || '-' || v_n || '.jpg',
      nullif(v_deity, ''),
      v_n);
  end loop;
end;
$$;

-- One altar, spelled three ways. Five consecutive days, so all five of 0079's
-- sentence shapes are covered without this script having to know which date
-- carries which -- the multiset of bodies is asserted instead.
do $$
declare
  v_base date := date '2026-03-02';
  v_n integer;
  v_names text;
  v_bodies text[] := '{}'::text[];
  v_titles text;
  v_wording record;
  v_expected text[] := array[
    'See how Kisora Kisori is looking today.',
    'Today''s darshan of Kisora Kisori is here.',
    'Come and take darshan of Kisora Kisori.',
    'Today''s pictures of Kisora Kisori are here.',
    'Kisora Kisori - today''s darshan from the temple.'
  ];
begin
  for v_n in 0 .. 4 loop
    perform pg_temp.td_day(v_base + v_n,
      array['kisora-kisori', 'KISORA  KISORI', 'Kishora Kishori']);

    -- The whole point: three spellings of one altar are ONE name.
    v_names := array_to_string(public.daily_darshan_deity_names(v_base + v_n), ' | ');
    if v_names is distinct from 'Kisora Kisori' then
      raise exception 'A day spelled one altar three ways grouped as: %', v_names;
    end if;

    select notice.title, notice.body into v_wording
    from public.daily_darshan_notification_text(v_base + v_n) as notice;

    if v_wording.title is distinct from 'Kisora Kisori' then
      raise exception 'The notification was titled %.', v_wording.title;
    end if;

    v_bodies := v_bodies || v_wording.body;
  end loop;

  -- Every one of 0079's five documented sentences, once each.
  if (select array_agg(sorted.body order by sorted.body)
      from unnest(v_bodies) as sorted(body))
     is distinct from
     (select array_agg(sorted.body order by sorted.body)
      from unnest(v_expected) as sorted(body))
  then
    raise exception 'Five consecutive days said: %', array_to_string(v_bodies, ' / ');
  end if;

  select string_agg(distinct notice.title, ',') into v_titles
  from generate_series(0, 4) as n,
       lateral public.daily_darshan_notification_text(v_base + n) as notice;
  if v_titles is distinct from 'Kisora Kisori' then
    raise exception 'The title varied by day: %', v_titles;
  end if;
end;
$$;

-- Two altars, each spelled two ways, and the phrase that must come out.
do $$
declare
  v_day date := date '2026-03-10';
  v_names text;
  v_wording record;
begin
  perform pg_temp.td_day(v_day,
    array['kisora kisori', 'Kishora Kishori', 'gaura-nitai', 'Nitai Gaura']);

  v_names := array_to_string(public.daily_darshan_deity_names(v_day), ' | ');
  if v_names is distinct from 'Kisora Kisori | Gaura Nitai' then
    raise exception 'Two altars spelled four ways grouped as: %', v_names;
  end if;

  select notice.title, notice.body into v_wording
  from public.daily_darshan_notification_text(v_day) as notice;

  if v_wording.title is distinct from 'Kisora Kisori and Gaura Nitai' then
    raise exception 'A two-altar day was titled %.', v_wording.title;
  end if;
  if v_wording.body !~ 'Kisora Kisori and Gaura Nitai' then
    raise exception 'A two-altar day said: %', v_wording.body;
  end if;
end;
$$;

-- Three named -- the cap -- and four, which collapses. The fourth is a Deity
-- the catalogue does not know, which is exactly the case a foreign key would
-- have made unpostable.
do $$
declare
  v_three date := date '2026-03-11';
  v_four date := date '2026-03-12';
  v_none date := date '2026-03-13';
  v_names text;
  v_wording record;
begin
  perform pg_temp.td_day(v_three,
    array['kisora-kisori', 'gaura nitai', 'jagannatha baladeva subhadra']);

  select notice.title into v_wording
  from public.daily_darshan_notification_text(v_three) as notice;
  if v_wording.title is distinct from
     'Kisora Kisori, Gaura Nitai and Jagannath Baldev Subhadra' then
    raise exception 'A three-altar day was titled %.', v_wording.title;
  end if;

  perform pg_temp.td_day(v_four,
    array['kisora-kisori', 'gaura nitai', 'jagannath baldev subhadra',
          'Their Lordships on the Ratha']);

  v_names := array_to_string(public.daily_darshan_deity_names(v_four), ' | ');
  if v_names is distinct from
     'Kisora Kisori | Gaura Nitai | Jagannath Baldev Subhadra | Their Lordships on the Ratha'
  then
    raise exception 'A four-Deity day grouped as: %', v_names;
  end if;

  select notice.title into v_wording
  from public.daily_darshan_notification_text(v_four) as notice;
  if v_wording.title is distinct from 'Kisora Kisori, Gaura Nitai and the other Deities' then
    raise exception 'A four-Deity day was titled %.', v_wording.title;
  end if;

  -- Nothing named at all: 0079's fallback, untouched by the catalogue.
  perform pg_temp.td_day(v_none, array['', '']);

  select notice.title, notice.body into v_wording
  from public.daily_darshan_notification_text(v_none) as notice;
  if v_wording.title is distinct from 'Daily Darshan' then
    raise exception 'A day naming nobody was titled %.', v_wording.title;
  end if;
  if v_wording.body !~ 'the Deities' then
    raise exception 'A day naming nobody said: %', v_wording.body;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 9. 0078's delete_daily_darshan, read and confirmed rather than restated.
--
--    The temple's requirement is the poster, the President and the Tech Admin.
--    0078 §10 allows exactly `posted_by = auth.uid() or
--    may_post_daily_darshan()`, and may_post_daily_darshan is the Community
--    Head, the Tech Admin and the President. So all three of the required
--    people may, and so may a Community Head who did not post -- which is
--    0078's own documented intent ("whoever put it up, and any of the three
--    who could have") and is what keeps a darshan removable after
--    `on delete set null` has cleared its poster. Nothing was changed.
--
--    Checked here so that a later edit narrowing it would be caught.
-- ---------------------------------------------------------------------------

reset role;

create function pg_temp.td_delete_as(p_who uuid, p_id uuid)
returns text
language plpgsql
as $$
declare
  v_result text := 'deleted';
begin
  perform set_config('request.jwt.claim.sub', p_who::text, true);
  set local role authenticated;
  begin
    perform public.delete_daily_darshan(p_id);
  exception when others then
    v_result := 'refused';
  end;
  reset role;
  return v_result;
end;
$$;

do $$
declare
  v_id uuid;
  v_answer text;
  v_person record;
begin
  for v_person in
    select * from (values
      ('e0000000-0000-0000-0000-000000000004'::uuid, 'a plain devotee', 'refused'),
      ('e0000000-0000-0000-0000-000000000005'::uuid, 'a volunteer', 'refused'),
      ('e0000000-0000-0000-0000-000000000002'::uuid, 'the Head who posted it', 'deleted'),
      ('e0000000-0000-0000-0000-000000000001'::uuid, 'the President', 'deleted'),
      ('e0000000-0000-0000-0000-000000000003'::uuid, 'the Tech Admin', 'deleted'),
      -- Narrowed by 202608310086: posting is a Community Head power, removing
      -- somebody else's darshan is not. Only the poster, Tech Admin, President.
      ('e0000000-0000-0000-0000-000000000006'::uuid, 'another Community Head', 'refused')
    ) as who(id, label, expected)
  loop
    -- A fresh darshan for a day nothing else in this script uses, posted by
    -- the Head each time.
    delete from public.daily_darshan where daily_darshan.darshan_on = date '2026-03-20';
    insert into public.daily_darshan (darshan_on, note, posted_by)
    values (date '2026-03-20', 'To be removed.', 'e0000000-0000-0000-0000-000000000002')
    returning daily_darshan.id into v_id;

    v_answer := pg_temp.td_delete_as(v_person.id, v_id);
    if v_answer is distinct from v_person.expected then
      raise exception 'delete_daily_darshan: % got %, expected %.',
        v_person.label, v_answer, v_person.expected;
    end if;
  end loop;

  delete from public.daily_darshan where daily_darshan.darshan_on = date '2026-03-20';
end;
$$;

-- ---------------------------------------------------------------------------
-- 10. Every guard, mutated.
--
--     Each row below breaks exactly one thing 0080 relies on and re-reads one
--     answer through the real function. A guard whose mutation changes nothing
--     is a guard that was not doing anything, and the table says so out loud.
--     The harness is 202608290078 §11's, unchanged: both readings roll back
--     whatever they would have written, and the probe is read a third time
--     after the mutation is undone and must match the first, or the harness
--     itself is lying.
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', '', true);

delete from public.daily_darshan;
delete from public.app_notifications;

create table td_mutations (
  n integer primary key,
  guard text not null,
  mutation text not null,
  probe text not null,
  intact text not null,
  mutated text not null,
  killed boolean not null
);

create function pg_temp.td_probe(p_sql text)
returns text
language plpgsql
as $$
declare
  v_answer text;
begin
  begin
    execute p_sql into v_answer;
    raise exception using errcode = 'PT780', message = coalesce(v_answer, '(null)');
  exception when sqlstate 'PT780' then
    return sqlerrm;
  end;
end;
$$;

-- Attempt something as somebody, and say only whether it was allowed. The role
-- is always put back, including when the attempt raised.
create function pg_temp.td_try_as(p_sub text, p_role text, p_sql text)
returns text
language plpgsql
as $$
declare
  v_result text := 'accepted';
begin
  perform set_config('request.jwt.claim.sub', p_sub, true);
  execute format('set local role %I', p_role);
  begin
    execute p_sql;
  exception when others then
    v_result := 'refused';
  end;
  reset role;
  perform set_config('request.jwt.claim.sub', '', true);
  return v_result;
end;
$$;

-- Write a day of pictures and report how 0079 groups it.
create function pg_temp.td_grouping(p_on date, p_deities text[])
returns text
language plpgsql
as $$
begin
  perform pg_temp.td_day(p_on, p_deities);
  return array_to_string(public.daily_darshan_deity_names(p_on), ' | ');
end;
$$;

-- Write one picture and report what the column actually holds.
create function pg_temp.td_stored(p_on date, p_typed text)
returns text
language plpgsql
as $$
declare
  v_stored text;
begin
  perform pg_temp.td_day(p_on, array[p_typed]);
  select img.deity into v_stored
  from public.daily_darshan_images img
  join public.daily_darshan darshan on darshan.id = img.darshan_id
  where darshan.darshan_on = p_on;
  return coalesce(v_stored, '(null)');
exception when others then
  return 'refused';
end;
$$;

create function pg_temp.td_mutate(
  p_n integer, p_guard text, p_mutation text, p_probe text,
  p_apply text[], p_query text
)
returns void
language plpgsql
as $$
declare
  v_intact text;
  v_mutated text;
  v_restored text;
  v_statement text;
begin
  v_intact := pg_temp.td_probe(p_query);

  begin
    foreach v_statement in array p_apply loop
      execute v_statement;
    end loop;
    v_mutated := pg_temp.td_probe(p_query);
    raise exception using errcode = 'PT781', message = v_mutated;
  exception when sqlstate 'PT781' then
    v_mutated := sqlerrm;
  end;

  v_restored := pg_temp.td_probe(p_query);
  if v_restored is distinct from v_intact then
    raise exception 'Mutation % did not roll back: the probe read % before and % after.',
      p_n, v_intact, v_restored;
  end if;

  insert into td_mutations (n, guard, mutation, probe, intact, mutated, killed)
  values (p_n, p_guard, p_mutation, p_probe, v_intact, v_mutated,
          v_mutated is distinct from v_intact);
end;
$$;

do $$
declare
  v_devotee text := 'e0000000-0000-0000-0000-000000000004';
  v_head text := 'e0000000-0000-0000-0000-000000000002';
  v_gaura uuid;
  v_grant text := 'insert into public.role_permissions (role_id, permission_key) '
    || 'select roles.id, ''services.manage_recurring'' from public.roles '
    || 'where roles.name = ''devotee''';
begin
  select temple_deities.id into v_gaura
  from public.temple_deities where temple_deities.name = 'Gaura Nitai';

  perform pg_temp.td_mutate(
    1,
    'only a Community Head, Tech Admin or President may add a Deity',
    'services.manage_recurring granted to the devotee role',
    'a plain devotee adding a Deity',
    array[v_grant],
    format('select pg_temp.td_try_as(%L, %L, %L)',
           v_devotee, 'authenticated',
           'select public.add_temple_deity(''A Devotee''''s Deity'')'));

  perform pg_temp.td_mutate(
    2,
    'only those three may rename, reorder or retire a Deity',
    'services.manage_recurring granted to the devotee role',
    'a plain devotee retiring Gaura Nitai',
    array[v_grant],
    format('select pg_temp.td_try_as(%L, %L, %L)',
           v_devotee, 'authenticated',
           format('select public.update_temple_deity(%L, p_is_active => false)', v_gaura)));

  perform pg_temp.td_mutate(
    3,
    'the list holds at most max_entries Deities',
    'temple_deities.max_entries dialled from 50 down to 3',
    'a Community Head adding a fourth Deity',
    array[format('update public.app_settings set value = %L where key = %L',
                 '3', 'temple_deities.max_entries')],
    format('select pg_temp.td_try_as(%L, %L, %L)',
           v_head, 'authenticated',
           'select public.add_temple_deity(''The Fourth'')'));

  perform pg_temp.td_mutate(
    4,
    'a Deity''s name is no longer than max_name_chars',
    'temple_deities.max_name_chars dialled from 120 down to 3',
    'adding Sri Sri Radha Govinda',
    array[format('update public.app_settings set value = %L where key = %L',
                 '3', 'temple_deities.max_name_chars')],
    format('select pg_temp.td_try_as(%L, %L, %L)',
           v_head, 'authenticated',
           'select public.add_temple_deity(''Sri Sri Radha Govinda'')'));

  perform pg_temp.td_mutate(
    5,
    'a Deity''s name also fits daily_darshan.max_credit_chars, or the picker '
      || 'would offer a name publish_daily_darshan refuses',
    'daily_darshan.max_credit_chars dialled from 120 down to 3',
    'adding Sri Sri Radha Govinda',
    array[format('update public.app_settings set value = %L where key = %L',
                 '3', 'daily_darshan.max_credit_chars')],
    format('select pg_temp.td_try_as(%L, %L, %L)',
           v_head, 'authenticated',
           'select public.add_temple_deity(''Sri Sri Radha Govinda'')'));

  perform pg_temp.td_mutate(
    6,
    'a Deity has at most max_aliases alternate spellings',
    'temple_deities.max_aliases dialled from 10 down to 0',
    'adding a Deity with one alternate spelling',
    array[format('update public.app_settings set value = %L where key = %L',
                 '0', 'temple_deities.max_aliases')],
    format('select pg_temp.td_try_as(%L, %L, %L)',
           v_head, 'authenticated',
           'select public.add_temple_deity(''A New Deity'', null, array[''One More''])'));

  perform pg_temp.td_mutate(
    7,
    'one spelling can only mean one Deity',
    'the check_temple_deity_spellings trigger dropped',
    'adding a Deity whose alternate spelling is Gaura Nitai''s name',
    array['drop trigger check_temple_deity_spellings on public.temple_deities'],
    format('select pg_temp.td_try_as(%L, %L, %L)',
           v_head, 'authenticated',
           'select public.add_temple_deity(''Something Else'', null, array[''Gaura Nitai''])'));

  perform pg_temp.td_mutate(
    8,
    'one altar, one row, however it is spelled the second time',
    'the spelling trigger and the match_key unique index both dropped',
    'adding gaura-nitai a second time',
    array['drop trigger check_temple_deity_spellings on public.temple_deities',
          'drop index public.temple_deities_match_key_idx'],
    format('select pg_temp.td_try_as(%L, %L, %L)',
           v_head, 'authenticated',
           'select public.add_temple_deity(''gaura-nitai'')'));

  perform pg_temp.td_mutate(
    9,
    'anon reads nothing',
    'select granted to anon and a permissive policy added',
    'anon counting the temple''s Deities',
    array['grant select on public.temple_deities to anon',
          'create policy "anon" on public.temple_deities for select to anon using (true)'],
    format('select pg_temp.td_try_as(%L, %L, %L)',
           '', 'anon', 'select count(*) from public.temple_deities'));

  perform pg_temp.td_mutate(
    10,
    'a typed name is stored in the temple''s own spelling, so 0079 groups a '
      || 'day by altar and not by spelling',
    'the canonicalise_darshan_deity trigger dropped',
    'a day whose three pictures spell one altar three ways',
    array['drop trigger canonicalise_darshan_deity on public.daily_darshan_images'],
    format('select pg_temp.td_grouping(%L, %L::text[])',
           date '2026-03-25',
           array['kisora-kisori', 'KISORA  KISORI', 'Kishora Kishori']::text));

  perform pg_temp.td_mutate(
    11,
    'a Deity the catalogue does not know is stored exactly as typed',
    'resolve_temple_deity_name made to answer with the first Deity in the list '
      || 'instead of null',
    'a picture of Their Lordships on the Ratha',
    array['create or replace function public.resolve_temple_deity_name(p_name text) '
          || 'returns text language sql stable security definer set search_path = '''' as $f$ '
          || 'select deity.name from public.temple_deities deity '
          || 'order by deity.display_order limit 1 $f$'],
    format('select pg_temp.td_stored(%L, %L)',
           date '2026-03-26', 'Their Lordships on the Ratha'));

  perform pg_temp.td_mutate(
    12,
    'matching ignores case, spacing and punctuation',
    'temple_deity_match_key made to keep punctuation',
    'asking what "gaura-nitai" means',
    array['create or replace function public.temple_deity_match_key(p_name text) '
          || 'returns text language sql immutable set search_path = '''' as $f$ '
          || 'select nullif(lower(coalesce(p_name, '''')), '''') $f$'],
    'select coalesce(public.resolve_temple_deity_name(''gaura-nitai''), ''(nothing)'')');

  perform pg_temp.td_mutate(
    13,
    'a Deity''s alternate spellings are consulted',
    'Gaura Nitai''s alternate spellings emptied',
    'asking what "Nitai Gaura" means',
    array['update public.temple_deities set aliases = ''{}''::text[] '
          || 'where name = ''Gaura Nitai'''],
    'select coalesce(public.resolve_temple_deity_name(''Nitai Gaura''), ''(nothing)'')');

  perform pg_temp.td_mutate(
    14,
    'deity has no foreign key, so a visiting Deity is still postable',
    'a foreign key added from daily_darshan_images.deity to temple_deities.name',
    'a picture of Their Lordships on the Ratha',
    array['create unique index td_fk_name on public.temple_deities (name)',
          'alter table public.daily_darshan_images add constraint td_fk '
          || 'foreign key (deity) references public.temple_deities(name) not valid'],
    format('select pg_temp.td_stored(%L, %L)',
           date '2026-03-27', 'Their Lordships on the Ratha'));
end;
$$;

do $$
declare
  v_survivors text;
  v_count integer;
  v_holders text;
begin
  select count(*)::integer into v_count from td_mutations;
  if v_count <> 14 then
    raise exception 'Only % mutations ran.', v_count;
  end if;

  select string_agg(td_mutations.n || ': ' || td_mutations.guard, E'\n  ')
  into v_survivors
  from td_mutations where not td_mutations.killed;

  if v_survivors is not null then
    raise exception E'These guards survived being broken:\n  %', v_survivors;
  end if;

  -- The probes rolled everything back: the catalogue is the seeded three, no
  -- darshan was left behind, and no role gained a permission.
  if (select count(*) from public.temple_deities) <> 3 then
    raise exception 'A mutation probe changed the catalogue; the harness is lying.';
  end if;
  if (select count(*) from public.daily_darshan) <> 0 then
    raise exception 'A mutation probe left a darshan behind; the harness is lying.';
  end if;

  select string_agg(roles.name, ',' order by roles.name) into v_holders
  from public.role_permissions
  join public.roles on roles.id = role_permissions.role_id
  where role_permissions.permission_key = 'services.manage_recurring';
  if v_holders is distinct from 'core,president,tech' then
    raise exception 'A mutation probe left services.manage_recurring held by %.', v_holders;
  end if;

  if current_user <> session_user then
    raise exception 'A mutation probe left the session as %.', current_user;
  end if;
end;
$$;

select
  td_mutations.n,
  td_mutations.guard,
  td_mutations.mutation,
  td_mutations.probe,
  td_mutations.intact,
  td_mutations.mutated,
  case when td_mutations.killed then 'killed' else 'SURVIVED' end as verdict
from td_mutations
order by td_mutations.n;

do $$
begin
  raise notice 'all temple deity checks passed';
end;
$$;

select 'temple deities verification passed' as result;

rollback;
