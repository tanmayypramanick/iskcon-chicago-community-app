-- Functional verification for 202608040049_donation_reconciliation.sql.
--
-- Rolled back at the end. Every local is prefixed v_ so it can never shadow a
-- column name. Anything that must be refused is attempted as the person who
-- would really attempt it, under `set local role authenticated`, so the row
-- level security policies and the grants are what is being tested rather than
-- superuser rights quietly waving everything through. Anything the webhook
-- would do is done with the role reset, because record_donation is the service
-- role's alone.
--
-- The people in this script:
--   President  ...0001  holds app.view_all; owns the unmatched queue
--   Asha       ...0002  pays exactly what she held. The happy path.
--   Bimal      ...0003  holds two identically priced sevas and pays once
--   Chandra    ...0004  pays $500 for a $551 sponsorship
--   Deva       ...0005  held a date three hours before he paid
--   Eshan      ...0006  let his hold lapse before the card cleared
--
-- The claims this script exists to prove:
--
--   1. A payment that fits exactly one open hold by email and amount confirms
--      that sponsorship, and nothing else.
--   2. A payment that fits none is recorded, not lost, and reaches the queue.
--   3. A payment that fits several is recorded unmatched. Nothing is confirmed.
--      Guessing is the one outcome that is never acceptable.
--   4. An amount that differs from the price is stored with both numbers and
--      the difference between them, visible on the President's screen.
--   5. The President can settle one by hand. A devotee cannot.
--   6. A Sunday Feast is refused on a Monday and accepted on a Sunday, and the
--      answer does not change with the caller's timezone.
--   7. A gift with no sponsorship behind it still records perfectly well.
--   8. The same Zeffy payment id delivered twice is one gift.
--
-- The final row must read: donation reconciliation verification passed

begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('e0000000-0000-0000-0000-000000000001', 'rec-president@example.test', '{"name":"Rec President"}'),
  ('e0000000-0000-0000-0000-000000000002', 'rec-asha@example.test', '{"name":"Asha Devi"}'),
  ('e0000000-0000-0000-0000-000000000003', 'rec-bimal@example.test', '{"name":"Bimal Das"}'),
  ('e0000000-0000-0000-0000-000000000004', 'rec-chandra@example.test', '{"name":"Chandra Devi"}'),
  ('e0000000-0000-0000-0000-000000000005', 'rec-deva@example.test', '{"name":"Deva Das"}'),
  ('e0000000-0000-0000-0000-000000000006', 'rec-eshan@example.test', '{"name":"Eshan Das"}');

update public.users
set role_id = (select roles.id from public.roles where roles.name = 'president')
where email = 'rec-president@example.test';

-- An ordinary table, not a temporary one, so reading it under the authenticated
-- role needs no assumptions about the temp schema. The whole script is rolled
-- back, so it never outlives the transaction.
create table public.reconciliation_ids (key text primary key, id uuid not null);
grant select, insert, update on public.reconciliation_ids to authenticated;

create table public.reconciliation_dates (key text primary key, on_date date not null);
grant select, insert on public.reconciliation_dates to authenticated;

-- Every date this script uses, decided once, in Chicago. v_sunday is always the
-- next Sunday strictly ahead of today, so no case ever collides with the
-- past-date refusal 202608040048 already owns.
do $$
declare
  v_today date := (now() at time zone 'America/Chicago')::date;
  v_sunday date;
begin
  v_sunday := v_today + (7 - (extract(isodow from v_today)::integer % 7));

  if extract(isodow from v_sunday) <> 7 then
    raise exception 'The script computed % as a Sunday and it is not one.', v_sunday;
  end if;
  if v_sunday <= v_today then
    raise exception 'The script computed a Sunday that is not in the future.';
  end if;

  insert into public.reconciliation_dates (key, on_date) values
    ('sunday_tz_loop',   v_sunday),
    ('monday_refused',   v_sunday + 1),
    ('sunday_asha',      v_sunday + 7),
    ('sunday_chandra',   v_sunday + 14),
    ('sunday_deva',      v_sunday + 21),
    ('sunday_eshan',     v_sunday + 28),
    ('sunday_cancelled', v_sunday + 35),
    ('twins',            v_today + 40);
end;
$$;

-- ---------------------------------------------------------------------------
-- 1. The shape of what was added.
--
--    Asserted one column and one seed at a time rather than as a count, because
--    a count passes when Sunday Feast is flagged and Garland is flagged too,
--    and a Garland that can only be sponsored on Sundays is a bug nobody would
--    notice until a devotee complained.
-- ---------------------------------------------------------------------------

do $$
declare
  v_row record;
  v_generated char;
  v_window interval;
  v_constraint text;
begin
  -- Exactly the two Sunday Feast rows are Sunday-only.
  for v_row in
    select sponsorship_types.name, sponsorship_types.sunday_only
    from public.sponsorship_types
    where sponsorship_types.sunday_only
      <> (sponsorship_types.name in ('Sunday Feast', 'Sunday Feast (higher)'))
  loop
    raise exception '% has sunday_only = %, which is not what the temple asked for.',
      v_row.name, v_row.sunday_only;
  end loop;

  -- The one Zeffy page that exists.
  select * into v_row
  from public.sponsorship_types
  where sponsorship_types.name = 'Sunday Feast';

  if v_row.zeffy_campaign_slug is distinct from 'sunday-feast-sponsorship' then
    raise exception 'Sunday Feast points at Zeffy campaign %.',
      coalesce(v_row.zeffy_campaign_slug, 'nothing');
  end if;
  if v_row.zeffy_campaign_url is null
     or v_row.zeffy_campaign_url not like '%sunday-feast-sponsorship%' then
    raise exception 'Sunday Feast has no usable Zeffy URL: %',
      coalesce(v_row.zeffy_campaign_url, 'null');
  end if;

  -- When this file was written, Sunday Feast was the only page the temple had
  -- made, and this asserted every other row was blank. The temple has since
  -- created all seven campaigns in 202608040050_sponsorship_campaigns.sql, and
  -- which slug belongs on which row is that migration's claim to prove — see
  -- supabase/verification/sponsorship_campaigns.sql.
  --
  -- What survives here is the reason the assertion existed at all: a URL that
  -- does not lead to its own campaign sends a devotee to pay for the wrong
  -- thing, which is worse than a button that is not there.
  if exists (
    select 1 from public.sponsorship_types
    where (sponsorship_types.zeffy_campaign_slug is null)
       <> (sponsorship_types.zeffy_campaign_url is null)
  ) then
    raise exception 'A sponsorship has a Zeffy slug without a URL, or a URL without a slug.';
  end if;

  if exists (
    select 1 from public.sponsorship_types
    where sponsorship_types.zeffy_campaign_slug is not null
      and sponsorship_types.zeffy_campaign_url
          not like '%' || sponsorship_types.zeffy_campaign_slug
  ) then
    raise exception 'A sponsorship''s Zeffy URL does not lead to its own campaign.';
  end if;

  -- A campaign must still price a payment unambiguously. 0049 spelt that as
  -- one row per slug; 202608040050_sponsorship_campaigns.sql relaxed it to one
  -- row per slug and amount, because the Sunday Feast turned out to be two
  -- rates on one page. The promise is unchanged and is what is asserted: given
  -- a campaign and an amount, the webhook finds exactly one sponsorship.
  if not exists (
    select 1 from pg_indexes
    where schemaname = 'public'
      and indexname = 'sponsorship_types_zeffy_slug_amount_key'
      and indexdef ilike 'CREATE UNIQUE INDEX%'
  ) then
    raise exception 'Two sponsorships could share one Zeffy campaign slug at one price.';
  end if;

  -- The reconciliation arithmetic must be the database's, not a caller's.
  foreach v_constraint in array array['amount_matches', 'amount_difference_cents'] loop
    select attgenerated into v_generated
    from pg_attribute
    where attrelid = 'public.donations'::regclass
      and attname = v_constraint;
    if coalesce(v_generated, ' ') <> 's' then
      raise exception 'donations.% is not a generated column, so it can drift from the amounts.',
        v_constraint;
    end if;
  end loop;

  -- And the constraints that keep the four states honest.
  foreach v_constraint in array array[
    'donation_match_status_known', 'donation_unmatched_reason_known',
    'donation_reason_matches_status', 'donation_settled_has_booking',
    'donation_general_has_no_booking'
  ] loop
    if not exists (select 1 from pg_constraint where conname = v_constraint) then
      raise exception 'The % constraint is missing.', v_constraint;
    end if;
  end loop;

  select public.zeffy_match_window() into v_window;
  if v_window <> interval '2 hours' then
    raise exception 'The match window is % rather than two hours.', v_window;
  end if;
end;
$$;

-- The generated columns cannot be written, by anybody, ever.
do $$
declare
  v_refused boolean := false;
begin
  begin
    update public.donations set amount_matches = true;
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'amount_matches can be written by hand.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. A Sunday Feast is a Sunday's, from every seat on earth.
--
--    The likeliest mistakes are extract(dow ...) confused with isodow, which
--    makes every Sunday fail, and evaluating the weekday through a timestamptz,
--    which reads the caller's own timezone and slides the date onto the day
--    before. Asking from session timezones spanning UTC-12 to UTC+14 catches
--    the second: at least one of them is always on a different calendar day
--    from Chicago.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'e0000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_feast uuid;
  v_feast_high uuid;
  v_garland uuid;
  v_sunday date;
  v_monday date;
  v_zone text;
  v_refused boolean;
  v_message text;
  v_booking public.sponsorship_bookings;
begin
  select types.id into v_feast from public.sponsorship_types types where types.name = 'Sunday Feast';
  select types.id into v_feast_high from public.sponsorship_types types
    where types.name = 'Sunday Feast (higher)';
  select types.id into v_garland from public.sponsorship_types types where types.name = 'Garland';

  select dates.on_date into v_sunday from public.reconciliation_dates dates
    where dates.key = 'sunday_tz_loop';
  select dates.on_date into v_monday from public.reconciliation_dates dates
    where dates.key = 'monday_refused';

  foreach v_zone in array
    array['UTC', 'Pacific/Kiritimati', 'Etc/GMT+12', 'Asia/Tokyo', 'America/Chicago']
  loop
    perform set_config('timezone', v_zone, true);

    -- A Monday is refused, and refused in a sentence a devotee can act on.
    v_refused := false;
    begin
      perform public.hold_sponsorship(v_feast, v_monday);
    exception when others then
      v_refused := true;
      v_message := sqlerrm;
    end;
    if not v_refused then
      raise exception 'The Sunday Feast was booked on a Monday from %.', v_zone;
    end if;
    if v_message not ilike '%only offered on Sundays%' then
      raise exception 'The Monday refusal is unreadable in %: %', v_zone, v_message;
    end if;

    -- The higher-priced Sunday Feast is the same seva and obeys the same rule.
    v_refused := false;
    begin
      perform public.hold_sponsorship(v_feast_high, v_monday);
    exception when others then
      v_refused := true;
    end;
    if not v_refused then
      raise exception 'Sunday Feast (higher) was booked on a Monday from %.', v_zone;
    end if;

    -- The Sunday is accepted from that same seat.
    v_booking := public.hold_sponsorship(v_feast, v_sunday);
    if v_booking.id is null then
      raise exception 'A Sunday was refused while the caller sat in %.', v_zone;
    end if;
    if v_booking.amount_cents <> 55100 then
      raise exception 'The Sunday Feast hold recorded % cents.', v_booking.amount_cents;
    end if;
    perform public.release_sponsorship_hold(v_booking.id);

    -- And the rule belongs to the Sunday Feast alone: a garland is a garland
    -- on a Monday.
    v_booking := public.hold_sponsorship(v_garland, v_monday);
    if v_booking.id is null then
      raise exception 'A garland was refused on a Monday from %.', v_zone;
    end if;
    perform public.release_sponsorship_hold(v_booking.id);
  end loop;

  perform set_config('timezone', 'UTC', true);
end;
$$;

reset role;
reset timezone;

-- The calendar stops offering the day before the tap is refused.
select set_config('request.jwt.claim.sub', 'e0000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_sunday date;
  v_monday date;
begin
  select dates.on_date into v_sunday from public.reconciliation_dates dates
    where dates.key = 'sunday_tz_loop';
  select dates.on_date into v_monday from public.reconciliation_dates dates
    where dates.key = 'monday_refused';

  if exists (
    select 1 from public.sponsorship_availability(v_monday, v_monday) calendar
    where calendar.type_name = 'Sunday Feast'
  ) then
    raise exception 'The calendar offers the Sunday Feast on a Monday.';
  end if;

  if not exists (
    select 1 from public.sponsorship_availability(v_sunday, v_sunday) calendar
    where calendar.type_name = 'Sunday Feast'
  ) then
    raise exception 'The calendar does not offer the Sunday Feast on a Sunday.';
  end if;

  -- Everything else is on the calendar both days.
  if not exists (
    select 1 from public.sponsorship_availability(v_monday, v_monday) calendar
    where calendar.type_name = 'Garland'
  ) then
    raise exception 'The Sunday rule swallowed the garland.';
  end if;

  -- And the app can find out where to pay.
  if not exists (
    select 1 from public.list_sponsorship_types() types
    where types.name = 'Sunday Feast'
      and types.sunday_only
      and types.zeffy_campaign_url like '%sunday-feast-sponsorship%'
  ) then
    raise exception 'The sponsorship list does not tell the app where to pay for a Sunday Feast.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Everybody takes their date. This is the state the webhooks arrive into.
-- ---------------------------------------------------------------------------

-- Asha holds a Sunday Feast and will pay exactly its price.
reset role;
select set_config('request.jwt.claim.sub', 'e0000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_booking public.sponsorship_bookings;
begin
  v_booking := public.hold_sponsorship(
    (select types.id from public.sponsorship_types types where types.name = 'Sunday Feast'),
    (select dates.on_date from public.reconciliation_dates dates where dates.key = 'sunday_asha')
  );
  insert into public.reconciliation_ids (key, id) values ('asha_feast', v_booking.id);
end;
$$;

-- Chandra holds one too, and will pay $500 for it.
reset role;
select set_config('request.jwt.claim.sub', 'e0000000-0000-0000-0000-000000000004', true);
set local role authenticated;

do $$
declare
  v_booking public.sponsorship_bookings;
begin
  v_booking := public.hold_sponsorship(
    (select types.id from public.sponsorship_types types where types.name = 'Sunday Feast'),
    (select dates.on_date from public.reconciliation_dates dates where dates.key = 'sunday_chandra')
  );
  insert into public.reconciliation_ids (key, id) values ('chandra_feast', v_booking.id);
end;
$$;

reset role;

-- Two sevas at one price, so Bimal can hold both and make the matching rule
-- genuinely ambiguous. Inserted directly because the point is the ambiguity,
-- not the President's form.
insert into public.sponsorship_types (name, amount_cents, display_order)
values ('Verify Twin A', 44400, 900), ('Verify Twin B', 44400, 910);

select set_config('request.jwt.claim.sub', 'e0000000-0000-0000-0000-000000000003', true);
set local role authenticated;

do $$
declare
  v_a public.sponsorship_bookings;
  v_b public.sponsorship_bookings;
  v_on date;
begin
  select dates.on_date into v_on from public.reconciliation_dates dates where dates.key = 'twins';

  v_a := public.hold_sponsorship(
    (select types.id from public.sponsorship_types types where types.name = 'Verify Twin A'), v_on);
  v_b := public.hold_sponsorship(
    (select types.id from public.sponsorship_types types where types.name = 'Verify Twin B'), v_on);

  insert into public.reconciliation_ids (key, id)
  values ('bimal_twin_a', v_a.id), ('bimal_twin_b', v_b.id);
end;
$$;

reset role;

-- Deva held his date three hours before he paid: outside the window, still
-- live. Eshan's hold lapsed a minute before the card cleared. Both are inserted
-- directly, because hold_sponsorship will not create a hold that is already old
-- or already expired — which is exactly why those two states have to be built
-- by hand to be tested at all.
do $$
declare
  v_feast uuid;
  v_id uuid;
begin
  select types.id into v_feast from public.sponsorship_types types where types.name = 'Sunday Feast';

  insert into public.sponsorship_bookings
    (sponsorship_type_id, devotee_id, on_date, status, held_until, amount_cents, created_at)
  values (
    v_feast, 'e0000000-0000-0000-0000-000000000005',
    (select dates.on_date from public.reconciliation_dates dates where dates.key = 'sunday_deva'),
    'held', now() + interval '30 minutes', 55100, now() - interval '3 hours'
  )
  returning id into v_id;
  insert into public.reconciliation_ids (key, id) values ('deva_feast', v_id);

  insert into public.sponsorship_bookings
    (sponsorship_type_id, devotee_id, on_date, status, held_until, amount_cents, created_at)
  values (
    v_feast, 'e0000000-0000-0000-0000-000000000006',
    (select dates.on_date from public.reconciliation_dates dates where dates.key = 'sunday_eshan'),
    'held', now() - interval '1 minute', 55100, now()
  )
  returning id into v_id;
  insert into public.reconciliation_ids (key, id) values ('eshan_feast', v_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. The happy path. One open hold, one payment, one confirmed sponsorship.
--
--    Nothing about the booking is passed in. The webhook knows an email, an
--    amount, a campaign and a moment, and that has to be enough.
-- ---------------------------------------------------------------------------

do $$
declare
  v_gift public.donations;
  v_booking uuid;
begin
  select ids.id into v_booking from public.reconciliation_ids ids where ids.key = 'asha_feast';

  v_gift := public.record_donation(
    p_external_payment_id := 'zeffy_rec_asha',
    p_amount_cents := 55100,
    p_kind := 'one_time',
    p_donor_name := 'Asha Devi',
    p_donor_email := 'REC-Asha@Example.Test',
    p_payload := '{"source":"zeffy","campaign_slug":"sunday-feast-sponsorship"}'::jsonb
  );

  if v_gift.id is null then
    raise exception 'The webhook could not record Asha''s payment.';
  end if;
  if v_gift.match_status <> 'matched' then
    raise exception 'Asha''s payment was recorded as % rather than matched.', v_gift.match_status;
  end if;
  if v_gift.sponsorship_booking_id is distinct from v_booking then
    raise exception 'Asha''s payment was tied to the wrong booking.';
  end if;
  if v_gift.donor_id is distinct from 'e0000000-0000-0000-0000-000000000002'::uuid then
    raise exception 'Asha''s payment was not matched to Asha.';
  end if;
  if v_gift.unmatched_reason is not null then
    raise exception 'A matched gift carries the reason %.', v_gift.unmatched_reason;
  end if;

  -- The temple's requirement, on the happy path: both numbers, and they agree.
  if v_gift.amount_cents <> 55100 or v_gift.expected_amount_cents <> 55100 then
    raise exception 'Asha''s gift recorded % against an expected %.',
      v_gift.amount_cents, coalesce(v_gift.expected_amount_cents, -1);
  end if;
  if v_gift.amount_matches is not true then
    raise exception 'An exactly-priced gift did not report as matching.';
  end if;
  if v_gift.amount_difference_cents <> 0 then
    raise exception 'An exactly-priced gift reports a difference of %.',
      v_gift.amount_difference_cents;
  end if;
  if v_gift.zeffy_campaign_slug is distinct from 'sunday-feast-sponsorship' then
    raise exception 'The campaign the money came through was not recorded.';
  end if;
  if v_gift.matched_at is null then
    raise exception 'A matched gift has no matched_at.';
  end if;

  -- And the date is now really hers.
  if (select bookings.status from public.sponsorship_bookings bookings
      where bookings.id = v_booking) <> 'confirmed' then
    raise exception 'Payment arrived and Asha''s sponsorship was not confirmed.';
  end if;
  if (select bookings.held_until from public.sponsorship_bookings bookings
      where bookings.id = v_booking) is not null then
    raise exception 'A confirmed sponsorship kept its hold expiry.';
  end if;
end;
$$;

-- The same delivery again. Zeffy retries on a timeout, and half of all timeouts
-- happen after the work was done.
do $$
declare
  v_again public.donations;
  v_rows integer;
begin
  v_again := public.record_donation(
    p_external_payment_id := 'zeffy_rec_asha',
    p_amount_cents := 55100,
    p_kind := 'one_time',
    p_donor_email := 'rec-asha@example.test',
    p_payload := '{"source":"zeffy","campaign_slug":"sunday-feast-sponsorship","retry":true}'::jsonb
  );

  select count(*)::integer into v_rows
  from public.donations where donations.external_payment_id = 'zeffy_rec_asha';
  if v_rows <> 1 then
    raise exception 'A repeated Zeffy payment id left % donation rows.', v_rows;
  end if;
  if v_again.match_status <> 'matched' then
    raise exception 'The retry rewrote the gift as %.', v_again.match_status;
  end if;
  if v_again.payload ? 'retry' then
    raise exception 'The retry overwrote the payload the first delivery recorded.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Several holds fit. Nothing is confirmed.
--
--    This is the case the whole design turns on. Bimal is holding two sevas at
--    exactly $444 and has paid $444 once. Either booking is a plausible answer,
--    which is precisely why neither may be chosen: confirming the wrong one
--    takes a date off the calendar that nobody paid for, and tells the devotee
--    who did pay that their day is gone.
-- ---------------------------------------------------------------------------

do $$
declare
  v_gift public.donations;
  v_a uuid;
  v_b uuid;
begin
  select ids.id into v_a from public.reconciliation_ids ids where ids.key = 'bimal_twin_a';
  select ids.id into v_b from public.reconciliation_ids ids where ids.key = 'bimal_twin_b';

  v_gift := public.record_donation(
    p_external_payment_id := 'zeffy_rec_bimal',
    p_amount_cents := 44400,
    p_kind := 'one_time',
    p_donor_email := 'rec-bimal@example.test'
  );

  if v_gift.id is null then
    raise exception 'An ambiguous payment was not recorded at all.';
  end if;
  if v_gift.match_status <> 'unmatched' then
    raise exception 'An ambiguous payment was recorded as %.', v_gift.match_status;
  end if;
  if v_gift.unmatched_reason <> 'several_candidates' then
    raise exception 'An ambiguous payment was set aside for the reason %.',
      coalesce(v_gift.unmatched_reason, 'null');
  end if;
  if v_gift.sponsorship_booking_id is not null then
    raise exception 'An ambiguous payment was attached to a booking anyway.';
  end if;

  if (select bookings.status from public.sponsorship_bookings bookings where bookings.id = v_a)
     <> 'held'
     or (select bookings.status from public.sponsorship_bookings bookings where bookings.id = v_b)
     <> 'held' then
    raise exception 'An ambiguous payment confirmed one of the two sevas it might have been for.';
  end if;

  -- The money is still the temple's and still Bimal's giving history.
  if v_gift.donor_id is distinct from 'e0000000-0000-0000-0000-000000000003'::uuid then
    raise exception 'An unmatched payment lost the devotee who made it.';
  end if;
  if v_gift.amount_cents <> 44400 then
    raise exception 'An unmatched payment recorded % cents.', v_gift.amount_cents;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. $500 paid for a $551 sponsorship.
--
--    The temple asked for this one in as many words: the amount from Zeffy and
--    the amount expected must both be in the app and must be comparable. It is
--    neither silently accepted — the seva is not confirmed — nor silently
--    rejected — the money is recorded to the cent.
-- ---------------------------------------------------------------------------

do $$
declare
  v_gift public.donations;
  v_booking uuid;
begin
  select ids.id into v_booking from public.reconciliation_ids ids where ids.key = 'chandra_feast';

  v_gift := public.record_donation(
    p_external_payment_id := 'zeffy_rec_chandra',
    p_amount_cents := 50000,
    p_kind := 'one_time',
    p_donor_email := 'rec-chandra@example.test',
    p_payload := '{"source":"zeffy","campaign_slug":"sunday-feast-sponsorship"}'::jsonb
  );

  if v_gift.match_status <> 'unmatched' then
    raise exception 'A short payment was recorded as %.', v_gift.match_status;
  end if;
  if v_gift.unmatched_reason <> 'amount_mismatch' then
    raise exception 'A short payment was set aside for the reason %.',
      coalesce(v_gift.unmatched_reason, 'null');
  end if;
  if v_gift.amount_cents <> 50000 then
    raise exception 'What Zeffy charged was not stored verbatim: % cents.', v_gift.amount_cents;
  end if;
  if v_gift.expected_amount_cents is distinct from 55100 then
    raise exception 'The expected price was recorded as %.',
      coalesce(v_gift.expected_amount_cents, -1);
  end if;
  if v_gift.amount_matches is not false then
    raise exception 'A short payment reports amount_matches = %.',
      coalesce(v_gift.amount_matches::text, 'null');
  end if;
  if v_gift.amount_difference_cents <> -5100 then
    raise exception 'A $51 shortfall reads as % cents.', v_gift.amount_difference_cents;
  end if;

  -- Nothing was confirmed on a short payment.
  if (select bookings.status from public.sponsorship_bookings bookings
      where bookings.id = v_booking) <> 'held' then
    raise exception 'A short payment confirmed the sponsorship anyway.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Two holds that must not match: one too old, one already lapsed.
--
--    Both payments name the Sunday Feast campaign, so both reach the queue with
--    the campaign's price against them rather than being written off as plain
--    gifts. The amounts agree; it is the holds that do not.
-- ---------------------------------------------------------------------------

do $$
declare
  v_gift public.donations;
  v_deva uuid;
  v_eshan uuid;
begin
  select ids.id into v_deva from public.reconciliation_ids ids where ids.key = 'deva_feast';
  select ids.id into v_eshan from public.reconciliation_ids ids where ids.key = 'eshan_feast';

  -- Held three hours ago: outside zeffy_match_window().
  v_gift := public.record_donation(
    p_external_payment_id := 'zeffy_rec_deva',
    p_amount_cents := 55100,
    p_kind := 'one_time',
    p_donor_email := 'rec-deva@example.test',
    p_payload := '{"source":"zeffy","campaign_slug":"sunday-feast-sponsorship"}'::jsonb
  );

  if v_gift.match_status <> 'unmatched' or v_gift.unmatched_reason <> 'no_candidate' then
    raise exception 'A hold from three hours earlier was treated as % / %.',
      v_gift.match_status, coalesce(v_gift.unmatched_reason, 'null');
  end if;
  if (select bookings.status from public.sponsorship_bookings bookings
      where bookings.id = v_deva) <> 'held' then
    raise exception 'A stale hold was confirmed by a later payment.';
  end if;
  -- The campaign still tells us what it should have cost.
  if v_gift.expected_amount_cents is distinct from 55100 then
    raise exception 'A payment on the Sunday Feast page recorded no expected price.';
  end if;
  if v_gift.amount_matches is not true then
    raise exception 'A correctly priced payment reports a mismatch.';
  end if;

  -- Lapsed before the card cleared.
  v_gift := public.record_donation(
    p_external_payment_id := 'zeffy_rec_eshan',
    p_amount_cents := 55100,
    p_kind := 'one_time',
    p_donor_email := 'rec-eshan@example.test',
    p_payload := '{"source":"zeffy","campaign_slug":"sunday-feast-sponsorship"}'::jsonb
  );

  if v_gift.match_status <> 'unmatched' or v_gift.unmatched_reason <> 'no_candidate' then
    raise exception 'An expired hold was treated as % / %.',
      v_gift.match_status, coalesce(v_gift.unmatched_reason, 'null');
  end if;
  if (select bookings.status from public.sponsorship_bookings bookings
      where bookings.id = v_eshan) <> 'held' then
    raise exception 'An expired hold was confirmed by a payment that arrived after it.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. A gift with no sponsorship behind it.
--
--    A visiting devotee's aunt gives $50 a month through the temple's general
--    Zeffy page. There is no booking, there is no campaign we know, there is
--    nothing to reconcile, and none of that is a problem: it is recorded, it is
--    complete, and it must never appear in a queue of things to fix.
-- ---------------------------------------------------------------------------

do $$
declare
  v_gift public.donations;
begin
  v_gift := public.record_donation(
    p_external_payment_id := 'zeffy_rec_general',
    p_amount_cents := 5000,
    p_kind := 'recurring',
    p_recurrence := 'monthly',
    p_donor_name := 'A Visiting Aunt',
    p_donor_email := 'rec-aunt@example.test',
    p_payload := '{"source":"zeffy"}'::jsonb
  );

  if v_gift.id is null then
    raise exception 'A general donation was not recorded.';
  end if;
  if v_gift.match_status <> 'general' then
    raise exception 'A general donation was recorded as %.', v_gift.match_status;
  end if;
  if v_gift.sponsorship_booking_id is not null then
    raise exception 'A general donation acquired a sponsorship booking.';
  end if;
  if v_gift.unmatched_reason is not null then
    raise exception 'A general donation was given the reason %.', v_gift.unmatched_reason;
  end if;
  if v_gift.expected_amount_cents is not null then
    raise exception 'A general donation was measured against an expected price.';
  end if;
  if v_gift.amount_matches is not null then
    raise exception 'A general donation reports amount_matches = %.', v_gift.amount_matches;
  end if;
  if v_gift.recurrence <> 'monthly' then
    raise exception 'A monthly gift was recorded as %.', coalesce(v_gift.recurrence, 'null');
  end if;
  if v_gift.donor_id is not null then
    raise exception 'A gift from a stranger was attached to a user row.';
  end if;
end;
$$;

-- A devotee who happens to have a live hold, giving generally: no campaign, no
-- matching amount, nothing taken off the calendar.
do $$
declare
  v_gift public.donations;
  v_booking uuid;
begin
  select ids.id into v_booking from public.reconciliation_ids ids where ids.key = 'chandra_feast';

  v_gift := public.record_donation(
    p_external_payment_id := 'zeffy_rec_chandra_extra',
    p_amount_cents := 2100,
    p_kind := 'one_time',
    p_donor_email := 'rec-chandra@example.test'
  );

  if v_gift.match_status <> 'unmatched' or v_gift.unmatched_reason <> 'amount_mismatch' then
    raise exception 'A small gift from a devotee holding a date became % / %.',
      v_gift.match_status, coalesce(v_gift.unmatched_reason, 'null');
  end if;
  if (select bookings.status from public.sponsorship_bookings bookings
      where bookings.id = v_booking) <> 'held' then
    raise exception 'A $21 gift confirmed a $551 sponsorship.';
  end if;
end;
$$;

-- Every gift's id, handed over from the webhook's side of the fence. A devotee
-- cannot read another devotee's donation to find its id, and the refusals below
-- must be testing the refusal rather than re-testing that policy: an attach
-- attempted with a null id would be refused for the wrong reason and would go
-- on being refused after the guard it is meant to prove had been deleted.
do $$
begin
  insert into public.reconciliation_ids (key, id)
  select 'gift_' || substring(donations.external_payment_id from 11), donations.id
  from public.donations
  where donations.external_payment_id like 'zeffy_rec_%';

  if not exists (select 1 from public.reconciliation_ids ids where ids.key = 'gift_bimal') then
    raise exception 'The script failed to hand over the donation ids it needs.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 9. The queue.
--
--    The President sees everything the rule declined to decide, and a candidate
--    beside each one. A devotee sees an empty list rather than an error, so the
--    screen cannot be probed by watching which calls fail.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'e0000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_rows integer;
begin
  select count(*)::integer into v_rows from public.list_unmatched_donations();
  if v_rows <> 0 then
    raise exception 'A devotee sees % rows of the temple''s unmatched money.', v_rows;
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'e0000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
  v_rows integer;
  v_row record;
  v_expected text;
begin
  select count(*)::integer into v_rows from public.list_unmatched_donations();
  -- Bimal's ambiguity, Chandra's shortfall, Chandra's small extra gift, Deva's
  -- stale hold, Eshan's lapsed one.
  if v_rows <> 5 then
    raise exception 'The queue holds % donations rather than five.', v_rows;
  end if;

  foreach v_expected in array array[
    'zeffy_rec_bimal', 'zeffy_rec_chandra', 'zeffy_rec_chandra_extra',
    'zeffy_rec_deva', 'zeffy_rec_eshan'
  ] loop
    if not exists (
      select 1 from public.list_unmatched_donations() queue
      where queue.external_payment_id = v_expected
    ) then
      raise exception '% never reached the queue.', v_expected;
    end if;
  end loop;

  -- Nothing settled is in it.
  if exists (
    select 1 from public.list_unmatched_donations() queue
    where queue.external_payment_id in ('zeffy_rec_asha', 'zeffy_rec_general')
  ) then
    raise exception 'A settled donation is sitting in the unmatched queue.';
  end if;

  -- Chandra's shortfall carries everything the President needs to decide.
  select * into v_row
  from public.list_unmatched_donations() queue
  where queue.external_payment_id = 'zeffy_rec_chandra';

  if v_row.amount_cents <> 50000 or v_row.expected_amount_cents <> 55100 then
    raise exception 'The queue shows % against an expected %.',
      v_row.amount_cents, coalesce(v_row.expected_amount_cents, -1);
  end if;
  if v_row.amount_difference_cents <> -5100 or v_row.amount_matches is not false then
    raise exception 'The queue does not show the shortfall as a shortfall.';
  end if;
  if v_row.donor_email is distinct from 'rec-chandra@example.test' then
    raise exception 'The queue does not say who paid: %', coalesce(v_row.donor_email, 'nobody');
  end if;
  if v_row.expected_type_name is distinct from 'Sunday Feast' then
    raise exception 'The queue does not say what was being paid for: %',
      coalesce(v_row.expected_type_name, 'nothing');
  end if;
  if v_row.candidate_booking_id is distinct from
     (select ids.id from public.reconciliation_ids ids where ids.key = 'chandra_feast') then
    raise exception 'The queue suggests the wrong booking for a short payment.';
  end if;
  if v_row.candidate_count < 1 then
    raise exception 'The queue suggests nothing at all for a payment with an obvious candidate.';
  end if;

  -- Bimal's is ambiguous, and the queue says so rather than hiding it behind a
  -- single confident suggestion.
  select * into v_row
  from public.list_unmatched_donations() queue
  where queue.external_payment_id = 'zeffy_rec_bimal';
  if v_row.candidate_count < 2 then
    raise exception 'The queue reports % candidates for a payment that had two.',
      v_row.candidate_count;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 10. Settling one by hand.
--
--     The President attaches Chandra's $500 to the $551 Sunday Feast she was
--     holding. The seva is confirmed, the gift leaves the queue, and the $51
--     stays on the record: attaching does not paper over the difference, it
--     files it.
-- ---------------------------------------------------------------------------

-- First, a devotee tries. This is the forgery record_donation is locked away
-- from, reached through a different door.
reset role;
select set_config('request.jwt.claim.sub', 'e0000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_donation uuid;
  v_booking uuid;
  v_refused boolean := false;
  v_message text;
begin
  select ids.id into v_donation from public.reconciliation_ids ids where ids.key = 'gift_bimal';
  select ids.id into v_booking from public.reconciliation_ids ids where ids.key = 'bimal_twin_a';

  if v_donation is null or v_booking is null then
    raise exception 'The devotee''s attempt has nothing real to attempt on.';
  end if;

  begin
    perform public.attach_donation_to_booking(v_donation, v_booking);
  exception when others then
    v_refused := true;
    v_message := sqlerrm;
  end;

  if not v_refused then
    raise exception 'A devotee settled the temple''s unmatched money.';
  end if;
  if v_message not ilike '%President%' then
    raise exception 'A devotee was refused for the wrong reason: %', v_message;
  end if;

  -- And she could not do it straight off the table either.
  v_refused := false;
  begin
    update public.donations set sponsorship_booking_id = v_booking where donations.id = v_donation;
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A devotee attached a donation by updating the table.';
  end if;
end;
$$;

-- Now the President.
reset role;
select set_config('request.jwt.claim.sub', 'e0000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
  v_donation uuid;
  v_booking uuid;
  v_settled public.donations;
  v_rows integer;
begin
  select donations.id into v_donation from public.donations
  where donations.external_payment_id = 'zeffy_rec_chandra';
  select ids.id into v_booking from public.reconciliation_ids ids where ids.key = 'chandra_feast';

  v_settled := public.attach_donation_to_booking(v_donation, v_booking);

  if v_settled.match_status <> 'manual' then
    raise exception 'A hand-settled donation reads as %.', v_settled.match_status;
  end if;
  if v_settled.sponsorship_booking_id is distinct from v_booking then
    raise exception 'Attaching pointed the donation somewhere else.';
  end if;
  if v_settled.unmatched_reason is not null then
    raise exception 'A settled donation kept the reason %.', v_settled.unmatched_reason;
  end if;
  if v_settled.matched_by is distinct from 'e0000000-0000-0000-0000-000000000001'::uuid then
    raise exception 'The settlement does not record who made it.';
  end if;
  if v_settled.matched_at is null then
    raise exception 'The settlement does not record when it was made.';
  end if;

  -- The difference survives the settlement. This is the point.
  if v_settled.amount_cents <> 50000 or v_settled.expected_amount_cents <> 55100 then
    raise exception 'Attaching rewrote the amounts to % against %.',
      v_settled.amount_cents, v_settled.expected_amount_cents;
  end if;
  if v_settled.amount_matches is not false or v_settled.amount_difference_cents <> -5100 then
    raise exception 'Attaching hid the $51 the temple is short.';
  end if;

  -- The seva is confirmed.
  if (select bookings.status from public.sponsorship_bookings bookings
      where bookings.id = v_booking) <> 'confirmed' then
    raise exception 'Attaching a gift did not confirm the sponsorship.';
  end if;

  -- And it has left the queue.
  select count(*)::integer into v_rows from public.list_unmatched_donations();
  if v_rows <> 4 then
    raise exception 'The queue holds % donations after one was settled.', v_rows;
  end if;

  -- Settling it again is refused. History is not repointed by one call.
  v_rows := 0;
  begin
    perform public.attach_donation_to_booking(
      v_donation,
      (select ids.id from public.reconciliation_ids ids where ids.key = 'bimal_twin_a')
    );
  exception when others then
    v_rows := 1;
  end;
  if v_rows <> 1 then
    raise exception 'A settled donation was repointed at another sponsorship.';
  end if;
end;
$$;

-- Bimal's ambiguity, settled the only way it ever could be: by somebody asking
-- him which seva he meant. His gift reached record_donation with no expectation
-- against it at all — two prices were equally plausible — so attaching is what
-- has to supply one.
do $$
declare
  v_donation uuid;
  v_twin_a uuid;
  v_twin_b uuid;
  v_settled public.donations;
  v_rows integer;
begin
  select donations.id into v_donation from public.donations
  where donations.external_payment_id = 'zeffy_rec_bimal';
  select ids.id into v_twin_a from public.reconciliation_ids ids where ids.key = 'bimal_twin_a';
  select ids.id into v_twin_b from public.reconciliation_ids ids where ids.key = 'bimal_twin_b';

  if (select donations.expected_amount_cents from public.donations
      where donations.id = v_donation) is not null then
    raise exception 'An ambiguous payment was given an expected price it could not know.';
  end if;

  v_settled := public.attach_donation_to_booking(v_donation, v_twin_a);

  if v_settled.expected_amount_cents is distinct from 44400 then
    raise exception 'Attaching did not record what the seva costs: %',
      coalesce(v_settled.expected_amount_cents, -1);
  end if;
  if v_settled.amount_matches is not true then
    raise exception 'A settled gift that paid the exact price reports a mismatch.';
  end if;

  if (select bookings.status from public.sponsorship_bookings bookings
      where bookings.id = v_twin_a) <> 'confirmed' then
    raise exception 'Attaching Bimal''s gift did not confirm the seva he chose.';
  end if;
  if (select bookings.status from public.sponsorship_bookings bookings
      where bookings.id = v_twin_b) <> 'held' then
    raise exception 'Settling one of two candidates disturbed the other.';
  end if;

  select count(*)::integer into v_rows from public.list_unmatched_donations();
  if v_rows <> 3 then
    raise exception 'The queue holds % donations after two were settled.', v_rows;
  end if;
end;
$$;

-- A cancelled booking is not somewhere money may be filed.
reset role;

do $$
declare
  v_id uuid;
begin
  insert into public.sponsorship_bookings
    (sponsorship_type_id, devotee_id, on_date, status, amount_cents)
  values (
    (select types.id from public.sponsorship_types types where types.name = 'Sunday Feast'),
    'e0000000-0000-0000-0000-000000000006',
    (select dates.on_date from public.reconciliation_dates dates where dates.key = 'sunday_cancelled'),
    'cancelled', 55100
  )
  returning id into v_id;
  insert into public.reconciliation_ids (key, id) values ('cancelled_booking', v_id);
end;
$$;

select set_config('request.jwt.claim.sub', 'e0000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
  v_refused boolean := false;
  v_message text;
begin
  begin
    perform public.attach_donation_to_booking(
      (select donations.id from public.donations
       where donations.external_payment_id = 'zeffy_rec_eshan'),
      (select ids.id from public.reconciliation_ids ids where ids.key = 'cancelled_booking')
    );
  exception when others then
    v_refused := true;
    v_message := sqlerrm;
  end;
  if not v_refused then
    raise exception 'Money was filed against a cancelled sponsorship.';
  end if;
  if v_message not ilike '%cancelled%' then
    raise exception 'A cancelled booking was refused for the wrong reason: %', v_message;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 11. What the two sides see of all this.
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', 'e0000000-0000-0000-0000-000000000004', true);
set local role authenticated;

do $$
declare
  v_row record;
begin
  select * into v_row
  from public.list_my_donations() mine
  where mine.external_payment_id = 'zeffy_rec_chandra';

  if v_row.match_status is distinct from 'manual' then
    raise exception 'Chandra cannot see that her gift was settled: %',
      coalesce(v_row.match_status, 'nothing');
  end if;
  if v_row.amount_matches is not false then
    raise exception 'Chandra is not shown that she paid less than the price.';
  end if;
  if v_row.sponsorship_type_name is distinct from 'Sunday Feast' then
    raise exception 'Chandra''s gift is not shown against the seva it paid for.';
  end if;

  -- Somebody else's unmatched money is still nobody else's business.
  if exists (
    select 1 from public.list_my_donations() mine
    where mine.external_payment_id in ('zeffy_rec_asha', 'zeffy_rec_bimal')
  ) then
    raise exception 'A devotee sees another devotee''s donation.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'e0000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
  v_short integer;
  v_all integer;
begin
  select count(*)::integer into v_all from public.list_all_donations(null, null);
  if v_all <> 7 then
    raise exception 'The President sees % gifts rather than all seven.', v_all;
  end if;

  -- The one question the temple asked to be able to answer at a glance.
  select count(*)::integer into v_short
  from public.list_all_donations(null, null) all_gifts
  where all_gifts.amount_matches is false;
  if v_short <> 2 then
    raise exception 'The President sees % gifts that do not match their price rather than two.',
      v_short;
  end if;

  if not exists (
    select 1 from public.list_all_donations(null, null) all_gifts
    where all_gifts.external_payment_id = 'zeffy_rec_chandra'
      and all_gifts.amount_difference_cents = -5100
      and all_gifts.match_status = 'manual'
      and all_gifts.zeffy_campaign_slug = 'sunday-feast-sponsorship'
  ) then
    raise exception 'The President''s report has lost the shortfall.';
  end if;
end;
$$;

-- The President may also point a sponsorship at its Zeffy page, and a whole URL
-- pasted into the slug box is understood rather than silently breaking every
-- payment on that campaign.
do $$
declare
  v_saved public.sponsorship_types;
begin
  v_saved := public.save_sponsorship_type(
    p_name := 'Sunday Feast (higher)',
    p_amount_cents := 75100,
    p_id := (select types.id from public.sponsorship_types types
             where types.name = 'Sunday Feast (higher)'),
    p_zeffy_campaign_url := 'https://www.zeffy.com/en-US/ticketing/sunday-feast-grand',
    p_zeffy_campaign_slug := 'https://www.zeffy.com/en-US/ticketing/sunday-feast-grand'
  );

  if v_saved.zeffy_campaign_slug is distinct from 'sunday-feast-grand' then
    raise exception 'A pasted Zeffy URL became the slug %.',
      coalesce(v_saved.zeffy_campaign_slug, 'null');
  end if;
  if not v_saved.sunday_only then
    raise exception 'Editing a sponsorship cleared its Sunday rule.';
  end if;

  -- Editing a price through a form that knows nothing about Zeffy must not
  -- silently unplug the page a devotee pays on.
  v_saved := public.save_sponsorship_type(
    p_name := 'Sunday Feast (higher)',
    p_amount_cents := 76100,
    p_id := v_saved.id
  );
  if v_saved.zeffy_campaign_slug is distinct from 'sunday-feast-grand' then
    raise exception 'A price change wiped the Zeffy campaign.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 12. The states the constraints allow, and the ones they refuse.
--
--     booking_lost_date — a hold found, then its date gone to somebody else
--     before the money landed — needs two transactions racing to reach, because
--     the partial unique index from 202608040048 is exactly what stops one
--     transaction from staging it. What can be proven here is that the state is
--     representable at all: unmatched, and still linked to the booking it was
--     meant for, so the only trace of what the money was for is not thrown away.
-- ---------------------------------------------------------------------------

reset role;

do $$
declare
  v_donation uuid;
  v_booking uuid;
  v_refused boolean;
begin
  select donations.id into v_donation from public.donations
  where donations.external_payment_id = 'zeffy_rec_asha';
  select ids.id into v_booking from public.reconciliation_ids ids where ids.key = 'asha_feast';

  -- Representable.
  update public.donations
  set match_status = 'unmatched', unmatched_reason = 'booking_lost_date', matched_at = null
  where donations.id = v_donation;

  -- A settled donation with no booking is not.
  v_refused := false;
  begin
    update public.donations
    set match_status = 'matched', unmatched_reason = null, sponsorship_booking_id = null
    where donations.id = v_donation;
  exception when check_violation then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A matched donation was stored with no sponsorship behind it.';
  end if;

  -- Nor is a general gift that holds a booking.
  v_refused := false;
  begin
    update public.donations
    set match_status = 'general', unmatched_reason = null
    where donations.id = v_donation;
  exception when check_violation then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A general gift was stored holding a sponsorship booking.';
  end if;

  -- Nor an unmatched one with no reason, nor a settled one that kept one.
  v_refused := false;
  begin
    update public.donations set unmatched_reason = null where donations.id = v_donation;
  exception when check_violation then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'An unmatched donation was stored without saying why.';
  end if;

  v_refused := false;
  begin
    update public.donations
    set match_status = 'unmatched', unmatched_reason = 'because'
    where donations.id = v_donation;
  exception when check_violation then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'An unmatched donation was stored with an invented reason.';
  end if;

  -- Put it back the way the webhook left it.
  update public.donations
  set match_status = 'matched', unmatched_reason = null, matched_at = now()
  where donations.id = v_donation;
end;
$$;

-- ---------------------------------------------------------------------------
-- 13. None of this is reachable anonymously, and the matching internals are not
--     a client entry point.
-- ---------------------------------------------------------------------------

do $$
declare
  v_function text;
begin
  for v_function in
    select p.oid::regprocedure::text
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in (
        'attach_donation_to_booking', 'list_unmatched_donations',
        'zeffy_match_window', 'is_sunday_in_chicago', 'save_sponsorship_type',
        'list_sponsorship_types', 'sponsorship_availability', 'record_donation'
      )
      and has_function_privilege('anon', p.oid, 'execute')
  loop
    raise exception 'anon can execute %.', v_function;
  end loop;

  if has_function_privilege('authenticated', 'public.zeffy_match_window()', 'execute') then
    raise exception 'A devotee can read the matching window.';
  end if;

  if not has_function_privilege(
    'authenticated', 'public.attach_donation_to_booking(uuid, uuid)', 'execute'
  ) then
    raise exception 'The President cannot reach attach_donation_to_booking.';
  end if;

  if not has_function_privilege(
    'service_role',
    'public.record_donation(text, integer, text, text, text, uuid, text, text, uuid, jsonb, timestamptz)',
    'execute'
  ) then
    raise exception 'The webhook''s service role can no longer record a donation.';
  end if;

  if has_function_privilege(
    'authenticated',
    'public.record_donation(text, integer, text, text, text, uuid, text, text, uuid, jsonb, timestamptz)',
    'execute'
  ) then
    raise exception 'record_donation is granted to authenticated.';
  end if;

  -- The new columns are readable by a devotee for her own row and writable by
  -- nobody.
  if not has_column_privilege('authenticated', 'public.donations', 'match_status', 'select') then
    raise exception 'A devotee cannot see the state of her own gift.';
  end if;
  if has_table_privilege('authenticated', 'public.donations', 'update') then
    raise exception 'authenticated holds update on public.donations.';
  end if;
  if has_column_privilege('authenticated', 'public.donations', 'payload', 'select') then
    raise exception 'authenticated can select the raw webhook payload.';
  end if;
end;
$$;

do $$
begin
  raise notice 'all donation reconciliation checks passed';
end;
$$;

select 'donation reconciliation verification passed' as result;

rollback;
