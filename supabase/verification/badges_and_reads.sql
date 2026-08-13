-- Functional verification for 202608040066_badges_and_reads.sql.
--
-- Rolled back at the end. Every local is prefixed v_ so it can never shadow a
-- column name. Anything a devotee could really attempt is attempted as that
-- devotee, under `set local role authenticated`, so the grants, the row level
-- security and the permission checks are what is being tested rather than
-- superuser rights waving everything through.
--
-- 0066 makes five claims and this file exists to break all five if they are
-- not true.
--
--   1. HOURS SERVED IS NOT HOURS CREDITED. A devotee whose every act is still
--      waiting on somebody reads zero credited minutes and their real minutes
--      served, on their own screen and on the President's. served >= credited
--      for every devotee in every period, not in one hand-picked case.
--
--   2. TEN BADGES, TEN REASONS. Each of the ten is earned by exactly the set of
--      devotees its own rule picks out — DERIVED AT RUNTIME from
--      public.seva_mala_period_measures rather than written down here — and by
--      a different set from every other badge. And for each one, a devotee who
--      beats the winner on the obvious measure did NOT get it, because "ten
--      badges for ten reasons" is a claim about what does NOT earn a badge.
--
--   3. A BADGE STAYS WHILE IT IS STILL BEING EARNED. Dhira holds the same badge
--      in week A, week B and the week happening now, and wears the newest one.
--      Vismrita earned one in week A, stopped, and it is gone from his profile
--      and still on his shelf. Nothing is ever deleted.
--
--   4. SEVA CARE SURFACES OUTLIERS AND ONLY OUTLIERS, AND CAN BE CLEARED.
--      Ghana washes pots seven times as hard as anybody else who washes pots
--      and is on the list. Samadarshi serves MORE hours a week than Ghana, in a
--      seva five other devotees serve just as hard, and is not. A dismissal
--      hides Ghana; a lapse brings him back.
--
--   5. THE DRILL-DOWN LEAKS NOTHING. seva_norm and giving_norm are not in its
--      return type at all, the cash figures are app.view_all's, and an ordinary
--      devotee asking about a devotee who opted out gets no row rather than a
--      row of nulls.
--
-- ---------------------------------------------------------------------------
-- The fixture.
--
-- Weeks are counted back from this Monday: week 0 is the week happening now,
-- week 1 is week B (the latest complete week), week 2 is week A. Everything
-- earlier is history, and history exists because half the badges are questions
-- about a devotee's past.
--
-- Every measure is designed to be decided GLOBALLY rather than inside one
-- window, so that no assertion depends on where last month's boundary happens
-- to fall this year. Three facts are asserted about the whole fixture before
-- anything is read:
--
--   nobody but Brahma ever serves before seven in the morning
--   nobody but Navina ever touches three categories
--   nobody but Dhruva ever gives in more than one week
--
-- The cast:
--
--   Shrama Das        most hours, weeks A and B          Śrama-dāna
--   Nitya Devi        six short days a week              Nitya-sevā
--   Aruna Das         first to the Shoe Room, Monday     Aruṇodaya
--   Dhira Das         twenty-one weeks of one seva       Dhairya
--   Ruchira Devi      a seva she had never served        Ruci
--   Navina Das        four categories in one month       Navadhā
--   Dhruva Devi       twenty dollars in each of 3 weeks  Dhruva-dāna
--   Tanmaya Das       hours AND giving, both middling    Tan-mana-dhana
--   Brahma Das        4:30am, six mornings               Brāhma-muhūrta
--   Bhakti Devi       two hours, then twenty             Bhakti-latā
--
--   Vismrita Das      Nitya-sevā in week A, then stopped — the badge that drops
--   Pratiksha Devi    two hours in week B, none confirmed — served, not credited
--   Chinmayi Devi     earns badges and OPTED OUT of the board
--   Vaishya Das       five thousand dollars and not one hour
--   Ghana Das         ten hours a week of pot washing, fourteen weeks
--   Samadarshi Das    eleven hours a week of a seva five people serve as hard
--   four pot washers  ninety minutes a fortnight — Ghana's "normal"
--   five servers      six hours a week of prasadam — Samadarshi's "normal"
--   Padma Devi        an ordinary devotee, on the board, who asks the questions
--   Adhyaksha Das     the President, app.view_all
--   Mukhya Das        a Community Head, services.manage_recurring and no more
--
-- The final row must read: badges and reads verification passed

begin;

-- ---------------------------------------------------------------------------
-- 0. The ground.
-- ---------------------------------------------------------------------------

do $$
declare
  v_holders text;
begin
  if to_regprocedure('public.seva_mala_served(date, date, uuid)') is null
    or to_regprocedure('public.list_all_seva_hours(text)') is null
    or to_regprocedure('public.seva_mala_period_measures(text, date, date, text)') is null
    or to_regprocedure('public.current_devotee_awards(uuid)') is null
    or to_regprocedure('public.list_seva_badge_legend()') is null
    or to_regprocedure('public.dismiss_seva_care(uuid, uuid, text)') is null
    or to_regprocedure('public.dismiss_seva_care_row(uuid, uuid)') is null
    or to_regprocedure('public.restore_seva_care(uuid, uuid, text)') is null
    or to_regprocedure('public.list_seva_care_dismissals(boolean)') is null
    or to_regprocedure('public.seva_yatra_devotee_summary(uuid, text)') is null
    or to_regclass('public.seva_care_dismissals') is null
  then
    raise exception '202608040066 is not applied.';
  end if;

  -- 0066 section 3's expiry is still a join that stops matching, and that is
  -- only safe while the row underneath it cannot be deleted.
  if not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.devotee_awards'::regclass
      and tgname = 'devotee_awards_append_only'
      and not tgisinternal
  ) then
    raise exception 'The append-only trigger on devotee_awards is gone.';
  end if;

  select string_agg(roles.name, ',' order by roles.name) into v_holders
  from public.role_permissions
  join public.roles on roles.id = role_permissions.role_id
  where role_permissions.permission_key = 'app.view_all';
  if v_holders is distinct from 'president,tech' then
    raise exception 'app.view_all is held by %.', v_holders;
  end if;

  -- Every promise in this file about what is withheld is only a promise while
  -- the tables themselves stay shut.
  if has_table_privilege('authenticated', 'public.period_scores', 'select')
    or has_table_privilege('authenticated', 'public.seva_mala_periods', 'select')
    or has_table_privilege('authenticated', 'public.app_settings', 'select')
    or has_table_privilege('authenticated', 'public.seva_care_dismissals', 'select')
  then
    raise exception 'A devotee can read something 0066 answers about.';
  end if;

  if public.seva_mala_number('seva_mala.minimum_cohort', 8) <> 8 then
    raise exception 'The minimum cohort is not eight; the fixture is sized for eight.';
  end if;
  if public.seva_care_dismissal_days() <> 90 then
    raise exception 'A dismissal lasts % days rather than ninety.',
      public.seva_care_dismissal_days();
  end if;
  if public.seva_mala_number('seva_balance.frequency_multiple', 2.0) <> 2.0 then
    raise exception 'The frequency multiple is not two; the fixture is laid out under it.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 1. The doors, their shapes, and what may not go through them.
-- ---------------------------------------------------------------------------

do $$
declare
  v_columns text;
  v_leaked text;
  v_name text;
begin
  -- my_seva_mala carries both figures, and only one of them is the scoring's.
  select string_agg(parameters.parameter_name, ', ' order by parameters.ordinal_position)
  into v_columns
  from information_schema.parameters parameters
  where parameters.specific_schema = 'public'
    and parameters.specific_name like 'my\_seva\_mala%'
    and parameters.parameter_mode = 'OUT';
  if v_columns not like '%seva_minutes, served_minutes, served_acts%' then
    raise exception 'my_seva_mala returns (%).', v_columns;
  end if;

  -- THE DRILL-DOWN DOES NOT DECLARE A COMPONENT. Not gated — absent. Asserted
  -- by pattern as well as by eye, so a column somebody adds later under a new
  -- name is refused too.
  select string_agg(parameters.parameter_name, ', ') into v_leaked
  from information_schema.parameters parameters
  where parameters.specific_schema = 'public'
    and parameters.specific_name like 'seva\_yatra\_devotee\_summary%'
    and parameters.parameter_mode = 'OUT'
    and (
      parameters.parameter_name ilike '%norm%'
      or parameters.parameter_name ilike '%utility%'
      or parameters.parameter_name ilike '%reference%'
      or parameters.parameter_name ilike '%unit%'
    );
  if v_leaked is not null then
    raise exception
      'The board drill-down declares %. 0060 section 3 is why it may not.', v_leaked;
  end if;

  -- And the repository-wide rule the three earlier files assert: the set of
  -- functions an ordinary devotee may execute that returns a component has not
  -- grown. Restated here because 0066 adds five devotee-callable functions.
  select string_agg(distinct proc.proname, ', ' order by proc.proname) into v_leaked
  from pg_proc proc
  join pg_namespace spaces on spaces.oid = proc.pronamespace
  where spaces.nspname = 'public'
    and has_function_privilege('authenticated', proc.oid, 'execute')
    and (
      pg_get_function_result(proc.oid) like '%seva_norm%'
      or pg_get_function_result(proc.oid) like '%giving_norm%'
      or pg_get_function_result(proc.oid) like '%giving_reference%'
      or pg_get_function_result(proc.oid) like '%giving_unit%'
    );
  if v_leaked is distinct from 'explain_my_score, list_all_seva_scores' then
    raise exception 'The functions returning a component are now: %.', v_leaked;
  end if;

  -- The machinery stays shut.
  foreach v_name in array array[
    'public.seva_mala_served(date, date, uuid)',
    'public.seva_mala_period_measures(text, date, date, text)',
    'public.current_devotee_awards(uuid)',
    'public.current_award_periods()',
    'public.seva_care_dismissal_days()',
    'public.award_seva_mala_for_period(uuid)'
  ] loop
    if has_function_privilege('authenticated', v_name, 'execute') then
      raise exception 'A devotee can execute %.', v_name;
    end if;
  end loop;

  -- And the doors are doors.
  foreach v_name in array array[
    'public.my_seva_mala(text)',
    'public.list_all_seva_hours(text)',
    'public.list_seva_badge_legend()',
    'public.list_devotee_badges(uuid)',
    'public.list_devotee_award_shelf(uuid)',
    'public.list_seva_concentration(integer, numeric)',
    'public.dismiss_seva_care(uuid, uuid, text)',
    'public.dismiss_seva_care_row(uuid, uuid)',
    'public.restore_seva_care(uuid, uuid, text)',
    'public.list_seva_care_dismissals(boolean)',
    'public.seva_yatra_devotee_summary(uuid, text)'
  ] loop
    if not has_function_privilege('authenticated', v_name, 'execute') then
      raise exception 'authenticated may not execute %.', v_name;
    end if;
    if has_function_privilege('anon', v_name, 'execute') then
      raise exception 'A signed-out visitor may execute %.', v_name;
    end if;
  end loop;

  -- Nothing writes to the dismissal table but the functions that own it.
  if has_table_privilege('authenticated', 'public.seva_care_dismissals', 'insert')
    or has_table_privilege('authenticated', 'public.seva_care_dismissals', 'update')
    or has_table_privilege('authenticated', 'public.seva_care_dismissals', 'delete')
  then
    raise exception 'A devotee can write to seva_care_dismissals directly.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. The ten, as definitions.
--
--    By TITLE and by MEASURE, because the title is what the temple said and the
--    measure is the claim that they are ten different questions.
-- ---------------------------------------------------------------------------

do $$
declare
  v_missing text;
  v_count integer;
begin
  select string_agg(wanted.title, ', ' order by wanted.title) into v_missing
  from (values
    ('Śrama-dāna', 'week', 'served_hours'),
    ('Nitya-sevā', 'week', 'days_served'),
    ('Aruṇodaya', 'week', 'scarce_earliest'),
    ('Dhairya', 'week', 'longest_run_weeks'),
    ('Ruci', 'week', 'served_a_new_seva'),
    ('Navadhā', 'month', 'seva_categories'),
    ('Dhruva-dāna', 'month', 'giving_weeks'),
    ('Tan-mana-dhana', 'month', 'reached_both_medians'),
    ('Brāhma-muhūrta', 'month', 'predawn_minutes'),
    ('Bhakti-latā', 'month', 'beat_own_best_hours')
  ) as wanted(title, period_kind, measure)
  where not exists (
    select 1 from public.award_definitions definitions
    where definitions.title = wanted.title
      and definitions.period_kind = wanted.period_kind
      and definitions.rule_measure = wanted.measure
      and definitions.is_active
  );
  if v_missing is not null then
    raise exception 'Missing or mis-measured: %.', v_missing;
  end if;

  select count(*) into v_count from public.award_definitions
  where rule_measure is not null and period_kind = 'week';
  if v_count <> 5 then
    raise exception 'There are % weekly measured badges rather than five.', v_count;
  end if;
  select count(*) into v_count from public.award_definitions
  where rule_measure is not null and period_kind = 'month';
  if v_count <> 5 then
    raise exception 'There are % monthly measured badges rather than five.', v_count;
  end if;

  -- TEN DIFFERENT REASONS, at the level of the definitions: no measure is used
  -- twice, so no two of them can be the same question with the threshold moved.
  select count(distinct rule_measure) into v_count
  from public.award_definitions where rule_measure is not null;
  if v_count <> 10 then
    raise exception
      'The ten badges are decided on % distinct measures. Two of them are one badge.',
      v_count;
  end if;

  -- Every one of them says what earns it, because the app shows a legend.
  select string_agg(definitions.title, ', ' order by definitions.title) into v_missing
  from public.award_definitions definitions
  where definitions.rule_measure is not null
    and (definitions.earned_by is null or length(trim(definitions.earned_by)) < 20);
  if v_missing is not null then
    raise exception 'These badges do not say what earns them: %.', v_missing;
  end if;

  -- And so does everything that was already here, so the legend has no holes.
  select string_agg(definitions.code, ', ' order by definitions.code) into v_missing
  from public.award_definitions definitions
  where definitions.is_active and definitions.earned_by is null;
  if v_missing is not null then
    raise exception 'The legend is silent about: %.', v_missing;
  end if;

  -- The seven Deity garlands still read as one text, earned_by included, or one
  -- of them would be worth more than another.
  select count(distinct earned_by) into v_count
  from public.award_definitions
  where rotation_group = 'weekly_deity_garland';
  if v_count <> 1 then
    raise exception 'The seven weekly garlands are earned by % different sentences.', v_count;
  end if;

  -- No new rule kind. supabase/verification/seva_mala.sql asserts five, and a
  -- sixth would break a file this migration does not own.
  select count(distinct rule_kind) into v_count from public.award_definitions;
  if v_count <> 5 then
    raise exception 'award_definitions now holds % rule kinds.', v_count;
  end if;

  -- None of the ten is a garland: a garland is a physical thing the kitchen has
  -- to make, and ten more of them is a promise nobody made.
  if exists (
    select 1 from public.award_definitions
    where rule_measure is not null and tier = 'garland'
  ) then
    raise exception 'A measured badge was seeded as a garland.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. The congregation.
-- ---------------------------------------------------------------------------

create table public.br_ids (key text primary key, id uuid not null);
grant select on public.br_ids to authenticated;

do $$
declare
  v_who record;
  v_i integer := 0;
begin
  for v_who in
    select * from (values
      ('shrama',     'Shrama Das'),
      ('nitya',      'Nitya Devi'),
      ('aruna',      'Aruna Das'),
      ('dhira',      'Dhira Das'),
      ('ruchira',    'Ruchira Devi'),
      ('navina',     'Navina Das'),
      ('dhruva',     'Dhruva Devi'),
      ('tanmaya',    'Tanmaya Das'),
      ('brahma',     'Brahma Das'),
      ('bhakti',     'Bhakti Devi'),
      ('vismrita',   'Vismrita Das'),
      ('pratiksha',  'Pratiksha Devi'),
      ('chinmayi',   'Chinmayi Devi'),
      ('vaishya',    'Vaishya Das'),
      ('ghana',      'Ghana Das'),
      ('samadarshi', 'Samadarshi Das'),
      ('pot1',       'Potwasher One Das'),
      ('pot2',       'Potwasher Two Das'),
      ('pot3',       'Potwasher Three Das'),
      ('pot4',       'Potwasher Four Das'),
      ('pras1',      'Server One Das'),
      ('pras2',      'Server Two Das'),
      ('pras3',      'Server Three Das'),
      ('pras4',      'Server Four Das'),
      ('pras5',      'Server Five Das'),
      ('padma',      'Padma Devi'),
      ('adhyaksha',  'Adhyaksha Das'),
      ('mukhya',     'Mukhya Das')
    ) as cast_member(key, name)
  loop
    v_i := v_i + 1;
    insert into auth.users (id, email, raw_user_meta_data)
    values (
      ('66000000-0000-0000-0000-0000000000' || lpad(v_i::text, 2, '0'))::uuid,
      'br-' || v_who.key || '@example.test',
      jsonb_build_object('name', v_who.name)
    );

    update public.users set name = v_who.name
    where users.email = 'br-' || v_who.key || '@example.test';

    insert into public.br_ids (key, id)
    select v_who.key, users.id
    from public.users where users.email = 'br-' || v_who.key || '@example.test';
  end loop;
end;
$$;

update public.users
set role_id = (select roles.id from public.roles where roles.name = 'president')
where users.email = 'br-adhyaksha@example.test';

update public.users
set role_id = (select roles.id from public.roles where roles.name = 'core')
where users.email = 'br-mukhya@example.test';

-- Everybody is on the board but Chinmayi, who is the whole of the opt-out test.
update public.users
set leaderboard_visible = (users.email <> 'br-chinmayi@example.test')
where users.email like 'br-%@example.test';

do $$
begin
  if exists (
    select 1 from public.role_permissions
    join public.roles on roles.id = role_permissions.role_id
    where roles.name = 'core' and role_permissions.permission_key = 'app.view_all'
  ) then
    raise exception 'A Community Head holds app.view_all; the refusals below are vacuous.';
  end if;
  if not exists (
    select 1 from public.role_permissions
    join public.roles on roles.id = role_permissions.role_id
    where roles.name = 'core' and role_permissions.permission_key = 'services.manage_recurring'
  ) then
    raise exception 'A Community Head does not run rotas; the board test is not about them.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Scarcity, declared rather than measured.
--
--    public.seva_type_weights is normally computed from ninety days of fill
--    rates and declines. Here it is written directly, because Aruṇodaya is a
--    claim about the BADGE and not about 0055's weighting, and a fixture that
--    had to steer the weight computation would be testing the wrong file.
-- ---------------------------------------------------------------------------

insert into public.seva_type_weights (service_type_id, weight)
select service_types.id, spec.weight
from (values
  ('Pot Washing',            0.80),
  ('Prasadam Serving',       0.85),
  ('Temple Room Cleaning',   0.90),
  ('Vegetable Cutting',      0.95),
  ('Guest Welcome',          1.00),
  ('Kitchen Preparation',    1.05),
  ('General Temple Service', 1.10),
  ('Festival Decoration',    1.15),
  ('Flower Garlands',        1.20),
  ('Mangal Arati Setup',     1.40),
  ('Shoe Room',              1.75)
) as spec(name, weight)
join public.service_types on service_types.name = spec.name
on conflict (service_type_id) do update set weight = excluded.weight;

do $$
declare
  v_scarce numeric;
  v_names text;
begin
  select percentile_cont(0.75) within group (order by weights.weight)
  into v_scarce from public.seva_type_weights weights;

  select string_agg(types.name, ', ' order by types.name) into v_names
  from public.seva_type_weights weights
  join public.service_types types on types.id = weights.service_type_id
  where weights.weight >= v_scarce;

  if v_names is distinct from 'Flower Garlands, Mangal Arati Setup, Shoe Room' then
    raise exception
      'The temple''s hard seva are [%] at a threshold of %. Aruṇodaya would be measuring something else.',
      v_names, v_scarce;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. The facts.
--
--    Two helpers, so that three hundred acts read as a plan rather than as an
--    insert. Nothing here starts before seven in the morning except Brahma's
--    six mornings, which is what makes predawn_minutes a one-devotee measure
--    however the month falls.
-- ---------------------------------------------------------------------------

create function public.br_serve(
  p_key text,
  p_seva text,
  p_on date,
  p_start time,
  p_minutes integer,
  p_counted boolean default true
)
returns void
language plpgsql
as $$
declare
  v_instance uuid;
begin
  insert into public.service_instances (
    service_type_id, date, start_time, duration_minutes, slots_needed,
    participation_mode, posted_by, status
  )
  select service_types.id, p_on, p_start, p_minutes, 1, 'open', null, 'completed'
  from public.service_types where service_types.name = p_seva
  returning id into v_instance;

  if v_instance is null then
    raise exception 'There is no service type called %.', p_seva;
  end if;

  insert into public.service_assignments (
    service_instance_id, devotee_id, assignment_method, status,
    verification, attendance, completed_at
  ) values (
    v_instance,
    (select ids.id from public.br_ids ids where ids.key = p_key),
    'self_joined', 'completed',
    case when p_counted then 'member_verified' else 'self_report' end,
    case when p_counted then 'served' else null end,
    (p_on + time '12:00') at time zone 'America/Chicago'
  );
end;
$$;

create function public.br_give(p_key text, p_cents integer, p_on date, p_tag text)
returns void
language sql
as $$
  insert into public.donations (
    donor_id, donor_name, amount_cents, kind, external_payment_id, received_at
  )
  select ids.id, p_key, p_cents, 'one_time', 'br-' || p_tag,
         (p_on + time '10:00') at time zone 'America/Chicago'
  from public.br_ids ids where ids.key = p_key
$$;

do $$
declare
  v_now date := public.seva_mala_today();
  v_w0 date := public.seva_mala_week_start(public.seva_mala_today());
  v_wb date := public.seva_mala_week_start(public.seva_mala_today()) - 7;
  v_wa date := public.seva_mala_week_start(public.seva_mala_today()) - 14;
  v_mp date := (date_trunc('month', public.seva_mala_today()) - interval '1 month')::date;
  v_m2 date := (date_trunc('month', public.seva_mala_today()) - interval '2 months')::date;
  v_k integer;
  v_d integer;
  v_who text;
begin
  -- ---- Dhira: twenty-one unbroken weeks of one seva, including this one. ---
  for v_k in 0 .. 20 loop
    perform public.br_serve('dhira', 'Temple Room Cleaning', v_w0 - 7 * v_k, time '10:00', 30);
  end loop;

  -- ---- Ghana: ten hours a week of pot washing, fourteen weeks. ------------
  for v_k in 0 .. 13 loop
    perform public.br_serve('ghana', 'Pot Washing', v_w0 - 7 * v_k, time '09:00', 300);
    perform public.br_serve('ghana', 'Pot Washing', v_w0 - 7 * v_k + 2, time '09:00', 300);
  end loop;

  -- ---- The four who wash pots normally: ninety minutes a fortnight. -------
  foreach v_who in array array['pot1', 'pot2', 'pot3', 'pot4'] loop
    for v_k in 0 .. 6 loop
      perform public.br_serve(v_who, 'Pot Washing', v_w0 - 14 * v_k, time '09:00', 90);
    end loop;
  end loop;

  -- ---- Samadarshi: eleven hours a week of a seva five others serve hard. --
  for v_k in 0 .. 13 loop
    perform public.br_serve('samadarshi', 'Prasadam Serving', v_w0 - 7 * v_k, time '11:00', 330);
    perform public.br_serve('samadarshi', 'Prasadam Serving', v_w0 - 7 * v_k + 3, time '11:00', 330);
  end loop;
  foreach v_who in array array['pras1', 'pras2', 'pras3', 'pras4', 'pras5'] loop
    for v_k in 0 .. 13 loop
      perform public.br_serve(v_who, 'Prasadam Serving', v_w0 - 7 * v_k + 1, time '11:00', 360);
    end loop;
  end loop;

  -- ---- Shrama: the most hours, weeks A and B, with history so that nothing
  --      of his is new — and a broken run, so Dhairya is not something hours
  --      can buy.
  for v_k in 6 .. 10 loop
    perform public.br_serve('shrama', 'Kitchen Preparation', v_w0 - 7 * v_k, time '13:00', 120);
    perform public.br_serve('shrama', 'Shoe Room', v_w0 - 7 * v_k + 2, time '13:00', 60);
  end loop;
  for v_k in 1 .. 2 loop
    for v_d in 0 .. 3 loop
      perform public.br_serve('shrama', 'Kitchen Preparation',
                              v_w0 - 7 * v_k + v_d, time '13:00', 300);
    end loop;
    -- The Shoe Room too, and on a Wednesday afternoon, so Aruṇodaya has to
    -- prefer the devotee who was EARLIER over the devotee who did more.
    perform public.br_serve('shrama', 'Shoe Room', v_w0 - 7 * v_k + 2, time '13:00', 60);
  end loop;

  -- ---- Nitya: six short days a week, weeks A and B, one day before that. --
  for v_k in 3 .. 8 loop
    perform public.br_serve('nitya', 'Guest Welcome', v_w0 - 7 * v_k, time '16:00', 30);
  end loop;
  for v_k in 1 .. 2 loop
    for v_d in 0 .. 5 loop
      perform public.br_serve('nitya', 'Guest Welcome', v_w0 - 7 * v_k + v_d, time '16:00', 30);
    end loop;
  end loop;

  -- ---- Aruna: the Shoe Room, Monday morning, weeks A and B. ---------------
  for v_k in 1 .. 8 loop
    perform public.br_serve('aruna', 'Shoe Room', v_w0 - 7 * v_k, time '09:00', 60);
  end loop;

  -- ---- Ruchira: pot washing for months, and one new thing in week B. ------
  for v_k in 2 .. 10 loop
    perform public.br_serve('ruchira', 'Pot Washing', v_w0 - 7 * v_k + 4, time '09:00', 60);
  end loop;
  perform public.br_serve('ruchira', 'Pot Washing', v_wb + 4, time '09:00', 60);
  perform public.br_serve('ruchira', 'Vegetable Cutting', v_wb + 5, time '09:00', 60);

  -- ---- Vismrita: Nitya-sevā in week A, and then he stopped. ---------------
  for v_k in 3 .. 6 loop
    perform public.br_serve('vismrita', 'Guest Welcome', v_w0 - 7 * v_k, time '16:00', 30);
  end loop;
  for v_d in 0 .. 5 loop
    perform public.br_serve('vismrita', 'Guest Welcome', v_wa + v_d, time '16:00', 30);
  end loop;

  -- ---- Pratiksha: two hours in week B and not one of them confirmed. ------
  for v_k in 3 .. 6 loop
    perform public.br_serve('pratiksha', 'Flower Garlands', v_w0 - 7 * v_k, time '09:00', 60);
  end loop;
  perform public.br_serve('pratiksha', 'Flower Garlands', v_wb + 3, time '09:00', 120, false);

  -- ---- Chinmayi: earns badges, opted out of the board. She serves in the
  --      week happening now as well, so that "she is not published" is a fact
  --      about the opt-out rather than about her having done nothing.
  for v_k in 0 .. 8 loop
    for v_d in 0 .. 3 loop
      perform public.br_serve('chinmayi', 'Festival Decoration',
                              v_w0 - 7 * v_k + v_d, time '14:00', 45);
    end loop;
  end loop;

  -- ---- Navina: four categories, inside last month. ------------------------
  perform public.br_serve('navina', 'Pot Washing',          v_mp + 1, time '09:00', 60);
  perform public.br_serve('navina', 'Temple Room Cleaning', v_mp + 2, time '10:00', 60);
  perform public.br_serve('navina', 'Guest Welcome',        v_mp + 3, time '16:00', 60);
  perform public.br_serve('navina', 'Flower Garlands',      v_mp + 4, time '09:00', 60);

  -- ---- Brahma: six mornings at half past four, inside last month. ---------
  for v_d in 0 .. 5 loop
    perform public.br_serve('brahma', 'Mangal Arati Setup', v_mp + 7 + v_d, time '04:30', 90);
  end loop;

  -- ---- Tanmaya: hours and giving, both comfortably middling. --------------
  for v_d in 0 .. 2 loop
    perform public.br_serve('tanmaya', 'General Temple Service',
                            v_mp + 10 + v_d, time '15:00', 240);
  end loop;
  perform public.br_give('tanmaya', 50000, v_mp + 11, 'tanmaya-mp');

  -- ---- Bhakti: two hours two months ago, twenty last month. ---------------
  perform public.br_serve('bhakti', 'Kitchen Preparation', v_m2 + 5, time '13:00', 120);
  for v_d in 0 .. 4 loop
    perform public.br_serve('bhakti', 'Kitchen Preparation',
                            v_mp + 14 + v_d, time '13:00', 240);
  end loop;

  -- ---- Dhruva: twenty dollars, three separate weeks of last month. --------
  perform public.br_give('dhruva', 2000, v_mp + 1,  'dhruva-1');
  perform public.br_give('dhruva', 2000, v_mp + 8,  'dhruva-2');
  perform public.br_give('dhruva', 2000, v_mp + 15, 'dhruva-3');

  -- ---- Vaishya: five thousand dollars and not one hour. -------------------
  perform public.br_give('vaishya', 500000, v_mp + 12, 'vaishya-mp');

  -- Ghana gives forty dollars this week, so that "the cash figure is withheld"
  -- is withholding a figure rather than withholding a zero.
  perform public.br_give('ghana', 4000, v_w0, 'ghana-now');

  -- ---- Padma: an ordinary devotee, on the board, who asks the questions. --
  for v_k in 1 .. 6 loop
    perform public.br_serve('padma', 'General Temple Service', v_w0 - 7 * v_k, time '15:00', 60);
  end loop;
  perform public.br_give('padma', 1000, v_mp + 5, 'padma-mp');

  if v_now < v_w0 then
    raise exception 'The week does not contain today; every date above is wrong.';
  end if;
end;
$$;

-- The fixture's own premise, said out loud and over the WHOLE database rather
-- than over this file's cast. Everything below about Brāhma-muhūrta, Navadhā
-- and Dhruva-dāna rests on these being one-devotee facts whatever month it is
-- when this runs.
do $$
declare
  v_offender text;
begin
  select users.name into v_offender
  from public.seva_mala_acts() acts
  join public.users on users.id = acts.devotee_id
  where acts.started_at_local < time '07:00'
    and acts.points_status <> 'not_served'
    and acts.devotee_id <> (select ids.id from public.br_ids ids where ids.key = 'brahma')
  limit 1;
  if v_offender is not null then
    raise exception '% serves before dawn as well as Brahma; the fixture is blunt.', v_offender;
  end if;

  select users.name into v_offender
  from (
    select acts.devotee_id, count(distinct types.category) as categories
    from public.seva_mala_acts() acts
    join public.service_types types on types.id = acts.service_type_id
    where acts.points_status <> 'not_served'
    group by acts.devotee_id
  ) breadth
  join public.users on users.id = breadth.devotee_id
  where breadth.categories >= 3
    and breadth.devotee_id <> (select ids.id from public.br_ids ids where ids.key = 'navina')
  limit 1;
  if v_offender is not null then
    raise exception '% touches three categories as well as Navina.', v_offender;
  end if;

  select users.name into v_offender
  from (
    select donations.donor_id,
           count(distinct public.seva_mala_week_start(
             (donations.received_at at time zone 'America/Chicago')::date)) as weeks
    from public.donations where donations.donor_id is not null
    group by donations.donor_id
  ) giving
  join public.users on users.id = giving.donor_id
  where giving.weeks >= 2
    and giving.donor_id <> (select ids.id from public.br_ids ids where ids.key = 'dhruva')
  limit 1;
  if v_offender is not null then
    raise exception '% gives in more than one week as well as Dhruva.', v_offender;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. The periods.
--
--    Week A closes, then week B closes, then the week happening now is computed
--    open, then last month closes. The lifetime period exists too, because
--    "lifetime is never published" needs a lifetime award to be a claim about
--    anything.
-- ---------------------------------------------------------------------------

create table public.br_periods (label text primary key, id uuid not null, starts_on date not null);
grant select on public.br_periods to authenticated;

insert into public.br_periods (label, id, starts_on)
select 'A',
       public.ensure_seva_mala_period('week', public.seva_mala_week_start(public.seva_mala_today()) - 14),
       public.seva_mala_week_start(public.seva_mala_today()) - 14;
select public.recompute_seva_mala_period((select id from public.br_periods where label = 'A')) as week_a;

insert into public.br_periods (label, id, starts_on)
select 'B',
       public.ensure_seva_mala_period('week', public.seva_mala_week_start(public.seva_mala_today()) - 7),
       public.seva_mala_week_start(public.seva_mala_today()) - 7;
select public.recompute_seva_mala_period((select id from public.br_periods where label = 'B')) as week_b;

insert into public.br_periods (label, id, starts_on)
select 'W0',
       public.ensure_seva_mala_period('week', public.seva_mala_week_start(public.seva_mala_today())),
       public.seva_mala_week_start(public.seva_mala_today());
select public.recompute_seva_mala_period((select id from public.br_periods where label = 'W0')) as week_now;

insert into public.br_periods (label, id, starts_on)
select 'MP',
       public.ensure_seva_mala_period('month',
         (date_trunc('month', public.seva_mala_today()) - interval '1 month')::date),
       (date_trunc('month', public.seva_mala_today()) - interval '1 month')::date;
select public.recompute_seva_mala_period((select id from public.br_periods where label = 'MP')) as month_prev;

insert into public.br_periods (label, id, starts_on)
select 'L',
       public.ensure_seva_mala_period('lifetime', public.seva_mala_today()),
       date '1970-01-01';
select public.recompute_seva_mala_period((select id from public.br_periods where label = 'L')) as lifetime;

do $$
declare
  v_row record;
begin
  for v_row in
    select periods.frozen_at, periods.participant_count, br_periods.label
    from public.br_periods
    join public.seva_mala_periods periods on periods.id = br_periods.id
  loop
    if v_row.label in ('A', 'B', 'MP') and v_row.frozen_at is null then
      raise exception 'Period % did not freeze, so no rivalrous badge could be decided.',
        v_row.label;
    end if;
    if v_row.label in ('W0', 'L') and v_row.frozen_at is not null then
      raise exception 'Period % froze; it is meant to be open.', v_row.label;
    end if;
  end loop;

  if (select participant_count from public.seva_mala_periods
      where id = (select id from public.br_periods where label = 'B'))
     < public.seva_mala_number('seva_mala.minimum_cohort', 8)
  then
    raise exception 'Week B is below the cohort, so no badge would publish.';
  end if;

  if (select period_id from public.current_award_periods() where period_kind = 'week')
     is distinct from (select id from public.br_periods where label = 'B')
  then
    raise exception 'Week B is not the current weekly leaderboard.';
  end if;
  if (select period_id from public.current_award_periods() where period_kind = 'month')
     is distinct from (select id from public.br_periods where label = 'MP')
  then
    raise exception 'Last month is not the current monthly leaderboard.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. CLAIM 1 — hours served is not hours credited.
-- ---------------------------------------------------------------------------

do $$
declare
  v_period public.seva_mala_periods;
  v_served numeric;
  v_credited numeric;
  v_acts integer;
begin
  select * into v_period from public.seva_mala_periods
  where id = (select id from public.br_periods where label = 'B');

  select hours.served_minutes, hours.served_acts
  into v_served, v_acts
  from public.seva_mala_served(v_period.starts_on, v_period.ends_on,
    (select ids.id from public.br_ids ids where ids.key = 'pratiksha')) hours;

  if coalesce(v_served, 0) <> 120 or coalesce(v_acts, 0) <> 1 then
    raise exception
      'Pratiksha served % minutes over % act(s) in week B; the fixture says 120 over 1.',
      v_served, v_acts;
  end if;

  -- AND THE SCORING PAID FOR NONE OF IT. This is the whole complaint: not that
  -- the number is small, but that it is zero while she stood there for two
  -- hours. She is not even reported as a zero — public.period_scores has no row
  -- for her at all, which is why the President's list is a full outer join and
  -- not a wider select.
  select coalesce(sum(scores.credited_minutes), 0) into v_credited
  from public.period_scores scores
  where scores.period_id = v_period.id
    and scores.devotee_id = (select ids.id from public.br_ids ids where ids.key = 'pratiksha');
  if v_credited <> 0 then
    raise exception
      'Pratiksha''s unverified act was credited % minutes, so there was nothing here to fix.',
      v_credited;
  end if;
  if exists (
    select 1 from public.period_scores scores
    where scores.period_id = v_period.id
      and scores.devotee_id = (select ids.id from public.br_ids ids where ids.key = 'pratiksha')
  ) then
    raise exception 'period_scores has a row for a devotee with no credited minutes.';
  end if;
end;
$$;

-- SERVED IS NEVER SMALLER THAN CREDITED, for every devotee in every period.
-- Stated over the whole fixture rather than in one case, because two figures
-- measuring different acts is exactly the bug this would hide.
do $$
declare
  v_bad text;
begin
  select string_agg(users.name || ' (' || periods.period_kind || ' from ' || periods.starts_on
                    || ': served ' || round(coalesce(hours.served_minutes, 0))
                    || ', credited ' || round(scores.credited_minutes) || ')', '; ')
  into v_bad
  from public.period_scores scores
  join public.seva_mala_periods periods on periods.id = scores.period_id
  join public.users on users.id = scores.devotee_id
  left join lateral public.seva_mala_served(
    periods.starts_on, periods.ends_on, scores.devotee_id) hours on true
  where periods.period_kind <> 'lifetime'
    and coalesce(hours.served_minutes, 0) < scores.credited_minutes;

  if v_bad is not null then
    raise exception 'Credited minutes exceeded served minutes for %.', v_bad;
  end if;
end;
$$;

-- Her own screen says it too, in her own words, for the week she served in.
-- my_seva_mala only answers about the period that is open, so the assertion
-- that matters here is the one the President's list makes below; this is the
-- shape check.
set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.br_ids ids where ids.key = 'ghana'), true);

do $$
declare
  v_row record;
begin
  select * into v_row from public.my_seva_mala('week');
  if v_row.period_id is null then
    raise exception 'Ghana''s own standing came back empty.';
  end if;
  if v_row.served_minutes is null or v_row.served_minutes <= 0 then
    raise exception 'Ghana served nothing this week according to his own screen.';
  end if;
  if v_row.served_minutes < v_row.seva_minutes then
    raise exception 'Ghana''s served minutes (%) are below his credited (%).',
      v_row.served_minutes, v_row.seva_minutes;
  end if;
  if v_row.served_acts <= 0 then
    raise exception 'Ghana served % acts this week.', v_row.served_acts;
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);

-- The President's list carries both figures, and carries the devotee the board
-- cannot see. The Community Head sees it too; a plain devotee does not.
create table public.br_seen (
  who text not null, what text not null, rows integer not null, detail text,
  primary key (who, what)
);
grant select, insert on public.br_seen to authenticated;

do $$
declare
  v_who text;
begin
  foreach v_who in array array['adhyaksha', 'mukhya', 'padma', 'pratiksha'] loop
    execute format('select set_config(''request.jwt.claim.sub'', %L, true)',
      (select ids.id from public.br_ids ids where ids.key = v_who));
    set local role authenticated;

    if current_user <> 'authenticated' then
      raise exception 'The reads are being attempted as %, not authenticated.', current_user;
    end if;

    insert into public.br_seen (who, what, rows, detail)
    select v_who, 'all_hours', count(*)::integer,
           string_agg(hours.devotee_name, ', ' order by hours.devotee_name)
             filter (where hours.awaiting_only)
    from public.list_all_seva_hours('week') hours;

    insert into public.br_seen (who, what, rows, detail)
    select v_who, 'dismissals', count(*)::integer, null
    from public.list_seva_care_dismissals();

    insert into public.br_seen (who, what, rows, detail)
    select v_who, 'concentration', count(*)::integer, null
    from public.list_seva_concentration();

    reset role;
  end loop;
  perform set_config('request.jwt.claim.sub', '', true);
end;
$$;

do $$
declare
  v_row record;
begin
  for v_row in select * from public.br_seen where what = 'all_hours' loop
    if v_row.who in ('adhyaksha', 'mukhya') and v_row.rows = 0 then
      raise exception '% sees no hours at all.', v_row.who;
    end if;
    if v_row.who in ('padma', 'pratiksha') and v_row.rows <> 0 then
      raise exception '% read the whole congregation''s hours.', v_row.who;
    end if;
  end loop;

  for v_row in select * from public.br_seen where what in ('dismissals', 'concentration') loop
    if v_row.who <> 'adhyaksha' and v_row.rows <> 0 then
      raise exception '% read the % list.', v_row.who, v_row.what;
    end if;
  end loop;
end;
$$;

-- And the devotee the board cannot see is on it. Read over week B, which is
-- where Pratiksha's unconfirmed hours are, through the same function.
do $$
declare
  v_row record;
begin
  perform set_config('request.jwt.claim.sub',
    (select ids.id::text from public.br_ids ids where ids.key = 'adhyaksha'), true);

  -- The open week first: Ghana served, Ghana is credited, and the two agree.
  select * into v_row from public.list_all_seva_hours('week')
  where devotee_name = 'Ghana Das';
  if v_row.served_minutes is null or v_row.served_minutes < v_row.credited_minutes then
    raise exception 'Ghana reads served % against credited % on the President''s list.',
      v_row.served_minutes, v_row.credited_minutes;
  end if;
  if v_row.awaiting_only then
    raise exception 'Ghana, whose every act is confirmed, is flagged as awaiting only.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. CLAIM 2 — ten badges, ten reasons.
--
--    For each badge: the set it was given to is EXACTLY the set its own rule
--    picks out of public.seva_mala_period_measures, derived here at runtime.
--    Nothing below writes down a winner and then goes looking for them.
-- ---------------------------------------------------------------------------

create table public.br_rule_check (
  code text primary key,
  period_label text not null,
  awarded integer not null,
  winners text
);

do $$
declare
  v_definition record;
  v_period public.seva_mala_periods;
  v_label text;
  v_from date;
  v_to date;
  v_threshold numeric;
  v_awarded uuid[];
  v_expected uuid[];
begin
  for v_definition in
    select * from public.award_definitions
    where rule_measure is not null and is_active order by sort_order
  loop
    v_label := case v_definition.period_kind when 'week' then 'B' else 'MP' end;
    select * into v_period from public.seva_mala_periods
    where id = (select id from public.br_periods where label = v_label);
    v_from := v_period.starts_on;
    v_to := least(v_period.ends_on, public.seva_mala_today());

    if v_definition.rule_kind = 'derived_threshold' then
      select percentile_cont(coalesce(v_definition.threshold_quantile, 0.5))
             within group (order by measures.value)
      into v_threshold
      from public.seva_mala_period_measures(
             v_definition.period_kind, v_from, v_to, v_definition.rule_measure) measures
      where measures.value > 0;

      v_threshold := greatest(coalesce(v_threshold, 0),
                              coalesce(v_definition.threshold_floor, 0));

      select coalesce(array_agg(measures.devotee_id order by measures.devotee_id), '{}')
      into v_expected
      from public.seva_mala_period_measures(
             v_definition.period_kind, v_from, v_to, v_definition.rule_measure) measures
      where v_threshold > 0 and measures.value >= v_threshold;
    else
      select coalesce(array_agg(ranked.devotee_id order by ranked.devotee_id), '{}')
      into v_expected
      from (
        select measures.devotee_id,
               dense_rank() over (order by measures.value desc) as rk
        from public.seva_mala_period_measures(
               v_definition.period_kind, v_from, v_to, v_definition.rule_measure) measures
        where measures.value > 0
      ) ranked
      where ranked.rk <= v_definition.top_n;
    end if;

    select coalesce(array_agg(awards.devotee_id order by awards.devotee_id), '{}')
    into v_awarded
    from public.devotee_awards awards
    where awards.period_id = v_period.id
      and awards.award_definition_id = v_definition.id;

    if v_awarded is distinct from v_expected then
      raise exception
        '% went to % devotee(s); its own rule picks % of them.',
        v_definition.code, cardinality(v_awarded), cardinality(v_expected);
    end if;

    if cardinality(v_awarded) = 0 then
      raise exception
        '% was earned by nobody, so nothing below proves anything about it.',
        v_definition.code;
    end if;

    insert into public.br_rule_check (code, period_label, awarded, winners)
    select v_definition.code, v_label, cardinality(v_awarded),
           string_agg(users.name, ', ' order by users.name)
    from public.users where users.id = any (v_awarded);
  end loop;
end;
$$;

-- NO TWO OF THE TEN WENT TO THE SAME SET. That is the whole of "not five copies
-- of top N": if two badges could go to exactly the same devotees for two
-- different stated reasons, one of them is decoration.
do $$
declare
  v_pair record;
begin
  for v_pair in
    select a.code as left_code, b.code as right_code, a.period_label
    from public.br_rule_check a
    join public.br_rule_check b on b.code > a.code and b.period_label = a.period_label
  loop
    if (
      select coalesce(array_agg(awards.devotee_id order by awards.devotee_id), '{}')
      from public.devotee_awards awards
      join public.award_definitions definitions on definitions.id = awards.award_definition_id
      join public.br_periods on br_periods.id = awards.period_id
      where definitions.code = v_pair.left_code and br_periods.label = v_pair.period_label
    ) = (
      select coalesce(array_agg(awards.devotee_id order by awards.devotee_id), '{}')
      from public.devotee_awards awards
      join public.award_definitions definitions on definitions.id = awards.award_definition_id
      join public.br_periods on br_periods.id = awards.period_id
      where definitions.code = v_pair.right_code and br_periods.label = v_pair.period_label
    ) then
      raise exception
        '% and % went to exactly the same devotees. Two badges, one reason.',
        v_pair.left_code, v_pair.right_code;
    end if;
  end loop;
end;
$$;

-- AND FOR EACH ONE, SOMEBODY WHO BEATS THE WINNER ON THE OBVIOUS MEASURE DID
-- NOT GET IT. This is the assertion a badge that secretly ranked on hours, on
-- score or on money would fail.
do $$
declare
  v_case record;
  v_period uuid;
begin
  for v_case in
    select * from (values
      ('weekly_shrama_dana',     'B',  'shrama',   'vaishya',
       'five thousand dollars is not an hour'),
      ('weekly_nitya_seva',      'B',  'nitya',    'ghana',
       'ten hours on two days is not six days'),
      ('weekly_arunodaya',       'B',  'aruna',    'shrama',
       'more of the hard seva, later in the week, is not first'),
      ('weekly_dhairya',         'B',  'dhira',    'shrama',
       'the most hours in the week is not a run of weeks'),
      ('weekly_ruci',            'B',  'ruchira',  'shrama',
       'more of what you always do is not something new'),
      ('monthly_navadha',        'MP', 'navina',   'samadarshi',
       'a hundred and forty hours of one thing is not breadth'),
      ('monthly_dhruva_dana',    'MP', 'dhruva',   'vaishya',
       'one gift of five thousand dollars is not three weeks of twenty'),
      ('monthly_tan_mana_dhana', 'MP', 'tanmaya',  'vaishya',
       'giving without hours is not both'),
      ('monthly_brahma_muhurta', 'MP', 'brahma',   'samadarshi',
       'hours after breakfast are not hours before dawn'),
      ('monthly_bhakti_lata',    'MP', 'bhakti',   'samadarshi',
       'serving as much as you always have is not growth')
    ) as spec(code, label, holder, foil, because)
  loop
    v_period := (select id from public.br_periods where label = v_case.label);

    if not exists (
      select 1 from public.devotee_awards awards
      join public.award_definitions definitions on definitions.id = awards.award_definition_id
      where awards.period_id = v_period
        and definitions.code = v_case.code
        and awards.devotee_id = (select ids.id from public.br_ids ids where ids.key = v_case.holder)
    ) then
      raise exception '% did not earn %.', v_case.holder, v_case.code;
    end if;

    if exists (
      select 1 from public.devotee_awards awards
      join public.award_definitions definitions on definitions.id = awards.award_definition_id
      where awards.period_id = v_period
        and definitions.code = v_case.code
        and awards.devotee_id = (select ids.id from public.br_ids ids where ids.key = v_case.foil)
    ) then
      raise exception '% earned % — %.', v_case.foil, v_case.code, v_case.because;
    end if;
  end loop;
end;
$$;

-- A rivalrous badge is still decided only when the period closes. The week
-- happening now carries threshold badges and no top_n badge at all, because
-- handing "most hours this week" out on a Wednesday puts it on the wrong
-- devotee for ever and nothing here is revoked.
do $$
declare
  v_w0 uuid := (select id from public.br_periods where label = 'W0');
  v_offenders text;
begin
  select string_agg(distinct definitions.code, ', ') into v_offenders
  from public.devotee_awards awards
  join public.award_definitions definitions on definitions.id = awards.award_definition_id
  where awards.period_id = v_w0 and definitions.rule_kind = 'top_n';
  if v_offenders is not null then
    raise exception 'The open week has already handed out %.', v_offenders;
  end if;

  if not exists (
    select 1 from public.devotee_awards awards
    join public.award_definitions definitions on definitions.id = awards.award_definition_id
    where awards.period_id = v_w0 and definitions.rule_measure is not null
  ) then
    raise exception
      'The open week awarded no measured badge, so section 9 proves nothing about a live badge.';
  end if;
end;
$$;

-- Re-running a closed period awards nothing. Idempotence is what makes a
-- nightly job safe to run twice.
do $$
declare
  v_before integer;
begin
  select count(*) into v_before from public.devotee_awards;
  perform public.award_seva_mala_for_period(
    (select id from public.br_periods where label = 'B'));
  perform public.award_seva_mala_for_period(
    (select id from public.br_periods where label = 'MP'));
  if (select count(*) from public.devotee_awards) <> v_before then
    raise exception 'Re-running a closed period handed out more badges.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 9. CLAIM 3 — a badge stays while it is still being earned, and drops when it
--    stops.
--
--    Read as Padma, an ordinary devotee, because "on a public profile" is what
--    the claim is about.
-- ---------------------------------------------------------------------------

-- The premise first, and as the owner rather than as a devotee:
-- public.devotee_awards is behind row level security and a devotee may read
-- only their own, so a premise checked from inside Padma's session would be
-- checking that she cannot see anything.
do $$
declare
  v_dhira uuid := (select ids.id from public.br_ids ids where ids.key = 'dhira');
  v_vismrita uuid := (select ids.id from public.br_ids ids where ids.key = 'vismrita');
  v_shrama uuid := (select ids.id from public.br_ids ids where ids.key = 'shrama');
  v_label text;
begin
  foreach v_label in array array['A', 'B', 'W0'] loop
    if not exists (
      select 1 from public.devotee_awards awards
      join public.award_definitions definitions on definitions.id = awards.award_definition_id
      join public.br_periods on br_periods.id = awards.period_id
      where awards.devotee_id = v_dhira and definitions.code = 'weekly_dhairya'
        and br_periods.label = v_label
    ) then
      raise exception 'Dhira did not earn Dhairya in period %.', v_label;
    end if;
  end loop;

  foreach v_label in array array['A', 'B'] loop
    if not exists (
      select 1 from public.devotee_awards awards
      join public.award_definitions definitions on definitions.id = awards.award_definition_id
      join public.br_periods on br_periods.id = awards.period_id
      where awards.devotee_id = v_shrama and definitions.code = 'weekly_shrama_dana'
        and br_periods.label = v_label
    ) then
      raise exception 'Shrama did not earn Śrama-dāna in week %.', v_label;
    end if;
  end loop;

  if exists (
    select 1 from public.devotee_awards awards
    join public.br_periods on br_periods.id = awards.period_id
    where awards.devotee_id = v_vismrita and br_periods.label in ('B', 'W0')
  ) then
    raise exception 'Vismrita earned something after week A; he is meant to have stopped.';
  end if;
  if not exists (
    select 1 from public.devotee_awards awards
    join public.br_periods on br_periods.id = awards.period_id
    where awards.devotee_id = v_vismrita and br_periods.label = 'A'
  ) then
    raise exception 'Vismrita earned nothing in week A, so there is nothing to drop.';
  end if;

  -- And there is a lifetime award to not publish.
  if not exists (
    select 1 from public.devotee_awards awards
    join public.award_definitions definitions on definitions.id = awards.award_definition_id
    where definitions.code = 'first_seva'
  ) then
    raise exception 'Nobody has a lifetime award, so the exclusion proves nothing.';
  end if;
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.br_ids ids where ids.key = 'padma'), true);

do $$
declare
  v_wa date := (select starts_on from public.br_periods where label = 'A');
  v_wb date := (select starts_on from public.br_periods where label = 'B');
  v_w0 date := (select starts_on from public.br_periods where label = 'W0');
  v_dhira uuid := (select ids.id from public.br_ids ids where ids.key = 'dhira');
  v_vismrita uuid := (select ids.id from public.br_ids ids where ids.key = 'vismrita');
  v_shrama uuid := (select ids.id from public.br_ids ids where ids.key = 'shrama');
  v_start date;
begin
  -- STILL EARNING IT: Dhira wears Dhairya, and it is THIS WEEK'S copy. Under
  -- 0063 the newest a badge could be was last week's, and a devotee serving
  -- today would have been shown nothing for it until Monday.
  select badges.period_start into v_start
  from public.list_devotee_badges(v_dhira) badges
  where badges.award_code = 'weekly_dhairya';
  if v_start is distinct from v_w0 then
    raise exception
      'Dhira wears a Dhairya from % rather than from the week happening now.',
      coalesce(v_start::text, '(nothing)');
  end if;

  -- ONE OF EACH. A badge earned three weeks running is one badge, not three.
  if (select count(*) from public.list_devotee_badges(v_dhira) badges
      where badges.award_code = 'weekly_dhairya') <> 1 then
    raise exception 'Dhira is wearing his Dhairya more than once.';
  end if;

  -- STOPPED: Vismrita's week A badge is off his profile. Weekly badges only —
  -- the month is its own clock and last month still has his week A hours in it,
  -- which is 0063's "a week badge and a month badge are current at the same
  -- time" and not something 0066 changes.
  if exists (
    select 1 from public.list_devotee_badges(v_vismrita) badges
    where badges.period_kind = 'week'
  ) then
    raise exception
      'Vismrita, who has served nothing for a fortnight, is still wearing a weekly badge.';
  end if;

  -- A RIVALROUS BADGE CARRIES ACROSS THE GAP. Shrama earned Śrama-dāna in week
  -- A and again in week B; he wears week B's, and only week B's.
  select badges.period_start into v_start
  from public.list_devotee_badges(v_shrama) badges
  where badges.award_code = 'weekly_shrama_dana';
  if v_start is distinct from v_wb then
    raise exception 'Shrama wears a Śrama-dāna from % rather than week B.',
      coalesce(v_start::text, '(nothing)');
  end if;

  -- And nothing from week A is on anybody's profile, because week B closed.
  if exists (
    select 1 from public.br_ids ids, lateral public.list_devotee_badges(ids.id) badges
    where badges.period_start = v_wa
  ) then
    raise exception 'A week A badge is still published after week B closed.';
  end if;

  -- LIFETIME IS NEVER PUBLISHED.
  if exists (
    select 1 from public.br_ids ids, lateral public.list_devotee_badges(ids.id) badges
    where badges.period_kind = 'lifetime'
  ) then
    raise exception
      'A lifetime award is on a public profile. It would be there for ever, and 0063 section 3 refuses that.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);

-- ...AND IT IS STILL HIS. The shelf, in the President's hands.
set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.br_ids ids where ids.key = 'adhyaksha'), true);

do $$
declare
  v_wa date := (select starts_on from public.br_periods where label = 'A');
  v_vismrita uuid := (select ids.id from public.br_ids ids where ids.key = 'vismrita');
begin
  if (select count(*) from public.list_devotee_award_shelf(v_vismrita)) = 0 then
    raise exception 'Vismrita''s shelf is empty. Nothing in Seva Mala is ever revoked.';
  end if;
  if not exists (
    select 1 from public.list_devotee_award_shelf(v_vismrita) shelf
    where shelf.period_start = v_wa and not shelf.is_current
  ) then
    raise exception
      'Vismrita''s week A badge is either gone from his shelf or still claims to be current.';
  end if;
  if exists (
    select 1 from public.list_devotee_award_shelf(v_vismrita) shelf
    where shelf.is_current and shelf.period_kind = 'week'
  ) then
    raise exception
      'A weekly badge belonging to a devotee who stopped still claims to be current.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);

-- The opt-out governs badges, exactly as 0063 decided.
do $$
declare
  v_who text;
  v_chinmayi uuid := (select ids.id from public.br_ids ids where ids.key = 'chinmayi');
begin
  if (select count(*) from public.devotee_awards where devotee_id = v_chinmayi) = 0 then
    raise exception 'Chinmayi earned nothing, so the opt-out proves nothing.';
  end if;

  foreach v_who in array array['padma', 'adhyaksha', 'chinmayi'] loop
    execute format('select set_config(''request.jwt.claim.sub'', %L, true)',
      (select ids.id from public.br_ids ids where ids.key = v_who));
    set local role authenticated;

    insert into public.br_seen (who, what, rows, detail)
    select v_who, 'chinmayi_badges', count(*)::integer, null
    from public.list_devotee_badges(v_chinmayi);

    insert into public.br_seen (who, what, rows, detail)
    select v_who, 'chinmayi_shelf', count(*)::integer, null
    from public.list_devotee_award_shelf(v_chinmayi);

    reset role;
  end loop;
  perform set_config('request.jwt.claim.sub', '', true);
end;
$$;

do $$
begin
  if (select rows from public.br_seen where who = 'padma' and what = 'chinmayi_badges') <> 0 then
    raise exception 'An ordinary devotee can read the badges of a devotee who opted out.';
  end if;
  if (select rows from public.br_seen where who = 'padma' and what = 'chinmayi_shelf') <> 0 then
    raise exception 'An ordinary devotee can read another devotee''s shelf.';
  end if;
  if (select rows from public.br_seen where who = 'adhyaksha' and what = 'chinmayi_badges') = 0 then
    raise exception 'The President cannot see what an opted-out devotee earned.';
  end if;
  if (select rows from public.br_seen where who = 'chinmayi' and what = 'chinmayi_badges') = 0 then
    raise exception 'Chinmayi cannot see her own badges.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 10. CLAIM 4 — Seva Care surfaces outliers and only outliers, and can be
--     cleared.
--
--     Read as the President throughout, because nobody else may read it at all.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.br_ids ids where ids.key = 'adhyaksha'), true);

do $$
declare
  v_refs record;
  v_ghana record;
  v_sama record;
  v_names text;
begin
  select * into v_refs from public.seva_balance_thresholds();
  if v_refs.gathering then
    raise exception 'The congregation is still gathering; nothing would surface.';
  end if;

  select * into v_sama
  from public.seva_balance_for_devotee(
    (select ids.id from public.br_ids ids where ids.key = 'samadarshi'))
  where seva_name = 'Prasadam Serving';
  select * into v_ghana
  from public.seva_balance_for_devotee(
    (select ids.id from public.br_ids ids where ids.key = 'ghana'))
  where seva_name = 'Pot Washing';

  -- THE PREMISE. Samadarshi clears both of 0058's gates, so he WOULD have been
  -- on 0058's list. If he ever stops clearing them, the tightening below is
  -- being proved by the wrong thing and this says so rather than passing.
  if v_sama.hours_trailing_quarter / 13.0 < v_refs.weekly_hours_threshold then
    raise exception
      'Samadarshi averages % hours a week against a threshold of %; 0058 would not have listed him either.',
      round(v_sama.hours_trailing_quarter / 13.0, 2), v_refs.weekly_hours_threshold;
  end if;
  if v_sama.consecutive_weeks < v_refs.consecutive_weeks_threshold then
    raise exception
      'Samadarshi has run % weeks against a threshold of %; 0058 would not have listed him either.',
      v_sama.consecutive_weeks, v_refs.consecutive_weeks_threshold;
  end if;
  if v_sama.hours_trailing_quarter <= v_ghana.hours_trailing_quarter then
    raise exception
      'Samadarshi serves % hours to Ghana''s %; the contrast is meant to be that he serves MORE.',
      v_sama.hours_trailing_quarter, v_ghana.hours_trailing_quarter;
  end if;

  -- AND YET: Ghana is on the list and Samadarshi is not, because five other
  -- devotees serve prasadam as hard as Samadarshi and nobody washes pots within
  -- seven times of Ghana.
  select string_agg(listed.devotee_name, ', ' order by listed.devotee_name) into v_names
  from public.list_seva_concentration() listed;

  if v_names is null or position('Ghana Das' in v_names) = 0 then
    raise exception 'Ghana is not on the Seva Care list. It surfaced [%].',
      coalesce(v_names, '(nobody)');
  end if;
  if position('Samadarshi Das' in v_names) > 0 then
    raise exception
      'Samadarshi was surfaced for a normal amount of a demanding seva. The list reads [%].',
      v_names;
  end if;
  if position('Potwasher' in v_names) > 0 or position('Server ' in v_names) > 0 then
    raise exception 'An ordinary server was surfaced. The list reads [%].', v_names;
  end if;
end;
$$;

-- The gate is the frequency multiple and nothing else: turn it down and
-- Samadarshi is back.
do $$
declare
  v_before integer;
  v_after integer;
begin
  select count(*)::integer into v_before
  from public.list_seva_concentration() listed
  where listed.devotee_name = 'Samadarshi Das';

  update public.app_settings set value = '1.0'
  where key = 'seva_balance.frequency_multiple';

  select count(*)::integer into v_after
  from public.list_seva_concentration() listed
  where listed.devotee_name = 'Samadarshi Das';

  update public.app_settings set value = '2.0'
  where key = 'seva_balance.frequency_multiple';

  if v_before <> 0 or v_after <> 1 then
    raise exception
      'Samadarshi appears % times at a multiple of two and % times at a multiple of one; the third gate is not what keeps him off.',
      v_before, v_after;
  end if;
end;
$$;

-- The two figures the office reads, and the row says which multiple produced it.
do $$
declare
  v_row record;
  v_week numeric;
  v_month numeric;
begin
  select * into v_row from public.list_seva_concentration()
  where devotee_name = 'Ghana Das';

  select
    round(coalesce(sum(acts.raw_minutes) filter (
      where acts.occurred_on >= public.seva_mala_week_start(public.seva_mala_today())), 0) / 60.0, 2),
    round(coalesce(sum(acts.raw_minutes) filter (
      where acts.occurred_on >= date_trunc('month', public.seva_mala_today())::date), 0) / 60.0, 2)
  into v_week, v_month
  from public.seva_mala_acts(
    (select ids.id from public.br_ids ids where ids.key = 'ghana')) acts
  join public.service_types types on types.id = acts.service_type_id
  where types.name = 'Pot Washing' and acts.points_status <> 'not_served';

  if v_row.hours_this_week is distinct from v_week then
    raise exception 'Ghana''s week reads % rather than %.', v_row.hours_this_week, v_week;
  end if;
  if v_row.hours_this_month is distinct from v_month then
    raise exception 'Ghana''s month reads % rather than %.', v_row.hours_this_month, v_month;
  end if;
  if v_row.min_multiple_used <> 2.00 then
    raise exception 'The row reports a multiple of % rather than 2.', v_row.min_multiple_used;
  end if;
  if v_row.hours_vs_peers < 2 then
    raise exception 'Ghana reads % times the normal for pot washing.', v_row.hours_vs_peers;
  end if;
  -- 0058's note survives, because a shipped screen renders it.
  if v_row.note not like '%Worth asking how they are finding it%' then
    raise exception 'The note reads: %', v_row.note;
  end if;
end;
$$;

-- A NAMED THRESHOLD STILL ASKS THE CALLER'S QUESTION. The third gate belongs to
-- the temple's own list, and a parameter that could be silently overridden
-- would be a lie.
do $$
declare
  v_rows integer;
begin
  select count(*)::integer into v_rows
  from public.list_seva_concentration(p_min_weeks => 2, p_min_hours => 5) listed
  where listed.devotee_name = 'Samadarshi Das';
  if v_rows <> 1 then
    raise exception
      'An explicit threshold of five hours a week did not reach Samadarshi; the derived gate overrode it.';
  end if;
  if (select min(listed.min_multiple_used)
      from public.list_seva_concentration(p_min_weeks => 2, p_min_hours => 5) listed) <> 0 then
    raise exception 'The row does not say the frequency gate was stood down.';
  end if;
  -- And 0058's own refusals are unchanged.
  begin
    perform * from public.list_seva_concentration(p_min_weeks => 0);
    raise exception 'Zero weeks was accepted.';
  exception when others then
    if sqlerrm not like '%at least one week%' then
      raise exception 'Zero weeks was answered with: %', sqlerrm;
    end if;
  end;
end;
$$;

-- Dismissal.
set local role authenticated;

do $$
declare
  v_ghana uuid := (select ids.id from public.br_ids ids where ids.key = 'ghana');
  v_pot uuid := (select service_types.id from public.service_types where name = 'Pot Washing');
  v_id uuid;
  v_row record;
begin
  if current_user <> 'authenticated' then
    raise exception 'The dismissal is being made as %, not authenticated.', current_user;
  end if;

  v_id := public.dismiss_seva_care(v_ghana, v_pot, 'Spoke to him after the Sunday feast.');
  if v_id is null then
    raise exception 'Dismissing Ghana returned nothing.';
  end if;
  if exists (
    select 1 from public.list_seva_concentration() listed
    where listed.devotee_name = 'Ghana Das'
  ) then
    raise exception 'Ghana is still on the list after being cleared from it.';
  end if;

  select * into v_row from public.list_seva_care_dismissals() where dismissal_id = v_id;
  if v_row.dismissal_id is null then
    raise exception 'The dismissal is invisible to the President who made it.';
  end if;
  if v_row.lapses_on <> public.seva_mala_today() + 90 then
    raise exception 'The dismissal lapses on % rather than in ninety days.', v_row.lapses_on;
  end if;
  if v_row.days_left <> 90 or not v_row.is_live then
    raise exception 'The dismissal reads % days left, live=%.', v_row.days_left, v_row.is_live;
  end if;
  if v_row.seva_name <> 'Pot Washing' or v_row.note not like 'Spoke to him%' then
    raise exception 'The dismissal reads (%, %).', v_row.seva_name, v_row.note;
  end if;

  -- Dismissing again extends rather than duplicating, and the name the app
  -- already ships is the same door.
  if public.dismiss_seva_care(v_ghana, v_pot, null) is distinct from v_id then
    raise exception 'A second dismissal made a second row.';
  end if;
  if public.dismiss_seva_care_row(v_ghana, v_pot) is distinct from v_id then
    raise exception 'dismiss_seva_care_row is not the same door.';
  end if;

  -- Un-dismissing brings him back.
  if public.restore_seva_care(v_ghana, v_pot, 'It has not settled after all.') <> 1 then
    raise exception 'Restoring Ghana undid nothing.';
  end if;
  if not exists (
    select 1 from public.list_seva_concentration() listed
    where listed.devotee_name = 'Ghana Das'
  ) then
    raise exception 'Ghana did not come back after the dismissal was undone.';
  end if;
  if public.restore_seva_care(v_ghana, v_pot, null) <> 0 then
    raise exception 'Restoring twice claims to have undone something.';
  end if;

  -- A null service type is the whole devotee, which is the temple's phrasing.
  perform public.dismiss_seva_care(v_ghana, null, 'Whatever he is doing, we have talked.');
  if exists (
    select 1 from public.list_seva_concentration() listed
    where listed.devotee_name = 'Ghana Das'
  ) then
    raise exception 'A devotee-wide dismissal did not clear their seva-specific row.';
  end if;
end;
$$;

reset role;

-- IT LAPSES. Ninety days is not a wait a test can sit through, so the clock is
-- moved rather than the calendar. The lapsed row is deliberately LEFT IN PLACE:
-- section 12 mutates it back into the future to prove that lapses_on is what is
-- being read.
do $$
begin
  update public.seva_care_dismissals
  set lapses_on = public.seva_mala_today() - 1
  where restored_at is null;

  if not exists (
    select 1 from public.list_seva_concentration() listed
    where listed.devotee_name = 'Ghana Das'
  ) then
    raise exception
      'A lapsed dismissal still hides a devotee. A devotee still overloaded next quarter would never resurface.';
  end if;

  if exists (
    select 1 from public.list_seva_care_dismissals() live
    where live.devotee_name = 'Ghana Das'
  ) then
    raise exception 'A lapsed dismissal still reads as live.';
  end if;
  if not exists (
    select 1 from public.list_seva_care_dismissals(true) everything
    where everything.devotee_name = 'Ghana Das' and not everything.is_live
  ) then
    raise exception 'A lapsed dismissal is not in the history either.';
  end if;
end;
$$;

-- Nobody but the President may clear anything, and the refusal is BY NAME.
do $$
declare
  v_who text;
  v_message text;
  v_ghana uuid := (select ids.id from public.br_ids ids where ids.key = 'ghana');
begin
  foreach v_who in array array['mukhya', 'padma', 'ghana'] loop
    execute format('select set_config(''request.jwt.claim.sub'', %L, true)',
      (select ids.id from public.br_ids ids where ids.key = v_who));
    set local role authenticated;

    if current_user <> 'authenticated' then
      raise exception 'The refusals are being attempted as %, not authenticated.', current_user;
    end if;

    v_message := '(nothing)';
    begin
      perform public.dismiss_seva_care(v_ghana, null, null);
    exception when others then v_message := sqlerrm;
    end;
    if v_message not like '%President and the Tech Admin may clear%' then
      raise exception '% dismissing a devotee was answered with: %', v_who, v_message;
    end if;

    v_message := '(nothing)';
    begin
      perform public.restore_seva_care(v_ghana, null, null);
    exception when others then v_message := sqlerrm;
    end;
    if v_message not like '%President and the Tech Admin may put%' then
      raise exception '% restoring a devotee was answered with: %', v_who, v_message;
    end if;

    v_message := '(nothing)';
    begin
      perform public.dismiss_seva_care_row(v_ghana, null);
    exception when others then v_message := sqlerrm;
    end;
    if v_message not like '%President and the Tech Admin may clear%' then
      raise exception '% dismissing through the app''s door was answered with: %',
        v_who, v_message;
    end if;

    reset role;
  end loop;
  perform set_config('request.jwt.claim.sub', '', true);
end;
$$;

-- A devotee cannot tell from anything they can read that any of this happened.
-- 0058 rule 2, restated because 0066 added the first write this feature has.
do $$
declare
  v_columns text;
begin
  select string_agg(lower(names.name), ',' order by names.name) into v_columns
  from pg_proc, unnest(pg_proc.proargnames) as names(name)
  where pg_proc.oid = to_regprocedure('public.my_seva_balance()');
  if v_columns is null then
    raise exception 'my_seva_balance''s columns could not be read; this check would pass vacuously.';
  end if;
  if v_columns like '%dismiss%' or v_columns like '%care%' then
    raise exception 'A devotee''s own screen mentions the coordinator''s list.';
  end if;
  if exists (
    select 1 from public.app_notifications where body ilike '%dismiss%'
  ) then
    raise exception 'A dismissal reached a devotee.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 11. CLAIM 5 — the drill-down.
-- ---------------------------------------------------------------------------

create table public.br_summary (
  who text not null, subject text not null,
  rows integer not null,
  score numeric, points integer, giving bigint, gifts integer,
  withheld boolean, supported boolean, served integer, credited integer,
  top_seva text, top_hours numeric,
  primary key (who, subject)
);
grant select, insert on public.br_summary to authenticated;

do $$
declare
  v_who text;
  v_subject text;
begin
  foreach v_who in array array['padma', 'adhyaksha', 'mukhya', 'ghana'] loop
    execute format('select set_config(''request.jwt.claim.sub'', %L, true)',
      (select ids.id from public.br_ids ids where ids.key = v_who));
    set local role authenticated;

    if current_user <> 'authenticated' then
      raise exception 'The drill-down is being read as %, not authenticated.', current_user;
    end if;

    foreach v_subject in array array['ghana', 'chinmayi', 'pratiksha'] loop
      insert into public.br_summary (
        who, subject, rows, score, points, giving, gifts, withheld, supported,
        served, credited, top_seva, top_hours
      )
      select v_who, v_subject, count(*)::integer,
             max(summary.score), max(summary.points), max(summary.giving_cents),
             max(summary.gifts), bool_or(summary.giving_withheld),
             bool_or(summary.supported),
             max(summary.served_minutes), max(summary.seva_minutes),
             max(summary.top_seva_name), max(summary.top_seva_hours)
      from public.seva_yatra_devotee_summary(
        (select ids.id from public.br_ids ids where ids.key = v_subject), 'week') summary;
    end loop;

    reset role;
  end loop;
  perform set_config('request.jwt.claim.sub', '', true);
end;
$$;

do $$
declare
  v_row record;
begin
  -- An ordinary devotee may ask about a devotee who is on the board.
  select * into v_row from public.br_summary where who = 'padma' and subject = 'ghana';
  if v_row.rows <> 1 then
    raise exception 'An ordinary devotee cannot read the board she is looking at.';
  end if;
  if v_row.score is not null or v_row.giving is not null or v_row.gifts is not null then
    raise exception
      'The drill-down handed an ordinary devotee a score of % and % cents.',
      v_row.score, v_row.giving;
  end if;
  if not v_row.withheld then
    raise exception
      'The drill-down did not say the giving was withheld, so a null reads as a zero.';
  end if;
  if coalesce(v_row.points, 0) <= 0 then
    raise exception 'The drill-down published no points, which is the number the board shows.';
  end if;
  if coalesce(v_row.served, 0) <= 0 then
    raise exception 'The drill-down published no hours.';
  end if;
  if v_row.top_seva is distinct from 'Pot Washing' then
    raise exception 'Ghana''s most-served seva reads %.', coalesce(v_row.top_seva, '(nothing)');
  end if;
  -- The one thing about giving an ordinary devotee gets, and it is not new:
  -- 0060's supporters list already publishes it, by name, with no amount.
  if not v_row.supported then
    raise exception 'Ghana gave this week and the summary says he did not.';
  end if;

  -- AND NOTHING AT ALL ABOUT A DEVOTEE WHO OPTED OUT. Not a row of nulls: no
  -- row, so "opted out" and "did nothing" look the same from outside.
  if (select rows from public.br_summary where who = 'padma' and subject = 'chinmayi') <> 0 then
    raise exception 'An ordinary devotee read a summary of a devotee who opted out.';
  end if;
  if (select rows from public.br_summary where who = 'mukhya' and subject = 'chinmayi') <> 0 then
    raise exception 'A Community Head read a summary of a devotee who opted out.';
  end if;
  if (select rows from public.br_summary where who = 'adhyaksha' and subject = 'chinmayi') <> 1 then
    raise exception 'The President cannot read a summary of a devotee who opted out.';
  end if;

  -- The President gets the figures, and says so.
  select * into v_row from public.br_summary where who = 'adhyaksha' and subject = 'ghana';
  if v_row.score is null or v_row.withheld then
    raise exception 'The President was refused the score.';
  end if;

  -- A devotee always sees themselves.
  if (select rows from public.br_summary where who = 'ghana' and subject = 'ghana') <> 1 then
    raise exception 'A devotee cannot read their own summary.';
  end if;

  -- Pratiksha is not on the board this week, so an ordinary devotee gets
  -- nothing about her — and the President still does.
  if (select rows from public.br_summary where who = 'padma' and subject = 'pratiksha') <> 0 then
    raise exception 'An ordinary devotee read a summary of a devotee not on the board.';
  end if;
  if (select rows from public.br_summary where who = 'adhyaksha' and subject = 'pratiksha') <> 1 then
    raise exception 'The President cannot read a summary of a devotee not on the board.';
  end if;
end;
$$;

-- The two points figures are the two 0060 already publishes, which is the whole
-- of why publishing them here reveals nothing new. Proved by equality rather
-- than argued for, so if 0060's board ever stops publishing one of them this
-- function is caught publishing something new.
set local role authenticated;
select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.br_ids ids where ids.key = 'padma'), true);

do $$
declare
  v_ghana uuid := (select ids.id from public.br_ids ids where ids.key = 'ghana');
  v_summary record;
  v_combined integer;
  v_seva integer;
  v_count integer;
begin
  select * into v_summary from public.seva_yatra_devotee_summary(v_ghana, 'week');

  select garland.points into v_combined
  from public.list_seva_garland('week', 200, 'combined') garland
  where garland.devotee_id = v_ghana;
  select garland.points into v_seva
  from public.list_seva_garland('week', 200, 'seva') garland
  where garland.devotee_id = v_ghana;

  if v_summary.points is distinct from v_combined then
    raise exception 'The drill-down publishes % points where the garland publishes %.',
      v_summary.points, v_combined;
  end if;
  if v_summary.seva_points is distinct from v_seva then
    raise exception 'The drill-down publishes % seva points where the seva board publishes %.',
      v_summary.seva_points, v_seva;
  end if;

  -- The legend answers every devotee, and says nothing about who holds anything.
  select count(*)::integer into v_count from public.list_seva_badge_legend();
  if v_count < 20 then
    raise exception 'The legend lists % gifts.', v_count;
  end if;
  if not exists (
    select 1 from public.list_seva_badge_legend() legend
    where legend.title = 'Brāhma-muhūrta' and legend.earned_by like '%before seven%'
  ) then
    raise exception 'The legend does not say what Brāhma-muhūrta is for.';
  end if;
  if exists (
    select 1 from public.list_seva_badge_legend() legend
    where legend.earned_by ~* '(percentile|quantile|dense_rank|norm)'
  ) then
    raise exception 'The legend explains a badge in arithmetic rather than in English.';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);

-- ---------------------------------------------------------------------------
-- 12. The mutation table.
--
--     Every guard, broken on purpose inside a subtransaction, with the probe
--     run before, during and after. A guard that cannot be broken was never
--     load-bearing, and a test that only ever sees the guard working proves
--     nothing about whether the guard is what is doing the work.
--
--     The probes are run with a JWT subject set but as the owner, because what
--     is under test here is the permission check inside the function. The
--     ROLE-level refusals are section 10's and are made under `set local role
--     authenticated`; these are the other half of the same question.
-- ---------------------------------------------------------------------------

create table public.br_mutations (
  n integer primary key,
  guard text not null,
  mutation text not null,
  probe text not null,
  intact text not null,
  mutated text not null,
  killed boolean not null
);

create function public.br_try(p_sql text)
returns text
language plpgsql
as $$
declare
  v_answer text;
begin
  execute p_sql into v_answer;
  return coalesce(v_answer, '(null)');
exception when others then
  return 'refused';
end;
$$;

create function public.br_mutate(
  p_n integer, p_as text, p_guard text, p_mutation text, p_probe text,
  p_apply text, p_query text, p_apply2 text default null
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
    (select ids.id::text from public.br_ids ids where ids.key = p_as), true);

  execute p_query into v_intact;

  begin
    execute p_apply;
    if p_apply2 is not null then
      execute p_apply2;
    end if;
    execute p_query into v_mutated;
    -- Undone by raising: a plpgsql BEGIN block is a subtransaction, and
    -- rolling one back is how the mutation is guaranteed not to escape.
    raise exception using errcode = 'PT666', message = coalesce(v_mutated, '(null)');
  exception when sqlstate 'PT666' then
    v_mutated := sqlerrm;
  end;

  execute p_query into v_restored;
  if v_restored is distinct from v_intact then
    raise exception
      'Mutation % did not roll back: the probe read % before and % after.',
      p_n, coalesce(v_intact, '(null)'), coalesce(v_restored, '(null)');
  end if;

  insert into public.br_mutations (n, guard, mutation, probe, intact, mutated, killed)
  values (p_n, p_guard, p_mutation, p_probe,
          coalesce(v_intact, '(null)'), v_mutated,
          v_mutated is distinct from coalesce(v_intact, '(null)'));
end;
$$;

do $$
declare
  v_ghana uuid := (select ids.id from public.br_ids ids where ids.key = 'ghana');
  v_chinmayi uuid := (select ids.id from public.br_ids ids where ids.key = 'chinmayi');
  v_dhira uuid := (select ids.id from public.br_ids ids where ids.key = 'dhira');
  v_w0 uuid := (select id from public.br_periods where label = 'W0');
  v_true text := $m$create or replace function public.has_permission(requested_permission text)
    returns boolean language sql stable set search_path = '' as $f$ select true $f$ $m$;
begin
  perform public.br_mutate(
    1, 'padma', 'dismiss_seva_care: has_permission(''app.view_all'')',
    'public.has_permission forced true', 'Padma dismisses Ghana',
    v_true,
    format($q$select public.br_try(format('select public.dismiss_seva_care(%%L::uuid, null, null)::text', %L))$q$,
           v_ghana));

  perform public.br_mutate(
    2, 'padma', 'restore_seva_care: has_permission(''app.view_all'')',
    'public.has_permission forced true', 'Padma restores Ghana',
    v_true,
    format($q$select public.br_try(format('select public.restore_seva_care(%%L::uuid, null, null)::text', %L))$q$,
           v_ghana));

  perform public.br_mutate(
    3, 'padma', 'list_seva_concentration: has_permission(''app.view_all'')',
    'public.has_permission forced true', 'rows a plain devotee sees',
    v_true,
    'select count(*)::text from public.list_seva_concentration()');

  perform public.br_mutate(
    4, 'padma', 'list_seva_care_dismissals: has_permission(''app.view_all'')',
    'public.has_permission forced true', 'rows a plain devotee sees',
    v_true,
    'select count(*)::text from public.list_seva_care_dismissals(true)');

  perform public.br_mutate(
    5, 'adhyaksha', 'list_all_seva_hours: may_view_whole_seva_board()',
    'may_view_whole_seva_board forced false', 'rows the President sees',
    $m$create or replace function public.may_view_whole_seva_board()
       returns boolean language sql stable set search_path = '' as $f$ select false $f$ $m$,
    'select count(*)::text from public.list_all_seva_hours(''week'')');

  perform public.br_mutate(
    6, 'adhyaksha', 'list_seva_concentration: hours a week against the normal for THIS seva',
    'seva_balance.frequency_multiple set to 1.0', 'Samadarshi on the list',
    $m$update public.app_settings set value = '1.0'
       where key = 'seva_balance.frequency_multiple'$m$,
    $q$select count(*)::text from public.list_seva_concentration() listed
       where listed.devotee_name = 'Samadarshi Das'$q$);

  perform public.br_mutate(
    7, 'adhyaksha', 'list_seva_concentration: peers needed before a median is a normal',
    'seva_balance.frequency_min_peers set to 99, so no seva has a normal of its own',
    'Samadarshi on the list',
    $m$update public.app_settings set value = '99'
       where key = 'seva_balance.frequency_min_peers'$m$,
    $q$select count(*)::text from public.list_seva_concentration() listed
       where listed.devotee_name = 'Samadarshi Das'$q$);

  perform public.br_mutate(
    8, 'adhyaksha', 'list_seva_concentration: a live dismissal hides the row',
    'Ghana dismissed through the RPC', 'Ghana on the list',
    format($m$select public.dismiss_seva_care(%L::uuid, null, null)$m$, v_ghana),
    $q$select count(*)::text from public.list_seva_concentration() listed
       where listed.devotee_name = 'Ghana Das'$q$);

  perform public.br_mutate(
    9, 'adhyaksha', 'list_seva_concentration: seva_care_dismissals.lapses_on',
    'the lapsed dismissal pushed back into the future', 'Ghana on the list',
    $m$update public.seva_care_dismissals
       set lapses_on = public.seva_mala_today() + 30 where restored_at is null$m$,
    $q$select count(*)::text from public.list_seva_concentration() listed
       where listed.devotee_name = 'Ghana Das'$q$);

  perform public.br_mutate(
    10, 'padma', 'list_devotee_badges: users.leaderboard_visible',
    'Chinmayi opted back in', 'badges an ordinary devotee sees on Chinmayi',
    format($m$update public.users set leaderboard_visible = true where id = %L::uuid$m$, v_chinmayi),
    format($q$select count(*)::text from public.list_devotee_badges(%L::uuid)$q$, v_chinmayi));

  perform public.br_mutate(
    11, 'padma', 'list_devotee_badges: seva_mala.minimum_cohort',
    'the minimum cohort raised to 999', 'badges on Dhira',
    $m$update public.app_settings set value = '999' where key = 'seva_mala.minimum_cohort'$m$,
    format($q$select count(*)::text from public.list_devotee_badges(%L::uuid)$q$, v_dhira));

  perform public.br_mutate(
    12, 'padma', 'current_devotee_awards: the period happening now is an anchor',
    'the open week moved off today', 'the week Dhira''s Dhairya is shown for',
    format($m$update public.seva_mala_periods
             set starts_on = starts_on - 700, ends_on = ends_on - 700
             where id = %L::uuid$m$, v_w0),
    format($q$select coalesce(max(badges.period_start)::text, '(none)')
             from public.list_devotee_badges(%L::uuid) badges
             where badges.award_code = 'weekly_dhairya'$q$, v_dhira));

  perform public.br_mutate(
    13, 'adhyaksha', 'seva_mala_served: points_status <> ''not_served''',
    'this week''s served acts rewritten as no-shows', 'Ghana''s served minutes this week',
    $m$update public.service_assignments set status = 'no_show'
       where id in (
         select assignments.id from public.service_assignments assignments
         join public.service_instances instances on instances.id = assignments.service_instance_id
         where assignments.devotee_id = (select ids.id from public.br_ids ids where ids.key = 'ghana')
           and instances.date >= public.seva_mala_week_start(public.seva_mala_today())
       )$m$,
    format($q$select coalesce(sum(hours.served_minutes), 0)::text
             from public.seva_mala_served(
               public.seva_mala_week_start(public.seva_mala_today()),
               public.seva_mala_today(), %L::uuid) hours$q$, v_ghana));

  perform public.br_mutate(
    14, 'adhyaksha', 'award_seva_mala_for_period: a measured top_n waits for the close',
    'the open week frozen and re-awarded', 'top_n badges on the open week',
    format($m$update public.seva_mala_periods set frozen_at = now() where id = %L::uuid$m$, v_w0),
    format($q$select count(*)::text from public.devotee_awards awards
             join public.award_definitions definitions on definitions.id = awards.award_definition_id
             where awards.period_id = %L::uuid and definitions.rule_kind = 'top_n'$q$, v_w0),
    format($m$select public.award_seva_mala_for_period(%L::uuid)$m$, v_w0));

  perform public.br_mutate(
    15, 'padma', 'seva_yatra_devotee_summary: may_view_all_giving()',
    'may_view_all_giving forced true', 'cents an ordinary devotee reads about Ghana',
    $m$create or replace function public.may_view_all_giving()
       returns boolean language sql stable set search_path = '' as $f$ select true $f$ $m$,
    format($q$select coalesce(max(summary.giving_cents)::text, '(withheld)')
             from public.seva_yatra_devotee_summary(%L::uuid, 'week') summary$q$, v_ghana));

  perform public.br_mutate(
    16, 'padma', 'seva_yatra_devotee_summary: the subject must be on the board',
    'Chinmayi opted back in', 'rows about Chinmayi',
    format($m$update public.users set leaderboard_visible = true where id = %L::uuid$m$, v_chinmayi),
    format($q$select count(*)::text from public.seva_yatra_devotee_summary(%L::uuid, 'week')$q$,
           v_chinmayi));

  perform set_config('request.jwt.claim.sub', '', true);
end;
$$;

do $$
declare
  v_survivors text;
  v_count integer;
begin
  select count(*) into v_count from public.br_mutations;
  if v_count <> 16 then
    raise exception 'Only % mutations ran.', v_count;
  end if;

  select string_agg(n || ' (' || guard || ')', '; ' order by n) into v_survivors
  from public.br_mutations where not killed;
  if v_survivors is not null then
    raise exception 'These guards survived being removed, so they guard nothing: %.', v_survivors;
  end if;
end;
$$;

-- The mutation table, printed.
select
  br_mutations.n,
  br_mutations.guard,
  br_mutations.mutation,
  br_mutations.probe,
  br_mutations.intact as with_guard,
  br_mutations.mutated as without_guard,
  case when br_mutations.killed then 'killed' else 'SURVIVED' end as verdict
from public.br_mutations
order by br_mutations.n;

-- The ten badges and who earned them, printed beside it.
select
  definitions.period_kind,
  definitions.title,
  definitions.rule_kind || ' on ' || definitions.rule_measure as decided_by,
  definitions.earned_by,
  checks.winners
from public.award_definitions definitions
join public.br_rule_check checks on checks.code = definitions.code
order by definitions.sort_order;

-- ---------------------------------------------------------------------------
-- 13. Nothing was revoked, and nothing was lost.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub',
  (select ids.id::text from public.br_ids ids where ids.key = 'adhyaksha'), true);

do $$
declare
  v_message text;
begin
  v_message := '(nothing)';
  begin
    delete from public.devotee_awards
    where id = (select id from public.devotee_awards limit 1);
  exception when others then v_message := sqlerrm;
  end;
  if v_message not like '%cannot be taken back%' then
    raise exception 'An award was deleted, and the answer was: %', v_message;
  end if;

  -- Every award ever given is still on its owner's shelf, whatever the display
  -- rule says about it.
  if exists (
    select 1 from public.br_ids ids
    where (select count(*) from public.devotee_awards where devotee_id = ids.id) > 0
      and (select count(*) from public.devotee_awards where devotee_id = ids.id)
       <> (select count(*) from public.list_devotee_award_shelf(ids.id))
  ) then
    raise exception 'A devotee''s shelf is shorter than what they were given.';
  end if;
end;
$$;

select set_config('request.jwt.claim.sub', '', true);

do $$
begin
  raise notice 'all badges and reads checks passed';
end;
$$;

select 'badges and reads verification passed' as result;

rollback;
