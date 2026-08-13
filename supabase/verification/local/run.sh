#!/usr/bin/env bash
# Apply every migration and run every verification script against a throwaway
# local Postgres, so a change can be proven before it reaches Supabase.
#
#   supabase/verification/local/run.sh
#
# Needs a local Postgres 14+ (brew install postgresql@14). Nothing here touches
# the hosted database.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
HERE="$REPO_ROOT/supabase/verification/local"
DATA_DIR="${ISKCON_PGDATA:-/tmp/iskcon-pgdata}"
SOCKET_DIR="${ISKCON_PGSOCKET:-/tmp/iskcon-pg}"
PORT="${ISKCON_PGPORT:-55433}"
DB="iskcon_verify"

for candidate in /opt/homebrew/opt/postgresql@17/bin /opt/homebrew/opt/postgresql@16/bin \
                 /opt/homebrew/opt/postgresql@15/bin /opt/homebrew/opt/postgresql@14/bin \
                 /usr/local/opt/postgresql@14/bin; do
  if [ -x "$candidate/initdb" ]; then PATH="$candidate:$PATH"; break; fi
done
export PATH PGHOST="$SOCKET_DIR" PGPORT="$PORT" PGUSER=postgres

command -v initdb >/dev/null || { echo "initdb not found — install postgresql first"; exit 1; }

# The socket path must stay under 103 bytes, so it never lives in the repo.
mkdir -p "$SOCKET_DIR"
if [ ! -d "$DATA_DIR/base" ]; then
  rm -rf "$DATA_DIR"
  initdb -D "$DATA_DIR" -U postgres --auth=trust -E UTF8 >/dev/null
fi
pg_ctl -D "$DATA_DIR" -o "-p $PORT -k $SOCKET_DIR -c listen_addresses=" \
  -l "$DATA_DIR/server.log" -w start >/dev/null 2>&1 || true

cleanup() { pg_ctl -D "$DATA_DIR" -m fast stop >/dev/null 2>&1 || true; }
trap cleanup EXIT

dropdb --if-exists "$DB"
createdb "$DB"

# Supabase supplies auth, storage and the realtime publication. This is the
# smallest shim that lets the real migrations run unmodified.
psql -q -d "$DB" -v ON_ERROR_STOP=1 -f "$HERE/bootstrap.sql" >/dev/null 2>&1
psql -q -d "$DB" -c "alter table auth.users add column if not exists phone text;" >/dev/null

failures=0

echo "migrations"
for file in "$REPO_ROOT"/supabase/migrations/*.sql; do
  name="$(basename "$file")"
  if output=$(psql -q -d "$DB" -v ON_ERROR_STOP=1 -f "$file" 2>&1); then
    printf '  ok    %s\n' "$name"
  else
    printf '  FAIL  %s\n' "$name"
    echo "$output" | grep -E 'ERROR|DETAIL|CONTEXT|HINT' | head -6 | sed 's/^/        /'
    failures=$((failures + 1))
    break
  fi
done

echo "verification"
for file in "$REPO_ROOT"/supabase/verification/*.sql; do
  name="$(basename "$file")"
  output=$(psql -q -d "$DB" -v ON_ERROR_STOP=1 -f "$file" 2>&1) || true
  if echo "$output" | grep -q 'ERROR'; then
    printf '  FAIL  %s\n' "$name"
    echo "$output" | grep -E 'ERROR|DETAIL|CONTEXT|HINT' | head -6 | sed 's/^/        /'
    failures=$((failures + 1))
  else
    printf '  ok    %s\n' "$name"
  fi
done

if [ "$failures" -ne 0 ]; then
  echo
  echo "$failures failed"
  exit 1
fi

echo
echo "all migrations applied and every verification script passed"
