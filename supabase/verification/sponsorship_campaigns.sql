-- Functional verification for 202608040050_sponsorship_campaigns.sql.
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
--   President  ...0001  holds app.view_all; the only one who may record a
--                       sponsorship as offered
--   Asha       ...0002  sponsors a deity dress, pays for it, and is told when
--                       it was offered
--   Bimal      ...0003  sponsors a deity dress of his own, on the same day, and
--                       does not collide with Asha
--   Chandra    ...0004  sponsors a third, and does not collide with either
--   Deva       ...0005  an ordinary devotee who may record nothing
--
-- The claims this script exists to prove:
--
--   1. All seven Zeffy campaigns are seeded on the right rows, with the
--      temple's own spelling, and both Sunday Feast tiers share the one page.
--   2. The slug constraint was relaxed to (slug, amount) and not abandoned: a
--      second sponsorship at the same price on one page is still refused, and a
--      sponsorship booked a different way cannot join a campaign at all.
--   3. A dated sponsorship still admits exactly one booking per date, and still
--      does so when the RPC is bypassed entirely.
--   4. Three different devotees each sponsor a deity dress and never collide.
--      This is the claim the whole dateless change is at risk of breaking, so
--      it is proved through the RPC, straight into the table, and by reading
--      the index predicate itself.
--   5. A dateless sponsorship refuses a date; a dated one refuses its absence.
--      Both are refused by the table, not only by the RPC.
--   6. The calendar has nothing to say about a dateless sponsorship.
--   7. Only app.view_all may record a sponsorship as offered, and the donor is
--      told when it is.
--   8. A Sunday Feast is still refused on a day that is not a Sunday.
--
-- The final row must read: sponsorship campaigns verification passed

begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('a0000000-0000-0000-0000-000000000001', 'sc-president@example.test', '{"name":"SC President"}'),
  ('a0000000-0000-0000-0000-000000000002', 'sc-asha@example.test', '{"name":"Asha Devi"}'),
  ('a0000000-0000-0000-0000-000000000003', 'sc-bimal@example.test', '{"name":"Bimal Das"}'),
  ('a0000000-0000-0000-0000-000000000004', 'sc-chandra@example.test', '{"name":"Chandra Devi"}'),
  ('a0000000-0000-0000-0000-000000000005', 'sc-deva@example.test', '{"name":"Deva Das"}');

update public.users
set role_id = (select roles.id from public.roles where roles.name = 'president')
where email = 'sc-president@example.test';

-- Ordinary tables rather than temporary ones, so reading them under the
-- authenticated role needs no assumptions about the temp schema. The whole
-- script is rolled back, so they never outlive the transaction.
create table public.sc_ids (key text primary key, id uuid not null);
grant select, insert, update on public.sc_ids to authenticated;

create table public.sc_dates (key text primary key, on_date date not null);
grant select, insert on public.sc_dates to authenticated;

-- Every date decided once, in Chicago. v_sunday is the next Sunday strictly
-- ahead of today, so no case ever collides with the past-date refusal.
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

  insert into public.sc_dates (key, on_date) values
    ('today',        v_today),
    ('sunday',       v_sunday),
    ('monday',       v_sunday + 1),
    ('garland',      v_today + 60),
    ('garland_two',  v_today + 61),
    ('tomorrow',     v_today + 1);
end;
$$;

-- ---------------------------------------------------------------------------
-- 1. The seven campaigns, on the right rows.
--
--    Asserted one row at a time against the list the temple gave, rather than
--    by counting slugs, because a count of seven passes when the garland's page
--    is on the rajbhog and a devotee is then sent to pay for the wrong seva.
--
--    `diety-dress` is checked verbatim, and the correct spelling is checked for
--    and refused, because a helpful hand tidying it would replace the temple's
--    live URL with a 404 at the moment a devotee was about to give.
-- ---------------------------------------------------------------------------

do $$
declare
  v_name text;
  v_slug text;
  v_url text;
  v_distinct integer;
begin
  for v_name, v_slug, v_url in
    select expected.name,
           coalesce(types.zeffy_campaign_slug, 'nothing'),
           coalesce(types.zeffy_campaign_url, 'nothing')
    from (values
      ('Mangal Aarti',          'mangala-aarti'),
      ('Breakfast',             'breakfast-6'),
      ('Sandhya Bhog',          'sandhya-bhog'),
      ('Rajbhog',               'rajbhog'),
      ('Garland',               'garland'),
      ('Sunday Feast',          'sunday-feast-sponsorship'),
      ('Sunday Feast (higher)', 'sunday-feast-sponsorship'),
      ('Deity Dress',           'diety-dress')
    ) as expected(name, slug)
    left join public.sponsorship_types types on types.name = expected.name
    where types.zeffy_campaign_slug is distinct from expected.slug
       or types.zeffy_campaign_url is distinct from
          'https://www.zeffy.com/embed/ticketing/' || expected.slug
  loop
    raise exception '% points at campaign % / %, which is not what the temple made.',
      v_name, v_slug, v_url;
  end loop;

  -- Eight sponsorships, seven pages: the two Sunday Feast rates are one page.
  select count(distinct sponsorship_types.zeffy_campaign_slug)::integer
  into v_distinct
  from public.sponsorship_types
  where sponsorship_types.zeffy_campaign_slug is not null;

  if v_distinct <> 7 then
    raise exception 'The temple has % Zeffy campaigns seeded rather than seven.', v_distinct;
  end if;

  if (select count(*) from public.sponsorship_types
      where zeffy_campaign_slug = 'sunday-feast-sponsorship') <> 2 then
    raise exception 'The two Sunday Feast rates are not two rows on one campaign.';
  end if;

  -- The temple's spelling, not ours.
  if exists (
    select 1 from public.sponsorship_types where zeffy_campaign_slug = 'deity-dress'
  ) then
    raise exception 'The deity dress slug was corrected to deity-dress and is now a 404.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Which sponsorships are booked to a day.
--
--    One at a time again, and not as a count: a count of one dateless
--    sponsorship passes when the garland is the dateless one and the deity
--    dress is on the calendar, which is precisely inverted and would look fine.
-- ---------------------------------------------------------------------------

do $$
declare
  v_row record;
begin
  for v_row in
    select sponsorship_types.name, sponsorship_types.requires_date
    from public.sponsorship_types
    where sponsorship_types.requires_date <> (sponsorship_types.name <> 'Deity Dress')
  loop
    raise exception '% has requires_date = %, which is not what the temple asked for.',
      v_row.name, v_row.requires_date;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. The campaign constraint, relaxed but not abandoned.
--
--    The old one-row-per-slug index is gone, because the Sunday Feast is two
--    rates on one page. What replaces it must still make (campaign, amount)
--    resolve to exactly one sponsorship, and must still stop a sponsorship
--    booked a different way from joining a campaign it has nothing to do with.
-- ---------------------------------------------------------------------------

do $$
declare
  v_refused boolean;
  v_message text;
begin
  if exists (
    select 1 from pg_indexes
    where schemaname = 'public' and indexname = 'sponsorship_types_zeffy_slug_key'
  ) then
    raise exception 'The one-row-per-campaign index survived, so the two Sunday Feast rates cannot both exist.';
  end if;

  if not exists (
    select 1 from pg_indexes
    where schemaname = 'public'
      and indexname = 'sponsorship_types_zeffy_slug_amount_key'
      and indexdef ilike 'CREATE UNIQUE INDEX%'
      and indexdef ilike '%amount_cents%'
      and indexdef ilike '%zeffy_campaign_slug IS NOT NULL%'
  ) then
    raise exception 'A campaign and an amount no longer resolve to one sponsorship.';
  end if;

  -- Two sponsorships at one price on one page: the webhook could not tell a
  -- payment of that amount apart, so it is still refused.
  v_refused := false;
  begin
    insert into public.sponsorship_types
      (name, amount_cents, display_order, sunday_only, zeffy_campaign_slug, zeffy_campaign_url)
    values
      ('SC Duplicate Rate', 55100, 950, true,
       'sunday-feast-sponsorship',
       'https://www.zeffy.com/embed/ticketing/sunday-feast-sponsorship');
  exception when unique_violation then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'Two sponsorships share one campaign at one price.';
  end if;

  -- A third rate on the same page is fine: that is the relaxation working.
  insert into public.sponsorship_types
    (name, amount_cents, display_order, sunday_only, zeffy_campaign_slug, zeffy_campaign_url)
  values
    ('SC Third Rate', 95100, 951, true,
     'sunday-feast-sponsorship',
     'https://www.zeffy.com/embed/ticketing/sunday-feast-sponsorship');

  delete from public.sponsorship_types where name = 'SC Third Rate';

  -- A sponsorship booked on any day cannot join a Sundays-only page: one page
  -- presents one set of bookable days.
  v_refused := false;
  begin
    update public.sponsorship_types
    set zeffy_campaign_slug = 'sunday-feast-sponsorship'
    where name = 'Garland';
  exception when others then
    v_refused := true;
    v_message := sqlerrm;
  end;
  if not v_refused then
    raise exception 'The garland joined the Sunday Feast campaign.';
  end if;
  if v_message not ilike '%not booked the same way%' then
    raise exception 'The campaign refusal is unreadable: %', v_message;
  end if;

  -- Nor can a dateless sponsorship join a dated campaign.
  v_refused := false;
  begin
    update public.sponsorship_types
    set zeffy_campaign_slug = 'garland',
        zeffy_campaign_url = 'https://www.zeffy.com/embed/ticketing/garland'
    where name = 'Deity Dress';
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'The deity dress joined a dated campaign.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. The one-per-date index still says what it always said.
--
--    Read out of the catalogue rather than inferred from behaviour, because the
--    behaviour it guarantees is a race that a single-connection script cannot
--    stage. The predicate is the promise.
-- ---------------------------------------------------------------------------

do $$
declare
  v_def text;
begin
  select indexdef into v_def
  from pg_indexes
  where schemaname = 'public'
    and indexname = 'sponsorship_booking_one_live_per_type_and_date';

  if v_def is null then
    raise exception 'The one-sponsor-per-date index is gone.';
  end if;
  if v_def not ilike 'CREATE UNIQUE INDEX%' then
    raise exception 'The one-sponsor-per-date index is no longer unique.';
  end if;
  if v_def not ilike '%on_date IS NOT NULL%' then
    raise exception
      'The one-sponsor-per-date index does not exclude dateless bookings, so a NULLS NOT DISTINCT away it admits exactly one deity dress ever.';
  end if;
  if v_def not ilike '%''held''%' or v_def not ilike '%''confirmed''%' then
    raise exception 'The one-sponsor-per-date index no longer covers the two live states.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. A dated sponsorship still admits one booking per date.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_booking public.sponsorship_bookings;
begin
  v_booking := public.hold_sponsorship(
    (select types.id from public.sponsorship_types types where types.name = 'Garland'),
    (select dates.on_date from public.sc_dates dates where dates.key = 'garland')
  );
  if v_booking.id is null then
    raise exception 'Asha could not hold a garland.';
  end if;
  insert into public.sc_ids (key, id) values ('asha_garland', v_booking.id);
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000003', true);
set local role authenticated;

do $$
declare
  v_refused boolean := false;
  v_message text;
begin
  begin
    perform public.hold_sponsorship(
      (select types.id from public.sponsorship_types types where types.name = 'Garland'),
      (select dates.on_date from public.sc_dates dates where dates.key = 'garland')
    );
  exception when others then
    v_refused := true;
    v_message := sqlerrm;
  end;

  if not v_refused then
    raise exception 'Two devotees hold the same garland on the same date.';
  end if;
  if v_message not ilike '%already been sponsored%' then
    raise exception 'The taken-date refusal is unreadable: %', v_message;
  end if;
end;
$$;

reset role;

-- And the index, not the RPC, is what decides. Inserted as a superuser with
-- every policy and grant out of the way.
do $$
declare
  v_refused boolean := false;
begin
  begin
    insert into public.sponsorship_bookings
      (sponsorship_type_id, devotee_id, on_date, status, held_until, amount_cents)
    values (
      (select types.id from public.sponsorship_types types where types.name = 'Garland'),
      'a0000000-0000-0000-0000-000000000003',
      (select dates.on_date from public.sc_dates dates where dates.key = 'garland'),
      'held', now() + interval '30 minutes', 35100
    );
  exception when unique_violation then
    v_refused := true;
  end;

  if not v_refused then
    raise exception 'The table itself allowed a second live booking on one date.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Three devotees, three deity dresses, no collision.
--
--    This is the claim the dateless change is most at risk of breaking, so it
--    is proved three ways: through the RPC by three different devotees, then
--    straight into the table by a fourth, then read off the rows themselves.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_booking public.sponsorship_bookings;
begin
  v_booking := public.hold_sponsorship(
    (select types.id from public.sponsorship_types types where types.name = 'Deity Dress')
  );
  if v_booking.id is null then
    raise exception 'Asha could not sponsor a deity dress.';
  end if;
  if v_booking.on_date is not null then
    raise exception 'A dateless sponsorship was given the date %.', v_booking.on_date;
  end if;
  if v_booking.amount_cents <> 250000 then
    raise exception 'The deity dress hold recorded % cents.', v_booking.amount_cents;
  end if;
  insert into public.sc_ids (key, id) values ('asha_dress', v_booking.id);
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000003', true);
set local role authenticated;

do $$
declare
  v_booking public.sponsorship_bookings;
begin
  v_booking := public.hold_sponsorship(
    (select types.id from public.sponsorship_types types where types.name = 'Deity Dress')
  );
  if v_booking.id is null then
    raise exception 'A second devotee was refused a deity dress.';
  end if;
  insert into public.sc_ids (key, id) values ('bimal_dress', v_booking.id);
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000004', true);
set local role authenticated;

do $$
declare
  v_booking public.sponsorship_bookings;
  v_live integer;
begin
  v_booking := public.hold_sponsorship(
    (select types.id from public.sponsorship_types types where types.name = 'Deity Dress')
  );
  if v_booking.id is null then
    raise exception 'A third devotee was refused a deity dress.';
  end if;
  insert into public.sc_ids (key, id) values ('chandra_dress', v_booking.id);

  -- Chandra may only read her own, so the count of three is taken below with
  -- the role reset. What she can see is that hers exists.
  select count(*)::integer into v_live
  from public.sponsorship_bookings bookings
  where bookings.on_date is null and bookings.status = 'held';
  if v_live <> 1 then
    raise exception 'Chandra can see % dateless holds rather than only her own.', v_live;
  end if;
end;
$$;

reset role;

do $$
declare
  v_live integer;
  v_devotees integer;
begin
  select count(*)::integer, count(distinct bookings.devotee_id)::integer
  into v_live, v_devotees
  from public.sponsorship_bookings bookings
  join public.sponsorship_types types on types.id = bookings.sponsorship_type_id
  where types.name = 'Deity Dress'
    and bookings.status = 'held';

  if v_live <> 3 or v_devotees <> 3 then
    raise exception
      'Three devotees sponsored a deity dress and the table holds % bookings by % of them.',
      v_live, v_devotees;
  end if;

  -- A fourth, straight into the table, so the proof does not rest on the RPC.
  insert into public.sponsorship_bookings
    (sponsorship_type_id, devotee_id, on_date, status, held_until, amount_cents)
  values (
    (select types.id from public.sponsorship_types types where types.name = 'Deity Dress'),
    'a0000000-0000-0000-0000-000000000005', null, 'confirmed', null, 250000
  );

  select count(*)::integer into v_live
  from public.sponsorship_bookings bookings
  join public.sponsorship_types types on types.id = bookings.sponsorship_type_id
  where types.name = 'Deity Dress'
    and bookings.status in ('held', 'confirmed');

  if v_live <> 4 then
    raise exception 'The table admits only % live deity dress sponsorships.', v_live;
  end if;

  -- And a devotee who has already given one may give another once it is no
  -- longer waiting to be paid for: a confirmed dress is outside the hold index.
  insert into public.sponsorship_bookings
    (sponsorship_type_id, devotee_id, on_date, status, held_until, amount_cents)
  values (
    (select types.id from public.sponsorship_types types where types.name = 'Deity Dress'),
    'a0000000-0000-0000-0000-000000000005', null, 'confirmed', null, 250000
  );
end;
$$;

-- One devotee cannot, however, leave two payments hanging on one dateless
-- sponsorship at once: two open holds are two candidates for one payment, and
-- her own money would go to the unmatched queue for no reason.
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_refused boolean := false;
  v_message text;
begin
  begin
    perform public.hold_sponsorship(
      (select types.id from public.sponsorship_types types where types.name = 'Deity Dress')
    );
  exception when others then
    v_refused := true;
    v_message := sqlerrm;
  end;

  if not v_refused then
    raise exception 'One devotee opened two deity dress holds at once.';
  end if;
  if v_message not ilike '%waiting to be paid for%' then
    raise exception 'The second-hold refusal is unreadable: %', v_message;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. A date where there is none to give, and none where there must be one.
-- ---------------------------------------------------------------------------

do $$
declare
  v_refused boolean := false;
  v_message text;
begin
  -- A dateless sponsorship refuses a date.
  begin
    perform public.hold_sponsorship(
      (select types.id from public.sponsorship_types types where types.name = 'Deity Dress'),
      (select dates.on_date from public.sc_dates dates where dates.key = 'tomorrow')
    );
  exception when others then
    v_refused := true;
    v_message := sqlerrm;
  end;

  if not v_refused then
    raise exception 'A deity dress was booked to a date.';
  end if;
  if v_message not ilike '%no date to choose%' then
    raise exception 'The refusal of a date is unreadable: %', v_message;
  end if;

  -- A dated sponsorship refuses its absence.
  v_refused := false;
  begin
    perform public.hold_sponsorship(
      (select types.id from public.sponsorship_types types where types.name = 'Garland')
    );
  exception when others then
    v_refused := true;
    v_message := sqlerrm;
  end;

  if not v_refused then
    raise exception 'A garland was sponsored on no day at all.';
  end if;
  if v_message not ilike '%choose a date%' then
    raise exception 'The refusal of a missing date is unreadable: %', v_message;
  end if;
end;
$$;

reset role;

-- Both refusals belong to the table, not to the RPC.
do $$
declare
  v_refused boolean;
  v_message text;
begin
  v_refused := false;
  begin
    insert into public.sponsorship_bookings
      (sponsorship_type_id, devotee_id, on_date, status, held_until, amount_cents)
    values (
      (select types.id from public.sponsorship_types types where types.name = 'Deity Dress'),
      'a0000000-0000-0000-0000-000000000005',
      (select dates.on_date from public.sc_dates dates where dates.key = 'tomorrow'),
      'held', now() + interval '30 minutes', 250000
    );
  exception when others then
    v_refused := true;
    v_message := sqlerrm;
  end;
  if not v_refused then
    raise exception 'The table accepted a deity dress booked to a date.';
  end if;
  if v_message not ilike '%cannot be booked to a date%' then
    raise exception 'The table''s refusal of a date is unreadable: %', v_message;
  end if;

  v_refused := false;
  begin
    insert into public.sponsorship_bookings
      (sponsorship_type_id, devotee_id, on_date, status, held_until, amount_cents)
    values (
      (select types.id from public.sponsorship_types types where types.name = 'Garland'),
      'a0000000-0000-0000-0000-000000000005', null,
      'held', now() + interval '30 minutes', 35100
    );
  exception when others then
    v_refused := true;
    v_message := sqlerrm;
  end;
  if not v_refused then
    raise exception 'The table accepted a garland with no date.';
  end if;
  if v_message not ilike '%none was given%' then
    raise exception 'The table''s refusal of a missing date is unreadable: %', v_message;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. The calendar, which has nothing to say about a deity dress.
--
--    Checked across a whole window rather than on one day, because a dateless
--    type leaking onto the calendar would leak onto every day of it and a
--    single-day check could land on the one day it happened not to.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000004', true);
set local role authenticated;

do $$
declare
  v_from date;
  v_rows integer;
begin
  select dates.on_date into v_from from public.sc_dates dates where dates.key = 'today';

  select count(*)::integer into v_rows
  from public.sponsorship_availability(v_from, v_from + 30) calendar
  where calendar.type_name = 'Deity Dress';

  if v_rows <> 0 then
    raise exception 'The calendar offers the deity dress on % days.', v_rows;
  end if;

  -- The dated sponsorships are still all there, every day.
  select count(*)::integer into v_rows
  from public.sponsorship_availability(v_from, v_from + 30) calendar
  where calendar.type_name = 'Garland';

  if v_rows <> 31 then
    raise exception 'The garland is on % of the 31 days asked for.', v_rows;
  end if;

  -- And the app is told which sponsorships have no calendar at all.
  if not exists (
    select 1 from public.list_sponsorship_types() types
    where types.name = 'Deity Dress'
      and not types.requires_date
      and types.zeffy_campaign_url = 'https://www.zeffy.com/embed/ticketing/diety-dress'
  ) then
    raise exception 'The sponsorship list does not tell the app the deity dress has no date.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 9. The Sunday Feast is still a Sunday's.
--
--    The two rates are now one campaign, and the rule has to survive that: a
--    campaign is a payment page, not a booking rule.
-- ---------------------------------------------------------------------------

do $$
declare
  v_sunday date;
  v_monday date;
  v_booking public.sponsorship_bookings;
  v_refused boolean := false;
  v_message text;
begin
  select dates.on_date into v_sunday from public.sc_dates dates where dates.key = 'sunday';
  select dates.on_date into v_monday from public.sc_dates dates where dates.key = 'monday';

  begin
    perform public.hold_sponsorship(
      (select types.id from public.sponsorship_types types where types.name = 'Sunday Feast'),
      v_monday
    );
  exception when others then
    v_refused := true;
    v_message := sqlerrm;
  end;

  if not v_refused then
    raise exception 'The Sunday Feast was sponsored on a Monday.';
  end if;
  if v_message not ilike '%only offered on Sundays%' then
    raise exception 'The Monday refusal is unreadable: %', v_message;
  end if;

  v_booking := public.hold_sponsorship(
    (select types.id from public.sponsorship_types types where types.name = 'Sunday Feast'),
    v_sunday
  );
  if v_booking.id is null then
    raise exception 'A Sunday Feast was refused on a Sunday.';
  end if;
  perform public.release_sponsorship_hold(v_booking.id);
end;
$$;

-- ---------------------------------------------------------------------------
-- 10. The money lands, and a dateless sponsorship is confirmed by it.
--
--     Through the real webhook path, because a dateless booking matched on
--     (donor, amount, campaign) is the thing the deity dress will actually do
--     every time somebody sponsors one.
-- ---------------------------------------------------------------------------

reset role;

do $$
declare
  v_gift public.donations;
  v_expected uuid;
begin
  select ids.id into v_expected from public.sc_ids ids where ids.key = 'asha_dress';

  v_gift := public.record_donation(
    p_external_payment_id := 'zeffy_sc_asha_dress',
    p_amount_cents := 250000,
    p_kind := 'one_time',
    p_donor_name := 'Asha Devi',
    p_donor_email := 'SC-Asha@Example.Test',
    p_payload := '{"source":"zeffy","campaign_slug":"diety-dress"}'::jsonb
  );

  if v_gift.match_status <> 'matched' then
    raise exception 'A deity dress payment was recorded as % rather than matched.',
      v_gift.match_status;
  end if;
  if v_gift.sponsorship_booking_id is distinct from v_expected then
    raise exception 'A deity dress payment was tied to the wrong booking.';
  end if;
  if (select bookings.status from public.sponsorship_bookings bookings
      where bookings.id = v_expected) <> 'confirmed' then
    raise exception 'Asha paid for a deity dress and it was not confirmed.';
  end if;

  -- Bimal pays for his too, so a second one exists to test the refusals with.
  select ids.id into v_expected from public.sc_ids ids where ids.key = 'bimal_dress';
  v_gift := public.record_donation(
    p_external_payment_id := 'zeffy_sc_bimal_dress',
    p_amount_cents := 250000,
    p_kind := 'one_time',
    p_donor_email := 'sc-bimal@example.test',
    p_payload := '{"source":"zeffy","campaign_slug":"diety-dress"}'::jsonb
  );
  if v_gift.match_status <> 'matched' then
    raise exception 'A second deity dress payment was recorded as %.', v_gift.match_status;
  end if;
  if (select bookings.status from public.sponsorship_bookings bookings
      where bookings.id = v_expected) <> 'confirmed' then
    raise exception 'Two confirmed deity dresses could not coexist.';
  end if;
end;
$$;

-- The two Sunday Feast rates are one page, so a payment on that page has to
-- resolve to the rate that was actually paid and not to whichever row the
-- catalogue happened to return first.
do $$
declare
  v_gift public.donations;
  v_higher uuid;
begin
  select types.id into v_higher from public.sponsorship_types types
  where types.name = 'Sunday Feast (higher)';

  v_gift := public.record_donation(
    p_external_payment_id := 'zeffy_sc_higher_feast',
    p_amount_cents := 75100,
    p_kind := 'one_time',
    p_donor_email := 'sc-deva@example.test',
    p_payload := '{"source":"zeffy","campaign_slug":"sunday-feast-sponsorship"}'::jsonb
  );

  if v_gift.expected_amount_cents is distinct from 75100 then
    raise exception 'A $751 payment on the shared Sunday Feast page expected % cents.',
      coalesce(v_gift.expected_amount_cents, -1);
  end if;
  if v_gift.expected_sponsorship_type_id is distinct from v_higher then
    raise exception 'A $751 payment on the shared page was priced against the wrong rate.';
  end if;
  if v_gift.amount_matches is not true then
    raise exception 'A payment at one of the campaign''s own rates reported a mismatch.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 11. Recording that it was offered, and telling the donor.
--
--     Refused for everybody but the President and the Tech Admin — including
--     the donor herself, who would otherwise be writing the temple's record of
--     what the temple did.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000005', true);
set local role authenticated;

do $$
declare
  v_refused boolean := false;
  v_message text;
  v_booking uuid;
begin
  select ids.id into v_booking from public.sc_ids ids where ids.key = 'asha_dress';

  begin
    perform public.mark_sponsorship_fulfilled(v_booking, null, 'I say it happened.');
  exception when others then
    v_refused := true;
    v_message := sqlerrm;
  end;

  if not v_refused then
    raise exception 'An ordinary devotee recorded a sponsorship as offered.';
  end if;
  if v_message not ilike '%President or a Tech Admin%' then
    raise exception 'The refusal is unreadable: %', v_message;
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_refused boolean := false;
  v_booking uuid;
begin
  select ids.id into v_booking from public.sc_ids ids where ids.key = 'asha_dress';

  begin
    perform public.mark_sponsorship_fulfilled(v_booking, null, null);
  exception when others then
    v_refused := true;
  end;

  if not v_refused then
    raise exception 'The donor recorded her own sponsorship as offered.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
  v_booking uuid;
  v_saved public.sponsorship_bookings;
  v_refused boolean;
  v_message text;
  v_today date;
  v_notes integer;
begin
  select ids.id into v_booking from public.sc_ids ids where ids.key = 'asha_dress';
  select dates.on_date into v_today from public.sc_dates dates where dates.key = 'today';

  -- Not before it happened.
  v_refused := false;
  begin
    perform public.mark_sponsorship_fulfilled(v_booking, v_today + 1, null);
  exception when others then
    v_refused := true;
    v_message := sqlerrm;
  end;
  if not v_refused then
    raise exception 'A sponsorship was recorded as offered on a day that has not arrived.';
  end if;
  if v_message not ilike '%has not arrived yet%' then
    raise exception 'The future-date refusal is unreadable: %', v_message;
  end if;

  -- Not before it was paid for. Chandra's dress is still only held.
  v_refused := false;
  begin
    perform public.mark_sponsorship_fulfilled(
      (select ids.id from public.sc_ids ids where ids.key = 'chandra_dress'), null, null);
  exception when others then
    v_refused := true;
    v_message := sqlerrm;
  end;
  if not v_refused then
    raise exception 'An unpaid sponsorship was recorded as offered.';
  end if;
  if v_message not ilike '%not been paid for%' then
    raise exception 'The unpaid refusal is unreadable: %', v_message;
  end if;

  -- And now, properly.
  v_saved := public.mark_sponsorship_fulfilled(
    v_booking, v_today, 'Offered at the morning darshan.'
  );

  if v_saved.fulfilled_on is distinct from v_today then
    raise exception 'The sponsorship was recorded as offered on %.',
      coalesce(v_saved.fulfilled_on::text, 'no day');
  end if;
  if v_saved.fulfilment_note is distinct from 'Offered at the morning darshan.' then
    raise exception 'The note the temple wrote was not kept.';
  end if;

  -- Once, and once only.
  v_refused := false;
  begin
    perform public.mark_sponsorship_fulfilled(v_booking, v_today, 'Again.');
  exception when others then
    v_refused := true;
    v_message := sqlerrm;
  end;
  if not v_refused then
    raise exception 'A sponsorship was recorded as offered twice.';
  end if;
  if v_message not ilike '%already recorded as offered%' then
    raise exception 'The second-call refusal is unreadable: %', v_message;
  end if;

  -- The President sees it on the whole-congregation list.
  if not exists (
    select 1 from public.list_all_sponsorships() all_sponsorships
    where all_sponsorships.id = v_booking
      and all_sponsorships.fulfilled_on = v_today
      and not all_sponsorships.requires_date
      and all_sponsorships.on_date is null
  ) then
    raise exception 'The President''s list does not show the dress as offered.';
  end if;

  select count(*)::integer into v_notes
  from public.sponsorship_bookings bookings
  where bookings.fulfilment_note is not null and bookings.fulfilled_on is null;
  if v_notes <> 0 then
    raise exception 'A fulfilment note exists without a day it happened on.';
  end if;
end;
$$;

-- The donor is told, and can see it on her own list.
reset role;

do $$
declare
  v_booking uuid;
  v_note record;
begin
  select ids.id into v_booking from public.sc_ids ids where ids.key = 'asha_dress';

  select * into v_note
  from public.app_notifications
  where app_notifications.user_id = 'a0000000-0000-0000-0000-000000000002'
    and app_notifications.kind = 'sponsorship_fulfilled';

  if v_note.id is null then
    raise exception 'The donor was not told her sponsorship had been offered.';
  end if;
  if (v_note.data ->> 'bookingId')::uuid is distinct from v_booking then
    raise exception 'The notification points at the wrong booking.';
  end if;
  if v_note.body not ilike '%Deity Dress%' then
    raise exception 'The notification does not say what was offered: %', v_note.body;
  end if;
  if v_note.body not ilike '%morning darshan%' then
    raise exception 'The temple''s note did not reach the donor.';
  end if;

  -- Nobody else was told.
  if (select count(*) from public.app_notifications
      where app_notifications.kind = 'sponsorship_fulfilled') <> 1 then
    raise exception 'A sponsorship being offered was announced to more than its donor.';
  end if;
end;
$$;

select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_booking uuid;
begin
  select ids.id into v_booking from public.sc_ids ids where ids.key = 'asha_dress';

  if not exists (
    select 1 from public.list_my_sponsorships() mine
    where mine.id = v_booking
      and mine.fulfilled_on is not null
      and mine.on_date is null
      and not mine.requires_date
      and mine.status = 'confirmed'
  ) then
    raise exception 'The donor cannot see that her deity dress was offered.';
  end if;
end;
$$;

reset role;

-- ---------------------------------------------------------------------------
-- 12. None of this is reachable anonymously, and no client may write the
--     tables directly.
-- ---------------------------------------------------------------------------

do $$
declare
  v_function text;
  v_table text;
  v_privilege text;
  v_kind text;
begin
  for v_function in
    select p.oid::regprocedure::text
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in (
        'mark_sponsorship_fulfilled', 'hold_sponsorship', 'sponsorship_availability',
        'list_sponsorship_types', 'save_sponsorship_type', 'list_my_sponsorships',
        'list_all_sponsorships', 'record_donation'
      )
      and has_function_privilege('anon', p.oid, 'execute')
  loop
    raise exception 'anon can execute %.', v_function;
  end loop;

  if has_function_privilege(
    'authenticated', 'public.mark_sponsorship_fulfilled(uuid, date, text)', 'execute'
  ) is not true then
    raise exception 'The President cannot reach mark_sponsorship_fulfilled.';
  end if;

  foreach v_table in array
    array['public.sponsorship_types', 'public.sponsorship_bookings']
  loop
    foreach v_privilege in array array['insert', 'update', 'delete'] loop
      if has_table_privilege('authenticated', v_table, v_privilege) then
        raise exception 'authenticated holds % on %.', v_privilege, v_table;
      end if;
    end loop;
  end loop;

  -- The kind really is allowed by the constraint, and the constraint really did
  -- keep every kind that came before it.
  foreach v_kind in array array[
    'sponsorship_fulfilled', 'access_appointed', 'access_revoked',
    'newsletter_posted', 'birthday_today', 'care_reply',
    'announcement_posted', 'feedback_reviewed', 'service_open',
    'sanga_created', 'access_request_submitted', 'devotee_joined', 'remote'
  ] loop
    begin
      insert into public.app_notifications (user_id, kind, title, body)
      values ('a0000000-0000-0000-0000-000000000005', v_kind, 'x', 'y');
    exception when check_violation then
      raise exception 'The notification kind % was outlawed.', v_kind;
    end;
  end loop;

  -- And a kind nobody has defined is still refused, so the constraint was
  -- widened rather than removed.
  begin
    insert into public.app_notifications (user_id, kind, title, body)
    values ('a0000000-0000-0000-0000-000000000005', 'sponsorship_invented', 'x', 'y');
    raise exception 'The notification kind constraint accepts anything at all.';
  exception when check_violation then
    null;
  end;
end;
$$;

select 'sponsorship campaigns verification passed' as result;

rollback;
