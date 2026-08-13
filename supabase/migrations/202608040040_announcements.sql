-- Announcements: the temple's noticeboard.
--
-- Janmashtami is on the 15th, Ekadashi is tomorrow, the parking lot is closed
-- Sunday morning. None of that is seva, none of it belongs in a chat thread,
-- and until now the app had nowhere to put it.
--
-- The shape is deliberately plain:
--
--   * a title, some words, and optionally a photo;
--   * posted by a Community Head, a Tech Admin, or the President;
--   * read by every devotee, with nothing to join and nothing to accept;
--   * taken down by whoever posted it, or by any of the three above;
--   * and, if it was given an end, it takes itself down when that has passed.
--
-- The dates and times are not the announcement. The words are. A devotee reads
-- "Janmashtami midnight arati begins at 11pm in the main hall" and knows what
-- to do; the fields exist so that the notice stops occupying the top of their
-- screen in September, not so that the app can render a calendar from them.
-- That is why all four are optional and independent of one another: a notice
-- may have an end and no beginning, a day and no clock, or neither.
--
-- Requires 202608040039_sangas.sql.

-- ---------------------------------------------------------------------------
-- 1. The notice itself.
-- ---------------------------------------------------------------------------

create table if not exists public.announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  body text not null,
  image_url text,
  -- The poster may one day leave the congregation. The notice they put up is
  -- the temple's, not theirs, so the row survives and only the attribution
  -- goes. A null poster is nobody's to delete but a Community Head's, which is
  -- the right answer once the author is gone.
  posted_by uuid references public.users(id) on delete set null,
  starts_on date,
  ends_on date,
  starts_at time,
  ends_at time,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint announcement_title_not_blank check (nullif(trim(title), '') is not null),
  constraint announcement_body_not_blank check (nullif(trim(body), '') is not null),
  -- Only the day pair can be checked here. Whether a time is "before" another
  -- depends on which day each one falls on, and a notice running from Friday
  -- evening to Sunday morning has an ends_at earlier in the clock than its
  -- starts_at while being perfectly ordered. create_announcement below settles
  -- the same-day case, where the comparison actually means something.
  constraint announcement_dates_ordered check (
    starts_on is null or ends_on is null or ends_on >= starts_on
  )
);

create index if not exists announcements_created_at_idx
  on public.announcements (created_at desc);

-- The list query filters on the end before it orders, and the overwhelming
-- majority of rows have no end at all.
create index if not exists announcements_ends_on_idx
  on public.announcements (ends_on) where ends_on is not null;

create index if not exists announcements_posted_by_idx
  on public.announcements (posted_by);

-- ---------------------------------------------------------------------------
-- 2. When a notice has run out — answered in Chicago, never in UTC.
--
--    This is the whole reason the function exists rather than being inlined.
--    Postgres holds now() as an instant, and at 7pm on the 14th in Chicago that
--    instant is already the 15th in UTC. Comparing an ends_on against a UTC
--    date therefore retires a notice on the evening before its last day: the
--    Janmashtami notice disappears five hours before Janmashtami ends. Every
--    other date comparison in this codebase reads
--    `(now() at time zone 'America/Chicago')::date` for exactly that reason,
--    and this one is no different.
--
--    The rules, in order:
--
--      * no ends_on: the notice stays until somebody takes it down. A standing
--        notice about temple opening hours has no expiry, and inventing one for
--        it would be worse than useless.
--      * an ends_on and no ends_at: the notice lasts the whole of that day in
--        Chicago, and goes at that day's midnight. A notice ending today is
--        still up all of today — this is the boundary that vanishes things a
--        day early when it is written as `ends_on >= today` in the wrong zone.
--      * an ends_on and an ends_at: the notice goes when that clock time
--        passes on that day, in Chicago. The 2pm–4pm bake sale stops shouting
--        at 4pm rather than at midnight.
--
--    ends_at without an ends_on says nothing about expiry — there is no day for
--    it to fall on — so it is ignored here and the notice stands.
-- ---------------------------------------------------------------------------

create or replace function public.announcement_is_live(
  p_ends_on date,
  p_ends_at time
)
returns boolean
language sql
stable
set search_path = ''
as $$
  select
    p_ends_on is null
    or (
      p_ends_on
        + coalesce(p_ends_at, time '00:00')
        + case when p_ends_at is null then interval '1 day' else interval '0' end
    ) > (now() at time zone 'America/Chicago')
$$;

comment on function public.announcement_is_live(date, time) is
  'True while an announcement with this end has not yet passed in America/Chicago.';

revoke all on function public.announcement_is_live(date, time) from public, anon;
grant execute on function public.announcement_is_live(date, time) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Who may take a notice down.
--
--    Community Head, Tech Admin, President — the same three who may put one up,
--    identified the same way the rest of the app identifies them, by holding
--    services.manage_recurring. No new permission key is registered: a fourth
--    role would have to be given announcement rights explicitly and would then
--    silently lack them, and the temple has been clear that these three speak
--    for it.
-- ---------------------------------------------------------------------------

create or replace function public.may_post_announcements()
returns boolean
language sql
stable
set search_path = ''
as $$
  select public.has_permission('services.manage_recurring')
$$;

revoke all on function public.may_post_announcements() from public, anon;
grant execute on function public.may_post_announcements() to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Reading.
--
--    Every devotee sees every live notice. There is no audience to pick and no
--    membership to check: that is what makes it a noticeboard.
--
--    The policy repeats the liveness test that list_announcements applies, so
--    a client that queries the table directly still cannot surface a notice the
--    temple considers finished. A poster keeps sight of their own expired
--    notices, and so does anyone who could delete them, because both need to
--    find the stale one to take it down.
-- ---------------------------------------------------------------------------

alter table public.announcements enable row level security;

drop policy if exists "Devotees read live announcements" on public.announcements;
create policy "Devotees read live announcements"
  on public.announcements for select to authenticated
  using (
    auth.uid() is not null
    and (
      public.announcement_is_live(ends_on, ends_at)
      or posted_by = auth.uid()
      or public.may_post_announcements()
    )
  );

-- Every write goes through an RPC below, so nothing beyond reading is granted.
revoke all on public.announcements from anon, authenticated;
grant select (
  id, title, body, image_url, posted_by,
  starts_on, ends_on, starts_at, ends_at, created_at, updated_at
) on public.announcements to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Telling the congregation there is a new notice.
--
--    Extended whole rather than appended to, because the constraint is
--    replaced rather than altered and a partial list would quietly outlaw
--    every kind already in use.
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
      'sanga_admin_transferred',
      'announcement_posted',
      'remote'
    )
  );

-- ---------------------------------------------------------------------------
-- 6. Putting one up.
-- ---------------------------------------------------------------------------

create or replace function public.create_announcement(
  p_title text,
  p_body text,
  p_image_url text default null,
  p_starts_on date default null,
  p_ends_on date default null,
  p_starts_at time default null,
  p_ends_at time default null
)
returns public.announcements
language plpgsql
security definer
set search_path = ''
as $$
declare
  clean_title text;
  clean_body text;
  clean_image text;
  created public.announcements;
  poster_name text;
  devotee record;
begin
  if auth.uid() is null then
    raise exception 'Sign in to post an announcement.';
  end if;

  if not public.may_post_announcements() then
    raise exception 'Only a Community Head, Tech Admin, or the President can post an announcement.';
  end if;

  clean_title := nullif(trim(coalesce(p_title, '')), '');
  if clean_title is null then
    raise exception 'Please give the announcement a title.';
  end if;

  clean_body := nullif(trim(coalesce(p_body, '')), '');
  if clean_body is null then
    raise exception 'Please write the announcement.';
  end if;

  if p_starts_on is not null and p_ends_on is not null and p_ends_on < p_starts_on then
    raise exception 'The announcement ends before it starts. Check the dates.';
  end if;

  -- Only meaningful when both times land on the same day: either the notice
  -- names one date for both ends, or it names no dates at all and the two
  -- times can only be read as a single afternoon.
  if p_starts_at is not null and p_ends_at is not null
     and p_starts_on is not distinct from p_ends_on
     and p_ends_at < p_starts_at
  then
    raise exception 'The announcement ends before it starts. Check the times.';
  end if;

  -- A photo must have come out of the app's own storage. Left open, this column
  -- is a way to have every devotee's phone fetch an arbitrary URL the moment the
  -- notice renders, which is a tracking pixel the temple did not agree to.
  clean_image := nullif(trim(coalesce(p_image_url, '')), '');
  if clean_image is not null
     and clean_image !~ '^https://[a-z0-9.-]+/storage/v1/object/public/message-images/'
  then
    raise exception 'An announcement photo must be uploaded through the app.';
  end if;

  insert into public.announcements (
    title, body, image_url, posted_by, starts_on, ends_on, starts_at, ends_at
  )
  values (
    clean_title, clean_body, clean_image, auth.uid(),
    p_starts_on, p_ends_on, p_starts_at, p_ends_at
  )
  returning * into created;

  select users.name into poster_name from public.users where users.id = auth.uid();

  -- Everyone, because that is what a noticeboard is. The poster is left out:
  -- they are standing at it. Any single failure to reach one devotee must not
  -- undo the notice for the rest, and queue_app_notification only writes a row
  -- — the push itself is already fire-and-forget in deliver_app_notification.
  for devotee in
    select users.id from public.users where users.id <> auth.uid()
  loop
    perform public.queue_app_notification(
      devotee.id,
      'announcement_posted',
      'New announcement',
      coalesce(poster_name, 'The temple') || ' posted "' || created.title || '".',
      jsonb_build_object('announcementId', created.id)
    );
  end loop;

  return created;
end;
$$;

revoke all on function public.create_announcement(text, text, text, date, date, time, time)
  from public, anon;
grant execute on function public.create_announcement(text, text, text, date, date, time, time)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 7. Reading the board.
--
--    Definer, so that the liveness rule is decided in exactly one place and a
--    devotee's client cannot be handed a different answer than the policy would
--    give. can_delete travels with the row because every card needs it to
--    decide whether to draw the button, and a second round trip per notice to
--    ask the same question would be absurd.
--
--    A notice whose starts_on is still ahead is shown. That is not an
--    oversight: "Janmashtami is on the 15th" is worth nothing on the 16th and
--    everything on the 1st, and a noticeboard that hid notices until their
--    event began would be a noticeboard nobody could plan around.
-- ---------------------------------------------------------------------------

create or replace function public.list_announcements()
returns table (
  id uuid,
  title text,
  body text,
  image_url text,
  posted_by uuid,
  posted_by_name text,
  posted_by_photo_url text,
  starts_on date,
  ends_on date,
  starts_at time,
  ends_at time,
  created_at timestamptz,
  can_delete boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    announcements.id,
    announcements.title,
    announcements.body,
    announcements.image_url,
    announcements.posted_by,
    poster.name,
    poster.photo_url,
    announcements.starts_on,
    announcements.ends_on,
    announcements.starts_at,
    announcements.ends_at,
    announcements.created_at,
    (
      announcements.posted_by = auth.uid()
      or public.may_post_announcements()
    )
  from public.announcements
  left join public.users poster on poster.id = announcements.posted_by
  where auth.uid() is not null
    and public.announcement_is_live(announcements.ends_on, announcements.ends_at)
  order by announcements.created_at desc
$$;

revoke all on function public.list_announcements() from public, anon;
grant execute on function public.list_announcements() to authenticated;

-- ---------------------------------------------------------------------------
-- 8. Taking one down.
--
--    Two people may: whoever put it up, and any of the three who could have.
--    The row goes for good. A notice is not a record of anything — it is a
--    piece of paper on a board — and keeping a tombstone for it would only
--    give the list something to have to filter out forever.
-- ---------------------------------------------------------------------------

create or replace function public.delete_announcement(p_announcement_id uuid)
returns public.announcements
language plpgsql
security definer
set search_path = ''
as $$
declare
  target public.announcements;
begin
  if auth.uid() is null then
    raise exception 'Sign in to remove an announcement.';
  end if;

  select * into target
  from public.announcements
  where announcements.id = p_announcement_id
  for update;

  if target.id is null then
    raise exception 'That announcement could not be found.';
  end if;

  if target.posted_by is distinct from auth.uid()
     and not public.may_post_announcements()
  then
    raise exception 'You can remove your own announcement, or any announcement if you are a Community Head, Tech Admin, or the President.';
  end if;

  delete from public.announcements where announcements.id = target.id;

  return target;
end;
$$;

revoke all on function public.delete_announcement(uuid) from public, anon;
grant execute on function public.delete_announcement(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 9. Photos.
--
--    The message-images bucket already holds exactly this kind of picture: put
--    there by one signed-in devotee, looked at by all of them, capped at 8MB,
--    and written only inside the uploader's own folder. A second bucket would
--    mean a second size limit and a second set of policies to keep in step with
--    it, for no difference a devotee could ever see.
-- ---------------------------------------------------------------------------

do $$
begin
  if not exists (select 1 from storage.buckets where id = 'message-images') then
    raise exception 'The message-images bucket is missing; apply 202608040032_messaging.sql first.';
  end if;
end;
$$;

do $$
begin
  raise notice 'announcements applied';
end;
$$;
