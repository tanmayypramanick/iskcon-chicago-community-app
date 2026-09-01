-- A birthday announcement carries the devotee's face and the temple's words.
-- Requires 202608040053_birthday_prompts.sql.
--
-- 0053 already put the privacy where the temple wants it: announce_birthdays
-- was dropped, prompt_birthday_wishes tells only holders of app.view_all — the
-- President and the Tech Admin — and nothing is ever posted without a person
-- pressing Post. None of that changes here.
--
-- What changes is what the composer opens with. It opened with a title and a
-- body; a greeting that goes to the whole congregation should show whose
-- birthday it is, so this hands back the devotee's photograph as well, ready
-- to be posted or removed. The wording is warmer and carries the temple's
-- diacritics, because the app renders them properly (the bundled EB Garamond
-- and Source Sans faces cover Latin Extended Additional, so Kṛṣṇa does not
-- fall back to a heavier face mid-word).
--
-- Still only ever a starting point. Both fields and the photograph are
-- editable in the composer, and the announcement goes through
-- create_announcement like any other notice, under the name of whoever posted
-- it.
--
-- Dropped and recreated rather than replaced: the OUT parameters change, and
-- create or replace cannot change a function's result shape.

drop function if exists public.suggested_birthday_announcement(uuid);

create function public.suggested_birthday_announcement(
  p_devotee_id uuid
)
returns table (
  title text,
  body text,
  image_url text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_name text;
  v_photo text;
begin
  if auth.uid() is null then
    raise exception 'Sign in to write a birthday announcement.';
  end if;

  if not public.has_permission('app.view_all') then
    raise exception 'Only the President or the Tech Admin can see whose birthday it is.';
  end if;

  select
    nullif(trim(coalesce(users.name, '')), ''),
    nullif(trim(coalesce(users.photo_url, '')), '')
  into v_name, v_photo
  from public.users
  where users.id = p_devotee_id;

  if not found then
    raise exception 'That devotee could not be found.';
  end if;

  -- they/them throughout, and nothing here reads gender: 0044 made that call
  -- for the notification and it holds all the more for a notice that goes on
  -- the noticeboard under somebody's name.
  if v_name is null then
    -- A row with no usable name. Rare, and no reason to hand back a greeting
    -- addressed to an empty string.
    title := 'Happy birthday!';
    body := 'One of our devotees celebrates their birthday today.' || chr(10) || chr(10)
      || 'Please join us in wishing them a very happy birthday. May Śrī Śrī '
      || 'Rādhā and Kṛṣṇa bless them with good health, steady devotion, and the '
      || 'association of devotees throughout the year ahead.' || chr(10) || chr(10)
      || 'Hare Kṛṣṇa!';
  else
    title := 'Happy birthday, ' || v_name || '!';
    body := 'Today is ' || v_name || '''s birthday.' || chr(10) || chr(10)
      || 'Please join us in wishing them a very happy birthday. May Śrī Śrī '
      || 'Rādhā and Kṛṣṇa bless them with good health, steady devotion, and the '
      || 'association of devotees throughout the year ahead.' || chr(10) || chr(10)
      || 'Hare Kṛṣṇa!';
  end if;

  -- The devotee's own photograph, exactly as users.photo_url holds it. It is a
  -- reference into a private bucket (202608310088), not a fetchable URL — the
  -- app signs it before rendering. Null where they have not added one, and the
  -- composer simply opens without a picture.
  image_url := v_photo;

  return next;
end;
$$;

comment on function public.suggested_birthday_announcement(uuid) is
  'The prefilled title, wording and photograph for a birthday announcement, for the President and the Tech Admin to edit before posting. Refuses everybody else. Posts nothing.';

revoke all on function public.suggested_birthday_announcement(uuid) from public, anon;
grant execute on function public.suggested_birthday_announcement(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Proof, run at migration time.
-- ---------------------------------------------------------------------------
do $$
declare
  v_president uuid := '6c000000-0000-0000-0000-000000000001';
  v_devotee   uuid := '6c000000-0000-0000-0000-000000000002';
  v_plain     uuid := '6c000000-0000-0000-0000-000000000003';
  v_row record;
  v_refused boolean := false;
begin
  -- Seeded and then rolled back by a sentinel rather than deleted. Removing a
  -- seeded devotee cascades, and public.devotee_awards refuses DELETE outright
  -- by design (0055), so a proof that tidies up with DELETEs is one recompute
  -- away from failing the migration on a database with a real congregation.
  begin
    insert into auth.users (id, email, raw_user_meta_data) values
      (v_president, 'bd-president@example.test', jsonb_build_object('name', 'Birthday President')),
      (v_devotee,   'bd-devotee@example.test',   jsonb_build_object('name', 'Ananda Das')),
      (v_plain,     'bd-plain@example.test',     jsonb_build_object('name', 'Plain Devotee'));

    update public.users
    set role_id = (select id from public.roles where name = 'president')
    where id = v_president;

    update public.users
    set photo_url =
      'https://example.supabase.co/storage/v1/object/public/devotee-photos/'
      || v_devotee::text || '/face.jpg'
    where id = v_devotee;

    -- The President gets the words and the face.
    perform set_config('request.jwt.claim.sub', v_president::text, true);
    select * into v_row from public.suggested_birthday_announcement(v_devotee);

    if v_row.title is distinct from 'Happy birthday, Ananda Das!' then
      raise exception 'the suggested title reads "%"', v_row.title;
    end if;
    if v_row.image_url is null or v_row.image_url not like '%devotee-photos%' then
      raise exception
        'the birthday announcement does not carry the devotee''s photograph (%)',
        v_row.image_url;
    end if;
    if v_row.body not like '%Hare Kṛṣṇa!%' then
      raise exception 'the temple''s wording is missing from the body';
    end if;

    -- An ordinary devotee is refused outright, as before.
    perform set_config('request.jwt.claim.sub', v_plain::text, true);
    begin
      perform public.suggested_birthday_announcement(v_devotee);
    exception when others then
      v_refused := true;
    end;
    perform set_config('request.jwt.claim.sub', '', true);

    if not v_refused then
      raise exception
        'an ordinary devotee was handed the birthday wording; birthdays are for the President and Tech Admin only';
    end if;

    raise exception 'ISKCON_PROOF_ROLLBACK';
  exception
    when others then
      if sqlerrm <> 'ISKCON_PROOF_ROLLBACK' then
        raise;
      end if;
  end;

  raise notice 'the birthday composer opens with the devotee''s face and the temple''s words';
end;
$$;
