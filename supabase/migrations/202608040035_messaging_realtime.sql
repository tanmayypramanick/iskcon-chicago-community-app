-- Messages arrive at once, and deleting means two different things.
--
-- Two problems this fixes.
--
-- 1. Realtime was slow. A filtered postgres_changes subscription on an
--    RLS-protected table cannot evaluate its filter from the default replica
--    identity, which carries only the primary key. Without REPLICA IDENTITY
--    FULL the change either arrives late or not at all, and the thread only
--    caught up on the next poll.
--
-- 2. Deleting removed a message for both devotees, always. WhatsApp's two
--    choices exist because they answer different needs: "delete for me" tidies
--    your own view, "delete for everyone" retracts what you said.
-- Requires 202608040034_profile_community.sql.

alter table public.messages replica identity full;
alter table public.conversations replica identity full;

-- ---------------------------------------------------------------------------
-- Delivered, as distinct from read.
-- ---------------------------------------------------------------------------

alter table public.messages
  add column if not exists delivered_at timestamptz;

comment on column public.messages.delivered_at is
  'Set when the recipient''s device has the message. Read is a separate, later thing.';

-- ---------------------------------------------------------------------------
-- Hiding a message for yourself only.
-- ---------------------------------------------------------------------------

create table if not exists public.message_hidden_for (
  message_id uuid not null references public.messages(id) on delete cascade,
  devotee_id uuid not null references public.users(id) on delete cascade,
  hidden_at timestamptz not null default now(),
  primary key (message_id, devotee_id)
);

alter table public.message_hidden_for enable row level security;

drop policy if exists "Devotees read their own hidden markers" on public.message_hidden_for;
create policy "Devotees read their own hidden markers"
  on public.message_hidden_for for select to authenticated
  using (devotee_id = auth.uid());

grant select on public.message_hidden_for to authenticated;

create or replace function public.hide_message_for_me(p_message_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.messages
    where id = p_message_id
      and public.is_conversation_participant(conversation_id)
  ) then
    raise exception 'That message is not in one of your conversations.';
  end if;

  insert into public.message_hidden_for (message_id, devotee_id)
  values (p_message_id, auth.uid())
  on conflict do nothing;
end;
$$;

revoke all on function public.hide_message_for_me(uuid) from public, anon;
grant execute on function public.hide_message_for_me(uuid) to authenticated;

-- Delete for everyone keeps the row (the thread keeps its shape, and the
-- temple's record stays whole) but clears what was said.
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
-- Marking delivery. Cheap, and it is what separates one tick from two.
-- ---------------------------------------------------------------------------

create or replace function public.mark_conversation_delivered(p_conversation_id uuid)
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

  update public.messages
  set delivered_at = now()
  where conversation_id = p_conversation_id
    and sender_id <> auth.uid()
    and delivered_at is null;
  get diagnostics marked = row_count;
  return marked;
end;
$$;

revoke all on function public.mark_conversation_delivered(uuid) from public, anon;
grant execute on function public.mark_conversation_delivered(uuid) to authenticated;

do $$
begin
  raise notice 'messaging realtime applied';
end;
$$;
