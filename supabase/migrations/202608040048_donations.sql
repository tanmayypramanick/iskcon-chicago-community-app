-- Donations and sponsorships: the temple's giving, recorded here.
--
-- The money itself never touches this database. A devotee taps "sponsor the
-- Sunday Feast", the app opens Zeffy's hosted form in the browser, and Zeffy
-- takes the card. Zeffy charges the temple nothing, which is the whole reason
-- it was chosen, and in exchange the temple gets no database of its own out of
-- it — Zeffy's dashboard knows who paid, and knows nothing about which deity
-- dress was sponsored on which day or which of those donors is the devotee who
-- has been coming to mangal aarti for eleven years.
--
-- So: payment there, records here. Zeffy's webhook calls record_donation with
-- the service role once the card clears, and from that moment the gift is the
-- temple's own record. A devotee can see everything they have ever given. The
-- President and the Tech Admin can see everything anybody has given. Nobody
-- else can see anything they did not give themselves.
--
-- The one thing this file is really about
-- ---------------------------------------
-- A sponsorship is a named thing on a named day: the garland on Radhashtami,
-- the deity dress on Janmashtami. There is one garland. If two devotees open
-- the calendar three seconds apart and both tap the 15th, exactly one of them
-- must get it, and the other must be told plainly that it has gone — before
-- either of them has been asked for a card.
--
-- That is not a thing application code can promise. Two Postgres connections
-- reading "is the 15th free?" at the same instant both see yes, and both
-- insert. The only thing that can promise it is the database refusing the
-- second row, so the promise is made by a partial unique index over the states
-- that hold a date: `held` and `confirmed`. Everything else in this file —
-- the hold, the expiry, the release — is arranged around that index rather
-- than the index being arranged around them. If the RPC is bypassed entirely
-- and a row is inserted straight into the table, the second one still fails.
--
-- Why holds expire
-- ----------------
-- The hold exists because paying happens somewhere else. hold_sponsorship
-- reserves the date, the devotee leaves for Zeffy, and either the webhook
-- comes back and confirms it or the devotee closes the tab on the payment
-- screen and never returns. Without an expiry the second case would take the
-- 15th off the calendar forever, so a hold carries held_until and
-- release_expired_sponsorship_holds() frees the abandoned ones, scheduled the
-- way the other maintenance functions in this repo are scheduled.
--
-- Money is cents
-- --------------
-- Every amount in this file is an integer number of cents. $151.00 is 15100.
-- Nothing here is ever a float, a numeric, or a dollar string: the sponsorship
-- prices are fixed, the arithmetic on them is exact, and the one way to
-- guarantee that stays true is to never introduce a type that can round.
--
-- Dates are Chicago's
-- -------------------
-- on_date is a temple calendar date. "Today" is evaluated as
-- `(now() at time zone 'America/Chicago')::date`, never in UTC and never in
-- the caller's own timezone — at 8pm on the 14th in Chicago, UTC has already
-- turned over to the 15th, and a past-date check written against UTC would
-- refuse a devotee sponsoring tomorrow. 202608040040_announcements.sql makes
-- the same point at length.
--
-- Requires 202608040047_access_appointments.sql.

-- ---------------------------------------------------------------------------
-- 1. What can be sponsored.
--
--    Seeded from the list the temple actually uses, but a table rather than a
--    CHECK constraint or a hardcoded array, because the prices are the
--    temple's to change and the list is the temple's to grow. A new
--    sponsorship should be a President tapping a form, not a migration.
--
--    is_active rather than DELETE: last year's Deity Dress sponsorships must
--    keep pointing at a row that still says what they were and what they cost,
--    so a type that is no longer offered is switched off, never removed. The
--    foreign key from bookings is ON DELETE RESTRICT to make that structural.
--
--    display_order because the list has a natural order — cheapest daily seva
--    first, deity dress last — that is neither alphabetical nor by price, and
--    the calendar screen should not have to know it.
-- ---------------------------------------------------------------------------

create table if not exists public.sponsorship_types (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  -- Integer cents. See the header: never a float, never numeric.
  amount_cents integer not null,
  is_active boolean not null default true,
  display_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint sponsorship_type_name_not_blank check (nullif(trim(name), '') is not null),
  constraint sponsorship_type_amount_positive check (amount_cents > 0)
);

create index if not exists sponsorship_types_order_idx
  on public.sponsorship_types (display_order, name);

-- The temple's current list. ON CONFLICT DO NOTHING rather than DO UPDATE:
-- re-running the migration must not undo a price the President has since
-- changed through the app. These are seeds, not settings.
insert into public.sponsorship_types (name, amount_cents, display_order)
values
  ('Mangal Aarti',            10800, 10),
  ('Breakfast',               12500, 20),
  ('Sandhya Bhog',            15100, 30),
  ('Rajbhog',                 20100, 40),
  ('Garland',                 35100, 50),
  ('Sunday Feast',            55100, 60),
  ('Sunday Feast (higher)',   75100, 70),
  ('Deity Dress',            250000, 80)
on conflict (name) do nothing;

-- ---------------------------------------------------------------------------
-- 2. A sponsorship booked on a day.
--
--    The four states, and what each one means to the calendar:
--
--      held       somebody is at Zeffy's payment page right now. The date is
--                 off the calendar, but only until held_until passes.
--      confirmed  the webhook came back. The date is theirs.
--      released   abandoned, or expired, or given up voluntarily. The date is
--                 free again.
--      cancelled  the temple or the devotee called it off after confirming.
--                 Kept apart from `released` because a cancelled sponsorship
--                 usually has money attached to it and somebody will have to
--                 answer for that; a released one never does.
--
--    amount_cents is copied from the type at booking time rather than joined
--    at read time. The price on the day is what the devotee agreed to give,
--    and a President raising Rajbhog from $201 to $251 in November must not
--    silently rewrite what September's sponsor is recorded as having promised.
-- ---------------------------------------------------------------------------

create table if not exists public.sponsorship_bookings (
  id uuid primary key default gen_random_uuid(),
  sponsorship_type_id uuid not null
    references public.sponsorship_types(id) on delete restrict,
  devotee_id uuid not null references public.users(id) on delete cascade,
  on_date date not null,
  status text not null default 'held' check (
    status in ('held', 'confirmed', 'released', 'cancelled')
  ),
  -- Only a hold has an expiry, and every hold has one. A hold without a
  -- deadline is the bug this column exists to make impossible.
  held_until timestamptz,
  amount_cents integer not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint sponsorship_booking_amount_positive check (amount_cents > 0),
  constraint sponsorship_booking_hold_expires check (
    status <> 'held' or held_until is not null
  )
);

-- ---------------------------------------------------------------------------
--    THE constraint. Everything else in this file is convenience.
--
--    One garland, one day, one sponsor. The predicate covers exactly the two
--    states that occupy a date; a released or cancelled booking leaves the day
--    open and so falls outside the index, which is why releasing is an UPDATE
--    of status and not a DELETE.
--
--    It cannot mention held_until — an index predicate must be immutable and
--    now() is not — so an expired hold keeps its grip on the index until
--    something releases it. That is what release_expired_sponsorship_holds()
--    is for, and why hold_sponsorship sweeps its own type and date first.
--    sponsorship_availability, which only reads, reports an expired hold as
--    free without waiting for the sweep.
-- ---------------------------------------------------------------------------

create unique index if not exists sponsorship_booking_one_live_per_type_and_date
  on public.sponsorship_bookings (sponsorship_type_id, on_date)
  where status in ('held', 'confirmed');

create index if not exists sponsorship_bookings_devotee_idx
  on public.sponsorship_bookings (devotee_id, on_date desc);

create index if not exists sponsorship_bookings_date_idx
  on public.sponsorship_bookings (on_date, sponsorship_type_id);

-- The sweep looks only at live holds, and there are never many.
create index if not exists sponsorship_bookings_expiry_idx
  on public.sponsorship_bookings (held_until) where status = 'held';

-- ---------------------------------------------------------------------------
-- 3. Every completed gift.
--
--    A row here means money actually arrived. There is no `pending`, no
--    `failed`, no state machine: Zeffy owns the attempt, and this table owns
--    the outcome. A donation that did not complete simply has no row.
--
--    The donor is two things at once, and both are kept:
--
--      donor_id     the app user, when the gift can be tied to one. Nullable,
--                   because a visiting devotee's aunt can give through the
--                   same Zeffy link without ever installing the app, and that
--                   gift is no less the temple's to record.
--      donor_name   what Zeffy reported. Kept even when donor_id is set,
--      donor_email  because it is what the payment processor said and an audit
--                   asks what the processor said, not what the app inferred.
--                   It also survives the user row being deleted.
--
--    payload is the webhook body, verbatim. When a gift is disputed a year
--    from now, the answer is in what Zeffy sent, not in this schema's reading
--    of it. It is never granted to any client role.
--
--    external_payment_id is UNIQUE, and that is not defensive programming — a
--    webhook delivered twice is the normal case, not the exceptional one. Every
--    webhook system on earth retries on a timeout, and half of those timeouts
--    happen after the work was already done. The uniqueness is what makes
--    record_donation idempotent; the function's ON CONFLICT is merely how it
--    responds politely to the constraint doing its job.
-- ---------------------------------------------------------------------------

create table if not exists public.donations (
  id uuid primary key default gen_random_uuid(),
  donor_id uuid references public.users(id) on delete set null,
  donor_name text,
  donor_email text,
  amount_cents integer not null,
  currency text not null default 'USD',
  kind text not null check (kind in ('one_time', 'recurring')),
  recurrence text check (recurrence in ('monthly', 'quarterly', 'yearly')),
  external_payment_id text not null,
  payload jsonb not null default '{}'::jsonb,
  sponsorship_booking_id uuid
    references public.sponsorship_bookings(id) on delete set null,
  received_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint donation_amount_positive check (amount_cents > 0),
  constraint donation_currency_shape check (currency ~ '^[A-Z]{3}$'),
  -- A recurring gift says how often; a one-off must not.
  constraint donation_recurrence_matches_kind check (
    (kind = 'recurring') = (recurrence is not null)
  ),
  constraint donation_external_payment_id_not_blank check (
    nullif(trim(external_payment_id), '') is not null
  ),
  constraint donation_external_payment_id_unique unique (external_payment_id)
);

create index if not exists donations_donor_received_idx
  on public.donations (donor_id, received_at desc);

create index if not exists donations_received_idx
  on public.donations (received_at desc);

create index if not exists donations_booking_idx
  on public.donations (sponsorship_booking_id)
  where sponsorship_booking_id is not null;

-- ---------------------------------------------------------------------------
-- 4. Who may see everything.
--
--    The President and the Tech Admin, identified by app.view_all, exactly as
--    every other whole-congregation read in this codebase identifies them. No
--    new permission key: a `donations.view_all` would have to be granted to
--    those two roles and to nobody else, which is precisely the set app.view_all
--    already describes, and a second key is a second thing to forget to grant
--    when the temple appoints a new President.
-- ---------------------------------------------------------------------------

create or replace function public.may_view_all_giving()
returns boolean
language sql
stable
set search_path = ''
as $$
  select public.has_permission('app.view_all')
$$;

comment on function public.may_view_all_giving() is
  'True for the President and Tech Admin, who may see every donation and sponsorship.';

revoke all on function public.may_view_all_giving() from public, anon;
grant execute on function public.may_view_all_giving() to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Who may call record_donation.
--
--    Zeffy's webhook handler, holding the service role key, and nothing else.
--    A devotee who could call it could write themselves a $10,000 donation
--    receipt and confirm any sponsorship on the calendar without paying.
--
--    The grant alone should be enough — the function is granted to service_role
--    and to nobody else — but the guard is written anyway, because a later
--    migration that runs `grant execute on all functions in schema public to
--    authenticated` would silently undo the grant and would not touch this.
--
--    The test is the `role` GUC, which is what PostgREST sets per request and
--    what `set local role` sets in the verification script. It is unaffected by
--    SECURITY DEFINER, unlike current_user. When nothing has set it the caller
--    is connected as its own login role — a migration, a cron job, the
--    webhook's own connection — and `authenticator`, the role PostgREST logs in
--    as before switching, is refused along with anon and authenticated so that
--    a request which somehow arrives without a role switch is refused too.
-- ---------------------------------------------------------------------------

create or replace function public.is_backend_caller()
returns boolean
language sql
stable
set search_path = ''
as $$
  select coalesce(nullif(current_setting('role', true), 'none'), session_user)
         not in ('anon', 'authenticated', 'authenticator')
$$;

comment on function public.is_backend_caller() is
  'True only for a trusted server-side caller (service role, cron, migration) — never for a client request.';

revoke all on function public.is_backend_caller() from public, anon, authenticated;
grant execute on function public.is_backend_caller() to service_role;

-- ---------------------------------------------------------------------------
-- 6. Row level security.
--
--    Reads only. Every write in this feature goes through an RPC below, so no
--    role is granted INSERT, UPDATE or DELETE on any of the three tables and
--    there is no write policy to get wrong.
--
--    The rule for both money tables is the same one sentence: your own, or
--    everything if you are the President or the Tech Admin. A devotee reading
--    public.donations directly through PostgREST gets their own rows and an
--    empty set for everybody else's — the policy is what enforces that, not
--    the list functions, so bypassing the list functions gains nothing.
--
--    donations.payload is granted to nobody. The raw webhook body is for
--    audit from a psql prompt, and it may contain whatever Zeffy chose to put
--    in it.
-- ---------------------------------------------------------------------------

alter table public.sponsorship_types enable row level security;
alter table public.sponsorship_bookings enable row level security;
alter table public.donations enable row level security;

drop policy if exists "Devotees read the sponsorship list" on public.sponsorship_types;
create policy "Devotees read the sponsorship list"
  on public.sponsorship_types for select to authenticated
  using (
    auth.uid() is not null
    and (is_active or public.may_view_all_giving())
  );

drop policy if exists "Devotees read their own sponsorships" on public.sponsorship_bookings;
create policy "Devotees read their own sponsorships"
  on public.sponsorship_bookings for select to authenticated
  using (
    auth.uid() is not null
    and (devotee_id = auth.uid() or public.may_view_all_giving())
  );

drop policy if exists "Devotees read their own donations" on public.donations;
create policy "Devotees read their own donations"
  on public.donations for select to authenticated
  using (
    auth.uid() is not null
    and (donor_id = auth.uid() or public.may_view_all_giving())
  );

revoke all on public.sponsorship_types from anon, authenticated;
revoke all on public.sponsorship_bookings from anon, authenticated;
revoke all on public.donations from anon, authenticated;

grant select (id, name, amount_cents, is_active, display_order, created_at, updated_at)
  on public.sponsorship_types to authenticated;

grant select (
  id, sponsorship_type_id, devotee_id, on_date, status,
  held_until, amount_cents, created_at, updated_at
) on public.sponsorship_bookings to authenticated;

-- payload is deliberately absent.
grant select (
  id, donor_id, donor_name, donor_email, amount_cents, currency,
  kind, recurrence, external_payment_id, sponsorship_booking_id,
  received_at, created_at
) on public.donations to authenticated;

-- ---------------------------------------------------------------------------
-- 7. The list of what can be sponsored.
--
--    Every signed-in devotee sees the active types, because the calendar is
--    built from them. The President and the Tech Admin also see the switched
--    off ones, because otherwise a type they retired would be invisible to the
--    only people who could bring it back.
-- ---------------------------------------------------------------------------

create or replace function public.list_sponsorship_types()
returns table (
  id uuid,
  name text,
  amount_cents integer,
  is_active boolean,
  display_order integer
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
    sponsorship_types.display_order
  from public.sponsorship_types
  where auth.uid() is not null
    and (sponsorship_types.is_active or public.may_view_all_giving())
  order by sponsorship_types.display_order, sponsorship_types.name
$$;

revoke all on function public.list_sponsorship_types() from public, anon;
grant execute on function public.list_sponsorship_types() to authenticated;

-- ---------------------------------------------------------------------------
-- 8. Changing the list.
--
--    One function for both adding and editing, because the form is the same
--    form and a create_/update_ pair would differ only in whether p_id was
--    null. A null p_id adds; a given p_id edits.
--
--    The price is taken in cents and refused if it is not a whole positive
--    number of them. A client that sends 151.00 gets a type error from
--    Postgres before it reaches here, which is the intended outcome.
-- ---------------------------------------------------------------------------

create or replace function public.save_sponsorship_type(
  p_name text,
  p_amount_cents integer,
  p_id uuid default null,
  p_is_active boolean default true,
  p_display_order integer default null
)
returns public.sponsorship_types
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_clean_name text;
  v_order integer;
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

  if p_id is null then
    insert into public.sponsorship_types (name, amount_cents, is_active, display_order)
    values (v_clean_name, p_amount_cents, coalesce(p_is_active, true), v_order)
    returning * into v_saved;
  else
    update public.sponsorship_types
    set name = v_clean_name,
        amount_cents = p_amount_cents,
        is_active = coalesce(p_is_active, true),
        display_order = v_order,
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

revoke all on function public.save_sponsorship_type(text, integer, uuid, boolean, integer)
  from public, anon;
grant execute on function public.save_sponsorship_type(text, integer, uuid, boolean, integer)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 9. The calendar.
--
--    For every active type and every day in the window: is it taken?
--
--    Everyone may ask, because everyone needs the calendar before they can
--    choose a day. That makes this the one function in the feature where the
--    leak would be easy and quiet — the natural implementation joins to users
--    to get the sponsor's name for the President's view and hands the same
--    column to everybody.
--
--    So booked_by_name is decided per row, not per query:
--
--      the President and the Tech Admin       see the sponsor's name
--      the devotee who booked it              see their own name, and is_mine
--      every other devotee                    see NULL, and only is_taken
--
--    booking_id is withheld on the same terms. An ordinary devotee learns one
--    bit about somebody else's booking — that the day is gone — and that bit
--    is the entire purpose of the call.
--
--    is_taken treats an expired hold as free. The index cannot, because index
--    predicates must be immutable, so a hold that ran out two minutes ago is
--    still `held` until the sweep runs. Showing that day as taken would be a
--    lie the devotee could not act on; hold_sponsorship sweeps the row before
--    inserting, so the answer this function gives is the answer they get.
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

  -- A year and a bit. Without a ceiling one call can be asked for a century of
  -- days across eight types and spend the database's afternoon on it.
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
  order by days.on_day, types.display_order, types.name;
end;
$$;

revoke all on function public.sponsorship_availability(date, date) from public, anon;
grant execute on function public.sponsorship_availability(date, date) to authenticated;

-- ---------------------------------------------------------------------------
-- 10. Taking a date.
--
--     Three refusals, in the order a devotee would meet them: a type that is
--     not on offer, a day that has already gone, and a day somebody else has.
--
--     The last one is answered twice, and the second answer is the real one.
--     The SELECT that looks for an existing live booking is there so the
--     common case gets a sentence a human wrote. The INSERT is what actually
--     decides, because between that SELECT and that INSERT another connection
--     can commit — which is exactly the three-seconds-apart case this feature
--     exists to survive. unique_violation is caught and turned into the same
--     sentence, so the two devotees get identical, truthful messages and only
--     one row exists.
--
--     Before either, the row's own expired hold is swept. Targeted at this
--     type and this date rather than calling the global sweep, so one devotee
--     booking the 15th never takes locks on anybody else's booking.
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
-- 11. Giving a held date back.
--
--     The devotee closed the Zeffy tab and came back to the app. Their own
--     hold, and only while it is still a hold: a confirmed sponsorship has
--     money against it and is not theirs to make disappear.
-- ---------------------------------------------------------------------------

create or replace function public.release_sponsorship_hold(p_booking_id uuid)
returns public.sponsorship_bookings
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_booking public.sponsorship_bookings;
begin
  if auth.uid() is null then
    raise exception 'Sign in to release a sponsorship.';
  end if;

  select * into v_booking
  from public.sponsorship_bookings
  where sponsorship_bookings.id = p_booking_id
  for update;

  if v_booking.id is null then
    raise exception 'That sponsorship could not be found.';
  end if;

  if v_booking.devotee_id is distinct from auth.uid() then
    raise exception 'You can only release your own sponsorship.';
  end if;

  if v_booking.status <> 'held' then
    raise exception 'That sponsorship is no longer on hold.';
  end if;

  update public.sponsorship_bookings
  set status = 'released', held_until = null, updated_at = now()
  where sponsorship_bookings.id = v_booking.id
  returning * into v_booking;

  return v_booking;
end;
$$;

revoke all on function public.release_sponsorship_hold(uuid) from public, anon;
grant execute on function public.release_sponsorship_hold(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 12. Freeing abandoned holds.
--
--     Shaped like remind_incomplete_profiles and announce_birthdays: no
--     arguments, returns how many rows it touched, granted to nobody, and
--     scheduled with pg_cron only if pg_cron is there. Every five minutes,
--     because a devotee who abandons a payment will often try again straight
--     away and should not have to wait an hour for their own date to come back.
-- ---------------------------------------------------------------------------

create or replace function public.release_expired_sponsorship_holds()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_released integer := 0;
begin
  with expired as (
    update public.sponsorship_bookings
    set status = 'released', held_until = null, updated_at = now()
    where sponsorship_bookings.status = 'held'
      and sponsorship_bookings.held_until <= now()
    returning 1
  )
  select count(*)::integer into v_released from expired;

  return v_released;
end;
$$;

comment on function public.release_expired_sponsorship_holds() is
  'Frees sponsorship holds whose payment window has passed. Returns how many were freed.';

revoke all on function public.release_expired_sponsorship_holds()
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 13. Recording a gift.
--
--     Called by the Zeffy webhook handler with the service role. Never by a
--     devotee — see is_backend_caller above for why that matters.
--
--     Idempotent on external_payment_id, and idempotent by asking the
--     constraint rather than by asking whether a row exists first. ON CONFLICT
--     DO NOTHING means two simultaneous deliveries of the same webhook both
--     reach the INSERT and exactly one wins; the loser finds the winner's row
--     and returns it, so both deliveries get a 200 and the temple is credited
--     once. A "select, then insert if missing" would record it twice under
--     precisely the retry storm that makes retries worth handling.
--
--     When the gift is a sponsorship, its booking is confirmed here, and only
--     here: a hold becomes a sponsorship when the money lands, not when the
--     devotee says it will. If the hold expired and somebody else has since
--     taken the date, the confirmation cannot happen — the unique index says
--     so — and the donation is still recorded, still linked, and left for the
--     temple to sort out with the donor. Losing the record of received money
--     because a calendar slot moved would be the worse of the two failures.
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
  v_donation public.donations;
  v_booking public.sponsorship_bookings;
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

  -- Zeffy knows an email address, not a user id. Matching it to a devotee is
  -- what turns "somebody gave $151" into "this devotee's giving history".
  v_donor := p_donor_id;
  if v_donor is null and v_email is not null then
    select users.id into v_donor
    from public.users
    where lower(users.email) = v_email
    limit 1;
  end if;

  -- If a booking was named, the sponsor is the donor unless the webhook said
  -- otherwise. A devotee who held the date and then paid on their phone is the
  -- same person even when Zeffy has a different email for them.
  if p_sponsorship_booking_id is not null then
    select * into v_booking
    from public.sponsorship_bookings
    where sponsorship_bookings.id = p_sponsorship_booking_id
    for update;

    if v_booking.id is null then
      raise exception 'That sponsorship booking could not be found.';
    end if;

    v_donor := coalesce(v_donor, v_booking.devotee_id);
  end if;

  insert into public.donations (
    donor_id, donor_name, donor_email, amount_cents, currency,
    kind, recurrence, external_payment_id, payload,
    sponsorship_booking_id, received_at
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
    p_sponsorship_booking_id,
    coalesce(p_received_at, now())
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

  if v_booking.id is not null and v_booking.status <> 'confirmed' then
    begin
      update public.sponsorship_bookings
      set status = 'confirmed', held_until = null, updated_at = now()
      where sponsorship_bookings.id = v_booking.id;
    exception when unique_violation then
      -- The hold ran out and the date went to somebody else. The money is
      -- recorded; the sponsorship is not. The temple sees both in
      -- list_all_donations and list_all_sponsorships and can make it right.
      raise warning 'Donation % arrived after booking % lost its date.',
        v_external, v_booking.id;
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
-- 14. A devotee's own giving.
--
--     Newest first, because the question a devotee opens this screen with is
--     "did my donation go through" far more often than "what did I give in
--     2019". The sponsorship it paid for travels with the row so the list can
--     say "Rajbhog, 14 September" instead of a bare amount.
--
--     No donor columns: it is their own history, they know who they are, and
--     leaving the columns out means there is nothing here to leak.
-- ---------------------------------------------------------------------------

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
  sponsorship_on_date date
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
    bookings.on_date
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

-- ---------------------------------------------------------------------------
-- 15. Every gift, for the two who may see them.
--
--     Empty set rather than an exception for everybody else. A report screen
--     that quietly shows nothing to a devotee who should not have it is a
--     screen that cannot be probed by watching which calls error, and the
--     President's client and the devotee's client are the same binary.
--
--     The window is in Chicago dates, matched against Chicago dates: a gift
--     received at 7pm on the 31st belongs to that month's total, and it would
--     not if received_at were compared in UTC.
-- ---------------------------------------------------------------------------

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
  sponsorship_on_date date
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
    bookings.on_date
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
-- 16. Sponsorships, the same two ways.
--
--     Held rows are included in a devotee's own list — the hold is the thing
--     they are looking at while they decide whether to go back and pay.
-- ---------------------------------------------------------------------------

create or replace function public.list_my_sponsorships()
returns table (
  id uuid,
  sponsorship_type_id uuid,
  type_name text,
  amount_cents integer,
  on_date date,
  status text,
  held_until timestamptz,
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
    bookings.status,
    bookings.held_until,
    bookings.created_at,
    gift.id
  from public.sponsorship_bookings bookings
  join public.sponsorship_types types on types.id = bookings.sponsorship_type_id
  left join public.donations gift on gift.sponsorship_booking_id = bookings.id
  where auth.uid() is not null
    and bookings.devotee_id = auth.uid()
  order by bookings.on_date desc, bookings.created_at desc
$$;

revoke all on function public.list_my_sponsorships() from public, anon;
grant execute on function public.list_my_sponsorships() to authenticated;

create or replace function public.list_all_sponsorships()
returns table (
  id uuid,
  sponsorship_type_id uuid,
  type_name text,
  amount_cents integer,
  on_date date,
  status text,
  held_until timestamptz,
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
    bookings.status,
    bookings.held_until,
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
  order by bookings.on_date desc, bookings.created_at desc
$$;

revoke all on function public.list_all_sponsorships() from public, anon;
grant execute on function public.list_all_sponsorships() to authenticated;

-- ---------------------------------------------------------------------------
-- 17. The sweep, scheduled where pg_cron exists.
--
--     Guarded exactly as 202608030009_weekly_seva_visibility_and_coverage.sql
--     guards its own job: the local verification cluster has no pg_cron and
--     must still apply this migration cleanly.
-- ---------------------------------------------------------------------------

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    if exists (select 1 from cron.job where jobname = 'release-expired-sponsorship-holds') then
      perform cron.unschedule('release-expired-sponsorship-holds');
    end if;

    perform cron.schedule(
      'release-expired-sponsorship-holds', '*/5 * * * *',
      'select public.release_expired_sponsorship_holds();'
    );
  end if;
end;
$$;

do $$
begin
  raise notice 'donations applied';
end;
$$;
