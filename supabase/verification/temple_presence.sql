-- Run after 202608020004_temple_presence.sql.
-- The final query returns today's actual check-ins and may return zero rows.

select
  to_regclass('public.temple_presence') as temple_presence,
  to_regprocedure('public.set_my_temple_presence(boolean,text)') as set_presence_rpc,
  to_regprocedure('public.list_temple_presence_today()') as list_presence_rpc;

select schemaname, tablename, policyname
from pg_policies
where schemaname = 'public'
  and tablename = 'temple_presence';

select tablename
from pg_publication_tables
where pubname = 'supabase_realtime'
  and schemaname = 'public'
  and tablename = 'temple_presence';

select * from public.list_temple_presence_today();
