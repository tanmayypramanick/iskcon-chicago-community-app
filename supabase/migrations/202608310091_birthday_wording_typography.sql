-- The birthday greeting uses the temple's apostrophe.
-- Requires 202608310089_birthday_announcement_carries_the_devotee.sql.
--
-- One character, and the reason it is worth a migration: the app's own copy
-- was normalised to the typographic apostrophe (U+2019) so that a devotee
-- never sees two different marks on one screen. This wording is drawn on the
-- same screen as that copy — it opens the announcement composer — and it was
-- still using the straight ASCII quote, which is exactly the inconsistency
-- that normalisation was for.
--
-- Only the body text changes. The audience, the photograph and the refusal
-- for anybody without app.view_all are all as 0089 left them.

create or replace function public.suggested_birthday_announcement(
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

  -- they/them throughout, and nothing here reads gender.
  if v_name is null then
    title := 'Happy birthday!';
    body := 'One of our devotees celebrates their birthday today.' || chr(10) || chr(10)
      || 'Please join us in wishing them a very happy birthday. May Śrī Śrī '
      || 'Rādhā and Kṛṣṇa bless them with good health, steady devotion, and the '
      || 'association of devotees throughout the year ahead.' || chr(10) || chr(10)
      || 'Hare Kṛṣṇa!';
  else
    title := 'Happy birthday, ' || v_name || '!';
    -- U+2019, matching the app's copy rather than the ASCII quote.
    body := 'Today is ' || v_name || '’s birthday.' || chr(10) || chr(10)
      || 'Please join us in wishing them a very happy birthday. May Śrī Śrī '
      || 'Rādhā and Kṛṣṇa bless them with good health, steady devotion, and the '
      || 'association of devotees throughout the year ahead.' || chr(10) || chr(10)
      || 'Hare Kṛṣṇa!';
  end if;

  image_url := v_photo;

  return next;
end;
$$;

revoke all on function public.suggested_birthday_announcement(uuid) from public, anon;
grant execute on function public.suggested_birthday_announcement(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Proof, run at migration time. Seeded and rolled back, never deleted.
-- ---------------------------------------------------------------------------
do $$
declare
  v_pres uuid := '71000000-0000-0000-0000-000000000001';
  v_dev  uuid := '71000000-0000-0000-0000-000000000002';
  v_row record;
begin
  begin
    insert into auth.users (id, email, raw_user_meta_data) values
      (v_pres, 'ty-pres@example.test', jsonb_build_object('name', 'Typography President')),
      (v_dev,  'ty-dev@example.test',  jsonb_build_object('name', 'Ananda Das'));

    update public.users
    set role_id = (select id from public.roles where name = 'president')
    where id = v_pres;

    perform set_config('request.jwt.claim.sub', v_pres::text, true);
    select * into v_row from public.suggested_birthday_announcement(v_dev);
    perform set_config('request.jwt.claim.sub', '', true);

    if v_row.body not like '%Ananda Das’s birthday%' then
      raise exception 'the greeting does not use the typographic apostrophe: %', v_row.body;
    end if;
    if position('''s birthday' in v_row.body) > 0 then
      raise exception 'the straight apostrophe is still in the greeting';
    end if;

    raise exception 'ISKCON_PROOF_ROLLBACK';
  exception
    when others then
      if sqlerrm <> 'ISKCON_PROOF_ROLLBACK' then
        raise;
      end if;
  end;

  raise notice 'the birthday greeting uses the temple''s apostrophe';
end;
$$;
