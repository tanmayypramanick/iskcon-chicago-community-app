-- Weekly seva that closes itself when its hour in Chicago has gone by.
--
-- "Weekly seva which is done — by the time zone it will already be completed,
--  so it will be completed automatically. Why is it waiting?"
--
-- They are describing a queue that should not exist. 202608040059 made a
-- recurring act earn its points the moment its assignment is 'completed', with
-- no verification level and no attendance mark required, precisely because a
-- recurring instance carries posted_by null and 202608040027 leaves the
-- President and the Tech Admin as the only two people in the temple who could
-- confirm one. What 0059 did NOT do is close the instance. So a Tuesday
-- kitchen slot whose Tuesday finished at noon sits at 'open' with its
-- assignments at 'confirmed', reads awaiting_completion in
-- list_seva_awaiting_confirmation, and waits for one of those same two people
-- to press a button that says what the clock already said.
--
-- This file makes the clock press it.
--
-- ---------------------------------------------------------------------------
-- 1. WHY A NEW SWEEP RATHER THAN AN EXTENSION OF THE EXISTING ONE.
--
--    202608030008 already has complete_due_service_sessions() on a
--    minute-by-minute pg_cron job named 'complete-due-seva-sessions'. It was
--    the obvious thing to extend, and it is the wrong thing to extend, for two
--    reasons that are worth writing down rather than discovering twice.
--
--    a. IT IS ABOUT A DIFFERENT OBJECT. It sweeps public.service_qr_sessions —
--       live timers a devotee started and never stopped — and finalises each
--       one through finalize_service_session_internal, which CREATES a
--       service_instance to record the timer that ran. Nothing it touches is a
--       roster slot. Its return value is a count of timers. Folding a second,
--       differently-shaped sweep into it would give one function two subjects
--       and one number two meanings.
--
--    b. IT CANNOT RUN FROM CRON AS IT STANDS. 202608040010 §3 added
--
--          if auth.uid() is null then raise exception 'Authentication is
--          required.'; end if;
--
--       to the front of it, and pg_cron runs as postgres with no JWT, so
--       auth.uid() is null and the scheduled call raises every minute.
--       202608040020 §11 then revoked its execute from authenticated, and
--       0013/0018 retired the RPCs that used to call it in-request. The job is
--       therefore dead: it is scheduled, it fires, and it throws. Hanging the
--       temple's points on that would have hidden this migration's failure
--       inside an existing one's.
--
--       THAT IS REPORTED, NOT REPAIRED HERE. complete_due_service_sessions
--       belongs to the live-timer feature and fixing its auth model is that
--       feature's call, not this one's. Section 5 below simply does not make
--       the same mistake: the new sweep has no auth.uid() requirement at all
--       and is granted to service_role rather than to any client role.
--
--    What IS reused, and reused rather than re-typed, is the write itself.
--    Section 3 lifts the body of complete_service_instance into
--    complete_service_instance_internal and leaves the public function as the
--    authority check in front of it — exactly the shape 202608030008 already
--    uses for finalize_service_session_internal(p_session_id, p_auto). An
--    auto-completion and a President's completion now run the same two UPDATE
--    statements in the same order, so there is one dialect of 'completed' and
--    not two.
--
--    The order of those two statements is 202608040023's and is preserved: the
--    instance goes to 'completed' first, and its `where status not in
--    ('completed', 'cancelled')` is the ONLY guard either statement has.
--    Swapping them is, as it happens, unobservable TODAY — both callers either
--    raise on the false return, which rolls the statement back, or can never
--    reach it, and the mutation test below records that honestly rather than
--    pretending to kill it. It stays in this order anyway, because the next
--    caller to be written may want to treat "already completed" as a
--    non-event, and with the statements swapped that caller would silently
--    close a devotee's assignment on a slot that was cancelled.
--
-- ---------------------------------------------------------------------------
-- 2. WHEN A SLOT IS DUE.
--
--        (date + start_time) at time zone 'America/Chicago'
--          + duration_minutes
--          + grace                                          <= now()
--
--    Chicago and only Chicago, which is the temple's whole point and is how
--    202608040027 already decides that a seva has started. The conversion runs
--    on the stored local wall-clock date and time, so it is right through both
--    daylight-saving shifts and it does not move when the caller's session is
--    in Asia/Kolkata. An eight-o'clock Sunday morning slot in Chicago is due at
--    the same instant for a devotee reading the app in Mayapur as for the
--    office, and never one minute before.
--
--    THE GRACE IS SIXTY MINUTES, and it is a dial rather than a constant.
--    Sixty because:
--
--      * The slot's own duration_minutes is the temple's declaration of how
--        long the seva takes, set on the template by a Community Head or above.
--        An hour past a length the temple itself chose is generous, and the
--        grace exists to cover a seva that ran over, not to re-litigate the
--        length.
--      * It keeps the temple's sentence true. A Sunday kitchen slot that ends
--        at noon is counted on Sunday, which is what "by the time zone it will
--        already be completed" means. A grace measured in days would put weekly
--        seva back in a queue, just a slower one.
--      * It is not the safety net, so it does not have to be long. Marking a
--        devotee absent still zeroes the act AFTER completion —
--        record_seva_attendance is not gated on the instance being open, only
--        on its having started — so a coordinator's correction has as long as
--        the Seva Mala period stays open, not one hour. Section 7 sets out
--        exactly how far that goes and where it stops.
--
--    THE LOOKBACK IS NINETY DAYS, and this one matters more than it looks.
--    Without it the first run of this sweep on the live database would close
--    every recurring slot ever generated and never closed, and the nightly
--    recompute would then award points for all of them at once. Ninety days is
--    list_seva_awaiting_confirmation's own default window — it is literally the
--    queue the temple is looking at and asking about — and it is
--    seva_mala.trailing_days, the window every congregation-relative reference
--    is already computed over. Anything older than that is in nobody's queue
--    and behind every reference, and quietly resurrecting it is not what was
--    asked for.
--
-- ---------------------------------------------------------------------------
-- 3. WHAT IS NEVER TOUCHED.
--
--    ONE-OFF SEVA. template_id is not null, full stop. A one-off seva has a
--    poster who asked for it, that poster can close it, and 202608040057's
--    stricter rule — completed AND verified AND served — still governs whether
--    it earns. Nothing here reaches it.
--
--    A CANCELLED INSTANCE. Stays cancelled. The guard is the same
--    `status not in ('completed', 'cancelled')` the human path has always used,
--    and it is in the shared internal so the two cannot drift.
--
--    A DECISION SOMEBODY ALREADY MADE. Auto-completion fills a silence. An
--    assignment at 'no_show' or 'withdrawn' is skipped, as it is on the human
--    path. An assignment with ANY attendance recorded — served, absent or
--    excused — is skipped too, and that is stricter than the human path on
--    purpose: attendance is the one column in this system that outranks the
--    roster, and a row a coordinator has already looked at is not a silence to
--    fill. A coordinator who marked a devotee 'served' but did not close the
--    slot is still holding that slot open, and the sweep leaves it to them.
--
--    A SLOT NOBODY STOOD IN. The sweep only considers an instance that has at
--    least one assignment at 'assigned' or 'confirmed' with no attendance
--    recorded — which is to say, at least one row it would actually change,
--    which is to say exactly the rows list_seva_awaiting_confirmation is
--    showing. A past recurring slot with no takers keeps its status, because
--    'completed' would be a claim that it happened.
--
--    IDEMPOTENCE falls out of that rather than being bolted on. The instance
--    UPDATE is `where status not in ('completed', 'cancelled')`; the second run
--    matches no rows, returns false, and never reaches the assignments. And the
--    selection itself no longer matches the instance, because none of its
--    assignments are 'assigned' or 'confirmed' any more.
--
-- ---------------------------------------------------------------------------
-- 4. THE ABUSE SURFACE, RE-EXAMINED RATHER THAN RE-ASSERTED.
--
--    0059 accepted that a devotee on a weekly roster earns points by closing
--    their own slot, and bounded it four ways. Automatic completion removes the
--    devotee's action from that sentence entirely — now nobody acts at all —
--    so each bound has to be checked again against silence rather than against
--    a self-close.
--
--      THE ROSTER IS STILL THE GATE, and it is now the ONLY gate, which is the
--      one thing that genuinely changes. service_templates and
--      service_template_assignees are select-only to authenticated
--      (202608020003); every write goes through a definer RPC; a devotee can
--      add themselves only via join_weekly_service, only while the template is
--      participation_mode 'open', and only into a free slot. That is unchanged
--      and it still holds. What changes is that being on the roster is now
--      sufficient rather than merely necessary — before this file a rostered
--      devotee still had to press something. So the standing of the roster
--      matters more than it did, and leaving somebody on a template they no
--      longer serve now costs the temple points rather than nothing. That is a
--      real change and it is the price of the feature the temple asked for.
--
--      THE HOURS ARE STILL THE TEMPLE'S. A recurring instance takes its
--      duration_minutes from the template, and seva_mala_acts credits
--      least(planned, coalesce(actual, planned)). An auto-completed slot has no
--      session and no verification, so actual is null and the credit is exactly
--      the slot's own length. Auto-completion cannot inflate an act by a
--      minute; it is arithmetically incapable of it.
--
--      THE CAPS STILL BIND, and they bind on the same numbers. 480 minutes a
--      Chicago day, 1800 a Chicago week, applied in seva_mala_acts to
--      cap_basis, which counts only acts whose quality is above zero.
--      Auto-completed acts are ordinary counted acts, so they spend the cap
--      like any other. 202608040062's soft cap and 0055's references are
--      congregation-relative, so a congregation where everybody's roster
--      auto-completes raises the reference for everybody and nobody gains
--      standing from it. The board measures distance from the congregation, and
--      moving the whole congregation moves nothing.
--
--      THE COORDINATOR'S UNDO STILL WORKS, WITH ONE NEW EDGE.
--      record_seva_attendance refuses only until the seva has STARTED; it does
--      not care whether the instance is completed. So marking 'absent' after an
--      auto-completion still flips the act to not_served and still notifies the
--      devotee in words. What is new is that the correction is now retroactive
--      rather than pre-emptive: before this file the points had not landed yet,
--      and now they have. Inside an open Seva Mala period that is invisible —
--      the nightly recompute rebuilds week, month and lifetime from the acts —
--      but a period that has already been FROZEN is never recomputed, so an
--      absence recorded after its period froze corrects the lifetime board and
--      not that week's. The grace period does not fix this and is not meant to;
--      what fixes it is that the temple now has a whole open period to notice,
--      instead of an instance nobody was looking at. Section 6's daily digest
--      exists so that somebody is looking.
--
--    AND ONE BOUND THAT IS NEW HERE: the sweep is not reachable by any client
--    role. It is revoked from public, anon and authenticated and granted only
--    to service_role, so no devotee can make the temple's database run a
--    hundred completions on demand, and no devotee can hurry their own slot
--    over the line — the clock decides, and only the backend asks the clock.
--
-- Requires 202608040064_board_access_and_beta.sql.

-- ---------------------------------------------------------------------------
-- 0. The ground this stands on.
--
--    Asserted rather than assumed. This file re-defines a function three other
--    migrations have already re-defined, and it depends on 0059's recurring
--    rule being the thing that turns a completed roster slot into points. If
--    either has moved, the sweep below means something other than what its
--    header says.
-- ---------------------------------------------------------------------------

do $$
begin
  if to_regprocedure('public.complete_service_instance(uuid)') is null
    or to_regprocedure('public.seva_points_status(text, text, text, boolean)') is null
    or to_regprocedure('public.notify_service_oversight(text, text, text, jsonb, uuid)') is null
    or to_regprocedure('public.queue_app_notification(uuid, text, text, text, jsonb)') is null
    or to_regprocedure('public.app_setting(text)') is null
    or to_regprocedure('public.has_permission(text)') is null
  then
    raise exception
      'The seva completion path is not in place; apply 202608030008, 202608040023 and 202608040059 first.';
  end if;

  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'service_instances'
      and column_name = 'template_id'
  ) then
    raise exception
      'public.service_instances has no template_id; there is nothing to call recurring.';
  end if;

  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'service_assignments'
      and column_name = 'attendance'
  ) then
    raise exception
      'public.service_assignments has no attendance; the coordinator''s decision cannot be respected.';
  end if;

  -- 0059's rule, which is the only reason completing an instance is worth
  -- anything. A completed recurring act counts with nothing else recorded; an
  -- unclosed one does not; and a decision already made still zeroes it.
  if public.seva_points_status('completed', null, 'self_report', true) <> 'counted'
    or public.seva_points_status('confirmed', null, 'self_report', true) <> 'awaiting_completion'
    or public.seva_points_status('completed', 'absent', 'self_report', true) <> 'not_served'
    or public.seva_points_status('completed', 'excused', 'self_report', true) <> 'not_served'
    or public.seva_points_status('no_show', null, 'self_report', true) <> 'not_served'
    or public.seva_points_status('withdrawn', null, 'self_report', true) <> 'not_served'
  then
    raise exception
      '202608040059''s recurring rule has moved; completing a weekly instance no longer means what this migration assumes.';
  end if;

  -- And one-off seva is still 0057's, which is why section 5 refuses to touch
  -- an instance with no template.
  if public.seva_points_status('completed', null, 'self_report', false) <> 'awaiting_verification'
    or public.seva_points_status('completed', 'served', 'member_verified', false) <> 'counted'
  then
    raise exception
      '202608040057''s one-off rule has moved.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 1. Three dials, so the temple can change its mind without a migration.
--
--    Held in app_settings beside the Seva Mala dials, read through
--    202608040026's app_setting(), and seeded ON CONFLICT DO NOTHING so
--    re-applying this file never stamps on a value the temple has since
--    changed.
--
--      seva.auto_complete_recurring       true / false. false stops the sweep
--                                         dead and puts weekly seva back
--                                         exactly where 0059 left it: waiting
--                                         for app.view_all. Nothing else in
--                                         the system changes.
--      seva.auto_complete_grace_minutes   whole minutes past the slot's own end
--                                         before it is closed. 0 to 1440.
--      seva.auto_complete_lookback_days   how far back a first run may reach.
--                                         1 to 3650.
--
--    A malformed value RAISES rather than falling back to the default, which
--    is 202608040055's rule for a dial and is the right one: a constant that
--    quietly reverts is a bug nobody finds. The sweep runs unattended, so the
--    only place that raise can be seen is the cron log — which is better than
--    the alternative, where a fat-fingered '6O' silently reinstates a
--    sixty-minute grace nobody chose.
-- ---------------------------------------------------------------------------

insert into public.app_settings (key, value)
values
  ('seva.auto_complete_recurring', 'true'),
  ('seva.auto_complete_grace_minutes', '60'),
  ('seva.auto_complete_lookback_days', '90')
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------
-- 2. The write, lifted out of the authority that used to wrap it.
--
--    This is 202608040023's body verbatim below the permission check, with two
--    parameters where it used to read auth.uid() directly. p_auto is the same
--    flag finalize_service_session_internal already carries, and it does two
--    things: it holds the assignment update off any row where a coordinator has
--    recorded attendance, and it suppresses the per-instance notifications,
--    because a sweep is not a person and "Sevak Das marked this completed" is
--    not true of the clock.
--
--    Returns whether it completed anything, so the caller can tell "already
--    completed" from "just completed" without a second query. The human wrapper
--    turns false into 202608040023's exception; the sweep just does not count
--    it.
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

  if coalesce(p_auto, false) then
    return true;
  end if;

  select * into instance_record from public.service_instances where id = p_instance_id;
  select name into actor_name from public.users where id = p_actor_id;

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
  'The two UPDATEs that close a seva, with no authority check of its own. Never granted to a client role: reach it through complete_service_instance, which is 202608040023''s permission rule, or through complete_due_recurring_service_instances, which is the clock.';

revoke all on function public.complete_service_instance_internal(uuid, uuid, boolean)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. 202608040023's function, now only its authority.
--
--    Same signature, same grants, same two exception messages word for word,
--    same rule about who may. The only change is that the write it performs is
--    the write the sweep performs, which is the entire point of section 2.
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

  if not public.complete_service_instance_internal(p_instance_id, auth.uid(), false) then
    raise exception 'This seva can no longer be completed.';
  end if;
end;
$$;

revoke all on function public.complete_service_instance(uuid) from public, anon;
grant execute on function public.complete_service_instance(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Which recurring slots the clock has already closed.
--
--    A view rather than a subquery inside the sweep, because it is the thing
--    the verification wants to look at, the thing an operator wants to look at
--    before turning the job on, and the thing a mutation test can point at. It
--    is a plain view over two tables that are already select-only to
--    authenticated under their own RLS, and it adds no column those policies do
--    not already expose.
--
--    Every clause is one of the rules in the header:
--
--      template_id is not null            recurring only; one-off keeps 0057
--      status not in (completed,cancelled) a decision, and idempotence
--      due_at <= now()                    Chicago wall clock plus the grace
--      date >= today - lookback           the first run is not a resurrection
--      exists (a silent assignment)       something it would actually change
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
    ((instances.date + instances.start_time) at time zone 'America/Chicago')
      + make_interval(mins => instances.duration_minutes)
      + make_interval(mins => (
          coalesce(
            nullif(trim(public.app_setting('seva.auto_complete_grace_minutes')), ''),
            '60'
          )::integer
        )) as due_at
  from public.service_instances instances
  where instances.template_id is not null
    and instances.status not in ('completed', 'cancelled')
    and instances.date >= (now() at time zone 'America/Chicago')::date
        - coalesce(
            nullif(trim(public.app_setting('seva.auto_complete_lookback_days')), ''),
            '90'
          )::integer
    and ((instances.date + instances.start_time) at time zone 'America/Chicago')
        + make_interval(mins => instances.duration_minutes)
        + make_interval(mins => (
            coalesce(
              nullif(trim(public.app_setting('seva.auto_complete_grace_minutes')), ''),
              '60'
            )::integer
          )) <= now()
    and exists (
      select 1 from public.service_assignments assignments
      where assignments.service_instance_id = instances.id
        and assignments.status in ('assigned', 'confirmed')
        and assignments.attendance is null
    );

comment on view public.due_recurring_service_instances is
  'Recurring seva slots whose Chicago hour, plus the configured grace, has gone by, and which still hold at least one assignment nobody has spoken about. What the sweep is about to close.';

revoke all on public.due_recurring_service_instances from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 5. The sweep.
--
--    Backend only: no auth.uid() check, because pg_cron has no JWT and a
--    function that demands one is the dead job section 1b describes; and no
--    grant to any client role, because the clock is not something a devotee
--    should be able to hurry.
--
--    `for update skip locked` on the instance rows so two overlapping runs — a
--    slow one and the next hour's — divide the work instead of blocking on it,
--    which is 202608030008's own pattern.
-- ---------------------------------------------------------------------------

create or replace function public.complete_due_recurring_service_instances()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_switch text;
  v_grace_raw text;
  v_lookback_raw text;
  v_grace integer;
  v_lookback integer;
  v_due record;
  v_completed integer := 0;
begin
  v_switch := lower(coalesce(nullif(trim(public.app_setting('seva.auto_complete_recurring')), ''), 'true'));
  if v_switch not in ('true', 'false') then
    raise exception
      'seva.auto_complete_recurring is "%", which is neither true nor false.', v_switch;
  end if;
  if v_switch = 'false' then
    return 0;
  end if;

  -- Read and validated here as well as in the view, so a malformed dial is a
  -- named error from the job rather than a cast failure from a view somebody
  -- has to go and read.
  v_grace_raw := coalesce(nullif(trim(public.app_setting('seva.auto_complete_grace_minutes')), ''), '60');
  begin
    v_grace := v_grace_raw::integer;
  exception when others then
    raise exception
      'seva.auto_complete_grace_minutes is "%", which is not a whole number of minutes.', v_grace_raw;
  end;
  if v_grace < 0 or v_grace > 1440 then
    raise exception
      'seva.auto_complete_grace_minutes is %, which is outside 0 to 1440.', v_grace;
  end if;

  v_lookback_raw := coalesce(nullif(trim(public.app_setting('seva.auto_complete_lookback_days')), ''), '90');
  begin
    v_lookback := v_lookback_raw::integer;
  exception when others then
    raise exception
      'seva.auto_complete_lookback_days is "%", which is not a whole number of days.', v_lookback_raw;
  end;
  if v_lookback < 1 or v_lookback > 3650 then
    raise exception
      'seva.auto_complete_lookback_days is %, which is outside 1 to 3650.', v_lookback;
  end if;

  for v_due in
    select instances.id as service_instance_id
    from public.service_instances instances
    where instances.id in (
      select due.service_instance_id from public.due_recurring_service_instances due
    )
    order by instances.date, instances.start_time
    for update skip locked
  loop
    if public.complete_service_instance_internal(v_due.service_instance_id, null, true) then
      v_completed := v_completed + 1;
    end if;
  end loop;

  -- One digest a Chicago day, and only when there was something to say. Not one
  -- notification per instance: a congregation with six weekly rotas would send
  -- the President forty messages a week saying that a clock had struck. The
  -- digest exists because the coordinator's undo — record_seva_attendance
  -- 'absent' — is only a real bound if somebody knows there is something to
  -- undo, and because a period freezes eventually (section 4 of the header).
  if v_completed > 0 and not exists (
    select 1 from public.app_notifications
    where app_notifications.kind = 'service_completed'
      and coalesce((app_notifications.data ->> 'autoCompleted')::boolean, false)
      and (app_notifications.created_at at time zone 'America/Chicago')::date
          = (now() at time zone 'America/Chicago')::date
  ) then
    perform public.notify_service_oversight(
      'service_completed',
      'Weekly seva completed automatically',
      v_completed::text || ' weekly seva ' ||
      case when v_completed = 1 then 'slot whose time had passed was' else 'slots whose time had passed were' end
      || ' closed automatically. Anyone who did not attend can still be marked absent.',
      jsonb_build_object('autoCompleted', true, 'autoCompletedCount', v_completed),
      null
    );
  end if;

  return v_completed;
end;
$$;

comment on function public.complete_due_recurring_service_instances() is
  'Closes recurring seva slots whose Chicago hour has gone by, so 202608040059''s rule can award their points without a President pressing a button per slot. Only recurring, never cancelled, never a row a coordinator has already spoken about, and idempotent. Backend only.';

revoke all on function public.complete_due_recurring_service_instances()
  from public, anon, authenticated;
grant execute on function public.complete_due_recurring_service_instances() to service_role;

-- ---------------------------------------------------------------------------
-- 6. The schedule.
--
--    Hourly at twenty past, guarded on pg_available_extensions exactly the way
--    202608030008 and 202608040055 guard theirs, so this file still applies to
--    a plain Postgres with no pg_cron — where nothing auto-completes and weekly
--    seva waits for app.view_all, which is 0059's behaviour unchanged.
--
--    Hourly rather than by the minute because the boundary this job watches
--    moves in units of a slot, not a second: with a sixty-minute grace the
--    worst case a devotee sees is their points landing about two hours after
--    their slot ended, on the same Chicago day, which is what was asked for.
--    A minute-by-minute job would run 1,440 times a day to find nothing 1,430
--    of them.
--
--    Scheduled under `where not exists` so re-applying never duplicates the
--    job, and wrapped so a project without cron privileges gets a notice rather
--    than a failed migration.
-- ---------------------------------------------------------------------------

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    execute 'create extension if not exists pg_cron with schema extensions';
    if exists (select 1 from pg_extension where extname = 'pg_cron') then
      execute $cron$
        select cron.schedule(
          'complete-due-recurring-seva',
          '20 * * * *',
          'select public.complete_due_recurring_service_instances();'
        )
        where not exists (
          select 1 from cron.job where jobname = 'complete-due-recurring-seva'
        )
      $cron$;
    end if;
  end if;
exception when others then
  raise notice 'Enable Supabase Cron so weekly seva closes itself; until then it waits for the President.';
end;
$$;

do $$
begin
  raise notice 'recurring autocomplete applied';
end;
$$;
