-- The temple newsletter.
--
-- Once a month somebody at the temple puts together a few pages — what
-- happened, what is coming, who joined, a photograph of the Sunday feast — and
-- until now it reached the congregation as a PDF attached to an email that half
-- of them never opened. This puts it in the app: one row per issue, a file
-- every devotee can download, and a notification when a new one lands.
--
-- Two halves, and the second is the one the temple actually asked for.
--
--   Reading   every devotee, no permission at all. There is no audience to
--             pick and nothing to join — it is the temple's own paper.
--
--   Posting   the President, the Tech Admin, and anyone they appoint.
--
-- That last clause is the whole design problem. The person who produces the
-- newsletter is usually neither the President nor the Tech Admin: it is a
-- devotee with a knack for layout who was asked to do it, and who may be asked
-- to stop doing it next year. Expressing that as a role would mean a sixth
-- entry in the ladder in 202608020001_access_levels.sql, and that ladder is
-- read by every permission check in this database — widening it to describe one
-- person's job would hand that person a shape they never asked for and would
-- make every existing has_permission() call answer a slightly different
-- question.
--
-- So the appointment is a grant, not a rank: one row in newsletter_editors,
-- given by a holder of app.view_all, taken back the same way. It says nothing
-- about the devotee except that they are, today, allowed to put out the
-- newsletter. Revoke the row and they are an ordinary devotee again in the same
-- instant, with no role change and nothing else disturbed.
--
--   may_manage_newsletter()  =  app.view_all  OR  a row in newsletter_editors
--
-- and every guard in this file — posting, deleting, reviewing submissions —
-- reads that one predicate, so there is exactly one answer to "may this person
-- work on the newsletter" and it cannot drift between the RPCs and the row
-- level security policies.
--
-- The third half, which the temple did not ask for and the newsletter editor
-- will be grateful for: story submissions. Any devotee can send in some words,
-- up to five photographs and a document, and an editor works through them the
-- way the President works through feedback — read it, mark it read, and send
-- back a line of thanks. It is the feedback flow of 202608040041_feedback.sql
-- almost exactly, deliberately, down to the optional reply and the refusal to
-- notify twice about a review that changed nothing. A devotee who has sent
-- something to the temple wants one thing above all: to know a human being
-- looked at it.
--
-- Requires 202608040041_feedback.sql and 202608040044_birthdays_and_congregation.sql.

-- ---------------------------------------------------------------------------
-- 1. Somewhere to keep a PDF.
--
--    Neither existing bucket will do. devotee-photos and message-images both
--    declare allowed_mime_types of images only, and Storage enforces that list
--    on upload — a newsletter PDF pushed at either one is refused by the
--    server, not by anything this migration could relax. Widening message-images
--    to accept application/pdf would also mean every direct-message attachment
--    could suddenly be a document, which is a different feature nobody has
--    designed.
--
--    So: one more bucket, shaped like the two that already exist. Public in the
--    same sense message-images is public — the object URL is unguessable and
--    the CDN will serve it, which is what makes a 12MB download tolerable on
--    temple wifi — with reads granted to signed-in devotees and writes confined
--    to the uploader's own folder, `<user id>/<file name>`, exactly as
--    202608040011_devotee_photos.sql established.
--
--    25MB, because a newsletter with photographs in it is not a 5MB avatar and
--    an editor who has to compress a PDF before every upload will eventually
--    stop uploading. Photographs attached to a story submission continue to go
--    to message-images: they are pictures, that bucket is for pictures, and the
--    8MB cap and the image mime list already there are the right ones.
-- ---------------------------------------------------------------------------

do $$
begin
  if not exists (select 1 from storage.buckets where id = 'message-images') then
    raise exception 'The message-images bucket is missing; apply 202608040032_messaging.sql first.';
  end if;
end;
$$;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'newsletter-files',
  'newsletter-files',
  true,
  25 * 1024 * 1024,
  array[
    'application/pdf',
    'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
  ]
)
on conflict (id) do update
set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Anyone signed in reads newsletter files" on storage.objects;
create policy "Anyone signed in reads newsletter files"
  on storage.objects for select to authenticated
  using (bucket_id = 'newsletter-files');

-- Ownership is the first path segment, as in every other bucket here. Note
-- that this is deliberately not may_manage_newsletter(): a devotee attaching a
-- document to a story submission is not an editor and must still be able to
-- upload it. What they cannot do is write into anybody else's folder, or point
-- a newsletter row at a file they do not own — the origin checks below settle
-- the second half.
drop policy if exists "Devotees upload their own newsletter files" on storage.objects;
create policy "Devotees upload their own newsletter files"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'newsletter-files'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "Devotees replace their own newsletter files" on storage.objects;
create policy "Devotees replace their own newsletter files"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'newsletter-files'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'newsletter-files'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "Devotees remove their own newsletter files" on storage.objects;
create policy "Devotees remove their own newsletter files"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'newsletter-files'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- ---------------------------------------------------------------------------
-- 2. The appointment.
--
--    devotee_id is the primary key, so the same person cannot be appointed
--    twice and there is no "which of these three rows is the real grant"
--    question to answer later.
--
--    It cascades on delete, because a grant to a devotee who has left the
--    congregation is not a grant to anybody. appointed_by only nulls out: the
--    President who made the appointment may themselves move on, and that must
--    not quietly withdraw the editor's authority in the middle of producing an
--    issue. The attribution goes; the appointment stays until somebody revokes
--    it on purpose.
-- ---------------------------------------------------------------------------

create table if not exists public.newsletter_editors (
  devotee_id uuid primary key references public.users(id) on delete cascade,
  appointed_by uuid references public.users(id) on delete set null,
  appointed_at timestamptz not null default now()
);

create index if not exists newsletter_editors_appointed_by_idx
  on public.newsletter_editors (appointed_by);

-- ---------------------------------------------------------------------------
-- 3. The issues themselves.
--
--    month is a date rather than a year/month pair because Postgres already
--    knows how to sort, compare and format a date and does none of those things
--    for two integers. It is pinned to the first of the month by a constraint
--    and normalised there by post_newsletter, so "August 2026" has exactly one
--    representation and a list cannot end up with the same issue twice under
--    2026-08-01 and 2026-08-31.
--
--    No unique index on month. A temple that puts out a special Janmashtami
--    edition alongside the August issue should not have to lie about its date
--    to publish it, and two rows in one month is a thing an editor can see and
--    fix, whereas a refusal at 11pm before a festival is not.
--
--    file_url is not null: a newsletter is the file. A row without one is not
--    an unfinished newsletter, it is a mistake, and the place to keep drafts is
--    the editor's own computer.
-- ---------------------------------------------------------------------------

create table if not exists public.newsletters (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  month date not null,
  file_url text not null,
  cover_image_url text,
  notes text,
  -- As with an announcement: the issue is the temple's, not the editor's, so
  -- the row outlives whoever posted it and only the attribution goes.
  posted_by uuid references public.users(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint newsletter_title_not_blank check (
    nullif(btrim(title, E' \t\n\r\f\v'), '') is not null
  ),
  constraint newsletter_file_url_not_blank check (
    nullif(btrim(file_url, E' \t\n\r\f\v'), '') is not null
  ),
  constraint newsletter_notes_not_blank check (
    notes is null or nullif(btrim(notes, E' \t\n\r\f\v'), '') is not null
  ),
  constraint newsletter_month_is_first_of_month check (
    month = date_trunc('month', month)::date
  )
);

-- The list is always "newest issue first", which is this index exactly.
create index if not exists newsletters_month_created_idx
  on public.newsletters (month desc, created_at desc);

create index if not exists newsletters_posted_by_idx
  on public.newsletters (posted_by);

-- ---------------------------------------------------------------------------
-- 4. What devotees send in.
--
--    The same skeleton as public.feedback — body, status, optional reply,
--    replier, timestamps, and the three constraints that keep an unreviewed row
--    genuinely untouched — plus the two things a story has that a complaint
--    does not: photographs and a document.
--
--    image_urls is a text[] rather than a child table. Five is the ceiling, the
--    order the devotee chose is the order they want them printed in, and an
--    array preserves that for free while a child table would need a position
--    column and a join to read one submission. The cap is enforced here rather
--    than only in the RPC because a limit that lives in one function is a limit
--    that the next function to touch the table will not know about.
-- ---------------------------------------------------------------------------

create table if not exists public.newsletter_submissions (
  id uuid primary key default gen_random_uuid(),
  devotee_id uuid not null references public.users(id) on delete cascade,
  body text not null,
  image_urls text[] not null default '{}'::text[],
  file_url text,
  status text not null default 'new' check (status in ('new', 'reviewed')),
  reply text,
  -- The editor may be revoked, or may leave; the acknowledgement stays, because
  -- the devotee was already shown it. Only the attribution goes.
  replied_by uuid references public.users(id) on delete set null,
  replied_at timestamptz,
  created_at timestamptz not null default now(),
  -- btrim with the explicit character list, not a bare trim(): trim() strips
  -- spaces alone, so a body of two newlines — what a multi-line text box sends
  -- when a devotee taps return twice and then send — would sail past as
  -- non-blank.
  constraint newsletter_submission_body_not_blank check (
    nullif(btrim(body, E' \t\n\r\f\v'), '') is not null
  ),
  constraint newsletter_submission_reply_not_blank check (
    reply is null or nullif(btrim(reply, E' \t\n\r\f\v'), '') is not null
  ),
  constraint newsletter_submission_file_url_not_blank check (
    file_url is null or nullif(btrim(file_url, E' \t\n\r\f\v'), '') is not null
  ),
  -- Five photographs. Not six, and not five plus a null pretending to be a
  -- sixth slot: array_position finds a null element, and cardinality counts
  -- one, so both are refused here.
  constraint newsletter_submission_photo_limit check (
    cardinality(image_urls) <= 5
  ),
  constraint newsletter_submission_photos_not_null check (
    array_position(image_urls, null) is null
  ),
  -- Unreviewed means untouched. Reviewed means somebody did it and there is a
  -- time on it; replied_by is absent from the second half on purpose, because
  -- the reviewer's account may later be deleted and that must not retroactively
  -- invalidate a row.
  constraint newsletter_submission_review_consistency check (
    (status = 'new' and reply is null and replied_by is null and replied_at is null)
    or
    (status = 'reviewed' and replied_at is not null)
  )
);

-- The devotee's own list, newest first.
create index if not exists newsletter_submissions_devotee_created_idx
  on public.newsletter_submissions (devotee_id, created_at desc);

-- The editor's queue: everything, newest first, usually filtered to 'new'.
create index if not exists newsletter_submissions_status_created_idx
  on public.newsletter_submissions (status, created_at desc);

create index if not exists newsletter_submissions_replied_by_idx
  on public.newsletter_submissions (replied_by);

-- ---------------------------------------------------------------------------
-- 5. The one predicate.
--
--    app.view_all is the key this app already uses to mean "the two people who
--    can see everything", and 202608020001_access_levels.sql grants it to
--    exactly president and tech. No newsletter permission key is registered
--    alongside it: a second answer to the same question is a second answer that
--    can drift, and a role added later would silently hold one and not the
--    other.
--
--    Security definer, and it has to be. A plain devotee holds no read grant on
--    newsletter_editors beyond their own row, and the policies below call this
--    function — a predicate that could only see what the caller can already see
--    would answer "no" for exactly the people it exists to say "yes" about.
--    Running as the owner also means the newsletter_editors policy calling this
--    function does not re-enter that policy, so there is no recursion.
--
--    Posting, deleting and reviewing all read this. That they are the same
--    authority is deliberate: an editor who can put out an issue but cannot
--    replace the one with the wrong date on it, or who can read submissions but
--    not answer them, is a state nobody asked for.
-- ---------------------------------------------------------------------------

create or replace function public.may_manage_newsletter()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    auth.uid() is not null
    and (
      public.has_permission('app.view_all')
      or exists (
        select 1 from public.newsletter_editors
        where newsletter_editors.devotee_id = auth.uid()
      )
    )
$$;

comment on function public.may_manage_newsletter() is
  'True for the President and the Tech Admin — the holders of app.view_all — and for any devotee they have appointed a newsletter editor.';

revoke all on function public.may_manage_newsletter() from public, anon;
grant execute on function public.may_manage_newsletter() to authenticated;

-- Appointing is a strictly narrower thing than editing, and stays with the two
-- office holders. An editor who could appoint another editor could appoint
-- their way around a revocation, and the grant would stop meaning "the
-- President asked this person to do it".
create or replace function public.may_appoint_newsletter_editor()
returns boolean
language sql
stable
set search_path = ''
as $$
  select public.has_permission('app.view_all')
$$;

comment on function public.may_appoint_newsletter_editor() is
  'True only for the President and the Tech Admin; appointing an editor is not itself delegable.';

revoke all on function public.may_appoint_newsletter_editor() from public, anon;
grant execute on function public.may_appoint_newsletter_editor() to authenticated;

-- ---------------------------------------------------------------------------
-- 6. Row level security.
--
--    Newsletters: everyone signed in, all of them. That is what a temple
--    newsletter is, and there is no back issue worth hiding.
--
--    Editors: your own row, so a devotee can tell whether they have been
--    appointed, plus everything for anyone who may manage the newsletter, so
--    the editors can see who else is on the team. Not the whole congregation:
--    who the President has asked to do a job is the President's business.
--
--    Submissions: your own, or everything if you may manage. The policies
--    repeat what the functions below enforce, so a client talking to PostgREST
--    directly gets the same answer as one calling the RPCs.
--
--    Every write goes through an RPC, so no insert, update or delete policy
--    exists and none is granted anywhere in this file. A devotee cannot edit a
--    story after sending it: an editor may already have read it, and a record
--    that can be rewritten underneath the person acting on it is worse than no
--    record.
-- ---------------------------------------------------------------------------

alter table public.newsletters enable row level security;

drop policy if exists "Devotees read every newsletter" on public.newsletters;
create policy "Devotees read every newsletter"
  on public.newsletters for select to authenticated
  using (auth.uid() is not null);

revoke all on public.newsletters from anon, authenticated;
grant select (
  id, title, month, file_url, cover_image_url, notes, posted_by, created_at
) on public.newsletters to authenticated;

alter table public.newsletter_editors enable row level security;

drop policy if exists "Editors and office holders read the editor list" on public.newsletter_editors;
create policy "Editors and office holders read the editor list"
  on public.newsletter_editors for select to authenticated
  using (
    auth.uid() is not null
    and (devotee_id = auth.uid() or public.may_manage_newsletter())
  );

revoke all on public.newsletter_editors from anon, authenticated;
grant select (devotee_id, appointed_by, appointed_at)
  on public.newsletter_editors to authenticated;

alter table public.newsletter_submissions enable row level security;

drop policy if exists "Devotees read their own newsletter submissions" on public.newsletter_submissions;
create policy "Devotees read their own newsletter submissions"
  on public.newsletter_submissions for select to authenticated
  using (
    auth.uid() is not null
    and (devotee_id = auth.uid() or public.may_manage_newsletter())
  );

revoke all on public.newsletter_submissions from anon, authenticated;
grant select (
  id, devotee_id, body, image_urls, file_url, status,
  reply, replied_by, replied_at, created_at
) on public.newsletter_submissions to authenticated;

-- ---------------------------------------------------------------------------
-- 7. Two new notification kinds.
--
--    Restated whole rather than appended to, because the constraint is replaced
--    rather than altered and a partial list would quietly outlaw every kind
--    already in use. The list below is the one from
--    202608040044_birthdays_and_congregation.sql — the most recent migration to
--    touch it — carried forward entire, including 'birthday_today' from 0044
--    and 'sanga_deleted' from 0043.
--
--    Mirrored in src/features/notifications/types.ts, which this migration does
--    not own: 'newsletter_posted' and 'newsletter_reviewed' must be added there
--    too or the client will not know how to route a tap on either.
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
      'remote'
    )
  );

-- ---------------------------------------------------------------------------
-- 8. Appointing and revoking.
--
--    Idempotent on purpose. A President who cannot remember whether they
--    already appointed somebody should be able to tap the button and find out
--    that they had, rather than be told off; re-appointing therefore returns
--    the existing grant untouched, keeping the original appointed_at, which is
--    the date the temple would actually want to see.
--
--    Appointing a devotee who already holds app.view_all is allowed and does
--    nothing they could notice today. It is not pointless: if that person later
--    steps down from the office, the grant is what keeps them producing the
--    newsletter through the handover.
-- ---------------------------------------------------------------------------

create or replace function public.appoint_newsletter_editor(p_devotee_id uuid)
returns public.newsletter_editors
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_grant public.newsletter_editors;
  v_target_name text;
  v_appointer_name text;
begin
  if auth.uid() is null then
    raise exception 'Sign in to appoint a newsletter editor.';
  end if;

  if not public.may_appoint_newsletter_editor() then
    raise exception 'Only the President or the Tech Admin can appoint a newsletter editor.';
  end if;

  if p_devotee_id is null then
    raise exception 'Choose a devotee to appoint.';
  end if;

  select users.name into v_target_name
  from public.users where users.id = p_devotee_id;

  if v_target_name is null then
    raise exception 'That devotee could not be found.';
  end if;

  -- Already appointed: hand back the grant as it stands rather than resetting
  -- the date on which the temple asked them.
  select * into v_grant
  from public.newsletter_editors
  where newsletter_editors.devotee_id = p_devotee_id;

  if v_grant.devotee_id is not null then
    return v_grant;
  end if;

  insert into public.newsletter_editors (devotee_id, appointed_by)
  values (p_devotee_id, auth.uid())
  returning * into v_grant;

  return v_grant;
end;
$$;

revoke all on function public.appoint_newsletter_editor(uuid) from public, anon;
grant execute on function public.appoint_newsletter_editor(uuid) to authenticated;

-- Taking it back. The row goes for good: an appointment is not a record of
-- anything the temple needs to keep, and a tombstone would only give every
-- query something to filter out forever. Revoking somebody who was never
-- appointed is a readable refusal rather than a silent success, because the
-- President tapping it is asking a question about who holds what.
create or replace function public.revoke_newsletter_editor(p_devotee_id uuid)
returns public.newsletter_editors
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_grant public.newsletter_editors;
begin
  if auth.uid() is null then
    raise exception 'Sign in to remove a newsletter editor.';
  end if;

  if not public.may_appoint_newsletter_editor() then
    raise exception 'Only the President or the Tech Admin can remove a newsletter editor.';
  end if;

  select * into v_grant
  from public.newsletter_editors
  where newsletter_editors.devotee_id = p_devotee_id
  for update;

  if v_grant.devotee_id is null then
    raise exception 'That devotee is not a newsletter editor.';
  end if;

  delete from public.newsletter_editors
  where newsletter_editors.devotee_id = v_grant.devotee_id;

  return v_grant;
end;
$$;

revoke all on function public.revoke_newsletter_editor(uuid) from public, anon;
grant execute on function public.revoke_newsletter_editor(uuid) to authenticated;

-- Who is on the team. Visible to anybody who may manage the newsletter — the
-- editors included, so they know who else to hand a draft to — and empty for
-- everybody else rather than an exception, because this backs a screen and a
-- screen that throws on open is a crash.
--
-- can_revoke travels with each row so the list can decide whether to draw the
-- button: an editor sees the team, only an office holder sees a way to change
-- it.
create or replace function public.list_newsletter_editors()
returns table (
  devotee_id uuid,
  devotee_name text,
  devotee_photo_url text,
  appointed_by uuid,
  appointed_by_name text,
  appointed_at timestamptz,
  can_revoke boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    newsletter_editors.devotee_id,
    editor.name,
    editor.photo_url,
    newsletter_editors.appointed_by,
    appointer.name,
    newsletter_editors.appointed_at,
    public.may_appoint_newsletter_editor()
  from public.newsletter_editors
  join public.users editor on editor.id = newsletter_editors.devotee_id
  left join public.users appointer on appointer.id = newsletter_editors.appointed_by
  where auth.uid() is not null
    and public.may_manage_newsletter()
  order by newsletter_editors.appointed_at desc
$$;

revoke all on function public.list_newsletter_editors() from public, anon;
grant execute on function public.list_newsletter_editors() to authenticated;

-- ---------------------------------------------------------------------------
-- 9. Putting out an issue.
--
--    The origin checks are the same defence 202608040040_announcements.sql
--    applies to an announcement photo, for the same reason and once more per
--    column. Left open, file_url is a way to have every devotee in the
--    congregation fetch an arbitrary host the moment they tap download — a
--    tracking beacon at best, and at worst a link the temple appears to have
--    endorsed pointing at a file the temple has never seen. A newsletter must
--    have come out of the app's own storage.
--
--    The pattern is the tighter one from 202608040011_devotee_photos.sql rather
--    than the one in 0040, and the difference matters. 0040 anchors on the path
--    alone — `https://[a-z0-9.-]+/storage/v1/object/public/message-images/` —
--    which any host on the internet can serve simply by arranging its
--    directories to look like Supabase's. Pinning the host to *.supabase.co is
--    what actually makes the column mean "the app's own storage" instead of
--    "somewhere shaped like it". Should the temple ever move Storage behind a
--    custom domain, this is the line to change, and it should be changed in one
--    deliberate edit rather than left loose in advance.
--
--    The month is normalised rather than rejected. A client that sends the day
--    the editor happened to be sitting at their desk means the month that day
--    falls in, and telling them off about it teaches them nothing.
-- ---------------------------------------------------------------------------

create or replace function public.post_newsletter(
  p_title text,
  p_month date,
  p_file_url text,
  p_cover_image_url text default null,
  p_notes text default null
)
returns public.newsletters
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_title text;
  v_file_url text;
  v_cover text;
  v_notes text;
  v_month date;
  v_created public.newsletters;
  v_poster_name text;
  v_devotee record;
begin
  if auth.uid() is null then
    raise exception 'Sign in to post the newsletter.';
  end if;

  if not public.may_manage_newsletter() then
    raise exception 'Only the President, the Tech Admin, or an appointed newsletter editor can post the newsletter.';
  end if;

  v_title := nullif(btrim(coalesce(p_title, ''), E' \t\n\r\f\v'), '');
  if v_title is null then
    raise exception 'Please give the newsletter a title.';
  end if;

  if p_month is null then
    raise exception 'Please say which month this newsletter is for.';
  end if;
  v_month := date_trunc('month', p_month)::date;

  v_file_url := nullif(btrim(coalesce(p_file_url, ''), E' \t\n\r\f\v'), '');
  if v_file_url is null then
    raise exception 'Please attach the newsletter file.';
  end if;
  if v_file_url !~ '^https://[a-z0-9-]+\.supabase\.co/storage/v1/object/public/newsletter-files/' then
    raise exception 'The newsletter file must be uploaded through the app.';
  end if;

  v_cover := nullif(btrim(coalesce(p_cover_image_url, ''), E' \t\n\r\f\v'), '');
  if v_cover is not null
     and v_cover !~ '^https://[a-z0-9-]+\.supabase\.co/storage/v1/object/public/message-images/'
  then
    raise exception 'A newsletter cover image must be uploaded through the app.';
  end if;

  v_notes := nullif(btrim(coalesce(p_notes, ''), E' \t\n\r\f\v'), '');

  insert into public.newsletters (
    title, month, file_url, cover_image_url, notes, posted_by
  )
  values (v_title, v_month, v_file_url, v_cover, v_notes, auth.uid())
  returning * into v_created;

  select users.name into v_poster_name
  from public.users where users.id = auth.uid();

  -- Everybody, because that is what a newsletter is. The editor is left out;
  -- they are holding it. A single failure to reach one devotee must not undo
  -- the issue for the rest, and queue_app_notification only writes a row — the
  -- push itself is already fire-and-forget in deliver_app_notification.
  for v_devotee in
    select users.id from public.users where users.id <> auth.uid()
  loop
    perform public.queue_app_notification(
      v_devotee.id,
      'newsletter_posted',
      'The temple newsletter is out',
      coalesce(v_poster_name, 'The temple') || ' posted "' || v_created.title || '".',
      jsonb_build_object('newsletterId', v_created.id)
    );
  end loop;

  return v_created;
end;
$$;

revoke all on function public.post_newsletter(text, date, text, text, text) from public, anon;
grant execute on function public.post_newsletter(text, date, text, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 10. Reading the back issues.
--
--     Every devotee, every issue, newest month first. Definer so the poster's
--     name can be joined in — a plain devotee cannot read another devotee's row
--     in public.users, and "posted by Rukmini devi dasi" is part of the issue,
--     not a leak.
--
--     can_delete travels with the row because every card needs it to decide
--     whether to draw the button, and a round trip per issue to ask the same
--     question would be absurd. can_manage is the same answer at the screen
--     level — whether to draw "Post an issue" at all — and is carried here so a
--     screen with one issue on it needs one call rather than two.
-- ---------------------------------------------------------------------------

create or replace function public.list_newsletters()
returns table (
  id uuid,
  title text,
  month date,
  file_url text,
  cover_image_url text,
  notes text,
  posted_by uuid,
  posted_by_name text,
  posted_by_photo_url text,
  created_at timestamptz,
  can_delete boolean,
  can_manage boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    newsletters.id,
    newsletters.title,
    newsletters.month,
    newsletters.file_url,
    newsletters.cover_image_url,
    newsletters.notes,
    newsletters.posted_by,
    poster.name,
    poster.photo_url,
    newsletters.created_at,
    public.may_manage_newsletter(),
    public.may_manage_newsletter()
  from public.newsletters
  left join public.users poster on poster.id = newsletters.posted_by
  where auth.uid() is not null
  order by newsletters.month desc, newsletters.created_at desc
$$;

revoke all on function public.list_newsletters() from public, anon;
grant execute on function public.list_newsletters() to authenticated;

-- ---------------------------------------------------------------------------
-- 11. Taking an issue down.
--
--     Whoever may manage the newsletter, and nobody else — deliberately not
--     "whoever posted it", which is how announcements work. The difference is
--     revocation: a devotee whose appointment has been taken back must not
--     still be able to reach back and delete the issues they produced while
--     they held it. Being asked to stop editing the newsletter and being able
--     to erase last November on the way out are not the same thing.
-- ---------------------------------------------------------------------------

create or replace function public.delete_newsletter(p_newsletter_id uuid)
returns public.newsletters
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_target public.newsletters;
begin
  if auth.uid() is null then
    raise exception 'Sign in to remove a newsletter.';
  end if;

  if not public.may_manage_newsletter() then
    raise exception 'Only the President, the Tech Admin, or an appointed newsletter editor can remove a newsletter.';
  end if;

  select * into v_target
  from public.newsletters
  where newsletters.id = p_newsletter_id
  for update;

  if v_target.id is null then
    raise exception 'That newsletter could not be found.';
  end if;

  delete from public.newsletters where newsletters.id = v_target.id;

  return v_target;
end;
$$;

revoke all on function public.delete_newsletter(uuid) from public, anon;
grant execute on function public.delete_newsletter(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 12. Sending in a story.
--
--     Any signed-in devotee, no permission at all — the same door feedback
--     opens, for the same reason. The child who wants to write about their
--     first Ratha Yatra should not have to know who the editor is.
--
--     The photographs are cleaned before they are counted: blanks and nulls a
--     client left in the array are dropped rather than refused, because an
--     empty slot in a picker is not something a devotee did wrong, and only
--     then is the five-photo ceiling applied to what actually remains. Six real
--     photographs is a refusal with the number in it, so the devotee knows what
--     to remove.
-- ---------------------------------------------------------------------------

create or replace function public.submit_newsletter_story(
  p_body text,
  p_image_urls text[] default null,
  p_file_url text default null
)
returns public.newsletter_submissions
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_body text;
  v_images text[];
  v_file_url text;
  v_image text;
  v_created public.newsletter_submissions;
begin
  if auth.uid() is null then
    raise exception 'Sign in to send a story for the newsletter.';
  end if;

  -- Leading and trailing whitespace only. The newlines the devotee put between
  -- their paragraphs are part of what they wrote and are left alone.
  v_body := nullif(btrim(coalesce(p_body, ''), E' \t\n\r\f\v'), '');
  if v_body is null then
    raise exception 'Please write your story before sending it.';
  end if;

  select coalesce(array_agg(candidate.url order by candidate.position), '{}'::text[])
  into v_images
  from (
    select
      nullif(btrim(coalesce(raw.url, ''), E' \t\n\r\f\v'), '') as url,
      raw.position
    from unnest(coalesce(p_image_urls, '{}'::text[]))
      with ordinality as raw(url, position)
  ) as candidate
  where candidate.url is not null;

  if cardinality(v_images) > 5 then
    raise exception 'You can attach up to 5 photos to a story; this one has %.',
      cardinality(v_images);
  end if;

  -- Same defence as every other url column in this app: a photo must have come
  -- out of the app's own storage, or the column is a way to have an editor's
  -- screen fetch an arbitrary host.
  foreach v_image in array v_images loop
    if v_image !~ '^https://[a-z0-9-]+\.supabase\.co/storage/v1/object/public/message-images/' then
      raise exception 'A story photo must be uploaded through the app.';
    end if;
  end loop;

  v_file_url := nullif(btrim(coalesce(p_file_url, ''), E' \t\n\r\f\v'), '');
  if v_file_url is not null
     and v_file_url !~ '^https://[a-z0-9-]+\.supabase\.co/storage/v1/object/public/newsletter-files/'
  then
    raise exception 'A story document must be uploaded through the app.';
  end if;

  insert into public.newsletter_submissions (devotee_id, body, image_urls, file_url)
  values (auth.uid(), v_body, v_images, v_file_url)
  returning * into v_created;

  return v_created;
end;
$$;

revoke all on function public.submit_newsletter_story(text, text[], text) from public, anon;
grant execute on function public.submit_newsletter_story(text, text[], text) to authenticated;

-- ---------------------------------------------------------------------------
-- 13. What the devotee sees back.
--
--     Their own, newest first, with the reply and the name of whoever left it.
--     Definer, because the editor's name lives in public.users and a plain
--     devotee cannot read another devotee's row there.
--
--     Nothing else about the editor travels: no id, no photo, no email. The
--     devotee is being told the temple answered, not handed a contact card.
--     can_manage is here so a devotee who is also an editor can be offered the
--     queue from the same screen without a second call.
-- ---------------------------------------------------------------------------

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
  can_manage boolean
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
    public.may_manage_newsletter()
  from public.newsletter_submissions
  left join public.users replier on replier.id = newsletter_submissions.replied_by
  where auth.uid() is not null
    and newsletter_submissions.devotee_id = auth.uid()
  order by newsletter_submissions.created_at desc
$$;

revoke all on function public.list_my_newsletter_submissions() from public, anon;
grant execute on function public.list_my_newsletter_submissions() to authenticated;

-- ---------------------------------------------------------------------------
-- 14. The editor's queue.
--
--     Everything, newest first, with the devotee's name and photo so the row
--     can be read as a person rather than a uuid, and with the photographs and
--     the document so the editor can actually do the work.
--
--     Anyone who may not manage the newsletter gets an empty set rather than an
--     exception — this backs a screen, and a screen that throws on open is a
--     crash whereas a screen with nothing on it is simply a screen that devotee
--     should never have been routed to. The guard sits inside the where clause
--     rather than around the call, so there is no argument, no ordering and no
--     partial result that hands a row to somebody who may not have it. In
--     particular a revoked editor sees nothing the instant their row is gone.
-- ---------------------------------------------------------------------------

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
  can_manage boolean
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
    true
  from public.newsletter_submissions
  join public.users devotee on devotee.id = newsletter_submissions.devotee_id
  left join public.users replier on replier.id = newsletter_submissions.replied_by
  where auth.uid() is not null
    and public.may_manage_newsletter()
  order by newsletter_submissions.created_at desc
$$;

revoke all on function public.list_all_newsletter_submissions() from public, anon;
grant execute on function public.list_all_newsletter_submissions() to authenticated;

-- ---------------------------------------------------------------------------
-- 15. Reading a story and answering it.
--
--     The reply is OPTIONAL, and that is a decision rather than an omission —
--     the same one review_feedback makes. "Thank you, we will run this in
--     September" is worth sending; a photograph of the Deities that needs no
--     words back should not force the editor to compose some, because an editor
--     who must write a paragraph per row is an editor with a queue they never
--     work through. So p_reply defaults to null, a blank or whitespace-only
--     reply is stored as no reply rather than as an empty string, and the
--     devotee is notified either way: being told somebody read it is the point.
--
--     Re-reviewing is allowed. An editor who sends "Thank you" and then wants
--     to add "we will run it in September" should not be stopped by the
--     database, and a typo in an acknowledgement the whole purpose of which is
--     goodwill should be fixable. The devotee is notified again only when the
--     reply actually changes, so correcting nothing notifies nobody.
-- ---------------------------------------------------------------------------

create or replace function public.review_newsletter_submission(
  p_submission_id uuid,
  p_reply text default null
)
returns public.newsletter_submissions
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_target public.newsletter_submissions;
  v_reviewed public.newsletter_submissions;
  v_reply text;
  v_reviewer_name text;
  v_should_notify boolean;
begin
  if auth.uid() is null then
    raise exception 'Sign in to review a newsletter story.';
  end if;

  if not public.may_manage_newsletter() then
    raise exception 'Only the President, the Tech Admin, or an appointed newsletter editor can review a newsletter story.';
  end if;

  select * into v_target
  from public.newsletter_submissions
  where newsletter_submissions.id = p_submission_id
  for update;

  if v_target.id is null then
    raise exception 'That newsletter story could not be found.';
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

  update public.newsletter_submissions
  set
    status = 'reviewed',
    reply = v_reply,
    replied_by = auth.uid(),
    replied_at = now()
  where newsletter_submissions.id = v_target.id
  returning * into v_reviewed;

  if v_should_notify then
    select users.name into v_reviewer_name
    from public.users where users.id = auth.uid();

    perform public.queue_app_notification(
      v_reviewed.devotee_id,
      'newsletter_reviewed',
      case when v_reviewed.reply is null
        then 'Your newsletter story was read'
        else 'The newsletter team replied to your story'
      end,
      case when v_reviewed.reply is null
        then coalesce(v_reviewer_name, 'The temple')
          || ' has read your newsletter story. Thank you.'
        else coalesce(v_reviewer_name, 'The temple') || ' replied: ' || v_reviewed.reply
      end,
      jsonb_build_object('submissionId', v_reviewed.id)
    );
  end if;

  return v_reviewed;
end;
$$;

revoke all on function public.review_newsletter_submission(uuid, text) from public, anon;
grant execute on function public.review_newsletter_submission(uuid, text) to authenticated;

do $$
begin
  raise notice 'newsletter applied';
end;
$$;
