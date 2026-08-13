-- Structural and authority verification for 202608120071.
-- The final row must read: conversation removal verification passed

begin;

do $$
declare
  v_function oid := to_regprocedure('public.remove_conversation_for_me(uuid)');
begin
  if to_regclass('public.conversation_cleared_for') is null then
    raise exception 'conversation_cleared_for was not created.';
  end if;
  if v_function is null then
    raise exception 'remove_conversation_for_me(uuid) was not created.';
  end if;
  if not has_function_privilege('authenticated', v_function, 'execute') then
    raise exception 'Authenticated devotees cannot remove their own conversation.';
  end if;
  if has_function_privilege('anon', v_function, 'execute') then
    raise exception 'Anonymous users can remove conversations.';
  end if;
  if to_regprocedure('public.list_conversation_messages(uuid)') is null then
    raise exception 'The retained leadership conversation reader is missing.';
  end if;
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'conversation_cleared_for'
      and policyname = 'Devotees read their own conversation clear markers'
  ) then
    raise exception 'The clear-marker ownership policy is missing.';
  end if;
end;
$$;

select 'conversation removal verification passed' as result;

rollback;
