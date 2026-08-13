-- Access-level foundation for ISKCON Chicago.
-- Apply this migration before connecting the Profile access-request UI to Supabase.

create extension if not exists pgcrypto;

create table if not exists public.roles (
  id uuid primary key default gen_random_uuid(),
  name text not null unique check (
    name in ('president', 'tech', 'core', 'volunteer', 'devotee')
  )
);

create table if not exists public.role_permissions (
  role_id uuid not null references public.roles(id) on delete cascade,
  permission_key text not null,
  primary key (role_id, permission_key)
);

insert into public.roles (name)
values
  ('president'),
  ('tech'),
  ('core'),
  ('volunteer'),
  ('devotee')
on conflict (name) do nothing;

with permissions(role_name, permission_key) as (
  values
    ('devotee', 'services.view_all'),
    ('devotee', 'services.participate'),
    ('devotee', 'services.self_log'),
    ('devotee', 'services.report_unavailable'),
    ('devotee', 'services.respond_to_offer'),

    ('volunteer', 'services.view_all'),
    ('volunteer', 'services.participate'),
    ('volunteer', 'services.self_log'),
    ('volunteer', 'services.report_unavailable'),
    ('volunteer', 'services.respond_to_offer'),
    ('volunteer', 'services.post_requirement'),
    ('volunteer', 'services.offer_assignment'),
    ('volunteer', 'services.resolve_coverage'),

    ('core', 'services.view_all'),
    ('core', 'services.participate'),
    ('core', 'services.self_log'),
    ('core', 'services.report_unavailable'),
    ('core', 'services.respond_to_offer'),
    ('core', 'services.post_requirement'),
    ('core', 'services.offer_assignment'),
    ('core', 'services.resolve_coverage'),
    ('core', 'services.manage_recurring'),

    ('tech', 'access.review_requests'),
    ('tech', 'app.view_all'),
    ('tech', 'services.view_all'),
    ('tech', 'services.participate'),
    ('tech', 'services.self_log'),
    ('tech', 'services.report_unavailable'),
    ('tech', 'services.respond_to_offer'),
    ('tech', 'services.post_requirement'),
    ('tech', 'services.offer_assignment'),
    ('tech', 'services.resolve_coverage'),
    ('tech', 'services.manage_recurring'),

    ('president', 'access.review_requests'),
    ('president', 'app.view_all'),
    ('president', 'services.view_all'),
    ('president', 'services.participate'),
    ('president', 'services.self_log'),
    ('president', 'services.report_unavailable'),
    ('president', 'services.respond_to_offer'),
    ('president', 'services.post_requirement'),
    ('president', 'services.offer_assignment'),
    ('president', 'services.resolve_coverage'),
    ('president', 'services.manage_recurring')
)
insert into public.role_permissions (role_id, permission_key)
select roles.id, permissions.permission_key
from permissions
join public.roles on roles.name = permissions.role_name
on conflict (role_id, permission_key) do nothing;

create table if not exists public.users (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null,
  phone text,
  email text not null,
  photo_url text,
  ashram_status text,
  role_id uuid not null references public.roles(id),
  joined_at timestamptz not null default now()
);

create table if not exists public.access_requests (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references public.users(id) on delete cascade,
  requested_role_id uuid not null references public.roles(id),
  status text not null default 'pending' check (
    status in ('pending', 'approved', 'denied')
  ),
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references public.users(id),
  constraint access_request_review_consistency check (
    (status = 'pending' and reviewed_at is null and reviewed_by is null)
    or
    (status in ('approved', 'denied') and reviewed_at is not null and reviewed_by is not null)
  )
);

create unique index if not exists one_pending_access_request_per_user
  on public.access_requests(requester_id)
  where status = 'pending';

create index if not exists access_requests_status_created_at_idx
  on public.access_requests(status, created_at desc);

create or replace function public.has_permission(requested_permission text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.users
    join public.role_permissions
      on role_permissions.role_id = users.role_id
    where users.id = auth.uid()
      and role_permissions.permission_key = requested_permission
  );
$$;

create or replace function public.can_request_access_role(
  requester uuid,
  requested_role uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case current_access_role.name
    when 'devotee' then requested_access_role.name in ('volunteer', 'core')
    when 'volunteer' then requested_access_role.name = 'core'
    else false
  end
  from public.users
  join public.roles as current_access_role
    on current_access_role.id = users.role_id
  cross join public.roles as requested_access_role
  where users.id = requester
    and requested_access_role.id = requested_role;
$$;

create or replace function public.create_access_request(requested_role_name text)
returns public.access_requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  requested_role public.roles;
  created_request public.access_requests;
begin
  if auth.uid() is null then
    raise exception 'Authentication is required.';
  end if;

  select * into requested_role
  from public.roles
  where name = requested_role_name;

  if requested_role.id is null
    or not public.can_request_access_role(auth.uid(), requested_role.id)
  then
    raise exception 'This access-level change is not allowed.';
  end if;

  insert into public.access_requests (requester_id, requested_role_id)
  values (auth.uid(), requested_role.id)
  returning * into created_request;

  return created_request;
exception
  when unique_violation then
    raise exception 'You already have a pending access request.';
end;
$$;

create or replace function public.review_access_request(
  access_request_id uuid,
  decision text
)
returns public.access_requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  pending_request public.access_requests;
  reviewed_request public.access_requests;
begin
  if not public.has_permission('access.review_requests') then
    raise exception 'Only the President or a Tech member can review access requests.';
  end if;

  if decision not in ('approved', 'denied') then
    raise exception 'Decision must be approved or denied.';
  end if;

  select * into pending_request
  from public.access_requests
  where id = access_request_id
  for update;

  if pending_request.id is null or pending_request.status <> 'pending' then
    raise exception 'This access request is no longer pending.';
  end if;

  if decision = 'approved' then
    update public.users
    set role_id = pending_request.requested_role_id
    where id = pending_request.requester_id;
  end if;

  update public.access_requests
  set
    status = decision,
    reviewed_at = now(),
    reviewed_by = auth.uid()
  where id = pending_request.id
  returning * into reviewed_request;

  return reviewed_request;
end;
$$;

create or replace function public.create_profile_for_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  devotee_role_id uuid;
begin
  select id into devotee_role_id
  from public.roles
  where name = 'devotee';

  insert into public.users (
    id,
    name,
    phone,
    email,
    photo_url,
    role_id,
    joined_at
  )
  values (
    new.id,
    coalesce(
      nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''),
      nullif(trim(new.raw_user_meta_data ->> 'name'), ''),
      nullif(split_part(coalesce(new.email, ''), '@', 1), ''),
      'Devotee'
    ),
    new.phone,
    coalesce(new.email, ''),
    nullif(new.raw_user_meta_data ->> 'avatar_url', ''),
    devotee_role_id,
    coalesce(new.created_at, now())
  )
  on conflict (id) do nothing;

  return new;
end;
$$;

drop trigger if exists create_profile_after_auth_signup on auth.users;
create trigger create_profile_after_auth_signup
  after insert on auth.users
  for each row execute function public.create_profile_for_new_auth_user();

insert into public.users (id, name, phone, email, photo_url, role_id, joined_at)
select
  auth_users.id,
  coalesce(
    nullif(trim(auth_users.raw_user_meta_data ->> 'full_name'), ''),
    nullif(trim(auth_users.raw_user_meta_data ->> 'name'), ''),
    nullif(split_part(coalesce(auth_users.email, ''), '@', 1), ''),
    'Devotee'
  ),
  auth_users.phone,
  coalesce(auth_users.email, ''),
  nullif(auth_users.raw_user_meta_data ->> 'avatar_url', ''),
  roles.id,
  coalesce(auth_users.created_at, now())
from auth.users as auth_users
cross join public.roles
where roles.name = 'devotee'
on conflict (id) do nothing;

alter table public.roles enable row level security;
alter table public.role_permissions enable row level security;
alter table public.users enable row level security;
alter table public.access_requests enable row level security;

create policy "Authenticated users can read roles"
  on public.roles for select
  to authenticated
  using (true);

create policy "Authenticated users can read role permissions"
  on public.role_permissions for select
  to authenticated
  using (true);

create policy "Users can read their profile and access reviewers can read profiles"
  on public.users for select
  to authenticated
  using (id = auth.uid() or public.has_permission('access.review_requests'));

create policy "Users can update their own non-access profile fields"
  on public.users for update
  to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

create policy "Users can read their requests and reviewers can read all requests"
  on public.access_requests for select
  to authenticated
  using (
    requester_id = auth.uid()
    or public.has_permission('access.review_requests')
  );

revoke all on public.roles from anon, authenticated;
revoke all on public.role_permissions from anon, authenticated;
revoke all on public.users from anon, authenticated;
revoke all on public.access_requests from anon, authenticated;

grant select on public.roles to authenticated;
grant select on public.role_permissions to authenticated;
grant select on public.users to authenticated;
grant update (name, phone, photo_url, ashram_status) on public.users to authenticated;
grant select on public.access_requests to authenticated;

revoke all on function public.has_permission(text) from public;
revoke all on function public.can_request_access_role(uuid, uuid) from public;
revoke all on function public.create_access_request(text) from public;
revoke all on function public.review_access_request(uuid, text) from public;

grant execute on function public.has_permission(text) to authenticated;
grant execute on function public.create_access_request(text) to authenticated;
grant execute on function public.review_access_request(uuid, text) to authenticated;
