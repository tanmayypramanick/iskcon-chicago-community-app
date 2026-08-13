-- Functional verification for 202608040069_schedule_and_clashes.sql.
--
-- Rolled back at the end. Every local is prefixed v_ so it can never shadow a
-- column name. Anything that must be refused is attempted as the devotee who
-- would really attempt it, under `set local role authenticated`, so the row
-- level security, the grants and the permission checks are what is being
-- tested rather than superuser rights waving everything through.
--
-- ---------------------------------------------------------------------------
-- What is being proved.
--
--   1. A handed-over seva names the SUBSTITUTE, in all three coverage scopes —
--      occurrence, date_range and forever — and the date_range one is proved on
--      the shape that actually breaks: an occurrence generated after the offer
--      was accepted, whose service_assignments row still names the original.
--      Both directions of "evidence outranks the plan" are proved as well: an
--      original who completed it anyway stays, a substitute who withdrew from
--      that one occurrence does not appear.
--   2. A devotee sees their own schedule and only their own, and asking for
--      somebody else's is refused rather than answered empty.
--   3. A Community Head sees the whole temple's — and so do the President and
--      the Tech Admin, and nobody else.
--   4. Clashes are found partial, total and across a midnight boundary, are
--      NOT found for back-to-back seva, and are not found for a devotee whose
--      seva was handed to somebody else.
--   5. A cancelled seva and a seva nobody served are marked as such and are
--      told apart from each other.
--   6. The feed does not fan out per devotee: one call, one pass over the
--      roster, whatever the size of the congregation. Measured, not asserted,
--      with pg_stat_get_xact_function_calls.
--   7. Nothing here decides anything. list_seva_clashes is called by no other
--      function, writes nothing, and refuses nothing.
--   8. Every window and every threshold is a dial, including the temple's own
--      programme, which is proved by moving Mangala Arati and reading it back.
--
--   and then eighteen mutations, each breaking exactly one guard and re-reading
--   one number through the real function.
--
-- ---------------------------------------------------------------------------
-- The fixture. Five weekly templates — so that no two occurrences collide on
-- the unique (template_id, date) index — five one-off seva, and a crowd.
-- v_mon is this Chicago week's Monday, so every date below is deterministic
-- whatever day the suite runs.
--
--   key             when                          who, and what should be read
--   -------------------------------------------------------------------------
--   swap_occ        Thu v_mon+3 10:00 +90   T1   assignment names ARPITA, an
--                                                accepted 'occurrence' plan
--                                                hands it to BHAKTA. ESHA holds
--                                                the second place, covered by
--                                                nothing.
--                                                -> Bhakta (sub) and Esha
--   swap_range_in   Tue v_mon+1 09:00 +60   T2   assignment names CHANDRA, an
--                                                accepted 'date_range' plan
--                                                covers v_mon..v_mon+7.
--                                                -> Damodar, isSubstitute
--   swap_range_out  Tue v_mon+15 09:00 +60  T2   the same plan, past its end.
--                                                -> Chandra
--   swap_forever    Fri v_mon+4 16:00 +60   T3   'forever' plan, already
--                                                materialised: Esha withdrawn,
--                                                Damodar confirmed.
--                                                -> Damodar once, not twice
--   evidence        Wed v_mon-5 08:00 +60   T4   an 'occurrence' plan hands it
--                                                to Chandra, and Arpita
--                                                completed it anyway.
--                                                -> Arpita AND Chandra
--   stepped         Sat v_mon+5 14:00 +60   T5   an 'occurrence' plan hands it
--                                                to Bhakta, who then withdrew
--                                                from that occurrence.
--                                                -> nobody at all
--   openslot        Mon v_mon+0 11:00 +60        one-off, three places, none
--                                                taken. -> a block with []
--   midnight        Wed v_mon+2 23:00 +120       one-off, Bhakta. Ends 01:00
--                                                on Thursday.
--   crowd           Tue v_mon+1 12:00 +60        one-off, twenty-four devotees.
--                                                -> ONE row, twenty-four names
--   done            Thu v_mon-4 09:00 +60        one-off, Esha, completed.
--   cancelled       Fri v_mon-3 15:00 +60        one-off, cancelled by a person.
--                                                -> cancelled, nobody_served f
--   unserved        Tue v_mon-6 09:00 +60        one-off, Arpita, completed and
--                                                then marked absent, so
--                                                202608040068 closed it.
--                                                -> cancelled, nobody_served t
--
-- The final row must read: schedule and clashes verification passed
-- ---------------------------------------------------------------------------

begin;

-- The fan-out proof in §12 counts function calls, which Postgres only records
-- when it is asked to. Set once, while this session is still the superuser
-- that ran the migrations.
set local track_functions = 'all';

-- ---------------------------------------------------------------------------
-- 0. The ground.
--
--    The dials this file is calibrated against, the exact shape of every RPC
--    the two client agents are building against, and — before a single fixture
--    row exists — who may reach them.
-- ---------------------------------------------------------------------------

do $$
declare
  v_expected text;
  v_actual text;
  v_name text;
  v_shape text;
begin
  for v_expected, v_actual in
    select expected.key || '=' || expected.value,
           expected.key || '=' || coalesce(settings.value, '(absent)')
    from (values
      ('seva_schedule.default_window_days', '7'),
      ('seva_schedule.max_window_days', '35'),
      ('temple_programme.day_starts_at', '03:30'),
      ('temple_programme.day_ends_at', '21:00')
    ) as expected(key, value)
    left join public.app_settings settings on settings.key = expected.key
    where settings.value is distinct from expected.value
  loop
    raise exception 'A dial this file depends on reads % rather than %.', v_actual, v_expected;
  end loop;

  -- Exactly one of each. A leftover overload would let a client reach a
  -- function nobody reviewed.
  for v_name in
    select proc.proname
    from pg_proc proc
    join pg_namespace spaces on spaces.oid = proc.pronamespace
    where spaces.nspname = 'public'
      and proc.proname in (
        'temple_moment', 'seva_schedule_window_days', 'seva_schedule_servers',
        'list_seva_schedule', 'list_seva_clashes', 'list_temple_programme',
        'temple_timetable_hours')
    group by proc.proname
    having count(*) <> 1
  loop
    raise exception 'There is more than one public.%.', v_name;
  end loop;

  -- THE CONTRACT. Two client agents build the grid and the warning against
  -- exactly these argument lists.
  for v_name, v_shape in
    select expected.name, coalesce((
      select pg_get_function_identity_arguments(proc.oid)
      from pg_proc proc
      join pg_namespace spaces on spaces.oid = proc.pronamespace
      where spaces.nspname = 'public' and proc.proname = expected.name), '(missing)')
    from (values
      ('temple_moment', 'p_date date, p_time time without time zone'),
      ('seva_schedule_window_days', 'p_key text'),
      ('seva_schedule_servers', 'p_from date, p_to date'),
      ('list_seva_schedule', 'p_from date, p_to date, p_devotee_id uuid'),
      ('list_seva_clashes',
       'p_devotee_id uuid, p_date date, p_start_time time without time zone, p_duration_minutes integer, p_exclude_instance_id uuid'),
      ('list_temple_programme', 'p_from date, p_to date'),
      ('temple_timetable_hours', '')
    ) as expected(name, args)
    where expected.args is distinct from coalesce((
      select pg_get_function_identity_arguments(proc.oid)
      from pg_proc proc
      join pg_namespace spaces on spaces.oid = proc.pronamespace
      where spaces.nspname = 'public' and proc.proname = expected.name), '(missing)')
  loop
    raise exception 'public.% takes (%), which is not the contract.', v_name, v_shape;
  end loop;

  -- THE RETURN SHAPES, column by column and type by type, for the same reason.
  for v_name, v_shape in
    select expected.sig,
      coalesce(pg_get_function_result(to_regprocedure(expected.sig)), '(missing)')
    from (values
      ('public.list_seva_schedule(date, date, uuid)',
       'TABLE(service_instance_id uuid, template_id uuid, from_weekly_template boolean, seva_name text, service_type_id uuid, service_category text, occurs_on date, day_of_week integer, starts_at_local time without time zone, ends_at_local time without time zone, ends_next_day boolean, duration_minutes integer, starts_at timestamp with time zone, ends_at timestamp with time zone, status text, nobody_served boolean, participation_mode text, posted_by uuid, slots_needed integer, filled_slots integer, open_slots integer, roster_visible boolean, servers jsonb)'),
      ('public.list_seva_clashes(uuid, date, time, integer, uuid)',
       'TABLE(service_instance_id uuid, template_id uuid, from_weekly_template boolean, seva_name text, name_visible boolean, occurs_on date, starts_at_local time without time zone, ends_at_local time without time zone, ends_next_day boolean, starts_at timestamp with time zone, ends_at timestamp with time zone, status text, assignment_status text, is_substitute boolean, overlap_minutes integer, overlap_starts_at timestamp with time zone, overlap_ends_at timestamp with time zone, covers_whole_request boolean)'),
      ('public.list_temple_programme(date, date)',
       'TABLE(programme_id uuid, kind text, name text, occurs_on date, day_of_week integer, starts_at_local time without time zone, ends_at_local time without time zone, duration_minutes integer, starts_at timestamp with time zone, ends_at timestamp with time zone, sort_order integer)'),
      ('public.temple_timetable_hours()',
       'TABLE(day_starts_at time without time zone, day_ends_at time without time zone)'),
      ('public.seva_schedule_servers(date, date)',
       'TABLE(service_instance_id uuid, devotee_id uuid, assignment_id uuid, assignment_status text, attendance text, verification text, points_status text, is_substitute boolean, covering_for_devotee_id uuid)')
    ) as expected(sig, columns)
    where expected.columns is distinct from
      coalesce(pg_get_function_result(to_regprocedure(expected.sig)), '(missing)')
  loop
    raise exception 'The return shape of % is %, which is not the contract.', v_name, v_shape;
  end loop;

  -- THE DOORS. Four for the client, two for nobody.
  for v_name in
    select expected.sig
    from (values
      ('public.list_seva_schedule(date, date, uuid)'),
      ('public.list_seva_clashes(uuid, date, time, integer, uuid)'),
      ('public.list_temple_programme(date, date)'),
      ('public.temple_timetable_hours()'),
      ('public.temple_moment(date, time)')
    ) as expected(sig)
    where not has_function_privilege('authenticated', expected.sig, 'execute')
       or has_function_privilege('anon', expected.sig, 'execute')
  loop
    raise exception 'The grants on % are wrong: a devotee must reach it and a signed-out visitor must not.', v_name;
  end loop;
  for v_name in
    select expected.sig
    from (values
      ('public.seva_schedule_servers(date, date)'),
      ('public.seva_schedule_window_days(text)')
    ) as expected(sig)
    where has_function_privilege('authenticated', expected.sig, 'execute')
       or has_function_privilege('anon', expected.sig, 'execute')
  loop
    raise exception
      'A client role can call %, which answers without asking who is looking.', v_name;
  end loop;

  -- Nothing in this feature writes. Header §4 of the migration is a promise
  -- and a promise in a comment is a wish.
  for v_name in
    select expected.sig
    from (values
      ('public.list_seva_schedule(date, date, uuid)'),
      ('public.list_seva_clashes(uuid, date, time, integer, uuid)'),
      ('public.list_temple_programme(date, date)'),
      ('public.seva_schedule_servers(date, date)')
    ) as expected(sig)
    where pg_get_functiondef(to_regprocedure(expected.sig))
          ~* '(insert\s+into|update\s+public|delete\s+from|queue_app_notification)'
  loop
    raise exception '% has learned to write.', v_name;
  end loop;
  for v_name in
    select expected.sig
    from (values
      ('public.list_seva_schedule(date, date, uuid)'),
      ('public.list_seva_clashes(uuid, date, time, integer, uuid)'),
      ('public.list_temple_programme(date, date)'),
      ('public.seva_schedule_servers(date, date)'),
      ('public.temple_moment(date, time)')
    ) as expected(sig)
    where (select provolatile from pg_proc where oid = to_regprocedure(expected.sig)) <> 's'
  loop
    raise exception '% is not stable, so it is allowed to have side effects.', v_name;
  end loop;

  -- NEVER current_date, and never the session's zone.
  for v_name in
    select expected.sig
    from (values
      ('public.list_seva_schedule(date, date, uuid)'),
      ('public.list_seva_clashes(uuid, date, time, integer, uuid)'),
      ('public.list_temple_programme(date, date)'),
      ('public.seva_schedule_servers(date, date)'),
      ('public.temple_moment(date, time)')
    ) as expected(sig)
    where pg_get_functiondef(to_regprocedure(expected.sig)) ~* 'current_date|localtimestamp'
  loop
    raise exception '% reads the session''s calendar instead of the temple''s.', v_name;
  end loop;

  -- Header §4. The clash check decides nothing, and cannot be wired into a
  -- guard without this failing.
  for v_name in
    select proc.proname
    from pg_proc proc
    join pg_namespace spaces on spaces.oid = proc.pronamespace
    where spaces.nspname = 'public'
      and proc.proname <> 'list_seva_clashes'
      and proc.prosrc like '%list_seva_clashes%'
  loop
    raise exception
      'public.% calls public.list_seva_clashes. A clash is a warning, not a refusal.', v_name;
  end loop;

  -- Header §6. Everyone who may see the whole board can already read every row
  -- of it one at a time, so the timetable is a faster path and not a wider one.
  if exists (
    select 1 from public.roles
    where exists (
      select 1 from public.role_permissions
      where role_permissions.role_id = roles.id
        and role_permissions.permission_key in ('services.manage_recurring', 'app.view_all'))
      and not exists (
        select 1 from public.role_permissions
        where role_permissions.role_id = roles.id
          and role_permissions.permission_key = 'services.view_all')
  ) then
    raise exception 'A whole-board viewer does not hold services.view_all.';
  end if;

  -- Header §5. The temple's programme, exactly as the temple dictated it.
  if (select count(*) from public.temple_programme) <> 10 then
    raise exception 'The temple programme holds % rows rather than ten.',
      (select count(*) from public.temple_programme);
  end if;
  for v_name in
    select expected.name || ' ' || expected.days::text || ' ' || expected.starts::text
    from (values
      ('Mangala Arati',           array[0,1,2,3,4,5,6], time '04:30', null::integer),
      ('Japa Meditation',         array[0,1,2,3,4,5,6], time '05:15', 105),
      ('Sringara Arati',          array[0,1,2,3,4,5,6], time '07:00', null),
      ('Srimad Bhagavatam Class', array[0,1,2,3,4,5,6], time '07:30', 60),
      ('Raja Bhoga Arati',        array[0,1,2,3,4,5,6], time '12:30', null),
      ('Gaura Arati',             array[1,2,3,4,5,6],   time '18:00', 30),
      ('Gaura Arati',             array[0],             time '17:00', 30),
      ('Sunday Lecture',          array[0],             time '17:30', 60),
      ('Prasadam',                array[0],             time '18:30', 30),
      ('Kirtan',                  array[0],             time '19:00', 60)
    ) as expected(name, days, starts, minutes)
    where not exists (
      select 1 from public.temple_programme programme
      where programme.name = expected.name
        and programme.starts_at_local = expected.starts
        and programme.days_of_week = expected.days
        and programme.duration_minutes is not distinct from expected.minutes
        and programme.active
    )
  loop
    raise exception 'The temple programme is missing or has moved: %.', v_name;
  end loop;

  -- 202608040068's fact, which the feed reports rather than re-derives.
  if to_regclass('public.service_instances_unserved') is null then
    raise exception 'public.service_instances_unserved is missing.';
  end if;

  -- Header §4. One day either side is arithmetic off this cap.
  if coalesce((
    select pg_get_constraintdef(pg_constraint.oid) from pg_constraint
    where conname = 'service_instances_duration_minutes_check'), '') not like '%720%'
  then
    raise exception 'A seva is no longer capped at 720 minutes.';
  end if;

  -- No migration seeds a service_instance, so every count below is this file's.
  if (select count(*) from public.service_instances) <> 0 then
    raise exception 'Seva already exists before this file builds any.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 1. The congregation.
-- ---------------------------------------------------------------------------

create table public.sc_ids (key text primary key, id uuid not null);
grant select on public.sc_ids to authenticated;

create table public.sc_rows (key text primary key, instance_id uuid not null);
grant select on public.sc_rows to authenticated;

create table public.sc_tpl (key text primary key, template_id uuid not null);
grant select on public.sc_tpl to authenticated;

-- A probe that survives a refusal, so a guard's message can be read as a value
-- and compared with what the same probe says once the guard is broken.
create function public.sc_try(p_sql text)
returns text
language plpgsql
as $$
declare
  v_answer text;
begin
  execute p_sql into v_answer;
  return coalesce(v_answer, '(null)');
exception when others then
  return 'REFUSED: ' || sqlerrm;
end;
$$;
grant execute on function public.sc_try(text) to authenticated;

-- One settled coverage handover, written the way 202608030009 writes one: a
-- resolved exception naming the substitute, and an accepted plan carrying the
-- scope, the window and the weekdays.
create function public.sc_cover(
  p_instance_id uuid, p_template_id uuid, p_original uuid, p_substitute uuid,
  p_scope text, p_from date, p_to date, p_days integer[]
)
returns void
language plpgsql
as $$
declare
  v_group uuid := gen_random_uuid();
  v_exception uuid;
begin
  insert into public.service_exceptions (
    service_instance_id, devotee_id, status, resolution_kind,
    substitute_devotee_id, resolved_at, resolved_by, request_group_id,
    unavailable_scope, unavailable_from, unavailable_to, unavailable_days)
  values (
    p_instance_id, p_original, 'resolved', 'substitute', p_substitute, now(),
    (select id from public.sc_ids where key = 'pres'), v_group,
    case when p_scope = 'forever' then 'forever' else p_scope end,
    p_from, case when p_scope = 'forever' then null else p_to end, p_days)
  returning id into v_exception;

  insert into public.service_coverage_plans (
    service_exception_id, request_group_id, service_template_id,
    original_devotee_id, substitute_devotee_id, scope, date_from, date_to,
    days_of_week, status, created_by, responded_at)
  values (
    v_exception, v_group, p_template_id, p_original, p_substitute, p_scope,
    p_from, case when p_scope = 'forever' then null else p_to end, p_days,
    'accepted', (select id from public.sc_ids where key = 'pres'), now());
end;
$$;

do $$
declare
  v_who record;
  v_i integer := 0;
begin
  for v_who in
    select * from (values
      ('pres', 'Schedule President'),
      ('tech', 'Schedule Tech Admin'),
      ('head', 'Schedule Community Head'),
      ('vol',  'Schedule Volunteer'),
      ('arpita',  'Arpita Devi Dasi'),
      ('bhakta',  'Bhakta Das'),
      ('chandra', 'Chandra Das'),
      ('damodar', 'Damodar Das'),
      ('esha',    'Esha Devi Dasi'),
      ('outsider','Outsider Das')
    ) as cast_member(key, name)
  loop
    v_i := v_i + 1;
    insert into auth.users (id, email, raw_user_meta_data)
    values (
      ('5c000000-0000-0000-0000-0000000000' || lpad(v_i::text, 2, '0'))::uuid,
      'sc-' || v_who.key || '@example.test',
      jsonb_build_object('name', v_who.name));
    update public.users set name = v_who.name
    where users.email = 'sc-' || v_who.key || '@example.test';
    insert into public.sc_ids (key, id)
    select v_who.key, users.id from public.users
    where users.email = 'sc-' || v_who.key || '@example.test';
  end loop;

  -- The crowd, for §12. Twenty-four devotees on one seva.
  for v_i in 1..24 loop
    insert into auth.users (id, email, raw_user_meta_data)
    values (
      ('5c000000-0000-0000-0000-0000000001' || lpad(v_i::text, 2, '0'))::uuid,
      'sc-crowd-' || v_i || '@example.test',
      jsonb_build_object('name', 'Crowd ' || lpad(v_i::text, 2, '0') || ' Das'));
    update public.users set name = 'Crowd ' || lpad(v_i::text, 2, '0') || ' Das'
    where users.email = 'sc-crowd-' || v_i || '@example.test';
    insert into public.sc_ids (key, id)
    select 'crowd' || v_i, users.id from public.users
    where users.email = 'sc-crowd-' || v_i || '@example.test';
  end loop;
end;
$$;

update public.users users
set role_id = roles.id
from public.roles roles
where (users.email, roles.name) in (
  ('sc-pres@example.test', 'president'),
  ('sc-tech@example.test', 'tech'),
  ('sc-head@example.test', 'core'),
  ('sc-vol@example.test', 'volunteer'));

-- ---------------------------------------------------------------------------
-- 2. The roster.
--
--    Five weekly templates, five one-off seva and one crowd, exactly as the
--    header's table describes them. The coverage plans are written as
--    202608030009 writes them — an exception and a plan, both settled — and
--    the assignments are deliberately left in the two states the swap can
--    leave them in: rewritten (swap_forever) and not yet rewritten
--    (swap_occ, swap_range_in), which is the late-generation shape.
-- ---------------------------------------------------------------------------

do $$
declare
  v_type uuid;
  v_pres uuid := (select id from public.sc_ids where key = 'pres');
  v_arpita uuid := (select id from public.sc_ids where key = 'arpita');
  v_bhakta uuid := (select id from public.sc_ids where key = 'bhakta');
  v_chandra uuid := (select id from public.sc_ids where key = 'chandra');
  v_damodar uuid := (select id from public.sc_ids where key = 'damodar');
  v_esha uuid := (select id from public.sc_ids where key = 'esha');
  v_mon date := public.seva_mala_week_start(public.seva_mala_today());
  v_tpl uuid;
  v_inst uuid;
  v_i integer;
begin
  select service_types.id into v_type
  from public.service_types where service_types.name = 'Pot Washing';
  if v_type is null then
    raise exception 'The Pot Washing service type is missing from the seed.';
  end if;

  -- T1 Thursday, and the occurrence swap.
  insert into public.service_templates (service_type_id, day_of_week, days_of_week,
    start_time, duration_minutes, slots_needed, participation_mode, start_date,
    created_by, active)
  values (v_type, 4, array[4], time '10:00', 90, 2, 'invite_only', v_mon - 60, v_pres, true)
  returning id into v_tpl;
  insert into public.sc_tpl values ('t1', v_tpl);
  insert into public.service_template_assignees (service_template_id, devotee_id,
    assigned_by, status, days_of_week)
  values (v_tpl, v_arpita, v_pres, 'active', array[4]);
  insert into public.service_instances (template_id, service_type_id, date, start_time,
    duration_minutes, slots_needed, participation_mode, status)
  values (v_tpl, v_type, v_mon + 3, time '10:00', 90, 2, 'invite_only', 'open')
  returning id into v_inst;
  insert into public.sc_rows values ('swap_occ', v_inst);
  insert into public.service_assignments (service_instance_id, devotee_id,
    assignment_method, assigned_by, status, verification)
  values (v_inst, v_arpita, 'recurring_assignment', v_pres, 'confirmed', 'self_report');
  -- Esha holds the second place on the same Thursday and is covered by
  -- nothing, so she is the co-server Bhakta must not be shown.
  insert into public.service_assignments (service_instance_id, devotee_id,
    assignment_method, assigned_by, status, verification)
  values (v_inst, v_esha, 'accepted_offer', v_pres, 'confirmed', 'self_report');
  perform public.sc_cover(v_inst, v_tpl, v_arpita, v_bhakta, 'occurrence',
    v_mon + 3, v_mon + 3, array[4]);

  -- T2 Tuesday, and the date_range swap that reaches past its end.
  insert into public.service_templates (service_type_id, day_of_week, days_of_week,
    start_time, duration_minutes, slots_needed, participation_mode, start_date,
    created_by, active)
  values (v_type, 2, array[2], time '09:00', 60, 2, 'invite_only', v_mon - 60, v_pres, true)
  returning id into v_tpl;
  insert into public.sc_tpl values ('t2', v_tpl);
  insert into public.service_template_assignees (service_template_id, devotee_id,
    assigned_by, status, days_of_week)
  values (v_tpl, v_chandra, v_pres, 'active', array[2]);
  insert into public.service_instances (template_id, service_type_id, date, start_time,
    duration_minutes, slots_needed, participation_mode, status)
  values (v_tpl, v_type, v_mon + 1, time '09:00', 60, 2, 'invite_only', 'open')
  returning id into v_inst;
  insert into public.sc_rows values ('swap_range_in', v_inst);
  insert into public.service_assignments (service_instance_id, devotee_id,
    assignment_method, assigned_by, status, verification)
  values (v_inst, v_chandra, 'recurring_assignment', v_pres, 'confirmed', 'self_report');
  perform public.sc_cover(v_inst, v_tpl, v_chandra, v_damodar, 'date_range',
    v_mon, v_mon + 7, array[2]);

  insert into public.service_instances (template_id, service_type_id, date, start_time,
    duration_minutes, slots_needed, participation_mode, status)
  values (v_tpl, v_type, v_mon + 15, time '09:00', 60, 2, 'invite_only', 'open')
  returning id into v_inst;
  insert into public.sc_rows values ('swap_range_out', v_inst);
  insert into public.service_assignments (service_instance_id, devotee_id,
    assignment_method, assigned_by, status, verification)
  values (v_inst, v_chandra, 'recurring_assignment', v_pres, 'confirmed', 'self_report');

  -- T3 Friday, and the forever swap, already materialised on the occurrence.
  insert into public.service_templates (service_type_id, day_of_week, days_of_week,
    start_time, duration_minutes, slots_needed, participation_mode, start_date,
    created_by, active)
  values (v_type, 5, array[5], time '16:00', 60, 2, 'invite_only', v_mon - 60, v_pres, true)
  returning id into v_tpl;
  insert into public.sc_tpl values ('t3', v_tpl);
  insert into public.service_template_assignees (service_template_id, devotee_id,
    assigned_by, status, days_of_week)
  values (v_tpl, v_damodar, v_pres, 'active', array[5]);
  insert into public.service_instances (template_id, service_type_id, date, start_time,
    duration_minutes, slots_needed, participation_mode, status)
  values (v_tpl, v_type, v_mon + 4, time '16:00', 60, 2, 'invite_only', 'open')
  returning id into v_inst;
  insert into public.sc_rows values ('swap_forever', v_inst);
  insert into public.service_assignments (service_instance_id, devotee_id,
    assignment_method, assigned_by, status, verification)
  values (v_inst, v_esha, 'recurring_assignment', v_pres, 'withdrawn', 'self_report');
  insert into public.service_assignments (service_instance_id, devotee_id,
    assignment_method, assigned_by, status, verification)
  values (v_inst, v_damodar, 'accepted_coverage_offer', v_pres, 'confirmed', 'self_report');
  perform public.sc_cover(v_inst, v_tpl, v_esha, v_damodar, 'forever',
    v_mon, null, array[5]);

  -- T4 last Wednesday, where the original served it anyway.
  insert into public.service_templates (service_type_id, day_of_week, days_of_week,
    start_time, duration_minutes, slots_needed, participation_mode, start_date,
    created_by, active)
  values (v_type, 3, array[3], time '08:00', 60, 2, 'invite_only', v_mon - 60, v_pres, true)
  returning id into v_tpl;
  insert into public.sc_tpl values ('t4', v_tpl);
  insert into public.service_template_assignees (service_template_id, devotee_id,
    assigned_by, status, days_of_week)
  values (v_tpl, v_arpita, v_pres, 'active', array[3]);
  insert into public.service_instances (template_id, service_type_id, date, start_time,
    duration_minutes, slots_needed, participation_mode, status)
  values (v_tpl, v_type, v_mon - 5, time '08:00', 60, 2, 'invite_only', 'open')
  returning id into v_inst;
  insert into public.sc_rows values ('evidence', v_inst);
  insert into public.service_assignments (service_instance_id, devotee_id,
    assignment_method, assigned_by, status, verification, attendance, completed_at)
  values (v_inst, v_arpita, 'recurring_assignment', v_pres, 'completed', 'self_report',
    'served', now());
  perform public.sc_cover(v_inst, v_tpl, v_arpita, v_chandra, 'occurrence',
    v_mon - 5, v_mon - 5, array[3]);

  -- T5 Saturday, where the substitute then withdrew from that one occurrence.
  insert into public.service_templates (service_type_id, day_of_week, days_of_week,
    start_time, duration_minutes, slots_needed, participation_mode, start_date,
    created_by, active)
  values (v_type, 6, array[6], time '14:00', 60, 2, 'invite_only', v_mon - 60, v_pres, true)
  returning id into v_tpl;
  insert into public.sc_tpl values ('t5', v_tpl);
  insert into public.service_template_assignees (service_template_id, devotee_id,
    assigned_by, status, days_of_week)
  values (v_tpl, v_arpita, v_pres, 'active', array[6]);
  insert into public.service_instances (template_id, service_type_id, date, start_time,
    duration_minutes, slots_needed, participation_mode, status)
  values (v_tpl, v_type, v_mon + 5, time '14:00', 60, 2, 'invite_only', 'open')
  returning id into v_inst;
  insert into public.sc_rows values ('stepped', v_inst);
  insert into public.service_assignments (service_instance_id, devotee_id,
    assignment_method, assigned_by, status, verification)
  values (v_inst, v_arpita, 'recurring_assignment', v_pres, 'confirmed', 'self_report');
  insert into public.service_assignments (service_instance_id, devotee_id,
    assignment_method, assigned_by, status, verification)
  values (v_inst, v_bhakta, 'accepted_coverage_offer', v_pres, 'withdrawn', 'self_report');
  perform public.sc_cover(v_inst, v_tpl, v_arpita, v_bhakta, 'occurrence',
    v_mon + 5, v_mon + 5, array[6]);

  -- The one-off seva.
  insert into public.service_instances (service_type_id, date, start_time,
    duration_minutes, slots_needed, participation_mode, posted_by, status)
  values (v_type, v_mon, time '11:00', 60, 3, 'open', v_pres, 'open')
  returning id into v_inst;
  insert into public.sc_rows values ('openslot', v_inst);

  insert into public.service_instances (service_type_id, date, start_time,
    duration_minutes, slots_needed, participation_mode, posted_by, status)
  values (v_type, v_mon + 2, time '23:00', 120, 3, 'open', v_pres, 'open')
  returning id into v_inst;
  insert into public.sc_rows values ('midnight', v_inst);
  insert into public.service_assignments (service_instance_id, devotee_id,
    assignment_method, assigned_by, status, verification)
  values (v_inst, v_bhakta, 'self_joined', v_bhakta, 'confirmed', 'self_report');

  insert into public.service_instances (service_type_id, date, start_time,
    duration_minutes, slots_needed, participation_mode, posted_by, status)
  values (v_type, v_mon + 1, time '12:00', 60, 40, 'open', v_pres, 'open')
  returning id into v_inst;
  insert into public.sc_rows values ('crowd', v_inst);
  for v_i in 1..24 loop
    insert into public.service_assignments (service_instance_id, devotee_id,
      assignment_method, assigned_by, status, verification)
    select v_inst, ids.id, 'self_joined', ids.id, 'confirmed', 'self_report'
    from public.sc_ids ids where ids.key = 'crowd' || v_i;
  end loop;

  insert into public.service_instances (service_type_id, date, start_time,
    duration_minutes, slots_needed, participation_mode, posted_by, status)
  values (v_type, v_mon - 4, time '09:00', 60, 1, 'open', v_pres, 'open')
  returning id into v_inst;
  insert into public.sc_rows values ('done', v_inst);
  insert into public.service_assignments (service_instance_id, devotee_id,
    assignment_method, assigned_by, status, verification)
  values (v_inst, v_esha, 'self_joined', v_esha, 'confirmed', 'self_report');

  insert into public.service_instances (service_type_id, date, start_time,
    duration_minutes, slots_needed, participation_mode, posted_by, status)
  values (v_type, v_mon - 3, time '15:00', 60, 1, 'open', v_pres, 'cancelled')
  returning id into v_inst;
  insert into public.sc_rows values ('cancelled', v_inst);
  insert into public.service_assignments (service_instance_id, devotee_id,
    assignment_method, assigned_by, status, verification)
  values (v_inst, v_chandra, 'self_joined', v_chandra, 'withdrawn', 'self_report');

  insert into public.service_instances (service_type_id, date, start_time,
    duration_minutes, slots_needed, participation_mode, posted_by, status)
  values (v_type, v_mon - 6, time '09:00', 60, 1, 'open', v_pres, 'open')
  returning id into v_inst;
  insert into public.sc_rows values ('unserved', v_inst);
  insert into public.service_assignments (service_instance_id, devotee_id,
    assignment_method, assigned_by, status, verification)
  values (v_inst, v_arpita, 'self_joined', v_arpita, 'confirmed', 'self_report');
end;
$$;

-- 'done' is closed by the President, and 'unserved' is closed and then has its
-- only devotee marked absent, so that 202608040068 takes it out of the
-- completed list itself rather than this file forging the row.
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.sc_ids ids where ids.key = 'pres'), true);

select public.complete_service_instance(
  (select instance_id from public.sc_rows where key = 'done'));
select public.complete_service_instance(
  (select instance_id from public.sc_rows where key = 'unserved'));
select public.record_seva_attendance(
  (select assignments.id from public.service_assignments assignments
   join public.sc_rows rows on rows.instance_id = assignments.service_instance_id
   where rows.key = 'unserved'),
  'absent');

select set_config('request.jwt.claim.sub', '', true);

do $$
begin
  if (select status from public.service_instances instances
      join public.sc_rows rows on rows.instance_id = instances.id
      where rows.key = 'unserved') <> 'cancelled'
  then
    raise exception '202608040068 did not close the unserved seva; the fixture is not the shape it claims.';
  end if;
  if (select status from public.service_instances instances
      join public.sc_rows rows on rows.instance_id = instances.id
      where rows.key = 'done') <> 'completed'
  then
    raise exception 'The completed seva is not completed; the fixture is wrong.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Who is serving, after the swaps. All three scopes and both directions of
--    "evidence outranks the plan", read straight out of the helper.
-- ---------------------------------------------------------------------------

do $$
declare
  v_mon date := public.seva_mala_week_start(public.seva_mala_today());
  v_row record;
  v_got text;
begin
  for v_row in
    select * from (values
      ('swap_occ',       'Bhakta Das, Esha Devi Dasi'),
      ('swap_range_in',  'Damodar Das'),
      ('swap_range_out', 'Chandra Das'),
      ('swap_forever',   'Damodar Das'),
      ('evidence',       'Arpita Devi Dasi, Chandra Das'),
      ('stepped',        '(nobody)'),
      ('midnight',       'Bhakta Das'),
      ('openslot',       '(nobody)')
    ) as expected(key, who)
  loop
    select coalesce(string_agg(users.name, ', ' order by users.name), '(nobody)')
    into v_got
    from public.seva_schedule_servers(v_mon - 10, v_mon + 20) servers
    join public.sc_rows rows on rows.instance_id = servers.service_instance_id
    join public.users on users.id = servers.devotee_id
    where rows.key = v_row.key;
    if v_got is distinct from v_row.who then
      raise exception 'The % seva is served by "%", not "%".', v_row.key, v_got, v_row.who;
    end if;
  end loop;

  -- The substitute is flagged as one and carries who they are covering for,
  -- and the devotee who served it anyway is not flagged.
  if not exists (
    select 1 from public.seva_schedule_servers(v_mon - 10, v_mon + 20) servers
    join public.sc_rows rows on rows.instance_id = servers.service_instance_id
    where rows.key = 'swap_occ'
      and servers.is_substitute
      and servers.covering_for_devotee_id = (select id from public.sc_ids where key = 'arpita')
      and servers.assignment_id is null)
  then
    raise exception
      'The occurrence swap does not name Bhakta as Arpita''s substitute with no assignment row of his own.';
  end if;
  if exists (
    select 1 from public.seva_schedule_servers(v_mon - 10, v_mon + 20) servers
    join public.sc_rows rows on rows.instance_id = servers.service_instance_id
    where rows.key = 'evidence'
      and servers.devotee_id = (select id from public.sc_ids where key = 'arpita')
      and servers.is_substitute)
  then
    raise exception 'The devotee who actually served it is being called a substitute.';
  end if;

  -- The forever swap agrees with the assignment, and that must be ONE row.
  if (select count(*) from public.seva_schedule_servers(v_mon - 10, v_mon + 20) servers
      join public.sc_rows rows on rows.instance_id = servers.service_instance_id
      where rows.key = 'swap_forever') <> 1
  then
    raise exception
      'A substitute who is both on the plan and on the assignment is being counted twice.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. The Community Head sees the whole temple's timetable.
--
--    All of it, under `set local role authenticated` so the grant is what is
--    being used, and every column of one block read out in full.
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.sc_ids ids where ids.key = 'head'), true);

do $$
declare
  v_mon date := public.seva_mala_week_start(public.seva_mala_today());
  v_block record;
  v_count integer;
begin
  select count(*) into v_count
  from public.list_seva_schedule(v_mon - 10, v_mon + 20);
  if v_count <> (select count(*) from public.sc_rows) then
    raise exception
      'The Community Head sees % of the % seva in the window.', v_count, (select count(*) from public.sc_rows);
  end if;

  -- The midnight crosser, column by column. This is the block the grid has to
  -- draw across two days.
  select * into v_block
  from public.list_seva_schedule(v_mon - 10, v_mon + 20) feed
  where feed.service_instance_id = (select instance_id from public.sc_rows where key = 'midnight');
  if v_block.seva_name <> 'Pot Washing'
    or v_block.from_weekly_template
    or v_block.template_id is not null
    or v_block.occurs_on <> v_mon + 2
    or v_block.day_of_week <> 3
    or v_block.starts_at_local <> time '23:00'
    or v_block.ends_at_local <> time '01:00'
    or not v_block.ends_next_day
    or v_block.duration_minutes <> 120
    or v_block.starts_at <> public.temple_moment(v_mon + 2, time '23:00')
    or v_block.ends_at <> public.temple_moment(v_mon + 2, time '23:00') + interval '120 minutes'
    or v_block.status <> 'open'
    or v_block.nobody_served
    or v_block.slots_needed <> 3
    or v_block.filled_slots <> 1
    or v_block.open_slots <> 2
    or not v_block.roster_visible
    or jsonb_array_length(v_block.servers) <> 1
    or v_block.servers -> 0 ->> 'name' <> 'Bhakta Das'
  then
    raise exception 'The midnight block reads wrong: %', to_jsonb(v_block);
  end if;

  -- The seva nobody has taken is a block with nobody on it, not a missing one.
  select * into v_block
  from public.list_seva_schedule(v_mon - 10, v_mon + 20) feed
  where feed.service_instance_id = (select instance_id from public.sc_rows where key = 'openslot');
  if v_block.servers <> '[]'::jsonb or v_block.filled_slots <> 0 or v_block.open_slots <> 3 then
    raise exception 'The untaken seva does not read as three open places: %', to_jsonb(v_block);
  end if;

  -- A weekly block carries its template, because the Head may open it.
  select * into v_block
  from public.list_seva_schedule(v_mon - 10, v_mon + 20) feed
  where feed.service_instance_id = (select instance_id from public.sc_rows where key = 'swap_occ');
  if not v_block.from_weekly_template
    or v_block.template_id is distinct from (select template_id from public.sc_tpl where key = 't1')
    or v_block.servers -> 0 ->> 'name' <> 'Bhakta Das'
    or (v_block.servers -> 0 ->> 'isSubstitute')::boolean is not true
    or v_block.servers -> 0 ->> 'coveringForName' <> 'Arpita Devi Dasi'
  then
    raise exception 'The handed-over Thursday does not name the substitute: %', to_jsonb(v_block);
  end if;

  -- Ordering: a grid pages forward and expects the days in order.
  if exists (
    select 1 from (
      select feed.occurs_on, feed.starts_at_local,
        lag(feed.occurs_on) over () as prev_date,
        lag(feed.starts_at_local) over () as prev_time
      from public.list_seva_schedule(v_mon - 10, v_mon + 20) feed
    ) ordered
    where ordered.prev_date is not null
      and (ordered.occurs_on, ordered.starts_at_local) < (ordered.prev_date, ordered.prev_time))
  then
    raise exception 'The feed does not come back in timetable order.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);

-- The President and the Tech Admin see the same board, and a Volunteer does not.
do $$
declare
  v_mon date := public.seva_mala_week_start(public.seva_mala_today());
  v_who text;
  v_answer text;
begin
  for v_who in select unnest(array['pres', 'tech', 'head']) loop
    perform set_config('request.jwt.claim.sub',
      (select ids.id::text from public.sc_ids ids where ids.key = v_who), true);
    if (select count(*) from public.list_seva_schedule(v_mon - 10, v_mon + 20))
       <> (select count(*) from public.sc_rows)
    then
      raise exception '% cannot see the whole board.', v_who;
    end if;
  end loop;

  for v_who in select unnest(array['vol', 'arpita', 'outsider']) loop
    perform set_config('request.jwt.claim.sub',
      (select ids.id::text from public.sc_ids ids where ids.key = v_who), true);
    v_answer := public.sc_try(format(
      'select count(*)::text from public.list_seva_schedule(%L::date, %L::date)',
      v_mon - 10, v_mon + 20));
    if v_answer not like 'REFUSED:%' then
      raise exception '% read the whole temple''s timetable and got %.', v_who, v_answer;
    end if;
  end loop;
  perform set_config('request.jwt.claim.sub', '', true);
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. A devotee sees their own schedule, and only their own.
--
--    Bhakta is the hard case: on swap_occ he is the substitute a plan names
--    and he has no assignment row of his own, so 202608030009 does not grant
--    him the template and RLS does not grant him the roster. He gets the
--    block, his own place on it, no template id and nobody else's name.
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.sc_ids ids where ids.key = 'bhakta'), true);

do $$
declare
  v_mon date := public.seva_mala_week_start(public.seva_mala_today());
  v_bhakta uuid := (select id from public.sc_ids where key = 'bhakta');
  v_keys text;
  v_block record;
begin
  select string_agg(rows.key, ', ' order by rows.key) into v_keys
  from public.list_seva_schedule(v_mon - 10, v_mon + 20, v_bhakta) feed
  join public.sc_rows rows on rows.instance_id = feed.service_instance_id;
  if v_keys is distinct from 'midnight, swap_occ' then
    raise exception 'Bhakta''s own timetable is "%", not "midnight, swap_occ".', v_keys;
  end if;

  select * into v_block
  from public.list_seva_schedule(v_mon - 10, v_mon + 20, v_bhakta) feed
  where feed.service_instance_id = (select instance_id from public.sc_rows where key = 'swap_occ');
  if not v_block.from_weekly_template then
    raise exception 'A substitute is not told the block came from a weekly seva.';
  end if;
  if v_block.template_id is not null then
    raise exception
      'A substitute was handed the weekly template id, which 202608030009 does not grant them.';
  end if;
  if v_block.roster_visible then
    raise exception 'A substitute with no assignment row was told the roster is his to read.';
  end if;
  if jsonb_array_length(v_block.servers) <> 1
    or v_block.servers -> 0 ->> 'name' <> 'Bhakta Das'
  then
    raise exception 'A substitute was shown somebody else on a seva RLS refuses him: %',
      v_block.servers;
  end if;
  -- The count is still the truth; it is a number, not a name.
  if v_block.filled_slots <> 2 or v_block.open_slots <> 0 then
    raise exception 'The places on the block were miscounted for the substitute.';
  end if;
  -- He is told who he is covering for, because he is one of the two people it
  -- is about.
  if v_block.servers -> 0 ->> 'coveringForName' <> 'Arpita Devi Dasi' then
    raise exception 'The substitute is not told whose Thursday he has.';
  end if;
end;
$$;

-- And an ordinary devotee gets nothing for somebody else.
do $$
declare
  v_mon date := public.seva_mala_week_start(public.seva_mala_today());
  v_answer text;
begin
  v_answer := public.sc_try(format(
    'select count(*)::text from public.list_seva_schedule(%L::date, %L::date, %L::uuid)',
    v_mon - 10, v_mon + 20, (select id from public.sc_ids where key = 'arpita')));
  if v_answer not like 'REFUSED:%' then
    raise exception 'Bhakta read Arpita''s schedule and got %.', v_answer;
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);

-- A board viewer may read one named devotee's, which is the whole point of the
-- third argument: seeing when somebody is free before asking them.
set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.sc_ids ids where ids.key = 'head'), true);

do $$
declare
  v_mon date := public.seva_mala_week_start(public.seva_mala_today());
  v_keys text;
begin
  select string_agg(rows.key, ', ' order by rows.key) into v_keys
  from public.list_seva_schedule(v_mon - 10, v_mon + 20,
    (select id from public.sc_ids where key = 'damodar')) feed
  join public.sc_rows rows on rows.instance_id = feed.service_instance_id;
  if v_keys is distinct from 'swap_forever, swap_range_in' then
    raise exception 'The Head reads Damodar''s week as "%".', v_keys;
  end if;

  -- Arpita's own week, which is what is left after two of her three Thursdays
  -- and Saturdays were handed away: only the seva she actually served.
  select string_agg(rows.key, ', ' order by rows.key) into v_keys
  from public.list_seva_schedule(v_mon - 10, v_mon + 20,
    (select id from public.sc_ids where key = 'arpita')) feed
  join public.sc_rows rows on rows.instance_id = feed.service_instance_id;
  if v_keys is distinct from 'evidence, unserved' then
    raise exception 'Arpita''s week reads "%", not "evidence, unserved".', v_keys;
  end if;

  -- A devotee who does not exist is refused, and only after the permission
  -- check, so this is not a way to learn who has an account.
  if public.sc_try(
       'select count(*)::text from public.list_seva_schedule(null, null, ''00000000-0000-0000-0000-0000000000ff''::uuid)')
     not like 'REFUSED:%'
  then
    raise exception 'A devotee who does not exist has a timetable.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Cancelled, completed, and nobody served — told apart.
-- ---------------------------------------------------------------------------

do $$
declare
  v_mon date := public.seva_mala_week_start(public.seva_mala_today());
  v_row record;
  v_block record;
begin
  for v_row in
    select * from (values
      ('done',      'completed', false),
      ('cancelled', 'cancelled', false),
      ('unserved',  'cancelled', true),
      ('openslot',  'open',      false)
    ) as expected(key, status, nobody)
  loop
    select * into v_block
    from public.list_seva_schedule(v_mon - 10, v_mon + 20) feed
    where feed.service_instance_id = (select instance_id from public.sc_rows where key = v_row.key);
    if v_block.status <> v_row.status or v_block.nobody_served <> v_row.nobody then
      raise exception
        'The % seva reads status % / nobody_served %, not % / %.',
        v_row.key, v_block.status, v_block.nobody_served, v_row.status, v_row.nobody;
    end if;
  end loop;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);

-- ---------------------------------------------------------------------------
-- 7. Clashes. Partial, total, across midnight, back-to-back, and after a swap.
--
--    Bhakta serves swap_occ on Thursday 10:00 to 11:30 and midnight on
--    Wednesday 23:00 to 01:00, so every case below is one question about one
--    of those two.
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.sc_ids ids where ids.key = 'bhakta'), true);

do $$
declare
  v_mon date := public.seva_mala_week_start(public.seva_mala_today());
  v_bhakta uuid := (select id from public.sc_ids where key = 'bhakta');
  v_clash record;
  v_count integer;
begin
  -- PARTIAL. The temple's own sentence: serving until 11:30, asked for 11:15.
  select * into v_clash
  from public.list_seva_clashes(v_bhakta, v_mon + 3, time '11:15', 60);
  if v_clash.service_instance_id is distinct from
       (select instance_id from public.sc_rows where key = 'swap_occ')
    or v_clash.overlap_minutes <> 15
    or v_clash.covers_whole_request
    or v_clash.starts_at_local <> time '10:00'
    or v_clash.ends_at_local <> time '11:30'
    or v_clash.overlap_starts_at <> public.temple_moment(v_mon + 3, time '11:15')
    or v_clash.overlap_ends_at <> public.temple_moment(v_mon + 3, time '11:30')
    or not v_clash.is_substitute
    or not v_clash.name_visible
    or v_clash.seva_name <> 'Pot Washing'
  then
    raise exception 'The fifteen-minute brush reads wrong: %', to_jsonb(v_clash);
  end if;

  -- TOTAL. Asked for half an hour inside a ninety-minute seva.
  select * into v_clash
  from public.list_seva_clashes(v_bhakta, v_mon + 3, time '10:15', 30);
  if v_clash.overlap_minutes <> 30 or not v_clash.covers_whole_request then
    raise exception 'A seva wholly inside another is not reported as one: %', to_jsonb(v_clash);
  end if;

  -- BACK TO BACK IS NOT A CLASH. Half-open ranges, on purpose.
  select count(*) into v_count
  from public.list_seva_clashes(v_bhakta, v_mon + 3, time '11:30', 60);
  if v_count <> 0 then
    raise exception 'Seva starting the minute another ends is being called a clash.';
  end if;
  select count(*) into v_count
  from public.list_seva_clashes(v_bhakta, v_mon + 3, time '09:00', 60);
  if v_count <> 0 then
    raise exception 'Seva ending the minute another begins is being called a clash.';
  end if;

  -- ACROSS MIDNIGHT. The seva began at 23:00 the day before.
  select * into v_clash
  from public.list_seva_clashes(v_bhakta, v_mon + 3, time '00:30', 60);
  if v_clash.service_instance_id is distinct from
       (select instance_id from public.sc_rows where key = 'midnight')
    or v_clash.occurs_on <> v_mon + 2
    or not v_clash.ends_next_day
    or v_clash.overlap_minutes <> 30
  then
    raise exception 'The seva running through midnight was not found: %', to_jsonb(v_clash);
  end if;
  -- And the other side of the same boundary, asked from the day before.
  select count(*) into v_count
  from public.list_seva_clashes(v_bhakta, v_mon + 2, time '23:30', 30);
  if v_count <> 1 then
    raise exception 'The midnight seva is not found from its own day.';
  end if;

  -- THE SEVA BEING ASKED ABOUT DOES NOT CLASH WITH ITSELF.
  select count(*) into v_count
  from public.list_seva_clashes(v_bhakta, v_mon + 3, time '10:00', 90,
    (select instance_id from public.sc_rows where key = 'swap_occ'));
  if v_count <> 0 then
    raise exception 'A seva was reported as clashing with itself.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);

-- A devotee whose Thursday was handed away is FREE on Thursday, and the
-- devotee who took it is not. This is the swap, asked as a clash.
set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.sc_ids ids where ids.key = 'arpita'), true);

do $$
declare
  v_mon date := public.seva_mala_week_start(public.seva_mala_today());
  v_arpita uuid := (select id from public.sc_ids where key = 'arpita');
begin
  if (select count(*) from public.list_seva_clashes(v_arpita, v_mon + 3, time '10:30', 30)) <> 0 then
    raise exception
      'Arpita is reported as busy on a Thursday she handed to Bhakta. The swap is not being applied to the clash check.';
  end if;
  -- And she is still busy on the Wednesday she actually served.
  if (select count(*) from public.list_seva_clashes(v_arpita, v_mon - 5, time '08:30', 30)) <> 1 then
    raise exception 'Arpita is reported as free during a seva she completed.';
  end if;
  -- A cancelled seva is not a clash. She was on the one nobody served.
  if (select count(*) from public.list_seva_clashes(v_arpita, v_mon - 6, time '09:15', 30)) <> 0 then
    raise exception 'A cancelled seva is being reported as a clash.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);

-- ---------------------------------------------------------------------------
-- 8. Who may ask about whom, and how much of the answer they get.
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.sc_ids ids where ids.key = 'vol'), true);

do $$
declare
  v_mon date := public.seva_mala_week_start(public.seva_mala_today());
  v_bhakta uuid := (select id from public.sc_ids where key = 'bhakta');
  v_clash record;
begin
  -- A Volunteer may invite a named devotee, so a Volunteer may ask whether
  -- that devotee is free — and gets the times, which is what a warning needs.
  select * into v_clash
  from public.list_seva_clashes(v_bhakta, v_mon + 3, time '11:15', 60);
  if v_clash.overlap_minutes <> 15 then
    raise exception 'A Volunteer cannot see that the devotee they are inviting is busy.';
  end if;
  -- But not the name of an invite-only seva they have nothing to do with.
  if v_clash.name_visible or v_clash.seva_name is not null then
    raise exception
      'A Volunteer was told the name of a seva RLS refuses them: %', v_clash.seva_name;
  end if;
  if v_clash.template_id is not null then
    raise exception 'A Volunteer was handed a weekly template id.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);

set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.sc_ids ids where ids.key = 'chandra'), true);

do $$
declare
  v_mon date := public.seva_mala_week_start(public.seva_mala_today());
  v_answer text;
begin
  -- An ordinary devotee may not ask about somebody else.
  v_answer := public.sc_try(format(
    'select count(*)::text from public.list_seva_clashes(%L::uuid, %L::date, ''11:15''::time, 60)',
    (select id from public.sc_ids where key = 'bhakta'), v_mon + 3));
  if v_answer not like 'REFUSED:%' then
    raise exception 'An ordinary devotee checked another devotee''s diary and got %.', v_answer;
  end if;
  -- But always about themselves, and with the name, because it is theirs.
  if (select count(*) from public.list_seva_clashes(
        (select id from public.sc_ids where key = 'chandra'), v_mon + 15, time '09:15', 30)) <> 1
  then
    raise exception 'A devotee cannot check themselves.';
  end if;
  if (select seva_name from public.list_seva_clashes(
        (select id from public.sc_ids where key = 'chandra'), v_mon + 15, time '09:15', 30))
     is distinct from 'Pot Washing'
  then
    raise exception 'A devotee is not told the name of their own seva.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);

-- Signed out, nothing at all.
do $$
begin
  perform set_config('request.jwt.claim.sub', '', true);
  if public.sc_try('select count(*)::text from public.list_seva_schedule()') not like 'REFUSED:%'
    or public.sc_try(
         'select count(*)::text from public.list_seva_clashes(null, null, null, 60)') not like 'REFUSED:%'
    or public.sc_try('select count(*)::text from public.list_temple_programme()') not like 'REFUSED:%'
  then
    raise exception 'A session with no devotee behind it can read the timetable.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 9. The clash check writes nothing and refuses nothing.
-- ---------------------------------------------------------------------------

do $$
declare
  v_before text;
  v_after text;
  v_mon date := public.seva_mala_week_start(public.seva_mala_today());
begin
  select
    (select count(*) from public.service_assignments)::text || '/' ||
    (select count(*) from public.service_instances)::text || '/' ||
    (select count(*) from public.app_notifications)::text || '/' ||
    (select count(*) from public.service_coverage_plans)::text
  into v_before;

  perform set_config('request.jwt.claim.sub',
    (select ids.id::text from public.sc_ids ids where ids.key = 'pres'), true);
  -- Every seva in the fixture, asked about at its own hour, by everybody on it.
  perform count(*)
  from public.sc_rows rows
  join public.service_instances instances on instances.id = rows.instance_id
  join lateral public.list_seva_clashes(
    (select ids.id from public.sc_ids ids where ids.key = 'bhakta'),
    instances.date, instances.start_time, instances.duration_minutes) clashes on true;

  select
    (select count(*) from public.service_assignments)::text || '/' ||
    (select count(*) from public.service_instances)::text || '/' ||
    (select count(*) from public.app_notifications)::text || '/' ||
    (select count(*) from public.service_coverage_plans)::text
  into v_after;

  if v_before is distinct from v_after then
    raise exception 'Asking about clashes changed the data: % became %.', v_before, v_after;
  end if;
  perform set_config('request.jwt.claim.sub', '', true);
end;
$$;

-- ---------------------------------------------------------------------------
-- 10. Chicago, from four session timezones.
--
--     A grid read in Mayapur must draw the temple's day. The instants, the
--     wall-clock times and the dates must all be identical whatever the
--     session's zone, which is what would break the moment anything in here
--     used date + time without naming America/Chicago.
-- ---------------------------------------------------------------------------

do $$
declare
  v_mon date := public.seva_mala_week_start(public.seva_mala_today());
  v_zone text;
  v_signature text;
  v_first text;
begin
  perform set_config('request.jwt.claim.sub',
    (select ids.id::text from public.sc_ids ids where ids.key = 'head'), true);
  for v_zone in
    select unnest(array['America/Chicago', 'UTC', 'Asia/Kolkata', 'Pacific/Auckland'])
  loop
    perform set_config('timezone', v_zone, true);
    select string_agg(
      feed.occurs_on::text || '|' || feed.starts_at_local::text || '|' ||
      feed.ends_at_local::text || '|' || feed.ends_next_day::text || '|' ||
      extract(epoch from feed.starts_at)::text, ',' order by feed.service_instance_id)
    into v_signature
    from public.list_seva_schedule(v_mon - 10, v_mon + 20) feed;
    if v_first is null then
      v_first := v_signature;
    elsif v_signature is distinct from v_first then
      raise exception 'The timetable is different when read from %.', v_zone;
    end if;

    -- And the programme with it.
    if (select starts_at from public.list_temple_programme(v_mon + 6, v_mon + 6)
        where name = 'Mangala Arati')
       <> public.temple_moment(v_mon + 6, time '04:30')
    then
      raise exception 'Mangala Arati moves when the session is in %.', v_zone;
    end if;
  end loop;
  perform set_config('timezone', 'UTC', true);
  perform set_config('request.jwt.claim.sub', '', true);
end;
$$;

-- ---------------------------------------------------------------------------
-- 11. The temple's own programme.
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.sc_ids ids where ids.key = 'arpita'), true);

do $$
declare
  v_mon date := public.seva_mala_week_start(public.seva_mala_today());
  v_row record;
  v_names text;
begin
  -- A weekday: six items, and Gaura Arati at six in the evening.
  select string_agg(programme.name || '@' || programme.starts_at_local::text, ', '
    order by programme.starts_at_local)
  into v_names
  from public.list_temple_programme(v_mon + 1, v_mon + 1) programme;
  if v_names is distinct from
    'Mangala Arati@04:30:00, Japa Meditation@05:15:00, Sringara Arati@07:00:00, ' ||
    'Srimad Bhagavatam Class@07:30:00, Raja Bhoga Arati@12:30:00, Gaura Arati@18:00:00'
  then
    raise exception 'A weekday''s programme reads "%".', v_names;
  end if;

  -- Sunday: Gaura Arati an hour earlier, and the evening programme after it.
  select string_agg(programme.name || '@' || programme.starts_at_local::text, ', '
    order by programme.starts_at_local)
  into v_names
  from public.list_temple_programme(v_mon + 6, v_mon + 6) programme;
  if v_names is distinct from
    'Mangala Arati@04:30:00, Japa Meditation@05:15:00, Sringara Arati@07:00:00, ' ||
    'Srimad Bhagavatam Class@07:30:00, Raja Bhoga Arati@12:30:00, Gaura Arati@17:00:00, ' ||
    'Sunday Lecture@17:30:00, Prasadam@18:30:00, Kirtan@19:00:00'
  then
    raise exception 'Sunday''s programme reads "%".', v_names;
  end if;

  -- The three the temple gave a start and no end have no end.
  if exists (
    select 1 from public.list_temple_programme(v_mon, v_mon + 6) programme
    where programme.name in ('Mangala Arati', 'Sringara Arati', 'Raja Bhoga Arati')
      and (programme.ends_at is not null or programme.ends_at_local is not null
           or programme.duration_minutes is not null))
  then
    raise exception 'An arati the temple gave no end for has been given one.';
  end if;
  -- And the ones that do, end where the temple said.
  select * into v_row
  from public.list_temple_programme(v_mon + 6, v_mon + 6) programme
  where programme.name = 'Kirtan';
  if v_row.starts_at_local <> time '19:00' or v_row.ends_at_local <> time '20:00'
    or v_row.ends_at <> public.temple_moment(v_mon + 6, time '20:00')
  then
    raise exception 'Sunday Kirtan does not run 19:00 to 20:00.';
  end if;

  -- Every row says plainly that it is not seva.
  if exists (
    select 1 from public.list_temple_programme(v_mon, v_mon + 6) programme
    where programme.kind is distinct from 'temple_programme')
  then
    raise exception 'A programme row does not say what it is.';
  end if;

  -- Nobody is assigned to it, so nothing can clash with it. Mangala Arati is
  -- at 04:30 every day of the fixture and no clash check ever returns it.
  if exists (
    select 1 from public.list_seva_clashes(
      (select id from public.sc_ids where key = 'arpita'), v_mon + 1, time '04:00', 120))
  then
    raise exception 'The temple programme is being reported as a seva clash.';
  end if;
  -- The grid's hours are a dial and are advisory: a seva outside them is still
  -- returned. The midnight seva starts at 23:00, which is after 21:00.
  if (select day_starts_at from public.temple_timetable_hours()) <> time '03:30'
    or (select day_ends_at from public.temple_timetable_hours()) <> time '21:00'
  then
    raise exception 'The timetable hours are not the ones the temple asked for.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);

set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.sc_ids ids where ids.key = 'head'), true);
do $$
declare
  v_mon date := public.seva_mala_week_start(public.seva_mala_today());
begin
  if not exists (
    select 1 from public.list_seva_schedule(v_mon - 10, v_mon + 20) feed
    where feed.starts_at_local > (select day_ends_at from public.temple_timetable_hours()))
  then
    raise exception
      'The fixture no longer has a seva outside the grid''s hours, so this file is not proving that the hours are advisory.';
  end if;
  -- And the programme is nowhere in the seva feed, on the whole temple's board.
  if exists (
    select 1 from public.list_seva_schedule(v_mon - 10, v_mon + 20) feed
    where feed.seva_name in ('Mangala Arati', 'Kirtan', 'Sringara Arati', 'Prasadam'))
  then
    raise exception 'The temple programme is leaking into the seva feed.';
  end if;
end;
$$;
reset role;
select set_config('request.jwt.claim.sub', '', true);

-- ---------------------------------------------------------------------------
-- 12. The feed does not fan out per devotee. Measured.
--
--     track_functions was turned on at the top of this file, so
--     pg_stat_get_xact_function_calls counts what the feed actually did.
--     One call to the feed is one pass over the roster and one question per
--     DISTINCT TEMPLATE, whatever the size of the congregation — and the crowd
--     seva, with twenty-four devotees on it, comes back as ONE block.
-- ---------------------------------------------------------------------------

do $$
declare
  v_mon date := public.seva_mala_week_start(public.seva_mala_today());
  v_servers_before bigint;
  v_servers_after bigint;
  v_templates_before bigint;
  v_templates_after bigint;
  v_rows integer;
  v_crowd jsonb;
begin
  perform set_config('request.jwt.claim.sub',
    (select ids.id::text from public.sc_ids ids where ids.key = 'head'), true);

  -- The counter has to be working, or nothing below means anything.
  v_servers_before := pg_stat_get_xact_function_calls(
    'public.seva_schedule_servers(date, date)'::regprocedure);
  perform count(*) from public.seva_schedule_servers(v_mon, v_mon);
  if pg_stat_get_xact_function_calls(
       'public.seva_schedule_servers(date, date)'::regprocedure) <> v_servers_before + 1 then
    raise exception
      'Function call statistics are not being recorded, so the fan-out measurement below would prove nothing.';
  end if;

  v_servers_before := pg_stat_get_xact_function_calls(
    'public.seva_schedule_servers(date, date)'::regprocedure);
  v_templates_before := pg_stat_get_xact_function_calls(
    'public.can_view_service_template(uuid)'::regprocedure);

  select count(*) into v_rows from public.list_seva_schedule(v_mon - 10, v_mon + 20);

  v_servers_after := pg_stat_get_xact_function_calls(
    'public.seva_schedule_servers(date, date)'::regprocedure);
  v_templates_after := pg_stat_get_xact_function_calls(
    'public.can_view_service_template(uuid)'::regprocedure);

  -- ONE pass over the roster for the whole window, not one per devotee. There
  -- are thirty-four devotees in this fixture.
  if v_servers_after - v_servers_before <> 1 then
    raise exception
      'One call to the timetable made % passes over the roster.', v_servers_after - v_servers_before;
  end if;
  -- And one visibility question per distinct template — five — not one per
  -- occurrence and certainly not one per devotee.
  if v_templates_after - v_templates_before > (select count(*) from public.sc_tpl) then
    raise exception
      'One call to the timetable asked % template questions for % templates.',
      v_templates_after - v_templates_before, (select count(*) from public.sc_tpl);
  end if;

  -- The crowd seva is ONE block with twenty-four names on it.
  select feed.servers into v_crowd
  from public.list_seva_schedule(v_mon - 10, v_mon + 20) feed
  where feed.service_instance_id = (select instance_id from public.sc_rows where key = 'crowd');
  if jsonb_array_length(v_crowd) <> 24 then
    raise exception 'The crowd seva carries % names.', jsonb_array_length(v_crowd);
  end if;
  if (select count(*) from public.list_seva_schedule(v_mon - 10, v_mon + 20) feed
      where feed.service_instance_id = (select instance_id from public.sc_rows where key = 'crowd')) <> 1
  then
    raise exception 'The crowd seva came back as more than one block.';
  end if;
  if v_rows <> (select count(*) from public.sc_rows) then
    raise exception 'The feed returned % rows for % occurrences.', v_rows, (select count(*) from public.sc_rows);
  end if;

  perform set_config('request.jwt.claim.sub', '', true);
end;
$$;

-- The window is bounded, so a grid cannot ask for a year in one call.
do $$
declare
  v_mon date := public.seva_mala_week_start(public.seva_mala_today());
begin
  perform set_config('request.jwt.claim.sub',
    (select ids.id::text from public.sc_ids ids where ids.key = 'head'), true);
  if public.sc_try(format(
       'select count(*)::text from public.list_seva_schedule(%L::date, %L::date)',
       v_mon, v_mon + 400)) not like 'REFUSED:%'
  then
    raise exception 'A four-hundred-day timetable window was allowed.';
  end if;
  if public.sc_try(format(
       'select count(*)::text from public.list_seva_schedule(%L::date, %L::date)',
       v_mon, v_mon - 1)) not like 'REFUSED:%'
  then
    raise exception 'A backwards window was allowed.';
  end if;
  if public.sc_try(format(
       'select count(*)::text from public.list_seva_clashes(%L::uuid, %L::date, ''10:00''::time, 0)',
       (select id from public.sc_ids where key = 'head'), v_mon)) not like 'REFUSED:%'
  then
    raise exception 'A zero-minute seva was accepted as a window to check.';
  end if;
  perform set_config('request.jwt.claim.sub', '', true);
end;
$$;

-- ---------------------------------------------------------------------------
-- 13. Every guard, mutated.
--
--     Each row below breaks exactly one thing this feature relies on and
--     re-reads one number through the real function. A guard whose mutation
--     changes nothing is a guard that was not doing anything, and the table
--     says so out loud.
--
--     The mutation is undone by raising inside a plpgsql block, which is a
--     subtransaction; the probe is read a third time afterwards and must match
--     the first, or the harness itself is lying.
-- ---------------------------------------------------------------------------

create table public.sc_mutations (
  n integer primary key,
  guard text not null,
  mutation text not null,
  probe text not null,
  intact text not null,
  mutated text not null,
  killed boolean not null
);

create function public.sc_mutate(
  p_n integer, p_as text, p_guard text, p_mutation text, p_probe text,
  p_apply text, p_query text
)
returns void
language plpgsql
as $$
declare
  v_intact text;
  v_mutated text;
  v_restored text;
begin
  perform set_config('request.jwt.claim.sub',
    (select ids.id::text from public.sc_ids ids where ids.key = p_as), true);

  execute p_query into v_intact;

  begin
    execute p_apply;
    execute p_query into v_mutated;
    raise exception using errcode = 'PT669', message = coalesce(v_mutated, '(null)');
  exception when sqlstate 'PT669' then
    v_mutated := sqlerrm;
  end;

  execute p_query into v_restored;
  if v_restored is distinct from v_intact then
    raise exception
      'Mutation % did not roll back: the probe read % before and % after.',
      p_n, coalesce(v_intact, '(null)'), coalesce(v_restored, '(null)');
  end if;

  insert into public.sc_mutations (n, guard, mutation, probe, intact, mutated, killed)
  values (p_n, p_guard, p_mutation, p_probe,
          coalesce(v_intact, '(null)'), v_mutated,
          v_mutated is distinct from coalesce(v_intact, '(null)'));
end;
$$;

do $$
declare
  v_mon date := public.seva_mala_week_start(public.seva_mala_today());
  v_arpita uuid := (select id from public.sc_ids where key = 'arpita');
  v_bhakta uuid := (select id from public.sc_ids where key = 'bhakta');
  v_devotee_role uuid := (select id from public.roles where name = 'devotee');
  v_vol_role uuid := (select id from public.roles where name = 'volunteer');
  -- Probes, written once and reused.
  v_who_swap_occ text := format(
    $q$select coalesce(string_agg(users.name, ', ' order by users.name), '(nobody)')
       from public.seva_schedule_servers(%L::date, %L::date) servers
       join public.users on users.id = servers.devotee_id
       where servers.service_instance_id =
         (select instance_id from public.sc_rows where key = 'swap_occ')$q$,
    v_mon - 10, v_mon + 20);
  v_who_range_in text := format(
    $q$select coalesce(string_agg(users.name, ', ' order by users.name), '(nobody)')
       from public.seva_schedule_servers(%L::date, %L::date) servers
       join public.users on users.id = servers.devotee_id
       where servers.service_instance_id =
         (select instance_id from public.sc_rows where key = 'swap_range_in')$q$,
    v_mon - 10, v_mon + 20);
  v_who_evidence text := format(
    $q$select coalesce(string_agg(users.name, ', ' order by users.name), '(nobody)')
       from public.seva_schedule_servers(%L::date, %L::date) servers
       join public.users on users.id = servers.devotee_id
       where servers.service_instance_id =
         (select instance_id from public.sc_rows where key = 'evidence')$q$,
    v_mon - 10, v_mon + 20);
  v_who_stepped text := format(
    $q$select coalesce(string_agg(users.name, ', ' order by users.name), '(nobody)')
       from public.seva_schedule_servers(%L::date, %L::date) servers
       join public.users on users.id = servers.devotee_id
       where servers.service_instance_id =
         (select instance_id from public.sc_rows where key = 'stepped')$q$,
    v_mon - 10, v_mon + 20);
  v_whole_board text := format(
    'select public.sc_try(%L)',
    format('select count(*)::text from public.list_seva_schedule(%L::date, %L::date)',
           v_mon - 10, v_mon + 20));
  v_someone_else text := format(
    'select public.sc_try(%L)',
    format('select count(*)::text from public.list_seva_schedule(null, null, %L::uuid)', v_bhakta));
  v_bhakta_template text := format(
    $q$select coalesce(feed.template_id::text, '(null)')
       from public.list_seva_schedule(%L::date, %L::date, %L::uuid) feed
       where feed.service_instance_id =
         (select instance_id from public.sc_rows where key = 'swap_occ')$q$,
    v_mon - 10, v_mon + 20, v_bhakta);
  v_bhakta_roster text := format(
    $q$select jsonb_array_length(feed.servers)::text
       from public.list_seva_schedule(%L::date, %L::date, %L::uuid) feed
       where feed.service_instance_id =
         (select instance_id from public.sc_rows where key = 'swap_occ')$q$,
    v_mon - 10, v_mon + 20, v_bhakta);
  v_clash_other text := format(
    'select public.sc_try(%L)',
    format('select count(*)::text from public.list_seva_clashes(%L::uuid, %L::date, ''11:15''::time, 60)',
           v_bhakta, v_mon + 3));
  v_vol_sees_name text := format(
    $q$select coalesce(clashes.seva_name, '(withheld)')
       from public.list_seva_clashes(%L::uuid, %L::date, '11:15'::time, 60) clashes$q$,
    v_bhakta, v_mon + 3);
  v_arpita_cancelled text := format(
    $q$select count(*)::text
       from public.list_seva_clashes(%L::uuid, %L::date, '09:15'::time, 30)$q$,
    v_arpita, v_mon - 6);
  v_backtoback text := format(
    $q$select count(*)::text
       from public.list_seva_clashes(%L::uuid, %L::date, '11:30'::time, 60)$q$,
    v_bhakta, v_mon + 3);
  v_midnight text := format(
    $q$select count(*)::text
       from public.list_seva_clashes(%L::uuid, %L::date, '00:30'::time, 60)$q$,
    v_bhakta, v_mon + 3);
  v_unserved_flag text := format(
    $q$select feed.nobody_served::text
       from public.list_seva_schedule(%L::date, %L::date) feed
       where feed.service_instance_id =
         (select instance_id from public.sc_rows where key = 'unserved')$q$,
    v_mon - 10, v_mon + 20);
  v_default_window text :=
    'select count(*)::text from public.list_seva_schedule()';
  v_mangala text :=
    $q$select (select starts_at_local::text from public.list_temple_programme()
               where name = 'Mangala Arati' limit 1)$q$;
  v_hours text :=
    'select (select day_starts_at::text from public.temple_timetable_hours())';
begin
  -- ---- The three gates on the feed. -------------------------------------
  perform public.sc_mutate(
    1, 'arpita', 'list_seva_schedule: may_view_whole_seva_board on the null case',
    'the devotee role granted services.manage_recurring',
    'what an ordinary devotee gets when she asks for the whole temple',
    format($m$insert into public.role_permissions (role_id, permission_key)
              values (%L::uuid, 'services.manage_recurring')$m$, v_devotee_role),
    v_whole_board);

  perform public.sc_mutate(
    2, 'arpita', 'list_seva_schedule: may_view_whole_seva_board on a named devotee',
    'the predicate forced to true',
    'what an ordinary devotee gets when she asks for somebody else''s week',
    $m$create or replace function public.may_view_whole_seva_board()
       returns boolean language sql stable set search_path = '' as $f$ select true $f$ $m$,
    v_someone_else);

  perform public.sc_mutate(
    3, 'head', 'list_seva_schedule: seva_schedule.max_window_days',
    'the cap dropped to three days',
    'a thirty-one-day window',
    $m$update public.app_settings set value = '3'
       where key = 'seva_schedule.max_window_days'$m$,
    v_whole_board);

  perform public.sc_mutate(
    4, 'head', 'list_seva_schedule: seva_schedule.default_window_days',
    'the default window dropped to one day',
    'how many blocks come back when nobody names a window',
    $m$update public.app_settings set value = '1'
       where key = 'seva_schedule.default_window_days'$m$,
    v_default_window);

  -- ---- The coverage resolution, rule by rule. ---------------------------
  perform public.sc_mutate(
    5, 'head', 'seva_schedule_servers: the plan must be accepted',
    'the occurrence plan put back to pending',
    'who is serving the handed-over Thursday',
    $m$update public.service_coverage_plans set status = 'pending'
       where scope = 'occurrence' and substitute_devotee_id =
         (select id from public.sc_ids where key = 'bhakta')
         and date_from = public.seva_mala_week_start(public.seva_mala_today()) + 3$m$,
    v_who_swap_occ);

  perform public.sc_mutate(
    6, 'head', 'seva_schedule_servers: the plan''s weekday must match',
    'the occurrence plan moved to a Monday',
    'who is serving the handed-over Thursday',
    $m$update public.service_coverage_plans set days_of_week = array[1]
       where scope = 'occurrence' and substitute_devotee_id =
         (select id from public.sc_ids where key = 'bhakta')
         and date_from = public.seva_mala_week_start(public.seva_mala_today()) + 3$m$,
    v_who_swap_occ);

  perform public.sc_mutate(
    7, 'head', 'seva_schedule_servers: the plan''s date window must contain the day',
    'the date_range swap ended before the occurrence it covers',
    'who is serving the Tuesday inside the range',
    format($m$update public.service_coverage_plans set date_to = %L::date
              where scope = 'date_range'$m$, v_mon),
    v_who_range_in);

  perform public.sc_mutate(
    8, 'head', 'seva_schedule_servers: evidence outranks the plan (the original)',
    'the devotee who served it anyway put back to merely confirmed',
    'who is on the Wednesday the original served despite the swap',
    format($m$update public.service_assignments
              set status = 'confirmed', attendance = null, completed_at = null
              where devotee_id = %L::uuid and service_instance_id =
                (select instance_id from public.sc_rows where key = 'evidence')$m$, v_arpita),
    v_who_evidence);

  perform public.sc_mutate(
    9, 'head', 'seva_schedule_servers: an explicit withdrawal outranks the plan',
    'the substitute''s withdrawal from that one Saturday erased',
    'who is on the Saturday the substitute pulled out of',
    format($m$update public.service_assignments set status = 'confirmed'
              where devotee_id = %L::uuid and service_instance_id =
                (select instance_id from public.sc_rows where key = 'stepped')$m$, v_bhakta),
    v_who_stepped);

  -- ---- The two leaks. ---------------------------------------------------
  perform public.sc_mutate(
    10, 'bhakta', 'list_seva_schedule: can_view_service_template on the block',
    'the template visibility check forced to true',
    'whether a substitute is handed the weekly template id',
    $m$create or replace function public.can_view_service_template(p_template_id uuid)
       returns boolean language sql stable security definer set search_path = ''
       as $f$ select true $f$ $m$,
    v_bhakta_template);

  perform public.sc_mutate(
    11, 'bhakta', 'list_seva_schedule: can_view_service_instance on the roster',
    'the instance visibility check forced to true',
    'how many names a substitute is shown on a seva RLS refuses him',
    $m$create or replace function public.can_view_service_instance(p_instance_id uuid)
       returns boolean language sql stable security definer set search_path = ''
       as $f$ select true $f$ $m$,
    v_bhakta_roster);

  -- ---- The clash check. -------------------------------------------------
  perform public.sc_mutate(
    12, 'chandra', 'list_seva_clashes: services.offer_assignment',
    'the devotee role granted the permission that invites people',
    'what an ordinary devotee gets when she checks somebody else''s diary',
    format($m$insert into public.role_permissions (role_id, permission_key)
              values (%L::uuid, 'services.offer_assignment')$m$, v_devotee_role),
    v_clash_other);

  perform public.sc_mutate(
    13, 'vol', 'list_seva_clashes: the seva name is withheld',
    'the Volunteer role granted services.view_all',
    'the name a Volunteer is told for an invite-only seva',
    format($m$insert into public.role_permissions (role_id, permission_key)
              values (%L::uuid, 'services.view_all')$m$, v_vol_role),
    v_vol_sees_name);

  perform public.sc_mutate(
    14, 'arpita', 'list_seva_clashes: a cancelled seva is not a clash',
    'the seva 202608040068 closed put back to completed',
    'how many clashes a devotee has during a seva nobody served',
    $m$update public.service_instances set status = 'completed'
       where id = (select instance_id from public.sc_rows where key = 'unserved')$m$,
    v_arpita_cancelled);

  perform public.sc_mutate(
    15, 'bhakta', 'list_seva_clashes: half-open ranges, so back-to-back is free',
    'the Thursday seva stretched fifteen minutes past its end',
    'how many clashes there are for a seva starting the minute the last one ends',
    $m$update public.service_instances set duration_minutes = 105
       where id = (select instance_id from public.sc_rows where key = 'swap_occ')$m$,
    v_backtoback);

  perform public.sc_mutate(
    16, 'bhakta', 'list_seva_clashes: the day before is scanned too',
    'the midnight seva moved back to the evening, so it no longer crosses',
    'how many clashes there are at half past midnight',
    $m$update public.service_instances set start_time = '19:00'
       where id = (select instance_id from public.sc_rows where key = 'midnight')$m$,
    v_midnight);

  -- ---- The facts the feed reports rather than derives. ------------------
  perform public.sc_mutate(
    17, 'head', 'list_seva_schedule: nobody_served is 202608040068''s own row',
    'the row that records why the seva was closed deleted',
    'whether the seva nobody served says so',
    $m$delete from public.service_instances_unserved
       where service_instance_id =
         (select instance_id from public.sc_rows where key = 'unserved')$m$,
    v_unserved_flag);

  -- ---- The temple programme, and the promise that made it a table. ------
  perform public.sc_mutate(
    18, 'arpita', 'temple_programme: the time can be changed without a release',
    'Mangala Arati moved to four in the morning by one UPDATE',
    'when the app is told Mangala Arati starts',
    $m$update public.temple_programme set starts_at_local = '04:00'
       where name = 'Mangala Arati'$m$,
    v_mangala);

  perform public.sc_mutate(
    19, 'arpita', 'temple_programme.day_starts_at',
    'the first hour of the grid moved to five in the morning',
    'the hour the grid is told to start drawing',
    $m$update public.app_settings set value = '05:00'
       where key = 'temple_programme.day_starts_at'$m$,
    v_hours);
end;
$$;

select set_config('request.jwt.claim.sub', '', true);

do $$
declare
  v_survivors text;
begin
  select string_agg(sc_mutations.n || ': ' || sc_mutations.guard, E'\n  ')
  into v_survivors
  from public.sc_mutations where not sc_mutations.killed;
  if v_survivors is not null then
    raise exception
      'These guards survived being broken, so nothing is holding them up:%s%',
      E'\n  ', v_survivors;
  end if;
  if (select count(*) from public.sc_mutations) <> 19 then
    raise exception 'Only % mutations ran.', (select count(*) from public.sc_mutations);
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 14. The tables a reader wants.
-- ---------------------------------------------------------------------------

select
  sc_mutations.n,
  sc_mutations.guard,
  sc_mutations.mutation,
  sc_mutations.probe,
  sc_mutations.intact,
  sc_mutations.mutated,
  case when sc_mutations.killed then 'killed' else 'SURVIVED' end as verdict
from public.sc_mutations
order by sc_mutations.n;

select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.sc_ids ids where ids.key = 'head'), true);

select
  rows.key,
  feed.seva_name,
  feed.occurs_on,
  feed.starts_at_local,
  feed.ends_at_local,
  feed.ends_next_day,
  feed.status,
  feed.nobody_served,
  feed.filled_slots || '/' || feed.slots_needed as places,
  coalesce((
    select string_agg(person ->> 'name' ||
      case when (person ->> 'isSubstitute')::boolean
           then ' (for ' || coalesce(person ->> 'coveringForName', '?') || ')'
           else '' end, ', ')
    from jsonb_array_elements(feed.servers) person), '—') as serving
from public.list_seva_schedule(
  public.seva_mala_week_start(public.seva_mala_today()) - 10,
  public.seva_mala_week_start(public.seva_mala_today()) + 20) feed
join public.sc_rows rows on rows.instance_id = feed.service_instance_id
order by feed.occurs_on, feed.starts_at_local;

select
  programme.name,
  programme.occurs_on,
  programme.starts_at_local,
  coalesce(programme.ends_at_local::text, '(no end given)') as ends,
  programme.kind
from public.list_temple_programme(
  public.seva_mala_week_start(public.seva_mala_today()) + 6,
  public.seva_mala_week_start(public.seva_mala_today()) + 6) programme
order by programme.starts_at_local;

select set_config('request.jwt.claim.sub', '', true);

do $$
begin
  raise notice 'all schedule and clash checks passed';
end;
$$;

select 'schedule and clashes verification passed' as result;

rollback;
