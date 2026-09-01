-- No bucket in this project serves its objects without a signed-in devotee.
--
-- This is a standing invariant rather than a one-off check, because the way it
-- broke is easy to repeat: `public = true` on a Storage bucket is a single
-- word in an insert, it reads like "the app can read it", and its real meaning
-- is "Supabase serves every object at /object/public/... to anybody, and row
-- level security on reads is bypassed". Two of the three buckets carried a
-- careful `for select to authenticated` policy that did nothing at all for
-- exactly that reason.
--
-- What this pins:
--   1. Every bucket is private.
--   2. Every bucket a devotee reads through has a SELECT policy naming
--      authenticated, since with private buckets that policy is now the thing
--      that decides.
--   3. No storage policy is open to anon or to PUBLIC.

do $$
declare
  v_row record;
  v_roles text[];
begin
  -- 1. No public buckets, whatever they are called. Deliberately not a fixed
  --    list: a bucket added later must not be able to opt out of this by not
  --    being named here.
  for v_row in select id from storage.buckets where public loop
    raise exception
      'Storage bucket "%" is public: its objects are served with no authentication.',
      v_row.id;
  end loop;

  -- 2. Each bucket the app reads from must still be readable by a signed-in
  --    devotee, or the fix above would have simply broken every image.
  for v_row in
    select unnest(array[
      'devotee-photos', 'message-images', 'newsletter-files'
    ]) as bucket
  loop
    if not exists (select 1 from storage.buckets where id = v_row.bucket) then
      continue;
    end if;

    if not exists (
      select 1 from pg_policies
      where schemaname = 'storage'
        and tablename = 'objects'
        and cmd = 'SELECT'
        and 'authenticated' = any (roles)
        and qual like '%' || v_row.bucket || '%'
    ) then
      raise exception
        'Nothing lets a signed-in devotee read "%", so everything stored in it is unreachable.',
        v_row.bucket;
    end if;
  end loop;

  -- 3. Nothing on storage.objects is open to anon or to PUBLIC. A policy with
  --    no role binds to PUBLIC, which reads as harmless and is not: that is
  --    precisely how devotee-photos became enumerable.
  for v_row in
    select policyname, roles::text[] as roles
    from pg_policies
    where schemaname = 'storage' and tablename = 'objects'
  loop
    v_roles := v_row.roles;
    if 'anon' = any (v_roles) then
      raise exception 'Storage policy "%" is open to anon.', v_row.policyname;
    end if;
    if 'public' = any (v_roles) or '-' = any (v_roles) then
      raise exception
        'Storage policy "%" has no role, so it binds to PUBLIC and includes anon.',
        v_row.policyname;
    end if;
  end loop;

  raise notice 'every storage bucket is private and readable only by signed-in devotees';
end;
$$;
