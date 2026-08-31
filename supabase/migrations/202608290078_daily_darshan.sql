-- Daily Darshan: the day's pictures of the Deities, and who dressed Them.
--
-- A devotee who cannot come to the temple on a Tuesday still wants to see
-- Radha Govinda that Tuesday. A devotee who dressed Them wants that recorded,
-- and the ones who did not want to know who did. That is the whole feature:
--
--   * a day, some pictures, and a line of words;
--   * each picture may name a Deity and the devotee who dressed Them;
--   * put up by a Community Head, a Tech Admin, or the President;
--   * seen by every signed-in devotee, with nothing to join and nothing to
--     accept;
--   * and the congregation is told once, when the day's darshan goes up.
--
-- 202608040040_announcements.sql is the file this one is written against. The
-- shape of the problem is the same — a post with pictures, visible to
-- everyone, notifying the whole congregation — so the answers are the same
-- answers: the same permission, the same `on delete set null` on the poster,
-- the same storage bucket, the same "every write goes through an RPC".
--
-- The one thing this file is really about
-- ---------------------------------------
-- A day has one darshan.
--
-- The temple asked for "daily pictures" and for "up to 5". Those two sentences
-- are the same sentence: five is a cap on what a devotee scrolls through for
-- Tuesday, not a cap on how many rows one INSERT may write. If a second post
-- on Tuesday made a second darshan, then "up to 5" would be enforced by the
-- database and defeated by tapping Post twice, which is the kind of limit that
-- is not a limit. So darshan_on carries a unique index and the cap means what
-- the temple meant.
--
-- Which forces the rest, and the rest is the interesting part:
--
--   * Posting again on a date the temple has already published REPLACES that
--     date's pictures and words. It is the Head noticing that photo three is
--     blurred, not a second darshan.
--   * The replacement keeps the SAME ROW. The id in Tuesday morning's
--     notification still resolves on Tuesday evening; a delete-and-reinsert
--     would leave every phone holding a dead link. The old image rows are
--     deleted with their parent still standing, so nothing is ever left
--     pointing at a darshan that no longer exists.
--   * And the congregation is told exactly once, because the notice is "there
--     is a darshan for Tuesday", which does not become true a second time when
--     the third photo is straightened. The insert notifies. The update does
--     not.
--
-- Two Community Heads posting Tuesday at the same instant are settled by the
-- unique index, not by a check-then-insert: the loser of the race catches the
-- unique violation and takes the update path, so one of them notifies and the
-- other amends.
--
-- darshan_on is a Chicago date
-- ----------------------------
-- Always `(now() at time zone 'America/Chicago')::date`, never current_date
-- and never now()::date. Both of those read the CALLER's timezone, and
-- PostgREST does not promise what that is; at 7pm on the 14th in Chicago, UTC
-- has already turned over to the 15th, and a future-date guard written in UTC
-- refuses a Head posting the evening's darshan. 202608040040 §2 and
-- 202608040048 make this argument at length; this file only obeys it.
--
-- Requires 202608040040_announcements.sql.

-- ---------------------------------------------------------------------------
-- 0. What this file assumes, asserted rather than trusted.
--
--    Both of these are things a later migration could quietly change, and both
--    would fail silently rather than loudly: a fourth role holding the
--    permission would be able to post to the whole congregation without anyone
--    noticing, and a missing bucket would only show up when a photo failed to
--    upload. 202608040064 §0 makes the first assertion for the Seva Mala board
--    for exactly this reason.
-- ---------------------------------------------------------------------------

do $$
declare
  v_holders text;
begin
  -- The temple named three: Community Head (core), Tech Admin (tech),
  -- President. services.manage_recurring is held by those three and by nobody
  -- else — 202608020001 seeds it to core, tech and president only, and no
  -- migration since has widened it. Section 2 explains why no new key is
  -- registered; this is the proof that the existing key names the right set.
  select string_agg(roles.name, ',' order by roles.name) into v_holders
  from public.role_permissions
  join public.roles on roles.id = role_permissions.role_id
  where role_permissions.permission_key = 'services.manage_recurring';

  if v_holders is distinct from 'core,president,tech' then
    raise exception
      'services.manage_recurring is held by % — Daily Darshan assumes core, president, tech.',
      coalesce(v_holders, '(nobody)');
  end if;

  -- Announcements' pictures live in message-images (202608040040 §9). So do
  -- these. A second bucket would mean a second size limit, a second mime list
  -- and a second set of storage policies to keep in step, for no difference a
  -- devotee could ever see.
  if not exists (select 1 from storage.buckets where storage.buckets.id = 'message-images') then
    raise exception
      'The message-images bucket is missing; apply 202608040032_messaging.sql first.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 1. The dials.
--
--    Five is the temple's number today and is not this file's to hardcode. A
--    President who wants six should be an UPDATE, not a migration, so every
--    limit below is a row in app_settings and no function body contains a
--    literal bound.
--
--      max_images       5   what the temple asked for.
--      min_images       1   a darshan with no pictures is not a darshan. It is
--                           a caption, and there is nowhere to show it.
--      max_note_chars   2000  the note is a line under a gallery, not an
--                           announcement; announcements already exist and are
--                           the right place for paragraphs.
--      max_credit_chars 120 "Radha Govinda" and "Bhaktin Anjali" — a name, not
--                           a story. Long enough for a diksa name in full.
--      max_backdate_days 7  yesterday's darshan posted this morning is normal;
--                           a date last month is a typo in the picker.
--      list_limit_max   100 a ceiling on what one request may pull, so a
--                           client asking for a million does not get a million.
--
--    ON CONFLICT DO NOTHING, never DO UPDATE: re-running this migration must
--    not undo a number the President has since changed. These are seeds.
-- ---------------------------------------------------------------------------

insert into public.app_settings (key, value) values
  ('daily_darshan.max_images', '5'),
  ('daily_darshan.min_images', '1'),
  ('daily_darshan.max_note_chars', '2000'),
  ('daily_darshan.max_credit_chars', '120'),
  ('daily_darshan.max_backdate_days', '7'),
  ('daily_darshan.list_limit_max', '100')
on conflict (key) do nothing;

create or replace function public.daily_darshan_limit(p_key text)
returns integer
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_raw text;
  v_value integer;
begin
  select nullif(trim(app_settings.value), '') into v_raw
  from public.app_settings
  where app_settings.key = p_key;

  -- A missing or malformed dial raises rather than falling back to a default.
  -- 0055 §4 and 0076 §5 both make the point: a limit that quietly reverts to a
  -- number nobody chose is a bug nobody finds, and here it would be a bug that
  -- lets a gallery of forty pictures onto the Home screen.
  if v_raw is null then
    raise exception 'The Daily Darshan dial % is missing from app_settings.', p_key;
  end if;

  begin
    v_value := v_raw::integer;
  exception when others then
    raise exception 'The Daily Darshan dial % is %, which is not a whole number.', p_key, v_raw;
  end;

  if v_value < 0 then
    raise exception 'The Daily Darshan dial % is %, which is negative.', p_key, v_value;
  end if;

  return v_value;
end;
$$;

comment on function public.daily_darshan_limit(text) is
  'One Daily Darshan dial, read from app_settings. Missing or malformed raises rather than defaulting.';

revoke all on function public.daily_darshan_limit(text) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. Who may put a darshan up.
--
--    Community Head, Tech Admin, President — the three the temple named,
--    identified the way the rest of the app identifies them, by holding
--    services.manage_recurring. Section 0 proves that key names exactly those
--    three.
--
--    No new permission key is registered, for the reason 202608040048 §4 gives
--    about app.view_all and 202608040040 §3 repeats: a `darshan.post` would
--    have to be granted to those three roles and to nobody else, which is
--    precisely the set services.manage_recurring already describes, and a
--    second key is a second thing to forget to grant when the temple appoints
--    a new President. A fourth role given darshan rights would then silently
--    lack them.
-- ---------------------------------------------------------------------------

create or replace function public.may_post_daily_darshan()
returns boolean
language sql
stable
set search_path = ''
as $$
  select public.has_permission('services.manage_recurring')
$$;

comment on function public.may_post_daily_darshan() is
  'True for the Community Head, Tech Admin and President, the three who may publish the Daily Darshan.';

revoke all on function public.may_post_daily_darshan() from public, anon;
grant execute on function public.may_post_daily_darshan() to authenticated;

-- ---------------------------------------------------------------------------
-- 3. The day's darshan.
--
--    posted_by is `on delete set null` for 202608040040's reason, unchanged: a
--    Head may one day leave the congregation, and the pictures of the Deities
--    are the temple's, not theirs. The row survives and only the attribution
--    goes.
--
--    darshan_on is unique — see the header. It is the whole design.
-- ---------------------------------------------------------------------------

create table if not exists public.daily_darshan (
  id uuid primary key default gen_random_uuid(),
  darshan_on date not null,
  note text,
  posted_by uuid references public.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint daily_darshan_note_not_blank check (
    note is null or nullif(trim(note), '') is not null
  )
);

-- One darshan per day, promised by the database rather than by the RPC. If
-- publish_daily_darshan is bypassed entirely and a row is inserted straight
-- into the table, the second one for a date still fails.
create unique index if not exists daily_darshan_on_key
  on public.daily_darshan (darshan_on);

create index if not exists daily_darshan_posted_by_idx
  on public.daily_darshan (posted_by);

-- ---------------------------------------------------------------------------
-- 4. The pictures.
--
--    `on delete cascade`, unlike the poster: an image is not the temple's
--    record of anything once the darshan it belonged to is gone. It is one of
--    five pictures in one gallery, and a gallery with no darshan is not
--    something any screen can render.
--
--    deity and dressed_by are free text and not references. "Who dressed which
--    deity" is a caption the Head types, and the devotee named may not have an
--    account — the pujari who dresses Gaura Nitai every Thursday is not
--    necessarily on the app, and a foreign key would make Their darshan
--    unpublishable until he signed up. The temple asked to write it down, not
--    to link it.
--
--    (darshan_id, position) is unique because ordering by a position two rows
--    share is not an ordering. The gallery is a sequence the Head chose; two
--    pictures cannot both be third.
-- ---------------------------------------------------------------------------

create table if not exists public.daily_darshan_images (
  id uuid primary key default gen_random_uuid(),
  darshan_id uuid not null references public.daily_darshan(id) on delete cascade,
  image_url text not null,
  deity text,
  dressed_by text,
  "position" integer not null default 1,
  created_at timestamptz not null default now(),
  constraint daily_darshan_image_url_not_blank check (nullif(trim(image_url), '') is not null),
  constraint daily_darshan_image_position_sane check ("position" >= 0),
  constraint daily_darshan_image_deity_not_blank check (
    deity is null or nullif(trim(deity), '') is not null
  ),
  constraint daily_darshan_image_dressed_by_not_blank check (
    dressed_by is null or nullif(trim(dressed_by), '') is not null
  )
);

create unique index if not exists daily_darshan_images_position_key
  on public.daily_darshan_images (darshan_id, "position");

-- ---------------------------------------------------------------------------
-- 5. Reading.
--
--    Every signed-in devotee sees every darshan. There is no audience to pick
--    and no membership to check: the Deities are the temple's, and looking at
--    Them is what the congregation is for. Anon sees nothing — this is a
--    congregation's app, not a public gallery, and a devotee named as having
--    dressed the Deities has not agreed to appear on the open internet.
--
--    Every write goes through an RPC below, so nothing beyond reading is
--    granted on either table.
-- ---------------------------------------------------------------------------

alter table public.daily_darshan enable row level security;
alter table public.daily_darshan_images enable row level security;

drop policy if exists "Devotees read the daily darshan" on public.daily_darshan;
create policy "Devotees read the daily darshan"
  on public.daily_darshan for select to authenticated
  using (auth.uid() is not null);

drop policy if exists "Devotees read daily darshan images" on public.daily_darshan_images;
create policy "Devotees read daily darshan images"
  on public.daily_darshan_images for select to authenticated
  using (auth.uid() is not null);

revoke all on public.daily_darshan from anon, authenticated;
revoke all on public.daily_darshan_images from anon, authenticated;

grant select (id, darshan_on, note, posted_by, created_at, updated_at)
  on public.daily_darshan to authenticated;
grant select (id, darshan_id, image_url, deity, dressed_by, "position", created_at)
  on public.daily_darshan_images to authenticated;

-- ---------------------------------------------------------------------------
-- 6. The notification kind.
--
--    EXTENDED, never restated. 202608040053 wrote down at length what goes
--    wrong when a migration retypes this constraint by hand — every kind added
--    between that file and this one is silently outlawed, and it surfaces at
--    7am when a cron job raises — and 202608260076 §8 settled the shape of the
--    fix. The presently allowed kinds are read straight out of the catalogue,
--    'darshan_posted' is added, and the union is written back. A migration
--    adding a kind in parallel with this one therefore survives in whichever
--    order the two are applied.
--
--    The sanity floor is 0076's, for 0076's reason: the whole scheme rests on
--    one regexp, and a constraint rewritten into a shape where the quoted
--    literals are not the kinds would make that regexp return a short list and
--    turn this from an addition into a silent deletion.
-- ---------------------------------------------------------------------------

do $$
declare
  v_definition text;
  v_kinds text[];
  v_new text[] := array['darshan_posted'];
begin
  select pg_get_constraintdef(pg_constraint.oid) into v_definition
  from pg_constraint
  where conname = 'app_notifications_kind_check'
    and conrelid = 'public.app_notifications'::regclass;

  if v_definition is null then
    raise exception
      'The app_notifications kind constraint is missing; apply the earlier migrations first.';
  end if;

  select array_agg(distinct quoted[1]) into v_kinds
  from regexp_matches(v_definition, '''([a-z_]+)''', 'g') as quoted;

  if v_kinds is null or cardinality(v_kinds) < 30 then
    raise exception
      'Only % notification kinds could be read out of app_notifications_kind_check; refusing to rewrite it.',
      coalesce(cardinality(v_kinds), 0);
  end if;

  select array_agg(distinct kind order by kind) into v_kinds
  from unnest(v_kinds || v_new) as kind;

  execute 'alter table public.app_notifications drop constraint app_notifications_kind_check';
  execute format(
    'alter table public.app_notifications add constraint app_notifications_kind_check check (kind in (%s))',
    (select string_agg(quote_literal(kind), ', ' order by kind) from unnest(v_kinds) as kind)
  );

  raise notice 'app_notifications now allows % kinds', cardinality(v_kinds);
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Putting the day's darshan up.
--
--    p_images is a jsonb array of
--      {"imageUrl": text, "deity": text|null, "dressedBy": text|null,
--       "position": int}
--    and every rule about it is enforced here, in the database, not in the
--    app. The app's own check is a courtesy to the Head who is typing; this is
--    the one that holds when the RPC is called from anywhere else.
--
--    On the same date twice: the row is kept and its contents replaced. See
--    the header. The images are deleted while their parent still stands, so
--    there is never a moment at which an image row points at nothing, and the
--    id every phone was notified with keeps resolving.
--
--    posted_by moves to whoever posted last. The note and every picture have
--    been replaced wholesale, so the attribution belongs to the devotee who
--    put up what is actually on the screen — attributing tonight's pictures to
--    this morning's Head would be writing down something untrue.
--
--    Storage: nothing is deleted from the bucket when a picture is replaced.
--    Nothing in this codebase deletes storage objects from SQL, the object
--    sits in the uploader's own folder in a bucket shared with direct
--    messages, and a definer function reaching into storage.objects to remove
--    a file another row may also point at is a worse failure than an orphaned
--    8MB photo. Announcements leaves its photo behind for the same reason.
-- ---------------------------------------------------------------------------

create or replace function public.publish_daily_darshan(
  p_darshan_on date,
  p_note text,
  p_images jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_today date := (now() at time zone 'America/Chicago')::date;
  v_min integer := public.daily_darshan_limit('daily_darshan.min_images');
  v_max integer := public.daily_darshan_limit('daily_darshan.max_images');
  v_max_note integer := public.daily_darshan_limit('daily_darshan.max_note_chars');
  v_max_credit integer := public.daily_darshan_limit('daily_darshan.max_credit_chars');
  v_backdate integer := public.daily_darshan_limit('daily_darshan.max_backdate_days');
  v_note text;
  v_count integer;
  v_darshan_id uuid;
  v_created boolean := false;
  v_poster_name text;
  v_image record;
  v_devotee record;
begin
  if auth.uid() is null then
    raise exception 'Sign in to post the Daily Darshan.';
  end if;

  if not public.may_post_daily_darshan() then
    raise exception 'Only a Community Head, Tech Admin, or the President can post the Daily Darshan.';
  end if;

  if p_darshan_on is null then
    raise exception 'Please say which day this darshan is for.';
  end if;

  -- Chicago, not UTC and not the caller's timezone. See the header.
  if p_darshan_on > v_today then
    raise exception 'The Daily Darshan cannot be posted for a day that has not happened yet.';
  end if;

  if p_darshan_on < v_today - v_backdate then
    raise exception 'The Daily Darshan can only be posted for the last % days.', v_backdate;
  end if;

  v_note := nullif(trim(coalesce(p_note, '')), '');
  if v_note is not null and length(v_note) > v_max_note then
    raise exception 'The darshan note is longer than % characters.', v_max_note;
  end if;

  if p_images is null or jsonb_typeof(p_images) <> 'array' then
    raise exception 'The darshan pictures must be given as a list.';
  end if;

  v_count := jsonb_array_length(p_images);

  -- At most five, at least one — server-side, which is the only side that
  -- counts. Both bounds are dials; neither is a literal here.
  if v_count < v_min then
    raise exception 'A darshan needs at least % picture(s).', v_min;
  end if;
  if v_count > v_max then
    raise exception 'A darshan can have at most % pictures; % were given.', v_max, v_count;
  end if;

  -- Everything about the pictures is checked before anything is written, so a
  -- bad fifth picture cannot leave a half-published darshan behind.
  for v_image in
    select
      nullif(trim(coalesce(entry.value ->> 'imageUrl', '')), '') as image_url,
      nullif(trim(coalesce(entry.value ->> 'deity', '')), '') as deity,
      nullif(trim(coalesce(entry.value ->> 'dressedBy', '')), '') as dressed_by,
      coalesce(
        nullif(trim(coalesce(entry.value ->> 'position', '')), '')::integer,
        entry.ordinality::integer
      ) as slot,
      entry.ordinality as nth
    from jsonb_array_elements(p_images) with ordinality as entry(value, ordinality)
  loop
    if v_image.image_url is null then
      raise exception 'Picture % has no photo.', v_image.nth;
    end if;

    -- A photo must have come out of the app's own storage. 202608040040 §6
    -- makes the argument: left open, this column is a way to have every
    -- devotee's phone fetch an arbitrary URL the moment the Home screen
    -- renders, which is a tracking pixel the temple did not agree to.
    if v_image.image_url !~ '^https://[a-z0-9.-]+/storage/v1/object/public/message-images/' then
      raise exception 'A darshan photo must be uploaded through the app.';
    end if;

    if v_image.slot < 0 then
      raise exception 'Picture % has a negative position.', v_image.nth;
    end if;

    if v_image.deity is not null and length(v_image.deity) > v_max_credit then
      raise exception 'A deity name is longer than % characters.', v_max_credit;
    end if;

    if v_image.dressed_by is not null and length(v_image.dressed_by) > v_max_credit then
      raise exception 'A "dressed by" name is longer than % characters.', v_max_credit;
    end if;
  end loop;

  -- Two pictures cannot both be third. Checked here so the Head is told what
  -- is wrong rather than being shown a unique-index violation.
  select count(*)::integer into v_count
  from (
    select distinct coalesce(
      nullif(trim(coalesce(entry.value ->> 'position', '')), '')::integer,
      entry.ordinality::integer
    ) as slot
    from jsonb_array_elements(p_images) with ordinality as entry(value, ordinality)
  ) as slots;

  if v_count <> jsonb_array_length(p_images) then
    raise exception 'Two darshan pictures were given the same position.';
  end if;

  -- The Postgres manual's upsert loop, and it is here for the race rather than
  -- for tidiness: two Heads posting the same date at the same instant both
  -- find no row, both insert, and the unique index refuses one of them. The
  -- loser catches that and amends instead, so exactly one of them notifies.
  loop
    update public.daily_darshan
    set note = v_note,
        posted_by = auth.uid(),
        updated_at = now()
    where daily_darshan.darshan_on = p_darshan_on
    returning daily_darshan.id into v_darshan_id;

    exit when found;

    begin
      insert into public.daily_darshan (darshan_on, note, posted_by)
      values (p_darshan_on, v_note, auth.uid())
      returning daily_darshan.id into v_darshan_id;
      v_created := true;
      exit;
    exception when unique_violation then
      -- Somebody else published this date between the update and the insert.
      -- Go round once more and amend theirs.
      null;
    end;
  end loop;

  -- The parent stays; only the pictures are replaced. Nothing is ever left
  -- pointing at a darshan that is not there.
  delete from public.daily_darshan_images
  where daily_darshan_images.darshan_id = v_darshan_id;

  insert into public.daily_darshan_images (
    darshan_id, image_url, deity, dressed_by, "position"
  )
  select
    v_darshan_id,
    nullif(trim(coalesce(entry.value ->> 'imageUrl', '')), ''),
    nullif(trim(coalesce(entry.value ->> 'deity', '')), ''),
    nullif(trim(coalesce(entry.value ->> 'dressedBy', '')), ''),
    coalesce(
      nullif(trim(coalesce(entry.value ->> 'position', '')), '')::integer,
      entry.ordinality::integer
    )
  from jsonb_array_elements(p_images) with ordinality as entry(value, ordinality);

  -- One notification per post, never one per picture, and only when the day's
  -- darshan is new. Amending Tuesday does not make "there is a darshan for
  -- Tuesday" true a second time, and a congregation buzzed twice for one
  -- gallery learns to turn the app's notifications off.
  if v_created then
    select users.name into v_poster_name from public.users where users.id = auth.uid();

    -- Everyone, because the Deities are everyone's. The poster is left out:
    -- they are looking at the pictures. Queued one at a time so that a single
    -- failure to reach one devotee cannot undo the darshan for the rest —
    -- queue_app_notification only writes a row, and the push itself is
    -- already fire-and-forget in deliver_app_notification.
    for v_devotee in
      select users.id from public.users where users.id <> auth.uid()
    loop
      perform public.queue_app_notification(
        v_devotee.id,
        'darshan_posted',
        'Daily Darshan',
        coalesce(v_poster_name, 'The temple') || ' posted today''s darshan.',
        jsonb_build_object('darshanId', v_darshan_id, 'darshanOn', p_darshan_on)
      );
    end loop;
  end if;

  return v_darshan_id;
end;
$$;

comment on function public.publish_daily_darshan(date, text, jsonb) is
  'Publishes or replaces one Chicago day''s darshan. Notifies the congregation only the first time that day is published.';

revoke all on function public.publish_daily_darshan(date, text, jsonb) from public, anon;
grant execute on function public.publish_daily_darshan(date, text, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- 8. Reading the darshan.
--
--    The pictures travel WITH the darshan, as a jsonb array ordered by
--    position and never null. A gallery is one request. The alternative — a
--    list of darshans and then a query per darshan for its images — is thirty
--    round trips on a phone on temple wifi to render one screen, and the app
--    would have to reassemble the ordering itself.
--
--    `[]` rather than null for a darshan with no pictures, which section 7
--    makes impossible to create but a hand-written row could still produce.
--    A client that has to write `(images ?? []).map(...)` will one day forget
--    the `?? []`.
--
--    Definer, so the visibility rule is decided in one place; can_delete
--    travels with the row because every card needs it to decide whether to
--    draw the button, and asking again per darshan would be absurd.
-- ---------------------------------------------------------------------------

create or replace function public.list_daily_darshan(p_limit integer default 30)
returns table (
  id uuid,
  darshan_on date,
  note text,
  posted_by uuid,
  posted_by_name text,
  posted_by_photo_url text,
  images jsonb,
  image_count integer,
  created_at timestamptz,
  updated_at timestamptz,
  can_delete boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    darshan.id,
    darshan.darshan_on,
    darshan.note,
    darshan.posted_by,
    poster.name,
    poster.photo_url,
    coalesce(gallery.gallery_images, '[]'::jsonb),
    coalesce(gallery.gallery_count, 0),
    darshan.created_at,
    darshan.updated_at,
    (darshan.posted_by = auth.uid() or public.may_post_daily_darshan())
  from public.daily_darshan darshan
  left join public.users poster on poster.id = darshan.posted_by
  left join lateral (
    select
      jsonb_agg(
        jsonb_build_object(
          'id', img.id,
          'imageUrl', img.image_url,
          'deity', img.deity,
          'dressedBy', img.dressed_by,
          'position', img."position"
        )
        order by img."position", img.created_at, img.id
      ) as gallery_images,
      count(*)::integer as gallery_count
    from public.daily_darshan_images img
    where img.darshan_id = darshan.id
  ) gallery on true
  where auth.uid() is not null
  order by darshan.darshan_on desc
  limit greatest(
    1,
    least(
      coalesce(p_limit, 30),
      public.daily_darshan_limit('daily_darshan.list_limit_max')
    )
  )
$$;

comment on function public.list_daily_darshan(integer) is
  'The most recent days'' darshans, newest first, each with its pictures as a jsonb array ordered by position.';

revoke all on function public.list_daily_darshan(integer) from public, anon;
grant execute on function public.list_daily_darshan(integer) to authenticated;

-- ---------------------------------------------------------------------------
-- 9. The Home card.
--
--    One row, the same row the list would put first, and deliberately not a
--    second query that could disagree with it. If the ordering or the shape or
--    the visibility rule ever changes, it changes in one place and this
--    follows.
-- ---------------------------------------------------------------------------

create or replace function public.latest_daily_darshan()
returns table (
  id uuid,
  darshan_on date,
  note text,
  posted_by uuid,
  posted_by_name text,
  posted_by_photo_url text,
  images jsonb,
  image_count integer,
  created_at timestamptz,
  updated_at timestamptz,
  can_delete boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select * from public.list_daily_darshan(1)
$$;

comment on function public.latest_daily_darshan() is
  'The most recent day''s darshan with its pictures, for the Home screen card. Exactly the first row of list_daily_darshan.';

revoke all on function public.latest_daily_darshan() from public, anon;
grant execute on function public.latest_daily_darshan() to authenticated;

-- ---------------------------------------------------------------------------
-- 10. Taking one down.
--
--     Two people may: whoever put it up, and any of the three who could have.
--     Announcements' answer, unchanged, and it matters here for the same
--     reason it matters there — after `on delete set null` has cleared the
--     poster, a darshan is nobody's to remove but a Community Head's.
--
--     The image ROWS go with it, by cascade. The image FILES stay in
--     message-images, for section 7's reason: nothing in this codebase deletes
--     storage objects from SQL, and a definer function reaching into
--     storage.objects to unlink a file that a direct message may also point at
--     would trade a harmless orphan for a broken conversation.
-- ---------------------------------------------------------------------------

create or replace function public.delete_daily_darshan(p_id uuid)
returns public.daily_darshan
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_target public.daily_darshan;
begin
  if auth.uid() is null then
    raise exception 'Sign in to remove a darshan.';
  end if;

  select * into v_target
  from public.daily_darshan
  where daily_darshan.id = p_id
  for update;

  if v_target.id is null then
    raise exception 'That darshan could not be found.';
  end if;

  if v_target.posted_by is distinct from auth.uid()
     and not public.may_post_daily_darshan()
  then
    raise exception 'You can remove your own darshan, or any darshan if you are a Community Head, Tech Admin, or the President.';
  end if;

  delete from public.daily_darshan where daily_darshan.id = v_target.id;

  return v_target;
end;
$$;

comment on function public.delete_daily_darshan(uuid) is
  'Removes one day''s darshan and, by cascade, its picture rows. The files stay in message-images.';

revoke all on function public.delete_daily_darshan(uuid) from public, anon;
grant execute on function public.delete_daily_darshan(uuid) to authenticated;

do $$
begin
  raise notice 'daily darshan applied';
end;
$$;
