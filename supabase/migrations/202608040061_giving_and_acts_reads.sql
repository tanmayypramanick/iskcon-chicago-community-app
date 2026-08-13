-- Three reads the client could not make, and one rule it kept re-inventing.
--
-- Nothing here is a new feature. Every gap below was found while building the
-- screens on top of 0048–0050 and 0055–0059, and every one of them was being
-- worked around on the device — which is to say, worked around three times, in
-- three files, with three different answers.
--
-- ---------------------------------------------------------------------------
-- 1. A lapsed booking is not giving, and the server never said so.
--
--    list_my_sponsorships has returned every row in sponsorship_bookings that
--    belongs to the caller since 0048, whatever its status. A devotee who
--    reserved the Sunday Feast on three separate evenings and paid once
--    therefore saw three $551 cards in her giving history, two of which were
--    dates she gave back.
--
--    The client learned to filter. Three screens learned it separately and did
--    not agree, which is the ordinary fate of a rule that lives anywhere but
--    the place the data comes from. So the filter moves here:
--
--      p_include_lapsed => false  (the default) — only what is live: a hold
--                                 that has not run out, or a confirmed gift.
--      p_include_lapsed => true   — everything, so the President can look at
--                                 the dates that were given back when Zeffy's
--                                 figure and the calendar disagree.
--
--    AND THE EXPIRED HOLD. This is the part no client can get right on its own
--    and the part every client got wrong. The unique index that guards a date
--    (0048 section 3) cannot mention now() — an index predicate must be
--    immutable — so it is written over `status in ('held','confirmed')` and a
--    hold that has run out keeps its row until expire_sponsorship_holds sweeps
--    it. Meanwhile sponsorship_availability, which only reads, has ALWAYS
--    reported that date as free, because it can afford to say
--    `held_until > now()`.
--
--    So there is a window — between the moment a hold expires and the moment a
--    sweep runs — in which the row says `held` and the calendar says the date
--    is anybody's. A devotee reading her own list in that window was being
--    shown a reservation the temple had already given away.
--
--    Both lists now project it:
--
--        case when status = 'held' and held_until <= now()
--             then 'released' else status end
--
--    That is not a cosmetic relabel. It is the same judgement
--    sponsorship_availability has always made, said out loud in the one other
--    place the same row is read, so no client ever has to reason about a stale
--    hold and no two clients can reason about it differently. The projection
--    lives in one function, public.sponsorship_effective_status, so that the
--    devotee's list, the President's list and the donation ledger cannot drift
--    apart by editing one of them.
--
--    held_until is left exactly as it stands. For a projected release it is
--    the moment the hold ran out, which is worth reading; blanking it the way
--    release_sponsorship_hold does would be claiming a sweep happened.
--
-- ---------------------------------------------------------------------------
-- 2. The President could not look at one devotee's seva act by act.
--
--    my_seva_acts (0057 section 7) is hard-scoped to auth.uid(), and the two
--    helpers underneath it — seva_mala_acts(uuid) and seva_balance_acts(uuid) —
--    are revoked from `authenticated` on purpose, because either of them called
--    directly with a null argument returns the whole congregation's history.
--    Between them there was no door at all: a President could see a devotee's
--    per-seva totals and could not see the acts they were made of, so
--    "Tuesday didn't count and I don't know why" could be asked by a devotee
--    and answered by nobody.
--
--    list_devotee_seva_acts opens exactly that door and no wider. Same return
--    shape as my_seva_acts, column for column and in the same order, so the one
--    client component that renders a devotee's own history renders somebody
--    else's without a second row type. app.view_all, and an empty set for
--    everybody else — this backs a screen, and a screen that raises for a
--    Community Head is a screen that tells the Community Head there was
--    something there to be refused.
--
-- ---------------------------------------------------------------------------
-- 3. The donation ledger could not be filtered, counted, or trusted to add up.
--
--    list_all_donations took a window and nothing else. A client wanting one
--    devotee's giving pulled the entire ledger and filtered it on the phone,
--    which is a full table read per screen and gets slower every Sunday. It
--    now takes p_donor_id; null keeps the old behaviour exactly.
--
--    It also now carries booking_status — the PROJECTED status, the same one
--    list_all_sponsorships reports — so a row that paid for a sponsorship says
--    where that sponsorship stands without a second round trip.
--
--    And there was no total anywhere on the server. The President's figure was
--    a sum over whatever rows the client happened to be holding, which is the
--    right answer today and silently the wrong one the day db-max-rows is set,
--    because a truncated page still sums. donation_totals and
--    my_donation_totals compute it in the database.
--
--    GROUPED BY CURRENCY, ALWAYS. Not "grouped by currency when there is more
--    than one". A single scalar total is a number that becomes a lie the first
--    time somebody's card settles in CAD, and it becomes a lie quietly. The
--    function returns one row per currency and there is no argument that
--    collapses them.
--
--    WHAT COUNTS, stated once so no screen has to guess:
--
--        A DONATION ROW MEANS MONEY WAS RECEIVED. EVERY DONATION ROW IN THE
--        WINDOW IS IN THE TOTAL, WHATEVER BECAME OF ANY SPONSORSHIP ATTACHED
--        TO IT.
--
--    Two client screens disagreed about this, and the disagreement is
--    understandable: a booking that was released or cancelled looks like
--    something being undone. It is not. Releasing a booking gives back A DATE.
--    It does not give back the gift, no money moves, and the temple is holding
--    the same dollars afterwards as before. A total that dropped a $551
--    donation because the Sunday it was meant for was later handed to somebody
--    else would not reconcile against Zeffy and should not.
--
--    So donation_totals does not join sponsorship_bookings at all. There is no
--    predicate to get wrong, and a later editor cannot add one by accident —
--    they would have to add the join first, and this paragraph is what they
--    would have to argue with.
--
--    The two lists remain the place to see a booking's standing, which is why
--    booking_status is on list_all_donations: the President can see that a
--    counted gift is attached to a released date, on the same row, and take it
--    up with the donor. That is a conversation, not an arithmetic correction.
--
-- ---------------------------------------------------------------------------
-- 4. On the drops.
--
--    Every function whose argument list or return shape moves is dropped with
--    its FULL argument list before being recreated. `create or replace` cannot
--    change either, and a leftover overload with a defaulted argument does not
--    fail loudly — it makes the call ambiguous, which has broken this repo
--    more than once. The new signatures are dropped too, so re-running this
--    migration over itself is safe.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 5. The projection, in one place.
--
--    Stable rather than immutable: it reads now(). Pure otherwise — it touches
--    no table, so it cannot leak a row and needs no definer rights. Granted to
--    authenticated so a client holding a raw booking can ask the same question
--    the lists answer, and get the same answer.
--
--    The `held_until is not null` arm is redundant against the table's own
--    check constraint (0048: a held booking must carry an expiry) and is
--    written anyway, so that a null cannot quietly turn the comparison into
--    null and hand back 'held' by way of the else branch.
-- ---------------------------------------------------------------------------

create or replace function public.sponsorship_effective_status(
  p_status text,
  p_held_until timestamptz
)
returns text
language sql
stable
set search_path = ''
as $$
  select case
    when p_status = 'held'
      and p_held_until is not null
      and p_held_until <= now()
    then 'released'
    else p_status
  end
$$;

comment on function public.sponsorship_effective_status(text, timestamptz) is
  'A booking''s status as the calendar already sees it: a hold whose time has passed reads as released, because sponsorship_availability has been giving that date away since the moment it expired. Everything else is returned unchanged.';

revoke all on function public.sponsorship_effective_status(text, timestamptz)
  from public, anon;
grant execute on function public.sponsorship_effective_status(text, timestamptz)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 6. A devotee's own sponsorships, live by default.
--
--    The filter is applied to the PROJECTED status, not the stored one. That is
--    the whole point: an expired hold is lapsed, so it is hidden by default and
--    reads as 'released' when it is asked for. Filtering on the stored status
--    would return the stale row and then label it released, which is the worst
--    of both — a card in the giving history that says it is not a gift.
--
--    coalesce on the flag because a client that sends an explicit null means
--    "you decide", and the default is what we decided.
-- ---------------------------------------------------------------------------

drop function if exists public.list_my_sponsorships();
drop function if exists public.list_my_sponsorships(boolean);

create function public.list_my_sponsorships(
  p_include_lapsed boolean default false
)
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
    public.sponsorship_effective_status(bookings.status, bookings.held_until),
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
    and (
      coalesce(p_include_lapsed, false)
      or public.sponsorship_effective_status(bookings.status, bookings.held_until)
         in ('held', 'confirmed')
    )
  order by bookings.on_date desc nulls first, bookings.created_at desc
$$;

comment on function public.list_my_sponsorships(boolean) is
  'Your own sponsorships. By default only the live ones — a hold that has not run out, or a confirmed gift; pass true to include the dates you gave back. A hold whose time has passed reads as released whether or not a sweep has run, because the calendar already treats that date as free.';

revoke all on function public.list_my_sponsorships(boolean) from public, anon;
grant execute on function public.list_my_sponsorships(boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- 7. Every sponsorship, on the same terms.
--
--    Same flag, same projection, same default. The President's record and the
--    devotee's record must not be able to disagree about what a booking is,
--    and the only way to guarantee that is for both to ask the same function
--    the same question — which is why section 5 exists as a function rather
--    than as two copies of a case expression.
-- ---------------------------------------------------------------------------

drop function if exists public.list_all_sponsorships();
drop function if exists public.list_all_sponsorships(boolean);

create function public.list_all_sponsorships(
  p_include_lapsed boolean default false
)
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
    public.sponsorship_effective_status(bookings.status, bookings.held_until),
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
    and (
      coalesce(p_include_lapsed, false)
      or public.sponsorship_effective_status(bookings.status, bookings.held_until)
         in ('held', 'confirmed')
    )
  order by bookings.on_date desc nulls first, bookings.created_at desc
$$;

comment on function public.list_all_sponsorships(boolean) is
  'Every sponsorship with its sponsor named, for the President and Tech Admin. Live ones by default; pass true for the dates that were given back. Statuses are projected exactly as list_my_sponsorships projects them, so the two records agree.';

revoke all on function public.list_all_sponsorships(boolean) from public, anon;
grant execute on function public.list_all_sponsorships(boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- 8. One devotee's seva, act by act, for whoever may see everything.
--
--    my_seva_acts with auth.uid() replaced by an argument and app.view_all
--    added. Nothing else moves — not the ninety-day default window, not the
--    weekday spelling, not the order, and not one column name or position. A
--    client that can render my_seva_acts can render this, and if it could not,
--    the President and the devotee would be reading two different accounts of
--    the same Tuesday.
--
--    p_devotee_id is not null is a guard and not a courtesy: seva_mala_acts
--    interprets a null argument as "everybody", so a null slipping through here
--    would hand the whole congregation's history to a caller who asked for one
--    devotee's. It is checked even though app.view_all is already required,
--    because a President asking about a devotee whose id the client failed to
--    resolve should get an empty screen and not a congregation.
--
--    Empty for anyone without app.view_all rather than an exception. This backs
--    a screen; a refusal that arrives as an error is a refusal that tells the
--    caller there was something worth refusing.
-- ---------------------------------------------------------------------------

drop function if exists public.list_devotee_seva_acts(uuid, date, date);

create function public.list_devotee_seva_acts(
  p_devotee_id uuid,
  p_from date default null,
  p_to date default null
)
returns table (
  assignment_id uuid,
  service_instance_id uuid,
  service_type_id uuid,
  seva_name text,
  occurred_on date,
  weekday text,
  started_at_local time,
  minutes numeric,
  hours numeric,
  is_recurring boolean,
  assignment_status text,
  verification text,
  attendance text,
  points_status text,
  points_note text
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    acts.assignment_id,
    acts.service_instance_id,
    acts.service_type_id,
    acts.seva_name,
    acts.occurred_on,
    trim(to_char(acts.occurred_on, 'FMDay')),
    acts.started_at_local,
    acts.raw_minutes,
    round(acts.raw_minutes / 60.0, 2),
    acts.is_recurring,
    acts.assignment_status,
    acts.verification,
    acts.attendance,
    acts.points_status,
    public.seva_points_note(acts.points_status)
  from public.seva_mala_acts(p_devotee_id) acts
  where auth.uid() is not null
    and p_devotee_id is not null
    and public.has_permission('app.view_all')
    and acts.occurred_on
        between coalesce(p_from, public.seva_mala_today() - 89)
            and coalesce(p_to, public.seva_mala_today())
  order by acts.occurred_on desc, acts.started_at_local desc, acts.seva_name
$$;

comment on function public.list_devotee_seva_acts(uuid, date, date) is
  'One devotee''s seva act by act, in the same shape my_seva_acts returns for the caller''s own. President and Tech Admin only; empty for everybody else, because this backs a screen.';

revoke all on function public.list_devotee_seva_acts(uuid, date, date) from public, anon;
grant execute on function public.list_devotee_seva_acts(uuid, date, date) to authenticated;

-- ---------------------------------------------------------------------------
-- 9. Every gift, filterable, and saying where its sponsorship stands.
--
--    0049 section 13 plus two things: a donor to narrow to, and the booking's
--    projected status on the row.
--
--    booking_status is null when a donation paid for no sponsorship, which is
--    most of them, and that null is meaningful — "this was a gift, not a date".
--    It is the projected status and not bookings.status, so it cannot disagree
--    with what list_all_sponsorships shows for the same booking.
--
--    p_donor_id matches on donor_id only. A gift from somebody who has never
--    opened the app carries a donor_email and no donor_id, and it belongs to
--    nobody's history until the President attaches it — which is
--    attach_donation_to_booking's job, and not a thing a filter should guess at
--    by comparing text.
-- ---------------------------------------------------------------------------

drop function if exists public.list_all_donations(date, date);
drop function if exists public.list_all_donations(date, date, uuid);

create function public.list_all_donations(
  p_from date default null,
  p_to date default null,
  p_donor_id uuid default null
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
  booking_status text,
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
    public.sponsorship_effective_status(bookings.status, bookings.held_until),
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
    and (p_donor_id is null or donations.donor_id = p_donor_id)
  order by donations.received_at desc, donations.id
$$;

comment on function public.list_all_donations(date, date, uuid) is
  'Every gift in a window of Chicago dates, optionally one donor''s, with the reconciliation and the standing of any sponsorship it paid for. President and Tech Admin only; empty for everybody else. A gift attached to a released or cancelled booking is still a gift and is still listed — the date came back, the money did not.';

revoke all on function public.list_all_donations(date, date, uuid) from public, anon;
grant execute on function public.list_all_donations(date, date, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 10. The total, computed where the rows are.
--
--     One row per currency, and no way to ask for fewer. total_cents is bigint
--     because a year of a growing temple's giving in cents outgrows an integer
--     long before it outgrows the temple.
--
--     Note what this function does not do. It does not join
--     sponsorship_bookings. It has no status predicate, because there is no
--     status on a donation that means the money came back — a refund would be
--     a row of its own with a negative amount, and there is no such row today.
--     Every donation received in the window is counted. See the header.
--
--     p_from and p_to are required rather than defaulted, unlike
--     list_all_donations'. A caller asking for a total must say over what; the
--     window on the screen and the window in the total are the same window, and
--     making it possible to omit it is making it possible to publish a
--     lifetime figure under a heading that says "this month". Nulls are
--     accepted and mean all time — said explicitly.
-- ---------------------------------------------------------------------------

drop function if exists public.donation_totals(date, date, uuid);

create function public.donation_totals(
  p_from date,
  p_to date,
  p_donor_id uuid default null
)
returns table (
  currency text,
  total_cents bigint,
  gifts integer
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    donations.currency,
    sum(donations.amount_cents)::bigint,
    count(*)::integer
  from public.donations
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
    and (p_donor_id is null or donations.donor_id = p_donor_id)
  group by donations.currency
  order by sum(donations.amount_cents) desc, donations.currency
$$;

comment on function public.donation_totals(date, date, uuid) is
  'What the temple received in a window of Chicago dates, one row per currency and never summed across them, optionally for one donor. President and Tech Admin only; empty for everybody else. Every donation received is counted, including one whose sponsorship was later released or cancelled: that gave back a date, not the gift.';

revoke all on function public.donation_totals(date, date, uuid) from public, anon;
grant execute on function public.donation_totals(date, date, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 11. The same figure, for the devotee it belongs to.
--
--     No window and no donor argument. "What have I given" is the whole
--     question a devotee asks, the answer is their whole history, and an
--     argument that could name a donor is an argument somebody will eventually
--     be tempted to pass somebody else's id to. There is nothing to pass.
--
--     Same shape as donation_totals, so the one component that renders a
--     currency total renders either.
-- ---------------------------------------------------------------------------

drop function if exists public.my_donation_totals();

create function public.my_donation_totals()
returns table (
  currency text,
  total_cents bigint,
  gifts integer
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    donations.currency,
    sum(donations.amount_cents)::bigint,
    count(*)::integer
  from public.donations
  where auth.uid() is not null
    and donations.donor_id = auth.uid()
  group by donations.currency
  order by sum(donations.amount_cents) desc, donations.currency
$$;

comment on function public.my_donation_totals() is
  'What you have given the temple, one row per currency and never summed across them. Only ever your own. Every gift counts, including one whose sponsorship you later gave back.';

revoke all on function public.my_donation_totals() from public, anon;
grant execute on function public.my_donation_totals() to authenticated;

do $$
begin
  raise notice 'giving and acts reads applied';
end;
$$;
