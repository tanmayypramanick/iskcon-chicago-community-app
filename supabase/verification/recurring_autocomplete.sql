-- Functional verification for 202608040065_recurring_autocomplete.sql.
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
-- The temple's sentence — "weekly seva which is done, by the time zone it will
-- already be completed, so it will be completed automatically" — is a
-- conjunction of a positive and four refusals, and every one of them is a
-- separate way to get this wrong:
--
--   1. A recurring slot whose Chicago hour has gone by is closed by the sweep,
--      its silent assignments go to 'completed', and 202608040059's rule then
--      reads the act as 'counted'. Nobody pressed anything.
--   2. A recurring slot whose hour has NOT gone by is untouched — including one
--      that is inside the grace, and including one that only LOOKS past from a
--      session in Asia.
--   3. A one-off slot is never auto-completed, whatever its hour. It has a
--      poster, and 202608040057's stricter rule still governs it.
--   4. A cancelled slot stays cancelled.
--   5. A decision already made is left exactly as it stands: no_show,
--      withdrawn, and any attendance mark at all — absent, excused OR served.
--      None of those rows moves a column, and none of them earns.
--
--   and then, over the top of all five: running the sweep twice changes nothing
--   the second time, and the queue the temple is complaining about shrinks to
--   exactly the rows that genuinely still need a human.
--
-- ---------------------------------------------------------------------------
-- The Chicago boundary, and why it is checked four times.
--
-- due_at is (date + start_time) at time zone 'America/Chicago', plus the slot's
-- own duration, plus the grace. Two of the fixture's slots END IN THE FUTURE in
-- Chicago:
--
--   soon     ends ninety minutes from now, Chicago
--   eleven   ends at eleven o'clock at night, Chicago
--
-- and section 10 asks for the due set from four session timezones —
-- America/Chicago, UTC, Asia/Kolkata and Pacific/Auckland — and requires the
-- same answer every time, with neither of those two in it. Asia/Kolkata is the
-- one that bites: it runs ten and a half to eleven and a half hours ahead of
-- Chicago, so a `date + start_time` read in the SESSION's timezone rather than
-- the temple's would place `soon` about eleven hours in the PAST and complete a
-- devotee's seva before they had done it. `soon` is constructed relative to now
-- so that this holds at any hour the suite happens to run.
--
-- ---------------------------------------------------------------------------
-- The fixture. One service type, four templates (so that no two instances
-- collide on the unique (template_id, date) index), and sixteen devotees, each
-- of whom exists to be exactly one row of the table below.
--
--   key          when                     the assignment                 expected
--   ---------------------------------------------------------------------------
--   past         today-7,  08:00 +120     d1  confirmed                  COMPLETED
--   assigned     today-12, 08:00 +120     d9  assigned                   COMPLETED
--   graceout     ended 90 minutes ago     d12 confirmed                  COMPLETED
--   decided      today-9,  08:00 +120     d7  confirmed                  COMPLETED
--                                         d4  confirmed + absent         UNTOUCHED
--                                         d5  no_show                    UNTOUCHED
--                                         d6  withdrawn                  UNTOUCHED
--                                         d8  confirmed + served         UNTOUCHED
--   gracein      ended 30 minutes ago     d11 confirmed                  waits (grace)
--   future       today+3,  08:00 +120     d16 confirmed                  waits
--   soon         ends now+90m             d14 confirmed                  waits
--   eleven       tomorrow, 21:00 +120     d15 confirmed                  waits
--   oneoff       today-7,  08:00 +120     d2  confirmed  (no template)   waits
--   cancelled    today-8,  cancelled      d3  confirmed                  cancelled
--   nobody       today-10, 08:00 +120     no assignments at all          untouched
--   alldecided   today-11, 08:00 +120     d5  no_show only               untouched
--   ancient      today-200,08:00 +120     d13 confirmed                  waits (lookback)
--   switched     today-13, 08:00 +120     d10 confirmed                  section 8
--   humanclose   started 3 hours ago      d16 confirmed                  section 13
--
-- 'humanclose' is the only row not built in section 2. It is recurring, past
-- and silent — the exact shape the sweep claims — so it is created after every
-- assertion about the sweep has been made, purely for the President to close by
-- hand under 202608040068's clock.
--
-- 'nobody' and 'alldecided' are the two that pin the sweep's selection to "at
-- least one row it would actually change". A past roster slot nobody stood in
-- must not be stamped 'completed', because that would be a claim that it
-- happened.
--
-- The final row must read: recurring autocomplete verification passed

begin;

-- ---------------------------------------------------------------------------
-- 0. The ground.
--
--    The dials the whole file is calibrated against, the shape of what was
--    created, and — before a single fixture row exists — who may reach it.
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
      ('seva.auto_complete_recurring', 'true'),
      ('seva.auto_complete_grace_minutes', '60'),
      ('seva.auto_complete_lookback_days', '90')
    ) as expected(key, value)
    left join public.app_settings settings on settings.key = expected.key
    where settings.value is distinct from expected.value
  loop
    raise exception 'A dial this file depends on reads % rather than %.', v_actual, v_expected;
  end loop;

  -- A leftover overload has broken this repository before, and an overload of
  -- the internal with a default for p_auto would make "auto" the silent
  -- default of the human path.
  for v_name in
    select proc.proname
    from pg_proc proc
    join pg_namespace spaces on spaces.oid = proc.pronamespace
    where spaces.nspname = 'public'
      and proc.proname in (
        'complete_due_recurring_service_instances',
        'complete_service_instance_internal',
        'complete_service_instance')
    group by proc.proname
    having count(*) <> 1
  loop
    raise exception 'There is more than one public.%.', v_name;
  end loop;

  for v_name, v_shape in
    select expected.name, coalesce(
      (select pg_get_function_identity_arguments(proc.oid)
       from pg_proc proc
       join pg_namespace spaces on spaces.oid = proc.pronamespace
       where spaces.nspname = 'public' and proc.proname = expected.name), '(missing)')
    from (values
      ('complete_due_recurring_service_instances', ''),
      ('complete_service_instance_internal', 'p_instance_id uuid, p_actor_id uuid, p_auto boolean'),
      ('complete_service_instance', 'p_instance_id uuid')
    ) as expected(name, args)
    where expected.args is distinct from coalesce(
      (select pg_get_function_identity_arguments(proc.oid)
       from pg_proc proc
       join pg_namespace spaces on spaces.oid = proc.pronamespace
       where spaces.nspname = 'public' and proc.proname = expected.name), '(missing)')
  loop
    raise exception 'public.% takes (%).', v_name, v_shape;
  end loop;

  if to_regclass('public.due_recurring_service_instances') is null then
    raise exception 'The due view does not exist.';
  end if;

  -- THE SWEEP IS THE CLOCK'S, NOT A DEVOTEE'S. No client role may run it, and
  -- no client role may run the write underneath it.
  if has_function_privilege('authenticated', 'public.complete_due_recurring_service_instances()', 'execute')
    or has_function_privilege('anon', 'public.complete_due_recurring_service_instances()', 'execute')
  then
    raise exception 'A client role can run the auto-completion sweep on demand.';
  end if;
  if not has_function_privilege('service_role', 'public.complete_due_recurring_service_instances()', 'execute') then
    raise exception 'The temple''s own schedule cannot run the sweep.';
  end if;
  if has_function_privilege('authenticated',
       'public.complete_service_instance_internal(uuid, uuid, boolean)', 'execute')
    or has_function_privilege('anon',
       'public.complete_service_instance_internal(uuid, uuid, boolean)', 'execute')
  then
    raise exception
      'A client role can call the completion write directly, which is 202608040023''s authority bypassed.';
  end if;
  if has_table_privilege('authenticated', 'public.due_recurring_service_instances', 'select')
    or has_table_privilege('anon', 'public.due_recurring_service_instances', 'select')
  then
    raise exception 'A client role can read the due view.';
  end if;

  -- And 202608040023's door is exactly as wide as it was.
  if not has_function_privilege('authenticated', 'public.complete_service_instance(uuid)', 'execute') then
    raise exception 'The poster can no longer close their own seva.';
  end if;
  if has_function_privilege('anon', 'public.complete_service_instance(uuid)', 'execute') then
    raise exception 'A signed-out visitor can close a seva.';
  end if;

  -- No migration seeds a service_instance, so the due set is empty before this
  -- file builds one. Every count below is therefore this file's own.
  if (select count(*) from public.due_recurring_service_instances) <> 0 then
    raise exception
      'Something is already due before any fixture exists; every count in this file is measuring somebody else''s rows.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 1. The congregation.
-- ---------------------------------------------------------------------------

create table public.ac_ids (key text primary key, id uuid not null);
grant select on public.ac_ids to authenticated;

create table public.ac_rows (
  key text primary key,
  instance_id uuid not null,
  assignment_id uuid
);
grant select on public.ac_rows to authenticated;

do $$
declare
  v_who record;
  v_i integer := 0;
begin
  for v_who in
    select * from (values
      ('pres', 'Autocomplete President'),
      ('head', 'Autocomplete Community Head'),
      ('d1',  'D1 Das'),  ('d2',  'D2 Das'),  ('d3',  'D3 Das'),  ('d4',  'D4 Das'),
      ('d5',  'D5 Das'),  ('d6',  'D6 Das'),  ('d7',  'D7 Das'),  ('d8',  'D8 Das'),
      ('d9',  'D9 Das'),  ('d10', 'D10 Das'), ('d11', 'D11 Das'), ('d12', 'D12 Das'),
      ('d13', 'D13 Das'), ('d14', 'D14 Das'), ('d15', 'D15 Das'), ('d16', 'D16 Das')
    ) as cast_member(key, name)
  loop
    v_i := v_i + 1;
    insert into auth.users (id, email, raw_user_meta_data)
    values (
      ('ac000000-0000-0000-0000-0000000000' || lpad(v_i::text, 2, '0'))::uuid,
      'ac-' || v_who.key || '@example.test',
      jsonb_build_object('name', v_who.name)
    );
    update public.users set name = v_who.name
    where users.email = 'ac-' || v_who.key || '@example.test';
    insert into public.ac_ids (key, id)
    select v_who.key, users.id from public.users
    where users.email = 'ac-' || v_who.key || '@example.test';
  end loop;
end;
$$;

update public.users users
set role_id = roles.id
from public.roles roles
where (users.email, roles.name) in (
  ('ac-pres@example.test', 'president'),
  ('ac-head@example.test', 'core')
);

-- ---------------------------------------------------------------------------
-- 2. The roster.
--
--    Four templates so no two instances collide on the unique
--    (template_id, date) index, and every instance carries the template's own
--    duration, which is what makes an auto-completed act arithmetically
--    incapable of claiming a minute the temple did not offer.
-- ---------------------------------------------------------------------------

do $$
declare
  v_type uuid;
  v_pres uuid := (select ids.id from public.ac_ids ids where ids.key = 'pres');
  v_now_chi timestamp := (now() at time zone 'America/Chicago');
  v_today date := v_now_chi::date;
  v_tpl_a uuid;
  v_tpl_b uuid;
  v_tpl_c uuid;
  v_tpl_d uuid;
  v_tpl_e uuid;
  v_gin timestamp;
  v_gout timestamp;
  v_soon timestamp;
  v_inst uuid;
  v_plan record;
begin
  select service_types.id into v_type
  from public.service_types where service_types.name = 'Pot Washing';
  if v_type is null then
    raise exception 'The Pot Washing service type is missing from the seed.';
  end if;

  insert into public.service_templates (
    service_type_id, day_of_week, days_of_week, start_time, duration_minutes,
    slots_needed, participation_mode, start_date, created_by, active
  )
  select v_type, 0, array[0,1,2,3,4,5,6], time '08:00', 120, 8, 'open',
    v_today - 400, v_pres, true
  returning id into v_tpl_a;

  insert into public.service_templates (
    service_type_id, day_of_week, days_of_week, start_time, duration_minutes,
    slots_needed, participation_mode, start_date, created_by, active
  )
  select v_type, 0, array[0,1,2,3,4,5,6], time '08:00', 60, 8, 'open',
    v_today - 400, v_pres, true
  returning id into v_tpl_b;

  insert into public.service_templates (
    service_type_id, day_of_week, days_of_week, start_time, duration_minutes,
    slots_needed, participation_mode, start_date, created_by, active
  )
  select v_type, 0, array[0,1,2,3,4,5,6], time '08:00', 60, 8, 'open',
    v_today - 400, v_pres, true
  returning id into v_tpl_c;

  insert into public.service_templates (
    service_type_id, day_of_week, days_of_week, start_time, duration_minutes,
    slots_needed, participation_mode, start_date, created_by, active
  )
  select v_type, 0, array[0,1,2,3,4,5,6], time '21:00', 120, 8, 'open',
    v_today - 400, v_pres, true
  returning id into v_tpl_d;

  -- The three clock-relative slots. Each is written as a wall-clock date and
  -- time in Chicago, exactly as the generator writes them, so nothing about the
  -- fixture knows what timezone the session is in.
  --   gracein   ended thirty minutes ago  -> inside a sixty-minute grace
  --   graceout  ended ninety minutes ago  -> past it
  --   soon      ends ninety minutes hence -> not due under any reading
  v_gin  := v_now_chi - interval '30 minutes' - interval '60 minutes';
  v_gout := v_now_chi - interval '90 minutes' - interval '60 minutes';
  v_soon := v_now_chi + interval '90 minutes' - interval '60 minutes';

  -- The fixed-date recurring slots, all on template A, all on their own date.
  for v_plan in
    select * from (values
      ('past',       7),
      ('cancelled',  8),
      ('decided',    9),
      ('nobody',    10),
      ('alldecided',11),
      ('assigned',  12),
      ('ancient',  200)
    ) as plan(key, days_ago)
  loop
    insert into public.service_instances (
      template_id, service_type_id, date, start_time, duration_minutes,
      slots_needed, participation_mode, posted_by, status
    ) values (
      v_tpl_a, v_type, v_today - v_plan.days_ago, time '08:00', 120, 8, 'open',
      null, case when v_plan.key = 'cancelled' then 'cancelled' else 'open' end
    ) returning id into v_inst;
    insert into public.ac_rows (key, instance_id) values (v_plan.key, v_inst);
  end loop;

  -- Three days ahead: the plain "its time has not passed" case.
  insert into public.service_instances (
    template_id, service_type_id, date, start_time, duration_minutes,
    slots_needed, participation_mode, posted_by, status
  ) values (v_tpl_a, v_type, v_today + 3, time '08:00', 120, 8, 'open', null, 'open')
  returning id into v_inst;
  insert into public.ac_rows (key, instance_id) values ('future', v_inst);

  insert into public.service_instances (
    template_id, service_type_id, date, start_time, duration_minutes,
    slots_needed, participation_mode, posted_by, status
  ) values (v_tpl_b, v_type, v_gin::date, v_gin::time, 60, 8, 'open', null, 'open')
  returning id into v_inst;
  insert into public.ac_rows (key, instance_id) values ('gracein', v_inst);

  insert into public.service_instances (
    template_id, service_type_id, date, start_time, duration_minutes,
    slots_needed, participation_mode, posted_by, status
  ) values (v_tpl_c, v_type, v_gout::date, v_gout::time, 60, 8, 'open', null, 'open')
  returning id into v_inst;
  insert into public.ac_rows (key, instance_id) values ('graceout', v_inst);

  -- 'soon' lands on today or tomorrow depending on the hour, which could
  -- collide with gracein or graceout on the unique (template_id, date) index,
  -- so it gets a template of its own.
  insert into public.service_templates (
    service_type_id, day_of_week, days_of_week, start_time, duration_minutes,
    slots_needed, participation_mode, start_date, created_by, active
  )
  select v_type, 0, array[0,1,2,3,4,5,6], time '08:00', 60, 8, 'open',
    v_today - 400, v_pres, true
  returning id into v_tpl_e;

  insert into public.service_instances (
    template_id, service_type_id, date, start_time, duration_minutes,
    slots_needed, participation_mode, posted_by, status
  ) values (v_tpl_e, v_type, v_soon::date, v_soon::time, 60, 8, 'open', null, 'open')
  returning id into v_inst;
  insert into public.ac_rows (key, instance_id) values ('soon', v_inst);

  -- Eleven o'clock at night in Chicago, tomorrow, so it is always ahead of now.
  insert into public.service_instances (
    template_id, service_type_id, date, start_time, duration_minutes,
    slots_needed, participation_mode, posted_by, status
  ) values (v_tpl_d, v_type, v_today + 1, time '21:00', 120, 8, 'open', null, 'open')
  returning id into v_inst;
  insert into public.ac_rows (key, instance_id) values ('eleven', v_inst);

  -- The one-off. A poster, no template, and 202608040057's whole rule.
  insert into public.service_instances (
    service_type_id, date, start_time, duration_minutes,
    slots_needed, participation_mode, posted_by, status
  ) values (v_type, v_today - 7, time '08:00', 120, 4, 'open', v_pres, 'open')
  returning id into v_inst;
  insert into public.ac_rows (key, instance_id) values ('oneoff', v_inst);
end;
$$;

-- The assignments. Every row of the header's table, and nothing else.
do $$
declare
  v_plan record;
  v_assignment uuid;
begin
  for v_plan in
    select * from (values
      ('past',       'd1',  'confirmed', null),
      ('assigned',   'd9',  'assigned',  null),
      ('graceout',   'd12', 'confirmed', null),
      ('gracein',    'd11', 'confirmed', null),
      ('future',     'd16', 'confirmed', null),
      ('soon',       'd14', 'confirmed', null),
      ('eleven',     'd15', 'confirmed', null),
      ('oneoff',     'd2',  'confirmed', null),
      ('cancelled',  'd3',  'confirmed', null),
      ('ancient',    'd13', 'confirmed', null),
      ('alldecided', 'd5',  'no_show',   null),
      ('decided',    'd7',  'confirmed', null),
      ('decided',    'd4',  'confirmed', 'absent'),
      ('decided',    'd5',  'no_show',   null),
      ('decided',    'd6',  'withdrawn', null),
      ('decided',    'd8',  'confirmed', 'served')
    ) as plan(instance_key, who, status, attendance)
  loop
    insert into public.service_assignments (
      service_instance_id, devotee_id, assignment_method, assigned_by,
      status, verification, attendance
    )
    select rows.instance_id,
      (select ids.id from public.ac_ids ids where ids.key = v_plan.who),
      'recurring_assignment', null, v_plan.status, 'self_report', v_plan.attendance
    from public.ac_rows rows where rows.key = v_plan.instance_key
    returning id into v_assignment;

    -- Only the single-assignment instances get their assignment recorded
    -- against the key; 'decided' is addressed by devotee below.
    update public.ac_rows set assignment_id = v_assignment
    where key = v_plan.instance_key and assignment_id is null
      and v_plan.instance_key <> 'decided';
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Before the sweep: everything is waiting, and the temple's complaint is
--    reproduced rather than assumed.
-- ---------------------------------------------------------------------------

do $$
declare
  v_waiting integer;
  v_status text;
begin
  select count(*) into v_waiting
  from public.service_assignments assignments
  join public.service_instances instances on instances.id = assignments.service_instance_id
  join public.ac_rows rows on rows.instance_id = instances.id
  where rows.key in ('past', 'assigned', 'graceout', 'decided')
    and public.seva_points_status(
      assignments.status, assignments.attendance, assignments.verification,
      instances.template_id is not null) = 'awaiting_completion';
  if v_waiting <> 5 then
    raise exception
      'Before the sweep, % roster rows on slots whose Chicago hour has passed read awaiting_completion rather than 5. That count IS the temple''s complaint.',
      v_waiting;
  end if;

  -- The four that are due are visible as due, and only those four.
  if (select count(*) from public.due_recurring_service_instances) <> 4 then
    raise exception 'The due view holds % rows rather than the four that are due.',
      (select count(*) from public.due_recurring_service_instances);
  end if;
  for v_status in
    select rows.key
    from public.due_recurring_service_instances due
    join public.ac_rows rows on rows.instance_id = due.service_instance_id
    where rows.key not in ('past', 'assigned', 'graceout', 'decided')
  loop
    raise exception 'The due view holds "%", which is not due.', v_status;
  end loop;
  if (select count(*) from public.due_recurring_service_instances due
      join public.ac_rows rows on rows.instance_id = due.service_instance_id
      where rows.key = 'decided') <> 1 then
    raise exception 'The slot with one silent row among four decided ones is not due.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. The sweep, once.
-- ---------------------------------------------------------------------------

do $$
declare
  v_completed integer;
begin
  v_completed := public.complete_due_recurring_service_instances();
  if v_completed <> 4 then
    raise exception 'The sweep completed % instances rather than the four that were due.', v_completed;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. What moved, and what did not.
--
--    Instance status first, then every assignment column, then the points.
-- ---------------------------------------------------------------------------

do $$
declare
  v_case record;
  v_status text;
begin
  for v_case in
    select * from (values
      ('past',       'completed'),
      ('assigned',   'completed'),
      ('graceout',   'completed'),
      ('decided',    'completed'),
      -- Not due, for four different reasons, and each of them is a rule.
      ('gracein',    'open'),      -- inside the grace
      ('future',     'open'),      -- its hour has not come
      ('soon',       'open'),      -- ends ninety minutes from now
      ('eleven',     'open'),      -- eleven at night in Chicago, tomorrow
      ('ancient',    'open'),      -- beyond the lookback
      -- Refusals.
      ('oneoff',     'open'),      -- one-off seva is never auto-completed
      ('cancelled',  'cancelled'), -- a cancelled slot stays cancelled
      ('nobody',     'open'),      -- nobody stood in it, so it did not happen
      ('alldecided', 'open')       -- every row already decided; nothing to fill
    ) as expected(key, status)
  loop
    select instances.status into v_status
    from public.service_instances instances
    join public.ac_rows rows on rows.instance_id = instances.id
    where rows.key = v_case.key;
    if v_status is distinct from v_case.status then
      raise exception 'The "%" instance is % rather than %.', v_case.key, v_status, v_case.status;
    end if;
  end loop;
end;
$$;

-- Every assignment, by devotee, with the exact status / attendance /
-- completed_at it must now carry. A decision left "mostly" alone is a decision
-- overruled, so completed_at is asserted too.
do $$
declare
  v_case record;
  v_row record;
begin
  for v_case in
    select * from (values
      -- Auto-completed: status moved, attendance still nobody's word, and the
      -- act reads counted under 202608040059.
      ('d1',  'completed', null,     true,  'counted'),
      ('d9',  'completed', null,     true,  'counted'),
      ('d12', 'completed', null,     true,  'counted'),
      ('d7',  'completed', null,     true,  'counted'),
      -- Decisions, untouched, on an instance that DID complete around them.
      ('d4',  'confirmed', 'absent', false, 'not_served'),
      ('d6',  'withdrawn', null,     false, 'not_served'),
      ('d8',  'confirmed', 'served', false, 'awaiting_completion'),
      -- Never due.
      ('d11', 'confirmed', null,     false, 'awaiting_completion'),
      ('d16', 'confirmed', null,     false, 'awaiting_completion'),
      ('d14', 'confirmed', null,     false, 'awaiting_completion'),
      ('d15', 'confirmed', null,     false, 'awaiting_completion'),
      ('d13', 'confirmed', null,     false, 'awaiting_completion'),
      -- One-off, and cancelled.
      ('d2',  'confirmed', null,     false, 'awaiting_completion'),
      ('d3',  'confirmed', null,     false, 'awaiting_completion')
    ) as expected(who, status, attendance, closed, points_status)
  loop
    select assignments.status, assignments.attendance, assignments.completed_at is not null as closed,
      public.seva_points_status(
        assignments.status, assignments.attendance, assignments.verification,
        instances.template_id is not null) as points_status
    into v_row
    from public.service_assignments assignments
    join public.service_instances instances on instances.id = assignments.service_instance_id
    join public.ac_ids ids on ids.id = assignments.devotee_id
    where ids.key = v_case.who
      and instances.id <> (select rows.instance_id from public.ac_rows rows where rows.key = 'alldecided');

    if v_row.status is distinct from v_case.status
      or v_row.attendance is distinct from v_case.attendance
      or v_row.closed is distinct from v_case.closed
      or v_row.points_status is distinct from v_case.points_status
    then
      raise exception
        '% now reads status %, attendance %, closed %, points %; expected % / % / % / %.',
        v_case.who, v_row.status, coalesce(v_row.attendance, '(null)'), v_row.closed,
        v_row.points_status, v_case.status, coalesce(v_case.attendance, '(null)'),
        v_case.closed, v_case.points_status;
    end if;
  end loop;

  -- d5 carries two rows, both no_show, on two different instances, and neither
  -- moved: one on a slot that completed around it and one on a slot the sweep
  -- refused to touch at all.
  if exists (
    select 1 from public.service_assignments assignments
    join public.ac_ids ids on ids.id = assignments.devotee_id
    where ids.key = 'd5' and (assignments.status <> 'no_show' or assignments.completed_at is not null)
  ) then
    raise exception 'A no-show was closed out by the sweep.';
  end if;
  if (select count(*) from public.service_assignments assignments
      join public.ac_ids ids on ids.id = assignments.devotee_id
      where ids.key = 'd5') <> 2 then
    raise exception 'The no-show fixture is not the two rows this file thinks it is.';
  end if;
end;
$$;

-- The points actually land, read through the ledger rather than through the
-- rule this file already called. 202608040059's promise is that a completed
-- recurring act needs no verification and no attendance mark.
do $$
declare
  v_act record;
begin
  select acts.points_status, acts.is_recurring, acts.planned_minutes, acts.quality,
    acts.verification, acts.attendance
  into v_act
  from public.seva_mala_acts(
    (select ids.id from public.ac_ids ids where ids.key = 'd1')) acts;

  if v_act.points_status <> 'counted' then
    raise exception
      'The auto-completed weekly act reads % rather than counted; the sweep closed the slot and the points did not follow.',
      v_act.points_status;
  end if;
  if not v_act.is_recurring or v_act.verification <> 'self_report' or v_act.attendance is not null then
    raise exception
      'The counted act is not the unverified, unmarked recurring act 202608040059 is about.';
  end if;
  -- The hours are the temple's. No session and no verification means actual is
  -- null, so the credit is the template's own duration and not a minute more.
  if v_act.planned_minutes <> 120 or v_act.quality <> 1.0 then
    raise exception 'The auto-completed act claims % minutes at quality %.',
      v_act.planned_minutes, v_act.quality;
  end if;

  -- And the four whose decision was left standing earn nothing.
  for v_act in
    select ids.key, acts.points_status
    from public.ac_ids ids
    cross join lateral public.seva_mala_acts(ids.id) acts
    join public.service_instances instances on instances.id = acts.service_instance_id
    join public.ac_rows rows on rows.instance_id = instances.id
    where ids.key in ('d4', 'd5', 'd6') and rows.key = 'decided'
      and acts.points_status <> 'not_served'
  loop
    raise exception 'The decision on % survived the sweep but reads %.', v_act.key, v_act.points_status;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Twice changes nothing.
--
--    A snapshot of every column the sweep can write, over the whole fixture,
--    compared before and after a second run. Not a count: a hash of the rows,
--    so a column moving somewhere unexpected is caught too.
-- ---------------------------------------------------------------------------

do $$
declare
  v_before text;
  v_after text;
  v_completed integer;
begin
  select md5(string_agg(snapshot.line, '|' order by snapshot.line)) into v_before
  from (
    select instances.id::text || ':' || instances.status || ':' ||
      coalesce(assignments.id::text, '-') || ':' || coalesce(assignments.status, '-') || ':' ||
      coalesce(assignments.attendance, '-') || ':' || coalesce(assignments.completed_at::text, '-') as line
    from public.service_instances instances
    join public.ac_rows rows on rows.instance_id = instances.id
    left join public.service_assignments assignments on assignments.service_instance_id = instances.id
  ) snapshot;

  v_completed := public.complete_due_recurring_service_instances();
  if v_completed <> 0 then
    raise exception 'The second run completed % instances. The sweep is not idempotent.', v_completed;
  end if;

  select md5(string_agg(snapshot.line, '|' order by snapshot.line)) into v_after
  from (
    select instances.id::text || ':' || instances.status || ':' ||
      coalesce(assignments.id::text, '-') || ':' || coalesce(assignments.status, '-') || ':' ||
      coalesce(assignments.attendance, '-') || ':' || coalesce(assignments.completed_at::text, '-') as line
    from public.service_instances instances
    join public.ac_rows rows on rows.instance_id = instances.id
    left join public.service_assignments assignments on assignments.service_instance_id = instances.id
  ) snapshot;

  if v_before is distinct from v_after then
    raise exception 'A second run of the sweep moved a column.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. The grace is a dial, and the digest is once a Chicago day.
--
--    Dropping the grace to zero makes 'gracein' — which ended thirty minutes
--    ago — due, and nothing else. That proves the grace was what was holding
--    it, rather than some other accident of the fixture. And because something
--    was auto-completed earlier today, the second digest must not be sent.
-- ---------------------------------------------------------------------------

do $$
declare
  v_digests_before integer;
  v_digests_after integer;
  v_completed integer;
  v_status text;
begin
  select count(*) into v_digests_before
  from public.app_notifications
  where kind = 'service_completed'
    and coalesce((data ->> 'autoCompleted')::boolean, false);

  -- The first sweep said something, once, to the people who run rotas.
  if v_digests_before <> (
    select count(*) from public.users
    join public.role_permissions on role_permissions.role_id = users.role_id
     and role_permissions.permission_key = 'services.manage_recurring'
  ) or v_digests_before = 0 then
    raise exception
      'The auto-completion digest reached % people rather than everyone who runs a rota.',
      v_digests_before;
  end if;
  if not exists (
    select 1 from public.app_notifications
    join public.ac_ids ids on ids.id = app_notifications.user_id
    where ids.key = 'pres' and app_notifications.kind = 'service_completed'
      and (app_notifications.data ->> 'autoCompletedCount')::integer = 4
  ) then
    raise exception 'The President was not told how many slots closed themselves.';
  end if;
  -- And no devotee was told anything: a clock striking is not news.
  if exists (
    select 1 from public.app_notifications
    join public.ac_ids ids on ids.id = app_notifications.user_id
    where ids.key in ('d1', 'd7', 'd9', 'd12')
  ) then
    raise exception 'An auto-completion sent a devotee a notification saying somebody closed their seva.';
  end if;

  update public.app_settings set value = '0' where key = 'seva.auto_complete_grace_minutes';
  v_completed := public.complete_due_recurring_service_instances();
  if v_completed <> 1 then
    raise exception
      'With no grace, the sweep completed % rather than the one slot the grace was holding.', v_completed;
  end if;

  select instances.status into v_status
  from public.service_instances instances
  join public.ac_rows rows on rows.instance_id = instances.id
  where rows.key = 'gracein';
  if v_status <> 'completed' then
    raise exception 'The slot the grace was holding is % after the grace was removed.', v_status;
  end if;

  select count(*) into v_digests_after
  from public.app_notifications
  where kind = 'service_completed'
    and coalesce((data ->> 'autoCompleted')::boolean, false);
  if v_digests_after <> v_digests_before then
    raise exception 'A second digest was sent on the same Chicago day.';
  end if;

  update public.app_settings set value = '60' where key = 'seva.auto_complete_grace_minutes';
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. The temple can turn it off.
--
--    With the switch at false the sweep does nothing at all, and weekly seva
--    sits exactly where 202608040059 left it. Turning it back on picks up the
--    slot it declined.
-- ---------------------------------------------------------------------------

do $$
declare
  v_type uuid;
  v_pres uuid := (select ids.id from public.ac_ids ids where ids.key = 'pres');
  v_today date := (now() at time zone 'America/Chicago')::date;
  v_template uuid;
  v_instance uuid;
  v_completed integer;
  v_status text;
  v_assignment_status text;
begin
  update public.app_settings set value = 'false' where key = 'seva.auto_complete_recurring';

  -- A slot built while the switch is off, thirteen days in the past and
  -- unambiguously due on every reading of the clock.
  select service_types.id into v_type
  from public.service_types where service_types.name = 'Pot Washing';

  insert into public.service_templates (
    service_type_id, day_of_week, days_of_week, start_time, duration_minutes,
    slots_needed, participation_mode, start_date, created_by, active
  )
  select v_type, 0, array[0,1,2,3,4,5,6], time '08:00', 120, 4, 'open',
    v_today - 400, v_pres, true
  returning id into v_template;

  insert into public.service_instances (
    template_id, service_type_id, date, start_time, duration_minutes,
    slots_needed, participation_mode, posted_by, status
  ) values (v_template, v_type, v_today - 13, time '08:00', 120, 4, 'open', null, 'open')
  returning id into v_instance;
  insert into public.ac_rows (key, instance_id) values ('switched', v_instance);

  insert into public.service_assignments (
    service_instance_id, devotee_id, assignment_method, assigned_by,
    status, verification, attendance
  )
  select v_instance, ids.id, 'recurring_assignment', null, 'confirmed', 'self_report', null
  from public.ac_ids ids where ids.key = 'd10';

  -- It is due, and the switch is the only thing stopping it.
  if not exists (
    select 1 from public.due_recurring_service_instances due
    where due.service_instance_id = v_instance
  ) then
    raise exception 'The switch-off fixture is not due, so this section proves nothing.';
  end if;

  v_completed := public.complete_due_recurring_service_instances();
  if v_completed <> 0 then
    raise exception 'The sweep completed % instances while switched off.', v_completed;
  end if;

  select instances.status into v_status
  from public.service_instances instances where instances.id = v_instance;
  select assignments.status into v_assignment_status
  from public.service_assignments assignments
  where assignments.service_instance_id = v_instance;
  if v_status <> 'open' or v_assignment_status <> 'confirmed' then
    raise exception
      'With auto-completion off, a due slot reads % / %; weekly seva is not where 202608040059 left it.',
      v_status, v_assignment_status;
  end if;

  -- Turned back on, it picks up exactly the slot it declined.
  update public.app_settings set value = 'true' where key = 'seva.auto_complete_recurring';
  v_completed := public.complete_due_recurring_service_instances();
  if v_completed <> 1 then
    raise exception 'Switched back on, the sweep completed % rather than the one slot it had declined.',
      v_completed;
  end if;
  select instances.status into v_status
  from public.service_instances instances where instances.id = v_instance;
  if v_status <> 'completed' then
    raise exception 'The slot the switch was holding is % after the switch came back on.', v_status;
  end if;
end;
$$;

-- A malformed dial raises rather than quietly reverting to a default.
do $$
declare
  v_case record;
  v_allowed boolean;
begin
  for v_case in
    select * from (values
      ('seva.auto_complete_recurring',      'maybe'),
      ('seva.auto_complete_grace_minutes',  'sixty'),
      ('seva.auto_complete_grace_minutes',  '-1'),
      ('seva.auto_complete_grace_minutes',  '99999'),
      ('seva.auto_complete_lookback_days',  'ninety'),
      ('seva.auto_complete_lookback_days',  '0')
    ) as bad(key, value)
  loop
    update public.app_settings set value = v_case.value where key = v_case.key;
    v_allowed := false;
    begin
      perform public.complete_due_recurring_service_instances();
      v_allowed := true;
    exception when others then
      if sqlstate <> 'P0001' then raise; end if;
    end;
    if v_allowed then
      raise exception 'The sweep ran with % set to "%".', v_case.key, v_case.value;
    end if;
    update public.app_settings set value =
      case v_case.key
        when 'seva.auto_complete_recurring' then 'true'
        when 'seva.auto_complete_grace_minutes' then '60'
        else '90'
      end
    where key = v_case.key;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- 9. A brand new slot, closed by nothing but the clock.
--
--    Everything above ran the sweep by hand against a fixture. This runs it
--    against a slot built the way the roster really builds one — a template, a
--    standing assignee, and generate_service_instances — with the only
--    intervention being to move the generated instance's date into the past,
--    because the generator only ever writes forward.
-- ---------------------------------------------------------------------------

do $$
declare
  v_type uuid;
  v_pres uuid := (select ids.id from public.ac_ids ids where ids.key = 'pres');
  v_today date := (now() at time zone 'America/Chicago')::date;
  v_template uuid;
  v_instance uuid;
  v_completed integer;
  v_status text;
begin
  select service_types.id into v_type
  from public.service_types where service_types.name = 'Pot Washing';

  -- Every template built above is retired first, so generate_service_instances
  -- writes for this one and nothing else. Left active, its upsert would rewrite
  -- the start_time of the clock-relative fixtures sections 7 and 10 depend on.
  update public.service_templates set active = false where active;

  insert into public.service_templates (
    service_type_id, day_of_week, days_of_week, start_time, duration_minutes,
    slots_needed, participation_mode, start_date, created_by, active
  ) values (
    v_type, extract(dow from v_today)::integer, array[0,1,2,3,4,5,6],
    time '08:00', 120, 4, 'open', v_today, v_pres, true
  ) returning id into v_template;

  insert into public.service_template_assignees (
    service_template_id, devotee_id, assigned_by, status, days_of_week
  )
  select v_template, ids.id, v_pres, 'active', array[0,1,2,3,4,5,6]
  from public.ac_ids ids where ids.key = 'd16';

  perform public.generate_service_instances(1);

  select instances.id into v_instance
  from public.service_instances instances
  where instances.template_id = v_template and instances.date = v_today;
  if v_instance is null then
    raise exception 'The generator produced no instance for today.';
  end if;

  -- Yesterday, so its hour is unambiguously behind us whatever the clock says.
  update public.service_instances set date = v_today - 1 where id = v_instance;

  v_completed := public.complete_due_recurring_service_instances();
  if v_completed <> 1 then
    raise exception 'A real generated roster slot was not closed by the sweep (% completed).', v_completed;
  end if;

  select instances.status into v_status
  from public.service_instances instances where instances.id = v_instance;
  if v_status <> 'completed' then
    raise exception 'The generated slot is % after the sweep.', v_status;
  end if;

  if not exists (
    select 1 from public.service_assignments assignments
    join public.ac_ids ids on ids.id = assignments.devotee_id
    where assignments.service_instance_id = v_instance and ids.key = 'd16'
      and assignments.status = 'completed'
      and public.seva_points_status(assignments.status, assignments.attendance,
            assignments.verification, true) = 'counted'
  ) then
    raise exception 'The standing assignee on a real generated slot did not earn.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 10. The Chicago boundary, from four session timezones.
--
--     The due set is a property of the temple's clock. `soon` ends ninety
--     minutes from now in Chicago and `eleven` ends at eleven at night in
--     Chicago; a session in Asia/Kolkata runs about eleven hours ahead, so a
--     boundary computed in the SESSION's timezone would place `soon` in the
--     past and pay a devotee for seva they have not done yet.
-- ---------------------------------------------------------------------------

do $$
declare
  v_zone text;
  v_signature text;
  v_reference text := null;
begin
  foreach v_zone in array array['America/Chicago', 'UTC', 'Asia/Kolkata', 'Pacific/Auckland']
  loop
    perform set_config('timezone', v_zone, true);

    select coalesce(string_agg(due.service_instance_id::text, ',' order by due.service_instance_id), '(none)')
    into v_signature
    from public.due_recurring_service_instances due;

    if v_reference is null then
      v_reference := v_signature;
    elsif v_signature is distinct from v_reference then
      raise exception
        'The due set seen from % differs from the one seen from America/Chicago.', v_zone;
    end if;

    if exists (
      select 1 from public.due_recurring_service_instances due
      join public.ac_rows rows on rows.instance_id = due.service_instance_id
      where rows.key in ('soon', 'eleven')
    ) then
      raise exception
        'From %, a Chicago slot that has not finished yet reads as due. The boundary is being computed in the session''s timezone.',
        v_zone;
    end if;
  end loop;

  -- And the sweep itself, run from Asia, must not close them.
  perform set_config('timezone', 'Asia/Kolkata', true);
  if public.complete_due_recurring_service_instances() <> 0 then
    raise exception 'The sweep, called from Asia/Kolkata, closed a slot that has not happened yet.';
  end if;
  perform set_config('timezone', 'UTC', true);

  if exists (
    select 1 from public.service_instances instances
    join public.ac_rows rows on rows.instance_id = instances.id
    where rows.key in ('soon', 'eleven') and instances.status <> 'open'
  ) then
    raise exception 'A slot ending later tonight in Chicago is no longer open.';
  end if;
end;
$$;

reset timezone;

-- ---------------------------------------------------------------------------
-- 11. The queue the temple was pointing at.
--
--     list_seva_awaiting_confirmation over its own default window, read as the
--     President, who under 202608040027 is one of the only two people who could
--     ever have cleared it. Every recurring roster row whose hour had passed is
--     gone from it. What remains is exactly what still needs a person.
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.ac_ids ids where ids.key = 'pres'), true);

do $$
declare
  v_left text;
  v_row record;
begin
  -- 'soon' is excluded and only 'soon': it ends ninety minutes from now, so
  -- whether its Chicago date is today or tomorrow — and therefore whether the
  -- queue's `date <= today` lets it through — depends on the hour the suite is
  -- run at. It is a boundary probe for section 10, and it is asserted below to
  -- be waiting rather than swept.
  select coalesce(string_agg(distinct rows.key || '/' || ids.key, ', ' order by rows.key || '/' || ids.key), '(none)')
  into v_left
  from public.list_seva_awaiting_confirmation() queue
  join public.ac_rows rows on rows.instance_id = queue.service_instance_id
  join public.ac_ids ids on ids.id = queue.devotee_id
  where rows.key <> 'soon';

  -- decided/d8 -- a coordinator wrote 'served' on it and did not close the
  --               slot, so the sweep left their row alone and it is theirs to
  --               finish.
  -- oneoff/d2  -- a one-off seva. It has a poster and 202608040057's rule.
  if v_left <> 'decided/d8, oneoff/d2' then
    raise exception 'What still waits for a human is: %.', v_left;
  end if;

  if not exists (
    select 1 from public.list_seva_awaiting_confirmation() queue
    join public.ac_rows rows on rows.instance_id = queue.service_instance_id
    where rows.key = 'soon'
  ) and (now() at time zone 'America/Chicago' + interval '30 minutes')::date
        = (now() at time zone 'America/Chicago')::date
  then
    raise exception 'The slot that has not happened yet left the queue.';
  end if;

  -- Nothing recurring, SILENT and past is left in it at all. Silent is the
  -- word doing the work: decided/d8 above is recurring and past and still
  -- waiting, and it is right that it is, because somebody wrote 'served' on it.
  for v_row in
    select rows.key, ids.key as who
    from public.list_seva_awaiting_confirmation() queue
    join public.ac_rows rows on rows.instance_id = queue.service_instance_id
    join public.ac_ids ids on ids.id = queue.devotee_id
    join public.service_assignments assignments on assignments.id = queue.assignment_id
    where queue.is_recurring
      and assignments.attendance is null
      and ((queue.occurred_on + queue.started_at_local) at time zone 'America/Chicago')
          + make_interval(mins => queue.planned_minutes + 60) <= now()
  loop
    raise exception
      'A recurring slot whose Chicago hour passed (%/%) is still in the queue. This is the thing the temple asked about.',
      v_row.key, v_row.who;
  end loop;

  -- Beyond the lookback the sweep does not reach, and that is deliberate rather
  -- than accidental: asked over a year, the ancient slot is still a person's
  -- job.
  if not exists (
    select 1 from public.list_seva_awaiting_confirmation(
      (now() at time zone 'America/Chicago')::date - 365,
      (now() at time zone 'America/Chicago')::date) queue
    join public.ac_rows rows on rows.instance_id = queue.service_instance_id
    where rows.key = 'ancient'
  ) then
    raise exception
      'The slot older than the lookback was swept after all; the first run on the live database would resurrect years of roster.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);

-- ---------------------------------------------------------------------------
-- 12. What a signed-in devotee cannot do.
--
--     All of it under `set local role authenticated`, so the grants are what is
--     refusing rather than this script's superuser rights.
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.ac_ids ids where ids.key = 'd1'), true);

do $$
declare
  v_allowed boolean;
  v_instance uuid;
begin
  v_allowed := false;
  begin
    perform public.complete_due_recurring_service_instances();
    v_allowed := true;
  exception when insufficient_privilege then null;
  end;
  if v_allowed then
    raise exception 'A devotee can run the auto-completion sweep.';
  end if;

  v_allowed := false;
  begin
    perform 1 from public.due_recurring_service_instances;
    v_allowed := true;
  exception when insufficient_privilege then null;
  end;
  if v_allowed then
    raise exception 'A devotee can read the due view.';
  end if;

  select rows.instance_id into v_instance from public.ac_rows rows where rows.key = 'gracein';

  v_allowed := false;
  begin
    perform public.complete_service_instance_internal(v_instance, null, true);
    v_allowed := true;
  exception when insufficient_privilege then null;
  end;
  if v_allowed then
    raise exception
      'A devotee can call the completion write directly, which is 202608040023''s authority bypassed.';
  end if;

  -- And 202608040023 still refuses them the front door, in the same words.
  select rows.instance_id into v_instance from public.ac_rows rows where rows.key = 'future';
  v_allowed := false;
  begin
    perform public.complete_service_instance(v_instance);
    v_allowed := true;
  exception when others then
    if sqlstate <> 'P0001' then raise; end if;
    if position('Tech Admin' in sqlerrm) = 0 then
      raise exception 'A devotee was refused, but not by 202608040023''s rule: %', sqlerrm;
    end if;
  end;
  if v_allowed then
    raise exception 'A devotee closed a weekly seva they have no authority over.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);

-- One more slot, built here rather than in section 2, for the President to
-- close by hand.
--
-- This used to be the 'future' slot, and 202608040068 is why it cannot be:
-- that slot exists to prove the sweep leaves an hour that has not come alone,
-- so its start is three days ahead, and sentence 3 now refuses a completion
-- before the start on the front door as well. The two purposes cannot share
-- one row any more. 'future' keeps the one it was made for; this one starts
-- three hours ago in CHICAGO — derived from the clock, never a literal hour,
-- because a fixture pinned to a wall-clock time passes in the morning and
-- fails at midnight.
--
-- It is created after section 11 on purpose: it is recurring, past and silent,
-- which is exactly the shape the sweep claims and the queue counts, and every
-- one of those assertions has already been made above. Nothing sweeps after
-- this point.
do $$
declare
  v_start timestamp := (now() at time zone 'America/Chicago') - interval '3 hours';
  v_template uuid;
  v_type uuid;
  v_inst uuid;
begin
  select instances.template_id, instances.service_type_id
  into v_template, v_type
  from public.service_instances instances
  join public.ac_rows rows on rows.instance_id = instances.id
  where rows.key = 'past';

  insert into public.service_instances (
    template_id, service_type_id, date, start_time, duration_minutes,
    slots_needed, participation_mode, posted_by, status
  ) values (
    v_template, v_type, v_start::date, v_start::time, 120, 8, 'open', null, 'open'
  ) returning id into v_inst;
  insert into public.ac_rows (key, instance_id) values ('humanclose', v_inst);

  insert into public.service_assignments (
    service_instance_id, devotee_id, assignment_method, assigned_by,
    status, verification, attendance
  )
  select v_inst, ids.id, 'recurring_assignment', null, 'confirmed', 'self_report', null
  from public.ac_ids ids where ids.key = 'd16';

  -- The premise, stated rather than assumed: its hour HAS gone, so the only
  -- thing that can refuse the President below is a rule about authority or
  -- about the status the seva is already in.
  if public.seva_completion_opens_at(v_start::date, v_start::time) > now() then
    raise exception
      'The fixture slot for the President''s own completion does not read as started; the Chicago arithmetic is wrong.';
  end if;
end;
$$;

-- The President's own completion still works, and still writes the same shape
-- and the same notifications it did before the internal was lifted out.
set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.ac_ids ids where ids.key = 'pres'), true);

do $$
declare
  v_instance uuid;
  v_allowed boolean;
begin
  select rows.instance_id into v_instance from public.ac_rows rows where rows.key = 'humanclose';
  perform public.complete_service_instance(v_instance);

  if not exists (
    select 1 from public.service_instances where id = v_instance and status = 'completed'
  ) then
    raise exception 'The President''s completion did not close the instance.';
  end if;
  if not exists (
    select 1 from public.service_assignments assignments
    join public.ac_ids ids on ids.id = assignments.devotee_id
    where assignments.service_instance_id = v_instance and ids.key = 'd16'
      and assignments.status = 'completed' and assignments.completed_at is not null
  ) then
    raise exception 'The President''s completion did not close the assignment.';
  end if;
  -- Closing it twice is still 202608040023's refusal, word for word.
  v_allowed := false;
  begin
    perform public.complete_service_instance(v_instance);
    v_allowed := true;
  exception when others then
    if sqlstate <> 'P0001' then raise; end if;
    if sqlerrm <> 'This seva can no longer be completed.' then
      raise exception 'Completing twice was refused with: %', sqlerrm;
    end if;
  end;
  if v_allowed then
    raise exception 'A seva was completed twice.';
  end if;

  -- And a cancelled one is still refused with the same sentence.
  select rows.instance_id into v_instance from public.ac_rows rows where rows.key = 'cancelled';
  v_allowed := false;
  begin
    perform public.complete_service_instance(v_instance);
    v_allowed := true;
  exception when others then
    if sqlstate <> 'P0001' then raise; end if;
    if sqlerrm <> 'This seva can no longer be completed.' then
      raise exception 'Completing a cancelled seva was refused with: %', sqlerrm;
    end if;
  end;
  if v_allowed then
    raise exception 'A cancelled seva was completed.';
  end if;

  -- And 202608040068's sentence 3, on the row that used to be closed here:
  -- three days ahead, the President's own authority, and still no.
  select rows.instance_id into v_instance from public.ac_rows rows where rows.key = 'future';
  v_allowed := false;
  begin
    perform public.complete_service_instance(v_instance);
    v_allowed := true;
  exception when others then
    if sqlstate <> 'P0001' then raise; end if;
    if position('has not started yet' in sqlerrm) = 0 then
      raise exception 'A seva three days away was refused, but not by the clock: %', sqlerrm;
    end if;
  end;
  if v_allowed then
    raise exception 'The President closed a seva three days before it starts.';
  end if;
  if not exists (
    select 1 from public.service_instances where id = v_instance and status = 'open'
  ) then
    raise exception 'The refused completion moved the future slot anyway.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);

-- The human path DOES tell the devotee, because a person decided it, and that
-- is the half of the write the auto path deliberately drops. Asserted with the
-- role reset, because app_notifications is under row level security and the
-- President cannot read a message addressed to somebody else.
do $$
declare
  v_instance uuid := (select rows.instance_id from public.ac_rows rows where rows.key = 'humanclose');
begin
  if not exists (
    select 1 from public.app_notifications
    join public.ac_ids ids on ids.id = app_notifications.user_id
    where ids.key = 'd16' and app_notifications.kind = 'service_completed'
      and app_notifications.data ->> 'serviceInstanceId' = v_instance::text
  ) then
    raise exception
      'The President closed a seva and the devotee was not told; lifting the write out dropped a notification.';
  end if;

  -- The refused attempts in the block above must have written NOTHING. The
  -- instance UPDATE and its WHERE clause run before the assignment UPDATE for
  -- exactly this reason: a completion that is going to be refused must not
  -- close somebody's assignment on its way to being refused.
  if exists (
    select 1 from public.service_assignments assignments
    join public.ac_ids ids on ids.id = assignments.devotee_id
    join public.ac_rows rows on rows.instance_id = assignments.service_instance_id
    where rows.key = 'cancelled' and ids.key = 'd3'
      and (assignments.status <> 'confirmed' or assignments.completed_at is not null)
  ) then
    raise exception
      'A refused completion on a cancelled seva closed the assignment anyway. The two UPDATEs are in the wrong order.';
  end if;

  -- And the auto path told nobody in particular anything. The only message any
  -- of the auto-completed devotees could have had is the one they did not get.
  if exists (
    select 1 from public.app_notifications
    join public.ac_ids ids on ids.id = app_notifications.user_id
    where ids.key in ('d1', 'd7', 'd9', 'd11', 'd12')
  ) then
    raise exception 'A devotee was notified that a clock had closed their seva.';
  end if;
end;
$$;

do $$
begin
  raise notice 'all recurring autocomplete checks passed';
end;
$$;

select 'recurring autocomplete verification passed' as result;

rollback;
