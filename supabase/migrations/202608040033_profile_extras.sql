-- The fields a temple actually reaches for.
--
-- Beyond who somebody is, a congregation needs to know how to reach them in an
-- emergency, what they can and cannot eat or do, and which language they are
-- most comfortable in. These come up constantly when arranging seva and are
-- awkward to ask for twice.
-- Requires 202608040032_messaging.sql.

alter table public.users
  add column if not exists emergency_contact_name text,
  add column if not exists emergency_contact_phone text,
  add column if not exists dietary_notes text,
  add column if not exists health_notes text,
  add column if not exists preferred_language text,
  add column if not exists occupation text,
  add column if not exists joined_temple_on date;

comment on column public.users.health_notes is
  'Anything that affects the seva a devotee can safely take on. Private to the devotee and authorised members.';
comment on column public.users.emergency_contact_phone is
  'Never shown to other devotees. Reached for only when somebody is unwell at the temple.';

-- Completion counts the practical ones. Health and dietary notes are
-- deliberately excluded: a devotee with nothing to declare should not be
-- shown an unfinished profile forever.
create or replace function public.profile_completion(p_user_id uuid)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  with person as (
    select * from public.users where id = p_user_id
  ), fields as (
    select unnest(array[
      nullif(trim(coalesce(person.name, '')), '') is not null,
      nullif(trim(coalesce(person.email, '')), '') is not null,
      nullif(trim(coalesce(person.phone, '')), '') is not null,
      person.date_of_birth is not null,
      nullif(trim(coalesce(person.birth_place, '')), '') is not null,
      nullif(trim(coalesce(person.address, '')), '') is not null,
      nullif(trim(coalesce(person.spiritual_mentor, '')), '') is not null,
      person.photo_url is not null,
      nullif(trim(coalesce(person.emergency_contact_name, '')), '') is not null,
      nullif(trim(coalesce(person.emergency_contact_phone, '')), '') is not null,
      nullif(trim(coalesce(person.preferred_language, '')), '') is not null,
      case
        when not person.is_initiated then true
        else person.initiation_date is not null
             and nullif(trim(coalesce(person.diksha_guru, '')), '') is not null
      end,
      case
        when not person.has_first_initiation then true
        else person.first_initiation_date is not null
             and nullif(trim(coalesce(person.first_diksha_guru, '')), '') is not null
      end,
      case
        when not person.has_second_initiation then true
        else person.second_initiation_date is not null
             and nullif(trim(coalesce(person.second_diksha_guru, '')), '') is not null
      end
    ]) as filled
    from person
  )
  select coalesce(
    (select round(100.0 * count(*) filter (where filled) / nullif(count(*), 0))::integer
     from fields),
    0
  )
$$;

revoke all on function public.profile_completion(uuid) from public, anon;
grant execute on function public.profile_completion(uuid) to authenticated;

create or replace function public.update_my_profile_extras(
  p_emergency_contact_name text,
  p_emergency_contact_phone text,
  p_dietary_notes text,
  p_health_notes text,
  p_preferred_language text,
  p_occupation text,
  p_joined_temple_on date
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
    emergency_contact_name = nullif(trim(coalesce(p_emergency_contact_name, '')), ''),
    emergency_contact_phone = nullif(trim(coalesce(p_emergency_contact_phone, '')), ''),
    dietary_notes = nullif(trim(coalesce(p_dietary_notes, '')), ''),
    health_notes = nullif(trim(coalesce(p_health_notes, '')), ''),
    preferred_language = nullif(trim(coalesce(p_preferred_language, '')), ''),
    occupation = nullif(trim(coalesce(p_occupation, '')), ''),
    joined_temple_on = p_joined_temple_on,
    profile_updated_at = now()
  where id = auth.uid()
  returning * into updated_person;

  if updated_person.id is null then
    raise exception 'Your profile could not be found.';
  end if;
  return updated_person;
end;
$$;

revoke all on function public.update_my_profile_extras(text, text, text, text, text, text, date) from public, anon;
grant execute on function public.update_my_profile_extras(text, text, text, text, text, text, date) to authenticated;

do $$
begin
  raise notice 'profile extras applied';
end;
$$;
