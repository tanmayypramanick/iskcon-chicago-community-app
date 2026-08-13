-- What the President can do about a sanga, deleting one, and live updates.
--
-- Three things the temple asked for after 202608040039_sangas.sql went live.
--
-- 1. The five RPCs that change a sanga admitted one caller: the devotee
--    running that sanga. Each now admits a second, a holder of app.view_all —
--    the President and the Tech Admin, and nobody else; see
--    202608020001_access_levels.sql. When the temple is asked to take a message
--    down or take somebody out of a group, "ask the devotee who runs it" is not
--    always an answer available at the hour it is asked.
--
--    They act on a sanga the same way they act on anything else in the app:
--    through the same RPCs, with the same rules about what a sanga is. Acting
--    does not enrol them. No sanga_members row is written for them, is_member
--    and is_admin stay false, and the member list is unchanged by anything they
--    do. That is deliberate: the count on the browse card is the count of
--    devotees in the circle, and it should not move because the office used a
--    button.
--
-- 2. There was no way to delete a sanga. Retiring one — active = false — is
--    reversible by its admin and is the right answer for "we are not meeting
--    over the summer". It is the wrong answer for a circle created in error or
--    one the temple has closed for good, which has to stop appearing anywhere.
--
-- 3. Every sanga screen needed a manual refresh, because the three tables the
--    screens are built from were not published for realtime.
--
-- Requires 202608040039_sangas.sql and 202608040042_devotee_care.sql.

-- ---------------------------------------------------------------------------
-- 1. Deleted, as distinct from retired.
--
--    Hard delete was considered and rejected. sangas cascades into
--    sanga_members, sanga_join_requests and sanga_messages, so a row removed is
--    a whole circle's history removed, and 202608040039_sangas.sql keeps that
--    history on purpose. So the row stays and deleted_at is stamped, the same
--    shape public.sanga_messages already uses for a message taken down.
--
--    deleted_at is set together with active = false, which is what makes this
--    cheap and safe: every guard already written against `active` — posting,
--    adding a member, asking to join — refuses a deleted sanga with no change
--    at all. deleted_at is the extra fact, and it does two things active alone
--    cannot. It takes the sanga out of list_my_sangas, where a retired one
--    deliberately stays so its admin can bring it back. And it closes the
--    update policy, so nobody can bring a deleted one back by flipping active.
-- ---------------------------------------------------------------------------

alter table public.sangas
  add column if not exists deleted_at timestamptz;

comment on column public.sangas.deleted_at is
  'Set when the sanga was deleted. Distinct from active = false, which is a pause its admin can undo: a row with deleted_at set is out of every list, cannot be posted in or joined, and cannot be made active again. The membership and the thread are kept.';

-- A deleted sanga must not sit on its name. The name is free again for anyone
-- to propose, on the same reasoning that already excludes declined sangas: a
-- row nobody can see blocking a name nobody can explain is the worst of both.
drop index if exists public.sangas_name_unique_idx;
create unique index if not exists sangas_name_unique_idx
  on public.sangas (lower(name))
  where status <> 'declined' and deleted_at is null;

-- Definer, for the same reason every other test in 0039 is: a policy on
-- sanga_messages that reads sangas under the caller's own rights would be
-- reading through the sangas policy, and the answer would then depend on
-- whether the caller may see the sanga rather than on whether it exists.
create or replace function public.is_sanga_deleted(p_sanga_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.sangas
    where sangas.id = p_sanga_id
      and sangas.deleted_at is not null
  )
$$;

revoke all on function public.is_sanga_deleted(uuid) from public, anon;
grant execute on function public.is_sanga_deleted(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. The one question the changed guards ask.
--
--    Two callers pass: the devotee who runs the sanga, and a holder of
--    app.view_all. Named once so the five RPCs below cannot drift apart, which
--    is exactly what happened to the five copies of `is_sanga_admin` this
--    replaces.
--
--    app.view_all rather than access.review_requests, even though the same two
--    roles hold both today. access.review_requests is keyed to the queue of
--    things waiting for a decision; this is not a decision, and a later change
--    to who staffs that queue should not silently change who can empty a
--    sanga.
-- ---------------------------------------------------------------------------

create or replace function public.can_act_on_sanga(p_sanga_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.is_sanga_admin(p_sanga_id)
      or public.has_permission('app.view_all')
$$;

revoke all on function public.can_act_on_sanga(uuid) from public, anon;
grant execute on function public.can_act_on_sanga(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Row level security.
--
--    Every write below goes through a security definer RPC, so no policy has
--    to be widened for the new powers — the definer functions are not subject
--    to them. What the policies do have to learn is deleted_at.
-- ---------------------------------------------------------------------------

drop policy if exists "Devotees read sangas they may see" on public.sangas;
create policy "Devotees read sangas they may see"
  on public.sangas for select to authenticated
  using (
    auth.uid() is not null
    and deleted_at is null
    and (
      (status = 'approved' and active)
      or created_by = auth.uid()
      or public.is_sanga_member(id)
      or public.has_permission('access.review_requests')
    )
  );

-- Unchanged except for deleted_at: a deleted sanga is not renamable and, more
-- to the point, not revivable, since active is a granted column and setting it
-- back to true is otherwise an ordinary update.
--
-- This clause is the one guard in this migration that cannot be caught on its
-- own by supabase/verification/sanga_powers.sql, and that is worth saying out
-- loud. Postgres applies a table's select policy to the rows an update reads,
-- and the select policy above already hides a deleted sanga from everybody, so
-- removing the words below changes no observable behaviour today. It is stated
-- anyway: whether a deleted sanga can be brought back should not be a side
-- effect of what the read policy happens to say.
drop policy if exists "Admins rename and retire their own sanga" on public.sangas;
create policy "Admins rename and retire their own sanga"
  on public.sangas for update to authenticated
  using (
    deleted_at is null
    and (public.is_sanga_admin(id) or public.has_permission('access.review_requests'))
  )
  with check (
    deleted_at is null
    and (public.is_sanga_admin(id) or public.has_permission('access.review_requests'))
  );

drop policy if exists "Devotees read messages in their sangas" on public.sanga_messages;
create policy "Devotees read messages in their sangas"
  on public.sanga_messages for select to authenticated
  using (
    not public.is_sanga_deleted(sanga_id)
    and (
      public.is_sanga_member(sanga_id)
      or public.has_permission('app.view_all')
    )
  );

-- can_see_sanga backs list_sanga_members, so a deleted sanga has to fall out of
-- it as well. Restated whole rather than patched, so the whole test reads in
-- one place.
create or replace function public.can_see_sanga(p_sanga_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is not null
    and exists (
      select 1 from public.sangas
      where sangas.id = p_sanga_id
        and sangas.deleted_at is null
        and (
          (sangas.status = 'approved' and sangas.active)
          or sangas.created_by = auth.uid()
          or public.is_sanga_member(p_sanga_id)
          or public.has_permission('access.review_requests')
          or public.has_permission('app.view_all')
        )
    )
$$;

-- ---------------------------------------------------------------------------
-- 4. The lists forget a deleted sanga.
--
--    list_sangas and list_pending_sangas already filter on active and status,
--    but a deleted sanga that was never approved would still be sitting in the
--    President's queue, so each one is stated rather than inferred.
-- ---------------------------------------------------------------------------

create or replace function public.list_sangas()
returns table (
  id uuid,
  name text,
  description text,
  member_count integer,
  is_member boolean,
  is_admin boolean,
  request_status text,
  admin_id uuid,
  admin_name text,
  created_by uuid,
  created_by_name text,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    sangas.id,
    sangas.name,
    sangas.description,
    coalesce(tally.total, 0),
    exists (
      select 1 from public.sanga_members mine
      where mine.sanga_id = sangas.id and mine.devotee_id = auth.uid()
    ),
    exists (
      select 1 from public.sanga_members mine
      where mine.sanga_id = sangas.id
        and mine.devotee_id = auth.uid()
        and mine.role = 'admin'
    ),
    (
      select asked.status from public.sanga_join_requests asked
      where asked.sanga_id = sangas.id and asked.devotee_id = auth.uid()
      order by asked.created_at desc
      limit 1
    ),
    sangas.admin_id,
    runner.name,
    sangas.created_by,
    founder.name,
    sangas.created_at
  from public.sangas
  left join public.users founder on founder.id = sangas.created_by
  left join public.users runner on runner.id = sangas.admin_id
  left join lateral (
    select count(*)::integer as total
    from public.sanga_members
    where sanga_members.sanga_id = sangas.id
  ) tally on true
  where auth.uid() is not null
    and sangas.status = 'approved'
    and sangas.active
    and sangas.deleted_at is null
  order by sangas.name
$$;

-- A retired sanga stays here, because its admin has to be able to find it and
-- bring it back. A deleted one does not.
create or replace function public.list_my_sangas()
returns table (
  id uuid,
  name text,
  description text,
  status text,
  active boolean,
  review_note text,
  member_count integer,
  is_member boolean,
  is_admin boolean,
  admin_id uuid,
  admin_name text,
  created_at timestamptz,
  reviewed_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    sangas.id,
    sangas.name,
    sangas.description,
    sangas.status,
    sangas.active,
    sangas.review_note,
    coalesce(tally.total, 0),
    membership.devotee_id is not null,
    coalesce(membership.role = 'admin', false),
    sangas.admin_id,
    runner.name,
    sangas.created_at,
    sangas.reviewed_at
  from public.sangas
  left join public.users runner on runner.id = sangas.admin_id
  left join public.sanga_members membership
    on membership.sanga_id = sangas.id
   and membership.devotee_id = auth.uid()
  left join lateral (
    select count(*)::integer as total
    from public.sanga_members
    where sanga_members.sanga_id = sangas.id
  ) tally on true
  where auth.uid() is not null
    and sangas.deleted_at is null
    and (membership.devotee_id is not null or sangas.created_by = auth.uid())
  order by
    case when sangas.status = 'pending' then 0 else 1 end,
    sangas.name
$$;

create or replace function public.list_pending_sangas()
returns table (
  id uuid,
  name text,
  description text,
  created_by uuid,
  created_by_name text,
  created_by_photo_url text,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    sangas.id,
    sangas.name,
    sangas.description,
    sangas.created_by,
    founder.name,
    founder.photo_url,
    sangas.created_at
  from public.sangas
  left join public.users founder on founder.id = sangas.created_by
  where public.has_permission('access.review_requests')
    and sangas.status = 'pending'
    and sangas.deleted_at is null
  order by sangas.created_at
$$;

create or replace function public.list_sanga_join_requests(p_sanga_id uuid)
returns table (
  id uuid,
  sanga_id uuid,
  devotee_id uuid,
  devotee_name text,
  devotee_photo_url text,
  status text,
  message text,
  created_at timestamptz,
  decided_at timestamptz,
  decided_by uuid,
  decided_by_name text
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    asked.id,
    asked.sanga_id,
    asked.devotee_id,
    asker.name,
    asker.photo_url,
    asked.status,
    asked.message,
    asked.created_at,
    asked.decided_at,
    asked.decided_by,
    decider.name
  from public.sanga_join_requests asked
  join public.users asker on asker.id = asked.devotee_id
  left join public.users decider on decider.id = asked.decided_by
  where public.can_act_on_sanga(p_sanga_id)
    and not public.is_sanga_deleted(p_sanga_id)
    and asked.sanga_id = p_sanga_id
  order by
    case when asked.status = 'pending' then 0 else 1 end,
    asked.created_at desc
$$;

create or replace function public.list_sanga_messages(p_sanga_id uuid)
returns table (
  id uuid,
  sanga_id uuid,
  sender_id uuid,
  sender_name text,
  sender_photo_url text,
  body text,
  image_url text,
  created_at timestamptz,
  deleted_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    sanga_messages.id,
    sanga_messages.sanga_id,
    sanga_messages.sender_id,
    sender.name,
    sender.photo_url,
    sanga_messages.body,
    sanga_messages.image_url,
    sanga_messages.created_at,
    sanga_messages.deleted_at
  from public.sanga_messages
  join public.users sender on sender.id = sanga_messages.sender_id
  where sanga_messages.sanga_id = p_sanga_id
    and not public.is_sanga_deleted(p_sanga_id)
    and (
      public.is_sanga_member(p_sanga_id)
      or public.has_permission('app.view_all')
    )
  order by sanga_messages.created_at
$$;

-- ---------------------------------------------------------------------------
-- 5. The five RPCs that gain a second permitted caller.
--
--    Each keeps every rule it already had. The refusal messages are unchanged:
--    they are addressed to the devotee being refused, who is being told what
--    they may do, and that has not changed for them.
-- ---------------------------------------------------------------------------

create or replace function public.send_sanga_message(
  p_sanga_id uuid,
  p_body text default null,
  p_image_url text default null
)
returns public.sanga_messages
language plpgsql
security definer
set search_path = ''
as $$
declare
  target public.sangas;
  sent public.sanga_messages;
begin
  if not (public.is_sanga_member(p_sanga_id) or public.has_permission('app.view_all')) then
    raise exception 'Only devotees in this sanga can post in it.';
  end if;

  -- A circle the temple has not agreed to run, or has retired or deleted, has
  -- no thread. This holds for every caller: there is nowhere to post.
  select * into target from public.sangas
  where id = p_sanga_id and status = 'approved' and active and deleted_at is null;
  if target.id is null then
    raise exception 'That sanga is not running.';
  end if;

  if nullif(trim(coalesce(p_body, '')), '') is null and p_image_url is null then
    raise exception 'Write something or attach a picture.';
  end if;

  insert into public.sanga_messages (sanga_id, sender_id, body, image_url)
  values (
    p_sanga_id, auth.uid(),
    nullif(trim(coalesce(p_body, '')), ''), p_image_url
  )
  returning * into sent;

  return sent;
end;
$$;

-- Three people may take a message down now: whoever said it, whoever runs the
-- sanga it was said in, and a holder of app.view_all.
create or replace function public.delete_sanga_message(p_message_id uuid)
returns public.sanga_messages
language plpgsql
security definer
set search_path = ''
as $$
declare
  target public.sanga_messages;
  updated public.sanga_messages;
begin
  select * into target from public.sanga_messages
  where id = p_message_id for update;
  if target.id is null then
    raise exception 'That message could not be found.';
  end if;

  if target.sender_id <> auth.uid()
     and not public.can_act_on_sanga(target.sanga_id) then
    raise exception 'You can take down your own messages, or any message in a sanga you run.';
  end if;

  -- coalesce so deleting twice cannot overwrite what was moved aside the
  -- first time with the nulls left behind by it.
  update public.sanga_messages
  set deleted_at = now(),
      original_body = coalesce(original_body, body),
      original_image_url = coalesce(original_image_url, image_url),
      body = null,
      image_url = null
  where id = p_message_id
  returning * into updated;
  return updated;
end;
$$;

create or replace function public.add_sanga_member(
  p_sanga_id uuid,
  p_devotee_id uuid
)
returns public.sanga_members
language plpgsql
security definer
set search_path = ''
as $$
declare
  target public.sangas;
  membership public.sanga_members;
  already_in boolean;
  admin_name text;
begin
  if not public.can_act_on_sanga(p_sanga_id) then
    raise exception 'Only the devotee who runs this sanga can add somebody to it.';
  end if;

  select * into target from public.sangas
  where id = p_sanga_id and status = 'approved' and active and deleted_at is null;
  if target.id is null then
    raise exception 'That sanga is not running.';
  end if;
  if not exists (select 1 from public.users where id = p_devotee_id) then
    raise exception 'That devotee could not be found.';
  end if;

  already_in := exists (
    select 1 from public.sanga_members
    where sanga_members.sanga_id = p_sanga_id
      and sanga_members.devotee_id = p_devotee_id
  );

  -- joined_at is written back as itself, and role is left alone: adding
  -- somebody who is already there — including the admin themselves — must not
  -- reset their standing or quietly demote them.
  insert into public.sanga_members (sanga_id, devotee_id, role, added_by)
  values (p_sanga_id, p_devotee_id, 'member', auth.uid())
  on conflict (sanga_id, devotee_id) do update
    set joined_at = public.sanga_members.joined_at
  returning * into membership;

  -- Being let in the front door answers the knock at the back one.
  update public.sanga_join_requests
  set status = 'approved', decided_by = auth.uid(), decided_at = now()
  where sanga_id = p_sanga_id
    and devotee_id = p_devotee_id
    and status = 'pending';

  if not already_in and p_devotee_id <> auth.uid() then
    select name into admin_name from public.users where id = auth.uid();
    perform public.queue_app_notification(
      p_devotee_id, 'sanga_member_added',
      'You were added to ' || target.name,
      coalesce(admin_name, 'The sanga admin') || ' added you to '
        || target.name || '.',
      jsonb_build_object('sangaId', target.id)
    );
  end if;

  return membership;
end;
$$;

-- The last-admin rule is unchanged, and it is unchanged for everybody.
--
-- A sanga has exactly one devotee responsible for it, and the sole admin is
-- refused rather than removed — for the President as much as for the admin
-- themselves. Letting the office remove them would leave a live circle with
-- nobody to answer its requests to join, which is a worse state than either of
-- the two things the President can actually do about it: hand the sanga to
-- another member, or delete it. The refusal says so.
create or replace function public.remove_sanga_member(
  p_sanga_id uuid,
  p_devotee_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  target public.sangas;
  target_role text;
  admin_tally integer;
  removed integer;
  admin_name text;
begin
  if not public.can_act_on_sanga(p_sanga_id) then
    raise exception 'Only the devotee who runs this sanga can remove somebody from it.';
  end if;

  select * into target from public.sangas where id = p_sanga_id;
  if target.id is null then
    raise exception 'That sanga could not be found.';
  end if;

  select role into target_role from public.sanga_members
  where sanga_members.sanga_id = p_sanga_id
    and sanga_members.devotee_id = p_devotee_id
  for update;
  -- Nobody to remove is not an error. The admin tapped twice, or somebody left
  -- while the screen was open.
  if target_role is null then
    return false;
  end if;

  if target_role = 'admin' then
    select count(*)::integer into admin_tally from public.sanga_members
    where sanga_members.sanga_id = p_sanga_id and sanga_members.role = 'admin';
    if admin_tally <= 1 then
      raise exception 'A sanga must always have somebody responsible for it. Hand "%" to another member before removing its admin, or delete the sanga.', target.name;
    end if;
  end if;

  delete from public.sanga_members
  where sanga_members.sanga_id = p_sanga_id
    and sanga_members.devotee_id = p_devotee_id;
  get diagnostics removed = row_count;

  -- No membership, no request. An answered request left behind would show this
  -- devotee as approved for a sanga they are not in, and a pending one would
  -- sit in an inbox for somebody who has just been shown the door.
  delete from public.sanga_join_requests
  where sanga_join_requests.sanga_id = p_sanga_id
    and sanga_join_requests.devotee_id = p_devotee_id;

  if target.admin_id = p_devotee_id then
    update public.sangas
    set admin_id = (
      select devotee_id from public.sanga_members
      where sanga_members.sanga_id = p_sanga_id and sanga_members.role = 'admin'
      order by joined_at
      limit 1
    )
    where id = p_sanga_id;
  end if;

  if p_devotee_id <> auth.uid() then
    select name into admin_name from public.users where id = auth.uid();
    perform public.queue_app_notification(
      p_devotee_id, 'sanga_member_removed',
      'You are no longer in ' || target.name,
      coalesce(admin_name, 'The sanga admin') || ' removed you from '
        || target.name || '.',
      jsonb_build_object('sangaId', target.id)
    );
  end if;

  return removed > 0;
end;
$$;

create or replace function public.review_sanga_join_request(
  p_request_id uuid,
  p_decision text
)
returns public.sanga_join_requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  waiting public.sanga_join_requests;
  decided public.sanga_join_requests;
  target public.sangas;
  admin_name text;
begin
  if p_decision not in ('approved', 'declined') then
    raise exception 'Decision must be approved or declined.';
  end if;

  select * into waiting from public.sanga_join_requests
  where id = p_request_id for update;
  if waiting.id is null then
    raise exception 'That request could not be found.';
  end if;
  if waiting.status <> 'pending' then
    raise exception 'That request has already been answered.';
  end if;

  if not public.can_act_on_sanga(waiting.sanga_id) then
    raise exception 'Only the devotee who runs this sanga can answer requests to join it.';
  end if;
  if public.is_sanga_deleted(waiting.sanga_id) then
    raise exception 'That sanga could not be found.';
  end if;

  select * into target from public.sangas where id = waiting.sanga_id;

  if p_decision = 'approved' then
    -- do nothing on conflict: if they are already in — added directly while
    -- the request sat there — approving must not make a second membership or
    -- reset how long they have been in the circle.
    insert into public.sanga_members (sanga_id, devotee_id, role)
    values (waiting.sanga_id, waiting.devotee_id, 'member')
    on conflict (sanga_id, devotee_id) do nothing;
  end if;

  update public.sanga_join_requests
  set status = p_decision,
      decided_by = auth.uid(),
      decided_at = now()
  where id = waiting.id
  returning * into decided;

  select name into admin_name from public.users where id = auth.uid();

  if waiting.devotee_id <> auth.uid() then
    perform public.queue_app_notification(
      waiting.devotee_id, 'sanga_join_reviewed',
      case when p_decision = 'approved'
        then 'You are in ' || target.name
        else 'Your request to join ' || target.name || ' was declined' end,
      case when p_decision = 'approved'
        then coalesce(admin_name, 'The sanga admin') || ' welcomed you into '
             || target.name || '.'
        else coalesce(admin_name, 'The sanga admin')
             || ' did not approve your request to join ' || target.name || '.'
      end,
      jsonb_build_object('sangaId', target.id, 'sangaJoinRequestId', decided.id)
    );
  end if;

  return decided;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Three RPCs that only learn about deleted_at.
--
--    active and deleted_at are two different facts and each is tested for its
--    own sake. active is the admin's pause switch, which they may set back; a
--    deleted sanga also has it clear, but nothing here leans on that, because a
--    guard that only holds while a second column happens to agree with it is a
--    guard that stops holding the day somebody changes the second column.
-- ---------------------------------------------------------------------------

create or replace function public.request_to_join_sanga(
  p_sanga_id uuid,
  p_message text default null
)
returns public.sanga_join_requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  target public.sangas;
  existing public.sanga_join_requests;
  created public.sanga_join_requests;
  asker_name text;
begin
  if auth.uid() is null then
    raise exception 'Sign in to ask to join a sanga.';
  end if;

  select * into target from public.sangas
  where id = p_sanga_id and status = 'approved' and active and deleted_at is null;
  if target.id is null then
    raise exception 'That sanga could not be found.';
  end if;

  if public.is_sanga_member(p_sanga_id) then
    raise exception 'You are already in %.', target.name;
  end if;

  -- A second tap is the same ask. It returns the row it already made and, in
  -- particular, does not tell the admin twice.
  select * into existing from public.sanga_join_requests
  where sanga_id = p_sanga_id
    and devotee_id = auth.uid()
    and status = 'pending'
  for update;
  if existing.id is not null then
    return existing;
  end if;

  insert into public.sanga_join_requests (sanga_id, devotee_id, message)
  values (p_sanga_id, auth.uid(), nullif(trim(coalesce(p_message, '')), ''))
  returning * into created;

  select name into asker_name from public.users where id = auth.uid();

  if target.admin_id is not null and target.admin_id <> auth.uid() then
    perform public.queue_app_notification(
      target.admin_id, 'sanga_join_requested',
      'Someone asked to join ' || target.name,
      coalesce(asker_name, 'A devotee') || ' asked to join ' || target.name || '.',
      jsonb_build_object('sangaId', target.id, 'sangaJoinRequestId', created.id)
    );
  end if;

  return created;
end;
$$;

create or replace function public.review_sanga(
  p_sanga_id uuid,
  p_decision text,
  p_note text default null
)
returns public.sangas
language plpgsql
security definer
set search_path = ''
as $$
declare
  waiting public.sangas;
  decided public.sangas;
  reviewer_name text;
begin
  if not public.has_permission('access.review_requests') then
    raise exception 'Only the President or a Tech Admin can approve a sanga.';
  end if;
  if p_decision not in ('approved', 'declined') then
    raise exception 'Decision must be approved or declined.';
  end if;

  select * into waiting from public.sangas where id = p_sanga_id for update;
  if waiting.id is null or waiting.deleted_at is not null then
    raise exception 'That sanga could not be found.';
  end if;
  if waiting.status <> 'pending' then
    raise exception 'That sanga has already been decided.';
  end if;

  update public.sangas
  set status = p_decision,
      reviewed_by = auth.uid(),
      reviewed_at = now(),
      review_note = nullif(trim(coalesce(p_note, '')), '')
  where id = waiting.id
  returning * into decided;

  select name into reviewer_name from public.users where id = auth.uid();

  if waiting.created_by is not null and waiting.created_by <> auth.uid() then
    perform public.queue_app_notification(
      waiting.created_by, 'sanga_reviewed',
      case when p_decision = 'approved'
        then decided.name || ' is now open'
        else 'Your sanga was not approved' end,
      case when p_decision = 'approved'
        then coalesce(reviewer_name, 'The President') || ' approved '
             || decided.name || '. Devotees can find it and ask to join.'
        else coalesce(reviewer_name, 'The President') || ' did not approve '
             || decided.name
             || coalesce('. ' || decided.review_note, '.')
      end,
      jsonb_build_object('sangaId', decided.id)
    );
  end if;

  return decided;
end;
$$;

-- Handing over stays the admin's alone: choosing a successor is a judgement
-- about the people in the circle. A holder of app.view_all who needs a sanga
-- to stop can delete it.
create or replace function public.transfer_sanga_admin(
  p_sanga_id uuid,
  p_devotee_id uuid
)
returns public.sangas
language plpgsql
security definer
set search_path = ''
as $$
declare
  target public.sangas;
  updated public.sangas;
  previous_name text;
begin
  if not public.is_sanga_admin(p_sanga_id) then
    raise exception 'Only the devotee who runs this sanga can hand it to somebody else.';
  end if;
  if p_devotee_id = auth.uid() then
    raise exception 'You already run this sanga.';
  end if;

  select * into target from public.sangas where id = p_sanga_id for update;
  if target.id is null or target.deleted_at is not null then
    raise exception 'That sanga could not be found.';
  end if;

  -- The successor has to already be in the circle. Handing a group to somebody
  -- standing outside it is how groups end up run by people who never open them.
  if not exists (
    select 1 from public.sanga_members
    where sanga_members.sanga_id = p_sanga_id
      and sanga_members.devotee_id = p_devotee_id
  ) then
    raise exception 'Add that devotee to the sanga before handing it to them.';
  end if;

  update public.sanga_members set role = 'admin'
  where sanga_members.sanga_id = p_sanga_id
    and sanga_members.devotee_id = p_devotee_id;

  update public.sanga_members set role = 'member'
  where sanga_members.sanga_id = p_sanga_id
    and sanga_members.devotee_id = auth.uid();

  update public.sangas set admin_id = p_devotee_id
  where id = p_sanga_id
  returning * into updated;

  select name into previous_name from public.users where id = auth.uid();

  perform public.queue_app_notification(
    p_devotee_id, 'sanga_admin_transferred',
    'You now run ' || updated.name,
    coalesce(previous_name, 'The previous admin') || ' handed '
      || updated.name || ' to you. You can add members and answer requests to join.',
    jsonb_build_object('sangaId', updated.id)
  );

  return updated;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Deleting one.
--
--    Restated whole: a check constraint cannot be added to in part. The list
--    below is 202608040042_devotee_care.sql's with sanga_deleted added.
-- ---------------------------------------------------------------------------

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
      'sanga_created', 'sanga_reviewed',
      'sanga_join_requested', 'sanga_join_reviewed',
      'sanga_member_added', 'sanga_member_removed', 'sanga_member_left',
      'sanga_admin_transferred', 'sanga_deleted',
      'announcement_posted',
      'feedback_reviewed',
      'care_reply',
      'remote'
    )
  );

-- Whoever runs the sanga, or a holder of app.view_all. Not the founder by
-- virtue of having founded it: they may have handed it on years ago, and the
-- devotee responsible for a circle is the one running it today.
--
-- Everybody who was in it is told. A group chat that disappears overnight with
-- no word is the kind of thing devotees ask the office about for a fortnight.
create or replace function public.delete_sanga(p_sanga_id uuid)
returns public.sangas
language plpgsql
security definer
set search_path = ''
as $$
declare
  target public.sangas;
  gone public.sangas;
  actor_name text;
  member record;
begin
  if auth.uid() is null then
    raise exception 'Sign in to delete a sanga.';
  end if;

  select * into target from public.sangas where id = p_sanga_id for update;
  if target.id is null or target.deleted_at is not null then
    raise exception 'That sanga could not be found.';
  end if;

  if not public.can_act_on_sanga(p_sanga_id) then
    raise exception 'Only the devotee who runs this sanga can delete it.';
  end if;

  -- active goes false alongside deleted_at so that every guard already written
  -- against active — posting, adding a member, asking to join — refuses this
  -- sanga without needing to be taught a second column.
  update public.sangas
  set active = false,
      deleted_at = now()
  where id = p_sanga_id
  returning * into gone;

  select name into actor_name from public.users where id = auth.uid();

  for member in
    select sanga_members.devotee_id
    from public.sanga_members
    where sanga_members.sanga_id = p_sanga_id
      and sanga_members.devotee_id <> auth.uid()
  loop
    perform public.queue_app_notification(
      member.devotee_id, 'sanga_deleted',
      gone.name || ' has closed',
      coalesce(actor_name, 'The temple office') || ' closed '
        || gone.name || '.',
      jsonb_build_object('sangaId', gone.id)
    );
  end loop;

  return gone;
end;
$$;

revoke all on function public.delete_sanga(uuid) from public, anon;
grant execute on function public.delete_sanga(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 8. Realtime.
--
--    sanga_messages was already published with replica identity full in
--    202608040039_sangas.sql; the other three were not, so every screen built
--    on them only changed when the devotee left it and came back.
--
--    REPLICA IDENTITY FULL is not optional here. A filtered postgres_changes
--    subscription on a table with row level security cannot evaluate its filter
--    from the default replica identity, which carries only the primary key: the
--    change then arrives late, or not at all. That is precisely the omission
--    fixed for direct messages in 202608040035_messaging_realtime.sql.
-- ---------------------------------------------------------------------------

alter table public.sangas replica identity full;
alter table public.sanga_members replica identity full;
alter table public.sanga_join_requests replica identity full;

do $$
declare
  v_table text;
  v_identity "char";
begin
  select relreplident into v_identity
  from pg_class
  join pg_namespace on pg_namespace.oid = pg_class.relnamespace
  where pg_namespace.nspname = 'public' and pg_class.relname = 'sanga_messages';
  if v_identity is distinct from 'f' then
    raise exception 'sanga_messages carries replica identity % rather than full.', v_identity;
  end if;

  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    return;
  end if;

  foreach v_table in array array['sangas', 'sanga_members', 'sanga_join_requests', 'sanga_messages']
  loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = v_table
    ) then
      execute format('alter publication supabase_realtime add table public.%I', v_table);
    end if;
  end loop;
end;
$$;

do $$
begin
  raise notice 'sanga powers applied';
end;
$$;
