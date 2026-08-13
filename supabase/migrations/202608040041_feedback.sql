-- Feedback: what a devotee wants to say to the temple.
--
-- The app has plenty of ways for the temple to speak to a devotee — seva
-- offers, announcements, notifications — and, until now, exactly one way for a
-- devotee to speak back: a direct message to somebody they happen to know is in
-- charge. That is a poor door. It requires knowing who to ask, it puts a
-- complaint about the app into the same thread as a conversation about kitchen
-- seva, and it leaves nothing anybody can look through later.
--
-- So: a short form, a category, and a body. Three categories, because those are
-- the three things a devotee actually has an opinion about —
--
--   temple     the building, the programmes, the prasadam, the parking
--   app        this software
--   community  the devotees, and how they treat one another
--
-- — and no more, because a list of fifteen is a list nobody reads before
-- picking the first entry.
--
-- Who sees it:
--
--   * the devotee who wrote it, always, along with any reply;
--   * the President and the Tech Admin, all of it;
--   * nobody else, ever, including through any function here.
--
-- The President or Tech Admin may mark a piece of feedback reviewed and attach
-- a short acknowledgement. That acknowledgement is deliberately not a chat: it
-- is one field on one row, it goes one way, and it cannot grow into a thread.
-- A devotee who wants a conversation already has direct messages; what they do
-- not have, and what this gives them, is the certainty that somebody read it.
--
-- Requires 202608040040_announcements.sql.

-- ---------------------------------------------------------------------------
-- 1. The feedback itself.
--
--    devotee_id cascades rather than nulling out. Unlike an announcement, a
--    piece of feedback is not the temple's notice — it is one devotee's opinion,
--    and an opinion detached from the person who held it is neither useful to
--    the President nor fair to the devotee who left the congregation. It goes
--    with them.
-- ---------------------------------------------------------------------------

create table if not exists public.feedback (
  id uuid primary key default gen_random_uuid(),
  devotee_id uuid not null references public.users(id) on delete cascade,
  category text not null check (category in ('temple', 'app', 'community')),
  body text not null,
  status text not null default 'new' check (status in ('new', 'reviewed')),
  reply text,
  -- The reviewer may leave; the reply stays, because the devotee was told it.
  -- Only the attribution goes.
  replied_by uuid references public.users(id) on delete set null,
  replied_at timestamptz,
  created_at timestamptz not null default now(),
  -- btrim with an explicit character list rather than a bare trim(): trim()
  -- strips spaces and nothing else, so a body of two newlines — which is
  -- exactly what a multi-line text box sends when a devotee taps return twice
  -- and then send — would otherwise sail past as non-blank.
  constraint feedback_body_not_blank check (
    nullif(btrim(body, E' \t\n\r\f\v'), '') is not null
  ),
  -- A reply of three spaces is not a reply. Either there is one or there is not.
  constraint feedback_reply_not_blank check (
    reply is null or nullif(btrim(reply, E' \t\n\r\f\v'), '') is not null
  ),
  -- Unreviewed means untouched: no reply, no reviewer, no timestamp. Reviewed
  -- means somebody did it and there is a time on it. replied_by is deliberately
  -- absent from the second half — the reviewer's account may later be deleted,
  -- and that must not retroactively invalidate a row.
  constraint feedback_review_consistency check (
    (status = 'new' and reply is null and replied_by is null and replied_at is null)
    or
    (status = 'reviewed' and replied_at is not null)
  )
);

-- The devotee's own list, newest first.
create index if not exists feedback_devotee_created_idx
  on public.feedback (devotee_id, created_at desc);

-- The President's queue: everything, newest first, usually filtered to 'new'.
create index if not exists feedback_status_created_idx
  on public.feedback (status, created_at desc);

create index if not exists feedback_replied_by_idx
  on public.feedback (replied_by);

-- ---------------------------------------------------------------------------
-- 2. Who reads all of it, and who may reply.
--
--    app.view_all, which 202608020001_access_levels.sql grants to exactly two
--    roles: president and tech. That is precisely the audience the temple asked
--    for, and it is already the key this app uses to mean "the two people who
--    can see everything". Registering a feedback.review_all alongside it would
--    create a second answer to the same question that could drift from the
--    first, and a fourth role added later would silently hold one and not the
--    other.
--
--    Reading all of it and replying to it are the same authority here on
--    purpose. A President who can read every complaint but cannot acknowledge
--    one, or an admin who can reply to feedback they cannot see, are both
--    states nobody asked for.
-- ---------------------------------------------------------------------------

create or replace function public.may_review_feedback()
returns boolean
language sql
stable
set search_path = ''
as $$
  select public.has_permission('app.view_all')
$$;

comment on function public.may_review_feedback() is
  'True for the President and the Tech Admin — the holders of app.view_all.';

revoke all on function public.may_review_feedback() from public, anon;
grant execute on function public.may_review_feedback() to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Row level security.
--
--    Your own, or everything if you are one of the two. The policy repeats what
--    the functions below enforce so that a client talking to PostgREST directly
--    gets the same answer as one calling the RPCs — a devotee selecting
--    straight from public.feedback sees their own rows and nothing else.
--
--    Every write goes through an RPC, so no insert, update or delete policy
--    exists and none is granted. A devotee cannot edit their feedback after
--    sending it: the President may already have read it, and a record that can
--    be rewritten underneath the person who acted on it is worse than no record.
-- ---------------------------------------------------------------------------

alter table public.feedback enable row level security;

drop policy if exists "Devotees read their own feedback" on public.feedback;
create policy "Devotees read their own feedback"
  on public.feedback for select to authenticated
  using (
    auth.uid() is not null
    and (devotee_id = auth.uid() or public.may_review_feedback())
  );

revoke all on public.feedback from anon, authenticated;
grant select (
  id, devotee_id, category, body, status,
  reply, replied_by, replied_at, created_at
) on public.feedback to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Telling the devotee their feedback was read.
--
--    Extended whole rather than appended to, because the constraint is replaced
--    rather than altered and a partial list would quietly outlaw every kind
--    already in use. Mirrored in src/features/notifications/types.ts.
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
      'remote'
    )
  );

-- ---------------------------------------------------------------------------
-- 5. Sending it.
--
--    Any signed-in devotee, no permission at all. That is the point: the
--    quietest person in the congregation must be able to say something to the
--    President without knowing who the President is.
--
--    The category is normalised before it is judged, so a client sending
--    'Temple' is not told off for capitalising a label the app itself
--    capitalises on screen.
-- ---------------------------------------------------------------------------

create or replace function public.submit_feedback(
  p_category text,
  p_body text
)
returns public.feedback
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_category text;
  v_body text;
  v_created public.feedback;
begin
  if auth.uid() is null then
    raise exception 'Sign in to send feedback.';
  end if;

  v_category := nullif(lower(btrim(coalesce(p_category, ''), E' \t\n\r\f\v')), '');
  if v_category is null or v_category not in ('temple', 'app', 'community') then
    raise exception 'Choose whether this is about the temple, the app, or the community.';
  end if;

  -- Leading and trailing whitespace only. The newlines a devotee put between
  -- their paragraphs are part of what they wrote and are left alone.
  v_body := nullif(btrim(coalesce(p_body, ''), E' \t\n\r\f\v'), '');
  if v_body is null then
    raise exception 'Please write your feedback before sending it.';
  end if;

  insert into public.feedback (devotee_id, category, body)
  values (auth.uid(), v_category, v_body)
  returning * into v_created;

  return v_created;
end;
$$;

revoke all on function public.submit_feedback(text, text) from public, anon;
grant execute on function public.submit_feedback(text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. What the devotee sees back.
--
--    Their own, newest first, with the reply and the name of whoever left it.
--    Definer, because the replier's name lives in public.users and a plain
--    devotee cannot read another devotee's row there — the President's name is
--    part of the acknowledgement, not a leak.
--
--    Nothing else about the replier travels: no id, no photo, no email. The
--    devotee is being told the temple answered, not handed a contact card.
-- ---------------------------------------------------------------------------

create or replace function public.list_my_feedback()
returns table (
  id uuid,
  category text,
  body text,
  status text,
  reply text,
  replied_by_name text,
  replied_at timestamptz,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    feedback.id,
    feedback.category,
    feedback.body,
    feedback.status,
    feedback.reply,
    replier.name,
    feedback.replied_at,
    feedback.created_at
  from public.feedback
  left join public.users replier on replier.id = feedback.replied_by
  where auth.uid() is not null
    and feedback.devotee_id = auth.uid()
  order by feedback.created_at desc
$$;

revoke all on function public.list_my_feedback() from public, anon;
grant execute on function public.list_my_feedback() to authenticated;

-- ---------------------------------------------------------------------------
-- 7. What the President and the Tech Admin see.
--
--    Everything, newest first, with the devotee's name and photo so the row can
--    be read as a person rather than a uuid.
--
--    Anyone without app.view_all gets an empty set rather than an exception.
--    The distinction matters: this function backs a screen, and a screen that
--    throws on open is a crash, whereas a screen that has nothing to show is
--    simply a screen a devotee should never have been routed to. The guard is
--    inside the where clause rather than around the call so that there is no
--    path — no argument, no ordering, no partial result — that returns a row to
--    a devotee who may not have it.
-- ---------------------------------------------------------------------------

create or replace function public.list_all_feedback()
returns table (
  id uuid,
  devotee_id uuid,
  devotee_name text,
  devotee_photo_url text,
  category text,
  body text,
  status text,
  reply text,
  replied_by uuid,
  replied_by_name text,
  replied_at timestamptz,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    feedback.id,
    feedback.devotee_id,
    devotee.name,
    devotee.photo_url,
    feedback.category,
    feedback.body,
    feedback.status,
    feedback.reply,
    feedback.replied_by,
    replier.name,
    feedback.replied_at,
    feedback.created_at
  from public.feedback
  join public.users devotee on devotee.id = feedback.devotee_id
  left join public.users replier on replier.id = feedback.replied_by
  where auth.uid() is not null
    and public.may_review_feedback()
  order by feedback.created_at desc
$$;

revoke all on function public.list_all_feedback() from public, anon;
grant execute on function public.list_all_feedback() to authenticated;

-- ---------------------------------------------------------------------------
-- 8. Reading it and answering.
--
--    The reply is OPTIONAL, and that is a decision rather than an omission.
--    Marking feedback reviewed and writing an acknowledgement are one action in
--    the interface, but they are not the same promise. "Thank you, we have read
--    this" is worth sending for a suggestion; a piece of feedback that says
--    "the 4:30 arati was beautiful" needs no answer at all, and forcing the
--    President to compose one for every row is the surest way to get a queue
--    that never gets worked through. So p_reply defaults to null, a blank or
--    whitespace-only reply is stored as no reply rather than as an empty
--    string, and the devotee is notified either way — being told somebody read
--    it is the point of the feature, with or without words attached.
--
--    Re-reviewing is allowed. A President who sends "Thank you" and then wants
--    to add "the parking will be resolved by Sunday" should not be stopped by
--    the database, and a typo in an acknowledgement the whole point of which is
--    goodwill should be fixable. The devotee is notified again only when the
--    reply actually changes, so correcting nothing notifies nobody.
-- ---------------------------------------------------------------------------

create or replace function public.review_feedback(
  p_feedback_id uuid,
  p_reply text default null
)
returns public.feedback
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_target public.feedback;
  v_reviewed public.feedback;
  v_reply text;
  v_reviewer_name text;
  v_should_notify boolean;
begin
  if auth.uid() is null then
    raise exception 'Sign in to review feedback.';
  end if;

  if not public.may_review_feedback() then
    raise exception 'Only the President or the Tech Admin can review feedback.';
  end if;

  select * into v_target
  from public.feedback
  where feedback.id = p_feedback_id
  for update;

  if v_target.id is null then
    raise exception 'That feedback could not be found.';
  end if;

  v_reply := nullif(btrim(coalesce(p_reply, ''), E' \t\n\r\f\v'), '');

  -- Silence is not a retraction: reviewing again without typing anything must
  -- not wipe an acknowledgement the devotee has already been shown.
  if v_reply is null then
    v_reply := v_target.reply;
  end if;

  v_should_notify :=
    v_target.status <> 'reviewed'
    or v_reply is distinct from v_target.reply;

  update public.feedback
  set
    status = 'reviewed',
    reply = v_reply,
    replied_by = auth.uid(),
    replied_at = now()
  where feedback.id = v_target.id
  returning * into v_reviewed;

  if v_should_notify then
    select users.name into v_reviewer_name
    from public.users where users.id = auth.uid();

    perform public.queue_app_notification(
      v_reviewed.devotee_id,
      'feedback_reviewed',
      case when v_reviewed.reply is null
        then 'Your feedback was read'
        else 'The temple replied to your feedback'
      end,
      case when v_reviewed.reply is null
        then coalesce(v_reviewer_name, 'The temple')
          || ' has read your feedback. Thank you.'
        else coalesce(v_reviewer_name, 'The temple') || ' replied: ' || v_reviewed.reply
      end,
      jsonb_build_object('feedbackId', v_reviewed.id)
    );
  end if;

  return v_reviewed;
end;
$$;

revoke all on function public.review_feedback(uuid, text) from public, anon;
grant execute on function public.review_feedback(uuid, text) to authenticated;

do $$
begin
  raise notice 'feedback applied';
end;
$$;
