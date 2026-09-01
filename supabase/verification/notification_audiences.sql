-- Who a notification actually reaches.
--
-- app_notifications has one primitive — queue_app_notification, one row, one
-- devotee — and everything else is a loop or a `select ... from public.users`
-- around it. That makes the audience an ordinary query, and an ordinary query
-- is exactly the kind of thing that quietly widens. The temple's five
-- audiences are:
--
--   PRIVATE      one named devotee
--   PARTY        the devotees involved in one seva, sanga or request
--   BROADCAST    every devotee
--   LEADERSHIP   app.view_all — President and Tech Admin only
--   OVERSIGHT    services.manage_recurring — Community Head and above
--
-- birthday_today was once BROADCAST when it should have been LEADERSHIP: the
-- whole congregation was told to go and post a wish. Nothing was checking, so
-- nothing caught it, and nothing would have caught it coming back. Section 3
-- checks it the hard way.
--
-- Every section drives the real RPC and then asserts the recipient list as a
-- multiset — which means it also asserts that everybody NOT in the list got
-- nothing, and that nobody got the same notification twice. A section ends
-- with nab_no_more, which fails if the flow queued any kind the section did
-- not name. Silence is asserted as loudly as speech.
--
-- Rolled back at the end, so the script is re-runnable.

begin;

-- ---------------------------------------------------------------------------
-- The congregation. One of each kind of authority, and two plain devotees so
-- "the other devotee heard nothing" is a thing that can be said at all.
-- ---------------------------------------------------------------------------

create temporary table nab_ids (key text primary key, id uuid not null)
  on commit drop;
grant all on table nab_ids to authenticated;

/** Every notification this script has already accounted for. */
create temporary table nab_seen (id uuid primary key) on commit drop;
grant all on table nab_seen to authenticated;

do $$
declare
  v_who record;
  v_i integer := 0;
  v_id uuid;
begin
  for v_who in
    select * from (values
      ('pres',  'Temple President',   'president'),
      ('tech',  'Tech Admin',         'tech'),
      ('head',  'Community Head',     'core'),
      ('vol',   'Temple Volunteer',   'volunteer'),
      ('dev1',  'Devotee One',        'devotee'),
      ('dev2',  'Devotee Two',        'devotee')
    ) as cast_member(key, name, role)
  loop
    v_i := v_i + 1;
    v_id := ('7a000000-0000-0000-0000-0000000000' || lpad(v_i::text, 2, '0'))::uuid;
    insert into auth.users (id, email, raw_user_meta_data)
    values (v_id, 'nab-' || v_who.key || '@example.test',
            jsonb_build_object('name', v_who.name));
    update public.users
    set role_id = (select id from public.roles where name = v_who.role)
    where id = v_id;
    insert into nab_ids (key, id) values (v_who.key, v_id);
  end loop;
end;
$$;

-- The cast must be the whole congregation, or "broadcast" cannot be asserted.
do $$
declare
  v_strays integer;
begin
  select count(*) into v_strays
  from public.users
  where id not in (select id from nab_ids);
  if v_strays <> 0 then
    raise exception
      'this database already holds % devotees outside the cast; the broadcast assertions would be meaningless',
      v_strays;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- The instruments.
-- ---------------------------------------------------------------------------

/** Runs as this devotee, the way PostgREST would. */
create or replace function pg_temp.nab_as(p_who text)
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claim.sub',
    (select id::text from nab_ids where key = p_who), true);
end;
$$;

create or replace function pg_temp.nab_anon()
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claim.sub', '', true);
end;
$$;

/**
 * The recipients of every notification of this kind that the script has not
 * already accounted for, as a sorted multiset of cast keys. A devotee who was
 * told twice appears twice, so double-notification is a failure and not a
 * rounding error.
 */
create or replace function pg_temp.nab_who(p_kind text)
returns text[]
language sql
stable
as $$
  select coalesce(array_agg(k order by k), '{}'::text[])
  from (
    select coalesce(ids.key, 'STRANGER:' || notes.user_id::text) as k
    from public.app_notifications notes
    left join nab_ids ids on ids.id = notes.user_id
    where notes.kind = p_kind
      and not exists (select 1 from nab_seen seen where seen.id = notes.id)
  ) reached;
$$;

/**
 * Asserts the exact audience of one kind, then accounts for it.
 *
 * p_who is a multiset. Anyone missing from it is asserted to have received
 * nothing of this kind — which is the half of the audit that matters, because
 * a notification reaching one person too many is the bug that leaks.
 */
create or replace function pg_temp.nab_expect(
  p_case text, p_kind text, p_who text[]
)
returns void
language plpgsql
as $$
declare
  v_actual text[] := pg_temp.nab_who(p_kind);
  v_expected text[] := coalesce(
    (select array_agg(w order by w) from unnest(p_who) w), '{}'::text[]);
begin
  if v_actual is distinct from v_expected then
    raise exception '%: % reached % rather than %',
      p_case, p_kind, v_actual, v_expected;
  end if;

  insert into nab_seen (id)
  select notes.id from public.app_notifications notes
  where notes.kind = p_kind
    and not exists (select 1 from nab_seen seen where seen.id = notes.id);
end;
$$;

/**
 * Closes a section: nothing may remain unaccounted for. This is what catches
 * a flow that quietly grew a second notification nobody asked for.
 */
create or replace function pg_temp.nab_no_more(p_case text)
returns void
language plpgsql
as $$
declare
  v_left text;
begin
  select string_agg(distinct notes.kind || ' -> ' ||
           coalesce((select key from nab_ids where id = notes.user_id),
                    notes.user_id::text), ', ')
  into v_left
  from public.app_notifications notes
  where not exists (select 1 from nab_seen seen where seen.id = notes.id);

  if v_left is not null then
    raise exception '%: nothing else should have been queued, but % was',
      p_case, v_left;
  end if;
end;
$$;

/** Forgets everything queued so far, without asserting anything about it. */
create or replace function pg_temp.nab_ignore_all()
returns void
language plpgsql
as $$
begin
  insert into nab_seen (id)
  select notes.id from public.app_notifications notes
  where not exists (select 1 from nab_seen seen where seen.id = notes.id);
end;
$$;

/** The one-off seva fixture: a service type the whole script shares. */
do $$
declare
  v_type uuid;
begin
  insert into public.service_types (name, category)
  values ('Notification Audience Seva', 'other')
  on conflict (name) do update set is_active = true
  returning id into v_type;
  insert into nab_ids (key, id) values ('type', v_type);
end;
$$;

-- Signing six devotees up already queued devotee_joined to leadership. That is
-- section 12's business; here it would only be noise.
select pg_temp.nab_ignore_all();

-- ---------------------------------------------------------------------------
-- 1. The inventory itself. Every kind the constraint allows must be queued by
--    something, and everything queued must be a kind the constraint allows.
--
--    A kind in the constraint that nothing sends is dead weight the app still
--    writes a screen for. A kind sent by a function but missing from the
--    constraint is worse: it raises at insert time, inside whatever seva
--    action produced it, and the devotee sees the action fail.
-- ---------------------------------------------------------------------------

create or replace view pg_temp.nab_sent as
  -- queue_app_notification(recipient, 'kind', ...)
  select distinct hit[1] as kind
  from pg_proc proc
  join pg_namespace space on space.oid = proc.pronamespace,
  lateral regexp_matches(proc.prosrc,
    'queue_app_notification\s*\(\s*[^,]+,\s*''([a-z_]+)''', 'g') hit
  where space.nspname = 'public'
  union
  -- notify_service_oversight('kind', ...)
  select distinct hit[1]
  from pg_proc proc
  join pg_namespace space on space.oid = proc.pronamespace,
  lateral regexp_matches(proc.prosrc,
    'notify_service_oversight\s*\(\s*''([a-z_]+)''', 'g') hit
  where space.nspname = 'public'
  union
  -- the bulk sends, which insert into the table directly
  select distinct hit[1]
  from pg_proc proc
  join pg_namespace space on space.oid = proc.pronamespace,
  lateral regexp_matches(proc.prosrc,
    'insert into public\.app_notifications\s*\([^)]*\)\s*(?:select|values)\s*\(?\s*(?:distinct\s*)?[^,]+,\s*''([a-z_]+)''',
    'g') hit
  where space.nspname = 'public';

create or replace view pg_temp.nab_allowed as
  select distinct hit[1] as kind
  from pg_constraint,
  lateral regexp_matches(pg_get_constraintdef(oid), '''([a-z_]+)''::text', 'g') hit
  where conname = 'app_notifications_kind_check';

do $$
declare
  v_allowed text[];
  v_sent text[];
  v_dead text[];
  v_unknown text[];
begin
  select array_agg(kind order by 1)
  into v_allowed from pg_temp.nab_allowed;

  if array_length(v_allowed, 1) is null or array_length(v_allowed, 1) < 40 then
    raise exception
      'only % kinds could be read out of app_notifications_kind_check; the inventory cannot be trusted',
      coalesce(array_length(v_allowed, 1), 0);
  end if;

  select array_agg(kind order by 1) into v_sent from pg_temp.nab_sent;

  -- A kind nothing sends. `remote` is the one legitimate case: the app falls
  -- back to it for a push that arrived with no kind of its own
  -- (src/services/notifications.ts), so no database function ever writes it.
  select array_agg(k order by k) into v_dead
  from unnest(v_allowed) k
  where k <> 'remote' and not exists (
    select 1 from pg_temp.nab_sent where kind = k
  );
  if v_dead is not null then
    raise exception
      'these kinds are allowed but nothing queues them, so the app writes screens for notifications that can never arrive: %',
      v_dead;
  end if;

  -- A kind sent but not allowed would raise inside the seva action itself.
  select array_agg(k order by k) into v_unknown
  from unnest(v_sent) k
  where not (k = any(v_allowed));
  if v_unknown is not null then
    raise exception
      'these kinds are queued by a function but rejected by app_notifications_kind_check, so the action that sends them fails: %',
      v_unknown;
  end if;

  raise notice 'inventory: % kinds allowed, % of them queued by a function, remote reserved for the app',
    array_length(v_allowed, 1), array_length(v_sent, 1);
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. The table itself. A devotee reads their own notifications and nobody
--    else's — not by convention, but because the policy refuses.
--
--    The whole audit rests on this: if the audience of a row were readable by
--    anyone, computing the audience correctly would not matter.
-- ---------------------------------------------------------------------------

do $$
declare
  v_forced boolean;
  v_insertable boolean;
begin
  if not (select relrowsecurity from pg_class where oid = 'public.app_notifications'::regclass)
  then
    raise exception 'row level security is off on app_notifications';
  end if;

  -- A devotee may never write a notification to anybody, themselves included:
  -- queue_app_notification is security definer and is the only way in.
  select bool_or(privilege_type = 'INSERT') into v_insertable
  from information_schema.role_table_grants
  where table_name = 'app_notifications' and grantee = 'authenticated';
  if coalesce(v_insertable, false) then
    raise exception
      'authenticated can insert into app_notifications, so a devotee can post a notification as the temple';
  end if;
end;
$$;

insert into public.app_notifications (user_id, kind, title, body)
select id, 'remote', 'Fixture', 'Fixture' from nab_ids where key in ('dev1', 'dev2');

do $$
declare
  v_mine integer;
  v_theirs integer;
  v_updated integer;
begin
  perform pg_temp.nab_as('dev1');
  set local role authenticated;

  select count(*) into v_mine from public.app_notifications
  where kind = 'remote' and user_id = (select id from nab_ids where key = 'dev1');
  select count(*) into v_theirs from public.app_notifications
  where kind = 'remote' and user_id = (select id from nab_ids where key = 'dev2');

  -- Marking read is allowed on your own row and silently touches nothing on
  -- anyone else's, because the policy filters rather than errors.
  update public.app_notifications set read_at = now()
  where user_id = (select id from nab_ids where key = 'dev2');
  get diagnostics v_updated = row_count;

  reset role;
  perform pg_temp.nab_anon();

  if v_mine <> 1 then
    raise exception 'a devotee cannot read their own notification (saw % rows)', v_mine;
  end if;
  if v_theirs <> 0 then
    raise exception
      'a devotee read % of another devotee''s notifications; every audience in this script is meaningless',
      v_theirs;
  end if;
  if v_updated <> 0 then
    raise exception
      'a devotee marked % of another devotee''s notifications read', v_updated;
  end if;
end;
$$;

-- Anonymous callers see nothing at all — and in fact are refused outright,
-- because anon holds no grant on the table.
do $$
declare
  v_seen integer;
  v_refused boolean := false;
begin
  perform pg_temp.nab_anon();
  set local role anon;
  begin
    select count(*) into v_seen from public.app_notifications;
  exception when insufficient_privilege then
    v_refused := true;
  end;
  reset role;
  if not v_refused and coalesce(v_seen, 0) <> 0 then
    raise exception 'a signed-out caller read % notifications', v_seen;
  end if;
end;
$$;

delete from public.app_notifications where kind = 'remote';
select pg_temp.nab_ignore_all();

-- ---------------------------------------------------------------------------
-- 3. birthday_today is LEADERSHIP, and this is the one that was wrong.
--
--    It reads app.view_all, so President and Tech Admin and nobody else: not
--    the Community Head who has every seva permission there is, not the
--    volunteer, and above all not the devotee whose birthday it is. Being
--    told to go and wish yourself a happy birthday is how the bug announced
--    itself last time.
-- ---------------------------------------------------------------------------

update public.users
set date_of_birth = (make_date(
  1985,
  extract(month from (now() at time zone 'America/Chicago')::date)::integer,
  extract(day from (now() at time zone 'America/Chicago')::date)::integer))
where id = (select id from nab_ids where key = 'dev1');

do $$
declare
  v_sent integer;
begin
  perform pg_temp.nab_as('pres');
  v_sent := public.prompt_birthday_wishes();
  perform pg_temp.nab_anon();

  if v_sent <> 2 then
    raise exception
      'the birthday prompt queued % notifications; leadership is two people',
      v_sent;
  end if;
end;
$$;

select pg_temp.nab_expect(
  'birthday prompt', 'birthday_today', array['pres', 'tech']);
select pg_temp.nab_no_more('birthday prompt');

-- And it carries the celebrant, so leadership can act without guessing.
-- (The row is gone from the unseen set by now, so this reads the table.)
do $$
declare
  v_devotee text;
begin
  select distinct data ->> 'devoteeId' into v_devotee
  from public.app_notifications where kind = 'birthday_today';
  if v_devotee is distinct from (select id::text from nab_ids where key = 'dev1') then
    raise exception 'the birthday prompt names % rather than the celebrant', v_devotee;
  end if;
end;
$$;

-- Run twice on the same day and the temple is not told twice.
do $$
declare
  v_again integer;
begin
  perform pg_temp.nab_as('tech');
  v_again := public.prompt_birthday_wishes();
  perform pg_temp.nab_anon();
  if v_again <> 0 then
    raise exception 'the birthday prompt queued % more notifications on a second run', v_again;
  end if;
end;
$$;

select pg_temp.nab_no_more('birthday prompt, twice in one day');

-- A devotee cannot run it at all, so the prompt cannot be used to discover
-- who has a birthday today.
do $$
declare
  v_refused boolean := false;
begin
  perform pg_temp.nab_as('dev2');
  set local role authenticated;
  begin
    perform public.prompt_birthday_wishes();
  exception when others then
    v_refused := true;
  end;
  reset role;
  perform pg_temp.nab_anon();
  if not v_refused then
    raise exception 'a plain devotee ran the birthday prompt';
  end if;
end;
$$;

select pg_temp.nab_ignore_all();
update public.users set date_of_birth = null
where id = (select id from nab_ids where key = 'dev1');

-- ---------------------------------------------------------------------------
-- 4. announcement_posted is BROADCAST — everybody except whoever wrote it.
--
--    The poster hearing about their own announcement is the self-notification
--    that would be noticed first and trusted least.
-- ---------------------------------------------------------------------------

do $$
begin
  perform pg_temp.nab_as('head');
  perform public.create_announcement(
    'Sunday feast', 'Everybody is welcome after the evening arati.');
  perform pg_temp.nab_anon();
end;
$$;

select pg_temp.nab_expect(
  'announcement posted', 'announcement_posted',
  array['pres', 'tech', 'vol', 'dev1', 'dev2']);
select pg_temp.nab_no_more('announcement posted');

-- ---------------------------------------------------------------------------
-- 5. A one-off seva, offered and answered.
--
--    service_offer is PRIVATE: the invitation reaches the devotee invited and
--    nobody else, because an invitation everybody can see is not an invitation.
--    The answer, accepted or declined, goes back to whoever asked.
-- ---------------------------------------------------------------------------

do $$
declare
  v_instance uuid;
  v_offer uuid;
begin
  perform pg_temp.nab_as('head');
  v_instance := public.create_service_requirement(
    (select id from nab_ids where key = 'type'), null,
    (now() at time zone 'America/Chicago')::date + 3,
    time '10:00', 90, 2, 'invite_only',
    array[(select id from nab_ids where key = 'dev1')]
  );
  insert into nab_ids values ('instance', v_instance);
  perform pg_temp.nab_anon();
end;
$$;

-- Posting it invited one devotee. Nobody else was told, because an invitee-only
-- seva is not an open one.
select pg_temp.nab_expect(
  'invitee-only seva posted', 'service_offer', array['dev1']);
select pg_temp.nab_no_more('invitee-only seva posted');

-- The coordinator then asks a second devotee directly.
do $$
declare
  v_offer uuid;
begin
  perform pg_temp.nab_as('head');
  v_offer := public.offer_service_instance(
    (select id from nab_ids where key = 'instance'),
    (select id from nab_ids where key = 'dev2'));
  insert into nab_ids values ('offer_dev2', v_offer);
  perform pg_temp.nab_anon();
end;
$$;

select pg_temp.nab_expect(
  'seva offered to one devotee', 'service_offer', array['dev2']);
select pg_temp.nab_no_more('seva offered to one devotee');

-- dev1 accepts. The coordinator hears; dev2, who is still deciding, does not.
do $$
declare
  v_offer uuid;
begin
  select id into v_offer from public.service_offers
  where service_instance_id = (select id from nab_ids where key = 'instance')
    and offered_to = (select id from nab_ids where key = 'dev1');

  perform pg_temp.nab_as('dev1');
  set local role authenticated;
  perform public.respond_to_service_offer(v_offer, true);
  reset role;
  perform pg_temp.nab_anon();
end;
$$;

select pg_temp.nab_expect(
  'seva offer accepted', 'service_offer_response', array['head']);
select pg_temp.nab_no_more('seva offer accepted');

-- dev2 declines. Again only the coordinator, and dev1 — already on the seva —
-- is not told that somebody else said no.
do $$
begin
  perform pg_temp.nab_as('dev2');
  set local role authenticated;
  perform public.respond_to_service_offer(
    (select id from nab_ids where key = 'offer_dev2'), false);
  reset role;
  perform pg_temp.nab_anon();
end;
$$;

select pg_temp.nab_expect(
  'seva offer declined', 'service_offer_response', array['head']);
select pg_temp.nab_no_more('seva offer declined');

-- ---------------------------------------------------------------------------
-- 6. A seva opened to everyone is BROADCAST — except the coordinator who
--    opened it, and except the devotee already invited, who was asked once
--    already and does not need asking twice.
-- ---------------------------------------------------------------------------

do $$
declare
  v_instance uuid;
begin
  perform pg_temp.nab_as('head');
  v_instance := public.create_service_requirement(
    (select id from nab_ids where key = 'type'), null,
    (now() at time zone 'America/Chicago')::date + 4,
    time '11:00', 60, 3, 'open', '{}'::uuid[]
  );
  insert into nab_ids values ('open_instance', v_instance);
  perform pg_temp.nab_anon();
end;
$$;

select pg_temp.nab_expect(
  'open seva posted', 'service_open',
  array['pres', 'tech', 'vol', 'dev1', 'dev2']);
select pg_temp.nab_no_more('open seva posted');

-- A devotee taking a place tells the coordinator who asked, and only them.
do $$
begin
  perform pg_temp.nab_as('dev2');
  set local role authenticated;
  perform public.join_service_instance(
    (select id from nab_ids where key = 'open_instance'));
  reset role;
  perform pg_temp.nab_anon();
end;
$$;

select pg_temp.nab_expect(
  'devotee joined an open seva', 'service_joined', array['head']);
select pg_temp.nab_no_more('devotee joined an open seva');

-- ---------------------------------------------------------------------------
-- 7. Coverage. A devotee on a rota cannot make their day.
--
--    service_coverage_needed is OVERSIGHT, not broadcast: the people who can
--    actually resolve it. The devotee who asked is not told about their own
--    request, and the plain devotees are not told at all.
-- ---------------------------------------------------------------------------

do $$
declare
  v_template uuid;
  v_instance uuid;
begin
  perform pg_temp.nab_as('head');
  set local role authenticated;
  v_template := public.create_service_template_v2(
    (select id from nab_ids where key = 'type'), null,
    array[0, 1, 2, 3, 4, 5, 6], '18:00:00', 60, 1, 'open',
    (now() at time zone 'America/Chicago')::date, null, '{}'::uuid[]
  );
  reset role;
  perform pg_temp.nab_anon();
  insert into nab_ids values ('template', v_template);
end;
$$;

select pg_temp.nab_ignore_all();

-- The volunteer takes a standing place on the rota.
do $$
begin
  perform pg_temp.nab_as('vol');
  set local role authenticated;
  perform public.join_weekly_service(
    (select id from nab_ids where key = 'template'));
  reset role;
  perform pg_temp.nab_anon();
end;
$$;

select pg_temp.nab_ignore_all();

-- Tomorrow's occurrence is the one they cannot make.
do $$
declare
  v_instance uuid;
  v_exception uuid;
  v_group uuid;
begin
  select instances.id into v_instance
  from public.service_instances instances
  join public.service_assignments assignments
    on assignments.service_instance_id = instances.id
   and assignments.devotee_id = (select id from nab_ids where key = 'vol')
   and assignments.status in ('assigned', 'confirmed')
  where instances.template_id = (select id from nab_ids where key = 'template')
    and instances.date > (now() at time zone 'America/Chicago')::date
  order by instances.date
  limit 1;

  if v_instance is null then
    raise exception 'the rota produced no future occurrence for the volunteer to stand down from';
  end if;
  insert into nab_ids values ('weekly_instance', v_instance);

  -- The RPC the app actually calls (src/features/services/api.ts). Its
  -- one-occurrence scope is the "I cannot make this Tuesday" case.
  perform pg_temp.nab_as('vol');
  set local role authenticated;
  v_group := public.report_weekly_service_unavailable(
    (select id from nab_ids where key = 'template'),
    'occurrence',
    (select date from public.service_instances where id = v_instance),
    (select date from public.service_instances where id = v_instance),
    array[(select extract(dow from date)::integer
           from public.service_instances where id = v_instance)],
    'Out of town');
  reset role;
  perform pg_temp.nab_anon();

  select id into v_exception from public.service_exceptions
  where request_group_id = v_group and service_instance_id = v_instance;
  if v_exception is null then
    raise exception 'standing down produced no coverage request to answer';
  end if;
  insert into nab_ids values ('exception', v_exception);
end;
$$;

-- services.resolve_coverage — Community Head, President, Tech Admin. Not the
-- volunteer who asked, and not the two devotees, who cannot resolve anything.
select pg_temp.nab_expect(
  'coverage needed', 'service_coverage_needed', array['head', 'pres', 'tech']);
select pg_temp.nab_no_more('coverage needed');

-- The Community Head asks dev1 to cover. PRIVATE, again.
do $$
declare
  v_offer uuid;
begin
  perform pg_temp.nab_as('head');
  set local role authenticated;
  v_offer := public.offer_service_coverage(
    (select id from nab_ids where key = 'exception'),
    (select id from nab_ids where key = 'dev1'));
  reset role;
  perform pg_temp.nab_anon();
  insert into nab_ids values ('coverage_offer', v_offer);
end;
$$;

select pg_temp.nab_expect(
  'coverage offered', 'service_offer', array['dev1']);
select pg_temp.nab_no_more('coverage offered');

-- dev1 accepts. The devotee who asked for cover is told it is resolved; the
-- coordinator who arranged it is told the answer. dev2 hears nothing about
-- somebody else's rota.
do $$
begin
  perform pg_temp.nab_as('dev1');
  set local role authenticated;
  perform public.respond_to_service_offer(
    (select id from nab_ids where key = 'coverage_offer'), true);
  reset role;
  perform pg_temp.nab_anon();
end;
$$;

select pg_temp.nab_expect(
  'coverage resolved', 'service_coverage_resolved', array['vol']);
select pg_temp.nab_expect(
  'coverage resolved, the asker answered', 'service_offer_response', array['head']);
select pg_temp.nab_no_more('coverage resolved');

-- ---------------------------------------------------------------------------
-- 8. Seva verification. A devotee describes seva they did and names a member
--    to vouch for it.
--
--    The ask is PRIVATE to the named verifier — nobody else is asked to
--    confirm somebody else's word — and the verdict is PRIVATE back to the
--    devotee. The other members of leadership are not copied in either
--    direction: an unverified claim is not news.
-- ---------------------------------------------------------------------------

do $$
declare
  v_request public.service_verifications;
begin
  perform pg_temp.nab_as('dev1');
  set local role authenticated;
  v_request := public.log_completed_seva(
    (select id from nab_ids where key = 'type'), null,
    now() - interval '3 hours', now() - interval '2 hours',
    'Temple kitchen',
    (select id from nab_ids where key = 'head'));
  reset role;
  perform pg_temp.nab_anon();
  insert into nab_ids values ('verification', v_request.id);
end;
$$;

select pg_temp.nab_expect(
  'verification requested', 'seva_verification_requested', array['head']);
select pg_temp.nab_no_more('verification requested');

-- The Community Head confirms it. The devotee is told; nobody else is.
do $$
begin
  perform pg_temp.nab_as('head');
  set local role authenticated;
  perform public.respond_to_seva_verification(
    (select id from nab_ids where key = 'verification'), true, null);
  reset role;
  perform pg_temp.nab_anon();
end;
$$;

select pg_temp.nab_expect(
  'verification reviewed', 'seva_verification_reviewed', array['dev1']);
-- Confirming it also creates the completed seva, and that is oversight's
-- business — the Community Head who did it is not told about their own act.
select pg_temp.nab_expect(
  'verification reviewed, oversight told', 'service_completed',
  array['pres', 'tech']);
select pg_temp.nab_no_more('verification reviewed');

-- ---------------------------------------------------------------------------
-- 9. weekly_seva_answer is PRIVATE to the devotee who was on the rota.
--
--    It asks "did you serve this?", so it can only go to the one person who
--    knows. A coordinator receiving it would be asked about a seva that was
--    never theirs.
-- ---------------------------------------------------------------------------

do $$
declare
  v_asked integer;
begin
  -- Today's occurrence is still the volunteer's — they stood down from
  -- tomorrow's, not this one. Move its start to first thing so it is over,
  -- which is the only condition the prompt waits on.
  update public.service_instances
  set start_time = time '00:05'
  where template_id = (select id from nab_ids where key = 'template')
    and date = (now() at time zone 'America/Chicago')::date
    and id in (
      select service_instance_id from public.service_assignments
      where devotee_id = (select id from nab_ids where key = 'vol')
        and status in ('assigned', 'confirmed')
    );

  perform pg_temp.nab_as('pres');
  v_asked := public.prompt_weekly_seva_answers();
  perform pg_temp.nab_anon();

  if v_asked < 1 then
    raise exception 'no weekly answer was asked for at all';
  end if;
end;
$$;

-- Only the devotees who actually held a place. dev1 covered tomorrow's
-- occurrence, which has not happened yet, so nothing is owed by them.
select pg_temp.nab_expect(
  'weekly seva answer', 'weekly_seva_answer', array['vol']);
select pg_temp.nab_no_more('weekly seva answer');

-- ---------------------------------------------------------------------------
-- 10. Sangas. A request to join reaches the one devotee who runs the circle.
--
--     Not leadership, not the other members, not the congregation. Who wants
--     to join what is the sanga admin's business alone.
-- ---------------------------------------------------------------------------

do $$
declare
  v_sanga public.sangas;
begin
  perform pg_temp.nab_as('dev1');
  set local role authenticated;
  v_sanga := public.create_sanga('Bhakti Vriksha North', 'A weekly study circle.');
  reset role;
  perform pg_temp.nab_anon();
  insert into nab_ids values ('sanga', v_sanga.id);
end;
$$;

-- Proposing a sanga is for whoever reviews requests: President and Tech Admin.
select pg_temp.nab_expect(
  'sanga proposed', 'sanga_created', array['pres', 'tech']);
select pg_temp.nab_no_more('sanga proposed');

do $$
begin
  perform pg_temp.nab_as('pres');
  set local role authenticated;
  perform public.review_sanga(
    (select id from nab_ids where key = 'sanga'), 'approved', null);
  reset role;
  perform pg_temp.nab_anon();
end;
$$;

select pg_temp.nab_expect(
  'sanga reviewed', 'sanga_reviewed', array['dev1']);
select pg_temp.nab_no_more('sanga reviewed');

-- dev2 asks to join. Only the admin hears.
do $$
declare
  v_request public.sanga_join_requests;
begin
  perform pg_temp.nab_as('dev2');
  set local role authenticated;
  v_request := public.request_to_join_sanga(
    (select id from nab_ids where key = 'sanga'), 'I would like to come.');
  reset role;
  perform pg_temp.nab_anon();
  insert into nab_ids values ('join_request', v_request.id);
end;
$$;

select pg_temp.nab_expect(
  'sanga join requested', 'sanga_join_requested', array['dev1']);
select pg_temp.nab_no_more('sanga join requested');

-- Asking twice is the same ask, and the admin is not told twice.
do $$
begin
  perform pg_temp.nab_as('dev2');
  set local role authenticated;
  perform public.request_to_join_sanga(
    (select id from nab_ids where key = 'sanga'), 'Still keen.');
  reset role;
  perform pg_temp.nab_anon();
end;
$$;

select pg_temp.nab_no_more('sanga join requested twice');

-- The verdict is PRIVATE to whoever asked.
do $$
begin
  perform pg_temp.nab_as('dev1');
  set local role authenticated;
  perform public.review_sanga_join_request(
    (select id from nab_ids where key = 'join_request'), 'approved');
  reset role;
  perform pg_temp.nab_anon();
end;
$$;

select pg_temp.nab_expect(
  'sanga join reviewed', 'sanga_join_reviewed', array['dev2']);
select pg_temp.nab_no_more('sanga join reviewed');

-- ---------------------------------------------------------------------------
-- 11. Access requests. A devotee asks for a role.
--
--     The named approver hears, and so does everybody who may review such a
--     request — but each of them exactly once, and never the requester, who
--     already knows what they asked for.
-- ---------------------------------------------------------------------------

do $$
declare
  v_request public.access_requests;
begin
  perform pg_temp.nab_as('dev2');
  set local role authenticated;
  v_request := public.create_access_request(
    'volunteer', 'I would like to help in the kitchen.',
    (select id from nab_ids where key = 'head'));
  reset role;
  perform pg_temp.nab_anon();
  insert into nab_ids values ('access_request', v_request.id);
end;
$$;

-- The named approver plus access.review_requests, deduplicated: the Community
-- Head named as approver must not be told twice, and the President and Tech
-- Admin must each hear once.
select pg_temp.nab_expect(
  'access request submitted', 'access_request_submitted',
  array['head', 'pres', 'tech']);
select pg_temp.nab_no_more('access request submitted');

do $$
begin
  perform pg_temp.nab_as('pres');
  set local role authenticated;
  perform public.review_access_request(
    (select id from nab_ids where key = 'access_request'), 'approved', null);
  reset role;
  perform pg_temp.nab_anon();
end;
$$;

-- The requester is told the verdict, and oversight is told a role changed —
-- except the President, who is the one who changed it.
select pg_temp.nab_expect(
  'access request reviewed', 'access_request_reviewed',
  array['dev2', 'head', 'tech']);
select pg_temp.nab_no_more('access request reviewed');

-- ---------------------------------------------------------------------------
-- 12. devotee_joined is LEADERSHIP. A new devotee signing up is told to
--     President and Tech Admin, and to nobody else — least of all the whole
--     congregation, and never to the newcomer themselves.
-- ---------------------------------------------------------------------------

do $$
begin
  insert into auth.users (id, email, raw_user_meta_data)
  values ('7a000000-0000-0000-0000-000000000099', 'nab-new@example.test',
          jsonb_build_object('name', 'Newly Arrived'));
  insert into nab_ids values ('newcomer', '7a000000-0000-0000-0000-000000000099');
end;
$$;

select pg_temp.nab_expect(
  'a devotee joined', 'devotee_joined', array['pres', 'tech']);
select pg_temp.nab_no_more('a devotee joined');

-- ---------------------------------------------------------------------------
-- 13. Nothing anywhere in this script reached a devotee who should not have
--     had it. Said once more as a whole, because a per-section assertion can
--     only fail on the section that wrote it.
-- ---------------------------------------------------------------------------

do $$
declare
  v_leaked text;
begin
  -- The two plain devotees may never hold a kind that is leadership's or
  -- oversight's alone.
  select string_agg(distinct notes.kind, ', ') into v_leaked
  from public.app_notifications notes
  where notes.user_id in (
      select id from nab_ids where key in ('dev1', 'dev2', 'vol'))
    and notes.kind in (
      'birthday_today', 'devotee_joined', 'recurring_interest_submitted',
      'access_request_submitted', 'sanga_created');
  if v_leaked is not null then
    raise exception
      'a devotee without leadership holds leadership-only notifications: %', v_leaked;
  end if;

  -- And nobody holds a notification addressed to a stranger, which would mean
  -- an audience query lost track of who it was writing to.
  if exists (
    select 1 from public.app_notifications notes
    where not exists (select 1 from nab_ids where id = notes.user_id)
  ) then
    raise exception 'a notification was queued to somebody outside the congregation';
  end if;
end;
$$;

do $$
begin
  raise notice 'every notification audience reaches exactly the devotees the temple intends';
end;
$$;

rollback;
