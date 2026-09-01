-- Six functions still carried PUBLIC execute, so PostgREST advertised them at
-- /rest/v1/rpc/… to callers holding nothing but the anon key.
--
-- Five are trigger functions and one is an event trigger, and Postgres refuses
-- to call those directly — "trigger functions can only be called as triggers" —
-- so none of them was reachable in practice. service_session_name is a real
-- function though, and PUBLIC could execute it.
--
-- The exposure it had was small: it takes a whole service_qr_sessions row as
-- its argument, so a caller had to already hold the row to learn the name of
-- the seva on it. Small is not the same as intended. Every other function in
-- this schema states who may run it; these six were only ever missed.
--
-- Nothing in the app calls any of them by name. They run where they always
-- ran: as triggers, under the definer rights the trigger already has.

-- Guarded one by one: rls_auto_enable is the platform's, not ours, and is
-- absent from a database built from these migrations alone. A revoke that
-- assumed it would fail the whole run locally while doing nothing hosted.
do $$
declare
  v_signature text;
begin
  foreach v_signature in array array[
    'public.announce_devotee_award()',
    'public.create_profile_for_new_auth_user()',
    'public.enforce_campaign_tiers_agree()',
    'public.enforce_sponsorship_booking_date()',
    'public.rls_auto_enable()',
    'public.service_session_name(public.service_qr_sessions)'
  ]
  loop
    if to_regprocedure(v_signature) is not null then
      execute format('revoke all on function %s from public, anon', v_signature);
    end if;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- Proof, run at migration time.
-- ---------------------------------------------------------------------------
do $$
declare
  v_name text;
  v_left text;
begin
  for v_name in
    select unnest(array[
      'announce_devotee_award',
      'create_profile_for_new_auth_user',
      'enforce_campaign_tiers_agree',
      'enforce_sponsorship_booking_date',
      'rls_auto_enable',
      'service_session_name'
    ])
  loop
    -- An empty grantee is PUBLIC, which is the one this migration exists to
    -- remove. anon is named explicitly for the same reason.
    select string_agg(acl.grantee::regrole::text, ', ')
    into v_left
    from pg_proc procs
    join pg_namespace spaces on spaces.oid = procs.pronamespace
    cross join lateral aclexplode(procs.proacl) acl
    where spaces.nspname = 'public'
      and procs.proname = v_name
      and acl.privilege_type = 'EXECUTE'
      and (acl.grantee = 0 or acl.grantee = 'anon'::regrole);

    if v_left is not null then
      raise exception '% can still be executed by %', v_name, v_left;
    end if;

  end loop;

  -- And the functions are still there to be fired as triggers.
  if not exists (
    select 1 from pg_proc procs
    join pg_namespace spaces on spaces.oid = procs.pronamespace
    where spaces.nspname = 'public'
      and procs.proname = 'create_profile_for_new_auth_user'
  ) then
    raise exception 'the new-account trigger function was removed, not revoked';
  end if;

  raise notice 'nothing in public runs for a caller who has not signed in';
end;
$$;
