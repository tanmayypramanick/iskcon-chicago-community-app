-- Reconciling Zeffy's money with the temple's calendar.
--
-- 202608040048_donations.sql built the calendar and the ledger and left one
-- thing unanswered: how a payment finds the booking it paid for.
--
-- The shape of the problem
-- -----------------------
-- Zeffy charges the temple nothing, which is why it was chosen, and in exchange
-- it gives almost nothing back. Its API is read-only. Its webhook carries no
-- signature. Its `utm_*` passthrough works on donation forms and not on
-- ticketing campaigns, and its custom questions cannot be prefilled. So the
-- temple made a decision — "Option B" — and this file is that decision written
-- down:
--
--     Our app owns the sponsorship calendar and its exclusivity.
--     Zeffy is a fixed-price ticketing page with no dates in it.
--
-- Which means a payment arrives carrying no booking reference at all. There is
-- no id to look up. There is a buyer email, an amount in cents, a campaign, and
-- a moment in time, and the booking must be found from those four things or not
-- at all.
--
-- The rule, in one paragraph
-- -------------------------
-- The app prefills the devotee's address into the Zeffy link (`?email=`), so
-- the payment's buyer email should be theirs. When the money lands we look for
-- the sponsorship holds that devotee had open at that instant — `held`, not yet
-- expired, created inside zeffy_match_window() of the payment — and narrow them
-- to the campaign the payment came from when the campaign is one we know. If
-- exactly one of those holds is priced at exactly what was paid, that is the
-- booking, and it is confirmed. If two are, or if none are, nothing is
-- confirmed: the donation is recorded as `unmatched` and goes into a queue for
-- the President or a Tech Admin to settle by hand with
-- attach_donation_to_booking.
--
-- Never guess. A wrongly confirmed sponsorship takes a date off the calendar
-- for a devotee who did not pay for it and tells one who did that the day is
-- gone. An unmatched donation is a row on a screen that somebody clears in
-- thirty seconds. The two failures are not comparable, so the tie always breaks
-- towards the queue.
--
-- What the temple asked for, in the temple's words
-- -----------------------------------------------
--     "I want the final amount sponsored data in my app from Zeffy, and both
--      should match."
--
-- So: what Zeffy charged is stored always and unaltered, and what the temple
-- expected is stored beside it whenever we can work it out — from the booking
-- when there is one, and from the campaign's sponsorship price when there is
-- not. amount_matches and amount_difference_cents are generated from the pair,
-- so they cannot drift from the numbers they describe. A devotee who paid $500
-- for a $551 sponsorship is neither silently accepted nor silently rejected:
-- the gift is recorded at $500, the expectation is recorded at $551, the
-- difference reads -5100, and the row sits in the queue until a human decides
-- what it means.
--
-- Sunday is Sunday in Chicago
-- ---------------------------
-- A Sunday Feast can only be sponsored on a Sunday. on_date is a temple
-- calendar date and carries no timezone, which is exactly why the check is
-- written against the date itself and never against now(), current_date, or a
-- timestamptz cast — each of those reads the caller's own seat on earth.
-- 202608040040_announcements.sql makes the same argument at length; the
-- verification here proves the answer is identical from UTC-12 to UTC+14.
--
-- Requires 202608040048_donations.sql.

-- ---------------------------------------------------------------------------
-- 1. Which Zeffy page a sponsorship opens, and which day it may be booked on.
--
--    The URL is the whole page as the temple will paste it out of Zeffy's
--    dashboard; the slug is the last path segment of it, kept apart because the
--    webhook has only the slug to identify a campaign by and comparing whole
--    URLs would break the first time Zeffy changes a locale prefix.
--
--    Only Sunday Feast is seeded. The temple has not created the other pages
--    yet, and a made-up URL is worse than no URL: a null means "the app cannot
--    open this yet", while a wrong one means "the app sent a devotee to pay for
--    the wrong thing".
-- ---------------------------------------------------------------------------

alter table public.sponsorship_types
  add column if not exists zeffy_campaign_url text,
  add column if not exists zeffy_campaign_slug text,
  add column if not exists sunday_only boolean not null default false;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'sponsorship_type_zeffy_slug_shape'
  ) then
    alter table public.sponsorship_types
      add constraint sponsorship_type_zeffy_slug_shape check (
        zeffy_campaign_slug is null
        or zeffy_campaign_slug ~ '^[a-z0-9][a-z0-9-]*$'
      );
  end if;
end;
$$;

-- One Zeffy page cannot be two sponsorships: the webhook resolves a payment's
-- campaign to a price through this column, and a duplicate would make that
-- lookup ambiguous in the one place where ambiguity means charging the wrong
-- expectation against real money.
create unique index if not exists sponsorship_types_zeffy_slug_key
  on public.sponsorship_types (zeffy_campaign_slug)
  where zeffy_campaign_slug is not null;

update public.sponsorship_types
set sunday_only = true,
    updated_at = now()
where name in ('Sunday Feast', 'Sunday Feast (higher)')
  and not sunday_only;

-- The one page that exists today. The higher-priced Sunday Feast is a separate
-- fixed-price ticketing campaign the temple has not made, so it stays null.
update public.sponsorship_types
set zeffy_campaign_slug = 'sunday-feast-sponsorship',
    zeffy_campaign_url =
      'https://www.zeffy.com/en-US/ticketing/sunday-feast-sponsorship',
    updated_at = now()
where name = 'Sunday Feast'
  and zeffy_campaign_slug is null;

-- ---------------------------------------------------------------------------
-- 2. Sunday, as the temple means it.
--
--    p_on_date is a date: no time, no offset, no zone. Its weekday is therefore
--    the same fact in every session on earth, and that is the property this
--    function exists to preserve. The mistakes it is written to prevent are
--    `extract(isodow from now())`, which is the caller's Sunday rather than
--    Chicago's, and `extract(isodow from p_on_date::timestamptz)`, which casts
--    through the session timezone and can slide a date onto the day before.
--
--    IMMUTABLE, so it may be used in an index predicate later and so the
--    planner does not re-evaluate it per row of the calendar.
-- ---------------------------------------------------------------------------

create or replace function public.is_sunday_in_chicago(p_on_date date)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p_on_date is not null and extract(isodow from p_on_date) = 7
$$;

comment on function public.is_sunday_in_chicago(date) is
  'True when a temple calendar date is a Sunday. Independent of the session timezone by construction.';

revoke all on function public.is_sunday_in_chicago(date) from public, anon;
grant execute on function public.is_sunday_in_chicago(date) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. How far back a payment may reach for a hold.
--
--    A hold lives thirty minutes. The window is longer than that on purpose: a
--    devotee can hold a date, take the link to a laptop, and pay from there,
--    and Zeffy's own timestamp is not this database's clock. Two hours is long
--    enough to survive that and short enough that last week's abandoned hold is
--    never a candidate for this morning's payment.
--
--    A function rather than a literal so the number is stated once, can be
--    asserted by the verification script, and can be changed without hunting
--    through query text.
-- ---------------------------------------------------------------------------

create or replace function public.zeffy_match_window()
returns interval
language sql
immutable
set search_path = ''
as $$
  select interval '2 hours'
$$;

comment on function public.zeffy_match_window() is
  'How far before a payment a sponsorship hold may have been created and still be considered its match.';

revoke all on function public.zeffy_match_window() from public, anon, authenticated;
grant execute on function public.zeffy_match_window() to service_role;

-- ---------------------------------------------------------------------------
-- 4. What a donation now remembers about how it was reconciled.
--
--    match_status is the whole state of the reconciliation in one word:
--
--      general     no sponsorship campaign was involved. A plain gift. Not a
--                  failure, and never in the queue.
--      matched     the rule above found exactly one hold and confirmed it.
--      manual      a President or Tech Admin attached it by hand.
--      unmatched   the rule declined to decide. Somebody must.
--
--    unmatched_reason says which way it declined, because "we could not tell"
--    and "she paid the wrong amount" need different things done about them:
--
--      no_candidate       nobody was holding a date for that email at that
--                         moment. Often a devotee who found the Zeffy link
--                         directly and never touched our calendar.
--      several_candidates more than one hold fits. Guessing here takes a date
--                         from one devotee and gives it to another.
--      amount_mismatch    exactly one hold was open and the amount is not its
--                         price. This is the $500-for-a-$551-sponsorship case,
--                         and expected_amount_cents is filled in from that lone
--                         hold so the difference is legible on the screen. It
--                         is a suggestion for a human, never a conclusion: the
--                         booking is not attached and nothing is confirmed.
--      booking_lost_date  the hold was found, but by the time the money landed
--                         the date had gone to somebody else and the unique
--                         index refused the confirmation. The money is still
--                         recorded and still linked; the sponsorship is not.
--
--    expected_amount_cents is what the temple thought this gift would be — the
--    booking's own price when there is a booking, and the campaign's
--    sponsorship price when there is not. amount_cents stays exactly what Zeffy
--    charged, always, whatever it is.
--
--    amount_matches and amount_difference_cents are GENERATED. The temple's
--    requirement is that the two numbers agree, and a stored boolean somebody
--    forgets to recompute is a report that says they agree when they do not.
--    Both are null when there is nothing to compare against, which is honest:
--    an unknown expectation is not a match and is not a mismatch.
-- ---------------------------------------------------------------------------

alter table public.donations
  add column if not exists match_status text not null default 'general',
  add column if not exists unmatched_reason text,
  add column if not exists zeffy_campaign_slug text,
  add column if not exists expected_sponsorship_type_id uuid
    references public.sponsorship_types(id) on delete set null,
  add column if not exists expected_amount_cents integer,
  add column if not exists matched_at timestamptz,
  add column if not exists matched_by uuid references public.users(id) on delete set null;

alter table public.donations
  add column if not exists amount_matches boolean
    generated always as (
      case
        when expected_amount_cents is null then null
        else amount_cents = expected_amount_cents
      end
    ) stored,
  add column if not exists amount_difference_cents integer
    generated always as (
      case
        when expected_amount_cents is null then null
        else amount_cents - expected_amount_cents
      end
    ) stored;

-- Rows already recorded by 202608040048 predate reconciliation, and they are
-- brought into the new vocabulary before the constraints that describe it are
-- added — otherwise a donation that named a booking would be a `general` gift
-- holding a booking, and the constraint below would refuse to be created.
update public.donations
set match_status = 'matched'
where sponsorship_booking_id is not null
  and match_status = 'general';

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'donation_match_status_known'
  ) then
    alter table public.donations
      add constraint donation_match_status_known check (
        match_status in ('general', 'matched', 'manual', 'unmatched')
      );
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'donation_unmatched_reason_known'
  ) then
    alter table public.donations
      add constraint donation_unmatched_reason_known check (
        unmatched_reason is null
        or unmatched_reason in (
          'no_candidate', 'several_candidates', 'amount_mismatch', 'booking_lost_date'
        )
      );
  end if;

  -- A reason belongs to an unmatched donation and to nothing else. Without
  -- this, a settled donation could keep a stale reason and haunt the queue.
  if not exists (
    select 1 from pg_constraint where conname = 'donation_reason_matches_status'
  ) then
    alter table public.donations
      add constraint donation_reason_matches_status check (
        (match_status = 'unmatched') = (unmatched_reason is not null)
      );
  end if;

  -- A settled donation names its booking, and a plain gift names none. The
  -- middle case — unmatched, but linked — exists for booking_lost_date alone,
  -- where throwing the link away would lose the only trace of what the money
  -- was for.
  if not exists (
    select 1 from pg_constraint where conname = 'donation_settled_has_booking'
  ) then
    alter table public.donations
      add constraint donation_settled_has_booking check (
        match_status not in ('matched', 'manual')
        or sponsorship_booking_id is not null
      );
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'donation_general_has_no_booking'
  ) then
    alter table public.donations
      add constraint donation_general_has_no_booking check (
        match_status <> 'general' or sponsorship_booking_id is null
      );
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'donation_expected_amount_positive'
  ) then
    alter table public.donations
      add constraint donation_expected_amount_positive check (
        expected_amount_cents is null or expected_amount_cents > 0
      );
  end if;
end;
$$;

-- The queue is the only hot read here and it is always small.
create index if not exists donations_unmatched_idx
  on public.donations (received_at desc)
  where match_status = 'unmatched';

create index if not exists donations_amount_mismatch_idx
  on public.donations (received_at desc)
  where amount_matches = false;

-- ---------------------------------------------------------------------------
-- 5. Column grants for what was just added.
--
--    A devotee may see the state of her own gift — whether the temple has it
--    tied to the sponsorship she booked, and whether the amount agrees. She
--    still cannot see payload, and she still cannot see anybody else's row:
--    the policies from 202608040048 are untouched and are what decides that.
-- ---------------------------------------------------------------------------

grant select (zeffy_campaign_url, zeffy_campaign_slug, sunday_only)
  on public.sponsorship_types to authenticated;

grant select (
  match_status, unmatched_reason, zeffy_campaign_slug,
  expected_sponsorship_type_id, expected_amount_cents,
  amount_matches, amount_difference_cents, matched_at, matched_by
) on public.donations to authenticated;

-- ---------------------------------------------------------------------------
-- 6. The sponsorship list, now carrying its Zeffy page.
--
--    Dropped and recreated rather than replaced because the returned row is
--    wider, and CREATE OR REPLACE cannot widen a return type. The app needs
--    zeffy_campaign_url to know where to send a devotee, and sunday_only to
--    stop offering a Sunday Feast on a Thursday before the tap is refused.
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
-- 7. Saving a sponsorship type, now including where it is paid for.
--
--    Same shape as 202608040048's: one function for adding and editing, a null
--    p_id adds. The new arguments default to null and, on an edit, null means
--    "leave it alone" rather than "clear it" — a President changing a price
--    through a form that does not know about Zeffy yet must not silently wipe
--    the URL that makes the sponsorship payable.
--
--    Clearing is still possible: pass the empty string.
--
--    The five-argument form from 202608040048 is dropped rather than kept
--    beside this one. Both would have defaults for everything past the second
--    argument, so `save_sponsorship_type('Garland', 35100)` would match both and
--    Postgres would refuse the call as ambiguous. Dropping loses nothing: a
--    client build already in a devotee's pocket sends the same argument names
--    and lands here, with the new arguments defaulted.
-- ---------------------------------------------------------------------------

drop function if exists public.save_sponsorship_type(text, integer, uuid, boolean, integer);

create or replace function public.save_sponsorship_type(
  p_name text,
  p_amount_cents integer,
  p_id uuid default null,
  p_is_active boolean default true,
  p_display_order integer default null,
  p_sunday_only boolean default null,
  p_zeffy_campaign_url text default null,
  p_zeffy_campaign_slug text default null
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
      sunday_only, zeffy_campaign_url, zeffy_campaign_slug
    )
    values (
      v_clean_name, p_amount_cents, coalesce(p_is_active, true), v_order,
      coalesce(p_sunday_only, false), v_url, v_slug
    )
    returning * into v_saved;
  else
    update public.sponsorship_types
    set name = v_clean_name,
        amount_cents = p_amount_cents,
        is_active = coalesce(p_is_active, true),
        display_order = v_order,
        sunday_only = coalesce(p_sunday_only, sponsorship_types.sunday_only),
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
  text, integer, uuid, boolean, integer, boolean, text, text
) from public, anon;
grant execute on function public.save_sponsorship_type(
  text, integer, uuid, boolean, integer, boolean, text, text
) to authenticated;

-- ---------------------------------------------------------------------------
-- 8. Holding a date, with Sunday enforced.
--
--    Identical to 202608040048's in every other respect — the refusals stay in
--    the order a devotee meets them, the expired hold on this exact type and
--    date is still swept first, and the INSERT is still what really decides who
--    got the day. The Sunday test sits with the other refusals about the date
--    itself, immediately after the past-date check, because "that day has gone"
--    and "that seva is not offered that day" are the same kind of answer.
-- ---------------------------------------------------------------------------

create or replace function public.hold_sponsorship(
  p_type_id uuid,
  p_on_date date
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

  if p_on_date is null then
    raise exception 'Please choose a date to sponsor.';
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
    -- case the partial unique index exists for.
    raise exception '% on % has already been sponsored. Please choose another date.',
      v_type.name, to_char(p_on_date, 'FMDay FMDD FMMonth YYYY');
  end;

  return v_booking;
end;
$$;

revoke all on function public.hold_sponsorship(uuid, date) from public, anon;
grant execute on function public.hold_sponsorship(uuid, date) to authenticated;

-- ---------------------------------------------------------------------------
-- 9. The calendar stops offering days a hold would refuse.
--
--    Unchanged from 202608040048 but for one clause. A Sunday Feast row on a
--    Wednesday is a tap that always fails, and the calendar knowing the rule is
--    cheaper than every screen learning it. Signature and columns are identical
--    so nothing that reads this has to change.
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
-- 10. Recording a gift, and finding what it paid for.
--
--     The signature is exactly 202608040048's and must stay that way: it is
--     what the webhook calls, what the grants name, and what that migration's
--     verification asserts by regprocedure. Everything new arrives through
--     p_payload, which the webhook writes as
--
--         {"source":"zeffy","campaign_slug":"...","payment":{...verbatim...}}
--
--     so the campaign is discoverable without widening the argument list. The
--     verbatim Zeffy object is still in there, under `payment`, and the older
--     shapes are still read, so a payload written by an earlier deploy is not
--     misread as a general donation.
--
--     Order of decision, once the money is known to be real:
--
--       1. A booking named outright by the caller wins. The app knows something
--          we do not, and asking a matching rule to second-guess it would be
--          the same guess this file exists to refuse.
--       2. Otherwise, look for open holds by this donor at this instant, inside
--          the window, on this campaign's sponsorship if the campaign is known.
--       3. Exactly one priced at exactly what was paid — confirm it.
--       4. Otherwise the queue, with a reason.
--
--     Idempotency is unchanged and is still the constraint's doing, not this
--     function's: ON CONFLICT DO NOTHING, and the loser of a simultaneous
--     retry reads back the winner's row and confirms nothing a second time.
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
    select * into v_campaign
    from public.sponsorship_types
    where lower(sponsorship_types.zeffy_campaign_slug) = v_slug
    limit 1;
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
    -- campaign's sponsorship when we recognise the campaign.
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
          and (v_campaign.id is null or bookings.sponsorship_type_id = v_campaign.id)
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
      -- price is the campaign's, so the amount can still be checked.
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
-- 11. The queue.
--
--     Everything the rule declined to decide, newest first, with enough beside
--     it that the President can decide in one glance rather than opening
--     Zeffy's dashboard in another tab.
--
--     The candidate columns are recomputed on every read rather than stored,
--     because holds expire: a suggestion frozen at webhook time would still be
--     pointing at a date that has since gone to somebody else. They are wider
--     than the matching rule on purpose — any status but cancelled, any amount,
--     a day either side — because a human can weigh a near miss and the rule
--     cannot. candidate_count says how much weighing there is to do.
--
--     Empty for everybody who is not the President or a Tech Admin, in the same
--     way and for the same reason as list_all_donations: a screen that shows
--     nothing cannot be probed by watching which calls error.
-- ---------------------------------------------------------------------------

create or replace function public.list_unmatched_donations()
returns table (
  donation_id uuid,
  external_payment_id text,
  received_at timestamptz,
  donor_id uuid,
  donor_name text,
  donor_email text,
  amount_cents integer,
  currency text,
  expected_amount_cents integer,
  amount_difference_cents integer,
  amount_matches boolean,
  unmatched_reason text,
  zeffy_campaign_slug text,
  expected_type_name text,
  linked_booking_id uuid,
  candidate_count integer,
  candidate_booking_id uuid,
  candidate_type_name text,
  candidate_on_date date,
  candidate_amount_cents integer,
  candidate_status text
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    donations.id,
    donations.external_payment_id,
    donations.received_at,
    donations.donor_id,
    coalesce(donations.donor_name, donor.name),
    coalesce(donations.donor_email, donor.email),
    donations.amount_cents,
    donations.currency,
    donations.expected_amount_cents,
    donations.amount_difference_cents,
    donations.amount_matches,
    donations.unmatched_reason,
    donations.zeffy_campaign_slug,
    expected_type.name,
    donations.sponsorship_booking_id,
    coalesce(candidates.candidate_count, 0)::integer,
    candidates.booking_id,
    candidates.type_name,
    candidates.on_date,
    candidates.amount_cents,
    candidates.status
  from public.donations
  left join public.users donor on donor.id = donations.donor_id
  left join public.sponsorship_types expected_type
    on expected_type.id = donations.expected_sponsorship_type_id
  left join lateral (
    select
      (count(*) over ())::integer as candidate_count,
      bookings.id as booking_id,
      types.name as type_name,
      bookings.on_date,
      bookings.amount_cents,
      bookings.status
    from public.sponsorship_bookings bookings
    join public.sponsorship_types types on types.id = bookings.sponsorship_type_id
    left join public.users devotee on devotee.id = bookings.devotee_id
    where bookings.status <> 'cancelled'
      and bookings.created_at >= donations.received_at - interval '1 day'
      and bookings.created_at <= donations.received_at + interval '1 day'
      and (
        (donations.donor_id is not null and bookings.devotee_id = donations.donor_id)
        or (
          donations.donor_email is not null
          and lower(devotee.email) = lower(donations.donor_email)
        )
      )
      and not exists (
        select 1 from public.donations settled
        where settled.sponsorship_booking_id = bookings.id
          and settled.match_status in ('matched', 'manual')
      )
    -- Closest in price first, then oldest. The best guess for a human to
    -- confirm, never applied by anything but a human.
    order by abs(bookings.amount_cents - donations.amount_cents), bookings.created_at
    limit 1
  ) candidates on true
  where auth.uid() is not null
    and public.may_view_all_giving()
    and donations.match_status = 'unmatched'
  order by donations.received_at desc, donations.id
$$;

comment on function public.list_unmatched_donations() is
  'Donations the matching rule declined to decide, with a suggested booking for a human to confirm.';

revoke all on function public.list_unmatched_donations() from public, anon;
grant execute on function public.list_unmatched_donations() to authenticated;

-- ---------------------------------------------------------------------------
-- 12. Settling one by hand.
--
--     The President or a Tech Admin, and nobody else. A devotee who could call
--     this could point any unmatched money at any booking on the calendar and
--     confirm a sponsorship they never paid for, which is the same forgery
--     record_donation is locked away from — reached by a different door.
--
--     It refuses rather than repoints. A donation already tied to a sponsorship
--     is history, and history that can be rewritten by one call is not a record
--     the temple can rely on when a devotee disputes a gift a year from now.
--
--     It refuses rather than half-succeeds. If the date has since gone to
--     somebody else, the unique index says no and the whole call is rolled back
--     with a sentence saying what to do about it, instead of leaving money
--     attached to a booking that is not confirmed and never will be.
--
--     The amount is not required to agree, and that is the point: the whole
--     reason a $500 payment for a $551 sponsorship reaches this function is
--     that it did not agree. Attaching records the expectation beside what was
--     paid, so amount_matches turns false and the difference is on the screen.
-- ---------------------------------------------------------------------------

create or replace function public.attach_donation_to_booking(
  p_donation_id uuid,
  p_booking_id uuid
)
returns public.donations
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_donation public.donations;
  v_booking public.sponsorship_bookings;
  v_type public.sponsorship_types;
begin
  if auth.uid() is null then
    raise exception 'Sign in to settle a donation.';
  end if;

  if not public.may_view_all_giving() then
    raise exception 'Only the President or a Tech Admin can attach a donation to a sponsorship.';
  end if;

  select * into v_donation
  from public.donations
  where donations.id = p_donation_id
  for update;

  if v_donation.id is null then
    raise exception 'That donation could not be found.';
  end if;

  if v_donation.sponsorship_booking_id is not null then
    raise exception 'That donation is already attached to a sponsorship.';
  end if;

  select * into v_booking
  from public.sponsorship_bookings
  where sponsorship_bookings.id = p_booking_id
  for update;

  if v_booking.id is null then
    raise exception 'That sponsorship booking could not be found.';
  end if;

  if v_booking.status = 'cancelled' then
    raise exception 'That sponsorship was cancelled. Book the date again before attaching the gift.';
  end if;

  select * into v_type
  from public.sponsorship_types
  where sponsorship_types.id = v_booking.sponsorship_type_id;

  if v_booking.status <> 'confirmed' then
    begin
      update public.sponsorship_bookings
      set status = 'confirmed', held_until = null, updated_at = now()
      where sponsorship_bookings.id = v_booking.id;
    exception when unique_violation then
      raise exception '% on % is already sponsored by somebody else. Release that booking first.',
        coalesce(v_type.name, 'That sponsorship'),
        to_char(v_booking.on_date, 'FMDay FMDD FMMonth YYYY');
    end;
  end if;

  update public.donations
  set sponsorship_booking_id = v_booking.id,
      donor_id = coalesce(donations.donor_id, v_booking.devotee_id),
      match_status = 'manual',
      unmatched_reason = null,
      expected_amount_cents = v_booking.amount_cents,
      expected_sponsorship_type_id = v_booking.sponsorship_type_id,
      matched_at = now(),
      matched_by = auth.uid()
  where donations.id = v_donation.id
  returning * into v_donation;

  return v_donation;
end;
$$;

comment on function public.attach_donation_to_booking(uuid, uuid) is
  'Ties an unmatched donation to the sponsorship it paid for, and confirms that booking. President and Tech Admin only.';

revoke all on function public.attach_donation_to_booking(uuid, uuid) from public, anon;
grant execute on function public.attach_donation_to_booking(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 13. Every gift, now with its reconciliation.
--
--     Same window, same permission, same order as 202608040048's. The added
--     columns are what the President needs to answer "does Zeffy's total agree
--     with ours" without leaving the screen.
-- ---------------------------------------------------------------------------

drop function if exists public.list_all_donations(date, date);

create or replace function public.list_all_donations(
  p_from date default null,
  p_to date default null
)
returns table (
  id uuid,
  donor_id uuid,
  donor_name text,
  donor_email text,
  amount_cents integer,
  currency text,
  kind text,
  recurrence text,
  external_payment_id text,
  received_at timestamptz,
  sponsorship_booking_id uuid,
  sponsorship_type_name text,
  sponsorship_on_date date,
  match_status text,
  unmatched_reason text,
  expected_amount_cents integer,
  amount_difference_cents integer,
  amount_matches boolean,
  zeffy_campaign_slug text
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    donations.id,
    donations.donor_id,
    coalesce(donations.donor_name, donor.name),
    coalesce(donations.donor_email, donor.email),
    donations.amount_cents,
    donations.currency,
    donations.kind,
    donations.recurrence,
    donations.external_payment_id,
    donations.received_at,
    donations.sponsorship_booking_id,
    types.name,
    bookings.on_date,
    donations.match_status,
    donations.unmatched_reason,
    donations.expected_amount_cents,
    donations.amount_difference_cents,
    donations.amount_matches,
    donations.zeffy_campaign_slug
  from public.donations
  left join public.users donor on donor.id = donations.donor_id
  left join public.sponsorship_bookings bookings
    on bookings.id = donations.sponsorship_booking_id
  left join public.sponsorship_types types
    on types.id = bookings.sponsorship_type_id
  where auth.uid() is not null
    and public.may_view_all_giving()
    and (
      p_from is null
      or (donations.received_at at time zone 'America/Chicago')::date >= p_from
    )
    and (
      p_to is null
      or (donations.received_at at time zone 'America/Chicago')::date <= p_to
    )
  order by donations.received_at desc, donations.id
$$;

revoke all on function public.list_all_donations(date, date) from public, anon;
grant execute on function public.list_all_donations(date, date) to authenticated;

-- ---------------------------------------------------------------------------
-- 14. A devotee's own giving, with the state of it.
--
--     "Did my donation go through" is the question this screen answers, and
--     until now it could only say yes. It can now say "yes, and the temple is
--     still tying it to the Sunday you booked", which is the truthful answer
--     when a payment lands in the queue.
-- ---------------------------------------------------------------------------

drop function if exists public.list_my_donations();

create or replace function public.list_my_donations()
returns table (
  id uuid,
  amount_cents integer,
  currency text,
  kind text,
  recurrence text,
  external_payment_id text,
  received_at timestamptz,
  sponsorship_booking_id uuid,
  sponsorship_type_name text,
  sponsorship_on_date date,
  match_status text,
  expected_amount_cents integer,
  amount_matches boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    donations.id,
    donations.amount_cents,
    donations.currency,
    donations.kind,
    donations.recurrence,
    donations.external_payment_id,
    donations.received_at,
    donations.sponsorship_booking_id,
    types.name,
    bookings.on_date,
    donations.match_status,
    donations.expected_amount_cents,
    donations.amount_matches
  from public.donations
  left join public.sponsorship_bookings bookings
    on bookings.id = donations.sponsorship_booking_id
  left join public.sponsorship_types types
    on types.id = bookings.sponsorship_type_id
  where auth.uid() is not null
    and donations.donor_id = auth.uid()
  order by donations.received_at desc, donations.id
$$;

revoke all on function public.list_my_donations() from public, anon;
grant execute on function public.list_my_donations() to authenticated;

do $$
begin
  raise notice 'donation reconciliation applied';
end;
$$;
