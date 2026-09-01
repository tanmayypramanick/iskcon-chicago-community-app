-- The birthdays coming up, for the President and the Tech Admin.
-- Requires 202608040044_birthdays_and_congregation.sql and
-- 202608040053_birthday_prompts.sql.
--
-- todays_birthdays answers "who is celebrating right now", which is what the
-- nightly prompt needs. It is the wrong question for a screen: the President
-- opening the noticeboard on a quiet Tuesday sees nothing, learns nothing, and
-- has no way to know that three devotees have birthdays this week.
--
-- So this is the same fact over a window. Same audience — app.view_all, the
-- President and the Tech Admin and nobody else, exactly as todays_birthdays
-- and suggested_birthday_announcement already are. Same leap-year rule, by
-- calling birthday_falls_on rather than restating it: a 29 February birthday
-- is greeted on 28 February in a year that has no 29th, and that logic must
-- not exist twice.
--
-- days_away is what the screen sorts and groups on. It is 0 for today, and the
-- caller does not have to do date arithmetic to find out — the answer to
-- "whose birthday is today" has to be identical to todays_birthdays, and the
-- only way to be sure of that is for one place to decide it.

create or replace function public.upcoming_birthdays(
  p_days integer default 60
)
returns table (
  devotee_id uuid,
  name text,
  photo_url text,
  date_of_birth date,
  turning_age integer,
  celebrated_on date,
  days_away integer
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_today date := (now() at time zone 'America/Chicago')::date;
  v_days integer := least(greatest(coalesce(p_days, 60), 0), 366);
begin
  -- Silent rather than raising, and deliberately unlike
  -- suggested_birthday_announcement: this one IS an idle read — a screen draws
  -- it on open — and a devotee who is simply not allowed should see an empty
  -- list, not an error. todays_birthdays makes the same call for the same
  -- reason.
  if auth.uid() is null or not public.has_permission('app.view_all') then
    return;
  end if;

  return query
  with horizon as (
    select (v_today + offset_days)::date as on_date, offset_days
    from generate_series(0, v_days) as offset_days
  ),
  matches as (
    -- distinct on, not merely ordered: a 60-day window cannot hold the same
    -- birthday twice but a 366-day one can, and the nearer of the two is the
    -- one a screen means. The ORDER BY inside is what picks it.
    select distinct on (users.id)
      users.id as devotee_id,
      users.name as name,
      users.photo_url as photo_url,
      users.date_of_birth as date_of_birth,
      case
        when extract(year from horizon.on_date)
               - extract(year from users.date_of_birth) between 0 and 120
        then (
          extract(year from horizon.on_date)
          - extract(year from users.date_of_birth)
        )::integer
        else null
      end as turning_age,
      horizon.on_date as celebrated_on,
      horizon.offset_days::integer as days_away
    from public.users
    join horizon
      on public.birthday_falls_on(users.date_of_birth, horizon.on_date)
    where users.date_of_birth is not null
    order by users.id, horizon.offset_days
  )
  select
    matches.devotee_id,
    matches.name,
    matches.photo_url,
    matches.date_of_birth,
    matches.turning_age,
    matches.celebrated_on,
    matches.days_away
  from matches
  -- Soonest first, and a stable order within a day so two devotees sharing a
  -- birthday do not swap places between reads.
  order by matches.days_away, matches.name, matches.devotee_id;
end;
$$;

comment on function public.upcoming_birthdays(integer) is
  'The devotees whose birthdays fall within the next p_days in America/Chicago, nearest first, for the President and the Tech Admin. Empty for everybody else. days_away is 0 for today.';

revoke all on function public.upcoming_birthdays(integer) from public, anon;
grant execute on function public.upcoming_birthdays(integer) to authenticated;

-- ---------------------------------------------------------------------------
-- Proof, run at migration time.
-- ---------------------------------------------------------------------------
do $$
declare
  v_pres  uuid := '6e000000-0000-0000-0000-000000000001';
  v_today uuid := '6e000000-0000-0000-0000-000000000002';
  v_soon  uuid := '6e000000-0000-0000-0000-000000000003';
  v_far   uuid := '6e000000-0000-0000-0000-000000000004';
  v_plain uuid := '6e000000-0000-0000-0000-000000000005';
  v_now date := (now() at time zone 'America/Chicago')::date;
  v_rows integer;
  v_days integer;
  v_plain_rows integer;
begin
  -- Seeded and rolled back rather than deleted, for the reason 202608310085
  -- records: removing a seeded devotee cascades, and devotee_awards refuses
  -- DELETE by design.
  begin
    insert into auth.users (id, email, raw_user_meta_data) values
      (v_pres,  'ub-pres@example.test',  jsonb_build_object('name','Upcoming President')),
      (v_today, 'ub-today@example.test', jsonb_build_object('name','Birthday Today')),
      (v_soon,  'ub-soon@example.test',  jsonb_build_object('name','Birthday Soon')),
      (v_far,   'ub-far@example.test',   jsonb_build_object('name','Birthday Far')),
      (v_plain, 'ub-plain@example.test', jsonb_build_object('name','Plain Devotee'));

    update public.users
    set role_id = (select id from public.roles where name = 'president')
    where id = v_pres;

    -- Born on today's month and day, thirty years ago.
    update public.users set date_of_birth =
      make_date(
        (extract(year from v_now)::integer - 30),
        extract(month from v_now)::integer,
        extract(day from v_now)::integer
      )
    where id = v_today;

    update public.users set date_of_birth =
      make_date(
        (extract(year from (v_now + 5))::integer - 40),
        extract(month from (v_now + 5))::integer,
        extract(day from (v_now + 5))::integer
      )
    where id = v_soon;

    -- Deliberately outside a 10-day window.
    update public.users set date_of_birth =
      make_date(
        (extract(year from (v_now + 200))::integer - 40),
        extract(month from (v_now + 200))::integer,
        extract(day from (v_now + 200))::integer
      )
    where id = v_far;

    perform set_config('request.jwt.claim.sub', v_pres::text, true);

    select count(*)::integer into v_rows
    from public.upcoming_birthdays(10) rows
    where rows.devotee_id in (v_today, v_soon, v_far);

    if v_rows <> 2 then
      raise exception
        'a ten-day window returned % of the seeded devotees; expected today and the one five days out',
        v_rows;
    end if;

    select rows.days_away into v_days
    from public.upcoming_birthdays(10) rows
    where rows.devotee_id = v_today;
    if v_days is distinct from 0 then
      raise exception 'today''s birthday reported days_away = %', v_days;
    end if;

    select rows.days_away into v_days
    from public.upcoming_birthdays(10) rows
    where rows.devotee_id = v_soon;
    if v_days is distinct from 5 then
      raise exception 'the birthday five days out reported days_away = %', v_days;
    end if;

    -- It must agree with todays_birthdays about who is celebrating now.
    if not exists (
      select 1 from public.todays_birthdays() t where t.devotee_id = v_today
    ) then
      raise exception 'todays_birthdays and upcoming_birthdays disagree about today';
    end if;

    -- And an ordinary devotee learns nothing at all.
    perform set_config('request.jwt.claim.sub', v_plain::text, true);
    select count(*)::integer into v_plain_rows from public.upcoming_birthdays(365);
    perform set_config('request.jwt.claim.sub', '', true);

    if v_plain_rows <> 0 then
      raise exception
        'an ordinary devotee was shown % upcoming birthdays; they are for the President and Tech Admin only',
        v_plain_rows;
    end if;

    raise exception 'ISKCON_PROOF_ROLLBACK';
  exception
    when others then
      if sqlerrm <> 'ISKCON_PROOF_ROLLBACK' then
        raise;
      end if;
  end;

  raise notice 'upcoming birthdays are windowed, dated and private';
end;
$$;
