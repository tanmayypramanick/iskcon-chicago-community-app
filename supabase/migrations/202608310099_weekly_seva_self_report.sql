-- A devotee is asked whether they made their weekly seva.
-- Requires 202608310098_weekly_seva_is_not_marked.sql.
--
-- A weekly rota runs by itself and counts on completion alone, which means the
-- devotee who quietly misses their day keeps the credit — silently, with
-- nobody told. That is the cost of "automatic", and this is what buys it back
-- without giving the marking job to somebody who was not there.
--
-- Once the occurrence has ended the devotee is asked one question: did you
-- serve it, or did you miss it?
--
--   "I missed it"  records absent. The act earns nothing, and the coordinator
--                  learns the day went uncovered.
--   "I served"     records served. They keep credit they would have had anyway.
--   No answer      changes nothing. The seva still counts, exactly as today.
--
-- WHY THIS IS NOT THE SELF-CERTIFICATION 202608310095 CLOSED, which is the
-- question anybody reading this schema should ask. That migration stopped a
-- devotee marking themselves present on a seva that would otherwise have
-- earned NOTHING — inventing credit out of nothing. Here the baseline is the
-- opposite: the seva already counts on its own, so the only answer that
-- changes anything is the one that gives credit away. Nobody lies to lose
-- hours. "I served" is the current default with a tap in front of it.
--
-- Deliberately never blocking. If the prompt is ignored, dismissed, or never
-- seen, the devotee keeps what they earned. A prompt that cost somebody their
-- hours for not noticing a notification would be a worse error than the one it
-- is fixing.
--
-- Scope, kept narrow on purpose: only the devotee themselves, only their own
-- place, only on a recurring occurrence, and only once it has ended.

-- ---------------------------------------------------------------------------
-- 1. The notification kind, added to the list rather than replacing it.
-- ---------------------------------------------------------------------------

do $$
declare
  v_definition text;
  v_kinds text[];
  v_new text[] := array['weekly_seva_answer'];
begin
  select pg_get_constraintdef(pg_constraint.oid) into v_definition
  from pg_constraint
  where conname = 'app_notifications_kind_check'
    and conrelid = 'public.app_notifications'::regclass;

  if v_definition is null then
    raise exception
      'The app_notifications kind constraint is missing; apply the earlier migrations first.';
  end if;

  select array_agg(distinct quoted[1]) into v_kinds
  from regexp_matches(v_definition, '''([a-z_]+)''', 'g') as quoted;

  if v_kinds is null or cardinality(v_kinds) < 30 then
    raise exception
      'Only % notification kinds could be read out of app_notifications_kind_check; refusing to rewrite it.',
      coalesce(cardinality(v_kinds), 0);
  end if;

  select array_agg(distinct kind order by kind) into v_kinds
  from unnest(v_kinds || v_new) as kind;

  execute 'alter table public.app_notifications drop constraint app_notifications_kind_check';
  execute format(
    'alter table public.app_notifications add constraint app_notifications_kind_check check (kind in (%s))',
    (select string_agg(quote_literal(kind), ', ' order by kind) from unnest(v_kinds) as kind)
  );

  raise notice 'app_notifications now allows % kinds', cardinality(v_kinds);
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. The devotee's own answer.
-- ---------------------------------------------------------------------------

create or replace function public.answer_my_weekly_seva(
  p_assignment_id uuid,
  p_served boolean
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
begin
  if auth.uid() is null then
    raise exception 'Sign in to answer.';
  end if;
  if p_served is null then
    raise exception 'Say whether you served this seva or missed it.';
  end if;

  select * into assignment_record from public.service_assignments
  where id = p_assignment_id for update;
  if assignment_record.id is null then
    raise exception 'This seva place could not be found.';
  end if;

  -- Their own place, and nobody else's. This is a self-report, not a way to
  -- answer for the rest of the rota.
  if assignment_record.devotee_id is distinct from auth.uid() then
    raise exception 'You can only answer for your own seva.';
  end if;

  select * into instance_record from public.service_instances
  where id = assignment_record.service_instance_id;

  -- Weekly only. A posted seva is settled by whoever posted it and a
  -- self-added one by the member who was named; neither is answered here.
  if instance_record.template_id is null then
    raise exception 'This is not a weekly seva. Only a weekly seva is answered by the devotee who stands on it.';
  end if;

  if ((instance_record.date + instance_record.start_time)
      at time zone 'America/Chicago')
     + make_interval(mins => coalesce(instance_record.duration_minutes, 0))
     > now()
  then
    raise exception 'You can answer once the seva is over.';
  end if;

  update public.service_assignments
  set attendance = case when p_served then 'served' else 'absent' end
  where id = p_assignment_id
  returning * into updated_assignment;

  -- The same two sentences record_seva_attendance ends on: a word about
  -- whether this seva happened may be the last word, and a correction must not
  -- be outlived by a frozen Seva Mala week.
  perform public.reconcile_service_instance_completion(instance_record.id);

  update public.seva_mala_periods
  set frozen_at = null
  where instance_record.date between starts_on and ends_on;

  perform public.recompute_seva_mala_period(periods.id)
  from public.seva_mala_periods periods
  where instance_record.date between periods.starts_on and periods.ends_on;

  return updated_assignment;
end;
$$;

revoke all on function public.answer_my_weekly_seva(uuid, boolean) from public, anon;
grant execute on function public.answer_my_weekly_seva(uuid, boolean) to authenticated;

comment on function public.answer_my_weekly_seva(uuid, boolean) is
  'The devotee''s own answer to "did you serve your weekly seva?". Their own place only, weekly only, and only once it is over. Answering "missed" gives up the credit; answering "served" keeps what the rota would have credited anyway; not answering changes nothing.';

-- ---------------------------------------------------------------------------
-- 3. What a devotee still has to answer.
-- ---------------------------------------------------------------------------

create or replace function public.list_my_weekly_seva_to_answer(
  p_days integer default 14
)
returns table (
  assignment_id uuid,
  service_instance_id uuid,
  seva_name text,
  occurred_on date,
  started_at_local time,
  duration_minutes integer
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    assignments.id,
    instances.id,
    public.service_instance_name(instances),
    instances.date,
    instances.start_time,
    instances.duration_minutes
  from public.service_assignments assignments
  join public.service_instances instances
    on instances.id = assignments.service_instance_id
  where auth.uid() is not null
    and assignments.devotee_id = auth.uid()
    and assignments.attendance is null
    and assignments.status in ('assigned', 'confirmed', 'completed')
    and instances.template_id is not null
    and instances.status <> 'cancelled'
    and instances.date >= (now() at time zone 'America/Chicago')::date
                          - greatest(coalesce(p_days, 14), 0)
    -- Over, by the temple's clock, not the reader's.
    and ((instances.date + instances.start_time) at time zone 'America/Chicago')
        + make_interval(mins => coalesce(instances.duration_minutes, 0)) <= now()
  order by instances.date desc, instances.start_time desc
$$;

revoke all on function public.list_my_weekly_seva_to_answer(integer) from public, anon;
grant execute on function public.list_my_weekly_seva_to_answer(integer) to authenticated;

comment on function public.list_my_weekly_seva_to_answer(integer) is
  'The devotee''s own weekly seva that has finished and that they have not answered for yet. Never anybody else''s.';

-- ---------------------------------------------------------------------------
-- 4. What the coordinator sees.
--
--    Whoever set the rota up, plus the Tech Admin and the President. A missed
--    day is the point of the whole feature: it is the thing somebody has to
--    know about, and until now nobody did.
-- ---------------------------------------------------------------------------

create or replace function public.list_weekly_seva_answers(
  p_days integer default 14
)
returns table (
  assignment_id uuid,
  service_instance_id uuid,
  devotee_id uuid,
  devotee_name text,
  devotee_photo_url text,
  seva_name text,
  occurred_on date,
  started_at_local time,
  answer text
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    assignments.id,
    instances.id,
    devotee.id,
    devotee.name,
    devotee.photo_url,
    public.service_instance_name(instances),
    instances.date,
    instances.start_time,
    assignments.attendance
  from public.service_assignments assignments
  join public.service_instances instances
    on instances.id = assignments.service_instance_id
  join public.service_templates templates
    on templates.id = instances.template_id
  join public.users devotee on devotee.id = assignments.devotee_id
  where auth.uid() is not null
    and instances.template_id is not null
    and assignments.attendance is not null
    and instances.date >= (now() at time zone 'America/Chicago')::date
                          - greatest(coalesce(p_days, 14), 0)
    and (
      public.has_permission('app.view_all')
      or templates.created_by = auth.uid()
      or instances.posted_by = auth.uid()
    )
  order by instances.date desc, devotee.name
$$;

revoke all on function public.list_weekly_seva_answers(integer) from public, anon;
grant execute on function public.list_weekly_seva_answers(integer) to authenticated;

comment on function public.list_weekly_seva_answers(integer) is
  'What devotees answered about their own weekly seva, for whoever set the rota up plus the Tech Admin and the President. Empty for everybody else.';

-- ---------------------------------------------------------------------------
-- 5. The asking.
--
--    One notification per unanswered place, once. The guard is keyed on the
--    assignment, the way every other repeating job in this schema keys on the
--    thing that must happen once rather than on the recipient.
-- ---------------------------------------------------------------------------

create or replace function public.prompt_weekly_seva_answers()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  due record;
  sent integer := 0;
begin
  for due in
    select
      assignments.id as assignment_id,
      assignments.devotee_id,
      instances.id as instance_id,
      public.service_instance_name(instances) as seva_name,
      instances.date as occurred_on,
      instances.start_time
    from public.service_assignments assignments
    join public.service_instances instances
      on instances.id = assignments.service_instance_id
    where assignments.attendance is null
      and assignments.status in ('assigned', 'confirmed', 'completed')
      and instances.template_id is not null
      and instances.status <> 'cancelled'
      -- Over, and recent. A rota from last month is not worth a notification.
      and ((instances.date + instances.start_time) at time zone 'America/Chicago')
          + make_interval(mins => coalesce(instances.duration_minutes, 0)) <= now()
      and instances.date >= (now() at time zone 'America/Chicago')::date - 2
      and not exists (
        select 1 from public.app_notifications already
        where already.kind = 'weekly_seva_answer'
          and already.data ->> 'assignmentId' = assignments.id::text
      )
  loop
    perform public.queue_app_notification(
      due.devotee_id,
      'weekly_seva_answer',
      'Did you serve this seva?',
      '"' || due.seva_name || '" on '
        || public.format_seva_when(due.occurred_on, due.start_time)
        || ' — let the temple know whether you made it.',
      jsonb_build_object(
        'assignmentId', due.assignment_id,
        'serviceInstanceId', due.instance_id
      )
    );
    sent := sent + 1;
  end loop;

  return sent;
end;
$$;

revoke all on function public.prompt_weekly_seva_answers()
  from public, anon, authenticated;

comment on function public.prompt_weekly_seva_answers() is
  'Asks each devotee whether they made their weekly seva, once per place, after it has ended. Answering is optional and never costs anybody their hours.';

-- Hourly, a little after the completion sweep, so an occurrence is asked about
-- in the hour it finishes rather than the next day. Guarded on pg_cron the way
-- every other schedule here is.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    if exists (select 1 from cron.job where jobname = 'prompt-weekly-seva-answers') then
      perform cron.unschedule('prompt-weekly-seva-answers');
    end if;
    perform cron.schedule(
      'prompt-weekly-seva-answers', '35 * * * *',
      'select public.prompt_weekly_seva_answers();'
    );
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Proof, run at migration time. Seeded and rolled back, never deleted.
-- ---------------------------------------------------------------------------
do $$
declare
  v_head uuid := '7c000000-0000-0000-0000-000000000001';
  v_dev  uuid := '7c000000-0000-0000-0000-000000000002';
  v_other uuid := '7c000000-0000-0000-0000-000000000003';
  v_type uuid;
  v_template uuid;
  v_inst uuid;
  v_asg uuid;
  v_on date := (now() at time zone 'America/Chicago')::date - 1;
  v_points text;
  v_rows integer;
  v_refused boolean;
  v_prompted integer;
begin
  begin
    insert into auth.users (id, email, raw_user_meta_data) values
      (v_head,  'wa-head@example.test',  jsonb_build_object('name', 'Rota Coordinator')),
      (v_dev,   'wa-dev@example.test',   jsonb_build_object('name', 'Rota Devotee')),
      (v_other, 'wa-other@example.test', jsonb_build_object('name', 'Other Devotee'));

    update public.users
    set role_id = (select id from public.roles where name = 'president')
    where id = v_head;

    insert into public.service_types (name, category)
    values ('Weekly Answer Proof Seva', 'other')
    returning id into v_type;

    insert into public.service_templates
      (service_type_id, day_of_week, start_time, duration_minutes, slots_needed,
       participation_mode, start_date, created_by, days_of_week)
    values (v_type, extract(dow from v_on)::integer, time '07:00', 60, 1,
            'invite_only', v_on - 30, v_head,
            array[extract(dow from v_on)::integer])
    returning id into v_template;

    insert into public.service_instances
      (template_id, service_type_id, date, start_time, duration_minutes,
       slots_needed, participation_mode, posted_by, status)
    values (v_template, v_type, v_on, time '07:00', 60, 1, 'invite_only',
            v_head, 'completed')
    returning id into v_inst;

    insert into public.service_assignments
      (service_instance_id, devotee_id, assignment_method, assigned_by,
       status, verification, completed_at)
    values (v_inst, v_dev, 'recurring_assignment', v_head, 'completed',
            'self_report', (v_on + time '08:00') at time zone 'America/Chicago')
    returning id into v_asg;

    -- Unanswered, it counts. That is the baseline this feature must not move.
    select acts.points_status into v_points
    from public.seva_mala_acts(v_dev) acts
    where acts.service_instance_id = v_inst;
    if v_points is distinct from 'counted' then
      raise exception
        'an unanswered weekly seva reads as % rather than counted', v_points;
    end if;

    -- It is on the devotee's list to answer, and on nobody else's.
    perform set_config('request.jwt.claim.sub', v_dev::text, true);
    select count(*)::integer into v_rows
    from public.list_my_weekly_seva_to_answer() rows
    where rows.assignment_id = v_asg;
    if v_rows <> 1 then
      raise exception 'the devotee was not asked about their own seva (% rows)', v_rows;
    end if;

    perform set_config('request.jwt.claim.sub', v_other::text, true);
    select count(*)::integer into v_rows from public.list_my_weekly_seva_to_answer();
    if v_rows <> 0 then
      raise exception 'another devotee was asked about somebody else''s seva';
    end if;

    -- Nobody answers for anybody else.
    v_refused := false;
    begin
      perform public.answer_my_weekly_seva(v_asg, false);
    exception when others then
      v_refused := true;
    end;
    if not v_refused then
      raise exception 'a devotee answered for somebody else''s seva';
    end if;

    -- "I missed it" gives up the credit.
    perform set_config('request.jwt.claim.sub', v_dev::text, true);
    perform public.answer_my_weekly_seva(v_asg, false);
    perform set_config('request.jwt.claim.sub', '', true);

    -- It earns nothing. This occurrence has one place, so saying "I missed it"
    -- also means nobody served it, and 202608040068's rule follows: the honest
    -- terminal state is 'cancelled' and the act leaves the board with the seva.
    -- Either way the credit is gone, which is the whole point of the answer.
    if exists (
      select 1 from public.seva_mala_acts(v_dev) acts
      where acts.service_instance_id = v_inst
        and acts.credited_minutes > 0
    ) then
      raise exception 'a devotee who said they missed it still earned minutes';
    end if;
    if (select instances.status from public.service_instances instances
        where instances.id = v_inst) = 'completed'
    then
      raise exception 'a weekly seva nobody served still reads as completed';
    end if;

    -- The coordinator can see the answer; an unrelated devotee cannot.
    perform set_config('request.jwt.claim.sub', v_head::text, true);
    select count(*)::integer into v_rows
    from public.list_weekly_seva_answers() rows
    where rows.assignment_id = v_asg and rows.answer = 'absent';
    if v_rows <> 1 then
      raise exception 'the coordinator was not shown the missed day (% rows)', v_rows;
    end if;

    perform set_config('request.jwt.claim.sub', v_other::text, true);
    select count(*)::integer into v_rows from public.list_weekly_seva_answers();
    perform set_config('request.jwt.claim.sub', '', true);
    if v_rows <> 0 then
      raise exception 'an unrelated devotee was shown the rota''s answers';
    end if;

    -- Changing the answer back restores nothing more than silence would have.
    perform set_config('request.jwt.claim.sub', v_dev::text, true);
    perform public.answer_my_weekly_seva(v_asg, true);
    perform set_config('request.jwt.claim.sub', '', true);

    select acts.points_status into v_points
    from public.seva_mala_acts(v_dev) acts
    where acts.service_instance_id = v_inst;
    if v_points is distinct from 'counted' then
      raise exception 'answering "served" left the act at %', v_points;
    end if;

    -- The asking happens once per place.
    update public.service_assignments set attendance = null where id = v_asg;
    v_prompted := public.prompt_weekly_seva_answers();
    if v_prompted < 1 then
      raise exception 'nobody was asked about a finished weekly seva';
    end if;
    if public.prompt_weekly_seva_answers() <> 0 then
      raise exception 'the same place was asked about twice';
    end if;

    raise exception 'ISKCON_PROOF_ROLLBACK';
  exception
    when others then
      if sqlerrm <> 'ISKCON_PROOF_ROLLBACK' then
        raise;
      end if;
  end;

  raise notice 'devotees are asked about their weekly seva, and silence still counts';
end;
$$;
