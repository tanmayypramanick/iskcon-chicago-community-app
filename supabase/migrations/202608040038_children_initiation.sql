-- A child can be initiated too.
--
-- The children list carried a name, an age, a gender and whether the child
-- practises, but not whether they have taken initiation. A temple that keeps
-- that for the devotee has the same reason to keep it for their children, so
-- the three answers the devotee is already asked — initiated, when, and by
-- whom — are asked of each child as well.
--
-- The validator refuses any key it does not recognise, so it has to be taught
-- the new ones before a client can send them. It is replaced whole rather than
-- amended: a function cannot be altered in part.
-- Requires 202608040037_profile_children_and_oversight.sql.

-- ---------------------------------------------------------------------------
-- 1. Three more keys per child.
-- ---------------------------------------------------------------------------

comment on column public.users.children is
  'One entry per child: name, age, gender, whether they practise and since when, and whether they are initiated, when and by whom. Private to the devotee and authorised members, as the rest of the family details are.';

create or replace function public.children_details_are_valid(p_children jsonb)
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
declare
  allowed_keys constant text[] := array[
    'name', 'age', 'gender', 'practices', 'practicing_since',
    'initiated', 'initiation_date', 'diksha_guru'
  ];
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

    if entry ? 'initiated'
       and jsonb_typeof(entry -> 'initiated') not in ('boolean', 'null') then
      return false;
    end if;

    -- An initiation date comes from a picker, never a keyboard, so it is held
    -- to the calendar shape the app sends. Matched as text for the same reason
    -- the age is: a wrong value must be refused, not raise.
    if entry ? 'initiation_date'
       and jsonb_typeof(entry -> 'initiation_date') not in ('string', 'null') then
      return false;
    end if;
    if jsonb_typeof(entry -> 'initiation_date') = 'string'
       and (entry ->> 'initiation_date')
           !~ '^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$' then
      return false;
    end if;

    if entry ? 'diksha_guru'
       and jsonb_typeof(entry -> 'diksha_guru') not in ('string', 'null') then
      return false;
    end if;
  end loop;

  return true;
end;
$$;

revoke all on function public.children_details_are_valid(jsonb) from public, anon;
grant execute on function public.children_details_are_valid(jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Answering "no" for a child clears the two answers underneath it.
--
--    Exactly what update_my_profile already does for the devotee's own
--    initiation. The details are dropped rather than the save refused: a
--    devotee who corrects an answer should not be made to tidy up after it,
--    and nothing else they typed should be lost because they did not.
-- ---------------------------------------------------------------------------

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
    raise exception 'Those children''s details could not be read. An age must be a whole number from 0 to 120, and an initiation date must be given as YYYY-MM-DD.';
  end if;

  -- Validated first, so the cast below only ever meets a boolean or nothing.
  -- Order is kept explicitly: jsonb_agg makes no promise about it otherwise.
  select coalesce(
           jsonb_agg(
             case
               when (element.entry ->> 'initiated')::boolean is true
                 then element.entry
               else element.entry - 'initiation_date' - 'diksha_guru'
             end
             order by element.position
           ),
           '[]'::jsonb
         )
  into children_details
  from jsonb_array_elements(children_details)
    with ordinality as element(entry, position);

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

do $$
begin
  raise notice 'children initiation applied';
end;
$$;
