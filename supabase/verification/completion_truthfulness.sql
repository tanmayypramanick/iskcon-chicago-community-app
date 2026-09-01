-- Functional verification for 202608040068_completion_truthfulness.sql.
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
-- The temple said three sentences and 0068 answers all three. Each is a claim
-- that can be wrong in a different direction, and this file exists to break
-- every one of them:
--
--   1. AN ABSENT DEVOTEE AND AN EXCUSED ONE EARN NOTHING. Asserted on
--      seva_points_status itself for both marks and both overloads, and then
--      asserted again on real rows: the devotee marked absent on a seva that
--      DID complete carries quality 0 and credited_minutes 0 in seva_mala_acts,
--      reads 'not_served' in their own my_seva_acts, and no other function in
--      the schema turns a place into minutes without asking seva_points_status
--      first.
--
--   2. A SEVA WHOSE TIME HAS NOT PASSED CANNOT BE COMPLETED, AND ONE WHOSE
--      TIME HAS CAN. Both buttons — the poster's complete_service_instance and
--      the devotee's complete_my_service_assignment — and the boundary tested
--      from BOTH sides, one second either way. Authority is not a bypass: the
--      President is refused on the same seva as everybody else. And the
--      boundary is a dial: moving seva.complete_after_start_minutes moves both
--      buttons together, and a nonsense value raises rather than quietly
--      reverting to permissive.
--
--      WHICH MOMENT THAT IS MOVED IN 202608040070, AND THIS FILE MOVED WITH IT.
--      0068 put the bar at the START and argued for it at length; the temple's
--      sentence is "after the seva has been done and the time has passed", and
--      a seva that is fifteen minutes into its hour has not been done. 0070
--      puts the bar at the END, keeps seva.complete_after_start_minutes as a
--      floor under it, and adds seva.complete_after_end_minutes for the grace
--      either side. So the fixtures below are hung off each seva's END rather
--      than its start, the refusal a running seva gets says it has not FINISHED
--      rather than that it has not started, and the boundary this file still
--      proves from both sides is the one every button now reads.
--      seva_completion_opens_at(date, time) — the two-argument form, which is
--      all 0068 had — is the start-side floor now, and every assertion below
--      that reads it is asking about the floor on purpose. The end of the seva
--      belongs to 202608040070 and to supabase/verification/completion_window.sql.
--
--   3. A SEVA WHERE EVERY LIVE PLACE IS ABSENT OR EXCUSED DOES NOT READ AS
--      COMPLETED. The sole-devotee case, in both marks; the all-absent-of-three
--      case, one mark at a time, so that it is the LAST one that tips it; and
--      the same thing arriving through the devotee's own button rather than the
--      poster's. Silence is never absence.
--
--      A SEVA WITH NO PLACES AT ALL WAS "LEFT ALONE" HERE AND IS NOT ANY MORE.
--      0068 returned early on an instance nobody had ever joined, so a poster
--      could close an unclaimed request and the app would report service that
--      certainly did not happen — and this file asserted that it would.
--      202608040070 refuses that completion at the door and puts a row that is
--      already wrong back to being an unclaimed request, which is where
--      lapsedOpenRequests looks for it. Section 7 below now proves the refusal;
--      what happens to the row afterwards is proved in
--      supabase/verification/completion_window.sql.
--
--   4. PARTIAL ABSENCE STILL COMPLETES, AND ONLY THE DEVOTEE WHO SERVED IS
--      CREDITED. Two on the roster, one absent: the seva stays in the completed
--      list, one of them earns, the other earns nothing.
--
--   5. 202608040065'S HOURLY SWEEP OBEYS ALL OF THE ABOVE, and so does
--      202608040020's settle_finished_verified_seva, which nobody presses. The
--      sweep is not a second dialect of 'completed'.
--
-- And, over the top of all five: the settlement is REVERSIBLE and it is
-- reversible in one direction only. Correcting an attendance mark puts the seva
-- and the devotee's points back. A seva a PERSON cancelled is never promoted to
-- completed by anything here, however much attendance is later recorded against
-- it — which is the whole reason public.service_instances_unserved exists, and
-- is the one guard whose absence would be this file undoing a human decision.
--
-- ---------------------------------------------------------------------------
-- The terminal state, said once so nothing below has to guess.
--
-- A seva nobody served ends at status = 'cancelled', with a row in
-- public.service_instances_unserved recording that THIS RULE closed it rather
-- than a person. It is not 'completed' and it is not a fourth status: 0068 adds
-- nothing to 202608020002's vocabulary. So a client asking "did this happen"
-- reads service_instances.status and finds 'cancelled', exactly as it would for
-- a seva a coordinator cancelled by hand; and a client asking "which seva
-- disappeared because nobody served it" calls list_seva_closed_unserved, which
-- is the only reader that can tell the two apart. Both are asserted below.
--
-- ---------------------------------------------------------------------------
-- Every instant in this file is derived from the Chicago clock, never written
-- as a literal hour, so the suite passes at 2am and at 2pm alike. The boundary
-- cases are one SECOND either side of now and are still not races, because
-- now() is the transaction's timestamp and this whole file is one transaction:
-- the instant the fixture is built from is the same instant the guard compares
-- against, however long the script takes to run.
--
-- ---------------------------------------------------------------------------
-- The fixture. Twenty-two devotees and sixteen seva, each of which exists to be
-- exactly one row of the table below.
--
-- Every seva here runs sixty minutes, and the five that exist to test the clock
-- are placed by where their END falls rather than their start, because
-- 202608040070 is what the buttons read.
--
--   key          when              places                          proves
--   -------------------------------------------------------------------------
--   future       now + 3 hours     d_future confirmed              sentence 3
--   edge         ends in 1 second  d_edge confirmed                sentence 3
--   exactly      ends exactly now  d_exact confirmed               sentence 3
--   bound        ended 1 second
--                ago               d_bound confirmed               sentence 3
--   dial         started 75 min
--                ago, ended 15     d_dial confirmed                the dial
--   sole         now - 3 hours     d_sole confirmed                sentence 2
--   soleexc      now - 3 hours     d_soleexc confirmed             sentence 2
--   partial      now - 3 hours     d_serve + d_abs confirmed       sentence 2/1
--   allabsent    now - 3 hours     d_a1 + d_a2 + d_a3 confirmed    sentence 2
--   allbutton    now - 3 hours     d_b1 + d_b2 confirmed           sentence 2
--   silent       now - 3 hours     d_silent confirmed              silence
--   noplaces     now - 3 hours     nobody at all                   refused (0070)
--   humancancel  now - 3 hours     d_hc confirmed                  never reopened
--   sweepone     recurring, - 3h   d_sweep confirmed, silent       the sweep
--   sweepfuture  recurring, + 3h   d_sweepf confirmed              the sweep
--   settle       now - 3h, closed  d_settle confirmed + absent     the reconciler
--
-- The final row must read: completion truthfulness verification passed

begin;

-- ---------------------------------------------------------------------------
-- 0. The ground.
--
--    What 0068 added, that it added nothing a client can reach, and that the
--    sentence the whole file rests on is still true in seva_points_status.
-- ---------------------------------------------------------------------------

do $$
declare
  v_offenders text;
begin
  if to_regprocedure('public.seva_completion_lead_minutes()') is null
    or to_regprocedure('public.seva_completion_opens_at(date, time)') is null
    or to_regprocedure('public.service_instance_has_server(uuid)') is null
    or to_regprocedure('public.reconcile_service_instance_completion(uuid)') is null
    or to_regprocedure('public.list_seva_closed_unserved(date, date)') is null
    or to_regclass('public.service_instances_unserved') is null
  then
    raise exception '202608040068 is not applied.';
  end if;

  -- One of each. A leftover overload of the reconciler with a defaulted
  -- argument would be ambiguous rather than merely stale.
  for v_offenders in
    select proc.proname
    from pg_proc proc
    join pg_namespace spaces on spaces.oid = proc.pronamespace
    where spaces.nspname = 'public'
      and proc.proname in (
        'reconcile_service_instance_completion', 'service_instance_has_server',
        'seva_completion_lead_minutes',
        'complete_service_instance', 'complete_my_service_assignment')
    group by proc.proname
    having count(*) <> 1
  loop
    raise exception '% has more than one overload.', v_offenders;
  end loop;

  -- THE BOUNDARY IS THE ONE EXCEPTION, AND IT IS EXACTLY TWO FORMS.
  -- 0068 wrote here that "an overload of the boundary would let two callers
  -- read two different clocks", and that is still the thing being guarded
  -- against: 202608040070 added seva_completion_opens_at(date, time, integer),
  -- which is the bar, and left the two-argument form as that same function
  -- asked about a seva of no length — the start-side floor, which is what the
  -- callers of it in this file and in seva_permutations were really asking for.
  -- One clock, two names for two different questions about it. A THIRD form
  -- would be the drift 0068 was worried about, and so would the disappearance
  -- of either of these two.
  if (select count(*) from pg_proc proc
      join pg_namespace spaces on spaces.oid = proc.pronamespace
      where spaces.nspname = 'public' and proc.proname = 'seva_completion_opens_at') <> 2
  then
    raise exception
      'public.seva_completion_opens_at is not the two forms 202608040070 settles on: the bar and the floor.';
  end if;
  if public.seva_completion_opens_at(
       (now() at time zone 'America/Chicago')::date, time '08:00')
     <> public.seva_completion_opens_at(
       (now() at time zone 'America/Chicago')::date, time '08:00', 0)
  then
    raise exception 'The two forms of the boundary are two clocks rather than one.';
  end if;

  -- SENTENCE 1, on the function itself, both overloads and both marks. If this
  -- has moved, "nobody served this" below means something other than what the
  -- temple said.
  if public.seva_points_status('completed', 'absent', 'member_verified') <> 'not_served'
    or public.seva_points_status('completed', 'excused', 'member_verified') <> 'not_served'
    or public.seva_points_status('completed', 'absent', 'member_verified', true) <> 'not_served'
    or public.seva_points_status('completed', 'excused', 'member_verified', true) <> 'not_served'
    or public.seva_points_status('completed', 'absent', 'member_verified', false) <> 'not_served'
    or public.seva_points_status('completed', 'excused', 'member_verified', false) <> 'not_served'
  then
    raise exception 'An absent or excused devotee no longer reads as not_served.';
  end if;

  -- The strongest form of it: absent and excused are refused under EVERY
  -- combination of the other three columns, so no verification and no status
  -- can buy a devotee out of the mark.
  if exists (
    select 1
    from unnest(array['assigned', 'confirmed', 'completed', 'no_show', 'withdrawn']) as s(status)
    cross join unnest(array['absent', 'excused']) as a(attendance)
    cross join unnest(array['self_report', 'live_timer', 'qr_scan', 'member_verified']) as v(verification)
    cross join unnest(array[true, false]) as r(recurring)
    where public.seva_points_status(s.status, a.attendance, v.verification, r.recurring)
          <> 'not_served'
  ) then
    raise exception
      'Some combination of status and verification lets an absent or excused devotee count.';
  end if;

  -- And the other half of sentence 2's definition, which is 0057's and 0059's:
  -- a place nobody has spoken about is service, not absence.
  if public.seva_points_status('completed', null, 'self_report', true) <> 'counted'
    or public.seva_points_status('completed', null, 'self_report', false) <> 'awaiting_verification'
  then
    raise exception 'A completed place with no attendance mark no longer reads as service.';
  end if;

  -- SENTENCE 1 FROM THE OTHER SIDE: no path credits a devotee except through
  -- seva_points_status. This is the migration's own section 0 check, asserted
  -- again here so it fails in the suite and not only on a fresh apply.
  select string_agg(proc.proname, ', ' order by proc.proname) into v_offenders
  from pg_proc proc
  join pg_namespace spaces on spaces.oid = proc.pronamespace
  where spaces.nspname = 'public'
    and proc.proname in (
      'seva_mala_acts', 'seva_balance_acts', 'seva_mala_served',
      'seva_mala_window_points', 'list_all_seva_hours', 'my_seva_acts',
      'my_seva_breakdown')
    and pg_get_functiondef(proc.oid) !~* '(seva_points_status|seva_mala_acts|points_status)';
  if v_offenders is not null then
    raise exception
      '% counts seva without asking seva_points_status, so an absent devotee could be credited there.',
      v_offenders;
  end if;
end;
$$;

-- The bookkeeping table is backend-only, and the reconciler is not a button.
do $$
begin
  if has_table_privilege('authenticated', 'public.service_instances_unserved', 'select')
    or has_table_privilege('authenticated', 'public.service_instances_unserved', 'insert')
    or has_table_privilege('anon', 'public.service_instances_unserved', 'select')
  then
    raise exception 'A client role can read or write service_instances_unserved.';
  end if;
  if not (select relrowsecurity from pg_class
          where oid = 'public.service_instances_unserved'::regclass) then
    raise exception 'Row level security is off on service_instances_unserved.';
  end if;
  if exists (select 1 from pg_policy
             where polrelid = 'public.service_instances_unserved'::regclass) then
    raise exception
      'service_instances_unserved has a policy; it is meant to be reachable by nothing but a definer function.';
  end if;

  if has_function_privilege('authenticated',
       'public.reconcile_service_instance_completion(uuid)', 'execute')
    or has_function_privilege('authenticated',
       'public.complete_service_instance_internal(uuid, uuid, boolean)', 'execute')
  then
    raise exception 'A devotee can settle or close a seva without going through the front door.';
  end if;

  -- And the two the client legitimately needs are open to a signed-in devotee
  -- and to nobody else.
  if not has_function_privilege('authenticated', 'public.seva_completion_opens_at(date, time)', 'execute')
    or not has_function_privilege('authenticated', 'public.service_instance_has_server(uuid)', 'execute')
    or not has_function_privilege('authenticated', 'public.list_seva_closed_unserved(date, date)', 'execute')
  then
    raise exception 'A signed-in devotee cannot ask when a seva may be completed.';
  end if;
  if has_function_privilege('anon', 'public.seva_completion_opens_at(date, time)', 'execute')
    or has_function_privilege('anon', 'public.list_seva_closed_unserved(date, date)', 'execute')
  then
    raise exception 'anon can reach 0068''s reads.';
  end if;
end;
$$;

-- The guards themselves, in the bodies that must carry them. A later
-- `create or replace` that drops one of these is the single most likely way for
-- the temple's complaint to come back without anybody noticing.
do $$
declare
  v_case record;
begin
  for v_case in
    select * from (values
      ('public.complete_service_instance(uuid)', 'seva_completion_opens_at',
       'the poster''s button has lost its clock'),
      ('public.complete_my_service_assignment(uuid)', 'seva_completion_opens_at',
       'the devotee''s own button has lost its clock'),
      ('public.complete_service_instance_internal(uuid, uuid, boolean)',
       'reconcile_service_instance_completion',
       'the shared body no longer asks whether anybody served the seva, so the hourly sweep does not either'),
      ('public.record_seva_attendance(uuid, text)', 'reconcile_service_instance_completion',
       'marking the last server absent no longer takes the seva out of the completed list'),
      ('public.settle_finished_verified_seva()', 'reconcile_service_instance_completion',
       'the fourth writer of completed no longer settles what it wrote'),
      ('public.service_instance_has_server(uuid)', 'seva_points_status',
       '"nobody served this" is decided somewhere other than the scoring rule'),
      -- The three-argument form, because 202608040070 made the two-argument one
      -- a call to it: the Chicago arithmetic lives in the bar now, and asking
      -- the floor for it would pass on a body that had lost it.
      ('public.seva_completion_opens_at(date, time, integer)', 'America/Chicago',
       'the completion boundary is no longer read in the temple''s time zone')
    ) as expected(target, needle, complaint)
  loop
    if pg_get_functiondef(v_case.target::regprocedure) !~* v_case.needle then
      raise exception '% (% no longer mentions %).', v_case.complaint, v_case.target, v_case.needle;
    end if;
  end loop;

  -- And the sweep's own selection still excludes what 0068 closes, or a seva
  -- taken out of the completed list would be put back on the hour.
  if pg_get_viewdef('public.due_recurring_service_instances'::regclass) !~* 'cancelled' then
    raise exception 'due_recurring_service_instances no longer excludes cancelled instances.';
  end if;
end;
$$;

-- THE CLOCK IS ASKED BEFORE THE WRITE, not after it, and that is asserted on
-- the source rather than on behaviour because behaviour cannot see it: a guard
-- that closes the seva and THEN raises looks identical from outside, since the
-- raise rolls the write back with it. It is a real defect all the same — the
-- refusal is only free of side effects for as long as nobody catches it — and
-- the position of the two names in the body is the only place it shows.
do $$
declare
  v_source text;
begin
  v_source := pg_get_functiondef('public.complete_service_instance(uuid)'::regprocedure);
  if position('seva_completion_opens_at' in v_source) = 0
    or position('complete_service_instance_internal' in v_source) = 0
    or position('seva_completion_opens_at' in v_source)
       > position('complete_service_instance_internal' in v_source)
  then
    raise exception
      'complete_service_instance closes the seva before it asks whether the seva has started.';
  end if;

  -- 202608040023's authority rule is still asked first of all, so a devotee
  -- with no standing learns nothing about the temple's schedule from a refusal.
  if position('has_permission' in v_source) = 0
    or position('has_permission' in v_source) > position('seva_completion_opens_at' in v_source)
  then
    raise exception
      'complete_service_instance asks the clock before it asks who is pressing the button.';
  end if;

  -- The same for the devotee's own button: the clock before the UPDATE that
  -- closes their place.
  v_source := pg_get_functiondef('public.complete_my_service_assignment(uuid)'::regprocedure);
  if position('seva_completion_opens_at' in v_source) = 0
    or position('seva_completion_opens_at' in v_source)
       > position('update public.service_assignments' in v_source)
  then
    raise exception
      'complete_my_service_assignment closes the devotee''s place before it asks whether the seva has started.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 1. The dial and the boundary, before any seva exists to be judged by them.
-- ---------------------------------------------------------------------------

do $$
declare
  v_today date := (now() at time zone 'America/Chicago')::date;
begin
  if public.seva_completion_lead_minutes() <> 0 then
    raise exception
      'seva.complete_after_start_minutes ships at % rather than 0, so the default bar is not record_seva_attendance''s bar.',
      public.seva_completion_lead_minutes();
  end if;

  -- At zero the boundary IS the start, to the microsecond, in Chicago.
  if public.seva_completion_opens_at(v_today, time '08:00')
     <> ((v_today + time '08:00') at time zone 'America/Chicago') then
    raise exception 'At the default the boundary is not the seva''s own Chicago start.';
  end if;

  -- Chicago and only Chicago. Asked from four session timezones, because a
  -- boundary read in the SESSION's zone would open a Chicago morning seva
  -- half a day early for a devotee reading the app in Mayapur.
  perform set_config('timezone', 'UTC', true);
  if public.seva_completion_opens_at(v_today, time '08:00')
     <> ((v_today + time '08:00') at time zone 'America/Chicago') then
    raise exception 'The completion boundary moved when the session timezone did (UTC).';
  end if;
  perform set_config('timezone', 'Asia/Kolkata', true);
  if public.seva_completion_opens_at(v_today, time '08:00')
     <> ((v_today + time '08:00') at time zone 'America/Chicago') then
    raise exception 'The completion boundary moved when the session timezone did (Asia/Kolkata).';
  end if;
  perform set_config('timezone', 'Pacific/Auckland', true);
  if public.seva_completion_opens_at(v_today, time '08:00')
     <> ((v_today + time '08:00') at time zone 'America/Chicago') then
    raise exception 'The completion boundary moved when the session timezone did (Pacific/Auckland).';
  end if;
  perform set_config('timezone', 'America/Chicago', true);
end;
$$;

-- The dial moves the boundary, and a value that is not a whole number of
-- minutes raises rather than falling back to permissive. 0055's rule for a dial
-- read on a button a devotee presses.
do $$
declare
  v_today date := (now() at time zone 'America/Chicago')::date;
  v_raised boolean;
begin
  update public.app_settings set value = '90' where key = 'seva.complete_after_start_minutes';
  if public.seva_completion_lead_minutes() <> 90 then
    raise exception 'The dial was set to 90 and reads %.', public.seva_completion_lead_minutes();
  end if;
  if public.seva_completion_opens_at(v_today, time '08:00')
     <> ((v_today + time '08:00') at time zone 'America/Chicago') + interval '90 minutes' then
    raise exception 'The dial does not move the boundary it is the dial for.';
  end if;

  update public.app_settings set value = 'ninety' where key = 'seva.complete_after_start_minutes';
  v_raised := false;
  begin
    perform public.seva_completion_lead_minutes();
  exception when others then v_raised := true;
  end;
  if not v_raised then
    raise exception 'A dial reading "ninety" was accepted rather than raising.';
  end if;

  update public.app_settings set value = '-1' where key = 'seva.complete_after_start_minutes';
  v_raised := false;
  begin
    perform public.seva_completion_lead_minutes();
  exception when others then v_raised := true;
  end;
  if not v_raised then
    raise exception 'A negative dial was accepted, so the bar could be set BEFORE the seva starts.';
  end if;

  update public.app_settings set value = '1441' where key = 'seva.complete_after_start_minutes';
  v_raised := false;
  begin
    perform public.seva_completion_lead_minutes();
  exception when others then v_raised := true;
  end;
  if not v_raised then
    raise exception 'A dial beyond a day was accepted.';
  end if;

  update public.app_settings set value = '0' where key = 'seva.complete_after_start_minutes';
  if public.seva_completion_lead_minutes() <> 0 then
    raise exception 'The dial did not go back to its default.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. The congregation.
-- ---------------------------------------------------------------------------

do $$
declare
  v_who text;
  v_i integer := 0;
begin
  foreach v_who in array array[
    'poster', 'president', 'outsider',
    'dfuture', 'dedge', 'dexact', 'dbound', 'ddial',
    'dsole', 'dsoleexc', 'dserve', 'dabs',
    'da1', 'da2', 'da3', 'db1', 'db2',
    'dsilent', 'dhc', 'dsweep', 'dsweepf', 'dsettle'
  ] loop
    v_i := v_i + 1;
    insert into auth.users (id, email, raw_user_meta_data)
    values (
      ('68000000-0000-0000-0000-0000000000' || lpad(v_i::text, 2, '0'))::uuid,
      'ct-' || v_who || '@example.test',
      jsonb_build_object('name', 'Ct ' || initcap(v_who))
    );
    update public.users set name = 'Ct ' || initcap(v_who)
    where users.email = 'ct-' || v_who || '@example.test';
  end loop;
end;
$$;

update public.users
set role_id = (select roles.id from public.roles where roles.name = 'president')
where users.email = 'ct-president@example.test';

-- Ordinary tables rather than temporary ones, so reading them under the
-- authenticated role needs no assumptions about the temp schema. The whole
-- script is rolled back, so they never outlive the transaction.
create table public.ct_ids (key text primary key, id uuid not null);
grant select on public.ct_ids to authenticated;

insert into public.ct_ids (key, id)
select split_part(split_part(users.email, '@', 1), 'ct-', 2), users.id
from public.users where users.email like 'ct-%@example.test';

create table public.ct_rows (
  key text primary key,
  instance_id uuid not null
);
grant select on public.ct_rows to authenticated;

create table public.ct_places (
  key text primary key,
  assignment_id uuid not null
);
grant select on public.ct_places to authenticated;

-- ---------------------------------------------------------------------------
-- 3. The roster.
--
--    Every instant derived from the Chicago clock. now() is the transaction's
--    timestamp, so the one-second cases below are exact rather than racy.
-- ---------------------------------------------------------------------------

do $$
declare
  v_now_chi timestamp := (now() at time zone 'America/Chicago');
  v_type uuid;
  v_poster uuid := (select ids.id from public.ct_ids ids where ids.key = 'poster');
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
      -- Placed by where each seva ENDS, which is what 202608040070's bar reads:
      -- every fixture here runs sixty minutes, so an hour is subtracted from
      -- the offset the boundary is wanted at. 'dial' ends fifteen minutes ago
      -- and started seventy-five minutes ago, so the default bar lets it
      -- through and a ninety-minute complete_after_start_minutes does not.
      ('future',      interval '3 hours',                              1),
      ('edge',        interval '1 second' - interval '60 minutes',     1),
      ('exactly',     interval '-60 minutes',                          1),
      ('bound',       interval '-60 minutes' - interval '1 second',    1),
      ('dial',        interval '-75 minutes',                          1),
      ('sole',        interval '-3 hours',     1),
      ('soleexc',     interval '-3 hours',     1),
      ('partial',     interval '-3 hours',     2),
      ('allabsent',   interval '-3 hours',     3),
      ('allbutton',   interval '-3 hours',     2),
      ('silent',      interval '-3 hours',     1),
      ('noplaces',    interval '-3 hours',     1),
      ('humancancel', interval '-3 hours',     2)
    ) as plan(key, offset_from_now, slots)
  loop
    v_when := v_now_chi + v_case.offset_from_now;
    insert into public.service_instances (
      service_type_id, date, start_time, duration_minutes,
      slots_needed, participation_mode, posted_by, status
    ) values (
      v_type, v_when::date, v_when::time, 60,
      v_case.slots, 'open', v_poster, 'open'
    ) returning id into v_inst;
    insert into public.ct_rows (key, instance_id) values (v_case.key, v_inst);
  end loop;

  -- The seva that has already been verified and is waiting for 202608040020's
  -- reconciler to move it on. Created 'closed', which is what accepting a
  -- verification for a seva that has not finished does.
  v_when := v_now_chi - interval '3 hours';
  insert into public.service_instances (
    service_type_id, date, start_time, duration_minutes,
    slots_needed, participation_mode, posted_by, status
  ) values (v_type, v_when::date, v_when::time, 60, 1, 'open', v_poster, 'closed')
  returning id into v_inst;
  insert into public.ct_rows (key, instance_id) values ('settle', v_inst);
end;
$$;

-- The two recurring slots. A template each, because two instances of one
-- template cannot share a date, and 'sweepone' and 'sweepfuture' can land on
-- the same Chicago day.
do $$
declare
  v_now_chi timestamp := (now() at time zone 'America/Chicago');
  v_type uuid;
  v_pres uuid := (select ids.id from public.ct_ids ids where ids.key = 'president');
  v_case record;
  v_when timestamp;
  v_template uuid;
  v_inst uuid;
begin
  select service_types.id into v_type
  from public.service_types where service_types.name = 'Pot Washing';

  for v_case in
    select * from (values
      ('sweepone',    interval '-3 hours'),
      ('sweepfuture', interval '3 hours')
    ) as plan(key, offset_from_now)
  loop
    v_when := v_now_chi + v_case.offset_from_now;
    insert into public.service_templates (
      service_type_id, day_of_week, days_of_week, start_time, duration_minutes,
      slots_needed, participation_mode, start_date, created_by, active
    )
    select v_type, 0, array[0,1,2,3,4,5,6], v_when::time, 60, 4, 'open',
      v_now_chi::date - 400, v_pres, true
    returning id into v_template;

    insert into public.service_instances (
      template_id, service_type_id, date, start_time, duration_minutes,
      slots_needed, participation_mode, posted_by, status
    ) values (
      v_template, v_type, v_when::date, v_when::time, 60, 4, 'open', null, 'open'
    ) returning id into v_inst;
    insert into public.ct_rows (key, instance_id) values (v_case.key, v_inst);
  end loop;
end;
$$;

-- The places. Everybody confirmed and silent except d_settle, who is already
-- marked absent, because that is the shape 202608040020's reconciler would
-- otherwise complete hours later with nobody watching.
do $$
declare
  v_case record;
  v_assignment uuid;
begin
  for v_case in
    select * from (values
      ('future',      'dfuture',  'self_report',     null),
      ('edge',        'dedge',    'self_report',     null),
      ('exactly',     'dexact',   'self_report',     null),
      ('bound',       'dbound',   'self_report',     null),
      ('dial',        'ddial',    'self_report',     null),
      ('sole',        'dsole',    'member_verified', null),
      ('soleexc',     'dsoleexc', 'member_verified', null),
      ('partial',     'dserve',   'member_verified', null),
      ('partial',     'dabs',     'member_verified', null),
      ('allabsent',   'da1',      'member_verified', null),
      ('allabsent',   'da2',      'member_verified', null),
      ('allabsent',   'da3',      'member_verified', null),
      ('allbutton',   'db1',      'member_verified', null),
      ('allbutton',   'db2',      'member_verified', null),
      ('silent',      'dsilent',  'member_verified', null),
      ('humancancel', 'dhc',      'member_verified', null),
      ('sweepone',    'dsweep',   'self_report',     null),
      ('sweepfuture', 'dsweepf',  'self_report',     null),
      ('settle',      'dsettle',  'member_verified', 'absent')
    ) as plan(instance_key, who, verification, attendance)
  loop
    insert into public.service_assignments (
      service_instance_id, devotee_id, assignment_method, assigned_by,
      status, verification, attendance
    )
    select rows.instance_id,
      (select ids.id from public.ct_ids ids where ids.key = v_case.who),
      'recurring_assignment', null, 'confirmed', v_case.verification, v_case.attendance
    from public.ct_rows rows where rows.key = v_case.instance_key
    returning id into v_assignment;

    insert into public.ct_places (key, assignment_id) values (v_case.who, v_assignment);
  end loop;

  -- The verification 202608040020 will act on: verified, and its end passed an
  -- hour ago.
  insert into public.service_verifications (
    devotee_id, service_type_id, start_at, end_at, verifier_id, status,
    service_instance_id, responded_at
  )
  select
    ids.id,
    (select service_types.id from public.service_types where service_types.name = 'Pot Washing'),
    now() - interval '3 hours', now() - interval '1 hour',
    (select p.id from public.ct_ids p where p.key = 'poster'),
    'verified',
    rows.instance_id,
    now() - interval '1 hour'
  from public.ct_ids ids, public.ct_rows rows
  where ids.key = 'dsettle' and rows.key = 'settle';
end;
$$;

-- The premises, stated rather than assumed. If the Chicago arithmetic above is
-- wrong, every refusal below would be right for the wrong reason.
do $$
declare
  v_case record;
  v_opens timestamptz;
begin
  for v_case in
    select * from (values
      ('future',      false), ('edge',        false),
      ('exactly',     true),  ('bound',       true),
      ('dial',        true),  ('sole',        true),
      ('soleexc',     true),  ('partial',     true),
      ('allabsent',   true),  ('allbutton',   true),
      ('silent',      true),  ('noplaces',    true),
      ('humancancel', true),  ('sweepone',    true),
      ('sweepfuture', false), ('settle',      true)
    ) as expected(key, may_complete)
  loop
    -- The three-argument bar, because that is the one the buttons read: the
    -- two-argument floor would say yes to a seva that is halfway through.
    select public.seva_completion_opens_at(
             instances.date, instances.start_time, instances.duration_minutes)
    into v_opens
    from public.service_instances instances
    join public.ct_rows rows on rows.instance_id = instances.id
    where rows.key = v_case.key;
    if (v_opens <= now()) <> v_case.may_complete then
      raise exception
        'The "%" fixture opens at %, and now is %; it was built to be completable = %.',
        v_case.key, v_opens, now(), v_case.may_complete;
    end if;
  end loop;

  -- And the two that are refused are refused for two DIFFERENT reasons, which
  -- is what section 4 goes on to read out of the two sentences: 'future' has
  -- not started, 'edge' has started and has one second left to run.
  if exists (
    select 1 from public.service_instances instances
    join public.ct_rows rows on rows.instance_id = instances.id
    where rows.key = 'future'
      and ((instances.date + instances.start_time) at time zone 'America/Chicago') <= now()
  ) then
    raise exception 'The "future" fixture has already started.';
  end if;
  if exists (
    select 1 from public.service_instances instances
    join public.ct_rows rows on rows.instance_id = instances.id
    where rows.key = 'edge'
      and ((instances.date + instances.start_time) at time zone 'America/Chicago') > now()
  ) then
    raise exception 'The "edge" fixture has not started, so it cannot prove the second sentence.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. SENTENCE 3. A seva whose time has not passed cannot be completed; one
--    whose time has passed can. Both buttons, both sides of the boundary, and
--    authority is not a bypass.
--
--    202608040070 moved the boundary from the start of the seva to its end, so
--    there are two ways to be too early and two sentences to say so. Both are
--    read out here, on the fixture built for each: 'future' has not started,
--    'edge' has one second of its hour left to run.
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.ct_ids ids where ids.key = 'poster'), true);

do $$
declare
  v_case record;
  v_instance uuid;
  v_allowed boolean;
  v_before text;
begin
  -- Three hours out and one second out are refused alike, and the refusal says
  -- WHEN rather than merely no — and says the right one of the two things that
  -- can be wrong with the hour.
  for v_case in
    select * from (values
      ('future', 'has not started yet'),
      ('edge',   'has not finished yet')
    ) as plan(key, sentence)
  loop
    select rows.instance_id into v_instance from public.ct_rows rows where rows.key = v_case.key;
    select instances.status into v_before
    from public.service_instances instances where instances.id = v_instance;
    v_allowed := false;
    begin
      perform public.complete_service_instance(v_instance);
      v_allowed := true;
    exception when others then
      if sqlstate <> 'P0001' then raise; end if;
      if position(v_case.sentence in sqlerrm) = 0 then
        raise exception 'The "%" seva was refused, but not with "%": %',
          v_case.key, v_case.sentence, sqlerrm;
      end if;
      if position('You can mark it completed once its time on' in sqlerrm) = 0 then
        raise exception
          'The refusal on "%" does not tell the devotee when they may come back: %',
          v_case.key, sqlerrm;
      end if;
    end;
    if v_allowed then
      raise exception 'The "%" seva was completed before its time had passed.', v_case.key;
    end if;

    -- A refused completion must write NOTHING. 202608040023's two UPDATEs are
    -- in their order for exactly this reason: a completion that is going to be
    -- refused must not close somebody's place on its way to being refused.
    -- The status is compared against what it was rather than against a literal,
    -- because 0019's capacity rule owns 'open' versus 'full' and this file does
    -- not.
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

  -- One second the other way, and exactly on the boundary, are both allowed.
  -- The guard is `opens_at > now()`, so a seva ending this instant may be
  -- completed this instant.
  for v_case in select unnest(array['bound', 'exactly']) as key loop
    select rows.instance_id into v_instance from public.ct_rows rows where rows.key = v_case.key;
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
-- still the clock: 0068's bar is on the seva, not on the person.
set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.ct_ids ids where ids.key = 'president'), true);

do $$
declare
  v_instance uuid := (select rows.instance_id from public.ct_rows rows where rows.key = 'future');
  v_allowed boolean := false;
begin
  begin
    perform public.complete_service_instance(v_instance);
    v_allowed := true;
  exception when others then
    if sqlstate <> 'P0001' then raise; end if;
    if position('has not started yet' in sqlerrm) = 0 then
      raise exception 'The President was refused, but not by the clock: %', sqlerrm;
    end if;
  end;
  if v_allowed then
    raise exception 'The President closed a seva three hours before it starts.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);

-- And the devotee's own button, which can flip the whole instance by itself,
-- opens at the same instant and says so in 202608040019's words.
set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.ct_ids ids where ids.key = 'dfuture'), true);

do $$
declare
  v_instance uuid := (select rows.instance_id from public.ct_rows rows where rows.key = 'future');
  v_allowed boolean := false;
begin
  begin
    perform public.complete_my_service_assignment(v_instance);
    v_allowed := true;
  exception when others then
    if sqlstate <> 'P0001' then raise; end if;
    if sqlerrm <> 'You can mark this seva completed once it has started.' then
      raise exception 'A devotee''s own button on a future seva was refused with: %', sqlerrm;
    end if;
  end;
  if v_allowed then
    raise exception 'A devotee reported their seva finished three hours before it started.';
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

-- THE BAR IS A DIAL AND BOTH BUTTONS READ IT. 'dial' started seventy-five
-- minutes ago and ended fifteen minutes ago: at the default it may be
-- completed, and seva.complete_after_start_minutes at ninety still holds it
-- shut on its own, which is 202608040070 keeping 0068's dial as the floor under
-- the end rather than orphaning it. When the dial goes back so does the answer.
update public.app_settings set value = '90' where key = 'seva.complete_after_start_minutes';

set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.ct_ids ids where ids.key = 'poster'), true);

do $$
declare
  v_instance uuid := (select rows.instance_id from public.ct_rows rows where rows.key = 'dial');
  v_allowed boolean := false;
begin
  begin
    perform public.complete_service_instance(v_instance);
    v_allowed := true;
  exception when others then
    if sqlstate <> 'P0001' then raise; end if;
    if position('has not finished yet' in sqlerrm) = 0 then
      raise exception 'The dialled-up bar refused for the wrong reason: %', sqlerrm;
    end if;
  end;
  if v_allowed then
    raise exception
      'A seva seventy-five minutes old was completed against a ninety-minute bar; the dial does not reach the poster''s button.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);

set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.ct_ids ids where ids.key = 'ddial'), true);

do $$
declare
  v_instance uuid := (select rows.instance_id from public.ct_rows rows where rows.key = 'dial');
  v_allowed boolean := false;
begin
  begin
    perform public.complete_my_service_assignment(v_instance);
    v_allowed := true;
  exception when others then
    if sqlstate <> 'P0001' then raise; end if;
    if sqlerrm <> 'You can mark this seva completed once it has finished.' then
      raise exception 'The dialled-up bar refused the devotee for the wrong reason: %', sqlerrm;
    end if;
  end;
  if v_allowed then
    raise exception
      'The dial moved the poster''s button and not the devotee''s; the two would open at different instants.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);

update public.app_settings set value = '0' where key = 'seva.complete_after_start_minutes';

set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.ct_ids ids where ids.key = 'ddial'), true);

do $$
declare
  v_instance uuid := (select rows.instance_id from public.ct_rows rows where rows.key = 'dial');
begin
  perform public.complete_my_service_assignment(v_instance);
  if not exists (
    select 1 from public.service_instances where id = v_instance and status = 'completed'
  ) then
    raise exception 'With the dial back at zero the seva that ended a quarter of an hour ago did not close.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);

-- ---------------------------------------------------------------------------
-- 5. SENTENCE 2. A seva where every live place is absent or excused does not
--    read as completed. The sole-devotee case, in both marks.
--
--    This is the temple's own row: the seva was closed on the day and the
--    absence was recorded afterwards, which is why the rule cannot live at
--    completion time alone.
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.ct_ids ids where ids.key = 'poster'), true);

do $$
declare
  v_case record;
  v_instance uuid;
begin
  for v_case in
    select * from (values ('sole', 'dsole', 'absent'), ('soleexc', 'dsoleexc', 'excused'))
      as plan(key, who, mark)
  loop
    select rows.instance_id into v_instance from public.ct_rows rows where rows.key = v_case.key;

    -- Closed honestly, on the day, by the devotee who asked for it.
    perform public.complete_service_instance(v_instance);
    if not exists (
      select 1 from public.service_instances where id = v_instance and status = 'completed'
    ) then
      raise exception 'The "%" seva did not close in the first place.', v_case.key;
    end if;

    -- And then the coordinator says nobody was there.
    perform public.record_seva_attendance(
      (select places.assignment_id from public.ct_places places where places.key = v_case.who),
      v_case.mark);

    if exists (
      select 1 from public.service_instances where id = v_instance and status = 'completed'
    ) then
      raise exception
        'The only devotee on "%" was marked % and the seva is still in the completed list. This is the temple''s complaint, unfixed.',
        v_case.key, v_case.mark;
    end if;
    if not exists (
      select 1 from public.service_instances where id = v_instance and status = 'cancelled'
    ) then
      raise exception
        'The "%" seva left the completed list and did not land on cancelled; 0068 has invented a status.',
        v_case.key;
    end if;

    -- Nobody served it, asked the way 0068 asks it.
    if public.service_instance_has_server(v_instance) then
      raise exception 'The "%" seva reads as having a server after its only place was %.',
        v_case.key, v_case.mark;
    end if;
  end loop;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);

-- The bookkeeping, which is what makes it reversible and what tells this file's
-- cancellations apart from a person's.
do $$
declare
  v_case record;
begin
  for v_case in select unnest(array['sole', 'soleexc']) as key loop
    if not exists (
      select 1 from public.service_instances_unserved unserved
      join public.ct_rows rows on rows.instance_id = unserved.service_instance_id
      where rows.key = v_case.key
    ) then
      raise exception
        'The "%" seva was cancelled without a row saying 0068 did it, so correcting the mark could never put it back.',
        v_case.key;
    end if;
  end loop;
end;
$$;

-- The act is out of the scoring entirely, and it was worth nothing anyway, so
-- no devotee's total moved by a minute.
do $$
declare
  v_rows integer;
begin
  select count(*) into v_rows
  from public.seva_mala_acts((select ids.id from public.ct_ids ids where ids.key = 'dsole'));
  if v_rows <> 0 then
    raise exception
      'The devotee marked absent on a seva nobody served still has % act(s) in the scoring.', v_rows;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. SENTENCE 2, the all-absent-of-several case. It is the LAST mark that tips
--    it, not the first, which is the difference between "somebody was absent"
--    and "nobody served this".
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.ct_ids ids where ids.key = 'poster'), true);

do $$
declare
  v_instance uuid := (select rows.instance_id from public.ct_rows rows where rows.key = 'allabsent');
begin
  perform public.complete_service_instance(v_instance);

  perform public.record_seva_attendance(
    (select places.assignment_id from public.ct_places places where places.key = 'da1'), 'absent');
  if not exists (
    select 1 from public.service_instances where id = v_instance and status = 'completed'
  ) then
    raise exception
      'One devotee of three was marked absent and the seva left the completed list. Two others still served it.';
  end if;

  perform public.record_seva_attendance(
    (select places.assignment_id from public.ct_places places where places.key = 'da2'), 'excused');
  if not exists (
    select 1 from public.service_instances where id = v_instance and status = 'completed'
  ) then
    raise exception 'Two of three were marked and the seva left the completed list while one still stood in it.';
  end if;

  -- The third, and only now.
  perform public.record_seva_attendance(
    (select places.assignment_id from public.ct_places places where places.key = 'da3'), 'absent');
  if not exists (
    select 1 from public.service_instances where id = v_instance and status = 'cancelled'
  ) then
    raise exception
      'Every place on the seva was marked absent or excused and it is still in the completed list.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);

-- The same thing arriving through the DEVOTEE's own button rather than the
-- poster's. Two on the roster, both marked absent by the coordinator, and the
-- second of them closing their own place is what flips the instance. Without
-- the reconcile after that flip, this is a completed seva nobody served.
set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.ct_ids ids where ids.key = 'poster'), true);

do $$
begin
  perform public.record_seva_attendance(
    (select places.assignment_id from public.ct_places places where places.key = 'db1'), 'absent');
  perform public.record_seva_attendance(
    (select places.assignment_id from public.ct_places places where places.key = 'db2'), 'absent');
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);

set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.ct_ids ids where ids.key = 'db1'), true);
do $$
declare
  v_instance uuid := (select rows.instance_id from public.ct_rows rows where rows.key = 'allbutton');
begin
  perform public.complete_my_service_assignment(v_instance);
  if exists (
    select 1 from public.service_instances where id = v_instance and status in ('completed', 'cancelled')
  ) then
    raise exception 'One place of two closed and the whole seva settled; the capacity rule has moved.';
  end if;
end;
$$;
reset role;
select set_config('request.jwt.claim.sub', '', true);

set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.ct_ids ids where ids.key = 'db2'), true);
do $$
declare
  v_instance uuid := (select rows.instance_id from public.ct_rows rows where rows.key = 'allbutton');
begin
  perform public.complete_my_service_assignment(v_instance);
  if not exists (
    select 1 from public.service_instances where id = v_instance and status = 'cancelled'
  ) then
    raise exception
      'Two absent devotees closed their own places and the seva went into the completed list. 0068''s reconcile is not on the devotee''s button.';
  end if;
end;
$$;
reset role;
select set_config('request.jwt.claim.sub', '', true);

-- ---------------------------------------------------------------------------
-- 7. SILENCE IS NOT ABSENCE, AND A SEVA WITH NO PLACES CANNOT BE COMPLETED AT
--    ALL.
--
--    Silence is the conservative direction, deliberately. The temple asked for
--    the seva to come out of the list when people are MARKED absent, not when
--    nobody has got round to marking anything.
--
--    THE SECOND HALF OF THIS SECTION USED TO ASSERT THE OPPOSITE OF WHAT IT
--    ASSERTS NOW, and that is the second thing 202608040070 corrects. 0068 left
--    an instance nobody had ever joined alone on the reasoning that sentence 2
--    is about devotees MARKED absent and there is nobody there to mark — which
--    is a good reason not to CANCEL it, and no reason at all to let it sit in
--    the completed list saying service happened. It is refused at the door now.
--    What becomes of a row that is already wrong, and the fact that it stays
--    visible as a lapsed request rather than vanishing, is proved in
--    supabase/verification/completion_window.sql.
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.ct_ids ids where ids.key = 'poster'), true);

do $$
declare
  v_silent uuid := (select rows.instance_id from public.ct_rows rows where rows.key = 'silent');
  v_none uuid := (select rows.instance_id from public.ct_rows rows where rows.key = 'noplaces');
  v_none_before text;
  v_allowed boolean;
begin
  perform public.complete_service_instance(v_silent);
  if not exists (
    select 1 from public.service_instances where id = v_silent and status = 'completed'
  ) then
    raise exception
      'A seva whose one place nobody has spoken about was taken out of the completed list. Silence was read as absence.';
  end if;
  if not public.service_instance_has_server(v_silent) then
    raise exception 'An unmarked place does not read as service.';
  end if;

  -- And the seva nobody was ever placed on is refused, in words that say why.
  select instances.status into v_none_before
  from public.service_instances instances where instances.id = v_none;
  v_allowed := false;
  begin
    perform public.complete_service_instance(v_none);
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
    where id = v_none and status is distinct from v_none_before
  ) then
    raise exception 'The refused completion moved the unclaimed request from % anyway.', v_none_before;
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);

-- The bookkeeping is read with the role reset throughout this file, because
-- service_instances_unserved is granted to nobody and that is asserted in
-- section 0.
do $$
begin
  if exists (
    select 1 from public.service_instances_unserved unserved
    join public.ct_rows rows on rows.instance_id = unserved.service_instance_id
    where rows.key in ('noplaces', 'silent')
  ) then
    raise exception
      'A seva with no places at all, or one nobody has spoken about, was recorded as one 0068 closed.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. PARTIAL ABSENCE STILL COMPLETES, AND ONLY THE DEVOTEE WHO SERVED EARNS.
--
--    The temple's own words: "if one person did the seva, it will still go to
--    the completed list as one person served, and only that person will get
--    seva in their list and seva points will be going only to that person."
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.ct_ids ids where ids.key = 'poster'), true);

do $$
declare
  v_instance uuid := (select rows.instance_id from public.ct_rows rows where rows.key = 'partial');
begin
  perform public.complete_service_instance(v_instance);
  perform public.record_seva_attendance(
    (select places.assignment_id from public.ct_places places where places.key = 'dserve'), 'served');
  perform public.record_seva_attendance(
    (select places.assignment_id from public.ct_places places where places.key = 'dabs'), 'absent');

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

-- Only that person. Asserted on the scoring itself, which is where a devotee's
-- minutes actually come from.
do $$
declare
  v_row record;
begin
  select acts.points_status, acts.quality, acts.credited_minutes into v_row
  from public.seva_mala_acts((select ids.id from public.ct_ids ids where ids.key = 'dserve')) acts
  join public.ct_rows rows on rows.instance_id = acts.service_instance_id
  where rows.key = 'partial';
  if v_row.points_status <> 'counted' or coalesce(v_row.quality, 0) <= 0
    or coalesce(v_row.credited_minutes, 0) <= 0 then
    raise exception
      'The devotee who actually served the seva is credited % minutes at quality % (%).',
      v_row.credited_minutes, v_row.quality, v_row.points_status;
  end if;

  select acts.points_status, acts.quality, acts.credited_minutes into v_row
  from public.seva_mala_acts((select ids.id from public.ct_ids ids where ids.key = 'dabs')) acts
  join public.ct_rows rows on rows.instance_id = acts.service_instance_id
  where rows.key = 'partial';
  if v_row.points_status is null then
    raise exception 'The absent devotee''s place vanished from the scoring rather than being worth nothing.';
  end if;
  if v_row.points_status <> 'not_served'
    or coalesce(v_row.quality, 1) <> 0
    or coalesce(v_row.credited_minutes, 1) <> 0 then
    raise exception
      'The absent devotee on a seva that DID complete is credited % minutes at quality % (%).',
      v_row.credited_minutes, v_row.quality, v_row.points_status;
  end if;
end;
$$;

-- And the absent devotee is told so in their own list, in their own words, by
-- the read they actually see.
set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.ct_ids ids where ids.key = 'dabs'), true);

do $$
declare
  v_status text;
begin
  select acts.points_status into v_status
  from public.my_seva_acts() acts
  join public.ct_rows rows on rows.instance_id = acts.service_instance_id
  where rows.key = 'partial';
  if v_status is distinct from 'not_served' then
    raise exception 'The absent devotee''s own list reads % for the seva they missed.', v_status;
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);

-- ---------------------------------------------------------------------------
-- 9. REVERSIBLE — AND IN ONE DIRECTION ONLY.
--
--    A coordinator who marks the wrong devotee absent has taken a seva out of
--    the completed list and, with it, that devotee's points. Correcting the
--    mark puts both back. But a seva a PERSON cancelled is never promoted here,
--    however much attendance is later recorded on a leftover place, and that is
--    what service_instances_unserved is for.
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.ct_ids ids where ids.key = 'poster'), true);

do $$
declare
  v_instance uuid := (select rows.instance_id from public.ct_rows rows where rows.key = 'sole');
begin
  perform public.record_seva_attendance(
    (select places.assignment_id from public.ct_places places where places.key = 'dsole'), 'served');

  if not exists (
    select 1 from public.service_instances where id = v_instance and status = 'completed'
  ) then
    raise exception
      'The absence was corrected and the seva did not go back into the completed list.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);

do $$
begin
  if exists (
    select 1 from public.service_instances_unserved unserved
    join public.ct_rows rows on rows.instance_id = unserved.service_instance_id
    where rows.key = 'sole'
  ) then
    raise exception
      'A seva put back into the completed list still carries the row saying 0068 closed it, so a later cancellation by a person could be undone.';
  end if;
end;
$$;

-- The devotee's points came back with it.
do $$
declare
  v_row record;
begin
  select acts.points_status, acts.credited_minutes into v_row
  from public.seva_mala_acts((select ids.id from public.ct_ids ids where ids.key = 'dsole')) acts
  join public.ct_rows rows on rows.instance_id = acts.service_instance_id
  where rows.key = 'sole';
  if v_row.points_status is distinct from 'counted' or coalesce(v_row.credited_minutes, 0) <= 0 then
    raise exception
      'The corrected devotee is back in the completed list but reads % for % minutes.',
      v_row.points_status, v_row.credited_minutes;
  end if;
end;
$$;

-- THE OTHER DIRECTION. d_hc closes their own place, which leaves it 'completed'
-- and therefore beyond cancel_service_instance's withdrawal of live places. The
-- poster then cancels the seva as a person — and no amount of attendance
-- recorded afterwards may promote it, because 0068 did not close it.
set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.ct_ids ids where ids.key = 'dhc'), true);
do $$
begin
  perform public.complete_my_service_assignment(
    (select rows.instance_id from public.ct_rows rows where rows.key = 'humancancel'));
end;
$$;
reset role;
select set_config('request.jwt.claim.sub', '', true);

-- The cancellation itself runs with the role reset and the poster's claim
-- still set, because 202608040010 took cancel_service_instance away from
-- `authenticated` altogether: it is a service-side call now. auth.uid() is
-- still the poster, which is the only thing the function's own rule reads.
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.ct_ids ids where ids.key = 'poster'), true);

do $$
declare
  v_instance uuid := (select rows.instance_id from public.ct_rows rows where rows.key = 'humancancel');
begin
  perform public.cancel_service_instance(v_instance);
  if not exists (
    select 1 from public.service_instances where id = v_instance and status = 'cancelled'
  ) then
    raise exception 'The poster''s own cancellation did not take.';
  end if;
end;
$$;

set local role authenticated;

do $$
declare
  v_instance uuid := (select rows.instance_id from public.ct_rows rows where rows.key = 'humancancel');
begin
  -- The place is still 'completed' and is about to be marked served, which is
  -- exactly the shape that would tempt the promotion arm.
  if not exists (
    select 1 from public.service_assignments assignments
    join public.ct_places places on places.assignment_id = assignments.id
    where places.key = 'dhc' and assignments.status = 'completed'
  ) then
    raise exception 'The fixture for the human cancellation no longer holds a live place to be marked.';
  end if;

  perform public.record_seva_attendance(
    (select places.assignment_id from public.ct_places places where places.key = 'dhc'), 'served');

  if exists (
    select 1 from public.service_instances where id = v_instance and status = 'completed'
  ) then
    raise exception
      'A seva a person cancelled was promoted to completed because somebody was later marked served. 0068 has undone a human decision.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);

-- And it was never in the table, which is the reason it could not be promoted.
-- Stated separately from the behaviour above so that a run where the promotion
-- arm has quietly stopped working altogether still fails here.
do $$
begin
  if exists (
    select 1 from public.service_instances_unserved unserved
    join public.ct_rows rows on rows.instance_id = unserved.service_instance_id
    where rows.key = 'humancancel'
  ) then
    raise exception 'A seva a person cancelled was recorded as one 0068 closed.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 10. 202608040065'S HOURLY SWEEP OBEYS ALL OF THE ABOVE.
--
--     It shares complete_service_instance_internal with the poster's button, so
--     there is one dialect of 'completed' and not two. The sweep's own bar
--     stays the inner one: 0068's clock is on the front door only, and the
--     sweep — which is stricter, being the end plus an hour — is untouched.
-- ---------------------------------------------------------------------------

do $$
declare
  v_one uuid := (select rows.instance_id from public.ct_rows rows where rows.key = 'sweepone');
  v_fut uuid := (select rows.instance_id from public.ct_rows rows where rows.key = 'sweepfuture');
begin
  if not exists (
    select 1 from public.due_recurring_service_instances where service_instance_id = v_one
  ) then
    raise exception
      'The recurring slot whose Chicago hour and grace have gone is not due. 0068 has reached into 0065''s selection.';
  end if;
  if exists (
    select 1 from public.due_recurring_service_instances where service_instance_id = v_fut
  ) then
    raise exception 'A recurring slot three hours in the future is due.';
  end if;

  perform public.complete_due_recurring_service_instances();

  -- The positive: the sweep still closes what it is for, and the silent place
  -- reads as service, so the reconcile leaves it exactly where the sweep put it.
  if not exists (
    select 1 from public.service_instances where id = v_one and status = 'completed'
  ) then
    raise exception
      'The sweep did not complete a due recurring slot, or 0068 cancelled one whose only place was silent.';
  end if;
  if not exists (
    select 1 from public.service_assignments assignments
    where assignments.service_instance_id = v_one and assignments.status = 'completed'
  ) then
    raise exception 'The sweep closed the instance and not the place.';
  end if;
  if exists (
    select 1 from public.service_instances where id = v_fut and status <> 'open'
  ) then
    raise exception 'The sweep touched a recurring slot whose hour has not come.';
  end if;
end;
$$;

-- And now the mark, on a slot a clock closed.
--
-- 202608310098 removed absence from weekly seva entirely: a rota runs by
-- itself, counts on completion alone, and a devotee who cannot make their day
-- asks for coverage rather than being marked away. So this is no longer a case
-- about what an absence does to the completed list — it is the case that the
-- mark cannot be made at all, and the occurrence stands.
set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.ct_ids ids where ids.key = 'president'), true);

do $$
declare
  v_one uuid := (select rows.instance_id from public.ct_rows rows where rows.key = 'sweepone');
  v_refused boolean := false;
begin
  begin
    perform public.record_seva_attendance(
      (select places.assignment_id from public.ct_places places where places.key = 'dsweep'), 'absent');
  exception when others then
    v_refused := true;
  end;

  if not v_refused then
    raise exception 'A devotee was marked absent on a weekly seva.';
  end if;
  if not exists (
    select 1 from public.service_instances where id = v_one and status = 'completed'
  ) then
    raise exception
      'A recurring slot the clock closed did not stay completed once absence was refused.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);

do $$
declare
  v_one uuid := (select rows.instance_id from public.ct_rows rows where rows.key = 'sweepone');
begin
  -- The sweep leaves it alone. A completed occurrence is not due again, and a
  -- rota that runs by itself must not be disturbed on the hour either.
  if exists (
    select 1 from public.due_recurring_service_instances where service_instance_id = v_one
  ) then
    raise exception
      'A completed weekly slot is due again; the sweep would rework it on the hour.';
  end if;
  perform public.complete_due_recurring_service_instances();
  if not exists (
    select 1 from public.service_instances where id = v_one and status = 'completed'
  ) then
    raise exception 'The next sweep moved a completed weekly slot out of the completed list.';
  end if;
end;
$$;

-- Neither mark reaches a weekly slot. 202608310098 removed both from a rota:
-- it counts on completion alone, and a devotee who cannot make their day asks
-- for coverage. So "served" is refused for the same reason "absent" was, and
-- the occurrence stands either way.
set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.ct_ids ids where ids.key = 'president'), true);

do $$
declare
  v_one uuid := (select rows.instance_id from public.ct_rows rows where rows.key = 'sweepone');
  v_refused boolean := false;
begin
  begin
    perform public.record_seva_attendance(
      (select places.assignment_id from public.ct_places places where places.key = 'dsweep'), 'served');
  exception when others then
    v_refused := true;
  end;

  if not v_refused then
    raise exception 'A devotee was marked served on a weekly seva.';
  end if;
  if not exists (
    select 1 from public.service_instances where id = v_one and status = 'completed'
  ) then
    raise exception 'A weekly slot did not stay completed once marking was refused.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);

-- THE ARM THE SWEEP CANNOT REACH TODAY, exercised anyway. 0065's view selects
-- only instances holding a place with no attendance recorded, so a sweep
-- completion always has a server — that is two migrations' selection rules
-- agreeing, not a guarantee. Called on the auto path directly, an all-absent
-- instance must settle the same way the President's button settles it.
do $$
declare
  v_type uuid;
  v_pres uuid := (select ids.id from public.ct_ids ids where ids.key = 'president');
  v_when timestamp := (now() at time zone 'America/Chicago') - interval '3 hours';
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
  ) values (v_template, v_type, v_when::date, v_when::time, 60, 4, 'open', null, 'open')
  returning id into v_inst;

  insert into public.service_assignments (
    service_instance_id, devotee_id, assignment_method, assigned_by,
    status, verification, attendance
  )
  select v_inst, ids.id, 'recurring_assignment', null, 'confirmed', 'member_verified', 'absent'
  from public.ct_ids ids where ids.key = 'outsider';

  if not public.complete_service_instance_internal(v_inst, v_pres, true) then
    raise exception 'The auto path refused an open recurring slot.';
  end if;
  if not exists (
    select 1 from public.service_instances where id = v_inst and status = 'cancelled'
  ) then
    raise exception
      'The auto path completed a slot whose every place was already marked absent. 0068''s reconcile is not on the shared body.';
  end if;
  if not exists (
    select 1 from public.service_instances_unserved where service_instance_id = v_inst
  ) then
    raise exception 'The auto path cancelled a slot without recording that 0068 did it.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 11. THE FOURTH WRITER OF 'completed', WHICH NOBODY PRESSES.
--
--     202608040020's reconciler moves a verified seva from 'closed' to
--     'completed' once its end time passes. A devotee verified for a seva they
--     were then marked absent from would be completed by it, hours later.
-- ---------------------------------------------------------------------------

do $$
declare
  v_instance uuid := (select rows.instance_id from public.ct_rows rows where rows.key = 'settle');
  v_moved integer;
begin
  v_moved := public.settle_finished_verified_seva();
  if v_moved < 1 then
    raise exception 'The verified-seva reconciler moved nothing; the fixture is not reaching it.';
  end if;
  if exists (
    select 1 from public.service_instances where id = v_instance and status = 'completed'
  ) then
    raise exception
      'A verified seva whose devotee was marked absent was completed by the reconciler nobody presses.';
  end if;
  if not exists (
    select 1 from public.service_instances where id = v_instance and status = 'cancelled'
  ) then
    raise exception 'The verified seva nobody served did not land on cancelled.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 12. NOTHING VANISHES SILENTLY.
--
--     'cancelled' is invisible in every list the app builds, which is what
--     "removed from the list" means and is also the one way this change could
--     hurt. list_seva_closed_unserved is the answer, and it answers only the
--     three people who could have closed the seva in the first place.
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.ct_ids ids where ids.key = 'poster'), true);

do $$
declare
  v_row record;
  v_seen integer;
begin
  select count(*) into v_seen
  from public.list_seva_closed_unserved() listed
  join public.ct_rows rows on rows.instance_id = listed.service_instance_id
  where rows.key = 'soleexc';
  if v_seen <> 1 then
    raise exception
      'The poster cannot see the seva that was taken out of their completed list (% rows).', v_seen;
  end if;

  -- With every place on it and what was said about each, so the coordinator can
  -- see WHY rather than merely that it is gone.
  select listed.devotee_name, listed.attendance, listed.points_status, listed.seva_name
  into v_row
  from public.list_seva_closed_unserved() listed
  join public.ct_rows rows on rows.instance_id = listed.service_instance_id
  where rows.key = 'soleexc';
  if v_row.attendance <> 'excused' or v_row.points_status <> 'not_served'
    or v_row.devotee_name is null or v_row.seva_name is null then
    raise exception
      'The list says % / % / % / %, which does not tell the coordinator who was marked what.',
      v_row.seva_name, v_row.devotee_name, v_row.attendance, v_row.points_status;
  end if;

  -- A seva that came BACK is not in it, and neither is one a person cancelled.
  if exists (
    select 1 from public.list_seva_closed_unserved() listed
    join public.ct_rows rows on rows.instance_id = listed.service_instance_id
    where rows.key in ('sole', 'humancancel')
  ) then
    raise exception
      'The unserved list holds a seva that was put back, or one a person cancelled.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);

-- A devotee with nothing to do with any of it sees none of it, including the
-- devotee who was marked absent on somebody else's seva.
set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.ct_ids ids where ids.key = 'dsoleexc'), true);

do $$
begin
  if exists (select 1 from public.list_seva_closed_unserved()) then
    raise exception
      'A devotee can read the list of seva nobody served, which names who was marked absent.';
  end if;
  if exists (select 1 from public.service_instances_unserved) then
    raise exception 'A devotee can read service_instances_unserved directly.';
  end if;
exception when insufficient_privilege then
  null;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);

-- The President sees all of it, recurring slots included, which is the whole
-- reason the view_all arm is there: a weekly slot carries no poster.
set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.ct_ids ids where ids.key = 'president'), true);

do $$
begin
  if not exists (
    select 1 from public.list_seva_closed_unserved() listed
    join public.ct_rows rows on rows.instance_id = listed.service_instance_id
    where rows.key = 'soleexc'
  ) then
    raise exception 'The President cannot see a seva that was taken out of the completed list.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);

-- ---------------------------------------------------------------------------
-- 13. THE WHOLE ROSTER, ONE LAST TIME.
--
--     Every fixture instance and the status 0068 must have left it in, so a
--     change that fixes one case by breaking another cannot pass.
-- ---------------------------------------------------------------------------

do $$
declare
  v_case record;
  v_status text;
begin
  for v_case in
    select * from (values
      -- 'full' rather than 'open' because 0019's capacity rule fills a
      -- one-place seva the moment its one devotee is on it. What matters here
      -- is that neither is 'completed'.
      ('future',      'full'),      -- three hours out; refused
      ('edge',        'full'),      -- one second of its hour left; refused
      ('exactly',     'completed'), -- ends exactly now; allowed
      ('bound',       'completed'), -- ended one second ago; allowed
      ('dial',        'completed'), -- allowed once the dial went back to zero
      ('sole',        'completed'), -- absent, then corrected
      ('soleexc',     'cancelled'), -- the only devotee, excused
      ('partial',     'completed'), -- one of two served
      ('allabsent',   'cancelled'), -- all three marked
      ('allbutton',   'cancelled'), -- both absent, via their own button
      ('silent',      'completed'), -- nobody said anything
      -- Refused outright by 202608040070: it never moved, so it is still the
      -- unclaimed request it was created as.
      ('noplaces',    'open'),      -- nobody was ever placed on it
      ('humancancel', 'cancelled'), -- a person cancelled it, and it stayed
      ('sweepone',    'completed'), -- swept, cancelled, corrected
      ('sweepfuture', 'open'),      -- its hour has not come
      ('settle',      'cancelled')  -- verified, absent, settled
    ) as expected(key, status)
  loop
    select instances.status into v_status
    from public.service_instances instances
    join public.ct_rows rows on rows.instance_id = instances.id
    where rows.key = v_case.key;
    if v_status is distinct from v_case.status then
      raise exception 'The "%" seva is % rather than %.', v_case.key, v_status, v_case.status;
    end if;
  end loop;

  -- And the terminal state is inside 202608020002's vocabulary. 0068 added no
  -- status of its own, so a client detects a nobody-served seva as
  -- status = 'cancelled' plus list_seva_closed_unserved, and never as some
  -- sixth value it has never seen.
  if exists (
    select 1 from public.service_instances instances
    join public.ct_rows rows on rows.instance_id = instances.id
    where instances.status not in ('open', 'full', 'closed', 'cancelled', 'completed')
  ) then
    raise exception '0068 wrote a status the rest of the system does not read.';
  end if;

  -- Every row this file left in the unserved table is cancelled, and every
  -- cancelled-as-unserved row is out of the completed list. The two halves
  -- cannot drift apart.
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

do $$
begin
  raise notice 'all completion truthfulness checks passed';
end;
$$;

select 'completion truthfulness verification passed' as result;

rollback;
