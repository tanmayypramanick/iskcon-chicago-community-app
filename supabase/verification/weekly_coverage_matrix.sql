-- Every way a weekly day changes hands.
--
-- A rota runs by itself, so the one thing a devotee can do about a day they
-- cannot make is ask for coverage. That makes coverage the whole of weekly
-- seva's flexibility, and it has more paths than anything else in the feature:
-- asked and accepted, asked and declined, opened to everyone, reopened,
-- released as a range, superseded by a later change of mind.
--
-- weekly_seva_visibility_and_coverage_functional.sql already proves that the
-- range path works. What was never walked is the rest of the fan-out, and
-- above all WHAT EACH ONE EARNS — which devotee ends up credited for the day,
-- and which does not. That is the part a devotee would notice and the part
-- nothing was checking.
--
-- Rolled back at the end, so the script is re-runnable.

begin;

-- ---------------------------------------------------------------------------
-- The rota and the people on it.
-- ---------------------------------------------------------------------------

create temporary table wcm_ids (key text primary key, id uuid not null)
  on commit drop;
grant all on table wcm_ids to authenticated;

do $$
declare
  v_who record;
  v_i integer := 0;
  v_id uuid;
begin
  for v_who in
    select * from (values
      ('head',   'Coverage Coordinator', 'president'),
      ('standing', 'Standing Devotee',   'devotee'),
      ('sub',    'Willing Substitute',   'devotee'),
      ('sub2',   'Second Substitute',    'devotee'),
      ('other',  'Uninvolved Devotee',   'devotee')
    ) as cast_member(key, name, role)
  loop
    v_i := v_i + 1;
    v_id := ('7e000000-0000-0000-0000-0000000000' || lpad(v_i::text, 2, '0'))::uuid;
    insert into auth.users (id, email, raw_user_meta_data)
    values (v_id, 'wcm-' || v_who.key || '@example.test',
            jsonb_build_object('name', v_who.name));
    update public.users
    set role_id = (select id from public.roles where name = v_who.role)
    where id = v_id;
    insert into wcm_ids (key, id) values (v_who.key, v_id);
  end loop;
end;
$$;

/** The first date on or after tomorrow that falls on the rota's weekday. */
create or replace function pg_temp.wcm_next(p_dow integer)
returns date
language sql
stable
as $$
  select min(day)::date
  from generate_series(
    (now() at time zone 'America/Chicago')::date + 1,
    (now() at time zone 'America/Chicago')::date + 14,
    interval '1 day'
  ) as day
  where extract(dow from day)::integer = p_dow;
$$;

/** What one devotee earned for one occurrence, in credited minutes. */
create or replace function pg_temp.wcm_minutes(p_instance uuid, p_who text)
returns numeric
language sql
stable
as $$
  select coalesce(
    (
      select acts.credited_minutes
      from public.seva_mala_acts((select id from wcm_ids where key = p_who)) acts
      where acts.service_instance_id = p_instance
    ),
    0
  );
$$;

/** Whether a devotee holds a live place on an occurrence. */
create or replace function pg_temp.wcm_holds(p_instance uuid, p_who text)
returns boolean
language sql
stable
as $$
  select exists (
    select 1 from public.service_assignments assignments
    where assignments.service_instance_id = p_instance
      and assignments.devotee_id = (select id from wcm_ids where key = p_who)
      and assignments.status in ('assigned', 'confirmed', 'completed')
  );
$$;

-- The rota itself: Mondays, one place, the standing devotee on it.
select set_config('request.jwt.claim.sub',
  (select id::text from wcm_ids where key = 'head'), true);
set local role authenticated;

do $$
declare
  v_template uuid;
begin
  -- Open, so the devotee can take a standing place on it directly. Naming an
  -- invitee here would only send them an OFFER — update_service_template_v2
  -- invites rather than assigns — and this fixture wants somebody already on
  -- the rota, which is what coverage is about.
  v_template := public.create_service_template_v2(
    null, 'Coverage matrix garlands', array[1], '17:00:00', 90, 1,
    'open', (now() at time zone 'America/Chicago')::date, null, '{}'::uuid[]
  );
  insert into wcm_ids values ('template', v_template);
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);

-- The standing devotee takes their place on the rota.
select set_config('request.jwt.claim.sub',
  (select id::text from wcm_ids where key = 'standing'), true);
set local role authenticated;
select public.join_weekly_service((select id from wcm_ids where key = 'template'));
reset role;
select set_config('request.jwt.claim.sub', '', true);

-- Outside the authenticated role: generating the rota's occurrences is the
-- database's own job and is revoked from clients on purpose. Run after the
-- devotee joins, so the occurrences carry their place.
select public.generate_service_instances(180);

-- ---------------------------------------------------------------------------
-- 1. Asking for coverage gives the day up straight away.
--
--    The place is released the moment the devotee says they cannot make it.
--    Holding it until somebody accepted would leave the rota looking staffed
--    by a devotee who has already said they will not be there.
-- ---------------------------------------------------------------------------

do $$
declare
  v_standing uuid := (select id from wcm_ids where key = 'standing');
  v_monday date := pg_temp.wcm_next(1);
  v_group uuid;
  v_exception uuid;
  v_instance uuid;
begin
  perform set_config('request.jwt.claim.sub', v_standing::text, true);
  -- Returns the request GROUP, not one exception: releasing a run of days
  -- opens one request per day and they are answered as a set.
  v_group := public.report_weekly_service_unavailable(
    (select id from wcm_ids where key = 'template'),
    'occurrence', v_monday, v_monday, array[1], 'Family commitment.'
  );
  perform set_config('request.jwt.claim.sub', '', true);

  if v_group is null then
    raise exception 'asking for coverage opened no request';
  end if;

  select exceptions.id, exceptions.service_instance_id
  into v_exception, v_instance
  from public.service_exceptions exceptions
  where exceptions.request_group_id = v_group
    and exceptions.devotee_id = v_standing
  limit 1;

  if v_exception is null then
    raise exception 'the request group opened no coverage request';
  end if;
  insert into wcm_ids values ('exception', v_exception);
  insert into wcm_ids values ('instance', v_instance);

  if (select exceptions.status from public.service_exceptions exceptions
      where exceptions.id = v_exception) <> 'pending' then
    raise exception 'the coverage request did not open as pending';
  end if;
  if pg_temp.wcm_holds(v_instance, 'standing') then
    raise exception 'the devotee still holds a day they asked to be covered';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Asked, and declined. The day comes back, and can be asked again.
-- ---------------------------------------------------------------------------

do $$
declare
  v_head uuid := (select id from wcm_ids where key = 'head');
  v_sub uuid := (select id from wcm_ids where key = 'sub');
  v_exception uuid := (select id from wcm_ids where key = 'exception');
  v_instance uuid := (select id from wcm_ids where key = 'instance');
  v_offer uuid;
begin
  perform set_config('request.jwt.claim.sub', v_head::text, true);
  v_offer := public.offer_service_coverage(v_exception, v_sub);
  perform set_config('request.jwt.claim.sub', '', true);

  perform set_config('request.jwt.claim.sub', v_sub::text, true);
  perform public.respond_to_service_offer(v_offer, false);
  perform set_config('request.jwt.claim.sub', '', true);

  if pg_temp.wcm_holds(v_instance, 'sub') then
    raise exception 'a devotee who declined was put on the seva anyway';
  end if;
  if (select exceptions.status from public.service_exceptions exceptions
      where exceptions.id = v_exception) <> 'pending' then
    raise exception 'a declined offer closed the coverage request';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Asked again, and accepted. The substitute takes the day.
-- ---------------------------------------------------------------------------

do $$
declare
  v_head uuid := (select id from wcm_ids where key = 'head');
  v_sub2 uuid := (select id from wcm_ids where key = 'sub2');
  v_exception uuid := (select id from wcm_ids where key = 'exception');
  v_instance uuid := (select id from wcm_ids where key = 'instance');
  v_offer uuid;
begin
  perform set_config('request.jwt.claim.sub', v_head::text, true);
  v_offer := public.offer_service_coverage(v_exception, v_sub2);
  perform set_config('request.jwt.claim.sub', '', true);

  perform set_config('request.jwt.claim.sub', v_sub2::text, true);
  perform public.respond_to_service_offer(v_offer, true);
  perform set_config('request.jwt.claim.sub', '', true);

  if not pg_temp.wcm_holds(v_instance, 'sub2') then
    raise exception 'the substitute who accepted did not get the day';
  end if;
  if pg_temp.wcm_holds(v_instance, 'standing') then
    raise exception 'the original devotee was put back on a covered day';
  end if;
  if (select exceptions.status from public.service_exceptions exceptions
      where exceptions.id = v_exception) <> 'resolved' then
    raise exception 'an accepted offer left the coverage request open';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. The standing rota is unchanged, so the seva comes back afterwards.
--
--    A swap is for a day, not for ever. 202608030009 keeps the template's own
--    roster whole precisely so the seva returns to the devotee who holds it.
-- ---------------------------------------------------------------------------

do $$
declare
  v_standing uuid := (select id from wcm_ids where key = 'standing');
  v_template uuid := (select id from wcm_ids where key = 'template');
  v_instance uuid := (select id from wcm_ids where key = 'instance');
  v_later integer;
begin
  if not exists (
    select 1 from public.service_template_assignees assignees
    where assignees.service_template_id = v_template
      and assignees.devotee_id = v_standing
      and assignees.status = 'active'
  ) then
    raise exception 'covering one day removed the devotee from the rota';
  end if;

  select count(*)::integer into v_later
  from public.service_instances instances
  join public.service_assignments assignments
    on assignments.service_instance_id = instances.id
  where instances.template_id = v_template
    and instances.id <> v_instance
    and assignments.devotee_id = v_standing
    and assignments.status in ('assigned', 'confirmed');

  if v_later = 0 then
    raise exception
      'the devotee holds no later occurrence; the swap took the whole rota';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Who earns the covered day.
--
--    The substitute served it, so the substitute is credited. The devotee who
--    asked to be covered earns nothing for a day they were not there — which
--    is the whole reason the ask exists rather than a quiet absence.
-- ---------------------------------------------------------------------------

do $$
declare
  v_instance uuid := (select id from wcm_ids where key = 'instance');
begin
  -- Bring the occurrence into the past and close it out, as the clock would.
  update public.service_instances
  set date = (now() at time zone 'America/Chicago')::date - 1,
      status = 'completed'
  where id = v_instance;

  update public.service_assignments
  set status = 'completed',
      completed_at = now() - interval '1 hour'
  where service_instance_id = v_instance
    and status in ('assigned', 'confirmed');

  if pg_temp.wcm_minutes(v_instance, 'sub2') <= 0 then
    raise exception 'the substitute who served the day earned nothing for it';
  end if;
  if pg_temp.wcm_minutes(v_instance, 'standing') <> 0 then
    raise exception
      'the devotee who asked to be covered was credited for a day they missed';
  end if;
  if pg_temp.wcm_minutes(v_instance, 'sub') <> 0 then
    raise exception 'the devotee who declined was credited for the day';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Opening the day to everyone.
--
--    The coordinator's other option, when they would rather not ask one
--    devotee: reopen_service_exception broadcasts the day — it marks the
--    request as answered by broadcast and opens the occurrence — and then
--    whoever is free takes it.
-- ---------------------------------------------------------------------------

do $$
declare
  v_standing uuid := (select id from wcm_ids where key = 'standing');
  v_head uuid := (select id from wcm_ids where key = 'head');
  v_other uuid := (select id from wcm_ids where key = 'other');
  v_template uuid := (select id from wcm_ids where key = 'template');
  v_monday date := pg_temp.wcm_next(1) + 7;
  v_group uuid;
  v_exception uuid;
  v_instance uuid;
  v_mode text;
begin
  perform set_config('request.jwt.claim.sub', v_standing::text, true);
  v_group := public.report_weekly_service_unavailable(
    v_template, 'occurrence', v_monday, v_monday, array[1], null
  );
  perform set_config('request.jwt.claim.sub', '', true);

  select exceptions.id, exceptions.service_instance_id
  into v_exception, v_instance
  from public.service_exceptions exceptions
  where exceptions.request_group_id = v_group
    and exceptions.devotee_id = v_standing
  limit 1;

  -- Opened to everyone.
  perform set_config('request.jwt.claim.sub', v_head::text, true);
  perform public.reopen_service_exception(v_exception);
  perform set_config('request.jwt.claim.sub', '', true);

  select instances.participation_mode into v_mode
  from public.service_instances instances where instances.id = v_instance;
  if v_mode <> 'open' then
    raise exception 'broadcasting a day left it %', v_mode;
  end if;
  if (select exceptions.resolution_kind from public.service_exceptions exceptions
      where exceptions.id = v_exception) <> 'broadcast' then
    raise exception 'the request does not record that the day was opened';
  end if;

  -- And a devotee nobody asked can now take it.
  perform set_config('request.jwt.claim.sub', v_other::text, true);
  perform public.join_service_instance(v_instance);
  perform set_config('request.jwt.claim.sub', '', true);

  if not pg_temp.wcm_holds(v_instance, 'other') then
    raise exception 'a devotee could not take a day that was opened to everyone';
  end if;
  if pg_temp.wcm_holds(v_instance, 'standing') then
    raise exception 'the devotee who released the day is back on it';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Releasing a run of days, and only the days the devotee holds.
-- ---------------------------------------------------------------------------

do $$
declare
  v_standing uuid := (select id from wcm_ids where key = 'standing');
  v_template uuid := (select id from wcm_ids where key = 'template');
  v_from date := pg_temp.wcm_next(1) + 14;
  v_group uuid;
  v_rows integer;
  v_refused boolean := false;
begin
  perform set_config('request.jwt.claim.sub', v_standing::text, true);
  v_group := public.report_weekly_service_unavailable(
    v_template, 'date_range', v_from, v_from + 21, array[1], 'Away.'
  );

  -- A day the rota does not run on is not a day anybody can release.
  begin
    perform public.report_weekly_service_unavailable(
      v_template, 'date_range', v_from, v_from + 7, array[3], null
    );
  exception when others then
    v_refused := true;
  end;
  perform set_config('request.jwt.claim.sub', '', true);

  if not v_refused then
    raise exception 'a devotee released a weekday the rota does not run on';
  end if;

  select count(*)::integer into v_rows
  from public.service_exceptions exceptions
  join public.service_instances instances
    on instances.id = exceptions.service_instance_id
  where exceptions.devotee_id = v_standing
    and instances.template_id = v_template
    and instances.date between v_from and v_from + 21
    and exceptions.status = 'pending';

  if v_rows < 2 then
    raise exception
      'a three-week release opened % coverage requests; expected one per Monday',
      v_rows;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. Saying it twice does not ask twice.
--
--    A devotee who releases the same day again — a second tap, a retry on a
--    bad connection — must not open a second request for it, or the coverage
--    inbox fills with duplicates of one day and a coordinator can ask two
--    people to cover the same place.
--
--    NOT covered here: withdraw_superseded_coverage_asks, which cancels a
--    pending coverage PLAN made by offer_service_coverage_range when the days
--    it covers are released again. That path needs a plan spanning days the
--    devotee still holds, and it is exercised by
--    weekly_seva_visibility_and_coverage_functional.sql rather than restated
--    badly here.
-- ---------------------------------------------------------------------------

do $$
declare
  v_standing uuid := (select id from wcm_ids where key = 'standing');
  v_template uuid := (select id from wcm_ids where key = 'template');
  v_monday date := pg_temp.wcm_next(1) + 42;
  v_instance uuid;
  v_first integer;
  v_second integer;
begin
  perform set_config('request.jwt.claim.sub', v_standing::text, true);
  perform public.report_weekly_service_unavailable(
    v_template, 'occurrence', v_monday, v_monday, array[1], null
  );

  select instances.id into v_instance
  from public.service_instances instances
  where instances.template_id = v_template and instances.date = v_monday;

  select count(*)::integer into v_first
  from public.service_exceptions exceptions
  where exceptions.service_instance_id = v_instance
    and exceptions.devotee_id = v_standing;

  -- Again, over the same day. The devotee no longer holds it, so there is
  -- nothing left to release and the second attempt is refused rather than
  -- quietly opening a duplicate.
  begin
    perform public.report_weekly_service_unavailable(
      v_template, 'occurrence', v_monday, v_monday, array[1], null
    );
  exception when others then
    null;
  end;
  perform set_config('request.jwt.claim.sub', '', true);

  select count(*)::integer into v_second
  from public.service_exceptions exceptions
  where exceptions.service_instance_id = v_instance
    and exceptions.devotee_id = v_standing;

  if v_first <> 1 then
    raise exception 'releasing one day opened % requests for it', v_first;
  end if;
  if v_second <> v_first then
    raise exception
      'releasing the same day twice left % requests for it rather than %',
      v_second, v_first;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 9. Who may arrange coverage, and who may not.
-- ---------------------------------------------------------------------------

do $$
declare
  v_other uuid := (select id from wcm_ids where key = 'other');
  v_sub uuid := (select id from wcm_ids where key = 'sub');
  v_exception uuid := (select id from wcm_ids where key = 'exception');
  v_refused boolean := false;
begin
  -- An ordinary devotee cannot hand somebody else's day to anybody.
  perform set_config('request.jwt.claim.sub', v_other::text, true);
  begin
    perform public.offer_service_coverage(v_exception, v_sub);
  exception when others then
    v_refused := true;
  end;
  perform set_config('request.jwt.claim.sub', '', true);

  if not v_refused then
    raise exception 'an ordinary devotee arranged coverage';
  end if;
end;
$$;

do $$
begin
  raise notice 'every weekly coverage path settles the way the temple says it does';
end;
$$;

rollback;
