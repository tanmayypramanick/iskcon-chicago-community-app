-- ###########################################################################
-- #                                                                         #
-- #   D E M O N S T R A T I O N   D A T A   —   N O T   R E A L   P E O P L E
-- #                                                                         #
-- #   This script invents a congregation of 42 devotees, their seva, their  #
-- #   giving and their sponsorships, so that the Sevā Mālā leaderboard,     #
-- #   Sevā Care, the donation ledger and the directory can be SEEN with     #
-- #   something in them. Every person, every hour and every dollar in here  #
-- #   is made up.                                                           #
-- #                                                                         #
-- #   TO REMOVE IT, RUN:  supabase/demo/remove_demo_congregation.sql        #
-- #   That script deletes every row this one creates and leaves the         #
-- #   temple's real data exactly as it found it.                            #
-- #                                                                         #
-- ###########################################################################
--
-- HOW DEMO DATA IS RECOGNISED
--
--   * Every demo devotee's email ends in  @demo.iskconchicago.test
--     (a reserved TLD — no such address can ever exist).
--   * Every demo devotee's id begins  decaf000-0000-4000-8000-
--   * Every demo donation's external_payment_id begins  demo-congregation-
--
--   Everything else — templates, instances, assignments, verifications,
--   sponsorship bookings, scores, awards — hangs off those three markers and
--   is reachable from them.
--
-- WHAT THIS SCRIPT PROMISES
--
--   1. It never writes to, or modifies, a real devotee. It adds no seva, no
--      donation and no role to anybody who was already here. The one place a
--      real devotee is even read is the recompute at the end, which is a
--      derived cache the temple's own nightly job rebuilds anyway. Any award
--      row the recompute would have handed a REAL devotee because of the demo
--      data is deleted again in section 11, so even that leaves no trace.
--   2. It is idempotent. Section 2 removes any previous demo congregation
--      before section 4 creates a new one, so running it twice gives you one
--      congregation, not two.
--   3. It is one transaction. A failure anywhere leaves nothing behind.
--   4. It sends nobody a notification. The `announce_new_devotee` and
--      `devotee_award_announced` triggers are switched off for the duration
--      and switched back on before commit.
--   5. It invents no phone numbers, and it places every fictional birthday at
--      least thirty days in the future, so the birthday jobs stay quiet.
--
-- WHAT IT NEEDS
--
--   All migrations up to 202608040060_leaderboard_modes.sql, and a session
--   running as `postgres` (the Supabase SQL editor does). Ownership of
--   public.users is needed for one ALTER TABLE ... DISABLE TRIGGER.
--
-- HOW LONG IT TAKES: a few seconds. It ends with a NOTICE summarising what
-- it made.
--
-- ---------------------------------------------------------------------------

begin;

-- ---------------------------------------------------------------------------
-- 1. Ground checks. Loudly wrong beats quietly wrong.
-- ---------------------------------------------------------------------------

do $$
begin
  if to_regprocedure('public.recompute_seva_mala()') is null
    or to_regprocedure('public.list_seva_concentration(integer,numeric)') is null
  then
    raise exception
      'This database is behind the migrations this demo needs. Apply supabase/migrations up to 202608040060 first.';
  end if;

  if not public.is_backend_caller() then
    raise exception
      'Run this as postgres (the Supabase SQL editor does). It has to recompute Seva Mala at the end.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 1b. Two triggers on public.devotee_awards come off for the length of this
--     transaction and go back on in section 11, before commit.
--
--       devotee_award_announced     fires a push at the devotee. The demo must
--                                   not text a real person about an award forty
--                                   invented devotees moved them into.
--       devotee_awards_append_only  is the guard that makes taking an award
--                                   back impossible — which is exactly what
--                                   clearing a previous demo run, and leaving
--                                   the real congregation untouched, require.
--
--     Both are restored below inside this same transaction, so a failure
--     anywhere rolls the disabling back with everything else.
-- ---------------------------------------------------------------------------

alter table public.devotee_awards disable trigger devotee_award_announced;
alter table public.devotee_awards disable trigger devotee_awards_append_only;

-- ---------------------------------------------------------------------------
-- 2. Remove any previous demo congregation first.
--
--    This is the same sequence, in the same order, as
--    supabase/demo/remove_demo_congregation.sql. It is repeated here rather
--    than factored into a function so that this file installs nothing
--    permanent. If you change one, change the other.
-- ---------------------------------------------------------------------------

create temp table demo_ids on commit drop as
  select auth_users.id from auth.users auth_users
  where lower(coalesce(auth_users.email, '')) like '%@demo.iskconchicago.test'
  union
  select devotees.id from public.users devotees
  where lower(coalesce(devotees.email, '')) like '%@demo.iskconchicago.test';

do $$
begin
  -- The one thing that must never happen: a real account inside the demo set.
  if exists (
    select 1 from public.users devotees
    join demo_ids on demo_ids.id = devotees.id
    where lower(coalesce(devotees.email, '')) not like '%@demo.iskconchicago.test'
  ) then
    raise exception
      'Refusing to continue: an account without the demo email marker is in the demo set.';
  end if;
end;
$$;

create temp table demo_awards_before on commit drop as
  select awards.id from public.devotee_awards awards;

create temp table demo_stale_templates on commit drop as
  select templates.id from public.service_templates templates
  where templates.created_by in (select id from demo_ids);

create temp table demo_stale_instances on commit drop as
  select instances.id from public.service_instances instances
  where instances.posted_by in (select id from demo_ids)
     or instances.template_id in (select id from demo_stale_templates);

delete from public.donations
where external_payment_id like 'demo-congregation-%'
   or donor_id in (select id from demo_ids)
   or matched_by in (select id from demo_ids);

delete from public.sponsorship_bookings
where devotee_id in (select id from demo_ids);

delete from public.service_verifications
where devotee_id in (select id from demo_ids)
   or verifier_id in (select id from demo_ids)
   or verified_by in (select id from demo_ids)
   or service_instance_id in (select id from demo_stale_instances);

delete from public.service_qr_sessions
where devotee_id in (select id from demo_ids)
   or service_instance_id in (select id from demo_stale_instances);

delete from public.service_offer_counters
where devotee_id in (select id from demo_ids)
   or responded_by in (select id from demo_ids);

delete from public.service_offers
where offered_to in (select id from demo_ids)
   or offered_by in (select id from demo_ids)
   or service_instance_id in (select id from demo_stale_instances)
   or service_template_id in (select id from demo_stale_templates);

delete from public.service_reminders_sent
where devotee_id in (select id from demo_ids)
   or service_instance_id in (select id from demo_stale_instances);

delete from public.service_assignments
where devotee_id in (select id from demo_ids)
   or assigned_by in (select id from demo_ids)
   or service_instance_id in (select id from demo_stale_instances);

delete from public.service_coverage_plans
where original_devotee_id in (select id from demo_ids)
   or substitute_devotee_id in (select id from demo_ids)
   or created_by in (select id from demo_ids)
   or service_template_id in (select id from demo_stale_templates);

delete from public.service_exceptions
where devotee_id in (select id from demo_ids)
   or resolved_by in (select id from demo_ids)
   or substitute_devotee_id in (select id from demo_ids)
   or service_instance_id in (select id from demo_stale_instances);

delete from public.service_instances
where id in (select id from demo_stale_instances);

delete from public.service_template_assignees
where devotee_id in (select id from demo_ids)
   or assigned_by in (select id from demo_ids)
   or service_template_id in (select id from demo_stale_templates);

delete from public.service_templates
where id in (select id from demo_stale_templates);

delete from public.recurring_service_interests
where devotee_id in (select id from demo_ids)
   or reviewed_by in (select id from demo_ids);

delete from public.access_requests
where requester_id in (select id from demo_ids)
   or approver_id in (select id from demo_ids)
   or reviewed_by in (select id from demo_ids);

delete from public.devotee_awards
where devotee_id in (select id from demo_ids)
   or awarded_by in (select id from demo_ids);

delete from public.app_notifications
where user_id in (select id from demo_ids)
   or data ->> 'devoteeId' in (select id::text from demo_ids);

-- The cascade from auth.users → public.users takes period_scores,
-- temple_presence, care posts, sanga rows, messages and the rest with it.
delete from auth.users where id in (select id from demo_ids);
delete from public.users where id in (select id from demo_ids);

truncate table demo_ids;
truncate table demo_stale_templates;
truncate table demo_stale_instances;

-- ---------------------------------------------------------------------------
-- 3. Helpers. Session-local, so this file leaves nothing behind.
-- ---------------------------------------------------------------------------

-- Every demo id is derived from its slug, so re-running produces the same
-- people rather than forty more of them.
create or replace function pg_temp.demo_uid(p_slug text) returns uuid
language sql immutable as $$
  select ('decaf000-0000-4000-8000-' || substr(md5('demo:' || p_slug), 1, 12))::uuid
$$;

create or replace function pg_temp.demo_email(p_slug text) returns text
language sql immutable as $$
  select p_slug || '@demo.iskconchicago.test'
$$;

-- A Chicago wall-clock moment, expressed as the instant it actually was.
create or replace function pg_temp.demo_at(p_on date, p_time time) returns timestamptz
language sql stable as $$
  select (p_on + p_time) at time zone 'America/Chicago'
$$;

-- Find a free date for a sponsorship so the demo can never collide with a
-- real booking. Scans away from the date we wanted, in the direction given.
create or replace function pg_temp.demo_free_date(
  p_type_id uuid, p_wanted date, p_step integer, p_sunday_only boolean
) returns date
language plpgsql stable as $$
declare
  v_group uuid;
  v_try date;
  v_i integer := 0;
begin
  select exclusivity_group into v_group
  from public.sponsorship_types where id = p_type_id;

  while v_i < 400 loop
    v_try := p_wanted + (p_step * v_i);
    v_i := v_i + 1;
    if p_sunday_only and extract(dow from v_try)::int <> 0 then
      continue;
    end if;
    if not exists (
      select 1 from public.sponsorship_bookings booking
      where booking.exclusivity_group = v_group
        and booking.on_date = v_try
        and booking.status in ('held', 'confirmed')
    ) then
      return v_try;
    end if;
  end loop;

  raise exception 'No free sponsorship date near % — the demo will not displace a real booking.', p_wanted;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. The congregation.
--
--    Forty-two invented devotees. The `pattern` column is the whole point of
--    the exercise: it says, in words, what this person does, so the board can
--    be read against what was intended.
-- ---------------------------------------------------------------------------

create temp table demo_devotee (
  ordinal        integer,
  slug           text primary key,
  name           text not null,
  role_name      text not null default 'devotee',
  ashram_status  text,
  gender         text,
  marital_status text,
  initiated      boolean not null default false,
  diksha_guru    text,
  rounds         integer,
  occupation     text,
  skills         text,
  visible        boolean not null default true,
  pattern        text not null
) on commit drop;

insert into demo_devotee
  (ordinal, slug, name, role_name, ashram_status, gender, marital_status,
   initiated, diksha_guru, rounds, occupation, skills, visible, pattern)
values
  -- The one demo account that runs things: posts the seva, verifies it.
  ( 1, 'gauranga-das', 'Gauranga Das', 'core', 'Brahmachari', 'male', 'single',
       true, 'HH Bhakti Chaitanya Swami', 16, 'Temple coordinator',
       'Rota planning, kirtan', true,
       'demo coordinator — posts and verifies the seva; 15 h of his own, no giving'),

  -- ---- serve only -------------------------------------------------------
  ( 2, 'ramesh-patel', 'Bhakta Ramesh Patel', 'devotee', 'Grihastha', 'male', 'married',
       false, null, 4, 'Restaurant supervisor', 'Kitchen, heavy lifting', true,
       'CONCENTRATION CASE — pot washing ~9.4 h a week for 13 weeks running (122 h), nothing else, no giving'),
  ( 3, 'gopala-krishna-das', 'Gopala Krishna Das', 'devotee', 'Grihastha', 'male', 'married',
       true, 'HH Jayapataka Swami', 16, 'Structural engineer',
       'Early mornings, deity altar, cleaning', true,
       'serve only, very heavy — 64 h across mangal arati and feast cleanup, no giving'),
  ( 4, 'madhava-priya-das', 'Madhava Priya Das', 'devotee', 'Grihastha', 'male', 'married',
       true, 'HH Radhanath Swami', 16, 'Florist',
       'Garland making, flower arrangement', true,
       'NARROWNESS CASE — 34.5 h, every hour of it deity worship, never once anything else'),
  ( 5, 'radha-vallabha-dd', 'Radha Vallabha Devi Dasi', 'devotee', 'Grihastha', 'female', 'married',
       true, 'HH Bhakti Charu Swami', 16, 'Paediatric nurse', 'Prasadam service', true,
       'serve only, moderate — 22 h, no giving'),
  ( 6, 'nitai-charan-das', 'Nitai Charan Das', 'devotee', 'Grihastha', 'male', 'married',
       false, null, 8, 'Accountant', 'Vegetable cutting', true,
       'serve only, moderate — 18 h of one-off seva, no giving'),
  ( 7, 'sundari-gopi-dd', 'Sundari Gopi Devi Dasi', 'devotee', 'Grihastha', 'female', 'married',
       false, null, 4, 'Schoolteacher', 'Guest welcome, childrens programme', true,
       'serve only, light — 6 h, no giving'),
  ( 8, 'hari-bhakta-das', 'Hari Bhakta Das', 'devotee', 'Grihastha', 'male', 'single',
       false, null, 4, 'Graduate student', 'Book distribution', true,
       'serve only, light — 4 h, no giving'),
  ( 9, 'tulasi-priya-dd', 'Tulasi Priya Devi Dasi', 'devotee', 'Grihastha', 'female', 'married',
       false, null, 2, 'Pharmacist', 'Shoe room, reception', true,
       'serve only, light — 3 h, no giving'),

  -- ---- give only --------------------------------------------------------
  (10, 'vrindavan-chandra-das', 'Vrindavan Chandra Das', 'devotee', 'Grihastha', 'male', 'married',
       true, 'HH Gopal Krishna Goswami', 16, 'Cardiologist', null, true,
       'give only, LARGE — the $2,500 deity dress sponsor, no seva at all'),
  (11, 'sita-thakurani-dd', 'Sita Thakurani Devi Dasi', 'devotee', 'Grihastha', 'female', 'married',
       true, 'HH Radhanath Swami', 16, 'Software director', null, true,
       'give only — $551 Sunday Feast plus a $49 general gift, no seva'),
  (12, 'govinda-das', 'Govinda Das', 'devotee', 'Grihastha', 'male', 'married',
       false, null, 4, 'Logistics manager', null, true,
       'give only, small and regular — $51 a month, three months, no seva'),
  (13, 'yamuna-dd', 'Yamuna Devi Dasi', 'devotee', 'Grihastha', 'female', 'widowed',
       true, 'HH Bhakti Charu Swami', 16, 'Retired', null, true,
       'give only, small and regular — $21 a month, three months, no seva'),
  (14, 'damodara-das', 'Damodara Das', 'devotee', 'Grihastha', 'male', 'married',
       false, null, 4, 'Dentist', null, false,
       'give only — $108 Mangal Aarti sponsor. OPTED OUT of the board'),
  (15, 'arjuna-das', 'Arjuna Das', 'devotee', 'Grihastha', 'male', 'single',
       false, null, 2, 'Delivery driver', null, true,
       'give only, small — two $25 gifts, no seva'),
  (16, 'lalita-sakhi-dd', 'Lalita Sakhi Devi Dasi', 'devotee', 'Grihastha', 'female', 'married',
       false, null, 4, 'Home maker', null, true,
       'give only, very small and regular — three $11 gifts ($33), no seva'),
  (17, 'bhakta-suresh', 'Bhakta Suresh Kumar', 'devotee', 'Grihastha', 'male', 'married',
       false, null, 2, 'Civil engineer', null, true,
       'give only — $201 Rajbhog sponsor, no seva'),

  -- ---- both, in different ratios ---------------------------------------
  (18, 'syamasundara-das', 'Syamasundara Das', 'devotee', 'Grihastha', 'male', 'married',
       true, 'HH Jayapataka Swami', 16, 'Chef', 'Sunday feast cooking', true,
       'BOTH — heavy seva (34 h) and a small gift ($25)'),
  (19, 'padmavati-dd', 'Padmavati Devi Dasi', 'devotee', 'Grihastha', 'female', 'married',
       true, 'HH Radhanath Swami', 16, 'Property developer', null, true,
       'BOTH — small seva (3 h) and a large gift ($1,000)'),
  (20, 'jahnava-dd', 'Jahnava Devi Dasi', 'devotee', 'Grihastha', 'female', 'married',
       true, 'HH Bhakti Charu Swami', 16, 'Anaesthetist', 'Cleaning, prasadam', true,
       'BOTH, balanced and heavy — 32 h and $751'),
  (21, 'krsna-kirtan-das', 'Krsna Kirtan Das', 'devotee', 'Grihastha', 'male', 'married',
       false, null, 8, 'Music teacher', 'Kirtan, vegetable cutting', true,
       'BOTH, balanced and moderate — 14 h and $151'),
  (22, 'bhakti-lata-dd', 'Bhakti Lata Devi Dasi', 'devotee', 'Grihastha', 'female', 'married',
       true, 'HH Bhakti Vinoda Swami', 16, 'Lawyer', 'Temple cleaning', true,
       'BOTH — 20 h and $351 (Garland sponsor)'),
  (23, 'acyuta-gopal-das', 'Acyuta Gopal Das', 'devotee', 'Grihastha', 'male', 'married',
       false, null, 4, 'Architect', 'Festival decoration', true,
       'BOTH — 10 h and $101; also has a RELEASED breakfast booking'),
  (24, 'rukmini-dd', 'Rukmini Devi Dasi', 'devotee', 'Grihastha', 'female', 'single',
       false, null, 4, 'Data analyst', 'Cleaning', true,
       'BOTH — 8 h and $75; also has a HELD Sandhya Bhog booking'),
  (25, 'narottama-das', 'Narottama Das', 'devotee', 'Grihastha', 'male', 'married',
       false, null, 4, 'Insurance broker', 'Kitchen preparation', true,
       'BOTH — 6 h and $251'),
  (26, 'bhaktin-anjali', 'Bhaktin Anjali Sharma', 'devotee', 'Grihastha', 'female', 'single',
       false, null, 2, 'Physiotherapist', 'Cleaning, guest welcome', true,
       'BOTH — 12 h and $51'),
  (27, 'sanatana-das', 'Sanatana Das', 'devotee', 'Grihastha', 'male', 'married',
       true, 'HH Gopal Krishna Goswami', 16, 'Business owner', 'Prasadam, festivals', false,
       'BOTH and high — 22 h and $501 — but OPTED OUT, so he must not appear on the board'),
  (28, 'gopinatha-das', 'Gopinatha Das', 'devotee', 'Grihastha', 'male', 'married',
       false, null, 4, 'Electrician', 'Feast cleanup', false,
       'serves 14 h, OPTED OUT of the board'),

  -- ---- very little ------------------------------------------------------
  (29, 'bhakta-vinay', 'Bhakta Vinay Shah', 'devotee', 'Grihastha', 'male', 'single',
       false, null, 0, 'Student', null, true,
       'barely anything — a single 1.5 h seva'),
  (30, 'subhadra-dd', 'Subhadra Devi Dasi', 'devotee', 'Grihastha', 'female', 'married',
       false, null, 0, 'Retail assistant', null, true,
       'barely anything — one $11 gift'),
  (31, 'mukunda-das', 'Mukunda Das', 'devotee', 'Grihastha', 'male', 'single',
       false, null, 0, 'Warehouse operative', null, true,
       'barely anything — a single 2 h seva'),
  (32, 'kaustubha-das', 'Kaustubha Das', 'devotee', 'Grihastha', 'male', 'married',
       false, null, 2, 'Taxi driver', null, true,
       'barely anything — 1 h of seva and a $10 gift'),
  (33, 'ananta-sesa-das', 'Ananta Sesa Das', 'devotee', 'Grihastha', 'male', 'married',
       false, null, 0, 'Chef de partie', null, true,
       'barely anything — a single 1 h seva two months ago'),

  -- ---- the pending states ----------------------------------------------
  (34, 'haridasa-das', 'Haridasa Das', 'devotee', 'Grihastha', 'male', 'married',
       false, null, 4, 'IT support', 'Kirtan, pot washing', true,
       'PENDING — 2 h counted, plus three acts sitting at awaiting_confirmation'),
  (35, 'campakalata-dd', 'Campakalata Devi Dasi', 'devotee', 'Grihastha', 'female', 'married',
       false, null, 2, 'Bookkeeper', 'Vegetable cutting', true,
       'PENDING — two acts at awaiting_verification, so nothing counts yet'),
  (36, 'vasudeva-das', 'Vasudeva Das', 'devotee', 'Grihastha', 'male', 'single',
       false, null, 2, 'Mechanic', 'Cleaning', true,
       'PENDING — two acts at awaiting_completion, so nothing counts yet'),

  -- ---- nothing at all, and they must still be in the directory ----------
  (37, 'gaura-nitai-das', 'Gaura Nitai Das', 'devotee', 'Grihastha', 'male', 'married',
       false, null, 0, 'Bus driver', null, true,
       'nothing — directory only, must not appear on the board'),
  (38, 'vaishnavi-dd', 'Vaishnavi Devi Dasi', 'devotee', 'Grihastha', 'female', 'married',
       false, null, 0, 'Care assistant', null, false,
       'nothing, and opted out — directory only'),
  (39, 'bhakta-dinesh', 'Bhakta Dinesh Reddy', 'devotee', 'Grihastha', 'male', 'married',
       false, null, 0, 'Pharmacy technician', null, true,
       'nothing — directory only'),
  (40, 'parvati-dd', 'Parvati Devi Dasi', 'devotee', 'Grihastha', 'female', 'single',
       false, null, 0, 'Optician', null, true,
       'nothing — directory only'),
  (41, 'nimai-das', 'Nimai Das', 'devotee', 'Grihastha', 'male', 'married',
       false, null, 0, 'Plumber', null, true,
       'nothing — directory only'),
  (42, 'saci-mata-dd', 'Saci Mata Devi Dasi', 'devotee', 'Grihastha', 'female', 'widowed',
       true, 'HH Bhakti Charu Swami', 16, 'Retired teacher', null, true,
       'nothing — directory only');

-- Nobody hears about a devotee who does not exist.
alter table public.users disable trigger announce_new_devotee;

insert into auth.users (id, email, raw_user_meta_data)
select
  pg_temp.demo_uid(person.slug),
  pg_temp.demo_email(person.slug),
  jsonb_build_object('name', person.name, 'demo_congregation', true)
from demo_devotee person
order by person.ordinal;

-- The signup trigger has now created the public.users rows at role 'devotee'.
-- Everything below is the profile detail the directory shows.
update public.users devotees
set
  role_id = (select roles.id from public.roles where roles.name = person.role_name),
  ashram_status = person.ashram_status,
  gender = person.gender,
  marital_status = person.marital_status,
  is_initiated = person.initiated,
  has_first_initiation = person.initiated,
  diksha_guru = person.diksha_guru,
  first_diksha_guru = person.diksha_guru,
  first_initiation_date = case when person.initiated
    then (public.seva_mala_today() - (900 + person.ordinal * 37)) end,
  initiation_date = case when person.initiated
    then (public.seva_mala_today() - (900 + person.ordinal * 37)) end,
  spiritual_mentor = person.diksha_guru,
  chanting_rounds = person.rounds,
  occupation = person.occupation,
  skills = person.skills,
  leaderboard_visible = person.visible,
  address = 'Chicago, IL',
  preferred_language = case when person.ordinal % 5 = 0 then 'Hindi'
                            when person.ordinal % 7 = 0 then 'Gujarati'
                            else 'English' end,
  languages_spoken = case when person.ordinal % 5 = 0 then 'English, Hindi'
                          when person.ordinal % 7 = 0 then 'English, Gujarati'
                          else 'English' end,
  how_they_found_us = case person.ordinal % 4
                        when 0 then 'A friend brought me to the Sunday feast'
                        when 1 then 'Harinam sankirtan downtown'
                        when 2 then 'Found the temple online'
                        else 'Family has come here for years' end,
  can_offer_lift = (person.ordinal % 6 = 0),
  can_host_programs = (person.ordinal % 9 = 0),
  joined_temple_on = public.seva_mala_today() - (120 + person.ordinal * 53),
  -- Birthdays are placed at least thirty days out on purpose, so seeding a
  -- demo congregation never fires the temple's birthday notifications.
  date_of_birth = (
    public.seva_mala_today() + 30 + (person.ordinal * 7)
  ) - ((22 + (person.ordinal % 40)) * interval '1 year'),
  joined_at = pg_temp.demo_at(
    public.seva_mala_today() - (120 + person.ordinal * 53), time '11:00'),
  profile_updated_at = now(),
  photo_url = null
from demo_devotee person
where devotees.id = pg_temp.demo_uid(person.slug);

alter table public.users enable trigger announce_new_devotee;

-- Everything from here on refers to the coordinator by this id.
create temp table demo_meta on commit drop as
  select pg_temp.demo_uid('gauranga-das') as coordinator_id,
         public.seva_mala_today() as today;

-- ---------------------------------------------------------------------------
-- 5. The weekly rota.
--
--    Recurring seva scores differently from one-off seva: 202608040059 says a
--    weekly act that is marked completed counts, with no verification and no
--    attendance mark. So the rota below is what the counted-by-default half of
--    the board is made of.
-- ---------------------------------------------------------------------------

create temp table demo_template (
  key       text primary key,
  type_name text not null,
  dows      integer[] not null,   -- 0 = Sunday
  at        time not null,
  minutes   integer not null,
  slots     integer not null,
  id        uuid
) on commit drop;

insert into demo_template (key, type_name, dows, at, minutes, slots) values
  ('pot-washing',     'Pot Washing',          array[1,3,5,6], time '19:00', 150,  6),
  ('temple-cleaning', 'Temple Room Cleaning', array[6],       time '10:00', 120,  8),
  ('mangal-arati',    'Mangal Arati Setup',   array[0,3],     time '04:15',  90,  4),
  ('prasadam',        'Prasadam Serving',     array[0],       time '13:00', 120, 10),
  ('kitchen-prep',    'Kitchen Preparation',  array[0],       time '09:00', 180,  8),
  ('garlands',        'Flower Garlands',      array[2,5],     time '08:00',  90,  4),
  ('feast-cleanup',   'Sunday Feast Cleanup', array[0],       time '16:00', 120, 10);

insert into public.service_templates (
  service_type_id, day_of_week, days_of_week, start_time, duration_minutes,
  slots_needed, participation_mode, start_date, created_by, active
)
select
  types.id, template.dows[1], template.dows, template.at, template.minutes,
  template.slots, 'invite_only',
  meta.today - 400, meta.coordinator_id, true
from demo_template template
join public.service_types types on types.name = template.type_name
cross join demo_meta meta;

update demo_template template
set id = templates.id
from public.service_templates templates
join public.service_types types on types.id = templates.service_type_id
cross join demo_meta meta
where templates.created_by = meta.coordinator_id
  and types.name = template.type_name;

-- Who is on which rota, and for how many weeks back. `weeks_back` is counted
-- in whole weeks from the Monday of the current week, so 12 means "the last
-- twelve full weeks and whatever has happened of this one".
create temp table demo_rota (
  slug         text not null,
  template_key text not null,
  weeks_back   integer not null
) on commit drop;

insert into demo_rota (slug, template_key, weeks_back) values
  -- The care case: four evenings a week, ten hours, every week for a quarter.
  ('ramesh-patel',       'pot-washing',     12),
  ('gopala-krishna-das', 'mangal-arati',    12),
  ('gopala-krishna-das', 'feast-cleanup',   12),
  ('madhava-priya-das',  'garlands',        11),
  ('syamasundara-das',   'kitchen-prep',    10),
  ('jahnava-dd',         'temple-cleaning', 10),
  ('radha-vallabha-dd',  'prasadam',         9),
  ('bhakti-lata-dd',     'temple-cleaning',  9),
  ('sanatana-das',       'prasadam',         8),
  ('gopinatha-das',      'feast-cleanup',    7),
  ('bhaktin-anjali',     'temple-cleaning',  5),
  ('gauranga-das',       'mangal-arati',     3);

-- ---------------------------------------------------------------------------
-- 6. One-off seva.
--
--    Scored only when completed AND verified AND marked served
--    (202608040057). The `state` column is which of those three is missing,
--    so the pending queue has something in it.
-- ---------------------------------------------------------------------------

create temp table demo_oneoff (
  slug           text not null,
  type_name      text not null,
  acts           integer not null,
  minutes        integer not null,
  first_days_ago integer not null,
  step_days      integer not null,
  at             time not null,
  state          text not null
) on commit drop;

insert into demo_oneoff
  (slug, type_name, acts, minutes, first_days_ago, step_days, at, state) values
  ('gauranga-das',       'Guest Welcome',          4,  90,  3, 18, time '10:00', 'counted'),
  ('gopala-krishna-das', 'General Temple Service', 2, 120,  3, 30, time '14:00', 'counted'),
  ('radha-vallabha-dd',  'Temple Room Cleaning',   2, 120,  2, 24, time '11:00', 'counted'),
  ('nitai-charan-das',   'Vegetable Cutting',      9, 120,  0,  9, time '09:30', 'counted'),
  ('sundari-gopi-dd',    'Guest Welcome',          4,  90,  1, 20, time '10:30', 'counted'),
  ('hari-bhakta-das',    'Book Table',             4,  60,  5, 21, time '15:00', 'counted'),
  ('tulasi-priya-dd',    'Shoe Room',              3,  60,  2, 25, time '17:00', 'counted'),
  ('syamasundara-das',   'Kirtana Support',        2, 120,  0, 14, time '18:00', 'counted'),
  ('padmavati-dd',       'Guest Welcome',          2,  90,  6, 30, time '10:30', 'counted'),
  ('krsna-kirtan-das',   'Vegetable Cutting',      7, 120,  0, 12, time '09:30', 'counted'),
  ('jahnava-dd',         'Prasadam Serving',       6, 120,  1, 13, time '13:00', 'counted'),
  ('acyuta-gopal-das',   'Festival Decoration',    5, 120,  2, 16, time '16:00', 'counted'),
  ('rukmini-dd',         'Temple Room Cleaning',   4, 120,  0, 18, time '11:00', 'counted'),
  ('narottama-das',      'Kitchen Preparation',    3, 120,  4, 22, time '09:00', 'counted'),
  ('sanatana-das',       'Festival Decoration',    3, 120,  1, 25, time '16:00', 'counted'),
  ('bhakti-lata-dd',     'Kitchen Preparation',    1, 120, 10,  1, time '09:00', 'counted'),
  ('bhaktin-anjali',     'Guest Welcome',          2,  60,  1, 26, time '10:30', 'counted'),
  ('bhakta-vinay',       'Guest Welcome',          1,  90, 40,  1, time '10:30', 'counted'),
  ('mukunda-das',        'Book Table',             1, 120, 55,  1, time '15:00', 'counted'),
  ('kaustubha-das',      'Shoe Room',              1,  60, 20,  1, time '17:00', 'counted'),
  ('ananta-sesa-das',    'General Temple Service', 1,  60, 70,  1, time '14:00', 'counted'),
  ('haridasa-das',       'Kirtana Support',        1, 120,  8,  1, time '18:00', 'counted'),
  -- Everything is in place and nobody has said "served".
  ('haridasa-das',       'Pot Washing',            3, 120,  0,  7, time '19:00', 'awaiting_confirmation'),
  -- Only the devotee says it happened.
  ('campakalata-dd',     'Vegetable Cutting',      2, 120,  1,  7, time '09:30', 'awaiting_verification'),
  -- Nobody has closed the seva out.
  ('vasudeva-das',       'Temple Room Cleaning',   2, 120,  0,  6, time '11:00', 'awaiting_completion');

-- Every act of seva, weekly and one-off, in one place.
create temp table demo_act (
  act_id         uuid not null default gen_random_uuid(),
  devotee_id     uuid not null,
  template_id    uuid,
  service_type_id uuid not null,
  occurred_on    date not null,
  at             time not null,
  minutes        integer not null,
  slots          integer not null,
  state          text not null,
  instance_key   text not null
) on commit drop;

insert into demo_act (
  devotee_id, template_id, service_type_id, occurred_on, at, minutes, slots,
  state, instance_key
)
select
  pg_temp.demo_uid(rota.slug),
  template.id,
  types.id,
  day::date,
  template.at,
  template.minutes,
  template.slots,
  'weekly',
  template.key || '|' || day::date
from demo_rota rota
join demo_template template on template.key = rota.template_key
join public.service_types types on types.name = template.type_name
cross join demo_meta meta
cross join lateral generate_series(
  (public.seva_mala_week_start(meta.today) - (7 * rota.weeks_back))::timestamp,
  meta.today::timestamp,
  interval '1 day'
) as day
where extract(dow from day)::int = any (template.dows);

insert into demo_act (
  devotee_id, template_id, service_type_id, occurred_on, at, minutes, slots,
  state, instance_key
)
select
  pg_temp.demo_uid(plan.slug),
  null,
  types.id,
  meta.today - (plan.first_days_ago + step * plan.step_days),
  plan.at,
  plan.minutes,
  1,
  plan.state,
  'oneoff|' || plan.slug || '|' || plan.type_name || '|' || step::text
from demo_oneoff plan
join public.service_types types on types.name = plan.type_name
cross join demo_meta meta
cross join generate_series(0, plan.acts - 1) as step;

-- One service_instance per (rota, date) and per one-off act.
create temp table demo_instance (
  instance_key text primary key,
  id uuid not null default gen_random_uuid()
) on commit drop;

insert into demo_instance (instance_key)
select distinct act.instance_key from demo_act act;

insert into public.service_instances (
  id, template_id, service_type_id, date, start_time, duration_minutes,
  slots_needed, participation_mode, posted_by, status, created_at
)
select
  instance.id,
  shape.template_id,
  shape.service_type_id,
  shape.occurred_on,
  shape.at,
  shape.minutes,
  shape.slots,
  case when shape.template_id is null then 'open' else 'invite_only' end,
  meta.coordinator_id,
  -- An act nobody has closed out leaves its occurrence open, which is exactly
  -- what "awaiting completion" means on the temple's screens.
  case when shape.state = 'awaiting_completion' then 'open' else 'completed' end,
  pg_temp.demo_at(shape.occurred_on, shape.at)
from demo_instance instance
join lateral (
  select distinct on (act.instance_key)
    act.instance_key, act.template_id, act.service_type_id, act.occurred_on,
    act.at, act.minutes, act.slots, act.state
  from demo_act act
  where act.instance_key = instance.instance_key
) shape on true
cross join demo_meta meta;

insert into public.service_assignments (
  service_instance_id, devotee_id, assignment_method, assigned_by, status,
  verification, attendance, created_at, completed_at
)
select
  instance.id,
  act.devotee_id,
  case when act.template_id is not null then 'recurring_assignment' else 'self_joined' end,
  meta.coordinator_id,
  case when act.state = 'awaiting_completion' then 'assigned' else 'completed' end,
  case
    when act.state = 'weekly' then 'self_report'
    when act.state in ('counted', 'awaiting_confirmation') then 'member_verified'
    else 'self_report'
  end,
  case when act.state = 'counted' then 'served' end,
  pg_temp.demo_at(act.occurred_on - 3, time '20:00'),
  case when act.state = 'awaiting_completion' then null
       else pg_temp.demo_at(act.occurred_on, act.at + (act.minutes * interval '1 minute')) end
from demo_act act
join demo_instance instance on instance.instance_key = act.instance_key
cross join demo_meta meta;

-- ---------------------------------------------------------------------------
-- 7. A few self-logged sevas still sitting in the verifier's inbox, so the
--    "someone verified it" half of the workflow has something to show. These
--    are not attached to an occurrence, so they score nothing either way.
-- ---------------------------------------------------------------------------

insert into public.service_verifications (
  devotee_id, service_type_id, start_at, end_at, verifier_id, status, created_at
)
select
  pg_temp.demo_uid(request.slug),
  types.id,
  pg_temp.demo_at(meta.today - request.days_ago, request.at),
  pg_temp.demo_at(meta.today - request.days_ago, request.at) + (request.minutes * interval '1 minute'),
  meta.coordinator_id,
  'pending',
  pg_temp.demo_at(meta.today - request.days_ago, request.at) + interval '3 hours'
from (values
  ('campakalata-dd', 'Vegetable Cutting',      2, time '09:30', 120),
  ('mukunda-das',    'General Temple Service', 4, time '13:00',  90),
  ('bhakta-vinay',   'Guest Welcome',          1, time '10:30',  60)
) as request(slug, type_name, days_ago, at, minutes)
join public.service_types types on types.name = request.type_name
cross join demo_meta meta;

-- ---------------------------------------------------------------------------
-- 8. Sponsorships — confirmed, released and held, so My Donations and the
--    admin ledger show the difference between them.
--
--    Dates are chosen by pg_temp.demo_free_date, which walks away from the
--    date we wanted until it finds one no real booking is sitting on. The
--    demo will never displace a temple booking.
-- ---------------------------------------------------------------------------

create temp table demo_booking (
  slug        text not null,
  type_name   text not null,
  status      text not null,
  booked_on   date,
  amount_cents integer not null,
  id          uuid not null default gen_random_uuid(),
  primary key (slug, type_name)
) on commit drop;

do $$
declare
  v_today date := public.seva_mala_today();
  v_row record;
  v_type public.sponsorship_types;
  v_date date;
begin
  for v_row in
    select * from (values
      ('vrindavan-chandra-das', 'Deity Dress',  'confirmed', -14, -1),
      ('sita-thakurani-dd',     'Sunday Feast', 'confirmed', -21, -1),
      ('bhakti-lata-dd',        'Garland',      'confirmed', -27, -1),
      ('damodara-das',          'Mangal Aarti', 'confirmed', -33, -1),
      ('bhakta-suresh',         'Rajbhog',      'confirmed', -45, -1),
      ('acyuta-gopal-das',      'Breakfast',    'released',   -5, -1),
      ('rukmini-dd',            'Sandhya Bhog', 'held',       21,  1)
    ) as t(slug, type_name, status, offset_days, direction)
  loop
    select * into v_type from public.sponsorship_types
    where sponsorship_types.name = v_row.type_name;

    if v_type.requires_date then
      v_date := pg_temp.demo_free_date(
        v_type.id, v_today + v_row.offset_days, v_row.direction, v_type.sunday_only);
    else
      v_date := null;
    end if;

    insert into demo_booking (slug, type_name, status, booked_on, amount_cents)
    values (v_row.slug, v_row.type_name, v_row.status, v_date, v_type.amount_cents);
  end loop;
end;
$$;

insert into public.sponsorship_bookings (
  id, sponsorship_type_id, devotee_id, on_date, status, held_until,
  amount_cents, created_at, updated_at, fulfilled_on, fulfilment_note
)
select
  booking.id,
  types.id,
  pg_temp.demo_uid(booking.slug),
  booking.booked_on,
  booking.status,
  case when booking.status = 'held' then now() + interval '30 minutes' end,
  booking.amount_cents,
  pg_temp.demo_at(coalesce(booking.booked_on, meta.today) - 6, time '20:15'),
  now(),
  case when booking.status = 'confirmed'
       then coalesce(booking.booked_on, meta.today - 10) end,
  case when booking.status = 'confirmed'
       then 'Offered on the altar. (Demonstration data.)' end
from demo_booking booking
join public.sponsorship_types types on types.name = booking.type_name
cross join demo_meta meta;

-- ---------------------------------------------------------------------------
-- 9. Giving. Integer cents throughout; every received_at is a Chicago wall
--    clock moment inside the last three months.
-- ---------------------------------------------------------------------------

-- 9a. The gifts that paid for a sponsorship, matched to their booking.
insert into public.donations (
  donor_id, donor_name, donor_email, amount_cents, currency, kind,
  external_payment_id, payload, sponsorship_booking_id, received_at,
  match_status, matched_at, matched_by
)
select
  pg_temp.demo_uid(booking.slug),
  devotees.name,
  devotees.email,
  booking.amount_cents,
  'USD',
  'one_time',
  'demo-congregation-sponsorship-' || booking.slug || '-' || lower(replace(booking.type_name, ' ', '-')),
  jsonb_build_object('demo', true, 'source', 'demo congregation', 'campaign', booking.type_name),
  booking.id,
  pg_temp.demo_at(coalesce(booking.booked_on, meta.today - 14) - 6, time '20:15'),
  'matched',
  pg_temp.demo_at(coalesce(booking.booked_on, meta.today - 14) - 6, time '20:16'),
  meta.coordinator_id
from demo_booking booking
join public.users devotees on devotees.id = pg_temp.demo_uid(booking.slug)
cross join demo_meta meta
where booking.status = 'confirmed';

-- 9b. General giving, including the small regular donors.
insert into public.donations (
  donor_id, donor_name, donor_email, amount_cents, currency, kind, recurrence,
  external_payment_id, payload, received_at, match_status
)
select
  pg_temp.demo_uid(gift.slug),
  devotees.name,
  devotees.email,
  gift.amount_cents,
  'USD',
  gift.kind,
  gift.recurrence,
  'demo-congregation-gift-' || gift.slug || '-' || step::text,
  jsonb_build_object('demo', true, 'source', 'demo congregation'),
  pg_temp.demo_at(meta.today - (gift.first_days_ago + step * gift.step_days), time '19:40'),
  'general'
from (values
  ('sita-thakurani-dd', 4900,   'one_time',  null,      1, 60, 1),
  ('govinda-das',       5100,   'recurring', 'monthly', 3,  5, 30),
  ('yamuna-dd',         2100,   'recurring', 'monthly', 3,  8, 30),
  ('arjuna-das',        2500,   'one_time',  null,      2, 12, 40),
  ('lalita-sakhi-dd',   1100,   'one_time',  null,      3,  0, 28),
  ('syamasundara-das',  2500,   'one_time',  null,      1, 25, 1),
  ('padmavati-dd',      100000, 'one_time',  null,      1,  8, 1),
  ('krsna-kirtan-das',  15100,  'one_time',  null,      1,  0, 1),
  ('jahnava-dd',        75100,  'one_time',  null,      1,  4, 1),
  ('acyuta-gopal-das',  10100,  'one_time',  null,      1, 30, 1),
  ('rukmini-dd',        7500,   'one_time',  null,      1, 16, 1),
  ('narottama-das',     25100,  'one_time',  null,      1,  0, 1),
  ('bhaktin-anjali',    5100,   'one_time',  null,      1, 22, 1),
  ('sanatana-das',      50100,  'one_time',  null,      1, 19, 1),
  ('subhadra-dd',       1100,   'one_time',  null,      1, 50, 1),
  ('kaustubha-das',     1000,   'one_time',  null,      1, 38, 1)
) as gift(slug, amount_cents, kind, recurrence, gifts, first_days_ago, step_days)
join public.users devotees on devotees.id = pg_temp.demo_uid(gift.slug)
cross join demo_meta meta
cross join lateral generate_series(0, gift.gifts - 1) as step;

-- ---------------------------------------------------------------------------
-- 10. Build the boards now, rather than waiting for the nightly job.
--
-- ---------------------------------------------------------------------------

select public.recompute_seva_mala();

-- ---------------------------------------------------------------------------
-- 11. Give the real congregation its awards back.
--
--     The recompute above ranks and thresholds the WHOLE congregation, so it
--     can hand a real devotee an award they only reached because forty
--     invented people moved the median. Any award row that did not exist
--     before this script ran and does not belong to a demo devotee is undone
--     here. The temple's own nightly recompute will grant it again if it was
--     genuinely earned.
-- ---------------------------------------------------------------------------

delete from public.devotee_awards awards
where awards.id not in (select id from demo_awards_before)
  and awards.devotee_id not in (
    select id from public.users
    where lower(coalesce(email, '')) like '%@demo.iskconchicago.test'
  );

alter table public.devotee_awards enable trigger devotee_awards_append_only;
alter table public.devotee_awards enable trigger devotee_award_announced;

-- ---------------------------------------------------------------------------
-- 12. Say what happened.
-- ---------------------------------------------------------------------------

do $$
declare
  v_devotees integer;
  v_acts integer;
  v_hours numeric;
  v_gifts integer;
  v_cents bigint;
  v_bookings integer;
  v_scored integer;
begin
  select count(*) into v_devotees from public.users
  where lower(coalesce(email, '')) like '%@demo.iskconchicago.test';

  select count(*), round(sum(assignments_minutes) / 60.0, 1)
  into v_acts, v_hours
  from (
    select instances.duration_minutes as assignments_minutes
    from public.service_assignments assignments
    join public.service_instances instances on instances.id = assignments.service_instance_id
    join public.users devotees on devotees.id = assignments.devotee_id
    where lower(coalesce(devotees.email, '')) like '%@demo.iskconchicago.test'
  ) rows;

  select count(*), coalesce(sum(amount_cents), 0) into v_gifts, v_cents
  from public.donations where external_payment_id like 'demo-congregation-%';

  select count(*) into v_bookings
  from public.sponsorship_bookings bookings
  join public.users devotees on devotees.id = bookings.devotee_id
  where lower(coalesce(devotees.email, '')) like '%@demo.iskconchicago.test';

  select count(*) into v_scored
  from public.period_scores scores
  join public.seva_mala_periods periods on periods.id = scores.period_id
  join public.users devotees on devotees.id = scores.devotee_id
  where periods.period_kind = 'lifetime'
    and lower(coalesce(devotees.email, '')) like '%@demo.iskconchicago.test';

  raise notice '';
  raise notice '=== DEMO CONGREGATION SEEDED ===============================';
  raise notice '  devotees            %', v_devotees;
  raise notice '  seva acts           %  (% hours rostered)', v_acts, v_hours;
  raise notice '  donations           %  ($%)', v_gifts, round(v_cents / 100.0, 2);
  raise notice '  sponsorships        %', v_bookings;
  raise notice '  on the board        %  (lifetime period)', v_scored;
  raise notice '';
  raise notice '  ALL OF IT IS FICTIONAL. To remove every trace, run';
  raise notice '  supabase/demo/remove_demo_congregation.sql';
  raise notice '===========================================================';
end;
$$;

commit;
