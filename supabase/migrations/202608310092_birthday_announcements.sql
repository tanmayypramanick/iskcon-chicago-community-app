-- A birthday announcement: the devotee's own photograph, and a frame around it.
-- Requires 202608040040_announcements.sql, 202608040052_announcement_reactions.sql
-- and 202608310089_birthday_announcement_carries_the_devotee.sql.
--
-- Three things, all of which the birthday flow ran into.
--
-- 1. THE PHOTOGRAPH WAS REFUSED. create_announcement checks that an image came
--    out of the app's own storage, which is right — left open, that column is
--    a way to make every devotee's phone fetch an arbitrary URL the moment the
--    notice renders, which is a tracking pixel the temple never agreed to. But
--    the check named ONE bucket, message-images, and a birthday announcement
--    carries the devotee's profile photograph, which lives in devotee-photos.
--    So posting one failed with "An announcement photo must be uploaded
--    through the app." The intent was never "one bucket"; it was "our
--    storage". Both buckets are ours, and both are private (202608310088).
--
-- 2. THE CARD COULD NOT KNOW. A birthday notice should not look like a notice
--    about the boiler. The card needs to be told, and inferring it from the
--    title would break the moment somebody edits the wording — which they are
--    invited to do. So the row carries `kind`.
--
-- 3. THE NOTIFICATION FAN-OUT WAS A LOOP. One INSERT per devotee, each firing
--    the deliver_app_notification trigger and its own net.http_post. The same
--    shape 202608310086 replaced for the Daily Darshan, for the same reason:
--    with a congregation of a couple of thousand the poster watches it spin
--    and then hit a statement timeout. notify_sanga_message_received
--    (202608120072) has always done it as one insert…select.

alter table public.announcements
  add column if not exists kind text not null default 'general';

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'announcement_kind_known'
      and conrelid = 'public.announcements'::regclass
  ) then
    alter table public.announcements
      add constraint announcement_kind_known
      check (kind in ('general', 'birthday'));
  end if;
end;
$$;

comment on column public.announcements.kind is
  'What sort of notice this is, so a card can dress it. "birthday" draws the greeting frame; "general" is an ordinary notice. Set when the notice is posted and never inferred from its wording, which a person is free to rewrite.';

-- The old seven-argument form is dropped rather than left beside the new one:
-- two overloads that differ only by a defaulted argument are ambiguous the
-- moment anybody calls the shorter one.
drop function if exists public.create_announcement(
  text, text, text, date, date, time, time
);

create or replace function public.create_announcement(
  p_title text,
  p_body text,
  p_image_url text default null,
  p_starts_on date default null,
  p_ends_on date default null,
  p_starts_at time default null,
  p_ends_at time default null,
  p_kind text default 'general'
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
  clean_kind text;
  created public.announcements;
  poster_name text;
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

  if p_starts_at is not null and p_ends_at is not null
     and p_starts_on is not distinct from p_ends_on
     and p_ends_at < p_starts_at
  then
    raise exception 'The announcement ends before it starts. Check the times.';
  end if;

  clean_kind := coalesce(nullif(trim(coalesce(p_kind, '')), ''), 'general');
  if clean_kind not in ('general', 'birthday') then
    raise exception 'An announcement is either general or a birthday greeting.';
  end if;

  -- A photo must have come out of the app's own storage. Both of the buckets
  -- the app writes images to are named: message-images, where a photo picked
  -- in the composer is uploaded, and devotee-photos, which is where a birthday
  -- greeting's picture already lives. Anything else is refused, which is the
  -- whole point of the check.
  clean_image := nullif(trim(coalesce(p_image_url, '')), '');
  if clean_image is not null
     and clean_image !~ '^https://[a-z0-9.-]+/storage/v1/object/public/(message-images|devotee-photos)/'
  then
    raise exception 'An announcement photo must be uploaded through the app.';
  end if;

  insert into public.announcements (
    title, body, image_url, posted_by, starts_on, ends_on, starts_at, ends_at,
    kind
  )
  values (
    clean_title, clean_body, clean_image, auth.uid(),
    p_starts_on, p_ends_on, p_starts_at, p_ends_at, clean_kind
  )
  returning * into created;

  select users.name into poster_name from public.users where users.id = auth.uid();

  -- Everyone, because that is what a noticeboard is. The poster is left out:
  -- they are standing at it. One statement rather than one per devotee.
  insert into public.app_notifications (user_id, kind, title, body, data)
  select
    users.id,
    'announcement_posted',
    'New announcement',
    coalesce(poster_name, 'The temple') || ' posted "' || created.title || '".',
    jsonb_build_object('announcementId', created.id)
  from public.users
  where users.id <> auth.uid();

  return created;
end;
$$;

revoke all on function public.create_announcement(
  text, text, text, date, date, time, time, text
) from public, anon;
grant execute on function public.create_announcement(
  text, text, text, date, date, time, time, text
) to authenticated;

-- The board, now carrying `kind` so a card can dress a greeting differently.
-- Dropped first: create or replace cannot change a function's result shape.
drop function if exists public.list_announcements();

create function public.list_announcements()
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
  can_delete boolean,
  like_count integer,
  comment_count integer,
  liked_by_me boolean,
  kind text
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
    ),
    (
      select count(*)::integer from public.announcement_likes
      where announcement_likes.announcement_id = announcements.id
    ),
    -- Removed comments are not comments. A card reading "3 comments" over a
    -- thread showing two and a tombstone is a card that looks broken.
    (
      select count(*)::integer from public.announcement_comments
      where announcement_comments.announcement_id = announcements.id
        and announcement_comments.deleted_at is null
    ),
    exists (
      select 1 from public.announcement_likes
      where announcement_likes.announcement_id = announcements.id
        and announcement_likes.devotee_id = auth.uid()
    ),
    announcements.kind
  from public.announcements
  left join public.users poster on poster.id = announcements.posted_by
  where auth.uid() is not null
    and public.announcement_is_live(announcements.ends_on, announcements.ends_at)
  order by announcements.created_at desc
$$;

revoke all on function public.list_announcements() from public, anon;
grant execute on function public.list_announcements() to authenticated;

-- ---------------------------------------------------------------------------
-- Proof, run at migration time. Seeded and rolled back, never deleted.
-- ---------------------------------------------------------------------------
do $$
declare
  v_pres uuid := '72000000-0000-0000-0000-000000000001';
  v_dev  uuid := '72000000-0000-0000-0000-000000000002';
  v_photo text;
  v_row public.announcements;
  v_refused boolean := false;
  v_kind text;
begin
  begin
    insert into auth.users (id, email, raw_user_meta_data) values
      (v_pres, 'ba-pres@example.test', jsonb_build_object('name', 'Birthday Frame President')),
      (v_dev,  'ba-dev@example.test',  jsonb_build_object('name', 'Ananda Das'));

    update public.users
    set role_id = (select id from public.roles where name = 'president')
    where id = v_pres;

    v_photo := 'https://example.supabase.co/storage/v1/object/public/devotee-photos/'
      || v_dev::text || '/face.jpg';

    perform set_config('request.jwt.claim.sub', v_pres::text, true);

    -- The bug this migration exists for: a devotee-photos URL must be accepted.
    v_row := public.create_announcement(
      'Happy birthday, Ananda Das!', 'Hare Kṛṣṇa!', v_photo,
      null, null, null, null, 'birthday'
    );

    if v_row.image_url is distinct from v_photo then
      raise exception 'the devotee''s photograph did not survive posting (%)', v_row.image_url;
    end if;
    if v_row.kind is distinct from 'birthday' then
      raise exception 'the announcement was stored as kind = %', v_row.kind;
    end if;

    -- And the card is told, through the function it actually reads.
    select listed.kind into v_kind
    from public.list_announcements() listed
    where listed.id = v_row.id;
    if v_kind is distinct from 'birthday' then
      raise exception 'list_announcements reports kind = %', v_kind;
    end if;

    -- An ordinary notice is still 'general'.
    v_row := public.create_announcement('Boiler', 'It is fixed.');
    if v_row.kind is distinct from 'general' then
      raise exception 'an ordinary notice was stored as kind = %', v_row.kind;
    end if;

    -- The guard still refuses a URL from outside the app's storage, which is
    -- the whole reason it exists.
    begin
      perform public.create_announcement(
        'Tracking pixel', 'Nope.', 'https://example.com/pixel.gif'
      );
    exception when others then
      v_refused := true;
    end;

    perform set_config('request.jwt.claim.sub', '', true);

    if not v_refused then
      raise exception 'an arbitrary external image URL was accepted';
    end if;

    raise exception 'ISKCON_PROOF_ROLLBACK';
  exception
    when others then
      if sqlerrm <> 'ISKCON_PROOF_ROLLBACK' then
        raise;
      end if;
  end;

  raise notice 'a birthday announcement keeps its photograph and knows what it is';
end;
$$;
