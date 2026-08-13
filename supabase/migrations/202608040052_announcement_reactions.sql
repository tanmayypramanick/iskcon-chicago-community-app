-- Announcement reactions: the noticeboard learns to talk back.
--
-- Until now an announcement was a sheet of paper. The temple put it up, four
-- hundred devotees read it, and every question it raised — "is the 11pm arati
-- in the main hall or the annexe?", "can I bring my mother?" — had to leave the
-- app entirely and turn into a phone call to whoever posted it. Meanwhile the
-- only way to say "I have seen this, thank you" was to say nothing.
--
-- So: likes, comments, and replies to comments. The shape everybody's thumbs
-- already know.
--
--   * any devotee likes a notice, and unlikes it; liking twice is one like;
--   * everybody sees who liked, by name and face, because a noticeboard where
--     the reactions are anonymous is a noticeboard nobody trusts;
--   * any devotee comments, and any devotee replies to a comment;
--   * comments thread exactly one level deep, and a reply to a reply is
--     refused — see section 3;
--   * an author takes their own words down, and a Community Head, Tech Admin
--     or President takes anybody's down; the removal is soft, so the thread
--     beneath keeps its shape.
--
-- The rule this file cares most about is the quiet one, and it is the same rule
-- devotee care was built around: a feature that pings on every tap is a feature
-- that teaches the congregation to mute the app, which costs the temple its
-- announcements too. So:
--
--   * a comment tells the announcement's poster, and nobody else;
--   * a reply tells the comment's author, and nobody else;
--   * a like tells nobody at all. Not the poster, not anybody.
--
-- Note the deliberate asymmetry in the middle: a reply does NOT also ping the
-- announcement's poster. The poster asked to hear that their notice was
-- discussed, not to follow every sub-thread it grew; and a busy notice would
-- otherwise deliver them one push per message forever. The verification script
-- asserts the notification count across every user in the database rather than
-- across the interesting ones, because "we only notify the one person" is the
-- kind of claim that stays true right up until somebody adds a helpful
-- `for devotee in select id from users` loop.
--
-- Requires 202608040040_announcements.sql.

-- ---------------------------------------------------------------------------
-- 1. The like.
--
--    The primary key is the pair, which is the whole idempotency story: a
--    double-tap, a retried request over a flaky temple wifi connection, and two
--    phones signed into the same account all land on one row. There is nothing
--    to reconcile and no count to repair, because the key itself is the rule.
--
--    No id column, because there is nothing a like needs to be addressed by. It
--    is not a thing that happened; it is a fact about a devotee and a notice,
--    and the pair says it exactly.
--
--    clock_timestamp() rather than now(). now() is the transaction's start, so
--    rows written inside one transaction share a timestamp exactly and "newest
--    first" falls back to whatever order the planner felt like — which the
--    verification script, being one transaction, would notice immediately.
-- ---------------------------------------------------------------------------

create table if not exists public.announcement_likes (
  announcement_id uuid not null
    references public.announcements(id) on delete cascade,
  -- A like is personal and means nothing without the person: when a devotee
  -- leaves, their likes go with them. This is the opposite choice from
  -- announcements.posted_by, which survives as null, because the notice belongs
  -- to the temple and the like does not.
  devotee_id uuid not null references public.users(id) on delete cascade,
  created_at timestamptz not null default clock_timestamp(),
  primary key (announcement_id, devotee_id)
);

-- The primary key's leading column already serves every read this feature makes
-- of the table — the count for one notice, the "did I like it" probe, and the
-- list of who liked. No second index on announcement_id is added for the
-- newest-first ordering: liking is the hottest write in the app and every extra
-- index is paid on every tap, while sorting the handful of rows a single notice
-- collects costs nothing worth measuring.
--
-- This one is not optional, though: without it, removing a devotee makes
-- Postgres scan the whole table to find the likes to cascade away.
create index if not exists announcement_likes_devotee_idx
  on public.announcement_likes (devotee_id);

comment on table public.announcement_likes is
  'One devotee''s like on one announcement. The pair is the primary key, so liking twice is liking once.';

-- ---------------------------------------------------------------------------
-- 2. The comment, and the reply, in one table.
--
--    A reply is a comment with a parent. Splitting them into two tables would
--    double every guard, every policy, every index and every removal path in
--    this file to express a difference of one nullable column, and would still
--    leave "list the thread" needing a union.
-- ---------------------------------------------------------------------------

create table if not exists public.announcement_comments (
  id uuid primary key default gen_random_uuid(),
  announcement_id uuid not null
    references public.announcements(id) on delete cascade,
  -- Null for a top-level comment. Section 3 is what keeps this at one level.
  parent_comment_id uuid
    references public.announcement_comments(id) on delete cascade,
  author_id uuid not null references public.users(id) on delete cascade,
  body text not null,
  created_at timestamptz not null default clock_timestamp(),
  deleted_at timestamptz,
  deleted_by uuid references public.users(id) on delete set null,
  -- btrim over a whitespace set rather than plain trim(), which strips spaces
  -- and nothing else. The comment box in the app is multi-line, so the easiest
  -- way to submit nothing is to press return twice — and a body of two newlines
  -- survives trim() intact and lands on the thread as an empty bubble. 0041 and
  -- 0042 spell the same set out for the same reason.
  constraint announcement_comment_body_not_blank
    check (nullif(btrim(body, e' \t\r\n\f\v'), '') is not null),
  -- A tombstone must say who made it. The pair moves together or not at all, so
  -- no row can claim to be removed by nobody, or to be live while naming a
  -- remover. deleted_by is nullable on its own account only because the remover
  -- may later leave the congregation, and the reference above sets it null
  -- then — which this check permits, since deleted_at is what decides state.
  constraint announcement_comment_removal_consistent check (
    deleted_at is not null or deleted_by is null
  ),
  -- Cheap half of the one-level rule: a comment cannot be its own parent. The
  -- half that needs to look at another row is section 3.
  constraint announcement_comment_not_own_parent
    check (parent_comment_id is null or parent_comment_id <> id)
);

-- The thread reads in creation order and renders tombstones, so this one index
-- serves the whole of list_announcement_comments.
create index if not exists announcement_comments_thread_idx
  on public.announcement_comments (announcement_id, created_at, id);

-- The board's comment_count excludes removed rows, so it gets its own partial
-- index rather than filtering the one above.
create index if not exists announcement_comments_live_idx
  on public.announcement_comments (announcement_id) where deleted_at is null;

-- reply_count, and the "is my parent a reply" test in section 3.
create index if not exists announcement_comments_parent_idx
  on public.announcement_comments (parent_comment_id)
  where parent_comment_id is not null;

create index if not exists announcement_comments_author_idx
  on public.announcement_comments (author_id);

comment on table public.announcement_comments is
  'A comment on an announcement, or — when parent_comment_id is set — a reply to one. Exactly one level deep. Removals are soft so the thread keeps its shape.';

-- ---------------------------------------------------------------------------
-- 3. One level, and one level only.
--
--    This is a temple noticeboard, not a forum. Unlimited nesting buys an
--    argument three replies deep that nobody can follow on a phone, and buys
--    the client a recursive renderer to draw it with. A comment, and replies to
--    that comment. That is all.
--
--    add_announcement_comment refuses this in words a devotee can read, which
--    is where the rule is actually enforced in practice. The trigger exists
--    because the rule is about the shape of the data rather than about one
--    function's manners: it also catches an UPDATE that would reparent a
--    top-level comment under a reply, which no RPC does today and which would
--    silently produce a thread the client cannot draw if one ever did.
--
--    The two are worded differently on purpose. The RPC speaks to a devotee;
--    the trigger speaks to whoever is writing to the table behind its back, and
--    should never be the thing a devotee sees. Identical wording would make the
--    two guards indistinguishable, and a verification script cannot then tell
--    that one of them has quietly stopped firing.
--
--    A check constraint cannot do this — it may not read another row.
-- ---------------------------------------------------------------------------

create or replace function public.announcement_comment_stays_one_level()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.parent_comment_id is null then
    return new;
  end if;

  if not exists (
    select 1 from public.announcement_comments parent
    where parent.id = new.parent_comment_id
  ) then
    raise exception
      'Announcement comment % names a parent that does not exist.', new.id;
  end if;

  if exists (
    select 1 from public.announcement_comments parent
    where parent.id = new.parent_comment_id
      and parent.parent_comment_id is not null
  ) then
    raise exception
      'Announcement comments nest one level deep only; % was filed under a reply.',
      new.id;
  end if;

  return new;
end;
$$;

comment on function public.announcement_comment_stays_one_level() is
  'Keeps announcement comments exactly one level deep: a reply''s parent must itself be top-level.';

revoke all on function public.announcement_comment_stays_one_level()
  from public, anon, authenticated;

drop trigger if exists announcement_comment_one_level on public.announcement_comments;
create trigger announcement_comment_one_level
before insert or update of parent_comment_id on public.announcement_comments
for each row execute function public.announcement_comment_stays_one_level();

-- ---------------------------------------------------------------------------
-- 4. Reading, and who may take somebody else's words down.
--
--    Every signed-in devotee sees every like and every comment that has not
--    been removed. There is no audience to pick — the notice itself is read by
--    everyone, so the conversation under it is too.
--
--    Removed comments are outside the policy entirely, so no query a devotee
--    can phrase against the table returns the words that were taken down. The
--    thread still keeps its shape, because list_announcement_comments below is
--    a definer function and renders the tombstone itself with the body left
--    out. The row survives for the temple's records; the policy is what makes
--    sure the removal actually removed something.
--
--    Moderation reuses may_post_announcements(), which is already exactly
--    "Community Head, Tech Admin, President" by way of
--    services.manage_recurring — the same three who may post a notice and the
--    same three who may take one down in 0040. A separate helper spelled the
--    same way would be a second place to forget to update, and a new permission
--    key would be a key a fourth role gets given one day while these threads go
--    quietly unmoderated.
-- ---------------------------------------------------------------------------

alter table public.announcement_likes enable row level security;
alter table public.announcement_comments enable row level security;

drop policy if exists "Devotees read announcement likes" on public.announcement_likes;
create policy "Devotees read announcement likes"
  on public.announcement_likes for select to authenticated
  using (auth.uid() is not null);

drop policy if exists "Devotees read announcement comments" on public.announcement_comments;
create policy "Devotees read announcement comments"
  on public.announcement_comments for select to authenticated
  using (auth.uid() is not null and deleted_at is null);

-- Every write goes through an RPC below, so nothing beyond reading is granted.
revoke all on public.announcement_likes from anon, authenticated;
revoke all on public.announcement_comments from anon, authenticated;

grant select (announcement_id, devotee_id, created_at)
  on public.announcement_likes to authenticated;

grant select (
  id, announcement_id, parent_comment_id, author_id, body,
  created_at, deleted_at, deleted_by
) on public.announcement_comments to authenticated;

-- ---------------------------------------------------------------------------
-- 5. The two notifications this feature has.
--
--    Extended whole rather than appended to, because the constraint is replaced
--    rather than altered and a partial list would quietly outlaw every kind
--    already in use. The list below is 0050's — the most recent migration to
--    touch this constraint — plus the two new kinds.
-- ---------------------------------------------------------------------------

alter table public.app_notifications
  drop constraint if exists app_notifications_kind_check;

alter table public.app_notifications
  add constraint app_notifications_kind_check check (
    kind in (
      'service_open', 'service_offer', 'service_recurring_offer',
      'service_offer_response', 'service_joined', 'service_left',
      'service_started', 'service_completed', 'service_cancelled',
      'service_deleted', 'service_coverage_needed',
      'service_coverage_resolved', 'recurring_interest_submitted',
      'recurring_interest_reviewed',
      'seva_verification_requested', 'seva_verification_reviewed',
      'weekly_offer_countered', 'weekly_offer_counter_reviewed',
      'access_request_submitted', 'access_request_reviewed',
      'devotee_joined', 'profile_incomplete',
      'sanga_created', 'sanga_reviewed',
      'sanga_join_requested', 'sanga_join_reviewed',
      'sanga_member_added', 'sanga_member_removed', 'sanga_member_left',
      'sanga_admin_transferred', 'sanga_deleted',
      'announcement_posted',
      'feedback_reviewed',
      'care_reply',
      'birthday_today',
      'newsletter_posted',
      'newsletter_reviewed',
      'access_appointed',
      'access_revoked',
      'sponsorship_fulfilled',
      'announcement_commented',
      'announcement_comment_replied',
      'remote'
    )
  );

-- ---------------------------------------------------------------------------
-- 6. Liking, and unliking.
--
--    One function for both, because the client has one button. It returns what
--    the button should now show rather than what it did, so a phone that missed
--    a response and retried ends up agreeing with the database instead of
--    inverting away from it.
--
--    Idempotent in both directions, in the only sense that survives a retry:
--    the insert cannot produce a second row (the primary key), and the delete
--    of a like that is not there is not an error. Toggling twice is a like and
--    then an unlike, which is what a button that has been pressed twice means.
--
--    Nothing is queued here. Deliberately, loudly: this is the single easiest
--    place in the app to accidentally generate four hundred pushes a day.
-- ---------------------------------------------------------------------------

create or replace function public.toggle_announcement_like(
  p_announcement_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  target public.announcements;
  removed integer;
begin
  if auth.uid() is null then
    raise exception 'Sign in to like an announcement.';
  end if;

  select * into target from public.announcements
  where announcements.id = p_announcement_id;

  if target.id is null then
    raise exception 'That announcement could not be found.';
  end if;

  delete from public.announcement_likes
  where announcement_likes.announcement_id = target.id
    and announcement_likes.devotee_id = auth.uid();

  get diagnostics removed = row_count;
  if removed > 0 then
    return false;
  end if;

  -- on conflict do nothing rather than a second existence check: two taps
  -- racing each other both find nothing to delete, and one of them must lose
  -- the insert without raising in the devotee's face.
  insert into public.announcement_likes (announcement_id, devotee_id)
  values (target.id, auth.uid())
  on conflict (announcement_id, devotee_id) do nothing;

  -- No notification. See the header. A noticeboard that pings on every tap is
  -- a noticeboard the congregation mutes, and it takes the announcements with
  -- it when it goes.
  return true;
end;
$$;

comment on function public.toggle_announcement_like(uuid) is
  'Like an announcement, or unlike it. Returns true when the viewer now likes it. Notifies nobody, deliberately.';

revoke all on function public.toggle_announcement_like(uuid) from public, anon;
grant execute on function public.toggle_announcement_like(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 7. Who liked.
--
--    Names and faces, for everybody, because that is the whole point of a like
--    on a noticeboard: the devotee who posted "the parking lot is closed
--    Sunday" wants to know it landed, and the devotee reading it wants to know
--    who else is coming.
-- ---------------------------------------------------------------------------

create or replace function public.list_announcement_likes(
  p_announcement_id uuid
)
returns table (
  devotee_id uuid,
  name text,
  photo_url text,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    announcement_likes.devotee_id,
    liker.name,
    liker.photo_url,
    announcement_likes.created_at
  from public.announcement_likes
  join public.users liker on liker.id = announcement_likes.devotee_id
  where auth.uid() is not null
    and announcement_likes.announcement_id = p_announcement_id
  order by announcement_likes.created_at desc, announcement_likes.devotee_id
$$;

comment on function public.list_announcement_likes(uuid) is
  'Everyone who liked one announcement, newest first, by name and face.';

revoke all on function public.list_announcement_likes(uuid) from public, anon;
grant execute on function public.list_announcement_likes(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 8. Commenting, and replying.
--
--    One function for both, because a reply is a comment with a parent, and the
--    guards either would need are the same guards.
--
--    The notification is the careful part:
--
--      * a top-level comment tells the announcement's poster;
--      * a reply tells the comment's author;
--      * and in both cases, nobody else — not the other people on the thread,
--        not the poster when the thread moves on beneath them, not the
--        congregation.
--
--    Speaking to yourself tells nobody: a poster answering a question on their
--    own notice, or a commenter adding "…and bring an umbrella" under their own
--    comment, does not need to be pushed their own words.
--
--    A notice whose poster has since left the congregation has a null
--    posted_by, and there is simply nobody to tell.
-- ---------------------------------------------------------------------------

create or replace function public.add_announcement_comment(
  p_announcement_id uuid,
  p_body text,
  p_parent_comment_id uuid default null
)
returns public.announcement_comments
language plpgsql
security definer
set search_path = ''
as $$
declare
  target public.announcements;
  parent public.announcement_comments;
  clean_body text;
  created public.announcement_comments;
  author_name text;
  recipient uuid;
begin
  if auth.uid() is null then
    raise exception 'Sign in to comment.';
  end if;

  -- No permission check, on purpose. Every devotee may say something on the
  -- board; being heard is not a privilege the temple hands out.

  -- Whitespace-aware, for the reason given on the table constraint: a body of
  -- two newlines is a blank body, and trim() alone would not say so.
  clean_body := nullif(btrim(coalesce(p_body, ''), e' \t\r\n\f\v'), '');
  if clean_body is null then
    raise exception 'Please write your comment.';
  end if;

  select * into target from public.announcements
  where announcements.id = p_announcement_id;

  if target.id is null then
    raise exception 'That announcement could not be found.';
  end if;

  if p_parent_comment_id is not null then
    select * into parent from public.announcement_comments
    where announcement_comments.id = p_parent_comment_id;

    -- A removed comment is reported as missing rather than as removed. The
    -- devotee cannot see it on the thread either way, and "that comment was
    -- taken down" is an answer to a question they did not ask about somebody
    -- else's business.
    if parent.id is null or parent.deleted_at is not null then
      raise exception 'That comment could not be found.';
    end if;

    if parent.announcement_id <> target.id then
      raise exception 'That comment is on a different announcement.';
    end if;

    -- One level. The trigger in section 3 would stop this too, but a devotee
    -- deserves to be told why rather than being shown a trigger's exception
    -- through whatever the client does with an unrecognised error.
    if parent.parent_comment_id is not null then
      raise exception 'You can reply to a comment, but not to a reply.';
    end if;
  end if;

  insert into public.announcement_comments (
    announcement_id, parent_comment_id, author_id, body
  )
  values (target.id, p_parent_comment_id, auth.uid(), clean_body)
  returning * into created;

  -- Exactly one person hears about this, and sometimes nobody does.
  if p_parent_comment_id is null then
    recipient := target.posted_by;
  else
    recipient := parent.author_id;
  end if;

  if recipient is not null and recipient <> auth.uid() then
    select users.name into author_name
    from public.users where users.id = auth.uid();

    if p_parent_comment_id is null then
      perform public.queue_app_notification(
        recipient,
        'announcement_commented',
        'New comment',
        coalesce(author_name, 'A devotee')
          || ' commented on "' || target.title || '".',
        jsonb_build_object(
          'announcementId', target.id,
          'commentId', created.id
        )
      );
    else
      perform public.queue_app_notification(
        recipient,
        'announcement_comment_replied',
        'New reply',
        coalesce(author_name, 'A devotee')
          || ' replied to your comment on "' || target.title || '".',
        jsonb_build_object(
          'announcementId', target.id,
          'commentId', created.id,
          'parentCommentId', parent.id
        )
      );
    end if;
  end if;

  return created;
end;
$$;

comment on function public.add_announcement_comment(uuid, text, uuid) is
  'Comment on an announcement, or reply to a comment. Tells the poster (or the comment''s author) and nobody else.';

revoke all on function public.add_announcement_comment(uuid, text, uuid) from public, anon;
grant execute on function public.add_announcement_comment(uuid, text, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 9. Reading a thread.
--
--    A removed comment keeps its place and loses its words. This is the whole
--    reason removal is soft: replies are read as answers to what came before
--    them, and deleting the row outright would leave "yes, the annexe" sitting
--    under a question nobody can see any more. The client renders "This comment
--    was removed" from the deleted_at, and the body comes back null — the words
--    are not returned to anybody through this function, and the row policy in
--    section 4 keeps them from being reached directly either.
--
--    can_remove is false on an already-removed comment: there is nothing left
--    to take down.
--
--    The order is the client's whole rendering strategy, so it is decided here
--    rather than left to a sort on the phone: top-level comments oldest first,
--    each one immediately followed by its own replies, oldest first. root is
--    the top-level comment a row belongs to — itself, for a comment; its
--    parent, for a reply — and the boolean in the middle of the ORDER BY puts
--    the root (false) ahead of the replies hanging off it (true).
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
    (
      announcement_comments.deleted_at is null
      and (
        announcement_comments.author_id = auth.uid()
        or public.may_post_announcements()
      )
    )
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
  'One announcement''s thread: top-level comments oldest first, each followed by its replies. A removed comment keeps its place and returns a null body.';

revoke all on function public.list_announcement_comments(uuid) from public, anon;
grant execute on function public.list_announcement_comments(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 10. Taking words down.
--
--     Two people may: whoever wrote them, and any of the three who speak for
--     the temple. Removing twice is a mistake rather than a licence, so it is
--     refused — otherwise a second call would rewrite deleted_by and the record
--     would name the wrong person.
--
--     Removing a top-level comment does not remove its replies. They keep their
--     words and their place under the tombstone, exactly as a removed reply
--     keeps its place among the replies around it, because the alternative is a
--     moderator silencing four other devotees by taking down one. Nothing is
--     notified: a removal is not news anybody asked for.
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

  if target.author_id <> auth.uid()
     and not public.may_post_announcements()
  then
    raise exception 'You can remove your own comment, or any comment if you are a Community Head, Tech Admin, or the President.';
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
  'Soft-remove a comment or reply. The author may, and so may a Community Head, Tech Admin or President. The thread keeps its shape.';

revoke all on function public.delete_announcement_comment(uuid) from public, anon;
grant execute on function public.delete_announcement_comment(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 11. The board, now with its counts.
--
--     Dropped first, with the full argument list, rather than replaced. A
--     function's return shape cannot be changed by CREATE OR REPLACE, and a
--     leftover overload with a different signature becomes an ambiguous call
--     the moment a client asks for list_announcements — which has cost this
--     repo an afternoon before.
--
--     Counts: three correlated subqueries per row rather than counter columns
--     kept by trigger. This is the cheaper-looking choice inverted, so it is
--     worth being explicit about why.
--
--     The expensive-sounding half first. list_announcements returns live
--     notices only — in practice a handful, a few dozen at Janmashtami, never
--     hundreds, because an announcement's whole purpose is to stop being one.
--     Each subquery is an index probe on the leading column of a key that
--     exists for it: the likes primary key (announcement_id, devotee_id) covers
--     both like_count and liked_by_me, and announcement_comments_live_idx
--     covers comment_count. Thirty notices is ninety index probes against
--     tables holding at most a few thousand rows between them, which is not a
--     cost anybody can measure on a temple's database.
--
--     Now the half that actually decides it. A stored counter is not free; it
--     is a second copy of the truth, and it has to be correct after a like, an
--     unlike, a comment, a soft removal, an author leaving the congregation and
--     cascading their rows away, and any backfill anybody ever runs. Miss one
--     of those paths and the notice reads "12 likes" under a list of eleven
--     faces — forever, silently, with nothing to make it notice, because a
--     counter has no way of knowing it is wrong. The brief asks for accurate
--     and cheap, and at this scale the subquery is both, while the counter buys
--     an unmeasurable saving with a whole class of drift bug. If the temple ever
--     grows a feed that pages through thousands of live notices, this is the
--     right thing to revisit; today it would be complexity bought on credit.
-- ---------------------------------------------------------------------------

drop function if exists public.list_announcements();

create or replace function public.list_announcements()
returns table (
  id uuid,
  title text,
  body text,
  image_url text,
  posted_by uuid,
  posted_by_name text,
  posted_by_photo_url text,
  starts_on date,
  ends_on date,
  starts_at time,
  ends_at time,
  created_at timestamptz,
  can_delete boolean,
  like_count integer,
  comment_count integer,
  liked_by_me boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    announcements.id,
    announcements.title,
    announcements.body,
    announcements.image_url,
    announcements.posted_by,
    poster.name,
    poster.photo_url,
    announcements.starts_on,
    announcements.ends_on,
    announcements.starts_at,
    announcements.ends_at,
    announcements.created_at,
    (
      announcements.posted_by = auth.uid()
      or public.may_post_announcements()
    ),
    (
      select count(*)::integer from public.announcement_likes
      where announcement_likes.announcement_id = announcements.id
    ),
    -- Removed comments are not comments. A card reading "3 comments" over a
    -- thread showing two and a tombstone is a card that looks broken.
    (
      select count(*)::integer from public.announcement_comments
      where announcement_comments.announcement_id = announcements.id
        and announcement_comments.deleted_at is null
    ),
    exists (
      select 1 from public.announcement_likes
      where announcement_likes.announcement_id = announcements.id
        and announcement_likes.devotee_id = auth.uid()
    )
  from public.announcements
  left join public.users poster on poster.id = announcements.posted_by
  where auth.uid() is not null
    and public.announcement_is_live(announcements.ends_on, announcements.ends_at)
  order by announcements.created_at desc
$$;

comment on function public.list_announcements() is
  'Every live notice, newest first, with its poster, whether the viewer may remove it, and its likes and comments as the viewer sees them.';

revoke all on function public.list_announcements() from public, anon;
grant execute on function public.list_announcements() to authenticated;

do $$
begin
  raise notice 'announcement reactions applied';
end;
$$;
