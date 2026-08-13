-- Run after 202608020006_service_one_time_offer_conflict_fix.sql.

select
  to_regprocedure(
    'public.create_service_requirement(uuid,text,date,time without time zone,integer,integer,text,uuid[])'
  ) as create_requirement_rpc,
  to_regprocedure(
    'public.offer_service_instance(uuid,uuid)'
  ) as offer_instance_rpc;

with definitions as (
  select
    proname,
    pg_get_functiondef(pg_proc.oid) as definition
  from pg_proc
  join pg_namespace on pg_namespace.oid = pg_proc.pronamespace
  where pg_namespace.nspname = 'public'
    and proname in (
      'create_service_requirement',
      'offer_service_instance'
    )
)
select
  proname,
  definition like '%where offer_kind = ''one_time''%' as targets_partial_index
from definitions
order by proname;

