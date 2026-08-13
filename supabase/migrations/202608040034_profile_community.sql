-- The rest of what a temple community actually keeps track of.
--
-- Gender is shown to everyone: devotees address one another as Prabhu or Mataji
-- and seva is sometimes arranged accordingly, so it is ordinary information
-- here rather than sensitive. Everything else in this migration stays private
-- to the devotee and to authorised members.
--
-- Age is deliberately NOT a column. It is derived from the date of birth, so
-- it can never drift out of date the way a stored number does.
-- Requires 202608040033_profile_extras.sql.

alter table public.users
  add column if not exists gender text,
  add column if not exists marital_status text,
  add column if not exists spouse_name text,
  add column if not exists children_count integer,
  add column if not exists chanting_rounds integer,
  add column if not exists languages_spoken text,
  add column if not exists how_they_found_us text,
  add column if not exists can_offer_lift boolean not null default false,
  add column if not exists can_host_programs boolean not null default false,
  add column if not exists skills text;

alter table public.users
  drop constraint if exists user_gender_check;
alter table public.users
  add constraint user_gender_check check (
    gender is null or gender in ('male', 'female', 'prefer_not_to_say')
  );

alter table public.users
  drop constraint if exists user_marital_status_check;
alter table public.users
  add constraint user_marital_status_check check (
    marital_status is null
    or marital_status in ('single', 'married', 'widowed', 'prefer_not_to_say')
  );

alter table public.users
  drop constraint if exists user_chanting_rounds_check;
alter table public.users
  add constraint user_chanting_rounds_check check (
    chanting_rounds is null or chanting_rounds between 0 and 200
  );

alter table public.users
  drop constraint if exists user_children_count_check;
alter table public.users
  add constraint user_children_count_check check (
    children_count is null or children_count between 0 and 30
  );

comment on column public.users.gender is
  'Shown to every devotee. Used for how people address one another and for seva that is arranged separately.';
comment on column public.users.chanting_rounds is
  'Daily japa rounds. A devotee''s own practice, never a requirement for seva.';
comment on column public.users.can_offer_lift is
  'Willing to give other devotees a lift to the temple. Practical, and often the difference between attending and not.';

create or replace function public.update_my_profile_community(
  p_gender text,
  p_marital_status text,
  p_spouse_name text,
  p_children_count integer,
  p_chanting_rounds integer,
  p_languages_spoken text,
  p_how_they_found_us text,
  p_can_offer_lift boolean,
  p_can_host_programs boolean,
  p_skills text
)
returns public.users
language plpgsql
security definer
set search_path = ''
as $$
declare
  updated_person public.users;
begin
  if auth.uid() is null then
    raise exception 'Sign in to update your details.';
  end if;

  update public.users set
    gender = nullif(trim(coalesce(p_gender, '')), ''),
    marital_status = nullif(trim(coalesce(p_marital_status, '')), ''),
    -- A spouse's name only means something alongside "married"; keeping it
    -- otherwise leaves a profile contradicting itself.
    spouse_name = case when p_marital_status = 'married'
      then nullif(trim(coalesce(p_spouse_name, '')), '') end,
    children_count = p_children_count,
    chanting_rounds = p_chanting_rounds,
    languages_spoken = nullif(trim(coalesce(p_languages_spoken, '')), ''),
    how_they_found_us = nullif(trim(coalesce(p_how_they_found_us, '')), ''),
    can_offer_lift = coalesce(p_can_offer_lift, false),
    can_host_programs = coalesce(p_can_host_programs, false),
    skills = nullif(trim(coalesce(p_skills, '')), ''),
    profile_updated_at = now()
  where id = auth.uid()
  returning * into updated_person;

  if updated_person.id is null then
    raise exception 'Your profile could not be found.';
  end if;
  return updated_person;
end;
$$;

revoke all on function public.update_my_profile_community(text, text, text, integer, integer, text, text, boolean, boolean, text) from public, anon;
grant execute on function public.update_my_profile_community(text, text, text, integer, integer, text, text, boolean, boolean, text) to authenticated;

-- Gender joins the handful of things one devotee may see of another; age comes
-- with it, derived rather than stored. The shape changes, so the old one is
-- dropped rather than replaced.
drop function if exists public.devotee_public_profile(uuid);

create or replace function public.devotee_public_profile(p_devotee_id uuid)
returns table (
  id uuid,
  name text,
  email text,
  photo_url text,
  role_name text,
  joined_at timestamptz,
  date_of_birth date,
  gender text,
  age integer,
  occupation text,
  phone text,
  birth_place text,
  address text,
  spiritual_mentor text,
  is_initiated boolean,
  diksha_guru text,
  can_see_everything boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    users.id, users.name, users.email, users.photo_url, roles.name,
    users.joined_at, users.date_of_birth, users.gender,
    case when users.date_of_birth is not null
      then extract(year from age(users.date_of_birth))::integer end,
    users.occupation,
    case when privileged then users.phone end,
    case when privileged then users.birth_place end,
    case when privileged then users.address end,
    case when privileged then users.spiritual_mentor end,
    case when privileged then users.is_initiated end,
    case when privileged then users.diksha_guru end,
    privileged
  from public.users
  join public.roles on roles.id = users.role_id
  cross join lateral (
    select (users.id = auth.uid() or public.has_permission('app.view_all')) as privileged
  ) as visibility
  where auth.uid() is not null and users.id = p_devotee_id
$$;

revoke all on function public.devotee_public_profile(uuid) from public, anon;
grant execute on function public.devotee_public_profile(uuid) to authenticated;

do $$
begin
  raise notice 'profile community fields applied';
end;
$$;
