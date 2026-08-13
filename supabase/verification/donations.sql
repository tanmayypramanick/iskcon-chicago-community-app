-- Functional verification for 202608040048_donations.sql.
--
-- Rolled back at the end. Every local is prefixed v_ so it can never shadow a
-- column name. Anything that must be refused is attempted as the devotee who
-- would really attempt it, under `set local role authenticated`, so the row
-- level security policies and the column grants are the thing being tested
-- rather than superuser rights quietly waving everything through.
--
-- The people in this script:
--   President  ...0001  holds app.view_all; must see every gift
--   Asha       ...0002  a devotee; books, pays, and may see only her own
--   Bimal      ...0003  a devotee; races Asha for the same date and loses
--   Chandra    ...0004  a devotee who gives nothing and must learn nothing
--
-- The one claim this script exists to prove is that a sponsorship type on a
-- date can be taken exactly once, and that it stays true when the RPC is not
-- involved at all. Section 4 inserts straight into the table as a superuser.
--
-- The final row must read: donations verification passed

begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('d0000000-0000-0000-0000-000000000001', 'don-president@example.test', '{"name":"Don President"}'),
  ('d0000000-0000-0000-0000-000000000002', 'don-asha@example.test', '{"name":"Asha Devi"}'),
  ('d0000000-0000-0000-0000-000000000003', 'don-bimal@example.test', '{"name":"Bimal Das"}'),
  ('d0000000-0000-0000-0000-000000000004', 'don-chandra@example.test', '{"name":"Chandra Devi"}');

update public.users
set role_id = (select roles.id from public.roles where roles.name = 'president')
where email = 'don-president@example.test';

-- Ordinary table rather than a temporary one, so reading it under the
-- authenticated role needs no assumptions about the temp schema. The whole
-- script is rolled back, so it never outlives the transaction.
create table public.donation_test_ids (key text primary key, id uuid not null);
grant select, insert, update on public.donation_test_ids to authenticated;

-- ---------------------------------------------------------------------------
-- 1. The temple's list is seeded, priced in whole cents, and nothing in it is
--    a float.
--
--    The amounts are asserted one by one rather than as a checksum, because a
--    checksum passes when two prices are swapped and a devotee then pays $2500
--    for a garland.
-- ---------------------------------------------------------------------------

do $$
declare
  v_expected text;
  v_actual text;
  v_type text;
begin
  for v_expected, v_actual in
    select expected.cents::text, coalesce(types.amount_cents::text, 'missing')
    from (values
      ('Mangal Aarti', 10800),
      ('Breakfast', 12500),
      ('Sandhya Bhog', 15100),
      ('Rajbhog', 20100),
      ('Garland', 35100),
      ('Sunday Feast', 55100),
      ('Sunday Feast (higher)', 75100),
      ('Deity Dress', 250000)
    ) as expected(name, cents)
    left join public.sponsorship_types types on types.name = expected.name
    where coalesce(types.amount_cents, -1) <> expected.cents
  loop
    raise exception 'A seeded sponsorship price is % where % was expected.',
      v_actual, v_expected;
  end loop;

  -- Every seeded type must be on offer and ordered.
  if exists (
    select 1 from public.sponsorship_types where not is_active
  ) then
    raise exception 'A seeded sponsorship type was seeded switched off.';
  end if;

  if exists (
    select 1 from public.sponsorship_types
    group by display_order having count(*) > 1
  ) then
    raise exception 'Two sponsorship types share a display order.';
  end if;

  -- Money must be an integer column, everywhere it appears.
  for v_type in
    select attrelid::regclass::text || '.' || attname
    from pg_attribute
    where attrelid in (
        'public.sponsorship_types'::regclass,
        'public.sponsorship_bookings'::regclass,
        'public.donations'::regclass
      )
      and attname = 'amount_cents'
      and format_type(atttypid, atttypmod) not in ('integer', 'bigint')
  loop
    raise exception '% is not an integer, so money can round.', v_type;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. The list is readable by an ordinary devotee.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'd0000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_rows integer;
  v_first text;
begin
  select count(*)::integer into v_rows from public.list_sponsorship_types();
  if v_rows < 8 then
    raise exception 'A devotee sees only % sponsorship types.', v_rows;
  end if;

  select types.name into v_first from public.list_sponsorship_types() types limit 1;
  if v_first is distinct from 'Mangal Aarti' then
    raise exception 'The sponsorship list is not in display order; it starts at %.', v_first;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Asha takes a date. Bimal is refused that exact type and date, and is
--    refused it while Asha has only a hold — not a confirmed sponsorship.
--
--    The date used everywhere below is chosen in Chicago, so the script never
--    depends on the machine running it agreeing with the temple about what day
--    it is.
-- ---------------------------------------------------------------------------

do $$
declare
  v_type public.sponsorship_types;
  v_booking public.sponsorship_bookings;
  v_target date := (now() at time zone 'America/Chicago')::date + 21;
begin
  select * into v_type from public.sponsorship_types where name = 'Garland';

  v_booking := public.hold_sponsorship(v_type.id, v_target);

  if v_booking.id is null then
    raise exception 'Asha could not hold the garland.';
  end if;
  if v_booking.status <> 'held' then
    raise exception 'A fresh booking is % rather than held.', v_booking.status;
  end if;
  if v_booking.held_until is null then
    raise exception 'A hold was created with no expiry.';
  end if;
  if v_booking.amount_cents <> 35100 then
    raise exception 'The garland hold recorded % cents.', v_booking.amount_cents;
  end if;
  if v_booking.devotee_id <> 'd0000000-0000-0000-0000-000000000002'::uuid then
    raise exception 'The hold was recorded against the wrong devotee.';
  end if;

  insert into public.donation_test_ids (key, id)
  values ('garland_type', v_type.id), ('asha_garland', v_booking.id);
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'd0000000-0000-0000-0000-000000000003', true);
set local role authenticated;

do $$
declare
  v_type uuid;
  v_target date := (now() at time zone 'America/Chicago')::date + 21;
  v_refused boolean := false;
  v_message text;
begin
  select ids.id into v_type from public.donation_test_ids ids where ids.key = 'garland_type';

  begin
    perform public.hold_sponsorship(v_type, v_target);
  exception when others then
    v_refused := true;
    v_message := sqlerrm;
  end;

  if not v_refused then
    raise exception 'Bimal double-booked the garland Asha is already holding.';
  end if;
  if v_message not ilike '%already been sponsored%' then
    raise exception 'Bimal was refused with an unreadable message: %', v_message;
  end if;

  -- A different date on the same type is still free, and a different type on
  -- the same date is still free. The constraint must be on the pair, not on
  -- either half of it.
  perform public.hold_sponsorship(v_type, v_target + 1);
  perform public.hold_sponsorship(
    (select types.id from public.sponsorship_types types where types.name = 'Rajbhog'),
    v_target
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. THE constraint. The RPC is not involved.
--
--    Everything above proves hold_sponsorship refuses politely. This proves
--    the database refuses at all, which is the only guarantee that survives a
--    second client, a psql session, or a future RPC that forgets to check.
--    Run as the owning superuser, with row level security no obstacle and no
--    application code in the path.
-- ---------------------------------------------------------------------------

reset role;

do $$
declare
  v_type uuid;
  v_target date := (now() at time zone 'America/Chicago')::date + 60;
  v_refused boolean := false;
  v_second_refused boolean := false;
begin
  select ids.id into v_type from public.donation_test_ids ids where ids.key = 'garland_type';

  insert into public.sponsorship_bookings
    (sponsorship_type_id, devotee_id, on_date, status, held_until, amount_cents)
  values
    (v_type, 'd0000000-0000-0000-0000-000000000002', v_target, 'held',
     now() + interval '30 minutes', 35100);

  -- A second hold on the same type and date.
  begin
    insert into public.sponsorship_bookings
      (sponsorship_type_id, devotee_id, on_date, status, held_until, amount_cents)
    values
      (v_type, 'd0000000-0000-0000-0000-000000000003', v_target, 'held',
       now() + interval '30 minutes', 35100);
  exception when unique_violation then
    v_refused := true;
  end;

  if not v_refused then
    raise exception 'A direct insert double-booked a date the RPC would have refused.';
  end if;

  -- And a confirmed row cannot be slipped in beside a held one either: both
  -- states must be inside the index predicate.
  begin
    insert into public.sponsorship_bookings
      (sponsorship_type_id, devotee_id, on_date, status, amount_cents)
    values
      (v_type, 'd0000000-0000-0000-0000-000000000003', v_target, 'confirmed', 35100);
  exception when unique_violation then
    v_second_refused := true;
  end;

  if not v_second_refused then
    raise exception 'A confirmed booking was inserted alongside a live hold.';
  end if;

  -- A released row on the same date is fine, and there may be many of them:
  -- releasing is what frees the day, so released rows must fall outside the
  -- index or a date could only ever be abandoned once.
  insert into public.sponsorship_bookings
    (sponsorship_type_id, devotee_id, on_date, status, amount_cents)
  values
    (v_type, 'd0000000-0000-0000-0000-000000000003', v_target, 'released', 35100),
    (v_type, 'd0000000-0000-0000-0000-000000000004', v_target, 'cancelled', 35100);

  delete from public.sponsorship_bookings
  where sponsorship_bookings.on_date = v_target;
end;
$$;

-- The index is a partial unique index over exactly the live states, and it is
-- asserted by shape as well as by behaviour, so that widening the predicate
-- later trips this script rather than production.
do $$
declare
  v_definition text;
begin
  select indexdef into v_definition
  from pg_indexes
  where schemaname = 'public'
    and indexname = 'sponsorship_booking_one_live_per_type_and_date';

  if v_definition is null then
    raise exception 'The partial unique index on sponsorship bookings is gone.';
  end if;
  if v_definition not ilike 'CREATE UNIQUE INDEX%' then
    raise exception 'The sponsorship booking index is no longer unique: %', v_definition;
  end if;
  if v_definition !~* 'WHERE .*held.*confirmed' then
    raise exception 'The sponsorship booking index no longer covers held and confirmed: %',
      v_definition;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. A released hold frees the date, and only its owner may release it.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'd0000000-0000-0000-0000-000000000003', true);
set local role authenticated;

do $$
declare
  v_booking uuid;
  v_refused boolean := false;
begin
  select ids.id into v_booking from public.donation_test_ids ids where ids.key = 'asha_garland';

  begin
    perform public.release_sponsorship_hold(v_booking);
  exception when others then
    v_refused := true;
  end;

  if not v_refused then
    raise exception 'Bimal released a hold belonging to Asha.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'd0000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_booking uuid;
  v_released public.sponsorship_bookings;
begin
  select ids.id into v_booking from public.donation_test_ids ids where ids.key = 'asha_garland';

  v_released := public.release_sponsorship_hold(v_booking);

  if v_released.status <> 'released' then
    raise exception 'Releasing a hold left it %.', v_released.status;
  end if;
  if v_released.held_until is not null then
    raise exception 'A released hold kept its expiry.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'd0000000-0000-0000-0000-000000000003', true);
set local role authenticated;

do $$
declare
  v_type uuid;
  v_target date := (now() at time zone 'America/Chicago')::date + 21;
  v_booking public.sponsorship_bookings;
begin
  select ids.id into v_type from public.donation_test_ids ids where ids.key = 'garland_type';

  v_booking := public.hold_sponsorship(v_type, v_target);
  if v_booking.id is null then
    raise exception 'The date Asha released did not come back.';
  end if;

  perform public.release_sponsorship_hold(v_booking.id);
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. An expired hold is freed by the maintenance function, and the calendar
--    tells the truth about it before the sweep has even run.
--
--    The hold is aged by hand rather than by waiting thirty minutes.
-- ---------------------------------------------------------------------------

reset role;

do $$
declare
  v_type uuid;
  v_target date := (now() at time zone 'America/Chicago')::date + 30;
  v_booking uuid;
  v_freed integer;
  v_taken boolean;
begin
  select ids.id into v_type from public.donation_test_ids ids where ids.key = 'garland_type';

  insert into public.sponsorship_bookings
    (sponsorship_type_id, devotee_id, on_date, status, held_until, amount_cents)
  values
    (v_type, 'd0000000-0000-0000-0000-000000000002', v_target, 'held',
     now() - interval '1 minute', 35100)
  returning id into v_booking;

  -- Before the sweep: the calendar must already show the day as free, because
  -- the index cannot mention now() and a devotee must not be told a lapsed
  -- hold still owns the date.
  perform set_config('request.jwt.claim.sub', 'd0000000-0000-0000-0000-000000000003', true);
  select availability.is_taken into v_taken
  from public.sponsorship_availability(v_target, v_target) availability
  where availability.sponsorship_type_id = v_type;

  if v_taken then
    raise exception 'The calendar still shows a lapsed hold as taken.';
  end if;

  v_freed := public.release_expired_sponsorship_holds();
  if v_freed < 1 then
    raise exception 'The sweep freed % holds when at least one had expired.', v_freed;
  end if;

  if (select bookings.status from public.sponsorship_bookings bookings
      where bookings.id = v_booking) <> 'released' then
    raise exception 'An expired hold survived the sweep.';
  end if;

  -- A live hold must not be swept away underneath a devotee mid-payment.
  insert into public.sponsorship_bookings
    (sponsorship_type_id, devotee_id, on_date, status, held_until, amount_cents)
  values
    (v_type, 'd0000000-0000-0000-0000-000000000002', v_target + 1, 'held',
     now() + interval '30 minutes', 35100)
  returning id into v_booking;

  perform public.release_expired_sponsorship_holds();

  if (select bookings.status from public.sponsorship_bookings bookings
      where bookings.id = v_booking) <> 'held' then
    raise exception 'The sweep released a hold that had not expired.';
  end if;

  delete from public.sponsorship_bookings where sponsorship_bookings.id = v_booking;
end;
$$;

-- The sweep is not a client entry point.
do $$
declare
  v_granted boolean;
begin
  select has_function_privilege('authenticated', 'public.release_expired_sponsorship_holds()', 'execute')
    into v_granted;
  if v_granted then
    raise exception 'A devotee can run the sponsorship hold sweep.';
  end if;
  select has_function_privilege('anon', 'public.release_expired_sponsorship_holds()', 'execute')
    into v_granted;
  if v_granted then
    raise exception 'An anonymous caller can run the sponsorship hold sweep.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. A date in the past is refused, and "past" is Chicago's opinion.
--
--    The likeliest mistake is current_date or now()::date, both of which read
--    the caller's own timezone. Asking from session timezones spanning UTC-12
--    to UTC+14 catches that at any hour: at least one of them is always on a
--    different calendar day from Chicago, so an implementation that follows
--    the session must give a different answer to at least one of these.
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', 'd0000000-0000-0000-0000-000000000004', true);
set local role authenticated;

do $$
declare
  v_type uuid;
  v_chicago_today date := (now() at time zone 'America/Chicago')::date;
  v_zone text;
  v_refused boolean;
  v_message text;
  v_booking public.sponsorship_bookings;
begin
  select ids.id into v_type from public.donation_test_ids ids where ids.key = 'garland_type';

  foreach v_zone in array
    array['UTC', 'Pacific/Kiritimati', 'Etc/GMT+12', 'Asia/Tokyo', 'America/Chicago']
  loop
    perform set_config('timezone', v_zone, true);

    -- Yesterday in Chicago is refused from every seat on earth.
    v_refused := false;
    begin
      perform public.hold_sponsorship(v_type, v_chicago_today - 1);
    exception when others then
      v_refused := true;
      v_message := sqlerrm;
    end;
    if not v_refused then
      raise exception 'A past date was sponsored while the caller sat in %.', v_zone;
    end if;
    if v_message not ilike '%already passed%' then
      raise exception 'The past-date refusal is unreadable in %: %', v_zone, v_message;
    end if;

    -- Today in Chicago is still bookable from every seat on earth. The temple
    -- can take a sponsorship for this evening's arati.
    v_booking := public.hold_sponsorship(v_type, v_chicago_today);
    if v_booking.id is null then
      raise exception 'Today in Chicago was refused while the caller sat in %.', v_zone;
    end if;
    perform public.release_sponsorship_hold(v_booking.id);
  end loop;

  perform set_config('timezone', 'UTC', true);
end;
$$;

reset role;
reset timezone;

-- ---------------------------------------------------------------------------
-- 8. Availability does not say who booked a date.
--
--    Asha takes a date; Chandra, an ordinary devotee, asks the calendar.
--    Chandra must learn the date is gone and nothing else — not the name, not
--    the booking id, not that it is or is not hers.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'd0000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_type uuid;
  v_target date := (now() at time zone 'America/Chicago')::date + 45;
  v_booking public.sponsorship_bookings;
begin
  select ids.id into v_type from public.donation_test_ids ids where ids.key = 'garland_type';
  v_booking := public.hold_sponsorship(v_type, v_target);
  insert into public.donation_test_ids (key, id) values ('asha_secret_date', v_booking.id);
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'd0000000-0000-0000-0000-000000000004', true);
set local role authenticated;

do $$
declare
  v_type uuid;
  v_target date := (now() at time zone 'America/Chicago')::date + 45;
  v_row record;
begin
  select ids.id into v_type from public.donation_test_ids ids where ids.key = 'garland_type';

  select * into v_row
  from public.sponsorship_availability(v_target, v_target) availability
  where availability.sponsorship_type_id = v_type;

  if not v_row.is_taken then
    raise exception 'The calendar does not show Asha''s date as taken.';
  end if;
  if v_row.booked_by_name is not null then
    raise exception 'The calendar told an ordinary devotee that % booked the date.',
      v_row.booked_by_name;
  end if;
  if v_row.booking_id is not null then
    raise exception 'The calendar handed an ordinary devotee somebody else''s booking id.';
  end if;
  if v_row.is_mine then
    raise exception 'The calendar claimed somebody else''s booking belongs to Chandra.';
  end if;

  -- Nor may she reach the booking row itself.
  if exists (
    select 1 from public.sponsorship_bookings bookings
    where bookings.devotee_id = 'd0000000-0000-0000-0000-000000000002'::uuid
  ) then
    raise exception 'A devotee read another devotee''s sponsorship straight off the table.';
  end if;
end;
$$;

-- Asha sees her own booking on the same calendar; the President sees the name.
reset role;
select set_config('request.jwt.claim.sub', 'd0000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_type uuid;
  v_target date := (now() at time zone 'America/Chicago')::date + 45;
  v_row record;
begin
  select ids.id into v_type from public.donation_test_ids ids where ids.key = 'garland_type';
  select * into v_row
  from public.sponsorship_availability(v_target, v_target) availability
  where availability.sponsorship_type_id = v_type;

  if not v_row.is_mine then
    raise exception 'Asha''s own booking is not marked as hers on the calendar.';
  end if;
  if v_row.booking_id is null then
    raise exception 'Asha cannot see the id of her own booking.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'd0000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
  v_type uuid;
  v_target date := (now() at time zone 'America/Chicago')::date + 45;
  v_row record;
begin
  select ids.id into v_type from public.donation_test_ids ids where ids.key = 'garland_type';
  select * into v_row
  from public.sponsorship_availability(v_target, v_target) availability
  where availability.sponsorship_type_id = v_type;

  if v_row.booked_by_name is distinct from 'Asha Devi' then
    raise exception 'The President sees % as the sponsor rather than Asha Devi.',
      coalesce(v_row.booked_by_name, 'nobody');
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 9. A devotee cannot record a donation. Only the webhook may.
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', 'd0000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_refused boolean := false;
begin
  begin
    perform public.record_donation('forged-1', 1000000, 'one_time');
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A devotee wrote herself a donation record.';
  end if;
end;
$$;

reset role;

do $$
declare
  v_granted boolean;
  v_signature text :=
    'public.record_donation(text, integer, text, text, text, uuid, text, text, uuid, jsonb, timestamptz)';
begin
  select has_function_privilege('authenticated', v_signature, 'execute') into v_granted;
  if v_granted then
    raise exception 'record_donation is granted to authenticated.';
  end if;
  select has_function_privilege('anon', v_signature, 'execute') into v_granted;
  if v_granted then
    raise exception 'record_donation is granted to anon.';
  end if;
  select has_function_privilege('service_role', v_signature, 'execute') into v_granted;
  if not v_granted then
    raise exception 'The webhook''s service role cannot record a donation.';
  end if;
end;
$$;

-- The grant is the first lock; the check inside record_donation is the second,
-- and it is the one that matters when a later migration runs something like
-- `grant execute on all functions in schema public to authenticated`. That is
-- simulated here rather than assumed: the grant is handed over, the devotee
-- tries again, and she must still be refused by the function itself.
grant execute on function public.record_donation(
  text, integer, text, text, text, uuid, text, text, uuid, jsonb, timestamptz
) to authenticated;

select set_config('request.jwt.claim.sub', 'd0000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_refused boolean := false;
  v_message text;
begin
  begin
    perform public.record_donation('forged-2', 1000000, 'one_time');
  exception when others then
    v_refused := true;
    v_message := sqlerrm;
  end;
  if not v_refused then
    raise exception 'With execute granted, a devotee wrote herself a donation record.';
  end if;
  if v_message ilike '%permission denied%' then
    raise exception 'record_donation is defended only by its grant: %', v_message;
  end if;
  if v_message not ilike '%payment webhook%' then
    raise exception 'record_donation refused a devotee for the wrong reason: %', v_message;
  end if;
end;
$$;

reset role;

revoke execute on function public.record_donation(
  text, integer, text, text, text, uuid, text, text, uuid, jsonb, timestamptz
) from authenticated;

do $$
begin
  if has_function_privilege(
    'authenticated',
    'public.record_donation(text, integer, text, text, text, uuid, text, text, uuid, jsonb, timestamptz)',
    'execute'
  ) then
    raise exception 'record_donation was left granted to authenticated.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 10. The same webhook delivered twice records one gift, and a sponsorship
--     gift confirms its booking.
--
--     Delivered twice is the ordinary case. Zeffy retries on a timeout, and a
--     timeout after a successful write is exactly how a temple ends up
--     thanking a devotee for $702 they did not give.
-- ---------------------------------------------------------------------------

do $$
declare
  v_booking uuid;
  v_first public.donations;
  v_second public.donations;
  v_rows integer;
begin
  select ids.id into v_booking from public.donation_test_ids ids where ids.key = 'asha_secret_date';

  v_first := public.record_donation(
    p_external_payment_id := 'zeffy_pay_00001',
    p_amount_cents := 35100,
    p_kind := 'one_time',
    p_donor_email := 'don-asha@example.test',
    p_sponsorship_booking_id := v_booking,
    p_payload := '{"source":"zeffy","status":"completed"}'::jsonb
  );

  if v_first.id is null then
    raise exception 'The webhook could not record a donation.';
  end if;
  if v_first.donor_id <> 'd0000000-0000-0000-0000-000000000002'::uuid then
    raise exception 'The gift was not matched to the devotee who gave it.';
  end if;
  if v_first.amount_cents <> 35100 then
    raise exception 'The gift was recorded as % cents.', v_first.amount_cents;
  end if;

  -- The booking is now a sponsorship.
  if (select bookings.status from public.sponsorship_bookings bookings
      where bookings.id = v_booking) <> 'confirmed' then
    raise exception 'Payment arrived and the sponsorship was not confirmed.';
  end if;
  if (select bookings.held_until from public.sponsorship_bookings bookings
      where bookings.id = v_booking) is not null then
    raise exception 'A confirmed sponsorship kept its hold expiry.';
  end if;

  -- The retry.
  v_second := public.record_donation(
    p_external_payment_id := 'zeffy_pay_00001',
    p_amount_cents := 35100,
    p_kind := 'one_time',
    p_donor_email := 'don-asha@example.test',
    p_sponsorship_booking_id := v_booking,
    p_payload := '{"source":"zeffy","status":"completed","retry":true}'::jsonb
  );

  if v_second.id is distinct from v_first.id then
    raise exception 'A repeated webhook created a second donation row.';
  end if;

  select count(*)::integer into v_rows
  from public.donations where donations.external_payment_id = 'zeffy_pay_00001';
  if v_rows <> 1 then
    raise exception 'A repeated webhook left % donation rows.', v_rows;
  end if;

  -- And the constraint refuses it even when record_donation is not in the way.
  v_rows := 0;
  begin
    insert into public.donations
      (amount_cents, currency, kind, external_payment_id)
    values (35100, 'USD', 'one_time', 'zeffy_pay_00001');
  exception when unique_violation then
    v_rows := 1;
  end;
  if v_rows <> 1 then
    raise exception 'A direct insert recorded the same payment id twice.';
  end if;
end;
$$;

-- A confirmed sponsorship is not the devotee's to release.
select set_config('request.jwt.claim.sub', 'd0000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_booking uuid;
  v_refused boolean := false;
begin
  select ids.id into v_booking from public.donation_test_ids ids where ids.key = 'asha_secret_date';
  begin
    perform public.release_sponsorship_hold(v_booking);
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A confirmed sponsorship was released by the devotee.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 11. A plain donation from somebody who is not an app user at all.
-- ---------------------------------------------------------------------------

reset role;

do $$
declare
  v_gift public.donations;
begin
  v_gift := public.record_donation(
    p_external_payment_id := 'zeffy_pay_00002',
    p_amount_cents := 5000,
    p_kind := 'recurring',
    p_recurrence := 'monthly',
    p_donor_name := 'A Visiting Aunt',
    p_donor_email := 'aunt@example.test',
    p_payload := '{"source":"zeffy"}'::jsonb
  );

  if v_gift.donor_id is not null then
    raise exception 'A gift from a stranger was attached to a user row.';
  end if;
  if v_gift.recurrence <> 'monthly' then
    raise exception 'A monthly gift was recorded as %.', coalesce(v_gift.recurrence, 'null');
  end if;

  -- Bimal gives too, so there is somebody else's money for Asha to fail to see.
  -- Zeffy reports an email address and no user id, which is the ordinary case:
  -- matching it to the devotee is what turns a payment into giving history.
  v_gift := public.record_donation(
    p_external_payment_id := 'zeffy_pay_00003',
    p_amount_cents := 20100,
    p_kind := 'one_time',
    p_donor_name := 'Bimal Das',
    p_donor_email := 'DON-Bimal@Example.Test'
  );

  if v_gift.donor_id is distinct from 'd0000000-0000-0000-0000-000000000003'::uuid then
    raise exception 'A gift identified only by email was not matched to the devotee who gave it.';
  end if;
end;
$$;

-- A one-time gift must not carry a recurrence, and a recurring one must.
do $$
declare
  v_refused boolean := false;
begin
  begin
    perform public.record_donation(
      p_external_payment_id := 'zeffy_pay_bad_1',
      p_amount_cents := 1000,
      p_kind := 'recurring'
    );
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A recurring gift was recorded with no schedule.';
  end if;

  v_refused := false;
  begin
    insert into public.donations (amount_cents, kind, recurrence, external_payment_id)
    values (1000, 'one_time', 'monthly', 'zeffy_pay_bad_2');
  exception when check_violation then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A one-off gift was stored with a repeat schedule.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 12. A devotee sees her own giving and nobody else's — through the function
--     and straight off the table.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'd0000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_rows integer;
  v_total integer;
  v_row record;
begin
  select count(*)::integer, coalesce(sum(mine.amount_cents), 0)::integer
    into v_rows, v_total
  from public.list_my_donations() mine;

  if v_rows <> 1 then
    raise exception 'Asha sees % donations rather than her own one.', v_rows;
  end if;
  if v_total <> 35100 then
    raise exception 'Asha''s giving totals % cents.', v_total;
  end if;

  select * into v_row from public.list_my_donations() mine limit 1;
  if v_row.sponsorship_type_name is distinct from 'Garland' then
    raise exception 'Asha''s gift is not shown against the garland she sponsored.';
  end if;

  -- The table itself, with no function in the way.
  select count(*)::integer into v_rows from public.donations;
  if v_rows <> 1 then
    raise exception 'A devotee reads % rows straight off the donations table.', v_rows;
  end if;

  if exists (
    select 1 from public.donations
    where donations.external_payment_id in ('zeffy_pay_00002', 'zeffy_pay_00003')
  ) then
    raise exception 'A devotee read another devotee''s donation from the table.';
  end if;

  -- The whole-congregation reports are empty for her, not an error.
  select count(*)::integer into v_rows from public.list_all_donations(null, null);
  if v_rows <> 0 then
    raise exception 'list_all_donations gave a devotee % rows.', v_rows;
  end if;

  select count(*)::integer into v_rows from public.list_all_sponsorships();
  if v_rows <> 0 then
    raise exception 'list_all_sponsorships gave a devotee % rows.', v_rows;
  end if;

  -- Her own sponsorships are hers to see.
  select count(*)::integer into v_rows
  from public.list_my_sponsorships() mine where mine.status = 'confirmed';
  if v_rows <> 1 then
    raise exception 'Asha sees % confirmed sponsorships rather than one.', v_rows;
  end if;

  -- The raw webhook payload is granted to nobody.
  v_rows := 0;
  begin
    select count(*)::integer into v_rows from public.donations d where d.payload is not null;
  exception when insufficient_privilege then
    v_rows := -1;
  end;
  if v_rows <> -1 then
    raise exception 'A devotee can read the raw webhook payload.';
  end if;
end;
$$;

-- Chandra gave nothing and must see nothing at all.
reset role;
select set_config('request.jwt.claim.sub', 'd0000000-0000-0000-0000-000000000004', true);
set local role authenticated;

do $$
declare
  v_rows integer;
  v_asha_booking uuid;
begin
  select count(*)::integer into v_rows from public.list_my_donations();
  if v_rows <> 0 then
    raise exception 'A devotee who gave nothing sees % donations.', v_rows;
  end if;

  select count(*)::integer into v_rows from public.donations;
  if v_rows <> 0 then
    raise exception 'A devotee who gave nothing reads % donation rows.', v_rows;
  end if;

  -- Chandra has held and released dates of her own, so her sponsorship list is
  -- not empty. What it must not contain is Asha's.
  select ids.id into v_asha_booking
  from public.donation_test_ids ids where ids.key = 'asha_secret_date';

  if exists (
    select 1 from public.list_my_sponsorships() mine where mine.id = v_asha_booking
  ) then
    raise exception 'A devotee''s sponsorship list contains somebody else''s sponsorship.';
  end if;

  -- Nor may she change the sponsorship list.
  v_rows := 0;
  begin
    perform public.save_sponsorship_type('Free Garland', 1);
  exception when others then
    v_rows := 1;
  end;
  if v_rows <> 1 then
    raise exception 'A devotee added a sponsorship type.';
  end if;

  v_rows := 0;
  begin
    update public.sponsorship_types set amount_cents = 1;
  exception when others then
    v_rows := 1;
  end;
  if v_rows <> 1 then
    raise exception 'A devotee repriced the sponsorship list straight off the table.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 13. The President sees everything, and may edit the list.
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', 'd0000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
  v_rows integer;
  v_total integer;
  v_saved public.sponsorship_types;
  v_today date := (now() at time zone 'America/Chicago')::date;
begin
  select count(*)::integer, coalesce(sum(all_gifts.amount_cents), 0)::integer
    into v_rows, v_total
  from public.list_all_donations(null, null) all_gifts;

  if v_rows <> 3 then
    raise exception 'The President sees % donations rather than all three.', v_rows;
  end if;
  if v_total <> 60200 then
    raise exception 'The President''s total is % cents rather than 60200.', v_total;
  end if;

  -- The stranger's contact details are the temple's to hold.
  if not exists (
    select 1 from public.list_all_donations(null, null) all_gifts
    where all_gifts.donor_email = 'aunt@example.test'
  ) then
    raise exception 'The President cannot see who a non-app donor was.';
  end if;

  -- The window is in Chicago dates, and everything was received just now.
  select count(*)::integer into v_rows
  from public.list_all_donations(v_today, v_today);
  if v_rows <> 3 then
    raise exception 'Today''s window found % of the three gifts received today.', v_rows;
  end if;

  select count(*)::integer into v_rows
  from public.list_all_donations(v_today + 1, v_today + 2);
  if v_rows <> 0 then
    raise exception 'A future window found % gifts.', v_rows;
  end if;

  -- Sponsorships, all of them, with the sponsor named.
  if not exists (
    select 1 from public.list_all_sponsorships() all_sponsorships
    where all_sponsorships.devotee_name = 'Asha Devi'
      and all_sponsorships.status = 'confirmed'
  ) then
    raise exception 'The President cannot see Asha''s confirmed sponsorship.';
  end if;

  -- And the list is the President's to change.
  v_saved := public.save_sponsorship_type('Tulasi Offering', 5100);
  if v_saved.amount_cents <> 5100 then
    raise exception 'A new sponsorship type saved at % cents.', v_saved.amount_cents;
  end if;

  v_saved := public.save_sponsorship_type(
    p_name := 'Tulasi Offering',
    p_amount_cents := 6100,
    p_id := v_saved.id,
    p_is_active := false
  );
  if v_saved.amount_cents <> 6100 or v_saved.is_active then
    raise exception 'Editing a sponsorship type did not take.';
  end if;

  -- A switched-off type stays visible to the President and vanishes for
  -- everybody else.
  if not exists (
    select 1 from public.list_sponsorship_types() types
    where types.name = 'Tulasi Offering'
  ) then
    raise exception 'The President cannot see a type they switched off.';
  end if;

  -- Handed on so the next section can try to book it by id. A devotee cannot
  -- read the row to find the id herself — which is the policy working, not the
  -- booking rule, and the two must be tested apart.
  insert into public.donation_test_ids (key, id) values ('tulasi_type', v_saved.id);
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'd0000000-0000-0000-0000-000000000004', true);
set local role authenticated;

do $$
declare
  v_type uuid;
  v_refused boolean := false;
  v_message text;
begin
  if exists (
    select 1 from public.list_sponsorship_types() types
    where types.name = 'Tulasi Offering'
  ) then
    raise exception 'A devotee is offered a sponsorship that was switched off.';
  end if;

  -- The id comes from the President's hand, not from a read of the table, so
  -- that this really tests the booking rule rather than re-testing the policy.
  select ids.id into v_type from public.donation_test_ids ids where ids.key = 'tulasi_type';
  if v_type is null then
    raise exception 'The switched-off type was never handed over to test with.';
  end if;

  begin
    perform public.hold_sponsorship(
      v_type, (now() at time zone 'America/Chicago')::date + 3
    );
  exception when others then
    v_refused := true;
    v_message := sqlerrm;
  end;
  if not v_refused then
    raise exception 'A devotee sponsored a type that is not being offered.';
  end if;
  if v_message not ilike '%not being offered%' then
    raise exception 'A switched-off type was refused for the wrong reason: %', v_message;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 14. Nothing here is reachable anonymously, and no write is granted on any of
--     the three tables.
-- ---------------------------------------------------------------------------

reset role;

do $$
declare
  v_function text;
  v_table text;
  v_privilege text;
begin
  for v_function in
    select p.oid::regprocedure::text
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in (
        'list_sponsorship_types', 'sponsorship_availability', 'hold_sponsorship',
        'release_sponsorship_hold', 'record_donation', 'list_my_donations',
        'list_all_donations', 'list_my_sponsorships', 'list_all_sponsorships',
        'release_expired_sponsorship_holds', 'save_sponsorship_type',
        'may_view_all_giving', 'is_backend_caller'
      )
      and has_function_privilege('anon', p.oid, 'execute')
  loop
    raise exception 'anon can execute %.', v_function;
  end loop;

  foreach v_table in array
    array['public.sponsorship_types', 'public.sponsorship_bookings', 'public.donations']
  loop
    foreach v_privilege in array array['insert', 'update', 'delete', 'truncate'] loop
      if has_table_privilege('authenticated', v_table, v_privilege) then
        raise exception 'authenticated holds % on %.', v_privilege, v_table;
      end if;
      if has_table_privilege('anon', v_table, v_privilege) then
        raise exception 'anon holds % on %.', v_privilege, v_table;
      end if;
    end loop;
    if has_table_privilege('anon', v_table, 'select') then
      raise exception 'anon can read %.', v_table;
    end if;
    if not (
      select relrowsecurity from pg_class where oid = v_table::regclass
    ) then
      raise exception 'Row level security is off on %.', v_table;
    end if;
  end loop;

  if has_column_privilege('authenticated', 'public.donations', 'payload', 'select') then
    raise exception 'authenticated can select the raw webhook payload.';
  end if;
end;
$$;

do $$
begin
  raise notice 'all donation checks passed';
end;
$$;

select 'donations verification passed' as result;

rollback;
