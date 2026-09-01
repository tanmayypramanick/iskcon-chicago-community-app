-- "Mark served" answers only the places nobody has answered yet.
-- Requires 202608040068_completion_truthfulness.sql.
--
-- The waiting list's one-tap "Mark served" looped in the client over ids taken
-- from the dashboard SNAPSHOT it was handed, calling record_seva_attendance
-- for each. Two things went wrong with that.
--
--   * record_seva_attendance overwrites attendance unconditionally, and the
--     snapshot can be up to thirty seconds old. Coordinator A marks Bhakta X
--     absent at 10:02; coordinator B's list still shows X unanswered; B taps
--     "Mark served" and X is flipped back to served and earns the points. The
--     temple's own record of an absence is overwritten by a stale screen.
--   * The loop is not atomic. A failure on the third of four places leaves the
--     first two written while onError restores the pre-mutation cache showing
--     none of them, so the screen and the database disagree and nothing
--     reconciles them until a refetch.
--
-- One statement, decided server-side against the live rows, fixes both. A
-- place that somebody has already answered — served, absent or excused — is
-- left exactly as they left it.

create or replace function public.record_unanswered_seva_attendance(
  p_instance_id uuid,
  p_attendance text default 'served'
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  instance_record public.service_instances;
  v_marked integer;
begin
  if p_attendance not in ('served', 'absent', 'excused') then
    raise exception 'Attendance is served, absent, or excused.';
  end if;

  select * into instance_record from public.service_instances
  where id = p_instance_id;
  if instance_record.id is null then
    raise exception 'This seva could not be found.';
  end if;

  -- The same authority as record_seva_attendance, checked here rather than
  -- inherited, because this does not go through it.
  if instance_record.posted_by is distinct from auth.uid()
    and not public.has_permission('app.view_all')
  then
    raise exception 'Only the devotee who posted this seva, a Tech Admin, or the President can record attendance.';
  end if;

  if ((instance_record.date + instance_record.start_time)
      at time zone 'America/Chicago') > now() then
    raise exception 'Attendance can be recorded once the seva has started.';
  end if;

  -- `attendance is null` is the whole guard: an answered place is somebody
  -- else's decision and is not this tap's to revisit.
  with marked as (
    update public.service_assignments
    set attendance = p_attendance
    where service_instance_id = p_instance_id
      and attendance is null
      and status in ('assigned', 'confirmed', 'completed')
    returning id
  )
  select count(*) into v_marked from marked;

  -- One word from a coordinator can be the last word on whether this seva
  -- happened at all, in either direction — the same sentence
  -- record_seva_attendance ends on.
  perform public.reconcile_service_instance_completion(p_instance_id);

  -- And the same reopening 202608310084 added, for the same reason: a
  -- correction must not be outlived by a frozen week.
  if v_marked > 0 then
    update public.seva_mala_periods
    set frozen_at = null
    where instance_record.date between starts_on and ends_on;

    perform public.recompute_seva_mala_period(periods.id)
    from public.seva_mala_periods periods
    where instance_record.date between periods.starts_on and periods.ends_on;
  end if;

  return v_marked;
end;
$$;

revoke all on function public.record_unanswered_seva_attendance(uuid, text)
  from public, anon;
grant execute on function public.record_unanswered_seva_attendance(uuid, text)
  to authenticated;

comment on function public.record_unanswered_seva_attendance(uuid, text) is
  'Marks every place on a seva that nobody has answered for, in one statement. A place already recorded as served, absent or excused is left alone: the tap answers silence, it does not overrule a coordinator.';

-- ---------------------------------------------------------------------------
-- Proof, run at migration time.
-- ---------------------------------------------------------------------------
do $$
declare
  v_president uuid := '6b000000-0000-0000-0000-000000000001';
  v_absent    uuid := '6b000000-0000-0000-0000-000000000002';
  v_silent    uuid := '6b000000-0000-0000-0000-000000000003';
  v_type uuid;
  v_instance uuid;
  v_marked integer;
  v_absent_after text;
  v_silent_after text;
begin
  -- The whole proof runs inside a sub-block and is then ROLLED BACK by
  -- raising a sentinel, rather than tidied up with DELETEs.
  --
  -- Deleting was wrong for a reason worth writing down: this function
  -- recomputes the Seva Mala period it touches, a recompute can award a badge,
  -- and public.devotee_awards refuses DELETE outright by design (0055 — "an
  -- award that was given cannot be taken back", enforced even against a
  -- superuser). Removing the seeded devotees therefore cascaded into
  -- devotee_awards and was refused, which failed the migration on the first
  -- database that had a real congregation in it. A rollback discards the
  -- inserts instead of deleting them, so no DELETE trigger ever fires.
  begin
    insert into auth.users (id, email, raw_user_meta_data) values
      (v_president, 'mu-president@example.test', jsonb_build_object('name', 'Mark President')),
      (v_absent,    'mu-absent@example.test',    jsonb_build_object('name', 'Mark Absent')),
      (v_silent,    'mu-silent@example.test',    jsonb_build_object('name', 'Mark Silent'));

    update public.users
    set role_id = (select id from public.roles where name = 'president')
    where id = v_president;

    insert into public.service_types (name, category)
    values ('Mark Unanswered Proof Seva', 'other')
    returning id into v_type;

    insert into public.service_instances (
      service_type_id, date, start_time, duration_minutes, slots_needed,
      participation_mode, posted_by, status
    )
    values (
      v_type, public.seva_mala_today() - 1, time '09:00', 60, 2,
      'open', v_president, 'open'
    )
    returning id into v_instance;

    -- One place already answered "absent", one still silent.
    insert into public.service_assignments
      (service_instance_id, devotee_id, assignment_method, status, attendance)
    values
      (v_instance, v_absent, 'self_joined', 'confirmed', 'absent'),
      (v_instance, v_silent, 'self_joined', 'confirmed', null);

    perform set_config('request.jwt.claim.sub', v_president::text, true);
    v_marked := public.record_unanswered_seva_attendance(v_instance, 'served');
    perform set_config('request.jwt.claim.sub', '', true);

    select attendance into v_absent_after from public.service_assignments
    where service_instance_id = v_instance and devotee_id = v_absent;
    select attendance into v_silent_after from public.service_assignments
    where service_instance_id = v_instance and devotee_id = v_silent;

    if v_absent_after is distinct from 'absent' then
      raise exception
        'a devotee recorded absent was overwritten to %; the stale-snapshot bug is still here',
        v_absent_after;
    end if;
    if v_silent_after is distinct from 'served' then
      raise exception 'the unanswered place was not marked served (%)', v_silent_after;
    end if;
    if v_marked <> 1 then
      raise exception 'expected exactly one place to be answered, got %', v_marked;
    end if;

    -- Everything held. Undo it all.
    raise exception 'ISKCON_PROOF_ROLLBACK';
  exception
    when others then
      -- A real failure propagates; the sentinel simply means "discard".
      if sqlerrm <> 'ISKCON_PROOF_ROLLBACK' then
        raise;
      end if;
  end;

  raise notice 'mark served answers silence and leaves an absence alone';
end;
$$;
