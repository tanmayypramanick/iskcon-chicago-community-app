# Maintenance

One-off operations against the hosted project. Nothing here runs on its own,
and nothing here is a migration — these are things you do deliberately, once,
and then read the result of.

## Clean slate

[`clean_slate.sql`](clean_slate.sql) empties the live project down to two
accounts and the temple's reference data, so the app can be tested from
nothing.

**Kept** — `tanmayp0612@gmail.com` and `arpitajadhav24k@gmail.com` and their
profiles; roles and permissions; the service types; award definitions; the
Vaiṣṇava calendar and its publications; the temple programme, deities and
sponsorship types; app settings.

**Gone** — every other account, all seva of every kind, Sevā Mālā periods,
scores and awards, announcements, sangas, chats, giving, sponsorship bookings,
care posts, feedback, access requests, presence, notifications, push tokens,
and the demo ledger table itself.

Run it in the **Supabase SQL Editor**, which runs as `postgres`. The script has
to turn the append-only guard on `devotee_awards` off for the length of the
transaction, and `alter table … disable trigger` needs the table's owner.

```bash
cat supabase/maintenance/clean_slate.sql | pbcopy   # then paste and run
```

It is one `begin; … commit;`, so it either all lands or none of it does — a
failure part-way through leaves the project exactly as it was, guard included.

### Files are separate, and deliberately so

The script does not delete anything from Storage, and cannot: `storage.objects`
and `storage.buckets` both carry a `protect_delete` trigger that refuses SQL
outright, because a row deleted that way would leave the file itself orphaned
in the bucket forever. Files go through the Storage API.

Nothing in the script cascades into Storage either — no storage table has a
foreign key to `auth.users` — so removing the accounts leaves their files whole
rather than half-deleted.

To see what is in a bucket:

```bash
npx supabase storage ls --linked --experimental -r ss:///message-images
```

To remove it, use the **Storage browser in the dashboard** — open the bucket,
tick the folder, delete. `supabase storage rm` is not usable for this: on this
project it answers `{"deleted":[]}` and removes nothing, for a whole prefix and
for a single named file alike, without reporting an error.

What needs removing after a clean slate is small: the chat pictures in
`message-images`, whose messages the script has just deleted. Profile photos in
`devotee-photos` are named by their owner's uuid — leave the two live accounts'
folders alone, and remove any other folder still there once the accounts have
gone.

### Proving it before running it

[`../../scripts/preflight-clean-slate.sh`](../../scripts/preflight-clean-slate.sh)
builds the schema from the real migrations on a throwaway local Postgres, seeds
one of everything the clean slate is meant to remove, runs the clean slate
against it, and checks what is left — that the right two accounts survive, that
no seva of any kind does, that the reference data is untouched, that the demo
ledger table is gone, and that the append-only guard is back on.

```bash
ISKCON_PGDATA=/tmp/iskcon-preflight ISKCON_PGSOCKET=/tmp/iskcon-pf \
ISKCON_PGPORT=55435 ./scripts/preflight-clean-slate.sh
```

Needs a local Postgres 14+ (`brew install postgresql@17`). It never touches the
hosted database.

## Removing the demo instead

If you want the demo gone but everything the temple did kept, do not use the
clean slate — [`../demo/remove_demo_congregation.sql`](../demo/remove_demo_congregation.sql)
and [`../demo/remove_demo_for_real_devotees.sql`](../demo/remove_demo_for_real_devotees.sql)
undo exactly what the seeds created, row by row, from the ledger they wrote.
Both are safe to run twice and safe to run on a database that never had the
demo.
