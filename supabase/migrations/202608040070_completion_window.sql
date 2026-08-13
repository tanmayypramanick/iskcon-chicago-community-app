-- The window in which a seva may be marked completed, and the seva nobody came to.
--
-- Two corrections to 202608040068. That file is right about almost everything
-- and this one keeps all of it: sentence 1 is still 0057's, "did anybody serve
-- this" is still asked through seva_points_status, the terminal state for a
-- seva everybody was absent from is still 'cancelled' with a row in
-- public.service_instances_unserved, and the reconciler still only ever reopens
-- a seva it closed itself. Two things move.
--
-- ---------------------------------------------------------------------------
-- FINDING ONE. THE BAR WAS AT THE START, AND THE TEMPLE ASKED FOR THE END.
--
--    "If it is upcoming seva and the time has not passed yet, it will not show
--     'mark my seva completed', as the date is still in the future. AFTER THE
--     SEVA HAS BEEN DONE AND THE TIME HAS PASSED, only then can anyone mark
--     this seva completed."
--
--    0068 section 1 read that as the start and said so at length. The reading
--    was defensible and it is wrong, and the way it is wrong is not subtle: on
--    the temple's own database seva.complete_after_start_minutes is 0, so a
--    9:00–10:00 seva can be marked completed at 9:01. The seva has not been
--    done. The time has not passed. Somebody is standing in the kitchen while
--    the app says the kitchen was cleaned.
--
--    0068's argument for the start had three legs and section 2 below takes
--    each of them:
--
--      "EVERY OTHER CLOCK GATE IS THE START." Two of the three still are, and
--      deliberately: record_seva_attendance and verify_seva_assignment open at
--      the start because a coordinator marks somebody absent DURING the seva,
--      standing in front of the empty place. Those are not the same question.
--      "Who is here?" is asked while it happens; "did this happen?" can only be
--      answered afterwards. This file moves the second and does not touch the
--      first — section 8 asserts it, so that a later edit cannot quietly drag
--      attendance along behind completion.
--
--      "A BAR AT THE END WOULD STOP THE POSTER'S BUTTON AND NOT THE DEVOTEE'S."
--      True of 0068 and fixed here rather than argued with: both buttons read
--      one function, and that function now reads the end. They open at the same
--      instant, as they did before, at a later instant than before.
--
--      "THE DIAL BUYS IT ANYWAY — set complete_after_start_minutes to the
--      length of the seva." That only works if every seva in the temple is the
--      same length. They are 30 to 720 minutes (202608020002), so a dial set to
--      an hour is late for Mangala Arati and early for a Sunday feast. The
--      length of the seva is already recorded per seva, in duration_minutes,
--      and that is what the bar is now computed from.
--
--    THE NEW BAR, and it is still every bit of it a dial:
--
--      completion opens at   GREATEST(
--                              start + seva.complete_after_start_minutes,
--                              start + duration_minutes
--                                    + seva.complete_after_end_minutes )
--
--    THE OLD DIAL IS NOT ORPHANED AND IS NOT REPURPOSED. It still means what
--    its name and 0068's comment say — whole minutes past the start before
--    anybody may mark this seva completed — and it is still read by
--    seva_completion_lead_minutes(). It is now a FLOOR under the new bar rather
--    than the bar itself. A temple that set it to 1440 because they wanted a
--    whole day to go by still gets a whole day, even on a 30-minute seva; at
--    its shipped 0 it is below the end of every seva there can be, so it
--    changes nothing until somebody raises it. Nothing was reinterpreted
--    underneath an operator who had already turned it.
--
--    THE NEW DIAL IS THE GRACE, AND IT CUTS BOTH WAYS.
--    seva.complete_after_end_minutes is -1440 to 1440 and ships at 0. Positive
--    is the temple wanting the dust to settle before anybody may say it is
--    done. Negative is the temple wanting the last five minutes forgiven, so
--    the pujari who is washing up at 9:55 can close a 9:00–10:00 seva without
--    standing there. It is the only dial in this file that may be negative, and
--    the floor above still holds under it: at -1440 the bar is the start, never
--    earlier, because the seva has to have begun before anybody may say it
--    finished.
--
--    AND THE SWEEP AND THE BUTTON NOW AGREE, WHICHEVER WAY THE DIALS ARE
--    TURNED. 202608040065 closes a weekly slot at end + 60 minutes of its own
--    grace, which was already stricter than 0068's start and stays stricter
--    than this file's end at the shipped values. But "stricter" was an accident
--    of two numbers, not a rule: with complete_after_end_minutes at 120 the
--    clock would have been closing seva an hour before the President was
--    allowed to, which is the sweep quietly holding an authority no person has.
--    Section 7 replaces 0065's view so its due_at is the LATER of its own grace
--    and this file's bar. At the shipped dials that is end + 60 to the
--    microsecond — the sweep does not move, and the weekly occurrence it closes
--    still closes — and at any other setting the sweep can never be the early
--    door.
--
-- ---------------------------------------------------------------------------
-- FINDING TWO. A SEVA NOBODY EVER JOINED COULD BE MARKED COMPLETED AND STAY
--    THAT WAY.
--
--    0068's reconciler returns early when the instance holds no assignments at
--    all, and its section 2 explains why: sentence 2 is about devotees MARKED
--    absent, and a seva with no places has nobody to mark. That is a good
--    reason not to CANCEL such an instance. It is not a reason to let it sit in
--    the completed list. The temple's sentence is "as if no one served this,
--    how is this seva completed", and no one is exactly who served a seva
--    nobody joined. A poster could close an unclaimed request and the app would
--    report service that certainly did not happen; 0068's own verification
--    asserted that it would.
--
--    THE THREE CASES ARE THREE DIFFERENT EVENTS AND THE APP MUST NOT CONFLATE
--    THEM.
--
--      served          somebody's place counts       -> status 'completed'
--      all absent      places, every one answered
--                      no                            -> status 'cancelled',
--                                                      row in
--                                                      service_instances_unserved
--      never joined    no places at all              -> status back to 'open'
--
--    WHY 'open' AND NOT 'cancelled' FOR THE THIRD. Three reasons, and the first
--    is the temple's:
--
--      IT MUST STAY VISIBLE. lapsedOpenRequests on the client is
--      `template_id is null and status not in ('completed','cancelled') and the
--      end has passed and participation_mode = 'open'`, and it exists because
--      the temple asked for passed unclaimed requests to reach history rather
--      than disappear. Cancelling one would take it out of that list, out of
--      awaitingCompletionServices, and out of upcomingServices at the same
--      time: the request would simply be gone. 'open' is the one status that
--      keeps it exactly where the temple put it.
--
--      IT IS NOT A NEW STATE. A passed request nobody took up is already 'open'
--      all over the database — that is the ordinary life of an unclaimed
--      request whose hour went by, and every reader already handles it. This
--      arm does not invent a state, it puts back the one that was true before
--      somebody pressed a button.
--
--      THE SYSTEM ALREADY SAYS SO, IN 202608040019. refresh_service_instance_
--      capacity turns a 'completed' instance with nothing on it back to 'open',
--      in those words: "an occurrence emptied after the fact can be reopened
--      rather than stranded as finished with nobody on it." That is this exact
--      case arriving from the other direction, and rather than write a second
--      rule beside it, section 3 CALLS that function and returns whatever it
--      decides. 0019 owns 'open' versus 'full' and still does.
--
--    AND THE BOOKKEEPING TABLE IS NOT TOUCHED. public.service_instances_
--    unserved means one thing — "0068 closed this because every place on it was
--    answered no" — and 202608040069's list_seva_schedule publishes it to the
--    client as nobody_served. Putting never-joined instances in it would make
--    that column mean two things at once and would break 0068's own invariant
--    that every row in it is 'cancelled'. So the client tells the three cases
--    apart with columns it already has:
--
--      completed   status = 'completed'                     it happened
--      all absent  status = 'cancelled' + nobody_served     it did not, and
--                  (or list_seva_closed_unserved)           here is who was
--                                                           marked what
--      never joined status = 'open', nobody_served false,   nobody came; it is
--                  filled_slots 0, end passed               a lapsed request
--
--    THE FRONT DOOR REFUSES IT RATHER THAN UNDOING IT AFTERWARDS. Reverting a
--    completion the poster just made, silently, is worse than refusing it, so
--    complete_service_instance now says plainly that nobody joined this seva
--    and that removing the request is the honest way to close the queue entry —
--    delete_service_requirement, which the poster already holds and which
--    deletes an instance with no history outright. The reconciler's arm stays,
--    because it is the backstop for the rows that already exist and for
--    settle_finished_verified_seva, which nobody presses.
--
-- ---------------------------------------------------------------------------
-- WHAT IS NOT CHANGED, SAID OUT LOUD.
--
--   record_seva_attendance, verify_seva_assignment   still open at the START
--   the meaning of 'cancelled' + service_instances_unserved   unchanged
--   list_seva_closed_unserved, list_seva_schedule    unchanged, and both still
--                                                    answer the same question
--   every argument list in the schema                unchanged
--   seva.auto_complete_grace_minutes and its two
--   siblings                                         unchanged, still 0065's
--
-- Requires 202608040068_completion_truthfulness.sql and, through it,
-- 202608040065_recurring_autocomplete.sql.

-- ---------------------------------------------------------------------------
-- 0. The ground this stands on, asserted rather than assumed.
-- ---------------------------------------------------------------------------

do $$
begin
  if to_regprocedure('public.seva_completion_opens_at(date, time)') is null
    or to_regprocedure('public.seva_completion_lead_minutes()') is null
    or to_regprocedure('public.reconcile_service_instance_completion(uuid)') is null
    or to_regprocedure('public.service_instance_has_server(uuid)') is null
    or to_regprocedure('public.complete_service_instance(uuid)') is null
    or to_regprocedure('public.complete_service_instance_internal(uuid, uuid, boolean)') is null
    or to_regprocedure('public.complete_my_service_assignment(uuid)') is null
    or to_regprocedure('public.refresh_service_instance_capacity(uuid)') is null
    or to_regprocedure('public.app_setting(text)') is null
    or to_regclass('public.service_instances_unserved') is null
    or to_regclass('public.due_recurring_service_instances') is null
  then
    raise exception
      'The completion path is not in place; apply 202608040065 and 202608040068 first.';
  end if;

  -- The length of a seva is the thing this file computes the bar from, so it
  -- has to be recorded on every seva and it has to be a real length.
  if exists (
    select 1 from public.service_instances where duration_minutes is null
  ) then
    raise exception
      'Some seva has no duration_minutes, so the end of it cannot be known and the bar below would be the start.';
  end if;
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.service_instances'::regclass
      and pg_get_constraintdef(oid) like '%duration_minutes%'
      and contype = 'c'
  ) then
    raise exception
      'public.service_instances no longer constrains duration_minutes; the completion bar rests on it.';
  end if;

  -- 0019 still owns the honest status of an instance with nothing on it, which
  -- is what section 3's never-joined arm delegates to.
  if pg_get_functiondef('public.refresh_service_instance_capacity(uuid)'::regprocedure)
     !~* 'then ''open''' then
    raise exception
      'refresh_service_instance_capacity no longer reopens an emptied instance; section 3 would have nothing to delegate to.';
  end if;

  -- And 0065's sweep is still shaped the way section 7 replaces it.
  if pg_get_viewdef('public.due_recurring_service_instances'::regclass)
     !~* 'auto_complete_grace_minutes' then
    raise exception
      'due_recurring_service_instances no longer reads seva.auto_complete_grace_minutes; section 7 would be rewriting something else.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 1. The second dial: the grace either side of the end.
--
--      seva.complete_after_end_minutes   whole minutes either side of the
--                                        seva's own Chicago end before anybody
--                                        may mark it completed. -1440 to 1440.
--
--    ZERO IS THE DEFAULT and zero is the end of the seva exactly, which is what
--    the temple asked for. Negative forgives the tail of a seva; positive makes
--    the temple wait. The floor in section 2 means a negative value can never
--    put the bar before the start.
--
--    The only dial in this schema that may be negative, so its range is stated
--    here and enforced in one place. Seeded on conflict do nothing, read
--    through 202608040026's app_setting(), and a malformed value RAISES rather
--    than falling back — 202608040055's rule, and this one is read on a button
--    a devotee presses, so the error reaches somebody who can report it.
-- ---------------------------------------------------------------------------

insert into public.app_settings (key, value)
values ('seva.complete_after_end_minutes', '0')
on conflict (key) do nothing;

create or replace function public.seva_completion_end_grace_minutes()
returns integer
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_raw text;
  v_minutes integer;
begin
  v_raw := coalesce(
    nullif(trim(public.app_setting('seva.complete_after_end_minutes')), ''), '0');
  begin
    v_minutes := v_raw::integer;
  exception when others then
    raise exception
      'seva.complete_after_end_minutes is "%", which is not a whole number of minutes.', v_raw;
  end;
  if v_minutes < -1440 or v_minutes > 1440 then
    raise exception
      'seva.complete_after_end_minutes is %, which is outside -1440 to 1440.', v_minutes;
  end if;
  return v_minutes;
end;
$$;

comment on function public.seva_completion_end_grace_minutes() is
  'Whole minutes either side of a seva''s own Chicago end before anybody may mark it completed. 0, the default, is the end exactly. Negative forgives the tail of the seva; the bar can still never fall before the start.';

revoke all on function public.seva_completion_end_grace_minutes() from public, anon;
grant execute on function public.seva_completion_end_grace_minutes() to authenticated;

-- ---------------------------------------------------------------------------
-- 2. The one place the boundary is computed, now that it needs to know how long
--    the seva is.
--
--    The three-argument form is the bar. The two-argument form 0068 created is
--    kept, keeps its grants, and is now that same function asked about a seva
--    of no length — which makes it exactly the start-side floor, and leaves the
--    two verification files that call it (seva_permutations,
--    recurring_autocomplete, both asking "has this seva started, so that the
--    refusal below is about authority and not the clock") answering the
--    question they were actually asking. There are two names for one clock, not
--    two clocks: at the shipped dials both are the seva's own Chicago start and
--    the three-argument one is the only thing any guard reads.
-- ---------------------------------------------------------------------------

create or replace function public.seva_completion_opens_at(
  p_date date,
  p_start_time time,
  p_duration_minutes integer
)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select greatest(
    ((p_date + p_start_time) at time zone 'America/Chicago')
      + make_interval(mins => public.seva_completion_lead_minutes()),
    ((p_date + p_start_time) at time zone 'America/Chicago')
      + make_interval(mins => coalesce(p_duration_minutes, 0))
      + make_interval(mins => public.seva_completion_end_grace_minutes())
  );
$$;

comment on function public.seva_completion_opens_at(date, time, integer) is
  'The instant a seva may first be marked completed: the later of its Chicago start plus seva.complete_after_start_minutes and its Chicago end plus seva.complete_after_end_minutes. Chicago and only Chicago, so the answer is the same for a devotee reading the app in Mayapur.';

revoke all on function public.seva_completion_opens_at(date, time, integer) from public, anon;
grant execute on function public.seva_completion_opens_at(date, time, integer) to authenticated;

create or replace function public.seva_completion_opens_at(
  p_date date,
  p_start_time time
)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select public.seva_completion_opens_at(p_date, p_start_time, 0);
$$;

comment on function public.seva_completion_opens_at(date, time) is
  'The floor under the completion bar for a seva starting then: its own Chicago start plus seva.complete_after_start_minutes. The bar for a REAL seva is seva_completion_opens_at(date, time, duration_minutes), which is this or the end of the seva, whichever is later.';

-- ---------------------------------------------------------------------------
-- 3. The reconciler, with the arm 0068 returned early from.
--
--    Everything else in this body is 0068's, unchanged and in its order: the
--    lock, the early return for anything that is not settled, the all-absent
--    arm that cancels and records, and the promotion arm that only ever reopens
--    a row this rule closed itself. The new arm is the one above them: no
--    places at all.
--
--    It writes nothing to public.service_instances_unserved. That table means
--    "closed because every place was answered no", 202608040069 publishes it as
--    nobody_served, and 0068's invariant that every row in it is 'cancelled'
--    stays true. A seva nobody joined is a different event and gets a different
--    answer, which is the whole of header finding two.
-- ---------------------------------------------------------------------------

create or replace function public.reconcile_service_instance_completion(
  p_instance_id uuid
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_status text;
  v_places integer;
  v_served boolean;
begin
  select instances.status into v_status
  from public.service_instances instances
  where instances.id = p_instance_id
  for update;

  -- Nothing to settle, or nothing settled yet. An 'open' or 'full' instance is
  -- not claiming anything.
  if v_status is null or v_status not in ('completed', 'cancelled') then
    return v_status;
  end if;

  select count(*) into v_places
  from public.service_assignments
  where service_instance_id = p_instance_id;

  if v_places = 0 then
    -- A seva a PERSON cancelled with nobody on it is their decision and is left
    -- exactly where they left it, the same way the promotion arm below leaves
    -- one alone.
    if v_status <> 'completed' then
      return v_status;
    end if;

    -- "As if no one served this, how is this seva completed." Nobody joined, so
    -- there is no absence to record and nothing to cancel — the seva goes back
    -- to being the unclaimed request it was, and 202608040019's capacity rule
    -- says which unclaimed status that is.
    perform public.refresh_service_instance_capacity(p_instance_id);
    select instances.status into v_status
    from public.service_instances instances
    where instances.id = p_instance_id;
    return v_status;
  end if;

  v_served := public.service_instance_has_server(p_instance_id);

  if v_status = 'completed' and not v_served then
    update public.service_instances
    set status = 'cancelled'
    where id = p_instance_id;
    insert into public.service_instances_unserved (service_instance_id)
    values (p_instance_id)
    on conflict (service_instance_id) do nothing;
    return 'cancelled';
  end if;

  -- The correction. Only ever a row this rule closed itself: a seva a person
  -- cancelled through cancel_service_instance is never in that table and is
  -- never reopened here, whatever is later recorded against a leftover place.
  if v_status = 'cancelled' and v_served
    and exists (
      select 1 from public.service_instances_unserved
      where service_instance_id = p_instance_id
    )
  then
    update public.service_instances
    set status = 'completed'
    where id = p_instance_id;
    delete from public.service_instances_unserved
    where service_instance_id = p_instance_id;
    return 'completed';
  end if;

  return v_status;
end;
$$;

comment on function public.reconcile_service_instance_completion(uuid) is
  'Settles one seva on the single question of whether anybody served it, and returns the status it settled on: completed when somebody did, cancelled with a row in service_instances_unserved when every place was answered no, and back to 202608040019''s unclaimed status when nobody was ever placed on it. Idempotent, decides nothing else, and only ever reopens a seva it closed itself.';

revoke all on function public.reconcile_service_instance_completion(uuid)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4. The poster's button: the clock moved to the end, and the seva nobody came
--    to refused at the door.
--
--    202608040023's authority check is still asked first of all, so a devotee
--    with no standing learns nothing about the temple's schedule from the
--    refusal they get. Then the clock, then the roster, then the write — every
--    refusal before anything is written, which is what 0068's verification
--    asserts on the source and this file keeps true.
--
--    TWO SENTENCES WHERE 0068 HAD ONE, because there are now two ways to be too
--    early and telling a devotee standing in the temple at 9:30 that their 9:00
--    seva "has not started yet" would be a lie the app tells to their face. The
--    not-started sentence is 0068's, word for word, and 202608040065's
--    verification pins it.
-- ---------------------------------------------------------------------------

create or replace function public.complete_service_instance(p_instance_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  instance_record public.service_instances;
  v_places integer;
begin
  select * into instance_record
  from public.service_instances
  where id = p_instance_id
  for update;

  if instance_record.id is null then
    raise exception 'This seva request could not be found.';
  end if;

  -- Confirming that a seva actually happened belongs to whoever asked for it,
  -- and to the two levels that can override anything.
  if instance_record.posted_by is distinct from auth.uid()
    and not public.has_permission('app.view_all')
  then
    raise exception 'Only the devotee who posted this seva request, a Tech Admin, or the President can mark it completed.';
  end if;

  -- Sentence 3, on the end of the seva. Plain enough to put in front of a
  -- devotee, and it says when they may come back.
  if public.seva_completion_opens_at(
       instance_record.date, instance_record.start_time,
       instance_record.duration_minutes) > now()
  then
    if ((instance_record.date + instance_record.start_time)
        at time zone 'America/Chicago') > now() then
      raise exception
        'This seva has not started yet. You can mark it completed once its time on % has passed.',
        public.format_seva_when(instance_record.date, instance_record.start_time);
    end if;
    raise exception
      'This seva has not finished yet. You can mark it completed once its time on % has passed.',
      public.format_seva_when(instance_record.date, instance_record.start_time);
  end if;

  -- "As if no one served this, how is this seva completed." Nobody joined, so
  -- there is nothing here to call completed. Refused rather than settled
  -- afterwards, because a button that appears to work and quietly undoes itself
  -- is worse than one that says why not.
  select count(*) into v_places
  from public.service_assignments
  where service_instance_id = p_instance_id;
  if v_places = 0 then
    raise exception
      'Nobody joined this seva, so there is nothing to mark completed. Remove the request instead if it did not happen.';
  end if;

  if not public.complete_service_instance_internal(p_instance_id, auth.uid(), false) then
    raise exception 'This seva can no longer be completed.';
  end if;
end;
$$;

revoke all on function public.complete_service_instance(uuid) from public, anon;
grant execute on function public.complete_service_instance(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. The shared body, which is also the hourly sweep's.
--
--    0068's is kept whole. The one change is the notice: it settled on three
--    outcomes rather than two, and telling oversight that somebody "completed"
--    a seva that has just gone back to being an unclaimed request would be the
--    same false sentence 0068 removed for the all-absent case.
-- ---------------------------------------------------------------------------

create or replace function public.complete_service_instance_internal(
  p_instance_id uuid,
  p_actor_id uuid,
  p_auto boolean
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  instance_record public.service_instances;
  participant record;
  actor_name text;
  v_settled text;
begin
  -- Order preserved from 202608040023 and load-bearing: the instance leaves
  -- 'open'/'full' first, so refresh_capacity_after_assignment cannot pull it
  -- back when the assignments move underneath it.
  update public.service_instances set status = 'completed'
  where id = p_instance_id and status not in ('completed', 'cancelled');
  if not found then
    return false;
  end if;

  update public.service_assignments
  set status = 'completed', completed_at = coalesce(completed_at, now())
  where service_instance_id = p_instance_id
    and status in ('assigned', 'confirmed')
    -- Auto-completion fills a silence. A row somebody has already spoken about
    -- is not silent, whatever they said.
    and (not coalesce(p_auto, false) or attendance is null);

  -- Sentence 2, on both paths, once the places have settled.
  v_settled := public.reconcile_service_instance_completion(p_instance_id);

  if coalesce(p_auto, false) then
    return true;
  end if;

  select * into instance_record from public.service_instances where id = p_instance_id;
  select name into actor_name from public.users where id = p_actor_id;

  if v_settled = 'cancelled' then
    perform public.notify_service_oversight(
      'service_completed', 'A seva closed with nobody having served it',
      actor_name || ' closed "' || public.service_instance_name(instance_record)
        || '", and everybody on it was marked absent or excused, so it is not counted as served. '
        || 'Correcting an attendance mark puts it back.',
      jsonb_build_object('serviceInstanceId', p_instance_id, 'served', false),
      p_actor_id
    );
    return true;
  end if;

  if v_settled is distinct from 'completed' then
    perform public.notify_service_oversight(
      'service_completed', 'A seva closed with nobody having joined it',
      actor_name || ' closed "' || public.service_instance_name(instance_record)
        || '", and nobody was ever on it, so it is not counted as served and is back to being an unclaimed request.',
      jsonb_build_object('serviceInstanceId', p_instance_id, 'served', false),
      p_actor_id
    );
    return true;
  end if;

  for participant in
    select distinct devotee_id from public.service_assignments
    where service_instance_id = p_instance_id and devotee_id <> p_actor_id
  loop
    perform public.queue_app_notification(
      participant.devotee_id, 'service_completed', 'Seva marked completed',
      actor_name || ' marked "' || public.service_instance_name(instance_record) || '" completed.',
      jsonb_build_object('serviceInstanceId', p_instance_id)
    );
  end loop;

  perform public.notify_service_oversight(
    'service_completed', 'A seva request was completed',
    actor_name || ' completed "' || public.service_instance_name(instance_record) || '".',
    jsonb_build_object('serviceInstanceId', p_instance_id), p_actor_id
  );

  return true;
end;
$$;

comment on function public.complete_service_instance_internal(uuid, uuid, boolean) is
  'The two UPDATEs that close a seva, followed by the question of whether anybody served it, with no authority check of its own. Never granted to a client role: reach it through complete_service_instance, which is 202608040023''s permission rule and 202608040070''s clock, or through complete_due_recurring_service_instances, which is the clock on its own.';

revoke all on function public.complete_service_instance_internal(uuid, uuid, boolean)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 6. The devotee's own button, which can close the whole seva by itself.
--
--    The same two sentences as section 4, in 202608040019's words, and the same
--    boundary function — so the poster's button and the devotee's still open at
--    the same instant, which was 0068's own requirement and is met by moving
--    both rather than neither.
-- ---------------------------------------------------------------------------

create or replace function public.complete_my_service_assignment(p_instance_id uuid)
returns public.service_assignments
language plpgsql
security definer
set search_path = ''
as $$
declare
  instance_record public.service_instances;
  completed_assignment public.service_assignments;
  completed_count integer;
  devotee_name text;
begin
  if auth.uid() is null then
    raise exception 'Authentication is required.';
  end if;

  select * into instance_record
  from public.service_instances
  where id = p_instance_id
  for update;

  if instance_record.id is null or instance_record.status = 'cancelled' then
    raise exception 'This seva is no longer available.';
  end if;

  -- Seva cannot be reported finished before it has finished.
  if public.seva_completion_opens_at(
       instance_record.date, instance_record.start_time,
       instance_record.duration_minutes) > now()
  then
    if ((instance_record.date + instance_record.start_time)
        at time zone 'America/Chicago') > now() then
      raise exception 'You can mark this seva completed once it has started.';
    end if;
    raise exception 'You can mark this seva completed once it has finished.';
  end if;

  update public.service_assignments
  set status = 'completed', completed_at = coalesce(completed_at, now())
  where service_instance_id = p_instance_id
    and devotee_id = auth.uid()
    and status in ('assigned', 'confirmed')
  returning * into completed_assignment;

  if completed_assignment.id is null then
    raise exception 'You are not currently assigned to this seva.';
  end if;

  select count(*) into completed_count
  from public.service_assignments
  where service_instance_id = p_instance_id and status = 'completed';

  if completed_count >= instance_record.slots_needed then
    update public.service_instances
    set status = 'completed' where id = p_instance_id;
    perform public.reconcile_service_instance_completion(p_instance_id);
  end if;

  select name into devotee_name from public.users where id = auth.uid();
  if instance_record.posted_by is not null
    and instance_record.posted_by <> auth.uid()
  then
    perform public.queue_app_notification(
      instance_record.posted_by, 'service_completed', 'A devotee finished their seva',
      devotee_name || ' marked their part of "'
        || public.service_instance_name(instance_record) || '" completed.',
      jsonb_build_object('serviceInstanceId', p_instance_id)
    );
  end if;

  return completed_assignment;
end;
$$;

revoke all on function public.complete_my_service_assignment(uuid) from public, anon;
grant execute on function public.complete_my_service_assignment(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 7. The two clocks made to agree.
--
--    202608040065's view, with every clause it had — recurring only, never
--    completed or cancelled, inside the lookback, holding a place nobody has
--    spoken about — and the same seven columns in the same order, so nothing
--    that selects from it notices. due_at is now the LATER of 0065's own
--    end-plus-grace and this file's completion bar.
--
--    AT THE SHIPPED DIALS NOTHING MOVES: grace 60, complete_after_end_minutes
--    0, complete_after_start_minutes 0, so the later of end + 60 and end + 0 is
--    end + 60, which is where 0065 put it. What changes is what happens when
--    somebody turns a dial. The sweep can no longer close a seva at an instant
--    when a President pressing the button would be refused, in either
--    direction, and 0065's grace still has the last word whenever it is the
--    stricter of the two.
-- ---------------------------------------------------------------------------

create or replace view public.due_recurring_service_instances as
  select
    instances.id as service_instance_id,
    instances.template_id,
    instances.date,
    instances.start_time,
    instances.duration_minutes,
    ((instances.date + instances.start_time) at time zone 'America/Chicago')
      + make_interval(mins => instances.duration_minutes) as ends_at,
    greatest(
      ((instances.date + instances.start_time) at time zone 'America/Chicago')
        + make_interval(mins => instances.duration_minutes)
        + make_interval(mins => (
            coalesce(
              nullif(trim(public.app_setting('seva.auto_complete_grace_minutes')), ''),
              '60'
            )::integer
          )),
      public.seva_completion_opens_at(
        instances.date, instances.start_time, instances.duration_minutes)
    ) as due_at
  from public.service_instances instances
  where instances.template_id is not null
    and instances.status not in ('completed', 'cancelled')
    and instances.date >= (now() at time zone 'America/Chicago')::date
        - coalesce(
            nullif(trim(public.app_setting('seva.auto_complete_lookback_days')), ''),
            '90'
          )::integer
    and greatest(
          ((instances.date + instances.start_time) at time zone 'America/Chicago')
            + make_interval(mins => instances.duration_minutes)
            + make_interval(mins => (
                coalesce(
                  nullif(trim(public.app_setting('seva.auto_complete_grace_minutes')), ''),
                  '60'
                )::integer
              )),
          public.seva_completion_opens_at(
            instances.date, instances.start_time, instances.duration_minutes)
        ) <= now()
    and exists (
      select 1 from public.service_assignments assignments
      where assignments.service_instance_id = instances.id
        and assignments.status in ('assigned', 'confirmed')
        and assignments.attendance is null
    );

comment on view public.due_recurring_service_instances is
  'Recurring seva slots whose Chicago hour, plus the later of seva.auto_complete_grace_minutes and the completion bar every button reads, has gone by, and which still hold at least one assignment nobody has spoken about. What the sweep is about to close.';

revoke all on public.due_recurring_service_instances from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 8. The gates that must NOT have moved.
--
--    "Who was here?" is asked during the seva, in front of the empty place, and
--    that is why record_seva_attendance and verify_seva_assignment open at the
--    start and are not touched by this file. The risk is not that somebody
--    disagrees; it is that a later edit tidies all the clock gates into one
--    function and takes attendance with it, leaving a coordinator unable to
--    mark somebody absent until the seva is over. Asserted on the bodies, so
--    that edit fails here.
-- ---------------------------------------------------------------------------

do $$
declare
  v_case record;
begin
  for v_case in
    select * from (values
      ('public.record_seva_attendance(uuid, text)',
       'Attendance can be recorded once the seva has started.'),
      ('public.verify_seva_assignment(uuid)',
       'A seva can be verified once it has started.')
    ) as expected(target, sentence)
  loop
    if position(v_case.sentence in
         pg_get_functiondef(v_case.target::regprocedure)) = 0 then
      raise exception
        '% no longer opens at the start of the seva; a coordinator cannot mark somebody absent while it is happening.',
        v_case.target;
    end if;
    if pg_get_functiondef(v_case.target::regprocedure) ~* 'seva_completion_opens_at' then
      raise exception
        '% now reads the completion bar, so recording who was there waits for the seva to be over.',
        v_case.target;
    end if;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- 9. The data that is already wrong.
--
--     CORRECTED: a seva at 'completed' with no places on it at all. Nobody
--     joined it, nobody was marked anything, and no devotee's points move by a
--     minute when it goes back to being an unclaimed request — there is nobody
--     on it to have points. It is the one row shape this file can put right
--     without guessing.
--
--     NOT CORRECTED, for 0068's reason and in 0068's words: a seva at
--     'completed' whose time has not passed. The truth about those is not
--     knowable from here and the assignments were moved to 'completed' too, so
--     un-completing somebody's seva without being asked is exactly the kind of
--     quiet change this file is written against. Sections 4 and 6 stop any more
--     being made; these are counted in a notice so that whoever wants them
--     reopened can say so.
-- ---------------------------------------------------------------------------

do $$
declare
  v_instance uuid;
  v_reopened integer := 0;
  v_early integer := 0;
begin
  for v_instance in
    select instances.id
    from public.service_instances instances
    where instances.status = 'completed'
      and not exists (
        select 1 from public.service_assignments assignments
        where assignments.service_instance_id = instances.id
      )
    order by instances.date
  loop
    if public.reconcile_service_instance_completion(v_instance)
       is distinct from 'completed' then
      v_reopened := v_reopened + 1;
    end if;
  end loop;

  select count(*) into v_early
  from public.service_instances instances
  where instances.status = 'completed'
    and public.seva_completion_opens_at(
          instances.date, instances.start_time, instances.duration_minutes) > now();

  raise notice
    'completion window: % seva nobody ever joined put back to unclaimed; % seva completed before their time had passed left alone for a person to decide about.',
    v_reopened, v_early;
end;
$$;

-- ---------------------------------------------------------------------------
-- 10. What this file is not allowed to have become.
-- ---------------------------------------------------------------------------

do $$
declare
  v_today date := (now() at time zone 'America/Chicago')::date;
begin
  -- Both buttons read the bar that knows how long the seva is. A guard that
  -- kept the two-argument form would be reading the start again.
  if pg_get_functiondef('public.complete_service_instance(uuid)'::regprocedure)
       !~* 'seva_completion_opens_at'
    or pg_get_functiondef('public.complete_service_instance(uuid)'::regprocedure)
       !~* 'instance_record\.duration_minutes'
  then
    raise exception
      'complete_service_instance no longer measures the bar against the length of the seva; the temple''s sentence is unenforced again.';
  end if;
  if pg_get_functiondef('public.complete_my_service_assignment(uuid)'::regprocedure)
       !~* 'seva_completion_opens_at'
    or pg_get_functiondef('public.complete_my_service_assignment(uuid)'::regprocedure)
       !~* 'instance_record\.duration_minutes' then
    raise exception
      'complete_my_service_assignment no longer measures the bar against the length of the seva.';
  end if;

  -- The bar really is the end at the shipped dials, asked through the function
  -- rather than asserted about it.
  if public.seva_completion_opens_at(v_today, time '08:00', 60)
     <> ((v_today + time '08:00') at time zone 'America/Chicago') + interval '60 minutes'
  then
    raise exception 'The completion bar is not the end of the seva at the shipped dials.';
  end if;

  -- And it can never fall before the start, whatever the grace is set to.
  if public.seva_completion_opens_at(v_today, time '08:00', 0)
     < ((v_today + time '08:00') at time zone 'America/Chicago')
  then
    raise exception 'The completion bar can fall before the seva starts.';
  end if;

  -- Sentence 2 is still on the shared body, so the hourly sweep obeys it too.
  if pg_get_functiondef('public.complete_service_instance_internal(uuid, uuid, boolean)'::regprocedure)
     !~* 'reconcile_service_instance_completion' then
    raise exception
      'complete_service_instance_internal no longer asks whether anybody served the seva.';
  end if;

  -- And the mark that causes it still settles it. Untouched here, asserted
  -- here, because this file rewrites the function it calls.
  if pg_get_functiondef('public.record_seva_attendance(uuid, text)'::regprocedure)
     !~* 'reconcile_service_instance_completion' then
    raise exception
      'record_seva_attendance no longer settles the seva, so marking the last server absent leaves it in the completed list.';
  end if;

  -- The sweep's own selection still excludes what 0068 closes.
  if pg_get_viewdef('public.due_recurring_service_instances'::regclass)
     !~* 'cancelled' then
    raise exception
      'due_recurring_service_instances no longer excludes cancelled instances; the sweep would resurrect every seva nobody served.';
  end if;

  -- The sweep can never be the early door.
  if pg_get_viewdef('public.due_recurring_service_instances'::regclass)
     !~* 'seva_completion_opens_at' then
    raise exception
      'The hourly sweep no longer reads the completion bar, so a dial could let a clock close a seva no person is allowed to close.';
  end if;

  -- Nothing here writes a status outside 202608020002's vocabulary, and the
  -- never-joined arm in particular delegates rather than inventing one.
  if pg_get_functiondef('public.reconcile_service_instance_completion(uuid)'::regprocedure)
     !~* 'refresh_service_instance_capacity' then
    raise exception
      'The reconciler decides the status of an emptied instance itself instead of asking 202608040019.';
  end if;
end;
$$;

do $$
begin
  raise notice 'completion window applied';
end;
$$;
