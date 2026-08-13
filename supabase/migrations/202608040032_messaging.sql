-- Devotees can write to one another.
--
-- A temple runs on people talking. Until now the app could tell a devotee what
-- to do and when, but gave them no way to ask a question, arrange a lift, or
-- say thank you. This adds direct messages: one conversation per pair, with
-- images, read receipts and deletion.
--
-- On oversight: a small number of authorised members can read conversations,
-- because a temple has a duty of care towards the people in it — particularly
-- where young devotees are involved. That is disclosed to devotees in the
-- privacy screen rather than hidden, which is both the honest thing and the
-- lawful one in Illinois.
-- Requires 202608040031_access_approver.sql.

-- ---------------------------------------------------------------------------
-- 1. One conversation per pair of devotees.
--
--    The pair is stored sorted, so "A talking to B" and "B talking to A" can
--    never become two separate threads.
-- ---------------------------------------------------------------------------

create table if not exists public.conversations (
  id uuid primary key default gen_random_uuid(),
  lower_devotee_id uuid not null references public.users(id) on delete cascade,
  higher_devotee_id uuid not null references public.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  last_message_at timestamptz not null default now(),
  constraint conversation_pair_ordered check (lower_devotee_id < higher_devotee_id),
  constraint conversation_pair_unique unique (lower_devotee_id, higher_devotee_id)
);

create index if not exists conversations_lower_idx
  on public.conversations(lower_devotee_id, last_message_at desc);
create index if not exists conversations_higher_idx
  on public.conversations(higher_devotee_id, last_message_at desc);

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_id uuid not null references public.users(id) on delete cascade,
  body text,
  image_url text,
  created_at timestamptz not null default now(),
  read_at timestamptz,
  deleted_at timestamptz,
  constraint message_has_content check (
    deleted_at is not null
    or nullif(trim(coalesce(body, '')), '') is not null
    or image_url is not null
  )
);

create index if not exists messages_conversation_idx
  on public.messages(conversation_id, created_at desc);

alter table public.conversations enable row level security;
alter table public.messages enable row level security;

-- ---------------------------------------------------------------------------
-- 2. Who may read what.
-- ---------------------------------------------------------------------------

create or replace function public.is_conversation_participant(p_conversation_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.conversations
    where id = p_conversation_id
      and (lower_devotee_id = auth.uid() or higher_devotee_id = auth.uid())
  )
$$;

revoke all on function public.is_conversation_participant(uuid) from public, anon;
grant execute on function public.is_conversation_participant(uuid) to authenticated;

drop policy if exists "Devotees read their own conversations" on public.conversations;
create policy "Devotees read their own conversations"
  on public.conversations for select to authenticated
  using (
    lower_devotee_id = auth.uid()
    or higher_devotee_id = auth.uid()
    or public.has_permission('app.view_all')
  );

drop policy if exists "Devotees read messages in their conversations" on public.messages;
create policy "Devotees read messages in their conversations"
  on public.messages for select to authenticated
  using (
    public.is_conversation_participant(conversation_id)
    or public.has_permission('app.view_all')
  );

grant select on public.conversations to authenticated;
grant select on public.messages to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Opening a conversation and sending.
-- ---------------------------------------------------------------------------

create or replace function public.open_conversation(p_devotee_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  lower_id uuid;
  higher_id uuid;
  conversation_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Sign in to send a message.';
  end if;
  if p_devotee_id = auth.uid() then
    raise exception 'You cannot message yourself.';
  end if;
  if not exists (select 1 from public.users where id = p_devotee_id) then
    raise exception 'That devotee could not be found.';
  end if;

  lower_id := least(auth.uid(), p_devotee_id);
  higher_id := greatest(auth.uid(), p_devotee_id);

  insert into public.conversations (lower_devotee_id, higher_devotee_id)
  values (lower_id, higher_id)
  on conflict (lower_devotee_id, higher_devotee_id) do update
    set last_message_at = public.conversations.last_message_at
  returning id into conversation_id;

  return conversation_id;
end;
$$;

revoke all on function public.open_conversation(uuid) from public, anon;
grant execute on function public.open_conversation(uuid) to authenticated;

create or replace function public.send_message(
  p_conversation_id uuid,
  p_body text default null,
  p_image_url text default null
)
returns public.messages
language plpgsql
security definer
set search_path = ''
as $$
declare
  sent public.messages;
begin
  if not public.is_conversation_participant(p_conversation_id) then
    raise exception 'This conversation is not yours.';
  end if;
  if nullif(trim(coalesce(p_body, '')), '') is null and p_image_url is null then
    raise exception 'Write something or attach a picture.';
  end if;

  insert into public.messages (conversation_id, sender_id, body, image_url)
  values (
    p_conversation_id, auth.uid(),
    nullif(trim(coalesce(p_body, '')), ''), p_image_url
  )
  returning * into sent;

  update public.conversations
  set last_message_at = sent.created_at
  where id = p_conversation_id;

  return sent;
end;
$$;

revoke all on function public.send_message(uuid, text, text) from public, anon;
grant execute on function public.send_message(uuid, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Read receipts and deletion.
-- ---------------------------------------------------------------------------

create or replace function public.mark_conversation_read(p_conversation_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  marked integer;
begin
  if not public.is_conversation_participant(p_conversation_id) then
    raise exception 'This conversation is not yours.';
  end if;

  -- Only the other devotee's messages are marked: your own are read by
  -- definition, and stamping them would make the tick meaningless.
  update public.messages
  set read_at = now()
  where conversation_id = p_conversation_id
    and sender_id <> auth.uid()
    and read_at is null;
  get diagnostics marked = row_count;
  return marked;
end;
$$;

revoke all on function public.mark_conversation_read(uuid) from public, anon;
grant execute on function public.mark_conversation_read(uuid) to authenticated;

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
    raise exception 'You can only delete your own messages.';
  end if;

  -- Soft delete: the row stays so the thread keeps its shape and the temple's
  -- record remains whole, but the content is gone.
  update public.messages
  set deleted_at = now(), body = null, image_url = null
  where id = p_message_id
  returning * into updated;
  return updated;
end;
$$;

revoke all on function public.delete_message(uuid) from public, anon;
grant execute on function public.delete_message(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. The conversation list, newest activity first.
-- ---------------------------------------------------------------------------

create or replace function public.list_my_conversations()
returns table (
  id uuid,
  other_devotee_id uuid,
  other_name text,
  other_photo_url text,
  other_role text,
  last_message_at timestamptz,
  last_body text,
  last_sender_id uuid,
  last_deleted boolean,
  last_has_image boolean,
  unread_count integer
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    conversations.id,
    other.id,
    other.name,
    other.photo_url,
    roles.name,
    conversations.last_message_at,
    latest.body,
    latest.sender_id,
    latest.deleted_at is not null,
    latest.image_url is not null,
    coalesce((
      select count(*)::integer from public.messages unread
      where unread.conversation_id = conversations.id
        and unread.sender_id <> auth.uid()
        and unread.read_at is null
        and unread.deleted_at is null
    ), 0)
  from public.conversations
  join public.users other
    on other.id = case
      when conversations.lower_devotee_id = auth.uid()
        then conversations.higher_devotee_id
      else conversations.lower_devotee_id
    end
  join public.roles on roles.id = other.role_id
  left join lateral (
    select body, sender_id, deleted_at, image_url
    from public.messages
    where conversation_id = conversations.id
    order by created_at desc
    limit 1
  ) latest on true
  where conversations.lower_devotee_id = auth.uid()
     or conversations.higher_devotee_id = auth.uid()
  order by conversations.last_message_at desc
$$;

revoke all on function public.list_my_conversations() from public, anon;
grant execute on function public.list_my_conversations() to authenticated;

-- ---------------------------------------------------------------------------
-- 6. What one devotee may see of another.
--
--    Name, photo, access level, email and date of birth — enough to recognise
--    somebody and reach them. Address, phone and the spiritual details stay
--    private to the devotee and to authorised members.
-- ---------------------------------------------------------------------------

create or replace function public.devotee_public_profile(p_devotee_id uuid)
returns table (
  id uuid,
  name text,
  email text,
  photo_url text,
  role_name text,
  joined_at timestamptz,
  date_of_birth date,
  phone text,
  birth_place text,
  address text,
  spiritual_mentor text,
  is_initiated boolean,
  diksha_guru text,
  can_see_everything boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    users.id, users.name, users.email, users.photo_url, roles.name,
    users.joined_at, users.date_of_birth,
    case when privileged then users.phone end,
    case when privileged then users.birth_place end,
    case when privileged then users.address end,
    case when privileged then users.spiritual_mentor end,
    case when privileged then users.is_initiated end,
    case when privileged then users.diksha_guru end,
    privileged
  from public.users
  join public.roles on roles.id = users.role_id
  cross join lateral (
    select (users.id = auth.uid() or public.has_permission('app.view_all')) as privileged
  ) as visibility
  where auth.uid() is not null and users.id = p_devotee_id
$$;

revoke all on function public.devotee_public_profile(uuid) from public, anon;
grant execute on function public.devotee_public_profile(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 7. Oversight: conversations across the temple.
-- ---------------------------------------------------------------------------

create or replace function public.list_all_conversations()
returns table (
  id uuid,
  first_devotee_id uuid,
  first_name text,
  second_devotee_id uuid,
  second_name text,
  message_count integer,
  last_message_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    conversations.id,
    lower_person.id, lower_person.name,
    higher_person.id, higher_person.name,
    coalesce((
      select count(*)::integer from public.messages
      where conversation_id = conversations.id
    ), 0),
    conversations.last_message_at
  from public.conversations
  join public.users lower_person on lower_person.id = conversations.lower_devotee_id
  join public.users higher_person on higher_person.id = conversations.higher_devotee_id
  where public.has_permission('app.view_all')
  order by conversations.last_message_at desc
$$;

revoke all on function public.list_all_conversations() from public, anon;
grant execute on function public.list_all_conversations() to authenticated;

-- ---------------------------------------------------------------------------
-- 8. Pictures in messages.
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'message-images', 'message-images', true, 8388608,
  array['image/jpeg', 'image/png', 'image/webp', 'image/heic']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Devotees upload their own message images" on storage.objects;
create policy "Devotees upload their own message images"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'message-images'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "Anyone signed in reads message images" on storage.objects;
create policy "Anyone signed in reads message images"
  on storage.objects for select to authenticated
  using (bucket_id = 'message-images');

-- ---------------------------------------------------------------------------
-- 9. Messages arrive live.
-- ---------------------------------------------------------------------------

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and tablename = 'messages'
    ) then
      alter publication supabase_realtime add table public.messages;
    end if;
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and tablename = 'conversations'
    ) then
      alter publication supabase_realtime add table public.conversations;
    end if;
  end if;
end;
$$;

do $$
begin
  raise notice 'messaging applied';
end;
$$;
