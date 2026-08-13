-- The weekly timetable: one feed of dated seva occurrences, one clash answer,
-- and the temple's own daily programme drawn behind them.
-- Requires 202608040068_completion_truthfulness.sql.
--
-- The temple asked for a school timetable — days across the top, time down the
-- side, seva as blocks — and for a warning when a devotee is asked to serve at
-- a time they are already serving. Two client agents build the grid and the
-- warning on top of this file, so every shape here is a contract and is
-- written out in full rather than left to be discovered.
--
-- ---------------------------------------------------------------------------
-- 1. WHY THE FEED IS ONE CALL FOR A WINDOW AND NOT ONE CALL PER DEVOTEE.
--
--    A grid asks for a week and re-asks when the user pages. The obvious
--    shape — "give me devotee X's week", called once per devotee on screen —
--    is forty round trips for a forty-devotee temple and forty more on every
--    page turn. So public.list_seva_schedule takes a DATE WINDOW and an
--    OPTIONAL devotee, and the whole-temple week is the null case: one call,
--    one scan of public.service_instances over an indexed date range, one scan
--    of public.service_assignments, one scan of the coverage plans that touch
--    it. Nothing in this file loops, and nothing in it is called once per
--    person; §0 asserts that the two set-returning bodies are single SQL
--    statements so that a later edit cannot quietly make one of them a loop.
--
--    The cost that IS per-row is public.can_view_service_template, and only
--    for the distinct templates in the window (§4), and
--    public.can_view_service_instance, and only when the caller is not a board
--    viewer (§4). Both are bounded by the size of the answer, not by the size
--    of the congregation.
--
-- ---------------------------------------------------------------------------
-- 2. WHO IS SERVING, AFTER THE SWAPS. THE SERVER'S weeklyRoster.
--
--    202608030009 deliberately does NOT edit a weekly seva's standing roster
--    when a coverage plan is accepted, unless the swap is 'forever'. The
--    original keeps their service_template_assignees row so the seva returns
--    to them when the plan runs out. respond_to_coverage_range_offer DOES
--    rewrite the dated service_assignments — the original to 'withdrawn', the
--    substitute in as 'confirmed' — but only for instances that exist at the
--    moment the offer is accepted. public.generate_service_instances runs
--    nightly on a rolling horizon, and every occurrence it creates AFTER that
--    moment is built from the standing roster, so it names the ORIGINAL. A
--    'date_range' swap reaching past the horizon therefore produces dated rows
--    that name the wrong devotee, which is the exact bug src/features/services
--    weeklyRoster exists to correct on the client.
--
--    public.seva_schedule_servers is that correction, on the server, per dated
--    occurrence, in four rules:
--
--      a. Start from the assignments that are actually live on the occurrence:
--         status in ('assigned', 'confirmed', 'completed'). A 'withdrawn' or
--         'no_show' row is not somebody serving.
--
--      b. TAKE OUT a devotee for whom an accepted coverage plan is in force on
--         that date and that weekday — date_from <= date, date <= date_to or
--         date_to is null, and the date's dow is in the plan's days_of_week.
--         This is weeklyRoster's "only plans actually in force today", asked
--         per occurrence instead of once for now, because a timetable shows
--         next month as well as this afternoon.
--
--      c. PUT IN the substitute that plan names.
--
--      d. And then EVIDENCE OUTRANKS THE PLAN, in both directions, because a
--         plan says who is expected and an attendance mark says who was there:
--           - a covered original whose assignment is 'completed', or whose
--             attendance is 'served', STAYS. She turned up anyway; erasing her
--             from the timetable would erase service the scoring has already
--             counted.
--           - a named substitute who has a 'withdrawn' or 'no_show' row on
--             that very occurrence does NOT go in. He stepped away from this
--             one after agreeing to the range, and an explicit mark outranks a
--             standing arrangement — the same ordering public.seva_points_status
--             uses when it puts the terminal arms first.
--
--    Rules (b) and (c) run off public.service_coverage_plans directly rather
--    than off the template's roster, so all three coverage scopes are handled
--    by the same three lines: 'occurrence' (date_to = date_from), 'date_range'
--    (a bounded window) and 'forever' (date_to null). §7 of the verification
--    proves each scope separately, and proves the late-generation case that
--    only 'date_range' and 'occurrence' can produce.
--
-- ---------------------------------------------------------------------------
-- 3. WHAT A BLOCK IS ALLOWED TO SAY. THE THREE LEAKS THIS FILE COULD HAVE BEEN.
--
--    A timetable is the easiest place in the app to leak something, because it
--    is the one screen whose whole purpose is to show everything at once.
--
--    LEAK ONE — THE TEMPLATE ROW. 202608030009's public.can_view_service_template
--    does not grant a substitute the weekly seva behind the occurrence they are
--    covering, and that is on purpose: covering three Thursdays is not joining
--    the rota. So the feed returns template_id ONLY when the caller may open
--    that template, and null otherwise, while from_weekly_template is always
--    truthful. A block always knows whether it came from a weekly template; it
--    only carries the id when tapping through would be allowed.
--
--    LEAK TWO — THE CO-SERVERS. A devotee reading their own timetable sees the
--    whole roster of each occurrence they are on, which is what the temple
--    wants and what public.service_assignments' own policy already permits,
--    because can_view_service_instance is true for somebody assigned to it.
--    The exception is rule 2(c): a substitute named by a plan on an occurrence
--    generated after the plan was accepted has NO assignment row yet, so
--    can_view_service_instance is false for them and the roster is not theirs
--    to read. On exactly those blocks the feed returns their own entry and
--    nobody else's. The block is still there — it is their seva — but it does
--    not hand them a list of names RLS would refuse.
--
--    LEAK THREE — THE CLASH REPLY. A Volunteer may invite a named devotee
--    (202608040015) and therefore may ask whether that devotee is free, which
--    is the whole point of the clash RPC. That must not turn into "read any
--    devotee's diary". So the clash reply always gives the times and the
--    overlap — those are the facts the warning is made of — and gives the SEVA
--    NAME only when the caller could already read that occurrence under
--    can_view_service_instance, OR is the devotee being asked about, since
--    every row this returns is a seva that devotee is serving and naming a
--    devotee's own seva to them discloses nothing. name_visible says which
--    happened, so the client can word "you are serving Kitchen Cleanup" or
--    "you are serving another seva" without guessing.
--
--    The FEED does not gate the seva name, and the reason is the same one read
--    the other way: the only rows a caller who is not a board viewer can get
--    out of it are the occurrences they are themselves serving.
--
-- ---------------------------------------------------------------------------
-- 4. THE CLASH RPC DECIDES NOTHING, AND IS SHAPED SO THAT IT CANNOT.
--
--    "A devotee serving 12:00–13:30 must still be able to take a seva starting
--    13:15, because they may be able to finish early." So this returns rows
--    and never raises on a clash, is `stable` and writes nothing, and — §0 of
--    the verification — is called by no other function in the schema. It
--    cannot be wired into a guard later without that assertion failing.
--
--    Partial and total are the same query: the intersection of two tstzranges.
--    overlap_minutes lets the client word a fifteen-minute brush differently
--    from a collision, and covers_whole_request says the proposed seva is
--    entirely inside an existing one, which is the case where "only accept if
--    you can manage it" is not really available.
--
--    Half-open ranges, so 12:00–13:30 followed by 13:30–14:30 is NOT a clash.
--    Back-to-back seva is the normal shape of a temple day and warning about it
--    would train devotees to ignore the warning.
--
--    MIDNIGHT. The window is given as a Chicago date, a Chicago start time and
--    a length in minutes — the three columns a seva is actually stored in — so
--    a seva at 23:00 for 120 minutes is expressible and the function, not the
--    client, decides what instant that is. Candidate occurrences are prefiltered
--    to p_date - 1 .. p_date + 1: service_instances_duration_minutes_check caps
--    a seva at 720 minutes, so nothing starting more than a day earlier can
--    still be running, and nothing can start more than a day after a window
--    that itself cannot exceed a day. §0 asserts that 720 is still the cap; if
--    somebody widens it, this migration's own check is what tells them.
--
-- ---------------------------------------------------------------------------
-- 5. THE TEMPLE'S PROGRAMME IS A TABLE, NOT A CLIENT CONSTANT.
--
--    Mangala Arati at 4:30 is fixed, identical for everyone, and nobody signs
--    up for it. Every one of those facts argues for a constant in the app
--    bundle. One fact argues the other way and it is the temple's own:
--    "the temple may want to change a time one day without an app release."
--    A constant cannot be changed without a release, a TestFlight round and a
--    review queue; a row can be changed with one UPDATE. That is the whole
--    argument and it is decisive, because it is the only requirement in the
--    list that has a cost attached to getting it wrong.
--
--    Three supporting reasons:
--      - Two client agents are building against this. A constant would be
--        copied into a grid and into a warning and the two copies would drift.
--      - A table takes constraints. days_of_week is checked against 0..6 and
--        the length against 1..7, exactly as service_templates does, so a
--        typo is refused at write time rather than drawn at 25:00.
--      - Every other "the temple may change this" value in this schema is
--        already a row: app_settings, service_types, award_definitions.
--
--    NOT a JSON blob in app_settings, which is where this would have gone if
--    it were only about avoiding a release: a blob cannot be constrained,
--    cannot be ordered, and cannot be read a week at a time.
--
--    IT IS NOT SEVA AND IS SHAPED SO IT CANNOT BE MISTAKEN FOR SEVA. It lives
--    in its own table with no service_type_id, no slots, no assignments and no
--    join to service_instances; the read RPC is a different function from the
--    seva feed; and every row it returns carries kind = 'temple_programme'. A
--    grid that puts these behind the seva blocks cannot accidentally count one
--    as somebody's service, and public.list_seva_clashes does not look at this
--    table at all — nobody is assigned to Mangala Arati, so nobody can clash
--    with it.
--
--    THE GRID'S HOURS, 3:30am to 9:00pm, ARE A DISPLAY CHOICE AND MOSTLY NOT
--    MINE. They do not filter the feed: list_seva_schedule returns a 2am seva
--    if one exists, and a grid that cannot draw it should say so rather than
--    have the server hide it. But the two numbers exist for one reason — to
--    contain the programme, from Mangala Arati at 4:30 to the end of Sunday
--    Kirtan at 20:00 — and the moment the temple moves Mangala Arati to 4:00
--    the grid's first row is wrong. So they travel with the programme, as two
--    dials read by public.temple_timetable_hours, and they are advisory: the
--    server never enforces them.
--
-- ---------------------------------------------------------------------------
-- 6. WHO MAY READ THE WHOLE BOARD, AND WHY may_view_whole_seva_board IS RIGHT.
--
--    The temple named President, Tech Admin and Community Head.
--    public.may_view_whole_seva_board (202608040064) is
--    services.manage_recurring or app.view_all, which today is exactly
--    {president, tech} ∪ {core, president, tech} = {core, president, tech},
--    and 'core' IS the Community Head role. So it names the right three, and it
--    names them by what they are allowed to do rather than by role name, which
--    is 202608040048 §4's rule and the reason a fourth appointment tomorrow
--    does not need this file edited.
--
--    It is also the SAFE predicate here, which is the part worth checking
--    rather than assuming: every role it admits also holds services.view_all,
--    so public.can_view_service_instance is already true for them on every row
--    this feed can return. The whole-temple timetable therefore discloses
--    nothing that the same person could not read one instance at a time
--    through RLS — it is a faster path to data they already have, not a wider
--    one. §0 asserts that containment. If somebody ever grants
--    services.manage_recurring to a role without services.view_all, this
--    migration's check is what stops the timetable becoming the leak.
--
--    A devotee may read their OWN schedule — every devotee gets the same
--    timetable view of their own seva — and a board viewer may read ONE NAMED
--    devotee's, explicitly so they can see when somebody is free before asking
--    them. Any other combination raises, rather than returning zero rows: a
--    grid cannot tell "nobody is serving this week" from "you may not see
--    this" if both are an empty array, and the two client agents would both
--    have to guess. This is a deliberate departure from list_all_seva_hours,
--    which filters silently; that one answers a question where empty is a real
--    answer, and this one does not.
--
-- ---------------------------------------------------------------------------
-- 7. THE `servers` ARRAY, WRITTEN OUT, BECAUSE IT IS THE HALF OF THE CONTRACT
--    THAT A COLUMN TYPE DOES NOT DESCRIBE.
--
--    list_seva_schedule.servers is a jsonb ARRAY, never null — an untaken seva
--    is [] — sorted by devotee name. Each element:
--
--      devoteeId             uuid    who is serving, after the swaps
--      name                  text    public.users.name
--      assignmentId          uuid    NULL for a substitute a plan names on an
--                                    occurrence generated after the plan was
--                                    accepted: they are serving it and there is
--                                    no service_assignments row yet
--      assignmentStatus      text    'assigned' | 'confirmed' | 'completed',
--                                    NULL in the same case as assignmentId
--      attendance            text    'served' | 'absent' | 'excused' | null
--      pointsStatus          text    public.seva_points_status for this place;
--                                    'awaiting_completion' in the null case
--      isSubstitute          bool    true when a coverage plan put them here
--      coveringForDevoteeId  uuid    who handed it over. NULL when not a
--                                    substitute, and NULL when the reader is
--                                    neither a board viewer nor one of the two
--                                    people it is about
--      coveringForName       text    that devotee's name, on the same terms
--
--    roster_visible says whether that array is the WHOLE roster or only the
--    reader's own place on it (header §3, leak two). filled_slots is always the
--    true count either way, because a count is a number and not a name.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 0. The ground this stands on, asserted rather than assumed.
-- ---------------------------------------------------------------------------

do $$
declare
  v_missing text;
  v_role text;
begin
  -- 202608040068 must be in. "Nobody served this" is its fact, not one this
  -- file re-derives, and §4 of the feed reads its table by name.
  if to_regclass('public.service_instances_unserved') is null then
    raise exception
      'public.service_instances_unserved is missing. 202608040068 has to be applied before this file.';
  end if;
  for v_missing in
    select expected.name
    from (values
      ('public.service_instance_has_server(uuid)'),
      ('public.seva_points_status(text, text, text, boolean)'),
      ('public.may_view_whole_seva_board()'),
      ('public.can_view_service_instance(uuid)'),
      ('public.can_view_service_template(uuid)'),
      ('public.seva_mala_today()'),
      ('public.seva_mala_week_start(date)'),
      ('public.service_instance_name(public.service_instances)'),
      ('public.app_setting(text)')
    ) as expected(name)
    where to_regprocedure(expected.name) is null
  loop
    raise exception 'This file is built on %, which does not exist.', v_missing;
  end loop;

  -- Header §6. Every role that may see the whole board can already read every
  -- instance one at a time, so the board is a faster path and not a wider one.
  for v_role in
    select roles.name
    from public.roles
    where exists (
      select 1 from public.role_permissions
      where role_permissions.role_id = roles.id
        and role_permissions.permission_key in ('services.manage_recurring', 'app.view_all')
    )
    and not exists (
      select 1 from public.role_permissions
      where role_permissions.role_id = roles.id
        and role_permissions.permission_key = 'services.view_all'
    )
  loop
    raise exception
      'Role % may view the whole seva board but does not hold services.view_all, so the timetable would show it rows RLS refuses one at a time.',
      v_role;
  end loop;

  -- Header §6. The three the temple named, and nobody else.
  if exists (
    select 1
    from public.roles
    where (
      exists (
        select 1 from public.role_permissions
        where role_permissions.role_id = roles.id
          and role_permissions.permission_key in ('services.manage_recurring', 'app.view_all')
      )
    ) <> (roles.name in ('core', 'president', 'tech'))
  ) then
    raise exception
      'may_view_whole_seva_board no longer names exactly the Community Head, the President and the Tech Admin.';
  end if;

  -- Header §4. The clash prefilter of one day either side is arithmetic off
  -- this cap, not a guess.
  if coalesce((
    select pg_get_constraintdef(pg_constraint.oid)
    from pg_constraint
    where conname = 'service_instances_duration_minutes_check'
  ), '') not like '%720%' then
    raise exception
      'service_instances no longer caps a seva at 720 minutes. public.list_seva_clashes prefilters one day either side because nothing can run longer than half a day; that reasoning has to be redone.';
  end if;

end;
$$;

-- ---------------------------------------------------------------------------
-- 1. The clock, in one place.
--
--    Every dated moment in this file — seva and programme alike — is built
--    here, from a Chicago date and a Chicago wall-clock time. Never
--    current_date, never the session's zone, and never a client-built
--    timestamp: a devotee reading the grid in Mayapur sees the temple's day.
--
--    Plain SQL, no SECURITY DEFINER and no table access, so Postgres inlines
--    it into the queries below instead of calling it once per row.
--
--    On the spring-forward Sunday a wall-clock time between 2 and 3 in the
--    morning does not exist and Postgres resolves it forward. The temple's
--    programme starts at 4:30 and the grid starts at 3:30, so nothing the
--    temple runs is in that hour; a seva posted into it is drawn an hour late
--    for that one day rather than being dropped, which is the safer of the two.
-- ---------------------------------------------------------------------------

create or replace function public.temple_moment(p_date date, p_time time)
returns timestamptz
language sql
stable
set search_path = ''
as $$
  select (p_date + p_time) at time zone 'America/Chicago'
$$;

comment on function public.temple_moment(date, time) is
  'The instant a Chicago date and Chicago wall-clock time name. The one place the timetable turns a date and a time into a moment, so the grid, the clash check and the temple programme cannot disagree about when 6pm is.';

revoke all on function public.temple_moment(date, time) from public, anon;
grant execute on function public.temple_moment(date, time) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. The dials.
--
--      seva_schedule.default_window_days   how much the feed returns when the
--                                          caller names no end date. 7: a grid
--                                          asks for a week.
--      seva_schedule.max_window_days       the longest window anybody may ask
--                                          for in one call. 35, a month view
--                                          plus its ragged edges.
--      temple_programme.day_starts_at      the first hour the grid draws.
--      temple_programme.day_ends_at        the last. Advisory, never enforced:
--                                          header §5.
--
--    Seeded on conflict do nothing, so re-applying never stamps on a value the
--    temple has since changed. The two day counts RAISE on a malformed value
--    rather than falling back, which is 202608040055's rule for a dial and
--    202608040068's reason for preferring the raise: these are read on a
--    screen a devotee is looking at, so the error reaches somebody who can
--    report it instead of a log nobody opens.
--
--    There is no dial for the clash prefilter of one day either side. It is
--    not a policy choice — it is ceil(720 / 1440) from the table's own CHECK,
--    asserted in §0 — and a dial somebody could set to 0 would silently stop
--    finding the seva that runs through midnight, which is precisely the case
--    the temple would never think to re-test.
-- ---------------------------------------------------------------------------

insert into public.app_settings (key, value) values
  ('seva_schedule.default_window_days', '7'),
  ('seva_schedule.max_window_days', '35'),
  ('temple_programme.day_starts_at', '03:30'),
  ('temple_programme.day_ends_at', '21:00')
on conflict (key) do nothing;

create or replace function public.seva_schedule_window_days(p_key text)
returns integer
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_raw text;
  v_days integer;
begin
  if p_key not in ('seva_schedule.default_window_days', 'seva_schedule.max_window_days') then
    raise exception 'seva_schedule_window_days does not read %.', p_key;
  end if;
  v_raw := nullif(trim(coalesce(public.app_setting(p_key), '')), '');
  if v_raw is null then
    raise exception '% is not set.', p_key;
  end if;
  begin
    v_days := v_raw::integer;
  exception when others then
    raise exception '% is "%", which is not a whole number of days.', p_key, v_raw;
  end;
  if v_days < 1 or v_days > 366 then
    raise exception '% is %, which is outside 1 to 366.', p_key, v_days;
  end if;
  return v_days;
end;
$$;

comment on function public.seva_schedule_window_days(text) is
  'One of the two timetable window dials, in whole days, refusing anything that is not a number between 1 and 366. Named keys only, so this is not a way to read app_settings.';

revoke all on function public.seva_schedule_window_days(text) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. Who is serving each dated occurrence, after the swaps.
--
--    Header §2 is the whole of the reasoning. One SQL statement over a date
--    window: no loop, and nothing per devotee.
--
--    Backend only. It answers without asking who is looking, which is exactly
--    what a client must never be handed; every caller below applies its own
--    gate first.
-- ---------------------------------------------------------------------------

create or replace function public.seva_schedule_servers(
  p_from date,
  p_to date
)
returns table (
  service_instance_id uuid,
  devotee_id uuid,
  assignment_id uuid,
  assignment_status text,
  attendance text,
  verification text,
  points_status text,
  is_substitute boolean,
  covering_for_devotee_id uuid
)
language sql
stable
security definer
set search_path = ''
as $$
  with occurrences as (
    select instances.id, instances.template_id, instances.date
    from public.service_instances instances
    where instances.date between p_from and p_to
  ),
  -- (a) The live roster on the occurrence itself.
  rostered as (
    select
      occurrences.id as instance_id,
      assignments.devotee_id,
      assignments.status,
      assignments.attendance
    from occurrences
    join public.service_assignments assignments
      on assignments.service_instance_id = occurrences.id
    where assignments.status in ('assigned', 'confirmed', 'completed')
  ),
  -- (b)/(c) Every accepted plan in force on this occurrence's own date and
  -- weekday. All three scopes fall out of the same three comparisons.
  swaps as (
    select
      occurrences.id as instance_id,
      plans.original_devotee_id,
      plans.substitute_devotee_id
    from occurrences
    join public.service_coverage_plans plans
      on plans.service_template_id = occurrences.template_id
     and plans.status = 'accepted'
     and occurrences.date >= plans.date_from
     and (plans.date_to is null or occurrences.date <= plans.date_to)
     and extract(dow from occurrences.date)::integer = any(plans.days_of_week)
  ),
  resolved as (
    -- Kept: anybody no plan covers, plus (d) a covered original who has
    -- evidence of actually serving.
    select
      rostered.instance_id,
      rostered.devotee_id,
      false as via_plan,
      null::uuid as covering_for
    from rostered
    where rostered.status = 'completed'
       or rostered.attendance = 'served'
       or not exists (
            select 1 from swaps
            where swaps.instance_id = rostered.instance_id
              and swaps.original_devotee_id = rostered.devotee_id
          )
    union all
    -- Added: the substitute, unless (d) they explicitly stepped away from this
    -- one occurrence after agreeing to the range.
    select
      swaps.instance_id,
      swaps.substitute_devotee_id,
      true,
      swaps.original_devotee_id
    from swaps
    where not exists (
      select 1 from public.service_assignments stepped
      where stepped.service_instance_id = swaps.instance_id
        and stepped.devotee_id = swaps.substitute_devotee_id
        and stepped.status in ('withdrawn', 'no_show')
    )
  ),
  collapsed as (
    select
      resolved.instance_id,
      resolved.devotee_id,
      bool_or(resolved.via_plan) as is_substitute,
      (array_agg(resolved.covering_for)
        filter (where resolved.covering_for is not null))[1] as covering_for
    from resolved
    group by resolved.instance_id, resolved.devotee_id
  )
  select
    collapsed.instance_id,
    collapsed.devotee_id,
    assignments.id,
    assignments.status,
    assignments.attendance,
    assignments.verification,
    public.seva_points_status(
      coalesce(assignments.status, 'confirmed'),
      assignments.attendance,
      coalesce(assignments.verification, 'self_report'),
      occurrences.template_id is not null
    ),
    collapsed.is_substitute,
    collapsed.covering_for
  from collapsed
  join occurrences on occurrences.id = collapsed.instance_id
  left join public.service_assignments assignments
    on assignments.service_instance_id = collapsed.instance_id
   and assignments.devotee_id = collapsed.devotee_id
   and assignments.status in ('assigned', 'confirmed', 'completed')
$$;

comment on function public.seva_schedule_servers(date, date) is
  'Who is actually serving each dated seva occurrence in a window, with accepted coverage plans applied per occurrence so a handed-over Thursday names the substitute. The server''s equivalent of the client''s weeklyRoster, and the single source both the timetable and the clash check read. No caller check of its own: backend only.';

revoke all on function public.seva_schedule_servers(date, date) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4. The feed.
--
--    Every seva in a date window, weekly and one-off alike, flattened to dated
--    occurrences a grid lays out directly. Header §1 for the shape, §3 for
--    what a block is allowed to say, §6 for who may ask.
--
--      p_devotee_id null  the whole temple. Board viewers only.
--      p_devotee_id = me  my own timetable. Every devotee.
--      p_devotee_id other one named devotee. Board viewers only — this is the
--                         "is she free on Thursday" call, and it is why the
--                         argument exists at all.
--
--    One row per OCCURRENCE, not per person: the roster travels in `servers`
--    as jsonb, so a forty-devotee kitchen slot is one block and not forty.
--
--    The window is what has been generated. public.generate_service_instances
--    keeps a rolling horizon (90 days on the nightly job), so a week far
--    enough ahead is legitimately empty rather than broken; the feed does not
--    generate, because it is a read and a read that writes is a read that
--    cannot be cached, retried or run by a devotee twice.
-- ---------------------------------------------------------------------------

create or replace function public.list_seva_schedule(
  p_from date default null,
  p_to date default null,
  p_devotee_id uuid default null
)
returns table (
  service_instance_id uuid,
  template_id uuid,
  from_weekly_template boolean,
  seva_name text,
  service_type_id uuid,
  service_category text,
  occurs_on date,
  day_of_week integer,
  starts_at_local time,
  ends_at_local time,
  ends_next_day boolean,
  duration_minutes integer,
  starts_at timestamptz,
  ends_at timestamptz,
  status text,
  nobody_served boolean,
  participation_mode text,
  posted_by uuid,
  slots_needed integer,
  filled_slots integer,
  open_slots integer,
  roster_visible boolean,
  servers jsonb
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_board boolean;
  v_from date;
  v_to date;
  v_max integer := public.seva_schedule_window_days('seva_schedule.max_window_days');
begin
  if v_me is null then
    raise exception 'Sign in to read the seva timetable.';
  end if;
  v_board := public.may_view_whole_seva_board();

  if p_devotee_id is null and not v_board then
    raise exception
      'Only the President, the Tech Admin and the Community Head may read the whole temple''s timetable. Ask for your own by naming yourself.';
  end if;
  if p_devotee_id is not null and p_devotee_id <> v_me and not v_board then
    raise exception 'You may only read your own seva timetable.';
  end if;
  -- After the permission check and never before it, so this cannot be used to
  -- ask whether a stranger has an account.
  if p_devotee_id is not null and not exists (
    select 1 from public.users where users.id = p_devotee_id
  ) then
    raise exception 'That devotee could not be found.';
  end if;

  v_from := coalesce(p_from, public.seva_mala_week_start(public.seva_mala_today()));
  v_to := coalesce(
    p_to,
    v_from + public.seva_schedule_window_days('seva_schedule.default_window_days') - 1);
  if v_to < v_from then
    raise exception 'The timetable window ends before it begins.';
  end if;
  if (v_to - v_from) + 1 > v_max then
    raise exception
      'A timetable window may cover at most % days; % to % is %.',
      v_max, v_from, v_to, (v_to - v_from) + 1;
  end if;

  return query
  with
  -- Computed once for the window, for everybody, and then filtered. Header §1:
  -- the alternative is one pass per devotee on screen.
  all_servers as (
    select * from public.seva_schedule_servers(v_from, v_to)
  ),
  wanted as (
    select instances.id, instances.template_id
    from public.service_instances instances
    where instances.date between v_from and v_to
      and (
        p_devotee_id is null
        or exists (
             select 1 from all_servers
             where all_servers.service_instance_id = instances.id
               and all_servers.devotee_id = p_devotee_id
           )
      )
  ),
  -- Header §3, leak one. `as materialized` so the visibility question is asked
  -- once per DISTINCT template in the answer and not once per occurrence: a
  -- weekly seva that appears on four Thursdays is one question, not four.
  window_templates as materialized (
    select distinct wanted.template_id as id
    from wanted
    where wanted.template_id is not null
  ),
  -- Materialized as well, or the qual is pushed into the join below and asked
  -- once per (occurrence, template) pair instead of once per template.
  open_templates as materialized (
    select window_templates.id
    from window_templates
    where public.can_view_service_template(window_templates.id)
  ),
  -- Header §3, leak two. A board viewer holds services.view_all, so this is
  -- true for them without the call; §0 asserts that containment.
  readable as (
    select
      wanted.id,
      v_board or public.can_view_service_instance(wanted.id) as can_see_roster
    from wanted
  ),
  roster as (
    select
      all_servers.service_instance_id as instance_id,
      count(*)::integer as filled,
      jsonb_agg(
        jsonb_build_object(
          'devoteeId', all_servers.devotee_id,
          'name', people.name,
          'assignmentId', all_servers.assignment_id,
          'assignmentStatus', all_servers.assignment_status,
          'attendance', all_servers.attendance,
          'pointsStatus', all_servers.points_status,
          'isSubstitute', all_servers.is_substitute,
          'coveringForDevoteeId',
            case when v_board
                   or v_me in (all_servers.devotee_id, all_servers.covering_for_devotee_id)
                 then all_servers.covering_for_devotee_id end,
          'coveringForName',
            case when v_board
                   or v_me in (all_servers.devotee_id, all_servers.covering_for_devotee_id)
                 then covered.name end
        )
        order by people.name, all_servers.devotee_id
      ) filter (
        where readable.can_see_roster or all_servers.devotee_id = p_devotee_id
      ) as roster_json
    from all_servers
    join readable on readable.id = all_servers.service_instance_id
    join public.users people on people.id = all_servers.devotee_id
    left join public.users covered on covered.id = all_servers.covering_for_devotee_id
    group by all_servers.service_instance_id
  )
  select
    instances.id,
    case when open_templates.id is not null then instances.template_id end,
    instances.template_id is not null,
    public.service_instance_name(instances),
    instances.service_type_id,
    service_types.category,
    instances.date,
    extract(dow from instances.date)::integer,
    instances.start_time,
    ((public.temple_moment(instances.date, instances.start_time)
      + make_interval(mins => instances.duration_minutes))
      at time zone 'America/Chicago')::time,
    ((public.temple_moment(instances.date, instances.start_time)
      + make_interval(mins => instances.duration_minutes))
      at time zone 'America/Chicago')::date > instances.date,
    instances.duration_minutes,
    public.temple_moment(instances.date, instances.start_time),
    public.temple_moment(instances.date, instances.start_time)
      + make_interval(mins => instances.duration_minutes),
    instances.status,
    unserved.service_instance_id is not null,
    instances.participation_mode,
    instances.posted_by,
    instances.slots_needed,
    coalesce(roster.filled, 0),
    greatest(instances.slots_needed - coalesce(roster.filled, 0), 0),
    readable.can_see_roster,
    coalesce(roster.roster_json, '[]'::jsonb)
  from wanted
  join public.service_instances instances on instances.id = wanted.id
  join readable on readable.id = wanted.id
  left join open_templates on open_templates.id = instances.template_id
  left join roster on roster.instance_id = wanted.id
  left join public.service_types on service_types.id = instances.service_type_id
  left join public.service_instances_unserved unserved
    on unserved.service_instance_id = wanted.id
  order by instances.date, instances.start_time, instances.id;
end;
$$;

comment on function public.list_seva_schedule(date, date, uuid) is
  'Every seva in a Chicago date window as dated occurrences a timetable can lay out: name, type, weekly-or-one-off, date, start, length, end, status, whether nobody served it, and the roster after coverage swaps are applied. p_devotee_id null is the whole temple and needs may_view_whole_seva_board; p_devotee_id = auth.uid() is a devotee''s own; any other devotee needs may_view_whole_seva_board. One row per occurrence and one call per window — never one per devotee.';

revoke all on function public.list_seva_schedule(date, date, uuid) from public, anon;
grant execute on function public.list_seva_schedule(date, date, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. The clash answer.
--
--    Header §4. Facts for a warning; it decides nothing, refuses nothing, and
--    writes nothing. The client says "you are serving X from A to B, but this
--    seva is from C to D — only accept if you can manage it."
--
--      a coordinator  any devotee, gated on services.offer_assignment, which
--                     is precisely the permission that lets them invite that
--                     devotee in the first place (202608040015). A Volunteer
--                     holds it, and header §3 leak three is why they get the
--                     times without necessarily getting the name.
--      a devotee      themselves, always.
--
--    p_exclude_instance_id is for the devotee already on a seva who is looking
--    at that same seva's page — without it, every "am I free?" check would
--    report the seva being asked about as a total clash with itself.
-- ---------------------------------------------------------------------------

create or replace function public.list_seva_clashes(
  p_devotee_id uuid,
  p_date date,
  p_start_time time,
  p_duration_minutes integer,
  p_exclude_instance_id uuid default null
)
returns table (
  service_instance_id uuid,
  template_id uuid,
  from_weekly_template boolean,
  seva_name text,
  name_visible boolean,
  occurs_on date,
  starts_at_local time,
  ends_at_local time,
  ends_next_day boolean,
  starts_at timestamptz,
  ends_at timestamptz,
  status text,
  assignment_status text,
  is_substitute boolean,
  overlap_minutes integer,
  overlap_starts_at timestamptz,
  overlap_ends_at timestamptz,
  covers_whole_request boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_board boolean;
  v_start timestamptz;
  v_end timestamptz;
begin
  if v_me is null then
    raise exception 'Sign in to check for a seva clash.';
  end if;
  if p_devotee_id is null then
    raise exception 'Name the devotee whose seva you are checking.';
  end if;
  if p_devotee_id <> v_me and not public.has_permission('services.offer_assignment') then
    raise exception
      'Your access level cannot check another devotee''s seva times. You may check your own.';
  end if;
  if p_date is null or p_start_time is null then
    raise exception 'A clash check needs a date and a start time.';
  end if;
  -- The same bounds service_instances itself is checked to, so a window can
  -- always be asked about a seva that could actually exist.
  if p_duration_minutes is null or p_duration_minutes < 1 or p_duration_minutes > 720 then
    raise exception 'A seva runs between 1 and 720 minutes; % was asked about.', p_duration_minutes;
  end if;
  if not exists (select 1 from public.users where users.id = p_devotee_id) then
    raise exception 'That devotee could not be found.';
  end if;

  v_board := public.may_view_whole_seva_board();
  v_start := public.temple_moment(p_date, p_start_time);
  v_end := v_start + make_interval(mins => p_duration_minutes);

  return query
  with mine as (
    -- Header §4: one day either side is enough because nothing may run longer
    -- than 720 minutes and the asked-about window cannot exceed a day.
    select
      servers.service_instance_id,
      servers.assignment_status,
      servers.is_substitute
    from public.seva_schedule_servers(p_date - 1, p_date + 1) servers
    where servers.devotee_id = p_devotee_id
  ),
  candidates as (
    select
      instances.id,
      mine.assignment_status,
      mine.is_substitute,
      public.temple_moment(instances.date, instances.start_time) as began,
      public.temple_moment(instances.date, instances.start_time)
        + make_interval(mins => instances.duration_minutes) as ended
    from mine
    join public.service_instances instances on instances.id = mine.service_instance_id
    where instances.status <> 'cancelled'
      and (p_exclude_instance_id is null or instances.id <> p_exclude_instance_id)
  ),
  overlapping as (
    select
      candidates.*,
      tstzrange(candidates.began, candidates.ended, '[)')
        * tstzrange(v_start, v_end, '[)') as shared
    from candidates
    where tstzrange(candidates.began, candidates.ended, '[)')
       && tstzrange(v_start, v_end, '[)')
  )
  select
    instances.id,
    case
      when instances.template_id is not null
       and public.can_view_service_template(instances.template_id)
      then instances.template_id
    end,
    instances.template_id is not null,
    case
      when v_board or p_devotee_id = v_me or public.can_view_service_instance(instances.id)
      then public.service_instance_name(instances)
    end,
    v_board or p_devotee_id = v_me or public.can_view_service_instance(instances.id),
    instances.date,
    instances.start_time,
    (overlapping.ended at time zone 'America/Chicago')::time,
    (overlapping.ended at time zone 'America/Chicago')::date > instances.date,
    overlapping.began,
    overlapping.ended,
    instances.status,
    overlapping.assignment_status,
    overlapping.is_substitute,
    (extract(epoch from (upper(overlapping.shared) - lower(overlapping.shared))) / 60)::integer,
    lower(overlapping.shared),
    upper(overlapping.shared),
    overlapping.began <= v_start and overlapping.ended >= v_end
  from overlapping
  join public.service_instances instances on instances.id = overlapping.id
  order by
    (extract(epoch from (upper(overlapping.shared) - lower(overlapping.shared))) / 60)::integer desc,
    overlapping.began,
    instances.id;
end;
$$;

comment on function public.list_seva_clashes(uuid, date, time, integer, uuid) is
  'Whether a devotee is already serving during a proposed Chicago window and what they are serving: the clashing seva, its start and end, and how many minutes overlap. Partial and total alike, across midnight, with coverage swaps applied. It never refuses anything and nothing refuses anything on its behalf — the temple was explicit that a devotee serving 12:00 to 13:30 may still take a seva at 13:15. A coordinator needs services.offer_assignment to ask about somebody else; anybody may ask about themselves.';

revoke all on function public.list_seva_clashes(uuid, date, time, integer, uuid) from public, anon;
grant execute on function public.list_seva_clashes(uuid, date, time, integer, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. The temple's own daily programme.
--
--    Header §5 is the decision and the argument. A table, because the one
--    requirement with a cost attached — changing a time without an app
--    release — is the one a constant cannot meet.
--
--    duration_minutes is NULLABLE and that is the temple's own shape: they
--    gave Mangala Arati, Sringara Arati and Raja Bhoga Arati a start and no
--    end, and Japa, the class, Gaura Arati, the lecture, prasadam and kirtan a
--    range. Inventing an end for the first three would be drawing a block the
--    temple never described.
-- ---------------------------------------------------------------------------

create table if not exists public.temple_programme (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  days_of_week integer[] not null,
  starts_at_local time not null,
  duration_minutes integer,
  sort_order integer not null default 0,
  active boolean not null default true,
  updated_at timestamptz not null default now(),
  constraint temple_programme_name_not_blank
    check (length(trim(name)) between 2 and 80),
  constraint temple_programme_days_check
    check (cardinality(days_of_week) between 1 and 7
           and days_of_week <@ array[0, 1, 2, 3, 4, 5, 6]),
  constraint temple_programme_duration_check
    check (duration_minutes is null or duration_minutes between 1 and 720),
  constraint temple_programme_one_per_start
    unique (name, starts_at_local)
);

alter table public.temple_programme enable row level security;

comment on table public.temple_programme is
  'The temple''s fixed daily programme — aratis, class, japa, kirtan — drawn behind the seva blocks on the timetable. NOT seva: no service type, no slots, nobody is assigned and nothing here can clash with anything. A row rather than a client constant so a time can be moved without an app release.';
comment on column public.temple_programme.duration_minutes is
  'Null where the temple named a start and no end, which is how three of the aratis are actually described. A null is not a zero-length block; it is a moment.';
comment on column public.temple_programme.days_of_week is
  'Postgres dow: 0 is Sunday. Gaura Arati is two rows because Sunday''s is an hour earlier.';

drop policy if exists "Everyone signed in can read the temple programme"
  on public.temple_programme;
create policy "Everyone signed in can read the temple programme"
  on public.temple_programme for select to authenticated
  using (active or public.has_permission('app.view_all'));

revoke all on public.temple_programme from public, anon;
grant select on public.temple_programme to authenticated;

-- Monday to Saturday and Sunday alike for the morning; Gaura Arati splits, and
-- Sunday carries the evening programme. Seeded only where the row is not
-- already there, so re-applying never moves a time the temple has changed.
insert into public.temple_programme (name, days_of_week, starts_at_local, duration_minutes, sort_order)
select seed.name, seed.days, seed.starts, seed.minutes, seed.sort_order
from (values
  ('Mangala Arati',           array[0,1,2,3,4,5,6], time '04:30', null::integer, 10),
  ('Japa Meditation',         array[0,1,2,3,4,5,6], time '05:15', 105,           20),
  ('Sringara Arati',          array[0,1,2,3,4,5,6], time '07:00', null,          30),
  ('Srimad Bhagavatam Class', array[0,1,2,3,4,5,6], time '07:30', 60,            40),
  ('Raja Bhoga Arati',        array[0,1,2,3,4,5,6], time '12:30', null,          50),
  ('Gaura Arati',             array[1,2,3,4,5,6],   time '18:00', 30,            60),
  ('Gaura Arati',             array[0],             time '17:00', 30,            60),
  ('Sunday Lecture',          array[0],             time '17:30', 60,            70),
  ('Prasadam',                array[0],             time '18:30', 30,            80),
  ('Kirtan',                  array[0],             time '19:00', 60,            90)
) as seed(name, days, starts, minutes, sort_order)
on conflict (name, starts_at_local) do nothing;

-- The grid's own hours, which are display and are advisory. Header §5.
create or replace function public.temple_timetable_hours()
returns table (day_starts_at time, day_ends_at time)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_starts time;
  v_ends time;
begin
  begin
    v_starts := trim(public.app_setting('temple_programme.day_starts_at'))::time;
    v_ends := trim(public.app_setting('temple_programme.day_ends_at'))::time;
  exception when others then
    raise exception
      'temple_programme.day_starts_at / day_ends_at are "%" and "%", which are not times of day.',
      public.app_setting('temple_programme.day_starts_at'),
      public.app_setting('temple_programme.day_ends_at');
  end;
  if v_starts is null or v_ends is null or v_ends <= v_starts then
    raise exception 'The timetable day must end after it begins; % to % does not.', v_starts, v_ends;
  end if;
  return query select v_starts, v_ends;
end;
$$;

comment on function public.temple_timetable_hours() is
  'The first and last hour the timetable grid draws, Chicago wall clock. Advisory and display only: nothing on the server filters a seva by them, and a 2am seva is still returned by list_seva_schedule. They are dials rather than a client constant because they exist to contain the temple programme, and the programme can move.';

revoke all on function public.temple_timetable_hours() from public, anon;
grant execute on function public.temple_timetable_hours() to authenticated;

-- The programme as dated occurrences, in the same window shape as the seva
-- feed, so a grid lays both out with one piece of code and does no date
-- arithmetic of its own.
create or replace function public.list_temple_programme(
  p_from date default null,
  p_to date default null
)
returns table (
  programme_id uuid,
  kind text,
  name text,
  occurs_on date,
  day_of_week integer,
  starts_at_local time,
  ends_at_local time,
  duration_minutes integer,
  starts_at timestamptz,
  ends_at timestamptz,
  sort_order integer
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_from date;
  v_to date;
  v_max integer := public.seva_schedule_window_days('seva_schedule.max_window_days');
begin
  if auth.uid() is null then
    raise exception 'Sign in to read the temple programme.';
  end if;

  v_from := coalesce(p_from, public.seva_mala_week_start(public.seva_mala_today()));
  v_to := coalesce(
    p_to,
    v_from + public.seva_schedule_window_days('seva_schedule.default_window_days') - 1);
  if v_to < v_from then
    raise exception 'The timetable window ends before it begins.';
  end if;
  if (v_to - v_from) + 1 > v_max then
    raise exception
      'A timetable window may cover at most % days; % to % is %.',
      v_max, v_from, v_to, (v_to - v_from) + 1;
  end if;

  return query
  with days as (
    select day::date as on_date
    from generate_series(v_from::timestamp, v_to::timestamp, interval '1 day') as day
  )
  select
    programme.id,
    'temple_programme'::text,
    programme.name,
    days.on_date,
    extract(dow from days.on_date)::integer,
    programme.starts_at_local,
    case when programme.duration_minutes is not null then
      ((public.temple_moment(days.on_date, programme.starts_at_local)
        + make_interval(mins => programme.duration_minutes))
        at time zone 'America/Chicago')::time
    end,
    programme.duration_minutes,
    public.temple_moment(days.on_date, programme.starts_at_local),
    case when programme.duration_minutes is not null then
      public.temple_moment(days.on_date, programme.starts_at_local)
        + make_interval(mins => programme.duration_minutes)
    end,
    programme.sort_order
  from days
  join public.temple_programme programme
    on programme.active
   and extract(dow from days.on_date)::integer = any(programme.days_of_week)
  order by days.on_date, programme.starts_at_local, programme.sort_order, programme.name;
end;
$$;

comment on function public.list_temple_programme(date, date) is
  'The temple''s fixed daily programme as dated occurrences over the same window as list_seva_schedule, so the grid can draw it behind the seva blocks without doing any date arithmetic. Every row carries kind = ''temple_programme'': this is not seva, nobody is assigned to it, and it never appears in list_seva_clashes. ends_at is null where the temple named a start and no end.';

revoke all on function public.list_temple_programme(date, date) from public, anon;
grant execute on function public.list_temple_programme(date, date) to authenticated;

-- ---------------------------------------------------------------------------
-- 7. What this file is not allowed to have become.
--
--    Two promises made in the header, checked here so that a later edit that
--    breaks one of them fails the migration rather than the temple.
-- ---------------------------------------------------------------------------

do $$
declare
  v_name text;
  v_body text;
begin
  -- Exactly one of each, with exactly the argument list the two client agents
  -- are building against. A leftover overload has broken this repository
  -- before, and an overload here would let a client reach a different function
  -- than the one that was reviewed.
  for v_name in
    select expected.name
    from (values
      ('temple_moment'), ('seva_schedule_window_days'), ('seva_schedule_servers'),
      ('list_seva_schedule'), ('list_seva_clashes'), ('list_temple_programme'),
      ('temple_timetable_hours')
    ) as expected(name)
    where (
      select count(*)
      from pg_proc proc
      join pg_namespace spaces on spaces.oid = proc.pronamespace
      where spaces.nspname = 'public' and proc.proname = expected.name
    ) <> 1
  loop
    raise exception 'There is not exactly one public.%.', v_name;
  end loop;

  for v_name, v_body in
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
    raise exception 'public.% takes (%), which is not the contract.', v_name, v_body;
  end loop;

  -- Header §1. Both set-returning bodies stay single SQL statements; a loop
  -- over devotees is exactly the shape this file exists to avoid.
  if (select prolang from pg_proc
      where oid = 'public.seva_schedule_servers(date, date)'::regprocedure)
     <> (select oid from pg_language where lanname = 'sql')
  then
    raise exception
      'public.seva_schedule_servers is no longer one SQL statement, which is how it stops being a per-devotee fan-out.';
  end if;

  -- Header §4. Nothing calls the clash check but a client. The moment some
  -- guard starts consulting it, it has begun to decide something.
  for v_name in
    select proc.proname
    from pg_proc proc
    join pg_namespace spaces on spaces.oid = proc.pronamespace
    where spaces.nspname = 'public'
      and proc.proname <> 'list_seva_clashes'
      and proc.prosrc like '%list_seva_clashes%'
  loop
    raise exception
      'public.% calls public.list_seva_clashes. The temple was explicit that a clash blocks nothing.', v_name;
  end loop;

  -- And no client role can reach the two backend helpers.
  for v_name in
    select expected.sig
    from (values
      ('public.seva_schedule_servers(date, date)'),
      ('public.seva_schedule_window_days(text)')
    ) as expected(sig)
    where has_function_privilege('authenticated', expected.sig, 'execute')
       or has_function_privilege('anon', expected.sig, 'execute')
  loop
    raise exception 'A client role can call %, which answers without asking who is looking.', v_name;
  end loop;

  select count(*)::text into v_body from public.temple_programme;
  raise notice 'temple programme holds % row(s); timetable and clash RPCs installed.', v_body;
end;
$$;
