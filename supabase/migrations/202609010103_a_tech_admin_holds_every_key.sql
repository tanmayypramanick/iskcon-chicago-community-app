-- A Tech Admin can grant or take back any access level, including their own.
-- Requires 202608040047_access_appointments.sql.
--
-- 202608040047 drew the ladder the app may climb and stopped it two rungs
-- short: appoint_access refuses any role but Volunteer and Community Head, and
-- both it and revoke_access refuse to touch a devotee who already holds
-- President or Tech Admin — "the President and Tech Admin access levels are set
-- outside the app". Out of band meant the Supabase SQL editor, and somebody
-- with the project keys.
--
-- That was the right rule while the two offices were the same office. They are
-- not. A temple that wants to hand the presidency to somebody new should not
-- need a database console to do it, and the person who keeps the app running
-- is exactly the person who should be able to. So the ladder now reaches the
-- top, and precisely one level may climb past Community Head:
--
--   Tech Admin        may appoint ANY level — President, Tech Admin,
--                     Community Head, Volunteer — to ANY devotee, and may take
--                     any of them back.
--
--   President         unchanged. Volunteer and Community Head, as before.
--   Community Head    unchanged. Volunteer and Community Head, and may only
--                     lower access they granted themselves.
--   Volunteer         unchanged. Nothing.
--   Devotee           unchanged. Nothing.
--
-- Note what this does NOT do: it does not give the President the new power.
-- The two offices held identical permissions until today and now they do not,
-- which is deliberate. Somebody has to be able to replace the President, and
-- it cannot be the President — an office that can only be left voluntarily is
-- not an office the temple controls. The Tech Admin is the one seat that
-- exists to hold the keys, so the keys live there.
--
-- The gate is a permission rather than a role name, like every other gate in
-- this schema, so `access.manage_any` is what the checks below ask about and
-- the roles table stays the only place that says who has it.
--
-- Three things stay exactly as they were, and each is load-bearing:
--
--   * Nobody changes their own access level, a Tech Admin included. A seat you
--     can promote yourself out of is not a seat anybody else can hold you to.
--   * A devotee still cannot REQUEST President or Tech Admin —
--     can_request_access_role has always answered false for both and is
--     untouched, so the only way to those levels is somebody appointing you.
--   * Every appointment and revocation is still written to
--     access_appointments, with a note, by whoever made it.

-- ---------------------------------------------------------------------------
-- 1. The permission, and the one role that holds it.
-- ---------------------------------------------------------------------------
insert into public.role_permissions (role_id, permission_key)
select roles.id, 'access.manage_any'
from public.roles
where roles.name = 'tech'
on conflict (role_id, permission_key) do nothing;

-- ---------------------------------------------------------------------------
-- 2. Asked once, in one place, so the two functions below cannot drift apart.
-- ---------------------------------------------------------------------------
create or replace function public.may_appoint_any_access()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is not null
     and public.has_permission('access.manage_any')
$$;

revoke all on function public.may_appoint_any_access() from public, anon;
grant execute on function public.may_appoint_any_access() to authenticated;

comment on function public.may_appoint_any_access() is
  'Whether the signed-in devotee may grant or take back every access level, President and Tech Admin included. True for the Tech Admin and nobody else.';

-- ---------------------------------------------------------------------------
-- 3. Appointing. Two guards change; nothing else in the function does.
--
--    The first widens what may be granted, but only for the level that holds
--    access.manage_any. The second stops treating a devotee who already holds
--    one of the two offices as untouchable — untouchable by everyone else, yes,
--    but not by the Tech Admin.
-- ---------------------------------------------------------------------------
create or replace function public.appoint_access(
  p_devotee_id uuid,
  p_role_name text,
  p_note text default null
)
returns public.access_appointments
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role public.roles;
  v_current_role_name text;
  v_devotee_name text;
  v_actor_name text;
  v_live public.access_appointments;
  v_grant public.access_appointments;
  v_label text;
  v_any boolean;
  v_coordinator record;
begin
  if auth.uid() is null then
    raise exception 'Sign in to change access levels.';
  end if;

  if not public.may_appoint_access() then
    raise exception 'Only a Community Head, the President or the Tech Admin can change access levels.';
  end if;

  if p_devotee_id is null then
    raise exception 'Choose a devotee to appoint.';
  end if;

  if p_devotee_id = auth.uid() then
    raise exception 'You cannot change your own access level.';
  end if;

  v_any := public.may_appoint_any_access();

  if p_role_name is null
     or p_role_name not in ('volunteer', 'core', 'president', 'tech')
  then
    raise exception 'That is not an access level this app can give.';
  end if;

  if p_role_name in ('president', 'tech') and not v_any then
    raise exception 'Only the Tech Admin can appoint the President or a Tech Admin.';
  end if;

  select * into v_role from public.roles where roles.name = p_role_name;
  if v_role.id is null then
    raise exception 'That is not an access level this app can give.';
  end if;

  select congregant.name, held.name
    into v_devotee_name, v_current_role_name
  from public.users congregant
  join public.roles held on held.id = congregant.role_id
  where congregant.id = p_devotee_id
  for update of congregant;

  if v_devotee_name is null then
    raise exception 'That devotee could not be found.';
  end if;

  -- Somebody already holding one of the two offices can only be moved by the
  -- Tech Admin. To everyone else they read exactly as they always did.
  if v_current_role_name in ('president', 'tech') and not v_any then
    raise exception 'The President and Tech Admin access levels are set outside the app.';
  end if;

  select * into v_live
  from public.access_appointments
  where access_appointments.devotee_id = p_devotee_id
    and access_appointments.revoked_at is null
  for update;

  -- Already exactly this. Hand back what is there.
  if v_live.id is not null
     and v_live.role_id = v_role.id
     and v_current_role_name = p_role_name
  then
    return v_live;
  end if;

  -- A Community Head — anybody who may appoint but may not review access —
  -- can raise somebody, and can lower only what they granted themselves.
  if not public.has_permission('access.review_requests')
     and public.access_level_rank(p_role_name)
         < public.access_level_rank(v_current_role_name)
     and (v_live.id is null or v_live.appointed_by is distinct from auth.uid())
  then
    raise exception 'A Community Head can only lower access they granted themselves.';
  end if;

  v_grant := public.record_access_appointment(
    p_devotee_id, v_role.id, auth.uid(), p_note, 'appointment', null
  );

  select users.name into v_actor_name from public.users where users.id = auth.uid();
  v_label := public.access_level_label(p_role_name);

  perform public.queue_app_notification(
    p_devotee_id, 'access_appointed', 'Your access level changed',
    coalesce(v_actor_name, 'A coordinator') || ' made you ' || v_label || '.',
    jsonb_build_object(
      'appointmentId', v_grant.id, 'devoteeId', p_devotee_id, 'roleName', p_role_name
    )
  );

  -- An access level changing is temple business, so the other coordinators are
  -- told who granted it rather than discovering it later. Same audience, same
  -- reasoning as review_access_request in 202608040031_access_approver.sql.
  for v_coordinator in
    select distinct users.id
    from public.users
    join public.role_permissions
      on role_permissions.role_id = users.role_id
     and role_permissions.permission_key = 'services.manage_recurring'
    where users.id <> auth.uid()
      and users.id <> p_devotee_id
  loop
    perform public.queue_app_notification(
      v_coordinator.id, 'access_appointed', 'An access level changed',
      coalesce(v_actor_name, 'A coordinator') || ' made '
        || coalesce(v_devotee_name, 'a devotee') || ' ' || v_label || '.',
      jsonb_build_object(
        'appointmentId', v_grant.id, 'devoteeId', p_devotee_id, 'roleName', p_role_name
      )
    );
  end loop;

  return v_grant;
end;
$$;

comment on function public.appoint_access(uuid, text, text) is
  'Gives a devotee an access level and writes the grant down. Volunteer and Community Head for any coordinator; President and Tech Admin as well for whoever holds access.manage_any. Never your own.';

-- ---------------------------------------------------------------------------
-- 4. Revoking. One guard changes, for the same reason and in the same shape.
-- ---------------------------------------------------------------------------
create or replace function public.revoke_access(
  p_devotee_id uuid,
  p_note text default null
)
returns public.access_appointments
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_current_role_name text;
  v_devotee_name text;
  v_actor_name text;
  v_devotee_role_id uuid;
  v_live public.access_appointments;
  v_ended public.access_appointments;
  v_coordinator record;
begin
  if auth.uid() is null then
    raise exception 'Sign in to change access levels.';
  end if;

  if not public.may_appoint_access() then
    raise exception 'Only a Community Head, the President or the Tech Admin can change access levels.';
  end if;

  if p_devotee_id is null then
    raise exception 'Choose a devotee.';
  end if;

  if p_devotee_id = auth.uid() then
    raise exception 'You cannot change your own access level.';
  end if;

  select congregant.name, held.name
    into v_devotee_name, v_current_role_name
  from public.users congregant
  join public.roles held on held.id = congregant.role_id
  where congregant.id = p_devotee_id
  for update of congregant;

  if v_devotee_name is null then
    raise exception 'That devotee could not be found.';
  end if;

  if v_current_role_name in ('president', 'tech')
     and not public.may_appoint_any_access()
  then
    raise exception 'The President and Tech Admin access levels are set outside the app.';
  end if;

  if v_current_role_name = 'devotee' then
    raise exception 'That devotee is already at the Devotee access level.';
  end if;

  select * into v_live
  from public.access_appointments
  where access_appointments.devotee_id = p_devotee_id
    and access_appointments.revoked_at is null
  for update;

  if not public.has_permission('access.review_requests')
     and (v_live.id is null or v_live.appointed_by is distinct from auth.uid())
  then
    raise exception 'A Community Head can only take back access they granted themselves.';
  end if;

  select roles.id into v_devotee_role_id from public.roles where roles.name = 'devotee';

  if v_live.id is not null then
    update public.access_appointments
    set revoked_at = now(),
        revoked_by = auth.uid(),
        revoke_reason = 'revoked',
        revoke_note = nullif(trim(coalesce(p_note, '')), '')
    where access_appointments.id = v_live.id
    returning * into v_ended;
  else
    -- Access with no grant behind it — an office set in the database before
    -- this app could reach it. The revocation is still written down rather
    -- than being the one access change the record cannot see.
    insert into public.access_appointments (
      devotee_id, role_id, appointed_by, source,
      revoked_at, revoked_by, revoke_reason, revoke_note
    )
    select
      p_devotee_id, congregant.role_id, null, 'backfill',
      now(), auth.uid(), 'revoked', nullif(trim(coalesce(p_note, '')), '')
    from public.users congregant
    where congregant.id = p_devotee_id
    returning * into v_ended;
  end if;

  update public.users
  set role_id = v_devotee_role_id
  where users.id = p_devotee_id;

  select users.name into v_actor_name from public.users where users.id = auth.uid();

  perform public.queue_app_notification(
    p_devotee_id, 'access_revoked', 'Your access level changed',
    coalesce(v_actor_name, 'A coordinator')
      || ' returned your access to Devotee.',
    jsonb_build_object(
      'appointmentId', v_ended.id, 'devoteeId', p_devotee_id, 'roleName', 'devotee'
    )
  );

  for v_coordinator in
    select distinct users.id
    from public.users
    join public.role_permissions
      on role_permissions.role_id = users.role_id
     and role_permissions.permission_key = 'services.manage_recurring'
    where users.id <> auth.uid()
      and users.id <> p_devotee_id
  loop
    perform public.queue_app_notification(
      v_coordinator.id, 'access_revoked', 'An access level changed',
      coalesce(v_actor_name, 'A coordinator') || ' returned '
        || coalesce(v_devotee_name, 'a devotee') || ' to Devotee.',
      jsonb_build_object(
        'appointmentId', v_ended.id, 'devoteeId', p_devotee_id, 'roleName', 'devotee'
      )
    );
  end loop;

  return v_ended;
end;
$$;

comment on function public.revoke_access(uuid, text) is
  'Returns a devotee to the Devotee access level and writes the revocation down. A Community Head may only take back what they granted; the President any coordinator; the Tech Admin anybody at all. Never your own.';

-- ---------------------------------------------------------------------------
-- 5. The Revoke button follows the same rule the server does.
--
--    can_revoke is computed per row so the screen never re-derives it. Without
--    this the President would be offered a Revoke button on a Tech Admin's row
--    — they hold access.review_requests — and the server would then refuse it.
--    A button that refuses is worse than a button that is not there.
-- ---------------------------------------------------------------------------
create or replace function public.list_access_appointments(
  p_devotee_id uuid default null
)
returns table (
  id uuid,
  devotee_id uuid,
  devotee_name text,
  devotee_photo_url text,
  role_name text,
  role_label text,
  appointed_by uuid,
  appointed_by_name text,
  appointed_at timestamptz,
  note text,
  revoked_by uuid,
  revoked_by_name text,
  revoked_at timestamptz,
  revoke_note text,
  revoke_reason text,
  source text,
  access_request_id uuid,
  is_active boolean,
  can_revoke boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    grants.id,
    grants.devotee_id,
    congregant.name,
    congregant.photo_url,
    granted.name,
    public.access_level_label(granted.name),
    grants.appointed_by,
    appointer.name,
    grants.appointed_at,
    grants.note,
    grants.revoked_by,
    revoker.name,
    grants.revoked_at,
    grants.revoke_note,
    grants.revoke_reason,
    grants.source,
    grants.access_request_id,
    grants.revoked_at is null,
    grants.revoked_at is null
      and grants.devotee_id <> auth.uid()
      and (
        public.has_permission('access.review_requests')
        or grants.appointed_by = auth.uid()
      )
      and (
        granted.name not in ('president', 'tech')
        or public.may_appoint_any_access()
      )
  from public.access_appointments grants
  join public.users congregant on congregant.id = grants.devotee_id
  join public.roles granted on granted.id = grants.role_id
  left join public.users appointer on appointer.id = grants.appointed_by
  left join public.users revoker on revoker.id = grants.revoked_by
  where public.may_appoint_access()
    and (p_devotee_id is null or grants.devotee_id = p_devotee_id)
  order by grants.appointed_at desc, grants.id
$$;

-- ---------------------------------------------------------------------------
-- Proof, run at migration time. Seeded and rolled back, never deleted.
-- ---------------------------------------------------------------------------
do $$
declare
  v_tech  uuid := '9a000000-0000-0000-0000-000000000001';
  v_dev   uuid := '9a000000-0000-0000-0000-000000000002';
  v_vol   uuid := '9a000000-0000-0000-0000-000000000003';
  v_core  uuid := '9a000000-0000-0000-0000-000000000004';
  v_pres  uuid := '9a000000-0000-0000-0000-000000000005';
  v_held text;
  v_refused boolean;
  v_message text;
begin
  begin
    -- Exactly one level may hold the new permission.
    if (select string_agg(roles.name, ',' order by roles.name)
        from public.role_permissions
        join public.roles on roles.id = role_permissions.role_id
        where role_permissions.permission_key = 'access.manage_any') <> 'tech'
    then
      raise exception 'access.manage_any is held by somebody other than the Tech Admin';
    end if;

    insert into auth.users (id, email, raw_user_meta_data) values
      (v_tech, 'ta-tech@example.test',  jsonb_build_object('name', 'The Tech Admin')),
      (v_dev,  'ta-dev@example.test',   jsonb_build_object('name', 'A Devotee')),
      (v_vol,  'ta-vol@example.test',   jsonb_build_object('name', 'A Volunteer')),
      (v_core, 'ta-core@example.test',  jsonb_build_object('name', 'A Community Head')),
      (v_pres, 'ta-pres@example.test',  jsonb_build_object('name', 'The President'));

    update public.users set role_id = (select id from public.roles where name = 'tech')
    where id = v_tech;
    update public.users set role_id = (select id from public.roles where name = 'volunteer')
    where id = v_vol;
    update public.users set role_id = (select id from public.roles where name = 'core')
    where id = v_core;
    update public.users set role_id = (select id from public.roles where name = 'president')
    where id = v_pres;

    -- 1. A Tech Admin appoints a Devotee the President.
    perform set_config('request.jwt.claim.sub', v_tech::text, true);
    if not public.may_appoint_any_access() then
      raise exception 'a Tech Admin does not hold access.manage_any';
    end if;
    perform public.appoint_access(v_dev, 'president', 'Handing over the office.');
    perform set_config('request.jwt.claim.sub', '', true);

    select roles.name into v_held
    from public.users join public.roles on roles.id = users.role_id
    where users.id = v_dev;
    if v_held <> 'president' then
      raise exception 'the devotee was not made President, they are %', v_held;
    end if;
    if not exists (
      select 1 from public.access_appointments grants
      join public.roles on roles.id = grants.role_id
      where grants.devotee_id = v_dev
        and grants.revoked_at is null
        and grants.appointed_by = v_tech
        and roles.name = 'president'
    ) then
      raise exception 'the appointment to President was not written down';
    end if;

    -- 2. A Volunteer trying the same is refused. They may not appoint at all.
    perform set_config('request.jwt.claim.sub', v_vol::text, true);
    v_refused := false;
    begin
      perform public.appoint_access(v_core, 'president', null);
    exception when others then
      v_refused := true; v_message := sqlerrm;
    end;
    perform set_config('request.jwt.claim.sub', '', true);
    if not v_refused then
      raise exception 'a Volunteer appointed somebody President';
    end if;
    if public.access_level_rank('president') <> 3 then
      raise exception 'the access ladder moved underneath this proof';
    end if;

    -- 3. A Community Head may appoint, but not to either office.
    perform set_config('request.jwt.claim.sub', v_core::text, true);
    if public.may_appoint_any_access() then
      raise exception 'a Community Head holds access.manage_any';
    end if;
    v_refused := false;
    begin
      perform public.appoint_access(v_vol, 'president', null);
    exception when others then
      v_refused := true;
    end;
    if not v_refused then
      raise exception 'a Community Head appointed somebody President';
    end if;
    v_refused := false;
    begin
      perform public.appoint_access(v_vol, 'tech', null);
    exception when others then
      v_refused := true;
    end;
    if not v_refused then
      raise exception 'a Community Head appointed somebody Tech Admin';
    end if;
    -- What they could always do, they still can.
    perform public.appoint_access(v_vol, 'core', 'Still allowed.');
    perform set_config('request.jwt.claim.sub', '', true);
    if (select roles.name from public.users join public.roles on roles.id = users.role_id
        where users.id = v_vol) <> 'core'
    then
      raise exception 'a Community Head lost the power to appoint a Community Head';
    end if;

    -- 4. The President may not touch either office either, in either direction.
    perform set_config('request.jwt.claim.sub', v_pres::text, true);
    v_refused := false;
    begin
      perform public.appoint_access(v_core, 'tech', null);
    exception when others then
      v_refused := true;
    end;
    if not v_refused then
      raise exception 'the President appointed a Tech Admin';
    end if;
    v_refused := false;
    begin
      perform public.revoke_access(v_dev, null);
    exception when others then
      v_refused := true;
    end;
    perform set_config('request.jwt.claim.sub', '', true);
    if not v_refused then
      raise exception 'the President revoked a President';
    end if;

    -- 5. The Tech Admin takes the presidency back again.
    perform set_config('request.jwt.claim.sub', v_tech::text, true);
    perform public.revoke_access(v_dev, 'Stepping down.');
    perform set_config('request.jwt.claim.sub', '', true);
    if (select roles.name from public.users join public.roles on roles.id = users.role_id
        where users.id = v_dev) <> 'devotee'
    then
      raise exception 'the President was not returned to Devotee';
    end if;

    -- 6. And still nobody, Tech Admin included, changes their own level.
    perform set_config('request.jwt.claim.sub', v_tech::text, true);
    v_refused := false;
    begin
      perform public.appoint_access(v_tech, 'president', null);
    exception when others then
      v_refused := true;
    end;
    perform set_config('request.jwt.claim.sub', '', true);
    if not v_refused then
      raise exception 'a Tech Admin promoted themselves';
    end if;

    raise exception 'ISKCON_PROOF_ROLLBACK';
  exception
    when others then
      if sqlerrm <> 'ISKCON_PROOF_ROLLBACK' then
        raise;
      end if;
  end;

  raise notice 'a Tech Admin can grant and take back every access level, and nobody else can';
end;
$$;
