-- Devotee Care: the board where a devotee asks for help.
--
-- "My mother is in hospital and I cannot drive to the temple this week."
-- "Does anyone have a spare tulsi plant?" "I have been struggling to finish my
-- rounds and could use some association." None of that is seva, none of it is
-- an announcement, and a direct message only reaches the one person the
-- devotee already thought to ask — which is precisely the wrong shape, because
-- the devotee asking usually does not know who can help.
--
-- So it is a board, not a chat:
--
--   * any devotee posts a request — a title, some words, optionally a photo;
--   * any devotee replies to any post;
--   * everybody reads everything, because a congregation that cannot see who
--     needs help cannot help;
--   * a Community Head, Tech Admin or President may take down any post or
--     reply, and an author may take down their own.
--
-- The one rule worth stating twice: this feature is deliberately quiet.
--
-- Announcements notify the whole congregation, and that is right — a notice
-- board with nobody looking at it is a wall. Devotee Care is the opposite. If
-- posting pinged everyone, the third post of the day would teach four hundred
-- people to turn the app's notifications off, and the temple would lose the
-- announcements too. So exactly one notification exists in this entire file:
-- the author of a post is told when somebody replies to it. Posting notifies
-- nobody. Replying notifies nobody but that one author. Replying to your own
-- post notifies nobody at all. The verification script asserts the count
-- across every user in the database, not just the interesting ones, because
-- "we only notify the author" is the kind of claim that stays true until
-- somebody adds a helpful `for devotee in select id from users` loop.
--
-- Requires 202608040040_announcements.sql.

-- ---------------------------------------------------------------------------
-- 1. The post.
--
--    deleted_at/deleted_by rather than a delete, for the reason set out in
--    section 6: a reply hangs off a post, and a reply two down the thread
--    reads as an answer to the one above it. Removing rows outright would
--    reshape a conversation that other people are still reading.
-- ---------------------------------------------------------------------------

create table if not exists public.care_posts (
  id uuid primary key default gen_random_uuid(),
  -- The author leaving the congregation takes their posts with them: unlike an
  -- announcement, which belongs to the temple, a request for help is personal
  -- and has no meaning once there is nobody to help.
  author_id uuid not null references public.users(id) on delete cascade,
  title text not null,
  body text not null,
  image_url text,
  -- clock_timestamp() rather than now(). now() is the transaction's start, so
  -- two rows written inside one transaction share a timestamp exactly and the
  -- board's "newest first" falls back to whatever order the planner felt like.
  -- A board is read as a sequence, so the sequence has to be real.
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  deleted_at timestamptz,
  deleted_by uuid references public.users(id) on delete set null,
  -- btrim over a whitespace set rather than plain trim(), which strips spaces
  -- and nothing else. A body typed as a couple of newlines in a multi-line
  -- text box survives trim() intact and lands as a post with nothing in it.
  constraint care_post_title_not_blank
    check (nullif(btrim(title, e' \t\r\n\f\v'), '') is not null),
  constraint care_post_body_not_blank
    check (nullif(btrim(body, e' \t\r\n\f\v'), '') is not null),
  -- A tombstone must say who made it. The pair moves together or not at all,
  -- so no row can claim to be removed by nobody, or to be live while naming a
  -- remover. deleted_by is nullable on its own account only because the
  -- remover may later leave, and the reference above sets it to null then —
  -- which this check permits, since deleted_at is what decides the state.
  constraint care_post_removal_consistent check (
    deleted_at is not null or deleted_by is null
  )
);

create index if not exists care_posts_created_at_idx
  on public.care_posts (created_at desc) where deleted_at is null;

create index if not exists care_posts_author_idx
  on public.care_posts (author_id);

-- ---------------------------------------------------------------------------
-- 2. The reply.
-- ---------------------------------------------------------------------------

create table if not exists public.care_replies (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.care_posts(id) on delete cascade,
  author_id uuid not null references public.users(id) on delete cascade,
  body text not null,
  -- As above: a thread is an order, and now() cannot tell two rows in one
  -- transaction apart.
  created_at timestamptz not null default clock_timestamp(),
  deleted_at timestamptz,
  deleted_by uuid references public.users(id) on delete set null,
  constraint care_reply_body_not_blank
    check (nullif(btrim(body, e' \t\r\n\f\v'), '') is not null),
  constraint care_reply_removal_consistent check (
    deleted_at is not null or deleted_by is null
  )
);

-- The thread reads oldest first and the count on the board excludes removals,
-- so both queries are served by one index.
create index if not exists care_replies_post_idx
  on public.care_replies (post_id, created_at);

create index if not exists care_replies_author_idx
  on public.care_replies (author_id);

comment on table public.care_posts is
  'A devotee''s request for help. Read by everyone; removals are soft so the thread beneath survives.';
comment on table public.care_replies is
  'One reply on a care post. Soft-removed so the replies after it still read in order.';

-- ---------------------------------------------------------------------------
-- 3. Who may take somebody else's words down.
--
--    Community Head, Tech Admin, President — identified by
--    services.manage_recurring, exactly as announcements identify them, and
--    for the same reason: it is the key the temple already means when it says
--    "the three who speak for us", and inventing a `care.moderate` alongside
--    it would give a fourth role that key one day and silently leave this
--    board unmoderated.
-- ---------------------------------------------------------------------------

create or replace function public.may_moderate_devotee_care()
returns boolean
language sql
stable
set search_path = ''
as $$
  select public.has_permission('services.manage_recurring')
$$;

comment on function public.may_moderate_devotee_care() is
  'True for a Community Head, Tech Admin or President — the three who may remove anybody''s care post or reply.';

revoke all on function public.may_moderate_devotee_care() from public, anon;
grant execute on function public.may_moderate_devotee_care() to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Reading.
--
--    Everyone signed in sees every post and every reply that has not been
--    removed. There is no audience to pick: that is what makes it a board
--    rather than a message.
--
--    Removed rows are outside the policy entirely, so no query a devotee can
--    phrase against the table returns the words that were taken down. The
--    thread still keeps its shape, because list_care_replies below is a
--    definer function and renders the tombstone itself, with the body left
--    out. The row survives for the temple's records; the policy is what makes
--    sure the removal actually removed something.
-- ---------------------------------------------------------------------------

alter table public.care_posts enable row level security;
alter table public.care_replies enable row level security;

drop policy if exists "Devotees read care posts" on public.care_posts;
create policy "Devotees read care posts"
  on public.care_posts for select to authenticated
  using (auth.uid() is not null and deleted_at is null);

drop policy if exists "Devotees read care replies" on public.care_replies;
create policy "Devotees read care replies"
  on public.care_replies for select to authenticated
  using (auth.uid() is not null and deleted_at is null);

-- Every write goes through an RPC below, so nothing beyond reading is granted.
revoke all on public.care_posts from anon, authenticated;
revoke all on public.care_replies from anon, authenticated;

grant select (
  id, author_id, title, body, image_url,
  created_at, updated_at, deleted_at, deleted_by
) on public.care_posts to authenticated;

grant select (
  id, post_id, author_id, body, created_at, deleted_at, deleted_by
) on public.care_replies to authenticated;

-- ---------------------------------------------------------------------------
-- 5. The one notification this feature has.
--
--    Extended whole rather than appended to, because the constraint is
--    replaced rather than altered and a partial list would quietly outlaw
--    every kind already in use.
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
      'sanga_admin_transferred',
      'announcement_posted',
      'feedback_reviewed',
      'care_reply',
      'remote'
    )
  );

-- ---------------------------------------------------------------------------
-- 6. Asking for help.
-- ---------------------------------------------------------------------------

create or replace function public.create_care_post(
  p_title text,
  p_body text,
  p_image_url text default null
)
returns public.care_posts
language plpgsql
security definer
set search_path = ''
as $$
declare
  clean_title text;
  clean_body text;
  clean_image text;
  created public.care_posts;
begin
  if auth.uid() is null then
    raise exception 'Sign in to ask the congregation for help.';
  end if;

  -- No permission check on purpose. Every devotee may ask; needing help is not
  -- a privilege the temple hands out.

  -- Whitespace-aware, for the reason given on the table constraint: a title
  -- of two newlines is a blank title, and trim() alone would not say so.
  clean_title := nullif(btrim(coalesce(p_title, ''), e' \t\r\n\f\v'), '');
  if clean_title is null then
    raise exception 'Please give your request a title.';
  end if;

  clean_body := nullif(btrim(coalesce(p_body, ''), e' \t\r\n\f\v'), '');
  if clean_body is null then
    raise exception 'Please say what you need help with.';
  end if;

  -- A photo must have come out of the app's own storage. Left open, this
  -- column is a way to have every devotee's phone fetch an arbitrary URL the
  -- moment the board renders, which is a tracking pixel the temple did not
  -- agree to. The bucket is the one direct messages already use — see
  -- section 10.
  clean_image := nullif(trim(coalesce(p_image_url, '')), '');
  if clean_image is not null
     and clean_image !~ '^https://[a-z0-9.-]+/storage/v1/object/public/message-images/'
  then
    raise exception 'A photo must be uploaded through the app.';
  end if;

  insert into public.care_posts (author_id, title, body, image_url)
  values (auth.uid(), clean_title, clean_body, clean_image)
  returning * into created;

  -- And nobody is told. See the header.
  return created;
end;
$$;

comment on function public.create_care_post(text, text, text) is
  'Post a request for help on the care board. Notifies nobody, deliberately.';

revoke all on function public.create_care_post(text, text, text) from public, anon;
grant execute on function public.create_care_post(text, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 7. Replying.
--
--    The only place in this file that queues anything, and it queues exactly
--    one row: the author of the post hears that somebody answered them. Not
--    the other people who replied — a devotee who offered a lift last Tuesday
--    did not sign up to follow the thread — and not the congregation.
-- ---------------------------------------------------------------------------

create or replace function public.reply_to_care_post(
  p_post_id uuid,
  p_body text
)
returns public.care_replies
language plpgsql
security definer
set search_path = ''
as $$
declare
  target public.care_posts;
  clean_body text;
  created public.care_replies;
  replier_name text;
begin
  if auth.uid() is null then
    raise exception 'Sign in to reply.';
  end if;

  clean_body := nullif(btrim(coalesce(p_body, ''), e' \t\r\n\f\v'), '');
  if clean_body is null then
    raise exception 'Please write your reply.';
  end if;

  select * into target from public.care_posts
  where care_posts.id = p_post_id;

  -- A removed post is reported as missing rather than as removed. The devotee
  -- cannot see it on the board either way, and "that post was taken down" is
  -- an answer to a question they did not ask about somebody else's business.
  if target.id is null or target.deleted_at is not null then
    raise exception 'That request could not be found.';
  end if;

  insert into public.care_replies (post_id, author_id, body)
  values (target.id, auth.uid(), clean_body)
  returning * into created;

  -- Replying to yourself tells nobody: the devotee adding "update: sorted,
  -- thank you all" to their own request does not need to be pushed their own
  -- words.
  if target.author_id <> auth.uid() then
    select users.name into replier_name
    from public.users where users.id = auth.uid();

    perform public.queue_app_notification(
      target.author_id,
      'care_reply',
      'New reply',
      coalesce(replier_name, 'A devotee')
        || ' replied to "' || target.title || '".',
      jsonb_build_object('postId', target.id, 'replyId', created.id)
    );
  end if;

  return created;
end;
$$;

comment on function public.reply_to_care_post(uuid, text) is
  'Reply to a care post. Notifies the post''s author and nobody else; notifies nobody when replying to yourself.';

revoke all on function public.reply_to_care_post(uuid, text) from public, anon;
grant execute on function public.reply_to_care_post(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 8. Reading the board.
--
--    Definer, so the reply count and the can_remove answer are decided in one
--    place. can_remove travels with the row because every card needs it to
--    decide whether to draw the button, and a round trip per post to ask the
--    same question would be absurd.
--
--    Removed posts are gone from the board entirely. Nothing hangs off a post
--    the way a reply hangs off the reply above it, so there is no shape to
--    keep and a tombstone would only be a permanent reminder that somebody
--    said something the temple took down.
-- ---------------------------------------------------------------------------

create or replace function public.list_care_posts()
returns table (
  id uuid,
  author_id uuid,
  author_name text,
  author_photo_url text,
  title text,
  body text,
  image_url text,
  created_at timestamptz,
  updated_at timestamptz,
  reply_count integer,
  can_remove boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    care_posts.id,
    care_posts.author_id,
    author.name,
    author.photo_url,
    care_posts.title,
    care_posts.body,
    care_posts.image_url,
    care_posts.created_at,
    care_posts.updated_at,
    (
      select count(*)::integer from public.care_replies
      where care_replies.post_id = care_posts.id
        and care_replies.deleted_at is null
    ),
    (
      care_posts.author_id = auth.uid()
      or public.may_moderate_devotee_care()
    )
  from public.care_posts
  join public.users author on author.id = care_posts.author_id
  where auth.uid() is not null
    and care_posts.deleted_at is null
  order by care_posts.created_at desc
$$;

comment on function public.list_care_posts() is
  'Every live care post, newest first, with its author, its reply count, and whether the viewer may remove it.';

revoke all on function public.list_care_posts() from public, anon;
grant execute on function public.list_care_posts() to authenticated;

-- ---------------------------------------------------------------------------
-- 9. Reading one thread.
--
--    A removed reply keeps its place in the order and loses its words. This is
--    the whole reason removal is soft: replies are read as answers to what
--    came before them, and deleting the row outright would leave "yes, I can
--    do that" sitting under a question nobody can see any more. The client
--    renders "This reply was removed" from the deleted_at, and the body comes
--    back null — the words are not returned to anybody through this function,
--    and the row policy in section 4 keeps them from being reached directly
--    either.
--
--    can_remove is false on an already-removed reply: there is nothing left to
--    take down.
-- ---------------------------------------------------------------------------

create or replace function public.list_care_replies(p_post_id uuid)
returns table (
  id uuid,
  post_id uuid,
  author_id uuid,
  author_name text,
  author_photo_url text,
  body text,
  created_at timestamptz,
  deleted_at timestamptz,
  can_remove boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    care_replies.id,
    care_replies.post_id,
    care_replies.author_id,
    author.name,
    author.photo_url,
    case when care_replies.deleted_at is null then care_replies.body end,
    care_replies.created_at,
    care_replies.deleted_at,
    (
      care_replies.deleted_at is null
      and (
        care_replies.author_id = auth.uid()
        or public.may_moderate_devotee_care()
      )
    )
  from public.care_replies
  join public.users author on author.id = care_replies.author_id
  join public.care_posts on care_posts.id = care_replies.post_id
  where auth.uid() is not null
    and care_replies.post_id = p_post_id
    -- A removed post takes its thread off the board with it.
    and care_posts.deleted_at is null
  order by care_replies.created_at, care_replies.id
$$;

comment on function public.list_care_replies(uuid) is
  'One thread, oldest first. A removed reply keeps its place and returns a null body.';

revoke all on function public.list_care_replies(uuid) from public, anon;
grant execute on function public.list_care_replies(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 10. Taking words down.
--
--     Two people may: whoever wrote them, and any of the three who speak for
--     the temple. Removing twice is a mistake rather than a licence, so it is
--     refused — otherwise a second call would rewrite deleted_by and the
--     record would name the wrong person.
-- ---------------------------------------------------------------------------

create or replace function public.delete_care_post(p_post_id uuid)
returns public.care_posts
language plpgsql
security definer
set search_path = ''
as $$
declare
  target public.care_posts;
  removed public.care_posts;
begin
  if auth.uid() is null then
    raise exception 'Sign in to remove a post.';
  end if;

  select * into target from public.care_posts
  where care_posts.id = p_post_id
  for update;

  if target.id is null or target.deleted_at is not null then
    raise exception 'That request could not be found.';
  end if;

  if target.author_id <> auth.uid()
     and not public.may_moderate_devotee_care()
  then
    raise exception 'You can remove your own post, or any post if you are a Community Head, Tech Admin, or the President.';
  end if;

  update public.care_posts
  set deleted_at = now(),
      deleted_by = auth.uid(),
      updated_at = now()
  where care_posts.id = target.id
  returning * into removed;

  return removed;
end;
$$;

revoke all on function public.delete_care_post(uuid) from public, anon;
grant execute on function public.delete_care_post(uuid) to authenticated;

create or replace function public.delete_care_reply(p_reply_id uuid)
returns public.care_replies
language plpgsql
security definer
set search_path = ''
as $$
declare
  target public.care_replies;
  removed public.care_replies;
begin
  if auth.uid() is null then
    raise exception 'Sign in to remove a reply.';
  end if;

  select * into target from public.care_replies
  where care_replies.id = p_reply_id
  for update;

  if target.id is null or target.deleted_at is not null then
    raise exception 'That reply could not be found.';
  end if;

  if target.author_id <> auth.uid()
     and not public.may_moderate_devotee_care()
  then
    raise exception 'You can remove your own reply, or any reply if you are a Community Head, Tech Admin, or the President.';
  end if;

  update public.care_replies
  set deleted_at = now(),
      deleted_by = auth.uid()
  where care_replies.id = target.id
  returning * into removed;

  return removed;
end;
$$;

revoke all on function public.delete_care_reply(uuid) from public, anon;
grant execute on function public.delete_care_reply(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 11. Photos.
--
--     The message-images bucket already holds exactly this kind of picture:
--     put there by one signed-in devotee, looked at by all of them, capped at
--     8MB, and written only inside the uploader's own folder. Announcements
--     reuse it for the same reason. A third bucket would mean a third size
--     limit and a third set of policies to keep in step, for no difference a
--     devotee could ever see.
-- ---------------------------------------------------------------------------

do $$
begin
  if not exists (select 1 from storage.buckets where id = 'message-images') then
    raise exception 'The message-images bucket is missing; apply 202608040032_messaging.sql first.';
  end if;
end;
$$;

do $$
begin
  raise notice 'devotee care applied';
end;
$$;
