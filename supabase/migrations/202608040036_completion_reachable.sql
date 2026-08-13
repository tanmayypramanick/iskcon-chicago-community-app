-- A profile a devotee can actually finish.
--
-- 0033 added emergency contact and preferred language to the completion count,
-- but the edit screen has no inputs for them. So 100% was unreachable, and the
-- daily "complete your profile" reminder never stopped — including for a
-- devotee who had answered every question in front of them, and for anybody
-- who is simply not initiated.
--
-- Completion now counts only what the app actually asks for. When the edit
-- screen gains the newer fields, they belong back in this list — the rule is
-- that the count and the form must always agree.
-- Requires 202608040035_messaging_realtime.sql.

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
      -- Answering "not initiated" is a complete answer. A devotee who has not
      -- taken initiation must be able to reach 100%.
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

-- A reminder that cannot be acted on is just noise, so it stops once a devotee
-- has answered everything the app asks.
create or replace function public.remind_incomplete_profiles()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  devotee record;
  sent integer := 0;
begin
  for devotee in
    select users.id, users.name, public.profile_completion(users.id) as completion
    from public.users
    where public.profile_completion(users.id) < 100
      and not exists (
        select 1 from public.app_notifications recent
        where recent.user_id = users.id
          and recent.kind = 'profile_incomplete'
          and recent.created_at > now() - interval '20 hours'
      )
  loop
    perform public.queue_app_notification(
      devotee.id, 'profile_incomplete', 'Help the temple know you',
      'Your profile is ' || devotee.completion
        || '% complete. Adding the rest helps us serve you better and welcome you properly.',
      jsonb_build_object('openProfileDetails', true)
    );
    sent := sent + 1;
  end loop;
  return sent;
end;
$$;

revoke all on function public.remind_incomplete_profiles() from public, anon, authenticated;

do $$
begin
  raise notice 'completion made reachable';
end;
$$;
