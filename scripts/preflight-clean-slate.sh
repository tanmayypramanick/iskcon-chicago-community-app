#!/usr/bin/env bash
# Builds the schema from the real migrations, seeds one of everything the
# clean slate is meant to remove, runs the clean slate, and checks what is
# left. Proves the ordering and the trigger toggling before it touches
# anything hosted.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA_DIR="${ISKCON_PGDATA:-/tmp/iskcon-preflight}"
# The socket path must stay under 103 bytes, so it never lives in the repo.
SOCKET_DIR="${ISKCON_PGSOCKET:-/tmp/iskcon-pf}"
PORT="${ISKCON_PGPORT:-55435}"
DB="iskcon_preflight"

for candidate in /opt/homebrew/opt/postgresql@17/bin /opt/homebrew/opt/postgresql@16/bin \
                 /opt/homebrew/opt/postgresql@15/bin /opt/homebrew/opt/postgresql@14/bin; do
  if [ -x "$candidate/initdb" ]; then PATH="$candidate:$PATH"; break; fi
done
export PATH PGHOST="$SOCKET_DIR" PGPORT="$PORT" PGUSER=postgres

mkdir -p "$SOCKET_DIR"
if [ ! -d "$DATA_DIR/base" ]; then
  rm -rf "$DATA_DIR"
  initdb -D "$DATA_DIR" -U postgres --auth=trust -E UTF8 >/dev/null
fi
pg_ctl -D "$DATA_DIR" -o "-p $PORT -k $SOCKET_DIR -c listen_addresses=" \
  -l "$DATA_DIR/server.log" -w start >/dev/null 2>&1 || true
trap 'pg_ctl -D "$DATA_DIR" -m fast stop >/dev/null 2>&1 || true' EXIT

dropdb --if-exists "$DB"
createdb "$DB"
psql -q -d "$DB" -v ON_ERROR_STOP=1 \
  -f "$REPO_ROOT/supabase/verification/local/bootstrap.sql" >/dev/null 2>&1
psql -q -d "$DB" -c "alter table auth.users add column if not exists phone text;" >/dev/null

echo "applying migrations…"
for file in "$REPO_ROOT"/supabase/migrations/*.sql; do
  psql -q -d "$DB" -v ON_ERROR_STOP=1 -f "$file" >/dev/null 2>&1 \
    || { echo "FAIL $(basename "$file")"; exit 1; }
done
echo "  applied"

echo "seeding one of everything the clean slate removes…"
psql -q -d "$DB" -v ON_ERROR_STOP=1 <<'SQL'
insert into auth.users (id, email, raw_user_meta_data) values
  ('11111111-0000-4000-8000-000000000001', 'tanmayp0612@gmail.com',
     jsonb_build_object('name', 'Tanmay')),
  ('11111111-0000-4000-8000-000000000002', 'arpitajadhav24k@gmail.com',
     jsonb_build_object('name', 'Arpita')),
  ('11111111-0000-4000-8000-000000000003', 'demo-devotee@demo.iskconchicago.test',
     jsonb_build_object('name', 'A Demo Devotee'));

update public.users set role_id = (select id from public.roles where name='president')
where id = '11111111-0000-4000-8000-000000000001';

-- Seva: a rota, an occurrence, a place on it, and an award for it.
insert into public.service_types (id, name, category)
values ('22222222-0000-4000-8000-000000000001', 'Preflight Seva', 'other');

insert into public.service_templates
  (id, service_type_id, day_of_week, start_time, duration_minutes, slots_needed,
   participation_mode, start_date, created_by, days_of_week)
values ('33333333-0000-4000-8000-000000000001',
        '22222222-0000-4000-8000-000000000001', 0, time '07:00', 60, 1,
        'invite_only', current_date - 30, '11111111-0000-4000-8000-000000000001',
        array[0]);

insert into public.service_instances
  (id, template_id, service_type_id, date, start_time, duration_minutes,
   slots_needed, participation_mode, posted_by, status)
values ('44444444-0000-4000-8000-000000000001',
        '33333333-0000-4000-8000-000000000001',
        '22222222-0000-4000-8000-000000000001', current_date - 7, time '07:00',
        60, 1, 'invite_only', '11111111-0000-4000-8000-000000000001', 'completed');

insert into public.service_assignments
  (service_instance_id, devotee_id, assignment_method, assigned_by, status,
   verification, attendance)
values ('44444444-0000-4000-8000-000000000001',
        '11111111-0000-4000-8000-000000000002', 'recurring_assignment',
        '11111111-0000-4000-8000-000000000001', 'completed', 'self_report',
        'served');

insert into public.seva_mala_periods
  (id, period_kind, starts_on, ends_on, participant_count)
values ('55555555-0000-4000-8000-000000000001', 'week',
        current_date - 7, current_date - 1, 1);

insert into public.devotee_awards (award_definition_id, devotee_id, period_id, awarded_on)
select definitions.id, '11111111-0000-4000-8000-000000000002',
       '55555555-0000-4000-8000-000000000001', current_date
from public.award_definitions definitions limit 1;

-- Everything else anybody writes.
insert into public.announcements (title, body, posted_by, kind)
values ('Preflight', 'A notice.', '11111111-0000-4000-8000-000000000001', 'general');

insert into public.sangas (id, name, created_by)
values ('66666666-0000-4000-8000-000000000001', 'Preflight Sanga',
        '11111111-0000-4000-8000-000000000001');
insert into public.sanga_members (sanga_id, devotee_id)
values ('66666666-0000-4000-8000-000000000001',
        '11111111-0000-4000-8000-000000000001');

insert into public.donations
  (donor_id, amount_cents, kind, external_payment_id)
values ('11111111-0000-4000-8000-000000000001', 10800, 'one_time', 'preflight-1');

insert into public.app_notifications (user_id, kind, title, body)
values ('11111111-0000-4000-8000-000000000002', 'announcement_posted', 'Hello', 'Body');

-- And the demo's ledger, which the seed script creates outside the migrations.
create table if not exists public.demo_seva_yatra_ledger (
  id bigserial primary key, entry_kind text, table_name text,
  row_id uuid, detail text, recorded_at timestamptz default now());
insert into public.demo_seva_yatra_ledger (entry_kind) values ('seeded');
SQL
echo "  seeded"

echo "running the clean slate…"
psql -q -d "$DB" -v ON_ERROR_STOP=1 \
  -f "$REPO_ROOT/supabase/maintenance/clean_slate.sql"
echo "  committed"

echo "checking what is left…"
psql -q -d "$DB" -v ON_ERROR_STOP=1 <<'SQL'
do $$
declare n integer; emails text;
begin
  select count(*) into n from auth.users;
  if n <> 2 then raise exception 'expected 2 accounts, found %', n; end if;

  select string_agg(email, ', ' order by email) into emails from auth.users;
  if emails <> 'arpitajadhav24k@gmail.com, tanmayp0612@gmail.com' then
    raise exception 'the wrong accounts survived: %', emails;
  end if;

  select count(*) into n from public.users;
  if n <> 2 then raise exception 'expected 2 profiles, found %', n; end if;

  select count(*) into n from public.service_instances;
  if n <> 0 then raise exception 'seva survived: % instances', n; end if;
  select count(*) into n from public.service_assignments;
  if n <> 0 then raise exception 'seva survived: % assignments', n; end if;
  select count(*) into n from public.service_templates;
  if n <> 0 then raise exception 'rotas survived: %', n; end if;
  select count(*) into n from public.devotee_awards;
  if n <> 0 then raise exception 'awards survived: %', n; end if;
  select count(*) into n from public.seva_mala_periods;
  if n <> 0 then raise exception 'periods survived: %', n; end if;
  select count(*) into n from public.announcements;
  if n <> 0 then raise exception 'announcements survived: %', n; end if;
  select count(*) into n from public.sangas;
  if n <> 0 then raise exception 'sangas survived: %', n; end if;
  select count(*) into n from public.donations;
  if n <> 0 then raise exception 'giving survived: %', n; end if;
  select count(*) into n from public.app_notifications;
  if n <> 0 then raise exception 'notifications survived: %', n; end if;

  -- Reference data is untouched.
  select count(*) into n from public.service_types;
  raise notice 'service types left: %', n;
  if not exists (select 1 from public.service_types
                 where id = '22222222-0000-4000-8000-000000000001') then
    raise exception 'the service type list was emptied';
  end if;
  select count(*) into n from public.roles;
  if n = 0 then raise exception 'the roles were emptied'; end if;
  select count(*) into n from public.award_definitions;
  if n = 0 then raise exception 'the award definitions were emptied'; end if;

  -- The demo ledger is gone, table and all.
  if to_regclass('public.demo_seva_yatra_ledger') is not null then
    raise exception 'the demo ledger table is still there';
  end if;

  -- And the award guard is back on.
  if not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.devotee_awards'::regclass
      and tgname = 'devotee_awards_append_only'
      and tgenabled <> 'D'
  ) then
    raise exception 'the append-only guard was left disabled';
  end if;

  raise notice 'the clean slate leaves two accounts and the reference data';
end $$;
SQL

echo
echo "PREFLIGHT PASSED"
