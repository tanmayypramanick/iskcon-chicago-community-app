-- Sangas: the smaller circles inside the congregation.
--
-- A temple this size is not one undifferentiated room of people. There is a
-- youth sanga, a Bhagavad-gita study group, a kirtan group — each with its own
-- regulars — and the app knew about none of them.
--
-- A sanga behaves the way a devotee already expects a group to behave, because
-- they have used WhatsApp:
--
--   * anybody signed in may start one, and it waits for the President;
--   * the devotee who started it runs it;
--   * whoever runs it can add a devotee straight in, or remove one;
--   * anybody else may ask to join, and the person running it decides;
--   * and everyone inside talks to everyone else, in one thread, with pictures.
--
-- The President stands at the door rather than inside every group. They decide
-- that the temple has a youth sanga at all; they do not decide who is in it.
-- That is the one judgement a congregation genuinely wants from its president,
-- and everything after it belongs to the people actually in the circle.
--
-- Nothing is seeded. The temple knows its own circles far better than we do,
-- and a guessed list only leaves somebody deleting our guesses first.
-- Requires 202608040038_children_initiation.sql.

-- An earlier draft of this file modelled a sanga as a noticeboard anyone could
-- sign themselves onto. Nothing was ever deployed from it, but a developer
-- machine may still carry it, and the shapes below have changed.
drop function if exists public.join_sanga(uuid);
drop function if exists public.list_sangas();
drop function if exists public.list_sanga_members(uuid);
drop function if exists public.create_sanga(text, text);
drop function if exists public.leave_sanga(uuid);

-- ---------------------------------------------------------------------------
-- 1. A sanga, who is in it, and who has asked to be.
--
--    A sanga is retired rather than deleted: the people who were in it, and
--    the fact that the temple once ran it, are worth keeping.
-- ---------------------------------------------------------------------------

create table if not exists public.sangas (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  -- The founder may one day leave the congregation; the circle they started
  -- outlives them, so the row is kept and only the attribution goes.
  created_by uuid references public.users(id) on delete set null,
  -- Denormalised from sanga_members deliberately. Every screen in the app asks
  -- "who runs this?" before it asks anything else, and a join for it on every
  -- row of a browse list is a join that will be forgotten somewhere.
  admin_id uuid references public.users(id) on delete set null,
  status text not null default 'pending' check (
    status in ('pending', 'approved', 'declined')
  ),
  reviewed_by uuid references public.users(id) on delete set null,
  reviewed_at timestamptz,
  review_note text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint sanga_name_not_blank check (nullif(trim(name), '') is not null),
  -- reviewed_by is allowed to be null on a decided sanga only because the
  -- reviewer's account may later be deleted; it is never null at the moment of
  -- the decision. reviewed_at is the field that says a decision happened.
  constraint sanga_review_consistency check (
    (status = 'pending' and reviewed_at is null and review_note is null)
    or status <> 'pending'
  )
);

-- Uniqueness is case-insensitive: "Youth Sanga" and "youth sanga" are the same
-- circle to everyone standing in the temple, and letting both exist would split
-- one group's membership across two rows nobody could tell apart.
--
-- Declined sangas are left out of it. A name the President turned down once is
-- a name that should be free for somebody to propose properly later, and a
-- rejected row silently squatting on it would be impossible to explain.
create unique index if not exists sangas_name_unique_idx
  on public.sangas (lower(name))
  where status <> 'declined';

create index if not exists sangas_status_name_idx
  on public.sangas (status, active, lower(name));

create index if not exists sangas_created_by_idx
  on public.sangas (created_by);

create table if not exists public.sanga_members (
  sanga_id uuid not null references public.sangas(id) on delete cascade,
  devotee_id uuid not null references public.users(id) on delete cascade,
  role text not null default 'member' check (role in ('admin', 'member')),
  joined_at timestamptz not null default now(),
  -- Null when the devotee asked to join and was let in; set when an admin put
  -- them there. The difference matters if anyone ever has to explain how a
  -- devotee ended up in a group they do not remember joining.
  added_by uuid references public.users(id) on delete set null,
  primary key (sanga_id, devotee_id)
);

-- The primary key already serves "who is in this sanga"; this serves the other
-- direction, "which sangas is this devotee in", which the profile screen asks.
create index if not exists sanga_members_devotee_idx
  on public.sanga_members (devotee_id);

create index if not exists sanga_members_admin_idx
  on public.sanga_members (sanga_id) where role = 'admin';

create table if not exists public.sanga_join_requests (
  id uuid primary key default gen_random_uuid(),
  sanga_id uuid not null references public.sangas(id) on delete cascade,
  devotee_id uuid not null references public.users(id) on delete cascade,
  status text not null default 'pending' check (
    status in ('pending', 'approved', 'declined')
  ),
  message text,
  decided_by uuid references public.users(id) on delete set null,
  decided_at timestamptz,
  created_at timestamptz not null default now(),
  constraint sanga_join_request_decision_consistency check (
    (status = 'pending' and decided_at is null)
    or (status <> 'pending' and decided_at is not null)
  )
);

-- One live ask at a time. A devotee on temple wifi taps a button, sees nothing
-- happen, and taps again; two rows in the admin's inbox would be the app's
-- fault dressed up as theirs. A request that was declined does not block a
-- later one — circumstances change, and so do admins.
create unique index if not exists sanga_join_requests_one_pending_idx
  on public.sanga_join_requests (sanga_id, devotee_id)
  where status = 'pending';

create index if not exists sanga_join_requests_sanga_idx
  on public.sanga_join_requests (sanga_id, status, created_at desc);

create index if not exists sanga_join_requests_devotee_idx
  on public.sanga_join_requests (devotee_id, created_at desc);

comment on column public.sangas.status is
  'pending until the President decides. Only approved sangas are browsable; a pending one is visible to the devotee who proposed it and to the President.';

comment on column public.sangas.active is
  'False means retired. Retired sangas vanish from the browse list but keep their membership, so a circle can be revived without asking everyone to rejoin.';

comment on column public.sangas.admin_id is
  'The devotee who runs this sanga. Always matches the single sanga_members row with role = admin; kept here so the browse list does not have to join for it.';

comment on column public.sanga_members.added_by is
  'The admin who put this devotee in, or null if the devotee asked and was let in.';

-- Renaming and retiring happen as plain updates under RLS rather than through
-- an RPC, so the stamp is applied by the database instead of being taken on
-- trust from whoever sent the update.
create or replace function public.touch_sanga_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

revoke all on function public.touch_sanga_updated_at() from public, anon, authenticated;

drop trigger if exists touch_sanga_updated_at on public.sangas;
create trigger touch_sanga_updated_at
before update on public.sangas
for each row execute function public.touch_sanga_updated_at();

alter table public.sangas enable row level security;
alter table public.sanga_members enable row level security;
alter table public.sanga_join_requests enable row level security;

-- ---------------------------------------------------------------------------
-- 2. The three questions every policy below asks.
--
--    Definer, and not only for speed. A policy on sangas that reads
--    sanga_members, and a policy on sanga_members that reads sangas, is a
--    recursion Postgres refuses outright at query time. Asking through a
--    definer function — which is not subject to either policy — is what breaks
--    the circle.
-- ---------------------------------------------------------------------------

create or replace function public.is_sanga_member(p_sanga_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.sanga_members
    where sanga_members.sanga_id = p_sanga_id
      and sanga_members.devotee_id = auth.uid()
  )
$$;

revoke all on function public.is_sanga_member(uuid) from public, anon;
grant execute on function public.is_sanga_member(uuid) to authenticated;

create or replace function public.is_sanga_admin(p_sanga_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.sanga_members
    where sanga_members.sanga_id = p_sanga_id
      and sanga_members.devotee_id = auth.uid()
      and sanga_members.role = 'admin'
  )
$$;

revoke all on function public.is_sanga_admin(uuid) from public, anon;
grant execute on function public.is_sanga_admin(uuid) to authenticated;

-- A sanga on offer is visible to everyone; one still waiting is visible to the
-- devotee who proposed it and to anyone already in it. The two permission keys
-- are both named rather than one standing in for the other: access.review_requests
-- is what the approval queue is keyed on, app.view_all is what the rest of the
-- app's read paths are keyed on, and a later change to either should not move
-- this test with it.
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
        and (
          (sangas.status = 'approved' and sangas.active)
          or sangas.created_by = auth.uid()
          or public.is_sanga_member(p_sanga_id)
          or public.has_permission('access.review_requests')
          or public.has_permission('app.view_all')
        )
    )
$$;

revoke all on function public.can_see_sanga(uuid) from public, anon;
grant execute on function public.can_see_sanga(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Who may see and change what.
--
--    Approved sangas are the opposite of private: the whole point is that a
--    devotee can see what exists and who is already there. Everything that
--    changes a sanga goes through an RPC, so no table below grants insert or
--    delete to anybody — the only direct write a devotee can make is an admin
--    renaming or retiring their own circle.
--
--    "The President" is the holder of access.review_requests, which is the
--    President and the Tech Admin. Inventing a parallel permission key for
--    sangas would be one more thing to keep in step, and the Tech Admin has to
--    be able to unstick a temple whose president is travelling.
-- ---------------------------------------------------------------------------

drop policy if exists "Devotees read sangas they may see" on public.sangas;
create policy "Devotees read sangas they may see"
  on public.sangas for select to authenticated
  using (
    auth.uid() is not null
    and (
      (status = 'approved' and active)
      or created_by = auth.uid()
      or public.is_sanga_member(id)
      or public.has_permission('access.review_requests')
    )
  );

-- Only name, description and active are granted below, so this policy cannot
-- be used to approve a sanga or hand it to somebody else.
drop policy if exists "Admins rename and retire their own sanga" on public.sangas;
create policy "Admins rename and retire their own sanga"
  on public.sangas for update to authenticated
  using (public.is_sanga_admin(id) or public.has_permission('access.review_requests'))
  with check (public.is_sanga_admin(id) or public.has_permission('access.review_requests'));

drop policy if exists "Devotees read who is in a sanga" on public.sanga_members;
create policy "Devotees read who is in a sanga"
  on public.sanga_members for select to authenticated
  using (public.can_see_sanga(sanga_id));

-- A devotee sees their own asks; the admin sees the ones addressed to them.
drop policy if exists "Devotees read their own join requests" on public.sanga_join_requests;
create policy "Devotees read their own join requests"
  on public.sanga_join_requests for select to authenticated
  using (
    devotee_id = auth.uid()
    or public.is_sanga_admin(sanga_id)
    or public.has_permission('access.review_requests')
  );

revoke all on public.sangas from anon, authenticated;
revoke all on public.sanga_members from anon, authenticated;
revoke all on public.sanga_join_requests from anon, authenticated;

grant select on public.sangas to authenticated;
-- Creation, approval and handover go through RPCs so the name is trimmed, the
-- decision is stamped by the database, and a clash comes back as a sentence
-- rather than a constraint name.
grant update (name, description, active) on public.sangas to authenticated;
grant select on public.sanga_members to authenticated;
grant select on public.sanga_join_requests to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Notification kinds.
--
--    Eight, because a client that has to read the body text to know what
--    happened is a client that will get it wrong. Restated whole: a check
--    constraint cannot be added to in part.
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
      'sanga_admin_transferred',
      'remote'
    )
  );

-- ---------------------------------------------------------------------------
-- 5. Starting one.
--
--    Any signed-in devotee. The people who know that the temple needs a young
--    mothers' sanga are the young mothers, not the office.
-- ---------------------------------------------------------------------------

create or replace function public.create_sanga(
  p_name text,
  p_description text default null
)
returns public.sangas
language plpgsql
security definer
set search_path = ''
as $$
declare
  clean_name text;
  created public.sangas;
  founder_name text;
  reviewer record;
begin
  if auth.uid() is null then
    raise exception 'Sign in to start a sanga.';
  end if;

  clean_name := nullif(trim(coalesce(p_name, '')), '');
  if clean_name is null then
    raise exception 'Please give the sanga a name.';
  end if;

  insert into public.sangas (name, description, created_by, admin_id)
  values (
    clean_name,
    nullif(trim(coalesce(p_description, '')), ''),
    auth.uid(),
    auth.uid()
  )
  returning * into created;

  -- The founder is in their own circle from the first moment, and running it.
  -- A sanga is never adminless, not even for the minute before approval.
  insert into public.sanga_members (sanga_id, devotee_id, role)
  values (created.id, auth.uid(), 'admin');

  select name into founder_name from public.users where id = auth.uid();

  for reviewer in
    select distinct users.id
    from public.users
    join public.role_permissions
      on role_permissions.role_id = users.role_id
     and role_permissions.permission_key = 'access.review_requests'
    where users.id <> auth.uid()
  loop
    perform public.queue_app_notification(
      reviewer.id, 'sanga_created', 'A devotee proposed a new sanga',
      coalesce(founder_name, 'A devotee') || ' would like to start '
        || created.name || '.',
      jsonb_build_object('sangaId', created.id)
    );
  end loop;

  return created;
exception
  -- The clash may be with a sanga still waiting for approval, which the caller
  -- cannot see, so the message has to account for it rather than send them
  -- scrolling through a list it is not in.
  when unique_violation then
    raise exception 'A sanga called "%" already exists, or is waiting to be approved.', clean_name;
end;
$$;

revoke all on function public.create_sanga(text, text) from public, anon;
grant execute on function public.create_sanga(text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. The President decides whether the temple runs it.
-- ---------------------------------------------------------------------------

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
  if waiting.id is null then
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

revoke all on function public.review_sanga(uuid, text, text) from public, anon;
grant execute on function public.review_sanga(uuid, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 7. Browsing.
--
--    Definer, because the member count has to be the true count. Under the
--    caller's own rights it would be right today and wrong the moment anyone
--    narrows who may read a membership row, and a count that quietly drifts is
--    worse than no count at all.
--
--    request_status is what makes the button on the card say the right thing:
--    null means "Ask to join", pending means "Asked", declined means the admin
--    said no and the devotee may ask again.
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
  order by sangas.name
$$;

revoke all on function public.list_sangas() from public, anon;
grant execute on function public.list_sangas() to authenticated;

-- Everything the caller has a stake in, whatever its state — including the one
-- they proposed last night that nobody has looked at yet. Without this a
-- devotee who starts a sanga watches it vanish until the President wakes up.
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
    and (membership.devotee_id is not null or sangas.created_by = auth.uid())
  order by
    case when sangas.status = 'pending' then 0 else 1 end,
    sangas.name
$$;

revoke all on function public.list_my_sangas() from public, anon;
grant execute on function public.list_my_sangas() to authenticated;

-- The President's approval queue. Empty for everybody else rather than an
-- error: a screen they cannot reach should not need to handle one.
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
  order by sangas.created_at
$$;

revoke all on function public.list_pending_sangas() from public, anon;
grant execute on function public.list_pending_sangas() to authenticated;

-- ---------------------------------------------------------------------------
-- 8. Asking to join, and the admin answering.
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
  where id = p_sanga_id and status = 'approved' and active;
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

revoke all on function public.request_to_join_sanga(uuid, text) from public, anon;
grant execute on function public.request_to_join_sanga(uuid, text) to authenticated;

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

  if not public.is_sanga_admin(waiting.sanga_id) then
    raise exception 'Only the devotee who runs this sanga can answer requests to join it.';
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

revoke all on function public.review_sanga_join_request(uuid, text) from public, anon;
grant execute on function public.review_sanga_join_request(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 9. The admin adding and removing people directly.
--
--    Adding has no acceptance step, exactly as adding somebody to a group chat
--    has none. The devotee is told, which is the honest substitute, and they
--    can leave in one tap.
-- ---------------------------------------------------------------------------

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
  if not public.is_sanga_admin(p_sanga_id) then
    raise exception 'Only the devotee who runs this sanga can add somebody to it.';
  end if;

  select * into target from public.sangas
  where id = p_sanga_id and status = 'approved' and active;
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

revoke all on function public.add_sanga_member(uuid, uuid) from public, anon;
grant execute on function public.add_sanga_member(uuid, uuid) to authenticated;

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
  if not public.is_sanga_admin(p_sanga_id) then
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
      raise exception 'A sanga must always have somebody responsible for it. Hand "%" to another member before removing its admin.', target.name;
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

revoke all on function public.remove_sanga_member(uuid, uuid) from public, anon;
grant execute on function public.remove_sanga_member(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 10. Handing a sanga over, and leaving.
--
--     The rule: a sanga always has exactly one devotee responsible for it, and
--     the only way that person stops being responsible is by naming their
--     successor. So the last admin cannot leave and cannot be removed; they are
--     refused with a sentence that says what to do instead. Silently promoting
--     whoever happens to have been in the group longest would hand a stranger a
--     job they never agreed to, and a sanga with nobody to answer its requests
--     is worse than a sanga that is retired on purpose.
--
--     An admin who wants out and has nobody to hand to can retire the sanga —
--     that is theirs to do, under the update policy above.
-- ---------------------------------------------------------------------------

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
  if target.id is null then
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

revoke all on function public.transfer_sanga_admin(uuid, uuid) from public, anon;
grant execute on function public.transfer_sanga_admin(uuid, uuid) to authenticated;

create or replace function public.leave_sanga(p_sanga_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  target public.sangas;
  my_role text;
  admin_tally integer;
  removed integer;
  leaver_name text;
begin
  if auth.uid() is null then
    raise exception 'Sign in to leave a sanga.';
  end if;

  select role into my_role from public.sanga_members
  where sanga_members.sanga_id = p_sanga_id
    and sanga_members.devotee_id = auth.uid()
  for update;
  -- Nothing to leave is not an error. The boolean says whether this call was
  -- the one that did it.
  if my_role is null then
    return false;
  end if;

  select * into target from public.sangas where id = p_sanga_id;

  if my_role = 'admin' then
    select count(*)::integer into admin_tally from public.sanga_members
    where sanga_members.sanga_id = p_sanga_id and sanga_members.role = 'admin';
    if admin_tally <= 1 then
      raise exception 'You are the only devotee responsible for "%". Hand it to another member first, or retire the sanga.', target.name;
    end if;
  end if;

  delete from public.sanga_members
  where sanga_members.sanga_id = p_sanga_id
    and sanga_members.devotee_id = auth.uid();
  get diagnostics removed = row_count;

  delete from public.sanga_join_requests
  where sanga_join_requests.sanga_id = p_sanga_id
    and sanga_join_requests.devotee_id = auth.uid();

  select name into leaver_name from public.users where id = auth.uid();

  if target.admin_id is not null and target.admin_id <> auth.uid() then
    perform public.queue_app_notification(
      target.admin_id, 'sanga_member_left',
      'Someone left ' || target.name,
      coalesce(leaver_name, 'A devotee') || ' left ' || target.name || '.',
      jsonb_build_object('sangaId', target.id)
    );
  end if;

  return removed > 0;
end;
$$;

revoke all on function public.leave_sanga(uuid) from public, anon;
grant execute on function public.leave_sanga(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 11. Who is in a sanga, and who is asking.
--
--     Name and face only. Seeing that someone is in the kirtan sanga is the
--     whole point; their phone number is a matter for the directory, which has
--     its own rules about who may read what.
-- ---------------------------------------------------------------------------

create or replace function public.list_sanga_members(p_sanga_id uuid)
returns table (
  id uuid,
  name text,
  photo_url text,
  role text,
  joined_at timestamptz,
  added_by uuid,
  added_by_name text
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    devotee.id,
    devotee.name,
    devotee.photo_url,
    members.role,
    members.joined_at,
    members.added_by,
    adder.name
  from public.sanga_members members
  join public.users devotee on devotee.id = members.devotee_id
  left join public.users adder on adder.id = members.added_by
  where public.can_see_sanga(p_sanga_id)
    and members.sanga_id = p_sanga_id
  order by
    case when members.role = 'admin' then 0 else 1 end,
    devotee.name
$$;

revoke all on function public.list_sanga_members(uuid) from public, anon;
grant execute on function public.list_sanga_members(uuid) to authenticated;

-- The admin's inbox. Empty for everyone else, including ordinary members of
-- the same sanga: who asked and was turned down is the admin's business.
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
  where public.is_sanga_admin(p_sanga_id)
    and asked.sanga_id = p_sanga_id
  order by
    case when asked.status = 'pending' then 0 else 1 end,
    asked.created_at desc
$$;

revoke all on function public.list_sanga_join_requests(uuid) from public, anon;
grant execute on function public.list_sanga_join_requests(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 12. The thread.
--
--     A sanga is a group chat, so it is shaped like the direct-message thread
--     devotees already use: one row per message, pictures carried as a URL, and
--     a delete that keeps the row so the thread does not change shape under
--     everybody at once. What was said moves aside into original_body and
--     original_image_url, which sit outside the select grant held by client
--     roles — the same arrangement public.messages uses.
-- ---------------------------------------------------------------------------

create table if not exists public.sanga_messages (
  id uuid primary key default gen_random_uuid(),
  sanga_id uuid not null references public.sangas(id) on delete cascade,
  sender_id uuid not null references public.users(id) on delete cascade,
  body text,
  image_url text,
  created_at timestamptz not null default now(),
  deleted_at timestamptz,
  original_body text,
  original_image_url text,
  constraint sanga_message_has_content check (
    deleted_at is not null
    or nullif(trim(coalesce(body, '')), '') is not null
    or image_url is not null
  )
);

-- The thread is read newest-first and then reversed by the client, which is the
-- direction this index serves.
create index if not exists sanga_messages_sanga_idx
  on public.sanga_messages (sanga_id, created_at desc);

comment on column public.sanga_messages.original_body is
  'What body held before the message was deleted. Retained for the temple''s records, and outside the select grant held by client roles.';

comment on column public.sanga_messages.original_image_url is
  'What image_url held before the message was deleted. Retained on the same terms as original_body.';

alter table public.sanga_messages enable row level security;

drop policy if exists "Devotees read messages in their sangas" on public.sanga_messages;
create policy "Devotees read messages in their sangas"
  on public.sanga_messages for select to authenticated
  using (
    public.is_sanga_member(sanga_id)
    or public.has_permission('app.view_all')
  );

-- Every write goes through an RPC below, so nothing beyond reading is granted,
-- and the two retained columns are left out of that grant entirely. Column
-- grants are role-wide, which is what makes this hold: no query a devotee's
-- client can write reaches them, whatever the row filter says.
revoke all on public.sanga_messages from anon, authenticated;
grant select (
  id, sanga_id, sender_id, body, image_url, created_at, deleted_at
) on public.sanga_messages to authenticated;

-- A filtered postgres_changes subscription on a table with row level security
-- cannot evaluate its filter from the default replica identity, which carries
-- only the primary key: the change then arrives late, or not at all. This is
-- the omission that made direct messages appear only on the next poll, fixed
-- in 202608040035_messaging_realtime.sql, and it is not repeated here.
alter table public.sanga_messages replica identity full;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'sanga_messages'
    ) then
      alter publication supabase_realtime add table public.sanga_messages;
    end if;
  end if;
end;
$$;

-- Pictures go into the message-images bucket that direct messages already use.
-- A second bucket would mean a second upload policy, a second size limit and a
-- second thing to forget, for images that are the same kind of thing.

-- ---------------------------------------------------------------------------
-- 13. Posting, reading and deleting.
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
  if not public.is_sanga_member(p_sanga_id) then
    raise exception 'Only devotees in this sanga can post in it.';
  end if;

  -- A circle the temple has not agreed to run, or has retired, has no thread.
  select * into target from public.sangas
  where id = p_sanga_id and status = 'approved' and active;
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

revoke all on function public.send_sanga_message(uuid, text, text) from public, anon;
grant execute on function public.send_sanga_message(uuid, text, text) to authenticated;

-- Oldest first, because a thread is read in the order it was said. Deleted rows
-- come back with deleted_at set and nothing in them, which is what lets the
-- client draw "This message was deleted" in the right place.
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
    and (
      public.is_sanga_member(p_sanga_id)
      or public.has_permission('app.view_all')
    )
  order by sanga_messages.created_at
$$;

revoke all on function public.list_sanga_messages(uuid) from public, anon;
grant execute on function public.list_sanga_messages(uuid) to authenticated;

-- Two people may take a message down: whoever said it, and whoever runs the
-- sanga it was said in. That is the pair a group chat needs — one to retract
-- their own words, one to keep the room usable.
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
     and not public.is_sanga_admin(target.sanga_id) then
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

revoke all on function public.delete_sanga_message(uuid) from public, anon;
grant execute on function public.delete_sanga_message(uuid) to authenticated;

do $$
begin
  raise notice 'sangas applied';
end;
$$;
