-- Devotee profile photos.
-- Requires 202608040010_rpc_execution_hardening.sql.
--
-- Faces live in a Storage bucket rather than the users table so the image is
-- served from the CDN and every avatar renders without an extra round trip.
-- users.photo_url holds the resulting public URL.
--
-- PRIVACY NOTE: the bucket is public-read, which is what makes avatars fast
-- and cacheable. Anyone holding an image URL can view it. Writes are still
-- restricted to the owner. If the temple would rather keep faces inside the
-- community, switch `public` to false below and have the client sign URLs
-- with createSignedUrls() before rendering.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'devotee-photos',
  'devotee-photos',
  true,
  5 * 1024 * 1024,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update
set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Object path is always `<user id>/<file name>`, so ownership is the first
-- path segment. A devotee may only write inside their own folder.
drop policy if exists "Devotee photos are readable" on storage.objects;
create policy "Devotee photos are readable"
  on storage.objects for select
  using (bucket_id = 'devotee-photos');

drop policy if exists "Devotees upload their own photo" on storage.objects;
create policy "Devotees upload their own photo"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'devotee-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "Devotees replace their own photo" on storage.objects;
create policy "Devotees replace their own photo"
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'devotee-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'devotee-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "Devotees remove their own photo" on storage.objects;
create policy "Devotees remove their own photo"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'devotee-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- users.photo_url is already in the authenticated UPDATE column grant from
-- 0001, but a devotee must not be able to point it at an arbitrary host and
-- use the directory as a tracking pixel or to serve unrelated content.
create or replace function public.enforce_devotee_photo_origin()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  allowed_prefix text;
begin
  if new.photo_url is null or new.photo_url is not distinct from old.photo_url then
    return new;
  end if;

  select 'https://' || split_part(
    split_part(current_setting('app.settings.supabase_url', true), '://', 2),
    '/', 1
  ) into allowed_prefix;

  -- Accept any Supabase Storage public object URL for this project, plus the
  -- Google avatar host used by OAuth sign-in.
  if new.photo_url ~ '^https://[a-z0-9-]+\.supabase\.co/storage/v1/object/public/devotee-photos/'
    or new.photo_url ~ '^https://lh3\.googleusercontent\.com/'
  then
    return new;
  end if;

  raise exception 'A profile photo must be uploaded through the app.';
end;
$$;

drop trigger if exists enforce_devotee_photo_origin on public.users;
create trigger enforce_devotee_photo_origin
before update of photo_url on public.users
for each row execute function public.enforce_devotee_photo_origin();

revoke all on function public.enforce_devotee_photo_origin() from public, anon, authenticated;

do $$
begin
  raise notice 'devotee photo storage applied';
end;
$$;
