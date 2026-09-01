-- A devotee can put the weekly question away without answering it.
-- Requires 202608310099_weekly_seva_self_report.sql.
--
-- The question — did you serve your weekly seva, or miss it? — is optional by
-- design: ignoring it costs nobody their hours. But "ignore" and "make it go
-- away" are different things, and without the second the prompt sits on the
-- seva board for a fortnight looking like a task.
--
-- So there is a cross. Dismissing records nothing about the seva: the day
-- still counts, exactly as it would have. It only says this devotee does not
-- want to be asked about it again.
--
-- Kept on the assignment rather than in a table of its own. It is one nullable
-- timestamp about one place, it disappears with the row it belongs to, and a
-- separate table would need its own policies to say what this column says by
-- sitting where it does.

alter table public.service_assignments
  add column if not exists answer_dismissed_at timestamptz;

comment on column public.service_assignments.answer_dismissed_at is
  'When the devotee put the "did you serve this weekly seva?" question away without answering. Says nothing about whether they served — the day counts either way — only that they do not want to be asked again.';

create or replace function public.dismiss_my_weekly_seva_answer(
  p_assignment_id uuid
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

  select * into assignment_record from public.service_assignments
  where id = p_assignment_id for update;
  if assignment_record.id is null then
    raise exception 'This seva place could not be found.';
  end if;

  -- Their own, and nobody else's: putting somebody else's question away would
  -- be answering for them by silence.
  if assignment_record.devotee_id is distinct from auth.uid() then
    raise exception 'You can only answer for your own seva.';
  end if;

  select * into instance_record from public.service_instances
  where id = assignment_record.service_instance_id;

  if instance_record.template_id is null then
    raise exception 'This is not a weekly seva.';
  end if;

  update public.service_assignments
  set answer_dismissed_at = now()
  where id = p_assignment_id
  returning * into updated_assignment;

  -- Nothing else. No reconcile, no recount: the seva is exactly as it was, and
  -- the devotee keeps what the rota credited them.
  return updated_assignment;
end;
$$;

revoke all on function public.dismiss_my_weekly_seva_answer(uuid) from public, anon;
grant execute on function public.dismiss_my_weekly_seva_answer(uuid) to authenticated;

comment on function public.dismiss_my_weekly_seva_answer(uuid) is
  'Puts the weekly "did you serve this?" question away without answering it. Changes nothing about the seva or the devotee''s hours.';

-- The question no longer asks about anything that was put away.
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
    and assignments.answer_dismissed_at is null
    and assignments.status in ('assigned', 'confirmed', 'completed')
    and instances.template_id is not null
    and instances.status <> 'cancelled'
    and instances.date >= (now() at time zone 'America/Chicago')::date
                          - greatest(coalesce(p_days, 14), 0)
    and ((instances.date + instances.start_time) at time zone 'America/Chicago')
        + make_interval(mins => coalesce(instances.duration_minutes, 0)) <= now()
  order by instances.date desc, instances.start_time desc
$$;

revoke all on function public.list_my_weekly_seva_to_answer(integer) from public, anon;
grant execute on function public.list_my_weekly_seva_to_answer(integer) to authenticated;

-- ---------------------------------------------------------------------------
-- Proof, run at migration time. Seeded and rolled back, never deleted.
-- ---------------------------------------------------------------------------
do $$
declare
  v_head uuid := '80000000-0000-0000-0000-000000000001';
  v_dev  uuid := '80000000-0000-0000-0000-000000000002';
  v_type uuid;
  v_template uuid;
  v_inst uuid;
  v_asg uuid;
  v_on date := (now() at time zone 'America/Chicago')::date - 1;
  v_rows integer;
  v_points text;
begin
  begin
    insert into auth.users (id, email, raw_user_meta_data) values
      (v_head, 'dm-head@example.test', jsonb_build_object('name', 'Rota Head')),
      (v_dev,  'dm-dev@example.test',  jsonb_build_object('name', 'Rota Devotee'));

    update public.users
    set role_id = (select id from public.roles where name = 'president')
    where id = v_head;

    insert into public.service_types (name, category)
    values ('Dismiss Proof Seva', 'other')
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

    perform set_config('request.jwt.claim.sub', v_dev::text, true);

    select count(*)::integer into v_rows
    from public.list_my_weekly_seva_to_answer() rows
    where rows.assignment_id = v_asg;
    if v_rows <> 1 then
      raise exception 'the question was not asked to begin with';
    end if;

    perform public.dismiss_my_weekly_seva_answer(v_asg);

    select count(*)::integer into v_rows
    from public.list_my_weekly_seva_to_answer() rows
    where rows.assignment_id = v_asg;
    perform set_config('request.jwt.claim.sub', '', true);

    if v_rows <> 0 then
      raise exception 'the question came back after it was put away';
    end if;

    -- And the seva is untouched: the day still counts, and no answer was
    -- recorded on the devotee's behalf.
    if (select assignments.attendance from public.service_assignments assignments
        where assignments.id = v_asg) is not null
    then
      raise exception 'putting the question away recorded an answer';
    end if;

    select acts.points_status into v_points
    from public.seva_mala_acts(v_dev) acts
    where acts.service_instance_id = v_inst;
    if v_points is distinct from 'counted' then
      raise exception
        'putting the question away cost the devotee their day (%)', v_points;
    end if;

    raise exception 'ISKCON_PROOF_ROLLBACK';
  exception
    when others then
      if sqlerrm <> 'ISKCON_PROOF_ROLLBACK' then
        raise;
      end if;
  end;

  raise notice 'the weekly question can be put away without answering it';
end;
$$;
