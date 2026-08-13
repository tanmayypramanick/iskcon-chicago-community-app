-- Children, how long somebody has been coming, and message retention.
--
-- Three things the temple asked for.
--
-- 1. `children_count` was only ever a number. A congregation that runs a
--    Sunday school needs the details behind it — who the children are, how
--    old, and whether they practise — so `children` holds one entry each and
--    the count is kept in step with it rather than typed in separately.
--
-- 2. "How long have you been coming?" is answered as "about three years", not
--    as a date. `joined_temple_on` asked for a precision nobody has, so an
--    amount and a unit sit beside it. The date stays: other code reads it.
--
-- 3. Deleting a message cleared body and image_url outright. The row survived
--    but its content did not, so the temple's records had a hole in them
--    wherever somebody had deleted. The previous values now move aside instead
--    of being discarded.
-- Requires 202608040036_completion_reachable.sql.

-- ---------------------------------------------------------------------------
-- 1. Children, one entry each.
--
--    The shape is enforced in the database rather than in the app. A client
--    can be old, wrong, or replaced; the column is the only place a rule about
--    the column can actually hold.
-- ---------------------------------------------------------------------------

alter table public.users
  add column if not exists children jsonb not null default '[]'::jsonb;

comment on column public.users.children is
  'One entry per child: name, age, gender, whether they practise, and since when. Private to the devotee and authorised members, as the rest of the family details are.';

-- Written out step by step rather than as one boolean expression: Postgres
-- does not promise the order it evaluates AND/OR in, so a single expression
-- would risk casting a value it has not yet established the type of.
create or replace function public.children_details_are_valid(p_children jsonb)
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
declare
  allowed_keys constant text[] :=
    array['name', 'age', 'gender', 'practices', 'practicing_since'];
  entry jsonb;
  present_key text;
begin
  if p_children is null or jsonb_typeof(p_children) <> 'array' then
    return false;
  end if;

  for entry in select value from jsonb_array_elements(p_children) as element(value)
  loop
    if jsonb_typeof(entry) <> 'object' then
      return false;
    end if;

    -- Anything unrecognised is refused outright. A key the app never meant to
    -- send is far more likely a bug than a new field.
    for present_key in select key from jsonb_object_keys(entry) as keys(key)
    loop
      if not (present_key = any (allowed_keys)) then
        return false;
      end if;
    end loop;

    -- A devotee fills this in over several sittings — they may know they have
    -- three children before they have typed all three ages. So every field is
    -- allowed to be absent or null and only its type is policed when a value
    -- is actually there. Refusing a half-filled row would reject the whole
    -- profile save and lose the rest of what they typed.
    if entry ? 'name'
       and jsonb_typeof(entry -> 'name') not in ('string', 'null') then
      return false;
    end if;

    -- Matched as text so a malformed age is rejected rather than raising: the
    -- pattern admits whole numbers 0 to 120 and nothing else.
    if entry ? 'age' and jsonb_typeof(entry -> 'age') not in ('number', 'null') then
      return false;
    end if;
    if jsonb_typeof(entry -> 'age') = 'number'
       and (entry ->> 'age') !~ '^(0|[1-9][0-9]?|1[01][0-9]|120)$' then
      return false;
    end if;

    if entry ? 'gender'
       and jsonb_typeof(entry -> 'gender') not in ('string', 'null') then
      return false;
    end if;
    if jsonb_typeof(entry -> 'gender') = 'string'
       and (entry ->> 'gender') not in ('male', 'female', 'prefer_not_to_say') then
      return false;
    end if;

    if entry ? 'practices'
       and jsonb_typeof(entry -> 'practices') not in ('boolean', 'null') then
      return false;
    end if;

    -- practicing_since is free text and may be absent or null: plenty of
    -- families cannot name a date, and being unable to should not block saving.
    if entry ? 'practicing_since'
       and jsonb_typeof(entry -> 'practicing_since') not in ('string', 'null') then
      return false;
    end if;
  end loop;

  return true;
end;
$$;

revoke all on function public.children_details_are_valid(jsonb) from public, anon;
grant execute on function public.children_details_are_valid(jsonb) to authenticated;

-- The count and the list must agree, or a profile contradicts itself. An empty
-- list means the details were never filled in, so whatever count was typed in
-- before still stands.
create or replace function public.children_count_agrees(
  p_children jsonb,
  p_children_count integer
)
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
begin
  if p_children is null or jsonb_typeof(p_children) <> 'array' then
    return true;
  end if;
  if jsonb_array_length(p_children) = 0 then
    return true;
  end if;
  return p_children_count is not distinct from jsonb_array_length(p_children);
end;
$$;

revoke all on function public.children_count_agrees(jsonb, integer) from public, anon;
grant execute on function public.children_count_agrees(jsonb, integer) to authenticated;

alter table public.users
  drop constraint if exists user_children_shape_check;
alter table public.users
  add constraint user_children_shape_check
  check (public.children_details_are_valid(children));

alter table public.users
  drop constraint if exists user_children_count_agrees_check;
alter table public.users
  add constraint user_children_count_agrees_check
  check (public.children_count_agrees(children, children_count));

-- ---------------------------------------------------------------------------
-- 2. How long they have been coming to the temple.
-- ---------------------------------------------------------------------------

alter table public.users
  add column if not exists temple_since_amount integer,
  add column if not exists temple_since_unit text;

alter table public.users
  drop constraint if exists user_temple_since_amount_check;
alter table public.users
  add constraint user_temple_since_amount_check check (
    temple_since_amount is null or temple_since_amount >= 0
  );

alter table public.users
  drop constraint if exists user_temple_since_unit_check;
alter table public.users
  add constraint user_temple_since_unit_check check (
    temple_since_unit is null
    or temple_since_unit in ('days', 'weeks', 'months', 'years')
  );

comment on column public.users.temple_since_amount is
  'How long the devotee has been coming, counted in temple_since_unit. Kept beside joined_temple_on, which stays for the code that already reads it.';
comment on column public.users.temple_since_unit is
  'days, weeks, months or years. The unit temple_since_amount is counted in.';

-- ---------------------------------------------------------------------------
-- 3. The two profile RPCs grow.
--
--    A function's argument list cannot be changed in place, and adding a
--    defaulted overload leaves two candidates PostgREST cannot choose between.
--    Both old signatures are dropped by name first, deliberately.
-- ---------------------------------------------------------------------------

drop function if exists public.update_my_profile_community(
  text, text, text, integer, integer, text, text, boolean, boolean, text
);

create or replace function public.update_my_profile_community(
  p_gender text,
  p_marital_status text,
  p_spouse_name text,
  p_children_count integer,
  p_chanting_rounds integer,
  p_languages_spoken text,
  p_how_they_found_us text,
  p_can_offer_lift boolean,
  p_can_host_programs boolean,
  p_skills text,
  p_children jsonb
)
returns public.users
language plpgsql
security definer
set search_path = ''
as $$
declare
  updated_person public.users;
  children_details jsonb;
  resolved_count integer;
begin
  if auth.uid() is null then
    raise exception 'Sign in to update your details.';
  end if;

  children_details := coalesce(p_children, '[]'::jsonb);
  if not public.children_details_are_valid(children_details) then
    raise exception 'Those children''s details could not be read. An age must be a whole number from 0 to 120.';
  end if;

  -- The count follows the list rather than the caller: two numbers a devotee
  -- can disagree with each other is one number too many.
  resolved_count := case
    when jsonb_array_length(children_details) > 0
      then jsonb_array_length(children_details)
    else p_children_count
  end;

  update public.users set
    gender = nullif(trim(coalesce(p_gender, '')), ''),
    marital_status = nullif(trim(coalesce(p_marital_status, '')), ''),
    -- A spouse's name only means something alongside "married"; keeping it
    -- otherwise leaves a profile contradicting itself.
    spouse_name = case when p_marital_status = 'married'
      then nullif(trim(coalesce(p_spouse_name, '')), '') end,
    children = children_details,
    children_count = resolved_count,
    chanting_rounds = p_chanting_rounds,
    languages_spoken = nullif(trim(coalesce(p_languages_spoken, '')), ''),
    how_they_found_us = nullif(trim(coalesce(p_how_they_found_us, '')), ''),
    can_offer_lift = coalesce(p_can_offer_lift, false),
    can_host_programs = coalesce(p_can_host_programs, false),
    skills = nullif(trim(coalesce(p_skills, '')), ''),
    profile_updated_at = now()
  where id = auth.uid()
  returning * into updated_person;

  if updated_person.id is null then
    raise exception 'Your profile could not be found.';
  end if;
  return updated_person;
end;
$$;

revoke all on function public.update_my_profile_community(text, text, text, integer, integer, text, text, boolean, boolean, text, jsonb) from public, anon;
grant execute on function public.update_my_profile_community(text, text, text, integer, integer, text, text, boolean, boolean, text, jsonb) to authenticated;

drop function if exists public.update_my_profile_extras(
  text, text, text, text, text, text, date
);

create or replace function public.update_my_profile_extras(
  p_emergency_contact_name text,
  p_emergency_contact_phone text,
  p_dietary_notes text,
  p_health_notes text,
  p_preferred_language text,
  p_occupation text,
  p_joined_temple_on date,
  p_temple_since_amount integer,
  p_temple_since_unit text
)
returns public.users
language plpgsql
security definer
set search_path = ''
as $$
declare
  updated_person public.users;
  since_unit text;
begin
  if auth.uid() is null then
    raise exception 'Sign in to update your details.';
  end if;

  since_unit := nullif(lower(trim(coalesce(p_temple_since_unit, ''))), '');
  if since_unit is not null
     and since_unit not in ('days', 'weeks', 'months', 'years') then
    raise exception 'How long you have been coming must be counted in days, weeks, months or years.';
  end if;
  if p_temple_since_amount is not null and p_temple_since_amount < 0 then
    raise exception 'How long you have been coming cannot be a negative number.';
  end if;

  update public.users set
    emergency_contact_name = nullif(trim(coalesce(p_emergency_contact_name, '')), ''),
    emergency_contact_phone = nullif(trim(coalesce(p_emergency_contact_phone, '')), ''),
    dietary_notes = nullif(trim(coalesce(p_dietary_notes, '')), ''),
    health_notes = nullif(trim(coalesce(p_health_notes, '')), ''),
    preferred_language = nullif(trim(coalesce(p_preferred_language, '')), ''),
    occupation = nullif(trim(coalesce(p_occupation, '')), ''),
    joined_temple_on = p_joined_temple_on,
    temple_since_amount = p_temple_since_amount,
    temple_since_unit = since_unit,
    profile_updated_at = now()
  where id = auth.uid()
  returning * into updated_person;

  if updated_person.id is null then
    raise exception 'Your profile could not be found.';
  end if;
  return updated_person;
end;
$$;

revoke all on function public.update_my_profile_extras(text, text, text, text, text, text, date, integer, text) from public, anon;
grant execute on function public.update_my_profile_extras(text, text, text, text, text, text, date, integer, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Deleting a message moves its content aside rather than discarding it.
--
--    body and image_url are still cleared, so the thread shows "This message
--    was deleted" exactly as before. The previous values are written to
--    original_body and original_image_url, which are retained for the temple's
--    records and are not part of the select grant held by devotees.
-- ---------------------------------------------------------------------------

alter table public.messages
  add column if not exists original_body text,
  add column if not exists original_image_url text;

comment on column public.messages.original_body is
  'What body held before the message was deleted. Retained for the temple''s records, and outside the select grant held by client roles.';
comment on column public.messages.original_image_url is
  'What image_url held before the message was deleted. Retained on the same terms as original_body.';

create or replace function public.delete_message(p_message_id uuid)
returns public.messages
language plpgsql
security definer
set search_path = ''
as $$
declare
  target public.messages;
  updated public.messages;
begin
  select * into target from public.messages where id = p_message_id for update;
  if target.id is null then
    raise exception 'That message could not be found.';
  end if;
  if target.sender_id <> auth.uid() then
    raise exception 'You can only delete your own messages for everyone.';
  end if;

  -- coalesce so deleting twice cannot overwrite what was moved aside the
  -- first time with the nulls left behind by it.
  update public.messages
  set deleted_at = now(),
      original_body = coalesce(original_body, body),
      original_image_url = coalesce(original_image_url, image_url),
      body = null,
      image_url = null
  where id = p_message_id
  returning * into updated;
  return updated;
end;
$$;

revoke all on function public.delete_message(uuid) from public, anon;
grant execute on function public.delete_message(uuid) to authenticated;

-- Column-level grants are role-wide, which is what makes them work here: the
-- retained columns come off the authenticated grant entirely, so no query a
-- devotee's client can write reaches them, whatever the row filter says.
revoke select on public.messages from authenticated;
grant select (
  id, conversation_id, sender_id, body, image_url,
  created_at, read_at, delivered_at, deleted_at
) on public.messages to authenticated;

-- ---------------------------------------------------------------------------
-- 5. One conversation, for a viewer holding app.view_all.
--
--    Every other viewer gets no rows at all.
-- ---------------------------------------------------------------------------

create or replace function public.list_conversation_messages(p_conversation_id uuid)
returns table (
  id uuid,
  sender_id uuid,
  sender_name text,
  body text,
  image_url text,
  created_at timestamptz,
  deleted_at timestamptz,
  original_body text,
  original_image_url text
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    messages.id,
    messages.sender_id,
    sender.name,
    messages.body,
    messages.image_url,
    messages.created_at,
    messages.deleted_at,
    messages.original_body,
    messages.original_image_url
  from public.messages
  join public.users sender on sender.id = messages.sender_id
  where messages.conversation_id = p_conversation_id
    and public.has_permission('app.view_all')
  order by messages.created_at
$$;

comment on function public.list_conversation_messages(uuid) is
  'Every message in one conversation, for a viewer holding app.view_all. Returns no rows to anyone else.';

revoke all on function public.list_conversation_messages(uuid) from public, anon;
grant execute on function public.list_conversation_messages(uuid) to authenticated;

do $$
begin
  raise notice 'profile children and oversight applied';
end;
$$;
