-- Two different things a devotee may want, which are not the same thing.
--
--   LEAVING       They are done with the app. Nothing is erased. The temple
--                 keeps their record exactly as it stands, because a
--                 congregation roll is the temple's own record of a member and
--                 walking away from an app is not a request to be forgotten.
--                 They can come back and everything is where they left it.
--
--   BEING         They want the temple to stop holding who they are. Every
--   FORGOTTEN     personal detail goes — name, email, phone, address, the
--                 birth date, the photo, the health and dietary notes, the
--                 emergency contact, the family. The login stops working.
--
-- Apple requires the second to exist in-app for any app that lets you make an
-- account (5.1.1(v)), and requires it to actually delete rather than deactivate.
-- Relabelling somebody "A former devotee" while still holding their phone
-- number is deactivation wearing deletion's clothes.
--
-- WHAT SURVIVES BEING FORGOTTEN, AND WHY
--
-- The seva stays. So does the giving. Neither is personal data once the person
-- is gone from it: they are the temple's record of what was done and what was
-- received, the hours in a Seva Mala month have to still add up a year later,
-- and a US charity must keep its donation records for tax and audit whatever
-- any donor asks. What is removed is who did it.
--
-- This is why the row is emptied rather than deleted. service_assignments,
-- service_verifications, period_scores, sponsorship_bookings and a dozen more
-- all carry `references users(id) on delete cascade` — deleting the row would
-- take every hour they ever served with it, and silently change months that
-- were closed and counted. So public.users keeps an id and nothing else worth
-- knowing, and auth.users is scrubbed down to a stub that cannot sign in.
--
-- WHAT THIS CANNOT DO
--
-- The profile photograph is a file in Storage, and Storage refuses SQL. The
-- client deletes the object before it calls this, and photo_url is cleared
-- here either way so nothing in the app points at it.

alter table public.users
  add column if not exists left_at timestamptz,
  add column if not exists forgotten_at timestamptz;

comment on column public.users.left_at is
  'When the devotee stepped away from the app. Nothing is erased — the temple keeps their record, and signing in again clears this.';
comment on column public.users.forgotten_at is
  'When the devotee asked to be forgotten. Every personal detail was erased at this moment; what is left is an anonymous row holding the seva and giving records that cannot be detached from it.';

-- ---------------------------------------------------------------------------
-- Leaving. Reversible by definition: it only writes a date.
-- ---------------------------------------------------------------------------
create or replace function public.leave_the_community()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Sign in first.';
  end if;

  if exists (
    select 1 from public.users where id = auth.uid() and forgotten_at is not null
  ) then
    raise exception 'This account has already been erased.';
  end if;

  update public.users set left_at = now() where id = auth.uid();

  -- Stop the notifications following them out of the door.
  delete from public.device_push_tokens where user_id = auth.uid();
end;
$$;

revoke all on function public.leave_the_community() from public, anon;
grant execute on function public.leave_the_community() to authenticated;

comment on function public.leave_the_community() is
  'The devotee steps away from the app. Nothing is erased and nothing is lost; signing in again undoes it.';

-- ---------------------------------------------------------------------------
-- Being forgotten. Not reversible, and it says so.
-- ---------------------------------------------------------------------------
create or replace function public.forget_me()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
begin
  if me is null then
    raise exception 'Sign in first.';
  end if;

  if exists (select 1 from public.users where id = me and forgotten_at is not null) then
    raise exception 'This account has already been erased.';
  end if;

  -- The temple must not be able to lock itself out. If this devotee is the
  -- last person who can see and run everything, somebody else has to be given
  -- that first — otherwise the congregation is left with an app nobody can
  -- administer.
  if public.has_permission('app.view_all')
     and not exists (
       select 1
       from public.users other
       join public.role_permissions grants on grants.role_id = other.role_id
       where other.id <> me
         and other.forgotten_at is null
         and grants.permission_key = 'app.view_all'
     )
  then
    raise exception
      'You are the only person who can administer this app. Give somebody else that access first.';
  end if;

  -- 1. Everything that is only ever personal, and is nobody's record but theirs.
  delete from public.device_push_tokens where user_id = me;
  delete from public.temple_presence where user_id = me;
  delete from public.app_notifications where user_id = me;
  delete from public.messages where sender_id = me;
  delete from public.sanga_messages where sender_id = me;
  delete from public.sanga_reads where devotee_id = me;
  delete from public.care_replies where author_id = me;
  delete from public.care_posts where author_id = me;
  delete from public.feedback where devotee_id = me;
  delete from public.access_requests where requester_id = me;
  delete from public.newsletter_submissions where devotee_id = me;

  -- 2. The profile, emptied. Named column by column on purpose: a `select *`
  --    would quietly keep whatever column is added next.
  update public.users set
    name                    = 'A former devotee',
    phone                   = null,
    -- email is NOT NULL here, so it becomes the same opaque stub as in auth:
    -- built from the row's own id, which tells nobody anything.
    email                   = 'forgotten-' || me::text || '@deleted.invalid',
    photo_url               = null,
    ashram_status           = null,
    date_of_birth           = null,
    birth_place             = null,
    address                 = null,
    spiritual_mentor        = null,
    is_initiated            = false,
    initiation_date         = null,
    diksha_guru             = null,
    has_first_initiation    = false,
    first_initiation_date   = null,
    first_diksha_guru       = null,
    has_second_initiation   = false,
    second_initiation_date  = null,
    second_diksha_guru      = null,
    emergency_contact_name  = null,
    emergency_contact_phone = null,
    dietary_notes           = null,
    health_notes            = null,
    preferred_language      = null,
    occupation              = null,
    joined_temple_on        = null,
    gender                  = null,
    marital_status          = null,
    spouse_name             = null,
    children_count          = null,
    children                = '[]'::jsonb,
    chanting_rounds         = null,
    languages_spoken        = null,
    how_they_found_us       = null,
    can_offer_lift          = false,
    can_host_programs       = false,
    skills                  = null,
    temple_since_amount     = null,
    temple_since_unit       = null,
    leaderboard_visible     = false,
    profile_updated_at      = now(),
    left_at                 = null,
    forgotten_at            = now(),
    -- Whatever they were trusted with goes with them.
    role_id                 = (select id from public.roles where name = 'devotee')
  where id = me;

  -- 3. The login. The row has to stay — public.users hangs off it by a
  --    cascading key, and that key is holding every hour they ever served — so
  --    it is scrubbed to a stub instead: no name, no address to reach them at,
  --    no way in, and their real email freed so they could start again one day.
  --
  --    Assembled column by column from what auth.users actually has. Supabase
  --    owns that table and has changed its shape before; a fixed SET list
  --    would either miss a column that arrives later or fail outright against
  --    a database that does not have one yet. Missing a column here would mean
  --    silently leaving a personal detail behind, which is the one failure
  --    this function must not have.
  declare
    v_sets text[] := array[
      format('email = %L', 'forgotten-' || me::text || '@deleted.invalid')
    ];
    v_column text;
  begin
    foreach v_column in array array[
      'phone', 'phone_confirmed_at', 'email_confirmed_at', 'confirmed_at',
      'encrypted_password', 'confirmation_token', 'recovery_token',
      'email_change', 'email_change_token_new', 'email_change_token_current',
      'phone_change', 'phone_change_token', 'reauthentication_token',
      'invited_at', 'last_sign_in_at'
    ]
    loop
      if exists (
        select 1 from information_schema.columns
        where table_schema = 'auth' and table_name = 'users'
          and column_name = v_column
      ) then
        v_sets := array_append(v_sets, format('%I = null', v_column));
      end if;
    end loop;

    if exists (
      select 1 from information_schema.columns
      where table_schema = 'auth' and table_name = 'users'
        and column_name = 'raw_user_meta_data'
    ) then
      v_sets := array_append(v_sets, 'raw_user_meta_data = ''{}''::jsonb');
    end if;
    if exists (
      select 1 from information_schema.columns
      where table_schema = 'auth' and table_name = 'users'
        and column_name = 'raw_app_meta_data'
    ) then
      v_sets := array_append(v_sets, 'raw_app_meta_data = ''{}''::jsonb');
    end if;
    -- The door, locked. Without this the stub could still be signed into by a
    -- password reset on the freed address.
    if exists (
      select 1 from information_schema.columns
      where table_schema = 'auth' and table_name = 'users'
        and column_name = 'banned_until'
    ) then
      v_sets := array_append(v_sets, 'banned_until = ''infinity''::timestamptz');
    end if;

    execute format(
      'update auth.users set %s where id = %L',
      array_to_string(v_sets, ', '), me
    );
  end;

  -- Same reasoning: these are Supabase's tables, and the local verification
  -- harness stubs auth with only what the migrations need.
  -- Through EXECUTE, so plpgsql never parses a table that is not there. A
  -- plain DELETE inside an untaken IF is still resolved when the function is
  -- compiled, which is enough to fail.
  if to_regclass('auth.identities') is not null then
    execute 'delete from auth.identities where user_id = $1' using me;
  end if;
  if to_regclass('auth.sessions') is not null then
    execute 'delete from auth.sessions where user_id = $1' using me;
  end if;
end;
$$;

revoke all on function public.forget_me() from public, anon;
grant execute on function public.forget_me() to authenticated;

comment on function public.forget_me() is
  'Erases every personal detail the temple holds about the signed-in devotee and stops their login for good. The seva and giving records stay, with nobody''s name on them.';

-- ---------------------------------------------------------------------------
-- Proof, run at migration time. Seeded and rolled back, never deleted.
-- ---------------------------------------------------------------------------
do $$
declare
  v_head uuid := '9f000000-0000-4000-8000-000000000001';
  v_dev  uuid := '9f000000-0000-4000-8000-000000000002';
  v_type uuid;
  v_inst uuid;
  v_refused boolean;
  v_left integer;
  v_row public.users;
begin
  begin
    insert into auth.users (id, email, raw_user_meta_data) values
      (v_head, 'forget-head@example.test', jsonb_build_object('name', 'The President')),
      (v_dev,  'forget-dev@example.test',  jsonb_build_object('name', 'Leaving Devotee'));

    update public.users
    set role_id = (select id from public.roles where name = 'president')
    where id = v_head;

    update public.users set
      phone = '+1 555 0000', address = '1 Lunt Avenue', health_notes = 'None',
      emergency_contact_name = 'Somebody', date_of_birth = date '1990-01-01'
    where id = v_dev;

    -- An hour they served, which must outlive them.
    insert into public.service_types (name, category)
    values ('Forget Proof Seva', 'other') returning id into v_type;
    insert into public.service_instances
      (service_type_id, date, start_time, duration_minutes, slots_needed,
       participation_mode, posted_by, status)
    values (v_type, (now() at time zone 'America/Chicago')::date - 2, time '09:00',
            60, 1, 'open', v_head, 'completed')
    returning id into v_inst;
    insert into public.service_assignments
      (service_instance_id, devotee_id, assignment_method, assigned_by,
       status, verification, attendance)
    values (v_inst, v_dev, 'self_joined', v_dev, 'completed', 'self_report', 'served');

    -- Leaving erases nothing.
    perform set_config('request.jwt.claim.sub', v_dev::text, true);
    perform public.leave_the_community();
    perform set_config('request.jwt.claim.sub', '', true);

    select * into v_row from public.users where id = v_dev;
    if v_row.left_at is null then
      raise exception 'leaving did not record that they had left';
    end if;
    if v_row.phone is null or v_row.name = 'A former devotee' then
      raise exception 'leaving erased something, and it must not';
    end if;

    -- Being forgotten erases everything about the person.
    perform set_config('request.jwt.claim.sub', v_dev::text, true);
    perform public.forget_me();
    perform set_config('request.jwt.claim.sub', '', true);

    select * into v_row from public.users where id = v_dev;
    if v_row.name <> 'A former devotee' then
      raise exception 'the name survived being forgotten';
    end if;
    if v_row.phone is not null or v_row.address is not null
       or v_row.health_notes is not null or v_row.date_of_birth is not null
       or v_row.emergency_contact_name is not null
       or v_row.email not like 'forgotten-%@deleted.invalid'
    then
      raise exception 'a personal detail survived being forgotten';
    end if;
    if v_row.forgotten_at is null then
      raise exception 'being forgotten was not recorded';
    end if;
    if v_row.left_at is not null then
      raise exception 'being forgotten left them merely departed';
    end if;

    -- The login is gone.
    if to_regclass('auth.identities') is not null then
      execute 'select count(*) from auth.identities where user_id = $1'
        into v_left using v_dev;
      if v_left > 0 then
        raise exception 'the sign-in identity survived';
      end if;
    end if;
    if (select email from auth.users where id = v_dev) not like 'forgotten-%' then
      raise exception 'the real email survived in auth';
    end if;
    if (select raw_user_meta_data from auth.users where id = v_dev) <> '{}'::jsonb then
      raise exception 'the name survived in auth metadata';
    end if;

    -- And the hour they served is still counted, with nobody's name on it.
    if not exists (
      select 1 from public.service_assignments
      where devotee_id = v_dev and attendance = 'served'
    ) then
      raise exception 'being forgotten took their seva with it';
    end if;

    -- The last administrator cannot erase themselves.
    perform set_config('request.jwt.claim.sub', v_head::text, true);
    v_refused := false;
    begin
      perform public.forget_me();
    exception when others then
      v_refused := true;
    end;
    perform set_config('request.jwt.claim.sub', '', true);
    if not v_refused then
      raise exception 'the only administrator erased themselves and locked the temple out';
    end if;

    raise exception 'ISKCON_PROOF_ROLLBACK';
  exception
    when others then
      if sqlerrm <> 'ISKCON_PROOF_ROLLBACK' then
        raise;
      end if;
  end;

  raise notice 'a devotee can leave without losing anything, or be forgotten entirely';
end;
$$;
