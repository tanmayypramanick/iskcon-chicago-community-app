-- Functional verification for 202608040070_completion_window.sql.
--
-- Rolled back at the end. Every local is prefixed v_ so it can never shadow a
-- column name. Anything a devotee could really attempt is attempted as that
-- devotee, under `set local role authenticated`, so the grants, the row level
-- security and the permission checks are what is being tested rather than
-- superuser rights waving everything through.
--
-- ---------------------------------------------------------------------------
-- What is being proved.
--
--   1. A SEVA CANNOT BE MARKED COMPLETED WHILE IT IS STILL RUNNING, and can the
--      moment it is over. Both buttons — the poster's complete_service_instance
--      and the devotee's complete_my_service_assignment — and the boundary from
--      both sides, one second either way, on a seva whose start has long since
--      passed. The refusal names the right reason: a seva that is halfway
--      through is told it has not FINISHED, not that it has not started, which
--      is the sentence a devotee standing in the temple would know to be false.
--      Authority is not a bypass: the President is refused on the same seva.
--
--   2. THE BAR IS THE END, AND IT IS DIALS ALL THE WAY DOWN.
--      seva.complete_after_end_minutes moves both buttons together, cuts both
--      ways, and cannot pull the bar in front of the start.
--      seva.complete_after_start_minutes — 202608040068's dial, which this
--      change could have orphaned — still holds a seva shut on its own, as a
--      floor under the end. Nonsense in either dial raises rather than quietly
--      reverting to permissive.
--
--   3. THE TWO CLOCK GATES THAT MUST NOT HAVE MOVED DID NOT MOVE.
--      record_seva_attendance and verify_seva_assignment still open at the
--      START, proved on a seva that is running right now: the coordinator can
--      say who is here and cannot yet say that it happened. That is the whole
--      reason 0068 gave for putting the bar at the start, kept as a fact about
--      attendance rather than a fact about completion.
--
--   4. 202608040065'S HOURLY SWEEP STILL CLOSES WEEKLY OCCURRENCES, at exactly
--      the instant it closed them before — end plus its own grace, to the
--      microsecond — and the two rules cannot fight: turn the completion dial
--      past the sweep's grace and the sweep waits for the button rather than
--      beating it to the door.
--
--   5. A SEVA NOBODY EVER JOINED IS NOT COMPLETED AND DOES NOT VANISH. The
--      front door refuses it in words; a row that is already wrong goes back to
--      being an unclaimed request; it stays exactly where lapsedOpenRequests
--      looks for it; and it is NOT recorded as a seva 0068 closed, because that
--      table means something else and 202608040069 publishes it. A seva a
--      PERSON cancelled with nobody on it is still their decision and is left
--      alone.
--
--   6. THE THREE CASES ARE TOLD APART BY THE READ THE CLIENT ACTUALLY MAKES.
--      list_seva_schedule gives 'completed', 'cancelled' + nobody_served, and
--      'open' + nobody_served false, for the three fixtures built to be exactly
--      those three events.
--
--   7. 0068'S OWN RULES ARE STILL TRUE. All-absent still leaves the completed
--      list for 'cancelled' with its bookkeeping row; partial absence still
--      completes and still credits only the devotee who served.
--
--   and then fourteen mutations, each breaking exactly one guard and re-reading
--   one answer through the real function.
--
-- ---------------------------------------------------------------------------
-- Every instant in this file is derived from the Chicago clock, never written
-- as a literal hour, so the suite passes at 2am and at 2pm alike. The
-- one-second cases are not races: now() is the transaction's timestamp and this
-- whole file is one transaction, so the instant the fixture is built from is
-- the instant the guard compares against, however long the script takes.
--
-- Durations are multiples of 30 minutes between 30 and 720, because
-- 202608020002 constrains them and a fixture that dodges the constraint is a
-- fixture the temple can never have. Every boundary below is therefore built by
-- moving the START, with a 30-minute seva hung off it.
--
-- ---------------------------------------------------------------------------
-- The fixture. Eighteen devotees and sixteen seva.
--
--   key         start            dur  places              proves
--   -------------------------------------------------------------------------
--   running     now - 15 min     30   d_run               still running: no
--   edge        now + 1s - 30m   30   d_edge              one second short: no
--   exactly     now - 30 min     30   d_exact             ends exactly now: yes
--   bound       now - 30m - 1s   30   d_bound             one second past: yes
--   dialend     now - 45 min     30   d_dialend           the end dial
--   dialstart   now - 90 min     30   d_dialstart         0068's dial, as floor
--   grace       now - 25 min     30   d_grace             negative grace
--   attend      now - 15 min     30   d_attend            attendance at the START
--   buttonrun   now - 15 min     30   d_brun              the devotee's button
--   button      now - 3 hours    60   d_b1                the devotee's button
--   nojoin      now - 3 hours    60   nobody at all       never joined
--   nojoinpre   now - 3 hours    60   nobody, forged
--                                     'completed'         the row already wrong
--   humanempty  now - 3 hours    60   nobody, 'cancelled' a person's decision
--   allabsent   now - 3 hours    60   d_a1 + d_a2         0068, still true
--   partial     now - 3 hours    60   d_p1 + d_p2         0068, still true
--   sweep       recurring, -3h   60   d_sweep, silent     the hourly sweep
--
-- The final row must read: completion window verification passed

begin;

-- ---------------------------------------------------------------------------
-- 0. The ground.
--
--    What 0070 added, that it added nothing a client can reach, and that the
--    two gates it deliberately did not move are still where they were.
-- ---------------------------------------------------------------------------

do $$
declare
  v_name text;
begin
  if to_regprocedure('public.seva_completion_end_grace_minutes()') is null
    or to_regprocedure('public.seva_completion_opens_at(date, time, integer)') is null
    or to_regprocedure('public.seva_completion_opens_at(date, time)') is null
    or to_regprocedure('public.seva_completion_lead_minutes()') is null
    or to_regprocedure('public.reconcile_service_instance_completion(uuid)') is null
    or to_regclass('public.service_instances_unserved') is null
  then
    raise exception '202608040070 is not applied.';
  end if;

  if not exists (
    select 1 from public.app_settings where key = 'seva.complete_after_end_minutes'
  ) then
    raise exception 'The end-grace dial was not seeded, so the bar is a literal somewhere.';
  end if;

  -- 0068's dial is still there and still means what it meant. A change that
  -- deleted it would have silently dropped a bar a temple may have set.
  if not exists (
    select 1 from public.app_settings where key = 'seva.complete_after_start_minutes'
  ) then
    raise exception
      '202608040068''s dial was removed rather than kept as the floor under the new bar.';
  end if;

  -- One of each, except the boundary, which is deliberately two: the
  -- three-argument bar and the two-argument floor 0068 shipped, kept for the
  -- two verification files that ask it whether a seva has started. They are one
  -- clock — the two-argument form is the three-argument form asked about a seva
  -- of no length — and section 1 proves that rather than asserting it.
  for v_name in
    select proc.proname
    from pg_proc proc
    join pg_namespace spaces on spaces.oid = proc.pronamespace
    where spaces.nspname = 'public'
      and proc.proname in (
        'reconcile_service_instance_completion', 'service_instance_has_server',
        'seva_completion_lead_minutes', 'seva_completion_end_grace_minutes',
        'complete_service_instance', 'complete_service_instance_internal',
        'complete_my_service_assignment', 'record_seva_attendance')
    group by proc.proname
    having count(*) <> 1
  loop
    raise exception '% has more than one overload.', v_name;
  end loop;

  if (select count(*) from pg_proc proc
      join pg_namespace spaces on spaces.oid = proc.pronamespace
      where spaces.nspname = 'public' and proc.proname = 'seva_completion_opens_at') <> 2 then
    raise exception
      'public.seva_completion_opens_at has % forms rather than the two 0070 settles on.',
      (select count(*) from pg_proc proc
       join pg_namespace spaces on spaces.oid = proc.pronamespace
       where spaces.nspname = 'public' and proc.proname = 'seva_completion_opens_at');
  end if;

  -- The argument lists nothing in this repository is allowed to have changed.
  for v_name in
    select expected.name
    from (values
      ('complete_service_instance', 'p_instance_id uuid'),
      ('complete_service_instance_internal', 'p_instance_id uuid, p_actor_id uuid, p_auto boolean'),
      ('complete_my_service_assignment', 'p_instance_id uuid'),
      ('record_seva_attendance', 'p_assignment_id uuid, p_attendance text'),
      ('reconcile_service_instance_completion', 'p_instance_id uuid'),
      ('service_instance_has_server', 'p_instance_id uuid')
    ) as expected(name, args)
    where expected.args is distinct from coalesce(
      (select pg_get_function_identity_arguments(proc.oid)
       from pg_proc proc
       join pg_namespace spaces on spaces.oid = proc.pronamespace
       where spaces.nspname = 'public' and proc.proname = expected.name), '(missing)')
  loop
    raise exception 'public.% no longer takes the arguments other files pin it to.', v_name;
  end loop;
end;
$$;

do $$
begin
  -- The reconciler is not a button, and neither is the shared body.
  if has_function_privilege('authenticated',
       'public.reconcile_service_instance_completion(uuid)', 'execute')
    or has_function_privilege('authenticated',
       'public.complete_service_instance_internal(uuid, uuid, boolean)', 'execute')
  then
    raise exception 'A devotee can settle or close a seva without going through the front door.';
  end if;

  -- The two reads the client legitimately needs are open to a signed-in devotee
  -- and to nobody else.
  if not has_function_privilege('authenticated',
       'public.seva_completion_opens_at(date, time, integer)', 'execute')
    or not has_function_privilege('authenticated',
       'public.seva_completion_end_grace_minutes()', 'execute')
  then
    raise exception 'A signed-in devotee cannot ask when a seva may be completed.';
  end if;
  if has_function_privilege('anon', 'public.seva_completion_opens_at(date, time, integer)', 'execute')
    or has_function_privilege('anon', 'public.seva_completion_end_grace_minutes()', 'execute')
  then
    raise exception 'anon can reach 0070''s reads.';
  end if;

  -- The sweep's view is still nobody's to read.
  if has_table_privilege('authenticated', 'public.due_recurring_service_instances', 'select')
    or has_table_privilege('anon', 'public.due_recurring_service_instances', 'select')
  then
    raise exception 'Replacing the due view handed it to a client role.';
  end if;
end;
$$;

-- The guards themselves, in the bodies that must carry them.
do $$
declare
  v_case record;
  v_source text;
begin
  for v_case in
    select * from (values
      ('public.complete_service_instance(uuid)', 'instance_record.duration_minutes',
       'the poster''s button no longer measures the bar against the length of the seva'),
      ('public.complete_my_service_assignment(uuid)', 'instance_record.duration_minutes',
       'the devotee''s button no longer measures the bar against the length of the seva'),
      ('public.complete_service_instance_internal(uuid, uuid, boolean)',
       'reconcile_service_instance_completion',
       'the shared body no longer asks whether anybody served the seva'),
      ('public.record_seva_attendance(uuid, text)', 'reconcile_service_instance_completion',
       'marking the last server absent no longer takes the seva out of the completed list'),
      ('public.reconcile_service_instance_completion(uuid)', 'refresh_service_instance_capacity',
       'the reconciler decides an emptied instance''s status itself instead of asking 202608040019'),
      ('public.seva_completion_opens_at(date, time, integer)', 'America/Chicago',
       'the completion bar is no longer read in the temple''s time zone')
    ) as expected(target, needle, complaint)
  loop
    if pg_get_functiondef(v_case.target::regprocedure) !~* v_case.needle then
      raise exception '% (% no longer mentions %).', v_case.complaint, v_case.target, v_case.needle;
    end if;
  end loop;

  -- THE TWO GATES THAT MUST NOT HAVE MOVED. Asserted on the source as well as
  -- on behaviour below, because the behaviour test only sees today's dials: a
  -- body that read the completion bar would still pass section 5 at a moment
  -- when the two happen to coincide.
  for v_case in
    select * from (values
      ('public.record_seva_attendance(uuid, text)',
       'Attendance can be recorded once the seva has started.'),
      ('public.verify_seva_assignment(uuid)',
       'A seva can be verified once it has started.')
    ) as expected(target, sentence)
  loop
    if position(v_case.sentence in pg_get_functiondef(v_case.target::regprocedure)) = 0 then
      raise exception '% no longer opens at the start of the seva.', v_case.target;
    end if;
    if pg_get_functiondef(v_case.target::regprocedure) ~* 'seva_completion_opens_at' then
      raise exception
        '% now reads the completion bar, so a coordinator cannot mark somebody absent during the seva.',
        v_case.target;
    end if;
  end loop;

  -- THE CLOCK IS ASKED BEFORE THE WRITE, and the authority before the clock.
  -- Asserted on the source rather than on behaviour because behaviour cannot
  -- see it: a guard that closes the seva and THEN raises looks identical from
  -- outside, since the raise rolls the write back with it.
  v_source := pg_get_functiondef('public.complete_service_instance(uuid)'::regprocedure);
  if position('has_permission' in v_source) = 0
    or position('has_permission' in v_source) > position('seva_completion_opens_at' in v_source)
    or position('seva_completion_opens_at' in v_source)
       > position('complete_service_instance_internal' in v_source)
  then
    raise exception
      'complete_service_instance asks the clock in the wrong place: authority, then the clock, then the write.';
  end if;

  -- And the seva nobody joined is refused before the write, not settled after
  -- it. The count is taken after the clock and before the internal.
  if position('seva_completion_opens_at' in v_source)
     > position('from public.service_assignments' in v_source)
    or position('from public.service_assignments' in v_source)
       > position('complete_service_instance_internal' in v_source)
  then
    raise exception
      'complete_service_instance looks for the roster in the wrong place; a seva nobody joined would be closed and then quietly reopened.';
  end if;

  v_source := pg_get_functiondef('public.complete_my_service_assignment(uuid)'::regprocedure);
  if position('seva_completion_opens_at' in v_source) = 0
    or position('seva_completion_opens_at' in v_source)
       > position('update public.service_assignments' in v_source)
  then
    raise exception
      'complete_my_service_assignment closes the devotee''s place before it asks whether the seva has finished.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 1. The dials and the boundary, before any seva exists to be judged by them.
-- ---------------------------------------------------------------------------

do $$
declare
  v_today date := (now() at time zone 'America/Chicago')::date;
  v_start timestamptz := ((v_today + time '08:00') at time zone 'America/Chicago');
begin
  if public.seva_completion_end_grace_minutes() <> 0 then
    raise exception
      'seva.complete_after_end_minutes ships at % rather than 0, so the default bar is not the end of the seva.',
      public.seva_completion_end_grace_minutes();
  end if;
  if public.seva_completion_lead_minutes() <> 0 then
    raise exception
      'seva.complete_after_start_minutes ships at % rather than 0.',
      public.seva_completion_lead_minutes();
  end if;

  -- THE BAR IS THE END OF THE SEVA, for every length a seva may be.
  if public.seva_completion_opens_at(v_today, time '08:00', 30)
       <> v_start + interval '30 minutes'
    or public.seva_completion_opens_at(v_today, time '08:00', 60)
       <> v_start + interval '60 minutes'
    or public.seva_completion_opens_at(v_today, time '08:00', 720)
       <> v_start + interval '720 minutes'
  then
    raise exception
      'At the shipped dials the bar is not the seva''s own end; a 9:00 to 10:00 seva could be closed at 9:01 again.';
  end if;

  -- And the two-argument form 0068 shipped is that same function asked about a
  -- seva of no length, which is the start-side floor exactly.
  if public.seva_completion_opens_at(v_today, time '08:00')
     <> public.seva_completion_opens_at(v_today, time '08:00', 0) then
    raise exception 'The two forms of the boundary are two clocks rather than one.';
  end if;
  if public.seva_completion_opens_at(v_today, time '08:00') <> v_start then
    raise exception 'The floor is not the seva''s own Chicago start at the shipped dials.';
  end if;

  -- Chicago and only Chicago. Asked from four session timezones, because a
  -- boundary read in the SESSION's zone would open a Chicago morning seva half
  -- a day early for a devotee reading the app in Mayapur.
  perform set_config('timezone', 'UTC', true);
  if public.seva_completion_opens_at(v_today, time '08:00', 60) <> v_start + interval '60 minutes' then
    raise exception 'The completion bar moved when the session timezone did (UTC).';
  end if;
  perform set_config('timezone', 'Asia/Kolkata', true);
  if public.seva_completion_opens_at(v_today, time '08:00', 60) <> v_start + interval '60 minutes' then
    raise exception 'The completion bar moved when the session timezone did (Asia/Kolkata).';
  end if;
  perform set_config('timezone', 'Pacific/Auckland', true);
  if public.seva_completion_opens_at(v_today, time '08:00', 60) <> v_start + interval '60 minutes' then
    raise exception 'The completion bar moved when the session timezone did (Pacific/Auckland).';
  end if;
  perform set_config('timezone', 'America/Chicago', true);
end;
$$;

-- Both dials move the boundary, the floor holds under the grace, and nonsense
-- raises rather than falling back to permissive.
do $$
declare
  v_today date := (now() at time zone 'America/Chicago')::date;
  v_start timestamptz := ((v_today + time '08:00') at time zone 'America/Chicago');
  v_raised boolean;
begin
  -- THE GRACE, FORWARD.
  update public.app_settings set value = '45' where key = 'seva.complete_after_end_minutes';
  if public.seva_completion_end_grace_minutes() <> 45 then
    raise exception 'The end dial was set to 45 and reads %.', public.seva_completion_end_grace_minutes();
  end if;
  if public.seva_completion_opens_at(v_today, time '08:00', 60)
     <> v_start + interval '105 minutes' then
    raise exception 'The end dial does not move the boundary it is the dial for.';
  end if;

  -- THE GRACE, BACKWARD. The last ten minutes of a seva forgiven.
  update public.app_settings set value = '-10' where key = 'seva.complete_after_end_minutes';
  if public.seva_completion_opens_at(v_today, time '08:00', 60)
     <> v_start + interval '50 minutes' then
    raise exception 'A negative grace does not open the bar early; the dial only cuts one way.';
  end if;

  -- AND THE FLOOR HOLDS UNDER IT. However far back the grace is wound, the bar
  -- can never fall in front of the start: a seva that has not begun cannot have
  -- finished.
  update public.app_settings set value = '-1440' where key = 'seva.complete_after_end_minutes';
  if public.seva_completion_opens_at(v_today, time '08:00', 30) <> v_start then
    raise exception
      'A grace of a whole day put the completion bar before the seva started (%).',
      public.seva_completion_opens_at(v_today, time '08:00', 30);
  end if;

  -- 202608040068'S DIAL IS NOT ORPHANED. It is the floor, and on its own it
  -- still holds a seva shut long after the seva has ended.
  update public.app_settings set value = '0' where key = 'seva.complete_after_end_minutes';
  update public.app_settings set value = '240' where key = 'seva.complete_after_start_minutes';
  if public.seva_completion_opens_at(v_today, time '08:00', 30)
     <> v_start + interval '240 minutes' then
    raise exception
      '202608040068''s dial no longer holds a short seva shut; setting it does nothing, which is the definition of orphaned.';
  end if;
  -- And the later of the two wins, whichever it is.
  if public.seva_completion_opens_at(v_today, time '08:00', 720)
     <> v_start + interval '720 minutes' then
    raise exception 'The floor overtook the end of a long seva; the bar is not the later of the two.';
  end if;
  update public.app_settings set value = '0' where key = 'seva.complete_after_start_minutes';

  -- NONSENSE RAISES. 0055's rule for a dial, and this one is read on a button a
  -- devotee presses, so the error reaches somebody who can report it.
  update public.app_settings set value = 'forty' where key = 'seva.complete_after_end_minutes';
  v_raised := false;
  begin
    perform public.seva_completion_end_grace_minutes();
  exception when others then v_raised := true;
  end;
  if not v_raised then
    raise exception 'An end dial reading "forty" was accepted rather than raising.';
  end if;

  update public.app_settings set value = '1441' where key = 'seva.complete_after_end_minutes';
  v_raised := false;
  begin
    perform public.seva_completion_end_grace_minutes();
  exception when others then v_raised := true;
  end;
  if not v_raised then
    raise exception 'An end dial beyond a day was accepted.';
  end if;

  update public.app_settings set value = '-1441' where key = 'seva.complete_after_end_minutes';
  v_raised := false;
  begin
    perform public.seva_completion_end_grace_minutes();
  exception when others then v_raised := true;
  end;
  if not v_raised then
    raise exception 'An end dial beyond a day backwards was accepted.';
  end if;

  update public.app_settings set value = '0' where key = 'seva.complete_after_end_minutes';
  if public.seva_completion_end_grace_minutes() <> 0 then
    raise exception 'The end dial did not go back to its default.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. The congregation, the roster, and the premises stated rather than assumed.
-- ---------------------------------------------------------------------------

do $$
declare
  v_who text;
  v_i integer := 0;
begin
  foreach v_who in array array[
    'poster', 'president', 'outsider',
    'drun', 'dedge', 'dexact', 'dbound', 'ddialend', 'ddialstart', 'dgrace',
    'dattend', 'dbrun', 'db1', 'da1', 'da2', 'dp1', 'dp2', 'dsweep',
    'dm1', 'dm2'
  ] loop
    v_i := v_i + 1;
    insert into auth.users (id, email, raw_user_meta_data)
    values (
      ('70000000-0000-0000-0000-0000000000' || lpad(v_i::text, 2, '0'))::uuid,
      'cw-' || v_who || '@example.test',
      jsonb_build_object('name', 'Cw ' || initcap(v_who))
    );
    update public.users set name = 'Cw ' || initcap(v_who)
    where users.email = 'cw-' || v_who || '@example.test';
  end loop;
end;
$$;

update public.users
set role_id = (select roles.id from public.roles where roles.name = 'president')
where users.email = 'cw-president@example.test';

-- Ordinary tables rather than temporary ones, so reading them under the
-- authenticated role needs no assumptions about the temp schema. The whole
-- script is rolled back, so they never outlive the transaction.
create table public.cw_ids (key text primary key, id uuid not null);
grant select on public.cw_ids to authenticated;

insert into public.cw_ids (key, id)
select split_part(split_part(users.email, '@', 1), 'cw-', 2), users.id
from public.users where users.email like 'cw-%@example.test';

create table public.cw_rows (key text primary key, instance_id uuid not null);
grant select on public.cw_rows to authenticated;

create table public.cw_places (key text primary key, assignment_id uuid not null);
grant select on public.cw_places to authenticated;

-- The one-off seva. Every start derived from the Chicago clock and every
-- duration a legal one, so each end lands exactly where the table in the header
-- says it does.
do $$
declare
  v_now_chi timestamp := (now() at time zone 'America/Chicago');
  v_type uuid;
  v_poster uuid := (select ids.id from public.cw_ids ids where ids.key = 'poster');
  v_case record;
  v_when timestamp;
  v_inst uuid;
begin
  select service_types.id into v_type
  from public.service_types where service_types.name = 'Pot Washing';
  if v_type is null then
    raise exception 'The Pot Washing service type is missing from the seed.';
  end if;

  for v_case in
    select * from (values
      -- key,        start offset from now,                     dur, slots, status
      ('running',    interval '-15 minutes',                     30, 1, 'open'),
      ('edge',       interval '1 second' - interval '30 minutes',30, 1, 'open'),
      ('exactly',    interval '-30 minutes',                     30, 1, 'open'),
      ('bound',      interval '-30 minutes' - interval '1 second',30, 1, 'open'),
      ('dialend',    interval '-45 minutes',                     30, 1, 'open'),
      ('dialstart',  interval '-90 minutes',                     30, 1, 'open'),
      ('grace',      interval '-25 minutes',                     30, 1, 'open'),
      ('attend',     interval '-15 minutes',                     30, 1, 'open'),
      ('buttonrun',  interval '-15 minutes',                     30, 1, 'open'),
      ('button',     interval '-3 hours',                        60, 1, 'open'),
      ('nojoin',     interval '-3 hours',                        60, 1, 'open'),
      ('nojoinpre',  interval '-3 hours',                        60, 1, 'completed'),
      ('humanempty', interval '-3 hours',                        60, 1, 'cancelled'),
      ('allabsent',  interval '-3 hours',                        60, 2, 'open'),
      ('partial',    interval '-3 hours',                        60, 2, 'open'),
      -- Two rows nothing above touches, kept for section 11 so that every
      -- mutation probe starts from a state the earlier sections have not
      -- already settled. Both are forged 'completed', which is the shape the
      -- temple's database actually holds.
      ('mutempty',   interval '-3 hours',                        60, 1, 'completed'),
      ('mutabs',     interval '-3 hours',                        60, 2, 'completed')
    ) as plan(key, offset_from_now, dur, slots, status)
  loop
    v_when := v_now_chi + v_case.offset_from_now;
    insert into public.service_instances (
      service_type_id, date, start_time, duration_minutes,
      slots_needed, participation_mode, posted_by, status
    ) values (
      v_type, v_when::date, v_when::time, v_case.dur,
      v_case.slots, 'open', v_poster, v_case.status
    ) returning id into v_inst;
    insert into public.cw_rows (key, instance_id) values (v_case.key, v_inst);
  end loop;
end;
$$;

-- The recurring slot the sweep is for.
do $$
declare
  v_when timestamp := (now() at time zone 'America/Chicago') - interval '3 hours';
  v_type uuid;
  v_pres uuid := (select ids.id from public.cw_ids ids where ids.key = 'president');
  v_template uuid;
  v_inst uuid;
begin
  select service_types.id into v_type
  from public.service_types where service_types.name = 'Pot Washing';

  insert into public.service_templates (
    service_type_id, day_of_week, days_of_week, start_time, duration_minutes,
    slots_needed, participation_mode, start_date, created_by, active
  )
  select v_type, 0, array[0,1,2,3,4,5,6], v_when::time, 60, 4, 'open',
    v_when::date - 400, v_pres, true
  returning id into v_template;

  insert into public.service_instances (
    template_id, service_type_id, date, start_time, duration_minutes,
    slots_needed, participation_mode, posted_by, status
  ) values (
    v_template, v_type, v_when::date, v_when::time, 60, 4, 'open', null, 'open'
  ) returning id into v_inst;
  insert into public.cw_rows (key, instance_id) values ('sweep', v_inst);
end;
$$;

-- The places. Everybody confirmed and silent: nobody has said anything about
-- anybody, which is the state every roster in the temple is in until a
-- coordinator speaks.
do $$
declare
  v_case record;
  v_assignment uuid;
begin
  for v_case in
    select * from (values
      ('running',   'drun'),       ('edge',      'dedge'),
      ('exactly',   'dexact'),     ('bound',     'dbound'),
      ('dialend',   'ddialend'),   ('dialstart', 'ddialstart'),
      ('grace',     'dgrace'),     ('attend',    'dattend'),
      ('buttonrun', 'dbrun'),      ('button',    'db1'),
      ('allabsent', 'da1'),        ('allabsent', 'da2'),
      ('partial',   'dp1'),        ('partial',   'dp2'),
      ('sweep',     'dsweep')
    ) as plan(instance_key, who)
  loop
    insert into public.service_assignments (
      service_instance_id, devotee_id, assignment_method, assigned_by,
      status, verification, attendance
    )
    select rows.instance_id,
      (select ids.id from public.cw_ids ids where ids.key = v_case.who),
      'recurring_assignment', null, 'confirmed', 'member_verified', null
    from public.cw_rows rows where rows.key = v_case.instance_key
    returning id into v_assignment;

    insert into public.cw_places (key, assignment_id) values (v_case.who, v_assignment);
  end loop;

  -- The seva that is running now is the one a coordinator speaks about while it
  -- happens, so its place starts unverified: section 4 raises it, and a place
  -- that shipped already verified would have proved nothing.
  update public.service_assignments set verification = 'self_report'
  where id = (select places.assignment_id from public.cw_places places where places.key = 'dattend');

  -- Section 11's own two rows: a completed seva both of whose devotees were
  -- marked absent, never yet reconciled.
  for v_case in
    select * from (values ('mutabs', 'dm1'), ('mutabs', 'dm2')) as plan(instance_key, who)
  loop
    insert into public.service_assignments (
      service_instance_id, devotee_id, assignment_method, assigned_by,
      status, verification, attendance
    )
    select rows.instance_id,
      (select ids.id from public.cw_ids ids where ids.key = v_case.who),
      'recurring_assignment', null, 'completed', 'member_verified', 'absent'
    from public.cw_rows rows where rows.key = v_case.instance_key
    returning id into v_assignment;

    insert into public.cw_places (key, assignment_id) values (v_case.who, v_assignment);
  end loop;
end;
$$;

-- The premises. If the Chicago arithmetic above is wrong, every refusal below
-- would be right for the wrong reason.
do $$
declare
  v_case record;
  v_opens timestamptz;
  v_started boolean;
begin
  for v_case in
    select * from (values
      -- key,        has the seva started,  may it be completed
      ('running',    true,  false),
      ('edge',       true,  false),
      ('exactly',    true,  true),
      ('bound',      true,  true),
      ('dialend',    true,  true),
      ('dialstart',  true,  true),
      ('grace',      true,  false),
      ('attend',     true,  false),
      ('buttonrun',  true,  false),
      ('button',     true,  true),
      ('nojoin',     true,  true),
      ('allabsent',  true,  true),
      ('partial',    true,  true),
      ('sweep',      true,  true)
    ) as expected(key, has_started, may_complete)
  loop
    select
      public.seva_completion_opens_at(
        instances.date, instances.start_time, instances.duration_minutes),
      ((instances.date + instances.start_time) at time zone 'America/Chicago') <= now()
    into v_opens, v_started
    from public.service_instances instances
    join public.cw_rows rows on rows.instance_id = instances.id
    where rows.key = v_case.key;

    if v_started <> v_case.has_started then
      raise exception 'The "%" fixture was built to have started = %.', v_case.key, v_case.has_started;
    end if;
    if (v_opens <= now()) <> v_case.may_complete then
      raise exception
        'The "%" fixture opens at %, and now is %; it was built to be completable = %.',
        v_case.key, v_opens, now(), v_case.may_complete;
    end if;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. THE WHOLE COMPLAINT. A seva that is still running cannot be marked
--    completed; one that is over can; and the boundary is exact.
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.cw_ids ids where ids.key = 'poster'), true);

do $$
declare
  v_case record;
  v_instance uuid;
  v_allowed boolean;
  v_before text;
begin
  -- Fifteen minutes into a thirty-minute seva, and one second short of its end,
  -- are refused alike — and refused for the RIGHT reason. "This seva has not
  -- started yet" would be a sentence the devotee knows to be false, because
  -- they are standing in it.
  for v_case in select unnest(array['running', 'edge']) as key loop
    select rows.instance_id into v_instance from public.cw_rows rows where rows.key = v_case.key;
    select instances.status into v_before
    from public.service_instances instances where instances.id = v_instance;
    v_allowed := false;
    begin
      perform public.complete_service_instance(v_instance);
      v_allowed := true;
    exception when others then
      if sqlstate <> 'P0001' then raise; end if;
      if position('has not finished yet' in sqlerrm) = 0 then
        raise exception
          'The "%" seva is halfway through and was refused with: %', v_case.key, sqlerrm;
      end if;
      if position('You can mark it completed once its time on' in sqlerrm) = 0 then
        raise exception
          'The refusal on "%" does not tell the devotee when they may come back: %',
          v_case.key, sqlerrm;
      end if;
    end;
    if v_allowed then
      raise exception
        'The "%" seva was marked completed while it was still going on. This is the temple''s complaint, unfixed.',
        v_case.key;
    end if;

    -- A refused completion must write NOTHING.
    if exists (
      select 1 from public.service_instances
      where id = v_instance and status is distinct from v_before
    ) then
      raise exception 'The refused completion moved the "%" instance from % anyway.',
        v_case.key, v_before;
    end if;
    if exists (
      select 1 from public.service_assignments
      where service_instance_id = v_instance
        and (status <> 'confirmed' or completed_at is not null)
    ) then
      raise exception 'The refused completion closed a place on "%" anyway.', v_case.key;
    end if;
  end loop;

  -- The instant the seva ends, and one second after, are both allowed. The
  -- guard is `opens_at > now()`, so a seva ending this instant may be completed
  -- this instant.
  for v_case in select unnest(array['exactly', 'bound']) as key loop
    select rows.instance_id into v_instance from public.cw_rows rows where rows.key = v_case.key;
    begin
      perform public.complete_service_instance(v_instance);
    exception when others then
      raise exception 'The "%" seva is over and was refused: %', v_case.key, sqlerrm;
    end;
    if not exists (
      select 1 from public.service_instances where id = v_instance and status = 'completed'
    ) then
      raise exception 'The "%" seva was allowed and did not close.', v_case.key;
    end if;
  end loop;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);

-- The President holds app.view_all and closes anybody's seva. The clock is
-- still the clock: the bar is on the seva, not on the person.
set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.cw_ids ids where ids.key = 'president'), true);

do $$
declare
  v_instance uuid := (select rows.instance_id from public.cw_rows rows where rows.key = 'running');
  v_allowed boolean := false;
begin
  begin
    perform public.complete_service_instance(v_instance);
    v_allowed := true;
  exception when others then
    if sqlstate <> 'P0001' then raise; end if;
    if position('has not finished yet' in sqlerrm) = 0 then
      raise exception 'The President was refused, but not by the clock: %', sqlerrm;
    end if;
  end;
  if v_allowed then
    raise exception 'The President closed a seva that was still going on.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);

-- AND THE DEVOTEE'S OWN BUTTON, which can flip the whole instance by itself,
-- opens at the same instant and says so in 202608040019's words.
set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.cw_ids ids where ids.key = 'dbrun'), true);

do $$
declare
  v_instance uuid := (select rows.instance_id from public.cw_rows rows where rows.key = 'buttonrun');
  v_allowed boolean := false;
begin
  begin
    perform public.complete_my_service_assignment(v_instance);
    v_allowed := true;
  exception when others then
    if sqlstate <> 'P0001' then raise; end if;
    if sqlerrm <> 'You can mark this seva completed once it has finished.' then
      raise exception 'A devotee''s own button on a running seva was refused with: %', sqlerrm;
    end if;
  end;
  if v_allowed then
    raise exception 'A devotee reported their seva finished while they were still doing it.';
  end if;
  if exists (
    select 1 from public.service_assignments
    where service_instance_id = v_instance and status <> 'confirmed'
  ) then
    raise exception 'The refused self-completion closed the place anyway.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);

set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.cw_ids ids where ids.key = 'db1'), true);

do $$
declare
  v_instance uuid := (select rows.instance_id from public.cw_rows rows where rows.key = 'button');
begin
  perform public.complete_my_service_assignment(v_instance);
  if not exists (
    select 1 from public.service_instances where id = v_instance and status = 'completed'
  ) then
    raise exception 'A devotee could not close their own place on a seva that ended two hours ago.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);

-- ---------------------------------------------------------------------------
-- 4. THE TWO GATES THAT DID NOT MOVE, on a seva that is running RIGHT NOW.
--
--    A coordinator marks somebody absent standing in front of the empty place,
--    and verifies a devotee who has just finished their part. Neither waits for
--    the seva to be over. The same instance refuses a completion in the same
--    breath, which is the distinction 0070 rests on: "who is here?" is asked
--    during, "did this happen?" only after.
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.cw_ids ids where ids.key = 'poster'), true);

do $$
declare
  v_instance uuid := (select rows.instance_id from public.cw_rows rows where rows.key = 'attend');
  v_place uuid := (select places.assignment_id from public.cw_places places where places.key = 'dattend');
  v_allowed boolean := false;
begin
  -- The completion is refused...
  begin
    perform public.complete_service_instance(v_instance);
    v_allowed := true;
  exception when others then
    if sqlstate <> 'P0001' then raise; end if;
    if position('has not finished yet' in sqlerrm) = 0 then raise; end if;
  end;
  if v_allowed then
    raise exception 'A running seva was completed; section 3 already said so.';
  end if;

  -- ...and in the same minute, on the same seva, the coordinator says who is
  -- here and confirms that they served.
  perform public.record_seva_attendance(v_place, 'served');
  if not exists (
    select 1 from public.service_assignments
    where id = v_place and attendance = 'served'
  ) then
    raise exception
      'Attendance could not be recorded on a seva that is happening now. 0070 dragged record_seva_attendance to the end with it.';
  end if;

  perform public.verify_seva_assignment(v_place);
  if not exists (
    select 1 from public.service_assignments
    where id = v_place and verification = 'member_verified'
  ) then
    raise exception
      'A devotee could not be verified on a seva that is happening now. 0070 dragged verify_seva_assignment to the end with it.';
  end if;

  -- And recording attendance did not quietly complete the instance.
  if exists (
    select 1 from public.service_instances
    where id = v_instance and status in ('completed', 'cancelled')
  ) then
    raise exception 'Recording attendance on a running seva settled it.';
  end if;

  -- Marking somebody ABSENT during a running seva is the same door, and it
  -- still cannot make the seva "not completed" — there is nothing to take out
  -- of a list the seva was never in.
  perform public.record_seva_attendance(v_place, 'absent');
  if exists (
    select 1 from public.service_instances
    where id = v_instance and status <> 'open' and status <> 'full'
  ) then
    raise exception 'An absence recorded during a running seva cancelled it.';
  end if;
  perform public.record_seva_attendance(v_place, 'served');
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);

-- ---------------------------------------------------------------------------
-- 5. BOTH DIALS, ON THE REAL BUTTONS.
--
--    Section 1 proved the arithmetic. This proves the buttons read it: the same
--    seva is refused and then allowed as the dial moves, and 202608040068's
--    dial still holds a seva shut on its own.
-- ---------------------------------------------------------------------------

-- 'dialend' ended fifteen minutes ago. A grace of thirty minutes shuts it.
update public.app_settings set value = '30' where key = 'seva.complete_after_end_minutes';

set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.cw_ids ids where ids.key = 'poster'), true);

do $$
declare
  v_instance uuid := (select rows.instance_id from public.cw_rows rows where rows.key = 'dialend');
  v_allowed boolean := false;
begin
  begin
    perform public.complete_service_instance(v_instance);
    v_allowed := true;
  exception when others then
    if sqlstate <> 'P0001' then raise; end if;
    if position('has not finished yet' in sqlerrm) = 0 then
      raise exception 'The dialled-up grace refused for the wrong reason: %', sqlerrm;
    end if;
  end;
  if v_allowed then
    raise exception
      'A seva that ended fifteen minutes ago was closed against a thirty-minute grace; the dial does not reach the button.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);

update public.app_settings set value = '0' where key = 'seva.complete_after_end_minutes';

set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.cw_ids ids where ids.key = 'poster'), true);

do $$
declare
  v_instance uuid := (select rows.instance_id from public.cw_rows rows where rows.key = 'dialend');
begin
  perform public.complete_service_instance(v_instance);
  if not exists (
    select 1 from public.service_instances where id = v_instance and status = 'completed'
  ) then
    raise exception 'With the grace back at zero the seva that ended fifteen minutes ago did not close.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);

-- 202608040068's DIAL, WHICH THIS FILE COULD HAVE ORPHANED. 'dialstart' started
-- ninety minutes ago and ended sixty minutes ago: the end says yes and the old
-- dial, set to four hours, still says no.
update public.app_settings set value = '240' where key = 'seva.complete_after_start_minutes';

set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.cw_ids ids where ids.key = 'ddialstart'), true);

do $$
declare
  v_instance uuid := (select rows.instance_id from public.cw_rows rows where rows.key = 'dialstart');
  v_allowed boolean := false;
begin
  begin
    perform public.complete_my_service_assignment(v_instance);
    v_allowed := true;
  exception when others then
    if sqlstate <> 'P0001' then raise; end if;
    if sqlerrm <> 'You can mark this seva completed once it has finished.' then
      raise exception 'The old dial refused the devotee with: %', sqlerrm;
    end if;
  end;
  if v_allowed then
    raise exception
      'seva.complete_after_start_minutes was set to four hours and a seva ninety minutes old closed anyway. The dial is orphaned.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);

update public.app_settings set value = '0' where key = 'seva.complete_after_start_minutes';

-- AND THE GRACE THE OTHER WAY. 'grace' has five minutes left to run; a temple
-- that forgives the last ten minutes may close it now.
update public.app_settings set value = '-10' where key = 'seva.complete_after_end_minutes';

set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.cw_ids ids where ids.key = 'poster'), true);

do $$
declare
  v_instance uuid := (select rows.instance_id from public.cw_rows rows where rows.key = 'grace');
begin
  perform public.complete_service_instance(v_instance);
  if not exists (
    select 1 from public.service_instances where id = v_instance and status = 'completed'
  ) then
    raise exception 'A negative grace did not open the button early on the seva it was set for.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);

update public.app_settings set value = '0' where key = 'seva.complete_after_end_minutes';

-- ---------------------------------------------------------------------------
-- 6. 202608040065'S HOURLY SWEEP: unmoved at the shipped dials, and unable to
--    become the early door at any other.
-- ---------------------------------------------------------------------------

do $$
declare
  v_one uuid := (select rows.instance_id from public.cw_rows rows where rows.key = 'sweep');
  v_due timestamptz;
  v_ends timestamptz;
begin
  select due.due_at, due.ends_at into v_due, v_ends
  from public.due_recurring_service_instances due
  where due.service_instance_id = v_one;
  if v_due is null then
    raise exception
      'The recurring slot whose Chicago hour and grace have gone is not due; 0070 has reached into 0065''s selection.';
  end if;

  -- THE SWEEP DID NOT MOVE. Its bar is still its own grace past the end, to the
  -- microsecond, read back through the dial rather than a literal.
  if v_due <> v_ends + make_interval(mins => (
       coalesce(nullif(trim(public.app_setting('seva.auto_complete_grace_minutes')), ''), '60')::integer))
  then
    raise exception
      'The sweep''s due_at is % rather than its own end plus its own grace (%); 0070 changed when weekly seva closes.',
      v_due, v_ends;
  end if;
end;
$$;

-- AND THE TWO CANNOT FIGHT. A completion grace of three hours is longer than
-- the sweep's own, so the sweep must wait for the button rather than closing a
-- seva no person is allowed to close.
update public.app_settings set value = '180' where key = 'seva.complete_after_end_minutes';

do $$
declare
  v_one uuid := (select rows.instance_id from public.cw_rows rows where rows.key = 'sweep');
  v_closed integer;
begin
  if exists (
    select 1 from public.due_recurring_service_instances where service_instance_id = v_one
  ) then
    raise exception
      'The sweep is due to close a slot that a President pressing the button would be refused on. The clock holds an authority no person has.';
  end if;
  v_closed := public.complete_due_recurring_service_instances();
  if exists (
    select 1 from public.service_instances where id = v_one and status <> 'open'
  ) then
    raise exception 'The sweep closed a slot whose completion bar had not been reached.';
  end if;
end;
$$;

update public.app_settings set value = '0' where key = 'seva.complete_after_end_minutes';

-- With the dials back where they ship, the weekly occurrence closes exactly as
-- it did before 0070 was written.
do $$
declare
  v_one uuid := (select rows.instance_id from public.cw_rows rows where rows.key = 'sweep');
begin
  if not exists (
    select 1 from public.due_recurring_service_instances where service_instance_id = v_one
  ) then
    raise exception 'The slot stopped being due when the dial went back.';
  end if;

  perform public.complete_due_recurring_service_instances();

  if not exists (
    select 1 from public.service_instances where id = v_one and status = 'completed'
  ) then
    raise exception
      'The sweep did not close a due weekly occurrence. 0070 broke 202608040065.';
  end if;
  if not exists (
    select 1 from public.service_assignments
    where service_instance_id = v_one and status = 'completed'
  ) then
    raise exception 'The sweep closed the instance and not the place.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. THE SEVA NOBODY EVER JOINED.
--
--    Refused at the door in words; put back to an unclaimed request if it is
--    already wrong; still exactly where lapsedOpenRequests looks for it; and
--    never recorded as a seva 0068 closed, because that table means the other
--    thing.
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.cw_ids ids where ids.key = 'poster'), true);

do $$
declare
  v_instance uuid := (select rows.instance_id from public.cw_rows rows where rows.key = 'nojoin');
  v_allowed boolean := false;
  v_before text;
begin
  select instances.status into v_before
  from public.service_instances instances where instances.id = v_instance;

  begin
    perform public.complete_service_instance(v_instance);
    v_allowed := true;
  exception when others then
    if sqlstate <> 'P0001' then raise; end if;
    if position('Nobody joined this seva' in sqlerrm) = 0 then
      raise exception
        'The seva nobody joined was refused, but not for that reason: %', sqlerrm;
    end if;
  end;
  if v_allowed then
    raise exception
      'A seva nobody was ever placed on was marked completed. As if no one served this, how is this seva completed.';
  end if;

  if exists (
    select 1 from public.service_instances
    where id = v_instance and status is distinct from v_before
  ) then
    raise exception 'The refused completion moved the unclaimed request from % anyway.', v_before;
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);

-- The row that is ALREADY WRONG, which is what section 9 of the migration
-- sweeps up: forged 'completed' with nobody on it, exactly as the temple's
-- database holds it. The reconciler puts it back to what 202608040019 says an
-- instance with nothing on it is.
do $$
declare
  v_instance uuid := (select rows.instance_id from public.cw_rows rows where rows.key = 'nojoinpre');
  v_settled text;
begin
  v_settled := public.reconcile_service_instance_completion(v_instance);
  if v_settled = 'completed' then
    raise exception
      'A seva nobody joined stayed in the completed list. This is finding two, unfixed.';
  end if;
  if v_settled <> 'open' then
    raise exception
      'The seva nobody joined settled on "%" rather than the unclaimed status 202608040019 gives an empty instance.',
      v_settled;
  end if;

  -- Idempotent: asking again changes nothing.
  if public.reconcile_service_instance_completion(v_instance) <> 'open' then
    raise exception 'Reconciling the same empty instance twice moved it.';
  end if;

  -- AND IT IS NOT RECORDED AS A SEVA 0068 CLOSED. That table means "every place
  -- on it was answered no", 202608040069 publishes it as nobody_served, and a
  -- seva with no places is a different event.
  if exists (
    select 1 from public.service_instances_unserved where service_instance_id = v_instance
  ) then
    raise exception
      'A seva nobody joined was recorded in service_instances_unserved, which means all-absent and is published as nobody_served.';
  end if;
end;
$$;

-- A SEVA A PERSON CANCELLED WITH NOBODY ON IT IS STILL THEIR DECISION.
do $$
declare
  v_instance uuid := (select rows.instance_id from public.cw_rows rows where rows.key = 'humanempty');
begin
  if public.reconcile_service_instance_completion(v_instance) <> 'cancelled' then
    raise exception
      'An empty seva a person cancelled was reopened; 0070 has undone a human decision.';
  end if;
end;
$$;

-- IT DOES NOT VANISH. lapsedOpenRequests is, in the client's own words,
-- `template_id is null and status not in ('completed','cancelled') and
-- participation_mode = 'open' and the end has passed`. Both never-joined seva
-- satisfy it, which is the temple asking for passed unclaimed requests to reach
-- history rather than disappear.
set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.cw_ids ids where ids.key = 'poster'), true);

do $$
declare
  v_case record;
  v_seen integer;
begin
  for v_case in select unnest(array['nojoin', 'nojoinpre']) as key loop
    select count(*) into v_seen
    from public.service_instances instances
    join public.cw_rows rows on rows.instance_id = instances.id
    where rows.key = v_case.key
      and instances.template_id is null
      and instances.status not in ('completed', 'cancelled')
      and instances.participation_mode = 'open'
      and ((instances.date + instances.start_time) at time zone 'America/Chicago')
          + make_interval(mins => instances.duration_minutes) <= now();
    if v_seen <> 1 then
      raise exception
        'The "%" seva is not where lapsedOpenRequests looks for it, so an unclaimed request the temple asked to keep has vanished from the app.',
        v_case.key;
    end if;
  end loop;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);

-- ---------------------------------------------------------------------------
-- 8. 202608040068'S OWN RULES, STILL TRUE.
--
--    All-absent still leaves the completed list, with the bookkeeping row that
--    makes it reversible; partial absence still completes.
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.cw_ids ids where ids.key = 'poster'), true);

do $$
declare
  v_instance uuid := (select rows.instance_id from public.cw_rows rows where rows.key = 'allabsent');
begin
  perform public.complete_service_instance(v_instance);
  perform public.record_seva_attendance(
    (select places.assignment_id from public.cw_places places where places.key = 'da1'), 'absent');
  if not exists (
    select 1 from public.service_instances where id = v_instance and status = 'completed'
  ) then
    raise exception 'One devotee of two was marked absent and the seva left the completed list.';
  end if;

  perform public.record_seva_attendance(
    (select places.assignment_id from public.cw_places places where places.key = 'da2'), 'excused');
  if not exists (
    select 1 from public.service_instances where id = v_instance and status = 'cancelled'
  ) then
    raise exception
      'Every place on the seva was marked absent or excused and it is still in the completed list.';
  end if;
end;
$$;

do $$
declare
  v_instance uuid := (select rows.instance_id from public.cw_rows rows where rows.key = 'partial');
begin
  perform public.complete_service_instance(v_instance);
  perform public.record_seva_attendance(
    (select places.assignment_id from public.cw_places places where places.key = 'dp1'), 'served');
  perform public.record_seva_attendance(
    (select places.assignment_id from public.cw_places places where places.key = 'dp2'), 'absent');
  if not exists (
    select 1 from public.service_instances where id = v_instance and status = 'completed'
  ) then
    raise exception
      'One of two devotees was absent and the seva left the completed list. One person did it, so it happened.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);

do $$
begin
  if not exists (
    select 1 from public.service_instances_unserved unserved
    join public.cw_rows rows on rows.instance_id = unserved.service_instance_id
    where rows.key = 'allabsent'
  ) then
    raise exception
      'The all-absent seva was cancelled without the row that makes it reversible.';
  end if;
  if exists (
    select 1 from public.service_instances_unserved unserved
    join public.cw_rows rows on rows.instance_id = unserved.service_instance_id
    where rows.key in ('partial', 'nojoin', 'nojoinpre', 'humanempty')
  ) then
    raise exception 'Something other than an all-absent seva was recorded as one 0068 closed.';
  end if;
end;
$$;

-- And only the devotee who served is credited, which is where a devotee's
-- minutes actually come from.
do $$
declare
  v_row record;
begin
  select acts.points_status, acts.credited_minutes into v_row
  from public.seva_mala_acts((select ids.id from public.cw_ids ids where ids.key = 'dp1')) acts
  join public.cw_rows rows on rows.instance_id = acts.service_instance_id
  where rows.key = 'partial';
  if v_row.points_status <> 'counted' or coalesce(v_row.credited_minutes, 0) <= 0 then
    raise exception 'The devotee who served the seva reads % for % minutes.',
      v_row.points_status, v_row.credited_minutes;
  end if;

  select acts.points_status, acts.credited_minutes into v_row
  from public.seva_mala_acts((select ids.id from public.cw_ids ids where ids.key = 'dp2')) acts
  join public.cw_rows rows on rows.instance_id = acts.service_instance_id
  where rows.key = 'partial';
  if v_row.points_status <> 'not_served' or coalesce(v_row.credited_minutes, 1) <> 0 then
    raise exception 'The absent devotee is credited % minutes (%).',
      v_row.credited_minutes, v_row.points_status;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 9. THE THREE CASES, TOLD APART BY THE READ THE CLIENT ACTUALLY MAKES.
--
--    202608040069's list_seva_schedule is the timetable the app lays out, and
--    it carries both halves: the status, and whether this is a seva 0068 took
--    out of the completed list. Three fixtures, three different answers, no
--    sixth status invented for any of them.
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.cw_ids ids where ids.key = 'president'), true);

do $$
declare
  v_case record;
  v_row record;
  v_from date := ((now() at time zone 'America/Chicago')::date - 1);
  v_to date := ((now() at time zone 'America/Chicago')::date + 1);
begin
  for v_case in
    select * from (values
      ('partial',   'completed', false, 'somebody served it'),
      ('allabsent', 'cancelled', true,  'everybody on it was marked absent or excused'),
      ('nojoinpre', 'open',      false, 'nobody ever joined it')
    ) as expected(key, status, nobody_served, what_happened)
  loop
    select listed.status, listed.nobody_served, listed.filled_slots
    into v_row
    from public.list_seva_schedule(v_from, v_to, null) listed
    join public.cw_rows rows on rows.instance_id = listed.service_instance_id
    where rows.key = v_case.key;

    if v_row.status is null then
      raise exception 'The "%" seva is not in the timetable at all.', v_case.key;
    end if;
    if v_row.status is distinct from v_case.status
      or v_row.nobody_served is distinct from v_case.nobody_served then
      raise exception
        'The seva where % reads status % / nobody_served %, which the app cannot tell from the other two cases.',
        v_case.what_happened, v_row.status, v_row.nobody_served;
    end if;
  end loop;

  -- And the never-joined one carries nobody, which is the third column that
  -- makes it unmistakable.
  select listed.filled_slots into v_row
  from public.list_seva_schedule(v_from, v_to, null) listed
  join public.cw_rows rows on rows.instance_id = listed.service_instance_id
  where rows.key = 'nojoinpre';
  if v_row.filled_slots <> 0 then
    raise exception 'The seva nobody joined reports % devotees on it.', v_row.filled_slots;
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);

-- ---------------------------------------------------------------------------
-- 10. THE WHOLE ROSTER, ONE LAST TIME.
--
--     Every fixture and the status it must have been left in, so a change that
--     fixes one case by breaking another cannot pass.
-- ---------------------------------------------------------------------------

do $$
declare
  v_case record;
  v_status text;
begin
  for v_case in
    select * from (values
      -- 'full' rather than 'open' because 0019's capacity rule fills a
      -- one-place seva the moment its one devotee is on it.
      ('running',    'full'),      -- still going on; refused
      ('edge',       'full'),      -- one second short of the end; refused
      ('exactly',    'completed'), -- ended exactly now; allowed
      ('bound',      'completed'), -- one second past the end; allowed
      ('dialend',    'completed'), -- allowed once the grace went back to zero
      ('dialstart',  'full'),      -- 0068's dial held it shut and stayed held
      ('grace',      'completed'), -- a negative grace opened it early
      ('attend',     'full'),      -- attendance recorded, never completed
      ('buttonrun',  'full'),      -- the devotee's button, refused
      ('button',     'completed'), -- the devotee's button, allowed
      ('nojoin',     'open'),      -- nobody joined; refused at the door
      ('nojoinpre',  'open'),      -- nobody joined; put back
      ('humanempty', 'cancelled'), -- a person cancelled it, and it stayed
      ('allabsent',  'cancelled'), -- both marked
      ('partial',    'completed'), -- one of two served
      ('sweep',      'completed'), -- the hourly sweep still closes it
      -- Section 11's rows, untouched by everything above and asserted again
      -- after the mutations have run over them.
      ('mutempty',   'completed'),
      ('mutabs',     'completed')
    ) as expected(key, status)
  loop
    select instances.status into v_status
    from public.service_instances instances
    join public.cw_rows rows on rows.instance_id = instances.id
    where rows.key = v_case.key;
    if v_status is distinct from v_case.status then
      raise exception 'The "%" seva is % rather than %.', v_case.key, v_status, v_case.status;
    end if;
  end loop;

  -- Nothing here wrote a status outside 202608020002's vocabulary.
  if exists (
    select 1 from public.service_instances instances
    join public.cw_rows rows on rows.instance_id = instances.id
    where instances.status not in ('open', 'full', 'closed', 'cancelled', 'completed')
  ) then
    raise exception '0070 wrote a status the rest of the system does not read.';
  end if;

  -- And 0068's invariant survives: every row in the bookkeeping table is
  -- cancelled. The never-joined arm would have broken this if it had used it.
  if exists (
    select 1 from public.service_instances_unserved unserved
    join public.service_instances instances on instances.id = unserved.service_instance_id
    where instances.status <> 'cancelled'
  ) then
    raise exception
      'An instance recorded as closed-because-unserved is not cancelled; the bookkeeping and the status disagree.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 11. Every guard, mutated.
--
--     Each row below breaks exactly one thing 0070 relies on and re-reads one
--     answer through the real function. A guard whose mutation changes nothing
--     is a guard that was not doing anything, and the table says so out loud.
--
--     The mutation is undone by raising inside a plpgsql block, which is a
--     subtransaction; the probe is read a third time afterwards and must match
--     the first, or the harness itself is lying. cw_try rolls back whatever the
--     statement it runs would have written, in both readings, so a probe that
--     completes a seva does not leave one completed.
-- ---------------------------------------------------------------------------

create table public.cw_mutations (
  n integer primary key,
  guard text not null,
  mutation text not null,
  probe text not null,
  intact text not null,
  mutated text not null,
  killed boolean not null
);

-- Was it allowed, and what did it say if not — with whatever it would have
-- written rolled back, because every probe below is asked twice and must not be
-- the thing that changes the answer.
create function public.cw_try(p_sql text)
returns text
language plpgsql
as $$
begin
  begin
    execute p_sql;
    raise exception using errcode = 'PT770', message = 'allowed';
  exception
    when sqlstate 'PT770' then return 'allowed';
    when others then return 'refused: ' || left(sqlerrm, 60);
  end;
end;
$$;

-- What status does this instance settle on — again, rolled back, so the
-- reconciler can be asked the same question twice and answer it twice.
create function public.cw_settle(p_instance uuid)
returns text
language plpgsql
as $$
declare
  v_status text;
begin
  begin
    perform public.reconcile_service_instance_completion(p_instance);
    select instances.status into v_status
    from public.service_instances instances where instances.id = p_instance;
    raise exception using errcode = 'PT771', message = coalesce(v_status, '(gone)');
  exception when sqlstate 'PT771' then
    return sqlerrm;
  end;
end;
$$;

-- And after it settles, is it still where lapsedOpenRequests looks for it:
-- a one-off open request, not completed and not cancelled, whose hour has gone.
create function public.cw_settle_lapsed(p_instance uuid)
returns text
language plpgsql
as $$
declare
  v_answer text;
begin
  begin
    perform public.reconcile_service_instance_completion(p_instance);
    select case when exists (
      select 1 from public.service_instances instances
      where instances.id = p_instance
        and instances.template_id is null
        and instances.status not in ('completed', 'cancelled')
        and instances.participation_mode = 'open'
        and ((instances.date + instances.start_time) at time zone 'America/Chicago')
            + make_interval(mins => instances.duration_minutes) <= now()
    ) then 'in history' else 'vanished' end into v_answer;
    raise exception using errcode = 'PT772', message = v_answer;
  exception when sqlstate 'PT772' then
    return sqlerrm;
  end;
end;
$$;

create function public.cw_mutate(
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
    (select ids.id::text from public.cw_ids ids where ids.key = p_as), true);

  execute p_query into v_intact;

  begin
    execute p_apply;
    execute p_query into v_mutated;
    raise exception using errcode = 'PT667', message = coalesce(v_mutated, '(null)');
  exception when sqlstate 'PT667' then
    v_mutated := sqlerrm;
  end;

  execute p_query into v_restored;
  if v_restored is distinct from v_intact then
    raise exception
      'Mutation % did not roll back: the probe read % before and % after.',
      p_n, coalesce(v_intact, '(null)'), coalesce(v_restored, '(null)');
  end if;

  insert into public.cw_mutations (n, guard, mutation, probe, intact, mutated, killed)
  values (p_n, p_guard, p_mutation, p_probe,
          coalesce(v_intact, '(null)'), v_mutated,
          v_mutated is distinct from coalesce(v_intact, '(null)'));
end;
$$;

-- One more recurring slot, built here rather than in section 2 because section 6
-- runs the sweep and would have closed it. Same shape as 'sweep': its hour and
-- 0065's grace have both gone by, and nobody has spoken about its one place.
do $$
declare
  v_when timestamp := (now() at time zone 'America/Chicago') - interval '3 hours';
  v_type uuid;
  v_pres uuid := (select ids.id from public.cw_ids ids where ids.key = 'president');
  v_template uuid;
  v_inst uuid;
begin
  select service_types.id into v_type
  from public.service_types where service_types.name = 'Pot Washing';

  insert into public.service_templates (
    service_type_id, day_of_week, days_of_week, start_time, duration_minutes,
    slots_needed, participation_mode, start_date, created_by, active
  )
  select v_type, 0, array[0,1,2,3,4,5,6], v_when::time, 60, 4, 'open',
    v_when::date - 400, v_pres, true
  returning id into v_template;

  insert into public.service_instances (
    template_id, service_type_id, date, start_time, duration_minutes,
    slots_needed, participation_mode, posted_by, status
  ) values (
    v_template, v_type, v_when::date, v_when::time, 60, 4, 'open', null, 'open'
  ) returning id into v_inst;
  insert into public.cw_rows (key, instance_id) values ('mutsweep', v_inst);

  insert into public.service_assignments (
    service_instance_id, devotee_id, assignment_method, assigned_by,
    status, verification, attendance
  )
  select v_inst, ids.id, 'recurring_assignment', null, 'confirmed', 'self_report', null
  from public.cw_ids ids where ids.key = 'dsweep';

  if not exists (
    select 1 from public.due_recurring_service_instances where service_instance_id = v_inst
  ) then
    raise exception 'The fixture for mutation 14 is not due even before it is mutated.';
  end if;
end;
$$;

do $$
declare
  v_today date := (now() at time zone 'America/Chicago')::date;
  v_running uuid := (select rows.instance_id from public.cw_rows rows where rows.key = 'running');
  v_buttonrun uuid := (select rows.instance_id from public.cw_rows rows where rows.key = 'buttonrun');
  v_dialstart uuid := (select rows.instance_id from public.cw_rows rows where rows.key = 'dialstart');
  v_nojoin uuid := (select rows.instance_id from public.cw_rows rows where rows.key = 'nojoin');
  v_mutempty uuid := (select rows.instance_id from public.cw_rows rows where rows.key = 'mutempty');
  v_mutabs uuid := (select rows.instance_id from public.cw_rows rows where rows.key = 'mutabs');
  v_mutsweep uuid := (select rows.instance_id from public.cw_rows rows where rows.key = 'mutsweep');
  v_attend uuid := (select places.assignment_id from public.cw_places places where places.key = 'dattend');

  -- The start-only boundary 0068 shipped, which is the mutation for every guard
  -- that must now read the end.
  v_start_only text := $m$
    create or replace function public.seva_completion_opens_at(
      p_date date, p_start_time time, p_duration_minutes integer)
    returns timestamptz language sql stable security definer set search_path = ''
    as $body$
      select ((p_date + p_start_time) at time zone 'America/Chicago')
           + make_interval(mins => public.seva_completion_lead_minutes());
    $body$;
  $m$;

  -- Every probe is built in two steps — the statement, then the statement as a
  -- literal handed to cw_try — so that nothing has to nest a format() inside a
  -- format() and get the quoting wrong somewhere nobody would notice.
  v_complete_running text := format($q$select public.cw_try(%L)$q$,
    format($q$select public.complete_service_instance(%L)$q$, v_running));
  v_complete_buttonrun text := format($q$select public.cw_try(%L)$q$,
    format($q$select public.complete_my_service_assignment(%L)$q$, v_buttonrun));
  v_complete_dialstart text := format($q$select public.cw_try(%L)$q$,
    format($q$select public.complete_service_instance(%L)$q$, v_dialstart));
  v_complete_nojoin text := format($q$select public.cw_try(%L)$q$,
    format($q$select public.complete_service_instance(%L)$q$, v_nojoin));
  v_mark_attend text := format($q$select public.cw_try(%L)$q$,
    format($q$select public.record_seva_attendance(%L, 'absent')$q$, v_attend));
  v_verify_attend text := format($q$select public.cw_try(%L)$q$,
    format($q$select public.verify_seva_assignment(%L)$q$, v_attend));
  v_settle_empty text := format($q$select public.cw_settle(%L)$q$, v_mutempty);
  v_lapsed_empty text := format($q$select public.cw_settle_lapsed(%L)$q$, v_mutempty);
  v_settle_absent text := format($q$select public.cw_settle(%L)$q$, v_mutabs);
  v_bar_at_eight text := format(
    $q$select public.seva_completion_opens_at(%L, time '08:00', 30)::text$q$, v_today);
  v_read_grace text := $q$select public.cw_try('select public.seva_completion_end_grace_minutes()')$q$;
  v_sweep_due text := format(
    $q$select case when exists (
         select 1 from public.due_recurring_service_instances
         where service_instance_id = %L) then 'due' else 'waiting' end$q$, v_mutsweep);
begin
  -- ---- The bar itself. -------------------------------------------------
  perform public.cw_mutate(
    1, 'poster',
    'seva_completion_opens_at: the end-of-seva arm',
    'drop the end arm, leaving 0068''s start-only boundary',
    'the poster completes a seva that is fifteen minutes into its thirty',
    v_start_only, v_complete_running);

  perform public.cw_mutate(
    2, 'dbrun',
    'seva_completion_opens_at: the end arm, on the devotee''s button',
    'drop the end arm, leaving 0068''s start-only boundary',
    'the devotee closes their own place on a running seva',
    v_start_only, v_complete_buttonrun);

  perform public.cw_mutate(
    3, 'poster',
    'complete_service_instance: reads the three-argument bar',
    'call the two-argument floor instead, ignoring how long the seva is',
    'the poster completes a running seva',
    $m$
      create or replace function public.complete_service_instance(p_instance_id uuid)
      returns void language plpgsql security definer set search_path = ''
      as $body$
      declare instance_record public.service_instances;
      begin
        select * into instance_record from public.service_instances
        where id = p_instance_id for update;
        if instance_record.id is null then
          raise exception 'This seva request could not be found.';
        end if;
        if instance_record.posted_by is distinct from auth.uid()
          and not public.has_permission('app.view_all') then
          raise exception 'Only the devotee who posted this seva request, a Tech Admin, or the President can mark it completed.';
        end if;
        if public.seva_completion_opens_at(
             instance_record.date, instance_record.start_time) > now() then
          raise exception 'This seva has not finished yet. You can mark it completed once its time on % has passed.',
            public.format_seva_when(instance_record.date, instance_record.start_time);
        end if;
        if not public.complete_service_instance_internal(p_instance_id, auth.uid(), false) then
          raise exception 'This seva can no longer be completed.';
        end if;
      end;
      $body$;
    $m$,
    v_complete_running);

  -- ---- The floor, which is 0068's dial kept alive. ----------------------
  update public.app_settings set value = '240' where key = 'seva.complete_after_start_minutes';
  perform public.cw_mutate(
    4, 'poster',
    'seva_completion_opens_at: the start-side floor',
    'drop the floor, so seva.complete_after_start_minutes is orphaned',
    'with the old dial at four hours, the poster completes a seva that ended an hour ago',
    $m$
      create or replace function public.seva_completion_opens_at(
        p_date date, p_start_time time, p_duration_minutes integer)
      returns timestamptz language sql stable security definer set search_path = ''
      as $body$
        select ((p_date + p_start_time) at time zone 'America/Chicago')
             + make_interval(mins => coalesce(p_duration_minutes, 0))
             + make_interval(mins => public.seva_completion_end_grace_minutes());
      $body$;
    $m$,
    v_complete_dialstart);
  update public.app_settings set value = '0' where key = 'seva.complete_after_start_minutes';

  -- ---- The dials' own guards. ------------------------------------------
  update public.app_settings set value = '-1440' where key = 'seva.complete_after_end_minutes';
  perform public.cw_mutate(
    5, 'poster',
    'seva_completion_opens_at: greatest(), which stops a grace reaching behind the start',
    'take the later-of-two away and return the end arm alone',
    'the bar for an 08:00 seva with the grace wound back a whole day',
    $m$
      create or replace function public.seva_completion_opens_at(
        p_date date, p_start_time time, p_duration_minutes integer)
      returns timestamptz language sql stable security definer set search_path = ''
      as $body$
        select ((p_date + p_start_time) at time zone 'America/Chicago')
             + make_interval(mins => coalesce(p_duration_minutes, 0))
             + make_interval(mins => public.seva_completion_end_grace_minutes());
      $body$;
    $m$,
    v_bar_at_eight);
  update public.app_settings set value = '0' where key = 'seva.complete_after_end_minutes';

  update public.app_settings set value = '99999' where key = 'seva.complete_after_end_minutes';
  perform public.cw_mutate(
    6, 'poster',
    'seva_completion_end_grace_minutes: the range check',
    'accept any integer at all',
    'the dial read back with 99999 in it',
    $m$
      create or replace function public.seva_completion_end_grace_minutes()
      returns integer language plpgsql stable security definer set search_path = ''
      as $body$
      begin
        return coalesce(nullif(trim(public.app_setting('seva.complete_after_end_minutes')), ''), '0')::integer;
      end;
      $body$;
    $m$,
    v_read_grace);
  update public.app_settings set value = '0' where key = 'seva.complete_after_end_minutes';

  update public.app_settings set value = 'forty' where key = 'seva.complete_after_end_minutes';
  perform public.cw_mutate(
    7, 'poster',
    'seva_completion_end_grace_minutes: nonsense raises rather than reverting',
    'fall back to the default when the value will not parse',
    'the dial read back with "forty" in it',
    $m$
      create or replace function public.seva_completion_end_grace_minutes()
      returns integer language plpgsql stable security definer set search_path = ''
      as $body$
      declare v_minutes integer;
      begin
        begin
          v_minutes := coalesce(nullif(trim(public.app_setting('seva.complete_after_end_minutes')), ''), '0')::integer;
        exception when others then v_minutes := 0;
        end;
        return v_minutes;
      end;
      $body$;
    $m$,
    v_read_grace);
  update public.app_settings set value = '0' where key = 'seva.complete_after_end_minutes';

  -- ---- The seva nobody joined. -----------------------------------------
  perform public.cw_mutate(
    8, 'poster',
    'complete_service_instance: the refusal for a seva nobody joined',
    'drop the roster check and close it anyway',
    'the poster completes a passed request nobody ever took up',
    $m$
      create or replace function public.complete_service_instance(p_instance_id uuid)
      returns void language plpgsql security definer set search_path = ''
      as $body$
      declare instance_record public.service_instances;
      begin
        select * into instance_record from public.service_instances
        where id = p_instance_id for update;
        if instance_record.id is null then
          raise exception 'This seva request could not be found.';
        end if;
        if instance_record.posted_by is distinct from auth.uid()
          and not public.has_permission('app.view_all') then
          raise exception 'Only the devotee who posted this seva request, a Tech Admin, or the President can mark it completed.';
        end if;
        if public.seva_completion_opens_at(instance_record.date, instance_record.start_time,
             instance_record.duration_minutes) > now() then
          raise exception 'This seva has not finished yet. You can mark it completed once its time on % has passed.',
            public.format_seva_when(instance_record.date, instance_record.start_time);
        end if;
        if not public.complete_service_instance_internal(p_instance_id, auth.uid(), false) then
          raise exception 'This seva can no longer be completed.';
        end if;
      end;
      $body$;
    $m$,
    v_complete_nojoin);

  perform public.cw_mutate(
    9, 'poster',
    'reconcile_service_instance_completion: the never-joined arm',
    'return early on an instance with no places, which is 0068''s body',
    'the status a forged completed-with-nobody-on-it seva settles on',
    $m$
      create or replace function public.reconcile_service_instance_completion(p_instance_id uuid)
      returns text language plpgsql security definer set search_path = ''
      as $body$
      declare v_status text; v_places integer; v_served boolean;
      begin
        select instances.status into v_status from public.service_instances instances
        where instances.id = p_instance_id for update;
        if v_status is null or v_status not in ('completed', 'cancelled') then
          return v_status;
        end if;
        select count(*) into v_places from public.service_assignments
        where service_instance_id = p_instance_id;
        if v_places = 0 then return v_status; end if;
        v_served := public.service_instance_has_server(p_instance_id);
        if v_status = 'completed' and not v_served then
          update public.service_instances set status = 'cancelled' where id = p_instance_id;
          insert into public.service_instances_unserved (service_instance_id)
          values (p_instance_id) on conflict (service_instance_id) do nothing;
          return 'cancelled';
        end if;
        return v_status;
      end;
      $body$;
    $m$,
    v_settle_empty);

  perform public.cw_mutate(
    10, 'poster',
    'reconcile_service_instance_completion: the never-joined arm does not cancel',
    'cancel the empty instance instead of putting it back',
    'whether the unclaimed request is still where lapsedOpenRequests looks for it',
    $m$
      create or replace function public.reconcile_service_instance_completion(p_instance_id uuid)
      returns text language plpgsql security definer set search_path = ''
      as $body$
      declare v_status text; v_places integer;
      begin
        select instances.status into v_status from public.service_instances instances
        where instances.id = p_instance_id for update;
        if v_status is null or v_status not in ('completed', 'cancelled') then
          return v_status;
        end if;
        select count(*) into v_places from public.service_assignments
        where service_instance_id = p_instance_id;
        if v_places = 0 then
          if v_status = 'completed' then
            update public.service_instances set status = 'cancelled' where id = p_instance_id;
            return 'cancelled';
          end if;
          return v_status;
        end if;
        return v_status;
      end;
      $body$;
    $m$,
    v_lapsed_empty);

  -- ---- 0068's rule, which this file must not have loosened. -------------
  perform public.cw_mutate(
    11, 'poster',
    'reconcile_service_instance_completion: the all-absent arm',
    'settle every instance that has places as completed',
    'the status of a seva both of whose devotees were marked absent',
    $m$
      create or replace function public.reconcile_service_instance_completion(p_instance_id uuid)
      returns text language plpgsql security definer set search_path = ''
      as $body$
      declare v_status text;
      begin
        select instances.status into v_status from public.service_instances instances
        where instances.id = p_instance_id for update;
        return v_status;
      end;
      $body$;
    $m$,
    v_settle_absent);

  -- ---- The two gates that did not move. ---------------------------------
  perform public.cw_mutate(
    12, 'poster',
    'record_seva_attendance: opens at the START',
    'move it to the completion bar, as a tidy-up of all the clock gates would',
    'the coordinator records attendance on a seva that is running now',
    $m$
      create or replace function public.record_seva_attendance(
        p_assignment_id uuid, p_attendance text)
      returns public.service_assignments language plpgsql security definer set search_path = ''
      as $body$
      declare
        assignment_record public.service_assignments;
        instance_record public.service_instances;
        updated_assignment public.service_assignments;
      begin
        select * into assignment_record from public.service_assignments
        where id = p_assignment_id for update;
        select * into instance_record from public.service_instances
        where id = assignment_record.service_instance_id;
        if instance_record.posted_by is distinct from auth.uid()
          and not public.has_permission('app.view_all') then
          raise exception 'Only the devotee who posted this seva, a Tech Admin, or the President can record attendance.';
        end if;
        if public.seva_completion_opens_at(instance_record.date, instance_record.start_time,
             instance_record.duration_minutes) > now() then
          raise exception 'Attendance can be recorded once the seva has started.';
        end if;
        update public.service_assignments set attendance = p_attendance
        where id = p_assignment_id returning * into updated_assignment;
        perform public.reconcile_service_instance_completion(instance_record.id);
        return updated_assignment;
      end;
      $body$;
    $m$,
    v_mark_attend);

  perform public.cw_mutate(
    13, 'poster',
    'verify_seva_assignment: opens at the START',
    'move it to the completion bar',
    'the coordinator verifies a devotee on a seva that is running now',
    $m$
      create or replace function public.verify_seva_assignment(p_assignment_id uuid)
      returns public.service_assignments language plpgsql security definer set search_path = ''
      as $body$
      declare
        v_assignment public.service_assignments;
        v_instance public.service_instances;
        v_updated public.service_assignments;
      begin
        select * into v_assignment from public.service_assignments
        where service_assignments.id = p_assignment_id for update;
        select * into v_instance from public.service_instances
        where service_instances.id = v_assignment.service_instance_id;
        if v_instance.posted_by is distinct from auth.uid()
          and not public.has_permission('app.view_all') then
          raise exception 'Only the devotee who posted this seva, a Tech Admin, or the President can verify it.';
        end if;
        if public.seva_completion_opens_at(v_instance.date, v_instance.start_time,
             v_instance.duration_minutes) > now() then
          raise exception 'A seva can be verified once it has started.';
        end if;
        update public.service_assignments set verification = 'member_verified'
        where id = p_assignment_id returning * into v_updated;
        return v_updated;
      end;
      $body$;
    $m$,
    v_verify_attend);

  -- ---- The sweep and the button, made to agree. -------------------------
  update public.app_settings set value = '180' where key = 'seva.complete_after_end_minutes';
  perform public.cw_mutate(
    14, 'poster',
    'due_recurring_service_instances: due_at is the later of the two bars',
    'put 0065''s own grace back on its own, so the clock can beat the button',
    'whether a weekly slot is due while a President would still be refused',
    $m$
      create or replace view public.due_recurring_service_instances as
        select
          instances.id as service_instance_id,
          instances.template_id,
          instances.date,
          instances.start_time,
          instances.duration_minutes,
          ((instances.date + instances.start_time) at time zone 'America/Chicago')
            + make_interval(mins => instances.duration_minutes) as ends_at,
          ((instances.date + instances.start_time) at time zone 'America/Chicago')
            + make_interval(mins => instances.duration_minutes)
            + make_interval(mins => (coalesce(nullif(trim(
                public.app_setting('seva.auto_complete_grace_minutes')), ''), '60')::integer)) as due_at
        from public.service_instances instances
        where instances.template_id is not null
          and instances.status not in ('completed', 'cancelled')
          and ((instances.date + instances.start_time) at time zone 'America/Chicago')
              + make_interval(mins => instances.duration_minutes)
              + make_interval(mins => (coalesce(nullif(trim(
                  public.app_setting('seva.auto_complete_grace_minutes')), ''), '60')::integer)) <= now()
          and exists (
            select 1 from public.service_assignments assignments
            where assignments.service_instance_id = instances.id
              and assignments.status in ('assigned', 'confirmed')
              and assignments.attendance is null);
    $m$,
    v_sweep_due);
  update public.app_settings set value = '0' where key = 'seva.complete_after_end_minutes';
end;
$$;

-- The harness itself, checked: every probe above rolled back, so the two rows
-- section 11 was given are exactly as they were forged and nothing it touched
-- was left behind.
do $$
begin
  if exists (
    select 1 from public.service_instances instances
    join public.cw_rows rows on rows.instance_id = instances.id
    where rows.key in ('mutempty', 'mutabs') and instances.status <> 'completed'
  ) then
    raise exception 'A mutation probe left one of section 11''s rows settled; the harness is lying.';
  end if;
  if exists (
    select 1 from public.service_instances_unserved unserved
    join public.cw_rows rows on rows.instance_id = unserved.service_instance_id
    where rows.key in ('mutempty', 'mutabs', 'mutsweep')
  ) then
    raise exception 'A mutation probe left a bookkeeping row behind.';
  end if;
  if not exists (
    select 1 from public.service_assignments assignments
    join public.cw_places places on places.assignment_id = assignments.id
    where places.key = 'dattend' and assignments.attendance = 'served'
  ) then
    raise exception 'A mutation probe left an attendance mark behind.';
  end if;
end;
$$;

select set_config('request.jwt.claim.sub', '', true);

do $$
declare
  v_survivors text;
begin
  if (select count(*) from public.cw_mutations) <> 14 then
    raise exception 'Only % mutations ran.', (select count(*) from public.cw_mutations);
  end if;

  select string_agg(cw_mutations.n || ': ' || cw_mutations.guard, E'\n  ')
  into v_survivors
  from public.cw_mutations where not cw_mutations.killed;
  if v_survivors is not null then
    raise exception
      E'These guards changed nothing when they were broken:\n  %', v_survivors;
  end if;
end;
$$;

select
  cw_mutations.n,
  cw_mutations.guard,
  cw_mutations.mutation,
  cw_mutations.probe,
  cw_mutations.intact,
  cw_mutations.mutated,
  case when cw_mutations.killed then 'killed' else 'SURVIVED' end as verdict
from public.cw_mutations
order by cw_mutations.n;

do $$
begin
  raise notice 'all completion window checks passed';
end;
$$;

select 'completion window verification passed' as result;

rollback;
