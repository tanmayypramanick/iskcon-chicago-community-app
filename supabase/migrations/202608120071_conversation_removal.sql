-- Remove a complete conversation from one devotee's Messages view without
-- destroying the temple's retained conversation record.
--
-- This is deliberately a per-devotee "clear" marker, not a DELETE. Messages
-- at or before cleared_at disappear for that devotee. A later incoming or
-- outgoing message makes the conversation reappear, beginning with the new
-- exchange. The President/Tech oversight RPC continues to read the complete
-- retained thread, including content retracted with "delete for everyone".

create table if not exists public.conversation_cleared_for (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  devotee_id uuid not null references public.users(id) on delete cascade,
  cleared_at timestamptz not null default now(),
  primary key (conversation_id, devotee_id)
);

comment on table public.conversation_cleared_for is
  'Per-devotee inbox clearing. It hides the existing thread from that devotee without deleting the retained temple record; a newer message makes it visible again.';

alter table public.conversation_cleared_for enable row level security;

drop policy if exists "Devotees read their own conversation clear markers"
  on public.conversation_cleared_for;
create policy "Devotees read their own conversation clear markers"
  on public.conversation_cleared_for for select to authenticated
  using (devotee_id = auth.uid());

revoke all on public.conversation_cleared_for from anon, authenticated;
grant select on public.conversation_cleared_for to authenticated;

create or replace function public.remove_conversation_for_me(p_conversation_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Sign in to remove a conversation.';
  end if;

  if not public.is_conversation_participant(p_conversation_id) then
    raise exception 'This conversation is not yours.';
  end if;

  insert into public.conversation_cleared_for (
    conversation_id, devotee_id, cleared_at
  ) values (
    p_conversation_id, auth.uid(), now()
  )
  on conflict (conversation_id, devotee_id) do update
    set cleared_at = excluded.cleared_at;
end;
$$;

comment on function public.remove_conversation_for_me(uuid) is
  'Clears the existing thread from the caller only. No message or retained content is deleted; a message created after the marker makes the thread reappear.';

revoke all on function public.remove_conversation_for_me(uuid) from public, anon;
grant execute on function public.remove_conversation_for_me(uuid) to authenticated;

-- A participant reads only messages they have not hidden individually and
-- only messages newer than their own whole-conversation clear marker. The
-- authorised oversight function is SECURITY DEFINER and remains deliberately
-- independent of this participant-facing policy.
drop policy if exists "Devotees read messages in their conversations"
  on public.messages;
create policy "Devotees read messages in their conversations"
  on public.messages for select to authenticated
  using (
    public.is_conversation_participant(conversation_id)
    and not exists (
      select 1
      from public.message_hidden_for hidden
      where hidden.message_id = messages.id
        and hidden.devotee_id = auth.uid()
    )
    and not exists (
      select 1
      from public.conversation_cleared_for cleared
      where cleared.conversation_id = messages.conversation_id
        and cleared.devotee_id = auth.uid()
        and messages.created_at <= cleared.cleared_at
    )
  );

-- Keep the conversation list and the opened thread on exactly the same
-- visibility rule. A conversation that has been cleared stays absent until a
-- new visible message exists. An ordinary newly opened empty conversation is
-- still listed so the devotee can write the first message.
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
    conversation.id,
    other.id,
    other.name,
    other.photo_url,
    role.name,
    coalesce(latest.created_at, conversation.last_message_at),
    latest.body,
    latest.sender_id,
    coalesce(latest.deleted_at is not null, false),
    coalesce(latest.image_url is not null, false),
    coalesce((
      select count(*)::integer
      from public.messages unread
      where unread.conversation_id = conversation.id
        and unread.sender_id <> auth.uid()
        and unread.read_at is null
        and unread.deleted_at is null
        and not exists (
          select 1
          from public.message_hidden_for hidden_unread
          where hidden_unread.message_id = unread.id
            and hidden_unread.devotee_id = auth.uid()
        )
        and (
          cleared.cleared_at is null
          or unread.created_at > cleared.cleared_at
        )
    ), 0)
  from public.conversations conversation
  join public.users other
    on other.id = case
      when conversation.lower_devotee_id = auth.uid()
        then conversation.higher_devotee_id
      else conversation.lower_devotee_id
    end
  join public.roles role on role.id = other.role_id
  left join public.conversation_cleared_for cleared
    on cleared.conversation_id = conversation.id
   and cleared.devotee_id = auth.uid()
  left join lateral (
    select
      message.id,
      message.body,
      message.sender_id,
      message.deleted_at,
      message.image_url,
      message.created_at
    from public.messages message
    where message.conversation_id = conversation.id
      and not exists (
        select 1
        from public.message_hidden_for hidden
        where hidden.message_id = message.id
          and hidden.devotee_id = auth.uid()
      )
      and (
        cleared.cleared_at is null
        or message.created_at > cleared.cleared_at
      )
    order by message.created_at desc
    limit 1
  ) latest on true
  where (
    conversation.lower_devotee_id = auth.uid()
    or conversation.higher_devotee_id = auth.uid()
  )
  and (cleared.cleared_at is null or latest.id is not null)
  order by coalesce(latest.created_at, conversation.last_message_at) desc
$$;

revoke all on function public.list_my_conversations() from public, anon;
grant execute on function public.list_my_conversations() to authenticated;

do $$
begin
  raise notice 'conversation removal applied';
end;
$$;
