-- Member-verified seva, and a third answer to a weekly seva invitation.
-- Requires 202608040010_rpc_execution_hardening.sql.
--
-- 1. A devotee can log seva they are doing now (start time + end time, no
--    timer) and nominate one Community Head / Tech Admin / President to verify
--    it. Nothing is credited until that person verifies. A declined or
--    unanswered request stays with the devotee, who can send it to someone
--    else. It never expires on its own.
--
-- 2. A devotee invited to a weekly seva gets a third answer besides yes and
--    no: propose a different day and time. Approving the proposal records the
--    devotee's availability and tells the coordinator, who then edits the
--    weekly seva themselves.

-- ---------------------------------------------------------------------------
-- Constraint widening
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
      'remote'
    )
  );

alter table public.service_assignments
  drop constraint if exists service_assignments_assignment_method_check;

alter table public.service_assignments
  add constraint service_assignments_assignment_method_check check (
    assignment_method in (
      'self_joined', 'accepted_offer', 'recurring_assignment',
      'accepted_coverage_offer', 'self_logged', 'live_timer', 'qr_scan',
      'member_verified'
    )
  );

alter table public.service_assignments
  drop constraint if exists service_assignments_verification_check;

alter table public.service_assignments
  add constraint service_assignments_verification_check check (
    verification in ('self_report', 'live_timer', 'qr_scan', 'member_verified')
  );

alter table public.service_offers
  drop constraint if exists service_offers_status_check;

alter table public.service_offers
  add constraint service_offers_status_check check (
    status in ('pending', 'accepted', 'declined', 'expired', 'countered')
  );

-- has_permission() only ever answers for the caller. Nominating a verifier
-- needs the same answer about somebody else.
create or replace function public.user_has_permission(
  p_user_id uuid,
  p_permission text
)
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
    where users.id = p_user_id
      and role_permissions.permission_key = p_permission
  );
$$;

-- ---------------------------------------------------------------------------
-- 1. Member-verified seva
-- ---------------------------------------------------------------------------

create table if not exists public.service_verifications (
  id uuid primary key default gen_random_uuid(),
  devotee_id uuid not null references public.users(id) on delete cascade,
  service_type_id uuid references public.service_types(id),
  custom_name text,
  start_at timestamptz not null,
  end_at timestamptz not null,
  location_text text not null default 'ISKCON Chicago Temple',
  verifier_id uuid not null references public.users(id),
  status text not null default 'pending' check (
    status in ('pending', 'verified', 'declined')
  ),
  review_note text,
  service_instance_id uuid references public.service_instances(id) on delete set null,
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  constraint service_verification_has_one_name check (
    (service_type_id is not null and custom_name is null)
    or
    (service_type_id is null and length(trim(custom_name)) between 2 and 100)
  ),
  constraint service_verification_window check (
    end_at > start_at and end_at <= start_at + interval '12 hours'
  ),
  constraint service_verification_review_consistency check (
    (status = 'pending' and responded_at is null)
    or (status in ('verified', 'declined') and responded_at is not null)
  )
);

-- One open request at a time keeps the verifier inbox honest.
create unique index if not exists one_pending_service_verification_per_devotee
  on public.service_verifications(devotee_id)
  where status = 'pending';

create index if not exists service_verifications_verifier_idx
  on public.service_verifications(verifier_id, status, created_at desc);

create index if not exists service_verifications_devotee_idx
  on public.service_verifications(devotee_id, created_at desc);

/** Community Heads, Tech Admins and the President — the people who may verify. */
create or replace function public.list_seva_verifiers()
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
  order by users.name;
$$;

create or replace function public.request_seva_verification(
  p_service_type_id uuid,
  p_custom_name text,
  p_start_at timestamptz,
  p_end_at timestamptz,
  p_location_text text,
  p_verifier_id uuid
)
returns public.service_verifications
language plpgsql
security definer
set search_path = ''
as $$
declare
  created_request public.service_verifications;
  devotee_name text;
  seva_name text;
begin
  if auth.uid() is null or not public.has_permission('services.participate') then
    raise exception 'Sign in to log seva.';
  end if;

  if not public.user_has_permission(p_verifier_id, 'services.manage_recurring') then
    raise exception 'Choose a Community Head, Tech Admin, or the President to verify this seva.';
  end if;

  if p_verifier_id = auth.uid() then
    raise exception 'Choose someone else to verify your seva.';
  end if;

  if (p_service_type_id is null) = (nullif(trim(p_custom_name), '') is null) then
    raise exception 'Choose a temple seva or enter one custom name.';
  end if;

  if p_service_type_id is not null and not exists (
    select 1 from public.service_types where id = p_service_type_id and is_active
  ) then
    raise exception 'The selected seva is not available.';
  end if;

  if p_end_at <= p_start_at
    or p_end_at > p_start_at + interval '12 hours'
  then
    raise exception 'Choose an end time within 12 hours of the start.';
  end if;

  if p_start_at > now() + interval '1 hour' then
    raise exception 'Seva can only be logged for a time that has started.';
  end if;

  insert into public.service_verifications (
    devotee_id, service_type_id, custom_name, start_at, end_at,
    location_text, verifier_id
  )
  values (
    auth.uid(), p_service_type_id, nullif(trim(p_custom_name), ''),
    p_start_at, p_end_at,
    coalesce(nullif(trim(p_location_text), ''), 'ISKCON Chicago Temple'),
    p_verifier_id
  )
  returning * into created_request;

  select name into devotee_name from public.users where id = auth.uid();
  seva_name := coalesce(
    (select name from public.service_types where id = created_request.service_type_id),
    created_request.custom_name
  );

  perform public.queue_app_notification(
    p_verifier_id,
    'seva_verification_requested',
    'Please verify a devotee''s seva',
    devotee_name || ' is asking you to verify "' || seva_name || '".',
    jsonb_build_object('serviceVerificationId', created_request.id)
  );

  return created_request;
exception
  when unique_violation then
    raise exception 'You already have a seva waiting to be verified.';
end;
$$;

/** Send a declined or still-pending request to a different member. */
create or replace function public.resend_seva_verification(
  p_verification_id uuid,
  p_verifier_id uuid
)
returns public.service_verifications
language plpgsql
security definer
set search_path = ''
as $$
declare
  existing_request public.service_verifications;
  updated_request public.service_verifications;
  devotee_name text;
  seva_name text;
begin
  select * into existing_request
  from public.service_verifications
  where id = p_verification_id
  for update;

  if existing_request.id is null or existing_request.devotee_id <> auth.uid() then
    raise exception 'This seva request could not be found.';
  end if;

  if existing_request.status = 'verified' then
    raise exception 'This seva has already been verified.';
  end if;

  if not public.user_has_permission(p_verifier_id, 'services.manage_recurring') then
    raise exception 'Choose a Community Head, Tech Admin, or the President to verify this seva.';
  end if;

  if p_verifier_id = auth.uid() then
    raise exception 'Choose someone else to verify your seva.';
  end if;

  update public.service_verifications
  set verifier_id = p_verifier_id,
      status = 'pending',
      review_note = null,
      responded_at = null
  where id = p_verification_id
  returning * into updated_request;

  select name into devotee_name from public.users where id = auth.uid();
  seva_name := coalesce(
    (select name from public.service_types where id = updated_request.service_type_id),
    updated_request.custom_name
  );

  perform public.queue_app_notification(
    p_verifier_id,
    'seva_verification_requested',
    'Please verify a devotee''s seva',
    devotee_name || ' is asking you to verify "' || seva_name || '".',
    jsonb_build_object('serviceVerificationId', updated_request.id)
  );

  return updated_request;
end;
$$;

create or replace function public.respond_to_seva_verification(
  p_verification_id uuid,
  p_approve boolean,
  p_note text default null
)
returns public.service_verifications
language plpgsql
security definer
set search_path = ''
as $$
declare
  pending_request public.service_verifications;
  reviewed_request public.service_verifications;
  created_instance_id uuid;
  chicago_started timestamp;
  duration_minutes integer;
  verifier_name text;
  seva_name text;
begin
  select * into pending_request
  from public.service_verifications
  where id = p_verification_id
  for update;

  if pending_request.id is null or pending_request.status <> 'pending' then
    raise exception 'This seva request is no longer waiting for a decision.';
  end if;

  if pending_request.verifier_id <> auth.uid() then
    raise exception 'Only the devotee''s chosen verifier can answer this.';
  end if;

  if p_approve then
    chicago_started := pending_request.start_at at time zone 'America/Chicago';
    duration_minutes := greatest(
      1,
      least(
        720,
        ceil(extract(epoch from (pending_request.end_at - pending_request.start_at)) / 60.0)::integer
      )
    );

    insert into public.service_instances (
      service_type_id, custom_name, date, start_time, duration_minutes,
      slots_needed, participation_mode, posted_by, status
    )
    values (
      pending_request.service_type_id, pending_request.custom_name,
      chicago_started::date, chicago_started::time, duration_minutes,
      1, 'invite_only', pending_request.devotee_id, 'completed'
    )
    returning id into created_instance_id;

    insert into public.service_assignments (
      service_instance_id, devotee_id, assignment_method, assigned_by,
      status, verification, completed_at
    )
    values (
      created_instance_id, pending_request.devotee_id, 'member_verified',
      auth.uid(), 'completed', 'member_verified', pending_request.end_at
    );
  end if;

  update public.service_verifications
  set status = case when p_approve then 'verified' else 'declined' end,
      review_note = nullif(trim(p_note), ''),
      responded_at = now(),
      service_instance_id = created_instance_id
  where id = p_verification_id
  returning * into reviewed_request;

  select name into verifier_name from public.users where id = auth.uid();
  seva_name := coalesce(
    (select name from public.service_types where id = reviewed_request.service_type_id),
    reviewed_request.custom_name
  );

  perform public.queue_app_notification(
    reviewed_request.devotee_id,
    'seva_verification_reviewed',
    case when p_approve then 'Your seva was verified' else 'Your seva was not verified' end,
    verifier_name
      || case when p_approve
           then ' verified your "' || seva_name || '" seva.'
           else ' could not verify your "' || seva_name || '" seva. You can ask someone else.'
         end,
    jsonb_build_object('serviceVerificationId', reviewed_request.id)
  );

  if p_approve then
    perform public.notify_service_oversight(
      'service_completed',
      'Verified seva logged',
      verifier_name || ' verified "' || seva_name || '".',
      jsonb_build_object(
        'serviceInstanceId', created_instance_id,
        'serviceVerificationId', reviewed_request.id
      ),
      auth.uid()
    );
  end if;

  return reviewed_request;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Counter-proposal for a weekly seva invitation
-- ---------------------------------------------------------------------------

create table if not exists public.service_offer_counters (
  id uuid primary key default gen_random_uuid(),
  service_offer_id uuid not null references public.service_offers(id) on delete cascade,
  devotee_id uuid not null references public.users(id) on delete cascade,
  proposed_days integer[] not null,
  proposed_start_time time not null,
  proposed_duration_minutes integer not null,
  note text,
  status text not null default 'pending' check (
    status in ('pending', 'approved', 'declined')
  ),
  review_note text,
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  responded_by uuid references public.users(id),
  constraint service_offer_counter_days_check check (
    cardinality(proposed_days) between 1 and 7
    and proposed_days <@ array[0,1,2,3,4,5,6]
  ),
  constraint service_offer_counter_duration_check check (
    proposed_duration_minutes between 30 and 720
    and proposed_duration_minutes % 30 = 0
  )
);

create unique index if not exists one_pending_counter_per_offer
  on public.service_offer_counters(service_offer_id)
  where status = 'pending';

create index if not exists service_offer_counters_offer_idx
  on public.service_offer_counters(service_offer_id, status, created_at desc);

create or replace function public.propose_weekly_offer_alternative(
  p_offer_id uuid,
  p_days integer[],
  p_start_time time,
  p_duration_minutes integer,
  p_note text default null
)
returns public.service_offer_counters
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_offer public.service_offers;
  created_counter public.service_offer_counters;
  devotee_name text;
  template_name text;
begin
  select * into target_offer
  from public.service_offers
  where id = p_offer_id
  for update;

  if target_offer.id is null or target_offer.offered_to <> auth.uid() then
    raise exception 'This seva invitation could not be found.';
  end if;

  if target_offer.status <> 'pending' then
    raise exception 'You have already answered this invitation.';
  end if;

  if target_offer.offer_kind not in ('recurring', 'coverage_range') then
    raise exception 'Only a weekly seva invitation can be answered with another time.';
  end if;

  if coalesce(cardinality(p_days), 0) = 0 then
    raise exception 'Choose at least one day you are available.';
  end if;

  if p_duration_minutes < 30 or p_duration_minutes > 720
    or p_duration_minutes % 30 <> 0
  then
    raise exception 'Duration must use 30-minute increments.';
  end if;

  insert into public.service_offer_counters (
    service_offer_id, devotee_id, proposed_days, proposed_start_time,
    proposed_duration_minutes, note
  )
  values (
    p_offer_id, auth.uid(), p_days, p_start_time, p_duration_minutes,
    nullif(trim(p_note), '')
  )
  returning * into created_counter;

  update public.service_offers
  set status = 'countered', responded_at = now()
  where id = p_offer_id;

  select name into devotee_name from public.users where id = auth.uid();
  select coalesce(service_types.name, service_templates.custom_name)
  into template_name
  from public.service_templates
  left join public.service_types
    on service_types.id = service_templates.service_type_id
  where service_templates.id = target_offer.service_template_id;

  perform public.queue_app_notification(
    target_offer.offered_by,
    'weekly_offer_countered',
    'A devotee suggested another time',
    devotee_name || ' cannot take "' || coalesce(template_name, 'the weekly seva')
      || '" as offered, and suggested a different day and time.',
    jsonb_build_object(
      'serviceOfferId', p_offer_id,
      'serviceOfferCounterId', created_counter.id,
      'serviceTemplateId', target_offer.service_template_id
    )
  );

  return created_counter;
exception
  when unique_violation then
    raise exception 'You already suggested another time for this invitation.';
end;
$$;

/**
 * Approving records the devotee's availability and tells the coordinator to
 * edit the weekly seva. It deliberately does not reassign anybody: the
 * coordinator stays in control of the schedule.
 */
create or replace function public.respond_to_weekly_offer_counter(
  p_counter_id uuid,
  p_approve boolean,
  p_note text default null
)
returns public.service_offer_counters
language plpgsql
security definer
set search_path = ''
as $$
declare
  pending_counter public.service_offer_counters;
  reviewed_counter public.service_offer_counters;
  target_offer public.service_offers;
  reviewer_name text;
begin
  select * into pending_counter
  from public.service_offer_counters
  where id = p_counter_id
  for update;

  if pending_counter.id is null or pending_counter.status <> 'pending' then
    raise exception 'This suggestion has already been answered.';
  end if;

  select * into target_offer
  from public.service_offers
  where id = pending_counter.service_offer_id;

  if target_offer.offered_by <> auth.uid()
    and not public.has_permission('services.manage_recurring')
  then
    raise exception 'Only the coordinator who invited this devotee can answer.';
  end if;

  update public.service_offer_counters
  set status = case when p_approve then 'approved' else 'declined' end,
      review_note = nullif(trim(p_note), ''),
      responded_at = now(),
      responded_by = auth.uid()
  where id = p_counter_id
  returning * into reviewed_counter;

  -- Either way the original invitation is finished. A declined suggestion
  -- leaves the weekly seva needing someone, which is what the coordinator
  -- inbox surfaces.
  update public.service_offers
  set status = 'declined', responded_at = now()
  where id = pending_counter.service_offer_id
    and status = 'countered';

  select name into reviewer_name from public.users where id = auth.uid();

  perform public.queue_app_notification(
    reviewed_counter.devotee_id,
    'weekly_offer_counter_reviewed',
    case when p_approve
      then 'Your suggested time was accepted'
      else 'Your suggested time was not taken'
    end,
    reviewer_name
      || case when p_approve
           then ' accepted the days and time you suggested. They will update the weekly seva.'
           else ' could not use the days and time you suggested.'
         end,
    jsonb_build_object('serviceOfferCounterId', reviewed_counter.id)
  );

  return reviewed_counter;
end;
$$;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------

alter table public.service_verifications enable row level security;
alter table public.service_offer_counters enable row level security;

drop policy if exists "Devotee verifier and oversight can read seva verifications"
  on public.service_verifications;
create policy "Devotee verifier and oversight can read seva verifications"
  on public.service_verifications for select to authenticated
  using (
    devotee_id = auth.uid()
    or verifier_id = auth.uid()
    or public.has_permission('services.oversee_activity')
  );

drop policy if exists "Devotee and coordinators can read weekly counters"
  on public.service_offer_counters;
create policy "Devotee and coordinators can read weekly counters"
  on public.service_offer_counters for select to authenticated
  using (
    devotee_id = auth.uid()
    or public.has_permission('services.manage_recurring')
    or exists (
      select 1 from public.service_offers
      where service_offers.id = service_offer_counters.service_offer_id
        and service_offers.offered_by = auth.uid()
    )
  );

revoke all on public.service_verifications from anon, authenticated;
revoke all on public.service_offer_counters from anon, authenticated;
grant select on public.service_verifications to authenticated;
grant select on public.service_offer_counters to authenticated;

revoke all on function public.user_has_permission(uuid, text) from public, anon, authenticated;
revoke all on function public.list_seva_verifiers() from public, anon;
revoke all on function public.request_seva_verification(uuid, text, timestamptz, timestamptz, text, uuid) from public, anon;
revoke all on function public.resend_seva_verification(uuid, uuid) from public, anon;
revoke all on function public.respond_to_seva_verification(uuid, boolean, text) from public, anon;
revoke all on function public.propose_weekly_offer_alternative(uuid, integer[], time, integer, text) from public, anon;
revoke all on function public.respond_to_weekly_offer_counter(uuid, boolean, text) from public, anon;

grant execute on function public.list_seva_verifiers() to authenticated;
grant execute on function public.request_seva_verification(uuid, text, timestamptz, timestamptz, text, uuid) to authenticated;
grant execute on function public.resend_seva_verification(uuid, uuid) to authenticated;
grant execute on function public.respond_to_seva_verification(uuid, boolean, text) to authenticated;
grant execute on function public.propose_weekly_offer_alternative(uuid, integer[], time, integer, text) to authenticated;
grant execute on function public.respond_to_weekly_offer_counter(uuid, boolean, text) to authenticated;

-- Realtime so both phones update the moment a decision is made.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public' and tablename = 'service_verifications'
  ) then
    alter publication supabase_realtime add table public.service_verifications;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public' and tablename = 'service_offer_counters'
  ) then
    alter publication supabase_realtime add table public.service_offer_counters;
  end if;
end;
$$;

do $$
begin
  raise notice 'seva verification and counter offers applied';
end;
$$;
