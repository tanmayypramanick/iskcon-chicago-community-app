do $$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'service_template_assignees'
      and column_name = 'days_of_week'
  ) then raise exception 'Missing day-specific weekly assignees.'; end if;

  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'service_exceptions'
      and column_name = 'request_group_id'
  ) then raise exception 'Missing grouped coverage requests.'; end if;

  if to_regprocedure('public.join_weekly_service(uuid)') is null
    or to_regprocedure('public.report_weekly_service_unavailable(uuid,text,date,date,integer[],text)') is null
    or to_regprocedure('public.offer_service_coverage_range(uuid,uuid,text,date,date)') is null
    or to_regprocedure('public.respond_to_coverage_range_offer(uuid,boolean)') is null
  then raise exception 'A required weekly-seva RPC is missing.'; end if;

  if exists (
    select 1
    from public.role_permissions permissions
    join public.roles roles on roles.id = permissions.role_id
    where roles.name = 'volunteer'
      and permissions.permission_key in (
        'services.view_all',
        'services.oversee_activity', 'services.complete_requirement',
        'services.resolve_coverage', 'services.manage_recurring'
      )
  ) then raise exception 'Volunteer still has coordinator or schedule access.'; end if;

  -- services.offer_assignment came back in 0015 on purpose: a Volunteer posts
  -- a seva request, so they must be able to invite devotees to it.
  if not exists (
    select 1
    from public.role_permissions permissions
    join public.roles roles on roles.id = permissions.role_id
    where roles.name = 'volunteer'
      and permissions.permission_key = 'services.offer_assignment'
  ) then raise exception 'Volunteer cannot invite devotees to a seva they post.'; end if;

  if not exists (
    select 1
    from public.role_permissions permissions
    join public.roles roles on roles.id = permissions.role_id
    where roles.name = 'volunteer'
      and permissions.permission_key = 'services.post_requirement'
  ) then raise exception 'Volunteer cannot post a service need.'; end if;
end;
$$;

select 'weekly seva schema verification passed' as result;
