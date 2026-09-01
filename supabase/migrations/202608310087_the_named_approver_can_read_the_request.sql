-- The devotee who was asked to approve an access request can actually see it.
-- Requires 202608020001_access_levels.sql and 202608040047_access_appointments.sql.
--
-- Three layers disagreed, and the devotee in the middle got a locked screen.
--
--   * public.answer_access_request accepts the named approver:
--     `approver_id = auth.uid() or has_permission('access.review_requests')`
--     (202608040047 ~615).
--   * create_access_request NOTIFIES that named approver
--     (202608040031 ~102), and the notification routes to AccessRequestReview.
--   * But the SELECT policy on public.access_requests allowed only
--     `requester_id = auth.uid() or has_permission('access.review_requests')`,
--     and access.review_requests is President and Tech Admin only. So a
--     Community Head asked to approve somebody could not read the row, and the
--     screen they were sent to had nothing to show them.
--
-- The server already decided the named approver may answer. This lets them
-- read the one request they were named on — and nothing else: the policy is
-- scoped to `approver_id = auth.uid()`, not to the whole table.

drop policy if exists
  "Users can read their requests and reviewers can read all requests"
  on public.access_requests;

create policy "Users can read their requests and reviewers can read all requests"
  on public.access_requests for select
  to authenticated
  using (
    requester_id = auth.uid()
    or approver_id = auth.uid()
    or public.has_permission('access.review_requests')
  );

-- ---------------------------------------------------------------------------
-- Proof, run at migration time.
-- ---------------------------------------------------------------------------
do $$
declare
  v_using text;
begin
  select pg_get_expr(polqual, polrelid) into v_using
  from pg_policy
  where polrelid = 'public.access_requests'::regclass
    and polname = 'Users can read their requests and reviewers can read all requests';

  if v_using is null then
    raise exception 'the access_requests read policy is missing';
  end if;

  if v_using not like '%approver_id%' then
    raise exception
      'the named approver still cannot read the request they were asked to answer: %',
      v_using;
  end if;

  -- The scope must not have widened while fixing it.
  if v_using not like '%requester_id%'
     or v_using not like '%review_requests%'
  then
    raise exception 'the access_requests read policy lost one of its other arms: %', v_using;
  end if;

  raise notice 'the named approver can read their own access request';
end;
$$;
