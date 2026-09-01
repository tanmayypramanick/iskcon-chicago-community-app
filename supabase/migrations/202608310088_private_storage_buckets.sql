-- Devotees' faces, private message photos and the temple's newsletters leave
-- the open internet.
-- Requires 202608040011_devotee_photos.sql, 202608040032_messaging.sql,
-- 202608040045_newsletter.sql and 202608310082.
--
-- All three buckets were created `public = true`. A public bucket is served at
-- /storage/v1/object/public/... with no authentication at all, and — this is
-- the part that made the existing policies misleading — a public bucket
-- BYPASSES row level security on reads entirely. So:
--
--   * "Anyone signed in reads message images" (0032:417) and the equivalent on
--     newsletter-files (0045:102) were dead code. Every photograph sent inside
--     a private direct message, every care-board and announcement image, and
--     every newsletter PDF was fetchable by anybody holding the URL, signed in
--     or not, forever — including a devotee who has since left the
--     congregation, and including a photo whose sender had "deleted" it, since
--     delete_message only nulls image_url and never touches the object.
--   * devotee-photos additionally had no `to authenticated` at all until
--     202608310082, so the bucket could be enumerated.
--
-- The privacy screen tells devotees "Every community screen requires a signed
-- in account; there is no guest directory or public devotee profile." This is
-- what makes that true of the image bytes and not only of the screens.
--
-- 202608290078's own header said the quiet part: a devotee named as having
-- dressed the Deities "has not agreed to appear on the open internet".
--
-- WHAT IS STORED IS UNCHANGED, and that is deliberate. users.photo_url,
-- messages.image_url, daily_darshan_images.image_url and the newsletter rows
-- keep the public-URL-shaped string they already hold. It is no longer
-- fetchable, but it still names the bucket and the object path, which is all
-- the client needs to mint a signed URL — so there is no data migration, no
-- backfill, and publish_daily_darshan's `^https://.../object/public/
-- message-images/` shape check keeps working untouched. The client reads these
-- through src/lib/storageUrl.ts and renders them through <RemoteImage>.

update storage.buckets
set public = false
where id in ('devotee-photos', 'message-images', 'newsletter-files');

-- With the buckets private, these policies stop being decorative and start
-- being the thing that decides. Restated here so all three are visibly the
-- same rule rather than three different vintages.
drop policy if exists "Devotee photos are readable" on storage.objects;
create policy "Devotee photos are readable"
  on storage.objects for select
  to authenticated
  using (bucket_id = 'devotee-photos');

drop policy if exists "Anyone signed in reads message images" on storage.objects;
create policy "Anyone signed in reads message images"
  on storage.objects for select
  to authenticated
  using (bucket_id = 'message-images');

drop policy if exists "Anyone signed in reads newsletter files" on storage.objects;
create policy "Anyone signed in reads newsletter files"
  on storage.objects for select
  to authenticated
  using (bucket_id = 'newsletter-files');

-- ---------------------------------------------------------------------------
-- Proof, run at migration time.
-- ---------------------------------------------------------------------------
do $$
declare
  v_bucket record;
  v_roles text[];
begin
  for v_bucket in
    select id, public from storage.buckets
    where id in ('devotee-photos', 'message-images', 'newsletter-files')
  loop
    if v_bucket.public then
      raise exception
        'bucket % is still public; its objects are served without authentication',
        v_bucket.id;
    end if;
  end loop;

  if (select count(*) from storage.buckets
      where id in ('devotee-photos', 'message-images', 'newsletter-files')) <> 3
  then
    raise notice 'not all three buckets exist here; the ones present were made private';
  end if;

  -- Every read policy must name authenticated and must not be open to PUBLIC,
  -- because now that reads go through RLS these are load-bearing.
  for v_bucket in
    select polname, polroles::regrole[]::text[] as roles
    from pg_policy
    where polrelid = 'storage.objects'::regclass
      and polname in (
        'Devotee photos are readable',
        'Anyone signed in reads message images',
        'Anyone signed in reads newsletter files'
      )
  loop
    v_roles := v_bucket.roles;
    if not ('authenticated' = any(v_roles)) then
      raise exception 'policy "%" does not name authenticated: %',
        v_bucket.polname, v_roles;
    end if;
    if '-' = any(v_roles) or 'public' = any(v_roles) then
      raise exception 'policy "%" is open to PUBLIC', v_bucket.polname;
    end if;
  end loop;

  raise notice 'devotee photos, message images and newsletter files are behind sign-in';
end;
$$;
