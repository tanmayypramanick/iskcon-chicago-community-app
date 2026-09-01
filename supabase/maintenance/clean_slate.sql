-- ###########################################################################
-- #   C L E A N   S L A T E                                                 #
-- #                                                                         #
-- #   Leaves the live project with two accounts and the temple's reference  #
-- #   data, and nothing else. One transaction: it all happens or none of it #
-- #   does.                                                                 #
-- #                                                                         #
-- #   KEPT   tanmayp0612@gmail.com, arpitajadhav24k@gmail.com and their     #
-- #          profiles; roles and permissions; the 14 service types; award   #
-- #          definitions; the Vaisnava calendar and its publications; the   #
-- #          temple programme, deities and sponsorship types; app settings. #
-- #                                                                         #
-- #   GONE   every other account, all seva of every kind, Seva Mala         #
-- #          periods scores and awards, announcements, sangas, chats,       #
-- #          giving, sponsorship bookings, care posts, feedback, access     #
-- #          requests, presence, notifications, push tokens, and the demo   #
-- #          ledger itself.                                                 #
-- #                                                                         #
-- #   NOT HERE  Uploaded files. Storage refuses SQL deletion by design;     #
-- #          see supabase/maintenance/README.md for the one command.        #
-- ###########################################################################

begin;

-- Awards refuse to be deleted, by design. The guard comes off for this
-- transaction and goes back on before it commits.
alter table public.devotee_awards disable trigger devotee_awards_append_only;
alter table public.devotee_awards disable trigger devotee_award_announced;

-- ---------------------------------------------------------------------------
-- 1. Seva, all of it, for everybody.
-- ---------------------------------------------------------------------------
delete from public.devotee_awards;
delete from public.period_scores;
delete from public.seva_mala_periods;
delete from public.seva_type_weights;
delete from public.seva_care_dismissals;
delete from public.service_verifications;
delete from public.service_qr_sessions;
delete from public.service_reminders_sent;
delete from public.service_instances_unserved;
delete from public.service_offer_counters;
delete from public.service_offers;
delete from public.service_coverage_plans;
delete from public.service_exceptions;
delete from public.service_assignments;
delete from public.service_instances;
delete from public.service_template_assignees;
delete from public.service_templates;
delete from public.recurring_service_interests;

-- ---------------------------------------------------------------------------
-- 2. Everything else anybody wrote.
-- ---------------------------------------------------------------------------
delete from public.announcement_likes;
delete from public.announcement_comments;
delete from public.announcements;

delete from public.sanga_reads;
delete from public.sanga_join_requests;
delete from public.sanga_messages;
delete from public.sanga_members;
delete from public.sangas;

delete from public.message_hidden_for;
delete from public.conversation_cleared_for;
delete from public.messages;
delete from public.conversations;

delete from public.donations;
delete from public.sponsorship_bookings;
delete from public.care_replies;
delete from public.care_posts;
delete from public.feedback;
delete from public.access_appointments;
delete from public.access_requests;
delete from public.temple_presence;

delete from public.newsletter_submissions;
delete from public.newsletters;
delete from public.newsletter_editors;

delete from public.daily_darshan_images;
delete from public.daily_darshan;
delete from public.daily_darshan_reaped_images;

delete from public.vaisnava_calendar_reminders_sent;

delete from public.app_notifications;
delete from public.device_push_tokens;

-- Uploaded files are NOT deleted here, and cannot be: storage.objects and
-- storage.buckets both carry a protect_delete trigger that refuses SQL
-- outright, because a row deleted here would leave the file itself behind in
-- the bucket forever. They go through the Storage API instead, and
-- supabase/maintenance/README.md has the one command for it.
--
-- Nothing below cascades into them either — no storage table has a foreign key
-- to auth.users — so removing the accounts leaves their files untouched rather
-- than half-deleted.

-- ---------------------------------------------------------------------------
-- 3. Every account but the two live ones.
-- ---------------------------------------------------------------------------
delete from auth.users
where email is distinct from 'tanmayp0612@gmail.com'
  and email is distinct from 'arpitajadhav24k@gmail.com';

-- ---------------------------------------------------------------------------
-- 4. The demo's own bookkeeping, which only existed to undo the demo.
-- ---------------------------------------------------------------------------
drop table if exists public.demo_seva_yatra_ledger;

alter table public.devotee_awards enable trigger devotee_award_announced;
alter table public.devotee_awards enable trigger devotee_awards_append_only;

commit;
