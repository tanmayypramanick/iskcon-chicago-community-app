-- A seva is completed when it has happened and somebody served it.
--
-- Three sentences from the temple, and the database currently keeps only one
-- of them:
--
--   1. "If marked absent and excused, it will not count as seva for that
--       person and will not get seva points."
--   2. "If there is only one person doing seva, if marked absent or excused,
--       it will get removed from the list and not go in the completed list —
--       as if no one served this, how is this seva completed. And if there are
--       more people assigned in that seva but only one or two people were
--       absent or excused, then if one person did the seva, it will still go
--       to the completed list as one person served, and only that person will
--       get seva in their list and seva points will be going only to that
--       person."
--   3. "If it is upcoming seva and the time has not passed yet, it will not
--       show 'mark my seva completed', as the date is still in the future.
--       After the seva has been done and the time has passed, only then can
--       anyone do 'complete my seva' and mark this entire seva completed."
--
-- SENTENCE 1 IS ALREADY TRUE AND NOTHING HERE CHANGES IT. 202608040057 put the
-- whole of it in one place — public.seva_points_status returns 'not_served' for
-- attendance 'absent' and for attendance 'excused', ahead of every other arm of
-- the CASE — and 202608040059 kept that arm first when it added the recurring
-- rule underneath it. Every number the temple publishes is downstream of that
-- one function: seva_mala_acts sets quality to 0 for any act that is not
-- 'counted', seva_balance_acts and seva_mala_served filter 'not_served' out by
-- name, and list_all_seva_hours counts only the three 'awaiting' statuses as
-- outstanding. There is no second path that adds minutes to a devotee, which
-- was the first thing checked when this file was written and is asserted again
-- in section 0 below and in the verification, so that it cannot quietly grow
-- one later.
--
-- SENTENCE 3 IS NOT ENFORCED AT ALL, and that is finding one.
-- complete_service_instance guards on WHO may close a seva (202608040023) and
-- on the status it is in (202608040013), and on nothing else. A President or a
-- poster can close next Sunday's kitchen slot this afternoon; on the copy of
-- the temple's data this file was written against, three instances dated the
-- evening of 12 August were already sitting at 'completed' at midday. Section 4
-- adds the clock.
--
-- SENTENCE 2 IS NOT ENFORCED EITHER, and that is finding two. The same copy of
-- the temple's data holds Temple Room Cleaning on 11 August, one devotee on the
-- roster, that devotee marked ABSENT, and the instance at 'completed'. Her act
-- is correctly worth nothing — sentence 1 held — and the seva is nevertheless
-- in the completed list saying it happened. That is the exact row the temple is
-- pointing at. Sections 2, 3 and 5 to 8 take it out.
--
-- ---------------------------------------------------------------------------
-- 1. WHICH MOMENT BARS A COMPLETION: THE START, NOT THE END.
--
--    The temple's sentence can be read either way — "after the seva has been
--    done and the time has passed" sounds like the end, "the date is still in
--    the future" sounds like the start — so the tie is broken by what the rest
--    of the system already does, and then checked against what an end-time bar
--    would actually buy.
--
--    EVERY OTHER CLOCK GATE ON A SEVA IS THE START, in the temple's own time
--    zone, and there are three of them:
--
--      record_seva_attendance  (202608040027)
--        'Attendance can be recorded once the seva has started.'
--      verify_seva_assignment  (202608040027)
--        same boundary, same wording
--      complete_my_service_assignment  (202608040019 section 2)
--        'You can mark this seva completed once it has started.'
--
--    A fourth gate on a different boundary would mean the temple had two
--    answers to "has this seva happened yet", and coordinators would meet both
--    on the same screen: they could say who attended, but not that the thing
--    they had just recorded attendance for was done.
--
--    AND AN END-TIME BAR WOULD BE A FENCE WITH A GATE BESIDE IT.
--    complete_my_service_assignment already flips the WHOLE instance to
--    'completed' the moment the number of completed places reaches
--    slots_needed (202608040019 section 2), and it opens at the START. So a bar
--    at the end on complete_service_instance would stop the poster's button and
--    not the devotees', for the same seva, in the same minute. The bar has to
--    be the start or it is not a bar.
--
--    WHAT AN END-TIME BAR WOULD HAVE BOUGHT is a seva that cannot be closed
--    while it is still running. That is a real thing to want, and it is
--    available without a second boundary: section 4's dial is minutes AFTER the
--    start, so a temple that wants the whole hour to have elapsed sets it to
--    the length of the hour. The default is 0, which is exactly
--    record_seva_attendance's bar, so nothing moves unless somebody decides it
--    should.
--
--    THE HOURLY SWEEP IS ALREADY STRICTER AND STAYS STRICTER. 202608040065
--    closes a recurring slot only once (date + start_time) in Chicago, plus its
--    own duration_minutes, plus seva.auto_complete_grace_minutes, has gone by.
--    That is the end plus an hour, and it is a deliberate choice about a job
--    that nobody presses. Section 4 does not touch it; the two bars sit one
--    inside the other, and the sweep's is the inner one.
--
-- ---------------------------------------------------------------------------
-- 2. WHAT "NOBODY SERVED THIS" IS, AND WHY IT IS ASKED THROUGH
--    seva_points_status RATHER THAN BY LOOKING AT attendance.
--
--    The temple names two marks, absent and excused. The system has five ways
--    for a place on a seva to come to nothing, and seva_points_status already
--    holds all five in one line each:
--
--      status 'no_show'     -> not_served
--      status 'withdrawn'   -> not_served
--      attendance 'absent'  -> not_served
--      attendance 'excused' -> not_served
--      anything else        -> counted / awaiting_something
--
--    So the question "did anybody serve this seva" is asked as: is there any
--    place on it whose points_status is not 'not_served'. That is one
--    definition, not a second one written alongside the first, and it means
--    this file can never disagree with the scoring — if 0057 or 0059's rule
--    moves, the completed list moves with it instead of drifting away from it.
--
--    A PLACE NOBODY HAS SPOKEN ABOUT COUNTS AS SERVICE. A completed assignment
--    with no attendance mark reads 'counted' on a weekly slot and
--    'awaiting_verification' on a one-off; neither is 'not_served'. So a seva
--    is only taken out of the completed list when EVERY place on it has been
--    explicitly answered and every answer was no. Silence is never read as
--    absence. That is deliberate and it is the conservative direction: the
--    temple asked for the seva to come out of the list when people are MARKED
--    absent, not when nobody has got round to marking anything.
--
--    A SEVA WITH NO PLACES AT ALL IS LEFT EXACTLY AS IT IS. An open request
--    that nobody answered and that the poster closed anyway has nobody who was
--    marked absent, so sentence 2 has nothing to say about it, and this file
--    says nothing about it either. 202608040065 already refuses to
--    auto-complete such an instance; that is that feature's rule and it stays
--    there.
--
-- ---------------------------------------------------------------------------
-- 3. THE HONEST TERMINAL STATE FOR A SEVA NOBODY SERVED IS 'cancelled'.
--
--    service_instances.status is checked to ('open', 'full', 'closed',
--    'cancelled', 'completed') by 202608020002 and this file adds nothing to
--    that list. Three of the five are candidates and two of them are wrong:
--
--    'completed' IS THE BUG. It is the claim the temple is disputing.
--
--    'closed' LOOKS RIGHT AND RESURRECTS THE SEVA. It already means something
--    else — 202608040014 and 202608040025 create an instance 'closed' when a
--    verification is accepted for a seva that has not finished yet, and
--    202608040020 section 1's settle_finished_verified_seva exists precisely to
--    move 'closed' on to 'completed' once the end time passes. So a seva parked
--    at 'closed' would be picked up by that reconciler and completed again. It
--    is also not 'cancelled', which is the shape of every "is this still live"
--    test in the system: join_weekly_service, respond_to_service_offer and
--    respond_to_coverage_range_offer all backfill assignments into any instance
--    whose status is `not in ('cancelled', 'completed')` from today onwards, so
--    a same-day slot parked at 'closed' can still be joined after the fact; and
--    on the client, upcomingServices, sevaHappeningNow and
--    awaitingCompletionServices all exclude exactly 'completed' and 'cancelled'
--    and would show a seva that is over and settled as one still waiting for
--    somebody to press something. Nothing can clear that queue entry: pressing
--    the button would complete the instance and this file would put it straight
--    back.
--
--    'cancelled' IS WHAT THE TEMPLE ASKED FOR, IN THE WORDS THEY USED. "It will
--    get removed from the list" — and 'cancelled' is the one status every
--    reader in the system already treats as "this did not happen":
--
--      seva_mala_acts            `instances.status <> 'cancelled'`  the act
--                                leaves the scoring entirely. It was worth zero
--                                anyway — every place on it is 'not_served' —
--                                so no devotee's total moves by a minute.
--      list_seva_awaiting_confirmation  same filter: the seva stops appearing
--                                in a queue where there is nothing left to do.
--      completedServices (client)  `status === 'completed'`: gone from the
--                                completed list, which is the whole request.
--      upcomingServices, sevaHappeningNow, lapsedOpenRequests (client)
--                                exclude 'cancelled': it cannot come back as
--                                something to join or something happening now.
--      join_weekly_service, respond_to_service_offer,
--      respond_to_coverage_range_offer
--                                exclude 'cancelled': no backfill can put a
--                                devotee on it afterwards.
--      due_recurring_service_instances (202608040065)
--                                excludes 'cancelled': the hourly sweep will
--                                not re-close it next hour, or ever.
--      refresh_service_instance_capacity (202608040019)
--                                only rewrites 'open', 'full' and 'completed',
--                                so 'cancelled' is genuinely terminal and
--                                cannot be pulled back to 'open' underneath us.
--      complete_service_instance, cancel_service_instance,
--      complete_my_service_assignment
--                                all refuse a cancelled instance already, in
--                                sentences that are already written.
--
--    THE COST, SAID OUT LOUD: a cancelled instance is invisible in the app's
--    seva lists, which is what "removed from the list" means but is also how a
--    seva could vanish from the coordinator who has to answer for it. Three
--    things stop that being a silent drop. seva_dashboard returns every
--    instance with its status and filters none of them, so the row is still
--    there to be read. Section 9 adds list_seva_closed_unserved, so the poster,
--    the Tech Admin and the President can ask for exactly these and see who was
--    marked what. And section 5 tells oversight in words at the moment it
--    happens, rather than sending the "marked completed" notice that
--    202608040023 would otherwise send about a seva that was not.
--
--    AND IT IS REVERSIBLE, WHICH IS THE REASON FOR THE ONE NEW TABLE. A
--    coordinator who marks the wrong devotee absent has taken a seva out of the
--    completed list and, with it, that devotee's points. Correcting the mark
--    has to put both back. But 'cancelled' is also what a person means when
--    they cancel a seva through cancel_service_instance, and promoting one of
--    those back to 'completed' because somebody later recorded attendance on a
--    leftover place would be this file undoing a human decision. The two cases
--    are indistinguishable from the status column alone, so section 3 records
--    which instances THIS RULE closed, in public.service_instances_unserved,
--    and the promotion arm will only ever touch a row it put there itself. A
--    seva a person cancelled is never reopened by anything here.
--
-- ---------------------------------------------------------------------------
-- 4. WHERE THE RULE IS APPLIED, AND WHY IT IS NOT ONE PLACE.
--
--    The temple's complaint is not "completing a seva marks it wrongly". It is
--    "a seva that is marked completed STAYS marked completed after somebody
--    says nobody was there". Attendance is almost always recorded AFTER
--    completion — 202608040065 section 4 relies on exactly that, and
--    record_seva_attendance is deliberately not gated on the instance still
--    being open — so a rule applied only at completion time would miss the
--    whole complaint. It is therefore applied at every point where either half
--    of the question can change:
--
--      complete_service_instance_internal   the poster's button AND
--                                           202608040065's hourly sweep, which
--                                           share this one body
--      complete_my_service_assignment       the devotee's own button, which
--                                           can flip the instance by itself
--      record_seva_attendance               the mark that causes it, and the
--                                           correction that undoes it
--      settle_finished_verified_seva        the fourth writer of 'completed',
--                                           which nobody presses
--
--    All four call one function, public.reconcile_service_instance_completion,
--    which is idempotent, decides nothing on its own, and returns the status it
--    settled on. No argument list changes anywhere in this file.
--
--    A trigger on service_assignments.attendance was the obvious alternative
--    and is not used. record_seva_attendance is the only function in the schema
--    that writes that column, so a trigger would buy coverage of direct SQL
--    only — and it would fire on the INSERTs that a dozen verification fixtures
--    use to build completed instances with absent devotees on purpose, quietly
--    rewriting other files' fixtures out from under them.
--
-- Requires 202608040067_award_currency_and_care_reach.sql.

-- ---------------------------------------------------------------------------
-- 0. The ground this stands on, asserted rather than assumed.
--
--    This file rewrites five functions that other migrations have already
--    rewritten, and its whole meaning rests on sentence 1 still being true in
--    seva_points_status. If that has moved, "nobody served this" below means
--    something other than what the header says.
-- ---------------------------------------------------------------------------

do $$
declare
  v_offenders text;
begin
  if to_regprocedure('public.complete_service_instance(uuid)') is null
    or to_regprocedure('public.complete_service_instance_internal(uuid, uuid, boolean)') is null
    or to_regprocedure('public.complete_my_service_assignment(uuid)') is null
    or to_regprocedure('public.record_seva_attendance(uuid, text)') is null
    or to_regprocedure('public.settle_finished_verified_seva()') is null
    or to_regprocedure('public.seva_points_status(text, text, text, boolean)') is null
    or to_regprocedure('public.app_setting(text)') is null
    or to_regprocedure('public.has_permission(text)') is null
    or to_regprocedure('public.notify_service_oversight(text, text, text, jsonb, uuid)') is null
  then
    raise exception
      'The seva completion path is not in place; apply 202608040023, 202608040027, 202608040059 and 202608040065 first.';
  end if;

  -- SENTENCE 1. Both overloads, because list_seva_awaiting_confirmation and
  -- seva_mala_acts do not call the same one.
  if public.seva_points_status('completed', 'absent', 'member_verified') <> 'not_served'
    or public.seva_points_status('completed', 'excused', 'member_verified') <> 'not_served'
    or public.seva_points_status('completed', 'absent', 'member_verified', true) <> 'not_served'
    or public.seva_points_status('completed', 'excused', 'member_verified', true) <> 'not_served'
    or public.seva_points_status('completed', 'absent', 'member_verified', false) <> 'not_served'
    or public.seva_points_status('completed', 'excused', 'member_verified', false) <> 'not_served'
    or public.seva_points_status('no_show', null, 'self_report', true) <> 'not_served'
    or public.seva_points_status('withdrawn', null, 'self_report', true) <> 'not_served'
  then
    raise exception
      'seva_points_status no longer reads an absent or excused devotee as not_served; sentence 1 has moved and this file would enforce the wrong rule.';
  end if;

  -- SENTENCE 2's other half, which is 0057's and 0059's and is only confirmed
  -- here: a place nobody has spoken about is not an absence.
  if public.seva_points_status('completed', null, 'self_report', true) <> 'counted'
    or public.seva_points_status('completed', null, 'self_report', false) <> 'awaiting_verification'
  then
    raise exception
      'A completed place with no attendance mark no longer reads as service; section 2''s definition of "nobody served" would be wrong.';
  end if;

  -- The status vocabulary this file settles on, and does not extend.
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.service_instances'::regclass
      and conname = 'service_instances_status_check'
      and pg_get_constraintdef(oid) like '%''cancelled''%'
      and pg_get_constraintdef(oid) like '%''completed''%'
  ) then
    raise exception
      'public.service_instances no longer constrains status to the vocabulary this file settles on.';
  end if;

  -- SENTENCE 1 AGAIN, FROM THE OTHER SIDE: no path credits a devotee except
  -- through seva_points_status. Everything that turns places into minutes goes
  -- through seva_mala_acts, and seva_mala_acts asks the function.
  select string_agg(proc.proname, ', ' order by proc.proname) into v_offenders
  from pg_proc proc
  join pg_namespace spaces on spaces.oid = proc.pronamespace
  where spaces.nspname = 'public'
    and proc.proname in (
      'seva_mala_acts', 'seva_balance_acts', 'seva_mala_served',
      'seva_mala_window_points', 'list_all_seva_hours'
    )
    and pg_get_functiondef(proc.oid) !~* '(seva_points_status|seva_mala_acts|points_status)';
  if v_offenders is not null then
    raise exception
      '% counts seva without asking seva_points_status, so an absent devotee could be credited there.', v_offenders;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 1. One dial, so the bar can move without a migration.
--
--      seva.complete_after_start_minutes   whole minutes past the seva's own
--                                          Chicago start before anybody may
--                                          mark it completed. 0 to 1440.
--
--    ZERO IS THE DEFAULT and zero is exactly record_seva_attendance's and
--    verify_seva_assignment's bar: the instant the seva starts. A temple that
--    wants the seva to have finished sets this to its usual length; a temple
--    that wants a whole day sets 1440. Header section 1 is why this is a
--    forward offset from the start rather than a second boundary at the end.
--
--    Seeded on conflict do nothing, so re-applying never stamps on a value the
--    temple has since changed, and read through 202608040026's app_setting().
--    A malformed value RAISES rather than falling back, which is 202608040055's
--    rule for a dial: this one is read on a button a devotee presses, so the
--    error is seen by somebody who can report it rather than buried in a log.
-- ---------------------------------------------------------------------------

insert into public.app_settings (key, value)
values ('seva.complete_after_start_minutes', '0')
on conflict (key) do nothing;

create or replace function public.seva_completion_lead_minutes()
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
    nullif(trim(public.app_setting('seva.complete_after_start_minutes')), ''), '0');
  begin
    v_minutes := v_raw::integer;
  exception when others then
    raise exception
      'seva.complete_after_start_minutes is "%", which is not a whole number of minutes.', v_raw;
  end;
  if v_minutes < 0 or v_minutes > 1440 then
    raise exception
      'seva.complete_after_start_minutes is %, which is outside 0 to 1440.', v_minutes;
  end if;
  return v_minutes;
end;
$$;

comment on function public.seva_completion_lead_minutes() is
  'Whole minutes past a seva''s own Chicago start before anybody may mark it completed. 0, the default, is record_seva_attendance''s bar exactly.';

revoke all on function public.seva_completion_lead_minutes() from public, anon;
grant execute on function public.seva_completion_lead_minutes() to authenticated;

-- The one place the boundary is computed, so the guard in section 4, the guard
-- in section 6 and the verification are all reading the same clock.
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
  select ((p_date + p_start_time) at time zone 'America/Chicago')
       + make_interval(mins => public.seva_completion_lead_minutes());
$$;

comment on function public.seva_completion_opens_at(date, time) is
  'The instant a seva may first be marked completed: its own start in the temple''s time zone, plus seva.complete_after_start_minutes. Chicago and only Chicago, so the answer is the same for a devotee reading the app in Mayapur.';

revoke all on function public.seva_completion_opens_at(date, time) from public, anon;
grant execute on function public.seva_completion_opens_at(date, time) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. "Did anybody serve this seva", asked exactly once.
--
--    Header section 2: through seva_points_status, so this file and the scoring
--    can never hold different opinions about the same place.
-- ---------------------------------------------------------------------------

create or replace function public.service_instance_has_server(p_instance_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.service_assignments assignments
    join public.service_instances instances
      on instances.id = assignments.service_instance_id
    where assignments.service_instance_id = p_instance_id
      and public.seva_points_status(
            assignments.status,
            assignments.attendance,
            assignments.verification,
            instances.template_id is not null
          ) <> 'not_served'
  );
$$;

comment on function public.service_instance_has_server(uuid) is
  'Whether any place on this seva is anything other than not_served. False only when every place has been explicitly answered and every answer was no: absent, excused, no_show or withdrawn. A place nobody has spoken about is service, not absence.';

revoke all on function public.service_instance_has_server(uuid) from public, anon;
grant execute on function public.service_instance_has_server(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. The reconciler, and the one row of bookkeeping that makes it reversible.
--
--    public.service_instances_unserved holds the instances THIS RULE closed,
--    and nothing else. It exists so that the promotion arm can tell a seva this
--    file cancelled from a seva a person cancelled, and never reopen the
--    second. Backend only: no grant to any client role, and RLS on with no
--    policy, which is how every internal table in this schema is held.
-- ---------------------------------------------------------------------------

create table if not exists public.service_instances_unserved (
  service_instance_id uuid primary key
    references public.service_instances(id) on delete cascade,
  closed_at timestamptz not null default now()
);

alter table public.service_instances_unserved enable row level security;

comment on table public.service_instances_unserved is
  'Seva that was closed as "nobody served it" by 202608040068 rather than cancelled by a person. The only rows the reconciler will ever promote back to completed.';

revoke all on public.service_instances_unserved from public, anon, authenticated;

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
  -- not claiming anything, and a seva nobody was ever placed on has nobody who
  -- was marked absent (header section 2).
  if v_status is null or v_status not in ('completed', 'cancelled') then
    return v_status;
  end if;

  select count(*) into v_places
  from public.service_assignments
  where service_instance_id = p_instance_id;
  if v_places = 0 then
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
  'Settles one seva between completed and cancelled on the single question of whether anybody served it, and returns the status it settled on. Idempotent, decides nothing else, and only ever reopens a seva it closed itself.';

revoke all on function public.reconcile_service_instance_completion(uuid)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4. Sentence 3. The clock, on the front door.
--
--    202608040023's two sentences are kept word for word and in their order:
--    who may close this seva is still asked before anything else, so a devotee
--    with no authority learns nothing about the temple's schedule from the
--    refusal they get. The clock is asked next, before the write, so a poster
--    with every right to close their seva is told plainly why not yet.
--
--    Same argument list, same grants, same behaviour for every seva whose hour
--    has gone.
-- ---------------------------------------------------------------------------

create or replace function public.complete_service_instance(p_instance_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  instance_record public.service_instances;
begin
  select * into instance_record
  from public.service_instances
  where id = p_instance_id
  for update;

  if instance_record.id is null then
    raise exception 'This seva request could not be found.';
  end if;

  -- Confirming that a seva actually happened belongs to whoever asked for it,
  -- and to the two levels that can override anything. A Community Head holds
  -- services.complete_requirement for the seva they run, but that is no longer
  -- enough to close somebody else's request.
  if instance_record.posted_by is distinct from auth.uid()
    and not public.has_permission('app.view_all')
  then
    raise exception 'Only the devotee who posted this seva request, a Tech Admin, or the President can mark it completed.';
  end if;

  -- Sentence 3. Plain enough to put in front of a devotee, and it says when.
  if public.seva_completion_opens_at(
       instance_record.date, instance_record.start_time) > now()
  then
    raise exception
      'This seva has not started yet. You can mark it completed once its time on % has passed.',
      public.format_seva_when(instance_record.date, instance_record.start_time);
  end if;

  if not public.complete_service_instance_internal(p_instance_id, auth.uid(), false) then
    raise exception 'This seva can no longer be completed.';
  end if;
end;
$$;

revoke all on function public.complete_service_instance(uuid) from public, anon;
grant execute on function public.complete_service_instance(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Sentence 2, in the body both the poster's button and the hourly sweep run.
--
--    202608040065's two UPDATEs are unchanged and in their order, and the
--    reconcile sits after them and before the early return for p_auto, so the
--    sweep obeys the rule on the same line the President does. There is one
--    dialect of 'completed' and this file does not add a second.
--
--    THE NOTIFICATION IS THE OTHER HALF OF THE HONESTY. 202608040023 tells the
--    participants and oversight that somebody "marked this completed". If the
--    seva has just been settled as one nobody served, that sentence is false,
--    and the participants have in any case already been told they were marked
--    absent by record_seva_attendance. So the per-participant notices are not
--    sent, and oversight is told what actually happened instead.
--
--    THE SWEEP CANNOT REACH THIS ARM TODAY and it is written for anyway.
--    due_recurring_service_instances selects only instances holding at least
--    one assignment with no attendance recorded, and such a place is never
--    'not_served', so a sweep completion always has a server. That is two
--    migrations' selection rules agreeing, not a guarantee; if 0065's view is
--    ever loosened the rule is already here, and section 10's verification
--    proves the sweep obeys it either way.
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
  'The two UPDATEs that close a seva, followed by 202608040068''s question of whether anybody served it, with no authority check of its own. Never granted to a client role: reach it through complete_service_instance, which is 202608040023''s permission rule and 202608040068''s clock, or through complete_due_recurring_service_instances, which is the clock on its own.';

revoke all on function public.complete_service_instance_internal(uuid, uuid, boolean)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 6. The devotee's own button, which can close the whole seva by itself.
--
--    202608040019 section 2 gave this the clock gate the poster's button never
--    had, and its sentence is kept word for word — only the boundary it reads
--    moves from a hard-coded start to section 1's dial, so the two buttons open
--    at the same instant however the temple sets it.
--
--    The reconcile is placed after the count that flips the instance, because
--    that flip is a completion like any other: four devotees on a seva, all
--    four marked absent by a coordinator, the last of them completing their own
--    place would otherwise put the instance in the completed list.
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

  -- Seva cannot be reported finished before it has begun.
  if public.seva_completion_opens_at(
       instance_record.date, instance_record.start_time) > now()
  then
    raise exception 'You can mark this seva completed once it has started.';
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
-- 7. The mark that causes it, and the correction that undoes it.
--
--    This is where the temple's row actually comes from: the seva was completed
--    on the day, and the absence was recorded afterwards. 202608040027's body
--    is unchanged — the same authority, the same clock gate, the same wording
--    of the notice to the devotee — with one call added at the end.
--
--    Both directions. Marking the last server absent takes the seva out of the
--    completed list; correcting that mark to 'served' puts it back, along with
--    the devotee's points, because the reconciler holds the row it closed.
-- ---------------------------------------------------------------------------

create or replace function public.record_seva_attendance(
  p_assignment_id uuid,
  p_attendance text
)
returns public.service_assignments
language plpgsql
security definer
set search_path = ''
as $$
declare
  assignment_record public.service_assignments;
  instance_record public.service_instances;
  updated_assignment public.service_assignments;
  actor_name text;
begin
  if p_attendance is not null
    and p_attendance not in ('served', 'absent', 'excused')
  then
    raise exception 'Attendance is served, absent, or excused.';
  end if;

  select * into assignment_record from public.service_assignments
  where id = p_assignment_id for update;
  if assignment_record.id is null then
    raise exception 'This seva place could not be found.';
  end if;

  select * into instance_record from public.service_instances
  where id = assignment_record.service_instance_id;

  -- The same authority that closes a seva says who was there for it.
  if instance_record.posted_by is distinct from auth.uid()
    and not public.has_permission('app.view_all')
  then
    raise exception 'Only the devotee who posted this seva, a Tech Admin, or the President can record attendance.';
  end if;

  if ((instance_record.date + instance_record.start_time)
      at time zone 'America/Chicago') > now() then
    raise exception 'Attendance can be recorded once the seva has started.';
  end if;

  update public.service_assignments
  set attendance = p_attendance
  where id = p_assignment_id
  returning * into updated_assignment;

  select name into actor_name from public.users where id = auth.uid();

  -- Being marked absent is worth knowing about; being marked present is not.
  if p_attendance = 'absent' and assignment_record.devotee_id <> auth.uid() then
    perform public.queue_app_notification(
      assignment_record.devotee_id, 'service_left',
      'Marked as not attending',
      actor_name || ' recorded that you were not able to attend "'
        || public.service_instance_name(instance_record) || '" on '
        || public.format_seva_when(instance_record.date, instance_record.start_time)
        || '. Tell them if that is wrong.',
      jsonb_build_object('serviceInstanceId', instance_record.id)
    );
  end if;

  -- Sentence 2. One word from a coordinator can be the last word on whether
  -- this seva happened at all, in either direction.
  perform public.reconcile_service_instance_completion(instance_record.id);

  return updated_assignment;
end;
$$;

revoke all on function public.record_seva_attendance(uuid, text) from public, anon;
grant execute on function public.record_seva_attendance(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 8. The fourth writer of 'completed', which nobody presses.
--
--    202608040020 section 1's reconciler moves a verified seva from 'closed' to
--    'completed' once its end time passes. A devotee verified for a seva they
--    were then marked absent from would be completed by it, hours later, with
--    nobody watching. Its body, its return value and its argument list are
--    unchanged; the moved instances are collected so each can be settled.
-- ---------------------------------------------------------------------------

create or replace function public.settle_finished_verified_seva()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  moved uuid[];
  moved_instance uuid;
begin
  with due as (
    select verifications.id as verification_id,
           verifications.service_instance_id,
           verifications.devotee_id,
           verifications.end_at
    from public.service_verifications verifications
    join public.service_instances instances
      on instances.id = verifications.service_instance_id
    where verifications.status = 'verified'
      and verifications.end_at <= now()
      and instances.status = 'closed'
  ), moved_assignments as (
    update public.service_assignments assignments
    set status = 'completed',
        completed_at = coalesce(assignments.completed_at, due.end_at)
    from due
    where assignments.service_instance_id = due.service_instance_id
      and assignments.devotee_id = due.devotee_id
      and assignments.status in ('assigned', 'confirmed')
    returning assignments.id
  ), moved_instances as (
    update public.service_instances instances
    set status = 'completed'
    from due
    where instances.id = due.service_instance_id
    returning instances.id
  )
  select coalesce(array_agg(moved_instances.id), '{}'::uuid[])
  into moved
  from moved_instances;

  foreach moved_instance in array moved loop
    perform public.reconcile_service_instance_completion(moved_instance);
  end loop;

  return coalesce(array_length(moved, 1), 0);
end;
$$;

revoke all on function public.settle_finished_verified_seva() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 9. So that nothing vanishes silently.
--
--    A cancelled instance is invisible in every list the app builds, which is
--    what "removed from the list" means and is also the one way this change
--    could hurt. This is the list of seva that were closed because nobody
--    served them, with every place on each and what was said about it, for the
--    same three people who could have closed the seva in the first place: its
--    poster, the Tech Admin and the President. A recurring slot carries no
--    poster, so those are visible to app.view_all only — the same rule
--    list_seva_awaiting_confirmation already applies for the same reason.
-- ---------------------------------------------------------------------------

create or replace function public.list_seva_closed_unserved(
  p_from date default null,
  p_to date default null
)
returns table (
  service_instance_id uuid,
  seva_name text,
  occurred_on date,
  weekday text,
  started_at_local time,
  planned_minutes integer,
  is_recurring boolean,
  posted_by uuid,
  closed_at timestamptz,
  devotee_id uuid,
  devotee_name text,
  assignment_status text,
  attendance text,
  points_status text
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    instances.id,
    public.service_instance_name(instances),
    instances.date,
    trim(to_char(instances.date, 'FMDay')),
    instances.start_time,
    instances.duration_minutes,
    instances.template_id is not null,
    instances.posted_by,
    unserved.closed_at,
    assignments.devotee_id,
    users.name,
    assignments.status,
    assignments.attendance,
    public.seva_points_status(
      assignments.status, assignments.attendance, assignments.verification,
      instances.template_id is not null)
  from public.service_instances_unserved unserved
  join public.service_instances instances
    on instances.id = unserved.service_instance_id
  join public.service_assignments assignments
    on assignments.service_instance_id = instances.id
  join public.users on users.id = assignments.devotee_id
  where auth.uid() is not null
    and instances.status = 'cancelled'
    and instances.date
        between coalesce(p_from, public.seva_mala_today() - 89)
            and coalesce(p_to, public.seva_mala_today())
    and (
      instances.posted_by = auth.uid()
      or public.has_permission('app.view_all')
    )
  order by instances.date desc, instances.start_time desc, users.name
$$;

comment on function public.list_seva_closed_unserved(date, date) is
  'Seva that was taken out of the completed list because everybody on it was marked absent or excused, with every place and what was said about it. For the poster, the Tech Admin and the President, so that "removed from the list" is not the same as "gone".';

revoke all on function public.list_seva_closed_unserved(date, date) from public, anon;
grant execute on function public.list_seva_closed_unserved(date, date) to authenticated;

-- ---------------------------------------------------------------------------
-- 10. The data that is already wrong.
--
--     TWO KINDS OF WRONG ROW EXIST ON THE TEMPLE'S OWN DATABASE, and this file
--     corrects one of them and refuses to correct the other.
--
--     CORRECTED: a seva at 'completed' with places on it and every place
--     'not_served'. That row is a false statement with no ambiguity about what
--     the truth is, and settling it changes nobody's points by a minute —
--     every act on it is already worth zero under sentence 1, so removing it
--     from seva_mala_acts moves no total and no frozen period. It is also
--     reversible in one attendance correction, because the reconciler records
--     what it closed. One such row exists on the copy this file was written
--     against: Temple Room Cleaning, 11 August, one devotee, marked absent.
--
--     NOT CORRECTED: a seva at 'completed' whose start has not passed. The
--     truth about those is not knowable from here — the honest previous status
--     is 'open' or 'full' depending on a capacity rule, and the assignments
--     were moved to 'completed' too — and un-completing somebody's seva without
--     being asked is exactly the kind of quiet change this file is written
--     against. The three on the copy this file was written against are all on
--     the same evening within hours of their start, at which point they are
--     simply true. Section 4 stops any more being made; these are counted and
--     named in a notice so that whoever wants them reopened can say so.
-- ---------------------------------------------------------------------------

do $$
declare
  v_instance uuid;
  v_corrected integer := 0;
  v_future integer := 0;
begin
  for v_instance in
    select instances.id
    from public.service_instances instances
    where instances.status = 'completed'
      and exists (
        select 1 from public.service_assignments assignments
        where assignments.service_instance_id = instances.id
      )
      and not public.service_instance_has_server(instances.id)
    order by instances.date
  loop
    if public.reconcile_service_instance_completion(v_instance) = 'cancelled' then
      v_corrected := v_corrected + 1;
    end if;
  end loop;

  select count(*) into v_future
  from public.service_instances instances
  where instances.status = 'completed'
    and public.seva_completion_opens_at(instances.date, instances.start_time) > now();

  raise notice
    'completion truthfulness: % seva nobody served taken out of the completed list; % seva completed before their time left alone for a person to decide about.',
    v_corrected, v_future;
end;
$$;

-- ---------------------------------------------------------------------------
-- 11. What this file is not allowed to have become.
--
--     Every guard above is a refusal, and a refusal is the easiest thing in a
--     schema to lose to a later `create or replace`. These are the three that
--     would take the temple's complaint back without anybody noticing.
-- ---------------------------------------------------------------------------

do $$
begin
  -- The clock is on the front door, and it is the temple's clock.
  if pg_get_functiondef('public.complete_service_instance(uuid)'::regprocedure)
     !~* 'seva_completion_opens_at' then
    raise exception 'complete_service_instance has lost its clock; sentence 3 is unenforced.';
  end if;

  -- Sentence 2 is on the shared body, so the hourly sweep obeys it too.
  if pg_get_functiondef('public.complete_service_instance_internal(uuid, uuid, boolean)'::regprocedure)
     !~* 'reconcile_service_instance_completion' then
    raise exception
      'complete_service_instance_internal no longer asks whether anybody served the seva, so 202608040065''s sweep does not either.';
  end if;

  -- And the mark that causes it settles it.
  if pg_get_functiondef('public.record_seva_attendance(uuid, text)'::regprocedure)
     !~* 'reconcile_service_instance_completion' then
    raise exception
      'record_seva_attendance no longer settles the seva, so marking the last server absent leaves it in the completed list.';
  end if;

  -- The sweep's own selection still excludes what this file closes, so a
  -- cancelled-as-unserved slot cannot be re-closed on the hour.
  if pg_get_viewdef('public.due_recurring_service_instances'::regclass)
     !~* 'cancelled' then
    raise exception
      'due_recurring_service_instances no longer excludes cancelled instances; the sweep would resurrect every seva nobody served.';
  end if;

  -- Nothing here writes a status outside 202608020002's vocabulary.
  if pg_get_functiondef('public.reconcile_service_instance_completion(uuid)'::regprocedure)
     ~* $bad$status = '(open|full|closed)'$bad$ then
    raise exception 'The reconciler has learned a status the rest of the system does not read.';
  end if;
end;
$$;

do $$
begin
  raise notice 'completion truthfulness applied';
end;
$$;
