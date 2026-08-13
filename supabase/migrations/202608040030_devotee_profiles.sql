-- Knowing the congregation.
--
-- The app knew a devotee's name, email and access level. A temple needs more
-- than that to be a community: when someone was born, where they came from,
-- who guides them spiritually, whether they are initiated and by whom. This
-- adds those details, a way to see how complete a profile is, a reason to
-- attach to an access request, and a gentle daily nudge for anyone who has not
-- filled theirs in.
-- Requires 202608040029_dashboard_columns.sql.

-- ---------------------------------------------------------------------------
-- 1. The details themselves.
--
--    Every field is nullable. A devotee is a member of the temple whether or
--    not they have told us their birthday, and nothing here gates access.
-- ---------------------------------------------------------------------------

alter table public.users
  add column if not exists date_of_birth date,
  add column if not exists birth_place text,
  add column if not exists address text,
  add column if not exists spiritual_mentor text,
  add column if not exists is_initiated boolean not null default false,
  add column if not exists initiation_date date,
  add column if not exists diksha_guru text,
  add column if not exists has_first_initiation boolean not null default false,
  add column if not exists first_initiation_date date,
  add column if not exists first_diksha_guru text,
  add column if not exists has_second_initiation boolean not null default false,
  add column if not exists second_initiation_date date,
  add column if not exists second_diksha_guru text,
  add column if not exists profile_updated_at timestamptz;

comment on column public.users.spiritual_mentor is
  'Who guides this devotee. Free text — a temple knows its own people better than a dropdown does.';

-- ---------------------------------------------------------------------------
-- 2. How complete a profile is.
--
--    One definition, in the database, so the devotee''s own screen and the
--    coordinator''s list can never disagree about what "80%" means.
--
--    Initiation details only count when they apply: a devotee who is not
--    initiated is not penalised for leaving a diksha guru blank.
-- ---------------------------------------------------------------------------

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
      -- Initiation counts as answered either way; only a "yes" asks for more.
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

-- ---------------------------------------------------------------------------
-- 3. A devotee updating their own details.
--
--    Name, phone and the spiritual details are theirs to set. Email is not
--    changed here: it belongs to the sign-in identity and goes through the
--    auth provider so the new address is proved before it takes effect.
-- ---------------------------------------------------------------------------

create or replace function public.update_my_profile(
  p_name text,
  p_phone text,
  p_date_of_birth date,
  p_birth_place text,
  p_address text,
  p_spiritual_mentor text,
  p_is_initiated boolean,
  p_initiation_date date,
  p_diksha_guru text,
  p_has_first_initiation boolean,
  p_first_initiation_date date,
  p_first_diksha_guru text,
  p_has_second_initiation boolean,
  p_second_initiation_date date,
  p_second_diksha_guru text
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
  if length(trim(coalesce(p_name, ''))) < 2 then
    raise exception 'Please enter your full name.';
  end if;
  if p_date_of_birth is not null and p_date_of_birth > current_date then
    raise exception 'A date of birth cannot be in the future.';
  end if;

  update public.users set
    name = trim(p_name),
    phone = nullif(trim(coalesce(p_phone, '')), ''),
    date_of_birth = p_date_of_birth,
    birth_place = nullif(trim(coalesce(p_birth_place, '')), ''),
    address = nullif(trim(coalesce(p_address, '')), ''),
    spiritual_mentor = nullif(trim(coalesce(p_spiritual_mentor, '')), ''),
    is_initiated = coalesce(p_is_initiated, false),
    -- Answering "no" clears whatever was entered under a previous "yes",
    -- so a profile can never carry contradictory details.
    initiation_date = case when coalesce(p_is_initiated, false) then p_initiation_date end,
    diksha_guru = case when coalesce(p_is_initiated, false)
      then nullif(trim(coalesce(p_diksha_guru, '')), '') end,
    has_first_initiation = coalesce(p_has_first_initiation, false),
    first_initiation_date = case when coalesce(p_has_first_initiation, false)
      then p_first_initiation_date end,
    first_diksha_guru = case when coalesce(p_has_first_initiation, false)
      then nullif(trim(coalesce(p_first_diksha_guru, '')), '') end,
    has_second_initiation = coalesce(p_has_second_initiation, false),
    second_initiation_date = case when coalesce(p_has_second_initiation, false)
      then p_second_initiation_date end,
    second_diksha_guru = case when coalesce(p_has_second_initiation, false)
      then nullif(trim(coalesce(p_second_diksha_guru, '')), '') end,
    profile_updated_at = now()
  where id = auth.uid()
  returning * into updated_person;

  if updated_person.id is null then
    raise exception 'Your profile could not be found.';
  end if;
  return updated_person;
end;
$$;

revoke all on function public.update_my_profile(text, text, date, text, text, text, boolean, date, text, boolean, date, text, boolean, date, text) from public, anon;
grant execute on function public.update_my_profile(text, text, date, text, text, text, boolean, date, text, boolean, date, text, boolean, date, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Access requests carry a reason.
--
--    "Why do you want this?" is the whole substance of the decision, and the
--    reviewer had nothing to go on before.
-- ---------------------------------------------------------------------------

alter table public.access_requests
  add column if not exists message text,
  add column if not exists review_note text;

-- The single-argument version is dropped rather than left alongside: with a
-- defaulted second parameter the two overloads are ambiguous, and every call
-- would fail with "function is not unique".
drop function if exists public.create_access_request(text);

create or replace function public.create_access_request(
  requested_role_name text,
  p_message text default null
)
returns public.access_requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  requested_role public.roles;
  created_request public.access_requests;
  requester_name text;
  reviewer record;
begin
  if auth.uid() is null then
    raise exception 'Authentication is required.';
  end if;
  if length(trim(coalesce(p_message, ''))) < 10 then
    raise exception 'Please say a little about why you would like this access.';
  end if;

  select * into requested_role from public.roles where name = requested_role_name;
  if requested_role.id is null
    or not public.can_request_access_role(auth.uid(), requested_role.id)
  then
    raise exception 'This access-level change is not allowed.';
  end if;

  insert into public.access_requests (requester_id, requested_role_id, message)
  values (auth.uid(), requested_role.id, trim(p_message))
  returning * into created_request;

  select name into requester_name from public.users where id = auth.uid();

  for reviewer in
    select distinct users.id
    from public.users
    join public.role_permissions
      on role_permissions.role_id = users.role_id
     and role_permissions.permission_key = 'access.review_requests'
    where users.id <> auth.uid()
  loop
    perform public.queue_app_notification(
      reviewer.id, 'access_request_submitted', 'A devotee asked for more access',
      coalesce(requester_name, 'A devotee') || ' asked to become '
        || public.access_level_label(requested_role.name) || '.',
      jsonb_build_object('accessRequestId', created_request.id)
    );
  end loop;

  return created_request;
exception
  when unique_violation then
    raise exception 'You already have a pending access request.';
end;
$$;

revoke all on function public.create_access_request(text, text) from public, anon;
grant execute on function public.create_access_request(text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Who reviewed it stays visible.
--
--    A devotee should be able to see that it was, say, the President who gave
--    them Volunteer access — and coordinators should see it too.
-- ---------------------------------------------------------------------------

create or replace function public.list_my_access_requests()
returns table (
  id uuid,
  requested_role text,
  status text,
  message text,
  review_note text,
  created_at timestamptz,
  reviewed_at timestamptz,
  reviewed_by_name text
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    requests.id,
    roles.name,
    requests.status,
    requests.message,
    requests.review_note,
    requests.created_at,
    requests.reviewed_at,
    reviewer.name
  from public.access_requests requests
  join public.roles on roles.id = requests.requested_role_id
  left join public.users reviewer on reviewer.id = requests.reviewed_by
  where requests.requester_id = auth.uid()
     or public.has_permission('access.review_requests')
  order by requests.created_at desc
$$;

revoke all on function public.list_my_access_requests() from public, anon;
grant execute on function public.list_my_access_requests() to authenticated;

drop function if exists public.review_access_request(uuid, text);

create or replace function public.review_access_request(
  access_request_id uuid,
  decision text,
  p_note text default null
)
returns public.access_requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  pending_request public.access_requests;
  reviewed_request public.access_requests;
  reviewer_name text;
  role_label text;
begin
  if not public.has_permission('access.review_requests') then
    raise exception 'Only the President or a Tech Admin can review access requests.';
  end if;
  if decision not in ('approved', 'denied') then
    raise exception 'Decision must be approved or denied.';
  end if;

  select * into pending_request from public.access_requests
  where id = access_request_id for update;
  if pending_request.id is null or pending_request.status <> 'pending' then
    raise exception 'This access request is no longer pending.';
  end if;

  if decision = 'approved' then
    update public.users
    set role_id = pending_request.requested_role_id
    where id = pending_request.requester_id;
  end if;

  update public.access_requests
  set status = decision,
      reviewed_at = now(),
      reviewed_by = auth.uid(),
      review_note = nullif(trim(coalesce(p_note, '')), '')
  where id = pending_request.id
  returning * into reviewed_request;

  select name into reviewer_name from public.users where id = auth.uid();
  select public.access_level_label(roles.name) into role_label
  from public.roles where roles.id = pending_request.requested_role_id;

  if pending_request.requester_id <> auth.uid() then
    perform public.queue_app_notification(
      pending_request.requester_id, 'access_request_reviewed',
      case when decision = 'approved'
        then 'Your access level changed'
        else 'Your access request was not approved' end,
      case when decision = 'approved'
        then coalesce(reviewer_name, 'A reviewer') || ' made you ' || role_label || '.'
        else coalesce(reviewer_name, 'A reviewer')
             || ' did not approve your request to become ' || role_label || '.'
      end,
      jsonb_build_object('accessRequestId', reviewed_request.id)
    );
  end if;

  return reviewed_request;
end;
$$;

revoke all on function public.review_access_request(uuid, text, text) from public, anon;
grant execute on function public.review_access_request(uuid, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. The congregation list, for the President and Tech Admin.
-- ---------------------------------------------------------------------------

create or replace function public.list_devotee_profiles()
returns table (
  id uuid,
  name text,
  email text,
  phone text,
  photo_url text,
  role_name text,
  joined_at timestamptz,
  date_of_birth date,
  birth_place text,
  address text,
  spiritual_mentor text,
  is_initiated boolean,
  initiation_date date,
  diksha_guru text,
  has_first_initiation boolean,
  first_initiation_date date,
  first_diksha_guru text,
  has_second_initiation boolean,
  second_initiation_date date,
  second_diksha_guru text,
  profile_updated_at timestamptz,
  completion integer
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    users.id, users.name, users.email, users.phone, users.photo_url,
    roles.name, users.joined_at, users.date_of_birth, users.birth_place,
    users.address, users.spiritual_mentor, users.is_initiated,
    users.initiation_date, users.diksha_guru, users.has_first_initiation,
    users.first_initiation_date, users.first_diksha_guru,
    users.has_second_initiation, users.second_initiation_date,
    users.second_diksha_guru, users.profile_updated_at,
    public.profile_completion(users.id)
  from public.users
  join public.roles on roles.id = users.role_id
  where public.has_permission('app.view_all')
  order by users.joined_at desc
$$;

revoke all on function public.list_devotee_profiles() from public, anon;
grant execute on function public.list_devotee_profiles() to authenticated;

-- ---------------------------------------------------------------------------
-- 7. A new devotee is worth knowing about, and worth welcoming.
-- ---------------------------------------------------------------------------

create or replace function public.announce_new_devotee()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  reviewer record;
begin
  for reviewer in
    select distinct users.id
    from public.users
    join public.role_permissions
      on role_permissions.role_id = users.role_id
     and role_permissions.permission_key = 'app.view_all'
    where users.id <> new.id
  loop
    perform public.queue_app_notification(
      reviewer.id, 'devotee_joined', 'A new devotee joined',
      new.name || ' created an account at ISKCON Chicago.',
      jsonb_build_object('devoteeId', new.id)
    );
  end loop;
  return new;
end;
$$;

revoke all on function public.announce_new_devotee() from public, anon, authenticated;

drop trigger if exists announce_new_devotee on public.users;
create trigger announce_new_devotee
after insert on public.users
for each row execute function public.announce_new_devotee();

-- ---------------------------------------------------------------------------
-- 8. A daily nudge until the profile is filled in.
--
--    Once a day at most, and only while it is still incomplete. It stops on
--    its own the moment a devotee finishes.
-- ---------------------------------------------------------------------------

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

alter table public.app_notifications
  drop constraint if exists app_notifications_kind_check;

alter table public.app_notifications
  add constraint app_notifications_kind_check check (
    kind in (
      'service_open', 'service_offer', 'service_recurring_offer',
      'service_offer_response', 'service_joined', 'service_left',
      'service_started', 'service_completed', 'service_cancelled',
      'service_deleted', 'service_coverage_needed',
      'service_coverage_resolved', 'recurring_interest_submitted',
      'recurring_interest_reviewed',
      'seva_verification_requested', 'seva_verification_reviewed',
      'weekly_offer_countered', 'weekly_offer_counter_reviewed',
      'access_request_submitted', 'access_request_reviewed',
      'devotee_joined', 'profile_incomplete',
      'remote'
    )
  );

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    if exists (select 1 from cron.job where jobname = 'remind-incomplete-profiles') then
      perform cron.unschedule('remind-incomplete-profiles');
    end if;
    -- Once a day, mid-morning Chicago time.
    perform cron.schedule(
      'remind-incomplete-profiles', '0 15 * * *',
      'select public.remind_incomplete_profiles();'
    );
  end if;
end;
$$;

do $$
begin
  raise notice 'devotee profiles applied';
end;
$$;
