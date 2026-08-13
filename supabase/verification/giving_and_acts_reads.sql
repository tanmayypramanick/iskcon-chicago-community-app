-- Functional verification for 202608040061_giving_and_acts_reads.sql.
--
-- Rolled back at the end. Every local is prefixed v_ so it can never shadow a
-- column name. Anything that must be refused is attempted as the devotee who
-- would really attempt it, under `set local role authenticated`, so the
-- permission checks and the function grants are what is being tested rather
-- than superuser rights waving everything through.
--
-- ---------------------------------------------------------------------------
-- The fixture is five bookings and five gifts, and each one is a sentence.
--
-- ASHA holds one booking in each of the five states a booking can be in, and
-- the fifth is the one this migration exists for:
--
--   confirmed     Garland, +30 days.  A gift. Shown always.
--   live hold     Rajbhog, +31 days.  Held until half an hour from now. Shown
--                                     always, and shown as 'held'.
--   EXPIRED HOLD  Mangal Aarti, +32.  status = 'held' in the table, held_until
--                                     one minute in the past, and NO SWEEP HAS
--                                     RUN. The stored row still says 'held'
--                                     and section 4 proves it still does after
--                                     every read below. It must read as
--                                     'released' anyway, because
--                                     sponsorship_availability has already
--                                     given that date away.
--   released      Breakfast, +33.     Given back by hand. Hidden by default.
--   cancelled     Sandhya Bhog, +34.  Hidden by default.
--
-- And the gifts, which are the other half of the claim:
--
--   $351.00 USD  attached to the confirmed booking
--   $125.00 USD  attached to the RELEASED booking     <- must still be counted
--   $108.00 USD  attached to the EXPIRED HOLD         <- must still be counted,
--                                                        and must report its
--                                                        booking as 'released'
--    $99.00 CAD  no booking at all                    <- must never be added
--                                                        to a USD figure
--   $50.00 USD   Bimal's, so the donor filter has something to leave out
--
-- Every total in this file is checked against numbers written out by hand
-- rather than against a second query, because a total verified by re-running
-- the same sum is a total that agrees with itself and with nothing else.
--
-- The cast:
--   prez   ...0001  President. app.view_all.
--   head   ...0002  Community Head — the `core` role. services.manage_recurring
--                   and NOT app.view_all. Sees nothing here, and that is the
--                   point: this is the role that is nearly an admin.
--   asha   ...0003  a devotee. Five bookings, four gifts, two acts of seva.
--   bimal  ...0004  a devotee. One gift, one act. He exists so that "only your
--                   own" and "only that donor's" have something to exclude.
--
-- The final row must read: giving and acts reads verification passed

begin;

-- ---------------------------------------------------------------------------
-- 0. The shape of the thing, before any of its behaviour.
--
--    One of each. A leftover overload with a defaulted argument does not fail
--    loudly, it makes the call ambiguous, and that is how this repo has broken
--    before — so the count is asserted rather than assumed.
-- ---------------------------------------------------------------------------

do $$
declare
  v_name text;
  v_overloads integer;
  v_proc record;
begin
  if to_regprocedure('public.sponsorship_effective_status(text, timestamptz)') is null
    or to_regprocedure('public.list_my_sponsorships(boolean)') is null
    or to_regprocedure('public.list_all_sponsorships(boolean)') is null
    or to_regprocedure('public.list_devotee_seva_acts(uuid, date, date)') is null
    or to_regprocedure('public.list_all_donations(date, date, uuid)') is null
    or to_regprocedure('public.donation_totals(date, date, uuid)') is null
    or to_regprocedure('public.my_donation_totals()') is null
  then
    raise exception 'The giving and acts read functions are not all present.';
  end if;

  foreach v_name in array array[
    'sponsorship_effective_status', 'list_my_sponsorships', 'list_all_sponsorships',
    'list_devotee_seva_acts', 'list_all_donations', 'donation_totals',
    'my_donation_totals', 'my_seva_acts'
  ] loop
    select count(*)::integer into v_overloads
    from pg_proc
    join pg_namespace on pg_namespace.oid = pg_proc.pronamespace
    where pg_namespace.nspname = 'public' and pg_proc.proname = v_name;
    if v_overloads <> 1 then
      raise exception 'public.% has % overloads rather than 1.', v_name, v_overloads;
    end if;
  end loop;

  -- The old two-argument list_all_donations must be gone, not shadowed.
  if to_regprocedure('public.list_all_donations(date, date)') is not null then
    raise exception 'The two-argument list_all_donations survived the drop.';
  end if;
  if to_regprocedure('public.list_my_sponsorships()') is not null
    or to_regprocedure('public.list_all_sponsorships()') is not null then
    raise exception 'A no-argument sponsorship list survived the drop.';
  end if;

  -- Nothing here may write. These back screens; the day one of them acts is
  -- the day a read became a side effect.
  for v_proc in
    select pg_proc.proname, pg_proc.prosecdef, pg_proc.provolatile,
           pg_get_functiondef(pg_proc.oid) as body
    from pg_proc
    join pg_namespace on pg_namespace.oid = pg_proc.pronamespace
    where pg_namespace.nspname = 'public'
      and pg_proc.proname in (
        'sponsorship_effective_status', 'list_my_sponsorships', 'list_all_sponsorships',
        'list_devotee_seva_acts', 'list_all_donations', 'donation_totals',
        'my_donation_totals'
      )
  loop
    if v_proc.provolatile = 'v' then
      raise exception '%: volatile, so it has been given permission to write.', v_proc.proname;
    end if;
    if position('search_path=''''' in v_proc.body) = 0
       and position('search_path TO ''''' in v_proc.body) = 0 then
      raise exception '%: no empty search_path.', v_proc.proname;
    end if;
    foreach v_name in array array['insert into', 'update public', 'delete from'] loop
      if position(v_name in lower(v_proc.body)) > 0 then
        raise exception '%: contains "%". These are reads.', v_proc.proname, v_name;
      end if;
    end loop;
    -- Everything that reaches a table must be definer, because the tables are
    -- unreadable by `authenticated` and the guard is in the function.
    if v_proc.proname <> 'sponsorship_effective_status' and not v_proc.prosecdef then
      raise exception '%: not security definer, so it cannot see the rows it filters.',
        v_proc.proname;
    end if;
  end loop;

  -- The projection lives in one place. If either list has grown a case
  -- expression of its own, the two can drift, which is the bug.
  for v_proc in
    select pg_proc.proname, pg_get_functiondef(pg_proc.oid) as body
    from pg_proc
    join pg_namespace on pg_namespace.oid = pg_proc.pronamespace
    where pg_namespace.nspname = 'public'
      and pg_proc.proname in (
        'list_my_sponsorships', 'list_all_sponsorships', 'list_all_donations')
  loop
    if position('sponsorship_effective_status' in v_proc.body) = 0 then
      raise exception
        '% does not go through sponsorship_effective_status, so it can disagree with the others.',
        v_proc.proname;
    end if;
  end loop;

  -- donation_totals must not know sponsorship_bookings exists. A predicate it
  -- cannot express is a predicate nobody can get wrong.
  if position('sponsorship_bookings' in
              lower(pg_get_functiondef('public.donation_totals(date, date, uuid)'::regprocedure)))
     > 0 then
    raise exception
      'donation_totals joins sponsorship_bookings, so a released date can now cancel a gift.';
  end if;
  if position('sponsorship_bookings' in
              lower(pg_get_functiondef('public.my_donation_totals()'::regprocedure))) > 0 then
    raise exception 'my_donation_totals joins sponsorship_bookings.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 1. list_devotee_seva_acts returns exactly what my_seva_acts returns.
--
--    Column for column, name for name, type for type, in order. Not "the same
--    fields" — the same list, so the one client component that renders a
--    devotee's own history renders somebody else's with no second row type and
--    no mapping in between.
-- ---------------------------------------------------------------------------

do $$
declare
  v_mine text;
  v_theirs text;
begin
  with columns as (
    select
      pg_proc.proname,
      subs.ord,
      pg_proc.proargnames[subs.ord] as column_name,
      format_type(pg_proc.proallargtypes[subs.ord], null) as column_type
    from pg_proc
    join pg_namespace on pg_namespace.oid = pg_proc.pronamespace,
    lateral generate_subscripts(pg_proc.proallargtypes, 1) as subs(ord)
    where pg_namespace.nspname = 'public'
      and pg_proc.proname in ('my_seva_acts', 'list_devotee_seva_acts')
      and pg_proc.proargmodes[subs.ord] = 't'
  )
  select
    string_agg(columns.column_name || ' ' || columns.column_type, ', ' order by columns.ord)
      filter (where columns.proname = 'my_seva_acts'),
    string_agg(columns.column_name || ' ' || columns.column_type, ', ' order by columns.ord)
      filter (where columns.proname = 'list_devotee_seva_acts')
  into v_mine, v_theirs
  from columns;

  if v_mine is null or v_mine = '' then
    raise exception 'my_seva_acts declares no output columns, so nothing was compared.';
  end if;
  if v_mine is distinct from v_theirs then
    raise exception
      'list_devotee_seva_acts returns a different shape. my_seva_acts is [%] and it is [%].',
      v_mine, coalesce(v_theirs, 'nothing');
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. The people.
-- ---------------------------------------------------------------------------

insert into auth.users (id, email, raw_user_meta_data) values
  ('90000000-0000-0000-0000-000000000001', 'gr-prez@example.test', '{"name":"Gr President"}'),
  ('90000000-0000-0000-0000-000000000002', 'gr-head@example.test', '{"name":"Gr Head"}'),
  ('90000000-0000-0000-0000-000000000003', 'gr-asha@example.test', '{"name":"Gr Asha"}'),
  ('90000000-0000-0000-0000-000000000004', 'gr-bimal@example.test', '{"name":"Gr Bimal"}');

update public.users
set role_id = (select roles.id from public.roles where roles.name = 'president')
where users.email = 'gr-prez@example.test';

update public.users
set role_id = (select roles.id from public.roles where roles.name = 'core')
where users.email = 'gr-head@example.test';

-- The Community Head must really be one, and must really not be an admin.
do $$
begin
  if not exists (
    select 1
    from public.users
    join public.role_permissions on role_permissions.role_id = users.role_id
    where users.email = 'gr-head@example.test'
      and role_permissions.permission_key = 'services.manage_recurring'
  ) then
    raise exception 'The Community Head in this fixture is not a Community Head.';
  end if;
  if exists (
    select 1
    from public.users
    join public.role_permissions on role_permissions.role_id = users.role_id
    where users.email = 'gr-head@example.test'
      and role_permissions.permission_key = 'app.view_all'
  ) then
    raise exception 'The Community Head in this fixture holds app.view_all.';
  end if;
end;
$$;

-- Ordinary table rather than a temporary one, so reading it under the
-- authenticated role needs no assumptions about the temp schema. The whole
-- script is rolled back, so it never outlives the transaction.
create table public.gr_ids (key text primary key, id uuid not null);
grant select on public.gr_ids to authenticated;

-- Two holding tables, so a thing read under one devotee's session can be
-- compared with a thing read under another's. Created empty by the owner and
-- filled by the devotee, so every read being compared happened under
-- `authenticated` and not under superuser rights.
create table public.gr_asha_own_acts as
  select * from public.my_seva_acts() with no data;
grant select, insert on public.gr_asha_own_acts to authenticated;

create table public.gr_asha_own_sponsorships as
  select * from public.list_my_sponsorships(true) with no data;
grant select, insert on public.gr_asha_own_sponsorships to authenticated;

insert into public.gr_ids (key, id) values
  ('prez',  '90000000-0000-0000-0000-000000000001'),
  ('head',  '90000000-0000-0000-0000-000000000002'),
  ('asha',  '90000000-0000-0000-0000-000000000003'),
  ('bimal', '90000000-0000-0000-0000-000000000004');

-- ---------------------------------------------------------------------------
-- 3. The five bookings and the five gifts.
--
--    Inserted straight into the tables as the owner. The RPCs cannot produce an
--    expired hold on demand — hold_sponsorship sweeps its own type and date
--    before it writes — and an expired hold that nothing has swept is precisely
--    the state under test.
--
--    Five different sponsorship types on five different days, so neither unique
--    index has anything to say about the fixture and every failure below is
--    about the read and not about the seed.
-- ---------------------------------------------------------------------------

do $$
declare
  v_case record;
  v_today date := (now() at time zone 'America/Chicago')::date;
  v_booking uuid;
  v_asha uuid := '90000000-0000-0000-0000-000000000003';
begin
  for v_case in
    select * from (values
      -- key,        type name,       day offset, status,      expiry
      ('confirmed',  'Garland',       30, 'confirmed', null::interval),
      ('live',       'Rajbhog',       31, 'held',      interval '30 minutes'),
      ('expired',    'Mangal Aarti',  32, 'held',      interval '-1 minute'),
      ('released',   'Breakfast',     33, 'released',  null),
      ('cancelled',  'Sandhya Bhog',  34, 'cancelled', null)
    ) as spec(key, type_name, offset_days, status, expiry)
  loop
    v_booking := null;
    insert into public.sponsorship_bookings (
      sponsorship_type_id, devotee_id, on_date, status, held_until, amount_cents
    )
    select types.id, v_asha, v_today + v_case.offset_days, v_case.status,
           case when v_case.expiry is not null then now() + v_case.expiry end,
           types.amount_cents
    from public.sponsorship_types types
    where types.name = v_case.type_name
    returning id into v_booking;

    if v_booking is null then
      raise exception 'The fixture could not book %.', v_case.type_name;
    end if;

    insert into public.gr_ids (key, id) values ('b_' || v_case.key, v_booking);
  end loop;
end;
$$;

insert into public.donations (
  donor_id, donor_name, donor_email, amount_cents, currency, kind,
  external_payment_id, received_at, sponsorship_booking_id, match_status,
  expected_amount_cents
)
values
  ('90000000-0000-0000-0000-000000000003', 'Gr Asha', 'gr-asha@example.test',
   35100, 'USD', 'one_time', 'gr-pay-confirmed', now(),
   (select ids.id from public.gr_ids ids where ids.key = 'b_confirmed'),
   'matched', 35100),
  ('90000000-0000-0000-0000-000000000003', 'Gr Asha', 'gr-asha@example.test',
   12500, 'USD', 'one_time', 'gr-pay-released', now(),
   (select ids.id from public.gr_ids ids where ids.key = 'b_released'),
   'matched', 12500),
  ('90000000-0000-0000-0000-000000000003', 'Gr Asha', 'gr-asha@example.test',
   10800, 'USD', 'one_time', 'gr-pay-expired', now(),
   (select ids.id from public.gr_ids ids where ids.key = 'b_expired'),
   'matched', 10800),
  ('90000000-0000-0000-0000-000000000003', 'Gr Asha', 'gr-asha@example.test',
   9900, 'CAD', 'one_time', 'gr-pay-cad', now(), null, 'general', null),
  ('90000000-0000-0000-0000-000000000004', 'Gr Bimal', 'gr-bimal@example.test',
   5000, 'USD', 'one_time', 'gr-pay-bimal', now(), null, 'general', null);

-- Two acts of seva for Asha and one for Bimal, on today's Chicago date at
-- midnight so the ninety-day default window always contains them.
do $$
declare
  v_type uuid;
  v_today date := public.seva_mala_today();
  v_case record;
  v_instance uuid;
begin
  select service_types.id into v_type
  from public.service_types where service_types.name = 'Pot Washing';

  for v_case in
    select * from (values
      ('asha',  120, 'completed', 'served', 'member_verified'),
      ('asha',   60, 'completed', null,     'member_verified'),
      ('bimal', 120, 'completed', 'served', 'member_verified')
    ) as spec(who, minutes, status, attendance, verification)
  loop
    insert into public.service_instances (
      service_type_id, date, start_time, duration_minutes, slots_needed,
      participation_mode, posted_by, status
    ) values (
      v_type, v_today, time '00:00', v_case.minutes, 1, 'open',
      '90000000-0000-0000-0000-000000000001', 'completed'
    ) returning id into v_instance;

    insert into public.service_assignments (
      service_instance_id, devotee_id, assignment_method, status,
      verification, attendance, completed_at
    )
    select v_instance, ids.id, 'self_joined', v_case.status,
           v_case.verification, v_case.attendance,
           (v_today + time '02:00') at time zone 'America/Chicago'
    from public.gr_ids ids where ids.key = v_case.who;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Nothing has swept. The expired hold is still 'held' in the table.
--
--    Asserted here and again at the end of the file, because every claim below
--    is only interesting while it is true.
-- ---------------------------------------------------------------------------

do $$
declare
  v_stored text;
begin
  select bookings.status into v_stored
  from public.sponsorship_bookings bookings
  join public.gr_ids ids on ids.id = bookings.id
  where ids.key = 'b_expired';

  if v_stored is distinct from 'held' then
    raise exception
      'The fixture''s expired hold is stored as %, so nothing below tests a stale hold.',
      v_stored;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. The projection itself, over every state a booking can be in.
--
--    Six cases rather than the one that matters, so a mutation that widens the
--    rule by one status fails whether or not anybody wrote a case for it.
-- ---------------------------------------------------------------------------

do $$
declare
  v_case record;
  v_got text;
begin
  for v_case in
    select * from (values
      ('held',      interval '30 minutes', 'held'),
      ('held',      interval '-1 minute',  'released'),
      ('held',      interval '-400 days',  'released'),
      ('confirmed', null::interval,        'confirmed'),
      ('released',  null,                  'released'),
      ('cancelled', null,                  'cancelled'),
      -- A confirmed booking that still carries a stale expiry is confirmed.
      -- Money was received; the clock has nothing to say about it.
      ('confirmed', interval '-1 minute',  'confirmed'),
      ('cancelled', interval '-1 minute',  'cancelled')
    ) as spec(status, expiry, expected)
  loop
    v_got := public.sponsorship_effective_status(
      v_case.status,
      case when v_case.expiry is not null then now() + v_case.expiry end);
    if v_got is distinct from v_case.expected then
      raise exception 'A % booking expiring % reads as % rather than %.',
        v_case.status, coalesce(v_case.expiry::text, 'never'), v_got, v_case.expected;
    end if;
  end loop;

  -- A hold with no expiry at all cannot be turned into a release by a null.
  if public.sponsorship_effective_status('held', null) is distinct from 'held' then
    raise exception 'A hold with no expiry was projected away by a null comparison.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Asha's own list. Live by default; everything with the flag.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000003', true);
set local role authenticated;

do $$
declare
  v_rows integer;
  v_case record;
  v_got text;
  v_today date := (now() at time zone 'America/Chicago')::date;
begin
  -- First, the premise. The calendar has already given the expired date away,
  -- which is why a list that still calls it a hold is lying. If this ever
  -- stops being true, the projection is agreeing with nothing.
  if not exists (
    select 1
    from public.sponsorship_availability(v_today, v_today + 40) free
    join public.sponsorship_types types on types.id = free.sponsorship_type_id
    where types.name = 'Mangal Aarti'
      and free.on_date = v_today + 32
      and not free.is_taken
  ) then
    raise exception
      'sponsorship_availability still treats the expired date as taken, so it disagrees with nothing.';
  end if;

  -- And the live hold really is still holding its date, so the two arms of the
  -- projection are being told apart by held_until and not by luck.
  if not exists (
    select 1
    from public.sponsorship_availability(v_today, v_today + 40) free
    join public.sponsorship_types types on types.id = free.sponsorship_type_id
    where types.name = 'Rajbhog'
      and free.on_date = v_today + 31
      and free.is_taken
  ) then
    raise exception 'The live hold is not holding its date, so the fixture proves nothing.';
  end if;

  select count(*)::integer into v_rows from public.list_my_sponsorships();
  if v_rows <> 2 then
    raise exception
      'Asha''s default sponsorship list has % rows rather than the two live ones.', v_rows;
  end if;

  -- Exactly which two, by name, so a filter that kept the wrong pair fails.
  if not exists (
    select 1 from public.list_my_sponsorships() mine
    where mine.type_name = 'Garland' and mine.status = 'confirmed'
  ) then
    raise exception 'Asha''s confirmed garland is missing from her own list.';
  end if;
  if not exists (
    select 1 from public.list_my_sponsorships() mine
    where mine.type_name = 'Rajbhog' and mine.status = 'held'
  ) then
    raise exception 'Asha''s live hold is missing from her own list.';
  end if;

  -- THE assertion. The expired hold is not there, and it is not there under
  -- either name it could go by.
  if exists (
    select 1 from public.list_my_sponsorships() mine
    where mine.type_name = 'Mangal Aarti'
  ) then
    raise exception 'The expired hold is still on Asha''s giving history by default.';
  end if;
  if exists (
    select 1 from public.list_my_sponsorships() mine
    where mine.status in ('released', 'cancelled')
  ) then
    raise exception 'A released or cancelled booking is shown by default.';
  end if;

  -- Explicit false is the default, and explicit null is not a way past it.
  if (select count(*)::integer from public.list_my_sponsorships(false)) <> 2 then
    raise exception 'Passing false is not the same as passing nothing.';
  end if;
  if (select count(*)::integer from public.list_my_sponsorships(null)) <> 2 then
    raise exception 'A null flag opened the lapsed bookings.';
  end if;

  -- With the flag, all five, each reading as what it is.
  select count(*)::integer into v_rows from public.list_my_sponsorships(true);
  if v_rows <> 5 then
    raise exception 'Asha''s full sponsorship list has % rows rather than five.', v_rows;
  end if;

  for v_case in
    select * from (values
      ('Garland',      'confirmed'),
      ('Rajbhog',      'held'),
      ('Mangal Aarti', 'released'),   -- the stale hold, projected
      ('Breakfast',    'released'),
      ('Sandhya Bhog', 'cancelled')
    ) as spec(type_name, expected)
  loop
    select mine.status into v_got
    from public.list_my_sponsorships(true) mine
    where mine.type_name = v_case.type_name;
    if v_got is distinct from v_case.expected then
      raise exception 'With the flag, % reads as % rather than %.',
        v_case.type_name, coalesce(v_got, 'missing'), v_case.expected;
    end if;
  end loop;

  -- The projected release keeps the moment it ran out, rather than being
  -- blanked as though a sweep had happened.
  if not exists (
    select 1 from public.list_my_sponsorships(true) mine
    where mine.type_name = 'Mangal Aarti'
      and mine.held_until is not null
      and mine.held_until <= now()
  ) then
    raise exception 'The projected release lost the moment its hold ran out.';
  end if;

  -- The gift attached to each booking still comes back, whatever the status.
  if not exists (
    select 1 from public.list_my_sponsorships(true) mine
    where mine.type_name = 'Breakfast' and mine.donation_id is not null
  ) then
    raise exception 'The gift attached to the released booking vanished with it.';
  end if;
end;
$$;

-- Kept for section 7, so the President's record can be compared with the
-- devotee's own rather than with a second copy of the same query.
insert into public.gr_asha_own_sponsorships
select * from public.list_my_sponsorships(true);

-- Bimal, who has no bookings, sees none of Asha's under either flag.
reset role;
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000004', true);
set local role authenticated;

do $$
begin
  if (select count(*) from public.list_my_sponsorships()) <> 0
    or (select count(*) from public.list_my_sponsorships(true)) <> 0 then
    raise exception 'A devotee with no bookings can see somebody else''s.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. The President's list says the same thing about the same rows.
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
  v_rows integer;
  v_disagreements integer;
begin
  select count(*)::integer into v_rows
  from public.list_all_sponsorships() theirs
  where theirs.devotee_email = 'gr-asha@example.test';
  if v_rows <> 2 then
    raise exception
      'The President''s default view of Asha has % rows rather than the two live ones.', v_rows;
  end if;

  if exists (
    select 1 from public.list_all_sponsorships() all_sponsorships
    where all_sponsorships.type_name = 'Mangal Aarti'
      and all_sponsorships.devotee_email = 'gr-asha@example.test'
  ) then
    raise exception 'The President''s default view still carries the expired hold.';
  end if;

  select count(*)::integer into v_rows
  from public.list_all_sponsorships(true) theirs
  where theirs.devotee_email = 'gr-asha@example.test';
  if v_rows <> 5 then
    raise exception 'The President''s full view of Asha has % rows rather than five.', v_rows;
  end if;

  if not exists (
    select 1 from public.list_all_sponsorships(true) theirs
    where theirs.type_name = 'Mangal Aarti'
      and theirs.status = 'released'
      and theirs.devotee_name = 'Gr Asha'
  ) then
    raise exception 'The President reads the stale hold as something other than released.';
  end if;

  -- THE agreement, booking by booking, against what Asha herself was shown in
  -- section 6 rather than against a second copy of the same query. Five rows
  -- on each side and no row where the two say different words.
  select count(*)::integer into v_disagreements
  from public.gr_asha_own_sponsorships mine
  full join (
    select theirs.id, theirs.status
    from public.list_all_sponsorships(true) theirs
    where theirs.devotee_email = 'gr-asha@example.test'
  ) presidents on presidents.id = mine.id
  where mine.id is null
     or presidents.id is null
     or mine.status is distinct from presidents.status;
  if v_disagreements <> 0 then
    raise exception
      'The President''s record and Asha''s disagree about % of her bookings.', v_disagreements;
  end if;

  -- The default views agree too, and not by both being empty.
  select count(*)::integer into v_disagreements
  from (
    (select mine.id from public.gr_asha_own_sponsorships mine
      where mine.status in ('held', 'confirmed')
     except
     select theirs.id from public.list_all_sponsorships() theirs
      where theirs.devotee_email = 'gr-asha@example.test')
    union all
    (select theirs.id from public.list_all_sponsorships() theirs
      where theirs.devotee_email = 'gr-asha@example.test'
     except
     select mine.id from public.gr_asha_own_sponsorships mine
      where mine.status in ('held', 'confirmed'))
  ) as difference;
  if v_disagreements <> 0 then
    raise exception
      'The two default views of Asha''s sponsorships differ by % bookings.', v_disagreements;
  end if;
end;
$$;

-- Neither a plain devotee nor a Community Head sees the whole-congregation
-- list, with the flag or without it.
reset role;
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000003', true);
set local role authenticated;

do $$
begin
  if (select count(*) from public.list_all_sponsorships()) <> 0
    or (select count(*) from public.list_all_sponsorships(true)) <> 0 then
    raise exception 'A devotee reads the whole congregation''s sponsorships.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
begin
  if (select count(*) from public.list_all_sponsorships()) <> 0
    or (select count(*) from public.list_all_sponsorships(true)) <> 0 then
    raise exception 'A Community Head reads the whole congregation''s sponsorships.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. One devotee's seva, act by act.
--
--    The President's answer must be Asha's own answer. Compared act by act
--    rather than by count, because two lists of two rows can both be two rows
--    and be about different Tuesdays.
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000003', true);
set local role authenticated;

insert into public.gr_asha_own_acts
select * from public.my_seva_acts();

do $$
begin
  if (select count(*) from public.gr_asha_own_acts) <> 2 then
    raise exception 'Asha''s own act list is % rows rather than two.',
      (select count(*) from public.gr_asha_own_acts);
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
  v_rows integer;
  v_differences integer;
begin
  select count(*)::integer into v_rows
  from public.list_devotee_seva_acts('90000000-0000-0000-0000-000000000003');
  if v_rows <> 2 then
    raise exception 'The President sees % of Asha''s two acts.', v_rows;
  end if;

  -- Row for row, column for column.
  select count(*)::integer into v_differences
  from (
    (select * from public.list_devotee_seva_acts('90000000-0000-0000-0000-000000000003')
     except all
     select * from public.gr_asha_own_acts)
    union all
    (select * from public.gr_asha_own_acts
     except all
     select * from public.list_devotee_seva_acts('90000000-0000-0000-0000-000000000003'))
  ) as difference;
  if v_differences <> 0 then
    raise exception
      'The President and Asha are reading % different rows about the same seva.',
      v_differences;
  end if;

  -- The reason in words survived the copy — it is the whole point of the
  -- screen, and a null there is a blank line where "nobody has confirmed you
  -- were there" belongs.
  if exists (
    select 1 from public.list_devotee_seva_acts('90000000-0000-0000-0000-000000000003') acts
    where acts.points_note is null or acts.points_note = ''
  ) then
    raise exception 'An act came back with no reason in words.';
  end if;
  if not exists (
    select 1 from public.list_devotee_seva_acts('90000000-0000-0000-0000-000000000003') acts
    where acts.points_status = 'counted'
  ) or not exists (
    select 1 from public.list_devotee_seva_acts('90000000-0000-0000-0000-000000000003') acts
    where acts.points_status <> 'counted'
  ) then
    raise exception 'The fixture no longer contains both a counted and an uncounted act.';
  end if;

  -- It is one devotee's, not everybody's. Bimal served today too.
  if (select count(*)
      from public.list_devotee_seva_acts('90000000-0000-0000-0000-000000000004')) <> 1 then
    raise exception 'Bimal''s act list is not one act.';
  end if;

  -- A null devotee id is an empty screen, not the congregation.
  -- seva_mala_acts reads null as "everybody", and this is the guard that stops
  -- a client that failed to resolve an id from being handed the temple.
  if (select count(*) from public.list_devotee_seva_acts(null)) <> 0 then
    raise exception 'A null devotee id returned the whole congregation''s seva.';
  end if;

  -- The window narrows, and narrows to nothing when asked.
  if (select count(*) from public.list_devotee_seva_acts(
        '90000000-0000-0000-0000-000000000003',
        public.seva_mala_today() + 1, public.seva_mala_today() + 30)) <> 0 then
    raise exception 'A future window found acts.';
  end if;
end;
$$;

-- A plain devotee and a Community Head get an empty set, not an exception:
-- this backs a screen.
reset role;
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000004', true);
set local role authenticated;

do $$
begin
  if (select count(*)
      from public.list_devotee_seva_acts('90000000-0000-0000-0000-000000000003')) <> 0 then
    raise exception 'A devotee read another devotee''s seva act by act.';
  end if;
  -- Not even their own, through this door. my_seva_acts is that door.
  if (select count(*)
      from public.list_devotee_seva_acts('90000000-0000-0000-0000-000000000004')) <> 0 then
    raise exception 'A devotee reached the admin act list by naming themselves.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
begin
  if (select count(*)
      from public.list_devotee_seva_acts('90000000-0000-0000-0000-000000000003')) <> 0 then
    raise exception 'A Community Head read another devotee''s seva act by act.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 9. The donation ledger: filtered, and saying where each sponsorship stands.
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
  v_rows integer;
  v_status text;
begin
  -- Null donor is the old behaviour: every gift in the window.
  select count(*)::integer into v_rows from public.list_all_donations(null, null);
  if v_rows <> 5 then
    raise exception 'The President sees % gifts rather than all five.', v_rows;
  end if;

  -- One donor's.
  select count(*)::integer into v_rows
  from public.list_all_donations(null, null, '90000000-0000-0000-0000-000000000003');
  if v_rows <> 4 then
    raise exception 'Asha''s giving is % rows rather than four.', v_rows;
  end if;

  if exists (
    select 1 from public.list_all_donations(
      null, null, '90000000-0000-0000-0000-000000000003') gifts
    where gifts.external_payment_id = 'gr-pay-bimal'
  ) then
    raise exception 'The donor filter let somebody else''s gift through.';
  end if;

  select count(*)::integer into v_rows
  from public.list_all_donations(null, null, '90000000-0000-0000-0000-000000000004');
  if v_rows <> 1 then
    raise exception 'Bimal''s giving is % rows rather than one.', v_rows;
  end if;

  -- A donor who gave nothing is an empty list and not everybody's.
  select count(*)::integer into v_rows
  from public.list_all_donations(null, null, '90000000-0000-0000-0000-000000000002');
  if v_rows <> 0 then
    raise exception 'Filtering by a donor who gave nothing returned % rows.', v_rows;
  end if;

  -- The window and the donor narrow together rather than one replacing the
  -- other.
  select count(*)::integer into v_rows
  from public.list_all_donations(
    (now() at time zone 'America/Chicago')::date + 1,
    (now() at time zone 'America/Chicago')::date + 2,
    '90000000-0000-0000-0000-000000000003');
  if v_rows <> 0 then
    raise exception 'A future window with a donor found % gifts.', v_rows;
  end if;

  -- booking_status, and it is the PROJECTED status.
  select gifts.booking_status into v_status
  from public.list_all_donations(null, null) gifts
  where gifts.external_payment_id = 'gr-pay-confirmed';
  if v_status is distinct from 'confirmed' then
    raise exception 'The confirmed booking reports % on its donation.', coalesce(v_status, 'null');
  end if;

  select gifts.booking_status into v_status
  from public.list_all_donations(null, null) gifts
  where gifts.external_payment_id = 'gr-pay-released';
  if v_status is distinct from 'released' then
    raise exception 'The released booking reports % on its donation.', coalesce(v_status, 'null');
  end if;

  -- The stale hold, on the ledger, without a second round trip and without a
  -- sweep.
  select gifts.booking_status into v_status
  from public.list_all_donations(null, null) gifts
  where gifts.external_payment_id = 'gr-pay-expired';
  if v_status is distinct from 'released' then
    raise exception
      'A gift attached to an expired hold reports its booking as %.', coalesce(v_status, 'null');
  end if;

  -- A gift that paid for no sponsorship has no booking status, and that null
  -- means "this was a gift, not a date".
  if (select gifts.booking_status from public.list_all_donations(null, null) gifts
      where gifts.external_payment_id = 'gr-pay-cad') is not null then
    raise exception 'A plain gift was given a booking status.';
  end if;

  -- THE claim about the ledger: the money is still there.
  if not exists (
    select 1 from public.list_all_donations(null, null) gifts
    where gifts.external_payment_id = 'gr-pay-released' and gifts.amount_cents = 12500
  ) then
    raise exception 'The gift for a released date fell off the ledger.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 10. The totals. Grouped by currency, and never across it.
-- ---------------------------------------------------------------------------

do $$
declare
  v_rows integer;
  v_usd bigint;
  v_cad bigint;
  v_gifts integer;
begin
  select count(*)::integer into v_rows from public.donation_totals(null, null);
  if v_rows <> 2 then
    raise exception 'The whole-temple total came back as % rows rather than one per currency.',
      v_rows;
  end if;

  select totals.total_cents, totals.gifts into v_usd, v_gifts
  from public.donation_totals(null, null) totals where totals.currency = 'USD';
  if v_usd is distinct from 63400 then
    raise exception 'The USD total is % rather than 63400 cents.', coalesce(v_usd, -1);
  end if;
  if v_gifts <> 4 then
    raise exception 'The USD total counts % gifts rather than four.', v_gifts;
  end if;

  select totals.total_cents, totals.gifts into v_cad, v_gifts
  from public.donation_totals(null, null) totals where totals.currency = 'CAD';
  if v_cad is distinct from 9900 then
    raise exception 'The CAD total is % rather than 9900 cents.', coalesce(v_cad, -1);
  end if;
  if v_gifts <> 1 then
    raise exception 'The CAD total counts % gifts rather than one.', v_gifts;
  end if;

  -- The sum across currencies, 73300, must exist nowhere. Not as a row, not as
  -- a currency called something else, not once.
  if exists (
    select 1 from public.donation_totals(null, null) totals where totals.total_cents = 73300
  ) then
    raise exception 'Dollars and Canadian dollars were added together.';
  end if;
  if (select count(*) from public.donation_totals(null, null) totals
      where totals.currency is null or totals.currency not in ('USD', 'CAD')) <> 0 then
    raise exception 'A total came back under a currency nobody gave in.';
  end if;

  -- THE claim: the released date and the stale hold are still money.
  -- 35100 alone would be the answer if a released booking cancelled its gift.
  if v_usd = 35100 then
    raise exception 'Only the confirmed booking''s gift was counted; the rest were dropped.';
  end if;
  if v_usd - 12500 - 10800 - 5000 <> 35100 then
    raise exception 'The USD total is not the four gifts that were received.';
  end if;

  -- One donor's total.
  select totals.total_cents, totals.gifts into v_usd, v_gifts
  from public.donation_totals(null, null, '90000000-0000-0000-0000-000000000003') totals
  where totals.currency = 'USD';
  if v_usd is distinct from 58400 or v_gifts <> 3 then
    raise exception 'Asha''s USD total is % over % gifts rather than 58400 over 3.',
      coalesce(v_usd, -1), v_gifts;
  end if;
  if (select count(*) from public.donation_totals(
        null, null, '90000000-0000-0000-0000-000000000003')) <> 2 then
    raise exception 'Asha''s total is not one row per currency.';
  end if;

  select totals.total_cents into v_usd
  from public.donation_totals(null, null, '90000000-0000-0000-0000-000000000004') totals
  where totals.currency = 'USD';
  if v_usd is distinct from 5000 then
    raise exception 'Bimal''s USD total is % rather than 5000.', coalesce(v_usd, -1);
  end if;
  if exists (
    select 1 from public.donation_totals(
      null, null, '90000000-0000-0000-0000-000000000004') totals
    where totals.currency = 'CAD'
  ) then
    raise exception 'Bimal was credited with Asha''s Canadian gift.';
  end if;

  -- The window applies to the total exactly as it does to the list.
  if (select count(*) from public.donation_totals(
        (now() at time zone 'America/Chicago')::date + 1,
        (now() at time zone 'America/Chicago')::date + 2)) <> 0 then
    raise exception 'A future window produced a total.';
  end if;
  select totals.total_cents into v_usd
  from public.donation_totals(
    (now() at time zone 'America/Chicago')::date,
    (now() at time zone 'America/Chicago')::date) totals
  where totals.currency = 'USD';
  if v_usd is distinct from 63400 then
    raise exception 'Today''s window totalled % rather than 63400.', coalesce(v_usd, -1);
  end if;

  -- The list and the total answer the same question about the same rows.
  if (select coalesce(sum(gifts.amount_cents), 0)
      from public.list_all_donations(null, null) gifts where gifts.currency = 'USD')
     is distinct from 63400 then
    raise exception 'The ledger and the total disagree about the USD figure.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 11. my_donation_totals is the caller's own, and nobody else's.
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000003', true);
set local role authenticated;

do $$
declare
  v_usd bigint;
  v_gifts integer;
begin
  if (select count(*) from public.my_donation_totals()) <> 2 then
    raise exception 'Asha''s own total is not one row per currency.';
  end if;

  select totals.total_cents, totals.gifts into v_usd, v_gifts
  from public.my_donation_totals() totals where totals.currency = 'USD';
  if v_usd is distinct from 58400 or v_gifts <> 3 then
    raise exception 'Asha''s own USD total is % over % gifts rather than 58400 over 3.',
      coalesce(v_usd, -1), v_gifts;
  end if;
  if v_usd = 63400 then
    raise exception 'Asha''s own total is the whole temple''s.';
  end if;

  select totals.total_cents into v_usd
  from public.my_donation_totals() totals where totals.currency = 'CAD';
  if v_usd is distinct from 9900 then
    raise exception 'Asha''s own CAD total is % rather than 9900.', coalesce(v_usd, -1);
  end if;

  -- And it agrees with what the President reads about her, which is the only
  -- way the two screens can ever be shown side by side.
  if (select count(*) from public.donation_totals(null, null)) <> 0 then
    raise exception 'A devotee read the whole temple''s totals.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000004', true);
set local role authenticated;

do $$
declare
  v_usd bigint;
begin
  select totals.total_cents into v_usd
  from public.my_donation_totals() totals where totals.currency = 'USD';
  if v_usd is distinct from 5000 then
    raise exception 'Bimal''s own USD total is % rather than 5000.', coalesce(v_usd, -1);
  end if;
  if (select count(*) from public.my_donation_totals()) <> 1 then
    raise exception 'Bimal''s own total carries a currency he never gave in.';
  end if;
end;
$$;

-- The Community Head is nearly an admin and is not one, for the totals too.
reset role;
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
begin
  if (select count(*) from public.donation_totals(null, null)) <> 0 then
    raise exception 'A Community Head read the whole temple''s totals.';
  end if;
  if (select count(*) from public.list_all_donations(null, null)) <> 0 then
    raise exception 'A Community Head read the whole temple''s ledger.';
  end if;
  if (select count(*) from public.list_all_donations(
        null, null, '90000000-0000-0000-0000-000000000003')) <> 0 then
    raise exception 'A Community Head reached one devotee''s giving by naming them.';
  end if;
  if (select count(*) from public.my_donation_totals()) <> 0 then
    raise exception 'A Community Head who gave nothing has a total.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 12. Nothing above wrote anything, and none of it is reachable anonymously.
-- ---------------------------------------------------------------------------

reset role;

do $$
declare
  v_function text;
  v_stored text;
begin
  -- Still no sweep. Every projection above was a projection.
  select bookings.status into v_stored
  from public.sponsorship_bookings bookings
  join public.gr_ids ids on ids.id = bookings.id
  where ids.key = 'b_expired';
  if v_stored is distinct from 'held' then
    raise exception 'Reading the lists released the expired hold. These are reads.';
  end if;

  if (select count(*) from public.donations) <> 5 then
    raise exception 'The donation table changed while being read.';
  end if;

  for v_function in
    select p.oid::regprocedure::text
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in (
        'sponsorship_effective_status', 'list_my_sponsorships', 'list_all_sponsorships',
        'list_devotee_seva_acts', 'list_all_donations', 'donation_totals',
        'my_donation_totals'
      )
      and has_function_privilege('anon', p.oid, 'execute')
  loop
    raise exception 'anon can execute %.', v_function;
  end loop;

  foreach v_function in array array[
    'public.sponsorship_effective_status(text, timestamptz)',
    'public.list_my_sponsorships(boolean)',
    'public.list_all_sponsorships(boolean)',
    'public.list_devotee_seva_acts(uuid, date, date)',
    'public.list_all_donations(date, date, uuid)',
    'public.donation_totals(date, date, uuid)',
    'public.my_donation_totals()'
  ] loop
    if not has_function_privilege('authenticated', v_function, 'execute') then
      raise exception 'A signed-in devotee cannot reach %.', v_function;
    end if;
  end loop;

  -- The helpers underneath list_devotee_seva_acts stay shut. This migration
  -- opened one door and must not have opened the corridor.
  if has_function_privilege('authenticated', 'public.seva_mala_acts(uuid)', 'execute')
    or has_function_privilege('authenticated', 'public.seva_balance_acts(uuid)', 'execute') then
    raise exception 'The seva act helpers became callable directly.';
  end if;
end;
$$;

select 'giving and acts reads verification passed' as result;

rollback;
