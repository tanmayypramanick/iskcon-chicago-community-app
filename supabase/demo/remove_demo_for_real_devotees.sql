-- ###########################################################################
-- #                                                                         #
-- #   R E M O V E   T H E   R E A L - A C C O U N T   D E M O               #
-- #                                                                         #
-- #   Deletes every row created by                                          #
-- #   supabase/demo/seed_demo_for_real_devotees.sql and leaves Tanmay's and #
-- #   Arpita's real accounts, the fictional congregation seeded by          #
-- #   supabase/demo/seed_demo_congregation.sql, and the temple's own seva,  #
-- #   giving and awards exactly as it found them.                           #
-- #                                                                         #
-- #   Safe to run when there is no demo data. Safe to run twice.            #
-- #                                                                         #
-- ###########################################################################
--
-- HOW IT KNOWS WHAT TO DELETE
--
--   public.demo_seva_yatra_ledger, which the seed writes and this script
--   drops. It holds four kinds of entry:
--
--     seeded              one row, saying the seed ran. Without it this script
--                         does nothing at all, which is what makes it safe on
--                         a database that never had the demo.
--     row                 one per row the seed created, as (table, id). Taken
--                         as the difference between a snapshot of every table
--                         the seed can reach, before and after — so it holds
--                         the rows the seed inserted AND the rows the temple's
--                         own RPCs inserted underneath it.
--     award_before        one per award that existed BEFORE the seed ran.
--     period_open_before  one per Sevā Mālā period that was still open when
--                         the seed ran.
--
--   Nothing here matches a row by a name, an email, a date or a devotee. Two
--   real accounts cannot be marked, so the only safe question is "did this
--   script create this exact row", and the ledger is the only thing that can
--   answer it.
--
-- WHAT IT WILL NOT DELETE
--
--   * Anything Tanmay or Arpita did themselves. Their profiles are never
--     written to by either script, and a row they created after the seed ran
--     is not in the ledger.
--   * An occurrence the seed created that somebody has since JOINED. Deleting
--     it would cascade a real devotee's place away with it, and no tidiness is
--     worth that. The seed's own rows on it go; the occurrence stays.
--   * Any award that was already on somebody's shelf.
--
-- WHAT IT PUTS BACK
--
--   Sevā Mālā scores, the service-type weights and the award shelf are derived
--   from the facts. The periods the seed opened are re-opened, the weights are
--   cleared, everything is recomputed from what is left, and any award the
--   rebuild hands out that was not there before the seed is undone again — so
--   the shelf comes out of this exactly where it went in.
--
--   ONE CAVEAT, SAID OUT LOUD. An award genuinely earned in the days BETWEEN
--   the seed and this removal is also undone, because nothing can tell it apart
--   from an award the demo caused. The temple's own nightly recompute grants it
--   again if it was real. This is the same trade
--   supabase/demo/remove_demo_congregation.sql makes, for the same reason.
--
-- HOW TO RUN
--
--   As postgres — the Supabase SQL editor does. It needs to call
--   public.recompute_seva_mala() and to disable three triggers. One
--   transaction; a failure leaves nothing half-removed.
--
-- ---------------------------------------------------------------------------

begin;

-- ---------------------------------------------------------------------------
-- 1. Is there anything to remove?
--
--    The ledger is created empty if it is missing, so every statement below
--    parses and runs against a database that never had the demo and does
--    nothing to it. The sentinel, not the table, is what says the seed ran —
--    an empty ledger with no sentinel must never be read as "the shelf was
--    empty before", which would delete every award in the temple.
-- ---------------------------------------------------------------------------

do $$
begin
  if to_regclass('public.demo_seva_yatra_ledger') is null then
    create table public.demo_seva_yatra_ledger (
      id          bigint generated always as identity primary key,
      entry_kind  text not null check (entry_kind in (
                     'seeded', 'row', 'award_before', 'period_open_before')),
      table_name  text,
      row_id      uuid,
      detail      text,
      recorded_at timestamptz not null default now()
    );
  end if;
end;
$$;

create temp table dsy_seeded on commit drop as
  select exists (
    select 1 from public.demo_seva_yatra_ledger where entry_kind = 'seeded'
  ) as seeded;

do $$
begin
  if not public.is_backend_caller() then
    raise exception
      'Run this as postgres (the Supabase SQL editor does). It has to recompute Seva Mala at the end.';
  end if;

  if not (select seeded from dsy_seeded) then
    raise notice '';
    raise notice 'No real-account demo is present. Nothing to remove.';
  end if;
end;
$$;

-- The tables the seed watched, CHILD FIRST, which is the order the foreign
-- keys require them to be deleted in. This is the same list, in the same
-- order, as section 3 of supabase/demo/seed_demo_for_real_devotees.sql. If you
-- change one, change the other.
create temp table dsy_tracked (position integer primary key, table_name text not null)
  on commit drop;

insert into dsy_tracked (position, table_name) values
  ( 1, 'donations'),
  ( 2, 'service_verifications'),
  ( 3, 'service_qr_sessions'),
  ( 4, 'service_offer_counters'),
  ( 5, 'service_offers'),
  ( 6, 'service_assignments'),
  ( 7, 'service_coverage_plans'),
  ( 8, 'service_exceptions'),
  ( 9, 'service_instances'),
  (10, 'service_template_assignees'),
  (11, 'service_templates'),
  (12, 'sponsorship_bookings'),
  (13, 'seva_care_dismissals'),
  (14, 'seva_mala_periods');

-- ---------------------------------------------------------------------------
-- 2. The triggers that would otherwise fight this.
--
--      devotee_awards_append_only  makes taking an award back impossible,
--                                  which is exactly what undoing the seed's
--                                  awards is.
--      devotee_award_announced     would push a real person about an award
--                                  that only existed because of a demo, in the
--                                  middle of removing the demo.
--      deliver_app_notification    the recompute below can produce nothing
--                                  that should reach a phone. This is belt and
--                                  braces; section 5 deletes the rows too.
--
--    All three are restored in section 6, before commit.
-- ---------------------------------------------------------------------------

alter table public.devotee_awards disable trigger devotee_award_announced;
alter table public.devotee_awards disable trigger devotee_awards_append_only;
alter table public.app_notifications disable trigger deliver_app_notification;

create temp table dsy_notifications_before on commit drop as
  select notifications.id from public.app_notifications notifications;

-- ---------------------------------------------------------------------------
-- 3. The deletions.
--
--    Awards go FIRST. devotee_awards.period_id is ON DELETE SET NULL, so a
--    period deleted before its awards leaves award rows pointing at nothing —
--    which would be a badge on somebody's shelf belonging to a week that no
--    longer exists.
-- ---------------------------------------------------------------------------

do $$
declare
  v_row record;
begin
  if not (select seeded from dsy_seeded) then
    return;
  end if;

  delete from public.devotee_awards
  where id not in (
    select ledger.row_id from public.demo_seva_yatra_ledger ledger
    where ledger.entry_kind = 'award_before'
  );

  for v_row in select table_name from dsy_tracked order by position loop
    if v_row.table_name = 'service_instances' then
      execute $q$
        delete from public.service_instances instances
        where instances.id in (
          select ledger.row_id from public.demo_seva_yatra_ledger ledger
          where ledger.entry_kind = 'row' and ledger.table_name = 'service_instances'
        )
        and not exists (
          select 1 from public.service_assignments assignments
          where assignments.service_instance_id = instances.id
        )
      $q$;
    else
      execute format($q$
        delete from public.%I
        where id in (
          select ledger.row_id from public.demo_seva_yatra_ledger ledger
          where ledger.entry_kind = 'row' and ledger.table_name = %L
        )
      $q$, v_row.table_name, v_row.table_name);
    end if;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Rebuild the boards from what is left.
--
--    A period the seed FROZE has to be re-opened, or it stays frozen at a
--    score computed from data that no longer exists — a frozen period is never
--    recomputed, which is the whole point of freezing one. The ledger says
--    which periods were open before the seed ran; every one of them that still
--    exists is put back that way, and the recompute re-freezes any whose end
--    date has genuinely passed since.
--
--    public.seva_type_weights is a pure cache, and
--    recompute_seva_type_weights only ever writes rows for the kinds of seva
--    that were active in the trailing window — it never removes one. So the
--    demo can leave a weight behind for a seva nothing else in the temple has
--    done for months. Clearing the table lets the recompute write back exactly
--    the rows the remaining facts justify, and no more. Nothing is lost: every
--    value in it is derived.
-- ---------------------------------------------------------------------------

do $$
begin
  if not (select seeded from dsy_seeded) then
    return;
  end if;

  update public.seva_mala_periods
  set frozen_at = null
  where id in (
    select ledger.row_id from public.demo_seva_yatra_ledger ledger
    where ledger.entry_kind = 'period_open_before'
  );

  delete from public.seva_type_weights;
end;
$$;

select public.recompute_seva_mala();

-- ---------------------------------------------------------------------------
-- 5. And take back anything the rebuild handed out that was not there before.
-- ---------------------------------------------------------------------------

do $$
begin
  if not (select seeded from dsy_seeded) then
    return;
  end if;

  delete from public.devotee_awards
  where id not in (
    select ledger.row_id from public.demo_seva_yatra_ledger ledger
    where ledger.entry_kind = 'award_before'
  );
end;
$$;

delete from public.app_notifications
where id not in (select id from dsy_notifications_before);

-- ---------------------------------------------------------------------------
-- 6. The triggers go back on, inside this transaction.
-- ---------------------------------------------------------------------------

alter table public.app_notifications enable trigger deliver_app_notification;
alter table public.devotee_awards enable trigger devotee_awards_append_only;
alter table public.devotee_awards enable trigger devotee_award_announced;

-- ---------------------------------------------------------------------------
-- 7. Prove it is gone, and then destroy the evidence of what there was.
--
--    Asserted before the ledger is dropped, because the ledger is the only
--    thing that knows what was supposed to go.
-- ---------------------------------------------------------------------------

do $$
declare
  v_row record;
  v_left bigint := 0;
  v_count bigint;
  v_kept bigint := 0;
begin
  if not (select seeded from dsy_seeded) then
    return;
  end if;

  for v_row in select table_name from dsy_tracked order by position loop
    execute format($q$
      select count(*) from public.%I rows
      where rows.id in (
        select ledger.row_id from public.demo_seva_yatra_ledger ledger
        where ledger.entry_kind = 'row' and ledger.table_name = %L
      )
    $q$, v_row.table_name, v_row.table_name) into v_count;

    if v_count > 0 and v_row.table_name = 'service_instances' then
      -- The one exception this script allows itself, and only for occurrences
      -- somebody else is now standing on.
      v_kept := v_count;
    elsif v_count > 0 then
      raise exception
        '% row(s) recorded in the ledger survived removal from public.%. Rolling back.',
        v_count, v_row.table_name;
    end if;
  end loop;

  select count(*) into v_left
  from public.devotee_awards awards
  where awards.id not in (
    select ledger.row_id from public.demo_seva_yatra_ledger ledger
    where ledger.entry_kind = 'award_before'
  );

  if v_left <> 0 then
    raise exception '% award(s) the demo caused survived removal. Rolling back.', v_left;
  end if;

  raise notice '';
  raise notice '=== REAL-ACCOUNT DEMO REMOVED =============================';
  raise notice '  Every row the seed created is gone.';
  if v_kept > 0 then
    raise notice '  % occurrence(s) were KEPT because somebody has joined them', v_kept;
    raise notice '  since the demo was seeded. Their demo places are gone.';
  end if;
  raise notice '  Seva Mala has been recomputed from the remaining facts.';
  raise notice '  Nobody''s profile, seva or giving was written to.';
  raise notice '===========================================================';
end;
$$;

drop table if exists public.demo_seva_yatra_ledger;

commit;
