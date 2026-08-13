-- Functional verification for 202608040058_seva_balance.sql.
--
-- Rolled back at the end. Every local is prefixed v_ so it can never shadow a
-- column name. Anything that must be refused is attempted as the devotee who
-- would really attempt it, under `set local role authenticated`, so the
-- permission checks and the function grants are what is being tested rather
-- than superuser rights waving everything through.
--
-- ---------------------------------------------------------------------------
-- The fixture is a contrast, not a crowd.
--
-- The whole feature comes down to one pair of devotees:
--
--   GOPAL serves ten hours a week, all of it pot washing, seven weeks running.
--   MIRA  serves ten hours a week, two hours each of five different sevas,
--         over the same weeks.
--
-- Identical weekly load. Gopal must be surfaced and Mira must not, and no
-- threshold that reads only "how many hours" can tell them apart. That single
-- pair is the assertion this file exists for; everything else is the
-- congregation they are being compared against.
--
-- Everything is laid out relative to this Monday in Chicago, so the script is
-- deterministic on any day of any week. W0 is this Monday, W(-k) is k Mondays
-- ago, and the trailing quarter the feature measures over is W(-12) .. today.
--
-- The cast:
--   gopal    ...0001  10 h/week of Pot Washing in each of W(-6)..W0. Seven
--                     weeks running, 70 hours, 100% of his seva, one category.
--                     Surfaced by BOTH lists, which is correct: he is carrying
--                     too much of one thing AND he has never done anything else.
--   mira     ...0002  10 h/week spread over five sevas in five categories,
--                     W(-6)..W(-1). Surfaced by neither. The control. Hers is
--                     also the only seva in this fixture that is fully
--                     confirmed and earns Seva Mala points; everybody else's
--                     sits unverified and earns none, which is the ordinary
--                     state of the temple's data and must not hide their hours.
--   ananda   ...0003  five hours a week of Kirtana Support and Guest Welcome,
--                     every other week. Never enough of one seva to concentrate
--                     — and never once outside the event category. Surfaced by
--                     narrowness only. This is the temple's "kirtan all the
--                     time but no ground work". He also gives ten hours to a
--                     custom-named seva with no service type and so no
--                     category, which are hours and are not evidence.
--   f1..f8   ...0021+ the congregation. Three hours a week each, half kitchen
--                     and half event, on alternating weeks. They are the
--                     distribution every threshold is derived from, and not one
--                     of them may be surfaced by anything.
--   nishtha  ...0011  nine tenths of her seva in the kitchen and half an hour
--                     of everything else. Narrow-looking and not narrow: you
--                     cannot be remarked on for never doing something you have
--                     done. Section 14.
--   purana   ...0010  Gopal's exact pattern, finished four months ago. Absent
--                     from every congregation figure and present in his own
--                     history, which is the difference between the trailing
--                     quarter and all time.
--   bhumi    ...0004  six acts on the six dates that prove the Chicago window
--                     boundaries: this Monday, the Sunday before it, the first
--                     of the month, the day before it, the first day of the
--                     quarter and the day before that. She serves in section 2
--                     rather than section 3, because two devotees are what
--                     makes the gathering rule provable.
--   ghost    ...0005  four ten-hour acts that must count for exactly nothing:
--                     a no-show, an absence, a withdrawal and a cancelled seva.
--   prez     ...0006  President. app.view_all.
--   tech     ...0007  Tech Admin. app.view_all.
--   head     ...0008  Community Head. services.manage_recurring and NOT
--                     app.view_all. Sees nothing, and that is deliberate.
--   plain    ...0009  a devotee. Sees nothing but her own hours.
--   heavy1.. ...0031+ fifteen devotees who arrive in section 12 serving
--                     twenty-five hours a week. Nothing about Gopal changes and
--                     Gopal stops being surfaced, because the congregation he
--                     is being read against changed. That section is the proof
--                     that the thresholds are the temple's and not ours.
--
-- The final row must read: seva balance verification passed

begin;

-- ---------------------------------------------------------------------------
-- 0. The shape of the thing, before any of its behaviour.
-- ---------------------------------------------------------------------------

do $$
declare
  v_name text;
  v_overloads integer;
  v_def text;
  v_proc record;
  v_trigger record;
begin
  -- One of each. A leftover overload with a defaulted argument is how a call
  -- in this repo has become ambiguous before.
  foreach v_name in array array[
    'seva_balance_for_devotee', 'list_seva_concentration', 'list_seva_narrowness',
    'seva_balance_thresholds', 'my_seva_balance', 'seva_balance_references',
    'seva_balance_acts', 'seva_balance_window_start'
  ] loop
    select count(*)::integer into v_overloads
    from pg_proc
    join pg_namespace on pg_namespace.oid = pg_proc.pronamespace
    where pg_namespace.nspname = 'public' and pg_proc.proname = v_name;
    if v_overloads <> 1 then
      raise exception 'public.% has % overloads rather than 1.', v_name, v_overloads;
    end if;
  end loop;

  -- Nothing here may act. Read-only in the type system, not only in intent:
  -- a volatile function is one that has been given permission to write, and
  -- the day this feature writes anything is the day it stops being care.
  for v_proc in
    select pg_proc.proname, pg_proc.prosecdef, pg_proc.provolatile,
           pg_get_functiondef(pg_proc.oid) as body
    from pg_proc
    join pg_namespace on pg_namespace.oid = pg_proc.pronamespace
    where pg_namespace.nspname = 'public'
      and pg_proc.proname in (
        'seva_balance_for_devotee', 'list_seva_concentration', 'list_seva_narrowness',
        'seva_balance_thresholds', 'my_seva_balance', 'seva_balance_references',
        'seva_balance_acts', 'seva_balance_window_start'
      )
  loop
    if not v_proc.prosecdef then
      raise exception '%: not security definer, so it answers differently depending on who asks.', v_proc.proname;
    end if;
    if v_proc.provolatile = 'v' then
      raise exception '%: volatile.', v_proc.proname;
    end if;
    if position('search_path=''''' in v_proc.body) = 0
       and position('search_path TO ''''' in v_proc.body) = 0 then
      raise exception '%: no empty search_path.', v_proc.proname;
    end if;
    foreach v_name in array array[
      'insert into', 'update public', 'delete from',
      'queue_app_notification', 'create temp'
    ] loop
      if position(v_name in lower(v_proc.body)) > 0 then
        raise exception
          '%: contains "%". This feature watches devotees and must never act on one.',
          v_proc.proname, v_name;
      end if;
    end loop;
  end loop;

  -- No trigger anywhere may call into this. A care report that fires is a
  -- care report that has become an automatic decision. Walked as a loop rather
  -- than asked as an EXISTS, because a planner is free to push a
  -- pg_get_functiondef filter down onto the whole of pg_proc, and that call
  -- raises on the first aggregate it meets.
  for v_trigger in
    select pg_proc.oid as fn from pg_trigger
    join pg_proc on pg_proc.oid = pg_trigger.tgfoid
    where pg_proc.prokind = 'f'
  loop
    if pg_get_functiondef(v_trigger.fn) ~* '(seva_balance|list_seva_concentration|list_seva_narrowness)' then
      raise exception 'A trigger calls into seva balance.';
    end if;
  end loop;

  -- The internals are not for devotees, and neither is the raw act stream.
  foreach v_name in array array[
    'public.seva_balance_references()',
    'public.seva_balance_acts(uuid)',
    'public.seva_balance_window_start()'
  ] loop
    if has_function_privilege('authenticated', v_name, 'execute') then
      raise exception 'authenticated may execute %.', v_name;
    end if;
  end loop;

  foreach v_name in array array[
    'public.seva_balance_for_devotee(uuid)',
    'public.list_seva_concentration(integer, numeric)',
    'public.list_seva_narrowness(numeric)',
    'public.seva_balance_thresholds()',
    'public.my_seva_balance()'
  ] loop
    if not has_function_privilege('authenticated', v_name, 'execute') then
      raise exception 'authenticated may not execute %.', v_name;
    end if;
    if has_function_privilege('anon', v_name, 'execute') then
      raise exception 'anon may execute %.', v_name;
    end if;
  end loop;

  -- The devotee's own view is built from a different set of columns on
  -- purpose. Nothing in it may be a reading of how they compare to anybody.
  select string_agg(lower(names.name), ',' order by names.name) into v_def
  from pg_proc, unnest(pg_proc.proargnames) as names(name)
  where pg_proc.oid = to_regprocedure('public.my_seva_balance()');
  if v_def is null or position('hours_all_time' in v_def) = 0 then
    raise exception 'my_seva_balance''s columns could not be read; this check would pass vacuously.';
  end if;
  foreach v_name in array array[
    'share', 'streak', 'consecutive', 'threshold', 'median', 'concentration',
    'pronounced', 'flag', 'vs_', 'note', 'untouched'
  ] loop
    if position(v_name in coalesce(v_def, '')) > 0 then
      raise exception
        'my_seva_balance returns a column matching "%" — a devotee''s own screen must not carry the coordinator''s reading.',
        v_name;
    end if;
  end loop;

  -- The dials must live in app_settings rather than in a function body.
  if position('seva_balance.weekly_load_multiple' in
       pg_get_functiondef('public.seva_balance_references()'::regprocedure)) = 0
  then
    raise exception 'The weekly load multiple is not read from app_settings.';
  end if;
  if has_table_privilege('authenticated', 'public.app_settings', 'select') then
    raise exception 'authenticated can read app_settings.';
  end if;
end;
$$;

do $$
declare
  v_expected text;
  v_actual text;
begin
  for v_expected, v_actual in
    select expected.key || '=' || expected.value,
           expected.key || '=' || coalesce(settings.value, '(absent)')
    from (values
      ('seva_balance.window_weeks', '13'),
      ('seva_balance.weekly_load_multiple', '1.5'),
      ('seva_balance.weekly_hours_quantile', '0.85'),
      ('seva_balance.weeks_quantile', '0.85'),
      ('seva_balance.minimum_weeks_floor', '2'),
      ('seva_balance.category_share_quantile', '0.90'),
      ('seva_balance.narrow_category_share_floor', '0.90'),
      ('seva_balance.minimum_cohort', '8')
    ) as expected(key, value)
    left join public.app_settings settings on settings.key = expected.key
  loop
    if v_expected <> v_actual then
      raise exception 'Seva balance dial mismatch: expected %, found %.', v_expected, v_actual;
    end if;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- 1. The congregation, and the acts.
-- ---------------------------------------------------------------------------

do $$
declare
  v_who text;
  v_i integer := 0;
begin
  foreach v_who in array array[
    'gopal', 'mira', 'ananda', 'bhumi', 'ghost', 'prez', 'tech', 'head', 'plain',
    'purana', 'nishtha'
  ] loop
    v_i := v_i + 1;
    insert into auth.users (id, email, raw_user_meta_data)
    values (
      ('5b000000-0000-0000-0000-0000000000' || lpad(v_i::text, 2, '0'))::uuid,
      'sb-' || v_who || '@example.test',
      jsonb_build_object('name', initcap(v_who) || ' Das')
    );
  end loop;

  for v_i in 1 .. 8 loop
    insert into auth.users (id, email, raw_user_meta_data)
    values (
      ('5b000000-0000-0000-0000-0000000000' || lpad((20 + v_i)::text, 2, '0'))::uuid,
      'sb-f' || v_i || '@example.test',
      jsonb_build_object('name', 'Filler ' || v_i)
    );
  end loop;
end;
$$;

update public.users set role_id = (select roles.id from public.roles where roles.name = 'president')
where users.email = 'sb-prez@example.test';
update public.users set role_id = (select roles.id from public.roles where roles.name = 'tech')
where users.email = 'sb-tech@example.test';
update public.users set role_id = (select roles.id from public.roles where roles.name = 'core')
where users.email = 'sb-head@example.test';

-- Ordinary table rather than a temporary one, so reading it under the
-- authenticated role needs no assumptions about the temp schema. The whole
-- script is rolled back, so it never outlives the transaction.
create table public.seva_balance_test_ids (key text primary key, id uuid not null);
grant select on public.seva_balance_test_ids to authenticated;

insert into public.seva_balance_test_ids (key, id)
select split_part(split_part(users.email, '@', 1), 'sb-', 2), users.id
from public.users where users.email like 'sb-%@example.test';

-- Every coordinator-side read below is made AS THE PRESIDENT. Superuser is not
-- a shortcut here: these functions gate on has_permission('app.view_all'),
-- which reads auth.uid(), so a script that forgot to say who it was would get
-- an empty set from every one of them and pass while proving nothing.
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.seva_balance_test_ids ids where ids.key = 'prez'), true);

do $$
begin
  if not public.has_permission('app.view_all') then
    raise exception 'The script is not speaking as somebody who holds app.view_all.';
  end if;
end;
$$;

-- One place that turns "who, what, which week, how long" into a served act, so
-- the fixture below reads as the story it is.
create or replace function public.sb_serve(
  p_who text, p_type text, p_on date, p_minutes integer, p_times integer default 1,
  p_verification text default 'self_report', p_attendance text default null
)
returns void
language plpgsql
as $$
declare
  v_instance uuid;
  v_n integer;
begin
  for v_n in 1 .. p_times loop
    insert into public.service_instances (
      service_type_id, date, start_time, duration_minutes, slots_needed,
      participation_mode, posted_by, status
    ) values (
      (select service_types.id from public.service_types where service_types.name = p_type),
      p_on, time '09:00', p_minutes, 1, 'open', null, 'completed'
    ) returning id into v_instance;

    insert into public.service_assignments (
      service_instance_id, devotee_id, assignment_method, status,
      verification, attendance, completed_at
    ) values (
      v_instance,
      (select ids.id from public.seva_balance_test_ids ids where ids.key = p_who),
      'self_joined', 'completed', p_verification, p_attendance,
      (p_on + time '12:00') at time zone 'America/Chicago'
    );
  end loop;
end;
$$;

-- The default above is the temple's ordinary case, and it is not an accident.
-- 202608040057 earns points only for completed AND verified AND marked served,
-- so a devotee on a recurring assignment that nobody has confirmed sits at
-- awaiting_verification forever and earns nothing. Every act in this fixture
-- except Mira's is exactly that act. If seva balance read hours off the points
-- rule, this entire script would find an empty temple — which is the failure
-- the fixture is shaped to catch.
do $$
begin
  if public.seva_points_status('completed', null, 'self_report') <> 'awaiting_verification' then
    raise exception 'The fixture''s ordinary act is no longer the unconfirmed one.';
  end if;
  if public.seva_points_status('completed', 'served', 'member_verified') <> 'counted' then
    raise exception 'Mira''s acts are no longer the fully counted ones.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Gathering: one devotee is not a distribution.
--
--    Gopal's pattern is laid down first, alone. With a single serving devotee
--    the congregation has no upper tail to be in, no median to be unlike, and
--    every list stays silent. A false alarm costs a devotee being told the
--    temple thinks they are struggling; a false silence costs a conversation
--    that was not going to happen anyway. This is which way this file fails.
-- ---------------------------------------------------------------------------

do $$
declare
  v_w0 date := public.seva_mala_week_start(public.seva_mala_today());
  v_k integer;
begin
  for v_k in 0 .. 6 loop
    perform public.sb_serve('gopal', 'Pot Washing', v_w0 - (7 * v_k), 120, 5);
  end loop;
  -- Two hours from long before the quarter, so that "all time" and "this
  -- quarter" are different numbers and a window that quietly stopped windowing
  -- has somewhere to show up. Eighteen and twenty weeks back, which is not
  -- contiguous with his run and so leaves the streak at seven.
  perform public.sb_serve('gopal', 'Pot Washing', v_w0 - 140, 120, 1);
  perform public.sb_serve('gopal', 'Pot Washing', v_w0 - 126, 120, 1);
end;
$$;

-- Bhumi, on the six dates that are the window boundaries themselves. She is
-- here in section 2 rather than with the rest of the congregation because two
-- devotees are what makes the gathering rule provable: with one devotee there
-- is no distribution at all, and the rule below would pass for the wrong
-- reason.
do $$
declare
  v_w0 date := public.seva_mala_week_start(public.seva_mala_today());
  v_month date := public.seva_mala_period_start('month', public.seva_mala_today());
  v_quarter date := public.seva_balance_window_start();
begin
  perform public.sb_serve('bhumi', 'Temple Room Cleaning', v_w0, 60, 1);
  perform public.sb_serve('bhumi', 'Temple Room Cleaning', v_w0 - 1, 120, 1);
  perform public.sb_serve('bhumi', 'Temple Room Cleaning', v_month, 30, 1);
  perform public.sb_serve('bhumi', 'Temple Room Cleaning', v_month - 1, 90, 1);
  perform public.sb_serve('bhumi', 'Temple Room Cleaning', v_quarter, 150, 1);
  perform public.sb_serve('bhumi', 'Temple Room Cleaning', v_quarter - 1, 180, 1);
end;
$$;

do $$
declare
  v_refs record;
  v_rows integer;
begin
  select * into v_refs from public.seva_balance_references();
  if v_refs.devotees_considered <> 2 then
    raise exception 'Expected two serving devotees, found %.', v_refs.devotees_considered;
  end if;
  if not v_refs.gathering then
    raise exception 'Two serving devotees are not a congregation, yet gathering is false.';
  end if;

  -- The assertion that makes the two below mean something: against a
  -- congregation of two, the DERIVED thresholds do reach Gopal. Whatever keeps
  -- him out of the default call is therefore the gathering rule and nothing
  -- else — not a threshold that happened to sit above him.
  select count(*)::integer into v_rows
  from public.list_seva_concentration(
    p_min_weeks => v_refs.consecutive_weeks_threshold,
    p_min_hours => v_refs.weekly_hours_threshold) listed
  where listed.devotee_name = 'Gopal Das';
  if v_rows <> 1 then
    raise exception
      'The derived thresholds (% hours, % weeks) do not reach Gopal, so the gathering rule proves nothing.',
      v_refs.weekly_hours_threshold, v_refs.consecutive_weeks_threshold;
  end if;
  select count(*)::integer into v_rows
  from public.list_seva_narrowness(p_min_hours => v_refs.median_total_hours) listed
  where listed.devotee_name = 'Gopal Das';
  if v_rows <> 1 then
    raise exception 'The derived narrowness threshold does not reach Gopal either.';
  end if;

  -- ...and yet:
  select count(*)::integer into v_rows from public.list_seva_concentration();
  if v_rows <> 0 then
    raise exception 'A congregation of two produced % concentration rows.', v_rows;
  end if;
  select count(*)::integer into v_rows from public.list_seva_narrowness();
  if v_rows <> 0 then
    raise exception 'A congregation of two produced % narrowness rows.', v_rows;
  end if;

  -- The caller may still ask a question of their own, and gets an answer.
  select count(*)::integer into v_rows
  from public.list_seva_concentration(p_min_weeks => 2, p_min_hours => 5);
  if v_rows <> 1 then
    raise exception
      'Named thresholds should answer even while gathering; got % rows.', v_rows;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. The rest of the congregation.
-- ---------------------------------------------------------------------------

do $$
declare
  v_w0 date := public.seva_mala_week_start(public.seva_mala_today());
  v_k integer;
  v_i integer;
  v_type text;
begin
  -- Mira: the same ten hours a week, five ways. Six weeks, ending last week.
  for v_k in 1 .. 6 loop
    foreach v_type in array array[
      'Pot Washing', 'Temple Room Cleaning', 'Flower Garlands',
      'Kirtana Support', 'General Temple Service'
    ] loop
      -- Mira's seva is fully confirmed and earns Seva Mala points. Gopal's is
      -- not and earns none. Both are hours, and this file must not be able to
      -- tell them apart.
      perform public.sb_serve(
        'mira', v_type, v_w0 - (7 * v_k), 120, 1, 'member_verified', 'served');
    end loop;
  end loop;

  -- Ananda: five hours a week, every other week, and never once outside event.
  for v_k in 1 .. 11 by 2 loop
    perform public.sb_serve('ananda', 'Kirtana Support', v_w0 - (7 * v_k), 150, 1);
    perform public.sb_serve('ananda', 'Guest Welcome', v_w0 - (7 * v_k), 150, 1);
  end loop;

  -- The eight who make the distribution: three hours a week, alternating weeks,
  -- half in the kitchen and half at the front of the temple.
  for v_i in 1 .. 8 loop
    for v_k in 2 .. 12 by 2 loop
      perform public.sb_serve('f' || v_i, 'Pot Washing', v_w0 - (7 * v_k), 90, 1);
      perform public.sb_serve('f' || v_i, 'Kirtana Support', v_w0 - (7 * v_k), 90, 1);
    end loop;
  end loop;

  -- Purana served exactly as Gopal does, and stopped four months ago. He is not
  -- part of this congregation's trailing quarter at all, and every figure
  -- derived from the congregation must come out as though he were not there —
  -- while his own history stays whole.
  for v_k in 14 .. 20 loop
    perform public.sb_serve('purana', 'Pot Washing', v_w0 - (7 * v_k), 120, 5);
  end loop;

  -- Nishtha: eighteen hours of pot washing and half an hour of everything else.
  -- Nine tenths of her seva is in one category and she has still touched every
  -- category the temple serves, which is the case narrowness must not call
  -- narrow. Alternating weeks, so she never concentrates either.
  for v_k in 2 .. 12 by 2 loop
    perform public.sb_serve('nishtha', 'Pot Washing', v_w0 - (7 * v_k), 90, 2);
  end loop;
  foreach v_type in array array[
    'Temple Room Cleaning', 'Flower Garlands', 'Kirtana Support',
    'General Temple Service'
  ] loop
    perform public.sb_serve('nishtha', v_type, v_w0 - 14, 30, 1);
  end loop;
end;
$$;

-- Ananda also gives ten hours to a seva that has no service type at all — a
-- custom-named one somebody typed in. It has no category, and so it says
-- nothing whatever about whether he has ever swept a floor. It counts as hours
-- and it must not count as a category.
do $$
declare
  v_w0 date := public.seva_mala_week_start(public.seva_mala_today());
  v_k integer;
  v_instance uuid;
begin
  for v_k in 2 .. 10 by 2 loop
    insert into public.service_instances (
      service_type_id, custom_name, date, start_time, duration_minutes,
      slots_needed, participation_mode, posted_by, status
    ) values (
      null, 'Harinama Party', v_w0 - (7 * v_k), time '17:00', 120, 1,
      'open', null, 'completed'
    ) returning id into v_instance;

    insert into public.service_assignments (
      service_instance_id, devotee_id, assignment_method, status,
      verification, attendance, completed_at
    ) values (
      v_instance,
      (select ids.id from public.seva_balance_test_ids ids where ids.key = 'ananda'),
      'self_joined', 'completed', 'self_report', null,
      ((v_w0 - (7 * v_k)) + time '19:00') at time zone 'America/Chicago'
    );
  end loop;
end;
$$;

-- Ghost: forty hours that never happened.
do $$
declare
  v_w0 date := public.seva_mala_week_start(public.seva_mala_today());
  v_ghost uuid := (select ids.id from public.seva_balance_test_ids ids where ids.key = 'ghost');
  v_case record;
  v_instance uuid;
begin
  for v_case in
    select * from (values
      ('no_show',   'completed', null),
      ('completed', 'completed', 'absent'),
      ('withdrawn', 'completed', null),
      ('completed', 'cancelled', 'served')
    ) as c(assignment_status, instance_status, attendance)
  loop
    insert into public.service_instances (
      service_type_id, date, start_time, duration_minutes, slots_needed,
      participation_mode, posted_by, status
    ) values (
      (select service_types.id from public.service_types where service_types.name = 'Pot Washing'),
      v_w0 - 7, time '09:00', 600, 1, 'open', null, v_case.instance_status
    ) returning id into v_instance;

    insert into public.service_assignments (
      service_instance_id, devotee_id, assignment_method, status,
      verification, attendance, completed_at
    ) values (
      v_instance, v_ghost, 'self_joined', v_case.assignment_status,
      'self_report', v_case.attendance, now()
    );
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. What the congregation turns out to be.
--
--    Asserted before anything is concluded from it, so a fixture that has
--    drifted fails here and says so rather than failing as a mysteriously
--    absent devotee twenty assertions later.
-- ---------------------------------------------------------------------------

create table public.seva_balance_snapshots (
  label text not null,
  key text not null,
  value numeric,
  primary key (label, key)
);

insert into public.seva_balance_snapshots (label, key, value)
select 'first', refs.key, refs.value
from public.seva_balance_references() r
cross join lateral (values
  ('devotees', r.devotees_considered::numeric),
  ('median_weekly', r.median_weekly_hours),
  ('median_total', r.median_total_hours),
  ('median_top_share', r.median_top_share),
  ('hours_threshold', r.weekly_hours_threshold),
  ('weeks_threshold', r.consecutive_weeks_threshold::numeric),
  ('category_share_threshold', r.top_category_share_threshold)
) as refs(key, value);

do $$
declare
  v_refs record;
begin
  select * into v_refs from public.seva_balance_references();

  -- Thirteen devotees served IN THE WINDOW. Not Ghost, whose forty hours never
  -- happened; not Purana, whose seventy happened four months ago; not the four
  -- who hold roles and serve nothing.
  if v_refs.devotees_considered <> 13 then
    raise exception '% devotees served, expected 13.', v_refs.devotees_considered;
  end if;
  if v_refs.gathering then
    raise exception 'Thirteen serving devotees and still gathering.';
  end if;

  -- The eight fillers at three hours a week are the middle of this
  -- congregation, and the median says so.
  if v_refs.median_weekly_hours <> 3 then
    raise exception 'Median weekly load is % rather than 3 hours.', v_refs.median_weekly_hours;
  end if;
  if v_refs.median_total_hours <> 18 then
    raise exception 'Median total is % rather than 18 hours.', v_refs.median_total_hours;
  end if;

  -- 3 h/week × 1.5 = 4.5, and the congregation's own 85th percentile of
  -- single-seva weekly hours is below that, so the multiple is what binds.
  if v_refs.weekly_hours_threshold <> 4.5 then
    raise exception 'Hours threshold is % rather than 4.5.', v_refs.weekly_hours_threshold;
  end if;
  if v_refs.weekly_hours_threshold <= v_refs.median_weekly_hours then
    raise exception 'The threshold is not above the median it is derived from.';
  end if;

  if v_refs.consecutive_weeks_threshold < 2 then
    raise exception
      'Weeks threshold is %; one week is not consecutive weeks.', v_refs.consecutive_weeks_threshold;
  end if;

  if v_refs.window_starts_on
     <> public.seva_mala_week_start(public.seva_mala_today()) - 84 then
    raise exception 'The window is not thirteen weeks: % .', v_refs.window_starts_on;
  end if;
  if v_refs.window_ends_on <> (now() at time zone 'America/Chicago')::date then
    raise exception 'The window does not end on Chicago''s today.';
  end if;

  if v_refs.congregation_categories
     is distinct from array['cleaning', 'deity-worship', 'event', 'kitchen', 'other'] then
    raise exception 'The congregation serves %, which is not the fixture.',
      v_refs.congregation_categories;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Gopal, seva by seva.
-- ---------------------------------------------------------------------------

do $$
declare
  v_row record;
  v_rows integer;
  v_expected_month numeric;
begin
  select count(*)::integer into v_rows
  from public.seva_balance_for_devotee(
    (select ids.id from public.seva_balance_test_ids ids where ids.key = 'gopal'));
  if v_rows <> 1 then
    raise exception 'Gopal does one seva; % rows came back.', v_rows;
  end if;

  select * into v_row
  from public.seva_balance_for_devotee(
    (select ids.id from public.seva_balance_test_ids ids where ids.key = 'gopal'));

  if v_row.seva_name <> 'Pot Washing' or v_row.category <> 'kitchen' then
    raise exception 'Gopal''s seva reads % / %.', v_row.seva_name, v_row.category;
  end if;
  -- Seven weeks of ten hours, and the current week is one of them.
  if v_row.hours_this_week <> 10 then
    raise exception 'This week reads % rather than 10 hours.', v_row.hours_this_week;
  end if;
  -- Seventy in the quarter and seventy-four since he began: the two windows
  -- are different numbers, so neither assertion can pass by standing in for
  -- the other.
  if v_row.hours_trailing_quarter <> 70 or v_row.hours_all_time <> 74 then
    raise exception 'The quarter reads % and all time %.',
      v_row.hours_trailing_quarter, v_row.hours_all_time;
  end if;
  if v_row.share_of_their_seva <> 1 then
    raise exception 'Gopal does nothing else, yet his share reads %.', v_row.share_of_their_seva;
  end if;
  if v_row.consecutive_weeks <> 7 then
    raise exception 'Gopal has run % weeks rather than 7.', v_row.consecutive_weeks;
  end if;
  if v_row.acts_trailing_quarter <> 35 then
    raise exception 'Gopal served % acts rather than 35.', v_row.acts_trailing_quarter;
  end if;
  -- Twenty weeks ago, which is outside the window the hours are counted over.
  -- "They have been doing this since March" is often the sentence that turns a
  -- worry into a happy shrug, and a function that only remembers a quarter
  -- cannot say it.
  if v_row.first_served_on
     <> public.seva_mala_week_start(public.seva_mala_today()) - 140 then
    raise exception 'Gopal first served on %.', v_row.first_served_on;
  end if;
  if v_row.last_served_on
     <> public.seva_mala_week_start(public.seva_mala_today()) then
    raise exception 'Gopal last served on %.', v_row.last_served_on;
  end if;

  -- The month is Chicago's month. Computed from the fixture rows rather than
  -- from a second copy of the function's own arithmetic.
  select coalesce(sum(instances.duration_minutes), 0) / 60.0 into v_expected_month
  from public.service_assignments assignments
  join public.service_instances instances
    on instances.id = assignments.service_instance_id
  where assignments.devotee_id
        = (select ids.id from public.seva_balance_test_ids ids where ids.key = 'gopal')
    and instances.date >= date_trunc('month', (now() at time zone 'America/Chicago')::date)::date;
  if v_row.hours_this_month <> v_expected_month then
    raise exception 'The month reads % rather than %.', v_row.hours_this_month, v_expected_month;
  end if;
end;
$$;

-- The hours this feature reads are NOT the hours Seva Mala credits.
--
-- Gopal's thirty-five acts are completed, self-reported and unconfirmed, which
-- since 202608040057 earns exactly nothing: his Seva Mala credited minutes are
-- zero and his standing is empty. He has still washed pots for seventy hours,
-- and it is still the middle of the night when he does it. This assertion is
-- the one that fails if somebody ever "tidies" seva_balance_acts to filter on
-- quality, and its failure mode without it is the worst kind — a report that
-- returns cleanly and sees nobody.
do $$
declare
  v_credited numeric;
  v_balance numeric;
begin
  select coalesce(sum(acts.credited_minutes), 0) into v_credited
  from public.seva_mala_acts(
    (select ids.id from public.seva_balance_test_ids ids where ids.key = 'gopal')) acts;
  select sum(balance.hours_trailing_quarter) into v_balance
  from public.seva_balance_for_devotee(
    (select ids.id from public.seva_balance_test_ids ids where ids.key = 'gopal')) balance;

  if v_credited <> 0 then
    raise exception
      'Gopal''s unconfirmed seva now earns % credited minutes; the contrast is gone.', v_credited;
  end if;
  if v_balance <> 70 then
    raise exception
      'Gopal earns no points and served 70 hours this quarter, yet seva balance reads % — this feature is reading eligibility instead of hours.',
      v_balance;
  end if;

  -- ...and Mira's confirmed acts are counted by both, so this is not a rule
  -- that only works for unconfirmed seva.
  select coalesce(sum(acts.credited_minutes), 0) into v_credited
  from public.seva_mala_acts(
    (select ids.id from public.seva_balance_test_ids ids where ids.key = 'mira')) acts;
  if v_credited <= 0 then
    raise exception 'Mira''s fully confirmed seva earns no credited minutes.';
  end if;
end;
$$;

-- Bhumi's boundaries. Every figure is checked against a sum taken from the
-- fixture rows themselves, and each window is proved to be excluding something
-- so that none of the four assertions can pass vacuously.
do $$
declare
  v_row record;
  v_bhumi uuid := (select ids.id from public.seva_balance_test_ids ids where ids.key = 'bhumi');
  v_w0 date := public.seva_mala_week_start(public.seva_mala_today());
  v_month date := date_trunc('month', (now() at time zone 'America/Chicago')::date)::date;
  v_quarter date := v_w0 - 84;
  v_week_h numeric;
  v_month_h numeric;
  v_quarter_h numeric;
  v_all_h numeric;
begin
  select
    sum(instances.duration_minutes) filter (where instances.date >= v_w0) / 60.0,
    sum(instances.duration_minutes) filter (where instances.date >= v_month) / 60.0,
    sum(instances.duration_minutes) filter (where instances.date >= v_quarter) / 60.0,
    sum(instances.duration_minutes) / 60.0
  into v_week_h, v_month_h, v_quarter_h, v_all_h
  from public.service_assignments assignments
  join public.service_instances instances
    on instances.id = assignments.service_instance_id
  where assignments.devotee_id = v_bhumi;

  if v_all_h <> 10.5 then
    raise exception 'Bhumi served % hours rather than 10.5.', v_all_h;
  end if;
  -- Each window must be leaving something out, or it is proving nothing.
  if not (v_week_h < v_all_h and v_month_h < v_all_h and v_quarter_h < v_all_h) then
    raise exception 'Bhumi''s boundary acts do not straddle the windows.';
  end if;

  select * into v_row from public.seva_balance_for_devotee(v_bhumi);
  if v_row.hours_this_week <> v_week_h then
    raise exception 'Bhumi''s week reads % rather than %.', v_row.hours_this_week, v_week_h;
  end if;
  if v_row.hours_this_month <> v_month_h then
    raise exception 'Bhumi''s month reads % rather than %.', v_row.hours_this_month, v_month_h;
  end if;
  if v_row.hours_trailing_quarter <> v_quarter_h then
    raise exception 'Bhumi''s quarter reads % rather than %.',
      v_row.hours_trailing_quarter, v_quarter_h;
  end if;
  if v_row.hours_all_time <> v_all_h then
    raise exception 'Bhumi''s lifetime reads % rather than %.', v_row.hours_all_time, v_all_h;
  end if;
  -- Her first act is older than the window, and the window did not forget it.
  if v_row.first_served_on <> v_quarter - 1 then
    raise exception 'Bhumi first served on % rather than %.', v_row.first_served_on, v_quarter - 1;
  end if;
end;
$$;

-- Ghost. Forty hours of no-show, absence, withdrawal and a cancelled seva.
do $$
declare
  v_rows integer;
begin
  select count(*)::integer into v_rows
  from public.seva_balance_for_devotee(
    (select ids.id from public.seva_balance_test_ids ids where ids.key = 'ghost'));
  if v_rows <> 0 then
    raise exception 'Ghost''s forty hours that never happened produced % rows.', v_rows;
  end if;
end;
$$;

-- Purana. Seventy hours of exactly Gopal's pattern, finished four months ago.
-- His history is whole and the quarter is empty, and he is nobody's concern.
do $$
declare
  v_row record;
begin
  select * into v_row
  from public.seva_balance_for_devotee(
    (select ids.id from public.seva_balance_test_ids ids where ids.key = 'purana'));

  if v_row.hours_all_time <> 70 then
    raise exception 'Purana''s history reads % hours rather than 70.', v_row.hours_all_time;
  end if;
  if v_row.hours_trailing_quarter <> 0 then
    raise exception
      'Purana has served nothing in thirteen weeks, yet the quarter reads %.',
      v_row.hours_trailing_quarter;
  end if;
  if v_row.consecutive_weeks <> 0 then
    raise exception 'Purana reads % weeks running, four months after he stopped.',
      v_row.consecutive_weeks;
  end if;
  if exists (
    select 1 from public.list_seva_concentration() listed
    where listed.devotee_name = 'Purana Das'
  ) or exists (
    select 1 from public.list_seva_narrowness() listed
    where listed.devotee_name = 'Purana Das'
  ) then
    raise exception 'Purana was surfaced for seva he finished four months ago.';
  end if;
end;
$$;

-- Ananda's Harinama Party has no service type and therefore no category. It is
-- ten real hours and it is not evidence about anything.
do $$
declare
  v_custom record;
  v_total numeric;
  v_narrow numeric;
begin
  select * into v_custom
  from public.seva_balance_for_devotee(
    (select ids.id from public.seva_balance_test_ids ids where ids.key = 'ananda')) balance
  where balance.seva_name = 'Harinama Party';

  if v_custom.seva_name is null then
    raise exception 'A custom-named seva is not seva; ten hours went missing.';
  end if;
  if v_custom.service_type_id is not null or v_custom.category is not null then
    raise exception 'The custom seva acquired a type or a category.';
  end if;
  if v_custom.hours_trailing_quarter <> 10 then
    raise exception 'The custom seva reads % hours rather than 10.',
      v_custom.hours_trailing_quarter;
  end if;

  select sum(balance.hours_trailing_quarter) into v_total
  from public.seva_balance_for_devotee(
    (select ids.id from public.seva_balance_test_ids ids where ids.key = 'ananda')) balance;
  select listed.hours_trailing_quarter into v_narrow
  from public.list_seva_narrowness() listed where listed.devotee_name = 'Ananda Das';

  -- Forty hours of seva, thirty of them in a category. Narrowness speaks only
  -- of the thirty, because the other ten say nothing about whether he has ever
  -- swept a floor — and if they were counted as a category of their own he
  -- would stop looking narrow while having done nothing differently.
  if v_total <> 40 then
    raise exception 'Ananda served % hours rather than 40.', v_total;
  end if;
  if v_narrow <> 30 then
    raise exception 'Narrowness reads % of Ananda''s hours rather than 30.', v_narrow;
  end if;
end;
$$;

-- Nishtha does nine tenths of her seva in the kitchen and has still done a
-- little of everything. Neither list wants her.
do $$
begin
  if exists (
    select 1 from public.list_seva_concentration() listed
    where listed.devotee_name = 'Nishtha Das'
  ) then
    raise exception 'Nishtha was surfaced for three hours a week.';
  end if;
  if exists (
    select 1 from public.list_seva_narrowness() listed
    where listed.devotee_name = 'Nishtha Das'
  ) then
    raise exception 'Nishtha has touched every category the temple serves.';
  end if;
end;
$$;

-- A named devotee is required. A null must not quietly hand back the whole
-- congregation's hours in one call.
do $$
declare
  v_rows integer;
begin
  select count(*)::integer into v_rows from public.seva_balance_for_devotee(null);
  if v_rows <> 0 then
    raise exception 'seva_balance_for_devotee(null) returned % rows.', v_rows;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. The pair this file exists for.
-- ---------------------------------------------------------------------------

do $$
declare
  v_row record;
  v_rows integer;
  v_names text;
begin
  select string_agg(listed.devotee_name, ', ' order by listed.devotee_name)
  into v_names
  from public.list_seva_concentration() listed;

  if v_names is distinct from 'Gopal Das' then
    raise exception
      'Concentration surfaced [%] — it must be Gopal alone. Mira serves exactly as many hours a week as he does.',
      coalesce(v_names, '(nobody)');
  end if;

  select * into v_row from public.list_seva_concentration();
  if v_row.seva_name <> 'Pot Washing' then
    raise exception 'Gopal was surfaced for %.', v_row.seva_name;
  end if;
  if v_row.hours_per_week <> 10 then
    raise exception 'Gopal reads % hours a week rather than 10.', v_row.hours_per_week;
  end if;
  if v_row.consecutive_weeks <> 7 then
    raise exception 'Gopal reads % weeks running.', v_row.consecutive_weeks;
  end if;
  if v_row.share_of_their_seva <> 1 then
    raise exception 'Gopal''s share reads %.', v_row.share_of_their_seva;
  end if;
  -- The thresholds that surfaced him travel with the row, so a President can
  -- always ask "compared to what?".
  if v_row.min_hours_used <> 4.5 then
    raise exception 'The row reports a threshold of % rather than 4.5.', v_row.min_hours_used;
  end if;
  if v_row.weekly_hours_vs_median is null
     or v_row.weekly_hours_vs_median <> round(10 / 3.0, 2) then
    raise exception 'Gopal reads % times the median weekly load.', v_row.weekly_hours_vs_median;
  end if;
  if v_row.pronouncedness <= 1 then
    raise exception 'Anything surfaced is at or above one on both gates; got %.',
      v_row.pronouncedness;
  end if;

  -- The note is the point of the whole function: a President reads English and
  -- goes to ask a question.
  if v_row.note not like '%Gopal Das has given 10.0 hours a week to Pot Washing for 7 weeks running%'
     or v_row.note not like '%100%% of their seva%'
     or v_row.note not like '%they have been doing it since %'
     or v_row.note not like '%Worth asking how they are finding it%' then
    raise exception 'The note reads: %', v_row.note;
  end if;
  -- Nothing in it may read as an instruction, a verdict or a diagnosis.
  if v_row.note ~* '(burn ?out|overwork|problem|violation|flag|warn|must |remove them|too much)' then
    raise exception 'The note reads as a verdict rather than a conversation: %', v_row.note;
  end if;

  -- Mira, explicitly, because "not in the list" is the assertion that a change
  -- to the gate would break first.
  select count(*)::integer into v_rows
  from public.list_seva_concentration() listed
  where listed.devotee_id
        = (select ids.id from public.seva_balance_test_ids ids where ids.key = 'mira');
  if v_rows <> 0 then
    raise exception 'Mira spreads ten hours over five sevas and was surfaced anyway.';
  end if;
end;
$$;

-- Mira and Gopal really do carry the same weekly load. If this ever stops
-- being true the contrast above is proving nothing.
do $$
declare
  v_gopal numeric;
  v_mira numeric;
begin
  select sum(balance.hours_trailing_quarter) into v_gopal
  from public.seva_balance_for_devotee(
    (select ids.id from public.seva_balance_test_ids ids where ids.key = 'gopal')) balance;
  select sum(balance.hours_trailing_quarter) into v_mira
  from public.seva_balance_for_devotee(
    (select ids.id from public.seva_balance_test_ids ids where ids.key = 'mira')) balance;
  if v_mira < v_gopal * 0.8 then
    raise exception
      'Mira gives % hours against Gopal''s %; the contrast is no longer a contrast.',
      v_mira, v_gopal;
  end if;
  -- Five sevas, none of them dominant.
  if (select max(balance.share_of_their_seva)
      from public.seva_balance_for_devotee(
        (select ids.id from public.seva_balance_test_ids ids where ids.key = 'mira')) balance) > 0.25
  then
    raise exception 'Mira is no longer evenly spread.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. The inverse.
-- ---------------------------------------------------------------------------

do $$
declare
  v_row record;
  v_names text;
begin
  select string_agg(listed.devotee_name, ', ' order by listed.devotee_name)
  into v_names
  from public.list_seva_narrowness() listed;

  -- Ananda has never done anything but event seva. Gopal has never done
  -- anything but the kitchen, and is correctly in both lists — the two shapes
  -- are not exclusive and a devotee can be an instance of each.
  if v_names is distinct from 'Ananda Das, Gopal Das' then
    raise exception 'Narrowness surfaced [%], expected Ananda and Gopal.',
      coalesce(v_names, '(nobody)');
  end if;

  select * into v_row from public.list_seva_narrowness() listed
  where listed.devotee_name = 'Ananda Das';

  if v_row.category <> 'event' then
    raise exception 'Ananda''s category reads %.', v_row.category;
  end if;
  if v_row.category_share <> 1 then
    raise exception 'Ananda has done nothing else, yet his share reads %.', v_row.category_share;
  end if;
  if v_row.untouched_categories
     is distinct from array['cleaning', 'deity-worship', 'kitchen', 'other'] then
    raise exception 'Ananda has untouched %.', v_row.untouched_categories;
  end if;
  if v_row.untouched_share_of_congregation <= 0
     or v_row.untouched_share_of_congregation >= 1 then
    raise exception 'The untouched share of the congregation reads %.',
      v_row.untouched_share_of_congregation;
  end if;
  if v_row.note not like '%none at all to cleaning, deity-worship, kitchen, other%'
     or v_row.note not like '%Not a problem in itself%' then
    raise exception 'Ananda''s note reads: %', v_row.note;
  end if;

  -- Ananda is emphatically NOT a concentration case: five hours a week across
  -- two sevas, every other week. Narrowness is a different question and this
  -- is the devotee who proves the two are not the same list.
  if exists (
    select 1 from public.list_seva_concentration() listed
    where listed.devotee_name = 'Ananda Das'
  ) then
    raise exception 'Ananda was surfaced as a concentration case.';
  end if;

  -- Mira touches all five categories.
  if exists (
    select 1 from public.list_seva_narrowness() listed
    where listed.devotee_name = 'Mira Das'
  ) then
    raise exception 'Mira serves all five categories and was called narrow.';
  end if;

  -- The eight fillers serve two categories evenly and are not narrow either.
  if exists (
    select 1 from public.list_seva_narrowness() listed
    where listed.devotee_name like 'Filler%'
  ) then
    raise exception 'A filler was called narrow.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. Who may read any of this.
--
--    app.view_all, which is the President and the Tech Admin. NOT a Community
--    Head: services.manage_recurring is the authority to run a rota, and this
--    is a reading of how tired somebody is. Every refusal below is attempted
--    as the devotee who would really attempt it, under the authenticated role.
-- ---------------------------------------------------------------------------

create table public.seva_balance_seen (
  who text not null,
  what text not null,
  rows integer not null,
  primary key (who, what)
);
grant select, insert on public.seva_balance_seen to authenticated;

do $$
declare
  v_who text;
begin
  foreach v_who in array array['prez', 'tech', 'head', 'plain', 'gopal'] loop
    execute format(
      'select set_config(''request.jwt.claim.sub'', %L, true)',
      (select ids.id from public.seva_balance_test_ids ids where ids.key = v_who)
    );
    set local role authenticated;

    -- Said out loud: these reads are made with the rights a phone has, not the
    -- rights a migration has. A refusal proved under superuser proves nothing.
    if current_user <> 'authenticated' then
      raise exception 'The refusals are being attempted as %, not authenticated.', current_user;
    end if;

    insert into public.seva_balance_seen (who, what, rows)
    select v_who, 'concentration', count(*)::integer from public.list_seva_concentration();
    insert into public.seva_balance_seen (who, what, rows)
    select v_who, 'narrowness', count(*)::integer from public.list_seva_narrowness();
    insert into public.seva_balance_seen (who, what, rows)
    select v_who, 'thresholds', count(*)::integer from public.seva_balance_thresholds();
    insert into public.seva_balance_seen (who, what, rows)
    select v_who, 'balance_other', count(*)::integer
    from public.seva_balance_for_devotee(
      (select ids.id from public.seva_balance_test_ids ids where ids.key = 'gopal'));
    insert into public.seva_balance_seen (who, what, rows)
    select v_who, 'own', count(*)::integer from public.my_seva_balance();

    reset role;
  end loop;
  -- Back to the President, who is who the rest of this script is.
  perform set_config('request.jwt.claim.sub',
    (select ids.id::text from public.seva_balance_test_ids ids where ids.key = 'prez'), true);
end;
$$;

do $$
declare
  v_row record;
begin
  for v_row in
    select * from public.seva_balance_seen order by who, what
  loop
    if v_row.who in ('prez', 'tech') then
      if v_row.what <> 'own' and v_row.rows = 0 then
        raise exception '% sees nothing of %, and holds app.view_all.', v_row.who, v_row.what;
      end if;
    else
      if v_row.what <> 'own' and v_row.rows <> 0 then
        raise exception
          '% has no app.view_all and read % rows of % — this is another devotee''s tiredness.',
          v_row.who, v_row.rows, v_row.what;
      end if;
    end if;
  end loop;

  -- The Community Head, said out loud, because this is the distinction the
  -- feature was asked to be deliberate about.
  if (select seen.rows from public.seva_balance_seen seen
      where seen.who = 'head' and seen.what = 'concentration') <> 0 then
    raise exception 'A Community Head read the concentration list.';
  end if;

  -- Gopal, who IS on the list, cannot see the list he is on.
  if (select seen.rows from public.seva_balance_seen seen
      where seen.who = 'gopal' and seen.what = 'concentration') <> 0 then
    raise exception 'The devotee on the list can read the list.';
  end if;
  -- ...but his own hours are his own.
  if (select seen.rows from public.seva_balance_seen seen
      where seen.who = 'gopal' and seen.what = 'own') <> 1 then
    raise exception 'Gopal cannot see his own seva.';
  end if;
  -- Plain has served nothing, so her own view is empty rather than forbidden.
  if (select seen.rows from public.seva_balance_seen seen
      where seen.who = 'plain' and seen.what = 'own') <> 0 then
    raise exception 'Plain has served nothing yet sees seva.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 9. What Gopal sees of himself.
--
--    A thank-you note. Recorded here so that section 12 can prove it does not
--    move when the congregation moves — which is the whole of the promise that
--    nothing in a devotee's own view says they have been noticed.
-- ---------------------------------------------------------------------------

create table public.seva_balance_own (
  label text not null,
  seva_name text not null,
  hours_month numeric,
  hours_quarter numeric,
  hours_all numeric,
  acts integer,
  primary key (label, seva_name)
);
grant select, insert on public.seva_balance_own to authenticated;

select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.seva_balance_test_ids ids where ids.key = 'gopal'), true);
set local role authenticated;

insert into public.seva_balance_own (label, seva_name, hours_month, hours_quarter, hours_all, acts)
select 'before', mine.seva_name, mine.hours_this_month, mine.hours_this_quarter,
       mine.hours_all_time, mine.acts_all_time
from public.my_seva_balance() mine;

reset role;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.seva_balance_test_ids ids where ids.key = 'prez'), true);

do $$
declare
  v_row record;
begin
  select * into v_row from public.seva_balance_own where label = 'before';
  if v_row.seva_name <> 'Pot Washing' or v_row.hours_all <> 74 or v_row.acts <> 37 then
    raise exception 'Gopal''s own view reads % / % hours / % acts.',
      v_row.seva_name, v_row.hours_all, v_row.acts;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 10. Parameters, when the temple wants to ask its own question.
-- ---------------------------------------------------------------------------

do $$
declare
  v_rows integer;
begin
  -- A threshold below Mira's per-seva load reaches her, which is how a
  -- coordinator asks a wider question on purpose rather than by accident.
  select count(*)::integer into v_rows
  from public.list_seva_concentration(p_min_weeks => 2, p_min_hours => 1.5) listed
  where listed.devotee_name = 'Mira Das';
  if v_rows = 0 then
    raise exception 'An explicit threshold of 1.5 hours a week did not reach Mira.';
  end if;

  -- ...and the row says which threshold produced it.
  if (select min(listed.min_hours_used)
      from public.list_seva_concentration(p_min_weeks => 2, p_min_hours => 1.5) listed) <> 1.5
  then
    raise exception 'The named threshold is not what the rows report.';
  end if;

  -- A run of nine weeks is longer than anybody here has run.
  select count(*)::integer into v_rows
  from public.list_seva_concentration(p_min_weeks => 9, p_min_hours => 1);
  if v_rows <> 0 then
    raise exception 'Nine consecutive weeks surfaced % rows.', v_rows;
  end if;
end;
$$;

-- A bad parameter must be refused BY NAME. Checking only that something was
-- raised would pass on a division by zero four hundred lines later, which is
-- the same bug wearing a worse error message.
do $$
declare
  v_message text;
begin
  v_message := '(nothing)';
  begin
    perform * from public.list_seva_concentration(p_min_weeks => 0);
  exception when others then v_message := sqlerrm;
  end;
  if v_message not like '%at least one week%' then
    raise exception 'Zero weeks was answered with: %', v_message;
  end if;

  v_message := '(nothing)';
  begin
    perform * from public.list_seva_concentration(p_min_hours => 0);
  exception when others then v_message := sqlerrm;
  end;
  if v_message not like '%hours a week to look above must be more than zero%' then
    raise exception 'Zero hours a week was answered with: %', v_message;
  end if;

  v_message := '(nothing)';
  begin
    perform * from public.list_seva_narrowness(p_min_hours => -1);
  exception when others then v_message := sqlerrm;
  end;
  if v_message not like '%hours to look above must be more than zero%' then
    raise exception 'A negative number of hours was answered with: %', v_message;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 11. A streak that ended is not a streak.
--
--    Chandra washed pots every week for eight weeks and stopped two months
--    ago. Eight weeks running is true of last spring and false of today, and a
--    coordinator sent to ask a devotee how they are coping with a seva they no
--    longer do is a coordinator who will not be sent again.
-- ---------------------------------------------------------------------------

insert into auth.users (id, email, raw_user_meta_data)
values ('5b000000-0000-0000-0000-000000000030', 'sb-chandra@example.test',
        '{"name":"Chandra Das"}');
insert into public.seva_balance_test_ids (key, id)
values ('chandra', '5b000000-0000-0000-0000-000000000030');

do $$
declare
  v_w0 date := public.seva_mala_week_start(public.seva_mala_today());
  v_k integer;
begin
  for v_k in 5 .. 12 loop
    perform public.sb_serve('chandra', 'Pot Washing', v_w0 - (7 * v_k), 120, 5);
  end loop;
end;
$$;

do $$
declare
  v_row record;
begin
  select * into v_row
  from public.seva_balance_for_devotee(
    (select ids.id from public.seva_balance_test_ids ids where ids.key = 'chandra'));

  if v_row.hours_trailing_quarter <> 80 then
    raise exception 'Chandra served % hours rather than 80.', v_row.hours_trailing_quarter;
  end if;
  if v_row.consecutive_weeks <> 0 then
    raise exception
      'Chandra stopped five weeks ago, yet reads % weeks running.', v_row.consecutive_weeks;
  end if;
  if exists (
    select 1 from public.list_seva_concentration() listed
    where listed.devotee_name = 'Chandra Das'
  ) then
    raise exception 'Chandra was surfaced for a seva he has not done in five weeks.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 12. The thresholds are the congregation's.
--
--    Fifteen devotees arrive, each serving twenty-five hours a week across
--    five sevas for twelve weeks. Not one act of Gopal's changes. Not one hour
--    of his changes. He is no longer surfaced, because ten hours a week of one
--    seva is an ordinary week in this congregation and an extraordinary one in
--    the last. That is the difference between a threshold and a constant, and
--    it is the assertion a hardcoded twelve hours could not pass.
-- ---------------------------------------------------------------------------

do $$
declare
  v_i integer;
  v_k integer;
  v_type text;
  v_w0 date := public.seva_mala_week_start(public.seva_mala_today());
begin
  for v_i in 1 .. 15 loop
    insert into auth.users (id, email, raw_user_meta_data)
    values (
      ('5b000000-0000-0000-0000-0000000000' || lpad((30 + v_i)::text, 2, '0'))::uuid,
      'sb-heavy' || v_i || '@example.test',
      jsonb_build_object('name', 'Heavy ' || v_i)
    );
    insert into public.seva_balance_test_ids (key, id)
    values ('heavy' || v_i,
      ('5b000000-0000-0000-0000-0000000000' || lpad((30 + v_i)::text, 2, '0'))::uuid);

    for v_k in 1 .. 12 loop
      foreach v_type in array array[
        'Pot Washing', 'Temple Room Cleaning', 'Flower Garlands',
        'Kirtana Support', 'General Temple Service'
      ] loop
        perform public.sb_serve('heavy' || v_i, v_type, v_w0 - (7 * v_k), 300, 1);
      end loop;
    end loop;
  end loop;
end;
$$;

insert into public.seva_balance_snapshots (label, key, value)
select 'after', refs.key, refs.value
from public.seva_balance_references() r
cross join lateral (values
  ('devotees', r.devotees_considered::numeric),
  ('median_weekly', r.median_weekly_hours),
  ('median_total', r.median_total_hours),
  ('median_top_share', r.median_top_share),
  ('hours_threshold', r.weekly_hours_threshold),
  ('weeks_threshold', r.consecutive_weeks_threshold::numeric),
  ('category_share_threshold', r.top_category_share_threshold)
) as refs(key, value);

do $$
declare
  v_before numeric;
  v_after numeric;
  v_gopal_hours numeric;
begin
  -- Gopal is untouched.
  select sum(balance.hours_trailing_quarter) into v_gopal_hours
  from public.seva_balance_for_devotee(
    (select ids.id from public.seva_balance_test_ids ids where ids.key = 'gopal')) balance;
  if v_gopal_hours <> 70 then
    raise exception 'Gopal now reads % hours; the experiment has changed him.', v_gopal_hours;
  end if;

  select value into v_before from public.seva_balance_snapshots
  where label = 'first' and key = 'hours_threshold';
  select value into v_after from public.seva_balance_snapshots
  where label = 'after' and key = 'hours_threshold';
  if v_after <= v_before then
    raise exception
      'The hours threshold went from % to % in a congregation that now serves eight times as much.',
      v_before, v_after;
  end if;
  if v_after <= 10 then
    raise exception
      'The threshold is % and Gopal serves 10 hours a week; the experiment cannot conclude anything.',
      v_after;
  end if;

  select value into v_before from public.seva_balance_snapshots
  where label = 'first' and key = 'weeks_threshold';
  select value into v_after from public.seva_balance_snapshots
  where label = 'after' and key = 'weeks_threshold';
  if v_after <= v_before then
    raise exception 'The weeks threshold did not move: % then %.', v_before, v_after;
  end if;

  select value into v_before from public.seva_balance_snapshots
  where label = 'first' and key = 'median_weekly';
  select value into v_after from public.seva_balance_snapshots
  where label = 'after' and key = 'median_weekly';
  if v_after <= v_before then
    raise exception 'The median weekly load did not move: % then %.', v_before, v_after;
  end if;

  -- And so Gopal falls out of the list, having done nothing differently.
  if exists (
    select 1 from public.list_seva_concentration() listed
    where listed.devotee_name = 'Gopal Das'
  ) then
    raise exception
      'Gopal is still surfaced against a congregation that now serves 25 hours a week each.';
  end if;

  -- The temple can still ask the old question, and gets the old answer.
  if not exists (
    select 1 from public.list_seva_concentration(p_min_weeks => 2, p_min_hours => 4.5) listed
    where listed.devotee_name = 'Gopal Das'
  ) then
    raise exception 'The old threshold, named explicitly, no longer reaches Gopal.';
  end if;
end;
$$;

-- And Gopal's own view did not move by a single hour, because nothing a
-- coordinator sees is wired to anything a devotee sees.
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.seva_balance_test_ids ids where ids.key = 'gopal'), true);
set local role authenticated;

insert into public.seva_balance_own (label, seva_name, hours_month, hours_quarter, hours_all, acts)
select 'after', mine.seva_name, mine.hours_this_month, mine.hours_this_quarter,
       mine.hours_all_time, mine.acts_all_time
from public.my_seva_balance() mine;

reset role;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.seva_balance_test_ids ids where ids.key = 'prez'), true);

do $$
declare
  v_differences integer;
begin
  select count(*)::integer into v_differences
  from public.seva_balance_own before
  full join public.seva_balance_own after
    on after.label = 'after' and after.seva_name = before.seva_name
  where before.label = 'before'
    and (after.seva_name is null
      or before.hours_month is distinct from after.hours_month
      or before.hours_quarter is distinct from after.hours_quarter
      or before.hours_all is distinct from after.hours_all
      or before.acts is distinct from after.acts);
  if v_differences <> 0 then
    raise exception
      'Gopal''s own screen changed when he stopped being surfaced. A devotee must not be able to read a coordinator''s list off their own hours.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 13. The heavy fifteen are not themselves a problem.
--
--    Twenty-five hours a week each, and not one of them surfaced: five sevas
--    apiece in five categories is not concentration and is not narrowness,
--    however many hours it adds up to. This is the file refusing to mistake
--    "gives a great deal" for "is carrying too much of one thing".
-- ---------------------------------------------------------------------------

do $$
begin
  if exists (
    select 1 from public.list_seva_concentration() listed
    where listed.devotee_name like 'Heavy%'
  ) then
    raise exception 'A devotee giving twenty-five hours a week over five sevas was surfaced.';
  end if;
  if exists (
    select 1 from public.list_seva_narrowness() listed
    where listed.devotee_name like 'Heavy%'
  ) then
    raise exception 'A devotee serving all five categories was called narrow.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 14. Narrow, and having touched everything.
--
--     The one gate the fixture above cannot reach on its own. This
--     congregation's ninetieth percentile of top-category share is exactly 1.0
--     — several devotees serve one category and nothing else — so the derived
--     share threshold is 1.0, and at 1.0 a devotee with no untouched category
--     is arithmetically impossible.
--
--     A temple that turns its quantile down is a supported configuration and
--     not a hypothetical: the dials are the temple's. Turned down, the
--     threshold falls to its floor, Nishtha's nine tenths clears it, and the
--     only thing standing between her and a coordinator's list is the rule that
--     you cannot be told off for never doing something you have done. This
--     also proves the quantile is read from app_settings rather than typed in.
-- ---------------------------------------------------------------------------

update public.app_settings set value = '0.10'
where key = 'seva_balance.category_share_quantile';

do $$
declare
  v_refs record;
  v_share numeric;
  v_hours numeric;
begin
  select * into v_refs from public.seva_balance_references();
  if v_refs.top_category_share_threshold <> 0.9 then
    raise exception
      'The share threshold is % rather than falling to its floor; the dial is not being read.',
      v_refs.top_category_share_threshold;
  end if;

  -- Nishtha clears both gates that remain.
  select
    max(by_category.minutes) / sum(by_category.minutes),
    sum(by_category.minutes) / 60.0
  into v_share, v_hours
  from (
    select acts.category, sum(acts.served_minutes) as minutes
    from public.seva_balance_acts(
      (select ids.id from public.seva_balance_test_ids ids where ids.key = 'nishtha')) acts
    where acts.occurred_on >= public.seva_balance_window_start()
      and acts.category is not null
    group by acts.category
  ) by_category;

  if v_share < v_refs.top_category_share_threshold or v_hours < 10 then
    raise exception
      'Nishtha is at % share and % hours; she no longer reaches the gates this is testing.',
      v_share, v_hours;
  end if;

  if exists (
    select 1 from public.list_seva_narrowness(p_min_hours => 10) listed
    where listed.devotee_name = 'Nishtha Das'
  ) then
    raise exception
      'Nishtha has served every category the temple serves and was still called narrow.';
  end if;

  -- ...and the call is not empty for some unrelated reason.
  if not exists (
    select 1 from public.list_seva_narrowness(p_min_hours => 10) listed
    where listed.devotee_name = 'Gopal Das'
  ) then
    raise exception 'Nobody at all came back, so Nishtha''s absence proves nothing.';
  end if;

  -- Every row that did come back has somewhere left to go.
  if exists (
    select 1 from public.list_seva_narrowness(p_min_hours => 10) listed
    where coalesce(array_length(listed.untouched_categories, 1), 0) = 0
       or listed.untouched_share_of_congregation <= 0
  ) then
    raise exception 'A narrowness row named no untouched category.';
  end if;
end;
$$;

update public.app_settings set value = '0.90'
where key = 'seva_balance.category_share_quantile';

do $$
begin
  raise notice 'all seva balance checks passed';
end;
$$;

select 'seva balance verification passed' as result;

rollback;
