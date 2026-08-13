-- Appointing access directly, and keeping a record of who gave it.
--
-- Until now the only way up the ladder was for the devotee to ask:
-- create_access_request, then somebody answers it. That is the right flow for
-- a devotee who wants more responsibility, and it stays exactly as it is. It
-- is the wrong flow for the temple, because the temple does not wait to be
-- asked. A Community Head who has watched somebody run the Sunday kitchen for
-- a year appoints them; they do not send them away to fill in a form so that
-- the form can be approved.
--
-- So this adds the other direction — appointment and revocation — and one
-- thing the request flow never had: a record.
--
--   Who may appoint            President, Tech Admin, Community Head
--                              (services.manage_recurring, which is held by
--                              exactly core, tech and president — the same
--                              predicate this database already means when it
--                              says "coordinator").
--
--   What may be appointed      Volunteer, Community Head. Nothing else.
--                              President and Tech Admin are set out of band,
--                              in the database, by somebody with the keys.
--
--   Who may take it back       President and Tech Admin, from anybody.
--                              A Community Head, only from somebody they
--                              appointed themselves.
--
-- That last rule is the reason this migration has a table rather than a
-- column. "Only what you granted yourself" is a question about the past, and
-- a role_id on public.users cannot answer it: it knows what somebody is, never
-- who made them that. public.access_appointments is the answer — one row per
-- grant, kept after it ends rather than overwritten, so a Community Head
-- revoked in March is still visibly the person who appointed somebody in
-- January.
--
-- A grant ends in one of two ways, and the difference matters to whoever reads
-- the history later:
--
--   revoked      somebody deliberately took the access back. The devotee is a
--                Devotee again.
--   superseded   the grant was replaced by another one — a Volunteer made a
--                Community Head. Nothing was taken away; a bigger grant simply
--                stands in front of the old one.
--
-- Who can see the record: Community Heads, the President, the Tech Admin. Not
-- the congregation, and deliberately not even the devotee themselves. "Which
-- Community Head signed off on Radha's Volunteer access" is a question about
-- how the temple is run, and answering it to everybody turns every appointment
-- into something the appointer has to defend in the car park.
--
-- Requires 202608040045_newsletter.sql (kind list) and
-- 202608040031_access_approver.sql (the request flow this extends).

-- ---------------------------------------------------------------------------
-- 1. The record.
--
--    role_id rather than a role name: the name is already normalised into
--    public.roles and a text copy is one rename away from lying. appointed_by
--    and revoked_by are `on delete set null` for the same reason
--    newsletter_editors.appointed_by is — the history of the temple should
--    outlive an account being deleted, with the attribution lost rather than
--    the whole row.
--
--    One live grant at a time, enforced by a partial unique index. Without it
--    "who appointed them" has no single answer the moment two coordinators act
--    in the same minute, and every reader would have to guess which row wins.
-- ---------------------------------------------------------------------------

create table if not exists public.access_appointments (
  id uuid primary key default gen_random_uuid(),
  devotee_id uuid not null references public.users(id) on delete cascade,
  role_id uuid not null references public.roles(id),
  appointed_by uuid references public.users(id) on delete set null,
  appointed_at timestamptz not null default now(),
  note text,
  revoked_by uuid references public.users(id) on delete set null,
  revoked_at timestamptz,
  revoke_note text,
  revoke_reason text check (revoke_reason in ('revoked', 'superseded')),
  -- How the grant came about, so an approved request and a direct appointment
  -- can be told apart in the same list without joining anything.
  source text not null default 'appointment' check (
    source in ('appointment', 'request', 'backfill')
  ),
  access_request_id uuid references public.access_requests(id) on delete set null,
  -- A grant is live or it has ended; an end always says why.
  constraint access_appointment_end_consistency check (
    (revoked_at is null and revoke_reason is null)
    or (revoked_at is not null and revoke_reason is not null)
  ),
  -- revoked_by may be null on a live grant, and may become null when the
  -- account that ended it is deleted — but it can never appear on a grant that
  -- has not ended.
  constraint access_appointment_revoker_needs_an_end check (
    revoked_by is null or revoked_at is not null
  )
);

comment on table public.access_appointments is
  'Every Volunteer or Community Head grant this temple has made: who gave it, when, who took it back. History, not current state — public.users.role_id is the current state.';
comment on column public.access_appointments.revoke_reason is
  '"revoked" — somebody took the access back. "superseded" — a later grant replaced this one.';
comment on column public.access_appointments.source is
  '"appointment" — given directly. "request" — the devotee asked and it was approved. "backfill" — held before this migration, grantor unknown.';

create unique index if not exists one_live_access_appointment_per_devotee
  on public.access_appointments (devotee_id)
  where revoked_at is null;

create index if not exists access_appointments_devotee_idx
  on public.access_appointments (devotee_id, appointed_at desc);

create index if not exists access_appointments_appointed_by_idx
  on public.access_appointments (appointed_by)
  where revoked_at is null;

-- ---------------------------------------------------------------------------
-- 2. What is already there.
--
--    Everybody holding Volunteer or Community Head today got it somehow, and
--    the record would be a lie if it started empty — every existing coordinator
--    would look unappointed, and revoke_access would have nothing to close.
--
--    Where an approved access_request explains the access, that request's
--    reviewer is the appointer and its review is the date, which is exactly
--    what rule 3 below says an approval means. Where nothing explains it (the
--    first President, anybody set by hand before this file), the grant is
--    recorded with no appointer: source 'backfill', appointed_by null. That is
--    the honest answer, and it has a useful consequence — a Community Head can
--    never revoke a grant nobody is recorded as having made, because it is not
--    theirs.
-- ---------------------------------------------------------------------------

insert into public.access_appointments (
  devotee_id, role_id, appointed_by, appointed_at, source, access_request_id
)
select
  congregant.id,
  congregant.role_id,
  approved.reviewed_by,
  coalesce(approved.reviewed_at, congregant.joined_at, now()),
  case when approved.id is null then 'backfill' else 'request' end,
  approved.id
from public.users congregant
join public.roles held on held.id = congregant.role_id
 and held.name in ('volunteer', 'core')
left join lateral (
  select request.id, request.reviewed_by, request.reviewed_at
  from public.access_requests request
  where request.requester_id = congregant.id
    and request.status = 'approved'
    and request.requested_role_id = congregant.role_id
  order by request.reviewed_at desc nulls last
  limit 1
) approved on true
where not exists (
  select 1 from public.access_appointments existing
  where existing.devotee_id = congregant.id
    and existing.revoked_at is null
);

-- ---------------------------------------------------------------------------
-- 3. Who may work the ladder at all.
--
--    One predicate, read by every guard below, so the RPCs and the row level
--    security policy cannot drift apart about who counts as a coordinator.
--    services.manage_recurring is held by core, tech and president and by
--    nothing else (202608020001_access_levels.sql) — a Volunteer is not a
--    coordinator and must not become one by standing next to this feature.
-- ---------------------------------------------------------------------------

create or replace function public.may_appoint_access()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is not null
     and public.has_permission('services.manage_recurring')
$$;

revoke all on function public.may_appoint_access() from public, anon;
grant execute on function public.may_appoint_access() to authenticated;

-- Where each rung sits, so "is this a promotion or a demotion" is one
-- comparison rather than a case expression repeated in three places.
create or replace function public.access_level_rank(p_role_name text)
returns integer
language sql
immutable
set search_path = ''
as $$
  select case p_role_name
    when 'devotee' then 0
    when 'volunteer' then 1
    when 'core' then 2
    -- Above the ladder this file may touch at all.
    when 'tech' then 3
    when 'president' then 3
    else -1
  end
$$;

revoke all on function public.access_level_rank(text) from public, anon;
grant execute on function public.access_level_rank(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Writing a grant down.
--
--    Shared by direct appointment and by an approved request, because rule 3
--    of the brief — "an approval counts as an appointment by the reviewer" —
--    is only true if both doors write the same row the same way. Internal:
--    it takes the actor as an argument and checks nothing, so it is revoked
--    from every client role and reachable only from the guarded functions
--    below.
-- ---------------------------------------------------------------------------

create or replace function public.record_access_appointment(
  p_devotee_id uuid,
  p_role_id uuid,
  p_actor uuid,
  p_note text default null,
  p_source text default 'appointment',
  p_access_request_id uuid default null
)
returns public.access_appointments
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_grant public.access_appointments;
begin
  -- The grant standing in front of it, if any, ends here. Not "revoked":
  -- nothing was taken away from the devotee, a newer grant simply replaced it.
  update public.access_appointments
  set revoked_at = now(),
      revoked_by = p_actor,
      revoke_reason = 'superseded'
  where access_appointments.devotee_id = p_devotee_id
    and access_appointments.revoked_at is null;

  insert into public.access_appointments (
    devotee_id, role_id, appointed_by, note, source, access_request_id
  )
  values (
    p_devotee_id,
    p_role_id,
    p_actor,
    nullif(trim(coalesce(p_note, '')), ''),
    p_source,
    p_access_request_id
  )
  returning * into v_grant;

  update public.users
  set role_id = p_role_id
  where users.id = p_devotee_id;

  return v_grant;
end;
$$;

revoke all on function public.record_access_appointment(uuid, uuid, uuid, text, text, uuid)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 5. Appointing.
--
--    The refusals, in the order they are checked, and why each one exists:
--
--      not signed in            nothing else can be decided.
--      not a coordinator        a Volunteer and a plain devotee are shut out.
--      yourself                 the whole point of a ladder is that somebody
--                               else puts you on it. Without this, one
--                               Community Head is one call away from being
--                               able to appoint anybody to anything forever.
--      president / tech         as a destination, because those two are set
--                               out of band; and as a *target*, because
--                               "appoint the President to Volunteer" is a
--                               demotion of an office holder wearing a
--                               promotion's clothes.
--      lowering somebody else's grant, as a Community Head
--                               revocation by another name. A Head who could
--                               move another Head's Community Head down to
--                               Volunteer has revoked most of that grant while
--                               the rule said they could not revoke it at all.
--
--    Idempotent where it can be: appointing somebody who already holds that
--    exact grant hands back the grant as it stands, keeping the original date.
--    A coordinator who cannot remember whether they already did it should be
--    able to find out by doing it, rather than be told off — and the date the
--    temple wants to see is the day they were first asked.
-- ---------------------------------------------------------------------------

create or replace function public.appoint_access(
  p_devotee_id uuid,
  p_role_name text,
  p_note text default null
)
returns public.access_appointments
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role public.roles;
  v_current_role_name text;
  v_devotee_name text;
  v_actor_name text;
  v_live public.access_appointments;
  v_grant public.access_appointments;
  v_label text;
  v_coordinator record;
begin
  if auth.uid() is null then
    raise exception 'Sign in to change access levels.';
  end if;

  if not public.may_appoint_access() then
    raise exception 'Only a Community Head, the President or the Tech Admin can change access levels.';
  end if;

  if p_devotee_id is null then
    raise exception 'Choose a devotee to appoint.';
  end if;

  if p_devotee_id = auth.uid() then
    raise exception 'You cannot change your own access level.';
  end if;

  if p_role_name is null or p_role_name not in ('volunteer', 'core') then
    raise exception 'Access can only be given as Volunteer or Community Head.';
  end if;

  select * into v_role from public.roles where roles.name = p_role_name;
  if v_role.id is null then
    raise exception 'Access can only be given as Volunteer or Community Head.';
  end if;

  select congregant.name, held.name
    into v_devotee_name, v_current_role_name
  from public.users congregant
  join public.roles held on held.id = congregant.role_id
  where congregant.id = p_devotee_id
  for update of congregant;

  if v_devotee_name is null then
    raise exception 'That devotee could not be found.';
  end if;

  if v_current_role_name in ('president', 'tech') then
    raise exception 'The President and Tech Admin access levels are set outside the app.';
  end if;

  select * into v_live
  from public.access_appointments
  where access_appointments.devotee_id = p_devotee_id
    and access_appointments.revoked_at is null
  for update;

  -- Already exactly this. Hand back what is there.
  if v_live.id is not null
     and v_live.role_id = v_role.id
     and v_current_role_name = p_role_name
  then
    return v_live;
  end if;

  -- A Community Head — anybody who may appoint but may not review access —
  -- can raise somebody, and can lower only what they granted themselves.
  if not public.has_permission('access.review_requests')
     and public.access_level_rank(p_role_name)
         < public.access_level_rank(v_current_role_name)
     and (v_live.id is null or v_live.appointed_by is distinct from auth.uid())
  then
    raise exception 'A Community Head can only lower access they granted themselves.';
  end if;

  v_grant := public.record_access_appointment(
    p_devotee_id, v_role.id, auth.uid(), p_note, 'appointment', null
  );

  select users.name into v_actor_name from public.users where users.id = auth.uid();
  v_label := public.access_level_label(p_role_name);

  perform public.queue_app_notification(
    p_devotee_id, 'access_appointed', 'Your access level changed',
    coalesce(v_actor_name, 'A coordinator') || ' made you ' || v_label || '.',
    jsonb_build_object(
      'appointmentId', v_grant.id, 'devoteeId', p_devotee_id, 'roleName', p_role_name
    )
  );

  -- An access level changing is temple business, so the other coordinators are
  -- told who granted it rather than discovering it later. Same audience, same
  -- reasoning as review_access_request in 202608040031_access_approver.sql.
  for v_coordinator in
    select distinct users.id
    from public.users
    join public.role_permissions
      on role_permissions.role_id = users.role_id
     and role_permissions.permission_key = 'services.manage_recurring'
    where users.id <> auth.uid()
      and users.id <> p_devotee_id
  loop
    perform public.queue_app_notification(
      v_coordinator.id, 'access_appointed', 'An access level changed',
      coalesce(v_actor_name, 'A coordinator') || ' made '
        || coalesce(v_devotee_name, 'a devotee') || ' ' || v_label || '.',
      jsonb_build_object(
        'appointmentId', v_grant.id, 'devoteeId', p_devotee_id, 'roleName', p_role_name
      )
    );
  end loop;

  return v_grant;
end;
$$;

revoke all on function public.appoint_access(uuid, text, text) from public, anon;
grant execute on function public.appoint_access(uuid, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. Taking it back.
--
--    Always to Devotee. There is no "demote a Community Head to Volunteer"
--    here — that is an appointment, and it goes through appoint_access where
--    the Community-Head-only-their-own rule is applied to it.
--
--    A Community Head may only revoke a grant they made. Somebody holding
--    access from before this record existed has appointed_by null, so no
--    Community Head owns it and only the President or Tech Admin can take it
--    back — which is the safe direction for a question the database cannot
--    answer.
-- ---------------------------------------------------------------------------

create or replace function public.revoke_access(
  p_devotee_id uuid,
  p_note text default null
)
returns public.access_appointments
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_current_role_name text;
  v_devotee_name text;
  v_actor_name text;
  v_devotee_role_id uuid;
  v_live public.access_appointments;
  v_ended public.access_appointments;
  v_coordinator record;
begin
  if auth.uid() is null then
    raise exception 'Sign in to change access levels.';
  end if;

  if not public.may_appoint_access() then
    raise exception 'Only a Community Head, the President or the Tech Admin can change access levels.';
  end if;

  if p_devotee_id is null then
    raise exception 'Choose a devotee.';
  end if;

  if p_devotee_id = auth.uid() then
    raise exception 'You cannot change your own access level.';
  end if;

  select congregant.name, held.name
    into v_devotee_name, v_current_role_name
  from public.users congregant
  join public.roles held on held.id = congregant.role_id
  where congregant.id = p_devotee_id
  for update of congregant;

  if v_devotee_name is null then
    raise exception 'That devotee could not be found.';
  end if;

  if v_current_role_name in ('president', 'tech') then
    raise exception 'The President and Tech Admin access levels are set outside the app.';
  end if;

  if v_current_role_name = 'devotee' then
    raise exception 'That devotee is already at the Devotee access level.';
  end if;

  select * into v_live
  from public.access_appointments
  where access_appointments.devotee_id = p_devotee_id
    and access_appointments.revoked_at is null
  for update;

  if not public.has_permission('access.review_requests')
     and (v_live.id is null or v_live.appointed_by is distinct from auth.uid())
  then
    raise exception 'A Community Head can only take back access they granted themselves.';
  end if;

  select roles.id into v_devotee_role_id from public.roles where roles.name = 'devotee';

  if v_live.id is not null then
    update public.access_appointments
    set revoked_at = now(),
        revoked_by = auth.uid(),
        revoke_reason = 'revoked',
        revoke_note = nullif(trim(coalesce(p_note, '')), '')
    where access_appointments.id = v_live.id
    returning * into v_ended;
  else
    -- Access with no grant behind it: only the President or the Tech Admin
    -- reach here, and the revocation is still written down rather than being
    -- the one access change the record cannot see.
    insert into public.access_appointments (
      devotee_id, role_id, appointed_by, source,
      revoked_at, revoked_by, revoke_reason, revoke_note
    )
    select
      p_devotee_id, congregant.role_id, null, 'backfill',
      now(), auth.uid(), 'revoked', nullif(trim(coalesce(p_note, '')), '')
    from public.users congregant
    where congregant.id = p_devotee_id
    returning * into v_ended;
  end if;

  update public.users
  set role_id = v_devotee_role_id
  where users.id = p_devotee_id;

  select users.name into v_actor_name from public.users where users.id = auth.uid();

  perform public.queue_app_notification(
    p_devotee_id, 'access_revoked', 'Your access level changed',
    coalesce(v_actor_name, 'A coordinator')
      || ' returned your access to Devotee.',
    jsonb_build_object(
      'appointmentId', v_ended.id, 'devoteeId', p_devotee_id, 'roleName', 'devotee'
    )
  );

  for v_coordinator in
    select distinct users.id
    from public.users
    join public.role_permissions
      on role_permissions.role_id = users.role_id
     and role_permissions.permission_key = 'services.manage_recurring'
    where users.id <> auth.uid()
      and users.id <> p_devotee_id
  loop
    perform public.queue_app_notification(
      v_coordinator.id, 'access_revoked', 'An access level changed',
      coalesce(v_actor_name, 'A coordinator') || ' returned '
        || coalesce(v_devotee_name, 'a devotee') || ' to Devotee.',
      jsonb_build_object(
        'appointmentId', v_ended.id, 'devoteeId', p_devotee_id, 'roleName', 'devotee'
      )
    );
  end loop;

  return v_ended;
end;
$$;

revoke all on function public.revoke_access(uuid, text) from public, anon;
grant execute on function public.revoke_access(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 7. Approving a request is an appointment.
--
--    Identical to 202608040031_access_approver.sql in every other respect —
--    same signature, same guards, same notifications, so nothing that calls it
--    today changes — except that the approval now writes the same row a direct
--    appointment writes, attributed to the reviewer. Without this the record
--    would be blind to the older half of the feature, and "who gave Radha
--    Volunteer access" would answer "nobody" for everybody who asked for it.
--
--    The role change itself moves inside record_access_appointment, so there
--    is exactly one statement in this database that writes users.role_id for
--    an appointment and exactly one place a grant can be born.
-- ---------------------------------------------------------------------------

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
    perform public.record_access_appointment(
      pending_request.requester_id,
      pending_request.requested_role_id,
      auth.uid(),
      p_note,
      'request',
      pending_request.id
    );
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

-- ---------------------------------------------------------------------------
-- 8. Reading the record.
--
--    p_devotee_id defaults to null, meaning everybody — one function for "the
--    history of this devotee" and for "every access change the temple has
--    made", because they are the same list with a different filter and a
--    second function would be a second place for the gate to be got wrong.
--
--    Empty rather than an exception for anybody else. This backs a screen, and
--    a screen that throws on open is a crash; a Volunteer opening a devotee's
--    profile simply sees no history section.
--
--    can_revoke travels with each row so the client can decide whether to draw
--    the button without reimplementing the ladder rules in TypeScript.
-- ---------------------------------------------------------------------------

drop function if exists public.list_access_appointments(uuid);

create or replace function public.list_access_appointments(
  p_devotee_id uuid default null
)
returns table (
  id uuid,
  devotee_id uuid,
  devotee_name text,
  devotee_photo_url text,
  role_name text,
  role_label text,
  appointed_by uuid,
  appointed_by_name text,
  appointed_at timestamptz,
  note text,
  revoked_by uuid,
  revoked_by_name text,
  revoked_at timestamptz,
  revoke_note text,
  revoke_reason text,
  source text,
  access_request_id uuid,
  is_active boolean,
  can_revoke boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    grants.id,
    grants.devotee_id,
    congregant.name,
    congregant.photo_url,
    granted.name,
    public.access_level_label(granted.name),
    grants.appointed_by,
    appointer.name,
    grants.appointed_at,
    grants.note,
    grants.revoked_by,
    revoker.name,
    grants.revoked_at,
    grants.revoke_note,
    grants.revoke_reason,
    grants.source,
    grants.access_request_id,
    grants.revoked_at is null,
    grants.revoked_at is null
      and grants.devotee_id <> auth.uid()
      and (
        public.has_permission('access.review_requests')
        or grants.appointed_by = auth.uid()
      )
  from public.access_appointments grants
  join public.users congregant on congregant.id = grants.devotee_id
  join public.roles granted on granted.id = grants.role_id
  left join public.users appointer on appointer.id = grants.appointed_by
  left join public.users revoker on revoker.id = grants.revoked_by
  where public.may_appoint_access()
    and (p_devotee_id is null or grants.devotee_id = p_devotee_id)
  order by grants.appointed_at desc, grants.id
$$;

comment on function public.list_access_appointments(uuid) is
  'Who granted a devotee their access and who took it back. Community Heads, the President and the Tech Admin only; empty for everybody else.';

revoke all on function public.list_access_appointments(uuid) from public, anon;
grant execute on function public.list_access_appointments(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 9. What the congregation view shows: who granted a devotee's access today.
--
--    A companion rather than three more columns on list_devotee_profiles, and
--    the reason is worth writing down because the obvious move is the wrong
--    one here.
--
--    supabase/verification/birthdays_and_congregation.sql pins that function's
--    result shape — it asserts, by regular expression, that sanga_names is the
--    last column, precisely so that nobody appends a field in the middle and
--    hands a client reading by position the wrong value. Widening the function
--    would mean editing that script, which belongs to another migration, to
--    make room. The pin is doing its job; the answer is not to file it down.
--
--    Two functions is also the better shape on its own terms. The audiences
--    genuinely differ: list_devotee_profiles is app.view_all, meaning the
--    President and the Tech Admin, while the access record is visible to
--    Community Heads as well. Folding the grant into a president-only function
--    would have left Heads with a congregation list they can read and a grant
--    column they cannot, or widened list_devotee_profiles to an audience it was
--    never written for.
--
--    One row per devotee who holds a grant today, so the client joins it to
--    the congregation list by devotee_id. Devotees with no live grant are
--    simply absent.
-- ---------------------------------------------------------------------------

drop function if exists public.list_devotee_access_grants(uuid);

create or replace function public.list_devotee_access_grants(
  p_devotee_id uuid default null
)
returns table (
  devotee_id uuid,
  devotee_name text,
  role_name text,
  role_label text,
  appointed_by uuid,
  appointed_by_name text,
  appointed_at timestamptz,
  note text,
  source text,
  access_request_id uuid
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    grants.devotee_id,
    congregant.name,
    granted.name,
    public.access_level_label(granted.name),
    grants.appointed_by,
    appointer.name,
    grants.appointed_at,
    grants.note,
    grants.source,
    grants.access_request_id
  from public.access_appointments grants
  join public.users congregant on congregant.id = grants.devotee_id
  join public.roles granted on granted.id = grants.role_id
  left join public.users appointer on appointer.id = grants.appointed_by
  where grants.revoked_at is null
    and public.may_appoint_access()
    and (p_devotee_id is null or grants.devotee_id = p_devotee_id)
  order by congregant.name
$$;

comment on function public.list_devotee_access_grants(uuid) is
  'Who granted each devotee the access they hold today, to sit beside list_devotee_profiles. Community Heads, the President and the Tech Admin only.';

revoke all on function public.list_devotee_access_grants(uuid) from public, anon;
grant execute on function public.list_devotee_access_grants(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 10. Row level security.
--
--     Same audience as the function, stated again at the table, because a
--     client using PostgREST goes straight at the table and would otherwise
--     read the whole history of every appointment the temple has ever made.
--     No insert, update or delete policy and no write grant: the record is
--     written by the security-definer functions above and by nothing else.
-- ---------------------------------------------------------------------------

alter table public.access_appointments enable row level security;

drop policy if exists "Coordinators read the access record" on public.access_appointments;
create policy "Coordinators read the access record"
  on public.access_appointments for select
  to authenticated
  using (public.may_appoint_access());

revoke all on public.access_appointments from anon, authenticated;
grant select (
  id, devotee_id, role_id, appointed_by, appointed_at, note,
  revoked_by, revoked_at, revoke_note, revoke_reason, source, access_request_id
) on public.access_appointments to authenticated;

-- ---------------------------------------------------------------------------
-- 11. The notification kinds.
--
--     Restated whole from 202608040045_newsletter.sql, the most recent
--     migration to touch this constraint, plus the two added here. The
--     constraint cannot be altered in place, only dropped and recreated, so a
--     migration that restates it from an older copy silently outlaws every kind
--     added since — which has broken this database four times.
--
--     Two kinds rather than reusing access_request_reviewed: that kind carries
--     an accessRequestId and its whole meaning is "the thing you asked for was
--     answered". An appointment answers nothing the devotee asked for, and its
--     payload is an appointmentId. A client switching on kind would have to
--     open the payload to find out which of two unrelated screens to route to.
--     Revocation is separated from appointment for the same reason: the two
--     messages need different words, a different icon and, one day, a different
--     tone of push notification.
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
      'birthday_today',
      'newsletter_posted',
      'newsletter_reviewed',
      'access_appointed',
      'access_revoked',
      'remote'
    )
  );

do $$
begin
  raise notice 'access appointments applied';
end;
$$;
