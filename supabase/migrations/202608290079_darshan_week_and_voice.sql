-- The Daily Darshan holds one week, and speaks like a temple.
--
-- 202608290078_daily_darshan.sql built the feature and is not yet deployed, so
-- this file amends it rather than working around it. Two things the temple
-- asked for are missing from it:
--
--   "To save space, every week the posts will get removed automatically on
--    Monday, and a new Daily Darshan will begin."
--
--   "Notifications should be premium -- nothing like 'xyz posted'. Just
--    'Today's pictures on Daily Darshan are here', or 'See how Kisora Kisori
--    is looking today'."
--
-- Part one: what "Monday" means
-- -----------------------------
-- It means public.seva_mala_week_start(public.seva_mala_today()) -- the Monday
-- of the current America/Chicago date, by ISO day-of-week, which is the
-- definition 202608040055 §2 already gave this app and which every Seva Mala
-- week, leaderboard period and schedule read has used since. There is exactly
-- one week in this database and this is it. A second definition written here
-- would be a second thing to keep in step, and the first Sunday the two
-- disagreed the gallery would clear a day early for half the congregation.
--
-- Two consequences worth saying out loud, because both are choices:
--
--   * Sunday's darshan is last week's darshan. At Chicago midnight on Monday
--     it stops being shown, which is precisely "a new Daily Darshan will
--     begin". A temple that wants a softer edge turns daily_darshan.keep_weeks
--     up to 2 and keeps the week before as well; nothing in any function body
--     assumes the number is one.
--
--   * The floor is a Chicago DATE, so it moves with the wall clock and not
--     with UTC. On the March changeover the week turns over at 05:00 UTC and
--     on the November one at 06:00 UTC, and both of those are midnight in
--     Chicago. Nothing here has to know that; it falls out of computing the
--     date in the temple's timezone and doing integer date arithmetic on it.
--
-- The sweep runs HOURLY and is not gated on it being Monday. Deleting
-- everything older than this week's Monday is idempotent -- the second run
-- finds nothing -- and it is self-healing: a database that was down all Monday
-- still clears on Tuesday, where a job that insisted on the weekday would
-- leave last week's pictures up for another seven days. 0026, 0044, 0053 and
-- 0076 all guard the schedule on pg_cron being present; so does this, so that
-- every local and CI database applies the file and schedules nothing.
--
-- And the reads move with the sweep. list_daily_darshan and, through it,
-- latest_daily_darshan filter on the same floor the sweep deletes on, because
-- otherwise the Home card would show last week's pictures for the hour between
-- Chicago midnight and the tick that clears them. The visible week and the
-- stored week are one function, so they cannot drift.
--
-- Part one and a half: the photographs, honestly
-- ----------------------------------------------
-- The temple's stated reason for the weekly clear-out is to save space, and a
-- feature that deletes rows while leaving every 8MB photograph on disk has
-- saved nothing. 0078 §7 says the files stay and gives two reasons. The second
-- one -- that a file another row still points at must not be unlinked -- is
-- right and is answered below. The first one -- that nothing here deletes
-- storage objects from SQL -- is right about the code and needs restating as a
-- fact about Supabase, because it is stronger than 0078 made it sound:
--
--   Deleting a row from storage.objects DOES NOT delete the file.
--
-- storage.objects is metadata. The bytes live in the storage backend, and the
-- Storage API is the only thing that removes them, using that row to find
-- them. So a migration that deleted the row would not free a byte; it would
-- make the object unreachable by the API and therefore impossible to ever
-- delete. It would convert a recoverable orphan into a permanent one, while
-- appearing to tidy up. That is worse than doing nothing, and it is why this
-- file does not do it.
--
-- What SQL can honestly do, and does here, is keep an exact ledger of every
-- object that stopped being referenced and hand it to something that holds
-- Storage credentials:
--
--   * daily_darshan_reaped_images records the bucket and object path of every
--     darshan picture whose row is deleted -- by the weekly sweep, by
--     delete_daily_darshan, or by publish_daily_darshan replacing a day's
--     gallery. It is written by an AFTER DELETE trigger on the image rows
--     rather than by those three call sites, so a fourth way to delete an
--     image row cannot forget it.
--   * reap_darshan_images() settles any entry whose file another feature still
--     shows -- message-images is shared with direct messages, sanga posts,
--     announcements, care posts and newsletter covers -- by asking the
--     catalogue which columns can hold such a URL, so a table added later is
--     covered without this file being edited. 0078's objection is met by a
--     check rather than by giving up.
--   * What is left is handed to a delete endpoint over pg_net, exactly the way
--     202608040026 hands a notification to the push function: the URL and the
--     secret live in app_settings, and where they are unset nothing is posted,
--     nothing is marked done and nothing raises. The entries simply wait.
--
-- So: after this migration the temple's database frees its own rows every
-- Monday and knows, exactly, which files are now dead. To free the bytes it
-- needs one more thing that a migration cannot contain -- a service-role
-- caller that can talk to the Storage API. Deploy a function that accepts
--
--     POST <daily_darshan.reaper_url>
--     x-darshan-reaper-secret: <daily_darshan.reaper_secret>
--     {"bucket": "message-images", "paths": [...], "reapIds": [...]}
--
-- removes those paths with the storage client, and calls
-- mark_darshan_images_reaped(reapIds) for the ones it removed. Until then
-- pending_darshan_image_reaps() tells the Tech Admin how much is waiting, and
-- nothing is lost.
--
-- Part two: the voice
-- -------------------
-- 0078 sent the title 'Daily Darshan' and the body '<name> posted today's
-- darshan.' -- the two things the temple explicitly did not want. The poster is
-- gone from the wording entirely, and gone structurally: the function that
-- composes the words never reads public.users and has no way to name anybody.
--
-- The Deities are the subject. When the pictures name Them, Their names are
-- the title and the sentence; when several are named the phrase joins them as
-- prose and collapses past daily_darshan.max_named_deities to
-- "A, B and the other Deities", so a five-picture post does not turn the lock
-- screen into a column of a table. When nothing is named the subject is "the
-- Deities" and the title falls back to Daily Darshan, which is the name of the
-- thing rather than a category invented to fill the slot.
--
-- The variation is real and is not random. Five sentence shapes, chosen by the
-- darshan's own date -- (darshan_on - 1970-01-01) mod 5 -- so the wording is a
-- property of the post and not of the moment it was sent. The same post always
-- words itself identically, a retry cannot reword it, and because 5 and 7 are
-- coprime a given weekday works through all five shapes over five weeks rather
-- than saying the same thing every Tuesday forever. Nothing is drawn at send
-- time, so nothing has to be stored to keep it stable.
--
-- Requires 202608290078_daily_darshan.sql, 202608040055_seva_mala.sql
-- (seva_mala_week_start), 202608040048_donations.sql (is_backend_caller) and
-- 202608040026_push_delivery_and_reminders.sql (app_setting).

-- ---------------------------------------------------------------------------
-- 0. What this file assumes, asserted rather than trusted.
--
--    Everything below is written against 0078 and against the one definition
--    of a week this app has. Both would fail quietly rather than loudly: a
--    seva_mala_week_start that had been redefined to start on Sunday would
--    clear the gallery a day early and nobody would find out until a devotee
--    complained, and a missing 'darshan_posted' kind would only show when a
--    Head pressed Post.
-- ---------------------------------------------------------------------------

do $$
declare
  v_definition text;
  v_probe date := date '2026-08-29';  -- a Saturday
begin
  if to_regprocedure('public.publish_daily_darshan(date, text, jsonb)') is null then
    raise exception
      'publish_daily_darshan is missing; apply 202608290078_daily_darshan.sql first.';
  end if;

  if to_regprocedure('public.seva_mala_week_start(date)') is null then
    raise exception
      'seva_mala_week_start is missing; apply 202608040055_seva_mala.sql first.';
  end if;

  if to_regprocedure('public.is_backend_caller()') is null then
    raise exception
      'is_backend_caller is missing; apply 202608040048_donations.sql first.';
  end if;

  -- The week this file clears on is the week Seva Mala already counts in. If
  -- that ever stops meaning Monday, this file must be reconsidered rather than
  -- silently following it somewhere else.
  if public.seva_mala_week_start(v_probe) <> date '2026-08-24'
     or extract(isodow from public.seva_mala_week_start(v_probe)) <> 1
  then
    raise exception
      'seva_mala_week_start(%) is %, which is not the Monday of that week; Daily Darshan''s weekly clear-out depends on it being one.',
      v_probe, public.seva_mala_week_start(v_probe);
  end if;

  select pg_get_constraintdef(pg_constraint.oid) into v_definition
  from pg_constraint
  where conname = 'app_notifications_kind_check'
    and conrelid = 'public.app_notifications'::regclass;

  -- 0053's argument, unchanged: the kind list is NOT restated here, because
  -- this file adds no kind. It is only checked that 0078's is still allowed,
  -- so a later migration that retyped the list by hand fails while it is being
  -- applied rather than at the moment a Head presses Post.
  if v_definition is null or position('''darshan_posted''' in v_definition) = 0 then
    raise exception
      'The kind darshan_posted is not allowed by app_notifications_kind_check. Restate that list whole, including darshan_posted.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 1. The new dials.
--
--    Every window and threshold this file introduces is a row here, read
--    through 0078's daily_darshan_limit, which raises on a missing or
--    malformed value rather than falling back to a number nobody chose. No
--    function body below contains a bound.
--
--      keep_weeks          1   how many weeks the gallery holds, counting the
--                              current one. 1 is the temple's ask. 2 keeps
--                              last week too, and nothing has to change.
--      max_named_deities   3   how many Deities a notification names before it
--                              says "and the other Deities".
--      max_title_chars    60   a lock screen title.
--      max_body_chars    120   a lock screen line.
--      reap_batch         50   how many dead files one reaper tick hands off.
--      reap_retry_minutes 60   how long before an unconfirmed hand-off is
--                              tried again.
--
--    Deliberately NOT seeded: daily_darshan.reaper_url and
--    daily_darshan.reaper_secret. 202608040026 leaves push_function_url unset
--    for the same reason -- an endpoint is a property of a deployment, not of
--    a schema, and absent must mean off rather than pointing somewhere wrong.
--
--    ON CONFLICT DO NOTHING: re-running must not undo a number the President
--    has since changed.
-- ---------------------------------------------------------------------------

insert into public.app_settings (key, value) values
  ('daily_darshan.keep_weeks', '1'),
  ('daily_darshan.max_named_deities', '3'),
  ('daily_darshan.max_title_chars', '60'),
  ('daily_darshan.max_body_chars', '120'),
  ('daily_darshan.reap_batch', '50'),
  ('daily_darshan.reap_retry_minutes', '60')
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------
-- 2. Monday.
--
--    The one place in this file that decides what week it is. The sweep
--    deletes below this date and the reads start at it, so "what is shown" and
--    "what is kept" are the same sentence.
--
--    keep_weeks below 1 raises rather than being quietly treated as 1: a
--    gallery that holds no weeks is not something anybody meant to ask for,
--    and 0078 §1 already settled that a dial nobody chose is worse than an
--    error somebody reads.
-- ---------------------------------------------------------------------------

create or replace function public.daily_darshan_week_floor()
returns date
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_keep integer := public.daily_darshan_limit('daily_darshan.keep_weeks');
begin
  if v_keep < 1 then
    raise exception
      'daily_darshan.keep_weeks is %, but the gallery must hold at least the current week.', v_keep;
  end if;

  return public.seva_mala_week_start(public.seva_mala_today()) - 7 * (v_keep - 1);
end;
$$;

comment on function public.daily_darshan_week_floor() is
  'The first day the Daily Darshan gallery still holds: the Monday of the current Chicago week, less keep_weeks-1 further weeks. The sweep deletes below it and every read starts at it.';

revoke all on function public.daily_darshan_week_floor() from public, anon;
grant execute on function public.daily_darshan_week_floor() to authenticated;

-- ---------------------------------------------------------------------------
-- 3. The ledger of dead files.
--
--    One row per storage object that a darshan picture used to point at and
--    now nothing does. See the header for why this is a ledger and not a
--    delete: removing the storage.objects row would strand the bytes forever
--    instead of freeing them.
--
--    No foreign key to daily_darshan. The whole point of a row here is that
--    its darshan is gone; a cascade would delete the ledger entry at the exact
--    moment it became useful.
--
--    The partial unique index is what makes the ledger idempotent. A Head who
--    replaces Tuesday's gallery four times with the same first photograph
--    queues that object once, not four times, and the sweep run twice adds
--    nothing the second time.
-- ---------------------------------------------------------------------------

create table if not exists public.daily_darshan_reaped_images (
  id uuid primary key default gen_random_uuid(),
  bucket_id text not null,
  object_path text not null,
  image_url text not null,
  darshan_id uuid,
  image_id uuid,
  queued_at timestamptz not null default now(),
  attempts integer not null default 0,
  handed_off_at timestamptz,
  settled_at timestamptz,
  outcome text,
  last_error text,
  constraint daily_darshan_reap_outcome_known check (
    outcome is null or outcome in ('unlinked', 'still_in_use')
  ),
  constraint daily_darshan_reap_settled_has_outcome check (
    (settled_at is null) = (outcome is null)
  ),
  constraint daily_darshan_reap_path_not_blank check (
    nullif(trim(object_path), '') is not null
  )
);

comment on table public.daily_darshan_reaped_images is
  'Storage objects that Daily Darshan pictures used to point at and nothing does now. SQL cannot delete a file from a Supabase bucket, so it writes down exactly which ones are dead and hands them to a caller that can.';

create unique index if not exists daily_darshan_reap_pending_key
  on public.daily_darshan_reaped_images (bucket_id, object_path)
  where settled_at is null;

create index if not exists daily_darshan_reap_pending_idx
  on public.daily_darshan_reaped_images (queued_at)
  where settled_at is null;

alter table public.daily_darshan_reaped_images enable row level security;
revoke all on table public.daily_darshan_reaped_images from public, anon, authenticated;

-- The object path inside the bucket, taken out of the public URL 0078 already
-- insists every darshan photo has. A URL that is not one of ours returns null
-- and is never queued -- there is nothing in this bucket to unlink. The query
-- string goes, because a cache-busting ?t= is part of the link and not part of
-- the object's name.
create or replace function public.daily_darshan_object_path(p_url text)
returns text
language sql
immutable
set search_path = ''
as $$
  select nullif(
    (regexp_match(
      split_part(coalesce(p_url, ''), '?', 1),
      '^https://[a-z0-9.-]+/storage/v1/object/public/message-images/(.+)$'
    ))[1],
    ''
  )
$$;

comment on function public.daily_darshan_object_path(text) is
  'The object path inside message-images that a Daily Darshan photo URL points at, or null if the URL is not one of ours.';

revoke all on function public.daily_darshan_object_path(text) from public, anon, authenticated;

-- Does anything else in the database still show this file?
--
-- message-images is shared: direct messages, sanga posts, announcements, care
-- posts and newsletter covers all put pictures in it. Rather than listing
-- those tables -- a list that is wrong the first time a migration adds a
-- sixth -- the columns are read out of the catalogue. Every text column in
-- public whose name ends in image_url is a place such a URL can live, which is
-- a convention this schema has followed without exception since 0032, and the
-- ledger's own copy of the URL is excluded so an entry cannot keep itself
-- alive.
create or replace function public.daily_darshan_object_is_referenced(p_url text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_column record;
  v_hit boolean;
begin
  if p_url is null then
    return true;  -- nothing to reap, and certainly nothing to delete.
  end if;

  for v_column in
    select columns.table_name, columns.column_name
    from information_schema.columns
    join information_schema.tables
      on tables.table_schema = columns.table_schema
     and tables.table_name = columns.table_name
    where columns.table_schema = 'public'
      and tables.table_type = 'BASE TABLE'
      and columns.data_type in ('text', 'character varying')
      and columns.column_name like '%image\_url'
      and columns.table_name <> 'daily_darshan_reaped_images'
    order by columns.table_name, columns.column_name
  loop
    execute format(
      'select exists (select 1 from public.%I where %I = $1)',
      v_column.table_name, v_column.column_name
    ) into v_hit using p_url;

    if v_hit then
      return true;
    end if;
  end loop;

  return false;
end;
$$;

comment on function public.daily_darshan_object_is_referenced(text) is
  'True when any row anywhere in public still points at this image URL. The columns are read from the catalogue, so a table added later is covered without editing this function.';

revoke all on function public.daily_darshan_object_is_referenced(text) from public, anon, authenticated;

-- Written by a trigger rather than by the three functions that delete image
-- rows, so that a fourth way of deleting one cannot forget the file. The
-- cascade from daily_darshan fires it too, which is what makes the weekly
-- sweep and delete_daily_darshan need no code of their own.
--
-- Nothing is checked here about whether the file is still in use. At this
-- instant it usually is -- publish_daily_darshan deletes a day's images and
-- re-inserts them in the same statement -- so the question is asked later, by
-- the reaper, when the answer is stable.
create or replace function public.remember_reaped_darshan_image()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_path text := public.daily_darshan_object_path(old.image_url);
begin
  if v_path is null then
    return null;
  end if;

  insert into public.daily_darshan_reaped_images (
    bucket_id, object_path, image_url, darshan_id, image_id
  )
  values ('message-images', v_path, old.image_url, old.darshan_id, old.id)
  on conflict (bucket_id, object_path) where settled_at is null do nothing;

  return null;
end;
$$;

revoke all on function public.remember_reaped_darshan_image() from public, anon, authenticated;

drop trigger if exists remember_reaped_darshan_image on public.daily_darshan_images;
create trigger remember_reaped_darshan_image
after delete on public.daily_darshan_images
for each row execute function public.remember_reaped_darshan_image();

-- ---------------------------------------------------------------------------
-- 4. The sweep.
--
--    Everything before this week's Monday, gone -- rows by this statement,
--    picture rows by cascade, files onto the ledger by the trigger above.
--
--    Idempotent by construction rather than by a guard table: the second run
--    finds nothing older than the floor because the first one deleted it. That
--    is also what makes it safe to run by hand, safe to run from two
--    overlapping ticks, and safe to run at any hour of any day.
--
--    Backend only. A devotee who could call this could clear the gallery, and
--    0048 §5's argument applies unchanged: the grant should be enough, but the
--    guard is written anyway because a later `grant execute on all functions`
--    would undo the grant and not touch the guard.
-- ---------------------------------------------------------------------------

create or replace function public.sweep_daily_darshan()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_floor date;
  v_removed integer;
begin
  if not public.is_backend_caller() then
    raise exception 'Only the temple''s own server clears the Daily Darshan week.';
  end if;

  v_floor := public.daily_darshan_week_floor();

  delete from public.daily_darshan
  where daily_darshan.darshan_on < v_floor;

  get diagnostics v_removed = row_count;
  return v_removed;
end;
$$;

comment on function public.sweep_daily_darshan() is
  'Removes every darshan from before the current Chicago week, with its pictures. Idempotent: a second run finds nothing. Returns how many days were removed.';

revoke all on function public.sweep_daily_darshan() from public, anon, authenticated;
grant execute on function public.sweep_daily_darshan() to service_role;

-- ---------------------------------------------------------------------------
-- 5. Handing the dead files to something that can delete them.
--
--    Two jobs in one pass, because both need the same batch:
--
--      * anything the rest of the app still shows is settled as still_in_use
--        and never handed to anybody. This is 0078 §7's worry, answered.
--      * everything else is posted to the configured reaper.
--
--    The post is pg_net, fire and forget, exactly as 202608040026 delivers a
--    push: resolved by schema at call time so it works wherever the extension
--    was installed, wrapped so that a failure to hand off cannot roll back the
--    settling, and completely absent where the settings are not there. An
--    unconfirmed hand-off is simply tried again after reap_retry_minutes; the
--    row is only settled when the reaper says the file is gone.
-- ---------------------------------------------------------------------------

create or replace function public.reap_darshan_images(p_limit integer default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_batch integer;
  v_retry integer;
  v_endpoint text;
  v_secret text;
  v_poster text;
  v_entry record;
  v_ids uuid[] := '{}'::uuid[];
  v_paths jsonb := '[]'::jsonb;
begin
  if not public.is_backend_caller() then
    raise exception 'Only the temple''s own server may reap Daily Darshan images.';
  end if;

  v_batch := greatest(1, coalesce(nullif(p_limit, 0),
                                  public.daily_darshan_limit('daily_darshan.reap_batch')));
  v_retry := public.daily_darshan_limit('daily_darshan.reap_retry_minutes');

  for v_entry in
    select entries.id, entries.image_url, entries.object_path
    from public.daily_darshan_reaped_images entries
    where entries.settled_at is null
      and (
        entries.handed_off_at is null
        or entries.handed_off_at < now() - make_interval(mins => v_retry)
      )
    order by coalesce(entries.handed_off_at, entries.queued_at), entries.id
    limit v_batch
    for update skip locked
  loop
    if public.daily_darshan_object_is_referenced(v_entry.image_url) then
      update public.daily_darshan_reaped_images
      set settled_at = now(), outcome = 'still_in_use', last_error = null
      where daily_darshan_reaped_images.id = v_entry.id;
    else
      v_ids := v_ids || v_entry.id;
      v_paths := v_paths || to_jsonb(v_entry.object_path);
    end if;
  end loop;

  if cardinality(v_ids) = 0 then
    return 0;
  end if;

  v_endpoint := public.app_setting('daily_darshan.reaper_url');
  v_secret := public.app_setting('daily_darshan.reaper_secret');
  if v_endpoint is null or v_secret is null then
    -- No reaper deployed. The entries stay pending, which is the honest state:
    -- the files are dead and nothing here can remove them.
    return 0;
  end if;

  select pg_namespace.nspname into v_poster
  from pg_proc
  join pg_namespace on pg_namespace.oid = pg_proc.pronamespace
  where pg_proc.proname = 'http_post'
  limit 1;

  if v_poster is null then
    return 0;
  end if;

  begin
    execute format(
      'select %I.http_post(url := $1, headers := $2, body := $3, timeout_milliseconds := 5000)',
      v_poster
    )
    using
      v_endpoint,
      jsonb_build_object(
        'Content-Type', 'application/json',
        'x-darshan-reaper-secret', v_secret
      ),
      jsonb_build_object(
        'bucket', 'message-images',
        'paths', v_paths,
        'reapIds', to_jsonb(v_ids)
      );
  exception when others then
    update public.daily_darshan_reaped_images
    set attempts = daily_darshan_reaped_images.attempts + 1,
        last_error = left(sqlerrm, 500)
    where daily_darshan_reaped_images.id = any(v_ids);
    raise warning 'Daily Darshan image reaping could not be handed off: %', sqlerrm;
    return 0;
  end;

  update public.daily_darshan_reaped_images
  set handed_off_at = now(),
      attempts = daily_darshan_reaped_images.attempts + 1,
      last_error = null
  where daily_darshan_reaped_images.id = any(v_ids);

  return cardinality(v_ids);
end;
$$;

comment on function public.reap_darshan_images(integer) is
  'Settles dead Daily Darshan image entries whose file is still shown elsewhere, and hands the rest to the configured storage reaper. Returns how many were handed off; zero, harmlessly, where no reaper is configured.';

revoke all on function public.reap_darshan_images(integer) from public, anon, authenticated;
grant execute on function public.reap_darshan_images(integer) to service_role;

-- The reaper says which paths it actually removed. Only then is the entry
-- settled: a hand-off is a request, not a receipt, and pg_net cannot tell us
-- whether the file went.
create or replace function public.mark_darshan_images_reaped(p_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_settled integer;
begin
  if not public.is_backend_caller() then
    raise exception 'Only the temple''s own server may confirm a Daily Darshan image was removed.';
  end if;

  if p_ids is null or cardinality(p_ids) = 0 then
    return 0;
  end if;

  update public.daily_darshan_reaped_images
  set settled_at = now(), outcome = 'unlinked', last_error = null
  where daily_darshan_reaped_images.id = any(p_ids)
    and daily_darshan_reaped_images.settled_at is null;

  get diagnostics v_settled = row_count;
  return v_settled;
end;
$$;

comment on function public.mark_darshan_images_reaped(uuid[]) is
  'Marks Daily Darshan image entries as actually deleted from storage. Called by the reaper once the files are gone.';

revoke all on function public.mark_darshan_images_reaped(uuid[]) from public, anon, authenticated;
grant execute on function public.mark_darshan_images_reaped(uuid[]) to service_role;

-- What is waiting, for the two people who can do something about it. Empty for
-- everybody else rather than an error, for 0053 §1's reason: this backs a card
-- an ordinary devotee's app may reasonably ask for and simply must not draw.
create or replace function public.pending_darshan_image_reaps()
returns table (
  pending integer,
  handed_off integer,
  unlinked integer,
  still_in_use integer,
  oldest_pending_at timestamptz,
  reaper_configured boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  -- Returned early rather than filtered. An ungrouped aggregate query answers
  -- one row of zeros however hard its WHERE excludes -- and a HAVING with no
  -- aggregate in it is pushed into the WHERE by the planner, so that is the
  -- same row. A row of zeros would tell an ordinary devotee whether a reaper
  -- is configured. No row at all is the answer 0053 §1 settled on for a card
  -- a plain devotee's app may ask for and must not draw.
  if not public.has_permission('app.view_all') then
    return;
  end if;

  return query
  select
    count(*) filter (where entries.settled_at is null)::integer,
    count(*) filter (where entries.settled_at is null
                       and entries.handed_off_at is not null)::integer,
    count(*) filter (where entries.outcome = 'unlinked')::integer,
    count(*) filter (where entries.outcome = 'still_in_use')::integer,
    min(entries.queued_at) filter (where entries.settled_at is null),
    public.app_setting('daily_darshan.reaper_url') is not null
      and public.app_setting('daily_darshan.reaper_secret') is not null
  from public.daily_darshan_reaped_images entries;
end;
$$;

comment on function public.pending_darshan_image_reaps() is
  'How many dead Daily Darshan files are waiting to be removed from storage, for the President and the Tech Admin. Empty for everybody else.';

revoke all on function public.pending_darshan_image_reaps() from public, anon;
grant execute on function public.pending_darshan_image_reaps() to authenticated;

-- ---------------------------------------------------------------------------
-- 6. Whose darshan it is.
--
--    The distinct Deity names a day's pictures carry, in gallery order, first
--    spelling wins. Deduplicated case-insensitively because five photographs
--    of one altar are five rows with the same name in them, and a notification
--    that said "Kisora Kisori, Kisora Kisori and Kisora Kisori" is exactly the
--    database row the temple asked not to receive.
-- ---------------------------------------------------------------------------

create or replace function public.daily_darshan_deity_names(p_darshan_on date)
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(array_agg(named.deity order by named.first_position, named.deity), '{}'::text[])
  from (
    select
      (array_agg(trim(img.deity) order by img."position", img.created_at, img.id))[1] as deity,
      min(img."position") as first_position
    from public.daily_darshan_images img
    join public.daily_darshan darshan on darshan.id = img.darshan_id
    where darshan.darshan_on = p_darshan_on
      and nullif(trim(coalesce(img.deity, '')), '') is not null
    group by lower(trim(img.deity))
  ) as named
$$;

comment on function public.daily_darshan_deity_names(date) is
  'The distinct Deity names one day''s darshan pictures carry, in gallery order. Empty when none of them names anybody.';

revoke all on function public.daily_darshan_deity_names(date) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
--    And the names as one phrase.
--
--      none        the Deities
--      one         Kisora Kisori
--      two         Kisora Kisori and Gaura Nitai
--      three       Kisora Kisori, Gaura Nitai and Radha Govinda
--      four+       Kisora Kisori, Gaura Nitai and the other Deities
--
--    The cap is max_named_deities and the overflow is "and the other Deities"
--    rather than "and 3 more", because a count is a database row and the
--    Deities left out are not a remainder.
--
--    A cap below two is refused. "and the other Deities" with nothing in front
--    of it is not a phrase, and silently treating 1 as 2 would be a number
--    nobody chose.
-- ---------------------------------------------------------------------------

create or replace function public.daily_darshan_deity_phrase(p_names text[])
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_cap integer := public.daily_darshan_limit('daily_darshan.max_named_deities');
  v_names text[] := coalesce(p_names, '{}'::text[]);
  v_count integer := cardinality(v_names);
begin
  if v_cap < 2 then
    raise exception
      'daily_darshan.max_named_deities is %, but a notification must be able to name at least two Deities.', v_cap;
  end if;

  if v_count = 0 then
    return 'the Deities';
  end if;

  if v_count = 1 then
    return v_names[1];
  end if;

  if v_count <= v_cap then
    return array_to_string(v_names[1:v_count - 1], ', ') || ' and ' || v_names[v_count];
  end if;

  return array_to_string(v_names[1:v_cap - 1], ', ') || ' and the other Deities';
end;
$$;

comment on function public.daily_darshan_deity_phrase(text[]) is
  'The Deities of one darshan as a phrase a person would say. Collapses past max_named_deities to "and the other Deities", and reads "the Deities" when nothing is named.';

revoke all on function public.daily_darshan_deity_phrase(text[]) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 7. The words.
--
--    Five shapes. The one the temple wrote down is the first, kept verbatim.
--
--      0  See how Kisora Kisori is looking today.
--      1  Today's darshan of Kisora Kisori is here.
--      2  Come and take darshan of Kisora Kisori.
--      3  Today's pictures of Kisora Kisori are here.
--      4  Kisora Kisori - today's darshan from the temple.
--
--    Only shape 0 has a verb agreeing with the subject, and it is the one
--    place number is decided: one Deity is looking, two or more are looking,
--    and "the Deities" are looking. Every other shape is number-neutral on
--    purpose, because whether "Jagannath" or "Gaura Nitai" takes a singular
--    verb is not something a schema can work out and a notification that gets
--    it wrong about the Deities is worse than one that never risks it.
--
--    Which shape is a property of the DAY, not of the send: shape 4 for the
--    29th of August 2026 and shape 4 for it forever, so a retry, a
--    re-published gallery or a second look at the same function all give the
--    same sentence. Five shapes against a seven-day week means a devotee who
--    only ever opens the app on Sundays still gets all five.
--
--    The title is the subject and does not vary. A lock screen title that
--    changed daily would read as noise; what a devotee wants to see in bold is
--    who is on the other side of the notification. With nothing named, it is
--    "Daily Darshan" -- the name the temple gave the feature, which is the
--    only true thing left to say.
--
--    The poster is not here. Not omitted from the string: absent from the
--    function. Nothing below reads public.users, so there is no path by which
--    a devotee's name could reach a lock screen.
-- ---------------------------------------------------------------------------

create or replace function public.daily_darshan_notification_text(p_darshan_on date)
returns table (
  title text,
  body text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_names text[] := public.daily_darshan_deity_names(p_darshan_on);
  v_subject text := public.daily_darshan_deity_phrase(v_names);
  v_singular boolean := cardinality(v_names) = 1;
  v_shapes integer := 5;
  v_shape integer;
  v_max_title integer := public.daily_darshan_limit('daily_darshan.max_title_chars');
  v_max_body integer := public.daily_darshan_limit('daily_darshan.max_body_chars');
begin
  if p_darshan_on is null then
    raise exception 'A Daily Darshan notification needs the day it is about.';
  end if;

  -- Positive for every date either side of 1970, and stable forever.
  v_shape := ((p_darshan_on - date '1970-01-01') % v_shapes + v_shapes) % v_shapes;

  body := case v_shape
    when 0 then 'See how ' || v_subject
                || case when v_singular then ' is' else ' are' end
                || ' looking today.'
    when 1 then 'Today''s darshan of ' || v_subject || ' is here.'
    when 2 then 'Come and take darshan of ' || v_subject || '.'
    when 3 then 'Today''s pictures of ' || v_subject || ' are here.'
    else v_subject || ' - today''s darshan from the temple.'
  end;

  -- Shape 4 starts with the subject, which is "the Deities" when nothing is
  -- named. A sentence starts with a capital.
  body := upper(left(body, 1)) || substr(body, 2);

  title := case
    when cardinality(v_names) = 0 then 'Daily Darshan'
    else v_subject
  end;

  if length(title) > v_max_title then
    title := left(title, greatest(1, v_max_title - 3)) || '...';
  end if;
  if length(body) > v_max_body then
    body := left(body, greatest(1, v_max_body - 3)) || '...';
  end if;

  return next;
end;
$$;

comment on function public.daily_darshan_notification_text(date) is
  'The temple''s wording for one day''s Daily Darshan notification. Names the Deities and never the devotee who posted. The shape is chosen by the date, so the same day always words itself identically.';

revoke all on function public.daily_darshan_notification_text(date) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 8. Publishing, with the week and the voice.
--
--    Same signature, same shape, same upsert-on-race, same one-notification-
--    per-new-day rule. Two changes:
--
--      * A day before this week's Monday is refused. max_backdate_days still
--        applies and is still the outer bound, but publishing into a week the
--        gallery no longer holds would put up pictures that no read returns
--        and the next sweep deletes -- a Head pressing Post and nothing
--        happening. Better to say why.
--      * The notification is section 7's, and v_poster_name is gone.
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
  v_floor date := public.daily_darshan_week_floor();
  v_min integer := public.daily_darshan_limit('daily_darshan.min_images');
  v_max integer := public.daily_darshan_limit('daily_darshan.max_images');
  v_max_note integer := public.daily_darshan_limit('daily_darshan.max_note_chars');
  v_max_credit integer := public.daily_darshan_limit('daily_darshan.max_credit_chars');
  v_backdate integer := public.daily_darshan_limit('daily_darshan.max_backdate_days');
  v_note text;
  v_count integer;
  v_darshan_id uuid;
  v_created boolean := false;
  v_title text;
  v_body text;
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

  -- Chicago, not UTC and not the caller's timezone. See 0078's header.
  if p_darshan_on > v_today then
    raise exception 'The Daily Darshan cannot be posted for a day that has not happened yet.';
  end if;

  if p_darshan_on < v_today - v_backdate then
    raise exception 'The Daily Darshan can only be posted for the last % days.', v_backdate;
  end if;

  if p_darshan_on < v_floor then
    raise exception
      'The Daily Darshan gallery holds this week only, from % onwards. A darshan for % would be cleared straight away.',
      v_floor, p_darshan_on;
  end if;

  v_note := nullif(trim(coalesce(p_note, '')), '');
  if v_note is not null and length(v_note) > v_max_note then
    raise exception 'The darshan note is longer than % characters.', v_max_note;
  end if;

  if p_images is null or jsonb_typeof(p_images) <> 'array' then
    raise exception 'The darshan pictures must be given as a list.';
  end if;

  v_count := jsonb_array_length(p_images);

  if v_count < v_min then
    raise exception 'A darshan needs at least % picture(s).', v_min;
  end if;
  if v_count > v_max then
    raise exception 'A darshan can have at most % pictures; % were given.', v_max, v_count;
  end if;

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
      null;
    end;
  end loop;

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

  if v_created then
    -- Composed after the pictures are in, because the wording is about the
    -- Deities in them. Nothing here reads who is posting.
    select notice.title, notice.body into v_title, v_body
    from public.daily_darshan_notification_text(p_darshan_on) as notice;

    for v_devotee in
      select users.id from public.users where users.id <> auth.uid()
    loop
      perform public.queue_app_notification(
        v_devotee.id,
        'darshan_posted',
        v_title,
        v_body,
        jsonb_build_object('darshanId', v_darshan_id, 'darshanOn', p_darshan_on)
      );
    end loop;
  end if;

  return v_darshan_id;
end;
$$;

comment on function public.publish_daily_darshan(date, text, jsonb) is
  'Publishes or replaces one Chicago day''s darshan, within the week the gallery holds. Notifies the congregation once, in the temple''s own words, naming the Deities and never the poster.';

revoke all on function public.publish_daily_darshan(date, text, jsonb) from public, anon;
grant execute on function public.publish_daily_darshan(date, text, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- 9. Reading, this week only.
--
--    Identical to 0078's in every column and in its ordering; the only change
--    is the floor. It is here rather than only in the sweep because the sweep
--    runs on a tick and Chicago midnight does not wait for it: without this,
--    the Home card would show Sunday's pictures until the top of the hour on
--    Monday morning, which is the one moment the temple most wanted them gone.
--
--    latest_daily_darshan is deliberately not restated. It is
--    `select * from list_daily_darshan(1)` and follows this by construction --
--    0078 §9's whole point -- so the Home card cannot disagree with the list
--    about which week it is.
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
    and darshan.darshan_on >= public.daily_darshan_week_floor()
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
  'The current week''s darshans, newest first, each with its pictures as a jsonb array ordered by position. Nothing from before the week the gallery holds.';

revoke all on function public.list_daily_darshan(integer) from public, anon;
grant execute on function public.list_daily_darshan(integer) to authenticated;

-- ---------------------------------------------------------------------------
-- 10. On the clock.
--
--     Hourly, both of them, and guarded on pg_cron the way 0026, 0044, 0053
--     and 0076 guard theirs: on a database without the extension -- every
--     local and CI database this file is applied to -- nothing is scheduled
--     and nothing fails.
--
--     Hourly rather than "Mondays at three", because pg_cron's clock is UTC
--     and Chicago's Monday is not. A fixed UTC hour drifts by one across the
--     two changeovers and would need a dial and a gate to correct; an hourly
--     idempotent sweep needs neither and clears the gallery within an hour of
--     Chicago midnight in either half of the year. The other 167 runs a week
--     delete nothing and cost one index scan.
--
--     The reaper is offset to :20 so the two are never contending for the same
--     rows on the same tick.
-- ---------------------------------------------------------------------------

do $$
declare
  v_job record;
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    return;
  end if;

  for v_job in
    select * from (values
      ('sweep-daily-darshan', '0 * * * *', 'select public.sweep_daily_darshan();'),
      ('reap-daily-darshan-images', '20 * * * *', 'select public.reap_darshan_images();')
    ) as jobs(name, schedule, command)
  loop
    if exists (select 1 from cron.job where jobname = v_job.name) then
      perform cron.unschedule(v_job.name);
    end if;
    perform cron.schedule(v_job.name, v_job.schedule, v_job.command);
  end loop;
end;
$$;

do $$
begin
  raise notice 'daily darshan week and voice applied';
end;
$$;
