-- Functional verification for 202608040024_seva_request_negotiation.sql.
--
-- Rolled back at the end, so it is safe against any database. Every local is
-- prefixed v_ so it can never shadow a column name.
--
-- The final row must read: seva request negotiation verification passed

begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('40000000-0000-0000-0000-000000000001', 'nego-president@example.test', '{"name":"Nego President"}'),
  ('40000000-0000-0000-0000-000000000002', 'nego-volunteer@example.test', '{"name":"Nego Volunteer"}'),
  ('40000000-0000-0000-0000-000000000003', 'nego-devotee-a@example.test', '{"name":"Nego Devotee A"}'),
  ('40000000-0000-0000-0000-000000000004', 'nego-devotee-b@example.test', '{"name":"Nego Devotee B"}');

update public.users users
set role_id = roles.id
from public.roles roles
where (users.email, roles.name) in (
  ('nego-president@example.test', 'president'),
  ('nego-volunteer@example.test', 'volunteer'),
  ('nego-devotee-a@example.test', 'devotee'),
  ('nego-devotee-b@example.test', 'devotee')
);

create temporary table nego_ids (key text primary key, id uuid not null);

-- ---------------------------------------------------------------------------
-- 1. A Volunteer posts a seva request and asks one devotee.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', '40000000-0000-0000-0000-000000000002', true);

do $$
declare
  v_instance uuid;
begin
  v_instance := public.create_service_requirement(
    null, 'Negotiation garland making',
    (now() at time zone 'America/Chicago')::date + 3,
    '09:00:00', 60, 1, 'invite_only',
    array['40000000-0000-0000-0000-000000000003'::uuid]
  );
  insert into nego_ids values ('instance', v_instance);
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. The devotee cannot make it then, but offers another time.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', '40000000-0000-0000-0000-000000000003', true);

do $$
declare
  v_offer uuid;
  v_counter public.service_offer_counters;
begin
  select id into v_offer from public.service_offers
  where service_instance_id = (select id from nego_ids where key = 'instance')
    and offered_to = '40000000-0000-0000-0000-000000000003'
    and status = 'pending';
  if v_offer is null then
    raise exception 'setup: the invitation was never sent.';
  end if;

  v_counter := public.propose_service_offer_alternative(
    v_offer,
    (now() at time zone 'America/Chicago')::date + 5,
    '16:00:00', 90, 'Mornings are hard for me.'
  );
  insert into nego_ids values ('counter', v_counter.id), ('offer', v_offer);

  if v_counter.proposed_date is null then
    raise exception 'The suggestion did not record which day was offered.';
  end if;
  if not exists (
    select 1 from public.service_offers where id = v_offer and status = 'countered'
  ) then
    raise exception 'Suggesting another time did not mark the invitation countered.';
  end if;

  -- The poster must hear about it, with the day and the hour in the message.
  if not exists (
    select 1 from public.app_notifications
    where user_id = '40000000-0000-0000-0000-000000000002'
      and kind = 'weekly_offer_countered'
      and body like '%4:00 PM%'
  ) then
    raise exception 'The poster was not told what time was offered: %',
      (select body from public.app_notifications
       where user_id = '40000000-0000-0000-0000-000000000002'
       order by created_at desc limit 1);
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Somebody else cannot answer the suggestion.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', '40000000-0000-0000-0000-000000000004', true);

do $$
declare
  v_refused boolean := false;
begin
  begin
    perform public.respond_to_service_offer_counter(
      (select id from nego_ids where key = 'counter'), true, null
    );
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A devotee who did not post the seva answered the suggestion.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. The poster accepts: the seva moves and the devotee is on it.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', '40000000-0000-0000-0000-000000000002', true);

do $$
declare
  v_instance uuid := (select id from nego_ids where key = 'instance');
  v_expected date := (now() at time zone 'America/Chicago')::date + 5;
begin
  perform public.respond_to_service_offer_counter(
    (select id from nego_ids where key = 'counter'), true, 'That works.'
  );

  if not exists (
    select 1 from public.service_instances
    where id = v_instance and date = v_expected
      and start_time = '16:00:00' and duration_minutes = 90
  ) then
    raise exception 'Accepting the suggestion did not move the seva.';
  end if;

  if not exists (
    select 1 from public.service_assignments
    where service_instance_id = v_instance
      and devotee_id = '40000000-0000-0000-0000-000000000003'
      and status = 'confirmed'
  ) then
    raise exception 'Accepting the suggestion did not put the devotee on the seva.';
  end if;

  if not exists (
    select 1 from public.app_notifications
    where user_id = '40000000-0000-0000-0000-000000000003'
      and kind = 'weekly_offer_counter_reviewed'
      and body like '%4:00 PM%'
  ) then
    raise exception 'The devotee was not told their time was taken up.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. A decline tells the poster how many places are still open.
-- ---------------------------------------------------------------------------

do $$
declare
  v_instance uuid;
begin
  v_instance := public.create_service_requirement(
    null, 'Negotiation prasadam serving',
    (now() at time zone 'America/Chicago')::date + 4,
    '18:00:00', 60, 2, 'invite_only',
    array[
      '40000000-0000-0000-0000-000000000003'::uuid,
      '40000000-0000-0000-0000-000000000004'::uuid
    ]
  );
  insert into nego_ids values ('second', v_instance);
end;
$$;

select set_config('request.jwt.claim.sub', '40000000-0000-0000-0000-000000000004', true);

do $$
declare
  v_offer uuid;
begin
  select id into v_offer from public.service_offers
  where service_instance_id = (select id from nego_ids where key = 'second')
    and offered_to = '40000000-0000-0000-0000-000000000004';
  perform public.respond_to_service_offer(v_offer, false);

  if not exists (
    select 1 from public.app_notifications
    where user_id = '40000000-0000-0000-0000-000000000002'
      and kind = 'service_offer_response'
      and data ->> 'needsPoster' = 'true'
      and body like '%still to fill%'
      and body like '%6:00 PM%'
  ) then
    raise exception 'A decline did not reach the poster as something to act on: %',
      (select body from public.app_notifications
       where user_id = '40000000-0000-0000-0000-000000000002'
       order by created_at desc limit 1);
  end if;
end;
$$;

-- Answering the same way twice is not an error.
do $$
begin
  perform public.respond_to_service_offer(
    (select id from public.service_offers
      where service_instance_id = (select id from nego_ids where key = 'second')
        and offered_to = '40000000-0000-0000-0000-000000000004'),
    false
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. The poster reshapes the request: opens it to everyone.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', '40000000-0000-0000-0000-000000000002', true);

do $$
declare
  v_instance uuid := (select id from nego_ids where key = 'second');
begin
  perform public.update_service_requirement(v_instance, 'open', 2, '{}'::uuid[]);

  if not exists (
    select 1 from public.service_instances
    where id = v_instance and participation_mode = 'open'
  ) then
    raise exception 'The seva request was not opened to everyone.';
  end if;

  if not exists (
    select 1 from public.app_notifications
    where user_id = '40000000-0000-0000-0000-000000000003'
      and kind = 'service_open'
      and body like '%open%'
  ) then
    raise exception 'Opening the request told nobody.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Places cannot be cut below the devotees already standing on them, and
--    nobody may be invited beyond the places that exist.
-- ---------------------------------------------------------------------------

do $$
declare
  v_instance uuid := (select id from nego_ids where key = 'second');
  v_refused boolean := false;
begin
  insert into public.service_assignments (
    service_instance_id, devotee_id, assignment_method, assigned_by,
    status, verification
  ) values (
    v_instance, '40000000-0000-0000-0000-000000000003', 'self_joined',
    '40000000-0000-0000-0000-000000000003', 'confirmed', 'self_report'
  ) on conflict do nothing;

  begin
    perform public.update_service_requirement(v_instance, 'open', 0, '{}'::uuid[]);
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'Places were cut below the devotees already serving.';
  end if;

  v_refused := false;
  begin
    perform public.update_service_requirement(
      v_instance, 'invite_only', 1,
      array['40000000-0000-0000-0000-000000000004'::uuid]
    );
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A devotee was invited to a place that does not exist.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. A devotee who did not post it cannot reshape it.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', '40000000-0000-0000-0000-000000000003', true);

do $$
declare
  v_refused boolean := false;
begin
  begin
    perform public.update_service_requirement(
      (select id from nego_ids where key = 'second'), 'open', 4, '{}'::uuid[]
    );
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'A devotee reshaped somebody else''s seva request.';
  end if;
end;
$$;

-- The President may, though.
select set_config('request.jwt.claim.sub', '40000000-0000-0000-0000-000000000001', true);

do $$
begin
  perform public.update_service_requirement(
    (select id from nego_ids where key = 'second'), 'open', 4, '{}'::uuid[]
  );
  if not exists (
    select 1 from public.service_instances
    where id = (select id from nego_ids where key = 'second') and slots_needed = 4
  ) then
    raise exception 'The President could not reshape a seva request.';
  end if;
end;
$$;

do $$
begin
  raise notice 'all negotiation checks passed';
end;
$$;

select 'seva request negotiation verification passed' as result;

rollback;
