-- Run after 202608020001_access_levels.sql in the Supabase SQL Editor.
-- These checks are read-only.

select name
from public.roles
order by case name
  when 'president' then 1
  when 'tech' then 2
  when 'core' then 3
  when 'volunteer' then 4
  when 'devotee' then 5
end;

select
  roles.name as role_name,
  array_agg(role_permissions.permission_key order by role_permissions.permission_key)
    as permissions
from public.roles
join public.role_permissions on role_permissions.role_id = roles.id
group by roles.name
order by roles.name;

select count(*) as auth_users_without_profile
from auth.users as auth_users
left join public.users as app_users on app_users.id = auth_users.id
where app_users.id is null;

select
  app_users.name,
  app_users.email,
  roles.name as role_name,
  app_users.joined_at
from public.users as app_users
join public.roles on roles.id = app_users.role_id
order by app_users.joined_at;
