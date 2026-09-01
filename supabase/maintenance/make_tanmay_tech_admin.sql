-- ###########################################################################
-- #   M A K E   T A N M A Y   A   T E C H   A D M I N                       #
-- #                                                                         #
-- #   Moves tanmayp0612@gmail.com from President to Tech Admin.             #
-- #                                                                         #
-- #   This is live data, not schema, which is why it is here and not in     #
-- #   supabase/migrations. A migration runs on every database built from    #
-- #   this repo, and "make this particular person a Tech Admin" is true of  #
-- #   exactly one of them.                                                  #
-- #                                                                         #
-- #   Run it in the Supabase SQL Editor. One transaction: it happens or it  #
-- #   does not.                                                             #
-- ###########################################################################
--
-- WHAT HE KEEPS. Nothing. The two levels held identical permission sets
-- before today — all sixteen keys, checked row for row — and no function,
-- policy or trigger in this schema distinguishes 'president' from 'tech'. Every
-- gate is a permission, and both roles hold every one of them.
--
-- WHAT HE GAINS. `access.manage_any`, added by
-- 202609010103_a_tech_admin_holds_every_key.sql and held by the Tech Admin
-- alone: the power to appoint or revoke ANY access level for any devotee,
-- President and Tech Admin included. The President cannot do that.
--
-- SO RUN THAT MIGRATION FIRST. Without it 'tech' is merely 'president' by
-- another name, and this script would be a sideways move for nothing. The
-- check at the top refuses to run if it is missing.
--
-- ONE THING TO KNOW BEFORE RUNNING IT. This leaves the temple with no
-- President at all — he is the only account holding the office. Nothing breaks:
-- no permission and no screen depends on somebody being President. But if the
-- temple wants a President again, a Tech Admin appoints one from inside the
-- app, on Profile → Manage access. That is now the only way in, and there is
-- no way for him to appoint himself back: nobody changes their own access
-- level, by design.

begin;

do $$
declare
  v_id uuid;
  v_before text;
  v_after text;
begin
  -- The migration this depends on.
  if not exists (
    select 1 from public.role_permissions
    join public.roles on roles.id = role_permissions.role_id
    where role_permissions.permission_key = 'access.manage_any'
      and roles.name = 'tech'
  ) then
    raise exception
      'Apply 202609010103_a_tech_admin_holds_every_key.sql first — without it the Tech Admin gains nothing.';
  end if;

  select users.id, roles.name
    into v_id, v_before
  from public.users
  join public.roles on roles.id = users.role_id
  where users.email = 'tanmayp0612@gmail.com'
  for update of users;

  if v_id is null then
    raise exception 'No account with the address tanmayp0612@gmail.com.';
  end if;

  if v_before = 'tech' then
    raise notice 'Already a Tech Admin. Nothing to do.';
    return;
  end if;

  update public.users
  set role_id = (select roles.id from public.roles where roles.name = 'tech')
  where users.id = v_id;

  select roles.name into v_after
  from public.users
  join public.roles on roles.id = users.role_id
  where users.id = v_id;

  if v_after <> 'tech' then
    raise exception 'The role did not move: it is still %.', v_after;
  end if;

  -- Deliberately no row in public.access_appointments. That table records who
  -- inside the app gave somebody their access, and nobody did — this was run
  -- by hand against the database. A row with no appointer would read as an
  -- appointment that had one and lost it.
  raise notice 'tanmayp0612@gmail.com: % -> %', v_before, v_after;
end;
$$;

commit;

-- What the temple looks like afterwards.
select users.email, roles.name as access_level
from public.users
join public.roles on roles.id = users.role_id
order by users.email;
