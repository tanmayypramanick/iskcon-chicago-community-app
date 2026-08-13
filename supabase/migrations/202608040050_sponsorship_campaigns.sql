-- The temple's seven Zeffy campaigns, and the one sponsorship that has no date.
--
-- 202608040049_donation_reconciliation.sql seeded a single Zeffy page because a
-- single Zeffy page was all that existed. The temple has since created all
-- seven ticketing campaigns, and creating them surfaced two facts the earlier
-- schema had no room for.
--
-- One campaign, more than one price
-- ---------------------------------
-- The Sunday Feast is one ticketing page with two rates on it: $551 and $751.
-- Those are two rows in sponsorship_types — they have different prices, and the
-- price is copied onto a booking at the moment it is made — but they are one
-- page on Zeffy and therefore one campaign slug. 0049's unique index over the
-- slug forbade exactly that, so it has to go.
--
-- What replaces it has to keep the promise the old one was making. That promise
-- was never "one row per slug" for its own sake; it was that a payment arriving
-- from a campaign can be resolved to one expected price, because the alternative
-- is charging the wrong expectation against real money. A campaign that maps to
-- one-or-more price tiers still keeps that promise as long as no two tiers on a
-- campaign share a price:
--
--     unique (zeffy_campaign_slug, amount_cents) where slug is not null
--
-- The webhook now resolves (campaign, amount paid) rather than (campaign), and
-- that pair is unique again. Two rows at $551 on one page would be the genuine
-- ambiguity — two different sevas, one payment, no way to tell which — and it
-- is exactly what the index still refuses.
--
-- Uniqueness alone would let a President point the Garland at the Sunday Feast
-- page, though, so a second rule says that tiers of one campaign must agree
-- about how they are booked: the same sunday_only, the same requires_date. One
-- Zeffy page presents one set of bookable days, and a page whose tiers disagreed
-- about which days those are would offer a devotee a calendar that the payment
-- behind it does not match. That is enforced by a trigger rather than a CHECK
-- because it is a statement about a group of rows, not about one row.
--
-- What this pair cannot prevent is a President deliberately putting two
-- similarly-shaped sevas — a Garland and a Rajbhog, say — on one page at
-- different prices. Nothing structural can tell those apart from two rates on
-- one seva without inventing a campaign table nobody has asked for, and the
-- reconciliation stays correct either way because the price still resolves. The
-- constraint prevents the ambiguity that costs money and the mismatch that
-- misleads a devotee; the rest is a data-entry decision.
--
-- A deity dress has no day
-- ------------------------
-- Every other sponsorship is a named thing on a named day. A deity outfit is
-- not: it is sewn, and it is offered when it is ready, and the donor does not
-- pick a date because nobody can promise one. So sponsorship_types gains
-- requires_date, false for the Deity Dress alone, and a booking's on_date
-- becomes nullable for that case and that case only.
--
-- The consequence that matters is the one-per-date unique index. It is the
-- whole point of 202608040048 and it must not follow on_date into null:
--
--   * A NULL never equals a NULL, so under the default NULLS DISTINCT the index
--     would already admit many dateless bookings. Relying on that would be
--     relying on a default — a later hand adding NULLS NOT DISTINCT, which
--     Postgres 15 made possible and which reads like a tightening, would
--     silently reduce the temple to one deity dress sponsorship for all time.
--   * So the predicate says `on_date is not null` outright. The index now
--     describes what it always meant: one sponsor per type per *day*, for the
--     types that have days. Several devotees may sponsor a deity dress, and they
--     do not collide, because there is no day for them to collide on.
--
-- A second, much smaller index says a devotee may have only one *live hold* on
-- a dateless sponsorship at a time. Confirmed ones are unlimited — a devotee who
-- gave a dress in March may give another in October — but two open holds by one
-- person are two candidates for one payment, which sends their own money to the
-- unmatched queue for no reason.
--
-- Being told it was offered
-- -------------------------
-- A dated sponsorship needs no completion: the day arrives and the devotee
-- knows. A dateless one would otherwise be paid for and never spoken of again,
-- so the booking gains fulfilled_on and fulfilment_note, and
-- mark_sponsorship_fulfilled records them and tells the donor. It is restricted
-- to app.view_all for the same reason every other whole-congregation write in
-- this feature is: the President and the Tech Admin are the temple, and a
-- devotee who could mark their own sponsorship fulfilled could write the
-- temple's records for it.
--
-- Requires 202608040049_donation_reconciliation.sql.

-- ---------------------------------------------------------------------------
-- 1. Whether a sponsorship is booked to a day at all.
--
--    Defaulting to true, because every sponsorship that existed before this
--    migration is booked to a day and a default of false would quietly take
--    them all off the calendar.
-- ---------------------------------------------------------------------------

alter table public.sponsorship_types
  add column if not exists requires_date boolean not null default true;

comment on column public.sponsorship_types.requires_date is
  'False for a sponsorship offered when it is ready rather than on a day the donor picks.';

update public.sponsorship_types
set requires_date = false,
    updated_at = now()
where name = 'Deity Dress'
  and requires_date;

-- ---------------------------------------------------------------------------
-- 2. One campaign, one-or-more price tiers.
--
--    The old index is dropped rather than left beside the new one: it would
--    refuse the second Sunday Feast tier before the new one was ever consulted.
-- ---------------------------------------------------------------------------

drop index if exists public.sponsorship_types_zeffy_slug_key;

create unique index if not exists sponsorship_types_zeffy_slug_amount_key
  on public.sponsorship_types (zeffy_campaign_slug, amount_cents)
  where zeffy_campaign_slug is not null;

comment on index public.sponsorship_types_zeffy_slug_amount_key is
  'A Zeffy campaign may carry several price tiers, but a payment of a given amount on it resolves to exactly one sponsorship.';

-- Tiers of one campaign are one seva at two rates, so they are booked the same
-- way. A trigger, not a CHECK: the statement is about the other rows sharing
-- the slug, and a CHECK may not look at them.
create or replace function public.enforce_campaign_tiers_agree()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_clash public.sponsorship_types;
begin
  if new.zeffy_campaign_slug is null then
    return new;
  end if;

  select * into v_clash
  from public.sponsorship_types other
  where other.zeffy_campaign_slug = new.zeffy_campaign_slug
    and other.id <> new.id
    and (other.sunday_only <> new.sunday_only
         or other.requires_date <> new.requires_date)
  limit 1;

  if v_clash.id is not null then
    raise exception
      '% cannot share the Zeffy campaign % with %: they are not booked the same way.',
      new.name, new.zeffy_campaign_slug, v_clash.name;
  end if;

  return new;
end;
$$;

comment on function public.enforce_campaign_tiers_agree() is
  'Keeps the price tiers on one Zeffy campaign agreeing about how they are booked.';

drop trigger if exists sponsorship_type_campaign_tiers_agree on public.sponsorship_types;
create trigger sponsorship_type_campaign_tiers_agree
  before insert or update of zeffy_campaign_slug, sunday_only, requires_date
  on public.sponsorship_types
  for each row execute function public.enforce_campaign_tiers_agree();

-- ---------------------------------------------------------------------------
-- 3. The seven campaigns, as the temple made them.
--
--    `diety-dress` is misspelt and is written here exactly as the temple typed
--    it, because it is their live URL and a corrected spelling is a 404 in a
--    devotee's browser at the moment they were about to give.
--
--    Both Sunday Feast rows take the one slug: two rates, one page.
--
--    A row is only written when it has not been pointed somewhere else by hand.
--    Re-running the migration is then a no-op, and a President who has since
--    edited a campaign through the app keeps their edit.
-- ---------------------------------------------------------------------------

update public.sponsorship_types
set zeffy_campaign_slug = seed.slug,
    zeffy_campaign_url = 'https://www.zeffy.com/embed/ticketing/' || seed.slug,
    updated_at = now()
from (values
  ('Mangal Aarti',          'mangala-aarti'),
  ('Breakfast',             'breakfast-6'),
  ('Sandhya Bhog',          'sandhya-bhog'),
  ('Rajbhog',               'rajbhog'),
  ('Garland',               'garland'),
  ('Sunday Feast',          'sunday-feast-sponsorship'),
  ('Sunday Feast (higher)', 'sunday-feast-sponsorship'),
  ('Deity Dress',           'diety-dress')
) as seed(name, slug)
where sponsorship_types.name = seed.name
  and (sponsorship_types.zeffy_campaign_slug is null
       or sponsorship_types.zeffy_campaign_slug = seed.slug)
  and (sponsorship_types.zeffy_campaign_slug is distinct from seed.slug
       or sponsorship_types.zeffy_campaign_url is distinct from
          'https://www.zeffy.com/embed/ticketing/' || seed.slug);

-- ---------------------------------------------------------------------------
-- 4. A booking that may have no date, and that can be recorded as offered.
-- ---------------------------------------------------------------------------

alter table public.sponsorship_bookings
  alter column on_date drop not null;

alter table public.sponsorship_bookings
  add column if not exists fulfilled_on date,
  add column if not exists fulfilment_note text;

comment on column public.sponsorship_bookings.fulfilled_on is
  'The day the temple actually offered a dateless sponsorship. Null until it has been.';

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'sponsorship_booking_note_needs_fulfilment'
  ) then
    alter table public.sponsorship_bookings
      add constraint sponsorship_booking_note_needs_fulfilment check (
        fulfilment_note is null or fulfilled_on is not null
      );
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. THE constraint, restated so that null cannot slip past it.
--
--    Identical in force to 202608040048's for every sponsorship that has a
--    date. The added predicate is not a relaxation: a dateless booking was
--    never a row this index had anything true to say about, and saying so out
--    loud is what stops a later NULLS NOT DISTINCT from turning the temple's
--    deity dress into a thing exactly one devotee may ever sponsor.
-- ---------------------------------------------------------------------------

drop index if exists public.sponsorship_booking_one_live_per_type_and_date;

create unique index if not exists sponsorship_booking_one_live_per_type_and_date
  on public.sponsorship_bookings (sponsorship_type_id, on_date)
  where status in ('held', 'confirmed') and on_date is not null;

comment on index public.sponsorship_booking_one_live_per_type_and_date is
  'One sponsor per type per day. Dateless sponsorships are outside it by construction: they have no day to collide on.';

-- One open hold at a time on a dateless sponsorship, per devotee. Confirmed
-- ones are deliberately outside the predicate — a devotee may sponsor a deity
-- dress again, and again after that.
create unique index if not exists sponsorship_booking_one_live_dateless_hold
  on public.sponsorship_bookings (sponsorship_type_id, devotee_id)
  where status = 'held' and on_date is null;

-- A date on a dateless sponsorship, or a dateless booking of a dated one, is
-- refused by the table and not only by the RPC — the same reasoning as the
-- index above it. A row inserted straight into the table is still refused.
create or replace function public.enforce_sponsorship_booking_date()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_type public.sponsorship_types;
begin
  select * into v_type
  from public.sponsorship_types
  where sponsorship_types.id = new.sponsorship_type_id;

  if v_type.id is null then
    -- The foreign key is about to say so in better words.
    return new;
  end if;

  if v_type.requires_date and new.on_date is null then
    raise exception '% is sponsored on a date, and none was given.', v_type.name;
  end if;

  if not v_type.requires_date and new.on_date is not null then
    raise exception '% is offered when it is ready, so it cannot be booked to a date.',
      v_type.name;
  end if;

  return new;
end;
$$;

drop trigger if exists sponsorship_booking_date_matches_type on public.sponsorship_bookings;
create trigger sponsorship_booking_date_matches_type
  before insert or update of sponsorship_type_id, on_date
  on public.sponsorship_bookings
  for each row execute function public.enforce_sponsorship_booking_date();

-- ---------------------------------------------------------------------------
-- 6. Column grants for what was just added.
--
--    A devotee may see that a sponsorship has no date and that hers was
--    offered. The policies from 202608040048 are untouched and are still what
--    decides whose rows she sees at all.
-- ---------------------------------------------------------------------------

grant select (requires_date) on public.sponsorship_types to authenticated;
grant select (fulfilled_on, fulfilment_note) on public.sponsorship_bookings to authenticated;

-- ---------------------------------------------------------------------------
-- 7. The sponsorship list, now saying whether a date is wanted.
--
--    Dropped and recreated because the row is wider. The app needs this to know
--    whether to open a calendar or a single "sponsor a deity dress" button.
-- ---------------------------------------------------------------------------

drop function if exists public.list_sponsorship_types();

create or replace function public.list_sponsorship_types()
returns table (
  id uuid,
  name text,
  amount_cents integer,
  is_active boolean,
  display_order integer,
  sunday_only boolean,
  requires_date boolean,
  zeffy_campaign_url text,
  zeffy_campaign_slug text
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    sponsorship_types.id,
    sponsorship_types.name,
    sponsorship_types.amount_cents,
    sponsorship_types.is_active,
    sponsorship_types.display_order,
    sponsorship_types.sunday_only,
    sponsorship_types.requires_date,
    sponsorship_types.zeffy_campaign_url,
    sponsorship_types.zeffy_campaign_slug
  from public.sponsorship_types
  where auth.uid() is not null
    and (sponsorship_types.is_active or public.may_view_all_giving())
  order by sponsorship_types.display_order, sponsorship_types.name
$$;

revoke all on function public.list_sponsorship_types() from public, anon;
grant execute on function public.list_sponsorship_types() to authenticated;

-- ---------------------------------------------------------------------------
-- 8. Saving a sponsorship type, now including whether it wants a date.
--
--    Same shape and same reasoning as 0049's: a null means "leave it alone" so
--    a President editing a price through a form that predates this column does
--    not silently turn the deity dress into a dated seva.
--
--    The eight-argument form is dropped rather than kept beside this one, for
--    the reason 0049 gives at length: both would have defaults past the second
--    argument and Postgres would refuse the call as ambiguous.
-- ---------------------------------------------------------------------------

drop function if exists public.save_sponsorship_type(
  text, integer, uuid, boolean, integer, boolean, text, text
);

create or replace function public.save_sponsorship_type(
  p_name text,
  p_amount_cents integer,
  p_id uuid default null,
  p_is_active boolean default true,
  p_display_order integer default null,
  p_sunday_only boolean default null,
  p_zeffy_campaign_url text default null,
  p_zeffy_campaign_slug text default null,
  p_requires_date boolean default null
)
returns public.sponsorship_types
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_clean_name text;
  v_order integer;
  v_url text;
  v_slug text;
  v_clear_url boolean;
  v_clear_slug boolean;
  v_saved public.sponsorship_types;
begin
  if auth.uid() is null then
    raise exception 'Sign in to change the sponsorship list.';
  end if;

  if not public.may_view_all_giving() then
    raise exception 'Only the President or a Tech Admin can change the sponsorship list.';
  end if;

  v_clean_name := nullif(trim(coalesce(p_name, '')), '');
  if v_clean_name is null then
    raise exception 'Please name the sponsorship.';
  end if;

  if p_amount_cents is null or p_amount_cents <= 0 then
    raise exception 'A sponsorship needs an amount in cents, for example 15100 for $151.';
  end if;

  v_order := coalesce(
    p_display_order,
    (select coalesce(max(existing.display_order), 0) + 10
     from public.sponsorship_types existing)
  );

  -- '' means clear; null means leave as it is.
  v_clear_url := p_zeffy_campaign_url is not null and trim(p_zeffy_campaign_url) = '';
  v_clear_slug := p_zeffy_campaign_slug is not null and trim(p_zeffy_campaign_slug) = '';
  v_url := nullif(trim(coalesce(p_zeffy_campaign_url, '')), '');
  v_slug := lower(nullif(trim(coalesce(p_zeffy_campaign_slug, '')), ''));

  -- A whole Zeffy URL pasted into the slug field is the likeliest mistake, and
  -- it would silently stop every payment on that page from reconciling. Take
  -- the last path segment instead of refusing a President who pasted sensibly.
  if v_slug is not null and v_slug like '%/%' then
    v_slug := nullif(regexp_replace(v_slug, '^.*/([^/?#]+).*$', '\1'), '');
  end if;

  if v_slug is not null and v_slug !~ '^[a-z0-9][a-z0-9-]*$' then
    raise exception 'A Zeffy campaign slug looks like sunday-feast-sponsorship.';
  end if;

  if p_id is null then
    insert into public.sponsorship_types (
      name, amount_cents, is_active, display_order,
      sunday_only, requires_date, zeffy_campaign_url, zeffy_campaign_slug
    )
    values (
      v_clean_name, p_amount_cents, coalesce(p_is_active, true), v_order,
      coalesce(p_sunday_only, false), coalesce(p_requires_date, true), v_url, v_slug
    )
    returning * into v_saved;
  else
    update public.sponsorship_types
    set name = v_clean_name,
        amount_cents = p_amount_cents,
        is_active = coalesce(p_is_active, true),
        display_order = v_order,
        sunday_only = coalesce(p_sunday_only, sponsorship_types.sunday_only),
        requires_date = coalesce(p_requires_date, sponsorship_types.requires_date),
        zeffy_campaign_url = case
          when v_clear_url then null
          else coalesce(v_url, sponsorship_types.zeffy_campaign_url)
        end,
        zeffy_campaign_slug = case
          when v_clear_slug then null
          else coalesce(v_slug, sponsorship_types.zeffy_campaign_slug)
        end,
        updated_at = now()
    where sponsorship_types.id = p_id
    returning * into v_saved;

    if v_saved.id is null then
      raise exception 'That sponsorship could not be found.';
    end if;
  end if;

  return v_saved;
end;
$$;

revoke all on function public.save_sponsorship_type(
  text, integer, uuid, boolean, integer, boolean, text, text, boolean
) from public, anon;
grant execute on function public.save_sponsorship_type(
  text, integer, uuid, boolean, integer, boolean, text, text, boolean
) to authenticated;

-- ---------------------------------------------------------------------------
-- 9. Taking a date, or taking no date.
--
--    The signature is 202608040048's and stays that way: p_on_date is now
--    genuinely optional rather than merely nullable, and the type decides which
--    of the two it must be. Passing a date for a deity dress is refused as
--    plainly as omitting one for a garland, because a devotee who chose the
--    14th for a dress the temple will offer in March has been misled by a screen
--    and should be told so rather than quietly given a different day.
--
--    Every refusal below the type lookup is now inside the branch it belongs
--    to. A past date, a Sunday rule and a taken day are all statements about a
--    date, and a sponsorship with no date cannot be wrong about any of them.
-- ---------------------------------------------------------------------------

create or replace function public.hold_sponsorship(
  p_type_id uuid,
  p_on_date date default null
)
returns public.sponsorship_bookings
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_type public.sponsorship_types;
  v_today date := (now() at time zone 'America/Chicago')::date;
  v_booking public.sponsorship_bookings;
  v_taken boolean;
begin
  if auth.uid() is null then
    raise exception 'Sign in to sponsor a seva.';
  end if;

  select * into v_type
  from public.sponsorship_types
  where sponsorship_types.id = p_type_id;

  if v_type.id is null then
    raise exception 'That sponsorship could not be found.';
  end if;

  if not v_type.is_active then
    raise exception '% is not being offered at the moment.', v_type.name;
  end if;

  if v_type.requires_date then
    if p_on_date is null then
      raise exception 'Please choose a date to sponsor.';
    end if;

    -- Chicago, not UTC. Today is still bookable; the temple can take a
    -- sponsorship for this evening's arati at four in the afternoon.
    if p_on_date < v_today then
      raise exception 'That date has already passed. Please choose today or a later date.';
    end if;

    -- The Sunday Feast is served on Sundays. on_date is a bare calendar date, so
    -- this answer is the same whether the devotee is booking from Chicago, Delhi,
    -- or an aeroplane over the date line.
    if v_type.sunday_only and not public.is_sunday_in_chicago(p_on_date) then
      raise exception '% is only offered on Sundays. % is a %.',
        v_type.name,
        to_char(p_on_date, 'FMDD FMMonth YYYY'),
        trim(to_char(p_on_date, 'FMDay'));
    end if;

    -- Free anything abandoned on this exact type and date.
    update public.sponsorship_bookings
    set status = 'released', held_until = null, updated_at = now()
    where sponsorship_bookings.sponsorship_type_id = v_type.id
      and sponsorship_bookings.on_date = p_on_date
      and sponsorship_bookings.status = 'held'
      and sponsorship_bookings.held_until <= now();

    select exists (
      select 1 from public.sponsorship_bookings
      where sponsorship_bookings.sponsorship_type_id = v_type.id
        and sponsorship_bookings.on_date = p_on_date
        and sponsorship_bookings.status in ('held', 'confirmed')
    ) into v_taken;

    if v_taken then
      raise exception '% on % has already been sponsored. Please choose another date.',
        v_type.name, to_char(p_on_date, 'FMDay FMDD FMMonth YYYY');
    end if;
  else
    if p_on_date is not null then
      raise exception '% is offered when it is ready, so there is no date to choose.',
        v_type.name;
    end if;

    -- This devotee's own abandoned hold on this dateless sponsorship. Nobody
    -- else's is touched: a dateless sponsorship is not a thing they compete for.
    update public.sponsorship_bookings
    set status = 'released', held_until = null, updated_at = now()
    where sponsorship_bookings.sponsorship_type_id = v_type.id
      and sponsorship_bookings.devotee_id = auth.uid()
      and sponsorship_bookings.on_date is null
      and sponsorship_bookings.status = 'held'
      and sponsorship_bookings.held_until <= now();

    select exists (
      select 1 from public.sponsorship_bookings
      where sponsorship_bookings.sponsorship_type_id = v_type.id
        and sponsorship_bookings.devotee_id = auth.uid()
        and sponsorship_bookings.on_date is null
        and sponsorship_bookings.status = 'held'
    ) into v_taken;

    if v_taken then
      raise exception 'You already have a % waiting to be paid for. Finish or release that one first.',
        v_type.name;
    end if;
  end if;

  begin
    insert into public.sponsorship_bookings (
      sponsorship_type_id, devotee_id, on_date, status, held_until, amount_cents
    )
    values (
      v_type.id, auth.uid(), p_on_date, 'held',
      now() + interval '30 minutes', v_type.amount_cents
    )
    returning * into v_booking;
  exception when unique_violation then
    -- Somebody committed between the check above and this insert. This is the
    -- case the partial unique indexes exist for, and which of the two spoke is
    -- decided by whether this sponsorship has a date at all.
    if v_type.requires_date then
      raise exception '% on % has already been sponsored. Please choose another date.',
        v_type.name, to_char(p_on_date, 'FMDay FMDD FMMonth YYYY');
    else
      raise exception 'You already have a % waiting to be paid for. Finish or release that one first.',
        v_type.name;
    end if;
  end;

  return v_booking;
end;
$$;

revoke all on function public.hold_sponsorship(uuid, date) from public, anon;
grant execute on function public.hold_sponsorship(uuid, date) to authenticated;

-- ---------------------------------------------------------------------------
-- 10. The calendar, which has nothing to say about a dateless sponsorship.
--
--     Unchanged from 0049 but for one clause. A Deity Dress row on every day of
--     a 400-day window would be 400 identical taps that all mean the same thing,
--     and a devotee tapping the 3rd would reasonably believe the dress arrives
--     on the 3rd. It is offered through the sponsorship list instead, which is
--     why list_sponsorship_types now carries requires_date.
-- ---------------------------------------------------------------------------

create or replace function public.sponsorship_availability(
  p_from date,
  p_to date
)
returns table (
  sponsorship_type_id uuid,
  type_name text,
  amount_cents integer,
  on_date date,
  is_taken boolean,
  is_mine boolean,
  booking_id uuid,
  booked_by_name text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_from date := coalesce(p_from, (now() at time zone 'America/Chicago')::date);
  v_to date;
begin
  if auth.uid() is null then
    raise exception 'Sign in to see the sponsorship calendar.';
  end if;

  v_to := coalesce(p_to, v_from + 30);

  if v_to < v_from then
    raise exception 'The calendar window ends before it starts.';
  end if;

  if v_to - v_from > 400 then
    raise exception 'Ask for at most 400 days of calendar at a time.';
  end if;

  return query
  select
    types.id,
    types.name,
    types.amount_cents,
    days.on_day::date,
    live.id is not null,
    coalesce(live.devotee_id = auth.uid(), false),
    case
      when live.id is null then null
      when live.devotee_id = auth.uid() or public.may_view_all_giving() then live.id
      else null
    end,
    case
      when live.id is null then null
      when live.devotee_id = auth.uid() or public.may_view_all_giving() then booker.name
      else null
    end
  from public.sponsorship_types types
  cross join generate_series(v_from, v_to, interval '1 day') as days(on_day)
  left join lateral (
    select bookings.id, bookings.devotee_id
    from public.sponsorship_bookings bookings
    where bookings.sponsorship_type_id = types.id
      and bookings.on_date = days.on_day::date
      and (
        bookings.status = 'confirmed'
        or (bookings.status = 'held' and bookings.held_until > now())
      )
    limit 1
  ) live on true
  left join public.users booker on booker.id = live.devotee_id
  where types.is_active
    and types.requires_date
    and (
      not types.sunday_only
      or public.is_sunday_in_chicago(days.on_day::date)
    )
  order by days.on_day, types.display_order, types.name;
end;
$$;

revoke all on function public.sponsorship_availability(date, date) from public, anon;
grant execute on function public.sponsorship_availability(date, date) to authenticated;

-- ---------------------------------------------------------------------------
-- 11. Recording a gift, when a campaign is more than one price.
--
--     The signature is 202608040048's, unchanged, for the reasons 0049 gives:
--     it is what the webhook calls, what the grants name, and what both earlier
--     verification scripts assert by regprocedure.
--
--     One thing changes, and it changes because section 2 above changed. 0049
--     resolved a campaign slug to a single sponsorship_types row with LIMIT 1.
--     With two Sunday Feast tiers on one slug that LIMIT 1 is a coin toss, and
--     it is consulted twice in places where a wrong answer is expensive:
--
--       * it narrows the candidate holds to one sponsorship_type_id, so a
--         devotee holding the $751 tier and paying $751 would have had her own
--         hold filtered out by the $551 row winning the toss, and her matched
--         sponsorship would have gone to the unmatched queue instead.
--       * it supplies expected_amount_cents when nobody was holding anything,
--         so a $751 payment could have been recorded as $200 short of a $551
--         sponsorship she never booked.
--
--     So a campaign now resolves to the *set* of its tiers for narrowing, and to
--     the tier nearest the amount actually paid for the expectation — which is
--     the exact tier whenever the devotee paid one of the campaign's prices, and
--     the nearest one when they did not, so the difference on the President's
--     screen is the smallest true statement available.
-- ---------------------------------------------------------------------------

create or replace function public.record_donation(
  p_external_payment_id text,
  p_amount_cents integer,
  p_kind text default 'one_time',
  p_recurrence text default null,
  p_currency text default 'USD',
  p_donor_id uuid default null,
  p_donor_name text default null,
  p_donor_email text default null,
  p_sponsorship_booking_id uuid default null,
  p_payload jsonb default '{}'::jsonb,
  p_received_at timestamptz default null
)
returns public.donations
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_external text;
  v_kind text;
  v_recurrence text;
  v_currency text;
  v_email text;
  v_donor uuid;
  v_received timestamptz;
  v_slug text;
  v_campaign_types uuid[];
  v_campaign public.sponsorship_types;
  v_donation public.donations;
  v_booking public.sponsorship_bookings;
  v_candidates integer := 0;
  v_exact integer := 0;
  v_match_booking uuid;
  v_lone_booking uuid;
  v_status text;
  v_reason text;
  v_expected integer;
  v_expected_type uuid;
begin
  if not public.is_backend_caller() then
    raise exception 'Donations are recorded by the payment webhook, not from the app.';
  end if;

  v_external := nullif(trim(coalesce(p_external_payment_id, '')), '');
  if v_external is null then
    raise exception 'A donation needs the payment id the processor reported.';
  end if;

  if p_amount_cents is null or p_amount_cents <= 0 then
    raise exception 'A donation needs a positive amount in cents.';
  end if;

  v_kind := coalesce(nullif(trim(coalesce(p_kind, '')), ''), 'one_time');
  if v_kind not in ('one_time', 'recurring') then
    raise exception 'A donation is either one_time or recurring.';
  end if;

  v_recurrence := nullif(trim(coalesce(p_recurrence, '')), '');
  if v_kind = 'one_time' then
    v_recurrence := null;
  elsif v_recurrence is null or v_recurrence not in ('monthly', 'quarterly', 'yearly') then
    raise exception 'A recurring donation repeats monthly, quarterly, or yearly.';
  end if;

  v_currency := upper(coalesce(nullif(trim(coalesce(p_currency, '')), ''), 'USD'));
  v_email := nullif(lower(trim(coalesce(p_donor_email, ''))), '');
  v_received := coalesce(p_received_at, now());

  -- Zeffy knows an email address, not a user id. Matching it to a devotee is
  -- what turns "somebody gave $151" into "this devotee's giving history".
  v_donor := p_donor_id;
  if v_donor is null and v_email is not null then
    select users.id into v_donor
    from public.users
    where lower(users.email) = v_email
    limit 1;
  end if;

  -- Which Zeffy page the money came through. The first key is what this repo's
  -- webhook writes; the rest are read so a payload from an older deploy, or a
  -- Zeffy object stored flat, is still understood.
  v_slug := lower(nullif(trim(coalesce(
    p_payload ->> 'campaign_slug',
    p_payload #>> '{payment,campaign,slug}',
    p_payload #>> '{campaign,slug}',
    ''
  )), ''));

  if v_slug is not null then
    -- Every tier on the page, for narrowing the candidate holds.
    select array_agg(tiers.id order by tiers.amount_cents, tiers.id)
    into v_campaign_types
    from public.sponsorship_types tiers
    where lower(tiers.zeffy_campaign_slug) = v_slug;

    if v_campaign_types is not null then
      -- The tier the money names. Exact when they paid one of the campaign's
      -- prices, nearest otherwise, and deterministic either way.
      select * into v_campaign
      from public.sponsorship_types tiers
      where tiers.id = any (v_campaign_types)
      order by abs(tiers.amount_cents - p_amount_cents), tiers.amount_cents, tiers.id
      limit 1;
    end if;
  end if;

  if p_sponsorship_booking_id is not null then
    -- The caller named the booking. FOR UPDATE so two deliveries of the same
    -- payment cannot both walk into the confirmation below.
    select * into v_booking
    from public.sponsorship_bookings
    where sponsorship_bookings.id = p_sponsorship_booking_id
    for update;

    if v_booking.id is null then
      raise exception 'That sponsorship booking could not be found.';
    end if;

    v_donor := coalesce(v_donor, v_booking.devotee_id);
    v_status := 'matched';
    v_expected := v_booking.amount_cents;
    v_expected_type := v_booking.sponsorship_type_id;
  else
    -- The matching rule. Only holds that were live at the moment the money
    -- landed, only this donor's, only inside the window, and only on this
    -- campaign's sponsorships when we recognise the campaign.
    if v_donor is not null or v_email is not null then
      select
        count(*)::integer,
        (count(*) filter (where candidates.amount_cents = p_amount_cents))::integer,
        -- Oldest first, so the reading is deterministic even though a second
        -- exact candidate sends the whole thing to the queue anyway.
        (array_agg(candidates.id order by candidates.created_at, candidates.id)
           filter (where candidates.amount_cents = p_amount_cents))[1],
        (array_agg(candidates.id order by candidates.created_at, candidates.id))[1]
      into v_candidates, v_exact, v_match_booking, v_lone_booking
      from (
        select
          bookings.id,
          bookings.amount_cents,
          bookings.created_at
        from public.sponsorship_bookings bookings
        left join public.users devotee on devotee.id = bookings.devotee_id
        where bookings.status = 'held'
          and bookings.held_until > v_received
          and bookings.created_at >= v_received - public.zeffy_match_window()
          and bookings.created_at <= v_received + interval '5 minutes'
          and (
            (v_donor is not null and bookings.devotee_id = v_donor)
            or (v_email is not null and lower(devotee.email) = v_email)
          )
          and (
            v_campaign_types is null
            or bookings.sponsorship_type_id = any (v_campaign_types)
          )
      ) candidates;
    end if;

    if v_exact = 1 then
      select * into v_booking
      from public.sponsorship_bookings
      where sponsorship_bookings.id = v_match_booking
      for update;

      v_status := 'matched';
      v_donor := coalesce(v_donor, v_booking.devotee_id);
      v_expected := v_booking.amount_cents;
      v_expected_type := v_booking.sponsorship_type_id;

    elsif v_exact > 1 or v_candidates > 1 then
      -- Two holds fit. Choosing one takes a date from a devotee who paid for
      -- it, so nobody's is chosen.
      v_status := 'unmatched';
      v_reason := 'several_candidates';

    elsif v_candidates = 1 then
      -- One hold was open and it is not priced at what was paid. The temple
      -- must see both numbers; the sponsorship stays unconfirmed until a human
      -- says otherwise.
      v_status := 'unmatched';
      v_reason := 'amount_mismatch';
      select bookings.amount_cents, bookings.sponsorship_type_id
        into v_expected, v_expected_type
      from public.sponsorship_bookings bookings
      where bookings.id = v_lone_booking;

    elsif v_campaign.id is not null then
      -- Paid on a sponsorship page with nothing held. Somebody used the Zeffy
      -- link directly, or the hold lapsed before the card cleared. The expected
      -- price is the campaign tier's, so the amount can still be checked.
      v_status := 'unmatched';
      v_reason := 'no_candidate';
      v_expected := v_campaign.amount_cents;
      v_expected_type := v_campaign.id;

    else
      -- No campaign, no hold: a plain gift, complete as it stands.
      v_status := 'general';
    end if;
  end if;

  insert into public.donations (
    donor_id, donor_name, donor_email, amount_cents, currency,
    kind, recurrence, external_payment_id, payload,
    sponsorship_booking_id, received_at,
    match_status, unmatched_reason, zeffy_campaign_slug,
    expected_sponsorship_type_id, expected_amount_cents, matched_at
  )
  values (
    v_donor,
    nullif(trim(coalesce(p_donor_name, '')), ''),
    v_email,
    p_amount_cents,
    v_currency,
    v_kind,
    v_recurrence,
    v_external,
    coalesce(p_payload, '{}'::jsonb),
    case when v_status = 'matched' then coalesce(p_sponsorship_booking_id, v_match_booking) end,
    v_received,
    v_status,
    v_reason,
    v_slug,
    v_expected_type,
    v_expected,
    case when v_status = 'matched' then now() end
  )
  on conflict on constraint donation_external_payment_id_unique do nothing
  returning * into v_donation;

  if v_donation.id is null then
    -- The webhook has been delivered before. Hand back what was recorded then
    -- and touch nothing: the booking was already confirmed by the first call.
    select * into v_donation
    from public.donations
    where donations.external_payment_id = v_external;
    return v_donation;
  end if;

  if v_status = 'matched' and v_booking.id is not null and v_booking.status <> 'confirmed' then
    begin
      update public.sponsorship_bookings
      set status = 'confirmed', held_until = null, updated_at = now()
      where sponsorship_bookings.id = v_booking.id;
    exception when unique_violation then
      -- The hold ran out and the date went to somebody else. The money is
      -- recorded and stays linked to the booking it was meant for, but the
      -- sponsorship is not confirmed and the temple has to settle it.
      raise warning 'Donation % arrived after booking % lost its date.',
        v_external, v_booking.id;

      update public.donations
      set match_status = 'unmatched',
          unmatched_reason = 'booking_lost_date',
          matched_at = null
      where donations.id = v_donation.id
      returning * into v_donation;
    end;
  end if;

  return v_donation;
end;
$$;

revoke all on function public.record_donation(
  text, integer, text, text, text, uuid, text, text, uuid, jsonb, timestamptz
) from public, anon, authenticated;
grant execute on function public.record_donation(
  text, integer, text, text, text, uuid, text, text, uuid, jsonb, timestamptz
) to service_role;

-- ---------------------------------------------------------------------------
-- 12. Recording that a dateless sponsorship was offered, and saying so.
--
--     The President or a Tech Admin. Not the donor: a devotee who could mark
--     her own sponsorship fulfilled would be writing the temple's record of
--     what the temple did, and the notification below would then be the app
--     telling her what she has just told it.
--
--     Only a confirmed sponsorship can be fulfilled. A held one has not been
--     paid for, and a released one is not a sponsorship at all.
--
--     Not a future date. "The dress will be offered on the 3rd" is a plan, and
--     a plan recorded as a fact is how a donor comes to be told something that
--     has not happened.
--
--     Once, and once only. fulfilled_on is history; a second call is either a
--     double tap or a correction, and a correction to the temple's record of
--     what it did is not a thing one RPC call should be able to make silently.
-- ---------------------------------------------------------------------------

create or replace function public.mark_sponsorship_fulfilled(
  p_booking_id uuid,
  p_on_date date default null,
  p_note text default null
)
returns public.sponsorship_bookings
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_booking public.sponsorship_bookings;
  v_type public.sponsorship_types;
  v_today date := (now() at time zone 'America/Chicago')::date;
  v_on date;
  v_note text;
  v_body text;
begin
  if auth.uid() is null then
    raise exception 'Sign in to record a sponsorship as offered.';
  end if;

  if not public.may_view_all_giving() then
    raise exception 'Only the President or a Tech Admin can record a sponsorship as offered.';
  end if;

  select * into v_booking
  from public.sponsorship_bookings
  where sponsorship_bookings.id = p_booking_id
  for update;

  if v_booking.id is null then
    raise exception 'That sponsorship could not be found.';
  end if;

  select * into v_type
  from public.sponsorship_types
  where sponsorship_types.id = v_booking.sponsorship_type_id;

  if v_booking.status <> 'confirmed' then
    raise exception 'That sponsorship has not been paid for yet, so it cannot be recorded as offered.';
  end if;

  if v_booking.fulfilled_on is not null then
    raise exception 'That sponsorship was already recorded as offered on %.',
      to_char(v_booking.fulfilled_on, 'FMDD FMMonth YYYY');
  end if;

  v_on := coalesce(p_on_date, v_today);

  if v_on > v_today then
    raise exception 'That day has not arrived yet. Record a sponsorship as offered once it has been.';
  end if;

  v_note := nullif(trim(coalesce(p_note, '')), '');

  update public.sponsorship_bookings
  set fulfilled_on = v_on,
      fulfilment_note = v_note,
      updated_at = now()
  where sponsorship_bookings.id = v_booking.id
  returning * into v_booking;

  v_body := 'Your ' || coalesce(v_type.name, 'sponsorship') || ' was offered on '
    || to_char(v_on, 'FMDD FMMonth YYYY') || '.';
  if v_note is not null then
    v_body := v_body || ' ' || v_note;
  end if;

  perform public.queue_app_notification(
    v_booking.devotee_id,
    'sponsorship_fulfilled',
    'Your sponsorship has been offered',
    v_body,
    jsonb_build_object(
      'bookingId', v_booking.id,
      'sponsorshipTypeId', v_booking.sponsorship_type_id,
      'fulfilledOn', v_on
    )
  );

  return v_booking;
end;
$$;

comment on function public.mark_sponsorship_fulfilled(uuid, date, text) is
  'Records the day the temple offered a sponsorship and tells the donor. President and Tech Admin only.';

revoke all on function public.mark_sponsorship_fulfilled(uuid, date, text) from public, anon;
grant execute on function public.mark_sponsorship_fulfilled(uuid, date, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 13. The sponsorship lists, now carrying the fulfilment.
--
--     Dropped and recreated because the rows are wider. A devotee's own list is
--     where "has my deity dress been offered yet" is answered on the day she
--     wonders rather than only in the moment the notification arrives.
-- ---------------------------------------------------------------------------

drop function if exists public.list_my_sponsorships();

create or replace function public.list_my_sponsorships()
returns table (
  id uuid,
  sponsorship_type_id uuid,
  type_name text,
  amount_cents integer,
  on_date date,
  requires_date boolean,
  status text,
  held_until timestamptz,
  fulfilled_on date,
  fulfilment_note text,
  created_at timestamptz,
  donation_id uuid
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    bookings.id,
    bookings.sponsorship_type_id,
    types.name,
    bookings.amount_cents,
    bookings.on_date,
    types.requires_date,
    bookings.status,
    bookings.held_until,
    bookings.fulfilled_on,
    bookings.fulfilment_note,
    bookings.created_at,
    gift.id
  from public.sponsorship_bookings bookings
  join public.sponsorship_types types on types.id = bookings.sponsorship_type_id
  left join public.donations gift on gift.sponsorship_booking_id = bookings.id
  where auth.uid() is not null
    and bookings.devotee_id = auth.uid()
  order by bookings.on_date desc nulls first, bookings.created_at desc
$$;

revoke all on function public.list_my_sponsorships() from public, anon;
grant execute on function public.list_my_sponsorships() to authenticated;

drop function if exists public.list_all_sponsorships();

create or replace function public.list_all_sponsorships()
returns table (
  id uuid,
  sponsorship_type_id uuid,
  type_name text,
  amount_cents integer,
  on_date date,
  requires_date boolean,
  status text,
  held_until timestamptz,
  fulfilled_on date,
  fulfilment_note text,
  created_at timestamptz,
  devotee_id uuid,
  devotee_name text,
  devotee_email text,
  donation_id uuid
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    bookings.id,
    bookings.sponsorship_type_id,
    types.name,
    bookings.amount_cents,
    bookings.on_date,
    types.requires_date,
    bookings.status,
    bookings.held_until,
    bookings.fulfilled_on,
    bookings.fulfilment_note,
    bookings.created_at,
    bookings.devotee_id,
    devotee.name,
    devotee.email,
    gift.id
  from public.sponsorship_bookings bookings
  join public.sponsorship_types types on types.id = bookings.sponsorship_type_id
  left join public.users devotee on devotee.id = bookings.devotee_id
  left join public.donations gift on gift.sponsorship_booking_id = bookings.id
  where auth.uid() is not null
    and public.may_view_all_giving()
  order by bookings.on_date desc nulls first, bookings.created_at desc
$$;

revoke all on function public.list_all_sponsorships() from public, anon;
grant execute on function public.list_all_sponsorships() to authenticated;

-- ---------------------------------------------------------------------------
-- 14. The notification kinds.
--
--     Restated whole from 202608040047_access_appointments.sql, the most recent
--     migration to touch this constraint, plus the one added here. The
--     constraint cannot be altered in place, only dropped and recreated, so a
--     migration that restates it from an older copy silently outlaws every kind
--     added since — which has now broken this database five times.
--
--     A kind of its own rather than reusing anything: nothing else in the app
--     means "the thing you gave for has now been given", its payload is a
--     bookingId, and a client switching on kind should not have to open the
--     payload to find out which screen to open.
-- ---------------------------------------------------------------------------

alter table public.app_notifications
  drop constraint if exists app_notifications_kind_check;

alter table public.app_notifications
  add constraint app_notifications_kind_check check (
    kind in (
      'service_open', 'service_offer', 'service_recurring_offer',
      'service_offer_response', 'service_joined', 'service_left',
      'service_started', 'service_completed', 'service_cancelled',
      'service_deleted', 'service_coverage_needed',
      'service_coverage_resolved', 'recurring_interest_submitted',
      'recurring_interest_reviewed',
      'seva_verification_requested', 'seva_verification_reviewed',
      'weekly_offer_countered', 'weekly_offer_counter_reviewed',
      'access_request_submitted', 'access_request_reviewed',
      'devotee_joined', 'profile_incomplete',
      'sanga_created', 'sanga_reviewed',
      'sanga_join_requested', 'sanga_join_reviewed',
      'sanga_member_added', 'sanga_member_removed', 'sanga_member_left',
      'sanga_admin_transferred', 'sanga_deleted',
      'announcement_posted',
      'feedback_reviewed',
      'care_reply',
      'birthday_today',
      'newsletter_posted',
      'newsletter_reviewed',
      'access_appointed',
      'access_revoked',
      'sponsorship_fulfilled',
      'remote'
    )
  );

do $$
begin
  raise notice 'sponsorship campaigns applied';
end;
$$;
