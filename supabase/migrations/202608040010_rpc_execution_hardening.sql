-- RPC execution hardening.
-- Requires 202608030009_weekly_seva_visibility_and_coverage.sql.
--
-- WHY THIS MIGRATION EXISTS
--
-- Every earlier migration protected its functions with
--   revoke all on function public.x(...) from public;
--   grant execute on function public.x(...) to authenticated;
--
-- That pattern does NOT stop the `anon` role. Supabase ships default
-- privileges that grant EXECUTE on every function created in `public`
-- directly to `anon` and `authenticated`. Revoking from the PUBLIC
-- pseudo-role never removes that direct grant, so every RPC in this project
-- has been callable with nothing but the publishable key -- which ships
-- inside the app binary and is therefore public.
--
-- Verified against the live project before writing this file:
--   POST /rest/v1/rpc/notify_service_oversight   -> 200, inserted a row
--   POST /rest/v1/rpc/queue_app_notification     -> 23503 (reached the INSERT)
--   POST /rest/v1/rpc/complete_due_service_sessions -> 200
--   POST /rest/v1/rpc/finalize_service_session_internal -> 200
--   POST /rest/v1/rpc/refresh_service_instance_capacity -> 204
--
-- Most user-facing RPCs survived only because each one re-checks auth.uid()
-- internally. The internal helpers do not, so they were fully exposed.
--
-- This migration closes the hole in three layers:
--   1. remove EXECUTE from `anon` on everything, now and for future functions
--   2. remove EXECUTE from `authenticated` on internal-only helpers
--   3. add an explicit caller check inside the helpers that stay reachable

-- ---------------------------------------------------------------------------
-- 1. `anon` loses execute on the whole schema, permanently.
-- ---------------------------------------------------------------------------

revoke execute on all functions in schema public from anon;

alter default privileges in schema public
  revoke execute on functions from anon;

-- ---------------------------------------------------------------------------
-- 2. Internal helpers are not client entry points. They are invoked from
--    inside SECURITY DEFINER functions, which run as the function owner and
--    therefore do not need a grant to the calling role.
-- ---------------------------------------------------------------------------

revoke execute on function public.queue_app_notification(uuid, text, text, text, jsonb) from authenticated;
revoke execute on function public.notify_service_oversight(text, text, text, jsonb, uuid) from authenticated;
revoke execute on function public.refresh_service_instance_capacity(uuid) from authenticated;
revoke execute on function public.finalize_service_session_internal(uuid, boolean) from authenticated;
revoke execute on function public.generate_service_instances(integer) from authenticated;
revoke execute on function public.service_instance_name(public.service_instances) from authenticated;
revoke execute on function public.service_session_name(public.service_qr_sessions) from authenticated;
revoke execute on function public.can_request_access_role(uuid, uuid) from authenticated;
revoke execute on function public.start_service_session(uuid, text, text, timestamptz, timestamptz, text) from authenticated;

-- Superseded entry points the client no longer calls. Retrospective
-- self-logging stays disabled (see spec section 6).
revoke execute on function public.log_completed_service(uuid, text, date, time, integer) from authenticated;
revoke execute on function public.create_service_template(uuid, integer, time, integer, integer, text, date, date, uuid[]) from authenticated;
revoke execute on function public.cancel_qr_service_session(uuid) from authenticated;
revoke execute on function public.complete_qr_service_session(uuid) from authenticated;
revoke execute on function public.cancel_service_instance(uuid) from authenticated;
revoke execute on function public.add_service_type(text, text) from authenticated;

-- ---------------------------------------------------------------------------
-- 3. Defence in depth: the helpers that remain reachable now refuse an
--    anonymous caller even if a future grant re-opens them.
-- ---------------------------------------------------------------------------

create or replace function public.queue_app_notification(
  p_user_id uuid,
  p_kind text,
  p_title text,
  p_body text,
  p_data jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  notification_id uuid;
begin
  if auth.uid() is null and current_user not in ('postgres', 'supabase_admin') then
    raise exception 'Authentication is required.';
  end if;

  insert into public.app_notifications (user_id, kind, title, body, data)
  values (p_user_id, p_kind, p_title, p_body, coalesce(p_data, '{}'::jsonb))
  returning id into notification_id;

  return notification_id;
end;
$$;

create or replace function public.complete_due_service_sessions()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  due_session record;
  completed_count integer := 0;
begin
  if auth.uid() is null then
    raise exception 'Authentication is required.';
  end if;

  for due_session in
    select id
    from public.service_qr_sessions
    where status = 'active' and planned_end_at <= now()
    order by planned_end_at
    for update skip locked
  loop
    perform public.finalize_service_session_internal(due_session.id, true);
    completed_count := completed_count + 1;
  end loop;

  return completed_count;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3b. CRITICAL: Devotees and Volunteers cannot finish a live seva timer.
--
--     `enforce_service_need_access` (0009:21-40) fires BEFORE INSERT on
--     service_instances and rejects any row where the poster is the caller,
--     participation_mode is not 'open', and the caller lacks
--     services.offer_assignment.
--
--     finalize_service_session_internal (0008) records a finished timer by
--     inserting exactly such a row -- participation_mode 'invite_only',
--     posted_by = the devotee. So the trigger fires on the devotee's own
--     completion and aborts it.
--
--     Reproduced on the Android emulator against the live project: signed in
--     as a Devotee, started a live seva, tapped "Finish this seva" and got
--     "The seva timer could not be updated." Cancelling worked, because
--     cancellation never inserts a service_instances row.
--
--     The trigger is only meant to stop a Volunteer from posting an
--     invite-only *need*. A need is always created with status 'open', while
--     a finished-seva record is inserted as 'completed'. Scoping the check to
--     open rows restores completion without weakening the rule.
-- ---------------------------------------------------------------------------

create or replace function public.enforce_service_need_access()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'open'
    and new.posted_by = auth.uid()
    and new.participation_mode <> 'open'
    and not public.has_permission('services.offer_assignment')
  then
    raise exception 'Your access level can post open service needs only.';
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. A volunteer lost `services.offer_assignment` in migration 0009, but
--    create_service_requirement never checked it before writing the invitee
--    offers in p_invitee_ids. A volunteer could therefore still send targeted
--    invitations by posting an "open" need with a non-empty invitee array.
-- ---------------------------------------------------------------------------

create or replace function public.create_service_requirement(
  p_service_type_id uuid,
  p_custom_name text,
  p_date date,
  p_start_time time,
  p_duration_minutes integer,
  p_slots_needed integer,
  p_participation_mode text,
  p_invitee_ids uuid[]
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  created_instance public.service_instances;
  invitee_id uuid;
  created_offer_id uuid;
  coordinator_name text;
  display_name text;
begin
  if not public.has_permission('services.post_requirement') then
    raise exception 'You are not allowed to post service requirements.';
  end if;

  if coalesce(cardinality(p_invitee_ids), 0) > 0
    and not public.has_permission('services.offer_assignment')
  then
    raise exception 'Your access level can post open service needs only.';
  end if;

  if p_date < (now() at time zone 'America/Chicago')::date then
    raise exception 'A service requirement cannot be posted in the past.';
  end if;

  if p_duration_minutes < 30 or p_duration_minutes > 720
    or p_duration_minutes % 30 <> 0
  then
    raise exception 'Duration must use 30-minute increments.';
  end if;

  if p_slots_needed < 1 or p_slots_needed > 100 then
    raise exception 'Slots needed must be between 1 and 100.';
  end if;

  if p_participation_mode not in ('open', 'invite_only') then
    raise exception 'Choose open or invite-only participation.';
  end if;

  if (p_service_type_id is null) = (nullif(trim(p_custom_name), '') is null) then
    raise exception 'Choose a catalog service or enter one custom name.';
  end if;

  if p_service_type_id is not null and not exists (
    select 1 from public.service_types
    where id = p_service_type_id and is_active
  ) then
    raise exception 'The selected service is not available.';
  end if;

  insert into public.service_instances (
    service_type_id, custom_name, date, start_time, duration_minutes,
    slots_needed, participation_mode, posted_by, status
  )
  values (
    p_service_type_id, nullif(trim(p_custom_name), ''), p_date, p_start_time,
    p_duration_minutes, p_slots_needed, p_participation_mode, auth.uid(), 'open'
  )
  returning * into created_instance;

  select name into coordinator_name
  from public.users
  where id = auth.uid();

  display_name := public.service_instance_name(created_instance);

  if p_participation_mode = 'open' then
    insert into public.app_notifications (user_id, kind, title, body, data)
    select
      users.id,
      'service_open',
      'Seva help requested',
      coordinator_name || ' posted "' || display_name || '" for ' ||
        to_char(created_instance.date, 'FMDay, FMMonth FMDD') || ' at ' ||
        to_char(created_instance.start_time, 'FMHH12:MI AM') || '.',
      jsonb_build_object('serviceInstanceId', created_instance.id)
    from public.users
    where users.id <> auth.uid();
  end if;

  for invitee_id in
    select distinct unnest(coalesce(p_invitee_ids, '{}'::uuid[]))
  loop
    if not exists (select 1 from public.users where id = invitee_id) then
      raise exception 'An invited devotee could not be found.';
    end if;

    insert into public.service_offers (
      service_instance_id, offered_to, offered_by, offer_kind, status
    )
    values (
      created_instance.id, invitee_id, auth.uid(), 'one_time', 'pending'
    )
    on conflict (service_instance_id, offered_to) do update
    set
      offered_by = excluded.offered_by,
      offer_kind = excluded.offer_kind,
      status = 'pending',
      created_at = now(),
      responded_at = null
    returning id into created_offer_id;

    perform public.queue_app_notification(
      invitee_id,
      'service_offer',
      'Can you help with this seva?',
      coordinator_name || ' is asking for your help with "' || display_name ||
        '" on ' || to_char(created_instance.date, 'FMDay, FMMonth FMDD') ||
        ' at ' || to_char(created_instance.start_time, 'FMHH12:MI AM') ||
        '. Please let them know if you are available.',
      jsonb_build_object(
        'serviceInstanceId', created_instance.id,
        'serviceOfferId', created_offer_id
      )
    );
  end loop;

  return created_instance.id;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4b. Completed and community-wide seva belong to coordinators.
--
--     `services.view_all` was seeded to every role in 0001, including Devotee,
--     and 0009 removed it from Volunteer only. That left Devotees able to read
--     the whole temple schedule -- including standing weekly assignee rosters,
--     which spec section 2 explicitly withholds from Volunteers -- while
--     Volunteers saw less than Devotees.
--
--     Confirmed product rule: only Core, Tech, and President see the community
--     schedule and everyone's completed seva. A Devotee or Volunteer sees the
--     open needs they can join plus their own seva. The RLS helpers
--     can_view_service_instance / can_view_service_template already let anyone
--     see open, joinable work and anything they are personally attached to, so
--     removing the blanket permission does not strand them.
-- ---------------------------------------------------------------------------

delete from public.role_permissions
where permission_key = 'services.view_all'
  and role_id in (
    select id from public.roles where name in ('devotee', 'volunteer')
  );

-- ---------------------------------------------------------------------------
-- 5. Re-assert the exact client entry points. `create or replace` above resets
--    privileges on replaced functions, so these grants must come last.
-- ---------------------------------------------------------------------------

revoke execute on function public.queue_app_notification(uuid, text, text, text, jsonb) from anon, authenticated;
revoke execute on function public.create_service_requirement(uuid, text, date, time, integer, integer, text, uuid[]) from anon;
revoke execute on function public.complete_due_service_sessions() from anon;

grant execute on function public.create_service_requirement(uuid, text, date, time, integer, integer, text, uuid[]) to authenticated;
grant execute on function public.complete_due_service_sessions() to authenticated;

-- Used inside RLS policies. The querying role must keep EXECUTE or every
-- select against service_instances/service_templates/service_assignments
-- fails for signed-in devotees.
grant execute on function public.has_permission(text) to authenticated;
grant execute on function public.can_view_service_instance(uuid) to authenticated;
grant execute on function public.can_view_service_template(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. `service_types.qr_token` is the only thing separating a `qr_scan`
--    verified seva from a `live_timer` self-report (spec section 6). Every
--    signed-in client was selecting the whole column, so any devotee could
--    read all temple tokens and replay one from home to earn the higher
--    verification label without ever being at the temple.
--
--    Column-level grants are role-wide, so the fix is to drop the column from
--    the `authenticated` grant entirely and hand tokens back only to catalog
--    coordinators through an RPC.
-- ---------------------------------------------------------------------------

revoke select on public.service_types from authenticated;
grant select (id, name, category, is_active, created_by, created_at)
  on public.service_types to authenticated;

-- Printing/QR management stays with President, Tech, and Core.
create or replace function public.list_service_qr_tokens()
returns table (id uuid, name text, qr_token text)
language sql
stable
security definer
set search_path = ''
as $$
  select service_types.id, service_types.name, service_types.qr_token
  from public.service_types
  where public.has_permission('services.manage_catalog')
    and service_types.is_active
    and service_types.qr_token is not null
  order by service_types.name;
$$;

revoke all on function public.list_service_qr_tokens() from public, anon;
grant execute on function public.list_service_qr_tokens() to authenticated;

do $$
begin
  raise notice 'rpc execution hardening applied';
end;
$$;
