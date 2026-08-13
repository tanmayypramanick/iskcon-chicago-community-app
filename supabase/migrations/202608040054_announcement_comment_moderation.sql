-- The devotee who posted a notice may moderate the conversation under it.
--
-- 202608040052_announcement_reactions.sql gave the noticeboard comments and
-- replies, and gave two people the right to take words down: whoever wrote
-- them, and any of the three who speak for the temple by way of
-- services.manage_recurring — Community Head, Tech Admin, President.
--
-- The temple has asked for a third, and the reasoning is theirs rather than
-- ours: a notice is the poster's. They wrote "the parking lot is closed
-- Sunday", four hundred devotees are reading it, and when the thread under it
-- turns into an argument the person standing at the board should be able to
-- tidy it up rather than waiting for a coordinator to wake up. Moderation that
-- needs a ticket is moderation that does not happen.
--
-- So the rule becomes, in full:
--
--   the author of the comment,
--   OR the devotee who posted the announcement that comment is on,
--   OR services.manage_recurring.
--
-- The whole subtlety of this file is the word "that". Posting one notice is not
-- a promotion. It buys authority over the conversation under *that* notice and
-- nothing else — a Community Head who steps down keeps the notices they put up
-- and keeps tidying those threads, and gains nothing over anybody else's. The
-- scoping is expressed structurally, by joining the comment to its own
-- announcement, so that the rule cannot be satisfied by "this devotee has
-- posted something, somewhere" — which is the shape this change would most
-- easily be got wrong in, and is mutation-tested for in the verification
-- script.
--
-- ---------------------------------------------------------------------------
-- One rule, one place, and why that is the point of this file.
--
-- The rule is enforced twice: delete_announcement_comment refuses it, and
-- list_announcement_comments reports it per row as can_remove so a client knows
-- whether to draw the Remove action. Those two must agree exactly. A button the
-- server then refuses is worse than no button — the devotee taps it, is told
-- no, and learns that the app lies — and a missing button on a comment they
-- were entitled to remove is the same failure read the other way.
--
-- Before this file they agreed by having the same boolean expression typed out
-- twice, which is agreement by luck and by memory. This change is exactly the
-- kind that breaks that: it touches both sides and adds a clause with a join in
-- it. So the rule moves into may_remove_announcement_comment() and both sides
-- call it. There is now no expression to keep in step, because there is only
-- one expression.
--
-- ---------------------------------------------------------------------------
-- Signatures.
--
-- Neither RPC changes shape. delete_announcement_comment(uuid) still returns
-- public.announcement_comments, and list_announcement_comments(uuid) still
-- returns the same ten columns in the same order and types — can_remove already
-- existed and only its meaning widens. So both are CREATE OR REPLACE, and no
-- DROP is needed or wanted: a drop would take the grants with it, and dropping
-- a function only to recreate it identically is how a defaulted overload gets
-- left behind and the next call becomes ambiguous. The one new object,
-- may_remove_announcement_comment(uuid), has never existed, so there is nothing
-- of its to drop either.
--
-- No table, column, index, policy or grant changes. Nothing here is a
-- migration of data; it is three function bodies.
--
-- Requires 202608040040_announcements.sql and
-- 202608040052_announcement_reactions.sql.

-- ---------------------------------------------------------------------------
-- 1. The rule.
--
--    Security definer, and deliberately so. Both callers are definer functions
--    already, and a definer function calling an invoker one runs it with the
--    definer's rights — so an invoker helper would answer one way from inside
--    list_announcement_comments and, if a client ever called it directly,
--    another way through the row level security policy on
--    announcement_comments, which hides removed rows. One rule that gives two
--    answers depending on who asked is not one rule. Definer everywhere means
--    the row it reasons about is always the row that is actually there.
--
--    deleted_at is null is part of the rule rather than an extra condition the
--    callers bolt on: there is nothing left to take down on a comment that has
--    already been taken down, and removing twice would rewrite deleted_by so
--    the record names the wrong person. can_remove has always been false on a
--    tombstone, and it stays false here.
--
--    The join is the scope. announcements is reached through this comment's own
--    announcement_id, so posted_by can only ever be the poster of the notice
--    this comment is on. A poster whose notice it is not never appears in this
--    query at all. Note also that a notice whose poster has since left the
--    congregation has posted_by null (0040 keeps the notice and drops the
--    attribution), and null = auth.uid() is null rather than true, so nobody
--    inherits an absent devotee's authority.
--
--    stable, not volatile: it reads and decides, and both callers are
--    themselves stable or read it once per row.
-- ---------------------------------------------------------------------------

create or replace function public.may_remove_announcement_comment(
  p_comment_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.announcement_comments
    join public.announcements
      on announcements.id = announcement_comments.announcement_id
    where announcement_comments.id = p_comment_id
      and announcement_comments.deleted_at is null
      and auth.uid() is not null
      and (
        -- Their own words.
        announcement_comments.author_id = auth.uid()
        -- Their own notice — and only their own; see the join above.
        or announcements.posted_by = auth.uid()
        -- The three who speak for the temple, anywhere on the board.
        or public.may_post_announcements()
      )
  )
$$;

comment on function public.may_remove_announcement_comment(uuid) is
  'Whether the viewer may take one announcement comment down: its author, the devotee who posted that announcement, or a Community Head, Tech Admin or President. False once it is already removed.';

revoke all on function public.may_remove_announcement_comment(uuid) from public, anon;
grant execute on function public.may_remove_announcement_comment(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. The guard.
--
--    Unchanged except for the rule and the sentence a devotee is shown when it
--    refuses them. The order of the checks matters and is kept: a missing
--    comment and an already-removed one are both reported as "could not be
--    found" before permission is considered at all, so a devotee cannot learn
--    from an error message whether a comment they may not touch exists, and a
--    second removal is still a not-found rather than a permission refusal.
--
--    The for update on the select is likewise kept. Two moderators reaching for
--    the same comment at the same moment must not both write deleted_by.
-- ---------------------------------------------------------------------------

create or replace function public.delete_announcement_comment(
  p_comment_id uuid
)
returns public.announcement_comments
language plpgsql
security definer
set search_path = ''
as $$
declare
  target public.announcement_comments;
  removed public.announcement_comments;
begin
  if auth.uid() is null then
    raise exception 'Sign in to remove a comment.';
  end if;

  select * into target from public.announcement_comments
  where announcement_comments.id = p_comment_id
  for update;

  if target.id is null or target.deleted_at is not null then
    raise exception 'That comment could not be found.';
  end if;

  if not public.may_remove_announcement_comment(target.id) then
    raise exception 'You can remove your own comment, any comment on an announcement you posted, or any comment at all if you are a Community Head, Tech Admin, or the President.';
  end if;

  update public.announcement_comments
  set deleted_at = now(),
      deleted_by = auth.uid()
  where announcement_comments.id = target.id
  returning * into removed;

  return removed;
end;
$$;

comment on function public.delete_announcement_comment(uuid) is
  'Soft-remove a comment or reply. The author may, so may the devotee who posted the announcement it sits under, and so may a Community Head, Tech Admin or President. The thread keeps its shape.';

revoke all on function public.delete_announcement_comment(uuid) from public, anon;
grant execute on function public.delete_announcement_comment(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. The flag.
--
--    Identical to 0052's in every other respect — same columns, same types,
--    same order, same thread ordering, same null body on a tombstone. The only
--    change is that can_remove is now the helper rather than a copy of the rule
--    written out again.
--
--    The client trusts this flag and must never re-derive it. That is not a
--    style preference: a phone cannot see role_permissions and would have to be
--    told the viewer's permissions to guess, which is both a second copy of the
--    rule and a second copy of the access model shipped to every device.
--
--    One function call per row rather than an inlined expression, and one index
--    probe with it. A definer function is not inlined by the planner, so this
--    is real work — and it is work on a thread, which is a handful of rows on a
--    temple noticeboard, against the comments primary key and the announcements
--    primary key. The row the helper looks up is the row the outer query has
--    already got in hand, so this is the cost of correctness stated plainly:
--    the alternative is the expression typed twice, and 0052's version of that
--    is precisely what this file is here to stop happening again.
-- ---------------------------------------------------------------------------

create or replace function public.list_announcement_comments(
  p_announcement_id uuid
)
returns table (
  id uuid,
  parent_comment_id uuid,
  author_id uuid,
  author_name text,
  author_photo_url text,
  body text,
  created_at timestamptz,
  deleted_at timestamptz,
  reply_count integer,
  can_remove boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    announcement_comments.id,
    announcement_comments.parent_comment_id,
    announcement_comments.author_id,
    author.name,
    author.photo_url,
    case when announcement_comments.deleted_at is null
      then announcement_comments.body end,
    announcement_comments.created_at,
    announcement_comments.deleted_at,
    (
      select count(*)::integer from public.announcement_comments reply
      where reply.parent_comment_id = announcement_comments.id
        and reply.deleted_at is null
    ),
    public.may_remove_announcement_comment(announcement_comments.id)
  from public.announcement_comments
  join public.users author on author.id = announcement_comments.author_id
  join public.announcement_comments root
    on root.id = coalesce(
      announcement_comments.parent_comment_id, announcement_comments.id
    )
  where auth.uid() is not null
    and announcement_comments.announcement_id = p_announcement_id
  order by
    root.created_at,
    root.id,
    (announcement_comments.parent_comment_id is not null),
    announcement_comments.created_at,
    announcement_comments.id
$$;

comment on function public.list_announcement_comments(uuid) is
  'One announcement''s thread: top-level comments oldest first, each followed by its replies. A removed comment keeps its place and returns a null body. can_remove is the server''s own answer, per row and per viewer.';

revoke all on function public.list_announcement_comments(uuid) from public, anon;
grant execute on function public.list_announcement_comments(uuid) to authenticated;

do $$
begin
  raise notice 'announcement comment moderation applied';
end;
$$;
