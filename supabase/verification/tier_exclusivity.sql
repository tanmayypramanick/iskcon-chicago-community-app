-- Functional verification for 202608040051_tier_exclusivity.sql.
--
-- Rolled back at the end. Every local is prefixed v_ so it can never shadow a
-- column name. Anything that must be refused is attempted as the person who
-- would really attempt it, under `set local role authenticated`, so the row
-- level security policies and the grants are what is being tested rather than
-- superuser rights quietly waving everything through.
--
-- The people in this script:
--   President  ...0001  holds app.view_all; the only one who may regroup tiers
--   Asha       ...0002  sponsors the Sunday Feast at $551
--   Bimal      ...0003  wants the same Sunday at $751 and must not get it
--   Chandra    ...0004  sponsors other days and other sevas
--   Deva       ...0005  sponsors deity dresses, which have no day at all
--
-- The claims this script exists to prove:
--
--   1. Both tables carry a not-null exclusivity group; the two Sunday Feast
--      rates share one; the Garland, the Rajbhog and the Deity Dress do not.
--   2. A Sunday held at $551 is gone at $751 — through the RPC, and through a
--      direct insert that bypasses the RPC entirely.
--   3. The refusal names the seva, not the rate.
--   4. A different Sunday is still free at either rate.
--   5. Different sponsorships stay independent: a Garland and a Rajbhog on one
--      date both succeed.
--   6. THREE DEVOTEES CAN EACH SPONSOR A DEITY DRESS. The dateless case is
--      unlimited, it is what this migration is most likely to have broken, and
--      it is proved through the RPC, straight into the table, through the
--      calendar, and by reading the index predicates themselves.
--   7. sponsorship_availability reports the day taken on every rate of the
--      group, so the calendar cannot offer a $751 slot on a sponsored Sunday.
--   8. A released hold frees the day at every rate.
--   9. An expired hold on one rate does not hold the day against another.
--  10. A rate added to a campaign later joins the group; repointing a rate's
--      Zeffy page does not split it; the President can group and ungroup by
--      hand, and a regrouping that would double-book a day is refused.
--
-- The final row must read: tier exclusivity verification passed

begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('b0000000-0000-0000-0000-000000000001', 'te-president@example.test', '{"name":"TE President"}'),
  ('b0000000-0000-0000-0000-000000000002', 'te-asha@example.test', '{"name":"TE Asha"}'),
  ('b0000000-0000-0000-0000-000000000003', 'te-bimal@example.test', '{"name":"TE Bimal"}'),
  ('b0000000-0000-0000-0000-000000000004', 'te-chandra@example.test', '{"name":"TE Chandra"}'),
  ('b0000000-0000-0000-0000-000000000005', 'te-deva@example.test', '{"name":"TE Deva"}');

update public.users
set role_id = (select roles.id from public.roles where roles.name = 'president')
where email = 'te-president@example.test';

-- Ordinary tables rather than temporary ones, so reading them under the
-- authenticated role needs no assumptions about the temp schema. The whole
-- script is rolled back, so they never outlive the transaction.
create table public.te_ids (key text primary key, id uuid not null);
grant select, insert, update on public.te_ids to authenticated;

create table public.te_dates (key text primary key, on_date date not null);
grant select, insert on public.te_dates to authenticated;

-- Every date decided once, in Chicago. Four separate Sundays, so no section
-- can pass by accident on a day another section already settled.
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

  insert into public.te_dates (key, on_date) values
    ('today',        v_today),
    ('sunday',       v_sunday),
    ('sunday_two',   v_sunday + 7),
    ('sunday_three', v_sunday + 14),
    ('sunday_four',  v_sunday + 21),
    ('monday',       v_sunday + 1),
    ('garland',      v_today + 40);
end;
$$;

-- The sponsorships this script talks about, looked up once.
insert into public.te_ids (key, id)
select lower(replace(types.name, ' ', '_')), types.id
from public.sponsorship_types types
where types.name in (
  'Sunday Feast', 'Sunday Feast (higher)', 'Garland', 'Rajbhog', 'Deity Dress'
);

insert into public.te_ids (key, id)
select 'feast_group', types.exclusivity_group
from public.sponsorship_types types
where types.name = 'Sunday Feast';

-- ---------------------------------------------------------------------------
-- 1. The group exists, on both tables, and says what the temple means.
--
--    Asserted one sponsorship at a time rather than by counting groups: a count
--    of seven distinct groups passes when the Garland and the Rajbhog are one
--    group and the two feast rates are two, which is precisely inverted and
--    would look fine.
-- ---------------------------------------------------------------------------

do $$
declare
  v_nullable text;
  v_feast uuid;
  v_higher uuid;
  v_garland uuid;
  v_rajbhog uuid;
  v_dress uuid;
  v_orphans integer;
begin
  foreach v_nullable in array array['sponsorship_types', 'sponsorship_bookings'] loop
    if not exists (
      select 1 from information_schema.columns
      where table_schema = 'public'
        and table_name = v_nullable
        and column_name = 'exclusivity_group'
        and is_nullable = 'NO'
    ) then
      raise exception
        '%.exclusivity_group is missing or nullable, and a null in a unique index constrains nothing.',
        v_nullable;
    end if;
  end loop;

  select types.exclusivity_group into v_feast
  from public.sponsorship_types types where types.name = 'Sunday Feast';
  select types.exclusivity_group into v_higher
  from public.sponsorship_types types where types.name = 'Sunday Feast (higher)';
  select types.exclusivity_group into v_garland
  from public.sponsorship_types types where types.name = 'Garland';
  select types.exclusivity_group into v_rajbhog
  from public.sponsorship_types types where types.name = 'Rajbhog';
  select types.exclusivity_group into v_dress
  from public.sponsorship_types types where types.name = 'Deity Dress';

  if v_feast is distinct from v_higher then
    raise exception
      'The two Sunday Feast rates are in different groups, so one Sunday can still be sold twice.';
  end if;

  -- The group is named after the base rate, which is what makes the refusal
  -- readable and what the label function reads back.
  if v_feast is distinct from (select ids.id from public.te_ids ids where ids.key = 'sunday_feast') then
    raise exception 'The Sunday Feast group is not named after the base rate.';
  end if;
  if public.sponsorship_group_label(v_higher) is distinct from 'Sunday Feast' then
    raise exception 'The higher rate calls its group %.',
      coalesce(public.sponsorship_group_label(v_higher), 'nothing');
  end if;

  -- And nothing else was swept into a group with anything else.
  if v_garland = v_rajbhog or v_garland = v_feast or v_rajbhog = v_feast
     or v_dress = v_feast or v_dress = v_garland or v_dress = v_rajbhog then
    raise exception 'Two different sevas were put in one exclusivity group.';
  end if;
  if v_garland is distinct from (select ids.id from public.te_ids ids where ids.key = 'garland')
     or v_dress is distinct from (select ids.id from public.te_ids ids where ids.key = 'deity_dress') then
    raise exception 'An untiered sponsorship is not its own group.';
  end if;

  -- Every booking already in the table agrees with its type.
  select count(*)::integer into v_orphans
  from public.sponsorship_bookings bookings
  join public.sponsorship_types types on types.id = bookings.sponsorship_type_id
  where bookings.exclusivity_group is distinct from types.exclusivity_group;
  if v_orphans <> 0 then
    raise exception '% bookings carry a group their sponsorship does not.', v_orphans;
  end if;
end;
$$;

-- The indexes themselves, read out of the catalogue rather than inferred from
-- behaviour: the race they guarantee cannot be staged from one connection, and
-- the predicate is the promise.
do $$
declare
  v_def text;
begin
  select indexdef into v_def
  from pg_indexes
  where schemaname = 'public'
    and indexname = 'sponsorship_booking_one_live_per_group_and_date';

  if v_def is null then
    raise exception 'There is no one-sponsor-per-group-per-date index.';
  end if;
  if v_def not ilike 'CREATE UNIQUE INDEX%' then
    raise exception 'The one-sponsor-per-group-per-date index is not unique.';
  end if;
  if v_def not ilike '%exclusivity_group%' then
    raise exception
      'The date index is still keyed on the tier, so two rates of one seva still take one day twice.';
  end if;
  if v_def not ilike '%on_date IS NOT NULL%' then
    raise exception
      'The date index does not exclude dateless bookings, so the temple may now have exactly one deity dress ever.';
  end if;
  if v_def not ilike '%''held''%' or v_def not ilike '%''confirmed''%' then
    raise exception 'The date index no longer covers the two live states.';
  end if;

  -- One open hold per devotee per dateless sponsorship. Without devotee_id in
  -- the key this index is the same catastrophe as a missing on_date predicate,
  -- reached by a different door.
  select indexdef into v_def
  from pg_indexes
  where schemaname = 'public'
    and indexname = 'sponsorship_booking_one_live_dateless_hold';

  if v_def is null then
    raise exception 'The one-open-hold-per-devotee index is gone.';
  end if;
  if v_def not ilike '%devotee_id%' then
    raise exception
      'The dateless hold index is not per devotee, so only one devotee at a time may hold a deity dress.';
  end if;
  if v_def not ilike '%on_date IS NULL%' or v_def not ilike '%''held''%' then
    raise exception 'The dateless hold index no longer describes a live dateless hold.';
  end if;

  -- 202608040048's promise is still written down, even though this migration's
  -- index now implies it.
  if not exists (
    select 1 from pg_indexes
    where schemaname = 'public'
      and indexname = 'sponsorship_booking_one_live_per_type_and_date'
  ) then
    raise exception 'The one-sponsor-per-type-per-date index was deleted rather than superseded.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. One Sunday, one feast, whichever rate.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_booking public.sponsorship_bookings;
begin
  v_booking := public.hold_sponsorship(
    (select ids.id from public.te_ids ids where ids.key = 'sunday_feast'),
    (select dates.on_date from public.te_dates dates where dates.key = 'sunday')
  );
  if v_booking.id is null then
    raise exception 'Asha could not sponsor the Sunday Feast.';
  end if;
  if v_booking.amount_cents <> 55100 then
    raise exception 'Asha''s feast was recorded at % cents.', v_booking.amount_cents;
  end if;
  insert into public.te_ids (key, id) values ('asha_feast', v_booking.id);
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-000000000003', true);
set local role authenticated;

do $$
declare
  v_refused boolean := false;
  v_message text;
begin
  begin
    perform public.hold_sponsorship(
      (select ids.id from public.te_ids ids where ids.key = 'sunday_feast_(higher)'),
      (select dates.on_date from public.te_dates dates where dates.key = 'sunday')
    );
  exception when others then
    v_refused := true;
    v_message := sqlerrm;
  end;

  if not v_refused then
    raise exception
      'Two devotees sponsored one Sunday''s feast, one at $551 and one at $751.';
  end if;
  if v_message not ilike '%already been sponsored%' then
    raise exception 'The taken-Sunday refusal is unreadable: %', v_message;
  end if;

  -- The sentence is about the Sunday, not about the rate. "Sunday Feast
  -- (higher) has already been sponsored" is true and useless: it invites the
  -- devotee to go and try the other rate, which is the thing that is gone.
  if v_message not ilike '%Sunday Feast%' then
    raise exception 'The refusal does not say what is taken: %', v_message;
  end if;
  if v_message ilike '%higher%' then
    raise exception
      'The refusal blames the rate rather than the Sunday, so the devotee is invited to try the other rate: %',
      v_message;
  end if;
end;
$$;

reset role;

-- And the index, not the RPC, is what decides. Inserted as the owning superuser
-- with every policy and grant out of the way.
do $$
declare
  v_refused boolean := false;
begin
  begin
    insert into public.sponsorship_bookings
      (sponsorship_type_id, devotee_id, on_date, status, held_until, amount_cents)
    values (
      (select ids.id from public.te_ids ids where ids.key = 'sunday_feast_(higher)'),
      'b0000000-0000-0000-0000-000000000003',
      (select dates.on_date from public.te_dates dates where dates.key = 'sunday'),
      'held', now() + interval '30 minutes', 75100
    );
  exception when unique_violation then
    v_refused := true;
  end;

  if not v_refused then
    raise exception
      'The table itself allowed both rates of one feast to be live on one Sunday.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. A different Sunday is still free, at either rate.
--
--    The group takes a day, not a season. Proved at both rates, because an
--    exclusivity keyed on the group alone rather than on (group, date) would
--    pass a test that only tried one of them.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-000000000003', true);
set local role authenticated;

do $$
declare
  v_booking public.sponsorship_bookings;
begin
  v_booking := public.hold_sponsorship(
    (select ids.id from public.te_ids ids where ids.key = 'sunday_feast_(higher)'),
    (select dates.on_date from public.te_dates dates where dates.key = 'sunday_two')
  );
  if v_booking.id is null then
    raise exception 'The higher rate was refused on a Sunday nobody had taken.';
  end if;
  perform public.release_sponsorship_hold(v_booking.id);
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-000000000004', true);
set local role authenticated;

do $$
declare
  v_booking public.sponsorship_bookings;
begin
  v_booking := public.hold_sponsorship(
    (select ids.id from public.te_ids ids where ids.key = 'sunday_feast'),
    (select dates.on_date from public.te_dates dates where dates.key = 'sunday_two')
  );
  if v_booking.id is null then
    raise exception 'The base rate was refused on a Sunday nobody had taken.';
  end if;
  perform public.release_sponsorship_hold(v_booking.id);
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Different sponsorships stay different.
--
--    A Garland and a Rajbhog on one day are two sevas on one day, and the
--    temple offers both. An exclusivity group that swallowed them would take a
--    booking off the calendar that nobody agreed to give up.
-- ---------------------------------------------------------------------------

do $$
declare
  v_booking public.sponsorship_bookings;
begin
  v_booking := public.hold_sponsorship(
    (select ids.id from public.te_ids ids where ids.key = 'garland'),
    (select dates.on_date from public.te_dates dates where dates.key = 'garland')
  );
  if v_booking.id is null then
    raise exception 'Chandra could not sponsor a garland.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-000000000003', true);
set local role authenticated;

do $$
declare
  v_booking public.sponsorship_bookings;
begin
  v_booking := public.hold_sponsorship(
    (select ids.id from public.te_ids ids where ids.key = 'rajbhog'),
    (select dates.on_date from public.te_dates dates where dates.key = 'garland')
  );
  if v_booking.id is null then
    raise exception 'A rajbhog was refused on a day somebody else had taken a garland.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Three devotees, three deity dresses, no collision.
--
--    This is the claim this migration is most likely to have broken. The index
--    it rewrote is the one 202608040050 spends a page explaining, and the
--    clause that keeps the deity dress unlimited — `on_date is not null` — is a
--    single line in a predicate that nothing else would complain about losing.
--
--    So it is proved four ways: through the RPC by three different devotees,
--    then straight into the table by a fourth, then twice over by that same
--    fourth, and then counted off the rows themselves.
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_booking public.sponsorship_bookings;
begin
  v_booking := public.hold_sponsorship(
    (select ids.id from public.te_ids ids where ids.key = 'deity_dress')
  );
  if v_booking.id is null then
    raise exception 'Asha could not sponsor a deity dress.';
  end if;
  if v_booking.on_date is not null then
    raise exception 'A dateless sponsorship was given the date %.', v_booking.on_date;
  end if;
  insert into public.te_ids (key, id) values ('asha_dress', v_booking.id);
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-000000000003', true);
set local role authenticated;

do $$
declare
  v_booking public.sponsorship_bookings;
begin
  v_booking := public.hold_sponsorship(
    (select ids.id from public.te_ids ids where ids.key = 'deity_dress')
  );
  if v_booking.id is null then
    raise exception 'A second devotee was refused a deity dress.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-000000000004', true);
set local role authenticated;

do $$
declare
  v_booking public.sponsorship_bookings;
begin
  v_booking := public.hold_sponsorship(
    (select ids.id from public.te_ids ids where ids.key = 'deity_dress')
  );
  if v_booking.id is null then
    raise exception 'A third devotee was refused a deity dress.';
  end if;
end;
$$;

-- One devotee still may not leave two payments hanging on one dateless
-- sponsorship: two open holds are two candidates for one payment, and her own
-- money would go to the unmatched queue for no reason.
reset role;
select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_refused boolean := false;
  v_message text;
begin
  begin
    perform public.hold_sponsorship(
      (select ids.id from public.te_ids ids where ids.key = 'deity_dress')
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

  -- A fourth and a fifth, straight into the table, so the proof does not rest
  -- on the RPC — and both by one devotee, because a confirmed dress is outside
  -- the hold index and a devotee who gave one in March may give another in
  -- October.
  insert into public.sponsorship_bookings
    (sponsorship_type_id, devotee_id, on_date, status, held_until, amount_cents)
  values
    ((select ids.id from public.te_ids ids where ids.key = 'deity_dress'),
     'b0000000-0000-0000-0000-000000000005', null, 'confirmed', null, 250000),
    ((select ids.id from public.te_ids ids where ids.key = 'deity_dress'),
     'b0000000-0000-0000-0000-000000000005', null, 'confirmed', null, 250000);

  select count(*)::integer into v_live
  from public.sponsorship_bookings bookings
  join public.sponsorship_types types on types.id = bookings.sponsorship_type_id
  where types.name = 'Deity Dress'
    and bookings.status in ('held', 'confirmed');

  if v_live <> 5 then
    raise exception
      'The table admits only % live deity dress sponsorships, so the dateless case is no longer unlimited.',
      v_live;
  end if;

  -- The denormalised group followed every one of them.
  if exists (
    select 1
    from public.sponsorship_bookings bookings
    join public.sponsorship_types types on types.id = bookings.sponsorship_type_id
    where types.name = 'Deity Dress'
      and bookings.exclusivity_group is distinct from types.exclusivity_group
  ) then
    raise exception 'A deity dress booking carries a group its sponsorship does not.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. The calendar, which must not offer a Sunday that is gone.
--
--    Every rate of the group reports the same day taken by the same booking,
--    and the devotee who took it sees it as hers on both rows rather than
--    seeing a stranger holding the rate she did not pick.
--
--    The deity dress is checked again here, across a whole window, because a
--    dateless type leaking onto the calendar would leak onto every day of it.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_sunday date;
  v_taken integer;
  v_mine integer;
  v_free integer;
  v_dress integer;
  v_booking uuid;
begin
  select dates.on_date into v_sunday from public.te_dates dates where dates.key = 'sunday';
  select ids.id into v_booking from public.te_ids ids where ids.key = 'asha_feast';

  select
    count(*) filter (where calendar.is_taken)::integer,
    count(*) filter (where calendar.is_mine and calendar.booking_id = v_booking)::integer
  into v_taken, v_mine
  from public.sponsorship_availability(v_sunday, v_sunday) calendar
  where calendar.type_name like 'Sunday Feast%';

  if v_taken <> 2 then
    raise exception
      'The calendar shows % of the two Sunday Feast rates as taken on a Sunday somebody has sponsored.',
      v_taken;
  end if;
  if v_mine <> 2 then
    raise exception 'Asha is shown as the sponsor of % of the two rates.', v_mine;
  end if;

  -- A Sunday nobody has taken is free at both rates.
  select count(*) filter (where not calendar.is_taken)::integer into v_free
  from public.sponsorship_availability(
    (select dates.on_date from public.te_dates dates where dates.key = 'sunday_two'),
    (select dates.on_date from public.te_dates dates where dates.key = 'sunday_two')
  ) calendar
  where calendar.type_name like 'Sunday Feast%';

  if v_free <> 2 then
    raise exception 'A free Sunday is offered at % of the two rates.', v_free;
  end if;

  -- And the deity dress is still not on the calendar at all.
  select count(*)::integer into v_dress
  from public.sponsorship_availability(
    (select dates.on_date from public.te_dates dates where dates.key = 'today'),
    (select dates.on_date from public.te_dates dates where dates.key = 'today') + 30
  ) calendar
  where calendar.type_name = 'Deity Dress';

  if v_dress <> 0 then
    raise exception 'The calendar offers the deity dress on % days.', v_dress;
  end if;
end;
$$;

-- Somebody else's Sunday is taken, and that is the only bit they learn.
reset role;
select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-000000000003', true);
set local role authenticated;

do $$
declare
  v_sunday date;
  v_leaked integer;
begin
  select dates.on_date into v_sunday from public.te_dates dates where dates.key = 'sunday';

  select count(*)::integer into v_leaked
  from public.sponsorship_availability(v_sunday, v_sunday) calendar
  where calendar.type_name like 'Sunday Feast%'
    and (calendar.is_mine or calendar.booking_id is not null
         or calendar.booked_by_name is not null);

  if v_leaked <> 0 then
    raise exception 'A devotee learns who holds a Sunday on % rows.', v_leaked;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Giving the Sunday back gives it back at every rate.
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
begin
  perform public.release_sponsorship_hold(
    (select ids.id from public.te_ids ids where ids.key = 'asha_feast')
  );
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-000000000003', true);
set local role authenticated;

do $$
declare
  v_sunday date;
  v_free integer;
  v_booking public.sponsorship_bookings;
begin
  select dates.on_date into v_sunday from public.te_dates dates where dates.key = 'sunday';

  select count(*) filter (where not calendar.is_taken)::integer into v_free
  from public.sponsorship_availability(v_sunday, v_sunday) calendar
  where calendar.type_name like 'Sunday Feast%';

  if v_free <> 2 then
    raise exception
      'A released hold left % of the two rates still showing as taken.', 2 - v_free;
  end if;

  v_booking := public.hold_sponsorship(
    (select ids.id from public.te_ids ids where ids.key = 'sunday_feast_(higher)'),
    v_sunday
  );
  if v_booking.id is null then
    raise exception 'A released Sunday could not be taken at the other rate.';
  end if;
  perform public.release_sponsorship_hold(v_booking.id);
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. An expired hold on one rate does not hold the day against another.
--
--    An index predicate must be immutable, so it cannot mention held_until and
--    an expired hold keeps its grip until something releases it. hold_sponsorship
--    sweeps first — and the sweep has to cover the whole group, or a devotee is
--    told a Sunday is gone by a hold that ran out twenty minutes ago.
-- ---------------------------------------------------------------------------

reset role;

do $$
declare
  v_id uuid;
begin
  insert into public.sponsorship_bookings
    (sponsorship_type_id, devotee_id, on_date, status, held_until, amount_cents)
  values (
    (select ids.id from public.te_ids ids where ids.key = 'sunday_feast'),
    'b0000000-0000-0000-0000-000000000002',
    (select dates.on_date from public.te_dates dates where dates.key = 'sunday_three'),
    'held', now() - interval '1 minute', 55100
  )
  returning id into v_id;
  insert into public.te_ids (key, id) values ('stale_feast', v_id);
end;
$$;

select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-000000000004', true);
set local role authenticated;

do $$
declare
  v_booking public.sponsorship_bookings;
begin
  v_booking := public.hold_sponsorship(
    (select ids.id from public.te_ids ids where ids.key = 'sunday_feast_(higher)'),
    (select dates.on_date from public.te_dates dates where dates.key = 'sunday_three')
  );
  if v_booking.id is null then
    raise exception 'An expired hold on the other rate kept a Sunday off the calendar.';
  end if;
  insert into public.te_ids (key, id) values ('chandra_higher', v_booking.id);
end;
$$;

reset role;

do $$
begin
  if (select bookings.status from public.sponsorship_bookings bookings
      where bookings.id = (select ids.id from public.te_ids ids where ids.key = 'stale_feast'))
     <> 'released' then
    raise exception 'The expired hold on the other rate was never swept.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 9. Rates added later, pages repointed, groups changed by hand.
--
--    The temple will add tiers to other sponsorships. A rate added to a
--    campaign that already has one joins its group, because a rate that quietly
--    failed to join would restore this whole bug for that rate alone.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-000000000002', true);
set local role authenticated;

do $$
declare
  v_booking public.sponsorship_bookings;
begin
  v_booking := public.hold_sponsorship(
    (select ids.id from public.te_ids ids where ids.key = 'sunday_feast'),
    (select dates.on_date from public.te_dates dates where dates.key = 'sunday_four')
  );
  insert into public.te_ids (key, id) values ('asha_fourth', v_booking.id);
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
  v_saved public.sponsorship_types;
  v_group uuid;
begin
  select ids.id into v_group from public.te_ids ids where ids.key = 'feast_group';

  v_saved := public.save_sponsorship_type(
    p_name := 'TE Grand Feast',
    p_amount_cents := 95100,
    p_display_order := 75,
    p_sunday_only := true,
    p_requires_date := true,
    p_zeffy_campaign_url := 'https://www.zeffy.com/embed/ticketing/sunday-feast-sponsorship',
    p_zeffy_campaign_slug := 'sunday-feast-sponsorship'
  );

  if v_saved.exclusivity_group is distinct from v_group then
    raise exception
      'A third rate added to the Sunday Feast page did not join the group, so it can sell a sponsored Sunday again.';
  end if;
  insert into public.te_ids (key, id) values ('grand_feast', v_saved.id);
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-000000000003', true);
set local role authenticated;

do $$
declare
  v_refused boolean := false;
  v_message text;
begin
  begin
    perform public.hold_sponsorship(
      (select ids.id from public.te_ids ids where ids.key = 'grand_feast'),
      (select dates.on_date from public.te_dates dates where dates.key = 'sunday_four')
    );
  exception when others then
    v_refused := true;
    v_message := sqlerrm;
  end;

  if not v_refused then
    raise exception 'A rate added later sold a Sunday that was already sponsored.';
  end if;
  if v_message not ilike '%already been sponsored%' then
    raise exception 'The refusal of a later rate is unreadable: %', v_message;
  end if;
end;
$$;

-- A Zeffy page is a payment page, not a booking rule. Repointing one rate at a
-- page of its own must not dissolve the exclusivity — which is exactly what
-- deriving the group from the slug would have done, silently, on an edit the
-- President has every right to make.
reset role;
select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
  v_saved public.sponsorship_types;
  v_group uuid;
begin
  select ids.id into v_group from public.te_ids ids where ids.key = 'feast_group';

  v_saved := public.save_sponsorship_type(
    p_name := 'Sunday Feast (higher)',
    p_amount_cents := 75100,
    p_id := (select ids.id from public.te_ids ids where ids.key = 'sunday_feast_(higher)'),
    p_display_order := 70,
    p_zeffy_campaign_url := 'https://www.zeffy.com/embed/ticketing/sunday-feast-grand',
    p_zeffy_campaign_slug := 'sunday-feast-grand'
  );

  if v_saved.zeffy_campaign_slug is distinct from 'sunday-feast-grand' then
    raise exception 'The higher rate was not repointed at its own page.';
  end if;
  if v_saved.exclusivity_group is distinct from v_group then
    raise exception
      'Repointing a rate''s Zeffy page split the exclusivity group, so one Sunday can be sold twice again.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-000000000003', true);
set local role authenticated;

do $$
declare
  v_refused boolean := false;
begin
  begin
    perform public.hold_sponsorship(
      (select ids.id from public.te_ids ids where ids.key = 'sunday_feast_(higher)'),
      (select dates.on_date from public.te_dates dates where dates.key = 'sunday_four')
    );
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A repointed page let the higher rate sell a sponsored Sunday.';
  end if;
end;
$$;

-- The President may still say it outright, in both directions, and a regrouping
-- that would leave two devotees on one day is refused rather than resolved.
reset role;
select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
  v_higher uuid;
  v_saved public.sponsorship_types;
begin
  select ids.id into v_higher from public.te_ids ids where ids.key = 'sunday_feast_(higher)';

  v_saved := public.save_sponsorship_type(
    p_name := 'Sunday Feast (higher)',
    p_amount_cents := 75100,
    p_id := v_higher,
    p_display_order := 70,
    p_exclusivity_group_id := v_higher
  );

  if v_saved.exclusivity_group is distinct from v_higher then
    raise exception 'A rate pointed at itself did not become a group of its own.';
  end if;

  -- The bookings already made against it followed.
  if exists (
    select 1 from public.sponsorship_bookings bookings
    where bookings.sponsorship_type_id = v_higher
      and bookings.exclusivity_group is distinct from v_higher
  ) then
    raise exception 'A regrouped rate left its existing bookings in the old group.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-000000000003', true);
set local role authenticated;

do $$
declare
  v_booking public.sponsorship_bookings;
begin
  v_booking := public.hold_sponsorship(
    (select ids.id from public.te_ids ids where ids.key = 'sunday_feast_(higher)'),
    (select dates.on_date from public.te_dates dates where dates.key = 'sunday_four')
  );
  if v_booking.id is null then
    raise exception 'A rate taken out of its group could not be booked on its own.';
  end if;
  insert into public.te_ids (key, id) values ('bimal_fourth', v_booking.id);
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
  v_refused boolean := false;
  v_message text;
begin
  begin
    perform public.save_sponsorship_type(
      p_name := 'Sunday Feast (higher)',
      p_amount_cents := 75100,
      p_id := (select ids.id from public.te_ids ids where ids.key = 'sunday_feast_(higher)'),
      p_display_order := 70,
      p_exclusivity_group_id := (select ids.id from public.te_ids ids where ids.key = 'sunday_feast')
    );
  exception when others then
    v_refused := true;
    v_message := sqlerrm;
  end;

  if not v_refused then
    raise exception
      'Two rates were merged while two devotees held the same Sunday on each of them.';
  end if;
  if v_message not ilike '%Settle those bookings first%' then
    raise exception 'The refusal to merge is unreadable: %', v_message;
  end if;

  -- And a group nobody has ever heard of is refused outright.
  v_refused := false;
  begin
    perform public.save_sponsorship_type(
      p_name := 'Sunday Feast (higher)',
      p_amount_cents := 75100,
      p_id := (select ids.id from public.te_ids ids where ids.key = 'sunday_feast_(higher)'),
      p_display_order := 70,
      p_exclusivity_group_id := 'b0000000-0000-0000-0000-0000000000ff'
    );
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A sponsorship joined a group that does not exist.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-000000000003', true);
set local role authenticated;

do $$
begin
  perform public.release_sponsorship_hold(
    (select ids.id from public.te_ids ids where ids.key = 'bimal_fourth')
  );
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
  v_saved public.sponsorship_types;
  v_group uuid;
begin
  select ids.id into v_group from public.te_ids ids where ids.key = 'feast_group';

  v_saved := public.save_sponsorship_type(
    p_name := 'Sunday Feast (higher)',
    p_amount_cents := 75100,
    p_id := (select ids.id from public.te_ids ids where ids.key = 'sunday_feast_(higher)'),
    p_display_order := 70,
    p_exclusivity_group_id := (select ids.id from public.te_ids ids where ids.key = 'sunday_feast')
  );

  if v_saved.exclusivity_group is distinct from v_group then
    raise exception 'The rates could not be put back into one group once the day was free.';
  end if;

  -- Chandra's live booking on the third Sunday came back with it.
  if (select bookings.exclusivity_group from public.sponsorship_bookings bookings
      where bookings.id = (select ids.id from public.te_ids ids where ids.key = 'chandra_higher'))
     is distinct from v_group then
    raise exception 'A live booking did not follow its rate back into the group.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 10. None of this is reachable anonymously, and no client may write either
--     table directly.
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
        'hold_sponsorship', 'sponsorship_availability', 'list_sponsorship_types',
        'save_sponsorship_type', 'sponsorship_group_label',
        'set_sponsorship_booking_exclusivity_group',
        'set_sponsorship_type_exclusivity_group', 'remap_sponsorship_booking_groups'
      )
      and has_function_privilege('anon', p.oid, 'execute')
  loop
    raise exception 'anon can execute %.', v_function;
  end loop;

  -- The President's form reaches the ten-argument form, and only that one.
  if has_function_privilege(
    'authenticated',
    'public.save_sponsorship_type(text, integer, uuid, boolean, integer, boolean, text, text, boolean, uuid)',
    'execute'
  ) is not true then
    raise exception 'The President cannot reach save_sponsorship_type.';
  end if;
  if exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'save_sponsorship_type'
      and p.pronargs = 9
  ) then
    raise exception
      'Both forms of save_sponsorship_type exist, so every defaulted call is ambiguous.';
  end if;

  foreach v_table in array
    array['public.sponsorship_types', 'public.sponsorship_bookings']
  loop
    foreach v_privilege in array array['insert', 'update', 'delete'] loop
      if has_table_privilege('authenticated', v_table, v_privilege) then
        raise exception 'authenticated holds % on %.', v_privilege, v_table;
      end if;
    end loop;

    if not has_column_privilege('authenticated', v_table, 'exclusivity_group', 'select') then
      raise exception 'A devotee cannot read the exclusivity group on %.', v_table;
    end if;
  end loop;
end;
$$;

select 'tier exclusivity verification passed' as result;

rollback;
