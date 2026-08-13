-- How many things have been said in a sanga since you last looked.
--
-- Direct messages have carried an unread count since 202608040032_messaging.sql
-- — `messages.read_at` is stamped per row, and `list_my_conversations` counts
-- the ones still unstamped. Sangas had nothing of the kind: a devotee could
-- come back to a circle after a week and the row looked exactly as it did when
-- they left it.
--
-- A per-message read receipt is the wrong shape for a group. It would mean one
-- row per member per message — the temple's youth sanga alone would write
-- thousands a week — and it would answer a question nobody asked, "who has read
-- what". A group chat only needs a watermark: one timestamp per member per
-- sanga, saying how far down they have got. That is what WhatsApp shows on the
-- right of a row, and it is one row per membership rather than per message.
-- Requires 202608040043_sanga_powers.sql.

-- ---------------------------------------------------------------------------
-- 1. The watermark.
-- ---------------------------------------------------------------------------

create table if not exists public.sanga_reads (
  sanga_id uuid not null references public.sangas(id) on delete cascade,
  devotee_id uuid not null references public.users(id) on delete cascade,
  last_read_at timestamptz not null default now(),
  primary key (sanga_id, devotee_id)
);

comment on table public.sanga_reads is
  'How far down a sanga''s thread one devotee has read. One row per membership, written only by mark_sanga_read.';

comment on column public.sanga_reads.last_read_at is
  'Never moves backwards. Two of a devotee''s devices marking the same sanga read out of order must not resurrect a count they have already cleared.';

alter table public.sanga_reads enable row level security;

-- A watermark is nobody else's business, not even an overseer's: it says when
-- a devotee last opened a thread, which is a fact about them rather than about
-- what was said. app.view_all reaches the messages, not the reading of them.
drop policy if exists "Devotees read their own sanga watermarks" on public.sanga_reads;
create policy "Devotees read their own sanga watermarks"
  on public.sanga_reads for select to authenticated
  using (devotee_id = auth.uid());

-- Writes go through mark_sanga_read alone, so nothing beyond reading is
-- granted. A client that could write its own watermark could clear a count it
-- had not read, or set one in the future and never see a badge again.
revoke all on public.sanga_reads from anon, authenticated;
grant select on public.sanga_reads to authenticated;

-- ---------------------------------------------------------------------------
-- 2. The count itself, in one place.
--
--    Both list functions and mark_sanga_read ask this rather than each spelling
--    the rule out. The rule has four parts and every one of them has a reason:
--
--      * only for a member — an observer holding app.view_all is reading over
--        the top of a circle they are not in, and a badge would be telling them
--        to catch up on somebody else's conversation;
--      * never your own messages — you have read what you said;
--      * never a deleted message — a tombstone is not news;
--      * never anything said before you joined — see below.
--
--    The floor at joined_at is the answer to "what does a devotee who joins an
--    existing sanga see". They see zero, and the badge starts counting from
--    their first moment inside. The whole thread is still theirs to scroll —
--    list_sanga_messages hands over all of it — but two years of a study group
--    they joined this morning is not a debt, and a badge reading 4,812 is one
--    a devotee clears by never opening the sanga again.
--
--    greatest() rather than coalesce() alone, so the floor holds for a devotee
--    who left and was let back in: their old watermark is still on file and
--    would otherwise reopen every message said while they were away.
-- ---------------------------------------------------------------------------

create or replace function public.sanga_unread_count(p_sanga_id uuid)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select count(*)::integer
    from public.sanga_members membership
    left join public.sanga_reads marker
      on marker.sanga_id = membership.sanga_id
     and marker.devotee_id = membership.devotee_id
    join public.sanga_messages unread
      on unread.sanga_id = membership.sanga_id
     and unread.sender_id <> membership.devotee_id
     and unread.deleted_at is null
     and unread.created_at > greatest(
       membership.joined_at,
       coalesce(marker.last_read_at, membership.joined_at)
     )
    where membership.sanga_id = p_sanga_id
      and membership.devotee_id = auth.uid()
  ), 0)
$$;

revoke all on function public.sanga_unread_count(uuid) from public, anon;
grant execute on function public.sanga_unread_count(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Marking a sanga read.
--
--    Returns how many messages the mark cleared, so the client can leave its
--    caches alone when there was nothing to clear. The chat screen calls this
--    on focus and on every arriving message; an unconditional refresh would be
--    a round of RPCs per message received.
-- ---------------------------------------------------------------------------

create or replace function public.mark_sanga_read(p_sanga_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cleared integer;
begin
  -- An observer has no watermark to move. Their reading of a circle they are
  -- not in must not leave a trace in it, and giving them a row here would put
  -- one member's worth of state against a non-member.
  if not public.is_sanga_member(p_sanga_id) then
    raise exception 'Only devotees in this sanga can mark it read.';
  end if;

  v_cleared := public.sanga_unread_count(p_sanga_id);

  insert into public.sanga_reads (sanga_id, devotee_id, last_read_at)
  values (p_sanga_id, auth.uid(), now())
  on conflict (sanga_id, devotee_id) do update
    set last_read_at = greatest(
      public.sanga_reads.last_read_at,
      excluded.last_read_at
    );

  return v_cleared;
end;
$$;

revoke all on function public.mark_sanga_read(uuid) from public, anon;
grant execute on function public.mark_sanga_read(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. The count on the rows a devotee actually looks at.
--
--    Both functions gain one column, so both are dropped first. A create or
--    replace cannot change a return type, and a leftover overload is how this
--    repo has broken before: two candidates, and every call becomes ambiguous.
-- ---------------------------------------------------------------------------

drop function if exists public.list_sangas();
drop function if exists public.list_my_sangas();

create or replace function public.list_sangas()
returns table (
  id uuid,
  name text,
  description text,
  member_count integer,
  is_member boolean,
  is_admin boolean,
  request_status text,
  admin_id uuid,
  admin_name text,
  created_by uuid,
  created_by_name text,
  created_at timestamptz,
  unread_count integer
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    sangas.id,
    sangas.name,
    sangas.description,
    coalesce(tally.total, 0),
    exists (
      select 1 from public.sanga_members mine
      where mine.sanga_id = sangas.id and mine.devotee_id = auth.uid()
    ),
    exists (
      select 1 from public.sanga_members mine
      where mine.sanga_id = sangas.id
        and mine.devotee_id = auth.uid()
        and mine.role = 'admin'
    ),
    (
      select asked.status from public.sanga_join_requests asked
      where asked.sanga_id = sangas.id and asked.devotee_id = auth.uid()
      order by asked.created_at desc
      limit 1
    ),
    sangas.admin_id,
    runner.name,
    sangas.created_by,
    founder.name,
    sangas.created_at,
    public.sanga_unread_count(sangas.id)
  from public.sangas
  left join public.users founder on founder.id = sangas.created_by
  left join public.users runner on runner.id = sangas.admin_id
  left join lateral (
    select count(*)::integer as total
    from public.sanga_members
    where sanga_members.sanga_id = sangas.id
  ) tally on true
  where auth.uid() is not null
    and sangas.status = 'approved'
    and sangas.active
    and sangas.deleted_at is null
  order by sangas.name
$$;

-- A retired sanga stays here, because its admin has to be able to find it and
-- bring it back. A deleted one does not.
create or replace function public.list_my_sangas()
returns table (
  id uuid,
  name text,
  description text,
  status text,
  active boolean,
  review_note text,
  member_count integer,
  is_member boolean,
  is_admin boolean,
  admin_id uuid,
  admin_name text,
  created_at timestamptz,
  reviewed_at timestamptz,
  unread_count integer
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    sangas.id,
    sangas.name,
    sangas.description,
    sangas.status,
    sangas.active,
    sangas.review_note,
    coalesce(tally.total, 0),
    membership.devotee_id is not null,
    coalesce(membership.role = 'admin', false),
    sangas.admin_id,
    runner.name,
    sangas.created_at,
    sangas.reviewed_at,
    public.sanga_unread_count(sangas.id)
  from public.sangas
  left join public.users runner on runner.id = sangas.admin_id
  left join public.sanga_members membership
    on membership.sanga_id = sangas.id
   and membership.devotee_id = auth.uid()
  left join lateral (
    select count(*)::integer as total
    from public.sanga_members
    where sanga_members.sanga_id = sangas.id
  ) tally on true
  where auth.uid() is not null
    and sangas.deleted_at is null
    and (membership.devotee_id is not null or sangas.created_by = auth.uid())
  order by
    case when sangas.status = 'pending' then 0 else 1 end,
    sangas.name
$$;

revoke all on function public.list_sangas() from public, anon;
grant execute on function public.list_sangas() to authenticated;
revoke all on function public.list_my_sangas() from public, anon;
grant execute on function public.list_my_sangas() to authenticated;

do $$
begin
  raise notice 'sanga unread applied';
end;
$$;
