-- Clash warnings inform. They never block.
-- Requires 202608040069_schedule_and_clashes.sql.
--
-- The temple's rule is explicit: a devotee who is already booked may still
-- take a second seva that overlaps it — "only accept if you manage to serve".
-- The warning exists so the choice is made knowingly, not so the app can
-- refuse on the devotee's behalf.
--
-- 202608040019 section 5 added an exclusion constraint under the heading "One
-- devotee cannot be in two places at once". That was a fair reading at the
-- time, but it predates public.list_seva_clashes (0069), which is now the
-- thing that surfaces an overlap, and it contradicts the rule above: it
-- refuses the temple's own worked example, a devotee serving in the kitchen
-- 12:00-13:30 and with flowers 13:15-14:30. The database, not the UI, was
-- having the final say, and it was saying no.
--
-- What still holds after this:
--   * public.list_seva_clashes keeps reporting the overlap, and the app keeps
--     showing it. Nothing about the warning changes.
--   * one_pending_service_verification_per_devotee (0012) still allows only
--     one open request at a time.
--   * The exact-duplicate guard below still refuses the same seva registered
--     twice, which is a mistake rather than a choice.

alter table public.service_verifications
  drop constraint if exists service_verification_no_overlap;

-- Overlap is allowed; registering the identical window twice is not. This is
-- the guard 0019 replaced, restored, and it is deliberately exact-match: a
-- window shifted by a minute is a different commitment and is the devotee's to
-- make.
create unique index if not exists service_verification_no_exact_duplicate
  on public.service_verifications (devotee_id, start_at, end_at)
  where status <> 'declined';

-- ---------------------------------------------------------------------------
-- Proof, run at migration time.
-- ---------------------------------------------------------------------------
do $$
declare
  -- Seeded here rather than borrowed from public.users. Reading an existing
  -- devotee meant this proof silently early-returned on every database that
  -- has none — which is every local and CI one — so it passed locally while
  -- being wrong, and only failed when it first met a real congregation.
  v_devotee uuid := '6f000000-0000-0000-0000-000000000001';
  v_type uuid;
  v_blocked boolean := false;
  v_rows integer;
begin
  if exists (
    select 1
    from pg_constraint
    where conname = 'service_verification_no_overlap'
      and conrelid = 'public.service_verifications'::regclass
  ) then
    raise exception 'service_verification_no_overlap survived the drop';
  end if;

  insert into auth.users (id, email, raw_user_meta_data)
  values (v_devotee, 'clash-proof@example.test',
          jsonb_build_object('name', 'Clash Proof Devotee'));

  insert into public.service_types (name, category)
  values ('Clash Proof Seva', 'other')
  returning id into v_type;

  -- The temple's worked example, attempted for real: kitchen 12:00-13:30 and
  -- flowers 13:15-14:30, overlapping by a quarter of an hour.
  --
  -- 'verified' rather than 'pending' so the one-open-request index (0012) is
  -- not what refuses the second row, and responded_at set because
  -- service_verification_review_consistency requires it of anything that is
  -- no longer pending.
  begin
    insert into public.service_verifications
      (devotee_id, verifier_id, service_type_id, start_at, end_at,
       status, responded_at)
    values
      (v_devotee, v_devotee, v_type,
       timestamptz '2099-01-01 12:00+00', timestamptz '2099-01-01 13:30+00',
       'verified', now()),
      (v_devotee, v_devotee, v_type,
       timestamptz '2099-01-01 13:15+00', timestamptz '2099-01-01 14:30+00',
       'verified', now());
  exception
    when exclusion_violation or unique_violation then
      v_blocked := true;
  end;

  select count(*)::integer into v_rows
  from public.service_verifications
  where devotee_id = v_devotee;

  delete from public.service_verifications where devotee_id = v_devotee;
  delete from public.service_types where id = v_type;
  delete from auth.users where id = v_devotee;

  if v_blocked then
    raise exception 'overlapping seva is still refused; the warning is still a block';
  end if;
  if v_rows <> 2 then
    raise exception
      'both overlapping registrations should have been stored, found %', v_rows;
  end if;

  raise notice 'overlapping seva accepted; clashes warn and do not block';
end;
$$;
