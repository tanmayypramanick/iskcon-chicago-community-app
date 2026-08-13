-- Taking it back: removing a piece of feedback, and removing a newsletter story.
--
-- Two things a devotee can put into this app and then cannot get out of it
-- again. Both were written that way on purpose — 202608040041_feedback.sql
-- argues, correctly, that a record which can be rewritten underneath the person
-- who acted on it is worse than no record — but the temple has come back and
-- asked for removal, and removal is not rewriting. A devotee who sent a
-- complaint in temper on Sunday and regrets it on Monday currently has no way
-- to withdraw it; a devotee who submitted the wrong photograph of their child
-- to the newsletter currently has to ask an editor to do it for them. Neither
-- is a record the temple has any interest in keeping against the wishes of the
-- person who wrote it.
--
-- Who may remove what, and why the two answers differ:
--
--   feedback              the devotee who wrote it, or the President or the
--                         Tech Admin (app.view_all — held by exactly president
--                         and tech, see 202608020001_access_levels.sql).
--
--   newsletter story      the devotee who submitted it, or anybody who may
--                         manage the newsletter (may_manage_newsletter() —
--                         app.view_all *or* an appointed editor).
--
-- The asymmetry is deliberate and must be kept. Feedback is addressed to the
-- President and the Tech Admin; it is correspondence, and nobody outside the
-- two people it was written to has any business deleting it — least of all a
-- Community Head, who may well be the subject of it. A story submission is not
-- correspondence, it is raw material for an issue somebody is producing, and
-- the person producing that issue is often an appointed editor rather than the
-- President. An editor who can read a submission, reply to it and run it, but
-- who must go and find the President to remove a duplicate, is not an editor.
--
-- Note also what an editor's power here is *not*: appointment can be revoked,
-- and the instant it is, may_manage_newsletter() goes false and every door in
-- this file closes with it. That is the same shape delete_newsletter already
-- has, and for the same reason.
--
-- Requires 202608040041_feedback.sql and 202608040045_newsletter.sql.

-- ---------------------------------------------------------------------------
-- 1. Hard delete, not a tombstone.
--
--    Checked before deciding: nothing in this schema references either table.
--    No foreign key points at public.feedback or public.newsletter_submissions,
--    neither has replies, comments or children hanging off it, and the one
--    thing that does mention a row — an app_notifications row carrying
--    {"feedbackId": …} or {"submissionId": …} in its jsonb data — is a message
--    that was already delivered and read, not a dependency. It is left exactly
--    where it is, which is what delete_newsletter and delete_announcement
--    already do; a notification saying "the temple replied to your story" was
--    true when it was sent and does not become false because the devotee later
--    withdrew the story.
--
--    So there is nothing for a soft delete to protect, and three good reasons
--    not to add one:
--
--      * A deleted_at column is a promise that every reader remembers to filter
--        on it. There are two list functions per table plus a row level
--        security policy per table, and the next function added to either table
--        is one that will not know. A row that is gone cannot be leaked by a
--        query that forgot.
--
--      * The devotee's expectation is deletion. "Remove my feedback" from
--        somebody who wrote something in anger means the President stops being
--        able to read it, not that it moves to a column the President can still
--        read. A soft delete here would be a quieter feature than the one the
--        temple asked for, and quieter in the direction of the devotee's
--        privacy, which is the wrong direction to be quiet in.
--
--      * Both tables cascade from public.users already, so the schema's
--        existing answer to "this devotee's opinion should go with them" is
--        already a hard delete. A soft delete for the single-row case would
--        contradict it.
--
--    The removed row is returned, so the caller has the whole thing in hand for
--    an undo affordance, a confirmation toast, or a log — which is the only
--    thing a tombstone would have given the client anyway.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 2. One predicate per table, and both take the author rather than the row.
--
--    The rule has to be evaluated in three places each — the delete function,
--    and both list functions, which now hand the client a can_delete flag — and
--    three copies of a permission rule is three chances for one of them to be
--    the stale one. So it is written once.
--
--    Taking the author's id as an argument rather than the row's id is what
--    lets a list function call it per row without a second lookup: the list
--    already has devotee_id in hand, and a predicate that took a row id would
--    turn every list into a correlated subquery against a table the caller may
--    not be able to read.
--
--    Security definer, like may_manage_newsletter() and has_permission() before
--    them, and for the same dull reason: they read auth.uid() directly, and
--    reaching into the auth schema is a thing the owner does on the caller's
--    behalf rather than a thing the caller does. Definer is safe here because
--    neither takes an instruction — the only argument is an author id, both
--    bodies are a comparison against auth.uid() and a call to an existing
--    predicate, and there is no branch that returns true for a caller who is
--    neither the author nor already privileged.
-- ---------------------------------------------------------------------------

create or replace function public.may_delete_feedback(p_author_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    auth.uid() is not null
    and (
      p_author_id = auth.uid()
      or public.may_review_feedback()
    )
$$;

comment on function public.may_delete_feedback(uuid) is
  'True for the devotee who wrote the feedback, and for the President and the Tech Admin — the holders of app.view_all. Takes the author so a list can evaluate it per row without a second lookup.';

revoke all on function public.may_delete_feedback(uuid) from public, anon;
grant execute on function public.may_delete_feedback(uuid) to authenticated;

create or replace function public.may_delete_newsletter_submission(p_author_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    auth.uid() is not null
    and (
      p_author_id = auth.uid()
      or public.may_manage_newsletter()
    )
$$;

comment on function public.may_delete_newsletter_submission(uuid) is
  'True for the devotee who submitted the story, and for anybody who may manage the newsletter — the holders of app.view_all and any appointed editor. Takes the author so a list can evaluate it per row without a second lookup.';

revoke all on function public.may_delete_newsletter_submission(uuid) from public, anon;
grant execute on function public.may_delete_newsletter_submission(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Removing a piece of feedback.
--
--    The row is found and locked before the permission is judged, because
--    unlike review_feedback the permission depends on the row — you cannot ask
--    "is this yours" without it. That is the shape delete_announcement already
--    has. It does mean a devotee who guesses a uuid learns whether it exists
--    before being refused, which is a fair trade for an error message that
--    tells an honest devotee what actually went wrong, and a uuid nobody can
--    guess is not much of an oracle.
--
--    for update, so two taps on a slow connection cannot both get past the
--    check and race each other into the delete.
-- ---------------------------------------------------------------------------

create or replace function public.delete_feedback(p_feedback_id uuid)
returns public.feedback
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_target public.feedback;
begin
  if auth.uid() is null then
    raise exception 'Sign in to remove feedback.';
  end if;

  select * into v_target
  from public.feedback
  where feedback.id = p_feedback_id
  for update;

  if v_target.id is null then
    raise exception 'That feedback could not be found.';
  end if;

  if not public.may_delete_feedback(v_target.devotee_id) then
    raise exception 'You can remove your own feedback, or any feedback if you are the President or the Tech Admin.';
  end if;

  delete from public.feedback where feedback.id = v_target.id;

  return v_target;
end;
$$;

comment on function public.delete_feedback(uuid) is
  'Removes a piece of feedback outright and returns the removed row. The author, the President and the Tech Admin only.';

revoke all on function public.delete_feedback(uuid) from public, anon;
grant execute on function public.delete_feedback(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Removing a newsletter story submission.
--
--    The same shape, the wider predicate. The photographs and the document the
--    devotee attached are left in storage: the bucket policies already let a
--    devotee remove their own uploads, an editor may already have placed a
--    photograph into an issue that is out, and a function that reached into
--    storage on the strength of a text column would be deleting files it cannot
--    prove are unused.
-- ---------------------------------------------------------------------------

create or replace function public.delete_newsletter_submission(p_submission_id uuid)
returns public.newsletter_submissions
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_target public.newsletter_submissions;
begin
  if auth.uid() is null then
    raise exception 'Sign in to remove a newsletter story.';
  end if;

  select * into v_target
  from public.newsletter_submissions
  where newsletter_submissions.id = p_submission_id
  for update;

  if v_target.id is null then
    raise exception 'That newsletter story could not be found.';
  end if;

  if not public.may_delete_newsletter_submission(v_target.devotee_id) then
    raise exception 'You can remove your own story, or any story if you are the President, the Tech Admin, or an appointed newsletter editor.';
  end if;

  delete from public.newsletter_submissions
  where newsletter_submissions.id = v_target.id;

  return v_target;
end;
$$;

comment on function public.delete_newsletter_submission(uuid) is
  'Removes a newsletter story submission outright and returns the removed row. The author, the President, the Tech Admin, and any appointed newsletter editor.';

revoke all on function public.delete_newsletter_submission(uuid) from public, anon;
grant execute on function public.delete_newsletter_submission(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Telling the client, so it does not have to work it out.
--
--    Every one of these four lists backs a screen with a row on it, and every
--    row now needs to know whether to draw a remove button. A client that
--    re-derives the rule from a role name and an editor list is a fourth copy
--    of the rule, in another language, that nobody will update when this file
--    changes — and the failure mode is a button that appears and then throws.
--    So can_delete travels with the row, computed by the same predicate the
--    delete function asks. It is appended last in all four so that a client
--    reading positionally is not silently shifted.
--
--    Postgres will not widen a function's result in place, so each is dropped
--    with its full (empty) argument list first. All four take no arguments and
--    have no defaulted overloads; the drops are written out anyway, because a
--    surviving overload with defaults is exactly what makes a later call
--    ambiguous, and that has bitten this repo before.
--
--    Worth being plain about what can_delete says today: in all four functions,
--    every row a caller can see is a row that caller can remove. list_my_* only
--    ever returns your own, and list_all_* is gated on the very permission that
--    grants removal, so the flag is true for every row any of them hands back.
--    That is not a reason to hardcode it. The flag is the answer to "may I
--    remove this row", the predicate is the only definition of that answer, and
--    the moment either gate moves — a status that locks a row, a narrower read
--    grant, a wider list — a hardcoded true becomes a lie while a computed one
--    simply tells the truth. The verification asserts the flag against the
--    predicate row by row rather than asserting the constant.
-- ---------------------------------------------------------------------------

drop function if exists public.list_my_feedback();

create or replace function public.list_my_feedback()
returns table (
  id uuid,
  category text,
  body text,
  status text,
  reply text,
  replied_by_name text,
  replied_at timestamptz,
  created_at timestamptz,
  can_delete boolean
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
    feedback.created_at,
    public.may_delete_feedback(feedback.devotee_id)
  from public.feedback
  left join public.users replier on replier.id = feedback.replied_by
  where auth.uid() is not null
    and feedback.devotee_id = auth.uid()
  order by feedback.created_at desc
$$;

revoke all on function public.list_my_feedback() from public, anon;
grant execute on function public.list_my_feedback() to authenticated;

drop function if exists public.list_all_feedback();

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
  created_at timestamptz,
  can_delete boolean
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
    feedback.created_at,
    public.may_delete_feedback(feedback.devotee_id)
  from public.feedback
  join public.users devotee on devotee.id = feedback.devotee_id
  left join public.users replier on replier.id = feedback.replied_by
  where auth.uid() is not null
    and public.may_review_feedback()
  order by feedback.created_at desc
$$;

revoke all on function public.list_all_feedback() from public, anon;
grant execute on function public.list_all_feedback() to authenticated;

drop function if exists public.list_my_newsletter_submissions();

create or replace function public.list_my_newsletter_submissions()
returns table (
  id uuid,
  body text,
  image_urls text[],
  file_url text,
  status text,
  reply text,
  replied_by_name text,
  replied_at timestamptz,
  created_at timestamptz,
  can_manage boolean,
  can_delete boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    newsletter_submissions.id,
    newsletter_submissions.body,
    newsletter_submissions.image_urls,
    newsletter_submissions.file_url,
    newsletter_submissions.status,
    newsletter_submissions.reply,
    replier.name,
    newsletter_submissions.replied_at,
    newsletter_submissions.created_at,
    public.may_manage_newsletter(),
    public.may_delete_newsletter_submission(newsletter_submissions.devotee_id)
  from public.newsletter_submissions
  left join public.users replier on replier.id = newsletter_submissions.replied_by
  where auth.uid() is not null
    and newsletter_submissions.devotee_id = auth.uid()
  order by newsletter_submissions.created_at desc
$$;

revoke all on function public.list_my_newsletter_submissions() from public, anon;
grant execute on function public.list_my_newsletter_submissions() to authenticated;

drop function if exists public.list_all_newsletter_submissions();

create or replace function public.list_all_newsletter_submissions()
returns table (
  id uuid,
  devotee_id uuid,
  devotee_name text,
  devotee_photo_url text,
  body text,
  image_urls text[],
  file_url text,
  status text,
  reply text,
  replied_by uuid,
  replied_by_name text,
  replied_at timestamptz,
  created_at timestamptz,
  can_manage boolean,
  can_delete boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    newsletter_submissions.id,
    newsletter_submissions.devotee_id,
    devotee.name,
    devotee.photo_url,
    newsletter_submissions.body,
    newsletter_submissions.image_urls,
    newsletter_submissions.file_url,
    newsletter_submissions.status,
    newsletter_submissions.reply,
    newsletter_submissions.replied_by,
    replier.name,
    newsletter_submissions.replied_at,
    newsletter_submissions.created_at,
    true,
    public.may_delete_newsletter_submission(newsletter_submissions.devotee_id)
  from public.newsletter_submissions
  join public.users devotee on devotee.id = newsletter_submissions.devotee_id
  left join public.users replier on replier.id = newsletter_submissions.replied_by
  where auth.uid() is not null
    and public.may_manage_newsletter()
  order by newsletter_submissions.created_at desc
$$;

revoke all on function public.list_all_newsletter_submissions() from public, anon;
grant execute on function public.list_all_newsletter_submissions() to authenticated;

do $$
begin
  raise notice 'removals applied';
end;
$$;
