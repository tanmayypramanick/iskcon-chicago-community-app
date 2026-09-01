-- Only the devotee who posted a darshan, a Tech Admin, or the President may
-- replace or remove it.
-- Requires 202608290079_darshan_week_and_voice.sql.
--
-- The temple's rule for Daily Darshan is: Community Heads, Tech Admin and the
-- President may post; the devotee who posted it, plus the President and Tech
-- Admin, may delete it. Two paths let any Community Head act on any other
-- Head's day.
--
--   * delete_daily_darshan allowed `posted_by = auth.uid() or
--     may_post_daily_darshan()`, and may_post_daily_darshan is all three
--     posting roles — so every Community Head could delete every darshan.
--   * publish_daily_darshan's upsert UPDATEd whatever row already existed for
--     the day, reassigned posted_by to the caller, and then deleted that row's
--     images. Head B posting Tuesday without realising Head A already had
--     wiped A's five photographs and left A no longer the poster. It never
--     called itself a delete, which is why the delete rule never covered it.
--
-- Both now ask the same question: is this yours, or do you hold app.view_all?

create or replace function public.publish_daily_darshan(
  p_darshan_on date,
  p_note text,
  p_images jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_existing_poster uuid;
  v_today date := (now() at time zone 'America/Chicago')::date;
  v_floor date := public.daily_darshan_week_floor();
  v_min integer := public.daily_darshan_limit('daily_darshan.min_images');
  v_max integer := public.daily_darshan_limit('daily_darshan.max_images');
  v_max_note integer := public.daily_darshan_limit('daily_darshan.max_note_chars');
  v_max_credit integer := public.daily_darshan_limit('daily_darshan.max_credit_chars');
  v_backdate integer := public.daily_darshan_limit('daily_darshan.max_backdate_days');
  v_note text;
  v_count integer;
  v_darshan_id uuid;
  v_created boolean := false;
  v_title text;
  v_body text;
  v_image record;
begin
  if auth.uid() is null then
    raise exception 'Sign in to post the Daily Darshan.';
  end if;

  if not public.may_post_daily_darshan() then
    raise exception 'Only a Community Head, Tech Admin, or the President can post the Daily Darshan.';
  end if;

  if p_darshan_on is null then
    raise exception 'Please say which day this darshan is for.';
  end if;

  -- Chicago, not UTC and not the caller's timezone. See 0078's header.
  if p_darshan_on > v_today then
    raise exception 'The Daily Darshan cannot be posted for a day that has not happened yet.';
  end if;

  if p_darshan_on < v_today - v_backdate then
    raise exception 'The Daily Darshan can only be posted for the last % days.', v_backdate;
  end if;

  if p_darshan_on < v_floor then
    raise exception
      'The Daily Darshan gallery holds this week only, from % onwards. A darshan for % would be cleared straight away.',
      v_floor, p_darshan_on;
  end if;

  v_note := nullif(trim(coalesce(p_note, '')), '');
  if v_note is not null and length(v_note) > v_max_note then
    raise exception 'The darshan note is longer than % characters.', v_max_note;
  end if;

  if p_images is null or jsonb_typeof(p_images) <> 'array' then
    raise exception 'The darshan pictures must be given as a list.';
  end if;

  v_count := jsonb_array_length(p_images);

  if v_count < v_min then
    raise exception 'A darshan needs at least % picture(s).', v_min;
  end if;
  if v_count > v_max then
    raise exception 'A darshan can have at most % pictures; % were given.', v_max, v_count;
  end if;

  for v_image in
    select
      nullif(trim(coalesce(entry.value ->> 'imageUrl', '')), '') as image_url,
      nullif(trim(coalesce(entry.value ->> 'deity', '')), '') as deity,
      nullif(trim(coalesce(entry.value ->> 'dressedBy', '')), '') as dressed_by,
      coalesce(
        nullif(trim(coalesce(entry.value ->> 'position', '')), '')::integer,
        entry.ordinality::integer
      ) as slot,
      entry.ordinality as nth
    from jsonb_array_elements(p_images) with ordinality as entry(value, ordinality)
  loop
    if v_image.image_url is null then
      raise exception 'Picture % has no photo.', v_image.nth;
    end if;

    if v_image.image_url !~ '^https://[a-z0-9.-]+/storage/v1/object/public/message-images/' then
      raise exception 'A darshan photo must be uploaded through the app.';
    end if;

    if v_image.slot < 0 then
      raise exception 'Picture % has a negative position.', v_image.nth;
    end if;

    if v_image.deity is not null and length(v_image.deity) > v_max_credit then
      raise exception 'A deity name is longer than % characters.', v_max_credit;
    end if;

    if v_image.dressed_by is not null and length(v_image.dressed_by) > v_max_credit then
      raise exception 'A "dressed by" name is longer than % characters.', v_max_credit;
    end if;
  end loop;

  select count(*)::integer into v_count
  from (
    select distinct coalesce(
      nullif(trim(coalesce(entry.value ->> 'position', '')), '')::integer,
      entry.ordinality::integer
    ) as slot
    from jsonb_array_elements(p_images) with ordinality as entry(value, ordinality)
  ) as slots;

  if v_count <> jsonb_array_length(p_images) then
    raise exception 'Two darshan pictures were given the same position.';
  end if;

  -- Whose day this already is decides whether it may be replaced. A second
  -- Community Head posting the same day used to silently UPDATE the first
  -- one's row, take over posted_by, and delete their pictures — deletion by
  -- another name, and the temple's rule is that only the devotee who posted
  -- it, a Tech Admin or the President may remove a darshan.
  select daily_darshan.posted_by into v_existing_poster
  from public.daily_darshan
  where daily_darshan.darshan_on = p_darshan_on;

  if found
     and v_existing_poster is distinct from auth.uid()
     and not public.has_permission('app.view_all')
  then
    raise exception
      'Today''s darshan has already been posted by another devotee. Ask them, a Tech Admin, or the President to change it.';
  end if;

  loop
    update public.daily_darshan
    set note = v_note,
        posted_by = auth.uid(),
        updated_at = now()
    where daily_darshan.darshan_on = p_darshan_on
    returning daily_darshan.id into v_darshan_id;

    exit when found;

    begin
      insert into public.daily_darshan (darshan_on, note, posted_by)
      values (p_darshan_on, v_note, auth.uid())
      returning daily_darshan.id into v_darshan_id;
      v_created := true;
      exit;
    exception when unique_violation then
      null;
    end;
  end loop;

  delete from public.daily_darshan_images
  where daily_darshan_images.darshan_id = v_darshan_id;

  insert into public.daily_darshan_images (
    darshan_id, image_url, deity, dressed_by, "position"
  )
  select
    v_darshan_id,
    nullif(trim(coalesce(entry.value ->> 'imageUrl', '')), ''),
    nullif(trim(coalesce(entry.value ->> 'deity', '')), ''),
    nullif(trim(coalesce(entry.value ->> 'dressedBy', '')), ''),
    coalesce(
      nullif(trim(coalesce(entry.value ->> 'position', '')), '')::integer,
      entry.ordinality::integer
    )
  from jsonb_array_elements(p_images) with ordinality as entry(value, ordinality);

  if v_created then
    -- Composed after the pictures are in, because the wording is about the
    -- Deities in them. Nothing here reads who is posting.
    select notice.title, notice.body into v_title, v_body
    from public.daily_darshan_notification_text(p_darshan_on) as notice;

    -- One statement for the whole congregation, not one round trip each.
    --
    -- This was a row-at-a-time loop calling queue_app_notification, and every
    -- one of those inserts fires the deliver_app_notification AFTER INSERT
    -- trigger, which queues its own net.http_post. With a congregation of a
    -- couple of thousand the Community Head watched "Post" spin and then hit
    -- the statement timeout — after having already uploaded five photographs.
    -- notify_sanga_message_received (202608120072) does the same job as a
    -- single insert…select; that pattern is simply used here too.
    insert into public.app_notifications (user_id, kind, title, body, data)
    select
      users.id,
      'darshan_posted',
      v_title,
      v_body,
      jsonb_build_object('darshanId', v_darshan_id, 'darshanOn', p_darshan_on)
    from public.users
    where users.id <> auth.uid();
  end if;

  return v_darshan_id;
end;
$$;

-- The delete rule, narrowed to match. `may_post_daily_darshan()` is who may
-- POST; it was never the right answer to who may remove somebody else's.
-- Identical to 202608290078's version but for the permission clause.
create or replace function public.delete_daily_darshan(p_id uuid)
returns public.daily_darshan
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_target public.daily_darshan;
begin
  if auth.uid() is null then
    raise exception 'Sign in to remove a darshan.';
  end if;

  select * into v_target
  from public.daily_darshan
  where daily_darshan.id = p_id
  for update;

  if v_target.id is null then
    raise exception 'That darshan could not be found.';
  end if;

  if v_target.posted_by is distinct from auth.uid()
     and not public.has_permission('app.view_all')
  then
    raise exception 'You can remove your own darshan. A Tech Admin or the President can remove any.';
  end if;

  delete from public.daily_darshan where daily_darshan.id = v_target.id;

  return v_target;
end;
$$;

comment on function public.delete_daily_darshan(uuid) is
  'Removes one day''s darshan and, by cascade, its picture rows. Only the devotee who posted it, a Tech Admin or the President. The files stay in message-images.';

revoke all on function public.delete_daily_darshan(uuid) from public, anon;
grant execute on function public.delete_daily_darshan(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Proof, run at migration time.
-- ---------------------------------------------------------------------------
do $$
begin
  if pg_get_functiondef('public.delete_daily_darshan(uuid)'::regprocedure)
     like '%may_post_daily_darshan()%'
  then
    raise exception
      'delete_daily_darshan still lets every Community Head remove another Head''s darshan';
  end if;

  if pg_get_functiondef('public.delete_daily_darshan(uuid)'::regprocedure)
     not like '%app.view_all%'
  then
    raise exception 'delete_daily_darshan no longer names app.view_all';
  end if;

  if pg_get_functiondef(
       'public.publish_daily_darshan(date, text, jsonb)'::regprocedure
     ) not like '%already been posted by another devotee%'
  then
    raise exception
      'publish_daily_darshan can still overwrite another Head''s day silently';
  end if;

  raise notice 'a darshan belongs to whoever posted it';
end;
$$;
