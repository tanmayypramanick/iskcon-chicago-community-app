-- ###########################################################################
-- #                                                                         #
-- #   R E M O V E   T H E   D E M O   C O N G R E G A T I O N               #
-- #                                                                         #
-- #   Deletes every row created by supabase/demo/seed_demo_congregation.sql #
-- #   and leaves the temple's real devotees, seva, giving and sponsorships  #
-- #   exactly as they were.                                                 #
-- #                                                                         #
-- #   Safe to run when there is no demo data. Safe to run twice.            #
-- #                                                                         #
-- ###########################################################################
--
-- WHAT IT DELETES
--
--   Everything belonging to an account whose email ends in
--   @demo.iskconchicago.test, plus every donation whose external_payment_id
--   begins demo-congregation-, in the order the foreign keys require.
--
-- WHAT IT WILL NOT DELETE
--
--   Section 1 refuses to run at all if an account without the demo email
--   marker has somehow ended up in the demo set. Nothing here matches a row
--   by anything except that marker.
--
-- WHAT IT PUTS BACK
--
--   Sevā Mālā scores and service-type weights are a derived cache. Any period
--   the demo data touched is un-frozen and recomputed from the real facts
--   alone (section 4), and any award the recompute hands a real devotee that
--   they did not have before this script started is undone again (section 5),
--   so the temple's own records come out of this byte for byte where they
--   went in.
--
-- HOW TO RUN
--
--   As postgres — the Supabase SQL editor does. It needs to be able to call
--   public.recompute_seva_mala(). One transaction; a failure leaves nothing
--   half-removed.
--
-- ---------------------------------------------------------------------------

begin;

-- ---------------------------------------------------------------------------
-- 1. Who the demo devotees are, and a refusal if that set is not what it
--    claims to be.
-- ---------------------------------------------------------------------------

create temp table demo_ids on commit drop as
  select auth_users.id from auth.users auth_users
  where lower(coalesce(auth_users.email, '')) like '%@demo.iskconchicago.test'
  union
  select devotees.id from public.users devotees
  where lower(coalesce(devotees.email, '')) like '%@demo.iskconchicago.test';

do $$
declare
  v_intruder text;
begin
  select devotees.email into v_intruder
  from public.users devotees
  join demo_ids on demo_ids.id = devotees.id
  where lower(coalesce(devotees.email, '')) not like '%@demo.iskconchicago.test'
  limit 1;

  if v_intruder is not null then
    raise exception
      'Refusing to remove anything: % is in the demo set without the demo email marker.',
      v_intruder;
  end if;
end;
$$;

-- Off for the whole transaction, on again in section 5. devotee_awards is
-- append-only by trigger, and both removing the demo devotees' awards and
-- undoing the ones the rebuild hands a real devotee mean deleting from it;
-- devotee_award_announced would otherwise push a real person about an award
-- that only existed because of the demo.
alter table public.devotee_awards disable trigger devotee_award_announced;
alter table public.devotee_awards disable trigger devotee_awards_append_only;

create temp table demo_awards_before on commit drop as
  select awards.id from public.devotee_awards awards;

-- Captured before the scores go, because that is the only record of which
-- periods the demo data got into.
create temp table demo_periods_touched on commit drop as
  select distinct scores.period_id
  from public.period_scores scores
  where scores.devotee_id in (select id from demo_ids);

create temp table demo_stale_templates on commit drop as
  select templates.id from public.service_templates templates
  where templates.created_by in (select id from demo_ids);

create temp table demo_stale_instances on commit drop as
  select instances.id from public.service_instances instances
  where instances.posted_by in (select id from demo_ids)
     or instances.template_id in (select id from demo_stale_templates);

-- ---------------------------------------------------------------------------
-- 2. The deletions, in dependency order.
--
--    Rows that reference public.users with ON DELETE CASCADE would go anyway;
--    they are listed where the order matters, and the ones referencing it
--    with NO ACTION (service_instances.posted_by, service_templates.created_by,
--    service_assignments.assigned_by, service_verifications.verifier_id) MUST
--    go first or the delete in section 3 fails.
-- ---------------------------------------------------------------------------

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

-- ---------------------------------------------------------------------------
-- 3. The people. The cascade from auth.users → public.users takes
--    period_scores, temple presence, care posts, sanga membership, messages
--    and everything else keyed on the devotee with it.
-- ---------------------------------------------------------------------------

delete from auth.users where id in (select id from demo_ids);
delete from public.users where id in (select id from demo_ids);

-- ---------------------------------------------------------------------------
-- 4. Rebuild the boards from the real facts alone.
--
--    A period whose end date has passed was frozen by the seed's recompute,
--    and a frozen period is never recomputed. So the periods the demo got
--    into are un-frozen first — they are re-frozen by the recompute itself
--    once they have been rebuilt without it.
-- ---------------------------------------------------------------------------

update public.seva_mala_periods
set frozen_at = null
where id in (select period_id from demo_periods_touched);

-- public.seva_type_weights is a pure cache, and recompute_seva_type_weights
-- only ever writes rows for the kinds of seva that were active in the trailing
-- window — it never removes one. So the demo leaves a weight behind for every
-- kind of seva it invented activity for. Clearing the table lets the recompute
-- below write back exactly the rows the temple's own facts justify, and no
-- more. Nothing is lost: every value in it is derived.
delete from public.seva_type_weights;

select public.recompute_seva_mala();

-- ---------------------------------------------------------------------------
-- 5. And take back any award the rebuild handed a real devotee that they did
--    not hold when this script began. The temple's own nightly recompute will
--    grant it again if it was genuinely earned.
-- ---------------------------------------------------------------------------

delete from public.devotee_awards awards
where awards.id not in (select id from demo_awards_before);

alter table public.devotee_awards enable trigger devotee_awards_append_only;
alter table public.devotee_awards enable trigger devotee_award_announced;

-- ---------------------------------------------------------------------------
-- 6. Prove it is gone.
-- ---------------------------------------------------------------------------

do $$
declare
  v_users integer;
  v_auth integer;
  v_donations integer;
  v_templates integer;
  v_instances integer;
  v_left integer;
begin
  select count(*) into v_users from public.users
  where lower(coalesce(email, '')) like '%@demo.iskconchicago.test'
     or id::text like 'decaf000-0000-4000-8000-%';

  select count(*) into v_auth from auth.users
  where lower(coalesce(email, '')) like '%@demo.iskconchicago.test'
     or id::text like 'decaf000-0000-4000-8000-%';

  select count(*) into v_donations from public.donations
  where external_payment_id like 'demo-congregation-%'
     or payload ->> 'demo' = 'true';

  select count(*) into v_templates from public.service_templates
  where created_by::text like 'decaf000-0000-4000-8000-%';

  select count(*) into v_instances from public.service_instances
  where posted_by::text like 'decaf000-0000-4000-8000-%';

  v_left := v_users + v_auth + v_donations + v_templates + v_instances;

  if v_left <> 0 then
    raise exception
      'Demo data survived removal: % profiles, % auth rows, % donations, % templates, % occurrences. Rolling back.',
      v_users, v_auth, v_donations, v_templates, v_instances;
  end if;

  raise notice '';
  raise notice '=== DEMO CONGREGATION REMOVED =============================';
  raise notice '  No demo profile, donation, rota or occurrence remains.';
  raise notice '  Seva Mala has been recomputed from the real data only.';
  raise notice '===========================================================';
end;
$$;

commit;
