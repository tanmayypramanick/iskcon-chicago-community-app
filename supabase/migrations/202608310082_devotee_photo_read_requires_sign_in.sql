-- Anonymous callers may no longer enumerate the devotee photo bucket.
-- Requires 202608040011_devotee_photos.sql.
--
-- 0011 created the read policy without a `to` clause:
--
--   create policy "Devotee photos are readable"
--     on storage.objects for select
--     using (bucket_id = 'devotee-photos');
--
-- A policy with no role binds to PUBLIC, which includes `anon`. Every other
-- bucket in this repo scopes its read (202608040032_messaging.sql:418 and
-- 202608040045_newsletter.sql:102 both say `for select to authenticated`);
-- this one was the exception, and it is the bucket holding devotees' faces.
--
-- The consequence was enumeration. The publishable key ships inside the app
-- binary, so anyone who reads the JS bundle could call
-- storage.from('devotee-photos').list() without signing in and receive one
-- folder per devotee — folder name being the user's uuid — and with it both a
-- directory of faces and an exact congregation headcount. The privacy screen
-- tells devotees "there is no guest directory or public devotee profile".
-- This is the half of that promise the database can keep today.
--
-- WHAT THIS DOES NOT FIX, stated plainly so it is not mistaken for done:
-- the bucket is still `public = true`, so an individual object is still
-- served without authentication at /storage/v1/object/public/... to anyone
-- holding the URL. Closing that means `public = false` plus signing URLs at
-- read time, which cannot be done in a migration alone: users.photo_url,
-- messages.image_url, the newsletter file rows and the darshan image rows all
-- persist the public URL, and a signed URL expires, so those columns have to
-- become object paths signed on read. That is a schema and client change and
-- is deliberately left for the temple to decide, exactly as 0011's own
-- PRIVACY NOTE framed it.

drop policy if exists "Devotee photos are readable" on storage.objects;
create policy "Devotee photos are readable"
  on storage.objects for select
  to authenticated
  using (bucket_id = 'devotee-photos');

-- ---------------------------------------------------------------------------
-- Proof, run at migration time.
-- ---------------------------------------------------------------------------
do $$
declare
  v_roles name[];
begin
  select polroles::regrole[] into v_roles
  from pg_policy
  where polname = 'Devotee photos are readable'
    and polrelid = 'storage.objects'::regclass;

  if v_roles is null then
    raise exception 'the devotee photo read policy is missing';
  end if;

  -- 0 is PUBLIC in pg_policy.polroles. Its presence is the defect.
  if 'public' = any(v_roles::text[]) or v_roles::text[] @> array['-'] then
    raise exception 'the devotee photo read policy is still open to PUBLIC';
  end if;

  if not ('authenticated' = any(v_roles::text[])) then
    raise exception 'the devotee photo read policy does not name authenticated: %', v_roles;
  end if;

  raise notice 'devotee photo reads require a signed-in devotee';
end;
$$;
