-- One Sunday, one feast, whichever rate the devotee chose.
--
-- 202608040050_sponsorship_campaigns.sql made the Sunday Feast two rows —
-- $551 and $751 — because they are two prices and a price is copied onto a
-- booking. It did not notice what that does to the promise 202608040048 was
-- built around. That promise is a partial unique index:
--
--     unique (sponsorship_type_id, on_date)
--       where status in ('held','confirmed') and on_date is not null
--
-- Two tiers are two sponsorship_type_ids. So on any given Sunday one devotee
-- can take the $551 feast and another can take the $751 feast, and the temple
-- has sold one Sunday twice. Nobody is refused, nobody is warned, and the
-- second devotee finds out on the day.
--
-- The tiers are alternatives, not products. One devotee sponsors that Sunday's
-- feast, at whichever rate they choose, and that Sunday is then gone.
--
-- What the group is, and why it is a column
-- -----------------------------------------
-- The index needs to compare something that is equal across all tiers of one
-- sponsorship. There were two candidates.
--
--   * Derive it from zeffy_campaign_slug, falling back to the id when the slug
--     is null.
--   * Store it: a group column on sponsorship_types, defaulting to the row's
--     own id so an untiered sponsorship is a group of one.
--
-- The slug loses, and it loses on the temple's own data rather than on
-- principle. A Zeffy campaign is a payment page. 0050 says so twice: its
-- tiers-agree trigger exists precisely because a page and a booking rule are
-- different things, and its own header admits that a President may deliberately
-- put a Garland and a Rajbhog on one page at different prices and that nothing
-- structural can tell that apart from two rates on one seva. Under
-- slug-derivation that data-entry decision silently makes the Garland and the
-- Rajbhog mutually exclusive on every day of the year, and the temple loses a
-- booking it never agreed to give up.
--
-- Worse in the other direction: the slug is editable. supabase/verification/
-- donation_reconciliation.sql already exercises a President repointing the
-- higher Sunday Feast at a page of its own. Under slug-derivation that one edit
-- silently splits the exclusivity group and restores the exact bug this file
-- exists to remove — with no error, no warning, and no way to see it except by
-- double-booking a Sunday. An exclusivity rule that a URL edit can dissolve is
-- not a rule.
--
-- So the group is stored, and it is its own fact. The slug seeds it once, here,
-- because today the slug is the only evidence in the database that two rows are
-- one seva at two rates; from then on the column is the truth and the President
-- can say so directly through save_sponsorship_type.
--
-- Why it is denormalised onto the booking
-- ---------------------------------------
-- A unique index predicate cannot reach across a join, so the group has to be a
-- stored column on sponsorship_bookings or there is no index to build. That
-- makes it derived data, and derived data that anybody may write is derived
-- data that will one day disagree with what it was derived from. It is
-- therefore never accepted from a caller: a BEFORE trigger overwrites whatever
-- was supplied with the type's own group, on insert and on any update that
-- touches either column, and an AFTER trigger on sponsorship_types pushes a
-- regrouping down onto the bookings that already exist. There is no path by
-- which a booking's group is anything other than its type's.
--
-- The thing most likely to be broken here
-- ---------------------------------------
-- The dateless sponsorship. 0050 spends a page explaining that the Deity Dress
-- has no day, that several devotees sponsor one at once, and that the only
-- thing keeping them from colliding is `on_date is not null` in the index
-- predicate — stated outright rather than left to NULLS DISTINCT, so that a
-- later hand "tightening" the index cannot reduce the temple to one deity dress
-- for all time. This migration rewrites that index. The predicate is carried
-- over verbatim, and supabase/verification/tier_exclusivity.sql proves the
-- consequence again from scratch: three devotees, three deity dresses, no
-- collision, through the RPC and straight into the table.
--
-- Requires 202608040050_sponsorship_campaigns.sql.

-- ---------------------------------------------------------------------------
-- 1. The group, on the sponsorship.
--
--    Nullable for exactly as long as it takes to fill in, then NOT NULL — a
--    null group in a unique index is a null in a unique index, which is to say
--    it is not a constraint at all, and this column exists only to be one.
-- ---------------------------------------------------------------------------

alter table public.sponsorship_types
  add column if not exists exclusivity_group uuid;

comment on column public.sponsorship_types.exclusivity_group is
  'The sponsorship these tiers are alternatives of. Its own id when it has no tiers. One group takes one date.';

-- Every sponsorship is its own group until something says otherwise.
update public.sponsorship_types
set exclusivity_group = sponsorship_types.id
where sponsorship_types.exclusivity_group is null;

-- The one-time reading of the slug. A campaign carrying more than one tier,
-- where the tiers agree about how they are booked, is one seva at several
-- rates: that is what 0050's tiers-agree trigger already guarantees about any
-- shared slug, and it is the only evidence the database holds.
--
-- bool_and(exclusivity_group = id) is what makes this re-runnable. It merges
-- only a campaign nobody has grouped by hand yet, so applying this migration a
-- second time cannot undo a President who has since split or joined the tiers
-- deliberately. The anchor is the first tier in the temple's own display order,
-- so the group is named by the base rate rather than by whichever uuid sorted
-- first.
with campaign_groups as (
  select
    tiers.zeffy_campaign_slug as slug,
    (array_agg(tiers.id order by tiers.display_order, tiers.amount_cents, tiers.id))[1]
      as anchor
  from public.sponsorship_types tiers
  where tiers.zeffy_campaign_slug is not null
  group by tiers.zeffy_campaign_slug
  having count(*) > 1
     and count(distinct tiers.sunday_only) = 1
     and count(distinct tiers.requires_date) = 1
     and bool_and(tiers.exclusivity_group = tiers.id)
)
update public.sponsorship_types
set exclusivity_group = campaign_groups.anchor,
    updated_at = now()
from campaign_groups
where sponsorship_types.zeffy_campaign_slug = campaign_groups.slug
  and sponsorship_types.exclusivity_group is distinct from campaign_groups.anchor;

alter table public.sponsorship_types
  alter column exclusivity_group set not null;

create index if not exists sponsorship_types_exclusivity_group_idx
  on public.sponsorship_types (exclusivity_group);

-- ---------------------------------------------------------------------------
-- 2. What to call a group when refusing somebody.
--
--    "Sunday Feast (higher) on Sunday the 16th has already been sponsored" is
--    true and useless: the devotee did not book the higher rate, somebody
--    booked the feast, and the sentence invites them to try the other rate. The
--    group is named by its first tier in display order, which is the base rate
--    and the name the temple uses when it says the word out loud.
-- ---------------------------------------------------------------------------

create or replace function public.sponsorship_group_label(p_group uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select types.name
  from public.sponsorship_types types
  where types.exclusivity_group = p_group
  order by types.display_order, types.amount_cents, types.id
  limit 1
$$;

comment on function public.sponsorship_group_label(uuid) is
  'What to call a sponsorship whose tiers are alternatives: the name of its base rate.';

revoke all on function public.sponsorship_group_label(uuid) from public, anon;
grant execute on function public.sponsorship_group_label(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. Keeping the sponsorship's own group filled in.
--
--    A row inserted with no group gets one, and which one it gets is the only
--    guess in this file:
--
--      * If the campaign it names already carries tiers and those tiers agree
--        on a single group, the new row joins them. A President adding a third
--        Sunday Feast rate through the app is adding a rate, and a rate that
--        quietly failed to join the group would restore this bug for that rate
--        alone.
--      * Otherwise it is its own group.
--
--    The guess errs towards grouping, and it errs that way on purpose. Grouping
--    two things that were not alternatives takes a date off the calendar that
--    the President can put back in one edit. Failing to group two things that
--    were takes a devotee's money for a Sunday another devotee already has.
--    Those are not comparable, so the tie breaks towards the calendar.
-- ---------------------------------------------------------------------------

create or replace function public.set_sponsorship_type_exclusivity_group()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_campaign_group uuid;
begin
  if tg_op = 'UPDATE' then
    -- A null on an update means "leave it alone", the same as every other
    -- optional field in save_sponsorship_type.
    new.exclusivity_group :=
      coalesce(new.exclusivity_group, old.exclusivity_group, new.id);
    return new;
  end if;

  if new.exclusivity_group is not null then
    return new;
  end if;

  if new.zeffy_campaign_slug is not null then
    select case
             when count(distinct other.exclusivity_group) = 1
             then (array_agg(distinct other.exclusivity_group))[1]
           end
    into v_campaign_group
    from public.sponsorship_types other
    where other.zeffy_campaign_slug = new.zeffy_campaign_slug
      and other.id <> new.id;
  end if;

  -- The column default has already given the row its id by the time a BEFORE
  -- trigger runs, so a group of one can be named after itself.
  new.exclusivity_group := coalesce(v_campaign_group, new.id);
  return new;
end;
$$;

comment on function public.set_sponsorship_type_exclusivity_group() is
  'Gives a sponsorship an exclusivity group: its campaign''s, when its campaign has one, and its own otherwise.';

-- A function is granted to PUBLIC the moment it is created, and these three are
-- SECURITY DEFINER. Calling one outside a trigger only earns an error, so the
-- grant is not a hole today — but it is a SECURITY DEFINER function reachable
-- by anon, and the cheapest moment to close it is the one it is written in.
revoke all on function public.set_sponsorship_type_exclusivity_group()
  from public, anon, authenticated;

drop trigger if exists sponsorship_type_exclusivity_group on public.sponsorship_types;
create trigger sponsorship_type_exclusivity_group
  before insert or update of exclusivity_group, zeffy_campaign_slug
  on public.sponsorship_types
  for each row execute function public.set_sponsorship_type_exclusivity_group();

-- ---------------------------------------------------------------------------
-- 4. The group, on the booking.
--
--    Denormalised because an index predicate cannot join. Derived, therefore
--    never written by anybody: section 5's trigger overwrites it.
-- ---------------------------------------------------------------------------

alter table public.sponsorship_bookings
  add column if not exists exclusivity_group uuid;

comment on column public.sponsorship_bookings.exclusivity_group is
  'Copied from the sponsorship type by trigger, because a unique index cannot reach across a join. Never set by hand.';

update public.sponsorship_bookings
set exclusivity_group = types.exclusivity_group
from public.sponsorship_types types
where types.id = sponsorship_bookings.sponsorship_type_id
  and sponsorship_bookings.exclusivity_group is distinct from types.exclusivity_group;

alter table public.sponsorship_bookings
  alter column exclusivity_group set not null;

-- ---------------------------------------------------------------------------
-- 5. The two triggers that make the copy true.
--
--    The first refuses to take the caller's word for the group. The second
--    carries a regrouping down onto the bookings that already exist, because a
--    President joining two tiers must not leave last week's bookings in the old
--    group where the index cannot see them.
-- ---------------------------------------------------------------------------

create or replace function public.set_sponsorship_booking_exclusivity_group()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_group uuid;
begin
  select types.exclusivity_group into v_group
  from public.sponsorship_types types
  where types.id = new.sponsorship_type_id;

  -- No such type: the foreign key is about to say so in better words, and it
  -- only gets to if the NOT NULL is satisfied first. The value is irrelevant
  -- because the row is not going to exist.
  new.exclusivity_group := coalesce(v_group, new.sponsorship_type_id);
  return new;
end;
$$;

comment on function public.set_sponsorship_booking_exclusivity_group() is
  'Copies the sponsorship type''s exclusivity group onto the booking, overwriting whatever the caller supplied.';

revoke all on function public.set_sponsorship_booking_exclusivity_group()
  from public, anon, authenticated;

drop trigger if exists sponsorship_booking_exclusivity_group on public.sponsorship_bookings;
create trigger sponsorship_booking_exclusivity_group
  before insert or update of sponsorship_type_id, exclusivity_group
  on public.sponsorship_bookings
  for each row execute function public.set_sponsorship_booking_exclusivity_group();

create or replace function public.remap_sponsorship_booking_groups()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.exclusivity_group is not distinct from old.exclusivity_group then
    return null;
  end if;

  begin
    update public.sponsorship_bookings
    set exclusivity_group = new.exclusivity_group,
        updated_at = now()
    where sponsorship_bookings.sponsorship_type_id = new.id
      and sponsorship_bookings.exclusivity_group is distinct from new.exclusivity_group;
  exception when unique_violation then
    -- Two live bookings that were on separate days-worth of calendar would
    -- become two live bookings on one. The regrouping is refused rather than
    -- one of them being chosen.
    raise exception
      'Grouping % with those tiers would leave two devotees sponsoring one day. Settle those bookings first.',
      new.name;
  end;

  return null;
end;
$$;

comment on function public.remap_sponsorship_booking_groups() is
  'Carries a change of exclusivity group down onto the bookings already made against that sponsorship.';

revoke all on function public.remap_sponsorship_booking_groups()
  from public, anon, authenticated;

drop trigger if exists sponsorship_type_regroups_bookings on public.sponsorship_types;
create trigger sponsorship_type_regroups_bookings
  after update of exclusivity_group on public.sponsorship_types
  for each row execute function public.remap_sponsorship_booking_groups();

-- ---------------------------------------------------------------------------
-- 6. Sundays already sold twice.
--
--    This migration tightens a constraint, so the data may already break it —
--    that is the whole reason it is being written. The index cannot be created
--    over rows that violate it, so the violations are dealt with first, and the
--    two kinds are not dealt with the same way:
--
--      two live holds        released. Nobody has paid, the later hold was
--                            never valid, and releasing an unpaid hold is what
--                            the sweep does to abandoned ones every five
--                            minutes anyway.
--      two confirmed         refused. That is money, on both sides, and a
--                            migration that quietly un-sponsors somebody's
--                            Sunday is a worse outcome than a deploy that stops
--                            and says which Sunday to look at.
--
--    On a database where the bug never fired — including the verification
--    cluster, which builds from empty — this section does nothing at all.
-- ---------------------------------------------------------------------------

do $$
declare
  v_row record;
begin
  for v_row in
    select bookings.exclusivity_group as grp, bookings.on_date as on_date
    from public.sponsorship_bookings bookings
    where bookings.status = 'confirmed'
      and bookings.on_date is not null
    group by bookings.exclusivity_group, bookings.on_date
    having count(*) > 1
  loop
    raise exception
      'Two devotees have already paid for % on %. Cancel one of those sponsorships before applying this migration.',
      coalesce(public.sponsorship_group_label(v_row.grp), 'one sponsorship'),
      to_char(v_row.on_date, 'FMDay FMDD FMMonth YYYY');
  end loop;

  -- Confirmed first, then oldest: the row that keeps the day is the one that
  -- was paid for, or failing that the one that asked first.
  with ranked as (
    select
      bookings.id,
      row_number() over (
        partition by bookings.exclusivity_group, bookings.on_date
        order by (bookings.status = 'confirmed') desc, bookings.created_at, bookings.id
      ) as standing
    from public.sponsorship_bookings bookings
    where bookings.status in ('held', 'confirmed')
      and bookings.on_date is not null
  )
  update public.sponsorship_bookings
  set status = 'released',
      held_until = null,
      updated_at = now()
  from ranked
  where ranked.id = sponsorship_bookings.id
    and ranked.standing > 1;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. THE constraint, now over the group.
--
--    `on_date is not null` is 0050's, carried across word for word, and it is
--    the single most important clause in this file. Without it the Deity Dress
--    — which has no day, and which several devotees sponsor at once — becomes a
--    thing exactly one devotee may ever sponsor, and nothing about the failure
--    would look like a failure. 0050 states the reasoning at length; this index
--    inherits it whole.
--
--    202608040048's (sponsorship_type_id, on_date) index is deliberately left
--    where it is. It is now implied by this one — two bookings of one type are
--    two bookings of one group — so it forbids nothing new, but it is the
--    promise 0048 and 0050 both wrote down and both verification scripts still
--    name, and a forward-only migration does not delete another migration's
--    stated promise for tidiness.
-- ---------------------------------------------------------------------------

create unique index if not exists sponsorship_booking_one_live_per_group_and_date
  on public.sponsorship_bookings (exclusivity_group, on_date)
  where status in ('held', 'confirmed') and on_date is not null;

comment on index public.sponsorship_booking_one_live_per_group_and_date is
  'One sponsor per sponsorship per day, whichever tier they chose. Dateless sponsorships are outside it by construction: they have no day to collide on.';

-- The one-live-hold-per-devotee rule widened the same way. Two open holds on
-- two rates of one dateless sponsorship are two candidates for one payment
-- exactly as two holds on one rate are. Recreated under its own name rather
-- than left beside a group-scoped twin: its meaning has not changed, only the
-- width of the word "sponsorship" in it.
drop index if exists public.sponsorship_booking_one_live_dateless_hold;

create unique index if not exists sponsorship_booking_one_live_dateless_hold
  on public.sponsorship_bookings (exclusivity_group, devotee_id)
  where status = 'held' and on_date is null;

comment on index public.sponsorship_booking_one_live_dateless_hold is
  'One open hold per devotee per dateless sponsorship. Confirmed ones are unlimited, and so are other devotees.';

create index if not exists sponsorship_bookings_group_date_idx
  on public.sponsorship_bookings (exclusivity_group, on_date);

-- ---------------------------------------------------------------------------
-- 8. Column grants for what was just added.
--
--    The app needs the group on the sponsorship list to draw one Sunday Feast
--    row with two prices on it rather than two rows that mysteriously share a
--    calendar. The policies from 202608040048 are untouched.
-- ---------------------------------------------------------------------------

grant select (exclusivity_group) on public.sponsorship_types to authenticated;
grant select (exclusivity_group) on public.sponsorship_bookings to authenticated;

-- ---------------------------------------------------------------------------
-- 9. Taking a date, from the group rather than from the tier.
--
--    0050's function, with the type swapped for its group in the three places
--    that decide whether the day is free, and with the refusal naming the seva
--    instead of the rate.
--
--    The sweep is one of those three and is the least obvious. If it stayed
--    per-tier, an abandoned $551 hold would sit in the index blocking the $751
--    rate until the five-minute cron caught it — and the devotee in front of
--    the screen would be told the Sunday was gone by a hold that had already
--    expired. The sweep has to free the whole group or it does not free the
--    day.
--
--    The dateless branch is grouped for the same reason and refuses the same
--    way. Nothing else moves: the signature, the order of the refusals and the
--    wording of every message that is not about the group are 0050's.
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
  v_label text;
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

  -- What to call the thing that is taken. The seva, not the rate: a devotee
  -- refused the $751 feast has not been refused a rate, they have been refused
  -- a Sunday, and telling them otherwise invites them to try the other tier.
  v_label := coalesce(public.sponsorship_group_label(v_type.exclusivity_group), v_type.name);

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

    -- Free anything abandoned anywhere in this group on this date. Per-group,
    -- not per-tier: an expired hold on the other rate holds this date in the
    -- index just as firmly as one on this rate.
    update public.sponsorship_bookings
    set status = 'released', held_until = null, updated_at = now()
    where sponsorship_bookings.exclusivity_group = v_type.exclusivity_group
      and sponsorship_bookings.on_date = p_on_date
      and sponsorship_bookings.status = 'held'
      and sponsorship_bookings.held_until <= now();

    select exists (
      select 1 from public.sponsorship_bookings
      where sponsorship_bookings.exclusivity_group = v_type.exclusivity_group
        and sponsorship_bookings.on_date = p_on_date
        and sponsorship_bookings.status in ('held', 'confirmed')
    ) into v_taken;

    if v_taken then
      raise exception '% on % has already been sponsored. Please choose another date.',
        v_label, to_char(p_on_date, 'FMDay FMDD FMMonth YYYY');
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
    where sponsorship_bookings.exclusivity_group = v_type.exclusivity_group
      and sponsorship_bookings.devotee_id = auth.uid()
      and sponsorship_bookings.on_date is null
      and sponsorship_bookings.status = 'held'
      and sponsorship_bookings.held_until <= now();

    select exists (
      select 1 from public.sponsorship_bookings
      where sponsorship_bookings.exclusivity_group = v_type.exclusivity_group
        and sponsorship_bookings.devotee_id = auth.uid()
        and sponsorship_bookings.on_date is null
        and sponsorship_bookings.status = 'held'
    ) into v_taken;

    if v_taken then
      raise exception 'You already have a % waiting to be paid for. Finish or release that one first.',
        v_label;
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
        v_label, to_char(p_on_date, 'FMDay FMDD FMMonth YYYY');
    else
      raise exception 'You already have a % waiting to be paid for. Finish or release that one first.',
        v_label;
    end if;
  end;

  return v_booking;
end;
$$;

revoke all on function public.hold_sponsorship(uuid, date) from public, anon;
grant execute on function public.hold_sponsorship(uuid, date) to authenticated;

-- ---------------------------------------------------------------------------
-- 10. The calendar, which must not offer a Sunday the other rate has taken.
--
--     One clause moves: the live booking is looked for across the group rather
--     than under the tier. Every tier of a group therefore reports the same day
--     as taken, by the same booking, which is the whole point — a calendar that
--     showed $751 free on a Sunday already sponsored at $551 would be inviting
--     a devotee towards a refusal, and if the index were ever wrong it would be
--     inviting them towards a double booking.
--
--     is_mine and booked_by_name follow the group too, so the devotee who took
--     the Sunday at $551 sees it as hers on both rows rather than seeing a
--     stranger hold the rate she did not pick.
--
--     Signature and columns are 0050's exactly, so nothing reading this changes.
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
    where bookings.exclusivity_group = types.exclusivity_group
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
-- 11. The sponsorship list, now saying which rows are alternatives.
--
--     Dropped and recreated because the row is wider. Without this the app has
--     two Sunday Feast rows, no way to tell they are one seva, and no honest
--     way to draw a calendar where tapping either one greys out both.
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
  zeffy_campaign_slug text,
  exclusivity_group uuid
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
    sponsorship_types.zeffy_campaign_slug,
    sponsorship_types.exclusivity_group
  from public.sponsorship_types
  where auth.uid() is not null
    and (sponsorship_types.is_active or public.may_view_all_giving())
  order by sponsorship_types.display_order, sponsorship_types.name
$$;

revoke all on function public.list_sponsorship_types() from public, anon;
grant execute on function public.list_sponsorship_types() to authenticated;

-- ---------------------------------------------------------------------------
-- 12. Saying so directly.
--
--     Section 3's guess reads the campaign, and the campaign is a payment page.
--     Sooner or later the temple will want two rates that are not on one page,
--     or two pages that are one seva, and the President needs a way to say
--     which without a migration.
--
--     p_exclusivity_group_id names a sponsorship, and the saved row joins that
--     sponsorship's group. Pointing a row at itself puts it in a group of its
--     own, which is how a tier is taken back out of a group — the same value
--     the column defaults to when nothing else is said. Null still means "leave
--     it alone", as every optional argument on this function has since 0049,
--     because a President editing a price on a form that predates this column
--     must not silently un-group the Sunday Feast.
--
--     The nine-argument form is dropped rather than kept beside this one, for
--     the reason 0049 and 0050 both give at length: both would have defaults
--     past the second argument and Postgres would refuse the call as ambiguous.
-- ---------------------------------------------------------------------------

drop function if exists public.save_sponsorship_type(
  text, integer, uuid, boolean, integer, boolean, text, text, boolean
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
  p_requires_date boolean default null,
  p_exclusivity_group_id uuid default null
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
  v_group uuid;
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

  if p_exclusivity_group_id is not null then
    if p_id is not null and p_exclusivity_group_id = p_id then
      -- Pointed at itself: a group of one, which is what an untiered
      -- sponsorship is and what a tier becomes when it leaves a group.
      v_group := p_id;
    else
      select other.exclusivity_group into v_group
      from public.sponsorship_types other
      where other.id = p_exclusivity_group_id;

      if v_group is null then
        raise exception
          'Point a sponsorship at one of the sponsorships it shares a date with.';
      end if;
    end if;
  end if;

  if p_id is null then
    insert into public.sponsorship_types (
      name, amount_cents, is_active, display_order,
      sunday_only, requires_date, zeffy_campaign_url, zeffy_campaign_slug,
      exclusivity_group
    )
    values (
      v_clean_name, p_amount_cents, coalesce(p_is_active, true), v_order,
      coalesce(p_sunday_only, false), coalesce(p_requires_date, true), v_url, v_slug,
      -- Null hands the decision to the trigger, which reads the campaign.
      v_group
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
        exclusivity_group = coalesce(v_group, sponsorship_types.exclusivity_group),
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
  text, integer, uuid, boolean, integer, boolean, text, text, boolean, uuid
) from public, anon;
grant execute on function public.save_sponsorship_type(
  text, integer, uuid, boolean, integer, boolean, text, text, boolean, uuid
) to authenticated;

do $$
begin
  raise notice 'tier exclusivity applied';
end;
$$;
