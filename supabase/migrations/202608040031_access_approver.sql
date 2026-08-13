-- An access request is addressed to somebody.
--
-- A request that goes to "whoever is watching" is a request nobody owns. The
-- devotee now names the Community Head or President they are asking, the same
-- way they name the member who verifies their seva. That person is told
-- directly; the President and Tech Admin are told as well, because they can
-- act on anything and should not have to be asked.
--
-- Once approved, who approved it stays on the record — visible to the devotee
-- and to the coordinators, so nobody has to remember.
-- Requires 202608040030_devotee_profiles.sql.

alter table public.access_requests
  add column if not exists approver_id uuid references public.users(id);

comment on column public.access_requests.approver_id is
  'The Community Head or President the devotee addressed. Anyone with access.review_requests may still answer it.';

-- ---------------------------------------------------------------------------
-- 1. Who may be asked.
--
--    The same set that verifies seva: Community Head, Tech Admin, President.
-- ---------------------------------------------------------------------------

create or replace function public.list_access_approvers()
returns table (id uuid, name text, photo_url text, role_name text)
language sql
stable
security definer
set search_path = ''
as $$
  select users.id, users.name, users.photo_url, roles.name
  from public.users
  join public.roles on roles.id = users.role_id
  join public.role_permissions
    on role_permissions.role_id = users.role_id
   and role_permissions.permission_key = 'services.manage_recurring'
  where auth.uid() is not null
    and users.id <> auth.uid()
  order by users.name
$$;

revoke all on function public.list_access_approvers() from public, anon;
grant execute on function public.list_access_approvers() to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Asking a named person.
-- ---------------------------------------------------------------------------

drop function if exists public.create_access_request(text, text);

create or replace function public.create_access_request(
  requested_role_name text,
  p_message text default null,
  p_approver_id uuid default null
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
  role_label text;
  reviewer record;
begin
  if auth.uid() is null then
    raise exception 'Authentication is required.';
  end if;
  if length(trim(coalesce(p_message, ''))) < 10 then
    raise exception 'Please say a little about why you would like this access.';
  end if;
  if p_approver_id is null then
    raise exception 'Choose the Community Head or President you are asking.';
  end if;
  if p_approver_id = auth.uid() then
    raise exception 'Choose somebody else to review your request.';
  end if;
  if not public.user_has_permission(p_approver_id, 'services.manage_recurring') then
    raise exception 'Choose a Community Head, Tech Admin, or the President.';
  end if;

  select * into requested_role from public.roles where name = requested_role_name;
  if requested_role.id is null
    or not public.can_request_access_role(auth.uid(), requested_role.id)
  then
    raise exception 'This access-level change is not allowed.';
  end if;

  insert into public.access_requests (
    requester_id, requested_role_id, message, approver_id
  )
  values (auth.uid(), requested_role.id, trim(p_message), p_approver_id)
  returning * into created_request;

  select name into requester_name from public.users where id = auth.uid();
  role_label := public.access_level_label(requested_role.name);

  -- The person actually asked hears it as a request of them.
  perform public.queue_app_notification(
    p_approver_id, 'access_request_submitted',
    'A devotee asked you for more access',
    coalesce(requester_name, 'A devotee') || ' asked you to approve '
      || role_label || ' access.',
    jsonb_build_object('accessRequestId', created_request.id)
  );

  -- Everyone who can act on it is told too, so a request is never stuck
  -- behind one person being away.
  for reviewer in
    select distinct users.id
    from public.users
    join public.role_permissions
      on role_permissions.role_id = users.role_id
     and role_permissions.permission_key = 'access.review_requests'
    where users.id <> auth.uid()
      and users.id <> p_approver_id
  loop
    perform public.queue_app_notification(
      reviewer.id, 'access_request_submitted', 'A devotee asked for more access',
      coalesce(requester_name, 'A devotee') || ' asked to become ' || role_label || '.',
      jsonb_build_object('accessRequestId', created_request.id)
    );
  end loop;

  return created_request;
exception
  when unique_violation then
    raise exception 'You already have a pending access request.';
end;
$$;

revoke all on function public.create_access_request(text, text, uuid) from public, anon;
grant execute on function public.create_access_request(text, text, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Requests carry who was asked and who answered.
--
--    A Community Head sees the requests addressed to them and everything they
--    have decided; the President and Tech Admin see everything.
-- ---------------------------------------------------------------------------

drop function if exists public.list_my_access_requests();

create or replace function public.list_my_access_requests()
returns table (
  id uuid,
  requester_id uuid,
  requester_name text,
  requester_photo_url text,
  requester_role text,
  requested_role text,
  status text,
  message text,
  review_note text,
  created_at timestamptz,
  reviewed_at timestamptz,
  approver_id uuid,
  approver_name text,
  reviewed_by_name text
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    requests.id,
    requests.requester_id,
    requester.name,
    requester.photo_url,
    holding.name,
    requested.name,
    requests.status,
    requests.message,
    requests.review_note,
    requests.created_at,
    requests.reviewed_at,
    requests.approver_id,
    approver.name,
    reviewer.name
  from public.access_requests requests
  join public.users requester on requester.id = requests.requester_id
  join public.roles holding on holding.id = requester.role_id
  join public.roles requested on requested.id = requests.requested_role_id
  left join public.users approver on approver.id = requests.approver_id
  left join public.users reviewer on reviewer.id = requests.reviewed_by
  where requests.requester_id = auth.uid()
     or requests.approver_id = auth.uid()
     or public.has_permission('access.review_requests')
     -- A Community Head can approve, so they see what is waiting.
     or public.has_permission('services.manage_recurring')
  order by
    case when requests.status = 'pending' then 0 else 1 end,
    requests.created_at desc
$$;

revoke all on function public.list_my_access_requests() from public, anon;
grant execute on function public.list_my_access_requests() to authenticated;

-- ---------------------------------------------------------------------------
-- 4. A Community Head can answer what they were asked.
--
--    Previously only access.review_requests (Tech Admin and President) could
--    decide, which made naming a Community Head meaningless.
-- ---------------------------------------------------------------------------

drop function if exists public.review_access_request(uuid, text, text);

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
  requester_name text;
  role_label text;
  coordinator record;
begin
  if decision not in ('approved', 'denied') then
    raise exception 'Decision must be approved or denied.';
  end if;

  select * into pending_request from public.access_requests
  where id = access_request_id for update;
  if pending_request.id is null or pending_request.status <> 'pending' then
    raise exception 'This access request is no longer pending.';
  end if;

  -- The member who was asked may answer; so may anyone who reviews access.
  if pending_request.approver_id is distinct from auth.uid()
    and not public.has_permission('access.review_requests')
  then
    raise exception 'Only the member this devotee asked, a Tech Admin, or the President can answer this.';
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
  select name into requester_name from public.users
  where id = pending_request.requester_id;
  select public.access_level_label(roles.name) into role_label
  from public.roles where roles.id = pending_request.requested_role_id;

  if pending_request.requester_id <> auth.uid() then
    perform public.queue_app_notification(
      pending_request.requester_id, 'access_request_reviewed',
      case when decision = 'approved'
        then 'Your access level changed'
        else 'Your access request was not approved' end,
      case when decision = 'approved'
        then coalesce(reviewer_name, 'A reviewer') || ' approved your '
             || role_label || ' access.'
        else coalesce(reviewer_name, 'A reviewer')
             || ' did not approve your request to become ' || role_label || '.'
      end,
      jsonb_build_object('accessRequestId', reviewed_request.id)
    );
  end if;

  -- An access level changing is temple business, so the coordinators are told
  -- who granted it rather than discovering it later.
  if decision = 'approved' then
    for coordinator in
      select distinct users.id
      from public.users
      join public.role_permissions
        on role_permissions.role_id = users.role_id
       and role_permissions.permission_key = 'services.manage_recurring'
      where users.id <> auth.uid()
    loop
      perform public.queue_app_notification(
        coordinator.id, 'access_request_reviewed', 'An access level changed',
        coalesce(reviewer_name, 'A reviewer') || ' approved '
          || role_label || ' access for ' || coalesce(requester_name, 'a devotee') || '.',
        jsonb_build_object('accessRequestId', reviewed_request.id)
      );
    end loop;
  end if;

  return reviewed_request;
end;
$$;

revoke all on function public.review_access_request(uuid, text, text) from public, anon;
grant execute on function public.review_access_request(uuid, text, text) to authenticated;

do $$
begin
  raise notice 'access approver applied';
end;
$$;
