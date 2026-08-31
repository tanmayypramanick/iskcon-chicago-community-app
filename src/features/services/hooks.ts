import {
  useMutation,
  useQueries,
  useQuery,
  useQueryClient,
} from "@tanstack/react-query";
import { useEffect, useRef, useState } from "react";

import { useChannelSuffix } from "../../lib/channelSuffix";
import { getSupabaseClient } from "../../lib/supabase";
import { groupClosedUnserved } from "./clashes";
import {
  completeService,
  completeMyServiceAssignment,
  createServiceRequirement,
  createRecurringService,
  deleteRecurringService,
  deleteServiceActivity,
  deleteServiceAssignmentActivity,
  deleteServiceRequirement,
  deleteSevaRegistration,
  fetchClosedUnservedSeva,
  fetchServiceDashboard,
  fetchSevaClashes,
  fetchSevaVerifiers,
  joinService,
  joinWeeklyService,
  leaveService,
  offerService,
  offerServiceCoverage,
  offerServiceCoverageRange,
  reopenServiceException,
  reportWeeklyServiceUnavailable,
  reviewRecurringServiceInterest,
  respondToServiceOffer,
  respondToCoverageRangeOffer,
  setRecurringServiceActive,
  proposeServiceOfferAlternative,
  proposeWeeklyOfferAlternative,
  recordSevaAttendance,
  respondToServiceOfferCounter,
  updateServiceRequirement,
  requestSevaVerification,
  logCompletedSeva,
  resendSevaVerification,
  respondToSevaVerification,
  respondToWeeklyOfferCounter,
  submitRecurringServiceInterest,
  updateRecurringService,
} from "./api";
import { unconfirmedAssignmentIds } from "./selectors";
import type {
  ClosedUnservedSeva,
  ServiceAssignmentRow,
  ServiceDashboard,
  ServiceListItem,
  SevaClash,
  SevaClashQuery,
} from "./types";
import type {
  CoverageRangeInput,
  CreateRecurringServiceInput,
  CreateRequirementInput,
  ProposeAlternativeInput,
  RecurringServiceInterestInput,
  RequestVerificationInput,
  LogCompletedSevaInput,
  UpdateRecurringServiceInput,
  WeeklyUnavailableInput,
} from "./types";

const serviceKeys = {
  all: ["services"] as const,
  /** Matches every signed-in account's cached dashboard, whoever it belongs to. */
  dashboards: ["services", "dashboard"] as const,
  dashboard: (userId: string | null) =>
    ["services", "dashboard", userId] as const,
};

export function useServiceDashboard(userId: string | null) {
  return useQuery({
    queryKey: serviceKeys.dashboard(userId),
    queryFn: () => fetchServiceDashboard(userId!),
    enabled: Boolean(userId),
    // Realtime subscriptions handle normal updates. This poll is only a
    // recovery path if a device briefly loses its realtime connection, so it
    // stays infrequent — each run rebuilds the whole dashboard on the JS
    // thread, which is expensive on low-powered devices.
    refetchInterval: 5 * 60_000,
  });
}

function useServiceMutation<TVariables>(
  mutationFn: (variables: TVariables) => Promise<unknown>,
) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn,
    // Only what is on screen refetches. Invalidating every cached seva query
    // made an answered invitation sit there while unrelated lists reloaded,
    // which read as the button not working.
    onSuccess: () =>
      queryClient.invalidateQueries({
        queryKey: serviceKeys.all,
        refetchType: "active",
      }),
  });
}

export function useCreateServiceRequirement() {
  return useServiceMutation<CreateRequirementInput>(createServiceRequirement);
}

export function useJoinService() {
  return useServiceMutation<string>(joinService);
}

export function useJoinWeeklyService() {
  return useServiceMutation<string>(joinWeeklyService);
}

export function useLeaveService() {
  return useServiceMutation<string>(leaveService);
}

export function useOfferService() {
  return useServiceMutation<{ instanceId: string; devoteeId: string }>(
    ({ instanceId, devoteeId }) => offerService(instanceId, devoteeId),
  );
}

export function useRespondToServiceOffer() {
  return useServiceMutation<{ offerId: string; accept: boolean }>(
    ({ offerId, accept }) => respondToServiceOffer(offerId, accept),
  );
}

export function useCompleteService() {
  return useServiceMutation<string>(completeService);
}

export function useCompleteMyServiceAssignment() {
  return useServiceMutation<string>(completeMyServiceAssignment);
}





export function useDeleteServiceActivity() {
  return useServiceMutation<string>(deleteServiceActivity);
}

export function useDeleteServiceAssignmentActivity() {
  return useServiceMutation<string>(deleteServiceAssignmentActivity);
}

export function useDeleteServiceRequirement() {
  return useServiceMutation<string>(deleteServiceRequirement);
}

export function useSubmitRecurringServiceInterest() {
  return useServiceMutation<RecurringServiceInterestInput>(
    submitRecurringServiceInterest,
  );
}

export function useReviewRecurringServiceInterest() {
  return useServiceMutation<{
    interestId: string;
    approve: boolean;
    reviewNote: string | null;
  }>(({ interestId, approve, reviewNote }) =>
    reviewRecurringServiceInterest(interestId, approve, reviewNote),
  );
}

export function useCreateRecurringService() {
  return useServiceMutation<CreateRecurringServiceInput>(
    createRecurringService,
  );
}

export function useUpdateRecurringService() {
  return useServiceMutation<UpdateRecurringServiceInput>(
    updateRecurringService,
  );
}

export function useDeleteRecurringService() {
  return useServiceMutation<string>(deleteRecurringService);
}

export function useReportWeeklyServiceUnavailable() {
  return useServiceMutation<WeeklyUnavailableInput>(
    reportWeeklyServiceUnavailable,
  );
}

export function useReopenServiceException() {
  return useServiceMutation<string>(reopenServiceException);
}

export function useOfferServiceCoverage() {
  return useServiceMutation<{ exceptionId: string; devoteeId: string }>(
    ({ exceptionId, devoteeId }) =>
      offerServiceCoverage(exceptionId, devoteeId),
  );
}

export function useOfferServiceCoverageRange() {
  return useServiceMutation<CoverageRangeInput>(offerServiceCoverageRange);
}

export function useRespondToCoverageRangeOffer() {
  return useServiceMutation<{ offerId: string; accept: boolean }>(
    ({ offerId, accept }) => respondToCoverageRangeOffer(offerId, accept),
  );
}

export function useSetRecurringServiceActive() {
  return useServiceMutation<{ templateId: string; active: boolean }>(
    ({ templateId, active }) => setRecurringServiceActive(templateId, active),
  );
}

export function useServiceRealtime() {
  const queryClient = useQueryClient();
  const suffix = useChannelSuffix();

  useEffect(() => {
    // One coordinator action fans out across several of these tables at once
    // (instance + assignment + offer + notification). Without coalescing, a
    // single "post a seva" produced four full dashboard refetches on every
    // connected device. A short window collapses the burst into one refresh
    // while still feeling immediate.
    let pending: ReturnType<typeof setTimeout> | null = null;
    const refresh = () => {
      if (pending) return;
      pending = setTimeout(() => {
        pending = null;
        void queryClient.invalidateQueries({ queryKey: serviceKeys.all });
      }, 220);
    };
    const channel = getSupabaseClient()
      // Per mount, never a fixed name. Two screens both watching the seva board
      // — which is every push transition, and now every screen that shows a
      // clash warning — would otherwise be handed the same channel object, and
      // the second one's listeners throw against an already-subscribed channel.
      .channel(`service-board-live-${suffix}`)
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "service_instances" },
        refresh,
      )
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "service_coverage_plans" },
        refresh,
      )
      .on(
        "postgres_changes",
        {
          event: "*",
          schema: "public",
          table: "recurring_service_interests",
        },
        refresh,
      )
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "service_templates" },
        refresh,
      )
      .on(
        "postgres_changes",
        {
          event: "*",
          schema: "public",
          table: "service_template_assignees",
        },
        refresh,
      )
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "service_exceptions" },
        refresh,
      )
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "service_assignments" },
        refresh,
      )
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "service_offers" },
        refresh,
      )
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "service_verifications" },
        refresh,
      )
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "service_offer_counters" },
        refresh,
      )
      .subscribe();

    return () => {
      if (pending) clearTimeout(pending);
      void getSupabaseClient().removeChannel(channel);
    };
  }, [queryClient, suffix]);
}

/** One clash question, plus the caller's own name for the answer. */
export type ClashRequest = SevaClashQuery & {
  /** How the caller looks the answer up again. */
  key: string;
  /**
   * Off when the caller already knows the question cannot be asked — nobody is
   * selected yet, or this account lacks `services.offer_assignment` and the
   * devotee is not themselves.
   */
  enabled?: boolean;
};

function clashQueryKey(request: SevaClashQuery) {
  return [
    "services",
    "clashes",
    request.devoteeId,
    request.date,
    request.startTime,
    request.durationMinutes,
    request.excludeInstanceId ?? null,
  ] as const;
}

/**
 * Live clash answers for as many windows as a screen needs at once.
 *
 * The temple asked for clashes that update as devotees rearrange their seva, so
 * the keys sit under `serviceKeys.all`. `useServiceRealtime` invalidates that
 * whole prefix, and every mutation on the tab does too, so a clash answer is
 * refetched the moment anything about anybody's seva moves — and the warning a
 * screen is drawing from it changes with it.
 *
 * WHY NOT DROP THE ANSWER THE INSTANT IT IS INVALIDATED. React Query clears
 * `isInvalidated` as soon as the refetch it triggered begins, so there is no
 * flag that means "this answer is under suspicion" for a caller to read; the
 * only thing available during the round trip is `isFetching`, which is true for
 * every refetch whatever caused it. Reading that as "no clash" would take a
 * *true* warning off the screen every time an unrelated seva changed anywhere
 * in the temple — and the screens clear a prompt when its clashes empty, so
 * that warning would not come back. A devotee losing a real warning is worse
 * than one seeing a gone seva for the length of one round trip, so the last
 * fetched answer stands until a newer one replaces it.
 *
 * `gcTime` 0 is the part that genuinely cannot be left to chance: a cached
 * answer must not outlive the screen that asked for it, so reopening a form
 * always asks again rather than trusting a minutes-old reading of somebody
 * else's day.
 */
export function useSevaClashLookup(requests: readonly ClashRequest[]) {
  const results = useQueries({
    queries: requests.map((request) => ({
      queryKey: clashQueryKey(request),
      queryFn: () => fetchSevaClashes(request),
      enabled: request.enabled !== false && Boolean(request.devoteeId),
      gcTime: 0,
      // A clash check that fails answers "nothing known", and nothing known
      // must never turn into a retry storm behind a form the devotee is using.
      retry: false,
    })),
  });

  const byKey = new Map<string, SevaClash[]>();
  requests.forEach((request, index) => {
    byKey.set(request.key, results[index]?.data ?? []);
  });
  return byKey;
}

/** One window. The same guarantees as `useSevaClashLookup`. */
export function useSevaClashes(request: SevaClashQuery | null, enabled = true) {
  const lookup = useSevaClashLookup(
    request ? [{ ...request, key: "only", enabled }] : [],
  );
  return lookup.get("only") ?? [];
}

/** A devotee a coordinator is about to ask, and the window they are asked for. */
export type ClashGateTarget = SevaClashQuery & { name: string };

/**
 * A clash check run because somebody tapped, for the lists where asking about
 * every devotee on screen up front would be dozens of questions about people
 * the coordinator was never going to pick.
 *
 * The gate warns and then gets out of the way: `proceed` is always available,
 * and an answer that never arrives — no permission to ask about this devotee,
 * 0069 not applied yet — sends the invitation rather than swallowing it.
 */
export function useClashGate(proceed: (target: ClashGateTarget) => void) {
  const [checking, setChecking] = useState<ClashGateTarget | null>(null);
  const [warning, setWarning] = useState<ClashGateTarget | null>(null);
  // The caller's callback is an inline arrow on every screen that uses this;
  // holding it in a ref keeps the effect below from re-running each render.
  const proceedRef = useRef(proceed);
  proceedRef.current = proceed;

  const target = checking ?? warning;
  const query = useQuery({
    queryKey: target
      ? clashQueryKey(target)
      : (["services", "clashes", "idle"] as const),
    queryFn: () => fetchSevaClashes(target!),
    enabled: Boolean(target),
    // For the same reason as useSevaClashLookup.
    gcTime: 0,
    retry: false,
  });
  const clashes = target ? (query.data ?? []) : [];

  useEffect(() => {
    if (!checking || query.isPending || query.isFetching) return;
    if (clashes.length) setWarning(checking);
    else proceedRef.current(checking);
    setChecking(null);
  }, [checking, clashes.length, query.isFetching, query.isPending]);

  // A warning outlives its clash by nothing: the seva it named being cancelled
  // or handed on takes the pop-up with it.
  useEffect(() => {
    if (warning && !checking && !query.isFetching && !clashes.length) {
      setWarning(null);
    }
  }, [checking, clashes.length, query.isFetching, warning]);

  return {
    /** True while a tap is waiting on an answer, for disabling the row. */
    checking: Boolean(checking),
    /** What the warning is about, or null when there is nothing to say. */
    warning: warning && clashes.length ? { target: warning, clashes } : null,
    ask: (next: ClashGateTarget) => setChecking(next),
    /** Do it anyway. The whole point: nothing here may refuse. */
    accept: () => {
      const settled = warning;
      setWarning(null);
      if (settled) proceedRef.current(settled);
    },
    dismiss: () => setWarning(null),
  };
}

/**
 * Seva that was taken out of the completed list because nobody served it.
 *
 * Reached only through `list_seva_closed_unserved`, which answers its poster,
 * the Tech Admin and the President and nobody else — an ordinary devotee gets
 * an empty list and the notice never appears for them.
 */
export function useClosedUnservedSeva(enabled = true) {
  return useQuery<ClosedUnservedSeva[]>({
    queryKey: ["services", "closed-unserved"] as const,
    queryFn: async () => groupClosedUnserved(await fetchClosedUnservedSeva()),
    enabled,
    staleTime: 5 * 60_000,
    retry: false,
  });
}

/** Members who may verify a devotee's logged seva. */
export function useSevaVerifiers(enabled = true) {
  return useQuery({
    queryKey: ["services", "seva-verifiers"] as const,
    queryFn: fetchSevaVerifiers,
    enabled,
    staleTime: 5 * 60_000,
  });
}

export function useRequestSevaVerification() {
  return useServiceMutation<RequestVerificationInput>(requestSevaVerification);
}

export function useLogCompletedSeva() {
  return useServiceMutation<LogCompletedSevaInput>(logCompletedSeva);
}

export function useResendSevaVerification() {
  return useServiceMutation<{ verificationId: string; verifierId: string }>(
    ({ verificationId, verifierId }) =>
      resendSevaVerification(verificationId, verifierId),
  );
}

export function useRespondToSevaVerification() {
  return useServiceMutation<{
    verificationId: string;
    approve: boolean;
    note: string | null;
  }>(({ verificationId, approve, note }) =>
    respondToSevaVerification(verificationId, approve, note),
  );
}

export function useProposeServiceOfferAlternative() {
  return useServiceMutation<{
    offerId: string;
    date: string;
    startTime: string;
    durationMinutes: number;
    note: string | null;
  }>(proposeServiceOfferAlternative);
}

export function useRespondToServiceOfferCounter() {
  return useServiceMutation<{
    counterId: string;
    accept: boolean;
    note: string | null;
  }>(({ counterId, accept, note }) =>
    respondToServiceOfferCounter(counterId, accept, note),
  );
}

/**
 * A mutation that shows its result before the server confirms it, then puts the
 * dashboard back if the server disagrees. Marking attendance and clearing a
 * waiting card both exist to make a row change or disappear, so waiting for a
 * round trip reads as the tap not having landed.
 */
function useOptimisticServiceMutation<TVariables>(
  mutationFn: (variables: TVariables) => Promise<unknown>,
  patch: (dashboard: ServiceDashboard, variables: TVariables) => ServiceDashboard,
) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn,
    onMutate: async (variables: TVariables) => {
      await queryClient.cancelQueries({ queryKey: serviceKeys.dashboards });
      const previous = queryClient.getQueriesData<ServiceDashboard>({
        queryKey: serviceKeys.dashboards,
      });
      queryClient.setQueriesData<ServiceDashboard>(
        { queryKey: serviceKeys.dashboards },
        (data) => (data ? patch(data, variables) : data),
      );
      return { previous };
    },
    onError: (_error, _variables, context) => {
      for (const [key, data] of context?.previous ?? []) {
        queryClient.setQueryData(key, data);
      }
    },
    onSettled: () =>
      queryClient.invalidateQueries({
        queryKey: serviceKeys.all,
        refetchType: "active",
      }),
  });
}

/**
 * One devotee's answer on one seva. Nobody else's place is touched.
 *
 * Exported for tests. This is the shape the tab shows before the server has
 * agreed to anything, so if it disagrees with what `record_seva_attendance`
 * stores the temple is reading a lie until the next refetch.
 */
export function setAttendanceInDashboard(
  dashboard: ServiceDashboard,
  { assignmentId, attendance }: RecordAttendanceInput,
): ServiceDashboard {
  const answer = (assignment: ServiceAssignmentRow): ServiceAssignmentRow =>
    assignment.id === assignmentId ? { ...assignment, attendance } : assignment;

  return {
    ...dashboard,
    services: dashboard.services.map((service): ServiceListItem => {
      if (
        !service.participants.some(
          (participant) => participant.assignment.id === assignmentId,
        )
      ) {
        return service;
      }
      return {
        ...service,
        participants: service.participants.map((participant) => ({
          ...participant,
          assignment: answer(participant.assignment),
        })),
        currentUserAssignment: service.currentUserAssignment
          ? answer(service.currentUserAssignment)
          : null,
      };
    }),
  };
}

type RecordAttendanceInput = {
  assignmentId: string;
  attendance: "served" | "absent" | "excused" | null;
};

/**
 * Optimistic on purpose, and per place. A coordinator standing in the kitchen
 * marks four devotees in a row; each tap has to settle instantly and leave the
 * other three alone. Answering the last unmarked place also satisfies
 * `isSevaConfirmedServed`, so the seva leaves "Waiting to be verified" for
 * "Recently completed" on the same tap rather than after a refetch.
 */
export function useRecordSevaAttendance() {
  return useOptimisticServiceMutation<RecordAttendanceInput>(
    ({ assignmentId, attendance }) =>
      recordSevaAttendance(assignmentId, attendance),
    setAttendanceInDashboard,
  );
}

/**
 * Everyone nobody has answered for served, and the seva itself is closed.
 *
 * Exported for tests, and for the same reason: the rows this patches have to be
 * exactly the rows `useMarkSevaServed` sends to the server.
 */
export function markServedInDashboard(
  dashboard: ServiceDashboard,
  instanceId: string,
): ServiceDashboard {
  const answer = (assignment: ServiceAssignmentRow): ServiceAssignmentRow =>
    assignment.attendance ||
    assignment.status === "no_show" ||
    assignment.status === "withdrawn"
      ? assignment
      : { ...assignment, attendance: "served", status: "completed" };

  return {
    ...dashboard,
    services: dashboard.services.map((service): ServiceListItem =>
      service.id === instanceId
        ? {
            ...service,
            status: "completed",
            participants: service.participants.map((participant) => ({
              ...participant,
              assignment: answer(participant.assignment),
            })),
            currentUserAssignment: service.currentUserAssignment
              ? answer(service.currentUserAssignment)
              : null,
          }
        : service,
    ),
  };
}

/**
 * "Mark served", from the waiting list. Says that everyone whose place nobody
 * had answered for did serve, and closes the seva off if that had not happened
 * either — one tap has to be enough to clear the card, or the temple is left
 * with a queue that takes two screens to empty.
 *
 * Optimistic on purpose: the whole point of the list is that answering removes
 * the row, so the dashboard is patched first and put back if the server says
 * no.
 */
export function useMarkSevaServed() {
  return useOptimisticServiceMutation<ServiceListItem>(
    async (service) => {
      for (const assignmentId of unconfirmedAssignmentIds(service)) {
        await recordSevaAttendance(assignmentId, "served");
      }
      if (service.status !== "completed") await completeService(service.id);
    },
    (dashboard, service) => markServedInDashboard(dashboard, service.id),
  );
}

export function useUpdateServiceRequirement() {
  return useServiceMutation<{
    instanceId: string;
    participationMode: "open" | "invite_only";
    slotsNeeded: number;
    inviteeIds: string[];
  }>(updateServiceRequirement);
}

export function useProposeWeeklyOfferAlternative() {
  return useServiceMutation<ProposeAlternativeInput>(
    proposeWeeklyOfferAlternative,
  );
}

export function useRespondToWeeklyOfferCounter() {
  return useServiceMutation<{
    counterId: string;
    approve: boolean;
    note: string | null;
  }>(({ counterId, approve, note }) =>
    respondToWeeklyOfferCounter(counterId, approve, note),
  );
}

export function useDeleteSevaRegistration() {
  return useServiceMutation<string>(deleteSevaRegistration);
}
